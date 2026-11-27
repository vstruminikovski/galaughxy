import type { Voxel } from '../types';

/**
 * Tiny signed-distance toolkit. Every organic shape in the game is sampled into integer voxel
 * cells, so the look stays "squares all the way down" and any shape can be re-tuned in code.
 * Convention: f(x,y,z) < 0 means the cell is solid.
 */
export type SDF = (x: number, y: number, z: number) => number;
export type Bounds = [x0: number, x1: number, y0: number, y1: number, z0: number, z1: number];

const len3 = (x: number, y: number, z: number) => Math.hypot(x, y, z);

export const sphere =
  (c: number[], r: number): SDF =>
  (x, y, z) =>
    len3(x - c[0], y - c[1], z - c[2]) - r;

export const ellipsoid =
  (c: number[], r: number[]): SDF =>
  (x, y, z) => {
    const k0 = len3((x - c[0]) / r[0], (y - c[1]) / r[1], (z - c[2]) / r[2]);
    const k1 = len3((x - c[0]) / (r[0] * r[0]), (y - c[1]) / (r[1] * r[1]), (z - c[2]) / (r[2] * r[2]));
    return k1 === 0 ? -1 : (k0 * (k0 - 1)) / k1;
  };

export const capsule =
  (a: number[], b: number[], r: number): SDF =>
  (x, y, z) => {
    const pax = x - a[0], pay = y - a[1], paz = z - a[2];
    const bax = b[0] - a[0], bay = b[1] - a[1], baz = b[2] - a[2];
    const h = Math.max(0, Math.min(1, (pax * bax + pay * bay + paz * baz) / (bax * bax + bay * bay + baz * baz)));
    return len3(pax - bax * h, pay - bay * h, paz - baz * h) - r;
  };

export const box =
  (c: number[], half: number[]): SDF =>
  (x, y, z) => {
    const qx = Math.abs(x - c[0]) - half[0];
    const qy = Math.abs(y - c[1]) - half[1];
    const qz = Math.abs(z - c[2]) - half[2];
    return len3(Math.max(qx, 0), Math.max(qy, 0), Math.max(qz, 0)) + Math.min(Math.max(qx, qy, qz), 0);
  };

/** Smooth union: blends joins like clay (k = blend radius in cells). */
export const smin =
  (a: SDF, b: SDF, k: number): SDF =>
  (x, y, z) => {
    const d1 = a(x, y, z);
    const d2 = b(x, y, z);
    const h = Math.max(k - Math.abs(d1 - d2), 0) / k;
    return Math.min(d1, d2) - h * h * k * 0.25;
  };

export const union =
  (...fs: SDF[]): SDF =>
  (x, y, z) => {
    let d = Infinity;
    for (const f of fs) d = Math.min(d, f(x, y, z));
    return d;
  };

export const minus =
  (a: SDF, b: SDF): SDF =>
  (x, y, z) =>
    Math.max(a(x, y, z), -b(x, y, z));

export type Paint = { c: string; e?: boolean } | null;

/** Sample every integer cell inside `b`; `paint` decides colour (null = skip). */
export function voxelize(f: SDF, b: Bounds, paint: (x: number, y: number, z: number) => Paint): Voxel[] {
  const out: Voxel[] = [];
  for (let x = b[0]; x <= b[1]; x++)
    for (let y = b[2]; y <= b[3]; y++)
      for (let z = b[4]; z <= b[5]; z++) {
        if (f(x, y, z) > 0) continue;
        const p = paint(x, y, z);
        if (p) out.push(p.e ? { x, y, z, c: p.c, e: true } : { x, y, z, c: p.c });
      }
  return out;
}

/** Shift voxels so the pivot becomes the origin (for rotating parts such as jaws and legs). */
export const relativeTo = (vs: Voxel[], p: number[]): Voxel[] =>
  vs.map((v) => ({ ...v, x: v.x - p[0], y: v.y - p[1], z: v.z - p[2] }));

/** Deterministic hash in [0,1) — used for stable per-cell colour variation. */
export const hash3 = (x: number, y: number, z: number) => {
  const n = Math.sin(x * 12.9898 + y * 78.233 + z * 37.719) * 43758.5453;
  return n - Math.floor(n);
};
