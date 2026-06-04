//
//  BundleStatus.swift
//  VirtualiseOS
//
//  Created by Daniel Mandea on 04/06/2026.
//  Copyright © 2026 Apple. All rights reserved.
//

enum BundleStatus: String, Codable, CaseIterable {
    case notInstalled
    case incomplete
    case installing
    case installed
    case starting
    case running
    case stopped
    case failed
    
    var displayName: String {
        switch self {
        case .notInstalled:
            return MachineConfigurationHelper.localized("Not installed")
        case .incomplete:
            return MachineConfigurationHelper.localized("Incomplete")
        case .installing:
            return MachineConfigurationHelper.localized("Installing")
        case .installed:
            return MachineConfigurationHelper.localized("Ready")
        case .starting:
            return MachineConfigurationHelper.localized("Starting")
        case .running:
            return MachineConfigurationHelper.localized("Running")
        case .stopped:
            return MachineConfigurationHelper.localized("Stopped")
        case .failed:
            return MachineConfigurationHelper.localized("Failed")
        }
    }
}
