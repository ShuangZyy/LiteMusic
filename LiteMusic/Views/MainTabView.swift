//
//  MainTabView.swift
//  LiteMusic
//
//  主界面：三个 Tab + 底部迷你播放器
//

import SwiftUI

struct MainTabView: View {
    @EnvironmentObject var auth: AuthManager
    @EnvironmentObject var playerVM: PlayerViewModel
    @EnvironmentObject var player: AudioPlayer
    @EnvironmentObject var appearance: AppearanceManager

    @State private var selectedTab = 0
    @State private var showLogin = false
    @State private var showPlayer = false

    var body: some View {
        ZStack(alignment: .bottom) {
            // 主界面氛围背景（跟随当前歌曲封面）
            AmbientBackground(coverURL: playerVM.currentSong?.coverURLString)
                .id(playerVM.currentSong?.coverURLString)

            TabView(selection: $selectedTab) {
                PlaylistView()
                    .tabItem { Label("首页", systemImage: "house.fill") }
                    .tag(0)

                SongListView(title: "搜索", source: .search)
                    .tabItem { Label("搜索", systemImage: "magnifyingglass") }
                    .tag(1)

                MineView()
                    .tabItem { Label("我的", systemImage: "person.fill") }
                    .tag(2)
            }

            // 底部迷你播放器（浮在 TabBar 上方）
            if playerVM.currentSong != nil {
                MiniPlayerView()
                    .onTapGesture { showPlayer = true }
                    .padding(.bottom, 49)
            }
        }
        .onAppear {
            if !auth.isLoggedIn { showLogin = true }
        }
        .sheet(isPresented: $showLogin) {
            LoginView()
                .environmentObject(auth)
                .environmentObject(appearance)
                .preferredColorScheme(appearance.themeMode.colorScheme)
        }
        .fullScreenCover(isPresented: $showPlayer) {
            PlayerView(onDismiss: { showPlayer = false })
                .environmentObject(playerVM)
                .environmentObject(player)
                .environmentObject(appearance)
                .preferredColorScheme(appearance.themeMode.colorScheme)
        }
    }
}

// MARK: - 我的页面

private struct MineView: View {
    @EnvironmentObject var auth: AuthManager
    @EnvironmentObject var appearance: AppearanceManager
    @State private var apiURL = ""
    @State private var showLogin = false
    @State private var showLogoutConfirm = false

    var body: some View {
        NavigationView {
            List {
                if auth.isLoggedIn {
                    Section {
                        HStack {
                            RemoteImage(urlString: auth.user?.avatarUrl,
                                        placeholder: Image(systemName: "person.crop.circle"))
                                .frame(width: 56, height: 56)
                                .clipShape(Circle())
                            VStack(alignment: .leading, spacing: 4) {
                                Text(auth.user?.nickname ?? "用户")
                                    .font(.headline)
                                Text("UID: \(auth.uid)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        Button("退出登录") { showLogoutConfirm = true }
                            .foregroundColor(.red)
                    }
                } else {
                    Section {
                        Button("登录网易云音乐") { showLogin = true }
                    }
                }

                Section(header: Text("API 设置"), footer: Text("请填写部署好的 NeteaseCloudMusicApi 地址，例如 http://192.168.1.5:3000")) {
                    TextField("API 地址", text: $apiURL)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                    Button("保存 API 地址") {
                        APIService.shared.baseURL = apiURL.trimmingCharacters(in: .whitespacesAndNewlines)
                    }
                }

                Section(header: Text("外观")) {
                    Picker("主题", selection: $appearance.themeMode) {
                        ForEach(ThemeMode.allCases) { mode in
                            Text(mode.label).tag(mode)
                        }
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text("背景模糊度")
                            .font(.footnote)
                            .foregroundColor(.secondary)
                        Slider(value: $appearance.backgroundBlur, in: 0...60, step: 1)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text("背景透明度")
                            .font(.footnote)
                            .foregroundColor(.secondary)
                        Slider(value: $appearance.backgroundOpacity, in: 0...1, step: 0.05)
                    }
                }
            }
            .listStyle(InsetGroupedListStyle())
            .navigationTitle("我的")
            .onAppear {
                apiURL = APIService.shared.baseURL
                auth.refreshUserProfile()
            }
            .sheet(isPresented: $showLogin) { LoginView().environmentObject(auth) }
            .alert(isPresented: $showLogoutConfirm) {
                Alert(title: Text("确认退出？"),
                      message: Text("退出后将清除本地登录状态"),
                      primaryButton: .destructive(Text("退出")) { auth.logout() },
                      secondaryButton: .cancel())
            }
        }
    }
}
