# Finding Earth analogs without scoring all of Earth

How `analog_search.py` finds the best Earth analog for a Mars target and mission, the decisions behind it, and what the measurements showed.

Pipeline (from `pipeline.md`):

```
Data -> data parsing -> similarity score per criterion -> criterion importance from std dev + user input
     -> final score -> optimization and sorting -> Earth analog
```

`site_weights.py` covers the middle steps: similarity rules, s̄_k, v_k, w_k(m) and the final similarity score. `analog_search.py` covers the last step and imports its scoring from `site_weights.py`, so the two always agree. Running `site_weights.py` on its own still prints the final similarity scores.

---

## 1. Criteria: 15, per `datasources.md`

| Category | Criteria |
|---|---|
| Rocks and minerals | basaltic, phyllosilicates, sulfates, carbonates, silica |
| Landforms and terrain | topography, aeolian, caves |
| Climate and radiation | temperature, uv, aridity, dust |
| Water, ice, and salts | ice, salts, periglacial |

- Geology is split into its 5 mineral classes.
- Dust conditions is now a criterion. `datasources.md` gives it data links (MCS dust opacity, MIDAS, MERRA-2) but no full write-up.
- Trafficability and volcanic terrain were removed as outdated.

Each criterion has a similarity rule s = rule(e, m) comparing an Earth value e with a Mars value m. The rules are the same as in `js/criteria.js`:

| Rule | Formula | Used for |
|---|---|---|
| ratio | min ÷ max (if a value is 0: 1 ÷ (1 + abs(e − m))) | geology ×5, topography, aeolian, uv, aridity, dust, ice |
| logRatio | ratio of log-scaled values | caves (Mars lava tubes are 10–100× wider) |
| gap | 1 ÷ (1 + abs(e − m) ÷ 0.1) | temperature |
| fraction | 1 − abs(e − m) | salts |
| match | 1 if both are on the same side of 0.5, else 0 | periglacial |

The 5 geology subclasses and dust default to `ratio`. Change them in `site_weights.rules` if a different rule fits better.

**Mission importance f_k(m)** keeps the 3 missions already in `site_weights.py`:
- Each geology importance value is copied to all 5 subclasses. Geology now takes up 5 of the 15 slots, so it carries more total influence than before. Lower the subclass values if that's too much.
- The dust importance values (rover 0.9, astrobiology 0.3, habitat 0.7) are placeholders I chose. Rovers need clean solar panels, which is why the rover value is high.

**Data gap.** `data/earth_grid.json` and `data/mars_regions.json` hold demo data with a single combined `geology` column and no dust column. The 6 new criteria are therefore read as missing. Missing values are skipped, never scored as 0, so they have no effect until real data arrives, and the script prints a warning. For testing, setting `GEOLOGY_FALLBACK = True` copies the combined geology value into all 5 subclasses.

---

## 2. The problem with v_k

w_k(m) = f_k(m)·v_k / Σ_j f_j(m)·v_j, where v_k is the spread of s_ik **over the candidate Earth cells**. Calculating v_k exactly requires scoring every Earth cell, which is the cost the search is trying to avoid.

**Decision:** estimate v_k from a random sample of Earth cells (`SAMPLE_SIZE`, default 200), then freeze w_k(m) and search with the frozen weights.

**Improvement found while testing:** s_ik doesn't depend on the mission, so v_k depends only on the Mars target. The sample is now scored once per target and shared by all missions. That cut the sampling cost by 3× and total cost from 12.5% to 5.5% of brute force.

**How big the sample needs to be** (19 targets × 3 missions = 57 runs, averaged over 5 random seeds):

| Sample size | Same top-5 set as all-cell weights | Same #1 analog | Total cost vs brute force |
|---|---|---|---|
| 50 | 33.0 / 57 | 46.6 / 57 | 2.9% |
| 100 | 39.2 / 57 | 51.4 / 57 | 3.8% |
| **200** | **44.2 / 57** | **53.0 / 57** | **5.5%** |
| 400 | 46.2 / 57 | 53.6 / 57 | 9.0% |
| 800 | 49.2 / 57 | 55.4 / 57 | 15.9% |

Most of the gain comes by 200, so that's the default. The differences are almost always near-ties swapping places at ranks 4–5.

---

## 3. Search algorithm

### 3.1 Hard filters
`HARD_FILTERS = {criterion: minimum similarity}`. A block whose best possible similarity on that criterion is below the minimum is dropped whole, and so is a cell. A cell with no data for a required criterion is also dropped.

### 3.2 Zoom pyramid
The 2.5° cells are grouped into 5°, 10°, 20°, 40° and 80° blocks (`PYRAMID_LEVELS = 5`). Each block stores, per criterion:
- the min and max raw Earth value,
- how many of its cells have data.

This only reads the data and needs no similarity scoring. With real rasters it corresponds to cheap, coarse min/max overview products.

### 3.3 Upper bound for a block
**Best similarity per criterion.** Every rule is highest where e is closest to m. `ratio` and `logRatio` also jump at e = 0. So the best similarity anywhere in [min, max] is the highest of:
- rule(clamp(m, min, max), m),
- rule at both ends,
- rule at 0, if 0 lies in the range.

That gives u_k ≥ s_ik for every cell in the block.

**Gower-aware bound.** The final score is Σ w·s / Σ w over the criteria with data, and which criteria have data can vary from cell to cell inside a block. So the bound is the largest weighted average possible over every allowed set of present criteria:
- Criteria present in every cell of the block are always included.
- Criteria present in only some cells are added greedily, highest u first, but only while they raise the average. A term raises a weighted average only if it's above the current average, so the greedy pass finds the true maximum.

### 3.4 Best-first branch and bound
1. Push every top-level block into a priority queue ordered by its upper bound.
2. Pop the block with the highest bound. If that bound is below the current K-th best score (`TOP_K`, default 5), stop: no remaining block can beat it.
3. Otherwise split the block. Child blocks get their own bounds, and children below the K-th best are dropped. Full-resolution cells inherit the parent's bound, because bounding a single cell would mean scoring it.
4. When a full-resolution cell comes off the queue, score it as described below.

This is exact: for the frozen weights it returns the same top-K as scoring every cell.

### 3.5 Cheap criteria first
Each criterion has a cost (`CRITERION_COST`). Periglacial, caves and aeolian are costly because they need high-resolution imagery; temperature, UV and aridity are cheap reanalysis layers. Criteria are scored in order of highest weight ÷ cost first. After each one, the criteria not yet scored are assumed to score 1:

upper = (Σ_scored w·s + Σ_unscored w) / (Σ_scored w + Σ_unscored w)

Each s ≤ 1, so this bounds the true score. Once it drops below the K-th best, the cell is abandoned.

---

## 4. Results (demo data, 1,916 cells, 19 Mars targets × 3 missions)

| Check | Result |
|---|---|
| Top-5 identical to brute force with the same weights | **57 / 57** |
| Full-resolution cells scored per run | 46.6 of 1,916 (**2.4%**) |
| Criterion evaluations, search + v_k sample vs brute force | 54,012 vs 982,908 (**5.5%**) |
| Same #1 analog as with all-cell weights | 54 / 57 |
| Same top-5 set as with all-cell weights | 50 / 57 |
| With `GEOLOGY_FALLBACK = True` | 57 / 57 exact, 5.3% cost |
| With `HARD_FILTERS = {"aridity": 0.6}` | 57 / 57 exact, 5.3% cost |

Typical run: Utopia Planitia, Habitat analog.
- 44 cells scored, 32 of them stopped early.
- 129 of 238 bounded blocks pruned.
- Best analog at (−73.75°, −121.93°), Antarctica, with a final similarity score of 0.734.

The remaining cost is now mostly the v_k sample, about 1,800 evaluations per target, compared with about 350 for the search itself.

---

## 5. Caveats and next steps

- **All data is demo data.** The rankings mean nothing until real layers from `datasources.md` replace the JSON files.
- **The grid is coarse.** At 2.5°, Earth has only 1,916 cells, so brute force would also be cheap today. The pruning pays off with real rasters: at 1 km (~150 M land cells) the same pruning ratios would skip the vast majority of expensive high-resolution evaluations. Add pyramid levels as the grid gets finer.
- **The weights are estimated.** Results are exact for the frozen weights, but near-ties at ranks 4–5 can swap compared with all-cell weights. Raise `SAMPLE_SIZE` or `TOP_K` if that matters.
- **Coverage limits:** Mars gullies occur only at 26–83°S and 28–76°N, and the Earth ice map covers the Arctic only. Missing data is skipped, but criteria with sparse coverage get less reliable v_k estimates.
- **Possible improvements:**
  - Stratify the v_k sample by latitude band.
  - Add the CRITIC correlation term so related criteria such as ice and periglacial aren't counted twice.
  - Run a stability check that drops one Mars site at a time.

## Files

- `site_weights.py`: 15 criteria, similarity rules, weight math and the final similarity score. Run it to print the scores.
- `analog_search.py`: data loading, v_k sampling, zoom pyramid, bounds, branch and bound, and the brute-force check. All inputs are variables at the top.
- `docs/analog_search_journey.md`: this file.
