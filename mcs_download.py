"""
MCS DDR bulk downloader. Run this on your own computer (the Snowflake sandbox
cannot reach the PDS website).

    python mcs_download.py

It downloads, for each chosen month, the chosen days (default: 1st and 15th),
all 6 four-hour files per day (.TAB + .LBL), plus the two .FMT format files once.
Files already downloaded are skipped, so it can be stopped and restarted.

BEFORE RUNNING: set DAY_FOLDER_URL to match the site.
Open any day folder in your browser (the page listing 2025070100_DDR.LBL etc.),
copy its address, and replace the parts that change with {volume}, {yyyy},
{yyyymm}, {yyyymmdd}. Do the same for LABEL_FOLDER_URL with the LABEL/ folder.
"""

import os
import sys
import time
import urllib.error
import urllib.request
from datetime import date

# ---------------------------------------------------------------------------
# Settings
# ---------------------------------------------------------------------------

# Example shape only - CHECK against your browser address bar and edit.
DAY_FOLDER_URL = "https://atmos.nmsu.edu/PDS/data/{volume}/DATA/{yyyy}/{yyyymm}/{yyyymmdd}/"
LABEL_FOLDER_URL = "https://atmos.nmsu.edu/PDS/data/{volume}/LABEL/"

# Months to download (inclusive). mrom_2100 = Dec 2014 ... mrom_2122 = Oct 2016
FIRST_MONTH = (2014, 12)
LAST_MONTH = (2016, 10)

DAYS_OF_MONTH = [1, 15]          # days sampled per month
HOURS = ["00", "04", "08", "12", "16", "20"]   # the 6 four-hour files per day
FMT_FILES = ["MCS_DDR1.FMT", "MCS_DDR2.FMT"]

OUT_DIR = "mcs_data"

# Volumes with no data (MCS off Sep-Nov 2009; no mrom_2213)
MISSING_VOLUMES = {"mrom_2037", "mrom_2038", "mrom_2039", "mrom_2213"}


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def volume_for(year, month):
    """mrom_2001 = Sep 2006, +1 per Earth month."""
    n = (year - 2006) * 12 + (month - 9) + 1
    return f"mrom_{2000 + n}"


def months(first, last):
    y, m = first
    while (y, m) <= last:
        yield y, m
        m += 1
        if m == 13:
            y, m = y + 1, 1


def download(url, path, retries=3):
    if os.path.exists(path) and os.path.getsize(path) > 0:
        return "skip"
    os.makedirs(os.path.dirname(path), exist_ok=True)
    for attempt in range(retries):
        try:
            with urllib.request.urlopen(url, timeout=120) as r, open(path + ".part", "wb") as f:
                while chunk := r.read(1 << 20):
                    f.write(chunk)
            os.replace(path + ".part", path)
            return "ok"
        except urllib.error.HTTPError as e:
            if e.code == 404:
                return "missing"
            time.sleep(5 * (attempt + 1))
        except Exception:
            time.sleep(5 * (attempt + 1))
    return "failed"


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main():
    counts = {"ok": 0, "skip": 0, "missing": 0, "failed": 0}
    fmt_done = False

    for year, month in months(FIRST_MONTH, LAST_MONTH):
        volume = volume_for(year, month)
        if volume in MISSING_VOLUMES:
            print(f"{volume}: no data for {year}-{month:02d}, skipped")
            continue

        if not fmt_done:
            for fmt in FMT_FILES:
                url = LABEL_FOLDER_URL.format(volume=volume) + fmt
                status = download(url, os.path.join(OUT_DIR, fmt))
                print(f"{fmt}: {status}")
            fmt_done = True

        for day in DAYS_OF_MONTH:
            try:
                d = date(year, month, day)
            except ValueError:
                continue
            folder = DAY_FOLDER_URL.format(volume=volume, yyyy=f"{d:%Y}",
                                           yyyymm=f"{d:%Y%m}", yyyymmdd=f"{d:%Y%m%d}")
            for hour in HOURS:
                for ext in ("LBL", "TAB"):
                    name = f"{d:%Y%m%d}{hour}_DDR.{ext}"
                    status = download(folder + name, os.path.join(OUT_DIR, volume, name))
                    counts[status] += 1
                    if status in ("missing", "failed"):
                        print(f"  {name}: {status}")
            print(f"{volume} {d}: done")

    print("\nSummary:", counts)
    if counts["missing"] and not counts["ok"] and not counts["skip"]:
        print("Every file was missing - DAY_FOLDER_URL is probably wrong. Check it in a browser.")
        sys.exit(1)


if __name__ == "__main__":
    main()
