import AppKit
import ApplicationServices

/// 마우스 버튼 단축키 (휠 클릭, 옆 버튼 등)
///
/// - 손쉬운 사용 권한이 있으면: 이벤트 탭으로 가로채서 다른 앱에는 전달하지 않음
/// - 권한이 없으면: 전역 모니터로 감지만 함 (다른 앱의 원래 동작도 같이 일어남)
final class MouseHotKeyCenter {
    static let shared = MouseHotKeyCenter()

    private struct Binding {
        let button: Int
        let modifiers: Int
        let handler: () -> Void
    }

    private var bindings: [Binding] = []
    private var tap: CFMachPort?
    private var tapSource: CFRunLoopSource?
    private var globalMonitor: Any?
    private var permissionTimer: Timer?
    private var swallowedButtons: Set<Int> = [] // 누름을 가로챈 버튼 → 떼는 이벤트도 가로챔
    private var didPrompt = false

    /// 이벤트를 가로챌 수 있는 상태인지 (손쉬운 사용 권한 있음)
    var canSwallow: Bool { tap != nil }

    func register(button: Int, modifiers: Int, handler: @escaping () -> Void) {
        bindings.append(Binding(button: button, modifiers: modifiers, handler: handler))
        start()
    }

    func unregisterAll() {
        bindings.removeAll()
        stop()
    }

    // MARK: - 시작 / 정지

    private func start() {
        guard tap == nil, globalMonitor == nil else { return }

        if startTap() { return }

        // 권한 없음 → 권한 요청 창을 한 번 띄우고, 감지만 하는 방식으로 대체
        if !didPrompt {
            didPrompt = true
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
            _ = AXIsProcessTrustedWithOptions(options)
        }
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .otherMouseDown) { [weak self] event in
            self?.match(button: event.buttonNumber, modifiers: Shortcut.carbonModifiers(event.modifierFlags))?.handler()
        }
        // 권한이 허용되면 자동으로 가로채는 방식으로 전환
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            guard let self, AXIsProcessTrusted() else { return }
            self.stop()
            if !self.bindings.isEmpty { self.start() }
        }
    }

    private func startTap() -> Bool {
        let mask = (1 << CGEventType.otherMouseDown.rawValue) | (1 << CGEventType.otherMouseUp.rawValue)
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap,
                                          place: .headInsertEventTap,
                                          options: .defaultTap,
                                          eventsOfInterest: CGEventMask(mask),
                                          callback: mouseTapCallback,
                                          userInfo: nil) else { return false }
        let source = CFMachPortCreateRunLoopSource(nil, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        self.tap = tap
        self.tapSource = source
        return true
    }

    private func stop() {
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
            if let tapSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), tapSource, .commonModes) }
            CFMachPortInvalidate(tap)
        }
        tap = nil
        tapSource = nil
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        globalMonitor = nil
        permissionTimer?.invalidate()
        permissionTimer = nil
        swallowedButtons.removeAll()
    }

    // MARK: - 이벤트 처리

    private func match(button: Int, modifiers: Int) -> Binding? {
        bindings.first { $0.button == button && $0.modifiers == modifiers }
    }

    fileprivate func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        // 시스템이 탭을 꺼 버리면 다시 켬
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passUnretained(event)
        }

        let button = Int(event.getIntegerValueField(.mouseEventButtonNumber))

        if type == .otherMouseUp {
            if swallowedButtons.remove(button) != nil { return nil }
            return Unmanaged.passUnretained(event)
        }

        guard type == .otherMouseDown,
              let binding = match(button: button, modifiers: Self.carbonModifiers(event.flags)) else {
            return Unmanaged.passUnretained(event)
        }
        swallowedButtons.insert(button)
        DispatchQueue.main.async { binding.handler() }
        return nil // 다른 앱에는 전달하지 않음
    }

    private static func carbonModifiers(_ flags: CGEventFlags) -> Int {
        var f: NSEvent.ModifierFlags = []
        if flags.contains(.maskControl) { f.insert(.control) }
        if flags.contains(.maskAlternate) { f.insert(.option) }
        if flags.contains(.maskShift) { f.insert(.shift) }
        if flags.contains(.maskCommand) { f.insert(.command) }
        return Shortcut.carbonModifiers(f)
    }
}

private func mouseTapCallback(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent,
                              refcon: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    MouseHotKeyCenter.shared.handle(type: type, event: event)
}
