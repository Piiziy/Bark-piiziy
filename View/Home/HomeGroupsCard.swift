//
//  HomeGroupsCard.swift
//  Bark
//
//  "Subscribed groups" card on the home screen: every notification group
//  received so far, each shown with the icon its pushes carry (usually the
//  server's per-group default icon), how many messages it has and when the
//  last one arrived. Tapping a chip opens that group's history.
//
//  On iOS 27 the chips are interactive Liquid Glass placed in a
//  UIGlassContainerEffect so neighbouring chips blend into each other.
//

import Kingfisher
import RealmSwift
import UIKit

final class HomeGroupsCard: GlassView {
    struct Item {
        let group: String?
        let icon: String?
        let count: Int
        let lastDate: Date?
    }

    /// Called with the tapped group (nil = messages without a group).
    var onSelectGroup: ((String?) -> Void)?

    private static let maxGroups = 12

    private let sectionLabel: UILabel = {
        let label = UILabel()
        label.text = "subscribedGroups".localized
        label.font = UIFont.preferredFont(forTextStyle: .headline)
        label.adjustsFontForContentSizeCategory = true
        return label
    }()

    private let descriptionLabel: UILabel = {
        let label = UILabel()
        label.text = "subscribedGroupsDetail".localized
        label.font = UIFont.preferredFont(forTextStyle: .subheadline)
        label.adjustsFontForContentSizeCategory = true
        label.textColor = .secondaryLabel
        label.numberOfLines = 0
        return label
    }()

    private let scrollView: UIScrollView = {
        let scrollView = UIScrollView()
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.alwaysBounceHorizontal = true
        // Let the chips' glass highlight render past the scroll bounds
        scrollView.clipsToBounds = false
        return scrollView
    }()

    private let chipStack: UIStackView = {
        let stack = UIStackView()
        stack.axis = .horizontal
        stack.spacing = 8
        stack.alignment = .fill
        return stack
    }()

    private var observers: [NSObjectProtocol] = []

    override init() {
        super.init()

        let contentStack = UIStackView(arrangedSubviews: [sectionLabel, descriptionLabel, scrollView])
        contentStack.axis = .vertical
        contentStack.spacing = 6
        contentStack.setCustomSpacing(14, after: descriptionLabel)
        contentView.addSubview(contentStack)
        contentStack.snp.makeConstraints { make in
            make.edges.equalToSuperview().inset(16)
        }

        let chipsHost: UIView
        if #available(iOS 27.0, *) {
            let container = UIVisualEffectView(effect: UIGlassContainerEffect())
            container.clipsToBounds = false
            container.contentView.addSubview(chipStack)
            chipsHost = container
            chipStack.snp.makeConstraints { make in
                make.edges.equalToSuperview()
            }
        } else {
            chipsHost = chipStack
        }
        scrollView.addSubview(chipsHost)
        chipsHost.snp.makeConstraints { make in
            make.edges.equalTo(scrollView.contentLayoutGuide)
            make.height.equalTo(scrollView.frameLayoutGuide)
        }
        scrollView.snp.makeConstraints { make in
            make.height.equalTo(GroupChip.height)
        }

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

    func reload() {
        let items = Self.loadItems()
        isHidden = items.isEmpty
        chipStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        for item in items {
            let chip = GroupChip(item: item)
            chip.onTap = { [weak self] in
                self?.onSelectGroup?(item.group)
            }
            chipStack.addArrangedSubview(chip)
        }
    }

    private static func loadItems() -> [Item] {
        guard let realm = try? Realm() else {
            return []
        }
        let messages = realm.objects(Message.self).sorted(byKeyPath: "createDate", ascending: false)
        let groups = messages.distinct(by: ["group"])
        var items: [Item] = []
        for latest in groups.prefix(maxGroups) {
            let inGroup: Results<Message>
            if let group = latest.group {
                inGroup = messages.filter("group == %@", group)
            } else {
                inGroup = messages.filter("group == nil")
            }
            let icon = latest.icon ?? inGroup.filter("icon != nil").first?.icon
            items.append(Item(group: latest.group, icon: icon, count: inGroup.count, lastDate: latest.createDate))
        }
        return items
    }
}

/// One group: icon + name + "12 · 3m ago", on interactive glass.
private final class GroupChip: UIView {
    static let height: CGFloat = 52

    var onTap: (() -> Void)?

    private let glassView: GlassView = {
        let view = GlassView()
        view.cornerRadius = GroupChip.height / 2
        view.isInteractive = true
        view.legacyBackgroundColor = BKColor.home.legacyButton
        return view
    }()

    private let iconView: UIImageView = {
        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFill
        imageView.layer.cornerRadius = 8
        imageView.layer.cornerCurve = .continuous
        imageView.clipsToBounds = true
        return imageView
    }()

    private let nameLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont.preferredFont(forTextStyle: .subheadline)
        label.adjustsFontForContentSizeCategory = true
        label.textColor = .label
        return label
    }()

    private let detailLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont.preferredFont(forTextStyle: .caption2)
        label.adjustsFontForContentSizeCategory = true
        label.textColor = .secondaryLabel
        return label
    }()

    init(item: HomeGroupsCard.Item) {
        super.init(frame: .zero)
        let name = item.group ?? "default".localized
        nameLabel.text = name
        detailLabel.text = [String(item.count), item.lastDate?.agoFormatString()]
            .compactMap { $0 }
            .joined(separator: " · ")

        let textStack = UIStackView(arrangedSubviews: [nameLabel, detailLabel])
        textStack.axis = .vertical
        textStack.spacing = 0

        addSubview(glassView)
        glassView.contentView.addSubview(iconView)
        glassView.contentView.addSubview(textStack)
        glassView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
            make.height.equalTo(GroupChip.height)
        }
        iconView.snp.makeConstraints { make in
            make.leading.equalToSuperview().offset(10)
            make.centerY.equalToSuperview()
            make.width.height.equalTo(32)
        }
        textStack.snp.makeConstraints { make in
            make.leading.equalTo(iconView.snp.trailing).offset(10)
            make.trailing.equalToSuperview().offset(-18)
            make.centerY.equalToSuperview()
        }

        if let icon = item.icon, let url = URL(string: icon) {
            let groupUrl = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.com.piiziy.homepush")
            let cache = (try? ImageCache(name: "shared", cacheDirectoryURL: groupUrl)) ?? ImageCache.default
            iconView.kf.setImage(with: url, options: [.targetCache(cache), .loadDiskFileSynchronously])
        } else {
            iconView.image = UIImage(
                systemName: "bell.fill",
                withConfiguration: UIImage.SymbolConfiguration(pointSize: 14, weight: .semibold)
            )
            iconView.contentMode = .center
            iconView.tintColor = .white
            iconView.backgroundColor = .systemBlue
        }

        isAccessibilityElement = true
        accessibilityTraits = .button
        accessibilityLabel = [name, detailLabel.text].compactMap { $0 }.joined(separator: ", ")

        // A gesture (not UIControl tracking) so touches still reach the
        // interactive glass underneath and it can react to the press.
        addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(tapped)))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc private func tapped() {
        onTap?()
    }
}
