import SwiftUI
import FronteggSwift

/// A view that displays the user's profile information and picture.
/// This component shows the user's profile picture and information in a vertical stack.
struct ProfileTab: View {
    /// The Frontegg authentication state object
    @EnvironmentObject var fronteggAuth: FronteggAuth

    var body: some View {
        NavigationView {
            VStack{
                ProfilePicture()
                    .padding(.top, 60)
                    .padding(.bottom, 40)
                
                ProfileInfo()
                
                Spacer()
                /// A button that logs out the user when pressed
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

// Preview provider for SwiftUI previews
struct ProfileTab_Previews: PreviewProvider {
    static var previews: some View {
        ProfileTab()
    }
}
