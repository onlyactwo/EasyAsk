import Foundation

enum MarkdownBlock: Equatable {
    case paragraph(String)
    case heading(level: Int, text: String)
    case listItem(marker: String, indent: Int, text: String)
    case quote(String)
    case code(language: String, text: String)
    case table(headers: [String], rows: [[String]])
    case rule
}

enum MarkdownBlocks {
    static func parse(_ source: String) -> [MarkdownBlock] {
        let lines = source.replacingOccurrences(of: "\r\n", with: "\n")
            .components(separatedBy: "\n")
        var blocks: [MarkdownBlock] = []
        var index = 0

        while index < lines.count {
            let line = lines[index]
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { index += 1; continue }

            if let fence = fenceStart(trimmed) {
                index += 1
                var code: [String] = []
                while index < lines.count {
                    let candidate = lines[index].trimmingCharacters(in: .whitespaces)
                    if candidate.hasPrefix(fence.marker) {
                        index += 1
                        break
                    }
                    code.append(lines[index])
                    index += 1
                }
                blocks.append(.code(language: fence.language, text: code.joined(separator: "\n")))
                continue
            }

            if index + 1 < lines.count,
               let headers = tableCells(line),
               let separator = tableCells(lines[index + 1]),
               headers.count == separator.count,
               separator.allSatisfy(isTableSeparator) {
                index += 2
                var rows: [[String]] = []
                while index < lines.count,
                      let cells = tableCells(lines[index]),
                      cells.count == headers.count {
                    rows.append(cells)
                    index += 1
                }
                blocks.append(.table(headers: headers, rows: rows))
                continue
            }

            if let heading = heading(line) {
                blocks.append(.heading(level: heading.level, text: heading.text))
                index += 1
                continue
            }

            if isRule(trimmed) {
                blocks.append(.rule)
                index += 1
                continue
            }

            if trimmed.hasPrefix(">") {
                var quoted: [String] = []
                while index < lines.count {
                    let next = lines[index].trimmingCharacters(in: .whitespaces)
                    guard next.hasPrefix(">") else { break }
                    quoted.append(String(next.dropFirst()).trimmingCharacters(in: .whitespaces))
                    index += 1
                }
                blocks.append(.quote(quoted.joined(separator: "\n")))
                continue
            }

            if let item = listItem(line) {
                blocks.append(.listItem(marker: item.marker, indent: item.indent, text: item.text))
                index += 1
                continue
            }

            var paragraph = [line]
            index += 1
            while index < lines.count {
                let next = lines[index]
                let nextTrimmed = next.trimmingCharacters(in: .whitespaces)
                if nextTrimmed.isEmpty || fenceStart(nextTrimmed) != nil ||
                    heading(next) != nil || isRule(nextTrimmed) ||
                    nextTrimmed.hasPrefix(">") || listItem(next) != nil ||
                    (index + 1 < lines.count && tableCells(next) != nil &&
                     tableCells(lines[index + 1])?.allSatisfy(isTableSeparator) == true) {
                    break
                }
                paragraph.append(next)
                index += 1
            }
            blocks.append(.paragraph(paragraph.joined(separator: " ")))
        }
        return blocks
    }

    private static func fenceStart(_ line: String) -> (marker: String, language: String)? {
        for marker in ["```", "~~~"] where line.hasPrefix(marker) {
            return (marker, String(line.dropFirst(marker.count)).trimmingCharacters(in: .whitespaces))
        }
        return nil
    }

    private static func heading(_ line: String) -> (level: Int, text: String)? {
        let text = line.trimmingCharacters(in: .whitespaces)
        let level = text.prefix(while: { $0 == "#" }).count
        guard (1...6).contains(level), text.dropFirst(level).first == " " else { return nil }
        return (level, String(text.dropFirst(level + 1)))
    }

    private static func isRule(_ line: String) -> Bool {
        let compact = line.filter { !$0.isWhitespace }
        guard compact.count >= 3, let first = compact.first,
              first == "-" || first == "*" || first == "_" else { return false }
        return compact.allSatisfy { $0 == first }
    }

    private static func listItem(_ line: String) -> (marker: String, indent: Int, text: String)? {
        let indent = line.prefix(while: { $0 == " " }).count
        let content = String(line.dropFirst(indent))
        if let first = content.first, "-+*".contains(first),
           content.dropFirst().first?.isWhitespace == true {
            return ("•", indent, String(content.dropFirst(2)))
        }
        let digits = content.prefix(while: { $0.isNumber })
        guard !digits.isEmpty else { return nil }
        let rest = content.dropFirst(digits.count)
        guard rest.first == "." || rest.first == ")",
              rest.dropFirst().first?.isWhitespace == true else { return nil }
        return (String(digits) + ".", indent, String(rest.dropFirst(2)))
    }

    private static func tableCells(_ line: String) -> [String]? {
        var content = line.trimmingCharacters(in: .whitespaces)
        guard content.contains("|") else { return nil }
        if content.hasPrefix("|") { content.removeFirst() }
        if content.hasSuffix("|") { content.removeLast() }
        return content.split(separator: "|", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
    }

    private static func isTableSeparator(_ cell: String) -> Bool {
        let dashes = cell.filter { $0 == "-" }
        return dashes.count >= 3 && cell.allSatisfy { $0 == "-" || $0 == ":" }
    }
}
