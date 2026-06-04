//
//  SetupButtonStyle.swift
//  VirtualiseOS
//
//  Created by Daniel Mandea on 04/06/2026.
//  Copyright © 2026 Apple. All rights reserved.
//

import SwiftUI

struct SetupButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(.white)
            .padding(.horizontal, 18)
            .frame(minHeight: 34)
            .background(.white.opacity(configuration.isPressed ? 0.24 : 0.16), in: Capsule())
            .overlay {
                Capsule()
                    .stroke(.white.opacity(0.30), lineWidth: 1)
            }
    }
}
