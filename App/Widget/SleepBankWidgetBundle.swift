//
//  SleepBankWidgetBundle.swift
//  SleepBank Widget
//
//  Extension entry point. Hosts the nap Live Activity (room here for home-screen
//  widgets later).
//

import WidgetKit
import SwiftUI

@main
struct SleepBankWidgetBundle: WidgetBundle {
    var body: some Widget {
        SleepBankHomeWidget()
        NapLiveActivityWidget()
    }
}
