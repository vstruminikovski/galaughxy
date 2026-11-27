import type { VoicePreset } from '../types';
import { useStudioStore } from '../store/useStudioStore';

/**
 * Native Web Audio engine.
 *
 *  mic / voiceover ─► voiceIn ─► [preset chain] ─► voiceOut ─┬─► analyser (lip-sync + ducking)
 *                                                            ├─► recordDest
 *                                                            └─► speakerGain ─► speakers
 *  music ─► musicGain ─► duckGain ─► master ─┬─► speakers
 *  sfx   ─► sfxGain  ──────────────► master ─┴─► recordDest   (baked into the video)
 */

// Delay-line granular pitch shifter (two crossfaded read heads). Runs on the audio thread.
const PITCH_WORKLET = `
class PitchShifter extends AudioWorkletProcessor {
  static get parameterDescriptors() { return [{ name: 'ratio', defaultValue: 1, minValue: 0.25, maxValue: 4 }]; }
  constructor() { super(); this.size = 8192; this.buf = new Float32Array(this.size); this.w = 0; this.phase = 0; this.win = 1600; }
  read(d) {
    let p = this.w - d; while (p < 0) p += this.size;
    const i = Math.floor(p), f = p - i, a = this.buf[i % this.size], b = this.buf[(i + 1) % this.size];
    return a + (b - a) * f;
  }
  process(inputs, outputs, params) {
    const input = inputs[0] && inputs[0][0];
    const out = outputs[0];
    if (!out || !out[0]) return true;
    const ratio = params.ratio[0];
    const step = (1 - ratio) / this.win;
    for (let i = 0; i < out[0].length; i++) {
      this.buf[this.w] = input ? input[i] : 0;
      this.phase += step; if (this.phase >= 1) this.phase -= 1; if (this.phase < 0) this.phase += 1;
      const p2 = (this.phase + 0.5) % 1;
      const g1 = Math.sin(Math.PI * this.phase) ** 2, g2 = Math.sin(Math.PI * p2) ** 2;
      const s = ratio === 1 ? (input ? input[i] : 0) : this.read(this.phase * this.win + 2) * g1 + this.read(p2 * this.win + 2) * g2;
      for (let c = 0; c < out.length; c++) out[c][i] = s;
      this.w = (this.w + 1) % this.size;
    }
    return true;
  }
}
registerProcessor('pitch-shifter', PitchShifter);
`;

export const VOICE_PRESETS: { id: VoicePreset; label: string }[] = [
  { id: 'normal', label: 'Normal' },
  { id: 'radio', label: 'Radio / Walkie' },
  { id: 'phone', label: 'Phone Call' },
  { id: 'scary', label: 'Scary / Low' },
  { id: 'squeaky', label: 'High Pitch' },
];

export type SfxId = 'splash' | 'sizzle' | 'pipeBurst' | 'impact' | 'slideWhistle' | 'doorSlam';
export const SFX_PADS: { id: SfxId; label: string; key: string }[] = [
  { id: 'splash', label: 'Splash', key: 'F1' },
  { id: 'sizzle', label: 'Sizzle', key: 'F2' },
  { id: 'pipeBurst', label: 'Pipe Burst', key: 'F3' },
  { id: 'impact', label: 'Impact Boom', key: 'F4' },
  { id: 'slideWhistle', label: 'Slide Whistle', key: 'F5' },
  { id: 'doorSlam', label: 'Door Slam', key: 'F6' },
];

const TALK_THRESHOLD = 0.035;

class VoiceFX {
  ctx: AudioContext | null = null;
  private master!: GainNode;
  private voiceIn!: GainNode;
  private voiceOut!: GainNode;
  private speakerGain!: GainNode;
  private analyser!: AnalyserNode;
  private musicGain!: GainNode;
  private duckGain!: GainNode;
  private sfxGain!: GainNode;
  recordDest!: MediaStreamAudioDestinationNode;

  private chainNodes: AudioNode[] = [];
  private workletReady = false;

  private micStream: MediaStream | null = null;
  private micSource: MediaStreamAudioSourceNode | null = null;

  private voBuffer: AudioBuffer | null = null;
  private voSource: AudioBufferSourceNode | null = null;
  voName = '';

  private musicBuffer: AudioBuffer | null = null;
  private musicSource: AudioBufferSourceNode | null = null;
  private musicStartedAt = 0;
  private musicOffset = 0;

  private customSfx = new Map<SfxId, AudioBuffer>();
  private timeData = new Float32Array(1024);
  private level = 0;
  private wasSpeaking = false;
  private silentSince = 0;

  /** Must be called from a user gesture the first time (autoplay policy). */
  async ensure(): Promise<AudioContext> {
    if (this.ctx) {
      if (this.ctx.state === 'suspended') await this.ctx.resume();
      return this.ctx;
    }
    const ctx = new AudioContext({ latencyHint: 'interactive' });
    this.ctx = ctx;
    this.master = ctx.createGain();
    this.recordDest = ctx.createMediaStreamDestination();
    this.master.connect(ctx.destination);
    this.master.connect(this.recordDest);

    this.voiceIn = ctx.createGain();
    this.voiceOut = ctx.createGain();
    this.analyser = ctx.createAnalyser();
    this.analyser.fftSize = 1024;
    this.speakerGain = ctx.createGain();
    this.speakerGain.gain.value = 0;
    this.voiceOut.connect(this.analyser);
    this.voiceOut.connect(this.recordDest);
    this.voiceOut.connect(this.speakerGain).connect(ctx.destination);

    this.musicGain = ctx.createGain();
    this.musicGain.gain.value = 0.55;
    this.duckGain = ctx.createGain();
    this.musicGain.connect(this.duckGain).connect(this.master);
    this.sfxGain = ctx.createGain();
    this.sfxGain.gain.value = 0.9;
    this.sfxGain.connect(this.master);

    try {
      const url = URL.createObjectURL(new Blob([PITCH_WORKLET], { type: 'application/javascript' }));
      await ctx.audioWorklet.addModule(url);
      this.workletReady = true;
    } catch (e) {
      console.warn('[VoiceFX] pitch worklet unavailable, falling back to playbackRate', e);
    }

    this.applyPreset(useStudioStore.getState().voicePreset);
    useStudioStore.subscribe((s, prev) => {
      if (s.voicePreset !== prev.voicePreset) this.applyPreset(s.voicePreset);
      if (s.monitor !== prev.monitor) this.updateSpeaker();
      if (prev.talkHeld && !s.talkHeld) this.onLineEnd();
    });
    window.setInterval(() => this.tick(), 30);
    return ctx;
  }

  // ───────────────────────── voice presets ─────────────────────────
  applyPreset(preset: VoicePreset) {
    const ctx = this.ctx;
    if (!ctx) return;
    this.voiceIn.disconnect();
    this.chainNodes.forEach((n) => n.disconnect());
    this.chainNodes = [];

    const nodes: AudioNode[] = [];
    const biquad = (type: BiquadFilterType, freq: number, q = 0.707, gain = 0) => {
      const f = ctx.createBiquadFilter();
      f.type = type;
      f.frequency.value = freq;
      f.Q.value = q;
      f.gain.value = gain;
      return f;
    };
    const pitch = (ratio: number) => {
      if (!this.workletReady) return null;
      const n = new AudioWorkletNode(ctx, 'pitch-shifter', { outputChannelCount: [1] });
      n.parameters.get('ratio')!.value = ratio;
      return n;
    };

    switch (preset) {
      case 'normal': {
        const g = ctx.createGain();
        g.gain.value = 1.0;
        nodes.push(g);
        break;
      }
      case 'radio': {
        const shaper = ctx.createWaveShaper();
        const curve = new Float32Array(1024);
        for (let i = 0; i < curve.length; i++) {
          const x = (i / (curve.length - 1)) * 2 - 1;
          curve[i] = Math.tanh(2.6 * x);
        }
        shaper.curve = curve;
        shaper.oversample = '2x';
        const out = ctx.createGain();
        out.gain.value = 0.8;
        nodes.push(biquad('highpass', 450, 2.2), biquad('lowpass', 2400, 2.2), shaper, out);
        break;
      }
      case 'phone': {
        const comp = ctx.createDynamicsCompressor();
        comp.threshold.value = -28;
        comp.ratio.value = 4;
        comp.attack.value = 0.005;
        comp.release.value = 0.15;
        const out = ctx.createGain();
        out.gain.value = 1.4;
        nodes.push(biquad('highpass', 320, 3.0), biquad('lowpass', 2800, 3.0), comp, out);
        break;
      }
      case 'scary': {
        const p = pitch(0.76);
        if (p) nodes.push(p);
        nodes.push(biquad('lowpass', 900, 0.9));
        break;
      }
      case 'squeaky': {
        const p = pitch(1.28);
        if (p) nodes.push(p);
        nodes.push(biquad('highshelf', 3200, 0.707, 7));
        break;
      }
    }

    let prev: AudioNode = this.voiceIn;
    for (const n of nodes) {
      prev.connect(n);
      prev = n;
    }
    prev.connect(this.voiceOut);

    // Scary: dark slapback delay (45ms, 0.25 feedback) in parallel.
    if (preset === 'scary') {
      const delay = ctx.createDelay(0.5);
      delay.delayTime.value = 0.045;
      const fb = ctx.createGain();
      fb.gain.value = 0.25;
      const wet = ctx.createGain();
      wet.gain.value = 0.5;
      prev.connect(delay);
      delay.connect(fb).connect(delay);
      delay.connect(wet).connect(this.voiceOut);
      nodes.push(delay, fb, wet);
    }
    this.chainNodes = nodes;
    if (this.voSource) this.voSource.playbackRate.value = this.fallbackRate(preset);
  }

  private fallbackRate(preset: VoicePreset) {
    if (this.workletReady) return 1;
    return preset === 'scary' ? 0.76 : preset === 'squeaky' ? 1.28 : 1;
  }

  private updateSpeaker() {
    if (!this.ctx) return;
    const on = useStudioStore.getState().monitor || !!this.voSource;
    this.speakerGain.gain.setTargetAtTime(on ? 1 : 0, this.ctx.currentTime, 0.02);
  }

  // ───────────────────────── mic ─────────────────────────
  async toggleMic(): Promise<boolean> {
    await this.ensure();
    if (this.micStream) {
      this.micStream.getTracks().forEach((t) => t.stop());
      this.micSource?.disconnect();
      this.micStream = null;
      this.micSource = null;
      return false;
    }
    this.micStream = await navigator.mediaDevices.getUserMedia({
      audio: { echoCancellation: true, noiseSuppression: true, autoGainControl: true },
    });
    this.micSource = this.ctx!.createMediaStreamSource(this.micStream);
    this.micSource.connect(this.voiceIn);
    return true;
  }

  // ───────────────────────── voiceover file ─────────────────────────
  async loadVoiceover(file: File) {
    const ctx = await this.ensure();
    this.voBuffer = await ctx.decodeAudioData(await file.arrayBuffer());
    this.voName = file.name;
  }

  async playVoiceover(onEnd?: () => void) {
    const ctx = await this.ensure();
    if (!this.voBuffer) return;
    this.stopVoiceover();
    const src = ctx.createBufferSource();
    src.buffer = this.voBuffer;
    src.playbackRate.value = this.fallbackRate(useStudioStore.getState().voicePreset);
    src.connect(this.voiceIn);
    src.onended = () => {
      if (this.voSource === src) {
        this.voSource = null;
        this.updateSpeaker();
        this.onLineEnd();
        onEnd?.();
      }
    };
    src.start();
    this.voSource = src;
    this.updateSpeaker();
  }

  stopVoiceover() {
    if (this.voSource) {
      const s = this.voSource;
      this.voSource = null;
      try {
        s.stop();
      } catch {
        /* already stopped */
      }
      this.updateSpeaker();
    }
  }

  // ───────────────────────── analysis / ducking ─────────────────────────
  /** RMS amplitude of the processed voice, 0..~0.5. Cheap enough to call per frame. */
  getLevel(): number {
    if (!this.ctx) return 0;
    this.analyser.getFloatTimeDomainData(this.timeData);
    let sum = 0;
    for (let i = 0; i < this.timeData.length; i++) sum += this.timeData[i] * this.timeData[i];
    this.level = Math.sqrt(sum / this.timeData.length);
    return this.level;
  }

  isSpeaking() {
    return this.level > TALK_THRESHOLD;
  }

  private tick() {
    if (!this.ctx) return;
    const st = useStudioStore.getState();
    const lvl = this.getLevel();
    const speaking = lvl > TALK_THRESHOLD || st.talkHeld;
    const now = this.ctx.currentTime;
    const target = st.ducking && speaking ? 0.25 : 1;
    this.duckGain.gain.setTargetAtTime(target, now, target < 1 ? 0.05 : 0.45);

    // Mic speech gate → radio squelch when a line finishes.
    if (lvl > TALK_THRESHOLD) {
      this.wasSpeaking = true;
      this.silentSince = 0;
    } else if (this.wasSpeaking && !st.talkHeld) {
      if (!this.silentSince) this.silentSince = now;
      else if (now - this.silentSince > 0.3) {
        this.wasSpeaking = false;
        this.silentSince = 0;
        this.onLineEnd();
      }
    }
  }

  private onLineEnd() {
    if (useStudioStore.getState().voicePreset === 'radio') this.squelch();
  }

  // ───────────────────────── music ─────────────────────────
  async loadMusic(file: File) {
    const ctx = await this.ensure();
    const buf = await ctx.decodeAudioData(await file.arrayBuffer());
    const wasPlaying = !!this.musicSource;
    this.stopMusic(true);
    this.musicBuffer = buf;
    this.musicOffset = 0;
    useStudioStore.getState().set({ musicName: file.name });
    if (wasPlaying) await this.playMusic();
  }

  async playMusic() {
    const ctx = await this.ensure();
    if (!this.musicBuffer) this.musicBuffer = await renderGrooveLoop(ctx.sampleRate);
    this.stopMusic(true);
    const src = ctx.createBufferSource();
    src.buffer = this.musicBuffer;
    src.loop = useStudioStore.getState().musicLoop;
    src.connect(this.musicGain);
    const offset = this.musicOffset % this.musicBuffer.duration;
    src.start(0, offset);
    this.musicStartedAt = ctx.currentTime - offset;
    src.onended = () => {
      if (this.musicSource === src) {
        this.musicSource = null;
        this.musicOffset = 0;
        useStudioStore.getState().set({ musicPlaying: false });
      }
    };
    this.musicSource = src;
    useStudioStore.getState().set({ musicPlaying: true });
  }

  stopMusic(keepState = false) {
    if (!this.musicSource || !this.ctx) return;
    const s = this.musicSource;
    this.musicSource = null;
    this.musicOffset = this.ctx.currentTime - this.musicStartedAt;
    try {
      s.stop();
    } catch {
      /* noop */
    }
    if (!keepState) useStudioStore.getState().set({ musicPlaying: false });
  }

  setMusicLoop(loop: boolean) {
    if (this.musicSource) this.musicSource.loop = loop;
  }

  setMusicVolume(v: number) {
    if (this.musicGain) this.musicGain.gain.value = v;
  }

  // ───────────────────────── SFX ─────────────────────────
  async loadSfx(id: SfxId, file: File) {
    const ctx = await this.ensure();
    this.customSfx.set(id, await ctx.decodeAudioData(await file.arrayBuffer()));
  }

  async sfx(id: SfxId) {
    const ctx = await this.ensure();
    const custom = this.customSfx.get(id);
    if (custom) {
      const s = ctx.createBufferSource();
      s.buffer = custom;
      s.connect(this.sfxGain);
      s.start();
      return;
    }
    const t = ctx.currentTime;
    const out = this.sfxGain;
    switch (id) {
      case 'splash': {
        const n = this.noise(0.7);
        const f = ctx.createBiquadFilter();
        f.type = 'bandpass';
        f.frequency.setValueAtTime(1800, t);
        f.frequency.exponentialRampToValueAtTime(500, t + 0.6);
        f.Q.value = 0.8;
        const g = env(ctx, t, 0.005, 0.65, 0.9);
        n.connect(f).connect(g).connect(out);
        n.start(t);
        // a couple of droplet blips
        for (let i = 0; i < 4; i++) this.blip(t + 0.12 + i * 0.09, 900 + i * 260, 0.06, 0.25);
        break;
      }
      case 'sizzle': {
        const n = this.noise(1.6);
        const f = ctx.createBiquadFilter();
        f.type = 'highpass';
        f.frequency.value = 3500;
        const am = ctx.createGain();
        am.gain.value = 0;
        for (let i = 0; i < 60; i++) am.gain.setValueAtTime(Math.random() * 0.7, t + i * 0.025);
        const g = env(ctx, t, 0.05, 1.5, 0.6);
        n.connect(f).connect(am).connect(g).connect(out);
        n.start(t);
        break;
      }
      case 'pipeBurst': {
        this.thump(t, 70, 0.5, 1);
        const n = this.noise(1.4);
        const f = ctx.createBiquadFilter();
        f.type = 'lowpass';
        f.frequency.setValueAtTime(6000, t);
        f.frequency.exponentialRampToValueAtTime(900, t + 1.3);
        const g = env(ctx, t, 0.002, 1.35, 1);
        n.connect(f).connect(g).connect(out);
        n.start(t);
        break;
      }
      case 'impact': {
        const o = ctx.createOscillator();
        o.type = 'sine';
        o.frequency.setValueAtTime(140, t);
        o.frequency.exponentialRampToValueAtTime(38, t + 1.1);
        const sh = ctx.createWaveShaper();
        const c = new Float32Array(512);
        for (let i = 0; i < 512; i++) c[i] = Math.tanh(4 * ((i / 511) * 2 - 1));
        sh.curve = c;
        const g = env(ctx, t, 0.002, 1.4, 1);
        o.connect(sh).connect(g).connect(out);
        o.start(t);
        o.stop(t + 1.5);
        break;
      }
      case 'slideWhistle': {
        const o = ctx.createOscillator();
        o.type = 'sine';
        o.frequency.setValueAtTime(500, t);
        o.frequency.exponentialRampToValueAtTime(1700, t + 0.45);
        o.frequency.exponentialRampToValueAtTime(380, t + 0.95);
        const vib = ctx.createOscillator();
        vib.frequency.value = 7;
        const vg = ctx.createGain();
        vg.gain.value = 18;
        vib.connect(vg).connect(o.frequency);
        const g = env(ctx, t, 0.02, 0.95, 0.35);
        o.connect(g).connect(out);
        o.start(t);
        vib.start(t);
        o.stop(t + 1);
        vib.stop(t + 1);
        break;
      }
      case 'doorSlam': {
        this.thump(t, 95, 0.35, 1);
        const n = this.noise(0.25);
        const f = ctx.createBiquadFilter();
        f.type = 'lowpass';
        f.frequency.value = 2200;
        const g = env(ctx, t, 0.001, 0.22, 0.8);
        n.connect(f).connect(g).connect(out);
        n.start(t);
        this.thump(t + 0.09, 160, 0.12, 0.3);
        break;
      }
    }
  }

  /** Radio squelch: short filtered noise tail + click. */
  squelch() {
    const ctx = this.ctx;
    if (!ctx) return;
    const t = ctx.currentTime;
    const n = this.noise(0.18);
    const f = ctx.createBiquadFilter();
    f.type = 'bandpass';
    f.frequency.value = 1700;
    f.Q.value = 1.2;
    const g = env(ctx, t, 0.002, 0.16, 0.35);
    n.connect(f).connect(g).connect(this.master);
    n.start(t);
    this.blip(t, 2600, 0.012, 0.4, this.master);
  }

  private noise(duration: number) {
    const ctx = this.ctx!;
    const len = Math.max(1, Math.floor(ctx.sampleRate * duration));
    const buf = ctx.createBuffer(1, len, ctx.sampleRate);
    const d = buf.getChannelData(0);
    for (let i = 0; i < len; i++) d[i] = Math.random() * 2 - 1;
    const s = ctx.createBufferSource();
    s.buffer = buf;
    return s;
  }

  private thump(t: number, freq: number, dur: number, vol: number) {
    const ctx = this.ctx!;
    const o = ctx.createOscillator();
    o.frequency.setValueAtTime(freq * 2, t);
    o.frequency.exponentialRampToValueAtTime(freq * 0.5, t + dur);
    const g = env(ctx, t, 0.002, dur, vol);
    o.connect(g).connect(this.sfxGain);
    o.start(t);
    o.stop(t + dur + 0.05);
  }

  private blip(t: number, freq: number, dur: number, vol: number, dest: AudioNode = this.sfxGain) {
    const ctx = this.ctx!;
    const o = ctx.createOscillator();
    o.type = 'sine';
    o.frequency.setValueAtTime(freq, t);
    o.frequency.exponentialRampToValueAtTime(freq * 1.6, t + dur);
    const g = env(ctx, t, 0.001, dur, vol);
    o.connect(g).connect(dest);
    o.start(t);
    o.stop(t + dur + 0.02);
  }
}

function env(ctx: BaseAudioContext, t: number, attack: number, dur: number, peak: number) {
  const g = ctx.createGain();
  g.gain.setValueAtTime(0.0001, t);
  g.gain.exponentialRampToValueAtTime(peak, t + attack);
  g.gain.exponentialRampToValueAtTime(0.0001, t + dur);
  return g;
}

/** Original procedurally composed 4-bar bouncy loop (no external audio). */
async function renderGrooveLoop(sampleRate: number): Promise<AudioBuffer> {
  const bpm = 112;
  const beat = 60 / bpm;
  const bars = 4;
  const len = bars * 4 * beat;
  const ctx = new OfflineAudioContext(2, Math.ceil(len * sampleRate), sampleRate);
  const master = ctx.createGain();
  master.gain.value = 0.5;
  master.connect(ctx.destination);
  const midi = (n: number) => 440 * Math.pow(2, (n - 69) / 12);

  const note = (n: number, t: number, d: number, type: OscillatorType, vol: number, cutoff = 4000) => {
    const o = ctx.createOscillator();
    o.type = type;
    o.frequency.value = midi(n);
    const f = ctx.createBiquadFilter();
    f.type = 'lowpass';
    f.frequency.value = cutoff;
    const g = env(ctx, t, 0.008, d, vol);
    o.connect(f).connect(g).connect(master);
    o.start(t);
    o.stop(t + d + 0.05);
  };

  // C – Am – F – G, walking bass + offbeat plucks + hats
  const chords = [
    [60, 64, 67],
    [57, 60, 64],
    [53, 57, 60],
    [55, 59, 62],
  ];
  const bassWalk = [0, 7, 12, 7];
  chords.forEach((ch, bar) => {
    const t0 = bar * 4 * beat;
    bassWalk.forEach((iv, i) => note(ch[0] - 24 + iv, t0 + i * beat, beat * 0.8, 'triangle', 0.6, 900));
    for (let i = 0; i < 4; i++) ch.forEach((n) => note(n, t0 + (i + 0.5) * beat, beat * 0.3, 'square', 0.07, 2200));
    // tiny melody hook
    note(ch[2] + 12, t0 + 3 * beat, beat * 0.25, 'sine', 0.18);
    note(ch[1] + 12, t0 + 3.5 * beat, beat * 0.25, 'sine', 0.18);
  });
  // hats
  const hatBuf = ctx.createBuffer(1, Math.floor(sampleRate * 0.05), sampleRate);
  const hd = hatBuf.getChannelData(0);
  for (let i = 0; i < hd.length; i++) hd[i] = (Math.random() * 2 - 1) * (1 - i / hd.length);
  for (let i = 0; i < bars * 8; i++) {
    const s = ctx.createBufferSource();
    s.buffer = hatBuf;
    const f = ctx.createBiquadFilter();
    f.type = 'highpass';
    f.frequency.value = 7000;
    const g = ctx.createGain();
    g.gain.value = i % 2 ? 0.12 : 0.22;
    s.connect(f).connect(g).connect(master);
    s.start(i * beat * 0.5);
  }
  return ctx.startRendering();
}

export const voiceFX = new VoiceFX();
