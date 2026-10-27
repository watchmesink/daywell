# App Review notes

Daywell is a self-directed Screen Time app with no login or server. It requires individual Family Controls authorization on a physical iPhone.

On first launch, tap **Continue** to open Apple's Screen Time authorization sheet. After authorization, tap **Choose what to block**, select apps, categories, or websites in Apple's private Screen Time picker, then tap **Activate protection**.

For a short test, add a daily block beginning soon and lasting at least 15 minutes, or set the shared allowance to 1–2 minutes. Use a selected app and return after the threshold. Selected activity should receive the system shield; its native button closes the app. iOS controls Device Activity callbacks, so blocking and usage updates may be delayed. Activity from earlier today may already count toward the allowance.

The device owner can revoke Screen Time permission in Settings or uninstall Daywell. The app has no account or in-app purchases. It uses Apple's Family Controls, Device Activity, and Managed Settings frameworks and stores selections and rules only in its local App Group container.

## October 27 update — version 1.1.2 (9)

- Improved recovery after interrupted or failed Screen Time monitor updates. Compatible usage-limit callbacks survive recovery without weakening saved rules or incorrectly exhausting an earlier policy.
- The dashboard reconciles schedule and daily-reset protection while it remains open, and reset messages show the actual local reset time after travel.
- Added **Share problem** at the bottom of setup and the dashboard. It opens a form and then Apple's native share sheet with a diagnostic JSON attachment. The user chooses a recipient or cancels; there is no automatic upload, analytics service, or app server.
- Automatic diagnostics include recent blocking events, rule settings, app/iOS versions, and selection counts. They exclude selected app/website identities, selection tokens, browsing history, and exact Screen Time usage measurements. Anything the user types into the form is included. The public privacy policy describes this optional sharing.
- Family Controls and the shared App Group remain enabled on the app and all four extensions. Exact usage measurements stay within Apple's report extension.
- The previously approved neutral **Continue** permission buttons and screenshot wording without pricing references are retained.
