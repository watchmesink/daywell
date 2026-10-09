# Physical-device validation

A simulator build and core tests cannot verify Apple's authorization, callback delivery, shields, or usage measurements. Record the device model, iOS version, signing method, times, and observed delays for each check below. Use a test app or deliberately short temporary settings before enabling your intended routine.

## Setup

1. Install a development-signed build with all extensions and entitlements.
2. Grant Screen Time access and choose two installed apps. Confirm categories and websites are rejected.
3. Before activation, set the daily allowance to two minutes and use a scheduled window of **at least 15 minutes** that starts shortly in the future.
4. Record whether Screen Time “Share Across Devices” is enabled. Keep it off for an isolated-device timing check.
5. Note any selected-app usage earlier today: it counts toward the shared threshold. Do not infer a timing bug just because earlier use exhausts the two-minute allowance immediately.

## Acceptance checks

| Check | Expected result | Result / observed delay |
| --- | --- | --- |
| Grant / deny permission | Denial shows a recoverable access state; approval permits activation | Pending |
| Start scheduled window with Daywell closed | Both selected apps receive blocking shields | Pending |
| Shield buttons | Close only; no bypass or extra-time control | Pending |
| Edit during a scheduled block | All editors open and save. Lower allowances, added apps, and more blocked time apply immediately; weaker edits appear under Upcoming changes and retain current protection | Pending |
| End scheduled window with allowance left | Both apps become usable; daily usage is retained | Pending |
| Split usage across selected apps and sessions | Combined usage reaches one shared daily threshold | Pending |
| Exhaust daily allowance | Both apps are shielded until budget reset, including after a scheduled block ends | Pending |
| Increase/remove allowance | Today remains unchanged; pending value or removal applies at reset. Unconfigured rules are omitted from the combined card | Pending |
| Add/remove an app | Additions apply immediately, including during blocks, without resetting exhaustion; removals remain queued until the displayed deadline tomorrow after any occurrence spanning midnight ends. Mixed replacements add now and remove later. Active and upcoming selections are displayed separately | Pending |
| Shorten, move, or remove schedule | Current windows remain; target windows and date appear under Upcoming changes, survive reopening, and activate at the saved deadline | Pending |
| Cancel pending changes | Pending allowance, apps, and schedules clear; immediate additions and stricter rules remain | Pending |
| Overlapping windows | End of the first window does not unblock while another remains active | Pending |
| Overnight / midnight | Schedule persists across reset; only the exhausted budget layer resets | Pending |
| Force-quit Daywell | Scheduled and usage callbacks continue to enforce restrictions | Pending |
| Reboot, then first unlock | Persisted rules and allowance remain; monitor callbacks recover | Pending |
| Offline / airplane mode | Rules continue to run locally | Pending |
| Revoke / restore Screen Time access | App reports lost access; restoration reapplies saved restrictions | Pending |
| Uninstall | iOS removes the app's protection; this is an accepted escape route | Pending |
| Time-zone / DST transition | Local schedules reconcile; existing budget is not reset just by reopening | Pending |
| Screen Time report | Combined selected-app usage appears without being exported to parent storage | Pending |

After the short checks, restore the intended **06:00–10:00**, **22:00–00:00**, and **30-minute** rules using the editors at any time. Raising a test allowance to 30 minutes is intentionally queued until the next day. Record a complete normal day, including midnight, before treating the build as verified for daily use.

If callbacks are delayed or missing, capture device logs under the `Daywell` subsystem, the configured intervals, and the OS version. Do not mark a test passed using simulated callbacks or the rule-test driver.
