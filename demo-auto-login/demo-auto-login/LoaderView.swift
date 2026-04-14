//
//  LoaderView.swift
//  demo-auto-login
//

import SwiftUI

struct LoaderView: View {
    var body: some View {
        ZStack {
            Color(red: 0.95, green: 0.95, blue: 0.95).ignoresSafeArea(.all)
            VStack(spacing: 16) {
                Image(systemName: "person.crop.circle.badge.checkmark")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 80, height: 80)
                    .foregroundColor(.blue)
                ProgressView()
            }
        }
        .accessibilityIdentifier("LoaderView")
    }
}
