import AppKit
import Testing
@testable import SidebArcCore

/// A vertical swipe over the space bar used to move it only by the fingers' sideways
/// drift (diagnosed from real trackpad logs on 2026-11-21): each gesture now locks
/// to its dominant axis, and up/down scrolls the bar like left/right.
@Suite struct SpaceBarScrollMapperTests {
    private func mapper() -> SpaceBarScrollMapper {
        SpaceBarScrollMapper(lockDistance: 4, linePitch: 20)
    }

    /// The shape of a real vertical swipe: dy −1…−2 per event, dx noise 0…1.
    @Test func verticalSwipeIgnoresSidewaysDrift() {
        var scroll = mapper()
        let events: [(CGFloat, CGFloat)] = [(0, -1), (0, -1), (1, -1), (1, -2), (0, -1), (1, -2), (0, -2), (-1, -1)]
        var offsets: [CGFloat] = []
        for (index, (dx, dy)) in events.enumerated() {
            offsets.append(scroll.offset(beginsGesture: index == 0, isPrecise: true, dx: dx, dy: dy))
        }
        #expect(scroll.axis == .vertical)
        // Never backwards, and the whole vertical travel arrives (fingers up → later spaces).
        #expect(offsets.allSatisfy { $0 >= 0 })
        #expect(offsets.reduce(0, +) == 11)
    }

    @Test func horizontalSwipeUsesDx() {
        var scroll = mapper()
        let events: [(CGFloat, CGFloat)] = [(-3, 0), (-5, 1), (-8, 0), (-12, -1)]
        var total: CGFloat = 0
        for (index, (dx, dy)) in events.enumerated() {
            total += scroll.offset(beginsGesture: index == 0, isPrecise: true, dx: dx, dy: dy)
        }
        #expect(scroll.axis == .horizontal)
        #expect(total == 28)
    }

    @Test func nothingMovesUntilTheAxisIsClear() {
        var scroll = mapper()
        #expect(scroll.offset(beginsGesture: true, isPrecise: true, dx: 0, dy: -1) == 0)
        #expect(scroll.offset(beginsGesture: false, isPrecise: true, dx: 1, dy: -1) == 0)
        #expect(scroll.axis == nil)
        // Past 4 pt: the held movement along the winning axis arrives at once.
        #expect(scroll.offset(beginsGesture: false, isPrecise: true, dx: 0, dy: -2) == 4)
    }

    /// Momentum events have no gesture phase: they keep the gesture's axis.
    @Test func momentumKeepsTheAxis() {
        var scroll = mapper()
        _ = scroll.offset(beginsGesture: true, isPrecise: true, dx: 0, dy: -6)
        #expect(scroll.offset(beginsGesture: false, isPrecise: true, dx: 3, dy: -20) == 20)
        #expect(scroll.axis == .vertical)
    }

    @Test func aNewGestureDecidesAgain() {
        var scroll = mapper()
        _ = scroll.offset(beginsGesture: true, isPrecise: true, dx: 0, dy: -6)
        #expect(scroll.axis == .vertical)
        #expect(scroll.offset(beginsGesture: true, isPrecise: true, dx: 6, dy: 0) == -6)
        #expect(scroll.axis == .horizontal)
    }

    @Test func mouseWheelMovesADotPerLine() {
        var scroll = mapper()
        #expect(scroll.offset(beginsGesture: false, isPrecise: false, dx: 0, dy: -1) == 20)
        #expect(scroll.offset(beginsGesture: false, isPrecise: false, dx: 0, dy: 2) == -40)
        #expect(scroll.offset(beginsGesture: false, isPrecise: false, dx: -1, dy: 0) == 20)
    }
}

@MainActor
@Suite struct SpaceBarScrollViewTests {
    @Test func scrollingIsClampedToTheContent() {
        let scroll = SpaceBarScrollView(frame: NSRect(x: 0, y: 0, width: 100, height: 32))
        scroll.documentView = NSView(frame: NSRect(x: 0, y: 0, width: 300, height: 32))
        scroll.scrollContent(by: 50)
        #expect(scroll.contentView.bounds.origin.x == 50)
        scroll.scrollContent(by: 1000)
        #expect(scroll.contentView.bounds.origin.x == 200)
        scroll.scrollContent(by: -1000)
        #expect(scroll.contentView.bounds.origin.x == 0)
    }
}
