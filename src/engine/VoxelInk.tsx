import { useEffect, useMemo, useRef } from 'react';
import { LineSegments2 } from 'three/examples/jsm/lines/LineSegments2.js';
import { useFrame } from '@react-three/fiber';
import { useStudioStore } from '../store/useStudioStore';
import type { Voxel } from '../types';
import { buildInkEdges, createInkMaterial, inkGeometry } from './vectorInk';

const INK = '#9a8570'; // muted middle brown
const BASE_WIDTH_PX = 2.2; // at 1080p; scales with the output height

/** Vector grease-pencil outline for one voxel object. Thickness & wobble follow the output size. */
export function VoxelInk({ voxels, size }: { voxels: Voxel[]; size: number }) {
  const drawn = useStudioStore((s) => s.drawn);
  const blocks = useStudioStore((s) => s.drawnBlocks || (s.mode === 'studio' && s.brush !== 'off'));
  const boil = useStudioStore((s) => s.drawnBoil);
  const inkWidth = useStudioStore((s) => s.drawnInk);

  const edges = useMemo(() => buildInkEdges(voxels, size), [voxels, size]);
  const geo = useMemo(() => inkGeometry(edges), [edges]);
  const mat = useMemo(() => createInkMaterial(INK), []);
  const line = useMemo(() => {
    const l = new LineSegments2(geo, mat);
    l.raycast = () => {}; // ink never steals taps from the voxels
    return l;
  }, [geo, mat]);

  useEffect(() => () => geo.dispose(), [geo]);
  useEffect(() => () => mat.dispose(), [mat]);
  useEffect(() => {
    line.visible = drawn;
  }, [line, drawn]);

  const parent = useRef(line);
  parent.current = line;
  useFrame((state) => {
    const l = parent.current;
    const gl = state.gl.domElement;
    const u = mat.userData.uniforms;
    const inv = l.matrixWorld.clone().invert();
    u.uViewObj.value.copy(state.camera.position).applyMatrix4(inv);
    u.uStep.value = Math.floor(state.clock.elapsedTime * 12);
    u.uBlocks.value = blocks ? 1 : 0;
    u.uBoilAmp.value = size * 0.25 * boil;
    mat.resolution.set(gl.width, gl.height);
    mat.linewidth = BASE_WIDTH_PX * inkWidth * (gl.height / 1080);
  });

  return <primitive object={line} />;
}
