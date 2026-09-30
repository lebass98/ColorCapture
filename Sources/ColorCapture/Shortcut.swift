import AppKit
import Carbon

/// 단축키 하나 (키보드 키 또는 마우스 버튼 + Carbon 수정키)
struct Shortcut: Codable, Equatable {
    var keyCode: Int
    var modifiers: Int
    /// 마우스 버튼 번호 (2 = 휠 클릭, 3 = 뒤로, 4 = 앞으로 …). nil이면 키보드 단축키
    var mouseButton: Int?

    init(keyCode: Int, modifiers: Int) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    init(mouseButton: Int, modifiers: Int) {
        self.keyCode = -1
        self.modifiers = modifiers
        self.mouseButton = mouseButton
    }

    /// 키보드 이벤트에서 만들기
    init(event: NSEvent) {
        keyCode = Int(event.keyCode)
        modifiers = Shortcut.carbonModifiers(event.modifierFlags)
    }

    /// 예: "⌃⇧C", "⌥ 휠 클릭"
    var displayString: String {
        var s = ""
        if modifiers & controlKey != 0 { s += "⌃" }
        if modifiers & optionKey != 0 { s += "⌥" }
        if modifiers & shiftKey != 0 { s += "⇧" }
        if modifiers & cmdKey != 0 { s += "⌘" }
        if let mouseButton {
            return (s.isEmpty ? "" : s + " ") + Shortcut.mouseButtonName(mouseButton)
        }
        return s + Shortcut.keyName(keyCode)
    }

    var isFunctionKey: Bool { Shortcut.functionKeys[keyCode] != nil }

    /// 키보드: ⌘ ⌃ ⌥ 중 하나 이상 필요 (F1~F20은 단독 허용) / 마우스: 휠 클릭 이상의 버튼이면 단독 허용
    var isValid: Bool {
        if let mouseButton { return mouseButton >= 2 }
        return isFunctionKey || modifiers & (cmdKey | controlKey | optionKey) != 0
    }

    static func mouseButtonName(_ button: Int) -> String {
        switch button {
        case 2: return "휠 클릭"
        case 3: return "마우스 뒤로 버튼"
        case 4: return "마우스 앞으로 버튼"
        default: return "마우스 \(button + 1)번 버튼"
        }
    }

    /// 메뉴 항목에 표시할 키 (한 글자 키만 가능)
    var menuKeyEquivalent: String? {
        guard mouseButton == nil else { return nil }
        let name = Shortcut.keyName(keyCode)
        return name.count == 1 ? name.lowercased() : nil
    }

    var menuModifierMask: NSEvent.ModifierFlags {
        var flags: NSEvent.ModifierFlags = []
        if modifiers & controlKey != 0 { flags.insert(.control) }
        if modifiers & optionKey != 0 { flags.insert(.option) }
        if modifiers & shiftKey != 0 { flags.insert(.shift) }
        if modifiers & cmdKey != 0 { flags.insert(.command) }
        return flags
    }

    static func carbonModifiers(_ flags: NSEvent.ModifierFlags) -> Int {
        let f = flags.intersection(.deviceIndependentFlagsMask)
        var m = 0
        if f.contains(.control) { m |= controlKey }
        if f.contains(.option) { m |= optionKey }
        if f.contains(.shift) { m |= shiftKey }
        if f.contains(.command) { m |= cmdKey }
        return m
    }

    // MARK: - 키 이름

    private static let functionKeys: [Int: String] = [
        kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4", kVK_F5: "F5",
        kVK_F6: "F6", kVK_F7: "F7", kVK_F8: "F8", kVK_F9: "F9", kVK_F10: "F10",
        kVK_F11: "F11", kVK_F12: "F12", kVK_F13: "F13", kVK_F14: "F14", kVK_F15: "F15",
        kVK_F16: "F16", kVK_F17: "F17", kVK_F18: "F18", kVK_F19: "F19", kVK_F20: "F20",
    ]

    private static let specialKeys: [Int: String] = [
        kVK_Space: "Space", kVK_Return: "↩", kVK_Tab: "⇥", kVK_Delete: "⌫",
        kVK_ForwardDelete: "⌦", kVK_Escape: "⎋",
        kVK_LeftArrow: "←", kVK_RightArrow: "→", kVK_UpArrow: "↑", kVK_DownArrow: "↓",
        kVK_Home: "↖", kVK_End: "↘", kVK_PageUp: "⇞", kVK_PageDown: "⇟",
    ]

    static func keyName(_ code: Int) -> String {
        if let name = functionKeys[code] ?? specialKeys[code] { return name }

        // 한글 입력 중이어도 영문 자판 기준으로 표시 (ㅊ → C)
        guard let source = TISCopyCurrentASCIICapableKeyboardLayoutInputSource()?.takeRetainedValue(),
              let ptr = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else { return "?" }
        let data = Unmanaged<CFData>.fromOpaque(ptr).takeUnretainedValue() as Data

        return data.withUnsafeBytes { raw -> String in
            guard let layout = raw.bindMemory(to: UCKeyboardLayout.self).baseAddress else { return "?" }
            var deadKeys: UInt32 = 0
            var chars = [UniChar](repeating: 0, count: 4)
            var length = 0
            let status = UCKeyTranslate(layout, UInt16(code), UInt16(kUCKeyActionDisplay), 0,
                                        UInt32(LMGetKbdType()), OptionBits(kUCKeyTranslateNoDeadKeysBit),
                                        &deadKeys, chars.count, &length, &chars)
            guard status == noErr, length > 0 else { return "?" }
            return String(utf16CodeUnits: chars, count: length).uppercased()
        }
    }
}

/// 단축키를 쓰는 기능
enum ShortcutAction: String, CaseIterable, Identifiable {
    case pickColor
    case captureRegion

    var id: String { rawValue }

    var title: String {
        switch self {
        case .pickColor: return "색 추출"
        case .captureRegion: return "영역 캡처"
        }
    }

    var symbol: String {
        switch self {
        case .pickColor: return "eyedropper"
        case .captureRegion: return "crop"
        }
    }

    var defaultShortcut: Shortcut {
        switch self {
        case .pickColor: return Shortcut(keyCode: kVK_ANSI_C, modifiers: controlKey | shiftKey)
        case .captureRegion: return Shortcut(keyCode: kVK_ANSI_S, modifiers: controlKey | shiftKey)
        }
    }
}

/// 단축키 저장소 (UserDefaults에 저장)
final class ShortcutStore: ObservableObject {
    static let shared = ShortcutStore()

    @Published private(set) var shortcuts: [ShortcutAction: Shortcut] = [:]

    /// AppDelegate가 연결: 모든 단축키를 다시 등록하고, 등록 실패한 기능을 돌려줌
    var register: (() -> [ShortcutAction])?
    /// AppDelegate가 연결: 모든 단축키 잠시 해제 (키 입력받는 동안)
    var unregister: (() -> Void)?

    private init() {
        for action in ShortcutAction.allCases {
            if let data = UserDefaults.standard.data(forKey: key(action)),
               let saved = try? JSONDecoder().decode(Shortcut.self, from: data) {
                shortcuts[action] = saved
            }
        }
    }

    func shortcut(for action: ShortcutAction) -> Shortcut {
        shortcuts[action] ?? action.defaultShortcut
    }

    /// 단축키 변경. 실패하면 이유를 돌려주고 원래대로 되돌림
    func update(_ action: ShortcutAction, to shortcut: Shortcut) -> String? {
        if let other = ShortcutAction.allCases.first(where: { $0 != action && self.shortcut(for: $0) == shortcut }) {
            _ = register?()
            return "\(shortcut.displayString)는 이미 '\(other.title)'에 쓰고 있어요."
        }

        let old = shortcuts[action]
        shortcuts[action] = shortcut
        let failed = register?() ?? []
        if failed.contains(action) {
            shortcuts[action] = old
            _ = register?()
            return "\(shortcut.displayString)는 다른 앱이 이미 쓰고 있어요."
        }
        save(action)
        return nil
    }

    func resetAll() {
        shortcuts = [:]
        for action in ShortcutAction.allCases {
            UserDefaults.standard.removeObject(forKey: key(action))
        }
        _ = register?()
    }

    private func save(_ action: ShortcutAction) {
        if let data = try? JSONEncoder().encode(shortcut(for: action)) {
            UserDefaults.standard.set(data, forKey: key(action))
        }
    }

    private func key(_ action: ShortcutAction) -> String { "shortcut.\(action.rawValue)" }
}
