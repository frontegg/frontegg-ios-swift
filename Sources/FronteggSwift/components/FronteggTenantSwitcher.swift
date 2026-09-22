//
//  FronteggTenantSwitcher.swift
//  FronteggSwift
//

import SwiftUI
import Combine

/// State passed to a custom `FronteggTenantSwitcher` row.
public struct FronteggTenantRowState: Equatable {
    public let isActive: Bool
    public let isSwitching: Bool

    public init(isActive: Bool, isSwitching: Bool) {
        self.isActive = isActive
        self.isSwitching = isSwitching
    }
}

/// Prebuilt list of the signed-in user's tenants that switches the active tenant on tap.
///
/// ```swift
/// NavigationView {
///     FronteggTenantSwitcher { result in
///         if case .success(let user) = result { print(user.activeTenant.name) }
///     }
/// }
/// ```
@available(iOS 15.0, *)
public struct FronteggTenantSwitcher<Row: View>: View {
    @StateObject private var viewModel: FronteggTenantSwitcherViewModel
    private let strings: FronteggTenantSwitcherStrings
    private let showsSearch: Bool
    private let onSwitch: ((Result<User, FronteggError>) -> Void)?
    private let row: (Tenant, FronteggTenantRowState) -> Row

    /// Creates a tenant switcher with a custom row.
    /// - Parameters:
    ///   - strings: Copy shown by the component.
    ///   - showsSearch: Adds a search field (in a navigation container) filtering tenants by name.
    ///   - onSwitch: Called after a switch attempt finishes.
    ///   - row: Builds the content of each row.
    @MainActor
    public init(
        strings: FronteggTenantSwitcherStrings = .init(),
        showsSearch: Bool = false,
        onSwitch: ((Result<User, FronteggError>) -> Void)? = nil,
        @ViewBuilder row: @escaping (Tenant, FronteggTenantRowState) -> Row
    ) {
        self.init(
            viewModel: FronteggTenantSwitcherViewModel(
                switcher: FronteggAuthTenantSwitcher(auth: FronteggAuth.shared),
                userPublisher: FronteggAuth.shared.mainThreadUserPublisher
            ),
            strings: strings,
            showsSearch: showsSearch,
            onSwitch: onSwitch,
            row: row
        )
    }

    @MainActor
    init(
        viewModel: @autoclosure @escaping () -> FronteggTenantSwitcherViewModel,
        strings: FronteggTenantSwitcherStrings,
        showsSearch: Bool,
        onSwitch: ((Result<User, FronteggError>) -> Void)?,
        row: @escaping (Tenant, FronteggTenantRowState) -> Row
    ) {
        self._viewModel = StateObject(wrappedValue: viewModel())
        self.strings = strings
        self.showsSearch = showsSearch
        self.onSwitch = onSwitch
        self.row = row
    }

    public var body: some View {
        list
            .navigationTitle(strings.title)
            .modifier(SearchableIfNeeded(enabled: showsSearch, text: $viewModel.searchText, prompt: strings.searchPrompt))
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
    }

    private var list: some View {
        List {
            ForEach(viewModel.filteredTenants, id: \.tenantId) { tenant in
                let state = FronteggTenantRowState(
                    isActive: viewModel.isActive(tenant),
                    isSwitching: viewModel.switchingTenantId == tenant.tenantId
                )
                Button {
                    Task {
                        if let result = await viewModel.select(tenant) {
                            onSwitch?(result)
                        }
                    }
                } label: {
                    row(tenant, state)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(viewModel.isSwitching && !state.isSwitching)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text(tenant.name))
                .accessibilityValue(Text(accessibilityValue(for: state)))
                .accessibilityHint(state.isActive ? Text("") : Text(strings.switchAccessibilityHint))
                .accessibilityAddTraits(state.isActive ? [.isButton, .isSelected] : .isButton)
            }
        }
        .overlay {
            if viewModel.filteredTenants.isEmpty {
                Text(strings.emptyState)
                    .font(.body)
                    .foregroundColor(.secondary)
            }
        }
    }

    private func accessibilityValue(for state: FronteggTenantRowState) -> String {
        if state.isSwitching { return strings.switchingAccessibilityValue }
        if state.isActive { return strings.activeAccessibilityValue }
        return ""
    }
}

@available(iOS 15.0, *)
extension FronteggTenantSwitcher where Row == FronteggTenantRow {
    /// Creates a tenant switcher with the default row.
    @MainActor
    public init(
        strings: FronteggTenantSwitcherStrings = .init(),
        showsSearch: Bool = false,
        onSwitch: ((Result<User, FronteggError>) -> Void)? = nil
    ) {
        self.init(strings: strings, showsSearch: showsSearch, onSwitch: onSwitch) { tenant, state in
            FronteggTenantRow(tenant: tenant, state: state)
        }
    }
}

/// Default row used by `FronteggTenantSwitcher`: initials, name, website and an active checkmark.
@available(iOS 15.0, *)
public struct FronteggTenantRow: View {
    public let tenant: Tenant
    public let state: FronteggTenantRowState

    public init(tenant: Tenant, state: FronteggTenantRowState) {
        self.tenant = tenant
        self.state = state
    }

    public var body: some View {
        HStack(spacing: 12) {
            Text(initials)
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.white)
                .frame(width: 36, height: 36)
                .background(Circle().fill(Color.accentColor))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(tenant.name)
                    .font(.body)
                    .foregroundColor(.primary)
                if let website = tenant.website, !website.isEmpty {
                    Text(website)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            if state.isSwitching {
                ProgressView()
            } else if state.isActive {
                Image(systemName: "checkmark")
                    .font(.body.weight(.semibold))
                    .foregroundColor(.accentColor)
            }
        }
        .padding(.vertical, 4)
    }

    private var initials: String {
        let words = tenant.name.split(separator: " ").prefix(2)
        let letters = words.compactMap { $0.first }.map { String($0) }.joined()
        return letters.isEmpty ? "?" : letters.uppercased()
    }
}

@available(iOS 15.0, *)
struct SearchableIfNeeded: ViewModifier {
    let enabled: Bool
    let text: Binding<String>
    let prompt: String

    func body(content: Content) -> some View {
        if enabled {
            content.searchable(text: text, prompt: Text(prompt))
        } else {
            content
        }
    }
}
