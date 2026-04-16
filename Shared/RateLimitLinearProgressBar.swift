//
//  RateLimitLinearProgressBar.swift
//  Codex Switcher
//
//  Created by Codex on 2026-04-13.
//

import SwiftUI

/// Renders the compact app-side rate-limit bar using an explicit fill instead
/// of `ProgressView`.
///
/// `ProgressView` can transiently fall back to the app's accent color when the
/// system appearance changes while the app is running. This custom bar keeps the
/// 0 -> red, 50 -> orange, 100 -> green ramp stable across live theme changes.
struct RateLimitLinearProgressBar: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast

    let remainingPercent: Int?
    let height: CGFloat
    let trackOpacity: Double

    init(
        remainingPercent: Int?,
        height: CGFloat = 4,
        trackOpacity: Double = 0.25
    ) {
        self.remainingPercent = remainingPercent
        self.height = height
        self.trackOpacity = trackOpacity
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(.tertiary.opacity(trackOpacity))

                if fillFraction > 0 {
                    Capsule()
                        .fill(fillColor)
                        .frame(width: proxy.size.width * fillFraction)
                }
            }
        }
        .frame(height: height)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var fillFraction: Double {
        Double(AccountDisplayFormatter.clampedPercentValue(remainingPercent) ?? 0) / 100
    }

    private var fillColor: Color {
        let clampedPercent = AccountDisplayFormatter.clampedPercentValue(remainingPercent) ?? 0
        let components = AccountDisplayFormatter.adaptiveUsageColorComponents(
            forRemainingPercent: clampedPercent,
            colorScheme: colorScheme,
            contrast: colorSchemeContrast
        )

        return Color(
            .sRGB,
            red: components.red,
            green: components.green,
            blue: components.blue
        )
    }
}
