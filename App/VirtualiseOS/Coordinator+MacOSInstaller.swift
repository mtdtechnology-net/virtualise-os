import Cocoa
import Foundation
#if arch(arm64)
import Virtualization
#endif

extension Coordinator {
#if arch(arm64)
    func installMacOS(from ipswURL: URL) {
        setupViewModel?.status = "Preparing installer...".localized
        setupViewModel?.detail = "Loading the downloaded macOS restore image.".localized

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

    func installMacOS(restoreImage: VZMacOSRestoreImage) {
        guard let macOSConfiguration = restoreImage.mostFeaturefulSupportedConfiguration else {
            showInstallationFailure("No supported macOS configuration is available for this Mac.".localized)
            return
        }

        guard macOSConfiguration.hardwareModel.isSupported else {
            showInstallationFailure("The macOS configuration is not supported on this Mac.".localized)
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

    func createInstallationVirtualMachineConfiguration(macOSConfiguration: VZMacOSConfigurationRequirements) throws -> VZVirtualMachineConfiguration {
        let virtualMachineConfiguration = VZVirtualMachineConfiguration()

        virtualMachineConfiguration.platform = try createInstallationPlatformConfiguration(macOSConfiguration: macOSConfiguration)
        virtualMachineConfiguration.cpuCount = MachineConfigurationHelper.computeCPUCount()
        if virtualMachineConfiguration.cpuCount < macOSConfiguration.minimumSupportedCPUCount {
            throw NSError(domain: "VirtualiseOS", code: 2, userInfo: [
                NSLocalizedDescriptionKey: "This Mac does not have enough CPU cores for the selected macOS restore image.".localized
            ])
        }

        virtualMachineConfiguration.memorySize = MachineConfigurationHelper.computeMemorySize()
        if virtualMachineConfiguration.memorySize < macOSConfiguration.minimumSupportedMemorySize {
            throw NSError(domain: "VirtualiseOS", code: 3, userInfo: [
                NSLocalizedDescriptionKey: "This Mac does not have enough memory for the selected macOS restore image.".localized
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

    func createInstallationPlatformConfiguration(macOSConfiguration: VZMacOSConfigurationRequirements) throws -> VZMacPlatformConfiguration {
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

    func createDiskImage() throws {
        let diskImageSizeInGiB = UInt64(selectedProfile?.diskSizeInGiB ?? Int(defaultDiskImageSizeInGiB))
        let diskImageSizeInBytes = diskImageSizeInGiB * 1024 * 1024 * 1024
        let diskFd = open(diskImageURL.path, O_RDWR | O_CREAT, S_IRUSR | S_IWUSR)

        guard diskFd != -1 else {
            throw NSError(domain: "VirtualiseOS", code: 4, userInfo: [
                NSLocalizedDescriptionKey: "Cannot create the virtual machine disk image.".localized
            ])
        }

        defer {
            close(diskFd)
        }

        guard ftruncate(diskFd, off_t(diskImageSizeInBytes)) == 0 else {
            throw NSError(domain: "VirtualiseOS", code: 5, userInfo: [
                NSLocalizedDescriptionKey: "Cannot resize the virtual machine disk image.".localized
            ])
        }
    }

    func startMacOSInstallation(on virtualMachine: VZVirtualMachine, restoreImageURL: URL) {
        let installer = VZMacOSInstaller(virtualMachine: virtualMachine, restoringFromImageAt: restoreImageURL)
        macOSInstaller = installer

        setupViewModel?.status = "Installing macOS...".localized
        setupViewModel?.detail = "The virtual machine is being created.".localized
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
                    self.setupViewModel?.status = "Installation complete".localized
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
                let detail = "%d%% installed".localized(Int(percentage))
                self.setupViewModel?.detail = detail
                self.updateSelectedProfile(status: .installing,
                                           detail: detail,
                                           progress: 50 + min(percentage * 0.5, 50))
            }
        }
    }

    func startBundledInstallationTool() {
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
            setupViewModel?.status = "Downloading macOS restore image...".localized
            setupViewModel?.detail = "This can take a while depending on network speed.".localized
            setupViewModel?.isActionHidden = true
            try process.run()
        } catch {
            showInstallationFailure(error.localizedDescription)
        }
    }

    func removeIncompleteVirtualMachineBundleIfNeeded() throws {
        guard FileManager.default.fileExists(atPath: vmBundlePath), !isVirtualMachineInstalled else {
            return
        }

        try FileManager.default.removeItem(at: vmBundleURL)
    }

    func installationToolURL() throws -> URL {
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
            NSLocalizedDescriptionKey: "InstallationTool-Swift is missing from the app bundle.".localized
        ])
    }

    func handleInstallationOutput(_ output: String) {
        guard isInstallationInProgress else {
            return
        }

        if output.contains("Restore image download progress") {
            setupViewModel?.status = "Downloading macOS restore image...".localized
            if let percentage = progressPercentage(from: output) {
                setupViewModel?.isProgressVisible = true
                setupViewModel?.progress = min(percentage * 0.5, 50)
                setupViewModel?.detail = "%d%% downloaded".localized(Int(percentage))
            }
        } else if output.contains("Latest supported macOS restore image") {
            setupViewModel?.detail = "Found the latest supported macOS restore image.".localized
        } else if output.contains("Starting installation") {
            setupViewModel?.status = "Installing macOS...".localized
            setupViewModel?.detail = "The virtual machine is being created.".localized
            setupViewModel?.progress = max(setupViewModel?.progress ?? 0, 50)
        } else if output.contains("Installation progress") {
            setupViewModel?.status = "Installing macOS...".localized
            if let percentage = progressPercentage(from: output) {
                setupViewModel?.isProgressVisible = true
                setupViewModel?.progress = 50 + min(percentage * 0.5, 50)
                setupViewModel?.detail = "%d%% installed".localized(Int(percentage))
            }
        } else if output.contains("Installation succeeded") {
            setupViewModel?.status = "Installation complete".localized
            setupViewModel?.detail = "Open the existing VM.bundle at the selected location.".localized
            setupViewModel?.progress = 100
        }
    }

    func progressPercentage(from output: String) -> Double? {
        let numericCharacterSet = CharacterSet(charactersIn: "0123456789.")
        let tokens = output.components(separatedBy: numericCharacterSet.inverted)
        return tokens.compactMap(Double.init).last
    }

    func handleInstallationFinished(with terminationStatus: Int32) {
        guard isInstallationInProgress else {
            return
        }

        guard terminationStatus == 0 else {
            showInstallationFailure("The installation tool exited with status %d.".localized(terminationStatus))
            return
        }

        finishInstallationAndRefreshSetupState()
    }

    func finishInstallationAndRefreshSetupState() {
        isInstallationInProgress = false
        restoreImageDownloadObserver = nil
        restoreImageDownloadProfileID = nil
        restoreImageDownloadTask = nil
        restoreImageDownloadURL = nil
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
                                  detail: "Ready to start.".localized,
                                  progress: 100)
        }
        updateSetupStateForCurrentVMLocation()

        if !isVirtualMachineInstalled {
            showInstallationFailure(missingVirtualMachineFilesDescription())
        }
    }

    func showInstallationFailure(_ message: String) {
        isInstallationInProgress = false
        restoreImageDownloadObserver = nil
        restoreImageDownloadProfileID = nil
        restoreImageDownloadTask = nil
        restoreImageDownloadURL = nil
        restoreImageDownloadMode = nil
        macOSInstallationObserver = nil
        restoreImageDownloadSession?.finishTasksAndInvalidate()
        restoreImageDownloadSession = nil
        macOSInstaller = nil
        installationVirtualMachine = nil
        installationVirtualMachineResponder = nil
        setupViewModel?.isLaunchSpinnerVisible = false
        updateSelectedProfile(status: .failed, detail: message, progress: 0)
        setupViewModel?.status = "Installation failed".localized
        setupViewModel?.detail = message
        setupViewModel?.progress = 0
        setupViewModel?.isProgressVisible = false
        setupViewModel?.actionTitle = "Retry Download and Install".localized
        setupViewModel?.isActionHidden = false
        setupViewModel?.isActionEnabled = true
        setupViewModel?.areControlsEnabled = true
    }
#endif
}
