# Lekka — setup and release guide (Phases 4 to 6)

## 1. Database

Fresh project: run all of `supabase/schema.sql`. Existing project: run the
files in `supabase/migrations/` in order (phase1 … phase6). Each is safe to
run twice.

## 2. Server jobs

```bash
supabase link --project-ref YOUR-PROJECT-REF
supabase secrets set CRON_SECRET=PASTE-YOUR-LONG-RANDOM-SECRET
supabase functions deploy accrue-interest --no-verify-jwt
supabase functions deploy send-reminders --no-verify-jwt
```

Then put your project ref and the same secret into `supabase/cron.sql` and
run it. Interest is added at 00:30 India time, reminders go out at 09:00.
`--no-verify-jwt` is on purpose: each function checks the caller itself
(the cron secret, or the signed-in lender for a ping).

## 3. Push notifications (Firebase)

Without these steps the app still works; reminders just appear on the
Reminders screen without a phone notification.

1. Create a project at console.firebase.google.com. Add an Android app (your
   application id, e.g. `com.lekka.lekka`) and an iOS app (your bundle id).
2. Download `google-services.json` → `android/app/`, and
   `GoogleService-Info.plist` → add to the Runner target in Xcode.
3. Android: add the Google services Gradle plugin as Firebase's Android setup
   page shows (one line in `android/settings.gradle`, one in `android/app/build.gradle`).
4. iPhone: in Xcode enable **Push Notifications** and **Background Modes →
   Remote notifications**. In the Apple developer account create an APNs key
   (.p8) and upload it in Firebase → Project settings → Cloud Messaging.
5. Firebase → Project settings → Service accounts → Generate new private key.
   Put the JSON on one line and save it as a server secret:
   `supabase secrets set FIREBASE_SERVICE_ACCOUNT='{"type":"service_account",...}'`
   Never put this file in the app or in git.

## 4. Invite links (optional)

Invite codes work with no setup. To make the `lekka://join/CODE` link in the
invite message open the app:

- Android, inside the main `<activity>` in `android/app/src/main/AndroidManifest.xml`:
  ```xml
  <intent-filter>
    <action android:name="android.intent.action.VIEW"/>
    <category android:name="android.intent.category.DEFAULT"/>
    <category android:name="android.intent.category.BROWSABLE"/>
    <data android:scheme="lekka" android:host="join"/>
  </intent-filter>
  ```
- iPhone, in `ios/Runner/Info.plist`: add a URL type with the scheme `lekka`.

This link handling has not been tried on a device yet. Test it; the typed code is the fallback.

## 5. Backups

Supabase's free plan has **no automatic backups**; daily backups (kept 7 days)
start with the Pro plan. Before real loans go in, do one of these:

- Move the project to Pro and confirm backups are listed under Database → Backups, or
- Export the database yourself at least weekly and keep the file somewhere safe:
  ```bash
  supabase db dump -f lekka_schema.sql
  supabase db dump -f lekka_data.sql --data-only
  ```

Try restoring one export into a spare project once, so you know it works.

## 6. Test builds

**Android (Play Console internal testing)**
1. Create an upload keystore and `android/key.properties` (Flutter's "Build and release an Android app" guide). Keep both out of git.
2. Add `<uses-permission android:name="android.permission.INTERNET"/>` to the main AndroidManifest.
3. `flutter build appbundle --release --dart-define-from-file=env.json`
4. Play Console → your app → Testing → Internal testing → upload the `.aab`, add testers' Google accounts, share the opt-in link.

**iPhone (TestFlight)**: needs a Mac, Xcode and a paid Apple developer account.
1. Set the bundle id and signing team in Xcode.
2. `flutter build ipa --release --dart-define-from-file=env.json`
3. Upload with Xcode or Transporter, then add testers in App Store Connect → TestFlight.

For every new build raise `version:` in `pubspec.yaml` and `appVersion` in `lib/core/config.dart`.

## 7. Problem reports

Testers use Settings → Report a problem. Read them in the SQL editor:

```sql
select f.created_at, p.name, f.app_version, f.message
from feedback f join profiles p on p.id = f.user_id
order by f.created_at desc;
```

## 8. Translation review

Give `docs/translation_review.csv` to a native Telugu speaker and a native
Hindi speaker (it opens in Excel or Google Sheets). It lists every app label
and push message with where it appears. They mark each one OK or write better
wording; the corrections then go into `lib/l10n/app_te.arb`, `app_hi.arb` and
`supabase/functions/send-reminders/messages.ts`.
