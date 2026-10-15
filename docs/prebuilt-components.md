# Prebuilt SwiftUI components

FronteggSwift ships two drop-in SwiftUI views for B2B apps. Both read the signed-in user from `FronteggAuth.shared`, so the SDK must be initialized (for example with `FronteggWrapper`) and the user authenticated before you show them.

Both views require **iOS 15 or later** (`@available(iOS 15, *)`). They rely on `.task`, `.refreshable`, `.swipeActions`, `.searchable` and `confirmationDialog`, and passkey registration itself needs iOS 15. The rest of the SDK still supports iOS 14.

The views use system `List`/`Form` styling, so they follow light/dark mode, Dynamic Type and your app's accent color. They don't wrap themselves in a navigation container; put them in a `NavigationView` or `NavigationStack` to get a title bar and search field.

## FronteggTenantSwitcher

Lists `user.tenants`, marks the active tenant, and calls `FronteggAuth.switchTenant(tenantId:)` when the user taps another one. The row shows a spinner while the switch is in progress, and an alert appears if the switch fails.

```swift
import FronteggSwift

struct AccountsScreen: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            FronteggTenantSwitcher(showsSearch: true) { result in
                if case .success = result { dismiss() }
            }
        }
    }
}
```

Parameters:

- `strings`: a `FronteggTenantSwitcherStrings` value. Every user-facing string is a `var` you can override, for example with `NSLocalizedString`.
- `showsSearch`: adds a search field that filters tenants by name.
- `onSwitch`: called with `Result<User, FronteggError>` after each switch attempt. Tapping the active tenant does nothing.
- `row`: an optional `@ViewBuilder` that replaces the default row:

```swift
FronteggTenantSwitcher { tenant, state in
    HStack {
        Text(tenant.name)
        Spacer()
        if state.isSwitching { ProgressView() }
        else if state.isActive { Image(systemName: "checkmark") }
    }
}
```

The default row is public as `FronteggTenantRow(tenant:state:)`, so you can reuse it inside your own layout. Each row is a single accessibility element. Its label is the tenant name, and its value is "Current account" or "Switching". The active row also carries the `isSelected` trait.

## FronteggSecurityCenter

An in-app security screen with four sections:

| Section | What it does |
| --- | --- |
| Identity verification (`.stepUp`) | Shows whether the current session is stepped up (`isSteppedUp(maxAge:)`) and starts `stepUp(maxAge:)`. The footer names the active tenant, because step-up applies to the current tenant session. |
| Passkeys (`.passkeys`) | Lists the user's passkeys (WebAuthn devices). **Add a passkey** uses `registerPasskeys()`. To delete one, swipe the row or use the VoiceOver action, then confirm. |
| Multi-factor authentication (`.mfa`) | Shows the `user.mfaEnrolled` status. **Manage** opens the embedded `AdminPortalView` by default, or runs your `onManageMFA` closure. |
| Active sessions (`.sessions`) | Lists the user's sessions and labels the current one as "This device". Swipe another session to sign it out, or use **Sign out all other sessions**. The current session can't be revoked from here; use `logout()` for that. |

```swift
NavigationView {
    FronteggSecurityCenter(
        sections: [.passkeys, .sessions, .stepUp],
        stepUpMaxAge: 300,
        onManageMFA: { showMyMfaScreen = true }
    )
}
```

Parameters:

- `sections`: a `FronteggSecurityCenter.Sections` option set. Defaults to `.all`.
- `stepUpMaxAge`: passed to `stepUp(maxAge:)` and `isSteppedUp(maxAge:)`.
- `strings`: a `FronteggSecurityCenterStrings` value with every user-facing string.
- `onManageMFA`: replaces the default admin-portal sheet.

To reload the data, pull down on the list. A failed list load shows an inline error with **Try again** and doesn't block the other sections. A failed action (revoke, delete or step-up) shows an alert. If the user cancels the passkey or step-up sheet, no error appears.

### Endpoints

The security center calls these Frontegg identity endpoints with the user's access token. They are the same endpoints the Frontegg admin portal uses.

| Action | Method and path |
| --- | --- |
| List sessions | `GET /frontegg/identity/resources/users/sessions/v1/me` |
| Revoke a session | `DELETE /frontegg/identity/resources/users/sessions/v1/me/{id}` |
| Revoke all other sessions | `DELETE /frontegg/identity/resources/users/sessions/v1/me/all` |
| List passkeys | `GET /frontegg/identity/resources/users/webauthn/v1/devices` |
| Delete a passkey | `DELETE /frontegg/identity/resources/users/webauthn/v1/devices/{id}` |

The SDK has no native MFA enrollment or disable flow, so MFA changes go through the admin portal or your own screen.
