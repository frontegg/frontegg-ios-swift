//
//  SelectRegionView.swift
//  demo-multi-region
//
//  Created by David Frontegg on 23/11/2023.
//


import SwiftUI
import FronteggSwift

/// A view that allows the user to select their region.
/// This component shows a list of regions and allows the user to select one.
struct SelectRegionView: View {
    /// The Frontegg authentication state object
    @EnvironmentObject var fronteggAuth: FronteggAuth
    
    var body: some View {
        VStack(alignment: .leading) {
            Text("Welcome to MyApp")
                .font(.largeTitle)
            
            Text("Select your region:")
                .padding(.top, 8)
                .padding(.bottom, 20)
                .font(.title2)
            
            /// A list of regions available to the user
            ForEach(fronteggAuth.regionData, id: \.key.self) { item in
                /// A button that allows the user to select a region
                Button(action: {
                    FronteggApp.shared.initWithRegion(regionKey: item.key)
                }) {
                    VStack(alignment: .leading) {
                        Text("Region - \(item.key.uppercased())")
                            .font(.title2)
                            .padding(.bottom, 1)
                        Text("\(item.baseUrl)")
                            .font(.caption)
                            .tint(.black)
                            .padding(.bottom, 8)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            
            Spacer()
            
        }
        .padding()
        .navigationTitle("Region")
    }
}

// Preview provider for SwiftUI previews
struct SelectRegionView_Previews: PreviewProvider {
    static var previews: some View {
        SelectRegionView()
    }
}
