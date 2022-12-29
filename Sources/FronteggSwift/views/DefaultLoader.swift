//
//  DefaultLoader.swift
//  
//
//  Created by David Frontegg on 29/12/2022.
//

import SwiftUI

public struct DefaultLoader: View {
    
    
    public init(){}
    public var body: some View {
        HStack {
            Color(red: 0.95, green:  0.95, blue:  0.95).ignoresSafeArea(.all)
            VStack {
                ProgressView()
            }
        }
        
    }
    
}
