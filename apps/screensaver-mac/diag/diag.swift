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

var tick = 0
Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { t in
    tick += 1
    if tick == 30 {
        for l in labels(view) where l.stringValue.contains("diagnostics") { print(l.stringValue) }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        p.arguments = ["-x", "shot.png"]
        try? p.run(); p.waitUntilExit()
        analyse("shot.png")
        t.invalidate(); exit(0)
    }
}
app.run()
