//
//  MacOSRestoreImage.swift
//  VirtualiseOS
//
//  Created by Daniel Mandea on 15.05.2025.
//  Copyright © 2026 M.T.D.Technology SRL. All rights reserved.
//

import Foundation
import Virtualization

#if arch(arm64)

class MacOSRestoreImage: NSObject {
    private var downloadObserver: NSKeyValueObservation?

    // MARK: Observe the download progress.

    public func download(completionHandler: @escaping () -> Void) {
        NSLog("Attempting to download latest available restore image.")
        VZMacOSRestoreImage.fetchLatestSupported { [self](result: Result<VZMacOSRestoreImage, Error>) in
            switch result {
                case let .failure(error):
                    fatalError(error.localizedDescription)

                case let .success(restoreImage):
                    NSLog("Latest supported macOS restore image: \(restoreImage.operatingSystemVersion) (\(restoreImage.buildVersion)).")
                    downloadRestoreImage(restoreImage: restoreImage, completionHandler: completionHandler)
            }
        }
    }

    // MARK: Download the restore image from the network.

    private func downloadRestoreImage(restoreImage: VZMacOSRestoreImage, completionHandler: @escaping () -> Void) {
        let downloadTask = URLSession.shared.downloadTask(with: restoreImage.url) { localURL, response, error in
            if let error = error {
                fatalError("Download failed. \(error.localizedDescription).")
            }

            if FileManager.default.fileExists(atPath: restoreImageURL.path) {
                do {
                    try FileManager.default.removeItem(at: restoreImageURL)
                } catch {
                    fatalError("Failed to remove existing restore image at \(restoreImageURL).")
                }
            }

            guard (try? FileManager.default.moveItem(at: localURL!, to: restoreImageURL)) != nil else {
                fatalError("Failed to move downloaded restore image to \(restoreImageURL).")
            }

            completionHandler()
        }

        downloadObserver = downloadTask.progress.observe(\.fractionCompleted, options: [.initial, .new]) { (progress, change) in
            NSLog("Restore image download progress: \(change.newValue! * 100).")
        }
        downloadTask.resume()
    }
}

#endif
