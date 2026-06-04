//
//  MacOSVirtualMachineDelegate.swift
//  VirtualiseOS
//
//  Created by Daniel Mandea on 15.05.2025.
//  Copyright © 2026 M.T.D.Technology SRL. All rights reserved.
//

import Foundation
import Virtualization

class MacOSVirtualMachineDelegate: NSObject, VZVirtualMachineDelegate {
    var didStopWithErrorHandler: ((Error) -> Void)?
    var guestDidStopHandler: (() -> Void)?

    func virtualMachine(_ virtualMachine: VZVirtualMachine, didStopWithError error: Error) {
        NSLog("Virtual machine did stop with error: \(error.localizedDescription)")
        didStopWithErrorHandler?(error)
    }

    func guestDidStop(_ virtualMachine: VZVirtualMachine) {
        NSLog("Guest did stop virtual machine.")
        guestDidStopHandler?()
    }
}
