import CoreGraphics

/// Where the space bar's icons go (pure geometry, so it's tested without views).
///
/// - **Full:** every space is a `buttonSize` slot showing its icon, centred while
///   they all fit in the available width.
/// - **Compact** (Arc's bar): once they don't, only the selected space keeps a
///   full slot; the others shrink to `compactWidth` dots. Still centred while they
///   fit, packed from the leading edge (and scrolled by the bar) when they don't.
///
/// The mode depends only on the space count and the width, never on the selection,
/// so a switch never flips it. During a switch in compact mode the selected slot
/// shrinks while the target's grows (`progress`); their widths add up to the same
/// total, so the row doesn't drift.
struct SpaceBarLayout: Equatable {
    struct Slot: Equatable {
        var x: CGFloat
        var width: CGFloat
        /// 1 = shows the space's icon, 0 = a dot; in between, they crossfade.
        var expansion: CGFloat
    }

    struct Pill: Equatable {
        var x: CGFloat
        var width: CGFloat
    }

    struct Result: Equatable {
        var isCompact: Bool
        /// Width of the scrolled content: at least the available width.
        var documentWidth: CGFloat
        var slots: [Slot]
        /// The selection pill (nil: no selected space).
        var pill: Pill?
    }

    var buttonSize: CGFloat = ThemeConstants.Sizing.spaceBarButtonSize
    var compactWidth: CGFloat = ThemeConstants.Sizing.spaceBarCompactSlotWidth
    var gap: CGFloat = ThemeConstants.Spacing.tiny
    var dotSize: CGFloat = ThemeConstants.Sizing.spaceBarDotSize
    var edgeDotMinSize: CGFloat = ThemeConstants.Sizing.spaceBarEdgeDotMinSize
    var edgeDotRamp: CGFloat = ThemeConstants.Sizing.spaceBarEdgeDotRamp

    /// Sub-point slack when deciding whether the bar can scroll further.
    static let edgeTolerance: CGFloat = 0.5

    /// Sub-point slack, so a width that fits on paper isn't compacted by rounding.
    private static let fitTolerance: CGFloat = 0.5

    /// Width of `count` full slots and the gaps between them.
    func fullWidth(count: Int) -> CGFloat {
        let n = CGFloat(max(0, count))
        return n * buttonSize + max(0, n - 1) * gap
    }

    func isCompact(count: Int, availableWidth: CGFloat) -> Bool {
        count > 1 && fullWidth(count: count) > availableWidth + Self.fitTolerance
    }

    /// - Parameters:
    ///   - selected: the selected space's index (its slot is full in compact mode).
    ///   - toward: during a switch, the target's index; `progress` (0…1) is how far
    ///     along the switch is.
    func arrange(
        count: Int,
        availableWidth: CGFloat,
        selected: Int?,
        toward: Int? = nil,
        progress: CGFloat = 0
    ) -> Result {
        let compact = isCompact(count: count, availableWidth: availableWidth)
        let selected = selected.flatMap { (0..<count).contains($0) ? $0 : nil }
        let toward = selected == nil ? nil : toward.flatMap { (0..<count).contains($0) ? $0 : nil }
        let progress = toward == nil || toward == selected ? 0 : min(1, max(0, progress))

        func expansion(_ index: Int) -> CGFloat {
            guard compact else { return 1 }
            var value: CGFloat = 0
            if index == selected { value += 1 - progress }
            if index == toward { value += progress }
            return value
        }

        let expansions = (0..<count).map(expansion)
        let widths = expansions.map { compactWidth + (buttonSize - compactWidth) * $0 }
        let contentWidth = widths.reduce(0, +) + CGFloat(max(0, count - 1)) * gap
        let documentWidth = max(contentWidth, availableWidth)

        var x = (documentWidth - contentWidth) / 2
        var slots: [Slot] = []
        slots.reserveCapacity(count)
        for (width, value) in zip(widths, expansions) {
            slots.append(Slot(x: x, width: width, expansion: value))
            x += width + gap
        }

        // The pill slides from the selected slot to the target's, which resize meanwhile.
        var pill: Pill?
        if let selected {
            let from = slots[selected]
            let to = toward.map { slots[$0] } ?? from
            pill = Pill(x: from.x + (to.x - from.x) * progress, width: from.width + (to.width - from.width) * progress)
        }
        return Result(isCompact: compact, documentWidth: documentWidth, slots: slots, pill: pill)
    }

    /// Dot diameter per slot while the bar shows `visibleMinX…visibleMaxX` of its
    /// content: at an edge with more beyond it, dots shrink toward `edgeDotMinSize`
    /// over `edgeDotRamp` (like a carousel's page indicator); elsewhere they're full.
    /// Continuous in the scroll position, so scrolling morphs them smoothly.
    func edgeDotSizes(slots: [Slot], documentWidth: CGFloat, visibleMinX: CGFloat, visibleMaxX: CGFloat) -> [CGFloat] {
        let canScrollLeft = visibleMinX > Self.edgeTolerance
        let canScrollRight = visibleMaxX < documentWidth - Self.edgeTolerance
        func size(atDistance distance: CGFloat) -> CGFloat {
            let fraction = edgeDotRamp > 0 ? min(1, max(0, distance / edgeDotRamp)) : 1
            return edgeDotMinSize + (dotSize - edgeDotMinSize) * fraction
        }
        return slots.map { slot in
            let center = slot.x + slot.width / 2
            var value = dotSize
            if canScrollLeft { value = min(value, size(atDistance: center - visibleMinX)) }
            if canScrollRight { value = min(value, size(atDistance: visibleMaxX - center)) }
            return value
        }
    }
}
