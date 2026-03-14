# SonoBar Look And Feel Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Deliver a media-first, adaptive/resizable, hybrid-themed visual refresh for SonoBar without changing playback, browse, room, alarm, or sleep-timer behavior.

**Architecture:** Add a lightweight SwiftUI design system (tokens + reusable primitives + layout modes), then migrate existing views incrementally. Keep domain/network logic in `AppState` and `SonoBarKit` unchanged; only touch view-layer behavior where needed for UX feedback and shared async/error presentation.

**Tech Stack:** Swift 5.9, SwiftUI (macOS 14+), AppKit color bridging, XcodeGen (`project.yml`), XCTest via new `SonoBarTests` target, `xcodebuild` for verification.

---

## Implementation Rules

- Use `@superpowers:test-driven-development` for every task.
- Keep changes DRY and YAGNI; avoid speculative abstractions.
- Commit after each task.
- Run `xcodegen generate` whenever `project.yml` changes.
- Use focused test runs (`-only-testing`) during tasks and full build/test at phase boundaries.

---

### Task 1: Add App-Layer Test Harness For UI Helpers

**Files:**
- Modify: `project.yml`
- Create: `SonoBarTests/AdaptiveLayoutTests.swift`
- Create: `SonoBarTests/VisualTokensTests.swift`

**Step 1: Write the failing tests**

```swift
// SonoBarTests/AdaptiveLayoutTests.swift
import XCTest
@testable import SonoBar

final class AdaptiveLayoutTests: XCTestCase {
    func testLayoutModeThresholds() {
        XCTAssertEqual(LayoutMode.forWidth(300), .compact)
        XCTAssertEqual(LayoutMode.forWidth(380), .standard)
        XCTAssertEqual(LayoutMode.forWidth(520), .expanded)
    }
}

// SonoBarTests/VisualTokensTests.swift
import XCTest
@testable import SonoBar

final class VisualTokensTests: XCTestCase {
    func testNowPlayingArtworkSizeByMode() {
        XCTAssertEqual(VisualMetrics.nowPlayingArtworkSize(for: .compact), 180)
        XCTAssertEqual(VisualMetrics.nowPlayingArtworkSize(for: .standard), 220)
        XCTAssertEqual(VisualMetrics.nowPlayingArtworkSize(for: .expanded), 260)
    }
}
```

**Step 2: Run tests to verify they fail**

Run: `xcodegen generate && xcodebuild -project SonoBar.xcodeproj -scheme SonoBar -destination 'platform=macOS' -only-testing:SonoBarTests/AdaptiveLayoutTests test`

Expected: FAIL because test target and symbols are not yet defined.

**Step 3: Add minimal test target scaffolding**

```yaml
# project.yml (add)
  SonoBarTests:
    type: bundle.unit-test
    platform: macOS
    sources:
      - path: SonoBarTests
    dependencies:
      - target: SonoBar
```

**Step 4: Re-run tests**

Run: `xcodegen generate && xcodebuild -project SonoBar.xcodeproj -scheme SonoBar -destination 'platform=macOS' -only-testing:SonoBarTests/AdaptiveLayoutTests test`

Expected: FAIL now on missing `LayoutMode`/`VisualMetrics` (good red state).

**Step 5: Commit**

```bash
git add project.yml SonoBarTests/AdaptiveLayoutTests.swift SonoBarTests/VisualTokensTests.swift SonoBar.xcodeproj
git commit -m "test: add SonoBar app-layer UI helper test harness"
```

---

### Task 2: Implement Adaptive Layout Modes And Popover Sizing

**Files:**
- Create: `SonoBar/Views/DesignSystem/AdaptiveLayout.swift`
- Modify: `SonoBar/Views/PopoverContentView.swift`
- Test: `SonoBarTests/AdaptiveLayoutTests.swift`

**Step 1: Extend failing tests**

```swift
func testPopoverSizingConstraints() {
    let constraints = PopoverSizing.constraints(for: .compact)
    XCTAssertEqual(constraints.minWidth, 320)
    XCTAssertEqual(constraints.defaultWidth, 360)
    XCTAssertEqual(constraints.maxWidth, 620)
}
```

**Step 2: Run test to verify failure**

Run: `xcodebuild -project SonoBar.xcodeproj -scheme SonoBar -destination 'platform=macOS' -only-testing:SonoBarTests/AdaptiveLayoutTests test`

Expected: FAIL with unknown `PopoverSizing` / `LayoutMode`.

**Step 3: Implement minimal adaptive logic and wire shell**

```swift
// SonoBar/Views/DesignSystem/AdaptiveLayout.swift
enum LayoutMode: Equatable {
    case compact, standard, expanded

    static func forWidth(_ width: CGFloat) -> LayoutMode {
        if width < 360 { return .compact }
        if width < 500 { return .standard }
        return .expanded
    }
}

struct PopoverConstraints {
    let minWidth: CGFloat
    let minHeight: CGFloat
    let defaultWidth: CGFloat
    let defaultHeight: CGFloat
    let maxWidth: CGFloat
    let maxHeight: CGFloat
}

enum PopoverSizing {
    static func constraints(for _: LayoutMode) -> PopoverConstraints {
        .init(minWidth: 320, minHeight: 440, defaultWidth: 380, defaultHeight: 560, maxWidth: 620, maxHeight: 760)
    }
}
```

Also update `PopoverContentView` to use adaptive constraints instead of hard-coded `.frame(width: 320, height: 450)`.

**Step 4: Run tests and build**

Run: `xcodebuild -project SonoBar.xcodeproj -scheme SonoBar -destination 'platform=macOS' -only-testing:SonoBarTests/AdaptiveLayoutTests test`

Expected: PASS.

**Step 5: Commit**

```bash
git add SonoBar/Views/DesignSystem/AdaptiveLayout.swift SonoBar/Views/PopoverContentView.swift SonoBarTests/AdaptiveLayoutTests.swift
git commit -m "feat: add adaptive popover sizing and layout modes"
```

---

### Task 3: Add Hybrid Theme Tokens And Shared Metrics

**Files:**
- Create: `SonoBar/Views/DesignSystem/VisualTokens.swift`
- Test: `SonoBarTests/VisualTokensTests.swift`

**Step 1: Expand tests for semantic metrics**

```swift
func testCornerRadiusByMode() {
    XCTAssertEqual(VisualMetrics.cornerRadius(for: .compact), 8)
    XCTAssertEqual(VisualMetrics.cornerRadius(for: .standard), 10)
    XCTAssertEqual(VisualMetrics.cornerRadius(for: .expanded), 12)
}
```

**Step 2: Run tests to verify failure**

Run: `xcodebuild -project SonoBar.xcodeproj -scheme SonoBar -destination 'platform=macOS' -only-testing:SonoBarTests/VisualTokensTests test`

Expected: FAIL due missing `VisualMetrics`.

**Step 3: Implement minimal token layer**

```swift
// SonoBar/Views/DesignSystem/VisualTokens.swift
enum VisualMetrics {
    static func nowPlayingArtworkSize(for mode: LayoutMode) -> CGFloat {
        switch mode { case .compact: 180; case .standard: 220; case .expanded: 260 }
    }

    static func cornerRadius(for mode: LayoutMode) -> CGFloat {
        switch mode { case .compact: 8; case .standard: 10; case .expanded: 12 }
    }
}
```

Add a `Color` extension with semantic surfaces (`surfaceBase`, `surfaceElevated`, `surfaceInteractive`, `mediaAccentMuted`) mapped to system colors + accent blending.

**Step 4: Run tests**

Run: `xcodebuild -project SonoBar.xcodeproj -scheme SonoBar -destination 'platform=macOS' -only-testing:SonoBarTests/VisualTokensTests test`

Expected: PASS.

**Step 5: Commit**

```bash
git add SonoBar/Views/DesignSystem/VisualTokens.swift SonoBarTests/VisualTokensTests.swift
git commit -m "feat: add semantic visual tokens and metrics"
```

---

### Task 4: Introduce Shared Surface Components

**Files:**
- Create: `SonoBar/Views/DesignSystem/SurfaceCard.swift`
- Create: `SonoBar/Views/DesignSystem/SectionHeader.swift`
- Modify: `SonoBar/Views/PopoverContentView.swift`
- Test: `SonoBarTests/AdaptiveLayoutTests.swift`

**Step 1: Add failing test for tab bar presentation model**

```swift
func testTabBarModelHasAllTabs() {
    XCTAssertEqual(AppTab.allCases.count, 4)
    XCTAssertEqual(AppTab.nowPlaying.title, "Now")
}
```

**Step 2: Run test to verify failure**

Run: `xcodebuild -project SonoBar.xcodeproj -scheme SonoBar -destination 'platform=macOS' -only-testing:SonoBarTests/AdaptiveLayoutTests test`

Expected: FAIL because `AppTab` does not exist yet.

**Step 3: Implement minimal shared components + tab metadata enum**

```swift
enum AppTab: CaseIterable {
    case nowPlaying, rooms, browse, alarms
    var title: String { ... }
    var icon: String { ... }
}
```

Refactor `PopoverContentView` to use `AppTab` and a reusable `SurfaceCard` style for tab bar container.

**Step 4: Run targeted tests and build**

Run: `xcodebuild -project SonoBar.xcodeproj -scheme SonoBar -destination 'platform=macOS' -only-testing:SonoBarTests/AdaptiveLayoutTests test`

Expected: PASS.

**Step 5: Commit**

```bash
git add SonoBar/Views/DesignSystem/SurfaceCard.swift SonoBar/Views/DesignSystem/SectionHeader.swift SonoBar/Views/PopoverContentView.swift SonoBarTests/AdaptiveLayoutTests.swift
git commit -m "feat: add shared surface components and tab metadata"
```

---

### Task 5: Refactor Now Playing + Volume To Media-First Layout

**Files:**
- Create: `SonoBar/Views/NowPlaying/NowPlayingFormatter.swift`
- Modify: `SonoBar/Views/NowPlayingView.swift`
- Modify: `SonoBar/Views/VolumeSliderView.swift`
- Test: `SonoBarTests/NowPlayingFormatterTests.swift`

**Step 1: Write failing formatter tests**

```swift
import XCTest
@testable import SonoBar

final class NowPlayingFormatterTests: XCTestCase {
    func testSourceBadgeMapping() {
        XCTAssertEqual(NowPlayingFormatter.sourceBadge(for: "x-rincon-mp3radio:abc"), "Radio")
        XCTAssertEqual(NowPlayingFormatter.sourceBadge(for: "spotify:track:123"), "Spotify")
    }

    func testProgressCalculation() {
        XCTAssertEqual(NowPlayingFormatter.progress(elapsed: "0:30", duration: "2:00"), 0.25, accuracy: 0.001)
    }
}
```

**Step 2: Run tests to verify failure**

Run: `xcodebuild -project SonoBar.xcodeproj -scheme SonoBar -destination 'platform=macOS' -only-testing:SonoBarTests/NowPlayingFormatterTests test`

Expected: FAIL with unknown `NowPlayingFormatter`.

**Step 3: Implement formatter and refactor views**

Implement `NowPlayingFormatter` for source badge + time parsing/progress; replace duplicated private logic in `NowPlayingView`. Update `VolumeSliderView` spacing, icon sizing, and state colors to align with design tokens.

**Step 4: Run tests and build**

Run: `xcodebuild -project SonoBar.xcodeproj -scheme SonoBar -destination 'platform=macOS' -only-testing:SonoBarTests/NowPlayingFormatterTests test`

Expected: PASS.

**Step 5: Commit**

```bash
git add SonoBar/Views/NowPlaying/NowPlayingFormatter.swift SonoBar/Views/NowPlayingView.swift SonoBar/Views/VolumeSliderView.swift SonoBarTests/NowPlayingFormatterTests.swift
git commit -m "feat: adopt media-first now playing layout and unified volume styling"
```

---

### Task 6: Refactor Browse Screens With Shared Control Strip

**Files:**
- Create: `SonoBar/Views/Browse/BrowseFilter.swift`
- Modify: `SonoBar/Views/BrowseView.swift`
- Modify: `SonoBar/Views/ContentGridView.swift`
- Modify: `SonoBar/Views/ContentListView.swift`
- Test: `SonoBarTests/BrowseFilterTests.swift`

**Step 1: Write failing filter tests**

```swift
import XCTest
import SonoBarKit
@testable import SonoBar

final class BrowseFilterTests: XCTestCase {
    func testSearchMatchesTitleAndDescription() {
        let items = [
            ContentItem(id: "1", title: "Morning Mix", resourceURI: "uri1", rawDIDL: "", itemClass: "object.container", description: "Apple Music"),
            ContentItem(id: "2", title: "Evening Jazz", resourceURI: "uri2", rawDIDL: "", itemClass: "object.container", description: "Local")
        ]
        let filtered = BrowseFilter.apply(searchText: "apple", to: items)
        XCTAssertEqual(filtered.map(\.id), ["1"])
    }
}
```

**Step 2: Run test to verify failure**

Run: `xcodebuild -project SonoBar.xcodeproj -scheme SonoBar -destination 'platform=macOS' -only-testing:SonoBarTests/BrowseFilterTests test`

Expected: FAIL due missing `BrowseFilter`.

**Step 3: Implement minimal filter helper and migrate views**

Implement `BrowseFilter.apply(searchText:to:)`; update `BrowseView` to use helper. Refactor search + segmented picker into one styled strip; migrate grid/list items to shared surface styling and stronger active indicators.

**Step 4: Run tests and build**

Run: `xcodebuild -project SonoBar.xcodeproj -scheme SonoBar -destination 'platform=macOS' -only-testing:SonoBarTests/BrowseFilterTests test`

Expected: PASS.

**Step 5: Commit**

```bash
git add SonoBar/Views/Browse/BrowseFilter.swift SonoBar/Views/BrowseView.swift SonoBar/Views/ContentGridView.swift SonoBar/Views/ContentListView.swift SonoBarTests/BrowseFilterTests.swift
git commit -m "feat: refresh browse tab with shared control strip and card styling"
```

---

### Task 7: Refactor Rooms + Alarms To Shared Section Patterns

**Files:**
- Create: `SonoBar/Views/Rooms/RoomStatusFormatter.swift`
- Modify: `SonoBar/Views/RoomSwitcherView.swift`
- Modify: `SonoBar/Views/AlarmsView.swift`
- Modify: `SonoBar/Views/AlarmFormView.swift`
- Test: `SonoBarTests/RoomStatusFormatterTests.swift`

**Step 1: Write failing status formatter tests**

```swift
import XCTest
@testable import SonoBar

final class RoomStatusFormatterTests: XCTestCase {
    func testOfflineRoomStatus() {
        XCTAssertEqual(RoomStatusFormatter.statusText(isReachable: false, transport: .stopped, title: nil, artist: nil, fallbackModel: "Era 100"), "Offline")
    }
}
```

**Step 2: Run tests to verify failure**

Run: `xcodebuild -project SonoBar.xcodeproj -scheme SonoBar -destination 'platform=macOS' -only-testing:SonoBarTests/RoomStatusFormatterTests test`

Expected: FAIL due missing `RoomStatusFormatter`.

**Step 3: Implement helper + migrate views**

Implement `RoomStatusFormatter` from existing room status logic. Update `RoomSwitcherView` and `AlarmsView` to use consistent section headers/cards, selected-state treatment, and badge typography. Update `AlarmFormView` day selectors to consistent chip style.

**Step 4: Run tests and build**

Run: `xcodebuild -project SonoBar.xcodeproj -scheme SonoBar -destination 'platform=macOS' -only-testing:SonoBarTests/RoomStatusFormatterTests test`

Expected: PASS.

**Step 5: Commit**

```bash
git add SonoBar/Views/Rooms/RoomStatusFormatter.swift SonoBar/Views/RoomSwitcherView.swift SonoBar/Views/AlarmsView.swift SonoBar/Views/AlarmFormView.swift SonoBarTests/RoomStatusFormatterTests.swift
git commit -m "feat: unify rooms and alarms section styling with shared status formatting"
```

---

### Task 8: Add Shared Async/Error UI Pattern

**Files:**
- Create: `SonoBar/Views/DesignSystem/InlineStateView.swift`
- Create: `SonoBar/Views/DesignSystem/TransientBannerView.swift`
- Modify: `SonoBar/Views/BrowseView.swift`
- Modify: `SonoBar/Views/AlarmsView.swift`
- Modify: `SonoBar/Views/RoomSwitcherView.swift`
- Modify: `SonoBar/Services/AppState.swift`
- Test: `SonoBarTests/InlineStateModelTests.swift`

**Step 1: Write failing model tests**

```swift
import XCTest
@testable import SonoBar

final class InlineStateModelTests: XCTestCase {
    func testEmptyStatePriorityOverContent() {
        let state = InlineStateModel(isLoading: false, error: nil, itemCount: 0)
        XCTAssertEqual(state.kind, .empty)
    }
}
```

**Step 2: Run tests to verify failure**

Run: `xcodebuild -project SonoBar.xcodeproj -scheme SonoBar -destination 'platform=macOS' -only-testing:SonoBarTests/InlineStateModelTests test`

Expected: FAIL due missing `InlineStateModel`.

**Step 3: Implement model + reusable state views**

Implement `InlineStateModel` and shared views for loading/empty/error rendering. Add lightweight transient banner state to `AppState` for non-blocking action errors and integrate in Browse/Rooms/Alarms.

**Step 4: Run tests and build**

Run: `xcodebuild -project SonoBar.xcodeproj -scheme SonoBar -destination 'platform=macOS' -only-testing:SonoBarTests/InlineStateModelTests test`

Expected: PASS.

**Step 5: Commit**

```bash
git add SonoBar/Views/DesignSystem/InlineStateView.swift SonoBar/Views/DesignSystem/TransientBannerView.swift SonoBar/Views/BrowseView.swift SonoBar/Views/AlarmsView.swift SonoBar/Views/RoomSwitcherView.swift SonoBar/Services/AppState.swift SonoBarTests/InlineStateModelTests.swift
git commit -m "feat: add shared async/error states and transient banner pattern"
```

---

### Task 9: End-To-End Verification And Documentation

**Files:**
- Modify: `docs/plans/2026-03-14-sonobar-look-and-feel-design.md` (append implementation notes)
- Create: `docs/plans/2026-03-14-sonobar-look-and-feel-verification.md`

**Step 1: Write verification checklist doc first (failing criteria list)**

```markdown
# SonoBar Look & Feel Verification

- [ ] Resizing works from compact to expanded without clipping
- [ ] Now playing controls remain functional
- [ ] Browse search, queue jump, and play actions still work
- [ ] Room switching and group indicators remain correct
- [ ] Alarm and sleep timer flows remain unchanged
```

**Step 2: Run complete automated verification**

Run: `xcodebuild -project SonoBar.xcodeproj -scheme SonoBar -destination 'platform=macOS' test`

Expected: PASS all `SonoBarTests`.

Run: `xcodebuild -project SonoBar.xcodeproj -scheme SonoBar -configuration Debug build`

Expected: `** BUILD SUCCEEDED **`.

**Step 3: Execute manual verification checklist**

Run app and validate:
- room switcher accuracy
- transport controls (`play/pause/next/previous/seek/volume`)
- browse segment loading and queue track jump
- alarm create/toggle/delete and sleep timer set/cancel

Expected: no behavioral regressions.

**Step 4: Update docs with outcomes**

Append measured outcomes and remaining follow-ups (if any) to design doc and verification doc.

**Step 5: Commit**

```bash
git add docs/plans/2026-03-14-sonobar-look-and-feel-design.md docs/plans/2026-03-14-sonobar-look-and-feel-verification.md
git commit -m "docs: add look-and-feel verification results"
```

---

## Final Gate

Before merge or release:

1. Run: `xcodebuild -project SonoBar.xcodeproj -scheme SonoBar -destination 'platform=macOS' test`
2. Run: `xcodebuild -project SonoBar.xcodeproj -scheme SonoBar -configuration Debug build`
3. Confirm popover resize behavior and readability in both light and dark appearances.
4. Confirm no Sonos control regressions in core user flows.
