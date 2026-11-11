package org.ppsspp.ppsspp.companion;

import android.annotation.SuppressLint;
import android.app.Activity;
import android.app.Presentation;
import android.content.ClipData;
import android.content.ClipboardManager;
import android.content.Context;
import android.content.Intent;
import android.graphics.Canvas;
import android.graphics.Paint;
import android.graphics.Path;
import android.graphics.PixelFormat;
import android.graphics.Rect;
import android.graphics.RectF;
import android.net.Uri;
import android.provider.Settings;
import android.util.DisplayMetrics;
import android.view.Gravity;
import android.view.View;
import android.view.WindowManager;
import android.hardware.display.DisplayManager;
import android.opengl.GLSurfaceView;
import android.os.Build;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.util.Log;
import android.view.Display;
import android.view.MotionEvent;
import android.window.OnBackInvokedDispatcher;

import javax.microedition.khronos.egl.EGL10;
import javax.microedition.khronos.egl.EGLConfig;
import javax.microedition.khronos.egl.EGLDisplay;
import javax.microedition.khronos.opengles.GL10;

/**
 * Thor Companion (M5 steps 2–4a).
 *
 * While PPSSPP is in the foreground, checks ~30 times a second whether the running game has a companion. If so, a
 * window opens on the Thor's other (bottom) screen with its own OpenGL ES surface, drawn by the C++ engine
 * (Companion/CompanionEngine.cpp). The surface only redraws when the engine reports a change or a touch needs it.
 * With no matching game the bottom screen is left alone (normal PPSSPP).
 *
 * The bottom screen's GL context is separate from PPSSPP's renderer (OpenGL or Vulkan), so they don't interfere.
 */
public final class ThorCompanion {
	private static final String TAG = "ThorCompanion";
	private static final long TICK_MS = 33;
	static final float LOGICAL_WIDTH = 540f;

	private static Activity activity;
	private static CompanionScreen screen;
	private static boolean running;
	private static final Handler handler = new Handler(Looper.getMainLooper());
	private static String lastLogged = "";

	// 7n: minimize. While minimized the bottom-screen window stays closed (the package keeps running, so the HUD
	// rule on the main screen holds) and a small floating restore button sits in the bottom screen's top-right
	// corner. Without the "Display over other apps" permission the window stays open and the package draws its
	// own black minimized screen with a restore tab. Not saved: a fresh start always shows the companion.
	private static boolean minimized;
	private static boolean askedThisRun;
	private static View overlayView;
	private static WindowManager overlayWm;

	private ThorCompanion() {}

	public static void onResume(Activity a) {
		activity = a;
		running = true;
		handler.removeCallbacks(tick);
		handler.post(tick);
		jlog("PPSSPP resumed (onResume)" + (minimized ? ", companion minimized" : ""));
	}

	public static void onPause() {
		running = false;
		handler.removeCallbacks(tick);
		close();
		jlog("PPSSPP paused (onPause)" + (minimized ? ", companion minimized" : ""));
	}

	public static void onDestroy() {
		onPause();
		removeOverlay();
		minimized = false;
		activity = null;
	}

	/** 7n: log lines only, to see what Android does to PPSSPP while another app runs on the bottom screen. */
	public static void onFocus(boolean hasFocus) {
		jlog("PPSSPP window focus " + (hasFocus ? "gained" : "lost") + (minimized ? " (companion minimized)" : ""));
	}

	public static void onTopResumed(boolean isTop) {
		jlog("PPSSPP " + (isTop ? "is the top app again" : "is no longer the top app")
			+ (minimized ? " (companion minimized)" : ""));
	}

	private static void jlog(String text) {
		// the native side writes it to logcat and the Logs screen; logcat directly only if that fails (7n2: no doubles)
		try { CompanionBridge.log(text); } catch (Throwable t) { Log.i(TAG, text); }
	}

	private static final Runnable tick = new Runnable() {
		@Override public void run() {
			if (!running) return;
			try {
				update();
			} catch (Throwable t) {
				Log.e(TAG, "update failed", t);
			}
			handler.postDelayed(this, TICK_MS);
		}
	};

	private static void update() {
		boolean supported = CompanionBridge.hasCompanion();
		String id = CompanionBridge.gameId();
		String state = id.isEmpty() ? "no game" : (supported ? "companion for " + id : id + " has no companion");
		if (!state.equals(lastLogged)) { Log.i(TAG, state); lastLogged = state; }
		if (!supported) {
			close();
			if (minimized || overlayView != null) { removeOverlay(); minimized = false; }
			return;
		}
		if (minimized && overlayView == null && canOverlay() && showOverlay()) {   // permission granted meanwhile
			close();
			jlog("Minimized (overlay ok)");
		}
		if (minimized && overlayView != null) {   // window closed: keep the package running (HUD rule, logs)
			CompanionBridge.engineUpdate();
			afterCallback();
			return;
		}
		if (screen == null && !open()) return;
		if (CompanionBridge.engineUpdate()) screen.redraw();
		afterCallback();
	}

	/** After every call into the package: the clipboard, then its requests (7n). */
	private static void afterCallback() {
		copyIfAsked();
		String r;
		int guard = 0;
		while (guard++ < 16 && (r = CompanionBridge.takeRequest()) != null) handleRequest(r);
	}

	private static void handleRequest(String r) {
		switch (r) {
			case "minimize":
				if (minimized) return;
				minimized = true;
				if (canOverlay() && showOverlay()) {
					close();
					jlog("Minimized (overlay ok)");
				} else {
					jlog("Minimized (fallback: black screen, no \"Display over other apps\" permission)");
					if (!askedThisRun) {
						askedThisRun = true;
						CompanionBridge.press("min_ask");
						afterCallback();
					}
					if (screen != null) screen.redraw();
				}
				break;
			case "restore":
				if (!minimized) return;
				minimized = false;
				removeOverlay();
				jlog("Restored");
				// the next tick reopens the window (ticks only run while PPSSPP is resumed)
				break;
			case "overlay_settings":
				openOverlaySettings();
				break;
			default:
				jlog("Unknown ui.request: " + r);
		}
	}

	private static boolean canOverlay() {
		return activity != null && Build.VERSION.SDK_INT >= 26 && Settings.canDrawOverlays(activity);
	}

	/**
	 * The "Display over other apps" page for this app. It opens on the main screen (over the game, which pauses):
	 * the bottom-screen window would sit on top of it there. Back returns to the game, and the next tick sees
	 * the permission and switches to the floating button.
	 */
	private static void openOverlaySettings() {
		if (activity == null) return;
		Intent i = new Intent(Settings.ACTION_MANAGE_OVERLAY_PERMISSION, Uri.parse("package:" + activity.getPackageName()));
		try {
			activity.startActivity(i);
			jlog("Opened the \"Display over other apps\" setting");
		} catch (Throwable t) {
			Log.e(TAG, "Could not open the overlay setting", t);
			jlog("Could not open the \"Display over other apps\" setting: " + t);
		}
	}

	/** 7n: the floating restore button, top-right corner of the bottom screen. */
	@SuppressWarnings("deprecation")
	private static boolean showOverlay() {
		if (overlayView != null) return true;
		if (activity == null || Build.VERSION.SDK_INT < 26) return false;
		Display bottom = otherDisplay(activity);
		if (bottom == null) return false;
		try {
			Context dc = activity.createDisplayContext(bottom);
			Context wc = Build.VERSION.SDK_INT >= 30
				? dc.createWindowContext(WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY, null) : dc;
			WindowManager wm = (WindowManager) wc.getSystemService(Context.WINDOW_SERVICE);
			DisplayMetrics m = new DisplayMetrics();
			bottom.getRealMetrics(m);
			float u = Math.max(1, m.widthPixels) / LOGICAL_WIDTH;   // px per logical unit
			RestoreButton v = new RestoreButton(wc, u);
			int size = Math.round(RestoreButton.BOX * u);
			WindowManager.LayoutParams lp = new WindowManager.LayoutParams(size, size,
				WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY,
				WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE | WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL
					| WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN,
				PixelFormat.TRANSLUCENT);
			lp.gravity = Gravity.TOP | Gravity.END;
			lp.setTitle("Thor Companion restore");
			v.setOnClickListener(x -> {
				jlog("User: floating restore button tapped");
				CompanionBridge.press("restore");
				afterCallback();
			});
			wm.addView(v, lp);
			overlayView = v;
			overlayWm = wm;
			return true;
		} catch (Throwable t) {
			Log.e(TAG, "Could not show the restore button", t);
			jlog("Could not show the floating restore button: " + t);
			return false;
		}
	}

	private static void removeOverlay() {
		if (overlayView != null && overlayWm != null) {
			try { overlayWm.removeView(overlayView); } catch (Throwable ignored) { }
		}
		overlayView = null;
		overlayWm = null;
	}

	/** 7n: a 62-unit box; the 48 x 48 button sits 10 units in from the top and right edges (MHFU frame style). */
	private static final class RestoreButton extends View {
		static final float BOX = 62f, BTN = 48f, INSET = 10f;
		private final float u;
		private final Paint fill = new Paint(Paint.ANTI_ALIAS_FLAG);
		private final Paint frame = new Paint(Paint.ANTI_ALIAS_FLAG);
		private final Paint icon = new Paint(Paint.ANTI_ALIAS_FLAG);
		private final Paint stud = new Paint(Paint.ANTI_ALIAS_FLAG);
		private boolean down;

		RestoreButton(Context c, float u) {
			super(c);
			this.u = u;
			fill.setStyle(Paint.Style.FILL);
			frame.setStyle(Paint.Style.STROKE);
			frame.setStrokeWidth(2 * u);
			frame.setColor(0xFFB08A52);
			icon.setStyle(Paint.Style.STROKE);
			icon.setStrokeWidth(2.2f * u);
			icon.setStrokeCap(Paint.Cap.ROUND);
			icon.setStrokeJoin(Paint.Join.ROUND);
			icon.setColor(0xFFF6D38A);
			stud.setStyle(Paint.Style.FILL);
			stud.setColor(0xFFF6D38A);
			setContentDescription("Restore the companion");
			setClickable(true);
		}

		@SuppressLint("ClickableViewAccessibility")
		@Override public boolean onTouchEvent(MotionEvent e) {
			switch (e.getActionMasked()) {
				case MotionEvent.ACTION_DOWN: down = true; invalidate(); break;
				case MotionEvent.ACTION_UP: case MotionEvent.ACTION_CANCEL: down = false; invalidate(); break;
				default: break;
			}
			return super.onTouchEvent(e);
		}

		@Override protected void onDraw(Canvas c) {
			float x = (BOX - INSET - BTN) * u, y = INSET * u, s = BTN * u;
			fill.setColor(down ? 0xEB2A3442 : 0xEB111A26);   // navy at 92%
			c.drawRoundRect(new RectF(x, y, x + s, y + s), 4 * u, 4 * u, fill);
			float h = u;   // half the frame stroke
			c.drawRoundRect(new RectF(x + h, y + h, x + s - h, y + s - h), 4 * u, 4 * u, frame);
			float d = 2.2f * u;   // corner studs
			c.drawCircle(x + 5 * u, y + 5 * u, d, stud);
			c.drawCircle(x + s - 5 * u, y + 5 * u, d, stud);
			c.drawCircle(x + 5 * u, y + s - 5 * u, d, stud);
			c.drawCircle(x + s - 5 * u, y + s - 5 * u, d, stud);
			// the restore icon: a window outline with an up chevron (24-unit icon drawn 26 units wide)
			float k = 26f / 24f * u, ix = x + (s - 26 * u) / 2, iy = y + (s - 26 * u) / 2;
			c.drawRect(ix + 4 * k, iy + 4 * k, ix + 20 * k, iy + 20 * k, icon);
			Path p = new Path();
			p.moveTo(ix + 8 * k, iy + 14 * k);
			p.lineTo(ix + 12 * k, iy + 10 * k);
			p.lineTo(ix + 16 * k, iy + 14 * k);
			c.drawPath(p, icon);
		}
	}

	/** Step 4d-3: ui.copy(text) from the package goes on the Android clipboard (for bug reports). */
	private static void copyIfAsked() {
		byte[] bytes = CompanionBridge.takeClipboard();
		if (bytes == null || activity == null) return;
		try {
			String text = new String(bytes, java.nio.charset.StandardCharsets.UTF_8);
			ClipboardManager cm = (ClipboardManager) activity.getSystemService(Context.CLIPBOARD_SERVICE);
			cm.setPrimaryClip(ClipData.newPlainText("M&M PSP logs", text));
			Log.i(TAG, "Copied " + text.length() + " characters to the clipboard");
		} catch (Throwable t) {
			Log.e(TAG, "Copy to clipboard failed", t);
		}
	}

	private static boolean open() {
		if (activity == null) return false;
		Display bottom = otherDisplay(activity);
		if (bottom == null) return false;
		try {
			screen = new CompanionScreen(activity, bottom);
			screen.show();
			Log.i(TAG, "Opened on display " + bottom.getDisplayId() + " (" + bottom.getName() + ")");
			return true;
		} catch (Throwable t) {
			Log.e(TAG, "Could not open the bottom screen", t);
			screen = null;
			return false;
		}
	}

	private static void close() {
		if (screen != null) {
			try { screen.dismiss(); } catch (Throwable ignored) { }
			screen = null;
		}
	}

	/** The display that is not the one PPSSPP itself runs on (on the Thor: the bottom screen). */
	@SuppressWarnings("deprecation")
	private static Display otherDisplay(Activity a) {
		DisplayManager dm = (DisplayManager) a.getSystemService(Context.DISPLAY_SERVICE);
		int mine = a.getWindowManager().getDefaultDisplay().getDisplayId();
		for (Display d : dm.getDisplays()) {
			if (d.getDisplayId() != mine) return d;
		}
		return null;
	}

	/** Picks an RGB888 ES2 config with 4x MSAA (smooth circles, arcs and rotated sprites); falls back to no MSAA. */
	private static final class MultisampleConfigChooser implements GLSurfaceView.EGLConfigChooser {
		private static final int EGL_OPENGL_ES2_BIT = 4;

		@Override public EGLConfig chooseConfig(EGL10 egl, EGLDisplay display) {
			EGLConfig c = choose(egl, display, 4);
			if (c == null) c = choose(egl, display, 0);
			if (c == null) throw new IllegalArgumentException("No usable EGL config for the bottom screen");
			return c;
		}

		private static EGLConfig choose(EGL10 egl, EGLDisplay display, int samples) {
			int[] attribs = samples > 0
				? new int[] { EGL10.EGL_RED_SIZE, 8, EGL10.EGL_GREEN_SIZE, 8, EGL10.EGL_BLUE_SIZE, 8,
					EGL10.EGL_RENDERABLE_TYPE, EGL_OPENGL_ES2_BIT, EGL10.EGL_SAMPLE_BUFFERS, 1, EGL10.EGL_SAMPLES, samples, EGL10.EGL_NONE }
				: new int[] { EGL10.EGL_RED_SIZE, 8, EGL10.EGL_GREEN_SIZE, 8, EGL10.EGL_BLUE_SIZE, 8,
					EGL10.EGL_RENDERABLE_TYPE, EGL_OPENGL_ES2_BIT, EGL10.EGL_NONE };
			int[] num = new int[1];
			EGLConfig[] configs = new EGLConfig[1];
			if (!egl.eglChooseConfig(display, attribs, configs, 1, num) || num[0] < 1) return null;
			return configs[0];
		}
	}

	/** The bottom-screen window: one GLSurfaceView drawn by the C++ engine, redrawn only on demand. */
	private static final class CompanionScreen extends Presentation {
		private GLSurfaceView view;

		CompanionScreen(Context outer, Display display) {
			super(outer, display);
		}

		/** 7c2: Back (a side swipe on the bottom screen) does nothing here; it used to close this window. */
		@SuppressWarnings("deprecation")
		@Override public void onBackPressed() { }

		@SuppressLint("ClickableViewAccessibility")
		@Override protected void onCreate(Bundle savedInstanceState) {
			super.onCreate(savedInstanceState);
			// 7c2: a Presentation is a dialog, and Back closes a dialog. Make Back do nothing on the bottom screen
			// (Back on the top screen still goes to PPSSPP as before).
			setCancelable(false);
			setCanceledOnTouchOutside(false);
			if (Build.VERSION.SDK_INT >= 33) {
				getOnBackInvokedDispatcher().registerOnBackInvokedCallback(
					OnBackInvokedDispatcher.PRIORITY_OVERLAY, () -> { });
			}
			// If the system closes this window anyway, forget it so the next tick opens a new one.
			setOnDismissListener(d -> { if (screen == this) screen = null; });
			view = new GLSurfaceView(getContext());
			view.setEGLContextClientVersion(2);
			view.setEGLConfigChooser(new MultisampleConfigChooser());
			view.setPreserveEGLContextOnPause(true);
			view.setRenderer(new GLSurfaceView.Renderer() {
				@Override public void onSurfaceCreated(GL10 gl, EGLConfig config) { CompanionBridge.glCreated(); }
				@Override public void onSurfaceChanged(GL10 gl, int w, int h) { CompanionBridge.glChanged(w, h); }
				@Override public void onDrawFrame(GL10 gl) { CompanionBridge.glDraw(); }
			});
			view.setRenderMode(GLSurfaceView.RENDERMODE_WHEN_DIRTY);
			view.setOnTouchListener((v, e) -> {
				int action;
				switch (e.getActionMasked()) {
					case MotionEvent.ACTION_DOWN: action = 0; break;
					case MotionEvent.ACTION_UP: action = 1; break;
					case MotionEvent.ACTION_MOVE: action = 2; break;
					default: action = 3; break;
				}
				float k = LOGICAL_WIDTH / Math.max(1, v.getWidth());
				if (CompanionBridge.touch(action, e.getX() * k, e.getY() * k)) view.requestRender();
				afterCallback();
				return true;
			});
			setContentView(view);
			// 7c2: keep the edge back-swipe off the middle of both sides, so a touch there reaches the panels.
			// Android honours at most 200 dp per edge, so it's a 200 dp strip centred on each side.
			if (Build.VERSION.SDK_INT >= 29) {
				view.addOnLayoutChangeListener((v, l, t, r, b, ol, ot, or, ob) -> {
					float dp = v.getResources().getDisplayMetrics().density;
					int w = v.getWidth(), h = v.getHeight();
					int edge = Math.round(48 * dp), tall = Math.min(h, Math.round(200 * dp));
					int top = (h - tall) / 2;
					v.setSystemGestureExclusionRects(java.util.Arrays.asList(
						new Rect(0, top, edge, top + tall), new Rect(w - edge, top, w, top + tall)));
				});
			}
		}

		void redraw() {
			if (view != null) view.requestRender();
		}

		@Override protected void onStop() {
			if (view != null) view.onPause();
			super.onStop();
		}
	}
}
