
�
mars_site_weights.py�"""Mission-specific criterion weights for candidate Mars sites.

Step 2: s̄_k    = (1/N) Σ_i s_ik                      mean similarity of criterion k
Step 3: v_k    = sqrt[(1/N) Σ_i (s_ik - s̄_k)^2]       discriminating power (population std)
Step 4: w_k(m) = f_k(m)·v_k / Σ_j [f_j(m)·v_j]         normalized weight for mission m
"""
import math

# ---------------- Inputs (edit these) ----------------
# Criteria names (k)
criteria = ["thermal", "mineralogy", "topography", "atmosphere", "radiation"]

# Similarity scores s_ik: site i -> list of scores per criterion k (0-1)
site_scores = {
    "Jezero Crater":    [0.72, 0.85, 0.60, 0.55, 0.40],
    "Gale Crater":      [0.68, 0.78, 0.55, 0.57, 0.42],
    "Utopia Planitia":  [0.80, 0.50, 0.90, 0.52, 0.45],
    "Meridiani Planum": [0.65, 0.70, 0.85, 0.54, 0.41],
    "Hellas Basin":     [0.75, 0.60, 0.40, 0.70, 0.55],
}

# Fidelity importance f_k(m): mission m -> list per criterion k (0-1 judgment)
mission_fidelity = {
    "Rover mobility test": [0.3, 0.2, 1.0, 0.4, 0.1],
    "Astrobiology":        [0.6, 1.0, 0.3, 0.5, 0.7],
    "Habitat analog":      [0.9, 0.3, 0.5, 0.8, 1.0],
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
print(f"{'criterion':<12}{'s̄_k':>8}{'v_k':>8}")
for k, c in enumerate(criteria):
    print(f"{c:<12}{s_bar[k]:>8.4f}{v[k]:>8.4f}")

for m, w in weights.items():
    print(f"\nMission: {m}  (Σw = {sum(w):.4f})")
    for c, wk in zip(criteria, w):
        print(f"  {c:<12}{wk:>8.4f}")
*
���� 876409bbd4ed40ba86cb2f75dd6448f7