import SwiftUI

#if os(macOS)
private let systemGray4 = Color(nsColor: .separatorColor)
private let systemGray5 = Color(nsColor: .controlBackgroundColor)
private let systemGray6 = Color(nsColor: .textBackgroundColor)
#else
private let systemGray4 = Color(.systemGray4)
private let systemGray5 = Color(.systemGray5)
private let systemGray6 = Color(.systemGray6)
#endif

public struct MarkdownRendererView: View {
    let text: String

    public init(text: String) {
        self.text = text
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(parseBlocks().enumerated()), id: \.offset) { _, block in
                switch block {
                case .code(let content, let language):
                    CodeBlockView(content: content, language: language)
                case .text(let content):
                    InlineMarkdownView(content: content)
                }
            }
        }
    }

    private enum Block {
        case code(String, language: String?)
        case text(String)
    }

    private func parseBlocks() -> [Block] {
        var blocks: [Block] = []
        var lines = text.components(separatedBy: "\n")
        var i = 0
        while i < lines.count {
            let line = lines[i]
            if line.hasPrefix("```") {
                let language = line.dropFirst(3).trimmingCharacters(in: .whitespaces)
                let lang = language.isEmpty ? nil : language
                var codeLines: [String] = []
                i += 1
                while i < lines.count {
                    if lines[i].hasPrefix("```") {
                        break
                    }
                    codeLines.append(lines[i])
                    i += 1
                }
                blocks.append(.code(codeLines.joined(separator: "\n"), language: lang))
                i += 1
            } else {
                blocks.append(.text(line))
                i += 1
            }
        }
        return blocks
    }
}

private struct InlineMarkdownView: View {
    let content: String

    var body: some View {
        if content.isEmpty {
            EmptyView()
        } else if content.hasPrefix("### ") {
            Text(String(content.dropFirst(4)))
                .font(.title3).bold()
                .frame(maxWidth: .infinity, alignment: .leading)
        } else if content.hasPrefix("## ") {
            Text(String(content.dropFirst(3)))
                .font(.title2).bold()
                .frame(maxWidth: .infinity, alignment: .leading)
        } else if content.hasPrefix("# ") {
            Text(String(content.dropFirst(2)))
                .font(.title).bold()
                .frame(maxWidth: .infinity, alignment: .leading)
        } else if content.hasPrefix("- ") || content.hasPrefix("* ") {
            HStack(alignment: .top, spacing: 4) {
                Text("\u{2022}")
                parsedText(String(content.dropFirst(2)))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else if content.range(of: "^\\d+\\.\\s", options: .regularExpression) != nil {
            HStack(alignment: .top, spacing: 4) {
                Text(content.prefix(while: { $0 != "." })).font(.body).bold()
                Text(".")
                parsedText(String(content.drop(while: { $0 != " " }).dropFirst()))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            parsedText(content)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private func parsedText(_ text: String) -> some View {
        if text.contains("**") || text.contains("__") || text.contains("`") || text.contains("[") {
            InlineStyledText(text)
        } else {
            Text(text)
                .font(.body)
        }
    }
}

private struct InlineStyledText: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        let segments = parseInline(text)
        segments.reduce(Text("")) { partial, segment in
            partial + segment
        }
        .font(.body)
    }

    private func parseInline(_ input: String) -> [Text] {
        var result: [Text] = []
        var remaining = input
        while !remaining.isEmpty {
            if let boldRange = remaining.range(of: #"\*\*(.+?)\*\*|__(.+?)__"#, options: .regularExpression) {
                let prefix = String(remaining[remaining.startIndex..<boldRange.lowerBound])
                if !prefix.isEmpty { result.append(Text(prefix)) }
                let matched = remaining[boldRange]
                let inner = String(matched.dropFirst(2).dropLast(2))
                result.append(Text(inner).bold())
                remaining = String(remaining[boldRange.upperBound...])
            } else if let codeRange = remaining.range(of: #"`([^`]+)`"#, options: .regularExpression) {
                let prefix = String(remaining[remaining.startIndex..<codeRange.lowerBound])
                if !prefix.isEmpty { result.append(Text(prefix)) }
                let matched = remaining[codeRange]
                let inner = String(matched.dropFirst().dropLast())
                result.append(Text(inner)
                    .font(.system(.body, design: .monospaced))
                    .foregroundColor(.blue))
                remaining = String(remaining[codeRange.upperBound...])
            } else {
                result.append(Text(remaining))
                break
            }
        }
        return result
    }
}

private struct CodeBlockView: View {
    let content: String
    let language: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let lang = language, !lang.isEmpty {
                Text(lang.uppercased())
                    .font(.caption2).bold()
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(systemGray5)
                    .cornerRadius(4)
            }
            ScrollView(.horizontal, showsIndicators: true) {
                Text(content)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
        }
        .padding(10)
        .background(systemGray6)
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(systemGray4, lineWidth: 0.5)
        )
    }
}
