//
//  BeachSceneView.swift
//  SleepBank
//
//  A calming, looping beach scene drawn entirely in a Canvas (no image assets) —
//  the view from the sand looking out to the horizon, with waves gently lapping the
//  shore. Adapts to appearance: light = clear blue day sky; dark = night sky with a
//  moon and twinkling stars over the water. Used behind the breathing circle.
//

import SwiftUI

struct BeachSceneView: View {
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        TimelineView(.animation) { tl in
            Canvas { ctx, size in
                draw(&ctx, size: size, t: tl.date.timeIntervalSinceReferenceDate, night: scheme == .dark)
            }
        }
        .ignoresSafeArea()
    }

    // MARK: - Layout (fractions of height)

    private let horizonF = 0.56     // sky / sea boundary
    private let shoreF = 0.80       // sea / sand boundary

    private struct Star { let x, y, size, phase: Double }
    private static let stars: [Star] = {
        var seed: UInt64 = 0xB16B00B5
        func rnd() -> Double { seed = seed &* 6364136223846793005 &+ 1442695040888963407
            return Double(seed >> 11) / Double(UInt64(1) << 53) }
        return (0..<70).map { _ in Star(x: rnd(), y: rnd() * 0.52, size: 0.6 + rnd() * 1.8, phase: rnd() * 6.28) }
    }()

    // MARK: - Draw

    private func draw(_ ctx: inout GraphicsContext, size: CGSize, t: Double, night: Bool) {
        let w = size.width, h = size.height
        let horizon = h * horizonF, shore = h * shoreF

        // Sky
        let sky = night
            ? [Color(red: 0.04, green: 0.05, blue: 0.16), Color(red: 0.11, green: 0.13, blue: 0.30)]
            : [Color(red: 0.36, green: 0.66, blue: 0.92), Color(red: 0.77, green: 0.89, blue: 0.98)]
        ctx.fill(Path(CGRect(x: 0, y: 0, width: w, height: horizon)),
                 with: .linearGradient(Gradient(colors: sky),
                                       startPoint: .zero, endPoint: CGPoint(x: 0, y: horizon)))

        // The sun/moon itself is the breathing circle (drawn by BreathingGuideView and
        // animated to this spot), so here we only draw the night stars.
        if night {
            for s in Self.stars {
                let tw = 0.35 + 0.65 * abs(sin(t * 1.3 + s.phase))
                let r = s.size
                ctx.fill(Path(ellipseIn: CGRect(x: s.x * w, y: s.y * horizon, width: r, height: r)),
                         with: .color(.white.opacity(tw)))
            }
        }

        // Sea
        let sea = night
            ? [Color(red: 0.06, green: 0.09, blue: 0.22), Color(red: 0.12, green: 0.18, blue: 0.32)]
            : [Color(red: 0.16, green: 0.50, blue: 0.66), Color(red: 0.42, green: 0.74, blue: 0.80)]
        ctx.fill(Path(CGRect(x: 0, y: horizon, width: w, height: shore - horizon)),
                 with: .linearGradient(Gradient(colors: sea),
                                       startPoint: CGPoint(x: 0, y: horizon), endPoint: CGPoint(x: 0, y: shore)))

        // Moon/sun glint reflection on the water, under where the orb sits.
        let glintX = w * 0.74
        ctx.fill(Path(CGRect(x: glintX - 22, y: horizon, width: 44, height: shore - horizon)),
                 with: .linearGradient(Gradient(colors: [Color.white.opacity(night ? 0.10 : 0.18), .clear]),
                                       startPoint: CGPoint(x: 0, y: horizon), endPoint: CGPoint(x: 0, y: shore)))

        // Gentle wave lines across the sea
        let waveColor: Color = night ? Color(white: 0.8) : .white
        for i in 0..<3 {
            let baseY = horizon + (shore - horizon) * (0.35 + 0.2 * Double(i))
            let amp = 2.5 + Double(i) * 1.5
            let speed = 0.5 + Double(i) * 0.25
            let freq = 0.012 + Double(i) * 0.004
            var p = Path()
            p.move(to: CGPoint(x: 0, y: baseY))
            stride(from: 0.0, through: Double(w), by: 8).forEach { x in
                let y = baseY + amp * sin(x * freq + t * speed + Double(i))
                p.addLine(to: CGPoint(x: x, y: y))
            }
            ctx.stroke(p, with: .color(waveColor.opacity(0.18)), lineWidth: 1.2)
        }

        // Sand
        let sand = night
            ? [Color(red: 0.17, green: 0.16, blue: 0.21), Color(red: 0.10, green: 0.09, blue: 0.13)]
            : [Color(red: 0.87, green: 0.80, blue: 0.65), Color(red: 0.77, green: 0.68, blue: 0.52)]
        ctx.fill(Path(CGRect(x: 0, y: shore, width: w, height: h - shore)),
                 with: .linearGradient(Gradient(colors: sand),
                                       startPoint: CGPoint(x: 0, y: shore), endPoint: CGPoint(x: 0, y: h)))

        // The lapping foam line where the water meets the sand — slowly advances and
        // recedes (the "lapping") and ripples along its length.
        let lap = sin(t * 0.45) * (h * 0.012)          // slow in/out
        let foamY = shore + lap
        var foam = Path()
        foam.move(to: CGPoint(x: 0, y: foamY))
        stride(from: 0.0, through: Double(w), by: 6).forEach { x in
            let y = foamY + 3.0 * sin(x * 0.02 + t * 0.9)
            foam.addLine(to: CGPoint(x: x, y: y))
        }
        // close down into the sand to fill a thin wet band
        foam.addLine(to: CGPoint(x: w, y: foamY + 16))
        foam.addLine(to: CGPoint(x: 0, y: foamY + 16))
        foam.closeSubpath()
        ctx.fill(foam, with: .color((night ? Color(white: 0.7) : .white).opacity(0.22)))
    }
}
