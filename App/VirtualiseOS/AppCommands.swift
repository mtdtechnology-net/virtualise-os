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
            Button("New Virtual Machine...".localized) {
                coordinator.showCreateProfileFlow()
            }
            .keyboardShortcut("n", modifiers: .command)
#endif
        }

        CommandMenu("Virtual Machine".localized) {
#if arch(arm64)
            Button("Start Selected VM".localized) {
                coordinator.startSelectedVirtualMachine()
            }
            .keyboardShortcut("r", modifiers: .command)
            .disabled(!coordinator.canStartSelectedProfile)

            Button("Download and Install macOS".localized) {
                coordinator.installSelectedVirtualMachine()
            }
            .disabled(!coordinator.canInstallSelectedProfile)

            Button("Cancel Installing".localized) {
                coordinator.cancelSelectedVirtualMachineInstallation()
            }
            .disabled(!coordinator.canCancelSelectedProfileInstallation)

            Button("Stop VM and Show Settings".localized) {
                coordinator.stopVirtualMachineAndShowSettings()
            }
            .keyboardShortcut(".", modifiers: [.command, .shift])
            .disabled(!coordinator.canStopVirtualMachine)

            Divider()

            Button("Choose VM Location...".localized) {
                coordinator.chooseVMLocation()
            }
            .disabled(coordinator.canStopVirtualMachine)

            Button("Choose Shared Folder...".localized) {
                coordinator.chooseSharedFolder()
            }

            Divider()

            Button("Refresh VM Status".localized) {
                coordinator.refreshVirtualMachineLibrary()
            }
            .keyboardShortcut("r", modifiers: [.command, .shift])

            Button("Delete Selected VM".localized) {
                coordinator.deleteSelectedProfile()
            }
            .disabled(!coordinator.canDeleteSelectedProfile)
#else
            Text("VirtualiseOS requires Apple silicon.".localized)
#endif
        }
    }
}
