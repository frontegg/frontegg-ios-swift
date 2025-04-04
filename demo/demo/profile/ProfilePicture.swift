//
//  ProfilePicture.swift
//
//  Created by David Frontegg on 14/11/2022.
//

import SwiftUI
import FronteggSwift

/// A view that displays the user's profile picture.    
/// This component shows the user's profile picture using an asynchronous image.
struct ProfilePicture: View {
    /// The Frontegg authentication state object
    @EnvironmentObject var fronteggAuth: FronteggAuth
    
    
    var body: some View {
        if #available(iOS 15.0, *) {
            AsyncImage(
                /// The URL of the user's profile picture
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
        } else {
            // Fallback on earlier versions
        }
    }
}

// Preview provider for SwiftUI previews
struct ProfilePicture_Previews: PreviewProvider {
    static var previews: some View {
        ProfilePicture()
    }
}
