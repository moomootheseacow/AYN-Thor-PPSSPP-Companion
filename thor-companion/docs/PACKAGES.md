# Companion packages

A package is one folder per game in `assets/companion/<package>/`, bundled in the APK.

When a game boots, the engine reads every `manifest.lua` and loads the package whose `ids` contain the
running game's ID. No match means normal PPSSPP and the bottom screen is left alone.

## manifest.lua

```lua
return {
	name = "Monster Hunter Freedom Unite",
	ids = { "ULJM05500", "ULUS10391", "ULES01213" },
	main = "main.lua",   -- optional, this is the default
}
```

## Callbacks (globals in main.lua)

| Function | When |
|---|---|
| `frame()` | Required. About 30 times a second: read the game, draw the screen. |
| `on_load()` | Once, after main.lua has run. |
| `on_press(id)` | A `ui.button` was tapped (finger released inside it). |
| `on_touch(action, x, y)` | Every touch event. action 0 down, 1 up, 2 move, 3 cancel. |

`frame()` rebuilds the whole screen every time. The engine compares the result with what is on screen and
only redraws when something changed, so drawing everything every frame costs nothing extra on the GPU.

## API

Coordinates are logical units: the screen is 540 wide and `ui.height` tall (470 on the Thor).
Colours are `0xRRGGBB`; alpha is optional, 0..1.

| Call | |
|---|---|
| `game.id`, `game.title` | Running game. |
| `ui.width`, `ui.height` | Screen size. |
| `ui.time` | Seconds since the package loaded. Use it for pulses and blinks; while a package animates with it, the screen redraws every tick. |
| `ui.clear(color)` | Background colour. |
| `ui.rect(x, y, w, h, color [, alpha])` | Filled rectangle. |
| `ui.frame(x, y, w, h, thickness, color [, alpha])` | Rectangle outline. |
| `ui.text(x, y, str, size, color [, align [, alpha]])` | Text, `y` is the top. align `"left"`, `"center"`, `"right"`. Returns the width. |
| `ui.text_width(str, size)` | Width of a string. |
| `ui.button(id, x, y, w, h)` | Touch area. Returns true while the finger is on it. Draw its look yourself. |
| `ui.stats(right_x, y, size, color)` | Engine stats line: redraws, Lua time per frame, Lua memory. |
| `ui.gradient(x, y, w, h, from, to [, "v" or "h" [, alpha_from, alpha_to]])` | Two-colour gradient, vertical by default. |
| `ui.image(file, x, y [, w, h [, opts]])` | PNG from the package. `opts`: `sx sy sw sh` source rect in pixels (atlases, sprite strips), `rot` degrees clockwise, `ox oy` pivot relative to `x, y` (default the centre), `tint` colour multiply, `alpha`, `pixel = true` for sharp pixel art, `flip = "x"`, `"y"` or `"xy"`. `silhouette = true` draws only the shape in the `tint` colour (outlines, glows); `grey = true` draws it in greyscale. A missing file draws a magenta box and is logged once. |
| `ui.image_size(file)` | Width, height in pixels, or `nil`. |
| `ui.poly({x1, y1, x2, y2, ...}, color [, alpha])` | Filled convex polygon. |
| `ui.line(x1, y1, x2, y2, width, color [, alpha])` | Line. |
| `ui.circle(cx, cy, r, color [, alpha])` | Filled circle. |
| `ui.ring(cx, cy, r, thickness, color [, alpha])` | Ring; `r` is the outer radius. |
| `ui.arc(cx, cy, r, thickness, from, to, color [, alpha])` | Part of a ring. Angles in degrees, 0 = 12 o'clock, clockwise. |
| `ui.pie(cx, cy, r, from, to, color [, alpha])` | Filled sector, same angles. |
| `ui.radial(cx, cy, rx, ry, centre, rim [, alpha_centre, alpha_rim])` | Radial glow / vignette (rim alpha defaults to 0). |
| `ui.clip(x, y, w, h)` / `ui.clip()` | Clip what follows to a rectangle / stop clipping. |
| `ui.vignette(cx, cy, rx, ry, inner, color [, alpha])` | Paints everything outside a soft ellipse (clear up to `inner` x radius, fading to the rim). Clip it to a box: fog of war, spotlights. |
| `store.get(key)` / `store.set(key, value)` | Small per-package memory (numbers or strings; `nil` removes), kept in `PSP/SYSTEM/companion/<package>.txt`. Written on every change, so use it for user choices, not per-frame data. |
| `mem.u8/u16/u32/s8/s16/s32/f32(addr)` | Guest memory reads; `nil` if the address isn't valid. |
| `mem.ptr(addr)` | The u32 at `addr` if it points into PSP RAM, else `nil`. |
| `mem.str(addr [, max])` | Zero-terminated string. |
| `mem.w8/w16/w32(addr, value)` | Guest memory writes, returns true if written. Selector-type writes only; anything that changes the pouch or box must make a save backup first. |
| `mem.code_patch(addr, value, {allowed})` | Keeps a word of the game's **code** at `value`, applied on the emulator thread at the next vblank (JIT block invalidated first). All patches are all-or-nothing: if any patched word holds a value not in its `allowed` list (another game version), none are written. |
| `mem.code_status(addr)` | `"pending"`, `"applied"` or `"unknown"` (left alone), plus the instruction last read there; `nil` if never requested. |
| `pad.press(name [, delay [, hold]])` | Presses a PSP button for the game: `"square"`, `"triangle"`, `"circle"` or `"cross"`. It goes down after `delay` vblanks (0..60, default 0) and is held for `hold` vblanks (1..30, default 4), on the emulator thread. One press at a time: returns false if one is still running. Released when the package unloads. |
| `pad.busy()` | True while a `pad.press` is waiting or held. |
| `include(file)` | Runs another Lua file from the same package and returns its results. |
| `log(...)`, `print(...)` | Logcat, tag `ThorCompanion`, and the in-app log (below). |
| `logs.lines()` | The in-app log, oldest first: up to 300 entries `{ time = "HH:MM:SS", text, err }`. Holds `log()` lines, engine errors (`err = true`) and "Package loaded in X ms". |
| `logs.clear()` | Empties the in-app log. |
| `logs.stats()` | The `ui.stats` line as a string (redraws, Lua ms per frame, Lua memory), for copying. |
| `ui.copy(text)` | Puts `text` (up to 256 KB) on the Android clipboard, right after the current frame or touch. |
| `ui.request(name)` | 7n: asks the app for something only it can do, right after the current frame or touch. `"minimize"` closes the bottom-screen window (a floating restore button appears when "Display over other apps" is allowed; otherwise the window stays, and the package draws its own minimized screen); `"restore"` reopens it; `"overlay_settings"` opens the "Display over other apps" page. When the button is tapped, the app calls `on_press("restore")`; when the permission is missing on the first minimize, it calls `on_press("min_ask")`. |

Libraries: base, table, string, math, utf8. No io, os, require, load or debug.

## Images

Images are decoded the first time a package uses them and kept until the game closes; the GPU copy is made on
first draw. Decoding time doesn't count against the 100 ms script budget. The bottom screen uses 4x MSAA, so shapes
and rotated sprites have smooth edges.

## Errors

- **The package fails to load** (syntax error, missing file): the bottom screen shows the error with file and line.
- **`frame()` errors:** the error is shown and logged once; the package keeps trying every frame, so a temporary
  problem (for example memory not ready while the game loads) clears by itself.
- **A callback runs longer than 100 ms:** the package is stopped until the game is restarted, so a stuck
  script can't freeze the app.
