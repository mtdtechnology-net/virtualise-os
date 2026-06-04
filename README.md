# VirtualiseOS

![CI](https://github.com/mtdtechnology-net/virtualization-macos/actions/workflows/ci.yml/badge.svg)
![CD](https://github.com/mtdtechnology-net/virtualization-macos/actions/workflows/cd.yml/badge.svg)
![License](https://img.shields.io/badge/license-Apache--2.0-blue.svg)

VirtualiseOS is a macOS app for creating, installing, and running macOS virtual machines on Apple silicon using Apple's Virtualization framework.

It started from Apple's macOS virtual machine sample and has grown into a SwiftUI app with multiple VM profiles, a VM library, restore image download/install flow, shared folder support, localization, and CI/CD packaging.

## Features

- Create and manage multiple macOS VM profiles.
- Download the latest supported macOS restore image exposed by the Virtualization framework.
- Install macOS into a selected `VM.bundle` location.
- Configure VM memory, disk size, and an optional shared host folder.
- Start, stop, and track VM status from a SwiftUI library/detail interface.
- Persist VM profile metadata with SwiftData.
- Package releases as macOS DMG artifacts through GitHub Actions.

## Requirements

- Apple silicon Mac for VM installation and runtime.
- macOS 14 or later for the app target.
- Xcode with the macOS 14 SDK or newer.
- SwiftLint, for local linting.

The project includes non-arm64 guards so it can build the app shell on other Macs, but Virtualization features that run macOS guests require Apple silicon.

## Getting Started

Clone the repository:

```sh
git clone https://github.com/mtdtechnology-net/virtualization-macos.git
cd virtualization-macos
```

Open the project:

```sh
open VirtualiseOS.xcodeproj
```

Build from the command line without code signing:

```sh
xcodebuild \
  -project VirtualiseOS.xcodeproj \
  -scheme VirtualiseOS-Swift \
  -configuration Debug \
  -destination 'platform=macOS' \
  CODE_SIGNING_ALLOWED=NO \
  build
```

Run SwiftLint locally:

```sh
swiftlint lint --config .swiftlint.yml --reporter json --no-cache
```

## Using VirtualiseOS

1. Create a virtual machine profile.
2. Choose where `VM.bundle` should be stored.
3. Optionally choose a host folder to share with the VM.
4. Select memory and disk size.
5. Download and install the latest supported macOS restore image.
6. Start or stop the VM from the library or the Virtual Machine menu.

VM bundles, restore images, archives, and generated build artifacts should not be committed.

## Project Layout

```text
App/Common              Shared VM configuration helpers
App/InstallationTool    Command-line installation target
App/VirtualiseOS        SwiftUI macOS app
.github/workflows       CI and release packaging workflows
Configuration           Xcode build configuration
```

## Development

The CI workflow builds the app and runs SwiftLint on pull requests. The CD workflow calculates a SemVer-style version from tags, archives the app, packages a DMG, and publishes a GitHub release.

Before opening a pull request:

- Build the `VirtualiseOS-Swift` scheme.
- Run SwiftLint.
- Update `CHANGELOG.md` for user-facing changes.
- Keep VM data, generated archives, and macOS metadata out of commits.

## Changelog

Release notes are maintained in [CHANGELOG.md](CHANGELOG.md).

## Contributing

Contributions are welcome. See [CONTRIBUTING.md](CONTRIBUTING.md) for setup, pull request, and review guidance.

## Security

Please do not report exploitable vulnerabilities in public issues. See [SECURITY.md](SECURITY.md).

## License

VirtualiseOS is licensed under the Apache License 2.0. See [LICENSE](LICENSE).

Portions of the project are derived from Apple's "Running macOS in a virtual machine on Apple silicon" sample code. The original Apple sample license is preserved in [LICENSE.txt](LICENSE.txt), and attribution is summarized in [NOTICE](NOTICE).
