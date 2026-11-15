"""Parse scraped HTML/JSON listings to extract downloadable URLs."""
import json
import re
import sys
from pathlib import Path


def parse_pds_listing(html_path, base_url):
    """Parse a WUSTL PDS directory listing into (name, size, url) tuples."""
    text = Path(html_path).read_text(encoding="utf-8", errors="ignore")
    # Entries look like: SIZE <A HREF="/path/to/file.ext">file.ext</A>
    pattern = re.compile(
        r'(\d+)\s+<A\s+HREF="([^"]+)">([^<]+)</A>',
        re.IGNORECASE,
    )
    results = []
    for size_str, href, name in pattern.findall(text):
        # Skip parent directory link
        if "Parent" in name or name.endswith("/"):
            continue
        url = base_url.rstrip("/") + "/" + href.lstrip("/")
        # Actually href is absolute path on same host; build full URL
        if href.startswith("/"):
            # scheme://host from base_url
            m = re.match(r"(https?://[^/]+)", base_url)
            host = m.group(1) if m else base_url
            url = host + href
        results.append((name, int(size_str), url))
    return results


def main():
    out = {}

    # GRS
    grs = parse_pds_listing(
        ".temp/grs_listing.html",
        "https://pds-geosciences.wustl.edu",
    )
    out["grs"] = grs
    print(f"GRS: {len(grs)} files, total {sum(s for _, s, _ in grs)} bytes")
    for n, s, u in grs:
        print(f"  {n}  {s}")

    print()

    # MOLA
    mola = parse_pds_listing(
        ".temp/mola_listing.html",
        "https://pds-geosciences.wustl.edu",
    )
    out["mola"] = mola
    print(f"MOLA: {len(mola)} entries, total {sum(s for _, s, _ in mola)} bytes")
    # Show just the .img entries
    img_files = [x for x in mola if x[0].lower().endswith(".img")]
    print(f"  .img files: {len(img_files)}")
    for n, s, u in img_files[:6]:
        print(f"  {n}  {s // (1024*1024)} MB")

    # Save
    Path(".temp/parsed_listings.json").write_text(json.dumps(out, indent=2))


if __name__ == "__main__":
    main()
