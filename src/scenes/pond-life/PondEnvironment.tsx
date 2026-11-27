import { useGLTF } from '@react-three/drei';
import { useFrame } from '@react-three/fiber';
import { useMemo } from 'react';
import * as THREE from 'three';

const URL_POND = `${import.meta.env.BASE_URL}models/pond.glb`;

/**
 * The Blender-sculpted habitat. Grass/reeds sway with a vertex-shader wind (uv.y = blade height),
 * so 16k blades cost one draw call and zero CPU per frame.
 */
export function PondEnvironment() {
  const { scene } = useGLTF(URL_POND);
  const wind = useMemo(() => ({ value: 0 }), []);

  const root = useMemo(() => {
    const s = scene.clone(true);
    s.traverse((o) => {
      const m = o as THREE.Mesh;
      if (!m.isMesh) return;
      const grass = m.name.startsWith('Grass');
      m.castShadow = !grass && !m.name.startsWith('LilyPads') && !m.name.startsWith('Terrain');
      m.receiveShadow = true;
      const mat = (m.material as THREE.MeshStandardMaterial).clone();
      mat.vertexColors = !!m.geometry.attributes.color;
      mat.metalness = 0;
      if (grass) {
        mat.side = THREE.DoubleSide;
        mat.onBeforeCompile = (shader) => {
          shader.uniforms.uWind = wind;
          shader.vertexShader = shader.vertexShader
            .replace('#include <common>', '#include <common>\nuniform float uWind;')
            .replace(
              '#include <begin_vertex>',
              `#include <begin_vertex>
              float bend = uv.y * uv.y;
              vec4 wp = modelMatrix * vec4(position, 1.0);
              float gust = sin(uWind * 1.3 + wp.x * 0.7 + wp.z * 0.4) * 0.5 + 0.5;
              transformed.x += (sin(uWind * 2.1 + wp.x * 3.0 + wp.z * 1.7) * 0.035 + gust * 0.05) * bend;
              transformed.y += cos(uWind * 1.7 + wp.z * 2.3) * 0.02 * bend;`,
            );
        };
      }
      m.material = mat;
    });
    return s;
  }, [scene, wind]);

  useFrame((_, dt) => {
    wind.value += dt;
  });

  return <primitive object={root} />;
}

useGLTF.preload(URL_POND);
