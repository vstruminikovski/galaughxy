import type { Voxel } from '../types';

/**
 * Vector ink, built as real strokes.
 *
 * 1. Every cube edge that touches the exposed surface is recorded with the two faces meeting there.
 * 2. Edges that are silhouettes for the camera are kept (one face toward the camera, one away).
 *    Block mode keeps every edge.
 * 3. Kept edges are joined into continuous contours, so one contour is one stroke and two strokes
 *    never run over each other.
 * 4. Contours are smoothed (Chaikin) so stair steps read as one curve, and are drawn as a ribbon
 *    whose width tapers smoothly from the middle to both ends (see VoxelInk.tsx).
 */
export interface InkEdges {
  pos: Float32Array; // 6 floats per edge: start xyz, end xyz (object space, metres)
  na: Float32Array; // normal of the first face at the edge (3 floats)
  nb: Float32Array; // normal of the second face (same as na when the edge has one face)
}

export function buildInkEdges(voxels: Voxel[], size: number): InkEdges {
  const solid = new Set<string>();
  for (const v of voxels) solid.add(`${v.x},${v.y},${v.z}`);
  const isSolid = (c: number[]) => solid.has(`${c[0]},${c[1]},${c[2]}`);

  const seen = new Set<string>();
  const pos: number[] = [];
  const na: number[] = [];
  const nb: number[] = [];

  for (const v of voxels)
    for (let A = 0; A < 3; A++) {
      const P = (A + 1) % 3;
      const Q = (A + 2) % 3;
      for (let a = 0; a < 2; a++)
        for (let b = 0; b < 2; b++) {
          const p = [v.x, v.y, v.z];
          p[P] += a;
          p[Q] += b;
          const key = `${A}:${p[0]},${p[1]},${p[2]}`;
          if (seen.has(key)) continue;
          seen.add(key);

          const cell = (pp: number, qq: number) => {
            const c = [0, 0, 0];
            c[A] = p[A];
            c[P] = pp;
            c[Q] = qq;
            return c;
          };
          const normals: number[][] = [];
          for (let dq = -1; dq <= 0; dq++) {
            const ca = cell(p[P] - 1, p[Q] + dq);
            const cb = cell(p[P], p[Q] + dq);
            const sa = isSolid(ca);
            if (sa !== isSolid(cb)) {
              const n = [0, 0, 0];
              n[P] = sa ? 1 : -1;
              normals.push(n);
            }
          }
          for (let dp = -1; dp <= 0; dp++) {
            const ca = cell(p[P] + dp, p[Q] - 1);
            const cb = cell(p[P] + dp, p[Q]);
            const sa = isSolid(ca);
            if (sa !== isSolid(cb)) {
              const n = [0, 0, 0];
              n[Q] = sa ? 1 : -1;
              normals.push(n);
            }
          }
          if (!normals.length) continue;

          const s = [p[0] * size, p[1] * size, p[2] * size];
          const e = [...s];
          e[A] += size;
          pos.push(...s, ...e);
          na.push(...normals[0]);
          nb.push(...(normals[1] ?? normals[0]));
        }
    }

  return { pos: Float32Array.from(pos), na: Float32Array.from(na), nb: Float32Array.from(nb) };
}

/** Wobble offset per point (same hash family as before, so the boil keeps its character). */
export function boilOffset(x: number, y: number, z: number, step: number, amp: number): [number, number, number] {
  const sx = Math.floor(x * 4096);
  const sy = Math.floor(y * 4096);
  const sz = Math.floor(z * 4096);
  const fr = (v: number) => v - Math.floor(v);
  const a = fr(Math.sin(sx * 12.9898 + sy * 78.233 + sz * 37.719 + step * 0.731) * 43758.5453);
  const b = fr(Math.sin(sx * 93.9898 + sy * 67.345 + sz * 11.135 + step * 1.17) * 24634.6345);
  const c = fr(Math.sin(sx * 41.1 + sy * 289.3 + sz * 173.7 + step * 0.419) * 15731.743);
  return [(a - 0.5) * amp, (b - 0.5) * amp, (c - 0.5) * amp];
}

const keyOf = (p: number[]) => `${Math.round(p[0] * 1e6)},${Math.round(p[1] * 1e6)},${Math.round(p[2] * 1e6)}`;

/** Chaikin corner cutting: turns stair steps into a smooth curve. Keeps the end points. */
export function smoothChaikin(pts: number[][], iterations: number): number[][] {
  let p = pts;
  for (let it = 0; it < iterations; it++) {
    if (p.length < 3) break;
    const q: number[][] = [p[0]];
    for (let i = 0; i < p.length - 1; i++) {
      const a = p[i];
      const b = p[i + 1];
      q.push([0.75 * a[0] + 0.25 * b[0], 0.75 * a[1] + 0.25 * b[1], 0.75 * a[2] + 0.25 * b[2]]);
      q.push([0.25 * a[0] + 0.75 * b[0], 0.25 * a[1] + 0.75 * b[1], 0.25 * a[2] + 0.75 * b[2]]);
    }
    q.push(p[p.length - 1]);
    p = q;
  }
  return p;
}

/**
 * Joins the silhouette edges into contours. Each contour is a flat xyz array (object space).
 * Every edge belongs to exactly one contour, so nothing is drawn twice.
 */
export function buildContours(
  edges: InkEdges,
  view: { x: number; y: number; z: number },
  blocks: boolean,
  step: number,
  amp: number,
): number[][] {
  const count = edges.pos.length / 6;
  const A: number[][] = [];
  const B: number[][] = [];
  for (let i = 0; i < count; i++) {
    const o = i * 6;
    const sx = edges.pos[o];
    const sy = edges.pos[o + 1];
    const sz = edges.pos[o + 2];
    const ex = edges.pos[o + 3];
    const ey = edges.pos[o + 4];
    const ez = edges.pos[o + 5];
    const mx = (sx + ex) / 2;
    const my = (sy + ey) / 2;
    const mz = (sz + ez) / 2;
    const da =
      edges.na[i * 3] * (view.x - mx) + edges.na[i * 3 + 1] * (view.y - my) + edges.na[i * 3 + 2] * (view.z - mz);
    const db =
      edges.nb[i * 3] * (view.x - mx) + edges.nb[i * 3 + 1] * (view.y - my) + edges.nb[i * 3 + 2] * (view.z - mz);
    if (!blocks && da * db > 0) continue;
    const oa = boilOffset(sx, sy, sz, step, amp);
    const ob = boilOffset(ex, ey, ez, step, amp);
    A.push([sx + oa[0], sy + oa[1], sz + oa[2]]);
    B.push([ex + ob[0], ey + ob[1], ez + ob[2]]);
  }

  const n = A.length;
  const adj = new Map<string, number[]>();
  const add = (k: string, i: number) => {
    const list = adj.get(k);
    if (list) list.push(i);
    else adj.set(k, [i]);
  };
  for (let i = 0; i < n; i++) {
    add(keyOf(A[i]), i);
    add(keyOf(B[i]), i);
  }

  const used = new Uint8Array(n);
  const out: number[][] = [];
  for (let i = 0; i < n; i++) {
    if (used[i]) continue;
    used[i] = 1;
    const fwd: number[][] = [B[i]];
    let key = keyOf(B[i]);
    for (;;) {
      const next = adj.get(key)?.find((j) => !used[j]);
      if (next === undefined) break;
      used[next] = 1;
      const atA = keyOf(A[next]) === key;
      fwd.push(atA ? B[next] : A[next]);
      key = atA ? keyOf(B[next]) : keyOf(A[next]);
    }
    const bwd: number[][] = [];
    key = keyOf(A[i]);
    for (;;) {
      const next = adj.get(key)?.find((j) => !used[j]);
      if (next === undefined) break;
      used[next] = 1;
      const atB = keyOf(B[next]) === key;
      bwd.push(atB ? A[next] : B[next]);
      key = atB ? keyOf(A[next]) : keyOf(B[next]);
    }
    const pts = [...bwd.reverse(), A[i], ...fwd];
    out.push(smoothChaikin(pts, 2).flat());
  }
  return out;
}
