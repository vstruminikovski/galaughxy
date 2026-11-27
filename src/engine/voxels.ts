import * as THREE from 'three';
import type { Voxel } from '../types';

export const VOXEL_SIZE = 0.1;
export const vkey = (x: number, y: number, z: number) => `${x},${y},${z}`;
export const parseKey = (k: string) => k.split(',').map(Number) as [number, number, number];

const NEIGHBORS: [number, number, number][] = [
  [1, 0, 0],
  [-1, 0, 0],
  [0, 1, 0],
  [0, -1, 0],
  [0, 0, 1],
  [0, 0, -1],
];

/** Drop voxels enclosed on all 6 faces — they can never be seen. */
export function cullHidden<T extends { x: number; y: number; z: number }>(voxels: T[]): T[] {
  const set = new Set(voxels.map((v) => vkey(v.x, v.y, v.z)));
  return voxels.filter((v) => !NEIGHBORS.every(([dx, dy, dz]) => set.has(vkey(v.x + dx, v.y + dy, v.z + dz))));
}

/** Fill an inclusive voxel box. */
export function vbox(
  x0: number,
  x1: number,
  y0: number,
  y1: number,
  z0: number,
  z1: number,
  c: string,
  e?: boolean,
): Voxel[] {
  const out: Voxel[] = [];
  for (let x = Math.min(x0, x1); x <= Math.max(x0, x1); x++)
    for (let y = Math.min(y0, y1); y <= Math.max(y0, y1); y++)
      for (let z = Math.min(z0, z1); z <= Math.max(z0, z1); z++) out.push(e ? { x, y, z, c, e } : { x, y, z, c });
  return out;
}

/** Merge voxel lists; later entries overwrite earlier ones at the same cell. */
export function vmerge(...lists: Voxel[][]): Voxel[] {
  const m = new Map<string, Voxel>();
  for (const l of lists) for (const v of l) m.set(vkey(v.x, v.y, v.z), v);
  return [...m.values()];
}

export const voxelGeometry = new THREE.BoxGeometry(VOXEL_SIZE, VOXEL_SIZE, VOXEL_SIZE);
export const litVoxelMaterial = new THREE.MeshStandardMaterial({ roughness: 0.78, metalness: 0.05 });
/** Unlit + not tone-mapped so emissive voxels read as glowing LEDs. */
export const glowVoxelMaterial = new THREE.MeshBasicMaterial({ toneMapped: false });

const _m = new THREE.Matrix4();
const _c = new THREE.Color();

/**
 * Writes voxels into an InstancedMesh. `index` maps instanceId -> voxel so editors can raycast.
 * Positions are voxel centres, so voxel (0,0,0) spans 0..0.1 on every axis.
 */
export function fillInstances(
  mesh: THREE.InstancedMesh,
  voxels: { x: number; y: number; z: number; c: string }[],
  size = VOXEL_SIZE,
) {
  voxels.forEach((v, i) => {
    _m.makeTranslation((v.x + 0.5) * size, (v.y + 0.5) * size, (v.z + 0.5) * size);
    mesh.setMatrixAt(i, _m);
    mesh.setColorAt(i, _c.set(v.c));
  });
  mesh.count = voxels.length;
  mesh.instanceMatrix.needsUpdate = true;
  if (mesh.instanceColor) mesh.instanceColor.needsUpdate = true;
  mesh.computeBoundingSphere();
  mesh.computeBoundingBox();
}

/** Capacity bucket so small edits don't reallocate GPU buffers. */
export const capacityFor = (n: number) => Math.ceil((n + 128) / 512) * 512;
