import SwiftUI
import FronteggSwift

/// A view that displays a list of tenants available to the current user.
/// Allows users to switch between different tenants they have access to.
struct TenantsList: View {
    /// The Frontegg authentication state object
    @EnvironmentObject var fronteggAuth: FronteggAuth
    /// Tracks which tenant is currently being switched to
    @State var switchingTenant:String? = nil
    
    var body: some View {
        /// A list of tenants available to the current user
        ForEach(fronteggAuth.user?.tenants.sorted(by: { t1, t2 in
            return t1.name < t2.name
        }) ?? [], id: \.tenantId.self) { item in
            /// A button that switches to the selected tenant
            Button(action: {
                switchingTenant = item.tenantId
                fronteggAuth.switchTenant(tenantId: item.tenantId) { _ in
                    switchingTenant = nil
                }
            }) {
                Text("\(item.name)\(fronteggAuth.user?.activeTenant.tenantId == item.tenantId ? " (active)" : switchingTenant == item.tenantId ? " (swithcing...)" : "")")
                    .font(.title2)
                    .padding(.bottom, 8)
            }.frame(maxWidth: .infinity, alignment: .leading)  // Make the entire row clickable
            .contentShape(Rectangle())
        }
    }
}

// Preview provider for SwiftUI previews
struct TaskList_Previews: PreviewProvider {
    static var previews: some View {
        TenantsList()
    }
}
