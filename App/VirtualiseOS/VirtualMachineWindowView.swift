//
//  VirtualMachineWindowView.swift
//  VirtualiseOS
//
//  Created by Daniel Mandea on 04.06.2026.
//  Copyright © 2026 M.T.D.Technology SRL. All rights reserved.
//

import SwiftUI

#if arch(arm64)

struct VirtualMachineWindowView: View {
    @ObservedObject var coordinator: Coordinator

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let virtualMachine = coordinator.displayedVirtualMachine,
               coordinator.isVirtualMachineVisible {
                DisplayView(virtualMachine: virtualMachine)
            } else {
                VStack(spacing: 14) {
                    ProgressView()
                        .controlSize(.large)
                        .tint(.white)

                    Text(MacOSVirtualMachineConfigurationHelper.localized("Opening virtual machine..."))
                        .foregroundStyle(.white)
                }
            }
        }
        .onDisappear {
            coordinator.virtualMachineWindowDidClose()
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(MacOSVirtualMachineConfigurationHelper.localized("Stop VM")) {
                    coordinator.stopVirtualMachineAndShowSettings()
                }
                .disabled(coordinator.displayedVirtualMachine == nil)
            }
        }
        .frame(minWidth: 960, minHeight: 600)
    }
}

#endif
