//
//  TasksTab.swift
//
//  Created by David Frontegg on 14/11/2022.
//


import SwiftUI

struct TenantsTab: View {
    
    var body: some View {
        NavigationView {
            VStack(alignment: .leading) {
                TenantsList()
                Spacer()
            }.padding(.all, 20)
            
            .navigationTitle("Tenants")
        }
    }
}

struct TasksTab_Previews: PreviewProvider {
    static var previews: some View {
        TenantsTab()
    }
}
