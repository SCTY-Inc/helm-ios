import SwiftUI

struct HTMLReaderView: View {
    @EnvironmentObject private var appState: AppState

    let file: RemoteFileReference
    let html: String
    var onOpenDocument: ((String) -> Void)?

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
            Button {
                appState.toggleFavoriteFile(file)
            } label: {
                Label(
                    appState.isFavoriteFile(file) ? "Remove Favorite" : "Favorite",
                    systemImage: appState.isFavoriteFile(file) ? "star.fill" : "star"
                )
            }
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
