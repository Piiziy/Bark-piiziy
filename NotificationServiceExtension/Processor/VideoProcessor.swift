//
//  VideoProcessor.swift
//  NotificationServiceExtension
//
//  Attaches the video given in the `video` parameter to the notification.
//  - If an `image` was attached already, it stays as the thumbnail and the
//    video is streamed by the content extension when the notification is
//    expanded, so nothing is downloaded here.
//  - Otherwise the video is downloaded (<= 50 MB, the system limit for video
//    attachments) so iOS can show a thumbnail and play it inline.
//

import Foundation
import UniformTypeIdentifiers

class VideoProcessor: NotificationContentProcessor {
    /// UNNotificationAttachment limit for video files.
    static let maxVideoBytes: Int64 = 50 * 1024 * 1024
    /// Keep well under the ~30s the extension gets, IconProcessor still has to run.
    static let downloadTimeout: TimeInterval = 15

    private static let supportedTypes: [UTType] = [.mpeg4Movie, .quickTimeMovie, .mpeg, .mpeg2Video, .avi, .appleProtectedMPEG4Video]

    func process(identifier: String, content bestAttemptContent: UNMutableNotificationContent) async throws -> UNMutableNotificationContent {
        guard let videoUrl = Self.videoURL(from: bestAttemptContent.userInfo),
              bestAttemptContent.attachments.isEmpty,
              let fileUrl = await Self.download(videoUrl)
        else {
            return bestAttemptContent
        }

        do {
            let attachment = try UNNotificationAttachment(
                identifier: "video",
                url: fileUrl,
                options: [UNNotificationAttachmentOptionsThumbnailTimeKey: 0]
            )
            bestAttemptContent.attachments = [attachment]
        } catch {
            try? FileManager.default.removeItem(at: fileUrl)
        }
        return bestAttemptContent
    }

    /// The `video` parameter as an http(s) URL.
    static func videoURL(from userInfo: [AnyHashable: Any]) -> URL? {
        guard let string = userInfo["video"] as? String,
              let url = URL(string: string.trimmingCharacters(in: .whitespacesAndNewlines)),
              let scheme = url.scheme?.lowercased(),
              scheme == "https" || scheme == "http"
        else {
            return nil
        }
        return url
    }

    /// Downloads the video into a temporary file with a proper extension.
    static func download(_ url: URL) async -> URL? {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = downloadTimeout
        config.timeoutIntervalForResource = downloadTimeout
        let session = URLSession(configuration: config)
        defer { session.finishTasksAndInvalidate() }

        guard let (tempUrl, response) = try? await session.download(from: url) else {
            return nil
        }
        defer { try? FileManager.default.removeItem(at: tempUrl) }

        if let http = response as? HTTPURLResponse, !(200 ..< 300).contains(http.statusCode) {
            return nil
        }
        let size = (try? FileManager.default.attributesOfItem(atPath: tempUrl.path)[.size] as? NSNumber)?.int64Value ?? 0
        guard size > 0, size <= maxVideoBytes else {
            return nil
        }

        let type = response.mimeType.flatMap { UTType(mimeType: $0) }
            ?? UTType(filenameExtension: url.pathExtension)
        let fileExtension: String
        if let type, supportedTypes.contains(where: { type.conforms(to: $0) }),
           let ext = type.preferredFilenameExtension {
            fileExtension = ext
        } else if ["mp4", "m4v", "mov"].contains(url.pathExtension.lowercased()) {
            fileExtension = url.pathExtension.lowercased()
        } else {
            fileExtension = "mp4"
        }

        let dest = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(fileExtension)
        do {
            try FileManager.default.moveItem(at: tempUrl, to: dest)
        } catch {
            return nil
        }
        return dest
    }
}
