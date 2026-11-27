import { useEffect, useRef, useState, type ReactNode } from 'react';
import { advanceChaos, cutToDrone, resetTake, setWaterStage } from '../engine/ChaosDirector';
import { dualRecorder } from '../engine/DualRecorder';
import { downloadJSON, exportPNG, saveToDisk } from '../engine/FrameExport';
import { runtime } from '../engine/runtime';
import { SFX_PADS, VOICE_PRESETS, voiceFX } from '../engine/VoiceFXEngine';
import { LOCAL_LIBRARY_KEY } from '../props/library';
import { useStudioStore, type BrushMode } from '../store/useStudioStore';
import { RenderDrawer } from './RenderDrawer';
import { sceneKey } from '../scenes/loadEpisode';
import { applyPose, loadViews, saveView, toggleFly } from '../engine/freeCam';
import type { Drawer, SceneDoc, VoxelModel } from '../types';

const DRAWERS: { id: Drawer; icon: string; label: string }[] = [
  { id: 'models', icon: '🧊', label: 'Models' },
  { id: 'scene', icon: '🌊', label: 'Scene & Chaos' },
  { id: 'voice', icon: '🎙', label: 'Voice & Lip-Sync' },
  { id: 'cameras', icon: '🎥', label: 'Cameras' },
  { id: 'timing', icon: '⏱', label: 'Movement & Timing' },
  { id: 'render', icon: '🎬', label: 'Render take' },
  { id: 'export', icon: '💾', label: 'Export' },
];

const PALETTE = ['#ff4f6d', '#ffcc33', '#3dff7a', '#38e8ff', '#4aa3df', '#9b6bff', '#f4f6f8', '#2c3442', '#b97a46', '#5fa8a0'];


function Row({ children }: { children: ReactNode }) {
  return <div className="row">{children}</div>;
}
function Seg<T extends string>({ value, options, onChange }: { value: T; options: { id: T; label: string }[]; onChange: (v: T) => void }) {
  return (
    <div className="seg">
      {options.map((o) => (
        <button key={o.id} className={value === o.id ? 'on' : ''} onClick={() => onChange(o.id)}>
          {o.label}
        </button>
      ))}
    </div>
  );
}

function ModelsDrawer() {
  const s = useStudioStore();
  const selected = s.scene.objects.find((o) => o.id === s.selectedId);
  const model = selected?.kind === 'prop' ? s.library[selected.ref] : undefined;
  const [assetName, setAssetName] = useState('');
  const [msg, setMsg] = useState('');

  const saveAsset = async () => {
    if (!model) return;
    const name = (assetName || `${model.name}-v2`).toLowerCase().replace(/[^a-z0-9-]+/g, '-');
    const asset: VoxelModel = { ...model, name };
    s.setModel(asset);
    s.updateObject(selected!.id, { ref: name, name });
    try {
      const all = JSON.parse(localStorage.getItem(LOCAL_LIBRARY_KEY) || '{}');
      all[name] = asset;
      localStorage.setItem(LOCAL_LIBRARY_KEY, JSON.stringify(all));
    } catch {
      /* storage blocked */
    }
    const disk = await saveToDisk('/api/save-prop', { name, recipe: asset });
    setMsg(disk ? `Saved ${name} (device + src/props/library)` : `Saved ${name} on device`);
  };

  return (
    <>
      <p className="hint">Pick a brush, then tap cubes on the room or any prop. Brush off = tap to select.</p>
      <Seg<BrushMode>
        value={s.brush}
        onChange={(b) => s.set({ brush: b })}
        options={[
          { id: 'off', label: 'Select' },
          { id: 'paint', label: 'Paint' },
          { id: 'add', label: 'Add' },
          { id: 'erase', label: 'Erase' },
        ]}
      />
      <div className="swatches">
        {PALETTE.map((c) => (
          <button key={c} className={`sw ${s.brushColor === c ? 'on' : ''}`} style={{ background: c }} onClick={() => s.set({ brushColor: c })} />
        ))}
        <input type="color" value={s.brushColor} onChange={(e) => s.set({ brushColor: e.target.value })} />
      </div>
      <Row>
        <label className="check">
          <input type="checkbox" checked={s.brushGlow} onChange={(e) => s.set({ brushGlow: e.target.checked })} /> Emissive glow
        </label>
        <button onClick={s.undo} disabled={!s.past.length}>↶ Undo</button>
        <button onClick={s.redo} disabled={!s.future.length}>↷</button>
      </Row>
      <h4>Stamp a prop</h4>
      <div className="chips">
        {Object.keys(s.library).map((name) => (
          <button
            key={name}
            onClick={() =>
              s.addObject({ kind: 'prop', ref: name, name, pos: [0, 0, 1.2], rot: [0, 0, 0], scale: [1, 1, 1], visible: true })
            }
          >
            + {name}
          </button>
        ))}
      </div>
      {model && (
        <>
          <h4>Asset: {model.name}</h4>
          <Row>
            <input placeholder={`${model.name}-v2`} value={assetName} onChange={(e) => setAssetName(e.target.value)} />
            <button onClick={saveAsset}>Save asset</button>
            <button onClick={() => downloadJSON(model.name, model)}>⤓ JSON</button>
          </Row>
          <Row>
            <label className="check">
              <input type="checkbox" checked={!!model.floats} onChange={(e) => s.setModel({ ...model, floats: e.target.checked })} /> Floats on water
            </label>
            <span className="hint">{model.voxels.length} voxels</span>
          </Row>
        </>
      )}
      {msg && <p className="ok">{msg}</p>}
    </>
  );
}

function SceneDrawer() {
  const s = useStudioStore();
  const [msg, setMsg] = useState('');
  const fileRef = useRef<HTMLInputElement>(null);
  const sel = s.scene.objects.find((o) => o.id === s.selectedId);

  const nudge = (dx: number, dz: number, dr = 0) =>
    sel && s.updateObject(sel.id, { pos: [+(sel.pos[0] + dx).toFixed(2), sel.pos[1], +(sel.pos[2] + dz).toFixed(2)], rot: [sel.rot[0], sel.rot[1] + dr, sel.rot[2]] });

  const save = async () => {
    try {
      localStorage.setItem(sceneKey(s.scene.slug), JSON.stringify(s.scene));
    } catch {
      /* storage blocked */
    }
    const disk = await saveToDisk('/api/save-scene', { slug: s.scene.slug, scene: s.scene });
    setMsg(disk ? 'Saved to device + scene.json' : 'Saved on device');
  };

  return (
    <>
      <h4>Water overflow</h4>
      <div className="seg">
        {(['Trickle', 'Surge', 'Flood'] as const).map((l, i) => (
          <button key={l} className={s.waterStage === i + 1 ? 'on' : ''} onClick={() => setWaterStage((i + 1) as 1 | 2 | 3)}>
            {i + 1}. {l}
          </button>
        ))}
        <button onClick={() => setWaterStage(0)}>Drain</button>
      </div>
      <Row>
        <button onClick={advanceChaos}>Next stage (G)</button>
        <button onClick={cutToDrone} className={s.waterStage === 3 ? 'pulse' : ''}>Cut to Drone</button>
        <button onClick={resetTake}>Reset take</button>
      </Row>
      <h4>Objects</h4>
      <ul className="outliner">
        {s.scene.objects.map((o) => (
          <li key={o.id} className={o.id === s.selectedId ? 'on' : ''}>
            <button className="name" onClick={() => s.set({ selectedId: o.id, brush: 'off' })}>
              {o.kind === 'actor' ? '🤖' : '▪'} {o.name}
            </button>
            <button onClick={() => s.updateObject(o.id, { visible: !o.visible })}>{o.visible ? '👁' : '🚫'}</button>
            {o.kind === 'prop' && <button onClick={() => s.duplicateObject(o.id)}>⧉</button>}
            {o.kind === 'prop' && <button onClick={() => s.removeObject(o.id)}>🗑</button>}
          </li>
        ))}
      </ul>
      {sel && (
        <div className="nudge">
          <span>{sel.name}</span>
          <button onClick={() => nudge(-0.1, 0)}>←</button>
          <button onClick={() => nudge(0, -0.1)}>↑</button>
          <button onClick={() => nudge(0, 0.1)}>↓</button>
          <button onClick={() => nudge(0.1, 0)}>→</button>
          <button onClick={() => nudge(0, 0, 15)}>⟳15°</button>
          <button onClick={() => window.dispatchEvent(new CustomEvent('robo:gizmo', { detail: 'translate' }))}>Move</button>
          <button onClick={() => window.dispatchEvent(new CustomEvent('robo:gizmo', { detail: 'rotate' }))}>Rotate</button>
        </div>
      )}
      <h4>Scene file</h4>
      <Row>
        <button onClick={save}>💾 Save scene</button>
        <button onClick={() => downloadJSON(s.scene.slug, s.scene)}>⤓ JSON</button>
        <button onClick={() => fileRef.current?.click()}>⤒ Import</button>
        <input
          ref={fileRef}
          type="file"
          accept="application/json"
          hidden
          onChange={async (e) => {
            const f = e.target.files?.[0];
            if (!f) return;
            const doc = JSON.parse(await f.text()) as SceneDoc;
            if (doc.objects && doc.voxels) s.loadScene({ ...doc, slug: s.scene.slug });
          }}
        />
      </Row>
      {msg && <p className="ok">{msg}</p>}
    </>
  );
}

function VoiceDrawer() {
  const s = useStudioStore();
  const voRef = useRef<HTMLInputElement>(null);
  const musicRef = useRef<HTMLInputElement>(null);
  const [voName, setVoName] = useState(voiceFX.voName);
  const [err, setErr] = useState('');
  return (
    <>
      <h4>Voice preset</h4>
      <div className="chips">
        {VOICE_PRESETS.map((p) => (
          <button key={p.id} className={s.voicePreset === p.id ? 'on' : ''} onClick={() => { void voiceFX.ensure(); s.set({ voicePreset: p.id }); }}>
            {p.label}
          </button>
        ))}
      </div>
      <Row>
        <button
          className={s.micOn ? 'on' : ''}
          onClick={async () => {
            try {
              s.set({ micOn: await voiceFX.toggleMic() });
              setErr('');
            } catch (e) {
              setErr(`Mic unavailable: ${(e as Error).message}. Needs HTTPS or localhost.`);
            }
          }}
        >
          🎙 Mic {s.micOn ? 'on' : 'off'}
        </button>
        <label className="check">
          <input type="checkbox" checked={s.monitor} onChange={(e) => s.set({ monitor: e.target.checked })} /> Monitor (headphones)
        </label>
      </Row>
      {err && <p className="err">{err}</p>}
      <Row>
        <button onClick={() => voRef.current?.click()}>Load voiceover</button>
        <button disabled={!voName} onClick={() => voiceFX.playVoiceover()}>▶ {voName || 'none'}</button>
        <button onClick={() => voiceFX.stopVoiceover()}>■</button>
        <input ref={voRef} type="file" accept="audio/*" hidden onChange={async (e) => {
          const f = e.target.files?.[0];
          if (f) { await voiceFX.loadVoiceover(f); setVoName(f.name); }
        }} />
      </Row>
      <h4>Music</h4>
      <Row>
        <button className={s.musicPlaying ? 'on' : ''} onClick={() => (s.musicPlaying ? voiceFX.stopMusic() : voiceFX.playMusic())}>
          {s.musicPlaying ? '❚❚' : '▶'} {s.musicName}
        </button>
      </Row>
      <Row>
        <label className="check"><input type="checkbox" checked={s.musicLoop} onChange={(e) => { s.set({ musicLoop: e.target.checked }); voiceFX.setMusicLoop(e.target.checked); }} /> Loop</label>
        <label className="check"><input type="checkbox" checked={s.ducking} onChange={(e) => s.set({ ducking: e.target.checked })} /> Auto-duck</label>
        <input type="range" min={0} max={1} step={0.01} defaultValue={0.55} onChange={(e) => voiceFX.setMusicVolume(+e.target.value)} />
        <button onClick={() => musicRef.current?.click()}>Load track</button>
        <input ref={musicRef} type="file" accept="audio/*" hidden onChange={(e) => e.target.files?.[0] && voiceFX.loadMusic(e.target.files[0])} />
      </Row>
      <h4>SFX pads</h4>
      <div className="pads">
        {SFX_PADS.map((p) => (
          <button key={p.id} onPointerDown={() => voiceFX.sfx(p.id)}>
            {p.label}
            <kbd>{p.key}</kbd>
          </button>
        ))}
      </div>
    </>
  );
}

function CamerasDrawer() {
  const s = useStudioStore();
  const [views, setViews] = useState(() => loadViews(s.episodeSlug));
  useEffect(() => setViews(loadViews(s.episodeSlug)), [s.episodeSlug]);
  const sliderRef = useRef<HTMLInputElement>(null);
  // Mirror runtime.sliderT into the range input without React re-renders.
  useEffect(() => {
    let raf = 0;
    const loop = () => {
      if (sliderRef.current && document.activeElement !== sliderRef.current) sliderRef.current.value = String(runtime.sliderT * 100);
      raf = requestAnimationFrame(loop);
    };
    loop();
    return () => cancelAnimationFrame(raf);
  }, []);
  return (
    <>
      <Seg
        value={s.camRig}
        onChange={(r) => s.set({ camRig: r })}
        options={[
          { id: 'static', label: 'Static Z' },
          { id: 'slider', label: 'Slider X' },
          { id: 'drone', label: 'Drone C' },
        ]}
      />
      <Row>
        <label className="check"><input type="checkbox" checked={s.punchIn} onChange={(e) => s.set({ punchIn: e.target.checked, camRig: 'static' })} /> Punch-in</label>
        <button onClick={() => (runtime.look.yaw = runtime.look.pitch = 0)}>Recentre look</button>
      </Row>
      <h4>Slider dolly</h4>
      <input ref={sliderRef} type="range" min={0} max={100} step={0.1} defaultValue={0} onInput={(e) => { runtime.sliderT = +e.currentTarget.value / 100; s.set({ camRig: 'slider', autoGlide: false }); }} />
      <Row>
        <button className={s.autoGlide ? 'on' : ''} onClick={() => { if (runtime.sliderT >= 1) runtime.sliderT = 0; s.set({ autoGlide: !s.autoGlide, camRig: 'slider' }); }}>
          Auto-glide
        </button>
        <span className="hint">speed</span>
        <input type="range" min={0.02} max={0.4} step={0.01} value={s.glideSpeed} onChange={(e) => s.set({ glideSpeed: +e.target.value })} />
      </Row>
      <h4>Free camera</h4>
      <Row>
        <button className={s.camRig === 'free' ? 'on' : ''} onClick={toggleFly}>🛸 Fly (N)</button>
        <span className="hint">WASD move · Space up · Shift down · drag to look</span>
      </Row>
      <h4>Saved views (this scene)</h4>
      <Row>
        {[0, 1, 2].map((i) => (
          <button key={`s${i}`} onClick={() => setViews(saveView(s.episodeSlug, i))}>Save {i + 1}</button>
        ))}
      </Row>
      <Row>
        {[0, 1, 2].map((i) => (
          <button key={`g${i}`} disabled={!views[i]} onClick={() => views[i] && applyPose(views[i]!)}>Go {i + 1}</button>
        ))}
      </Row>
      <h4>Framing (38° lens)</h4>
      <Seg value={s.aspect} onChange={(a) => s.set({ aspect: a })} options={[{ id: '16:9', label: '16:9' }, { id: '9:16', label: '9:16' }, { id: 'dual', label: 'Dual' }]} />
      <label className="check"><input type="checkbox" checked={s.autoTrack} onChange={(e) => s.set({ autoTrack: e.target.checked })} /> 9:16 auto-track speaker</label>
    </>
  );
}

function TimingDrawer() {
  const s = useStudioStore();
  return (
    <>
      <Seg value={s.onTwos ? 'twos' : 'smooth'} onChange={(v) => s.set({ onTwos: v === 'twos' })} options={[{ id: 'twos', label: '12fps On Twos' }, { id: 'smooth', label: '60fps Smooth' }]} />
      <p className="hint">On Twos holds character poses for 2 frames; cameras, water and particles stay smooth.</p>
      <h4>Turn snappiness</h4>
      <input type="range" min={30} max={400} step={5} value={s.snappiness} onChange={(e) => s.set({ snappiness: +e.target.value })} />
      <h4>Turn overshoot</h4>
      <input type="range" min={0} max={1} step={0.05} value={s.overshoot} onChange={(e) => s.set({ overshoot: +e.target.value })} />
      <h4>Look</h4>
      <label className="check"><input type="checkbox" checked={s.drawn} onChange={(e) => s.set({ drawn: e.target.checked })} /> ✏️ Grease-pencil drawn look</label>
      <span className="hint">Ink</span>
      <input type="range" min={0} max={1.5} step={0.05} value={s.drawnInk} onChange={(e) => s.set({ drawnInk: +e.target.value })} />
      <label className="check"><input type="checkbox" checked={s.drawnBlocks} onChange={(e) => s.set({ drawnBlocks: e.target.checked })} /> Show block edges (always on while painting)</label>
      <span className="hint">Line boil (wobble per drawn frame)</span>
      <input type="range" min={0} max={3} step={0.1} value={s.drawnBoil} onChange={(e) => s.set({ drawnBoil: +e.target.value })} />
      <h4>Mode</h4>
      <Seg value={s.mode} onChange={(m) => s.set({ mode: m, selectedId: null, brush: 'off' })} options={[{ id: 'game', label: 'Game' }, { id: 'studio', label: 'Studio / Puppet' }]} />
    </>
  );
}

function ExportDrawer() {
  const s = useStudioStore();
  return (
    <>
      <h4>PNG frame (HUD-free)</h4>
      <Row>
        {[1, 2, 4].map((k) => (
          <button key={k} onClick={() => exportPNG(k)}>{k}× PNG</button>
        ))}
      </Row>
      <h4>Video ({s.aspect === 'dual' ? '16:9 with 9:16 crop guide' : s.aspect})</h4>
      <Row>
        <button className={`rec ${s.recording ? 'on' : ''}`} onClick={() => dualRecorder.toggle()}>
          {s.recording ? '■ Stop & save' : '● Record take'}
        </button>
      </Row>
      <p className="hint">Records only the 3D canvas plus voice FX, music and SFX. MP4 where the browser supports it, otherwise WebM.</p>
    </>
  );
}

export function StudioDrawers() {
  const drawer = useStudioStore((s) => s.drawer);
  const set = useStudioStore((s) => s.set);
  const body = {
    models: <ModelsDrawer />,
    scene: <SceneDrawer />,
    voice: <VoiceDrawer />,
    cameras: <CamerasDrawer />,
    timing: <TimingDrawer />,
    export: <ExportDrawer />,
    render: <RenderDrawer />,
  };
  return (
    <div className="drawers" onPointerDown={(e) => e.stopPropagation()}>
      <div className="rail">
        {DRAWERS.map((d) => (
          <button key={d.id} className={drawer === d.id ? 'on' : ''} title={d.label} onClick={() => set({ drawer: drawer === d.id ? null : d.id })}>
            {d.icon}
          </button>
        ))}
      </div>
      {drawer && (
        <div className="panel">
          <div className="panel-head">
            <b>{DRAWERS.find((d) => d.id === drawer)!.label}</b>
            <button onClick={() => set({ drawer: null })}>✕</button>
          </div>
          <div className="panel-body">{body[drawer]}</div>
        </div>
      )}
    </div>
  );
}
