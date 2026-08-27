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
    models/          HealthMeasurement and related enums
    repositories/     HealthRepository abstraction + FakeHealthRepository
  presentation/
    providers/       Riverpod providers wiring repositories to the UI
    screens/          Splash, Onboarding, Login, Register, Dashboard shell
                       (Health Metrics, Insights, History, Profile)
    widgets/          Shared UI (empty states, metric cards, demo banner)
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
- [ ] Milestone 4+ — Galaxy Watch heart-rate connection, Flutter↔Kotlin
      bridge, Samsung Health historical data, Firebase, analytics engine
      (quality/confidence, baselines, trends, anomalies), insights, AI
      explanations, alerts, and reporting

All currently displayed health data is clearly labeled as simulated/demo data
and is never presented as a real measurement.

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

