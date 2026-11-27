import type { Episode, SceneDoc } from '../../types';
import { buildKitchenRoom } from './room';
import sceneJson from './scene.json';

export const overflowingKitchen: Episode = {
  slug: 'overflowing-kitchen',
  title: 'The Overflowing Kitchen',
  tagline: 'flood the kitchen!',
  mapPos: [24, 62],
  mapIcon: '🍳',
  skyColor: '#8fc4e8',
  bounds: { minX: -3, maxX: 3, minZ: -2.5, maxZ: 2.5 },
  cameras: {
    static: { pos: [0, 1.7, 7.2], target: [0, 1.0, 0], fov: 38, punchFov: 16 },
    slider: { start: [-2.6, 1.3, 3.6], end: [2.6, 1.3, 3.6], lookOffset: [0, -0.25, -3.6], fov: 38 },
    drone: { center: [0, 0.4, 0], radius: 6.5, height: 5.5, orbitSpeed: 0.08, fov: 38 },
  },
  buildBaseVoxels: buildKitchenRoom,
  portals: [{ to: 'pond-life', position: [-2.95, 0, 0.9], rotationY: Math.PI / 2 }],
  scene: sceneJson as SceneDoc,
};

if (import.meta.hot) import.meta.hot.accept();
