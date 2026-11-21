import AppKit

/// How far a scroll event over the space bar moves it (pure, so it's tested without
/// events).
///
/// AppKit's scroll view ignores the vertical part of a gesture over a bar that only
/// scrolls sideways and applies just the horizontal drift of the fingers (1–2 pt per
/// event, either sign), so a vertical swipe made the bar jitter. Here each trackpad
/// gesture locks to its dominant axis once it has moved `lockDistance`, keeps it
/// through the momentum that follows, and only that axis moves the bar: up/down
/// scrolls it like left/right (fingers up or left reveal the later spaces).
/// A mouse wheel (no phases) moves `linePitch` per line, along its dominant axis.
struct SpaceBarScrollMapper: Equatable {
    enum Axis: Equatable {
        case horizontal
        case vertical
    }

    var lockDistance: CGFloat = ThemeConstants.Sizing.spaceBarScrollLockDistance
    /// One dot slot, so a wheel notch moves the bar by about a dot.
    var linePitch: CGFloat = ThemeConstants.Sizing.spaceBarCompactSlotWidth + ThemeConstants.Spacing.tiny

    private(set) var axis: Axis?
    private var pendingX: CGFloat = 0
    private var pendingY: CGFloat = 0

    /// Points to move the bar's content by: positive toward the later spaces.
    /// - Parameters:
    ///   - beginsGesture: the fingers touched down (`began` / `mayBegin`).
    ///   - isPrecise: a trackpad (or Magic Mouse); false for a line-based wheel.
    mutating func offset(beginsGesture: Bool, isPrecise: Bool, dx: CGFloat, dy: CGFloat) -> CGFloat {
        guard isPrecise else {
            return -(abs(dy) > abs(dx) ? dy : dx) * linePitch
        }
        if beginsGesture {
            axis = nil
            pendingX = 0
            pendingY = 0
        }
        if let axis {
            return -(axis == .vertical ? dy : dx)
        }
        // Undecided: hold the movement until the direction is clear, then apply it.
        pendingX += dx
        pendingY += dy
        guard abs(pendingX) + abs(pendingY) >= lockDistance else { return 0 }
        let locked: Axis = abs(pendingY) > abs(pendingX) ? .vertical : .horizontal
        axis = locked
        return -(locked == .vertical ? pendingY : pendingX)
    }
}

/// The space bar's scroll view: scrolls only by `SpaceBarScrollMapper` (no rubber
/// band at the ends; the bar just stops there).
final class SpaceBarScrollView: NSScrollView {
    private var mapper = SpaceBarScrollMapper()

    override func scrollWheel(with event: NSEvent) {
        let offset = mapper.offset(
            beginsGesture: !event.phase.isDisjoint(with: [.began, .mayBegin]),
            isPrecise: event.hasPreciseScrollingDeltas,
            dx: event.scrollingDeltaX,
            dy: event.scrollingDeltaY
        )
        scrollContent(by: offset)
    }

    /// Moves the content by `offset` points, clamped to the ends.
    func scrollContent(by offset: CGFloat) {
        guard offset != 0, let documentView else { return }
        let clip = contentView
        let maxX = max(0, documentView.frame.width - clip.bounds.width)
        let x = min(maxX, max(0, clip.bounds.origin.x + offset))
        guard x != clip.bounds.origin.x else { return }
        clip.scroll(to: NSPoint(x: x, y: clip.bounds.origin.y))
        reflectScrolledClipView(clip)
    }
}
