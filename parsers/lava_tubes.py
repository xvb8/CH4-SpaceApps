"""Earth lava tube regions from data/real/earth_lava_tubes_polito/*.pdf (Table 1).

Note: the file named Sauro_2020_Lava_Tubes_crosssections.pdf is actually
Romio & Lobosco (2025), "Underground landscapes: volcanism, lava tubes, and man"
(Tunnelling and Underground Space Technology 162, 106618). It has no cross-section
measurements or coordinates. Its Table 1 ("Synthetic summary of the Atlas of Lava
Tube Uses") lists country, region, uses and years, which is what this extracts.

Output feeds no score (no coordinates or sizes); it records which Earth regions
have documented lava tubes. Run:  python3 -m parsers.lava_tubes
"""

import csv
import glob
import os
import re

from parsers.geo import DATA_ROOT

DEFAULT_FOLDER = os.path.join(DATA_ROOT, "earth_lava_tubes_polito")
OUT_FILE = os.path.join(os.path.dirname(DATA_ROOT), "parsed", "earth_lava_tube_regions.csv")

COUNTRIES = ["United States", "South Korea", "Saudi Arabia", "Iceland", "Spain", "Italy", "Jordan",
             "Kenya", "China", "Vietnam", "Australia", "Portugal", "Japan"]
USE_STARTS = ["Ritualistic", "Shelter", "Catchment", "Ice mining", "Temporary", "Habitation",
              "Tourism", "Touristic", "Permanent", "Mining", "No data, tourism"]
# PDF text extraction garbles some diacritics
REGION_FIXES = {"Đ ˘a ´ ắk N ˆong province": "Đắk Nông province"}
YEAR_START = r"(From |Unknown|No data;|Used at least|\d{4} (?:to|CE)|\d{4}\s*CE)"


def _table_text(pdf_path):
    import pypdf
    pages = [p.extract_text() or "" for p in pypdf.PdfReader(pdf_path).pages]
    text = "\n".join(pages[:8])
    start = re.search(r"Table\s*\n?\s*1\s*\n?\s*Synthetic summary", text)
    end = text.find("*For", start.end() if start else 0)
    if not start or end < 0:
        return ""
    body = text[start.end():end]
    body = re.sub(r"Table\s*\n?\s*1\s*\(\s*continued\s*\).*?Utilization", " ", body, flags=re.S)
    body = re.sub(r"F\.A\.P\..*?\n\s*\d+\s*\n", " ", body, flags=re.S)  # page footer
    body = body.split("Utilization", 2)[-1]  # drop the header row
    return re.sub(r"\s+", " ", body.replace("-\n", "")).strip()


def parse_table(pdf_path):
    text = _table_text(pdf_path)
    pat = "|".join(re.escape(c).replace(r"\ ", r"\s+") for c in COUNTRIES)
    hits = list(re.finditer(r"(?:^|(?<=[\s.)\d]))(%s)\s" % pat, text))
    rows = []
    for a, b in zip(hits, hits[1:] + [None]):
        country = re.sub(r"\s+", " ", a.group(1))
        rest = text[a.end():b.start() if b else len(text)].strip()
        y = re.search(YEAR_START, rest)
        years = rest[y.start():].strip() if y else ""
        head = rest[:y.start()].strip() if y else rest
        u = min((head.find(w) for w in USE_STARTS if head.find(w) > 0), default=-1)
        region, uses = (head[:u].strip(), head[u:].strip()) if u > 0 else (head, "")
        years = re.sub(r"\s*Years of Utilization\s*$", "", years)
        if rows and not rows[-1]["uses"] and not rows[-1]["years"]:
            # "Western Iceland": the country name inside the region split the row
            prev = rows.pop()
            region = f"{prev['region']} {country}".strip()
            u = min((rest.find(w) for w in USE_STARTS if rest.find(w) >= 0), default=-1)
            uses = rest[u:y.start()].strip() if (u >= 0 and y) else rest
            if not y:
                years = ""
        region = REGION_FIXES.get(region, region)
        rows.append({"country": country, "region": region, "uses": uses, "years": years})
    return rows


def main():
    pdfs = glob.glob(os.path.join(DEFAULT_FOLDER, "*.pdf"))
    if not pdfs:
        print("no lava tube PDF found")
        return
    rows = parse_table(pdfs[0])
    os.makedirs(os.path.dirname(OUT_FILE), exist_ok=True)
    with open(OUT_FILE, "w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=["country", "region", "uses", "years"])
        w.writeheader()
        w.writerows(rows)
    print(f"wrote {len(rows)} rows to {OUT_FILE}")


if __name__ == "__main__":
    main()
