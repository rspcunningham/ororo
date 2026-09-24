import AVKit
import OroroKit
import SwiftUI

/// Full-screen player: fetches a freshly signed stream URL, then hands off
/// to the native tvOS player.
struct PlayerScreen: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let request: PlaybackRequest

    private enum LoadState {
        case loading
        case ready(PlaybackInfo)
        case failed(String)
    }

    @State private var state: LoadState = .loading

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            switch state {
            case .loading:
                ProgressView()
            case .ready(let info):
                PlayerContainer(
                    request: request,
                    info: info,
                    onProgress: { position, duration in
                        model.recordProgress(request, position: position, duration: duration)
                    },
                    onFinished: {
                        Task {
                            model.saveLibraryNow()
                            let playingNext = await model.playNextEpisode(after: request)
                            if !playingNext { dismiss() }
                        }
                    }
                )
                .id(request.id)
                .ignoresSafeArea()
            case .failed(let message):
                VStack(spacing: 40) {
                    Text(message).font(.title3).multilineTextAlignment(.center)
                    Button("Close") { dismiss() }
                }
                .padding(100)
            }
        }
        .task(id: request.id) {
            state = .loading
            guard let client = model.client else { return }
            do {
                state = .ready(try await client.playback(for: request.media))
            } catch {
                state = .failed(error.localizedDescription)
            }
        }
        .onDisappear { model.saveLibraryNow() }
    }
}

struct PlayerContainer: UIViewControllerRepresentable {
    let request: PlaybackRequest
    let info: PlaybackInfo
    let onProgress: (Double, Double) -> Void
    let onFinished: () -> Void

    func makeCoordinator() -> PlaybackCoordinator {
        PlaybackCoordinator()
    }

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let coordinator = context.coordinator
        coordinator.onProgress = onProgress
        coordinator.onFinished = onFinished
        coordinator.start(request: request, info: info)
        return coordinator.controller
    }

    func updateUIViewController(_ controller: AVPlayerViewController, context: Context) {}

    static func dismantleUIViewController(_ controller: AVPlayerViewController, coordinator: PlaybackCoordinator) {
        coordinator.stop()
    }
}
