//
//  FronteggTenantSwitcherViewModel.swift
//  FronteggSwift
//

import Foundation
import Combine

@MainActor
final class FronteggTenantSwitcherViewModel: ObservableObject {

    @Published private(set) var user: User?
    @Published private(set) var switchingTenantId: String?
    @Published var errorMessage: String?
    @Published var searchText = ""

    private let switcher: FronteggTenantSwitching

    init(switcher: FronteggTenantSwitching, userPublisher: AnyPublisher<User?, Never>) {
        self.switcher = switcher
        userPublisher.assign(to: &$user)
    }

    var tenants: [Tenant] {
        user?.tenants ?? []
    }

    var activeTenantId: String? {
        user?.activeTenant.tenantId
    }

    var filteredTenants: [Tenant] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return tenants }
        return tenants.filter { $0.name.localizedCaseInsensitiveContains(query) }
    }

    var isSwitching: Bool {
        switchingTenantId != nil
    }

    func isActive(_ tenant: Tenant) -> Bool {
        tenant.tenantId == activeTenantId
    }

    @discardableResult
    func select(_ tenant: Tenant) async -> Result<User, FronteggError>? {
        guard !isActive(tenant), switchingTenantId == nil else { return nil }
        switchingTenantId = tenant.tenantId
        defer { switchingTenantId = nil }
        do {
            let updated = try await switcher.switchTenant(tenantId: tenant.tenantId)
            user = updated
            errorMessage = nil
            return .success(updated)
        } catch {
            errorMessage = error.localizedDescription
            return .failure(error as? FronteggError ?? .authError(.other(error)))
        }
    }
}
