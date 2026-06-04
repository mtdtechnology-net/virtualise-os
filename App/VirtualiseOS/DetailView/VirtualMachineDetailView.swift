//
//  VirtualMachineDetailView.swift
//  VirtualiseOS
//
//  Created by Daniel Mandea on 04/06/2026.
//  Copyright © 2026 Apple. All rights reserved.
//

import SwiftUI

#if arch(arm64)

struct VirtualMachineDetailView: View {
    
    let profile: MachineProfile
    
    // MARK: - Observable
    
    @ObservedObject var coordinator: Coordinator
    
    // MARK: - Environment
    
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header
                configurationPanel
                actionPanel
            }
            .padding(32)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(detailBackgroundColor)
    }
    
    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 8) {
                Text(profile.name)
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundStyle(primaryTextStyle)
                
                Text(profile.statusDetail.isEmpty ? profile.status.displayName : profile.statusDetail)
                    .font(.system(size: 15))
                    .foregroundStyle(secondaryTextStyle)
                    .lineLimit(3)
            }
            
            Spacer()
            
            Text(profile.status.displayName)
                .font(.system(size: 13, weight: .semibold))
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .foregroundStyle(.white)
                .background(statusColor, in: Capsule())
        }
    }
    
    private var configurationPanel: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Configuration".localized)
                .font(.headline)
                .foregroundStyle(primaryTextStyle)
            
            settingRow(title: "VM Location".localized, value: profile.vmBundlePath) {
                coordinator.chooseVMLocation()
            }
            
            Picker("Memory".localized, selection: memoryBinding) {
                ForEach([4, 6, 8, 12, 16, 24, 32], id: \.self) { value in
                    Text("%d GB".localized(value))
                        .tag(value)
                }
            }
            .pickerStyle(.menu)
            .disabled(profile.status == .running || profile.status == .installing || profile.status == .starting)
            
            Stepper(value: diskSizeBinding, in: 32...2048, step: 16) {
                Text("Hard Disk: %d GB".localized(profile.diskSizeInGiB))
            }
            .disabled(profile.status != .notInstalled && profile.status != .incomplete && profile.status != .failed)
            
            settingRow(title: "Shared Folder".localized,
                       value: profile.sharedFolderPath ?? "No shared folder selected".localized) {
                coordinator.chooseSharedFolder()
            }
        }
        .padding(22)
        .background(Color("cardWhite"))
        .modifier(CardModifier())
    }
    
    private var actionPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            if profile.status == .installing {
                ProgressView(value: profile.installProgress, total: 100)
                    .tint(.blue)
                Text("%d%% complete".localized(Int(profile.installProgress)))
                    .font(.caption)
                    .foregroundStyle(secondaryTextStyle)
            }
            
            HStack(spacing: 12) {
                Button(primaryActionTitle) {
                    runPrimaryAction()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .tint(.blue)
                .disabled(!isPrimaryActionEnabled)
                
                if profile.status == .installing || coordinator.canCancelSelectedProfileInstallation {
                    Button("Cancel Installing".localized) {
                        coordinator.cancelSelectedVirtualMachineInstallation()
                    }
                    .controlSize(.large)
                    .disabled(!coordinator.canCancelSelectedProfileInstallation)
                }
                
                if profile.status == .running || coordinator.displayedVirtualMachine != nil {
                    Button("Stop VM".localized) {
                        coordinator.stopVirtualMachineAndShowSettings()
                    }
                    .controlSize(.large)
                }
                
                Spacer()
                
                Button(role: .destructive) {
                    coordinator.deleteSelectedProfile()
                } label: {
                    Label("Delete VM".localized, systemImage: "trash")
                }
                .controlSize(.large)
                .disabled(!coordinator.canDeleteSelectedProfile)
            }
        }
        .padding(22)
        .background(Color("cardWhite"))
        .modifier(CardModifier())
    }
    
    private func settingRow(title: String, value: String, action: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(primaryTextStyle)
                Spacer()
                Button("Choose...".localized, action: action)
                    .buttonStyle(.borderedProminent)
                    .tint(.blue)
                    .disabled(profile.status == .running || profile.status == .installing || profile.status == .starting)
            }
            
            Text(value)
                .font(.caption)
                .foregroundStyle(secondaryTextStyle)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }
    
    private var memoryBinding: Binding<Int> {
        Binding(get: { profile.memorySizeInGiB },
                set: { coordinator.updateSelectedProfileMemory($0) })
    }
    
    private var diskSizeBinding: Binding<Int> {
        Binding(get: { profile.diskSizeInGiB },
                set: { coordinator.updateSelectedProfileDiskSize($0) })
    }
    
    private var primaryActionTitle: String {
        switch profile.status {
        case .installed, .stopped:
            return "Start Virtual Machine".localized
        case .running:
            return "Running".localized
        case .starting:
            return "Starting...".localized
        case .installing:
            return "Installing...".localized
        case .notInstalled, .incomplete, .failed:
            return "Download and Install Latest macOS".localized
        }
    }
    
    private var isPrimaryActionEnabled: Bool {
        switch profile.status {
        case .running, .starting, .installing:
            return false
        default:
            return true
        }
    }
    
    private func runPrimaryAction() {
        switch profile.status {
        case .installed, .stopped:
            coordinator.startSelectedVirtualMachine()
        case .notInstalled, .incomplete, .failed:
            coordinator.installSelectedVirtualMachine()
        default:
            break
        }
    }
    
    private var statusColor: Color {
        switch profile.status {
        case .running:
            return .green
        case .installing, .starting:
            return .blue
        case .failed, .incomplete:
            return .orange
        case .installed, .stopped:
            return .gray
        case .notInstalled:
            return .secondary
        }
    }
    
    private var isDarkMode: Bool {
        colorScheme == .dark
    }
    
    private var detailBackgroundColor: Color {
        isDarkMode ? VirtualiseOSPalette.detailBackground : .white
    }
    
    private var panelBackgroundStyle: Color {
        isDarkMode ? VirtualiseOSPalette.detailPanelBackground : Color(.controlBackgroundColor).opacity(0.62)
    }
    
    private var panelStrokeColor: Color {
        isDarkMode ? .white.opacity(0.08) : .blue.opacity(0.12)
    }
    
    private var primaryTextStyle: Color {
        isDarkMode ? .white : .primary
    }
    
    private var secondaryTextStyle: Color {
        isDarkMode ? .white.opacity(0.72) : .secondary
    }
}

#Preview {
    VirtualMachineDetailView(
        profile:
            MachineProfile(
                name: "Some Profile",
                memorySizeInGiB: 30,
                diskSizeInGiB: 20,
                vmBundlePath: "/Downloads/SomeVM.vm"
            ),
        coordinator: Coordinator()
    )
}

#endif
