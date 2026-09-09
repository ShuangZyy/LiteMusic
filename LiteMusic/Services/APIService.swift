//
//  APIService.swift
//  LiteMusic
//
//  网易云音乐 API 封装，基于开源的 NeteaseCloudMusicApi 作为数据源
//  参考：https://github.com/Binaryify/NeteaseCloudMusicApi
//

import Foundation

// MARK: - 错误类型

enum APIError: LocalizedError {
    /// 尚未配置 API 地址
    case noBaseURL
    /// 请求地址无效
    case invalidURL
    /// 服务器未返回数据
    case noData
    /// 业务错误（code 非 200）
    case apiError(code: Int, message: String)

    var errorDescription: String? {
        switch self {
        case .noBaseURL:
            return "尚未配置 API 地址，请在「我的」页设置"
        case .invalidURL:
            return "请求地址无效"
        case .noData:
            return "服务器未返回数据"
        case .apiError(let code, let message):
            return "接口错误(\(code)): \(message)"
        }
    }
}

// MARK: - 返回结果类型

/// 二维码状态检查结果
struct QRCheckResult {
    /// 800 二维码不存在或已过期 / 801 等待扫码 / 802 已扫码待确认 / 803 授权成功
    let code: Int
    let cookie: String
    let message: String
}

/// 手机号登录结果
struct CellphoneLoginResult {
    let cookie: String
    let uid: Int
    let profile: UserProfile?
}

// MARK: - API 服务

final class APIService {
    static let shared = APIService()

    private let session: URLSession
    private let decoder = JSONDecoder()

    /// API 基础地址（用户可配置，保存在 UserDefaults）
    /// 例如：http://192.168.1.5:3000  （部署 NeteaseCloudMusicApi 后填写）
    var baseURL: String {
        get { UserDefaults.standard.string(forKey: "apiBaseURL") ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: "apiBaseURL") }
    }

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 20
        session = URLSession(configuration: config)
    }

    // MARK: - 通用请求

    /// 发起 GET 请求，返回原始 Data
    private func get(path: String, query: [String: String], completion: @escaping (Result<Data, Error>) -> Void) {
        let base = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !base.isEmpty else { completion(.failure(APIError.noBaseURL)); return }
        guard let baseURL = URL(string: base) else { completion(.failure(APIError.invalidURL)); return }

        var components = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)
        if !query.isEmpty {
            components?.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }
        }
        guard let url = components?.url else { completion(.failure(APIError.invalidURL)); return }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 20

        session.dataTask(with: request) { data, _, error in
            if let error = error { completion(.failure(error)); return }
            guard let data = data else { completion(.failure(APIError.noData)); return }
            completion(.success(data))
        }.resume()
    }

    /// 校验业务返回码，非 200 抛错
    private func validate(code: Int, message: String?) throws {
        if code != 200 {
            throw APIError.apiError(code: code, message: message ?? "未知错误")
        }
    }

    // MARK: - 登录：二维码

    /// 获取二维码 key（unikey）
    func qrKey(completion: @escaping (Result<String, Error>) -> Void) {
        get(path: "/login/qr/key", query: [:]) { result in
            switch result {
            case .success(let data):
                do {
                    let resp = try self.decoder.decode(QRKeyResponse.self, from: data)
                    try self.validate(code: resp.code, message: resp.message)
                    guard let unikey = resp.data?.unikey else {
                        completion(.failure(APIError.noData)); return
                    }
                    completion(.success(unikey))
                } catch { completion(.failure(error)) }
            case .failure(let e): completion(.failure(e))
            }
        }
    }

    /// 生成二维码图片，返回 base64 编码的图片字符串
    func qrCreate(key: String, completion: @escaping (Result<String, Error>) -> Void) {
        get(path: "/login/qr/create", query: ["key": key, "qrimg": "true"]) { result in
            switch result {
            case .success(let data):
                do {
                    let resp = try self.decoder.decode(QRCreateResponse.self, from: data)
                    try self.validate(code: resp.code, message: resp.message)
                    guard let qrimg = resp.data?.qrimg else {
                        completion(.failure(APIError.noData)); return
                    }
                    completion(.success(qrimg))
                } catch { completion(.failure(error)) }
            case .failure(let e): completion(.failure(e))
            }
        }
    }

    /// 检查二维码扫码状态（800/801/802/803 均为正常返回，不做 200 校验）
    func qrCheck(key: String, completion: @escaping (Result<QRCheckResult, Error>) -> Void) {
        get(path: "/login/qr/check", query: ["key": key]) { result in
            switch result {
            case .success(let data):
                do {
                    let resp = try self.decoder.decode(QRCheckResponse.self, from: data)
                    completion(.success(QRCheckResult(code: resp.code, cookie: resp.cookie ?? "", message: resp.message ?? "")))
                } catch { completion(.failure(error)) }
            case .failure(let e): completion(.failure(e))
            }
        }
    }

    // MARK: - 登录：手机号

    /// 手机号 + 密码登录（密码由服务端 md5 处理）
    func cellphoneLogin(phone: String, password: String, completion: @escaping (Result<CellphoneLoginResult, Error>) -> Void) {
        get(path: "/login/cellphone", query: ["phone": phone, "password": password, "countrycode": "86"]) { result in
            switch result {
            case .success(let data):
                do {
                    let resp = try self.decoder.decode(CellphoneLoginResponse.self, from: data)
                    try self.validate(code: resp.code, message: resp.message)
                    guard let cookie = resp.cookie, !cookie.isEmpty else {
                        completion(.failure(APIError.noData)); return
                    }
                    let uid = resp.account?.id ?? resp.profile?.userId ?? 0
                    completion(.success(CellphoneLoginResult(cookie: cookie, uid: uid, profile: resp.profile)))
                } catch { completion(.failure(error)) }
            case .failure(let e): completion(.failure(e))
            }
        }
    }

    /// 查询登录状态，返回用户信息
    func loginStatus(cookie: String, completion: @escaping (UserProfile?) -> Void) {
        get(path: "/login/status", query: ["cookie": cookie]) { result in
            switch result {
            case .success(let data):
                let resp = try? self.decoder.decode(LoginStatusResponse.self, from: data)
                completion(resp?.data?.profile)
            case .failure:
                completion(nil)
            }
        }
    }

    // MARK: - 歌单

    /// 获取用户歌单列表
    func userPlaylist(uid: Int, cookie: String, completion: @escaping (Result<[Playlist], Error>) -> Void) {
        var query = ["uid": String(uid)]
        if !cookie.isEmpty { query["cookie"] = cookie }
        get(path: "/user/playlist", query: query) { result in
            switch result {
            case .success(let data):
                do {
                    let resp = try self.decoder.decode(UserPlaylistResponse.self, from: data)
                    try self.validate(code: resp.code, message: resp.message)
                    completion(.success(resp.playlist))
                } catch { completion(.failure(error)) }
            case .failure(let e): completion(.failure(e))
            }
        }
    }

    /// 获取歌单详情（含歌曲列表）
    func playlistDetail(id: Int, completion: @escaping (Result<[Song], Error>) -> Void) {
        get(path: "/playlist/detail", query: ["id": String(id)]) { result in
            switch result {
            case .success(let data):
                do {
                    let resp = try self.decoder.decode(PlaylistDetailResponse.self, from: data)
                    try self.validate(code: resp.code, message: resp.message)
                    completion(.success(resp.playlist?.tracks ?? []))
                } catch { completion(.failure(error)) }
            case .failure(let e): completion(.failure(e))
            }
        }
    }

    // MARK: - 推荐 / 私人FM / 搜索

    /// 每日推荐歌曲
    func recommendSongs(cookie: String, completion: @escaping (Result<[Song], Error>) -> Void) {
        var query: [String: String] = [:]
        if !cookie.isEmpty { query["cookie"] = cookie }
        get(path: "/recommend/songs", query: query) { result in
            switch result {
            case .success(let data):
                do {
                    let resp = try self.decoder.decode(RecommendSongsResponse.self, from: data)
                    try self.validate(code: resp.code, message: resp.message)
                    completion(.success(resp.data?.dailySongs ?? []))
                } catch { completion(.failure(error)) }
            case .failure(let e): completion(.failure(e))
            }
        }
    }

    /// 私人 FM（单次 /personal_fm 只返回 3 首，这里顺序拉取多批并去重，凑够约 15 首）
    func personalFM(cookie: String, batches: Int = 5, completion: @escaping (Result<[Song], Error>) -> Void) {
        var all: [Song] = []
        var seen = Set<Int>()
        var firstError: Error?

        func fetchNext(_ remaining: Int) {
            guard remaining > 0 else {
                if all.isEmpty, let e = firstError {
                    completion(.failure(e))
                } else {
                    completion(.success(all))
                }
                return
            }
            fetchPersonalFMBatch(cookie: cookie) { result in
                switch result {
                case .success(let songs):
                    for s in songs where !seen.contains(s.id) {
                        seen.insert(s.id)
                        all.append(s)
                    }
                case .failure(let e):
                    if firstError == nil { firstError = e }
                }
                fetchNext(remaining - 1)
            }
        }
        fetchNext(batches)
    }

    /// 单批私人 FM（内部使用）
    private func fetchPersonalFMBatch(cookie: String, completion: @escaping (Result<[Song], Error>) -> Void) {
        var query: [String: String] = [:]
        if !cookie.isEmpty { query["cookie"] = cookie }
        get(path: "/personal_fm", query: query) { result in
            switch result {
            case .success(let data):
                do {
                    let resp = try self.decoder.decode(FMResponse.self, from: data)
                    try self.validate(code: resp.code, message: resp.message)
                    completion(.success(resp.data ?? []))
                } catch { completion(.failure(error)) }
            case .failure(let e): completion(.failure(e))
            }
        }
    }

    /// 搜索歌曲（type=1 表示单曲）
    func search(keyword: String, completion: @escaping (Result<[Song], Error>) -> Void) {
        get(path: "/search", query: ["keywords": keyword, "type": "1", "limit": "50"]) { result in
            switch result {
            case .success(let data):
                do {
                    let resp = try self.decoder.decode(SearchResponse.self, from: data)
                    try self.validate(code: resp.code, message: resp.message)
                    completion(.success(resp.result?.songs ?? []))
                } catch { completion(.failure(error)) }
            case .failure(let e): completion(.failure(e))
            }
        }
    }

    // MARK: - 播放地址 / 歌词

    /// 获取歌曲播放地址（可能为 nil，例如 VIP / 无版权歌曲）
    func songURL(id: Int, completion: @escaping (Result<String?, Error>) -> Void) {
        get(path: "/song/url", query: ["id": String(id)]) { result in
            switch result {
            case .success(let data):
                do {
                    let resp = try self.decoder.decode(SongURLResponse.self, from: data)
                    try self.validate(code: resp.code, message: resp.message)
                    let url = resp.data?.first(where: { $0.id == id })?.url
                    completion(.success(url))
                } catch { completion(.failure(error)) }
            case .failure(let e): completion(.failure(e))
            }
        }
    }

    /// 获取歌词（LRC 原文）
    func lyric(id: Int, completion: @escaping (Result<String?, Error>) -> Void) {
        get(path: "/lyric", query: ["id": String(id)]) { result in
            switch result {
            case .success(let data):
                do {
                    let resp = try self.decoder.decode(LyricResponse.self, from: data)
                    try self.validate(code: resp.code, message: resp.message)
                    completion(.success(resp.lrc?.lyric))
                } catch { completion(.failure(error)) }
            case .failure(let e): completion(.failure(e))
            }
        }
    }

    // MARK: - 评论（歌曲 type=0）

    /// 获取歌曲评论（热门 + 最新），返回总条数与是否还有更多
    /// - Parameters:
    ///   - id: 歌曲 ID
    ///   - offset: 最新评论分页偏移（每页 limit 条）
    func commentMusic(id: Int, limit: Int = 20, offset: Int = 0, cookie: String = "",
                      completion: @escaping (Result<(hot: [Comment], latest: [Comment], total: Int, more: Bool), Error>) -> Void) {
        var query: [String: String] = ["id": String(id), "limit": String(limit), "offset": String(offset)]
        if !cookie.isEmpty { query["cookie"] = cookie }
        get(path: "/comment/music", query: query) { result in
            switch result {
            case .success(let data):
                do {
                    let resp = try self.decoder.decode(CommentListResponse.self, from: data)
                    try self.validate(code: resp.code, message: resp.message)
                    completion(.success((hot: resp.hotComments ?? [],
                                         latest: resp.comments ?? [],
                                         total: resp.total ?? 0,
                                         more: resp.more ?? false)))
                } catch { completion(.failure(error)) }
            case .failure(let e): completion(.failure(e))
            }
        }
    }

    /// 获取某条评论的楼中楼回复（楼层评论）
    /// 返回回复列表、是否还有更多、下一次请求的 time 游标
    func commentFloor(id: Int, parentCommentId: Int, limit: Int = 20, time: Int = 0, cookie: String = "",
                      completion: @escaping (Result<(comments: [Comment], hasMore: Bool, nextTime: Int), Error>) -> Void) {
        var query: [String: String] = ["id": String(id), "parentCommentId": String(parentCommentId),
                                       "type": "0", "limit": String(limit), "time": String(time)]
        if !cookie.isEmpty { query["cookie"] = cookie }
        get(path: "/comment/floor", query: query) { result in
            switch result {
            case .success(let data):
                do {
                    let resp = try self.decoder.decode(CommentFloorResponse.self, from: data)
                    try self.validate(code: resp.code, message: resp.message)
                    let data = resp.data
                    completion(.success((comments: data?.comments ?? [],
                                         hasMore: data?.hasMore ?? false,
                                         nextTime: data?.time ?? time)))
                } catch { completion(.failure(error)) }
            case .failure(let e): completion(.failure(e))
            }
        }
    }

    /// 发表 / 回复 / 删除评论（均需登录）
    /// - Parameters:
    ///   - t: 1 发表，2 回复，0 删除
    ///   - content: 发表/回复时的内容（删除传空字符串）
    ///   - commentId: 回复或删除时，被回复/被删除评论的 ID
    func sendComment(id: Int, t: Int, content: String, commentId: Int?, cookie: String,
                     completion: @escaping (Result<Void, Error>) -> Void) {
        var query: [String: String] = ["id": String(id), "t": String(t), "type": "0"]
        if !content.isEmpty { query["content"] = content }
        if let commentId = commentId { query["commentId"] = String(commentId) }
        if !cookie.isEmpty { query["cookie"] = cookie }
        get(path: "/comment", query: query) { result in
            switch result {
            case .success(let data):
                do {
                    let resp = try self.decoder.decode(CommentActionResponse.self, from: data)
                    try self.validate(code: resp.code, message: resp.message)
                    completion(.success(()))
                } catch { completion(.failure(error)) }
            case .failure(let e): completion(.failure(e))
            }
        }
    }

    /// 评论点赞 / 取消点赞（需登录）
    /// - Parameters:
    ///   - t: 1 点赞，0 取消点赞
    func likeComment(id: Int, cid: Int, t: Int, cookie: String,
                     completion: @escaping (Result<Void, Error>) -> Void) {
        var query: [String: String] = ["id": String(id), "cid": String(cid), "t": String(t), "type": "0"]
        if !cookie.isEmpty { query["cookie"] = cookie }
        get(path: "/comment/like", query: query) { result in
            switch result {
            case .success(let data):
                do {
                    let resp = try self.decoder.decode(CommentActionResponse.self, from: data)
                    try self.validate(code: resp.code, message: resp.message)
                    completion(.success(()))
                } catch { completion(.failure(error)) }
            case .failure(let e): completion(.failure(e))
            }
        }
    }
}

// MARK: - 响应包装结构（内部使用）

private struct QRKeyResponse: Decodable {
    let code: Int
    let message: String?
    let data: QRKeyData?
}
private struct QRKeyData: Decodable {
    let unikey: String
}

private struct QRCreateResponse: Decodable {
    let code: Int
    let message: String?
    let data: QRCreateData?
}
private struct QRCreateData: Decodable {
    let qrimg: String?
    let qrurl: String?
}

private struct QRCheckResponse: Decodable {
    let code: Int
    let message: String?
    let cookie: String?
}

private struct CellphoneLoginResponse: Decodable {
    let code: Int
    let message: String?
    let cookie: String?
    let token: String?
    let account: AccountInfo?
    let profile: UserProfile?
}
private struct AccountInfo: Decodable {
    let id: Int
    let userName: String?
}

private struct LoginStatusResponse: Decodable {
    // 注意：enhanced API 的 /login/status 返回体只有 { data: { ...profile } }，
    // 顶层没有 code 字段，因此这里必须用可选类型，否则解码失败导致用户信息永远为空。
    let code: Int?
    let message: String?
    let data: LoginStatusData?
}
private struct LoginStatusData: Decodable {
    let account: AccountInfo?
    let profile: UserProfile?
}

private struct UserPlaylistResponse: Decodable {
    let code: Int
    let message: String?
    let playlist: [Playlist]
}

private struct PlaylistDetailResponse: Decodable {
    let code: Int
    let message: String?
    let playlist: PlaylistDetail?
    struct PlaylistDetail: Decodable {
        let tracks: [Song]?
    }
}

private struct RecommendSongsResponse: Decodable {
    let code: Int
    let message: String?
    let data: RecommendData?
}
private struct RecommendData: Decodable {
    let dailySongs: [Song]?
}

private struct FMResponse: Decodable {
    let code: Int
    let message: String?
    let data: [Song]?
}

private struct SearchResponse: Decodable {
    let code: Int
    let message: String?
    let result: SearchResult?
}
private struct SearchResult: Decodable {
    let songs: [Song]?
}

private struct SongURLResponse: Decodable {
    let code: Int
    let message: String?
    let data: [SongURLItem]?
}
private struct SongURLItem: Decodable {
    let id: Int
    let url: String?
}

private struct LyricResponse: Decodable {
    let code: Int
    let message: String?
    let lrc: LRCData?
}
private struct LRCData: Decodable {
    let lyric: String?
}

// MARK: - 评论响应包装

private struct CommentListResponse: Decodable {
    let code: Int
    let message: String?
    let total: Int?
    let more: Bool?
    let hotComments: [Comment]?
    let comments: [Comment]?
}

private struct CommentFloorResponse: Decodable {
    let code: Int
    let message: String?
    let data: CommentFloorData?
}
private struct CommentFloorData: Decodable {
    let comments: [Comment]?
    let hasMore: Bool?
    /// 下次分页的 time 游标
    let time: Int?
    let totalCount: Int?
}

private struct CommentActionResponse: Decodable {
    let code: Int
    let message: String?
    let comment: Comment?
}
