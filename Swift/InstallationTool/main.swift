/*
See the LICENSE.txt file for this sample’s licensing information.

Abstract:
The entry for `InstallationTool`.
*/

import Foundation

#if arch(arm64)

struct InstallationToolArguments {
    let ipswURL: URL?
    let diskImageSizeInGiB: UInt64
}

func printUsage() {
    NSLog("""
    Usage: InstallationTool [--disk-size-gib SIZE] [IPSW_PATH]

    Options:
      --disk-size-gib SIZE  Size of VM.bundle/Disk.img in GiB. Defaults to \(MacOSVirtualMachineInstaller.defaultDiskImageSizeInGiB).

    Omit IPSW_PATH to download and install the latest macOS restore image supported by this host.
    """)
}

func parseArguments(_ arguments: [String]) -> InstallationToolArguments? {
    var diskImageSizeInGiB = MacOSVirtualMachineInstaller.defaultDiskImageSizeInGiB
    var ipswPath: String?
    var index = 1

    while index < arguments.count {
        let argument = arguments[index]

        switch argument {
        case "--disk-size-gib", "--disk-size-gb":
            index += 1
            guard index < arguments.count,
                  let size = UInt64(arguments[index]),
                  size > 0 else {
                return nil
            }
            diskImageSizeInGiB = size

        case "--help", "-h":
            printUsage()
            exit(0)

        default:
            guard !argument.hasPrefix("-"), ipswPath == nil else {
                return nil
            }
            ipswPath = argument
        }

        index += 1
    }

    let ipswURL = ipswPath.map { URL(fileURLWithPath: $0) }
    return InstallationToolArguments(ipswURL: ipswURL, diskImageSizeInGiB: diskImageSizeInGiB)
}

guard let arguments = parseArguments(CommandLine.arguments) else {
    printUsage()
    exit(-1)
}

let installer = MacOSVirtualMachineInstaller(diskImageSizeInGiB: arguments.diskImageSizeInGiB)

installer.setUpVirtualMachineArtifacts()

if let ipswURL = arguments.ipswURL {
    installer.installMacOS(ipswURL: ipswURL)

    dispatchMain()
} else {
    let restoreImage = MacOSRestoreImage()
    restoreImage.download {
        // Install from the latest restore image that you downloaded.
        installer.installMacOS(ipswURL: restoreImageURL)
    }

    dispatchMain()
}

#else

NSLog("This tool can only be run on Apple Silicon Macs.")

#endif
