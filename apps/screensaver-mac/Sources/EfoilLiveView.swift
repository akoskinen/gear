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

    // MARK: - Settings

    static var defaults: ScreenSaverDefaults {
        let bundleID = Bundle(for: EfoilLiveView.self).bundleIdentifier ?? "racing.efoil.live-screensaver"
        let defaults = ScreenSaverDefaults(forModuleWithName: bundleID)!
        defaults.register(defaults: [
            "url": defaultURL,
            "reloadMinutes": defaultReloadMinutes,
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
        loadPage()
    }

    override func stopAnimation() {
        super.stopAnimation()
        tearDown()
    }

    override func animateOneFrame() {
        // The web page animates itself.
    }

    @objc private func screenSaverWillStop() {
        tearDown()
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
        config.mediaTypesRequiringUserActionForPlayback = .all
        config.websiteDataStore = .default()

        let webView = WKWebView(frame: bounds, configuration: config)
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

        showStatus("Connecting to eFoil Racing live…")
        webView.load(URLRequest(url: pageURL, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30))

        if reloadMinutes > 0 {
            reloadTimer = Timer.scheduledTimer(withTimeInterval: TimeInterval(reloadMinutes * 60), repeats: true) { [weak self] _ in
                self?.webView?.reload()
            }
        }
    }

    private func tearDown() {
        reloadTimer?.invalidate()
        reloadTimer = nil
        retryTimer?.invalidate()
        retryTimer = nil
        if let webView {
            webView.stopLoading()
            webView.navigationDelegate = nil
            webView.loadHTMLString("", baseURL: nil)
            webView.removeFromSuperview()
        }
        webView = nil
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
        showStatus("")
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 1.2
            webView.animator().alphaValue = 1
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        scheduleRetry()
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        scheduleRetry()
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        scheduleRetry()
    }

    // MARK: - Options sheet

    override var hasConfigureSheet: Bool { true }

    override var configureSheet: NSWindow? {
        let controller = ConfigSheetController()
        configController = controller
        return controller.window
    }
}

/// The "Options…" sheet in System Settings → Screen Saver.
final class ConfigSheetController: NSObject {

    let window: NSWindow
    private let urlField = NSTextField()
    private let reloadField = NSTextField()

    override init() {
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 190),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        super.init()

        let defaults = EfoilLiveView.defaults
        urlField.stringValue = defaults.string(forKey: "url") ?? EfoilLiveView.defaultURL
        urlField.placeholderString = EfoilLiveView.defaultURL
        reloadField.integerValue = defaults.integer(forKey: "reloadMinutes")
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

        let stack = NSStackView(views: [title, grid, hint, buttons])
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
    }

    @objc private func cancel() {
        close()
    }

    @objc private func save() {
        let defaults = EfoilLiveView.defaults
        let url = urlField.stringValue.trimmingCharacters(in: .whitespaces)
        defaults.set(url.isEmpty ? EfoilLiveView.defaultURL : url, forKey: "url")
        defaults.set(max(0, reloadField.integerValue), forKey: "reloadMinutes")
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
