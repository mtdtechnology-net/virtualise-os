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
            Button(MachineConfigurationHelper.localized("New Virtual Machine...")) {
                coordinator.showCreateProfileFlow()
            }
            .keyboardShortcut("n", modifiers: .command)
#endif
        }

        CommandMenu(MachineConfigurationHelper.localized("Virtual Machine")) {
#if arch(arm64)
            Button(MachineConfigurationHelper.localized("Start Selected VM")) {
                coordinator.startSelectedVirtualMachine()
            }
            .keyboardShortcut("r", modifiers: .command)
            .disabled(!coordinator.canStartSelectedProfile)

            Button(MachineConfigurationHelper.localized("Download and Install macOS")) {
                coordinator.installSelectedVirtualMachine()
            }
            .disabled(!coordinator.canInstallSelectedProfile)

            Button(MachineConfigurationHelper.localized("Cancel Installing")) {
                coordinator.cancelSelectedVirtualMachineInstallation()
            }
            .disabled(!coordinator.canCancelSelectedProfileInstallation)

            Button(MachineConfigurationHelper.localized("Stop VM and Show Settings")) {
                coordinator.stopVirtualMachineAndShowSettings()
            }
            .keyboardShortcut(".", modifiers: [.command, .shift])
            .disabled(!coordinator.canStopVirtualMachine)

            Divider()

            Button(MachineConfigurationHelper.localized("Choose VM Location...")) {
                coordinator.chooseVMLocation()
            }
            .disabled(coordinator.canStopVirtualMachine)

            Button(MachineConfigurationHelper.localized("Choose Shared Folder...")) {
                coordinator.chooseSharedFolder()
            }

            Divider()

            Button(MachineConfigurationHelper.localized("Refresh VM Status")) {
                coordinator.refreshVirtualMachineLibrary()
            }
            .keyboardShortcut("r", modifiers: [.command, .shift])

            Button(MachineConfigurationHelper.localized("Delete Selected VM")) {
                coordinator.deleteSelectedProfile()
            }
            .disabled(!coordinator.canDeleteSelectedProfile)
#else
            Text(MacOSVirtualMachineConfigurationHelper.localized("VirtualiseOS requires Apple silicon."))
#endif
        }
    }
}
