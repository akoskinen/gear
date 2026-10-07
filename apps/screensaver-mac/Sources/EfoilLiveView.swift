import AppKit
import ScreenSaver
import WebKit

/// A macOS screensaver that shows the eFoil Racing live view
/// (riders broadcasting their rides) full screen.
@objc(EfoilLiveView)
final class EfoilLiveView: ScreenSaverView, WKNavigationDelegate {

    static let defaultURL = "https://api.efoilracing.nl/live"
    static let defaultReloadMinutes = 30

    private var webView: WKWebView?
    private let statusLabel = NSTextField(labelWithString: "")
    private var reloadTimer: Timer?
    private var retryTimer: Timer?
    private var configController: ConfigSheetController?
    private var activity: NSObjectProtocol?
    private let diagnosticsLabel = NSTextField(wrappingLabelWithString: "")
    private var diagnosticsTimer: Timer?
    private var pageReport: [String: Any] = [:]
    private var events: [String] = []

    // MARK: - Settings

    static var defaults: ScreenSaverDefaults {
        let bundleID = Bundle(for: EfoilLiveView.self).bundleIdentifier ?? "racing.efoil.live-screensaver"
        let defaults = ScreenSaverDefaults(forModuleWithName: bundleID)!
        defaults.register(defaults: [
            "url": defaultURL,
            "reloadMinutes": defaultReloadMinutes,
            "showDiagnostics": false,
        ])
        return defaults
    }

    private var pageURL: URL {
        let string = Self.defaults.string(forKey: "url") ?? Self.defaultURL
        return URL(string: string) ?? URL(string: Self.defaultURL)!
    }

    private var reloadMinutes: Int {
        Self.defaults.integer(forKey: "reloadMinutes")
    }

    private var showDiagnostics: Bool {
        Self.defaults.bool(forKey: "showDiagnostics") && !isPreview
    }

    // MARK: - Lifecycle

    override init?(frame: NSRect, isPreview: Bool) {
        super.init(frame: frame, isPreview: isPreview)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        animationTimeInterval = 1.0

        statusLabel.textColor = NSColor(white: 1, alpha: 0.6)
        statusLabel.font = .systemFont(ofSize: isPreview ? 9 : 15, weight: .medium)
        statusLabel.alignment = .center
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(statusLabel)
        NSLayoutConstraint.activate([
            statusLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            statusLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])

        diagnosticsLabel.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        diagnosticsLabel.textColor = .white
        diagnosticsLabel.drawsBackground = true
        diagnosticsLabel.backgroundColor = NSColor(white: 0, alpha: 0.75)
        diagnosticsLabel.translatesAutoresizingMaskIntoConstraints = false
        diagnosticsLabel.isHidden = true
        addSubview(diagnosticsLabel)
        NSLayoutConstraint.activate([
            diagnosticsLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            diagnosticsLabel.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -16),
            diagnosticsLabel.widthAnchor.constraint(lessThanOrEqualToConstant: 640),
        ])

        // Since macOS Sonoma the screensaver host often never calls
        // stopAnimation(), so the page would keep running (and using
        // network and battery) after you wake the Mac. Listen for the
        // system notification and tear the page down ourselves.
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(screenSaverWillStop),
            name: NSNotification.Name("com.apple.screensaver.willstop"),
            object: nil
        )
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    deinit {
        DistributedNotificationCenter.default().removeObserver(self)
    }

    override func startAnimation() {
        super.startAnimation()
        if activity == nil {
            activity = ProcessInfo.processInfo.beginActivity(
                options: [.userInitiatedAllowingIdleSystemSleep, .latencyCritical],
                reason: "Rendering the eFoil Racing live view"
            )
        }
        loadPage()
    }

    override func stopAnimation() {
        super.stopAnimation()
        stop()
    }

    override func animateOneFrame() {
        // The web page animates itself.
    }

    @objc private func screenSaverWillStop() {
        stop()
    }

    // Keep mouse and keyboard events on the screensaver so any input
    // dismisses it, instead of being swallowed by the web page.
    override func hitTest(_ point: NSPoint) -> NSView? {
        bounds.contains(convert(point, from: superview)) ? self : nil
    }

    // MARK: - Web view

    private func loadPage() {
        tearDown()

        let config = WKWebViewConfiguration()
        // A screensaver never gets a click, so video (the riders' live
        // streams) must be allowed to start on its own. Sound stays off:
        // the mute script below silences every audio and video element.
        config.mediaTypesRequiringUserActionForPlayback = []
        config.websiteDataStore = .default()
        // Keep timers and the web content process at full speed even when
        // WebKit believes the page is in the background.
        Self.setPrivateFlag(config.preferences, "_setHiddenPageDOMTimerThrottlingEnabled:", false)
        Self.setPrivateFlag(config.preferences, "_setPageVisibilityBasedProcessSuppressionEnabled:", false)
        config.userContentController.addUserScript(WKUserScript(
            source: Self.muteScript, injectionTime: .atDocumentStart, forMainFrameOnly: false))
        config.userContentController.addUserScript(WKUserScript(
            source: Self.pageProbeScript, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        config.userContentController.add(WeakMessageHandler(self), name: "efoil")

        let webView = WKWebView(frame: bounds, configuration: config)
        // Since macOS Sonoma the screensaver runs in a helper process and is
        // shown on screen through a remote layer, so its window may not count
        // as visible. If WebKit then treats the page as hidden it stops
        // requestAnimationFrame, which the Mapbox globe draws with. Tell
        // WebKit to ignore window occlusion so the page keeps rendering.
        Self.setPrivateFlag(webView, "_setWindowOcclusionDetectionEnabled:", false)
        Self.mutePage(webView)
        webView.autoresizingMask = [.width, .height]
        webView.navigationDelegate = self
        webView.setValue(false, forKey: "drawsBackground")
        webView.alphaValue = 0
        if isPreview {
            // Render the thumbnail in System Settings as a scaled-down
            // desktop page rather than a cramped mobile layout.
            webView.pageZoom = max(0.2, bounds.width / 1440)
        }
        addSubview(webView, positioned: .below, relativeTo: statusLabel)
        self.webView = webView
        log("load \(pageURL.absoluteString) in \(ProcessInfo.processInfo.processName), macOS \(ProcessInfo.processInfo.operatingSystemVersionString)")

        if showDiagnostics {
            diagnosticsLabel.isHidden = false
            diagnosticsTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
                self?.updateDiagnostics()
            }
        }

        showStatus("Connecting to eFoil Racing live…")
        webView.load(URLRequest(url: pageURL, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30))

        if reloadMinutes > 0 {
            reloadTimer = Timer.scheduledTimer(withTimeInterval: TimeInterval(reloadMinutes * 60), repeats: true) { [weak self] _ in
                self?.webView?.reload()
            }
        }
    }

    private func stop() {
        tearDown()
        if let activity {
            ProcessInfo.processInfo.endActivity(activity)
            self.activity = nil
        }
    }

    private func tearDown() {
        reloadTimer?.invalidate()
        reloadTimer = nil
        retryTimer?.invalidate()
        retryTimer = nil
        diagnosticsTimer?.invalidate()
        diagnosticsTimer = nil
        pageReport = [:]
        if let webView {
            webView.stopLoading()
            webView.navigationDelegate = nil
            webView.configuration.userContentController.removeScriptMessageHandler(forName: "efoil")
            webView.loadHTMLString("", baseURL: nil)
            webView.removeFromSuperview()
        }
        webView = nil
    }

    /// Mutes every audio and video element as soon as it appears, in all
    /// frames, so streams can autoplay without making a sound.
    static let muteScript = """
    (() => {
      const mute = el => { el.muted = true; el.defaultMuted = true; };
      const muteAll = root => root.querySelectorAll && root.querySelectorAll('video, audio').forEach(mute);
      const origPlay = HTMLMediaElement.prototype.play;
      HTMLMediaElement.prototype.play = function () { mute(this); return origPlay.apply(this, arguments); };
      ['loadstart', 'play', 'volumechange'].forEach(type => document.addEventListener(type, e => {
        if (e.target instanceof HTMLMediaElement && !e.target.muted) mute(e.target);
      }, true));
      new MutationObserver(records => records.forEach(r => r.addedNodes.forEach(n => {
        if (n instanceof HTMLMediaElement) mute(n); else muteAll(n);
      }))).observe(document, { childList: true, subtree: true });
    })();
    """

    /// Also mutes the whole page through WebKit, where this macOS allows it.
    static func mutePage(_ webView: WKWebView) {
        let selector = NSSelectorFromString("_setPageMuted:")
        guard webView.responds(to: selector),
              let method = class_getInstanceMethod(WKWebView.self, selector) else { return }
        typealias Setter = @convention(c) (AnyObject, Selector, UInt) -> Void
        unsafeBitCast(method_getImplementation(method), to: Setter.self)(webView, selector, 1) // audio muted
    }

    /// Calls a private WebKit `-set…:(BOOL)` method if this macOS has it.
    static func setPrivateFlag(_ object: NSObject, _ selectorName: String, _ value: Bool) {
        let selector = NSSelectorFromString(selectorName)
        guard object.responds(to: selector),
              let method = class_getInstanceMethod(type(of: object), selector) else {
            NSLog("EfoilLive: %@ not available", selectorName)
            return
        }
        typealias Setter = @convention(c) (AnyObject, Selector, Bool) -> Void
        unsafeBitCast(method_getImplementation(method), to: Setter.self)(object, selector, value)
    }

    private func showStatus(_ text: String) {
        statusLabel.stringValue = text
        statusLabel.isHidden = text.isEmpty
    }

    private func scheduleRetry() {
        showStatus("Live view unavailable — retrying…")
        webView?.alphaValue = 0
        retryTimer?.invalidate()
        retryTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: false) { [weak self] _ in
            self?.loadPage()
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        log("page finished loading")
        showStatus("")
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 1.2
            webView.animator().alphaValue = 1
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        log("load failed: \(error.localizedDescription)")
        scheduleRetry()
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        log("load failed: \(error.localizedDescription)")
        scheduleRetry()
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        log("web content process terminated")
        scheduleRetry()
    }

    // MARK: - Diagnostics

    /// Runs inside the page and reports, every 2 seconds, what the page sees:
    /// visibility, animation frame rate, WebGL, the map canvas and errors.
    static let pageProbeScript = """
    (() => {
      const errors = [];
      let frames = 0, fps = 0, contextLost = 0;
      const note = m => { errors.push(String(m).slice(0, 160)); if (errors.length > 4) errors.shift(); };
      addEventListener('error', e => note('error: ' + e.message), true);
      addEventListener('unhandledrejection', e => note('rejection: ' + (e.reason && e.reason.message || e.reason)));
      const origError = console.error;
      console.error = (...a) => { note('console: ' + a.join(' ')); origError.apply(console, a); };
      const origGetContext = HTMLCanvasElement.prototype.getContext;
      HTMLCanvasElement.prototype.getContext = function (type, ...rest) {
        const ctx = origGetContext.call(this, type, ...rest);
        if (/webgl/.test(type) && !this.__efoil) {
          this.__efoil = true;
          if (!ctx) note('getContext(' + type + ') returned null');
          this.addEventListener('webglcontextlost', () => { contextLost++; note('WebGL context lost'); });
        }
        return ctx;
      };
      (function tick() { frames++; requestAnimationFrame(tick); })();
      let gl = 'unknown';
      try {
        const c = origGetContext.call(document.createElement('canvas'), 'webgl2') || origGetContext.call(document.createElement('canvas'), 'webgl');
        gl = c ? c.getParameter(c.VERSION) : 'NONE';
      } catch (e) { gl = 'error ' + e.message; }
      setInterval(() => {
        fps = Math.round(frames / 2); frames = 0;
        const canvas = document.querySelector('canvas.mapboxgl-canvas');
        window.webkit.messageHandlers.efoil.postMessage({
          visibility: document.visibilityState, fps, webgl: gl, contextLost,
          canvas: canvas ? canvas.width + 'x' + canvas.height : 'none',
          errors: errors.slice()
        });
      }, 2000);
    })();
    """

    func receivedPageReport(_ report: [String: Any]) {
        let first = pageReport.isEmpty
        pageReport = report
        if first || !((report["errors"] as? [String])?.isEmpty ?? true) {
            log("page: \(report)")
        }
    }

    private func log(_ message: String) {
        NSLog("EfoilLive: %@", message)
        let time = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
        events.append("\(time) \(message)")
        if events.count > 5 { events.removeFirst() }
    }

    private func updateDiagnostics() {
        let window = self.window
        var lines = [
            "eFoil Racing Live — diagnostics",
            "host: \(ProcessInfo.processInfo.processName)  macOS \(ProcessInfo.processInfo.operatingSystemVersionString)",
            "window: \(window.map { "visible=\($0.isVisible) occluded=\(!$0.occlusionState.contains(.visible)) level=\($0.level.rawValue) \(Int($0.frame.width))x\(Int($0.frame.height))" } ?? "none")",
            "web view: \(webView.map { "alpha=\($0.alphaValue) \(Int($0.frame.width))x\(Int($0.frame.height)) loading=\($0.isLoading)" } ?? "none")",
        ]
        if pageReport.isEmpty {
            lines.append("page: no report yet")
        } else {
            let r = pageReport
            lines.append("page: visibility=\(r["visibility"] ?? "?") fps=\(r["fps"] ?? "?") webgl=\(r["webgl"] ?? "?")")
            lines.append("map canvas: \(r["canvas"] ?? "?")  context lost: \(r["contextLost"] ?? 0)")
            for e in (r["errors"] as? [String]) ?? [] { lines.append("  ! \(e)") }
        }
        lines.append("events:")
        lines += events.map { "  \($0)" }
        diagnosticsLabel.stringValue = lines.joined(separator: "\n")
    }

    // MARK: - Options sheet

    override var hasConfigureSheet: Bool { true }

    override var configureSheet: NSWindow? {
        let controller = ConfigSheetController()
        configController = controller
        return controller.window
    }
}

/// Forwards page reports without the web view retaining the screensaver.
final class WeakMessageHandler: NSObject, WKScriptMessageHandler {
    weak var target: EfoilLiveView?
    init(_ target: EfoilLiveView) { self.target = target }

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        if let report = message.body as? [String: Any] {
            target?.receivedPageReport(report)
        }
    }
}

/// The "Options…" sheet in System Settings → Screen Saver.
final class ConfigSheetController: NSObject {

    let window: NSWindow
    private let urlField = NSTextField()
    private let reloadField = NSTextField()
    private let diagnosticsBox = NSButton(checkboxWithTitle: "Show diagnostics on screen", target: nil, action: nil)

    override init() {
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 220),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        super.init()

        let defaults = EfoilLiveView.defaults
        urlField.stringValue = defaults.string(forKey: "url") ?? EfoilLiveView.defaultURL
        urlField.placeholderString = EfoilLiveView.defaultURL
        reloadField.integerValue = defaults.integer(forKey: "reloadMinutes")
        diagnosticsBox.state = defaults.bool(forKey: "showDiagnostics") ? .on : .off
        reloadField.formatter = {
            let formatter = NumberFormatter()
            formatter.minimum = 0
            formatter.maximum = 1440
            formatter.allowsFloats = false
            return formatter
        }()

        let title = NSTextField(labelWithString: "eFoil Racing Live")
        title.font = .systemFont(ofSize: 15, weight: .semibold)

        let grid = NSGridView(views: [
            [NSTextField(labelWithString: "Page URL:"), urlField],
            [NSTextField(labelWithString: "Reload every (min):"), reloadField],
        ])
        grid.column(at: 0).xPlacement = .trailing
        grid.rowSpacing = 10
        urlField.widthAnchor.constraint(equalToConstant: 290).isActive = true
        reloadField.widthAnchor.constraint(equalToConstant: 60).isActive = true

        let hint = NSTextField(labelWithString: "Set reload to 0 to never reload the page.")
        hint.font = .systemFont(ofSize: 11)
        hint.textColor = .secondaryLabelColor

        let resetButton = NSButton(title: "Reset", target: self, action: #selector(reset))
        let cancelButton = NSButton(title: "Cancel", target: self, action: #selector(cancel))
        cancelButton.keyEquivalent = "\u{1b}"
        let saveButton = NSButton(title: "Save", target: self, action: #selector(save))
        saveButton.keyEquivalent = "\r"

        let buttons = NSStackView(views: [resetButton, NSView(), cancelButton, saveButton])
        buttons.distribution = .fill

        let stack = NSStackView(views: [title, grid, hint, diagnosticsBox, buttons])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)
        stack.translatesAutoresizingMaskIntoConstraints = false
        buttons.widthAnchor.constraint(equalTo: grid.widthAnchor).isActive = true

        let content = NSView()
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            stack.topAnchor.constraint(equalTo: content.topAnchor),
            stack.bottomAnchor.constraint(equalTo: content.bottomAnchor),
        ])
        window.contentView = content
    }

    @objc private func reset() {
        urlField.stringValue = EfoilLiveView.defaultURL
        reloadField.integerValue = EfoilLiveView.defaultReloadMinutes
        diagnosticsBox.state = .off
    }

    @objc private func cancel() {
        close()
    }

    @objc private func save() {
        let defaults = EfoilLiveView.defaults
        let url = urlField.stringValue.trimmingCharacters(in: .whitespaces)
        defaults.set(url.isEmpty ? EfoilLiveView.defaultURL : url, forKey: "url")
        defaults.set(max(0, reloadField.integerValue), forKey: "reloadMinutes")
        defaults.set(diagnosticsBox.state == .on, forKey: "showDiagnostics")
        defaults.synchronize()
        close()
    }

    private func close() {
        if let parent = window.sheetParent {
            parent.endSheet(window)
        } else {
            window.close()
        }
    }
}
