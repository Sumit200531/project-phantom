"""Synthesizes every sound effect used by Project Phantom.

Run:  python3 tools/generate_audio.py
Outputs 16-bit mono WAV files into assets/audio/. All sounds are generated here
from noise and oscillators, so they are original and licence-free.
"""
import os
import wave
import numpy as np
from scipy import signal

OUT = os.path.join(os.path.dirname(__file__), "..", "assets", "audio")
os.makedirs(OUT, exist_ok=True)
SR = 32000
rng = np.random.default_rng(42)


def t_axis(dur):
    return np.arange(int(SR * dur)) / SR


def noise(dur):
    return rng.uniform(-1, 1, int(SR * dur))


def env_exp(dur, decay, attack=0.001):
    t = t_axis(dur)
    a = np.clip(t / max(attack, 1e-5), 0, 1)
    return a * np.exp(-t / decay)


def bp(x, lo, hi, order=2):
    b, a = signal.butter(order, [lo / (SR / 2), min(hi / (SR / 2), 0.99)], btype="band")
    return signal.lfilter(b, a, x)


def lp(x, f, order=2):
    b, a = signal.butter(order, min(f / (SR / 2), 0.99), btype="low")
    return signal.lfilter(b, a, x)


def hp(x, f, order=2):
    b, a = signal.butter(order, f / (SR / 2), btype="high")
    return signal.lfilter(b, a, x)


def sweep_sine(dur, f0, f1, curve=4.0):
    t = t_axis(dur)
    f = f1 + (f0 - f1) * np.exp(-t * curve / dur * 3)
    ph = 2 * np.pi * np.cumsum(f) / SR
    return np.sin(ph)


def reverb(x, length=0.6, decay=0.18, mix=0.25, bright=4000):
    ir = noise(length) * np.exp(-t_axis(length) / decay)
    ir = lp(ir, bright)
    ir /= np.max(np.abs(ir)) + 1e-9
    wet = signal.fftconvolve(x, ir)[: len(x) + int(SR * length)]
    dry = np.concatenate([x, np.zeros(len(wet) - len(x))])
    wet /= np.max(np.abs(wet)) + 1e-9
    return dry * (1 - mix) + wet * mix * np.max(np.abs(dry))


def pad(x, dur):
    n = int(SR * dur)
    if len(x) >= n:
        return x[:n]
    return np.concatenate([x, np.zeros(n - len(x))])


def mix(*parts):
    n = max(len(p) for p in parts)
    out = np.zeros(n)
    for p in parts:
        out[: len(p)] += p
    return out


def write(name, x, gain=0.9):
    x = np.asarray(x, dtype=float)
    fade = min(len(x), int(SR * 0.01))
    x[-fade:] *= np.linspace(1, 0, fade)
    peak = np.max(np.abs(x)) + 1e-9
    x = x / peak * gain
    data = (x * 32767).astype(np.int16)
    with wave.open(os.path.join(OUT, name + ".wav"), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(data.tobytes())


# ------------------------------------------------------------------ weapons
def gunshot(body_f, crack_lo, crack_hi, decay, tail, thump_f=80, bright=5000, dur=0.9, seed_shift=0):
    global rng
    rng = np.random.default_rng(100 + seed_shift)
    crack = bp(noise(0.05), crack_lo, crack_hi) * env_exp(0.05, 0.008)
    blast = lp(noise(dur), bright) * env_exp(dur, decay, 0.0005)
    body = sweep_sine(0.25, body_f * 2.2, body_f, 6) * env_exp(0.25, 0.05)
    thump = sweep_sine(0.3, thump_f * 2, thump_f * 0.6, 5) * env_exp(0.3, 0.07)
    mech = bp(noise(0.03), 2500, 7000) * env_exp(0.03, 0.004)
    x = mix(crack * 1.2, blast * 0.9, body * 0.5, thump * 0.9, np.concatenate([np.zeros(int(SR * 0.012)), mech * 0.3]))
    x = np.tanh(x * 2.2)
    return reverb(pad(x, dur), length=tail, decay=tail * 0.3, mix=0.3)


def weapons():
    for i in range(3):
        write(f"rifle_shot_{i+1}", gunshot(140 + i * 8, 1800, 9000, 0.07, 0.9, thump_f=70, seed_shift=i), 0.95)
    for i in range(2):
        write(f"smg_shot_{i+1}", gunshot(220 + i * 15, 2500, 11000, 0.045, 0.6, thump_f=95, bright=7000, dur=0.6, seed_shift=10 + i), 0.9)
    for i in range(2):
        write(f"pistol_shot_{i+1}", gunshot(260 + i * 20, 2200, 10000, 0.05, 0.7, thump_f=110, bright=6500, dur=0.7, seed_shift=20 + i), 0.9)
    # distant variant (muffled) for far shots
    write("rifle_shot_far", lp(gunshot(130, 1500, 6000, 0.12, 1.2, thump_f=60, dur=1.4, seed_shift=40), 1500), 0.7)

    # mechanical sounds
    def click(f_lo, f_hi, decay, dur=0.06):
        return bp(noise(dur), f_lo, f_hi) * env_exp(dur, decay)

    write("dry_fire", mix(click(2500, 8000, 0.006), pad(np.zeros(int(SR * 0.02)), 0.02)), 0.6)
    mag_out = mix(click(800, 4000, 0.02, 0.15), np.concatenate([np.zeros(int(SR * 0.05)), click(300, 1500, 0.04, 0.15) * 0.6]))
    write("reload_mag_out", mag_out, 0.7)
    mag_in = mix(click(600, 3500, 0.015, 0.1) * 0.6, np.concatenate([np.zeros(int(SR * 0.06)), click(1500, 7000, 0.01, 0.1) * 1.2]))
    write("reload_mag_in", mag_in, 0.8)
    bolt = mix(click(1200, 6000, 0.02, 0.12), np.concatenate([np.zeros(int(SR * 0.11)), click(2000, 9000, 0.012, 0.12) * 1.3]))
    write("reload_bolt", bolt, 0.85)
    write("weapon_switch", mix(click(500, 3000, 0.03, 0.2) * 0.6, np.concatenate([np.zeros(int(SR * 0.08)), click(2000, 7000, 0.01, 0.08)])), 0.6)
    for i in range(2):
        t = t_axis(0.25)
        tink = (np.sin(2 * np.pi * (5200 + i * 600) * t) * 0.6 + np.sin(2 * np.pi * (7900 + i * 400) * t) * 0.4) * env_exp(0.25, 0.04)
        tink2 = np.concatenate([np.zeros(int(SR * 0.09)), tink[: int(SR * 0.15)] * 0.4])
        write(f"shell_{i+1}", mix(tink, tink2), 0.35)


# ------------------------------------------------------------------ hits / feedback
def feedback():
    t = t_axis(0.12)
    write("hit_body", (np.sin(2 * np.pi * 1600 * t) * 0.5 + bp(noise(0.12), 1500, 5000) * 0.5) * env_exp(0.12, 0.025), 0.55)
    t = t_axis(0.4)
    ding = (np.sin(2 * np.pi * 2350 * t) + 0.5 * np.sin(2 * np.pi * 4700 * t) + 0.25 * np.sin(2 * np.pi * 3530 * t)) * env_exp(0.4, 0.09)
    write("hit_head", mix(ding, bp(noise(0.05), 3000, 9000) * env_exp(0.05, 0.01) * 0.6), 0.6)
    t = t_axis(0.5)
    k = np.sin(2 * np.pi * 660 * t) * env_exp(0.5, 0.12) + np.concatenate([np.zeros(int(SR * 0.07)), (np.sin(2 * np.pi * 990 * t) * env_exp(0.5, 0.15))[: int(SR * 0.43)]])
    write("kill_confirm", k, 0.6)
    write("hurt", mix(lp(noise(0.25), 400) * env_exp(0.25, 0.06), sweep_sine(0.2, 160, 60) * env_exp(0.2, 0.05)), 0.75)
    for i, (lo, hi) in enumerate([(800, 5000), (2000, 9000)]):
        name = ["impact_concrete", "impact_metal"][i]
        x = bp(noise(0.25), lo, hi) * env_exp(0.25, 0.03)
        if i == 1:
            tt = t_axis(0.35)
            ring = np.sin(2 * np.pi * (3100 + 900 * np.exp(-tt * 20)) * tt) * env_exp(0.35, 0.07) * 0.6
            x = mix(x, ring)
        write(name, x, 0.5)
    write("impact_flesh", mix(lp(noise(0.12), 900) * env_exp(0.12, 0.02), bp(noise(0.08), 2000, 6000) * env_exp(0.08, 0.01) * 0.6), 0.55)


# ------------------------------------------------------------------ footsteps
def footsteps():
    for i in range(4):
        global rng
        rng = np.random.default_rng(200 + i)
        heel = lp(noise(0.08), 1800) * env_exp(0.08, 0.012)
        scuff = bp(noise(0.12), 1500, 6000) * env_exp(0.12, 0.03, 0.01) * 0.35
        write(f"step_concrete_{i+1}", mix(heel, np.concatenate([np.zeros(int(SR * 0.02)), scuff])), 0.5)
        t = t_axis(0.3)
        clang = (np.sin(2 * np.pi * (420 + i * 35) * t) * 0.5 + np.sin(2 * np.pi * (1130 + i * 70) * t) * 0.35 + np.sin(2 * np.pi * (2410 + i * 50) * t) * 0.2) * env_exp(0.3, 0.06)
        write(f"step_metal_{i+1}", mix(heel * 0.8, clang * 0.7), 0.55)
        rustle = bp(noise(0.22), 2500, 9000) * env_exp(0.22, 0.05, 0.015)
        soft = lp(noise(0.1), 600) * env_exp(0.1, 0.02)
        write(f"step_grass_{i+1}", mix(rustle * 0.8, soft * 0.7), 0.4)
    write("land_concrete", mix(lp(noise(0.25), 900) * env_exp(0.25, 0.05), bp(noise(0.15), 1500, 5000) * env_exp(0.15, 0.03) * 0.5), 0.7)
    t = t_axis(0.5)
    write("land_metal", mix(lp(noise(0.25), 900) * env_exp(0.25, 0.05), (np.sin(2 * np.pi * 380 * t) + 0.5 * np.sin(2 * np.pi * 950 * t)) * env_exp(0.5, 0.1) * 0.6), 0.7)
    write("land_grass", mix(lp(noise(0.25), 500) * env_exp(0.25, 0.05), bp(noise(0.3), 2500, 9000) * env_exp(0.3, 0.06) * 0.6), 0.6)
    write("jump", bp(noise(0.15), 800, 3000) * env_exp(0.15, 0.04, 0.02), 0.35)


# ------------------------------------------------------------------ abilities
def abilities():
    # obscuring field: canister pop + long hiss
    pop = bp(noise(0.08), 400, 3000) * env_exp(0.08, 0.015)
    hiss_t = 1.6
    hiss = bp(noise(hiss_t), 1500, 9000) * (np.clip(t_axis(hiss_t) / 0.08, 0, 1) * np.exp(-t_axis(hiss_t) / 0.7))
    write("smoke_deploy", mix(pop * 1.2, np.concatenate([np.zeros(int(SR * 0.05)), hiss * 0.8])), 0.8)
    write("smoke_throw", bp(noise(0.25), 600, 3000) * env_exp(0.25, 0.06, 0.03), 0.4)
    # barrier: rising synth with hum
    t = t_axis(0.9)
    f = 140 + 260 * np.clip(t / 0.35, 0, 1) ** 0.5
    ph = 2 * np.pi * np.cumsum(f) / SR
    tone = (np.sin(ph) + 0.4 * np.sin(2 * ph) + 0.2 * signal.sawtooth(ph * 3)) * env_exp(0.9, 0.35, 0.02)
    write("barrier_up", reverb(mix(tone, bp(noise(0.9), 2000, 6000) * env_exp(0.9, 0.15) * 0.2), 0.5, 0.15, 0.3), 0.75)
    t = t_axis(0.18)
    write("barrier_hit", (np.sin(2 * np.pi * 880 * t) * 0.5 + bp(noise(0.18), 3000, 9000)) * env_exp(0.18, 0.03), 0.4)
    t = t_axis(0.6)
    f = 380 * np.exp(-t * 3)
    ph = 2 * np.pi * np.cumsum(f + 60) / SR
    write("barrier_down", (np.sin(ph) + 0.3 * bp(noise(0.6), 1000, 5000)) * env_exp(0.6, 0.2), 0.6)
    # recon pulse: sonar ping with echo
    t = t_axis(1.4)
    ping = np.sin(2 * np.pi * 1320 * t) * env_exp(1.4, 0.25, 0.003) + 0.35 * np.sin(2 * np.pi * 1980 * t) * env_exp(1.4, 0.18)
    sweep = sweep_sine(0.4, 300, 2200, 2) * env_exp(0.4, 0.1) * 0.4
    write("recon_pulse", reverb(mix(sweep, np.concatenate([np.zeros(int(SR * 0.05)), ping])), 1.0, 0.3, 0.45, 6000), 0.8)
    t = t_axis(0.35)
    write("ability_ready", (np.sin(2 * np.pi * 880 * t) * env_exp(0.35, 0.08) + np.concatenate([np.zeros(int(SR * 0.08)), (np.sin(2 * np.pi * 1320 * t) * env_exp(0.35, 0.1))[: int(SR * 0.27)]])), 0.4)
    t = t_axis(0.2)
    write("ability_denied", signal.square(2 * np.pi * 180 * t) * env_exp(0.2, 0.06) * 0.5, 0.35)
    write("reveal_tick", (np.sin(2 * np.pi * 2600 * t_axis(0.08)) * env_exp(0.08, 0.015)), 0.35)


# ------------------------------------------------------------------ objective device
def device():
    t = t_axis(0.12)
    write("device_beep", (np.sin(2 * np.pi * 2100 * t) + 0.3 * signal.square(2 * np.pi * 2100 * t)) * env_exp(0.12, 0.04, 0.002), 0.55)
    t = t_axis(1.2)
    f = 200 + 900 * np.clip(t / 1.0, 0, 1) ** 2
    ph = 2 * np.pi * np.cumsum(f) / SR
    write("device_planted", reverb((np.sin(ph) + 0.3 * signal.sawtooth(ph)) * env_exp(1.2, 0.5, 0.05), 0.8, 0.25, 0.35), 0.75)
    t = t_axis(0.09)
    write("device_tick", np.sin(2 * np.pi * 1450 * t) * env_exp(0.09, 0.02), 0.4)
    t = t_axis(1.0)
    f = 1100 * np.exp(-t * 2.5) + 120
    ph = 2 * np.pi * np.cumsum(f) / SR
    write("device_defused", reverb(np.sin(ph) * env_exp(1.0, 0.35, 0.01), 0.6, 0.2, 0.3), 0.7)
    dur = 4.0
    boom = lp(noise(dur), 900) * env_exp(dur, 0.7, 0.003)
    sub = sweep_sine(2.0, 90, 28, 2) * env_exp(2.0, 0.6)
    crackle = bp(noise(dur), 2000, 8000) * env_exp(dur, 0.25) * 0.4
    write("device_explode", reverb(np.tanh(mix(boom * 1.4, sub * 1.6, crackle) * 1.8), 1.5, 0.5, 0.4, 3000), 0.98)
    write("device_pickup", (np.sin(2 * np.pi * 740 * t_axis(0.25)) * env_exp(0.25, 0.06) + np.concatenate([np.zeros(int(SR * 0.07)), (np.sin(2 * np.pi * 1110 * t_axis(0.25)) * env_exp(0.25, 0.07))[: int(SR * 0.18)]])), 0.45)


# ------------------------------------------------------------------ stingers / ui
def chord(freqs, dur, decay, delay_step=0.0, wave_fn=np.sin):
    out = np.zeros(int(SR * (dur + delay_step * len(freqs))))
    for i, fq in enumerate(freqs):
        t = t_axis(dur)
        tone = (wave_fn(2 * np.pi * fq * t) + 0.3 * np.sin(2 * np.pi * fq * 2 * t)) * env_exp(dur, decay, 0.01)
        s = int(SR * delay_step * i)
        out[s : s + len(tone)] += tone
    return out


def stingers():
    tri = lambda x: signal.sawtooth(x, 0.5)
    write("round_start", reverb(mix(chord([392, 523.25], 0.9, 0.3, 0.0, tri), np.concatenate([np.zeros(int(SR * 0.25)), chord([587.33, 783.99], 0.9, 0.35, 0.0, tri)])), 0.9, 0.3, 0.35), 0.6)
    write("round_win", reverb(chord([523.25, 659.25, 783.99, 1046.5], 1.1, 0.4, 0.09, tri), 1.0, 0.35, 0.35), 0.65)
    write("round_lose", reverb(chord([440, 349.23, 293.66, 220], 1.2, 0.45, 0.11, tri), 1.0, 0.35, 0.35), 0.6)
    write("match_win", reverb(mix(chord([523.25, 659.25, 783.99], 1.6, 0.6, 0.0, tri), np.concatenate([np.zeros(int(SR * 0.45)), chord([698.46, 880, 1046.5, 1318.5], 1.8, 0.7, 0.07, tri)])), 1.4, 0.45, 0.4), 0.7)
    write("match_lose", reverb(chord([392, 311.13, 261.63, 196], 2.0, 0.7, 0.18, tri), 1.4, 0.45, 0.4), 0.65)
    write("ui_hover", np.sin(2 * np.pi * 1800 * t_axis(0.05)) * env_exp(0.05, 0.012), 0.2)
    write("ui_click", mix(np.sin(2 * np.pi * 1200 * t_axis(0.09)) * env_exp(0.09, 0.02), bp(noise(0.03), 3000, 9000) * env_exp(0.03, 0.005) * 0.5), 0.35)
    write("countdown", np.sin(2 * np.pi * 1000 * t_axis(0.15)) * env_exp(0.15, 0.05), 0.4)


# ------------------------------------------------------------------ ambience loops
def ambience():
    dur = 8.0
    n = noise(dur)
    wind = lp(n, 500) * (0.6 + 0.4 * np.sin(2 * np.pi * t_axis(dur) / dur * 2))
    hiss = bp(noise(dur), 3000, 8000) * 0.05
    x = wind + hiss
    # make seamless: crossfade end into start
    cf = int(SR * 0.5)
    x[:cf] = x[:cf] * np.linspace(0, 1, cf) + x[-cf:] * np.linspace(1, 0, cf)
    write("amb_wind_loop", x[:-cf], 0.35)
    t = t_axis(dur)
    hum = (np.sin(2 * np.pi * 55 * t) * 0.5 + np.sin(2 * np.pi * 110 * t) * 0.3 + np.sin(2 * np.pi * 165.5 * t) * 0.15)
    hum *= 0.8 + 0.2 * np.sin(2 * np.pi * 0.25 * t)
    hum += lp(noise(dur), 300) * 0.15
    write("amb_reactor_loop", hum, 0.45)


if __name__ == "__main__":
    for fn in (weapons, feedback, footsteps, abilities, device, stingers, ambience):
        fn()
        print("generated", fn.__name__)
