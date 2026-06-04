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
import Virtualization

final class Coordinator: NSObject, ObservableObject {

    @Published private(set) var setupViewModel: SetupViewModel?
    @Published private(set) var displayedVirtualMachine: VZVirtualMachine?
    @Published private(set) var isVirtualMachineVisible = false
    @Published private(set) var virtualMachineProfiles: [MachineProfile]
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
    @Published private(set) var virtualMachineWindowRequest = 0

    private static let profilesUserDefaultsKey = "VirtualMachineProfiles"
    private static let selectedProfileIDUserDefaultsKey = "SelectedVirtualMachineProfileID"

    private var selectedProfile: MachineProfile? {
        guard let selectedProfileID else {
            return nil
        }

        return virtualMachineProfiles.first { $0.id == selectedProfileID }
    }

    private var selectedProfileIndex: Int? {
        guard let selectedProfileID else {
            return nil
        }

        return virtualMachineProfiles.firstIndex { $0.id == selectedProfileID }
    }

    private var modelContext: ModelContext?

    private var virtualMachineResponder: MacOSVirtualMachineDelegate?

    private var virtualMachine: VZVirtualMachine!

    private var installationProcess: Process?
    private enum RestoreImageDownloadMode {
        case foreground
        case background
    }

    private var restoreImageDownloadObserver: NSKeyValueObservation?
    private var restoreImageDownloadProfileID: MachineProfile.ID?
    private var restoreImageDownloadTask: URLSessionDownloadTask?
    private var restoreImageDownloadMode: RestoreImageDownloadMode?
    private var isSwitchingRestoreImageDownloadSession = false
    private var macOSInstallationObserver: NSKeyValueObservation?
    private var restoreImageDownloadSession: URLSession?
    private var installationVirtualMachineResponder: MacOSVirtualMachineDelegate?
    private var installationVirtualMachine: VZVirtualMachine?
    private var macOSInstaller: VZMacOSInstaller?
    private var isInstallationInProgress = false
    private var isCancellingInstallation = false
    private var didPrepareVirtualMachine = false

    private let defaultDiskImageSizeInGiB: UInt64 = 128
    private let estimatedRestoreImageSizeInBytes: Int64 = 16 * 1024 * 1024 * 1024
    private let restoreImageBackgroundSessionPrefix = "com.mtdtechnology.VirtualiseOS.restore-image"

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

    private static func loadLegacyProfiles() -> [MachineProfile] {
        guard let data = UserDefaults.standard.data(forKey: profilesUserDefaultsKey) else {
            return []
        }

        do {
            return try JSONDecoder().decode([MachineProfile].self, from: data)
        } catch {
            NSLog("Failed to load legacy virtual machine profiles: \(error.localizedDescription)")
            return []
        }
    }

    private static func loadSelectedProfileID(from profiles: [MachineProfile]) -> MachineProfile.ID? {
        guard let rawValue = UserDefaults.standard.string(forKey: selectedProfileIDUserDefaultsKey),
              let id = UUID(uuidString: rawValue),
              profiles.contains(where: { $0.id == id }) else {
            return profiles.first?.id
        }

        return id
    }

    private func migrateUserDefaultsProfilesIfNeeded() {
        guard let modelContext else {
            return
        }

        do {
            let existingCount = try modelContext.fetchCount(FetchDescriptor<ProfileRecord>())
            guard existingCount == 0 else {
                return
            }

            let legacyProfiles = Self.loadLegacyProfiles()
            guard !legacyProfiles.isEmpty else {
                return
            }

            legacyProfiles.forEach { modelContext.insert(ProfileRecord(profile: $0)) }
            try modelContext.save()
            UserDefaults.standard.removeObject(forKey: Self.profilesUserDefaultsKey)
        } catch {
            NSLog("Failed to migrate virtual machine profiles to SwiftData: \(error.localizedDescription)")
        }
    }

    private func loadProfilesFromDatabase() {
        guard let modelContext else {
            return
        }

        do {
            let descriptor = FetchDescriptor<ProfileRecord>(sortBy: [SortDescriptor(\.createdAt)])
            let records = try modelContext.fetch(descriptor)
            virtualMachineProfiles = records.map(MachineProfile.init(record:))
            selectedProfileID = Self.loadSelectedProfileID(from: virtualMachineProfiles)
        } catch {
            NSLog("Failed to load virtual machine profiles from SwiftData: \(error.localizedDescription)")
            virtualMachineProfiles = []
            selectedProfileID = nil
        }
    }

    private func saveProfiles() {
        UserDefaults.standard.set(selectedProfileID?.uuidString, forKey: Self.selectedProfileIDUserDefaultsKey)

        guard let modelContext else {
            return
        }

        do {
            let records = try modelContext.fetch(FetchDescriptor<ProfileRecord>())
            var recordsByID = Dictionary(uniqueKeysWithValues: records.map { ($0.id, $0) })
            let profileIDs = Set(virtualMachineProfiles.map(\.id))

            for profile in virtualMachineProfiles {
                if let record = recordsByID.removeValue(forKey: profile.id) {
                    record.apply(profile)
                } else {
                    modelContext.insert(ProfileRecord(profile: profile))
                }
            }

            for record in records where !profileIDs.contains(record.id) {
                modelContext.delete(record)
            }

            try modelContext.save()
        } catch {
            NSLog("Failed to save virtual machine profiles to SwiftData: \(error.localizedDescription)")
        }
    }

    private static func savedMemorySizeInGiB() -> Int {
        let savedMemorySizeInGiB = UserDefaults.standard.integer(forKey: MachineConfigurationHelper.memorySizeInGiBUserDefaultsKey)
        return savedMemorySizeInGiB > 0 ? savedMemorySizeInGiB : MachineConfigurationHelper.defaultMemorySizeInGiB
    }

    private static func normalizedVMLocation(_ url: URL) -> URL {
        if url.lastPathComponent == "VM.bundle" || url.pathExtension == "bundle" {
            return url
        }

        return url.appendingPathComponent("VM.bundle", isDirectory: true)
    }

    private func createDefaultProfileIfNeeded() {
        let profile = MachineProfile(name: MachineConfigurationHelper.localized("Primary VM"),
                                            memorySizeInGiB: Self.savedMemorySizeInGiB(),
                                            diskSizeInGiB: Int(defaultDiskImageSizeInGiB),
                                            vmBundlePath: vmBundleURL.path,
                                            status: .notInstalled)
        virtualMachineProfiles = [profile]
        selectedProfileID = profile.id
        refreshAllProfileStatuses()
        activateSelectedProfile()
        saveProfiles()
    }

    private func refreshAllProfileStatuses() {
        for index in virtualMachineProfiles.indices {
            refreshProfileStatus(at: index)
        }
    }

    private func updateSelectedProfile(status: BundleStatus,
                                       detail: String,
                                       progress: Double? = nil,
                                       osVersion: String? = nil) {
        guard let selectedProfileIndex else {
            return
        }

        virtualMachineProfiles[selectedProfileIndex].status = status
        virtualMachineProfiles[selectedProfileIndex].statusDetail = detail
        if let progress {
            virtualMachineProfiles[selectedProfileIndex].installProgress = progress
        }
        if let osVersion {
            virtualMachineProfiles[selectedProfileIndex].osVersion = osVersion
        }
        saveProfiles()
    }

    private func refreshProfileStatus(at index: Int) {
        let profile = virtualMachineProfiles[index]

        if profile.status == .installing {
            return
        }

        if profile.isInstalledOnDisk {
            let staleRunningState = profile.status == .running || profile.status == .starting
            virtualMachineProfiles[index].status = staleRunningState ? .stopped : .installed
            virtualMachineProfiles[index].installProgress = 100
            virtualMachineProfiles[index].statusDetail = staleRunningState
                ? MachineConfigurationHelper.localized("Virtual machine is stopped.")
                : MachineConfigurationHelper.localized("Ready to start.")
        } else if profile.isBundlePresentOnDisk {
            virtualMachineProfiles[index].status = .incomplete
            virtualMachineProfiles[index].installProgress = 0
            virtualMachineProfiles[index].statusDetail = MachineConfigurationHelper.localized("Missing VM files: %@", profile.missingFileNames.joined(separator: ", "))
        } else {
            virtualMachineProfiles[index].status = .notInstalled
            virtualMachineProfiles[index].installProgress = 0
            virtualMachineProfiles[index].statusDetail = MachineConfigurationHelper.localized("Download and install macOS to create this VM.")
        }
    }

    var selectedVirtualMachineProfile: MachineProfile? {
        selectedProfile
    }

    var canStartSelectedProfile: Bool {
        guard let selectedProfile else {
            return false
        }

        return selectedProfile.status == .installed || selectedProfile.status == .stopped
    }

    var canInstallSelectedProfile: Bool {
        guard let selectedProfile else {
            return false
        }

        return selectedProfile.status == .notInstalled || selectedProfile.status == .incomplete || selectedProfile.status == .failed
    }

    var canCancelSelectedProfileInstallation: Bool {
        selectedProfile?.status == .installing || isInstallationInProgress || restoreImageDownloadTask != nil || macOSInstaller != nil || installationProcess != nil
    }

    var canDeleteSelectedProfile: Bool {
        guard let selectedProfile else {
            return false
        }

        return selectedProfile.status != .running && selectedProfile.status != .starting && selectedProfile.status != .installing && !canCancelSelectedProfileInstallation
    }

    var canStopVirtualMachine: Bool {
        displayedVirtualMachine != nil || virtualMachine != nil || selectedProfile?.status == .running
    }

    private func markSelectedProfileStoppedIfNeeded() {
        guard let selectedProfileIndex,
              virtualMachineProfiles[selectedProfileIndex].status == .running || virtualMachineProfiles[selectedProfileIndex].status == .starting else {
            return
        }

        virtualMachineProfiles[selectedProfileIndex].status = .stopped
        virtualMachineProfiles[selectedProfileIndex].statusDetail = MachineConfigurationHelper.localized("Virtual machine is stopped.")
        virtualMachineProfiles[selectedProfileIndex].installProgress = 100
        saveProfiles()
    }

    func showCreateProfileFlow() {
        isCreatingProfile = true
    }

    func refreshVirtualMachineLibrary() {
        refreshAllProfileStatuses()
        activateSelectedProfile()
        saveProfiles()
        showInstallationScreen()
    }

    func createProfile(name: String,
                       vmBundleURL: URL,
                       sharedFolderURL: URL?,
                       restoreImageURL: URL?,
                       osVersion: String?,
                       memorySizeInGiB: Int,
                       diskSizeInGiB: Int) {
        do {
            let normalizedURL = Self.normalizedVMLocation(vmBundleURL)
            if !FileManager.default.fileExists(atPath: normalizedURL.path) {
                try FileManager.default.createDirectory(at: normalizedURL, withIntermediateDirectories: true)
            }
            let vmBookmarkData = try normalizedURL.bookmarkData(options: URL.BookmarkCreationOptions.withSecurityScope,
                                                                includingResourceValuesForKeys: nil,
                                                                relativeTo: nil)
            let sharedBookmarkData = try sharedFolderURL?.bookmarkData(options: URL.BookmarkCreationOptions.withSecurityScope,
                                                                       includingResourceValuesForKeys: nil,
                                                                       relativeTo: nil)
            let profileName = name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? nextGeneratedProfileName()
                : name.trimmingCharacters(in: .whitespacesAndNewlines)
            let profile = MachineProfile(name: profileName,
                                         osVersion: osVersion,
                                                restoreImageURLString: restoreImageURL?.absoluteString,
                                                memorySizeInGiB: memorySizeInGiB,
                                                diskSizeInGiB: diskSizeInGiB,
                                                vmBundlePath: normalizedURL.path,
                                                vmBundleBookmarkData: vmBookmarkData,
                                                sharedFolderPath: sharedFolderURL?.path,
                                                sharedFolderBookmarkData: sharedBookmarkData,
                                                status: .notInstalled,
                                                statusDetail: MachineConfigurationHelper.localized("Download and install macOS to create this VM."))
            virtualMachineProfiles.append(profile)
            selectedProfileID = profile.id
            refreshAllProfileStatuses()
            activateSelectedProfile()
            saveProfiles()
            isCreatingProfile = false
            showInstallationScreen()
        } catch {
            showInformationAlert(error.localizedDescription)
        }
    }

    func deleteSelectedProfile() {
        guard let selectedProfileIndex else {
            return
        }

        if !canDeleteSelectedProfile {
            showInformationAlert(MachineConfigurationHelper.localized("Stop or cancel this virtual machine before deleting it."))
            return
        }

        let profile = virtualMachineProfiles[selectedProfileIndex]
        guard confirmDelete(profile) else {
            return
        }

        do {
            try deleteBundle(for: profile)
        } catch {
            showInformationAlert(error.localizedDescription)
            return
        }

        virtualMachineProfiles.remove(at: selectedProfileIndex)
        selectedProfileID = virtualMachineProfiles.first?.id
        if virtualMachineProfiles.isEmpty {
            createDefaultProfileIfNeeded()
        } else {
            activateSelectedProfile()
            saveProfiles()
            showInstallationScreen()
        }
    }

    private func confirmDelete(_ profile: MachineProfile) -> Bool {
        let alert = NSAlert()
        alert.messageText = MachineConfigurationHelper.localized("Delete \"%@\"?", profile.name)
        alert.informativeText = MachineConfigurationHelper.localized("This removes the VM.bundle from disk and deletes the virtual machine record from the database.")
        alert.alertStyle = .warning
        alert.addButton(withTitle: MachineConfigurationHelper.localized("Delete"))
        alert.addButton(withTitle: MachineConfigurationHelper.localized("Cancel"))
        return alert.runModal() == .alertFirstButtonReturn
    }

    private func deleteBundle(for profile: MachineProfile) throws {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: profile.vmBundleURL.path) else {
            return
        }

        try fileManager.removeItem(at: profile.vmBundleURL)
    }

    private func nextGeneratedProfileName() -> String {
        let baseName = MachineConfigurationHelper.localized("Virtual Machine")
        var candidate = baseName
        var index = 2

        while virtualMachineProfiles.contains(where: { $0.name == candidate }) {
            candidate = "\(baseName) \(index)"
            index += 1
        }

        return candidate
    }

    func updateSelectedProfileMemory(_ memorySizeInGiB: Int) {
        guard let selectedProfileIndex else {
            return
        }

        virtualMachineProfiles[selectedProfileIndex].memorySizeInGiB = memorySizeInGiB
        activateSelectedProfile()
        saveProfiles()
    }

    func updateSelectedProfileDiskSize(_ diskSizeInGiB: Int) {
        guard let selectedProfileIndex else {
            return
        }

        virtualMachineProfiles[selectedProfileIndex].diskSizeInGiB = max(32, diskSizeInGiB)
        saveProfiles()
    }

    func selectProfile(_ profile: MachineProfile) {
        guard selectedProfileID != profile.id else {
            return
        }

        selectedProfileID = profile.id
        activateSelectedProfile()
        saveProfiles()
        updateSetupStateForCurrentVMLocation()
    }

    private func resolveSecurityScopedURL(from bookmarkData: Data) -> URL? {
        do {
            var isStale = false
            let url = try URL(resolvingBookmarkData: bookmarkData,
                              options: [.withSecurityScope],
                              relativeTo: nil,
                              bookmarkDataIsStale: &isStale)
            guard !isStale, url.startAccessingSecurityScopedResource() else {
                return nil
            }

            return url
        } catch {
            NSLog("Failed to resolve virtual machine bookmark: \(error.localizedDescription)")
            return nil
        }
    }

    private func activateSelectedProfile() {
        guard let selectedProfile else {
            setActiveVMBundleURL(nil)
            return
        }

        if let bookmarkData = selectedProfile.vmBundleBookmarkData,
           let resolvedURL = resolveSecurityScopedURL(from: bookmarkData) {
            setActiveVMBundleURL(resolvedURL)
        } else {
            setActiveVMBundleURL(selectedProfile.vmBundleURL)
        }
        UserDefaults.standard.set(selectedProfile.memorySizeInGiB, forKey: MachineConfigurationHelper.memorySizeInGiBUserDefaultsKey)

        if let bookmarkData = selectedProfile.sharedFolderBookmarkData {
            UserDefaults.standard.set(bookmarkData, forKey: MachineConfigurationHelper.sharedDirectoryBookmarkUserDefaultsKey)
        } else {
            UserDefaults.standard.removeObject(forKey: MachineConfigurationHelper.sharedDirectoryBookmarkUserDefaultsKey)
        }
    }

#if !arch(arm64)
    private func showInstallationScreen() {}

    private func updateSetupStateForCurrentVMLocation() {}

    private func showInformationAlert(_ message: String) {
        NSLog(message)
    }
#endif

    // MARK: Create the Mac platform configuration.

#if arch(arm64)
    private func createMacPlaform() throws -> VZMacPlatformConfiguration {
        let macPlatform = VZMacPlatformConfiguration()

        let auxiliaryStorage = VZMacAuxiliaryStorage(contentsOf: auxiliaryStorageURL)
        macPlatform.auxiliaryStorage = auxiliaryStorage

        if !FileManager.default.fileExists(atPath: vmBundlePath) {
            throw virtualMachineSetupError(MachineConfigurationHelper.localized("Missing Virtual Machine Bundle at %@. Run InstallationTool first to create it.", vmBundlePath))
        }

        // Retrieve the hardware model and save this value to disk during installation.
        guard let hardwareModelData = try? Data(contentsOf: hardwareModelURL) else {
            throw virtualMachineSetupError(MachineConfigurationHelper.localized("Failed to retrieve hardware model data."))
        }

        guard let hardwareModel = VZMacHardwareModel(dataRepresentation: hardwareModelData) else {
            throw virtualMachineSetupError(MachineConfigurationHelper.localized("Failed to create hardware model."))
        }

        if !hardwareModel.isSupported {
            throw virtualMachineSetupError(MachineConfigurationHelper.localized("The hardware model isn't supported on the current host"))
        }
        macPlatform.hardwareModel = hardwareModel

        // Retrieve the machine identifier and save this value to disk during installation.
        guard let machineIdentifierData = try? Data(contentsOf: machineIdentifierURL) else {
            throw virtualMachineSetupError(MachineConfigurationHelper.localized("Failed to retrieve machine identifier data."))
        }

        guard let machineIdentifier = VZMacMachineIdentifier(dataRepresentation: machineIdentifierData) else {
            throw virtualMachineSetupError(MachineConfigurationHelper.localized("Failed to create machine identifier."))
        }
        macPlatform.machineIdentifier = machineIdentifier

        return macPlatform
    }

    // MARK: Create the virtual machine configuration and instantiate the virtual machine.

    private func createVirtualMachine() throws {
        let virtualMachineConfiguration = VZVirtualMachineConfiguration()

        virtualMachineConfiguration.platform = try createMacPlaform()
        virtualMachineConfiguration.bootLoader = MachineConfigurationHelper.createBootLoader()
        virtualMachineConfiguration.cpuCount = MachineConfigurationHelper.computeCPUCount()
        virtualMachineConfiguration.memorySize = MachineConfigurationHelper.computeMemorySize()

        virtualMachineConfiguration.audioDevices = [MachineConfigurationHelper.createSoundDeviceConfiguration()]
        virtualMachineConfiguration.graphicsDevices = [MachineConfigurationHelper.createGraphicsDeviceConfiguration()]
        virtualMachineConfiguration.networkDevices = [MachineConfigurationHelper.createNetworkDeviceConfiguration()]
        virtualMachineConfiguration.storageDevices = [MachineConfigurationHelper.createBlockDeviceConfiguration()]
        if let directorySharingDevice = MachineConfigurationHelper.createDirectorySharingDeviceConfiguration() {
            virtualMachineConfiguration.directorySharingDevices = [directorySharingDevice]
        }

        virtualMachineConfiguration.pointingDevices = [MachineConfigurationHelper.createPointingDeviceConfiguration()]
        virtualMachineConfiguration.keyboards = [MachineConfigurationHelper.createKeyboardConfiguration()]

        try virtualMachineConfiguration.validate()

        if #available(macOS 14.0, *) {
            try virtualMachineConfiguration.validateSaveRestoreSupport()
        }

        virtualMachine = VZVirtualMachine(configuration: virtualMachineConfiguration)
    }

    private func virtualMachineSetupError(_ message: String) -> NSError {
        NSError(domain: "VirtualiseOS", code: 10, userInfo: [NSLocalizedDescriptionKey: message])
    }

    // MARK: Start or restore the virtual machine.

    func startVirtualMachine() {
        virtualMachine.start(completionHandler: { [weak self] result in
            DispatchQueue.main.async {
                guard let self else {
                    return
                }

                switch result {
                case .success:
                    self.presentRunningVirtualMachine()

                case let .failure(error):
                    self.handleVirtualMachineLaunchFailure(self.virtualMachineErrorMessage(prefixKey: "Virtual machine failed to start with %@", error: error))
                }
            }
        })
    }

    func resumeVirtualMachine() {
        virtualMachine.resume(completionHandler: { [weak self] result in
            DispatchQueue.main.async {
                guard let self else {
                    return
                }

                switch result {
                case .success:
                    self.presentRunningVirtualMachine()

                case let .failure(error):
                    self.handleVirtualMachineLaunchFailure(self.virtualMachineErrorMessage(prefixKey: "Virtual machine failed to resume with %@", error: error))
                }
            }
        })
    }

    private func virtualMachineErrorMessage(prefixKey: String, error: Error) -> String {
        let nsError = error as NSError
        let errorDescription = "\(error)"

        if errorDescription.contains("Failed to lock auxiliary storage")
            || nsError.localizedDescription.contains("Failed to lock auxiliary storage") {
            return MachineConfigurationHelper.localized("The virtual machine is already in use. Quit any other running copy of VirtualiseOS or wait for the previous VM process to finish, then start the app again.")
        }

        return MachineConfigurationHelper.localized(prefixKey, errorDescription)
    }

    @available(macOS 14.0, *)
    func restoreVirtualMachine() {
        virtualMachine.restoreMachineStateFrom(url: saveFileURL, completionHandler: { [self] (error) in
            // Remove the saved file. Whether success or failure, the state no longer matches the VM's disk.
            let fileManager = FileManager.default
            do {
                try fileManager.removeItem(at: saveFileURL)
            } catch {
                NSLog("Failed to remove saved VM state at \(saveFileURL.path): \(error.localizedDescription)")
            }

            if error == nil {
                self.resumeVirtualMachine()
            } else {
                NSLog("Failed to restore saved VM state; starting normally. \(error!.localizedDescription)")
                self.startVirtualMachine()
            }
        })
    }
#endif

#if arch(arm64)
    func prepareVirtualMachineIfNeeded() {
        guard !didPrepareVirtualMachine else {
            return
        }

        didPrepareVirtualMachine = true
        prepareVirtualMachine()
    }

    private func prepareVirtualMachine() {
        activateSelectedProfile()
        refreshAllProfileStatuses()
        showInstallationScreen()
    }

    func applicationDidBecomeActive() {
        refreshSetupStateIfNeeded()
        switchRestoreImageDownloadModeIfNeeded(to: .foreground)
    }

    func applicationDidResignActive() {
        switchRestoreImageDownloadModeIfNeeded(to: .background)
    }

    func refreshSetupStateIfNeeded() {
        guard virtualMachine == nil,
              installationProcess == nil,
              !isInstallationInProgress,
              setupViewModel != nil else {
            return
        }

        updateSetupStateForCurrentVMLocation()
    }

    private var isVirtualMachineInstalled: Bool {
        let fileManager = FileManager.default
        let requiredPaths = [
            vmBundlePath,
            auxiliaryStorageURL.path,
            diskImageURL.path,
            hardwareModelURL.path,
            machineIdentifierURL.path
        ]

        return requiredPaths.allSatisfy { fileManager.fileExists(atPath: $0) }
    }

    private func launchVirtualMachine() {
        showVirtualMachineStartingState()

        DispatchQueue.main.async { [weak self] in
            self?.startVirtualMachineLaunch()
        }
    }

    private func startVirtualMachineLaunch() {
        do {
            try createVirtualMachine()
        } catch {
            handleVirtualMachineLaunchFailure(error.localizedDescription)
            return
        }

        virtualMachineResponder = MacOSVirtualMachineDelegate()
        virtualMachineResponder?.didStopWithErrorHandler = { [weak self] error in
            DispatchQueue.main.async {
                self?.handleVirtualMachineLaunchFailure(self?.virtualMachineErrorMessage(prefixKey: "Virtual machine stopped with %@", error: error) ?? error.localizedDescription)
            }
        }
        virtualMachineResponder?.guestDidStopHandler = { [weak self] in
            DispatchQueue.main.async {
                self?.returnToSettingsScreen(markAsStopped: true)
            }
        }
        virtualMachine.delegate = virtualMachineResponder
        displayedVirtualMachine = virtualMachine
        isVirtualMachineVisible = false

        DispatchQueue.main.async { [weak self] in
            self?.startOrRestoreVirtualMachine()
        }
    }

    private func startOrRestoreVirtualMachine() {
        if #available(macOS 14.0, *) {
            let fileManager = FileManager.default
            if fileManager.fileExists(atPath: saveFileURL.path) {
                restoreVirtualMachine()
            } else {
                startVirtualMachine()
            }
        } else {
            startVirtualMachine()
        }
    }

    private func presentRunningVirtualMachine() {
        setupViewModel?.isLaunchSpinnerVisible = false
        updateSelectedProfile(status: .running,
                              detail: MachineConfigurationHelper.localized("Virtual machine is running."),
                              progress: 100)
        isVirtualMachineVisible = true
        virtualMachineWindowRequest += 1
    }

    private func showVirtualMachineStartingState() {
        guard let setupViewModel else {
            return
        }

        updateSelectedProfile(status: .starting,
                              detail: MachineConfigurationHelper.localized("Opening the selected VM.bundle."),
                              progress: 100)
        setupViewModel.status = MachineConfigurationHelper.localized("Starting virtual machine...")
        setupViewModel.detail = MachineConfigurationHelper.localized("VirtualiseOS is validating the VM configuration and opening the selected VM.bundle.")
        setupViewModel.actionTitle = MachineConfigurationHelper.localized("Starting...")
        setupViewModel.isActionEnabled = false
        setupViewModel.areControlsEnabled = false
        setupViewModel.progress = 0
        setupViewModel.isProgressVisible = false
        setupViewModel.isLaunchSpinnerVisible = true
    }

    private func handleVirtualMachineLaunchFailure(_ message: String) {
        updateSelectedProfile(status: .stopped,
                              detail: MachineConfigurationHelper.localized("Virtual machine is stopped."),
                              progress: 100)
        displayedVirtualMachine = nil
        isVirtualMachineVisible = false
        virtualMachine = nil
        virtualMachineResponder = nil
        showInstallationScreen()
        updateSelectedProfile(status: .failed, detail: message, progress: 0)
        setupViewModel?.status = MachineConfigurationHelper.localized("Virtual machine failed to start")
        setupViewModel?.detail = message
        setupViewModel?.progress = 0
        setupViewModel?.isProgressVisible = false
        setupViewModel?.isLaunchSpinnerVisible = false
        setupViewModel?.actionTitle = MachineConfigurationHelper.localized("Retry Open VM")
        setupViewModel?.isActionHidden = false
        setupViewModel?.isActionEnabled = true
        setupViewModel?.areControlsEnabled = true
    }

    func stopVirtualMachineAndShowSettings() {
        guard let virtualMachine else {
            returnToSettingsScreen(markAsStopped: true)
            return
        }

        if virtualMachine.canStop {
            virtualMachine.stop { [weak self] error in
                DispatchQueue.main.async {
                    if let error {
                        self?.showInformationAlert(self?.virtualMachineErrorMessage(prefixKey: "Virtual machine failed to stop with %@", error: error) ?? error.localizedDescription)
                        return
                    }

                    self?.returnToSettingsScreen(markAsStopped: true)
                }
            }
        } else {
            showInformationAlert(MachineConfigurationHelper.localized("The virtual machine cannot be stopped while it is changing state. Try again in a moment."))
        }
    }

    func virtualMachineWindowDidClose() {
        guard displayedVirtualMachine != nil || virtualMachine != nil else {
            returnToSettingsScreen(markAsStopped: true)
            return
        }

        if let virtualMachine, virtualMachine.canStop {
            virtualMachine.stop { [weak self] error in
                DispatchQueue.main.async {
                    if let error {
                        self?.showInformationAlert(self?.virtualMachineErrorMessage(prefixKey: "Virtual machine failed to stop with %@", error: error) ?? error.localizedDescription)
                    }
                    self?.returnToSettingsScreen(markAsStopped: true)
                }
            }
        } else {
            returnToSettingsScreen(markAsStopped: true)
        }
    }

    private func returnToSettingsScreen(markAsStopped: Bool = false) {
        if markAsStopped {
            markSelectedProfileStoppedIfNeeded()
            updateSelectedProfile(status: .stopped,
                                  detail: MachineConfigurationHelper.localized("Virtual machine is stopped."),
                                  progress: 100)
        }
        displayedVirtualMachine = nil
        isVirtualMachineVisible = false
        virtualMachine = nil
        virtualMachineResponder = nil
        showInstallationScreen()
        updateSetupStateForCurrentVMLocation()
    }

    private func showInstallationScreen() {
        let model = SetupViewModel(status: MachineConfigurationHelper.localized("Virtual machine is not installed"),
                                   detail: MachineConfigurationHelper.localized("Download and install the latest macOS version supported by this Mac."),
                                   actionTitle: MachineConfigurationHelper.localized("Download and Install Latest macOS"),
                                   selectedMemorySizeInGiB: selectedMemorySizeInGiB(),
                                   vmLocationDescription: vmLocationDescription(),
                                   sharedFolderDescription: sharedFolderDescription())
        model.actionHandler = { [weak self] in
            self?.downloadAndInstallLatestMacOS()
        }
        model.cancelActionHandler = { [weak self] in
            self?.cancelSelectedVirtualMachineInstallation()
        }
        model.chooseVMLocationHandler = { [weak self] in
            self?.chooseVMLocation()
        }
        model.chooseSharedFolderHandler = { [weak self] in
            self?.chooseSharedFolder()
        }
        model.memorySelectionHandler = { memorySizeInGiB in
            UserDefaults.standard.set(memorySizeInGiB, forKey: MachineConfigurationHelper.memorySizeInGiBUserDefaultsKey)
        }

        setupViewModel = model
        updateSetupStateForCurrentVMLocation()
    }

    private func vmLocationDescription() -> String {
        return MachineConfigurationHelper.localized("VM bundle path: %@", vmBundleURL.path)
    }

    func chooseVMLocation() {
        guard virtualMachine == nil else {
            showInformationAlert(MachineConfigurationHelper.localized("Changing the VM location requires quitting the running virtual machine first."))
            return
        }

        let openPanel = NSOpenPanel()
        openPanel.canChooseFiles = true
        openPanel.canChooseDirectories = true
        openPanel.allowsMultipleSelection = false
        openPanel.canCreateDirectories = true
        openPanel.treatsFilePackagesAsDirectories = false
        openPanel.prompt = MachineConfigurationHelper.localized("Choose")
        openPanel.message = MachineConfigurationHelper.localized("Choose VM.bundle or the folder where VirtualiseOS should store it.")

        guard openPanel.runModal() == .OK, let url = openPanel.url else {
            return
        }

        do {
            let selectedURL = normalizedSelectedVMLocation(url)
            if !FileManager.default.fileExists(atPath: selectedURL.path) {
                try FileManager.default.createDirectory(at: selectedURL, withIntermediateDirectories: true)
            }
            let bookmarkData = try selectedURL.bookmarkData(options: [.withSecurityScope],
                                                            includingResourceValuesForKeys: nil,
                                                            relativeTo: nil)
            UserDefaults.standard.set(bookmarkData, forKey: vmBundleBookmarkUserDefaultsKey)
            UserDefaults.standard.removeObject(forKey: vmBundleParentDirectoryBookmarkUserDefaultsKey)
            if let selectedProfileIndex {
                virtualMachineProfiles[selectedProfileIndex].vmBundlePath = selectedURL.path
                virtualMachineProfiles[selectedProfileIndex].vmBundleBookmarkData = bookmarkData
                refreshProfileStatus(at: selectedProfileIndex)
                activateSelectedProfile()
                saveProfiles()
            }
            setupViewModel?.vmLocationDescription = vmLocationDescription()
            updateSetupStateForCurrentVMLocation()
        } catch {
            showInstallationFailure(error.localizedDescription)
        }
    }

    private func normalizedSelectedVMLocation(_ url: URL) -> URL {
        if url.lastPathComponent == "VM.bundle" || url.pathExtension == "bundle" {
            return url
        }

        return url.appendingPathComponent("VM.bundle", isDirectory: true)
    }

    private func updateSetupStateForCurrentVMLocation() {
        guard let setupViewModel else {
            return
        }

        setupViewModel.isActionHidden = false
        setupViewModel.isActionEnabled = true
        setupViewModel.areControlsEnabled = true
        setupViewModel.progress = 0
        setupViewModel.isProgressVisible = false
        setupViewModel.isLaunchSpinnerVisible = false
        setupViewModel.isCancelActionVisible = canCancelSelectedProfileInstallation
        setupViewModel.isCancelActionEnabled = canCancelSelectedProfileInstallation
        setupViewModel.vmLocationDescription = vmLocationDescription()
        setupViewModel.sharedFolderDescription = sharedFolderDescription()

        if isVirtualMachineInstalled {
            setupViewModel.status = MachineConfigurationHelper.localized("Virtual machine is ready")
            setupViewModel.detail = MachineConfigurationHelper.localized("Open the existing VM.bundle at the selected location.")
            setupViewModel.actionTitle = MachineConfigurationHelper.localized("Open VM")
        } else if FileManager.default.fileExists(atPath: vmBundlePath) {
            setupViewModel.status = MachineConfigurationHelper.localized("VM.bundle was found but is incomplete")
            setupViewModel.detail = missingVirtualMachineFilesDescription()
            setupViewModel.actionTitle = MachineConfigurationHelper.localized("Download and Install Latest macOS")
        } else {
            setupViewModel.status = MachineConfigurationHelper.localized("Virtual machine is not installed")
            setupViewModel.detail = MachineConfigurationHelper.localized("Download and install the latest macOS version supported by this Mac.")
            setupViewModel.actionTitle = MachineConfigurationHelper.localized("Download and Install Latest macOS")
        }
    }

    private func missingVirtualMachineFilesDescription() -> String {
        let requiredFiles = [
            auxiliaryStorageURL,
            diskImageURL,
            hardwareModelURL,
            machineIdentifierURL
        ]
        let missingNames = requiredFiles
            .filter { !FileManager.default.fileExists(atPath: $0.path) }
            .map(\.lastPathComponent)

        guard !missingNames.isEmpty else {
            return MachineConfigurationHelper.localized("Open the existing VM.bundle at the selected location.")
        }

        return MachineConfigurationHelper.localized("Missing VM files: %@", missingNames.joined(separator: ", "))
    }

    private func showInformationAlert(_ message: String) {
        let alert = NSAlert()
        alert.messageText = MachineConfigurationHelper.localized("VirtualiseOS")
        alert.informativeText = message
        alert.alertStyle = .informational
        alert.addButton(withTitle: MachineConfigurationHelper.localized("OK"))
        alert.runModal()
    }

    private func sharedFolderDescription() -> String {
        guard let url = selectedSharedFolderURL() else {
            return MachineConfigurationHelper.localized("No shared folder selected")
        }

        return MachineConfigurationHelper.localized("Shared in the guest at /Volumes/My Shared Files: %@", url.path)
    }

    private func selectedSharedFolderURL() -> URL? {
        guard let bookmarkData = UserDefaults.standard.data(forKey: MachineConfigurationHelper.sharedDirectoryBookmarkUserDefaultsKey) else {
            return nil
        }

        do {
            var isStale = false
            let url = try URL(resolvingBookmarkData: bookmarkData,
                              options: [.withSecurityScope],
                              relativeTo: nil,
                              bookmarkDataIsStale: &isStale)
            return isStale ? nil : url
        } catch {
            return nil
        }
    }

    func chooseSharedFolder() {
        let openPanel = NSOpenPanel()
        openPanel.canChooseFiles = false
        openPanel.canChooseDirectories = true
        openPanel.allowsMultipleSelection = false
        openPanel.canCreateDirectories = true
        openPanel.prompt = MachineConfigurationHelper.localized("Choose")
        openPanel.message = MachineConfigurationHelper.localized("Choose a host folder to share with the macOS virtual machine.")

        guard openPanel.runModal() == .OK, let url = openPanel.url else {
            return
        }

        do {
            let bookmarkData = try url.bookmarkData(options: [.withSecurityScope],
                                                    includingResourceValuesForKeys: nil,
                                                    relativeTo: nil)
            UserDefaults.standard.set(bookmarkData, forKey: MachineConfigurationHelper.sharedDirectoryBookmarkUserDefaultsKey)
            if let selectedProfileIndex {
                virtualMachineProfiles[selectedProfileIndex].sharedFolderPath = url.path
                virtualMachineProfiles[selectedProfileIndex].sharedFolderBookmarkData = bookmarkData
                saveProfiles()
            }
            setupViewModel?.sharedFolderDescription = sharedFolderDescription()
            updateRunningSharedFolderIfPossible()
            updateSetupStateForCurrentVMLocation()
        } catch {
            showInstallationFailure(error.localizedDescription)
        }
    }

    private func updateRunningSharedFolderIfPossible() {
        guard let virtualMachine,
              let directorySharingDevice = virtualMachine.directorySharingDevices.first as? VZVirtioFileSystemDevice,
              let sharingConfiguration = MachineConfigurationHelper.createDirectorySharingDeviceConfiguration() else {
            return
        }

        directorySharingDevice.share = sharingConfiguration.share
    }

    private func selectedMemorySizeInGiB() -> Int {
        let savedMemorySizeInGiB = UserDefaults.standard.integer(forKey: MachineConfigurationHelper.memorySizeInGiBUserDefaultsKey)
        return savedMemorySizeInGiB > 0 ? savedMemorySizeInGiB : MachineConfigurationHelper.defaultMemorySizeInGiB
    }

    static func macOSVersionString(_ version: OperatingSystemVersion) -> String {
        if version.patchVersion > 0 {
            return "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)"
        }

        return "\(version.majorVersion).\(version.minorVersion)"
    }

    static func restoreImageDisplayName(operatingSystemVersion: OperatingSystemVersion, buildVersion: String? = nil) -> String {
        let version = macOSVersionString(operatingSystemVersion)
        guard let buildVersion, !buildVersion.isEmpty else {
            return MachineConfigurationHelper.localized("macOS %@", version)
        }

        return MachineConfigurationHelper.localized("macOS %@ (%@)", version, buildVersion)
    }

    func startSelectedVirtualMachine() {
        activateSelectedProfile()
        guard isVirtualMachineInstalled else {
            updateSetupStateForCurrentVMLocation()
            return
        }

        launchVirtualMachine()
    }

    func installSelectedVirtualMachine() {
        activateSelectedProfile()
        downloadAndInstallLatestMacOS()
    }

    @objc private func downloadAndInstallLatestMacOS() {
        activateSelectedProfile()
        if isVirtualMachineInstalled {
            launchVirtualMachine()
            return
        }

        if let memorySizeInGiB = setupViewModel?.selectedMemorySizeInGiB {
            UserDefaults.standard.set(memorySizeInGiB, forKey: MachineConfigurationHelper.memorySizeInGiBUserDefaultsKey)
        }

        isInstallationInProgress = true
        isCancellingInstallation = false
        updateSelectedProfile(status: .installing,
                              detail: MachineConfigurationHelper.localized("Preparing installation."),
                              progress: 0)
        setupViewModel?.isActionEnabled = false
        setupViewModel?.isCancelActionVisible = true
        setupViewModel?.isCancelActionEnabled = true
        setupViewModel?.areControlsEnabled = false
        setupViewModel?.isProgressVisible = true
        setupViewModel?.progress = 0
        startInAppInstallation()
    }

    func cancelSelectedVirtualMachineInstallation() {
        guard canCancelSelectedProfileInstallation else {
            return
        }

        isCancellingInstallation = true
        setupViewModel?.status = MachineConfigurationHelper.localized("Canceling installation...")
        setupViewModel?.detail = MachineConfigurationHelper.localized("Stopping the current download or installer.")
        setupViewModel?.isCancelActionEnabled = false

        restoreImageDownloadTask?.cancel()
        restoreImageDownloadSession?.invalidateAndCancel()
        restoreImageDownloadObserver = nil
        restoreImageDownloadTask = nil
        restoreImageDownloadMode = nil
        restoreImageDownloadProfileID = nil
        restoreImageDownloadSession = nil

        macOSInstaller?.progress.cancel()
        installationProcess?.terminate()

        completeInstallationCancellation()
    }

    private func completeInstallationCancellation() {
        isInstallationInProgress = false
        restoreImageDownloadObserver = nil
        restoreImageDownloadProfileID = nil
        restoreImageDownloadTask = nil
        restoreImageDownloadMode = nil
        macOSInstallationObserver = nil
        macOSInstaller = nil
        restoreImageDownloadSession?.finishTasksAndInvalidate()
        restoreImageDownloadSession = nil
        installationVirtualMachine = nil
        installationVirtualMachineResponder = nil
        installationProcess = nil
        isCancellingInstallation = false

        refreshAllProfileStatuses()
        let canceledStatus: BundleStatus = FileManager.default.fileExists(atPath: vmBundlePath) ? .incomplete : .notInstalled
        updateSelectedProfile(status: canceledStatus,
                              detail: MachineConfigurationHelper.localized("Installation was canceled. Delete the VM or start installation again."),
                              progress: 0)
        updateSetupStateForCurrentVMLocation()
    }

    private func startInAppInstallation() {
        do {
            try removeIncompleteVirtualMachineBundleIfNeeded()
            try FileManager.default.createDirectory(at: vmBundleURL, withIntermediateDirectories: true)
        } catch {
            showInstallationFailure(error.localizedDescription)
            return
        }

        setupViewModel?.isActionHidden = true
        setupViewModel?.status = MachineConfigurationHelper.localized("Preparing macOS restore image...")
        setupViewModel?.detail = MachineConfigurationHelper.localized("VirtualiseOS will download the selected macOS restore image.")
        setupViewModel?.progress = 0

        downloadSelectedRestoreImageOrLatest()
    }

    private func downloadSelectedRestoreImageOrLatest() {
        if let selectedProfile,
           let restoreImageURL = selectedProfile.restoreImageURL {
            let osVersion = selectedProfile.osVersion ?? MachineConfigurationHelper.localized("Selected macOS")
            setupViewModel?.detail = MachineConfigurationHelper.localized("Selected macOS: %@", osVersion)
            updateSelectedProfile(status: .installing,
                                  detail: MachineConfigurationHelper.localized("Selected macOS: %@", osVersion),
                                  progress: 0,
                                  osVersion: selectedProfile.osVersion)
            downloadRestoreImage(from: restoreImageURL, osVersion: selectedProfile.osVersion)
            return
        }

        fetchLatestSupportedRestoreImage()
    }

    private func fetchLatestSupportedRestoreImage() {
        VZMacOSRestoreImage.fetchLatestSupported { [weak self] result in
            DispatchQueue.main.async {
                guard let self, self.isInstallationInProgress else {
                    return
                }

                switch result {
                case let .failure(error):
                    self.showInstallationFailure(error.localizedDescription)

                case let .success(restoreImage):
                    let osVersion = Self.restoreImageDisplayName(operatingSystemVersion: restoreImage.operatingSystemVersion,
                                                                 buildVersion: restoreImage.buildVersion)
                    self.setupViewModel?.detail = MachineConfigurationHelper.localized("Latest supported macOS: %@", osVersion)
                    self.updateSelectedProfile(status: .installing,
                                               detail: MachineConfigurationHelper.localized("Latest supported macOS: %@", osVersion),
                                               progress: 0,
                                               osVersion: osVersion)
                    self.downloadRestoreImage(restoreImage)
                }
            }
        }
    }

    private func foregroundRestoreImageDownloadSession() -> URLSession {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 300
        configuration.timeoutIntervalForResource = 24 * 60 * 60
        configuration.waitsForConnectivity = true
        configuration.allowsExpensiveNetworkAccess = true
        configuration.allowsConstrainedNetworkAccess = true

        return URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
    }

    private func backgroundRestoreImageDownloadSession(for profileID: MachineProfile.ID) -> URLSession {
        let configuration = URLSessionConfiguration.background(withIdentifier: "\(restoreImageBackgroundSessionPrefix).\(profileID.uuidString)")
        configuration.timeoutIntervalForRequest = 300
        configuration.timeoutIntervalForResource = 24 * 60 * 60
        configuration.waitsForConnectivity = true
        configuration.isDiscretionary = false
        configuration.allowsExpensiveNetworkAccess = true
        configuration.allowsConstrainedNetworkAccess = true

        return URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
    }

    private func restoreImageDownloadSession(for mode: RestoreImageDownloadMode, profileID: MachineProfile.ID) -> URLSession {
        switch mode {
        case .foreground:
            return foregroundRestoreImageDownloadSession()
        case .background:
            return backgroundRestoreImageDownloadSession(for: profileID)
        }
    }

    private func reconnectBackgroundRestoreImageDownloadIfNeeded() {
        guard restoreImageDownloadSession == nil,
              let installingProfile = virtualMachineProfiles.first(where: { $0.status == .installing && $0.installProgress < 50 }) else {
            return
        }

        selectedProfileID = installingProfile.id
        restoreImageDownloadProfileID = installingProfile.id
        let session = backgroundRestoreImageDownloadSession(for: installingProfile.id)
        restoreImageDownloadSession = session
        restoreImageDownloadMode = .background
        session.getAllTasks { [weak self] tasks in
            guard tasks.isEmpty else {
                if let downloadTask = tasks.compactMap({ $0 as? URLSessionDownloadTask }).first {
                    DispatchQueue.main.async {
                        self?.restoreImageDownloadTask = downloadTask
                    }
                }
                tasks.forEach { $0.resume() }
                return
            }

            DispatchQueue.main.async {
                self?.restoreImageDownloadSession?.finishTasksAndInvalidate()
                self?.restoreImageDownloadSession = nil
                self?.restoreImageDownloadProfileID = nil
                self?.showInstallationFailure(MachineConfigurationHelper.localized("The background macOS download is no longer available. Start the download again."))
            }
        }
    }

    private func downloadRestoreImage(_ restoreImage: VZMacOSRestoreImage) {
        downloadRestoreImage(from: restoreImage.url,
                             osVersion: Self.restoreImageDisplayName(operatingSystemVersion: restoreImage.operatingSystemVersion,
                                                                     buildVersion: restoreImage.buildVersion))
    }

    private func downloadRestoreImage(from url: URL, osVersion: String?) {
        setupViewModel?.status = MachineConfigurationHelper.localized("Downloading macOS restore image...")
        if let osVersion {
            setupViewModel?.detail = MachineConfigurationHelper.localized("Downloading %@.", osVersion)
        } else {
            setupViewModel?.detail = MachineConfigurationHelper.localized("The download can continue in the background while VirtualiseOS remains open.")
        }

        let profileID = selectedProfileID ?? UUID()
        restoreImageDownloadProfileID = profileID

        let mode: RestoreImageDownloadMode = NSApp.isActive ? .foreground : .background
        startRestoreImageDownload(from: url, resumeData: nil, profileID: profileID, mode: mode)
    }

    private func startRestoreImageDownload(from url: URL?,
                                           resumeData: Data?,
                                           profileID: MachineProfile.ID,
                                           mode: RestoreImageDownloadMode) {
        let session = restoreImageDownloadSession(for: mode, profileID: profileID)
        let downloadTask: URLSessionDownloadTask

        if let resumeData {
            downloadTask = session.downloadTask(withResumeData: resumeData)
        } else if let url {
            downloadTask = session.downloadTask(with: url)
        } else {
            showInstallationFailure(MachineConfigurationHelper.localized("The macOS download could not be resumed."))
            return
        }

        downloadTask.countOfBytesClientExpectsToReceive = estimatedRestoreImageSizeInBytes
        restoreImageDownloadSession = session
        restoreImageDownloadTask = downloadTask
        restoreImageDownloadMode = mode
        restoreImageDownloadProfileID = profileID
        downloadTask.resume()
    }

    private func switchRestoreImageDownloadModeIfNeeded(to mode: RestoreImageDownloadMode) {
        guard isInstallationInProgress,
              let currentTask = restoreImageDownloadTask,
              let profileID = restoreImageDownloadProfileID,
              restoreImageDownloadMode != mode,
              !isSwitchingRestoreImageDownloadSession else {
            return
        }

        isSwitchingRestoreImageDownloadSession = true
        currentTask.cancel { [weak self] resumeData in
            DispatchQueue.main.async {
                guard let self else {
                    return
                }

                self.restoreImageDownloadSession?.finishTasksAndInvalidate()
                self.restoreImageDownloadSession = nil
                self.restoreImageDownloadTask = nil
                self.isSwitchingRestoreImageDownloadSession = false
                self.startRestoreImageDownload(from: nil,
                                               resumeData: resumeData,
                                               profileID: profileID,
                                               mode: mode)
            }
        }
    }

    func urlSession(_ session: URLSession,
                    downloadTask: URLSessionDownloadTask,
                    didWriteData bytesWritten: Int64,
                    totalBytesWritten: Int64,
                    totalBytesExpectedToWrite: Int64) {
        let expectedBytes = totalBytesExpectedToWrite > 0 ? totalBytesExpectedToWrite : estimatedRestoreImageSizeInBytes
        let percentage = min((Double(totalBytesWritten) / Double(expectedBytes)) * 100, 99)
        DispatchQueue.main.async { [weak self] in
            self?.updateRestoreImageDownloadProgress(percentage, downloadedBytes: totalBytesWritten, expectedBytes: totalBytesExpectedToWrite)
        }
    }

    func urlSession(_ session: URLSession,
                    downloadTask: URLSessionDownloadTask,
                    didFinishDownloadingTo location: URL) {
        do {
            let destinationURL = try moveRestoreImageFromTemporaryLocation(location)
            DispatchQueue.main.async { [weak self] in
                self?.finishRestoreImageDownload(at: destinationURL)
            }
        } catch {
            DispatchQueue.main.async { [weak self] in
                self?.showInstallationFailure(error.localizedDescription)
            }
        }
    }

    func urlSession(_ session: URLSession,
                    task: URLSessionTask,
                    didCompleteWithError error: Error?) {
        guard let error else {
            return
        }

        DispatchQueue.main.async { [weak self] in
            guard let self else {
                return
            }

            if self.isSwitchingRestoreImageDownloadSession,
               (error as NSError).code == NSURLErrorCancelled {
                return
            }

            if (error as NSError).code == NSURLErrorCancelled, !self.isInstallationInProgress {
                return
            }

            self.restoreImageDownloadSession?.finishTasksAndInvalidate()
            self.restoreImageDownloadSession = nil
            self.restoreImageDownloadTask = nil
            self.restoreImageDownloadMode = nil
            self.restoreImageDownloadProfileID = nil
            self.showInstallationFailure(MachineConfigurationHelper.localized("Download failed with error: %@", error.localizedDescription))
        }
    }

    private func updateRestoreImageDownloadProgress(_ percentage: Double, downloadedBytes: Int64, expectedBytes: Int64) {
        setupViewModel?.isProgressVisible = true
        setupViewModel?.progress = min(percentage * 0.5, 50)

        let downloadedGiB = Double(downloadedBytes) / 1024 / 1024 / 1024
        let detail: String
        if expectedBytes > 0 {
            detail = MachineConfigurationHelper.localized("%d%% downloaded (%.1f GB)", Int(percentage), downloadedGiB)
        } else {
            detail = MachineConfigurationHelper.localized("%.1f GB downloaded", downloadedGiB)
        }

        setupViewModel?.detail = detail
        updateSelectedProfile(status: .installing,
                              detail: detail,
                              progress: min(percentage * 0.5, 50))
    }

    private func moveRestoreImageFromTemporaryLocation(_ location: URL) throws -> URL {
        let destinationURL = restoreImageURL
        let destinationDirectoryURL = destinationURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: destinationDirectoryURL, withIntermediateDirectories: true)

        if FileManager.default.fileExists(atPath: destinationURL.path) {
            try FileManager.default.removeItem(at: destinationURL)
        }

        try FileManager.default.moveItem(at: location, to: destinationURL)
        return destinationURL
    }

    private func finishRestoreImageDownload(at downloadedRestoreImageURL: URL) {
        if let restoreImageDownloadProfileID,
           selectedProfileID != restoreImageDownloadProfileID,
           let profile = virtualMachineProfiles.first(where: { $0.id == restoreImageDownloadProfileID }) {
            selectProfile(profile)
        }

        restoreImageDownloadSession?.finishTasksAndInvalidate()
        restoreImageDownloadSession = nil
        restoreImageDownloadTask = nil
        restoreImageDownloadMode = nil
        restoreImageDownloadProfileID = nil
        installMacOS(from: downloadedRestoreImageURL)
    }

    private func installMacOS(from ipswURL: URL) {
        setupViewModel?.status = MachineConfigurationHelper.localized("Preparing installer...")
        setupViewModel?.detail = MachineConfigurationHelper.localized("Loading the downloaded macOS restore image.")

        VZMacOSRestoreImage.load(from: ipswURL) { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case let .failure(error):
                    self?.showInstallationFailure(error.localizedDescription)

                case let .success(restoreImage):
                    self?.installMacOS(restoreImage: restoreImage)
                }
            }
        }
    }

    private func installMacOS(restoreImage: VZMacOSRestoreImage) {
        guard let macOSConfiguration = restoreImage.mostFeaturefulSupportedConfiguration else {
            showInstallationFailure(MachineConfigurationHelper.localized("No supported macOS configuration is available for this Mac."))
            return
        }

        guard macOSConfiguration.hardwareModel.isSupported else {
            showInstallationFailure(MachineConfigurationHelper.localized("The macOS configuration is not supported on this Mac."))
            return
        }

        do {
            let virtualMachineConfiguration = try createInstallationVirtualMachineConfiguration(macOSConfiguration: macOSConfiguration)
            let installVirtualMachine = VZVirtualMachine(configuration: virtualMachineConfiguration)
            let installResponder = MacOSVirtualMachineDelegate()
            installVirtualMachine.delegate = installResponder
            installationVirtualMachine = installVirtualMachine
            installationVirtualMachineResponder = installResponder

            startMacOSInstallation(on: installVirtualMachine, restoreImageURL: restoreImage.url)
        } catch {
            showInstallationFailure(error.localizedDescription)
        }
    }

    private func createInstallationVirtualMachineConfiguration(macOSConfiguration: VZMacOSConfigurationRequirements) throws -> VZVirtualMachineConfiguration {
        let virtualMachineConfiguration = VZVirtualMachineConfiguration()

        virtualMachineConfiguration.platform = try createInstallationPlatformConfiguration(macOSConfiguration: macOSConfiguration)
        virtualMachineConfiguration.cpuCount = MachineConfigurationHelper.computeCPUCount()
        if virtualMachineConfiguration.cpuCount < macOSConfiguration.minimumSupportedCPUCount {
            throw NSError(domain: "VirtualiseOS", code: 2, userInfo: [
                NSLocalizedDescriptionKey: MachineConfigurationHelper.localized("This Mac does not have enough CPU cores for the selected macOS restore image.")
            ])
        }

        virtualMachineConfiguration.memorySize = MachineConfigurationHelper.computeMemorySize()
        if virtualMachineConfiguration.memorySize < macOSConfiguration.minimumSupportedMemorySize {
            throw NSError(domain: "VirtualiseOS", code: 3, userInfo: [
                NSLocalizedDescriptionKey: MachineConfigurationHelper.localized("This Mac does not have enough memory for the selected macOS restore image.")
            ])
        }

        try createDiskImage()

        virtualMachineConfiguration.bootLoader = MachineConfigurationHelper.createBootLoader()
        virtualMachineConfiguration.audioDevices = [MachineConfigurationHelper.createSoundDeviceConfiguration()]
        virtualMachineConfiguration.graphicsDevices = [MachineConfigurationHelper.createGraphicsDeviceConfiguration()]
        virtualMachineConfiguration.networkDevices = [MachineConfigurationHelper.createNetworkDeviceConfiguration()]
        virtualMachineConfiguration.storageDevices = [MachineConfigurationHelper.createBlockDeviceConfiguration()]
        if let directorySharingDevice = MachineConfigurationHelper.createDirectorySharingDeviceConfiguration() {
            virtualMachineConfiguration.directorySharingDevices = [directorySharingDevice]
        }
        virtualMachineConfiguration.pointingDevices = [MachineConfigurationHelper.createPointingDeviceConfiguration()]
        virtualMachineConfiguration.keyboards = [MachineConfigurationHelper.createKeyboardConfiguration()]

        try virtualMachineConfiguration.validate()

        if #available(macOS 14.0, *) {
            try virtualMachineConfiguration.validateSaveRestoreSupport()
        }

        return virtualMachineConfiguration
    }

    private func createInstallationPlatformConfiguration(macOSConfiguration: VZMacOSConfigurationRequirements) throws -> VZMacPlatformConfiguration {
        let macPlatformConfiguration = VZMacPlatformConfiguration()
        let auxiliaryStorage = try VZMacAuxiliaryStorage(creatingStorageAt: auxiliaryStorageURL,
                                                         hardwareModel: macOSConfiguration.hardwareModel,
                                                         options: [])
        let machineIdentifier = VZMacMachineIdentifier()

        macPlatformConfiguration.auxiliaryStorage = auxiliaryStorage
        macPlatformConfiguration.hardwareModel = macOSConfiguration.hardwareModel
        macPlatformConfiguration.machineIdentifier = machineIdentifier

        try macOSConfiguration.hardwareModel.dataRepresentation.write(to: hardwareModelURL)
        try machineIdentifier.dataRepresentation.write(to: machineIdentifierURL)

        return macPlatformConfiguration
    }

    private func createDiskImage() throws {
        let diskImageSizeInGiB = UInt64(selectedProfile?.diskSizeInGiB ?? Int(defaultDiskImageSizeInGiB))
        let diskImageSizeInBytes = diskImageSizeInGiB * 1024 * 1024 * 1024
        let diskFd = open(diskImageURL.path, O_RDWR | O_CREAT, S_IRUSR | S_IWUSR)

        guard diskFd != -1 else {
            throw NSError(domain: "VirtualiseOS", code: 4, userInfo: [
                NSLocalizedDescriptionKey: MachineConfigurationHelper.localized("Cannot create the virtual machine disk image.")
            ])
        }

        defer {
            close(diskFd)
        }

        guard ftruncate(diskFd, off_t(diskImageSizeInBytes)) == 0 else {
            throw NSError(domain: "VirtualiseOS", code: 5, userInfo: [
                NSLocalizedDescriptionKey: MachineConfigurationHelper.localized("Cannot resize the virtual machine disk image.")
            ])
        }
    }

    private func startMacOSInstallation(on virtualMachine: VZVirtualMachine, restoreImageURL: URL) {
        let installer = VZMacOSInstaller(virtualMachine: virtualMachine, restoringFromImageAt: restoreImageURL)
        macOSInstaller = installer

        setupViewModel?.status = MachineConfigurationHelper.localized("Installing macOS...")
        setupViewModel?.detail = MachineConfigurationHelper.localized("The virtual machine is being created.")
        setupViewModel?.progress = max(setupViewModel?.progress ?? 0, 50)

        installer.install { [weak self] result in
            DispatchQueue.main.async {
                guard let self, self.isInstallationInProgress else {
                    return
                }

                switch result {
                case let .failure(error):
                    self.showInstallationFailure(error.localizedDescription)

                case .success:
                    self.setupViewModel?.status = MachineConfigurationHelper.localized("Installation complete")
                    self.finishInstallationAndRefreshSetupState()
                }
            }
        }

        macOSInstallationObserver = installer.progress.observe(\.fractionCompleted, options: [.initial, .new]) { [weak self] progress, change in
            DispatchQueue.main.async {
                guard let self, self.isInstallationInProgress else {
                    return
                }

                let percentage = (change.newValue ?? progress.fractionCompleted) * 100
                self.setupViewModel?.isProgressVisible = true
                self.setupViewModel?.progress = 50 + min(percentage * 0.5, 50)
                let detail = MachineConfigurationHelper.localized("%d%% installed", Int(percentage))
                self.setupViewModel?.detail = detail
                self.updateSelectedProfile(status: .installing,
                                           detail: detail,
                                           progress: 50 + min(percentage * 0.5, 50))
            }
        }
    }

    private func startBundledInstallationTool() {
        do {
            try removeIncompleteVirtualMachineBundleIfNeeded()
            let helperURL = try installationToolURL()
            let process = Process()
            let outputPipe = Pipe()

            process.executableURL = helperURL
            process.standardOutput = outputPipe
            process.standardError = outputPipe

            outputPipe.fileHandleForReading.readabilityHandler = { [weak self] fileHandle in
                let data = fileHandle.availableData
                guard !data.isEmpty, let output = String(data: data, encoding: .utf8) else {
                    return
                }

                DispatchQueue.main.async {
                    self?.handleInstallationOutput(output)
                }
            }

            process.terminationHandler = { [weak self] process in
                outputPipe.fileHandleForReading.readabilityHandler = nil

                DispatchQueue.main.async {
                    self?.installationProcess = nil
                    self?.handleInstallationFinished(with: process.terminationStatus)
                }
            }

            installationProcess = process
            setupViewModel?.status = MachineConfigurationHelper.localized("Downloading macOS restore image...")
            setupViewModel?.detail = MachineConfigurationHelper.localized("This can take a while depending on network speed.")
            setupViewModel?.isActionHidden = true
            try process.run()
        } catch {
            showInstallationFailure(error.localizedDescription)
        }
    }

    private func removeIncompleteVirtualMachineBundleIfNeeded() throws {
        guard FileManager.default.fileExists(atPath: vmBundlePath), !isVirtualMachineInstalled else {
            return
        }

        try FileManager.default.removeItem(at: vmBundleURL)
    }

    private func installationToolURL() throws -> URL {
        let bundledHelperURL = Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/InstallationTool-Swift")
        if FileManager.default.isExecutableFile(atPath: bundledHelperURL.path) {
            return bundledHelperURL
        }

        let buildProductsHelperURL = Bundle.main.bundleURL
            .deletingLastPathComponent()
            .appendingPathComponent("InstallationTool-Swift")
        if FileManager.default.isExecutableFile(atPath: buildProductsHelperURL.path) {
            return buildProductsHelperURL
        }

        throw NSError(domain: "VirtualiseOS", code: 1, userInfo: [
            NSLocalizedDescriptionKey: MachineConfigurationHelper.localized("InstallationTool-Swift is missing from the app bundle.")
        ])
    }

    private func handleInstallationOutput(_ output: String) {
        guard isInstallationInProgress else {
            return
        }

        if output.contains("Restore image download progress") {
            setupViewModel?.status = MachineConfigurationHelper.localized("Downloading macOS restore image...")
            if let percentage = progressPercentage(from: output) {
                setupViewModel?.isProgressVisible = true
                setupViewModel?.progress = min(percentage * 0.5, 50)
                setupViewModel?.detail = MachineConfigurationHelper.localized("%d%% downloaded", Int(percentage))
            }
        } else if output.contains("Latest supported macOS restore image") {
            setupViewModel?.detail = MachineConfigurationHelper.localized("Found the latest supported macOS restore image.")
        } else if output.contains("Starting installation") {
            setupViewModel?.status = MachineConfigurationHelper.localized("Installing macOS...")
            setupViewModel?.detail = MachineConfigurationHelper.localized("The virtual machine is being created.")
            setupViewModel?.progress = max(setupViewModel?.progress ?? 0, 50)
        } else if output.contains("Installation progress") {
            setupViewModel?.status = MachineConfigurationHelper.localized("Installing macOS...")
            if let percentage = progressPercentage(from: output) {
                setupViewModel?.isProgressVisible = true
                setupViewModel?.progress = 50 + min(percentage * 0.5, 50)
                setupViewModel?.detail = MachineConfigurationHelper.localized("%d%% installed", Int(percentage))
            }
        } else if output.contains("Installation succeeded") {
            setupViewModel?.status = MachineConfigurationHelper.localized("Installation complete")
            setupViewModel?.detail = MachineConfigurationHelper.localized("Open the existing VM.bundle at the selected location.")
            setupViewModel?.progress = 100
        }
    }

    private func progressPercentage(from output: String) -> Double? {
        let numericCharacterSet = CharacterSet(charactersIn: "0123456789.")
        let tokens = output.components(separatedBy: numericCharacterSet.inverted)
        return tokens.compactMap(Double.init).last
    }

    private func handleInstallationFinished(with terminationStatus: Int32) {
        guard isInstallationInProgress else {
            return
        }

        guard terminationStatus == 0 else {
            showInstallationFailure(MachineConfigurationHelper.localized("The installation tool exited with status %d.", terminationStatus))
            return
        }

        finishInstallationAndRefreshSetupState()
    }

    private func finishInstallationAndRefreshSetupState() {
        isInstallationInProgress = false
        restoreImageDownloadObserver = nil
        restoreImageDownloadProfileID = nil
        restoreImageDownloadTask = nil
        restoreImageDownloadMode = nil
        macOSInstallationObserver = nil
        restoreImageDownloadSession?.finishTasksAndInvalidate()
        restoreImageDownloadSession = nil
        macOSInstaller = nil
        installationVirtualMachine = nil
        installationVirtualMachineResponder = nil
        setupViewModel?.progress = 100
        refreshAllProfileStatuses()
        if isVirtualMachineInstalled {
            updateSelectedProfile(status: .installed,
                                  detail: MachineConfigurationHelper.localized("Ready to start."),
                                  progress: 100)
        }
        updateSetupStateForCurrentVMLocation()

        if !isVirtualMachineInstalled {
            showInstallationFailure(missingVirtualMachineFilesDescription())
        }
    }

    private func showInstallationFailure(_ message: String) {
        isInstallationInProgress = false
        restoreImageDownloadObserver = nil
        restoreImageDownloadProfileID = nil
        restoreImageDownloadTask = nil
        restoreImageDownloadMode = nil
        macOSInstallationObserver = nil
        restoreImageDownloadSession?.finishTasksAndInvalidate()
        restoreImageDownloadSession = nil
        macOSInstaller = nil
        installationVirtualMachine = nil
        installationVirtualMachineResponder = nil
        setupViewModel?.isLaunchSpinnerVisible = false
        updateSelectedProfile(status: .failed, detail: message, progress: 0)
        setupViewModel?.status = MachineConfigurationHelper.localized("Installation failed")
        setupViewModel?.detail = message
        setupViewModel?.progress = 0
        setupViewModel?.isProgressVisible = false
        setupViewModel?.actionTitle = MachineConfigurationHelper.localized("Retry Download and Install")
        setupViewModel?.isActionHidden = false
        setupViewModel?.isActionEnabled = true
        setupViewModel?.areControlsEnabled = true
    }
#endif

    // MARK: Save the virtual machine when the app exits.

#if arch(arm64)
    @available(macOS 14.0, *)
    func saveVirtualMachine(completionHandler: @escaping () -> Void) {
        virtualMachine.saveMachineStateTo(url: saveFileURL, completionHandler: { (error) in
            guard error == nil else {
                MachineConfigurationHelper.showErrorAndExit(self.virtualMachineErrorMessage(prefixKey: "Virtual machine failed to save with %@", error: error!))
            }

            completionHandler()
        })
    }

    @available(macOS 14.0, *)
    func pauseAndSaveVirtualMachine(completionHandler: @escaping () -> Void) {
        virtualMachine.pause(completionHandler: { (result) in
            if case let .failure(error) = result {
                MachineConfigurationHelper.showErrorAndExit(self.virtualMachineErrorMessage(prefixKey: "Virtual machine failed to pause with %@", error: error))
            }

            self.saveVirtualMachine(completionHandler: completionHandler)
        })
    }
#endif

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
#if arch(arm64)
        if installationProcess != nil {
            installationProcess?.terminate()
            return .terminateNow
        }

        if #available(macOS 14.0, *) {
            if virtualMachine?.state == .running {
                pauseAndSaveVirtualMachine(completionHandler: { [weak self] in
                    self?.markSelectedProfileStoppedIfNeeded()
                    sender.reply(toApplicationShouldTerminate: true)
                })

                return .terminateLater
            }
        }
#endif

        markSelectedProfileStoppedIfNeeded()
        return .terminateNow
    }
}

#if arch(arm64)
extension Coordinator: URLSessionDownloadDelegate {}
#endif
