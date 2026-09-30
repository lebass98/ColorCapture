import AppKit
import SwiftUI

/// 마우스 근처에 잠깐 떴다 사라지는 알림 창
final class HUD {
    static let shared = HUD()

    private var panel: NSPanel?
    private var hideWork: DispatchWorkItem?

    func showColor(_ color: NSColor, hex: String) {
        show(HUDView(color: Color(nsColor: color), image: nil, title: hex, subtitle: "복사됨"))
    }

    func showImage(_ image: NSImage, fileName: String) {
        show(HUDView(color: nil, image: image, title: "캡처 완료", subtitle: "클립보드에 복사됨 · \(fileName)"))
    }

    func showMessage(_ title: String, _ subtitle: String) {
        show(HUDView(color: nil, image: nil, title: title, subtitle: subtitle))
    }

    private func show(_ view: HUDView) {
        panel?.orderOut(nil)
        hideWork?.cancel()

        let hosting = NSHostingView(rootView: view)
        hosting.frame.size = hosting.fittingSize

        let panel = NSPanel(contentRect: NSRect(origin: .zero, size: hosting.fittingSize),
                            styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered,
                            defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .statusBar
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentView = hosting

        // 마우스 오른쪽 아래에 표시하고, 화면 밖으로 나가지 않게 조정
        let mouse = NSEvent.mouseLocation
        var origin = NSPoint(x: mouse.x + 16, y: mouse.y - hosting.fittingSize.height - 16)
        if let screen = NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) }) {
            let f = screen.visibleFrame
            origin.x = min(max(origin.x, f.minX + 8), f.maxX - hosting.fittingSize.width - 8)
            origin.y = min(max(origin.y, f.minY + 8), f.maxY - hosting.fittingSize.height - 8)
        }
        panel.setFrameOrigin(origin)
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { $0.duration = 0.12; panel.animator().alphaValue = 1 }
        self.panel = panel

        let work = DispatchWorkItem { [weak self, weak panel] in
            guard let panel else { return }
            NSAnimationContext.runAnimationGroup({ $0.duration = 0.25; panel.animator().alphaValue = 0 },
                                                 completionHandler: {
                panel.orderOut(nil)
                if self?.panel === panel { self?.panel = nil }
            })
        }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6, execute: work)
    }
}

private struct HUDView: View {
    let color: Color?
    let image: NSImage?
    let title: String
    let subtitle: String

    var body: some View {
        HStack(spacing: 10) {
            if let color {
                RoundedRectangle(cornerRadius: 6)
                    .fill(color)
                    .frame(width: 32, height: 32)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(.white.opacity(0.4), lineWidth: 1))
            }
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: 80, maxHeight: 50)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 14, weight: .semibold, design: .monospaced))
                Text(subtitle).font(.system(size: 11)).foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .fixedSize()
    }
}
