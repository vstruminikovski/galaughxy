import { useFrame } from '@react-three/fiber';
import { useRef } from 'react';
import * as THREE from 'three';
import type { Vec3 } from '../types';

export interface ScenePortalProps {
  /** Slug of the episode room this doorway will lead to in Phase 2. */
  to: string;
  position: Vec3;
  rotationY?: number;
  /** Dormant portals render a closed door and never fire. */
  active?: boolean;
  onEnter?: (to: string) => void;
}

/**
 * Phase 2 world-stitching hook. Every episode room keeps at least one dormant portal so
 * episodes can later be chained into a continuous game world without touching room code.
 */
export function ScenePortal({ to, position, rotationY = 0, active = false }: ScenePortalProps) {
  const glow = useRef<THREE.MeshStandardMaterial>(null);
  useFrame(({ clock }) => {
    if (glow.current) glow.current.emissiveIntensity = active ? 0.8 + Math.sin(clock.elapsedTime * 3) * 0.4 : 0.05;
  });
  return (
    <group position={position} rotation={[0, rotationY, 0]} userData={{ portalTo: to }}>
      {/* frame */}
      <mesh position={[-0.47, 1.05, 0]} castShadow>
        <boxGeometry args={[0.1, 2.1, 0.14]} />
        <meshStandardMaterial color="#6b4a2f" />
      </mesh>
      <mesh position={[0.47, 1.05, 0]} castShadow>
        <boxGeometry args={[0.1, 2.1, 0.14]} />
        <meshStandardMaterial color="#6b4a2f" />
      </mesh>
      <mesh position={[0, 2.15, 0]} castShadow>
        <boxGeometry args={[1.04, 0.1, 0.14]} />
        <meshStandardMaterial color="#6b4a2f" />
      </mesh>
      {/* door slab */}
      <mesh position={[0, 1.05, 0.01]}>
        <boxGeometry args={[0.84, 2.08, 0.06]} />
        <meshStandardMaterial ref={glow} color="#a9744a" emissive="#ffd27a" emissiveIntensity={0.05} />
      </mesh>
      <mesh position={[0.3, 1.0, 0.06]}>
        <sphereGeometry args={[0.04, 12, 8]} />
        <meshStandardMaterial color="#d8b24a" metalness={0.9} roughness={0.3} />
      </mesh>
    </group>
  );
}
