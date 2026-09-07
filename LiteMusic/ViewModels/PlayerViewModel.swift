//
//  PlayerViewModel.swift
//  LiteMusic
//
//  播放器状态管理：播放队列、播放模式、歌词等
//

import Foundation
import Combine
import SwiftUI
import UIKit

// MARK: - 播放模式

enum PlayMode: Int, CaseIterable {
    case listLoop   // 列表循环
    case random     // 随机播放
    case singleLoop // 单曲循环

    /// 对应 SF Symbol 图标名
    var icon: String {
        switch self {
        case .listLoop: return "repeat"
        case .random: return "shuffle"
        case .singleLoop: return "repeat.1"
        }
    }
}

// MARK: - 播放器 ViewModel

final class PlayerViewModel: ObservableObject {
    /// 当前播放歌曲
    @Published var currentSong: Song?
    /// 播放队列
    @Published var queue: [Song] = []
    /// 当前播放下标
    @Published var currentIndex: Int = -1
    /// 播放模式
    @Published var playMode: PlayMode = .listLoop
    /// 当前歌曲歌词
    @Published var lyrics: [LyricLine] = []
    /// 当前高亮歌词行下标
    @Published var currentLyricIndex: Int = 0
    /// 当前封面印象色（平均色），用于播放控制按钮等配色
    @Published var coverColor: Color = .accentColor

    private let player = AudioPlayer.shared
    private var cancellables = Set<AnyCancellable>()

    init() {
        // 播放结束 / 远程下一首 / 远程上一首
        player.onNext = { [weak self] in self?.next() }
        player.onPrevious = { [weak self] in self?.previous() }
        // 监听进度更新歌词高亮
        player.$currentTime
            .sink { [weak self] t in self?.updateLyricIndex(t) }
            .store(in: &cancellables)
    }

    var isPlaying: Bool { player.isPlaying }
    var currentTime: TimeInterval { player.currentTime }
    var duration: TimeInterval { player.duration }

    // MARK: - 播放

    /// 播放一个歌曲列表，从指定下标开始
    func play(songs: [Song], index: Int = 0) {
        guard index >= 0, index < songs.count else { return }
        queue = songs
        currentIndex = index
        playCurrent()
    }

    /// 播放单首歌曲
    func playSingle(_ song: Song) {
        play(songs: [song], index: 0)
    }

    /// 播放当前下标的歌曲
    private func playCurrent() {
        guard currentIndex >= 0, currentIndex < queue.count else { return }
        let song = queue[currentIndex]
        currentSong = song
        lyrics = []
        currentLyricIndex = 0
        updateCoverColor(for: song)

        APIService.shared.songURL(id: song.id) { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self else { return }
                switch result {
                case .success(let urlString):
                    guard let urlString = urlString, let url = URL(string: urlString) else {
                        // 无播放地址（VIP / 无版权），自动跳到下一首
                        self.next()
                        return
                    }
                    self.player.play(url: url)
                    self.player.setNowPlayingInfo(song: song)
                    self.loadLyrics(for: song)
                case .failure(let error):
                    print("获取播放地址失败: \(error.localizedDescription)")
                }
            }
        }
    }

    /// 播放 / 暂停切换
    func togglePlay() {
        if player.isPlaying {
            player.pause()
        } else {
            if currentSong == nil {
                playCurrent()
            } else {
                player.resume()
            }
        }
    }

    /// 下一首
    func next() {
        guard !queue.isEmpty else { return }
        switch playMode {
        case .singleLoop:
            playCurrent()
        case .random:
            currentIndex = Int.random(in: 0..<queue.count)
            playCurrent()
        case .listLoop:
            currentIndex = (currentIndex + 1) % queue.count
            playCurrent()
        }
    }

    /// 上一首（播放超过 5 秒则回到开头）
    func previous() {
        guard !queue.isEmpty else { return }
        if player.currentTime > 5 {
            player.seek(to: 0)
        } else {
            currentIndex = (currentIndex - 1 + queue.count) % queue.count
            playCurrent()
        }
    }

    /// 跳转到指定进度
    func seek(to time: TimeInterval) {
        player.seek(to: time)
    }

    /// 循环切换播放模式
    func cyclePlayMode() {
        switch playMode {
        case .listLoop: playMode = .random
        case .random: playMode = .singleLoop
        case .singleLoop: playMode = .listLoop
        }
    }

    // MARK: - 歌词

    private func loadLyrics(for song: Song) {
        APIService.shared.lyric(id: song.id) { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self else { return }
                if case .success(let text) = result, let text = text {
                    self.lyrics = LRC.parse(text)
                }
            }
        }
    }

    // MARK: - 封面印象色

    /// 提取当前封面平均色作为「印象色」，用于播放控制按钮等配色
    private func updateCoverColor(for song: Song) {
        guard let cover = song.coverURLString, let url = URL(string: cover) else {
            coverColor = .accentColor
            return
        }
        if let cached = ImageCache.shared.image(for: cover) {
            applyCoverColor(cached, for: song)
            return
        }
        URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
            guard let data = data, let img = UIImage(data: data) else { return }
            ImageCache.shared.set(img, for: cover)
            DispatchQueue.main.async {
                self?.applyCoverColor(img, for: song)
            }
        }.resume()
    }

    /// 在后台线程计算平均色，主线程回写（用 song.id 防止旧歌颜色覆盖新歌）
    private func applyCoverColor(_ img: UIImage, for song: Song) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let avg = img.averageColor()
            DispatchQueue.main.async {
                guard self?.currentSong?.id == song.id else { return }
                self?.coverColor = Color(uiColor: avg)
            }
        }
    }

    /// 根据当前进度更新高亮歌词行
    private func updateLyricIndex(_ time: TimeInterval) {
        guard !lyrics.isEmpty else { return }
        var idx = 0
        for (i, line) in lyrics.enumerated() {
            if time >= line.time { idx = i } else { break }
        }
        if idx != currentLyricIndex { currentLyricIndex = idx }
    }
}
