//
//  VirtualiseOSCommands.swift
//  VirtualiseOS
//
//  Created by Daniel Mandea on 04.06.2026.
//  Copyright © 2026 M.T.D.Technology SRL. All rights reserved.
//

import SwiftUI

struct AppCommands: Commands {
    
    @ObservedObject var coordinator: Coordinator

    var body: some Commands {
        CommandGroup(after: .appInfo) {
#if arch(arm64)
            Divider()

            Button(MacOSVirtualMachineConfigurationHelper.localized("Choose VM Location...")) {
                coordinator.chooseVMLocation()
            }

            Button(MacOSVirtualMachineConfigurationHelper.localized("Choose Shared Folder...")) {
                coordinator.chooseSharedFolder()
            }

            Button(MacOSVirtualMachineConfigurationHelper.localized("Stop VM and Show Settings...")) {
                coordinator.stopVirtualMachineAndShowSettings()
            }
            .disabled(coordinator.displayedVirtualMachine == nil)
#endif
        }
    }
}
