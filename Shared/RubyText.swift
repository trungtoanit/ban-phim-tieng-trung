//
//  RubyText.swift
//  Hiển thị pinyin thẳng hàng phía trên từng từ chữ Hán (và âm Hán Việt bên dưới), tự xuống dòng.
//

import SwiftUI
import UIKit

struct RubyText: View {
    let words: [PinyinWord]
    var hanziSize: CGFloat = 20
    var hanziWeight: Font.Weight = .medium
    /// Pinyin xanh duong giong trang web (#1899d6; sang hon o che do toi).
    var pinyinColor: Color = RubyText.pinyinBlue
    /// Màu chữ Hán khi từ không bị đánh dấu — đổi được để dùng ở dải "đang nghe".
    var hanziColor: Color = .primary
    var showHanViet = SharedSettings.showHanViet
    /// Tô xanh những từ đã đọc đúng. Chỉ bật khi đang chấm trực tiếp lúc đọc;
    /// chỗ khác `flagged == false` chỉ có nghĩa "không sao", không phải "vừa đọc đúng".
    var showsCorrect = false
    /// Chạm vào một từ (nghe phát âm, xem nghĩa).
    var onTapWord: ((PinyinWord) -> Void)?

    static let pinyinBlue = Color(uiColor: UIColor { trait in
        trait.userInterfaceStyle == .dark
            ? UIColor(red: 0.35, green: 0.72, blue: 0.98, alpha: 1)
            : UIColor(red: 0.09, green: 0.60, blue: 0.84, alpha: 1)
    })
    private let flaggedColor = Color.red
    /// Xanh lá đậm trên nền sáng, nhạt hơn trên nền tối cho đủ tương phản.
    private let correctColor = Color(uiColor: UIColor { trait in
        trait.userInterfaceStyle == .dark
            ? UIColor(red: 0.36, green: 0.84, blue: 0.47, alpha: 1)
            : UIColor(red: 0.13, green: 0.58, blue: 0.27, alpha: 1)
    })

    var body: some View {
        FlowLayout(spacing: hanziSize * 0.35, lineSpacing: hanziSize * 0.25) {
            ForEach(Array(words.enumerated()), id: \.offset) { _, word in
                wordView(word)
            }
        }
    }

    private func wordView(_ word: PinyinWord) -> some View {
        let parts = Self.splitPunctuation(word.zh)
        let flagged = word.flagged == true
        let correct = showsCorrect && word.flagged == false
        let hanViet = showHanViet ? word.hv : nil

        return HStack(alignment: .top, spacing: 0) {
            // Dấu câu đứng ngoài cột để pinyin căn giữa đúng trên chữ Hán.
            VStack(spacing: 0) {
                Text(word.py.trimmingCharacters(in: .punctuationCharacters))
                    .font(.system(size: hanziSize * 0.6))
                    .foregroundColor(flagged ? flaggedColor : (correct ? correctColor : pinyinColor))
                Text(parts.core)
                    .font(.system(size: hanziSize, weight: hanziWeight))
                    .foregroundColor(flagged ? flaggedColor : (correct ? correctColor : hanziColor))
                    .underline(flagged, color: flaggedColor)
                if let hanViet {
                    Text(hanViet)
                        .font(.system(size: hanziSize * 0.5))
                        .foregroundColor(Color(red: 0.55, green: 0.35, blue: 0.2))
                }
            }
            if !parts.trailing.isEmpty {
                VStack(spacing: 0) {
                    Text(" ").font(.system(size: hanziSize * 0.6))
                    Text(parts.trailing)
                        .font(.system(size: hanziSize, weight: hanziWeight))
                        .foregroundColor(flagged ? flaggedColor : (correct ? correctColor : hanziColor))
                }
            }
        }
        .lineLimit(1)
        .fixedSize()
        .contentShape(Rectangle())
        .onTapGesture {
            onTapWord?(word)
        }
        .allowsHitTesting(onTapWord != nil)
    }

    static func splitPunctuation(_ text: String) -> (core: String, trailing: String) {
        let core = text.trimmingCharacters(in: .punctuationCharacters.union(.symbols))
        guard !core.isEmpty, let range = text.range(of: core) else { return (text, "") }
        return (core, String(text[range.upperBound...]))
    }
}

/// Xếp các phần tử theo hàng, hết chỗ thì xuống dòng.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6
    var lineSpacing: CGFloat = 4

    /// Sai số làm tròn điểm ảnh: bề rộng khi đặt có thể nhỏ hơn bề rộng đã đo một chút.
    private let tolerance: CGFloat = 1

    private struct Row {
        var items: [(index: Int, size: CGSize)] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    /// Chia hàng theo bề rộng tối đa — dùng chung cho đo và đặt để hai bước luôn khớp nhau.
    private func rows(for subviews: Subviews, maxWidth: CGFloat) -> [Row] {
        var rows: [Row] = []
        var current = Row()
        for (index, subview) in subviews.enumerated() {
            let size = subview.sizeThatFits(.unspecified)
            let proposedWidth = current.items.isEmpty ? size.width : current.width + spacing + size.width
            if !current.items.isEmpty, proposedWidth > maxWidth + tolerance {
                rows.append(current)
                current = Row()
            }
            current.width = current.items.isEmpty ? size.width : current.width + spacing + size.width
            current.height = max(current.height, size.height)
            current.items.append((index, size))
        }
        if !current.items.isEmpty { rows.append(current) }
        return rows
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        let rows = rows(for: subviews, maxWidth: maxWidth)
        let width = rows.map(\.width).max() ?? 0
        let height = rows.map(\.height).reduce(0, +) + lineSpacing * CGFloat(max(rows.count - 1, 0))
        return CGSize(width: ceil(min(width, maxWidth)), height: ceil(height))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in rows(for: subviews, maxWidth: bounds.width) {
            var x = bounds.minX
            for item in row.items {
                subviews[item.index].place(at: CGPoint(x: x, y: y), anchor: .topLeading, proposal: ProposedViewSize(item.size))
                x += item.size.width + spacing
            }
            y += row.height + lineSpacing
        }
    }
}
