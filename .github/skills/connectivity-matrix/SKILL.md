---
name: connectivity-matrix
description: Generates the 8x8 intra-cell peer connectivity matrix from peer pod logs in the swarm-ambient-* / swarm-sidecar-* namespaces of clusters kind-pasta-1 and kind-pasta-2 (the two clusters of the `pasta` cell). Use this skill when asked to build, refresh, regenerate, or check the connectivity matrix for the meshlab pasta cell.
---

# Connectivity Matrix Skill

Produces the markdown table that summarises which `(src peer, dst peer)`
intersections are succeeding inside the `pasta` cell.

## Terminology

- **Cell** — a unit of isolation/scalability composed of one or more clusters
  and other elements. MeshLab currently defines the `pasta` cell (clusters
  `pasta-1`, `pasta-2`); a `pizza` cell may be added later. **Scope of this
  skill is intra-cell only** (pasta).
- **Peer** — one axis label of the matrix, identified by
  `(cluster, namespace)`. Short form: `p<cluster#>/<mode><ns#>`, e.g. `p1/am1`
  = pasta-1 / `swarm-ambient-n1`. The 8 peers are
  `p1/am1, p1/am2, p1/sc1, p1/sc2, p2/am1, p2/am2, p2/sc1, p2/sc2`.
- **Intersection** — one square in the matrix, i.e. an ordered pair
  `(src peer, dst peer)`. ✅ iff at least one observed hop has
  `200 ≤ http.status < 400`, otherwise ❌.

## How to use

Run the script and paste its stdout verbatim. Do **not** read peer logs into
the model context — the script aggregates them locally and emits only the
final 8×8 table, which is the only thing the model needs to see.

```sh
.github/skills/connectivity-matrix/gen-matrix.sh
```

Optional: increase log window per pod (default 500 lines):

```sh
TAIL=2000 .github/skills/connectivity-matrix/gen-matrix.sh
```

## What it does

1. For each peer (`pasta-{1,2}` × `swarm-{ambient,sidecar}-n{1,2}`), tails the
   `peer` container logs of the first pod with `app=peer`.
2. Greps each `hop` JSON line for `src.cluster`, `src.namespace`,
   `dst.cluster`, `dst.namespace`, `http.status`.
3. Marks each `(src peer, dst peer)` intersection ✅ iff at least one observed
   hop has `200 ≤ status < 400`, otherwise ❌.
4. Prints a single markdown table — nothing else — so the entire matrix costs
   ~1 KB of model context regardless of how many log lines were processed.

## Token-efficiency rules

- Always invoke the script; never paste raw `kubectl logs` output into chat.
- Do not pipe the logs through extra `awk`/`sed` previews "to check the
  format" — the script already handles parsing.
- If the user wants a deeper drill-down for a specific intersection, scope
  the follow-up query to that one peer pair instead of dumping all logs again.
