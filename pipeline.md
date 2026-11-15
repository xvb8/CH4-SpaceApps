# CH4 Pipeline

Shared data and scoring pipeline used by the Python batch code
([`analog_scoring.py`](analog_scoring.py:1), [`analog_search.py`](analog_search.py:1),
[`site_weights.py`](site_weights.py:1)) and the website
([`js/scoring.js`](js/scoring.js:1), [`js/analog-search.js`](js/analog-search.js:1),
[`js/app.js`](js/app.js:1)).

```
data -> parsing -> s_ik per criterion -> w_k(m) from std dev + importance
     -> final score S_i(m) -> pruned search and sorting -> Earth analogs
```

## 1. Data

Earth data shipped with the app:

- [`data/earth_sites.json`](data/earth_sites.json:1) — ~30 named sites (Atacama,
  Death Valley, MDRS, ...), each with per-criterion values.
- [`data/earth_grid.json`](data/earth_grid.json:1) — ~1900 cells at 2.5° step.
- [`data/mars_regions.json`](data/mars_regions.json:1) — ~20 Mars anchor regions.

Site + grid rows use the 9-criterion schema defined in
[`js/criteria.js`](js/criteria.js:29):
`geology, topography, aeolian, caves, temperature, aridity, ice, salts, periglacial`.
Datasets with narrow footprints (e.g. Mars ice-wedge coverage, Earth lava-tube
pdfs) have a `coverage` field; values outside coverage are masked to `null` so
the pair is skipped rather than scored as zero.

## 2. Parsing

Raw downloads in `data/real/` and `grs_data/` are converted into the per-site
CSVs in [`data/parsed/`](data/parsed/.folder:1) by [`parsers/`](parsers/__init__.py:1)
and [`parsers/run.py`](parsers/run.py:76). The website and the Python batch
load the same JSON bundles so both paths always see the same numbers.

## 3. Similarity, `s_ik`

For each (site i, criterion k) the rule in
[`CRITERIA[k].rule`](js/criteria.js:29) produces a similarity `s_ik ∈ [0, 1]`:

| rule              | shape                                        |
| ----------------- | -------------------------------------------- |
| `basic`           | smaller ÷ larger; `1 / (1 + |e-m|)` if ≤ 0 |
| `basicLog`        | `basic` on `log10(value + 1)`                |
| `gap`             | `1 / (1 + |e-m| / scale)`                    |
| `fraction`        | `max(0, 1 − |e-m|)`                          |
| `match`           | `0.5` if same side of `PRESENT_AT = 0.5` else `0` |
| `basicOrFraction` | `fraction` if both in `[0,1]` else `basic`   |

Missing values (`null`) propagate — they are **not** scored as zero.

- Python definitions: [`analog_scoring.basic()`](analog_scoring.py:46),
  [`site_weights.similarity()`](site_weights.py:100).
- JS definitions: [`similarity()`](js/scoring.js:61), rules in
  [`RULES`](js/criteria.js:20).

## 4. Weights, `w_k(m)`

For a Mars target `m`:

1. **Criterion spread** `v_k = std_i(s_ik)` — the discriminating power of
   criterion `k` given the Earth candidate population. See
   [`criterionSpread()`](js/scoring.js:80) /
   [`site_weights.criterion_spread()`](site_weights.py:129).
2. **Mission weight** `w_k(m) = f_k(m)·v_k / Σ_j f_j(m)·v_j`, where `f_k(m)`
   is the user-chosen importance slider. See
   [`missionWeights()`](js/scoring.js:87) /
   [`site_weights.mission_weights()`](site_weights.py:138).

The analog-search optimization **freezes** `w_k` from a random sample of
candidates rather than from the full set (see §6).

## 5. Final score, `S_i(m)`

Weighted average (Gower) of the available similarities:

```
S_i(m) = Σ_k w_k·s_ik  /  Σ_k w_k      over criteria with s_ik != null
```

[`scoreLocationsWithWeights()`](js/scoring.js:132) /
[`site_weights.final_similarity_score()`](site_weights.py:147).

## 6. Pruned search and sorting

For the global 2.5° grid, scoring every cell works but
[`analog_search.py`](analog_search.py:1) /
[`js/analog-search.js`](js/analog-search.js:1) do it faster and still
exact (relative to the frozen weights):

1. **Frozen weights.** Sample `SAMPLE_SIZE = 200` Earth cells, estimate `v_k`
   there, compute `w_k(m)` once, and reuse that ruler for every candidate.
   [`frozenWeights()`](js/analog-search.js:67) /
   [`target_spread()`](analog_search.py:159).
2. **Hard filters.** Any cell whose similarity on a required criterion is
   below [`HARD_FILTERS[k]`](js/criteria.js:260) is dropped immediately.
3. **Zoom pyramid.** Grid cells are grouped into `step, 2·step, 4·step, ...`
   blocks (2.5° through 80°) storing the min / max raw value of each
   criterion. [`buildPyramid()`](js/analog-search.js:90) /
   [`build_pyramid()`](analog_search.py:170).
4. **Branch and bound.** A block's upper bound is the best Gower average its
   criteria could reach given those min / max values
   ([`blockBound()`](js/analog-search.js:152)). Blocks are opened best-bound
   first; any block whose bound is below the current K-th best score is
   pruned. The result is exact for the frozen weights.
5. **Cheap criteria first.** Full-resolution cells are scored criterion by
   criterion, ordered by weight / [`CRITERION_COST`](js/criteria.js:240).
   Unscored criteria are assumed to be 1 and scoring stops as soon as that
   bound falls below the K-th best
   ([`scoreCellStaged()`](js/analog-search.js:173)).

On the shipped grid this scores **~2–4% of cells** and does **~5% of the
criterion evaluations** of a brute-force run, with identical top-K.

## 7. Website wiring

[`js/app.js runAnalysis()`](js/app.js:374):

1. Freeze weights on the grid sample ([`frozenWeights`](js/analog-search.js:67)).
2. Score sites + every grid cell with those weights
   ([`scoreLocationsWithWeights`](js/scoring.js:132)) — the heatmap and
   ranking views need a total for every location.
3. Run the pruned search over the grid to report the top-K analog and the
   search statistics ([`search`](js/analog-search.js:249)).
4. The top 5 named sites populate the cards
   ([`renderTopCards`](js/app.js:419)); every scored location feeds the
   Earth heatmap ([`applyLayer`](js/app.js:650)) and the Chart-view
   ranking ([`renderRanking`](js/app.js:617)).

Smoke tests:

- [`tmp/smoke_search.mjs`](tmp/smoke_search.mjs:1) — pyramid + search agree
  with brute force on the real grid for 3 targets.
- [`tmp/smoke_integration.mjs`](tmp/smoke_integration.mjs:1) — mirrors
  `runAnalysis` and checks that the search's top grid cell matches the
  scored grid's top cell.
- `python analog_search.py` — Python end-to-end check (57/57 runs match
  brute force with frozen weights).
