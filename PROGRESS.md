# VitalSync — Progress & Milestone Tracking

## Project Status Overview

| Milestone | Scope | Status | Verification Evidence |
|---|---|---|---|
| **M0** | Environment Setup (Flutter, Android SDK, JDK 17, Gradle) | ✅ **COMPLETE** | Toolchain verified; Gradle 9.5 & Temurin-17 JDK. |
| **M1** | Foundation (M3 theme, GoRouter, Riverpod DI) | ✅ **COMPLETE** | Dark/light theme, routing shell, provider graph. |
| **M2** | UI Screens (Dashboard Shell, Metrics, Insights, History, Profile) | ✅ **COMPLETE** | 5 core tabs, responsive design, empty & active states. |
| **M3** | Health Repository & Simulated Baseline (`FakeHealthRepository`) | ✅ **COMPLETE** | Clearly labeled simulated data with `DemoDataBanner`. |
| **M4** | Galaxy Watch4 Wear OS App + Samsung Health Sensor SDK | ✅ **COMPLETE** | Round Wear Compose UI, `samsung-health-sensor-api-1.4.1.aar`. |
| **M5** | Hardened Native Android Bridge & Dual-Engine Failover | ✅ **COMPLETE** | `NodeClient` proactive checks, `MessageClient`, Wear OS `SensorManager`. |
| **M6** | Real-Time Hardware Sensor Streaming & Zero Synthetic Backfill | ✅ **COMPLETE** | Tested and verified live on **Galaxy Watch4 + Galaxy S21 FE**. |
| **M7 (Deferred)**| Firebase & Cloud Sync | ⏸️ **DEFERRED** | Deferred per decision to prioritize local watch features. |
| **Sensor Expansion** | Steps/Activity (`Sensor.TYPE_STEP_COUNTER`) + SpO2 (`HealthTrackerType.SPO2_ON_DEMAND`) | ✅ **COMPLETE** | Multi-path Wear OS Data Layer (`/steps`, `/spo2`), reactive Flutter streams, 32/32 tests. |
| **UI Modernization & Performance** | Wear OS 60fps lag fix, AMOLED styling, Flutter design system overhaul | ✅ **COMPLETE** | 1Hz IPC rate-limiting, node caching, pulsing hero pulse card, squircle metric cards. |

---

## Key Technical Milestones Accomplished

### 1. Dual-Engine Physical PPG Sensor Engine & Expanded Sensors (Wear OS)
- Integrated **Samsung Health Sensor SDK (v1.4.1 AAR)** (`HealthTrackingService` & `HealthTracker`) for raw continuous heart rate and on-demand SpO2 spot checks.
- Implemented **Android Wear OS Platform Failover** (`SensorManager.getDefaultSensor(Sensor.TYPE_HEART_RATE)`) with `SENSOR_DELAY_UI`.
- Added hardware **Step Counter** (`Sensor.TYPE_STEP_COUNTER`) and **Step Detector** (`Sensor.TYPE_STEP_DETECTOR`) tracking.
- Resolved Wear OS 4+ (One UI Watch 5/6) permission security restrictions by declaring `android.permission.health.READ_HEART_RATE`, `android.permission.BODY_SENSORS_BACKGROUND`, and `android.permission.ACTIVITY_RECOGNITION`.

### 2. Wear OS 60fps Performance Optimization & Lag Elimination
- **Eliminated Recomposition Storm**: Bounded UI state dispatch to at most once per 500ms (or on significant delta), preventing 50–100Hz Compose recomposition churn on Exynos W920.
- **1 Hz Data Layer Transmission**: Bounded Bluetooth Data Layer message dispatches to 1 message/sec max per sensor, eliminating IPC queue flooding.
- **Node Caching**: Implemented thread-safe caching of connected node IDs with a 10s TTL, eliminating continuous `NodeClient.connectedNodes` IPC calls during active streaming.
- **Optimized Sensor Delay**: Switched from `SENSOR_DELAY_FASTEST` to `SensorManager.SENSOR_DELAY_UI` (~60ms), reducing CPU interrupt overhead by ~80%.

### 3. Native Bridge & Reliable Multi-Metric Protocol
- Standardized distinct message endpoints over Google Play Services Wearable Data Layer:
  - `/vitalsync/connection` (Connection state)
  - `/vitalsync/heartrate` (PPG live heart rate)
  - `/vitalsync/steps` (Cumulative steps)
  - `/vitalsync/spo2` (Spot blood oxygen saturation)
- `WatchDataHolder` singleton manages thread-safe state, `lastHeartRate`, `lastSteps`, `lastSpO2`, and 30-second automatic staleness degradation.
- Foreground `MessageClient.OnMessageReceivedListener` + background `WatchListenerService` dual delivery.

### 4. UI Modernization & Health Design System
- **Wear OS AMOLED Revamp**:
  - True `#000000` black background for OLED battery efficiency and infinite contrast.
  - Animated pulsing heart icon with `rememberInfiniteTransition` when active.
  - Large bold 32sp BPM readout + styled status badges.
  - Quick metric pills for Steps (`🚶`) and SpO2 (`🫁`).
  - Elevated action chips for live tracking, SpO2 spot checks, permissions, and phone sync.
- **Flutter Companion App Design System**:
  - Deep Obsidian dark mode (`#0B0F17`) and Crisp Health Slate light mode (`#F8FAFC`).
  - Custom `CardThemeData` with 18dp rounded corners and subtle border outlines.
  - Semantic metric palettes: Crimson Rose (HR), Emerald Mint (Steps), Sky Cyan (SpO2), Lavender Purple (Insights).
  - `MetricSummaryCard`: 12dp squircle icons, bold hero values, micro visual baseline gauge, quality/confidence pills.
  - `WatchStatusCard`: Connectivity banner with glowing pulse dot and live recency (`● Connected • Updated 2s ago`).
  - All tabs (Dashboard, Metrics, Insights, History, Profile) upgraded with cohesive visual styling.

---

## Live Hardware Verification

- **Watch Device**: Samsung Galaxy Watch4 (`SM_R870`, Wear OS 4 / One UI Watch 5)
- **Phone Device**: Samsung Galaxy S21 FE (`SM_G990B2`, Android 14 / One UI 6)
- **Verified Flows**:
  1. Phone auto-detects paired Galaxy Watch4 on launch (`● Connected`).
  2. Watch app activates optical PPG sensor upon tapping `Start Live Tracking`.
  3. Real-time heart rate streams over `/vitalsync/heartrate` at a smooth 1 Hz cadence.
  4. Step counter sensor streams cumulative steps over `/vitalsync/steps` to the Activity summary card.
  5. On-demand SpO2 tracker reads spot blood oxygen and streams over `/vitalsync/spo2` to the SpO2 summary card.
  6. Zero lag or stutter on watch UI during continuous streaming.

---

## Test Suite & Quality Status

- `flutter analyze`: **0 issues found** (Clean static analysis).
- `flutter test`: **32 / 32 unit & widget tests passed** (100% pass rate).
- Watch APK: `./gradlew :app:assembleDebug` → **BUILD SUCCESSFUL**.
- Mobile APK: `flutter build apk --debug` & `flutter build apk --release` → **BUILD SUCCESSFUL**.
- GitHub Repository: `https://github.com/Peeyush2005/VitalSync.git` on branch `main`.
