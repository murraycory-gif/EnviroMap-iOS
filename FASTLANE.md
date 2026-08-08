# EnviroMap — Fastlane

Automates **build** and **unit tests** on your Mac. LiDAR / RoomPlan / AR still need a **real iPhone** (not Simulator).

## One-time setup

```bash
cd ~/Developer/EnviroMap-iOS
git pull
bundle install
```

If `bundle` is missing:

```bash
sudo gem install bundler
bundle install
```

## Lanes

| Command | What it does |
|---------|----------------|
| `bundle exec fastlane build` | Compile app for iOS Simulator |
| `bundle exec fastlane build_clean` | Clean + compile |
| `bundle exec fastlane tests` | Run `EnviroMapTests` on Simulator |
| `bundle exec fastlane qa` | Build + tests + list open High items |
| `bundle exec fastlane open_items` | Print High+Open rows from `OPEN_ITEMS.md` |
| `bundle exec fastlane device_build` | Build for physical device (signing required) |
| `bundle exec fastlane sims` | List simulators |

Pick a simulator if default fails:

```bash
export SCAN_DEVICE="iPhone 16 Pro"
bundle exec fastlane tests
```

## What Fastlane covers vs device QA

| Automated (Fastlane / Simulator) | Manual (Cory’s iPhone) |
|----------------------------------|-------------------------|
| Compiles without errors | LiDAR scan (OI-007) |
| Unit tests (`RoomSession`, tracker file) | 3D mesh open / freeze (OI-008) |
| Open-items file present | Floor plan / session buttons (OI-009/010) |
| | Level flat/upright/side (OI-005/006) |
| | Launch splash / first login (OI-001/003) |

## Reports

After `tests` or `qa`:

- `build/test_output/report.html`
- `build/test_output/report.junit`

## GitHub Actions (optional later)

This repo is ready for a Mac runner. A Linux GitHub-hosted runner **cannot** build iOS without a macOS image + Xcode.

## Troubleshooting

- **No scheme EnviroMap** → open `EnviroMap.xcodeproj` once in Xcode, then re-run  
- **Signing errors on device_build** → set Team in Xcode Signing & Capabilities  
- **scan device not found** → `fastlane sims` and set `SCAN_DEVICE`  
