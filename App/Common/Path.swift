//
//  Path.swift
//  VirtualiseOS
//
//  Created by Daniel Mandea on 15.05.2025.
//  Copyright © 2026 M.T.D.Technology SRL. All rights reserved.
//

import Foundation

let vmBundleBookmarkUserDefaultsKey = "VMBundleBookmark"
let vmBundleParentDirectoryBookmarkUserDefaultsKey = "VMBundleParentDirectoryBookmark"

private let defaultApplicationSupportURL = FileManager.default
    .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    .appendingPathComponent("VirtualiseOS", isDirectory: true)

private var activeVMBundleURL: URL?

func setActiveVMBundleURL(_ url: URL?) {
    activeVMBundleURL = url
}

var applicationSupportURL: URL {
    if let selectedVMBundleURL {
        return selectedVMBundleURL.deletingLastPathComponent()
    }

    if let parentURL = selectedVMBundleParentURL {
        return parentURL
    }

    return defaultApplicationSupportURL
}

private var selectedVMBundleURL: URL? {
    guard let bookmarkData = UserDefaults.standard.data(forKey: vmBundleBookmarkUserDefaultsKey) else {
        return nil
    }

    do {
        var isStale = false
        let url = try URL(resolvingBookmarkData: bookmarkData,
                          options: [.withSecurityScope],
                          relativeTo: nil,
                          bookmarkDataIsStale: &isStale)

        if !isStale, url.startAccessingSecurityScopedResource() {
            activeVMBundleURL = url
            return normalizedVMBundleURL(from: url)
        }
    } catch {
        NSLog("Failed to resolve VM bundle bookmark: \(error.localizedDescription)")
    }

    return nil
}

private var selectedVMBundleParentURL: URL? {
    if let bookmarkData = UserDefaults.standard.data(forKey: vmBundleParentDirectoryBookmarkUserDefaultsKey) {
        do {
            var isStale = false
            let url = try URL(resolvingBookmarkData: bookmarkData,
                              options: [.withSecurityScope],
                              relativeTo: nil,
                              bookmarkDataIsStale: &isStale)

            if !isStale, url.startAccessingSecurityScopedResource() {
                return url
            }
        } catch {
            NSLog("Failed to resolve VM bundle parent bookmark: \(error.localizedDescription)")
        }
    }

    return nil
}

private func normalizedVMBundleURL(from url: URL) -> URL {
    if url.lastPathComponent == "VM.bundle" || url.pathExtension == "bundle" {
        return url
    }

    return url.appendingPathComponent("VM.bundle", isDirectory: true)
}

var vmBundleURL: URL {
    if let selectedVMBundleURL {
        return selectedVMBundleURL
    }

    return applicationSupportURL.appendingPathComponent("VM.bundle", isDirectory: true)
}

var vmBundlePath: String {
    vmBundleURL.path
}

var auxiliaryStorageURL: URL {
    vmBundleURL.appendingPathComponent("AuxiliaryStorage")
}

var diskImageURL: URL {
    vmBundleURL.appendingPathComponent("Disk.img")
}

var hardwareModelURL: URL {
    vmBundleURL.appendingPathComponent("HardwareModel")
}

var machineIdentifierURL: URL {
    vmBundleURL.appendingPathComponent("MachineIdentifier")
}

var macAddressURL: URL {
    vmBundleURL.appendingPathComponent("MACAddress")
}

var restoreImageURL: URL {
    vmBundleURL.appendingPathComponent("RestoreImage.ipsw")
}

var saveFileURL: URL {
    vmBundleURL.appendingPathComponent("SaveFile.vzvmsave")
}
