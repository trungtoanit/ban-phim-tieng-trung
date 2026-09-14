//
//  RubyText.swift
//  Hiển thị pinyin thẳng hàng phía trên từng từ chữ Hán (và âm Hán Việt bên dưới), tự xuống dòng.
//

import SwiftUI

struct RubyText: View {
    let words: [PinyinWord]
    var hanziSize: CGFloat = 20
    var hanziWeight: Font.Weight = .medium
    var pinyinColor: Color = .secondary
    var showHanViet = SharedSettings.showHanViet
    /// Chạm vào một từ (nghe phát âm, xem nghĩa).
    var onTapWord: ((PinyinWord) -> Void)?

    private let flaggedColor = Color.red

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
        let hanViet = showHanViet ? word.hv : nil

        return HStack(alignment: .top, spacing: 0) {
            // Dấu câu đứng ngoài cột để pinyin căn giữa đúng trên chữ Hán.
            VStack(spacing: 0) {
                Text(word.py.trimmingCharacters(in: .punctuationCharacters))
                    .font(.system(size: hanziSize * 0.6))
                    .foregroundColor(flagged ? flaggedColor : pinyinColor)
                Text(parts.core)
                    .font(.system(size: hanziSize, weight: hanziWeight))
                    .foregroundColor(flagged ? flaggedColor : .primary)
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
                    Text(parts.trailing).font(.system(size: hanziSize, weight: hanziWeight))
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
