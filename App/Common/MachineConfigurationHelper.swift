//
//  MachineConfigurationHelper.swift
//  VirtualiseOS
//
//  Created by Daniel Mandea on 15.05.2025.
//  Copyright © 2026 M.T.D.Technology SRL. All rights reserved.
//

import Foundation
#if canImport(AppKit)
import AppKit
#endif
#if arch(arm64)
import Virtualization
#endif

struct MachineConfigurationHelper {
    static let memorySizeInGiBUserDefaultsKey = "VirtualMachineMemorySizeInGiB"
    static let sharedDirectoryBookmarkUserDefaultsKey = "SharedDirectoryBookmark"
    static let defaultMemorySizeInGiB = 4

    private static var activeSharedDirectoryURL: URL?

    static func showErrorAndExit(_ message: String) -> Never {
        NSLog(message)

#if canImport(AppKit)
        if Bundle.main.bundleURL.pathExtension == "app" {
            let showAlert = {
                let alert = NSAlert()
                alert.messageText = "VirtualiseOS Error".localized
                alert.informativeText = message
                alert.alertStyle = .critical
                alert.addButton(withTitle: "Quit".localized)
                alert.runModal()
            }

            if Thread.isMainThread {
                showAlert()
            } else {
                DispatchQueue.main.sync(execute: showAlert)
            }
        }
#endif

        exit(EXIT_FAILURE)
    }

#if arch(arm64)
    static func computeCPUCount() -> Int {
        let totalAvailableCPUs = ProcessInfo.processInfo.processorCount
        var virtualCPUCount = totalAvailableCPUs <= 1 ? 1 : totalAvailableCPUs - 1
        virtualCPUCount = max(virtualCPUCount, VZVirtualMachineConfiguration.minimumAllowedCPUCount)
        virtualCPUCount = min(virtualCPUCount, VZVirtualMachineConfiguration.maximumAllowedCPUCount)

        return virtualCPUCount
    }

    static func computeMemorySize() -> UInt64 {
        let configuredMemorySizeInGiB = UserDefaults.standard.integer(forKey: memorySizeInGiBUserDefaultsKey)
        let memorySizeInGiB = configuredMemorySizeInGiB > 0 ? configuredMemorySizeInGiB : defaultMemorySizeInGiB
        var memorySize = UInt64(memorySizeInGiB) * 1024 * 1024 * 1024
        memorySize = max(memorySize, VZVirtualMachineConfiguration.minimumAllowedMemorySize)
        memorySize = min(memorySize, VZVirtualMachineConfiguration.maximumAllowedMemorySize)

        return memorySize
    }

    static func createBootLoader() -> VZMacOSBootLoader {
        return VZMacOSBootLoader()
    }

    static func createBlockDeviceConfiguration() -> VZVirtioBlockDeviceConfiguration {
        guard let diskImageAttachment = try? VZDiskImageStorageDeviceAttachment(url: diskImageURL, readOnly: false) else {
            showErrorAndExit("Failed to create Disk image.".localized)
        }
        let disk = VZVirtioBlockDeviceConfiguration(attachment: diskImageAttachment)
        return disk
    }

    static func createDirectorySharingDeviceConfiguration() -> VZVirtioFileSystemDeviceConfiguration? {
        guard let sharedDirectoryURL = resolvedSharedDirectoryURL() else {
            return nil
        }

        let sharedDirectory = VZSharedDirectory(url: sharedDirectoryURL, readOnly: false)
        let singleDirectoryShare = VZSingleDirectoryShare(directory: sharedDirectory)
        let sharingConfiguration = VZVirtioFileSystemDeviceConfiguration(tag: VZVirtioFileSystemDeviceConfiguration.macOSGuestAutomountTag)
        sharingConfiguration.share = singleDirectoryShare

        return sharingConfiguration
    }

    static func createGraphicsDeviceConfiguration() -> VZMacGraphicsDeviceConfiguration {
        let graphicsConfiguration = VZMacGraphicsDeviceConfiguration()
        graphicsConfiguration.displays = [
            // The system arbitrarily chooses the resolution of the display to be 1920 x 1200.
            VZMacGraphicsDisplayConfiguration(widthInPixels: 1920, heightInPixels: 1200, pixelsPerInch: 80)
        ]

        return graphicsConfiguration
    }

    static func createNetworkDeviceConfiguration() -> VZVirtioNetworkDeviceConfiguration {
        let networkDevice = VZVirtioNetworkDeviceConfiguration()
        networkDevice.macAddress = persistedMACAddress()

        let networkAttachment = VZNATNetworkDeviceAttachment()
        networkDevice.attachment = networkAttachment

        return networkDevice
    }

    private static func resolvedSharedDirectoryURL() -> URL? {
        guard let bookmarkData = UserDefaults.standard.data(forKey: sharedDirectoryBookmarkUserDefaultsKey) else {
            return nil
        }

        do {
            var isStale = false
            let url = try URL(resolvingBookmarkData: bookmarkData,
                              options: [.withSecurityScope],
                              relativeTo: nil,
                              bookmarkDataIsStale: &isStale)

            guard !isStale, url.startAccessingSecurityScopedResource() else {
                return nil
            }

            activeSharedDirectoryURL = url
            return url
        } catch {
            NSLog("Failed to resolve shared directory bookmark: \(error.localizedDescription)")
            return nil
        }
    }

    private static func persistedMACAddress() -> VZMACAddress {
        if let savedAddress = try? String(contentsOf: macAddressURL, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines),
           let macAddress = VZMACAddress(string: savedAddress) {
            return macAddress
        }

        let generatedAddress = generateLocalUnicastMACAddress()
        try? generatedAddress.write(to: macAddressURL, atomically: true, encoding: .utf8)

        guard let macAddress = VZMACAddress(string: generatedAddress) else {
            showErrorAndExit("Failed to create generated MAC address.".localized)
        }

        return macAddress
    }

    private static func generateLocalUnicastMACAddress() -> String {
        let bytes = [UInt8(0x02)] + (0..<5).map { _ in UInt8.random(in: 0...255) }
        return bytes.map { String(format: "%02x", $0) }.joined(separator: ":")
    }

    static func createSoundDeviceConfiguration() -> VZVirtioSoundDeviceConfiguration {
        let audioConfiguration = VZVirtioSoundDeviceConfiguration()

        let inputStream = VZVirtioSoundDeviceInputStreamConfiguration()
        inputStream.source = VZHostAudioInputStreamSource()

        let outputStream = VZVirtioSoundDeviceOutputStreamConfiguration()
        outputStream.sink = VZHostAudioOutputStreamSink()

        audioConfiguration.streams = [inputStream, outputStream]
        return audioConfiguration
    }

    static func createPointingDeviceConfiguration() -> VZPointingDeviceConfiguration {
        return VZMacTrackpadConfiguration()
    }

    static func createKeyboardConfiguration() -> VZKeyboardConfiguration {
        if #available(macOS 14.0, *) {
            return VZMacKeyboardConfiguration()
        } else {
            return VZUSBKeyboardConfiguration()
        }
    }
#endif
}
