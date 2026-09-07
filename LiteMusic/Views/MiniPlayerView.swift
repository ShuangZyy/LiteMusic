//
//  MiniPlayerView.swift
//  LiteMusic
//
//  底部迷你播放器
//

import SwiftUI

struct MiniPlayerView: View {
    @EnvironmentObject var playerVM: PlayerViewModel
    @EnvironmentObject var player: AudioPlayer

    var body: some View {
        HStack(spacing: 12) {
            RemoteImage(urlString: playerVM.currentSong?.coverURLString,
                        placeholder: Image(systemName: "music.note"))
                .frame(width: 44, height: 44)
                .cornerRadius(4)

            VStack(alignment: .leading, spacing: 2) {
                Text(playerVM.currentSong?.name ?? "")
                    .font(.subheadline)
                    .lineLimit(1)
                Text(playerVM.currentSong?.artistName ?? "")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Button(action: { playerVM.togglePlay() }) {
                Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                    .font(.title2)
            }
            Button(action: { playerVM.next() }) {
                Image(systemName: "forward.fill")
                    .font(.title2)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(radius: 3)
        .padding(.horizontal, 8)
    }
}
