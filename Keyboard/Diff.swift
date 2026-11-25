import Foundation

// One run of characters in the tracked-changes view.
struct DiffSegment: Hashable {
    enum Kind { case same, removed, added }
    let kind: Kind
    var text: String
}

// Compares the user's message with the corrected one, character by
// character, and returns runs of same / removed / added text.
//
// Swift's built-in `difference(from:)` does the hard part. It tells us
// which positions were removed from the original and which positions
// were inserted into the corrected text. We then walk both strings
// side by side to put the pieces in reading order.
func diffSegments(original: String, corrected: String) -> [DiffSegment] {
    let old = Array(original)
    let new = Array(corrected)
    let diff = new.difference(from: old)

    var removedAt = Set<Int>()   // positions in `old`
    var addedAt = Set<Int>()     // positions in `new`
    for change in diff {
        switch change {
        case .remove(let offset, _, _): removedAt.insert(offset)
        case .insert(let offset, _, _): addedAt.insert(offset)
        }
    }

    var segments: [DiffSegment] = []
    func append(_ kind: DiffSegment.Kind, _ char: Character) {
        // Merge with the previous segment if it's the same kind,
        // so "不太" becomes one red run instead of two.
        if let last = segments.last, last.kind == kind {
            segments[segments.count - 1].text.append(char)
        } else {
            segments.append(DiffSegment(kind: kind, text: String(char)))
        }
    }

    var i = 0  // index into old
    var j = 0  // index into new
    while i < old.count || j < new.count {
        if i < old.count && removedAt.contains(i) {
            append(.removed, old[i]); i += 1      // deletions show before additions
        } else if j < new.count && addedAt.contains(j) {
            append(.added, new[j]); j += 1
        } else {
            append(.same, old[i]); i += 1; j += 1 // unchanged in both
        }
    }
    return segments
}

// Pinyin with tone marks, worked out on the phone (no API call).
// Apple's converter picks the most common reading, so a few characters
// with several readings (了, 得, 还, 行…) can occasionally be wrong.
func pinyin(_ text: String) -> String {
    let mutable = NSMutableString(string: text)
    CFStringTransform(mutable, nil, kCFStringTransformMandarinLatin, false)
    return mutable as String
}
