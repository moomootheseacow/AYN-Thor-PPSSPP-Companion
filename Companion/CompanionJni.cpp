// Thor Companion (M5 step 1): the small bridge between PPSSPP's emulator core and the bottom-screen companion.
// Read-only for now: the running game's ID and title, and guest-memory reads guarded by an address check.
// Everything companion-specific lives under Companion/ (native) and android/src/org/ppsspp/ppsspp/companion (Java),
// so moving to a newer PPSSPP release means re-applying only a few small hooks.

#include <jni.h>
#include <string>

#include "Core/System.h"
#include "Core/MemMap.h"
#include "Core/ELF/ParamSFO.h"

static bool CompanionGameRunning() {
	return PSP_IsInited();
}

extern "C" JNIEXPORT jstring JNICALL
Java_org_ppsspp_ppsspp_companion_CompanionBridge_gameId(JNIEnv *env, jclass) {
	std::string id = CompanionGameRunning() ? g_paramSFO.GetDiscID() : std::string();
	return env->NewStringUTF(id.c_str());
}

extern "C" JNIEXPORT jstring JNICALL
Java_org_ppsspp_ppsspp_companion_CompanionBridge_gameTitle(JNIEnv *env, jclass) {
	std::string t = CompanionGameRunning() ? g_paramSFO.GetValueString("TITLE") : std::string();
	return env->NewStringUTF(t.c_str());
}

// Returns -1 (as a long) when no game is running or the address is outside PSP memory.
extern "C" JNIEXPORT jlong JNICALL
Java_org_ppsspp_ppsspp_companion_CompanionBridge_readU32(JNIEnv *, jclass, jlong address) {
	u32 a = (u32)address;
	if (!CompanionGameRunning() || !Memory::IsValidRange(a, 4)) return -1;
	return (jlong)Memory::ReadUnchecked_U32(a);
}

extern "C" JNIEXPORT jint JNICALL
Java_org_ppsspp_ppsspp_companion_CompanionBridge_readU16(JNIEnv *, jclass, jlong address) {
	u32 a = (u32)address;
	if (!CompanionGameRunning() || !Memory::IsValidRange(a, 2)) return -1;
	return (jint)Memory::ReadUnchecked_U16(a);
}

extern "C" JNIEXPORT jint JNICALL
Java_org_ppsspp_ppsspp_companion_CompanionBridge_readU8(JNIEnv *, jclass, jlong address) {
	u32 a = (u32)address;
	if (!CompanionGameRunning() || !Memory::IsValidRange(a, 1)) return -1;
	return (jint)Memory::ReadUnchecked_U8(a);
}

// ---- M5 step 2: the GPU-drawn bottom screen (Companion/CompanionEngine.cpp)
#include "Companion/CompanionEngine.h"

extern "C" JNIEXPORT jboolean JNICALL
Java_org_ppsspp_ppsspp_companion_CompanionBridge_hasCompanion(JNIEnv *, jclass) {
	return Companion::HasCompanionForRunningGame();
}

extern "C" JNIEXPORT jboolean JNICALL
Java_org_ppsspp_ppsspp_companion_CompanionBridge_engineUpdate(JNIEnv *, jclass) {
	return Companion::Update();
}

extern "C" JNIEXPORT void JNICALL
Java_org_ppsspp_ppsspp_companion_CompanionBridge_glCreated(JNIEnv *, jclass) {
	Companion::GlSurfaceCreated();
}

extern "C" JNIEXPORT void JNICALL
Java_org_ppsspp_ppsspp_companion_CompanionBridge_glChanged(JNIEnv *, jclass, jint w, jint h) {
	Companion::GlSurfaceChanged(w, h);
}

extern "C" JNIEXPORT void JNICALL
Java_org_ppsspp_ppsspp_companion_CompanionBridge_glDraw(JNIEnv *, jclass) {
	Companion::GlDraw();
}

extern "C" JNIEXPORT jboolean JNICALL
Java_org_ppsspp_ppsspp_companion_CompanionBridge_touch(JNIEnv *, jclass, jint action, jfloat x, jfloat y) {
	return Companion::Touch(action, x, y);
}

// ---- step 4d-3: ui.copy -> Android clipboard. Returns null when nothing is waiting.
// Bytes (UTF-8), decoded on the Java side: NewStringUTF would abort on text that isn't modified UTF-8.
extern "C" JNIEXPORT jbyteArray JNICALL
Java_org_ppsspp_ppsspp_companion_CompanionBridge_takeClipboard(JNIEnv *env, jclass) {
	std::string text;
	if (!Companion::TakeClipboard(&text)) return nullptr;
	jbyteArray arr = env->NewByteArray((jsize)text.size());
	if (arr) env->SetByteArrayRegion(arr, 0, (jsize)text.size(), (const jbyte *)text.data());
	return arr;
}

// ---- 7n: minimize the bottom screen. ui.request -> Java, a press from the floating button, Java log lines.
static std::string JStr(JNIEnv *env, jstring s) {
	if (!s) return std::string();
	const char *c = env->GetStringUTFChars(s, nullptr);
	std::string out = c ? c : "";
	if (c) env->ReleaseStringUTFChars(s, c);
	return out;
}

extern "C" JNIEXPORT jstring JNICALL
Java_org_ppsspp_ppsspp_companion_CompanionBridge_takeRequest(JNIEnv *env, jclass) {
	std::string r;
	if (!Companion::TakeRequest(&r)) return nullptr;
	return env->NewStringUTF(r.c_str());
}

extern "C" JNIEXPORT jboolean JNICALL
Java_org_ppsspp_ppsspp_companion_CompanionBridge_press(JNIEnv *env, jclass, jstring id) {
	return Companion::Press(JStr(env, id));
}

extern "C" JNIEXPORT void JNICALL
Java_org_ppsspp_ppsspp_companion_CompanionBridge_log(JNIEnv *env, jclass, jstring text) {
	Companion::JavaLog(JStr(env, text));
}
