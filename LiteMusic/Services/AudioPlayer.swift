//
//  AudioPlayer.swift
//  LiteMusic
//
//  AVFoundation 播放器封装：负责音频会话、播放控制、锁屏信息与远程控制
//

import AVFoundation
import MediaPlayer
import Combine
import UIKit

final class AudioPlayer: NSObject, ObservableObject {
    static let shared = AudioPlayer()

    /// 是否正在播放
    @Published var isPlaying = false
    /// 当前播放进度（秒）
    @Published var currentTime: TimeInterval = 0
    /// 总时长（秒）
    @Published var duration: TimeInterval = 0

    /// 播放结束 / 远程“下一首”回调
    var onNext: (() -> Void)?
    /// 远程“上一首”回调
    var onPrevious: (() -> Void)?

    private var player: AVPlayer?
    private var timeObserver: Any?
    private var statusObservation: NSKeyValueObservation?
    private var endObserver: NSObjectProtocol?
    private var currentSong: Song?

    private override init() {
        super.init()
        setupAudioSession()
        setupRemoteCommands()
    }

    // MARK: - 音频会话

    private func setupAudioSession() {
        let session = AVAudioSession.sharedInstance()
        do {
            // .playback 类别支持后台播放、静音键下仍出声
            try session.setCategory(.playback, mode: .default)
            try session.setActive(true)
        } catch {
            print("音频会话配置失败: \(error.localizedDescription)")
        }
    }

    // MARK: - 播放控制

    /// 播放指定 URL
    func play(url: URL) {
        teardownCurrentItem()

        let item = AVPlayerItem(url: url)
        player = AVPlayer(playerItem: item)

        // 监听播放状态
        statusObservation = item.observe(\.status, options: [.new, .initial]) { [weak self] item, _ in
            switch item.status {
            case .readyToPlay:
                let d = item.duration.seconds
                self?.duration = d.isFinite ? d : 0
            case .failed:
                print("播放失败: \(item.error?.localizedDescription ?? "未知错误")")
            default:
                break
            }
        }

        // 监听播放结束，自动切换下一首
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            self?.isPlaying = false
            self?.onNext?()
        }

        // 周期性更新进度
        timeObserver = player?.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.5, preferredTimescale: 600),
            queue: .main
        ) { [weak self] time in
            self?.currentTime = time.seconds
        }

        player?.play()
        isPlaying = true
    }

    func pause() {
        player?.pause()
        isPlaying = false
        updateNowPlayingElapsed()
    }

    func resume() {
        player?.play()
        isPlaying = true
        updateNowPlayingElapsed()
    }

    func toggle() {
        isPlaying ? pause() : resume()
    }

    /// 跳转到指定进度
    func seek(to time: TimeInterval) {
        let target = CMTime(seconds: time, preferredTimescale: 600)
        player?.seek(to: target)
        currentTime = time
        updateNowPlayingElapsed()
    }

    func stop() {
        teardownCurrentItem()
        player = nil
        isPlaying = false
        currentTime = 0
        duration = 0
    }

    private func teardownCurrentItem() {
        if let obs = timeObserver { player?.removeTimeObserver(obs); timeObserver = nil }
        if let end = endObserver { NotificationCenter.default.removeObserver(end); endObserver = nil }
        statusObservation?.invalidate()
        statusObservation = nil
    }

    // MARK: - 锁屏 / 控制中心信息

    func setNowPlayingInfo(song: Song) {
        currentSong = song
        let info: [String: Any] = [
            MPMediaItemPropertyTitle: song.name,
            MPMediaItemPropertyArtist: song.artistName,
            MPMediaItemPropertyAlbumTitle: song.albumName,
            MPMediaItemPropertyPlaybackDuration: song.duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: currentTime,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0
        ]
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info

        // 异步加载封面图
        if let cover = song.coverURLString, let url = URL(string: cover) {
            URLSession.shared.dataTask(with: url) { data, _, _ in
                guard let data = data, let image = UIImage(data: data) else { return }
                let artwork = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
                DispatchQueue.main.async {
                    var current = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
                    current[MPMediaItemPropertyArtwork] = artwork
                    MPNowPlayingInfoCenter.default().nowPlayingInfo = current
                }
            }.resume()
        }
    }

    private func updateNowPlayingElapsed() {
        guard var info = MPNowPlayingInfoCenter.default().nowPlayingInfo else { return }
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = currentTime
        info[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? 1.0 : 0.0
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    // MARK: - 远程控制（锁屏 / 耳机 / 控制中心）

    private func setupRemoteCommands() {
        let center = MPRemoteCommandCenter.shared()
        center.playCommand.addTarget { [weak self] _ in self?.resume(); return .success }
        center.pauseCommand.addTarget { [weak self] _ in self?.pause(); return .success }
        center.togglePlayPauseCommand.addTarget { [weak self] _ in self?.toggle(); return .success }
        center.nextTrackCommand.addTarget { [weak self] _ in self?.onNext?(); return .success }
        center.previousTrackCommand.addTarget { [weak self] _ in self?.onPrevious?(); return .success }
        center.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let e = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            self?.seek(to: e.positionTime)
            return .success
        }
    }
}
