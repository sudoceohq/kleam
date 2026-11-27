import { keyPosition } from "../keyboard.ts";
import { DEFAULT_SWITCH_SLUG } from "../switches.ts";

export type Stroke = "down" | "up";

export type EngineOptions = {
  enabled: boolean;
  volume: number;
  randomPitch: boolean;
  spatial: boolean;
  upDown: boolean;
};

export type Played = {
  code: string;
  stroke: Stroke;
  pitch: number;
  cents: number;
};

const VARIANTS = 6;

/** Triangular spread. Most presses sit near the center; the edges reach ±5%. */
export const PITCH_DEPTH = 0.05;

export function randomPitchFactor(enabled: boolean, rng: () => number = Math.random): number {
  if (!enabled) return 1;
  const spread = rng() + rng() - 1;
  return 1 + spread * PITCH_DEPTH;
}

export function toCents(pitch: number): number {
  return Math.round(1200 * Math.log2(pitch));
}

function variantFor(code: string): number {
  let hash = 0;
  for (let index = 0; index < code.length; index++) {
    hash = (hash * 33 + code.charCodeAt(index)) >>> 0;
  }
  return hash % VARIANTS;
}

function baseRate(code: string): number {
  if (code === "Space") return 0.84;
  if (
    code === "Enter" ||
    code === "Backspace" ||
    code === "Tab" ||
    code === "CapsLock" ||
    code.startsWith("Shift") ||
    code.startsWith("Control") ||
    code.startsWith("Alt") ||
    code.startsWith("Meta")
  ) {
    return 0.92;
  }
  if (code.startsWith("Digit") || code === "Backquote" || code === "Minus" || code === "Equal") {
    return 1.06;
  }
  return 1;
}

async function loadBank(ctx: AudioContext, slug: string, stroke: Stroke): Promise<AudioBuffer[]> {
  const buffers = await Promise.all(
    Array.from({ length: VARIANTS }, async (_, index) => {
      const response = await fetch(`${import.meta.env.BASE_URL}sounds/${slug}/${stroke}-${index}.wav`);
      if (!response.ok) throw new Error(`Missing ${slug}/${stroke}-${index}.wav`);
      return ctx.decodeAudioData(await response.arrayBuffer());
    }),
  );
  return buffers;
}

export class KleamEngine {
  private ctx: AudioContext | null = null;
  private master: GainNode | null = null;
  private analyser: AnalyserNode | null = null;
  private down: AudioBuffer[] = [];
  private up: AudioBuffer[] = [];
  private loading: Promise<void> | null = null;
  private loadToken = 0;
  private slug = DEFAULT_SWITCH_SLUG;
  private time = new Uint8Array(new ArrayBuffer(256));
  private options: EngineOptions;

  constructor(options: EngineOptions, slug: string = DEFAULT_SWITCH_SLUG) {
    this.options = options;
    this.slug = slug;
  }

  getSwitch(): string {
    return this.slug;
  }

  /** Reload down/up banks from `{base}sounds/{slug}/`. Mouse wavs are unused on web. */
  setSwitch(slug: string) {
    if (slug === this.slug && this.down.length > 0 && this.up.length > 0) return;
    this.slug = slug;
    this.down = [];
    this.up = [];
    this.loading = null;
    this.loadToken += 1;
    void this.preload();
  }

  setOptions(options: EngineOptions) {
    this.options = options;
    if (!this.master || !this.ctx) return;
    const volume = options.enabled ? options.volume : 0;
    this.master.gain.setTargetAtTime(volume, this.ctx.currentTime, 0.02);
  }

  resume() {
    const ctx = this.ensure();
    if (ctx.state !== "running") void ctx.resume();
    void this.preload();
  }

  close() {
    const ctx = this.ctx;
    this.ctx = null;
    this.master = null;
    this.analyser = null;
    this.down = [];
    this.up = [];
    this.loading = null;
    this.loadToken += 1;
    if (ctx && ctx.state !== "closed") void ctx.close();
  }

  keyDown(code: string): Played | null {
    return this.trigger(code, "down");
  }

  keyUp(code: string): Played | null {
    if (!this.options.upDown) return null;
    return this.trigger(code, "up");
  }

  preview(codes: string[]): Played[] {
    if (!this.options.enabled || this.options.volume <= 0.001) return [];
    const ctx = this.ensure();
    const events = codes.map((code) => {
      const pitch = baseRate(code) * randomPitchFactor(this.options.randomPitch);
      const played: Played = { code, stroke: "down", pitch, cents: toCents(pitch / baseRate(code)) };
      return { code, pitch, played };
    });
    const start = () => {
      void this.preload().then(() => {
        let time = ctx.currentTime + 0.03;
        for (const event of events) {
          this.fire(event.code, "down", time, event.pitch);
          if (this.options.upDown) {
            const upPitch = baseRate(event.code) * randomPitchFactor(this.options.randomPitch);
            this.fire(event.code, "up", time + 0.09, upPitch);
          }
          time += 0.2;
        }
      });
    };
    if (ctx.state === "suspended") void ctx.resume().then(start);
    else start();
    return events.map((event) => event.played);
  }

  getLevel(): number {
    if (!this.analyser) return 0;
    this.analyser.getByteTimeDomainData(this.time);
    let peak = 0;
    for (let index = 0; index < this.time.length; index++) {
      peak = Math.max(peak, Math.abs((this.time[index] ?? 128) - 128));
    }
    return Math.min(1, peak / 36);
  }

  private trigger(code: string, stroke: Stroke): Played | null {
    if (!this.options.enabled || this.options.volume <= 0.001) return null;
    const ctx = this.ensure();
    const rate = baseRate(code);
    const pitch = rate * randomPitchFactor(this.options.randomPitch);
    const played: Played = { code, stroke, pitch, cents: toCents(pitch / rate) };
    const start = () => {
      void this.preload().then(() => this.fire(code, stroke, ctx.currentTime + 0.005, pitch));
    };
    if (ctx.state === "suspended") void ctx.resume().then(start);
    else start();
    return played;
  }

  private fire(code: string, stroke: Stroke, time: number, pitch: number) {
    if (!this.ctx || !this.master) return;
    const bank = stroke === "down" ? this.down : this.up;
    const buffer = bank[variantFor(code)];
    if (!buffer) return;
    const source = this.ctx.createBufferSource();
    source.buffer = buffer;
    source.playbackRate.setValueAtTime(pitch, time);
    const gain = this.ctx.createGain();
    gain.gain.value = this.options.randomPitch ? 0.9 + Math.random() * 0.15 : 1;
    const position = keyPosition(code);
    source.connect(gain);
    if (this.options.spatial) {
      const panner = this.ctx.createPanner();
      panner.panningModel = "HRTF";
      panner.distanceModel = "inverse";
      panner.refDistance = 1;
      panner.rolloffFactor = 0.3;
      panner.positionX.value = (position.x - 0.5) * 2.1;
      panner.positionY.value = (0.42 - position.y) * 0.55;
      panner.positionZ.value = -0.6;
      gain.connect(panner);
      panner.connect(this.master);
    } else {
      const pan = this.ctx.createStereoPanner();
      pan.pan.value = Math.max(-1, Math.min(1, (position.x - 0.5) * 0.35));
      gain.connect(pan);
      pan.connect(this.master);
    }
    source.start(time);
  }

  private preload(): Promise<void> {
    const ctx = this.ctx;
    if (!ctx) return Promise.resolve();
    if (this.down.length > 0 && this.up.length > 0) return Promise.resolve();
    const token = this.loadToken;
    const slug = this.slug;
    this.loading ??= Promise.all([loadBank(ctx, slug, "down"), loadBank(ctx, slug, "up")])
      .then(([down, up]) => {
        if (token !== this.loadToken || this.slug !== slug) return;
        this.down = down;
        this.up = up;
      })
      .finally(() => {
        this.loading = null;
      });
    return this.loading;
  }

  private ensure(): AudioContext {
    if (this.ctx && this.master) return this.ctx;
    const ctx = new AudioContext();
    const master = ctx.createGain();
    master.gain.value = this.options.enabled ? this.options.volume : 0;
    const comp = ctx.createDynamicsCompressor();
    comp.threshold.value = -16;
    comp.knee.value = 10;
    comp.ratio.value = 1.6;
    comp.attack.value = 0.003;
    comp.release.value = 0.08;
    const analyser = ctx.createAnalyser();
    analyser.fftSize = 256;
    analyser.smoothingTimeConstant = 0.45;
    master.connect(comp);
    comp.connect(ctx.destination);
    comp.connect(analyser);
    if (ctx.listener.forwardZ) ctx.listener.forwardZ.value = -1;
    this.ctx = ctx;
    this.master = master;
    this.analyser = analyser;
    return ctx;
  }
}
