//
//  AlertnessDetailView.swift
//  SleepBank
//
//  Alertness detail — the full curve plus an honest explainer of what shapes it
//  (the two-process model), now with the *magnitude + duration* of each lever and
//  superscript citations to the research behind the claims (the f.lux move). The
//  evidence lives in AlertnessEvidence; the magnitudes mirror the curve's own model
//  constants (see docs/NAP_BENEFIT_EVIDENCE.md, DAYLIGHT_EVIDENCE.md, MOVEMENT_EVIDENCE.md).
//

import SwiftUI

struct AlertnessDetailView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                AlertnessCurveView()
                explainer
                references
            }
            .padding()
        }
        .navigationTitle("Alertness Score")
    }

    // MARK: - What shapes this

    private var explainer: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("What shapes this").font(.headline)
            ForEach(AlertnessEvidence.factors) { factor in
                factorRow(factor)
            }
            Text("This is a predicted rhythm to guide timing — illustrative, not a measurement. Boost sizes are directional summaries of the cited research, not personalized measurements.")
                .font(.caption).foregroundStyle(.secondary).padding(.top, 2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 20))
    }

    private func factorRow(_ f: AlertnessEvidence.Factor) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: f.icon).foregroundStyle(f.tint).frame(width: 24)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(f.title).font(.subheadline.weight(.semibold))
                    Text(f.magnitude)
                        .font(.caption2.weight(.medium))
                        .padding(.horizontal, 7).padding(.vertical, 2)
                        .background(f.tint.opacity(0.16), in: Capsule())
                        .foregroundStyle(f.tint)
                }
                claim(f)
            }
        }
    }

    /// The claim with its citation numbers rendered as a superscript.
    private func claim(_ f: AlertnessEvidence.Factor) -> Text {
        let base = Text(f.claim).font(.caption).foregroundColor(.secondary)
        guard !f.cites.isEmpty else { return base }
        let supers = Text(f.cites.map(String.init).joined(separator: ","))
            .font(.system(size: 9, weight: .bold))
            .baselineOffset(5)
            .foregroundColor(f.tint)
        return base + Text(" ").font(.caption) + supers
    }

    // MARK: - References

    private var references: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("References").font(.headline)
            ForEach(AlertnessEvidence.references) { ref in
                HStack(alignment: .top, spacing: 8) {
                    Text("\(ref.id)")
                        .font(.caption2.weight(.bold).monospacedDigit())
                        .foregroundStyle(.indigo)
                        .frame(width: 14, alignment: .trailing)
                    if let url = ref.url {
                        Link(destination: url) {
                            Text(ref.text)
                                .font(.caption2).foregroundStyle(.secondary)
                                .underline().multilineTextAlignment(.leading)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    } else {
                        Text(ref.text)
                            .font(.caption2).foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            Text("Citations point to a stable source search; verify against the primary source. Magnitudes summarized from SleepBank's evidence docs.")
                .font(.caption2).foregroundStyle(.tertiary).padding(.top, 2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 20))
    }
}
