import Foundation

// The JSON the model sends back. Same shape as check.py:
// { verdict, corrected, changes: [{from, to, reason}], native_version }
//
// `Codable` lets Swift turn JSON into this struct automatically.
// `CodingKeys` maps the snake_case JSON name to a Swift-style name.
struct CheckResult: Codable, Equatable {
    let verdict: String          // "natural", "not_natural" or "error"
    let corrected: String
    let changes: [Change]
    let nativeVersion: String

    struct Change: Codable, Hashable {
        let from: String
        let to: String
        let reason: String
    }

    enum CodingKeys: String, CodingKey {
        case verdict, corrected, changes
        case nativeVersion = "native_version"
    }

    // The guardrail from check.py: if the model says "natural", or its
    // corrected text is identical to what the user wrote, we show ✓ and
    // no changes, whatever else it returned.
    func isNatural(original: String) -> Bool {
        verdict == "natural" || corrected == original
    }
}
