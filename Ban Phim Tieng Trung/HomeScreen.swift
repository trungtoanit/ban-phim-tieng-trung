//
//  HomeScreen.swift
//  Màn hình chính theo phong cách iOS mới (kính mờ): widget, icon bóng kính có số đỏ, dock ở đáy.
//  Mở tính năng phóng ra từ icon; nút "‹ Trang chủ" cùng kiểu kính trên thanh điều hướng để quay về.
//

import SwiftUI

extension AppTab {
    var title: String {
        switch self {
        case .practice: "Luyện nói"
        case .conversation: "Hội thoại"
        case .vocabulary: "Từ vựng"
        case .sounds: "Phát âm"
        case .mistakes: "Sửa lỗi"
        case .keyboard: "Bàn phím"
        case .about: "Giới thiệu"
        case .interpreter: "Phiên dịch"
        }
    }

    var symbol: String {
        switch self {
        case .practice: "text.bubble.fill"
        case .conversation: "bubble.left.and.bubble.right.fill"
        case .vocabulary: "rectangle.stack.fill"
        case .sounds: "character.book.closed.fill"
        case .mistakes: "exclamationmark.bubble.fill"
        case .keyboard: "keyboard.fill"
        case .about: "person.crop.circle.fill"
        case .interpreter: "translate"
        }
    }

    /// Hai màu nền icon (trên, dưới).
    var colors: [Color] {
        switch self {
        case .practice: [Color(red: 1, green: 0.45, blue: 0.38), Color(red: 0.86, green: 0.14, blue: 0.16)]
        case .conversation: [Color(red: 0.42, green: 0.9, blue: 0.5), Color(red: 0.1, green: 0.66, blue: 0.32)]
        case .vocabulary: [Color(red: 1, green: 0.8, blue: 0.3), Color(red: 0.98, green: 0.5, blue: 0.1)]
        case .sounds: [Color(red: 0.74, green: 0.55, blue: 1), Color(red: 0.44, green: 0.24, blue: 0.92)]
        case .mistakes: [Color(red: 1, green: 0.48, blue: 0.64), Color(red: 0.88, green: 0.18, blue: 0.44)]
        case .keyboard: [Color(red: 0.66, green: 0.7, blue: 0.78), Color(red: 0.36, green: 0.4, blue: 0.48)]
        case .about: [Color(red: 0.36, green: 0.74, blue: 1), Color(red: 0.12, green: 0.44, blue: 0.94)]
        case .interpreter: [Color(red: 0.3, green: 0.88, blue: 0.84), Color(red: 0.05, green: 0.58, blue: 0.64)]
        }
    }

    /// Bốn tính năng dùng nhiều nhất nằm ở dock, còn lại trên màn hình.
    static let dock: [AppTab] = [.practice, .conversation, .vocabulary, .sounds]
    static let grid: [AppTab] = [.interpreter, .mistakes, .keyboard, .about]
}

// MARK: - Nút về trang chủ

private struct GoHomeKey: EnvironmentKey {
    static let defaultValue: (() -> Void)? = nil
}

extension EnvironmentValues {
    /// Về màn hình chính. Nil khi màn hình không được mở từ màn hình chính.
    var goHome: (() -> Void)? {
        get { self[GoHomeKey.self] }
        set { self[GoHomeKey.self] = newValue }
    }
}

/// Nút "‹ Trang chủ" dạng viên kính ở góc trái thanh điều hướng, cho trang đầu của mỗi tính năng.
private struct HomeBackButton: ViewModifier {
    @Environment(\.goHome) private var goHome

    func body(content: Content) -> some View {
        content.toolbar {
            if let goHome {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: goHome) {
                        HStack(spacing: 6) {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 13, weight: .bold))
                            Image(systemName: "square.grid.2x2.fill")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(
                                    LinearGradient(colors: AppTab.practice.colors, startPoint: .top, endPoint: .bottom)
                                )
                            Text("Trang chủ")
                                .font(.subheadline.weight(.semibold))
                        }
                        .foregroundStyle(.primary)
                        .padding(.leading, 11)
                        .padding(.trailing, 14)
                        .padding(.vertical, 8)
                        .glassCapsule()
                    }
                    .buttonStyle(PressableStyle())
                    .accessibilityLabel("Về trang chủ")
                }
            }
        }
    }
}

extension View {
    func homeBackButton() -> some View {
        modifier(HomeBackButton())
    }
}

// MARK: - Kính mờ

private struct GlassBackground<S: InsettableShape>: ViewModifier {
    let shape: S
    var tint: Color = .clear
    /// Kính thật (làm nhoè phần phía sau) rất tốn khi nền phía sau thay đổi. Thẻ lớn đặt trên nền đã
    /// nhoè sẵn thì dùng lớp trắng trong suốt: nhìn gần như y hệt mà nhẹ hơn nhiều.
    var material = true

    func body(content: Content) -> some View {
        content
            .background {
                if material {
                    shape.fill(.ultraThinMaterial)
                } else {
                    shape.fill(.white.opacity(0.1))
                }
            }
            .background(shape.fill(tint))
            // Viền phản quang: sáng ở góc trên trái, nhạt dần xuống dưới.
            .overlay(
                shape.strokeBorder(
                    LinearGradient(colors: [.white.opacity(0.75), .white.opacity(0.12), .white.opacity(0.35)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing),
                    lineWidth: 1
                )
            )
            .shadow(color: .black.opacity(material ? 0.12 : 0.08), radius: material ? 10 : 6, y: 4)
    }
}

extension View {
    func glassCapsule(tint: Color = .clear) -> some View {
        modifier(GlassBackground(shape: Capsule(), tint: tint))
    }

    func glassCard(cornerRadius: CGFloat, tint: Color = .clear) -> some View {
        modifier(GlassBackground(shape: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous),
                                 tint: tint, material: false))
    }
}

/// Nhấn xuống thì lún nhẹ, như icon trên màn hình iPhone.
struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.9 : 1)
            .brightness(configuration.isPressed ? -0.06 : 0)
            .animation(.spring(response: 0.25, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

// MARK: - Nền

/// Nền mảng màu tươi nhoè mờ: dùng cho màn hình chính và các màn chơi.
///
/// Vẽ một lần rồi giữ nguyên thành ảnh (`drawingGroup`). Bản trước cho các mảng màu trôi liên tục:
/// đẹp nhưng máy phải làm nhoè lại cả màn hình ở mọi khung hình, kéo theo cả các lớp kính phía trên.
struct VividWallpaper: View {
    var body: some View {
        Canvas { context, size in
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color(red: 0.07, green: 0.05, blue: 0.14)))
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            context.drawLayer { layer in
                layer.addFilter(.blur(radius: 80))
                for (color, diameter, dx, dy) in Self.blobs {
                    let rect = CGRect(x: center.x + dx - diameter / 2, y: center.y + dy - diameter / 2,
                                      width: diameter, height: diameter)
                    layer.fill(Path(ellipseIn: rect), with: .color(color.opacity(0.75)))
                }
            }
            // Lớp tối nhẹ ở đáy cho chữ trắng dễ đọc.
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .linearGradient(
                Gradient(colors: [.clear, .black.opacity(0.35)]),
                startPoint: center, endPoint: CGPoint(x: center.x, y: size.height)
            ))
        }
        .drawingGroup()
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private static let blobs: [(Color, CGFloat, CGFloat, CGFloat)] = [
        (Color(red: 1, green: 0.3, blue: 0.28), 460, -150, -270),
        (Color(red: 1, green: 0.62, blue: 0.2), 340, 150, -100),
        (Color(red: 0.52, green: 0.3, blue: 1), 480, 150, 280),
        (Color(red: 0.95, green: 0.2, blue: 0.55), 360, -130, 200),
    ]
}

// MARK: - Màn hình chính

/// Khung của từng icon, để mở tính năng phóng ra đúng từ icon đó.
///
/// Là lớp thường, không phát thông báo thay đổi: ghi vị trí lúc cuộn không làm màn hình vẽ lại.
/// (Bản trước dùng PreferenceKey, cuộn tới đâu cả màn hình chính vẽ lại tới đó.)
final class IconFrameRegistry {
    var frames: [AppTab: CGRect] = [:]
}

struct HomeScreenView: View {
    let badges: [AppTab: Int]
    let streak: StreakStore.Summary
    let frames: IconFrameRegistry
    let onOpen: (AppTab) -> Void

    @State private var appeared = false

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 10), count: 4)

    var body: some View {
        // Khoá cứng khung theo đúng kích thước màn hình: không thành phần nào được đẩy bố cục tràn ra ngoài.
        GeometryReader { geo in
            VStack(spacing: 0) {
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 18) {
                        MicLiveBanner { onOpen(.keyboard) }
                        dateHeader
                        streakWidget
                        HStack(spacing: 14) {
                            vocabularyWidget
                            mistakesWidget
                        }
                        LazyVGrid(columns: columns, spacing: 20) {
                            ForEach(Array(AppTab.grid.enumerated()), id: \.element) { index, app in
                                Group {
                                    if app == .keyboard {
                                        KeyboardAppIcon(frames: frames) { onOpen(app) }
                                    } else {
                                        HomeAppIcon(app: app, badge: badges[app] ?? 0, frames: frames) { onOpen(app) }
                                    }
                                }
                                .appear(appeared, delay: 0.18 + 0.05 * Double(index))
                            }
                        }
                        .padding(.top, 4)
                    }
                    .frame(width: max(geo.size.width - 40, 0), alignment: .leading)
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                    .padding(.bottom, 20)
                }
                .frame(width: geo.size.width)

                dock
                    .frame(width: max(geo.size.width - 24, 0))
                    .padding(.bottom, 6)
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        // Nền nằm ngoài khung đã khoá để vẫn phủ kín dưới thanh trạng thái và thanh home.
        .background(wallpaper)
        .onAppear {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.82)) { appeared = true }
        }
    }

    // MARK: Nền

    private var wallpaper: some View {
        VividWallpaper()
    }

    // MARK: Widget

    private var dateHeader: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(Self.dateFormatter.string(from: Date()).capitalizedFirst)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white.opacity(0.85))
            Text("Nói tiếng Trung mỗi ngày")
                .font(.system(size: 30, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
        }
        .appear(appeared, delay: 0)
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "vi_VN")
        formatter.dateFormat = "EEEE, d 'tháng' M"
        return formatter
    }()

    /// Chuỗi ngày: gấu trúc, số ngày liên tiếp, vòng tiến độ câu hôm nay. Chạm để mở Hội thoại.
    private var streakWidget: some View {
        Button { onOpen(.conversation) } label: {
            HStack(spacing: 14) {
                MascotView(mood: MascotMood(streak), size: 72, animated: false)
                VStack(alignment: .leading, spacing: 4) {
                    Label("Chuỗi ngày", systemImage: "flame.fill")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(streak.streak > 0 ? .orange : .white.opacity(0.6))
                    HStack(alignment: .firstTextBaseline, spacing: 5) {
                        Text("\(streak.streak)")
                            .font(.system(size: 36, weight: .heavy, design: .rounded))
                            .contentTransition(.numericText())
                        Text("ngày")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.75))
                    }
                    Text(streak.doneToday ? "Xong mục tiêu hôm nay 👏" : "Còn \(streak.remaining) câu hôm nay")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.8))
                }
                Spacer(minLength: 0)
                ZStack {
                    Circle().stroke(.white.opacity(0.18), lineWidth: 7)
                    Circle()
                        .trim(from: 0, to: streak.progress)
                        .stroke(streak.doneToday ? Color.green : .white, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    VStack(spacing: 0) {
                        Text("\(streak.today.sentences)")
                            .font(.headline.weight(.bold).monospacedDigit())
                        Text("/\(streak.goal)")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.7))
                    }
                }
                .frame(width: 64, height: 64)
            }
            .foregroundStyle(.white)
            .padding(16)
            .glassCard(cornerRadius: 28, tint: .white.opacity(0.04))
            .environment(\.colorScheme, .dark)
        }
        .buttonStyle(PressableStyle())
        .appear(appeared, delay: 0.05)
    }

    private var vocabularyWidget: some View {
        VocabularyWidget { value, detail in
            smallWidget(app: .vocabulary, value: value, caption: "từ đang học", detail: detail)
        }
        .appear(appeared, delay: 0.1)
    }

    private var mistakesWidget: some View {
        let count = badges[.mistakes] ?? 0
        return smallWidget(app: .mistakes, value: "\(count)", caption: "lỗi phát âm",
                           detail: count == 0 ? "Chưa có lỗi nào" : "Chạm để luyện lại")
            .appear(appeared, delay: 0.14)
    }

    private func smallWidget(app: AppTab, value: String, caption: String, detail: String) -> some View {
        Button { onOpen(app) } label: {
            VStack(alignment: .leading, spacing: 6) {
                Image(systemName: app.symbol)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 30, height: 30)
                    .background(RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(LinearGradient(colors: app.colors, startPoint: .top, endPoint: .bottom)))
                Spacer(minLength: 0)
                Text(value)
                    .font(.system(size: 30, weight: .heavy, design: .rounded))
                    .contentTransition(.numericText())
                Text(caption)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.85))
                Text(detail)
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.6))
                    .lineLimit(1)
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, minHeight: 138, alignment: .leading)
            .padding(14)
            .glassCard(cornerRadius: 24, tint: .white.opacity(0.04))
            .environment(\.colorScheme, .dark)
        }
        .buttonStyle(PressableStyle())
    }

    // MARK: Dock

    private var dock: some View {
        HStack(spacing: 0) {
            ForEach(Array(AppTab.dock.enumerated()), id: \.element) { index, app in
                HomeAppIcon(app: app, badge: badges[app] ?? 0, showsLabel: false, frames: frames) { onOpen(app) }
                    .frame(maxWidth: .infinity)
                    .appear(appeared, delay: 0.2 + 0.04 * Double(index))
            }
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 6)
        .glassCard(cornerRadius: 36, tint: .white.opacity(0.06))
        .environment(\.colorScheme, .dark)
    }
}

/// Chỉ số từ vựng tự theo dõi kho từ, để thêm từ không làm cả màn hình chính vẽ lại.
private struct VocabularyWidget<Content: View>: View {
    @ObservedObject private var store = VocabularyStore.shared
    let content: (String, String) -> Content

    var body: some View {
        content("\(store.learning.count)", "\(store.learned.count) từ đã thuộc")
    }
}

/// Icon Bàn phím tự theo dõi micro: trạng thái bàn phím đổi liên tục khi đang ghi âm,
/// chỉ riêng icon này vẽ lại chứ không phải cả màn hình chính.
private struct KeyboardAppIcon: View {
    let frames: IconFrameRegistry
    let action: () -> Void
    @ObservedObject private var voice = VoiceEngine.shared

    var body: some View {
        HomeAppIcon(app: .keyboard, badge: 0, micActive: voice.state.sessionActive, frames: frames, action: action)
    }
}

private struct HomeAppIcon: View {
    let app: AppTab
    let badge: Int
    var showsLabel = true
    /// Chỉ icon Bàn phím có: micro đang bật (true) hay tắt (false).
    var micActive: Bool?
    let frames: IconFrameRegistry
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                icon
                    .background(
                        GeometryReader { geo in
                            let frame = geo.frame(in: .global)
                            Color.clear
                                .onAppear { frames.frames[app] = frame }
                                .onChange(of: frame) { frames.frames[app] = $0 }
                        }
                    )
                if showsLabel {
                    Text(app.title)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.45), radius: 2, y: 1)
                        .lineLimit(1)
                }
            }
        }
        .buttonStyle(PressableStyle())
        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: badge)
        .accessibilityLabel(accessibilityText)
    }

    private var accessibilityText: String {
        var parts = [app.title]
        if badge > 0 { parts.append("\(badge)") }
        if let micActive { parts.append(micActive ? "micro đang bật" : "micro đang tắt") }
        return parts.joined(separator: ", ")
    }

    /// Icon bóng kính: màu nền, vệt sáng phía trên, viền phản quang, biểu tượng nổi nhẹ.
    private var icon: some View {
        let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)
        return shape
            .fill(LinearGradient(colors: app.colors, startPoint: .topLeading, endPoint: .bottomTrailing))
            .overlay(
                shape.fill(LinearGradient(colors: [.white.opacity(0.42), .white.opacity(0.05), .clear],
                                          startPoint: .top, endPoint: .center))
            )
            .overlay(
                shape.strokeBorder(
                    LinearGradient(colors: [.white.opacity(0.8), .white.opacity(0.1), .white.opacity(0.35)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing),
                    lineWidth: 1.2
                )
            )
            .frame(width: 62, height: 62)
            .overlay {
                Image(systemName: app.symbol)
                    .font(.system(size: 27, weight: .semibold))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.22), radius: 3, y: 2)
            }
            .shadow(color: app.colors[app.colors.count - 1].opacity(0.45), radius: 10, y: 6)
            .overlay(alignment: .topTrailing) {
                if badge > 0 {
                    Text(badge > 999 ? "999+" : "\(badge)")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .frame(minWidth: 23, minHeight: 23)
                        .background(Capsule().fill(Color.red))
                        .overlay(Capsule().strokeBorder(.white.opacity(0.35), lineWidth: 0.8))
                        .offset(x: 9, y: -8)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .overlay(alignment: .bottomTrailing) {
                if let micActive {
                    MicStatusBadge(active: micActive)
                        .offset(x: 8, y: 7)
                }
            }
            .background {
                if micActive == true {
                    MicGlowRing(cornerRadius: 18)
                        .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.3), value: micActive)
    }
}

/// Viền sáng xanh tỏa ra quanh icon Bàn phím khi micro đang bật.
private struct MicGlowRing: View {
    let cornerRadius: CGFloat

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var spread = false

    var body: some View {
        ZStack {
            ForEach(0..<2, id: \.self) { ring in
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(Color.green, lineWidth: 3)
                    .scaleEffect(spread ? 1.38 : 1)
                    .opacity(spread ? 0 : 0.9)
                    .animation(reduceMotion ? nil : .easeOut(duration: 1.6).repeatForever(autoreverses: false)
                        .delay(Double(ring) * 0.8), value: spread)
            }
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(Color.green.opacity(0.35))
                .blur(radius: 10)
        }
        .onAppear { spread = true }
        .onDisappear { spread = false }
        .allowsHitTesting(false)
    }
}

/// Viên báo micro bàn phím đang bật ở đầu màn hình chính, kiểu chỉ báo ghi âm của iPhone.
/// Tự theo dõi micro nên chỉ riêng viên này vẽ lại khi trạng thái bàn phím đổi.
private struct MicLiveBanner: View {
    let onTap: () -> Void
    @ObservedObject private var voice = VoiceEngine.shared

    var body: some View {
        let active = voice.state.sessionActive
        VStack {
            if active {
                Button(action: onTap) {
                    HStack(spacing: 10) {
                        SoundBars()
                            .frame(width: 22, height: 16)
                        Text("Micro bàn phím đang bật")
                            .font(.subheadline.weight(.semibold))
                        Spacer(minLength: 4)
                        Text("Mở")
                            .font(.caption.weight(.bold))
                            .padding(.horizontal, 9)
                            .padding(.vertical, 4)
                            .background(Capsule().fill(.white.opacity(0.22)))
                    }
                    .foregroundStyle(.white)
                    .padding(.leading, 14)
                    .padding(.trailing, 10)
                    .padding(.vertical, 10)
                    .background(
                        Capsule().fill(LinearGradient(colors: [Color(red: 0.2, green: 0.82, blue: 0.38), Color(red: 0.08, green: 0.6, blue: 0.3)],
                                                      startPoint: .leading, endPoint: .trailing))
                    )
                    .overlay(Capsule().strokeBorder(.white.opacity(0.35), lineWidth: 1))
                    .shadow(color: .green.opacity(0.45), radius: 10, y: 4)
                }
                .buttonStyle(PressableStyle())
                .transition(.move(edge: .top).combined(with: .opacity))
                .accessibilityLabel("Micro bàn phím đang bật. Mở trang bàn phím")
            }
        }
        .animation(.spring(response: 0.45, dampingFraction: 0.8), value: active)
    }
}

/// Cột sóng âm nhảy nhịp.
private struct SoundBars: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 20, paused: reduceMotion)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            HStack(alignment: .center, spacing: 3) {
                ForEach(0..<4, id: \.self) { bar in
                    let wave = (sin(t * (5 + Double(bar) * 1.3) + Double(bar)) + 1) / 2
                    Capsule()
                        .fill(.white)
                        .frame(width: 3, height: 4 + 12 * CGFloat(reduceMotion ? 0.5 : wave))
                }
            }
        }
    }
}

/// Chấm trạng thái micro: bật thì xanh, nhấp nháy kèm vòng sóng; tắt thì xám có gạch chéo.
private struct MicStatusBadge: View {
    let active: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulse = false

    var body: some View {
        ZStack {
            if active {
                Circle()
                    .fill(Color.green.opacity(0.55))
                    .frame(width: 24, height: 24)
                    .scaleEffect(pulse ? 1.7 : 0.9)
                    .opacity(pulse ? 0 : 0.9)
            }
            Circle()
                .fill(active ? Color(red: 0.2, green: 0.8, blue: 0.35) : Color(white: 0.32))
                .frame(width: 24, height: 24)
                .overlay(Circle().strokeBorder(.white.opacity(0.9), lineWidth: 1.5))
                .shadow(color: .black.opacity(0.3), radius: 3, y: 1)
            Image(systemName: active ? "mic.fill" : "mic.slash.fill")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.white)
                .opacity(active && pulse ? 0.45 : 1)
        }
        .frame(width: 26, height: 26)
        .onAppear(perform: restart)
        .onChange(of: active) { _ in restart() }
    }

    private func restart() {
        pulse = false
        guard active, !reduceMotion else { return }
        DispatchQueue.main.async {
            withAnimation(.easeInOut(duration: 0.85).repeatForever(autoreverses: false)) { pulse = true }
        }
    }
}

private extension View {
    /// Bật lên lần lượt khi màn hình chính hiện ra.
    func appear(_ appeared: Bool, delay: Double) -> some View {
        self
            .scaleEffect(appeared ? 1 : 0.85)
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : 14)
            .animation(.spring(response: 0.55, dampingFraction: 0.78).delay(delay), value: appeared)
    }
}

private extension String {
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}
