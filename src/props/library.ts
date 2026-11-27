import type { VoxelModel } from '../types';
import { SEED_MODELS } from './seeds';

/** User-saved voxel assets (written by the dev server's /api/save-prop). */
const files = import.meta.glob<VoxelModel>('./library/*.json', { eager: true, import: 'default' });

export const LOCAL_LIBRARY_KEY = 'robo-world:library';

function fromLocalStorage(): VoxelModel[] {
  try {
    const raw = localStorage.getItem(LOCAL_LIBRARY_KEY);
    return raw ? (Object.values(JSON.parse(raw)) as VoxelModel[]) : [];
  } catch {
    return [];
  }
}

/** Seeds < repo JSON < on-device edits (later wins). */
export const initialLibrary: Record<string, VoxelModel> = Object.fromEntries(
  [...SEED_MODELS, ...Object.values(files), ...fromLocalStorage()].map((m) => [m.name, m]),
);

// The store already holds saved models in memory; don't full-reload when a JSON file is written.
if (import.meta.hot) import.meta.hot.accept();
