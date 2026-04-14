//
//  ProfileView.swift
//  demo-auto-login
//

import SwiftUI
import FronteggSwift

struct ProfileView: View {
    @EnvironmentObject var fronteggAuth: FronteggAuth

    var body: some View {
        NavigationView {
            List {
                // User info section
                if let user = fronteggAuth.user {
                    Section("Profile") {
                        HStack(spacing: 12) {
                            AsyncImage(url: URL(string: user.profilePictureUrl ?? "")) { image in
                                image.resizable().scaledToFill()
                            } placeholder: {
                                Image(systemName: "person.circle.fill")
                                    .resizable()
                                    .foregroundColor(.gray)
                            }
                            .frame(width: 48, height: 48)
                            .clipShape(Circle())

                            VStack(alignment: .leading, spacing: 4) {
                                Text(user.name ?? "Unknown")
                                    .font(.headline)
                                    .accessibilityIdentifier("ProfileUserName")
                                Text(user.email)
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                    .accessibilityIdentifier("ProfileUserEmail")
                            }
                        }
                    }

                    // Active tenant
                    Section("Active Tenant") {
                        Text(user.activeTenant.name)
                            .accessibilityIdentifier("ProfileActiveTenant")
                    }

                    // Tenant switcher
                    if user.tenants.count > 1 {
                        Section("Switch Tenant") {
                            ForEach(user.tenants, id: \.tenantId) { tenant in
                                Button {
                                    fronteggAuth.switchTenant(tenantId: tenant.tenantId)
                                } label: {
                                    HStack {
                                        Text(tenant.name)
                                        Spacer()
                                        if tenant.tenantId == user.activeTenant.tenantId {
                                            Image(systemName: "checkmark")
                                                .foregroundColor(.blue)
                                        }
                                    }
                                }
                                .accessibilityIdentifier("TenantSwitch_\(tenant.tenantId)")
                            }
                        }
                    }
                }

                // Logout
                Section {
                    Button(role: .destructive) {
                        fronteggAuth.logout()
                    } label: {
                        HStack {
                            Image(systemName: "rectangle.portrait.and.arrow.right")
                            Text("Logout")
                        }
                    }
                    .accessibilityIdentifier("LogoutButton")
                }
            }
            .navigationTitle("Profile")
            .accessibilityIdentifier("ProfileView")
            .overlay(alignment: .topLeading) {
                if AutoLoginTestMode.isEnabled {
                    tokenDiagnostics
                    offlineDiagnostics
                }
            }
        }
    }

    @ViewBuilder
    private var tokenDiagnostics: some View {
        if let accessToken = fronteggAuth.accessToken,
           let payload = decodeJWTPayload(accessToken) {
            let version = payload["token_version"] as? Int ?? 0
            let exp = payload["exp"] as? Int ?? 0
            Text("\(version)")
                .font(.system(size: 1))
                .foregroundColor(.clear)
                .accessibilityIdentifier("AccessTokenVersionValue")
            Text("\(exp)")
                .font(.system(size: 1))
                .foregroundColor(.clear)
                .accessibilityIdentifier("AccessTokenExpValue")
        }
    }

    @ViewBuilder
    private var offlineDiagnostics: some View {
        if fronteggAuth.isOfflineMode {
            Text("OfflineModeBadge")
                .font(.system(size: 1))
                .foregroundColor(.clear)
                .accessibilityIdentifier("OfflineModeBadge")
        }
    }

    private func decodeJWTPayload(_ jwt: String) -> [String: Any]? {
        let parts = jwt.split(separator: ".")
        guard parts.count >= 2 else { return nil }
        var base64 = String(parts[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while base64.count % 4 != 0 { base64.append("=") }
        guard let data = Data(base64Encoded: base64) else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }
}
