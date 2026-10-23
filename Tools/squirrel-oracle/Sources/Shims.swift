import AppKit

// What SquirrelTheme, SquirrelView and SquirrelPanel need from the rest of
// Squirrel, written for this tool: the operators from BridgingFunctions.swift
// (whose librime parts cannot build here), a SquirrelConfig that reads a
// dictionary instead of librime, and an input controller that only carries
// the comment colours.

infix operator ?= : AssignmentPrecedence

func ?=<T>(left: inout T, right: T?) {
    if let right {
        left = right
    }
}

func ?=<T>(left: inout T?, right: T?) {
    if let right {
        left = right
    }
}

extension NSRange {
    static let empty = NSRange(location: NSNotFound, length: 0)
}

extension NSPoint {
    static func += (lhs: inout Self, rhs: Self) {
        lhs.x += rhs.x
        lhs.y += rhs.y
    }

    static func - (lhs: Self, rhs: Self) -> Self {
        Self(x: lhs.x - rhs.x, y: lhs.y - rhs.y)
    }

    static func -= (lhs: inout Self, rhs: Self) {
        lhs.x -= rhs.x
        lhs.y -= rhs.y
    }

    static func * (lhs: Self, rhs: CGFloat) -> Self {
        Self(x: lhs.x * rhs, y: lhs.y * rhs)
    }

    static func / (lhs: Self, rhs: CGFloat) -> Self {
        Self(x: lhs.x / rhs, y: lhs.y / rhs)
    }

    var length: CGFloat {
        sqrt(pow(x, 2) + pow(y, 2))
    }
}

/// Config values by librime path, such as "style/font_point".
final class SquirrelConfig {
    private let values: [String: String]

    init(_ values: [String: String]) {
        self.values = values
    }

    func getString(_ option: String) -> String? {
        values[option]
    }

    func getBool(_ option: String) -> Bool? {
        switch values[option]?.lowercased() {
        case "true": true
        case "false": false
        default: nil
        }
    }

    func getDouble(_ option: String) -> CGFloat? {
        values[option].flatMap(Double.init).map { CGFloat($0) }
    }

    /// "0xAABBGGRR" or "0xBBGGRR".
    func getColor(_ option: String, inSpace colorSpace: SquirrelTheme.RimeColorSpace) -> NSColor? {
        guard let value = values[option], value.hasPrefix("0x") else { return nil }
        let digits = value.dropFirst(2)
        guard digits.count == 6 || digits.count == 8, let packed = UInt32(digits, radix: 16) else { return nil }
        func component(_ shift: UInt32) -> CGFloat {
            CGFloat((packed >> shift) & 0xff) / 255
        }
        let alpha = digits.count == 8 ? component(24) : 1
        return switch colorSpace {
        case .displayP3: NSColor(displayP3Red: component(0), green: component(8), blue: component(16), alpha: alpha)
        case .sRGB: NSColor(srgbRed: component(0), green: component(8), blue: component(16), alpha: alpha)
        }
    }
}

final class SquirrelInputController {
    var specialCommentIndices: [ReservedPropertyKey: Set<Int>] = [:]

    func page(up: Bool) -> Bool {
        false
    }

    func moveCaret(forward: Bool) -> Bool {
        false
    }

    func selectCandidate(_ index: Int) -> Bool {
        false
    }
}
