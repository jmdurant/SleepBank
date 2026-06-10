import Foundation

/// Small interval algebra used to let user-defined "OK to nap" windows override the
/// calendar: subtracting an allowed window from a busy block punches a hole in it,
/// so a free moment opens up inside an otherwise-booked stretch.
public enum Intervals {

    /// Remove every `allowed` range from each `busy` interval, returning the
    /// remaining busy pieces. An allowed window covering a busy block removes it; one
    /// in the middle splits it in two; one overlapping an edge trims it.
    public static func subtract(_ allowed: [DateInterval], from busy: [DateInterval]) -> [DateInterval] {
        guard !allowed.isEmpty else { return busy }
        var result = busy
        for window in allowed {
            result = result.flatMap { block -> [DateInterval] in
                guard block.intersects(window) else { return [block] }
                var pieces: [DateInterval] = []
                if window.start > block.start { pieces.append(DateInterval(start: block.start, end: window.start)) }
                if window.end < block.end { pieces.append(DateInterval(start: window.end, end: block.end)) }
                return pieces
            }
        }
        return result
    }
}
