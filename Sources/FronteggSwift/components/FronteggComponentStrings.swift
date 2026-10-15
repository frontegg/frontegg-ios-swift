//
//  FronteggComponentStrings.swift
//  FronteggSwift
//

import Foundation

/// User-facing copy for `FronteggTenantSwitcher`. Override any property to localize.
public struct FronteggTenantSwitcherStrings {
    public var title = "Accounts"
    public var searchPrompt = "Search accounts"
    public var emptyState = "No accounts available"
    public var activeAccessibilityValue = "Current account"
    public var switchingAccessibilityValue = "Switching"
    public var switchAccessibilityHint = "Switches to this account"
    public var errorTitle = "Couldn't switch account"
    public var dismiss = "OK"

    public init() {}
}

/// User-facing copy for `FronteggSecurityCenter`. Override any property to localize.
public struct FronteggSecurityCenterStrings {
    public var title = "Security"
    public var errorTitle = "Something went wrong"
    public var dismiss = "OK"
    public var cancel = "Cancel"
    public var retry = "Try again"

    public var passkeysHeader = "Passkeys"
    public var passkeysFooter = "Passkeys let you sign in with Face ID, Touch ID or your device passcode."
    public var passkeysEmpty = "No passkeys yet"
    public var addPasskey = "Add a passkey"
    public var platformPasskey = "Device passkey"
    public var crossPlatformPasskey = "Security key"
    public var otherPasskey = "Passkey"
    public var deletePasskey = "Delete"
    public var deletePasskeyConfirmationTitle = "Delete this passkey?"
    public var deletePasskeyConfirmationMessage = "You won't be able to sign in with it anymore."
    public var addedPrefix = "Added"

    public var mfaHeader = "Multi-factor authentication"
    public var mfaStatus = "Status"
    public var mfaEnabled = "On"
    public var mfaDisabled = "Off"
    public var manageMfa = "Manage multi-factor authentication"

    public var stepUpHeader = "Identity verification"
    public var stepUpStatus = "Status"
    public var steppedUp = "Verified"
    public var notSteppedUp = "Not verified"
    public var stepUpAction = "Verify it's you"
    public var stepUpFooterPrefix = "Applies to your session in"

    public var sessionsHeader = "Active sessions"
    public var sessionsEmpty = "No active sessions"
    public var currentSession = "This device"
    public var impersonatedSession = "Impersonated"
    public var signedInPrefix = "Signed in"
    public var revokeSession = "Sign out"
    public var revokeOtherSessions = "Sign out all other sessions"
    public var revokeOtherSessionsConfirmationTitle = "Sign out of all other sessions?"
    public var revokeOtherSessionsConfirmationMessage = "You'll stay signed in on this device."

    public var platformIPhone = "iPhone"
    public var platformIPad = "iPad"
    public var platformMac = "Mac"
    public var platformAndroid = "Android"
    public var platformWindows = "Windows"
    public var platformLinux = "Linux"
    public var platformUnknown = "Unknown device"

    public init() {}

    func name(for platform: FronteggSession.Platform) -> String {
        switch platform {
        case .iPhone: return platformIPhone
        case .iPad: return platformIPad
        case .mac: return platformMac
        case .android: return platformAndroid
        case .windows: return platformWindows
        case .linux: return platformLinux
        case .unknown: return platformUnknown
        }
    }

    func name(for deviceType: FronteggPasskey.DeviceType) -> String {
        switch deviceType {
        case .platform: return platformPasskey
        case .crossPlatform: return crossPlatformPasskey
        case .other: return otherPasskey
        }
    }
}
