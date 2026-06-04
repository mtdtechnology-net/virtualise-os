//
//  CardModifier.swift
//  VirtualiseOS
//
//  Created by Daniel Mandea on 04/06/2026.
//  Copyright © 2026 Apple. All rights reserved.
//

import SwiftUI

struct CardModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .clipShape(.rect(cornerRadius: 12, style: .continuous))
            .shadow(color: Color.black.opacity(0.1), radius: 4, x: 0, y: 2)
    }
}
