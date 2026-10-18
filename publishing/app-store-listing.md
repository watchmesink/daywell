# App Store listing draft

| Field | Current / proposed value |
| --- | --- |
| Platform | iOS (iPhone) |
| Bundle ID | dev.glebmelnikov.InstaBlock |
| Name | Daywell: Simple App Blocker (27/30). Replaces “Daywell: Control Screen time”; “Daywell” alone was unavailable. |
| Subtitle | Screen time, simple & private (29/30) |
| Promotional text | Pick the apps that eat your time, set a daily routine, and let iOS keep it in place. No account, no ads, no analytics. Open source. |
| Primary category | Productivity |
| Price | Free ($0.00), saved in App Store Connect for all 175 territories on October 9, 2026. |
| Age rating | Apple-calculated 9+ in 172 regions, with country-specific ratings elsewhere |
| Copyright | 2026 Daywell contributors |
| Version | 1.1.1 (8), prepared October 18, 2026; release after App Review approval |
| Minimum OS | iOS 17.4 |
| Keywords | focus,distraction,doomscrolling,social media,limit,schedule,routine,wellbeing,habit,productivity (96/100; avoids repeating name and subtitle words) |
| Privacy Policy URL | https://daywell-support.tunedtoast2.chatgpt.site/privacy.html |
| Public support email | melnikovglebdm@gmail.com |
| Support URL | https://daywell-support.tunedtoast2.chatgpt.site/support.html |

## Description

Make room for your day.

Daywell is a simple, private app blocker for iPhone. Choose the apps that eat your time, set a daily routine, and let Apple’s Screen Time keep it in place. No account, no subscription, no ads.

SIMPLE BY DESIGN
• Pick apps, whole categories, or websites in Apple’s private Screen Time picker.
• Add up to seven daily block windows, including overnight.
• Set one shared daily allowance that counts time across everything you selected.
• Use blocks, an allowance, or both.
• See what’s blocked, when, and today’s usage on one dashboard.

PRIVATE. NO ACCOUNT.
• Nothing to sign up for and nothing to sign in to.
• Daywell never sees which apps you chose; iOS gives it only opaque tokens.
• No server, no analytics, no tracking, no advertising. Your rules stay on your iPhone.

FREE, WITH NOTHING TO UNLOCK
• No subscription, no in-app purchases, no trial that expires.
• Open source under the MIT license.

BUILT TO HOLD
• Tightening a limit applies immediately. Loosening one waits until the next day, so a weak moment can’t undo your plan.
• When a block is active, iOS shows a blocking screen with a native button to close the app and no skip option.

Daywell requires Screen Time access on iOS 17.4 or later. You can turn it off in Settings or uninstall the app at any time. iOS controls Screen Time callbacks, so activity updates and blocking can be delayed.

## What’s New in 1.1.1

• Corrected today's usage to show time in your selected apps, categories, and websites.
• Added total screen time with a comparison to your previous seven-day average.
• Improved dashboard scrolling and simplified the blocked-activity card.
• Restored native blocking-screen button colors and a consistent dark app icon.

## Screenshots

Six slides in `publishing/screenshots/`, alternating light and dark appearance, at 1206 × 2622 (`6.3-inch/`, the iPhone with Dynamic Island medium slot) and 1320 × 2868 (`6.9-inch/`). RGB PNG, no alpha. Upload in file-name order.

| # | Value | Headline | Screen |
| --- | --- | --- | --- |
| 1 | Simplicity | Choose the apps. That’s it. | Selection editor, light |
| 2 | Private, no account | No account. No sign-in. | Dashboard, dark |
| 3 | Core feature | One allowance, shared. | Allowance editor, light |
| 4 | Simplicity | Simple by design. | Dashboard, light |
| 5 | Privacy | Private by default. | Selection editor, dark |
| 6 | Your routine | Your time. Your routine. | Allowance editor, dark |

To regenerate: `bash scripts/make-store-captures.sh` renders the real app views on the iPhone 17 Pro simulator into `build/store-captures/`, then `python3 scripts/make-store-screenshots.py` composes the slides. The simulator can’t authorize Screen Time or create activity tokens, so `scripts/store-preview/Fixture.swift` supplies a sample routine and usage values, plus Social, Entertainment, and Games tiles in the selection editor. The capture script reuses the production report views. The status bar and sample routine are fixed at 09:41.

## Information to enter in App Store Connect

- App privacy: Based on the current code, Daywell does not transmit selected apps or activity to its developer. Check the whole release build before answering Apple's data collection questionnaire. The public privacy policy URL is listed above.
- Age rating: Questionnaire completed from the current app content. Apple calculated 9+ in most regions; confirm this rating before submission.
- Export compliance: The app's Info plist declares `ITSAppUsesNonExemptEncryption = false`. Answer App Store Connect's export questions consistently with the shipped build.
- Review contact: The saved form contains the first name, last name, email, and phone. On October 9, the phone field was confirmed populated and browser-valid without reading or recording the number.
- Availability: App Store Connect currently covers 175 territories. Mac and Vision Pro compatibility distribution were disabled and saved on October 9. Complete EU trader-status compliance before release. The Paid Apps Agreement is not needed for this free app with no in-app purchases.
