import Foundation
import Carbon
let path = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Input Methods/VKey.app")
if CommandLine.arguments.contains("--register") {
    let status = TISRegisterInputSource(path as CFURL)
    print("Registration status: \(status)")
    if status != noErr { exit(1) }
}
let list = TISCreateInputSourceList(nil, true).takeRetainedValue() as! [TISInputSource]
var found = false
for source in list {
    guard let ptr = TISGetInputSourceProperty(source, kTISPropertyInputSourceID) else { continue }
    let id = Unmanaged<CFString>.fromOpaque(ptr).takeUnretainedValue() as String
    if id.localizedCaseInsensitiveContains("vkey") {
        found = true
        print("Registered source: \(id)")
    }
}
print("VKey found: \(found)")
exit(found ? 0 : 2)
