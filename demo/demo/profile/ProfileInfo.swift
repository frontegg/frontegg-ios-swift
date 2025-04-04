//
//  ProfileInfo.swift
//
//  Created by David Frontegg on 14/11/2022.
//

import SwiftUI
import FronteggSwift

/// A view that displays the user's profile information.
/// This component shows the user's name, email, and the currently active tenant.
struct ProfileInfo: View {
    /// The Frontegg authentication state object
    @EnvironmentObject var fronteggAuth: FronteggAuth
    
    var body: some View {
        VStack(alignment: .leading) {
            Text(fronteggAuth.user?.name ?? "Name")
                .font(.title)

            HStack {
                Text(fronteggAuth.user?.email ?? "Email")
                    .font(.subheadline)
                Spacer()
                Text("Admin")
                    .font(.subheadline)
            }
            Text(fronteggAuth.user?.activeTenant.name ?? "no tenant")
                .font(.subheadline)
            Spacer()
        }
        .padding()
    }
}

// Preview provider for SwiftUI previews
struct ProfileInfo_Previews: PreviewProvider {
    static var previews: some View {
        ProfileInfo()
    }
}
