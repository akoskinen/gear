// Loads the built .saver the way macOS does and checks the screensaver
// view can be created. Run: swift smoke-test.swift "build/eFoil Racing Live.saver"
import AppKit
import ScreenSaver
import WebKit

let path = CommandLine.arguments[1]
guard let bundle = Bundle(path: path), bundle.load() else {
    fatalError("Could not load bundle at \(path)")
}
guard let cls = bundle.principalClass as? ScreenSaverView.Type else {
    fatalError("Principal class is not a ScreenSaverView")
}
guard let view = cls.init(frame: NSRect(x: 0, y: 0, width: 800, height: 500), isPreview: false) else {
    fatalError("Screensaver view failed to initialise")
}
view.startAnimation()
RunLoop.main.run(until: Date().addingTimeInterval(3))

// A live stream arrives as a MediaStream on a <video> that autoplays with no
// click. Check, with the screensaver's own web view settings, that such a
// video starts playing and is muted.
func findWebView(_ v: NSView) -> WKWebView? {
    if let w = v as? WKWebView { return w }
    return v.subviews.lazy.compactMap(findWebView).first
}
guard let webView = findWebView(view) else { fatalError("No web view") }
webView.loadHTMLString("""
<canvas id=c width=64 height=64></canvas><video id=v autoplay playsinline></video>
<script>
const c = document.getElementById('c'), g = c.getContext('2d');
setInterval(() => { g.fillStyle = '#' + Math.floor(Math.random() * 0xffffff).toString(16).padStart(6, '0'); g.fillRect(0, 0, 64, 64); }, 50);
document.getElementById('v').srcObject = c.captureStream(20);
</script>
""", baseURL: URL(string: "https://example.com/"))
RunLoop.main.run(until: Date().addingTimeInterval(4))
var videoState = ""
webView.evaluateJavaScript("const v = document.getElementById('v'); JSON.stringify({paused: v.paused, muted: v.muted, time: v.currentTime})") { result, error in
    videoState = (result as? String) ?? "error: \(String(describing: error))"
}
RunLoop.main.run(until: Date().addingTimeInterval(1))
print("stream video: \(videoState)")
guard videoState.contains("\"paused\":false"), videoState.contains("\"muted\":true") else {
    fatalError("A live stream video did not autoplay muted: \(videoState)")
}
view.stopAnimation()
print("OK: \(cls) loaded, hasConfigureSheet=\(view.hasConfigureSheet), sheet=\(view.configureSheet != nil)")
