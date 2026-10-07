// Loads the built .saver the way macOS does and checks the screensaver
// view can be created. Run: swift smoke-test.swift "build/eFoil Racing Live.saver" [prepared-podcast-folder]
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
// Show it in a window, as macOS does; media won't play in a hidden page.
let window = NSWindow(contentRect: view.frame, styleMask: [.borderless], backing: .buffered, defer: false)
window.contentView = view
window.orderFrontRegardless()
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

// Podcast mode: with nobody live, random clips play with the sponsor overlays
// in turn; when a rider goes live it returns to the map. Test media comes from
// the folder prepared by prepare-podcast.sh (second argument).
if CommandLine.arguments.count > 2 {
    let folder = URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true)
    let sessions = folder.appendingPathComponent("sessions.json")
    try! #"{"data": []}"#.write(to: sessions, atomically: true, encoding: .utf8)
    let stub = folder.appendingPathComponent("stub.html")
    try! "<body style='background:#123'>live map stand-in</body>".write(to: stub, atomically: true, encoding: .utf8)

    let defaults = ScreenSaverDefaults(forModuleWithName: "racing.efoil.live-screensaver")!
    defaults.set(stub.absoluteString, forKey: "url")
    defaults.set(sessions.absoluteString, forKey: "sessionsURL")
    defaults.set(folder.absoluteString, forKey: "podcastURL")
    defaults.set(2, forKey: "pollSeconds")
    defaults.synchronize()

    func state() -> String { view.value(forKey: "debugState") as? String ?? "" }
    func waitFor(_ seconds: Double, _ condition: (String) -> Bool) -> Bool {
        let end = Date().addingTimeInterval(seconds)
        while Date() < end {
            if condition(state()) { return true }
            RunLoop.main.run(until: Date().addingTimeInterval(0.25))
        }
        return false
    }
    func number(_ key: String, _ s: String) -> Int {
        Int(s.components(separatedBy: " ").first { $0.hasPrefix(key + "=") }?.dropFirst(key.count + 1) ?? "") ?? 0
    }

    view.startAnimation()
    guard waitFor(20, { $0.contains("mode=podcast") && $0.contains("playing=true") }) else {
        fatalError("Podcast did not start with nobody live: \(state())")
    }
    print("podcast playing: \(state())")
    var adsSeen: [String] = []
    guard waitFor(45, { s in
        if s.contains("ad=true"), let name = s.components(separatedBy: " ").first(where: { $0.hasPrefix("lastAd=") })?.dropFirst(7),
           adsSeen.last != String(name) { adsSeen.append(String(name)) }
        return number("clips", s) >= 4
    }) else {
        fatalError("Clips did not keep coming: \(state())")
    }
    print("after 4 clips: \(state()), sponsors in order: \(adsSeen)")
    guard adsSeen.starts(with: ["ad_1", "ad_2", "ad_10"]) else {
        fatalError("Sponsors did not rotate in folder-number order: \(adsSeen)")
    }

    try! #"{"data": [{"id": "test-rider"}]}"#.write(to: sessions, atomically: true, encoding: .utf8)
    guard waitFor(10, { $0.contains("mode=globe") }) else {
        fatalError("Did not return to the map when a rider went live: \(state())")
    }
    print("rider live: \(state())")
    view.stopAnimation()
    defaults.removePersistentDomain(forName: "racing.efoil.live-screensaver")
}
print("OK: \(cls) loaded, hasConfigureSheet=\(view.hasConfigureSheet), sheet=\(view.configureSheet != nil)")
