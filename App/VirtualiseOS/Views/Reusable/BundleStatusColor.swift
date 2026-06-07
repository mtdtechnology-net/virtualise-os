//
//  BundleStatusColor.swift
//  VirtualiseOS
//
//  Created by Daniel Mandea on 07/06/2026.
//  Copyright © 2026 Apple. All rights reserved.
//

import SwiftUI

extension BundleStatus {
    var color: Color {
        switch self {
        case .running:
            return .green
        case .installing, .starting:
            return .blue
        case .failed:
            return .orange
        case .incomplete:
            return .yellow
        case .installed:
            return .gray
        case .stopped:
            return .red
        case .notInstalled:
            return .secondary
        }
    }
}

#Preview {
    ForEach(BundleStatus.allCases, id: \.self) { value in
        HStack {
            Text("Helo World")
                .tint(value.color)
                .padding(20)
                .border(value.color)
                .padding(20)
        }
    }
}
