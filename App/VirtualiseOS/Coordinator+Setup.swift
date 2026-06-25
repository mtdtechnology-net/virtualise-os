import Cocoa
import Foundation
#if arch(arm64)
import Virtualization
#endif

extension Coordinator {
#if arch(arm64)
    func showInstallationScreen() {
        let model = SetupViewModel(status: "Virtual machine is not installed".localized,
                                   detail: "Download and install the latest macOS version supported by this Mac.".localized,
                                   actionTitle: "Download and Install Latest macOS".localized,
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

    func vmLocationDescription() -> String {
        return "VM bundle path: %@".localized(vmBundleURL.path)
    }

    func chooseVMLocation() {
        guard virtualMachine == nil else {
            showInformationAlert("Changing the VM location requires quitting the running virtual machine first.".localized)
            return
        }

        let openPanel = NSOpenPanel()
        openPanel.canChooseFiles = true
        openPanel.canChooseDirectories = true
        openPanel.allowsMultipleSelection = false
        openPanel.canCreateDirectories = true
        openPanel.treatsFilePackagesAsDirectories = false
        openPanel.prompt = "Choose".localized
        openPanel.message = "Choose VM.bundle or the folder where VirtualiseOS should store it.".localized

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

    func normalizedSelectedVMLocation(_ url: URL) -> URL {
        if url.lastPathComponent == "VM.bundle" || url.pathExtension == "bundle" {
            return url
        }

        return url.appendingPathComponent("VM.bundle", isDirectory: true)
    }

    func updateSetupStateForCurrentVMLocation() {
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
            setupViewModel.status = "Virtual machine is ready".localized
            setupViewModel.detail = "Open the existing VM.bundle at the selected location.".localized
            setupViewModel.actionTitle = "Open VM".localized
        } else if FileManager.default.fileExists(atPath: vmBundlePath) {
            setupViewModel.status = "VM.bundle was found but is incomplete".localized
            setupViewModel.detail = missingVirtualMachineFilesDescription()
            setupViewModel.actionTitle = "Download and Install Latest macOS".localized
        } else {
            setupViewModel.status = "Virtual machine is not installed".localized
            setupViewModel.detail = "Download and install the latest macOS version supported by this Mac.".localized
            setupViewModel.actionTitle = "Download and Install Latest macOS".localized
        }
    }

    func missingVirtualMachineFilesDescription() -> String {
        let requiredFiles = [
            auxiliaryStorageURL,
            diskImageURL,
            hardwareModelURL,
            machineIdentifierURL,
        ]
        let missingNames = requiredFiles
            .filter { !FileManager.default.fileExists(atPath: $0.path) }
            .map(\.lastPathComponent)

        guard !missingNames.isEmpty else {
            return "Open the existing VM.bundle at the selected location.".localized
        }

        return "Missing VM files: %@".localized(missingNames.joined(separator: ", "))
    }

    func showInformationAlert(_ message: String) {
        let alert = NSAlert()
        alert.messageText = "VirtualiseOS".localized
        alert.informativeText = message
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK".localized)
        alert.runModal()
    }

    func sharedFolderDescription() -> String {
        guard let url = selectedSharedFolderURL() else {
            return "No shared folder selected".localized
        }

        return "Shared in the guest at /Volumes/My Shared Files: %@".localized(url.path)
    }

    func selectedSharedFolderURL() -> URL? {
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
        openPanel.prompt = "Choose".localized
        openPanel.message = "Choose a host folder to share with the macOS virtual machine.".localized

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

    func updateRunningSharedFolderIfPossible() {
        guard let virtualMachine,
              let directorySharingDevice = virtualMachine.directorySharingDevices.first as? VZVirtioFileSystemDevice,
              let sharingConfiguration = MachineConfigurationHelper.createDirectorySharingDeviceConfiguration() else {
            return
        }

        directorySharingDevice.share = sharingConfiguration.share
    }

    func selectedMemorySizeInGiB() -> Int {
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
            return "macOS %@".localized(version)
        }

        return "macOS %@ (%@)".localized(version, buildVersion)
    }
#endif
}
