//
//  RemoteImage.swift
//  LiteMusic
//
//  远程图片加载组件（使用 URLSession + NSCache，iOS 14 兼容，避免使用 iOS 15 的 AsyncImage）
//

import SwiftUI
import UIKit

/// 从网络加载图片的视图，带内存缓存
struct RemoteImage: View {
    let urlString: String?
    let placeholder: Image
    @State private var image: UIImage?
    @State private var loadToken = UUID()

    var body: some View {
        Group {
            if let image = image {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                placeholder.resizable().scaledToFit().foregroundColor(.secondary)
            }
        }
        .onAppear(perform: load)
        // 地址变化时重新加载（例如切歌后封面跟着换）
        .onChange(of: urlString) { _ in
            image = nil
            load()
        }
    }

    private func load() {
        let token = UUID()
        loadToken = token
        guard let urlString = urlString, let url = URL(string: urlString) else { return }
        if let cached = ImageCache.shared.image(for: urlString) {
            image = cached
            return
        }
        URLSession.shared.dataTask(with: url) { data, _, _ in
            guard let data = data, let img = UIImage(data: data) else { return }
            ImageCache.shared.set(img, for: urlString)
            DispatchQueue.main.async {
                // 仅在地址未再变化时应用，避免旧图覆盖新图
                if self.loadToken == token { self.image = img }
            }
        }.resume()
    }
}

/// 简单的图片内存缓存
final class ImageCache {
    static let shared = ImageCache()
    private let cache = NSCache<NSString, UIImage>()
    private init() {}

    func image(for key: String) -> UIImage? {
        cache.object(forKey: key as NSString)
    }

    func set(_ image: UIImage, for key: String) {
        cache.setObject(image, forKey: key as NSString)
    }
}
