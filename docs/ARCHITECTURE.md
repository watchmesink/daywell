# Architecture

## Rule evaluation

`BlockingCore` is a Foundation-only Swift package. The containing app and the monitor extension use the same `ProtectionCoordinator`, `BlockingPolicy`, and `ProtectionSnapshot`. The core accepts edits during active schedules. Stronger protection applies immediately; weaker protection is persisted with an effective date, so editing cannot release today's restrictions.

Windows use local calendar dates, start inclusively and end exclusively. An end time before the start continues into the next day. Their union determines whether a scheduled block is active and the next real change in availability. A fully covered day has no misleading early-unlock timestamp.

Fresh installs start with no scheduled windows and a 30-minute shared allowance. Saved windows are decoded as stored, so an update preserves existing schedules. Daily windows and the daily allowance are independently optional. Increasing or removing an active allowance stores a pending change with an effective date; draft rules without any selected activity apply immediately. An absent allowance stays absent during reconciliation. Usage reports remain visible whenever access is authorized and activity is selected, including during blocks and without an allowance. Adding apps, categories, or websites applies immediately, including during scheduled blocks, and preserves an exhausted allowance, including threshold callbacks received during monitor replacement. For a mixed selection edit, the union of old and new tokens of every kind is protected immediately and the desired selection is queued. Removals and schedule edits that free any blocked minutes take effect at the next reset, extended to finish occurrences spanning that reset. The deadline is fixed when saving so continuous daily coverage cannot postpone changes indefinitely. Schedule strengthening compares the union of blocked minutes, including overlapping and overnight windows. Cancelling pending edits retains the existing rules. There is no early-unlock API, URL handler, debugging control, or shield override.

## iOS enforcement

The Family Controls picker returns opaque `ApplicationToken`, `ActivityCategoryToken`, and `WebDomainToken` values. `BlockingSelection` keeps their encoded data in separate normalized arrays. The picker supports entire categories, individual apps, and websites; any one kind can activate protection. The adapter uses `DeviceActivityCenter` to install:

- A recurring midnight monitor to advance pending edits and maintain future budget monitoring.
- One recurring monitor per daily blocking window.
- Dated, non-repeating usage monitors for the current and following budget day, each with one shared threshold across selected apps, categories, and websites.

The dated usage names contain a configuration generation and cycle UUID. Expired callbacks cannot consume a new day's allowance. Repeated callbacks are idempotent. `includesPastActivity: true` asks iOS to include earlier usage in the same calendar interval after activation or registration changes. Foreground wall-clock timers are not used to measure app use.

The next day's budget monitor is registered in advance. Its callbacks also advance state if the midnight callback arrives late. The recurring midnight monitor can recover the rolling pair after longer interruptions. All callback paths recompute the full decision instead of blindly unblocking on `intervalDidEnd`.

Two named `ManagedSettingsStore` instances independently apply the schedule and exhausted allowance. Each layer sets or clears explicit applications and web domains plus both application-category and web-domain-category policies. Entire categories cover both kinds of activity. Every token kind must decode successfully before replacing existing shields. At transitions, restrictive assignments are made before clearing inactive layers. The shield action extension always returns `.close`; its button uses the system's default label and colors.

The selected-activity report filters all three token kinds and sums today's application/site durations, counting each token once per segment without adding category totals. The separate total report uses unfiltered segment screen-on duration and compares today with the mean of the previous seven complete local-calendar days. Both report contexts default to the current device. Missing daily segments leave the total comparison unavailable; a zero baseline never produces an infinite percentage. Decreases are green and increases red. Usage remains inside the report extension and is not exported to the parent app or a server.

The dashboard shows selection counts and a Change action without a token-icon carousel. Read-only report hosts disable hit testing so dashboard swipes pass through them. The 15-second timeline updates only the status copy, and unchanged storage polls do not publish model updates. Report day boundaries refresh when the app becomes active or the system reports a significant time change.

## Persistence and update transactions

App Group storage uses a versioned Codable document, atomic file replacement, and a separate file lock for concurrent readers/writers. Files remain accessible after the first unlock following reboot. Unreadable or unknown-version state causes an error and leaves installed shields untouched.

Schema version 3 stores separate application, category, and web-domain arrays for active, staged, and pending selections. `pendingSelection` replaces the app-only pending field. Version 1 documents with a single app token and version 2 app arrays, including their queued changes, are read and upgraded on the next write. Versions 1 and 2 retain their existing apps, exhausted cycles, and deadlines. Optional `pendingWindows` stores a queued schedule and its effective date; documents without this field still decode. The App Group file path is unchanged so an installed build keeps its saved protection.

The app's display name, project, and scheme are Daywell. Bundle IDs, the App Group ID, monitor names, and named settings stores retain their original `InstaBlock` / `instablock` identifiers so an installed build can update in place and keep its saved protection. These identifiers are implementation details, not user-facing branding.

A second, nonblocking operation lock serializes monitor changes. API registration happens outside the state-file lock so a synchronously delivered callback can persist its result without deadlocking. Callbacks do not wait for the operation lock.

A new configuration is staged on disk, all of its monitors register, then it becomes active. Thresholds received while staged are retained; compatible threshold events from the previous generation are merged. Failure removes only the replacement monitors and retains the previous policy and shields. An interrupted staged update is discarded on recovery. Old monitors are retired after successful commit.

Seven windows leave room for two complete configurations during replacement: each has at most seven window monitors, two budget monitors, and one midnight monitor. Platform registration failures are still handled explicitly.

The 15-second dashboard refresh only reads state and leaves edit controls enabled. Full reconciliation runs on foregrounding and significant time changes. A save awaits any in-flight app refresh; a revision check prevents stale refresh results from replacing the saved UI state.

## Time changes and platform limits

- Daily intervals use calendar midnights, including 23-hour and 25-hour daylight-saving days.
- Scheduled windows adopt the device's current time zone when state is reconciled. Launch, foregrounding, significant-time notifications, and extension callbacks trigger reconciliation.
- An existing budget keeps its original reset instant across a time-zone change. Once that boundary passes, a new local-calendar day is monitored with its earlier usage included. This can temporarily differ from local midnight; the stored reset instant is authoritative.
- Moving the clock backward does not erase an already-exhausted cycle. This is not protection against all system-time manipulation. Manual time changes, permission revocation, uninstalling, changing/rebuilding the source, and invalid signing are outside the in-app lock boundary.
- iOS can delay or miss callbacks. Device-level behavior must be measured on the intended OS version, especially after reboot and force-quit. If monitoring cannot be restored, the app reports the error and retains whatever restrictions are already installed; it cannot guarantee new blocks will start without OS callbacks.
- Rules are stored locally, without cloud synchronization. Apple's own Screen Time “Share Across Devices” setting may affect reported/counted activity.
- Website choices and enforcement use Apple's Screen Time domain tokens and depend on the supported browser and OS. Category membership is resolved by iOS. Validate explicit domains and websites inside categories on the intended device.
- Explicit shields are limited to 50 application tokens and 50 domain tokens. Selection validation also caps categories at 50. During a replacement, retained targets awaiting removal count toward these limits; an oversized union is rejected before changing protection.

## Research basis

This is an independent functional implementation of the requested core behavior. No AppBlock binary, proprietary source, branding, or subscription system is included. REA was evaluated during planning and was unnecessary for the public-API implementation.

- [AppBlock's iOS feature descriptions](https://appblock.app/ios/)
- [Apple's Screen Time overview](https://developer.apple.com/videos/play/wwdc2022/110336/)
- [Past activity accounting](https://developer.apple.com/documentation/deviceactivity/deviceactivityevent/includespastactivity)
- [Minimum monitoring interval](https://developer.apple.com/documentation/deviceactivity/deviceactivitycenter/monitoringerror/intervaltooshort)
