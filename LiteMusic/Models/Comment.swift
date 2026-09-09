//
//  Comment.swift
//  LiteMusic
//
//  评论数据模型：对应网易云音乐接口返回的 comment 对象（歌曲评论 type=0）
//

import Foundation

// MARK: - 评论用户

/// 评论用户（昵称 / 头像）
struct CommentUser: Decodable, Hashable {
    /// 用户 ID（评论接口中字段为 userId）
    let userId: Int
    /// 昵称
    let nickname: String
    /// 头像地址
    let avatarUrl: String?

    enum CodingKeys: String, CodingKey {
        case userId, nickname, avatarUrl
    }

    init(userId: Int, nickname: String, avatarUrl: String?) {
        self.userId = userId
        self.nickname = nickname
        self.avatarUrl = avatarUrl
    }

    /// 部分用户已注销或字段缺失，做容错处理
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        userId = (try? c.decode(Int.self, forKey: .userId)) ?? 0
        nickname = (try? c.decode(String.self, forKey: .nickname)) ?? "已注销用户"
        avatarUrl = try? c.decode(String.self, forKey: .avatarUrl)
    }
}

// MARK: - 被回复引用

/// 楼中楼里「回复了谁」的引用信息（beReplied）
struct CommentReply: Decodable, Hashable {
    let user: CommentUser?
    let content: String?

    enum CodingKeys: String, CodingKey {
        case user, content
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        user = try? c.decode(CommentUser.self, forKey: .user)
        content = try? c.decode(String.self, forKey: .content)
    }
}

// MARK: - 评论

/// 单条评论，对应网易云 API 中的 comment 对象
/// 注意：liked / likedCount 可变，用于本地点赞的乐观更新
struct Comment: Identifiable, Decodable, Hashable {
    /// 评论 ID（作为 Identifiable 的 id）
    let commentId: Int
    /// 评论内容
    let content: String
    /// 评论时间（毫秒时间戳）
    let time: Int
    /// 点赞数
    var likedCount: Int
    /// 当前用户是否已赞
    var liked: Bool
    /// 评论用户
    let user: CommentUser
    /// 被回复的引用（首层评论可能回复了另一条评论）
    let beReplied: [CommentReply]
    /// IP 属地文本，如「浙江」（不同接口字段为 ipLocation.location / ip）
    let ipLocation: String?
    /// 首条楼中楼回复（用作「查看 X 条回复」入口预览）
    let showFloorComment: Comment?

    /// Identifiable 协议：id = commentId
    var id: Int { commentId }

    enum CodingKeys: String, CodingKey {
        case commentId, content, time, likedCount, liked, user, beReplied, ipLocation, showFloorComment, ip
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        commentId = (try? c.decode(Int.self, forKey: .commentId)) ?? 0
        content = (try? c.decode(String.self, forKey: .content)) ?? ""
        time = (try? c.decode(Int.self, forKey: .time)) ?? 0
        likedCount = (try? c.decode(Int.self, forKey: .likedCount)) ?? 0
        liked = (try? c.decode(Bool.self, forKey: .liked)) ?? false
        user = (try? c.decode(CommentUser.self, forKey: .user)) ?? CommentUser(userId: 0, nickname: "未知用户", avatarUrl: nil)
        if let replies = try? c.decode([CommentReply].self, forKey: .beReplied) {
            beReplied = replies
        } else {
            beReplied = []
        }
        // IP 属地兼容两种结构：ipLocation: { "location": "浙江" } 或 ip: "浙江"
        if let ipObj = try? c.decode(IPLocationObject.self, forKey: .ipLocation) {
            ipLocation = ipObj.location
        } else if let ipStr = try? c.decode(String.self, forKey: .ipLocation) {
            ipLocation = ipStr
        } else if let ip = try? c.decode(String.self, forKey: .ip) {
            ipLocation = ip
        } else {
            ipLocation = nil
        }
        // 容错：首条楼中楼解析失败不影响整条评论
        if let nested = try? c.decodeIfPresent(Comment.self, forKey: .showFloorComment) {
            showFloorComment = nested
        } else {
            showFloorComment = nil
        }
    }

    /// 评论时间相对文本，例如「刚刚 / 3分钟前 / 2小时前 / 昨天 / 2024-01-02」
    var timeText: String {
        let interval = Double(time) / 1000.0
        let diff = Date().timeIntervalSince1970 - interval
        if diff < 60 { return "刚刚" }
        let minutes = Int(diff / 60)
        if minutes < 60 { return "\(minutes) 分钟前" }
        let hours = minutes / 60
        if hours < 24 { return "\(hours) 小时前" }
        let days = hours / 24
        if days < 3 { return "\(days) 天前" }
        let date = Date(timeIntervalSince1970: interval)
        return Self.dayFormatter.string(from: date)
    }

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    /// 点赞数文本：1.2 万 这种缩写
    var likedCountText: String {
        if likedCount >= 10000 {
            return String(format: "%.1f万", Double(likedCount) / 10000.0)
        }
        return "\(likedCount)"
    }
}

/// ipLocation 为对象时的内部容器（仅用于解码）
private struct IPLocationObject: Decodable {
    let location: String?
}
