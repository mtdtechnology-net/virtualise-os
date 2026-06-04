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
    var memorySizeInGiB: Int
    var diskSizeInGiB: Int
    var vmBundlePath: String
    var vmBundleBookmarkData: Data?
    var sharedFolderPath: String?
    var sharedFolderBookmarkData: Data?
    var statusRawValue: String
    var installProgress: Double
    var statusDetail: String
    
    init(profile: MachineProfile) {
        id = profile.id
        name = profile.name
        createdAt = profile.createdAt
        osVersion = profile.osVersion
        memorySizeInGiB = profile.memorySizeInGiB
        diskSizeInGiB = profile.diskSizeInGiB
        vmBundlePath = profile.vmBundlePath
        vmBundleBookmarkData = profile.vmBundleBookmarkData
        sharedFolderPath = profile.sharedFolderPath
        sharedFolderBookmarkData = profile.sharedFolderBookmarkData
        statusRawValue = profile.status.rawValue
        installProgress = profile.installProgress
        statusDetail = profile.statusDetail
    }
    
    func apply(_ profile: MachineProfile) {
        name = profile.name
        createdAt = profile.createdAt
        osVersion = profile.osVersion
        memorySizeInGiB = profile.memorySizeInGiB
        diskSizeInGiB = profile.diskSizeInGiB
        vmBundlePath = profile.vmBundlePath
        vmBundleBookmarkData = profile.vmBundleBookmarkData
        sharedFolderPath = profile.sharedFolderPath
        sharedFolderBookmarkData = profile.sharedFolderBookmarkData
        statusRawValue = profile.status.rawValue
        installProgress = profile.installProgress
        statusDetail = profile.statusDetail
    }
}

