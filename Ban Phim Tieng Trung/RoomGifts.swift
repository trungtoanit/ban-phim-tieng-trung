//
//  RoomGifts.swift
//  Quà tặng miễn phí kiểu TikTok trong phòng chat: bảng chọn quà, hiệu ứng (bay lên, banner,
//  pháo giấy, rồng bay toàn màn hình), viên thông báo quà trong danh sách tin, bảng xếp hạng quà.
//

import Combine
import SwiftUI

private let giftGold = Color(red: 1, green: 0.78, blue: 0.2)

// MARK: - Hàng đợi hiệu ứng

struct GiftEvent: Identifiable, Equatable {
    let id = UUID()
    let gift: RoomGift
    let senderName: String
    let senderAvatar: URL?
    let senderInitial: String

    init(message: RoomMessage, gift: RoomGift) {
        self.gift = gift
        senderName = message.mine ? "Bạn" : message.user.name
        senderAvatar = message.user.avatarURL
        senderInitial = message.user.initial
    }

    var recipientText: String { gift.to?.name ?? "cả phòng" }

    var duration: Double {
        switch gift.tier {
        case .small: return 2.2
        case .medium: return 2.6
        case .big: return 3.0
        case .epic: return 3.4
        }
    }
}

/// Phát lần lượt từng hiệu ứng quà.
@MainActor
final class GiftEffectCenter: ObservableObject {
    @Published private(set) var current: GiftEvent?
    private var queue: [GiftEvent] = []
    private var runner: Task<Void, Never>?
    var reduceMotion = false

    func enqueue(_ message: RoomMessage) {
        guard let gift = message.gift else { return }
        // Tránh dồn quá nhiều hiệu ứng khi nhiều người tặng cùng lúc.
        guard queue.count < 12 else { return }
        queue.append(GiftEvent(message: message, gift: gift))
        startIfNeeded()
    }

    func stop() {
        runner?.cancel()
        runner = nil
        queue.removeAll()
        current = nil
    }

    private func startIfNeeded() {
        guard runner == nil else { return }
        runner = Task { [weak self] in
            while let self, !Task.isCancelled, !self.queue.isEmpty {
                let event = self.queue.removeFirst()
                self.current = event
                self.haptic(for: event.gift.tier)
                let seconds = self.reduceMotion ? 1.8 : event.duration
                try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                self.current = nil
                try? await Task.sleep(nanoseconds: 150_000_000)
            }
            self?.runner = nil
        }
    }

    private func haptic(for tier: GiftTier) {
        switch tier {
        case .small: UIImpactFeedbackGenerator(style: .light).impactOccurred()
        case .medium: UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        case .big: UINotificationFeedbackGenerator().notificationOccurred(.success)
        case .epic:
            let heavy = UIImpactFeedbackGenerator(style: .heavy)
            heavy.impactOccurred()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { heavy.impactOccurred(intensity: 0.8) }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { heavy.impactOccurred() }
        }
    }
}

// MARK: - Lớp hiệu ứng

/// Đặt trên cùng màn phòng chat; không nhận chạm.
struct GiftEffectsOverlay: View {
    @ObservedObject var center: GiftEffectCenter
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            if let event = center.current {
                GiftEffectView(event: event, reduceMotion: reduceMotion)
                    .id(event.id)
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.2), value: center.current?.id)
        .allowsHitTesting(false)
        .onAppear { center.reduceMotion = reduceMotion }
        .onChange(of: reduceMotion) { center.reduceMotion = $0 }
    }
}

/// Một hiệu ứng, vẽ theo thời gian trôi (TimelineView) để mọi thứ đồng bộ và không phải giữ trạng thái hoạt ảnh.
private struct GiftEffectView: View {
    let event: GiftEvent
    let reduceMotion: Bool

    @State private var start = Date()
    private let seed = UInt64.random(in: 1...UInt64.max / 2)

    var body: some View {
        TimelineView(.animation) { timeline in
            let t = max(0, timeline.date.timeIntervalSince(start))
            GeometryReader { geo in
                ZStack {
                    if reduceMotion {
                        banner(t: t, size: geo.size)
                    } else {
                        switch event.gift.tier {
                        case .small:
                            floatingEmojis(t: t, size: geo.size)
                            if event.gift.count > 1 { banner(t: t, size: geo.size) }
                        case .medium:
                            centerPop(t: t, size: geo.size, scale: 1)
                            sparkleRing(t: t, size: geo.size)
                            banner(t: t, size: geo.size)
                        case .big:
                            confetti(t: t, size: geo.size)
                            centerPop(t: t, size: geo.size, scale: 1.5)
                            banner(t: t, size: geo.size)
                        case .epic:
                            epic(t: t, size: geo.size)
                        }
                    }
                }
                .frame(width: geo.size.width, height: geo.size.height)
            }
        }
        .ignoresSafeArea()
        .onAppear { start = Date() }
        .accessibilityElement()
        .accessibilityLabel("\(event.senderName) tặng \(event.recipientText) \(event.gift.name) x\(event.gift.count)")
    }

    // MARK: Số ngẫu nhiên ổn định theo từng hạt

    private func random(_ index: Int, _ salt: UInt64) -> Double {
        var x = seed &+ UInt64(index) &* 0x9E37_79B9_7F4A_7C15 &+ salt &* 0xBF58_476D_1CE4_E5B9
        x ^= x >> 30
        x = x &* 0xBF58_476D_1CE4_E5B9
        x ^= x >> 27
        x = x &* 0x94D0_49BB_1331_11EB
        x ^= x >> 31
        return Double(x % 10_000) / 10_000
    }

    private func easeOut(_ x: Double) -> Double { 1 - pow(1 - min(max(x, 0), 1), 3) }

    /// Nảy kiểu lò xo: 0 → vượt quá 1 → về 1.
    private func spring(_ t: Double) -> Double { 1 - exp(-7 * t) * cos(11 * t) }

    // MARK: Nhỏ: emoji bay lên

    private func floatingEmojis(t: Double, size: CGSize) -> some View {
        let count: Int = 8 + Int(random(99, 1) * 5)
        return Canvas { context, canvas in
            for i in 0..<count {
                drawFloating(index: i, t: t, context: context, canvas: canvas)
            }
        }
    }

    private func drawFloating(index i: Int, t: Double, context: GraphicsContext, canvas: CGSize) {
        let delay: Double = random(i, 2) * 0.7
        let life: Double = 1.4 + random(i, 3) * 0.4
        let p: Double = (t - delay) / life
        guard p > 0, p < 1 else { return }
        let startX: CGFloat = canvas.width * CGFloat(0.15 + random(i, 4) * 0.7)
        let drift: CGFloat = CGFloat((random(i, 5) - 0.5) * 120 * p)
        let y: CGFloat = canvas.height * CGFloat(0.85 - 0.6 * easeOut(p))
        let scale: CGFloat = CGFloat(0.7 + random(i, 6) * 0.8 + p * 0.3)
        let opacity: Double = p < 0.15 ? p / 0.15 : (p > 0.7 ? (1 - p) / 0.3 : 1)
        let angle: Double = (random(i, 7) - 0.5) * 70 * p
        var ctx = context
        ctx.opacity = opacity
        ctx.translateBy(x: startX + drift, y: y)
        ctx.rotate(by: .degrees(angle))
        ctx.scaleBy(x: scale, y: scale)
        ctx.draw(Text(event.gift.emoji).font(.system(size: 34)), at: .zero)
    }

    // MARK: Vừa: emoji nảy giữa màn hình + vòng lấp lánh

    private func centerPop(t: Double, size: CGSize, scale: Double) -> some View {
        let fadeStart = event.duration - 0.6
        let opacity = t < fadeStart ? 1 : max(0, 1 - (t - fadeStart) / 0.5)
        let s = spring(t) * scale
        return Text(event.gift.emoji)
            .font(.system(size: 110))
            .scaleEffect(max(0.01, s))
            .shadow(color: giftGold.opacity(0.8), radius: 24)
            .opacity(opacity)
            .position(x: size.width / 2, y: size.height * 0.42)
    }

    private func sparkleRing(t: Double, size: CGSize) -> some View {
        Canvas { context, canvas in
            for ring in 0..<2 {
                drawRing(ring, t: t, context: context, canvas: canvas)
            }
        }
    }

    private func drawRing(_ ring: Int, t: Double, context: GraphicsContext, canvas: CGSize) {
        let center = CGPoint(x: canvas.width / 2, y: canvas.height * 0.42)
        let p: Double = (t - 0.15 - Double(ring) * 0.25) / 1.1
        guard p > 0, p < 1 else { return }
        let radius: CGFloat = CGFloat(60 + 120 * easeOut(p))
        let opacity: Double = 1 - p
        var circle = context
        circle.opacity = opacity * 0.6
        let rect = CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
        circle.stroke(Path(ellipseIn: rect), with: .color(giftGold), lineWidth: 3)
        let starSize: CGFloat = CGFloat(16 + 8 * (1 - p))
        for i in 0..<12 {
            let angle: Double = Double(i) / 12 * 2 * Double.pi + Double(ring) * 0.26
            let point = CGPoint(x: center.x + CGFloat(cos(angle)) * radius, y: center.y + CGFloat(sin(angle)) * radius)
            var star = context
            star.opacity = opacity
            star.draw(Text("✨").font(.system(size: starSize)), at: point)
        }
    }

    // MARK: Banner trượt từ trái (kiểu TikTok)

    private func banner(t: Double, size: CGSize) -> some View {
        let enter = easeOut(t / 0.45)
        let leaveStart = (reduceMotion ? 1.8 : event.duration) - 0.45
        let leave = t > leaveStart ? easeOut((t - leaveStart) / 0.45) : 0
        let x = -size.width + size.width * enter - size.width * leave
        let pulse = 1 + 0.12 * sin(t * 9)
        return HStack(spacing: 10) {
            SocialAvatar(url: event.senderAvatar, initial: event.senderInitial, size: 38)
                .overlay(Circle().strokeBorder(.white, lineWidth: 2))
            VStack(alignment: .leading, spacing: 1) {
                Text(event.senderName)
                    .font(.subheadline.weight(.bold))
                    .lineLimit(1)
                Text("tặng \(event.recipientText) · \(event.gift.name)")
                    .font(.caption)
                    .lineLimit(1)
                    .opacity(0.9)
            }
            .foregroundStyle(.white)
            Text(event.gift.emoji)
                .font(.system(size: 36))
                .shadow(color: .black.opacity(0.25), radius: 3)
            Text("x\(event.gift.count)")
                .font(.system(size: 26, weight: .heavy, design: .rounded))
                .italic()
                .foregroundStyle(LinearGradient(colors: [.white, giftGold], startPoint: .top, endPoint: .bottom))
                .shadow(color: .orange, radius: 4)
                .scaleEffect(pulse)
        }
        .padding(.leading, 5)
        .padding(.trailing, 16)
        .padding(.vertical, 5)
        .background(
            Capsule().fill(LinearGradient(colors: [socialRed, Color(red: 1, green: 0.45, blue: 0.2).opacity(0.85)],
                                          startPoint: .leading, endPoint: .trailing))
        )
        .shadow(color: .black.opacity(0.2), radius: 8, y: 3)
        .frame(maxWidth: size.width - 24, alignment: .leading)
        .position(x: size.width / 2 + x, y: size.height * 0.24)
        .frame(width: size.width, height: size.height, alignment: .topLeading)
    }

    // MARK: Lớn: pháo giấy đỏ / vàng

    private static let confettiColors: [Color] = [socialRed, giftGold, .orange, Color(red: 1, green: 0.9, blue: 0.5), .white]

    private func confetti(t: Double, size: CGSize) -> some View {
        Canvas { context, canvas in
            for burst in 0..<2 {
                for i in 0..<45 {
                    drawConfetti(index: i, burst: burst, t: t, context: context, canvas: canvas)
                }
            }
        }
    }

    private func drawConfetti(index i: Int, burst: Int, t: Double, context: GraphicsContext, canvas: CGSize) {
        let bt: Double = t - Double(burst) * 0.35
        guard bt > 0 else { return }
        let life: Double = 1.8 + random(i, 30) * 0.6
        guard bt < life else { return }
        let angle: Double = random(i, 10 + UInt64(burst)) * 2 * Double.pi
        let speed: Double = 180 + random(i, 20 + UInt64(burst)) * 320
        let x: CGFloat = canvas.width / 2 + CGFloat(cos(angle) * speed * bt)
        let y: CGFloat = canvas.height * 0.42 + CGFloat(sin(angle) * speed * bt + 380 * bt * bt)
        let spin: Double = bt * (4 + random(i, 40) * 8)
        let w: CGFloat = CGFloat(5 + random(i, 50) * 5)
        var ctx = context
        ctx.opacity = max(0, 1 - bt / life)
        ctx.translateBy(x: x, y: y)
        ctx.rotate(by: .radians(spin))
        ctx.fill(Path(CGRect(x: -w / 2, y: -w / 4, width: w, height: w / 2)),
                 with: .color(Self.confettiColors[i % Self.confettiColors.count]))
    }

    // MARK: Epic: rồng bay toàn màn hình

    private func epic(t: Double, size: CGSize) -> some View {
        let total = event.duration
        let fade = t > total - 0.5 ? max(0, (total - t) / 0.5) : min(1, t / 0.3)
        return ZStack {
            Color.black.opacity(0.5 * fade)

            // Mưa hạt vàng
            Canvas { context, canvas in
                for i in 0..<70 {
                    drawGoldRain(index: i, t: t, fade: fade, context: context, canvas: canvas)
                }
            }

            // Emoji khổng lồ bay chéo màn hình với vệt sáng
            Canvas { context, canvas in
                drawFlight(t: t, total: total, fade: fade, context: context, canvas: canvas)
            }

            VStack(spacing: 6) {
                Text("\(event.senderName) tặng \(event.recipientText)")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .shadow(radius: 4)
                Text("\(event.gift.emoji) \(event.gift.name)")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(giftGold)
                    .shadow(color: .orange, radius: 6)
                Text("x\(event.gift.count)")
                    .font(.system(size: 64, weight: .black, design: .rounded))
                    .italic()
                    .foregroundStyle(LinearGradient(colors: [.white, giftGold, .orange], startPoint: .top, endPoint: .bottom))
                    .shadow(color: socialRed, radius: 10)
                    .scaleEffect(1 + 0.08 * sin(t * 14))
                    .offset(x: sin(t * 55) * 4 * max(0, 1 - t / 1.5), y: cos(t * 47) * 3 * max(0, 1 - t / 1.5))
            }
            .opacity(fade)
            .scaleEffect(0.6 + 0.4 * spring(t * 1.2))
            .position(x: size.width / 2, y: size.height * 0.36)
        }
    }

    private func drawGoldRain(index i: Int, t: Double, fade: Double, context: GraphicsContext, canvas: CGSize) {
        let delay: Double = random(i, 60) * 1.6
        let p: Double = (t - delay) / 1.6
        guard p > 0, p < 1 else { return }
        let x: CGFloat = canvas.width * CGFloat(random(i, 61)) + CGFloat(sin(t * 3 + Double(i)) * 12)
        let y: CGFloat = -20 + (canvas.height + 40) * CGFloat(p)
        let r: CGFloat = CGFloat(2 + random(i, 62) * 3.5)
        var ctx = context
        ctx.opacity = fade * (1 - p * 0.4)
        ctx.fill(Path(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)),
                 with: .color(i % 3 == 0 ? .white : giftGold))
    }

    private func flightPoint(_ p: Double, canvas: CGSize) -> CGPoint {
        let x: CGFloat = -120 + (canvas.width + 240) * CGFloat(p)
        let y: CGFloat = canvas.height * 0.72 - canvas.height * 0.42 * CGFloat(p) + CGFloat(sin(p * Double.pi * 2) * 40)
        return CGPoint(x: x, y: y)
    }

    private func drawFlight(t: Double, total: Double, fade: Double, context: GraphicsContext, canvas: CGSize) {
        let flight: Double = min(1, t / (total * 0.8))
        for k in stride(from: 8, through: 1, by: -1) {
            let p: Double = flight - Double(k) * 0.025
            guard p > 0 else { continue }
            var trail = context
            trail.opacity = fade * 0.5 * (1 - Double(k) / 9)
            trail.addFilter(.blur(radius: CGFloat(k)))
            let fontSize: CGFloat = 150 - CGFloat(k) * 8
            trail.draw(Text(event.gift.emoji).font(.system(size: fontSize)), at: flightPoint(p, canvas: canvas))
        }
        var glow = context
        glow.opacity = fade
        glow.addFilter(.shadow(color: giftGold, radius: 30))
        glow.draw(Text(event.gift.emoji).font(.system(size: 160)), at: flightPoint(flight, canvas: canvas))
    }
}

// MARK: - Viên quà trong danh sách tin

struct GiftMessagePill: View {
    let message: RoomMessage
    let gift: RoomGift
    let onReplay: () -> Void

    var body: some View {
        Button(action: onReplay) {
            HStack(spacing: 6) {
                Text("🎁")
                (Text(message.mine ? "Bạn" : message.user.name).fontWeight(.bold)
                 + Text(" tặng ")
                 + Text(gift.to?.name ?? "cả phòng").fontWeight(.bold))
                    .lineLimit(1)
                Text(gift.emoji).font(.title3)
                Text(gift.name).lineLimit(1)
                Text("x\(gift.count)")
                    .font(.subheadline.weight(.heavy))
                    .italic()
                    .foregroundStyle(giftGold)
            }
            .font(.caption)
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(
                Capsule().fill(LinearGradient(colors: pillColors, startPoint: .leading, endPoint: .trailing))
            )
            .overlay(Capsule().strokeBorder(.white.opacity(0.35), lineWidth: 1))
            .shadow(color: pillColors.first!.opacity(0.35), radius: 6, y: 2)
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
        .accessibilityLabel("\(message.mine ? "Bạn" : message.user.name) tặng \(gift.to?.name ?? "cả phòng") \(gift.name) x\(gift.count)")
        .accessibilityHint("Chạm để xem lại hiệu ứng")
    }

    private var pillColors: [Color] {
        switch gift.tier {
        case .small: return [Color(red: 1, green: 0.45, blue: 0.55), Color(red: 1, green: 0.6, blue: 0.4)]
        case .medium: return [Color(red: 0.95, green: 0.35, blue: 0.2), Color(red: 1, green: 0.62, blue: 0.1)]
        case .big: return [socialRed, Color(red: 0.95, green: 0.65, blue: 0.1)]
        case .epic: return [Color(red: 0.55, green: 0.15, blue: 0.75), socialRed, Color(red: 1, green: 0.7, blue: 0.1)]
        }
    }
}

// MARK: - Bảng chọn quà

struct GiftRecipient: Identifiable, Hashable {
    let id: Int
    let name: String
    let avatar: URL?
    let initial: String
    var isOwner = false
    var online = false
}

struct GiftSheet: View {
    @ObservedObject var model: RoomChatModel
    let onSent: (RoomMessage) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var gifts: [GiftItem] = []
    @State private var loaded = false
    @State private var selected: GiftItem?
    /// nil = cả phòng.
    @State private var recipientID: Int?
    @State private var multiplier = 1
    /// Số lần bấm "Tặng" liên tiếp đang dồn lại (gửi gộp sau 0,7 giây).
    @State private var pendingTaps = 0
    @State private var comboShown = 0
    @State private var flushTask: Task<Void, Never>?
    @State private var sending = false
    @State private var errorMessage: String?

    private var myID: Int? { WebAccountStore.shared.user?.id }

    private var recipients: [GiftRecipient] {
        var list: [GiftRecipient] = []
        var seen = Set<Int>()
        func add(_ r: GiftRecipient) {
            guard r.id != myID, !seen.contains(r.id) else { return }
            seen.insert(r.id)
            list.append(r)
        }
        let room = model.room
        if room.ownerId > 0 {
            add(GiftRecipient(id: room.ownerId, name: room.owner?.name ?? room.ownerName, avatar: room.owner?.avatarURL,
                              initial: String((room.owner?.name ?? room.ownerName).prefix(1)).uppercased(), isOwner: true,
                              online: model.onlineIDs.contains(room.ownerId)))
        }
        if let reply = model.replyingTo {
            add(GiftRecipient(id: reply.user.id, name: reply.user.name, avatar: reply.user.avatarURL, initial: reply.user.initial,
                              online: model.onlineIDs.contains(reply.user.id)))
        }
        for user in model.online {
            add(GiftRecipient(id: user.id, name: user.name, avatar: user.avatarURL, initial: user.initial, online: true))
        }
        for member in model.room.sortedMembers where member.online {
            add(GiftRecipient(id: member.id, name: member.name, avatar: member.avatarURL, initial: member.initial,
                              isOwner: member.isOwner, online: true))
        }
        return list
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                recipientPicker
                ScrollView {
                    if !loaded {
                        ProgressView().padding(.top, 30)
                    } else if gifts.isEmpty {
                        Text(errorMessage ?? "Chưa có quà nào.")
                            .foregroundStyle(.secondary)
                            .padding(.top, 30)
                    } else {
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 4), spacing: 10) {
                            ForEach(gifts) { gift in
                                GiftCell(gift: gift, selected: selected?.key == gift.key,
                                         combo: selected?.key == gift.key ? comboShown : 0) {
                                    if selected?.key != gift.key {
                                        flush()
                                        selected = gift
                                    }
                                    UISelectionFeedbackGenerator().selectionChanged()
                                }
                            }
                        }
                        .padding(.horizontal, 14)
                        .padding(.top, 4)
                    }
                }
                footer
            }
            .navigationTitle("🎁 Tặng quà")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Đóng") {
                        flush()
                        dismiss()
                    }
                }
            }
            .task { await load() }
            .onDisappear { flush() }
        }
        .tint(socialRed)
        .presentationDetents([.medium, .large])
    }

    private var recipientPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                recipientChip(id: nil, label: "Cả phòng") {
                    Text("👥")
                        .font(.system(size: 22))
                        .frame(width: 44, height: 44)
                        .background(Circle().fill(Color(.tertiarySystemFill)))
                }
                ForEach(recipients) { r in
                    recipientChip(id: r.id, label: r.name) {
                        SocialAvatar(url: r.avatar, initial: r.initial, size: 44, online: r.online)
                            .overlay(alignment: .top) {
                                if r.isOwner { Text("👑").font(.system(size: 13)).offset(y: -10) }
                            }
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 10)
        }
    }

    private func recipientChip<Icon: View>(id: Int?, label: String, @ViewBuilder icon: () -> Icon) -> some View {
        let active = recipientID == id
        return Button {
            if recipientID != id { flush() }
            recipientID = id
            UISelectionFeedbackGenerator().selectionChanged()
        } label: {
            VStack(spacing: 4) {
                icon()
                    .padding(3)
                    .overlay(Circle().strokeBorder(active ? socialRed : .clear, lineWidth: 2.5))
                Text(label)
                    .font(.caption2.weight(active ? .bold : .regular))
                    .foregroundStyle(active ? socialRed : .primary)
                    .lineLimit(1)
                    .frame(maxWidth: 64)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Tặng \(label)")
        .accessibilityAddTraits(active ? .isSelected : [])
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Picker("Combo", selection: $multiplier) {
                Text("x1").tag(1)
                Text("x10").tag(10)
                Text("x99").tag(99)
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 170)
            .onChange(of: multiplier) { _ in flush() }

            Spacer(minLength: 0)

            Button {
                tapSend()
            } label: {
                HStack(spacing: 6) {
                    if sending && pendingTaps == 0 {
                        ProgressView().tint(.white)
                    } else {
                        Text(selected?.emoji ?? "🎁")
                    }
                    Text(pendingTaps > 0 ? "Tặng x\(min(99, pendingTaps * multiplier))" : "Tặng")
                        .fontWeight(.bold)
                        .monospacedDigit()
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 22)
                .padding(.vertical, 12)
                .background(Capsule().fill(selected == nil ? Color(.systemGray3) : socialRed))
                .scaleEffect(pendingTaps > 0 ? 1.06 : 1)
                .animation(.spring(response: 0.2, dampingFraction: 0.5), value: pendingTaps)
            }
            .buttonStyle(.plain)
            .disabled(selected == nil)
            .accessibilityLabel("Tặng quà")
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 10)
        .overlay(alignment: .top) {
            if let errorMessage, loaded, !gifts.isEmpty {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .offset(y: -18)
            }
        }
    }

    private func load() async {
        do {
            gifts = try await SocialAPI.gifts()
            selected = selected ?? gifts.first
        } catch {
            errorMessage = error.localizedDescription
        }
        // Mặc định: người đang được trả lời, không thì chủ phòng (nếu không phải mình).
        if let reply = model.replyingTo, reply.user.id != myID {
            recipientID = reply.user.id
        } else if model.room.ownerId > 0, model.room.ownerId != myID {
            recipientID = model.room.ownerId
        }
        loaded = true
    }

    /// Bấm liên tục cùng một món thì dồn thành combo, gửi gộp khi ngừng bấm 0,7 giây (hoặc đủ 99).
    private func tapSend() {
        guard selected != nil else { return }
        errorMessage = nil
        UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
        pendingTaps += 1
        comboShown = min(99, pendingTaps * multiplier)
        flushTask?.cancel()
        if pendingTaps * multiplier >= 99 {
            flush()
            return
        }
        flushTask = Task {
            try? await Task.sleep(nanoseconds: 700_000_000)
            guard !Task.isCancelled else { return }
            flush()
        }
    }

    private func flush() {
        flushTask?.cancel()
        flushTask = nil
        guard pendingTaps > 0, let gift = selected else { return }
        let count = min(99, pendingTaps * multiplier)
        pendingTaps = 0
        let to = recipientID
        let roomID = model.room.id
        sending = true
        Task {
            defer {
                sending = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) { if pendingTaps == 0 { comboShown = 0 } }
            }
            do {
                let message = try await SocialAPI.sendGift(roomId: roomID, gift: gift.key, to: to, count: count)
                onSent(message)
            } catch {
                UINotificationFeedbackGenerator().notificationOccurred(.error)
                errorMessage = error.localizedDescription
            }
        }
    }
}

/// Ô quà: hạng vừa phát sáng, hạng lớn viền vàng, hạng epic viền cầu vồng xoay.
private struct GiftCell: View {
    let gift: GiftItem
    let selected: Bool
    let combo: Int
    let onTap: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 3) {
                Text(gift.emoji)
                    .font(.system(size: 38))
                    .shadow(color: gift.tier == .medium ? .orange.opacity(0.8) : .clear, radius: 10)
                    .scaleEffect(selected ? 1.12 : 1)
                Text(gift.name)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text("Miễn phí")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(onlineGreen)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(shape.fill(selected ? socialRed.opacity(0.12) : Color(.secondarySystemGroupedBackground)))
            .overlay { border }
            .overlay(alignment: .topTrailing) {
                if combo > 0 {
                    Text("x\(combo)")
                        .font(.system(size: 13, weight: .heavy, design: .rounded))
                        .italic()
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(socialRed))
                        .offset(x: 6, y: -8)
                        .transition(.scale.combined(with: .opacity))
                        .id(combo)
                }
            }
            .animation(.spring(response: 0.25, dampingFraction: 0.55), value: combo)
            .animation(.spring(response: 0.25, dampingFraction: 0.6), value: selected)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(gift.name), miễn phí")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    @ViewBuilder
    private var border: some View {
        switch gift.tier {
        case .small:
            shape.strokeBorder(selected ? socialRed : .clear, lineWidth: 2)
        case .medium:
            shape.strokeBorder(selected ? socialRed : Color.orange.opacity(0.45), lineWidth: selected ? 2 : 1.5)
                .shadow(color: .orange.opacity(0.5), radius: 6)
        case .big:
            shape.strokeBorder(LinearGradient(colors: [giftGold, .orange, giftGold], startPoint: .topLeading, endPoint: .bottomTrailing),
                               lineWidth: selected ? 3 : 2.2)
        case .epic:
            if reduceMotion {
                shape.strokeBorder(rainbow(angle: 0), lineWidth: 3)
            } else {
                TimelineView(.animation) { timeline in
                    let angle = timeline.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 3) / 3 * 360
                    shape.strokeBorder(rainbow(angle: angle), lineWidth: 3)
                        .shadow(color: .purple.opacity(0.4), radius: 6)
                }
            }
        }
    }

    private func rainbow(angle: Double) -> AngularGradient {
        AngularGradient(colors: [.red, .orange, .yellow, .green, .blue, .purple, .red], center: .center,
                        angle: .degrees(angle))
    }
}

// MARK: - Bảng xếp hạng quà

struct GiftTopSection: View {
    let roomID: Int
    @State private var senders: [GiftTopUser] = []
    @State private var receivers: [GiftTopUser] = []
    @State private var loaded = false

    var body: some View {
        Section {
            if loaded, senders.isEmpty, receivers.isEmpty {
                Text("Chưa có ai tặng quà. Bấm 🎁 trong phòng để tặng miễn phí!")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                if !senders.isEmpty {
                    Text("Tặng nhiều nhất")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    ForEach(Array(senders.enumerated()), id: \.element.id) { index, user in
                        row(index: index, user: user, verb: "đã tặng")
                    }
                }
                if !receivers.isEmpty {
                    Text("Nhận nhiều nhất")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    ForEach(Array(receivers.enumerated()), id: \.element.id) { index, user in
                        row(index: index, user: user, verb: "đã nhận")
                    }
                }
            }
        } header: {
            Text("🏆 Quà trong phòng")
        }
        .task(id: roomID) {
            if let top = try? await SocialAPI.giftTop(roomId: roomID) {
                senders = top.senders
                receivers = top.receivers
            }
            loaded = true
        }
    }

    private func row(index: Int, user: GiftTopUser, verb: String) -> some View {
        NavigationLink(value: user.socialUser) {
            HStack(spacing: 10) {
                Text(["🥇", "🥈", "🥉"].indices.contains(index) ? ["🥇", "🥈", "🥉"][index] : "\(index + 1)")
                    .font(index < 3 ? .body : .subheadline.weight(.semibold))
                    .frame(width: 26)
                SocialAvatar(url: user.avatarURL, initial: user.initial, size: 34)
                Text(user.name)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Spacer()
                Text("🎁 \(user.total)")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(socialRed)
                    .accessibilityLabel("\(verb) \(user.total) quà")
            }
        }
    }
}
