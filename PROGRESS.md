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
| **Sensor Expansion** | Steps/Activity (`Sensor.TYPE_STEP_COUNTER`) + SpO2 (`HealthTrackerType.SPO2_ON_DEMAND`) | ✅ **COMPLETE** | Multi-path Wear OS Data Layer (`/steps`, `/spo2`), reactive Flutter streams. |
| **UI Modernization & Performance** | Wear OS 60fps lag fix, AMOLED styling, Flutter design system overhaul | ✅ **COMPLETE** | 1Hz IPC rate-limiting, node caching, pulsing hero pulse card, squircle metric cards. |
| **M8** | Per-Metric Data Quality Engine (HR, Steps, SpO2) | ✅ **COMPLETE** | Signal variance, sampling cadence, delta jumps, repeat spot consistency, real quality/confidence pills. |
| **M9** | Real-Time Activity Context Classification | ✅ **COMPLETE** | Resting/Walking/Active/Exercising/Unknown fusion from cadence + HR elevation gated by M8 confidence. |
| **M10** | Local SQLite Persistence & Personal Baseline Engine | ✅ **COMPLETE** | Async `sqflite` persistence, zero UI blocking, personalized expected bounds (median ± 1.5σ), quality gating. |
| **M11** | Biometric Trend Engine & Insights Intelligence | ✅ **COMPLETE** | Multi-day windowing (7d HR/steps, 14d SpO2), rolling stddev, Z-score, slope, repeated deviation, plain-language insights. |
| **M12** | Anomaly Detection Engine & Context-Aware Surfacing | ✅ **COMPLETE** | Pure combination layer, structural M8 quality gate, M10 deviation ratio math, M9 activity suppression, M11 trend escalation, ongoing anomaly deduplication. |

---

## Key Technical Milestones Accomplished

### 1. Anomaly Detection Engine (M12)
- **Pure Combination & Decision Layer**: Implemented in `lib/analytics/anomaly_engine.dart`. Re-derives no stats independently; purely combines M8 quality, M9 activity context, M10 personal baseline, and M11 multi-day trend inputs.
- **Structural Quality Precondition (Gate 1, First, Always)**: Evaluates M8 data quality at the very top before any deviation math exists in scope. Readings with quality < 0.60 return `AnomalyResult.gated` with confidence 0.0 — zero low-quality readings can ever be flagged as anomalies.
- **M10 Personal Baseline & Recency Gating (Gate 2)**: Requires established baseline with expected range bounds (`minExpected`, `maxExpected`) and fresh measurements (≤ 10 minutes old).
- **M9 Activity Context Suppression (Gate 3)**: High-side heart rate elevation during `Exercising`, `Active`, or `Walking` is classified as expected physiological response and suppressed. Low-side deviations (e.g. bradycardia crash) are never suppressed by activity.
- **Cumulative Steps Disambiguation**: Point comparisons against daily baseline ranges are skipped for cumulative step counts. Step anomalies surface exclusively via M11 confirmed trend patterns.
- **Documented Severity Scale**: Expressed in units of the expected range's half-width:
  - `mild`: Deviation ratio ≤ 0.25 beyond expected range bounds.
  - `moderate`: Deviation ratio 0.25 to 0.75 beyond expected bounds.
  - `severe`: Deviation ratio > 0.75 beyond expected bounds.
- **M11 Trend Corroboration & Escalation**: Confirmed acute/repeated patterns (`suddenShift`, `repeatedDeviation` with confidence ≥ 0.50) escalate severity by one level and surface pattern anomalies even when a single reading is within range.
- **Ongoing vs. New Anomaly Deduplication**: Tracks stable `anomalyKey` (`<metric>:<high|low>[:pattern]`) with a 6-hour continuity window. Sustained deviations set `isOngoing = true` and carry `firstDetectedAt` forward to prevent alert fatigue.
- **Non-Diagnostic UI Notice Banners**: `MetricSummaryCard` displays non-diagnostic notices ("unusual pattern", "worth monitoring", "outside your usual range") with severity color accenting and `Ongoing` status chips.

### 2. Biometric Trend Engine (M11)
- **Mathematical Multi-Day Trend Models**: Implemented in `lib/analytics/trend_engine.dart` with tailored physiological windowing:
  - *Heart Rate*: 7-day lookback window aggregated into daily resting medians.
  - *Steps*: 7-day lookback window aggregated into daily cumulative step totals.
  - *SpO2*: 14-day lookback window evaluating sparse on-demand spot checks chronologically.
- **Statistical Measures**: Computes Moving Average, Rolling Standard Deviation, Z-Score relative to M10 baseline, Percent Deviation, and Linear Regression Slope (units/day).
- **Trend Classifications**:
  - `stable`: Recent readings within expected baseline bounds.
  - `increasing` / `decreasing`: Statistically elevated or lowered trend (|Z| ≥ 1.25, slope trend).
  - `suddenShift`: Acute sustained elevation or drop (|Z| ≥ 2.2).
  - `repeatedDeviation`: Alternating upper/lower bound violations outside expected baseline range.
  - `insufficientData`: Clean gating requiring minimum days/samples and established M10 baselines ("not enough data yet" pattern).
- **Data Quality Gating**: Excludes low M8 quality (<0.60) readings and scales trend confidence by the valid sample ratio.
- **UI & Repository Integration**: Powered by `trendHistoryProvider` querying SQLite time ranges and `InsightsScreen` displaying status badges, plain non-diagnostic headlines, and baseline references.

### 2. Local Persistence & Personal Baseline Engine (M10)
- **Local Persistence (`HealthDatabase`)**: SQLite persistence via `sqflite` with composite indexes (`idx_measurements_type_timestamp`, `idx_measurements_type_activity_timestamp`) and non-blocking asynchronous writes.
- **Personal Baseline Engine (`PersonalBaselineEngine`)**: Computes central tendency baseline, standard deviation, and normal expected physiological ranges (median ± 1.5σ) per metric.
- **Strict Gating**: Requires minimum sample counts (≥5 resting HR, ≥3 step days, ≥3 SpO2) and filters low M8 quality (<0.60) readings before establishing a baseline.

### 3. Data Quality Engine (M8) & Activity Context Classification (M9)
- **Per-Metric Mathematical Quality Assessment**: Factors physiological sanity bounds, delta jumps, rolling variance, and sampling cadence into 0.0–1.0 quality scores.
- **Multi-Sensor Activity Fusion**: Fuses real-time step cadence, heart rate elevation, and quality scores to classify user states (`Resting`, `Walking`, `Active`, `Exercising`, `Unknown`).
- **Dashboard UI Cards**: `MetricSummaryCard` displays live quality pills; `ActivityContextCard` renders real-time state and cadence.

### 4. Dual-Engine Physical PPG Sensor Engine & Wear OS Modernization
- **Samsung Health Sensor SDK (v1.4.1 AAR)** + Android Wear OS Platform Failover (`SensorManager`).
- **Eliminated Recomposition Storm**: Bounded UI state dispatch to ≤ 1 update / 500ms and Bluetooth Data Layer transmissions to 1 Hz.
- **AMOLED Dark Theme**: `#000000` AMOLED styling with pulsing pulse indicators on Wear OS.

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
- `flutter test`: **104 / 104 unit & widget tests passed** (100% pass rate).
- Watch APK: `./gradlew :app:assembleDebug` → **BUILD SUCCESSFUL**.
- Mobile APK: `flutter build apk --debug` & `flutter build apk --release` → **BUILD SUCCESSFUL**.
- GitHub Repository: `https://github.com/Peeyush2005/VitalSync.git` on branch `main`.
