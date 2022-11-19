//
//  TaskRow.swift
//  poc
//
//  Created by David Frontegg on 14/11/2022.
//

import SwiftUI


struct TaskList: View {
    var body: some View {
            Text("Task 1")
                .font(.title2)
                .padding(.bottom, 8)
            Text("Move iOS tasks to JIRA")
                .font(.subheadline)
                .padding(.bottom, 16)
            
            Text("Task 2")
                .font(.title2)
                .padding(.bottom, 8)
            Text("Build Credentials Manager in iOS Wrapper")
                .font(.subheadline)
                .padding(.bottom, 16)
        
    }
}

struct TaskList_Previews: PreviewProvider {
    static var previews: some View {
        TaskList()
    }
}
