//
//  String+Localization.swift
//  VirtualiseOS
//
//  Created by Daniel Mandea on 04.06.2026.
//  Copyright © 2026 M.T.D.Technology SRL. All rights reserved.
//

import Foundation

private extension Bundle {
    static var module: Bundle { .main }
}

extension String {

    // MARK: - Return the localized String

    var localized: String { NSLocalizedString(self, bundle: .module, comment: "") }

    func localized(_ arguments: CVarArg...) -> String {
        String(format: localized, arguments: arguments)
    }
}
