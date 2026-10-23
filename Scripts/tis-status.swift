// Prints how the Text Input Sources manager sees Scribe, without changing
// anything:
//
//   xcrun swift Scripts/tis-status.swift
//
// One line per input source: its ID, then "registered", "enabled" (offered
// to the user) and "selected" as applicable. Exits 1 unless both modes are
// registered.

import Carbon
import Foundation

let bundleID = "io.github.itvx.inputmethod.Scribe"
let modes = ["\(bundleID).Hans", "\(bundleID).Hant"]

func sources(includeAllInstalled: Bool) -> [TISInputSource] {
    let filter = [kTISPropertyBundleID as String: bundleID] as CFDictionary
    return TISCreateInputSourceList(filter, includeAllInstalled)?.takeRetainedValue() as? [TISInputSource] ?? []
}

func id(of source: TISInputSource) -> String {
    guard let value = TISGetInputSourceProperty(source, kTISPropertyInputSourceID) else { return "?" }
    return Unmanaged<CFString>.fromOpaque(value).takeUnretainedValue() as String
}

let registered = Set(sources(includeAllInstalled: true).map(id))
let enabled = Set(sources(includeAllInstalled: false).map(id))
let current = id(of: TISCopyCurrentKeyboardInputSource().takeRetainedValue())

for source in [bundleID] + modes {
    var states: [String] = []
    if registered.contains(source) { states.append("registered") }
    if enabled.contains(source) { states.append("enabled") }
    if current == source { states.append("selected") }
    print("\(source) \(states.isEmpty ? "absent" : states.joined(separator: " "))")
}
exit(modes.allSatisfy(registered.contains) ? 0 : 1)
