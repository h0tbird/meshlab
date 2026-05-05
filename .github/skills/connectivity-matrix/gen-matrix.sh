#!/usr/bin/env bash
# Generate the cross-cluster swarm peer connectivity matrix from peer pod logs.
# Output: a single 9x9 markdown table on stdout. Nothing else.
#
# A cell is ✅ iff at least one hop log line from src-cell to dst-cell has an
# HTTP status in [200,400). Otherwise ❌.
#
# Env:
#   TAIL  number of log lines to inspect per pod (default 500)
set -euo pipefail

CTXS=(kind-pasta-1 kind-pasta-2)
NSS=(swarm-ambient-n1 swarm-ambient-n2 swarm-sidecar-n1 swarm-sidecar-n2)
TAIL="${TAIL:-500}"

PY=$(mktemp --suffix=.py)
trap 'rm -f "$PY"' EXIT
cat > "$PY" <<'PYEOF'
import sys, re
pat = re.compile(
    r'"src":\s*\{"cluster":"([^"]+)"[^}]*"namespace":"([^"]+)"[^}]*\},\s*'
    r'"dst":\s*\{"cluster":"([^"]+)"[^}]*"namespace":"([^"]+)"[^}]*\},\s*'
    r'"http":\s*\{"status":(\d+)'
)
def short(c, n):
    cs = {"pasta-1": "p1", "pasta-2": "p2"}.get(c, c)
    if n.endswith("ambient-n1"): ns = "am1"
    elif n.endswith("ambient-n2"): ns = "am2"
    elif n.endswith("sidecar-n1"): ns = "sc1"
    elif n.endswith("sidecar-n2"): ns = "sc2"
    else: ns = n
    return f"{cs}/{ns}"
ok = set()
for line in sys.stdin:
    m = pat.search(line)
    if not m: continue
    s = short(m.group(1), m.group(2))
    d = short(m.group(3), m.group(4))
    if 200 <= int(m.group(5)) < 400:
        ok.add((s, d))
L = ["p1/am1","p1/am2","p1/sc1","p1/sc2","p2/am1","p2/am2","p2/sc1","p2/sc2"]
print("| Src \u2193 \\ Dst \u2192 | " + " | ".join(L) + " |")
print("|---|" + "---|"*len(L))
for s in L:
    row = [f"**{s}**"] + [("\u2705" if (s,d) in ok else "\u274c") for d in L]
    print("| " + " | ".join(row) + " |")
PYEOF

{
  for ctx in "${CTXS[@]}"; do
    for ns in "${NSS[@]}"; do
      pod=$(kubectl --context "$ctx" -n "$ns" get pod -l app=peer -o name 2>/dev/null | head -1)
      [ -z "$pod" ] && continue
      kubectl --context "$ctx" -n "$ns" logs "$pod" -c peer --tail="$TAIL" 2>/dev/null \
        || kubectl --context "$ctx" -n "$ns" logs "$pod" --tail="$TAIL" 2>/dev/null || true
    done
  done
} | python3 "$PY"
