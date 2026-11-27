import { useRef, useState, type PointerEvent as RPE } from 'react';
import { hop } from '../actors/RoboActor';
import { LED_FACES } from '../actors/ledFaces';
import { advanceChaos } from '../engine/ChaosDirector';
import { runtime } from '../engine/runtime';
import { voiceFX } from '../engine/VoiceFXEngine';
import { useStudioStore } from '../store/useStudioStore';
import { EXPRESSIONS, type Expression } from '../types';

const STICK_R = 56;

/** Left thumb zone: floating analog joystick that spawns where the thumb lands. */
function JoystickZone() {
  const [base, setBase] = useState<{ x: number; y: number } | null>(null);
  const [knob, setKnob] = useState({ x: 0, y: 0 });
  const pid = useRef<number | null>(null);

  const down = (e: RPE) => {
    if (pid.current !== null) return;
    void voiceFX.ensure();
    pid.current = e.pointerId;
    (e.target as HTMLElement).setPointerCapture(e.pointerId);
    setBase({ x: e.clientX, y: e.clientY });
    setKnob({ x: 0, y: 0 });
  };
  const move = (e: RPE) => {
    if (e.pointerId !== pid.current || !base) return;
    let dx = e.clientX - base.x;
    let dy = e.clientY - base.y;
    const len = Math.hypot(dx, dy);
    if (len > STICK_R) {
      dx = (dx / len) * STICK_R;
      dy = (dy / len) * STICK_R;
    }
    setKnob({ x: dx, y: dy });
    runtime.stick.x = dx / STICK_R;
    runtime.stick.z = dy / STICK_R;
  };
  const up = (e: RPE) => {
    if (e.pointerId !== pid.current) return;
    pid.current = null;
    setBase(null);
    runtime.stick.x = runtime.stick.z = 0;
  };

  return (
    <div className="zone zone-left" onPointerDown={down} onPointerMove={move} onPointerUp={up} onPointerCancel={up}>
      {base ? (
        <div className="stick-base" style={{ left: base.x, top: base.y }}>
          <div className="stick-knob" style={{ transform: `translate(${knob.x}px, ${knob.y}px)` }} />
        </div>
      ) : (
        <div className="stick-hint">MOVE</div>
      )}
    </div>
  );
}

/** Right zone background: drag to orbit the camera rig, double-tap to recentre. */
function LookZone() {
  const last = useRef<{ id: number; x: number; y: number } | null>(null);
  const lastTap = useRef(0);
  const down = (e: RPE) => {
    if (last.current) return;
    (e.target as HTMLElement).setPointerCapture(e.pointerId);
    last.current = { id: e.pointerId, x: e.clientX, y: e.clientY };
    const now = performance.now();
    if (now - lastTap.current < 280) runtime.look.yaw = runtime.look.pitch = 0;
    lastTap.current = now;
  };
  const move = (e: RPE) => {
    const l = last.current;
    if (!l || l.id !== e.pointerId) return;
    runtime.look.yaw = Math.max(-0.9, Math.min(0.9, runtime.look.yaw - (e.clientX - l.x) * 0.005));
    runtime.look.pitch = Math.max(-0.35, Math.min(0.35, runtime.look.pitch - (e.clientY - l.y) * 0.004));
    l.x = e.clientX;
    l.y = e.clientY;
  };
  const up = (e: RPE) => {
    if (last.current?.id === e.pointerId) last.current = null;
  };
  return <div className="zone zone-right" onPointerDown={down} onPointerMove={move} onPointerUp={up} onPointerCancel={up} />;
}

/** Hold the Face button and drag toward a sector; release to apply. Quick tap = next face. */
function FaceButton() {
  const [wheel, setWheel] = useState<{ x: number; y: number; sel: number } | null>(null);
  const start = useRef(0);
  const expr = useStudioStore((s) => (s.activeActorId ? s.expressions[s.activeActorId] : undefined) ?? 'DEADPAN');

  const sectorAt = (x: number, y: number, cx: number, cy: number) => {
    const dx = x - cx;
    const dy = y - cy;
    if (Math.hypot(dx, dy) < 28) return -1;
    const a = (Math.atan2(dy, dx) + Math.PI * 2.5) % (Math.PI * 2); // 0 = up
    return Math.floor((a / (Math.PI * 2)) * 6 + 0.5) % 6;
  };
  const down = (e: RPE) => {
    e.stopPropagation();
    (e.target as HTMLElement).setPointerCapture(e.pointerId);
    const r = (e.currentTarget as HTMLElement).getBoundingClientRect();
    start.current = performance.now();
    setWheel({ x: r.left + r.width / 2, y: r.top + r.height / 2 - 110, sel: -1 });
  };
  const move = (e: RPE) => {
    if (!wheel) return;
    setWheel({ ...wheel, sel: sectorAt(e.clientX, e.clientY, wheel.x, wheel.y) });
  };
  const up = () => {
    const st = useStudioStore.getState();
    if (wheel && wheel.sel >= 0) st.setExpression(EXPRESSIONS[wheel.sel]);
    else if (performance.now() - start.current < 220) {
      st.setExpression(EXPRESSIONS[(EXPRESSIONS.indexOf(expr) + 1) % 6]);
    }
    setWheel(null);
  };

  return (
    <>
      <button
        className="act act-face"
        style={{ '--led': LED_FACES[expr].color } as React.CSSProperties}
        onPointerDown={down}
        onPointerMove={move}
        onPointerUp={up}
        onPointerCancel={() => setWheel(null)}
      >
        <span className="act-label">FACE</span>
        <span className="act-sub">{expr}</span>
      </button>
      {wheel && (
        <div className="wheel" style={{ left: wheel.x, top: wheel.y }}>
          {EXPRESSIONS.map((e: Expression, i) => {
            const a = (i / 6) * Math.PI * 2 - Math.PI / 2;
            return (
              <div
                key={e}
                className={`wheel-item ${wheel.sel === i ? 'sel' : ''}`}
                style={{
                  transform: `translate(${Math.cos(a) * 92}px, ${Math.sin(a) * 92}px)`,
                  borderColor: LED_FACES[e].color,
                  color: LED_FACES[e].color,
                }}
              >
                <b>{i + 1}</b>
                {e}
              </div>
            );
          })}
          <div className="wheel-center">{wheel.sel >= 0 ? EXPRESSIONS[wheel.sel] : 'drag'}</div>
        </div>
      )}
    </>
  );
}

function ActionCluster() {
  const talkHeld = useStudioStore((s) => s.talkHeld);
  const stage = useStudioStore((s) => s.waterStage);
  const set = useStudioStore((s) => s.set);
  const talk = (on: boolean) => (e: RPE) => {
    e.stopPropagation();
    void voiceFX.ensure();
    set({ talkHeld: on });
  };
  return (
    <div className="actions">
      <button
        className={`act act-talk ${talkHeld ? 'on' : ''}`}
        onPointerDown={talk(true)}
        onPointerUp={talk(false)}
        onPointerLeave={(e) => talkHeld && talk(false)(e)}
        onPointerCancel={talk(false)}
      >
        <span className="act-label">TALK</span>
        <span className="act-sub">hold · space</span>
      </button>
      <button
        className="act act-hop"
        onPointerDown={(e) => {
          e.stopPropagation();
          hop(useStudioStore.getState().activeActorId);
        }}
      >
        <span className="act-label">HOP</span>
        <span className="act-sub">F</span>
      </button>
      <button
        className={`act act-chaos stage-${stage}`}
        onPointerDown={(e) => {
          e.stopPropagation();
          advanceChaos();
        }}
      >
        <span className="act-label">CHAOS</span>
        <span className="act-sub">{stage === 3 ? 'drain' : `stage ${stage + 1}`}</span>
      </button>
      <FaceButton />
    </div>
  );
}

export function GameHUD() {
  return (
    <>
      <JoystickZone />
      <LookZone />
      <ActionCluster />
    </>
  );
}
