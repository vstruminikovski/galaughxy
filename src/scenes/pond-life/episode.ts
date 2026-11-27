import type { Episode, SceneDoc } from '../../types';
import { pondGround, pondWorld } from './world';
import sceneJson from './scene.json';

/** Pond Life: Bog the frog in a voxel pond. Telephoto-ish lenses, same square-voxel style as every scene. */
export const pondLife: Episode = {
  slug: 'pond-life',
  title: 'Pond Life',
  tagline: 'a nature mockumentary',
  mapPos: [72, 40],
  mapIcon: '🐸',
  skyColor: '#b9cfc4',
  bounds: { minX: -5.5, maxX: 5.5, minZ: -4.5, maxZ: 4.5 },
  cameras: {
    static: { pos: [0.35, 0.55, 3.9], target: [-0.3, 0.28, 1.2], fov: 22, punchFov: 9 },
    slider: { start: [-1.8, 0.45, 3.4], end: [1.6, 0.45, 3.4], lookOffset: [0, -0.18, -2.2], fov: 26 },
    drone: { center: [0.3, 0, -0.8], radius: 6.2, height: 3.8, orbitSpeed: 0.06, fov: 34 },
  },
  buildBaseVoxels: () => pondWorld().voxels,
  ground: pondGround,
  waterRest: 0,
  floodScale: 0.5,
  portals: [
    { to: 'overflowing-kitchen', position: [-5.4, 0, 3.6], rotationY: Math.PI / 2 },
    { to: 'garden', position: [5.4, 0, -3.4], rotationY: -Math.PI / 2 },
  ],
  scene: sceneJson as SceneDoc,
};

if (import.meta.hot) import.meta.hot.accept();
