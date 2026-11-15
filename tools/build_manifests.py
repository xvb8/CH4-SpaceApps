"""Generate download manifests for all datasets from parsed metadata."""
import json
from pathlib import Path


def main():
    # --- Ice-wedge (Zenodo 10522820) ---
    zi = json.loads(Path(".temp/zenodo_icewedge.json").read_text())
    ice_manifest = []
    for f in zi.get("files", []):
        ice_manifest.append({
            "url": f["links"]["self"],
            "dest": f"data/real/earth_ice_wedge_polygons/{f['key']}",
            "size": f["size"],
            "md5": f["checksum"].replace("md5:", ""),
        })
    Path("tools/manifest_icewedge.json").write_text(
        json.dumps(ice_manifest, indent=2)
    )
    total = sum(x["size"] for x in ice_manifest)
    print(f"Wrote manifest_icewedge.json: {len(ice_manifest)} files, {total/1024:.1f} KB")

    # --- MGC3 cave catalog (single zip) ---
    mgc3 = [{
        "url": "https://astrogeology.usgs.gov/ckan/dataset/c2960f77-ee20-4cc6-ac85-abbecc0fc7f6/resource/ccd54fb2-9a50-46bf-8971-80c241bb2f40/download/mars_cave_catalog.zip",
        "dest": "data/real/mars_caves_mgc3/mars_cave_catalog.zip",
    }]
    Path("tools/manifest_mgc3.json").write_text(json.dumps(mgc3, indent=2))
    print(f"Wrote manifest_mgc3.json: {len(mgc3)} file")

    # --- MOLA sample tiles (first 2 .img + their .lbl/.hdr + inventory) ---
    listings = json.loads(Path(".temp/parsed_listings.json").read_text())
    mola_files = listings["mola"]
    # Pick small files + 2 sample image tiles for 0-44N
    keep_prefixes = ("megc00n000hb", "megc00n090hb")
    keep_small = {"collection_data_meg128.xml", "collection_data_meg128_inventory.csv"}
    mola_manifest = []
    for name, size, url in mola_files:
        base = name.split(".")[0]
        if name in keep_small or (base in keep_prefixes):
            mola_manifest.append({
                "url": url,
                "dest": f"data/real/mars_mola_megdr/{name}",
                "size": size,
            })
    Path("tools/manifest_mola.json").write_text(json.dumps(mola_manifest, indent=2))
    total = sum(x["size"] for x in mola_manifest)
    print(
        f"Wrote manifest_mola.json: {len(mola_manifest)} files, "
        f"{total/(1024*1024):.1f} MB"
    )

    # --- GRS (all 18 files, tiny) ---
    grs_files = listings["grs"]
    grs_manifest = []
    for name, size, url in grs_files:
        grs_manifest.append({
            "url": url,
            "dest": f"data/real/mars_odyssey_grs/{name}",
            "size": size,
        })
    Path("tools/manifest_grs.json").write_text(json.dumps(grs_manifest, indent=2))
    total = sum(x["size"] for x in grs_manifest)
    print(f"Wrote manifest_grs.json: {len(grs_manifest)} files, {total/1024:.1f} KB")


if __name__ == "__main__":
    main()
