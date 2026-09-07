//
//  PlayerView.swift
//  LiteMusic
//
//  全屏播放器：封面、歌曲信息、进度拖拽、播放控制、歌词
//

import SwiftUI

struct PlayerView: View {
    @EnvironmentObject var playerVM: PlayerViewModel
    @EnvironmentObject var player: AudioPlayer
    /// 关闭回调（由父视图传入，避免 fullScreenCover 下 presentationMode 不可靠）
    let onDismiss: () -> Void

    @State private var isSeeking = false
    @State private var seekTime: Double = 0

    var body: some View {
        ZStack {
            // 氛围背景：当前歌曲封面模糊 + 氛围色
            AmbientBackground(coverURL: playerVM.currentSong?.coverURLString)
                .id(playerVM.currentSong?.coverURLString)

            VStack(spacing: 0) {
                // 顶部收起按钮
                HStack {
                    Button(action: onDismiss) {
                        Image(systemName: "chevron.down")
                            .font(.title2)
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    Spacer()
                    Text(playerVM.currentSong?.name ?? "")
                        .font(.subheadline)
                        .lineLimit(1)
                    Spacer()
                    Image(systemName: "chevron.down").opacity(0) // 占位保持居中
                }
                .padding(.horizontal)
                .padding(.top, 8)

                // 专辑封面（碟片）
                RemoteImage(urlString: playerVM.currentSong?.coverURLString,
                            placeholder: Image(systemName: "music.note"))
                    .frame(width: 260, height: 260)
                    .cornerRadius(12)
                    .shadow(radius: 10)
                    .padding(.top, 30)
                    // 手指在碟片位置下滑退出全屏
                    .gesture(
                        DragGesture(minimumDistance: 20)
                            .onEnded { value in
                                if value.translation.height > 60,
                                   value.translation.height > abs(value.translation.width) {
                                    onDismiss()
                                }
                            }
                    )

                // 歌曲信息
                VStack(spacing: 6) {
                    Text(playerVM.currentSong?.name ?? "")
                        .font(.title2).bold()
                        .lineLimit(1)
                    Text(playerVM.currentSong?.artistName ?? "")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                .padding(.top, 20)

                // 进度条
                VStack(spacing: 4) {
                    Slider(value: $seekTime,
                           in: 0...max(player.duration, 1),
                           onEditingChanged: { editing in
                               isSeeking = editing
                               if !editing { playerVM.seek(to: seekTime) }
                           })
                    .padding(.horizontal)
                    HStack {
                        Text(timeText(player.currentTime))
                        Spacer()
                        Text(timeText(player.duration))
                    }
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.horizontal)
                }
                .padding(.top, 16)

                // 播放控制
                HStack(spacing: 28) {
                    Button(action: { playerVM.cyclePlayMode() }) {
                        Image(systemName: playerVM.playMode.icon).font(.title2)
                    }
                    Button(action: { playerVM.previous() }) {
                        Image(systemName: "backward.fill").font(.largeTitle)
                    }
                    Button(action: { playerVM.togglePlay() }) {
                        Image(systemName: player.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                            .font(.system(size: 70))
                    }
                    Button(action: { playerVM.next() }) {
                        Image(systemName: "forward.fill").font(.largeTitle)
                    }
                }
                .padding(.top, 20)

                Spacer()

                // 歌词
                LyricsView(lyrics: playerVM.lyrics, currentIndex: playerVM.currentLyricIndex)
                    .frame(height: 170)
                    .padding(.bottom, 20)
            }
        }
        .onAppear { seekTime = player.currentTime }
        .onReceive(player.$currentTime) { t in
            if !isSeeking { seekTime = t }
        }
    }

    private func timeText(_ t: TimeInterval) -> String {
        guard t.isFinite else { return "0:00" }
        let total = max(0, Int(t))
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
