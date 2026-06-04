# Changelog

All notable changes to VirtualiseOS will be documented in this file.

This project adheres to [Semantic Versioning](https://semver.org/).
The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).

## [Unreleased]

### Added

- Added a SwiftLint code quality job to the CI workflow.
- Added a repository SwiftLint configuration scoped to the `App` source tree.
- Added open-source project documentation, contribution guidance, security reporting guidance, issue templates, and attribution notice.

### Changed

- Replaced the sample README with a VirtualiseOS README covering features, requirements, local build commands, project layout, CI/CD, and licensing.
- Updated repository ignore rules for macOS and Xcode-generated artifacts.
- Updated the pull request template with a contributor checklist.

### Fixed

- Removed an extra trailing newline from `RootView.swift` so SwiftLint can pass with the current configuration.

---

## [0.0.8] - 2026-06-04

### Added

- Added a dedicated create-VM flow with name, `VM.bundle` location, shared folder, memory, disk size, and latest-supported macOS restore image selection.
- Added VM detail, VM row, setup, and reusable card views for a richer SwiftUI library experience.
- Added app palette, card styling, new color assets, and VirtualiseOS logo assets.
- Added a standalone splash screen view.
- Added localized string convenience helpers.
- Added restore image URL and OS version metadata to VM profiles.

### Changed

- Reworked the VM library into a sidebar/detail interface with explicit configuration and action panels.
- Updated restore-image download and installation handling to use profile-specific restore image metadata.
- Reorganized SwiftUI views under clearer `DetailView`, `Views/Setup`, `Views/Reusable`, and `Model` folders.
- Updated app entitlements and project metadata for the refreshed macOS app package.
- Refined the installation tool around disk image creation and restore-image handling.

---

## [0.0.7] - 2026-06-04

### Added

- Added installer cancellation support and menu actions for cancelling an in-progress install.
- Added safer profile deletion checks so installing, starting, and running VMs cannot be deleted accidentally.

### Changed

- Renamed `MacOSVirtualMachineConfigurationHelper` to `MachineConfigurationHelper`.
- Updated app metadata with developer tools category, encryption declaration, and copyright information.
- Improved start, stop, quit, and profile status state handling.
- Refined setup and library view behavior around VM lifecycle transitions.

### Fixed

- Fixed several app start/stop state transitions that could leave a VM profile marked as running or starting after the VM had stopped.

---

## [0.0.6] - 2026-06-04

### Added

- Added app commands for creating a new VM, starting the selected VM, installing macOS, stopping the VM, refreshing status, and removing a selected VM.
- Added a splash screen during app startup.
- Added computed availability checks for start, install, stop, and delete actions.

### Fixed

- Marked VM profiles as stopped when the app terminates or returns from a running VM.
- Refreshed stale running/starting profile states back to stopped when appropriate.

---

## [0.0.5] - 2026-06-04

### Fixed

- Stopped the VM and returned to the settings screen when the VM window closes.
- Updated VM profile state to stopped after user-initiated stop and guest-stop events.
- Improved VM window close handling so the app does not keep stale VM references.

---

## [0.0.4] - 2026-06-04

### Fixed

- Fixed non-Apple silicon build paths by guarding Virtualization-only helper APIs behind `arch(arm64)`.
- Added non-arm64 fallbacks for setup and information-alert flows used by the app shell.
- Normalized VM bundle location handling after the SwiftUI refactor.

---

## [0.0.3] - 2026-06-04

### Fixed

- Made shared VM profile, status, and persistence models available outside the arm64-only code paths.
- Moved URL session download delegate conformance into an arm64-only extension.
- Cleaned up post-refactor architecture guards around shared app types.

---

## [0.0.2] - 2026-06-04

### Fixed

- Fixed background restore image downloads by moving the temporary download file before handing it back to the installation flow.
- Improved error handling when the downloaded restore image cannot be moved into the VM bundle location.

---

## [0.0.1] - 2026-06-04

### Added

- Added the initial VirtualiseOS macOS app derived from Apple's Virtualization sample.
- Added Swift app and `InstallationTool-Swift` targets.
- Added restore image download, macOS installation, VM launch, VM save/restore, and shared folder support.
- Added MTD branding, app icons, light/dark visual updates, and localized strings.
- Added a SwiftUI rewrite with sidebar-style VM management and support for multiple VM profiles.
- Added SwiftData-backed profile persistence and migration from legacy user defaults profile storage.
- Added GitHub CI and CD workflows, CODEOWNERS, and a pull request template.

### Changed

- Renamed the original sample app, project, schemes, and entitlements to VirtualiseOS.
- Moved source files from the original `Swift` folder into the `App` source layout.

### Fixed

- Fixed the Xcode project `Info.plist` path after the source layout refactor.

[Unreleased]: https://github.com/mtdtechnology-net/virtualization-macos/compare/v0.0.8...HEAD
[0.0.8]: https://github.com/mtdtechnology-net/virtualization-macos/compare/v0.0.7...v0.0.8
[0.0.7]: https://github.com/mtdtechnology-net/virtualization-macos/compare/v0.0.6...v0.0.7
[0.0.6]: https://github.com/mtdtechnology-net/virtualization-macos/compare/v0.0.5...v0.0.6
[0.0.5]: https://github.com/mtdtechnology-net/virtualization-macos/compare/v0.0.4...v0.0.5
[0.0.4]: https://github.com/mtdtechnology-net/virtualization-macos/compare/v0.0.3...v0.0.4
[0.0.3]: https://github.com/mtdtechnology-net/virtualization-macos/compare/v0.0.2...v0.0.3
[0.0.2]: https://github.com/mtdtechnology-net/virtualization-macos/compare/v0.0.1...v0.0.2
[0.0.1]: https://github.com/mtdtechnology-net/virtualization-macos/releases/tag/v0.0.1
