import SwiftUI

/// A tab view that displays the list of tenants available to the current user.
/// This view is part of the main tab navigation in the app and provides access to tenant management.
struct TenantsTab: View {
    
    var body: some View {
        NavigationView {
            VStack(alignment: .leading) {
                // Display the list of tenants using the TenantsList component
                TenantsList()
                Spacer()
            }.padding(.all, 20)
            
            .navigationTitle("Tenants")
        }
    }
}

// Preview provider for SwiftUI previews
struct TasksTab_Previews: PreviewProvider {
    static var previews: some View {
        TenantsTab()
    }
}
