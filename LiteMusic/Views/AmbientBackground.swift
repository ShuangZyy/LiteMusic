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

    /// 处理后的模糊图（下采样 + 高斯模糊，避免大图在渲染时引发布局异常）
    @State private var blurredImage: UIImage?
    @State private var ambientColor: Color = Color(.systemBackground)
    @State private var loadToken = UUID()

    var body: some View {
        ZStack {
            // 静态底色铺满全屏（含状态栏/底部指示条），不参与动态布局
            Color(.systemBackground)
                .ignoresSafeArea()
            // 动态氛围内容只铺安全区，避免 ignoresSafeArea 影响外层 TabView / NavigationView 布局
            if let img = blurredImage {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFill()
                    .clipped()
                    .opacity(appearance.backgroundOpacity)
                ambientColor
                    .opacity(appearance.backgroundOpacity * 0.55)
            }
        }
        .allowsHitTesting(false)
        .onAppear(perform: loadCover)
        .onChange(of: coverURL) { _ in
            blurredImage = nil
            loadCover()
        }
    }

    private func loadCover() {
        let token = UUID()
        loadToken = token
        guard let coverURL = coverURL, let url = URL(string: coverURL) else {
            blurredImage = nil
            ambientColor = Color(.systemBackground)
            return
        }
        if let cached = ImageCache.shared.image(for: coverURL) {
            process(cached, token: token)
            return
        }
        URLSession.shared.dataTask(with: url) { data, _, _ in
            guard let data = data, let img = UIImage(data: data) else { return }
            ImageCache.shared.set(img, for: coverURL)
            DispatchQueue.main.async {
                // 仅在封面地址未再变化时应用，避免旧图覆盖新图
                if self.loadToken == token { self.process(img, token: token) }
            }
        }.resume()
    }

    /// 后台线程下采样 + 高斯模糊，主线程只负责回写状态，避免卡顿与缩放异常
    private func process(_ img: UIImage, token: UUID) {
        let blur = CGFloat(appearance.backgroundBlur)
        DispatchQueue.global(qos: .userInitiated).async {
            let small = img.downscaled(maxDimension: 256)
            let blurred = blur > 0 ? (small.blurred(radius: blur / 3) ?? small) : small
            let avg = img.averageColor()
            DispatchQueue.main.async {
                guard self.loadToken == token else { return }
                self.blurredImage = blurred
                var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
                avg.getRed(&r, green: &g, blue: &b, alpha: &a)
                self.ambientColor = Color(.sRGB, red: Double(r), green: Double(g), blue: Double(b), opacity: Double(a))
            }
        }
    }
}

extension UIImage {
    /// 下采样到指定最大边长（用于氛围背景，降低内存与渲染压力）
    func downscaled(maxDimension: CGFloat) -> UIImage {
        let size = self.size
        guard size.width > 0, size.height > 0 else { return self }
        let scale = min(1.0, maxDimension / max(size.width, size.height))
        guard scale < 1.0 else { return self }
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { _ in
            self.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }

    /// 高斯模糊（半径单位：像素）
    func blurred(radius: CGFloat) -> UIImage? {
        guard let ci = CIImage(image: self) else { return nil }
        let filter = CIFilter(name: "CIGaussianBlur",
                              parameters: [kCIInputImageKey: ci, kCIInputRadiusKey: radius])
        guard let output = filter?.outputImage else { return nil }
        let context = CIContext(options: [CIContextOption.useSoftwareRenderer: false])
        // 裁回原尺寸，避免高斯模糊在边缘外扩产生透明边
        guard let cg = context.createCGImage(output, from: ci.extent) else { return nil }
        return UIImage(cgImage: cg)
    }

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
