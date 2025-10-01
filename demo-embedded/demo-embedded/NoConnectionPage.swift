import SwiftUI
import FronteggSwift

struct NoConnectionPage: View {
    @EnvironmentObject private var fronteggAuth: FronteggAuth
    
    var body: some View {
        VStack(spacing: 20) {
            // Icon
            Image(systemName: "wifi.slash")
                .resizable()
                .scaledToFit()
                .frame(width: 100, height: 100)
                .foregroundColor(.red)

            // Title
            Text("No Connection")
                .font(.largeTitle)
                .fontWeight(.bold)
                .foregroundColor(.primary)

            // Subtitle
            Text("It looks like you're offline.\nPlease check your internet connection and try again.")
                .font(.body)
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
                .padding(.horizontal)

            // Retry Button
            Button(action: {
                // Handle retry action here
                
                self.fronteggAuth.recheckConnection()
            }) {
                Text("Retry")
                    .fontWeight(.semibold)
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(12)
            }
            .padding(.horizontal, 40)
        }
        .padding()
    }
}

#Preview {
    NoConnectionPage()
}
