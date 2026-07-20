import SwiftUI

struct MarkdownReaderView: View {
    @EnvironmentObject private var appState: AppState
    @StateObject private var speechReader = MarkdownSpeechReader()

    let file: RemoteFileReference
    let markdown: String
    var onOpenDocument: ((String) -> Void)? = nil
    var onMarkdownSaved: ((String) -> Void)? = nil

    @State private var scrollAnchor: String?
    @State private var activeSheet: ActiveSheet?

    private enum ActiveSheet: String, Identifiable {
        case edit
        case suggest
        case ask

        var id: String { rawValue }
    }

    var body: some View {
        DocumentWebView(
            html: renderedHTML,
            documentPath: file.path,
            onOpenDocument: onOpenDocument,
            scrollAnchor: $scrollAnchor
        )
        .ignoresSafeArea(edges: .bottom)
        .navigationTitle(file.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !outline.isEmpty {
                Menu {
                    ForEach(outline) { heading in
                        Button {
                            scrollAnchor = heading.slug
                        } label: {
                            Text(String(repeating: "  ", count: max(0, heading.level - 1)) + heading.title)
                        }
                    }
                } label: {
                    Label("Contents", systemImage: "list.bullet")
                }
            }

            Button {
                speechReader.toggleReading(title: file.title, markdown: markdown)
            } label: {
                Label(
                    speechReader.isSpeaking ? "Stop Reading" : "Read Aloud",
                    systemImage: speechReader.isSpeaking ? "stop.circle" : "speaker.wave.2"
                )
            }

            Menu {
                Button {
                    activeSheet = .edit
                } label: {
                    Label("Edit Markdown", systemImage: "pencil")
                }

                Button {
                    activeSheet = .suggest
                } label: {
                    Label("Suggest Change", systemImage: "waveform.badge.mic")
                }

                if #available(iOS 26.0, *) {
                    Button {
                        activeSheet = .ask
                    } label: {
                        Label("Ask about this doc", systemImage: "sparkles")
                    }
                }

                Button {
                    appState.toggleFavoriteFile(file)
                } label: {
                    Label(
                        appState.isFavoriteFile(file) ? "Remove Favorite" : "Favorite",
                        systemImage: appState.isFavoriteFile(file) ? "star.fill" : "star"
                    )
                }
            } label: {
                Label("Page Actions", systemImage: "ellipsis.circle")
            }
        }
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .edit:
                MarkdownEditorView(file: file, markdown: markdown) { updated in
                    onMarkdownSaved?(updated)
                }
            case .suggest:
                RecorderView(targetFile: file)
            case .ask:
                if #available(iOS 26.0, *) {
                    DocumentChatView(title: file.title, documentText: markdown)
                } else {
                    ContentUnavailableView("On-device AI unavailable", systemImage: "sparkles")
                }
            }
        }
        .onDisappear {
            speechReader.stopReading()
        }
    }

    private var renderer: MarkdownHTMLRenderer {
        MarkdownHTMLRenderer(title: file.title)
    }

    private var renderedHTML: String {
        renderer.makeDocument(from: markdown)
    }

    private var outline: [DocumentHeading] {
        renderer.outline(from: markdown)
    }
}

#Preview {
    NavigationStack {
        MarkdownReaderView(
            file: RemoteFileReference(
                hostID: UUID(),
                path: "README.md",
                title: "README"
            ),
            markdown: """
            # Helm

            A private **markdown reader** for your Tailscale tailnet.

            ## Features

            - Browse remote files
            - `inline code` and fenced blocks
            - Tables and quotes

            > Connect over Tailscale, read anywhere.

            ```swift
            let helm = Reader()
            helm.open(page)
            ```
            """
        )
        .environmentObject(AppState())
    }
}
