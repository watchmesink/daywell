# App Review notes draft

Daywell is a free, self-directed Screen Time app. It has no login or server. It requires individual Family Controls authorization on a physical iPhone. On first launch, tap **Enable Screen Time access**, approve Apple's permission sheet, then tap **Choose apps & start**. In Apple's picker, expand a category and select one or more individual installed apps; categories and websites are not supported. Save with **Activate protection**.

For a short test, edit a daily block to begin soon and last at least 15 minutes, or reduce the shared allowance to 1–2 minutes. Use a selected app and return after the threshold. The selected apps should receive the system shield; its action is **Close**. The app uses Device Activity callbacks, so iOS may not apply a change instantly. App use from earlier today may already count toward the shared allowance.

The device owner can bypass enforcement by revoking Screen Time permission or uninstalling Daywell. The app has no account, subscription, or in-app purchases. The app uses Apple's Family Controls, Device Activity, and Managed Settings frameworks; it stores selected app tokens and rule state only in its local App Group container.

Before submission, update these notes with any measured callback delay from physical-device validation and verify the wording against the actual release build.
