# Daywell 1.1.2 (10)

Prepared October 27, 2026, following the released version 1.1.1 (8).

## What's New

• Improved recovery after interrupted Screen Time updates.
• Improved daily-reset and scheduled-block updates while Daywell is open.
• Reset messages now show the correct local time after travel.
• Added Share problem to share a diagnostic report when something goes wrong.

## Validation

- All 93 core tests passed, including 21 new protection-recovery, threshold-transfer, and reset-message regressions.
- The standalone audit verifies five corrected scenarios using simulated clocks and callbacks.
- The app, all four extensions, and the reusable screenshot preview built successfully for the simulator.
- The actual-app simulator sharing flow passed, including creating a JSON attachment and cancelling without sending it. An additional earlier check verified that sharing can export a partial report when saved protection state is unreadable.
- Native iOS premature threshold delivery was not reproduced on a physical device; this release improves application recovery and diagnostic evidence and does not claim to fix Apple's usage accounting.

## Release status

The initial build 9 upload was accepted. Final release checks identified missing required-reason API declarations in the new diagnostics, so build 10 supersedes that candidate. It adds privacy manifests to all five bundles and a prominent device-uptime disclosure before the user chooses to share a report. Build 9 will not be submitted for App Review.

The final build 10 archive and App Store export succeeded. Its exact IPA passed the five-bundle signing, entitlement, profile, version/build, iPhone-only, ExtensionKit, and required-reason privacy-manifest checks. [Final IPA audit](evidence/release-1.1.2-build10-audit.json). The final simulator UI test also verified that uptime is visible before the user opens the native share sheet.

The updated optional-report privacy policy is live at [the existing privacy URL](https://daywell-support.tunedtoast2.chatgpt.site/privacy.html); [deployment evidence](evidence/release-1.1.2-privacy-deployment.json). Apple accepted final build 10, processed it as **VALID**, and the version was submitted at **16:28:19 UTC (17:28 Berlin time) on October 27, 2026**. Both the version and submission read back as **WAITING_FOR_REVIEW**. Automatic release after approval is selected.

- [App Review submission](https://appstoreconnect.apple.com/apps/6820666833/distribution/reviewsubmissions/details/a80401d2-d923-483f-8019-1f5bce2bd082)
- [Verified submission evidence](evidence/release-1.1.2-submission.json)
- [GitHub PR #5](https://github.com/watchmesink/daywell/pull/5)
- Final implementation commit: `0471de3cde8f36f937975f3e04f0275eb475b919`.
