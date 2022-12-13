//
//  LoaderView.swift
//  demo
//
//  Created by David Frontegg on 13/12/2022.
//

import SwiftUI

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

struct LoaderView_Previews: PreviewProvider {
    static var previews: some View {
        LoaderView()
    }
}
