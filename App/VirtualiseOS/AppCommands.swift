//
//  AppCommands.swift
//  VirtualiseOS
//
//  Created by Daniel Mandea on 04.06.2026.
//  Copyright © 2026 M.T.D.Technology SRL. All rights reserved.
//

import SwiftUI

struct AppCommands: Commands {
    @ObservedObject var coordinator: Coordinator

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
#if arch(arm64)
            Button(MacOSVirtualMachineConfigurationHelper.localized("New Virtual Machine...")) {
                coordinator.showCreateProfileFlow()
            }
            .keyboardShortcut("n", modifiers: .command)
#endif
        }

        CommandMenu(MacOSVirtualMachineConfigurationHelper.localized("Virtual Machine")) {
#if arch(arm64)
            Button(MacOSVirtualMachineConfigurationHelper.localized("Start Selected VM")) {
                coordinator.startSelectedVirtualMachine()
            }
            .keyboardShortcut("r", modifiers: .command)
            .disabled(!coordinator.canStartSelectedProfile)

            Button(MacOSVirtualMachineConfigurationHelper.localized("Download and Install macOS")) {
                coordinator.installSelectedVirtualMachine()
            }
            .disabled(!coordinator.canInstallSelectedProfile)

            Button(MacOSVirtualMachineConfigurationHelper.localized("Stop VM and Show Settings")) {
                coordinator.stopVirtualMachineAndShowSettings()
            }
            .keyboardShortcut(".", modifiers: [.command, .shift])
            .disabled(!coordinator.canStopVirtualMachine)

            Divider()

            Button(MacOSVirtualMachineConfigurationHelper.localized("Choose VM Location...")) {
                coordinator.chooseVMLocation()
            }
            .disabled(coordinator.canStopVirtualMachine)

            Button(MacOSVirtualMachineConfigurationHelper.localized("Choose Shared Folder...")) {
                coordinator.chooseSharedFolder()
            }

            Divider()

            Button(MacOSVirtualMachineConfigurationHelper.localized("Refresh VM Status")) {
                coordinator.refreshVirtualMachineLibrary()
            }
            .keyboardShortcut("r", modifiers: [.command, .shift])

            Button(MacOSVirtualMachineConfigurationHelper.localized("Remove Selected VM")) {
                coordinator.deleteSelectedProfile()
            }
            .disabled(coordinator.selectedVirtualMachineProfile == nil || coordinator.canStopVirtualMachine)
#else
            Text(MacOSVirtualMachineConfigurationHelper.localized("VirtualiseOS requires Apple silicon."))
#endif
        }
    }
}
