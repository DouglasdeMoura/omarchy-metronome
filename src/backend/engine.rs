use crate::json::Json;
use std::sync::atomic::{AtomicBool, AtomicU32, AtomicU64, Ordering};
use std::sync::mpsc::{Receiver, Sender};
use std::sync::Arc;

use super::proto;
use super::state;

// One metronome setting set. Every field the UI can move lives here, clamped
// once, so neither the wire nor the state file can smuggle in a bpm of 10^9.
#[derive(Debug, Clone, PartialEq)]
pub struct Params {
    pub bpm: f64,
    pub beats: u32,
    // The time signature's bottom number: the tick is a 1/d note, so its
    // interval is 60/bpm × 4/d. 1 and 2 stretch the tick past the quarter;
    // 4 is the classic metronome.
    pub denominator: u32,
    pub volume: f32,
    // Ticks per beat: 1 is the beat alone, 2 splits it in halves, 3 in
    // triplets, 4 in quarters. The extra ticks are a lighter voice, and a
    // muted beat keeps its subdivisions muted too.
    pub subdivision: u32,
    // Per-beat voice, one entry per beat position, BEATS_MAX long: 0 silent,
    // 1 low tone, 2 medium tone, 3 high tone. Positions past `beats` are
    // remembered, so a pattern survives a temporary change of meter.
    pub voices: [u8; BEATS_MAX as usize],
}

pub const VOICE_LOW: u8 = 1;
pub const VOICE_MEDIUM: u8 = 2;
pub const VOICE_HIGH: u8 = 3;

pub const DENOMINATORS: [u32; 4] = [1, 2, 4, 8];

impl Default for Params {
    fn default() -> Self {
        Params {
            bpm: 120.0,
            beats: 4,
            denominator: 4,
            volume: 0.8,
            subdivision: 1,
            // The classic metronome: high on the one, low on the rest.
            voices: {
                let mut v = [VOICE_LOW; BEATS_MAX as usize];
                v[0] = VOICE_HIGH;
                v
            },
        }
    }
}

pub const BPM_MIN: f64 = 10.0;
pub const BPM_MAX: f64 = 400.0;
pub const BEATS_MIN: u32 = 1;
pub const BEATS_MAX: u32 = 16;
pub const SUBDIVISION_MIN: u32 = 1;
pub const SUBDIVISION_MAX: u32 = 4;

impl Params {
    pub fn clamp(&mut self) {
        self.bpm = self.bpm.clamp(BPM_MIN, BPM_MAX);
        self.beats = self.beats.clamp(BEATS_MIN, BEATS_MAX);
        // A denominator from outside the set (an old state file, a sloppy
        // client) snaps to the nearest one rather than being refused; the
        // wire refuses, the clamps forgive.
        if !DENOMINATORS.contains(&self.denominator) {
            self.denominator = DENOMINATORS
                .iter()
                .copied()
                .min_by_key(|d| d.abs_diff(self.denominator))
                .unwrap_or(4);
        }
        self.volume = self.volume.clamp(0.0, 1.0);
        self.subdivision = self.subdivision.clamp(SUBDIVISION_MIN, SUBDIVISION_MAX);
    }

    pub fn to_json(&self) -> Json {
        // volume is an f32 by nature, so it renders with f32 noise on the way
        // out; three decimals is what the slider showed and all a state file
        // needs.
        let volume = (self.volume as f64 * 1000.0).round() / 1000.0;
        Json::obj(vec![
            ("bpm", Json::Num(self.bpm)),
            ("beats", Json::int(self.beats as i64)),
            ("denominator", Json::int(self.denominator as i64)),
            ("volume", Json::Num(volume)),
            ("subdivision", Json::int(self.subdivision as i64)),
            (
                "voices",
                Json::Arr(self.voices.iter().map(|v| Json::int(*v as i64)).collect()),
            ),
        ])
    }

    // Only the keys present are a patch; everything else keeps its value.
    pub fn apply_patch(&mut self, body: &Json) -> Result<(), String> {
        if !matches!(body, Json::Obj(_)) {
            return Err("parameters must be an object".into());
        }
        let mut next = self.clone();
        next.patch_fields(body)?;
        *self = next;
        Ok(())
    }

    fn patch_fields(&mut self, body: &Json) -> Result<(), String> {
        if let Some(v) = body.get("bpm") {
            self.bpm = v
                .as_f64()
                .ok_or_else(|| "bpm must be a number".to_string())?;
        }
        if let Some(v) = body.get("beats") {
            self.beats = v
                .as_u32()
                .ok_or_else(|| "beats must be a whole number".to_string())?;
        }
        if let Some(v) = body.get("denominator") {
            let d = v
                .as_u32()
                .ok_or_else(|| "denominator must be a whole number".to_string())?;
            if !DENOMINATORS.contains(&d) {
                return Err("denominator must be 1, 2, 4 or 8".to_string());
            }
            self.denominator = d;
        } else if let Some(v) = body.get("subdiv") {
            // A pre-time-signature state file: the old clicks-per-beat ladder
            // lands on the closest denominator.
            let s = v
                .as_u32()
                .ok_or_else(|| "subdiv must be a whole number".to_string())?;
            self.denominator = match s {
                1 => 4,
                _ => 8,
            };
        }
        if let Some(v) = body.get("volume") {
            self.volume =
                v.as_f64()
                    .ok_or_else(|| "volume must be a number".to_string())? as f32;
        }
        if let Some(v) = body.get("subdivision") {
            let s = v
                .as_u32()
                .ok_or_else(|| "subdivision must be a whole number".to_string())?;
            if !(SUBDIVISION_MIN..=SUBDIVISION_MAX).contains(&s) {
                return Err("subdivision must be 1, 2, 3 or 4".to_string());
            }
            self.subdivision = s;
        }
        if let Some(v) = body.get("voices") {
            let items = match v {
                Json::Arr(items) => items,
                _ => return Err("voices must be an array".to_string()),
            };
            // A short array preserves the tail; an entry that is not 0..3 is
            // refused, not clamped, so a sloppy client learns the wire.
            if items.len() > BEATS_MAX as usize {
                return Err("voices must contain at most sixteen entries".into());
            }
            let mut voices = self.voices;
            for (i, item) in items.iter().take(BEATS_MAX as usize).enumerate() {
                let n = item
                    .as_u32()
                    .filter(|n| *n <= VOICE_HIGH as u32)
                    .ok_or_else(|| format!("voices[{}] must be 0, 1, 2 or 3", i))?;
                voices[i] = n as u8;
            }
            self.voices = voices;
        }
        self.clamp();
        Ok(())
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Kind {
    High,
    Medium,
    Low,
    // A tick between beats, the subdivision's own voice: lighter than any
    // beat, so the beat still reads as the beat.
    Sub,
    // A beat the user muted: the timeline walks it, no click sounds.
    Off,
}

impl Kind {
    pub fn wire(&self) -> &'static str {
        match self {
            Kind::High => "high",
            Kind::Medium => "medium",
            Kind::Low => "low",
            Kind::Sub => "sub",
            Kind::Off => "off",
        }
    }
}

// Events ride the one channel the engine answers through. Beat is emitted by
// the audio callback at the buffer position where the click is mixed in, so a
// lamp lights when its click is on the device, not when a thread woke up.
#[derive(Debug, Clone, PartialEq)]
pub enum Ev {
    Beat { beat: u32, kind: Kind },
    Started,
    Stopped { beats: u64 },
    Error(String),
}

// The click voices. The high tone is brighter, longer and louder; the low
// and medium sit under it, so a pattern reads as one shape, not a row of
// equals.
#[derive(Debug, Clone, Copy)]
struct ClickSpec {
    freq: f32,
    amp: f32,
    dur: f32,
    tau: f32,
}

fn click_spec(kind: Kind) -> ClickSpec {
    match kind {
        Kind::High => ClickSpec {
            freq: 1800.0,
            amp: 1.0,
            dur: 0.07,
            tau: 0.018,
        },
        Kind::Medium => ClickSpec {
            freq: 1400.0,
            amp: 0.85,
            dur: 0.06,
            tau: 0.015,
        },
        Kind::Low => ClickSpec {
            freq: 1100.0,
            amp: 0.7,
            dur: 0.055,
            tau: 0.012,
        },
        Kind::Sub => ClickSpec {
            freq: 1300.0,
            amp: 0.4,
            dur: 0.035,
            tau: 0.008,
        },
        // Nothing sounds on a muted beat; the spec is never sampled because
        // fire_click sets the click length to zero.
        Kind::Off => ClickSpec {
            freq: 0.0,
            amp: 0.0,
            dur: 0.0,
            tau: 1.0,
        },
    }
}

// A short sine burst: ~1 ms fade-in, then an exponential decay. pos is in
// samples at the device's own rate.
fn click_sample(spec: &ClickSpec, pos: usize, sr: f64) -> f32 {
    let t = pos as f64 / sr;
    let attack = 0.001;
    let env = if t < attack {
        t / attack
    } else {
        (-(t - attack) / spec.tau as f64).exp()
    };
    let wave = (2.0 * std::f64::consts::PI * spec.freq as f64 * t).sin();
    (env * wave) as f32 * spec.amp
}

fn click_len(spec: &ClickSpec, sr: f64) -> usize {
    (spec.dur as f64 * sr).ceil() as usize
}

// The keep-alive floor: white noise at -74 dBFS under everything the output
// stream carries, clicks or none, armed or not. A metronome is mostly
// silence, and a link that sees digital silence goes to sleep: Bluetooth
// earbuds gate their amplifier a second or so after the last non-zero
// sample and take a few hundred milliseconds to wake, so a 55 ms tick every
// other beat lands on a sleeping amplifier and is never heard, sometimes for
// bars at a time. The floor is far under any device's own noise and is not
// scaled by volume, because its listener is the hardware, not the player.
const FLOOR_AMP: f32 = 2.0e-4;

// One tick of a x/d signature: a quarter at d=4, an eighth at d=8, a whole
// note at d=1.
fn interval_frames(bpm: f64, denominator: u32, sr: f64) -> f64 {
    240.0 / (bpm * denominator as f64) * sr
}

fn kind_for(beat: u32, params: &Params) -> Kind {
    match params.voices[beat as usize] {
        VOICE_HIGH => Kind::High,
        VOICE_MEDIUM => Kind::Medium,
        VOICE_LOW => Kind::Low,
        _ => Kind::Off,
    }
}

// The timeline both outputs share. phase is the absolute frame of the next
// click, held in f64 so intervals accumulate without integer rounding drift;
// the u64 forms exist only where the device talks in whole frames.
#[derive(Debug)]
struct Timeline {
    armed: bool,
    phase: f64,
    beat: u32,
    // Which tick of the beat is due: 0 is the beat itself.
    sub: u32,
    total_beats: u64,
    click_pos: usize,
    click_len: usize,
    gain: f32,
    spec: ClickSpec,
    // The floor's xorshift state; never zero.
    noise: u32,
}

impl Timeline {
    fn new() -> Self {
        Timeline {
            armed: false,
            phase: 0.0,
            beat: 0,
            sub: 0,
            total_beats: 0,
            click_pos: 0,
            click_len: 0,
            gain: 0.0,
            spec: click_spec(Kind::Low),
            noise: 0x9E37_79B9,
        }
    }

    // Start the bar `lead` seconds from `at`; the lead keeps the first click
    // clear of the priming the device does after play().
    fn arm(&mut self, at: u64, lead: f64, sr: f64) {
        self.armed = true;
        self.phase = at as f64 + lead * sr;
        self.beat = 0;
        self.sub = 0;
        self.total_beats = 0;
        self.click_pos = 0;
        self.click_len = 0;
        self.spec = click_spec(Kind::Low);
    }

    fn disarm(&mut self) {
        self.armed = false;
        self.click_pos = 0;
        self.click_len = 0;
    }

    // Fire the due click: pick its voice from the position the counters name,
    // move the counters on, and step phase one tick. Params are read per
    // click, so a bpm, signature or subdivision change lands at the next
    // boundary, which is where a musician expects it.
    fn fire_click(&mut self, params: &Params, sr: f64) -> Ev {
        self.beat %= params.beats;
        self.gain = params.volume;
        let beat_kind = kind_for(self.beat, params);
        // A tick between beats takes the subdivision's voice, and none at
        // all on a muted beat: a beat the player took out stays out.
        let kind = if self.sub == 0 {
            beat_kind
        } else if beat_kind == Kind::Off {
            Kind::Off
        } else {
            Kind::Sub
        };
        self.spec = click_spec(kind);
        // A muted tick walks the timeline but samples no click.
        self.click_len = if kind == Kind::Off {
            0
        } else {
            click_len(&self.spec, sr)
        };
        self.click_pos = 0;
        let ev = Ev::Beat {
            beat: self.beat,
            kind,
        };
        if self.sub == 0 {
            self.total_beats += 1;
        }
        self.sub += 1;
        if self.sub >= params.subdivision {
            self.sub = 0;
            self.beat = (self.beat + 1) % params.beats;
        }
        self.phase +=
            interval_frames(params.bpm, params.denominator, sr) / params.subdivision as f64;
        ev
    }

    // One buffer's worth: fire every due click, then fill with silence or the
    // running click. `from` is the buffer's first absolute frame.
    #[cfg(test)]
    fn mix_into(
        &mut self,
        out: &mut [f32],
        channels: usize,
        from: u64,
        params: &Params,
        sr: f64,
        events: &mut Vec<Ev>,
    ) {
        for (i, frame) in out.chunks_mut(channels).enumerate() {
            let abs = from + i as u64;
            while self.armed && abs as f64 >= self.phase {
                let ev = self.fire_click(params, sr);
                events.push(ev);
            }
            let s = self.sample(sr);
            for sample in frame.iter_mut() {
                *sample = s;
            }
        }
    }

    // One output sample: the running click, if any, over the floor.
    fn sample(&mut self, sr: f64) -> f32 {
        let floor = self.floor();
        if self.click_pos >= self.click_len {
            return floor;
        }
        let sample = click_sample(&self.spec, self.click_pos, sr) * self.gain;
        self.click_pos += 1;
        sample + floor
    }

    // Uniform white noise in ±FLOOR_AMP from a 32-bit xorshift: no
    // allocation, no syscall, nothing the audio callback may not do.
    fn floor(&mut self) -> f32 {
        let mut x = self.noise;
        x ^= x << 13;
        x ^= x >> 17;
        x ^= x << 5;
        self.noise = x;
        (x as f32 / u32::MAX as f32 * 2.0 - 1.0) * FLOOR_AMP
    }

    // The silent clock's shape of the same loop: no samples, only the due
    // clicks up to `until`, inclusive.
    fn advance_events_to(&mut self, until: u64, params: &Params, sr: f64, events: &mut Vec<Ev>) {
        while self.armed && until as f64 >= self.phase {
            events.push(self.fire_click(params, sr));
        }
    }
}

// Single writer, bounded reader: a callback keeps its previous snapshot if a
// publication is in progress. Sequential consistency makes the version check
// cover all fields without a mutex, allocation, or retry loop.
struct AtomicParams {
    version: AtomicU64,
    bpm: AtomicU64,
    volume: AtomicU32,
    pattern: AtomicU64,
}

impl AtomicParams {
    fn new(params: &Params) -> Self {
        let value = Self {
            version: AtomicU64::new(0),
            bpm: AtomicU64::new(0),
            volume: AtomicU32::new(0),
            pattern: AtomicU64::new(0),
        };
        value.store(params);
        value
    }

    fn store(&self, params: &Params) {
        self.version.fetch_add(1, Ordering::SeqCst);
        self.bpm.store(params.bpm.to_bits(), Ordering::SeqCst);
        self.volume.store(params.volume.to_bits(), Ordering::SeqCst);
        // One word: beats in the low byte, denominator in the next, two
        // bits per voice slot from 16, and the subdivision at 48 — well
        // inside the u64.
        let mut pattern = params.beats as u64
            | ((params.denominator as u64) << 8)
            | ((params.subdivision as u64) << 48);
        for (i, voice) in params.voices.iter().enumerate() {
            pattern |= (*voice as u64) << (16 + i * 2);
        }
        self.pattern.store(pattern, Ordering::SeqCst);
        self.version.fetch_add(1, Ordering::SeqCst);
    }

    fn load(&self) -> Option<Params> {
        let version = self.version.load(Ordering::SeqCst);
        if version & 1 != 0 {
            return None;
        }
        let bpm = f64::from_bits(self.bpm.load(Ordering::SeqCst));
        let volume = f32::from_bits(self.volume.load(Ordering::SeqCst));
        let pattern = self.pattern.load(Ordering::SeqCst);
        if version != self.version.load(Ordering::SeqCst) {
            return None;
        }
        Some(Params {
            bpm,
            volume,
            beats: (pattern & 0xff) as u32,
            denominator: ((pattern >> 8) & 0xff) as u32,
            subdivision: ((pattern >> 48) & 0xf) as u32,
            voices: std::array::from_fn(|i| ((pattern >> (16 + i * 2)) & 3) as u8),
        })
    }
}

// Control → output plane. Only the control thread publishes parameters.
struct Shared {
    params: AtomicParams,
    // Desired transport state includes requests not yet seen by the output.
    requested: AtomicBool,
    stop_acknowledged: AtomicBool,
    events: Sender<Ev>,
    // The device error callback can fire every buffer; one report is the truth.
    err_reported: AtomicBool,
    // Set by the control thread to end the silent clock.
    shutdown: AtomicBool,
}

impl Shared {
    fn params_snapshot(&self) -> Params {
        self.params
            .load()
            .expect("control thread is the sole parameter writer")
    }

    fn send(&self, ev: Ev) {
        let _ = self.events.send(ev);
    }
}

pub struct Handle {
    pub cmd_tx: Sender<proto::Command>,
    pub control: std::thread::JoinHandle<()>,
}

pub fn launch(initial: Params, silent_forced: bool) -> Handle {
    let (cmd_tx, cmd_rx) = std::sync::mpsc::channel();
    let control = std::thread::Builder::new()
        .name("pulse-control".into())
        .spawn(move || control_main(cmd_rx, initial, silent_forced))
        .expect("spawn control thread");
    Handle { cmd_tx, control }
}

fn control_main(cmd_rx: Receiver<proto::Command>, initial: Params, silent_forced: bool) {
    let (ev_tx, ev_rx) = std::sync::mpsc::channel::<Ev>();
    let shared = Arc::new(Shared {
        params: AtomicParams::new(&initial),
        requested: AtomicBool::new(false),
        stop_acknowledged: AtomicBool::new(true),
        events: ev_tx,
        err_reported: AtomicBool::new(false),
        shutdown: AtomicBool::new(false),
    });

    let mut audio = if silent_forced {
        None
    } else {
        audio::Output::open(&shared)
    };
    let mut clock = None;
    if audio.is_none() {
        if !silent_forced {
            let _ = proto::emit(&proto::ev::error("no usable audio output, running silent"));
        }
        // A nominal 48 kHz names the silent clock's frame grid; nothing hears it.
        clock = Some(clock::spawn(shared.clone(), 48_000.0));
    }

    // The device's own name and rate go out with ready; a silent clock says so.
    let (mut device, mut rate) = match &audio {
        Some(out) => (out.device_name.clone(), out.sample_rate),
        None => ("silent".to_string(), 48_000),
    };
    let _ = proto::emit(&proto::ev::state(&shared.params_snapshot()));
    let _ = proto::emit(&proto::ev::ready(&device, rate, audio.is_none()));

    // The out thread owns the event receiver and is the only other writer to
    // stdout; lines are whole because each write takes stdout's own lock.
    let out_thread = std::thread::Builder::new()
        .name("pulse-out".into())
        .spawn(move || {
            for ev in ev_rx {
                let line = match ev {
                    Ev::Beat { beat, kind } => proto::ev::beat(beat, kind.wire()),
                    Ev::Started => proto::ev::started(),
                    Ev::Stopped { beats } => proto::ev::stopped(beats),
                    Ev::Error(msg) => proto::ev::error(&msg),
                };
                let _ = proto::emit(&line);
            }
        })
        .expect("spawn out thread");

    loop {
        if audio.is_some() && shared.err_reported.load(Ordering::Acquire) {
            // Dropping the failed stream joins its callback before the silent
            // clock takes ownership. A new run starts from beat zero.
            drop(audio.take());
            device = "silent".into();
            rate = 48_000;
            let _ = proto::emit(&proto::ev::ready(&device, rate, true));
            clock = Some(clock::spawn(shared.clone(), rate as f64));
        }
        let cmd = match cmd_rx.recv_timeout(std::time::Duration::from_millis(20)) {
            Ok(cmd) => cmd,
            Err(std::sync::mpsc::RecvTimeoutError::Timeout) => continue,
            Err(std::sync::mpsc::RecvTimeoutError::Disconnected) => break,
        };
        match cmd {
            proto::Command::Hello => {
                let _ = proto::emit(&proto::ev::state(&shared.params_snapshot()));
                let _ = proto::emit(&proto::ev::ready(&device, rate, audio.is_none()));
            }
            proto::Command::Start => shared.requested.store(true, Ordering::Release),
            proto::Command::Stop => shared.requested.store(false, Ordering::Release),
            proto::Command::Toggle => {
                shared.requested.fetch_xor(true, Ordering::AcqRel);
            }
            proto::Command::Params(ref body) | proto::Command::Save(ref body) => {
                let mut params = shared.params_snapshot();
                match params.apply_patch(body) {
                    Err(e) => {
                        let _ = proto::emit(&proto::ev::error(&e));
                    }
                    Ok(()) => {
                        shared.params.store(&params);
                        if matches!(cmd, proto::Command::Save(_)) {
                            if let Err(e) = state::save(&params) {
                                let _ = proto::emit(&proto::ev::error(&format!(
                                    "the state was not saved ({})",
                                    e
                                )));
                            }
                        }
                    }
                }
            }
            proto::Command::Quit => break,
        }
    }

    // Drain: a stop at a click boundary, then wait for the output plane to
    // say it happened, so a quit never races the last beat line out the door.
    shared.requested.store(false, Ordering::Release);
    shared.stop_acknowledged.store(false, Ordering::Release);
    drain_stop(&shared);

    shared.shutdown.store(true, Ordering::Release);
    drop(audio); // closes the stream, which drops the callback's Shared arc
    drop(shared); // drops the last sender, so the out thread's loop ends
    let _ = clock.map(|h| h.join());
    let _ = out_thread.join();
    let _ = proto::emit(&proto::ev::quitready());
}

// Both outputs reconcile the same desired transport state.
fn update_transport(shared: &Shared, tl: &mut Timeline, frame: u64, sr: f64) {
    apply_transport(
        shared,
        tl,
        frame,
        sr,
        shared.requested.load(Ordering::Acquire),
    );
}

fn apply_transport(shared: &Shared, tl: &mut Timeline, frame: u64, sr: f64, requested: bool) {
    if requested != tl.armed {
        if requested {
            tl.arm(frame, 0.08, sr);
            shared.send(Ev::Started);
        } else {
            tl.disarm();
            shared.send(Ev::Stopped {
                beats: tl.total_beats,
            });
        }
    }
    // Acknowledge the observed request, not the control thread's current
    // desired state: a start already in flight must finish and then stop.
    shared
        .stop_acknowledged
        .store(!requested, Ordering::Release);
}

mod audio {
    use super::{update_transport, Ev, Shared, Timeline};
    use cpal::traits::{DeviceTrait, HostTrait, StreamTrait};
    use cpal::{FromSample, SizedSample};
    use std::sync::atomic::Ordering;
    use std::sync::Arc;

    pub struct Output {
        pub device_name: String,
        pub sample_rate: u32,
        _stream: cpal::Stream,
    }

    fn build<T: SizedSample + FromSample<f32>>(
        device: &cpal::Device,
        config: &cpal::StreamConfig,
        shared: &Arc<Shared>,
    ) -> Result<cpal::Stream, cpal::BuildStreamError> {
        let channels = config.channels as usize;
        let sr = config.sample_rate.0 as f64;
        let mut tl = Timeline::new();
        let mut frame = 0;
        let mut params = shared.params_snapshot();
        let callback_shared = shared.clone();
        let err_shared = shared.clone();
        device.build_output_stream(
            config,
            move |data: &mut [T], _| {
                let s = &callback_shared;
                update_transport(s, &mut tl, frame, sr);
                for samples in data.chunks_mut(channels) {
                    while tl.armed && frame as f64 >= tl.phase {
                        if let Some(latest) = s.params.load() {
                            params = latest;
                        }
                        s.send(tl.fire_click(&params, sr));
                    }
                    let value = T::from_sample(tl.sample(sr));
                    samples.fill(value);
                    frame += 1;
                }
            },
            move |err| {
                if !err_shared.err_reported.swap(true, Ordering::AcqRel) {
                    err_shared.send(Ev::Error(format!("the audio device failed ({})", err)));
                }
            },
            None,
        )
    }

    impl Output {
        pub fn open(shared: &Arc<Shared>) -> Option<Output> {
            let device = cpal::default_host().default_output_device()?;
            let name = device.name().unwrap_or_else(|_| "unknown".into());
            let default = device
                .default_output_config()
                .map_err(|err| {
                    eprintln!("pulse: no output configuration ({err})");
                })
                .ok()?;
            let format = default.sample_format();
            let mut config: cpal::StreamConfig = default.into();
            if config.channels == 0 || config.sample_rate.0 == 0 {
                return None;
            }
            // A finite list: a failed 48 kHz default must never retry forever.
            let mut rates = vec![48_000];
            if config.sample_rate.0 != 48_000 {
                rates.push(config.sample_rate.0);
            }
            for rate in rates {
                shared.err_reported.store(false, Ordering::Release);
                config.sample_rate = cpal::SampleRate(rate);
                let built = match format {
                    cpal::SampleFormat::I8 => build::<i8>(&device, &config, shared),
                    cpal::SampleFormat::I16 => build::<i16>(&device, &config, shared),
                    cpal::SampleFormat::I32 => build::<i32>(&device, &config, shared),
                    cpal::SampleFormat::I64 => build::<i64>(&device, &config, shared),
                    cpal::SampleFormat::U8 => build::<u8>(&device, &config, shared),
                    cpal::SampleFormat::U16 => build::<u16>(&device, &config, shared),
                    cpal::SampleFormat::U32 => build::<u32>(&device, &config, shared),
                    cpal::SampleFormat::U64 => build::<u64>(&device, &config, shared),
                    cpal::SampleFormat::F32 => build::<f32>(&device, &config, shared),
                    cpal::SampleFormat::F64 => build::<f64>(&device, &config, shared),
                    _ => return None,
                };
                match built {
                    Ok(stream) => match stream.play() {
                        Ok(()) => {
                            return Some(Output {
                                device_name: name,
                                sample_rate: rate,
                                _stream: stream,
                            })
                        }
                        Err(err) => eprintln!("pulse: output would not start at {rate} Hz ({err})"),
                    },
                    Err(err) => eprintln!("pulse: output could not be built at {rate} Hz ({err})"),
                }
            }
            None
        }
    }
}

mod clock {
    use super::{update_transport, Params, Shared, Timeline};
    use std::sync::atomic::Ordering;
    use std::sync::Arc;
    use std::time::{Duration, Instant};

    pub fn spawn(shared: Arc<Shared>, sr: f64) -> std::thread::JoinHandle<()> {
        std::thread::Builder::new()
            .name("pulse-clock".into())
            .spawn(move || {
                let mut tl = Timeline::new();
                let mut events = Vec::new();
                let anchor = Instant::now();
                let mut params = Params::default();
                while !shared.shutdown.load(Ordering::Acquire) {
                    let frame = (anchor.elapsed().as_secs_f64() * sr) as u64;
                    update_transport(&shared, &mut tl, frame, sr);
                    events.clear();
                    if let Some(latest) = shared.params.load() {
                        params = latest;
                    }
                    tl.advance_events_to(frame, &params, sr, &mut events);
                    for ev in events.drain(..) {
                        shared.send(ev);
                    }
                    // Silent playback needs no CPU-burning spin wait.
                    let wait = if tl.armed {
                        Duration::from_secs_f64(((tl.phase - frame as f64) / sr).max(0.0))
                            .min(Duration::from_millis(2))
                    } else {
                        Duration::from_millis(2)
                    };
                    std::thread::sleep(wait);
                }
            })
            .expect("spawn silent clock")
    }
}

// Stop has to be observable: the control thread waits for the output plane to
// acknowledge the stop request before teardown, with a generous cap so
// a wedged device cannot hang the quit.
fn drain_stop(shared: &Arc<Shared>) {
    let deadline = std::time::Instant::now() + std::time::Duration::from_secs(1);
    while !shared.stop_acknowledged.load(Ordering::Acquire) {
        if std::time::Instant::now() > deadline {
            return;
        }
        std::thread::sleep(std::time::Duration::from_millis(2));
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    const SR: f64 = 48_000.0;

    fn params(bpm: f64, beats: u32, denominator: u32) -> Params {
        Params {
            bpm,
            beats,
            denominator,
            volume: 1.0,
            ..Params::default()
        }
    }

    #[test]
    fn published_parameters_are_coherent_under_contention() {
        let first = Params::default();
        let second = Params {
            bpm: 397.125,
            beats: BEATS_MAX,
            denominator: 8,
            volume: 0.1234,
            subdivision: 3,
            voices: [2; BEATS_MAX as usize],
        };
        let shared = Arc::new(AtomicParams::new(&first));
        let writer = shared.clone();
        let expected = second.clone();
        let thread = std::thread::spawn(move || {
            for _ in 0..10_000 {
                writer.store(&expected);
                writer.store(&Params::default());
            }
        });
        for _ in 0..10_000 {
            if let Some(p) = shared.load() {
                assert!(p == first || p == second);
            }
        }
        thread.join().unwrap();
        assert_eq!(shared.load(), Some(first));
    }

    #[test]
    fn the_widest_meter_survives_the_atomic_round_trip() {
        // 16 needs five bits; a four-bit field would read it back as 0 and
        // the callback would divide by it.
        let mut p = params(120.0, BEATS_MAX, 8);
        p.voices = std::array::from_fn(|i| (i % 4) as u8);
        let shared = AtomicParams::new(&p);
        assert_eq!(shared.load(), Some(p.clone()));
        let mut tl = Timeline::new();
        tl.arm(0, 0.0, SR);
        let mut events = Vec::new();
        let mut buf = vec![0.0f32; SR as usize * 5];
        tl.mix_into(&mut buf, 1, 0, &shared.load().unwrap(), SR, &mut events);
        // 5 s at 120 on the eighth is 20 ticks: one full 16-bar and four more.
        assert_eq!(events.len(), 20);
        for (i, ev) in events.iter().enumerate() {
            let beat = (i % BEATS_MAX as usize) as u32;
            assert_eq!(
                *ev,
                Ev::Beat {
                    beat,
                    kind: kind_for(beat, &p)
                }
            );
        }
        assert_eq!(tl.beat, 4);
    }

    #[test]
    fn transport_honors_pending_toggles_and_idempotent_start() {
        let (events, rx) = std::sync::mpsc::channel();
        let shared = Shared {
            params: AtomicParams::new(&Params::default()),
            requested: AtomicBool::new(false),
            stop_acknowledged: AtomicBool::new(true),
            events,
            err_reported: AtomicBool::new(false),
            shutdown: AtomicBool::new(false),
        };
        let mut tl = Timeline::new();
        shared.requested.fetch_xor(true, Ordering::AcqRel);
        shared.requested.fetch_xor(true, Ordering::AcqRel);
        update_transport(&shared, &mut tl, 0, SR);
        assert!(!tl.armed);
        assert!(rx.try_recv().is_err());
        shared.requested.store(true, Ordering::Release);
        update_transport(&shared, &mut tl, 0, SR);
        assert_eq!(rx.try_recv().unwrap(), Ev::Started);
        let phase = tl.phase;
        update_transport(&shared, &mut tl, 500, SR);
        assert_eq!(tl.phase, phase);
        assert!(rx.try_recv().is_err());
        shared.requested.store(false, Ordering::Release);
        update_transport(&shared, &mut tl, 600, SR);
        assert_eq!(rx.try_recv().unwrap(), Ev::Stopped { beats: 0 });
        assert!(!tl.armed);

        // Output captured start, then control requested shutdown before the
        // output could mark itself running. It must not acknowledge stop yet.
        shared.stop_acknowledged.store(false, Ordering::Release);
        apply_transport(&shared, &mut tl, 700, SR, true);
        assert!(!shared.stop_acknowledged.load(Ordering::Acquire));
        assert_eq!(rx.try_recv().unwrap(), Ev::Started);
        update_transport(&shared, &mut tl, 800, SR);
        assert!(shared.stop_acknowledged.load(Ordering::Acquire));
        assert_eq!(rx.try_recv().unwrap(), Ev::Stopped { beats: 0 });
    }

    #[test]
    fn every_meter_and_voice_renders_at_tempo_extremes() {
        for sr in [44_100.0, 48_000.0] {
            for bpm in [10.0, 113.0, 400.0] {
                for denominator in DENOMINATORS {
                    for beats in 1..=BEATS_MAX {
                        for voice in 0..=VOICE_HIGH {
                            let mut p = params(bpm, beats, denominator);
                            p.voices = [voice; BEATS_MAX as usize];
                            let mut tl = Timeline::new();
                            tl.arm(0, 0.0, sr);
                            let mut events = Vec::new();
                            for beat in 0..beats * 2 {
                                let from = tl.phase.ceil() as u64;
                                let mut samples = vec![0.0; (sr * 0.071) as usize * 2];
                                events.clear();
                                tl.mix_into(&mut samples, 2, from, &p, sr, &mut events);
                                assert_eq!(
                                    events,
                                    vec![Ev::Beat {
                                        beat: beat % beats,
                                        kind: kind_for(beat % beats, &p)
                                    }]
                                );
                                assert!(samples.as_chunks::<2>().0.iter().all(|s| s[0] == s[1]));
                                let peak = samples.iter().map(|s| s.abs()).fold(0.0f32, f32::max);
                                if voice == 0 {
                                    assert!(peak <= FLOOR_AMP, "a muted beat is floor alone");
                                } else {
                                    assert!(peak > 0.5 && peak <= 1.0);
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    #[test]
    fn shrinking_meter_wraps_before_selecting_voice() {
        let mut p = params(120.0, 12, 4);
        let mut tl = Timeline::new();
        tl.arm(0, 0.0, SR);
        let mut events = Vec::new();
        tl.advance_events_to(10 * 24_000, &p, SR, &mut events);
        p.beats = 3;
        events.clear();
        tl.advance_events_to(11 * 24_000, &p, SR, &mut events);
        assert_eq!(
            events,
            vec![Ev::Beat {
                beat: 2,
                kind: Kind::Low
            }]
        );
    }

    #[test]
    fn gain_is_held_for_the_entire_click() {
        let mut p = params(120.0, 4, 4);
        let mut tl = Timeline::new();
        tl.arm(0, 0.0, SR);
        let mut events = Vec::new();
        tl.mix_into(&mut [0.0; 64], 1, 0, &p, SR, &mut events);
        p.volume = 0.0;
        let mut tail = [0.0; 64];
        tl.mix_into(&mut tail, 1, 64, &p, SR, &mut events);
        assert!(tail.iter().any(|x| x.abs() > 0.1));
        let mut next = vec![0.0; 24_000];
        tl.mix_into(&mut next, 1, 128, &p, SR, &mut events);
        assert!(next[24_000 - 128..].iter().all(|x| x.abs() <= FLOOR_AMP));
    }

    #[test]
    fn invalid_patch_does_not_change_any_setting() {
        let mut p = Params::default();
        let original = p.clone();
        assert!(p
            .apply_patch(&Json::parse(r#"{"bpm":200,"denominator":3}"#).unwrap())
            .is_err());
        assert_eq!(p, original);
    }

    #[test]
    fn state_requires_an_object_and_at_most_sixteen_voices() {
        let mut p = Params::default();
        assert!(p.apply_patch(&Json::Null).is_err());
        // A pre-16 state file carries twelve slots; it still loads, and the
        // four it never knew keep their defaults.
        let twelve = Json::obj(vec![("voices", Json::Arr(vec![Json::int(2); 12]))]);
        p.apply_patch(&twelve).unwrap();
        assert_eq!(&p.voices[..12], &[2; 12]);
        assert_eq!(&p.voices[12..], &[VOICE_LOW; 4]);
        let sixteen = Json::obj(vec![("voices", Json::Arr(vec![Json::int(3); 16]))]);
        p.apply_patch(&sixteen).unwrap();
        assert_eq!(p.voices, [3; 16]);
        assert!(p
            .apply_patch(&Json::obj(vec![(
                "voices",
                Json::Arr(vec![Json::int(1); 17])
            )]))
            .is_err());
    }

    #[test]
    fn interval_follows_the_signature_bottom() {
        // x/4 ticks on the quarter, x/8 on the eighth, x/1 on the whole note.
        assert_eq!(interval_frames(120.0, 4, SR), 24_000.0);
        assert_eq!(interval_frames(120.0, 8, SR), 12_000.0);
        assert_eq!(interval_frames(120.0, 2, SR), 48_000.0);
        assert_eq!(interval_frames(60.0, 1, SR), 192_000.0);
    }

    #[test]
    fn kinds_follow_the_pattern() {
        let p = params(120.0, 4, 4);
        assert_eq!(kind_for(0, &p), Kind::High);
        assert_eq!(kind_for(1, &p), Kind::Low);
        assert_eq!(kind_for(3, &p), Kind::Low);

        let mut p = params(120.0, 4, 4);
        p.voices[1] = VOICE_MEDIUM;
        assert_eq!(kind_for(1, &p), Kind::Medium);

        p.voices[0] = 0; // silent
        assert_eq!(kind_for(0, &p), Kind::Off);
    }

    #[test]
    fn a_bar_walks_high_then_low() {
        let p = params(120.0, 4, 4);
        let mut tl = Timeline::new();
        tl.arm(0, 0.0, SR);
        let mut events = Vec::new();
        tl.advance_events_to(95_999, &p, SR, &mut events);
        assert_eq!(events.len(), 4);
        assert_eq!(
            events[0],
            Ev::Beat {
                beat: 0,
                kind: Kind::High
            }
        );
        assert_eq!(
            events[1],
            Ev::Beat {
                beat: 1,
                kind: Kind::Low
            }
        );
        assert_eq!(
            events[3],
            Ev::Beat {
                beat: 3,
                kind: Kind::Low
            }
        );
        assert_eq!(tl.total_beats, 4);
    }

    #[test]
    fn an_eighth_signature_ticks_twice_as_fast() {
        let p = params(120.0, 4, 8);
        let mut tl = Timeline::new();
        tl.arm(0, 0.0, SR);
        let mut events = Vec::new();
        tl.advance_events_to(12_000, &p, SR, &mut events);
        assert_eq!(events.len(), 2);
        assert_eq!(
            events[0],
            Ev::Beat {
                beat: 0,
                kind: Kind::High
            }
        );
        assert_eq!(
            events[1],
            Ev::Beat {
                beat: 1,
                kind: Kind::Low
            }
        );
        assert_eq!(tl.total_beats, 2);
    }

    #[test]
    fn a_bpm_change_lands_at_the_next_click() {
        let p = params(120.0, 4, 4);
        let mut tl = Timeline::new();
        tl.arm(0, 0.0, SR);
        let mut events = Vec::new();
        tl.advance_events_to(1, &p, SR, &mut events); // first click armed at frame 0
        assert_eq!(events.len(), 1);
        assert_eq!(tl.phase, 24_000.0);

        let faster = params(240.0, 4, 4);
        tl.advance_events_to(23_999, &faster, SR, &mut events);
        assert_eq!(events.len(), 1, "no click before its own boundary");
        tl.advance_events_to(24_000, &faster, SR, &mut events);
        assert_eq!(events.len(), 2);
        // The new interval starts from the click that carried the change.
        assert_eq!(tl.phase, 24_000.0 + 12_000.0);
    }

    #[test]
    fn a_long_click_survives_across_buffers() {
        let p = params(120.0, 4, 4);
        let mut tl = Timeline::new();
        tl.arm(0, 0.0, SR);
        let mut events = Vec::new();
        // A 64-frame buffer, the size a realtime device actually hands over.
        let mut buf = vec![0.0f32; 64 * 2];
        tl.mix_into(&mut buf, 2, 0, &p, SR, &mut events);
        assert_eq!(events.len(), 1);
        assert!(
            buf.iter().any(|s| s.abs() > FLOOR_AMP),
            "the high click is in the first buffer (its own sample 0 is still attack-silent)"
        );
        let mut peak = 0.0f32;
        for chunk in 1..10usize {
            events.clear();
            tl.mix_into(&mut buf, 2, chunk as u64 * 64, &p, SR, &mut events);
            for s in buf.iter().step_by(2) {
                peak = peak.max(s.abs());
            }
        }
        // The click is 70 ms = 3360 samples; 10 buffers of 64 only reach 640.
        assert!(peak > FLOOR_AMP, "the click continues into later buffers");
    }

    #[test]
    fn silence_after_disarm() {
        let p = params(120.0, 4, 4);
        let mut tl = Timeline::new();
        tl.arm(0, 0.0, SR);
        let mut events = Vec::new();
        tl.disarm();
        let mut buf = vec![0.0f32; 4800];
        tl.mix_into(&mut buf, 1, 0, &p, SR, &mut events);
        assert!(events.is_empty());
        assert!(buf.iter().all(|s| s.abs() <= FLOOR_AMP), "no click after disarm");
        assert!(buf.iter().any(|s| *s != 0.0), "the floor still runs after disarm");
    }

    #[test]
    fn the_link_never_hears_digital_silence() {
        // The reported pattern: nothing on one and three, a low tick on two
        // and four at 110, so the ticks stand over a second apart. Every
        // 10 ms window between them carries the floor and nothing louder.
        let mut p = params(110.0, 4, 4);
        p.voices = [0, 1, 0, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1];
        let mut tl = Timeline::new();
        tl.arm(0, 0.08, SR);
        let mut buf = vec![0.0f32; 8 * SR as usize];
        let mut events = Vec::new();
        tl.mix_into(&mut buf, 1, 0, &p, SR, &mut events);
        let window = SR as usize / 100;
        let mut quiet = 0;
        for chunk in buf.chunks(window) {
            let peak = chunk.iter().map(|s| s.abs()).fold(0.0f32, f32::max);
            assert!(peak > 0.0, "a window of digital silence");
            if peak <= FLOOR_AMP {
                quiet += 1;
            }
        }
        // Eight seconds hold about seven low ticks of 55 ms: nearly every
        // window is floor alone, and the floor is what keeps the link awake.
        assert!(quiet > 700, "only {} floor-only windows", quiet);
        // The floor is a floor: nothing in it reaches -70 dBFS.
        assert!(buf.iter().all(|s| s.abs() <= 1.0), "sane samples");
        let floor_peak = buf[..(0.07 * SR) as usize]
            .iter()
            .map(|s| s.abs())
            .fold(0.0f32, f32::max);
        assert!(floor_peak <= FLOOR_AMP && floor_peak > FLOOR_AMP * 0.5);
    }

    #[test]
    fn clamps_catch_every_wire_value() {
        let mut p = Params::default();
        let body = Json::parse(r#"{"voices":[0,9]}"#).unwrap();
        // 9 is not a voice: the patch refuses rather than clamps.
        assert!(p.apply_patch(&body).is_err());

        let body = Json::parse(r#"{"denominator":3}"#).unwrap();
        // 3 is not a denominator either: triplet signs left with the old
        // subdivision ladder, and the wire refuses what the editor cannot
        // produce.
        assert!(p.apply_patch(&body).is_err());

        let body = Json::parse(r#"{"bpm":100000,"beats":0,"volume":5}"#).unwrap();
        p.apply_patch(&body).unwrap();
        assert_eq!(p.bpm, BPM_MAX);
        assert_eq!(p.beats, BEATS_MIN);
        assert_eq!(p.volume, 1.0);
        assert_eq!(p.denominator, 4, "an absent denominator keeps its value");
    }

    #[test]
    fn a_legacy_subdiv_maps_onto_the_signature() {
        let mut p = Params::default();
        p.apply_patch(&Json::parse(r#"{"subdiv":1}"#).unwrap())
            .unwrap();
        assert_eq!(p.denominator, 4);
        p.apply_patch(&Json::parse(r#"{"subdiv":2}"#).unwrap())
            .unwrap();
        assert_eq!(p.denominator, 8);
        // Triplet signs had no bottom number to call home; they land on 8.
        p.apply_patch(&Json::parse(r#"{"subdiv":3}"#).unwrap())
            .unwrap();
        assert_eq!(p.denominator, 8);
        p.apply_patch(&Json::parse(r#"{"subdiv":4}"#).unwrap())
            .unwrap();
        assert_eq!(p.denominator, 8);
        // An explicit denominator wins over the legacy key in one body.
        let body = Json::parse(r#"{"subdiv":2,"denominator":1}"#).unwrap();
        p.apply_patch(&body).unwrap();
        assert_eq!(p.denominator, 1);
    }

    #[test]
    fn voices_patch_updates_the_pattern() {
        let mut p = Params::default();
        let body = Json::parse(r#"{"voices":[3,0,2]}"#).unwrap();
        p.apply_patch(&body).unwrap();
        assert_eq!(p.voices[0], VOICE_HIGH);
        assert_eq!(p.voices[1], 0); // silent
        assert_eq!(p.voices[2], VOICE_MEDIUM);
        // A short array leaves the tail as it was.
        assert_eq!(p.voices[3], VOICE_LOW);
    }

    #[test]
    fn a_muted_beat_walks_the_timeline_without_sound() {
        let mut p = params(120.0, 4, 4);
        p.voices[1] = 0; // silent
        let mut tl = Timeline::new();
        tl.arm(0, 0.0, SR);
        let mut events = Vec::new();
        tl.advance_events_to(24_000, &p, SR, &mut events);
        assert_eq!(events.len(), 2);
        assert_eq!(
            events[0],
            Ev::Beat {
                beat: 0,
                kind: Kind::High
            }
        );
        assert_eq!(
            events[1],
            Ev::Beat {
                beat: 1,
                kind: Kind::Off
            }
        );
        assert_eq!(tl.total_beats, 2);

        // Nothing at all is on: every position walks, not one sample sounds.
        let mut p = params(120.0, 4, 4);
        p.voices = [0; BEATS_MAX as usize]; // all silent
        let mut tl = Timeline::new();
        tl.arm(0, 0.0, SR);
        let mut buf = vec![0.0f32; 96_000];
        let mut events = Vec::new();
        tl.mix_into(&mut buf, 1, 0, &p, SR, &mut events);
        assert_eq!(events.len(), 4, "the timeline still walks every beat");
        assert!(
            buf.iter().all(|s| s.abs() <= FLOOR_AMP),
            "not one click sounds, only the floor"
        );
        assert_eq!(
            events[0],
            Ev::Beat {
                beat: 0,
                kind: Kind::Off
            }
        );
    }

    #[test]
    fn patch_leaves_absent_keys_alone() {
        let mut p = params(95.0, 3, 4);
        let body = Json::parse(r#"{"bpm":140}"#).unwrap();
        p.apply_patch(&body).unwrap();
        assert_eq!(p.bpm, 140.0);
        assert_eq!(p.beats, 3);
        assert_eq!(p.denominator, 4);
        assert_eq!(p.voices[0], VOICE_HIGH);
    }

    // Every voice must render its own tone on 4/4: silent stays silent, and
    // low/medium/high each correlate strongest with their own frequency.
    // Guards the "wrong tone / missing tone" report at the shared Timeline
    // core both outputs play through.
    #[test]
    fn each_voice_renders_its_own_tone() {
        fn goertzel(seg: &[f32], sr: f64, freq: f64) -> f64 {
            let n = seg.len() as f64;
            let k = (0.5 + freq * n / sr).floor();
            let w = 2.0 * std::f64::consts::PI * k / n;
            let (mut s1, mut s2) = (0.0f64, 0.0f64);
            for &x in seg {
                let s0 = x as f64 + 2.0 * w.cos() * s1 - s2;
                s2 = s1;
                s1 = s0;
            }
            (s1 * s1 + s2 * s2 - s1 * s2 * 2.0 * w.cos()).sqrt()
        }
        // voice value, expected kind, expected dominant freq (0 = silence)
        for (voice, kind, freq) in [
            (0u8, Kind::Off, 0.0),
            (1u8, Kind::Low, 1100.0),
            (2u8, Kind::Medium, 1400.0),
            (3u8, Kind::High, 1800.0),
        ] {
            let mut p = params(120.0, 4, 4);
            p.voices = [voice; BEATS_MAX as usize];
            let mut tl = Timeline::new();
            tl.arm(0, 0.0, SR);
            let mut out = vec![0.0f32; 48_000];
            let mut events = Vec::new();
            for from in (0..48_000).step_by(512) {
                let end = (from + 512).min(48_000);
                let mut ev = Vec::new();
                tl.mix_into(&mut out[from..end], 1, from as u64, &p, SR, &mut ev);
                events.extend(ev);
            }
            assert_eq!(
                events,
                vec![Ev::Beat { beat: 0, kind }, Ev::Beat { beat: 1, kind },],
                "voice {} must fire two {} beats in one second at 120bpm 4/4",
                voice,
                kind.wire()
            );
            let seg = &out[0..4000];
            let peak = seg.iter().map(|s| s.abs()).fold(0.0f32, f32::max);
            if freq == 0.0 {
                assert!(peak <= FLOOR_AMP, "silent voice must render only the floor");
            } else {
                assert!(
                    peak > 0.5,
                    "voice {} must be audible (peak {})",
                    voice,
                    peak
                );
                let g = [1100.0, 1400.0, 1800.0].map(|f| goertzel(seg, SR, f));
                let best = [1100.0, 1400.0, 1800.0][g
                    .iter()
                    .enumerate()
                    .max_by(|a, b| a.1.partial_cmp(b.1).unwrap())
                    .unwrap()
                    .0];
                assert_eq!(
                    best, freq,
                    "voice {} must sound {}Hz, not {:?}",
                    voice, freq, g
                );
            }
        }
    }

    // The reported pattern (2nd and 4th audible, 1st and 3rd muted) must
    // survive every buffer shape and phase offset the device can hand over:
    // audible clicks render their peak, muted windows render exact silence.
    #[test]
    fn audible_and_muted_beats_survive_every_buffer_shape() {
        let sr = 44_100.0;
        let mut p = params(113.0, 4, 4);
        p.voices = [0, 1, 0, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1];
        let total = 15 * 44_100usize;
        for (buf, start, lead) in [
            (64u64, 0u64, 0.0),
            (256, 0, 0.0),
            (512, 0, 0.0),
            (1881, 0, 0.08),
            (1882, 0, 0.08),
            (1882, 98_490, 0.08), // arm mid-history, as the live callback does
            (4096, 0, 0.08),
            (997, 1111, 0.08),
        ] {
            let mut tl = Timeline::new();
            tl.arm(start, lead, sr);
            let mut out = vec![0.0f32; start as usize + total];
            let mut fired = Vec::new();
            let mut from = start;
            while from < start + total as u64 {
                let end = (from + buf).min(start + total as u64);
                let mut ev = Vec::new();
                tl.mix_into(
                    &mut out[from as usize..end as usize],
                    1,
                    from,
                    &p,
                    sr,
                    &mut ev,
                );
                fired.extend(ev);
                from = end;
            }
            // Events: beats cycle 0,1,2,3 — muted, low, muted, low.
            for (i, ev) in fired.iter().enumerate() {
                let want = if i % 4 % 2 == 0 {
                    Ev::Beat {
                        beat: (i % 4) as u32,
                        kind: Kind::Off,
                    }
                } else {
                    Ev::Beat {
                        beat: (i % 4) as u32,
                        kind: Kind::Low,
                    }
                };
                assert_eq!(*ev, want, "buf={} start={}: event {} wrong", buf, start, i);
            }
            assert!(
                fired.len() >= 26,
                "buf={} start={}: only {} clicks in 15s",
                buf,
                start,
                fired.len()
            );
            // Click frames: first at start+lead*sr, then +interval each.
            let first = start as f64 + lead * sr;
            let interval = 240.0 / (p.bpm * p.denominator as f64) * sr;
            let mut f = first;
            let mut beat = 0u32;
            let mut audible = 0;
            while (f as usize) + 4000 <= out.len() {
                let i = f as usize;
                let peak = out[i..i + 4000]
                    .iter()
                    .map(|s| s.abs())
                    .fold(0.0f32, f32::max);
                if beat & 1 == 0 {
                    assert!(
                        peak <= FLOOR_AMP,
                        "buf={} start={}: muted beat at frame {} sounded (peak {})",
                        buf,
                        start,
                        i,
                        peak
                    );
                } else {
                    assert!(
                        peak > 0.3,
                        "buf={} start={}: audible beat at frame {} is silent (peak {})",
                        buf,
                        start,
                        i,
                        peak
                    );
                    audible += 1;
                }
                beat = (beat + 1) % 4;
                f += interval;
            }
            assert!(
                audible >= 13,
                "buf={} start={}: only {} audible windows",
                buf,
                start,
                audible
            );
        }
    }

    #[test]
    fn a_subdivision_ticks_between_the_beats() {
        // 120 bpm 4/4 in halves: eight ticks a bar, a beat then a sub, the
        // beat counter moving only on the beat, each tick half an interval.
        let mut p = params(120.0, 4, 4);
        p.subdivision = 2;
        let mut tl = Timeline::new();
        tl.arm(0, 0.0, SR);
        let mut events = Vec::new();
        tl.advance_events_to(SR as u64 - 1, &p, SR, &mut events);
        let kinds: Vec<_> = events.iter().map(|e| match e {
            Ev::Beat { beat, kind } => (*beat, *kind),
            _ => unreachable!(),
        }).collect();
        assert_eq!(
            kinds,
            vec![(0, Kind::High), (0, Kind::Sub), (1, Kind::Low), (1, Kind::Sub)]
        );
        assert_eq!(tl.total_beats, 2, "sub-ticks are not beats");
        let half = interval_frames(120.0, 4, SR) / 2.0;
        assert!((tl.phase - 4.0 * half).abs() < 1e-6);

        // Triplets on a muted beat stay muted; the next beat's are heard.
        let mut p = params(120.0, 2, 4);
        p.subdivision = 3;
        p.voices[0] = 0;
        let mut tl = Timeline::new();
        tl.arm(0, 0.0, SR);
        let mut events = Vec::new();
        tl.advance_events_to(SR as u64 - 1, &p, SR, &mut events);
        let kinds: Vec<_> = events.iter().map(|e| match e {
            Ev::Beat { kind, .. } => *kind,
            _ => unreachable!(),
        }).collect();
        assert_eq!(
            kinds,
            vec![Kind::Off, Kind::Off, Kind::Off, Kind::Low, Kind::Sub, Kind::Sub]
        );

        // The sub voice sounds, and under every beat voice.
        let sub = click_spec(Kind::Sub);
        assert!(sub.amp > 0.0 && sub.amp < click_spec(Kind::Low).amp);
    }

    #[test]
    fn subdivision_rides_the_wire_and_the_atomics() {
        let mut p = Params::default();
        p.apply_patch(&Json::parse(r#"{"subdivision":3}"#).unwrap()).unwrap();
        assert_eq!(p.subdivision, 3);
        assert!(p.apply_patch(&Json::parse(r#"{"subdivision":5}"#).unwrap()).is_err());
        assert!(p.apply_patch(&Json::parse(r#"{"subdivision":0}"#).unwrap()).is_err());
        assert!(p.apply_patch(&Json::parse(r#"{"subdivision":"two"}"#).unwrap()).is_err());
        assert_eq!(p.subdivision, 3, "a refused patch changes nothing");
        let rendered = p.to_json().render();
        assert!(rendered.contains("\"subdivision\":3"), "{}", rendered);
        // The state line carries it, so the shell learns it at startup.
        let state = Json::parse(&proto::ev::state(&p)).unwrap();
        assert_eq!(state.get("subdivision").unwrap().as_u32(), Some(3));
        // A subdivision from a state file outside the range is forgiven.
        let mut q = Params::default();
        q.subdivision = 9;
        q.clamp();
        assert_eq!(q.subdivision, SUBDIVISION_MAX);
        for s in SUBDIVISION_MIN..=SUBDIVISION_MAX {
            p.subdivision = s;
            let atomics = AtomicParams::new(&p);
            assert_eq!(atomics.load().unwrap(), p);
        }
    }
}
