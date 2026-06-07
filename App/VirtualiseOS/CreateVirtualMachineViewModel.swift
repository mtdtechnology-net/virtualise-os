//
//  CreateVirtualMachineViewModel.swift
//  VirtualiseOS
//
//  Created by Daniel Mandea on 04.06.2026.
//  Copyright © 2026 M.T.D.Technology SRL. All rights reserved.
//

import Foundation

#if arch(arm64)
import Virtualization

final class CreateVirtualMachineViewModel: ObservableObject {
    @Published var name = ""
    @Published var vmBundleURL: URL?
    @Published var sharedFolderURL: URL?
    @Published var restoreImageOptions: [RestoreImageOption] = []
    @Published var selectedRestoreImageID = ""
    @Published var isLoadingRestoreImages = false
    @Published var restoreImageError: String?
    @Published var memorySizeInGiB = MachineConfigurationHelper.defaultMemorySizeInGiB
    @Published var diskSizeInGiB = 128

    var selectedRestoreImageOption: RestoreImageOption? {
        restoreImageOptions.first { $0.id == selectedRestoreImageID }
    }

    var canCreate: Bool {
        vmBundleURL != nil && selectedRestoreImageOption != nil
    }

    func fetchLatestSupportedRestoreImageIfNeeded() {
        guard restoreImageOptions.isEmpty, !isLoadingRestoreImages else {
            return
        }

        isLoadingRestoreImages = true
        restoreImageError = nil
        VZMacOSRestoreImage.fetchLatestSupported { [weak self] result in
            DispatchQueue.main.async {
                guard let self else {
                    return
                }

                self.isLoadingRestoreImages = false

                switch result {
                case let .failure(error):
                    self.restoreImageError = error.localizedDescription

                case let .success(restoreImage):
                    let option = RestoreImageOption(url: restoreImage.url,
                                                    displayName: Coordinator.restoreImageDisplayName(operatingSystemVersion: restoreImage.operatingSystemVersion))
                    self.restoreImageOptions = [option]
                    self.selectedRestoreImageID = option.id
                }
            }
        }
    }
}

struct RestoreImageOption: Identifiable, Hashable {
    let url: URL
    let displayName: String

    var id: String {
        url.absoluteString
    }
}

#endif
