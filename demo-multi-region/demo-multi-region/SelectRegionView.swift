//
//  SelectRegionView.swift
//  demo-multi-region
//
//  Created by David Frontegg on 23/11/2023.
//


import SwiftUI
import FronteggSwift

struct SelectRegionView: View {
    @EnvironmentObject var fronteggAuth: FronteggAuth
    
    var body: some View {
        VStack(alignment: .leading) {
            Text("Welcome to MyApp")
                .font(.largeTitle)
            
            Text("Select your region:")
                .padding(.top, 8)
                .padding(.bottom, 20)
                .font(.title2)
            
            
            ForEach(fronteggAuth.regionData, id: \.key.self) { item in
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

struct SelectRegionView_Previews: PreviewProvider {
    static var previews: some View {
        SelectRegionView()
    }
}
