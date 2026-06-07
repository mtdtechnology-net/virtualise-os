//
//  CardView.swift
//  VirtualiseOS-Swift
//
//  Created by Daniel Mandea on 07/06/2026.
//  Copyright © 2026 Apple. All rights reserved.
//

import SwiftUI

struct CardView: View {
    
    // MARK: - Items
    
    var title: String
    var subtitle: String
    var color: Color
    
    // MARK: Body
    
    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Text(title.uppercased())
                    .font(.caption)
                    .fontWeight(.medium)
                Text(subtitle)
                    .font(.title)
                    .fontWeight(.bold)
                    .padding([.bottom, .top], 5)
                Rectangle()
                    .fill(color)
                    .frame(height: 5)
                    .frame(maxWidth: .infinity)
                    .overlay {
                        Capsule()
                            .stroke(.white.opacity(0.30), lineWidth: 1)
                    }
            }
            .padding()
        }
        .background(Color("cardWhite"), in: .rect(cornerRadius: 16, style: .continuous))
        .modifier(CardModifier())
    }
}

// MARK: - Preview

#Preview {
    CardView(title: "memory", subtitle: "4GB", color: .blue)
        .padding()
}
