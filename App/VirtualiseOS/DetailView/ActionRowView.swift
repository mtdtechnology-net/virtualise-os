//
//  ActionRowView.swift
//  VirtualiseOS-Swift
//
//  Created by Daniel Mandea on 07/06/2026.
//  Copyright © 2026 Apple. All rights reserved.
//

import SwiftUI

struct ActionRowView: View {
    
    // MARK: - Values
    
    var title: String
    var value: String
    var status: BundleStatus
    var action: () -> Void
    
    // MARK: - Body
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)
                Spacer()
                Button("Choose".localized, action: action)
                    .glassButtonStyle(prominent: true)
                    .tint(.blue)
                    .disabled(status == .running || status == .installing || status == .starting)
            }
            Text(value)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }
}

#Preview {
    ActionRowView(title: "VM Location", value: "/Users/danielmandea/Containers/XYZ", status: .installed) {
        
    }
    .padding()
}
