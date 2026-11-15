"""
fetch_sources.py - one downloader for every automatable data source.

Run on your OWN computer (the Snowflake sandbox cannot reach these sites):

    python fetch_sources.py --list              # show sources and whether they're ready
    python fetch_sources.py --dry-run grs mcs   # print what would be downloaded
    python fetch_sources.py grs mola            # download selected sources
    python fetch_sources.py                     # download every enabled source

Files go to raw_data/<source>/. Existing files are skipped, so it can be
stopped and restarted.

Logins (free):
  * NASA Earthdata (EMIT, ASTER GED, MLS): create a token at
    https://urs.earthdata.nasa.gov  ->  set environment variable EARTHDATA_TOKEN
  * ERA5 (Copernicus Climate Data Store): pip install cdsapi, and put your key in
    ~/.cdsapirc as described on the CDS website.

Location-based sources (Copernicus DEM, EMIT, ASTER, ERA5, NASA POWER) need the
Earth locations produced by the team's location-filtering code. Pass that output
file with --locations (CSV with name, lat, lon columns):

    python fetch_sources.py --locations filtered_earth_sites.csv copernicus_dem

Entries marked TODO contain an address that could not be checked from the
sandbox; confirm it in a browser and set "enabled": True.

NOT automatable (get these manually):
  * Mars Climate Database (Mars aridity + salt): request form at www-mars.lmd.jussieu.fr
  * Earth lava tube cross-sections: table inside the polito.it PDF
"""

import argparse
import json
import math
import os
import re
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from datetime import date

OUT_ROOT = "raw_data"
EARTH_LOCATIONS_CSV = None   # set from --locations (output of the location filter)
LOCATION_PAD_DEG = 0.5          # area fetched around each Earth location

# MCS sampling: one Mars year, 1st and 15th of each month (see datasources.md)
MCS_FIRST_MONTH = (2014, 12)    # mrom_2100
MCS_LAST_MONTH = (2016, 10)     # mrom_2122
MCS_DAYS = [1, 15]
MCS_HOURS = ["00", "04", "08", "12", "16", "20"]
MCS_MISSING_VOLUMES = {"mrom_2037", "mrom_2038", "mrom_2039", "mrom_2213"}

GRS_ELEMENTS = ["cl", "fe", "h2o", "k", "si", "th"]

# ---------------------------------------------------------------------------
# Source list - one entry per dataset
# ---------------------------------------------------------------------------

SOURCES = {
    # ---------------- Mars ----------------
    "grs": {
        "desc": "Mars Odyssey GRS 5x5 element maps (chemical composition, ice)",
        "method": "http_files", "enabled": True,
        "base": "https://pds-geosciences.wustl.edu/ody/ody-m-grs-5-elements-v1/odgm_xxxx/data/unsmoothed/5x5/",
        "files": [f"{el}_5x5.{ext}" for el in GRS_ELEMENTS for ext in ("tab", "lbl")],
    },
    "mola": {
        "desc": "Mars MOLA MEGDR 128 px/deg topography tiles (65-130 MB each)",
        "method": "http_listing", "enabled": True,
        "base": "https://pds-geosciences.wustl.edu/mgs/urn-nasa-pds-mgs_mola_topography_derived/meg128/",
        "pattern": r"megt.*\.(img|lbl|xml)$",   # TODO: confirm topography tiles start with 'megt'
    },
    "mcs": {
        "desc": "Mars MCS DDR, 2 days/month for one Mars year (~5.5 GB)",
        "method": "mcs", "enabled": False,   # TODO: confirm both URL templates, then enable
        "day_url": "https://atmos.nmsu.edu/PDS/data/{volume}/DATA/{yyyy}/{yyyymm}/{yyyymmdd}/",
        "label_url": "https://atmos.nmsu.edu/PDS/data/{volume}/LABEL/",
        "fmt_files": ["MCS_DDR1.FMT", "MCS_DDR2.FMT"],
    },
    "crism_mtrdr": {
        "desc": "Mars CRISM MTRDR mineral parameter maps (very large; pick folders)",
        "method": "http_listing", "enabled": False,  # TODO: narrow to the regions you need
        "base": "https://pds-geosciences.wustl.edu/mro/mro-m-crism-5-rdr-multispectral-v1/mrocr_3201/mrdr/",
        "pattern": r"\.(img|lbl)$",
    },
    "tes_minerals": {
        "desc": "Mars TES olivine/pyroxene maps (basaltic)",
        "method": "http_files", "enabled": False,  # TODO: get file links from mars.asu.edu/data
        "base": "https://www.mars.asu.edu/data/", "files": [],
    },
    "mgc3_caves": {
        "desc": "Mars Global Cave Candidate Catalog (USGS)",
        "method": "http_files", "enabled": False,  # TODO: copy the download link from the USGS page
        "base": "https://astrogeology.usgs.gov/", "files": [],
    },
    "mars_gullies": {
        "desc": "Mars global map of gullied hillslopes (Noblet et al.)",
        "method": "zenodo", "enabled": True, "record": "10581763",
    },

    # ---------------- Earth ----------------
    "copernicus_dem": {
        "desc": "Earth Copernicus DEM GLO-30 tiles around each Earth location",
        "method": "copernicus_dem", "enabled": True,
    },
    "emit_minerals": {
        "desc": "Earth EMIT L2B minerals (clay, sulfate, carbonate)",
        "method": "earthdata", "enabled": True,
        "short_name": "EMITL2BMIN", "version": "002",
    },
    "aster_ged": {
        "desc": "Earth ASTER GED AG100 emissivity (basaltic, silica)",
        "method": "earthdata", "enabled": True,
        "short_name": "AG100", "version": "003",
    },
    "mls_temperature": {
        "desc": "Earth Aura MLS temperature profiles (one file per day)",
        "method": "earthdata", "enabled": True,
        "short_name": "ML2T", "version": "005", "global": True,
        "temporal": "2025-01-01T00:00:00Z,2025-01-31T23:59:59Z",  # widen as needed
    },
    "nasa_power": {
        "desc": "Earth NASA POWER daily 2 m air temp (mean/max/min) per Earth location - no login",
        "method": "nasa_power", "enabled": True,
        "parameters": "T2M,T2M_MAX,T2M_MIN", "start": "20230101", "end": "20231231",
    },
    "earth_geochem_us": {
        "desc": "Earth geochemistry, US only (ScienceBase) - Earth side of chemical composition",
        "method": "http_files", "enabled": False,  # TODO: copy file links from the ScienceBase item
        "base": "https://www.sciencebase.gov/catalog/item/5dd2f264e4b0695797628351/", "files": [],
    },
    "earth_geochem_au": {
        "desc": "Earth geochemistry, Australia only (doi 10.5066/P9YEAFHI)",
        "method": "http_files", "enabled": False,  # TODO: copy file links from the DOI page
        "base": "", "files": [],
    },
    "earth_geochem_ca": {
        "desc": "Earth geochemistry, Canada only (open.canada.ca)",
        "method": "http_files", "enabled": False,  # TODO: copy file links from the dataset page
        "base": "", "files": [],
    },
    "era5": {
        "desc": "Earth ERA5 hourly T, dewpoint, water vapour (aridity, salt)",
        "method": "cds", "enabled": True,
        "dataset": "reanalysis-era5-single-levels",
        "variables": ["2m_temperature", "2m_dewpoint_temperature",
                      "surface_pressure", "total_column_water_vapour"],
        "year": "2023",
    },
    "earth_ice_wedges": {
        "desc": "Earth ice-wedge polygons (Permafrost Discovery Gateway) - large",
        "method": "zenodo", "enabled": True, "record": "10522820",
    },
    "esa_cci_permafrost": {
        "desc": "Earth ESA CCI permafrost 1 m ground temperature",
        "method": "http_listing", "enabled": False,  # TODO: copy the data folder link from climate.esa.int
        "base": "", "pattern": r"\.nc$",
    },
}


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def download(url, path, headers=None, dry_run=False, retries=3):
    """Download url to path. Returns ok / skip / missing / failed / dry."""
    if dry_run:
        print(f"    {url}")
        return "dry"
    if os.path.exists(path) and os.path.getsize(path) > 0:
        return "skip"
    os.makedirs(os.path.dirname(path) or ".", exist_ok=True)
    req = urllib.request.Request(url, headers=headers or {})
    for attempt in range(retries):
        try:
            with urllib.request.urlopen(req, timeout=300) as r, open(path + ".part", "wb") as f:
                while chunk := r.read(1 << 20):
                    f.write(chunk)
            os.replace(path + ".part", path)
            return "ok"
        except urllib.error.HTTPError as e:
            if e.code in (401, 403):
                print(f"    {url}: HTTP {e.code} (login/token needed?)")
                return "failed"
            if e.code == 404:
                return "missing"
        except Exception:
            pass
        time.sleep(5 * (attempt + 1))
    return "failed"


def get_text(url, headers=None):
    req = urllib.request.Request(url, headers=headers or {})
    with urllib.request.urlopen(req, timeout=120) as r:
        return r.read().decode("utf-8", errors="replace")


def load_locations(path=None):
    import csv
    path = path or EARTH_LOCATIONS_CSV
    if not path or not os.path.exists(path):
        return None
    with open(path, newline="") as f:
        rows = list(csv.DictReader(f))
    return [(r["name"], float(r["lat"]), float(r["lon"])) for r in rows]


def location_boxes(locations, pad=LOCATION_PAD_DEG):
    """(name, west, south, east, north) around each location."""
    return [(n, lon - pad, lat - pad, lon + pad, lat + pad) for n, lat, lon in locations]


def mcs_volume(year, month):
    """mrom_2001 = Sep 2006, +1 per Earth month."""
    return f"mrom_{2000 + (year - 2006) * 12 + (month - 9) + 1}"


def months(first, last):
    y, m = first
    while (y, m) <= last:
        yield y, m
        y, m = (y + 1, 1) if m == 12 else (y, m + 1)


def copernicus_tile(lat, lon):
    """Copernicus GLO-30 tile name for the 1x1 deg cell containing lat/lon."""
    la, lo = math.floor(lat), math.floor(lon)
    ns = f"{'N' if la >= 0 else 'S'}{abs(la):02d}_00"
    ew = f"{'E' if lo >= 0 else 'W'}{abs(lo):03d}_00"
    return f"Copernicus_DSM_COG_10_{ns}_{ew}_DEM"


# ---------------------------------------------------------------------------
# Methods
# ---------------------------------------------------------------------------

def run_http_files(name, src, out, dry):
    return [download(src["base"] + f, os.path.join(out, f), dry_run=dry) for f in src["files"]]


def run_http_listing(name, src, out, dry):
    if not src["base"]:
        print("    no folder link set")
        return ["failed"]
    html = get_text(src["base"])
    links = sorted(set(re.findall(r'href="([^"?#]+)"', html)))
    files = [l for l in links if re.search(src["pattern"], l, re.IGNORECASE) and not l.endswith("/")]
    print(f"    {len(files)} matching files")
    return [download(urllib.parse.urljoin(src["base"], l),
                     os.path.join(out, os.path.basename(l)), dry_run=dry) for l in files]


def run_mcs(name, src, out, dry):
    results, fmt_done = [], False
    for year, month in months(MCS_FIRST_MONTH, MCS_LAST_MONTH):
        vol = mcs_volume(year, month)
        if vol in MCS_MISSING_VOLUMES:
            continue
        if not fmt_done:
            for fmt in src["fmt_files"]:
                results.append(download(src["label_url"].format(volume=vol) + fmt,
                                        os.path.join(out, fmt), dry_run=dry))
            fmt_done = True
        for day in MCS_DAYS:
            d = date(year, month, day)
            folder = src["day_url"].format(volume=vol, yyyy=f"{d:%Y}",
                                           yyyymm=f"{d:%Y%m}", yyyymmdd=f"{d:%Y%m%d}")
            for hour in MCS_HOURS:
                for ext in ("LBL", "TAB"):
                    fn = f"{d:%Y%m%d}{hour}_DDR.{ext}"
                    results.append(download(folder + fn, os.path.join(out, vol, fn), dry_run=dry))
    return results


def run_zenodo(name, src, out, dry):
    meta = json.loads(get_text(f"https://zenodo.org/api/records/{src['record']}"))
    results = []
    for f in meta.get("files", []):
        size_mb = f.get("size", 0) / 1e6
        print(f"    {f['key']} ({size_mb:.0f} MB)")
        results.append(download(f["links"]["self"], os.path.join(out, f["key"]), dry_run=dry))
    return results


def run_copernicus_dem(name, src, out, dry):
    locs = load_locations()
    if not locs:
        print("    needs --locations <filtered Earth sites CSV> (name, lat, lon)")
        return ["failed"]
    tiles = sorted({copernicus_tile(lat, lon) for _, lat, lon in locs})
    base = "https://copernicus-dem-30m.s3.amazonaws.com/"
    return [download(f"{base}{t}/{t}.tif", os.path.join(out, f"{t}.tif"), dry_run=dry) for t in tiles]


def cmr_granule_links(short_name, version, bbox=None, temporal=None):
    """Search NASA CMR (no login needed) and return data download links."""
    params = {"short_name": short_name, "version": version, "page_size": 200}
    if bbox:
        params["bounding_box"] = ",".join(f"{v:.4f}" for v in bbox)
    if temporal:
        params["temporal"] = temporal
    url = "https://cmr.earthdata.nasa.gov/search/granules.json?" + urllib.parse.urlencode(params)
    feed = json.loads(get_text(url))["feed"]["entry"]
    links = []
    for g in feed:
        for l in g.get("links", []):
            if l.get("rel", "").endswith("/data#") and l["href"].startswith("http"):
                links.append(l["href"])
    return links


def run_earthdata(name, src, out, dry):
    token = os.environ.get("EARTHDATA_TOKEN")
    if not token and not dry:
        print("    set EARTHDATA_TOKEN first")
        return ["failed"]
    headers = {"Authorization": f"Bearer {token}"} if token else {}
    if src.get("global"):
        boxes = [("global", None)]
    else:
        locs = load_locations()
        if not locs:
            print("    needs --locations <filtered Earth sites CSV> (name, lat, lon)")
            return ["failed"]
        boxes = [(n, (w, s, e, nn)) for n, w, s, e, nn in location_boxes(locs)]
    results, seen = [], set()
    for loc_name, bbox in boxes:
        links = cmr_granule_links(src["short_name"], src["version"], bbox, src.get("temporal"))
        print(f"    {loc_name}: {len(links)} files")
        for link in links:
            if link in seen:
                continue
            seen.add(link)
            results.append(download(link, os.path.join(out, os.path.basename(link)),
                                    headers=headers, dry_run=dry))
    return results


def run_cds(name, src, out, dry):
    locs = load_locations()
    if not locs:
        print("    needs --locations <filtered Earth sites CSV> (name, lat, lon)")
        return ["failed"]
    results = []
    for loc_name, w, s, e, n in location_boxes(locs):
        safe = re.sub(r"[^A-Za-z0-9]+", "_", loc_name)
        path = os.path.join(out, f"{safe}_{src['year']}.nc")
        request = {
            "product_type": ["reanalysis"], "variable": src["variables"],
            "year": [src["year"]], "month": [f"{m:02d}" for m in range(1, 13)],
            "day": [f"{d:02d}" for d in range(1, 32)],
            "time": [f"{h:02d}:00" for h in range(24)],
            "area": [n, w, s, e],   # north, west, south, east
            "data_format": "netcdf",
        }
        if dry:
            print(f"    {loc_name}: {src['dataset']} area={request['area']} -> {path}")
            results.append("dry")
            continue
        if os.path.exists(path):
            results.append("skip")
            continue
        try:
            import cdsapi
        except ImportError:
            print("    pip install cdsapi first")
            return ["failed"]
        os.makedirs(out, exist_ok=True)
        cdsapi.Client().retrieve(src["dataset"], request, path)
        results.append("ok")
    return results


def run_nasa_power(name, src, out, dry):
    """NASA POWER point API: one CSV of daily values per Earth location (no login)."""
    locs = load_locations()
    if not locs:
        print("    needs --locations <filtered Earth sites CSV> (name, lat, lon)")
        return ["failed"]
    results = []
    for loc_name, lat, lon in locs:
        params = urllib.parse.urlencode({
            "parameters": src["parameters"], "community": "RE",
            "latitude": f"{lat:.4f}", "longitude": f"{lon:.4f}",
            "start": src["start"], "end": src["end"], "format": "CSV",
        })
        url = "https://power.larc.nasa.gov/api/temporal/daily/point?" + params
        safe = re.sub(r"[^A-Za-z0-9]+", "_", loc_name)
        results.append(download(url, os.path.join(out, f"{safe}.csv"), dry_run=dry))
    return results


METHODS = {
    "http_files": run_http_files, "http_listing": run_http_listing, "mcs": run_mcs,
    "zenodo": run_zenodo, "copernicus_dem": run_copernicus_dem,
    "earthdata": run_earthdata, "cds": run_cds, "nasa_power": run_nasa_power,
}


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("sources", nargs="*", help="source names (default: all enabled)")
    ap.add_argument("--list", action="store_true", help="list sources and exit")
    ap.add_argument("--dry-run", action="store_true", help="print downloads without fetching")
    ap.add_argument("--locations", help="Earth locations CSV from the location filter (name, lat, lon)")
    args = ap.parse_args(argv)

    global EARTH_LOCATIONS_CSV
    EARTH_LOCATIONS_CSV = args.locations

    if args.list:
        for n, s in SOURCES.items():
            print(f"{'ON ' if s['enabled'] else 'off'}  {n:20s} {s['desc']}")
        return

    unknown = [n for n in args.sources if n not in SOURCES]
    if unknown:
        sys.exit(f"Unknown source(s): {unknown}. Use --list.")
    names = args.sources or [n for n, s in SOURCES.items() if s["enabled"]]

    summary = {}
    for n in names:
        src = SOURCES[n]
        if not src["enabled"] and not args.sources:
            continue
        print(f"\n[{n}] {src['desc']}")
        out = os.path.join(OUT_ROOT, n)
        try:
            results = METHODS[src["method"]](n, src, out, args.dry_run)
        except Exception as e:
            print(f"    error: {e}")
            results = ["failed"]
        summary[n] = {k: results.count(k) for k in set(results)}

    print("\nSummary:")
    for n, counts in summary.items():
        print(f"  {n:20s} {counts}")


if __name__ == "__main__":
    main()
