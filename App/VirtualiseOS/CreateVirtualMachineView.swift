//
//  CreateVirtualMachineView.swift
//  VirtualiseOS
//
//  Created by Daniel Mandea on 04.06.2026.
//  Copyright © 2026 M.T.D.Technology SRL. All rights reserved.
//

import SwiftUI

#if arch(arm64)

struct CreateVirtualMachineView: View {
    @ObservedObject var coordinator: Coordinator
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @StateObject private var model = CreateVirtualMachineViewModel()

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            Text("Create Virtual Machine".localized)
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(primaryTextStyle)

            TextField("Name".localized, text: $model.name)
                .textFieldStyle(.roundedBorder)

            osSelectionRow

            Picker("Memory".localized, selection: $model.memorySizeInGiB) {
                ForEach([4, 6, 8, 12, 16, 24, 32], id: \.self) { value in
                    Text("%d GB".localized(value))
                        .tag(value)
                }
            }
            .foregroundStyle(primaryTextStyle)

            Stepper(value: $model.diskSizeInGiB, in: 32...2048, step: 16) {
                Text("Hard Disk: %d GB".localized(model.diskSizeInGiB))
                    .foregroundStyle(primaryTextStyle)
            }

            chooserRow(title: "VM Location".localized,
                       value: model.vmBundleURL?.path ?? "Choose a storage folder or VM bundle".localized) {
                model.vmBundleURL = chooseFolderOrBundle()
            }

            chooserRow(title: "Shared Folder".localized,
                       value: model.sharedFolderURL?.path ?? "Optional".localized) {
                model.sharedFolderURL = chooseFolder()
            }

            Spacer()

            HStack {
                Button("Cancel".localized) {
                    dismiss()
                }
                .glassButtonStyle()

                Spacer()

                Button("Create".localized) {
                    guard let vmBundleURL = model.vmBundleURL,
                          let selectedRestoreImageOption = model.selectedRestoreImageOption else {
                        return
                    }

                    coordinator.createProfile(name: model.name,
                                              vmBundleURL: vmBundleURL,
                                              sharedFolderURL: model.sharedFolderURL,
                                              restoreImageURL: selectedRestoreImageOption.url,
                                              osVersion: selectedRestoreImageOption.displayName,
                                              memorySizeInGiB: model.memorySizeInGiB,
                                              diskSizeInGiB: model.diskSizeInGiB)
                    dismiss()
                }
                .glassButtonStyle(prominent: true)
                .tint(.blue)
                .disabled(!model.canCreate)
            }
        }
        .padding(28)
        .frame(width: 520, height: 520)
        .background(backgroundColor)
        .task {
            model.fetchLatestSupportedRestoreImageIfNeeded()
        }
    }

    private var osSelectionRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("macOS".localized)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(primaryTextStyle)
                Spacer()
                Picker("", selection: $model.selectedRestoreImageID) {
                    if model.restoreImageOptions.isEmpty {
                        Text("Loading latest supported macOS...".localized)
                            .tag("")
                    } else {
                        ForEach(model.restoreImageOptions) { option in
                            Text(option.displayName)
                                .tag(option.id)
                        }
                    }
                }
                .labelsHidden()
                .frame(width: 240)
                .disabled(model.restoreImageOptions.isEmpty)
            }

            if let restoreImageError = model.restoreImageError {
                Text(restoreImageError)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .lineLimit(2)
            } else {
                Text("Apple only exposes the latest restore image supported by this Mac through Virtualization.".localized)
                    .font(.caption)
                    .foregroundStyle(secondaryTextStyle)
                    .lineLimit(2)
            }
        }
    }

    private func chooserRow(title: String, value: String, action: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(primaryTextStyle)
                Spacer()
                Button("Choose...".localized, action: action)
                    .glassButtonStyle(prominent: true)
                    .tint(.blue)
            }

            Text(value)
                .font(.caption)
                .foregroundStyle(secondaryTextStyle)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }

    private var isDarkMode: Bool {
        colorScheme == .dark
    }

    private var backgroundColor: Color {
        isDarkMode ? VirtualiseOSPalette.detailBackground : .white
    }

    private var primaryTextStyle: Color {
        isDarkMode ? .white : .primary
    }

    private var secondaryTextStyle: Color {
        isDarkMode ? .white.opacity(0.72) : .secondary
    }

    private func chooseFolderOrBundle() -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.treatsFilePackagesAsDirectories = false
        panel.message = "Choose an existing .bundle or a folder where VirtualiseOS should create the VM bundle.".localized
        return panel.runModal() == .OK ? panel.url : nil
    }

    private func chooseFolder() -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.message = "Choose a host folder to share with the macOS virtual machine.".localized
        return panel.runModal() == .OK ? panel.url : nil
    }
}

#endif
