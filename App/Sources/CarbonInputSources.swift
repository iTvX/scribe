import Carbon
import Foundation

/// The real Text Input Sources manager.
struct CarbonInputSources: InputSourceSystem {
    /// Posted to the distributed notification center when the selected input
    /// source changes.
    static let selectionChanged = Notification.Name(kTISNotifySelectedKeyboardInputSourceChanged as String)

    var currentInputSourceID: String? {
        guard let source = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue(),
              let value = TISGetInputSourceProperty(source, kTISPropertyInputSourceID)
        else { return nil }
        return Unmanaged<CFString>.fromOpaque(value).takeUnretainedValue() as String
    }

    var disabledKeyboardLayoutForRefresh: String? {
        let filter = [
            kTISPropertyInputSourceType as String: kTISTypeKeyboardLayout as String,
            kTISPropertyBundleID as String: "com.apple.keyboardlayout.all",
        ] as CFDictionary
        guard let sources = TISCreateInputSourceList(filter, true)?.takeRetainedValue() as? [TISInputSource] else {
            return nil
        }
        let candidates = sources.compactMap { source -> String? in
            guard bool(source, kTISPropertyInputSourceIsEnableCapable),
                  bool(source, kTISPropertyInputSourceIsSelectCapable),
                  bool(source, kTISPropertyInputSourceIsASCIICapable),
                  !bool(source, kTISPropertyInputSourceIsEnabled),
                  !bool(source, kTISPropertyInputSourceIsSelected),
                  let languageValue = TISGetInputSourceProperty(source, kTISPropertyInputSourceLanguages),
                  let languages = Unmanaged<CFArray>.fromOpaque(languageValue).takeUnretainedValue() as? [String],
                  languages.contains("en"),
                  let idValue = TISGetInputSourceProperty(source, kTISPropertyInputSourceID)
            else { return nil }
            let id = Unmanaged<CFString>.fromOpaque(idValue).takeUnretainedValue() as String
            return id.hasPrefix("com.apple.keylayout.") ? id : nil
        }
        func priority(_ id: String) -> Int {
            switch id {
            case "com.apple.keylayout.ABC": 0
            case "com.apple.keylayout.US": 1
            default: 2
            }
        }
        return candidates.sorted { (priority($0), $0) < (priority($1), $1) }.first
    }

    func state(of id: String) -> InputSourceState? {
        guard let source = source(id, includeAllInstalled: true) else { return nil }
        return InputSourceState(
            // A mode reports its default state in kTISPropertyInputSourceIsEnabled
            // even while Scribe itself is off, so ask for enabled sources instead.
            isEnabled: self.source(id, includeAllInstalled: false) != nil,
            isSelectable: bool(source, kTISPropertyInputSourceIsSelectCapable),
            isSelected: bool(source, kTISPropertyInputSourceIsSelected),
            // TIS names no bundle, but an input mode's icon lives in it.
            bundlePath: TISGetInputSourceProperty(source, kTISPropertyIconImageURL)
                .map { Unmanaged<CFURL>.fromOpaque($0).takeUnretainedValue() as URL }
                .flatMap(InputSourceState.bundlePath(containing:))
        )
    }

    func register(_ bundleURL: URL) -> OSStatus {
        TISRegisterInputSource(bundleURL as CFURL)
    }

    func enable(_ id: String) -> OSStatus {
        source(id, includeAllInstalled: true).map(TISEnableInputSource) ?? OSStatus(paramErr)
    }

    func disable(_ id: String) -> OSStatus {
        source(id, includeAllInstalled: true).map(TISDisableInputSource) ?? OSStatus(paramErr)
    }

    func select(_ id: String) -> OSStatus {
        source(id, includeAllInstalled: true).map(TISSelectInputSource) ?? OSStatus(paramErr)
    }

    private func source(_ id: String, includeAllInstalled: Bool) -> TISInputSource? {
        let filter = [kTISPropertyInputSourceID as String: id] as CFDictionary
        let sources = TISCreateInputSourceList(filter, includeAllInstalled)?.takeRetainedValue() as? [TISInputSource]
        return sources?.first
    }

    private func bool(_ source: TISInputSource, _ key: CFString) -> Bool {
        guard let value = TISGetInputSourceProperty(source, key) else { return false }
        return CFBooleanGetValue(Unmanaged<CFBoolean>.fromOpaque(value).takeUnretainedValue())
    }
}
