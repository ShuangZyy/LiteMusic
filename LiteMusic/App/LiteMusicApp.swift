//
//  LiteMusicApp.swift
//  LiteMusic
//
//  应用入口：配置环境对象与后台音频会话
//

import SwiftUI
import AVFoundation
import MediaPlayer

@main
struct LiteMusicApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var playerVM = PlayerViewModel()
    @StateObject private var playlistVM = PlaylistViewModel()

    var body: some Scene {
        WindowGroup {
            MainTabView()
                .environmentObject(playerVM)
                .environmentObject(playlistVM)
                .environmentObject(AuthManager.shared)
                .environmentObject(AudioPlayer.shared)
        }
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        // 配置后台音频会话（.playback 支持后台播放）
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playback, mode: .default)
            try session.setActive(true)
        } catch {
            print("音频会话配置失败: \(error.localizedDescription)")
        }
        // 允许接收远程控制事件（锁屏 / 耳机 / 控制中心）
        application.beginReceivingRemoteControlEvents()
        return true
    }
}
