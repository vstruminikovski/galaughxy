import { vkey } from '../../engine/voxels';
import { ellipsoid, hash3, sphere, union, voxelize, type SDF } from '../../engine/sdf';

/**
 * Pond Life — the whole habitat is generated from 0.1 m squares.
 * Terrain = height field sampled into columns; features (rocks, trees, log, reeds, lily pads,
 * mushrooms) are SDF shapes voxelized into the same grid. Tweak the constants below to re-shape it.
 */
const V = 0.1; // metres per cell
const WATER_TOP_CELL = -1;

const C = {
  water: '#2f6f8a',
  waterDeep: '#22566b',
  grass: ['#3f5f22', '#6b8834', '#8f9145', '#2f4a1c'],
  dirt: '#6a5236',
  mud: ['#4d3d27', '#2e2618'],
  rock: ['#80796c', '#4d4942', '#6d6a60'],
  lichen: '#b3ad72',
  bark: ['#5b4431', '#2d2118'],
  leaf: ['#3e6b23', '#7a9a3a', '#1d3312'],
  pad: ['#3c6e2a', '#7aa344'],
  pink: '#f7c6d6',
  yellow: '#ffd23a',
  reed: '#9b9a55',
  cattail: '#5a3a1e',
  mushCap: '#b8452a',
  mushStem: '#efe3c8',
};

const pick = <T,>(arr: T[], x: number, z: number) => arr[Math.floor(hash3(x, 0, z) * arr.length) % arr.length];
const clamp01 = (t: number) => Math.max(0, Math.min(1, t));
const smooth = (a: number, b: number, x: number) => {
  const t = clamp01((x - a) / (b - a));
  return t * t * (3 - 2 * t);
};

// ── value noise for the height field ──
const lattice = (x: number, y: number) => hash3(x, y, 17);
const vnoise = (x: number, y: number) => {
  const xi = Math.floor(x);
  const yi = Math.floor(y);
  const xf = x - xi;
  const yf = y - yi;
  const u = xf * xf * (3 - 2 * xf);
  const v = yf * yf * (3 - 2 * yf);
  const a = lattice(xi, yi);
  const b = lattice(xi + 1, yi);
  const c = lattice(xi, yi + 1);
  const d = lattice(xi + 1, yi + 1);
  return a + (b - a) * u + (c - a) * v + (a - b - c + d) * u * v - 0.5;
};
const fbm = (x: number, y: number, o = 4) => {
  let v = 0;
  let a = 0.5;
  let f = 1;
  for (let i = 0; i < o; i++) {
    v += a * vnoise(x * f, y * f);
    a *= 0.5;
    f *= 2;
  }
  return v;
};

/** Height in metres at world (x, z). The pond sits in the basin around (0.6, -1.5). */
export function pondHeight(x: number, z: number): number {
  const y = -z; // the layout was authored with y pointing "into" the scene
  let h = fbm(x * 0.22 + 3.1, y * 0.22) * 0.32 + fbm(x * 0.9 + 4, y * 0.9 + 4) * 0.05;
  h += smooth(1.8, 5, y) * 1.5; // back hill
  h += smooth(-3, -6, x) * 0.45; // left bank
  h += smooth(3.5, 6, x) * 0.35; // right bank
  const d = Math.sqrt(((x - 0.6) / 3.1) ** 2 + ((y - 1.5) / 1.7) ** 2);
  h -= 0.62 * smooth(1.05, 0.25, d); // pond basin
  h *= 1 - 0.75 * smooth(1.4, 0, Math.hypot(x + 0.3, y + 1.2)); // flat stage for the actors
  return h;
}

export interface PondWorld {
  voxels: Map<string, string>;
  /** Highest solid (non-water) cell per column, for actors to stand on. */
  solidTop: Map<string, number>;
}

let cache: PondWorld | null = null;

export function pondWorld(): PondWorld {
  return (cache ??= buildPond());
}

/** Metres to stand at above world (x, z); the top of the highest solid cell. */
export function pondGround(x: number, z: number): number {
  const w = pondWorld();
  const t = w.solidTop.get(vkey(Math.round(x / V), 0, Math.round(z / V)));
  return t === undefined ? 0 : (t + 1) * V;
}

function buildPond(): PondWorld {
  const voxels = new Map<string, string>();
  const solidTop = new Map<string, number>();
  const put = (x: number, y: number, z: number, c: string, glow = false) => voxels.set(vkey(x, y, z), glow ? `*${c}` : c);
  const surfaceAt = new Map<string, number>(); // column -> surface cell (no grass)

  // ── terrain columns ──
  for (let ix = -60; ix <= 60; ix++)
    for (let iz = -50; iz <= 50; iz++) {
      const x = ix * V;
      const z = iz * V;
      const s = Math.round(pondHeight(x, z) / V);
      const under = s < WATER_TOP_CELL;
      surfaceAt.set(vkey(ix, 0, iz), s);
      const dirtPatch = smooth(0.25, 0.45, fbm(x * 0.6 + 5, -z * 0.6) + 0.5) > 0.5;
      const topColour = under ? pick(C.mud, ix, iz) : dirtPatch ? C.dirt : pick(C.grass, ix, iz);
      for (let y = -8; y < s; y++) put(ix, y, iz, y >= s - 2 ? C.dirt : pick(C.mud, ix, y) ?? C.mud[1]);
      put(ix, s, iz, topColour);
      solidTop.set(vkey(ix, 0, iz), s);
      if (under) {
        for (let y = s + 1; y <= WATER_TOP_CELL; y++) put(ix, y, iz, y === WATER_TOP_CELL ? C.water : C.waterDeep);
      }
    }

  const surface = (x: number, z: number) => surfaceAt.get(vkey(Math.round(x), 0, Math.round(z))) ?? 0;

  // ── reeds on the shoreline (cattail heads on top) ──
  for (let ix = -60; ix <= 60; ix++)
    for (let iz = -50; iz <= 50; iz++) {
      const s = surfaceAt.get(vkey(ix, 0, iz)) ?? 0;
      if (s < WATER_TOP_CELL || s > 1) continue;
      const nearWater = [
        [1, 0],
        [-1, 0],
        [0, 1],
        [0, -1],
      ].some(([dx, dz]) => (surfaceAt.get(vkey(ix + dx, 0, iz + dz)) ?? 0) < WATER_TOP_CELL);
      if (!nearWater || hash3(ix, 1, iz) < 0.72) continue;
      const hgt = 4 + Math.floor(hash3(iz, 2, ix) * 4);
      for (let k = 1; k <= hgt; k++) put(ix, s + k, iz, C.reed);
      put(ix, s + hgt + 1, iz, C.cattail);
    }

  // ── lily pads on the pond, some with a pink flower ──
  for (let ix = -60; ix <= 60; ix++)
    for (let iz = -50; iz <= 50; iz++) {
      const s = surfaceAt.get(vkey(ix, 0, iz)) ?? 0;
      if (s >= WATER_TOP_CELL || hash3(ix, 9, iz) < 0.955) continue;
      for (let dx = -2; dx <= 2; dx++)
        for (let dz = -2; dz <= 2; dz++)
          if (dx * dx + dz * dz <= 4) put(ix + dx, 0, iz + dz, pick(C.pad, ix + dx, iz + dz));
      if (hash3(iz, 4, ix) > 0.5) put(ix, 1, iz, C.pink);
    }

  // ── rocks (SDF blobs, lichen speckle) ──
  const rocks: [number, number, number][] = [
    [-2.6, 0.6, 0.45],
    [-2.0, 1.2, 0.25],
    [3.4, 0.9, 0.55],
    [3.9, 1.7, 0.3],
    [2.2, 3.0, 0.4],
    [-1.0, 3.1, 0.6],
    [4.6, -1.5, 0.35],
    [-4.4, -1.0, 0.5],
    [1.5, -3.2, 0.2],
    [-3.2, -3.0, 0.25],
  ];
  for (const [rx, ry, rs] of rocks) {
    const cx = Math.round(rx / V);
    const cz = Math.round(-ry / V);
    const r = Math.max(2, Math.round(rs / V));
    const cy = surface(cx, cz) + Math.round(r * 0.3);
    const f = ellipsoid([cx, cy, cz], [r, r * 0.7, r]);
    for (const v of voxelize(f, [cx - r, cx + r, cy - r, cy + r, cz - r, cz + r], (x, y, z) => ({
      c: hash3(x, y, z) > 0.93 ? C.lichen : pick(C.rock, x + y, z),
    })))
      put(v.x, v.y, v.z, v.c);
  }

  // ── fallen log along the bank ──
  for (let x = -36; x <= -4; x++) {
    const s = surface(x, 2);
    for (let z = 1; z <= 3; z++)
      for (let y = 1; y <= 2; y++) put(x, s + y, z, y === 2 && z === 2 ? C.bark[1] : C.bark[0]);
  }

  // ── trees with trunk, root flare and a blobby crown of leaf cubes ──
  const trees: [number, number, number][] = [
    [-4.6, 3.6, 4.2],
    [-1.8, 4.4, 5.0],
    [1.2, 4.6, 4.4],
    [3.9, 4.0, 5.2],
    [5.4, 2.0, 3.6],
    [-5.4, 0.6, 3.4],
  ];
  for (const [tx, ty, th] of trees) {
    const cx = Math.round(tx / V);
    const cz = Math.round(-ty / V);
    const s = surface(cx, cz);
    const trunk = Math.round(th * 6);
    for (let y = s + 1; y <= s + trunk; y++) put(cx, y, cz, pick(C.bark, cx, y));
    for (const [dx, dz] of [[1, 0], [-1, 0], [0, 1], [0, -1]]) put(cx + dx, s + 1, cz + dz, C.bark[0]);

    const top = s + trunk;
    const blobs: SDF[] = [];
    for (let k = 0; k < 9; k++) {
      const a = hash3(cx, k, cz) * Math.PI * 2;
      const rr = 1 + hash3(k, cz, cx) * 5;
      blobs.push(sphere([cx + Math.cos(a) * rr, top + 2 + hash3(cz, k, 3) * 4, cz + Math.sin(a) * rr], 3 + hash3(k, 7, cx) * 1.5));
    }
    const crown = union(...blobs);
    const b: [number, number, number, number, number, number] = [cx - 9, cx + 9, top - 1, top + 9, cz - 9, cz + 9];
    for (const v of voxelize(crown, b, (x, y, z) => ({ c: pick(C.leaf, x + y, z) }))) put(v.x, v.y, v.z, v.c);
  }

  // ── bushes (rounded clumps) ──
  const bushes: [number, number, number][] = [
    [-3.6, 2.2, 0.6],
    [-0.2, 2.9, 0.45],
    [2.9, 2.6, 0.55],
    [4.8, 0.2, 0.6],
    [-4.9, -2.2, 0.55],
    [4.2, -3.2, 0.5],
  ];
  for (const [bx, by, bs] of bushes) {
    const cx = Math.round(bx / V);
    const cz = Math.round(-by / V);
    const r = Math.round(bs / V) + 2;
    const cy = surface(cx, cz) + 1;
    for (const v of voxelize(ellipsoid([cx, cy, cz], [r, r * 0.7, r]), [cx - r, cx + r, cy - 1, cy + r, cz - r, cz + r], (x, _y, z) => ({
      c: pick(C.leaf, x, z),
    })))
      put(v.x, v.y, v.z, v.c);
  }

  // ── mushrooms ──
  for (const [mx, my] of [
    [-1.3, -0.45],
    [-1.15, -0.5],
    [-2.5, -0.55],
  ] as [number, number][]) {
    const cx = Math.round(mx / V);
    const cz = Math.round(-my / V);
    const s = surface(cx, cz);
    for (let y = s + 1; y <= s + 2; y++) put(cx, y, cz, C.mushStem);
    for (let dx = -1; dx <= 1; dx++) for (let dz = -1; dz <= 1; dz++) put(cx + dx, s + 3, cz + dz, dx * dx + dz * dz < 2 ? C.mushCap : C.mushStem);
  }

  // ── cattail heads on the bank are above; yellow flowers on the meadow ──
  for (let ix = -40; ix <= 40; ix++)
    for (let iz = -30; iz <= 30; iz++) {
      const s = surfaceAt.get(vkey(ix, 0, iz)) ?? 0;
      if (s < 1 || hash3(ix, 11, iz) < 0.994) continue;
      put(ix, s + 1, iz, C.yellow);
    }

  return { voxels, solidTop };
}

