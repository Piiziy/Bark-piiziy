//
//  NotificationViewController.swift
//  NotificationContentExtension
//
//  Created by huangfeng on 2018/7/4.
//  Copyright © 2018 Fin. All rights reserved.
//

import AVFoundation
import UIKit
import UserNotifications
import UserNotificationsUI

class NotificationViewController: UIViewController, UNNotificationContentExtension {
    let noticeLabel: UILabel = {
        let label = UILabel()
        label.textColor = UIColor(named: "notification_copy_color")
        label.font = UIFont.preferredFont(ofSize: 16)
        label.adjustsFontForContentSizeCategory = true
        label.textAlignment = .center
        return label
    }()

    /// 增加图片view
    let imageView: UIImageView = {
        let view = UIImageView()
        view.contentMode = .scaleAspectFit
        return view
    }()

    /// Video playback (`video` parameter)
    var player: AVPlayer?
    var playerLayer: AVPlayerLayer?
    var playerEndObserver: NSObjectProtocol?
    /// Attachment URL we hold security-scoped access to
    var securityScopedVideoURL: URL?

    deinit {
        player?.pause()
        if let playerEndObserver {
            NotificationCenter.default.removeObserver(playerEndObserver)
        }
        securityScopedVideoURL?.stopAccessingSecurityScopedResource()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        self.view.addSubview(self.noticeLabel)
        self.view.addSubview(self.imageView)
        self.preferredContentSize = CGSize(width: 0, height: 1)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        self.preferredContentSize = self.playerLayer == nil ? CGSize(width: 0, height: 1) : self.imageView.frame.size
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        self.preferredContentSize = self.playerLayer == nil ? CGSize(width: 0, height: 1) : self.imageView.frame.size
    }

    func didReceive(_ notification: UNNotification) {
        ///  处理图片显示 (a video, if present, takes the place of the image)
        if !self.videoHandler(notification) {
            self.ImageHandler(notification)
        }

        guard notification.request.content.userInfo["autocopy"] as? String == "1"
            || notification.request.content.userInfo["automaticallycopy"] as? String == "1"
        else {
            return
        }
        if let copy = notification.request.content.userInfo["copy"] as? String {
            UIPasteboard.general.string = copy
        } else {
            UIPasteboard.general.string = notification.request.content.bodyText
        }
    }

    func didReceive(_ response: UNNotificationResponse, completionHandler completion: @escaping (UNNotificationContentExtensionResponseOption) -> Void) {
        switch response.actionIdentifier {
        case "copy":
            self.copyAction(response, completionHandler: completion)
        case "mute":
            self.muteAction(response, duration: 60 * 60, completionHandler: completion)
        case "mute10Minutes":
            self.muteAction(response, duration: 10 * 60, completionHandler: completion)
        default:
            completion(.dismiss)
        }
    }

    /// 复制
    func copyAction(_ response: UNNotificationResponse, completionHandler completion: @escaping (UNNotificationContentExtensionResponseOption) -> Void) {
        let userInfo = response.notification.request.content.userInfo

        if let copy = userInfo["copy"] as? String {
            UIPasteboard.general.string = copy
        } else {
            var content = ""
            if !response.notification.request.content.title.isEmpty {
                content += "\(response.notification.request.content.title)\n"
            }
            if !response.notification.request.content.subtitle.isEmpty {
                content += "\(response.notification.request.content.subtitle)\n"
            }
            if !response.notification.request.content.bodyText.isEmpty {
                content += "\(response.notification.request.content.bodyText)\n"
            }
            if let url = userInfo["url"] as? String, !url.isEmpty {
                content += "\(url)\n"
            }
            content = content.trimmingCharacters(in: .whitespacesAndNewlines)
            UIPasteboard.general.string = content
        }

        showTips(text: "Copy".localized)
        completion(.doNotDismiss)
    }

    /// 静音分组
    func muteAction(_ response: UNNotificationResponse, duration: TimeInterval, completionHandler completion: @escaping (UNNotificationContentExtensionResponseOption) -> Void) {
        let groupName = response.notification.request.content.threadIdentifier
        GroupMuteSettingManager().settings[groupName] = Date() + duration

        showTips(text: String(format: "groupMuted".localized, groupName.isEmpty ? "default".localized : groupName))
        completion(.doNotDismiss)
    }

    func showTips(text: String) {
        /// 调整页面整个大小为image的高度和label的高度总和
        self.preferredContentSize = CGSize(width: 0, height: self.imageView.frame.height + 40)
        self.noticeLabel.text = text
        /// 调整 y的位置，如果复制内容，显示在图片的底部
        self.noticeLabel.frame = CGRect(x: 0, y: self.imageView.frame.height, width: self.view.bounds.width, height: 40)
    }
}

extension NotificationViewController {
    ///  处理下拉显示大图
    func ImageHandler(_ notification: UNNotification) {
        Task {
            guard let imageUrl = notification.request.content.userInfo["image"] as? String,
                  let imageFileUrl = await ImageDownloader.downloadImage(imageUrl),
                  let image = UIImage(contentsOfFile: imageFileUrl)
            else {
                self.imageView.frame = .zero
                return
            }
            /// 计算图片的比例按照通知界面缩放
            let viewWidth = view.bounds.size.width
            let aspectRatio = image.size.width / image.size.height
            let viewHeight = viewWidth / aspectRatio
            let size = CGSize(width: viewWidth, height: viewHeight)

            DispatchQueue.main.async {
                self.preferredContentSize = size
                self.imageView.image = image
                self.imageView.frame = CGRect(x: 0, y: 0, width: size.width, height: size.height)
            }
        }
    }
}

// MARK: - Video

extension NotificationViewController {
    /// The system draws a play/pause button over the video.
    @objc var mediaPlayPauseButtonType: UNNotificationContentExtensionMediaPlayPauseButtonType {
        player == nil ? .none : .overlay
    }

    @objc var mediaPlayPauseButtonFrame: CGRect {
        imageView.frame
    }

    @objc var mediaPlayPauseButtonTintColor: UIColor {
        .white
    }

    @objc func mediaPlay() {
        player?.play()
    }

    @objc func mediaPause() {
        player?.pause()
    }

    /// Plays the `video` parameter. Uses the attachment the service extension
    /// downloaded when there is one, otherwise streams the URL.
    /// - Returns: false when the notification has no video.
    func videoHandler(_ notification: UNNotification) -> Bool {
        let content = notification.request.content
        guard let urlString = content.userInfo["video"] as? String,
              let remoteURL = URL(string: urlString.trimmingCharacters(in: .whitespacesAndNewlines)),
              let scheme = remoteURL.scheme?.lowercased(),
              scheme == "https" || scheme == "http"
        else {
            return false
        }

        var videoURL = remoteURL
        if let attachment = content.attachments.first(where: { $0.identifier == "video" }),
           attachment.url.startAccessingSecurityScopedResource()
        {
            securityScopedVideoURL = attachment.url
            videoURL = attachment.url
        }

        let asset = AVURLAsset(url: videoURL)
        let item = AVPlayerItem(asset: asset)
        let player = AVPlayer(playerItem: item)
        player.actionAtItemEnd = .none
        self.player = player

        let layer = AVPlayerLayer(player: player)
        layer.videoGravity = .resizeAspect
        layer.backgroundColor = UIColor.black.cgColor
        imageView.image = nil
        imageView.backgroundColor = .black
        imageView.layer.addSublayer(layer)
        playerLayer = layer

        // Loop
        playerEndObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak player] _ in
            player?.seek(to: .zero)
            player?.play()
        }

        // Start with a 16:9 box, then resize to the real aspect ratio.
        layoutVideo(aspectRatio: 16.0 / 9.0)
        Task {
            var aspectRatio: CGFloat = 16.0 / 9.0
            if let track = try? await asset.loadTracks(withMediaType: .video).first,
               let loaded = try? await track.load(.naturalSize, .preferredTransform)
            {
                let size = loaded.0.applying(loaded.1)
                if abs(size.width) > 0, abs(size.height) > 0 {
                    aspectRatio = abs(size.width) / abs(size.height)
                }
            }
            await MainActor.run {
                self.layoutVideo(aspectRatio: aspectRatio)
                // The user expanded the notification on purpose: start playing.
                self.player?.play()
                self.extensionContext?.mediaPlayingStarted()
            }
        }
        return true
    }

    func layoutVideo(aspectRatio: CGFloat) {
        let width = view.bounds.size.width
        // Keep tall (portrait) videos from taking the whole screen.
        let height = min(width / aspectRatio, width * 1.25)
        let frame = CGRect(x: 0, y: 0, width: width, height: height)
        imageView.frame = frame
        playerLayer?.frame = imageView.bounds
        preferredContentSize = frame.size
    }
}
