import { TransformControls } from '@react-three/drei';
import { Canvas, type ThreeEvent } from '@react-three/fiber';
import { Suspense, useEffect, useMemo, useRef, useState } from 'react';
import * as THREE from 'three';
import { ACTOR_TYPES } from '../actors';
import { CinematicFX } from './CinematicFX';
import { CameraRigs } from '../engine/CameraRigs';
import { MicroVoxelWorld } from '../engine/MicroVoxelWorld';
import { ProceduralEnv } from '../engine/ProceduralEnv';
import { runtime } from '../engine/runtime';
import { ScenePortal } from '../engine/ScenePortal';
import { VoxelModelMesh, type VoxelHit } from '../engine/VoxelModelMesh';
import { vkey } from '../engine/voxels';
import { WaterSystem } from '../engine/WaterSystem';
import { useStudioStore } from '../store/useStudioStore';
import type { Episode, SceneObject, Voxel } from '../types';

const D2R = Math.PI / 180;

function PropObject({ obj, studio }: { obj: SceneObject; studio: boolean }) {
  const model = useStudioStore((s) => s.library[obj.ref]);
  const ref = useRef<THREE.Group>(null);

  useEffect(() => {
    const g = ref.current!;
    runtime.objects.set(obj.id, g);
    return () => {
      if (runtime.objects.get(obj.id) === g) runtime.objects.delete(obj.id);
    };
  }, [obj.id]);

  if (!model) return null;

  const onVoxelClick = ({ voxel, normal }: VoxelHit, e: ThreeEvent<MouseEvent>) => {
    const st = useStudioStore.getState();
    if (!studio) return;
    e.stopPropagation();
    if (st.brush === 'off') {
      st.set({ selectedId: obj.id });
      return;
    }
    // In-world voxel editing of the asset itself (affects every placed copy).
    const key = vkey(voxel.x, voxel.y, voxel.z);
    let voxels: Voxel[];
    const fresh: Voxel = { x: voxel.x, y: voxel.y, z: voxel.z, c: st.brushColor, ...(st.brushGlow ? { e: true } : {}) };
    if (st.brush === 'paint') voxels = model.voxels.map((v) => (vkey(v.x, v.y, v.z) === key ? fresh : v));
    else if (st.brush === 'erase') voxels = model.voxels.filter((v) => vkey(v.x, v.y, v.z) !== key);
    else {
      const n = { ...fresh, x: voxel.x + Math.round(normal.x), y: voxel.y + Math.round(normal.y), z: voxel.z + Math.round(normal.z) };
      voxels = [...model.voxels.filter((v) => vkey(v.x, v.y, v.z) !== vkey(n.x, n.y, n.z)), n];
    }
    st.setModel({ ...model, voxels });
  };

  return (
    <group
      ref={ref}
      name={`prop:${obj.id}`}
      position={obj.pos}
      rotation={[obj.rot[0] * D2R, obj.rot[1] * D2R, obj.rot[2] * D2R]}
      scale={obj.scale}
      visible={obj.visible}
    >
      <VoxelModelMesh voxels={model.voxels} onVoxelClick={studio ? onVoxelClick : undefined} />
      {Object.entries(model.sockets ?? {}).map(([name, p]) => (
        <object3D key={name} name={`socket:${name}`} position={[p[0] * 0.1, p[1] * 0.1, p[2] * 0.1]} />
      ))}
    </group>
  );
}

function SelectionGizmo() {
  const selectedId = useStudioStore((s) => s.selectedId);
  const brush = useStudioStore((s) => s.brush);
  const objects = useStudioStore((s) => s.scene.objects);
  const [target, setTarget] = useState<THREE.Object3D | null>(null);
  const [mode, setMode] = useState<'translate' | 'rotate'>('translate');

  useEffect(() => {
    setTarget(selectedId ? (runtime.objects.get(selectedId) ?? null) : null);
  }, [selectedId, objects]);

  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      if (e.key === 'v') setMode('translate');
      if (e.key === 'b') setMode('rotate');
    };
    const onGizmo = (e: Event) => setMode((e as CustomEvent<'translate' | 'rotate'>).detail);
    window.addEventListener('keydown', onKey);
    window.addEventListener('robo:gizmo', onGizmo);
    return () => {
      window.removeEventListener('keydown', onKey);
      window.removeEventListener('robo:gizmo', onGizmo);
    };
  }, []);

  if (!target || !selectedId || brush !== 'off') return null;
  return (
    <TransformControls
      object={target}
      mode={mode}
      size={0.8}
      translationSnap={0.1}
      rotationSnap={Math.PI / 12}
      showX={mode === 'translate'}
      showZ={mode === 'translate'}
      onMouseUp={() => {
        const o = target;
        useStudioStore.getState().updateObject(selectedId, {
          pos: [+o.position.x.toFixed(2), +o.position.y.toFixed(2), +o.position.z.toFixed(2)],
          rot: [+(o.rotation.x / D2R).toFixed(1), +(o.rotation.y / D2R).toFixed(1), +(o.rotation.z / D2R).toFixed(1)],
        });
      }}
    />
  );
}

export function Stage({ episode, dpr }: { episode: Episode; dpr: number }) {
  const objects = useStudioStore((s) => s.scene.objects);
  const mode = useStudioStore((s) => s.mode);
  const brush = useStudioStore((s) => s.brush);
  const selectedId = useStudioStore((s) => s.selectedId);
  const cinematic = useStudioStore((s) => s.cinematic);
  const drawn = useStudioStore((s) => s.drawn);
  const studio = mode === 'studio';
  const base = useMemo(() => episode.buildBaseVoxels?.(), [episode]);
  const c = episode.cameras.static;

  return (
    <Canvas
      shadows
      dpr={dpr}
      gl={{ preserveDrawingBuffer: true, antialias: false, powerPreference: 'high-performance' }}
      camera={{ fov: c.fov, position: c.pos, near: 0.05, far: 200 }}
      onCreated={({ gl, scene, camera }) => {
        runtime.three = { gl, scene, camera };
        runtime.canvas = gl.domElement;
      }}
      onPointerMissed={() => studio && brush === 'off' && useStudioStore.getState().set({ selectedId: null })}
    >
      <color attach="background" args={[episode.skyColor]} />
      <fog attach="fog" args={[episode.skyColor, 14, 40]} />
      <ProceduralEnv />
      <hemisphereLight args={['#dff1ff', '#8a6d4a', 0.9]} />
      <directionalLight
        position={[4, 8, 6]}
        intensity={2.1}
        castShadow
        shadow-mapSize={[1024, 1024]}
        shadow-camera-left={-5}
        shadow-camera-right={5}
        shadow-camera-top={5}
        shadow-camera-bottom={-5}
        shadow-bias={-0.0005}
      />

      {base && <MicroVoxelWorld base={base} editable={studio && brush !== 'off'} />}
      <Suspense fallback={null}>
      {objects.map((o) => {
        if (o.kind === 'actor') {
          const Actor = ACTOR_TYPES[o.ref as keyof typeof ACTOR_TYPES] ?? ACTOR_TYPES.robo;
          return (
            <Actor
              key={o.id}
              obj={o}
              episode={episode}
              perform={!(studio && selectedId === o.id)}
              onSelect={
                studio
                  ? (e) => {
                      e.stopPropagation();
                      useStudioStore.getState().set({ selectedId: o.id, activeActorId: o.id });
                    }
                  : undefined
              }
            />
          );
        }
        return <PropObject key={o.id} obj={o} studio={studio} />;
      })}
      </Suspense>

      <WaterSystem episode={episode} perform={!studio || !selectedId} />
      {(episode.portals ?? []).map((p) => (
        <ScenePortal key={p.to} to={p.to} position={p.position} rotationY={p.rotationY ?? 0} active />
      ))}
      <CameraRigs config={episode.cameras} />
      {studio && <SelectionGizmo />}
      {(cinematic || drawn) && <CinematicFX nature={false} cinematic={cinematic} drawn={drawn} />}
    </Canvas>
  );
}
