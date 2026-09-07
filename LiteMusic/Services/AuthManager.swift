//
//  AuthManager.swift
//  LiteMusic
//
//  登录态管理：保存/加载 cookie 与用户信息，并提供登录、退出接口
//

import Foundation
import Combine

final class AuthManager: ObservableObject {
    static let shared = AuthManager()

    /// 是否已登录
    @Published var isLoggedIn = false
    /// 当前用户信息
    @Published var user: UserProfile?
    /// 登录 cookie
    @Published var cookie: String = ""
    /// 用户 ID
    @Published var uid: Int = 0

    private let cookieKey = "netease_cookie"
    private let uidKey = "netease_uid"

    private init() {
        loadState()
    }

    /// 从 Keychain / UserDefaults 恢复登录态
    private func loadState() {
        cookie = KeychainHelper.shared.read(key: cookieKey) ?? ""
        uid = UserDefaults.standard.integer(forKey: uidKey)
        isLoggedIn = !cookie.isEmpty
    }

    /// 保存登录态
    func saveLogin(cookie: String, uid: Int) {
        guard !cookie.isEmpty else { return }
        self.cookie = cookie
        self.uid = uid
        KeychainHelper.shared.save(cookie, key: cookieKey)
        UserDefaults.standard.set(uid, forKey: uidKey)
        isLoggedIn = true
    }

    /// 退出登录，清除本地登录状态
    func logout() {
        cookie = ""
        uid = 0
        user = nil
        isLoggedIn = false
        KeychainHelper.shared.delete(key: cookieKey)
        UserDefaults.standard.removeObject(forKey: uidKey)
    }

    /// 手机号登录
    func login(phone: String, password: String, completion: @escaping (Result<Void, Error>) -> Void) {
        APIService.shared.cellphoneLogin(phone: phone, password: password) { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self else { return }
                switch result {
                case .success(let r):
                    self.saveLogin(cookie: r.cookie, uid: r.uid)
                    self.user = r.profile
                    completion(.success(()))
                case .failure(let e):
                    completion(.failure(e))
                }
            }
        }
    }

    /// 刷新用户信息（登录后调用，获取昵称/头像/uid）
    func refreshUserProfile() {
        guard !cookie.isEmpty else { return }
        APIService.shared.loginStatus(cookie: cookie) { [weak self] profile in
            DispatchQueue.main.async {
                guard let self = self, let profile = profile else { return }
                self.user = profile
                self.uid = profile.userId
                UserDefaults.standard.set(profile.userId, forKey: self.uidKey)
            }
        }
    }
}
