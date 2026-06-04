//
//  VirtualMachineLibraryView.swift
//  VirtualiseOS
//
//  Created by Daniel Mandea on 04.06.2026.
//  Copyright © 2026 M.T.D.Technology SRL. All rights reserved.
//

import SwiftUI

#if arch(arm64)

struct VirtualMachineLibraryView: View {
    @ObservedObject var coordinator: Coordinator
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            if let profile = coordinator.selectedVirtualMachineProfile {
                VirtualMachineDetailView(profile: profile, coordinator: coordinator)
            } else {
                ContentUnavailableView("No Virtual Machine Selected".localized,
                                       systemImage: "desktopcomputer",
                                       description: Text("Create or select a virtual machine.".localized))
            }
        }
        .navigationSplitViewStyle(.balanced)
        .background(libraryBackgroundColor)
        .sheet(isPresented: $coordinator.isCreatingProfile) {
            CreateVirtualMachineView(coordinator: coordinator)
        }
    }

    private var sidebar: some View {
        List(selection: $coordinator.selectedProfileID) {
            Section("Virtual Machines".localized) {
                ForEach(coordinator.virtualMachineProfiles) { profile in
                    VirtualMachineRow(profile: profile)
                        .tag(profile.id)
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            HStack(spacing: 10) {
                Button {
                    coordinator.isCreatingProfile = true
                } label: {
                    Label("Add".localized, systemImage: "plus")
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(.borderedProminent)
                .tint(.blue)

                Button {
                    coordinator.deleteSelectedProfile()
                } label: {
                    Label("Delete".localized, systemImage: "trash")
                        .labelStyle(.iconOnly)
                }
                .disabled(!coordinator.canDeleteSelectedProfile)

                Spacer()
            }
            .padding(12)
            .background(sidebarBackgroundColor)
        }
        .navigationTitle("VirtualiseOS".localized)
        .scrollContentBackground(.hidden)
        .background(sidebarBackgroundColor)
    }

    private var isDarkMode: Bool {
        colorScheme == .dark
    }

    private var libraryBackgroundColor: Color {
        isDarkMode ? VirtualiseOSPalette.detailBackground : .white
    }

    private var sidebarBackgroundColor: Color {
        isDarkMode ? VirtualiseOSPalette.sidebarBackground : .white
    }
}


#endif
