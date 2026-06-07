//
//  DisplayView.swift
//  VirtualiseOS
//
//  Created by Daniel Mandea on 04.06.2026.
//  Copyright © 2026 M.T.D.Technology SRL. All rights reserved.
//

import SwiftUI

#if arch(arm64)
import Virtualization

struct DisplayView: NSViewRepresentable {
    let virtualMachine: VZVirtualMachine

    func makeNSView(context: Context) -> FocusableVirtualMachineView {
        let view = FocusableVirtualMachineView()
        configure(view)
        view.virtualMachine = virtualMachine
        view.activateConsoleInputWhenReady()
        return view
    }

    func updateNSView(_ nsView: FocusableVirtualMachineView, context: Context) {
        configure(nsView)
        nsView.virtualMachine = virtualMachine
        nsView.activateConsoleInputWhenReady()
    }

    static func dismantleNSView(_ nsView: FocusableVirtualMachineView, coordinator: ()) {
        nsView.virtualMachine = nil
    }

    private func configure(_ view: VZVirtualMachineView) {
        view.capturesSystemKeys = true

        if #available(macOS 14.0, *) {
            view.automaticallyReconfiguresDisplay = true
        }
    }
}

final class FocusableVirtualMachineView: VZVirtualMachineView {
    private let shouldLogKeyboardEvents = ProcessInfo.processInfo.arguments.contains("--log-vm-keyboard-events")

    override var acceptsFirstResponder: Bool {
        true
    }

    override func becomeFirstResponder() -> Bool {
        true
    }

    override func resignFirstResponder() -> Bool {
        true
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        activateConsoleInputWhenReady()
    }

    override func mouseDown(with event: NSEvent) {
        activateConsoleInput()
        super.mouseDown(with: event)
    }

    override func rightMouseDown(with event: NSEvent) {
        activateConsoleInput()
        super.rightMouseDown(with: event)
    }

    override func otherMouseDown(with event: NSEvent) {
        activateConsoleInput()
        super.otherMouseDown(with: event)
    }

    override func keyDown(with event: NSEvent) {
        logKeyboardEvent("keyDown", event: event)
        super.keyDown(with: event)
    }

    override func keyUp(with event: NSEvent) {
        logKeyboardEvent("keyUp", event: event)
        super.keyUp(with: event)
    }

    override func flagsChanged(with event: NSEvent) {
        logKeyboardEvent("flagsChanged", event: event)
        super.flagsChanged(with: event)
    }

    func activateConsoleInputWhenReady() {
        DispatchQueue.main.async { [weak self] in
            self?.activateConsoleInput()
        }
    }

    private func activateConsoleInput() {
        guard let window else {
            return
        }

        if !window.isKeyWindow {
            window.makeKey()
        }

        if window.firstResponder !== self {
            window.makeFirstResponder(self)
        }
    }

    private func logKeyboardEvent(_ name: String, event: NSEvent) {
        guard shouldLogKeyboardEvents else {
            return
        }

        NSLog("VM %@: keyCode=%d chars=%@ modifiers=%llu repeat=%@",
              name,
              event.keyCode,
              event.characters ?? "",
              event.modifierFlags.rawValue,
              event.isARepeat ? "true" : "false")
    }
}

#endif
