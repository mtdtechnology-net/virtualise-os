import Cocoa
import Foundation

extension Coordinator {
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
#if arch(arm64)
        selectedProfile?.status == .installing || isInstallationInProgress || restoreImageDownloadTask != nil || macOSInstaller != nil || installationProcess != nil
#else
        selectedProfile?.status == .installing || isInstallationInProgress || restoreImageDownloadTask != nil || installationProcess != nil
#endif
    }

    var canDeleteSelectedProfile: Bool {
        guard let selectedProfile else {
            return false
        }

        return selectedProfile.status != .running && selectedProfile.status != .starting && selectedProfile.status != .installing && !canCancelSelectedProfileInstallation
    }

    var canStopVirtualMachine: Bool {
#if arch(arm64)
        displayedVirtualMachine != nil || virtualMachine != nil || selectedProfile?.status == .running
#else
        false
#endif
    }

    func markSelectedProfileStoppedIfNeeded() {
        guard let selectedProfileIndex,
              virtualMachineProfiles[selectedProfileIndex].status == .running || virtualMachineProfiles[selectedProfileIndex].status == .starting else {
            return
        }

        virtualMachineProfiles[selectedProfileIndex].status = .stopped
        virtualMachineProfiles[selectedProfileIndex].statusDetail = "Virtual machine is stopped.".localized
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

    // swiftlint:disable:next function_parameter_count
    func createProfile(name: String,
                       vmBundleURL: URL,
                       sharedFolderURL: URL?,
                       restoreImageURL: URL?,
                       osVersion: String?,
                       memorySizeInGiB: Int,
                       diskSizeInGiB: Int,
                       portForwarding: PortForwardingConfiguration = .disabled) {
        do {
            let profileName = name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? nextGeneratedProfileName()
                : name.trimmingCharacters(in: .whitespacesAndNewlines)
            let normalizedURL = vmBundleURL.pathExtension == "bundle"
                ? Self.normalizedVMLocation(vmBundleURL, profileName: profileName)
                : uniqueVMLocation(in: vmBundleURL, profileName: profileName)

            if virtualMachineProfiles.contains(where: { $0.vmBundleURL.standardizedFileURL.path == normalizedURL.standardizedFileURL.path }) {
                throw NSError(domain: "VirtualiseOS", code: 22, userInfo: [
                    NSLocalizedDescriptionKey: "A virtual machine already uses this bundle location.".localized
                ])
            }

            if !FileManager.default.fileExists(atPath: normalizedURL.path) {
                try FileManager.default.createDirectory(at: normalizedURL, withIntermediateDirectories: true)
            }
            let vmBookmarkData = try normalizedURL.bookmarkData(options: URL.BookmarkCreationOptions.withSecurityScope,
                                                                includingResourceValuesForKeys: nil,
                                                                relativeTo: nil)
            let sharedBookmarkData = try sharedFolderURL?.bookmarkData(options: URL.BookmarkCreationOptions.withSecurityScope,
                                                                       includingResourceValuesForKeys: nil,
                                                                       relativeTo: nil)
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
                                                statusDetail: "Download and install macOS to create this VM.".localized,
                                                portForwarding: portForwarding)
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
            showInformationAlert("Stop or cancel this virtual machine before deleting it.".localized)
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

    func confirmDelete(_ profile: MachineProfile) -> Bool {
        let alert = NSAlert()
        alert.messageText = "Delete \"%@\"?".localized(profile.name)
        alert.informativeText = "This removes the VM.bundle from disk and deletes the virtual machine record from the database.".localized
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Delete".localized)
        alert.addButton(withTitle: "Cancel".localized)
        return alert.runModal() == .alertFirstButtonReturn
    }

    func deleteBundle(for profile: MachineProfile) throws {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: profile.vmBundleURL.path) else {
            return
        }

        try fileManager.removeItem(at: profile.vmBundleURL)
    }

    func nextGeneratedProfileName() -> String {
        let baseName = "Virtual Machine".localized
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

        let requestedDiskSizeInGiB = max(32, diskSizeInGiB)
        let currentProfile = virtualMachineProfiles[selectedProfileIndex]
        guard requestedDiskSizeInGiB != currentProfile.diskSizeInGiB else {
            return
        }

        if currentProfile.status == .running || currentProfile.status == .starting || currentProfile.status == .installing {
            showInformationAlert("Stop the virtual machine before changing its disk size.".localized)
            return
        }

        if currentProfile.isInstalledOnDisk {
            guard requestedDiskSizeInGiB > currentProfile.diskSizeInGiB else {
                showInformationAlert("VirtualiseOS can increase a virtual machine disk, but it cannot safely shrink an installed macOS disk.".localized)
                return
            }

            do {
                try resizeDiskImage(for: currentProfile, to: requestedDiskSizeInGiB)
                virtualMachineProfiles[selectedProfileIndex].diskSizeInGiB = requestedDiskSizeInGiB
                saveProfiles()
                showGuestDiskExpansionInstructions(newSizeInGiB: requestedDiskSizeInGiB)
            } catch {
                showInformationAlert(error.localizedDescription)
            }
            return
        }

        virtualMachineProfiles[selectedProfileIndex].diskSizeInGiB = requestedDiskSizeInGiB
        saveProfiles()
    }

    func updateSelectedProfilePortForwarding(_ portForwarding: PortForwardingConfiguration) {
        guard let selectedProfileIndex else {
            return
        }

        virtualMachineProfiles[selectedProfileIndex].portForwarding = sanitized(portForwarding)
        saveProfiles()
    }

    func sanitized(_ portForwarding: PortForwardingConfiguration) -> PortForwardingConfiguration {
        PortForwardingConfiguration(isEnabled: portForwarding.isEnabled,
                                    hostPort: min(max(portForwarding.hostPort, 1), 65535),
                                    guestAddress: portForwarding.guestAddress.trimmingCharacters(in: .whitespacesAndNewlines),
                                    guestPort: min(max(portForwarding.guestPort, 1), 65535))
    }

    func resizeDiskImage(for profile: MachineProfile, to diskSizeInGiB: Int) throws {
        let diskImageSizeInBytes = UInt64(diskSizeInGiB) * 1024 * 1024 * 1024
        let diskFd = open(profile.diskImageURL.path, O_RDWR)

        guard diskFd != -1 else {
            throw NSError(domain: "VirtualiseOS", code: 20, userInfo: [
                NSLocalizedDescriptionKey: "Cannot open the virtual machine disk image.".localized
            ])
        }

        defer {
            close(diskFd)
        }

        guard ftruncate(diskFd, off_t(diskImageSizeInBytes)) == 0 else {
            throw NSError(domain: "VirtualiseOS", code: 21, userInfo: [
                NSLocalizedDescriptionKey: "Cannot resize the virtual machine disk image.".localized
            ])
        }
    }

    func showGuestDiskExpansionInstructions(newSizeInGiB: Int) {
        showInformationAlert("The VM disk image was increased to %d GB. To use the extra space inside macOS, start the virtual machine, open Disk Utility in the guest, select the internal APFS container, and expand it to fill the newly available space. You can also use diskutil inside the guest if you prefer Terminal.".localized(newSizeInGiB))
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

    func resolveSecurityScopedURL(from bookmarkData: Data) -> URL? {
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

    func activateSelectedProfile() {
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
    func showInstallationScreen() {}

    func updateSetupStateForCurrentVMLocation() {}

    func showInformationAlert(_ message: String) {
        NSLog(message)
    }
#endif
}
