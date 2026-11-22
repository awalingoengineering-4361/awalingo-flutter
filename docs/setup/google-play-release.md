# Awalingo Google Play release

The permanent Android application ID is `org.awalingo.app`. Its Firebase SDK configuration uses the Awalingo Firebase project. Back up the upload keystore and its password together in the team’s private credential store. Keep `android/key.properties` and `.secrets/` out of Git. Once Play App Signing is enabled, use the Play app signing certificate for services that depend on the installed app’s certificate. The upload certificate identifies the bundle uploaded to Play.

## Play Console

- Complete identity verification, trader status, organization website verification, and phone verification. Google may take a few days to review identity documents.
- Create the Awalingo app record and complete its store listing, content rating, Data safety, app access, privacy policy, and account deletion details. Confirm that the public `https://www.awalingo.org/delete-account` route and both in-app deletion flows work.
- Build with `flutter build appbundle --release --dart-define-from-file=config/production.json` and upload the signed AAB to Internal testing. Use a higher build number if Play already has that version code.
- Create active consumable one-time products with IDs `cowries_copper_50`, `cowries_silver_100`, `cowries_gold_500`, and `cowries_diamond_1000`. Use the approved regional prices and keep multi-quantity disabled.
- Enable the Google Play Developer API and grant the server service account access to this app and its purchase data. Add tester Google accounts to license testing and invite them to the internal track. Use separate disposable Awalingo accounts for license tests.

## Supabase deployment

1. Verify that the target database has the account deletion migration and its payment/profile/ledger guards. Apply the reviewed `supabase_cowry_payment_credit.sql` and `supabase_store_refunds.sql` to that environment. Both RPCs must be callable only by the service role.
2. Configure the Edge Function secrets from the secure local configuration. Set `GOOGLE_PLAY_PACKAGE_NAME=org.awalingo.app`, the server-only `GOOGLE_PLAY_SERVICE_ACCOUNT_JSON`, `COWRY_STORE_CHECKOUT_MODE=testing`, and `COWRY_STORE_TEST_USER_IDS` to disposable Awalingo user UUIDs. Keep `APP_STORE_CHECKOUT_MODE=off` until Apple billing and refund operations have been validated separately.
3. Deploy `cowry-store-purchase` and `cowry-store-reconcile`. Each validates its own authorization. Use `--no-verify-jwt` where required by the gateway for the project’s Auth token configuration and for the server-only reconciliation endpoint. Verify unauthenticated requests are denied.
4. Configure the same random `COWRY_STORE_RECONCILE_SECRET` in Supabase and the GitHub repository secret. Run the reconciliation workflow after setting repository variable `COWRY_STORE_REFUNDS_ENABLED=true`. Verify it processes the Google voided purchase window. Monitor workflow failures so they are retried while receipts remain in Google’s available window.
5. Keep new checkout in testing mode until the installed-build tests below pass. Set `COWRY_STORE_CHECKOUT_MODE=live` for the approved release. Remove disposable IDs after the test orders are reconciled.

## Installed build verification

Install from the Play test track. Test sign-in, push registration and tap routing, one purchase followed by a second purchase of the same pack, cancellation, pending approval, and restart after purchase before fulfillment. Verify each successful order credits the intended account exactly once and allows the pack to be bought again. Repeat with an account switch, and verify that an account queued for deletion cannot open checkout. Void a disposable test order in Play, run reconciliation twice, and verify exactly one reversal in the ledger. A refund can make the wallet negative when the buyer has already spent the Cowries. Verify this behavior before enabling live sales. Check the Android build’s target API against the Play Console requirement before submitting.
