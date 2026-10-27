# Protection audit — October 26–27, 2026

The reported symptom was Instagram blocked immediately with a 30-minute allowance and “Selected activity today: 0 min.” The initial investigation added diagnostics and Share problem without changing enforcement. On October 27, the confirmed application defects below were fixed and given regression coverage. The failure descriptions preserve what was reproduced before those fixes.

The standalone harness now verifies the corrected capacity, foreground reset, travel messaging, failed repair, and interrupted-stage recovery scenarios. The original suspected iOS premature callback remains an on-device investigation; these fixes do not claim to correct Apple's usage accounting.

## Original incident: a premature threshold can exhaust the day

**Confirmed mechanism; the affected device's trigger is unconfirmed.** The coordinator accepts a matching current-cycle `daily-limit` callback, including one delivered during first registration. The result survives commit and subsequent launches until the cycle resets. The report's usage measurement is independent of this flag. Diagnostic tests reproduce the sequence without advancing the clock or providing any usage.

`ScreenTimeDriver.install` sets `includesPastActivity: true`, so real selected activity earlier in the same day can legitimately cause immediate exhaustion. A true zero-usage case also matches [reports of premature callbacks on Apple's developer forums](https://developer.apple.com/forums/thread/808470). The screenshot cannot distinguish a false callback from legitimately counted earlier activity or incomplete report data.

## 1. Monitor recovery can repeatedly fail after interrupted cleanup

**Fixed October 27.** Reconciliation retires obsolete owned generations before installing a replacement. Active and unrelated registrations remain intact, including if the next installation fails. `RecoveryTests` reproduces the 20-registration crash state and verifies successful midnight recovery with exactly ten current registrations.

**High priority; reproduced with a driver enforcing Apple's 20-activity limit.**

With seven windows, one midnight monitor, and two budget monitors, a generation has ten registrations. If the process dies after a new generation is committed but before the previous one is retired, both generations can remain registered and `staged` is already nil. If the day changes before the next reconciliation, the prospective plan differs from the saved plan. The coordinator attempts another full replacement before cleaning up unused registrations.

Even allowing the OS to remove both yesterday-only budgets leaves 18 registrations. Installing ten replacements hits the capacity limit; rollback removes the attempted replacement but retains the obsolete generation. Repeated reconciliations take the same failing path. Rules and future monitoring can remain stale, and edits can keep failing.

Evidence: `ProtectionCoordinator.update` only performs general cleanup after an unchanged-plan update or a successful replacement. Its initial recovery handles `saved.staged`, which is nil in this crash window. The audit reproduced three consecutive failures with 18 registrations remaining. This is a core reproduction of the crash/capacity conditions, not a claim that those conditions occurred on the reported phone.

Diagnostic signature: `configuration.staged` lists surplus generations; `monitor.system_failed` reports `excessiveActivities`; `configuration.rolled_back` repeats without retiring the surplus names. Apple's documented limit is [twenty activities across an app and its extensions](https://developer.apple.com/documentation/deviceactivity/deviceactivitycenter/monitoringerror/excessiveactivities).

## 2. A foreground dashboard can disagree with installed shields after a missed boundary

**Fixed October 27.** The 15-second foreground refresh now reconciles protection. It clears expired budget shields and applies schedule transitions without needing an iOS boundary callback. Unchanged plans keep their registered monitors, and unchanged model state does not invalidate the UI. The selected-usage report also moves to the new day when reconciliation rotates the budget cycle.

**Medium priority; reproduced with a delayed midnight callback.**

The dashboard evaluates the decision against the current clock. After midnight, that computation selects tomorrow's unused cycle and displays time available. However, the 15-second foreground timer calls `refresh(reconcileMonitors: false)`, which only reads storage. If the midnight and new-cycle callbacks are delayed or missed, yesterday's budget shield remains installed while the visible status says time is available.

The audit exhausted a day, advanced the clock past midnight, and simulated four read-only polls: the display decision was unblocked while the driver's last applied shield remained blocked. Calling `reconcile()` cleared the discrepancy. Similar disagreements can occur at schedule boundaries. Normal callback delivery or foregrounding the app again usually reconciles the state; remaining in the foreground does not provide that fallback.

Evidence: `App/DaywellApp.swift` foreground timer, `App/ContentView.swift` status timeline, and `ProtectionSnapshot.currentCycle`. Diagnostic signature: an expired cycle in persisted state, no corresponding boundary callback, and a remaining budget shield even though the exported decision is unblocked. A later `shield.presented` event with an unblocked snapshot strengthens that evidence.

## 3. “Reset at midnight” can be false after a time-zone change

**Fixed October 27.** Both the dashboard and shield format the actual stored reset instant in the current time zone. Midnight wording is used only for the next local midnight. Regression cases cover travel, a 25-hour daylight-saving day, later calendar dates, and missing/expired reset instants.

**Medium priority; reproduced with Berlin → Tokyo.**

The core intentionally pins an existing allowance to its original reset instant during travel. On October 26, Berlin midnight is 08:00 on October 27 in Tokyo. An exhausted Berlin cycle therefore remains exhausted during the new Tokyo morning until 08:00. Both the dashboard and shield nevertheless use the hard-coded `ProtectionCopy.allowanceUsed` text promising midnight.

The audit verified the exhausted state, the 08:00 local reset, and the midnight wording. The pinned cycle is an intentional rule; the inaccurate explanation makes correct enforcement look like a failed daily reset.

Evidence: `ProtectionSnapshot.advance`, `ProtectionSnapshot.currentCycle`, and `ProtectionCopy.allowanceUsed`. Diagnostic signature: the environment/schedule time zone differs from the cycle's time zone; `budgetResetsAt` is not midnight in the current zone.

## 4. Failed monitor repair can discard an accepted usage threshold

**Fixed October 27.** Rollback merges compatible threshold evidence into the active snapshot before discarding staged state. Repair with the same targets/allowance therefore remains exhausted after failure and subsequent retry. Tests also verify that a shorter staged allowance or additional staged targets cannot incorrectly exhaust the retained policy.

**Medium priority; reproduced October 27 with failed registration after an accepted callback.**

If iOS loses a configuration's registrations, reconciliation installs replacement monitors under a new generation. A threshold delivered during registration is saved only in the staged snapshot when it matches that new generation. If the next registration fails, rollback deletes the staged snapshot, including the reached threshold, and reapplies the unchanged active policy without its exhaustion flag.

The audit activated a 30-minute allowance, advanced the test clock by 31 minutes, removed the driver's registrations, and delivered today's threshold while the current-day replacement was installed. Registering tomorrow's budget then failed. The report history confirmed `stagedResult: accepted`, followed by `configuration.rolled_back`, while persisted active state and the applied decision remained unblocked. A later successful repair without another threshold callback still left the allowance unexhausted. A subsequent current-generation threshold restored blocking.

This can leave an enforcement gap until iOS sends another threshold callback; it does not show that real usage can be independently verified by the app. The reproduction injects the callback and registration failure instead of observing them on an iPhone. Restricting the case to repair with an identical policy makes the lost callback relevant to the retained rules; a callback for a changed selection or allowance would require a compatibility check before transferring it.

Evidence: `ProtectionCoordinator.update` retains staged thresholds on successful commit but sets `staged = nil` on rollback without merging compatible exhaustion into active state. Diagnostic signature: the same activity appears in `callback.processed` with `stagedResult: accepted`, then a registration failure and rollback; the retained active snapshot has no reached cycle. The reproduction is included in `scripts/audit-protection.swift`; its latest output is `build/validation/daywell-protection-audit-2026-10-27.log`.

## 5. Interrupted staged recovery can lose the same threshold evidence

**Found and fixed October 27.** A process interruption after a staged threshold was persisted but before commit left the evidence only in `staged`. Startup recovery discarded it even when the staged and active budget policy were identical. Recovery now applies the same compatibility checks as rollback, persists the evidence into active state, and only then discards the abandoned configuration.

Regression tests verify that compatible exhaustion survives recovery and another registration failure, incompatible stricter drafts do not block the retained policy, and yesterday's staged exhaustion cannot affect the new day. `mergeCompatibleThresholds` also checks all token kinds and full cycle identity, so equal IDs with different date boundaries do not transfer evidence.

## Simulator incident: a legacy installation shielded the current build

**Confirmed environment issue — October 26, 2026 at 17:39 local time.** The reused iPhone 17 Pro simulator contained both `org.opensource.InstaBlock` (an older Daywell 1.0 build) and `dev.glebmelnikov.InstaBlock` (the current build). The old installation had 13 selected categories and persisted schedule shields. The current installation had no saved protection document or Screen Time authorization, and its diagnostic history showed no rule activation or threshold callback.

The system log identified `org.opensource.InstaBlock.ShieldConfiguration(1.0)` as the extension rendering “Daywell can wait” over the current app. The old monitor eventually removed the stale category shields at 17:39:51, after the screenshot. This explains both the immediate block and why the current app's diagnostics did not contain `shield.presented`: the rendering extension belonged to the separate old installation.

The obsolete simulator app bundle, app data, and App Group were backed up under `build/validation/legacy-simulator-daywell-backup/`, then only `org.opensource.InstaBlock` was uninstalled from that simulator. After reboot, `dev.glebmelnikov.InstaBlock` launched normally, the old bundle was absent, and the system's effective shield settings were empty. Evidence: `build/validation/daywell-self-shield-system.log`, `daywell-self-shield-cleanup.json`, and `daywell-self-shield-after-reboot.png`. No enforcement code or physical-device state was changed for this cleanup. The launch guidance now covers duplicate bundle prefixes.

## Verify the corrected scenarios

From the repository root:

```sh
xcrun swiftc Sources/BlockingCore/*.swift scripts/audit-protection.swift -o /tmp/daywell-protection-audit
/tmp/daywell-protection-audit
```

The harness uses temporary repositories and simulated clocks/drivers, removes its own state afterward, and never contacts Screen Time or changes installed app data. It now asserts the corrected behavior for five scenarios and complements the core regression suite. The pre-fix output is retained in `build/validation/daywell-protection-audit-2026-10-27.log`; fixed-behavior output is in `build/validation/daywell-protection-fixes-audit.log`.

## Using a shared problem report

Open **Share problem** at the bottom of the dashboard or setup screen. Describe what happened, select its approximate time, optionally enter the selected-usage value shown, and choose **Share report**. The iOS share sheet attaches a `Daywell-problem-….json` file. The user chooses the recipient; the app has no automatic upload.

The report includes versions, hardware model (not the device's name or identifier), authorization, time zone, uptime, sanitized active/staged/pending state, actual registered schedules/events, current shield settings, and a recent local event history. Events record registration, callback type and acceptance/rejection, commits/rollbacks, state changes, shield presentation/actions, authorization, lifecycle, and errors. Correlate `activity` names and generation/cycle IDs; compare callback uptime with `monitor.install_requested` or `monitor.system_request` to identify immediate delivery.

Logs use four rotating files of up to 128 KiB each and a nonblocking lock separate from protection storage. The report explicitly marks partial/corrupt history or collection errors. Logging failure cannot stop protection. Raw Screen Time tokens, selected app/website identities, arbitrary error userInfo/descriptions, device names, and browsing history are excluded. User-entered notes are included as written, within length limits.

Apple's [report sandbox](https://developer.apple.com/documentation/deviceactivity/deviceactivityreport) prevents exporting sensitive usage measurements. `selectedUsageShown` is explicitly user-supplied. Diagnostics start with an instrumented build; installing this change cannot recover the original incident's callback history. Sharing reads the failing state without reconciling, clearing shields, requesting authorization, or resetting limits.
