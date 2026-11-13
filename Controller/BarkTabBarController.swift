//
//  BarkTabBarController.swift
//  Bark
//
//  Created by huangfeng on 2024/8/20.
//  Copyright © 2024 Fin. All rights reserved.
//

import Material
import RxCocoa
import UIKit

class BarkTabBarController: StateRestoringTabBarContr {
    override func viewDidLoad() {
        super.viewDidLoad()
        self.tabBar.tintColor = BKColor.grey.darken4
        
        self.viewControllers = [
            BarkNavigationController(rootViewController: HomeViewController(viewModel: HomeViewModel())),
            BarkNavigationController(rootViewController: MessageListViewController(viewModel: MessageListViewModel())),
            BarkNavigationController(rootViewController: MessageSettingsViewController(viewModel: MessageSettingsViewModel()))
        ]
        
        let tabBarItems = [UITabBarItem(title: "service".localized, image: UIImage(named: "baseline_gite_black_24pt"), tag: 0),
                           UITabBarItem(title: "historyMessage".localized, image: Icon.history, tag: 1),
                           UITabBarItem(title: "settings".localized, image: UIImage(named: "baseline_manage_accounts_black_24pt"), tag: 2)]
        for (index, viewController) in self.viewControllers!.enumerated() {
            viewController.tabBarItem = tabBarItems[index]
        }

        if #available(iOS 26.0, *) {
            setupLiquidGlassTabBar()
        }
    }

    /// Liquid Glass tab bar: it shrinks while the content scrolls down, and a
    /// glass accessory above it shows the latest push (with its group icon).
    /// When the bar is minimized the accessory moves inline next to it.
    @available(iOS 26.0, *)
    private func setupLiquidGlassTabBar() {
        tabBarMinimizeBehavior = .onScrollDown

        let latestMessageView = LatestMessageAccessoryView()
        latestMessageView.addTarget(self, action: #selector(openMessageHistory), for: .touchUpInside)
        bottomAccessory = UITabAccessory(contentView: latestMessageView)
    }

    @objc private func openMessageHistory() {
        if currentSelectedIndex == TabPage.messageHistory.rawValue {
            // Already there: scroll to the newest message
            tabBarItemDidClick.accept(.messageHistory)
        } else {
            currentSelectedIndex = TabPage.messageHistory.rawValue
        }
    }
}
