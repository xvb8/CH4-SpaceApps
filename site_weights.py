"""Mission-specific criterion weights for candidate Mars sites.

Step 2: s̄_k    = (1/N) Σ_i s_ik                      mean similarity of criterion k
Step 3: v_k    = sqrt[(1/N) Σ_i (s_ik - s̄_k)^2]       discriminating power (population std)
Step 4: w_k(m) = f_k(m)·v_k / Σ_j [f_j(m)·v_j]         normalized weight for mission m
"""
import math

# ---------------- Inputs (edit these) ----------------
# Criteria for similarities (k), grouped by category.
# Earth / Mars data sources noted per criterion.
categories = {
    "Rocks and minerals": [
        "geology_minerals",   # basaltic, phyllosilicates/clay, sulfates, carbonates, silica/evaporites
                              #   Earth: ASTER, EMIT, Landsat | Mars: CRISM, OMEGA
    ],
    "Landforms and terrain": [
        "topography",         # Earth: SRTM, Copernicus DEM | Mars: MOLA
        "trafficability",     # rock abundance & slope (slope < 15°, rock abundance < 10%)
                              #   Earth: DEM roughness, day/night ECOSTRESS/MODIS | Mars: THEMIS TI @ 100 m/px
        "aeolian_bedforms",   # dunes, ripples, megaripples
                              #   Earth: Sentinel-2, Landsat dune/ripple maps | Mars: HiRISE, CTX
        "caves",              # shielded subsurface: relative tube diameter, skylight/pit presence
        "volcanic_terrain",   # Earth: DEM + geology data | Mars: MOLA topography + geologic maps
    ],
    "Climate and radiation": [
        "temperature",        # mean, diurnal range, annual minimum
                              #   Earth: MODIS, ECOSTRESS | Mars: THEMIS
        "uv_radiation",       # Earth: UV index (OMI/TROPOMI) | Mars: surface UV index
        "aridity",            # biological habitability
                              #   Earth: aridity index, GPM precip, MODIS NDVI | Mars: water activity, humidity
    ],
    "Water, ice, and salts": [
        "ice_permafrost",     # Earth: permafrost maps | Mars: SHARAD radar, ice-exposing impacts
        "salt_deliquescence", # RH-T envelope
                              #   Earth: ERA5 hourly RH/T time-fraction above each salt's deliquescence point
                              #   Mars: modeled RH-T over chloride and perchlorate deposits
        "periglacial",        # patterned ground & gullies (freeze/thaw)
                              #   Earth: polygon/gully detection, high-res imagery | Mars: HiRISE, CTX
    ],
}
criteria = [c for group in categories.values() for c in group]

# Similarity scores s_ik: site i -> list of scores per criterion k (0-1), in `criteria` order:
#   geology, topo, traffic, aeolian, caves, volcanic, temp, uv, aridity, ice, salt, periglacial
site_scores = {
    "Jezero Crater":    [0.85, 0.60, 0.70, 0.55, 0.20, 0.45, 0.72, 0.40, 0.65, 0.30, 0.45, 0.25],
    "Gale Crater":      [0.78, 0.55, 0.60, 0.80, 0.15, 0.30, 0.68, 0.42, 0.60, 0.25, 0.50, 0.20],
    "Utopia Planitia":  [0.50, 0.90, 0.85, 0.40, 0.25, 0.60, 0.80, 0.45, 0.55, 0.90, 0.60, 0.85],
    "Meridiani Planum": [0.70, 0.85, 0.90, 0.75, 0.10, 0.25, 0.65, 0.41, 0.70, 0.20, 0.55, 0.15],
    "Hellas Basin":     [0.60, 0.40, 0.45, 0.50, 0.20, 0.55, 0.75, 0.55, 0.50, 0.75, 0.65, 0.70],
}

# Fidelity importance f_k(m): mission m -> list per criterion k (0-1 judgment), same order
mission_fidelity = {
    "Rover mobility test": [0.2, 1.0, 1.0, 0.8, 0.1, 0.3, 0.3, 0.1, 0.2, 0.2, 0.1, 0.4],
    "Astrobiology":        [1.0, 0.3, 0.2, 0.2, 0.8, 0.4, 0.6, 0.7, 1.0, 0.8, 0.9, 0.6],
    "Habitat analog":      [0.3, 0.5, 0.6, 0.3, 0.9, 0.5, 0.9, 1.0, 0.6, 0.8, 0.3, 0.4],
}
# ------------------------------------------------------


def criterion_means(scores, n_criteria):
    """s̄_k = (1/N) Σ_i s_ik"""
    N = len(scores)
    return [sum(s[k] for s in scores.values()) / N for k in range(n_criteria)]


def criterion_spread(scores, means):
    """v_k = sqrt[(1/N) Σ_i (s_ik - s̄_k)^2]"""
    N = len(scores)
    return [
        math.sqrt(sum((s[k] - means[k]) ** 2 for s in scores.values()) / N)
        for k in range(len(means))
    ]


def mission_weights(fidelity, spread):
    """w_k(m) = f_k(m)·v_k / Σ_j f_j(m)·v_j"""
    products = [f * v for f, v in zip(fidelity, spread)]
    total = sum(products)
    if total == 0:
        raise ValueError("Σ f_j(m)·v_j is zero; weights undefined for this mission.")
    return [p / total for p in products]


def validate(criteria, scores, fidelity_by_mission):
    K = len(criteria)
    for site, s in scores.items():
        if len(s) != K:
            raise ValueError(f"Site '{site}' has {len(s)} scores, expected {K}.")
        if any(not 0 <= x <= 1 for x in s):
            raise ValueError(f"Site '{site}' scores must be in [0, 1].")
    for m, f in fidelity_by_mission.items():
        if len(f) != K:
            raise ValueError(f"Mission '{m}' has {len(f)} fidelities, expected {K}.")
        if any(not 0 <= x <= 1 for x in f):
            raise ValueError(f"Mission '{m}' fidelities must be in [0, 1].")


validate(criteria, site_scores, mission_fidelity)
K = len(criteria)
s_bar = criterion_means(site_scores, K)
v = criterion_spread(site_scores, s_bar)
weights = {m: mission_weights(f, v) for m, f in mission_fidelity.items()}

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
