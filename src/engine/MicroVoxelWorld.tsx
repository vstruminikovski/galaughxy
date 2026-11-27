import { useMemo } from 'react';
import { useStudioStore } from '../store/useStudioStore';
import type { Voxel } from '../types';
import { VoxelModelMesh, type VoxelHit } from './VoxelModelMesh';
import { parseKey, vkey } from './voxels';

/** "*#hex" = emissive voxel. */
export const encodeVoxel = (c: string, glow: boolean) => (glow ? `*${c}` : c);
const decode = (k: string, s: string): Voxel => {
  const [x, y, z] = parseKey(k);
  return s.startsWith('*') ? { x, y, z, c: s.slice(1), e: true } : { x, y, z, c: s };
};

/**
 * The room itself: procedural base voxels (never persisted) + scene.json deltas.
 * In Studio mode with a brush active, taps paint / add / erase world cubes.
 */
export function MicroVoxelWorld({ base, editable }: { base: Map<string, string>; editable: boolean }) {
  const deltas = useStudioStore((s) => s.scene.voxels);

  const voxels = useMemo(() => {
    const merged = new Map(base);
    for (const [k, v] of Object.entries(deltas)) {
      if (v === null) merged.delete(k);
      else merged.set(k, v);
    }
    return [...merged].map(([k, s]) => decode(k, s));
  }, [base, deltas]);

  const onVoxelClick = ({ voxel, normal }: VoxelHit, e: { stopPropagation: () => void }) => {
    const st = useStudioStore.getState();
    if (st.brush === 'off') return;
    e.stopPropagation();
    const key = vkey(voxel.x, voxel.y, voxel.z);
    const value = encodeVoxel(st.brushColor, st.brushGlow);
    if (st.brush === 'paint') st.setWorldVoxel(key, value);
    else if (st.brush === 'erase') st.setWorldVoxel(key, base.has(key) ? null : undefined);
    else st.setWorldVoxel(vkey(voxel.x + Math.round(normal.x), voxel.y + Math.round(normal.y), voxel.z + Math.round(normal.z)), value);
  };

  return <VoxelModelMesh voxels={voxels} onVoxelClick={editable ? onVoxelClick : undefined} />;
}
