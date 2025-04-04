//
//  LoaderView.swift
//  demo
//
//  Created by David Frontegg on 13/12/2022.
//

import SwiftUI

/// A view that displays a loading indicator.
/// This component shows a loading spinner and a message while the app is loading.
struct LoaderView: View {
    var body: some View {
        Color(red: 0.95, green:  0.95, blue:  0.95).ignoresSafeArea(.all)
        VStack {
            Image("SplashIcon")
                .resizable()
                .frame(width: 100, height: 100)
            ProgressView()
                
        }
    }
}

// Preview provider for SwiftUI previews
struct LoaderView_Previews: PreviewProvider {
    static var previews: some View {
        LoaderView()
    }
}
