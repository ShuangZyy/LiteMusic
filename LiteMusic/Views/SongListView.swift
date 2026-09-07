//
//  SongListView.swift
//  LiteMusic
//
//  歌曲列表：展示歌名、歌手、专辑、时长，支持搜索
//

import SwiftUI

/// 歌曲列表来源
enum SongListSource: Equatable {
    case daily
    case fm
    case playlist(Int)
    case search
}

struct SongListView: View {
    let title: String
    let source: SongListSource

    @EnvironmentObject var vm: PlaylistViewModel
    @EnvironmentObject var playerVM: PlayerViewModel
    @State private var searchText = ""

    /// 根据来源取对应歌曲数组
    private var songs: [Song] {
        switch source {
        case .daily: return vm.dailySongs
        case .fm: return vm.fmSongs
        case .playlist: return vm.playlistSongs
        case .search: return vm.searchResults
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            if source == .search {
                SearchBar(text: $searchText, placeholder: "搜索歌曲、歌手") {
                    vm.search(searchText)
                }
                .padding(.horizontal, 8)
                .padding(.top, 4)
            }

            List {
                if songs.isEmpty {
                    Text(emptyText)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.top, 40)
                } else {
                    ForEach(Array(songs.enumerated()), id: \.element.id) { index, song in
                        SongRow(song: song)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                playerVM.play(songs: songs, index: index)
                            }
                    }
                }
            }
            .listStyle(PlainListStyle())
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: load)
    }

    private var emptyText: String {
        if source == .search { return searchText.isEmpty ? "输入关键词搜索" : "无搜索结果" }
        return "暂无歌曲"
    }

    private func load() {
        switch source {
        case .daily: vm.fetchDailyRecommend()
        case .fm: vm.fetchPersonalFM()
        case .playlist(let id): vm.fetchPlaylistDetail(id: id)
        case .search: break
        }
    }
}

/// 单行歌曲条目
private struct SongRow: View {
    let song: Song

    var body: some View {
        HStack(spacing: 12) {
            RemoteImage(urlString: song.coverURLString,
                        placeholder: Image(systemName: "music.note"))
                .frame(width: 44, height: 44)
                .cornerRadius(4)

            VStack(alignment: .leading, spacing: 4) {
                Text(song.name).font(.body).lineLimit(1)
                Text("\(song.artistName) · \(song.albumName)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Text(song.durationText)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 4)
    }
}
