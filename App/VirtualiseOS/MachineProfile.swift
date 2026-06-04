//
//  MachineProfile.swift
//  VirtualiseOS
//
//  Created by Daniel Mandea on 04.06.2026.
//  Copyright © 2026 M.T.D.Technology SRL. All rights reserved.
//

import Foundation
import SwiftData

struct MachineProfile: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var createdAt: Date
    var osVersion: String?
    var memorySizeInGiB: Int
    var diskSizeInGiB: Int
    var vmBundlePath: String
    var vmBundleBookmarkData: Data?
    var sharedFolderPath: String?
    var sharedFolderBookmarkData: Data?
    var status: BundleStatus
    var installProgress: Double
    var statusDetail: String

    init(id: UUID = UUID(),
         name: String,
         createdAt: Date = Date(),
         osVersion: String? = nil,
         memorySizeInGiB: Int,
         diskSizeInGiB: Int,
         vmBundlePath: String,
         vmBundleBookmarkData: Data? = nil,
         sharedFolderPath: String? = nil,
         sharedFolderBookmarkData: Data? = nil,
         status: BundleStatus = .notInstalled,
         installProgress: Double = 0,
         statusDetail: String = "") {
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.osVersion = osVersion
        self.memorySizeInGiB = memorySizeInGiB
        self.diskSizeInGiB = diskSizeInGiB
        self.vmBundlePath = vmBundlePath
        self.vmBundleBookmarkData = vmBundleBookmarkData
        self.sharedFolderPath = sharedFolderPath
        self.sharedFolderBookmarkData = sharedFolderBookmarkData
        self.status = status
        self.installProgress = installProgress
        self.statusDetail = statusDetail
    }

    init(record: ProfileRecord) {
        self.init(id: record.id,
                  name: record.name,
                  createdAt: record.createdAt,
                  osVersion: record.osVersion,
                  memorySizeInGiB: record.memorySizeInGiB,
                  diskSizeInGiB: record.diskSizeInGiB,
                  vmBundlePath: record.vmBundlePath,
                  vmBundleBookmarkData: record.vmBundleBookmarkData,
                  sharedFolderPath: record.sharedFolderPath,
                  sharedFolderBookmarkData: record.sharedFolderBookmarkData,
                  status: BundleStatus(rawValue: record.statusRawValue) ?? .notInstalled,
                  installProgress: record.installProgress,
                  statusDetail: record.statusDetail)
    }

    var vmBundleURL: URL {
        URL(fileURLWithPath: vmBundlePath)
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

    var requiredFileURLs: [URL] {
        [auxiliaryStorageURL, diskImageURL, hardwareModelURL, machineIdentifierURL]
    }

    var isInstalledOnDisk: Bool {
        let fileManager = FileManager.default
        return ([vmBundleURL] + requiredFileURLs).allSatisfy { fileManager.fileExists(atPath: $0.path) }
    }

    var isBundlePresentOnDisk: Bool {
        FileManager.default.fileExists(atPath: vmBundleURL.path)
    }

    var missingFileNames: [String] {
        requiredFileURLs
            .filter { !FileManager.default.fileExists(atPath: $0.path) }
            .map(\.lastPathComponent)
    }
}

