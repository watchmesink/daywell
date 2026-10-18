# App Review notes

Daywell is a self-directed Screen Time app with no login or server. It requires individual Family Controls authorization on a physical iPhone.

On first launch, tap **Continue** to open Apple's Screen Time authorization sheet. After authorization, tap **Choose what to block**, select apps, categories, or websites in Apple's private Screen Time picker, then tap **Activate protection**.

For a short test, add a daily block beginning soon and lasting at least 15 minutes, or set the shared allowance to 1–2 minutes. Use a selected app and return after the threshold. Selected activity should receive the system shield; its native button closes the app. iOS controls Device Activity callbacks, so blocking and usage updates may be delayed. Activity from earlier today may already count toward the allowance.

The device owner can revoke Screen Time permission in Settings or uninstall Daywell. The app has no account or in-app purchases. It uses Apple's Family Controls, Device Activity, and Managed Settings frameworks and stores selections and rules only in its local App Group container.

## October 18 update — version 1.1.1 (8)

- Corrected the selected-activity duration. A separate, smaller total-screen-time report compares today with the previous seven complete days; missing history displays an unavailable comparison.
- Simplified the dashboard's blocked-activity card and improved scrolling across read-only reports and periodic status updates.
- The shield uses native button colors, and the Home Screen icon consistently uses the dark artwork.
- Family Controls and the shared App Group remain enabled on the app and all four extensions. Usage stays within Apple's report extension and is not sent to the developer or a server.
- The previously approved neutral **Continue** permission buttons and screenshot wording without pricing references are retained.
