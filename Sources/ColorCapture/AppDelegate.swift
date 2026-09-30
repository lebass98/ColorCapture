import AppKit
import Carbon
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private let colorSampler = NSColorSampler()
    private var isCapturing = false
    private var didRequestScreenCapture = false

    private let recentKey = "recentColors"
    private let maxRecent = 12

    private var recentColors: [String] {
        get { UserDefaults.standard.stringArray(forKey: recentKey) ?? [] }
        set { UserDefaults.standard.set(Array(newValue.prefix(maxRecent)), forKey: recentKey) }
    }

    /// 캡처 이미지 저장 위치: ~/Pictures/ColorCapture
    private var captureFolder: URL {
        FileManager.default.urls(for: .picturesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ColorCapture", isDirectory: true)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        DebugLog.write("앱 시작 — 위치: \(Bundle.main.bundlePath), 화면 기록 권한: \(CGPreflightScreenCaptureAccess() ? "있음" : "없음"), 손쉬운 사용 권한: \(AXIsProcessTrusted() ? "있음" : "없음")")
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = NSImage(systemSymbolName: "eyedropper", accessibilityDescription: "ColorCapture")
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu

        // 단축키 (설정 창에서 바꿀 수 있음, 기본값 ⌃⇧C / ⌃⇧S)
        let store = ShortcutStore.shared
        store.register = { [weak self] in self?.registerHotKeys() ?? [] }
        store.unregister = {
            HotKeyCenter.shared.unregisterAll()
            MouseHotKeyCenter.shared.unregisterAll()
        }

        let failed = registerHotKeys()
        if !failed.isEmpty {
            let keys = failed.map { store.shortcut(for: $0).displayString }.joined(separator: ", ")
            HUD.shared.showMessage("단축키 등록 실패", "\(keys) — 다른 앱이 사용 중 (메뉴 → 단축키 설정)")
        }
    }

    /// 저장된 단축키를 모두 다시 등록하고, 실패한 기능을 돌려줌
    @discardableResult
    private func registerHotKeys() -> [ShortcutAction] {
        HotKeyCenter.shared.unregisterAll()
        MouseHotKeyCenter.shared.unregisterAll()
        var failed: [ShortcutAction] = []
        for action in ShortcutAction.allCases {
            let s = ShortcutStore.shared.shortcut(for: action)
            let handler: () -> Void = { [weak self] in self?.perform(action) }
            if let button = s.mouseButton {
                MouseHotKeyCenter.shared.register(button: button, modifiers: s.modifiers, handler: handler)
            } else if !HotKeyCenter.shared.register(keyCode: s.keyCode, modifiers: s.modifiers, handler: handler) {
                failed.append(action)
            }
        }
        return failed
    }

    private func perform(_ action: ShortcutAction) {
        switch action {
        case .pickColor: pickColor()
        case .captureRegion: captureRegion()
        }
    }

    /// 현재 단축키를 표시하는 메뉴 항목
    private func actionMenuItem(_ action: ShortcutAction, selector: Selector) -> NSMenuItem {
        let s = ShortcutStore.shared.shortcut(for: action)
        let item: NSMenuItem
        if let key = s.menuKeyEquivalent {
            item = NSMenuItem(title: action.title, action: selector, keyEquivalent: key)
            item.keyEquivalentModifierMask = s.menuModifierMask
        } else {
            item = NSMenuItem(title: "\(action.title)   \(s.displayString)", action: selector, keyEquivalent: "")
        }
        item.image = NSImage(systemSymbolName: action.symbol, accessibilityDescription: nil)
        item.target = self
        return item
    }

    // MARK: - 메뉴 (열 때마다 새로 구성)

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        menu.addItem(actionMenuItem(.pickColor, selector: #selector(pickColor)))
        menu.addItem(actionMenuItem(.captureRegion, selector: #selector(captureRegion)))

        menu.addItem(.separator())

        let colors = recentColors
        if colors.isEmpty {
            let empty = NSMenuItem(title: "최근 색상 없음", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            menu.addItem(empty)
        } else {
            let header = NSMenuItem(title: "최근 색상 (클릭하면 복사)", action: nil, keyEquivalent: "")
            header.isEnabled = false
            menu.addItem(header)
            for hex in colors {
                let item = NSMenuItem(title: "\(hex)   \(rgbString(hex))", action: #selector(copyRecent(_:)), keyEquivalent: "")
                item.representedObject = hex
                item.image = swatch(hex)
                item.target = self
                menu.addItem(item)
            }
            let clear = NSMenuItem(title: "기록 지우기", action: #selector(clearRecent), keyEquivalent: "")
            clear.target = self
            menu.addItem(clear)
        }

        menu.addItem(.separator())

        let folder = NSMenuItem(title: "캡처 폴더 열기", action: #selector(openCaptureFolder), keyEquivalent: "")
        folder.target = self
        menu.addItem(folder)

        let shortcuts = NSMenuItem(title: "단축키 설정…", action: #selector(openShortcutSettings), keyEquivalent: ",")
        shortcuts.image = NSImage(systemSymbolName: "keyboard", accessibilityDescription: nil)
        shortcuts.target = self
        menu.addItem(shortcuts)

        let login = NSMenuItem(title: "로그인 시 자동 실행", action: #selector(toggleLoginItem), keyEquivalent: "")
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        login.target = self
        menu.addItem(login)

        menu.addItem(.separator())
        let relaunch = NSMenuItem(title: "ColorCapture 다시 시작", action: #selector(relaunchApp), keyEquivalent: "")
        relaunch.target = self
        menu.addItem(relaunch)
        menu.addItem(NSMenuItem(title: "ColorCapture 종료", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
    }

    // MARK: - 색 추출

    @objc func pickColor() {
        NSApp.activate(ignoringOtherApps: true)
        colorSampler.show { [weak self] color in
            guard let self, let color, let rgb = color.usingColorSpace(.sRGB) else { return }
            let hex = String(format: "#%02X%02X%02X",
                             Int((rgb.redComponent * 255).rounded()),
                             Int((rgb.greenComponent * 255).rounded()),
                             Int((rgb.blueComponent * 255).rounded()))
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(hex, forType: .string)

            var list = self.recentColors.filter { $0 != hex }
            list.insert(hex, at: 0)
            self.recentColors = list

            HUD.shared.showColor(rgb, hex: hex)
        }
    }

    @objc private func copyRecent(_ sender: NSMenuItem) {
        guard let hex = sender.representedObject as? String else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(hex, forType: .string)
        if let color = color(from: hex) { HUD.shared.showColor(color, hex: hex) }
    }

    @objc private func clearRecent() {
        recentColors = []
    }

    // MARK: - 영역 캡처

    @objc func captureRegion() {
        guard !isCapturing else { return }

        // 화면 기록 권한이 없으면 캡처하지 않고 안내 (권한은 앱을 다시 켜야 적용됨)
        DebugLog.write("캡처 시작 — 화면 기록 권한: \(CGPreflightScreenCaptureAccess() ? "있음" : "없음")")
        guard CGPreflightScreenCaptureAccess() else {
            if didRequestScreenCapture {
                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!)
            } else {
                didRequestScreenCapture = true
                CGRequestScreenCaptureAccess() // 처음 한 번은 시스템 권한 요청 창
            }
            HUD.shared.showMessage("화면 기록 권한이 필요해요",
                                   "ColorCapture를 켠 뒤 메뉴 → 다시 시작")
            return
        }

        do {
            try FileManager.default.createDirectory(at: captureFolder, withIntermediateDirectories: true)
        } catch {
            HUD.shared.showMessage("폴더 생성 실패", error.localizedDescription)
            return
        }

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        let fileURL = captureFolder.appendingPathComponent("Capture_\(formatter.string(from: Date())).png")

        // macOS 기본 screencapture: -i = 마우스로 드래그해서 영역 선택 (Esc 취소, 스페이스 = 창 선택)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        process.arguments = ["-i", fileURL.path]
        let errorPipe = Pipe()
        process.standardError = errorPipe
        process.terminationHandler = { [weak self] p in
            let errorText = String(data: errorPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            DebugLog.write("screencapture 종료 코드: \(p.terminationStatus), 파일 생성: \(FileManager.default.fileExists(atPath: fileURL.path)), 오류: \(errorText.trimmingCharacters(in: .whitespacesAndNewlines))")
            DispatchQueue.main.async {
                self?.isCapturing = false
                // Esc로 취소하면 파일이 만들어지지 않음
                guard FileManager.default.fileExists(atPath: fileURL.path),
                      let image = NSImage(contentsOf: fileURL) else { return }
                NSPasteboard.general.clearContents()
                NSPasteboard.general.writeObjects([image])
                HUD.shared.showImage(image, fileName: fileURL.lastPathComponent)
            }
        }

        do {
            isCapturing = true
            try process.run()
        } catch {
            isCapturing = false
            DebugLog.write("screencapture 실행 실패: \(error.localizedDescription)")
            HUD.shared.showMessage("캡처 실패", error.localizedDescription)
        }
    }

    @objc private func openCaptureFolder() {
        try? FileManager.default.createDirectory(at: captureFolder, withIntermediateDirectories: true)
        NSWorkspace.shared.open(captureFolder)
    }

    /// 권한 변경 후 적용하려면 앱을 다시 켜야 함
    @objc private func relaunchApp() {
        let path = Bundle.main.bundlePath
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", "sleep 0.5; /usr/bin/open \"$0\"", path]
        try? process.run()
        NSApp.terminate(nil)
    }

    @objc private func openShortcutSettings() {
        ShortcutSettingsWindow.shared.show()
    }

    // MARK: - 로그인 시 자동 실행

    @objc private func toggleLoginItem() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            HUD.shared.showMessage("자동 실행 설정 실패", error.localizedDescription)
        }
    }

    // MARK: - 도우미

    private func color(from hex: String) -> NSColor? {
        guard hex.count == 7, let value = Int(hex.dropFirst(), radix: 16) else { return nil }
        return NSColor(srgbRed: CGFloat((value >> 16) & 0xFF) / 255,
                       green: CGFloat((value >> 8) & 0xFF) / 255,
                       blue: CGFloat(value & 0xFF) / 255,
                       alpha: 1)
    }

    private func rgbString(_ hex: String) -> String {
        guard let value = Int(hex.dropFirst(), radix: 16) else { return "" }
        return "rgb(\((value >> 16) & 0xFF), \((value >> 8) & 0xFF), \(value & 0xFF))"
    }

    private func swatch(_ hex: String) -> NSImage? {
        guard let color = color(from: hex) else { return nil }
        return NSImage(size: NSSize(width: 14, height: 14), flipped: false) { rect in
            let path = NSBezierPath(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), xRadius: 3, yRadius: 3)
            color.setFill()
            path.fill()
            NSColor.gray.withAlphaComponent(0.5).setStroke()
            path.stroke()
            return true
        }
    }
}
