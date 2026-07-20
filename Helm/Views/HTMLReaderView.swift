import SwiftUI

struct HTMLReaderView: View {
    @EnvironmentObject private var appState: AppState

    let file: RemoteFileReference
    let html: String
    var onOpenDocument: ((String) -> Void)?

    @State private var isSuggesting = false

    var body: some View {
        DocumentWebView(
            html: html,
            documentPath: file.path,
            onOpenDocument: onOpenDocument
        )
        .ignoresSafeArea(edges: .bottom)
        .navigationTitle(file.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            Menu {
                Button {
                    isSuggesting = true
                } label: {
                    Label("Suggest Change", systemImage: "waveform.badge.mic")
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
        .sheet(isPresented: $isSuggesting) {
            RecorderView(targetFile: file)
        }
    }
}

#Preview {
    NavigationStack {
        HTMLReaderView(
            file: RemoteFileReference(
                hostID: UUID(),
                path: "Guide.html",
                title: "Guide"
            ),
            html: "<h1>Guide</h1><p>This is rendered HTML.</p>"
        )
        .environmentObject(AppState())
    }
}
