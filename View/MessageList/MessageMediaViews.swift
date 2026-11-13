//
//  MessageMediaViews.swift
//  Bark
//
//  Media helpers for the message history: the Liquid Glass play button,
//  video thumbnails and full-screen playback.
//

import AVFoundation
import AVKit
import UIKit

/// Round play button. Uses the system Liquid Glass button style on iOS 27
/// (clear glass reads well on top of video frames), a dark translucent
/// capsule before that. Being a UIButton it wins over the card's tap gesture.
final class GlassPlayButton: UIButton {
    static let diameter: CGFloat = 56

    init() {
        super.init(frame: .zero)
        let symbol = UIImage(
            systemName: "play.fill",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 20, weight: .semibold)
        )
        var config: UIButton.Configuration
        if #available(iOS 27.0, *) {
            config = .clearGlass()
        } else {
            config = .filled()
            config.baseBackgroundColor = UIColor.black.withAlphaComponent(0.45)
        }
        config.image = symbol
        config.baseForegroundColor = .white
        config.cornerStyle = .capsule
        // Optical centering of the triangle
        config.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: 3, bottom: 0, trailing: 0)
        configuration = config

        accessibilityLabel = "playVideo".localized
        snp.makeConstraints { make in
            make.width.height.equalTo(GlassPlayButton.diameter)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

/// Generates and memory-caches the first frame of a video.
enum VideoThumbnailProvider {
    private static let cache: NSCache<NSURL, UIImage> = {
        let cache = NSCache<NSURL, UIImage>()
        cache.countLimit = 60
        return cache
    }()

    static func cached(_ url: URL) -> UIImage? {
        cache.object(forKey: url as NSURL)
    }

    static func thumbnail(for url: URL) async -> UIImage? {
        if let image = cached(url) {
            return image
        }
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 960, height: 960)
        let image: UIImage? = await withCheckedContinuation { continuation in
            generator.generateCGImagesAsynchronously(forTimes: [NSValue(time: .zero)]) { _, cgImage, _, _, _ in
                continuation.resume(returning: cgImage.map { UIImage(cgImage: $0) })
            }
        }
        if let image {
            cache.setObject(image, forKey: url as NSURL)
        }
        return image
    }
}

enum MessageVideoPlayer {
    /// Presents the system player full screen from the view's view controller.
    static func play(_ url: URL, from view: UIView) {
        guard let presenter = view.bk_viewController else {
            return
        }
        // Play sound even when the ring/silent switch is on.
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
        let player = AVPlayer(url: url)
        let controller = AVPlayerViewController()
        controller.player = player
        controller.allowsPictureInPicturePlayback = true
        presenter.present(controller, animated: true) {
            player.play()
        }
    }
}

extension UIResponder {
    /// The closest view controller in the responder chain.
    var bk_viewController: UIViewController? {
        var responder: UIResponder? = self
        while let current = responder {
            if let viewController = current as? UIViewController {
                return viewController
            }
            responder = current.next
        }
        return nil
    }
}
