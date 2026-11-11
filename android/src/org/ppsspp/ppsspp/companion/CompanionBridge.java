package org.ppsspp.ppsspp.companion;

/**
 * Thor Companion: native calls into PPSSPP's core (Companion/CompanionJni.cpp, Companion/CompanionEngine.cpp).
 * The native library is already loaded by PpssppActivity.
 */
public final class CompanionBridge {
	private CompanionBridge() {}

	/** Disc / product ID of the running game (e.g. "ULJM05500"), or "" when no game is running. */
	public static native String gameId();
	public static native String gameTitle();

	public static native long readU32(long address);
	public static native int readU16(long address);
	public static native int readU8(long address);

	// M5 step 2: the GPU-drawn bottom screen
	/** True when a companion exists for the running game. */
	public static native boolean hasCompanion();
	/** Reads the game (UI thread, ~30x/s). True when the bottom screen needs a redraw. */
	public static native boolean engineUpdate();
	/** GL thread of the bottom screen. */
	public static native void glCreated();
	public static native void glChanged(int width, int height);
	public static native void glDraw();
	/** Touch in logical units (540 wide). action 0 down, 1 up, 2 move, 3 cancel. True when a redraw is needed. */
	public static native boolean touch(int action, float x, float y);
	/** Step 4d-3: text the package asked to copy (ui.copy) as UTF-8, or null. Clears it. */
	public static native byte[] takeClipboard();

	// 7n: minimize the bottom screen
	/** The next ui.request(name) from the package ("minimize", "restore", "overlay_settings"), or null. */
	public static native String takeRequest();
	/** Calls the package's on_press(id) as if that button was tapped (the floating restore button). */
	public static native boolean press(String id);
	/** A Java line for logcat and the in-app log (Logs screen). */
	public static native void log(String text);
}
