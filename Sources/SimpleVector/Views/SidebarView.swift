import SimpleVectorCore
import SwiftUI

struct SidebarView: View {
    @Bindable var model: AppModel

    var body: some View {
        let ctrl = model.controller
        VStack(spacing: 0) {
            // Section 1: Multipage Thumbnails & Navigation
            VStack(alignment: .leading, spacing: 6) {
                SectionHeader(L("Pages (\(ctrl.document.pages.count))", "Pages (\(ctrl.document.pages.count))")) {
                    HStack(spacing: 3) {
                        IconButton(
                            symbol: "plus",
                            helpText: L("Ajouter une page vierge (⇧⌘N)", "Add a blank page (⇧⌘N)")
                        ) {
                            ctrl.addBlankPage()
                        }
                        IconButton(
                            symbol: "plus.square.on.square",
                            helpText: L("Dupliquer la page courante", "Duplicate current page")
                        ) {
                            ctrl.duplicateCurrentPage()
                        }
                        IconButton(
                            symbol: "rotate.right",
                            helpText: L("Pivoter la page de 90°", "Rotate page 90°")
                        ) {
                            ctrl.rotateCurrentPage(clockwise: true)
                        }
                        IconButton(
                            symbol: "trash",
                            helpText: L("Supprimer la page courante", "Delete current page"),
                            disabled: ctrl.document.pages.count <= 1
                        ) {
                            ctrl.deleteCurrentPage()
                        }
                    }
                }
                .padding(.horizontal, 10)
                .padding(.top, 10)

                ScrollView {
                    LazyVStack(spacing: 6) {
                        ForEach(Array(ctrl.document.pages.enumerated()), id: \.element.id) { index, page in
                            PageThumbnailRow(
                                page: page,
                                pageIndex: index,
                                isCurrent: index == ctrl.currentPageIndex,
                                pageCount: ctrl.document.pages.count,
                                onSelect: {
                                    ctrl.currentPageIndex = index
                                    ctrl.selection.removeAll()
                                    model.editingTextElementID = nil
                                },
                                onMoveUp: {
                                    ctrl.currentPageIndex = index
                                    ctrl.moveCurrentPage(offset: -1)
                                },
                                onMoveDown: {
                                    ctrl.currentPageIndex = index
                                    ctrl.moveCurrentPage(offset: 1)
                                }
                            )
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.bottom, 8)
                }
                .frame(height: 248)
            }

            Rectangle().fill(Theme.separator.swiftUI).frame(height: 1)

            // Section 2: Elements & PDF Text Blocks on Current Page
            VStack(alignment: .leading, spacing: 6) {
                SectionHeader(L("Éléments · Page \(ctrl.currentPageIndex + 1)", "Elements · Page \(ctrl.currentPageIndex + 1)")) {
                    Text("\(ctrl.filteredElementsOnCurrentPage.count)")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Theme.textFaint.swiftUI)
                }
                .padding(.horizontal, 10)
                .padding(.top, 10)

                ScrollView {
                    LazyVStack(spacing: 3) {
                        let elements = Array(ctrl.filteredElementsOnCurrentPage.reversed())
                        if elements.isEmpty {
                            Text(L("Aucun élément sur cette page.", "No elements on this page."))
                                .font(.system(size: 11))
                                .foregroundStyle(Theme.textFaint.swiftUI)
                                .padding(12)
                        } else {
                            ForEach(elements) { element in
                                ElementLayerRow(
                                    element: element,
                                    isSelected: ctrl.selection.contains(element.id),
                                    onSelect: {
                                        ctrl.selection = [element.id]
                                        if case .text = element.kind {
                                            model.editingTextElementID = element.id
                                        } else {
                                            model.editingTextElementID = nil
                                        }
                                    },
                                    onToggleVisible: {
                                        ctrl.perform { doc in
                                            VectorOperations.updateElement(id: element.id, onPage: ctrl.currentPageIndex, in: &doc) { el in
                                                el.visible.toggle()
                                            }
                                        }
                                    },
                                    onToggleLock: {
                                        ctrl.perform { doc in
                                            VectorOperations.updateElement(id: element.id, onPage: ctrl.currentPageIndex, in: &doc) { el in
                                                el.locked.toggle()
                                            }
                                        }
                                    }
                                )
                            }
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.bottom, 10)
                }
            }
        }
        .background(Theme.panel.swiftUI)
    }
}

private struct PageThumbnailRow: View {
    let page: VectorPage
    let pageIndex: Int
    let isCurrent: Bool
    let pageCount: Int
    let onSelect: () -> Void
    let onMoveUp: () -> Void
    let onMoveDown: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 9) {
                // Mini vector page preview
                MiniPagePreview(page: page)
                    .frame(width: 40, height: 52)
                    .overlay(
                        RoundedRectangle(cornerRadius: 3)
                            .strokeBorder(isCurrent ? Theme.accent.swiftUI : Color.white.opacity(0.16), lineWidth: isCurrent ? 1.5 : 0.8)
                    )

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 5) {
                        Text("\(pageIndex + 1)")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundStyle(isCurrent ? Theme.background.swiftUI : Theme.textDim.swiftUI)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(
                                Capsule().fill(isCurrent ? Theme.accent.swiftUI : Color.white.opacity(0.08))
                            )
                        Text(page.title)
                            .font(.system(size: 11.5, weight: isCurrent ? .semibold : .medium))
                            .foregroundStyle(Theme.text.swiftUI)
                            .lineLimit(1)
                    }

                    HStack(spacing: 5) {
                        if page.pdfPageData != nil {
                            Chip(text: "PDF", tint: Theme.tcp.swiftUI)
                        } else {
                            Chip(text: "SVG", tint: Theme.alive.swiftUI)
                        }
                        Text("\(page.elements.count) élém.")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(Theme.textFaint.swiftUI)
                    }
                }

                Spacer(minLength: 0)

                if isCurrent && pageCount > 1 {
                    VStack(spacing: 2) {
                        Button(action: onMoveUp) {
                            Image(systemName: "chevron.up").font(.system(size: 8.5, weight: .bold))
                        }
                        .buttonStyle(.plain)
                        .disabled(pageIndex == 0)
                        .foregroundStyle(pageIndex == 0 ? Theme.textFaint.swiftUI : Theme.textDim.swiftUI)

                        Button(action: onMoveDown) {
                            Image(systemName: "chevron.down").font(.system(size: 8.5, weight: .bold))
                        }
                        .buttonStyle(.plain)
                        .disabled(pageIndex + 1 >= pageCount)
                        .foregroundStyle(pageIndex + 1 >= pageCount ? Theme.textFaint.swiftUI : Theme.textDim.swiftUI)
                    }
                }
            }
            .padding(6)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isCurrent ? Theme.laneSelected.swiftUI : Theme.lane.swiftUI)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .strokeBorder(isCurrent ? Theme.accent.swiftUI.opacity(0.55) : Color.clear, lineWidth: 1)
                    )
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct MiniPagePreview: View {
    let page: VectorPage

    var body: some View {
        Canvas { ctx, size in
            let bg = RGBAColor(hex: page.backgroundColorHex) ?? RGBAColor(r: 1, g: 1, b: 1)
            ctx.fill(
                Path(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: 3),
                with: .color(Color(red: bg.r, green: bg.g, blue: bg.b))
            )

            let sx = size.width / CGFloat(max(1, page.width))
            let sy = size.height / CGFloat(max(1, page.height))

            for el in page.elements.prefix(24) where el.visible {
                let r = CGRect(
                    x: CGFloat(el.frame.x) * sx,
                    y: CGFloat(el.frame.y) * sy,
                    width: max(2, CGFloat(el.frame.width) * sx),
                    height: max(1.5, CGFloat(el.frame.height) * sy)
                )
                switch el.kind {
                case .signature:
                    ctx.fill(Path(roundedRect: r, cornerRadius: 1), with: .color(Theme.accent.swiftUI.opacity(0.85)))
                case .stamp:
                    ctx.stroke(Path(roundedRect: r, cornerRadius: 1), with: .color(Theme.alive.swiftUI), lineWidth: 1.0)
                case .text:
                    ctx.fill(Path(roundedRect: r, cornerRadius: 0.8), with: .color(Color.black.opacity(0.32)))
                default:
                    ctx.stroke(Path(r), with: .color(Theme.standby.swiftUI.opacity(0.75)), lineWidth: 0.8)
                }
            }
        }
    }
}

private struct ElementLayerRow: View {
    let element: VectorElement
    let isSelected: Bool
    let onSelect: () -> Void
    let onToggleVisible: () -> Void
    let onToggleLock: () -> Void

    var body: some View {
        let tint = Theme.elementTint(element).swiftUI
        HStack(spacing: 6) {
            Button(action: onSelect) {
                HStack(spacing: 6) {
                    Image(systemName: element.typeSymbol)
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(tint)
                        .frame(width: 16)

                    VStack(alignment: .leading, spacing: 1) {
                        Text(element.displayTitle)
                            .font(.system(size: 11, weight: isSelected ? .semibold : .regular))
                            .foregroundStyle(element.visible ? Theme.text.swiftUI : Theme.textFaint.swiftUI)
                            .lineLimit(1)
                        HStack(spacing: 4) {
                            Text(element.typeBadge)
                                .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                                .foregroundStyle(tint)
                            if element.hasModifiedPDFText {
                                Text(L("modifié", "edited"))
                                    .font(.system(size: 8.5, weight: .semibold))
                                    .foregroundStyle(Theme.alive.swiftUI)
                            }
                        }
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button(action: onToggleLock) {
                Image(systemName: element.locked ? "lock.fill" : "lock.open")
                    .font(.system(size: 9.5))
                    .foregroundStyle(element.locked ? Theme.warning.swiftUI : Theme.textFaint.swiftUI)
            }
            .buttonStyle(.plain)
            .help(L("Verrouiller ou déverrouiller l'élément", "Lock or unlock element"))

            Button(action: onToggleVisible) {
                Image(systemName: element.visible ? "eye" : "eye.slash")
                    .font(.system(size: 9.5))
                    .foregroundStyle(element.visible ? Theme.textDim.swiftUI : Theme.textFaint.swiftUI)
            }
            .buttonStyle(.plain)
            .help(L("Afficher ou masquer l'élément", "Show or hide element"))
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 4.5)
        .background(
            RoundedRectangle(cornerRadius: 5)
                .fill(isSelected ? Theme.laneSelected.swiftUI : Color.clear)
                .overlay(
                    RoundedRectangle(cornerRadius: 5)
                        .strokeBorder(isSelected ? Theme.accent.swiftUI.opacity(0.55) : Color.clear, lineWidth: 1)
                )
        )
    }
}
