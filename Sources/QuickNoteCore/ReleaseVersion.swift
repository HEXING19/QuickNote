import Foundation

public struct ReleaseVersion: Comparable, Equatable {
    private let parts: [Int]
    public init?(_ value: String) {
        let raw = value.hasPrefix("v") ? String(value.dropFirst()) : value
        let tokens = raw.split(separator: ".", omittingEmptySubsequences: false)
        guard (2...3).contains(tokens.count), tokens.allSatisfy({ !$0.isEmpty && $0.allSatisfy({ $0.isASCII && $0.isNumber }) }), tokens.allSatisfy({ Int($0) != nil }) else { return nil }
        parts = tokens.map { Int($0)! } + Array(repeating: 0, count: 3-tokens.count)
    }
    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.parts.lexicographicallyPrecedes(rhs.parts) }
}
