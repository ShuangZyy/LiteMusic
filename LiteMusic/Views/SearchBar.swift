//
//  SearchBar.swift
//  LiteMusic
//
//  搜索栏：使用 UIKit 的 UISearchBar 封装（iOS 14 无 .searchable，需用 UIKit 替代）
//

import SwiftUI
import UIKit

struct SearchBar: UIViewRepresentable {
    @Binding var text: String
    var placeholder: String
    var onCommit: () -> Void

    func makeUIView(context: Context) -> UISearchBar {
        let bar = UISearchBar()
        bar.placeholder = placeholder
        bar.delegate = context.coordinator
        bar.searchBarStyle = .minimal
        bar.autocapitalizationType = .none
        bar.enablesReturnKeyAutomatically = true
        return bar
    }

    func updateUIView(_ uiView: UISearchBar, context: Context) {
        uiView.text = text
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UISearchBarDelegate {
        let parent: SearchBar
        init(_ parent: SearchBar) { self.parent = parent }

        func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) {
            parent.text = searchText
        }

        func searchBarSearchButtonClicked(_ searchBar: UISearchBar) {
            searchBar.resignFirstResponder()
            parent.onCommit()
        }
    }
}
