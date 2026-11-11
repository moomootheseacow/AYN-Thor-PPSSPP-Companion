// Thor Companion engine (M5 step 3, drawing API extended in step 4a): package loader, Lua runtime, Lua API.
// See CompanionEngine.h, and docs/PACKAGES.md for the full API.
//
// Lua API for packages (all coordinates in logical units: the screen is 540 wide, ui.height tall):
//   game.id, game.title                    running game (strings, refreshed every frame)
//   ui.width, ui.height                    screen size
//   ui.clear(color)                        background colour (0xRRGGBB)
//   ui.rect(x, y, w, h, color [, alpha])
//   ui.frame(x, y, w, h, thickness, color [, alpha])
//   ui.text(x, y, str, size, color [, align [, alpha]]) -> width   align: "left" (default), "center", "right"
//   ui.text_width(str, size) -> width
//   ui.button(id, x, y, w, h) -> pressed   touch area; on release inside it the engine calls on_press(id)
//   ui.stats(right_x, y, size, color)      engine stats line (redraws, Lua time, Lua memory)
//   ui.gradient / image / image_size / poly / line / circle / ring / arc / pie / radial / clip  (step 4a)
//   mem.u8/u16/u32/s8/s16/s32/f32(addr)    guest memory reads, nil when the address isn't valid
//   mem.ptr(addr)                          u32 at addr if it points into PSP RAM, else nil
//   mem.str(addr, max)                     zero-terminated string
//   mem.w8/w16/w32(addr, value) -> ok      guest memory writes (selector-type writes only; inventory writes
//                                          must go through a save backup first, M5 decision 10)
//   log(...)                               logcat, tag ThorCompanion, and the in-app log (step 4d-3)
//   logs.lines(), logs.clear(), logs.stats() the in-app log: last 300 log() lines and engine errors
//   ui.copy(text)                          puts text on the Android clipboard
//   ui.request(name)                       7n: asks the app for "minimize", "restore" or "overlay_settings"
//   ui.transform(k, dx, dy) / ui.transform()  7p: scale + move what's drawn after it (and button areas), per frame
//   ui.remap({[from] = to}) / ui.remap()     7p: colour swaps for everything drawn after it, per frame
//   ui.font("game" | "plain")              7p: ui.text / text_width with the game's letters (hud/font_text.png)
//   pad.press(name, delay, hold) -> ok    press a PSP button on the emulator thread (7f); pad.busy()
//   include(file)                          run another Lua file from the same package, returns its results
// Package callbacks (globals): frame() [required], on_load(), on_press(id), on_touch(action, x, y).

#include "Companion/CompanionEngine.h"
#include "Companion/CompanionDraw.h"
#include "Companion/CompanionFont.h"
#include "Companion/CompanionEmu.h"

#include <android/log.h>

#include <algorithm>
#include <cctype>
#include <chrono>
#include <cstdarg>
#include <ctime>
#include <deque>
#include <cstdlib>
#include <map>
#include <memory>
#include <cmath>
#include <cstring>
#include <mutex>
#include <string>
#include <vector>

#include "Common/Data/Format/PNGLoad.h"
#include "Common/File/FileUtil.h"
#include "Common/File/Path.h"
#include "Common/File/VFS/VFS.h"
#include "Core/System.h"
#include "Core/Util/PathUtil.h"
#include "Core/MemMap.h"
#include "Core/ELF/ParamSFO.h"

#include "ext/lua/lua.hpp"

#define CLOG(...) __android_log_print(ANDROID_LOG_INFO, "ThorCompanion", __VA_ARGS__)
#define CLOGE(...) LogErrorF(__VA_ARGS__)   // logcat + the in-app log

namespace Companion {

static const char *kPackageRoot = "companion";

// ---------------------------------------------------------------- in-app log (main thread only)
// The last kLogMax lines from log() and the engine's errors, with the clock time, for the Logs screen.

struct LogLine {
	std::string time, text;
	bool err;
};
static const size_t kLogMax = 300;
static std::deque<LogLine> g_log;

static void AddLog(bool err, const std::string &text) {
	char t[16] = "--:--:--";
	time_t now = time(nullptr);
	struct tm tmv;
	if (localtime_r(&now, &tmv)) strftime(t, sizeof(t), "%H:%M:%S", &tmv);
	g_log.push_back({ t, text, err });
	while (g_log.size() > kLogMax) g_log.pop_front();
}

__attribute__((format(printf, 1, 2)))
static void LogErrorF(const char *fmt, ...) {
	char buf[1024];
	va_list ap;
	va_start(ap, fmt);
	vsnprintf(buf, sizeof(buf), fmt, ap);
	va_end(ap);
	__android_log_print(ANDROID_LOG_ERROR, "ThorCompanion", "%s", buf);
	AddLog(true, buf);
}

// ui.copy: text waiting for the Java side to put it on the clipboard (TakeClipboard)
static std::string g_clipboard;
static bool g_hasClipboard = false;

bool TakeClipboard(std::string *out) {
	if (!g_hasClipboard) return false;
	*out = std::move(g_clipboard);
	g_clipboard.clear();
	g_hasClipboard = false;
	return true;
}

// 7n: ui.request(name): asks the Java side for something only it can do ("minimize", "restore",
// "overlay_settings"). Queued here, taken by Java (TakeRequest) right after the callback that asked.
static std::deque<std::string> g_requests;

bool TakeRequest(std::string *out) {
	if (g_requests.empty()) return false;
	*out = std::move(g_requests.front());
	g_requests.pop_front();
	return true;
}

void JavaLog(const std::string &text) {
	__android_log_print(ANDROID_LOG_INFO, "ThorCompanion", "%s", text.c_str());
	AddLog(false, text);
}
static const int kScriptBudgetMs = 100;   // a frame() taking longer than this is stopped

// ---------------------------------------------------------------- shared with the renderer

static std::mutex g_lock;
static DrawList g_published;
static EngineStats g_stats;
static float g_logicalHeight = 470.0f;

void CopyDrawList(DrawList *out, EngineStats *stats) {
	std::lock_guard<std::mutex> guard(g_lock);
	*out = g_published;
	*stats = g_stats;
}

float LogicalHeight() {
	std::lock_guard<std::mutex> guard(g_lock);
	return g_logicalHeight;
}

void SetLogicalHeight(float h) {
	std::lock_guard<std::mutex> guard(g_lock);
	g_logicalHeight = h;
}

float TextWidth(const std::string &s, float size) {
	float k = size / kFontCellH, w = 0;
	for (unsigned char c : s) w += (c >= 32 && c < 127 ? kFontAdvance[c - 32] : kFontAdvance[0]) * k;
	return w;
}

// ---------------------------------------------------------------- packages

struct Package {
	std::string dir;    // "companion/mhfu"
	std::string name;
	std::string main;   // "main.lua"
	std::vector<std::string> ids;
};

static std::vector<Package> g_packages;
static bool g_scanned = false;

static bool ReadAsset(const std::string &path, std::string *out) {
	size_t size = 0;
	uint8_t *data = g_VFS.ReadFile(path.c_str(), &size);
	if (!data) return false;
	out->assign((const char *)data, size);
	delete[] data;
	return true;
}

static void OpenSafeLibs(lua_State *L) {
	// No io / os / package / debug: packages can only touch the game through the API below.
	static const luaL_Reg libs[] = {
		{ LUA_GNAME, luaopen_base }, { LUA_TABLIBNAME, luaopen_table }, { LUA_STRLIBNAME, luaopen_string },
		{ LUA_MATHLIBNAME, luaopen_math }, { LUA_UTF8LIBNAME, luaopen_utf8 }, { nullptr, nullptr },
	};
	for (const luaL_Reg *l = libs; l->func; l++) {
		luaL_requiref(L, l->name, l->func, 1);
		lua_pop(L, 1);
	}
	for (const char *name : { "dofile", "loadfile", "load", "require" }) {
		lua_pushnil(L);
		lua_setglobal(L, name);
	}
}

static void ScanPackages() {
	if (g_scanned) return;
	g_scanned = true;
	std::vector<File::FileInfo> listing;
	if (!g_VFS.GetFileListing(kPackageRoot, &listing, nullptr)) {
		CLOGE("No packages folder (assets/%s)", kPackageRoot);
		return;
	}
	for (const File::FileInfo &info : listing) {
		if (!info.isDirectory) continue;
		Package pkg;
		pkg.dir = std::string(kPackageRoot) + "/" + info.name;
		std::string src;
		if (!ReadAsset(pkg.dir + "/manifest.lua", &src)) {
			CLOGE("Package %s has no manifest.lua", info.name.c_str());
			continue;
		}
		lua_State *L = luaL_newstate();
		OpenSafeLibs(L);
		std::string chunk = "@" + pkg.dir + "/manifest.lua";
		if (luaL_loadbufferx(L, src.data(), src.size(), chunk.c_str(), "t") != LUA_OK || lua_pcall(L, 0, 1, 0) != LUA_OK) {
			CLOGE("Package %s: %s", info.name.c_str(), lua_tostring(L, -1));
			lua_close(L);
			continue;
		}
		if (lua_istable(L, -1)) {
			if (lua_getfield(L, -1, "name") == LUA_TSTRING) pkg.name = lua_tostring(L, -1);
			lua_pop(L, 1);
			pkg.main = lua_getfield(L, -1, "main") == LUA_TSTRING ? lua_tostring(L, -1) : "main.lua";
			lua_pop(L, 1);
			if (lua_getfield(L, -1, "ids") == LUA_TTABLE) {
				lua_Integer n = luaL_len(L, -1);
				for (lua_Integer i = 1; i <= n; i++) {
					if (lua_geti(L, -1, i) == LUA_TSTRING) pkg.ids.push_back(lua_tostring(L, -1));
					lua_pop(L, 1);
				}
			}
			lua_pop(L, 1);
		}
		lua_close(L);
		if (pkg.ids.empty()) {
			CLOGE("Package %s lists no game IDs", info.name.c_str());
			continue;
		}
		if (pkg.name.empty()) pkg.name = info.name;
		std::string ids;
		for (const std::string &id : pkg.ids) ids += (ids.empty() ? "" : " ") + id;
		CLOG("Package %s: %s [%s]", pkg.dir.c_str(), pkg.name.c_str(), ids.c_str());
		g_packages.push_back(pkg);
	}
	CLOG("%d package(s) found", (int)g_packages.size());
}

static const Package *FindPackage(const std::string &id) {
	ScanPackages();
	for (const Package &p : g_packages)
		for (const std::string &pid : p.ids)
			if (pid == id) return &p;
	return nullptr;
}

// ---------------------------------------------------------------- running package state (main thread only)

struct Region {
	std::string id;
	float x, y, w, h;
};

static lua_State *g_L = nullptr;
static const Package *g_pkg = nullptr;
static std::string g_runningId;        // game ID the current state was chosen for
static std::string g_loadError;        // package failed to load: shown until the game changes
static std::string g_frameError;       // last frame() error, cleared when frame() works again
static std::string g_lastLoggedError;
static DrawList g_build;               // list being built by frame()
static std::vector<Region> g_regions, g_buildRegions;
static std::string g_downId, g_pressedId;  // button the finger went down on / is currently over
static std::chrono::steady_clock::time_point g_deadline;
static bool g_budgetHit = false;          // a script ran too long: the package is stopped until the game changes
static std::chrono::steady_clock::time_point g_loadTime = std::chrono::steady_clock::now();   // ui.time = seconds since this

// 7p: per-frame drawing state set by the package (reset before every frame()):
//   ui.transform(k, dx, dy) scales and moves everything drawn after it (and the button areas): x' = x * k + dx.
//   ui.remap({[from] = to, ...}) swaps colours (fills, text, image tints) as they are drawn.
//   ui.font("game") draws ui.text with the game's own letters (hud/font_text.png), "plain" with the built-in font.
static bool g_tOn = false;
static float g_tk = 1, g_tx = 0, g_ty = 0;
static std::vector<std::pair<uint32_t, uint32_t>> g_remap;
static bool g_gameFont = false;

static void ResetDrawState() {
	g_tOn = false; g_tk = 1; g_tx = 0; g_ty = 0;
	g_remap.clear();
	g_gameFont = false;
}

static uint32_t Remap(uint32_t c) {
	for (const auto &r : g_remap) if (r.first == c) return r.second;
	return c;
}

static void Push(Cmd &&c) {
	if (!g_remap.empty()) { c.c[0] = Remap(c.c[0]); c.c[1] = Remap(c.c[1]); }
	if (g_tOn) {
		const float k = g_tk;
		auto pt = [&](float &x, float &y) { x = x * k + g_tx; y = y * k + g_ty; };
		switch (c.type) {
		case CMD_RECT: case CMD_GRADIENT:
			pt(c.f[0], c.f[1]); c.f[2] *= k; c.f[3] *= k; break;
		case CMD_CLIP:
			if (!(c.flags & 1)) { pt(c.f[0], c.f[1]); c.f[2] *= k; c.f[3] *= k; }
			break;
		case CMD_IMAGE:
			pt(c.f[0], c.f[1]); c.f[2] *= k; c.f[3] *= k; c.f[9] *= k; c.f[10] *= k; break;
		case CMD_TEXT: case CMD_STATS:
			pt(c.f[0], c.f[1]); c.f[2] *= k; break;
		case CMD_POLY:
			for (size_t i = 0; i + 1 < c.pts.size(); i += 2) pt(c.pts[i], c.pts[i + 1]);
			break;
		case CMD_ARC:
			pt(c.f[0], c.f[1]); c.f[2] *= k; c.f[3] *= k; break;
		case CMD_RADIAL:
			pt(c.f[0], c.f[1]); c.f[2] *= k; c.f[3] *= k; break;
		case CMD_VIGNETTE:
			pt(c.f[0], c.f[1]); c.f[2] *= k; c.f[3] *= k; break;   // f[4] is a fraction of rx
		}
	}
	g_build.cmds.push_back(std::move(c));
}

static void AddRect(float x, float y, float w, float h, uint32_t color, float alpha = 1.0f) {
	if (w <= 0 || h <= 0) return;
	Cmd c;
	c.type = CMD_RECT;
	c.f[0] = x; c.f[1] = y; c.f[2] = w; c.f[3] = h; c.c[0] = color; c.a[0] = alpha;
	Push(std::move(c));
}

static void AddText(float x, float y, const std::string &s, float size, uint32_t color, float alpha = 1.0f) {
	if (s.empty()) return;
	Cmd c;
	c.type = CMD_TEXT;
	c.f[0] = x; c.f[1] = y; c.f[2] = size; c.c[0] = color; c.a[0] = alpha; c.text = s;
	Push(std::move(c));
}

// ---- package images (decoded on the main thread, uploaded by the GL thread on first use)

static std::map<std::string, std::shared_ptr<Image>> g_imageByPath;   // main thread
static std::map<int, std::shared_ptr<Image>> g_imageById;             // under g_lock (renderer reads it)
static int g_nextImageId = 1;

std::shared_ptr<const Image> GetImage(int id) {
	std::lock_guard<std::mutex> guard(g_lock);
	auto it = g_imageById.find(id);
	return it == g_imageById.end() ? nullptr : it->second;
}

// Returns nullptr if the file is missing or not a PNG (logged once per path).
static std::shared_ptr<Image> LoadImage(const std::string &file) {
	auto it = g_imageByPath.find(file);
	if (it != g_imageByPath.end()) return it->second;
	std::shared_ptr<Image> img;
	auto t0 = std::chrono::steady_clock::now();
	std::string path = (g_pkg ? g_pkg->dir : std::string()) + "/" + file, data;
	if (file.find("..") == std::string::npos && ReadAsset(path, &data)) {
		int w = 0, h = 0;
		unsigned char *px = nullptr;
		if (pngLoadPtr((const unsigned char *)data.data(), data.size(), &w, &h, &px) && px && w > 0 && h > 0) {
			img = std::make_shared<Image>();
			img->id = g_nextImageId++;
			img->w = w;
			img->h = h;
			img->path = path;
			img->rgba.assign(px, px + (size_t)w * h * 4);
			std::lock_guard<std::mutex> guard(g_lock);
			g_imageById[img->id] = img;
		}
		if (px) free(px);
	}
	if (img) CLOG("Image %s: %d x %d", path.c_str(), img->w, img->h);
	else CLOGE("Image %s: not found or not a PNG", path.c_str());
	g_imageByPath[file] = img;   // remember failures too, so they're logged once
	g_deadline += std::chrono::steady_clock::now() - t0;   // decoding doesn't count against the script's time budget
	return img;
}

static std::shared_ptr<Image> g_fontImg;   // 7p: hud/font_text.png for ui.font("game")
static void ClearImages() {
	g_fontImg.reset();
	g_imageByPath.clear();
	std::lock_guard<std::mutex> guard(g_lock);
	g_imageById.clear();
}

// ---- Lua: ui

static float Num(lua_State *L, int i) { return (float)luaL_checknumber(L, i); }
static uint32_t ColorArg(lua_State *L, int i) { return (uint32_t)(luaL_checkinteger(L, i) & 0xFFFFFF); }
static float AlphaArg(lua_State *L, int i) { return (float)luaL_optnumber(L, i, 1.0); }

// Reads t[key] as a number (default when missing).
static float OptField(lua_State *L, int t, const char *key, float def) {
	if (t == 0) return def;
	lua_getfield(L, t, key);
	float v = lua_isnumber(L, -1) ? (float)lua_tonumber(L, -1) : def;
	lua_pop(L, 1);
	return v;
}

static int ui_clear(lua_State *L) { g_build.clear = Remap(ColorArg(L, 1)); return 0; }

static int ui_rect(lua_State *L) {
	AddRect(Num(L, 1), Num(L, 2), Num(L, 3), Num(L, 4), ColorArg(L, 5), AlphaArg(L, 6));
	return 0;
}

static int ui_frame(lua_State *L) {
	float x = Num(L, 1), y = Num(L, 2), w = Num(L, 3), h = Num(L, 4), t = Num(L, 5);
	uint32_t color = ColorArg(L, 6);
	float a = AlphaArg(L, 7);
	AddRect(x, y, w, t, color, a);
	AddRect(x, y + h - t, w, t, color, a);
	AddRect(x, y + t, t, h - 2 * t, color, a);
	AddRect(x + w - t, y + t, t, h - 2 * t, color, a);
	return 0;
}

// ui.gradient(x, y, w, h, color_from, color_to [, "v" | "h" [, alpha_from, alpha_to]])
static int ui_gradient(lua_State *L) {
	Cmd c;
	c.type = CMD_GRADIENT;
	for (int i = 0; i < 4; i++) c.f[i] = Num(L, i + 1);
	c.c[0] = ColorArg(L, 5);
	c.c[1] = ColorArg(L, 6);
	c.flags = !strcmp(luaL_optstring(L, 7, "v"), "h") ? 1 : 0;
	c.a[0] = AlphaArg(L, 8);
	c.a[1] = AlphaArg(L, 9);
	if (c.f[2] > 0 && c.f[3] > 0) Push(std::move(c));
	return 0;
}

// ---- 7p: the game's font (hud/font_text.png: 74 cells of 20 x 22 px). At size 19 a letter advances 13.2, a space 9,
// ':' and the middle dot 8 (drawn as square pixel dots with a black edge). Other characters advance like a space.
static const char kGameChars[] = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789.,'-/+?%[]()";
static int g_gameIndex[128];
static bool g_gameIndexReady = false;

static int GameGlyph(unsigned c) {
	if (!g_gameIndexReady) {
		for (int &i : g_gameIndex) i = -1;
		for (int i = 0; kGameChars[i]; i++) g_gameIndex[(unsigned char)kGameChars[i]] = i;
		g_gameIndexReady = true;
	}
	return c < 128 ? g_gameIndex[c] : -1;
}

// Splits UTF-8 into code points the game font knows: letters, ':' / middle dot (0xB7), 'x' for the times sign.
template <typename F>
static void ForGameChars(const std::string &s, F fn) {
	for (size_t i = 0; i < s.size();) {
		unsigned char c = s[i];
		unsigned cp = c;
		size_t n = 1;
		if (c >= 0xC0) {
			n = c >= 0xF0 ? 4 : c >= 0xE0 ? 3 : 2;
			cp = (c & (0x3F >> (n - 1)));
			for (size_t j = 1; j < n && i + j < s.size(); j++) cp = (cp << 6) | ((unsigned char)s[i + j] & 0x3F);
		}
		if (cp == 0xD7) cp = 'x';
		fn(cp);
		i += n;
	}
}

static float GameAdvance(unsigned cp) {
	if (GameGlyph(cp) >= 0) return 13.2f;
	if (cp == ':' || cp == 0xB7) return 8.0f;
	return 9.0f;
}

static float GameTextWidth(const std::string &s, float size) {
	float w = 0;
	ForGameChars(s, [&](unsigned cp) { w += GameAdvance(cp); });
	return w * size / 19.0f;
}

static float FontTextWidth(const std::string &s, float size) {
	return g_gameFont ? GameTextWidth(s, size) : TextWidth(s, size);
}


static void AddGameText(float x, float y, const std::string &s, float size, uint32_t color, float alpha) {
	if (!g_fontImg) g_fontImg = LoadImage("hud/font_text.png");
	if (!g_fontImg) { AddText(x, y, s, size, color, alpha); return; }
	const float k = size / 19.0f, yy = y - 3 * k;
	float cx = x;
	ForGameChars(s, [&](unsigned cp) {
		int gi = GameGlyph(cp);
		if (gi >= 0) {
			Cmd c;
			c.type = CMD_IMAGE;
			c.image = g_fontImg->id; c.iw = g_fontImg->w; c.ih = g_fontImg->h;
			c.f[0] = cx - 2.5f * k; c.f[1] = yy; c.f[2] = 20 * k; c.f[3] = 22 * k;
			c.f[4] = (float)(gi * 20); c.f[5] = 0; c.f[6] = 20; c.f[7] = 22;
			c.f[9] = c.f[2] / 2; c.f[10] = c.f[3] / 2;
			c.c[0] = color; c.a[0] = alpha; c.flags = 1;
			Push(std::move(c));
		} else if (cp == ':' || cp == 0xB7) {
			const float d = 3 * k;
			const float dots[2] = { cp == ':' ? yy + 7 * k : yy + 11 * k, yy + 15 * k };
			const int n = cp == ':' ? 2 : 1;
			for (int i = 0; i < n; i++) AddRect(cx + 1.2f * k - k, dots[i] - k, d + 2 * k, d + 2 * k, 0x000000, alpha);
			for (int i = 0; i < n; i++) AddRect(cx + 1.2f * k, dots[i], d, d, color, alpha);
		}
		cx += GameAdvance(cp) * k;
	});
}

static int ui_text(lua_State *L) {
	float x = Num(L, 1), y = Num(L, 2);
	std::string s = luaL_tolstring(L, 3, nullptr);
	lua_pop(L, 1);
	float size = Num(L, 4);
	uint32_t color = ColorArg(L, 5);
	const char *align = luaL_optstring(L, 6, "left");
	float alpha = AlphaArg(L, 7);
	float w = FontTextWidth(s, size);
	if (!strcmp(align, "center")) x -= w / 2;
	else if (!strcmp(align, "right")) x -= w;
	if (g_gameFont) AddGameText(x, y, s, size, color, alpha);
	else AddText(x, y, s, size, color, alpha);
	lua_pushnumber(L, w);
	return 1;
}

static int ui_text_width(lua_State *L) {
	std::string s = luaL_tolstring(L, 1, nullptr);
	lua_pop(L, 1);
	lua_pushnumber(L, FontTextWidth(s, Num(L, 2)));
	return 1;
}

// ui.transform(k, dx, dy), or ui.transform() to turn it off
static int ui_transform(lua_State *L) {
	if (lua_gettop(L) == 0 || lua_isnil(L, 1)) { g_tOn = false; g_tk = 1; g_tx = 0; g_ty = 0; return 0; }
	g_tk = Num(L, 1); g_tx = (float)luaL_optnumber(L, 2, 0); g_ty = (float)luaL_optnumber(L, 3, 0);
	g_tOn = !(g_tk == 1 && g_tx == 0 && g_ty == 0);
	return 0;
}

// ui.remap({[0x121A24] = 0x1A1E1A, ...}), or ui.remap() to turn it off
static int ui_remap(lua_State *L) {
	g_remap.clear();
	if (!lua_istable(L, 1)) return 0;
	lua_pushnil(L);
	while (lua_next(L, 1)) {
		if (lua_isinteger(L, -2) && lua_isinteger(L, -1))
			g_remap.emplace_back((uint32_t)(lua_tointeger(L, -2) & 0xFFFFFF), (uint32_t)(lua_tointeger(L, -1) & 0xFFFFFF));
		lua_pop(L, 1);
	}
	return 0;
}

// ui.font("game" | "plain")
static int ui_font(lua_State *L) {
	g_gameFont = !strcmp(luaL_optstring(L, 1, "plain"), "game");
	return 0;
}

static int ui_button(lua_State *L) {
	std::string id = luaL_tolstring(L, 1, nullptr);
	lua_pop(L, 1);
	Region r{ id, Num(L, 2), Num(L, 3), Num(L, 4), Num(L, 5) };
	if (g_tOn) { r.x = r.x * g_tk + g_tx; r.y = r.y * g_tk + g_ty; r.w *= g_tk; r.h *= g_tk; }
	g_buildRegions.push_back(r);
	lua_pushboolean(L, !g_pressedId.empty() && g_pressedId == id);
	return 1;
}

static int ui_stats(lua_State *L) {
	Cmd c;
	c.type = CMD_STATS;
	c.f[0] = Num(L, 1); c.f[1] = Num(L, 2); c.f[2] = Num(L, 3); c.c[0] = ColorArg(L, 4);
	Push(std::move(c));
	return 0;
}

// ui.image(file, x, y [, w, h [, opts]])  opts: sx sy sw sh (source rect, pixels), rot (degrees clockwise),
// ox oy (pivot relative to x, y; default the centre), tint (0xRRGGBB, multiplies), alpha, pixel (nearest
// filtering), flip ("x", "y", "xy"), silhouette (draw only the shape, in the tint colour: outlines, glows),
// grey (greyscale).
static int ui_image(lua_State *L) {
	std::string file = luaL_checkstring(L, 1);
	float x = Num(L, 2), y = Num(L, 3);
	std::shared_ptr<Image> img = LoadImage(file);
	int opts = lua_istable(L, 6) ? 6 : 0;
	float sx = OptField(L, opts, "sx", 0), sy = OptField(L, opts, "sy", 0);
	float sw = OptField(L, opts, "sw", img ? img->w - sx : 16), sh = OptField(L, opts, "sh", img ? img->h - sy : 16);
	float w = (float)luaL_optnumber(L, 4, sw), h = (float)luaL_optnumber(L, 5, sh);
	if (!img) {   // missing image: magenta box, so it's obvious on screen
		AddRect(x, y, w, h, 0xFF00FF, 0.6f);
		return 0;
	}
	Cmd c;
	c.type = CMD_IMAGE;
	c.image = img->id; c.iw = img->w; c.ih = img->h;
	c.f[0] = x; c.f[1] = y; c.f[2] = w; c.f[3] = h;
	c.f[4] = sx; c.f[5] = sy; c.f[6] = sw; c.f[7] = sh;
	c.f[8] = OptField(L, opts, "rot", 0);
	c.f[9] = OptField(L, opts, "ox", w / 2);
	c.f[10] = OptField(L, opts, "oy", h / 2);
	c.c[0] = 0xFFFFFF;
	c.a[0] = OptField(L, opts, "alpha", 1.0f);
	if (opts) {
		lua_getfield(L, opts, "tint");
		if (lua_isinteger(L, -1)) c.c[0] = (uint32_t)(lua_tointeger(L, -1) & 0xFFFFFF);
		lua_pop(L, 1);
		lua_getfield(L, opts, "pixel");
		if (lua_toboolean(L, -1)) c.flags |= 1;
		lua_pop(L, 1);
		lua_getfield(L, opts, "silhouette");
		if (lua_toboolean(L, -1)) c.flags |= 8;
		lua_pop(L, 1);
		lua_getfield(L, opts, "grey");
		if (lua_toboolean(L, -1)) c.flags |= 16;
		lua_pop(L, 1);
		lua_getfield(L, opts, "flip");
		if (lua_isstring(L, -1)) {
			const char *fl = lua_tostring(L, -1);
			if (strchr(fl, 'x')) c.flags |= 2;
			if (strchr(fl, 'y')) c.flags |= 4;
		}
		lua_pop(L, 1);
	}
	if (w != 0 && h != 0) Push(std::move(c));
	return 0;
}

// ui.image_size(file) -> w, h (pixels), or nil
static int ui_image_size(lua_State *L) {
	std::shared_ptr<Image> img = LoadImage(luaL_checkstring(L, 1));
	if (!img) { lua_pushnil(L); return 1; }
	lua_pushinteger(L, img->w);
	lua_pushinteger(L, img->h);
	return 2;
}

// ui.poly({x1, y1, x2, y2, ...}, color [, alpha])  convex polygon
static int ui_poly(lua_State *L) {
	luaL_checktype(L, 1, LUA_TTABLE);
	Cmd c;
	c.type = CMD_POLY;
	lua_Integer n = luaL_len(L, 1);
	for (lua_Integer i = 1; i <= n; i++) {
		lua_geti(L, 1, i);
		c.pts.push_back((float)lua_tonumber(L, -1));
		lua_pop(L, 1);
	}
	c.c[0] = ColorArg(L, 2);
	c.a[0] = AlphaArg(L, 3);
	if (c.pts.size() >= 6) Push(std::move(c));
	return 0;
}

// ui.line(x1, y1, x2, y2, width, color [, alpha])
static int ui_line(lua_State *L) {
	float x1 = Num(L, 1), y1 = Num(L, 2), x2 = Num(L, 3), y2 = Num(L, 4), w = Num(L, 5);
	float dx = x2 - x1, dy = y2 - y1, len = std::sqrt(dx * dx + dy * dy);
	if (len <= 0 || w <= 0) return 0;
	float nx = -dy / len * w / 2, ny = dx / len * w / 2;
	Cmd c;
	c.type = CMD_POLY;
	c.pts = { x1 + nx, y1 + ny, x2 + nx, y2 + ny, x2 - nx, y2 - ny, x1 - nx, y1 - ny };
	c.c[0] = ColorArg(L, 6);
	c.a[0] = AlphaArg(L, 7);
	Push(std::move(c));
	return 0;
}

static void AddArc(float cx, float cy, float r, float t, float from, float to, uint32_t color, float alpha) {
	Cmd c;
	c.type = CMD_ARC;
	c.f[0] = cx; c.f[1] = cy; c.f[2] = r; c.f[3] = t; c.f[4] = from; c.f[5] = to;
	c.c[0] = color; c.a[0] = alpha;
	Push(std::move(c));
}

// Angles: degrees, 0 = 12 o'clock, clockwise. r is the outer radius.
static int ui_circle(lua_State *L) {   // ui.circle(cx, cy, r, color [, alpha])
	AddArc(Num(L, 1), Num(L, 2), Num(L, 3), 0, 0, 360, ColorArg(L, 4), AlphaArg(L, 5));
	return 0;
}
static int ui_ring(lua_State *L) {     // ui.ring(cx, cy, r, thickness, color [, alpha])
	AddArc(Num(L, 1), Num(L, 2), Num(L, 3), Num(L, 4), 0, 360, ColorArg(L, 5), AlphaArg(L, 6));
	return 0;
}
static int ui_arc(lua_State *L) {      // ui.arc(cx, cy, r, thickness, from, to, color [, alpha])
	AddArc(Num(L, 1), Num(L, 2), Num(L, 3), Num(L, 4), Num(L, 5), Num(L, 6), ColorArg(L, 7), AlphaArg(L, 8));
	return 0;
}
static int ui_pie(lua_State *L) {      // ui.pie(cx, cy, r, from, to, color [, alpha])
	AddArc(Num(L, 1), Num(L, 2), Num(L, 3), 0, Num(L, 4), Num(L, 5), ColorArg(L, 6), AlphaArg(L, 7));
	return 0;
}

// ui.radial(cx, cy, rx, ry, color_centre, color_rim [, alpha_centre, alpha_rim])
static int ui_radial(lua_State *L) {
	Cmd c;
	c.type = CMD_RADIAL;
	for (int i = 0; i < 4; i++) c.f[i] = Num(L, i + 1);
	c.c[0] = ColorArg(L, 5);
	c.c[1] = ColorArg(L, 6);
	c.a[0] = AlphaArg(L, 7);
	c.a[1] = (float)luaL_optnumber(L, 8, 0.0);
	Push(std::move(c));
	return 0;
}

// ui.vignette(cx, cy, rx, ry, inner, color [, alpha]): paints everything outside a soft ellipse (fully clear up to
// inner x radius, fading in to the rim). Use with ui.clip to keep it inside a box (fog of war, spotlights).
static int ui_vignette(lua_State *L) {
	Cmd c;
	c.type = CMD_VIGNETTE;
	for (int i = 0; i < 5; i++) c.f[i] = Num(L, i + 1);
	c.c[0] = ColorArg(L, 6);
	c.a[0] = AlphaArg(L, 7);
	Push(std::move(c));
	return 0;
}

// ui.clip(x, y, w, h) clips everything drawn after it to that rectangle; ui.clip() turns clipping off.
static int ui_clip(lua_State *L) {
	Cmd c;
	c.type = CMD_CLIP;
	if (lua_gettop(L) == 0) {
		c.flags = 1;
	} else {
		for (int i = 0; i < 4; i++) c.f[i] = Num(L, i + 1);
	}
	Push(std::move(c));
	return 0;
}

// ---- Lua: mem

static bool MemOk(lua_Integer a, u32 n) {
	return a >= 0 && a <= 0xFFFFFFFFLL && PSP_IsInited() && Memory::IsValidRange((u32)a, n);
}

static int mem_u8(lua_State *L) {
	lua_Integer a = luaL_checkinteger(L, 1);
	if (MemOk(a, 1)) lua_pushinteger(L, Memory::ReadUnchecked_U8((u32)a)); else lua_pushnil(L);
	return 1;
}
static int mem_s8(lua_State *L) {
	lua_Integer a = luaL_checkinteger(L, 1);
	if (MemOk(a, 1)) lua_pushinteger(L, (int8_t)Memory::ReadUnchecked_U8((u32)a)); else lua_pushnil(L);
	return 1;
}
static int mem_u16(lua_State *L) {
	lua_Integer a = luaL_checkinteger(L, 1);
	if (MemOk(a, 2)) lua_pushinteger(L, Memory::ReadUnchecked_U16((u32)a)); else lua_pushnil(L);
	return 1;
}
static int mem_s16(lua_State *L) {
	lua_Integer a = luaL_checkinteger(L, 1);
	if (MemOk(a, 2)) lua_pushinteger(L, (int16_t)Memory::ReadUnchecked_U16((u32)a)); else lua_pushnil(L);
	return 1;
}
static int mem_u32(lua_State *L) {
	lua_Integer a = luaL_checkinteger(L, 1);
	if (MemOk(a, 4)) lua_pushinteger(L, (lua_Integer)Memory::ReadUnchecked_U32((u32)a)); else lua_pushnil(L);
	return 1;
}
static int mem_s32(lua_State *L) {
	lua_Integer a = luaL_checkinteger(L, 1);
	if (MemOk(a, 4)) lua_pushinteger(L, (int32_t)Memory::ReadUnchecked_U32((u32)a)); else lua_pushnil(L);
	return 1;
}
static int mem_f32(lua_State *L) {
	lua_Integer a = luaL_checkinteger(L, 1);
	if (MemOk(a, 4)) {
		u32 bits = Memory::ReadUnchecked_U32((u32)a);
		float f;
		memcpy(&f, &bits, 4);
		lua_pushnumber(L, f);
	} else {
		lua_pushnil(L);
	}
	return 1;
}
static int mem_ptr(lua_State *L) {
	lua_Integer a = luaL_checkinteger(L, 1);
	if (MemOk(a, 4)) {
		u32 p = Memory::ReadUnchecked_U32((u32)a);
		if (p >= 0x08800000 && p < 0x0A000000 && Memory::IsValidRange(p, 4)) {
			lua_pushinteger(L, p);
			return 1;
		}
	}
	lua_pushnil(L);
	return 1;
}
static int mem_str(lua_State *L) {
	lua_Integer a = luaL_checkinteger(L, 1);
	lua_Integer max = luaL_optinteger(L, 2, 64);
	if (max < 0 || max > 4096) max = 4096;
	std::string s;
	for (lua_Integer i = 0; i < max && MemOk(a + i, 1); i++) {
		u8 c = Memory::ReadUnchecked_U8((u32)(a + i));
		if (!c) break;
		s.push_back((char)c);
	}
	lua_pushlstring(L, s.data(), s.size());
	return 1;
}
static int mem_w8(lua_State *L) {
	lua_Integer a = luaL_checkinteger(L, 1), v = luaL_checkinteger(L, 2);
	bool ok = MemOk(a, 1);
	if (ok) Memory::WriteUnchecked_U8((u8)v, (u32)a);
	lua_pushboolean(L, ok);
	return 1;
}
static int mem_w16(lua_State *L) {
	lua_Integer a = luaL_checkinteger(L, 1), v = luaL_checkinteger(L, 2);
	bool ok = MemOk(a, 2);
	if (ok) Memory::WriteUnchecked_U16((u16)v, (u32)a);
	lua_pushboolean(L, ok);
	return 1;
}
static int mem_w32(lua_State *L) {
	lua_Integer a = luaL_checkinteger(L, 1), v = luaL_checkinteger(L, 2);
	bool ok = MemOk(a, 4);
	if (ok) Memory::WriteUnchecked_U32((u32)v, (u32)a);
	lua_pushboolean(L, ok);
	return 1;
}

// ---- 7s probe: research files in PSP/SYSTEM/companion/probe/ (read-only for the game; nothing is written to it)

static Path ProbePath(lua_State *L, const char *ext) {
	std::string name = luaL_checkstring(L, 1);
	for (char &ch : name) if (!isalnum((unsigned char)ch) && ch != '_' && ch != '-') ch = '_';
	Path dir = GetSysDirectory(DIRECTORY_SYSTEM) / "companion" / "probe";
	File::CreateFullPath(dir);
	return dir / (name + ext);
}

// mem.dump(name, start, len) -> bytes written (or nil): copies game RAM to probe/<name>.bin, 1 MB at a time,
// stopping at the first block outside valid memory.
static int mem_dump(lua_State *L) {
	Path path = ProbePath(L, ".bin");
	lua_Integer a = luaL_checkinteger(L, 2), n = luaL_checkinteger(L, 3);
	if (n <= 0 || n > 0x04000000 || !PSP_IsInited()) { lua_pushnil(L); return 1; }
	FILE *f = File::OpenCFile(path, "wb");
	if (!f) { CLOGE("Probe: can't write %s", path.c_str()); lua_pushnil(L); return 1; }
	lua_Integer done = 0;
	while (done < n) {
		u32 step = (u32)std::min<lua_Integer>(n - done, 0x100000);
		if (!MemOk(a + done, step)) break;
		const u8 *src = Memory::GetPointerUnchecked((u32)(a + done));
		if (!src || fwrite(src, 1, step, f) != step) break;
		done += step;
	}
	fclose(f);
	lua_pushinteger(L, done);
	return 1;
}

// logs.write(name, text [, append]) -> true: a text file probe/<name>.txt
static int logs_write(lua_State *L) {
	Path path = ProbePath(L, ".txt");
	size_t len = 0;
	const char *text = luaL_checklstring(L, 2, &len);
	FILE *f = File::OpenCFile(path, lua_toboolean(L, 3) ? "ab" : "wb");
	bool ok = f && fwrite(text, 1, len, f) == len;
	if (f) fclose(f);
	if (!ok) CLOGE("Probe: can't write %s", path.c_str());
	lua_pushboolean(L, ok);
	return 1;
}

// ---- Lua: store (small key -> value memory per package, kept in PSP/SYSTEM/companion/<package>.txt)
// Lines: key TAB n|s TAB value. Written whenever a value changes (only on user actions, so rarely).

static std::map<std::string, std::string> g_store;   // value with a type prefix: "n" number, "s" string
static Path g_storePath;

static void StoreLoad() {
	g_store.clear();
	std::string name = g_pkg ? g_pkg->dir.substr(g_pkg->dir.rfind('/') + 1) : "unknown";
	g_storePath = GetSysDirectory(DIRECTORY_SYSTEM) / "companion" / (name + ".txt");
	std::string text;
	if (!File::ReadTextFileToString(g_storePath, &text)) return;
	size_t pos = 0;
	while (pos < text.size()) {
		size_t end = text.find('\n', pos);
		if (end == std::string::npos) end = text.size();
		std::string line = text.substr(pos, end - pos);
		pos = end + 1;
		size_t t1 = line.find('\t'), t2 = t1 == std::string::npos ? t1 : line.find('\t', t1 + 1);
		if (t2 == std::string::npos) continue;
		g_store[line.substr(0, t1)] = line.substr(t1 + 1, t2 - t1 - 1) + line.substr(t2 + 1);
	}
	CLOG("Store %s: %d value(s)", g_storePath.c_str(), (int)g_store.size());
}

static void StoreSave() {
	std::string text;
	for (const auto &kv : g_store) text += kv.first + "\t" + kv.second.substr(0, 1) + "\t" + kv.second.substr(1) + "\n";
	File::CreateFullPath(g_storePath.NavigateUp());
	if (!File::WriteStringToFile(true, text, g_storePath)) CLOGE("Store %s: write failed", g_storePath.c_str());
}

static int store_get(lua_State *L) {
	auto it = g_store.find(luaL_checkstring(L, 1));
	if (it == g_store.end() || it->second.empty()) { lua_pushnil(L); return 1; }
	if (it->second[0] == 'n') {
		lua_Number n = strtod(it->second.c_str() + 1, nullptr);
		if (n == (lua_Number)(lua_Integer)n) lua_pushinteger(L, (lua_Integer)n); else lua_pushnumber(L, n);
	} else {
		lua_pushstring(L, it->second.c_str() + 1);
	}
	return 1;
}

static int store_set(lua_State *L) {
	std::string key = luaL_checkstring(L, 1);
	if (key.find_first_of("\t\n") != std::string::npos) return luaL_error(L, "store.set: bad key");
	std::string val;
	if (lua_isnoneornil(L, 2)) {
		if (!g_store.erase(key)) return 0;
	} else {
		if (lua_type(L, 2) == LUA_TNUMBER) val = "n" + std::string(lua_tostring(L, 2));
		else val = "s" + std::string(luaL_checkstring(L, 2));
		if (val.find_first_of("\t\n") != std::string::npos) return luaL_error(L, "store.set: value has a tab or newline");
		auto it = g_store.find(key);
		if (it != g_store.end() && it->second == val) return 0;
		g_store[key] = val;
	}
	StoreSave();
	CLOG("[%s] store %s = %s", g_pkg ? g_pkg->dir.c_str() : "?", key.c_str(), val.empty() ? "(removed)" : val.c_str() + 1);
	return 0;
}

// ---- Lua: code patches (applied on the emulator thread, see CompanionEmu.h)

// mem.code_patch(addr, want, {allowed values}): keep the instruction at addr = want, but only touch it while
// it holds one of the allowed values (the original, or our own). Applied at the next vblank.
static int mem_code_patch(lua_State *L) {
	u32 addr = (u32)luaL_checkinteger(L, 1);
	u32 want = (u32)luaL_checkinteger(L, 2);
	luaL_checktype(L, 3, LUA_TTABLE);
	std::vector<uint32_t> allowed;
	lua_Integer n = luaL_len(L, 3);
	for (lua_Integer i = 1; i <= n; i++) {
		lua_geti(L, 3, i);
		allowed.push_back((uint32_t)lua_tointeger(L, -1));
		lua_pop(L, 1);
	}
	SetCodePatch(addr, want, allowed);
	return 0;
}

// 7z: mem.watch({ start1, end1, start2, end2, ... }) watches those ranges for reads / writes (research; {} = off)
static int mem_watch(lua_State *L) {
	luaL_checktype(L, 1, LUA_TTABLE);
	std::vector<uint32_t> v;
	lua_Integer n = luaL_len(L, 1);
	for (lua_Integer i = 1; i <= n && i <= 32; i++) {
		lua_geti(L, 1, i);
		v.push_back((uint32_t)lua_tointeger(L, -1));
		lua_pop(L, 1);
	}
	if (v.size() % 2) v.pop_back();
	SetWatch(v);
	return 0;
}

// 7z: mem.watch_hits() -> { { addr, pc, ra, size, write, count }, ... } counted since the last call
static int mem_watch_hits(lua_State *L) {
	std::vector<WatchHit> hits;
	TakeWatchHits(&hits);
	lua_createtable(L, (int)hits.size(), 0);
	int i = 1;
	for (auto &h : hits) {
		lua_createtable(L, 0, 6);
		lua_pushinteger(L, h.addr); lua_setfield(L, -2, "addr");
		lua_pushinteger(L, h.pc); lua_setfield(L, -2, "pc");
		lua_pushinteger(L, h.ra); lua_setfield(L, -2, "ra");
		lua_pushinteger(L, h.size); lua_setfield(L, -2, "size");
		lua_pushboolean(L, h.write); lua_setfield(L, -2, "write");
		lua_pushinteger(L, h.count); lua_setfield(L, -2, "count");
		lua_rawseti(L, -2, i++);
	}
	return 1;
}

// mem.code_status(addr) -> "pending" | "applied" | "unknown" (left alone: not a value we know) | nil, instruction
static int mem_code_status(lua_State *L) {
	uint32_t seen = 0;
	int st = CodePatchStatus((u32)luaL_checkinteger(L, 1), &seen);
	if (st < 0) { lua_pushnil(L); return 1; }
	lua_pushstring(L, st == 1 ? "applied" : st == 2 ? "unknown" : "pending");
	lua_pushinteger(L, seen);
	return 2;
}

// mem.code_read(addr, count) -> { word, ... } once read on the emulator thread (the real instructions, even
// where the JIT left its markers), or nil while the read is still queued (try again next frame)
static int mem_code_read(lua_State *L) {
	u32 addr = (u32)luaL_checkinteger(L, 1);
	u32 count = (u32)luaL_checkinteger(L, 2);
	std::vector<uint32_t> words;
	if (!CodeRead(addr, count, &words)) { lua_pushnil(L); return 1; }
	lua_createtable(L, (int)words.size(), 0);
	for (size_t i = 0; i < words.size(); i++) {
		lua_pushinteger(L, words[i]);
		lua_rawseti(L, -2, (lua_Integer)i + 1);
	}
	return 1;
}

// ---- Lua: 7f button presses (on the emulator thread, see CompanionEmu.h)

// pad.press(name, delay, hold) -> ok: press one PSP button ("square", "triangle", "circle", "cross") after delay
// vblanks (60 a second), for hold vblanks. false while an earlier press is still running.
static int pad_press(lua_State *L) {
	static const std::map<std::string, uint32_t> names = {
		{ "square", 0x8000 }, { "triangle", 0x1000 }, { "circle", 0x2000 }, { "cross", 0x4000 },
	};
	auto it = names.find(luaL_checkstring(L, 1));
	if (it == names.end()) return luaL_error(L, "pad.press: unknown button");
	int delay = (int)luaL_optinteger(L, 2, 0), hold = (int)luaL_optinteger(L, 3, 4);
	lua_pushboolean(L, PressButtons(it->second, delay, hold));
	return 1;
}

// pad.busy() -> true while a press is queued or held
static int pad_busy(lua_State *L) {
	lua_pushboolean(L, ButtonsBusy());
	return 1;
}

// ---- Lua: misc

static int l_log(lua_State *L) {
	std::string line;
	int n = lua_gettop(L);
	for (int i = 1; i <= n; i++) {
		if (i > 1) line += " ";
		line += luaL_tolstring(L, i, nullptr);
		lua_pop(L, 1);
	}
	CLOG("[%s] %s", g_pkg ? g_pkg->dir.c_str() : "?", line.c_str());
	AddLog(false, line);
	return 0;
}

// logs.lines() -> { {time = "12:34:56", text = "...", err = false}, ... } oldest first
static int logs_lines(lua_State *L) {
	lua_createtable(L, (int)g_log.size(), 0);
	int i = 1;
	for (const LogLine &l : g_log) {
		lua_createtable(L, 0, 3);
		lua_pushstring(L, l.time.c_str());
		lua_setfield(L, -2, "time");
		lua_pushlstring(L, l.text.data(), l.text.size());
		lua_setfield(L, -2, "text");
		lua_pushboolean(L, l.err);
		lua_setfield(L, -2, "err");
		lua_rawseti(L, -2, i++);
	}
	return 1;
}

static int logs_clear(lua_State *) {
	g_log.clear();
	return 0;
}

// logs.stats() -> "redraws N  lua X ms  K KB" (the same line ui.stats draws, for copying)
static int logs_stats(lua_State *L) {
	EngineStats st;
	{
		std::lock_guard<std::mutex> guard(g_lock);
		st = g_stats;
	}
	char s[96];
	snprintf(s, sizeof(s), "redraws %d  lua %.2f ms  %d KB", RedrawCount(), st.luaMicros / 1000.0f, st.luaKB);
	lua_pushstring(L, s);
	return 1;
}

// ui.copy(text): put text on the Android clipboard (done by the Java side right after this callback)
static int ui_copy(lua_State *L) {
	size_t n = 0;
	const char *s = luaL_checklstring(L, 1, &n);
	if (n > 256 * 1024) n = 256 * 1024;
	g_clipboard.assign(s, n);
	g_hasClipboard = true;
	return 0;
}

// 7n: ui.request(name): see g_requests
static int ui_request(lua_State *L) {
	const char *s = luaL_checkstring(L, 1);
	if (g_requests.size() < 16) g_requests.push_back(s);
	return 0;
}

static int l_include(lua_State *L) {
	std::string file = luaL_checkstring(L, 1);
	if (!g_pkg || file.find("..") != std::string::npos) return luaL_error(L, "include: bad file '%s'", file.c_str());
	std::string path = g_pkg->dir + "/" + file, src;
	if (!ReadAsset(path, &src)) return luaL_error(L, "include: %s not found", path.c_str());
	std::string chunk = "@" + path;
	if (luaL_loadbufferx(L, src.data(), src.size(), chunk.c_str(), "t") != LUA_OK) return lua_error(L);
	int base = lua_gettop(L) - 1;
	lua_call(L, 0, LUA_MULTRET);
	return lua_gettop(L) - base;
}

static void BudgetHook(lua_State *L, lua_Debug *) {
	if (std::chrono::steady_clock::now() > g_deadline) {
		g_budgetHit = true;
		luaL_error(L, "script took longer than %d ms, so the package was stopped (it may be stuck in a loop)", kScriptBudgetMs);
	}
}

static void Register(lua_State *L, const char *table, const luaL_Reg *funcs) {
	lua_newtable(L);
	luaL_setfuncs(L, funcs, 0);
	lua_setglobal(L, table);
}

// Calls global `name` with nargs already pushed (below them nothing). Returns false and sets *err on failure.
static bool CallGlobal(const char *name, int nargs, std::string *err, bool required) {
	lua_State *L = g_L;
	lua_getglobal(L, name);
	if (!lua_isfunction(L, -1)) {
		lua_pop(L, 1 + nargs);
		if (required) *err = std::string("the package has no ") + name + "() function";
		return !required;
	}
	if (nargs) lua_insert(L, -1 - nargs);
	g_deadline = std::chrono::steady_clock::now() + std::chrono::milliseconds(kScriptBudgetMs);
	if (lua_pcall(L, nargs, 0, 0) != LUA_OK) {
		*err = lua_tostring(L, -1) ? lua_tostring(L, -1) : "(error)";
		lua_pop(L, 1);
		return false;
	}
	return true;
}

static void SetGameFields(float lh);

static void Unload() {
	if (g_L) {
		lua_close(g_L);
		CLOG("Package %s unloaded", g_pkg ? g_pkg->dir.c_str() : "?");
	}
	g_L = nullptr;
	g_pkg = nullptr;
	g_loadError.clear();
	g_frameError.clear();
	g_budgetHit = false;
	g_lastLoggedError.clear();
	ClearImages();
	ClearCodePatches();
	ReleaseButtons();
	g_regions.clear();
	g_downId.clear();
	g_pressedId.clear();
	g_requests.clear();
}

static void Load(const Package *pkg) {
	g_pkg = pkg;
	g_loadTime = std::chrono::steady_clock::now();
	lua_State *L = luaL_newstate();
	g_L = L;
	OpenSafeLibs(L);
	static const luaL_Reg ui[] = {
		{ "clear", ui_clear }, { "rect", ui_rect }, { "frame", ui_frame }, { "text", ui_text },
		{ "text_width", ui_text_width }, { "button", ui_button }, { "stats", ui_stats }, { "gradient", ui_gradient },
		{ "image", ui_image }, { "image_size", ui_image_size }, { "poly", ui_poly }, { "line", ui_line },
		{ "circle", ui_circle }, { "ring", ui_ring }, { "arc", ui_arc }, { "pie", ui_pie }, { "radial", ui_radial },
		{ "clip", ui_clip }, { "vignette", ui_vignette }, { "copy", ui_copy },
		{ "request", ui_request }, { "transform", ui_transform }, { "remap", ui_remap }, { "font", ui_font },
		{ nullptr, nullptr },
	};
	static const luaL_Reg mem[] = {
		{ "u8", mem_u8 }, { "s8", mem_s8 }, { "u16", mem_u16 }, { "s16", mem_s16 }, { "u32", mem_u32 }, { "s32", mem_s32 },
		{ "f32", mem_f32 }, { "ptr", mem_ptr }, { "str", mem_str }, { "w8", mem_w8 }, { "w16", mem_w16 }, { "w32", mem_w32 },
		{ "code_patch", mem_code_patch }, { "code_status", mem_code_status }, { "code_read", mem_code_read },
		{ "dump", mem_dump },
		{ "watch", mem_watch }, { "watch_hits", mem_watch_hits },
		{ nullptr, nullptr },
	};
	Register(L, "ui", ui);
	Register(L, "mem", mem);
	static const luaL_Reg store[] = { { "get", store_get }, { "set", store_set }, { nullptr, nullptr } };
	Register(L, "store", store);
	static const luaL_Reg pad[] = { { "press", pad_press }, { "busy", pad_busy }, { nullptr, nullptr } };
	Register(L, "pad", pad);
	static const luaL_Reg logs[] = { { "lines", logs_lines }, { "clear", logs_clear }, { "stats", logs_stats }, { "write", logs_write }, { nullptr, nullptr } };
	Register(L, "logs", logs);
	StoreLoad();
	lua_newtable(L);
	lua_setglobal(L, "game");
	lua_register(L, "log", l_log);
	lua_register(L, "print", l_log);
	lua_register(L, "include", l_include);
	lua_sethook(L, BudgetHook, LUA_MASKCOUNT, 10000);
	SetGameFields(LogicalHeight());

	auto t0 = std::chrono::steady_clock::now();
	g_deadline = t0 + std::chrono::milliseconds(kScriptBudgetMs * 10);   // loading may take a little longer
	lua_pushcfunction(L, l_include);
	lua_pushstring(L, pkg->main.c_str());
	if (lua_pcall(L, 1, 0, 0) != LUA_OK) {
		g_loadError = lua_tostring(L, -1) ? lua_tostring(L, -1) : "(error)";
		lua_pop(L, 1);
	} else {
		CallGlobal("on_load", 0, &g_loadError, false);
	}
	int us = (int)std::chrono::duration_cast<std::chrono::microseconds>(std::chrono::steady_clock::now() - t0).count();
	if (g_loadError.empty()) {
		CLOG("Package %s loaded in %.2f ms", pkg->dir.c_str(), us / 1000.0f);
		char t[96];
		snprintf(t, sizeof(t), "Package loaded in %.2f ms", us / 1000.0f);
		AddLog(false, t);
	}
	else {
		CLOGE("Package %s failed to load: %s", pkg->dir.c_str(), g_loadError.c_str());
	}
}

bool HasCompanionForRunningGame() {
	std::string id = PSP_IsInited() ? g_paramSFO.GetDiscID() : std::string();
	if (id != g_runningId) {
		Unload();
		g_runningId = id;
		if (!id.empty()) {
			const Package *pkg = FindPackage(id);
			if (pkg) Load(pkg);
		}
	}
	return g_pkg != nullptr;
}

// ---------------------------------------------------------------- frames

static void SetGameFields(float lh) {
	lua_State *L = g_L;
	lua_getglobal(L, "game");
	lua_pushstring(L, g_runningId.c_str());
	lua_setfield(L, -2, "id");
	lua_pushstring(L, PSP_IsInited() ? g_paramSFO.GetValueString("TITLE").c_str() : "");
	lua_setfield(L, -2, "title");
	lua_pop(L, 1);
	lua_getglobal(L, "ui");
	// seconds since the package loaded; a package that animates with it redraws every tick while it does
	lua_pushnumber(L, std::chrono::duration<double>(std::chrono::steady_clock::now() - g_loadTime).count());
	lua_setfield(L, -2, "time");
	lua_pushnumber(L, kLogicalWidth);
	lua_setfield(L, -2, "width");
	lua_pushnumber(L, lh);
	lua_setfield(L, -2, "height");
	lua_pop(L, 1);
}

static void WrapText(const std::string &msg, float x, float y, float maxW, float size, uint32_t color, float maxY) {
	std::string line, word;
	auto flush = [&]() {
		if (y < maxY) AddText(x, y, line, size, color);
		y += size * 1.25f;
		line.clear();
	};
	for (size_t i = 0; i <= msg.size(); i++) {
		char c = i < msg.size() ? msg[i] : ' ';
		if (c == '\n' || c == ' ') {
			std::string test = line.empty() ? word : line + " " + word;
			if (!line.empty() && TextWidth(test, size) > maxW) { flush(); line = word; }
			else line = test;
			word.clear();
			if (c == '\n') flush();
		} else {
			word.push_back(c);
		}
	}
	if (!line.empty()) flush();
}

static void BuildErrorScreen(const char *title, const std::string &msg, float lh) {
	ResetDrawState();
	g_build.cmds.clear();
	g_buildRegions.clear();
	g_build.clear = 0x1A0C0C;
	AddRect(0, 0, kLogicalWidth, 36, 0x3A1414);
	AddRect(0, 36, kLogicalWidth, 2, 0xE05A4A);
	AddText(12, 5, title, 20, 0xFFD0C8);
	AddText(12, 46, g_pkg ? g_pkg->dir : std::string("?"), 16, 0xB9AD92);
	WrapText(msg, 12, 72, kLogicalWidth - 24, 17, 0xEFE6CF, lh - 20);
}

// Runs frame() and publishes the result. True when it differs from what's on screen.
static bool BuildAndPublish() {
	const float lh = LogicalHeight();
	g_build = DrawList();
	g_buildRegions.clear();
	ResetDrawState();
	int us = 0;
	if (g_budgetHit && g_loadError.empty()) g_loadError = "script took longer than 100 ms, so the package was stopped";
	if (!g_loadError.empty()) {
		BuildErrorScreen(g_budgetHit ? "Companion package stopped" : "Companion package failed to load", g_loadError, lh);
	} else {
		SetGameFields(lh);
		auto t0 = std::chrono::steady_clock::now();
		std::string err;
		bool ok = CallGlobal("frame", 0, &err, true);
		us = (int)std::chrono::duration_cast<std::chrono::microseconds>(std::chrono::steady_clock::now() - t0).count();
		if (ok) {
			g_frameError.clear();
		} else if (g_budgetHit) {
			// Don't keep blocking the UI thread with a stuck script: stop the package until the game changes.
			g_loadError = err;
			CLOGE("frame() stopped: %s", err.c_str());
			BuildErrorScreen("Companion package stopped", err, lh);
		} else {
			g_frameError = err;
			if (err != g_lastLoggedError) {
				CLOGE("frame() error: %s", err.c_str());
				g_lastLoggedError = err;
			}
			BuildErrorScreen("Companion script error", err, lh);
		}
	}
	g_regions = g_buildRegions;
	int kb = g_L ? lua_gc(g_L, LUA_GCCOUNT, 0) : 0;
	std::lock_guard<std::mutex> guard(g_lock);
	g_stats.luaMicros = us;
	g_stats.luaKB = kb;
	if (g_build == g_published) return false;
	g_published = std::move(g_build);
	return true;
}

bool Update() {
	if (!g_pkg) return false;
	return BuildAndPublish();
}

static const Region *RegionAt(float x, float y) {
	for (auto it = g_regions.rbegin(); it != g_regions.rend(); ++it)   // last drawn is on top
		if (x >= it->x && x < it->x + it->w && y >= it->y && y < it->y + it->h) return &*it;
	return nullptr;
}

bool Touch(int action, float x, float y) {
	if (!g_pkg) return false;
	const Region *hit = RegionAt(x, y);
	std::string hitId = hit ? hit->id : std::string();
	std::string pressId;
	switch (action) {
	case 0:  // down
		g_downId = hitId;
		g_pressedId = hitId;
		break;
	case 2:  // move: the button stays pressed only while the finger is over it
		g_pressedId = (!g_downId.empty() && hitId == g_downId) ? g_downId : std::string();
		break;
	case 1:  // up
		if (!g_downId.empty() && hitId == g_downId) pressId = g_downId;
		g_downId.clear();
		g_pressedId.clear();
		break;
	default:  // cancel
		g_downId.clear();
		g_pressedId.clear();
		break;
	}
	if (g_L && g_loadError.empty()) {
		std::string err;
		// (a stuck on_press / on_touch also sets g_budgetHit; BuildAndPublish below then stops the package)
		if (!pressId.empty()) {
			lua_pushstring(g_L, pressId.c_str());
			if (!CallGlobal("on_press", 1, &err, false)) CLOGE("on_press error: %s", err.c_str());
		}
		lua_pushinteger(g_L, action);
		lua_pushnumber(g_L, x);
		lua_pushnumber(g_L, y);
		if (!CallGlobal("on_touch", 3, &err, false)) CLOGE("on_touch error: %s", err.c_str());
	}
	return BuildAndPublish();
}

// 7n: a button pressed from outside the bottom-screen window (the floating restore button)
bool Press(const std::string &id) {
	if (!g_pkg) return false;
	if (g_L && g_loadError.empty()) {
		std::string err;
		lua_pushstring(g_L, id.c_str());
		if (!CallGlobal("on_press", 1, &err, false)) CLOGE("on_press error: %s", err.c_str());
	}
	return BuildAndPublish();
}

}  // namespace Companion
