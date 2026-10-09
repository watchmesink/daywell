# Signing and installation

## Personal development build

Use a paid Apple Developer membership that supports the Family Controls capability. Daywell itself has no subscription; Apple's developer membership and provisioning are separate requirements for installing your own build.

1. Sign into Xcode under **Xcode → Settings → Accounts**.
2. Find the membership's Team ID in your Apple Developer account. A certificate's personal identifier is not necessarily the Team ID.
3. Copy `Config/Local.xcconfig.example` to `Config/Local.xcconfig` and replace its three values. For example, your bundle prefix might be `com.yourname`, with the group `group.com.yourname.InstaBlock`.
4. Open `Daywell.xcodeproj`. Check **Signing & Capabilities** for all five targets:
   - Daywell
   - ActivityMonitor
   - ShieldConfiguration
   - ShieldAction
   - ActivityReport
5. Use the same development team for every target. The supplied entitlement file enables **Family Controls** and the configured **App Group**. Register the group and attach it to the identifiers as Xcode requests.
6. Connect and unlock the iPhone, trust the Mac, and enable **Settings → Privacy & Security → Developer Mode** if required.
7. Choose the Daywell scheme and the iPhone destination, then Run.

The bundle IDs derive from `BUNDLE_ID_PREFIX`; the main ID remains `<prefix>.InstaBlock`, with an extension suffix for each extension. The App Group also retains its original `InstaBlock` suffix. These identifiers let Daywell replace an earlier install without losing its saved rules or leaving old Screen Time restrictions behind. `APP_GROUP_IDENTIFIER` is passed both to entitlements and to the runtime Info plist. Changing only one will break shared storage.

Do not commit certificates, provisioning profiles, signing secrets, or `Local.xcconfig`. Regenerating the project preserves the local configuration.

For simulator interface checks, use Xcode's normal simulator signing or `CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=-`. Installing a build made with `CODE_SIGNING_ALLOWED=NO` omits its App Group entitlement and can produce a shared-storage error. Unsigned builds are compilation checks, not runnable entitlement checks.

## First launch

Grant **individual Screen Time authorization** using the device owner's authentication. Choose one or more apps; categories and websites are outside this version. Review the schedule before activation because choosing apps during a scheduled window activates the block immediately.

You can edit the initial schedule and allowance before granting permission or selecting an app. Activation still requires authorization. After activation, the shared rule engine enforces the edit restrictions even if a form was left open before a block started.

## TestFlight or App Store later

Distribution requires Apple to approve the **Family Controls distribution entitlement** for the app and each relevant Screen Time extension. A successful development build does not imply distribution approval. Public publication is not performed by the build scripts in this repository.

Official references:

- [Configure Family Controls](https://developer.apple.com/documentation/xcode/configuring-family-controls)
- [Request the Family Controls distribution entitlement](https://developer.apple.com/documentation/familycontrols/requesting-the-family-controls-entitlement)
- [Individual authorization and its limitations](https://developer.apple.com/videos/play/wwdc2022/110336/)

## Troubleshooting

| Symptom | Check |
| --- | --- |
| Missing provisioning profile or unsupported capability | Paid team selected; Family Controls enabled on the exact app/extension identifier |
| Shared storage unavailable | All five targets use the same registered App Group and matching local configuration |
| Monitor registration fails | Permission, valid time range, installed extension entitlements; the prior configuration is retained |
| App launches but limits never fire | Verify on a physical device, inspect extension logs, check Screen Time permission and signing validity |
| Usage report is empty | Use a selected app and allow time for Screen Time to populate its report |
| Protection needs access | Reauthorize through the app; saved rules and exhausted allowance state are retained |

In Console.app, select the connected device and filter for subsystem `Daywell` / category `Protection`. Tokens and usage history are not logged. The app displays a persisted monitoring error when one is available.
