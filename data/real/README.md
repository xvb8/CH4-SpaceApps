# Real-world datasets

This directory holds the real datasets downloaded from the links in
[`datasources.md`](../../datasources.md).
See sections below for what is here, how it was obtained, and how to obtain
the datasets that require authentication or registration.

---

## Summary of what is bundled in the repo

Everything in the table below is vendored directly in `data/real/` (and
bundled into `data_real.zip`). Larger / per-query datasets are instead
fetched **on demand** by the API scripts documented in the
[On-demand API fetchers](#on-demand-api-fetchers) section further down.

| Dataset | Planet | Role in [`datasources.md`](../../datasources.md) | Files | Size | Integrity |
| --- | --- | --- | --- | --- | --- |
| Noblet et al. gullies (Zenodo 10581763) | Mars | Periglacial patterned ground & gullies | 9 | 129 MB | MD5 verified |
| Odyssey GRS 5x5 element maps | Mars | Minerals + Ice/Permafrost (H) | 18 | 955 KB | Size verified |
| MOLA MEG128 collection metadata | Mars | Topography (inventory only; tiles fetched on demand) | 2 | 9 KB | Size verified |
| Mars Global Cave Candidate Catalog (MGC3) | Mars | Caves | 1 zip | 1.7 MB | ZIP magic OK |
| Permafrost Discovery Gateway ice-wedge method package (DOI 10.18739/A2KW57K57) | Earth | Periglacial patterned ground & gullies | 4 | 279 KB | Size + PNG/XML/PDF magic OK |
| Sauro 2020 lava tubes cross-sections (Polito) | Earth | Caves (lava tubes) | 1 PDF | 3.4 MB | PDF magic OK |

Total: **34 files, ~135 MB** uncompressed. All integrity checks pass; see
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

### `mars_mola_megdr/` — MOLA MEG128 topography (metadata only)

- **Source:** NASA PDS Geosciences Node,
  [`urn-nasa-pds-mgs_mola_topography_derived/meg128`](https://pds-geosciences.wustl.edu/mgs/urn-nasa-pds-mgs_mola_topography_derived/meg128/).
- **What is here:** Only the collection inventory and schema
  (`collection_data_meg128.xml`, `collection_data_meg128_inventory.csv`,
  ~9 KB total). The actual topography tiles are **no longer bundled** — the
  full collection is ~3 GB (48 tiles at 65 MB each).
- **How to get tiles on demand:** use
  [`tools/mola_fetch.py`](../../tools/mola_fetch.py:1), which resolves
  `(lat, lon) -> tile filename` and streams the `.img/.lbl/.hdr/.xml` quadruple
  with HTTP Range resume. Example (Jezero crater, 18.4°N 77.5°E):

  ```bat
  python tools\mola_fetch.py --lat 18.4 --lon 77.5 --out data\real\mars_mola_megdr
  ```
- **NOTE on product type:** MEG128 is the MOLA topography derived product at
  128 pixels/degree (64 MB per tile), served as the modern PDS4 wrapping of
  the classic MEGT128.

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

## On-demand API fetchers

The following sources are **not** bundled in `data_real.zip` because they are
either too large (hundreds of MB to hundreds of GB) or inherently per-query
(bbox / time / point lookups). Each one is wrapped by a dedicated Python
script under [`tools/`](../../tools/) that talks directly to the upstream
API. All scripts are standard-library only (no `earthaccess`, no `cdsapi`),
support HTTP `Range` resume, and expose a `--list` dry-run mode.

### Earth — NASA Earthdata CMR

- **Script:** [`tools/earthdata_cmr.py`](../../tools/earthdata_cmr.py:1)
- **How:** direct JSON queries to the NASA CMR endpoint
  `https://cmr.earthdata.nasa.gov/search/granules.json`, followed by
  `urllib` streaming downloads of each granule URL. The user supplies an
  Earthdata Login token via the `EARTHDATA_TOKEN` env var (free bearer
  token from <https://urs.earthdata.nasa.gov/profile>).
- **Datasets wired in:**

  | Collection | Short name | Role (datasources.md) |
  | --- | --- | --- |
  | ASTER-GED AG100 thermal emissivity 100 m | `AG100` v003 | Basaltic + Silica/Evaporites |
  | EMIT L2B mineral ID & band depth | `EMITL2BMIN` v002 | Phyllosilicates, Sulfates, Carbonates |
  | MLS L2 Temperature (Aura) | `ML2T` v005 | Temperature profile |
  | MODIS Terra LST daily | `MOD11A1` v061 | Temperature |
  | MODIS Terra NDVI 16-day | `MOD13A2` v061 | Aridity index (NDVI) |
  | GPM IMERG daily precipitation | `GPM_3IMERGDF` v07 | Aridity index (precipitation) |

- **Example (Jezero, Mars-analog bbox on Earth is nonsensical; use Cuprite NV):**

  ```bat
  set EARTHDATA_TOKEN=eyJ0eXAi...
  python tools\earthdata_cmr.py --collection EMITL2BMIN --bbox -117.3 36.8 -117.0 37.1 --start 2023-01-01 --end 2024-12-31 --out data\real\earthdata_cmr\emit
  ```

### Earth — Copernicus DEM GLO-30

- **Script:** [`tools/copernicus_dem.py`](../../tools/copernicus_dem.py:1)
- **How:** direct OData queries against the Copernicus Data Space Ecosystem
  catalog (`https://catalogue.dataspace.copernicus.eu/odata/v1/Products`)
  followed by anonymous streaming downloads of each 1° × 1° DGED tile
  (`Copernicus_DSM_COG_10_*.tif`, ≈25 MB each). No account required for
  GLO-30.
- **Role:** Earth topography 30 m.
- **Example:**

  ```bat
  python tools\copernicus_dem.py --bbox -117.3 36.8 -117.0 37.1 --out data\real\copernicus_dem
  ```

### Earth — ERA5 ARCO Zarr

- **Script:** [`tools/era5_arco.py`](../../tools/era5_arco.py:1)
- **How:** reads the public Google / ECMWF ARCO ERA5 Zarr store
  (`gs://gcp-public-data-arco-era5/ar/full_37-1h-0p25deg-chunk-1.zarr-v3`)
  via `xarray` + `zarr`, selects variable / time / bbox server-side, and
  writes a slim NetCDF. No CDS account or `cdsapi` dependency; the ARCO
  mirror is fully anonymous.
- **Role:** RH, T, dewpoint, column water vapor hourly 1940–present.
- **Example:**

  ```bat
  python tools\era5_arco.py --var 2m_temperature --start 2024-06-01 --end 2024-06-02 --bbox -117.3 36.8 -117.0 37.1 --out data\real\era5\t2m_cuprite.nc
  ```

### Earth — TROPOMI Surface UV (FMI finhub)

- **Script:** [`tools/tropomi_finhub.py`](../../tools/tropomi_finhub.py:1)
- **How:** OpenSearch queries against the FMI finhub catalog
  (`https://finhub.nsdc.fmi.fi/search`) with product filter
  `OFFL_L3_UV`, then anonymous streaming downloads of the matching
  `.nc` granules. No login required.
- **Role:** Earth surface UV index.
- **Example:**

  ```bat
  python tools\tropomi_finhub.py --start 2024-06-01 --end 2024-06-07 --bbox -117.3 36.8 -117.0 37.1 --out data\real\tropomi_uv
  ```

### Earth — ESA CCI Permafrost (CEDA)

- **Script:** [`tools/esa_permafrost.py`](../../tools/esa_permafrost.py:1)
- **How:** anonymous HTTPS listing of the CEDA archive
  (`https://data.ceda.ac.uk/neodc/esacci/permafrost/data/`) followed by
  streaming NetCDF downloads. `AREA4_PP` = northern-hemisphere permafrost
  product packaged (1 km, annual).
- **Role:** Ice & Permafrost (1 m ground temperature).
- **Example (fetch 2023 NH product):**

  ```bat
  python tools\esa_permafrost.py --year 2023 --area AREA4_PP --out data\real\esa_permafrost
  ```

### Mars — MCD CGI (Mars Climate Database)

- **Script:** [`tools/mcd_fetch.py`](../../tools/mcd_fetch.py:1)
- **How:** direct HTTP POSTs to the LMD CGI gateway
  (`http://www-mars.lmd.jussieu.fr/mcd_python/cgi-bin/mcdcgi.py`) that
  backs the web form. Point and grid modes supported; returns a parsed
  text/CSV payload — no email approval needed.
- **Role:** Mars water vapor column, surface T, p, RH-T for salt deliquescence.
- **Example (Jezero point, Ls=90°, noon):**

  ```bat
  python tools\mcd_fetch.py --lat 18.4 --lon 77.5 --ls 90 --localtime 12 --out data\real\mcd\jezero_ls90.txt
  ```

### Mars — MIDAS dust (Zenodo)

- **Script:** [`tools/midas_zenodo.py`](../../tools/midas_zenodo.py:1)
- **How:** anonymous REST calls to the Zenodo API
  (`https://zenodo.org/api/records/4244106`), per-Mars-Year tar.gz
  downloads with HTTP Range resume, optional safe `tar.gz` extraction.
  The full record is ≈65 GB; the script lets you grab just the years you
  need (each ~2–6 GB).
- **Role:** Mars dust column optical depth time-series (Smith / Montabone
  reprocessed).
- **Example (MY 34 only, no extract):**

  ```bat
  python tools\midas_zenodo.py --year 34 --out data\real\midas
  ```

### Mars — PDS ODE (HiRISE / CTX / CRISM / MCS)

- **Script:** [`tools/pds_ode_fetch.py`](../../tools/pds_ode_fetch.py:1)
- **How:** unified queries to the PDS Orbital Data Explorer REST API
  (`https://oderest.rsl.wustl.edu/live2/`) with `IHID` / `IIID` / `PT`
  mission-instrument-product filters, bbox + target, then streaming
  downloads of each returned `Product_file`. Covers the four big MRO /
  MGS instruments in a single script.
- **Instruments wired in:**

  | Instrument | IHID / IIID / PT | Role |
  | --- | --- | --- |
  | HiRISE RDR | `MRO / HIRISE / RDRV11` | High-res imagery per site |
  | CTX EDR | `MRO / CTX / EDR` | Context imagery per site |
  | CRISM MTRDR | `MRO / CRISM / MTRDR` | Phyllosilicates / sulfates / carbonates mineral maps |
  | MCS DDR | `MRO / MCS / DDR` | Temperature + dust opacity profiles |

- **Example (CTX tiles around Jezero):**

  ```bat
  python tools\pds_ode_fetch.py --instrument ctx --bbox 76 17 79 19 --limit 5 --out data\real\pds_ctx
  ```

### Mars — TES mineral maps (ASU WMS)

- **Script:** [`tools/tes_asu_fetch.py`](../../tools/tes_asu_fetch.py:1)
- **How:** manual query-string construction (to preserve un-encoded
  slashes that the ASU WMS requires) against
  `https://wms.mars.asu.edu/wms` with `request=GetMap`. Returns PNG /
  GeoTIFF raster tiles at user-specified bbox and resolution.
- **Layers wired in:** Thermal Inertia, Albedo, Dust Cover Index,
  Hematite, Olivine, Pyroxene, Plagioclase, High-Si (see `--list`).
- **Example (global thermal inertia preview):**

  ```bat
  python tools\tes_asu_fetch.py --layer thermal_inertia --bbox -180 -90 180 90 --width 400 --height 200 --out data\real\tes\ti_global.png
  ```

### Mars — Montabone dust climatology (LMD)

- **Script:** [`tools/montabone_fetch.py`](../../tools/montabone_fetch.py:1)
- **How:** anonymous HTTPS fetch from the LMD host
  (`http://www-mars.lmd.jussieu.fr/mars/dust_climatology/dataset_v2/`),
  which is the actual data mirror behind the Open Research Online
  abstract. Resumable per-Mars-Year download. Product can be the daily
  gridded field (`griddedcdod`) or the GCM-ready kriged scenario
  (`dustscenario`, recommended, ≈57 MB per year).
- **Role:** Mars Column Dust Optical Depth (CDOD) climatology MY24–MY36.
- **Example (dust scenario for MY34):**

  ```bat
  python tools\montabone_fetch.py --product scenario --year 34 --out data\real\montabone
  ```

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
├── data_real.zip                          snapshot of the bundled subdirs below
├── mars_gullies_noblet/                   9 files, 129 MB  (Noblet gully catalog)
├── mars_odyssey_grs/                      18 files, 955 KB  (Cl/Fe/H2O/K/Si/Th 5x5 grids)
├── mars_mola_megdr/                       2 files, 9 KB    (MEG128 collection metadata only — tiles fetched on demand)
├── mars_caves_mgc3/                       mars_cave_catalog.zip (1.7 MB)
├── earth_pdg_icewedge/                    4 files, 279 KB  (Arctic Data Center DOI 10.18739/A2KW57K57)
└── earth_lava_tubes_polito/               Sauro_2020_Lava_Tubes_crosssections.pdf (3.4 MB)
```

Additional directories are populated on demand by the fetcher scripts and
are **not** in the bundled zip:

```
data/real/
├── earthdata_cmr/                         Earthdata CMR granules (EMIT/AG100/MLS/MODIS/GPM)
├── copernicus_dem/                        Copernicus DEM GLO-30 tiles
├── era5/                                  ERA5 ARCO slices
├── tropomi_uv/                            TROPOMI OFFL_L3_UV granules
├── esa_permafrost/                        ESA CCI Permafrost NetCDF
├── mcd/                                   MCD CGI point/grid responses
├── midas/                                 MIDAS per-MY tar.gz (Zenodo 4244106)
├── pds_hirise/, pds_ctx/, pds_crism/, pds_mcs/   PDS ODE products
├── tes/                                   TES ASU WMS raster tiles
└── montabone/                             Montabone CDOD per-MY NetCDF
```

## Tools

All downloader / helper scripts live under [`tools/`](../../tools/):

**Bundled-data helpers:**

- [`tools/download_real_data.py`](../../tools/download_real_data.py:1) —
  resumable, MD5-verifying downloader driven by the per-dataset manifests.
- [`tools/build_manifests.py`](../../tools/build_manifests.py:1) —
  regenerates per-dataset JSON manifests from scraped metadata.
- [`tools/parse_listings.py`](../../tools/parse_listings.py:1) —
  parses WUSTL PDS HTML directory listings into (name, size, url) tuples.
- [`tools/verify_downloads.py`](../../tools/verify_downloads.py:1) —
  cross-checks every file against its manifest and spot-checks binary
  magic bytes.

**On-demand API fetchers** (one script per upstream, all stdlib-only,
`--list` dry-run, HTTP Range resume):

- Earth:
  [`tools/earthdata_cmr.py`](../../tools/earthdata_cmr.py:1),
  [`tools/copernicus_dem.py`](../../tools/copernicus_dem.py:1),
  [`tools/era5_arco.py`](../../tools/era5_arco.py:1),
  [`tools/tropomi_finhub.py`](../../tools/tropomi_finhub.py:1),
  [`tools/esa_permafrost.py`](../../tools/esa_permafrost.py:1).
- Mars:
  [`tools/mcd_fetch.py`](../../tools/mcd_fetch.py:1),
  [`tools/mola_fetch.py`](../../tools/mola_fetch.py:1),
  [`tools/midas_zenodo.py`](../../tools/midas_zenodo.py:1),
  [`tools/pds_ode_fetch.py`](../../tools/pds_ode_fetch.py:1)
  (HiRISE / CTX / CRISM / MCS),
  [`tools/tes_asu_fetch.py`](../../tools/tes_asu_fetch.py:1),
  [`tools/montabone_fetch.py`](../../tools/montabone_fetch.py:1).

The scratch metadata snapshots used to build the bundled manifests are
kept under `.temp/` (Zenodo JSON responses and PDS HTML listings) for
inspection, but should not be relied on for anything other than
reproducibility.
