import type { Episode, SceneDoc } from '../../types';
import { buildKitchenRoom } from './room';
import sceneJson from './scene.json';

export const overflowingKitchen: Episode = {
  slug: 'overflowing-kitchen',
  title: 'The Overflowing Kitchen',
  skyColor: '#8fc4e8',
  bounds: { minX: -3, maxX: 3, minZ: -2.5, maxZ: 2.5 },
  cameras: {
    static: { pos: [0, 1.7, 7.2], target: [0, 1.0, 0], fov: 38, punchFov: 16 },
    slider: { start: [-2.6, 1.3, 3.6], end: [2.6, 1.3, 3.6], lookOffset: [0, -0.25, -3.6], fov: 38 },
    drone: { center: [0, 0.4, 0], radius: 6.5, height: 5.5, orbitSpeed: 0.08, fov: 38 },
  },
  buildBaseVoxels: buildKitchenRoom,
  scene: sceneJson as SceneDoc,
};

// Saving the scene rewrites scene.json; accept the update so the live session isn't reloaded.
if (import.meta.hot) import.meta.hot.accept();
