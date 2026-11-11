// Thor Companion: turns a draw list into triangle batches (no GL here, so it can be tested off-device).

#include "Companion/CompanionDraw.h"
#include "Companion/CompanionFont.h"

#include <algorithm>
#include <cmath>

namespace Companion {

namespace {

const float kPi = 3.14159265358979f;

struct Builder {
	std::vector<Batch> *out;
	bool clip = false;
	float clipRect[4] = {};

	Batch &Get(int tex, bool nearest, int mode = 0) {
		if (!out->empty()) {
			Batch &b = out->back();
			if (b.tex == tex && b.nearest == nearest && b.mode == mode && b.clip == clip &&
				(!clip || (b.cx == clipRect[0] && b.cy == clipRect[1] && b.cw == clipRect[2] && b.ch == clipRect[3])))
				return b;
		}
		Batch b;
		b.tex = tex;
		b.nearest = nearest;
		b.mode = mode;
		b.clip = clip;
		b.cx = clipRect[0]; b.cy = clipRect[1]; b.cw = clipRect[2]; b.ch = clipRect[3];
		out->push_back(std::move(b));
		return out->back();
	}
};

Vtx V(float x, float y, uint32_t rgb, float alpha, float u = 0.5f, float v = 0.5f) {
	float a = std::max(0.0f, std::min(1.0f, alpha));
	Vtx o;
	o.x = x; o.y = y; o.u = u; o.v = v;
	o.r = (uint8_t)std::lround(((rgb >> 16) & 255) * a);
	o.g = (uint8_t)std::lround(((rgb >> 8) & 255) * a);
	o.b = (uint8_t)std::lround((rgb & 255) * a);
	o.a = (uint8_t)std::lround(255 * a);
	return o;
}

void Tri(Batch &b, const Vtx &p, const Vtx &q, const Vtx &r) {
	b.v.push_back(p); b.v.push_back(q); b.v.push_back(r);
}

void Quad(Batch &b, const Vtx &tl, const Vtx &tr, const Vtx &bl, const Vtx &br) {
	Tri(b, tl, tr, bl);
	Tri(b, tr, br, bl);
}

int Segments(float r, float sweepRad) {
	// about one segment per 2.5 logical units of arc (~6 physical pixels on the Thor)
	int n = (int)std::ceil(std::fabs(sweepRad) * std::max(r, 1.0f) / 2.5f);
	return std::max(6, std::min(256, n));
}

// angle in degrees, 0 = 12 o'clock, clockwise
void Polar(float cx, float cy, float rx, float ry, float rad, float *x, float *y) {
	*x = cx + rx * std::sin(rad);
	*y = cy - ry * std::cos(rad);
}

void Text(Builder &bld, float x, float y, float size, uint32_t color, float alpha, const std::string &s) {
	Batch &b = bld.Get(TEX_FONT, false);
	const float k = size / kFontCellH;
	const float aw = (float)(kAtlasCols * kFontCellW), ah = (float)(kAtlasRows * kFontCellH);
	for (unsigned char ch : s) {
		int g = (ch >= 32 && ch < 127) ? ch - 32 : 0;
		if (g != 0) {
			float u0 = (g % kAtlasCols) * kFontCellW / aw, v0 = (g / kAtlasCols) * kFontCellH / ah;
			float u1 = u0 + kFontCellW / aw, v1 = v0 + kFontCellH / ah;
			float w = kFontCellW * k, h = kFontCellH * k;
			Quad(b, V(x, y, color, alpha, u0, v0), V(x + w, y, color, alpha, u1, v0),
				V(x, y + h, color, alpha, u0, v1), V(x + w, y + h, color, alpha, u1, v1));
		}
		x += kFontAdvance[g] * k;
	}
}

}  // namespace

void Tessellate(const DrawList &list, const std::string &statsText, std::vector<Batch> *out) {
	out->clear();
	Builder bld;
	bld.out = out;
	for (const Cmd &c : list.cmds) {
		const float *f = c.f;
		switch (c.type) {
		case CMD_RECT: {
			Batch &b = bld.Get(TEX_WHITE, false);
			Quad(b, V(f[0], f[1], c.c[0], c.a[0]), V(f[0] + f[2], f[1], c.c[0], c.a[0]),
				V(f[0], f[1] + f[3], c.c[0], c.a[0]), V(f[0] + f[2], f[1] + f[3], c.c[0], c.a[0]));
			break;
		}
		case CMD_GRADIENT: {
			Batch &b = bld.Get(TEX_WHITE, false);
			Vtx p0 = V(f[0], f[1], c.c[0], c.a[0]);
			bool horiz = c.flags & 1;
			Vtx tr = V(f[0] + f[2], f[1], c.c[horiz ? 1 : 0], c.a[horiz ? 1 : 0]);
			Vtx bl = V(f[0], f[1] + f[3], c.c[horiz ? 0 : 1], c.a[horiz ? 0 : 1]);
			Vtx br = V(f[0] + f[2], f[1] + f[3], c.c[1], c.a[1]);
			Quad(b, p0, tr, bl, br);
			break;
		}
		case CMD_TEXT:
			Text(bld, f[0], f[1], f[2], c.c[0], c.a[0], c.text);
			break;
		case CMD_STATS: {
			float w = TextWidth(statsText, f[2]);
			Text(bld, f[0] - w, f[1], f[2], c.c[0], c.a[0], statsText);
			break;
		}
		case CMD_IMAGE: {
			if (c.iw <= 0 || c.ih <= 0) break;
			Batch &b = bld.Get(c.image, c.flags & 1, (c.flags & 8) ? 1 : (c.flags & 16) ? 2 : 0);
			float x = f[0], y = f[1], w = f[2], h = f[3];
			float u0 = f[4] / c.iw, v0 = f[5] / c.ih, u1 = (f[4] + f[6]) / c.iw, v1 = (f[5] + f[7]) / c.ih;
			if (c.flags & 2) std::swap(u0, u1);
			if (c.flags & 4) std::swap(v0, v1);
			float rot = f[8] * kPi / 180.0f, ox = x + f[9], oy = y + f[10];
			float cs = std::cos(rot), sn = std::sin(rot);
			auto P = [&](float px, float py, float u, float v) {
				float dx = px - ox, dy = py - oy;
				return V(ox + dx * cs - dy * sn, oy + dx * sn + dy * cs, c.c[0], c.a[0], u, v);
			};
			Quad(b, P(x, y, u0, v0), P(x + w, y, u1, v0), P(x, y + h, u0, v1), P(x + w, y + h, u1, v1));
			break;
		}
		case CMD_POLY: {
			size_t n = c.pts.size() / 2;
			if (n < 3) break;
			Batch &b = bld.Get(TEX_WHITE, false);
			Vtx p0 = V(c.pts[0], c.pts[1], c.c[0], c.a[0]);
			for (size_t i = 1; i + 1 < n; i++)
				Tri(b, p0, V(c.pts[2 * i], c.pts[2 * i + 1], c.c[0], c.a[0]), V(c.pts[2 * i + 2], c.pts[2 * i + 3], c.c[0], c.a[0]));
			break;
		}
		case CMD_ARC: {
			float cx = f[0], cy = f[1], ro = f[2], t = f[3];
			float a0 = f[4] * kPi / 180.0f, a1 = f[5] * kPi / 180.0f;
			if (a1 == a0 || ro <= 0) break;
			Batch &b = bld.Get(TEX_WHITE, false);
			int n = Segments(ro, a1 - a0);
			float ri = t > 0 ? std::max(0.0f, ro - t) : 0.0f;
			for (int i = 0; i < n; i++) {
				float s0 = a0 + (a1 - a0) * i / n, s1 = a0 + (a1 - a0) * (i + 1) / n;
				float ox0, oy0, ox1, oy1;
				Polar(cx, cy, ro, ro, s0, &ox0, &oy0);
				Polar(cx, cy, ro, ro, s1, &ox1, &oy1);
				if (ri <= 0) {
					Tri(b, V(cx, cy, c.c[0], c.a[0]), V(ox0, oy0, c.c[0], c.a[0]), V(ox1, oy1, c.c[0], c.a[0]));
				} else {
					float ix0, iy0, ix1, iy1;
					Polar(cx, cy, ri, ri, s0, &ix0, &iy0);
					Polar(cx, cy, ri, ri, s1, &ix1, &iy1);
					Quad(b, V(ox0, oy0, c.c[0], c.a[0]), V(ox1, oy1, c.c[0], c.a[0]), V(ix0, iy0, c.c[0], c.a[0]), V(ix1, iy1, c.c[0], c.a[0]));
				}
			}
			break;
		}
		case CMD_RADIAL: {
			float cx = f[0], cy = f[1], rx = f[2], ry = f[3];
			if (rx <= 0 || ry <= 0) break;
			Batch &b = bld.Get(TEX_WHITE, false);
			int n = Segments(std::max(rx, ry), 2 * kPi);
			Vtx centre = V(cx, cy, c.c[0], c.a[0]);
			for (int i = 0; i < n; i++) {
				float x0, y0, x1, y1;
				Polar(cx, cy, rx, ry, 2 * kPi * i / n, &x0, &y0);
				Polar(cx, cy, rx, ry, 2 * kPi * (i + 1) / n, &x1, &y1);
				Tri(b, centre, V(x0, y0, c.c[1], c.a[1]), V(x1, y1, c.c[1], c.a[1]));
			}
			break;
		}
		case CMD_VIGNETTE: {
			// covers everything except a soft-edged ellipse: clear up to inner x radius, fading in to the rim,
			// solid beyond (out to a far ring; clip it to the box it belongs in)
			float cx = f[0], cy = f[1], rx = f[2], ry = f[3], in = std::max(0.0f, std::min(1.0f, f[4]));
			if (rx <= 0 || ry <= 0) break;
			Batch &b = bld.Get(TEX_WHITE, false);
			int n = Segments(std::max(rx, ry), 2 * kPi);
			for (int i = 0; i < n; i++) {
				float a0 = 2 * kPi * i / n, a1 = 2 * kPi * (i + 1) / n;
				float ix0, iy0, ix1, iy1, ox0, oy0, ox1, oy1, fx0, fy0, fx1, fy1;
				Polar(cx, cy, rx * in, ry * in, a0, &ix0, &iy0);
				Polar(cx, cy, rx * in, ry * in, a1, &ix1, &iy1);
				Polar(cx, cy, rx, ry, a0, &ox0, &oy0);
				Polar(cx, cy, rx, ry, a1, &ox1, &oy1);
				Polar(cx, cy, 4000, 4000, a0, &fx0, &fy0);
				Polar(cx, cy, 4000, 4000, a1, &fx1, &fy1);
				Quad(b, V(ix0, iy0, c.c[0], 0), V(ix1, iy1, c.c[0], 0), V(ox0, oy0, c.c[0], c.a[0]), V(ox1, oy1, c.c[0], c.a[0]));
				Quad(b, V(ox0, oy0, c.c[0], c.a[0]), V(ox1, oy1, c.c[0], c.a[0]), V(fx0, fy0, c.c[0], c.a[0]), V(fx1, fy1, c.c[0], c.a[0]));
			}
			break;
		}
		case CMD_CLIP:
			bld.clip = !(c.flags & 1);
			bld.clipRect[0] = f[0]; bld.clipRect[1] = f[1]; bld.clipRect[2] = f[2]; bld.clipRect[3] = f[3];
			break;
		}
	}
}

}  // namespace Companion
