//
//  ProfilePicture.swift
//  poc
//
//  Created by David Frontegg on 14/11/2022.
//

import SwiftUI
import FronteggSwift

struct ProfilePicture: View {
    @EnvironmentObject var fronteggAuth: FronteggAuth
    
    
    var body: some View {
        AsyncImage(
            url: URL(string: self.fronteggAuth.user?.profilePictureUrl ?? ""),
            content: { image in
                image
                    .resizable()
                    .frame(width: 160, height: 160)
                    .clipShape(Circle())
                    .shadow(radius: 2)
            },
            placeholder: {
                Image("ProfileImg")
                    .resizable()
                    .frame(width: 160, height: 160)
                    .clipShape(Circle())
                    .shadow(radius: 2)
            }
            )
    }
}

struct ProfilePicture_Previews: PreviewProvider {
    static var previews: some View {
        ProfilePicture()
    }
}
