//
//  SplashView.swift
//  Màn chào lúc mở app: gấu trúc nảy vào, tên app hiện từng chữ, bốn dấu thanh điệu được vẽ ra,
//  rồi cả màn phóng to mờ dần để lộ app. Nền trùng màu màn khởi động tĩnh nên không bị chớp.
//

import SwiftUI

struct SplashView: View {
    var onFinish: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pandaIn = false
    @State private var ringPulse = false
    @State private var lettersShown = 0
    @State private var tonesDrawn = false
    @State private var subtitleIn = false
    @State private var drift = false
    @State private var exiting = false

    private let title = Array("Bàn Phím Trung")
    /// Chữ Hán mờ trôi phía sau: (chữ, vị trí ngang, vị trí dọc, cỡ).
    private let floating: [(String, CGFloat, CGFloat, CGFloat)] = [
        ("你", 0.14, 0.16, 64), ("好", 0.84, 0.22, 52), ("学", 0.1, 0.72, 58),
        ("说", 0.86, 0.66, 70), ("中", 0.24, 0.9, 48), ("文", 0.78, 0.9, 56),
    ]

    var body: some View {
        ZStack {
            MascotMood.happy.background
                .ignoresSafeArea()
            RadialGradient(colors: [.white.opacity(0.2), .clear], center: .center, startRadius: 20, endRadius: 380)
                .ignoresSafeArea()

            GeometryReader { geo in
                ForEach(Array(floating.enumerated()), id: \.offset) { index, item in
                    Text(item.0)
                        .font(.system(size: item.3, weight: .bold))
                        .foregroundStyle(.white.opacity(0.1))
                        .position(x: geo.size.width * item.1, y: geo.size.height * item.2)
                        .offset(y: drift ? -30 - CGFloat(index % 3) * 10 : 10)
                        .rotationEffect(.degrees(index.isMultiple(of: 2) ? -8 : 8))
                }
            }
            .ignoresSafeArea()
            .accessibilityHidden(true)

            VStack(spacing: 22) {
                ZStack {
                    ForEach(0..<2, id: \.self) { ring in
                        Circle()
                            .stroke(.white.opacity(0.4), lineWidth: 2)
                            .frame(width: 170, height: 170)
                            .scaleEffect(ringPulse ? 1.9 : 0.8)
                            .opacity(ringPulse ? 0 : 0.9)
                            .animation(.easeOut(duration: 1.3).delay(Double(ring) * 0.25), value: ringPulse)
                    }
                    MascotView(mood: .happy, size: 150)
                        .shadow(color: .black.opacity(0.25), radius: 18, y: 10)
                        .scaleEffect(pandaIn ? 1 : 0.2)
                        .rotationEffect(.degrees(pandaIn ? 0 : -30))
                        .opacity(pandaIn ? 1 : 0)
                }
                .frame(height: 190)

                HStack(spacing: 0) {
                    ForEach(title.indices, id: \.self) { index in
                        let shown = index < lettersShown
                        Text(String(title[index]))
                            .font(.system(size: 36, weight: .heavy, design: .rounded))
                            .foregroundStyle(.white)
                            .opacity(shown ? 1 : 0)
                            .offset(y: shown ? 0 : 16)
                            .scaleEffect(shown ? 1 : 0.5, anchor: .bottom)
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Bàn Phím Trung")

                HStack(spacing: 16) {
                    ForEach(1...4, id: \.self) { tone in
                        ToneStroke(tone: tone)
                            .trim(from: 0, to: tonesDrawn ? 1 : 0)
                            .stroke(.white, style: StrokeStyle(lineWidth: 4.5, lineCap: .round, lineJoin: .round))
                            .frame(width: 34, height: 22)
                            .animation(.easeOut(duration: 0.4).delay(Double(tone - 1) * 0.12), value: tonesDrawn)
                    }
                }
                .accessibilityHidden(true)

                VStack(spacing: 4) {
                    Text("zhōngwén")
                        .font(.headline)
                        .foregroundStyle(.white.opacity(0.8))
                    Text("Nói tiếng Trung mỗi ngày")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.95))
                }
                .opacity(subtitleIn ? 1 : 0)
                .offset(y: subtitleIn ? 0 : 12)
            }
        }
        .scaleEffect(exiting ? 1.18 : 1)
        .opacity(exiting ? 0 : 1)
        .task { await run() }
    }

    /// Chạy trên main actor: đổi @State và gọi rung (UIKit) đều phải ở luồng chính.
    @MainActor
    private func run() async {
        if reduceMotion {
            pandaIn = true
            lettersShown = title.count
            tonesDrawn = true
            subtitleIn = true
            try? await Task.sleep(nanoseconds: 900_000_000)
            withAnimation(.easeOut(duration: 0.3)) { exiting = true }
            try? await Task.sleep(nanoseconds: 300_000_000)
            return onFinish()
        }

        withAnimation(.easeInOut(duration: 2.6)) { drift = true }
        withAnimation(.spring(response: 0.55, dampingFraction: 0.5)) { pandaIn = true }
        ringPulse = true
        try? await Task.sleep(nanoseconds: 380_000_000)
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()

        for count in 1...title.count {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.6)) { lettersShown = count }
            try? await Task.sleep(nanoseconds: 35_000_000)
        }
        tonesDrawn = true
        withAnimation(.easeOut(duration: 0.5).delay(0.25)) { subtitleIn = true }

        try? await Task.sleep(nanoseconds: 1_100_000_000)
        withAnimation(.easeIn(duration: 0.4)) { exiting = true }
        try? await Task.sleep(nanoseconds: 400_000_000)
        onFinish()
    }
}

/// Dấu thanh điệu vẽ bằng nét: ngang, lên, xuống rồi lên, rơi.
private struct ToneStroke: Shape {
    let tone: Int

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width, h = rect.height
        switch tone {
        case 1:
            path.move(to: CGPoint(x: 0, y: h * 0.3))
            path.addLine(to: CGPoint(x: w, y: h * 0.3))
        case 2:
            path.move(to: CGPoint(x: 0, y: h * 0.85))
            path.addLine(to: CGPoint(x: w, y: h * 0.15))
        case 3:
            path.move(to: CGPoint(x: 0, y: h * 0.3))
            path.addQuadCurve(to: CGPoint(x: w, y: h * 0.2), control: CGPoint(x: w * 0.4, y: h * 1.5))
        default:
            path.move(to: CGPoint(x: 0, y: h * 0.15))
            path.addLine(to: CGPoint(x: w, y: h * 0.85))
        }
        return path
    }
}
