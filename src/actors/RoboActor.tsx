import type { ThreeEvent } from '@react-three/fiber';
import { useFrame } from '@react-three/fiber';
import gsap from 'gsap';
import { useEffect, useMemo, useRef } from 'react';
import * as THREE from 'three';
import { getActorMark, runtime } from '../engine/runtime';
import { VoxelModelMesh } from '../engine/VoxelModelMesh';
import { vbox, vmerge } from '../engine/voxels';
import { voiceFX } from '../engine/VoiceFXEngine';
import { useStudioStore } from '../store/useStudioStore';
import type { Episode, Expression, SceneObject } from '../types';
import { LED_FACES, ledPixels } from './ledFaces';

const D2R = Math.PI / 180;
const WALK_SPEED = 1.7;
const TALK_THRESHOLD = 0.035;
const ROBO_SCALE = 0.7;
const TWOS_FPS = 12;

/** Original robo-character, built entirely from 0.1 micro-voxels. */
function buildRobo(color: string) {
  const dark = '#1b1f2a';
  const trim = '#f4f6f8';
  return {
    leg: vmerge(vbox(-1, 0, -3, -1, -1, 0, '#2c3442'), vbox(-1, 0, -3, -3, -1, 1, trim)),
    body: vmerge(
      vbox(-3, 2, 0, 5, -2, 1, color),
      vbox(-2, 1, 1, 3, 2, 2, dark),
      vbox(-1, 0, 2, 2, 2, 2, '#ffcc33', true), // chest heart LED
      vbox(-3, 2, 0, 0, -2, 1, '#2c3442'),
    ),
    arm: vmerge(vbox(-1, 0, -4, -1, -1, 0, color), vbox(-1, 0, -5, -5, -1, 0, trim)),
    head: vmerge(
      vbox(-5, 4, 0, 9, -4, 3, color),
      vbox(-4, 3, 1, 8, 3, 3, dark), // screen bezel
      vbox(-6, -6, 3, 6, -1, 0, trim), // ear bolts
      vbox(5, 5, 3, 6, -1, 0, trim),
      vbox(0, 0, 10, 12, 0, 0, '#9aa4b2'), // antenna
      vbox(0, 0, 13, 13, 0, 0, '#ff3d7f', true),
    ),
  };
}

const ledGeo = new THREE.BoxGeometry(0.088, 0.088, 0.02);
const ledMat = new THREE.MeshBasicMaterial({ toneMapped: false });
const LED_OFF = new THREE.Color('#0d1424');
const _c = new THREE.Color();
const _m = new THREE.Matrix4();

export function RoboActor({
  obj,
  perform,
  episode,
  onSelect,
}: {
  obj: SceneObject;
  perform: boolean;
  episode: Episode;
  onSelect?: (e: ThreeEvent<MouseEvent>) => void;
}) {
  const root = useRef<THREE.Group>(null);
  const rig = useRef<THREE.Group>(null);
  const head = useRef<THREE.Group>(null);
  const armL = useRef<THREE.Group>(null);
  const armR = useRef<THREE.Group>(null);
  const legL = useRef<THREE.Group>(null);
  const legR = useRef<THREE.Group>(null);
  const led = useRef<THREE.InstancedMesh>(null);

  const parts = useMemo(() => buildRobo(obj.color ?? '#4aa3df'), [obj.color]);
  const sim = useRef({ yaw: 0, yawVel: 0, lastStep: -1, face: '', expr: 'DEADPAN' as Expression });

  // Keep the live mark in sync with the staged mark.
  useEffect(() => {
    const m = getActorMark(obj.id, obj.pos);
    m.pos.set(...obj.pos);
    m.yaw = obj.rot[1] * D2R;
    sim.current.yaw = m.yaw;
  }, [obj.id, obj.pos, obj.rot]);

  useEffect(() => {
    const g = root.current!;
    runtime.objects.set(obj.id, g);
    // LED grid layout (8x8 on the head screen)
    const mesh = led.current!;
    for (let i = 0; i < 64; i++) {
      const col = i % 8;
      const row = Math.floor(i / 8);
      mesh.setMatrixAt(i, _m.makeTranslation(-0.35 + col * 0.1, 0.85 - row * 0.1, 0.41));
      mesh.setColorAt(i, LED_OFF);
    }
    mesh.instanceMatrix.needsUpdate = true;
    return () => {
      if (runtime.objects.get(obj.id) === g) runtime.objects.delete(obj.id);
    };
  }, [obj.id]);

  useFrame((state, dt) => {
    const st = useStudioStore.getState();
    const t = state.clock.elapsedTime;
    const s = sim.current;
    const isActive = st.activeActorId === obj.id;
    const expr: Expression = st.expressions[obj.id] ?? 'DEADPAN';
    const mark = getActorMark(obj.id, obj.pos);

    // ── simulation (always smooth) ──
    let moving = 0;
    if (perform && isActive) {
      let mx = runtime.stick.x;
      let mz = runtime.stick.z;
      const k = runtime.keys;
      if (k.has('w') || k.has('arrowup')) mz -= 1;
      if (k.has('s') || k.has('arrowdown')) mz += 1;
      if (k.has('a') || k.has('arrowleft')) mx -= 1;
      if (k.has('d') || k.has('arrowright')) mx += 1;
      const len = Math.hypot(mx, mz);
      if (len > 0.08) {
        const n = Math.max(1, len);
        const b = episode.bounds;
        mark.pos.x = THREE.MathUtils.clamp(mark.pos.x + (mx / n) * WALK_SPEED * dt, b.minX + 0.35, b.maxX - 0.35);
        mark.pos.z = THREE.MathUtils.clamp(mark.pos.z + (mz / n) * WALK_SPEED * dt, b.minZ + 0.35, b.maxZ - 0.35);
        mark.yaw = Math.atan2(mx, mz);
        moving = Math.min(1, len);
      }
    }
    mark.moving = THREE.MathUtils.damp(mark.moving, moving, 10, dt);

    // Spring turn → snappy overshoot (Spider-Verse style).
    let dy = mark.yaw - s.yaw;
    dy = Math.atan2(Math.sin(dy), Math.cos(dy));
    const kStiff = st.snappiness;
    const damping = 2 * Math.sqrt(kStiff) * (1 - st.overshoot * 0.85);
    s.yawVel += (dy * kStiff - s.yawVel * damping) * Math.min(dt, 1 / 30);
    s.yaw += s.yawVel * Math.min(dt, 1 / 30);

    // ── pose output: 12fps "On Twos" holds poses, 60fps writes every frame ──
    const step = Math.floor(t * TWOS_FPS);
    if (st.onTwos && step === s.lastStep) return;
    s.lastStep = step;
    const tq = st.onTwos ? step / TWOS_FPS : t;

    const g = root.current!;
    if (perform) {
      g.position.set(mark.pos.x, mark.pos.y, mark.pos.z);
      g.rotation.y = s.yaw;
    }

    // ── lip-sync, locked to the active expression ──
    const level = isActive && perform ? voiceFX.getLevel() : 0;
    const talking = isActive && perform && (st.talkHeld || level > TALK_THRESHOLD);
    let open = false;
    if (talking) {
      open =
        st.talkHeld && level <= TALK_THRESHOLD
          ? Math.sin(tq * 15) + Math.sin(tq * 23) * 0.5 > -0.1
          : level > TALK_THRESHOLD * (1.1 + 0.5 * Math.sin(tq * 13));
    }
    const panicFlash = expr === 'PANIC' && Math.floor(tq * 6) % 2 === 0;
    const faceKey = `${expr}${open}${panicFlash}`;
    if (faceKey !== s.face) {
      s.face = faceKey;
      const px = ledPixels(expr, open);
      _c.set(LED_FACES[expr].color);
      if (panicFlash) _c.multiplyScalar(0.55);
      const mesh = led.current!;
      px.forEach((on, i) => mesh.setColorAt(i, on ? _c : LED_OFF));
      mesh.instanceColor!.needsUpdate = true;
    }
    if (expr !== s.expr) {
      s.expr = expr;
      gsap.fromTo(head.current!.scale, { x: 1.15, y: 0.85, z: 1.15 }, { x: 1, y: 1, z: 1, duration: 0.4, ease: 'elastic.out(1.3, 0.35)' });
    }

    // ── head ──
    const h = head.current!;
    h.rotation.x = (talking ? Math.sin(tq * 9) * 0.08 : 0) + (expr === 'ANGRY' ? 0.12 : 0) + (expr === 'SHOCKED' ? -0.1 : 0);
    h.rotation.z = expr === 'SMIRK' ? 0.12 : expr === 'PANIC' ? Math.sin(tq * 20) * 0.08 : 0;
    h.position.y = 0.9 + (talking ? Math.abs(Math.sin(tq * 9)) * 0.03 : 0) + Math.sin(tq * 1.6) * 0.01;

    // ── limbs ──
    const walk = mark.moving;
    const swing = Math.sin(tq * 11) * 0.75 * walk;
    legL.current!.rotation.x = swing;
    legR.current!.rotation.x = -swing;
    let aL = -swing * 0.8;
    let aR = swing * 0.8;
    let zL = 0.08;
    let zR = -0.08;
    if (expr === 'PANIC') {
      zL = 2.6 + Math.sin(tq * 17) * 0.4;
      zR = -2.6 - Math.sin(tq * 17 + 1) * 0.4;
      aL = aR = 0;
    } else if (expr === 'HAPPY') {
      zL = 0.6 + Math.sin(tq * 6) * 0.25;
      zR = -0.6 - Math.sin(tq * 6) * 0.25;
    } else if (expr === 'ANGRY') {
      zL = 0.6;
      zR = -0.6;
      aL = aR = -0.7;
    } else if (expr === 'SHOCKED') {
      zL = 1.3;
      zR = -1.3;
    } else if (talking) {
      aR = -0.6 + Math.sin(tq * 5) * 0.35;
    }
    armL.current!.rotation.set(aL, 0, zL);
    armR.current!.rotation.set(aR, 0, zR);

    const hop = expr === 'HAPPY' ? Math.abs(Math.sin(tq * 6)) * 0.06 : 0;
    rig.current!.position.y = hop + Math.abs(Math.sin(tq * 11)) * 0.04 * walk;
  });

  return (
    <group
      ref={root}
      name={`actor:${obj.id}`}
      position={obj.pos}
      rotation={[obj.rot[0] * D2R, obj.rot[1] * D2R, obj.rot[2] * D2R]}
      scale={obj.scale}
      visible={obj.visible}
      onClick={onSelect}
    >
      <group ref={rig} scale={ROBO_SCALE}>
        <group ref={legL} position={[-0.15, 0.3, 0]}>
          <VoxelModelMesh voxels={parts.leg} />
        </group>
        <group ref={legR} position={[0.15, 0.3, 0]}>
          <VoxelModelMesh voxels={parts.leg} />
        </group>
        <group position={[0, 0.3, 0]}>
          <VoxelModelMesh voxels={parts.body} />
        </group>
        <group ref={armL} position={[-0.4, 0.85, 0]}>
          <VoxelModelMesh voxels={parts.arm} />
          <object3D name="socket:handSocketL" position={[-0.05, -0.55, 0]} />
        </group>
        <group ref={armR} position={[0.4, 0.85, 0]}>
          <VoxelModelMesh voxels={parts.arm} />
          <object3D name="socket:handSocketR" position={[0.05, -0.55, 0]} />
        </group>
        <group ref={head} position={[0, 0.9, 0]}>
          <VoxelModelMesh voxels={parts.head} />
          <instancedMesh ref={led} args={[ledGeo, ledMat, 64]} />
          <object3D name="socket:headSocket" position={[0, 1.0, 0]} />
        </group>
      </group>
    </group>
  );
}

/** Hop action: deterministic gsap arc on the actor's live mark. */
export function hop(actorId: string | null) {
  if (!actorId) return;
  const m = runtime.actors.get(actorId);
  if (!m || gsap.isTweening(m.pos)) return;
  const floor = 0;
  gsap
    .timeline()
    .to(m.pos, { y: floor + 0.55, duration: 0.22, ease: 'power2.out' })
    .to(m.pos, { y: floor, duration: 0.26, ease: 'bounce.out' });
  void voiceFX.sfx('slideWhistle');
}

export const ACTOR_TYPES = { robo: RoboActor } as const;
