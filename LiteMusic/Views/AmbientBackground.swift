//
//  AmbientBackground.swift
//  LiteMusic
//
//  氛围背景：当前歌曲封面做模糊 + 提取平均色作为氛围色，铺在主界面/播放器底部
//

import SwiftUI
import UIKit
import CoreImage

struct AmbientBackground: View {
    /// 当前封面地址（nil 时显示纯背景）
    let coverURL: String?
    @EnvironmentObject var appearance: AppearanceManager

    @State private var coverImage: UIImage?
    @State private var ambientColor: Color = Color(.systemBackground)
    @State private var loadToken = UUID()

    var body: some View {
        ZStack {
            // 基底色，保证文字可读性
            Color(.systemBackground)
            if let img = coverImage {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFill()
                    .blur(radius: CGFloat(appearance.backgroundBlur))
                    .opacity(appearance.backgroundOpacity)
                    .clipped()
                // 氛围色叠加
                ambientColor
                    .opacity(appearance.backgroundOpacity * 0.55)
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .onAppear(perform: loadCover)
        .onChange(of: coverURL) { _ in
            coverImage = nil
            loadCover()
        }
    }

    private func loadCover() {
        let token = UUID()
        loadToken = token
        guard let coverURL = coverURL, let url = URL(string: coverURL) else {
            coverImage = nil
            ambientColor = Color(.systemBackground)
            return
        }
        if let cached = ImageCache.shared.image(for: coverURL) {
            apply(cached)
            return
        }
        URLSession.shared.dataTask(with: url) { data, _, _ in
            guard let data = data, let img = UIImage(data: data) else { return }
            ImageCache.shared.set(img, for: coverURL)
            DispatchQueue.main.async {
                // 仅在封面地址未再变化时应用，避免旧图覆盖新图
                if self.loadToken == token { self.apply(img) }
            }
        }.resume()
    }

    private func apply(_ img: UIImage) {
        coverImage = img
        let avg = img.averageColor()
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        avg.getRed(&r, green: &g, blue: &b, alpha: &a)
        ambientColor = Color(.sRGB, red: Double(r), green: Double(g), blue: Double(b), opacity: Double(a))
    }
}

extension UIImage {
    /// 提取图片平均色，用作氛围色
    func averageColor() -> UIColor {
        guard let ci = CIImage(image: self) else { return .systemBackground }
        guard let filter = CIFilter(name: "CIAreaAverage",
                                    parameters: [kCIInputImageKey: ci,
                                                 kCIInputExtentKey: CIVector(cgRect: ci.extent)]),
              let output = filter.outputImage else { return .systemBackground }
        var bitmap = [UInt8](repeating: 0, count: 4)
        CIContext().render(output, toBitmap: &bitmap, rowBytes: 4,
                           bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
                           format: .RGBA8, colorSpace: CGColorSpaceCreateDeviceRGB())
        return UIColor(red: CGFloat(bitmap[0]) / 255.0,
                       green: CGFloat(bitmap[1]) / 255.0,
                       blue: CGFloat(bitmap[2]) / 255.0,
                       alpha: 1.0)
    }
}
