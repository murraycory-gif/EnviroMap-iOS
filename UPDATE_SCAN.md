# Force update to Full 3D Scan (not RoomPlan walls)

Your phone showed the **old** RoomPlan UI (Walls / Doors / Windows).
GitHub already has Full Environment scan. Force-sync your Mac:

```bash
cd ~/Developer/EnviroMap-iOS

# 1) Drop local conflicts and match GitHub exactly
git fetch origin
git reset --hard origin/main
git clean -fd

# 2) Confirm you have the new code
grep -n "Full 3D Scan" EnviroMap/MainHubView.swift | head
grep -n "FULL ENV" EnviroMap/Capture/FullEnvironmentScanView.swift | head
ls EnviroMap/Capture/FullEnvironmentScanView.swift

# 3) Open project fresh
open EnviroMap.xcodeproj
```

In Xcode:
1. Product → Clean Build Folder (hold Option)
2. Delete EnviroMap from iPhone
3. Select Cory's iPhone → ▶ Run

You should see:
- Home: **Full 3D Scan** / Capture everything · real colors
- Scan screen: **FULL ENV · NOT WALLS ONLY** (green text)
- NO Walls/Doors/Windows counters
