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

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            if let profile = coordinator.selectedVirtualMachineProfile {
                VirtualMachineDetailView(profile: profile, coordinator: coordinator)
            } else {
                ContentUnavailableView(MacOSVirtualMachineConfigurationHelper.localized("No Virtual Machine Selected"),
                                       systemImage: "desktopcomputer",
                                       description: Text(MacOSVirtualMachineConfigurationHelper.localized("Create or select a virtual machine.")))
            }
        }
        .navigationSplitViewStyle(.balanced)
        .background(Color.white)
        .sheet(isPresented: $coordinator.isCreatingProfile) {
            CreateVirtualMachineView(coordinator: coordinator)
        }
    }

    private var sidebar: some View {
        List(selection: $coordinator.selectedProfileID) {
            Section(MacOSVirtualMachineConfigurationHelper.localized("Virtual Machines")) {
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
                    Label(MacOSVirtualMachineConfigurationHelper.localized("Add"), systemImage: "plus")
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(.borderedProminent)
                .tint(.blue)

                Button {
                    coordinator.deleteSelectedProfile()
                } label: {
                    Label(MacOSVirtualMachineConfigurationHelper.localized("Remove"), systemImage: "minus")
                        .labelStyle(.iconOnly)
                }
                .disabled(coordinator.virtualMachineProfiles.isEmpty)

                Spacer()
            }
            .padding(12)
            .background(.regularMaterial)
        }
        .navigationTitle(MacOSVirtualMachineConfigurationHelper.localized("VirtualiseOS"))
    }
}

private struct VirtualMachineRow: View {
    let profile: MachineProfile

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(profile.name)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Spacer()

                Circle()
                    .fill(statusColor)
                    .frame(width: 8, height: 8)
            }

            Text(profile.status.displayName)
                .font(.caption)
                .foregroundStyle(.secondary)

            Text(profile.createdAt.formatted(date: .abbreviated, time: .omitted))
                .font(.caption2)
                .foregroundStyle(.secondary)

            if let osVersion = profile.osVersion, !osVersion.isEmpty {
                Text(osVersion)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 6)
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
}

private struct VirtualMachineDetailView: View {
    let profile: MachineProfile
    @ObservedObject var coordinator: Coordinator

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
        .background(Color.white)
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 8) {
                Text(profile.name)
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundStyle(.primary)

                Text(profile.statusDetail.isEmpty ? profile.status.displayName : profile.statusDetail)
                    .font(.system(size: 15))
                    .foregroundStyle(.secondary)
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
            Text(MacOSVirtualMachineConfigurationHelper.localized("Configuration"))
                .font(.headline)

            settingRow(title: MacOSVirtualMachineConfigurationHelper.localized("VM Location"), value: profile.vmBundlePath) {
                coordinator.chooseVMLocation()
            }

            Picker(MacOSVirtualMachineConfigurationHelper.localized("Memory"), selection: memoryBinding) {
                ForEach([4, 6, 8, 12, 16, 24, 32], id: \.self) { value in
                    Text(MacOSVirtualMachineConfigurationHelper.localized("%d GB", value))
                        .tag(value)
                }
            }
            .pickerStyle(.menu)
            .disabled(profile.status == .running || profile.status == .installing || profile.status == .starting)

            Stepper(value: diskSizeBinding, in: 32...2048, step: 16) {
                Text(MacOSVirtualMachineConfigurationHelper.localized("Hard Disk: %d GB", profile.diskSizeInGiB))
            }
            .disabled(profile.status != .notInstalled && profile.status != .incomplete && profile.status != .failed)

            settingRow(title: MacOSVirtualMachineConfigurationHelper.localized("Shared Folder"),
                       value: profile.sharedFolderPath ?? MacOSVirtualMachineConfigurationHelper.localized("No shared folder selected")) {
                coordinator.chooseSharedFolder()
            }
        }
        .padding(22)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(.blue.opacity(0.12), lineWidth: 1)
        }
    }

    private var actionPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            if profile.status == .installing {
                ProgressView(value: profile.installProgress, total: 100)
                    .tint(.blue)
                Text(MacOSVirtualMachineConfigurationHelper.localized("%d%% complete", Int(profile.installProgress)))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 12) {
                Button(primaryActionTitle) {
                    runPrimaryAction()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .tint(.blue)
                .disabled(!isPrimaryActionEnabled)

                if profile.status == .running || coordinator.displayedVirtualMachine != nil {
                    Button(MacOSVirtualMachineConfigurationHelper.localized("Stop VM")) {
                        coordinator.stopVirtualMachineAndShowSettings()
                    }
                    .controlSize(.large)
                }
            }
        }
        .padding(22)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func settingRow(title: String, value: String, action: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Button(MacOSVirtualMachineConfigurationHelper.localized("Choose..."), action: action)
                    .buttonStyle(.borderedProminent)
                    .tint(.blue)
                    .disabled(profile.status == .running || profile.status == .installing || profile.status == .starting)
            }

            Text(value)
                .font(.caption)
                .foregroundStyle(.secondary)
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
            return MacOSVirtualMachineConfigurationHelper.localized("Start Virtual Machine")
        case .running:
            return MacOSVirtualMachineConfigurationHelper.localized("Running")
        case .starting:
            return MacOSVirtualMachineConfigurationHelper.localized("Starting...")
        case .installing:
            return MacOSVirtualMachineConfigurationHelper.localized("Installing...")
        case .notInstalled, .incomplete, .failed:
            return MacOSVirtualMachineConfigurationHelper.localized("Download and Install Latest macOS")
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
}

private struct CreateVirtualMachineView: View {
    @ObservedObject var coordinator: Coordinator
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var vmBundleURL: URL?
    @State private var sharedFolderURL: URL?
    @State private var memorySizeInGiB = MacOSVirtualMachineConfigurationHelper.defaultMemorySizeInGiB
    @State private var diskSizeInGiB = 128

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            Text(MacOSVirtualMachineConfigurationHelper.localized("Create Virtual Machine"))
                .font(.system(size: 28, weight: .semibold))

            TextField(MacOSVirtualMachineConfigurationHelper.localized("Name"), text: $name)
                .textFieldStyle(.roundedBorder)

            Picker(MacOSVirtualMachineConfigurationHelper.localized("Memory"), selection: $memorySizeInGiB) {
                ForEach([4, 6, 8, 12, 16, 24, 32], id: \.self) { value in
                    Text(MacOSVirtualMachineConfigurationHelper.localized("%d GB", value))
                        .tag(value)
                }
            }

            Stepper(value: $diskSizeInGiB, in: 32...2048, step: 16) {
                Text(MacOSVirtualMachineConfigurationHelper.localized("Hard Disk: %d GB", diskSizeInGiB))
            }

            chooserRow(title: MacOSVirtualMachineConfigurationHelper.localized("VM Location"),
                       value: vmBundleURL?.path ?? MacOSVirtualMachineConfigurationHelper.localized("Choose where VM.bundle should be stored")) {
                vmBundleURL = chooseFolderOrBundle()
            }

            chooserRow(title: MacOSVirtualMachineConfigurationHelper.localized("Shared Folder"),
                       value: sharedFolderURL?.path ?? MacOSVirtualMachineConfigurationHelper.localized("Optional")) {
                sharedFolderURL = chooseFolder()
            }

            Spacer()

            HStack {
                Button(MacOSVirtualMachineConfigurationHelper.localized("Cancel")) {
                    dismiss()
                }

                Spacer()

                Button(MacOSVirtualMachineConfigurationHelper.localized("Create")) {
                    guard let vmBundleURL else {
                        return
                    }

                    coordinator.createProfile(name: name,
                                              vmBundleURL: vmBundleURL,
                                              sharedFolderURL: sharedFolderURL,
                                              memorySizeInGiB: memorySizeInGiB,
                                              diskSizeInGiB: diskSizeInGiB)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .tint(.blue)
                .disabled(vmBundleURL == nil)
            }
        }
        .padding(28)
        .frame(width: 520, height: 460)
        .background(Color.white)
    }

    private func chooserRow(title: String, value: String, action: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Button(MacOSVirtualMachineConfigurationHelper.localized("Choose..."), action: action)
                    .buttonStyle(.borderedProminent)
                    .tint(.blue)
            }

            Text(value)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }

    private func chooseFolderOrBundle() -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.treatsFilePackagesAsDirectories = false
        panel.message = MacOSVirtualMachineConfigurationHelper.localized("Choose VM.bundle or a folder where VirtualiseOS should store it.")
        return panel.runModal() == .OK ? panel.url : nil
    }

    private func chooseFolder() -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.message = MacOSVirtualMachineConfigurationHelper.localized("Choose a host folder to share with the macOS virtual machine.")
        return panel.runModal() == .OK ? panel.url : nil
    }
}

#endif
