import GemmaKit
import SwiftMath
import SwiftUI
import UIKit

/// Renders a chat answer: block structure from `MarkdownParser`, inline styling from AttributedString.
struct MarkdownText: View {
    let text: String

    var body: some View {
        let blocks = MarkdownParser.parse(text)
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                BlockView(block: block)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct BlockView: View {
    let block: MarkdownBlock

    var body: some View {
        switch block {
        case .paragraph(let text):
            Text(inline(text))
        case .heading(let level, let text):
            Text(inline(text))
                .font(level == 1 ? .title2.bold() : level == 2 ? .title3.bold() : .headline)
        case .code(let language, let code, _):
            CodeBlockView(language: language, code: code)
        case .listItem(let marker, let text, let indent):
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                switch marker {
                case .bullet: Text("•")
                case .number(let n): Text("\(n).").monospacedDigit()
                }
                Text(inline(text))
            }
            .padding(.leading, CGFloat(indent) * 16)
        case .quote(let text):
            Text(inline(text))
                .foregroundStyle(.secondary)
                .padding(.leading, 10)
                .overlay(alignment: .leading) {
                    Rectangle().fill(.tertiary).frame(width: 3)
                }
        case .table(let header, let rows):
            TableBlockView(header: header, rows: rows)
        case .rule:
            Divider()
        case .math(let latex):
            MathBlockView(latex: latex)
        }
    }
}

/// Inline Markdown (bold, italics, `code`, links); inline LaTeX becomes Unicode first (`$\pi r^2$` → πr²),
/// so its `_` / `^` / `*` are never read as Markdown. Falls back to plain text on parse errors.
func inline(_ text: String) -> AttributedString {
    let text = LaTeX.replacingInlineMath(in: text)
    let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace, failurePolicy: .returnPartiallyParsedIfPossible)
    return (try? AttributedString(markdown: text, options: options)) ?? AttributedString(text)
}

/// A display formula typeset with SwiftMath (fractions, roots, sub/superscripts like real LaTeX).
/// Falls back to the Unicode rendering when SwiftMath cannot parse the source.
private struct MathBlockView: View {
    let latex: String
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        if MathBlockView.canTypeset(latex) {
            ScrollView(.horizontal, showsIndicators: false) {
                MathLabel(latex: latex, fontSize: UIFont.preferredFont(forTextStyle: .body).pointSize * 1.15)
                    .padding(.vertical, 4)
                    .id(colorScheme) // re-render text colour on appearance change
            }
            .accessibilityElement()
            .accessibilityLabel(LaTeX.toUnicode(latex))
        } else {
            Text(LaTeX.toUnicode(latex))
                .font(.body.italic())
                .textSelection(.enabled)
        }
    }

    static func canTypeset(_ latex: String) -> Bool {
        var error: NSError?
        _ = MTMathListBuilder.build(fromString: latex, error: &error)
        return error == nil
    }
}

private struct MathLabel: UIViewRepresentable {
    let latex: String
    let fontSize: CGFloat

    func makeUIView(context: Context) -> MTMathUILabel {
        let label = MTMathUILabel()
        label.labelMode = .display
        label.textAlignment = .left
        label.setContentHuggingPriority(.required, for: .horizontal)
        label.setContentHuggingPriority(.required, for: .vertical)
        return label
    }

    func updateUIView(_ label: MTMathUILabel, context: Context) {
        label.latex = latex
        label.fontSize = fontSize
        label.textColor = .label
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: MTMathUILabel, context: Context) -> CGSize? {
        uiView.intrinsicContentSize
    }
}

private struct CodeBlockView: View {
    let language: String?
    let code: String
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(language ?? String(localized: "kod"))
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    UIPasteboard.general.string = code
                    copied = true
                    Task {
                        try? await Task.sleep(for: .seconds(1.5))
                        copied = false
                    }
                } label: {
                    Label(copied ? "Skopiowano" : "Kopiuj", systemImage: copied ? "checkmark" : "doc.on.doc")
                        .font(.caption)
                }
                .buttonStyle(.borderless)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(.quaternary.opacity(0.5))

            ScrollView(.horizontal, showsIndicators: false) {
                Text(code)
                    .font(.callout.monospaced())
                    .textSelection(.enabled)
                    .padding(12)
            }
        }
        .background(.quaternary.opacity(0.3), in: .rect(cornerRadius: 10))
        .clipShape(.rect(cornerRadius: 10))
    }
}

private struct TableBlockView: View {
    let header: [String]
    let rows: [[String]]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 6) {
                GridRow {
                    ForEach(Array(header.enumerated()), id: \.offset) { _, cell in
                        Text(inline(cell)).bold()
                    }
                }
                Divider()
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    GridRow {
                        ForEach(Array(row.enumerated()), id: \.offset) { _, cell in
                            Text(inline(cell))
                        }
                    }
                }
            }
            .font(.callout)
            .padding(10)
        }
        .background(.quaternary.opacity(0.3), in: .rect(cornerRadius: 10))
    }
}
