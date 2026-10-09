# Family Controls distribution request

## Verified status — October 8, 2026

Apple Developer's **Capability Requests** tab showed **Assigned** for Family Controls (Distribution) on each of the five IDs below. The distribution capability has now been enabled and saved on all five IDs. Xcode generated fresh App Store provisioning profiles and successfully archived and exported version 1.0, build 1.

All five exported bundles passed signature verification. Their embedded App Store profiles and signed entitlements include Family Controls and `group.dev.glebmelnikov.InstaBlock`, with debugging disabled. Every bundle has iPhone-only device-family metadata. Local evidence: `build/validation/distribution-verification.json`; portal screenshot: `build/validation/family-controls-enabled.jpg`. Export: `build/AppStoreExport/Daywell.ipa`. This verifies distribution signing, not App Review approval or runtime Screen Time behavior.

No additional request is needed for these IDs. For future IDs, use the **paid Apple Developer team's Account Holder** account. In [Certificates, Identifiers & Profiles](https://developer.apple.com/account/resources/identifiers/list), open the App ID, select **Capability Requests**, and request **Family Controls (Distribution)**. Apple's [configuration guide](https://developer.apple.com/documentation/xcode/configuring-family-controls) says to submit the same request for Screen Time API extensions. Keep the existing bundle prefix and App Group so the release can update development installs in place.

The five App IDs generated from the current local signing configuration are:

1. `dev.glebmelnikov.InstaBlock` — Daywell app
2. `dev.glebmelnikov.InstaBlock.ActivityMonitor` — scheduled and usage callbacks
3. `dev.glebmelnikov.InstaBlock.ShieldConfiguration` — blocking screen appearance
4. `dev.glebmelnikov.InstaBlock.ShieldAction` — blocking screen Close action
5. `dev.glebmelnikov.InstaBlock.ActivityReport` — local usage report

## Proposed purpose statement

> Daywell is a self-directed digital wellbeing app for iPhone. The device owner grants individual Screen Time authorization and selects specific installed apps using Apple's Family Controls picker. Daywell uses Device Activity to enforce recurring daily block windows and one shared daily allowance across the selected apps. Managed Settings shields those apps during a window or after the allowance is reached. Its monitor extension handles system callbacks, shield extensions display a Close-only blocking screen, and a report extension shows today's use in the app. The app has no account, advertising, analytics, subscription, or server. Selected app tokens and rule state stay in the device's App Group container and are shared only with Daywell's extensions. Users can revoke Screen Time access or uninstall the app in iOS Settings.

Adjust this statement to fit the exact fields Apple presents. Mention the parent app bundle ID when requesting each extension so Apple can connect the five requests. Do not claim that blocking is impossible to bypass: uninstalling the app or revoking permission ends enforcement.

For future requests, after approval enable and save **Family Controls (Distribution)** on every affected App ID, refresh provisioning profiles, and verify the Family Controls and App Group entitlements in the exported app and each extension.
