// The toolkit-owned Android host: a complete Android application around
// the embed C ABI, in plain Java so `native dev --target android` and
// `native package --target android` compile it with nothing but the JDK
// and the Android SDK's build tools — an app project carries zero host
// code, and everything app-specific (application id, names, icons)
// arrives through the generated manifest and resources. The native half
// lives in android_host.c; the pair is the Android mirror of the iOS
// host (src/platform/ios/uikit_host.m).
//
// Presentation: a SurfaceView shows the CPU reference renderer's pixels,
// copied into the surface's window buffer by the native bridge. A
// Choreographer callback pumps `native_sdk_app_frame` and the canvas
// revision gates re-presents, so unchanged frames cost one JNI call.
//
// Input: single-pointer touch sequences forward through the embed
// touch/scroll exports in density-independent points. The touch-slop
// state machine mirrors the iOS host (and UIScrollView's delayed content
// touches): an under-slop touch is a tap, an over-slop move over a
// scrollable widget pans it through wheel-style scroll deltas, and an
// over-slop move elsewhere becomes a pointer drag so sliders and text
// selection keep desktop semantics.
//
// The soft keyboard keys off the embed focus/IME-intent state: while an
// editable text widget owns focus the canvas view holds Android input
// focus and InputMethodManager shows the keyboard; when focus leaves it
// hides. Committed text flows through `native_sdk_app_text` and IME
// composition (setComposingText / finishComposingText) maps onto the
// same `native_sdk_app_ime` set/commit/cancel path the desktop hosts
// drive. Keyboard overlap reports through the viewport's keyboard
// insets: the window stays edge-to-edge (the decor never resizes), the
// IME inset arrives via WindowInsets, and the runtime insets layout by
// the keyboard's residual overlap beyond the safe area.
//
// Layout: display cutout and system-bar insets report as the viewport's
// safe area, which the embed host republishes over the window-chrome
// channel — apps pad via `on_chrome` exactly as they do for the macOS
// titlebar band, and apps without the hook keep the automatic runtime
// inset. Rotation keeps the activity (the manifest claims configChanges)
// so the embedded runtime survives with a resize instead of a restart.
//
// Text metrics: the host registers a Paint-backed measure callback
// before start — the Android mirror of the iOS host's CoreText callback —
// so layout uses real typographic widths instead of the deterministic
// estimator. Launch with the `estimator-text-metrics` boolean extra to
// keep the estimator (before/after comparisons, deterministic goldens).

package dev.native_sdk.host;

import android.app.Activity;
import android.content.res.AssetManager;
import android.graphics.Paint;
import android.graphics.Typeface;
import android.os.Bundle;
import android.text.InputType;
import android.util.LruCache;
import android.view.Choreographer;
import android.view.KeyEvent;
import android.view.MotionEvent;
import android.view.SurfaceHolder;
import android.view.SurfaceView;
import android.view.ViewConfiguration;
import android.view.WindowInsets;
import android.view.WindowManager;
import android.view.inputmethod.BaseInputConnection;
import android.view.inputmethod.EditorInfo;
import android.view.inputmethod.InputConnection;
import android.view.inputmethod.InputMethodManager;
import java.io.File;
import java.io.FileOutputStream;
import java.io.InputStream;
import java.io.OutputStream;
import java.nio.ByteBuffer;
import java.nio.charset.CharacterCodingException;
import java.nio.charset.CodingErrorAction;
import java.nio.charset.StandardCharsets;

public final class NativeSdkActivity extends Activity implements SurfaceHolder.Callback, Choreographer.FrameCallback {
    private static final int TOUCH_MODE_IDLE = 0;
    // Touch down seen, under slop: undecided between tap / drag / scroll.
    private static final int TOUCH_MODE_PENDING = 1;
    // Over slop on a scrollable widget: forwarding wheel scroll deltas.
    private static final int TOUCH_MODE_SCROLLING = 2;
    // Over slop elsewhere: forwarded pointer down, forwarding drags.
    private static final int TOUCH_MODE_DRAGGING = 3;

    private static final int TOUCH_PHASE_DOWN = 0;
    private static final int TOUCH_PHASE_UP = 1;
    private static final int TOUCH_PHASE_DRAG = 2;
    private static final int TOUCH_PHASE_CANCEL = 3;

    private static final int KEY_PHASE_DOWN = 0;
    private static final int KEY_PHASE_UP = 1;

    private static final int IME_SET_COMPOSITION = 0;
    private static final int IME_COMMIT_COMPOSITION = 1;
    private static final int IME_CANCEL_COMPOSITION = 2;

    private long nativeApp;
    private CanvasSurfaceView canvasView;
    private boolean surfaceReady;
    private float density = 1f;
    private float safeTop, safeRight, safeBottom, safeLeft;
    private float keyboardBottom;
    private int surfaceWidthPx, surfaceHeightPx;
    private long lastCanvasRevision = -1;
    private boolean hasPresentedRevision;
    private boolean needsPresent;
    private boolean keyboardShown;
    private long focusedTextWidget;
    private final LruCache<String, Double> measureCache = new LruCache<>(16384);
    private final Paint measurePaint = new Paint(Paint.ANTI_ALIAS_FLAG);

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        System.loadLibrary("native_sdk_host");

        // Edge-to-edge: the decor never resizes for system bars, cutouts,
        // or the keyboard — those bands arrive as viewport insets instead,
        // so the embedded runtime owns clearance the same way it does on
        // iOS.
        getWindow().setDecorFitsSystemWindows(false);
        getWindow().getAttributes().layoutInDisplayCutoutMode =
            WindowManager.LayoutParams.LAYOUT_IN_DISPLAY_CUTOUT_MODE_SHORT_EDGES;
        getWindow().setStatusBarColor(android.graphics.Color.TRANSPARENT);
        getWindow().setNavigationBarColor(android.graphics.Color.TRANSPARENT);

        density = getResources().getDisplayMetrics().density;
        canvasView = new CanvasSurfaceView();
        canvasView.getHolder().addCallback(this);
        setContentView(canvasView);

        canvasView.setOnApplyWindowInsetsListener((view, insets) -> {
            android.graphics.Insets bars = insets.getInsets(
                WindowInsets.Type.systemBars() | WindowInsets.Type.displayCutout());
            android.graphics.Insets ime = insets.getInsets(WindowInsets.Type.ime());
            safeTop = bars.top / density;
            safeRight = bars.right / density;
            safeBottom = bars.bottom / density;
            safeLeft = bars.left / density;
            keyboardBottom = ime.bottom / density;
            pushViewport();
            return insets;
        });

        nativeApp = nativeCreate();
        if (nativeApp == 0) {
            android.util.Log.e("native-sdk", "nativeCreate failed");
            finish();
            return;
        }

        // Real text metrics: register the Paint measure callback before
        // start so the installing layout already measures with the fonts
        // presentation would draw with.
        if (getIntent().getBooleanExtra("estimator-text-metrics", false)) {
            android.util.Log.i("native-sdk", "text measure disabled (estimator metrics)");
        } else {
            nativeSetTextMeasure(nativeApp);
        }

        // Verification harness: `am start --ez native-sdk-automation true`
        // publishes snapshot.txt into the app's files dir, same protocol
        // as the desktop -Dautomation=true runners (readable over
        // `adb shell run-as <application id>` for this debuggable host).
        if (getIntent().getBooleanExtra("native-sdk-automation", false)) {
            File dir = new File(getFilesDir(), "native-sdk-automation");
            dir.mkdirs();
            nativeSetAutomationDir(nativeApp, dir.getAbsolutePath());
        }

        // Packaged assets: the APK carries the app's assets under
        // assets/native-sdk; the embed asset root needs a real directory,
        // so mirror them into the files dir once and point the host there.
        String assetRoot = mirrorPackagedAssets();
        if (assetRoot != null) {
            nativeSetAssetRoot(nativeApp, assetRoot);
        }

        nativeStart(nativeApp);
        nativeActivate(nativeApp);
        Choreographer.getInstance().postFrameCallback(this);
    }

    @Override
    protected void onResume() {
        super.onResume();
        if (nativeApp != 0) nativeActivate(nativeApp);
    }

    @Override
    protected void onPause() {
        if (nativeApp != 0) nativeDeactivate(nativeApp);
        super.onPause();
    }

    @Override
    protected void onDestroy() {
        Choreographer.getInstance().removeFrameCallback(this);
        if (nativeApp != 0) {
            nativeStop(nativeApp);
            nativeDestroy(nativeApp);
            nativeApp = 0;
        }
        super.onDestroy();
    }

    // ------------------------------------------------------------ surface

    @Override
    public void surfaceCreated(SurfaceHolder holder) {
    }

    @Override
    public void surfaceChanged(SurfaceHolder holder, int format, int width, int height) {
        if (nativeApp == 0) return;
        nativeSurfaceChanged(nativeApp, holder.getSurface());
        surfaceReady = true;
        surfaceWidthPx = width;
        surfaceHeightPx = height;
        pushViewport();
    }

    @Override
    public void surfaceDestroyed(SurfaceHolder holder) {
        surfaceReady = false;
        if (nativeApp != 0) nativeSurfaceDestroyed(nativeApp);
    }

    // Report the surface size in density-independent points plus the
    // safe-area and keyboard insets; the embed host republishes the safe
    // area over the window-chrome channel and keeps insetting layout by
    // the keyboard's residual overlap beyond it.
    private void pushViewport() {
        if (nativeApp == 0 || !surfaceReady || surfaceWidthPx <= 0 || surfaceHeightPx <= 0) return;
        nativeViewport(nativeApp,
            surfaceWidthPx / density, surfaceHeightPx / density, density,
            safeTop, safeRight, safeBottom, safeLeft,
            0f, 0f, keyboardBottom, 0f);
        needsPresent = true;
    }

    // ------------------------------------------------------------- frames

    @Override
    public void doFrame(long frameTimeNanos) {
        if (nativeApp == 0) return;
        Choreographer.getInstance().postFrameCallback(this);

        // Host-pumped frame: synthesizes the gpu_surface_frame event
        // (first tick installs the widget tree, later ticks re-present).
        nativeFrame(nativeApp);

        // Keyboard show/hide follows the runtime's focus state each tick,
        // not only after forwarded input: focus can also move from key
        // handling or model updates.
        syncTextInput();

        if (!surfaceReady) return;
        long revision = nativeCanvasRevision(nativeApp);
        if (!needsPresent && revision >= 0 && hasPresentedRevision && revision == lastCanvasRevision) return;
        if (nativePresent(nativeApp, density)) {
            if (revision >= 0) {
                lastCanvasRevision = revision;
                hasPresentedRevision = true;
            }
            needsPresent = false;
        }
    }

    // ------------------------------------------- keyboard <-> focus sync

    // Reconcile the platform soft keyboard with the runtime's
    // focus/IME-intent state: keyboard up while an editable text widget
    // owns focus, down when focus leaves — the Android mirror of the iOS
    // host's first-responder sync.
    private void syncTextInput() {
        if (nativeApp == 0 || canvasView == null) return;
        long[] widgetId = new long[1];
        float[] frame = new float[4];
        boolean active = nativeTextInputState(nativeApp, widgetId, frame);
        InputMethodManager input = getSystemService(InputMethodManager.class);
        if (active) {
            boolean widgetChanged = widgetId[0] != focusedTextWidget;
            focusedTextWidget = widgetId[0];
            if (widgetChanged) {
                canvasView.clearComposingState();
                if (keyboardShown) input.restartInput(canvasView);
            }
            if (!keyboardShown) {
                canvasView.requestFocus();
                input.showSoftInput(canvasView, 0);
                keyboardShown = true;
            }
        } else {
            focusedTextWidget = 0;
            if (keyboardShown) {
                canvasView.clearComposingState();
                input.hideSoftInputFromWindow(canvasView.getWindowToken(), 0);
                keyboardShown = false;
            }
        }
    }

    // ------------------------------------------------------- text metrics

    // Paint-backed measure upcall from android_host.c: the typographic
    // width of a single-line run, measured with the same font resolution
    // presentation draws with. Returns a negative value when the bytes
    // are not valid UTF-8 so layout falls back to its estimator.
    @SuppressWarnings("unused") // called from android_host.c
    double measureText(long fontId, double size, byte[] utf8) {
        if (utf8 == null || utf8.length == 0) return 0;
        String text;
        try {
            text = StandardCharsets.UTF_8.newDecoder()
                .onMalformedInput(CodingErrorAction.REPORT)
                .onUnmappableCharacter(CodingErrorAction.REPORT)
                .decode(ByteBuffer.wrap(utf8))
                .toString();
        } catch (CharacterCodingException e) {
            return -1;
        }
        double clamped = Math.max(1, size);
        String key = fontId + "/" + clamped + "/" + text;
        Double cached = measureCache.get(key);
        if (cached != null) return cached;
        measurePaint.setTypeface(typefaceForFontId(fontId));
        measurePaint.setTextSize((float) clamped);
        double width = measurePaint.measureText(text);
        measureCache.put(key, width);
        return width;
    }

    // Resolves a canvas font id to the Typeface measurement uses. Ids 3-6
    // are the reserved sans span variants (medium, bold, italic, bold
    // italic); 2 is mono; everything else keeps the regular sans.
    private static Typeface typefaceForFontId(long fontId) {
        if (fontId == 2) return Typeface.MONOSPACE;
        if (fontId == 3) return Typeface.create(Typeface.DEFAULT, 500, false);
        if (fontId == 4) return Typeface.create(Typeface.DEFAULT, Typeface.BOLD);
        if (fontId == 5) return Typeface.create(Typeface.DEFAULT, Typeface.ITALIC);
        if (fontId == 6) return Typeface.create(Typeface.DEFAULT, Typeface.BOLD_ITALIC);
        return Typeface.DEFAULT;
    }

    // ------------------------------------------------------------- assets

    // Copy the APK's assets/native-sdk tree into files/native-sdk-assets
    // so asset-relative loads resolve against a real directory. Returns
    // null when the app ships no assets.
    private String mirrorPackagedAssets() {
        AssetManager assets = getAssets();
        try {
            String[] entries = assets.list("native-sdk");
            if (entries == null || entries.length == 0) return null;
            File root = new File(getFilesDir(), "native-sdk-assets");
            copyAssetDir(assets, "native-sdk", root);
            return root.getAbsolutePath();
        } catch (Exception e) {
            android.util.Log.e("native-sdk", "asset mirror failed: " + e);
            return null;
        }
    }

    private static void copyAssetDir(AssetManager assets, String path, File dest) throws Exception {
        String[] entries = assets.list(path);
        if (entries == null || entries.length == 0) {
            // A leaf: copy the file bytes.
            File parent = dest.getParentFile();
            if (parent != null) parent.mkdirs();
            try (InputStream in = assets.open(path); OutputStream out = new FileOutputStream(dest)) {
                byte[] buffer = new byte[65536];
                int count;
                while ((count = in.read(buffer)) > 0) out.write(buffer, 0, count);
            }
            return;
        }
        dest.mkdirs();
        for (String entry : entries) {
            copyAssetDir(assets, path + "/" + entry, new File(dest, entry));
        }
    }

    // -------------------------------------------------------- canvas view

    private final class CanvasSurfaceView extends SurfaceView {
        private int touchMode = TOUCH_MODE_IDLE;
        private long touchSequence;
        private float startXPx, startYPx;
        private float lastXPx, lastYPx;
        private final int touchSlopPx;
        private String composingText = "";

        CanvasSurfaceView() {
            super(NativeSdkActivity.this);
            setFocusable(true);
            setFocusableInTouchMode(true);
            touchSlopPx = ViewConfiguration.get(NativeSdkActivity.this).getScaledTouchSlop();
        }

        void clearComposingState() {
            composingText = "";
        }

        private void forwardTouchPhase(int phase, float xPx, float yPx, float pressure) {
            if (nativeApp == 0) return;
            nativeTouch(nativeApp, touchSequence, phase, xPx / density, yPx / density, pressure);
        }

        @Override
        public boolean onTouchEvent(MotionEvent event) {
            if (nativeApp == 0) return false;
            float x = event.getX();
            float y = event.getY();
            switch (event.getActionMasked()) {
                case MotionEvent.ACTION_DOWN:
                    touchSequence += 1;
                    touchMode = TOUCH_MODE_PENDING;
                    startXPx = x;
                    startYPx = y;
                    lastXPx = x;
                    lastYPx = y;
                    return true;
                case MotionEvent.ACTION_MOVE: {
                    if (touchMode == TOUCH_MODE_IDLE) return true;
                    if (touchMode == TOUCH_MODE_PENDING) {
                        float dx = x - startXPx;
                        float dy = y - startYPx;
                        if (dx * dx + dy * dy < (float) touchSlopPx * touchSlopPx) return true;
                        if (nativeScrollableWidgetAt(nativeApp, startXPx / density, startYPx / density)) {
                            touchMode = TOUCH_MODE_SCROLLING;
                        } else {
                            touchMode = TOUCH_MODE_DRAGGING;
                            forwardTouchPhase(TOUCH_PHASE_DOWN, startXPx, startYPx, 1f);
                        }
                    }
                    if (touchMode == TOUCH_MODE_SCROLLING) {
                        // Natural scrolling: finger up moves content up =
                        // offset grows, so the wheel delta is the negated
                        // finger delta.
                        float deltaX = (lastXPx - x) / density;
                        float deltaY = (lastYPx - y) / density;
                        if (deltaX != 0 || deltaY != 0) {
                            nativeScroll(nativeApp, touchSequence, x / density, y / density, deltaX, deltaY);
                        }
                    } else if (touchMode == TOUCH_MODE_DRAGGING) {
                        forwardTouchPhase(TOUCH_PHASE_DRAG, x, y, event.getPressure());
                    }
                    lastXPx = x;
                    lastYPx = y;
                    return true;
                }
                case MotionEvent.ACTION_UP:
                    switch (touchMode) {
                        case TOUCH_MODE_PENDING:
                            // Under-slop touch: a tap at the start point.
                            forwardTouchPhase(TOUCH_PHASE_DOWN, startXPx, startYPx, 1f);
                            forwardTouchPhase(TOUCH_PHASE_UP, startXPx, startYPx, 0f);
                            break;
                        case TOUCH_MODE_DRAGGING:
                            forwardTouchPhase(TOUCH_PHASE_UP, x, y, 0f);
                            break;
                        default:
                            break;
                    }
                    touchMode = TOUCH_MODE_IDLE;
                    syncTextInput();
                    return true;
                case MotionEvent.ACTION_CANCEL:
                    if (touchMode == TOUCH_MODE_DRAGGING) {
                        forwardTouchPhase(TOUCH_PHASE_CANCEL, lastXPx, lastYPx, 0f);
                    }
                    touchMode = TOUCH_MODE_IDLE;
                    syncTextInput();
                    return true;
                default:
                    return super.onTouchEvent(event);
            }
        }

        // --------------------------------------------------- hardware keys

        // Hardware keys (and `adb shell input` injections) arrive here:
        // named control keys forward by name, printable characters commit
        // as text — the split the desktop key/text seam expects.
        @Override
        public boolean onKeyDown(int keyCode, KeyEvent event) {
            if (nativeApp == 0) return super.onKeyDown(keyCode, event);
            String name = keyNameForCode(keyCode);
            if (name != null) {
                emitKeyDownUp(name, modifiersMask(event));
                syncTextInput();
                return true;
            }
            int unicode = event.getUnicodeChar();
            if (unicode != 0 && !event.isCtrlPressed() && !event.isAltPressed()) {
                commitTextToApp(new String(Character.toChars(unicode)));
                syncTextInput();
                return true;
            }
            return super.onKeyDown(keyCode, event);
        }

        private void emitKeyDownUp(String key, int modifiers) {
            nativeKey(nativeApp, KEY_PHASE_DOWN, key, modifiers);
            nativeKey(nativeApp, KEY_PHASE_UP, key, modifiers);
        }

        // ------------------------------------------------ input connection

        @Override
        public boolean onCheckIsTextEditor() {
            return true;
        }

        @Override
        public InputConnection onCreateInputConnection(EditorInfo outAttrs) {
            // Deterministic input for tests and desktop-parity text
            // handling: the runtime owns editing behavior, so system
            // rewriting stays off.
            outAttrs.inputType = InputType.TYPE_CLASS_TEXT | InputType.TYPE_TEXT_FLAG_NO_SUGGESTIONS;
            outAttrs.imeOptions = EditorInfo.IME_ACTION_DONE | EditorInfo.IME_FLAG_NO_FULLSCREEN;
            return new BaseInputConnection(this, true) {
                // Mirrors the iOS host's insertText: committing identical
                // composed text maps to commit_composition; divergent
                // text cancels before the plain insert so the runtime
                // never double-applies the composition.
                @Override
                public boolean commitText(CharSequence text, int newCursorPosition) {
                    String value = text == null ? "" : text.toString();
                    if (value.isEmpty()) return true;
                    if ("\n".equals(value)) {
                        boolean hadComposition = !composingText.isEmpty();
                        clearComposingState();
                        if (hadComposition) emitIme(IME_COMMIT_COMPOSITION, "", -1);
                        emitKeyDownUp("enter", 0);
                        syncTextInput();
                        return true;
                    }
                    boolean hadComposition = !composingText.isEmpty();
                    String previous = composingText;
                    clearComposingState();
                    if (hadComposition && previous.equals(value)) {
                        emitIme(IME_COMMIT_COMPOSITION, "", -1);
                        return true;
                    }
                    if (hadComposition) emitIme(IME_CANCEL_COMPOSITION, "", -1);
                    commitTextToApp(value);
                    return true;
                }

                // The live composition forwards (with the caret as a
                // UTF-8 byte offset) through the same set_composition
                // path the desktop hosts use, so multi-stage IMEs stay
                // correct.
                @Override
                public boolean setComposingText(CharSequence text, int newCursorPosition) {
                    String value = text == null ? "" : text.toString();
                    if (value.isEmpty()) {
                        boolean hadComposition = !composingText.isEmpty();
                        clearComposingState();
                        if (hadComposition) emitIme(IME_CANCEL_COMPOSITION, "", -1);
                        return true;
                    }
                    composingText = value;
                    long cursorBytes = value.getBytes(StandardCharsets.UTF_8).length;
                    emitIme(IME_SET_COMPOSITION, value, cursorBytes);
                    return true;
                }

                @Override
                public boolean finishComposingText() {
                    boolean hadComposition = !composingText.isEmpty();
                    clearComposingState();
                    if (hadComposition) emitIme(IME_COMMIT_COMPOSITION, "", -1);
                    return true;
                }

                @Override
                public boolean deleteSurroundingText(int beforeLength, int afterLength) {
                    if (!composingText.isEmpty()) {
                        clearComposingState();
                        emitIme(IME_CANCEL_COMPOSITION, "", -1);
                        return true;
                    }
                    if (beforeLength > 0 && afterLength == 0) {
                        for (int i = 0; i < beforeLength; i++) emitKeyDownUp("backspace", 0);
                        return true;
                    }
                    if (afterLength > 0 && beforeLength == 0) {
                        for (int i = 0; i < afterLength; i++) emitKeyDownUp("delete", 0);
                        return true;
                    }
                    return super.deleteSurroundingText(beforeLength, afterLength);
                }

                @Override
                public boolean performEditorAction(int actionCode) {
                    emitKeyDownUp("enter", 0);
                    syncTextInput();
                    return true;
                }

                @Override
                public boolean sendKeyEvent(KeyEvent event) {
                    if (event.getAction() == KeyEvent.ACTION_DOWN) {
                        if (event.getKeyCode() == KeyEvent.KEYCODE_DEL) {
                            if (!composingText.isEmpty()) {
                                clearComposingState();
                                emitIme(IME_CANCEL_COMPOSITION, "", -1);
                                return true;
                            }
                            emitKeyDownUp("backspace", 0);
                            return true;
                        }
                        if (event.getKeyCode() == KeyEvent.KEYCODE_FORWARD_DEL) {
                            emitKeyDownUp("delete", 0);
                            return true;
                        }
                    }
                    return super.sendKeyEvent(event);
                }
            };
        }

        private void emitIme(int kind, String text, long cursor) {
            if (nativeApp == 0) return;
            nativeIme(nativeApp, kind, text.getBytes(StandardCharsets.UTF_8), cursor);
        }

        private void commitTextToApp(String text) {
            if (nativeApp == 0 || text.isEmpty()) return;
            nativeText(nativeApp, text.getBytes(StandardCharsets.UTF_8));
        }
    }

    // Named control keys the runtime's key vocabulary understands; other
    // key codes fall through to their unicode character (as committed
    // text) or the platform default.
    private static String keyNameForCode(int keyCode) {
        switch (keyCode) {
            case KeyEvent.KEYCODE_ENTER:
            case KeyEvent.KEYCODE_NUMPAD_ENTER:
                return "enter";
            case KeyEvent.KEYCODE_DEL:
                return "backspace";
            case KeyEvent.KEYCODE_FORWARD_DEL:
                return "delete";
            case KeyEvent.KEYCODE_ESCAPE:
                return "escape";
            case KeyEvent.KEYCODE_TAB:
                return "tab";
            case KeyEvent.KEYCODE_DPAD_LEFT:
                return "arrowleft";
            case KeyEvent.KEYCODE_DPAD_RIGHT:
                return "arrowright";
            case KeyEvent.KEYCODE_DPAD_UP:
                return "arrowup";
            case KeyEvent.KEYCODE_DPAD_DOWN:
                return "arrowdown";
            case KeyEvent.KEYCODE_MOVE_HOME:
                return "home";
            case KeyEvent.KEYCODE_MOVE_END:
                return "end";
            case KeyEvent.KEYCODE_PAGE_UP:
                return "pageup";
            case KeyEvent.KEYCODE_PAGE_DOWN:
                return "pagedown";
            default:
                return null;
        }
    }

    // The embed modifiers mask (1 primary, 2 command, 4 control, 8
    // option, 16 shift); Android's ctrl doubles as primary, matching the
    // Linux and Windows hosts.
    private static int modifiersMask(KeyEvent event) {
        int mask = 0;
        if (event.isCtrlPressed()) mask |= 1 | 4;
        if (event.isAltPressed()) mask |= 8;
        if (event.isShiftPressed()) mask |= 16;
        return mask;
    }

    // ------------------------------------------------------- JNI bridge

    private native long nativeCreate();
    private native void nativeDestroy(long app);
    private native void nativeStart(long app);
    private native void nativeActivate(long app);
    private native void nativeDeactivate(long app);
    private native void nativeStop(long app);
    private native void nativeSurfaceChanged(long app, android.view.Surface surface);
    private native void nativeSurfaceDestroyed(long app);
    private native void nativeViewport(long app, float width, float height, float scale, float safeTop, float safeRight, float safeBottom, float safeLeft, float keyboardTop, float keyboardRight, float keyboardBottom, float keyboardLeft);
    private native void nativeFrame(long app);
    private native long nativeCanvasRevision(long app);
    private native boolean nativePresent(long app, float scale);
    private native void nativeTouch(long app, long id, int phase, float x, float y, float pressure);
    private native void nativeScroll(long app, long id, float x, float y, float deltaX, float deltaY);
    private native void nativeKey(long app, int phase, String key, int modifiers);
    private native void nativeText(long app, byte[] utf8);
    private native void nativeIme(long app, int kind, byte[] utf8, long cursor);
    private native boolean nativeTextInputState(long app, long[] widgetId, float[] frame);
    private native boolean nativeScrollableWidgetAt(long app, float x, float y);
    private native void nativeSetAssetRoot(long app, String path);
    private native void nativeSetAutomationDir(long app, String path);
    private native void nativeSetTextMeasure(long app);
    private native String nativeLastError(long app);
}
