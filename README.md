# BeniAI Activity Alarm

An alarm clock that only stops once you've actually done the activity you set
for it - squats, push-ups, jumping jacks, or a neck stretch - verified live
through your camera.

Built with Flutter. Firebase for auth/database, Superwall for the paywall,
and Mixpanel for analytics. Activity verification is entirely on-device -
no cloud AI vision calls, no per-check cost or latency.

## How it works

1. **Set an alarm** - time, repeat days, alarm sound, and an activity target
   (e.g. "20 squats"). Pick the activity manually, or open the camera and
   demonstrate it - on-device pose detection identifies which built-in
   activity it matches and pre-fills the alarm. You can also save a
   demonstrated activity by name to reuse on future alarms.
2. **Alarm rings** - a full-screen ringing view that can't be swiped away.
3. **Camera verification** - tapping "I'm up" opens the camera: reps are
   counted live, continuously, and entirely on-device with Google's
   MediaPipe-based pose detector (via ML Kit) - fast, free, works offline.
4. Once the target is hit, the alarm stops.

## Project structure

```
lib/
  core/
    config/       env vars, built-in alarm sounds
    providers/    Riverpod wiring for all services
    router/       go_router routes
    services/     Firebase, Mixpanel, Superwall, alarm scheduling,
                   pose detection + rep counting
    theme/
  features/
    auth/         login / sign up, auth state
    alarms/        alarm list, create/edit
    activity/      activity picker, camera-based activity setup
    alarm_ring/    full-screen ring UI + camera verification
    paywall/       Superwall subscription gating
    settings/
  models/          AlarmModel, ActivityPreset, AppUserModel
```

## Prerequisites

- Flutter 3.44+ (`flutter --version`)
- Accounts with: [Firebase](https://console.firebase.google.com),
  [Superwall](https://superwall.com), [Mixpanel](https://mixpanel.com)
- For iOS: Xcode + CocoaPods, on macOS
- For Android: Android Studio / SDK

## 1. Firebase setup

This repo ships a **placeholder** `lib/firebase_options.dart` with fake keys
so the project builds out of the box. Replace it with your real project:

```bash
dart pub global activate flutterfire_cli
flutterfire configure
```

This walks you through selecting/creating a Firebase project and platforms,
and regenerates `lib/firebase_options.dart` with real values.

Then, in the Firebase console:

- **Authentication** -> Sign-in method -> enable **Email/Password**.
- **Firestore Database** -> create a database, then apply the security rules
  in [`firestore.rules`](firestore.rules) (Firestore -> Rules -> paste and
  publish). Data model:
  ```
  users/{uid}                  -> { email, displayName, isPremium, createdAt }
  users/{uid}/alarms/{alarmId} -> AlarmModel fields
  ```

## 2. Superwall setup

1. Create an app in the Superwall dashboard, add your iOS/Android API keys.
2. Create a paywall and a campaign with a placement/trigger (default name
   used here: `campaign_trigger`).
3. Put your keys in `.env` (see below). The app calls
   `Superwall.shared.registerPlacement(...)` when a free user hits the alarm
   limit or opens "Manage subscription" in Settings - Superwall decides
   whether to show a paywall based on your dashboard campaign config.

## 3. Mixpanel setup

Create a project at <https://mixpanel.com>, copy its **Project Token** (not
the secret key). Events tracked: `sign_up`, `sign_in`, `sign_out`,
`alarm_created/updated/deleted/toggled`, `alarm_rang`,
`activity_verification_started/completed`, `activity_rep_counted`,
`alarm_dismissed`, `paywall_viewed`. See
`lib/core/services/analytics_service.dart` (`AnalyticsEvents`) for the full
list.

## 4. Configure secrets

```bash
cp .env.example .env
```

Fill in `.env` with your real keys:

```
MIXPANEL_TOKEN=...
SUPERWALL_API_KEY_IOS=pk_...
SUPERWALL_API_KEY_ANDROID=pk_...
SUPERWALL_PAYWALL_PLACEMENT=campaign_trigger
```

`.env` is bundled as a Flutter asset so the app has something to load even
before you've configured it (all integrations simply no-op until their key
is present - see `EnvConfig`). **Once you add real secrets, add `.env` to
`.gitignore`** so you don't commit them.

## 5. Run it

```bash
flutter pub get
flutter run
```

Grant camera + notification permissions when prompted. Note that the
iOS Simulator and most desktop/web targets don't have a usable camera, so
test the camera-verification flow on a real device.

## Alarm sounds

Four placeholder tones are generated into `assets/sounds/*.wav` so the app
runs out of the box. Swap them for real audio files (keep the same file
names, or update `lib/core/config/alarm_sounds.dart`) before shipping.

## Known limitations / production TODOs

- **iOS background reliability**: iOS kills backgrounded apps aggressively;
  the `alarm` package works around this with a silent background audio
  session, but truly reliable wake-ups on iOS depend on the OS more than on
  Android. Test thoroughly on real devices before shipping.
- **Rep counting** uses simple joint-angle/position thresholds on top of
  MediaPipe pose landmarks (see `lib/core/services/rep_counter.dart`), not a
  trained action-recognition model. It works well for clear, properly-framed
  reps but, being purely geometric, has no real understanding of *which*
  activity is happening - only built-in activities with hand-coded rules are
  supported (squats, push-ups, jumping jacks, neck stretch). Adding another
  trackable activity means writing a new rule in `RepCounter`.
- **Firestore rules**: the provided `firestore.rules` are a reasonable
  starting point (users can only read/write their own data) but review them
  against your own threat model before going to production.
- **Superwall entitlements**: `isSubscribed` reflects Superwall's
  subscription status; wire up a `PurchaseController` in
  `PaywallService.init()` if you need custom purchase logic (e.g. your own
  backend receipt validation) instead of Superwall's default StoreKit/Play
  Billing handling.
