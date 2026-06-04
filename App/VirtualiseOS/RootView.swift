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

    var body: some View {
        Group {
#if arch(arm64)
            VirtualMachineLibraryView(coordinator: coordinator)
                .onAppear {
                    coordinator.configurePersistence(modelContext: modelContext)
                    coordinator.prepareVirtualMachineIfNeeded()
                }
                .onChange(of: coordinator.virtualMachineWindowRequest) { _, _ in
                    openWindow(id: "virtual-machine")
                }
#else
            ZStack {
                Color.white.ignoresSafeArea()
                Text("VirtualiseOS requires Apple silicon.")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(.primary)
            }
#endif
        }
        .frame(minWidth: 960, minHeight: 600)
    }
}
