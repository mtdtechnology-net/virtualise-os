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
            return MacOSVirtualMachineConfigurationHelper.localized("Not installed")
        case .incomplete:
            return MacOSVirtualMachineConfigurationHelper.localized("Incomplete")
        case .installing:
            return MacOSVirtualMachineConfigurationHelper.localized("Installing")
        case .installed:
            return MacOSVirtualMachineConfigurationHelper.localized("Ready")
        case .starting:
            return MacOSVirtualMachineConfigurationHelper.localized("Starting")
        case .running:
            return MacOSVirtualMachineConfigurationHelper.localized("Running")
        case .stopped:
            return MacOSVirtualMachineConfigurationHelper.localized("Stopped")
        case .failed:
            return MacOSVirtualMachineConfigurationHelper.localized("Failed")
        }
    }
}
