//
//  VirtualMachineRow.swift
//  VirtualiseOS
//
//  Created by Daniel Mandea on 04/06/2026.
//  Copyright © 2026 Apple. All rights reserved.
//

import SwiftUI

#if arch(arm64)

struct VirtualMachineRow: View {
    
    // MARK: - Internal
    
    let profile: MachineProfile
    
    // MARK: - Environment
    
    @Environment(\.colorScheme) private var colorScheme
    
    // MARK: - View
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(osDisplayName)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(primaryTextStyle)
                    .lineLimit(1)
                
                Spacer()
                
                Circle()
                    .fill(profile.status.color)
                    .frame(width: 8, height: 8)
            }
            
            Text(profile.status.displayName)
                .font(.caption)
                .foregroundStyle(secondaryTextStyle)
            
        }
        .padding(.horizontal, isDarkMode ? 10 : 0)
        .padding(.vertical, isDarkMode ? 9 : 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(rowBackground)
        .clipShape(RoundedRectangle(cornerRadius: isDarkMode ? 8 : 0, style: .continuous))
        .listRowBackground(isDarkMode ? VirtualiseOSPalette.sidebarBackground : Color.clear)
    }
    
    private var osDisplayName: String {
        guard let osVersion = profile.osVersion, !osVersion.isEmpty else {
            return "macOS".localized
        }
        
        return osVersion
    }
    
    private var isDarkMode: Bool {
        colorScheme == .dark
    }
    
    private var rowBackground: Color {
        isDarkMode ? VirtualiseOSPalette.sidebarCellBackground : .clear
    }
    
    private var primaryTextStyle: Color {
        isDarkMode ? .white : .primary
    }
    
    private var secondaryTextStyle: Color {
        isDarkMode ? .white.opacity(0.72) : .secondary
    }
}

#Preview {
    VirtualMachineRow(
        profile:
            MachineProfile(
                name: "Machine 1",
                osVersion: "14.0.1",
                memorySizeInGiB: 30,
                diskSizeInGiB: 230,
                vmBundlePath: "/Downloads/Virtual Machines/Virtual Machines/Virtual Machines.vm"
            )
    )
}

#endif
