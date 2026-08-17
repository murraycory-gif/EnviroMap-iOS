# EnviroMap scan research (2026-08-16)

## What the best apps actually do

| App | Geometry | Look | After scan |
| --- | --- | --- | --- |
| **Polycam LiDAR** | iPhone LiDAR mesh + planes | Project photos onto that mesh | Optional cloud photogrammetry / Gaussian splat |
| **Scaniverse** | LiDAR mesh on-device | Photo project or Gaussian splat | On-device process |
| **3D Snap** | LiDAR + live wire overlay | One photo per surface | Fast bake |
| **RoomPlan** | Semantic walls/doors (not photo) | Cartoon rooms | Instant |
| **Apple Object Capture** | Photos only | Looks real | Minutes; **objects**, not garages |

**Textureless drywall** cannot be built from photos. LiDAR (or planes) must supply the wall. Photos only paint it.

**Gaussian splats** look most real. They are a different renderer (not SceneKit mesh). Later milestone, not tonight.

## What we were doing wrong

1. **Per-triangle photos** on the Tesla → quilt / pink squares.
2. **One photo on a whole garage wall** → UVs fail → wall goes black.
3. **Fake depth triangles** → speckle field (BQ).
4. **Drop a whole wall if 35% hit the car** → the hole-fill part of the wall was thrown away. That is why BS looks like BN’s Tesla with almost no wall.

## The correct hybrid (what Polycam LiDAR mode does)

1. LiDAR mesh = car, fan, jacket, floor clutter. **One photo per small tile.**
2. ARKit **vertical + ceiling planes** = the room shell. **Clip cells that sit on the car. Keep the rest.**
3. Paint the shell with any photo that faces it. Never reject drywall as “blown white.”
4. Do not invent depth confetti.
5. Photogrammetry / splats only as a later “Enhance” pass — not the live walk.

## Overnight fix (Build 0810-BT)

- Stop dropping whole walls.
- Tag backdrop chunks and always try to photo-paint them.
- Keep Tesla on one photo per tile (clarity).
- Project saved to GitHub `main`.

## When you’re back

1. `git pull` + Clean Build → stamp **BT**
2. Walk once, pause 2s on each wall.
3. If walls are still thin, next step is live **plane banking** (keep the largest wall ARKit ever saw, not only the last frame).
4. After walls are reliable: optional “Make it photo-real” button (Gaussian splat / Object Capture) as a slow enhance.
