# RADIUS BZ1 — Push notifications

This feature is isolated on `feature/push-notifications`; it is not enabled in production until the branch is reviewed, merged, and configured.

## What it adds
- An authenticated user's opt-in control for browser push notifications.
- Root-scoped service worker to show alerts when the web app is not open.
- A subscription table protected by row-level security (users can manage only their own device subscriptions).
- An Edge Function that sends one alert per device/cone/due-date for: tomorrow, today, and already-expired cones. It removes subscriptions rejected by push providers.

## Required configuration before enabling
1. Generate a VAPID key pair using a trusted Web Push key generator or `web-push generate-vapid-keys`. Never commit the private key.
2. Add `VITE_VAPID_PUBLIC_KEY` to Vercel Production and Preview environments (public key only), then redeploy.
3. Deploy the `send-cone-expiry-notifications` Supabase Edge Function with secrets:
   - `CRON_SECRET`: a long random secret used only by the scheduler.
   - `VAPID_PUBLIC_KEY`: public VAPID key.
   - `VAPID_PRIVATE_KEY`: private VAPID key (secret).
   - `VAPID_SUBJECT`: a contact URI such as `mailto:your-real-admin-email`.
   Supabase normally supplies `SUPABASE_URL` and `SUPABASE_SERVICE_ROLE_KEY` to Edge Functions; verify these exist in the project's function secrets. Never put the service-role key in the browser or repository.
4. Apply `supabase/migrations/20261028160000_push_notifications.sql` to the target database.
5. Create a daily Supabase Cron job for 08:00 America/Sao_Paulo (11:00 UTC) that POSTs to `https://ucotjvvrobmpyjullmyk.supabase.co/functions/v1/send-cone-expiry-notifications` with header `x-cron-secret: <CRON_SECRET>` and `Content-Type: application/json`. Store the secret in Supabase Vault/cron configuration; do not put it in SQL source or Git.
6. On iPhone, open the installed RADIUS BZ1 home-screen app, sign in, press **Ativar notificações**, and allow notifications. iOS web push requires iOS/iPadOS 16.4+ and a home-screen web app. Ensure notifications are allowed in iOS Settings.

## Validation checklist
- Build the Vite app and review TypeScript errors before merging.
- Confirm the SQL migration applies and RLS denies one user access to another user's subscriptions.
- Test the Edge Function with a valid cron secret and a test cone due tomorrow; verify duplicate runs do not duplicate notifications.
- Test an actual push on the iPhone; browser support and OS notification settings affect delivery.

## Notes
The notification scheduler and secrets are intentionally not applied automatically by this PR. This avoids changing production database/security settings or activating an unconfigured background job without review.
