# Physical-device validation

A simulator build and core tests cannot verify Apple's authorization, callback delivery, shields, or usage measurements. Record the device model, iOS version, signing method, times, and observed delays for each check below. Use a test app or deliberately short temporary settings before enabling your intended routine.

## Setup

1. Install a development-signed build with all extensions and entitlements.
2. Grant Screen Time access and choose two installed apps, a whole category, and a website. Repeat activation with only a category and only a website.
3. Before activation, set the daily allowance to two minutes and use a scheduled window of **at least 15 minutes** that starts shortly in the future.
4. Record whether Screen Time “Share Across Devices” is enabled. Keep it off for an isolated-device timing check.
5. Note any selected activity earlier today: it counts toward the shared threshold. Do not infer a timing bug just because earlier use exhausts the two-minute allowance immediately.

## Acceptance checks

| Check | Expected result | Result / observed delay |
| --- | --- | --- |
| Grant / deny permission | Denial shows a recoverable access state; approval permits activation | Pending |
| Start scheduled window with Daywell closed | Selected apps, sites, and apps/sites in selected categories receive blocking shields | Pending |
| Category-only / website-only selection | Activation succeeds, rules and usage monitors apply, and choices survive reopening | Pending |
| Category website shield | Websites within a selected category receive the custom Close-only shield | Pending |
| Existing installation update | Old app selections, exhausted allowance, and queued changes survive the schema upgrade | Pending |
| Shield buttons in light/dark mode | Native button colors and label; closes the blocked app, with no bypass or extra-time control | Pending |
| Edit during a scheduled block | All editors open and save. Lower allowances, added apps, and more blocked time apply immediately; weaker edits appear under Upcoming changes and retain current protection | Pending |
| End scheduled window with allowance left | Selected activity becomes usable; daily usage is retained | Pending |
| Split usage across apps, categories, websites, and sessions | Combined usage reaches one shared daily threshold | Pending |
| Exhaust daily allowance | Every selected target is shielded until budget reset, including after a scheduled block ends | Pending |
| Increase/remove allowance | Today remains unchanged; pending value or removal applies at reset. Unconfigured rules are omitted from the combined card | Pending |
| Add/remove an app, category, or website | Additions apply immediately, including during blocks, without resetting exhaustion; removals remain queued until the displayed deadline tomorrow after any occurrence spanning midnight ends. Mixed replacements add now and remove later. Active and upcoming selections are displayed separately | Pending |
| Shorten, move, or remove schedule | Current windows remain; target windows and date appear under Upcoming changes, survive reopening, and activate at the saved deadline | Pending |
| Cancel pending changes | Pending allowance, selections, and schedules clear; immediate additions and stricter rules remain | Pending |
| Overlapping windows | End of the first window does not unblock while another remains active | Pending |
| Overnight / midnight | Schedule persists across reset; only the exhausted budget layer resets | Pending |
| Force-quit Daywell | Scheduled and usage callbacks continue to enforce restrictions | Pending |
| Reboot, then first unlock | Persisted rules and allowance remain; monitor callbacks recover | Pending |
| Offline / airplane mode | Rules continue to run locally | Pending |
| Revoke / restore Screen Time access | App reports lost access; restoration reapplies saved restrictions | Pending |
| Uninstall | iOS removes the app's protection; this is an accepted escape route | Pending |
| Time-zone / DST transition | Local schedules reconcile; existing budget is not reset just by reopening | Pending |
| Screen Time report | Selected activity is prominent, total screen time is smaller, and both match current-device Screen Time; data stays inside the extension | Pending |
| Usage comparison | Total screen time versus the previous seven complete days; decreases green, increases red; no selected-activity comparison | Pending |
| Dashboard scrolling | Swipes beginning over either usage report scroll normally, and position stays stable through periodic refreshes; no dashboard icon row | Pending |

After the short checks, choose your intended daily blocks (optional) and allowance using the editors at any time. Fresh installations have no prefilled daily blocks and start with a 30-minute allowance. Raising a test allowance to 30 minutes is intentionally queued until the next day. Record a complete normal day, including midnight, before treating the build as verified for daily use.

If callbacks are delayed or missing, capture device logs under the `Daywell` subsystem, the configured intervals, and the OS version. Do not mark a test passed using simulated callbacks or the rule-test driver.
