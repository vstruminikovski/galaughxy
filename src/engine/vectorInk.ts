import { InstancedBufferAttribute, Vector3 } from 'three';
import { LineMaterial } from 'three/examples/jsm/lines/LineMaterial.js';
import { LineSegmentsGeometry } from 'three/examples/jsm/lines/LineSegmentsGeometry.js';
import type { Voxel } from '../types';

/**
 * Vector ink: every outline is real line geometry (no screen-space pixel pass).
 *
 * For each cube edge that touches the exposed surface we store the two surface normals of the
 * faces meeting there. The vertex shader keeps an edge only if one face points toward the camera
 * and the other away (a silhouette), so the outline is view-correct and stays sharp at any size.
 */
export interface InkEdges {
  pos: Float32Array; // 6 floats per segment: start xyz, end xyz (object space, metres)
  na: Float32Array; // normal of the first face at the edge
  nb: Float32Array; // normal of the second face (equal to na if the edge has one face)
  ws: Float32Array; // pressure at the start point (shared by every stroke meeting there)
  we: Float32Array; // pressure at the end point
}

/** Stable pressure in [0.45, 1] per point, so strokes that meet at a point share its width. */
const pressure = (x: number, y: number, z: number) => {
  const n = Math.sin(x * 127.1 + y * 311.7 + z * 74.7) * 43758.5453;
  return 0.45 + 0.55 * (n - Math.floor(n));
};

export function buildInkEdges(voxels: Voxel[], size: number): InkEdges {
  const solid = new Set<string>();
  for (const v of voxels) solid.add(`${v.x},${v.y},${v.z}`);
  const isSolid = (c: number[]) => solid.has(`${c[0]},${c[1]},${c[2]}`);

  const seen = new Set<string>();
  const pos: number[] = [];
  const na: number[] = [];
  const nb: number[] = [];
  const ws: number[] = [];
  const we: number[] = [];

  for (const v of voxels)
    for (let A = 0; A < 3; A++) {
      const P = (A + 1) % 3;
      const Q = (A + 2) % 3;
      for (let a = 0; a < 2; a++)
        for (let b = 0; b < 2; b++) {
          const p = [v.x, v.y, v.z];
          p[P] += a;
          p[Q] += b;
          const key = `${A}:${p[0]},${p[1]},${p[2]}`;
          if (seen.has(key)) continue;
          seen.add(key);

          // the four cells around this edge
          const cell = (pp: number, qq: number) => {
            const c = [0, 0, 0];
            c[A] = p[A];
            c[P] = pp;
            c[Q] = qq;
            return c;
          };
          const normals: number[][] = [];
          // faces separating cells that differ along P
          for (let dq = -1; dq <= 0; dq++) {
            const ca = cell(p[P] - 1, p[Q] + dq);
            const cb = cell(p[P], p[Q] + dq);
            const sa = isSolid(ca);
            if (sa !== isSolid(cb)) {
              const n = [0, 0, 0];
              n[P] = sa ? 1 : -1;
              normals.push(n);
            }
          }
          // faces separating cells that differ along Q
          for (let dp = -1; dp <= 0; dp++) {
            const ca = cell(p[P] + dp, p[Q] - 1);
            const cb = cell(p[P] + dp, p[Q]);
            const sa = isSolid(ca);
            if (sa !== isSolid(cb)) {
              const n = [0, 0, 0];
              n[Q] = sa ? 1 : -1;
              normals.push(n);
            }
          }
          if (!normals.length) continue;

          const s = [p[0] * size, p[1] * size, p[2] * size];
          const e = [...s];
          e[A] += size;
          pos.push(...s, ...e);
          const n0 = normals[0];
          const n1 = normals[1] ?? normals[0];
          na.push(...n0);
          nb.push(...n1);
          ws.push(pressure(s[0], s[1], s[2]));
          we.push(pressure(e[0], e[1], e[2]));
        }
    }

  return {
    pos: Float32Array.from(pos),
    na: Float32Array.from(na),
    nb: Float32Array.from(nb),
    ws: Float32Array.from(ws),
    we: Float32Array.from(we),
  };
}

/** Line material with the silhouette test and the 12fps boil added to its vertex shader. */
export function createInkMaterial(color: string) {
  const mat = new LineMaterial({ color, linewidth: 2, worldUnits: false });
  const uniforms = {
    uViewObj: { value: new Vector3() }, // camera position in the object's own space
    uBlocks: { value: 0 }, // 1 = draw every edge (block outlines), 0 = silhouettes only
    uStep: { value: 0 }, // current drawn frame (12 per second)
    uBoilAmp: { value: 0 }, // wobble amplitude in metres
  };
  mat.userData.uniforms = uniforms;
  mat.onBeforeCompile = (shader) => {
    Object.assign(shader.uniforms, uniforms);
    shader.vertexShader = shader.vertexShader
      .replace(
        '#include <common>',
        `#include <common>
        attribute vec3 instanceNA;
        attribute vec3 instanceNB;
        attribute float instanceWS;
        attribute float instanceWE;
        uniform vec3 uViewObj;
        uniform float uBlocks;
        uniform float uStep;
        uniform float uBoilAmp;
        vec3 inkBoil(vec3 p) {
          vec3 s = floor(p * 4096.0);
          float a = fract(sin(dot(s, vec3(12.9898, 78.233, 37.719)) + uStep * 0.731) * 43758.5453);
          float b = fract(sin(dot(s, vec3(93.9898, 67.345, 11.135)) + uStep * 1.17) * 24634.6345);
          float c = fract(sin(dot(s, vec3(41.1, 289.3, 173.7)) + uStep * 0.419) * 15731.743);
          return (vec3(a, b, c) - 0.5) * uBoilAmp;
        }`,
      )
      .replace(
        'vec4 start = modelViewMatrix * vec4( instanceStart, 1.0 );',
        `vec3 bS = instanceStart + inkBoil(instanceStart);
        vec3 bE = instanceEnd + inkBoil(instanceEnd);
        vec3 mid = (bS + bE) * 0.5;
        float da = dot(instanceNA, uViewObj - mid);
        float db = dot(instanceNB, uViewObj - mid);
        bool hideEdge = uBlocks < 0.5 && da * db > 0.0;
        vec4 start = modelViewMatrix * vec4( bS, 1.0 );`,
      )
      .replace('vec4 end = modelViewMatrix * vec4( instanceEnd, 1.0 );', 'vec4 end = modelViewMatrix * vec4( bE, 1.0 );')
      .replace(/offset \*= linewidth;/g, 'offset *= linewidth * ((position.y < 0.5) ? instanceWS : instanceWE);')
      .replace('gl_Position = clip;', 'gl_Position = hideEdge ? vec4(0.0, 0.0, 2.0, 1.0) : clip;');
  };
  return mat;
}

export function inkGeometry(edges: InkEdges) {
  const g = new LineSegmentsGeometry();
  g.setPositions(edges.pos);
  g.setAttribute('instanceNA', new InstancedBufferAttribute(edges.na, 3));
  g.setAttribute('instanceNB', new InstancedBufferAttribute(edges.nb, 3));
  g.setAttribute('instanceWS', new InstancedBufferAttribute(edges.ws, 1));
  g.setAttribute('instanceWE', new InstancedBufferAttribute(edges.we, 1));
  return g;
}
