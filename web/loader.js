import {
  boot,
  tick,
  set_strategy,
  toggle_sensor,
  draw,
  reset,
} from "../target/js/release/build/cmd/web/web.js";

const canvas = document.getElementById("stage");
const ctx = canvas.getContext("2d");
globalThis.__ctx = ctx;

// Handle DPR so strokes stay crisp on retina.
function resize() {
  const dpr = window.devicePixelRatio || 1;
  const rect = canvas.getBoundingClientRect();
  canvas.width = Math.round(rect.width * dpr);
  canvas.height = Math.round(rect.height * dpr);
  ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
}
resize();
window.addEventListener("resize", resize);

boot();

// Simulation state — a deterministic-ish random walk for reproducibility.
const sim = {
  price: 100,
  temp: 20.0,
  valve: 0.0,
  valvePhase: 0,
  tempPhase: 0,
};
function nextSample(dt_ms) {
  // Price: mean-reverting random walk with occasional spikes.
  const drift = (100 - sim.price) * 0.002;
  const noise = (Math.random() - 0.5) * 0.6;
  const spike = Math.random() < 0.003 ? (Math.random() - 0.5) * 8 : 0;
  sim.price += drift + noise + spike;

  // Temp: slow drift plus micro-jitter. Rare spike to show Range anomaly.
  sim.tempPhase += dt_ms / 1000;
  const jitter = (Math.random() - 0.5) * 0.08;
  sim.temp = 20 + Math.sin(sim.tempPhase * 0.25) * 4 + jitter;
  if (Math.random() < 0.0015) sim.temp = -999; // out-of-range → anomaly

  // Valve: open for ~4s every ~12s.
  sim.valvePhase += dt_ms;
  const cyclePos = sim.valvePhase % 12000;
  sim.valve = cyclePos < 4000 ? 1 : 0;

  return [sim.price, sim.temp, sim.valve];
}

// UI wiring.
const strategyButtons = Array.from(
  document.querySelectorAll("button[data-strat]"),
);
strategyButtons.forEach((btn) =>
  btn.addEventListener("click", () => {
    strategyButtons.forEach((b) => b.classList.remove("active"));
    btn.classList.add("active");
    set_strategy(parseInt(btn.dataset.strat, 10));
  }),
);

const sensorBtn = document.getElementById("toggle-sensor");
sensorBtn.addEventListener("click", () => {
  sensorBtn.classList.toggle("active");
  toggle_sensor();
});

const pauseBtn = document.getElementById("pause");
let paused = false;
pauseBtn.addEventListener("click", () => {
  paused = !paused;
  pauseBtn.textContent = paused ? "▶ resume" : "⏸ pause";
});

document.getElementById("reset").addEventListener("click", () => {
  sim.price = 100;
  reset();
});

const rateSlider = document.getElementById("rate");
const rateLabel = document.getElementById("rate-label");
let rateHz = parseInt(rateSlider.value, 10);
rateSlider.addEventListener("input", () => {
  rateHz = parseInt(rateSlider.value, 10);
  rateLabel.textContent = rateHz + " /s";
});

// Frame loop. Data production rate is decoupled from render rate — we push
// however many samples the target Hz implies, but draw once per frame (rAF).
let last = performance.now();
let drift = 0;
function frame(now) {
  const dt = now - last;
  last = now;
  if (!paused) {
    // How many samples to feed this frame?
    const want = (rateHz * dt) / 1000 + drift;
    const count = Math.max(0, Math.floor(want));
    drift = want - count;
    const stepMs = count > 0 ? dt / count : 0;
    for (let i = 0; i < count; i++) {
      const [p, t, v] = nextSample(stepMs);
      tick(stepMs, p, t, v);
    }
  }
  const rect = canvas.getBoundingClientRect();
  draw(rect.width, rect.height);
  requestAnimationFrame(frame);
}
requestAnimationFrame(frame);
