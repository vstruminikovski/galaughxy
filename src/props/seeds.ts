import { vbox, vmerge } from '../engine/voxels';
import type { Voxel, VoxelModel } from '../types';

/**
 * Starter voxel props, generated procedurally so the repo never stores giant voxel arrays.
 * All 100% original. Units are 0.1-unit voxels; origin is the bottom-centre-ish of each prop.
 */
const model = (name: string, voxels: Voxel[], extra: Partial<VoxelModel> = {}): VoxelModel => ({
  name,
  version: 1,
  voxels,
  ...extra,
});

function counter(): VoxelModel {
  const wood = '#b97a46';
  return model(
    'counter',
    vmerge(
      vbox(-12, 11, 0, 7, -3, 3, wood),
      vbox(-12, 11, 8, 8, -4, 3, '#efe9dc'),
      // cupboard seams + handles
      vbox(-4, -4, 1, 6, 4, 4, '#7a4f2c'),
      vbox(4, 4, 1, 6, 4, 4, '#7a4f2c'),
      vbox(-6, -6, 5, 5, 4, 4, '#d8b24a'),
      vbox(2, 2, 5, 5, 4, 4, '#d8b24a'),
      vbox(6, 6, 5, 5, 4, 4, '#d8b24a'),
    ),
  );
}

function sink(): VoxelModel {
  const steel = '#b8c2cc';
  const rim = vbox(-3, 3, 0, 0, -2, 2, steel);
  const basin = vbox(-2, 2, 0, 0, -1, 1, '#5d6c7a'); // dark basin floor inset
  const tap = vmerge(vbox(0, 0, 1, 4, -2, -2, steel), vbox(0, 0, 4, 4, -1, 0, steel), vbox(-1, -1, 1, 1, -2, -2, '#e05050'), vbox(1, 1, 1, 1, -2, -2, '#4f8fe0'));
  return model('kitchen-sink', vmerge(rim, basin, tap), { sockets: { tapSocket: [0.5, 3.5, 0.5] } });
}

function stove(): VoxelModel {
  const body = vbox(-4, 3, 0, 8, -3, 3, '#f2f2ee');
  const top = vbox(-4, 3, 9, 9, -3, 3, '#26262b');
  const burners = [
    [-3, -2],
    [1, -2],
    [-3, 1],
    [1, 1],
  ].flatMap(([x, z]) => vbox(x, x + 1, 10, 10, z, z + 1, '#ff6a2a', true));
  const window = vbox(-3, 2, 2, 5, 4, 4, '#3a3f48');
  const knobs = [-3, -1, 1].flatMap((x) => vbox(x, x, 7, 7, 4, 4, '#222'));
  return model('stove', vmerge(body, top, burners, window, knobs));
}

function fridge(): VoxelModel {
  return model(
    'fridge',
    vmerge(
      vbox(-4, 3, 0, 18, -3, 3, '#dfe8ef'),
      vbox(-4, 3, 12, 12, 4, 4, '#aab6bf'),
      vbox(2, 2, 13, 16, 4, 4, '#8b969e'),
      vbox(2, 2, 6, 10, 4, 4, '#8b969e'),
      vbox(-3, -2, 15, 16, 4, 4, '#ff5f87', true), // tiny LED status panel
    ),
  );
}

function fryingPan(): VoxelModel {
  const pan: Voxel[] = [];
  for (let x = -2; x <= 2; x++)
    for (let z = -2; z <= 2; z++) if (x * x + z * z <= 5) pan.push({ x: x + 4, y: 0, z, c: '#2b2b30' });
  const rim = pan.filter((v) => (v.x - 4) ** 2 + v.z ** 2 >= 4).map((v) => ({ ...v, y: 1 }));
  return model('frying-pan', vmerge(pan, rim, vbox(-1, 1, 0, 0, 0, 0, '#6b4226')), {
    sockets: { panSocket: [4, 1, 0], handleSocket: [-1, 0, 0] },
  });
}

function mug(): VoxelModel {
  const body: Voxel[] = [];
  for (let y = 0; y <= 1; y++)
    for (let x = -1; x <= 0; x++) for (let z = -1; z <= 0; z++) body.push({ x, y, z, c: '#e2574c' });
  return model('mug', vmerge(body, [{ x: 1, y: 1, z: 0, c: '#e2574c' }]), { floats: true });
}

function fish(): VoxelModel {
  const c = '#ff8c42';
  return model(
    'fish',
    vmerge(
      vbox(-1, 2, 0, 1, 0, 0, c),
      vbox(0, 1, 2, 2, 0, 0, c),
      vbox(-3, -2, 0, 1, 0, 0, '#ffb347'),
      vbox(-3, -3, -1, 2, 0, 0, '#ffb347'),
      [{ x: 2, y: 1, z: 1, c: '#111' }, { x: 2, y: 1, z: -1, c: '#111' }],
    ),
    { floats: true },
  );
}

function bucket(): VoxelModel {
  const c = '#3d8bd4';
  const walls: Voxel[] = [];
  for (let y = 0; y <= 3; y++)
    for (let x = -2; x <= 2; x++)
      for (let z = -2; z <= 2; z++) if (y === 0 || Math.abs(x) === 2 || Math.abs(z) === 2) walls.push({ x, y, z, c });
  return model('bucket', vmerge(walls, vbox(-2, 2, 4, 4, 0, 0, '#d9dde2').filter((v) => Math.abs(v.x) === 2 || v.x === 0)), {
    floats: true,
  });
}

function duck(): VoxelModel {
  return model(
    'robo-duck',
    vmerge(
      vbox(-2, 1, 0, 1, -1, 1, '#ffd23f'),
      vbox(0, 1, 2, 3, -1, 0, '#ffd23f'),
      vbox(2, 2, 2, 2, -1, 0, '#ff8a00'),
      [{ x: 1, y: 3, z: 1, c: '#20e3ff', e: true }],
      vbox(-3, -3, 1, 2, -1, 0, '#ffd23f'),
    ),
    { floats: true },
  );
}

function plant(): VoxelModel {
  return model(
    'pot-plant',
    vmerge(
      vbox(-1, 1, 0, 2, -1, 1, '#c8643b'),
      vbox(0, 0, 3, 6, 0, 0, '#3e8f3e'),
      vbox(-2, -1, 5, 5, 0, 0, '#5bbf5b'),
      vbox(1, 2, 6, 6, 0, 0, '#5bbf5b'),
      vbox(-1, 1, 7, 7, -1, 1, '#5bbf5b'),
    ),
  );
}

export const SEED_MODELS: VoxelModel[] = [counter(), sink(), stove(), fridge(), fryingPan(), mug(), fish(), bucket(), duck(), plant()];
