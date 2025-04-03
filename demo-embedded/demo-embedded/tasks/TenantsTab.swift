//
//  TasksTab.swift
//
//  Created by David Frontegg on 14/11/2022.
//


import SwiftUI

/// A view that displays a list of tenants available to the current user.
/// Allows users to switch between different tenants they have access to.
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

// Preview provider for SwiftUI previews
struct TasksTab_Previews: PreviewProvider {
    static var previews: some View {
        TenantsTab()
    }
}
