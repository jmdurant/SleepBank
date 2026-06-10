//
//  AppearanceMode.swift
//  SleepBank
//
//  Light/Dark/System appearance preference. Default follows the system; the user can
//  pin Light or Dark in Settings. Applied via `.preferredColorScheme` at the root.
//

import SwiftUI

enum AppearanceMode: String, CaseIterable, Identifiable {
    case system, light, dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: return "System"
        case .light:  return "Light"
        case .dark:   return "Dark"
        }
    }

    /// `nil` = follow the system.
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light:  return .light
        case .dark:   return .dark
        }
    }
}
