#!/usr/bin/env python3
"""Renders an Electron's tone channel, logged by clkh --soundlog (a line per
write to &FE06 or &FE07: the 2 MHz cycle, the register, the value in hex),
as 16-bit mono WAV files: the ULA's square wave, 1 MHz / (16 * (n + 1)) for
counter n, on while bits 1-2 of &FE07 are 01, through a 6 kHz low-pass (as
CLK's speaker).

  soundwav.py LOG OUT.wav [START END]     seconds of emulated time (default:
                                          the whole log)
  soundwav.py LOG --marks MARKS DIR PRE   for each line "CYCLE NAME" of MARKS,
                                          DIR/PRE-NAME.wav up to the next mark
                                          (3 s at most), and the tone sequence
                                          printed (ms after the mark: counter,
                                          or - for off)
"""
import sys, wave, struct, math, os


def events(log):
    ev = []
    for l in open(log):
        f = l.split()
        if len(f) == 3:
            ev.append((int(f[0]) / 2e6, int(f[1]), int(f[2], 16)))
    return ev


def render(ev, out, t0, t1, sr=44100, amp=0.25):
    on, div, phase, lp = False, 0, 0.0, 0.0
    k = math.exp(-2 * math.pi * 6000 / sr)
    i = 0
    while i < len(ev) and ev[i][0] < t0:
        _, r, v = ev[i]
        if r == 7: on = (v & 6) == 2
        else: div = v
        i += 1
    frames = bytearray()
    for s in range(int((t1 - t0) * sr)):
        t = t0 + s / sr
        while i < len(ev) and ev[i][0] <= t:
            _, r, v = ev[i]
            if r == 7: on = (v & 6) == 2
            else: div = v
            i += 1
        x = 0.0
        if on:
            f = 1e6 / (16 * (div + 1))
            if f < sr / 2:
                phase = (phase + f / sr) % 1.0
                x = amp if phase < 0.5 else -amp
        lp = lp * k + x * (1 - k)
        frames += struct.pack('<h', int(max(-1.0, min(1.0, lp)) * 32767))
    w = wave.open(out, 'wb')
    w.setnchannels(1); w.setsampwidth(2); w.setframerate(sr)
    w.writeframes(bytes(frames)); w.close()


def sequence(ev, t0, t1):
    seq, last, on, div = [], None, False, 0
    for t, r, v in ev:
        if r == 7: on = (v & 6) == 2
        else: div = v
        if t < t0 or t >= t1: continue
        st = div if on else None
        if st != last: seq.append((round((t - t0) * 1000), st)); last = st
    return seq


def main():
    a = sys.argv[1:]
    ev = events(a[0])
    if len(a) > 1 and a[1] == '--marks':
        marks = [(int(c) / 2e6, n) for c, n in (l.split() for l in open(a[2]) if l.strip())]
        for k, (t0, name) in enumerate(marks):
            t1 = min(marks[k + 1][0] if k + 1 < len(marks) else t0 + 3, t0 + 3)
            print("%-15s %s" % (name, " ".join("%d:%s" % (t, '-' if d is None else d) for t, d in sequence(ev, t0, t1))))
            render(ev, os.path.join(a[3], "%s-%s.wav" % (a[4], name)), t0, t1)
    else:
        t0 = float(a[2]) if len(a) > 2 else ev[0][0]
        t1 = float(a[3]) if len(a) > 3 else ev[-1][0] + 0.2
        render(ev, a[1], t0, t1)


main()
