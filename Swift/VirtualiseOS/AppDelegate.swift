//
//  AppDelegate.swift
//  VirtualiseOS
//
//  Created by Daniel Mandea on 15.05.2025.
//  Copyright © 2026 M.T.D.Technology SRL. All rights reserved.
//

import Cocoa
import Foundation
import Virtualization

private final class SetupProgressView: NSView {
    var isIndeterminate = false
    var minValue = 0.0
    var maxValue = 100.0
    var doubleValue = 0.0 {
        didSet {
            needsDisplay = true
        }
    }
    var controlSize = NSControl.ControlSize.regular

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: 8)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let bounds = bounds.insetBy(dx: 0, dy: max((bounds.height - 6) / 2, 0))
        let trackPath = NSBezierPath(roundedRect: bounds, xRadius: 3, yRadius: 3)
        NSColor.white.withAlphaComponent(0.22).setFill()
        trackPath.fill()

        let range = max(maxValue - minValue, 1)
        let progress = min(max((doubleValue - minValue) / range, 0), 1)
        guard progress > 0 else {
            return
        }

        let fillRect = NSRect(x: bounds.minX,
                              y: bounds.minY,
                              width: bounds.width * progress,
                              height: bounds.height)
        let fillPath = NSBezierPath(roundedRect: fillRect, xRadius: 3, yRadius: 3)
        NSColor.white.setFill()
        fillPath.fill()
    }
}

@main
class AppDelegate: NSObject, NSApplicationDelegate {

    @IBOutlet var window: NSWindow!

    @IBOutlet weak var virtualMachineView: VZVirtualMachineView!

    private var virtualMachineResponder: MacOSVirtualMachineDelegate?

    private var virtualMachine: VZVirtualMachine!

    private var installationProcess: Process?
    private var originalContentView: NSView?
    private weak var installationStatusLabel: NSTextField?
    private weak var installationDetailLabel: NSTextField?
    private weak var installationProgressIndicator: SetupProgressView?
    private weak var launchSpinner: NSProgressIndicator?
    private weak var installButton: NSButton?
    private weak var memorySizePopUpButton: NSPopUpButton?
    private weak var vmLocationButton: NSButton?
    private weak var vmLocationPathLabel: NSTextField?
    private weak var sharedFolderButton: NSButton?
    private weak var sharedFolderPathLabel: NSTextField?
    private var restoreImageDownloadObserver: NSKeyValueObservation?
    private var macOSInstallationObserver: NSKeyValueObservation?
    private var restoreImageDownloadSession: URLSession?
    private var installationVirtualMachineResponder: MacOSVirtualMachineDelegate?
    private var installationVirtualMachine: VZVirtualMachine?
    private var isInstallationInProgress = false

    private let defaultDiskImageSizeInGiB: UInt64 = 128

    // MARK: Create the Mac platform configuration.

#if arch(arm64)
    private func createMacPlaform() throws -> VZMacPlatformConfiguration {
        let macPlatform = VZMacPlatformConfiguration()

        let auxiliaryStorage = VZMacAuxiliaryStorage(contentsOf: auxiliaryStorageURL)
        macPlatform.auxiliaryStorage = auxiliaryStorage

        if !FileManager.default.fileExists(atPath: vmBundlePath) {
            throw virtualMachineSetupError(MacOSVirtualMachineConfigurationHelper.localized("Missing Virtual Machine Bundle at %@. Run InstallationTool first to create it.", vmBundlePath))
        }

        // Retrieve the hardware model and save this value to disk during installation.
        guard let hardwareModelData = try? Data(contentsOf: hardwareModelURL) else {
            throw virtualMachineSetupError(MacOSVirtualMachineConfigurationHelper.localized("Failed to retrieve hardware model data."))
        }

        guard let hardwareModel = VZMacHardwareModel(dataRepresentation: hardwareModelData) else {
            throw virtualMachineSetupError(MacOSVirtualMachineConfigurationHelper.localized("Failed to create hardware model."))
        }

        if !hardwareModel.isSupported {
            throw virtualMachineSetupError(MacOSVirtualMachineConfigurationHelper.localized("The hardware model isn't supported on the current host"))
        }
        macPlatform.hardwareModel = hardwareModel

        // Retrieve the machine identifier and save this value to disk during installation.
        guard let machineIdentifierData = try? Data(contentsOf: machineIdentifierURL) else {
            throw virtualMachineSetupError(MacOSVirtualMachineConfigurationHelper.localized("Failed to retrieve machine identifier data."))
        }

        guard let machineIdentifier = VZMacMachineIdentifier(dataRepresentation: machineIdentifierData) else {
            throw virtualMachineSetupError(MacOSVirtualMachineConfigurationHelper.localized("Failed to create machine identifier."))
        }
        macPlatform.machineIdentifier = machineIdentifier

        return macPlatform
    }

    // MARK: Create the virtual machine configuration and instantiate the virtual machine.

    private func createVirtualMachine() throws {
        let virtualMachineConfiguration = VZVirtualMachineConfiguration()

        virtualMachineConfiguration.platform = try createMacPlaform()
        virtualMachineConfiguration.bootLoader = MacOSVirtualMachineConfigurationHelper.createBootLoader()
        virtualMachineConfiguration.cpuCount = MacOSVirtualMachineConfigurationHelper.computeCPUCount()
        virtualMachineConfiguration.memorySize = MacOSVirtualMachineConfigurationHelper.computeMemorySize()

        virtualMachineConfiguration.audioDevices = [MacOSVirtualMachineConfigurationHelper.createSoundDeviceConfiguration()]
        virtualMachineConfiguration.graphicsDevices = [MacOSVirtualMachineConfigurationHelper.createGraphicsDeviceConfiguration()]
        virtualMachineConfiguration.networkDevices = [MacOSVirtualMachineConfigurationHelper.createNetworkDeviceConfiguration()]
        virtualMachineConfiguration.storageDevices = [MacOSVirtualMachineConfigurationHelper.createBlockDeviceConfiguration()]
        if let directorySharingDevice = MacOSVirtualMachineConfigurationHelper.createDirectorySharingDeviceConfiguration() {
            virtualMachineConfiguration.directorySharingDevices = [directorySharingDevice]
        }

        virtualMachineConfiguration.pointingDevices = [MacOSVirtualMachineConfigurationHelper.createPointingDeviceConfiguration()]
        virtualMachineConfiguration.keyboards = [MacOSVirtualMachineConfigurationHelper.createKeyboardConfiguration()]

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
            return MacOSVirtualMachineConfigurationHelper.localized("The virtual machine is already in use. Quit any other running copy of VirtualiseOS or wait for the previous VM process to finish, then start the app again.")
        }

        return MacOSVirtualMachineConfigurationHelper.localized(prefixKey, errorDescription)
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

    func applicationDidFinishLaunching(_ aNotification: Notification) {
#if arch(arm64)
        configureSharedFolderMenuItem()

        DispatchQueue.main.async { [self] in
            prepareVirtualMachine()
        }
#endif
    }

    func applicationDidBecomeActive(_ notification: Notification) {
#if arch(arm64)
        refreshSetupStateIfNeeded()
#endif
    }

#if arch(arm64)
    private func prepareVirtualMachine() {
        showInstallationScreen()

        if isVirtualMachineInstalled {
            launchVirtualMachine()
        }
    }

    private func refreshSetupStateIfNeeded() {
        guard virtualMachine == nil,
              installationProcess == nil,
              !isInstallationInProgress,
              installButton != nil else {
            return
        }

        updateSetupStateForCurrentVMLocation()
    }

    private func configureSharedFolderMenuItem() {
        guard let appMenu = NSApp.mainMenu?.items.first?.submenu else {
            return
        }

        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: MacOSVirtualMachineConfigurationHelper.localized("Choose VM Location..."),
                        action: #selector(chooseVMLocation),
                        keyEquivalent: "")
        appMenu.addItem(withTitle: MacOSVirtualMachineConfigurationHelper.localized("Choose Shared Folder..."),
                        action: #selector(chooseSharedFolder),
                        keyEquivalent: "")
        appMenu.addItem(withTitle: MacOSVirtualMachineConfigurationHelper.localized("Stop VM and Show Settings..."),
                        action: #selector(stopVirtualMachineAndShowSettings),
                        keyEquivalent: "")
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
                self?.returnToSettingsScreen()
            }
        }
        virtualMachine.delegate = virtualMachineResponder
        virtualMachineView.virtualMachine = virtualMachine
        virtualMachineView.capturesSystemKeys = true

        if #available(macOS 14.0, *) {
            // Configure the app to automatically respond to changes in the display size.
            virtualMachineView.automaticallyReconfiguresDisplay = true
        }

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
        launchSpinner?.stopAnimation(nil)
        launchSpinner?.isHidden = true

        if let originalContentView {
            window.contentView = originalContentView
        }
    }

    private func showVirtualMachineStartingState() {
        guard installButton != nil else {
            return
        }

        installationStatusLabel?.stringValue = MacOSVirtualMachineConfigurationHelper.localized("Starting virtual machine...")
        installationDetailLabel?.stringValue = MacOSVirtualMachineConfigurationHelper.localized("VirtualiseOS is validating the VM configuration and opening the selected VM.bundle.")
        setSetupButtonTitle(MacOSVirtualMachineConfigurationHelper.localized("Starting..."), for: installButton)
        installButton?.isEnabled = false
        memorySizePopUpButton?.isEnabled = false
        vmLocationButton?.isEnabled = false
        sharedFolderButton?.isEnabled = false
        installationProgressIndicator?.doubleValue = 0
        installationProgressIndicator?.isHidden = true
        launchSpinner?.isHidden = false
        launchSpinner?.startAnimation(nil)
    }

    private func handleVirtualMachineLaunchFailure(_ message: String) {
        launchSpinner?.stopAnimation(nil)
        launchSpinner?.isHidden = true
        virtualMachineView?.virtualMachine = nil
        virtualMachine = nil
        virtualMachineResponder = nil
        showInstallationScreen()
        installationStatusLabel?.stringValue = MacOSVirtualMachineConfigurationHelper.localized("Virtual machine failed to start")
        installationDetailLabel?.stringValue = message
        installationProgressIndicator?.doubleValue = 0
        installationProgressIndicator?.isHidden = true
        setSetupButtonTitle(MacOSVirtualMachineConfigurationHelper.localized("Retry Open VM"), for: installButton)
        installButton?.isHidden = false
        installButton?.isEnabled = true
        memorySizePopUpButton?.isEnabled = true
        vmLocationButton?.isEnabled = true
        sharedFolderButton?.isEnabled = true
    }

    @objc private func stopVirtualMachineAndShowSettings() {
        guard let virtualMachine else {
            returnToSettingsScreen()
            return
        }

        if virtualMachine.canStop {
            virtualMachine.stop { [weak self] error in
                DispatchQueue.main.async {
                    if let error {
                        self?.showInformationAlert(self?.virtualMachineErrorMessage(prefixKey: "Virtual machine failed to stop with %@", error: error) ?? error.localizedDescription)
                        return
                    }

                    self?.returnToSettingsScreen()
                }
            }
        } else {
            showInformationAlert(MacOSVirtualMachineConfigurationHelper.localized("The virtual machine cannot be stopped while it is changing state. Try again in a moment."))
        }
    }

    private func returnToSettingsScreen() {
        virtualMachineView?.virtualMachine = nil
        virtualMachine = nil
        virtualMachineResponder = nil
        showInstallationScreen()
        updateSetupStateForCurrentVMLocation()
    }

    private func showInstallationScreen() {
        if originalContentView == nil {
            originalContentView = window.contentView
        }

        let contentView = NSView()
        contentView.wantsLayer = true
        contentView.layer?.backgroundColor = (NSColor(named: "backgroundColor") ?? .windowBackgroundColor).cgColor
        window.backgroundColor = NSColor(named: "backgroundColor") ?? .windowBackgroundColor

        let primaryTextColor = NSColor.white
        let secondaryTextColor = NSColor.white.withAlphaComponent(0.72)

        let titleLabel = NSTextField(labelWithString: MacOSVirtualMachineConfigurationHelper.localized("Preparing VirtualiseOS"))
        titleLabel.font = .systemFont(ofSize: 30, weight: .semibold)
        titleLabel.textColor = primaryTextColor
        titleLabel.alignment = .center

        let statusLabel = NSTextField(labelWithString: MacOSVirtualMachineConfigurationHelper.localized("Virtual machine is not installed"))
        statusLabel.font = .systemFont(ofSize: 17, weight: .medium)
        statusLabel.textColor = primaryTextColor
        statusLabel.alignment = .center

        let detailLabel = NSTextField(labelWithString: MacOSVirtualMachineConfigurationHelper.localized("Download and install the latest macOS version supported by this Mac."))
        detailLabel.font = .systemFont(ofSize: 14)
        detailLabel.textColor = secondaryTextColor
        detailLabel.alignment = .center
        detailLabel.lineBreakMode = .byWordWrapping
        detailLabel.maximumNumberOfLines = 3

        let progressIndicator = SetupProgressView()
        progressIndicator.isIndeterminate = false
        progressIndicator.minValue = 0
        progressIndicator.maxValue = 100
        progressIndicator.doubleValue = 0
        progressIndicator.controlSize = .large
        progressIndicator.isHidden = true

        let launchSpinner = NSProgressIndicator()
        launchSpinner.style = .spinning
        launchSpinner.controlSize = .large
        launchSpinner.isIndeterminate = true
        launchSpinner.isDisplayedWhenStopped = false
        launchSpinner.isHidden = true

        let installButton = NSButton(title: MacOSVirtualMachineConfigurationHelper.localized("Download and Install Latest macOS"),
                                     target: self,
                                     action: #selector(downloadAndInstallLatestMacOS))
        installButton.bezelStyle = .rounded
        installButton.controlSize = .large
        styleSetupButton(installButton)

        let memoryLabel = NSTextField(labelWithString: MacOSVirtualMachineConfigurationHelper.localized("Memory"))
        memoryLabel.font = .systemFont(ofSize: 13, weight: .medium)
        memoryLabel.textColor = primaryTextColor

        let memorySizePopUpButton = NSPopUpButton()
        memorySizePopUpButton.controlSize = .large
        memorySizePopUpButton.target = self
        memorySizePopUpButton.action = #selector(memorySizeSelectionDidChange)
        configureMemorySizePopUpButton(memorySizePopUpButton)
        styleSetupPopUpButton(memorySizePopUpButton)

        let memoryStackView = NSStackView(views: [memoryLabel, memorySizePopUpButton])
        memoryStackView.orientation = .horizontal
        memoryStackView.alignment = .centerY
        memoryStackView.distribution = .equalSpacing
        memoryStackView.spacing = 16

        let vmLocationTitleLabel = NSTextField(labelWithString: MacOSVirtualMachineConfigurationHelper.localized("VM Location"))
        vmLocationTitleLabel.font = .systemFont(ofSize: 13, weight: .medium)
        vmLocationTitleLabel.textColor = primaryTextColor

        let vmLocationButton = NSButton(title: MacOSVirtualMachineConfigurationHelper.localized("Choose Folder..."),
                                        target: self,
                                        action: #selector(chooseVMLocation))
        vmLocationButton.bezelStyle = .rounded
        vmLocationButton.controlSize = .large
        styleSetupButton(vmLocationButton)

        let vmLocationPathLabel = NSTextField(labelWithString: vmLocationDescription())
        vmLocationPathLabel.font = .systemFont(ofSize: 12)
        vmLocationPathLabel.textColor = secondaryTextColor
        vmLocationPathLabel.lineBreakMode = .byTruncatingMiddle
        vmLocationPathLabel.maximumNumberOfLines = 1

        let vmLocationHeaderStackView = NSStackView(views: [vmLocationTitleLabel, vmLocationButton])
        vmLocationHeaderStackView.orientation = .horizontal
        vmLocationHeaderStackView.alignment = .centerY
        vmLocationHeaderStackView.distribution = .equalSpacing
        vmLocationHeaderStackView.spacing = 16

        let vmLocationStackView = NSStackView(views: [vmLocationHeaderStackView, vmLocationPathLabel])
        vmLocationStackView.orientation = .vertical
        vmLocationStackView.alignment = .centerX
        vmLocationStackView.spacing = 6

        let sharedFolderTitleLabel = NSTextField(labelWithString: MacOSVirtualMachineConfigurationHelper.localized("Shared Folder"))
        sharedFolderTitleLabel.font = .systemFont(ofSize: 13, weight: .medium)
        sharedFolderTitleLabel.textColor = primaryTextColor

        let sharedFolderButton = NSButton(title: MacOSVirtualMachineConfigurationHelper.localized("Choose Folder..."),
                                          target: self,
                                          action: #selector(chooseSharedFolder))
        sharedFolderButton.bezelStyle = .rounded
        sharedFolderButton.controlSize = .large
        styleSetupButton(sharedFolderButton)

        let sharedFolderPathLabel = NSTextField(labelWithString: sharedFolderDescription())
        sharedFolderPathLabel.font = .systemFont(ofSize: 12)
        sharedFolderPathLabel.textColor = secondaryTextColor
        sharedFolderPathLabel.lineBreakMode = .byTruncatingMiddle
        sharedFolderPathLabel.maximumNumberOfLines = 1

        let sharedFolderHeaderStackView = NSStackView(views: [sharedFolderTitleLabel, sharedFolderButton])
        sharedFolderHeaderStackView.orientation = .horizontal
        sharedFolderHeaderStackView.alignment = .centerY
        sharedFolderHeaderStackView.distribution = .equalSpacing
        sharedFolderHeaderStackView.spacing = 16

        let sharedFolderStackView = NSStackView(views: [sharedFolderHeaderStackView, sharedFolderPathLabel])
        sharedFolderStackView.orientation = .vertical
        sharedFolderStackView.alignment = .centerX
        sharedFolderStackView.spacing = 6

        let stackView = NSStackView(views: [titleLabel, statusLabel, detailLabel, launchSpinner, memoryStackView, vmLocationStackView, sharedFolderStackView, installButton, progressIndicator])
        stackView.orientation = .vertical
        stackView.alignment = .centerX
        stackView.spacing = 18
        stackView.translatesAutoresizingMaskIntoConstraints = false

        let panelView = NSView()
        panelView.wantsLayer = true
        panelView.translatesAutoresizingMaskIntoConstraints = false
        panelView.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.10).cgColor
        panelView.layer?.cornerRadius = 22
        panelView.layer?.borderColor = NSColor.white.withAlphaComponent(0.18).cgColor
        panelView.layer?.borderWidth = 1
        panelView.layer?.shadowColor = NSColor.black.cgColor
        panelView.layer?.shadowOpacity = 0.18
        panelView.layer?.shadowRadius = 24
        panelView.layer?.shadowOffset = CGSize(width: 0, height: -8)

        let logoImageView = NSImageView()
        logoImageView.image = NSImage(named: "logo")
        logoImageView.imageScaling = .scaleProportionallyUpOrDown
        logoImageView.translatesAutoresizingMaskIntoConstraints = false
        logoImageView.isHidden = logoImageView.image == nil

        contentView.addSubview(panelView)
        panelView.addSubview(stackView)
        contentView.addSubview(logoImageView)
        NSLayoutConstraint.activate([
            panelView.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            panelView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            panelView.widthAnchor.constraint(equalToConstant: 560),
            panelView.leadingAnchor.constraint(greaterThanOrEqualTo: contentView.leadingAnchor, constant: 48),
            panelView.trailingAnchor.constraint(lessThanOrEqualTo: contentView.trailingAnchor, constant: -48),
            stackView.topAnchor.constraint(equalTo: panelView.topAnchor, constant: 44),
            stackView.bottomAnchor.constraint(equalTo: panelView.bottomAnchor, constant: -44),
            stackView.leadingAnchor.constraint(equalTo: panelView.leadingAnchor, constant: 48),
            stackView.trailingAnchor.constraint(equalTo: panelView.trailingAnchor, constant: -48),
            progressIndicator.widthAnchor.constraint(equalToConstant: 420),
            detailLabel.widthAnchor.constraint(equalToConstant: 420),
            installButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 260),
            installButton.heightAnchor.constraint(equalToConstant: 36),
            memorySizePopUpButton.widthAnchor.constraint(equalToConstant: 160),
            memorySizePopUpButton.heightAnchor.constraint(equalToConstant: 34),
            vmLocationButton.widthAnchor.constraint(equalToConstant: 168),
            vmLocationButton.heightAnchor.constraint(equalToConstant: 34),
            sharedFolderButton.widthAnchor.constraint(equalToConstant: 168),
            sharedFolderButton.heightAnchor.constraint(equalToConstant: 34),
            memoryStackView.widthAnchor.constraint(equalToConstant: 420),
            vmLocationHeaderStackView.widthAnchor.constraint(equalToConstant: 420),
            vmLocationPathLabel.widthAnchor.constraint(equalToConstant: 420),
            sharedFolderHeaderStackView.widthAnchor.constraint(equalToConstant: 420),
            sharedFolderPathLabel.widthAnchor.constraint(equalToConstant: 420),
            logoImageView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -28),
            logoImageView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -24),
            logoImageView.widthAnchor.constraint(equalToConstant: 120),
            logoImageView.heightAnchor.constraint(equalToConstant: 56)
        ])

        installationStatusLabel = statusLabel
        installationDetailLabel = detailLabel
        installationProgressIndicator = progressIndicator
        self.launchSpinner = launchSpinner
        self.installButton = installButton
        self.memorySizePopUpButton = memorySizePopUpButton
        self.vmLocationButton = vmLocationButton
        self.vmLocationPathLabel = vmLocationPathLabel
        self.sharedFolderButton = sharedFolderButton
        self.sharedFolderPathLabel = sharedFolderPathLabel
        updateSetupStateForCurrentVMLocation()
        window.contentView = contentView
    }

    private func setupControlTitle(_ title: String, font: NSFont = .systemFont(ofSize: NSFont.systemFontSize)) -> NSAttributedString {
        NSAttributedString(string: title, attributes: [
            .foregroundColor: NSColor.white,
            .font: font
        ])
    }

    private func styleSetupButton(_ button: NSButton) {
        button.isBordered = false
        button.wantsLayer = true
        button.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.16).cgColor
        button.layer?.cornerRadius = 16
        button.layer?.borderColor = NSColor.white.withAlphaComponent(0.30).cgColor
        button.layer?.borderWidth = 1
        setSetupButtonTitle(button.title, for: button)
    }

    private func setSetupButtonTitle(_ title: String, for button: NSButton?) {
        guard let button else {
            return
        }

        let font = button.font ?? .systemFont(ofSize: NSFont.systemFontSize)
        let attributedTitle = setupControlTitle(title, font: font)
        button.title = title
        button.attributedTitle = attributedTitle
        button.attributedAlternateTitle = attributedTitle
    }

    private func styleSetupPopUpButton(_ popUpButton: NSPopUpButton) {
        let font = popUpButton.font ?? .systemFont(ofSize: NSFont.systemFontSize)
        for item in popUpButton.itemArray where !item.title.isEmpty {
            item.attributedTitle = setupControlTitle(item.title, font: font)
        }

        let title = popUpButton.titleOfSelectedItem ?? popUpButton.title
        popUpButton.attributedTitle = setupControlTitle(title, font: font)
    }

    private func vmLocationDescription() -> String {
        return MacOSVirtualMachineConfigurationHelper.localized("VM bundle path: %@", vmBundleURL.path)
    }

    @objc private func chooseVMLocation() {
        guard virtualMachine == nil else {
            showInformationAlert(MacOSVirtualMachineConfigurationHelper.localized("Changing the VM location requires quitting the running virtual machine first."))
            return
        }

        let openPanel = NSOpenPanel()
        openPanel.canChooseFiles = true
        openPanel.canChooseDirectories = true
        openPanel.allowsMultipleSelection = false
        openPanel.canCreateDirectories = true
        openPanel.treatsFilePackagesAsDirectories = false
        openPanel.prompt = MacOSVirtualMachineConfigurationHelper.localized("Choose")
        openPanel.message = MacOSVirtualMachineConfigurationHelper.localized("Choose VM.bundle or the folder where VirtualiseOS should store it.")

        guard openPanel.runModal() == .OK, let url = openPanel.url else {
            return
        }

        do {
            let selectedURL = normalizedSelectedVMLocation(url)
            let bookmarkData = try selectedURL.bookmarkData(options: [.withSecurityScope],
                                                            includingResourceValuesForKeys: nil,
                                                            relativeTo: nil)
            UserDefaults.standard.set(bookmarkData, forKey: vmBundleBookmarkUserDefaultsKey)
            UserDefaults.standard.removeObject(forKey: vmBundleParentDirectoryBookmarkUserDefaultsKey)
            vmLocationPathLabel?.stringValue = vmLocationDescription()
            updateSetupStateForCurrentVMLocation()
        } catch {
            showInstallationFailure(error.localizedDescription)
        }
    }

    private func normalizedSelectedVMLocation(_ url: URL) -> URL {
        if url.lastPathComponent == "VM.bundle" || url.pathExtension == "bundle" {
            return url
        }

        return url
    }

    private func updateSetupStateForCurrentVMLocation() {
        installButton?.isHidden = false
        installButton?.isEnabled = true
        memorySizePopUpButton?.isEnabled = true
        vmLocationButton?.isEnabled = true
        sharedFolderButton?.isEnabled = true
        installationProgressIndicator?.doubleValue = 0
        installationProgressIndicator?.isHidden = true
        launchSpinner?.stopAnimation(nil)
        launchSpinner?.isHidden = true

        if isVirtualMachineInstalled {
            installationStatusLabel?.stringValue = MacOSVirtualMachineConfigurationHelper.localized("Virtual machine is ready")
            installationDetailLabel?.stringValue = MacOSVirtualMachineConfigurationHelper.localized("Open the existing VM.bundle at the selected location.")
            setSetupButtonTitle(MacOSVirtualMachineConfigurationHelper.localized("Open VM"), for: installButton)
        } else if FileManager.default.fileExists(atPath: vmBundlePath) {
            installationStatusLabel?.stringValue = MacOSVirtualMachineConfigurationHelper.localized("VM.bundle was found but is incomplete")
            installationDetailLabel?.stringValue = missingVirtualMachineFilesDescription()
            setSetupButtonTitle(MacOSVirtualMachineConfigurationHelper.localized("Download and Install Latest macOS"), for: installButton)
        } else {
            installationStatusLabel?.stringValue = MacOSVirtualMachineConfigurationHelper.localized("Virtual machine is not installed")
            installationDetailLabel?.stringValue = MacOSVirtualMachineConfigurationHelper.localized("Download and install the latest macOS version supported by this Mac.")
            setSetupButtonTitle(MacOSVirtualMachineConfigurationHelper.localized("Download and Install Latest macOS"), for: installButton)
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
            return MacOSVirtualMachineConfigurationHelper.localized("Open the existing VM.bundle at the selected location.")
        }

        return MacOSVirtualMachineConfigurationHelper.localized("Missing VM files: %@", missingNames.joined(separator: ", "))
    }

    private func showInformationAlert(_ message: String) {
        let alert = NSAlert()
        alert.messageText = MacOSVirtualMachineConfigurationHelper.localized("VirtualiseOS")
        alert.informativeText = message
        alert.alertStyle = .informational
        alert.addButton(withTitle: MacOSVirtualMachineConfigurationHelper.localized("OK"))
        alert.runModal()
    }

    private func sharedFolderDescription() -> String {
        guard let url = selectedSharedFolderURL() else {
            return MacOSVirtualMachineConfigurationHelper.localized("No shared folder selected")
        }

        return MacOSVirtualMachineConfigurationHelper.localized("Shared in the guest at /Volumes/My Shared Files: %@", url.path)
    }

    private func selectedSharedFolderURL() -> URL? {
        guard let bookmarkData = UserDefaults.standard.data(forKey: MacOSVirtualMachineConfigurationHelper.sharedDirectoryBookmarkUserDefaultsKey) else {
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

    @objc private func chooseSharedFolder() {
        let openPanel = NSOpenPanel()
        openPanel.canChooseFiles = false
        openPanel.canChooseDirectories = true
        openPanel.allowsMultipleSelection = false
        openPanel.canCreateDirectories = true
        openPanel.prompt = MacOSVirtualMachineConfigurationHelper.localized("Choose")
        openPanel.message = MacOSVirtualMachineConfigurationHelper.localized("Choose a host folder to share with the macOS virtual machine.")

        guard openPanel.runModal() == .OK, let url = openPanel.url else {
            return
        }

        do {
            let bookmarkData = try url.bookmarkData(options: [.withSecurityScope],
                                                    includingResourceValuesForKeys: nil,
                                                    relativeTo: nil)
            UserDefaults.standard.set(bookmarkData, forKey: MacOSVirtualMachineConfigurationHelper.sharedDirectoryBookmarkUserDefaultsKey)
            sharedFolderPathLabel?.stringValue = sharedFolderDescription()
            updateRunningSharedFolderIfPossible()
            updateSetupStateForCurrentVMLocation()
        } catch {
            showInstallationFailure(error.localizedDescription)
        }
    }

    private func updateRunningSharedFolderIfPossible() {
        guard let virtualMachine,
              let directorySharingDevice = virtualMachine.directorySharingDevices.first as? VZVirtioFileSystemDevice,
              let sharingConfiguration = MacOSVirtualMachineConfigurationHelper.createDirectorySharingDeviceConfiguration() else {
            return
        }

        directorySharingDevice.share = sharingConfiguration.share
    }

    private func configureMemorySizePopUpButton(_ popUpButton: NSPopUpButton) {
        let memorySizeOptionsInGiB = [4, 6, 8, 12, 16, 24, 32]
        let savedMemorySizeInGiB = UserDefaults.standard.integer(forKey: MacOSVirtualMachineConfigurationHelper.memorySizeInGiBUserDefaultsKey)
        let selectedMemorySizeInGiB = savedMemorySizeInGiB > 0 ? savedMemorySizeInGiB : MacOSVirtualMachineConfigurationHelper.defaultMemorySizeInGiB

        popUpButton.removeAllItems()

        for memorySizeInGiB in memorySizeOptionsInGiB {
            popUpButton.addItem(withTitle: MacOSVirtualMachineConfigurationHelper.localized("%d GB", memorySizeInGiB))
            popUpButton.lastItem?.representedObject = memorySizeInGiB
        }

        if let selectedItem = popUpButton.itemArray.first(where: { ($0.representedObject as? Int) == selectedMemorySizeInGiB }) {
            popUpButton.select(selectedItem)
        } else {
            popUpButton.selectItem(withTitle: MacOSVirtualMachineConfigurationHelper.localized("%d GB", MacOSVirtualMachineConfigurationHelper.defaultMemorySizeInGiB))
        }
    }

    @objc private func memorySizeSelectionDidChange(_ sender: NSPopUpButton) {
        guard let memorySizeInGiB = sender.selectedItem?.representedObject as? Int else {
            return
        }

        UserDefaults.standard.set(memorySizeInGiB, forKey: MacOSVirtualMachineConfigurationHelper.memorySizeInGiBUserDefaultsKey)
        styleSetupPopUpButton(sender)
    }

    @objc private func downloadAndInstallLatestMacOS() {
        if isVirtualMachineInstalled {
            launchVirtualMachine()
            return
        }

        if let memorySizeInGiB = memorySizePopUpButton?.selectedItem?.representedObject as? Int {
            UserDefaults.standard.set(memorySizeInGiB, forKey: MacOSVirtualMachineConfigurationHelper.memorySizeInGiBUserDefaultsKey)
        }

        isInstallationInProgress = true
        installButton?.isEnabled = false
        memorySizePopUpButton?.isEnabled = false
        vmLocationButton?.isEnabled = false
        sharedFolderButton?.isEnabled = false
        installationProgressIndicator?.isHidden = false
        installationProgressIndicator?.doubleValue = 0
        startInAppInstallation()
    }

    private func startInAppInstallation() {
        do {
            try removeIncompleteVirtualMachineBundleIfNeeded()
            try FileManager.default.createDirectory(at: vmBundleURL, withIntermediateDirectories: true)
        } catch {
            showInstallationFailure(error.localizedDescription)
            return
        }

        installButton?.isHidden = true
        installationStatusLabel?.stringValue = MacOSVirtualMachineConfigurationHelper.localized("Finding latest supported macOS...")
        installationDetailLabel?.stringValue = MacOSVirtualMachineConfigurationHelper.localized("VirtualiseOS will download the latest macOS restore image supported by this Mac.")
        installationProgressIndicator?.doubleValue = 0

        VZMacOSRestoreImage.fetchLatestSupported { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case let .failure(error):
                    self?.showInstallationFailure(error.localizedDescription)

                case let .success(restoreImage):
                    self?.installationDetailLabel?.stringValue = MacOSVirtualMachineConfigurationHelper.localized("Latest supported macOS: %@ (%@)", "\(restoreImage.operatingSystemVersion)", restoreImage.buildVersion)
                    self?.downloadRestoreImage(restoreImage)
                }
            }
        }
    }

    private func downloadRestoreImage(_ restoreImage: VZMacOSRestoreImage) {
        installationStatusLabel?.stringValue = MacOSVirtualMachineConfigurationHelper.localized("Downloading macOS restore image...")
        installationDetailLabel?.stringValue = MacOSVirtualMachineConfigurationHelper.localized("This can take a while depending on network speed.")

        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 300
        configuration.timeoutIntervalForResource = 24 * 60 * 60

        let session = URLSession(configuration: configuration)
        restoreImageDownloadSession = session

        let downloadTask = session.downloadTask(with: restoreImage.url) { [weak self] localURL, response, error in
            DispatchQueue.main.async {
                if let error {
                    self?.showInstallationFailure(MacOSVirtualMachineConfigurationHelper.localized("Download failed with error: %@", error.localizedDescription))
                    return
                }

                guard let localURL else {
                    self?.showInstallationFailure(MacOSVirtualMachineConfigurationHelper.localized("Download failed because the restore image file was not available."))
                    return
                }

                do {
                    if FileManager.default.fileExists(atPath: restoreImageURL.path) {
                        try FileManager.default.removeItem(at: restoreImageURL)
                    }

                    try FileManager.default.moveItem(at: localURL, to: restoreImageURL)
                    self?.restoreImageDownloadSession?.finishTasksAndInvalidate()
                    self?.restoreImageDownloadSession = nil
                    self?.installMacOS(from: restoreImageURL)
                } catch {
                    self?.showInstallationFailure(error.localizedDescription)
                }
            }
        }

        restoreImageDownloadObserver = downloadTask.progress.observe(\.fractionCompleted, options: [.initial, .new]) { [weak self] progress, change in
            DispatchQueue.main.async {
                let percentage = (change.newValue ?? progress.fractionCompleted) * 100
                self?.installationProgressIndicator?.isHidden = false
                self?.installationProgressIndicator?.doubleValue = min(percentage * 0.5, 50)
                self?.installationDetailLabel?.stringValue = MacOSVirtualMachineConfigurationHelper.localized("%d%% downloaded", Int(percentage))
            }
        }

        downloadTask.resume()
    }

    private func installMacOS(from ipswURL: URL) {
        installationStatusLabel?.stringValue = MacOSVirtualMachineConfigurationHelper.localized("Preparing installer...")
        installationDetailLabel?.stringValue = MacOSVirtualMachineConfigurationHelper.localized("Loading the downloaded macOS restore image.")

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
            showInstallationFailure(MacOSVirtualMachineConfigurationHelper.localized("No supported macOS configuration is available for this Mac."))
            return
        }

        guard macOSConfiguration.hardwareModel.isSupported else {
            showInstallationFailure(MacOSVirtualMachineConfigurationHelper.localized("The macOS configuration is not supported on this Mac."))
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
        virtualMachineConfiguration.cpuCount = MacOSVirtualMachineConfigurationHelper.computeCPUCount()
        if virtualMachineConfiguration.cpuCount < macOSConfiguration.minimumSupportedCPUCount {
            throw NSError(domain: "VirtualiseOS", code: 2, userInfo: [
                NSLocalizedDescriptionKey: MacOSVirtualMachineConfigurationHelper.localized("This Mac does not have enough CPU cores for the selected macOS restore image.")
            ])
        }

        virtualMachineConfiguration.memorySize = MacOSVirtualMachineConfigurationHelper.computeMemorySize()
        if virtualMachineConfiguration.memorySize < macOSConfiguration.minimumSupportedMemorySize {
            throw NSError(domain: "VirtualiseOS", code: 3, userInfo: [
                NSLocalizedDescriptionKey: MacOSVirtualMachineConfigurationHelper.localized("This Mac does not have enough memory for the selected macOS restore image.")
            ])
        }

        try createDiskImage()

        virtualMachineConfiguration.bootLoader = MacOSVirtualMachineConfigurationHelper.createBootLoader()
        virtualMachineConfiguration.audioDevices = [MacOSVirtualMachineConfigurationHelper.createSoundDeviceConfiguration()]
        virtualMachineConfiguration.graphicsDevices = [MacOSVirtualMachineConfigurationHelper.createGraphicsDeviceConfiguration()]
        virtualMachineConfiguration.networkDevices = [MacOSVirtualMachineConfigurationHelper.createNetworkDeviceConfiguration()]
        virtualMachineConfiguration.storageDevices = [MacOSVirtualMachineConfigurationHelper.createBlockDeviceConfiguration()]
        if let directorySharingDevice = MacOSVirtualMachineConfigurationHelper.createDirectorySharingDeviceConfiguration() {
            virtualMachineConfiguration.directorySharingDevices = [directorySharingDevice]
        }
        virtualMachineConfiguration.pointingDevices = [MacOSVirtualMachineConfigurationHelper.createPointingDeviceConfiguration()]
        virtualMachineConfiguration.keyboards = [MacOSVirtualMachineConfigurationHelper.createKeyboardConfiguration()]

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
        let diskImageSizeInBytes = defaultDiskImageSizeInGiB * 1024 * 1024 * 1024
        let diskFd = open(diskImageURL.path, O_RDWR | O_CREAT, S_IRUSR | S_IWUSR)

        guard diskFd != -1 else {
            throw NSError(domain: "VirtualiseOS", code: 4, userInfo: [
                NSLocalizedDescriptionKey: MacOSVirtualMachineConfigurationHelper.localized("Cannot create the virtual machine disk image.")
            ])
        }

        defer {
            close(diskFd)
        }

        guard ftruncate(diskFd, off_t(diskImageSizeInBytes)) == 0 else {
            throw NSError(domain: "VirtualiseOS", code: 5, userInfo: [
                NSLocalizedDescriptionKey: MacOSVirtualMachineConfigurationHelper.localized("Cannot resize the virtual machine disk image.")
            ])
        }
    }

    private func startMacOSInstallation(on virtualMachine: VZVirtualMachine, restoreImageURL: URL) {
        let installer = VZMacOSInstaller(virtualMachine: virtualMachine, restoringFromImageAt: restoreImageURL)

        installationStatusLabel?.stringValue = MacOSVirtualMachineConfigurationHelper.localized("Installing macOS...")
        installationDetailLabel?.stringValue = MacOSVirtualMachineConfigurationHelper.localized("The virtual machine is being created.")
        installationProgressIndicator?.doubleValue = max(installationProgressIndicator?.doubleValue ?? 0, 50)

        installer.install { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case let .failure(error):
                    self?.showInstallationFailure(error.localizedDescription)

                case .success:
                    self?.installationStatusLabel?.stringValue = MacOSVirtualMachineConfigurationHelper.localized("Installation complete")
                    self?.finishInstallationAndRefreshSetupState()
                }
            }
        }

        macOSInstallationObserver = installer.progress.observe(\.fractionCompleted, options: [.initial, .new]) { [weak self] progress, change in
            DispatchQueue.main.async {
                let percentage = (change.newValue ?? progress.fractionCompleted) * 100
                self?.installationProgressIndicator?.isHidden = false
                self?.installationProgressIndicator?.doubleValue = 50 + min(percentage * 0.5, 50)
                self?.installationDetailLabel?.stringValue = MacOSVirtualMachineConfigurationHelper.localized("%d%% installed", Int(percentage))
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
            installationStatusLabel?.stringValue = MacOSVirtualMachineConfigurationHelper.localized("Downloading macOS restore image...")
            installationDetailLabel?.stringValue = MacOSVirtualMachineConfigurationHelper.localized("This can take a while depending on network speed.")
            installButton?.isHidden = true
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
            NSLocalizedDescriptionKey: MacOSVirtualMachineConfigurationHelper.localized("InstallationTool-Swift is missing from the app bundle.")
        ])
    }

    private func handleInstallationOutput(_ output: String) {
        if output.contains("Restore image download progress") {
            installationStatusLabel?.stringValue = MacOSVirtualMachineConfigurationHelper.localized("Downloading macOS restore image...")
            if let percentage = progressPercentage(from: output) {
                installationProgressIndicator?.doubleValue = min(percentage * 0.5, 50)
                installationDetailLabel?.stringValue = MacOSVirtualMachineConfigurationHelper.localized("%d%% downloaded", Int(percentage))
            }
        } else if output.contains("Latest supported macOS restore image") {
            installationDetailLabel?.stringValue = MacOSVirtualMachineConfigurationHelper.localized("Found the latest supported macOS restore image.")
        } else if output.contains("Starting installation") {
            installationStatusLabel?.stringValue = MacOSVirtualMachineConfigurationHelper.localized("Installing macOS...")
            installationDetailLabel?.stringValue = MacOSVirtualMachineConfigurationHelper.localized("The virtual machine is being created.")
            installationProgressIndicator?.doubleValue = max(installationProgressIndicator?.doubleValue ?? 0, 50)
        } else if output.contains("Installation progress") {
            installationStatusLabel?.stringValue = MacOSVirtualMachineConfigurationHelper.localized("Installing macOS...")
            if let percentage = progressPercentage(from: output) {
                installationProgressIndicator?.doubleValue = 50 + min(percentage * 0.5, 50)
                installationDetailLabel?.stringValue = MacOSVirtualMachineConfigurationHelper.localized("%d%% installed", Int(percentage))
            }
        } else if output.contains("Installation succeeded") {
            installationStatusLabel?.stringValue = MacOSVirtualMachineConfigurationHelper.localized("Installation complete")
            installationDetailLabel?.stringValue = MacOSVirtualMachineConfigurationHelper.localized("Open the existing VM.bundle at the selected location.")
            installationProgressIndicator?.doubleValue = 100
        }
    }

    private func progressPercentage(from output: String) -> Double? {
        let numericCharacterSet = CharacterSet(charactersIn: "0123456789.")
        let tokens = output.components(separatedBy: numericCharacterSet.inverted)
        return tokens.compactMap(Double.init).last
    }

    private func handleInstallationFinished(with terminationStatus: Int32) {
        guard terminationStatus == 0 else {
            showInstallationFailure(MacOSVirtualMachineConfigurationHelper.localized("The installation tool exited with status %d.", terminationStatus))
            return
        }

        finishInstallationAndRefreshSetupState()
    }

    private func finishInstallationAndRefreshSetupState() {
        isInstallationInProgress = false
        restoreImageDownloadObserver = nil
        macOSInstallationObserver = nil
        restoreImageDownloadSession?.finishTasksAndInvalidate()
        restoreImageDownloadSession = nil
        installationVirtualMachine = nil
        installationVirtualMachineResponder = nil
        installationProgressIndicator?.doubleValue = 100
        updateSetupStateForCurrentVMLocation()

        if !isVirtualMachineInstalled {
            showInstallationFailure(missingVirtualMachineFilesDescription())
        }
    }

    private func showInstallationFailure(_ message: String) {
        isInstallationInProgress = false
        restoreImageDownloadObserver = nil
        macOSInstallationObserver = nil
        restoreImageDownloadSession?.finishTasksAndInvalidate()
        restoreImageDownloadSession = nil
        installationVirtualMachine = nil
        installationVirtualMachineResponder = nil
        launchSpinner?.stopAnimation(nil)
        launchSpinner?.isHidden = true
        installationStatusLabel?.stringValue = MacOSVirtualMachineConfigurationHelper.localized("Installation failed")
        installationDetailLabel?.stringValue = message
        installationProgressIndicator?.doubleValue = 0
        installationProgressIndicator?.isHidden = true
        setSetupButtonTitle(MacOSVirtualMachineConfigurationHelper.localized("Retry Download and Install"), for: installButton)
        installButton?.isHidden = false
        installButton?.isEnabled = true
        memorySizePopUpButton?.isEnabled = true
        vmLocationButton?.isEnabled = true
        sharedFolderButton?.isEnabled = true
    }
#endif

    // MARK: Save the virtual machine when the app exits.

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }
    
#if arch(arm64)
    @available(macOS 14.0, *)
    func saveVirtualMachine(completionHandler: @escaping () -> Void) {
        virtualMachine.saveMachineStateTo(url: saveFileURL, completionHandler: { (error) in
            guard error == nil else {
                MacOSVirtualMachineConfigurationHelper.showErrorAndExit(self.virtualMachineErrorMessage(prefixKey: "Virtual machine failed to save with %@", error: error!))
            }

            completionHandler()
        })
    }

    @available(macOS 14.0, *)
    func pauseAndSaveVirtualMachine(completionHandler: @escaping () -> Void) {
        virtualMachine.pause(completionHandler: { (result) in
            if case let .failure(error) = result {
                MacOSVirtualMachineConfigurationHelper.showErrorAndExit(self.virtualMachineErrorMessage(prefixKey: "Virtual machine failed to pause with %@", error: error))
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
                pauseAndSaveVirtualMachine(completionHandler: {
                    sender.reply(toApplicationShouldTerminate: true)
                })
                
                return .terminateLater
            }
        }
#endif

        return .terminateNow
    }
}
