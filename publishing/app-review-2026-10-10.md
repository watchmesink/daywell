# Family Controls rejection — October 10, 2026

**Status:** Apple’s response is pending; the rejection remains unresolved. Gleb Melnikov sent the reply below on **October 10, 2026 at 09:50 local time**. The live App Review conversation was verified in Dia: **Messages (2)** includes Gleb’s posted reply with all five bundle IDs and the metadata link, and **Reply to App Review** is available again. The metadata attachment was not attached because Apple’s upload returned a generic error on both attempts. No rebuild, app source change, or resubmission has been made.

Apple rejected Daywell **1.0 (2)** under Guideline **2.5.1**, stating that automated analysis found Screen Time API use without the Family Controls entitlement. The submitted binary and Apple's own processed metadata contradict that finding. No missing entitlement or signing defect was found; the cause of Apple's automated discrepancy requires App Review to recheck.

## Verified evidence

- [App Store Connect build metadata](https://appstoreconnect.apple.com/teams/412c5bea-4898-45a8-9011-b1242e545b75/apps/6820666833/testflight/ios/cc965576-6272-4bac-977a-2cca059453b6/metadata), inspected in Dia on October 10, lists `com.apple.developer.family-controls: true` for the main app and all four extensions under **Store Information → Entitlements**. **Binary State** is **Validated**.
- The exact IPA used by the successful October 9 upload was independently inspected. All five bundles have the entitlement in both their signatures and embedded App Store provisioning profiles, use team `VA23K94D58` and the matching App Group, and pass strict signature verification. The app also passes deep signature verification.
- Apple's upload log records app ID `6820666833`, version `1.0`, build `2`, and MD5 `e4f35f9b875e63ef4e0a2dbe7a2671d7`, matching the inspected IPA. Upload succeeded at **2026-10-09 08:38:33 UTC**. SHA256: `328699cd18c5bad2ce28b119bc52548b6c6cf67291f700f981c4ef8b3b721f42`.
- [App Store Connect metadata transcript](evidence/app-store-connect-build2-metadata.txt) preserves the live entitlement entries read in Dia. The main app’s Apple Developer Capability Requests page also showed Family Controls (Distribution) as **Assigned** on October 10; the ActivityReport capability page showed the distribution checkbox enabled.
- [Sanitized audit JSON](evidence/uploaded-build2-entitlements.json) records the per-bundle checks and upload correlation. It excludes local user paths, credentials, certificates, and raw network logs.
- [Posted reply transcript](evidence/app-review-reply-sent.txt) preserves the message Gleb sent and the live **Messages (2)** confirmation. The submission remains **Unresolved Issues / Rejected** while Apple’s response is pending.

[Review submission](https://appstoreconnect.apple.com/apps/6820666833/distribution/reviewsubmissions/details/99686a9d-e6a2-4686-98fd-514a9d72a3db): `99686a9d-e6a2-4686-98fd-514a9d72a3db`.

## Sent reply

Hello App Review,

Please manually recheck the Guideline 2.5.1 finding for Daywell 1.0 (2), app ID 6820666833, team VA23K94D58, submission 99686a9d-e6a2-4686-98fd-514a9d72a3db.

App Store Connect's processed Build Metadata > Store Information > Entitlements lists com.apple.developer.family-controls: true for the main app and all four extensions. Binary State is Validated:
https://appstoreconnect.apple.com/teams/412c5bea-4898-45a8-9011-b1242e545b75/apps/6820666833/testflight/ios/cc965576-6272-4bac-977a-2cca059453b6/metadata

The affected bundle IDs are:

- dev.glebmelnikov.InstaBlock
- dev.glebmelnikov.InstaBlock.ActivityMonitor
- dev.glebmelnikov.InstaBlock.ShieldConfiguration
- dev.glebmelnikov.InstaBlock.ShieldAction
- dev.glebmelnikov.InstaBlock.ActivityReport

We also verified the exact uploaded IPA against the successful upload log's checksum. All five bundles contain the Family Controls entitlement in their signed entitlements and App Store provisioning profiles, and their signatures pass verification.

Could you recheck the automated finding and continue review? If a requirement remains unmet, please identify the specific bundle or executable and the missing entitlement or approval so we can address it precisely.

Thank you.
