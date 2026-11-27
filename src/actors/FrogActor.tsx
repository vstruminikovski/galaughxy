import type { ThreeEvent } from '@react-three/fiber';
import { useFrame } from '@react-three/fiber';
import gsap from 'gsap';
import { useEffect, useMemo, useRef } from 'react';
import * as THREE from 'three';
import { getActorMark, runtime } from '../engine/runtime';
import { VoxelModelMesh } from '../engine/VoxelModelMesh';
import { voiceFX } from '../engine/VoiceFXEngine';
import { useStudioStore } from '../store/useStudioStore';
import type { Episode, Expression, SceneObject } from '../types';
import { buildFrogParts, FROG_VOXEL } from './frogModel';

const D2R = Math.PI / 180;
const HOP_SPEED = 1.1;
const TALK_THRESHOLD = 0.035;
const TWOS_FPS = 12;

/** Lid angle per expression (0 = upper half covered, + closes, − opens), tilt and eye bulge. */
const LIDS: Record<Expression, { l: number; r: number; tilt: number; bulge: number }> = {
  DEADPAN: { l: -0.3, r: -0.3, tilt: 0, bulge: 1 },
  SMIRK: { l: -0.2, r: -1.0, tilt: 0.15, bulge: 1 },
  PANIC: { l: -1.45, r: -1.45, tilt: 0, bulge: 1.22 },
  ANGRY: { l: -0.4, r: -0.4, tilt: 0.5, bulge: 0.95 },
  HAPPY: { l: -0.05, r: -0.05, tilt: -0.25, bulge: 1 },
  SHOCKED: { l: -1.55, r: -1.55, tilt: 0, bulge: 1.3 },
};

/** Bog: a voxel hybrid frog (organic body, robot LEDs and antenna). Animation is deterministic. */
export function FrogActor({
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
  const parts = useMemo(() => buildFrogParts(), []);
  const root = useRef<THREE.Group>(null);
  const rig = useRef<THREE.Group>(null);
  const body = useRef<THREE.Group>(null);
  const jaw = useRef<THREE.Group>(null);
  const eyeL = useRef<THREE.Group>(null);
  const eyeR = useRef<THREE.Group>(null);
  const lidL = useRef<THREE.Group>(null);
  const lidR = useRef<THREE.Group>(null);
  const armL = useRef<THREE.Group>(null);
  const armR = useRef<THREE.Group>(null);
  const legL = useRef<THREE.Group>(null);
  const legR = useRef<THREE.Group>(null);

  const sim = useRef({ yaw: 0, yawVel: 0, lastStep: -1, phase: 0, expr: 'DEADPAN' as Expression, jaw: 0 });

  useEffect(() => {
    const m = getActorMark(obj.id, obj.pos);
    m.pos.set(obj.pos[0], 0, obj.pos[2]);
    m.yaw = obj.rot[1] * D2R;
    sim.current.yaw = m.yaw;
  }, [obj.id, obj.pos, obj.rot]);

  useEffect(() => {
    const g = root.current!;
    runtime.objects.set(obj.id, g);
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

    // ── locomotion: frogs hop, they don't walk ──
    let moving = 0;
    if (perform && isActive && st.camRig !== 'free') {
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
        const air = Math.max(0, Math.sin(s.phase));
        const sp = HOP_SPEED * (0.3 + air * 1.6);
        mark.pos.x = THREE.MathUtils.clamp(mark.pos.x + (mx / n) * sp * dt, b.minX + 0.3, b.maxX - 0.3);
        mark.pos.z = THREE.MathUtils.clamp(mark.pos.z + (mz / n) * sp * dt, b.minZ + 0.3, b.maxZ - 0.3);
        mark.yaw = Math.atan2(mx, mz);
        moving = Math.min(1, len);
      }
    }
    mark.moving = THREE.MathUtils.damp(mark.moving, moving, 8, dt);
    s.phase = mark.moving > 0.05 ? s.phase + dt * 9 : THREE.MathUtils.damp(s.phase, Math.ceil(s.phase / Math.PI) * Math.PI, 8, dt);

    let dy = mark.yaw - s.yaw;
    dy = Math.atan2(Math.sin(dy), Math.cos(dy));
    const kStiff = st.snappiness;
    const damping = 2 * Math.sqrt(kStiff) * (1 - st.overshoot * 0.85);
    const h = Math.min(dt, 1 / 30);
    s.yawVel += (dy * kStiff - s.yawVel * damping) * h;
    s.yaw += s.yawVel * h;

    // ── On Twos gate ──
    const step = Math.floor(t * TWOS_FPS);
    if (st.onTwos && step === s.lastStep) return;
    s.lastStep = step;
    const tq = st.onTwos ? step / TWOS_FPS : t;

    const ground = episode.ground ? episode.ground(mark.pos.x, mark.pos.z) : 0;
    const water = (episode.waterRest ?? -99) + runtime.waterLevel * (episode.floodScale ?? 1);
    const swimming = water > ground + 0.12;
    const hopY = Math.max(0, Math.sin(s.phase)) * 0.13 * mark.moving;
    const g = root.current!;
    if (perform) {
      const y = swimming ? water - 0.17 + Math.sin(tq * 2.2) * 0.012 : ground + hopY + mark.pos.y;
      g.position.set(mark.pos.x, y, mark.pos.z);
      g.rotation.y = s.yaw;
    }

    // ── lip-sync: jaw drops in proportion to voice, expression stays locked ──
    const level = isActive && perform ? voiceFX.getLevel() : 0;
    const talking = isActive && perform && (st.talkHeld || level > TALK_THRESHOLD);
    let jawTarget = 0;
    if (talking) {
      jawTarget =
        st.talkHeld && level <= TALK_THRESHOLD
          ? Math.max(0, Math.sin(tq * 14) + Math.sin(tq * 21) * 0.5) * 0.24
          : Math.min(0.42, level * 4.5);
    }
    if (expr === 'SHOCKED') jawTarget = Math.max(jawTarget, 0.28);
    if (expr === 'PANIC') jawTarget = Math.max(jawTarget, 0.12 + Math.abs(Math.sin(tq * 9)) * 0.1);
    s.jaw = st.onTwos ? jawTarget : THREE.MathUtils.damp(s.jaw, jawTarget, 25, dt);
    jaw.current!.rotation.x = s.jaw;

    if (expr !== s.expr) {
      s.expr = expr;
      gsap.fromTo(rig.current!.scale, { x: 1.08, y: 0.9, z: 1.08 }, { x: 1, y: 1, z: 1, duration: 0.45, ease: 'elastic.out(1.2, 0.35)' });
    }

    // ── eyes + lids (the expression lives here) ──
    const L = LIDS[expr];
    const blink = tq % 3.7 < 0.12 ? 1.5 : 0;
    lidL.current!.rotation.set(Math.max(L.l, blink), 0, L.tilt);
    lidR.current!.rotation.set(Math.max(L.r, blink), 0, -L.tilt);
    const bulge = L.bulge + (expr === 'PANIC' ? Math.sin(tq * 25) * 0.04 : 0);
    eyeL.current!.scale.setScalar(bulge);
    eyeR.current!.scale.setScalar(bulge);

    // ── body: breathing throat, angry puff, talk bob ──
    const puff = expr === 'ANGRY' ? 1.12 + Math.sin(tq * 3) * 0.02 : 1 + Math.sin(tq * 2.4) * 0.012;
    body.current!.scale.set(puff, 1 + (puff - 1) * 0.6, puff);
    rig.current!.rotation.x = (talking ? -Math.abs(Math.sin(tq * 8)) * 0.05 : 0) - hopY * 1.2;
    rig.current!.position.y = expr === 'HAPPY' ? Math.abs(Math.sin(tq * 5)) * 0.04 : 0;
    rig.current!.position.x = expr === 'PANIC' ? Math.sin(tq * 30) * 0.008 : 0;

    // ── limbs ──
    const air = Math.max(0, Math.sin(s.phase)) * mark.moving;
    const kick = swimming ? Math.sin(tq * 6) * 0.6 : 0;
    legL.current!.rotation.x = -air * 1.1 + kick;
    legR.current!.rotation.x = -air * 1.1 - kick;
    let armX = air * 0.7;
    let armZ = 0;
    if (expr === 'PANIC') {
      armX = -1.2 + Math.sin(tq * 16) * 0.5;
      armZ = 0.6;
    } else if (expr === 'HAPPY') armX = -0.5 + Math.sin(tq * 5) * 0.3;
    else if (talking) armX = -0.25 + Math.sin(tq * 4) * 0.2;
    armL.current!.rotation.set(armX, 0, armZ);
    armR.current!.rotation.set(expr === 'PANIC' ? -1.2 - Math.sin(tq * 16) * 0.5 : armX, 0, -armZ);
  });

  const at = (p: [number, number, number]) =>
    [p[0] * FROG_VOXEL, p[1] * FROG_VOXEL, p[2] * FROG_VOXEL] as [number, number, number];

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
      <group ref={rig}>
        <group ref={body}>
          <VoxelModelMesh voxels={parts.body.voxels} size={FROG_VOXEL} />
        </group>
        <group ref={jaw} position={at(parts.jaw.pivot)}>
          <VoxelModelMesh voxels={parts.jaw.voxels} size={FROG_VOXEL} />
        </group>
        <group ref={eyeL} position={at(parts.eyeL.pivot)}>
          <VoxelModelMesh voxels={parts.eyeL.voxels} size={FROG_VOXEL} />
        </group>
        <group ref={eyeR} position={at(parts.eyeR.pivot)}>
          <VoxelModelMesh voxels={parts.eyeR.voxels} size={FROG_VOXEL} />
        </group>
        <group ref={lidL} position={at(parts.lidL.pivot)}>
          <VoxelModelMesh voxels={parts.lidL.voxels} size={FROG_VOXEL} />
        </group>
        <group ref={lidR} position={at(parts.lidR.pivot)}>
          <VoxelModelMesh voxels={parts.lidR.voxels} size={FROG_VOXEL} />
        </group>
        <group ref={armL} position={at(parts.armL.pivot)}>
          <VoxelModelMesh voxels={parts.armL.voxels} size={FROG_VOXEL} />
        </group>
        <group ref={armR} position={at(parts.armR.pivot)}>
          <VoxelModelMesh voxels={parts.armR.voxels} size={FROG_VOXEL} />
        </group>
        <group ref={legL} position={at(parts.legL.pivot)}>
          <VoxelModelMesh voxels={parts.legL.voxels} size={FROG_VOXEL} />
        </group>
        <group ref={legR} position={at(parts.legR.pivot)}>
          <VoxelModelMesh voxels={parts.legR.voxels} size={FROG_VOXEL} />
        </group>
      </group>
    </group>
  );
}
