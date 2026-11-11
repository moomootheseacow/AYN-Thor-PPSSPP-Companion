// Thor Companion: the draw list shared by the engine (main thread) and the renderer (GL thread).
// A package's frame() produces a list of high-level commands; the screen is only redrawn when a new list
// differs from the previous one. The GL thread turns the list into triangle batches (CompanionTess.cpp)
// and draws them (CompanionRenderer.cpp).
#pragma once

#include <cstdint>
#include <memory>
#include <string>
#include <vector>

namespace Companion {

static const float kLogicalWidth = 540.0f;

enum CmdType : uint8_t {
	CMD_RECT,      // f: x y w h
	CMD_GRADIENT,  // f: x y w h; c0 -> c1; flags & 1 = horizontal
	CMD_TEXT,      // f: x y size; text
	CMD_STATS,     // f: right_x y size (text filled in by the renderer)
	CMD_IMAGE,     // f: x y w h  sx sy sw sh  rot ox oy; image, iw ih; flags: 1 nearest, 2 flip x, 4 flip y,
	               //    8 silhouette (colour x alpha only), 16 greyscale
	CMD_POLY,      // pts (convex polygon)
	CMD_ARC,       // f: cx cy r_outer thickness(0 = filled) from_deg to_deg  (0 = 12 o'clock, clockwise)
	CMD_RADIAL,    // f: cx cy rx ry; c0 centre -> c1 rim
	CMD_CLIP,      // f: x y w h; flags & 1 = clipping off
	CMD_VIGNETTE,  // f: cx cy rx ry inner; c0 / a0: everything outside a soft ellipse (clear inside inner x radius)
};

struct Cmd {
	CmdType type = CMD_RECT;
	uint8_t flags = 0;
	int image = 0, iw = 0, ih = 0;
	float f[11] = {};
	uint32_t c[2] = {};   // 0xRRGGBB
	float a[2] = { 1.0f, 1.0f };
	std::string text;
	std::vector<float> pts;

	bool operator==(const Cmd &o) const {
		for (int i = 0; i < 11; i++) if (f[i] != o.f[i]) return false;
		return type == o.type && flags == o.flags && image == o.image && c[0] == o.c[0] && c[1] == o.c[1] &&
			a[0] == o.a[0] && a[1] == o.a[1] && text == o.text && pts == o.pts;
	}
};

struct DrawList {
	uint32_t clear = 0x0B0F15;
	std::vector<Cmd> cmds;
	bool operator==(const DrawList &o) const { return clear == o.clear && cmds == o.cmds; }
};

struct EngineStats {
	int luaMicros = 0;  // last frame() duration
	int luaKB = 0;      // Lua heap
};

// Decoded package image (RGBA8, straight alpha). Shared with the GL thread for (re)uploading.
struct Image {
	int id = 0, w = 0, h = 0;
	std::string path;
	std::vector<uint8_t> rgba;
};

// Width of a string at a text size (logical units), using the built-in font.
float TextWidth(const std::string &s, float size);

// Engine -> renderer (these take the engine's lock).
void CopyDrawList(DrawList *out, EngineStats *stats);
int RedrawCount();   // bottom-screen redraws so far (renderer, any thread)
float LogicalHeight();
void SetLogicalHeight(float h);
std::shared_ptr<const Image> GetImage(int id);

// ---- tessellation (GL-free, CompanionTess.cpp)

struct Vtx {
	float x, y, u, v;
	uint8_t r, g, b, a;   // premultiplied
};

enum : int { TEX_WHITE = 0, TEX_FONT = -1 };   // > 0: package image id

struct Batch {
	int tex = TEX_WHITE;
	bool nearest = false;
	int mode = 0;       // 0 normal, 1 silhouette, 2 greyscale
	bool clip = false;
	float cx = 0, cy = 0, cw = 0, ch = 0;   // clip rect, logical units
	std::vector<Vtx> v;                     // triangles
};

void Tessellate(const DrawList &list, const std::string &statsText, std::vector<Batch> *out);

// Font atlas layout, shared by the tessellator and the renderer.
static const int kAtlasCols = 16, kAtlasRows = 6;

}  // namespace Companion
