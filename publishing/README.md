# Daywell App Store release kit

This folder contains text ready to enter in Apple Developer and App Store Connect. The public privacy and support pages are in `docs/`. The app icon is already in `App/Assets.xcassets/AppIcon.appiconset/DaywellIcon.png` (1024 × 1024, no alpha channel).

## Current status

- A paid team has signed and installed development builds on an iPhone.
- On October 8, 2026, **Family Controls (Distribution)** was confirmed assigned, enabled, and saved for the app and all four extensions. Xcode generated fresh App Store provisioning profiles for all five targets; their profiles and signed entitlements include Family Controls and the shared App Group.
- The corrected signed Release archive and App Store export are `build/Daywell-build2.xcarchive` and `build/AppStoreExport-build2/Daywell.ipa` (version **1.0 (2)**). The coffee link is removed. All five bundles passed signature, distribution profile, Family Controls, App Group, version, and iPhone-only checks. The usage-report extension now uses ExtensionKit and embeds in `Extensions/`, matching Apple’s Xcode template. Evidence: `build/validation/distribution-verification-build2.json`.
- You confirmed the app has been tested on a physical iPhone. Individual results and observed Screen Time callback delays have not yet been recorded in `docs/DEVICE_VALIDATION.md`.
- A clean dashboard screenshot was captured from the current Release build on the physical iPhone on October 9: `build/screenshots/current/daywell-current.png` (**1206 × 2622**, no alpha). It matches the live App Store Connect medium Dynamic Island slot. Its dimensions and checksum are recorded in `build/screenshots/current/manifest.json`. The screenshot is now saved in App Store Connect alongside `IMG_9042.PNG` and `IMG_9041.PNG`; three iPhone screenshots were verified in the browser. The older InstaBlock and simulator screenshots must not be submitted.
- Public support email: `melnikovglebdm@gmail.com`. The pages are live: [support](https://daywell-support.tunedtoast2.chatgpt.site/support.html) and [privacy](https://daywell-support.tunedtoast2.chatgpt.site/privacy.html). The public Site project ID is `appgprj_6ac7e46400e48191b014440cceb32af2`; its local checkout is under ignored `build/DaywellSite/`. Edit `docs/` first, then sync and republish the Site before changing the App Store URLs.
- The App Store Connect Terms of Service has been accepted. App record **6820666833** exists for iOS, English (U.S.), bundle ID `dev.glebmelnikov.InstaBlock`, SKU `DAYWELL-IOS-001`. The current store name is **“Daywell: Control Screen time”**; “Daywell” was unavailable; this title was submitted for review. The subtitle is “Make room for your day.” The on-device display name can remain Daywell.
- The user switched the app to **free** on October 9. The Free Apps Agreement is active; the Paid Apps Agreement, banking, and payout-tax setup are not required for this free app with no in-app purchases. EU DSA compliance is now **Active**; the saved declaration is **non-trader**, verified in the browser. The current availability covers **175 territories**.
- App Information now has Productivity as its primary category, content rights declared for the licensed third-party artwork, and the age-rating questionnaire completed. Apple calculated 9+ in 172 regions, with regional differences. App Privacy’s “Data Not Collected” label and privacy-policy URL are published.
- After Apple sign-in was restored on October 9, the version form retained its description, keywords, support URL, copyright, review notes, and review-contact fields. Its Save control was disabled, indicating no unsaved changes. The phone field was checked without exposing the number: it is populated and passes browser validity. Build **1.0 (2)** has finished processing and is already attached to the store version.
- On October 9, the current Release archive's development profiles were verified to cover the connected iPhone and retain Family Controls on all five bundles. CoreDevice installed and launched that current Daywell build successfully. A clean physical-device dashboard capture is ready as described above.
- Project and Info plist release versions are aligned at 1.0; increment the build number for each subsequent upload.
- The in-app **Buy me a coffee** link remains removed. App Store Connect now has a **Free ($0.00)** price in all 175 territories, effective immediately, replacing the earlier $0.99 schedule. Evidence: `build/validation/pricing-free-confirmed.jpg`. Mac and Vision Pro compatibility distribution remain disabled for the iPhone-only release. No binary rebuild is needed for the price change.

## Release order

1. **Completed:** Family Controls distribution access is assigned and enabled for all five IDs listed in `family-controls-request.md`, and fresh App Store profiles were verified in the exported app. No further entitlement request is needed for these IDs based on the October 8 verification.
2. **User confirmed testing:** Daywell was tested on a physical iPhone. If any checks in `docs/DEVICE_VALIDATION.md` failed or showed significant delays, record them in `docs/VALIDATION.md` before App Review.
3. **Completed:** Public support and privacy pages are hosted at the URLs above.
4. **Completed:** EU DSA compliance is Active with the saved non-trader declaration. Free pricing is saved for all 175 territories.
5. **Completed:** Listing metadata and review contact are saved; the user published the Data Not Collected privacy label.
6. **Completed:** Three physical-iPhone screenshots are saved in the medium Dynamic Island slot.
7. **Completed:** Build 1.0 (2) was uploaded, processed, and selected. Apple rejected build 1 with error 91179; build 2 fixes the ActivityReport ExtensionKit packaging. Increment the build number for future uploads.
8. **Submitted:** Version 1.0, build 2 is Waiting for Review. Automatic release after approval is selected. Wait for Apple’s review email and respond to any review questions.

Apple references: [Family Controls setup](https://developer.apple.com/documentation/xcode/configuring-family-controls), [Capability Requests](https://developer.apple.com/help/account/capabilities/capability-requests), [new app record](https://developer.apple.com/help/app-store-connect/create-an-app-record/add-a-new-app/), [screenshot specifications](https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications), [app privacy](https://developer.apple.com/help/app-store-connect/manage-app-information/manage-app-privacy), [submit an app](https://developer.apple.com/help/app-store-connect/manage-submissions-to-app-review/submit-an-app).

## Latest submission check — October 9, 2026

Version **1.0 (2)** was submitted on October 9, 2026 at **11:16 AM**, by Gleb Melnikov, and is **Waiting for Review**. Submission ID: `99686a9d-e6a2-4686-98fd-514a9d72a3db`. [Open review status](https://appstoreconnect.apple.com/apps/6820666833/distribution/reviewsubmissions/details/99686a9d-e6a2-4686-98fd-514a9d72a3db). Apple confirmed “1 Item Submitted”; automatic release after approval is selected. The earlier unpublished-privacy validation error was resolved by the user publishing the label.

Apple’s Included Assets → App Icon preview shows the correct Daywell sunset icon from build 2. The generic header icon does not mean the uploaded asset is missing. Evidence: `build/validation/app-store-icon-confirmed.jpg`, `build/validation/app-review-submitted.jpg`, and `build/validation/app-review-waiting.jpg`.
