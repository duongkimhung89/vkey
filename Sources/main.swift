import AppKit
import InputMethodKit
import Carbon

final class Preferences {
    static let shared = Preferences()
    private let store = UserDefaults(suiteName: "local.vkey.inputmethod") ?? .standard

    var enabled: Bool {
        get { store.object(forKey: "VietnameseEnabled") as? Bool ?? true }
        set { store.set(newValue, forKey: "VietnameseEnabled") }
    }
    var mode: TypingMode {
        get { TypingMode(rawValue: store.string(forKey: "TypingMode") ?? "telex") ?? .telex }
        set { store.set(newValue.rawValue, forKey: "TypingMode") }
    }
}

@objc(VKeyController)
final class VKeyController: IMKInputController {
    private var composer = Composer()
    private var lastMode = Preferences.shared.mode

    // Keep the current word as ordinary document text.  `setMarkedText` asks the
    // host application to decorate the composition (usually with an underline
    // and a selection background), and the host owns that rendering.  XKey's
    // no-underline IMKit mode uses `insertText` with a replacement range instead.
    // These two values describe the text VKey has already inserted for the
    // current word so the next converted value replaces it atomically.
    private var directStartLocation = NSNotFound
    private var directTextLength = 0

    override func recognizedEvents(_ sender: Any!) -> Int { Int(NSEvent.EventTypeMask.keyDown.rawValue) }
    override func handle(_ event: NSEvent!, client sender: Any!) -> Bool {
        guard let event, let client = sender as? IMKTextInput else { return false }
        // Secure Input is owned by macOS. Never attempt a fallback or a global hook.
        guard !IsSecureEventInputEnabled() else {
            composer.reset()
            clearDirectComposition()
            return false
        }
        guard event.type == .keyDown else { return false }
        let preferences = Preferences.shared
        if !preferences.enabled || lastMode != preferences.mode {
            commitComposition(sender)
            lastMode = preferences.mode
        }
        guard preferences.enabled else { return false }
        composer.mode = preferences.mode
        synchronizeDirectCursor(client)
        if !event.modifierFlags.intersection([.command, .control, .option]).isEmpty {
            commitComposition(sender)
            return false
        }
        if event.keyCode == 53, !composer.raw.isEmpty {
            let raw = composer.raw
            replaceCurrentText(raw, in: client)
            composer.reset()
            clearDirectComposition()
            return true
        }
        if event.keyCode == 51, !composer.raw.isEmpty {
            let oldLength = directTextLength
            composer.backspace()
            replaceCurrentText(composer.text, in: client, replacingLength: oldLength)
            return true
        }
        guard let input = event.characters, input.count == 1, let c = input.first,
              c.isASCII, c.isLetter || c.isNumber || (composer.mode == .telex && "[]".contains(c)) else {
            commitComposition(sender)
            return false
        }
        if composer.raw.count >= Composer.maximumRawLength { commitComposition(sender) }
        composer.append(c)
        replaceCurrentText(composer.text, in: client)
        return true
    }

    /// Replace the current word with the latest converted value without creating
    /// an IMKit marked-text range.  The host therefore receives normal text and
    /// does not apply its marked-text underline/background styling.
    private func replaceCurrentText(_ text: String,
                                    in client: IMKTextInput,
                                    replacingLength explicitLength: Int? = nil) {
        let oldLength = explicitLength ?? directTextLength
        let replacementRange: NSRange

        if oldLength > 0 {
            let selection = client.selectedRange()
            if selection.location != NSNotFound, selection.location >= oldLength {
                // This is the same replacement strategy used by XKey: the
                // previous converted word sits immediately before the caret.
                replacementRange = NSRange(
                    location: selection.location - oldLength,
                    length: oldLength + selection.length
                )
            } else if directStartLocation != NSNotFound {
                // A few clients temporarily report an unavailable selection
                // after insertText.  The tracked start keeps the next key in
                // the same word instead of appending a duplicate.
                replacementRange = NSRange(location: directStartLocation,
                                            length: oldLength)
            } else {
                replacementRange = NSRange(location: NSNotFound, length: 0)
            }
        } else {
            let selection = client.selectedRange()
            if directStartLocation == NSNotFound, selection.location != NSNotFound {
                directStartLocation = selection.location
            }
            replacementRange = NSRange(location: NSNotFound, length: 0)
        }

        client.insertText(text, replacementRange: replacementRange)
        directTextLength = text.utf16.count

        if directTextLength == 0 {
            clearDirectComposition()
        } else if directStartLocation == NSNotFound {
            let selection = client.selectedRange()
            if selection.location != NSNotFound {
                directStartLocation = max(0, selection.location - directTextLength)
            }
        }
    }

    private func clearDirectComposition() {
        directStartLocation = NSNotFound
        directTextLength = 0
    }

    private func synchronizeDirectCursor(_ client: IMKTextInput) {
        guard directTextLength > 0,
              directStartLocation != NSNotFound else { return }
        let selection = client.selectedRange()
        guard selection.location != NSNotFound, selection.length == 0 else { return }
        let expected = directStartLocation + directTextLength
        if selection.location != expected {
            // The user moved the caret or selected another range.  The text is
            // already committed in the host, so only discard VKey's word state.
            composer.reset()
            clearDirectComposition()
        }
    }

    override func commitComposition(_ sender: Any!) {
        // In direct mode the latest converted text is already in the host
        // document.  Committing only clears VKey's reconstruction state; an
        // extra insert here would duplicate the word before a space, Enter, or
        // punctuation key reaches the host application.
        composer.reset()
        clearDirectComposition()
    }
    override func activateServer(_ sender: Any!) {
        composer.reset()
        clearDirectComposition()
        lastMode = Preferences.shared.mode
        super.activateServer(sender)
    }
    override func deactivateServer(_ sender: Any!) {
        commitComposition(sender)
        super.deactivateServer(sender)
    }
    // Keep VKey's settings in its own status-item menu.  Returning nil here
    // leaves the macOS input-source menu focused on source selection only.
    override func menu() -> NSMenu! { nil }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    static let shared = AppDelegate()
    private let inputMethodBundleIdentifier = "local.inputmethod.VKey"
    private var server: IMKServer?
    private var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        switch prepareInputMethodInstallation() {
        case .ready, .updated:
            break
        case .installed:
            showInstallationComplete()
            return
        case .failed(let message):
            showInstallationFailure(message)
            return
        }

        server = IMKServer(name: "local.inputmethod.VKey_Connection", bundleIdentifier: inputMethodBundleIdentifier)
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem?.button?.title = "VK"
        statusItem?.button?.toolTip = "VKey — bộ gõ tiếng Việt"
        refreshStatusMenu()
    }

    private enum InstallationResult {
        case ready
        case installed
        case updated
        case failed(String)
    }

    private var installedInputMethodURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Input Methods", isDirectory: true)
            .appendingPathComponent("VKey.app", isDirectory: true)
    }

    private var applicationsAppURL: URL {
        URL(fileURLWithPath: "/Applications/VKey.app", isDirectory: true)
    }

    /// A drag-and-drop install puts the visible app in Applications, but
    /// macOS only discovers IMK bundles from its Input Methods directories.
    /// Copy the user-launched app there and register that copy. Once macOS
    /// launches the registered copy, this method is a no-op.
    private func prepareInputMethodInstallation() -> InstallationResult {
        let sourceURL = Bundle.main.bundleURL.standardizedFileURL
        let destinationURL = installedInputMethodURL.standardizedFileURL

        guard sourceURL != destinationURL else { return .ready }

        let fileManager = FileManager.default
        let sourceBundle = Bundle(url: sourceURL)
        let destinationBundle = Bundle(url: destinationURL)
        let sourceVersion = sourceBundle?.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        let destinationVersion = destinationBundle?.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        let destinationExists = fileManager.fileExists(atPath: destinationURL.path)

        // The copy in ~/Library/Input Methods is the bundle macOS launches as
        // an input method.  If it is already the same build, keep it in place
        // and let this user-launched instance continue to its status menu.
        // Re-copy only when the installed bundle is missing or outdated.
        if destinationExists, sourceVersion == destinationVersion {
            let status = TISRegisterInputSource(destinationURL as CFURL)
            guard status == noErr else {
                return .failed("macOS không đăng ký được VKey (mã lỗi \(status)).")
            }
            return .ready
        }

        let stagingURL = destinationURL.deletingLastPathComponent()
            .appendingPathComponent(".VKey.app.\(UUID().uuidString).installing")

        do {
            try fileManager.createDirectory(at: destinationURL.deletingLastPathComponent(),
                                            withIntermediateDirectories: true)
            try fileManager.copyItem(at: sourceURL, to: stagingURL)
            defer { try? fileManager.removeItem(at: stagingURL) }

            if fileManager.fileExists(atPath: destinationURL.path) {
                _ = try fileManager.replaceItemAt(destinationURL, withItemAt: stagingURL)
            } else {
                try fileManager.moveItem(at: stagingURL, to: destinationURL)
            }

            let status = TISRegisterInputSource(destinationURL as CFURL)
            guard status == noErr else {
                return .failed("macOS không đăng ký được VKey (mã lỗi \(status)).")
            }
            return destinationExists ? .updated : .installed
        } catch {
            return .failed("Không thể cài VKey vào thư mục input method của tài khoản này.\n\n\(error.localizedDescription)")
        }
    }

    private func showInstallationComplete() {
        let alert = NSAlert()
        alert.messageText = "Đã cài VKey"
        alert.informativeText = "VKey đã được chuẩn bị xong. Hãy đăng xuất tài khoản macOS rồi đăng nhập lại để VKey xuất hiện trong danh sách nguồn nhập. Sau đó vào Cài đặt hệ thống → Bàn phím → Nhập văn bản → Sửa → + → Tiếng Việt → VKey → Thêm. Nếu VKey vẫn chưa xuất hiện, hãy khởi động lại máy."
        alert.addButton(withTitle: "Đã hiểu")
        alert.runModal()
        NSApp.terminate(nil)
    }

    private func showInstallationFailure(_ message: String) {
        let alert = NSAlert()
        alert.alertStyle = .critical
        alert.messageText = "Chưa cài được VKey"
        alert.informativeText = "\(message)\n\nHãy chắc chắn bạn đã kéo VKey.app vào Applications rồi mở lại ứng dụng."
        alert.addButton(withTitle: "Đóng")
        alert.runModal()
        NSApp.terminate(nil)
    }

    private func refreshStatusMenu() {
        statusItem?.menu = makeMenu()
    }

    func makeMenu() -> NSMenu {
        let menu = NSMenu()
        func item(_ title: String, _ action: Selector, checked: Bool = false) {
            let entry = NSMenuItem(title: title, action: action, keyEquivalent: "")
            entry.target = self
            entry.state = checked ? .on : .off
            menu.addItem(entry)
        }
        item("Tiếng Việt", #selector(vietnamese), checked: Preferences.shared.enabled)
        item("English", #selector(english), checked: !Preferences.shared.enabled)
        menu.addItem(.separator())
        item("Telex", #selector(telex), checked: Preferences.shared.mode == .telex)
        item("VNI", #selector(vni), checked: Preferences.shared.mode == .vni)
        menu.addItem(.separator())
        item("Hướng dẫn / Giới thiệu", #selector(about))
        item("Gỡ cài đặt VKey", #selector(uninstall))
        item("Thoát", #selector(quit))
        return menu
    }
    @objc private func vietnamese() {
        Preferences.shared.enabled = true
        refreshStatusMenu()
    }
    @objc private func english() {
        Preferences.shared.enabled = false
        refreshStatusMenu()
    }
    @objc private func telex() {
        Preferences.shared.mode = .telex
        refreshStatusMenu()
    }
    @objc private func vni() {
        Preferences.shared.mode = .vni
        refreshStatusMenu()
    }
    @objc private func quit() { NSApp.terminate(nil) }

    @objc private func uninstall() {
        let confirmation = NSAlert()
        confirmation.messageText = "Gỡ cài đặt VKey?"
        confirmation.informativeText = "VKey sẽ bị tắt trong macOS, bản copy trong ~/Library/Input Methods và VKey.app trong Applications sẽ được đưa vào Thùng rác."
        confirmation.addButton(withTitle: "Gỡ VKey")
        confirmation.addButton(withTitle: "Huỷ")
        guard confirmation.runModal() == .alertFirstButtonReturn else { return }

        let errors = removeRegisteredInputMethod()
        if errors.isEmpty {
            let finished = NSAlert()
            finished.messageText = "Đã gỡ cài đặt VKey"
            finished.informativeText = "VKey đã được xoá khỏi danh sách nguồn nhập và đưa vào Thùng rác. Nếu mục này còn hiện trong Cài đặt hệ thống, hãy đóng rồi mở lại cửa sổ đó."
            finished.addButton(withTitle: "Đã hiểu")
            finished.runModal()

            // macOS normally launches the registered copy from ~/Library/Input
            // Methods. Both possible app bundles have now been moved to the
            // Trash, so finish the current event and exit.
            NSApp.terminate(nil)
        } else {
            let failure = NSAlert()
            failure.alertStyle = .critical
            failure.messageText = "Chưa gỡ hết VKey"
            failure.informativeText = errors.joined(separator: "\n\n")
            failure.addButton(withTitle: "Đóng")
            failure.runModal()
        }
    }

    /// Disable the registered source before moving its bundle away. TIS has no
    /// public unregister call; disabling the source plus removing the bundle
    /// is the supported cleanup path for a user-installed input method.
    private func removeRegisteredInputMethod() -> [String] {
        var errors: [String] = []
        let sources = registeredInputSources()

        if let current = TISCopyCurrentKeyboardInputSource().takeRetainedValue() as TISInputSource?,
           isVKeyInputSource(current) {
            guard let fallback = TISCopyCurrentASCIICapableKeyboardInputSource().takeRetainedValue() as TISInputSource?,
                  !isVKeyInputSource(fallback) else {
                errors.append("Không thể chuyển khỏi VKey đang được chọn. Hãy chọn ABC trước rồi thử lại.")
                return errors
            }
            let status = TISSelectInputSource(fallback)
            if status != noErr {
                errors.append("Không thể chuyển khỏi VKey đang được chọn (mã lỗi \(status)). Hãy chọn ABC trước rồi thử lại.")
                return errors
            }
        }

        for source in sources {
            let status = TISDisableInputSource(source)
            if status != noErr {
                errors.append("macOS không tắt được nguồn nhập VKey (mã lỗi \(status)).")
            }
        }

        let fileManager = FileManager.default
        let bundlesToRemove = [installedInputMethodURL, applicationsAppURL]
        for bundleURL in bundlesToRemove {
            guard fileManager.fileExists(atPath: bundleURL.path) else { continue }
            do {
                try fileManager.trashItem(at: bundleURL, resultingItemURL: nil)
            } catch {
                let location = bundleURL == applicationsAppURL ? "Applications" : "~/Library/Input Methods"
                errors.append("Không thể đưa VKey trong \(location) vào Thùng rác.\n\n\(error.localizedDescription)")
            }
        }
        return errors
    }

    private func registeredInputSources() -> [TISInputSource] {
        guard let list = TISCreateInputSourceList(nil, true)?.takeRetainedValue() as? [TISInputSource] else {
            return []
        }
        return list.filter { source in
            isVKeyInputSource(source)
        }
    }

    private func isVKeyInputSource(_ source: TISInputSource) -> Bool {
        inputSourceProperty(source, kTISPropertyInputSourceID) == inputMethodBundleIdentifier ||
        inputSourceProperty(source, kTISPropertyBundleID) == inputMethodBundleIdentifier
    }

    private func inputSourceProperty(_ source: TISInputSource, _ key: CFString) -> String? {
        guard let pointer = TISGetInputSourceProperty(source, key) else { return nil }
        return Unmanaged<CFString>.fromOpaque(pointer).takeUnretainedValue() as String
    }

    @objc private func about() {
        let alert = NSAlert()
        alert.messageText = "VKey 0.2.0 — bộ gõ offline"
        alert.informativeText = "Telex và VNI • Unicode\nKhông kết nối mạng, không lưu nội dung gõ.\n\nKéo VKey.app vào Applications rồi mở một lần. VKey sẽ tự chuẩn bị input method. Hãy đăng xuất tài khoản macOS rồi đăng nhập lại để VKey xuất hiện trong danh sách nguồn nhập, sau đó thêm VKey trong Cài đặt hệ thống → Bàn phím → Nhập văn bản → Sửa → + → Tiếng Việt. Nếu VKey vẫn chưa xuất hiện, hãy khởi động lại máy.\n\nChọn VKey trong menu nguồn nhập của macOS. Menu nguồn nhập chỉ chọn ABC/VKey; bấm nút VK trên thanh menu để mở các lệnh Tiếng Việt/English, Telex/VNI và Hướng dẫn. Escape trả lại từ đang gõ; Backspace hoàn tác một phím trong từ.\n\nKhông cần quyền Accessibility hoặc Input Monitoring. Bản thử nghiệm: cần kiểm tra tương thích với ứng dụng bạn dùng.\n\nEngine dựa trên XKey/OpenKey; thông báo bản quyền và license nằm trong Resources/THIRD_PARTY.md và Resources/Licenses/."
        alert.runModal()
    }
}
let app = NSApplication.shared
app.delegate = AppDelegate.shared
app.run()
