"""Renders the game's synthwave music loops to assets/audio/*.wav.

Everything is synthesized from oscillators and noise (no samples), so the
music matches the game's synth sound effects. Run from the repository root:

    python3 tools/synthwave.py

Needs numpy. Each track is a seamless loop; the game sets the loop points.
"""
import wave
import numpy as np

RATE = 32000
rng = np.random.default_rng(1989)

NOTE = {"C": 0, "C#": 1, "D": 2, "D#": 3, "E": 4, "F": 5, "F#": 6, "G": 7, "G#": 8, "A": 9, "A#": 10, "B": 11}


def freq(name, octave):
    return 440.0 * 2 ** ((NOTE[name] + 12 * (octave + 1) - 69) / 12)


def lowpass(x, cutoff):
    """One-pole lowpass; cutoff may be a number or a per-sample array (Hz)."""
    cutoff = np.broadcast_to(np.asarray(cutoff, dtype=float), x.shape)
    a = 1.0 - np.exp(-2 * np.pi * cutoff / RATE)
    y = np.empty_like(x)
    acc = 0.0
    for i in range(len(x)):
        acc += a[i] * (x[i] - acc)
        y[i] = acc
    return y


def saw(f, n, phase=0.0):
    t = np.arange(n) / RATE
    return 2 * ((f * t + phase) % 1.0) - 1


def square(f, n, width=0.5):
    t = np.arange(n) / RATE
    return np.where((f * t) % 1.0 < width, 1.0, -1.0)


def env(n, attack, decay, sustain=0.0, release=0.0):
    """Attack, then exponential decay toward sustain; optional linear release at the end."""
    t = np.arange(n) / RATE
    e = sustain + (1 - sustain) * np.exp(-t / max(decay, 1e-4))
    e *= np.clip(t / max(attack, 1e-4), 0, 1)
    if release > 0:
        r = int(release * RATE)
        if r < n:
            e[-r:] *= np.linspace(1, 0, r)
    return e


def place(track, sound, at):
    """Adds sound into track at sample index at, wrapping around for a seamless loop."""
    n = len(sound)
    end = at + n
    if end <= len(track):
        track[at:end] += sound
    else:
        first = len(track) - at
        track[at:] += sound[:first]
        track[: n - first] += sound[first:]


def delay(x, seconds, feedback, mix, taps=6):
    d = int(seconds * RATE)
    out = x.copy()
    echo = x.copy()
    for _ in range(taps):
        echo = np.roll(echo, d) * feedback
        out += echo * mix / feedback
    return out


# --- Instruments -------------------------------------------------------------------

def kick(power=1.0):
    n = int(0.35 * RATE)
    t = np.arange(n) / RATE
    pitch = 45 + 110 * np.exp(-t / 0.035)
    phase = 2 * np.pi * np.cumsum(pitch) / RATE
    body = np.sin(phase) * np.exp(-t / 0.14)
    click = rng.standard_normal(n) * np.exp(-t / 0.004) * 0.25
    return (body + click) * power


def snare():
    n = int(0.45 * RATE)
    t = np.arange(n) / RATE
    tone = np.sin(2 * np.pi * 185 * t) * np.exp(-t / 0.06) * 0.5
    noise = lowpass(rng.standard_normal(n), 6500) * np.exp(-t / 0.16)
    # A gated-reverb tail, the classic 80s snare.
    tail = lowpass(rng.standard_normal(n), 3500) * 0.35 * (t < 0.3) * np.exp(-t / 0.5)
    return (tone + noise * 0.6 + tail) * 0.55


def hat(open_=False):
    n = int((0.18 if open_ else 0.05) * RATE)
    t = np.arange(n) / RATE
    noise = rng.standard_normal(n)
    bright = noise - lowpass(noise, 7000)
    return bright * np.exp(-t / (0.06 if open_ else 0.012)) * 0.22


def bass_note(f, length):
    n = int(length * RATE)
    raw = saw(f, n) * 0.6 + saw(f * 1.004, n) * 0.4 + np.sin(2 * np.pi * f / 2 * np.arange(n) / RATE) * 0.5
    cut = 260 + 1600 * env(n, 0.002, 0.07)
    return lowpass(raw, cut) * env(n, 0.003, 0.25, 0.55, 0.02) * 0.55


def pad_chord(freqs, length):
    n = int(length * RATE)
    out = np.zeros(n)
    for f in freqs:
        for detune, phase in ((0.996, 0.1), (1.004, 0.6), (1.0, 0.35)):
            out += saw(f * detune, n, phase)
    out = lowpass(out / (len(freqs) * 3), 1400)
    return out * env(n, 0.6, 99, 1.0, 0.5) * 0.32


def pluck(f, length, bright=3200, vol=0.22):
    n = int(length * RATE)
    raw = square(f, n, 0.3) * 0.6 + saw(f * 2.002, n) * 0.25
    return lowpass(raw, 300 + bright * env(n, 0.001, 0.05)) * env(n, 0.002, 0.12, 0.0, 0.01) * vol


def lead_note(f, length, vol=0.2):
    n = int(length * RATE)
    t = np.arange(n) / RATE
    vibrato = 1 + 0.006 * np.sin(2 * np.pi * 5.5 * t) * np.clip(t / 0.25, 0, 1)
    phase = np.cumsum(f * vibrato) / RATE
    raw = 2 * (phase % 1.0) - 1 + (2 * ((phase * 1.005) % 1.0) - 1) * 0.6
    return lowpass(raw, 2600) * env(n, 0.02, 0.4, 0.7, 0.08) * vol


# --- Songs -------------------------------------------------------------------------

def render(bpm, bars, chords, bass_octave, arp_pattern, melody, drums, name, kick_power=1.0):
    beat = 60.0 / bpm
    total = int(bars * 4 * beat * RATE)
    drum_bus = np.zeros(total)
    bass_bus = np.zeros(total)
    pad_bus = np.zeros(total)
    arp_bus = np.zeros(total)
    lead_bus = np.zeros(total)
    duck = np.ones(total)
    sixteenth = beat / 4
    for bar in range(bars):
        root, quality = chords[bar % len(chords)]
        r = NOTE[root]
        third = 3 if quality == "m" else 4
        tones = [r, r + third, r + 7]
        bar_start = bar * 4 * beat
        # Pads hold the chord for the whole bar.
        pad = pad_chord([440 * 2 ** ((t + 12 * 4 - 69 + 12) / 12) for t in tones], 4 * beat + 0.3)
        place(pad_bus, pad, int(bar_start * RATE))
        # Driving eighth-note bass, octave pumping on the off-beats.
        for k in range(8):
            octave = bass_octave + (1 if k % 2 else 0)
            f = 440 * 2 ** ((r + 12 * (octave + 1) - 69) / 12)
            place(bass_bus, bass_note(f, beat / 2 * 0.95), int((bar_start + k * beat / 2) * RATE))
        # Sixteenth-note arpeggio over the chord.
        for k in range(16):
            step = arp_pattern[k % len(arp_pattern)]
            if step is None:
                continue
            semis = tones[step % 3] + 12 * (step // 3)
            f = 440 * 2 ** ((semis + 12 * 5 - 69) / 12)
            place(arp_bus, pluck(f, sixteenth * 1.8), int((bar_start + k * sixteenth) * RATE))
        # Drums.
        for k in range(16):
            at = int((bar_start + k * sixteenth) * RATE)
            if k % 4 == 0 and drums != "half":
                place(drum_bus, kick(kick_power), at)
                duck_len = int(beat * 0.6 * RATE)
                curve = 1 - 0.55 * np.exp(-np.arange(duck_len) / (0.08 * RATE))
                end = min(total, at + duck_len)
                duck[at:end] = np.minimum(duck[at:end], curve[: end - at])
            if drums == "half" and k in (0, 10):
                place(drum_bus, kick(kick_power), at)
            if k in (4, 12):
                place(drum_bus, snare(), at)
            if k % 2 == 0:
                place(drum_bus, hat(open_=(k % 8 == 6)), at)
            elif drums == "busy":
                place(drum_bus, hat() * 0.6, at)
    # Lead melody: list of (bar, sixteenth, note, octave, length in sixteenths).
    for bar, step, note, octave, length in melody:
        at = int((bar * 4 * beat + step * sixteenth) * RATE)
        place(lead_bus, lead_note(freq(note, octave), length * sixteenth), at)
    arp_bus = delay(arp_bus, sixteenth * 3, 0.35, 0.5)
    lead_bus = delay(lead_bus, beat * 0.75, 0.3, 0.45)
    pad_bus = delay(pad_bus, beat * 1.5, 0.25, 0.3)
    mix = drum_bus * 0.9 + (bass_bus * 0.9 + pad_bus + arp_bus * 0.8 + lead_bus) * duck
    mix = np.tanh(mix * 1.2)
    mix *= 0.7 / np.max(np.abs(mix))
    data = (mix * 32767).astype("<i2").tobytes()
    with wave.open(f"assets/audio/{name}.wav", "wb") as out:
        out.setnchannels(1)
        out.setsampwidth(2)
        out.setframerate(RATE)
        out.writeframes(data)
    print(f"assets/audio/{name}.wav: {total / RATE:.1f} s")


# Neon Row: A minor, i-VI-III-VII, a warm cruising tempo. The lead comes in for
# the second half of the loop.
street_lead = [
    (8, 0, "E", 5, 6), (8, 6, "D", 5, 2), (8, 8, "C", 5, 4), (8, 12, "A", 4, 4),
    (9, 0, "C", 5, 6), (9, 6, "D", 5, 2), (9, 8, "E", 5, 8),
    (10, 0, "G", 5, 6), (10, 6, "E", 5, 2), (10, 8, "D", 5, 4), (10, 12, "C", 5, 4),
    (11, 0, "D", 5, 8), (11, 8, "B", 4, 8),
    (12, 0, "E", 5, 6), (12, 6, "D", 5, 2), (12, 8, "C", 5, 4), (12, 12, "E", 5, 4),
    (13, 0, "A", 5, 8), (13, 8, "G", 5, 8),
    (14, 0, "E", 5, 4), (14, 4, "G", 5, 4), (14, 8, "D", 5, 8),
    (15, 0, "B", 4, 8), (15, 8, "A", 4, 8),
]
render(100, 16, [("A", "m"), ("F", ""), ("C", ""), ("G", "")], 1,
       [0, 1, 2, 3, 2, 1, 0, 1, 2, 3, 4, 3, 2, 1, 2, None], street_lead, "straight", "music_street")

# The Ash Warden: D minor with a tense Bb and A, faster and heavier.
boss_lead = [
    (4, 0, "D", 5, 4), (4, 4, "F", 5, 4), (4, 8, "A", 5, 6), (4, 14, "G#", 5, 2),
    (5, 0, "A", 5, 8), (5, 8, "F", 5, 8),
    (6, 0, "D", 5, 4), (6, 4, "F", 5, 4), (6, 8, "A#", 5, 6), (6, 14, "A", 5, 2),
    (7, 0, "E", 5, 16),
]
render(124, 8, [("D", "m"), ("A#", ""), ("D", "m"), ("A", "")], 1,
       [0, 2, 1, 2, 3, 2, 1, 2, 0, 2, 1, 2, 4, 3, 2, 1], boss_lead, "busy", "music_boss", kick_power=1.15)
