import AppKit
import Testing
@testable import SidebArcCore

/// The space bar shows every space's icon while they fit, then goes compact (Arc's
/// bar: the selected space's icon, dots for the others), then scrolls.
/// Defaults: 28-pt slots, 16-pt dot slots, 4-pt gaps.
@Suite struct SpaceBarLayoutTests {
    private let layout = SpaceBarLayout(buttonSize: 28, compactWidth: 16, gap: 4)

    @Test func fullWhileEveryIconFits() throws {
        // 5 × 28 + 4 × 4 = 156
        let result = layout.arrange(count: 5, availableWidth: 156, selected: 2)
        #expect(!result.isCompact)
        #expect(result.slots.allSatisfy { $0.width == 28 && $0.expansion == 1 })
        #expect(result.documentWidth == 156)
        let pill = try #require(result.pill)
        let slot = try #require(result.slots[safe: 2])
        #expect(pill == SpaceBarLayout.Pill(x: slot.x, width: 28))
    }

    @Test func fullIsCentred() throws {
        let result = layout.arrange(count: 2, availableWidth: 100, selected: 0)
        // 2 × 28 + 4 = 60, centred in 100.
        let first = try #require(result.slots.first)
        let last = try #require(result.slots.last)
        #expect(first.x == 20)
        #expect(last.x + last.width == 80)
    }

    @Test func compactOncePastTheFit() throws {
        // One point short of the 156 the five icons need.
        let result = layout.arrange(count: 5, availableWidth: 155, selected: 2)
        #expect(result.isCompact)
        #expect(result.slots.map(\.width) == [16, 16, 28, 16, 16])
        #expect(result.slots.map(\.expansion) == [0, 0, 1, 0, 0])
        // 28 + 4 × 16 + 4 × 4 = 108, centred in 155.
        let first = try #require(result.slots.first)
        #expect(first.x == 23.5)
        let pill = try #require(result.pill)
        let selected = try #require(result.slots[safe: 2])
        #expect(pill == SpaceBarLayout.Pill(x: selected.x, width: 28))
    }

    @Test func sub_pointRoundingDoesNotCompact() {
        #expect(!layout.isCompact(count: 5, availableWidth: 155.6))
    }

    @Test func modeIgnoresTheSelection() {
        for selected in [nil, 0, 4] as [Int?] {
            #expect(layout.arrange(count: 5, availableWidth: 155, selected: selected).isCompact)
            #expect(!layout.arrange(count: 5, availableWidth: 156, selected: selected).isCompact)
        }
    }

    @Test func compactStillOverflowingScrolls() throws {
        // 40 spaces: 28 + 39 × 16 + 39 × 4 = 808 > 200.
        let result = layout.arrange(count: 40, availableWidth: 200, selected: 10)
        #expect(result.isCompact)
        #expect(result.documentWidth == 808)
        let first = try #require(result.slots.first)
        #expect(first.x == 0)  // packed from the leading edge
    }

    @Test func aSingleSpaceAlwaysShowsItsIcon() throws {
        let result = layout.arrange(count: 1, availableWidth: 10, selected: 0)
        #expect(!result.isCompact)
        let slot = try #require(result.slots.first)
        #expect(slot.width == 28 && slot.expansion == 1)
    }

    @Test func noSelectionMeansNoPill() {
        let compact = layout.arrange(count: 6, availableWidth: 100, selected: nil)
        #expect(compact.pill == nil)
        #expect(compact.slots.allSatisfy { $0.expansion == 0 })
        #expect(layout.arrange(count: 0, availableWidth: 100, selected: nil).slots.isEmpty)
    }

    @Test func outOfRangeIndicesAreIgnored() {
        let result = layout.arrange(count: 3, availableWidth: 50, selected: 7, toward: 9, progress: 0.5)
        #expect(result.pill == nil)
    }

    /// Mid-switch in compact mode: the selected slot shrinks as the target's grows,
    /// the row keeps its width, and the pill ends exactly on the target's full slot.
    @Test func compactSwitchResizesTwoSlots() throws {
        let widths = { (progress: CGFloat) in
            layout.arrange(count: 6, availableWidth: 120, selected: 1, toward: 4, progress: progress)
        }
        let start = widths(0), half = widths(0.5), end = widths(1)
        #expect(start.slots.map(\.width) == [16, 28, 16, 16, 16, 16])
        #expect(half.slots.map(\.width) == [16, 22, 16, 16, 22, 16])
        #expect(end.slots.map(\.width) == [16, 16, 16, 16, 28, 16])
        #expect(half.slots.map(\.expansion) == [0, 0.5, 0, 0, 0.5, 0])

        let rowWidth = { (result: SpaceBarLayout.Result) -> CGFloat in
            guard let first = result.slots.first, let last = result.slots.last else { return 0 }
            return last.x + last.width - first.x
        }
        #expect(rowWidth(start) == rowWidth(half))
        #expect(rowWidth(start) == rowWidth(end))

        let startPill = try #require(start.pill), endPill = try #require(end.pill)
        let from = try #require(start.slots[safe: 1]), to = try #require(end.slots[safe: 4])
        #expect(startPill == SpaceBarLayout.Pill(x: from.x, width: 28))
        #expect(endPill == SpaceBarLayout.Pill(x: to.x, width: 28))
    }

    /// Full mode: only the pill moves; the slots stay put.
    @Test func fullSwitchSlidesOnlyThePill() throws {
        let start = layout.arrange(count: 3, availableWidth: 200, selected: 0, toward: 2, progress: 0)
        let half = layout.arrange(count: 3, availableWidth: 200, selected: 0, toward: 2, progress: 0.5)
        #expect(start.slots == half.slots)
        let from = try #require(half.slots.first), to = try #require(half.slots.last)
        let pill = try #require(half.pill)
        #expect(pill == SpaceBarLayout.Pill(x: (from.x + to.x) / 2, width: 28))
    }

    // MARK: - Edge dots

    private let dots = SpaceBarLayout(
        buttonSize: 28, compactWidth: 16, gap: 4, dotSize: 5, edgeDotMinSize: 2, edgeDotRamp: 40
    )

    /// 40 spaces in 200 pt: content is 808 wide, packed from x = 0.
    private func scrolled() -> SpaceBarLayout.Result {
        dots.arrange(count: 40, availableWidth: 200, selected: 10)
    }

    @Test func dotsAreFullWhenNothingIsHidden() {
        let result = dots.arrange(count: 5, availableWidth: 155, selected: 2)
        let sizes = dots.edgeDotSizes(slots: result.slots, documentWidth: result.documentWidth,
                                      visibleMinX: 0, visibleMaxX: 155)
        #expect(sizes.allSatisfy { $0 == 5 })
    }

    @Test func dotsShrinkOnlyTowardAScrollableEdge() throws {
        let result = scrolled()
        // At the leading end: only the trailing edge has more beyond it.
        let sizes = dots.edgeDotSizes(slots: result.slots, documentWidth: result.documentWidth,
                                      visibleMinX: 0, visibleMaxX: 200)
        #expect(try #require(sizes.first) == 5)
        // Dots before the selected slot sit every 20 pt; the last one before the
        // edge (slot 9: 180…196, centre 188) is 12 pt from it: 2 + 3 × 12/40.
        let index = 9
        let edge = try #require(sizes[safe: index])
        #expect(abs(edge - 2.9) < 0.0001)
        let inner = try #require(sizes[safe: index - 1])
        #expect(inner > edge && inner < 5)
        // Slots past the edge sit at the minimum.
        #expect(try #require(sizes.last) == 2)
    }

    @Test func dotsShrinkOnBothSidesInTheMiddle() throws {
        let result = scrolled()
        let sizes = dots.edgeDotSizes(slots: result.slots, documentWidth: result.documentWidth,
                                      visibleMinX: 300, visibleMaxX: 500)
        #expect(try #require(sizes.first) == 2)
        #expect(try #require(sizes.last) == 2)
        // Some dot in the middle of the visible range is full size.
        #expect(sizes.contains(5))
    }

    @Test func progressIsClamped() {
        let over = layout.arrange(count: 6, availableWidth: 120, selected: 1, toward: 4, progress: 1.7)
        let end = layout.arrange(count: 6, availableWidth: 120, selected: 1, toward: 4, progress: 1)
        #expect(over == end)
    }
}

/// The real bar: resizing across the threshold turns icons into dots and back.
@MainActor
@Suite struct SpaceBarViewCompactTests {
    private let bar = SpaceBarView(frame: .zero)
    private let items: [SpaceBarView.Item] = (0..<6).map {
        SpaceBarView.Item(id: UUID(), name: "Space \($0)", icon: nil, color: .systemBlue)
    }

    init() {
        bar.translatesAutoresizingMaskIntoConstraints = true
    }

    /// Bar width for a scroll area of `width` (gear and `+` take 28 + 4 each).
    private func setScrollWidth(_ width: CGFloat) {
        bar.frame = NSRect(x: 0, y: 0, width: width + 64, height: ThemeConstants.Sizing.spaceBarHeight)
        bar.layoutSubtreeIfNeeded()
    }

    private func expansions() throws -> [CGFloat] {
        try items.map { item in
            let button = try #require(bar.buttonView(for: item.id) as? SpaceBarButton)
            return button.expansion
        }
    }

    @Test func iconsBecomeDotsWhenTheBarNarrows() throws {
        let selected = try #require(items[safe: 3])
        bar.update(items: items, selectedId: selected.id, isSettingsShown: false)
        let fullWidth = SpaceBarLayout().fullWidth(count: items.count)

        setScrollWidth(fullWidth)
        #expect(try expansions() == [1, 1, 1, 1, 1, 1])

        setScrollWidth(fullWidth - 10)
        #expect(try expansions() == [0, 0, 0, 1, 0, 0])
        let button = try #require(bar.buttonView(for: selected.id))
        #expect(button.frame.width == ThemeConstants.Sizing.spaceBarButtonSize)

        setScrollWidth(fullWidth + 40)
        #expect(try expansions() == [1, 1, 1, 1, 1, 1])
    }

    /// With Settings shown the current space keeps its slot, so the gear doesn't reflow.
    @Test func settingsKeepsTheCurrentSpaceExpanded() throws {
        let selected = try #require(items[safe: 2])
        bar.update(items: items, selectedId: selected.id, isSettingsShown: false)
        setScrollWidth(100)
        let before = try expansions()
        bar.update(items: items, selectedId: selected.id, isSettingsShown: true)
        #expect(try expansions() == before)
        #expect(before == [0, 0, 1, 0, 0, 0])
    }

    /// Dots shrink toward an edge with more spaces beyond it, and only there.
    @Test func edgeDotsShrinkTowardHiddenSpaces() throws {
        let many: [SpaceBarView.Item] = (0..<30).map {
            SpaceBarView.Item(id: UUID(), name: "Space \($0)", icon: nil, color: .systemBlue)
        }
        let first = try #require(many.first), last = try #require(many.last)
        bar.update(items: many, selectedId: first.id, isSettingsShown: false)
        setScrollWidth(200)
        let trailing = try #require(bar.buttonView(for: last.id) as? SpaceBarButton)
        #expect(trailing.dotSize == ThemeConstants.Sizing.spaceBarEdgeDotMinSize)
        // Scrolled to the start: nothing is hidden on the leading side.
        let second = try #require(many[safe: 1])
        let leading = try #require(bar.buttonView(for: second.id) as? SpaceBarButton)
        #expect(leading.dotSize == ThemeConstants.Sizing.spaceBarDotSize)
    }

    /// A tracked swipe resizes the two slots; ending the transition and selecting
    /// the target lands on the same geometry.
    @Test func swipeProgressLandsWithoutAJump() throws {
        let from = try #require(items[safe: 1]), to = try #require(items[safe: 2])
        bar.update(items: items, selectedId: from.id, isSettingsShown: false)
        setScrollWidth(100)

        bar.setSelectionProgress(toward: to.id, progress: 1)
        let target = try #require(bar.buttonView(for: to.id))
        let trackedFrame = target.frame
        #expect(try expansions() == [0, 0, 1, 0, 0, 0])

        bar.endSelectionTransition()
        bar.update(items: items, selectedId: to.id, isSettingsShown: false)
        #expect(target.frame == trackedFrame)
    }
}
