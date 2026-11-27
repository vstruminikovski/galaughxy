import { useGLTF } from '@react-three/drei';
import type { ThreeEvent } from '@react-three/fiber';
import { useFrame } from '@react-three/fiber';
import gsap from 'gsap';
import { useEffect, useMemo, useRef } from 'react';
import * as THREE from 'three';
import { getActorMark, runtime } from '../engine/runtime';
import { voiceFX } from '../engine/VoiceFXEngine';
import { useStudioStore } from '../store/useStudioStore';
import type { Episode, Expression, SceneObject } from '../types';

const URL_FROG = `${import.meta.env.BASE_URL}models/frog.glb`;
const D2R = Math.PI / 180;
const HOP_SPEED = 1.1;
const TALK_THRESHOLD = 0.035;
const TWOS_FPS = 12;

/** Upper-lid angle per expression (0 = upper half covered, + closes, − opens) and eye bulge. */
const LIDS: Record<Expression, { l: number; r: number; tilt: number; bulge: number }> = {
  DEADPAN: { l: -0.3, r: -0.3, tilt: 0, bulge: 1 },
  SMIRK: { l: -0.2, r: -1.0, tilt: 0.15, bulge: 1 },
  PANIC: { l: -1.45, r: -1.45, tilt: 0, bulge: 1.22 },
  ANGRY: { l: -0.4, r: -0.4, tilt: 0.5, bulge: 0.95 },
  HAPPY: { l: -0.05, r: -0.05, tilt: -0.25, bulge: 1 },
  SHOCKED: { l: -1.55, r: -1.55, tilt: 0, bulge: 1.3 },
};

type Part = THREE.Object3D;

/** Bog: Blender-sculpted pond frog. Segmented rig (no skeleton), every beat deterministic. */
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
  const { scene } = useGLTF(URL_FROG);
  const root = useRef<THREE.Group>(null);
  const rig = useRef<THREE.Group>(null);

  const parts = useMemo(() => {
    const s = scene.clone(true);
    const get = (n: string) => s.getObjectByName(n) as Part;
    s.traverse((o) => {
      const m = o as THREE.Mesh;
      if (m.isMesh) {
        m.castShadow = true;
        m.receiveShadow = true;
        const mat = (m.material as THREE.MeshStandardMaterial).clone();
        mat.vertexColors = !!m.geometry.attributes.color;
        mat.metalness = 0;
        m.material = mat;
      }
    });
    const p = {
      scene: s,
      body: get('Frog_Body'),
      jaw: get('Frog_Jaw'),
      mouth: get('Frog_Mouth'),
      eyeL: get('Frog_Eye_L'),
      eyeR: get('Frog_Eye_R'),
      lidL: get('Frog_Lid_L'),
      lidR: get('Frog_Lid_R'),
      armL: get('Frog_Arm_L'),
      armR: get('Frog_Arm_R'),
      legL: get('Frog_Leg_L'),
      legR: get('Frog_Leg_R'),
    };
    // remember rest transforms
    Object.values(p).forEach((o) => {
      if (o && (o as THREE.Object3D).isObject3D) (o as THREE.Object3D).userData.rest = (o as THREE.Object3D).position.clone();
    });
    return p;
  }, [scene]);

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
        // forward progress only while airborne → reads as distinct hops
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
    parts.jaw.rotation.x = s.jaw;

    if (expr !== s.expr) {
      s.expr = expr;
      gsap.fromTo(rig.current!.scale, { x: 1.08, y: 0.9, z: 1.08 }, { x: 1, y: 1, z: 1, duration: 0.45, ease: 'elastic.out(1.2, 0.35)' });
    }

    // ── eyes + lids (the expression lives here) ──
    const L = LIDS[expr];
    const blink = tq % 3.7 < 0.12 ? 1.5 : 0;
    parts.lidL.rotation.set(Math.max(L.l, blink), 0, L.tilt);
    parts.lidR.rotation.set(Math.max(L.r, blink), 0, -L.tilt);
    const bulge = L.bulge + (expr === 'PANIC' ? Math.sin(tq * 25) * 0.04 : 0);
    parts.eyeL.scale.setScalar(bulge);
    parts.eyeR.scale.setScalar(bulge);
    parts.lidL.scale.setScalar(bulge);
    parts.lidR.scale.setScalar(bulge);

    // ── body: breathing throat, angry puff, talk bob ──
    const puff = expr === 'ANGRY' ? 1.12 + Math.sin(tq * 3) * 0.02 : 1 + Math.sin(tq * 2.4) * 0.012;
    parts.body.scale.set(puff, 1 + (puff - 1) * 0.6, puff);
    rig.current!.rotation.x = (talking ? -Math.abs(Math.sin(tq * 8)) * 0.05 : 0) - hopY * 1.2;
    rig.current!.position.y = expr === 'HAPPY' ? Math.abs(Math.sin(tq * 5)) * 0.04 : 0;
    rig.current!.position.x = expr === 'PANIC' ? Math.sin(tq * 30) * 0.008 : 0;

    // ── limbs ──
    const air = Math.max(0, Math.sin(s.phase)) * mark.moving;
    const kick = swimming ? Math.sin(tq * 6) * 0.6 : 0;
    parts.legL.rotation.x = -air * 1.1 + kick;
    parts.legR.rotation.x = -air * 1.1 - kick;
    let armX = air * 0.7;
    let armZ = 0;
    if (expr === 'PANIC') {
      armX = -1.2 + Math.sin(tq * 16) * 0.5;
      armZ = 0.6;
    } else if (expr === 'HAPPY') armX = -0.5 + Math.sin(tq * 5) * 0.3;
    else if (talking) armX = -0.25 + Math.sin(tq * 4) * 0.2;
    parts.armL.rotation.set(armX, 0, armZ);
    parts.armR.rotation.set(expr === 'PANIC' ? -1.2 - Math.sin(tq * 16) * 0.5 : armX, 0, -armZ);
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
      <group ref={rig}>
        <primitive object={parts.scene} />
      </group>
    </group>
  );
}

useGLTF.preload(URL_FROG);
