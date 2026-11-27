#!/usr/bin/env python3
"""Audio manifest for the audio-first director.

Scans godot/assets/audio/<folder>/ for .wav and .ogg clips and writes exact durations to
godot/data/audio_manifest.json, so shot timing always matches the recorded dialogue.

  python3 tools/sync_audio_manifest.py            # write the manifest
  python3 tools/sync_audio_manifest.py --check    # also check every episode against it

--check reports, per episode: lines whose clip is not recorded yet (text fallback, 0.065 s/char),
lines that overlap for the same character, and shots whose fixed duration is shorter than their
dialogue. It exits with status 1 if anything needs attention.
"""

import json
import os
import struct
import sys
import wave

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "godot")
AUDIO = os.path.join(ROOT, "assets", "audio")
MANIFEST = os.path.join(ROOT, "data", "audio_manifest.json")
EPISODES = os.path.join(ROOT, "data", "episodes")
SEC_PER_CHAR = 0.065


def wav_seconds(path):
    with wave.open(path, "rb") as w:
        return w.getnframes() / float(w.getframerate())


def ogg_seconds(path):
    """Vorbis or Opus: last page granule position / sample rate."""
    data = open(path, "rb").read()
    rate = None
    i = data.find(b"\x01vorbis")
    if i >= 0:
        rate = struct.unpack_from("<I", data, i + 12)[0]
    elif data.find(b"OpusHead") >= 0:
        rate = 48000
    if not rate:
        raise ValueError("unknown ogg codec")
    last = data.rfind(b"OggS")
    granule = struct.unpack_from("<q", data, last + 6)[0]
    if data.find(b"OpusHead") >= 0:
        pre_skip = struct.unpack_from("<H", data, data.find(b"OpusHead") + 10)[0]
        granule -= pre_skip
    return granule / float(rate)


def scan():
    files = {}
    if not os.path.isdir(AUDIO):
        return files
    for folder, _, names in os.walk(AUDIO):
        for name in sorted(names):
            path = os.path.join(folder, name)
            rel = os.path.relpath(path, AUDIO).replace(os.sep, "/")
            try:
                if name.lower().endswith(".wav"):
                    files[rel] = round(wav_seconds(path), 4)
                elif name.lower().endswith(".ogg"):
                    files[rel] = round(ogg_seconds(path), 4)
            except Exception as e:  # unreadable clip: report, keep going
                print("  ! could not read %s: %s" % (rel, e))
    return files


def line_length(event, files):
    if float(event.get("duration", -1)) > 0:
        return float(event["duration"]), "duration"
    audio = event.get("audio", "")
    if audio in files:
        return files[audio], "clip"
    return max(0.5, len(event.get("text", "")) * SEC_PER_CHAR), "text"


def check(files):
    problems = 0
    if not os.path.isdir(EPISODES):
        return 0
    for name in sorted(os.listdir(EPISODES)):
        if not name.endswith(".json"):
            continue
        ep = json.load(open(os.path.join(EPISODES, name)))
        print("\n%s (%s)" % (ep.get("episode_id", name), ep.get("title", "")))
        for shot in ep.get("shots", []):
            busy = {}
            talk_end = 0.0
            for e in sorted(shot.get("events", []), key=lambda e: float(e.get("t", 0))):
                if e.get("action") != "talk":
                    continue
                t = float(e.get("t", 0))
                length, source = line_length(e, files)
                actor = e.get("actor", "")
                if source == "text":
                    print("  · %s %s: %s not recorded yet (text timing %.2f s)" % (shot["id"], actor, e.get("audio", "(no path)"), length))
                if actor in busy and t < busy[actor] - 1e-3:
                    print("  ! %s %s: line at %.2f s starts before the previous one ends (%.2f s)" % (shot["id"], actor, t, busy[actor]))
                    problems += 1
                busy[actor] = t + length
                talk_end = max(talk_end, t + length)
            if not shot.get("auto_advance_on_audio", True) and "duration" in shot and float(shot["duration"]) < talk_end:
                print("  ! %s: duration %.2f s is shorter than its dialogue (%.2f s)" % (shot["id"], float(shot["duration"]), talk_end))
                problems += 1
    return problems


def main():
    files = scan()
    os.makedirs(os.path.dirname(MANIFEST), exist_ok=True)
    with open(MANIFEST, "w") as f:
        json.dump({"files": files}, f, indent=1, sort_keys=True)
        f.write("\n")
    print("wrote %s (%d clips)" % (os.path.relpath(MANIFEST), len(files)))
    for rel, sec in sorted(files.items()):
        print("  %-40s %7.3f s" % (rel, sec))
    if "--check" in sys.argv:
        problems = check(files)
        print("\n%s" % ("all episodes in sync" if problems == 0 else "%d problem(s)" % problems))
        sys.exit(1 if problems else 0)


main()
