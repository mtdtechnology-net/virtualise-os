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
    @State private var hasAppeared = false
    @State private var isPulsing = false

    var body: some View {
        VStack {
            Spacer()
            Image("logo-virtualise-os")
                .resizable()
                .scaledToFit()
                .frame(width: 180, height: 88)
                .scaleEffect(hasAppeared ? 1 : 0.72)
                .opacity(hasAppeared ? 1 : 0)
                .shadow(color: .cardWhite.opacity(isPulsing ? 0.42 : 0.16), radius: isPulsing ? 26 : 10)
                .rotation3DEffect(
                    .degrees(hasAppeared ? 0 : -18),
                    axis: (x: 1, y: 0, z: 0),
                    perspective: 0.55
                )
                .animation(.spring(response: 0.8, dampingFraction: 0.68), value: hasAppeared)
                .animation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true), value: isPulsing)
            Text("Virtualize OS")
                .font(.title)
                .foregroundStyle(.cardWhite)
                .opacity(hasAppeared ? 1 : 0)
                .offset(y: hasAppeared ? 0 : 14)
                .animation(.easeOut(duration: 0.55).delay(0.24), value: hasAppeared)
            Spacer()
            HStack {
                Spacer()
                HStack {
                    Text("Powered by")
                        .font(.caption)
                        .foregroundStyle(.cardWhite)
                    Image("logo")
                        .resizable()
                        .scaledToFit()
                }
                .frame(height: 20)
                .opacity(hasAppeared ? 1 : 0)
                .offset(y: hasAppeared ? 0 : 8)
                .animation(.easeOut(duration: 0.45).delay(0.42), value: hasAppeared)
            }
        }
        .padding()
        .background(.accent)
        .onAppear {
            hasAppeared = true
            isPulsing = true
        }
    }
}

#Preview {
    SplashScreenView()
}
