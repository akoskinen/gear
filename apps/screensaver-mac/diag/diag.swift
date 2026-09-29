// Temporary diagnostic: recreates the screensaver host's situation (a window
// macOS reports as not visible) and measures whether the Mapbox page keeps
// animating, with WebKit's occlusion detection on (old build) and off (fix).
import AppKit
import ScreenSaver
import WebKit

let app = NSApplication.shared
app.setActivationPolicy(.regular)

let bundle = Bundle(path: CommandLine.arguments[1])!
bundle.load()
let cls = bundle.principalClass as! ScreenSaverView.Type
let frame = NSRect(x: 0, y: 0, width: 1440, height: 900)
let window = NSWindow(contentRect: frame, styleMask: [.borderless], backing: .buffered, defer: false)
let view = cls.init(frame: frame, isPreview: false)!
window.contentView = view
window.setFrameOrigin(NSPoint(x: -30000, y: -30000))  // off screen: occluded
window.orderFrontRegardless()
view.startAnimation()

func findWebView(_ v: NSView) -> WKWebView? {
    if let w = v as? WKWebView { return w }
    for s in v.subviews { if let w = findWebView(s) { return w } }
    return nil
}
func setOcclusionDetection(_ wv: WKWebView, _ on: Bool) {
    let sel = NSSelectorFromString("_setWindowOcclusionDetectionEnabled:")
    let m = class_getInstanceMethod(WKWebView.self, sel)!
    typealias F = @convention(c) (AnyObject, Selector, Bool) -> Void
    unsafeBitCast(method_getImplementation(m), to: F.self)(wv, sel, on)
}

var tick = 0
var mark = 0
Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { t in
    tick += 1
    guard let wv = findWebView(view) else { return }
    switch tick {
    case 3:
        print("window visible=\(window.isVisible) occlusionVisible=\(window.occlusionState.contains(.visible))")
        wv.evaluateJavaScript("window.__raf=0;(function f(){__raf++;requestAnimationFrame(f)})();1")
    case 14:
        print("-- phase A: occlusion detection ON (how the first build behaved)")
        setOcclusionDetection(wv, true)
    case 16, 26:
        wv.evaluateJavaScript("__raf") { r, _ in mark = (r as? Int) ?? -1 }
    case 21, 31:
        let label = tick == 21 ? "A (old)" : "B (fix)"
        wv.evaluateJavaScript("JSON.stringify({raf: __raf, vis: document.visibilityState, hidden: document.hidden})") { r, _ in
            let s = r as? String ?? "?"
            let raf = (try? JSONSerialization.jsonObject(with: Data(s.utf8)) as? [String: Any])?["raf"] as? Int ?? -1
            print("phase \(label): animation frames in 5 s = \(raf - mark)  page=\(s)")
        }
        if tick == 21 {
            print("-- phase B: occlusion detection OFF (the fix)")
            setOcclusionDetection(wv, false)
        }
    case 33:
        t.invalidate(); exit(0)
    default: break
    }
}
app.run()
