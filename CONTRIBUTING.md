# Contributing

Thanks for helping improve VirtualiseOS.

## Development Setup

1. Clone the repository.
2. Open `VirtualiseOS.xcodeproj` in Xcode.
3. Build the `VirtualiseOS-Swift` scheme.
4. Run SwiftLint before opening a pull request.

Command-line build:

```sh
xcodebuild \
  -project VirtualiseOS.xcodeproj \
  -scheme VirtualiseOS-Swift \
  -configuration Debug \
  -destination 'platform=macOS' \
  CODE_SIGNING_ALLOWED=NO \
  build
```

SwiftLint:

```sh
swiftlint lint --config .swiftlint.yml --reporter json --no-cache
```

## Pull Requests

- Keep changes focused.
- Describe the user-visible behavior change.
- Include screenshots for UI changes when useful.
- Update `CHANGELOG.md` for notable user-facing changes.
- Do not commit VM bundles, restore images, build artifacts, derived data, archives, DMGs, or `.DS_Store` files.

## Coding Guidelines

- Prefer the existing SwiftUI and coordinator patterns before introducing new abstractions.
- Keep Virtualization framework calls behind the existing Apple silicon guards when needed.
- Keep user-facing strings localizable.
- Preserve security-scoped bookmark handling for user-selected VM and shared-folder locations.

## Release Notes

Versioned releases are tracked in `CHANGELOG.md` using Keep a Changelog sections:

- `Added`
- `Changed`
- `Deprecated`
- `Removed`
- `Fixed`
- `Security`
