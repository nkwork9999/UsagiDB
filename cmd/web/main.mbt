///| Canvas FFI — JS host assigns the active context to `globalThis.__ctx`.
extern "js" fn ctx_clear(w : Double, h : Double) -> Unit =
  #|(w, h) => globalThis.__ctx.clearRect(0, 0, w, h)

///|
extern "js" fn ctx_begin_path() -> Unit =
  #|() => globalThis.__ctx.beginPath()

///|
extern "js" fn ctx_move_to(x : Double, y : Double) -> Unit =
  #|(x, y) => globalThis.__ctx.moveTo(x, y)

///|
extern "js" fn ctx_line_to(x : Double, y : Double) -> Unit =
  #|(x, y) => globalThis.__ctx.lineTo(x, y)

///|
extern "js" fn ctx_stroke() -> Unit =
  #|() => globalThis.__ctx.stroke()

///|
extern "js" fn ctx_fill_rect(
  x : Double,
  y : Double,
  w : Double,
  h : Double,
) -> Unit =
  #|(x, y, w, h) => globalThis.__ctx.fillRect(x, y, w, h)

///|
extern "js" fn ctx_set_stroke(style : String) -> Unit =
  #|(s) => { globalThis.__ctx.strokeStyle = s }

///|
extern "js" fn ctx_set_fill(style : String) -> Unit =
  #|(s) => { globalThis.__ctx.fillStyle = s }

///|
extern "js" fn ctx_set_line_width(w : Double) -> Unit =
  #|(w) => { globalThis.__ctx.lineWidth = w }

///|
extern "js" fn ctx_fill_text(s : String, x : Double, y : Double) -> Unit =
  #|(s, x, y) => globalThis.__ctx.fillText(s, x, y)

///|
extern "js" fn ctx_set_font(s : String) -> Unit =
  #|(s) => { globalThis.__ctx.font = s }

///|
extern "js" fn ctx_global_alpha(a : Double) -> Unit =
  #|(a) => { globalThis.__ctx.globalAlpha = a }

///|
extern "js" fn dom_set_text(id : String, text : String) -> Unit =
  #|(id, t) => { const el = document.getElementById(id); if (el) el.textContent = t; }

///| Session state — rebuilt whenever the user flips strategies.
struct Session {
  store : @stream.EventStore
  mut clock_ms : Int64
  strategy_kind : Int
  sensor_on : Bool
  // Smoothly-tweened y-axis for the price panel — settles toward the data's
  // real min/max each frame instead of snapping, so candles don't bob
  // vertically when extremes drop out of the visible window.
  mut view_v_min : Double
  mut view_v_max : Double
  mut view_inited : Bool
}

///| Bucket width in ms for the current strategy. `0L` means "not downsampled".
fn bucket_ms_for(kind : Int) -> Int64 {
  match kind {
    1 => 1000L
    2 => 5000L
    _ => 0L
  }
}

///|
fn fresh_session(
  store : @stream.EventStore,
  clock_ms : Int64,
  kind : Int,
  sensor_on : Bool,
) -> Session {
  {
    store,
    clock_ms,
    strategy_kind: kind,
    sensor_on,
    view_v_min: 0.0,
    view_v_max: 1.0,
    view_inited: false,
  }
}

///|
let g_session : Ref[Session?] = { val: None }

///|
fn make_store(kind : Int, sensor_on : Bool) -> @stream.EventStore {
  let config = @stream.CompactionConfig::new()
  match kind {
    0 => {
      let _ = config.rule("price", @stream.KeepLastN(300))

    }
    1 => {
      let _ = config.rule("price", @stream.Downsample(1000L, @stream.OHLC))

    }
    2 => {
      let _ = config.rule("price", @stream.Downsample(5000L, @stream.OHLC))

    }
    _ => {
      let _ = config.rule("price", @stream.KeepAll)

    }
  }
  if sensor_on {
    let _ = config.rule("temp", @stream.DeadBand(0.4))
    let _ = config.validate("temp", @stream.Range(-40.0, 60.0))
    let _ = config.rule("valve", @stream.ExceptionBased(0.5, 2000L))
  }
  @stream.EventStore::new(config)
}

///|
pub fn boot() -> Unit {
  g_session.val = Some(fresh_session(make_store(1, true), 0L, 1, true))
}

///| Called from JS with the simulated next price (and, if the sensor toggle
/// is on, a temperature + valve state).  Advances the internal clock by
/// `dt_ms` so `time` stays monotonic even under a paused UI.
pub fn tick(
  dt_ms : Double,
  price : Double,
  temp : Double,
  valve : Double,
) -> Unit {
  match g_session.val {
    None => ()
    Some(s) => {
      s.clock_ms = s.clock_ms + dt_ms.to_int64()
      let _ = s.store.put("price", price, s.clock_ms)
      if s.sensor_on {
        let _ = s.store.put("temp", temp, s.clock_ms)
        let _ = s.store.put("valve", valve, s.clock_ms)
      }
    }
  }
}

///|
pub fn set_strategy(kind : Int) -> Unit {
  match g_session.val {
    None => ()
    Some(s) =>
      g_session.val = Some(
        fresh_session(make_store(kind, s.sensor_on), s.clock_ms, kind, s.sensor_on),
      )
  }
}

///|
pub fn toggle_sensor() -> Unit {
  match g_session.val {
    None => ()
    Some(s) => {
      let on = not(s.sensor_on)
      g_session.val = Some(
        fresh_session(make_store(s.strategy_kind, on), s.clock_ms, s.strategy_kind, on),
      )
    }
  }
}

///|
pub fn reset() -> Unit {
  match g_session.val {
    None => ()
    Some(s) =>
      g_session.val = Some(
        fresh_session(make_store(s.strategy_kind, s.sensor_on), 0L, s.strategy_kind, s.sensor_on),
      )
  }
}

///| Main draw. JS supplies the canvas pixel dimensions so we don't hardcode.
pub fn draw(width : Double, height : Double) -> Unit {
  match g_session.val {
    None => ()
    Some(s) => do_draw(s, width, height)
  }
}

///|
fn do_draw(s : Session, width : Double, height : Double) -> Unit {
  // background
  ctx_set_fill("#0e1018")
  ctx_fill_rect(0.0, 0.0, width, height)

  // layout: price panel on top 60%, sensors on bottom 40%
  let price_h = if s.sensor_on { height * 0.6 } else { height - 24.0 }
  draw_price_panel(s, 0.0, 0.0, width, price_h)
  if s.sensor_on {
    draw_temp_panel(s, 0.0, price_h, width, height - price_h - 24.0)
    draw_valve_strip(s, 0.0, height - 24.0, width, 24.0)
  }

  // stats footer updates DOM
  update_stats(s)
}

///|
fn draw_price_panel(
  s : Session,
  x : Double,
  y : Double,
  w : Double,
  h : Double,
) -> Unit {
  // panel title
  ctx_set_fill("#2a2e3c")
  ctx_fill_rect(x, y, w, h)
  ctx_set_fill("#8aa4ff")
  ctx_set_font("12px system-ui")
  ctx_fill_text("price  \{strategy_label(s.strategy_kind)}", x + 8.0, y + 16.0)

  let rows = s.store.query("price")
  if rows.length() == 0 {
    return
  }
  let body_x = x + 12.0
  let body_y = y + 24.0
  let body_w = w - 24.0
  let body_h = h - 32.0

  // compute t/v ranges
  let mut t_min : Int64 = time_of(rows[0])
  let mut t_max : Int64 = t_min
  let mut v_min = 0.0
  let mut v_max = 0.0
  let mut inited = false
  for r in rows {
    let t = time_of(r)
    if t < t_min {
      t_min = t
    }
    if t > t_max {
      t_max = t
    }
    let (lo, hi) = value_range(r)
    if not(inited) {
      v_min = lo
      v_max = hi
      inited = true
    } else {
      if lo < v_min {
        v_min = lo
      }
      if hi > v_max {
        v_max = hi
      }
    }
  }
  // pad vertical range, then EMA-tween toward it so the y-axis doesn't snap.
  let pad = (v_max - v_min) * 0.15 + 0.001
  let target_v_min = v_min - pad
  let target_v_max = v_max + pad
  if not(s.view_inited) {
    s.view_v_min = target_v_min
    s.view_v_max = target_v_max
    s.view_inited = true
  } else {
    let alpha = 0.06
    s.view_v_min = s.view_v_min + (target_v_min - s.view_v_min) * alpha
    s.view_v_max = s.view_v_max + (target_v_max - s.view_v_max) * alpha
  }
  let view_min = s.view_v_min
  let view_max = s.view_v_max
  let view_span = if view_max - view_min < 0.001 {
    0.001
  } else {
    view_max - view_min
  }
  let t_span = if t_max == t_min { 1L } else { t_max - t_min }

  // faint horizontal grid
  ctx_global_alpha(0.15)
  ctx_set_stroke("#6a7290")
  ctx_set_line_width(1.0)
  let mut gi = 0
  while gi <= 4 {
    let gy = body_y + body_h * gi.to_double() / 4.0
    ctx_begin_path()
    ctx_move_to(body_x, gy)
    ctx_line_to(body_x + body_w, gy)
    ctx_stroke()
    gi = gi + 1
  }
  ctx_global_alpha(1.0)

  // render
  match s.strategy_kind {
    0 =>
      render_line(rows, body_x, body_y, body_w, body_h, t_min, t_span, view_min, view_span)
    _ => {
      let bucket = bucket_ms_for(s.strategy_kind)
      render_candles_smooth(rows, body_x, body_y, body_w, body_h, view_min, view_span, bucket, s.clock_ms)
    }
  }

  // price axis labels (min / max)
  ctx_set_fill("#9ca0b5")
  ctx_set_font("10px system-ui")
  ctx_fill_text(fmt1(view_max), x + 4.0, body_y + 8.0)
  ctx_fill_text(fmt1(view_min), x + 4.0, body_y + body_h)
}

///|
fn render_line(
  rows : Array[@stream.Row],
  bx : Double,
  by : Double,
  bw : Double,
  bh : Double,
  t_min : Int64,
  t_span : Int64,
  v_min : Double,
  v_span : Double,
) -> Unit {
  ctx_set_stroke("#6ee7b7")
  ctx_set_line_width(1.5)
  ctx_begin_path()
  let mut first = true
  for r in rows {
    match r {
      @stream.Point(t, v) => {
        let px = bx + (t - t_min).to_double() / t_span.to_double() * bw
        let py = by + bh - (v - v_min) / v_span * bh
        if first {
          ctx_move_to(px, py)
          first = false
        } else {
          ctx_line_to(px, py)
        }
      }
      _ => ()
    }
  }
  ctx_stroke()
}

///| Smooth-scrolling candle layout.
///
/// Each candle's x-position is derived from the gap between its bucket start
/// and `clock_ms` rather than its index in the array. This means that as time
/// progresses inside the live bucket, every candle slides leftward smoothly,
/// and a bucket rollover doesn't visibly snap. The live (rightmost) bucket
/// is rendered with reduced opacity so the eye treats it as "still forming".
fn render_candles_smooth(
  rows : Array[@stream.Row],
  bx : Double,
  by : Double,
  bw : Double,
  bh : Double,
  v_min : Double,
  v_span : Double,
  bucket_ms : Int64,
  clock_ms : Int64,
) -> Unit {
  let n = rows.length()
  if n == 0 {
    return
  }
  // How many candles to fit on screen — the live one is the right-most slot.
  let visible = 30
  let cell = bw / visible.to_double()
  let body_w = if cell * 0.6 > 1.0 { cell * 0.6 } else { 1.0 }
  let right_edge = bx + bw
  let last_idx = n - 1

  // Live bucket's start: it's the most recent row's `start`.
  let live_start : Int64 = match rows[last_idx] {
    @stream.Candle(b) => b.start
    _ => clock_ms
  }
  // Progress 0..1 inside the live bucket. Pinning x via this ratio means the
  // chart slides continuously instead of snapping each rollover.
  let bucket_d = bucket_ms.to_double()
  let raw_progress = if bucket_d > 0.0 {
    (clock_ms - live_start).to_double() / bucket_d
  } else {
    0.0
  }
  let progress = if raw_progress < 0.0 {
    0.0
  } else if raw_progress > 1.0 {
    1.0
  } else {
    raw_progress
  }
  let mut idx = 0
  for r in rows {
    match r {
      @stream.Candle(b) => {
        // Distance from "now" measured in cells.
        let dist = (last_idx - idx).to_double() + progress
        let cx = right_edge - dist * cell
        // Cull anything that has scrolled off the left edge.
        if cx < bx - cell {
          ()
        } else {
          let y_hi = by + bh - (b.high - v_min) / v_span * bh
          let y_lo = by + bh - (b.low - v_min) / v_span * bh
          let y_open = by + bh - (b.open - v_min) / v_span * bh
          let y_close = by + bh - (b.close - v_min) / v_span * bh
          let color = if b.close >= b.open { "#6ee7b7" } else { "#f87171" }
          let is_live = idx == last_idx
          if is_live {
            ctx_global_alpha(0.45)
          }
          ctx_set_stroke(color)
          ctx_set_line_width(1.0)
          ctx_begin_path()
          ctx_move_to(cx, y_hi)
          ctx_line_to(cx, y_lo)
          ctx_stroke()
          ctx_set_fill(color)
          let y_top = if y_open < y_close { y_open } else { y_close }
          let y_bot = if y_open < y_close { y_close } else { y_open }
          let h = y_bot - y_top
          let h2 = if h < 1.0 { 1.0 } else { h }
          ctx_fill_rect(cx - body_w / 2.0, y_top, body_w, h2)
          if is_live {
            // Outline the live candle so it reads as "in progress".
            ctx_global_alpha(0.9)
            ctx_set_stroke(color)
            ctx_set_line_width(1.0)
            ctx_begin_path()
            ctx_move_to(cx - body_w / 2.0, y_top)
            ctx_line_to(cx + body_w / 2.0, y_top)
            ctx_line_to(cx + body_w / 2.0, y_bot)
            ctx_line_to(cx - body_w / 2.0, y_bot)
            ctx_line_to(cx - body_w / 2.0, y_top)
            ctx_stroke()
            ctx_global_alpha(1.0)
          }
        }
      }
      _ => ()
    }
    idx = idx + 1
  }
}

///|
fn draw_temp_panel(
  s : Session,
  x : Double,
  y : Double,
  w : Double,
  h : Double,
) -> Unit {
  ctx_set_fill("#1b1f2b")
  ctx_fill_rect(x, y, w, h)
  let rows = s.store.query("temp")
  let received = s.store.stats("temp").0
  let kept = rows.length()
  ctx_set_fill("#fbbf24")
  ctx_set_font("11px system-ui")
  ctx_fill_text(
    "temp  DeadBand(0.4) + Range(-40..60)   recv=\{received} kept=\{kept}",
    x + 8.0,
    y + 14.0,
  )
  if rows.length() == 0 {
    return
  }
  let body_x = x + 12.0
  let body_y = y + 22.0
  let body_w = w - 24.0
  let body_h = h - 30.0
  // range
  let mut v_min = 999.0
  let mut v_max = -999.0
  let mut t_min = time_of(rows[0])
  let mut t_max = t_min
  for r in rows {
    let t = time_of(r)
    if t < t_min {
      t_min = t
    }
    if t > t_max {
      t_max = t
    }
    match r {
      @stream.Point(_, v) => {
        if v < v_min {
          v_min = v
        }
        if v > v_max {
          v_max = v
        }
      }
      _ => ()
    }
  }
  let v_span = if v_max - v_min < 0.1 { 0.1 } else { v_max - v_min + 0.1 }
  let t_span = if t_max == t_min { 1L } else { t_max - t_min }
  ctx_set_stroke("#fbbf24")
  ctx_set_line_width(1.2)
  ctx_begin_path()
  let mut first = true
  for r in rows {
    match r {
      @stream.Point(t, v) => {
        let px = body_x + (t - t_min).to_double() / t_span.to_double() * body_w
        let py = body_y + body_h - (v - v_min) / v_span * body_h
        if first {
          ctx_move_to(px, py)
          first = false
        } else {
          ctx_line_to(px, py)
        }
        ctx_set_fill("#fbbf24")
        ctx_fill_rect(px - 1.5, py - 1.5, 3.0, 3.0)
        ctx_begin_path()
        ctx_move_to(px, py)
      }
      _ => ()
    }
  }
  ctx_stroke()

  // anomalies as red marks along the baseline
  let anoms = s.store.anomalies("temp")
  for a in anoms {
    let (t, _) = a
    if t >= t_min && t <= t_max {
      let px = body_x + (t - t_min).to_double() / t_span.to_double() * body_w
      ctx_set_fill("#f87171")
      ctx_fill_rect(px - 1.0, body_y, 2.0, body_h)
    }
  }
}

///|
fn draw_valve_strip(
  s : Session,
  x : Double,
  y : Double,
  w : Double,
  h : Double,
) -> Unit {
  ctx_set_fill("#0a0c14")
  ctx_fill_rect(x, y, w, h)
  let rows = s.store.query("valve")
  if rows.length() == 0 {
    return
  }
  let mut t_min = time_of(rows[0])
  let mut t_max = t_min
  for r in rows {
    let t = time_of(r)
    if t < t_min {
      t_min = t
    }
    if t > t_max {
      t_max = t
    }
  }
  let t_span = if t_max == t_min { 1L } else { t_max - t_min }
  for r in rows {
    match r {
      @stream.Point(t, v) => {
        let px = x + (t - t_min).to_double() / t_span.to_double() * w
        let color = if v > 0.5 { "#60a5fa" } else { "#334155" }
        ctx_set_fill(color)
        ctx_fill_rect(px - 1.0, y + 4.0, 2.0, h - 8.0)
      }
      _ => ()
    }
  }
  ctx_set_fill("#64748b")
  ctx_set_font("10px system-ui")
  let rec = s.store.stats("valve").0
  let kept = rows.length()
  ctx_fill_text("valve  ExceptionBased + heartbeat  recv=\{rec} kept=\{kept}", x + 8.0, y + 16.0)
}

///|
fn update_stats(s : Session) -> Unit {
  let (rec, kept) = s.store.stats("price")
  let stored = s.store.size("price")
  let ratio = if rec > 0 {
    (stored.to_double() / rec.to_double() * 100.0).to_int()
  } else {
    0
  }
  dom_set_text("stat-received", rec.to_string())
  dom_set_text("stat-kept", kept.to_string())
  dom_set_text("stat-stored", stored.to_string())
  dom_set_text("stat-ratio", "\{ratio}%")
}

///|
fn strategy_label(kind : Int) -> String {
  match kind {
    0 => "KeepLastN(300)"
    1 => "Downsample(1s, OHLC)"
    2 => "Downsample(5s, OHLC)"
    _ => "KeepAll"
  }
}

///|
fn time_of(r : @stream.Row) -> Int64 {
  match r {
    @stream.Point(t, _) => t
    @stream.Candle(b) => b.start
  }
}

///|
fn value_range(r : @stream.Row) -> (Double, Double) {
  match r {
    @stream.Point(_, v) => (v, v)
    @stream.Candle(b) => (b.low, b.high)
  }
}

///|
fn fmt1(x : Double) -> String {
  ((x * 10.0).to_int().to_double() / 10.0).to_string()
}

///|
fn main {

}
