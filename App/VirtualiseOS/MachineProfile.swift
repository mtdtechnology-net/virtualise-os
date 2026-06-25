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
    var restoreImageURLString: String?
    var memorySizeInGiB: Int
    var diskSizeInGiB: Int
    var vmBundlePath: String
    var vmBundleBookmarkData: Data?
    var sharedFolderPath: String?
    var sharedFolderBookmarkData: Data?
    var status: BundleStatus
    var installProgress: Double
    var statusDetail: String
    var portForwarding: PortForwardingConfiguration

    init(id: UUID = UUID(),
         name: String,
         createdAt: Date = Date(),
         osVersion: String? = nil,
         restoreImageURLString: String? = nil,
         memorySizeInGiB: Int,
         diskSizeInGiB: Int,
         vmBundlePath: String,
         vmBundleBookmarkData: Data? = nil,
         sharedFolderPath: String? = nil,
         sharedFolderBookmarkData: Data? = nil,
         status: BundleStatus = .notInstalled,
         installProgress: Double = 0,
         statusDetail: String = "",
         portForwarding: PortForwardingConfiguration = .disabled) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.osVersion = osVersion
        self.restoreImageURLString = restoreImageURLString
        self.memorySizeInGiB = memorySizeInGiB
        self.diskSizeInGiB = diskSizeInGiB
        self.vmBundlePath = vmBundlePath
        self.vmBundleBookmarkData = vmBundleBookmarkData
        self.sharedFolderPath = sharedFolderPath
        self.sharedFolderBookmarkData = sharedFolderBookmarkData
        self.status = status
        self.installProgress = installProgress
        self.statusDetail = statusDetail
        self.portForwarding = portForwarding
    }

    init(record: ProfileRecord) {
        self.init(id: record.id,
                  name: record.name,
                  createdAt: record.createdAt,
                  osVersion: record.osVersion,
                  restoreImageURLString: record.restoreImageURLString,
                  memorySizeInGiB: record.memorySizeInGiB,
                  diskSizeInGiB: record.diskSizeInGiB,
                  vmBundlePath: record.vmBundlePath,
                  vmBundleBookmarkData: record.vmBundleBookmarkData,
                  sharedFolderPath: record.sharedFolderPath,
                  sharedFolderBookmarkData: record.sharedFolderBookmarkData,
                  status: BundleStatus(rawValue: record.statusRawValue) ?? .notInstalled,
                  installProgress: record.installProgress,
                  statusDetail: record.statusDetail,
                  portForwarding: PortForwardingConfiguration(record: record))
    }

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case createdAt
        case osVersion
        case restoreImageURLString
        case memorySizeInGiB
        case diskSizeInGiB
        case vmBundlePath
        case vmBundleBookmarkData
        case sharedFolderPath
        case sharedFolderBookmarkData
        case status
        case installProgress
        case statusDetail
        case portForwarding
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(id: try container.decode(UUID.self, forKey: .id),
                  name: try container.decode(String.self, forKey: .name),
                  createdAt: try container.decode(Date.self, forKey: .createdAt),
                  osVersion: try container.decodeIfPresent(String.self, forKey: .osVersion),
                  restoreImageURLString: try container.decodeIfPresent(String.self, forKey: .restoreImageURLString),
                  memorySizeInGiB: try container.decode(Int.self, forKey: .memorySizeInGiB),
                  diskSizeInGiB: try container.decode(Int.self, forKey: .diskSizeInGiB),
                  vmBundlePath: try container.decode(String.self, forKey: .vmBundlePath),
                  vmBundleBookmarkData: try container.decodeIfPresent(Data.self, forKey: .vmBundleBookmarkData),
                  sharedFolderPath: try container.decodeIfPresent(String.self, forKey: .sharedFolderPath),
                  sharedFolderBookmarkData: try container.decodeIfPresent(Data.self, forKey: .sharedFolderBookmarkData),
                  status: try container.decode(BundleStatus.self, forKey: .status),
                  installProgress: try container.decode(Double.self, forKey: .installProgress),
                  statusDetail: try container.decode(String.self, forKey: .statusDetail),
                  portForwarding: try container.decodeIfPresent(PortForwardingConfiguration.self, forKey: .portForwarding) ?? .disabled)
    }

    var vmBundleURL: URL {
        URL(fileURLWithPath: vmBundlePath)
    }

    var restoreImageURL: URL? {
        guard let restoreImageURLString else {
            return nil
        }

        return URL(string: restoreImageURLString)
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

struct PortForwardingConfiguration: Codable, Equatable {
    var isEnabled: Bool
    var hostPort: Int
    var guestAddress: String
    var guestPort: Int

    static let disabled = PortForwardingConfiguration(isEnabled: false,
                                                      hostPort: 2222,
                                                      guestAddress: "",
                                                      guestPort: 22)

    init(isEnabled: Bool = false,
         hostPort: Int = 2222,
         guestAddress: String = "",
         guestPort: Int = 22) {
        self.isEnabled = isEnabled
        self.hostPort = hostPort
        self.guestAddress = guestAddress
        self.guestPort = guestPort
    }

    init(record: ProfileRecord) {
        self.init(isEnabled: record.isPortForwardingEnabled,
                  hostPort: record.portForwardingHostPort,
                  guestAddress: record.portForwardingGuestAddress,
                  guestPort: record.portForwardingGuestPort)
    }

    var summary: String {
        guard isEnabled else {
            return "Disabled".localized
        }

        let hostAddress = PortForwarder.hostIPAddress ?? "this Mac".localized
        let hostEndpoint = "\(hostAddress):\(hostPort)"

        guard !guestAddress.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return "Host endpoint %@, waiting for guest IP address".localized(hostEndpoint)
        }

        return "%@ forwards to %@:%d".localized(hostEndpoint, guestAddress, guestPort)
    }
}
