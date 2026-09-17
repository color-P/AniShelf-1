import SwiftUI
import AVKit
import UIKit

struct MediaPlayerView: View {
    let url: URL
    let title: String
    let isImage: Bool

    @State private var player: AVPlayer?

    init(candidate: MediaCandidate) {
        url = candidate.url
        title = candidate.displayTitle
        isImage = candidate.kind.isImage
    }

    init(fileURL: URL) {
        url = fileURL
        title = fileURL.lastPathComponent
        isImage = MediaKind(rawValue: fileURL.pathExtension.lowercased())?.isImage ?? false
    }

    var body: some View {
        Group {
            if isImage {
                imagePreview
            } else {
                VideoPlayer(player: player)
                    .ignoresSafeArea()
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            guard !isImage else { return }
            if player == nil {
                let newPlayer = AVPlayer(url: url)
                newPlayer.play()
                player = newPlayer
            } else {
                player?.play()
            }
        }
        .onDisappear {
            player?.pause()
        }
    }

    @ViewBuilder
    private var imagePreview: some View {
        if url.isFileURL {
            if let image = UIImage(contentsOfFile: url.path) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
            } else {
                placeholder
            }
        } else {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFit()
                case .failure:
                    placeholder
                case .empty:
                    ProgressView()
                @unknown default:
                    placeholder
                }
            }
        }
    }

    private var placeholder: some View {
        VStack(spacing: 12) {
            Image(systemName: "photo")
                .font(.system(size: 44))
                .foregroundStyle(.secondary)
            Text("无法预览图片")
                .font(.headline)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
