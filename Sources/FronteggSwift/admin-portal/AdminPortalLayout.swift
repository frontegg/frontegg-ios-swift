//
//  AdminPortalLayout.swift
//  FronteggSwift
//

import Foundation

/// How the embedded Admin Portal lays itself out.
public enum AdminPortalLayout: Sendable {
    /// Renders the desktop layout at 1024px, scaled to fit, with the sidebar always visible.
    case desktop
    /// Uses the device's real width, so on phones the sidebar collapses into a menu button.
    case responsive

    public static let `default`: AdminPortalLayout = .desktop
}
