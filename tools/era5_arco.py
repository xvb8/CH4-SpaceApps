#!/usr/bin/env python3
"""era5_arco.py -- stream ERA5 variables from the ECMWF ARCO Zarr API.

The ECMWF ARCO (Analysis-Ready, Cloud-Optimized) store exposes the entire
ERA5 reanalysis as four Zarr datasets, two chunked by geography and two
by time.  Access requires a CDS API key (free account at
https://cds.climate.copernicus.eu/profile).  The key is read from the
CDS_API_KEY environment variable or ~/.cdsapirc (standard cdsapi format).

Four endpoints (verbatim from ECMWF documentation):
    surface_geo_url  : single-level fields, GEO-chunked
                       -> optimised for time-series at a single point
    surface_time_url : single-level fields, TIME-chunked
                       -> optimised for global maps at a given timestamp
    wave_geo_url     : ocean-wave fields,   GEO-chunked
    wave_time_url    : ocean-wave fields,   TIME-chunked

Choose "geo" for a few points over a long time span,
choose "time" for a short time window over a wide spatial region.

Usage:
    # Get 2 m temperature + skin temperature over a 10x10 deg box for a year
    python tools\\era5_arco.py --vars t2m,skt \\
        --bbox 60 -10 70 20 \\
        --start 2023-01-01 --end 2023-12-31 \\
        --out data/real/era5/arctic_t2m_2023.nc

    # Point time-series at Svalbard for the past decade (surface, time-chunked)
    python tools\\era5_arco.py --vars t2m,tp,sf \\
        --point 78.2 15.6 --start 2015-01-01 --end 2024-12-31 \\
        --store time --out data/real/era5/svalbard_point.nc

    # List available variables in the store without downloading anything
    python tools\\era5_arco.py --list --store geo

Dependencies: xarray, zarr, fsspec, requests, netCDF4.
    pip install "xarray>=2024.1" zarr fsspec requests netCDF4
"""
from __future__ import annotations
import argparse, os, sys
from pathlib import Path

URLS = {
    "surface_geo":  "https://arco.datastores.ecmwf.int/cadl-arco-geo-002/arco/reanalysis_era5_single_levels/sfc/geoChunked.zarr",
    "surface_time": "https://arco.datastores.ecmwf.int/cadl-arco-time-002/arco/reanalysis_era5_single_levels/sfc/timeChunked.zarr",
    "wave_geo":     "https://arco.datastores.ecmwf.int/cadl-arco-geo-003/arco/reanalysis_era5_single_levels/wav/geoChunked.zarr",
    "wave_time":    "https://arco.datastores.ecmwf.int/cadl-arco-time-003/arco/reanalysis_era5_single_levels/wav/timeChunked.zarr",
}


def get_cds_api_key() -> str:
    key = os.environ.get("CDS_API_KEY") or os.environ.get("CDSAPI_KEY")
    if key:
        return key.strip()
    rc = Path.home() / ".cdsapirc"
    if rc.exists():
        for line in rc.read_text().splitlines():
            line = line.strip()
            if line.startswith("key:"):
                return line.split(":", 1)[1].strip()
    raise SystemExit(
        "ERROR: CDS API key not found.  Set CDS_API_KEY env var or create "
        "~/.cdsapirc with a 'key: <your-key>' line "
        "(see https://cds.climate.copernicus.eu/how-to-api)."
    )


def open_store(product: str, variant: str):
    """Open one of the four ARCO Zarr stores with the CDS Bearer header."""
    import xarray as xr

    key = get_cds_api_key()
    name = f"{product}_{variant}"
    if name not in URLS:
        raise SystemExit(f"Unknown store '{name}'.  Valid: {list(URLS)}")
    url = URLS[name]
    print(f"Opening {name}: {url}", file=sys.stderr)
    ds = xr.open_zarr(
        url,
        consolidated=True,
        storage_options={"headers": {"Authorization": f"Bearer {key}"}},
    )
    return ds, url


def select(ds, variables, bbox=None, point=None, start=None, end=None):
    """Subset ds by variables, spatial region (bbox or point), and time."""
    if variables:
        missing = [v for v in variables if v not in ds.data_vars]
        if missing:
            raise SystemExit(
                f"Variables not in store: {missing}.  "
                f"Available: {sorted(list(ds.data_vars))[:40]} ..."
            )
        ds = ds[variables]

    if start or end:
        ds = ds.sel(time=slice(start, end))

    if bbox is not None:
        south, west, north, east = bbox
        # ERA5 latitude is descending (90 -> -90); use slice(north, south)
        lat_da = ds["latitude"] if "latitude" in ds.coords else ds["lat"]
        lat_name = lat_da.name
        lat_slice = slice(north, south) if float(lat_da[0]) > float(lat_da[-1]) \
                    else slice(south, north)
        ds = ds.sel({lat_name: lat_slice})
        lon_name = "longitude" if "longitude" in ds.coords else "lon"
        # ERA5 longitude is [0, 360).  If user passed a negative value,
        # wrap it into that range before slicing.
        if west < 0:
            west += 360
        if east < 0:
            east += 360
        if west <= east:
            ds = ds.sel({lon_name: slice(west, east)})
        else:
            # box crosses the anti-meridian -- concatenate both halves
            import xarray as xr
            ds = xr.concat(
                [ds.sel({lon_name: slice(west, 360)}),
                 ds.sel({lon_name: slice(0, east)})],
                dim=lon_name,
            )
    elif point is not None:
        lat, lon = point
        lat_name = "latitude" if "latitude" in ds.coords else "lat"
        lon_name = "longitude" if "longitude" in ds.coords else "lon"
        if lon < 0:
            lon += 360
        ds = ds.sel({lat_name: lat, lon_name: lon}, method="nearest")
    return ds


def main():
    ap = argparse.ArgumentParser(
        description="Stream ERA5 variables from the ECMWF ARCO Zarr store."
    )
    ap.add_argument("--vars", default="",
                    help="Comma-separated ERA5 variable names (e.g. t2m,tp,skt). "
                         "Omit together with --list to inspect the store.")
    ap.add_argument("--product", choices=["surface", "wave"], default="surface",
                    help="surface = single-level atmospheric, wave = ocean waves")
    ap.add_argument("--store", choices=["geo", "time"], default="geo",
                    help="geo = geo-chunked (good for point time-series); "
                         "time = time-chunked (good for global maps / spatial regions)")
    ap.add_argument("--bbox", nargs=4, type=float, metavar=("S", "W", "N", "E"),
                    help="Spatial bounding box in degrees "
                         "(S<N, W/E in [-180,180] or [0,360])")
    ap.add_argument("--point", nargs=2, type=float, metavar=("LAT", "LON"),
                    help="Single lat,lon (degrees).  Mutually exclusive with --bbox.")
    ap.add_argument("--start", help="ISO start date (e.g. 2023-01-01)")
    ap.add_argument("--end", help="ISO end date   (e.g. 2023-12-31)")
    ap.add_argument("--out", help="Output NetCDF path (.nc).  If omitted, "
                                  "prints dataset info to stdout.")
    ap.add_argument("--list", action="store_true",
                    help="Print the list of variables available in the store and exit")
    args = ap.parse_args()

    if args.bbox and args.point:
        raise SystemExit("--bbox and --point are mutually exclusive")

    ds, url = open_store(args.product, args.store)

    if args.list:
        print(f"\nVariables in {args.product}_{args.store}:")
        for v in sorted(ds.data_vars):
            da = ds[v]
            dims = ", ".join(f"{d}={ds.sizes[d]}" for d in da.dims)
            print(f"  {v:<10} [{dims}]  {da.attrs.get('long_name', '')}")
        print(f"\nTime coverage: {str(ds.time.values[0])[:10]}  ..  "
              f"{str(ds.time.values[-1])[:10]}")
        return

    variables = [v.strip() for v in args.vars.split(",") if v.strip()]
    if not variables:
        raise SystemExit("--vars is required (or use --list to see what is available)")

    sub = select(ds, variables,
                 bbox=args.bbox, point=args.point,
                 start=args.start, end=args.end)

    print("\nSelected dataset:", file=sys.stderr)
    print(sub, file=sys.stderr)

    if not args.out:
        return
    out = Path(args.out); out.parent.mkdir(parents=True, exist_ok=True)
    print(f"\nWriting NetCDF -> {out} ...", file=sys.stderr)
    sub.to_netcdf(out)
    print(f"  wrote {out.stat().st_size/1e6:.1f} MB", file=sys.stderr)


if __name__ == "__main__":
    main()
