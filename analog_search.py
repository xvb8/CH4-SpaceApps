"""Find the best Earth analogs for a Mars target without scoring every Earth cell.

Pipeline (see pipeline.md and docs/analog_search_journey.md):
  data -> parsing -> s_ik per criterion -> w_k(m) from std dev + importance
       -> final score S_i(m) -> pruned search and sorting -> Earth analogs

1. Weights. v_k needs similarities of the Earth candidates, so it is estimated
   from a random sample of Earth cells, then w_k(m) is frozen.
2. Hard filters. Cells whose similarity on a required criterion is below a
   minimum are dropped.
3. Zoom pyramid. Earth cells are grouped into 5°, 10°, ... blocks storing the
   min / max raw value of each criterion (cheap, coarse products).
4. Branch and bound. A block's upper bound is the best Gower average its
   criteria could reach given those min / max values. Blocks are opened
   best-bound first; any block whose bound is below the current K-th best
   score is dropped. The result is exact for the frozen weights.
5. Cheap criteria first. Full-resolution cells are scored criterion by
   criterion, cheapest / heaviest first. Unscored criteria are assumed to be 1;
   scoring stops as soon as that bound falls below the K-th best.

Scores come from site_weights.py (similarity, mission_weights,
final_similarity_score), so this file always agrees with it.
"""
import heapq
import itertools
import json
import math
import os
import random
import sys

try:
    HERE = os.path.dirname(os.path.abspath(__file__))
except NameError:  # Workspaces kernel may run without __file__
    HERE = os.getcwd()
sys.path.insert(0, HERE)

import site_weights as sw  # noqa: E402

# ---------------- Inputs (edit these) ----------------
EARTH_GRID_PATH = os.path.join(HERE, "data", "earth_grid.json")
MARS_REGIONS_PATH = os.path.join(HERE, "data", "mars_regions.json")

# When True, criteria are derived from the data file's own header (intersected
# with scoring rules known to site_weights). This keeps the search aligned
# with whatever criterion ids the website / parsers ship (see js/criteria.js
# and data/earth_grid.json). Set to False to force the full 14-key schema.
USE_DATAFILE_CRITERIA = True

# Fallback / additional rules for criterion ids that the website uses but are
# not in site_weights.rules (the UI rolls the 5 mineral subs into one
# "geology" criterion). The rule is identical to "basaltic" so mineral sites
# still score well; override here without touching site_weights.py.
EXTRA_RULES = {
    "geology": {"type": "basic"},
}

MARS_TARGETS = None          # list of Mars region names, or None for all regions
SHOW_DETAIL_FOR = ["Jezero Crater", "Gale Crater", "Utopia Planitia"]
MISSIONS = sw.mission_fidelity   # mission -> f_k(m) in criteria order

TOP_K = 5                    # how many analogs to return per target and mission
SAMPLE_SIZE = 200            # Earth cells sampled to estimate v_k
RANDOM_SEED = 42
PYRAMID_LEVELS = 5           # block sizes: 2.5° x 2^1 ... 2^5 (5° to 80°)

# Relative cost of scoring one criterion on one full-resolution cell.
# Keys cover both the full (14-key) and UI (9-key, geology aggregate) schemes.
CRITERION_COST = {
    "basaltic": 3, "phyllosilicates": 3, "sulfates": 3, "carbonates": 3, "silica": 3,
    "geology": 3,
    "topography": 1, "aeolian": 4, "caves": 5,
    "temperature": 1, "aridity": 1, "dust": 2,
    "ice": 2, "salts": 3, "periglacial": 5,
}

# Hard filters: criterion -> minimum similarity. A cell is dropped if that
# criterion is missing or below the minimum. Example: {"aridity": 0.5}
HARD_FILTERS = {}

RUN_BRUTE_FORCE_CHECK = True
# ------------------------------------------------------


def datafile_criteria(earth_path, mars_path):
    """Intersect the criteria listed in the two data files with the rules
    known to site_weights (+ EXTRA_RULES). Order follows the Earth file."""
    with open(earth_path) as f:
        earth_cols = json.load(f).get("columns", [])
    with open(mars_path) as f:
        mars_file = json.load(f)
    mars_cols = set(mars_file.get("criteria", []))
    if not mars_cols and mars_file.get("regions"):
        mars_cols = set(mars_file["regions"][0].get("values", {}))
    known = {**sw.rules, **EXTRA_RULES}
    order = [c for c in earth_cols if c in known and c in mars_cols]
    if not order:
        return None
    # Mission fidelity f_k(m) is indexed by site_weights.criteria order; when
    # the data file has fewer criteria the fidelities must be re-indexed.
    return order


def build_criteria_and_rules():
    """Return (CRITERIA, RULES, fidelity_by_mission) in the active order."""
    rules = {**sw.rules, **EXTRA_RULES}
    criteria = None
    if USE_DATAFILE_CRITERIA:
        criteria = datafile_criteria(EARTH_GRID_PATH, MARS_REGIONS_PATH)
    if not criteria:
        criteria = sw.criteria
    rule_list = [rules[c] for c in criteria]
    # Re-index mission fidelities to match the active criteria order. Missing
    # entries default to the mean of that mission (so the criterion still
    # contributes without us having to invent a bespoke value).
    sw_idx = {c: i for i, c in enumerate(sw.criteria)}
    fidelities = {}
    for name, f in MISSIONS.items():
        mean_f = sum(f) / len(f)
        fidelities[name] = [f[sw_idx[c]] if c in sw_idx else mean_f for c in criteria]
    return criteria, rule_list, fidelities


CRITERIA, RULES, FIDELITY = build_criteria_and_rules()
K = len(CRITERIA)


# ---------- data parsing ----------

def _row_to_values(get):
    """Build a criteria-ordered value list from a column getter (None = missing).

    Columns in the data file are now matched to criteria by exact id, so the
    criteria list produced by `build_criteria_and_rules` reads cleanly even
    for schemas that don't cover every criterion.
    """
    return [get(c) for c in CRITERIA]


def load_earth(path):
    with open(path) as f:
        g = json.load(f)
    idx = {c: i for i, c in enumerate(g["columns"])}
    cells = []
    for p in g["points"]:
        get = lambda col: p[idx[col]] if col in idx else None  # noqa: E731
        cells.append({"lat": p[idx["lat"]], "lon": p[idx["lon"]], "values": _row_to_values(get)})
    return g["step_deg"], cells


def load_mars(path):
    with open(path) as f:
        m = json.load(f)
    return {r["name"]: _row_to_values(lambda col, r=r: r["values"].get(col)) for r in m["regions"]}


# ---------- weights ----------

def target_spread(cells, target, sample_idx):
    """v_k estimated from the sampled Earth cells. s_ik does not depend on the
    mission, so this is computed once per Mars target and shared by all missions."""
    S = {i: [sw.similarity(RULES[k], cells[i]["values"][k], target[k]) for k in range(K)] for i in sample_idx}
    means = sw.criterion_means(S, K)
    evals = sum(1 for s in S.values() for x in s if x is not None)
    return sw.criterion_spread(S, means), evals


# ---------- zoom pyramid and bounds ----------

def build_pyramid(cells, step, levels):
    """Return {level: {block_key: block}}; level 0 blocks are single cells."""
    def key(lat, lon, size):
        return (math.floor((lat + 90) / size), math.floor((lon + 180) / size))

    pyramid = {}
    for lvl in range(levels + 1):
        size = step * 2 ** lvl
        blocks = {}
        for i, c in enumerate(cells):
            b = blocks.setdefault(key(c["lat"], c["lon"], size), {
                "level": lvl, "cells": [], "lo": [None] * K, "hi": [None] * K,
                "n_present": [0] * K, "children": set(),
            })
            b["cells"].append(i)
            for k, e in enumerate(c["values"]):
                if e is None:
                    continue
                b["n_present"][k] += 1
                b["lo"][k] = e if b["lo"][k] is None else min(b["lo"][k], e)
                b["hi"][k] = e if b["hi"][k] is None else max(b["hi"][k], e)
            if lvl > 0:
                b["children"].add(key(c["lat"], c["lon"], step * 2 ** (lvl - 1)))
        pyramid[lvl] = blocks
    return pyramid


def best_similarity_in_range(rule, lo, hi, m):
    """Highest rule(e, m) for any e in [lo, hi].

    Every rule peaks where e is closest to m, except "basic" / "basicLog",
    which switch formula at e = 0. So the max is among clamp(m), the two ends and 0.
    """
    candidates = {min(max(m, lo), hi), lo, hi}
    if lo <= 0 <= hi:
        candidates.add(0.0)
    return max(sw.similarity(rule, e, m) for e in candidates)


def gower_upper_bound(forced, optional):
    """Max of Σ w·u / Σ w over every present set (forced ∪ any subset of optional).

    forced / optional: lists of (w, u). Adding an optional term raises the
    average only if its u is above the current average, so add them greedily
    from the largest u.
    """
    num = sum(w * u for w, u in forced)
    den = sum(w for w, _ in forced)
    for w, u in sorted(optional, key=lambda t: -t[1]):
        if den == 0 or u > num / den:
            num += w * u
            den += w
    return num / den if den else 0.0


def block_bound(block, target, weights):
    """Upper bound on S_i(m) over every cell in the block; -1 if a hard filter rules it out."""
    n = len(block["cells"])
    forced, optional = [], []
    for k in range(K):
        has_data = block["n_present"][k] > 0 and target[k] is not None
        u = best_similarity_in_range(RULES[k], block["lo"][k], block["hi"][k], target[k]) if has_data else None
        need = HARD_FILTERS.get(CRITERIA[k])
        if need is not None and (u is None or u < need):
            return -1.0
        if u is None or weights[k] == 0:
            continue
        (forced if block["n_present"][k] == n else optional).append((weights[k], u))
    return gower_upper_bound(forced, optional)


# ---------- full-resolution scoring ----------

def score_cell_staged(values, target, weights, order, cutoff, stats):
    """Score criteria in `order`; stop once the bound (unscored = 1) drops below cutoff.

    Returns the final score, or None if the cell was stopped early or failed a filter.
    """
    present = [k for k in order if values[k] is not None and target[k] is not None and weights[k] > 0]
    num = den = 0.0
    remaining_w = sum(weights[k] for k in present)
    for k in present:
        s = sw.similarity(RULES[k], values[k], target[k])
        stats["criterion_evals"] += 1
        need = HARD_FILTERS.get(CRITERIA[k])
        if need is not None and s < need:
            return None
        num += weights[k] * s
        den += weights[k]
        remaining_w -= weights[k]
        if cutoff is not None and (num + remaining_w) / (den + remaining_w) < cutoff:
            stats["stopped_early"] += 1
            return None
    for c, need in HARD_FILTERS.items():   # required criterion with no data
        k = CRITERIA.index(c)
        if values[k] is None or target[k] is None:
            return None
    return num / den if den else 0.0


def search(cells, pyramid, target, weights, top_k):
    """Best-first branch and bound. Returns (top list of (score, cell_idx), stats)."""
    stats = {"blocks_bounded": 0, "blocks_pruned": 0, "cells_scored": 0,
             "cells_skipped": 0, "criterion_evals": 0, "stopped_early": 0}
    # Cheap and heavy first: highest weight per unit cost.
    order = sorted(range(K), key=lambda k: -(weights[k] / CRITERION_COST.get(CRITERIA[k], 1)))
    top = []                     # min-heap of (score, cell_idx), size <= top_k
    tie = itertools.count()
    queue = []                   # max-heap via negative bound
    top_level = max(pyramid)
    for key, b in pyramid[top_level].items():
        bound = block_bound(b, target, weights)
        stats["blocks_bounded"] += 1
        if bound >= 0:
            heapq.heappush(queue, (-bound, next(tie), top_level, key))
        else:
            stats["blocks_pruned"] += 1

    def cutoff():
        return top[0][0] if len(top) == top_k else None

    while queue:
        neg_bound, _, lvl, key = heapq.heappop(queue)
        c = cutoff()
        if c is not None and -neg_bound < c:
            # Best-first: nothing left in the queue can beat the K-th best.
            stats["blocks_pruned"] += 1 + len(queue)
            break
        b = pyramid[lvl][key]
        if lvl == 0:
            i = b["cells"][0]
            stats["cells_scored"] += 1
            score = score_cell_staged(cells[i]["values"], target, weights, order, c, stats)
            if score is None:
                continue
            if len(top) < top_k:
                heapq.heappush(top, (score, i))
            elif score > top[0][0]:
                heapq.heapreplace(top, (score, i))
            continue
        for child_key in b["children"]:
            child = pyramid[lvl - 1][child_key]
            if lvl - 1 == 0:
                # Full-resolution cells inherit the parent bound: bounding them
                # would mean scoring them, which is the expensive step.
                heapq.heappush(queue, (neg_bound, next(tie), 0, child_key))
                continue
            bound = block_bound(child, target, weights)
            stats["blocks_bounded"] += 1
            if bound < 0 or (c is not None and bound < c):
                stats["blocks_pruned"] += 1
                continue
            heapq.heappush(queue, (-bound, next(tie), lvl - 1, child_key))
    stats["cells_skipped"] = len(cells) - stats["cells_scored"]
    return sorted(top, reverse=True), stats


# ---------- brute force check ----------

def brute_force(cells, target, weights, top_k):
    scored, evals = [], 0
    for i, c in enumerate(cells):
        s = [sw.similarity(RULES[k], c["values"][k], target[k]) for k in range(K)]
        evals += sum(1 for k in range(K) if s[k] is not None and weights[k] > 0)
        if any(s[CRITERIA.index(cr)] is None or s[CRITERIA.index(cr)] < need for cr, need in HARD_FILTERS.items()):
            continue
        scored.append((sw.final_similarity_score(s, weights), i))
    return sorted(scored, reverse=True)[:top_k], evals


def exact_spread(cells, target):
    """v_k from every Earth cell (what sampling approximates)."""
    return target_spread(cells, target, range(len(cells)))[0]


def fmt_cell(c):
    return f"({c['lat']:+7.2f}, {c['lon']:+8.2f})"


def main():
    step, cells = load_earth(EARTH_GRID_PATH)
    mars = load_mars(MARS_REGIONS_PATH)
    targets = MARS_TARGETS or list(mars)
    missing = [c for k, c in enumerate(CRITERIA) if all(cell["values"][k] is None for cell in cells)]
    pyramid = build_pyramid(cells, step, PYRAMID_LEVELS)
    rng = random.Random(RANDOM_SEED)
    sample_idx = rng.sample(range(len(cells)), min(SAMPLE_SIZE, len(cells)))

    print(f"Earth cells: {len(cells)} at {step}°, Mars targets: {len(targets)}, missions: {len(FIDELITY)}, "
          f"criteria: {K} ({', '.join(CRITERIA)}), top-K: {TOP_K}, v_k sample: {len(sample_idx)}")
    if missing:
        print(f"WARNING: no Earth data for {missing}; these are skipped (weight has no effect).")
    if HARD_FILTERS:
        print(f"Hard filters: {HARD_FILTERS}")

    totals = {"runs": 0, "exact": 0, "same_as_exact_weights": 0, "same_top1_exact_weights": 0, "cells_scored": 0,
              "criterion_evals": 0, "brute_evals": 0, "sample_evals": 0}
    for name in targets:
        target = mars[name]
        spread, sample_evals = target_spread(cells, target, sample_idx)
        totals["sample_evals"] += sample_evals
        full_spread = exact_spread(cells, target) if RUN_BRUTE_FORCE_CHECK else None
        for mission, fidelity in FIDELITY.items():
            weights = sw.mission_weights(fidelity, spread)
            top, stats = search(cells, pyramid, target, weights, TOP_K)
            totals["runs"] += 1
            totals["cells_scored"] += stats["cells_scored"]
            totals["criterion_evals"] += stats["criterion_evals"]

            if RUN_BRUTE_FORCE_CHECK:
                bf_top, bf_evals = brute_force(cells, target, weights, TOP_K)
                totals["brute_evals"] += bf_evals
                same = [i for _, i in top] == [i for _, i in bf_top] and all(
                    abs(a - b) < 1e-12 for (a, _), (b, _) in zip(top, bf_top))
                totals["exact"] += same
                ex_top, _ = brute_force(cells, target, sw.mission_weights(fidelity, full_spread), TOP_K)
                totals["same_as_exact_weights"] += {i for _, i in top} == {i for _, i in ex_top}
                totals["same_top1_exact_weights"] += top[0][1] == ex_top[0][1]

            if name in SHOW_DETAIL_FOR:
                print(f"\n=== {name} | {mission} ===")
                print(f"  cells scored {stats['cells_scored']}/{len(cells)}, "
                      f"criterion evals {stats['criterion_evals']}, stopped early {stats['stopped_early']}, "
                      f"blocks bounded {stats['blocks_bounded']}, pruned {stats['blocks_pruned']}")
                for rank, (score, i) in enumerate(top, 1):
                    print(f"  {rank}. {fmt_cell(cells[i])}  final similarity score {score:.4f}")
                if RUN_BRUTE_FORCE_CHECK:
                    print(f"  matches brute force: {same}")

    print("\n=== Summary over all targets and missions ===")
    r = totals["runs"]
    print(f"  runs: {r}")
    print(f"  full-resolution cells scored: {totals['cells_scored'] / r:.1f} of {len(cells)} per run "
          f"({100 * totals['cells_scored'] / (r * len(cells)):.1f}%)")
    if RUN_BRUTE_FORCE_CHECK:
        search_cost = totals["criterion_evals"] + totals["sample_evals"]
        print(f"  criterion evaluations: search {totals['criterion_evals']} + v_k sample {totals['sample_evals']} "
              f"= {search_cost} vs brute force {totals['brute_evals']} "
              f"({100 * search_cost / totals['brute_evals']:.1f}%)")
        print(f"  top-{TOP_K} identical to brute force (same weights): {totals['exact']}/{r}")
        print(f"  top-{TOP_K} set identical with exact (all-cell) weights: {totals['same_as_exact_weights']}/{r}")
        print(f"  #1 analog identical with exact (all-cell) weights: {totals['same_top1_exact_weights']}/{r}")
    return totals


if __name__ == "__main__":
    main()
