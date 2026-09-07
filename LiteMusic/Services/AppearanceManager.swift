//
//  AppearanceManager.swift
//  LiteMusic
//
//  外观设置管理：深色模式、主界面氛围背景的模糊度/透明度
//

import SwiftUI
import Combine

/// 主题模式
enum ThemeMode: String, CaseIterable, Identifiable {
    case system   // 跟随系统
    case light    // 浅色
    case dark     // 深色

    var id: String { rawValue }

    var label: String {
        switch self {
        case .system: return "跟随系统"
        case .light: return "浅色"
        case .dark: return "深色"
        }
    }

    /// 对应的 SwiftUI 配色方案（nil 表示跟随系统）
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

/// 外观设置管理器（单例，持久化到 UserDefaults）
final class AppearanceManager: ObservableObject {
    static let shared = AppearanceManager()

    /// 主题模式
    @Published var themeMode: ThemeMode {
        didSet { UserDefaults.standard.set(themeMode.rawValue, forKey: "appearance_theme") }
    }
    /// 氛围背景模糊度（0~60）
    @Published var backgroundBlur: Double {
        didSet { UserDefaults.standard.set(backgroundBlur, forKey: "appearance_blur") }
    }
    /// 氛围背景透明度（0~1）
    @Published var backgroundOpacity: Double {
        didSet { UserDefaults.standard.set(backgroundOpacity, forKey: "appearance_opacity") }
    }

    private init() {
        UserDefaults.standard.register(defaults: [
            "appearance_theme": ThemeMode.system.rawValue,
            "appearance_blur": 30.0,
            "appearance_opacity": 0.4,
        ])
        themeMode = ThemeMode(rawValue: UserDefaults.standard.string(forKey: "appearance_theme") ?? "") ?? .system
        backgroundBlur = UserDefaults.standard.double(forKey: "appearance_blur")
        backgroundOpacity = UserDefaults.standard.double(forKey: "appearance_opacity")
    }
}
