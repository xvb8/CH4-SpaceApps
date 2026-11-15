"""Mission-specific criterion weights and final similarity score.

Step 1: s_ik   = rule_k(e_ik, m_k)                     similarity of site i to the Mars target on criterion k
Step 2: s̄_k    = (1/N) Σ_i s_ik                        mean similarity of criterion k
Step 3: v_k    = sqrt[(1/N) Σ_i (s_ik - s̄_k)^2]         discriminating power (population std)
Step 4: w_k(m) = f_k(m)·v_k / Σ_j [f_j(m)·v_j]           normalized weight for mission m
Step 5: S_i(m) = Σ_k w_k(m)·s_ik / Σ_k w_k(m)            final similarity score (weighted average)

Missing values (None) are skipped for that site: they are left out of s̄_k, v_k
and the Step 5 sums, never scored as 0. With no missing values the Step 5
denominator is 1, so S_i(m) = Σ_k w_k(m)·s_ik.

Running this file prints the final similarity score. analog_search.py imports
the functions below.
"""
import math

# ---------------- Inputs (edit these) ----------------
# Criteria for similarities (k), grouped by category, per datasources.md.
categories = {
    "Rocks and minerals": [
        "basaltic",           # Earth: ASTER-GED AG100 mafic index | Mars: TES olivine/pyroxene
        "phyllosilicates",    # clay. Earth: EMIT L2B | Mars: CRISM D2300, BD2210, BD1900
        "sulfates",           # Earth: EMIT L2B gypsum | Mars: CRISM SINDEX, BD2100, BD1900
        "carbonates",         # Earth: EMIT L2B calcite/dolomite | Mars: CRISM BD2500, BD3900
        "silica",             # silica/evaporites. Earth: AG100 quartz index | Mars: CRISM hydrated silica
    ],
    "Landforms and terrain": [
        "topography",         # Earth: Copernicus DEM, 3DEP (US) | Mars: MOLA MEGDR
        "aeolian",            # dunes, ripples, megaripples. Earth: Sentinel-2, Landsat | Mars: HiRISE, CTX
        "caves",              # tube diameter, skylight/pit presence. Earth: lava tube DBs | Mars: USGS MGC3
    ],
    "Climate and radiation": [
        "temperature",        # mean, diurnal range, annual minimum. Earth: MODIS, ECOSTRESS | Mars: THEMIS, MCS
        "uv",                 # Earth: TROPOMI surface UV | Mars: modeled UV
        "aridity",            # Earth: ERA5 water vapor, GPM, MODIS NDVI | Mars: MCD water vapor
        "dust",               # dust conditions / storms. Earth: MIDAS, MERRA-2 | Mars: MCS dust opacity
    ],
    "Water, ice, and salts": [
        "ice",                # Earth: ESA CCI permafrost | Mars: Odyssey GRS
        "salts",              # deliquescence time fraction. Earth: ERA5 RH-T | Mars: MCD RH-T
        "periglacial",        # patterned ground & gullies. Earth: PDG ice-wedge polygons | Mars: Noblet et al.
    ],
}
criteria = [c for group in categories.values() for c in group]

# Per-criterion similarity rule s = rule(e, m) comparing an Earth value e with a Mars value m
# (same rules as js/criteria.js; new criteria default to "ratio").
rules = {
    "basaltic":        {"type": "ratio"},
    "phyllosilicates": {"type": "ratio"},
    "sulfates":        {"type": "ratio"},
    "carbonates":      {"type": "ratio"},
    "silica":          {"type": "ratio"},
    "topography":      {"type": "ratio"},
    "aeolian":         {"type": "ratio"},
    "caves":           {"type": "logRatio"},
    "temperature":     {"type": "gap", "scale": 0.1},
    "uv":              {"type": "ratio"},
    "aridity":         {"type": "ratio"},
    "dust":            {"type": "ratio"},
    "ice":             {"type": "ratio"},
    "salts":           {"type": "fraction"},
    "periglacial":     {"type": "match", "threshold": 0.5},
}

# Example similarity scores s_ik (0-1, None = missing), in `criteria` order:
#   basalt, clay, sulf, carb, silica, topo, aeol, caves, temp, uv, arid, dust, ice, salts, perig
# PLACEHOLDER values. Replace with real scores.
site_scores = {
    "Jezero Crater":    [0.60, 0.85, 0.50, 0.90, 0.55, 0.60, 0.55, 0.20, 0.72, 0.40, 0.65, 0.50, 0.30, 0.45, 0.25],
    "Gale Crater":      [0.55, 0.80, 0.85, 0.30, 0.60, 0.55, 0.80, 0.15, 0.68, 0.42, 0.60, 0.65, 0.25, 0.50, 0.20],
    "Utopia Planitia":  [0.70, 0.45, 0.35, 0.20, 0.40, 0.90, 0.40, 0.25, 0.80, 0.45, 0.55, 0.40, 0.90, 0.60, 0.85],
    "Meridiani Planum": [0.50, 0.55, 0.90, 0.25, 0.45, 0.85, 0.75, 0.10, 0.65, 0.41, 0.70, 0.55, 0.20, 0.55, 0.15],
    "Hellas Basin":     [0.75, 0.50, 0.40, 0.25, 0.35, 0.40, 0.50, 0.20, 0.75, 0.55, 0.50, 0.85, 0.75, 0.65, 0.70],
}

# Fidelity importance f_k(m) (0-1 judgment), same order. Geology importance is
# copied to all 5 subcriteria. Dust values are placeholders.
mission_fidelity = {
    "Rover mobility test": [0.2, 0.2, 0.2, 0.2, 0.2, 1.0, 0.8, 0.1, 0.3, 0.1, 0.2, 0.9, 0.2, 0.1, 0.4],
    "Astrobiology":        [1.0, 1.0, 1.0, 1.0, 1.0, 0.3, 0.2, 0.8, 0.6, 0.7, 1.0, 0.3, 0.8, 0.9, 0.6],
    "Habitat analog":      [0.3, 0.3, 0.3, 0.3, 0.3, 0.5, 0.3, 0.9, 0.9, 1.0, 0.6, 0.7, 0.8, 0.3, 0.4],
}
# ------------------------------------------------------


def _ratio(e, m):
    if e == 0 or m == 0:
        return 1 / (1 + abs(e - m))
    return min(e, m) / max(e, m)


def _log_scale(x):
    """Maps [0, 1] onto [0, 1] logarithmically, so a 10x size difference counts as one step."""
    return math.log10(1 + 9 * x)


def similarity(rule, e, m):
    """Step 1: s = rule(e, m) in [0, 1]; None if either value is missing."""
    if e is None or m is None or (isinstance(e, float) and math.isnan(e)) or (isinstance(m, float) and math.isnan(m)):
        return None
    t = rule["type"]
    if t == "ratio":
        return _ratio(abs(e), abs(m))
    if t == "logRatio":
        return _ratio(_log_scale(abs(e)), _log_scale(abs(m)))
    if t == "gap":
        return 1 / (1 + abs(e - m) / rule["scale"])
    if t == "fraction":
        return max(0.0, 1 - abs(e - m))
    if t == "match":
        return 1.0 if (e >= rule["threshold"]) == (m >= rule["threshold"]) else 0.0
    raise ValueError(f"Unknown scoring rule: {t}")


def criterion_means(scores, n_criteria):
    """Step 2: s̄_k = (1/N) Σ_i s_ik, over the sites with data for k."""
    means = []
    for k in range(n_criteria):
        vals = [s[k] for s in scores.values() if s[k] is not None]
        means.append(sum(vals) / len(vals) if vals else 0.0)
    return means


def criterion_spread(scores, means):
    """Step 3: v_k = sqrt[(1/N) Σ_i (s_ik - s̄_k)^2], over the sites with data for k."""
    spread = []
    for k, mean in enumerate(means):
        vals = [s[k] for s in scores.values() if s[k] is not None]
        spread.append(math.sqrt(sum((x - mean) ** 2 for x in vals) / len(vals)) if vals else 0.0)
    return spread


def mission_weights(fidelity, spread):
    """Step 4: w_k(m) = f_k(m)·v_k / Σ_j f_j(m)·v_j"""
    products = [f * v for f, v in zip(fidelity, spread)]
    total = sum(products)
    if total == 0:
        raise ValueError("Σ f_j(m)·v_j is zero; weights undefined for this mission.")
    return [p / total for p in products]


def final_similarity_score(site_score, weight):
    """Step 5: S_i(m) = Σ_k w_k(m)·s_ik / Σ_k w_k(m), over the criteria with data."""
    num = den = 0.0
    for w, s in zip(weight, site_score):
        if s is not None:
            num += w * s
            den += w
    return num / den if den else 0.0


def validate(criteria, scores, fidelity_by_mission):
    K = len(criteria)
    missing_rules = [c for c in criteria if c not in rules]
    if missing_rules:
        raise ValueError(f"No similarity rule for: {missing_rules}")
    for site, s in scores.items():
        if len(s) != K:
            raise ValueError(f"Site '{site}' has {len(s)} scores, expected {K}.")
        if any(x is not None and not 0 <= x <= 1 for x in s):
            raise ValueError(f"Site '{site}' scores must be in [0, 1].")
    for m, f in fidelity_by_mission.items():
        if len(f) != K:
            raise ValueError(f"Mission '{m}' has {len(f)} fidelities, expected {K}.")
        if any(not 0 <= x <= 1 for x in f):
            raise ValueError(f"Mission '{m}' fidelities must be in [0, 1].")


if __name__ == "__main__":
    validate(criteria, site_scores, mission_fidelity)
    K = len(criteria)
    s_bar = criterion_means(site_scores, K)
    v = criterion_spread(site_scores, s_bar)
    weights = {m: mission_weights(f, v) for m, f in mission_fidelity.items()}

    # final_similarity_scores[m][site] = S_i(m)
    final_similarity_scores = {
        m: {site: final_similarity_score(s, w) for site, s in site_scores.items()}
        for m, w in weights.items()
    }

    print(f"N = {len(site_scores)} sites, K = {K} criteria\n")
    print(f"{'criterion':<22}{'s̄_k':>8}{'v_k':>8}")
    k = 0
    for cat, group in categories.items():
        print(f"[{cat}]")
        for c in group:
            print(f"  {c:<20}{s_bar[k]:>8.4f}{v[k]:>8.4f}")
            k += 1

    for m, w in weights.items():
        print(f"\nMission: {m}  (Σw = {sum(w):.4f})")
        k = 0
        for cat, group in categories.items():
            cat_w = sum(w[k:k + len(group)])
            print(f"  [{cat}]  subtotal {cat_w:.4f}")
            for c in group:
                print(f"    {c:<20}{w[k]:>8.4f}")
                k += 1

    print("\n=== Final similarity score S_i(m), ranked ===")
    for m, scores in final_similarity_scores.items():
        print(f"\nMission: {m}")
        for rank, (site, score) in enumerate(
            sorted(scores.items(), key=lambda kv: kv[1], reverse=True), start=1
        ):
            print(f"  {rank}. {site:<20}{score:>8.4f}")
