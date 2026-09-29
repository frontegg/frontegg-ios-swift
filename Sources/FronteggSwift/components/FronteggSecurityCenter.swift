//
//  FronteggSecurityCenter.swift
//  FronteggSwift
//

import SwiftUI

/// Prebuilt in-app security center: passkeys, multi-factor authentication status,
/// identity verification (step-up) for the active tenant and active sessions.
///
/// ```swift
/// NavigationView {
///     FronteggSecurityCenter(stepUpMaxAge: 300)
/// }
/// ```
@available(iOS 15.0, *)
public struct FronteggSecurityCenter: View {

    /// Sections rendered by the security center.
    public struct Sections: OptionSet {
        public let rawValue: Int

        public init(rawValue: Int) {
            self.rawValue = rawValue
        }

        public static let passkeys = Sections(rawValue: 1 << 0)
        public static let mfa = Sections(rawValue: 1 << 1)
        public static let stepUp = Sections(rawValue: 1 << 2)
        public static let sessions = Sections(rawValue: 1 << 3)
        public static let all: Sections = [.passkeys, .mfa, .stepUp, .sessions]
    }

    @StateObject private var viewModel: FronteggSecurityCenterViewModel
    @State private var passkeyPendingDeletion: FronteggPasskey?
    @State private var confirmingRevokeOthers = false
    @State private var showingAdminPortal = false

    private let sections: Sections
    private let strings: FronteggSecurityCenterStrings
    private let onManageMFA: (() -> Void)?

    /// Creates the security center.
    /// - Parameters:
    ///   - sections: Sections to show. Defaults to all.
    ///   - stepUpMaxAge: Max age (seconds) passed to `FronteggAuth.stepUp` / `isSteppedUp`.
    ///   - strings: Copy shown by the component.
    ///   - onManageMFA: Called by "Manage multi-factor authentication". When nil, the
    ///     embedded `AdminPortalView` is presented, where MFA devices are managed.
    @MainActor
    public init(
        sections: Sections = .all,
        stepUpMaxAge: TimeInterval? = nil,
        strings: FronteggSecurityCenterStrings = .init(),
        onManageMFA: (() -> Void)? = nil
    ) {
        self.init(
            viewModel: FronteggSecurityCenterViewModel(
                service: FronteggAuthSecurityCenterService(auth: FronteggAuth.shared),
                userPublisher: FronteggAuth.shared.mainThreadUserPublisher,
                stepUpMaxAge: stepUpMaxAge
            ),
            sections: sections,
            strings: strings,
            onManageMFA: onManageMFA
        )
    }

    @MainActor
    init(
        viewModel: @autoclosure @escaping () -> FronteggSecurityCenterViewModel,
        sections: Sections,
        strings: FronteggSecurityCenterStrings,
        onManageMFA: (() -> Void)?
    ) {
        self._viewModel = StateObject(wrappedValue: viewModel())
        self.sections = sections
        self.strings = strings
        self.onManageMFA = onManageMFA
    }

    public var body: some View {
        Form {
            if sections.contains(.stepUp) {
                stepUpSection
            }
            if sections.contains(.passkeys) {
                passkeysSection
            }
            if sections.contains(.mfa) {
                mfaSection
            }
            if sections.contains(.sessions) {
                sessionsSection
            }
        }
        .navigationTitle(strings.title)
        .task { await reload() }
        .refreshable { await reload() }
        .alert(
            strings.errorTitle,
            isPresented: Binding(
                get: { viewModel.errorMessage != nil },
                set: { if !$0 { viewModel.errorMessage = nil } }
            ),
            presenting: viewModel.errorMessage
        ) { _ in
            Button(strings.dismiss, role: .cancel) {}
        } message: { message in
            Text(message)
        }
        .confirmationDialog(
            strings.deletePasskeyConfirmationTitle,
            isPresented: Binding(
                get: { passkeyPendingDeletion != nil },
                set: { if !$0 { passkeyPendingDeletion = nil } }
            ),
            titleVisibility: .visible,
            presenting: passkeyPendingDeletion
        ) { passkey in
            Button(strings.deletePasskey, role: .destructive) {
                Task { await viewModel.delete(passkey) }
            }
            Button(strings.cancel, role: .cancel) {}
        } message: { _ in
            Text(strings.deletePasskeyConfirmationMessage)
        }
        .confirmationDialog(
            strings.revokeOtherSessionsConfirmationTitle,
            isPresented: $confirmingRevokeOthers,
            titleVisibility: .visible
        ) {
            Button(strings.revokeOtherSessions, role: .destructive) {
                Task { await viewModel.revokeOtherSessions() }
            }
            Button(strings.cancel, role: .cancel) {}
        } message: {
            Text(strings.revokeOtherSessionsConfirmationMessage)
        }
        .sheet(isPresented: $showingAdminPortal) {
            AdminPortalView()
        }
    }

    private func reload() async {
        if sections.contains(.passkeys) && sections.contains(.sessions) {
            await viewModel.load()
        } else if sections.contains(.passkeys) {
            await viewModel.loadPasskeys()
        } else if sections.contains(.sessions) {
            await viewModel.loadSessions()
        }
    }

    // MARK: Step-up

    private var stepUpSection: some View {
        Section {
            statusRow(
                title: strings.stepUpStatus,
                value: viewModel.isSteppedUp ? strings.steppedUp : strings.notSteppedUp,
                systemImage: viewModel.isSteppedUp ? "checkmark.shield.fill" : "shield",
                tint: viewModel.isSteppedUp ? .green : .secondary
            )
            Button {
                Task { await viewModel.stepUp() }
            } label: {
                actionLabel(strings.stepUpAction, isBusy: viewModel.isSteppingUp)
            }
            .disabled(viewModel.isSteppingUp)
        } header: {
            Text(strings.stepUpHeader)
        } footer: {
            if let tenantName = viewModel.activeTenantName {
                Text("\(strings.stepUpFooterPrefix) \(tenantName).")
            }
        }
    }

    // MARK: Passkeys

    private var passkeysSection: some View {
        Section {
            if let error = viewModel.passkeysError {
                errorRow(error) { await viewModel.loadPasskeys() }
            } else if viewModel.passkeys.isEmpty {
                placeholderRow(viewModel.isLoadingPasskeys ? nil : strings.passkeysEmpty)
            } else {
                ForEach(viewModel.passkeys) { passkey in
                    passkeyRow(passkey)
                }
            }
            Button {
                Task { await viewModel.addPasskey() }
            } label: {
                actionLabel(strings.addPasskey, systemImage: "plus.circle.fill", isBusy: viewModel.isAddingPasskey)
            }
            .disabled(viewModel.isAddingPasskey)
        } header: {
            Text(strings.passkeysHeader)
        } footer: {
            Text(strings.passkeysFooter)
        }
    }

    private func passkeyRow(_ passkey: FronteggPasskey) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "key.fill")
                .foregroundColor(.accentColor)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(strings.name(for: passkey.deviceType))
                if let createdAt = passkey.createdAt {
                    Text("\(strings.addedPrefix) \(createdAt.formatted(date: .abbreviated, time: .omitted))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            Spacer(minLength: 8)
            if viewModel.pendingIds.contains(passkey.id) {
                ProgressView()
            }
        }
        .accessibilityElement(children: .combine)
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(strings.deletePasskey, role: .destructive) {
                passkeyPendingDeletion = passkey
            }
        }
        .accessibilityAction(named: Text(strings.deletePasskey)) {
            passkeyPendingDeletion = passkey
        }
    }

    // MARK: MFA

    private var mfaSection: some View {
        Section {
            statusRow(
                title: strings.mfaStatus,
                value: viewModel.mfaEnrolled ? strings.mfaEnabled : strings.mfaDisabled,
                systemImage: viewModel.mfaEnrolled ? "lock.shield.fill" : "lock.open",
                tint: viewModel.mfaEnrolled ? .green : .secondary
            )
            Button {
                if let onManageMFA {
                    onManageMFA()
                } else {
                    showingAdminPortal = true
                }
            } label: {
                actionLabel(strings.manageMfa, isBusy: false)
            }
        } header: {
            Text(strings.mfaHeader)
        }
    }

    // MARK: Sessions

    private var sessionsSection: some View {
        Section {
            if let error = viewModel.sessionsError {
                errorRow(error) { await viewModel.loadSessions() }
            } else if viewModel.sessions.isEmpty {
                placeholderRow(viewModel.isLoadingSessions ? nil : strings.sessionsEmpty)
            } else {
                ForEach(viewModel.sessions) { session in
                    sessionRow(session)
                }
            }
            if !viewModel.otherSessions.isEmpty {
                Button(role: .destructive) {
                    confirmingRevokeOthers = true
                } label: {
                    actionLabel(strings.revokeOtherSessions, isBusy: viewModel.isRevokingOtherSessions)
                }
                .disabled(viewModel.isRevokingOtherSessions)
            }
        } header: {
            Text(strings.sessionsHeader)
        }
    }

    @ViewBuilder
    private func sessionRow(_ session: FronteggSession) -> some View {
        let row = HStack(spacing: 12) {
            Image(systemName: Self.symbol(for: session.platform))
                .frame(width: 24)
                .foregroundColor(.accentColor)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(strings.name(for: session.platform))
                    if session.isCurrent {
                        badge(strings.currentSession, color: .green)
                    }
                    if session.isImpersonated {
                        badge(strings.impersonatedSession, color: .orange)
                    }
                }
                if let detail = sessionDetail(session) {
                    Text(detail)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            Spacer(minLength: 8)
            if viewModel.pendingIds.contains(session.id) {
                ProgressView()
            }
        }
        .accessibilityElement(children: .combine)

        if session.isCurrent {
            row
        } else {
            row
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button(strings.revokeSession, role: .destructive) {
                        Task { await viewModel.revoke(session) }
                    }
                }
                .accessibilityAction(named: Text(strings.revokeSession)) {
                    Task { await viewModel.revoke(session) }
                }
        }
    }

    private func sessionDetail(_ session: FronteggSession) -> String? {
        var parts: [String] = []
        if let ip = session.ipAddress, !ip.isEmpty {
            parts.append(ip)
        }
        if let createdAt = session.createdAt {
            parts.append("\(strings.signedInPrefix) \(createdAt.formatted(.relative(presentation: .named)))")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    static func symbol(for platform: FronteggSession.Platform) -> String {
        switch platform {
        case .iPhone, .android: return "iphone"
        case .iPad: return "ipad"
        case .mac: return "laptopcomputer"
        case .windows, .linux: return "desktopcomputer"
        case .unknown: return "globe"
        }
    }

    // MARK: Shared rows

    private func statusRow(title: String, value: String, systemImage: String, tint: Color) -> some View {
        HStack {
            Label(title, systemImage: systemImage)
            Spacer()
            Text(value)
                .foregroundColor(tint)
        }
        .accessibilityElement(children: .combine)
    }

    private func actionLabel(_ title: String, systemImage: String? = nil, isBusy: Bool) -> some View {
        HStack {
            if let systemImage {
                Label(title, systemImage: systemImage)
            } else {
                Text(title)
            }
            if isBusy {
                Spacer()
                ProgressView()
            }
        }
    }

    private func placeholderRow(_ text: String?) -> some View {
        HStack {
            if let text {
                Text(text)
                    .foregroundColor(.secondary)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private func errorRow(_ message: String, retry: @escaping () async -> Void) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .foregroundColor(.red)
            Button(strings.retry) {
                Task { await retry() }
            }
        }
    }

    private func badge(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .foregroundColor(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(color.opacity(0.15)))
    }
}
