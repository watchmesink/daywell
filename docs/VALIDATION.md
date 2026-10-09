# Validation results

Recorded on **2026-10-08**.

## Completed

| Check | Result |
| --- | --- |
| Foundation-only core tests | **41 passed, 0 failures** before the selection fixes below; not rerun for this fix |
| iOS Simulator Debug build | **Passed** after the Daywell rename, main app and all four extensions |
| iOS device Debug build, signing disabled | **Passed after the multi-app change**, main app and all four extensions |
| Final iOS device Release build, signing disabled | **Passed before the rename**, main app and all four extensions |
| Simulator installation with ad-hoc signing | **Passed before the rename**, iPhone 17 Pro / iOS 26.5 |
| Simulator launch | **Passed before the rename**, app process launched successfully |
| Onboarding visual inspection | **Passed before the rename**, default schedules and allowance rendered; no shared-storage error with correct simulator signing |
| Extension bundle metadata | **Passed after the rename**, Daywell display names and upgrade-compatible bundle IDs verified in all five bundles; shared-storage keys verified where used |
| Signed iPhone Debug build | **Passed after the multi-app change**, main app and all four extensions |
| Daywell physical iPhone installation | **Passed**, iPhone 16 Pro / iOS 26.7.1; `dev.glebmelnikov.InstaBlock` updated in place and listed as Daywell 1.0 |
| Pre-rename physical iPhone launch | **Passed**, iPhone 16 Pro / iOS 26.7.1; running process confirmed |

Environment: **Xcode 26.6 (17F113)**, **Swift 6.3.3**, **XcodeGen 2.45.4**. The application and package use Swift 5 language mode, with an iOS 17.4 deployment target.

The tests exercise start/end boundaries, overlapping/overnight blocks, DST, a shared schedule and budget for multiple apps, pending allowance and app changes, migration of saved single-app selections, stale/duplicate/future callbacks, callbacks during monitor installation, failed updates, crash recovery, clock changes, missing monitors, unreadable state, and concurrent storage transactions. The earlier suite expected registrations crossing a block start to be rejected. That expectation is superseded by the editable-anytime behavior below: weakening edits are queued instead.

The build emits Apple's informational warning that App Intents metadata extraction was skipped because the app has no AppIntents dependency. No App Intents integration is intended.

Logs and the inspected screenshot are retained locally under `build/validation/` and `build/screenshots/` (ignored by Git).

## Physical-device installation history

The paired **iPhone 16 Pro** was unavailable during the initial implementation pass. In a later installation attempt on the same date, it connected over USB, running **iOS 26.7.1**, with **Developer Mode enabled**.

The connected-device attempt could not install the app:

- Xcode's configured account is a **Personal Team**. The signing build explicitly failed because Personal Teams do not support **Family Controls (Development)**. A paid developer team with the capability is required for the app and its extensions.
- CoreDevice could not mount its developer support image because the **iPhone was locked**. Unlocking the phone is required for device preparation.
- The discovered team and app identifiers have been placed in the Git-ignored `Config/Local.xcconfig`; no personal account configuration is committed. This file must be updated if a different paid team is added.

The failed signing log is retained at `build/validation/phone-signing-attempt.log`. No build has been installed on the physical phone.

After the developer membership purchase, a second attempt found the iPhone connected, but Xcode Accounts still listed only the Personal Team. A fresh build with `-allowProvisioningUpdates` again failed for all five targets because that team does not support Family Controls (Development). The retry log is `build/validation/phone-signing-retry.log`. The Apple Developer account page requires sign-in, so paid membership activation has not yet been verified.

A subsequent retry stopped rejecting Family Controls and instead reported that the team had no registered devices. Building for the connected iPhone with `-allowProvisioningUpdates -allowProvisioningDeviceRegistration` succeeded. The signed app was installed and launched using CoreDevice, and its running process was confirmed. The successful build log is `build/validation/phone-device-build.log`. The earlier signing and locked-device blockers are resolved.

The Daywell multi-app build was signed and installed on the connected iPhone using the same bundle ID. The successful build log is `build/validation/daywell-phone-build.log`. CoreDevice confirmed Daywell 1.0 is installed. The first launch attempt was denied because the phone was locked; launch remains pending until it is unlocked.

## Still pending

The selection-fix build successfully launched on the physical iPhone. Actual Screen Time authorization, usage callbacks, shield presentation, report content, force-quit/reboot behavior, and midnight transitions on a physical device are **not verified**. Timing delays have not been measured. Installation and launch alone are not evidence of these behaviors. The user must authorize Screen Time and select apps on the phone to activate protection.

Interactive editor and activated-dashboard visual checks were not completed: the computer-use surface could not obtain a Simulator window. The editor code compiled successfully; edit restrictions are covered by the core tests.

Follow [signing and installation](SIGNING.md) and complete [the physical-device checklist](DEVICE_VALIDATION.md) before relying on this build for daily blocking. No TestFlight or App Review submission has been made. Family Controls distribution access and local export were subsequently verified as recorded below.

## Multi-app selection fixes

- The editor loads the pending selection when present and initializes only once, preventing picker reappearances from overwriting unsaved choices with active apps.
- Active, draft, and upcoming selections have explicit counts and token-label rows with reserved height. The upcoming card shows the actual queued apps and effective date.
- The editor uses explicit Save/Cancel actions and explains unsupported category/website selections before saving.
- Pure additions apply immediately between blocks. Both persisted exhaustion and compatible in-flight threshold callbacks survive the expanded selection's monitor replacement. Removals and replacements remain deferred.
- Saved state loads even if monitor reconciliation fails; the failure is shown alongside the saved apps instead of leaving the app at its empty defaults.

The signed Debug build passed and was installed in place and launched on the connected iPhone. Build log: `build/validation/daywell-selection-fix-build.log`. Existing assertions were updated for immediate additions; no tests were added or run in this pass. Reading the device's App Group state through CoreDevice failed with `ContainerLookupErrorDomain` code 7, so the reported UI and enforcement behavior still require an on-device check.

## Allowance interface update

“Used today” now renders only in the green status card while authorized and the budget is not exhausted. The report extension uses black text suitable for the green background. Foreground refreshes pick up threshold state from the monitor extension every 15 seconds; Screen Time delivery can still be delayed.

The allowance editor only accepts 1–1,440 minutes and loads any pending increase. New disabled allowances are rejected by core validation. Reconciliation cancels legacy queued disables, preserves finite limits, and restores the 30-minute default for an already-disabled legacy policy without erasing reached-cycle state.

The signed Debug build passed, and CoreDevice confirmed installation and launch on the iPhone. Build log: `build/validation/daywell-allowance-ui-build.log`. Existing assertions were updated; tests were not run. The report's appearance and exhaustion transition have not been observed on the physical screen.

## Ocean sunset artwork

The MIT-licensed ocean sunset from ascii.rest is bundled as a static image for offline display. It appears in the native launch storyboard, the initial loading view, the dashboard status-card background, and the Screen Time shield's supported image slot. White dashboard/report text and a dark overlay replace the former green-card styling. The shield uses matching dark colors; Apple controls its image sizing and layout.

The signed Debug build passed (`build/validation/daywell-ocean-art-build.log`). The compiled launch storyboard, image catalogs, and attribution files were confirmed in the main app and applicable extension. CoreDevice confirmed the updated app installed on the iPhone. Tests were not run; on-device artwork layout and the shield's final image sizing have not been visually confirmed.

The blocking-screen artwork was subsequently reverted at the user's request. The shield again uses its leaf icon, system background, and adaptive text colors. The sunset remains on launch/loading screens and the dashboard. The signed rebuild passed (`build/validation/daywell-shield-revert-build.log`) and CoreDevice confirmed installation on the iPhone.

## Approved icon and optional rules

The user-approved square sunset crop now supplies the Home Screen icon and the shield's image slot (rendered at 3x). Both the dashboard and shield use “The allowance is used for today. It will reset at midnight”. The shield's fallback no longer includes the “Come back” sentence.

Schedules and allowance now share a single card in setup and the dashboard. Either rule can be omitted; absent rules have Add controls instead of empty sections, and usage is hidden without an allowance. Explicit removal replaces the old allowance toggle. Active allowance removal remains queued until the next reset and is displayed under Upcoming changes; before activation, removal is immediate. Reconciliation no longer restores an absent allowance or cancels its removal.

The signed Debug rebuild passed (`build/validation/daywell-icon-rules-build.log`) and CoreDevice confirmed installation on the iPhone. Existing core assertions were adjusted for optional allowances; tests were not run. Actual shield appearance and optional-rule transitions remain unverified on-device.

## Temporary testing reset

Debug builds now include a Testing card with Reset all limits, available even during a block. The dedicated reset operation clears schedules, allowance, exhausted cycles, staged state, pending edits, shields, and owned monitors while preserving selected apps. Fresh generation/cycle IDs discard old threshold callbacks; reconciliation leaves an empty policy unmonitored. The reset does not erase Apple's usage history and is not run automatically at installation.

The signed Debug build passed (`build/validation/daywell-testing-reset-build.log`) and CoreDevice confirmed installation on the iPhone. No tests were added or run. Manual reset behavior on the phone and the Release build have not been checked in this pass; the button and API are guarded by `#if DEBUG`.

The user subsequently confirmed the testing reset worked and requested its removal. The Testing card, model action, and core reset API have been removed entirely. The signed Debug rebuild passed (`build/validation/daywell-remove-reset-build.log`), and CoreDevice confirmed installation on the iPhone. Saved rules were not modified by this update. No tests were added or run.

## Shield icon resolution

The shield's leaf was handed to the system as a bare SF Symbol, which rasterises at body-text size (about 17pt) before the shield upscales it into its icon slot, so it appeared blurry. The symbol is now rendered at 100pt into a 120pt square bitmap at 3x scale and cached before being passed to `ShieldConfiguration`, so the shield receives a 360px image and no longer upscales. The leaf motif, green tint, system background, and adaptive text colors are unchanged.

The signed Debug build passed (`build/validation/daywell-shield-icon-build.log`) and CoreDevice confirmed installation on the iPhone. Tests were not run; the sharper icon has not yet been observed on the physical shield.

## Family Controls distribution and App Store export

On October 8, 2026, Family Controls (Distribution) was confirmed **Assigned** in Apple Developer for the main app and all four Screen Time extensions. The capability was enabled and saved on all five App IDs. Xcode then generated fresh App Store provisioning profiles and successfully created a signed Release archive and local App Store export of version **1.0**, build **1**.

The exported app and all four extensions were checked against their embedded provisioning profiles: Family Controls enabled, shared App Group matching, application identifiers matching, debugging disabled, App Store distribution profiles, and iPhone-only device families. Individual signatures and the app's deep signature verification passed.

Artifacts: `build/Daywell.xcarchive`, `build/AppStoreExport/Daywell.ipa`. Evidence: `build/validation/distribution-archive.log`, `build/validation/distribution-export.log`, `build/validation/distribution-verification.json`, and `build/validation/family-controls-enabled.jpg`.

This export has not been uploaded to App Store Connect or submitted to App Review. These signing checks do not verify the pending physical-device Screen Time behaviors above.

The release was rebuilt after replacing an unsupported open-source claim in the app footer. It was rebuilt again after the user requested removal of the external coffee link and set a $0.99 one-time price. The canonical archive and IPA paths above now contain this latest build. All five bundles passed the profile, entitlement, iPhone-only, and signature checks. Current evidence: `build/validation/distribution-archive-099.log`, `build/validation/distribution-export-099.log`, and `build/validation/distribution-verification-099.json`.

On October 9, 2026, all five development profiles embedded in that Release archive were decoded and confirmed to include the connected iPhone, team `VA23K94D58`, Family Controls, and iPhone-only device families. CoreDevice successfully installed `build/Daywell.xcarchive/Products/Applications/Daywell.app` on the iPhone. Launch was denied because the phone was locked; current-release screenshots have not yet been captured. This installation does not add runtime Screen Time test evidence.

Xcode Organizer's custom App Store Connect upload flow rejected its cached Personal Team as not enrolled in the Apple Developer Program. Refreshing manual profiles completed but did not expose a paid team. No upload occurred. The Apple web session also expired overnight and requires sign-in before the saved store state can be checked again.

After the user restored Apple sign-in and unlocked the phone, CoreDevice successfully launched the current installed Daywell build. Xcode captured its dashboard in `build/screenshots/current/daywell-current.png`, at 1206 × 2622 with no alpha. The screenshot has no simulator banner or shared-storage warning. App Store Connect's live medium Dynamic Island slot accepts these dimensions. Automatic approval review rejected uploading the capture because it contains on-device app selection and usage information; specific user approval is pending. No screenshot upload occurred at that point; the subsequent binary-upload attempt and packaging correction are recorded below. The listing's saved text and populated, browser-valid review-contact phone survived the expired session. Mac and Vision Pro compatibility distribution were disabled and the Pricing and Availability page displayed **Saved**; evidence is `build/validation/availability-iphone-only.jpg`.

## User-reported physical-device test

On October 8, 2026, the user confirmed that Daywell was tested on a physical iPhone. The individual results and callback delays from `DEVICE_VALIDATION.md` were not provided, so the detailed acceptance matrix remains unrecorded. This confirmation clears the user's requested publishing step; any known failure should be resolved before submission.


## Editable rules and Upcoming changes — October 8, 2026

Removed the schedule-active edit prohibition from both the UI and core. All editors remain available during a scheduled block. Lower allowances, added apps, and schedules covering all currently blocked minutes apply immediately; allowance increases/removal, app removals, and schedules freeing blocked minutes are queued. Mixed app replacements protect additions immediately and defer removals. Schedule/app changes capture the next reset or the end of occurrences spanning that reset as a fixed deadline, avoiding indefinite deferral under full-day coverage.

Upcoming changes now includes queued schedules, target allowance, target app selection, effective dates, and cancellation. Editors initialize from queued values once per presentation. Cancelling pending changes retains immediate strengthening. The optional persisted schedule field is backward compatible with existing saved documents.

The periodic status refresh no longer disables editing or reinstalls monitors. Foreground reconciliation finishes before a save starts, and revision checks discard stale refresh results.

The signed Debug build succeeded, and CoreDevice confirmed installation and launch on the connected iPhone. Build log: `build/validation/daywell-editing-build.log`. Existing test assertions were updated for the new semantics; automated tests were not run in this pass. Physical interaction, midnight/overnight transitions, and iOS callback timing remain to be checked on this build. Earlier test counts in this document are historical.

## ExtensionKit packaging correction — October 9, 2026

After Xcode sign-in recognized the paid team, the build-1 upload reached Apple and was rejected with error 91179: ActivityReport must use ExtensionKit, embed under `Extensions/`, and declare `EXAppExtensionAttributes`. The installed Xcode Device Activity Report template confirms this format. Updated `project.yml` to use `extensionkit-extension`, replaced the report plist keys, and regenerated the project. Version plist values now use the build settings for all five targets; version is 1.0, build 2.

Signed archive and App Store export succeeded: `build/Daywell-build2.xcarchive` and `build/AppStoreExport-build2/Daywell.ipa`. All five exported bundles passed signature verification, iPhone-only device family, Family Controls and App Group entitlement/profile matching, distribution-only signing, team ID, bundle identifier, and version checks. ActivityReport exists only under `Extensions/`, has the correct ExtensionKit attributes, and has no `NSExtension` key. Evidence: `build/validation/distribution-verification-build2.json`, `distribution-archive-build2.log`, and `distribution-export-build2.log`. Xcode Organizer confirmed **Daywell 1.0 (2) uploaded**, followed by **Uploaded to Apple**, at 10:38 on October 9. Evidence: `build/validation/xcode-upload-build2-complete.png`. App Store Connect’s TestFlight Build Uploads table confirms **version 1.0, build 2 — Processing**, uploaded October 9 at 10:38 AM. Evidence: `build/validation/testflight-build2-processing.jpg`. Processing has not yet completed and the app has not been submitted for review. No runtime source changes or new physical-device test claims are made for this configuration fix.

## Free release pricing — October 9, 2026

At the user’s request, App Store Connect’s global price schedule was changed from $0.99 to $0.00, effective immediately. The saved current-price popover lists zero prices across all 175 territories. Evidence: `build/validation/pricing-free-confirmed.jpg`. Publishing text and the public privacy page now describe a free app; the updated public Site deployment succeeded (version 4). The Free Apps Agreement is active, so the unfinished Paid Apps Agreement is no longer a release blocker for this app with no in-app purchases. EU trader-status compliance remains required for EU availability. Price changes are store metadata and require no new binary; build 1.0 (2) remains the uploaded build.

## Store readiness check — October 9, 2026

The browser now shows EU DSA compliance Active and the existing non-trader declaration selected. No compliance declaration was changed in this pass. Build 1.0 (2) is attached to the store version; three iPhone screenshots are saved. Add for Review failed with only the unpublished app-privacy information requirement reported. The final Data Not Collected publication dialog is open pending explicit user confirmation of Apple’s accuracy/legal declaration; no review submission occurred.

## Successful App Review submission — October 9, 2026

The user published the Data Not Collected privacy label, resolving the earlier Add for Review validation error. Version 1.0, build 2 was submitted at 11:16 AM by Gleb Melnikov. App Store Connect confirmed “1 Item Submitted” and the review detail shows Waiting for Review. Submission ID: `99686a9d-e6a2-4686-98fd-514a9d72a3db`. Automatic release after approval is selected. Evidence: `build/validation/app-review-submitted.jpg` and `build/validation/app-review-waiting.jpg`. This supersedes earlier processing and not-submitted status entries; the app is not yet publicly released.

Apple’s Included Assets → App Icon preview visibly contains the correct sunset icon from build 2, despite the generic header placeholder. Evidence: `build/validation/app-store-icon-confirmed.jpg`. No icon rebuild or replacement was needed.
