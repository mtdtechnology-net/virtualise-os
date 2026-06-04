//
//  VirtualiseOSApp.swift
//  VirtualiseOS
//
//  Created by Daniel Mandea on 03.06.2026.
//  Copyright © 2026 M.T.D.Technology SRL. All rights reserved.
//

import SwiftData
import SwiftUI

@main
struct VirtualiseOSApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var coordinator = Coordinator()

    var body: some Scene {
        Window("VirtualiseOS", id: "main") {
            RootView(coordinator: coordinator)
                .onAppear {
                    appDelegate.coordinator = coordinator
                }
        }
        .defaultSize(width: 1120, height: 720)
        .windowResizability(.contentMinSize)
        .modelContainer(for: ProfileRecord.self)
        .commands {
            AppCommands(coordinator: coordinator)
        }

#if arch(arm64)
        Window("Virtual Machine", id: "virtual-machine") {
            VirtualMachineWindowView(coordinator: coordinator)
        }
        .defaultSize(width: 1120, height: 760)
        .windowResizability(.contentMinSize)
#endif
    }
}
