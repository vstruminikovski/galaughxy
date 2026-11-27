import { vkey } from '../../engine/voxels';
import { capsule, ellipsoid, hash3, sphere, union, voxelize, type SDF } from '../../engine/sdf';

/**
 * Backyard Garden — lawn, fence, flower beds, stepping stones, a tree and a garden table.
 * Everything is square voxels on the same 0.1 m grid. Lawn top sits at y = 0 (cell -1).
 */
const C = {
  soil: '#5a4228',
  grass: ['#4f7a2a', '#5d8a33', '#466f25'],
  wood: '#a6743f',
  woodDark: '#7a5230',
  stone: ['#9a9790', '#8a877f'],
  bark: '#5b4431',
  leaf: ['#3e6b23', '#4f8030', '#2f5a1c'],
  flowers: ['#ff5f87', '#ffd23a', '#9b6bff', '#ffffff', '#ff8a3d'],
  mug: '#e2574c',
  table: '#c79a5e',
};

const pick = <T,>(a: T[], x: number, z: number) => a[Math.floor(hash3(x, 0, z) * a.length) % a.length];

export function buildGarden(): Map<string, string> {
  const m = new Map<string, string>();
  const put = (x: number, y: number, z: number, c: string, glow = false) => m.set(vkey(x, y, z), glow ? `*${c}` : c);
  const fill = (x0: number, x1: number, y0: number, y1: number, z0: number, z1: number, c: (x: number, y: number, z: number) => string) => {
    for (let x = x0; x <= x1; x++) for (let y = y0; y <= y1; y++) for (let z = z0; z <= z1; z++) put(x, y, z, c(x, y, z));
  };

  // lawn: soil underneath, grass top at cell -1 with mown stripes
  fill(-55, 55, -4, -2, -45, 45, () => C.soil);
  fill(-55, 55, -1, -1, -45, 45, (x, _y, z) => (Math.floor((x + 60) / 6) + Math.floor((z + 60) / 6)) % 2 ? C.grass[0] : pick(C.grass, x, z));

  // fence around the lawn
  for (let x = -55; x <= 55; x++) {
    if (Math.abs(x) % 5 === 0) for (let y = 0; y <= 8; y++) put(x, y, -45, C.woodDark), put(x, y, 45, C.woodDark);
    put(x, 6, -45, C.wood), put(x, 3, -45, C.wood), put(x, 6, 45, C.wood), put(x, 3, 45, C.wood);
  }
  for (let z = -45; z <= 45; z++) {
    if (Math.abs(z) % 5 === 0) for (let y = 0; y <= 8; y++) put(-55, y, z, C.woodDark), put(55, y, z, C.woodDark);
    put(-55, 6, z, C.wood), put(-55, 3, z, C.wood), put(55, 6, z, C.wood), put(55, 3, z, C.wood);
  }

  // stepping-stone path from the back gate to the table
  for (let z = -40; z <= 20; z += 3) fill(-1, 1, 0, 0, z, z + 1, () => pick(C.stone, z, 2));

  // flower beds with blooms
  fill(-45, -30, 0, 0, -30, -20, () => C.soil);
  for (let x = -45; x <= -30; x++)
    for (let z = -30; z <= -20; z++) if (hash3(x, 7, z) > 0.45) put(x, 1, z, pick(C.flowers, x, z));
  fill(28, 40, 0, 0, 22, 30, () => C.soil);
  for (let x = 28; x <= 40; x++) for (let z = 22; z <= 30; z++) if (hash3(z, 3, x) > 0.4) put(x, 1 + (hash3(x, z, 1) > 0.7 ? 1 : 0), z, pick(C.flowers, z, x));

  // tree in the far corner
  const tx = -36;
  const tz = -6;
  for (let y = 0; y <= 22; y++) put(tx, y, tz, C.bark), (y < 4 && put(tx + 1, y, tz, C.bark));
  const crown: SDF[] = [];
  for (let k = 0; k < 8; k++) {
    const a = hash3(k, 1, 2) * Math.PI * 2;
    crown.push(sphere([tx + Math.cos(a) * 5, 22 + hash3(k, 4, 1) * 3, tz + Math.sin(a) * 5], 5 + hash3(k, 9, 3) * 2));
  }
  for (const v of voxelize(union(...crown), [tx - 12, tx + 12, 18, 32, tz - 12, tz + 12], (x, _y, z) => ({ c: pick(C.leaf, x, z) })))
    put(v.x, v.y, v.z, v.c);

  // garden table with a mug and two chairs' worth of legs
  const table = [14, 26, 6, 7, -14, -6] as const;
  fill(table[0], table[1], table[2], table[3], table[4], table[5], () => C.table);
  for (const [lx, lz] of [
    [14, -14],
    [26, -14],
    [14, -6],
    [26, -6],
  ]) fill(lx, lx, 0, 5, lz, lz, () => C.woodDark);
  put(22, 8, -10, C.mug), put(22, 9, -10, C.mug), put(21, 8, -10, C.mug);

  // a glowing LED lantern on the table (robot hybrid touch)
  put(18, 8, -10, '#ffd23a', true);
  put(18, 9, -10, '#ffd23a', true);

  // bushes near the fence
  for (const [bx, bz] of [
    [40, -36],
    [-40, 36],
    [44, 20],
  ] as [number, number][]) {
    const r = 4;
    for (const v of voxelize(ellipsoid([bx, 1, bz], [r, r * 0.8, r]), [bx - r, bx + r, 0, 6, bz - r, bz + r], (x, _y, z) => ({ c: pick(C.leaf, x, z) })))
      put(v.x, v.y, v.z, v.c);
  }

  // capsule-shaped garden hose (decor)
  for (const v of voxelize(capsule([-20, 0, 30], [-8, 0, 36], 0.6), [-22, -6, -1, 2, 28, 38], () => ({ c: '#2b7fb5' })))
    put(v.x, v.y, v.z, v.c);

  return m;
}
