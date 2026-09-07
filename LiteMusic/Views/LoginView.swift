//
//  LoginView.swift
//  LiteMusic
//
//  登录界面：支持扫码登录与手机号登录
//

import SwiftUI
import UIKit

struct LoginView: View {
    @EnvironmentObject var auth: AuthManager
    @Environment(\.presentationMode) var presentationMode

    @State private var loginMode: LoginMode = .qr
    @StateObject private var qrViewModel = QRLoginViewModel()
    @State private var phone = ""
    @State private var password = ""
    @State private var isLoggingIn = false
    @State private var errorMessage: String?

    enum LoginMode {
        case qr, phone
    }

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    Picker("登录方式", selection: $loginMode) {
                        Text("扫码登录").tag(LoginMode.qr)
                        Text("手机号登录").tag(LoginMode.phone)
                    }
                    .pickerStyle(SegmentedPickerStyle())
                    .padding(.horizontal)

                    if loginMode == .qr {
                        qrSection
                    } else {
                        phoneSection
                    }

                    if let error = errorMessage {
                        Text(error)
                            .font(.footnote)
                            .foregroundColor(.red)
                            .padding(.horizontal)
                    }
                    Spacer()
                }
                .padding(.top, 20)
            }
            .navigationTitle("登录")
            .navigationBarItems(leading: Button("关闭") {
                presentationMode.wrappedValue.dismiss()
            })
            // 登录成功统一在此关闭登录页
            .onReceive(auth.$isLoggedIn) { loggedIn in
                if loggedIn {
                    presentationMode.wrappedValue.dismiss()
                }
            }
        }
    }

    // MARK: - 扫码登录

    private var qrSection: some View {
        VStack(spacing: 12) {
            if let image = qrViewModel.qrImage {
                Image(uiImage: image)
                    .resizable()
                    .interpolation(.none)   // 保持二维码清晰
                    .scaledToFit()
                    .frame(width: 220, height: 220)
                    .padding()
                    .background(Color.white)
                    .cornerRadius(12)
            } else {
                Rectangle()
                    .fill(Color.gray.opacity(0.2))
                    .frame(width: 220, height: 220)
                    .cornerRadius(12)
                    .overlay(ProgressView())
            }
            Text(qrViewModel.statusText)
                .font(.subheadline)
                .foregroundColor(.secondary)
            Button("刷新二维码") { qrViewModel.refresh() }
                .font(.footnote)
        }
        .onAppear { qrViewModel.start() }
        .onDisappear { qrViewModel.stop() }
    }

    // MARK: - 手机号登录

    private var phoneSection: some View {
        VStack(spacing: 16) {
            TextField("手机号", text: $phone)
                .keyboardType(.numberPad)
                .textFieldStyle(RoundedBorderTextFieldStyle())
            SecureField("密码", text: $password)
                .textFieldStyle(RoundedBorderTextFieldStyle())
            Button(action: doPhoneLogin) {
                Group {
                    if isLoggingIn {
                        ProgressView()
                    } else {
                        Text("登录").frame(maxWidth: .infinity)
                    }
                }
            }
            .padding(.vertical, 12)
            .background(Color.red)
            .foregroundColor(.white)
            .cornerRadius(10)
            .disabled(phone.isEmpty || password.isEmpty || isLoggingIn)
        }
        .padding(.horizontal, 30)
    }

    private func doPhoneLogin() {
        isLoggingIn = true
        errorMessage = nil
        auth.login(phone: phone, password: password) { result in
            isLoggingIn = false
            if case .failure(let e) = result {
                errorMessage = e.localizedDescription
            }
        }
    }
}

// MARK: - 二维码登录 ViewModel

final class QRLoginViewModel: ObservableObject {
    @Published var qrImage: UIImage?
    @Published var statusText = "请使用网易云音乐 App 扫码登录"

    private var timer: Timer?
    private var key = ""

    func start() {
        refresh()
    }

    func refresh() {
        statusText = "正在生成二维码..."
        APIService.shared.qrKey { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .success(let unikey):
                self.key = unikey
                self.loadQRImage(key: unikey)
            case .failure(let e):
                self.statusText = e.localizedDescription
            }
        }
    }

    private func loadQRImage(key: String) {
        APIService.shared.qrCreate(key: key) { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .success(let base64):
                if let data = Data(base64Encoded: base64), let img = UIImage(data: data) {
                    DispatchQueue.main.async {
                        self.qrImage = img
                        self.statusText = "请使用网易云音乐 App 扫码登录"
                    }
                    self.startPolling()
                } else {
                    self.statusText = "二维码解析失败"
                }
            case .failure(let e):
                self.statusText = e.localizedDescription
            }
        }
    }

    private func startPolling() {
        stopTimer()
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            self?.checkStatus()
        }
    }

    private func checkStatus() {
        guard !key.isEmpty else { return }
        APIService.shared.qrCheck(key: key) { [weak self] result in
            guard let self = self else { return }
            DispatchQueue.main.async {
                switch result {
                case .success(let r):
                    switch r.code {
                    case 800:
                        self.statusText = "等待扫码..."
                    case 801:
                        self.statusText = "已扫码，请在手机上确认登录"
                    case 802:
                        self.stopTimer()
                        self.statusText = "登录成功"
                        AuthManager.shared.saveLogin(cookie: r.cookie, uid: 0)
                        AuthManager.shared.refreshUserProfile()
                    case 803:
                        self.statusText = "二维码已过期，请刷新"
                        self.stopTimer()
                    default:
                        break
                    }
                case .failure(let e):
                    self.statusText = e.localizedDescription
                }
            }
        }
    }

    func stop() {
        stopTimer()
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }
}
