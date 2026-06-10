//
//  WindDownMonitor.swift
//  SleepBankDeviceMonitor (DeviceActivityMonitor extension)
//
//  Runs the automatic nightly wind-down shield. The app schedules an evening→morning
//  DeviceActivity interval; the OS calls these hooks at its boundaries, even when the
//  app isn't running. Apply/clear logic is shared with the app via `WindDownShield`
//  (App Group), so manual and automatic shielding use the same picked apps + mode.
//

import DeviceActivity

class WindDownMonitor: DeviceActivityMonitor {
    override func intervalDidStart(for activity: DeviceActivityName) {
        super.intervalDidStart(for: activity)
        WindDownShield.apply()      // evening: block the chosen apps
    }

    override func intervalDidEnd(for activity: DeviceActivityName) {
        super.intervalDidEnd(for: activity)
        WindDownShield.clear()      // morning: lift the shield
    }
}
