//
//  SetupView.swift
//  VirtualiseOS
//
//  Created by Daniel Mandea on 04/06/2026.
//  Copyright © 2026 Apple. All rights reserved.
//

import SwiftUI

struct SetupView: View {
    @ObservedObject var model: SetupViewModel
    
    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Color("backgroundColor")
                .ignoresSafeArea()
            
            VStack(spacing: 18) {
                Text(MacOSVirtualMachineConfigurationHelper.localized("Preparing VirtualiseOS"))
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(.white)
                
                Text(model.status)
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                
                Text(model.detail)
                    .font(.system(size: 14))
                    .foregroundStyle(.white.opacity(0.72))
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                    .frame(width: 420)
                
                if model.isLaunchSpinnerVisible {
                    ProgressView()
                        .controlSize(.large)
                        .tint(.white)
                }
                
                settingsRows
                
                if !model.isActionHidden {
                    Button(model.actionTitle) {
                        model.actionHandler?()
                    }
                    .buttonStyle(SetupButtonStyle())
                    .disabled(!model.isActionEnabled)
                    .frame(minWidth: 260, minHeight: 36)
                }
                
                if model.isProgressVisible {
                    ProgressView(value: model.progress, total: 100)
                        .progressViewStyle(.linear)
                        .tint(.white)
                        .frame(width: 420)
                }
            }
            .padding(.vertical, 44)
            .padding(.horizontal, 48)
            .frame(width: 560)
            .background(.white.opacity(0.10), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(.white.opacity(0.18), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.18), radius: 24, y: 8)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            
            Image("logo")
                .resizable()
                .scaledToFit()
                .frame(width: 120, height: 56)
                .padding(.trailing, 28)
                .padding(.bottom, 24)
        }
    }
    
    private var settingsRows: some View {
        VStack(spacing: 16) {
            HStack {
                Text(MacOSVirtualMachineConfigurationHelper.localized("Memory"))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white)
                
                Spacer()
                
                Picker("", selection: $model.selectedMemorySizeInGiB) {
                    ForEach(model.memoryOptionsInGiB, id: \.self) { memorySizeInGiB in
                        Text(MacOSVirtualMachineConfigurationHelper.localized("%d GB", memorySizeInGiB))
                            .tag(memorySizeInGiB)
                    }
                }
                .labelsHidden()
                .frame(width: 160)
                .disabled(!model.areControlsEnabled)
                .onChange(of: model.selectedMemorySizeInGiB) { _, newValue in
                    model.memorySelectionHandler?(newValue)
                }
            }
            .frame(width: 420)
            
            setupLocationRow(title: MacOSVirtualMachineConfigurationHelper.localized("VM Location"),
                             path: model.vmLocationDescription,
                             action: { model.chooseVMLocationHandler?() })
            
            setupLocationRow(title: MacOSVirtualMachineConfigurationHelper.localized("Shared Folder"),
                             path: model.sharedFolderDescription,
                             action: { model.chooseSharedFolderHandler?() })
        }
    }
    
    private func setupLocationRow(title: String, path: String, action: @escaping () -> Void) -> some View {
        VStack(spacing: 6) {
            HStack {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white)
                
                Spacer()
                
                Button(MacOSVirtualMachineConfigurationHelper.localized("Choose Folder..."), action: action)
                    .buttonStyle(SetupButtonStyle())
                    .disabled(!model.areControlsEnabled)
                    .frame(width: 168, height: 34)
            }
            
            Text(path)
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.72))
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity)
        }
        .frame(width: 420)
    }
}
