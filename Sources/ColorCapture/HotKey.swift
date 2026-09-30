import Carbon

/// 전역 단축키 등록 (Carbon API — 손쉬운 사용 권한 없이 동작)
final class HotKeyCenter {
    static let shared = HotKeyCenter()

    private var handlers: [UInt32: () -> Void] = [:]
    private var refs: [EventHotKeyRef] = []
    private var nextID: UInt32 = 1

    private init() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                 eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
            var hotKeyID = EventHotKeyID()
            GetEventParameter(event,
                              EventParamName(kEventParamDirectObject),
                              EventParamType(typeEventHotKeyID),
                              nil,
                              MemoryLayout<EventHotKeyID>.size,
                              nil,
                              &hotKeyID)
            let id = hotKeyID.id
            DispatchQueue.main.async { HotKeyCenter.shared.handlers[id]?() }
            return noErr
        }, 1, &spec, nil, nil)
    }

    /// 성공하면 true, 다른 앱이 이미 쓰는 단축키면 false
    @discardableResult
    func register(keyCode: Int, modifiers: Int, handler: @escaping () -> Void) -> Bool {
        let id = nextID
        nextID += 1
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(UInt32(keyCode),
                                         UInt32(modifiers),
                                         EventHotKeyID(signature: OSType(0x434C_4350), id: id), // 'CLCP'
                                         GetApplicationEventTarget(),
                                         0,
                                         &ref)
        guard status == noErr, let ref else { return false }
        refs.append(ref)
        handlers[id] = handler
        return true
    }

    func unregisterAll() {
        refs.forEach { UnregisterEventHotKey($0) }
        refs.removeAll()
        handlers.removeAll()
    }
}
