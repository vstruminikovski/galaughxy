import type { Episode, SceneDoc } from '../../types';
import { pondGround } from './heightmap';
import { PondEnvironment } from './PondEnvironment';
import sceneJson from './scene.json';

/** Nature-documentary episode: Blender-sculpted habitat + sculpted frog, telephoto lenses. */
export const pondLife: Episode = {
  slug: 'pond-life',
  title: 'Pond Life',
  tagline: 'a nature mockumentary',
  look: 'nature',
  skyColor: '#b9cfc4',
  bounds: { minX: -5.5, maxX: 5.5, minZ: -4.5, maxZ: 4.5 },
  cameras: {
    static: { pos: [0.35, 0.55, 3.9], target: [-0.3, 0.28, 1.2], fov: 22, punchFov: 9 },
    slider: { start: [-1.8, 0.45, 3.4], end: [1.6, 0.45, 3.4], lookOffset: [0, -0.18, -2.2], fov: 26 },
    drone: { center: [0.3, 0, -0.8], radius: 6.2, height: 3.8, orbitSpeed: 0.06, fov: 34 },
  },
  Environment: PondEnvironment,
  ground: pondGround,
  waterRest: -0.12,
  floodScale: 0.5,
  scene: sceneJson as SceneDoc,
};

if (import.meta.hot) import.meta.hot.accept();
