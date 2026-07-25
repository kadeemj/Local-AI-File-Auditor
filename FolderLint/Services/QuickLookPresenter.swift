import AppKit
import QuickLookUI
import SwiftUI

/// Presents the system Quick Look panel for a single local file URL.
enum QuickLookPresenter {
    @MainActor
    private static var retained: PreviewController?

    @MainActor
    static func preview(url: URL) {
        let controller = PreviewController(url: url)
        retained = controller
        guard let panel = QLPreviewPanel.shared() else { return }
        panel.dataSource = controller
        panel.delegate = controller
        panel.makeKeyAndOrderFront(nil)
        panel.reloadData()
    }
}

final class PreviewController: NSObject, QLPreviewPanelDataSource, QLPreviewPanelDelegate {
    let url: URL

    init(url: URL) {
        self.url = url
    }

    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int { 1 }

    func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> (any QLPreviewItem)! {
        url as NSURL
    }
}
