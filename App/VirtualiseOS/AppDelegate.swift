//
//  AppDelegate.swift
//  VirtualiseOS
//
//  Created by Daniel Mandea on 15.05.2025.
//  Copyright © 2026 M.T.D.Technology SRL. All rights reserved.
//

import Cocoa

final class AppDelegate: NSObject, NSApplicationDelegate {

    var coordinator: Coordinator?

    func applicationDidFinishLaunching(_ notification: Notification) {
#if arch(arm64)
        coordinator?.prepareVirtualMachineIfNeeded()
#endif
    }

    func applicationDidBecomeActive(_ notification: Notification) {
#if arch(arm64)
        coordinator?.applicationDidBecomeActive()
#endif
    }

    func applicationDidResignActive(_ notification: Notification) {
#if arch(arm64)
        coordinator?.applicationDidResignActive()
#endif
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
#if arch(arm64)
        return coordinator?.applicationShouldTerminate(sender) ?? .terminateNow
#else
        return .terminateNow
#endif
    }
}
