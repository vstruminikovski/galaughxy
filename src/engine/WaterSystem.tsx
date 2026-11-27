import { useFrame } from '@react-three/fiber';
import { useMemo, useRef } from 'react';
import * as THREE from 'three';
import { useStudioStore } from '../store/useStudioStore';
import type { Episode, SceneObject } from '../types';
import { runtime } from './runtime';

const DROPS = 1400;
const pondMat = new THREE.MeshPhysicalMaterial({
  color: '#2f4f3f',
  roughness: 0.04,
  metalness: 0.0,
  clearcoat: 1,
  clearcoatRoughness: 0.05,
  transparent: true,
  opacity: 0.78,
  side: THREE.DoubleSide,
  depthWrite: false,
});
const waterMat = new THREE.MeshStandardMaterial({
  color: '#3fa7d6',
  roughness: 0.06,
  metalness: 0.15,
  transparent: true,
  opacity: 0.62,
  side: THREE.DoubleSide,
  depthWrite: false,
});

/**
 * Flood plane + puddle + drip emitter + floating props + debris.
 * Everything is driven from `runtime` (gsap-tweened) and mutated in useFrame — zero React renders.
 */
export function WaterSystem({ episode, perform }: { episode: Episode; perform: boolean }) {
  const { minX, maxX, minZ, maxZ } = episode.bounds;
  const pond = episode.waterRest !== undefined;
  const rest = episode.waterRest ?? 0;
  const w = maxX - minX + (pond ? 3 : 0.6);
  const d = maxZ - minZ + (pond ? 3 : 0.6);
  const cx = (minX + maxX) / 2;
  const cz = (minZ + maxZ) / 2;

  const surfRef = useRef<THREE.Mesh>(null);
  const bodyRef = useRef<THREE.Mesh>(null);
  const puddleRef = useRef<THREE.Mesh>(null);
  const dropsRef = useRef<THREE.Points>(null);
  const debrisRef = useRef<THREE.Group>(null);

  const surfGeo = useMemo(() => {
    const g = new THREE.PlaneGeometry(w, d, pond ? 96 : 48, pond ? 80 : 40);
    g.rotateX(-Math.PI / 2);
    return g;
  }, [w, d]);
  const basePos = useMemo(() => Float32Array.from(surfGeo.attributes.position.array), [surfGeo]);

  const drops = useMemo(() => {
    const pos = new Float32Array(DROPS * 3).fill(-100);
    const vel = new Float32Array(DROPS);
    const g = new THREE.BufferGeometry();
    g.setAttribute('position', new THREE.BufferAttribute(pos, 3));
    return { g, pos, vel, next: 0 };
  }, []);

  const debrisSeeds = useMemo(
    () =>
      Array.from({ length: 14 }, (_, i) => ({
        x: minX + 0.4 + ((i * 0.618) % 1) * (maxX - minX - 0.8),
        z: minZ + 0.4 + ((i * 0.381 + 0.2) % 1) * (maxZ - minZ - 0.8),
        s: 0.08 + ((i * 0.27) % 1) * 0.14,
        c: (pond ? ['#6b4a2b', '#4d6b2a', '#8a6a3a', '#3f5a22', '#a08050'] : ['#8b5a2b', '#e6c27a', '#d94f4f', '#f2f2f2', '#6cbf6c'])[i % 5],
        ph: i * 1.7,
      })),
    [minX, maxX, minZ, maxZ, pond],
  );

  const tapWorld = useRef(new THREE.Vector3(0, 1, -2));

  useFrame((state, dt) => {
    const t = state.clock.elapsedTime;
    const level = rest + runtime.waterLevel * (episode.floodScale ?? 1);
    const amp = runtime.rippleAmp + (pond ? 0.006 : 0);

    // Locate the tap socket (any prop exposing "tapSocket"); outdoors there is none → rain.
    let hasTap = false;
    for (const obj of runtime.objects.values()) {
      const s = obj.getObjectByName('socket:tapSocket');
      if (s) {
        s.getWorldPosition(tapWorld.current);
        hasTap = true;
        break;
      }
    }

    // Flood body + rippling surface
    const surf = surfRef.current!;
    const body = bodyRef.current!;
    const on = pond || level > 0.004;
    surf.visible = on;
    body.visible = on && !pond;
    if (on) {
      surf.position.set(cx, level, cz);
      body.scale.set(w, Math.max(level, 0.001), d);
      body.position.set(cx, level / 2, cz);
      const p = surfGeo.attributes.position as THREE.BufferAttribute;
      for (let i = 0; i < p.count; i++) {
        const x = basePos[i * 3];
        const z = basePos[i * 3 + 2];
        const y =
          Math.sin(x * 3.1 + t * 2.2) * amp +
          Math.cos(z * 2.7 - t * 1.7) * amp * 0.8 +
          Math.sin((x + z) * 6 + t * 4) * amp * 0.35;
        p.setY(i, y);
      }
      p.needsUpdate = true;
      surfGeo.computeVertexNormals();
    }

    // Puddle under the sink
    const pud = puddleRef.current!;
    pud.visible = hasTap && runtime.puddle > 0.01 && level < 0.05;
    pud.position.set(tapWorld.current.x, 0.006, Math.min(tapWorld.current.z + 0.7, maxZ));
    const r = runtime.puddle * 0.9;
    pud.scale.set(r, 1, r * 0.75);

    // Drip / stream emitter
    const spawnPerSec = runtime.dripRate * runtime.dripRate * 260 * (hasTap ? 1 : 12);
    let toSpawn = spawnPerSec * dt + (Math.random() < (spawnPerSec * dt) % 1 ? 1 : 0);
    while (toSpawn-- >= 1) {
      const i = drops.next;
      drops.next = (drops.next + 1) % DROPS;
      if (hasTap) {
        drops.pos[i * 3] = tapWorld.current.x + (Math.random() - 0.5) * 0.04 * (1 + runtime.dripRate * 3);
        drops.pos[i * 3 + 1] = tapWorld.current.y;
        drops.pos[i * 3 + 2] = tapWorld.current.z + (Math.random() - 0.5) * 0.04 + runtime.dripRate * 0.05;
        drops.vel[i] = 0;
      } else {
        // rainstorm across the habitat
        drops.pos[i * 3] = minX + Math.random() * (maxX - minX);
        drops.pos[i * 3 + 1] = 3 + Math.random() * 2;
        drops.pos[i * 3 + 2] = minZ + Math.random() * (maxZ - minZ);
        drops.vel[i] = -6;
      }
    }
    const floor = pond ? level : Math.max(level, 0);
    for (let i = 0; i < DROPS; i++) {
      if (drops.pos[i * 3 + 1] < -50) continue;
      drops.vel[i] -= 9.8 * dt;
      drops.pos[i * 3 + 1] += drops.vel[i] * dt;
      if (hasTap) drops.pos[i * 3 + 2] += runtime.dripRate * 0.8 * dt;
      const ground = episode.ground ? episode.ground(drops.pos[i * 3], drops.pos[i * 3 + 2]) : 0;
      if (drops.pos[i * 3 + 1] < Math.max(floor, ground)) drops.pos[i * 3 + 1] = -100;
    }
    (drops.g.attributes.position as THREE.BufferAttribute).needsUpdate = true;
    dropsRef.current!.visible = runtime.dripRate > 0.01;

    // Floating debris
    const dg = debrisRef.current!;
    dg.visible = runtime.debris > 0.01;
    dg.children.forEach((m, i) => {
      const s = debrisSeeds[i];
      m.position.set(
        s.x + Math.sin(t * 0.4 + s.ph) * 0.4,
        level + Math.sin(t * 2 + s.ph) * 0.03,
        s.z + Math.cos(t * 0.3 + s.ph) * 0.3,
      );
      m.rotation.set(Math.sin(t + s.ph) * 0.3, t * 0.3 + s.ph, Math.cos(t * 1.2 + s.ph) * 0.3);
      m.scale.setScalar(runtime.debris);
    });

    // Floating props bob on the surface (performance mode only, so gizmos never fight it)
    if (perform) {
      const objects = useStudioStore.getState().scene.objects;
      const lib = useStudioStore.getState().library;
      for (const o of objects) {
        if (!floats(o, lib)) continue;
        const g = runtime.objects.get(o.id);
        if (!g) continue;
        const baseY = o.pos[1] + (pond ? rest : 0);
        if (level > baseY + 0.03) {
          g.position.y = level - 0.04 + Math.sin(t * 2.3 + o.pos[0] * 3) * 0.025;
          g.rotation.z = Math.sin(t * 1.7 + o.pos[2]) * 0.18;
          g.rotation.x = Math.cos(t * 1.3 + o.pos[0]) * 0.12;
          g.position.x = o.pos[0] + Math.sin(t * 0.35 + o.pos[2] * 2) * 0.25;
        } else {
          g.position.set(...o.pos);
          g.rotation.set((o.rot[0] * Math.PI) / 180, (o.rot[1] * Math.PI) / 180, (o.rot[2] * Math.PI) / 180);
        }
      }
    }
  });

  return (
    <group>
      <mesh ref={bodyRef} material={waterMat} visible={false} renderOrder={2}>
        <boxGeometry args={[1, 1, 1]} />
      </mesh>
      <mesh ref={surfRef} geometry={surfGeo} material={pond ? pondMat : waterMat} visible={false} renderOrder={3} receiveShadow />
      <mesh ref={puddleRef} material={waterMat} visible={false} renderOrder={1}>
        <cylinderGeometry args={[1, 1, 0.012, 32]} />
      </mesh>
      <points ref={dropsRef} geometry={drops.g} frustumCulled={false}>
        <pointsMaterial color="#cfe8ff" size={0.03} transparent opacity={0.75} />
      </points>
      <group ref={debrisRef} visible={false}>
        {debrisSeeds.map((s, i) => (
          <mesh key={i} castShadow>
            <boxGeometry args={[s.s * 2, s.s * 0.4, s.s]} />
            <meshStandardMaterial color={s.c} roughness={0.8} />
          </mesh>
        ))}
      </group>
    </group>
  );
}

function floats(o: SceneObject, lib: Record<string, { floats?: boolean }>) {
  if (o.kind !== 'prop') return false;
  return !!lib[o.ref]?.floats;
}
