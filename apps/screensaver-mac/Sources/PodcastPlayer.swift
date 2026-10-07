import AppKit
import AVFoundation

/// `manifest.json` in the podcast folder, written by `podcast/prepare-podcast.sh`.
struct PodcastManifest: Decodable {
    struct Episode: Decodable {
        let file: String
        let title: String?
        let duration: Double?
    }

    struct Ad: Decodable {
        let name: String?
        let image: String?
        let audio: String?
        let duration: Double?
    }

    var showName: String?
    var clipSeconds: Double?
    var skipStartSeconds: Double?
    var skipEndSeconds: Double?
    var adEveryClips: Int?
    let episodes: [Episode]
    var ads: [Ad]?
}

/// Plays random segments of the podcast episodes, one after another, with the
/// sponsor overlays (a transparent PNG plus a short sound) shown during a clip.
final class PodcastView: NSView {

    var onGiveUp: (() -> Void)?
    var log: (String) -> Void = { _ in }

    private let baseURL: URL
    private let manifest: PodcastManifest
    private let soundOn: Bool

    private let videoHost = NSView()
    private let playerLayer = AVPlayerLayer()
    private let overlayLayer = CALayer()
    private let showLabel = NSTextField(labelWithString: "")
    private let titleLabel = NSTextField(labelWithString: "")
    private let player = AVPlayer()
    private let adPlayer = AVPlayer()

    private var running = false
    private var timers: [Timer] = []
    private var statusObservation: NSKeyValueObservation?
    private var lastEpisode: Int?
    private var adIndex = 0
    private var failures = 0
    private var currentEpisode = ""
    private(set) var clipsStarted = 0
    private(set) var adsShown = 0
    private var adOnScreen = false
    private var lastAd = ""

    private var clipSeconds: Double { max(5, manifest.clipSeconds ?? 30) }
    private var skipStart: Double { max(0, manifest.skipStartSeconds ?? 60) }
    private var skipEnd: Double { max(0, manifest.skipEndSeconds ?? 60) }
    private var adEvery: Int { max(1, manifest.adEveryClips ?? 1) }
    private var ads: [PodcastManifest.Ad] { manifest.ads ?? [] }

    init(frame: NSRect, baseURL: URL, manifest: PodcastManifest, soundOn: Bool) {
        self.baseURL = baseURL
        self.manifest = manifest
        self.soundOn = soundOn
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor

        videoHost.wantsLayer = true
        videoHost.frame = bounds
        videoHost.autoresizingMask = [.width, .height]
        videoHost.alphaValue = 0
        addSubview(videoHost)
        playerLayer.player = player
        playerLayer.videoGravity = .resizeAspectFill
        overlayLayer.contentsGravity = .resizeAspectFill
        overlayLayer.opacity = 0
        videoHost.layer?.addSublayer(playerLayer)
        videoHost.layer?.addSublayer(overlayLayer)

        showLabel.font = .systemFont(ofSize: 13, weight: .heavy)
        showLabel.textColor = NSColor(calibratedRed: 0.13, green: 0.77, blue: 0.37, alpha: 1)
        titleLabel.font = .systemFont(ofSize: 22, weight: .semibold)
        titleLabel.textColor = .white
        for label in [showLabel, titleLabel] {
            label.shadow = {
                let shadow = NSShadow()
                shadow.shadowColor = NSColor(white: 0, alpha: 0.8)
                shadow.shadowBlurRadius = 6
                return shadow
            }()
            label.alphaValue = 0
            label.translatesAutoresizingMaskIntoConstraints = false
            addSubview(label)
        }
        NSLayoutConstraint.activate([
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 48),
            titleLabel.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -44),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -48),
            showLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            showLabel.bottomAnchor.constraint(equalTo: titleLabel.topAnchor, constant: -4),
        ])
        showLabel.stringValue = (manifest.showName ?? "The eFoil Racing Experience").uppercased()
    }

    required init?(coder: NSCoder) { nil }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        playerLayer.frame = videoHost.bounds
        overlayLayer.frame = videoHost.bounds
        CATransaction.commit()
    }

    /// For the diagnostics panel and the tests.
    var state: String {
        "clips=\(clipsStarted) ads=\(adsShown) playing=\(player.rate > 0) ad=\(adOnScreen) lastAd=\(lastAd) episode=\(currentEpisode)"
    }

    func start() {
        guard !running else { return }
        running = true
        nextClip()
    }

    func stop() {
        running = false
        timers.forEach { $0.invalidate() }
        timers = []
        statusObservation = nil
        player.pause()
        player.replaceCurrentItem(with: nil)
        adPlayer.pause()
        adPlayer.replaceCurrentItem(with: nil)
    }

    private func after(_ seconds: Double, _ block: @escaping () -> Void) {
        let timer = Timer.scheduledTimer(withTimeInterval: seconds, repeats: false) { [weak self] _ in
            guard let self, self.running else { return }
            block()
        }
        timers.append(timer)
    }

    private func resolve(_ path: String) -> URL? {
        let encoded = path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? path
        return URL(string: encoded, relativeTo: baseURL)?.absoluteURL
    }

    // MARK: - Clips

    private func nextClip() {
        guard running, !manifest.episodes.isEmpty else { return }
        timers.forEach { $0.invalidate() }
        timers = []
        if adOnScreen {
            adOnScreen = false
            setOverlay(visible: false)
            adPlayer.pause()
        }

        var index = Int.random(in: 0..<manifest.episodes.count)
        if manifest.episodes.count > 1, index == lastEpisode {
            index = (index + 1) % manifest.episodes.count
        }
        lastEpisode = index
        let episode = manifest.episodes[index]
        guard let url = resolve(episode.file) else { return fail("bad episode path \(episode.file)") }

        let asset = AVURLAsset(url: url)
        if let duration = episode.duration, duration > 0 {
            play(asset, episode: episode, duration: duration)
        } else {
            asset.loadValuesAsynchronously(forKeys: ["duration"]) { [weak self] in
                DispatchQueue.main.async {
                    guard let self, self.running else { return }
                    let duration = asset.duration.seconds
                    guard duration.isFinite, duration > 0 else { return self.fail("can't read \(episode.file)") }
                    self.play(asset, episode: episode, duration: duration)
                }
            }
        }
        // If nothing plays within 25 s (server down, slow network), move on.
        after(25) { [weak self] in
            guard let self, self.player.rate == 0 else { return }
            self.fail("\(episode.file) did not start")
        }
    }

    private func play(_ asset: AVURLAsset, episode: PodcastManifest.Episode, duration: Double) {
        var low = skipStart
        var high = duration - skipEnd - clipSeconds
        if high <= low { low = 0; high = max(0, duration - clipSeconds) }
        let start = Double.random(in: low...max(low, high))

        let item = AVPlayerItem(asset: asset)
        statusObservation = item.observe(\.status) { [weak self] item, _ in
            DispatchQueue.main.async {
                if item.status == .failed {
                    self?.fail("\(episode.file): \(item.error?.localizedDescription ?? "failed")")
                }
            }
        }
        player.replaceCurrentItem(with: item)
        player.isMuted = !soundOn
        player.volume = 1
        currentEpisode = episode.file
        titleLabel.stringValue = episode.title ?? ""

        let time = CMTime(seconds: start, preferredTimescale: 600)
        let tolerance = CMTime(seconds: 1, preferredTimescale: 600)
        player.seek(to: time, toleranceBefore: tolerance, toleranceAfter: tolerance) { [weak self] finished in
            DispatchQueue.main.async {
                guard let self, self.running, finished, self.player.currentItem === item else { return }
                self.clipStarted(at: start)
            }
        }
    }

    private func clipStarted(at start: Double) {
        player.play()
        clipsStarted += 1
        failures = 0
        log(String(format: "podcast clip %@ from %.0f s", currentEpisode, start))
        fade(in: true)

        if !ads.isEmpty, (clipsStarted - 1) % adEvery == 0 {
            let ad = ads[adIndex % ads.count]
            adIndex += 1
            let length = min(15, max(3, ad.duration ?? 8))
            let adStart = max(2, (clipSeconds - length) / 2)
            prepareOverlay(ad)
            after(adStart) { [weak self] in self?.showAd(ad, length: length) }
        }
        after(clipSeconds - 0.8) { [weak self] in
            self?.fade(in: false)
            self?.after(0.9) { self?.nextClip() }
        }
    }

    private func fade(in visible: Bool) {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = visible ? 0.8 : 0.7
            videoHost.animator().alphaValue = visible ? 1 : 0
            showLabel.animator().alphaValue = visible ? 1 : 0
            titleLabel.animator().alphaValue = visible && !titleLabel.stringValue.isEmpty ? 1 : 0
        }
    }

    private func fail(_ reason: String) {
        guard running else { return }
        failures += 1
        log("podcast problem: \(reason)")
        timers.forEach { $0.invalidate() }
        timers = []
        player.pause()
        if failures >= 3 {
            log("podcast: giving up for now")
            onGiveUp?()
        } else {
            after(2) { [weak self] in self?.nextClip() }
        }
    }

    // MARK: - Sponsor overlays

    private func prepareOverlay(_ ad: PodcastManifest.Ad) {
        overlayLayer.contents = nil
        guard let path = ad.image, let url = resolve(path) else { return }
        URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
            guard let data, let image = NSImage(data: data),
                  let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return }
            DispatchQueue.main.async { self?.overlayLayer.contents = cgImage }
        }.resume()
    }

    private func showAd(_ ad: PodcastManifest.Ad, length: Double) {
        adsShown += 1
        adOnScreen = true
        lastAd = ad.name ?? ""
        log("podcast ad \(ad.name ?? ad.image ?? "?")")
        setOverlay(visible: true)
        if soundOn, let path = ad.audio, let url = resolve(path) {
            adPlayer.replaceCurrentItem(with: AVPlayerItem(url: url))
            adPlayer.play()
            player.volume = 0.25   // duck the conversation under the ad
        }
        after(length) { [weak self] in
            guard let self else { return }
            self.adOnScreen = false
            self.setOverlay(visible: false)
            self.adPlayer.pause()
            self.player.volume = 1
        }
    }

    private func setOverlay(visible: Bool) {
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = overlayLayer.presentation()?.opacity ?? overlayLayer.opacity
        fade.toValue = visible ? 1 : 0
        fade.duration = 0.4
        overlayLayer.opacity = visible ? 1 : 0
        overlayLayer.add(fade, forKey: "fade")
    }
}
