# Account deletion confirmation without a sign-in age limit

User decision: typing DELETE while signed in confirms intent. The shared backend removes its ten-minute session age restriction but still verifies the user and active session. Mobile copy drops the ten-minute instruction. Only a 401 offers sign-in recovery; unrelated 403 errors keep retry available.

This branch starts at main and is independent of remote-session sign-out PR #39. It requires the matching backend change in the awalingo web repository. No migration or production deployment is included.

- [x] Reproduce misleading forbidden-response sign-in recovery.
- [x] Remove time-limit copy and retain authentication/DELETE requirements.
- [x] Run full mobile verification and account-deletion Android fixture; inspect screenshots.

Verification: scripts/verify-change passed with 168 tests, one existing conditional skip, 34 pre-existing analysis infos, and Android build/install/launch. The Android account-deletion fixture passed all three journeys (four checks including teardown); confirmation screenshot inspected with the age instruction removed. Nine focused service/widget tests passed. Independent review found no concrete regression. The existing small-screen retry fixture now scrolls to its button before retrying.

Backend deployment is required to remove the enforced rule for both apps; the mobile copy change requires a new build. No deployment, database migration, or production account action was performed.
