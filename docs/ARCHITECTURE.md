# SidebArc Architecture

SidebArc is a macOS bookmark sidebar built with Swift 6 and AppKit (macOS 13+), with no Swift package dependencies (the note editor vendors two JavaScript libraries, listed in `Sources/SidebArcCore/NoteEditor/README.md`). Links, folders and notes live in **spaces**; spaces belong to **profiles**, which share a browser setup and the **Favorites** grid. This page is the map; the details are linked from each section.

| Topic | File |
|---|---|
| Rules most tasks need | [CLAUDE.md](../CLAUDE.md) |
| Data flow, data model, schema versions, mutation pattern, node tree operations, list updates, search | [INTERNALS.md](INTERNALS.md) |
| Profiles, Favorites, browser routing, Arc import mapping, agent API | [PROFILES_AND_BROWSERS.md](PROFILES_AND_BROWSERS.md) |
| Switching to open tabs | [TAB_FOCUS.md](TAB_FOCUS.md) |
| Space layout, space bar, header, Settings, transitions | [SPACES.md](SPACES.md) |
| Base classes, `ThemeConstants`, component patterns | [COMPONENT_USAGE_GUIDE.md](COMPONENT_USAGE_GUIDE.md) |
| Arc and Chrome import formats | [ARC_IMPORT_ARCHITECTURE.md](ARC_IMPORT_ARCHITECTURE.md), [CHROME_IMPORT_ARCHITECTURE.md](CHROME_IMPORT_ARCHITECTURE.md) |
| Build, signing, release | [BUILD_AND_CODESIGN.md](BUILD_AND_CODESIGN.md), [DISTRIBUTION.md](DISTRIBUTION.md) |
| Refactoring of the upstream code (2026-02-10, historical) | [REFACTORING_PLAN.md](REFACTORING_PLAN.md) |

## Data flow

```
User action → view / view controller → AppModel method → AppState → DataStore → data.json
                     ↑                                                    │
                     └──────────────── onChange callback ─────────────────┘
```

- **`AppModel`** owns `AppState` and is the single source of truth. Every mutation is an `AppModel` method, which persists through `DataStore` and calls `onChange`.
- **`DataStore`** reads and writes `data.json` in the data directory, keeps rotating backups and the `Icons/` and `Notes/` folders.
- **UI** observes `onChange` and never mutates state.

The model (`AppState` → `Profile`, `Workspace` → `Node`) and schema migration are in [INTERNALS.md › Core Data Model](INTERNALS.md#core-data-model).

## Targets

| Target | Role |
|---|---|
| `SidebArcCore` | Library with all app logic and UI |
| `SidebArcApp` | Executable entry point (`main.swift`); the bundle's product is `sidebarc` |
| `SidebArcTests` | swift-testing suites |

## Project structure

`Sources/SidebArcCore/`, grouped by role (the folders on disk are only partly grouped: many files sit at the top level).

| Area | Files |
|---|---|
| App and state | `AppDelegate` (window, menus, hotkey, attachment wiring), `AppModel`, `DataStore`, `Models` (`AppState`, `Profile`, `Workspace`, `Node`, `Link`, `Folder`, `Note`, `CustomIcon`), `Persistence/SchemaMigration` (`SchemaVersionProbe`, `SchemaV1`, `v1ToV2`), `Persistence/DataTransfer` (export and import), `Constants` (`AppIdentity`), `WorkspaceColor`, `SidebarPosition`, `KeyboardShortcut` |
| View controllers | `MainViewController` (~1000 lines: layout, model binding, menus) and `MainViewController+SpaceTransition` (~450), `ViewControllers/NodeListViewController` (~1300: list, drag and drop, context menus), `ViewControllers/SearchCoordinator`, `ViewControllers/SidebarBackdropViewController` (window root: behind-window blur under the main view), `SettingsContentViewController` (~1600) |
| List | `NodeCollectionViewItem`, `NodeRowView`, `ListFlowLayout`, `NodeFiltering`, `ScheduledLinkFiltering`, `Components/ScheduledLinksAccordion/` |
| Components | `Components/Base/` (`BaseControl`, `BaseView`, `InlineEditableTextField`, `DropIndicatorView`, `FlippedContentView`), `Components/Spaces/` (`SpaceBarView`, `SpaceBarLayout`, `SpaceBarScroll`, `SpaceHeaderView`, `SpaceIconView`, `SpacePageStage`, `SpaceColorPanel`), `Components/PinnedTabs/` (Favorites grid), `Components/Menus/` (`SpaceMenu`, `BrowserMenus`), `Components/Settings/` (`ProfileSettingsView`, `AutomationPermissionView`, `WorkspaceContextMenuCollectionView`), `Components/IconPicker/`, `Components/Buttons/`, `Components/Inputs/ShortcutRecorderView`, `Components/Tooltip/`; at the top level `IconTitleButton`, `CustomToggle`, `SearchBarView`, `SidebarPositionSelector`, `WorkspaceCollectionViewItem`, `WorkspaceRowView` |
| Browsers and tabs | `BrowserManager` (`resolveTarget`, opening, profile detection), `Services/TabFocus`, `Services/TabFocusService`, `Services/TabLocator`, `Utilities/TabURLMatcher`, `Utilities/URLNormalization` |
| Services | `FaviconService`, `LinkTitleService`, `WindowAttachmentService` (follows the frontmost profile browser's window over Accessibility), `GlobalHotkeyService`, `SwipeGestureService`, `Services/SchedulerService`, `Services/SchedulePresets`, `ArcImportService`, `ChromeImportService` |
| Notes | `Notes/NoteStorage` (`Notes/*.md`), `Notes/NoteServer` (token-authenticated loopback HTTP server for the note editor and the agent API), `NoteEditor/` (the editor's HTML/JS, copied into the bundle's resources) |
| Utilities | `Utilities/Theme/ThemeConstants`, `Utilities/ClosureMenuItem`, `Utilities/SpaceSwipe`, `Utilities/WindowPlacement` |

## Key design decisions

- **State:** all mutations through `AppModel`; persistence is automatic (callers never call `save()`); `notify: false` suppresses `onChange`; tree edits are recursive (`insertNode`, `updateNode`, `removeNode`, `findNodeLocation`).
- **Schema:** new fields on synthesized-Codable models are `Optional`; anything else gets a `SchemaVn` mirror and a migration. Migrations never drop links (`Profile.appendFavorites` + a leftovers folder).
- **UI:** controls extend `BaseControl`, hover-only views `BaseView`; every colour, size and duration comes from `ThemeConstants`; list updates are diffed and animated; inline renames are scheduled with `pendingInlineRenameId` and run after the reload.
- **Browsers:** where a link opens is decided in one place (`BrowserManager.resolveTarget`); browsers launch through LaunchServices, never as child processes; tab focus uses raw Apple Events by pid, never `NSAppleScript` or `osascript`.
- **Spaces:** navigation goes through `requestSpaceSwitch(to:)`; views are never moved through their layer `transform`. A space's colours are read through `Workspace.color` / `Workspace.backgroundColor` and painted once, on `MainViewController`'s layer, over the backdrop blur.

## Testing

All tests use swift-testing (`import Testing`; XCTest isn't available with Command Line Tools only). Model operations are tested through `AppModel` with a temporary `DataStore`, checking the mutation and the JSON round trip; pure logic (`TabURLMatcher`, `SpaceSwipe`, `SchemaMigration`, `WindowAttachmentService.cocoaFrame`) is tested directly; layout bugs get off-screen probe tests (`InlineRenameLayoutTests`, `PinnedTabsLayoutTests`). Opt-in acceptance tests run against copies of real files (`SIDEBARC_V1_FIXTURE`, `SIDEBARC_ARC_FIXTURE`, `SIDEBARC_TAB_PROBE`). Commands and rules: [CLAUDE.md › Testing](../CLAUDE.md#testing).

## Build

swift-bundler (pinned in `Mintfile`, run through Mint) builds the app bundle from `Bundler.toml`; the scripts in `scripts/` add signing, Info.plist patches and the DMG. See [BUILD_AND_CODESIGN.md](BUILD_AND_CODESIGN.md).
