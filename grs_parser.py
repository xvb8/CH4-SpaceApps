"""
GRS parser: reads Mars Odyssey GRS 5x5 element files (PDS3 .lbl + .tab).

Standalone for now (not connected to chemical_composition.py yet).

Usage per element:
    table = read_grs("fe_5x5.lbl")              # finds fe_5x5.tab via the label
    grid  = to_grid(table)                       # {(lat, lon): value}
    save_grid_csv(grid, "mars_fe_grid.csv")      # lat, lon, value

The .lbl label describes the columns (name, start byte, width, missing value).
Column choices for lat / lon / value are guessed from the column names and can
be overridden once the real labels have been checked.
"""

import os
import re

ELEMENT_FILES = {
    "cl": "cl_5x5.lbl",
    "fe": "fe_5x5.lbl",
    "h2o": "h2o_5x5.lbl",
    "k": "k_5x5.lbl",
    "si": "si_5x5.lbl",
    "th": "th_5x5.lbl",
}


# ---------------------------------------------------------------------------
# PDS3 label parsing
# ---------------------------------------------------------------------------

def _clean(value):
    value = value.strip().strip('"').strip()
    return re.sub(r"\s+", " ", value)


def parse_label(lbl_path):
    """
    Read a PDS3 .lbl and return:
      {"table_file": str|None, "rows": int|None, "row_bytes": int|None,
       "columns": [{"name", "start_byte", "bytes", "unit", "missing"}]}
    """
    with open(lbl_path, "r", errors="replace") as f:
        text = f.read()

    info = {"table_file": None, "rows": None, "row_bytes": None, "columns": []}

    m = re.search(r'\^TABLE\s*=\s*\(?\s*"?([^",)\s]+)"?', text)
    if m:
        info["table_file"] = m.group(1)
    for key, field in (("ROWS", "rows"), ("ROW_BYTES", "row_bytes")):
        m = re.search(rf"\b{key}\s*=\s*(\d+)", text)
        if m:
            info[field] = int(m.group(1))

    for block in re.findall(r"OBJECT\s*=\s*COLUMN(.*?)END_OBJECT\s*=\s*COLUMN", text, re.DOTALL):
        col = {}
        # Works whether KEY = value pairs are one per line or several per line
        for key, value in re.findall(r'(\w+)\s*=\s*("[^"]*"|\S+)', block):
            col[key.upper()] = _clean(value)
        if "NAME" not in col:
            continue
        missing = (col.get("MISSING_CONSTANT") or col.get("INVALID_CONSTANT")
                   or col.get("NOT_APPLICABLE_CONSTANT"))
        info["columns"].append({
            "name": col["NAME"],
            "start_byte": int(col["START_BYTE"]) if "START_BYTE" in col else None,
            "bytes": int(col["BYTES"]) if "BYTES" in col else None,
            "unit": col.get("UNIT"),
            "missing": float(missing) if missing and _is_number(missing) else None,
        })
    return info


def _is_number(s):
    try:
        float(s)
        return True
    except ValueError:
        return False


# ---------------------------------------------------------------------------
# Table reading
# ---------------------------------------------------------------------------

def _find_table(lbl_path, table_file):
    folder = os.path.dirname(lbl_path) or "."
    candidates = []
    if table_file:
        candidates += [table_file, table_file.lower(), table_file.upper()]
    stem = os.path.splitext(os.path.basename(lbl_path))[0]
    candidates += [stem + ".tab", stem + ".TAB"]
    for name in candidates:
        path = os.path.join(folder, name)
        if os.path.exists(path):
            return path
    raise FileNotFoundError(f"No table file found next to {lbl_path} (tried {candidates})")


# GRS labels mark invalid cells as 9999.999 (description says 9999.999999)
INVALID_AT_OR_ABOVE = 9999.0


def read_grs(lbl_path):
    """
    Read one element: parse the label, then read its .tab.
    Returns {"columns": [names], "units": {name: unit}, "rows": [{name: float|None}]}.
    Values equal to the label's missing constant become None.
    """
    label = parse_label(lbl_path)
    tab_path = _find_table(lbl_path, label["table_file"])
    cols = label["columns"]
    fixed_width = cols and all(c["start_byte"] and c["bytes"] for c in cols)

    rows = []
    with open(tab_path, "r", errors="replace") as f:
        for line in f:
            if not line.strip():
                continue
            if fixed_width:
                raw = [line[c["start_byte"] - 1: c["start_byte"] - 1 + c["bytes"]] for c in cols]
            else:
                raw = re.split(r"[,\s]+", line.strip())
            row = {}
            for i, c in enumerate(cols or [{"name": f"col{i}", "missing": None} for i in range(len(raw))]):
                text = raw[i].strip().strip('"') if i < len(raw) else ""
                val = float(text) if _is_number(text) else None
                if val is not None and (val >= INVALID_AT_OR_ABOVE or
                                        (c.get("missing") is not None and val == c["missing"])):
                    val = None
                row[c["name"]] = val
            rows.append(row)

    names = [c["name"] for c in cols] if cols else list(rows[0]) if rows else []
    return {"columns": names, "units": {c["name"]: c["unit"] for c in cols}, "rows": rows}


# ---------------------------------------------------------------------------
# Column selection and grid output
# ---------------------------------------------------------------------------

def _guess(columns, keywords, exclude=()):
    for name in columns:
        low = name.lower()
        if any(k in low for k in keywords) and not any(x in low for x in exclude):
            return name
    return None


def to_grid(table, lat_col=None, lon_col=None, value_col=None, clip_negative=True):
    """
    Convert parsed rows to {(lat, lon): value}. Rows with a missing value are skipped.
    Negative concentrations (background > signal, per the GRS label) are set to 0
    when clip_negative=True, since the Basic ratio rule cannot handle negatives.
    Column names are guessed if not given; pass them explicitly once labels are checked.
    """
    cols = table["columns"]
    lat_col = lat_col or _guess(cols, ["lat"])
    lon_col = lon_col or _guess(cols, ["lon"])
    value_col = value_col or _guess(cols, ["conc", "abund", "wt", "value", "ppm", "frac"],
                                    exclude=["err", "sigma", "unc", "lat", "lon"])
    if not (lat_col and lon_col and value_col):
        raise ValueError(f"Could not pick lat/lon/value from columns {cols}; pass them explicitly.")

    grid = {}
    for row in table["rows"]:
        lat, lon, val = row.get(lat_col), row.get(lon_col), row.get(value_col)
        if lat is None or lon is None or val is None:
            continue
        grid[(lat, lon)] = max(val, 0.0) if clip_negative else val
    return grid


def save_grid_csv(grid, path):
    import csv
    with open(path, "w", newline="") as f:
        w = csv.writer(f)
        w.writerow(["lat", "lon", "value"])
        for (lat, lon), val in sorted(grid.items()):
            w.writerow([lat, lon, val])


def parse_all(folder, out_folder=None):
    """Parse every element in ELEMENT_FILES found in folder; write <element>_grid.csv."""
    out_folder = out_folder or folder
    results = {}
    for element, lbl in ELEMENT_FILES.items():
        path = os.path.join(folder, lbl)
        if not os.path.exists(path):
            print(f"{element}: {lbl} not found, skipped")
            continue
        table = read_grs(path)
        grid = to_grid(table)
        save_grid_csv(grid, os.path.join(out_folder, f"{element}_grid.csv"))
        results[element] = grid
        print(f"{element}: {len(grid)} cells, columns={table['columns']}")
    return results


if __name__ == "__main__":
    import sys
    parse_all(sys.argv[1] if len(sys.argv) > 1 else "grs_data")
