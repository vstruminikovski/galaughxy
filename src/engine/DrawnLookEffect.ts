import { BlendFunction, Effect, EffectAttribute } from 'postprocessing';
import * as THREE from 'three';

/**
 * "Grease Pencil" hand-drawn look as a single screen pass:
 *  - ink outlines from depth discontinuities + colour edges (Sobel)
 *  - line boil: the sampling jitters with noise that re-rolls 12×/sec (on twos)
 *  - pencil hatching in shadows, gentle paint posterize, paper grain
 */
const frag = /* glsl */ `
uniform float uTime;
uniform float uInk;
uniform float uThickness;
uniform float uHatch;
uniform float uPaper;
uniform float uBoil;
uniform vec3 uInkColor;
uniform float uBlocks;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float vnoise(vec2 p) {
  vec2 i = floor(p), f = fract(p);
  vec2 u = f * f * (3.0 - 2.0 * f);
  return mix(mix(hash(i), hash(i + vec2(1, 0)), u.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), u.x), u.y);
}
float lum(vec3 c) { return dot(c, vec3(0.299, 0.587, 0.114)); }
float linDepth(vec2 uv) { return -getViewZ(readDepth(uv)); }

void mainImage(const in vec4 inputColor, const in vec2 uv, const in float depth, out vec4 outputColor) {
  float frame = floor(uTime * 12.0);              // redraw the drawing 12 times a second
  vec2 px = texelSize * uThickness;

  // line boil: wobble where we sample edges, re-rolled every drawn frame
  vec2 w = vec2(vnoise(uv * 9.0 + frame * 17.3), vnoise(uv * 9.0 - frame * 11.1)) - 0.5;
  vec2 suv = uv + w * texelSize * 3.0 * uBoil;

  float dC = linDepth(suv);
  float gx = 0.0, gy = 0.0, cx = 0.0, cy = 0.0;
  for (int i = -1; i <= 1; i++) {
    for (int j = -1; j <= 1; j++) {
      if (i == 0 && j == 0) continue;
      vec2 o = vec2(float(i), float(j)) * px;
      float kx = float(i) * (j == 0 ? 2.0 : 1.0);
      float ky = float(j) * (i == 0 ? 2.0 : 1.0);
      float d = linDepth(suv + o) / max(dC, 0.001);
      float l = lum(texture2D(inputBuffer, suv + o).rgb);
      gx += d * kx; gy += d * ky;
      cx += l * kx; cy += l * ky;
    }
  }
  float depthEdge = smoothstep(0.12, 0.35, length(vec2(gx, gy)));
  float colorEdge = smoothstep(0.25, 0.6, length(vec2(cx, cy)));
  // pencil pressure varies along the stroke
  float pressure = 0.65 + 0.35 * vnoise(uv * resolution * 0.08 + frame * 3.7);
  // silhouettes always; block (colour-seam) lines only when uBlocks is on
  float ink = clamp(max(depthEdge, colorEdge * 0.7 * uBlocks) * pressure, 0.0, 1.0) * uInk;

  // paint: soft posterize toward flat cel fills
  vec3 col = inputColor.rgb;
  float L = lum(col);
  float steps = 5.0;
  float Lq = floor(L * steps + 0.5) / steps;
  col *= mix(1.0, Lq / max(L, 0.001), 0.45);

  // cross-hatching in the shadows, boiling with the lines
  vec2 sp = uv * resolution / uThickness;
  float jit = (vnoise(sp * 0.05 + frame * 5.1) - 0.5) * 3.0;
  float h1 = smoothstep(0.7, 0.98, sin((sp.x + sp.y + jit) * 0.42) * 0.5 + 0.5);
  float h2 = smoothstep(0.7, 0.98, sin((sp.x - sp.y + jit) * 0.42) * 0.5 + 0.5);
  float shade = smoothstep(0.3, 0.06, L);
  float hatch = (h1 * smoothstep(0.0, 0.5, shade) + h2 * smoothstep(0.5, 1.0, shade)) * uHatch;

  // paper tooth
  float paper = vnoise(uv * resolution * 0.35) * 0.6 + vnoise(uv * resolution * 0.9) * 0.4;
  col *= 1.0 - (paper - 0.5) * 0.12 * uPaper;
  col = mix(col, col * 0.94 + vec3(0.03, 0.025, 0.0), uPaper * 0.5);  // warm paper cast

  col = mix(col, uInkColor, clamp(hatch * 0.55, 0.0, 1.0));
  col = mix(col, uInkColor, ink);
  outputColor = vec4(col, inputColor.a);
}
`;

export class DrawnLookEffect extends Effect {
  constructor({ ink = 1, thickness = 1.2, hatch = 0, paper = 0, boil = 1, blocks = 0, inkColor = '#1c1712' } = {}) {
    super('DrawnLookEffect', frag, {
      blendFunction: BlendFunction.NORMAL,
      attributes: EffectAttribute.DEPTH,
      uniforms: new Map<string, THREE.Uniform>([
        ['uTime', new THREE.Uniform(0)],
        ['uInk', new THREE.Uniform(ink)],
        ['uThickness', new THREE.Uniform(thickness)],
        ['uHatch', new THREE.Uniform(hatch)],
        ['uPaper', new THREE.Uniform(paper)],
        ['uBoil', new THREE.Uniform(boil)],
        ['uBlocks', new THREE.Uniform(blocks)],
        ['uInkColor', new THREE.Uniform(new THREE.Color(inkColor))],
      ]),
    });
  }

  set(p: { ink?: number; thickness?: number; hatch?: number; boil?: number; blocks?: number }) {
    if (p.blocks !== undefined) this.uniforms.get('uBlocks')!.value = p.blocks;
    if (p.ink !== undefined) this.uniforms.get('uInk')!.value = p.ink;
    if (p.thickness !== undefined) this.uniforms.get('uThickness')!.value = p.thickness;
    if (p.hatch !== undefined) this.uniforms.get('uHatch')!.value = p.hatch;
    if (p.boil !== undefined) this.uniforms.get('uBoil')!.value = p.boil;
  }

  update(_r: THREE.WebGLRenderer, _i: THREE.WebGLRenderTarget, dt?: number) {
    this.uniforms.get('uTime')!.value += dt ?? 0;
  }
}
