import SimpleVectorCore
import SwiftUI

struct SectionHeader: View {
    let title: String
    var trailing: AnyView? = nil

    init(_ title: String) {
        self.title = title
        self.trailing = nil
    }

    init<V: View>(_ title: String, @ViewBuilder trailing: () -> V) {
        self.title = title
        self.trailing = AnyView(trailing())
    }

    var body: some View {
        HStack {
            Text(title)
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(Theme.textDim.swiftUI)
                .tracking(0.6)
                .textCase(.uppercase)
            Spacer()
            if let trailing { trailing }
        }
        .padding(.bottom, 2)
    }
}

struct FieldRow<Content: View>: View {
    let label: String
    var width: CGFloat = 96
    let content: Content

    init(_ label: String, width: CGFloat = 96, @ViewBuilder content: () -> Content) {
        self.label = label
        self.width = width
        self.content = content()
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(label)
                .font(.system(size: 11.5))
                .foregroundStyle(Theme.textDim.swiftUI)
                .frame(width: width, alignment: .leading)
            content
            Spacer(minLength: 0)
        }
    }
}

struct CommitField: View {
    let value: String
    var placeholder: String = ""
    var monospaced: Bool = false
    var onCommit: (String) -> Void
    var onSubmit: ((String) -> Void)? = nil

    @State private var text: String
    @FocusState private var focused: Bool

    init(
        value: String,
        placeholder: String = "",
        monospaced: Bool = false,
        onCommit: @escaping (String) -> Void,
        onSubmit: ((String) -> Void)? = nil
    ) {
        self.value = value
        self.placeholder = placeholder
        self.monospaced = monospaced
        self.onCommit = onCommit
        self.onSubmit = onSubmit
        self._text = State(initialValue: value)
    }

    var body: some View {
        TextField(placeholder, text: $text)
            .textFieldStyle(.plain)
            .font(.system(size: 11.5, design: monospaced ? .monospaced : .default))
            .foregroundStyle(Theme.text.swiftUI)
            .focused($focused)
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 5)
                    .fill(Color.white.opacity(0.05))
                    .overlay(
                        RoundedRectangle(cornerRadius: 5)
                            .strokeBorder(focused ? Theme.accent.swiftUI.opacity(0.6) : Color.white.opacity(0.08), lineWidth: 1)
                    )
            )
            .animation(.easeOut(duration: 0.15), value: focused)
            .onAppear { text = value }
            .onChange(of: value) { _, newValue in if !focused { text = newValue } }
            .onSubmit { onCommit(text); onSubmit?(text) }
            .onChange(of: focused) { _, isFocused in
                if !isFocused && text != value { onCommit(text) }
            }
    }
}

struct IconButton: View {
    let symbol: String
    var helpText: String = ""
    var active: Bool = false
    var tint: Color = Theme.accent.swiftUI
    var disabled: Bool = false
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(disabled ? Theme.textFaint.swiftUI : (active ? Theme.background.swiftUI : Theme.text.swiftUI))
                .frame(width: 26, height: 24)
                .background(
                    RoundedRectangle(cornerRadius: 5)
                        .fill(active ? tint : Color.white.opacity(disabled ? 0.02 : (hovering ? 0.1 : 0.06)))
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .help(helpText)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
    }
}

struct TextButton: View {
    let title: String
    var symbol: String? = nil
    var prominent: Bool = false
    var destructive: Bool = false
    var tint: Color? = nil
    var compact: Bool = false
    var disabled: Bool = false
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        let activeColor = tint ?? (destructive ? Theme.danger.swiftUI : Theme.accent.swiftUI)
        Button(action: action) {
            HStack(spacing: 5) {
                if let symbol {
                    Image(systemName: symbol)
                        .font(.system(size: compact ? 10.5 : 11, weight: .semibold))
                }
                Text(title)
                    .font(.system(size: compact ? 11 : 11.5, weight: prominent || destructive ? .semibold : .medium))
                    .lineLimit(1)
            }
            .fixedSize(horizontal: true, vertical: false)
            .foregroundStyle(
                disabled ? Theme.textFaint.swiftUI
                    : (prominent || destructive ? Theme.background.swiftUI : (tint ?? Theme.text.swiftUI))
            )
            .padding(.horizontal, compact ? 8 : 11)
            .padding(.vertical, compact ? 4 : 5)
            .background(
                RoundedRectangle(cornerRadius: 5)
                    .fill(
                        prominent || destructive ? activeColor.opacity(disabled ? 0.35 : (hovering ? 0.9 : 1))
                            : (tint != nil ? activeColor.opacity(hovering ? 0.22 : 0.14) : Color.white.opacity(disabled ? 0.02 : (hovering ? 0.11 : 0.07)))
                    )
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
    }
}

struct Chip: View {
    let text: String
    var tint: Color = Theme.textDim.swiftUI
    var filled: Bool = false

    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold, design: .monospaced))
            .foregroundStyle(filled ? Theme.background.swiftUI : tint)
            .padding(.horizontal, 5.5)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: 3.5)
                    .fill(filled ? tint : tint.opacity(0.14))
            )
            .lineLimit(1)
    }
}

struct ActionChip: View {
    let text: String
    var tint: Color = Theme.textDim.swiftUI
    var active: Bool = false
    var help: String = ""
    var action: (() -> Void)? = nil

    @State private var hovering = false

    var body: some View {
        if let action {
            Button(action: action) {
                Chip(text: text, tint: tint, filled: active || hovering)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(help)
            .onHover { inside in
                hovering = inside
            }
            .animation(.easeOut(duration: 0.12), value: hovering)
        } else {
            Chip(text: text, tint: tint, filled: active).help(help)
        }
    }
}

/// Hero illustration for SimpleVector (About sheet, Update sheet, Welcome screen):
/// stacked multipage vector sheets with a Bezier curve, tangent handles, and calligraphic signature flourish.
struct VectorHeroGraphic: View {
    var active: Bool = false
    var size: CGFloat = 120

    var body: some View {
        Canvas { ctx, s in
            let w = s.width
            let h = s.height

            // Outer ring
            let ringRect = CGRect(x: 6, y: 6, width: w - 12, height: h - 12)
            ctx.stroke(Path(ellipseIn: ringRect), with: .color(Theme.accent.swiftUI.opacity(0.22)), lineWidth: 1.2)

            // Back page (multipage stack)
            let backPage = CGRect(x: w * 0.28, y: h * 0.16, width: w * 0.50, height: h * 0.62)
            ctx.fill(Path(roundedRect: backPage, cornerRadius: 5), with: .color(Theme.laneAlt.swiftUI))
            ctx.stroke(Path(roundedRect: backPage, cornerRadius: 5), with: .color(Theme.tcp.swiftUI.opacity(0.45)), lineWidth: 1.1)

            // Front page
            let frontPage = CGRect(x: w * 0.20, y: h * 0.22, width: w * 0.52, height: h * 0.64)
            ctx.fill(Path(roundedRect: frontPage, cornerRadius: 5), with: .color(Theme.panel.swiftUI))
            ctx.stroke(Path(roundedRect: frontPage, cornerRadius: 5), with: .color(Theme.accent.swiftUI.opacity(0.75)), lineWidth: 1.4)

            // Editable PDF text lines on front page
            for (idx, frac) in [0.40, 0.32, 0.36].enumerated() {
                let ly = frontPage.minY + CGFloat(idx + 1) * (frontPage.height * 0.13)
                let rect = CGRect(x: frontPage.minX + 8, y: ly, width: frontPage.width * CGFloat(frac), height: 3.0)
                ctx.fill(Path(roundedRect: rect, cornerRadius: 1.5), with: .color(idx == 0 ? Theme.tcp.swiftUI : Theme.textDim.swiftUI.opacity(0.65)))
            }

            // Sweeping Bezier curve + signature flourish
            var bezier = Path()
            let p0 = CGPoint(x: frontPage.minX + 8, y: frontPage.maxY - 14)
            let p1 = CGPoint(x: frontPage.maxX - 8, y: frontPage.midY + 4)
            let c1 = CGPoint(x: frontPage.minX + 18, y: frontPage.midY - 8)
            let c2 = CGPoint(x: frontPage.maxX - 20, y: frontPage.maxY - 4)
            bezier.move(to: p0)
            bezier.addCurve(to: p1, control1: c1, control2: c2)
            ctx.stroke(bezier, with: .color(Theme.accent.swiftUI), style: StrokeStyle(lineWidth: 2.4, lineCap: .round))

            // Tangent handles
            var handles = Path()
            handles.move(to: p0)
            handles.addLine(to: c1)
            handles.move(to: p1)
            handles.addLine(to: c2)
            ctx.stroke(handles, with: .color(Theme.alive.swiftUI.opacity(0.75)), style: StrokeStyle(lineWidth: 1.0, dash: [2, 2]))

            for pt in [p0, p1, c1, c2] {
                let nodeRect = CGRect(x: pt.x - 2.5, y: pt.y - 2.5, width: 5, height: 5)
                ctx.fill(Path(ellipseIn: nodeRect), with: .color(Theme.alive.swiftUI))
            }
        }
        .frame(width: size, height: size)
    }
}
