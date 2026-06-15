//
//  LiquidGlassButtonStyle.swift
//  VirtualiseOS
//
//  Created by OpenAI on 16.06.2026.
//  Copyright © 2026 M.T.D.Technology SRL. All rights reserved.
//

import SwiftUI

extension View {
    @ViewBuilder
    func glassButtonStyle(prominent: Bool = false) -> some View {
        if #available(macOS 26.0, *) {
            if prominent {
                buttonStyle(.glassProminent)
            } else {
                buttonStyle(.glass)
            }
        } else {
            if prominent {
                buttonStyle(.borderedProminent)
            } else {
                buttonStyle(.bordered)
            }
        }
    }
}
