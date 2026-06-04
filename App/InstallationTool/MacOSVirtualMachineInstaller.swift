//
//  MacOSVirtualMachineInstaller.swift
//  VirtualiseOS
//
//  Created by Daniel Mandea on 15.05.2025.
//  Copyright © 2026 M.T.D.Technology SRL. All rights reserved.
//

import Virtualization

#if arch(arm64)

class MacOSVirtualMachineInstaller: NSObject {
    static let defaultDiskImageSizeInGiB: UInt64 = 128

    private static let bytesPerGiB: UInt64 = 1024 * 1024 * 1024

    private var installationObserver: NSKeyValueObservation?
    private var virtualMachine: VZVirtualMachine!
    private var virtualMachineResponder: MacOSVirtualMachineDelegate?
    private let diskImageSizeInGiB: UInt64
    private let diskImageSizeInBytes: UInt64

    init(diskImageSizeInGiB: UInt64 = MacOSVirtualMachineInstaller.defaultDiskImageSizeInGiB) {
        guard diskImageSizeInGiB > 0,
              diskImageSizeInGiB <= UInt64(Int64.max) / MacOSVirtualMachineInstaller.bytesPerGiB else {
            MachineConfigurationHelper.showErrorAndExit("The disk image size must be a positive whole number of GiB.".localized)
        }

        self.diskImageSizeInGiB = diskImageSizeInGiB
        self.diskImageSizeInBytes = diskImageSizeInGiB * MacOSVirtualMachineInstaller.bytesPerGiB
    }

    // Create a bundle on the user's Home directory to store any artifacts
    // that the installation produces.
    public func setUpVirtualMachineArtifacts() {
        createVMBundle()
    }

    // MARK: Install macOS onto the virtual machine from IPSW.

    public func installMacOS(ipswURL: URL, completionHandler: (() -> Void)? = nil) {
        NSLog("Attempting to install from IPSW at \(ipswURL).")
        VZMacOSRestoreImage.load(from: ipswURL, completionHandler: { [self](result: Result<VZMacOSRestoreImage, Error>) in
            switch result {
                case let .failure(error):
                    MachineConfigurationHelper.showErrorAndExit(error.localizedDescription)

                case let .success(restoreImage):
                    installMacOS(restoreImage: restoreImage, completionHandler: completionHandler)
            }
        })
    }

    // MARK: - Internal helper functions.

    private func installMacOS(restoreImage: VZMacOSRestoreImage, completionHandler: (() -> Void)?) {
        guard let macOSConfiguration = restoreImage.mostFeaturefulSupportedConfiguration else {
            MachineConfigurationHelper.showErrorAndExit("No supported configuration available.".localized)
        }

        if !macOSConfiguration.hardwareModel.isSupported {
            MachineConfigurationHelper.showErrorAndExit("macOSConfiguration configuration isn't supported on the current host.".localized)
        }

        DispatchQueue.main.async { [self] in
            setupVirtualMachine(macOSConfiguration: macOSConfiguration)
            startInstallation(restoreImageURL: restoreImage.url, completionHandler: completionHandler)
        }
    }

    // MARK: Create the Mac platform configuration.

    private func createMacPlatformConfiguration(macOSConfiguration: VZMacOSConfigurationRequirements) -> VZMacPlatformConfiguration {
        let macPlatformConfiguration = VZMacPlatformConfiguration()

        guard let auxiliaryStorage = try? VZMacAuxiliaryStorage(creatingStorageAt: auxiliaryStorageURL,
                                                                    hardwareModel: macOSConfiguration.hardwareModel,
                                                                          options: []) else {
            MachineConfigurationHelper.showErrorAndExit("Failed to create auxiliary storage.".localized)
        }
        macPlatformConfiguration.auxiliaryStorage = auxiliaryStorage
        macPlatformConfiguration.hardwareModel = macOSConfiguration.hardwareModel
        macPlatformConfiguration.machineIdentifier = VZMacMachineIdentifier()

        // Store the hardware model and machine identifier to disk so that you
        // can retrieve them for subsequent boots.
        try! macPlatformConfiguration.hardwareModel.dataRepresentation.write(to: hardwareModelURL)
        try! macPlatformConfiguration.machineIdentifier.dataRepresentation.write(to: machineIdentifierURL)

        return macPlatformConfiguration
    }

    // MARK: Create the virtual machine configuration and instantiate the virtual machine.

    private func setupVirtualMachine(macOSConfiguration: VZMacOSConfigurationRequirements) {
        let virtualMachineConfiguration = VZVirtualMachineConfiguration()

        virtualMachineConfiguration.platform = createMacPlatformConfiguration(macOSConfiguration: macOSConfiguration)
        virtualMachineConfiguration.cpuCount = MachineConfigurationHelper.computeCPUCount()
        if virtualMachineConfiguration.cpuCount < macOSConfiguration.minimumSupportedCPUCount {
            MachineConfigurationHelper.showErrorAndExit("CPUCount isn't supported by the macOS configuration.".localized)
        }

        virtualMachineConfiguration.memorySize = MachineConfigurationHelper.computeMemorySize()
        if virtualMachineConfiguration.memorySize < macOSConfiguration.minimumSupportedMemorySize {
            MachineConfigurationHelper.showErrorAndExit("memorySize isn't supported by the macOS configuration.".localized)
        }

        // Create the VM disk image.
        createDiskImage()

        virtualMachineConfiguration.bootLoader = MachineConfigurationHelper.createBootLoader()

        virtualMachineConfiguration.audioDevices = [MachineConfigurationHelper.createSoundDeviceConfiguration()]
        virtualMachineConfiguration.graphicsDevices = [MachineConfigurationHelper.createGraphicsDeviceConfiguration()]
        virtualMachineConfiguration.networkDevices = [MachineConfigurationHelper.createNetworkDeviceConfiguration()]
        virtualMachineConfiguration.storageDevices = [MachineConfigurationHelper.createBlockDeviceConfiguration()]

        virtualMachineConfiguration.pointingDevices = [MachineConfigurationHelper.createPointingDeviceConfiguration()]
        virtualMachineConfiguration.keyboards = [MachineConfigurationHelper.createKeyboardConfiguration()]

        try! virtualMachineConfiguration.validate()

        if #available(macOS 14.0, *) {
            try! virtualMachineConfiguration.validateSaveRestoreSupport()
        }

        virtualMachine = VZVirtualMachine(configuration: virtualMachineConfiguration)
        virtualMachineResponder = MacOSVirtualMachineDelegate()
        virtualMachine.delegate = virtualMachineResponder
    }

    // MARK: Begin macOS installation.

    private func startInstallation(restoreImageURL: URL, completionHandler: (() -> Void)?) {
        let installer = VZMacOSInstaller(virtualMachine: virtualMachine, restoringFromImageAt: restoreImageURL)

        NSLog("Starting installation.")
        installer.install(completionHandler: { (result: Result<Void, Error>) in
            if case let .failure(error) = result {
                MachineConfigurationHelper.showErrorAndExit(error.localizedDescription)
            } else {
                NSLog("Installation succeeded.")
                completionHandler?()
            }
        })

        // Observe installation progress.
        installationObserver = installer.progress.observe(\.fractionCompleted, options: [.initial, .new]) { (progress, change) in
            NSLog("Installation progress: \(change.newValue! * 100).")
        }
    }

    private func createVMBundle() {
        do {
            try FileManager.default.createDirectory(at: vmBundleURL, withIntermediateDirectories: true)
        } catch {
            MachineConfigurationHelper.showErrorAndExit("Failed to create VM.bundle.".localized)
        }
    }

    // Virtualization framework supports two disk image formats:
    // * RAW disk image: a file that has a 1-to-1 mapping between the offsets in the file and the offsets in the VM disk.
    //   The logical size of a RAW disk image is the size of the disk itself.
    //
    //   In case the image file is stored on an APFS volume, the file will take less space
    //   thanks to the sparse files feature of APFS.
    //
    // * ASIF disk image: A sparse image format. You can transfer ASIF files more efficiently between hosts or disks
    //   as their sparsity doesn’t depend on the host’s filesystem capabilities.
    //
    // The framework supports ASIF since macOS 16.
    @available(macOS 16.0, *)
    private func createASIFDiskImage() {
        do {
            let process = try Process.run(URL(fileURLWithPath: "/usr/sbin/diskutil"),
                                          arguments: ["image", "create", "blank",
                                                      "--fs", "none", "--format",
                                                      "ASIF", "--size", "\(diskImageSizeInGiB)GiB",
                                                      diskImageURL.path])
            process.waitUntilExit()
            if process.terminationStatus != 0 {
                MachineConfigurationHelper.showErrorAndExit("Failed to create the disk image.".localized)
            }
        } catch {
            MachineConfigurationHelper.showErrorAndExit("Failed to launch diskutil: %@".localized(error.localizedDescription))
        }
    }

    private func createRAWDiskImage() {
        let diskFd = open(diskImageURL.path, O_RDWR | O_CREAT, S_IRUSR | S_IWUSR)
        if diskFd == -1 {
            MachineConfigurationHelper.showErrorAndExit("Cannot create disk image.".localized)
        }

        var result = ftruncate(diskFd, off_t(diskImageSizeInBytes))
        if result != 0 {
            MachineConfigurationHelper.showErrorAndExit("ftruncate() failed.".localized)
        }

        result = close(diskFd)
        if result != 0 {
            MachineConfigurationHelper.showErrorAndExit("Failed to close the disk image.".localized)
        }
    }

    private func createDiskImage() {
        if #available(macOS 16.0, *) {
            createASIFDiskImage()
        } else {
            createRAWDiskImage()
        }
    }
}

#endif
