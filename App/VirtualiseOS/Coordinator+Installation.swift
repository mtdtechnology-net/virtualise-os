import Cocoa
import Foundation
#if arch(arm64)
import Virtualization
#endif

extension Coordinator {
#if arch(arm64)
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

    @objc func downloadAndInstallLatestMacOS() {
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
                              detail: "Preparing installation.".localized,
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
        setupViewModel?.status = "Canceling installation...".localized
        setupViewModel?.detail = "Stopping the current download or installer.".localized
        setupViewModel?.isCancelActionEnabled = false

        restoreImageDownloadTask?.cancel()
        restoreImageDownloadSession?.invalidateAndCancel()
        restoreImageDownloadObserver = nil
        restoreImageDownloadTask = nil
        restoreImageDownloadURL = nil
        restoreImageDownloadMode = nil
        restoreImageDownloadProfileID = nil
        restoreImageDownloadSession = nil

        macOSInstaller?.progress.cancel()
        installationProcess?.terminate()

        completeInstallationCancellation()
    }

    func completeInstallationCancellation() {
        isInstallationInProgress = false
        restoreImageDownloadObserver = nil
        restoreImageDownloadProfileID = nil
        restoreImageDownloadTask = nil
        restoreImageDownloadURL = nil
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
                              detail: "Installation was canceled. Delete the VM or start installation again.".localized,
                              progress: 0)
        updateSetupStateForCurrentVMLocation()
    }

    func startInAppInstallation() {
        do {
            try removeIncompleteVirtualMachineBundleIfNeeded()
            try FileManager.default.createDirectory(at: vmBundleURL, withIntermediateDirectories: true)
        } catch {
            showInstallationFailure(error.localizedDescription)
            return
        }

        setupViewModel?.isActionHidden = true
        setupViewModel?.status = "Preparing macOS restore image...".localized
        setupViewModel?.detail = "VirtualiseOS will download the selected macOS restore image.".localized
        setupViewModel?.progress = 0

        downloadSelectedRestoreImageOrLatest()
    }
#endif
}
