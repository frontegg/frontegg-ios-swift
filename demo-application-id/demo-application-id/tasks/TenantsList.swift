import SwiftUI
import FronteggSwift

/// A view that displays a list of tenants available to the current user.
/// Allows users to switch between different tenants they have access to.
struct TenantsList: View {
    /// The Frontegg authentication state object
    @EnvironmentObject var fronteggAuth: FronteggAuth
    
    /// Tracks which tenant is currently being switched to
    @State var switchingTenant: String? = nil
    
    var body: some View {
        // Display tenants sorted alphabetically by name
        ForEach(fronteggAuth.user?.tenants.sorted(by: { t1, t2 in
            return t1.name < t2.name
        }) ?? [], id: \.id.self) { item in
            // Create a button for each tenant
            Button(action: {
                // Set the switching state and initiate tenant switch
                switchingTenant = item.id
                fronteggAuth.switchTenant(tenantId: item.tenantId) { _ in
                    switchingTenant = nil
                }
            }) {
                // Display tenant name with status indicators
                Text("\(item.name)\(fronteggAuth.user?.activeTenant.id == item.id ? " (active)" : switchingTenant == item.id ? " (swithcing...)" : "")")
                    .font(.title2)
                    .padding(.bottom, 8)
            }
            .frame(maxWidth: .infinity, alignment: .leading)  // Make the entire row clickable
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
