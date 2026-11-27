import { useStudioStore } from '../store/useStudioStore';
import { runtime } from './runtime';
import { voiceFX } from './VoiceFXEngine';

/**
 * HUD-free recorder: captures ONLY the WebGL canvas (React overlays and safe-zone guides
 * are separate DOM layers, so they never appear) + the master Web Audio bus
 * (voice FX, music, SFX baked in).
 */
class DualRecorderImpl {
  private rec: MediaRecorder | null = null;
  private chunks: Blob[] = [];

  private pickMime() {
    const candidates = [
      'video/mp4;codecs=avc1.42E01E,mp4a.40.2',
      'video/mp4',
      'video/webm;codecs=vp9,opus',
      'video/webm;codecs=vp8,opus',
      'video/webm',
    ];
    return candidates.find((m) => MediaRecorder.isTypeSupported(m)) ?? '';
  }

  async start() {
    const canvas = runtime.canvas;
    if (!canvas || this.rec) return;
    await voiceFX.ensure();
    const video = canvas.captureStream(60);
    const stream = new MediaStream([...video.getVideoTracks(), ...voiceFX.recordDest.stream.getAudioTracks()]);
    const mimeType = this.pickMime();
    this.chunks = [];
    this.rec = new MediaRecorder(stream, {
      mimeType: mimeType || undefined,
      videoBitsPerSecond: 12_000_000,
      audioBitsPerSecond: 192_000,
    });
    this.rec.ondataavailable = (e) => e.data.size && this.chunks.push(e.data);
    this.rec.onstop = () => {
      const type = this.rec?.mimeType || mimeType || 'video/webm';
      const blob = new Blob(this.chunks, { type });
      const st = useStudioStore.getState();
      const ext = type.includes('mp4') ? 'mp4' : 'webm';
      const stamp = new Date().toISOString().replace(/[:.]/g, '-').slice(0, 19);
      const a = document.createElement('a');
      a.href = URL.createObjectURL(blob);
      a.download = `${st.episodeSlug || 'take'}_${st.aspect.replace(':', 'x')}_${stamp}.${ext}`;
      a.click();
      setTimeout(() => URL.revokeObjectURL(a.href), 10_000);
      this.rec = null;
    };
    this.rec.start(250);
    useStudioStore.getState().set({ recording: true });
  }

  stop() {
    this.rec?.stop();
    useStudioStore.getState().set({ recording: false });
  }

  toggle() {
    if (this.rec) this.stop();
    else void this.start();
  }
}

export const dualRecorder = new DualRecorderImpl();
