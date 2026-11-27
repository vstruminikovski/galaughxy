import { useEffect, useState } from 'react';
import { currentPose } from '../engine/freeCam';
import { cancelRender, downloadBlob, FPS_OPTIONS, loadShots, renderTake, RESOLUTIONS, saveShots, type RenderProgress, type Shot } from '../engine/TakeRenderer';
import { useStudioStore } from '../store/useStudioStore';
import type { CamRig } from '../types';

const uid = () => `shot_${Math.random().toString(36).slice(2, 8)}`;

/** Render Take: pick output size + frame rate, arrange shots, render a sharp MP4 at that size. */
export function RenderDrawer() {
  const slug = useStudioStore((s) => s.episodeSlug);
  const rendering = useStudioStore((s) => s.rendering);
  const [resId, setResId] = useState<string>(RESOLUTIONS[0].id);
  const [fps, setFps] = useState<number>(24);
  const [shots, setShots] = useState<Shot[]>([]);
  const [progress, setProgress] = useState<RenderProgress | null>(null);
  const [msg, setMsg] = useState('');
  const [busy, setBusy] = useState(false);
  const res = RESOLUTIONS.find((r) => r.id === resId)!;
  const total = shots.reduce((n, s) => n + s.seconds, 0);

  useEffect(() => setShots(loadShots(slug)), [slug]);
  const update = (next: Shot[]) => {
    setShots(next);
    saveShots(slug, next);
  };

  const addPoseShot = () => {
    const n = shots.length + 1;
    update([...shots, { id: uid(), name: `Shot ${n}`, seconds: 4, mode: 'pose', pose: currentPose() }]);
  };
  const addRigShot = (rig: CamRig) => {
    const n = shots.length + 1;
    update([...shots, { id: uid(), name: `${rig[0].toUpperCase() + rig.slice(1)} ${n}`, seconds: 6, mode: 'rig', rig }]);
  };
  const patch = (id: string, p: Partial<Shot>) => update(shots.map((s) => (s.id === id ? { ...s, ...p } : s)));
  const move = (i: number, d: number) => {
    const j = i + d;
    if (j < 0 || j >= shots.length) return;
    const n = [...shots];
    [n[i], n[j]] = [n[j], n[i]];
    update(n);
  };

  const render = async () => {
    setBusy(true);
    setMsg('');
    try {
      const blob = await renderTake({ w: res.w, h: res.h, fps, shots, onProgress: setProgress });
      downloadBlob(blob, `${slug}_${res.w}x${res.h}_${fps}fps.mp4`);
      setMsg(`Rendered ${res.w}×${res.h} at ${fps} fps (${(blob.size / 1e6).toFixed(1)} MB).`);
    } catch (e) {
      setMsg((e as Error).message);
    } finally {
      setBusy(false);
      setProgress(null);
    }
  };

  return (
    <>
      <p className="hint">Renders from the 3D scene at the size you pick. Not a screen recording, so the output is sharp at full resolution.</p>
      <h4>Output size</h4>
      <div className="chips">
        {RESOLUTIONS.map((r) => (
          <button key={r.id} className={resId === r.id ? 'on' : ''} onClick={() => setResId(r.id)} disabled={busy}>
            {r.label}
          </button>
        ))}
      </div>
      <h4>Frame rate</h4>
      <div className="seg">
        {FPS_OPTIONS.map((f) => (
          <button key={f} className={fps === f ? 'on' : ''} onClick={() => setFps(f)} disabled={busy}>
            {f} fps{f === 12 ? ' (on twos)' : ''}
          </button>
        ))}
      </div>
      <h4>Shots · {total.toFixed(1)} s total</h4>
      <div className="row">
        <button onClick={addPoseShot} disabled={busy}>+ Shot from this camera</button>
        <button onClick={() => addRigShot('slider')} disabled={busy}>+ Slider</button>
        <button onClick={() => addRigShot('drone')} disabled={busy}>+ Drone</button>
      </div>
      <ul className="outliner">
        {shots.map((s, i) => (
          <li key={s.id} className="shot">
            <input value={s.name} onChange={(e) => patch(s.id, { name: e.target.value })} disabled={busy} />
            <input type="number" min={0.5} max={60} step={0.5} value={s.seconds} onChange={(e) => patch(s.id, { seconds: Math.max(0.5, +e.target.value) })} disabled={busy} style={{ width: 56 }} />
            <span className="hint">s</span>
            <button onClick={() => move(i, -1)} disabled={busy}>↑</button>
            <button onClick={() => move(i, 1)} disabled={busy}>↓</button>
            <button onClick={() => update(shots.filter((x) => x.id !== s.id))} disabled={busy}>🗑</button>
            <span className="hint">{s.mode === 'pose' ? 'frozen camera' : `moving ${s.rig}`}</span>
          </li>
        ))}
      </ul>
      {shots.length === 0 && <p className="hint">Frame a shot with the camera, then tap “+ Shot from this camera”.</p>}
      <h4>Render</h4>
      {busy ? (
        <>
          <div className="bar">
            <div style={{ width: `${progress ? (100 * progress.frame) / progress.total : 0}%` }} />
          </div>
          <p className="hint">
            {progress ? `${progress.shotName} · frame ${progress.frame}/${progress.total}` : 'Preparing…'}
          </p>
          <button onClick={cancelRender}>■ Cancel</button>
        </>
      ) : (
        <button className="rec-big" onClick={render} disabled={!shots.length || rendering}>
          🎬 Render {res.w}×{res.h} · {fps} fps · {total.toFixed(1)} s
        </button>
      )}
      {msg && <p className={msg.startsWith('Rendered') ? 'ok' : 'err'}>{msg}</p>}
    </>
  );
}
