//
//  LatestMessageAccessoryView.swift
//  Bark
//
//  Content of the tab bar's bottom accessory (iOS 26+). The system renders it
//  inside a Liquid Glass capsule above the tab bar and shrinks it inline next
//  to the tab bar when the bar minimizes on scroll. Shows the most recent
//  push with its group icon; tapping opens the message history.
//

import Kingfisher
import RealmSwift
import UIKit

final class LatestMessageAccessoryView: UIControl {
    private let iconView: UIImageView = {
        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFill
        imageView.layer.cornerRadius = 7
        imageView.layer.cornerCurve = .continuous
        imageView.clipsToBounds = true
        return imageView
    }()

    private let titleLabel: UILabel = {
        let label = UILabel()
        label.font = UIFontMetrics(forTextStyle: .subheadline).scaledFont(for: .systemFont(ofSize: 15, weight: .semibold))
        label.adjustsFontForContentSizeCategory = true
        label.textColor = .label
        label.lineBreakMode = .byTruncatingTail
        return label
    }()

    private let detailLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont.preferredFont(forTextStyle: .caption1)
        label.adjustsFontForContentSizeCategory = true
        label.textColor = .secondaryLabel
        label.lineBreakMode = .byTruncatingTail
        return label
    }()

    private let timeLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont.preferredFont(forTextStyle: .caption2)
        label.adjustsFontForContentSizeCategory = true
        label.textColor = .tertiaryLabel
        label.setContentCompressionResistancePriority(.required, for: .horizontal)
        label.setContentHuggingPriority(.required, for: .horizontal)
        return label
    }()

    private let textStack: UIStackView = {
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 1
        stack.isUserInteractionEnabled = false
        return stack
    }()

    private var observers: [NSObjectProtocol] = []
    private var latestDate: Date?

    init() {
        super.init(frame: .zero)
        iconView.isUserInteractionEnabled = false
        timeLabel.isUserInteractionEnabled = false
        textStack.addArrangedSubview(titleLabel)
        textStack.addArrangedSubview(detailLabel)
        addSubview(iconView)
        addSubview(textStack)
        addSubview(timeLabel)

        iconView.snp.makeConstraints { make in
            make.leading.equalToSuperview().offset(14)
            make.centerY.equalToSuperview()
            make.width.height.equalTo(28)
        }
        textStack.snp.makeConstraints { make in
            make.leading.equalTo(iconView.snp.trailing).offset(10)
            make.centerY.equalToSuperview()
            make.top.greaterThanOrEqualToSuperview().offset(4)
            make.bottom.lessThanOrEqualToSuperview().offset(-4)
        }
        timeLabel.snp.makeConstraints { make in
            make.leading.equalTo(textStack.snp.trailing).offset(8)
            make.trailing.equalToSuperview().offset(-16)
            make.centerY.equalToSuperview()
        }

        isAccessibilityElement = true
        accessibilityTraits = .button
        accessibilityHint = "historyMessage".localized

        let center = NotificationCenter.default
        for name in [kBarkMessagesDidChangeNotification, UIApplication.didBecomeActiveNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                self?.reload()
            })
        }
        reload()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        observers.forEach { NotificationCenter.default.removeObserver($0) }
    }

    override var isHighlighted: Bool {
        didSet {
            UIView.animate(withDuration: 0.15) {
                self.alpha = self.isHighlighted ? 0.55 : 1
            }
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        // Inline (minimized) accessory is narrow: keep the title, drop the rest.
        let isCompact = bounds.width < 240
        detailLabel.isHidden = isCompact || detailLabel.text?.isEmpty != false
        timeLabel.isHidden = isCompact
    }

    func reload() {
        let latest = (try? Realm())?
            .objects(Message.self)
            .sorted(byKeyPath: "createDate", ascending: false)
            .first

        guard let latest else {
            showPlaceholder()
            return
        }

        let body = (latest.body ?? "")
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespaces)
        let title = [latest.title, latest.subtitle, latest.group]
            .compactMap { $0 }
            .first { !$0.isEmpty }
        titleLabel.text = title ?? body
        detailLabel.text = title == nil ? nil : body
        latestDate = latest.createDate
        timeLabel.text = latest.createDate?.agoFormatString()

        if let icon = latest.icon, let url = URL(string: icon) {
            let groupUrl = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.com.piiziy.homepush")
            let cache = (try? ImageCache(name: "shared", cacheDirectoryURL: groupUrl)) ?? ImageCache.default
            iconView.tintColor = nil
            iconView.backgroundColor = nil
            iconView.contentMode = .scaleAspectFill
            iconView.kf.setImage(with: url, placeholder: Self.bellImage, options: [.targetCache(cache), .transition(.fade(0.2))])
        } else {
            setBellIcon()
        }

        accessibilityLabel = [titleLabel.text, detailLabel.text, timeLabel.text]
            .compactMap { $0 }
            .joined(separator: ", ")
        setNeedsLayout()
    }

    private func showPlaceholder() {
        setBellIcon()
        titleLabel.text = "accessoryNoMessages".localized
        detailLabel.text = "accessoryNoMessagesHint".localized
        timeLabel.text = nil
        accessibilityLabel = titleLabel.text
        setNeedsLayout()
    }

    private static let bellImage = UIImage(
        systemName: "bell.badge.fill",
        withConfiguration: UIImage.SymbolConfiguration(pointSize: 15, weight: .semibold)
    )

    private func setBellIcon() {
        iconView.kf.cancelDownloadTask()
        iconView.image = Self.bellImage
        iconView.contentMode = .center
        iconView.tintColor = .white
        iconView.backgroundColor = .systemBlue
    }
}
