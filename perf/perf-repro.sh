#!/bin/sh
# Reproducible measurement for the slow extrude/fillet case (perf.sc, SolidCraft v0.43.0).
# Usage: sh perf-repro.sh /path/to/perf.sc /path/to/solidcraft-cli
# The CLI must be a release build from the commit you are reporting against.
set -e
DESIGN="${1:?pass the design file as the first argument}"
CLI="${2:?pass the solidcraft-cli path as the second argument}"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
cp "$DESIGN" "$WORK/perf.sc"
unzip -o -q "$WORK/perf.sc" -d "$WORK/x"
python3 - "$WORK" << 'PY'
import json, zipfile, sys
work = sys.argv[1]
d = json.load(open(f"{work}/x/document.json"))
container = open(f"{work}/x/container.json").read()
feats = d["features"]
# One variant per timeline length, cache dropped, so every run is a full evaluation.
for n in range(1, len(feats) + 1):
    d2 = dict(d); d2["features"] = feats[:n]
    with zipfile.ZipFile(f"{work}/trunc{n}.sc", "w", zipfile.ZIP_DEFLATED) as z:
        z.writestr("container.json", container)
        z.writestr("document.json", json.dumps(d2))
print(f"built {len(feats)} truncated variants")
PY
echo "== full evaluation, three runs (idle machine) =="
for i in 1 2 3; do /usr/bin/time -h "$CLI" eval "$WORK/trunc18.sc" 2>&1 >/dev/null | grep real; done
echo "== per-feature incremental cost: time to evaluate the first N features =="
for n in $(seq 1 18); do
  printf "N=%2d  " $n
  /usr/bin/time -h "$CLI" eval "$WORK/trunc$n.sc" 2>&1 >/dev/null | grep real
done
echo "== per-feature spans and kernel breakdown (also writes ./trace.json) =="
"$CLI" eval "$WORK/trunc18.sc" --profile --profile-out "$WORK/trace.json" 2>&1 | grep -E "feature |kernel (fillet|boolean|measure|shell|sweep|revolve)|^profile:" || true
cp "$WORK/trace.json" ./trace.json
echo "trace.json written: open in chrome://tracing or ui.perfetto.dev"
