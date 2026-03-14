# SonoBar Look & Feel Enhancement Design (Media-First)

## Overview

This design upgrades SonoBar's visual quality and interaction polish while preserving all existing playback, browsing, room management, and alarm functionality. The target direction is:

- Media-first presentation
- Adaptive and resizable popover layout
- Hybrid visual language (system-native base + richer media accents)

Primary view targets:

- `SonoBar/Views/PopoverContentView.swift`
- `SonoBar/Views/NowPlayingView.swift`
- `SonoBar/Views/BrowseView.swift`
- `SonoBar/Views/ContentGridView.swift`
- `SonoBar/Views/ContentListView.swift`
- `SonoBar/Views/RoomSwitcherView.swift`
- `SonoBar/Views/AlarmsView.swift`
- `SonoBar/Views/AlarmFormView.swift`
- `SonoBar/Views/VolumeSliderView.swift`

## Approach Options Considered

### 1) Polish Existing Views

Refine spacing, typography, and visual affordances in-place while retaining the current structure.

Trade-offs:

- Lowest implementation effort and risk
- Quick visual improvements
- Weaker long-term consistency due to ad hoc styling remaining in each screen

### 2) Light Design System + View Refactor (Recommended)

Introduce shared design primitives and semantic tokens, then migrate each screen to those primitives while adding adaptive layout behavior.

Trade-offs:

- Medium effort
- Strong consistency and maintainability
- Better platform fit without full rewrite risk

### 3) Full Visual Rewrite

Recompose all screens with new layout patterns and richer motion throughout.

Trade-offs:

- Highest visual upside
- Highest regression risk and iteration cost
- Slower path to stable delivery

## Recommended Direction

Proceed with **Approach 2**.

This provides substantial visual quality gains now and creates reusable UI foundations for future features.

## Visual Architecture

### Adaptive Shell

- Replace fixed popover dimensions with a resizable shell.
- Use min/max constraints and width-based layout modes instead of fixed constants.
- Set a larger media-friendly default size while preserving compact usability.

### Hybrid Theme Strategy

- Keep system backgrounds and text for native readability.
- Introduce semantic accent tokens for media emphasis and interactive surfaces.
- Allow artwork-informed accents where appropriate without compromising contrast.

### Hierarchy Rules

- Prioritize now-playing context: artwork, title/artist, progress, primary transport controls.
- Demote utility metadata and secondary labels.
- Ensure information density scales cleanly with available width.

### Surface Language

- Standardize card surfaces, rounded corners, divider usage, and spacing rhythm.
- Align row/item interaction states (hover, press, selected, active) across tabs.

### Motion Principles

- Keep motion minimal and meaningful.
- Animate only important transitions: tab change, now-playing state changes, focused media feedback.
- Respect reduced-motion settings.

## Per-Screen UX Changes

### Popover Shell (`PopoverContentView`)

- Adaptive frame constraints and background treatment
- Elevated bottom tab bar with clearer active state affordance
- Improved icon-label alignment and touch target consistency

### Now Playing (`NowPlayingView`)

- Larger, adaptive artwork framing
- Clear typographic tiers for title/artist/album
- Dedicated media-progress card
- More balanced transport control spacing and targets

### Browse (`BrowseView`, `ContentGridView`, `ContentListView`)

- Unified search + segmented control strip
- Richer list and grid item cards with stronger text hierarchy
- Stronger now-playing indicator in queue/list contexts

### Rooms (`RoomSwitcherView`)

- Consistent interactive room cards
- Better active/group badge readability
- Clear status styling rules for playback/offline/idle

### Alarms + Sleep Timer (`AlarmsView`, `AlarmFormView`)

- Distinct section cards and shared headers
- Stronger alarm row hierarchy (time first, metadata second)
- Consistent day chip and button selection states

### Shared Volume (`VolumeSliderView`)

- One canonical volume control style used everywhere
- Standardized spacing, numeric alignment, and muted-state visuals

## Interaction, State, and Behavior

### Layout Modes

- Compact, standard, and expanded modes derived from available width
- Reflow components by mode rather than scaling all dimensions uniformly

### Async State Surfaces

- Shared loading, empty, and error patterns across all tabs
- Smooth transitions to avoid abrupt visual jumps during refresh

### Immediate Media Feedback

- Optimistic UI response for transport/seek/volume actions
- Reconcile optimistic state with authoritative `AppState` refresh updates

### Selection and Focus

- Uniform selected and active treatment across rooms and browse rows/cards
- Explicit keyboard focus visibility for accessibility and power users

### Error Pattern

- Use one non-blocking error banner/pill style with auto-dismiss where safe
- Include retry affordance where actionable

### Animation Boundaries

- Limit animation to high-value transitions
- Avoid long or continuous animation in popover context

## Rollout Plan

### Phase 1: Shell + Tokens

- Add semantic colors, spacing/type scale, and shared surface components
- Make popover adaptive/resizable

### Phase 2: Now Playing + Volume

- Implement media-first now-playing hierarchy
- Unify volume control presentation and interaction

### Phase 3: Browse, Rooms, Alarms

- Migrate remaining tabs to shared design primitives
- Standardize empty/loading/error and selection patterns

## Verification Strategy

- Build validation after each phase via `xcodebuild -project SonoBar.xcodeproj -scheme SonoBar -configuration Debug build`
- Manual flow checks after each phase:
  - Room switching
  - Play/pause/next/previous/seek/volume
  - Browse playlists and queue track jumping
  - Alarm create/toggle/delete
  - Sleep timer set/cancel
- Usability checks:
  - Resize behavior across compact to expanded widths
  - Text truncation and layout stability
  - Keyboard navigation/focus visibility
  - Light/dark appearance readability

## Performance and Risk Controls

- Keep business logic in `AppState` unchanged during visual refactors
- Prefer view-layer and component-layer changes to minimize playback regressions
- Avoid expensive redraw patterns tied to frequent playback refresh

## Definition Of Done

- All tabs use one coherent visual system
- No clipping or major layout breakage across supported popover widths
- Interaction states are consistent and clear
- Existing feature behavior remains unchanged
