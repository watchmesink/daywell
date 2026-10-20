<img src="docs/assets/icon.png" alt="Daywell icon" width="96">

# Daywell

<a href="https://buymeacoffee.com/glebmelnikov"><img src="https://cdn.buymeacoffee.com/buttons/v2/default-yellow.png" alt="Buy me a coffee" width="180"></a>

**Make room for your day.**

Daywell is a free, open-source iPhone app for spending less time doomscrolling. Pick the apps, categories, or websites you want to limit. Block them at set times, give them a shared daily allowance, or use both.

Your selections and activity stay on your device. No account, subscription, ads, or analytics. Requires iOS 17.4 or later.

[Get it on the App Store](https://apps.apple.com/app/id6820666833) · [Support](https://daywell-support.tunedtoast2.chatgpt.site/support.html) · [Privacy](https://daywell-support.tunedtoast2.chatgpt.site/privacy.html) · [Report an issue](https://github.com/watchmesink/daywell/issues)

## Screenshots

Dashboard, activity selection, and shared allowance. Simulator captures with sample data, in light and dark mode.

<p>
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="docs/screenshots/dashboard-dark.png">
    <img src="docs/screenshots/dashboard.png" alt="Dashboard with selected activity, total screen time, and daily blocks" width="250">
  </picture>
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="docs/screenshots/selected-apps-dark.png">
    <img src="docs/screenshots/selected-apps.png" alt="Choose apps, categories, and websites; three sample categories selected" width="250">
  </picture>
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="docs/screenshots/shared-allowance-dark.png">
    <img src="docs/screenshots/shared-allowance.png" alt="Shared daily allowance set to 30 minutes" width="250">
  </picture>
</p>

## How it works

Give Daywell Screen Time access and use Apple's picker to choose what to block. You start with a 30-minute shared allowance and no scheduled blocks. Adjust those rules before you activate protection.

- Add up to seven daily blocking windows, including overnight schedules.
- Share one daily allowance across your selected apps, categories, and websites outside those windows.
- See how much time you've spent on your selection today. Total screen time appears below, with a comparison to your previous seven-day average.

For example, 10 minutes in TikTok and 20 minutes in X use the full 30-minute allowance. Both apps are then blocked for the rest of the day.

Stricter limits take effect right away. Changes that give you more time take effect the next day, after any overnight block ends. Review or cancel them under Upcoming changes.

iOS can delay blocking and usage reports. You can remove protection by uninstalling Daywell or turning off its Screen Time access. See [architecture and limitations](docs/ARCHITECTURE.md) for details.

## Build and test

To build Daywell yourself, you need macOS, Xcode, a paid Apple Developer membership with Family Controls access, and an iPhone running iOS 17.4 or later. The app uses SwiftUI and has no third-party runtime dependencies.

1. Copy `Config/Local.xcconfig.example` to `Config/Local.xcconfig` and set your Team ID, bundle prefix, and App Group. This file is ignored by Git.
2. Open `Daywell.xcodeproj`, select the **Daywell** scheme, and choose your connected iPhone.
3. Configure signing, Family Controls, and the shared App Group for the app and its four extensions, following the [signing guide](docs/SIGNING.md). Build and run.

Run the rule tests and build the app and extensions for the simulator:

```sh
bash scripts/check.sh
```

Use `swift test` for just the portable tests. The Xcode project is checked in; run `xcodegen generate` after changing targets or adding source files.

Use the simulator to check the interface and a real iPhone to test blocking with the [device checklist](docs/DEVICE_VALIDATION.md). See [validation results](docs/VALIDATION.md) for completed checks and the [App Store release kit](publishing/README.md) for distribution setup.

## License

The source and app icon are [MIT licensed](LICENSE). The ocean-sunset artwork is adapted from [ascii.rest](https://ascii.rest/ocean-sunset/) by bas3line under the MIT license; see [artwork attribution](docs/ARTWORK.md).
