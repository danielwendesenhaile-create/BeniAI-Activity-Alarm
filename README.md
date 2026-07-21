# BeniAI Activity Alarm

An alarm clock that only stops once you've actually done the activity you set
for it - squats, push-ups, jumping jacks, or anything else - verified live
through your camera.

Built with Flutter. Firebase for auth/database, Superwall for the paywall,
OpenAI for camera-based activity verification, and Mixpanel for analytics.

## How it works

1. **Set an alarm** - time, repeat days, alarm sound, and an activity target
   (e.g. "20 squats"). You can pick the activity manually, or open the camera
   and demonstrate it - OpenAI vision identifies it and pre-fills the alarm.
2. **Alarm rings** - a full-screen ringing view that can't be swiped away.
3. **Camera verification** - tapping "I'm up" opens the camera:
   - Squats / push-ups / jumping jacks are counted live, on-device, with
     Google ML Kit pose detection (fast, free, works offline).
   - A periodic OpenAI vision spot-check runs alongside it as a sanity check.
   - Custom activities (anything pose detection can't count) are verified
     entirely by OpenAI vision from a captured photo.
4. Once the target is hit, the alarm stops.

## Project structure

```
lib/
  core/
    config/       env vars, built-in alarm sounds
    providers/    Riverpod wiring for all services
    router/       go_router routes
    services/     Firebase, OpenAI, Mixpanel, Superwall, alarm scheduling,
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
  [Superwall](https://superwall.com), [OpenAI](https://platform.openai.com),
  [Mixpanel](https://mixpanel.com)
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

## 3. OpenAI setup

Create an API key at <https://platform.openai.com/api-keys>. The app uses a
vision-capable chat model (default `gpt-4o-mini`) for:
- Identifying an activity demonstrated on camera during alarm setup.
- Verifying custom (non-pose-countable) activities.
- Periodic spot-checks alongside on-device pose detection.

## 4. Mixpanel setup

Create a project at <https://mixpanel.com>, copy its **Project Token** (not
the secret key). Events tracked: `sign_up`, `sign_in`, `sign_out`,
`alarm_created/updated/deleted/toggled`, `alarm_rang`,
`activity_verification_started/completed`, `activity_rep_counted`,
`alarm_dismissed`, `paywall_viewed`. See
`lib/core/services/analytics_service.dart` (`AnalyticsEvents`) for the full
list.

## 5. Configure secrets

```bash
cp .env.example .env
```

Fill in `.env` with your real keys:

```
OPENAI_API_KEY=sk-...
OPENAI_VISION_MODEL=gpt-4o-mini
MIXPANEL_TOKEN=...
SUPERWALL_API_KEY_IOS=pk_...
SUPERWALL_API_KEY_ANDROID=pk_...
SUPERWALL_PAYWALL_PLACEMENT=campaign_trigger
```

`.env` is bundled as a Flutter asset so the app has something to load even
before you've configured it (all integrations simply no-op until their key
is present - see `EnvConfig`). **Once you add real secrets, add `.env` to
`.gitignore`** so you don't commit them.

## 6. Run it

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
- **Rep counting** uses simple joint-angle thresholds (see
  `lib/core/services/rep_counter.dart`), not a trained ML rep-counting
  model. It works well for clear, full-body-in-frame reps but can be fooled
  by partial reps or bad framing - that's what the OpenAI spot-check is for.
- **Firestore rules**: the provided `firestore.rules` are a reasonable
  starting point (users can only read/write their own data) but review them
  against your own threat model before going to production.
- **Superwall entitlements**: `isSubscribed` reflects Superwall's
  subscription status; wire up a `PurchaseController` in
  `PaywallService.init()` if you need custom purchase logic (e.g. your own
  backend receipt validation) instead of Superwall's default StoreKit/Play
  Billing handling.
