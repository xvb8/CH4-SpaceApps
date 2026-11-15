"""End-to-end analog scoring on real parsed data.

Reads the two parsed criterion CSVs produced by `python -m parsers.run ...`
(see parsers/criteria.py and parsers/run.py) and feeds them straight into
the two scoring engines:

  * analog_scoring.run_all          - every non-chemistry criterion
  * chemical_composition.score_element - every GRS element pair

Both engines return the same shape: {(mars_loc, earth_loc): score}. We
combine them into one nested {mars: {earth: {criterion: score}}} and print
the top analogs per Mars region.

Default inputs:
    data/parsed/mars_regions_criteria.csv
    data/parsed/earth_sites_criteria.csv

Values that are blank in the CSV stay None, so the criterion is skipped
for that pair (never scored 0). A criterion is only scored where both
planets have data in the CSV; this matches the behaviour documented in
parsers/criteria.py.

Run:
    python run_scoring.py
    python run_scoring.py --mars data/parsed/mars_regions_criteria.csv \
                          --earth data/parsed/earth_sites_criteria.csv \
                          --top 5
"""

import argparse
import csv
import json
import os
import sys

# Ensure stdout can emit UTF-8 on Windows consoles (cp1252 can't do
# characters like "ı" in site names).
if hasattr(sys.stdout, "reconfigure"):
    try:
        sys.stdout.reconfigure(encoding="utf-8")
    except (AttributeError, ValueError):
        pass

from analog_scoring import CRITERIA, run_all
from chemical_composition import GRS_ELEMENTS, score_element


def load_criteria_csv(path):
    """CSV with columns name,lat,lon,<criterion...> -> ([(name,lat,lon)], {criterion: {name: float}}).

    Empty cells become None so the scoring code will skip them.
    """
    if not os.path.exists(path):
        raise FileNotFoundError(path)
    with open(path, newline="", encoding="utf-8") as f:
        reader = csv.DictReader(f)
        rows = list(reader)
    if not rows:
        return [], {}
    meta_cols = {"name", "lat", "lon"}
    criterion_cols = [c for c in reader.fieldnames if c not in meta_cols]
    locations = []
    values = {c: {} for c in criterion_cols}
    for row in rows:
        name = row["name"]
        try:
            lat = float(row["lat"])
            lon = float(row["lon"])
        except (TypeError, ValueError):
            continue
        locations.append((name, lat, lon))
        for c in criterion_cols:
            cell = row.get(c, "")
            if cell is None or cell == "":
                continue
            try:
                values[c][name] = float(cell)
            except ValueError:
                continue
    return locations, values


def split_chem(values):
    """Pull chemical_composition_<el> columns out of a {criterion: {loc: v}} map."""
    chem, other = {}, {}
    for col, data in values.items():
        if col.startswith("chemical_composition_"):
            el = col[len("chemical_composition_"):]
            if el in GRS_ELEMENTS:
                chem[el] = data
                continue
        other[col] = data
    return chem, other


def score_chemistry(mars_chem, earth_chem):
    """Mirror of chemical_composition.score_elements, but without re-applying
    to_scoring_units (parsers/criteria.py already converted Th to ppm)."""
    shared = sorted(set(mars_chem) & set(earth_chem))
    return {f"chemical_composition_{el}":
            score_element(mars_chem[el], earth_chem[el], element=None)
            for el in shared}


def score_other(mars_other, earth_other):
    """Run analog_scoring on every criterion present on both sides."""
    datasets = {c: (mars_other[c], earth_other[c])
                for c in CRITERIA
                if c in mars_other and c in earth_other}
    if not datasets:
        return {}, []
    return run_all(datasets, parallel=False), sorted(datasets)


def combine(criterion_scores):
    """{criterion: {(m,e): s}} -> {mars: {earth: {criterion: s}}}."""
    out = {}
    for crit, pairs in criterion_scores.items():
        for (m, e), s in pairs.items():
            out.setdefault(m, {}).setdefault(e, {})[crit] = s
    return out


def rank_pairs(combined):
    """Mean score per (mars, earth); drops pairs with no overlapping criterion."""
    ranked = {}
    for m, earths in combined.items():
        rows = []
        for e, crit_scores in earths.items():
            good = [s for s in crit_scores.values() if s is not None]
            if not good:
                continue
            rows.append((e, sum(good) / len(good), len(good)))
        rows.sort(key=lambda r: r[1], reverse=True)
        ranked[m] = rows
    return ranked


def print_report(ranked, top=5):
    for m, rows in ranked.items():
        print(f"\n=== {m} ===")
        if not rows:
            print("  no overlapping criteria with any Earth site")
            continue
        for e, score, n in rows[:top]:
            print(f"  {score:.3f}  ({n:>2d} criteria)  {e}")


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--mars", default="data/parsed/mars_regions_criteria.csv")
    ap.add_argument("--earth", default="data/parsed/earth_sites_criteria.csv")
    ap.add_argument("--top", type=int, default=5, help="Top N Earth analogs per Mars region (default 5)")
    ap.add_argument("--json", action="store_true", help="Dump full combined scores as JSON instead of the ranked report")
    args = ap.parse_args(argv)

    _, mars_values = load_criteria_csv(args.mars)
    _, earth_values = load_criteria_csv(args.earth)

    mars_chem, mars_other = split_chem(mars_values)
    earth_chem, earth_other = split_chem(earth_values)

    chem_scores = score_chemistry(mars_chem, earth_chem)
    other_scores, other_cols = score_other(mars_other, earth_other)
    all_scores = {**other_scores, **chem_scores}

    print(f"Mars criteria loaded   : {sorted(mars_values)}", file=sys.stderr)
    print(f"Earth criteria loaded  : {sorted(earth_values)}", file=sys.stderr)
    print(f"Scored (non-chem)      : {other_cols}", file=sys.stderr)
    print(f"Scored (chemistry)     : {sorted(set(mars_chem) & set(earth_chem))}", file=sys.stderr)

    combined = combine(all_scores)
    if args.json:
        json.dump(combined, sys.stdout, indent=2, default=str)
        print()
        return
    print_report(rank_pairs(combined), top=args.top)


if __name__ == "__main__":
    main()
