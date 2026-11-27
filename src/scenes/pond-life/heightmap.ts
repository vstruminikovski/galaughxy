/** Ground height sampled from the Blender-exported heightmap (Three coords: z = -blenderY). */
interface HeightData {
  x0: number;
  y0: number;
  step: number;
  nx: number;
  ny: number;
  waterLevel: number;
  h: number[][];
}

let data: HeightData | null = null;
export const heightReady = fetch(`${import.meta.env.BASE_URL}models/pond_height.json`)
  .then((r) => r.json())
  .then((d: HeightData) => {
    data = d;
  })
  .catch(() => {
    data = null;
  });

export function pondGround(x: number, z: number): number {
  if (!data) return 0;
  const by = -z;
  const fx = Math.min(data.nx - 1.001, Math.max(0, (x - data.x0) / data.step));
  const fy = Math.min(data.ny - 1.001, Math.max(0, (by - data.y0) / data.step));
  const i = Math.floor(fx);
  const j = Math.floor(fy);
  const tx = fx - i;
  const ty = fy - j;
  const h = data.h;
  const a = h[j][i] * (1 - tx) + h[j][i + 1] * tx;
  const b = h[j + 1][i] * (1 - tx) + h[j + 1][i + 1] * tx;
  return a * (1 - ty) + b * ty;
}
