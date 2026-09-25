import AVKit
import OroroKit
import UIKit

/// Drives a stock `AVPlayerViewController` (Apple doesn't support
/// subclassing it) and adds Ororo's subtitles.
///
/// Ororo's HLS streams have no subtitle tracks; subtitles are separate
/// WebVTT files. They're drawn in the player's content overlay, which also
/// allows a second language at the same time. The subtitle menu lives in the
/// player's transport bar.
@MainActor
final class PlaybackCoordinator {
    let controller = AVPlayerViewController()
    var onProgress: ((Double, Double) -> Void)?
    var onFinished: (() -> Void)?

    private var player: AVPlayer? { controller.player }
    private var info: PlaybackInfo?
    private var timeObserver: Any?
    private var endObserver: NSObjectProtocol?
    private var lastSavedPosition: Double = 0
    private var didFinish = false

    private var primaryTrack: SubtitleTrack?
    private var secondaryTrack: SubtitleTrack?
    private var trackCache: [String: SubtitleTrack] = [:]

    private let primaryLabel = PlaybackCoordinator.makeLabel(size: 46, color: .white)
    private let secondaryLabel = PlaybackCoordinator.makeLabel(size: 36, color: UIColor(white: 0.85, alpha: 1))

    private var primaryLanguage: String {
        get { UserDefaults.standard.string(forKey: SubtitleSettings.primaryKey) ?? "en" }
        set { UserDefaults.standard.set(newValue, forKey: SubtitleSettings.primaryKey) }
    }

    private var secondaryLanguage: String {
        get { UserDefaults.standard.string(forKey: SubtitleSettings.secondaryKey) ?? SubtitleSettings.off }
        set { UserDefaults.standard.set(newValue, forKey: SubtitleSettings.secondaryKey) }
    }

    // MARK: Lifecycle

    func start(request: PlaybackRequest, info: PlaybackInfo) {
        self.info = info
        installSubtitleOverlay()

        let item = AVPlayerItem(url: info.streamURL)
        item.externalMetadata = [
            Self.metadata(.commonIdentifierTitle, request.title),
            Self.metadata(.iTunesMetadataTrackSubTitle, request.subtitle ?? ""),
        ]
        let player = AVPlayer(playerItem: item)
        controller.player = player

        if let startAt = request.startAt {
            player.seek(to: CMTime(seconds: startAt, preferredTimescale: 600),
                        toleranceBefore: .zero, toleranceAfter: .zero)
            lastSavedPosition = startAt
        }

        let interval = CMTime(seconds: 0.25, preferredTimescale: 600)
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            MainActor.assumeIsolated { self?.tick(time.seconds) }
        }
        endObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime,
                                                             object: item, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.finish() }
        }

        selectAudio(for: item)
        loadSubtitles()
        player.play()
    }

    /// Ororo's playlists mark their only audio rendition as auxiliary (not
    /// DEFAULT or AUTOSELECT), so automatic media selection picks none and
    /// the video plays silently. Select it explicitly.
    private func selectAudio(for item: AVPlayerItem) {
        Task {
            guard let group = try? await item.asset.loadMediaSelectionGroup(for: .audible),
                  item.currentMediaSelection.selectedMediaOption(in: group) == nil,
                  let option = group.options.first(where: \.isPlayable) ?? group.options.first
            else { return }
            item.select(option, in: group)
        }
    }

    func stop() {
        saveProgress()
        if let timeObserver { player?.removeTimeObserver(timeObserver) }
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        timeObserver = nil
        endObserver = nil
        player?.pause()
    }

    private func installSubtitleOverlay() {
        controller.loadViewIfNeeded()
        guard let overlay = controller.contentOverlayView else { return }
        let stack = UIStackView(arrangedSubviews: [secondaryLabel, primaryLabel])
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        overlay.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: overlay.centerXAnchor),
            stack.widthAnchor.constraint(lessThanOrEqualTo: overlay.widthAnchor, multiplier: 0.8),
            stack.bottomAnchor.constraint(equalTo: overlay.bottomAnchor, constant: -70),
        ])
    }

    // MARK: Playback

    private func tick(_ seconds: Double) {
        guard seconds.isFinite else { return }
        primaryLabel.text = primaryTrack?.text(at: seconds)
        primaryLabel.isHidden = primaryLabel.text == nil
        secondaryLabel.text = secondaryTrack?.text(at: seconds)
        secondaryLabel.isHidden = secondaryLabel.text == nil

        if abs(seconds - lastSavedPosition) >= 10 {
            saveProgress()
        }
    }

    private func saveProgress() {
        guard let player, let item = player.currentItem else { return }
        let position = player.currentTime().seconds
        let duration = item.duration.seconds
        guard position.isFinite, position > 0 else { return }
        lastSavedPosition = position
        onProgress?(position, duration.isFinite ? duration : 0)
    }

    private func finish() {
        guard !didFinish else { return }
        didFinish = true
        saveProgress()
        onFinished?()
    }

    // MARK: Subtitles

    private func loadSubtitles() {
        rebuildSubtitleMenu()
        let primary = primaryLanguage, secondary = secondaryLanguage
        Task {
            primaryTrack = await track(for: primary)
            secondaryTrack = secondary == primary ? nil : await track(for: secondary)
        }
    }

    private func track(for language: String) async -> SubtitleTrack? {
        guard language != SubtitleSettings.off, let subtitle = info?.subtitle(for: language) else { return nil }
        if let cached = trackCache[language] { return cached }
        guard let (data, _) = try? await URLSession.shared.data(from: subtitle.url) else { return nil }
        let track = SubtitleTrack(webVTT: String(decoding: data, as: UTF8.self))
        trackCache[language] = track
        return track
    }

    private func rebuildSubtitleMenu() {
        let available = info?.subtitles.map(\.lang) ?? []
        controller.transportBarCustomMenuItems = [
            languageMenu(title: "Subtitles", image: "captions.bubble", available: available,
                         selected: primaryLanguage) { [weak self] lang in
                self?.primaryLanguage = lang
                self?.loadSubtitles()
            },
            languageMenu(title: "Second Subtitles", image: "text.bubble", available: available,
                         selected: secondaryLanguage) { [weak self] lang in
                self?.secondaryLanguage = lang
                self?.loadSubtitles()
            },
        ]
    }

    private func languageMenu(title: String, image: String, available: [String], selected: String,
                              choose: @escaping (String) -> Void) -> UIMenu {
        let off = UIAction(title: "Off", state: selected == SubtitleSettings.off ? .on : .off) { _ in
            choose(SubtitleSettings.off)
        }
        let languages = available.map { lang in
            UIAction(title: languageName(lang), state: lang == selected ? .on : .off) { _ in choose(lang) }
        }
        return UIMenu(title: title, image: UIImage(systemName: image),
                      options: .singleSelection, children: [off] + languages)
    }

    private static func makeLabel(size: CGFloat, color: UIColor) -> UILabel {
        let label = UILabel()
        label.font = .systemFont(ofSize: size, weight: .semibold)
        label.textColor = color
        label.textAlignment = .center
        label.numberOfLines = 0
        label.isHidden = true
        label.layer.shadowColor = UIColor.black.cgColor
        label.layer.shadowOffset = CGSize(width: 0, height: 2)
        label.layer.shadowRadius = 4
        label.layer.shadowOpacity = 1
        return label
    }

    private static func metadata(_ identifier: AVMetadataIdentifier, _ value: String) -> AVMetadataItem {
        let item = AVMutableMetadataItem()
        item.identifier = identifier
        item.value = value as NSString
        item.extendedLanguageTag = "und"
        return item.copy() as! AVMetadataItem
    }
}
