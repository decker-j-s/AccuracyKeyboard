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

        // How much room this change needs on screen. Shared so the iPhone
        // and Mac lay out change cards the same way.
        //   tiny:   不 → 没                 (reason beside it)
        //   medium: 去中国在明年 → 明年去中国  (side by side, reason below)
        //   long:   "sign up for the class…" → 报名…  (stacked, text wraps)
        enum Size { case tiny, medium, long }

        var size: Size {
            if from.count + to.count <= 6 { return .tiny }
            if from.count <= 8 && to.count <= 8 { return .medium }
            return .long
        }
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

    // The changes to show on screen, cleaned up in case the model slips:
    // skips empty entries, and fills in a blank reason so the card never
    // has a mysterious gap. (The red/green line comes from the diff, so
    // it's always complete even if this list isn't.)
    var displayChanges: [Change] {
        changes
            .filter { !($0.from.isEmpty && $0.to.isEmpty) }
            .map { change in
                let reason = change.reason.trimmingCharacters(in: .whitespacesAndNewlines)
                return reason.isEmpty
                    ? Change(from: change.from, to: change.to, reason: "No explanation given for this change.")
                    : change
            }
    }
}
