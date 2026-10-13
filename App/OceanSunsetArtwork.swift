import AVFoundation
import SwiftUI
import UIKit

/// A silent, local loop of the original ascii.rest scene, with a static fallback.
struct OceanSunsetArtwork: UIViewRepresentable {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    var contentMode: UIView.ContentMode = .scaleAspectFit

    private var artworkName: String { colorScheme == .light ? "OceanSunsetLight" : "OceanSunset" }

    func makeUIView(context: Context) -> OceanSunsetImageView {
        OceanSunsetImageView(artworkName: artworkName)
    }

    func updateUIView(_ view: OceanSunsetImageView, context: Context) {
        view.artworkName = artworkName
        view.contentMode = contentMode
        view.videoGravity = contentMode == .scaleAspectFill ? .resizeAspectFill : .resizeAspect
        view.animationEnabled = scenePhase == .active && !reduceMotion
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: OceanSunsetImageView, context: Context) -> CGSize? {
        guard let width = proposal.width, let height = proposal.height else { return nil }
        return CGSize(width: width, height: height)
    }

    static func dismantleUIView(_ view: OceanSunsetImageView, coordinator: ()) {
        view.animationEnabled = false
    }
}

final class OceanSunsetImageView: UIImageView {
    var artworkName: String {
        didSet {
            guard artworkName != oldValue else { return }
            player?.pause()
            looper?.disableLooping()
            playerLayer.player = nil
            player = nil
            looper = nil
            playing = false
            playerLayer.isHidden = true
            updateStillImage()
            updatePlayback()
        }
    }
    var animationEnabled = false {
        didSet { updatePlayback() }
    }
    var videoGravity: AVLayerVideoGravity = .resizeAspect {
        didSet { playerLayer.videoGravity = videoGravity }
    }

    private let playerLayer = AVPlayerLayer()
    private var player: AVQueuePlayer?
    private var looper: AVPlayerLooper?
    private var visibilityTimer: Timer?
    private var playing = false

    init(artworkName: String) {
        self.artworkName = artworkName
        super.init(frame: .zero)
        updateStillImage()
        clipsToBounds = true
        isUserInteractionEnabled = false
        accessibilityElementsHidden = true
        playerLayer.isHidden = true
        layer.addSublayer(playerLayer)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func updateStillImage() {
        image = UIImage(named: artworkName)
        backgroundColor = artworkName == "OceanSunsetLight"
            ? UIColor(red: 240 / 255, green: 220 / 255, blue: 229 / 255, alpha: 1)
            : UIColor(red: 11 / 255, green: 8 / 255, blue: 23 / 255, alpha: 1)
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        updatePlayback()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        // Resizing the artwork should not implicitly animate the video layer.
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        playerLayer.frame = bounds
        CATransaction.commit()
        updateVisibility()
    }

    private func updatePlayback() {
        guard animationEnabled, window != nil else {
            visibilityTimer?.invalidate()
            visibilityTimer = nil
            player?.pause()
            playing = false
            playerLayer.isHidden = true
            return
        }
        if visibilityTimer == nil {
            let timer = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
                self?.updateVisibility()
            }
            visibilityTimer = timer
            RunLoop.main.add(timer, forMode: .common)
        }
        updateVisibility()
    }

    private func updateVisibility() {
        guard animationEnabled, let window else { return }
        let visible = !bounds.isEmpty && convert(bounds, to: window).intersects(window.bounds)
        if visible, player == nil,
           let url = Bundle.main.url(forResource: artworkName, withExtension: "mp4") {
            let player = AVQueuePlayer()
            player.isMuted = true
            player.preventsDisplaySleepDuringVideoPlayback = false
            player.audiovisualBackgroundPlaybackPolicy = .pauses
            looper = AVPlayerLooper(player: player, templateItem: AVPlayerItem(url: url))
            self.player = player
            playerLayer.player = player
        }
        if visible != playing {
            if visible { player?.play() }
            else { player?.pause() }
            playing = visible
        }
        playerLayer.isHidden = !playerLayer.isReadyForDisplay
    }

    deinit {
        visibilityTimer?.invalidate()
        player?.pause()
        looper?.disableLooping()
    }
}
