//
//  VirtualiseOSPalette.swift
//  VirtualiseOS
//
//  Created by Daniel Mandea on 04/06/2026.
//  Copyright © 2026 Apple. All rights reserved.
//

import SwiftUI

#if arch(arm64)

enum VirtualiseOSPalette {
    static let sidebarBackground = Color(hex: 0x1B1B1B)
    static let sidebarCellBackground = Color(hex: 0x333333)
    static let detailBackground = Color(hex: 0x292A2F)
    static let detailPanelBackground = Color(hex: 0x404045)
}

extension Color {
    init(hex: UInt32) {
        let red = Double((hex >> 16) & 0xFF) / 255
        let green = Double((hex >> 8) & 0xFF) / 255
        let blue = Double(hex & 0xFF) / 255
        self.init(red: red, green: green, blue: blue)
    }
}
#endif
