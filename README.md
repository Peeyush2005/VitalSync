# VitalSync

VitalSync is a production-quality Flutter health & wellness app targeting the
Samsung Galaxy Watch4. It collects health data, tracks personal history,
calculates individual baselines, detects trends/deviations, evaluates
measurement quality, and surfaces understandable wellness insights.

**VitalSync is not a medical diagnostic or treatment system.**

## Architecture

```
Galaxy Watch4 → Wear OS/Kotlin → Android Phone → Native Android Bridge
→ Flutter → Repository → Processing/Analytics → Firebase → FastAPI → Insights/AI
```

Data collection, data processing, and data presentation are kept in separate
layers. The Flutter UI never contains Samsung SDK logic — it depends only on
repository abstractions (`HealthRepository`, `FakeHealthRepository`, and
later `SamsungHealthRepository`), so the data source can be swapped without
touching UI code.

```
lib/
  core/
    theme/          Material 3 theming
    routing/         go_router configuration
  data/
    models/          HealthMeasurement, WatchConnectionState, and related enums
    repositories/     HealthRepository abstraction + FakeHealthRepository +
                       SamsungHealthRepository (stub, see Milestone 4 status)
    watch_bridge/     Flutter <-> Android platform channel bridge
  presentation/
    providers/       Riverpod providers wiring repositories/bridge to the UI
    screens/          Splash, Onboarding, Login, Register, Dashboard shell
                       (Health Metrics, Insights, History, Profile)
    widgets/          Shared UI (empty states, metric cards, demo banner,
                       watch status card)
```

## Tech stack

- Flutter / Dart, Material 3
- Riverpod (state management / DI) + go_router (navigation)
- Kotlin + Android SDK + Wear OS (planned)
- Samsung Health Sensor/Data SDK (planned)
- Firebase Auth + Firestore + FCM (planned)
- Python + FastAPI, NumPy/Pandas (planned, for analytics/insights backend)

## Current status

Development follows a strict milestone order (INSPECT → PLAN → IMPLEMENT →
RUN → TEST → VERIFY → REVIEW → COMMIT → NEXT), starting with fake data before
any hardware integration.

- [x] **Milestone 0** — Environment verified (Flutter, Android SDK, Gradle, JDK)
- [x] **Milestone 1** — Flutter foundation (theme, router, DI shell)
- [x] **Milestone 2** — UI screens (Splash, Onboarding, Login, Register,
      Dashboard shell with Health Metrics/Insights/History/Profile tabs)
- [x] **Milestone 3** — Fake health data (`HealthMeasurement` model,
      `HealthRepository`/`FakeHealthRepository`, wired into the Dashboard and
      Health Metrics screens with clear "simulated data" labeling)
- [~] **Milestone 4** — Galaxy Watch4 heart-rate connection: **blocked, see
      below**. Flutter↔Android bridge and connection-state UI are
      implemented and tested; real Samsung Health Sensor SDK integration is
      not yet possible (SDK download requires a Samsung Developer account
      sign-in, and no Galaxy Watch4 is connected for hardware testing).
- [ ] Milestone 5+ — Samsung Health historical data, Firebase, analytics
      engine (quality/confidence, baselines, trends, anomalies), insights,
      AI explanations, alerts, and reporting

All currently displayed health data is clearly labeled as simulated/demo data
and is never presented as a real measurement.

## Galaxy Watch4 integration status (Milestone 4)

**Not yet functional end-to-end.** Here is exactly what was verified,
implemented, and blocked.

### Verified from official Samsung/Android documentation

- **Samsung Health Sensor SDK v1.4.1** is the official SDK for Galaxy Watch
  health sensors ([developer.samsung.com/health/sensor](https://developer.samsung.com/health/sensor/overview.html)).
  It only works on **Galaxy Watch4 series and later, running Wear OS powered
  by Samsung**, and explicitly **does not support an emulator**.
- Samsung's own code lab, ["Transfer heart rate data from Galaxy Watch to a
  mobile device"](https://developer.samsung.com/codelab/health/heart-rate-data-transfer.html),
  confirms the watch-to-phone communication mechanism is Android's official
  **Wearable Data Layer API**
  ([developer.android.com/training/wearables/data](https://developer.android.com/training/wearables/data/overview)) —
  not a Samsung-specific protocol.
- Galaxy Watch developer setup (verified from the official guide, [Connect
  Galaxy Watch with Android Studio](https://developer.samsung.com/health/sensor/guide/connect-watch.html)):
  connect the watch to the same Wi-Fi as your PC, enable **Developer
  options** (Settings > About watch > Software > tap Software version 5
  times), enable **ADB debugging** and **Wireless debugging**, then pair
  from Android Studio's terminal with `adb pair <ip>:<port> <code>` followed
  by `adb connect <ip>:<port>`.

### Blocker: Samsung SDK access

The SDK is **not** distributed on Maven Central and cannot be added as a
regular Gradle dependency. Attempting to download it
(`https://developer.samsung.com/SHealth/file/...`) redirects to a **Samsung
Account sign-in page** (`account.samsung.com`). This cannot and should not be
done autonomously. Without the SDK artifact, the exact Kotlin API surface
(tracker class/method names, e.g. what is commonly called
`HealthTrackingService`/`HealthTracker` in community write-ups) could not be
verified against the current official reference docs, and this project's
rules forbid guessing SDK class/method names. **A Samsung Developer account
sign-in and manual SDK download by a human is required before this can be
completed.**

### Blocker: no hardware

No physical Galaxy Watch4 or Android phone is connected to the development
machine (confirmed via `adb devices`), and the SDK explicitly does not
support emulators — so real hardware is required to test this milestone
regardless of SDK access.

### What was implemented (verified, real, non-Samsung-specific)

- `WatchConnectionState` enum (`disconnected`, `connecting`, `connected`,
  `measuring`, `error`) — [lib/data/models/watch_connection_state.dart](lib/data/models/watch_connection_state.dart).
- `WatchHealthBridge` — a Flutter↔Android bridge using Flutter's officially
  documented [platform channels](https://docs.flutter.dev/platform-integration/platform-channels)
  (`MethodChannel` + `EventChannel`), not any Samsung API —
  [lib/data/watch_bridge/watch_health_bridge.dart](lib/data/watch_bridge/watch_health_bridge.dart).
- Native Android side of the bridge in
  [MainActivity.kt](android/app/src/main/kotlin/com/example/vitalsync/MainActivity.kt),
  which honestly reports `disconnected` (no Wear OS app/SDK integration
  exists yet) and fails `connect` with a clear, caught error instead of
  crashing.
- `SamsungHealthRepository` — a `HealthRepository` stub that always returns
  no data (never fabricated), ready to be completed once the SDK is
  available — [lib/data/repositories/samsung_health_repository.dart](lib/data/repositories/samsung_health_repository.dart).
- Dashboard now shows a **Galaxy Watch status card** (`● Connected` /
  `○ Not connected`) and only shows the demo-data banner while disconnected,
  per the required UI states.
- `FakeHealthRepository` and the rest of the app are untouched and continue
  to work exactly as before — this is the app's default, working mode.

### What remains incomplete

- No Wear OS Gradle module or Kotlin watch app was created, and no Samsung
  Health Sensor SDK code was written, because doing so would require
  guessing an unverified API surface, which this project's rules forbid.
- Real heart-rate data has **not** been observed end-to-end on hardware.
  Nothing above should be read as "working with a real watch" — only the
  non-Samsung-specific scaffolding (bridge, state model, UI) has been built
  and tested.

### Next steps (need a human)

1. Sign in with a Samsung Developer account and download Samsung Health
   Sensor SDK v1.4.1 from https://developer.samsung.com/health/sensor/overview.html.
2. Provide the SDK (or its class/method reference docs) so the Wear OS
   watch app and the native Android receiver can be implemented against
   verified, real APIs.
3. Connect a Galaxy Watch4 (paired, Developer Mode + Wireless debugging
   enabled per the steps above) and an Android phone to test end-to-end.

## Getting started

```bash
flutter pub get
flutter analyze
flutter test
flutter run          # or: flutter build apk --release
```

## Testing

Run `flutter analyze` and `flutter test` before every commit. Tests cover the
`HealthMeasurement` model, `FakeHealthRepository`, and key screens
(onboarding flow, login validation, dashboard rendering).

