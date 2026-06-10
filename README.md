# SleepChartKit

<img width="1920" height="1080" alt="Shots Mockups (48)" src="https://github.com/user-attachments/assets/0c86507d-1243-43f7-b8e1-933446034500" />

A clean, lightweight SwiftUI package for displaying beautiful sleep stage visualizations with comprehensive HealthKit integration.

> **This repository is the home of SleepBank** — a **daytime alertness manager**
> for iOS + watchOS, built on top of the SleepChartKit package documented further
> below.

---

# 😴⚡ SleepBank — a daytime alertness manager

**For the nights you can't get the sleep you need, SleepBank is the healthiest way
through the next day** — timing naps, light, and movement so you stay sharp without
leaning on caffeine or other stimulants.

It began as a power-nap app and grew into a **daytime alertness manager**: it helps
you *time* rest and light so you feel sharp through the day — using a smart alarm, a
predicted alertness curve, and the natural levers that actually move it (naps,
morning daylight, morning movement). It's honest by design: it shows you *when* to
act, not a pseudo-scientific score — and it's clear that this helps you **cope with
and optimize** a short-sleep day, not *replace* the sleep you actually need.

**Most wearables tell you your *readiness* for the day — a score you receive.
SleepBank is the *response*:** it turns that depletion into a forward-looking,
hour-by-hour plan (when you'll dip, when to nap, when to get light) so you can act
on the day instead of just rating it. Readiness is the diagnosis; SleepBank is the
levers. (It reads the same signals — sleep, HRV, resting heart rate — so a readiness
score can even feed it.)

> **Status:** investigational / pre-validation **wellness prototype** — **not** a
> medical device and makes no diagnostic claim. See [`RATIONALE.md`](RATIONALE.md).

## What it does

### 🛌 Smart-alarm power naps — *the core*
- Two nap types: **Power Nap** (~20 min, wake before deep sleep) and **Cycle Nap**
  (~90 min, one full cycle).
- The alarm fires off **detected sleep onset**, not the clock — it wakes you in
  light sleep, **before slow-wave (N3) sleep consolidates**, to dodge the grogginess
  of sleep inertia.
- Wakes on the earliest of: your target, a safety ceiling, **deep-sleep approach**,
  or a **spontaneous awakening** — tiered haptic → audible.

### ⚡ "You are here" — your daily alertness curve
- A predicted **two-process** curve (circadian rhythm − sleep pressure) for the
  whole day: the late-morning peak, the **post-lunch dip**, the evening **second
  wind**, and the night plunge.
- A **"you are here"** marker with your current % and a plain-words phase, plus the
  single most-relevant move (a nap when it would help, morning light when it's early).
- **Last night's sleep sets the curve's height** — a short night visibly lowers it
  all day, and a dashed branch shows where a nap *now* could take you.

### 🔋 Energy ring & the (honest) sleep bank
- An Apple-Activity-style **charge ring** that fills when you wake from a nap and
  **drains over the benefit window** — because nap alertness is genuinely transient.
- A **descriptive** sleep bank: naps today, minutes this week, streaks. Deliberately
  **not** a ledger — naps restore alertness, they don't mathematically repay sleep
  debt, and the app says so.

### 🗓️ Today's Plan — the response layer
- Turns the curve into an **agenda**: get morning light, **nap before your predicted
  dip**, wind down in time — with a readiness header ("how your day starts").
- **Calendar-aware**: it suggests a nap in a *free* slot, not on top of a meeting
  (reads only busy times, never event details). Add **"always OK to nap" windows**
  in Settings that override the calendar (e.g., a quiet stretch in a long appointment).
- Delivered by a **morning notification**, shown on the **phone and watch**, and
  speakable via Siri ("How alert am I?" / "Should I nap?").

### 🌙 Wind Down — bring alertness *down* to protect sleep
- A guided routine (paced breathing + relaxing sounds), evening-light/screens-off
  guidance, and a self-reported **"screens off" streak**.
- **Block distracting apps** during wind-down (FamilyControls/ManagedSettings) —
  a blocklist or a **"Bare Necessities"** allow-only mode — manually or on a nightly
  schedule (a `DeviceActivityMonitor` automation on a Home hub). *iOS won't let apps
  **read** Screen Time, so we **enforce** instead of track.*
- **Warm your HomeKit lights** at wind-down (color temperature, via one Home scene);
  the all-day curve is left to Apple Adaptive Lighting.

### ☀️ Morning light & movement — circadian anchoring
- Reads Apple Watch **Time in Daylight**, **sub-segmented by window** — morning
  light is weighted because that's what anchors your body clock.
- A morning walk earns a small, honest lift on the curve (the **cortisol awakening
  response**); **morning movement** earns its own credit (exercise is a non-photic
  zeitgeber). Stacked but capped — and **fasted/caffeine are deliberately *not*
  credited** without evidence.
- A 🌅 **morning-light streak**, plus a **daylight detail screen** that explains why
  it matters (anchors your rhythm + better sleep tonight).

### 📡 Sensor fusion
- A ladder of optional signals: **Apple Watch** (HR + immobility) → **Polar H10**
  (HR, HRV, accelerometer, breathing, posture) → **Muse** frontal **EEG**.
- Onset is detected by fusing immobility with HR drop / HRV rise / breathing slowing
  / EEG; deep-sleep approach is detected to trigger the wake.
- **AirPods Pro 3 heart rate** is on the roadmap as a fourth, zero-extra-hardware
  sensor (the earbuds are already in for the wind-down audio) — see
  [`docs/AIRPODS_HR_SENSOR.md`](docs/AIRPODS_HR_SENSOR.md).

### 📲 Everywhere you look
- **Home / Lock-screen widgets** — a live "you are here" alertness % + morning-light
  streak, and banked naps.
- **Apple Watch app & complications** — start/stop naps, nap totals, a morning-light
  streak, and your **next plan action** one tap from the watch face.
- **Siri / Shortcuts** — *"How alert am I?"* / *"Should I nap?"* answered without
  opening the app, plus *"Start a nap."*
- **Notifications** — a morning plan nudge and an evening wind-down reminder (both
  toggleable in **Settings**), a nap **Live Activity**, and **deep links**
  (`sleepbank://{plan,alertness,daylight,winddown,nap,settings}`).

### 🎧 Sounds & guided relaxation
- Procedural **white / pink / brown noise** and a **guided TTS relaxation** (paced
  4-7-8 breathing + body relaxation), with smooth audio ducking and AirPlay route
  control — for naps and the evening wind-down.

### 🍏 Health & data pipeline
- Writes naps to **Apple Health**.
- A built-in **validation + training-data pipeline**: every nap is captured as a
  labeled trace, and raw Muse EEG auto-syncs via iCloud to a Mac-side **YASA**
  staging tool — building toward an on-device Core ML onset model.

## The evidence base

SleepBank is built on a deliberately honest, fact-checked evidence base — claims
verified against primary sources, with what is *not* supported flagged:

- [`RATIONALE.md`](RATIONALE.md) — clinical rationale & regulatory positioning
- [`docs/NAP_BENEFIT_EVIDENCE.md`](docs/NAP_BENEFIT_EVIDENCE.md) — why short naps work + the honest sleep-debt framing
- [`docs/DAYLIGHT_EVIDENCE.md`](docs/DAYLIGHT_EVIDENCE.md) — morning light, circadian anchoring & the cortisol awakening response
- [`docs/EEG_EVIDENCE.md`](docs/EEG_EVIDENCE.md) — Muse / frontal-EEG sleep staging
- [`docs/WIND_DOWN_MODE.md`](docs/WIND_DOWN_MODE.md) — evening app-shielding (enforce, not measure — the Screen Time API reality)
- [`docs/AIRPODS_HR_SENSOR.md`](docs/AIRPODS_HR_SENSOR.md) — AirPods Pro 3 heart-rate access research
- [`docs/AIRPODS_HR_SENSOR.md`](docs/AIRPODS_HR_SENSOR.md) — AirPods Pro 3 heart-rate access research
- [`ARCHITECTURE.md`](ARCHITECTURE.md) — app design

## Building SleepBank

The app project is generated with **XcodeGen**:

```sh
brew install xcodegen
xcodegen generate
open SleepBank.xcodeproj
```

Targets: **SleepBank** (iOS app), **SleepBankWatch** (watchOS), **SleepBankWidget**
(iOS widgets + Live Activity), **SleepBankWatchWidget** (complications). Requires
iOS 17+. Onset/nap logic lives in the pure, unit-tested **SleepBankCore** library
(`swift test`).

---

# SleepChartKit — the charting package underneath

SleepChartKit is the SwiftUI sleep-visualization package SleepBank is built on; the
rest of this README documents it.

## Features

- 📊 **Timeline Visualization** - Interactive sleep stage timeline with smooth stage transitions
- 🧘 **Minimal Style** - Lightweight timeline view without legends or axis chrome
- 🎨 **Customizable Colors** - Define your own color scheme for different sleep stages
- ⏰ **Time Axis** - Clear time labels showing sleep session duration
- 📋 **Legend** - Duration summary for each sleep stage
- 🏥 **HealthKit Integration** - Native support for `HKCategoryValueSleepAnalysis` data
- 🌍 **Localization Support** - Configurable display names for internationalization
- 🔧 **SOLID Architecture** - Clean, testable, and extensible design
- 📱 **Cross-Platform** - iOS 15+, macOS 12+, watchOS 8+, tvOS 15+

## Installation

### Swift Package Manager

Add SleepChartKit to your project via Xcode:

1. File → Add Package Dependencies
2. Enter: `https://github.com/DanielJamesTronca/SleepChartKit`
3. Select version and add to target

Or add to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/DanielJamesTronca/SleepChartKit", from: "1.2.0")
]
```

## Quick Start

### Basic Usage

```swift
import SwiftUI
import SleepChartKit

struct ContentView: View {
    let sleepSamples = [
        SleepSample(stage: .asleepDeep, startDate: date1, endDate: date2),
        SleepSample(stage: .asleepCore, startDate: date2, endDate: date3),
        SleepSample(stage: .asleepREM, startDate: date3, endDate: date4),
        SleepSample(stage: .awake, startDate: date4, endDate: date5)
    ]
    
    var body: some View {
        SleepChartView(samples: sleepSamples)
            .padding()
    }
}
```

### Minimal Timeline

Use the minimal style when you only need the stage bars without the axis or legend:

```swift
SleepChartView(
    samples: sleepSamples,
    style: .minimal
)
```

### Circular Chart

The circular chart displays sleep duration as a percentage of a configurable threshold, starting from the top (12 o'clock) and filling clockwise:

```swift
import SwiftUI
import SleepChartKit

struct CircularChartView: View {
    let sleepSamples = [
        SleepSample(stage: .asleepDeep, startDate: date1, endDate: date2),
        SleepSample(stage: .asleepCore, startDate: date2, endDate: date3),
        SleepSample(stage: .asleepREM, startDate: date3, endDate: date4)
    ]
    
    var body: some View {
        VStack(spacing: 30) {
            // Basic circular chart (9-hour threshold by default)
            SleepCircularChartView(samples: sleepSamples)
            
            // Custom threshold and styling
            SleepCircularChartView(
                samples: sleepSamples,
                lineWidth: 20,
                size: 200,
                showIcons: false,
                thresholdHours: 8.0
            )
        }
        .padding()
    }
}
```

#### Circular Chart Parameters

- `thresholdHours` - Sleep duration threshold for percentage calculation (default: 9.0 hours)
- `showIcons` - Display sun/moon icons at start/end of sleep arc (default: true)
- `lineWidth` - Width of the circular segments (default: 16)
- `size` - Size of the circular chart (default: 160)
- `showLabels` - Show duration and time labels in center (default: true)

**Example:** If a user sleeps 7 hours with a 9-hour threshold, the circle fills 77.8% (7/9) of the way around.

### HealthKit Integration

<img width="1920" height="1080" alt="Gym Hero Frame 481030" src="https://github.com/user-attachments/assets/231b8ad7-e77f-4fcd-aa47-cf13f2358c42" />

```swift
import SwiftUI
import HealthKit
import SleepChartKit

@available(iOS 16.0, *)
struct HealthKitSleepView: View {
    @State private var healthKitSamples: [HKCategorySample] = []
    
    var body: some View {
        // Direct HealthKit integration
        SleepChartView(healthKitSamples: healthKitSamples)
            .padding()
            .onAppear {
                loadHealthKitData()
            }
    }
    
    private func loadHealthKitData() {
        // Your HealthKit data loading logic
        // healthKitSamples = fetchedSamples
    }
}
```

## Sleep Stages

SleepChartKit supports the following sleep stages:

- **Awake** - Periods of wakefulness
- **REM Sleep** - Rapid Eye Movement sleep
- **Light Sleep** - Core/light sleep stages
- **Deep Sleep** - Deep sleep stages
- **Unspecified Sleep** - General sleep periods
- **In Bed** - Time spent in bed (filtered when other stages present)

## Customization

### Custom Colors

```swift
struct MyColorProvider: SleepStageColorProvider {
    func color(for stage: SleepStage) -> Color {
        switch stage {
        case .awake: return .red
        case .asleepREM: return .purple
        case .asleepCore: return .blue
        case .asleepDeep: return .indigo
        case .asleepUnspecified: return .gray
        case .inBed: return .secondary
        }
    }
}

SleepChartView(
    samples: sleepSamples,
    colorProvider: MyColorProvider()
)
```

### Custom Display Names

```swift
// Using custom names
let customNameProvider = CustomSleepStageDisplayNameProvider(customNames: [
    .awake: "Awake",
    .asleepREM: "REM Sleep", 
    .asleepCore: "Light Sleep",
    .asleepDeep: "Deep Sleep",
    .asleepUnspecified: "Unknown Sleep",
    .inBed: "In Bed"
])

SleepChartView(
    samples: sleepSamples,
    displayNameProvider: customNameProvider
)
```

### Localization Support

```swift
// Using localized strings from your app's bundle
let localizedProvider = LocalizedSleepStageDisplayNameProvider(
    bundle: .main,
    tableName: "SleepStages"
)

SleepChartView(
    samples: sleepSamples,
    displayNameProvider: localizedProvider
)
```

Create a `SleepStages.strings` file:
```
"sleep_stage_awake" = "Awake";
"sleep_stage_asleepREM" = "REM Sleep";
"sleep_stage_asleepCore" = "Light Sleep";
"sleep_stage_asleepDeep" = "Deep Sleep";
"sleep_stage_asleepUnspecified" = "Sleep";
"sleep_stage_inBed" = "In Bed";
```

### Custom Duration Formatting

```swift
struct MyDurationFormatter: DurationFormatter {
    func format(_ duration: TimeInterval) -> String {
        let hours = Int(duration) / 3600
        let minutes = (Int(duration) % 3600) / 60
        return "\(hours):\(String(format: "%02d", minutes))"
    }
}

SleepChartView(
    samples: sleepSamples,
    durationFormatter: MyDurationFormatter()
)
```

### Complete Customization Example

```swift
@available(iOS 16.0, *)
SleepChartView(
    healthKitSamples: healthKitSamples,
    colorProvider: MyColorProvider(),
    durationFormatter: MyDurationFormatter(),
    displayNameProvider: LocalizedSleepStageDisplayNameProvider()
)
```

## Architecture

SleepChartKit follows SOLID principles with a clean, modular architecture:

### Core Components

- **SleepChartView** - Main timeline chart container
- **SleepCircularChartView** - Circular percentage-based chart with threshold support
- **SleepTimelineGraph** - Timeline visualization with Canvas
- **SleepTimeAxisView** - Time labels and axis
- **SleepLegendView** - Sleep stage legend

### Data Models

- **SleepSample** - Represents a sleep period
- **SleepStage** - Enum of sleep stages
- **TimeSpan** - Time axis labels

### Services (Protocols)

- **SleepStageColorProvider** - Stage color customization
- **SleepStageDisplayNameProvider** - Stage display name customization
- **DurationFormatter** - Duration text formatting
- **TimeSpanGenerator** - Time axis customization

## HealthKit Integration

SleepChartKit provides native support for HealthKit sleep analysis data with automatic conversion and type safety.

### Direct HealthKit Usage

```swift
import HealthKit
import SleepChartKit

@available(iOS 16.0, *)
func createChart(with healthKitSamples: [HKCategorySample]) -> some View {
    // Direct integration - automatically converts HealthKit samples
    SleepChartView(healthKitSamples: healthKitSamples)
}
```

### Manual Conversion

```swift
// Convert individual samples
let sleepSample = SleepSample(healthKitSample: hkSample)

// Batch convert samples
let sleepSamples = SleepSample.samples(from: healthKitSamples)

// Create chart with converted samples
SleepChartView(samples: sleepSamples)
```

### Working with SleepStage and HealthKit

```swift
// Convert between SleepStage and HKCategoryValueSleepAnalysis
let sleepStage = SleepStage(healthKitValue: .asleepREM) // Optional conversion
let healthKitValue = sleepStage.healthKitValue // Direct conversion

// Use with color providers
let color = colorProvider.color(for: .asleepREM) // HKCategoryValueSleepAnalysis
```

### Availability

HealthKit integration requires:
- iOS 16.0+ / macOS 13.0+ / watchOS 9.0+
- HealthKit framework available

## Requirements

- iOS 15.0+
- macOS 12.0+
- watchOS 8.0+
- tvOS 15.0+
- Xcode 13.0+
- Swift 5.5+

## Contributing

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

## License

SleepChartKit is available under the MIT license. See the LICENSE file for more info.

## Example
<img width="1920" height="1080" alt="Shots Mockups (43)" src="https://github.com/user-attachments/assets/4bb626ef-51e0-40cb-ab10-220226abf814" />

*Sample sleep chart showing a night's sleep with deep sleep, REM, and wake periods.*
