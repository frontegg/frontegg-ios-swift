//
//  ProfilePicture.swift
//  poc
//
//  Created by David Frontegg on 14/11/2022.
//

import SwiftUI

struct ProfilePicture: View {
    var body: some View {
        Image("ProfileImg")
            .resizable()
            .frame(width: 160, height: 160)
            .clipShape(Circle())
            .shadow(radius: 2)
    }
}

struct ProfilePicture_Previews: PreviewProvider {
    static var previews: some View {
        ProfilePicture()
    }
}
