//
//  LiteMusicApp.swift
//  LiteMusic
//
//  应用入口：配置环境对象与后台音频会话
//

import SwiftUI
import AVFoundation
import MediaPlayer
import UIKit

@main
struct LiteMusicApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var playerVM = PlayerViewModel()
    @StateObject private var playlistVM = PlaylistViewModel()
    @StateObject private var appearance = AppearanceManager.shared

    var body: some Scene {
        WindowGroup {
            MainTabView()
                .preferredColorScheme(appearance.themeMode.colorScheme)
                .environmentObject(appearance)
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
        // 让 SwiftUI List 背景透明，主界面氛围背景可透出
        UITableView.appearance().backgroundColor = .clear
        UITableViewCell.appearance().backgroundColor = .clear

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

    /// 锁定竖屏：播放歌曲时避免系统把界面旋转成横屏（出现宽屏/黑边、只显示中间的问题）
    func application(_ application: UIApplication,
                     supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        return .portrait
    }
}
