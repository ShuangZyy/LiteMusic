//
//  Playlist.swift
//  LiteMusic
//
//  歌单数据模型
//

import Foundation

/// 歌单模型，对应网易云 /user/playlist 与 /playlist/detail 返回的 playlist 对象
struct Playlist: Identifiable, Codable {
    /// 歌单 ID
    let id: Int
    /// 歌单名称
    let name: String
    /// 封面图地址
    let coverImgUrl: String?
    /// 歌曲数量
    let trackCount: Int
    /// 播放次数
    let playCount: Int
    /// 歌单内歌曲（加载详情后填充）
    var tracks: [Song]?

    enum CodingKeys: String, CodingKey {
        case id, name, coverImgUrl, trackCount, playCount, tracks
    }

    init(id: Int, name: String, coverImgUrl: String?, trackCount: Int, playCount: Int, tracks: [Song]? = nil) {
        self.id = id
        self.name = name
        self.coverImgUrl = coverImgUrl
        self.trackCount = trackCount
        self.playCount = playCount
        self.tracks = tracks
    }

    /// 部分接口字段可能缺失，这里做容错处理
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        coverImgUrl = try? c.decode(String.self, forKey: .coverImgUrl)
        trackCount = (try? c.decode(Int.self, forKey: .trackCount)) ?? 0
        playCount = (try? c.decode(Int.self, forKey: .playCount)) ?? 0
        tracks = try? c.decode([Song].self, forKey: .tracks)
    }
}
