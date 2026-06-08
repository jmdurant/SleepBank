//
//  RoutePickerView.swift
//  SleepBank
//
//  Thin SwiftUI wrapper over AVRoutePickerView — the system AirPlay/output
//  picker. Tapping it lets the user send the relaxing sound to the phone speaker,
//  AirPods, or any AirPlay device, using the same picker as Apple's own apps.
//

import SwiftUI
import AVKit

struct RoutePickerView: UIViewRepresentable {
    func makeUIView(context: Context) -> AVRoutePickerView {
        let picker = AVRoutePickerView()
        picker.prioritizesVideoDevices = false
        picker.tintColor = .systemIndigo
        picker.activeTintColor = .systemIndigo
        return picker
    }

    func updateUIView(_ uiView: AVRoutePickerView, context: Context) {}
}
