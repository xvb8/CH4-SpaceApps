# Real-world datasets

This directory holds the real datasets downloaded from the links in
[`datasources.md`](../../datasources.md).
See sections below for what is here, how it was obtained, and how to obtain
the datasets that require authentication or registration.

---

## Summary of what was downloaded

| Dataset | Planet | Role in [`datasources.md`](../../datasources.md) | Files | Size | Integrity |
| --- | --- | --- | --- | --- | --- |
| Noblet et al. gullies (Zenodo 10581763) | Mars | Periglacial patterned ground & gullies | 9 | 129 MB | MD5 verified |
| Odyssey GRS 5x5 element maps | Mars | Minerals + Ice/Permafrost (H) | 18 | 955 KB | Size verified |
| MOLA MEG128 sample tiles (meg128) | Mars | Topography | 10 | 124 MB | Size verified |
| Mars Global Cave Candidate Catalog (MGC3) | Mars | Caves | 1 zip | 1.7 MB | ZIP magic OK |
| Permafrost Discovery Gateway ice-wedge method package (DOI 10.18739/A2KW57K57) | Earth | Periglacial patterned ground & gullies | 4 | 279 KB | Size + PNG/XML/PDF magic OK |
| Sauro 2020 lava tubes cross-sections (Polito) | Earth | Caves (lava tubes) | 1 PDF | 3.4 MB | PDF magic OK |

Total: **42 files, ~259 MB** uncompressed. All integrity checks pass; see
[`tools/verify_downloads.py`](../../tools/verify_downloads.py:1).

### Archive bundle

For convenience, the entire `data/real/` tree (minus this README) is also
tracked in the repo as a single compressed archive:

- [`data/real/data_real.zip`](./data_real.zip) — **~59 MB** (~4.4× smaller
  than the raw files thanks to shapefile/`.tab` compression).

After cloning, either unzip this archive in place:

```bat
powershell -NoProfile -Command "Expand-Archive -Path data\real\data_real.zip -DestinationPath data\real -Force"
python tools\verify_downloads.py
```

…or regenerate everything from the authoritative sources using the manifests
(see **Reproducibility** below). The archive and the manifest-driven download
produce byte-identical files.

### Reproducibility

The downloads are driven by JSON manifests
[`tools/manifest_gullies.json`](../../tools/manifest_gullies.json:1),
[`tools/manifest_pdg_icewedge.json`](../../tools/manifest_pdg_icewedge.json:1),
and [`tools/manifest_non_zenodo.json`](../../tools/manifest_non_zenodo.json:1),
and executed by [`tools/download_real_data.py`](../../tools/download_real_data.py:1).
The script resumes partial downloads via HTTP `Range`, retries with
exponential backoff, and verifies MD5 checksums when the source publishes them.

To re-run (idempotent; files already complete are skipped):

```bat
python tools\download_real_data.py tools\manifest_gullies.json
python tools\download_real_data.py tools\manifest_pdg_icewedge.json
python tools\download_real_data.py tools\manifest_non_zenodo.json
python tools\verify_downloads.py
```

The per-dataset manifests
[`tools/manifest_icewedge.json`](../../tools/manifest_icewedge.json:1),
[`tools/manifest_mgc3.json`](../../tools/manifest_mgc3.json:1),
[`tools/manifest_mola.json`](../../tools/manifest_mola.json:1),
and [`tools/manifest_grs.json`](../../tools/manifest_grs.json:1) are also
kept in the repo for inspection — the three "big" manifests above combine
them, plus the Zenodo Noblet gullies and the Arctic Data Center PDG package.
Note: `manifest_icewedge.json` still points at Zenodo 10522820 (SvalCryo)
for archival reference and is no longer used by the verifier.

---

## Downloaded datasets

### `mars_gullies_noblet/` — Global map of gullied hillslopes on Mars

- **Source:** Noblet A. et al., Zenodo record
  [10581763](https://zenodo.org/records/10581763).
- **Covers:** Gullied hillslopes digitized as polygons on a CTX mosaic, in the
  Mars2000 coordinate system. Latitudes 26–83°S and 28–76°N.
- **Files:** ESRI shapefile (`GlobalGullies_ANoblet.*`, 9 files) plus a 110 MB
  statistics text file `GG_Aspect_Gradient_stats.txt`.
- **Role:** "Periglacial patterned ground and gullies" layer for Mars.
- **Integrity:** All 9 files pass MD5 check against Zenodo's published hashes.

### `mars_odyssey_grs/` — Mars Odyssey Gamma-Ray Spectrometer element maps

- **Source:** NASA PDS Geosciences Node,
  [`ody-m-grs-5-elements-v1`](https://pds-geosciences.wustl.edu/ody/ody-m-grs-5-elements-v1/odgm_xxxx/data/unsmoothed/5x5/).
- **Covers:** Global 5°×5° element-concentration maps (Cl, Fe, H2O, K, Si, Th)
  as `.tab` ASCII tables plus `.lbl` PDS3 labels and `.xml` PDS4 labels.
- **Role:** Minerals (chemical composition, coarse) **and** Ice/Permafrost
  (the `h2o_5x5.tab` map represents water-equivalent hydrogen in the top meter).
- **Integrity:** All 18 files match directory-listing sizes.

### `mars_mola_megdr/` — MOLA MEG128 topography sample tiles

- **Source:** NASA PDS Geosciences Node,
  [`urn-nasa-pds-mgs_mola_topography_derived/meg128`](https://pds-geosciences.wustl.edu/mgs/urn-nasa-pds-mgs_mola_topography_derived/meg128/).
- **What is here:** The collection inventory plus two `.img` tiles
  (`megc00n000hb.img`, `megc00n090hb.img`) at 128 ppd covering the equatorial
  belt from 0–44°N and longitudes 0–90°E and 90–180°E, together with their
  `.hdr` / `.lbl` / `.xml` labels.
- **Why only two tiles:** the full collection is ~5 GB (48 tiles at 65 MB each);
  these two are a representative sample for Gale/Jezero-adjacent longitudes.
- **To download more tiles,** edit the `keep_prefixes` list in
  [`tools/build_manifests.py`](../../tools/build_manifests.py:1) and re-run.
- **NOTE on product type:** the directory served here is MEG128 (topography
  derived product, 64 MB per tile at 128 ppd), not the older MEGT128. This is
  still the MOLA topography grid, just a newer PDS4 wrapping.

### `mars_caves_mgc3/` — Mars Global Cave Candidate Catalog

- **Source:** USGS Astrogeology Science Center,
  [MGC3 catalog page](https://astrogeology.usgs.gov/search/map/mars_global_cave_candidate_catalog_v1_cushing).
- **Direct product file:**
  `https://astrogeology.usgs.gov/ckan/dataset/.../download/mars_cave_catalog.zip`
  (1.69 MB zip containing the shapefile and metadata for 1,000+ cave entrance
  candidates).
- **Role:** Caves (shielded subsurface environment).
- **Integrity:** ZIP magic bytes (`PK\x03\x04`) verified.

### `earth_pdg_icewedge/` — Permafrost Discovery Gateway (ice-wedge method)

- **Source:** Arctic Data Center, DOI
  [10.18739/A2KW57K57](https://arcticdata.io/catalog/view/doi%3A10.18739%2FA2KW57K57)
  — "Ice-wedge polygon detection in satellite imagery from pan-Arctic
  regions, Permafrost Discovery Gateway, 2001-2021" (Witharana et al.).
- **Role:** "Permafrost Discovery Gateway ice-wedge polygons" entry in
  [`datasources.md`](../../datasources.md:310). This replaces the earlier
  SvalCryo placeholder — see the *Resolved discrepancy* note below.
- **Files (4, 279 KB total):**
  - `Ice_wedge_polygon_detection_in_satellite_imagery.xml` — EML 2.2 dataset
    metadata (65 KB).
  - `Ice_Wedge_Polygon_Pipeline.png` — diagram of the end-to-end detection
    pipeline (140 KB).
  - `add_date_attribute_footprints.py` — a processing script from the
    published pipeline (2 KB).
  - `PGC_Commercial_Satellite_Imagery_Documentation.pdf` — PGC/Maxar imagery
    provenance documentation (72 KB).
- **Download endpoint:** DataONE v2 object API,
  `https://arcticdata.io/metacat/d1/mn/v2/object/{urlencoded-id}` — no
  authentication required.
- **Integrity:** Size-verified against the DataONE solr metadata (the
  endpoint does not publish content checksums in the query response). Magic
  bytes verified for the PNG, XML, and PDF.
- **Why the method package, not the rasters:** the actual pan-Arctic
  ice-wedge polygon rasters (billions of polygons, hundreds of GB) are
  served through the PDG GeoServer / web-tile service at
  <https://permafrost.arcticdata.io/>, not as a single downloadable file.
  For our analog-search use case we only need the method description,
  pipeline, and provenance — which is exactly what this Arctic Data Center
  record publishes.

**Resolved discrepancy:** [`datasources.md`](../../datasources.md:310) links
to Zenodo record [10522820](https://zenodo.org/records/10522820) as the
"Permafrost Discovery Gateway ice-wedge polygons", but that Zenodo record
is actually the *SvalCryo* cryo-hazards inventory for Svalbard (thermo-
erosional gullies and thaw slumps, not ice-wedge polygons and not from the
PDG project). The correct Permafrost Discovery Gateway publication is on
Arctic Data Center under DOI 10.18739/A2KW57K57, which is what is now
downloaded here. [`tools/manifest_icewedge.json`](../../tools/manifest_icewedge.json:1)
is retained in the repo as a reference to the SvalCryo files but is no
longer part of the default download pipeline.

### `earth_lava_tubes_polito/` — Sauro et al. 2020 lava-tube cross-sections

- **Source:** Politecnico di Torino IRIS repository,
  [handle 11583/2999116](https://iris.polito.it/retrieve/handle/11583/2999116/903261).
- **What is here:** The paper PDF `Sauro_2020_Lava_Tubes_crosssections.pdf`
  (3.4 MB) which contains ≈1,200 cross-sections from 92+ terrestrial lava
  tubes. The repository only publishes the paper; the underlying
  cross-section geometry is tabulated in the paper's figures and supplementary
  material.
- **Role:** Caves — terrestrial lava-tube shape analog for Mars lava tubes.
- **Integrity:** PDF header `%PDF-` verified.

---

## Datasets NOT downloaded (manual-access instructions)

Many sources in [`datasources.md`](../../datasources.md) require a free
account, an interactive request form, or are too large to vendor into this
repo. They are listed below with the exact access method.

### Requires NASA Earthdata Login

A free account at <https://urs.earthdata.nasa.gov/> is required. The
simplest path is the `earthaccess` Python library:

```bash
pip install earthaccess xarray
```

```python
import earthaccess
earthaccess.login()  # writes ~/.netrc on first run

bbox = (-117.3, 36.8, -117.0, 37.1)  # example: Cuprite, NV
granules = earthaccess.search_data(
    short_name="EMITL2BMIN", version="002",
    bounding_box=bbox, temporal=("2023-01-01", "2024-12-31"),
)
files = earthaccess.download(granules, "./data/real/earth_emit_l2b")
```

Collections referenced in [`datasources.md`](../../datasources.md):

| Collection | Short name / DOI | Role | datasources.md line |
| --- | --- | --- | --- |
| ASTER-GED AG100 (thermal emissivity, 100 m) | `AG100` v003 | Basaltic + Silica/Evaporites | [93](../../datasources.md:93), [101](../../datasources.md:101) |
| EMIT L2B mineral ID & band depth | `EMITL2BMIN` v002 | Phyllosilicates, Sulfates, Carbonates | [95](../../datasources.md:95), [97](../../datasources.md:97), [99](../../datasources.md:99) |
| MLS L2 Temperature (Aura) | `ML2T` v005 | Temperature profile (Earth limb sounder analog to MCS) | [251](../../datasources.md:251) |
| MODIS LST / NDVI | various `MOD11*`, `MOD13*` | Temperature + Aridity (NDVI) | lines 39, 51 |
| GPM IMERG precipitation | `GPM_3IMERGDF` | Aridity index inputs | line 51 |

### Requires other registration / form submission

| Dataset | Access method | Role |
| --- | --- | --- |
| **Mars Climate Database (MCD)** — <http://www-mars.lmd.jussieu.fr> | Interactive web form; credentials emailed after approval | Water vapor column, surface T, p, RH-T for salt deliquescence |
| **Copernicus DEM GLO-30** — [data space portal](https://dataspace.copernicus.eu/explore-data/data-collections/copernicus-contributing-missions/collections-description/COP-DEM) | Free Copernicus Data Space account; then OData / STAC API | Earth topography 30 m |
| **ERA5 hourly reanalysis** — DOI [10.24381/cds.adbb2d47](https://doi.org/10.24381/cds.adbb2d47) | Copernicus Climate Data Store account + `cdsapi` Python client (`pip install cdsapi`) | RH, T, dewpoint, column water vapor hourly 1940–present |
| **TROPOMI Surface UV** — <https://www.tropomi.eu/data-products/surface-uv> | FMI / TEMIS portal, no login but requires form or ad-hoc order | Earth surface UV index |
| **ESA CCI Permafrost** — <https://climate.esa.int/de/projekte/permafrost/data> | Simple registration on ESA CCI Open Data Portal | Ice & Permafrost (1 m ground temperature) |

### Mars datasets intentionally skipped

| Dataset | Why not downloaded here | Pointer |
| --- | --- | --- |
| **MIDAS dust optical depth (Zenodo 4244106)** | 65 GB total; out of scope for the bundled sample | <https://zenodo.org/records/4244106> |
| **CRISM MTRDR (MRO)** | Hundreds of GB of mineralogy cubes; download selective tiles from the PDS Geosciences Node by target region | <https://pds-geosciences.wustl.edu/mro/mro-m-crism-5-rdr-multispectral-v1/mrocr_3201/mrdr/> |
| **TES mineral maps (ASU)** | ASU-hosted selection UI; browse at <https://www.mars.asu.edu/data/> | — |
| **MCS temperature / dust opacity** | Interactive filter UI; download per-sol L5 products from NMSU server | <https://atmos.nmsu.edu/data_and_services/atmospheres_data/MARS/mcs.html> |
| **Montabone dust climatology** | Supplementary data behind an Open Research Online abstract; request via the record | <https://oro.open.ac.uk/45036/> |
| **HiRISE / CTX image products** | PDS Imaging Node, far too large for a bundled sample; use JMARS or the HiRISE project page per site | <https://www.uahirise.org/> |

### Reference papers (read-only, not datasets)

| Reference | Role |
| --- | --- |
| PNAS 2024 Mars UV paper, DOI [10.1073/pnas.2426611122](https://www.pnas.org/doi/10.1073/pnas.2426611122) | UV modeling methodology |
| arXiv 1710.01238 — Mars surface UV | UV modeling methodology (companion to the PNAS paper) |
| academia.edu 55427843 — Mars UV spectrometer | Context on MSL REMS UV sensor |

### Country-restricted mineral surveys

| Jurisdiction | Dataset | Link |
| --- | --- | --- |
| USA only | USGS mineral geochemistry catalog | <https://www.sciencebase.gov/catalog/item/5dd2f264e4b0695797628351> |
| Australia only | Geoscience Australia national geochemistry | DOI [10.5066/P9YEAFHI](https://doi.org/10.5066/P9YEAFHI) |
| Canada only | Open Canada geochemistry | <https://open.canada.ca/data/en/dataset/289c931c-a1b1-55f8-8d93-4d88e66f1810> |

---

## Directory layout

```
data/real/
├── README.md                              (this file)
├── mars_gullies_noblet/                   9 files, 129 MB
├── mars_odyssey_grs/                      18 files, 955 KB  (Cl/Fe/H2O/K/Si/Th 5x5 grids)
├── mars_mola_megdr/                       10 files, 124 MB  (MEG128 sample tiles)
├── mars_caves_mgc3/                       mars_cave_catalog.zip (1.7 MB)
├── earth_pdg_icewedge/                    4 files, 279 KB  (Arctic Data Center DOI 10.18739/A2KW57K57)
└── earth_lava_tubes_polito/               Sauro_2020_Lava_Tubes_crosssections.pdf (3.4 MB)
```

## Tools

All downloader / helper scripts live under [`tools/`](../../tools/):

- [`tools/download_real_data.py`](../../tools/download_real_data.py:1) —
  resumable, MD5-verifying downloader.
- [`tools/build_manifests.py`](../../tools/build_manifests.py:1) —
  regenerates per-dataset JSON manifests from scraped metadata.
- [`tools/parse_listings.py`](../../tools/parse_listings.py:1) —
  parses WUSTL PDS HTML directory listings into (name, size, url) tuples.
- [`tools/verify_downloads.py`](../../tools/verify_downloads.py:1) —
  cross-checks every file against its manifest and spot-checks binary
  magic bytes.

The scratch metadata snapshots used to build the manifests are kept under
`.temp/` (Zenodo JSON responses and PDS HTML listings) for inspection, but
should not be relied on for anything other than reproducibility.
