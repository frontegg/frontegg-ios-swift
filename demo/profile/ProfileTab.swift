//
//  ProfileTab.swift
//  poc
//
//  Created by David Frontegg on 14/11/2022.
//

import SwiftUI

struct ProfileTab: View {
    
    @EnvironmentObject var fronteggAuth: FronteggAuth

    
    var body: some View {
        NavigationView {
            VStack{
                ProfilePicture()
                    .padding(.top, 60)
                    .padding(.bottom, 40)
                
                ProfileInfo()
                
                Spacer()
                Button("Logout") {
                    fronteggAuth.logout()
                }
                .foregroundColor(.red)
                .font(.title2)
                .padding(.bottom, 40)
            }
            
            .navigationTitle("Profile")
        }
    }
}

struct ProfileTab_Previews: PreviewProvider {
    static var previews: some View {
        ProfileTab()
    }
}
