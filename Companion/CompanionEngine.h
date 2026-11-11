// Thor Companion engine (M5 step 3).
//
// The engine is game-agnostic. Each supported game is a Lua package bundled in the APK under
// assets/companion/<package>/ (manifest.lua lists its game IDs, main.lua draws the bottom screen).
// When the running game's ID matches a manifest, that package is loaded and drives the bottom screen.
// With no match the bottom screen is left alone (normal PPSSPP).
//
// Threads: everything Lua runs on the Android main (UI) thread (Update, Touch, HasCompanionForRunningGame).
// The GL thread only replays the last published draw list (CompanionRenderer.cpp).
#pragma once

#include <string>

namespace Companion {

// Main thread, ~30x per second. Loads / unloads packages when the running game changes.
// True when a package exists for the running game.
bool HasCompanionForRunningGame();

// Main thread, ~30x per second: runs the package's frame(). True when the screen needs a redraw.
bool Update();

// Touch in logical units (the screen is 540 units wide). action: 0 down, 1 up, 2 move, 3 cancel.
// Main thread. True when the screen needs a redraw.
bool Touch(int action, float x, float y);

// Main thread: text a package asked to put on the clipboard (ui.copy), or false. Clears it.
bool TakeClipboard(std::string *out);

// 7n: main thread. The next ui.request(name) from the package, or false.
bool TakeRequest(std::string *out);
// 7n: main thread. Calls the package's on_press(id) as if a button with that id was tapped.
bool Press(const std::string &id);
// 7n: main thread. A line from the Java side for logcat and the in-app log.
void JavaLog(const std::string &text);

// GL thread (the bottom screen's own GLSurfaceView / EGL context, separate from PPSSPP's renderer).
void GlSurfaceCreated();
void GlSurfaceChanged(int width, int height);
void GlDraw();

}  // namespace Companion
