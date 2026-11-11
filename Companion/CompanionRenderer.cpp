// Thor Companion renderer (GL thread): tessellates the engine's latest draw list (CompanionTess.cpp) and draws
// the batches with GLES2 on the bottom screen's own EGL context. One shader: premultiplied texture x colour.
// Texture 0 is a 1x1 white texel (solid shapes), the font atlas is luminance-alpha, package images are RGBA.

#include "Companion/CompanionEngine.h"
#include "Companion/CompanionDraw.h"
#include "Companion/CompanionFont.h"

#include <GLES2/gl2.h>
#include <android/log.h>

#include <atomic>
#include <cstdio>
#include <map>
#include <vector>

#define CLOG(...) __android_log_print(ANDROID_LOG_INFO, "ThorCompanion", __VA_ARGS__)

namespace Companion {

static GLuint g_prog = 0, g_whiteTex = 0, g_fontTex = 0;
static GLint g_aPos = -1, g_aUV = -1, g_aColor = -1, g_uScale = -1, g_uTex = -1, g_uMode = -1;
static int g_width = 1, g_height = 1;
static std::atomic<int> g_redraws{0};

int RedrawCount() { return g_redraws.load(); }
static std::map<int, GLuint> g_images;          // package image id -> texture
static std::map<GLuint, bool> g_texNearest;     // current filter of each texture
static std::vector<Batch> g_batches;

static GLuint Compile(GLenum type, const char *src) {
	GLuint sh = glCreateShader(type);
	glShaderSource(sh, 1, &src, nullptr);
	glCompileShader(sh);
	GLint ok = 0;
	glGetShaderiv(sh, GL_COMPILE_STATUS, &ok);
	if (!ok) {
		char log[512] = {};
		glGetShaderInfoLog(sh, sizeof(log), nullptr, log);
		CLOG("shader error: %s", log);
	}
	return sh;
}

static GLuint MakeTexture(GLenum format, int w, int h, const void *data) {
	GLuint t = 0;
	glGenTextures(1, &t);
	glBindTexture(GL_TEXTURE_2D, t);
	glPixelStorei(GL_UNPACK_ALIGNMENT, 1);
	glTexImage2D(GL_TEXTURE_2D, 0, format, w, h, 0, format, GL_UNSIGNED_BYTE, data);
	glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
	glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
	glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
	glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
	g_texNearest[t] = false;
	return t;
}

void GlSurfaceCreated() {
	// A new EGL context: everything from an earlier one is gone.
	g_images.clear();
	g_texNearest.clear();

	static const char *vs =
		"attribute vec2 aPos; attribute vec2 aUV; attribute vec4 aColor; uniform vec2 uScale;\n"
		"varying vec2 vUV; varying vec4 vColor;\n"
		"void main() { gl_Position = vec4(aPos.x * uScale.x - 1.0, 1.0 - aPos.y * uScale.y, 0.0, 1.0); vUV = aUV; vColor = aColor; }\n";
	static const char *fs =
		"precision mediump float; varying vec2 vUV; varying vec4 vColor; uniform sampler2D uTex; uniform float uMode;\n"
		"void main() {\n"
		"  vec4 t = texture2D(uTex, vUV);\n"
		"  if (uMode > 1.5) { float g = dot(t.rgb, vec3(0.299, 0.587, 0.114)); t = vec4(g, g, g, t.a); }\n"   // greyscale
		"  else if (uMode > 0.5) { t = vec4(t.a); }\n"                                                       // silhouette
		"  gl_FragColor = t * vColor;\n"
		"}\n";
	g_prog = glCreateProgram();
	glAttachShader(g_prog, Compile(GL_VERTEX_SHADER, vs));
	glAttachShader(g_prog, Compile(GL_FRAGMENT_SHADER, fs));
	glLinkProgram(g_prog);
	g_aPos = glGetAttribLocation(g_prog, "aPos");
	g_aUV = glGetAttribLocation(g_prog, "aUV");
	g_aColor = glGetAttribLocation(g_prog, "aColor");
	g_uScale = glGetUniformLocation(g_prog, "uScale");
	g_uTex = glGetUniformLocation(g_prog, "uTex");
	g_uMode = glGetUniformLocation(g_prog, "uMode");

	static const uint8_t white[4] = { 255, 255, 255, 255 };
	g_whiteTex = MakeTexture(GL_RGBA, 1, 1, white);

	// font atlas: 16 x 6 cells of 32 x 34; luminance = alpha, i.e. premultiplied white
	const int aw = kAtlasCols * kFontCellW, ah = kAtlasRows * kFontCellH;
	std::vector<uint8_t> px(aw * ah * 2, 0);
	for (int g = 0; g < kFontCount; g++) {
		int cx = (g % kAtlasCols) * kFontCellW, cy = (g / kAtlasCols) * kFontCellH;
		for (int y = 0; y < kFontCellH; y++) {
			uint32_t bits = kFontBits[g * kFontCellH + y];
			for (int x = 0; x < kFontCellW; x++)
				if (bits & (0x80000000u >> x)) {
					size_t i = ((cy + y) * aw + cx + x) * 2;
					px[i] = px[i + 1] = 255;
				}
		}
	}
	g_fontTex = MakeTexture(GL_LUMINANCE_ALPHA, aw, ah, px.data());
	GLint samples = 0;
	glGetIntegerv(GL_SAMPLES, &samples);
	CLOG("GL surface created (%s, %dx MSAA)", (const char *)glGetString(GL_RENDERER), (int)samples);
}

void GlSurfaceChanged(int width, int height) {
	g_width = width > 0 ? width : 1;
	g_height = height > 0 ? height : 1;
	glViewport(0, 0, g_width, g_height);
	SetLogicalHeight(kLogicalWidth * g_height / g_width);
	CLOG("GL surface %d x %d (logical 540 x %.0f)", g_width, g_height, kLogicalWidth * g_height / g_width);
}

static GLuint TextureFor(int tex) {
	if (tex == TEX_WHITE) return g_whiteTex;
	if (tex == TEX_FONT) return g_fontTex;
	auto it = g_images.find(tex);
	if (it != g_images.end()) return it->second;
	std::shared_ptr<const Image> img = GetImage(tex);
	if (!img || img->rgba.empty()) return g_whiteTex;
	// premultiply on upload, so linear filtering doesn't darken edges
	std::vector<uint8_t> px(img->rgba);
	for (size_t i = 0; i + 3 < px.size(); i += 4) {
		unsigned a = px[i + 3];
		px[i] = (uint8_t)((px[i] * a + 127) / 255);
		px[i + 1] = (uint8_t)((px[i + 1] * a + 127) / 255);
		px[i + 2] = (uint8_t)((px[i + 2] * a + 127) / 255);
	}
	GLuint t = MakeTexture(GL_RGBA, img->w, img->h, px.data());
	g_images[tex] = t;
	CLOG("Uploaded %s (%d x %d)", img->path.c_str(), img->w, img->h);
	return t;
}

void GlDraw() {
	DrawList list;
	EngineStats stats;
	CopyDrawList(&list, &stats);
	const float lh = LogicalHeight();
	int redraws = ++g_redraws;

	char s[96];
	snprintf(s, sizeof(s), "redraws %d  lua %.2f ms  %d KB", redraws, stats.luaMicros / 1000.0f, stats.luaKB);
	Tessellate(list, s, &g_batches);

	glDisable(GL_SCISSOR_TEST);
	glClearColor(((list.clear >> 16) & 255) / 255.0f, ((list.clear >> 8) & 255) / 255.0f, (list.clear & 255) / 255.0f, 1.0f);
	glClear(GL_COLOR_BUFFER_BIT);
	if (!g_prog) return;
	glUseProgram(g_prog);
	glUniform2f(g_uScale, 2.0f / kLogicalWidth, 2.0f / lh);
	glUniform1i(g_uTex, 0);
	glActiveTexture(GL_TEXTURE0);
	glEnable(GL_BLEND);
	glBlendFunc(GL_ONE, GL_ONE_MINUS_SRC_ALPHA);
	glEnableVertexAttribArray(g_aPos);
	glEnableVertexAttribArray(g_aUV);
	glEnableVertexAttribArray(g_aColor);

	const float sx = g_width / kLogicalWidth, sy = g_height / lh;
	int mode = -1;
	for (const Batch &b : g_batches) {
		if (b.v.empty()) continue;
		if (b.mode != mode) { glUniform1f(g_uMode, (float)b.mode); mode = b.mode; }
		GLuint t = TextureFor(b.tex);
		glBindTexture(GL_TEXTURE_2D, t);
		if (g_texNearest[t] != b.nearest) {
			GLint f = b.nearest ? GL_NEAREST : GL_LINEAR;
			glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, f);
			glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, f);
			g_texNearest[t] = b.nearest;
		}
		if (b.clip) {
			glEnable(GL_SCISSOR_TEST);
			int x0 = (int)(b.cx * sx + 0.5f), x1 = (int)((b.cx + b.cw) * sx + 0.5f);
			int y0 = (int)(b.cy * sy + 0.5f), y1 = (int)((b.cy + b.ch) * sy + 0.5f);
			glScissor(x0, g_height - y1, x1 - x0 > 0 ? x1 - x0 : 0, y1 - y0 > 0 ? y1 - y0 : 0);
		} else {
			glDisable(GL_SCISSOR_TEST);
		}
		const Vtx *v = b.v.data();
		glVertexAttribPointer(g_aPos, 2, GL_FLOAT, GL_FALSE, sizeof(Vtx), &v->x);
		glVertexAttribPointer(g_aUV, 2, GL_FLOAT, GL_FALSE, sizeof(Vtx), &v->u);
		glVertexAttribPointer(g_aColor, 4, GL_UNSIGNED_BYTE, GL_TRUE, sizeof(Vtx), &v->r);
		glDrawArrays(GL_TRIANGLES, 0, (GLsizei)b.v.size());
	}

	glDisable(GL_SCISSOR_TEST);
	glDisableVertexAttribArray(g_aPos);
	glDisableVertexAttribArray(g_aUV);
	glDisableVertexAttribArray(g_aColor);
}

}  // namespace Companion
