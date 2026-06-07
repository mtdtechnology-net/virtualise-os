//
//  MachineStatus.swift
//  VirtualiseOS-Swift
//
//  Created by Daniel Mandea on 07/06/2026.
//  Copyright © 2026 Apple. All rights reserved.
//

import SwiftUI

struct MachineStatus: View {
    
    // MARK: - State
    
    @State private var isPulsing = false
    
    // MARK: - Variables
    
    var status: BundleStatus
    
    // MARK: - Body
    
    var body: some View {
        HStack {
            Capsule()
                .fill(status.color.opacity(isPulsing ? 1.0 : 0.0))
                .frame(width: 10, height: 10)
                .overlay {
                    Capsule()
                        .stroke(status.color, lineWidth: 1)
                }
                .padding(.leading, 10)
                .animation(
                    .easeInOut(duration: 0.8).repeatForever(autoreverses: true),
                    value: isPulsing
                )
                .onAppear {
                    isPulsing = true
                }
            Text(status.displayName)
                .font(.system(size: 13, weight: .light))
                .padding(.trailing, 12)
                .padding(.vertical, 7)
        }
        .background(status.color.opacity(0.5), in: Capsule())
        .overlay {
            Capsule()
                .stroke(status.color, lineWidth: 1)
        }
        
    }
}

#Preview {
    ScrollView {
        MachineStatus(status: .failed)
            .padding(20)
        MachineStatus(status: .incomplete)
            .padding(20)
        MachineStatus(status: .notInstalled)
            .padding(20)
        MachineStatus(status: .running)
            .padding(20)
        MachineStatus(status: .stopped)
            .padding(20)
        MachineStatus(status: .starting)
            .padding(20)
    }
    
}
