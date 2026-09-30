import AppKit
import ApplicationServices
import Carbon
import Combine
import SwiftUI

/// "단축키 설정" 창
final class ShortcutSettingsWindow: NSObject, NSWindowDelegate {
    static let shared = ShortcutSettingsWindow()

    private var window: NSWindow?

    func show() {
        if window == nil {
            let w = NSWindow(contentRect: .zero, styleMask: [.titled, .closable], backing: .buffered, defer: false)
            w.title = "단축키 설정"
            w.contentView = NSHostingView(rootView: ShortcutSettingsView())
            w.isReleasedWhenClosed = false
            w.delegate = self
            w.center()
            window = w
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        ShortcutRecorder.shared.cancel()
    }
}

/// 키 입력받기 (버튼을 누른 뒤 다음 키 조합을 가로챔)
final class ShortcutRecorder: ObservableObject {
    static let shared = ShortcutRecorder()

    @Published private(set) var recording: ShortcutAction?
    @Published var message: String?

    private var monitor: Any?
    private let store = ShortcutStore.shared

    func toggle(_ action: ShortcutAction) {
        if recording == action { cancel() } else { start(action) }
    }

    func start(_ action: ShortcutAction) {
        stopMonitor()
        store.unregister?() // 입력하는 키를 기존 단축키가 가로채지 않도록
        recording = action
        message = nil
        // 키보드 키 또는 마우스 버튼(휠 클릭, 옆 버튼)을 받음
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .otherMouseDown]) { [weak self] event in
            self?.handle(event)
            return nil // 입력한 키는 다른 곳으로 전달하지 않음
        }
    }

    func cancel() {
        guard recording != nil else { return }
        stopMonitor()
        _ = store.register?()
    }

    private func handle(_ event: NSEvent) {
        guard let action = recording else { return }

        if event.type == .otherMouseDown {
            let shortcut = Shortcut(mouseButton: event.buttonNumber,
                                    modifiers: Shortcut.carbonModifiers(event.modifierFlags))
            guard shortcut.isValid else { return }
            stopMonitor()
            message = store.update(action, to: shortcut)
            return
        }

        let shortcut = Shortcut(event: event)
        if shortcut.keyCode == kVK_Escape && shortcut.modifiers == 0 {
            cancel()
            return
        }
        guard shortcut.isValid else {
            message = "⌘ ⌃ ⌥ 중 하나 이상과 함께 눌러 주세요. (F1~F20은 단독 가능)"
            return
        }
        stopMonitor()
        message = store.update(action, to: shortcut)
    }

    private func stopMonitor() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        recording = nil
    }
}

private struct ShortcutSettingsView: View {
    @ObservedObject private var store = ShortcutStore.shared
    @ObservedObject private var recorder = ShortcutRecorder.shared
    @State private var accessibilityGranted = AXIsProcessTrusted()

    private let permissionCheck = Timer.publish(every: 2, on: .main, in: .common).autoconnect()

    private var usesMouse: Bool {
        ShortcutAction.allCases.contains { store.shortcut(for: $0).mouseButton != nil }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Grid(alignment: .leading, horizontalSpacing: 20, verticalSpacing: 12) {
                ForEach(ShortcutAction.allCases) { action in
                    GridRow {
                        Label(action.title, systemImage: action.symbol)
                            .frame(width: 110, alignment: .leading)
                        recorderButton(action)
                    }
                }
            }

            Text(recorder.message ?? "버튼을 누른 뒤 원하는 키 조합이나 마우스 버튼(휠 클릭, 옆 버튼)을 누르세요. (Esc = 취소)")
                .font(.callout)
                .foregroundStyle(recorder.message == nil ? Color.secondary : Color.red)
                .fixedSize(horizontal: false, vertical: true)

            if usesMouse && !accessibilityGranted {
                VStack(alignment: .leading, spacing: 6) {
                    Label("손쉬운 사용 권한이 없어요", systemImage: "exclamationmark.triangle.fill")
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(.orange)
                    Text("마우스 단축키는 동작하지만, 다른 앱의 원래 동작(예: 브라우저 휠 클릭 = 새 탭 열기)도 같이 일어나요. 권한을 켜면 자동으로 적용돼요.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Button("손쉬운 사용 설정 열기") {
                        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
                    }
                }
                .padding(10)
                .background(Color.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
            }

            HStack {
                Spacer()
                Button("기본값으로 되돌리기") {
                    recorder.cancel()
                    store.resetAll()
                    recorder.message = nil
                }
            }
        }
        .padding(20)
        .frame(width: 400)
        .onReceive(permissionCheck) { _ in accessibilityGranted = AXIsProcessTrusted() }
    }

    private func recorderButton(_ action: ShortcutAction) -> some View {
        let isRecording = recorder.recording == action
        return Button {
            recorder.toggle(action)
        } label: {
            Text(isRecording ? "키/마우스 버튼을 누르세요…" : store.shortcut(for: action).displayString)
                .font(.system(size: 14, weight: .medium, design: .monospaced))
                .frame(minWidth: 190)
                .padding(.vertical, 2)
        }
        .buttonStyle(.bordered)
        .tint(isRecording ? .accentColor : nil)
    }
}
