//
//  PlaylistViewModel.swift
//  LiteMusic
//
//  歌单/推荐/搜索数据管理
//

import Foundation
import Combine

final class PlaylistViewModel: ObservableObject {
    /// 我的歌单
    @Published var playlists: [Playlist] = []
    /// 每日推荐歌曲
    @Published var dailySongs: [Song] = []
    /// 私人 FM 歌曲
    @Published var fmSongs: [Song] = []
    /// 当前歌单详情歌曲
    @Published var playlistSongs: [Song] = []
    /// 搜索结果
    @Published var searchResults: [Song] = []
    /// 是否加载中
    @Published var isLoading = false
    /// 错误信息
    @Published var errorMessage: String?

    // MARK: - 我的歌单

    func fetchPlaylists() {
        let auth = AuthManager.shared
        guard auth.isLoggedIn else {
            playlists = []
            return
        }
        APIService.shared.userPlaylist(uid: auth.uid, cookie: auth.cookie) { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .success(let list): self?.playlists = list
                case .failure(let e): self?.errorMessage = e.localizedDescription
                }
            }
        }
    }

    // MARK: - 每日推荐

    func fetchDailyRecommend() {
        isLoading = true
        APIService.shared.recommendSongs(cookie: AuthManager.shared.cookie) { [weak self] result in
            DispatchQueue.main.async {
                self?.isLoading = false
                switch result {
                case .success(let songs): self?.dailySongs = songs
                case .failure(let e): self?.errorMessage = e.localizedDescription
                }
            }
        }
    }

    // MARK: - 私人 FM

    func fetchPersonalFM() {
        isLoading = true
        APIService.shared.personalFM(cookie: AuthManager.shared.cookie) { [weak self] result in
            DispatchQueue.main.async {
                self?.isLoading = false
                switch result {
                case .success(let songs): self?.fmSongs = songs
                case .failure(let e): self?.errorMessage = e.localizedDescription
                }
            }
        }
    }

    // MARK: - 歌单详情

    func fetchPlaylistDetail(id: Int) {
        isLoading = true
        APIService.shared.playlistDetail(id: id) { [weak self] result in
            DispatchQueue.main.async {
                self?.isLoading = false
                switch result {
                case .success(let songs): self?.playlistSongs = songs
                case .failure(let e): self?.errorMessage = e.localizedDescription
                }
            }
        }
    }

    // MARK: - 搜索

    func search(_ keyword: String) {
        let kw = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !kw.isEmpty else {
            searchResults = []
            return
        }
        APIService.shared.search(keyword: kw) { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .success(let songs): self?.searchResults = songs
                case .failure(let e): self?.errorMessage = e.localizedDescription
                }
            }
        }
    }
}
