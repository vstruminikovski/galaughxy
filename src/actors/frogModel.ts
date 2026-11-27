import { box, capsule, ellipsoid, hash3, minus, relativeTo, smin, sphere, union, voxelize, type Bounds } from '../engine/sdf';
import { vmerge } from '../engine/voxels';
import type { Voxel } from '../types';

/**
 * Bog the frog — a HYBRID character built entirely from squares:
 * organic silhouette (smooth-blended ellipsoids) + robot parts (glowing LED side strip,
 * antenna with a magenta beacon, glowing gold eye lenses). Every part is a separate voxel
 * group with its pivot at the joint, so the animation code can rotate jaw, lids, limbs.
 */
export const FROG_VOXEL = 0.03; // metres per cell

const C = {
  skin: '#5f9a3a',
  dark: '#3c6a24',
  light: '#9cc35a',
  belly: '#e6dca0',
  gold: '#e6b52a',
  black: '#0b0b0b',
  metal: '#4a5160',
  led: '#ff3d7f',
  lip: '#c9c27f',
  mouth: '#5a1a22',
};

const skin = (x: number, _y: number, z: number) => {
  const r = hash3(x, _y, z);
  return r < 0.2 ? C.dark : r < 0.82 ? C.skin : C.light;
};

export interface FrogPart {
  voxels: Voxel[];
  pivot: [number, number, number];
}

const part = (vs: Voxel[], pivot: number[]): FrogPart => ({
  voxels: relativeTo(vs, pivot),
  pivot: pivot as [number, number, number],
});

export function buildFrogParts(): Record<string, FrogPart> {
  // ── torso + head (one organic blend) ──
  const torso = smin(ellipsoid([0, 7, 0], [7, 5, 9]), ellipsoid([0, 9, 6], [6, 4.5, 5]), 2.5);
  const mouthCut = ellipsoid([0, 6.6, 9.6], [4.6, 1.4, 3.2]);
  const bodyVox = voxelize(minus(torso, mouthCut), [-12, 12, -1, 20, -12, 14], (x, y, z) => {
    if (Math.abs(x) === 6 && y === 7 && z % 3 === 0) return { c: C.led, e: true }; // robot LED strip
    return { c: y <= 3 ? C.belly : skin(x, y, z) };
  });

  // antenna with a magenta beacon
  const antenna = voxelize(capsule([0, 14, 4], [0, 19, 4], 0.7), [-2, 2, 13, 21, 2, 6], () => ({ c: C.metal }));
  const beacon = voxelize(sphere([0, 19.6, 4], 1.2), [-2, 2, 18, 22, 2, 6], () => ({ c: C.led, e: true }));
  const body = vmerge(bodyVox, antenna, beacon);

  // ── eyes: glowing gold lenses with a black slit pupil; lids are separate ──
  const eyes: Record<string, FrogPart> = {};
  const lids: Record<string, FrogPart> = {};
  for (const [side, s] of [
    ['L', 1],
    ['R', -1],
  ] as const) {
    const ex = 4 * s;
    const ey = 12;
    const ez = 8;
    const pivot = [ex, ey, ez];
    const ball = voxelize(sphere(pivot, 2.4), [ex - 3, ex + 3, ey - 3, ey + 3, ez - 3, ez + 3], (x, y, z) => {
      const front = z > ez + 1 && Math.abs(x - ex) <= 0.8 && Math.abs(y - ey) <= 1.2;
      return front ? { c: C.black } : { c: C.gold, e: true };
    });
    eyes[side] = part(ball, pivot);

    // upper shell: rotating it forward covers the eye
    const shellSDF = minus(sphere(pivot, 3.3), sphere(pivot, 2.2));
    const shell = voxelize(shellSDF, [ex - 4, ex + 4, ey, ey + 4, ez - 4, ez + 4], () => ({ c: skin(ex, ey, ez) }));
    lids[side] = part(shell, pivot);
  }

  // ── lower jaw (pivot at the hinge behind the mouth) ──
  const jawVox = voxelize(ellipsoid([0, 5.2, 8.5], [4.2, 1.5, 3.6]), [-6, 6, 2, 9, 4, 13], (_x, _y, z) =>
    z >= 10 ? { c: C.lip } : { c: C.belly },
  );
  const jaw = part(jawVox, [0, 6, 4]);

  // ── limbs: robot joint caps at the pivots ──
  const limb = (s: number) => {
    const hip = [6 * s, 4, -4];
    const leg = union(ellipsoid(hip, [3.2, 3, 4.5]), box([6 * s, 1, -1], [2.4, 1, 2.6]));
    const legVox = voxelize(leg, [6 * s - 6, 6 * s + 6, -1, 9, -11, 2], (x, y, z) =>
      y >= 6 && Math.abs(x - 6 * s) <= 1 ? { c: C.metal } : { c: skin(x, y, z) },
    );
    const sh = [5 * s, 5, 4];
    const arm = union(capsule([5 * s, 4, 4], [7.5 * s, 1.5, 8], 1.5), box([7.5 * s, 1, 9], [1.8, 0.8, 1.6]));
    const armVox = voxelize(arm, [5 * s - 3, 5 * s + 4, -1, 7, 1, 12], (x, y, z) =>
      y >= 4 && Math.abs(x - 5 * s) <= 1 && z <= 5 ? { c: C.metal } : { c: skin(x, y, z) },
    );
    return { leg: part(legVox, hip), arm: part(armVox, sh) };
  };
  const L = limb(1);
  const R = limb(-1);

  return {
    body: part(body, [0, 0, 0]),
    jaw,
    eyeL: eyes.L,
    eyeR: eyes.R,
    lidL: lids.L,
    lidR: lids.R,
    armL: L.arm,
    armR: R.arm,
    legL: L.leg,
    legR: R.leg,
  };
}

/** Bounds helper kept for future parts. */
export const frogBounds = (): Bounds => [-12, 12, -1, 22, -12, 14];
