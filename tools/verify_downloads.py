"""Verify downloaded files: check sizes against manifests and MD5 if available.
Also inspect binary files for valid magic bytes.
"""
import hashlib
import json
from pathlib import Path


def md5_of(path, chunk=65536):
    h = hashlib.md5()
    with open(path, "rb") as f:
        while True:
            b = f.read(chunk)
            if not b:
                break
            h.update(b)
    return h.hexdigest()


def check_manifest(manifest_path):
    print(f"\n=== {manifest_path} ===")
    items = json.loads(Path(manifest_path).read_text())
    ok = fail = missing = 0
    for item in items:
        dest = Path(item["dest"])
        if not dest.exists():
            print(f"  MISSING: {dest}")
            missing += 1
            continue
        size = dest.stat().st_size
        exp_size = item.get("size")
        if exp_size is not None and size != exp_size:
            print(f"  SIZE MISMATCH: {dest.name} got {size} expected {exp_size}")
            fail += 1
            continue
        exp_md5 = item.get("md5")
        if exp_md5:
            got = md5_of(dest)
            if got != exp_md5:
                print(f"  MD5 MISMATCH: {dest.name} got {got} expected {exp_md5}")
                fail += 1
                continue
            print(f"  OK (md5): {dest.name} ({size:,} B)")
        else:
            print(f"  OK (size): {dest.name} ({size:,} B)")
        ok += 1
    print(
        f"  ---> {ok} ok, {fail} failed, {missing} missing "
        f"of {len(items)}"
    )
    return ok, fail, missing


def check_magic(path, expected_prefix, label):
    p = Path(path)
    if not p.exists():
        print(f"  MISSING: {p}")
        return False
    with open(p, "rb") as f:
        head = f.read(len(expected_prefix))
    ok = head.startswith(expected_prefix)
    print(f"  {label}: {p.name} magic={head!r} ok={ok}")
    return ok


def main():
    totals = [0, 0, 0]
    for m in [
        "tools/manifest_gullies.json",
        "tools/manifest_pdg_icewedge.json",
        "tools/manifest_non_zenodo.json",
    ]:
        if Path(m).exists():
            r = check_manifest(m)
            for i in range(3):
                totals[i] += r[i]

    print("\n=== Magic byte spot-checks ===")
    # PDF
    check_magic(
        "data/real/earth_lava_tubes_polito/"
        "Sauro_2020_Lava_Tubes_crosssections.pdf",
        b"%PDF-",
        "PDF",
    )
    # ZIP (MGC3)
    check_magic(
        "data/real/mars_caves_mgc3/mars_cave_catalog.zip",
        b"PK\x03\x04",
        "ZIP",
    )
    # Shapefile (ESRI shp = 0x00 00 27 0a)
    check_magic(
        "data/real/mars_gullies_noblet/GlobalGullies_ANoblet.shp",
        b"\x00\x00\x27\x0a",
        "SHP",
    )
    # PNG (PDG pipeline diagram)
    check_magic(
        "data/real/earth_pdg_icewedge/Ice_Wedge_Polygon_Pipeline.png",
        b"\x89PNG\r\n\x1a\n",
        "PNG",
    )
    # EML metadata (XML)
    check_magic(
        "data/real/earth_pdg_icewedge/"
        "Ice_wedge_polygon_detection_in_satellite_imagery.xml",
        b"<?xml",
        "XML",
    )
    # PDG provenance PDF
    check_magic(
        "data/real/earth_pdg_icewedge/"
        "PGC_Commercial_Satellite_Imagery_Documentation.pdf",
        b"%PDF-",
        "PDF",
    )

    print(
        f"\nGrand total: {totals[0]} ok, {totals[1]} failed, {totals[2]} missing"
    )


if __name__ == "__main__":
    main()
