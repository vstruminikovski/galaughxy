import type { ThreeEvent } from '@react-three/fiber';
import { useLayoutEffect, useMemo, useRef } from 'react';
import * as THREE from 'three';
import type { Voxel } from '../types';
import { capacityFor, cullHidden, fillInstances, glowVoxelMaterial, litVoxelMaterial, voxelGeometry } from './voxels';

export interface VoxelHit {
  voxel: Voxel;
  normal: THREE.Vector3;
}

/**
 * Renders any voxel list as 2 draw calls max (lit + glowing), with hidden-voxel culling.
 * `onVoxelClick` reports which voxel + face was tapped, for in-world editing.
 */
export function VoxelModelMesh({
  voxels,
  onVoxelClick,
  castShadow = true,
}: {
  voxels: Voxel[];
  onVoxelClick?: (hit: VoxelHit, e: ThreeEvent<MouseEvent>) => void;
  castShadow?: boolean;
}) {
  const litRef = useRef<THREE.InstancedMesh>(null);
  const glowRef = useRef<THREE.InstancedMesh>(null);

  const { lit, glow } = useMemo(() => {
    const visible = cullHidden(voxels);
    return { lit: visible.filter((v) => !v.e), glow: visible.filter((v) => v.e) };
  }, [voxels]);

  const litCap = capacityFor(lit.length);
  const glowCap = capacityFor(glow.length);

  useLayoutEffect(() => {
    if (litRef.current) fillInstances(litRef.current, lit);
    if (glowRef.current) fillInstances(glowRef.current, glow);
  }, [lit, glow, litCap, glowCap]);

  const handler = (list: Voxel[]) =>
    onVoxelClick
      ? (e: ThreeEvent<MouseEvent>) => {
          if (e.instanceId === undefined || !e.face) return;
          const v = list[e.instanceId];
          if (v) onVoxelClick({ voxel: v, normal: e.face.normal.clone() }, e);
        }
      : undefined;

  return (
    <>
      <instancedMesh
        key={`l${litCap}`}
        ref={litRef}
        args={[voxelGeometry, litVoxelMaterial, litCap]}
        castShadow={castShadow}
        receiveShadow
        onClick={handler(lit)}
      />
      {glow.length > 0 && (
        <instancedMesh
          key={`g${glowCap}`}
          ref={glowRef}
          args={[voxelGeometry, glowVoxelMaterial, glowCap]}
          onClick={handler(glow)}
        />
      )}
    </>
  );
}
