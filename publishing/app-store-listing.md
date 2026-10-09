# App Store listing draft

| Field | Current / proposed value |
| --- | --- |
| Platform | iOS (iPhone) |
| Bundle ID | dev.glebmelnikov.InstaBlock |
| Name | Current App Store Connect name: “Daywell: Control Screen time” (provisional; “Daywell” was unavailable) |
| Subtitle | Make room for your day |
| Primary category | Productivity |
| Price | Free ($0.00), saved in App Store Connect for all 175 territories on October 9, 2026. |
| Age rating | Apple-calculated 9+ in 172 regions, with country-specific ratings elsewhere |
| Copyright | 2026 Daywell contributors |
| Version | 1.0 |
| Minimum OS | iOS 17.4 |
| Keywords | screen time,focus,app blocker,digital wellbeing,habits,limits |
| Privacy Policy URL | https://daywell-support.tunedtoast2.chatgpt.site/privacy.html |
| Public support email | melnikovglebdm@gmail.com |
| Support URL | https://daywell-support.tunedtoast2.chatgpt.site/support.html |

## Description

Make a little more room in your day. Daywell helps you set boundaries for the apps you choose, then lets iOS keep those boundaries in place.

Choose individual apps in Apple's private Screen Time picker. Set daily block windows, a shared daily allowance, or both. Time across all selected apps adds up toward the same allowance. When a block is active, the system shows a blocking screen with a Close button and no in-app skip option.

Start with a morning block from 06:00 to 10:00, an evening block from 22:00 to midnight, and a 30-minute shared allowance, then adjust the routine to fit your day. You can use up to seven daily block windows. Lower allowances apply immediately; higher allowances and app removals take effect the next day after any overnight block.

Daywell works without an account, subscription, ads, analytics, or a server. Your selected apps and rules stay on your device. Screen Time access is required. You can turn it off in iOS Settings or uninstall Daywell; iOS may delay Screen Time activity and blocking updates.

## Screenshot plan

Use real captures from the current Daywell release build, with no simulator preview banner. Capture:

1. Onboarding with default routine visible.
2. Activated dashboard showing the status card, selected apps, blocks, and allowance.
3. Daily blocks editor showing editable windows.
4. Shared allowance editor or the app selection flow, provided no private selections appear.

Provide iPhone screenshots in the display sizes App Store Connect asks for. The checked-in app icon is ready; App Store Connect normally obtains it from the uploaded build. The existing `build/screenshots/onboarding.png` is obsolete and must not be used. A current simulator capture in `build/validation/rejected-simulator-onboarding.png` also cannot be submitted because it contains a simulator-only banner and storage warning; capture from the tested physical iPhone.

Apple's [current screenshot specifications](https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications), checked October 9, 2026, accept **1206 × 2622** portrait captures from the connected iPhone 16 Pro in the **iPhone with Dynamic Island (medium display)** slot. The page's required-size summary calls for at least one medium-display capture; confirm any additional required slots in the live app version before submission. Upload one to ten PNG or JPEG images per device size, with no alpha channel. Use the current installed Release build and save captures at their native dimensions. The recommended order is onboarding/dashboard, daily blocks, and shared allowance. Xcode's **Window → Devices and Simulators → Gleb’s iPhone → Take Screenshot** can capture these screens after the phone is unlocked.

## Information to enter in App Store Connect

- App privacy: Based on the current code, Daywell does not transmit selected apps or activity to its developer. Check the whole release build before answering Apple's data collection questionnaire. The public privacy policy URL is listed above.
- Age rating: Questionnaire completed from the current app content. Apple calculated 9+ in most regions; confirm this rating before submission.
- Export compliance: The app's Info plist declares `ITSAppUsesNonExemptEncryption = false`. Answer App Store Connect's export questions consistently with the shipped build.
- Review contact: The saved form contains the first name, last name, email, and phone. On October 9, the phone field was confirmed populated and browser-valid without reading or recording the number.
- Availability: App Store Connect currently covers 175 territories. Mac and Vision Pro compatibility distribution were disabled and saved on October 9. Complete EU trader-status compliance before release. The Paid Apps Agreement is not needed for this free app with no in-app purchases.
