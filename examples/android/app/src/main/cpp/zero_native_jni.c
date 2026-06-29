#include <jni.h>
#include <stdint.h>
#include <string.h>

#include "zero_native.h"

JNIEXPORT jlong JNICALL Java_dev_zero_1native_examples_android_MainActivity_nativeCreate(JNIEnv *env, jobject self) {
    (void)env;
    (void)self;
    return (jlong)zero_native_app_create();
}

JNIEXPORT void JNICALL Java_dev_zero_1native_examples_android_MainActivity_nativeDestroy(JNIEnv *env, jobject self, jlong app) {
    (void)env;
    (void)self;
    zero_native_app_destroy((void *)app);
}

JNIEXPORT void JNICALL Java_dev_zero_1native_examples_android_MainActivity_nativeStart(JNIEnv *env, jobject self, jlong app) {
    (void)env;
    (void)self;
    zero_native_app_start((void *)app);
}

JNIEXPORT void JNICALL Java_dev_zero_1native_examples_android_MainActivity_nativeActivate(JNIEnv *env, jobject self, jlong app) {
    (void)env;
    (void)self;
    zero_native_app_activate((void *)app);
}

JNIEXPORT void JNICALL Java_dev_zero_1native_examples_android_MainActivity_nativeDeactivate(JNIEnv *env, jobject self, jlong app) {
    (void)env;
    (void)self;
    zero_native_app_deactivate((void *)app);
}

JNIEXPORT void JNICALL Java_dev_zero_1native_examples_android_MainActivity_nativeStop(JNIEnv *env, jobject self, jlong app) {
    (void)env;
    (void)self;
    zero_native_app_stop((void *)app);
}

JNIEXPORT void JNICALL Java_dev_zero_1native_examples_android_MainActivity_nativeResize(JNIEnv *env, jobject self, jlong app, jfloat width, jfloat height, jfloat scale, jobject surface) {
    (void)env;
    (void)self;
    zero_native_app_resize((void *)app, width, height, scale, surface);
}

JNIEXPORT void JNICALL Java_dev_zero_1native_examples_android_MainActivity_nativeViewport(JNIEnv *env, jobject self, jlong app, jfloat width, jfloat height, jfloat scale, jobject surface, jfloat safe_top, jfloat safe_right, jfloat safe_bottom, jfloat safe_left, jfloat keyboard_top, jfloat keyboard_right, jfloat keyboard_bottom, jfloat keyboard_left) {
    (void)env;
    (void)self;
    zero_native_app_viewport((void *)app, width, height, scale, surface, safe_top, safe_right, safe_bottom, safe_left, keyboard_top, keyboard_right, keyboard_bottom, keyboard_left);
}

JNIEXPORT void JNICALL Java_dev_zero_1native_examples_android_MainActivity_nativeTouch(JNIEnv *env, jobject self, jlong app, jlong id, jint phase, jfloat x, jfloat y, jfloat pressure) {
    (void)env;
    (void)self;
    zero_native_app_touch((void *)app, (uint64_t)id, phase, x, y, pressure);
}

JNIEXPORT void JNICALL Java_dev_zero_1native_examples_android_MainActivity_nativeKey(JNIEnv *env, jobject self, jlong app, jint phase, jstring key, jstring text, jint modifiers) {
    (void)self;
    const char *key_chars = key ? (*env)->GetStringUTFChars(env, key, NULL) : NULL;
    const char *text_chars = text ? (*env)->GetStringUTFChars(env, text, NULL) : NULL;
    zero_native_app_key((void *)app, phase, key_chars, key_chars ? strlen(key_chars) : 0, text_chars, text_chars ? strlen(text_chars) : 0, (uint32_t)modifiers);
    if (key_chars) (*env)->ReleaseStringUTFChars(env, key, key_chars);
    if (text_chars) (*env)->ReleaseStringUTFChars(env, text, text_chars);
}

JNIEXPORT void JNICALL Java_dev_zero_1native_examples_android_MainActivity_nativeText(JNIEnv *env, jobject self, jlong app, jstring text) {
    (void)self;
    const char *text_chars = (*env)->GetStringUTFChars(env, text, NULL);
    if (!text_chars) return;
    zero_native_app_text((void *)app, text_chars, strlen(text_chars));
    (*env)->ReleaseStringUTFChars(env, text, text_chars);
}

JNIEXPORT void JNICALL Java_dev_zero_1native_examples_android_MainActivity_nativeIme(JNIEnv *env, jobject self, jlong app, jint kind, jstring text, jlong cursor) {
    (void)self;
    const char *text_chars = text ? (*env)->GetStringUTFChars(env, text, NULL) : NULL;
    zero_native_app_ime((void *)app, kind, text_chars, text_chars ? strlen(text_chars) : 0, (intptr_t)cursor);
    if (text_chars) (*env)->ReleaseStringUTFChars(env, text, text_chars);
}

JNIEXPORT jint JNICALL Java_dev_zero_1native_examples_android_MainActivity_nativeCommand(JNIEnv *env, jobject self, jlong app, jstring command) {
    (void)self;
    const char *command_chars = (*env)->GetStringUTFChars(env, command, NULL);
    if (!command_chars) return 0;
    zero_native_app_command((void *)app, command_chars, strlen(command_chars));
    (*env)->ReleaseStringUTFChars(env, command, command_chars);
    return (jint)zero_native_app_last_command_count((void *)app);
}

JNIEXPORT void JNICALL Java_dev_zero_1native_examples_android_MainActivity_nativeFrame(JNIEnv *env, jobject self, jlong app) {
    (void)env;
    (void)self;
    zero_native_app_frame((void *)app);
}
