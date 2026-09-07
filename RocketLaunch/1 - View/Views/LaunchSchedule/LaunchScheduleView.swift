//
//  LaunchScheduleView.swift
//  RocketLaunch
//
//  Created by Gavin Chohan on 17/01/2024.
//

import SwiftUI

struct LaunchScheduleView: View {
    @StateObject private var viewModel = LaunchScheduleViewModel()
    var body: some View {
        if viewModel.receivedNextRocketLaunch {
            Text("Next Launch")
            Text("")
            Text("Name: \(viewModel.launchName)")
            Text("Mission: \(viewModel.mission)")
        } else {
            Text("Get Next Rocket Launch")
                .padding()
            Button("Refresh") {
                viewModel.refresh()
            }
        }
    }
}
    
    struct LaunchScheduleView_Previews: PreviewProvider {
        static var previews: some View {
            LaunchScheduleView()
        }
    }
