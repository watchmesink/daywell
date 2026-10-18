# Daywell 1.1.1 (8)

Prepared October 18, 2026, following the released version 1.1 (5).

## Changes

- Today's selected usage sums filtered app and website activity instead of the device-wide aggregate. Total screen time appears separately with a percentage against the previous seven complete days.
- Removed the dashboard icon carousel, title, decorative sun, and selected-activity percentage. Selection editors retain stable token ordering.
- Read-only reports pass swipes through to the dashboard; timed status updates and unchanged storage polls no longer redraw the entire dashboard.
- Shield buttons use native system styling. Both Home Screen appearances use the requested dark icon fallback.
- Refreshed all six App Store slides in both supported iPhone screenshot sizes to match the updated interface.

## Validation

- All 62 core tests passed for the release, including eight usage-statistics regressions.
- Three simulator UI gesture checks passed using the production layout with mock report data, including scroll stability through a timed update.
- The equivalent development build 1.1 (7) was installed and launched on the connected iPhone 16 Pro.
- Signed Release archive and App Store export succeeded. The exact exported IPA passed strict signatures, version/build, iPhone-only support, Family Controls and shared App Group entitlement/profile checks for all five bundles. ActivityReport uses the required ExtensionKit packaging.
- [Sanitized IPA audit](evidence/release-1.1.1-build8-audit.json). SHA-256: `bb2d590a730f44e9c2ac0ace517805453b12d7f998dffc94dfc5844f87a2d5a4`.

Native shield rendering and scrolling with Apple's live report process have not been directly observed by automation. Simulator reports use explicit sample values.

## Release status

Version **1.1.1 (8)** uploaded successfully and processed as **VALID**. It was submitted at **15:23:20 UTC (17:23 Berlin time) on October 18, 2026**. Both the submission and version read back as **WAITING_FOR_REVIEW**. It will release automatically after approval; version 1.1 remains live until then.

- [Review submission](https://appstoreconnect.apple.com/apps/6820666833/distribution/reviewsubmissions/details/75437723-d37b-4f59-8422-fb03716ba375)
- [Verified submission and screenshot metadata](evidence/release-1.1.1-submission.json)
- [PR #3](https://github.com/watchmesink/daywell/pull/3), source commit `3d5ec37`
