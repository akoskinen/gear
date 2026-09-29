// Loads the built .saver the way macOS does and checks the screensaver
// view can be created. Run: swift smoke-test.swift "build/eFoil Racing Live.saver"
import AppKit
import ScreenSaver

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
view.stopAnimation()
print("OK: \(cls) loaded, hasConfigureSheet=\(view.hasConfigureSheet), sheet=\(view.configureSheet != nil)")
