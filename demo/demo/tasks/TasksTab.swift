//
//  TasksTab.swift
//
//  Created by David Frontegg on 14/11/2022.
//


import SwiftUI

struct TasksTab: View {
    var body: some View {
        NavigationView {
            VStack(alignment: .leading) {
                TaskList()
                Spacer()
            }.padding(.top, 20)
            
            .navigationTitle("Tasks")
        }
    }
}

struct TasksTab_Previews: PreviewProvider {
    static var previews: some View {
        TasksTab()
    }
}
