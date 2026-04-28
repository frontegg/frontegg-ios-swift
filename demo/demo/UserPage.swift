import SwiftUI
import FronteggSwift

struct UserPage: View {
    @EnvironmentObject private var fronteggAuth: FronteggAuth
    @State private var message: Message?
    @State private var messageTimer: Timer?
    @State private var loadSuccess: Bool?
    @State private var entitlementFeature: Entitlement?
    @State private var entitlementPermission: Entitlement?
    @State private var entitlementUnifiedFeature: Entitlement?
    @State private var entitlementUnifiedPermission: Entitlement?
    @State private var entitlementsLoading = false
    @State private var showAdminPortal = false

    struct Message: Identifiable {
        let id = UUID()
        let text: String
        let isSuccess: Bool
    }
    
    var body: some View {
        if fronteggAuth.isLoading {
            LoaderView()
        } else {
            ZStack() {
                Color.backgroundColor.ignoresSafeArea()
                mainContent
            }
            .overlay(FronteggAppBar()
                .ignoresSafeArea(edges: .top),alignment: .top)
            .overlay(Footer()
                .ignoresSafeArea(edges: .bottom),alignment: .bottom)
            .sheet(isPresented: $showAdminPortal) {
                AdminPortalView()
            }
        }
    }
    
    private var mainContent: some View {
        ScrollView {
            Spacer().frame(height: 130)
            if let message = message {
                MessageView(message: message)
            }
            
            Spacer().frame(height: 16)
            userContent
            Spacer(minLength: 220)
        }
    }
    
    private var userContent: some View {
        CardView{
            VStack(spacing: 0) {
                if let user = fronteggAuth.user {
                    UserHeaderView(user: user)
                    Spacer().frame(height: 16)
                    TenantInfo(activeTenant: user.activeTenant, tenants: user.tenants)
                    Spacer().frame(height: 24)
                    UserInfoView(user: user)
                    Spacer().frame(height: 16)
                    
                    VStack(spacing: 12) {
                        sensitiveActionButton
                        requestAuthorizeButton
                        adminPortalButton
                    }
                    Spacer().frame(height: 16)
                    entitlementsSection
                    Spacer().frame(height: 24)
                }
            }
            .padding(.horizontal, 24)
        }.padding(.horizontal, 24)
    }
    
    private var sensitiveActionButton: some View {
        Button("Sensitive action") {
            handleSensitiveAction()
        }
        .buttonStyle(PrimaryButtonStyle())
        .padding(.horizontal, 8)
    }

    private var requestAuthorizeButton: some View {
        Button("Request Authorize") {
            handleRequestAuthorize()
        }
        .buttonStyle(PrimaryButtonStyle())
        .padding(.horizontal, 8)
    }

    private var adminPortalButton: some View {
        Button("Open Admin Portal") {
            showAdminPortal = true
        }
        .buttonStyle(PrimaryButtonStyle())
        .padding(.horizontal, 8)
    }

    private var entitlementsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button("Load entitlements") {
                loadEntitlements()
            }
            .buttonStyle(PrimaryButtonStyle())
            .padding(.horizontal, 8)
            .disabled(entitlementsLoading)
            if entitlementsLoading {
                Text("Loading…")
                    .font(.caption)
                    .foregroundColor(.gray)
            }
            if let success = loadSuccess {
                Text(success ? "Load succeeded" : "Load failed")
                    .font(.caption)
                    .foregroundColor(success ? .greenForeground : .redForeground)
            }
            if let state = entitlementStateSummary {
                Text(state)
                    .font(.caption2)
                    .foregroundColor(.gray)
            }
            if let e = entitlementFeature {
                entitlementRow(label: "getFeatureEntitlements(\"sso\")", entitlement: e)
            }
            if let e = entitlementUnifiedFeature {
                entitlementRow(label: "getEntitlements(.featureKey(\"proteins.*\"))", entitlement: e)
            }
            if let e = entitlementPermission {
                entitlementRow(label: "getPermissionEntitlements(\"dora.protein.*\")", entitlement: e)
            }
            if let e = entitlementUnifiedPermission {
                entitlementRow(label: "getEntitlements(.permissionKey(\"fe.secure.*\"))", entitlement: e)
            }
        }
    }

    private var entitlementStateSummary: String? {
        let state = fronteggAuth.entitlements.state
        guard !state.featureKeys.isEmpty || !state.permissionKeys.isEmpty else { return nil }
        return "Cached: \(state.featureKeys.count) feature(s), \(state.permissionKeys.count) permission(s)"
    }

    private func entitlementRow(label: String, entitlement: Entitlement) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: entitlement.isEntitled ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundColor(entitlement.isEntitled ? .greenForeground : .redForeground)
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.caption)
                    .foregroundColor(.gray800)
                Text(entitlement.isEntitled ? "Entitled" : "Not entitled\(entitlement.justification.map { " (\($0))" } ?? "")")
                    .font(.caption2)
                    .foregroundColor(entitlement.isEntitled ? .greenForeground : .redForeground)
            }
            Spacer()
        }
        .padding(8)
        .background(Color.white)
        .cornerRadius(8)
    }

    private func loadEntitlements() {
        entitlementsLoading = true
        loadSuccess = nil
        entitlementFeature = nil
        entitlementPermission = nil
        entitlementUnifiedFeature = nil
        entitlementUnifiedPermission = nil
        fronteggAuth.loadEntitlements { success in
            let feature = fronteggAuth.getFeatureEntitlements(featureKey: "sso")
            let unifiedFeature = fronteggAuth.getEntitlements(options: .featureKey("proteins.*"))
            let permission = fronteggAuth.getPermissionEntitlements(permissionKey: "dora.protein.*")
            let unifiedPermission = fronteggAuth.getEntitlements(options: .permissionKey("fe.secure.*"))
            DispatchQueue.main.async {
                loadSuccess = success
                entitlementFeature = feature
                entitlementPermission = permission
                entitlementUnifiedFeature = unifiedFeature
                entitlementUnifiedPermission = unifiedPermission
                entitlementsLoading = false
            }
        }
    }

   private func handleRequestAuthorize() {
    Task {
        do {
            guard let refreshToken = fronteggAuth.refreshToken else {
                showMessage("No refresh token available", isSuccess: false)
                return
            }
            
            showMessage("Calling silentAuthorize...", isSuccess: true)
            
            let (data, _) = try await fronteggAuth.api.silentAuthorize(refreshToken: refreshToken)        
            
            showMessage("Silent authorize successful! Access token received.", isSuccess: true)
        } catch {
            showMessage("Request failed: \(error.localizedDescription)", isSuccess: false)
        }
    }
}
    
    private var footerContent: some View {
        VStack {
            Spacer()
            Footer(showSignUpBanner: fronteggAuth.baseUrl == "https://app-x4gr8g28fxr5.frontegg.com")
        }
    }
    
    private func handleSensitiveAction() {
        let isSteppedUp = fronteggAuth.isSteppedUp(maxAge: 60)
        if isSteppedUp {
            showMessage("You are already stepped up", isSuccess: true)
        } else {
            Task {
                await fronteggAuth.stepUp(maxAge: 60) { res in
                    switch(res) {
                    case .success(_) :
                        showMessage("Action completed successfully", isSuccess: true)
                    case .failure(_):
                        showMessage("Action completed with failure", isSuccess: false)
                    }
                    
                }
            }
        }
    }
    
    private func showMessage(_ text: String, isSuccess: Bool) {
        message = Message(text: text, isSuccess: isSuccess)
        messageTimer?.invalidate()
        messageTimer = Timer.scheduledTimer(withTimeInterval: 10, repeats: false) { _ in
            message = nil
        }
    }
}

struct MessageView: View {
    let message: UserPage.Message
    
    var body: some View {
        let bacground: Color = message.isSuccess ? .greenBackground : .redBackground
        HStack {
            Image(systemName: message.isSuccess ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                .resizable()
                .frame(width: 16, height: 16)
                .foregroundColor(message.isSuccess ? .greenForeground : .redForeground)
            
            Text(message.text)
                .font(.bodyMedium)
                .fontWeight(.semibold)
                .foregroundColor(message.isSuccess ? .greenForeground : .redForeground)
            
            Spacer()
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(bacground)
        .cornerRadius(16)
        .padding(.horizontal, 24)
    }
}

struct UserHeaderView: View {
    let user: User
    
    var body: some View {
        Text("Hello, \(user.name.components(separatedBy: " ").first ?? "")!")
            .font(.headlineSmall)
            .foregroundColor(Color(hex: "202020"))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 24)
    }
}

struct UserInfoView: View {
    let user: User
    
    var body: some View {
        VStack(spacing: 16) {
            HStack {
                AsyncImage(url: URL(string: user.profilePictureUrl)) { image in
                    image.resizable()
                } placeholder: {
                    Color.gray
                }
                .frame(width: 24, height: 24)
                .clipShape(Circle())
                
                Text(user.name)
                    .font(.bodyMedium)
                    .foregroundColor(.gray800)
                Spacer()
            }
            .padding(.top, 4)
            .padding(.leading, 4)
            .padding(.trailing, 4)
            
            Divider()
            
            HStack(alignment: .top, spacing: 0) {
                
                VStack(alignment: .leading, spacing: 16) {
                    HStack{
                        InfoLabel("Name")
                        Spacer()
                    }
                    
                    InfoLabel("Email")
                    InfoLabel("Roles")
                }
                .frame(width: 80)
                
                
                VStack(alignment: .leading, spacing: 16) {
                    HStack{ Text(user.name)
                            .font(.bodyMedium)
                            .foregroundColor(Color(hex: "7A7C81"))
                            .lineLimit(1)
                        Spacer()
                    }
                    Text(user.email)
                        .font(.bodyMedium)
                        .foregroundColor(Color(hex: "7A7C81"))
                        .lineLimit(1)
                    Text(user.roles.isEmpty ? "No roles assigned" : user.roles.map { $0.name }.joined(separator: ", "))
                        .font(.bodyMedium)
                        .foregroundColor(Color(hex: "7A7C81"))
                        .lineLimit(1)
                }
            }
            .padding(8)
            .padding(.bottom, 16)
        }
        .padding(.top, 16)
        .padding(.trailing, 16)
        .padding(.leading, 16)
        .background(Color.white)
        .cornerRadius(8)
        .shadow(radius: 2)
    }
}

struct InfoLabel: View {
    let text: String
    
    init(_ text: String) {
        self.text = text
    }
    
    var body: some View {
        Text(text)
            .font(.bodyMedium)
            .foregroundColor(.textColor)
            .fontWeight(.semibold)
            .foregroundColor(.gray800)
    }
}

struct TenantInfo: View {
    let activeTenant: Tenant
    let tenants: [Tenant]
    @EnvironmentObject private var fronteggAuth: FronteggAuth
    
    var body: some View {
        VStack(spacing: 16) {
            TenantDropdown(selectedTenant: activeTenant, tenants: tenants)
            Divider()
                .padding(.leading, 16)
                .padding(.trailing, 16)
            column
            
        }
        .background(Color.white)
        .cornerRadius(8)
        .shadow(radius: 2)
    }
    
    var column: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 16) {
                HStack{
                    InfoLabel("ID")
                    Spacer()
                }.frame(height: 20)
                InfoLabel("Website")
                InfoLabel("Creator")
            }
            .frame(width: 80)
            
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text(activeTenant.id)
                        .font(.bodyMedium)
                        .foregroundColor(Color(hex: "7A7C81"))
                        .lineLimit(1)
                    
                    Button {
                        UIPasteboard.general.string = activeTenant.id
                        
                    } label: {
                        Image("copy-icon")
                            .resizable()
                            .frame(width: 16, height: 24)
                            .foregroundColor(Color(hex: "7A7C81"))
                    }
                    
                }.frame(height: 20)
                
                Text(activeTenant.website ?? "No website")
                    .font(.bodyMedium)
                    .foregroundColor(Color(hex: "7A7C81"))
                    .lineLimit(1)
                
                Text(activeTenant.creatorName ?? "Unknown")
                    .font(.bodyMedium)
                    .foregroundColor(Color(hex: "7A7C81"))
                    .lineLimit(1)
                
                    
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 16)
        .padding(.bottom, 8)
        .padding(.horizontal, 8)
    }
}

struct TenantDropdown: View {
    var selectedTenant: Tenant
    let tenants: [Tenant]
    @EnvironmentObject private var fronteggAuth: FronteggAuth
    
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            button
            
            if isExpanded {
                expanded
            }
        }
        .animation(.easeInOut, value: isExpanded)
    }
    
    let circleColor: Color = .gray200
    let circleLetterColor: Color = .gray700
    
    var button : some View {
        Button(action: { isExpanded.toggle() }) {
            HStack {
                Circle()
                    .fill(circleColor)
                    .frame(width: 24, height: 24)
                    .overlay(Text(selectedTenant.name.prefix(1)).font(.bodyMedium).foregroundColor(circleLetterColor))
                Text(selectedTenant.name)
                    .font(.bodyMedium)
                    .foregroundColor(.gray800)
                Spacer()
                Image("menu-icon")
                    .resizable()
                    .frame(width: 16, height: 24)
                    .foregroundColor(.gray)
            }
            .padding(.top, 20)
            .padding(.leading, 20)
            .padding(.trailing, 20)
        }
    }
    
    var expanded: some View {
        VStack(spacing: 0) {
            ForEach(tenants, id: \.id) { tenant in
                Button(action: {
                    if tenant.tenantId != selectedTenant.tenantId {
                        fronteggAuth.switchTenant(tenantId: tenant.tenantId)
                    }
                    isExpanded = false
                }) {
                    HStack {
                        Circle()
                            .fill(circleColor)
                            .frame(width: 24, height: 24)
                            .overlay(Text(tenant.name.prefix(1)).font(.bodyMedium).foregroundColor(circleLetterColor))
                        Text(tenant.name)
                            .font(.bodyMedium)
                            .fontWeight(tenant.id == selectedTenant.id ? .bold : .regular)
                            .foregroundColor(tenant.id == selectedTenant.id ? .primaryColor : .gray800)
                        Spacer()
                        if tenant.id == selectedTenant.id {
                            Image( "checkmark-icon")
                                .resizable()
                                .frame(width: 11.73, height: 8.94)
                                .foregroundColor(.primaryColor)
                        }
                    }
                    .padding(.top, tenants.first?.tenantId != tenant.tenantId ? 0 : 20)
                    .padding(.bottom ,20)
                    .padding(.leading, 20)
                    .padding(.trailing, 20)
                }
                .background(Color.white)
            }
        }
        .background(Color.white)
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
    }
}

#Preview {
    UserPage()
}

