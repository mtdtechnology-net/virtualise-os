//
//  RootView.swift
//  VirtualiseOS
//
//  Created by Daniel Mandea on 04.06.2026.
//  Copyright © 2026 M.T.D.Technology SRL. All rights reserved.
//

import SwiftData
import SwiftUI

struct RootView: View {
    @ObservedObject var coordinator: Coordinator
    @Environment(\.openWindow) private var openWindow
    @Environment(\.modelContext) private var modelContext
    @State private var isShowingSplash = true
    @State private var didPrepare = false

    var body: some View {
        ZStack {
            Group {
#if arch(arm64)
                VirtualMachineLibraryView(coordinator: coordinator)
                    .onAppear {
                        prepareIfNeeded()
                    }
                    .onChange(of: coordinator.virtualMachineWindowRequest) { _, _ in
                        openWindow(id: "virtual-machine")
                    }
#else
                ZStack {
                    Color.white.ignoresSafeArea()
                    Text("VirtualiseOS requires Apple silicon.")
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(.white)
                }
#endif
            }

            if isShowingSplash {
                SplashScreenView()
                    .transition(.opacity)
                    .zIndex(10)
            }
        }
        .animation(.easeOut(duration: 0.25), value: isShowingSplash)
        .task {
#if !arch(arm64)
            try? await Task.sleep(nanoseconds: 900_000_000)
            await MainActor.run {
                isShowingSplash = false
            }
#endif
        }
        .frame(minWidth: 960, minHeight: 600)
    }

#if arch(arm64)
    private func prepareIfNeeded() {
        guard !didPrepare else {
            return
        }

        didPrepare = true
        coordinator.configurePersistence(modelContext: modelContext)
        coordinator.prepareVirtualMachineIfNeeded()

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 900_000_000)
            isShowingSplash = false
        }
    }
#endif
}

private struct SplashScreenView: View {
    var body: some View {
        ZStack {
            Color.accentColor.ignoresSafeArea()

            VStack(spacing: 22) {
                Image("logo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 180, height: 88)

                Text("VirtualiseOS")
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundStyle(.white)

                ProgressView()
                    .controlSize(.large)
                    .tint(.blue)
            }
        }
    }
}
