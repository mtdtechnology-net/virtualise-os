//
//  SetupViewModel.swift
//  VirtualiseOS
//
//  Created by Daniel Mandea on 15.05.2025.
//  Copyright © 2026 M.T.D.Technology SRL. All rights reserved.
//

import SwiftUI

final class SetupViewModel: ObservableObject {
    
    let memoryOptionsInGiB = [4, 6, 8, 12, 16, 24, 32]

    @Published var status: String
    @Published var detail: String
    @Published var actionTitle: String
    @Published var isActionHidden = false
    @Published var isActionEnabled = true
    @Published var areControlsEnabled = true
    @Published var isLaunchSpinnerVisible = false
    @Published var isProgressVisible = false
    @Published var progress = 0.0
    @Published var selectedMemorySizeInGiB: Int
    @Published var vmLocationDescription: String
    @Published var sharedFolderDescription: String

    var actionHandler: (() -> Void)?
    var chooseVMLocationHandler: (() -> Void)?
    var chooseSharedFolderHandler: (() -> Void)?
    var memorySelectionHandler: ((Int) -> Void)?

    init(status: String,
         detail: String,
         actionTitle: String,
         selectedMemorySizeInGiB: Int,
         vmLocationDescription: String,
         sharedFolderDescription: String) {
        self.status = status
        self.detail = detail
        self.actionTitle = actionTitle
        self.selectedMemorySizeInGiB = selectedMemorySizeInGiB
        self.vmLocationDescription = vmLocationDescription
        self.sharedFolderDescription = sharedFolderDescription
    }
}
