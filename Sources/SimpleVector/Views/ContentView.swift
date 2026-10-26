import SimpleVectorCore
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @Bindable var model: AppModel
    @State private var dropTargeted = false

    var body: some View {
        VStack(spacing: 0) {
            TopBar(model: model)

            HStack(spacing: 0) {
                if model.showSidebar {
                    HStack(spacing: 0) {
                        SidebarView(model: model)
                            .frame(width: 224)
                        Rectangle().fill(Theme.separator.swiftUI).frame(width: 1)
                    }
                    .transition(.move(edge: .leading).combined(with: .opacity))
                }

                CanvasViewportView(model: model)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Theme.background.swiftUI)
                    .overlay {
                        if dropTargeted {
                            RoundedRectangle(cornerRadius: 10)
                                .strokeBorder(Theme.accent.swiftUI, style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
                                .padding(12)
                                .allowsHitTesting(false)
                        }
                    }
                    .onDrop(of: [.fileURL], isTargeted: $dropTargeted) { providers in
                        handleDrop(providers)
                    }

                if model.showInspector {
                    HStack(spacing: 0) {
                        Rectangle().fill(Theme.separator.swiftUI).frame(width: 1)
                        InspectorView(model: model)
                            .frame(width: 316)
                    }
                    .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
            .animation(.spring(duration: 0.22, bounce: 0.0), value: model.showSidebar)
            .animation(.spring(duration: 0.22, bounce: 0.0), value: model.showInspector)

            StatusBar(model: model)
        }
        .background(Theme.background.swiftUI)
        .preferredColorScheme(.dark)
        .environment(\.locale, model.language.locale)
        .id(model.language.resolvedCode)
        .navigationTitle("SimpleVector")
        .navigationSubtitle(subtitle)
        .sheet(isPresented: $model.showExportSheet) { ExportSheet(model: model) }
        .sheet(isPresented: $model.showOSCGuide) { OSCGuideSheet(model: model) { model.showOSCGuide = false } }
        .sheet(isPresented: $model.showShortcuts) { ShortcutsSheet { model.showShortcuts = false } }
        .sheet(isPresented: $model.showHelp) {
            HelpManualSheet(openShortcuts: { DispatchQueue.main.async { model.showShortcuts = true } }) {
                model.showHelp = false
            }
        }
        .sheet(isPresented: $model.showAbout) {
            AboutSheet(model: model, openHelp: { DispatchQueue.main.async { model.showHelp = true } }) {
                model.showAbout = false
            }
        }
        .sheet(isPresented: $model.showUpdater) {
            UpdateSheet(model: model) {
                model.showUpdater = false
            }
        }
        .alert(item: $model.alert) { alert in
            SwiftUI.Alert(title: Text(alert.title), message: Text(alert.message), dismissButton: .default(Text("OK")))
        }
    }

    private var subtitle: String {
        let doc = model.controller.document
        return "\(doc.title) · \(L("Page \(model.controller.currentPageIndex + 1)/\(doc.pages.count)", "Page \(model.controller.currentPageIndex + 1)/\(doc.pages.count)"))"
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        var handled = false
        for provider in providers where provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            handled = true
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                let url: URL?
                if let data = item as? Data { url = URL(dataRepresentation: data, relativeTo: nil) }
                else if let u = item as? URL { url = u }
                else { url = nil }
                guard let url else { return }
                Task { @MainActor in
                    model.open(url)
                }
            }
        }
        return handled
    }
}
