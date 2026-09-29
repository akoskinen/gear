// Temporary diagnostic: runs the built screensaver on screen with its
// diagnostics overlay on, prints the overlay, and measures from a real screen
// capture whether the map is actually drawn (vs. the page's dark background).
import AppKit
import ScreenSaver
import WebKit

let app = NSApplication.shared
app.setActivationPolicy(.regular)

ScreenSaverDefaults(forModuleWithName: "racing.efoil.live-screensaver")!.set(true, forKey: "showDiagnostics")

let bundle = Bundle(path: CommandLine.arguments[1])!
bundle.load()
let cls = bundle.principalClass as! ScreenSaverView.Type
let screen = NSScreen.main!.frame
let window = NSWindow(contentRect: screen, styleMask: [.borderless], backing: .buffered, defer: false)
window.level = .screenSaver
let view = cls.init(frame: NSRect(origin: .zero, size: screen.size), isPreview: false)!
window.contentView = view
window.orderFrontRegardless()
view.startAnimation()

func labels(_ v: NSView) -> [NSTextField] {
    (v as? NSTextField).map { [$0] } ?? [] + v.subviews.flatMap(labels)
}

func analyse(_ path: String) {
    guard let img = NSImage(contentsOfFile: path), let tiff = img.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff) else { print("no capture"); return }
    var dark = 0, colour = 0, total = 0
    for y in stride(from: 0, to: rep.pixelsHigh, by: 6) {
        for x in stride(from: 0, to: rep.pixelsWide, by: 6) {
            guard let c = rep.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { continue }
            total += 1
            let r = c.redComponent, g = c.greenComponent, b = c.blueComponent
            if r + g + b < 0.25 { dark += 1 }
            if max(r, g, b) - min(r, g, b) > 0.08 && r + g + b > 0.3 { colour += 1 }
        }
    }
    print("capture \(rep.pixelsWide)x\(rep.pixelsHigh): dark \(100 * dark / max(total, 1))%, coloured \(100 * colour / max(total, 1))%")
}

func findWebView(_ v: NSView) -> WKWebView? {
    if let w = v as? WKWebView { return w }
    for s in v.subviews { if let w = findWebView(s) { return w } }
    return nil
}

func measure(_ label: String) {
    guard let wv = findWebView(view) else { print("\(label): no web view"); return }
    let w = wv.window!
    wv.evaluateJavaScript("new Promise(r=>{let n=0,t0=performance.now();(function f(){n++;if(performance.now()-t0<3000)requestAnimationFrame(f);else r(JSON.stringify({fps:Math.round(n/3),vis:document.visibilityState}))})()})") { _, _ in }
    wv.callAsyncJavaScript("return await new Promise(r=>{let n=0,t0=performance.now();(function f(){n++;if(performance.now()-t0<3000)requestAnimationFrame(f);else r(JSON.stringify({fps:Math.round(n/3),vis:document.visibilityState}))})()})", arguments: [:], in: nil, in: .page) { result in
        print("\(label): \((try? result.get()) ?? "err")  alpha=\(wv.alphaValue) winVisible=\(w.isVisible) occlusionVisible=\(w.occlusionState.contains(.visible)) level=\(w.level.rawValue)")
    }
}

let steps: [(Int, String, () -> Void)] = [
    (12, "A screensaver level, as shipped", {}),
    (18, "B normal window level", { window.level = .normal }),
    (24, "C back to screensaver level", { window.level = .screenSaver }),
    (30, "D key + main window", { app.activate(ignoringOtherApps: true); window.makeKeyAndOrderFront(nil) }),
]
var tick = 0
Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { t in
    tick += 1
    for (at, label, change) in steps where at == tick { change(); DispatchQueue.main.asyncAfter(deadline: .now() + 1) { measure(label) } }
    if tick == 38 { t.invalidate(); exit(0) }
}
app.run()
