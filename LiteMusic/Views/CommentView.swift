//
//  CommentView.swift
//  LiteMusic
//
//  歌曲评论区：热门评论 + 最新评论（分页）、楼中楼回复、点赞、发表/回复/删除
//  iOS 14 兼容：无 safeAreaInset，底部输入栏用 VStack 布局 + 键盘高度避让
//

import SwiftUI
import UIKit
import Combine

// MARK: - 评论主界面

struct CommentView: View {
    let song: Song

    @ObservedObject private var auth = AuthManager.shared
    @StateObject private var vm = CommentViewModel()
    @State private var draft = ""
    @State private var didLoad = false
    /// 单一片呈现：登录 or 楼中楼（iOS 14 同一视图挂多个 sheet 不可靠，统一合并为一个）
    @State private var activeSheet: ActiveCommentSheet?

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                commentList

                if let feedback = vm.feedback {
                    Text(feedback)
                        .font(.footnote)
                        .foregroundColor(vm.feedbackIsError ? .red : .secondary)
                        .padding(.top, 6)
                }

                Divider()

                CommentComposer(isLoggedIn: auth.isLoggedIn,
                                sending: vm.sending,
                                text: $draft,
                                onSend: { vm.post(content: draft); draft = "" },
                                onNeedLogin: { activeSheet = .login })
            }
            .keyboardAdaptive()
            .navigationTitle(navTitle)
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarItems(leading: Button("关闭") {
                presentationMode.wrappedValue.dismiss()
            })
            .onAppear {
                if !didLoad {
                    didLoad = true
                    vm.load(songId: song.id)
                }
            }
        }
        .sheet(item: $activeSheet) { sheet in
            sheetContent(for: sheet)
        }
    }

    /// 登录 / 楼中楼 sheet 内容
    private func sheetContent(for sheet: ActiveCommentSheet) -> some View {
        switch sheet {
        case .login:
            return AnyView(LoginView().environmentObject(AuthManager.shared))
        case .floor(let root):
            return AnyView(FloorCommentsView(song: song, rootComment: root))
        }
    }

    /// 评论区顶层的两个可弹出层：登录、楼中楼
    enum ActiveCommentSheet: Identifiable {
        case login
        case floor(Comment)

        var id: String {
            switch self {
            case .login: return "login"
            case .floor(let c): return "floor-\(c.commentId)"
            }
        }
    }

    @Environment(\.presentationMode) private var presentationMode

    /// 导航标题：评论数加载完成后带上总数
    private var navTitle: String {
        vm.total > 0 ? "评论（\(countText(vm.total))）" : "评论"
    }

    private var commentList: some View {
        List {
            if let error = vm.errorMessage, vm.hotComments.isEmpty, vm.latestComments.isEmpty {
                Text(error)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top, 30)
            } else if !vm.isLoading, vm.hotComments.isEmpty, vm.latestComments.isEmpty {
                Text("暂无评论，来抢沙发吧")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top, 30)
            } else {
                if !vm.hotComments.isEmpty {
                    Section(header: Text("热门评论")) {
                        ForEach(vm.hotComments) { comment in
                            CommentRowView(comment: comment,
                                           showLike: true,
                                           canDelete: vm.canDelete(comment),
                                           onLike: { like(comment) },
                                           onReply: { openFloor(comment) },
                                           onDelete: { vm.delete(comment) })
                        }
                    }
                }

                if !vm.latestComments.isEmpty {
                    Section(header: Text("最新评论（\(countText(vm.total))）")) {
                        ForEach(vm.latestComments) { comment in
                            CommentRowView(comment: comment,
                                           showLike: true,
                                           canDelete: vm.canDelete(comment),
                                           onLike: { like(comment) },
                                           onReply: { openFloor(comment) },
                                           onDelete: { vm.delete(comment) })
                        }
                    }
                }

                if vm.isLoading || vm.isLoadingMore {
                    HStack { Spacer(); ProgressView(); Spacer() }
                        .padding(.vertical, 12)
                } else if vm.hasMore {
                    // 触底加载更多
                    Color.clear
                        .frame(height: 4)
                        .onAppear { vm.loadMore() }
                }
            }
        }
        .listStyle(PlainListStyle())
    }

    private func openFloor(_ comment: Comment) {
        // 浏览楼层无需登录；登录与否都可查看回复，仅发表才需要登录
        activeSheet = .floor(comment)
    }

    /// 点赞：未登录则弹出登录
    private func like(_ comment: Comment) {
        guard auth.isLoggedIn else {
            activeSheet = .login
            return
        }
        vm.toggleLike(comment)
    }

    /// 万级评论数缩写，如 1307 -> 1307，12345 -> 1.2万
    private func countText(_ n: Int) -> String {
        if n >= 10000 {
            return String(format: "%.1f万", Double(n) / 10000.0)
        }
        return "\(n)"
    }
}

// MARK: - 楼中楼回复界面

struct FloorCommentsView: View {
    let song: Song
    /// 根评论（被回复的那条）
    let rootComment: Comment

    @ObservedObject private var auth = AuthManager.shared
    @StateObject private var vm = FloorCommentsViewModel()
    @State private var draft = ""
    @State private var showLogin = false
    @State private var loaded = false

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                List {
                    // 根评论置顶展示
                    Section {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(spacing: 10) {
                                RemoteImage(urlString: rootComment.user.avatarUrl,
                                            placeholder: Image(systemName: "person.crop.circle"))
                                    .frame(width: 36, height: 36)
                                    .clipShape(Circle())
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(rootComment.user.nickname)
                                        .font(.subheadline).bold()
                                    HStack(spacing: 6) {
                                        Text(rootComment.timeText)
                                        if let ip = rootComment.ipLocation {
                                            Text("· \(ip)")
                                        }
                                    }
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                }
                            }
                            Text(rootComment.content)
                                .font(.subheadline)
                        }
                        .padding(.vertical, 4)
                    }

                    if let error = vm.errorMessage, vm.comments.isEmpty {
                        Text(error)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.vertical, 20)
                    } else if !vm.isLoading, vm.comments.isEmpty {
                        Text("还没有回复，来说两句吧")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.vertical, 20)
                    } else {
                        Section(header: Text(vm.comments.isEmpty ? "" : "全部回复（\(vm.comments.count)）")) {
                            ForEach(vm.comments) { comment in
                                CommentRowView(comment: comment,
                                               showLike: true,
                                               canDelete: vm.canDelete(comment),
                                               onLike: { like(comment) },
                                               onReply: nil,
                                               onDelete: { vm.delete(comment) })
                            }
                        }

                        if vm.isLoading || vm.isLoadingMore {
                            HStack { Spacer(); ProgressView(); Spacer() }
                                .padding(.vertical, 12)
                        } else if vm.hasMore {
                            Color.clear
                                .frame(height: 4)
                                .onAppear { vm.loadMore() }
                        }
                    }
                }
                .listStyle(PlainListStyle())

                if let feedback = vm.feedback {
                    Text(feedback)
                        .font(.footnote)
                        .foregroundColor(vm.feedbackIsError ? .red : .secondary)
                        .padding(.top, 6)
                }

                Divider()

                CommentComposer(isLoggedIn: auth.isLoggedIn,
                                sending: vm.sending,
                                text: $draft,
                                onSend: { vm.reply(content: draft); draft = "" },
                                onNeedLogin: { showLogin = true })
            }
            .keyboardAdaptive()
            .navigationTitle("回复")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarItems(leading: Button("关闭") {
                presentationMode.wrappedValue.dismiss()
            })
            .onAppear {
                if !loaded {
                    loaded = true
                    vm.load(songId: song.id, parentCommentId: rootComment.commentId)
                }
            }
        }
        .sheet(isPresented: $showLogin) {
            LoginView().environmentObject(AuthManager.shared)
        }
    }

    @Environment(\.presentationMode) private var presentationMode

    /// 点赞：未登录则弹出登录
    private func like(_ comment: Comment) {
        guard auth.isLoggedIn else {
            showLogin = true
            return
        }
        vm.toggleLike(comment)
    }
}

/// 单条评论行；onReply 为 nil 时隐藏「回复」入口
struct CommentRowView: View {
    let comment: Comment
    let showLike: Bool
    let canDelete: Bool
    let onLike: () -> Void
    /// 为 nil 表示当前列表（楼中楼）不需要再进入下一层回复
    var onReply: (() -> Void)?
    let onDelete: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            RemoteImage(urlString: comment.user.avatarUrl,
                        placeholder: Image(systemName: "person.crop.circle"))
                .frame(width: 36, height: 36)
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 6) {
                // 昵称 + 时间
                HStack(alignment: .firstTextBaseline) {
                    Text(comment.user.nickname)
                        .font(.subheadline).bold()
                        .lineLimit(1)
                    Spacer()
                    Text(comment.timeText)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                // 内容
                Text(comment.content)
                    .font(.subheadline)
                    .fixedSize(horizontal: false, vertical: true)

                // IP 属地
                if let ip = comment.ipLocation, !ip.isEmpty {
                    Text(ip)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }

                // 被回复引用（回复了某条评论）
                if let first = comment.beReplied.first, let text = first.content, !text.isEmpty {
                    Text("\(first.user?.nickname ?? ""): \(text)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                        .padding(6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(.secondarySystemBackground))
                        .cornerRadius(6)
                }

                // 点赞 + 回复操作栏
                HStack(spacing: 20) {
                    Button(action: onLike) {
                        HStack(spacing: 3) {
                            Image(systemName: comment.liked ? "heart.fill" : "heart")
                            Text(comment.likedCountText)
                        }
                        .font(.caption)
                        .foregroundColor(comment.liked ? .red : .secondary)
                    }
                    .buttonStyle(BorderlessButtonStyle())
                    .disabled(!showLike)

                    if let onReply = onReply {
                        Button(action: onReply) {
                            Label("回复", systemImage: "bubble.right")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(BorderlessButtonStyle())
                    }

                    Spacer()
                }

                // 楼中楼首条预览（提示可展开）
                if let preview = comment.showFloorComment {
                    HStack(alignment: .top, spacing: 4) {
                        Image(systemName: "arrow.turn.down.right")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .padding(.top, 2)
                        Text("\(preview.user.nickname): \(preview.content)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(2)
                    }
                    .onTapGesture { onReply?() }
                }
            }
        }
        .padding(.vertical, 4)
        // 仅作者本人显示「删除」菜单（长按评论）
        .if(canDelete) { view in
            view.contextMenu {
                Button(action: onDelete) {
                    Label("删除评论", systemImage: "trash")
                }
            }
        }
    }
}

// MARK: - 底部输入栏

private struct CommentComposer: View {
    let isLoggedIn: Bool
    let sending: Bool
    @Binding var text: String
    let onSend: () -> Void
    let onNeedLogin: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            TextField(isLoggedIn ? "说点什么..." : "登录后可评论", text: $text)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color(.secondarySystemBackground))
                .cornerRadius(18)
                .lineLimit(1)
                .disabled(!isLoggedIn)

            Button(action: {
                if isLoggedIn { onSend() } else { onNeedLogin() }
            }) {
                Group {
                    if sending {
                        ProgressView()
                            .frame(width: 28, height: 28)
                    } else {
                        Image(systemName: isLoggedIn ? "arrow.up.circle.fill" : "person.crop.circle.badge.plus")
                            .font(.system(size: 28))
                            .foregroundColor(isLoggedIn ? Color.red : .secondary)
                    }
                }
            }
            .buttonStyle(BorderlessButtonStyle())
            // 未登录时按钮保持可点，用于弹出登录
            .disabled(sending || (isLoggedIn && text.trimmingCharacters(in: .whitespaces).isEmpty))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(.systemBackground))
    }
}

// MARK: - 键盘避让（iOS 14：底部输入栏跟随键盘上移）

/// 监听系统键盘高度，给内容底部加 padding，避免输入栏被键盘遮挡
struct KeyboardAdaptive: ViewModifier {
    @State private var keyboardHeight: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .padding(.bottom, keyboardHeight)
            .animation(.easeOut(duration: 0.25))   // iOS 14：用 animation(_:) 重载（带 value 的版本 iOS 15+）
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillChangeFrameNotification)) { note in
                guard let frame = note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else { return }
                keyboardHeight = frame.height
            }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
                keyboardHeight = 0
            }
    }
}

extension View {
    func keyboardAdaptive() -> some View {
        modifier(KeyboardAdaptive())
    }
}

// MARK: - 条件修饰符

extension View {
    /// 条件成立时应用 transform，否则返回原视图
    @ViewBuilder
    func `if`<Content: View>(_ condition: Bool, transform: (Self) -> Content) -> some View {
        if condition {
            transform(self)
        } else {
            self
        }
    }
}
