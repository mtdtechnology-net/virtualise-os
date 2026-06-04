//
//  SplashScreenView.swift
//  VirtualiseOS-Swift
//
//  Created by Daniel Mandea on 04/06/2026.
//  Copyright © 2026 Apple. All rights reserved.
//

import Foundation
import SwiftUI

struct SplashScreenView: View {
    var body: some View {
        ZStack {
            Color.accentColor.ignoresSafeArea()
            
            VStack(spacing: 0) {
                Image("logo-virtualise-os")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 180, height: 88)
                HStack {
                    Text("Powered by")
                        .font(.caption)
                    Image("logo")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 60
                               , height: 88)
                }
                
                
                ProgressView()
                    .controlSize(.small)
                    .tint(.blue)
            }
        }
    }
}

#Preview {
    SplashScreenView()
}
