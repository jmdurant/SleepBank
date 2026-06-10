//
//  DayPlanView.swift
//  SleepBank
//
//  "Today's Plan" — the response layer. Readiness apps tell you the day is
//  compromised; this turns that into an agenda: how the day starts, get morning
//  light, nap before the afternoon dip, wind down in time. Built from the same
//  AlertnessRhythm as the curve.
//

import SwiftUI
import SleepBankCore

struct DayPlanView: View {
    var health = HealthKitService.shared
    var store = NapDecisionStore.shared
    var dayStore = DayPlanStore.shared
    @State private var scheduledNap: Date? = PlanNotificationService.scheduledNapAt
    @State private var scheduledActivities = PlanNotificationService.scheduledActivities
    @State private var showCalendar = false

    var body: some View {
        TimelineView(.periodic(from: .now, by: 600)) { context in
            let now = context.date
            let isToday = dayStore.selectedOffset == 0
            let rhythm = isToday ? AlertnessProvider.rhythm(health: health, store: store, now: now)
                                 : futureRhythm(now: now)
            // User's "always OK to nap" windows override the calendar's busy times.
            let busy = isToday ? Intervals.subtract(NapWindowsStore.shared.todayIntervals(now: now),
                                                    from: CalendarService.shared.busyToday(now: now)) : []
            let plan = DayPlan.build(rhythm: rhythm, now: isToday ? now : rhythm.wakeTime, busy: busy)
            let planned = dayStore.plan(for: dayStore.selectedDate)
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    dayNav(now: now, isToday: isToday)
                    if isToday {
                        AlertnessRecapView()
                        if let napAt = scheduledNap { scheduledNapCard(napAt) }
                        ForEach(scheduledActivities) { scheduledActivityCard($0) }
                    }
                    if !planned.isEmpty { plannedCard(planned) }
                    agendaCard(plan)
                    if isToday && plan.napBlockedByCalendar {
                        Label("Your calendar's booked through your dip — grab even 10 min if a gap opens.",
                              systemImage: "calendar.badge.exclamationmark")
                            .font(.caption).foregroundStyle(.orange)
                            .padding(.horizontal, 4)
                    }
                    NavigationLink(value: HomeRoute.windDown) {
                        HStack {
                            Image(systemName: "moon.stars.fill")
                            Text("Tonight's wind-down").font(.subheadline.weight(.semibold))
                            Spacer()
                            Image(systemName: "chevron.right").font(.caption)
                        }
                        .padding()
                        .background(.purple.opacity(0.15), in: RoundedRectangle(cornerRadius: 16))
                        .foregroundStyle(.purple)
                    }
                    .buttonStyle(.plain)
                    Text("A plan to get through the day well — it helps you cope with a short night, not replace the sleep you need.")
                        .font(.caption2).foregroundStyle(.secondary)
                }
                .padding()
            }
        }
        .navigationTitle("Plan")
        .task {
            await CalendarService.shared.requestAccess()
            if await health.requestAuthorization() { await health.refreshAll() }
        }
        .onAppear {
            scheduledNap = PlanNotificationService.scheduledNapAt
            scheduledActivities = PlanNotificationService.scheduledActivities
        }
    }

    // MARK: - Day navigation

    private func dayNav(now: Date, isToday: Bool) -> some View {
        HStack(spacing: 8) {
            Button { dayStore.shift(by: -1) } label: { Image(systemName: "chevron.left").font(.headline) }
                .buttonStyle(.plain).foregroundStyle(.indigo).disabled(dayStore.selectedOffset == 0)
            Spacer()
            Text(dayLabel(now: now, isToday: isToday)).font(.headline)
                .onTapGesture { showCalendar = true }
                .popover(isPresented: $showCalendar) {
                    DatePicker("Day", selection: Binding(get: { dayStore.selectedDate },
                                                         set: { dayStore.select($0); showCalendar = false }),
                               in: Date()..., displayedComponents: .date)
                        .datePickerStyle(.graphical).padding()
                        .frame(minWidth: 300, minHeight: 320).presentationCompactAdaptation(.popover)
                }
            Spacer()
            Button { dayStore.shift(by: 1) } label: { Image(systemName: "chevron.right").font(.headline) }
                .buttonStyle(.plain).foregroundStyle(.indigo).disabled(dayStore.selectedOffset >= 14)
        }
        .padding(.horizontal, 4)
    }

    private func dayLabel(now: Date, isToday: Bool) -> String {
        if isToday { return "Today" }
        if dayStore.selectedOffset == 1 { return "Tomorrow" }
        return dayStore.selectedDate.formatted(.dateTime.weekday(.wide).month().day())
    }

    private func futureRhythm(now: Date) -> AlertnessRhythm {
        let today = AlertnessProvider.rhythm(health: health, store: store, now: now)
        let wake = Calendar.current.date(byAdding: .day, value: dayStore.selectedOffset, to: today.wakeTime) ?? today.wakeTime
        let avg = health.sleepAverage7Day
        let need = max(avg > 0 ? avg : 7.5, 6)
        let debt = avg > 0 ? SleepScore.debt(asleepHours: avg, needHours: need) : 0.25
        return AlertnessRhythm(wakeTime: wake, sleepDebt: debt)
    }

    /// The naps/walks/workouts planned on the curve for the selected day.
    private func plannedCard(_ planned: [PlanItem]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Your plan").font(.headline)
            ForEach(planned.sorted { ($0.at ?? .distantFuture) < ($1.at ?? .distantFuture) }) { item in
                HStack(spacing: 10) {
                    ZStack {
                        Circle().fill(item.kind.tint.opacity(0.18)).frame(width: 30, height: 30)
                        Image(systemName: item.kind.icon).font(.caption).foregroundStyle(item.kind.tint)
                    }
                    VStack(alignment: .leading, spacing: 1) {
                        Text(item.kind.label).font(.subheadline.weight(.semibold))
                        Text(plannedDetail(item)).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if let at = item.at {
                        Text(at, format: .dateTime.hour().minute()).font(.caption.weight(.medium)).foregroundStyle(item.kind.tint)
                    }
                }
            }
            Text("Edit on the alertness curve (Home).").font(.caption2).foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading).padding()
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    private func plannedDetail(_ item: PlanItem) -> String {
        if item.kind == .nap { return item.napType == .cycle ? "Cycle · ~90 min" : "Power · ~20 min" }
        return "\(Int(item.minutes)) min · \(item.outdoors ? "outside ☀️" : "inside")"
    }

    /// A scheduled walk/workout from the alertness curve, with a one-tap cancel.
    private func scheduledActivityCard(_ item: PlanNotificationService.ScheduledActivity) -> some View {
        let isWalk = item.kind.caseInsensitiveCompare("Walk") == .orderedSame
        let tint: Color = isWalk ? .orange : .pink
        return HStack(spacing: 12) {
            ZStack {
                Circle().fill(tint.opacity(0.18)).frame(width: 32, height: 32)
                Image(systemName: isWalk ? "figure.walk" : "figure.run").font(.caption).foregroundStyle(tint)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text("\(item.kind) scheduled for \(clock(item.at))").font(.subheadline.weight(.semibold))
                Text(item.outdoors ? "Outside — movement + daylight to anchor tonight's sleep."
                                    : "Indoors — a movement lift to stay sharp.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                PlanNotificationService.shared.cancelActivity(kind: item.kind)
                scheduledActivities = PlanNotificationService.scheduledActivities
            } label: {
                Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Cancel scheduled \(item.kind)")
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 16))
    }

    /// The nap the user scheduled off the alertness curve, with a one-tap cancel.
    private func scheduledNapCard(_ napAt: Date) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(.indigo.opacity(0.18)).frame(width: 32, height: 32)
                Image(systemName: "moon.zzz.fill").font(.caption).foregroundStyle(.indigo)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text("Nap scheduled for \(clock(napAt))").font(.subheadline.weight(.semibold))
                Text("We'll remind you — settle in to stay sharp through the afternoon.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                PlanNotificationService.shared.cancelScheduledNap()
                scheduledNap = nil
            } label: {
                Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Cancel scheduled nap")
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.indigo.opacity(0.12), in: RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Agenda

    private func agendaCard(_ plan: DayPlan) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(plan.items.enumerated()), id: \.offset) { i, item in
                if i > 0 { Divider().padding(.leading, 44) }
                row(item, plan: plan)
            }
        }
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 20))
    }

    private func row(_ item: DayPlan.Item, plan: DayPlan) -> some View {
        let s = style(item.kind)
        return HStack(alignment: .top, spacing: 10) {
            ZStack {
                Circle().fill(s.tint.opacity(item.done ? 0.10 : 0.18)).frame(width: 32, height: 32)
                Image(systemName: item.done ? "checkmark" : s.icon)
                    .font(.caption).foregroundStyle(item.done ? .secondary : s.tint)
            }
            VStack(alignment: .leading, spacing: 1) {
                HStack {
                    Text(title(item, plan: plan))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(item.done ? .secondary : .primary)
                    Spacer()
                    Text(timeLabel(item)).font(.caption.weight(.medium))
                        .foregroundStyle(item.done ? .secondary : s.tint)
                }
                Text(detail(item, plan: plan)).font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 8).padding(.horizontal, 12)
        .opacity(item.done ? 0.7 : 1)
    }

    // MARK: - Wording

    private func style(_ kind: DayPlan.Kind) -> (icon: String, tint: Color) {
        switch kind {
        case .morningLight:    return ("sun.max.fill", .orange)
        case .morningMovement: return ("figure.walk", .green)
        case .nap:             return ("moon.zzz.fill", .indigo)
        case .dip:             return ("arrow.down.right", .red)
        case .windDown:        return ("bed.double.fill", .purple)
        }
    }

    private func title(_ item: DayPlan.Item, plan: DayPlan) -> String {
        switch item.kind {
        case .morningLight:    return item.done ? "Morning light — done" : "Get morning light"
        case .morningMovement: return item.done ? "Morning movement — done" : "Move a little"
        case .nap:             return "Power nap"
        case .dip:             return "Energy dip"
        case .windDown:        return "Wind down"
        }
    }

    private func detail(_ item: DayPlan.Item, plan: DayPlan) -> String {
        switch item.kind {
        case .morningLight:
            return item.done ? "Rhythm anchored." : "Step outside — it anchors your clock and lifts your morning."
        case .morningMovement:
            return item.done ? "Nice — that advances your clock too." : "A short walk advances your clock and wakes you up."
        case .nap:
            if let dip = plan.dipTime { return "Before your \(clock(dip)) dip — wake refreshed going into it." }
            return "A power nap lifts your afternoon."
        case .dip:
            return "Your predicted low — plan around it."
        case .windDown:
            return plan.isShortNight ? "Aim for an earlier night to start tomorrow higher." : "Start winding down to protect tonight."
        }
    }

    private func timeLabel(_ item: DayPlan.Item) -> String {
        if item.done { return "✓" }
        guard let time = item.time else { return "Now" }
        return clock(time)
    }

    private func clock(_ date: Date) -> String { date.formatted(.dateTime.hour().minute()) }
}
