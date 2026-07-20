//
//  Coordinator.swift
//  VirtualiseOS
//
//  Created by Daniel Mandea on 15.05.2025.
//  Copyright © 2026 M.T.D.Technology SRL. All rights reserved.
//

import Cocoa
import Combine
import Foundation
import SwiftData
#if arch(arm64)
import Virtualization
#endif

final class Coordinator: NSObject, ObservableObject {

    @Published var setupViewModel: SetupViewModel?
#if arch(arm64)
    @Published var displayedVirtualMachine: VZVirtualMachine?
#endif
    @Published var isVirtualMachineVisible = false
    @Published var virtualMachineProfiles: [MachineProfile]
    @Published var selectedProfileID: MachineProfile.ID? {
        didSet {
            guard oldValue != selectedProfileID else {
                return
            }

            activateSelectedProfile()
            saveProfiles()
            showInstallationScreen()
        }
    }
    @Published var isCreatingProfile = false
    @Published var virtualMachineWindowRequest = 0

    static let profilesUserDefaultsKey = "VirtualMachineProfiles"
    static let selectedProfileIDUserDefaultsKey = "SelectedVirtualMachineProfileID"

    var selectedProfile: MachineProfile? {
        guard let selectedProfileID else {
            return nil
        }

        return virtualMachineProfiles.first { $0.id == selectedProfileID }
    }

    var selectedProfileIndex: Int? {
        guard let selectedProfileID else {
            return nil
        }

        return virtualMachineProfiles.firstIndex { $0.id == selectedProfileID }
    }

    var modelContext: ModelContext?

#if arch(arm64)
    var virtualMachineResponder: MacOSVirtualMachineDelegate?
    var portForwarder: PortForwarder?

    var virtualMachine: VZVirtualMachine!
    var sleepPreventionActivityToken: NSObjectProtocol?
#endif

    var installationProcess: Process?
    enum RestoreImageDownloadMode {
        case foreground
        case background
    }

    var restoreImageDownloadObserver: NSKeyValueObservation?
    var restoreImageDownloadProfileID: MachineProfile.ID?
    var restoreImageDownloadTask: URLSessionDownloadTask?
    var restoreImageDownloadURL: URL?
    var restoreImageDownloadMode: RestoreImageDownloadMode?
    var isSwitchingRestoreImageDownloadSession = false
    var macOSInstallationObserver: NSKeyValueObservation?
    var restoreImageDownloadSession: URLSession?
#if arch(arm64)
    var installationVirtualMachineResponder: MacOSVirtualMachineDelegate?
    var installationVirtualMachine: VZVirtualMachine?
    var macOSInstaller: VZMacOSInstaller?
#endif
    var isInstallationInProgress = false
    var isCancellingInstallation = false
    var didPrepareVirtualMachine = false

    let defaultDiskImageSizeInGiB: UInt64 = 128
    let estimatedRestoreImageSizeInBytes: Int64 = 16 * 1024 * 1024 * 1024
    let restoreImageBackgroundSessionPrefix = "com.mtdtechnology.VirtualiseOS.restore-image"

    override init() {
        virtualMachineProfiles = []
        selectedProfileID = nil
        super.init()
    }

    func configurePersistence(modelContext: ModelContext) {
        guard self.modelContext == nil else {
            return
        }

        self.modelContext = modelContext
        migrateUserDefaultsProfilesIfNeeded()
        loadProfilesFromDatabase()

        if virtualMachineProfiles.isEmpty {
            createDefaultProfileIfNeeded()
        } else {
            refreshAllProfileStatuses()
            activateSelectedProfile()
            saveProfiles()
        }

#if arch(arm64)
        reconnectBackgroundRestoreImageDownloadIfNeeded()
#endif
    }
}
