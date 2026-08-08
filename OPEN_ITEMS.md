# EnviroMap — Open Items

Last updated: 2026-08-08

| ID | Area Of App | Problem | Priority | Status | Testing Date | Completed Date | Notes |
|----|-------------|---------|----------|--------|--------------|----------------|-------|
| OI-001 | Launch / Startup | White or bright flash before dark splash; system launch not seamless with logo splash | High | Open | 2026-08-08 | | User wants only designed splash; launch-screen cache needs delete-app reinstall when testing |
| OI-002 | Launch / Splash | Transparent logo can show checkerboard / fringe on some assets | Medium | Open | 2026-08-08 | | Prefer true transparent PNG without white plate; splash restored with logo + EnviroMap name |
| OI-003 | First Login / Onboarding | Intro screens must always show on true first install; regressions when launch experiments run | High | Open | 2026-08-08 | | Restored with onboarding key v3; verify full page set after reinstall |
| OI-004 | Home | Keep simple mobile-first home (scan primary, 2-col tools, More Tools tab) | Low | Done | 2026-08-08 | 2026-08-08 | Layout accepted by user |
| OI-005 | Level Tool | Landscape layout: overlap, cramped chrome, grey nav bar | Medium | Mostly Done | 2026-08-08 | | Full-screen level, modes on right, tip bottom; re-test overlap on iPhone 17 Pro landscape |
| OI-006 | Level Tool | Multi-orientation accuracy (flat / upright / side) vs real surfaces | Medium | Open | 2026-08-08 | | Compare against known level surface / wall |
| OI-007 | Scan / LiDAR | World tracking failure during RoomPlan capture | High | Open | 2026-08-07 | | Tips added; still needs reliable recovery on device |
| OI-008 | 3D Mesh Viewer | Freeze when opening mesh from prior scan | High | Open | 2026-08-07 | | SceneKit path added earlier; re-verify after recent pulls |
| OI-009 | Floor Plan | Navigation tries to open then fails / incomplete | High | Open | 2026-08-07 | | Library fullScreenCover routing — re-test Session Detail |
| OI-010 | Session Detail | Buttons (Room Planner, Floor Plan, 3D Mesh, Walk AR) not always working | High | Open | 2026-08-07 | | Design pass also requested to match home theme |
| OI-011 | 3D Mesh Content | Viewer shows walls/openings mainly; user wants “everything” mapped | High | Open | 2026-08-08 | | RoomPlan parametric model vs full dense mesh (ARMesh) — product decision needed |
| OI-012 | Room Planner | Dated/clunky; need modern 3D furniture + solid interactions | Medium | Open | 2026-08-07 | | 3D mode started; polish + button actions |
| OI-013 | Ruler / Area / Level | Measure tools UX polish + Title Case copy standard | Low | Open | 2026-08-08 | | Level copy Title Case applied; apply same standard app-wide |
| OI-014 | More Tools | Photo To 3D / Words To 3D are lightweight placeholders vs full product vision | Medium | Open | | | Keep as secondary; define v1 scope |
| OI-015 | Design System | App-wide Title Case for first letter of each word in UI strings | Low | In Progress | 2026-08-08 | | Established for Level; extend to Home, Library, Onboarding |
| OI-016 | Library | Empty state + open prior scans must be obvious for new users | Medium | Open | 2026-08-08 | | “My Rooms” tab — validate with zero scans and with 1+ scans |
| OI-017 | AR Walk | Walk AR stability after scan | Medium | Open | | | Test with latest mesh export |
| OI-019 | Automation / Fastlane | Wire continuous build+unit tests; LiDAR still manual on device | Medium | Done | 2026-08-08 | 2026-08-08 | `bundle exec fastlane qa` — see FASTLANE.md |
| OI-018 | Signing / Device | Trust developer, team signing, keychain prompts on device installs | Low | Done | 2026-08-07 | 2026-08-07 | Documented for Cory’s iPhone workflow |

---

## Status Legend

| Status | Meaning |
|--------|---------|
| Open | Not fixed or not verified on device |
| In Progress | Actively being worked |
| Mostly Done | Shipped but needs final device QA |
| Done | Verified complete |
| Blocked | Waiting on decision, asset, or hardware |

## Priority

| Priority | Meaning |
|----------|---------|
| High | Breaks core scan → save → view path or first-run |
| Medium | Hurts UX or a main tool |
| Low | Polish / copy / nice-to-have |

---

## Suggested Next Testing Order

1. **OI-001 + OI-003** — Delete app → install → splash → full onboarding → home  
2. **OI-007** — New LiDAR scan success rate  
3. **OI-008 + OI-009 + OI-010** — Open a saved room → every action button  
4. **OI-005 + OI-006** — Level flat / upright / side  
5. **OI-011** — Decide dense mesh vs RoomPlan structure  

---

## How To Update

When you finish or retest an item:

1. Set **Status**  
2. Fill **Testing Date** (when you last tried on phone)  
3. Fill **Completed Date** when Status = Done  
4. Add a short note under **Notes**  

Example:

| OI-008 | 3D Mesh Viewer | … | High | Done | 2026-08-09 | 2026-08-09 | Opens SceneKit view; no freeze on 3 scans |
