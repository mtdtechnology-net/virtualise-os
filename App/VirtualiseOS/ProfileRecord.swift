//
//  ProfileRecord.swift
//  VirtualiseOS
//
//  Created by Daniel Mandea on 04/06/2026.
//  Copyright © 2026 Apple. All rights reserved.
//

import Foundation
import SwiftData

@Model
final class ProfileRecord {
    @Attribute(.unique) var id: UUID
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
    var statusRawValue: String
    var installProgress: Double
    var statusDetail: String
    var isPortForwardingEnabled: Bool = false
    var portForwardingHostPort: Int = 2222
    var portForwardingGuestAddress: String = ""
    var portForwardingGuestPort: Int = 22
    
    init(profile: MachineProfile) {
        id = profile.id
        name = profile.name
        createdAt = profile.createdAt
        osVersion = profile.osVersion
        restoreImageURLString = profile.restoreImageURLString
        memorySizeInGiB = profile.memorySizeInGiB
        diskSizeInGiB = profile.diskSizeInGiB
        vmBundlePath = profile.vmBundlePath
        vmBundleBookmarkData = profile.vmBundleBookmarkData
        sharedFolderPath = profile.sharedFolderPath
        sharedFolderBookmarkData = profile.sharedFolderBookmarkData
        statusRawValue = profile.status.rawValue
        installProgress = profile.installProgress
        statusDetail = profile.statusDetail
        isPortForwardingEnabled = profile.portForwarding.isEnabled
        portForwardingHostPort = profile.portForwarding.hostPort
        portForwardingGuestAddress = profile.portForwarding.guestAddress
        portForwardingGuestPort = profile.portForwarding.guestPort
    }
    
    func apply(_ profile: MachineProfile) {
        name = profile.name
        createdAt = profile.createdAt
        osVersion = profile.osVersion
        restoreImageURLString = profile.restoreImageURLString
        memorySizeInGiB = profile.memorySizeInGiB
        diskSizeInGiB = profile.diskSizeInGiB
        vmBundlePath = profile.vmBundlePath
        vmBundleBookmarkData = profile.vmBundleBookmarkData
        sharedFolderPath = profile.sharedFolderPath
        sharedFolderBookmarkData = profile.sharedFolderBookmarkData
        statusRawValue = profile.status.rawValue
        installProgress = profile.installProgress
        statusDetail = profile.statusDetail
        isPortForwardingEnabled = profile.portForwarding.isEnabled
        portForwardingHostPort = profile.portForwarding.hostPort
        portForwardingGuestAddress = profile.portForwarding.guestAddress
        portForwardingGuestPort = profile.portForwarding.guestPort
    }
}
