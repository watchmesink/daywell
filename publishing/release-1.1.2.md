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

The updated optional-report privacy policy is live at [the existing privacy URL](https://daywell-support.tunedtoast2.chatgpt.site/privacy.html); [deployment evidence](evidence/release-1.1.2-privacy-deployment.json). App Store processing and submission status will be recorded after Apple accepts the upload.
