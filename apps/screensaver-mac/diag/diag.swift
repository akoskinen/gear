// Temporary diagnostic: loads the live page inside the built screensaver view
// in a real window, captures JS console output/errors and WebGL status, and
// saves a snapshot.
import AppKit
import ScreenSaver
import WebKit

let app = NSApplication.shared
app.setActivationPolicy(.regular)

let bundle = Bundle(path: CommandLine.arguments[1])!
bundle.load()
let cls = bundle.principalClass as! ScreenSaverView.Type
let frame = NSRect(x: 0, y: 0, width: 1440, height: 900)
let window = NSWindow(contentRect: frame, styleMask: [.titled], backing: .buffered, defer: false)
let view = cls.init(frame: frame, isPreview: false)!
window.contentView = view
window.makeKeyAndOrderFront(nil)
app.activate(ignoringOtherApps: true)
view.startAnimation()

func findWebView(_ v: NSView) -> WKWebView? {
    if let w = v as? WKWebView { return w }
    for s in v.subviews { if let w = findWebView(s) { return w } }
    return nil
}

let probe = """
(() => {
  const out = {title: document.title, url: location.href};
  out.scripts = [...document.scripts].map(s => s.src || ('inline:' + s.textContent.slice(0, 120)));
  out.links = [...document.querySelectorAll('link[rel=stylesheet]')].map(l => l.href);
  out.canvases = [...document.querySelectorAll('canvas')].map(c => ({w: c.width, h: c.height, cls: c.className, id: c.id}));
  const t = document.createElement('canvas');
  const gl = t.getContext('webgl2') || t.getContext('webgl');
  out.webgl = gl ? (gl.getParameter(gl.VERSION) + ' / ' + gl.getParameter(gl.RENDERER)) : 'NO WEBGL';
  out.globals = ['Cesium','mapboxgl','maplibregl','THREE','L','google','ol','deck'].filter(k => k in window);
  out.errors = window.__errs || [];
  out.text = (document.body ? document.body.innerText : '').slice(0, 400);
  out.html = document.documentElement.outerHTML.slice(0, 3000);
  return JSON.stringify(out, null, 1);
})()
"""

var tick = 0
Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { t in
    tick += 1
    guard let wv = findWebView(view) else { if tick > 60 { exit(2) }; return }
    if tick == 2 {
        // Capture errors from now on (page already started loading).
        wv.evaluateJavaScript("window.__errs=[];addEventListener('error',e=>__errs.push('error: '+e.message+' @'+(e.filename||'')+':'+e.lineno),true);addEventListener('unhandledrejection',e=>__errs.push('rejection: '+(e.reason&&e.reason.message||e.reason)));['error','warn'].forEach(k=>{const o=console[k];console[k]=(...a)=>{__errs.push(k+': '+a.join(' '));o.apply(console,a)}});1")
    }
    if tick == 12 || tick == 40 {
        wv.evaluateJavaScript(probe) { r, e in
            print("=== probe at \(tick)s alpha=\(wv.alphaValue) ===")
            print(r ?? "nil", e ?? "")
        }
        wv.takeSnapshot(with: nil) { img, _ in
            guard let img, let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) else { return }
            try? rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "snap-\(tick).png"))
            print("saved snap-\(tick).png")
        }
    }
    if tick == 45 { t.invalidate(); exit(0) }
}
app.run()
