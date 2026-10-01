import AppKit
import SwiftUI

struct MarkdownView: View {
    let source: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(MarkdownBlocks.parse(source).enumerated()), id: \.offset) { _, block in
                blockView(block)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .textSelection(.enabled)
    }

    @ViewBuilder
    private func blockView(_ block: MarkdownBlock) -> some View {
        switch block {
        case .paragraph(let text):
            inline(text)
                .frame(maxWidth: .infinity, alignment: .leading)
        case .heading(let level, let text):
            inline(text)
                .font(level <= 2 ? .title3 : .headline)
                .fontWeight(.semibold)
                .padding(.top, level <= 2 ? 3 : 0)
                .frame(maxWidth: .infinity, alignment: .leading)
        case .listItem(let marker, let indent, let text):
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(marker)
                    .frame(width: 24, alignment: .trailing)
                inline(text)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.leading, min(CGFloat(indent) * 6, 48))
        case .quote(let text):
            HStack(alignment: .top, spacing: 10) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.accentColor)
                    .frame(width: 3)
                inline(text)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.vertical, 3)
        case .code(let language, let text):
            VStack(alignment: .leading, spacing: 7) {
                if !language.isEmpty {
                    Text(language)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                ScrollView(.horizontal) {
                    Text(text.isEmpty ? " " : text)
                        .font(.system(.body, design: .monospaced))
                        .fixedSize(horizontal: true, vertical: true)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(nsColor: .textBackgroundColor).opacity(0.7))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        case .table(let headers, let rows):
            ScrollView(.horizontal) {
                VStack(alignment: .leading, spacing: 0) {
                    tableRow(headers, header: true)
                    Divider()
                    ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                        tableRow(row, header: false)
                        Divider()
                    }
                }
                .background(Color(nsColor: .textBackgroundColor).opacity(0.7))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        case .rule:
            Divider()
        }
    }

    private func tableRow(_ cells: [String], header: Bool) -> some View {
        HStack(alignment: .top, spacing: 0) {
            ForEach(cells.indices, id: \.self) { index in
                inline(cells[index])
                    .fontWeight(header ? .semibold : .regular)
                    .frame(width: 150, alignment: .leading)
                    .padding(8)
                if index < cells.count - 1 { Divider() }
            }
        }
    }

    private func inline(_ source: String) -> Text {
        let options = AttributedString.MarkdownParsingOptions(
            interpretedSyntax: .inlineOnlyPreservingWhitespace
        )
        let styled = (try? AttributedString(markdown: source, options: options)) ?? AttributedString(source)
        return Text(styled)
    }
}
