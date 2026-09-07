//
//  User.swift
//  LiteMusic
//
//  用户信息数据模型
//

import Foundation

/// 用户信息，对应网易云 /login/status 与 /login/cellphone 返回的 profile 字段
struct UserProfile: Codable {
    /// 用户 ID
    let userId: Int
    /// 昵称
    let nickname: String
    /// 头像地址
    let avatarUrl: String?
    /// 个人签名
    let signature: String?

    enum CodingKeys: String, CodingKey {
        case userId, nickname, avatarUrl, signature
    }

    init(userId: Int, nickname: String, avatarUrl: String?, signature: String?) {
        self.userId = userId
        self.nickname = nickname
        self.avatarUrl = avatarUrl
        self.signature = signature
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        userId = (try? c.decode(Int.self, forKey: .userId)) ?? 0
        nickname = (try? c.decode(String.self, forKey: .nickname)) ?? "未知用户"
        avatarUrl = try? c.decode(String.self, forKey: .avatarUrl)
        signature = try? c.decode(String.self, forKey: .signature)
    }
}
