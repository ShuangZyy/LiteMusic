//
//  LyricsView.swift
//  LiteMusic
//
//  LRC 滚动歌词：当前行高亮并自动滚动到中间
//  使用 ScrollViewReader（iOS 14 可用）实现滚动定位
//

import SwiftUI

struct LyricsView: View {
    let lyrics: [LyricLine]
    let currentIndex: Int

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 14) {
                    // 顶部占位，让首行歌词也能滚动到中间
                    Color.clear.frame(height: 60)

                    if lyrics.isEmpty {
                        Text("暂无歌词")
                            .foregroundColor(.secondary)
                            .frame(height: 100)
                    } else {
                        ForEach(Array(lyrics.enumerated()), id: \.offset) { index, line in
                            Text(line.text.isEmpty ? "♪" : line.text)
                                .font(index == currentIndex ? .headline : .subheadline)
                                .foregroundColor(index == currentIndex ? Color.red : Color.secondary)
                                .multilineTextAlignment(.center)
                                .id(index)
                        }
                    }

                    Color.clear.frame(height: 60)
                }
                .frame(maxWidth: .infinity)
            }
            .onChange(of: currentIndex) { newIndex in
                withAnimation(.easeInOut) {
                    proxy.scrollTo(newIndex, anchor: .center)
                }
            }
        }
    }
}
