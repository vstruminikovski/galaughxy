import type { Episode, SceneDoc } from '../../types';
import { buildGarden } from './world';
import sceneJson from './scene.json';

/** Backyard Garden: the same voxel world style, a different room. */
export const garden: Episode = {
  slug: 'garden',
  title: 'Backyard Garden',
  tagline: 'lawn, fence, tiny tree',
  mapPos: [30, 24],
  mapIcon: '🌷',
  skyColor: '#a9d3ea',
  bounds: { minX: -5, maxX: 5, minZ: -4.5, maxZ: 4.5 },
  cameras: {
    static: { pos: [0, 1.6, 5.5], target: [0, 0.7, 0], fov: 38, punchFov: 18 },
    slider: { start: [-3.2, 1.3, 4.2], end: [3.2, 1.3, 4.2], lookOffset: [0, -0.3, -4], fov: 38 },
    drone: { center: [0, 0, 0], radius: 7, height: 5, orbitSpeed: 0.07, fov: 38 },
  },
  buildBaseVoxels: buildGarden,
  portals: [{ to: 'pond-life', position: [0, 0, -4.8], rotationY: 0 }],
  scene: sceneJson as SceneDoc,
};

if (import.meta.hot) import.meta.hot.accept();
