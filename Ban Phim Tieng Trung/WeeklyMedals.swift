//
//  WeeklyMedals.swift
//  Huân chương tuần: mỗi Chủ nhật máy chủ chốt top 3 số câu nói và trao 🥇🥈🥉.
//  Chip huân chương cạnh tên, "Bảng vàng" ở màn Bạn bè, mục "Huân chương tuần" trên tường.
//

import SwiftUI

private let medalGold = Color(red: 0.93, green: 0.7, blue: 0.1)
private let medalSilver = Color(red: 0.62, green: 0.66, blue: 0.72)
private let medalBronze = Color(red: 0.8, green: 0.5, blue: 0.25)

// MARK: - Chip cạnh tên

/// "🥇2 🥈1" — chỉ hiện loại khác 0; không có huân chương thì không chiếm chỗ.
struct MedalChips: View {
    let medals: Medals?
    var font: Font = .caption2

    var body: some View {
        if let medals, medals.total > 0 {
            HStack(spacing: 4) {
                if medals.gold > 0 { chip("🥇", medals.gold) }
                if medals.silver > 0 { chip("🥈", medals.silver) }
                if medals.bronze > 0 { chip("🥉", medals.bronze) }
            }
            .fixedSize()
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(label(medals))
        }
    }

    private func chip(_ emoji: String, _ count: Int) -> some View {
        HStack(spacing: 1) {
            Text(emoji)
            Text("\(count)")
                .fontWeight(.bold)
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
        .font(font)
    }

    private func label(_ medals: Medals) -> String {
        var parts: [String] = []
        if medals.gold > 0 { parts.append("\(medals.gold) huy chương vàng") }
        if medals.silver > 0 { parts.append("\(medals.silver) huy chương bạc") }
        if medals.bronze > 0 { parts.append("\(medals.bronze) huy chương đồng") }
        return parts.joined(separator: ", ")
    }
}

// MARK: - Bảng vàng (màn Bạn bè)

/// Section "🏆 Bảng vàng": bục nhận giải tuần đã chốt gần nhất + các tuần trước.
struct GoldBoardSection: View {
    let weeks: [AwardWeek]
    let loaded: Bool

    @State private var showPrevious = false

    var body: some View {
        Section {
            if let latest = weeks.first, !latest.winners.isEmpty {
                VStack(spacing: 10) {
                    Text(SocialFormat.week(start: latest.weekStart, end: latest.weekEnd))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Podium(winners: latest.winners)
                }
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity)

                if weeks.count > 1 {
                    DisclosureGroup(isExpanded: $showPrevious) {
                        ForEach(weeks.dropFirst()) { week in
                            previousWeekRow(week)
                        }
                    } label: {
                        Text("Xem các tuần trước")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(socialRed)
                    }
                }
            } else if loaded {
                HStack(spacing: 10) {
                    Text("🏆").font(.title2)
                    Text("Chưa có tuần nào được chốt. Luyện nói thật nhiều để lọt top 3 tuần này nhé!")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            } else {
                ProgressView().frame(maxWidth: .infinity)
            }
        } header: {
            Text("🏆 Bảng vàng")
        } footer: {
            Text("Mỗi Chủ nhật chốt top 3 và trao huân chương")
        }
    }

    private func previousWeekRow(_ week: AwardWeek) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(SocialFormat.week(start: week.weekStart, end: week.weekEnd))
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            ForEach(week.winners) { winner in
                NavigationLink(value: winner.socialUser) {
                    HStack(spacing: 8) {
                        Text(winner.medal)
                        SocialAvatar(url: winner.avatarURL, initial: winner.initial, size: 26)
                        Text(winner.isMe ? "Bạn" : winner.name)
                            .font(.subheadline.weight(winner.isMe ? .bold : .medium))
                            .lineLimit(1)
                        Spacer()
                        Text("\(winner.sentences) câu")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }
}

/// Bục nhận giải: 🥈 trái, 🥇 giữa cao hơn, 🥉 phải.
private struct Podium: View {
    let winners: [AwardWinner]

    var body: some View {
        let first = winners.first { $0.rank == 1 }
        let second = winners.first { $0.rank == 2 }
        let third = winners.first { $0.rank == 3 }
        HStack(alignment: .bottom, spacing: 8) {
            place(second, height: 58, color: medalSilver)
            place(first, height: 84, color: medalGold)
            place(third, height: 44, color: medalBronze)
        }
        .frame(maxWidth: 360)
    }

    @ViewBuilder
    private func place(_ winner: AwardWinner?, height: CGFloat, color: Color) -> some View {
        VStack(spacing: 5) {
            if let winner {
                NavigationLink(value: winner.socialUser) {
                    VStack(spacing: 4) {
                        SocialAvatar(url: winner.avatarURL, initial: winner.initial, size: winner.rank == 1 ? 60 : 48)
                            .overlay(Circle().strokeBorder(color, lineWidth: 3))
                            .overlay(alignment: .bottomTrailing) {
                                Text(winner.medal)
                                    .font(.system(size: winner.rank == 1 ? 24 : 20))
                                    .offset(x: 6, y: 6)
                            }
                            .shadow(color: color.opacity(0.45), radius: winner.rank == 1 ? 10 : 5)
                        Text(winner.isMe ? "Bạn" : winner.name)
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        Text("\(winner.sentences) câu")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Hạng \(winner.rank): \(winner.isMe ? "Bạn" : winner.name), \(winner.sentences) câu")
            } else {
                Text("—").foregroundStyle(.tertiary).frame(height: 48)
            }
            ZStack {
                UnevenTop(radius: 10)
                    .fill(LinearGradient(colors: [color.opacity(0.85), color.opacity(0.45)], startPoint: .top, endPoint: .bottom))
                Text(winner.map { "\($0.rank)" } ?? "")
                    .font(.system(size: 22, weight: .black, design: .rounded))
                    .foregroundStyle(.white.opacity(0.9))
            }
            .frame(height: height)
        }
        .frame(maxWidth: .infinity)
    }
}

/// Hình chữ nhật bo góc phía trên (bục).
private struct UnevenTop: Shape {
    let radius: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let r = min(radius, rect.width / 2, rect.height)
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + r))
        path.addQuadCurve(to: CGPoint(x: rect.minX + r, y: rect.minY), control: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - r, y: rect.minY))
        path.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY + r), control: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

// MARK: - Tường: Huân chương tuần

struct WallMedalsCard: View {
    let medals: Medals?
    let awards: [WeeklyAward]

    private let card = RoundedRectangle(cornerRadius: 18, style: .continuous)

    var body: some View {
        let counts = medals ?? countsFromAwards
        VStack(alignment: .leading, spacing: 10) {
            Text("🏅 Huân chương tuần")
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)
            VStack(spacing: 12) {
                HStack(spacing: 10) {
                    MedalCount(emoji: "🥇", count: counts.gold, label: "Vàng", color: medalGold, delay: 0)
                    MedalCount(emoji: "🥈", count: counts.silver, label: "Bạc", color: medalSilver, delay: 0.35)
                    MedalCount(emoji: "🥉", count: counts.bronze, label: "Đồng", color: medalBronze, delay: 0.7)
                }
                if awards.isEmpty {
                    Text("Lọt top 3 tuần để nhận huân chương 🏅")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                } else {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(awards.enumerated()), id: \.offset) { index, award in
                            timelineRow(award, last: index == awards.count - 1)
                        }
                    }
                }
            }
            .padding(12)
            .background(card.fill(Color(.secondarySystemGroupedBackground)))
        }
    }

    private var countsFromAwards: Medals {
        Medals(gold: awards.filter { $0.rank == 1 }.count,
               silver: awards.filter { $0.rank == 2 }.count,
               bronze: awards.filter { $0.rank == 3 }.count)
    }

    private func timelineRow(_ award: WeeklyAward, last: Bool) -> some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(spacing: 0) {
                Text(award.medal)
                    .font(.title3)
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(color(for: award.rank).opacity(0.18)))
                if !last {
                    Rectangle()
                        .fill(Color(.separator))
                        .frame(width: 2)
                        .frame(minHeight: 14)
                }
            }
            Text("Hạng \(award.rank) · \(SocialFormat.week(start: award.weekStart, end: award.weekEnd).replacingOccurrences(of: " – ", with: "–")) · \(award.sentences) câu")
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 6)
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }

    private func color(for rank: Int) -> Color {
        switch rank {
        case 1: return medalGold
        case 2: return medalSilver
        default: return medalBronze
        }
    }
}

/// Ô đếm huân chương có vệt sáng lướt qua (tắt khi giảm chuyển động hoặc chưa có huân chương).
private struct MedalCount: View {
    let emoji: String
    let count: Int
    let label: String
    let color: Color
    let delay: Double

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)

    var body: some View {
        VStack(spacing: 2) {
            Text(emoji)
                .font(.system(size: 30))
                .grayscale(count > 0 ? 0 : 1)
                .opacity(count > 0 ? 1 : 0.45)
            Text("\(count)")
                .font(.title3.weight(.bold))
                .monospacedDigit()
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(shape.fill(count > 0 ? color.opacity(0.14) : Color(.tertiarySystemFill)))
        .overlay {
            if count > 0, !reduceMotion {
                TimelineView(.animation(minimumInterval: 1 / 30)) { timeline in
                    shine(at: timeline.date.timeIntervalSinceReferenceDate)
                }
                .clipShape(shape)
                .allowsHitTesting(false)
            }
        }
        .overlay(shape.strokeBorder(count > 0 ? color.opacity(0.5) : .clear, lineWidth: 1))
        .accessibilityElement(children: .combine)
    }

    /// Vệt sáng chéo chạy qua mỗi 3 giây.
    private func shine(at time: Double) -> some View {
        let cycle: Double = 3
        let phase: Double = ((time + delay).truncatingRemainder(dividingBy: cycle)) / cycle
        let progress: CGFloat = CGFloat(min(1, phase / 0.35))
        return GeometryReader { geo in
            let width: CGFloat = geo.size.width
            LinearGradient(colors: [.clear, .white.opacity(0.55), .clear], startPoint: .leading, endPoint: .trailing)
                .frame(width: width * 0.35)
                .rotationEffect(.degrees(20))
                .offset(x: -width * 0.5 + (width * 1.5) * progress)
                .opacity(phase < 0.35 ? 1 : 0)
        }
    }
}
