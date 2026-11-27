import { vkey } from '../../engine/voxels';

/**
 * Procedural sitcom-style kitchen shell: checker floor, two walls, window cut-out,
 * baseboard, and a glowing neon trim line. Generated at load — never stored in scene.json.
 * Floor top sits at y = 0; room spans x -3..3, z -2.5..2.5 metres.
 */
export function buildKitchenRoom(): Map<string, string> {
  const m = new Map<string, string>();
  // floor (y = -1 layer), 0.5 m checker tiles
  for (let x = -30; x < 30; x++)
    for (let z = -25; z < 25; z++) {
      const checker = (Math.floor((x + 30) / 5) + Math.floor((z + 25) / 5)) % 2 === 0;
      m.set(vkey(x, -1, z), checker ? '#f1e6d0' : '#cdb894');
    }
  const wallColor = (y: number, base: string) =>
    y === 0 ? '#5a3b24' : y === 11 ? '*#29e6ff' : y < 11 ? '#5fa8a0' : base;
  // back wall (z = -26) with a window
  for (let x = -31; x < 30; x++)
    for (let y = 0; y < 30; y++) {
      const inWindow = x >= -4 && x <= 7 && y >= 15 && y <= 22;
      if (inWindow) continue;
      const frame = x >= -5 && x <= 8 && y >= 14 && y <= 23;
      m.set(vkey(x, y, -26), frame ? '#ffffff' : wallColor(y, '#9fd3c7'));
    }
  // left wall (x = -31)
  for (let z = -26; z < 25; z++) for (let y = 0; y < 30; y++) m.set(vkey(-31, y, z), wallColor(y, '#f4c97a'));
  return m;
}
