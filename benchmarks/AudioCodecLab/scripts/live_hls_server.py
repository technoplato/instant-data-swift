#!/usr/bin/env python3
"""Serves a segment folder as a live HLS EVENT playlist that grows in real time (#1012, ADR 0021).

    live_hls_server.py <segments-dir> --port 8765 [--finality 10] [--upload 1.5] [--elapsed 0] [--pause 90:120]
        [--changing-comment]

Audio time 0 is "captured" `--elapsed` seconds before the server starts (a listener who opens a recording that has
been running for a while). Segment n becomes listed once its last sample exists, plus
`--finality` seconds (the writer reads the master file that far behind its end, so mixed system audio is final) plus
`--upload` seconds (upload and manifest sync). `--pause a:b` lists nothing new between a and b seconds after capture
start (the phone offline). `--changing-comment` adds a comment line that changes on every request, to see whether a
playlist whose text changes without a new segment keeps a player alive through a pause. The playlist is VOD-complete
(EXT-X-ENDLIST) once every segment is out.

Measured 2026-10-23 (macOS 26.5): AVPlayer given an EVENT playlist that lists no segment yet fails for good with
CoreMedia -12888 "Playlist File unchanged for longer than 1.5 * target duration"; so does a playlist that stops growing.

It prints {"captureStart": <epoch seconds>} first, then one JSON line per request. It also rewrites
<segments-dir>/live-file.m3u8 every half second with absolute http URIs, to test a file:// playlist.
"""
import argparse
import http.server
import json
import os
import re
import threading
import time


def parse_vod(path):
    init_uri, segments, duration = None, [], None
    for line in open(path):
        line = line.strip()
        m = re.match(r'#EXT-X-MAP:URI="([^"]+)"', line)
        if m:
            init_uri = m.group(1)
        elif line.startswith("#EXTINF:"):
            duration = float(line[len("#EXTINF:") :].split(",")[0])
        elif line and not line.startswith("#"):
            segments.append((line, duration))
    return init_uri, segments


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("directory")
    parser.add_argument("--port", type=int, default=8765)
    parser.add_argument("--finality", type=float, default=10.0)
    parser.add_argument("--upload", type=float, default=1.5)
    parser.add_argument("--elapsed", type=float, default=0.0)
    parser.add_argument("--pause", default=None)
    parser.add_argument("--changing-comment", action="store_true")
    args = parser.parse_args()

    directory = os.path.abspath(args.directory)
    init_uri, segments = parse_vod(os.path.join(directory, "vod.m3u8"))
    target = max(1, int(max(d for _, d in segments) + 0.999))
    ends, t = [], 0.0
    for _, d in segments:
        t += d
        ends.append(t)
    capture_start = time.time() - args.elapsed
    pause = tuple(float(x) for x in args.pause.split(":")) if args.pause else None
    print(json.dumps({"kind": "server", "captureStart": capture_start, "segments": len(segments), "target": target}), flush=True)

    def playlist(absolute_base=""):
        now = time.time() - capture_start
        if pause and pause[0] <= now < pause[1]:
            now = pause[0]
        available = [i for i, end in enumerate(ends) if end + args.finality + args.upload <= now]
        lines = [
            "#EXTM3U",
            "#EXT-X-VERSION:7",
            f"#EXT-X-TARGETDURATION:{target}",
            "#EXT-X-MEDIA-SEQUENCE:0",
            "#EXT-X-PLAYLIST-TYPE:EVENT",
            "#EXT-X-INDEPENDENT-SEGMENTS",
            f'#EXT-X-MAP:URI="{absolute_base}{init_uri}"',
        ]
        for i in available:
            name, d = segments[i]
            lines.append(f"#EXTINF:{d:.5f},")
            lines.append(f"{absolute_base}{name}")
        if args.changing_comment:
            lines.append(f"## served {time.time():.3f}")
        if len(available) == len(segments):
            lines.append("#EXT-X-ENDLIST")
        return "\n".join(lines) + "\n", len(available)

    class Handler(http.server.SimpleHTTPRequestHandler):
        def __init__(self, *a, **k):
            super().__init__(*a, directory=directory, **k)

        def log_message(self, *a):
            pass

        def do_GET(self):
            now = time.time() - capture_start
            if self.path.startswith("/live.m3u8"):
                body, listed = playlist()
                data = body.encode()
                self.send_response(200)
                self.send_header("Content-Type", "application/vnd.apple.mpegurl")
                self.send_header("Content-Length", str(len(data)))
                self.send_header("Cache-Control", "no-cache")
                self.send_header("Access-Control-Allow-Origin", "*")
                self.end_headers()
                self.wfile.write(data)
                print(json.dumps({"kind": "request", "t": round(now, 2), "path": "/live.m3u8", "listed": listed}), flush=True)
                return
            print(json.dumps({"kind": "request", "t": round(now, 2), "path": self.path}), flush=True)
            super().do_GET()

        def end_headers(self):
            self.send_header("Access-Control-Allow-Origin", "*")
            super().end_headers()

    def rewrite_file_playlist():
        base = f"http://127.0.0.1:{args.port}/"
        path = os.path.join(directory, "live-file.m3u8")
        while True:
            body, _ = playlist(base)
            tmp = path + ".tmp"
            with open(tmp, "w") as f:
                f.write(body)
            os.replace(tmp, path)
            time.sleep(0.5)

    threading.Thread(target=rewrite_file_playlist, daemon=True).start()
    http.server.ThreadingHTTPServer(("127.0.0.1", args.port), Handler).serve_forever()


if __name__ == "__main__":
    main()
