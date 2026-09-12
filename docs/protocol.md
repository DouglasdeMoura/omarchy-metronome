# The Pulse protocol

One json object per line, both ways, over the stdio of `pulse --backend`. The
UI (`ui/Backend.qml`) is the only client; `src/backend/proto.rs` is the only
interpreter. A line the backend cannot read becomes an `error` event, never a
silence.

## Requests — UI → backend

Every request names its command in `"c"`.

| command | fields | meaning |
| --- | --- | --- |
| `hello` | — | re-send `state` and `ready` (the UI asks on startup) |
| `start` | — | arm the timeline; the first click is one lead-in out |
| `stop` | — | stop at once; a `stopped` event answers with the beat total |
| `toggle` | — | start if stopped, stop if running |
| `params` | any of `bpm`, `beats`, `denominator`, `volume`, `voices` | apply; tempo and signature changes land at the next click, volume at the next click, all clamped |
| `save` | same fields as `params` | apply and persist to `~/.config/pulse/state.json` |
| `quit` | — | drain (stop, last events out), then one `quitready` |

```json
{"c":"params","bpm":132,"beats":3,"denominator":8}
{"c":"save","bpm":132,"beats":4,"denominator":4,"voices":[2,1,1,0,1,1,1,1,1,1,1,1]}
```

`voices` is the per-beat pattern: 0 silent, 1 low tone, 2 medium tone,
3 high tone — twelve slots so a pattern survives a change of meter.
`denominator` is the time signature's bottom number: the tick is a 1/d note,
so its interval is 60/bpm × 4/d; only 1, 2, 4 and 8 are accepted. The legacy
`subdiv` key (1=4, 2/3/4=8) is still read when `denominator` is absent, and
`volume` is still accepted for state-file compatibility, but the UI no longer
exposes a control — loudness belongs to the system, not to one app.

## Events — backend → UI

Every event names itself in `"t"`.

| event | fields | meaning |
| --- | --- | --- |
| `state` | `bpm`, `beats`, `denominator`, `voices`, `volume` | the loaded parameters, sent at startup and on `hello` |
| `ready` | `device`, `rate`, `silent` | the output that will sound; `silent: true` means no device was found and a wall clock drives the visuals |
| `started` | — | the timeline is armed and the first click is scheduled |
| `beat` | `beat`, `kind` | one beat position is on the device; `beat` counts from 0, `kind` is `high`, `medium`, `low` or `off` (muted: the visual walks, nothing sounds) |
| `stopped` | `beats` | stopped; `beats` is the total number of beats played this run |
| `error` | `msg` | a device failed, a patch was refused, a line was unreadable |
| `quitready` | — | the backend has drained; the window may close |

```json
{"t":"beat","beat":0,"sub":2,"kind":"sub"}
{"t":"stopped","beats":12}
```

## Timing

Beat events are emitted by the audio callback at the buffer position where
the click is mixed in, so a lamp lights when its click is on the device.
Tempo, meter and subdivision changes are read per click, which makes the next
click the changeover point; volume likewise. `quit` waits for the stop to be
observable before it answers, so a close never races the last beat out.
