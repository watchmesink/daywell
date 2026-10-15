# App Review correction — October 15, 2026

Apple reviewed version **1.1 (4)** on an **iPad Air 11-inch (M3)**. Submission: `4b49f91f-095d-4252-92c9-943608d8a9b2`.

## Findings

**Guideline 2.3.7 — Accurate Metadata:** screenshots include references to the app's price. Apple explicitly counts references to free or discounted services as pricing references and asks that they be removed from metadata; pricing may be described in the app description.

**Guideline 5.1.1(iv) — Privacy:** a custom message before Screen Time authorization uses an **Enable Screen Time Access** button. Apple requests a neutral **Continue** or **Next** button.

## Corrections

- Changed the onboarding authorization button and the dashboard reauthorization button to **Continue**.
- Replaced screenshot 6 in both size sets with **Your time. Your routine.** and **Set daily blocks and a shared allowance that fit your day.**
- Prepared subtitle **Screen time, simple & private** and promotional text without pricing references. Pricing remains only in the app description.
- Updated reviewer instructions to match current app, category, and website selection and the new permission button.
- Increased the build number to **5**, keeping version **1.1**.

## Validation

- All **54** existing tests passed.
- Signed Release archive succeeded: `build/Daywell-1.1-build5.xcarchive`.
- Verified signatures, version **1.1 (5)**, Family Controls entitlement, and shared App Group on the app and all four extensions. Audit: `build/validation/review-fix-archive-audit.json`.
- Regenerated the screenshot sets and visually inspected the replacement slide.

## Submission status

Version **1.1 (5)** was uploaded successfully, processed as **VALID**, attached to the existing review submission, and **resubmitted at 09:08:49 UTC (11:08 Berlin time) on October 15, 2026**. Both the submission and the version read back as **WAITING_FOR_REVIEW**. Release remains automatic after approval.

Submission: `4b49f91f-095d-4252-92c9-943608d8a9b2`.
Build: `8cd62268-7bbc-413b-999d-8177c01830f3`.

Evidence: [metadata read-back](evidence/review-fix-metadata-2026-10-15.json), [confirmed resubmission](evidence/review-resubmitted-2026-10-15.json).

The API uses team key `CD7FGT83L2` with Issuer ID `412c5bea-4898-45a8-9011-b1242e545b75`, recovered from the signed-in Integrations page. The private key remains outside the repository. The local ignored API client now defaults to this issuer.
