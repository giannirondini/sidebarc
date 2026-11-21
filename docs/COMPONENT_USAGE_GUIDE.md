# Component Usage Guide

This guide provides practical examples for using SidebArc's base classes and design system components.

## Table of Contents
1. [Overview](#overview)
2. [ThemeConstants](#themeconstants)
3. [BaseControl](#basecontrol)
4. [BaseView](#baseview)
5. [InlineEditableTextField](#inlineeditabletextfield)
6. [Space Components](#space-components)
7. [Menu Builders](#menu-builders)
8. [Common Patterns](#common-patterns)

---

## Overview

_Moved from CLAUDE.md › "UI Component Architecture (Post-Refactoring)" on 2026-11-15._

**Base Classes** (located in `Components/Base/`):
- **BaseControl** - Base class for all interactive controls with hover and pressed state management
  - Owns the tracking area and mouse events; refreshes the hover state on layout and window changes
  - Provides `handleHoverStateChanged()` and `handlePressedStateChanged()` override points
  - Used by: `IconTitleButton`, `CustomToggle`, `SpaceBarButton`, `PinnedTabTileView`, `IconPickerItemView`, `ScheduledLinkRowView`, the scheduled-links `HeaderButton`
- **BaseView** - Base class for custom views with hover state management (no pressed state)
  - Simpler than BaseControl, designed for non-interactive views like rows
  - Used by: `NodeRowView`, `WorkspaceRowView`, `SpaceHeaderView`, the shortcut recorder's `RecorderBoxView`
- **InlineEditableTextField** - Reusable component for inline text editing
  - Encapsulates commit/cancel logic, focus management, and callbacks
  - Used by: `NodeRowView`, `WorkspaceRowView`, `SpaceHeaderView`

**Design System** (located in `Utilities/Theme/`):
- **ThemeConstants** - Centralized design system constants
  - Colors: Brand colors and semantic values (darkGray, white, settingsBackground)
  - Opacity: Standard opacity levels (full, high, medium, low, subtle, extraSubtle, minimal)
  - Fonts: Typography styles (bodyRegular, bodySemibold, bodyMedium, bodyBold)
  - Spacing: Layout spacing values (tiny=4, small=6, medium=8, regular=10, large=14, extraLarge=16, huge=20)
  - CornerRadius: Rounding values (small=6, medium=8, large=12)
  - Sizing: Standard sizes (iconSmall=14, iconMedium=18, iconLarge=22, iconExtraLarge=26, buttonHeight=32; list rows use `ListMetrics.rowHeight`), Favorites grid (`pinnedTileHeight`, `pinnedTileMinWidth`, `pinnedTileMinColumns`, `pinnedTileSpacing`) and space bar (`spaceBarHeight`, `spaceBarButtonSize`, `spaceBarCompactSlotWidth`, `spaceBarDotSize`, `spaceBarEdgeDotMinSize`, `spaceBarEdgeDotRamp`)
  - Animation: Timing values (durationFast=0.15s, durationNormal=0.2s, durationSlow=0.3s)
  - SpaceTransition: space-switch tuning (commit fraction, flick velocity, velocity window, rubber band, spring response and damping ratio)

**Component Patterns**:
All interactive controls extend BaseControl or BaseView and use ThemeConstants for consistency:

```swift
// Example: Custom button extending BaseControl
final class MyButton: BaseControl {
    override func handleHoverStateChanged() {
        layer?.backgroundColor = isHovered
            ? ThemeConstants.Colors.darkGray.withAlphaComponent(ThemeConstants.Opacity.minimal).cgColor
            : NSColor.clear.cgColor
    }

    override func handlePressedStateChanged() {
        layer?.backgroundColor = isPressed
            ? ThemeConstants.Colors.darkGray.withAlphaComponent(ThemeConstants.Opacity.subtle).cgColor
            : NSColor.clear.cgColor
    }
}
```

---

## ThemeConstants

`ThemeConstants` provides a centralized design system for consistent styling across the application.

### Basic Usage

```swift
import AppKit

// Using colors
layer?.backgroundColor = ThemeConstants.Colors.darkGray.cgColor

// Using colors with opacity
let hoverColor = ThemeConstants.Colors.darkGray
    .withAlphaComponent(ThemeConstants.Opacity.minimal)

// Using fonts
label.font = ThemeConstants.Fonts.bodyRegular
titleLabel.font = ThemeConstants.Fonts.bodySemibold

// Using spacing
stackView.spacing = ThemeConstants.Spacing.regular
view.layoutMargins = NSEdgeInsets(
    top: ThemeConstants.Spacing.large,
    left: ThemeConstants.Spacing.extraLarge,
    bottom: ThemeConstants.Spacing.large,
    right: ThemeConstants.Spacing.extraLarge
)

// Using corner radius
layer?.cornerRadius = ThemeConstants.CornerRadius.medium

// Using sizing
imageView.frame.size = CGSize(
    width: ThemeConstants.Sizing.iconMedium,
    height: ThemeConstants.Sizing.iconMedium
)

// Using animation values
CATransaction.begin()
CATransaction.setAnimationDuration(ThemeConstants.Animation.durationFast)
CATransaction.setAnimationTimingFunction(ThemeConstants.Animation.timingFunction)
layer?.opacity = 0.5
CATransaction.commit()
```

### Creating Custom Fonts

```swift
// For custom sizes while maintaining consistency
let largeTitle = ThemeConstants.Fonts.systemFont(size: 18, weight: .semibold)
let smallCaption = ThemeConstants.Fonts.systemFont(size: 12, weight: .regular)
```

### Opacity Levels Quick Reference

```swift
// Full opacity - No transparency
ThemeConstants.Opacity.full        // 1.0

// High opacity - Primary content with slight transparency
ThemeConstants.Opacity.high         // 0.8

// Medium opacity - Secondary content
ThemeConstants.Opacity.medium       // 0.6

// Low opacity - Tertiary content or disabled states
ThemeConstants.Opacity.low          // 0.4

// Subtle opacity - Selected or focused backgrounds
ThemeConstants.Opacity.subtle       // 0.15

// Extra subtle - Very light backgrounds
ThemeConstants.Opacity.extraSubtle  // 0.10

// Minimal - Hover states with barely visible tint
ThemeConstants.Opacity.minimal      // 0.06
```

---

## BaseControl

`BaseControl` is a base class for interactive controls (buttons, toggles) with automatic hover and pressed state management.

### Creating a Custom Button

```swift
import AppKit

final class MyCustomButton: BaseControl {

    private let titleLabel = NSTextField(labelWithString: "")
    private let iconView = NSImageView()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupUI()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupUI()
    }

    private func setupUI() {
        // Setup your subviews
        titleLabel.font = ThemeConstants.Fonts.bodyMedium
        titleLabel.textColor = ThemeConstants.Colors.white

        addSubview(iconView)
        addSubview(titleLabel)

        // ... layout code

        updateAppearance()
    }

    // Override to respond to hover state changes
    override func handleHoverStateChanged() {
        updateAppearance()
    }

    // Override to respond to pressed state changes
    override func handlePressedStateChanged() {
        updateAppearance()
    }

    private func updateAppearance() {
        let backgroundOpacity: CGFloat
        let textOpacity: CGFloat

        if isPressed {
            backgroundOpacity = ThemeConstants.Opacity.subtle
            textOpacity = ThemeConstants.Opacity.high
        } else if isHovered {
            backgroundOpacity = ThemeConstants.Opacity.minimal
            textOpacity = ThemeConstants.Opacity.full
        } else {
            backgroundOpacity = 0
            textOpacity = ThemeConstants.Opacity.high
        }

        CATransaction.begin()
        CATransaction.setAnimationDuration(ThemeConstants.Animation.durationFast)
        CATransaction.setAnimationTimingFunction(ThemeConstants.Animation.timingFunction)

        layer?.backgroundColor = ThemeConstants.Colors.darkGray
            .withAlphaComponent(backgroundOpacity).cgColor
        titleLabel.alphaValue = textOpacity

        CATransaction.commit()
    }

    // Optional: Override to customize action behavior
    override func performAction() {
        // Custom action logic
        print("Button clicked!")

        // Still send the action to target
        super.performAction()
    }
}
```

### Using the Custom Button

```swift
let button = MyCustomButton(frame: .zero)
button.target = self
button.action = #selector(handleButtonClick)

// BaseControl automatically handles:
// - Hover state detection
// - Pressed state tracking
// - Mouse event handling
// - Tracking area management
```

---

## BaseView

`BaseView` is a base class for non-interactive custom views that need hover state detection (like row views in lists).

### Creating a Custom Row View

```swift
import AppKit

final class MyCustomRow: BaseView {

    private let titleLabel = NSTextField(labelWithString: "")
    private let subtitleLabel = NSTextField(labelWithString: "")
    private var isSelected = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupUI()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupUI()
    }

    private func setupUI() {
        titleLabel.font = ThemeConstants.Fonts.bodyMedium
        titleLabel.textColor = ThemeConstants.Colors.darkGray

        subtitleLabel.font = ThemeConstants.Fonts.bodyRegular
        subtitleLabel.textColor = ThemeConstants.Colors.darkGray
            .withAlphaComponent(ThemeConstants.Opacity.medium)

        addSubview(titleLabel)
        addSubview(subtitleLabel)

        // ... layout code

        updateVisualState()
    }

    // Override to respond to hover state changes
    override func handleHoverStateChanged() {
        updateVisualState()
    }

    func setSelected(_ selected: Bool) {
        guard isSelected != selected else { return }
        isSelected = selected
        updateVisualState()
    }

    private func updateVisualState() {
        let backgroundColor: NSColor

        if isSelected {
            backgroundColor = ThemeConstants.Colors.darkGray
                .withAlphaComponent(ThemeConstants.Opacity.subtle)
        } else if isHovered {
            backgroundColor = ThemeConstants.Colors.darkGray
                .withAlphaComponent(ThemeConstants.Opacity.minimal)
        } else {
            backgroundColor = .clear
        }

        CATransaction.begin()
        CATransaction.setAnimationDuration(ThemeConstants.Animation.durationFast)
        layer?.backgroundColor = backgroundColor.cgColor
        CATransaction.commit()
    }
}
```

### BaseView vs BaseControl - When to Use Which?

**Use BaseControl when:**
- Creating interactive controls (buttons, toggles, sliders)
- Need both hover AND pressed state tracking
- Want automatic mouse tracking loop
- Control should perform an action on click

**Use BaseView when:**
- Creating non-interactive views (row views, cards, containers)
- Only need hover state detection (no pressed state)
- View doesn't perform actions directly
- Simpler than BaseControl for display-only components

---

## InlineEditableTextField

`InlineEditableTextField` provides reusable inline text editing with commit/cancel functionality.

### Basic Usage

```swift
import AppKit

final class MyEditableCard: NSView {

    private let editableTitle = InlineEditableTextField()
    private let editButton = NSButton()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupUI()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupUI()
    }

    private func setupUI() {
        // Configure the editable text field
        editableTitle.text = "Initial Title"
        editableTitle.font = ThemeConstants.Fonts.bodyMedium
        editableTitle.textColor = ThemeConstants.Colors.darkGray

        addSubview(editableTitle)
        addSubview(editButton)

        editButton.target = self
        editButton.action = #selector(startEditing)

        // ... layout code
    }

    @objc private func startEditing() {
        editableTitle.beginInlineRename(
            onCommit: { [weak self] newText in
                // User pressed Enter with valid text
                self?.handleTitleChanged(newText)
            },
            onCancel: { [weak self] in
                // User pressed Escape or focus was lost
                print("Edit canceled")
            }
        )
    }

    private func handleTitleChanged(_ newTitle: String) {
        print("Title changed to: \(newTitle)")
        // Update your model, persist changes, etc.
    }
}
```

### Integration with Row Views

```swift
final class EditableRowView: BaseView {

    private let editableTitle = InlineEditableTextField()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupUI()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupUI()
    }

    private func setupUI() {
        editableTitle.font = ThemeConstants.Fonts.bodyRegular
        editableTitle.textColor = ThemeConstants.Colors.white
        addSubview(editableTitle)

        // ... layout code
    }

    // Public method to trigger inline editing
    func beginRename(currentTitle: String, onCommit: @escaping (String) -> Void) {
        editableTitle.text = currentTitle
        editableTitle.beginInlineRename(
            onCommit: onCommit,
            onCancel: {
                print("Rename canceled")
            }
        )
    }

    // Public method to check if currently editing
    var isEditing: Bool {
        editableTitle.isEditing
    }

    // Public method to programmatically cancel editing
    func cancelEditing() {
        editableTitle.cancelInlineRename()
    }
}
```

### Edit Behavior Details

**Commit triggers (calls onCommit):**
- User presses Enter key
- Text is non-empty after trimming whitespace

**Cancel triggers (calls onCancel):**
- User presses Escape key
- Text field loses focus (click outside)
- Text is empty after trimming whitespace

**Automatic features:**
- Text is selected when editing begins
- Original text is restored on cancel
- Whitespace is trimmed on commit
- Focus management is automatic

---

## Space Components

The space UI lives in `Components/Spaces/`. All three take data, never the
`AppModel`; `MainViewController` wires their callbacks to model calls.

### SpaceIconView

A space's emoji or SF Symbol (`Workspace.icon`), or a dot in its colour when it has none.
Use it anywhere a space is shown, so icons look the same everywhere.

```swift
let iconView = SpaceIconView()
iconView.iconSize = ThemeConstants.Sizing.iconMedium   // emoji/symbol size
iconView.dotSize = ThemeConstants.Sizing.iconSmall     // colour dot diameter
iconView.configure(icon: workspace.icon, color: workspace.color)   // never colorId.color: a custom colour wins

// Just the image (e.g. for an NSImageView in an existing row):
let image = SpaceIconView.image(for: .emoji("🚀"), size: ThemeConstants.Sizing.iconMedium)
```

### SpaceBarView

The bottom bar: gear, one button per space, `+`. Feed it the whole list on every reload;
it rebuilds buttons only when the items change, and keeps the selected one scrolled into view.
When every icon doesn't fit, it goes compact on its own (selected icon, dots for the rest;
geometry in `SpaceBarLayout`).

```swift
spaceBar.update(
    items: model.workspaces.map { SpaceBarView.Item(id: $0.id, name: $0.name, icon: $0.icon, color: $0.color) },
    selectedId: model.currentWorkspace.id,
    isSettingsShown: model.isSettingsShown
)
spaceBar.onSpaceSelected = { id in /* requestSpaceSwitch(to: id) */ }
spaceBar.onSpaceContextMenu = { id, event in /* SpaceMenu, anchored to spaceBar.buttonView(for: id) */ }
spaceBar.onAddSpace = { /* create a space */ }
spaceBar.onSettings = { /* toggle Settings */ }
```

- Register it with `SwipeGestureService.shared.addExcludedView(spaceBar)`, so a horizontal
  scroll over it scrolls the bar instead of switching spaces.
- The selection is a separate pill view. During a space transition, drive it with
  `setSelectionProgress(toward:progress:)` while tracking and
  `settleSelection(on:duration:travel:animation:)` inside the transition's `CATransaction`
  (`animation` slides the pill in full mode; `travel`, the pages' spring curve, drives the
  compact slots' resize until `duration`); call `endSelectionTransition()` when it lands.
- `SpaceBarButton` (a `BaseControl`) is the button used for all three kinds; its content is
  dimmed unless selected or hovered. A space button's `expansion` (set by the bar's layout)
  crossfades its icon (1) with the compact bar's dot (0).

### SpaceHeaderView

The current space's icon and name between the Favorites and the pinned list. It uses
`ListMetrics`, so its icon and title line up with a top-level row of the list.

```swift
spaceHeader.configure(name: workspace.name, icon: workspace.icon, color: workspace.color)
spaceHeader.onRename = { newName in /* model.renameWorkspace */ }        // after a double-click
spaceHeader.onIconClicked = { anchor in /* icon picker, kind .space */ }
spaceHeader.onContextMenu = { event in /* SpaceMenu */ }
spaceHeader.beginInlineRename()                                          // from a menu or a new space
```

`configure` never touches the title while it is being edited (the text field returns the
live typed value), so a reload mid-rename can't end it. Switching spaces cancels a rename.

### IconTitleButton `.listRow`

A dimmed "+ Title" row that reads as the last row of a list (Arc's "New Tab" row): the
icon sits in the list's icon column, the title where link titles start, and it is as tall
as a list row. All of it is derived from `ListMetrics`.

```swift
let row = IconTitleButton(title: "Add from Clipboard", symbolName: "plus", style: .listRow)
```

---

## Menu Builders

Context menus are built by small enums that only build items (`BrowserMenus`, `SpaceMenu`);
every action is a closure supplied by the caller, which makes the `AppModel` call.

```swift
let menu = SpaceMenu.build(
    workspace: workspace,
    canDelete: model.workspaces.count > 1,
    profileItem: profileMenuItem(for: workspace),
    actions: SpaceMenu.Actions(
        rename: { /* … */ },
        changeIcon: { /* … */ },
        setColor: { colorId in model.updateWorkspaceColor(id: workspace.id, colorId: colorId) },
        customColor: {                                  // "Custom Color…": the colour panel
            SpaceColorPanel.shared.edit(workspace) { id, color in model.setWorkspaceCustomColor(id: id, color: color) }
        },
        moveLeft: index > 0 ? { /* … */ } : nil,      // nil hides the item
        moveRight: nil,
        delete: { /* confirm, then delete */ }
    )
)
```

Rules:

1. **Use `ClosureMenuItem`** for closure actions. Never name an `@objc` action method
   `perform(_:)`: `#selector` resolves to NSObject's `performSelector:`, AppKit swallows the
   exception, and the item silently does nothing.
2. **Capture the id** of the thing the menu is for. Don't act on "the current" space or
   link: opening a menu must not change the selection.
3. **Set `menu.autoenablesItems = false`** when an item can be disabled; otherwise AppKit
   re-enables every item whose target responds to its action.
4. **Test the dispatch**: build the menu, call `menu.performActionForItem(at:)` and check the
   closure ran (see `ClosureMenuItemTests`, `SpaceMenuTests`). A menu that only renders is
   not tested.

---

## Common Patterns

### Pattern 1: Hover State with Animation

```swift
override func handleHoverStateChanged() {
    CATransaction.begin()
    CATransaction.setAnimationDuration(ThemeConstants.Animation.durationFast)
    CATransaction.setAnimationTimingFunction(ThemeConstants.Animation.timingFunction)

    if isHovered {
        layer?.backgroundColor = ThemeConstants.Colors.darkGray
            .withAlphaComponent(ThemeConstants.Opacity.minimal).cgColor
    } else {
        layer?.backgroundColor = NSColor.clear.cgColor
    }

    CATransaction.commit()
}
```

### Pattern 2: Multi-State Appearance (Pressed, Hovered, Default)

```swift
private func updateAppearance() {
    let opacity: CGFloat

    if isPressed {
        opacity = ThemeConstants.Opacity.subtle
    } else if isHovered {
        opacity = ThemeConstants.Opacity.minimal
    } else {
        opacity = 0
    }

    CATransaction.begin()
    CATransaction.setAnimationDuration(ThemeConstants.Animation.durationFast)
    layer?.backgroundColor = ThemeConstants.Colors.darkGray
        .withAlphaComponent(opacity).cgColor
    CATransaction.commit()
}
```

### Pattern 3: Custom Style Struct with ThemeConstants

```swift
struct MyButtonStyle {
    let backgroundColor: NSColor
    let textColor: NSColor
    let hoverOpacity: CGFloat
    let pressedOpacity: CGFloat

    static let primary = MyButtonStyle(
        backgroundColor: ThemeConstants.Colors.darkGray,
        textColor: ThemeConstants.Colors.white,
        hoverOpacity: ThemeConstants.Opacity.minimal,
        pressedOpacity: ThemeConstants.Opacity.subtle
    )

    static let secondary = MyButtonStyle(
        backgroundColor: ThemeConstants.Colors.settingsBackground,
        textColor: ThemeConstants.Colors.darkGray,
        hoverOpacity: ThemeConstants.Opacity.extraSubtle,
        pressedOpacity: ThemeConstants.Opacity.subtle
    )
}
```

### Pattern 4: Programmatic Hover State Refresh

```swift
// After dynamically changing view hierarchy or bounds
override func layout() {
    super.layout()
    // BaseControl/BaseView automatically call refreshHoverState()
}

// Manual refresh if needed (e.g., after modal dismissal)
myButton.refreshHoverState()
```

### Pattern 5: Inline Editing with Validation

```swift
func beginRename() {
    editableTextField.beginInlineRename(
        onCommit: { [weak self] newText in
            guard let self = self else { return }

            // Validate the new text
            if self.isValidTitle(newText) {
                self.updateTitle(newText)
            } else {
                self.showValidationError()
                // Optionally start editing again
                self.beginRename()
            }
        },
        onCancel: {
            print("Edit canceled")
        }
    )
}

private func isValidTitle(_ title: String) -> Bool {
    // Your validation logic
    return !title.isEmpty && title.count <= 100
}
```

---

## Best Practices

1. **Always use ThemeConstants** instead of hardcoded values for colors, fonts, spacing, etc.
2. **Prefer BaseControl over manual tracking area setup** for interactive controls
3. **Use BaseView for display-only components** that need hover state
4. **Leverage InlineEditableTextField** instead of reimplementing inline editing
5. **Animate state changes** using ThemeConstants.Animation values for consistency
6. **Use semantic opacity names** (minimal, subtle, etc.) instead of raw numbers
7. **Document custom override behavior** when extending base classes
8. **Keep appearance logic in dedicated methods** (e.g., `updateAppearance()`)

---

## Additional Resources

- See [REFACTORING_PLAN.md](REFACTORING_PLAN.md) for the full refactoring history
- See [ARCHITECTURE.md](ARCHITECTURE.md) and [INTERNALS.md](INTERNALS.md) for the architecture
- Check the source code for `BaseControl`, `BaseView`, and `InlineEditableTextField` for implementation details
- Look at existing components like `IconTitleButton`, `NodeRowView`, and `WorkspaceRowView` for real-world examples
- For the space UI, see `SpaceBarView`, `SpaceHeaderView`, `SpaceIconView` and `SpaceMenu`; for the space switch, [SPACES.md](SPACES.md)
