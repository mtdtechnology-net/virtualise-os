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
    @StateObject private var model = CreateVirtualMachineViewModel()

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            Text("Create Virtual Machine".localized)
                .font(.system(size: 28, weight: .semibold))

            TextField("Name".localized, text: $model.name)
                .textFieldStyle(.roundedBorder)

            osSelectionRow

            Picker("Memory".localized, selection: $model.memorySizeInGiB) {
                ForEach([4, 6, 8, 12, 16, 24, 32], id: \.self) { value in
                    Text("%d GB".localized(value))
                        .tag(value)
                }
            }

            Stepper(value: $model.diskSizeInGiB, in: 32...2048, step: 16) {
                Text("Hard Disk: %d GB".localized(model.diskSizeInGiB))
            }

            chooserRow(title: "VM Location".localized,
                       value: model.vmBundleURL?.path ?? "Choose where VM.bundle should be stored".localized) {
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
                .buttonStyle(.borderedProminent)
                .tint(.blue)
                .disabled(!model.canCreate)
            }
        }
        .padding(28)
        .frame(width: 520, height: 520)
        .background(Color.white)
        .task {
            model.fetchLatestSupportedRestoreImageIfNeeded()
        }
    }

    private var osSelectionRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("macOS".localized)
                    .font(.system(size: 13, weight: .semibold))
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
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
    }

    private func chooserRow(title: String, value: String, action: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Button("Choose...".localized, action: action)
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
        panel.message = "Choose VM.bundle or a folder where VirtualiseOS should store it.".localized
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
