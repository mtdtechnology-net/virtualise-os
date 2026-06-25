import Cocoa
import Foundation
#if arch(arm64)
import Virtualization
#endif

extension Coordinator {
#if arch(arm64)
    func downloadSelectedRestoreImageOrLatest() {
        if let selectedProfile,
           let restoreImageURL = selectedProfile.restoreImageURL {
            let osVersion = selectedProfile.osVersion ?? "Selected macOS".localized
            setupViewModel?.detail = "Selected macOS: %@".localized(osVersion)
            updateSelectedProfile(status: .installing,
                                  detail: "Selected macOS: %@".localized(osVersion),
                                  progress: 0,
                                  osVersion: selectedProfile.osVersion)
            downloadRestoreImage(from: restoreImageURL, osVersion: selectedProfile.osVersion)
            return
        }

        fetchLatestSupportedRestoreImage()
    }

    func fetchLatestSupportedRestoreImage() {
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
                    self.setupViewModel?.detail = "Latest supported macOS: %@".localized(osVersion)
                    self.updateSelectedProfile(status: .installing,
                                               detail: "Latest supported macOS: %@".localized(osVersion),
                                               progress: 0,
                                               osVersion: osVersion)
                    self.downloadRestoreImage(restoreImage)
                }
            }
        }
    }

    func foregroundRestoreImageDownloadSession() -> URLSession {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 300
        configuration.timeoutIntervalForResource = 24 * 60 * 60
        configuration.waitsForConnectivity = true
        configuration.allowsExpensiveNetworkAccess = true
        configuration.allowsConstrainedNetworkAccess = true

        return URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
    }

    func backgroundRestoreImageDownloadSession(for profileID: MachineProfile.ID) -> URLSession {
        let configuration = URLSessionConfiguration.background(withIdentifier: "\(restoreImageBackgroundSessionPrefix).\(profileID.uuidString)")
        configuration.timeoutIntervalForRequest = 300
        configuration.timeoutIntervalForResource = 24 * 60 * 60
        configuration.waitsForConnectivity = true
        configuration.isDiscretionary = false
        configuration.allowsExpensiveNetworkAccess = true
        configuration.allowsConstrainedNetworkAccess = true

        return URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
    }

    func restoreImageDownloadSession(for mode: RestoreImageDownloadMode, profileID: MachineProfile.ID) -> URLSession {
        switch mode {
        case .foreground:
            return foregroundRestoreImageDownloadSession()
        case .background:
            return backgroundRestoreImageDownloadSession(for: profileID)
        }
    }

    func reconnectBackgroundRestoreImageDownloadIfNeeded() {
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
                self?.showInstallationFailure("The background macOS download is no longer available. Start the download again.".localized)
            }
        }
    }

    func downloadRestoreImage(_ restoreImage: VZMacOSRestoreImage) {
        downloadRestoreImage(from: restoreImage.url,
                             osVersion: Self.restoreImageDisplayName(operatingSystemVersion: restoreImage.operatingSystemVersion,
                                                                     buildVersion: restoreImage.buildVersion))
    }

    func downloadRestoreImage(from url: URL, osVersion: String?) {
        setupViewModel?.status = "Downloading macOS restore image...".localized
        if let osVersion {
            setupViewModel?.detail = "Downloading %@.".localized(osVersion)
        } else {
            setupViewModel?.detail = "The download can continue in the background while VirtualiseOS remains open.".localized
        }

        let profileID = selectedProfileID ?? UUID()
        restoreImageDownloadProfileID = profileID

        startRestoreImageDownload(from: url, resumeData: nil, profileID: profileID, mode: .background)
    }

    func startRestoreImageDownload(
        from url: URL?,
        resumeData: Data?,
        profileID: MachineProfile.ID,
        mode: RestoreImageDownloadMode
    ) {
        let session = restoreImageDownloadSession(for: mode, profileID: profileID)
        let downloadTask: URLSessionDownloadTask

        if let resumeData {
            downloadTask = session.downloadTask(withResumeData: resumeData)
        } else if let url {
            downloadTask = session.downloadTask(with: url)
        } else {
            showInstallationFailure("The macOS download could not be resumed.".localized)
            return
        }

        downloadTask.countOfBytesClientExpectsToReceive = estimatedRestoreImageSizeInBytes
        restoreImageDownloadSession = session
        restoreImageDownloadTask = downloadTask
        if let url {
            restoreImageDownloadURL = url
        }
        restoreImageDownloadMode = mode
        restoreImageDownloadProfileID = profileID
        downloadTask.resume()
    }

    func switchRestoreImageDownloadModeIfNeeded(to mode: RestoreImageDownloadMode) {
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
                self.startRestoreImageDownload(from: self.restoreImageDownloadURL,
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
            self.restoreImageDownloadURL = nil
            self.restoreImageDownloadMode = nil
            self.restoreImageDownloadProfileID = nil
            self.showInstallationFailure("Download failed with error: %@".localized(error.localizedDescription))
        }
    }

    func updateRestoreImageDownloadProgress(_ percentage: Double, downloadedBytes: Int64, expectedBytes: Int64) {
        setupViewModel?.isProgressVisible = true
        setupViewModel?.progress = min(percentage * 0.5, 50)

        let downloadedGiB = Double(downloadedBytes) / 1024 / 1024 / 1024
        let detail: String
        if expectedBytes > 0 {
            detail = "%d%% downloaded (%.1f GB)".localized(Int(percentage), downloadedGiB)
        } else {
            detail = "%.1f GB downloaded".localized(downloadedGiB)
        }

        setupViewModel?.detail = detail
        updateSelectedProfile(status: .installing,
                              detail: detail,
                              progress: min(percentage * 0.5, 50))
    }

    func moveRestoreImageFromTemporaryLocation(_ location: URL) throws -> URL {
        let destinationURL = restoreImageURL
        let destinationDirectoryURL = destinationURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: destinationDirectoryURL, withIntermediateDirectories: true)

        if FileManager.default.fileExists(atPath: destinationURL.path) {
            try FileManager.default.removeItem(at: destinationURL)
        }

        try FileManager.default.moveItem(at: location, to: destinationURL)
        return destinationURL
    }

    func finishRestoreImageDownload(at downloadedRestoreImageURL: URL) {
        if let restoreImageDownloadProfileID,
           selectedProfileID != restoreImageDownloadProfileID,
           let profile = virtualMachineProfiles.first(where: { $0.id == restoreImageDownloadProfileID }) {
            selectProfile(profile)
        }

        restoreImageDownloadSession?.finishTasksAndInvalidate()
        restoreImageDownloadSession = nil
        restoreImageDownloadTask = nil
        restoreImageDownloadURL = nil
        restoreImageDownloadMode = nil
        restoreImageDownloadProfileID = nil
        installMacOS(from: downloadedRestoreImageURL)
    }
#endif
}
