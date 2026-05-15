//
//  Path.swift
//  VirtualiseOS
//
//  Created by Daniel Mandea on 15.05.2025.
//  Copyright © 2026 M.T.D.Technology SRL. All rights reserved.
//

import Foundation

let vmBundlePath = NSHomeDirectory() + "/VM.bundle/"

let vmBundleURL = URL(fileURLWithPath: vmBundlePath)

let auxiliaryStorageURL = vmBundleURL.appendingPathComponent("AuxiliaryStorage")

let diskImageURL = vmBundleURL.appendingPathComponent("Disk.img")

let hardwareModelURL = vmBundleURL.appendingPathComponent("HardwareModel")

let machineIdentifierURL = vmBundleURL.appendingPathComponent("MachineIdentifier")

let restoreImageURL = vmBundleURL.appendingPathComponent("RestoreImage.ipsw")

let saveFileURL = vmBundleURL.appendingPathComponent("SaveFile.vzvmsave")
