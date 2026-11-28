# CLAUDE.md — MASTER ARCHITECTURE: PIXELATED ROBO-WORLD GAME & MACHINIMA ENGINE

## 1. VISION, PURPOSE & WHY THIS SOFTWARE EXISTS
You are building **Pixelated Robo-World**, a unified **playable slapstick game and real-time 3D machinima studio** engineered from the ground up around `0.1`-unit micro-voxels, tactile multi-finger controls, and rapid creative iteration.

### Why We Are Building This Instead of Traditional Pipelines
Traditional 3D animation and game development force creators through slow, fragmented toolchains: sculpting in one app, rigging or UV-mapping in another, exporting heavy files, compiling slow builds, and editing timelines frame by frame before seeing if a joke or game mechanic actually works.

This software solves that by uniting **play, live direction, editing, and capture inside one single engine**:
1. **One Shared World for Game & Show:** Every room, prop, water volume, and robo-character is built out of the same `0.1`-unit micro-voxel data model. What works as a slapstick game mechanic (flooding a room, knocking props over, hopping across marks, reacting with pixel-LED faces) works immediately as a live comedy performance tool—and every scene can later evolve into a standalone playable game level or micro-game without rebuilding the world from scratch.
2. **Speed of Live Puppetry Over Keyframe Bottlenecks:** Instead of spending hours keyframing every limb and mouth movement by hand, you perform scenes live using responsive multi-finger controls—moving characters, flicking between pixel-LED expressions, driving lip-sync from voice/talk input, cutting between deterministic cameras, and triggering escalating chaos on cue.
3. **100% Original Micro-Voxel Craft:** Rather than relying on external 3D models or 2D image pipelines, everything is composed of crisp `0.1`-unit micro-cubes (`VOXEL_SIZE = 0.1`) and emissive pixel-LED face grids. Every prop, robot, and room can be edited directly in-world (painting colors, adding/erasing cubes, toggling glow) and saved as lightweight local JSON data.
4. **Built for Real-World Mobility & Dual-Format Output:** Designed to run locally on Android (such as on a Samsung Galaxy S25 via Termux/local dev server and Capacitor packaging) as well as desktop browsers, using PUBG-style multi-finger touch zones and keyboard parity so complex control remains effortless on a phone screen. Every scene supports both `16:9` widescreen and `9:16` vertical framing (plus dual crop guides) and clean HUD-free frame/video export.

---

## 2. REFERENCE GAME MIX (FEEL & DESIGN TARGETS)
Use these reference games as **design and feel touchstones** (without copying any third-party IP or assets) so every system has clear personality:
- **Crossy Road:** Crisp, readable micro-voxel diorama silhouettes, bold colors, and clean framing that stays unmistakable on a phone screen.
- **Spider-Man: Into the Spider-Verse:** Mixing stepped character pose timing (`12fps "On Twos"` with snappy overshoot) against smoother camera/environmental motion so poses pop with weight.
- **Thank Goodness You're Here! & Untitled Goose Game:** Escalating slapstick absurdity, compact self-contained spaces, and reactive comedic gags (such as multi-stage water overflow turning a calm room into chaos).
- **Teardown & WarioWare:** Destructible/reactive voxel objects for slapstick moments and tight, punchy comic beats that can later become playable micro-game loops.
- **PUBG Mobile & Brawl Stars:** Split-thumb multi-finger touch zones, claw readiness, hold-and-drag radial selection wheels, and clean, uncluttered mobile HUD buttons that keep the scene unobstructed.
- **Garry's Mod (GMod) & Live Puppetry:** Real-time sandbox staging, camera cuts, prop/character posing, and voice-driven expression/lip-sync performance inside a live world.

---

## 3. CORE ARCHITECTURAL PRINCIPLES
1. **Game-First Base + On-Demand Studio Mode:**
   - **Game Mode (`mode === 'game'`):** Clean, responsive playable state with full multi-finger touch and keyboard controls, zero editor clutter, and clear interactive objectives or slapstick triggers.
   - **Studio Mode (`mode === 'studio'`):** Unlocks modular, collapsible creator drawers over the live scene for **Models**, **Scenes & Chaos**, **Voice & Lip-Sync**, **Cameras & Framing**, **Movement & "On Twos" Timing**, and **Frame & Video Export**—all operated seamlessly through the same game-style control paradigm.
2. **Deterministic Motion + "On Twos" Stop-Motion Toggle:**
   - Character movement, head turns, expressions, and lip-sync support a global **`12fps "On Twos"`** toggle (mimicking tactile stop-motion / stylized animated shorts with crisp pose holds and subtle rotational overshoot on snappy turns) alongside smooth **`60fps`** mode for fast game action.
   - Use deterministic tweens/state transitions (`gsap` + controlled accumulators) rather than fragile, unpredictable physics simulations for core comedy beats.
3. **High-FPS Micro-Voxel Performance (`InstancedMesh`):**
   - Represent micro-voxels compactly as `{ x, y, z, color, emissive?, group? }` scaled by `0.1`.
   - Batch voxels via `THREE.InstancedMesh` with **hidden-face culling** (omitting internal cubes surrounded on all 6 neighbor faces) so dense micro-voxel environments stay fast on mobile GPUs.
   - Keep `useFrame` focused on direct Three.js ref/matrix/material/audio mutations—never trigger React state re-renders inside per-frame loops.
4. **Local-First Persistence & Clean Vertical Slices:**
   - Persist custom voxel props, edits, and scene configurations as compact JSON files locally on device.
   - Build a complete, working vertical slice first (one micro-voxel scene, one pixel-face robo-character, PUBG-style touch + keyboard controls, `Static / Slider / Drone` cameras, `12fps "On Twos"` toggle, multi-stage water overflow chaos, and clean frame/video export) before expanding into additional episodes and tools.

---

## 4. RECOMMENDED TECH STACK
- **Frontend & Build:** React 19, TypeScript (strict mode), Vite
- **3D Engine:** Three.js (`WebGLRenderer` with `preserveDrawingBuffer: true`), `@react-three/fiber`, `@react-three/drei`
- **Motion & State:** `gsap` for deterministic animations/transitions, `zustand` for centralized game/studio state, active drawers, and undo history
- **Audio & Lip-Sync:** Browser Web Audio API (`AudioContext`, `AnalyserNode`, `BiquadFilterNode`, `DelayNode`, `GainNode`) for voice presets, amplitude-driven lip-sync, background music ducking, and SFX triggers
- **Android & Local Workflow:** Local Node/Vite execution on Android (e.g., Termux) with local JSON storage and Capacitor (`@capacitor/core`, `@capacitor/android`) for native mobile packaging

---

## 5. CONTROLS & INTERACTION MODEL (PUBG-STYLE HUD + KEYBOARD)
Design all controls so a creator or player can command rich actions quickly with multiple fingers on a phone screen or via keyboard:
- **Left Thumb Zone / `WASD`:** Floating analog virtual joystick for smooth character movement across the room/stage.
- **Right Screen Zone:** Camera pan/look drag zone paired with tactile action triggers (`Talk / Lip-Sync`, `Interact / Chaos`, `Hop / Action`).
- **Radial Expression Wheel (`Hold & Drag` on `Face` button or keys `1`–`6`):** Opens a circular radial selector on hold to flick between glowing `8x8` pixel-LED expressions on the robot's head (`1: Deadpan`, `2: Smirk`, `3: Panic`, `4: Angry`, `5: Happy`, `6: Shocked`).
- **Top Corner Claws & Hotkeys:** Quick toggles for `Game / Studio Mode`, `12fps On Twos`, `16:9 / 9:16 / Dual` guides, camera cuts (`Z: Static`, `X: Slider`, `C: Drone`), chaos triggers (`Q`, `W`, `E`), and `Clean HUD` (hides all UI overlays for capture).

---

## 6. STUDIO MODE CAPABILITIES (COLLAPSIBLE DRAWERS)
When `Studio Mode` is toggled on, provide clean, non-overlapping drawers (ideally one expanded at a time so the 3D scene stays prominent):
1. **Model & Voxel Editor:** Pick any robo-character or prop group, edit `0.1`-unit micro-cubes (`Paint`, `Add`, `Erase`), choose colors or emissive glow, undo edits, and save reusable voxel JSON assets locally.
2. **Scene & Chaos Controls:** Toggle/move props, test interactive triggers, and run multi-stage **Water Overflow** sequences (`Stage 1: Trickle/Leak`, `Stage 2: Surge/Bobbing Props`, `Stage 3: Full Flood & Panic`).
3. **Voice & Lip-Sync Studio:** Drive expression-locked mouth animation and head bob from microphone/audio amplitude or `Talk` hold input, switch 1-button voice presets (`Normal`, `Radio`, `Phone`, `Scary`, `High/Low Pitch`), and trigger SFX/music with auto-ducking.
4. **Cameras & Framing:** Switch between `Static` (locked cinema tripod), `Slider` (linear dolly track with `0–100%` scrub or auto-glide), and `Drone` (elevated hover/orbit), with `38°` cinema lens framing and `16:9` / `9:16` / `Dual` safe-zone guides.
5. **Movement & Timing:** Toggle `12fps "On Twos"` vs. `60fps` smooth motion, tune turn overshoot/snappiness, and switch between playable game mode and live puppet/machinima mode.
6. **Frame & Video Export:** Export individual high-res **PNG frames** or record clean **16:9 / 9:16 video** directly from the `<Canvas>` with HUD controls hidden.

---

## 7. EXECUTION DIRECTIVE FOR CLAUDE CODE
- Scaffold a clean, modular TypeScript project (`/src/store/`, `/src/engine/`, `/src/actors/`, `/src/scenes/`, `/src/ui/`) with a complete working vertical slice first.
- Make sure every control works both on mobile touchscreens and desktop keyboards, persists custom edits cleanly to local JSON, and maintains high frame rates on mobile hardware.
- Keep code well-structured, typed, and easy to extend into new episodes, props, and playable game loops.

---

## 8. IMPLEMENTATION NOTES (keep in sync with the code)
- **Chaos hotkeys are `Q` / `E` / `R` (+ `T` = drain/reset)**, not `Q/W/E`: `W` is reserved for WASD movement. Touch: the `Chaos` action button advances one stage per tap.
- `Space` = hold Talk, `F` = Hop, `G` = Interact (next chaos stage), `H` = Clean HUD, `Tab` = Game/Studio, `O` = On Twos, `P` = PNG frame, `F1`–`F6` = SFX pads, `Cmd/Ctrl+Z` = undo.
- Persistence: scenes and voxel assets save to `localStorage` and download as `.json`; on the Vite dev server they are also written to disk via `/api/save-scene` and `/api/save-prop`.
- **Two art pipelines share one engine.** Voxel episodes (`overflowing-kitchen`) build rooms from `0.1` voxels at runtime. Sculpted episodes (`pond-life`, a nature-mockumentary look) use original assets sculpted procedurally in **Blender** via `tools/blender/*.py`: ellipsoid clay forms are fused by voxel remesh, carved with booleans, smoothed, given layered displacement "brush" passes, decimated and vertex-painted, then exported to `public/models/*.glb`.
  - Regenerate: `/Applications/Blender.app/Contents/MacOS/Blender -b -P tools/blender/sculpt_frog.py` (or `sculpt_pond.py`). Preview a still with `tools/blender/preview.py -- <glb> <png> [cam xyz] [target xyz]`.
  - Sculpted characters are segmented rigs (no skeleton): each part is its own object with its origin at the joint pivot (`Frog_Jaw`, `Frog_Lid_L`, …), animated deterministically in `src/actors/FrogActor.tsx`. Expressions live in the eyelids, eye bulge, jaw and throat puff; lip-sync drives the jaw.
  - Actors follow the ground via `public/models/pond_height.json`. The grass uses `uv.y` as blade height for the vertex-shader wind.
- `CinematicFX` (depth of field auto-focused on the active actor, bloom, AgX tone mapping, vignette, grain) can be toggled under Studio → Timing → Look. The `@react-three/postprocessing` wrapper copies the DOF `target` only once, so the live effect's `target` is updated every frame.
- **Drawn look** (`src/engine/DrawnLookEffect.ts`, toggled with `L` or the ✏️ claw): a grease-pencil-style screen pass. It draws ink outlines where depth and color change sharply, makes them wobble with a 12fps line boil so they read as hand-redrawn, adds hatching in the shadows, slightly flattens the colors, and overlays paper grain. Ink, hatching and boil sliders are in Studio → Timing.

## 10. ART DIRECTION (current — supersedes earlier notes)
- **One aesthetic everywhere: square voxels.** Every scene and character is built from square cells (`src/engine/sdf.ts` shapes sampled into voxels). No imported meshes. `public/models` and the Blender pipeline are retired; `tools/blender/` is kept for reference only.
- **Hybrid characters:** organic silhouettes made of squares, with robot parts (glowing LED strips, antennas, glowing lenses). Bog the frog (`src/actors/frogModel.ts`) and the robo both follow this.
- **Adjustable:** each part is a list of cells with a pivot, so you can resize or recolour any part in code. Character voxels use a finer size (`FROG_VOXEL = 0.03`) than rooms (`0.1`).
- Scenes: The Overflowing Kitchen, Pond Life, Backyard Garden. Each is one node on the world map (`M`); doorways (portals) connect neighbouring scenes.
- **Camera:** `N` or 🛸 Fly = free-fly (WASD, Space up, Shift down, drag to look). Studio → Cameras → Saved views stores three views per scene.
- Deploy: `scripts/deploy.sh` builds the site and publishes to GitHub Pages (`gh-pages`, public).
- **Drawn look is clean by default:** ink silhouettes with 12fps boil only. Hatching was removed; paper grain is off by default. Block (voxel seam) edges show when  is on or while painting in Studio.

- **Drawn look is clean by default:** ink silhouettes with 12fps boil only. Hatching was removed; paper grain is off by default. Block (voxel seam) edges show when the Show block edges option is on, or while painting in Studio.

## 11. RENDER TAKE (replaces screen recording)
- 🎬 **Render** drawer (Studio → Render take, or the 🎬 Render claw). Choose output size (1080p, 4K, 9:16, square) and frame rate (12 on twos, 24, 30, 60), then arrange shots.
- **Shots:** "+ Shot from this camera" freezes the current camera. "+ Slider" / "+ Drone" add moving-rig shots. Shots are saved per scene.
- **How it works:** the render steps time by exactly 1/fps per frame (R3F frame loop set to manual), draws each frame at the chosen size with the full post-processing stack, and encodes H.264 MP4 with WebCodecs + mp4-muxer. Output sharpness comes from the chosen resolution, not the device screen.
- Requires Chrome/Edge (WebCodecs) and HTTPS for the live site.

- **Grease pencil is outline-only.** The drawn pass inks silhouettes and boils them. It never changes fill colours, adds paper tint, or adds grain. The project contains no bitmap assets (no PNG/JPG/GLB); every surface is procedural geometry and colour.

## 12. VECTOR ONLY (current rule — overrides earlier raster notes)
- **No raster in the pipeline.** Removed: screen-space ink, depth of field, bloom, grain, vignette, tone mapping. Nothing samples pixels, and no bitmap/texture/image assets exist in the repo.
- **Ink is vector geometry.** `src/engine/vectorInk.ts` builds each object's outer edges (each edge keeps the two faces it touches). `src/engine/VoxelInk.tsx` draws them as fat-line geometry. The GPU keeps an edge only if one face points toward the camera and the other away (silhouette), and wobbles it 12 times a second. Width scales with output height.
- Block outlines (every edge) are on while painting or with Show block edges on.
- Known cost: dense voxel areas create many edges. Keep detail coarse (e.g. no 1-cell grass tufts) to stay fast on phones.

- Ink: darker muted brown (`#5c5043`), pressure-tapered strokes (width varies per point, shared where strokes meet), stroke width as a share of frame height. The 16:9 thirds grid is removed; shadows are off to avoid shaded-square artifacts.

- **Ink strokes (current):** silhouette edges are joined into contours (one contour = one stroke, so strokes never overlap), smoothed with Chaikin, then drawn as a ribbon that tapers from the middle to both ends (`src/engine/vectorInk.ts`, `src/engine/VoxelInk.tsx`). Width is set in screen pixels relative to frame height.

## 13. GODOT PORT (in progress — `godot/`)
- Engine: Godot 4.7 (installed via Homebrew). The Three.js app stays in the repo until the port reaches parity.
- Voxels: `godot/scripts/VoxelMesh.gd` builds one ArrayMesh per object, emitting only exposed faces with flat normals and vertex colours. Glowing voxels are a second surface.
- Outline: traced grease-pencil strokes (`InkStroke.gd`); the inverted-hull `Outline.gd` is retired.
- Done: garden room + robo slice (`Main.gd`), screenshot checked.
- Next: cameras + free fly, scene switching + portals, kitchen, pond + frog rig, flood chaos, tapered grease-pencil strokes, Movie Maker render path, Android export.

## 14. UPDATING THE INSTALLED APP (Android)
- Install a new build over the old one: no uninstall, and app data is kept. Android allows this only if the package name (`com.galaughxy.studio`) and signing key match, and the new `version/code` is higher than the installed one.
- Bump `version/code` in `godot/export_presets.cfg` every release (current: 3, version 0.3.0).
- Keep the signing key: `~/Library/Application Support/Godot/keystores/debug.keystore`. Never delete or regenerate it, or updates will fail and the phone will need a fresh install.

## 15. REGRESSION TEST (run before every build)
- `cd godot && /Applications/Godot.app/Contents/MacOS/Godot --headless --path . -- --test` drives keys, HUD buttons, touch joystick, look-drag, fly, flood stages, map and portals, then prints `RESULT: ALL PASS` or the failures.
- Pending art direction (new spec): characters, props and rooms move from voxel cubes to smooth stylized meshes. Decide per asset before converting, and keep the test green.

## 16. SMOOTH STYLISED PIPELINE (current — replaces the voxel look)
- Shapes are signed-distance functions (`godot/scripts/Sdf.gd`: rounded boxes, capsules, ellipsoids, cylinders, smooth blends). `SmoothMesh.gd` extracts smooth surfaces from them (surface nets) with normals from the field and per-vertex colour. Ink is traced strokes from `InkStroke.gd`.
- Characters: `RoboParts.gd` and `FrogModel.gd` define parts with a pivot, a bounding box and a colour function. Parts are model-space; the mesh is shifted to its pivot.
- Scenes: `KitchenWorld.gd`, `GardenWorld.gd`, `PondWorld.gd` (smooth height field for the ground). Scatter uses MultiMesh (reeds, pads, flowers).
- The voxel builders (`VoxelMesh.gd`, `VoxelBuild.gd`) are removed.
- Frog ground follows the smooth height field. Water is a translucent plane at -0.06 m in the pond.

- **Grease-pencil outlines (all objects):** see section 20 — traced on the GPU every frame (`InkStroke.gd` + `shaders/ink_contour.gdshader`).

## 17. PERFECT STYLE — HARD RULE FOR EVERY MODEL (current, overrides anything earlier)
- **Every model is smooth, symmetrical and perfect.** No faceting, no bumps, no jagged silhouettes, no lopsided shapes. This applies to characters, props, rooms and anything spawned later.
- **Symmetry:** build left/right parts by mirroring one definition (`for s in [1, -1]`), and keep bounding boxes symmetric about the mirror plane so the sample grid is mirrored too.
- **Smoothness:** room and prop shapes come from SDFs through `SmoothMesh.build`, which snaps every vertex exactly onto the surface (`_snap`). Roster characters come from Blender (section 18) built only from high-segment smooth primitives. Pick a grid step fine enough that the smallest rounding radius spans at least 5–6 cells (robo uses 0.012 m for 0.03–0.07 m radii).
- **Clean contact:** parts never cut into the ground or each other where the cut would show. Feet and bases sit a few millimetres above the floor; joined parts blend with `Sdf.smin` instead of crossing.
- Check every new or changed model in a close-up screenshot before committing.

## 18. CAST, MAPS & EXPANSIONS (current)
- **Roster (20 characters):** `tools/generate_roster.py` builds every character in Blender from smooth primitives (bevelled boxes/cylinders, size-scaled spheres, shade smooth + weighted normals), mirrors every left/right part, and exports `godot/assets/models/characters/<id>.glb`. Regenerate: `/Applications/Blender.app/Contents/MacOS/Blender --background --factory-startup --python tools/generate_roster.py -- godot/assets/models/characters [ids…]`. Contact sheet: `tools/preview_roster.py -- <glb dir> <out.png>`. This supersedes the "no imported meshes / no GLB" notes in sections 10 and 12 for characters only; no textures or bitmaps are used.
- **Shared joints:** every character has `Root > Hips > Spine > Head, Arm_L/R, Leg_L/R`, a face (`Eye_L/R`, optional `Brow_L/R`, `Jaw` or `Mouth`), and named gag joints (`Toast`, `Steam`, `Rotor_*`, `Tentacle_*`, `Wheel_*`, `Ear_*`, `Ball_*`, `Cheek_*`, `Mustache`, `Flame`, `Tail`, `Antenna_*`). `godot/scripts/Puppet.gd` animates any of them procedurally (walk, panic, expressions 1–6, lip-sync, gags, flags `flop` / `spin_in_flood` / `squash_hop` / `stretch_turn`). A new character only needs a generator function plus a `characters.json` entry.
- **Registries:** `godot/data/characters.json` (id, name, category Robo/Animal/Hybrid, model, scale, badge colour, icon, gag, flags) and `godot/data/maps.json` (id, aliases, title, scene, sky, lighting, host, bounds, flood levels, cameras, portals, expansions).
- **Maps:** `Main.tscn` is a persistent studio root (camera, HUD, `CastRoot`, On Twos clock). Maps are `godot/scenes/maps/<id>.tscn` with a script extending `MapBase` (build, ground height, `Spawn*` markers, expansions) and load into `MapContainer` with a fade. Add a map: one `.tscn` + one script + one `maps.json` entry. Maps: Overflowing Kitchen (+ Backyard Patio), Mac Garage Lab (+ Basement Server Room), Skyline Rooftop Terrace (+ Helipad), Pond Life, Backyard Garden.
- **Cast drawer (`I` / 🎭 Cast):** filter pills All/Robos/Animals/Hybrids, search, 4-column card grid; tap a card to spawn (pop-in) and take control. `Tab`, the Next button, or tapping a character on screen switches control between the map's host and the cast. Despawn Selected / Clear Cast. The cast follows you to the next map's spawn points.
- **Maps drawer (`M` / 🗺 Maps):** a card per map with its chaos keys and Load Map; expansion toggles appear under the current map.
- **12fps On Twos (`O` / 12fps claw):** character poses and positions update 12 times a second; the camera stays smooth.
- Keys: see section 19 (they changed when the director arrived).
- Debug flags: `-- --scene <id> --expand --roster --open cast|maps --cam x,y,z,tx,ty,tz,fov --shot <png>`.

## 19. AUDIO-FIRST DIRECTOR, VOICE & OVERDUB (current — supersedes older key lists)
- **Controls are InputMap actions** (`godot/scripts/Controls.gd`). Keyboard keys bind to actions; touch buttons call `Input.action_press/release`; the Director calls `Main.act() / walk_to() / say()`, the same functions the input path uses, so humans and the AI produce identical movement, sound and On Twos animation.
- **Keys:** WASD/arrows move · Space talk (hold; rises in fly) · J hop · 1–6 expressions · F wave · G point · V facepalm · B shrug · Q/7 drip · E/8 surge · 9 flood · 0 drain · Z/X/C static/slider/drone · N fly · M maps · I cast · P director · T timeline · K play/pause · R overdub · Tab next character · O 12fps On Twos · Y PNG · Esc close / stop. (F was hop and P was PNG before; chaos left R/T for overdub/timeline.)
- **Voice** (`Voice.gd`): `DialogueBus` = PitchShift → BandPass → SpectrumAnalyzer. Each character has `voice: {pitch, filter}` in `characters.json` (`none` / `radio` / `tiny_squeak` / `deep_bot`). Speech energy in 200–3000 Hz drives the mouth and head bounce, sampled at 12 fps. Holding Talk plays a synthesized babble through the character's preset (live test input). A line with no clip uses the procedural bounce for 0.065 s per character.
- **Audio-first folder convention:** dialogue lives in `godot/assets/audio/<folder>/` (ep01 uses `godot/assets/audio/ep01/`), referenced from events as `"audio": "ep01/01_bear.wav"`. Record `.wav` or `.ogg` with exactly those names, then run `python3 tools/sync_audio_manifest.py --check` — it writes `godot/data/audio_manifest.json` (exact durations) and flags missing clips, overlapping lines and too-short shots. Shot timing adapts automatically; never hand-edit timestamps to fit a recording.
- **Episodes** (`godot/data/episodes/*.json`, `DirectorController.gd`): `episode_id`, `map`, `cast` (marks: `at`, `yaw`, `expr`), `shots[]` with `id`, `name`, `cam`, `cam_target`, `cut` (0 hard / 0.25 ease), `shake`, `push`, `auto_advance_on_audio`, `min_duration`, `events[]`. Events: `move` `[x,y,z]`, `expr`, `emote`, `hop`, `talk` (`audio`, `text`, optional `duration`), `chaos` 0–3, `cam`, `shake`, `face`. A shot lasts max(min_duration, last event + 0.6, every line's end + 0.35).
- **Determinism:** each shot starts from a snapshot of the cast (taken when first reached, or rebuilt by silently fast-forwarding earlier shots at a fixed 1/60 s). Retake, loop, jump and scrub restore the snapshot and fast-forward, so the same second always looks the same. Hops are analytic arcs and the animation clock resets per shot to keep this true.
- **Cameras:** `wide_static`, `closeup_actor` (42° lens on the target / speaker / controlled character's face), `slider_push` (map slider track, `push` 0–100 %, aims at the subject), `follow_shoulder`, `drone_intro`. Shake is a decaying trauma impulse. Free fly is disabled while the Director plays.
- **Director drawer (P):** episodes with Select / Play Episode (clean HUD: only subtitles show; tap or Esc = Stop / Take Over), per-shot Play and Loop, Retake, Save Episode.
- **Timeline bar (T):** shot pills + Play All, play/pause (K), scrub slider, loop, `● OVERDUB` (R), Save Episode. Overdub records the controlled character's live input (move marks every 0.25 s, expressions, emotes, hops, talk holds with duration) plus camera cuts and chaos, at the exact shot time. On commit it removes only that actor's events in the same channel inside the recorded range (channels: move, expr, gesture, talk; cam, chaos) and keeps everything else. Save writes `user://episodes/<id>.json`, and also `godot/data/episodes/` when running from the project (desktop / Android editor).
- **Headless Mac video export (Movie Maker):**
  `/Applications/Godot.app/Contents/MacOS/Godot --path godot --write-movie ~/Movies/ep01.avi --fixed-fps 60 -- --episode ep01_kitchen_disaster --quit-after-episode`
  It opens a window (rendering needs the GPU) and records at the project window size (1280×720; `--resolution` is ignored by Movie Maker), with the dialogue mixed in. `--at-shot <shot_id>` starts mid-episode. Convert: `ffmpeg -i ep01.avi -c:v libx264 -pix_fmt yuv420p -crf 20 ep01.mp4`. The earlier test ran at about 37 % of real time.
- **Asset sourcing rule (permanent):** never ask the user to download files by hand. Either generate smooth stylised `.glb` models with headless Blender scripts in `tools/` (Mac Studio palette), or fetch CC0 packs / HDRIs with `curl` (Kenney, Poly Pizza, Poly Haven) and normalise them with `tools/restyle_assets.py` (scale to height, feet on the floor, palette colours, smooth + weighted normals, textures removed; `--character` adds the shared joint layout) into `godot/assets/`. Keep the no-bitmap rule: restyle strips textures.
- **Android export:** non-resource files must be listed in the preset's `include_filter` (`data/*.json, data/episodes/*.json`), or the APK starts without characters, maps and episodes.
- **Tests:** `--test` covers 80+ checks, including scrub determinism and overdub merging. Run it once without `--headless` as well: only real audio output exercises the spectrum lip-sync check (`assets/audio/_selftest/babble.wav`).

## 20. STUDIO VINYL — THE ONE STYLE (hard rule, current)
- **Palette:** only the seven Mac Studio colours (`#E5E7EB` silver, `#2C2E33` space gray, `#F5F2EB` cream, `#4A90E2` Bondi blue, `#FF5F56` coral, `#FFBD2E` amber, `#27C93F` mint), each in three values: light (42 % toward white), base, shade (32 % darker). `godot/scripts/Style.gd` snaps every SDF vertex colour, every imported material and every scatter colour to these 21 swatches, so nothing off-palette can appear. Pick swatches deliberately (`Style.swatch("coral", "light")`); never rely on snapping a gradient.
- **Shading:** cel (toon) diffuse + toon specular + soft rim on every lit material (`Style.toon`). Glow = `Style.glow`. Lighting: ambient 0.62 white + sun 0.40, so lit faces sit on the swatch and shadow faces one value darker; skies are palette tints.
- **Surfaces:** flat swatch areas only: no speckle, noise, gradients or textures. Two-tone banding (e.g. darker cap on the frog's back) is fine.
- **Outlines:** one dark-red line, traced on the GPU every frame. Every triangle that can hold part of the silhouette is a quad carrying its three corners; the vertex shader finds where `dot(normal, camera - point)` changes sign and draws that piece as a round-capped, anti-aliased, constant-pixel-width segment (2.4 px at 1080p). Shared edges give identical crossing points, so pieces join into one line that stays glued to the silhouette at any angle. Flat triangles are skipped at setup. Boil = 12 fps sideways noise. Measured: 20 characters + a map at 145 fps on the M5.
- Old notes about CPU-traced strokes (section 16) and natural colours are superseded.

## 21. MAP KIT, CHAOS FX & THE 15 NEW MAPS (current)
- **Generator:** `tools/generate_15_maps.py` (Blender, headless) builds every new map from one smooth-primitive kit in Studio Vinyl swatches: `/Applications/Blender.app/Contents/MacOS/Blender --background --factory-startup --python tools/generate_15_maps.py -- [map_id ...]` → `godot/assets/maps/<id>/<id>.glb` + `<id>__<expansion>.glb`. It reuses the roster kit (`generate_roster.Char`) with Godot coordinates (+Z toward camera, back wall at -Z).
- **Naming contract** (read by `godot/scripts/maps/GlbMap.gd`): `Set_*` inked set dressing · `Flat_*` floors/tiles (no ink) · `Glow_*` emissive (flicker target) · `Prop_<group>_<n>` movable prop, pivot at its base · `Spawn_<n>` spawn marks.
- **No `-rigid` physics props, no downloaded CC0 kits (decision):** physics bodies break deterministic scrubbing/retakes, and third-party kits are faceted and textured (breaking sections 17 and 20). Props are moved by deterministic chaos FX instead. `tools/restyle_assets.py` stays available if a CC0 model is ever needed.
- **Registering a map:** `godot/scenes/maps/<id>.tscn` (a Node3D with `GlbMap.gd`, `map_id = "<id>"`) + an entry in `maps.json` with `chaos_stages` (three: name, key, flood, optional `water` colour, `fx` list), optional `idle` FX (always on) and `hidden` prop groups (shown by a `show` FX).
- **Chaos FX** (pure functions of time since the stage began, so they replay on scrub/retake and continue across cuts): `topple`, `scatter`, `drop`, `float`, `spin`, `orbit`, `bob`, `conveyor`, `show`, `melt`, `wobble`, `gust`, `flicker`, `swarm` (rush / fountain / tornado / circle), `fog`, `shake`, `lowgrav`, `slip`. Stages stack; `0` resets everything to rest. Shot snapshots store each stage's elapsed time.
- **Keys:** chaos stays Q/7 · E/8 · 9 · 0 (the spec's Q/W/E collides with W = move). The maps drawer lists each map's gags.
- **All 15 new maps built (20 total):** iFruit Keynote Store (+ Genius Repair Bar), aisle 7 Supermarket (+ Bakery & Deli), Bondi Blue Diner (+ Drive-Thru), Hot-Take Podcast Set (+ Green-Screen Room), Tranquility Mac Base (+ Rover Pad), Maple Street Cul-de-Sac (+ Treehouse), Sunday Living Room (+ Sunroom nook), St. Glitch Clinic (+ MRI Room), Cubicle Farm (+ Glass Boardroom), Pixel-Smooth Pier (+ Arcade Shack), 8-Bit Vinyl Arcade (+ Bowling Alley Lane), The Express Dining Car (+ Locomotive Engine Cab; scenery scrolls past the windows as an idle conveyor), Judge Bot's Courtroom (+ Jury Room), The Minimalist Museum (+ Skylight Vault), Dusty Clockwork Attic (+ Secret Bell Tower).
- **Categories:** every map has `category` (`Indoor`, `Outdoor`, `Sci-Fi & Wild`) in `maps.json`; the Maps drawer (M) shows pills `All (20) · Indoor · Outdoor · Sci-Fi & Wild` and a 2-column scrollable grid of map cards (category, gags, expansion, Load Map; expansion switches on the current map).
- **Lighting FX:** `dim` (blackout; `glows_off`, `stutter` for power coughs) and `flash` (lightning double pulse) drive the studio's ambient/sun/sky through `Main._apply_chaos_light`. `swarm` accepts `colors` for multicolour confetti.
- **Checks:** `Godot --headless --path godot --import` and `--quit` report zero errors; `-- --test` runs 120 checks.
- Expansions must sit inside the camera's view of the set (not behind walls or in front of the lens).
