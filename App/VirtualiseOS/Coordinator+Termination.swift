import Cocoa
import Foundation
#if arch(arm64)
import Virtualization
#endif

extension Coordinator {
    // MARK: Save the virtual machine when the app exits.

#if arch(arm64)
    @available(macOS 14.0, *)
    func saveVirtualMachine(completionHandler: @escaping () -> Void) {
        virtualMachine.saveMachineStateTo(url: saveFileURL, completionHandler: { (error) in
            guard error == nil else {
                MachineConfigurationHelper.showErrorAndExit(self.virtualMachineErrorMessage(prefixKey: "Virtual machine failed to save with %@", error: error!))
            }

            completionHandler()
        })
    }

    @available(macOS 14.0, *)
    func pauseAndSaveVirtualMachine(completionHandler: @escaping () -> Void) {
        virtualMachine.pause(completionHandler: { (result) in
            if case let .failure(error) = result {
                MachineConfigurationHelper.showErrorAndExit(self.virtualMachineErrorMessage(prefixKey: "Virtual machine failed to pause with %@", error: error))
            }

            self.saveVirtualMachine(completionHandler: completionHandler)
        })
    }
#endif

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
#if arch(arm64)
        if installationProcess != nil {
            installationProcess?.terminate()
            return .terminateNow
        }

        if #available(macOS 14.0, *) {
            if virtualMachine?.state == .running {
                pauseAndSaveVirtualMachine(completionHandler: { [weak self] in
                    self?.markSelectedProfileStoppedIfNeeded()
                    sender.reply(toApplicationShouldTerminate: true)
                })

                return .terminateLater
            }
        }
#endif

        markSelectedProfileStoppedIfNeeded()
        return .terminateNow
    }
}

#if arch(arm64)
extension Coordinator: URLSessionDownloadDelegate {}
#endif
