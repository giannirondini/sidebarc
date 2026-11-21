import AppKit
import os

/// One space switch in progress.
///
/// The page being left and the page being revealed are drawn as images on the
/// `SpacePageStage` (the live page is hidden meanwhile) and move by the same offset:
/// 1:1 with the finger while tracking, then a spring (`SpaceSwipe.Spring`) to the
/// end. The background colour and the space bar's pill follow the same progress
/// and the same spring. A swipe, a space bar click and ⌘⌥←/→ all go through here.
@MainActor
final class SpaceTransition {
    enum Phase {
        case tracking
        case settling(commits: Bool)
    }

    let fromWorkspace: Workspace
    let fromIndex: Int
    /// The space being revealed; nil past the first or last space (rubber band).
    var target: (workspace: Workspace, index: Int)?
    /// +1: the target is on the left (finger right, previous space); -1: on the right.
    var side: CGFloat = 1
    /// Page images rendered during this transition, so a drag that wiggles across
    /// its start doesn't render the same space again.
    var snapshots: [UUID: NSImage] = [:]
    /// Current horizontal offset of the pages (points).
    var offset: CGFloat = 0
    var phase: Phase = .tracking
    /// System "Reduce motion": nothing slides; a switch crossfades instead.
    let reducesMotion: Bool
    /// The target profile's Favorites went in when the settle started, so landing
    /// doesn't fade them in again.
    var favoritesSwapped = false
    /// Drives the Favorites' height from the old grid's to the new one's on the
    /// pages' spring; stopped on landing.
    var favoritesHeightTimer: Timer?

    init(fromWorkspace: Workspace, fromIndex: Int) {
        self.fromWorkspace = fromWorkspace
        self.fromIndex = fromIndex
        reducesMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }
}

extension MainViewController: SwipeGestureServiceDelegate {
    private static let transitionAnimationKey = "spaceTransition"
    private static let transitionLogger = Logger(subsystem: AppIdentity.logSubsystem, category: "transition")

    // MARK: - Gesture

    func swipeGestureDidBegin(_ service: SwipeGestureService) {
        // A new gesture during a settle: land the previous switch first.
        if spaceTransition != nil {
            finishSpaceTransitionNow()
        }
    }

    func swipeGestureDidUpdate(_ service: SwipeGestureService, translationX: CGFloat) {
        trackSpaceSwipe(translation: translationX)
    }

    func swipeGestureDidCancel(_ service: SwipeGestureService) {
        endSpaceSwipe(translation: 0, velocity: 0, forceStay: true)
    }

    func swipeGestureDidEnd(_ service: SwipeGestureService, translationX: CGFloat, velocityX: CGFloat) {
        endSpaceSwipe(translation: translationX, velocity: velocityX, forceStay: false)
    }

    // MARK: - Input during a transition

    /// While the pages slide, the model still selects the old space (and the live
    /// page underneath is the old one). So any click or key lands the transition
    /// first; the event then reaches the new space. Local monitors run before the
    /// event is dispatched. The monitor is removed with this controller.
    func installTransitionInputMonitor() {
        transitionInputMonitor = LocalEventMonitor(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown, .keyDown]) { [weak self] event in
            if let self, self.spaceTransition != nil {
                self.finishSpaceTransitionNow()
            }
            return event
        }
    }

    // MARK: - Entry points

    /// A click on a space bar icon or ⌘⌥←/→: slide to `id` with the same spring as
    /// a swipe. Instant (no transition) from Settings, for the current space, or
    /// while the window isn't visible.
    func requestSpaceSwitch(to id: UUID) {
        if spaceTransition != nil {
            finishSpaceTransitionNow()
        }
        let workspaces = model.workspaces
        guard !model.isSettingsShown,
              view.window?.isVisible == true,
              let fromIndex = workspaces.firstIndex(where: { $0.id == model.currentWorkspace.id }),
              let toIndex = workspaces.firstIndex(where: { $0.id == id }),
              fromIndex != toIndex
        else {
            model.selectWorkspace(id: id)
            return
        }
        let transition = beginSpaceTransition(fromIndex: fromIndex)
        // Further away than one space still slides one page, from its side.
        prepareTarget(of: transition, target: (workspaces[toIndex], toIndex), side: toIndex < fromIndex ? 1 : -1)
        settle(transition, commits: true, releaseVelocity: 0)
    }

    private func trackSpaceSwipe(translation: CGFloat) {
        guard !model.isSettingsShown else { return }
        if let transition = spaceTransition, case .settling = transition.phase {
            finishSpaceTransitionNow()
        }
        let transition: SpaceTransition
        if let existing = spaceTransition {
            transition = existing
        } else {
            guard let index = model.workspaces.firstIndex(where: { $0.id == model.currentWorkspace.id }) else { return }
            transition = beginSpaceTransition(fromIndex: index)
        }

        let width = swipeClipContainer.bounds.width
        let side: CGFloat = translation >= 0 ? 1 : -1
        let workspaces = model.workspaces
        let targetIndex = transition.fromIndex - Int(side)
        let target = workspaces.indices.contains(targetIndex) ? (workspaces[targetIndex], targetIndex) : nil
        if target?.1 != transition.target?.index || side != transition.side {
            prepareTarget(of: transition, target: target, side: side)
        }

        // Reduce Motion: the page doesn't follow the finger; the release decides.
        guard !transition.reducesMotion else { return }
        let offset = target == nil
            ? SpaceSwipe.rubberBand(translation, dimension: width)
            : max(-width, min(width, translation))
        apply(offset: offset, to: transition)
    }

    private func endSpaceSwipe(translation: CGFloat, velocity: CGFloat, forceStay: Bool) {
        guard let transition = spaceTransition, case .tracking = transition.phase else { return }
        let outcome = forceStay ? .stay : SpaceSwipe.outcome(
            translation: translation,
            velocity: velocity,
            width: swipeClipContainer.bounds.width,
            canGoPrevious: transition.fromIndex > 0,
            canGoNext: transition.fromIndex < model.workspaces.count - 1
        )
        let commits = outcome != .stay && transition.target != nil
        // Past the ends the page doesn't follow the finger 1:1, so the release speed doesn't apply.
        settle(transition, commits: commits, releaseVelocity: transition.target == nil ? 0 : velocity)
    }

    // MARK: - Pages

    /// Starts a transition: the current page goes onto the stage as an image, and
    /// the live page is hidden until the transition lands.
    private func beginSpaceTransition(fromIndex: Int) -> SpaceTransition {
        let transition = SpaceTransition(fromWorkspace: model.workspaces[fromIndex], fromIndex: fromIndex)
        spaceTransition = transition
        // A rename belongs to the space being left (and would show in the images).
        spaceHeader.cancelInlineRename()
        pageStage.begin(outgoing: pageImage(of: workspaceContentStack))
        workspaceContentStack.isHidden = true
        return transition
    }

    /// Puts `target`'s page on the stage, one page to `side`; nil (past an end) shows none.
    private func prepareTarget(of transition: SpaceTransition, target: (Workspace, Int)?, side: CGFloat) {
        transition.side = side
        transition.target = target.map { (workspace: $0.0, index: $0.1) }
        guard let workspace = target?.0 else {
            pageStage.setIncoming(nil, baseX: 0)
            return
        }
        let image = transition.snapshots[workspace.id] ?? renderPageImage(for: workspace)
        transition.snapshots[workspace.id] = image
        pageStage.setIncoming(image, baseX: -side * swipeClipContainer.bounds.width)
        pageStage.setOffset(transition.offset)
    }

    /// Tracking: moves the pages, the colour, the pill and (across profiles) the
    /// Favorites' opacity to `offset` at once.
    private func apply(offset: CGFloat, to transition: SpaceTransition) {
        transition.offset = offset
        let progress = self.progress(of: transition)
        pageStage.setOffset(offset)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        view.layer?.backgroundColor = blendedBackground(transition, progress: progress).cgColor
        CATransaction.commit()
        pinnedTabsView.alphaValue = changesFavorites(transition) ? 1 - progress : 1
        spaceBar.setSelectionProgress(toward: transition.target?.workspace.id, progress: progress)
    }

    /// Whether the target space shows other Favorites (another profile): only then
    /// do they fade with the page; otherwise they stay still.
    private func changesFavorites(_ transition: SpaceTransition) -> Bool {
        guard let target = transition.target?.workspace else { return false }
        return target.profileId != transition.fromWorkspace.profileId
    }

    /// How far the page is toward the target, 0…1 (0 past an end).
    private func progress(of transition: SpaceTransition) -> CGFloat {
        let width = swipeClipContainer.bounds.width
        guard transition.target != nil, width > 0 else { return 0 }
        return min(1, abs(transition.offset) / width)
    }

    private func blendedBackground(_ transition: SpaceTransition, progress: CGFloat) -> NSColor {
        let from = transition.fromWorkspace.backgroundColor
        guard let to = transition.target?.workspace.backgroundColor, progress > 0 else { return from }
        return from.usingColorSpace(.sRGB)?.blended(withFraction: progress, of: to.usingColorSpace(.sRGB) ?? to) ?? to
    }

    // MARK: - Settling

    /// Springs the pages (and colour, pill and Favorites) from where they are to the
    /// target (`commits`) or back. All animations start in one transaction, so they
    /// stay in step.
    private func settle(_ transition: SpaceTransition, commits: Bool, releaseVelocity: CGFloat) {
        transition.phase = .settling(commits: commits)
        if transition.reducesMotion {
            return crossfade(transition, commits: commits)
        }
        let width = swipeClipContainer.bounds.width
        let start = transition.offset
        let end = commits ? transition.side * width : 0
        let spring = SpaceSwipe.Spring.standard
        let initialVelocity = spring.initialVelocity(releaseVelocity: releaseVelocity, remaining: end - start)
        // Land once the pages are visually there, not when the spring has fully
        // stopped: the live page (and another profile's Favorites) come sooner.
        let visualDuration = spring.visualDuration(
            initialVelocity: initialVelocity,
            distance: Double(end - start),
            tolerance: ThemeConstants.SpaceTransition.landingTolerance
        )

        func springAnimation(_ keyPath: String, from: Any, to: Any) -> CASpringAnimation {
            let animation = CASpringAnimation(keyPath: keyPath)
            animation.mass = 1
            animation.stiffness = spring.stiffness
            animation.damping = spring.damping
            animation.initialVelocity = initialVelocity
            animation.fromValue = from
            animation.toValue = to
            animation.duration = min(animation.settlingDuration, max(visualDuration, ThemeConstants.Animation.durationFast))
            return animation
        }

        let startColor = blendedBackground(transition, progress: progress(of: transition))
        let endColor = commits
            ? transition.target?.workspace.backgroundColor ?? startColor
            : transition.fromWorkspace.backgroundColor
        let pillSpaceId = commits ? transition.target?.workspace.id : transition.fromWorkspace.id
        let startAlpha = pinnedTabsView.alphaValue
        // Another profile's Favorites: when its grid is as tall as this one, it goes
        // in now and fades in with the page; otherwise the old grid fades out and the
        // new one fades in on landing (a height change would move the sliding page).
        let targetFavorites = transition.target.map { model.profile(for: $0.workspace).favorites } ?? []
        let currentCount = model.profile(for: transition.fromWorkspace).favorites.count
        let gridWidth = pinnedTabsView.bounds.width
        // An empty grid is hidden by the stack together with its spacing, which
        // can't be animated: those switches keep the fade on landing.
        let swapsFavoritesNow = commits && changesFavorites(transition)
            && (PinnedTabsView.hasSameHeight(tiles: currentCount, tiles: targetFavorites.count, width: gridWidth)
                || (currentCount > 0 && !targetFavorites.isEmpty))
        if swapsFavoritesNow {
            let fromHeight = PinnedTabsView.height(tiles: currentCount, width: gridWidth)
            let toHeight = PinnedTabsView.height(tiles: targetFavorites.count, width: gridWidth)
            if fromHeight != toHeight {
                pinnedTabsView.heightOverride = fromHeight
            }
            pinnedTabsView.update(pinnedLinks: targetFavorites)
            transition.favoritesSwapped = true
            if fromHeight != toHeight {
                animateFavoritesHeight(of: transition, from: fromHeight, to: toHeight,
                                       spring: spring, initialVelocity: initialVelocity, duration: visualDuration)
            }
        }
        let endAlpha: CGFloat = commits && changesFavorites(transition) && !swapsFavoritesNow ? 0 : 1
        // A click or ⌘⌥←/→ has no drag (the old grid is fully shown): the swapped grid
        // fades in from nothing rather than cutting.
        let fromAlpha: CGFloat = swapsFavoritesNow && startAlpha >= 1 ? 0 : startAlpha

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        CATransaction.setCompletionBlock { [weak self, weak transition] in
            guard let self, let transition, self.spaceTransition === transition else { return }
            self.finish(transition)
        }
        // Final values first, then the explicit springs.
        pageStage.setOffset(end)
        for page in [pageStage.outgoing, pageStage.incoming] {
            page.add(springAnimation("transform.translation.x", from: start, to: end), forKey: Self.transitionAnimationKey)
        }
        view.layer?.backgroundColor = endColor.cgColor
        view.layer?.add(springAnimation("backgroundColor", from: startColor.cgColor, to: endColor.cgColor),
                        forKey: Self.transitionAnimationKey)
        if let pillSpaceId {
            spaceBar.settleSelection(
                on: pillSpaceId,
                duration: visualDuration,
                travel: { CGFloat(spring.position(at: $0, initialVelocity: initialVelocity)) }
            ) { keyPath, from, to in
                springAnimation(keyPath, from: from, to: to)
            }
        }
        pinnedTabsView.alphaValue = endAlpha
        if fromAlpha != endAlpha {
            pinnedTabsView.layer?.add(springAnimation("opacity", from: Float(fromAlpha), to: Float(endAlpha)),
                                      forKey: Self.transitionAnimationKey)
        }
        CATransaction.commit()
        transition.offset = end
    }

    /// Reduce Motion: the target's page fades in over the current one in place;
    /// the colour (and another profile's Favorites) fade with it; the pill moves on landing.
    private func crossfade(_ transition: SpaceTransition, commits: Bool) {
        guard commits, let target = transition.target?.workspace else {
            return finish(transition)
        }
        func fade(_ keyPath: String, from: Any, to: Any) -> CABasicAnimation {
            let animation = CABasicAnimation(keyPath: keyPath)
            animation.fromValue = from
            animation.toValue = to
            animation.duration = ThemeConstants.Animation.durationNormal
            animation.timingFunction = ThemeConstants.Animation.timingFunction
            return animation
        }

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        CATransaction.setCompletionBlock { [weak self, weak transition] in
            guard let self, let transition, self.spaceTransition === transition else { return }
            self.finish(transition)
        }
        // In place, over the current page.
        pageStage.setIncoming(transition.snapshots[target.id], baseX: 0)
        pageStage.setOffset(0)
        pageStage.incoming.add(fade("opacity", from: 0, to: 1), forKey: Self.transitionAnimationKey)
        // Both images are transparent around the rows: fade the old one out too, or
        // its extra rows would show under a shorter new list.
        pageStage.outgoing.opacity = 0
        pageStage.outgoing.add(fade("opacity", from: 1, to: 0), forKey: Self.transitionAnimationKey)

        let startColor = transition.fromWorkspace.backgroundColor
        let endColor = target.backgroundColor
        view.layer?.backgroundColor = endColor.cgColor
        view.layer?.add(fade("backgroundColor", from: startColor.cgColor, to: endColor.cgColor), forKey: Self.transitionAnimationKey)

        if changesFavorites(transition) {
            pinnedTabsView.alphaValue = 0
            pinnedTabsView.layer?.add(fade("opacity", from: Float(1), to: Float(0)), forKey: Self.transitionAnimationKey)
        }
        CATransaction.commit()
    }

    /// The Favorites' height follows the pages' spring (same curve and start speed),
    /// so the page below glides to its new place instead of jumping on landing.
    /// Layout can't ride a Core Animation spring, so a timer sets each frame.
    private func animateFavoritesHeight(
        of transition: SpaceTransition,
        from: CGFloat,
        to: CGFloat,
        spring: SpaceSwipe.Spring,
        initialVelocity: Double,
        duration: TimeInterval
    ) {
        let start = CACurrentMediaTime()
        let timer = Timer(timeInterval: ThemeConstants.SpaceTransition.layoutFrameInterval, repeats: true) { [weak self, weak transition] timer in
            // Timers on the main run loop fire on the main thread.
            let done = MainActor.assumeIsolated { () -> Bool in
                guard let self, let transition, self.spaceTransition === transition else { return true }
                let elapsed = CACurrentMediaTime() - start
                let fraction = elapsed >= duration ? 1 : spring.position(at: elapsed, initialVelocity: initialVelocity)
                self.pinnedTabsView.heightOverride = from + (to - from) * CGFloat(fraction)
                self.view.layoutSubtreeIfNeeded()
                return elapsed >= duration
            }
            if done {
                timer.invalidate()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        transition.favoritesHeightTimer = timer
    }

    // MARK: - Landing

    /// Lands the current transition immediately (a new click or gesture arrived):
    /// a settle jumps to its end, a drag still being tracked goes back.
    func finishSpaceTransitionNow() {
        guard let transition = spaceTransition else { return }
        if case .tracking = transition.phase {
            transition.phase = .settling(commits: false)
        }
        finish(transition)
    }

    /// The stage shows the landed page (the target's, or the current one after a
    /// cancel). The live page is updated and drawn underneath it while still covered,
    /// and only then does the stage fade away, so nothing flashes.
    private func finish(_ transition: SpaceTransition) {
        let commits: Bool
        if case .settling(let value) = transition.phase { commits = value } else { commits = false }

        pageStage.removeAllPageAnimations()
        transition.favoritesHeightTimer?.invalidate()
        transition.favoritesHeightTimer = nil
        pinnedTabsView.heightOverride = nil
        // Cut short (a click, a new gesture): the pages jump to where they were going.
        pageStage.setOffset(commits && !transition.reducesMotion ? transition.side * swipeClipContainer.bounds.width : 0)
        view.layer?.removeAnimation(forKey: Self.transitionAnimationKey)
        // A drag landed mid-way (no settle) was left with a blended colour.
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let landedColor = commits
            ? transition.target?.workspace.backgroundColor ?? transition.fromWorkspace.backgroundColor
            : transition.fromWorkspace.backgroundColor
        view.layer?.backgroundColor = landedColor.cgColor
        CATransaction.commit()
        pinnedTabsView.layer?.removeAnimation(forKey: Self.transitionAnimationKey)
        spaceBar.endSelectionTransition()
        let fadeInFavorites = commits && changesFavorites(transition) && !transition.favoritesSwapped

        // Unless something else changed the selection meanwhile (a new space, the
        // agent API): that change wins. Still "in transition" here, so the
        // selection's own reload is held rather than run twice.
        if commits, let target = transition.target, model.currentWorkspace.id == transition.fromWorkspace.id {
            model.selectWorkspace(id: target.workspace.id)
        }
        spaceTransition = nil
        if commits || reloadHeldByTransition {
            reloadHeldByTransition = false
            // The stage covers the page; no list animation underneath it.
            suppressNodeAnimations = true
            reloadData()
            suppressNodeAnimations = false
        }
        if commits {
            // The new space's image showed it from the top; land there too.
            let clipView = nodeListViewController.scrollView.contentView
            clipView.scroll(to: .zero)
            nodeListViewController.scrollView.reflectScrolledClipView(clipView)
        }

        pinnedTabsView.alphaValue = 1
        if fadeInFavorites {
            // The new profile's grid (possibly another height) is in place: fade it in.
            pinnedTabsView.layer?.add(Self.fade(from: 0, to: 1), forKey: Self.transitionAnimationKey)
        }

        workspaceContentStack.isHidden = false
        view.layoutSubtreeIfNeeded()
        view.displayIfNeeded()
        // Next turn of the run loop the live page is on screen under the stage.
        let generation = pageStage.generation
        DispatchQueue.main.async { [weak self] in
            guard let self, self.spaceTransition == nil, self.pageStage.generation == generation else { return }
            self.pageStage.fadeOut(duration: ThemeConstants.Animation.durationFast)
        }
    }

    private static func fade(from: Float, to: Float) -> CABasicAnimation {
        let animation = CABasicAnimation(keyPath: "opacity")
        animation.fromValue = from
        animation.toValue = to
        animation.duration = ThemeConstants.Animation.durationFast
        animation.timingFunction = CAMediaTimingFunction(name: .easeOut)
        return animation
    }

    // MARK: - Page images

    /// The page (header, scheduled links, list, bottom row) as it is drawn now.
    private func pageImage(of page: NSView) -> NSImage? {
        let bounds = page.bounds
        guard let bitmap = page.bitmapImageRepForCachingDisplay(in: bounds) else { return nil }
        page.cacheDisplay(in: bounds, to: bitmap)
        let image = NSImage(size: bounds.size)
        image.addRepresentation(bitmap)
        return image
    }

    /// `workspace`'s page, rendered in the real (hidden) content views from the top
    /// and then restored. The model is not touched.
    private func renderPageImage(for workspace: Workspace) -> NSImage? {
        let started = CACurrentMediaTime()
        let current = model.currentWorkspace
        let clipView = nodeListViewController.scrollView.contentView
        let savedScroll = clipView.bounds.origin
        // Hidden views don't draw into a bitmap; nothing is displayed in between.
        let wasHidden = workspaceContentStack.isHidden
        workspaceContentStack.isHidden = false
        defer { workspaceContentStack.isHidden = wasHidden }

        renderSpaceContent(workspace)
        clipView.scroll(to: .zero)
        workspaceContentStack.layoutSubtreeIfNeeded()
        let image = pageImage(of: workspaceContentStack)

        renderSpaceContent(current)
        workspaceContentStack.layoutSubtreeIfNeeded()
        clipView.scroll(to: savedScroll)
        nodeListViewController.scrollView.reflectScrolledClipView(clipView)

        let milliseconds = (CACurrentMediaTime() - started) * 1000
        let rows = workspace.items.count
        Self.transitionLogger.debug("snapshot of a space with \(rows, privacy: .public) top-level items took \(milliseconds, format: .fixed(precision: 1), privacy: .public) ms")
        return image
    }

    /// Shows `workspace`'s page content in the content views (what `reloadData`
    /// shows for the current space), without animation.
    private func renderSpaceContent(_ workspace: Workspace) {
        let searching = searchCoordinator.isSearchActive
        configureSpaceHeader(for: workspace)
        if searching {
            scheduledLinksAccordion.isHidden = true
        } else {
            scheduledLinksAccordion.update(entries: model.scheduledLinks(in: workspace.id))
        }
        nodeListViewController.workspaceBackgroundColor = workspace.backgroundColor
        let items = searching ? workspace.items : ScheduledLinkFiltering.hideScheduled(workspace.items)
        nodeListViewController.reloadData(with: searchCoordinator.filter(nodes: items), forceExpand: searching, animated: false)
    }
}
