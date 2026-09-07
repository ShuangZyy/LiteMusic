//
//  PlaylistView.swift
//  LiteMusic
//
//  首页：展示每日推荐、私人FM、我的歌单
//

import SwiftUI

struct PlaylistView: View {
    @EnvironmentObject var vm: PlaylistViewModel
    @EnvironmentObject var auth: AuthManager

    var body: some View {
        NavigationView {
            List {
                Section(header: Text("每日推荐")) {
                    NavigationLink(destination: SongListView(title: "每日推荐", source: .daily)) {
                        Label("每日推荐", systemImage: "calendar")
                    }
                }

                Section(header: Text("私人FM")) {
                    NavigationLink(destination: SongListView(title: "私人FM", source: .fm)) {
                        Label("私人FM", systemImage: "radio")
                    }
                }

                Section(header: Text("我的歌单")) {
                    if vm.playlists.isEmpty {
                        Text(auth.isLoggedIn ? "暂无歌单" : "请先登录")
                            .foregroundColor(.secondary)
                    } else {
                        ForEach(vm.playlists) { playlist in
                            NavigationLink(destination: SongListView(title: playlist.name, source: .playlist(playlist.id))) {
                                PlaylistRow(playlist: playlist)
                            }
                        }
                    }
                }
            }
            .listStyle(InsetGroupedListStyle())
            .navigationTitle("首页")
            .onAppear {
                vm.fetchPlaylists()
            }
        }
    }
}

private struct PlaylistRow: View {
    let playlist: Playlist

    var body: some View {
        HStack {
            RemoteImage(urlString: playlist.coverImgUrl,
                        placeholder: Image(systemName: "music.note.list"))
                .frame(width: 48, height: 48)
                .cornerRadius(6)
            VStack(alignment: .leading, spacing: 2) {
                Text(playlist.name).font(.headline).lineLimit(1)
                Text("\(playlist.trackCount) 首").font(.caption).foregroundColor(.secondary)
            }
        }
    }
}
