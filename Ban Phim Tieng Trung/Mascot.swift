import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// Tâm trạng của gấu trúc, suy ra từ chuỗi ngày luyện nói.
enum MascotMood: String, CaseIterable, Identifiable {
    case happy, sad, angry, crying

    var id: String { rawValue }

    init(_ summary: StreakStore.Summary) {
        if summary.activeToday {
            // Hôm nay đã giữ được chuỗi.
            self = .happy
        } else if summary.usedGrace {
            // Hôm qua đã nghỉ, hôm nay không nói nữa là đứt.
            self = .angry
        } else if summary.streak > 0 {
            self = .sad
        } else {
            // Chuỗi về 0: từng học rồi bỏ thì khóc, người mới thì vui vẻ chào.
            self = summary.totalDays > 0 ? .crying : .happy
        }
    }

    var title: String {
        switch self {
        case .happy: "Vui"
        case .sad: "Buồn"
        case .angry: "Giận"
        case .crying: "Khóc"
        }
    }

    /// Lời gấu trúc nói với người học.
    func message(_ summary: StreakStore.Summary) -> String {
        switch self {
        case .happy:
            if summary.doneToday {
                "Giỏi quá! Hôm nay xong mục tiêu rồi."
            } else if summary.activeToday {
                "Chuỗi hôm nay giữ được rồi! Thêm \(summary.remaining) câu là xong mục tiêu."
            } else {
                "Chào bạn! Nói câu tiếng Trung đầu tiên cùng mình nhé."
            }
        case .sad:
            "Hôm nay chưa đủ câu… nói thêm \(summary.toKeepStreak) câu để giữ chuỗi nhé."
        case .angry:
            "Hôm qua bạn bỏ mình đó! Hôm nay không nói là mất chuỗi."
        case .crying:
            "Chuỗi đứt mất rồi… Mình bắt đầu lại nhé?"
        }
    }

    var background: Color {
        switch self {
        case .happy: Color(red: 0.86, green: 0.17, blue: 0.16)
        case .sad: PandaDrawing.rgb(127, 143, 171)
        case .angry: PandaDrawing.rgb(90, 21, 18)
        case .crying: PandaDrawing.rgb(47, 127, 209)
        }
    }

    /// Tên bộ icon phụ trong Assets; nil là icon chính (gấu vui).
    var iconName: String? {
        switch self {
        case .happy: nil
        case .sad: "AppIcon-Sad"
        case .angry: "AppIcon-Angry"
        case .crying: "AppIcon-Crying"
        }
    }
}

/// Gấu trúc vẽ trên khung 200×200. Icon app cũng render từ chính bản vẽ này,
/// nên trong app và ngoài màn hình chính luôn khớp nhau, phóng to không vỡ.
struct PandaDrawing {
    var mood: MascotMood
    /// Bo góc nền. Icon app để 0 vì iOS tự bo.
    var cornerRadius: CGFloat = 46

    static func rgb(_ red: Int, _ green: Int, _ blue: Int) -> Color {
        Color(red: Double(red) / 255, green: Double(green) / 255, blue: Double(blue) / 255)
    }

    private let ink = rgb(38, 34, 31)
    private let mouth = rgb(58, 31, 28)
    private let tongue = rgb(255, 122, 138)
    private let cheek = rgb(255, 179, 186)
    private let shade = rgb(227, 218, 209)
    private let tear = rgb(79, 182, 255)

    func draw(in context: GraphicsContext, size: CGSize) {
        var ctx = context
        ctx.scaleBy(x: size.width / 200, y: size.height / 200)
        ctx.fill(Path(roundedRect: CGRect(x: 0, y: 0, width: 200, height: 200),
                      cornerRadius: cornerRadius, style: .continuous),
                 with: .color(mood.background))
        drawHead(ctx)
        switch mood {
        case .happy: drawHappy(ctx)
        case .sad: drawSad(ctx)
        case .angry: drawAngry(ctx)
        case .crying: drawCrying(ctx)
        }
    }

    // MARK: - Phần chung

    private func drawHead(_ ctx: GraphicsContext) {
        ctx.fill(ellipse(50, 56, 24, 24), with: .color(ink))
        ctx.fill(ellipse(150, 56, 24, 24), with: .color(ink))
        // Viền sẫm dưới cằm cho mặt có khối.
        ctx.fill(ellipse(100, 111, 70, 62), with: .color(shade))
        ctx.fill(ellipse(100, 106, 70, 58), with: .color(.white))
        for (x, angle) in [(CGFloat(68), 30.0), (132, -30)] {
            var patch = ctx
            patch.translateBy(x: x, y: 104)
            patch.rotate(by: .degrees(angle))
            patch.fill(ellipse(0, 0, 19, 24), with: .color(ink))
        }
    }

    private func drawNose(_ ctx: GraphicsContext) {
        var path = Path()
        path.move(to: CGPoint(x: 91, y: 123))
        path.addQuadCurve(to: CGPoint(x: 109, y: 123), control: CGPoint(x: 100, y: 118))
        path.addQuadCurve(to: CGPoint(x: 100, y: 133), control: CGPoint(x: 109, y: 131))
        path.addQuadCurve(to: CGPoint(x: 91, y: 123), control: CGPoint(x: 91, y: 131))
        ctx.fill(path, with: .color(ink))
    }

    private func drawEye(_ ctx: GraphicsContext, _ x: CGFloat, _ y: CGFloat, pupilDrop: CGFloat) {
        ctx.fill(ellipse(x, y, 11, 11), with: .color(.white))
        ctx.fill(ellipse(x, y + pupilDrop, 6, 6), with: .color(ink))
        ctx.fill(ellipse(x + 2.5, y + pupilDrop - 2.5, 2.2, 2.2), with: .color(.white))
    }

    /// Lông mày buồn: đầu trong nhướng lên.
    private func drawWorriedBrows(_ ctx: GraphicsContext) {
        stroke(ctx, line((52, 80), (78, 71)), ink, 5)
        stroke(ctx, line((122, 71), (148, 80)), ink, 5)
    }

    // MARK: - Từng tâm trạng

    private func drawHappy(_ ctx: GraphicsContext) {
        stroke(ctx, quad((59, 103), (70, 89), (81, 103)), .white, 5.5)
        stroke(ctx, quad((119, 103), (130, 89), (141, 103)), .white, 5.5)
        ctx.fill(ellipse(46, 130, 9, 6), with: .color(cheek))
        ctx.fill(ellipse(154, 130, 9, 6), with: .color(cheek))
        drawNose(ctx)

        var open = Path()
        open.move(to: CGPoint(x: 81, y: 139))
        open.addLine(to: CGPoint(x: 119, y: 139))
        open.addQuadCurve(to: CGPoint(x: 100, y: 164), control: CGPoint(x: 119, y: 164))
        open.addQuadCurve(to: CGPoint(x: 81, y: 139), control: CGPoint(x: 81, y: 164))
        ctx.fill(open, with: .color(mouth))
        ctx.fill(tonguePath(left: 89, right: 111, top: 146, base: 156, bottom: 164), with: .color(tongue))
    }

    private func drawSad(_ ctx: GraphicsContext) {
        drawEye(ctx, 70, 101, pupilDrop: 3)
        drawEye(ctx, 130, 101, pupilDrop: 3)
        drawWorriedBrows(ctx)
        drawNose(ctx)
        stroke(ctx, quad((87, 149), (100, 139), (113, 149)), ink, 5)
        ctx.fill(drop(x: 150, top: 118, bottom: 132), with: .color(PandaDrawing.rgb(110, 198, 255)))
    }

    private func drawAngry(_ ctx: GraphicsContext) {
        // Mí mắt xiên xuống phía trong: cắt nửa trên của mắt theo đường chéo.
        let eyes: [(CGFloat, [(CGFloat, CGFloat)])] = [
            (70, [(50, 93), (90, 105), (90, 130), (50, 130)]),
            (130, [(110, 105), (150, 93), (150, 130), (110, 130)]),
        ]
        for (x, cut) in eyes {
            var eye = ctx
            eye.clip(to: polygon(cut))
            drawEye(eye, x, 102, pupilDrop: 2)
        }
        stroke(ctx, line((46, 76), (86, 90)), ink, 7)
        stroke(ctx, line((114, 90), (154, 76)), ink, 7)
        drawNose(ctx)

        // Nghiến răng.
        ctx.fill(Path(roundedRect: CGRect(x: 80, y: 140, width: 40, height: 18), cornerRadius: 7), with: .color(mouth))
        ctx.fill(Path(roundedRect: CGRect(x: 84, y: 143, width: 32, height: 12), cornerRadius: 4), with: .color(.white))
        var teeth = line((84, 149), (116, 149))
        for x in [92.5, 100, 107.5] {
            teeth.move(to: CGPoint(x: x, y: 143))
            teeth.addLine(to: CGPoint(x: x, y: 155))
        }
        ctx.stroke(teeth, with: .color(mouth), lineWidth: 2)

        // Dấu nổi gân trên đầu.
        var vein = Path()
        let corners: [((CGFloat, CGFloat), (CGFloat, CGFloat), (CGFloat, CGFloat))] = [
            ((-11, -3), (-3, -3), (-3, -11)), ((3, -11), (3, -3), (11, -3)),
            ((11, 3), (3, 3), (3, 11)), ((-3, 11), (-3, 3), (-11, 3)),
        ]
        for (from, control, to) in corners {
            vein.addPath(quad((100 + from.0, 24 + from.1), (100 + control.0, 24 + control.1), (100 + to.0, 24 + to.1)))
        }
        stroke(ctx, vein, PandaDrawing.rgb(255, 197, 61), 4.5)
    }

    private func drawCrying(_ ctx: GraphicsContext) {
        drawWorriedBrows(ctx)
        stroke(ctx, quad((64, 109), (58, 132), (63, 158)), tear, 10)
        stroke(ctx, quad((136, 109), (142, 132), (137, 158)), tear, 10)
        // Mắt nhắm tịt: > <
        stroke(ctx, line((61, 93), (79, 101), (61, 109)), .white, 5.5)
        stroke(ctx, line((139, 93), (121, 101), (139, 109)), .white, 5.5)
        drawNose(ctx)
        ctx.fill(drop(x: 63, top: 170, bottom: 181), with: .color(tear))
        ctx.fill(drop(x: 137, top: 170, bottom: 181), with: .color(tear))
        ctx.fill(ellipse(100, 152, 16, 13), with: .color(mouth))
        ctx.fill(tonguePath(left: 89, right: 111, top: 151, base: 159, bottom: 165), with: .color(tongue))
    }

    // MARK: - Hình cơ bản

    private func ellipse(_ x: CGFloat, _ y: CGFloat, _ rx: CGFloat, _ ry: CGFloat) -> Path {
        Path(ellipseIn: CGRect(x: x - rx, y: y - ry, width: rx * 2, height: ry * 2))
    }

    private func line(_ points: (CGFloat, CGFloat)...) -> Path {
        var path = Path()
        path.addLines(points.map { CGPoint(x: $0.0, y: $0.1) })
        return path
    }

    private func polygon(_ points: [(CGFloat, CGFloat)]) -> Path {
        var path = line()
        path.addLines(points.map { CGPoint(x: $0.0, y: $0.1) })
        path.closeSubpath()
        return path
    }

    private func quad(_ from: (CGFloat, CGFloat), _ control: (CGFloat, CGFloat), _ to: (CGFloat, CGFloat)) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: from.0, y: from.1))
        path.addQuadCurve(to: CGPoint(x: to.0, y: to.1), control: CGPoint(x: control.0, y: control.1))
        return path
    }

    /// Giọt nước: nhọn ở trên, tròn ở dưới.
    private func drop(x: CGFloat, top: CGFloat, bottom: CGFloat) -> Path {
        let belly = top + (bottom - top) * 0.64
        var path = Path()
        path.move(to: CGPoint(x: x, y: top))
        path.addQuadCurve(to: CGPoint(x: x, y: bottom), control: CGPoint(x: x + 5, y: belly))
        path.addQuadCurve(to: CGPoint(x: x, y: top), control: CGPoint(x: x - 5, y: belly))
        return path
    }

    /// Lưỡi nằm đáy miệng: mép trên cong lồi, đáy tròn theo miệng.
    private func tonguePath(left: CGFloat, right: CGFloat, top: CGFloat, base: CGFloat, bottom: CGFloat) -> Path {
        let mid = (left + right) / 2
        var path = Path()
        path.move(to: CGPoint(x: left, y: base))
        path.addQuadCurve(to: CGPoint(x: right, y: base), control: CGPoint(x: mid, y: top))
        path.addQuadCurve(to: CGPoint(x: mid, y: bottom), control: CGPoint(x: right - 4, y: bottom))
        path.addQuadCurve(to: CGPoint(x: left, y: base), control: CGPoint(x: left + 4, y: bottom))
        return path
    }

    private func stroke(_ ctx: GraphicsContext, _ path: Path, _ color: Color, _ width: CGFloat) {
        ctx.stroke(path, with: .color(color),
                   style: StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round))
    }
}

/// Gấu trúc có cử động nhẹ theo tâm trạng: vui thì nhún, giận thì run, buồn thì lắc lư, khóc thì nấc.
struct MascotView: View {
    var mood: MascotMood
    var size: CGFloat = 64

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var phase = false

    var body: some View {
        ZStack {
            Canvas { context, canvasSize in
                PandaDrawing(mood: mood, cornerRadius: 46).draw(in: context, size: canvasSize)
            }
            .id(mood)
            .transition(.scale(scale: 0.6).combined(with: .opacity))
        }
        .frame(width: size, height: size)
        .offset(y: offset)
        .rotationEffect(.degrees(rotation), anchor: .bottom)
        .animation(.spring(response: 0.4, dampingFraction: 0.55), value: mood)
        .accessibilityElement()
        .accessibilityLabel("Gấu trúc đang \(mood.title.lowercased())")
        .onAppear { startMotion() }
        .onDisappear { phase = false }
        .onChange(of: mood) { _ in startMotion() }
    }

    private var offset: CGFloat {
        switch mood {
        case .happy: phase ? -size * 0.05 : 0
        case .crying: phase ? size * 0.02 : 0
        case .sad, .angry: 0
        }
    }

    private var rotation: Double {
        switch mood {
        case .angry: phase ? 2.5 : -2.5
        case .sad: phase ? 2 : -2
        case .happy, .crying: 0
        }
    }

    private var motion: Animation {
        switch mood {
        case .happy: .easeInOut(duration: 0.5)
        case .sad: .easeInOut(duration: 1.6)
        case .angry: .easeInOut(duration: 0.09)
        case .crying: .easeInOut(duration: 0.3)
        }
    }

    private func startMotion() {
        // Cùng mẹo với FlameView: đặt về false rồi mới bật ở nhịp sau, không thì animation không chạy lại.
        phase = false
        guard !reduceMotion else { return }
        let animation = motion
        DispatchQueue.main.async {
            withAnimation(animation.repeatForever(autoreverses: true)) { phase = true }
        }
    }
}

/// Gấu trúc kèm lời nhắn, dùng ở đầu màn Chuỗi ngày.
struct MascotBubble: View {
    var summary: StreakStore.Summary
    var size: CGFloat = 76

    var body: some View {
        let mood = MascotMood(summary)
        HStack(spacing: 12) {
            MascotView(mood: mood, size: size)
            Text(mood.message(summary))
                .font(.subheadline.weight(.medium))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(mood.background.opacity(0.14)))
                .frame(maxWidth: .infinity, alignment: .leading)
                .animation(.easeInOut, value: mood)
        }
    }
}

#if canImport(UIKit)
/// Icon ngoài màn hình chính đổi theo tâm trạng gấu trúc.
/// iOS chỉ cho đổi lúc app đang mở và lần nào đổi cũng hiện một thông báo nhỏ,
/// nên chỉ đổi khi tâm trạng thật sự khác icon đang dùng.
enum MascotIcon {
    static let followsMoodKey = "iconFollowsMood"

    static var followsMood: Bool {
        get { SharedSettings.store.object(forKey: followsMoodKey) as? Bool ?? true }
        set { SharedSettings.store.set(newValue, forKey: followsMoodKey) }
    }

    static func sync() {
        // Nhật ký chuỗi có thể ghi từ luồng âm thanh; UIApplication chỉ dùng trên luồng chính.
        // Đợi một nhịp: đổi icon ngay lúc app vừa bật lên hay bị iOS từ chối.
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 500_000_000)
            let app = UIApplication.shared
            guard app.supportsAlternateIcons, app.applicationState == .active else { return }
            let wanted = followsMood ? MascotMood(StreakStore.summary()).iconName : nil
            guard app.alternateIconName != wanted else { return }
            app.setAlternateIconName(wanted) { error in
                if let error { print("Không đổi được icon: \(error.localizedDescription)") }
            }
        }
    }
}
#endif

#Preview {
    VStack(spacing: 20) {
        HStack(spacing: 16) {
            ForEach(MascotMood.allCases) { MascotView(mood: $0, size: 72) }
        }
    }
    .padding()
}
