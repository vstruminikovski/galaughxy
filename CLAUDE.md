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
