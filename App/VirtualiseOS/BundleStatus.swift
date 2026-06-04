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
            return "Not installed".localized
        case .incomplete:
            return "Incomplete".localized
        case .installing:
            return "Installing".localized
        case .installed:
            return "Ready".localized
        case .starting:
            return "Starting".localized
        case .running:
            return "Running".localized
        case .stopped:
            return "Stopped".localized
        case .failed:
            return "Failed".localized
        }
    }
}
