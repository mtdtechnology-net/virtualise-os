import Cocoa
import Foundation
#if arch(arm64)
import Virtualization
#endif

extension Coordinator {
    // MARK: Create the Mac platform configuration.

#if arch(arm64)
    func createMacPlaform() throws -> VZMacPlatformConfiguration {
        let macPlatform = VZMacPlatformConfiguration()

        let auxiliaryStorage = VZMacAuxiliaryStorage(contentsOf: auxiliaryStorageURL)
        macPlatform.auxiliaryStorage = auxiliaryStorage

        if !FileManager.default.fileExists(atPath: vmBundlePath) {
            throw virtualMachineSetupError("Missing Virtual Machine Bundle at %@. Run InstallationTool first to create it.".localized(vmBundlePath))
        }

        // Retrieve the hardware model and save this value to disk during installation.
        guard let hardwareModelData = try? Data(contentsOf: hardwareModelURL) else {
            throw virtualMachineSetupError("Failed to retrieve hardware model data.".localized)
        }

        guard let hardwareModel = VZMacHardwareModel(dataRepresentation: hardwareModelData) else {
            throw virtualMachineSetupError("Failed to create hardware model.".localized)
        }

        if !hardwareModel.isSupported {
            throw virtualMachineSetupError("The hardware model isn't supported on the current host".localized)
        }
        macPlatform.hardwareModel = hardwareModel

        // Retrieve the machine identifier and save this value to disk during installation.
        guard let machineIdentifierData = try? Data(contentsOf: machineIdentifierURL) else {
            throw virtualMachineSetupError("Failed to retrieve machine identifier data.".localized)
        }

        guard let machineIdentifier = VZMacMachineIdentifier(dataRepresentation: machineIdentifierData) else {
            throw virtualMachineSetupError("Failed to create machine identifier.".localized)
        }
        macPlatform.machineIdentifier = machineIdentifier

        return macPlatform
    }

    // MARK: Create the virtual machine configuration and instantiate the virtual machine.

    func createVirtualMachine() throws {
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

    func virtualMachineSetupError(_ message: String) -> NSError {
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

    func virtualMachineErrorMessage(prefixKey: String, error: Error) -> String {
        let nsError = error as NSError
        let errorDescription = "\(error)"

        if errorDescription.contains("Failed to lock auxiliary storage")
            || nsError.localizedDescription.contains("Failed to lock auxiliary storage") {
            return "The virtual machine is already in use. Quit any other running copy of VirtualiseOS or wait for the previous VM process to finish, then start the app again.".localized
        }

        return prefixKey.localized(errorDescription)
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

    func prepareVirtualMachineIfNeeded() {
        guard !didPrepareVirtualMachine else {
            return
        }

        didPrepareVirtualMachine = true
        prepareVirtualMachine()
    }

    func prepareVirtualMachine() {
        activateSelectedProfile()
        refreshAllProfileStatuses()
        showInstallationScreen()
    }

    func applicationDidBecomeActive() {
        refreshSetupStateIfNeeded()
    }

    func applicationDidResignActive() {}

    func refreshSetupStateIfNeeded() {
        guard virtualMachine == nil,
              installationProcess == nil,
              !isInstallationInProgress,
              setupViewModel != nil else {
            return
        }

        updateSetupStateForCurrentVMLocation()
    }

    var isVirtualMachineInstalled: Bool {
        let fileManager = FileManager.default
        let requiredPaths = [
            vmBundlePath,
            auxiliaryStorageURL.path,
            diskImageURL.path,
            hardwareModelURL.path,
            machineIdentifierURL.path,
        ]

        return requiredPaths.allSatisfy { fileManager.fileExists(atPath: $0) }
    }

    func launchVirtualMachine() {
        showVirtualMachineStartingState()

        DispatchQueue.main.async { [weak self] in
            self?.startVirtualMachineLaunch()
        }
    }

    func startVirtualMachineLaunch() {
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

    func startOrRestoreVirtualMachine() {
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

    func presentRunningVirtualMachine() {
        setupViewModel?.isLaunchSpinnerVisible = false
        updateSelectedProfile(status: .running,
                              detail: "Virtual machine is running.".localized,
                              progress: 100)
        startPortForwardingIfNeeded()
        isVirtualMachineVisible = true
        virtualMachineWindowRequest += 1
    }

    func startPortForwardingIfNeeded() {
        portForwarder?.stop()
        portForwarder = nil

        guard let selectedProfile,
              selectedProfile.portForwarding.isEnabled else {
            return
        }

        do {
            let forwarder = PortForwarder(configuration: sanitized(selectedProfile.portForwarding))
            try forwarder.start()
            portForwarder = forwarder
        } catch {
            showInformationAlert(error.localizedDescription)
        }
    }

    func showVirtualMachineStartingState() {
        guard let setupViewModel else {
            return
        }

        updateSelectedProfile(status: .starting,
                              detail: "Opening the selected VM.bundle.".localized,
                              progress: 100)
        setupViewModel.status = "Starting virtual machine...".localized
        setupViewModel.detail = "VirtualiseOS is validating the VM configuration and opening the selected VM.bundle.".localized
        setupViewModel.actionTitle = "Starting...".localized
        setupViewModel.isActionEnabled = false
        setupViewModel.areControlsEnabled = false
        setupViewModel.progress = 0
        setupViewModel.isProgressVisible = false
        setupViewModel.isLaunchSpinnerVisible = true
    }

    func handleVirtualMachineLaunchFailure(_ message: String) {
        updateSelectedProfile(status: .stopped,
                              detail: "Virtual machine is stopped.".localized,
                              progress: 100)
        portForwarder?.stop()
        portForwarder = nil
        displayedVirtualMachine = nil
        isVirtualMachineVisible = false
        virtualMachine = nil
        virtualMachineResponder = nil
        showInstallationScreen()
        updateSelectedProfile(status: .failed, detail: message, progress: 0)
        setupViewModel?.status = "Virtual machine failed to start".localized
        setupViewModel?.detail = message
        setupViewModel?.progress = 0
        setupViewModel?.isProgressVisible = false
        setupViewModel?.isLaunchSpinnerVisible = false
        setupViewModel?.actionTitle = "Retry Open VM".localized
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
            showInformationAlert("The virtual machine cannot be stopped while it is changing state. Try again in a moment.".localized)
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

    func returnToSettingsScreen(markAsStopped: Bool = false) {
        if markAsStopped {
            markSelectedProfileStoppedIfNeeded()
            updateSelectedProfile(status: .stopped,
                                  detail: "Virtual machine is stopped.".localized,
                                  progress: 100)
        }
        displayedVirtualMachine = nil
        isVirtualMachineVisible = false
        virtualMachine = nil
        virtualMachineResponder = nil
        showInstallationScreen()
        updateSetupStateForCurrentVMLocation()
    }
}
