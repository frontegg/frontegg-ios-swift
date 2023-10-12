
import SwiftUI
import FronteggSwift

struct TenantsList: View {
    @EnvironmentObject var fronteggAuth: FronteggAuth
    @State var switchingTenant:String? = nil
    
    var body: some View {
        
        ForEach(fronteggAuth.user?.tenants.sorted(by: { t1, t2 in
            return t1.name < t2.name
        }) ?? [], id: \.tenantId.self) { item in
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

struct TaskList_Previews: PreviewProvider {
    
    
    static var previews: some View {
        TenantsList()
    }
}
