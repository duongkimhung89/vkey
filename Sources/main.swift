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

    /// Applications found unable to take direct text; the active word is
    /// shown there as marked text.  Only bundle identifiers are stored.
    func usesMarkedText(in bundleIdentifier: String?) -> Bool {
        guard let bundleIdentifier else { return false }
        return (store.stringArray(forKey: "MarkedTextApplications") ?? []).contains(bundleIdentifier)
    }
    var markedTextApplicationCount: Int { (store.stringArray(forKey: "MarkedTextApplications") ?? []).count }
    func forgetMarkedTextApplications() { store.removeObject(forKey: "MarkedTextApplications") }
    func useMarkedText(in bundleIdentifier: String) {
        var learned = store.stringArray(forKey: "MarkedTextApplications") ?? []
        guard !learned.contains(bundleIdentifier) else { return }
        learned.append(bundleIdentifier)
        store.set(learned, forKey: "MarkedTextApplications")
    }
}

private struct Client: TextClient {
    let input: IMKTextInput
    func selectedRange() -> NSRange { input.selectedRange() }
    func insertText(_ text: String, replacementRange: NSRange) {
        input.insertText(text, replacementRange: replacementRange)
    }
    func setMarkedText(_ text: String, selectionRange: NSRange, replacementRange: NSRange) {
        // A barely visible underline for clients that need marked text.
        let marked = NSAttributedString(string: text, attributes: VKeyController.markedTextAttributes)
        input.setMarkedText(marked, selectionRange: selectionRange, replacementRange: replacementRange)
    }
}

@objc(VKeyController)
final class VKeyController: IMKInputController {
    // The typing logic lives in InputSession.  By default the current word is
    // ordinary document text replaced on each key (`insertText` with a
    // replacement range), because
    // `setMarkedText` makes the host draw an underline and background.
    private let session = InputSession()
    /// Control+Shift went down with nothing else; releasing it switches language.
    private var toggleArmed = false

    override func recognizedEvents(_ sender: Any!) -> Int {
        Int(NSEvent.EventTypeMask([.keyDown, .flagsChanged, .leftMouseDown]).rawValue)
    }
    override func handle(_ event: NSEvent!, client sender: Any!) -> Bool {
        guard let event, let input = sender as? IMKTextInput else { return false }
        let client = Client(input: input)
        if event.type == .flagsChanged {
            handleModifiers(event.modifierFlags, client: client)
            return false
        }
        if event.type == .leftMouseDown {
            // A click moves the caret.  Clients that pass it on let the word
            // end now rather than when the moved caret is next reported.
            session.commit(client: client)
            return false
        }
        guard event.type == .keyDown else { return false }
        toggleArmed = false

        // Secure Input is owned by macOS. Never attempt a fallback or a global hook.
        let secure = IsSecureEventInputEnabled()
        AppDelegate.shared.secureInputChanged(secure)
        guard !secure else {
            session.commit(client: client)
            return false
        }
        let preferences = Preferences.shared
        guard preferences.enabled else {
            session.commit(client: client)
            return false
        }
        if session.mode != preferences.mode {
            session.commit(client: client)
            session.mode = preferences.mode
        }
        let flags = event.modifierFlags
        return session.handle(KeyStroke(keyCode: event.keyCode,
                                        characters: event.characters,
                                        hasShortcutModifier: !flags.intersection([.command, .control, .option]).isEmpty,
                                        isNumericPad: flags.contains(.numericPad)),
                              client: client)
    }

    private func handleModifiers(_ modifierFlags: NSEvent.ModifierFlags, client: Client) {
        let flags = modifierFlags.intersection([.control, .shift, .command, .option])
        let chord: NSEvent.ModifierFlags = [.control, .shift]
        if flags == chord {
            toggleArmed = true
        } else if toggleArmed, flags.isSubset(of: chord) {
            toggleArmed = false
            session.commit(client: client)
            Preferences.shared.enabled.toggle()
            AppDelegate.shared.refreshStatus()
        } else {
            toggleArmed = false
        }
    }

    override func commitComposition(_ sender: Any!) {
        // Direct text is already in the host document, so committing only
        // clears VKey's state; an extra insert would duplicate the word.
        // Marked text is what IMKit expects to be inserted here.
        if let input = sender as? IMKTextInput {
            session.commit(client: Client(input: input))
        } else {
            session.reset()
        }
    }
    override func activateServer(_ sender: Any!) {
        session.reset()
        toggleArmed = false
        let preferences = Preferences.shared
        session.mode = preferences.mode
        let bundleIdentifier = (sender as? IMKTextInput)?.bundleIdentifier()
        session.prefersMarkedText = preferences.usesMarkedText(in: bundleIdentifier)
        session.onDirectTextUnsupported = {
            if let bundleIdentifier { Preferences.shared.useMarkedText(in: bundleIdentifier) }
        }
        super.activateServer(sender)
    }
    override func deactivateServer(_ sender: Any!) {
        commitComposition(sender)
        super.deactivateServer(sender)
    }
    static let markedTextAttributes: [NSAttributedString.Key: Any] = [
        .underlineStyle: NSUnderlineStyle.single.rawValue,
        .underlineColor: NSColor.textColor.withAlphaComponent(0.15),
    ]
    override func mark(forStyle style: Int, at range: NSRange) -> [AnyHashable: Any]! {
        var attributes: [AnyHashable: Any] = Self.markedTextAttributes
        attributes[NSAttributedString.Key.markedClauseSegment] = NSNumber(value: style)
        return attributes
    }
    // Keep VKey's settings in its own status-item menu.  Returning nil here
    // leaves the macOS input-source menu focused on source selection only.
    override func menu() -> NSMenu! { nil }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    static let shared = AppDelegate()
    private let inputMethodBundleIdentifier = "local.inputmethod.VKey"
    private var server: IMKServer?
    private var statusItem: NSStatusItem?
    private var secureInput = false

    private var shortVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
    }
    private var version: String {
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        return "\(shortVersion) (build \(build))"
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Only the copy in ~/Library/Input Methods serves as the input method.
        // Any other copy (Applications, the disk image, a build folder) is an
        // installer: it puts itself there, restarts the running input method
        // when it replaced it, and exits.
        let running = Bundle.main.bundleURL.resolvingSymlinksInPath().standardizedFileURL
        guard running != installedInputMethodURL.resolvingSymlinksInPath().standardizedFileURL else {
            startInputMethod()
            return
        }
        let result = installInputMethod()
        if !CommandLine.arguments.contains("--quiet") {
            switch result {
            case .ready:
                showAlert("VKey đã được cài",
                          "VKey \(version) đang sẵn sàng. Chọn VKey trong menu nguồn nhập của macOS; nút VI/EN trên thanh menu mở các lệnh Tiếng Việt/English và Telex/VNI.")
            case .installed:
                showAlert("Đã cài VKey",
                          "VKey đã được chuẩn bị xong. Hãy đăng xuất tài khoản macOS rồi đăng nhập lại để VKey xuất hiện trong danh sách nguồn nhập. Sau đó vào Cài đặt hệ thống → Bàn phím → Nhập văn bản → Sửa → + → Tiếng Việt → VKey → Thêm. Nếu VKey vẫn chưa xuất hiện, hãy khởi động lại máy.")
            case .updated:
                showAlert("Đã cập nhật VKey",
                          "VKey \(version) đã thay bản cũ và đang chạy lại. Không cần đăng xuất.")
            case .failed(let message):
                showAlert("Chưa cài được VKey",
                          "\(message)\n\nHãy chắc chắn bạn đã kéo VKey.app vào Applications rồi mở lại ứng dụng.",
                          style: .critical)
            }
        }
        NSApp.terminate(nil)
    }

    private func startInputMethod() {
        server = IMKServer(name: "local.inputmethod.VKey_Connection", bundleIdentifier: inputMethodBundleIdentifier)
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
        statusItem = item
        refreshStatus()
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
    /// Copy this bundle there when the installed one is missing or differs,
    /// and register it.
    private func installInputMethod() -> InstallationResult {
        let sourceURL = Bundle.main.bundleURL.standardizedFileURL
        let destinationURL = installedInputMethodURL.standardizedFileURL
        let fileManager = FileManager.default
        let destinationExists = fileManager.fileExists(atPath: destinationURL.path)
        let current = destinationExists && isSameBuild(sourceURL, destinationURL)

        if !current {
            let stagingURL = destinationURL.deletingLastPathComponent()
                .appendingPathComponent(".VKey.app.\(UUID().uuidString).installing")
            do {
                try fileManager.createDirectory(at: destinationURL.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
                try fileManager.copyItem(at: sourceURL, to: stagingURL)
                defer { try? fileManager.removeItem(at: stagingURL) }

                if destinationExists {
                    _ = try fileManager.replaceItemAt(destinationURL, withItemAt: stagingURL)
                } else {
                    try fileManager.moveItem(at: stagingURL, to: destinationURL)
                }
            } catch {
                return .failed("Không thể cài VKey vào thư mục input method của tài khoản này.\n\n\(error.localizedDescription)")
            }
        }

        let status = TISRegisterInputSource(destinationURL as CFURL)
        guard status == noErr else {
            return .failed("macOS không đăng ký được VKey (mã lỗi \(status)).")
        }
        guard destinationExists else { return .installed }

        // A running input method keeps executing the code it was started
        // with.  Restart it after an update, and also when the running one is
        // not the installed copy (0.2.0 served from Applications).
        let others = otherRunningInstances()
        let stale = others.contains { $0.bundleURL?.standardizedFileURL != destinationURL }
        if !others.isEmpty, !current || stale {
            restartInputMethod(others, at: destinationURL)
        }
        return current ? .ready : .updated
    }

    private func isSameBuild(_ first: URL, _ second: URL) -> Bool {
        ["Contents/MacOS/VKey", "Contents/Info.plist", "Contents/_CodeSignature/CodeResources"].allSatisfy { path in
            FileManager.default.contentsEqual(atPath: first.appendingPathComponent(path).path,
                                              andPath: second.appendingPathComponent(path).path)
        }
    }

    private func otherRunningInstances() -> [NSRunningApplication] {
        NSRunningApplication.runningApplications(withBundleIdentifier: inputMethodBundleIdentifier)
            .filter { $0 != NSRunningApplication.current }
    }

    private func restartInputMethod(_ instances: [NSRunningApplication], at url: URL) {
        instances.forEach { $0.terminate() }
        let deadline = Date().addingTimeInterval(3)
        while instances.contains(where: { !$0.isTerminated }), Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }
        instances.filter { !$0.isTerminated }.forEach { $0.forceTerminate() }

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        configuration.createsNewApplicationInstance = true
        let launched = DispatchSemaphore(value: 0)
        NSWorkspace.shared.openApplication(at: url, configuration: configuration) { _, _ in launched.signal() }
        _ = launched.wait(timeout: .now() + 5)
    }

    private func showAlert(_ title: String, _ text: String, style: NSAlert.Style = .informational) {
        let alert = NSAlert()
        alert.alertStyle = style
        alert.messageText = title
        alert.informativeText = text
        alert.addButton(withTitle: "Đã hiểu")
        alert.runModal()
    }

    // MARK: - Status item

    /// Called on every key: Secure Input suspends VKey everywhere, which is
    /// otherwise invisible to the user.
    func secureInputChanged(_ active: Bool) {
        guard active != secureInput else { return }
        secureInput = active
        refreshStatus()
    }

    func refreshStatus() {
        guard let button = statusItem?.button else { return }
        button.title = secureInput ? "🔒" : (Preferences.shared.enabled ? "VI" : "EN")
        button.toolTip = secureInput
            ? "VKey tạm dừng: Secure Input đang bật"
            : "VKey — bộ gõ tiếng Việt (Control + Shift để đổi Việt/Anh)"
    }

    /// The application holding Secure Input, as reported by the window server.
    private var secureInputOwner: String? {
        guard let session = CGSessionCopyCurrentDictionary() as? [String: Any],
              let pid = session["kCGSSessionSecureInputPID"] as? Int else { return nil }
        return NSRunningApplication(processIdentifier: pid_t(pid))?.localizedName
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        secureInputChanged(IsSecureEventInputEnabled())
        menu.removeAllItems()
        func item(_ title: String, _ action: Selector?, checked: Bool = false) {
            let entry = NSMenuItem(title: title, action: action, keyEquivalent: "")
            entry.target = self
            entry.state = checked ? .on : .off
            menu.addItem(entry)
        }
        let preferences = Preferences.shared
        if secureInput {
            item("Tạm dừng: \(secureInputOwner ?? "một ứng dụng") đang bật Secure Input", nil)
            menu.addItem(.separator())
        }
        item("Tiếng Việt", #selector(vietnamese), checked: preferences.enabled)
        item("English", #selector(english), checked: !preferences.enabled)
        item("Control + Shift: đổi Việt/Anh", nil)
        menu.addItem(.separator())
        item("Telex", #selector(telex), checked: preferences.mode == .telex)
        item("VNI", #selector(vni), checked: preferences.mode == .vni)
        menu.addItem(.separator())
        if preferences.markedTextApplicationCount > 0 {
            item("Thử lại gõ không gạch chân ở \(preferences.markedTextApplicationCount) ứng dụng", #selector(forgetMarkedText))
        }
        menu.addItem(.separator())
        item("Hướng dẫn", #selector(guide))
        item("Giới thiệu VKey \(shortVersion)", #selector(about))
        item("Gỡ cài đặt VKey", #selector(uninstall))
        item("Thoát", #selector(quit))
    }
    @objc private func vietnamese() {
        Preferences.shared.enabled = true
        refreshStatus()
    }
    @objc private func english() {
        Preferences.shared.enabled = false
        refreshStatus()
    }
    @objc private func telex() { Preferences.shared.mode = .telex }
    @objc private func vni() { Preferences.shared.mode = .vni }
    @objc private func forgetMarkedText() { Preferences.shared.forgetMarkedTextApplications() }
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
            showAlert("Đã gỡ cài đặt VKey",
                      "VKey đã được xoá khỏi danh sách nguồn nhập và đưa vào Thùng rác. Nếu mục này còn hiện trong Cài đặt hệ thống, hãy đóng rồi mở lại cửa sổ đó.")

            // Both app bundles have now been moved to the Trash, so finish
            // the current event and exit.
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

    @objc private func guide() {
        showAlert("Hướng dẫn gõ",
                  "Chọn VKey trong menu nguồn nhập của macOS. Nút VI/EN trên thanh menu đổi Tiếng Việt/English và Telex/VNI; Control + Shift đổi nhanh Việt/Anh.\n\nTelex: tieengs Vieetj → tiếng Việt, dduwowngf → đường.\nVNI: tie6ng1 Vie6t5 → tiếng Việt, d9uo7ng2 → đường.\n\nBackspace xoá một ký tự của từ đang gõ. Escape trả lại các phím đã gõ.\n\nKhi kết thúc từ, nếu dấu rơi vào chỗ tiếng Việt không có (windows, user, software…) VKey trả lại đúng các phím đã gõ. Từ tiếng Anh có dạng âm tiết tiếng Việt (test → tét, is → í) thì chuyển sang English hoặc gõ lặp phím dấu để huỷ dấu (tesst → test, passs → pass).\n\nCài đặt: kéo VKey.app vào Applications rồi mở một lần. Lần đầu cần đăng xuất rồi đăng nhập lại, sau đó thêm VKey trong Cài đặt hệ thống → Bàn phím → Nhập văn bản → Sửa → + → Tiếng Việt. Khi cập nhật chỉ cần mở bản mới một lần.")
    }
    @objc private func about() {
        showAlert("VKey \(version)",
                  "Bộ gõ tiếng Việt offline cho macOS.\nTelex và VNI • Unicode\n\nKhông kết nối mạng, không lưu nội dung gõ. Không cần quyền Accessibility hoặc Input Monitoring.\n\nhttps://github.com/duongkimhung89/vkey\n\nThông tin nguồn mở, bản quyền và license nằm trong Resources/THIRD_PARTY.md và Resources/Licenses/.")
    }
}
let app = NSApplication.shared
app.delegate = AppDelegate.shared
app.run()
