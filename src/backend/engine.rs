use crate::json::Json;
use std::sync::atomic::{AtomicBool, AtomicU8, AtomicU64, Ordering};
use std::sync::mpsc::{Receiver, Sender};
use std::sync::{Arc, Mutex};

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
    // Per-beat voice, one entry per beat position, BEATS_MAX long: 0 silent,
    // 1 low tone, 2 medium tone, 3 high tone. Positions past `beats` are
    // remembered, so a pattern survives a temporary change of meter.
    pub voices: [u8; BEATS_MAX as usize],
}

pub const VOICE_OFF: u8 = 0;
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
pub const BEATS_MAX: u32 = 12;

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
            (
                "voices",
                Json::Arr(self.voices.iter().map(|v| Json::int(*v as i64)).collect()),
            ),
        ])
    }

    // Only the keys present are a patch; everything else keeps its value.
    pub fn apply_patch(&mut self, body: &Json) -> Result<(), String> {
        if let Some(v) = body.get("bpm") {
            self.bpm = v
                .as_f64()
                .ok_or_else(|| "bpm must be a number".to_string())?;
        }
        if let Some(v) = body.get("beats") {
            self.beats = v.as_u32().ok_or_else(|| "beats must be a whole number".to_string())?;
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
            let s = v.as_u32().ok_or_else(|| "subdiv must be a whole number".to_string())?;
            self.denominator = match s {
                1 => 4,
                _ => 8,
            };
        }
        if let Some(v) = body.get("volume") {
            self.volume = v
                .as_f64()
                .ok_or_else(|| "volume must be a number".to_string())? as f32;
        }
        if let Some(v) = body.get("voices") {
            let items = match v {
                Json::Arr(items) => items,
                _ => return Err("voices must be an array".to_string()),
            };
            // A short array pads with low tones; an entry that is not 0..3 is
            // refused, not clamped, so a sloppy client learns the wire.
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
    // A beat the user muted: the timeline walks it, no click sounds.
    Off,
}

impl Kind {
    pub fn wire(&self) -> &'static str {
        match self {
            Kind::High => "high",
            Kind::Medium => "medium",
            Kind::Low => "low",
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
        Kind::High => ClickSpec { freq: 1800.0, amp: 1.0, dur: 0.07, tau: 0.018 },
        Kind::Medium => ClickSpec { freq: 1400.0, amp: 0.85, dur: 0.06, tau: 0.015 },
        Kind::Low => ClickSpec { freq: 1100.0, amp: 0.7, dur: 0.055, tau: 0.012 },
        // Nothing sounds on a muted beat; the spec is never sampled because
        // fire_click sets the click length to zero.
        Kind::Off => ClickSpec { freq: 0.0, amp: 0.0, dur: 0.0, tau: 1.0 },
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
    total_beats: u64,
    click_pos: usize,
    click_len: usize,
    spec: ClickSpec,
}

impl Timeline {
    fn new() -> Self {
        Timeline {
            armed: false,
            phase: 0.0,
            beat: 0,
            total_beats: 0,
            click_pos: 0,
            click_len: 0,
            spec: click_spec(Kind::Low),
        }
    }

    // Start the bar `lead` seconds from `at`; the lead keeps the first click
    // clear of the priming the device does after play().
    fn arm(&mut self, at: u64, lead: f64, sr: f64) {
        self.armed = true;
        self.phase = at as f64 + lead * sr;
        self.beat = 0;
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
    // move the counters on, and step phase one interval. Params are read per
    // click, so a bpm or signature change lands at the next boundary, which is
    // where a musician expects it.
    fn fire_click(&mut self, params: &Params, sr: f64) -> Ev {
        let kind = kind_for(self.beat, params);
        self.spec = click_spec(kind);
        // A muted beat walks the timeline but samples no click.
        self.click_len = if kind == Kind::Off { 0 } else { click_len(&self.spec, sr) };
        self.click_pos = 0;
        let ev = Ev::Beat {
            beat: self.beat,
            kind,
        };
        self.total_beats += 1;
        self.beat = (self.beat + 1) % params.beats;
        self.phase += interval_frames(params.bpm, params.denominator, sr);
        ev
    }

    // One buffer's worth: fire every due click, then fill with silence or the
    // running click. `from` is the buffer's first absolute frame.
    fn mix_into(
        &mut self,
        out: &mut [f32],
        channels: usize,
        from: u64,
        params: &Params,
        sr: f64,
        events: &mut Vec<Ev>,
    ) {
        let mut gain = params.volume;
        for (i, frame) in out.chunks_mut(channels).enumerate() {
            let abs = from + i as u64;
            while self.armed && abs as f64 >= self.phase {
                let ev = self.fire_click(params, sr);
                gain = params.volume;
                events.push(ev);
            }
            let s = if self.click_pos < self.click_len {
                let s = click_sample(&self.spec, self.click_pos, sr) * gain;
                self.click_pos += 1;
                s
            } else {
                0.0
            };
            for sample in frame.iter_mut() {
                *sample = s;
            }
        }
    }

    // The silent clock's shape of the same loop: no samples, only the due
    // clicks up to `until`, exclusive.
    fn advance_events_to(&mut self, until: u64, params: &Params, sr: f64, events: &mut Vec<Ev>) {
        while self.armed && until as f64 >= self.phase {
            events.push(self.fire_click(params, sr));
        }
    }
}

// Control → output plane. The atomics are what a realtime callback may read
// without ever locking; the params mutex is taken only at a click boundary.
struct Shared {
    params: Mutex<Params>,
    // 0 = nothing, 1 = start requested, 2 = stop requested. The output plane
    // clears it, so a request can never be lost between threads.
    pending: AtomicU8,
    running: AtomicBool,
    events: Sender<Ev>,
    // A virtual frame position the silent clock publishes, so a stop never
    // waits on a poll interval that outlived its purpose.
    frame: AtomicU64,
    // The device error callback can fire every buffer; one report is the truth.
    err_reported: AtomicBool,
    // Set by the control thread to end the silent clock.
    shutdown: AtomicBool,
}

impl Shared {
    fn params_snapshot(&self) -> Params {
        self.params.lock().unwrap().clone()
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
        params: Mutex::new(initial),
        pending: AtomicU8::new(0),
        running: AtomicBool::new(false),
        events: ev_tx,
        frame: AtomicU64::new(0),
        err_reported: AtomicBool::new(false),
        shutdown: AtomicBool::new(false),
    });

    let audio = if silent_forced { None } else { audio::Output::open(&shared) };
    let mut clock = None;
    if audio.is_none() {
        if !silent_forced {
            let _ = proto::emit(&proto::ev::error("no usable audio output, running silent"));
        }
        // A nominal 48 kHz names the silent clock's frame grid; nothing hears it.
        clock = Some(clock::spawn(shared.clone(), 48_000.0));
    }

    // The device's own name and rate go out with ready; a silent clock says so.
    let (device, rate) = match &audio {
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

    while let Ok(cmd) = cmd_rx.recv() {
        match cmd {
            proto::Command::Hello => {
                let _ = proto::emit(&proto::ev::state(&shared.params_snapshot()));
                let _ = proto::emit(&proto::ev::ready(&device, rate, audio.is_none()));
            }
            proto::Command::Start => shared.pending.store(1, Ordering::Release),
            proto::Command::Stop => shared.pending.store(2, Ordering::Release),
            proto::Command::Toggle => {
                let next = if shared.running.load(Ordering::Acquire) { 2 } else { 1 };
                shared.pending.store(next, Ordering::Release);
            }
            proto::Command::Params(body) => {
                let mut params = shared.params_snapshot();
                if let Err(e) = params.apply_patch(&body) {
                    let _ = proto::emit(&proto::ev::error(&e));
                } else {
                    *shared.params.lock().unwrap() = params;
                }
            }
            proto::Command::Save(body) => {
                let mut params = shared.params_snapshot();
                let patch_result = params.apply_patch(&body);
                if let Err(e) = patch_result {
                    let _ = proto::emit(&proto::ev::error(&e));
                } else {
                    *shared.params.lock().unwrap() = params.clone();
                    if let Err(e) = state::save(&params) {
                        let _ = proto::emit(&proto::ev::error(&format!("the state was not saved ({})", e)));
                    }
                }
            }
            proto::Command::Quit => break,
        }
    }

    // Drain: a stop at a click boundary, then wait for the output plane to
    // say it happened, so a quit never races the last beat line out the door.
    shared.pending.store(2, Ordering::Release);
    drain_stop(&shared);

    shared.shutdown.store(true, Ordering::Release);
    drop(audio); // closes the stream, which drops the callback's Shared arc
    drop(shared); // drops the last sender, so the out thread's loop ends
    let _ = clock.map(|h| h.join());
    let _ = out_thread.join();
    let _ = proto::emit(&proto::ev::quitready());
}

mod audio {
    use super::{Ev, Shared, Timeline};
    use cpal::traits::{DeviceTrait, HostTrait, StreamTrait};
    use std::cell::RefCell;
    use std::sync::atomic::{AtomicU64, Ordering};
    use std::sync::Arc;

    const LEAD_SECONDS: f64 = 0.08;

    // One timeline per audio thread. The cpal callback runs on a device thread
    // that never crosses over, so thread-local storage is the cheapest safe
    // home for state the control plane must never touch mid-buffer.
    thread_local! {
        static TIMELINE: RefCell<Timeline> = RefCell::new(Timeline::new());
    }

    fn with_timeline<R>(f: impl FnOnce(&mut Timeline) -> R) -> R {
        TIMELINE.with(|tl| f(&mut tl.borrow_mut()))
    }

    pub struct Output {
        pub device_name: String,
        pub sample_rate: u32,
        _stream: cpal::Stream,
    }

    impl Output {
        // Build the default output stream, or say why not and give None, which
        // the control thread answers with the silent clock.
        pub fn open(shared: &Arc<Shared>) -> Option<Output> {
            let host = cpal::default_host();
            let device = host.default_output_device()?;
            let name = device.name().unwrap_or_else(|_| "unknown".to_string());

            let supported = match device.default_output_config() {
                Ok(c) => c,
                Err(e) => {
                    eprintln!("pulse: the output device answered no config ({})", e);
                    return None;
                }
            };
            if supported.sample_format() != cpal::SampleFormat::F32 {
                eprintln!(
                    "pulse: the output device offered {:?}, and Pulse speaks f32 only",
                    supported.sample_format()
                );
                return None;
            }
            let config: cpal::StreamConfig = supported.into();
            let sample_rate = config.sample_rate.0;
            let channels = config.channels as usize;
            let sr = sample_rate as f64;

            let frame = Arc::new(AtomicU64::new(0));
            let callback_frame = frame.clone();
            let callback_shared = shared.clone();
            let err_shared = shared.clone();

            let stream = match device.build_output_stream(
                &config,
                move |data: &mut [f32], _| {
                    let s: &Shared = &callback_shared;
                    let running = s.running.load(Ordering::Acquire);
                    match s.pending.swap(0, Ordering::AcqRel) {
                        1 if !running => {
                            let at = callback_frame.load(Ordering::Acquire);
                            with_timeline(|tl| tl.arm(at, LEAD_SECONDS, sr));
                            s.running.store(true, Ordering::Release);
                            s.send(Ev::Started);
                        }
                        2 if running => {
                            let beats = with_timeline(|tl| {
                                tl.disarm();
                                tl.total_beats
                            });
                            s.running.store(false, Ordering::Release);
                            s.send(Ev::Stopped { beats });
                        }
                        _ => {}
                    }

                    if s.running.load(Ordering::Acquire) {
                        let params = s.params_snapshot();
                        let from = callback_frame.load(Ordering::Acquire);
                        let mut events = Vec::new();
                        with_timeline(|tl| {
                            tl.mix_into(data, channels, from, &params, sr, &mut events)
                        });
                        for ev in events {
                            s.send(ev);
                        }
                    } else {
                        data.fill(0.0);
                    }
                    callback_frame.fetch_add(data.len() as u64 / channels.max(1) as u64, Ordering::AcqRel);
                },
                move |err| {
                    if !err_shared.err_reported.swap(true, Ordering::AcqRel) {
                        err_shared.send(Ev::Error(format!("the audio device failed ({})", err)));
                    }
                },
                None,
            ) {
                Ok(s) => s,
                Err(e) => {
                    eprintln!("pulse: the output stream could not be built ({})", e);
                    return None;
                }
            };

            if let Err(e) = stream.play() {
                eprintln!("pulse: the output stream would not start ({})", e);
                return None;
            }

            Some(Output {
                device_name: name,
                sample_rate,
                _stream: stream,
            })
        }
    }
}

mod clock {
    use super::{Ev, Shared, Timeline};
    use std::sync::atomic::Ordering;
    use std::sync::Arc;
    use std::time::{Duration, Instant};

    const LEAD_SECONDS: f64 = 0.08;
    const POLL: Duration = Duration::from_millis(10);
    // The final stretch is spun, not slept, the way the audio path never sleeps
    // at all; this is the silent clock's answer to the same problem.
    const SPIN: Duration = Duration::from_millis(8);

    pub fn spawn(shared: Arc<Shared>, sr: f64) -> std::thread::JoinHandle<()> {
        std::thread::Builder::new()
            .name("pulse-clock".into())
            .spawn(move || run(shared, sr))
            .expect("spawn silent clock")
    }

    fn run(shared: Arc<Shared>, sr: f64) {
        let mut tl = Timeline::new();
        let mut events = Vec::new();
        loop {
            // Parked between runs: only a start request or a shutdown moves it.
            loop {
                if shared.shutdown.load(Ordering::Acquire) {
                    return;
                }
                match shared.pending.swap(0, Ordering::AcqRel) {
                    1 => break,
                    2 if shared.running.load(Ordering::Acquire) => {
                        let beats = {
                            tl.disarm();
                            shared.running.store(false, Ordering::Release);
                            tl.total_beats
                        };
                        shared.send(Ev::Stopped { beats });
                    }
                    _ => std::thread::sleep(POLL),
                }
            }

            let anchor = Instant::now();
            tl.arm(0, LEAD_SECONDS, sr);
            shared.running.store(true, Ordering::Release);
            shared.send(Ev::Started);

            while shared.running.load(Ordering::Acquire) {
                if shared.shutdown.load(Ordering::Acquire) {
                    return;
                }
                match shared.pending.swap(0, Ordering::AcqRel) {
                    2 => {
                        let beats = {
                            tl.disarm();
                            shared.running.store(false, Ordering::Release);
                            tl.total_beats
                        };
                        shared.send(Ev::Stopped { beats });
                        break;
                    }
                    _ => {}
                }

                let wall_frame = (anchor.elapsed().as_secs_f64() * sr) as u64;
                let until = wall_frame.min(u64::MAX);
                events.clear();
                tl.advance_events_to(until, &shared.params_snapshot(), sr, &mut events);
                for ev in events.drain(..) {
                    shared.send(ev);
                }
                shared.frame.store(wall_frame, Ordering::Release);

                // Sleep toward the next click, then spin the last stretch so the
                // event lands within a few microseconds of its own sample.
                if tl.armed {
                    let until_instant = anchor + Duration::from_secs_f64(tl.phase / sr);
                    let now = Instant::now();
                    if until_instant > now + SPIN {
                        let chunk = (until_instant - now - SPIN).min(POLL);
                        std::thread::sleep(chunk);
                    } else if until_instant > now {
                        std::hint::spin_loop();
                    }
                } else {
                    std::thread::sleep(POLL);
                }
            }
        }
    }
}

// Stop has to be observable: the control thread waits for the output plane to
// clear the running flag before it tears anything down, with a generous cap so
// a wedged device cannot hang the quit.
fn drain_stop(shared: &Arc<Shared>) {
    let deadline = std::time::Instant::now() + std::time::Duration::from_secs(1);
    while shared.running.load(Ordering::Acquire) {
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
        Params { bpm, beats, denominator, volume: 1.0, ..Params::default() }
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

        p.voices[0] = VOICE_OFF;
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
        assert_eq!(events[0], Ev::Beat { beat: 0, kind: Kind::High });
        assert_eq!(events[1], Ev::Beat { beat: 1, kind: Kind::Low });
        assert_eq!(events[3], Ev::Beat { beat: 3, kind: Kind::Low });
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
        assert_eq!(events[0], Ev::Beat { beat: 0, kind: Kind::High });
        assert_eq!(events[1], Ev::Beat { beat: 1, kind: Kind::Low });
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
            buf.iter().any(|s| *s != 0.0),
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
        assert!(peak > 0.0, "the click continues into later buffers");
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
        assert!(buf.iter().all(|s| *s == 0.0));
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
        p.apply_patch(&Json::parse(r#"{"subdiv":1}"#).unwrap()).unwrap();
        assert_eq!(p.denominator, 4);
        p.apply_patch(&Json::parse(r#"{"subdiv":2}"#).unwrap()).unwrap();
        assert_eq!(p.denominator, 8);
        // Triplet signs had no bottom number to call home; they land on 8.
        p.apply_patch(&Json::parse(r#"{"subdiv":3}"#).unwrap()).unwrap();
        assert_eq!(p.denominator, 8);
        p.apply_patch(&Json::parse(r#"{"subdiv":4}"#).unwrap()).unwrap();
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
        assert_eq!(p.voices[1], VOICE_OFF);
        assert_eq!(p.voices[2], VOICE_MEDIUM);
        // A short array leaves the tail as it was.
        assert_eq!(p.voices[3], VOICE_LOW);
    }

    #[test]
    fn a_muted_beat_walks_the_timeline_without_sound() {
        let mut p = params(120.0, 4, 4);
        p.voices[1] = VOICE_OFF;
        let mut tl = Timeline::new();
        tl.arm(0, 0.0, SR);
        let mut events = Vec::new();
        tl.advance_events_to(24_000, &p, SR, &mut events);
        assert_eq!(events.len(), 2);
        assert_eq!(events[0], Ev::Beat { beat: 0, kind: Kind::High });
        assert_eq!(events[1], Ev::Beat { beat: 1, kind: Kind::Off });
        assert_eq!(tl.total_beats, 2);

        // Nothing at all is on: every position walks, not one sample sounds.
        let mut p = params(120.0, 4, 4);
        p.voices = [VOICE_OFF; 12];
        let mut tl = Timeline::new();
        tl.arm(0, 0.0, SR);
        let mut buf = vec![0.0f32; 96_000];
        let mut events = Vec::new();
        tl.mix_into(&mut buf, 1, 0, &p, SR, &mut events);
        assert_eq!(events.len(), 4, "the timeline still walks every beat");
        assert!(buf.iter().all(|s| *s == 0.0), "not one sample sounds");
        assert_eq!(events[0], Ev::Beat { beat: 0, kind: Kind::Off });
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
}
