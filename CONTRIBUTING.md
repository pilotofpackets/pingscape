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

## Versions and releases

Versions follow [Semantic Versioning](https://semver.org): `MAJOR.MINOR.PATCH`. While the major version is 0 the app is still in development, and 1.0.0 is the first public release. New features raise the minor version, fixes raise the patch version.

- The version is `MARKETING_VERSION` in `project.yml`.
- The build number is the number of commits, written into the app and the widget at build time by `scripts/set-build-number.sh`. It is never edited by hand. `scripts/check-build-numbers.sh` fails the build if an extension and the app differ.
- Releases are tagged `vMAJOR.MINOR.PATCH`. `scripts/release.sh 0.2.0` sets the version, commits it if it changed and creates the annotated tag. Push it with `git push origin main v0.2.0`.

## Test

All network logic lives in the `NetKit` package and is tested on the Mac:

```sh
swift test --package-path Packages/NetKit
```

Add a test for every rule you add. Bugs in the VPN detection are best reproduced with a fixture (a hand-built snapshot in `Tests/NetKitTests`).

The app itself has two test targets, run with the `Pingscape` scheme (⌘U) or from the command line:

- `Tests/PingscapeTests`: the app's own logic (units, hiding values, tool input, settings) and the string catalogs (every string in all five languages, same placeholders as English).
- `Tests/PingscapeUITests`: every screen in demo mode, page by page down to its end. Each page gets a screenshot, Apple's accessibility audit (contrast, Dynamic Type, clipped text, tap targets, labels) and a check that nothing sticks out of the window. The flows a user goes through are tested too: tabs, the keyboard with Start and Done, hiding values, the first launch, the LAN list opening a tool.

`scripts/ui-matrix.sh` runs both on many simulators (iPhone SE to Pro Max, iPad mini to 13", iOS 18, 26 and 27), text sizes from XS to AX5, light and dark, all five languages, portrait and landscape:

```sh
scripts/ui-matrix.sh quick       # one iPhone, two variants, about half an hour
scripts/ui-matrix.sh             # 4 devices x 6 variants, about 3 hours
scripts/ui-matrix.sh full        # 12 devices x 31 variants, overnight
scripts/ui-matrix.sh quick --only ToolFlowTests --variants de:AX5:dark:portrait:0
```

It never runs more than 2 simulators at once (`PS_MAX_SIMULATORS` changes that; 4 overloaded a 32 GB Mac): the devices are tested in groups, and each group is shut down before the next boots. It creates the simulators it needs (named `PS …`) and writes `build/ui-matrix/<time>/report.md` (failures and accessibility findings, with the devices and variants where they occur) and `index.html` (all screenshots side by side, one row per screen). A UI test reads its variant from `PS_LANGUAGE`, `PS_TEXT_SIZE`, `PS_APPEARANCE`, `PS_ORIENTATION` and `PS_HIDE_VALUES`; set them in the scheme's environment to run one variant from Xcode.

A new screen gets a test in `ScreenTests.swift`, reached through the demo launch arguments (`-demo-tab`, `-demo-path`, `-demo-tool`, `-demo-lan-device`). A control a flow test taps gets an `accessibilityIdentifier`, so the test does not depend on the language.

## Contributing

Issues are welcome: bug reports, wrong values (especially VPN detection on your setup) and ideas. Use the templates.

Pull requests are switched off on this repository for now, and only the maintainer changes the code. You can read everything, fork the repository and work on your own branch in your fork, under the terms of the [MIT license](LICENSE). If you have a fix or a fixture, open an issue and link to your branch.

Code, comments and commit messages are in English. User-facing strings go into `App/Resources/Localizable.xcstrings` in English, German, French, Spanish and Italian. A correction of a translation is welcome as an issue, ideally from a native speaker.
