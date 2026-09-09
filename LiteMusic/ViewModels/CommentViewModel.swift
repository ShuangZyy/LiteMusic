//
//  CommentViewModel.swift
//  LiteMusic
//
//  评论数据管理：加载评论、分页、点赞、发表、回复、删除
//

import Foundation
import Combine

// MARK: - 数组便捷方法

extension Array where Element == Comment {
    /// 按评论 ID 就地修改（本地点赞的乐观更新）
    mutating func updateComment(id: Int, _ mutate: (inout Comment) -> Void) {
        if let i = self.firstIndex(where: { $0.commentId == id }) {
            mutate(&self[i])
        }
    }
}

// MARK: - 评论列表 ViewModel

final class CommentViewModel: ObservableObject {
    /// 热门评论
    @Published var hotComments: [Comment] = []
    /// 最新评论（按时间倒序分页加载）
    @Published var latestComments: [Comment] = []
    /// 总评论数
    @Published var total = 0
    /// 首次加载中
    @Published var isLoading = false
    /// 分页加载中
    @Published var isLoadingMore = false
    /// 首屏错误信息
    @Published var errorMessage: String?
    /// 发送/操作反馈（成功提示语或错误提示语）
    @Published var feedback: String?
    /// feedback 是否为错误提示（红色显示）
    @Published var feedbackIsError = false
    /// 是否正在发送
    @Published var sending = false

    private var songId = 0
    private var offset = 0
    private var more = true
    private let pageSize = 20
    /// 防止重复请求
    private var isFetching = false

    /// 是否还有更多最新评论
    var hasMore: Bool { more }

    private var isLoggedIn: Bool { AuthManager.shared.isLoggedIn }
    private var cookie: String { AuthManager.shared.cookie }
    private var uid: Int { AuthManager.shared.uid }

    /// 首次加载或刷新：重置分页并从第 0 页开始
    func load(songId: Int) {
        self.songId = songId
        hotComments = []
        latestComments = []
        total = 0
        more = true
        offset = 0
        errorMessage = nil
        feedback = nil
        feedbackIsError = false
        isLoading = true
        fetch(offset: 0, append: false)
    }

    /// 上拉加载更多最新评论
    func loadMore() {
        guard more, !isLoadingMore, !isFetching, !latestComments.isEmpty else { return }
        fetch(offset: offset, append: true)
    }

    private func fetch(offset: Int, append: Bool) {
        guard !isFetching else { return }
        isFetching = true
        isLoadingMore = append
        let songId = songId
        APIService.shared.commentMusic(id: songId, limit: pageSize, offset: offset, cookie: cookie) { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.isFetching = false
                self.isLoading = false
                self.isLoadingMore = false
                switch result {
                case .success(let r):
                    if append {
                        // 去掉与已存在重复的评论，防止分页边界重复
                        var existed = Set(self.latestComments.map { $0.commentId })
                        self.latestComments.append(contentsOf: r.latest.filter { existed.insert($0.commentId).inserted })
                    } else {
                        self.hotComments = r.hot
                        self.latestComments = r.latest
                    }
                    self.total = r.total
                    self.more = r.more
                    self.offset = offset + self.pageSize
                case .failure(let e):
                    if self.latestComments.isEmpty && self.hotComments.isEmpty {
                        self.errorMessage = e.localizedDescription
                    }
                }
            }
        }
    }

    // MARK: - 点赞

    /// 点赞 / 取消点赞：先本地乐观更新，接口失败再回滚
    func toggleLike(_ comment: Comment) {
        guard isLoggedIn else { return }
        let original = comment
        let target = !comment.liked
        // 乐观更新热门与最新两个数组
        if hotComments.contains(where: { $0.commentId == comment.commentId }) {
            hotComments.updateComment(id: comment.commentId) { c in
                c.liked = target
                c.likedCount = max(0, c.likedCount + (target ? 1 : -1))
            }
        }
        if latestComments.contains(where: { $0.commentId == comment.commentId }) {
            latestComments.updateComment(id: comment.commentId) { c in
                c.liked = target
                c.likedCount = max(0, c.likedCount + (target ? 1 : -1))
            }
        }
        APIService.shared.likeComment(id: songId, cid: comment.commentId, t: target ? 1 : 0, cookie: cookie) { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self else { return }
                if case .failure = result {
                    // 回滚
                    if self.hotComments.contains(where: { $0.commentId == comment.commentId }) {
                        self.hotComments.updateComment(id: comment.commentId) { c in
                            c.liked = original.liked
                            c.likedCount = original.likedCount
                        }
                    }
                    if self.latestComments.contains(where: { $0.commentId == comment.commentId }) {
                        self.latestComments.updateComment(id: comment.commentId) { c in
                            c.liked = original.liked
                            c.likedCount = original.likedCount
                        }
                    }
                    self.feedback = "操作失败，请重试"
                    self.feedbackIsError = true
                }
            }
        }
    }

    // MARK: - 发表 / 删除

    /// 发表新评论
    func post(content: String) {
        let text = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        guard isLoggedIn else { return }
        guard !sending else { return }
        sending = true
        feedback = nil
        feedbackIsError = false
        APIService.shared.sendComment(id: songId, t: 1, content: text, commentId: nil, cookie: cookie) { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.sending = false
                switch result {
                case .success:
                    // 先重载列表，再设置提示（load 会清空 feedback，顺序不能反）
                    self.load(songId: self.songId)
                    self.feedback = "评论成功"
                    self.feedbackIsError = false
                case .failure(let e):
                    self.feedback = "发表失败：\(e.localizedDescription)"
                    self.feedbackIsError = true
                }
            }
        }
    }

    /// 删除自己的评论
    func delete(_ comment: Comment) {
        guard isLoggedIn, comment.user.userId == uid else { return }
        APIService.shared.sendComment(id: songId, t: 0, content: "", commentId: comment.commentId, cookie: cookie) { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self else { return }
                switch result {
                case .success:
                    self.hotComments.removeAll { $0.commentId == comment.commentId }
                    self.latestComments.removeAll { $0.commentId == comment.commentId }
                    self.total = max(0, self.total - 1)
                    self.feedback = "删除成功"
                    self.feedbackIsError = false
                case .failure(let e):
                    self.feedback = "删除失败：\(e.localizedDescription)"
                    self.feedbackIsError = true
                }
            }
        }
    }

    /// 当前用户是否可删除该评论（仅作者本人）
    func canDelete(_ comment: Comment) -> Bool {
        isLoggedIn && comment.user.userId == uid
    }

    /// 是否已登录（视图层提示用）
    var isLoggedInUser: Bool { isLoggedIn }
}

// MARK: - 楼中楼 ViewModel

/// 某条评论的楼中楼回复数据管理（含对根评论的回复）
final class FloorCommentsViewModel: ObservableObject {
    /// 楼中楼回复列表
    @Published var comments: [Comment] = []
    /// 总回复数
    @Published var totalCount = 0
    /// 加载中
    @Published var isLoading = false
    /// 分页加载中
    @Published var isLoadingMore = false
    /// 错误信息
    @Published var errorMessage: String?
    /// 发送反馈
    @Published var feedback: String?
    /// feedback 是否为错误提示（红色显示）
    @Published var feedbackIsError = false
    /// 是否正在发送
    @Published var sending = false

    private var songId = 0
    private var parentCommentId = 0
    /// 楼中楼分页游标（按 time 增量拉取）
    private var nextTime = 0
    private var hasMoreData = true
    private let pageSize = 20
    private var isFetching = false

    var hasMore: Bool { hasMoreData }
    private var isLoggedIn: Bool { AuthManager.shared.isLoggedIn }
    private var cookie: String { AuthManager.shared.cookie }

    /// 首次加载或刷新
    func load(songId: Int, parentCommentId: Int) {
        self.songId = songId
        self.parentCommentId = parentCommentId
        comments = []
        totalCount = 0
        hasMoreData = true
        nextTime = 0
        errorMessage = nil
        feedback = nil
        feedbackIsError = false
        isLoading = true
        fetch(time: 0, append: false)
    }

    func loadMore() {
        guard hasMoreData, !isFetching, !isLoadingMore, !comments.isEmpty else { return }
        fetch(time: nextTime, append: true)
    }

    private func fetch(time: Int, append: Bool) {
        guard !isFetching else { return }
        isFetching = true
        isLoadingMore = append
        APIService.shared.commentFloor(id: songId, parentCommentId: parentCommentId,
                                       limit: pageSize, time: time, cookie: cookie) { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.isFetching = false
                self.isLoading = false
                self.isLoadingMore = false
                switch result {
                case .success(let r):
                    if append {
                        var existed = Set(self.comments.map { $0.commentId })
                        self.comments.append(contentsOf: r.comments.filter { existed.insert($0.commentId).inserted })
                    } else {
                        self.comments = r.comments
                    }
                    self.hasMoreData = r.hasMore
                    self.nextTime = r.nextTime
                case .failure(let e):
                    if self.comments.isEmpty {
                        self.errorMessage = e.localizedDescription
                    }
                }
            }
        }
    }

    /// 回复根评论（楼中楼），成功后刷新
    func reply(content: String) {
        let text = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, isLoggedIn, !sending else { return }
        sending = true
        feedback = nil
        feedbackIsError = false
        APIService.shared.sendComment(id: songId, t: 2, content: text, commentId: parentCommentId, cookie: cookie) { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.sending = false
                switch result {
                case .success:
                    // 先重载，再提示（load 会清空 feedback）
                    self.load(songId: self.songId, parentCommentId: self.parentCommentId)
                    self.feedback = "回复成功"
                    self.feedbackIsError = false
                case .failure(let e):
                    self.feedback = "回复失败：\(e.localizedDescription)"
                    self.feedbackIsError = true
                }
            }
        }
    }

    /// 点赞 / 取消点赞（乐观更新 + 回滚）
    func toggleLike(_ comment: Comment) {
        guard isLoggedIn else { return }
        let original = comment
        let target = !comment.liked
        comments.updateComment(id: comment.commentId) { c in
            c.liked = target
            c.likedCount = max(0, c.likedCount + (target ? 1 : -1))
        }
        APIService.shared.likeComment(id: songId, cid: comment.commentId, t: target ? 1 : 0, cookie: cookie) { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self else { return }
                if case .failure = result {
                    self.comments.updateComment(id: comment.commentId) { c in
                        c.liked = original.liked
                        c.likedCount = original.likedCount
                    }
                    self.feedback = "操作失败，请重试"
                    self.feedbackIsError = true
                }
            }
        }
    }

    /// 删除自己楼中楼的回复
    func delete(_ comment: Comment) {
        guard isLoggedIn, comment.user.userId == AuthManager.shared.uid else { return }
        APIService.shared.sendComment(id: songId, t: 0, content: "", commentId: comment.commentId, cookie: cookie) { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self else { return }
                switch result {
                case .success:
                    self.comments.removeAll { $0.commentId == comment.commentId }
                    self.totalCount = max(0, self.totalCount - 1)
                    self.feedback = "删除成功"
                    self.feedbackIsError = false
                case .failure(let e):
                    self.feedback = "删除失败：\(e.localizedDescription)"
                    self.feedbackIsError = true
                }
            }
        }
    }

    /// 当前用户是否可删除该楼中楼回复（仅作者本人）
    func canDelete(_ comment: Comment) -> Bool {
        isLoggedIn && comment.user.userId == AuthManager.shared.uid
    }

    var isLoggedInUser: Bool { isLoggedIn }
}
