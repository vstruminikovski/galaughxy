import { useFrame } from '@react-three/fiber';
import { useRef } from 'react';
import * as THREE from 'three';
import type { Vec3 } from '../types';
import { loadEpisode } from '../scenes/loadEpisode';

export interface ScenePortalProps {
  /** Slug of the scene this doorway leads to. */
  to: string;
  position: Vec3;
  rotationY?: number;
  active?: boolean;
}

/** A glowing doorway. Tap it (or walk into view and tap) to travel to the linked scene. */
export function ScenePortal({ to, position, rotationY = 0, active = false }: ScenePortalProps) {
  const glow = useRef<THREE.MeshStandardMaterial>(null);
  useFrame(({ clock }) => {
    if (glow.current) glow.current.emissiveIntensity = active ? 0.8 + Math.sin(clock.elapsedTime * 3) * 0.4 : 0.05;
  });
  return (
    <group
      position={position}
      rotation={[0, rotationY, 0]}
      userData={{ portalTo: to }}
      onClick={(e) => {
        e.stopPropagation();
        loadEpisode(to);
      }}
    >
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
      <mesh position={[0, 1.05, 0.01]}>
        <boxGeometry args={[0.84, 2.08, 0.06]} />
        <meshStandardMaterial ref={glow} color="#7fd4ff" emissive="#7fd4ff" emissiveIntensity={0.05} />
      </mesh>
    </group>
  );
}
