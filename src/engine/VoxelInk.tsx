import { useFrame, useThree } from '@react-three/fiber';
import { useEffect, useMemo, useRef } from 'react';
import * as THREE from 'three';
import { useStudioStore } from '../store/useStudioStore';
import type { Voxel } from '../types';
import { buildContours, buildInkEdges } from './vectorInk';

const INK = '#7a1f1f'; // dark red
const BASE_WIDTH_PX = 3.6; // stroke width at 1080 px frame height (scales with output size)
const TWOS = 12;

/**
 * Vector ink strokes for one voxel object. Each contour becomes one ribbon that tapers
 * smoothly from its middle to both ends. Width is set in screen pixels, so the drawing
 * keeps the same proportions at every output size.
 */
export function VoxelInk({ voxels, size }: { voxels: Voxel[]; size: number }) {
  const drawn = useStudioStore((s) => s.drawn);
  const blocks = useStudioStore((s) => s.drawnBlocks || (s.mode === 'studio' && s.brush !== 'off'));
  const boil = useStudioStore((s) => s.drawnBoil);
  const inkWidth = useStudioStore((s) => s.drawnInk);
  const scene = useThree((s) => s.scene);

  const edges = useMemo(() => buildInkEdges(voxels, size), [voxels, size]);
  const anchor = useMemo(() => new THREE.Object3D(), []);
  const mat = useMemo(
    () => new THREE.MeshBasicMaterial({ color: INK, side: THREE.DoubleSide, toneMapped: false }),
    [],
  );
  const mesh = useMemo(() => {
    const m = new THREE.Mesh(new THREE.BufferGeometry(), mat);
    m.frustumCulled = false;
    m.raycast = () => {}; // ink never steals taps from the voxels
    return m;
  }, [mat]);
  const lastKey = useRef('');

  useEffect(() => {
    scene.add(mesh);
    return () => {
      scene.remove(mesh);
      mesh.geometry.dispose();
    };
  }, [scene, mesh]);
  useEffect(() => () => mat.dispose(), [mat]);
  useEffect(() => {
    lastKey.current = ''; // edges changed, rebuild
  }, [edges]);

  const camW = useMemo(() => new THREE.Vector3(), []);
  const inv = useMemo(() => new THREE.Matrix4(), []);
  const tangent = useMemo(() => new THREE.Vector3(), []);
  const toCam = useMemo(() => new THREE.Vector3(), []);
  const side = useMemo(() => new THREE.Vector3(), []);
  const up = useMemo(() => new THREE.Vector3(0, 1, 0), []);

  useFrame((state) => {
    mesh.visible = drawn;
    if (!drawn) return;
    const cam = state.camera as THREE.PerspectiveCamera;
    const step = Math.floor(state.clock.elapsedTime * TWOS);
    const amp = size * 0.25 * boil;
    const H = state.gl.domElement.height;
    camW.setFromMatrixPosition(cam.matrixWorld);
    const e = anchor.matrixWorld.elements;
    const key = [step, blocks ? 1 : 0, amp, inkWidth, H, cam.fov, ...e.map((v) => Math.round(v * 1e4)), ...camW.toArray().map((v) => Math.round(v * 1e3))].join('|');
    if (key === lastKey.current) return;
    lastKey.current = key;

    inv.copy(anchor.matrixWorld).invert();
    const viewLocal = camW.clone().applyMatrix4(inv);
    const contours = buildContours(edges, viewLocal, blocks, step, amp);

    const tanHalf = Math.tan(THREE.MathUtils.degToRad(cam.fov) / 2);
    const verts: number[] = [];
    const index: number[] = [];
    for (const flat of contours) {
      const n = flat.length / 3;
      if (n < 2) continue;
      const pts: THREE.Vector3[] = [];
      for (let i = 0; i < n; i++) pts.push(new THREE.Vector3(flat[i * 3], flat[i * 3 + 1], flat[i * 3 + 2]).applyMatrix4(anchor.matrixWorld));
      // arc length and taper along the stroke
      const cum = [0];
      for (let i = 1; i < n; i++) cum.push(cum[i - 1] + pts[i].distanceTo(pts[i - 1]));
      const L = cum[n - 1] || 1;
      const closed = pts[0].distanceTo(pts[n - 1]) < size * 0.6;
      const base = verts.length / 3;
      for (let i = 0; i < n; i++) {
        const t = cum[i] / L;
        const taper = closed ? 0.7 + 0.3 * Math.sin(Math.PI * 2 * t) : Math.max(0.1, Math.sin(Math.PI * t) ** 0.6);
        const p = pts[i];
        const q = pts[Math.min(n - 1, i + 1)];
        const r = pts[Math.max(0, i - 1)];
        tangent.subVectors(q, r);
        if (tangent.lengthSq() < 1e-12) tangent.set(1, 0, 0);
        tangent.normalize();
        toCam.subVectors(camW, p);
        const d = Math.max(toCam.length(), 1e-4);
        side.crossVectors(tangent, toCam);
        if (side.lengthSq() < 1e-12) side.crossVectors(tangent, up);
        side.normalize();
        // width in metres: BASE px at 1080 px tall, measured where the stroke sits
        const pressure = 0.8 + 0.2 * (Math.sin(p.x * 91.7 + p.y * 53.1 + p.z * 17.3) * 0.5 + 0.5);
        const worldW = (BASE_WIDTH_PX * inkWidth * 2 * tanHalf * d) / 1080;
        const hw = (worldW * taper * pressure) / 2;
        verts.push(p.x + side.x * hw, p.y + side.y * hw, p.z + side.z * hw);
        verts.push(p.x - side.x * hw, p.y - side.y * hw, p.z - side.z * hw);
      }
      for (let i = 0; i < n - 1; i++) {
        const a = base + i * 2;
        const b = a + 1;
        const c = a + 2;
        const dd = a + 3;
        index.push(a, c, b, b, c, dd);
      }
    }

    const geo = new THREE.BufferGeometry();
    geo.setAttribute('position', new THREE.Float32BufferAttribute(verts, 3));
    geo.setIndex(index);
    geo.computeBoundingSphere();
    mesh.geometry.dispose();
    mesh.geometry = geo;
  });

  return <primitive object={anchor} />;
}
