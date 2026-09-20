# Contributing

Thanks for helping. Pingscape is small on purpose: it shows network information and changes nothing.

## Principles

- **Only real data.** Show what iOS actually returns. Nothing is guessed, and a missing value is a missing row, not a greyed-out placeholder.
- **Public Apple APIs only.** No private frameworks.
- **Private by default.** Everything runs on the device. Anything that leaves the device needs the user's consent and is listed in [PRIVACY.md](PRIVACY.md).
- **No third-party runtime dependencies.**
- **Works on every iPhone.** Check the smallest screen, the largest text size, light and dark mode.

## Build

Requirements: Xcode 26 or newer, [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```sh
brew install xcodegen
xcodegen generate            # creates Pingscape.xcodeproj from project.yml
open Pingscape.xcodeproj
```

To run on a device, copy `Config/Local.xcconfig.example` to `Config/Local.xcconfig` and set your team. Reading the Wi-Fi name needs the "Access WiFi Information" capability, which needs a paid developer account.

The simulator shows the network of your Mac, not of an iPhone. Launch with the argument `-demo` to use fixture data instead.

## Test

All network logic lives in the `NetKit` package and is tested on the Mac:

```sh
swift test --package-path Packages/NetKit
```

Add a test for every rule you add. Bugs in the VPN detection are best reproduced with a fixture (a hand-built snapshot in `Tests/NetKitTests`).

## Pull requests

- Keep them focused.
- Code, comments and commit messages are in English. User-facing strings go into `App/Resources/Localizable.xcstrings` in English and German.
- Explain in the description how you checked the change (device, iOS version).
