# zero-native mobile-shell example

The mobile shell shape is implemented by the concrete platform hosts in `examples/ios` and `examples/android`.

- `examples/ios` uses a native UIKit header with a WKWebView workspace and native command buttons.
- `examples/android` uses a native Android header with a WebView workspace, JNI bridge, native command buttons, and system Back dispatch.

Both hosts leave keyboard avoidance in the native layout system: UIKit adjusts the WebView constraint from keyboard frame notifications, and Android uses `adjustResize` for soft-keyboard relayout.

Android orientation and screen-size changes stay in the same activity so the embedded runtime survives rotation while resize/frame events update the content surface.

Use those platform folders when building or running the example.

The shared mobile metadata in `app.zon` records the intended platforms and capabilities for tooling. The runtime view tree is still owned by each native mobile host, so generic desktop `ShellView` declarations are not materialized on iOS or Android yet.
