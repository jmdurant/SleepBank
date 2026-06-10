//
//  ContentView.swift
//  SleepBank
//
//  The app shell: a bottom tab bar — Home (Alert Score + curve), Today (the plan),
//  Nap (start + live sensors), History (last night + sleep bank), Settings. Each tab
//  has its own navigation stack; deep links / notifications select the right tab and
//  push as needed. App-wide bootstrap (Health, snapshot, watch sync, notifications)
//  runs once here.
//

import SwiftUI
import WidgetKit
import SleepChartKit
import SleepBankCore

struct ContentView: View {
    @State private var health = HealthKitService.shared
    @AppStorage("appearanceMode") private var appearance: AppearanceMode = .system

    enum Tab: Hashable { case home, today, nap, history, settings }
    @State private var tab: Tab = .home
    @State private var homePath: [HomeRoute] = []
    @State private var todayPath: [HomeRoute] = []
    @State private var napPath: [HomeRoute] = []
    @State private var settingsPath: [HomeRoute] = []

    var body: some View {
        TabView(selection: $tab) {
            NavigationStack(path: $homePath) {
                HomeView().navigationDestination(for: HomeRoute.self, destination: destination)
            }
            .tabItem { Label("Home", systemImage: "bolt.fill") }.tag(Tab.home)

            NavigationStack(path: $todayPath) {
                DayPlanView().navigationDestination(for: HomeRoute.self, destination: destination)
            }
            .tabItem { Label("Today", systemImage: "list.bullet.clipboard.fill") }.tag(Tab.today)

            NavigationStack(path: $napPath) {
                NapTabView().navigationDestination(for: HomeRoute.self, destination: destination)
            }
            .tabItem { Label("Nap", systemImage: "moon.zzz.fill") }.tag(Tab.nap)

            NavigationStack {
                HistoryView()
            }
            .tabItem { Label("History", systemImage: "chart.bar.fill") }.tag(Tab.history)

            NavigationStack(path: $settingsPath) {
                SettingsView().navigationDestination(for: HomeRoute.self, destination: destination)
            }
            .tabItem { Label("Settings", systemImage: "gearshape.fill") }.tag(Tab.settings)
        }
        .preferredColorScheme(appearance.colorScheme)
        .task { await bootstrap() }
        .onOpenURL { open(host: $0.host) }
        .onReceive(NotificationCenter.default.publisher(for: .openPlan)) { note in
            if let route = note.object as? HomeRoute { open(route) }
            PlanNotificationService.shared.clearPending()
        }
    }

    // MARK: - Navigation

    @ViewBuilder
    private func destination(_ route: HomeRoute) -> some View {
        switch route {
        case .plan:      DayPlanView()
        case .daylight:  DaylightView()
        case .alertness: AlertnessDetailView()
        case .windDown:  WindDownView()
        case .nap:       NapView()
        case .settings:  SettingsView()
        }
    }

    /// Route to the right tab (and push within it) for a deep link / notification.
    private func open(_ route: HomeRoute) {
        switch route {
        case .alertness, .daylight: tab = .home;     homePath = [route]
        case .plan:                 tab = .today;    todayPath = []
        case .windDown:             tab = .today;    todayPath = [.windDown]
        case .nap:                  tab = .nap;      napPath = []
        case .settings:             tab = .settings; settingsPath = []
        }
    }

    private func open(host: String?) {
        switch host {
        case "plan":      open(.plan)
        case "daylight":  open(.daylight)
        case "alertness": open(.alertness)
        case "winddown":  open(.windDown)
        case "nap":       open(.nap)
        case "settings":  open(.settings)
        default:          break
        }
    }

    // MARK: - Bootstrap (once, app-wide)

    private func bootstrap() async {
        if let route = PlanNotificationService.shared.pendingRoute {   // cold-start from a notification
            open(route)
            PlanNotificationService.shared.clearPending()
        }
        guard await health.requestAuthorization() else { return }
        await health.refreshAll()
        // Accumulate bedtime history so Sleep Score can grade consistency over time.
        if let bedtime = health.lastNightSleep?.bedtime {
            BedtimeHistoryStore.shared.record(bedtime: bedtime)
        }
        // Snapshot the rhythm so the widget + watch can compute the Alert Score / plan.
        let snapshot = RhythmSnapshot(rhythm: AlertnessProvider.rhythm(now: Date()),
                                      morningLightStreak: health.morningLightStreak, updated: Date())
        snapshot.save()
        PhoneConnectivity.shared.sendDailySummary(
            samples: health.lastNightSamples,
            morningLightStreak: health.morningLightStreak,
            rhythmSnapshot: try? JSONEncoder().encode(snapshot))
        SharedStore.lastNightHours = health.lastNightSleep?.totalHours ?? 0
        SharedStore.restingHR = Int(health.restingHeartRate)
        WidgetCenter.shared.reloadAllTimelines()
        await PlanNotificationService.shared.requestAndSchedule()
    }
}

// MARK: - Home tab

private struct HomeView: View {
    @State private var health = HealthKitService.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                EnergyRingView()
                AlertnessCurveView()
                baselineCard
            }
            .padding()
        }
        .toolbar(.hidden, for: .navigationBar)
    }

    private var baselineCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Today's Baseline").font(.headline)
            Label(health.restingHeartRate > 0 ? "\(Int(health.restingHeartRate)) bpm resting (\(health.restingHRTrend))" : "Resting HR —",
                  systemImage: "heart.fill")
            Label(health.hrvAverage > 0 ? String(format: "%.0f ms HRV", health.hrvAverage) : "HRV —",
                  systemImage: "waveform.path.ecg")
        }
        .font(.subheadline)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }
}

// MARK: - Nap tab (start + live sensors)

private struct NapTabView: View {
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                NapView()   // the two nap types (or the active session) — no extra hop
                VStack(spacing: 12) {
                    link("Live Data — HR & EEG", "waveform.path.ecg.rectangle") { LiveView() }
                    link("Sensors — Muse & H10", "sensor.tag.radiowaves.forward") { SensorsView() }
                    link("Relaxing Sounds", "speaker.wave.2.fill") { SoundsView() }
                }
                .padding(.horizontal)
            }
            .padding(.vertical)
        }
        .navigationTitle("Nap")
    }

    private func link(_ title: String, _ icon: String, @ViewBuilder destination: @escaping () -> some View) -> some View {
        NavigationLink { destination() } label: {
            Label(title, systemImage: icon)
                .frame(maxWidth: .infinity, alignment: .leading).padding()
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - History tab (last night + sleep bank)

private struct HistoryView: View {
    @State private var health = HealthKitService.shared
    @State private var manual = ManualSleepStore.shared
    @State private var editing = false
    @State private var entryHours = 7.0

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                lastNightCard
                chartCard
                NavigationLink { ValidationView() } label: {
                    Label("Validation & Training Data", systemImage: "checklist")
                        .frame(maxWidth: .infinity, alignment: .leading).padding()
                        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
                }
                .buttonStyle(.plain)
            }
            .padding()
        }
        .navigationTitle("History")
        .task { if await health.requestAuthorization() { await health.refreshAll() } }
    }

    private var lastNightCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Last Night").font(.headline)
            if let s = health.lastNightSleep, s.totalHours > 0 {
                let need = max(health.sleepAverage7Day > 0 ? health.sleepAverage7Day : 7.5, 6)
                let score = SleepScore.score(
                    asleepHours: s.totalHours, needHours: need, efficiency: s.efficiency,
                    bedtimeMinutes: s.bedtime.map(BedtimeHistoryStore.minutesFrom6pm),
                    normalMinutes: BedtimeHistoryStore.shared.normalMinutes)
                scoreRow(score)
                Text(String(format: "%.1f h asleep · %.0f%% efficiency", s.totalHours, s.efficiency * 100))
                    .font(.subheadline)
                Text(String(format: "7-day average: %.1f h", health.sleepAverage7Day))
                    .font(.caption).foregroundStyle(.secondary)
            } else if let h = manual.today, !editing {
                Text(String(format: "You logged %.1f h last night.", h)).font(.subheadline)
                Text("Today's Alert Score starts from this.").font(.caption).foregroundStyle(.secondary)
                Button("Change") { entryHours = h; editing = true }.font(.caption)
            } else {
                Text(manual.today == nil ? "No sleep data — how long did you sleep last night?" : "Update last night")
                    .font(.subheadline)
                Stepper(value: $entryHours, in: 0...14, step: 0.25) {
                    Text(String(format: "%.1f hours", entryHours)).monospacedDigit()
                }
                Button {
                    manual.log(hours: entryHours); editing = false
                } label: {
                    Label("Save", systemImage: "checkmark").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    private func scoreRow(_ score: Int) -> some View {
        HStack(spacing: 8) {
            Text("\(score)").font(.system(.title, design: .rounded).bold()).foregroundStyle(.indigo)
            VStack(alignment: .leading, spacing: 0) {
                Text("Sleep Score").font(.caption2).foregroundStyle(.secondary)
                Text(SleepScore.label(score)).font(.subheadline.weight(.semibold))
            }
        }
    }

    private var chartCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Sleep Stages").font(.headline)
            if health.lastNightSamples.isEmpty {
                Text("Charting sample data — grant Health access for your real night.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            SleepChartView(
                samples: health.lastNightSamples.isEmpty ? Self.sampleNight : health.lastNightSamples,
                style: .timeline
            )
            .frame(height: 220)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    /// Placeholder timeline so the chart renders before live data exists.
    private static var sampleNight: [SleepSample] {
        let base = Calendar.current.date(bySettingHour: 23, minute: 0, second: 0, of: Date()) ?? Date()
        func at(_ minutes: Int) -> Date { base.addingTimeInterval(TimeInterval(minutes * 60)) }
        return [
            SleepSample(stage: .awake, startDate: at(0), endDate: at(8)),
            SleepSample(stage: .asleepCore, startDate: at(8), endDate: at(55)),
            SleepSample(stage: .asleepDeep, startDate: at(55), endDate: at(95)),
            SleepSample(stage: .asleepCore, startDate: at(95), endDate: at(150)),
            SleepSample(stage: .asleepREM, startDate: at(150), endDate: at(180)),
            SleepSample(stage: .asleepCore, startDate: at(180), endDate: at(240)),
            SleepSample(stage: .asleepDeep, startDate: at(240), endDate: at(270)),
            SleepSample(stage: .asleepREM, startDate: at(270), endDate: at(320)),
        ]
    }
}

#Preview {
    ContentView()
}
