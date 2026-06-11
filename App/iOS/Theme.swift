//
//  Theme.swift
//  SleepBank
//
//  The app palette — ocean blues with a soft-gold accent, matching the beach/
//  breathing theme. Replaces the old purple/indigo + orange.
//

import SwiftUI

extension Color {
    /// Primary accent (was indigo/purple).
    static let ocean = Color(red: 0.302, green: 0.651, blue: 0.800)   // #4DA6CC
    /// Deeper blue for gradients/depth.
    static let tide  = Color(red: 0.122, green: 0.431, blue: 0.549)   // #1F6E8C
    /// Warm accent — sun / daylight / energy (was orange/yellow).
    static let sand  = Color(red: 0.886, green: 0.761, blue: 0.459)   // #E2C275
    /// Cool "good / energized" accent.
    static let aqua  = Color(red: 0.357, green: 0.753, blue: 0.745)   // #5BC0BE
}

// Enable the leading-dot form in `some ShapeStyle` contexts (e.g. .foregroundStyle(.ocean)).
extension ShapeStyle where Self == Color {
    static var ocean: Color { Color.ocean }
    static var tide:  Color { Color.tide }
    static var sand:  Color { Color.sand }
    static var aqua:  Color { Color.aqua }
}
