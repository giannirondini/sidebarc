import AppKit

/// The bottom bar: the Settings gear, one icon per space, and `+` (Arc's space bar).
///
/// ```
/// [⚙︎]  [🚀][💼][●][📚]  [+]      every icon fits
/// [⚙︎]   ·  · [💼] ·  ·  ·   [+]      compact: only the selected space's icon
/// ```
///
/// Space icons are centred while they fit. When they don't (a narrow window, many
/// spaces), the bar goes compact: unselected spaces become small dots
/// (`SpaceBarLayout`); if even that overflows, it scrolls horizontally (with faded
/// edges) and keeps the selected one in view. The selection is a separate pill view
/// behind the icons, so a space switch can slide it; in compact mode the two slots
/// involved resize along with it.
/// Outside the swipe clip; register it with `SwipeGestureService.addExcludedView`
/// so a horizontal scroll here scrolls the bar instead of switching spaces.
@MainActor
final class SpaceBarView: NSView {
    struct Item: Equatable {
        let id: UUID
        let name: String
        let icon: CustomIcon?
        /// `Workspace.color` (opaque).
        let color: NSColor
    }

    var onSpaceSelected: ((UUID) -> Void)?
    var onSpaceContextMenu: ((UUID, NSEvent) -> Void)?
    var onAddSpace: (() -> Void)?
    var onSettings: (() -> Void)?

    private let buttonSize = ThemeConstants.Sizing.spaceBarButtonSize
    private let gap = ThemeConstants.Spacing.tiny
    private let fadeWidth = ThemeConstants.Spacing.huge
    private static let edgeTolerance = SpaceBarLayout.edgeTolerance

    private let settingsButton = SpaceBarButton(symbolName: "gearshape", label: "Settings")
    private let addButton = SpaceBarButton(symbolName: "plus", label: "New Space")
    private let scrollView = SpaceBarScrollView()
    private let documentView = FlippedView()
    private let selectionPill = NSView()
    private let fadeMask = CAGradientLayer()

    private var items: [Item] = []
    private var spaceButtons: [SpaceBarButton] = []
    private var selectedId: UUID?
    private var isSettingsShown = false
    private let geometry = SpaceBarLayout()
    private var isCompact = false
    /// The last layout's slots, for the edge dots (which follow the scroll).
    private var arrangement: SpaceBarLayout.Result?

    /// During a space transition: how far the selection has moved toward a space
    /// (layout follows it; nil otherwise).
    private struct SelectionBlend {
        var towardId: UUID?
        var progress: CGFloat
    }
    private var blend: SelectionBlend?
    /// Compact mode: drives the blend on the pages' spring while a switch settles
    /// (slot widths are layout, which can't ride a Core Animation spring).
    private var settleTimer: Timer?
    private static let pillAnimationKey = "spaceTransition"

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: ThemeConstants.Sizing.spaceBarHeight)
    }

    private func setup() {
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true

        settingsButton.onTap = { [weak self] in self?.onSettings?() }
        addButton.onTap = { [weak self] in self?.onAddSpace?() }
        addSubview(settingsButton)
        addSubview(addButton)

        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasHorizontalScroller = false
        scrollView.hasVerticalScroller = false
        scrollView.horizontalScrollElasticity = .none  // scrolling is SpaceBarScrollView's own
        scrollView.verticalScrollElasticity = .none
        scrollView.wantsLayer = true
        scrollView.documentView = documentView
        scrollView.contentView.postsBoundsChangedNotifications = true
        addSubview(scrollView)

        fadeMask.startPoint = CGPoint(x: 0, y: 0.5)
        fadeMask.endPoint = CGPoint(x: 1, y: 0.5)
        scrollView.layer?.mask = fadeMask

        selectionPill.wantsLayer = true
        selectionPill.layer?.cornerRadius = ThemeConstants.CornerRadius.small
        selectionPill.layer?.backgroundColor = ThemeConstants.Colors.darkGray
            .withAlphaComponent(ThemeConstants.Opacity.subtle).cgColor
        documentView.addSubview(selectionPill)

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(scrollBoundsChanged),
            name: NSView.boundsDidChangeNotification,
            object: scrollView.contentView
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - Content

    func update(items newItems: [Item], selectedId newSelectedId: UUID?, isSettingsShown newSettingsShown: Bool) {
        let itemsChanged = newItems != items
        let selectionChanged = newSelectedId != selectedId || newSettingsShown != isSettingsShown
        items = newItems
        selectedId = newSelectedId
        isSettingsShown = newSettingsShown

        if itemsChanged {
            rebuildSpaceButtons()
        }
        updateSelection()
        if itemsChanged || selectionChanged {
            needsLayout = true
            layoutSubtreeIfNeeded()
            scrollSelectedIntoView()
        }
    }

    private func rebuildSpaceButtons() {
        spaceButtons.forEach { $0.removeFromSuperview() }
        spaceButtons = items.map { item in
            let button = SpaceBarButton(spaceIcon: item.icon, color: item.color, label: item.name)
            button.onTap = { [weak self] in self?.onSpaceSelected?(item.id) }
            button.onRightClick = { [weak self] event in self?.onSpaceContextMenu?(item.id, event) }
            documentView.addSubview(button)
            return button
        }
    }

    private func updateSelection() {
        settingsButton.isSelected = isSettingsShown
        let selectedIndex = isSettingsShown ? nil : items.firstIndex(where: { $0.id == selectedId })
        for (index, button) in spaceButtons.enumerated() {
            button.isSelected = index == selectedIndex
        }
        selectionPill.isHidden = selectedIndex == nil
    }

    // MARK: - Selection during a space transition

    private func index(of spaceId: UUID?) -> Int? {
        guard let spaceId, let index = items.firstIndex(where: { $0.id == spaceId }),
              index < spaceButtons.count else { return nil }
        return index
    }

    // The pill and the buttons move by their frames (which AppKit keeps), plus an
    // additive animation for the pill in full mode, never by a layer transform:
    // AppKit resets the transforms of its views' layers.

    /// While a swipe is tracked: the pill sits `progress` (0…1) of the way from
    /// the selected space's icon toward `targetId`'s (nil: stays put). In compact
    /// mode the selected slot shrinks to a dot meanwhile and the target's grows.
    func setSelectionProgress(toward targetId: UUID?, progress: CGFloat) {
        guard index(of: selectedId) != nil else { return }
        stopSettle()
        blend = SelectionBlend(towardId: targetId, progress: progress)
        relayout()
    }

    /// Moves the selection from where it is now to `spaceId`'s icon.
    ///
    /// - Full mode: the pill slides with `animation`, built for `keyPath` from the
    ///   start to the end offset (applied additively).
    /// - Compact mode: the slots resize too, so a timer lays the bar out along
    ///   `travel` (fraction of the way done, 0 → 1, at a time in seconds) until
    ///   `duration`: the same curve as the pages.
    ///
    /// Call inside the transition's `CATransaction` so it runs in step with the page.
    func settleSelection(
        on spaceId: UUID,
        duration: TimeInterval,
        travel: @escaping @Sendable (TimeInterval) -> CGFloat,
        animation: (_ keyPath: String, _ from: CGFloat, _ to: CGFloat) -> CAPropertyAnimation
    ) {
        guard !isSettingsShown, index(of: spaceId) != nil, let layer = selectionPill.layer else { return }
        stopSettle()
        layer.removeAnimation(forKey: Self.pillAnimationKey)

        // Back to the selected space (a cancelled swipe): the blend unwinds toward 0.
        // Toward another space: it runs on to 1 (from 0 for a click).
        let backToSelected = spaceId == selectedId
        let towardId = backToSelected ? blend?.towardId : spaceId
        let startProgress = blend.map { $0.towardId == towardId ? $0.progress : 0 } ?? 0
        let endProgress: CGFloat = backToSelected ? 0 : 1

        guard isCompact else {
            let currentX = selectionPill.frame.minX
            blend = SelectionBlend(towardId: towardId, progress: endProgress)
            relayout()
            let move = animation("position.x", currentX - selectionPill.frame.minX, 0)
            move.isAdditive = true
            layer.add(move, forKey: Self.pillAnimationKey)
            return
        }

        blend = SelectionBlend(towardId: towardId, progress: startProgress)
        let start = CACurrentMediaTime()
        let timer = Timer(timeInterval: ThemeConstants.SpaceTransition.layoutFrameInterval, repeats: true) { [weak self] timer in
            // Timers on the main run loop fire on the main thread.
            let done = MainActor.assumeIsolated { () -> Bool in
                // A stopped settle's timer is invalidated, so it never gets here.
                guard let self else { return true }
                let elapsed = CACurrentMediaTime() - start
                let fraction = elapsed >= duration ? 1 : travel(elapsed)
                self.blend?.progress = startProgress + (endProgress - startProgress) * fraction
                self.relayout()
                return elapsed >= duration
            }
            if done {
                timer.invalidate()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        settleTimer = timer
    }

    /// Ends a transition: the selection rests where it was going; the next `update`
    /// takes over.
    func endSelectionTransition() {
        selectionPill.layer?.removeAnimation(forKey: Self.pillAnimationKey)
        stopSettle()
        blend = nil
        // A drag landed mid-way left the pill between two icons; layout puts it back.
        needsLayout = true
    }

    private func stopSettle() {
        settleTimer?.invalidate()
        settleTimer = nil
    }

    private func relayout() {
        needsLayout = true
        layoutSubtreeIfNeeded()
    }

    /// The button of a space, e.g. to anchor a popover to it.
    func buttonView(for spaceId: UUID) -> NSView? {
        index(of: spaceId).map { spaceButtons[$0] }
    }

    private func scrollSelectedIntoView() {
        guard let index = index(of: selectedId) else { return }
        documentView.scrollToVisible(spaceButtons[index].frame.insetBy(dx: -fadeWidth, dy: 0))
    }

    // MARK: - Layout

    override func layout() {
        super.layout()
        let height = bounds.height
        let y = (height - buttonSize) / 2

        settingsButton.frame = NSRect(x: 0, y: y, width: buttonSize, height: buttonSize)
        addButton.frame = NSRect(x: bounds.width - buttonSize, y: y, width: buttonSize, height: buttonSize)

        let scrollX = buttonSize + gap
        let scrollWidth = max(0, bounds.width - 2 * (buttonSize + gap))
        scrollView.frame = NSRect(x: scrollX, y: 0, width: scrollWidth, height: height)

        // With Settings shown the current space keeps its icon (no pill), so the
        // gear doesn't reflow the bar.
        let arrangement = geometry.arrange(
            count: spaceButtons.count,
            availableWidth: scrollWidth,
            selected: index(of: selectedId),
            toward: index(of: blend?.towardId),
            progress: blend?.progress ?? 0
        )
        isCompact = arrangement.isCompact
        self.arrangement = arrangement
        documentView.frame = NSRect(x: 0, y: 0, width: arrangement.documentWidth, height: height)

        // Centred while they fit; otherwise packed from the leading edge and scrolled.
        for (button, slot) in zip(spaceButtons, arrangement.slots) {
            button.frame = NSRect(x: slot.x, y: y, width: slot.width, height: buttonSize)
            button.expansion = slot.expansion
        }
        if let pill = arrangement.pill {
            selectionPill.frame = NSRect(x: pill.x, y: y, width: pill.width, height: buttonSize)
        }
        updateFadeMask()
        updateEdgeDots()
    }

    @objc private func scrollBoundsChanged() {
        updateFadeMask()
        updateEdgeDots()
        spaceButtons.forEach { $0.refreshHoverState() }
    }

    /// Shrinks the dots toward a scrollable edge (only a compact bar ever scrolls).
    private func updateEdgeDots() {
        let fullSize = geometry.dotSize
        guard let arrangement, arrangement.isCompact else {
            spaceButtons.forEach { $0.dotSize = fullSize }
            return
        }
        let visible = scrollView.contentView.documentVisibleRect
        let sizes = geometry.edgeDotSizes(
            slots: arrangement.slots,
            documentWidth: arrangement.documentWidth,
            visibleMinX: visible.minX,
            visibleMaxX: visible.maxX
        )
        for (button, size) in zip(spaceButtons, sizes) {
            button.dotSize = size
        }
    }

    /// Fades an edge only when there is more to scroll to on that side.
    private func updateFadeMask() {
        let width = scrollView.bounds.width
        guard width > 0 else { return }
        let visible = scrollView.contentView.documentVisibleRect
        let canScrollLeft = visible.minX > Self.edgeTolerance
        let canScrollRight = visible.maxX < documentView.frame.width - Self.edgeTolerance
        let fade = min(fadeWidth / width, 0.5)
        let opaque = NSColor.black.cgColor
        let clear = NSColor.clear.cgColor

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        fadeMask.frame = scrollView.bounds
        fadeMask.colors = [canScrollLeft ? clear : opaque, opaque, opaque, canScrollRight ? clear : opaque]
        fadeMask.locations = [0, NSNumber(value: Double(fade)), NSNumber(value: Double(1 - fade)), 1]
        CATransaction.commit()
    }
}

// MARK: - Buttons

/// A button of the space bar: a space's icon (or colour dot), or a symbol (gear,
/// `+`). Unselected content is dimmed; hover shows a faint background. In a compact
/// bar an unselected space is a narrow slot with a small neutral dot (`expansion`).
@MainActor
final class SpaceBarButton: BaseControl {
    var onTap: (() -> Void)?
    var onRightClick: ((NSEvent) -> Void)?

    /// Selected space: full-opacity icon (the pill behind it is drawn by the bar).
    /// Selected gear: its own background, since it has no pill.
    var isSelected = false {
        didSet {
            setAccessibilitySelected(isSelected)
            updateAppearance()
        }
    }

    /// Space buttons: 1 shows the space's icon, 0 the compact bar's dot; in between
    /// (a switch in a compact bar) they crossfade.
    var expansion: CGFloat = 1 {
        didSet {
            if expansion != oldValue { updateAppearance() }
        }
    }

    /// Space buttons: the compact bar's dot diameter (smaller at a scrollable edge).
    var dotSize: CGFloat = ThemeConstants.Sizing.spaceBarDotSize {
        didSet {
            guard dotSize != oldValue else { return }
            dotWidth?.constant = dotSize
            dotHeight?.constant = dotSize
            dotView?.layer?.cornerRadius = ThemeConstants.CornerRadius.round(dotSize)
        }
    }

    private let content: NSView
    /// Space buttons only: the compact bar's dot.
    private let dotView: NSView?
    private var dotWidth: NSLayoutConstraint?
    private var dotHeight: NSLayoutConstraint?
    private let drawsOwnSelection: Bool

    init(spaceIcon: CustomIcon?, color: NSColor, label: String) {
        let iconView = SpaceIconView()
        iconView.iconSize = ThemeConstants.Sizing.iconMedium
        iconView.configure(icon: spaceIcon, color: color)
        content = iconView
        let dot = NSView()
        dot.wantsLayer = true
        dot.layer?.cornerRadius = ThemeConstants.CornerRadius.round(ThemeConstants.Sizing.spaceBarDotSize)
        dot.layer?.backgroundColor = ThemeConstants.Colors.darkGray
            .withAlphaComponent(ThemeConstants.Opacity.medium).cgColor
        dotView = dot
        drawsOwnSelection = false
        super.init(frame: .zero)
        setup(label: label)
    }

    init(symbolName: String, label: String) {
        let imageView = NSImageView()
        let config = NSImage.SymbolConfiguration(pointSize: ThemeConstants.Sizing.iconSmall, weight: .semibold)
        imageView.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: label)?
            .withSymbolConfiguration(config)
        imageView.contentTintColor = ThemeConstants.Colors.darkGray
        imageView.imageScaling = .scaleNone
        content = imageView
        dotView = nil
        drawsOwnSelection = true
        super.init(frame: .zero)
        setup(label: label)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setup(label: String) {
        layer?.cornerRadius = ThemeConstants.CornerRadius.small
        toolTip = label
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel(label)

        content.translatesAutoresizingMaskIntoConstraints = false
        addSubview(content)
        NSLayoutConstraint.activate([
            content.centerXAnchor.constraint(equalTo: centerXAnchor),
            content.centerYAnchor.constraint(equalTo: centerYAnchor),
            content.widthAnchor.constraint(equalToConstant: ThemeConstants.Sizing.iconMedium),
            content.heightAnchor.constraint(equalToConstant: ThemeConstants.Sizing.iconMedium),
        ])
        if let dotView {
            dotView.translatesAutoresizingMaskIntoConstraints = false
            addSubview(dotView)
            let width = dotView.widthAnchor.constraint(equalToConstant: dotSize)
            let height = dotView.heightAnchor.constraint(equalToConstant: dotSize)
            NSLayoutConstraint.activate([
                dotView.centerXAnchor.constraint(equalTo: centerXAnchor),
                dotView.centerYAnchor.constraint(equalTo: centerYAnchor),
                width,
                height,
            ])
            dotWidth = width
            dotHeight = height
        }
        updateAppearance()
    }

    override func handleHoverStateChanged() {
        updateAppearance()
    }

    override func handlePressedStateChanged() {
        updateAppearance()
    }

    override func performAction() {
        onTap?()
    }

    override func rightMouseDown(with event: NSEvent) {
        onRightClick?(event)
    }

    override func accessibilityPerformPress() -> Bool {
        onTap?()
        return true
    }

    private func updateAppearance() {
        let background: NSColor
        if drawsOwnSelection && isSelected {
            background = ThemeConstants.Colors.darkGray.withAlphaComponent(ThemeConstants.Opacity.subtle)
        } else if isPressed {
            background = ThemeConstants.Colors.darkGray.withAlphaComponent(ThemeConstants.Opacity.extraSubtle)
        } else if isHovered && !isSelected {
            background = ThemeConstants.Colors.darkGray.withAlphaComponent(ThemeConstants.Opacity.minimal)
        } else {
            background = .clear
        }
        layer?.backgroundColor = background.cgColor
        let alpha = isSelected || isHovered ? ThemeConstants.Opacity.full : ThemeConstants.Opacity.medium
        guard let dotView else {
            content.alphaValue = alpha
            return
        }
        content.alphaValue = alpha * expansion
        dotView.alphaValue = alpha * (1 - expansion)
        // Fully a dot: the icon (wider than the slot) stays out of the way.
        content.isHidden = expansion == 0
        dotView.isHidden = expansion == 1
    }
}

/// Top-left origin, so the bar lays out like the rest of the sidebar.
private final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}

