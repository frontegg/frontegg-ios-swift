//
//  UIWindow+FronteggPresentation.swift
//
//  Created by David Frontegg on 14/11/2022.
//

import UIKit

extension UIWindow {
    static var key: UIWindow? {
        return UIApplication.shared.windows.filter {$0.isKeyWindow}.first
    }

    static var fronteggPresentationCandidate: UIWindow? {
        let sceneWindows = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .filter { scene in
                scene.activationState == .foregroundActive || scene.activationState == .foregroundInactive
            }
            .flatMap(\.windows)

        return sceneWindows.first(where: \.isKeyWindow)
            ?? sceneWindows.first(where: { !$0.isHidden && $0.alpha > 0 })
            ?? UIApplication.shared.windows.first(where: \.isKeyWindow)
            ?? UIApplication.shared.windows.last
    }
}
