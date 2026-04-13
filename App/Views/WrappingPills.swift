import SwiftUI

struct WrappingPillsLayoutHelper {
    static func wrappedRows(widths: [CGFloat], maxWidth: CGFloat, spacing: CGFloat) -> [[Int]] {
        guard maxWidth > 0 else { return [Array(widths.indices)] }
        var rows: [[Int]] = [[]]
        var currentRowWidth: CGFloat = 0

        for index in widths.indices {
            let width = widths[index]
            let nextWidth = rows[rows.count - 1].isEmpty ? width : currentRowWidth + spacing + width
            if nextWidth <= maxWidth || rows[rows.count - 1].isEmpty {
                rows[rows.count - 1].append(index)
                currentRowWidth = nextWidth
            } else {
                rows.append([index])
                currentRowWidth = width
            }
        }

        return rows
    }
}

struct WrappingPillsFlowLayout: Layout {
    var spacing: CGFloat = 8
    var rowSpacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .greatestFiniteMagnitude
        let rows = layoutRows(maxWidth: maxWidth, subviews: subviews)
        let width = min(maxWidth, rows.map { row in
            row.reduce(0) { partial, index in
                let size = subviews[index].sizeThatFits(.unspecified)
                return partial == 0 ? size.width : partial + spacing + size.width
            }
        }.max() ?? 0)
        let height = rows.reduce(CGFloat(0)) { partial, row in
            let rowHeight = row.map { subviews[$0].sizeThatFits(.unspecified).height }.max() ?? 0
            return partial == 0 ? rowHeight : partial + rowSpacing + rowHeight
        }
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let rows = layoutRows(maxWidth: bounds.width, subviews: subviews)
        var y = bounds.minY

        for row in rows {
            var x = bounds.minX
            let rowHeight = row.map { subviews[$0].sizeThatFits(.unspecified).height }.max() ?? 0
            for index in row {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(
                    at: CGPoint(x: x, y: y),
                    proposal: ProposedViewSize(width: size.width, height: rowHeight)
                )
                x += size.width + spacing
            }
            y += rowHeight + rowSpacing
        }
    }

    private func layoutRows(maxWidth: CGFloat, subviews: Subviews) -> [[Int]] {
        let widths = subviews.map { $0.sizeThatFits(.unspecified).width }
        return WrappingPillsLayoutHelper.wrappedRows(widths: widths, maxWidth: maxWidth, spacing: spacing)
    }
}

struct WrappingPills<Option: Hashable>: View {
    let options: [Option]
    @Binding var selection: Option
    let title: (Option) -> String
    var isDisabled: (Option) -> Bool = { _ in false }
    var helpText: (Option) -> String? = { _ in nil }

    var body: some View {
        WrappingPillsFlowLayout(spacing: 8, rowSpacing: 8) {
            ForEach(options, id: \.self) { option in
                Button {
                    selection = option
                } label: {
                    Text(title(option))
                        .lineLimit(1)
                        .padding(.horizontal, 12)
                        .frame(height: 30)
                        .background(selection == option ? Color.accentColor.opacity(0.18) : Color(nsColor: .controlBackgroundColor))
                        .overlay(
                            Capsule()
                                .stroke(selection == option ? Color.accentColor : Color(nsColor: .separatorColor), lineWidth: 1)
                        )
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .disabled(isDisabled(option))
                .help(helpText(option) ?? "")
            }
        }
    }
}
