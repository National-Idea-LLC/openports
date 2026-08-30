import SwiftUI

/// Lays subviews out along a line, wrapping to the next one when the next subview would not fit.
///
/// `LazyVGrid`'s adaptive columns give every cell the same width, which is wrong for chips whose
/// width is their own text: "3000" and "com.docker.backend" would be padded to a shared size, or
/// forced onto separate lines. This measures each subview and packs the line instead.
struct WrapLayout: Layout {
    /// Gap between chips on the same line.
    var spacing: CGFloat = 6
    /// Gap between lines. Kept equal to `spacing` by default so the field reads as one block.
    var lineSpacing: CGFloat = 6
    /// `Layout` places subviews in raw coordinates — SwiftUI does not mirror them — so the caller
    /// passes the environment's direction and lines fill from the trailing edge under RTL.
    var layoutDirection: LayoutDirection = .leftToRight

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let lines = lines(within: proposal.width ?? .infinity, subviews: subviews)
        let height = lines.map(\.height).reduce(0, +)
            + lineSpacing * CGFloat(max(lines.count - 1, 0))
        return CGSize(width: lines.map(\.width).max() ?? 0, height: height)
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        var y = bounds.minY
        for line in lines(within: bounds.width, subviews: subviews) {
            var offset: CGFloat = 0 // from the line's leading edge, whichever side that is
            for item in line.items {
                let x = layoutDirection == .rightToLeft
                    ? bounds.maxX - offset - item.size.width
                    : bounds.minX + offset
                subviews[item.index].place(
                    at: CGPoint(x: x, y: y),
                    anchor: .topLeading,
                    proposal: ProposedViewSize(item.size)
                )
                offset += item.size.width + spacing
            }
            y += line.height + lineSpacing
        }
    }

    private struct Line {
        var items: [(index: Int, size: CGSize)] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func lines(within maxWidth: CGFloat, subviews: Subviews) -> [Line] {
        var lines: [Line] = []
        var current = Line()
        for index in subviews.indices {
            let ideal = subviews[index].sizeThatFits(.unspecified)
            // A subview wider than the whole line is clamped rather than allowed to overflow —
            // a long process name truncates inside its chip instead of running off the panel.
            let size = CGSize(width: min(ideal.width, maxWidth), height: ideal.height)
            let lineWidth = current.items.isEmpty ? size.width : current.width + spacing + size.width
            if !current.items.isEmpty, lineWidth > maxWidth {
                lines.append(current)
                current = Line()
            }
            current.width = current.items.isEmpty ? size.width : current.width + spacing + size.width
            current.height = max(current.height, size.height)
            current.items.append((index, size))
        }
        if !current.items.isEmpty { lines.append(current) }
        return lines
    }
}
