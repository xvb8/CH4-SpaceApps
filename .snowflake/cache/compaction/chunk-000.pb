
�3
site_weights.py�3"""Mission-specific criterion weights for candidate Mars sites.

Step 2: s̄_k    = (1/N) Σ_i s_ik                      mean similarity of criterion k
Step 3: v_k    = sqrt[(1/N) Σ_i (s_ik - s̄_k)^2]       discriminating power (population std)
Step 4: w_k(m) = f_k(m)·v_k / Σ_j [f_j(m)·v_j]         normalized weight for mission m
Step 5: S_i(m) = Σ_k w_k(m)·s_ik                       final similarity score (weighted average)
"""
import math

# ---------------- Inputs (edit these) ----------------
# Criteria for similarities (k), grouped by category.
# Earth / Mars data sources noted per criterion.
categories = {
    "Rocks and minerals": [
        "geology_minerals",   # basaltic, phyllosilicates/clay, sulfates, carbonates, silica/evaporites
                              #   Earth: ASTER, EMIT, Landsat | Mars: CRISM, OMEGA
    ],
    "Landforms and terrain": [
        "topography",         # Earth: SRTM, Copernicus DEM | Mars: MOLA
        "trafficability",     # rock abundance & slope (slope < 15°, rock abundance < 10%)
                              #   Earth: DEM roughness, day/night ECOSTRESS/MODIS | Mars: THEMIS TI @ 100 m/px
        "aeolian_bedforms",   # dunes, ripples, megaripples
                              #   Earth: Sentinel-2, Landsat dune/ripple maps | Mars: HiRISE, CTX
        "caves",              # shielded subsurface: relative tube diameter, skylight/pit presence
        "volcanic_terrain",   # Earth: DEM + geology data | Mars: MOLA topography + geologic maps
    ],
    "Climate and radiation": [
        "temperature",        # mean, diurnal range, annual minimum
                              #   Earth: MODIS, ECOSTRESS | Mars: THEMIS
        "uv_radiation",       # Earth: UV index (OMI/TROPOMI) | Mars: surface UV index
        "aridity",            # biological habitability
                              #   Earth: aridity index, GPM precip, MODIS NDVI | Mars: water activity, humidity
    ],
    "Water, ice, and salts": [
        "ice_permafrost",     # Earth: permafrost maps | Mars: SHARAD radar, ice-exposing impacts
        "salt_deliquescence", # RH-T envelope
                              #   Earth: ERA5 hourly RH/T time-fraction above each salt's deliquescence point
                              #   Mars: modeled RH-T over chloride and perchlorate deposits
        "periglacial",        # patterned ground & gullies (freeze/thaw)
                              #   Earth: polygon/gully detection, high-res imagery | Mars: HiRISE, CTX
    ],
}
criteria = [c for group in categories.values() for c in group]

# Similarity scores s_ik: site i -> list of scores per criterion k (0-1), in `criteria` order:
#   geology, topo, traffic, aeolian, caves, volcanic, temp, uv, aridity, ice, salt, periglacial
site_scores = {
    "Jezero Crater":    [0.85, 0.60, 0.70, 0.55, 0.20, 0.45, 0.72, 0.40, 0.65, 0.30, 0.45, 0.25],
    "Gale Crater":      [0.78, 0.55, 0.60, 0.80, 0.15, 0.30, 0.68, 0.42, 0.60, 0.25, 0.50, 0.20],
    "Utopia Planitia":  [0.50, 0.90, 0.85, 0.40, 0.25, 0.60, 0.80, 0.45, 0.55, 0.90, 0.60, 0.85],
    "Meridiani Planum": [0.70, 0.85, 0.90, 0.75, 0.10, 0.25, 0.65, 0.41, 0.70, 0.20, 0.55, 0.15],
    "Hellas Basin":     [0.60, 0.40, 0.45, 0.50, 0.20, 0.55, 0.75, 0.55, 0.50, 0.75, 0.65, 0.70],
}

# Fidelity importance f_k(m): mission m -> list per criterion k (0-1 judgment), same order
mission_fidelity = {
    "Rover mobility test": [0.2, 1.0, 1.0, 0.8, 0.1, 0.3, 0.3, 0.1, 0.2, 0.2, 0.1, 0.4],
    "Astrobiology":        [1.0, 0.3, 0.2, 0.2, 0.8, 0.4, 0.6, 0.7, 1.0, 0.8, 0.9, 0.6],
    "Habitat analog":      [0.3, 0.5, 0.6, 0.3, 0.9, 0.5, 0.9, 1.0, 0.6, 0.8, 0.3, 0.4],
}
# ------------------------------------------------------


def criterion_means(scores, n_criteria):
    """s̄_k = (1/N) Σ_i s_ik"""
    N = len(scores)
    return [sum(s[k] for s in scores.values()) / N for k in range(n_criteria)]


def criterion_spread(scores, means):
    """v_k = sqrt[(1/N) Σ_i (s_ik - s̄_k)^2]"""
    N = len(scores)
    return [
        math.sqrt(sum((s[k] - means[k]) ** 2 for s in scores.values()) / N)
        for k in range(len(means))
    ]


def mission_weights(fidelity, spread):
    """w_k(m) = f_k(m)·v_k / Σ_j f_j(m)·v_j"""
    products = [f * v for f, v in zip(fidelity, spread)]
    total = sum(products)
    if total == 0:
        raise ValueError("Σ f_j(m)·v_j is zero; weights undefined for this mission.")
    return [p / total for p in products]


def final_similarity_score(site_score, weight):
    """S_i(m) = Σ_k w_k(m)·s_ik  (weights sum to 1, so this is a weighted average)"""
    return sum(w * s for w, s in zip(weight, site_score))


def validate(criteria, scores, fidelity_by_mission):
    K = len(criteria)
    for site, s in scores.items():
        if len(s) != K:
            raise ValueError(f"Site '{site}' has {len(s)} scores, expected {K}.")
        if any(not 0 <= x <= 1 for x in s):
            raise ValueError(f"Site '{site}' scores must be in [0, 1].")
    for m, f in fidelity_by_mission.items():
        if len(f) != K:
            raise ValueError(f"Mission '{m}' has {len(f)} fidelities, expected {K}.")
        if any(not 0 <= x <= 1 for x in f):
            raise ValueError(f"Mission '{m}' fidelities must be in [0, 1].")


validate(criteria, site_scores, mission_fidelity)
K = len(criteria)
s_bar = criterion_means(site_scores, K)
v = criterion_spread(site_scores, s_bar)
weights = {m: mission_weights(f, v) for m, f in mission_fidelity.items()}

# final_similarity_scores[m][site] = S_i(m)
final_similarity_scores = {
    m: {site: final_similarity_score(s, w) for site, s in site_scores.items()}
    for m, w in weights.items()
}

print(f"N = {len(site_scores)} sites, K = {K} criteria\n")
print(f"{'criterion':<22}{'s̄_k':>8}{'v_k':>8}")
k = 0
for cat, group in categories.items():
    print(f"[{cat}]")
    for c in group:
        print(f"  {c:<20}{s_bar[k]:>8.4f}{v[k]:>8.4f}")
        k += 1

for m, w in weights.items():
    print(f"\nMission: {m}  (Σw = {sum(w):.4f})")
    k = 0
    for cat, group in categories.items():
        cat_w = sum(w[k:k + len(group)])
        print(f"  [{cat}]  subtotal {cat_w:.4f}")
        for c in group:
            print(f"    {c:<20}{w[k]:>8.4f}")
            k += 1

print("\n=== Final similarity score S_i(m), ranked ===")
for m, scores in final_similarity_scores.items():
    print(f"\nMission: {m}")
    for rank, (site, score) in enumerate(
        sorted(scores.items(), key=lambda kv: kv[1], reverse=True), start=1
    ):
        print(f"  {rank}. {site:<20}{score:>8.4f}")
*
���� 8d705e404afe7a918c30d32ebf7172cf
�t
datasources.md�s**Criteria for similarities:**

**Rocks and minerals**

* Geology and Minerals (chemical composition)  
- Basaltic  
- Phyllosilicates/clay  
- Sulfates  
- Carbonates  
- Silica/Evaporites  
- Earth data: ASTER, EMIT, Landsat  
- Mars data: CRISM, OMEGA

Rationale: The chemical composition of the minerals can affect instrument (i.e. equipment and drill) behavior and influence the structure, material, and design of our mars equipment.

**Landforms and terrain**

* Topography  
- Topography on Earth: SRTM data and Copernicus DEM data  
- Topography on Mars: MOLA data

	Rationale: The topography (elevation) can affect the descent & landing while impacting a location’s likelihood to be a plausible mars landing site (or base).

* Aeolian bedforms (dunes, ripples, megaripples)  
- Earth data: Dune and ripple maps from Sentinel-2 and Landsat (measuring bedford size/spacing)  
- Mars: HiRISE and CTX (measuring bedford size/spacing)

Rationale: The wind causing sand dunes and ripples may affect the rover on mars, wearing the rover out while also decreasing the solar panel’s solar irradiance.

* Caves (shielded subsurface environment):  
- Relative sizes of cave tube diameter  
- Skylight/pit presence

	Rationale: subsurface caves on Mars act as a means of shelter for people and equipment from radiation and temperature. 

**Climate and radiation**

* Temperature (mean, diurnal range, and annual minimum)  
- Thermal data on earth: MODIS and ECOSTRESS  
- THEMIS on Mars

	Rationale: The temperature may affect battery health in electronics, cause stress on certain material, and impact the structural design and materials of the rover, space suit, landing equipment, and rocket modules. 

* UV radiation  
- Earth: UV index (OMI/TROPOMI)  
- Mars: Surface UV index

	Rationale: UV radiation may damage equipment and technology, requiring UV resistant materials around all equipment.

* Aridity and water availability (biological habitability)  
- Earth: Aridity index, GPM precipitation, MODIS NDVI vegetation cover  
- Mars: Water activity and humidity level

	Rationale: Aridity affects where microbes and primitive organisms can survive on mars. Simulating the appropriate aridity may also help us better understand Mars’ climate. 

**Water, ice, and salts**

* Ice & Permafrost  
- Earth: ice consistency   
- Mars: ice consistency 

	Rationale: Buried ice is a key component for drinking water, oxygen, and fuel all critically necessary for starting a mars colony.

* Salt deliquescence potential (relative humidity and temperature envelope)  
- Earth: Hourly relative humidity and temperature from ERA5 time fraction layer (the fraction of time above each salt’s deliquescence point)  
- Mars: modeled RH–T over chloride and perchlorate deposits

	Rationale: Salts (perchlorates) pull moisture from the air and create liquid brine, which is one of the ways to obtain liquid water on the surface of mars.

* Periglacial patterned ground and gullies (signs of freezing and thawing ice on ground)  
- Earth: gully detection from high-resolution imagery  
- Mars: HiRISE and CTX data

	Rationale: Periglacial patterns on Mars’s surface indicate the freezing and thawing of ice, which may help locate the presence and locations of ground ice on mars.

# **Mars Data Links by Topic**

## **Geology**

**Rocks and minerals**

* Geology and Minerals (chemical composition)  
- Basaltic  
- Phyllosilicates/clay  
- Sulfates  
- Carbonates  
- Silica/Evaporites  
- Earth data: ASTER, EMIT, Landsat  
- Mars data: CRISM, OMEGA

| Class | Planet | Dataset | Notes | Link |
| ----- | ----- | ----- | ----- | ----- |
| Basaltic | Earth | ASTER-GED AG100 | 100 m thermal emissivity, bands 10-14. Compute the Mafic Index from it. | [DOI](https://doi.org/10.5067/Community/ASTER_GED/AG100.003) |
| Basaltic | Mars | TES Mineral Maps | Olivine and pyroxene maps. | [ODE](https://www.mars.asu.edu/data/) |
| Phyllosilicates / clay | Earth | EMIT L2B V002 | Kaolinite, illite+muscovite, montmorillonite, chlorite, vermiculite layers. | [Earthdata](https://www.earthdata.nasa.gov/data/catalog/lpcloud-emitl2bmin-002) |
| Phyllosilicates / clay | Mars | CRISM MTRDR (PDS Geosciences Node) | Use the phyllosilicate parameters D2300, BD2210 and BD1900. | [PDS](https://pds-geosciences.wustl.edu/mro/mro-m-crism-5-rdr-multispectral-v1/mrocr_3201/mrdr/) |
| Sulfates | Earth | EMIT L2B V002 | Gypsum layer (same product as the clay row). | [Earthdata](https://www.earthdata.nasa.gov/data/catalog/lpcloud-emitl2bmin-002) |
| Sulfates | Mars | CRISM MTRDR (PDS Geosciences Node) | Use the sulfate parameters SINDEX, BD2100 and BD1900. | [PDS](https://pds-geosciences.wustl.edu/missions/mro/crism.htm) |
| Carbonates | Earth | EMIT L2B V002 | Calcite and dolomite layers (same product). | [Earthdata](https://www.earthdata.nasa.gov/data/catalog/lpcloud-emitl2bmin-002) |
| Carbonates | Mars | CRISM MTRDR (PDS Geosciences Node) | Use BD2500 and BD3900. Carbonate occurs in only a few regions, mainly Nili Fossae. | [PDS](https://pds-geosciences.wustl.edu/mro/mro-m-crism-5-rdr-multispectral-v1/mrocr_3201/mrdr/) |
| Silica / evaporites | Earth | AG100 | Use QUARTZ INDEX | [AG](https://doi.org/10.5067/Community/ASTER_GED/AG100.003) |
| Silica / evaporites | Mars | CRISM | CRISM detects hydrated silica from absorption bands at 1.4, 1.9 and a broad 2.2 µm,  | [PDS](https://pds-geosciences.wustl.edu/mro/mro-m-crism-5-rdr-multispectral-v1/mrocr_3201/mrdr/) |
|  |  |  |  |  |
|  |  |  |  |  |
|  |  |  |  |  |
|  |  |  |  |  |
|  |  |  |  |  |
|  |  |  |  |  |

## **Minerals**

●       [Odyssey GRS](https://pds-geosciences.wustl.edu/ody/ody-m-grs-5-elements-v1/odgm_xxxx/data/unsmoothed/5x5/): **Data.** Orbital element-concentration maps, gamma and neutron data, and a custom-product node at the University of Arizona. Coarse, global-scale composition rather than rock-by-rock.

## **Temperature**

DATASET: [https\://atmos.nmsu.edu/data\_and\_services/atmospheres\_data/MARS/mcs.html](https://atmos.nmsu.edu/data_and_services/atmospheres_data/MARS/mcs.html)

## **Ice / Permafrost**

●       [Odyssey GRS](https://pds-geosciences.wustl.edu/ody/ody-m-grs-5-elements-v1/odgm_xxxx/data/unsmoothed/5x5/): **Data.** Neutron and hydrogen maps that show where ice lies in the top meter. Same page as the one under Chemical composition.

## **Dust processes / storms**

MCS Dust Opacity: [https\://atmos.nmsu.edu/data\_and\_services/atmospheres\_data/MARS/mcs.html](https://atmos.nmsu.edu/data_and_services/atmospheres_data/MARS/mcs.html)

## **Caves  (dry caves, shape, minerals, underground environments)**

## 

●       [Mars Global Cave Candidate Catalog (MGC3), USGS](https://astrogeology.usgs.gov/search/map/mars_global_cave_candidate_catalog_v1_cushing): **Data (replacement link).** Coordinates, feature type and confidence rating for 1,000+ candidate cave entrances. Your original link was a USGS search page, which I could not open; this is the catalog's own page, found through search.

No instrument measures cave interiors or cave mineralogy directly. Everything here is surface imagery plus indirect radar.

## **Topography**

●       [MOLA MEGDR tiles, 128 pixels per degree](https://pds-geosciences.wustl.edu/mgs/urn-nasa-pds-mgs_mola_topography_derived/meg128/): **Data (direct files).** Folder of topography, radius and areoid tiles (.img with labels), each 65 to 130 MB. This is the best direct download in your list.

## **UV:**

●       [https\://www\.pnas.org/doi/10.1073/pnas.2426611122](https://www.pnas.org/doi/10.1073/pnas.2426611122) (UV) (Better than the article below)  
●       [https\://www\.academia.edu/55427843/Ultraviolet\_radiation\_on\_the\_surface\_of\_Mars\_and\_a\_UV\_spectrometer\_on\_Mars](https://www.academia.edu/55427843/Ultraviolet_radiation_on_the_surface_of_Mars_and_a_UV_spectrometer_on_Mars) (UV spectrometer)

([https\://arxiv.org/pdf/1710.01238](https://arxiv.org/pdf/1710.01238)) Build a simple UV layer yourself from the data you already have. The main control on surface UV is the Sun’s angle (latitude, season and time of day) and how much dust is in the air. You’re already downloading MCS dust opacity for the grid, and latitude and season are known. A radiative-transfer model with those inputs gives you modeled UV per cell, and the Gale REMS data lets you check that your numbers are the right size. The paper above does this by feeding dust optical depths into a UV model and validating against REMS, so it’s a documented approach. [arxiv](https://arxiv.org/pdf/1710.01238)

Label this layer “modeled UV” in your methods so nobody reads it as a measurement.

## **Aridity: Water vapor column**

**Mars: MCD.** Link: [http\://www-mars.lmd.jussieu.fr](http://www-mars.lmd.jussieu.fr)  
It is a database of meteorological fields from general circulation model simulations, validated with observations, and freely available on request via an online form. 

It offers water vapor column (kg/m²), water vapor volume mixing ratio, surface temperature, and surface pressure. These variables are listed in its web interface.

## **Salt Deliquescence potential: Hourly RH-T (fraction of time above a salt’s threshold)**

**Mars: MCD.** Link: [http\://www-mars.lmd.jussieu.fr](http://www-mars.lmd.jussieu.fr)  
It is a database of meteorological fields from general circulation model simulations, validated with observations, and freely available on request via an online form. 

It offers water vapor column (kg/m²), water vapor volume mixing ratio, surface temperature, and surface pressure. These variables are listed in its web interface.

 **Periglacial Patterned ground and gullies (Periglacial landform area per grid cell)**

**Mars: Global Map of Gullied Hillslopes (Noblet et al.).** Link: [https\://zenodo.org/records/10581763](https://zenodo.org/records/10581763)

* It contains gullied hillslopes digitized as polygons on a CTX mosaic, in the Mars2000 coordinate system.   
* Gullies are constrained between 26°–83°S and 28°–76°N, so compare only within those latitudes

## **Earth**

## **Geology**

**Rocks and minerals**

* Geology and Minerals (chemical composition)  
- Basaltic  
- Phyllosilicates/clay  
- Sulfates  
- Carbonates  
- Silica/Evaporites  
- Earth data: ASTER, EMIT, Landsat  
- Mars data: CRISM, OMEG

**GEOLOGY IN MARS SECTION**

## **Minerals**

[https\://www\.sciencebase.gov/catalog/item/5dd2f264e4b0695797628351](https://www.sciencebase.gov/catalog/item/5dd2f264e4b0695797628351) (ONLY US)  
[https\://doi.org/10.5066/P9YEAFHI](https://doi.org/10.5066/P9YEAFHI) (ONLY AUSTRALIA)  
[https\://open.canada.ca/data/en/dataset/289c931c-a1b1-55f8-8d93-4d88e66f1810](https://open.canada.ca/data/en/dataset/289c931c-a1b1-55f8-8d93-4d88e66f1810?utm_source=chatgpt.com) (ONLY CANADA)

## **Temperature**

* [https\://www\.earthdata.nasa.gov/data/catalog/ges-disc-ml2t-005](https://www.earthdata.nasa.gov/data/catalog/ges-disc-ml2t-005)  
* Profiles are spaced about 1.5° (\~165 km) along the orbit track, roughly 15 orbits per day.  
* The recommended vertical range is 261 to 0.001 hPa, with 3 to 6 km vertical resolution.  
* ● This is the closest Earth analog to MCS: both are limb sounders that retrieve temperature versus altitude, so compare them on matching pressure levels.  
* ● Data comes as one HDF file per day (for example `MLS-Aura_L2GP-Temperature_v05-03-c01_2025d117.he5`), and a free NASA Earthdata login is required to download.  
* ● Screen profiles with the quality, status and convergence flags in the [V5 data quality document](https://mls.jpl.nasa.gov/data/v5-0_data_quality_document.pdf) before using them.  
* ● Use the standard ML2T product, not the near-real-time one, which is less accurate.  
* ● The end date differs between catalog copies, so check it on the GES DISC page before relying on recent dates.  
* ● For near-surface air temperature, MLS doesn’t reach below about 261 hPa, so use NASA POWER 2 m air temperature instead.

## **Ice / Permafrost**

[https\://climate.esa.int/de/projekte/permafrost/data](https://climate.esa.int/de/projekte/permafrost/data)  Its 1 m ground-temperature layer is more comparable to the approximate upper-meter sensitivity of Odyssey GRS.

## **Dust processes / Dust storms / Storm conditions**

[MIDAS on Zenodo](https://zenodo.org/records/4244106) provides daily dust optical depth at 550 nm, 0.1° resolution, for 2003–2017. The download is about 65 GB.

●       Caveat: optical depth is a whole-column measure, not surface wind, visibility or concentration, and the record ends in 2017\.  
●       Near-surface dust concentrations are available from the MERRA-2 reanalysis.

[https\://oro.open.ac.uk/45036/](https://oro.open.ac.uk/45036/) Montabone maps provide column dust optical depth, making them more comparable to Earth optical-depth datasets. 

## **Caves (dry caves, shape, minerals, underground environments)**

Four lava tube sources cover cave shape and cave minerals.

●     [https\://iris.polito.it/retrieve/handle/11583/2999116/903261](https://iris.polito.it/retrieve/handle/11583/2999116/903261)

Contains over 1,200 cross-sections from more than 92 lava tubes, providing a more standardized comparison. 

## **Topography**

Use 3DEP inside the US and Copernicus elsewhere.

●       [Copernicus DEM GLO-30](https://dataspace.copernicus.eu/explore-data/data-collections/copernicus-contributing-missions/collections-description/COP-DEM): global coverage at about 30 m. Needs free registration. It is a surface model, so it includes buildings and vegetation.

## **UV:**

●       [https\://www\.tropomi.eu/data-products/surface-uv](https://www.tropomi.eu/data-products/surface-uv)  
 Ultraviolet surface uv product data set info stuff.  
 

## **Aridity: Water vapor column**

**Earth: ERA5.** DOI: [https\://doi.org/10.24381/cds.adbb2d47](https://doi.org/10.24381/cds.adbb2d47)

* It is global and hourly from 1940 to present on a 0.25° grid.   
* It includes 2 m temperature, 2 m dewpoint temperature, and surface pressure. RH comes from temperature and dewpoint. ERA5 also provides total column water vapor in kg/m².

## **Salt Deliquescence potential: Hourly RH-T (fraction of time above a salt’s threshold)**

**Earth: ERA5.** DOI: [https\://doi.org/10.24381/cds.adbb2d47](https://doi.org/10.24381/cds.adbb2d47)

* It is global and hourly from 1940 to present on a 0.25° grid.   
* It includes 2 m temperature, 2 m dewpoint temperature, and surface pressure. RH comes from temperature and dewpoint. ERA5 also provides total column water vapor in kg/m².

**Periglacial Patterned ground and gullies (Periglacial landform area per grid cell)**

Earth: Permafrost Discovery Gateway ice-wedge polygons. Link: [https\://zenodo.org/records/10522820](https://zenodo.org/records/10522820)

*
���� 513581d76a32f542c7cf7d21ba466094
��
data/earth_coastlines.json�{"source":"Natural Earth 1:110m land (via world-atlas@2), public domain","rings":[[-59.6,-80,-59.9,-80.5,-60.2,-81,-62.3,-80.9,-64.5,-80.9,-65.7,-80.6,-65.7,-80.5,-66.3,-80.3,-64,-80.3,-61.9,-80.4,-61.1,-80,-60.6,-79.6,-59.6,-80],[-159.2,-79.5,-161.1,-79.6,-162.4,-79.3,-163,-78.9,-163.1,-78.9,-163.7,-78.6,-163.1,-78.2,-161.2,-78.4,-160.2,-78.7,-159.5,-79,-159.2,-79.5],[-45.2,-78,-43.9,-78.5,-43.5,-79.1,-43.4,-79.5,-43.3,-80,-44.9,-80.3,-46.5,-80.6,-48.4,-80.8,-50.5,-81,-52.9,-81,-54.2,-80.6,-54,-80.2,-51.9,-79.9,-51,-79.6,-50.4,-79.2,-49.9,-78.8,-49.3,-78.5,-48.7,-78,-48.2,-78,-46.7,-77.8,-45.2,-78],[-121.2,-73.5,-119.9,-73.7,-118.7,-73.5,-119.3,-73.8,-120.2,-74.1,-121.6,-74,-122.6,-73.7,-122.4,-73.3,-121.2,-73.5],[-125.6,-73.5,-124,-73.9,-124.6,-73.8,-125.9,-73.7,-127.3,-73.5,-126.6,-73.2,-125.6,-73.5],[-99,-71.9,-97.9,-72.1,-96.8,-72,-96.2,-72.5,-97,-72.4,-98.2,-72.5,-99.4,-72.4,-100.8,-72.5,-101.8,-72.3,-102.3,-71.9,-101.7,-71.7,-100.4,-71.9,-99,-71.9],[-68.5,-71,-68.3,-71.4,-68.5,-71.8,-68.8,-72.2,-70,-72.3,-71.1,-72.5,-72.4,-72.5,-71.9,-72.1,-73.1,-72.2,-74.2,-72.4,-75,-72.1,-75,-71.7,-73.9,-71.3,-73.2,-71.2,-72.1,-71.2,-71.8,-70.7,-71.7,-70.3,-71.7,-69.5,-71.2,-69,-70.3,-68.9,-69.7,-69.3,-69.5,-69.6,-69.1,-70.1,-68.7,-70.5,-68.5,-71],[-180,-84.7,-179.9,-84.7,-179.1,-84.1,-177.3,-84.5,-177.1,-84.4,-176.9,-84.3,-176.5,-84.2,-176.2,-84.1,-176.1,-84.1,-175.9,-84.1,-175.8,-84.1,-174.4,-84.5,-173.1,-84.1,-172.9,-84.1,-170,-83.9,-169,-84.1,-168.5,-84.2,-167,-84.6,-164.2,-84.8,-161.9,-85.1,-158.1,-85.4,-155.2,-85.1,-150.9,-85.3,-148.5,-85.6,-145.9,-85.3,-143.1,-85,-142.9,-84.6,-146.8,-84.5,-150.1,-84.3,-150.9,-83.9,-153.6,-83.7,-153.4,-83.2,-153,-82.8,-152.7,-82.5,-152.9,-82,-154.5,-81.8,-155.3,-81.4,-156.8,-81.1,-154.4,-81.2,-152.1,-81,-150.6,-81.3,-148.9,-81,-147.2,-80.7,-146.4,-80.3,-146.8,-79.9,-148.1,-79.7,-149.5,-79.4,-151.6,-79.3,-153.4,-79.2,-155.3,-79.1,-156,-78.7,-157.3,-78.4,-158.1,-78,-158.4,-76.9,-157.9,-77,-157,-77.3,-155.3,-77.2,-153.7,-77.1,-152.9,-77.5,-151.3,-77.4,-150,-77.2,-148.7,-76.9,-147.6,-76.6,-146.1,-76.5,-146.1,-76.1,-146.5,-75.7,-146.2,-75.4,-144.9,-75.2,-144.3,-75.5,-142.8,-75.3,-141.6,-75.1,-140.2,-75.1,-138.9,-75,-137.5,-74.7,-136.4,-74.5,-135.2,-74.3,-134.4,-74.4,-133.7,-74.4,-132.3,-74.3,-130.9,-74.5,-129.6,-74.5,-128.2,-74.3,-126.9,-74.4,-125.4,-74.5,-124,-74.5,-122.6,-74.5,-121.1,-74.5,-119.7,-74.5,-118.7,-74.2,-117.5,-74,-116.2,-74.2,-115,-74.1,-113.9,-73.7,-113.3,-74,-112.9,-74.4,-112.3,-74.7,-111.3,-74.4,-110.1,-74.8,-108.7,-74.9,-107.6,-75.2,-106.1,-75.1,-104.9,-74.9,-103.4,-75,-102,-75.1,-100.6,-75.3,-100.1,-74.9,-100.8,-74.5,-101.3,-74.2,-102.5,-74.1,-103.1,-73.7,-103.3,-73.4,-103.7,-72.6,-102.9,-72.8,-101.6,-72.8,-100.3,-72.8,-99.1,-72.9,-98.1,-73.2,-97.7,-73.6,-96.3,-73.6,-95,-73.5,-93.7,-73.3,-92.4,-73.2,-91.4,-73.4,-90.1,-73.3,-89.2,-72.6,-88.4,-73,-87.3,-73.2,-86,-73.1,-85.2,-73.5,-83.9,-73.5,-82.7,-73.6,-81.5,-73.9,-80.7,-73.5,-80.3,-73.1,-79.3,-73.5,-77.9,-73.4,-76.9,-73.6,-76.2,-74,-74.9,-73.9,-73.9,-73.7,-72.8,-73.4,-71.6,-73.3,-70.2,-73.1,-68.9,-73,-68,-72.8,-67.4,-72.5,-67.1,-72,-67.3,-71.6,-67.6,-71.2,-67.9,-70.9,-68.2,-70.5,-68.5,-70.1,-68.5,-69.7,-68.4,-69.3,-68,-69,-67.6,-68.5,-67.4,-68.2,-67.6,-67.7,-67.7,-67.3,-67.3,-66.9,-66.7,-66.6,-66.1,-66.2,-65.4,-65.9,-64.6,-65.6,-64.2,-65.2,-63.6,-64.9,-63,-64.6,-62,-64.6,-61.4,-64.3,-60.7,-64.1,-59.9,-64,-59.2,-63.7,-58.6,-63.4,-57.8,-63.3,-57.2,-63.5,-57.6,-63.9,-58.6,-64.2,-59,-64.4,-59.8,-64.2,-60.6,-64.3,-61.3,-64.5,-62,-64.8,-62.5,-65.1,-62.6,-65.5,-62.6,-65.9,-62.1,-66.2,-62.8,-66.4,-63.7,-66.5,-64.3,-66.8,-64.9,-67.1,-65.5,-67.6,-65.7,-68,-65.3,-68.4,-64.8,-68.7,-64,-68.9,-63.2,-69.2,-62.8,-69.6,-62.6,-70,-62.3,-70.4,-61.8,-70.7,-61.5,-71.1,-61.4,-72,-61.1,-72.4,-61,-72.8,-60.7,-73.2,-60.8,-73.7,-61.4,-74.1,-62,-74.4,-63.3,-74.6,-63.7,-74.9,-64.4,-75.3,-65.9,-75.6,-67.2,-75.8,-68.4,-76,-69.8,-76.2,-70.6,-76.6,-72.2,-76.7,-74,-76.6,-75.6,-76.7,-77.2,-76.7,-76.9,-77.1,-75.4,-77.3,-74.3,-77.6,-73.7,-77.9,-74.8,-78.2,-76.5,-78.1,-77.9,-78.4,-78,-78.8,-78,-79.2,-76.8,-79.5,-76.6,-79.9,-75.4,-80.3,-73.2,-80.4,-71.4,-80.7,-70,-81,-68.2,-81.3,-65.7,-81.5,-63.3,-81.7,-61.6,-82,-59.7,-82.4,-58.7,-82.8,-58.2,-83.2,-57,-82.9,-55.4,-82.6,-53.6,-82.3,-51.5,-82,-49.8,-81.7,-47.3,-81.7,-44.8,-81.8,-42.8,-82.1,-42.2,-81.7,-40.8,-81.4,-38.2,-81.3,-36.3,-81.1,-34.4,-80.9,-32.3,-80.8,-30.1,-80.6,-28.6,-80.3,-29.3,-80,-29.7,-79.6,-29.7,-79.3,-31.6,-79.3,-33.7,-79.5,-35.6,-79.5,-35.9,-79.1,-35.8,-78.3,-35.3,-78.1,-33.9,-77.9,-32.2,-77.7,-31,-77.4,-29.8,-77.1,-28.9,-76.7,-27.5,-76.5,-26.2,-76.4,-25.5,-76.3,-23.9,-76.2,-22.5,-76.1,-21.2,-75.9,-20,-75.7,-18.9,-75.4,-17.5,-75.1,-16.6,-74.8,-15.7,-74.5,-15.4,-74.1,-16.5,-73.9,-16.1,-73.5,-15.4,-73.1,-14.4,-73,-13.3,-72.7,-12.3,-72.4,-11.5,-72,-11,-71.5,-10.3,-71.3,-9.1,-71.3,-8.6,-71.7,-7.4,-71.7,-7.4,-71.3,-6.9,-70.9,-5.8,-71,-5.5,-71.4,-4.3,-71.5,-3,-71.3,-1.8,-71.2,-0.7,-71.2,-0.2,-71.6,0.9,-71.3,1.9,-71.1,3,-71,4.1,-70.9,5.2,-70.6,6.3,-70.5,7.1,-70.2,7.7,-69.9,8.5,-70.1,9.5,-70,10.3,-70.5,10.8,-70.8,12,-70.6,12.4,-70.2,13.4,-70,14.7,-70,15.1,-70.4,15.9,-70,17,-69.9,18.2,-69.9,19.3,-69.9,20.4,-70,21.5,-70.1,21.9,-70.4,22.6,-70.7,23.7,-70.5,24.8,-70.5,26,-70.5,27.1,-70.5,28.1,-70.3,29.2,-70.2,30,-69.9,31,-69.8,32,-69.7,32.8,-69.4,33.3,-68.8,33.9,-68.5,34.9,-68.7,35.3,-69,36.2,-69.2,37.2,-69.2,37.9,-69.5,38.6,-69.8,39.7,-69.5,40,-69.1,40.9,-68.9,42,-68.6,42.9,-68.5,44.1,-68.3,44.9,-68.1,45.7,-67.8,46.5,-67.6,47.4,-67.7,48.3,-67.4,49,-67.1,49.9,-67.1,50.8,-66.9,50.9,-66.5,51.8,-66.2,52.6,-66.1,53.6,-65.9,54.5,-65.8,55.4,-65.9,56.4,-66,57.2,-66.2,57.3,-66.7,58.1,-67,58.7,-67.3,59.9,-67.4,60.6,-67.7,61.4,-68,62.4,-68,63.2,-67.8,64.1,-67.4,65,-67.6,66,-67.7,66.9,-67.9,67.9,-67.9,68.9,-67.9,69.7,-69,69.7,-69.2,69.6,-69.7,68.6,-69.9,67.8,-70.3,67.9,-70.7,69.1,-70.7,68.9,-71.1,68.4,-71.4,67.9,-71.9,68.7,-72.2,69.9,-72.3,71,-72.1,71.6,-71.7,71.9,-71.3,72.5,-71,73.1,-70.7,73.3,-70.4,73.9,-69.9,74.5,-69.8,75.6,-69.7,76.6,-69.6,77.6,-69.5,78.1,-69.1,78.4,-68.7,79.1,-68.3,80.1,-68.1,80.9,-67.9,81.5,-67.5,82.1,-67.4,82.8,-67.2,83.8,-67.3,84.7,-67.2,85.7,-67.1,86.8,-67.1,87.5,-66.9,88,-66.2,88.4,-66.5,88.8,-67,89.7,-67.1,90.6,-67.2,91.6,-67.1,92.6,-67.2,93.5,-67.2,94.2,-67.1,95,-67.2,95.8,-67.4,96.7,-67.2,97.8,-67.2,98.7,-67.1,99.7,-67.2,100.4,-66.9,100.9,-66.6,101.6,-66.3,102.8,-65.6,103.5,-65.7,104.2,-66,104.9,-66.3,106.2,-66.9,107.2,-67,108.1,-67,109.2,-66.8,110.2,-66.7,111.1,-66.4,111.7,-66.1,112.9,-66.1,113.6,-65.9,114.4,-66.1,114.9,-66.4,115.6,-66.7,116.7,-66.7,117.4,-66.9,118.6,-67.2,119.8,-67.3,120.9,-67.2,121.7,-66.9,122.3,-66.6,123.2,-66.5,124.1,-66.6,125.2,-66.7,126.1,-66.6,127,-66.6,127.9,-66.7,128.8,-66.8,129.7,-66.6,130.8,-66.4,131.8,-66.4,132.9,-66.4,133.9,-66.3,134.8,-66.2,135,-65.7,135.1,-65.3,135.7,-65.6,135.9,-66,136.2,-66.4,136.6,-66.8,137.5,-67,138.6,-66.9,139.9,-66.9,140.8,-66.8,142.1,-66.8,143.1,-66.8,144.4,-66.8,145.5,-66.9,146.2,-67.2,146,-67.6,146.6,-67.9,147.7,-68.1,148.8,-68.4,150.1,-68.6,151.5,-68.7,152.5,-68.9,153.6,-68.9,154.3,-68.6,155.2,-68.8,155.9,-69.1,156.8,-69.4,158,-69.5,159.2,-69.6,159.7,-70,160.8,-70.2,161.6,-70.6,162.7,-70.7,163.8,-70.7,164.9,-70.8,166.1,-70.8,167.3,-70.8,168.4,-71,169.5,-71.2,170.5,-71.4,171.2,-71.7,171.1,-72.1,170.6,-72.4,170.1,-72.9,169.8,-73.2,169.3,-73.7,168,-73.8,167.4,-74.2,166.1,-74.4,165.6,-74.8,165,-75.1,164.2,-75.5,163.8,-75.9,163.6,-76.2,163.5,-76.7,163.5,-77.1,164.1,-77.5,164.3,-77.8,164.7,-78.2,166.6,-78.3,167,-78.8,165.2,-78.9,163.7,-79.1,161.8,-79.2,160.9,-79.7,160.7,-80.2,160.3,-80.6,159.8,-80.9,161.1,-81.3,161.6,-81.7,162.5,-82.1,163.7,-82.4,165.1,-82.7,166.6,-83,168.9,-83.3,169.4,-83.8,172.3,-84,172.5,-84.1,173.2,-84.4,176,-84.2,178.3,-84.5,-180,-84.7],[-67.8,-53.8,-66.5,-54.5,-65.1,-54.7,-65.5,-55.2,-66.5,-55.2,-67,-54.9,-67.3,-55.3,-68.1,-55.6,-69.2,-55.5,-70,-55.2,-71,-55.1,-72.3,-54.5,-73.3,-54,-74.7,-52.8,-73.8,-53,-72.4,-53.7,-71.1,-54.1,-70.6,-53.6,-70.3,-52.9,-69.3,-52.5,-68.6,-52.6,-68.3,-53.1,-67.8,-53.8],[-58.5,-51.1,-57.7,-51.5,-58,-51.9,-59.4,-52.2,-59.8,-51.8,-60.7,-52.3,-61.2,-51.8,-60,-51.3,-59.2,-51.5,-58.5,-51.1],[70.3,-49.7,68.7,-49.8,68.7,-49.2,68.9,-48.8,68.9,-48.6,69.6,-48.9,70.5,-49.1,70.6,-49.3,70.3,-49.7],[145.4,-40.8,146.4,-41.1,146.9,-41,147.7,-40.8,148.3,-40.9,148.4,-42.1,148,-42.4,147.9,-43.2,147.6,-42.9,146.9,-43.6,146.7,-43.6,146,-43.5,145.4,-42.7,145.3,-42,144.7,-41.2,144.7,-40.7,145.4,-40.8],[173,-40.9,173.2,-41.3,174,-40.9,174.2,-41.3,174.2,-41.8,173.9,-42.2,173.2,-43,172.7,-43.4,173.1,-43.9,172.3,-43.9,171.5,-44.2,171.2,-44.9,170.6,-45.9,169.8,-46.4,169.3,-46.6,168.4,-46.6,167.8,-46.3,166.7,-46.2,166.5,-45.9,167,-45.1,168.3,-44.1,168.9,-43.9,169.7,-43.6,170.5,-43,171.1,-42.5,171.6,-41.8,172,-41.5,172.1,-41,172.8,-40.5,173,-40.9],[174.6,-36.2,175.3,-37.2,175.4,-36.5,175.8,-36.8,176,-37.6,176.8,-37.9,177.4,-38,178,-37.6,178.5,-37.7,178.3,-38.6,178,-39.2,177.2,-39.1,176.9,-39.4,177,-39.9,176.9,-40.1,176.5,-40.6,176,-41.3,175.2,-41.7,175.1,-41.4,174.7,-41.3,175.2,-40.5,174.9,-39.9,173.8,-39.5,173.9,-39.1,174.6,-38.8,174.7,-38,174.7,-37.4,174.3,-36.7,174.3,-36.5,173.8,-36.1,173.1,-35.2,172.6,-34.5,173,-34.5,173.6,-35,174.3,-35.3,174.6,-36.2],[167.1,-22.2,166.7,-22.4,166.2,-22.1,165.5,-21.7,164.8,-21.1,164.2,-20.4,164,-20.1,164.5,-20.1,165,-20.5,165.5,-20.8,165.8,-21.1,166.6,-21.7,167.1,-22.2],[178.4,-17.3,178.7,-17.6,178.6,-18.2,177.9,-18.3,177.4,-18.2,177.3,-17.7,177.7,-17.4,178.1,-17.5,178.4,-17.3],[-180,-16.6,179.4,-16.8,178.7,-17,178.6,-16.6,179.1,-16.4,179.4,-16.4,-180,-16.1,-179.8,-16,-179.9,-16.5,-180,-16.6],[167.8,-16.5,167.5,-16.6,167.2,-16.2,167.2,-15.9,167.8,-16.5],[167.1,-14.9,167.3,-15.7,167,-15.6,166.8,-15.7,166.7,-15.4,166.6,-14.6,167.1,-14.9],[50.1,-13.6,50.2,-14.8,50.5,-15.2,50.4,-15.7,50.2,-16,49.9,-15.4,49.7,-15.7,49.9,-16.5,49.8,-16.9,49.5,-17.1,49.4,-18,49,-19.1,48.5,-20.5,47.9,-22.4,47.5,-23.8,47.1,-24.9,46.3,-25.2,45.4,-25.6,44.8,-25.3,44,-25,43.8,-24.5,43.7,-23.6,43.3,-22.8,43.3,-22.1,43.4,-21.3,43.9,-21.2,43.9,-20.8,44.4,-20.1,44.5,-19.4,44.2,-19,44,-18.3,44,-17.4,44.3,-16.9,44.4,-16.2,44.9,-16.2,45.5,-16,45.9,-15.8,46.3,-15.8,46.9,-15.2,47.7,-14.6,48,-14.1,47.9,-13.7,48.3,-13.8,48.8,-13.1,48.9,-12.5,49.2,-12,49.5,-12.5,49.8,-12.9,50.1,-13.6],[143.6,-13.8,143.9,-14.5,144.6,-14.2,144.9,-14.6,145.4,-15,145.3,-15.4,145.5,-16.3,145.6,-16.8,145.9,-16.9,146.2,-17.8,146.1,-18.3,146.4,-19,147.5,-19.5,148.2,-20,148.8,-20.4,148.7,-20.6,149.3,-21.3,149.7,-22.3,150.1,-22.1,150.5,-22.6,150.7,-22.4,150.9,-23.5,151.6,-24.1,152.1,-24.5,152.9,-25.3,153.1,-26.1,153.2,-26.6,153.1,-27.3,153.6,-28.1,153.5,-29,153.3,-29.5,153.1,-30.4,153.1,-30.9,152.9,-31.6,152.4,-32.6,151.7,-33,151.3,-33.8,151,-34.3,150.7,-35.2,150.3,-35.7,150.1,-36.4,149.9,-37.1,150,-37.4,149.4,-37.8,148.3,-37.8,147.4,-38.2,146.9,-38.6,146.3,-39,145.5,-38.6,144.9,-38.4,145,-37.9,144.5,-38.1,143.6,-38.8,142.7,-38.5,142.2,-38.4,141.6,-38.3,140.6,-38,140,-37.4,139.8,-36.6,139.6,-36.1,139.1,-35.7,138.1,-35.6,138.4,-35.1,138.2,-34.4,137.7,-35.1,136.8,-35.3,137.4,-34.7,137.5,-34.1,137.9,-33.6,137.8,-32.9,137,-33.8,136.4,-34.1,136,-34.9,135.2,-34.5,135.2,-33.9,134.6,-33.2,134.1,-32.8,134.3,-32.6,133,-32,132.3,-32,131.3,-31.5,129.5,-31.6,128.2,-31.9,127.1,-32.3,126.1,-32.2,125.1,-32.7,124.2,-33,124,-33.5,123.7,-33.9,122.8,-33.9,122.2,-34,121.3,-33.8,120.6,-33.9,119.9,-34,119.3,-34.5,119,-34.5,118.5,-34.7,118,-35.1,117.3,-35,116.6,-35,115.6,-34.4,115,-34.2,115,-33.6,115.5,-33.5,115.7,-33.3,115.7,-32.9,115.8,-32.2,115.7,-31.6,115.2,-30.6,115,-30,115,-29.5,114.6,-28.8,114.6,-28.5,114.2,-28.1,114,-27.3,113.5,-26.5,113.3,-26.1,113.8,-26.5,113.4,-25.6,113.9,-25.9,114.2,-26.3,114.2,-25.8,113.7,-25,113.6,-24.7,113.4,-24.4,113.5,-23.8,113.7,-23.6,113.8,-23.1,113.7,-22.5,114.1,-21.8,114.2,-22.5,114.6,-21.8,115.5,-21.5,115.9,-21.1,116.7,-20.7,117.2,-20.6,117.4,-20.7,118.2,-20.4,118.8,-20.3,119,-20,119.3,-20,119.8,-20,120.9,-19.7,121.4,-19.2,121.7,-18.7,122.2,-18.2,122.3,-17.8,122.3,-17.3,123,-16.4,123.4,-17.3,123.9,-17.1,123.5,-16.6,123.8,-16.1,124.3,-16.3,124.4,-15.6,124.9,-15.1,125.2,-14.7,125.7,-14.5,125.7,-14.2,126.1,-14.3,126.1,-14.1,126.6,-14,127.1,-13.8,127.8,-14.3,128.4,-14.9,129,-14.9,129.6,-15,129.4,-14.4,129.9,-13.6,130.3,-13.4,130.2,-13.1,130.6,-12.5,131.2,-12.2,131.7,-12.3,132.6,-12.1,132.6,-11.6,131.8,-11.3,132.4,-11.1,133,-11.4,133.6,-11.8,134.4,-12,134.7,-11.9,135.3,-12.2,135.9,-12,136.3,-12,136.5,-11.9,137,-12.4,136.7,-12.9,136.3,-13.3,136,-13.3,136.1,-13.7,135.8,-14.2,135.4,-14.7,135.5,-15,136.3,-15.6,137.1,-15.9,137.6,-16.2,138.3,-16.8,138.6,-16.8,139.1,-17.1,139.3,-17.4,140.2,-17.7,140.9,-17.4,141.1,-16.8,141.3,-16.4,141.4,-15.8,141.7,-15,141.6,-14.6,141.6,-14.3,141.5,-13.7,141.7,-12.9,141.8,-12.7,141.7,-12.4,141.9,-11.9,142.1,-11.3,142.1,-11,142.5,-10.7,142.8,-11.2,142.9,-11.8,143.1,-11.9,143.2,-12.3,143.5,-12.8,143.6,-13.4,143.6,-13.8],[162.1,-10.5,162.4,-10.8,161.7,-10.8,161.3,-10.2,161.9,-10.4,162.1,-10.5],[120.7,-10.2,120.3,-10.3,119,-9.6,119.9,-9.4,120.4,-9.7,120.8,-10,120.7,-10.2],[160.9,-9.9,160.5,-9.9,159.9,-9.8,159.6,-9.6,159.7,-9.2,160.4,-9.4,160.7,-9.6,160.9,-9.9],[161.7,-9.6,161.5,-9.8,160.8,-8.9,160.6,-8.3,160.9,-8.3,161.3,-9.1,161.7,-9.6],[124.4,-10.1,123.6,-10.4,123.5,-10.2,123.6,-9.9,124,-9.3,125,-8.9,125.1,-8.7,125.9,-8.4,126.6,-8.4,127,-8.3,127.3,-8.4,127,-8.7,125.9,-9.1,125.1,-9.4,124.4,-10.1],[117.9,-8.1,118.3,-8.4,118.9,-8.3,119.1,-8.7,118,-8.9,117.3,-9,116.7,-9,117.1,-8.5,117.6,-8.4,117.9,-8.1],[122.9,-8.1,122.8,-8.7,121.3,-8.9,119.9,-8.8,119.9,-8.4,120.7,-8.2,121.3,-8.5,122,-8.5,122.9,-8.1],[159.9,-8.3,159.9,-8.5,159.1,-8.1,158.6,-7.8,158.2,-7.4,158.4,-7.3,158.8,-7.6,159.6,-8,159.9,-8.3],[157.5,-7.3,157.3,-7.4,156.9,-7.2,156.5,-6.8,156.5,-6.6,157.1,-7,157.5,-7.3],[108.6,-6.8,110.5,-6.9,110.8,-6.5,112.6,-6.9,113,-7.6,114.5,-7.8,115.7,-8.4,114.6,-8.8,113.5,-8.3,112.6,-8.4,111.5,-8.3,110.6,-8.1,109.4,-7.7,108.7,-7.6,108.3,-7.8,106.5,-7.4,106.3,-6.9,105.4,-6.9,106.1,-5.9,107.3,-6,108.1,-6.3,108.5,-6.4,108.6,-6.8],[134.7,-6.2,134.2,-6.9,134.1,-6.1,134.3,-5.8,134.5,-5.4,134.7,-5.7,134.7,-6.2],[155.9,-6.8,155.6,-6.9,155.2,-6.5,154.7,-5.9,154.5,-5.1,154.7,-5,154.8,-5.3,155.1,-5.6,155.5,-6.2,156,-6.5,155.9,-6.8],[152,-5.5,151.5,-5.6,151.3,-5.8,150.8,-6.1,150.2,-6.3,149.7,-6.3,148.9,-6,148.3,-5.7,148.4,-5.4,149.3,-5.6,149.8,-5.5,150,-5,150.1,-5,150.2,-5.5,150.8,-5.5,151.1,-5.1,151.6,-4.8,151.5,-4.2,152.1,-4.1,152.3,-4.3,152.3,-4.9,152,-5.5],[127.2,-3.5,126.9,-3.8,126.2,-3.6,126,-3.2,127,-3.1,127.2,-3.5],[130.5,-3.1,130.8,-3.9,130,-3.4,129.2,-3.4,128.6,-3.4,127.9,-3.4,128.1,-2.8,129.4,-2.8,130.5,-3.1],[153.1,-4.5,152.8,-4.8,152.6,-4.2,152.4,-3.8,152,-3.5,151.4,-3,150.7,-2.7,150.9,-2.5,151.5,-2.8,151.8,-3,152.2,-3.2,152.6,-3.7,153,-4,153.1,-4.5],[134.1,-1.2,134.4,-2.8,135.5,-3.4,136.3,-2.3,137.4,-1.7,138.3,-1.7,139.2,-2.1,139.9,-2.4,141,-2.6,142.7,-3.3,144.6,-3.9,145.3,-4.4,145.8,-4.9,146,-5.5,147.6,-6.1,147.9,-6.6,147,-6.7,147.2,-7.4,148.1,-8,148.7,-9.1,149.3,-9.1,149.3,-9.5,150,-9.7,149.7,-9.9,150.8,-10.3,150.7,-10.6,150,-10.7,149.8,-10.4,148.9,-10.3,147.9,-10.1,147.1,-9.5,146.6,-8.9,146,-8.1,144.7,-7.6,143.9,-7.9,143.3,-8.2,143.4,-9,142.6,-9.3,142.1,-9.2,141,-9.1,140.1,-8.3,139.1,-8.1,138.9,-8.4,137.6,-8.4,138,-7.6,138.7,-7.3,138.4,-6.2,137.9,-5.4,136,-4.5,135.2,-4.5,133.7,-3.5,133.4,-4,133,-4.1,132.8,-3.7,132.8,-3.3,132,-2.8,133.1,-2.5,133.8,-2.5,133.7,-2.2,132.2,-2.2,131.8,-1.6,130.9,-1.4,130.5,-0.9,131.9,-0.7,132.4,-0.4,134,-0.8,134.1,-1.2],[125.2,1.4,124.4,0.4,123.7,0.2,122.7,0.4,121.1,0.4,120.2,0.2,120,-0.5,120.9,-1.4,121.5,-1,123.3,-0.6,123.3,-1.1,122.8,-0.9,122.4,-1.5,121.5,-1.9,122.5,-3.2,122.3,-3.5,123.2,-4.7,123.2,-5.3,122.6,-5.6,122.2,-5.3,122.7,-4.5,121.7,-4.9,121.5,-4.6,121.6,-4.2,120.9,-3.6,121,-2.6,120.3,-2.9,120.4,-4.1,120.4,-5.5,119.8,-5.7,119.4,-5.4,119.7,-4.5,119.5,-3.5,119.1,-3.5,118.8,-2.8,119.2,-2.1,119.3,-1.4,119.8,0.2,120,0.6,120.9,1.3,121.7,1,122.9,0.9,124.1,0.9,125.1,1.6,125.2,1.4],[128.7,1.1,128.6,0.3,128.1,0.4,128,-0.3,128.4,-0.8,128.1,-0.9,127.7,-0.3,127.4,1,127.6,1.8,127.9,2.2,128,1.6,128.6,1.5,128.7,1.1],[105.8,-5.9,104.7,-5.9,103.9,-5,102.6,-4.2,102.2,-3.6,101.4,-2.8,100.9,-2.1,100.1,-0.7,99.3,0.2,99,1,98.6,1.8,97.7,2.5,97.2,3.3,96.4,3.9,95.4,5,95.3,5.5,95.9,5.4,97.5,5.2,98.4,4.3,99.1,3.6,99.7,3.2,100.6,2.1,101.7,2.1,102.5,1.4,103.1,0.6,103.8,0.1,103.4,-0.7,104,-1.1,104.4,-1.1,104.5,-1.8,104.9,-2.3,105.6,-2.4,106.1,-3.1,105.9,-4.3,105.8,-5.9],[117.9,1.8,119,0.9,117.8,0.8,117.5,0.1,117.5,-0.8,116.6,-1.5,116.5,-2.5,116.1,-4,116,-3.7,114.9,-4.1,114.5,-3.5,113.8,-3.4,113.3,-3.1,112.1,-3.5,111.7,-3,111,-3,110.2,-2.9,110.1,-1.6,109.6,-1.3,109.1,-0.5,109,0.4,109.1,1.3,109.7,2,110.4,1.7,111.2,1.9,111.4,2.7,111.8,2.9,113,3.1,113.7,3.9,114.2,4.5,114.6,4.9,115.5,5.4,116.2,6.1,116.7,6.9,117.1,6.9,117.6,6.4,117.7,6,118.3,5.7,119.2,5.4,119.1,5,118.4,5,118.6,4.5,117.9,4.1,117.3,3.2,118,2.3,117.9,1.8],[126.4,8.4,126.5,7.8,126.5,7.2,126.2,6.3,125.8,7.3,125.4,6.8,125.7,6,125.4,5.6,124.2,6.2,123.9,6.9,124.2,7.4,123.6,7.8,123.3,7.4,122.8,7.5,122.1,6.9,121.9,7.2,122.3,8,122.9,8.3,123.5,8.7,123.8,8.2,124.6,8.5,124.8,9,125.5,9,125.4,9.8,126.2,9.3,126.3,8.8,126.4,8.4],[81.2,6.2,80.3,6,79.9,6.8,79.7,8.2,80.1,9.8,80.8,9.3,81.3,8.6,81.8,7.5,81.6,6.5,81.2,6.2],[-60.9,10.1,-61.8,10,-62,10.1,-61.7,10.4,-61.7,10.8,-61.1,10.9,-60.9,10.9,-60.9,10.1],[124,10.3,123.6,9.9,123.3,9.3,123,9,122.4,9.7,122.6,10,122.8,10.3,122.9,10.9,123.5,10.9,123.3,10.3,124.1,11.2,124,10.3],[118.5,9.3,117.2,8.4,117.7,9.1,118.4,9.7,119,10.4,119.5,11.4,119.7,10.6,119,10,118.5,9.3],[121.9,11.9,122.5,11.6,123.1,11.6,123.1,11.2,122.6,10.7,122,10.4,122,10.9,122,11.4,121.9,11.9],[125.5,12.2,125.8,11,125,11.3,125,11,125.3,10.4,124.8,10.1,124.8,10.8,124.5,10.9,124.3,11.5,124.9,11.4,124.9,11.8,124.3,12.6,125.2,12.5,125.5,12.2],[121.5,13.1,121.3,12.2,120.8,12.7,120.3,13.5,121.2,13.4,121.5,13.1],[121.3,18.5,121.9,18.2,122.2,18.5,122.3,18.2,122.2,17.8,122.5,17.1,122.3,16.3,121.7,15.9,121.5,15.1,121.7,14.3,122.3,14.2,122.7,14.3,124,13.8,123.9,13.2,124.2,13,124.1,12.5,123.3,13,122.9,13.6,122.7,13.2,122,13.8,121.1,13.6,120.6,13.9,120.7,14.3,121,14.5,120.7,14.8,120.6,14.4,120.1,15,119.9,15.4,119.9,16.4,120.3,16,120.4,17.6,120.7,18.5,121.3,18.5],[-65.6,18.2,-65.8,18,-66.6,18,-67.2,17.9,-67.2,18.4,-67.1,18.5,-66.3,18.5,-65.8,18.4,-65.6,18.2],[-76.9,17.9,-77.2,17.7,-77.8,17.9,-78.3,18.2,-78.2,18.5,-77.8,18.5,-77.6,18.5,-76.9,18.4,-76.4,18.2,-76.2,17.9,-76.9,17.9],[-72.6,19.9,-71.7,19.7,-71.6,19.9,-70.8,19.9,-70.2,19.6,-70,19.6,-69.8,19.3,-69.2,19.3,-69.3,19,-68.8,19,-68.3,18.6,-68.7,18.2,-69.2,18.4,-69.6,18.4,-70,18.4,-70.1,18.2,-70.5,18.2,-70.7,18.4,-71,18.3,-71.4,17.6,-71.7,17.8,-71.7,18,-72.4,18.2,-72.8,18.1,-73.5,18.2,-73.9,18,-74.5,18.3,-74.4,18.7,-73.4,18.5,-72.7,18.4,-72.3,18.7,-72.8,19.1,-72.8,19.5,-73.4,19.6,-73.2,19.9,-72.6,19.9],[110.3,18.7,109.5,18.2,108.7,18.5,108.6,19.4,109.1,19.8,110.2,20.1,110.8,20.1,111,19.7,110.6,19.3,110.3,18.7],[-155.5,19.1,-155.7,18.9,-155.9,19.1,-155.9,19.3,-156.1,19.7,-156,19.8,-155.9,20,-155.9,20.2,-155.9,20.3,-155.8,20.2,-155.4,20.1,-155.2,20,-155.1,19.9,-154.8,19.5,-155.2,19.2,-155.5,19.1],[-156.1,20.6,-156.4,20.6,-156.6,20.8,-156.7,20.9,-156.6,21,-156.3,20.9,-156,20.8,-156.1,20.6],[-156.8,21.2,-156.8,21.1,-157.3,21.1,-157.3,21.2,-156.8,21.2],[-157.7,21.3,-157.8,21.3,-158.1,21.3,-158.3,21.5,-158.3,21.6,-158,21.7,-157.9,21.7,-157.7,21.3],[-159.3,22,-159.5,21.9,-159.8,22.1,-159.7,22.1,-159.6,22.2,-159.4,22.2,-159.3,22],[-79.7,22.8,-79.3,22.4,-78.3,22.5,-78,22.3,-77.1,21.7,-76.5,21.2,-76.2,21.2,-75.6,21,-75.7,20.7,-74.9,20.7,-74.2,20.3,-74.3,20.1,-75,19.9,-75.6,19.9,-76.3,20,-77.8,19.9,-77.1,20.4,-77.5,20.7,-78.1,20.7,-78.5,21,-78.7,21.6,-79.3,21.6,-80.2,21.8,-80.5,22,-81.8,22.2,-82.2,22.4,-81.8,22.6,-82.8,22.7,-83.5,22.2,-83.9,22.2,-84.1,21.9,-84.5,21.8,-85,21.9,-84.4,22.2,-84.2,22.6,-83.8,22.8,-83.3,23,-82.5,23.1,-82.3,23.2,-81.4,23.1,-80.6,23.1,-79.7,22.8],[-77.5,23.8,-77.8,23.7,-78,24.3,-78.4,24.6,-78.2,25.2,-77.9,25.2,-77.5,24.3,-77.5,23.8],[121.2,22.8,120.7,22,120.2,22.8,120.1,23.6,120.7,24.5,121.5,25.3,122,25,121.8,24.4,121.2,22.8],[-77.8,26.6,-78.9,26.4,-79,26.8,-78.5,26.9,-77.8,26.8,-77.8,26.6],[-77,26.6,-77.2,25.9,-77.4,26,-77.3,26.5,-77.8,26.9,-77.8,27,-77,26.6],[134.6,34.1,134.8,33.8,134.2,33.2,133.8,33.5,133.3,33.3,133,32.7,132.4,33,132.4,33.5,132.9,34.1,133.5,33.9,133.9,34.4,134.6,34.1],[34.6,35.7,33.9,35.2,34,35.1,34,35,33,34.6,32.5,34.7,32.3,35.1,32.7,35.1,32.8,35.1,32.9,35.4,33.7,35.4,34.6,35.7],[23.7,35.7,24.2,35.4,25,35.4,25.8,35.4,25.7,35.2,26.3,35.3,26.2,35,24.7,34.9,24.7,35.1,23.5,35.3,23.7,35.7],[15.5,38.2,15.2,37.4,15.3,37.1,15.1,36.6,14.3,37,13.8,37.1,12.4,37.6,12.6,38.1,13.7,38,14.8,38.1,15.5,38.2],[9.2,41.2,9.8,40.5,9.7,39.2,9.2,39.2,8.8,38.9,8.4,39.2,8.4,40.4,8.2,41,8.7,40.9,9.2,41.2],[141,37.1,140.6,36.3,140.8,35.8,140.3,35.1,139,34.7,137.2,34.6,135.8,33.5,135.1,33.8,135.1,34.6,133.3,34.4,132.2,33.9,131,33.9,132,33.1,131.3,31.5,130.7,31,130.2,31.4,130.4,32.3,129.8,32.6,129.4,33.3,130.4,33.6,130.9,34.2,131.9,34.8,132.6,35.4,134.6,35.7,135.7,35.5,136.7,37.3,137.4,36.8,138.9,37.8,139.4,38.2,140.1,39.4,139.9,40.6,140.3,41.2,141.4,41.4,141.9,40,141.9,39.2,141,38.2,141,37.1],[9.6,42.2,9.2,41.4,8.8,41.6,8.5,42.3,8.7,42.6,9.4,43,9.6,42.2],[143.9,44.2,144.6,44,145.3,44.4,145.5,43.3,144.1,43,143.2,42,141.6,42.7,141.1,41.6,140,41.6,139.8,42.6,140.3,43.3,141.4,43.4,141.7,44.8,142,45.6,143.1,44.5,143.9,44.2],[-63.7,46.5,-62.9,46.4,-62,46.4,-62.5,46,-62.9,46,-64.1,46.4,-64.4,46.7,-64,47,-63.7,46.5],[-61.8,49.1,-62.3,49.1,-63.6,49.4,-64.5,49.9,-64.2,50,-62.9,49.7,-61.8,49.3,-61.8,49.1],[-123.5,48.5,-124,48.4,-125.7,48.8,-126,49.2,-126.8,49.5,-127,49.8,-128.1,50,-128.4,50.5,-128.4,50.8,-127.3,50.6,-126.7,50.4,-125.8,50.3,-125.4,49.9,-124.9,49.5,-123.9,49.1,-123.5,48.5],[-56.1,50.7,-56.8,49.8,-56.1,50.1,-55.5,49.9,-55.8,49.6,-54.9,49.3,-54.5,49.6,-53.5,49.2,-53.8,48.5,-53.1,48.7,-53,48.2,-52.6,47.5,-53.1,46.7,-53.5,46.6,-54.2,46.8,-54,47.6,-54.2,47.8,-55.4,46.9,-56,46.9,-55.3,47.4,-56.3,47.6,-57.3,47.6,-59.3,47.6,-59.4,47.9,-58.8,48.3,-59.2,48.5,-58.4,49.1,-57.4,50.7,-56.7,51.3,-55.9,51.6,-55.4,51.6,-55.6,51.3,-56.1,50.7],[-132.7,54,-131.7,54.1,-132.1,53,-131.2,52.2,-131.6,52.2,-132.2,52.6,-132.6,53.1,-133.1,53.4,-133.2,53.9,-133.2,54.2,-132.7,54],[143.6,50.7,144.7,49,143.2,49.3,142.6,47.9,143.5,46.8,143.5,46.1,142.7,46.7,142.1,46,141.9,46.8,142,47.8,141.9,48.9,142.1,49.6,142.2,51,141.6,51.9,141.7,53.3,142.6,53.8,142.2,54.2,142.7,54.4,142.9,53.7,143.3,52.7,143.2,51.8,143.6,50.7],[-6.8,52.3,-8.6,51.7,-10,51.8,-9.2,52.9,-9.7,53.9,-8.3,54.7,-7.6,55.1,-6.7,55.2,-5.7,54.6,-6.2,53.9,-6,53.2,-6.8,52.3],[12.7,55.6,12.1,54.8,11,55.4,10.9,55.8,12.4,56.1,12.7,55.6],[-153,57.1,-154,56.7,-154.5,57,-154.7,57.5,-153.8,57.8,-153.2,58,-152.6,57.9,-152.1,57.6,-153,57.1],[-3,58.6,-4.1,57.6,-3.1,57.7,-2,57.7,-2.2,56.9,-3.1,56,-2.1,55.9,-1.1,54.6,-0.4,54.5,0.2,53.3,0.5,52.9,1.7,52.7,1.6,52.1,1,51.8,1.4,51.3,0.5,50.8,-0.8,50.8,-2.5,50.5,-3,50.7,-3.6,50.2,-4.5,50.3,-5.2,50,-5.8,50.2,-4.3,51.2,-3.4,51.4,-5,51.6,-5.3,52,-4.2,52.3,-4.8,52.8,-4.6,53.5,-3.1,53.4,-2.9,54,-3.6,54.6,-4.8,54.8,-5.1,55.1,-4.7,55.5,-5,55.8,-5.6,55.3,-5.6,56.3,-6.2,56.8,-5.8,57.8,-5,58.6,-4.2,58.6,-3,58.6],[-165.6,59.9,-166.2,59.8,-166.8,59.9,-167.5,60.2,-166.5,60.4,-165.7,60.3,-165.6,59.9],[-79.3,62.2,-79.7,61.6,-80.1,61.7,-80.4,62,-80.3,62.1,-79.9,62.4,-79.5,62.4,-79.3,62.2],[-81.9,62.7,-83.1,62.2,-83.8,62.2,-84,62.5,-83.2,62.9,-81.9,62.9,-81.9,62.7],[-171.7,63.8,-171.1,63.6,-170.5,63.7,-169.7,63.4,-168.7,63.3,-168.8,63.2,-169.5,63,-170.3,63.2,-170.7,63.4,-171.6,63.3,-171.8,63.4,-171.7,63.8],[-85.2,65.7,-85,65.2,-84.5,65.4,-83.9,65.1,-82.8,64.8,-81.6,64.5,-81.6,64,-80.8,64.1,-80.1,63.7,-81,63.4,-82.5,63.7,-83.1,64.1,-84.1,63.6,-85.5,63.1,-85.9,63.6,-87.2,63.5,-86.4,64,-86.2,64.8,-85.9,65.7,-85.2,65.7],[-14.5,66.5,-14.7,65.8,-13.6,65.1,-14.9,64.4,-17.8,63.7,-18.7,63.5,-20,63.6,-22.8,64,-21.8,64.4,-24,64.9,-22.2,65.1,-22.2,65.4,-24.3,65.6,-23.7,66.3,-22.1,66.4,-20.6,65.7,-19.1,66.3,-17.8,66,-16.2,66.5,-14.5,66.5],[-75.9,67.1,-77,67.1,-77.2,67.6,-76.8,68.1,-75.9,68.3,-75.1,68,-75.1,67.6,-75.2,67.4,-75.9,67.1],[-180,69,-177.5,68.2,-174.9,67.2,-175,66.6,-174.3,66.3,-174.6,67.1,-171.9,66.9,-169.9,66,-170.9,65.5,-172.5,65.4,-172.6,64.5,-173,64.3,-173.9,64.3,-174.7,64.6,-176,64.9,-176.2,65.4,-177.2,65.5,-178.4,65.4,-178.9,65.7,-178.7,66.1,-179.9,65.9,-179.4,65.4,-180,65,180,65,178.7,64.5,177.4,64.6,178.3,64.1,178.9,63.3,179.4,63,179.5,62.6,179.2,62.3,177.4,62.5,174.6,61.8,173.7,61.7,172.1,60.9,170.7,60.3,170.3,59.9,168.9,60.6,166.3,59.8,165.8,60.2,164.9,59.7,163.5,59.9,163.2,59.2,162,58.2,162.1,57.8,163.2,57.6,163.1,56.2,162.1,56.1,161.7,55.3,162.1,54.9,160.4,54.3,160,53.2,158.5,53,158.2,51.9,156.8,51,156.4,51.7,156,53.2,155.4,55.4,155.9,56.8,156.8,57.4,156.8,57.8,158.4,58.1,160.1,59.3,161.9,60.3,163.7,61.1,164.5,62.6,163.3,62.5,162.7,61.6,160.1,60.5,159.3,61.8,156.7,61.4,154.2,59.8,155,59.1,152.8,58.9,151.3,58.8,151.3,59.5,149.8,59.7,148.5,59.2,145.5,59.3,142.2,59,139,57.1,135.1,54.7,136.7,54.6,137.2,54,138.2,53.8,138.8,54.3,139.9,54.2,141.3,53.1,141.4,52.2,140.6,51.2,140.5,50,140.1,48.4,138.6,47,138.2,46.3,136.9,45.1,135.5,44,134.9,43.4,133.5,42.8,132.9,42.8,132.3,43.3,130.9,42.6,130.8,42.2,130.4,42.3,130,41.9,129.7,41.6,129.7,40.9,129.2,40.7,129,40.5,128.6,40.2,128,40,127.5,39.8,127.5,39.3,127.4,39.2,127.8,39.1,128.4,38.6,129.2,37.4,129.5,36.8,129.5,35.6,129.1,35.1,128.2,34.9,127.4,34.5,126.5,34.4,126.4,34.9,126.6,35.7,126.1,36.7,126.9,36.9,126.2,37.7,125.7,37.9,125.6,37.8,125.3,37.7,125.2,37.9,125,37.9,124.7,38.1,125,38.5,125.2,38.7,125.1,38.8,125.4,39.4,125.3,39.6,124.7,39.7,124.3,39.9,122.9,39.6,122.1,39.2,121.1,38.9,121.6,39.4,121.4,39.8,122.2,40.4,121.6,40.9,120.8,40.6,119.6,39.9,119,39.3,118,39.2,117.5,38.7,118.1,38.1,118.9,37.9,118.9,37.4,119.7,37.2,120.8,37.9,121.7,37.5,122.4,37.5,122.5,36.9,121.1,36.7,120.6,36.1,119.7,35.6,119.2,34.9,120.2,34.4,120.6,33.4,121.2,32.5,121.9,31.7,121.9,30.9,121.3,30.7,121.5,30.1,122.1,29.8,121.9,29,121.7,28.2,121.1,28.1,120.4,27.1,119.6,25.7,118.7,24.5,117.3,23.6,115.9,22.8,114.8,22.7,114.2,22.2,113.8,22.5,113.2,22.1,111.8,21.6,110.8,21.4,110.4,20.3,109.9,20.3,109.6,21,109.9,21.4,108.5,21.7,108,21.6,106.7,20.7,105.9,19.8,105.7,19.1,106.4,18,107.4,16.7,108.3,16.1,108.9,15.3,109.3,13.4,109.2,11.7,108.4,11,107.2,10.4,106.4,9.5,105.2,8.6,104.8,9.2,105.1,9.9,104.3,10.5,103.5,10.6,103.1,11.2,102.6,12.2,101.7,12.6,100.8,12.6,101,13.4,100.1,13.4,100,12.3,99.5,10.8,99.2,10,99.2,9.2,99.9,9.2,100.3,8.3,100.5,7.4,101,6.9,101.6,6.7,102.1,6.2,102.4,6.1,103,5.5,103.4,4.9,103.4,4.2,103.3,3.7,103.4,3.4,103.5,2.8,103.9,2.5,104.2,1.6,104.2,1.3,103.5,1.2,102.6,2,101.4,2.8,101.3,3.3,100.7,3.9,100.6,4.8,100.2,5.3,100.3,6,100.1,6.5,99.7,6.8,99.5,7.3,99,7.9,98.5,8.4,98.3,7.8,98.1,8.3,98.3,9,98.6,9.9,98.5,10.7,98.8,11.4,98.4,12,98.5,13.1,98.1,13.6,97.8,14.8,97.6,16.1,97.2,16.9,96.5,16.4,95.4,15.7,94.8,15.8,94.2,16,94.5,17.3,94.3,18.2,93.5,19.4,93.7,19.7,93.1,19.9,92.4,20.7,92.1,21.2,92,21.7,91.8,22.2,91.4,22.8,90.5,22.8,90.6,22.4,90.3,21.8,89.8,22,89.7,21.9,89.4,22,89,22.1,88.9,21.7,88.2,21.7,87,21.5,87,20.7,86.5,20.2,85.1,19.5,83.9,18.3,83.2,17.7,82.2,17,82.2,16.6,81.7,16.3,80.8,16,80.3,15.9,80,15.1,80.2,13.8,80.3,13,79.9,12.1,79.9,10.4,79.3,10.3,78.9,9.5,79.2,9.2,78.3,8.9,77.9,8.3,77.5,8,76.6,8.9,76.1,10.3,75.7,11.3,75.4,11.8,74.9,12.7,74.6,14,74.4,14.6,73.5,16,73.1,17.9,72.8,19.2,72.8,20.4,72.6,21.4,71.2,20.8,70.5,20.9,69.2,22.1,69.6,22.5,69.3,22.8,68.2,23.7,67.4,23.9,67.1,24.7,66.4,25.4,64.5,25.2,62.9,25.2,61.5,25.1,59.6,25.4,58.5,25.6,57.4,25.7,57,27,56.5,27.1,55.7,27,54.7,26.5,53.5,26.8,52.5,27.6,51.5,27.9,50.9,28.8,50.1,30.1,49.6,30,48.9,30.3,48.6,29.9,48,30,48.2,29.5,48.1,29.3,48.4,28.6,48.8,27.7,49.3,27.5,49.5,27.1,50.2,26.7,50.2,26.3,50.1,25.9,50.2,25.6,50.5,25.3,50.7,25,50.8,24.8,50.7,25.5,51,26,51.3,26.1,51.6,25.8,51.6,25.2,51.4,24.6,51.6,24.2,51.8,24.3,51.8,24,52.6,24.2,53.4,24.2,54,24.1,54.7,24.8,55.4,25.4,56.1,26.1,56.4,26.4,56.5,26.3,56.4,25.9,56.3,25.7,56.4,24.9,56.8,24.2,57.4,23.9,58.1,23.7,58.7,23.6,59.2,23,59.4,22.7,59.8,22.5,59.8,22.3,59.4,21.7,59.3,21.4,58.9,21.1,58.5,20.4,58,20.5,57.8,20.2,57.7,19.7,57.8,19.1,57.7,18.9,57.2,18.9,56.6,18.6,56.5,18.1,56.3,17.9,55.7,17.9,55.3,17.6,55.3,17.2,54.8,16.9,54.2,17,53.6,16.7,53.1,16.7,52.4,16.4,52.2,15.9,52.2,15.6,51.2,15.2,49.6,14.7,48.7,14,48.2,13.9,47.9,14,47.4,13.6,46.7,13.4,45.9,13.3,45.6,13.3,45.4,13,45.1,13,45,12.7,44.5,12.7,44.2,12.6,43.5,12.6,43.2,13.2,43.3,13.8,43.1,14.1,42.9,14.8,42.6,15.2,42.8,15.3,42.7,15.7,42.8,15.9,42.8,16.3,42.7,16.8,42.3,17.1,42.3,17.5,41.8,17.8,41.2,18.7,40.9,19.5,40.2,20.2,39.8,20.3,39.1,21.3,39,22,39.1,22.6,38.5,23.7,38,24.1,37.5,24.3,37.2,24.9,37.2,25.1,36.9,25.6,36.6,25.8,36.3,26.6,35.6,27.4,35.1,28.1,34.6,28.1,34.8,28.6,34.8,29,35,29.4,34.9,29.5,34.6,29.1,34.4,28.3,34.2,27.8,33.9,27.6,33.6,28,33.1,28.4,32.4,29.9,32.3,29.8,32.7,28.7,33.3,27.7,34.1,26.1,34.5,25.6,34.8,25,35.7,23.9,35.5,23.8,35.5,23.1,36.7,22.2,36.9,22,37.2,21,37,20.8,37.1,19.8,37.5,18.6,37.9,18.4,38.4,18,39,16.8,39.3,15.9,39.8,15.4,41.2,14.5,41.7,13.9,42.3,13.3,42.6,13,43.1,12.7,43.3,12.4,43.3,12,42.7,11.7,43.1,11.5,43.5,11.3,43.7,10.9,44.1,10.4,44.6,10.4,45.6,10.7,46.6,10.8,47.5,11.1,48,11.2,48.4,11.4,48.9,11.4,49.3,11.4,49.7,11.6,50.3,11.7,50.7,12,51.1,12,51.1,11.7,51,11.2,51,10.6,50.8,10.3,50.6,9.2,50.1,8.1,49.5,6.8,48.6,5.3,47.7,4.2,46.6,2.9,45.6,2,44.1,1.1,43.1,0.3,42,-0.9,41.8,-1.4,41.6,-1.7,40.9,-2.1,40.6,-2.5,40.3,-2.6,40.1,-3.3,39.8,-3.7,39.6,-4.3,39.2,-4.7,38.7,-5.9,38.8,-6.5,39.4,-6.8,39.5,-7.1,39.2,-7.7,39.3,-8,39.2,-8.5,39.5,-9.1,40,-10.1,40.3,-10.3,40.5,-10.8,40.4,-11.8,40.6,-12.6,40.6,-14.2,40.8,-14.7,40.5,-15.4,40.1,-16.1,39.5,-16.7,38.5,-17.1,37.4,-17.6,36.3,-18.7,35.9,-18.8,35.2,-19.6,34.8,-19.8,34.7,-20.5,35.2,-21.3,35.4,-21.8,35.4,-22.1,35.6,-22.1,35.5,-23.1,35.4,-23.5,35.6,-23.7,35.5,-24.1,35,-24.5,34.2,-24.8,33,-25.4,32.6,-25.7,32.7,-26.1,32.9,-26.2,32.8,-26.7,32.6,-27.5,32.5,-28.3,32.2,-28.8,31.5,-29.3,31.3,-29.4,30.9,-29.9,30.6,-30.4,30.1,-31.1,28.9,-32.2,28.2,-32.8,27.5,-33.2,26.4,-33.6,25.9,-33.7,25.8,-33.9,25.2,-33.8,24.7,-34,23.6,-33.8,23,-33.9,22.6,-33.9,21.5,-34.3,20.7,-34.4,20.1,-34.8,19.6,-34.8,19.2,-34.5,18.9,-34.4,18.4,-34,18.4,-34.1,18.2,-33.9,18.3,-33.3,17.9,-32.6,18.2,-32.4,18.2,-31.7,17.6,-30.7,17.1,-29.9,16.3,-28.6,15.6,-27.8,15.2,-27.1,15,-26.1,14.7,-25.4,14.4,-23.9,14.4,-22.7,14.3,-22.1,13.9,-21.7,13.4,-20.9,12.8,-19.7,12.6,-19,11.8,-18.1,11.7,-17.3,11.6,-16.7,11.8,-15.8,12.1,-14.9,12.2,-14.4,12.5,-13.5,12.7,-13.1,13.3,-12.5,13.6,-12,13.7,-11.3,13.7,-10.7,13.4,-10.4,13.1,-9.8,12.9,-9.2,12.9,-9,13.2,-8.6,12.9,-7.6,12.7,-6.9,12.2,-6.3,12.3,-6.1,12.2,-5.8,11.9,-5,11.1,-4,10.1,-3,9.4,-2.1,8.8,-1.1,8.8,-0.8,9,-0.5,9.3,0.3,9.5,1,9.3,1.2,9.6,2.3,9.8,3.1,9.4,3.7,8.9,3.9,8.7,4.4,8.5,4.5,8.5,4.8,7.5,4.4,7.1,4.5,6.7,4.2,5.9,4.3,5.4,4.9,5,5.6,4.3,6.3,3.6,6.3,2.7,6.3,1.9,6.1,1.1,5.9,-0.5,5.3,-1.1,5,-2,4.7,-2.9,5,-3.3,5,-4,5.2,-4.6,5.2,-5.8,5,-6.5,4.7,-7.5,4.3,-7.7,4.4,-8,4.4,-9,4.8,-9.9,5.6,-10.8,6.1,-11.4,6.8,-11.7,6.9,-12.4,7.3,-12.9,7.8,-13.1,8.2,-13.2,8.9,-13.7,9.5,-14.1,9.9,-14.3,10,-14.6,10.2,-14.7,10.7,-14.8,10.9,-15.1,11,-15.7,11.5,-16.1,11.5,-16.3,11.8,-16.3,12,-16.6,12.2,-16.7,12.4,-16.8,13.2,-16.7,13.6,-17.1,14.4,-17.6,14.7,-17.2,14.9,-16.7,15.6,-16.5,16.1,-16.6,16.7,-16.3,17.2,-16.1,18.1,-16.3,19.1,-16.4,19.6,-16.3,20.1,-16.5,20.6,-17.1,21,-17,21.4,-17,21.9,-16.6,22.2,-16.3,22.7,-16.3,23,-16,23.7,-15.4,24.4,-15.1,24.5,-14.8,25.1,-14.8,25.6,-14.4,26.3,-13.8,26.6,-13.1,27.6,-12.6,28,-11.7,28.1,-10.9,28.8,-10.4,29.1,-9.6,29.9,-9.8,31.2,-9.4,32,-9.3,32.6,-8.7,33.2,-7.7,33.7,-6.9,34.1,-6.2,35.1,-5.9,35.8,-5.2,35.8,-4.6,35.3,-3.6,35.4,-2.6,35.2,-2.2,35.2,-1.2,35.7,-0.1,35.9,0.5,36.3,1.5,36.6,3.2,36.8,4.8,36.9,5.3,36.7,6.3,37.1,7.3,37.1,7.7,36.9,8.4,36.9,9.5,37.4,10.2,37.2,10.2,36.7,11,37.1,11.1,36.9,10.6,36.4,10.6,35.9,10.9,35.7,10.8,34.8,10.2,34.3,10.3,33.8,10.9,33.8,11.1,33.3,11.5,33.1,12.7,32.8,13.1,32.9,13.9,32.7,15.2,32.3,15.7,31.4,16.6,31.2,18,30.8,19.1,30.3,19.6,30.5,20.1,31,19.8,31.8,20.1,32.2,20.9,32.7,21.5,32.8,22.9,32.6,23.2,32.2,23.6,32.2,23.9,32,24.9,31.9,25.2,31.6,26.5,31.6,27.5,31.3,28.4,31,28.9,30.9,29.7,31.2,30.1,31.5,31,31.6,31.7,31.4,32,30.9,32.2,31.3,33,31,33.8,31,34.3,31.2,34.6,31.5,34.5,31.6,34.8,32.1,35,32.8,35.1,33.1,35.5,33.9,36,34.6,35.9,35.4,36.1,35.8,35.8,36.3,36.2,36.7,35.6,36.6,34.7,36.8,34,36.2,32.5,36.1,31.7,36.6,30.6,36.7,30.4,36.3,29.7,36.1,28.7,36.7,27.6,36.7,27,37.7,26.3,38.2,26.8,39,26.2,39.5,27.3,40.4,28.8,40.5,29.2,41.2,31.1,41.1,32.3,41.7,33.5,42,35.2,42,36.9,41.3,38.3,40.9,39.5,41.1,40.4,41,41.6,41.5,41.7,42,41.5,42.6,40.9,43,40.3,43.1,40,43.4,38.7,44.3,37.5,44.7,36.7,45.2,37.4,45.4,38.2,46.2,37.7,46.6,39.1,47,39.1,47.3,38.2,47.1,37.4,47,36.8,46.7,35.8,46.6,35,46.3,35,45.7,35.5,45.4,36.5,45.5,36.3,45.1,35.2,44.9,33.9,44.4,33.3,44.6,33.5,45,32.5,45.3,32.6,45.5,33.6,45.9,33.3,46.1,31.7,46.3,31.7,46.7,30.7,46.6,30.4,46,29.6,45.3,29.6,45,29.1,44.8,28.8,44.9,28.6,43.7,28,43.3,27.7,42.6,28,42,28.1,41.6,29,41.3,28.8,41.1,27.6,41,27.2,40.7,26.4,40.2,26,40.6,26.1,40.8,25.4,40.9,24.9,40.9,23.7,40.7,24.4,40.1,23.9,40,23.3,40,22.8,40.5,22.6,40.3,22.9,39.7,23.4,39.2,23,39,23.5,38.5,24,38.2,24,37.7,23.1,37.9,23.4,37.4,22.8,37.3,23.2,36.4,22.5,36.4,21.7,36.8,21.3,37.6,21.1,38.3,20.7,38.8,20.2,39.3,20.2,39.6,20,39.7,20,39.9,19.4,40.3,19.3,40.7,19.4,41.4,19.5,41.7,19.4,41.9,19.2,42,18.9,42.3,18.4,42.5,17.5,42.8,16.9,43.2,16,43.5,15.2,44.2,15.4,44.3,14.9,44.7,14.9,45.1,14.3,45.2,14,44.8,13.7,45.1,13.7,45.5,13.9,45.6,13.1,45.7,12.3,45.4,12.4,44.9,12.3,44.6,12.6,44.1,13.5,43.6,14,42.8,15.1,42,15.9,42,16.2,41.7,15.9,41.5,16.8,41.2,17.5,40.9,18.4,40.4,18.5,40.2,18.3,39.8,17.7,40.3,16.9,40.4,16.5,39.8,17.2,39.4,17.1,38.9,16.6,38.8,16.1,38,15.7,37.9,15.7,38.2,15.9,38.8,16.1,39,15.7,39.5,15.4,40,15,40.2,14.7,40.6,14.1,40.8,13.6,41.2,12.9,41.3,12.1,41.7,11.2,42.4,10.5,42.9,10.2,43.9,9.7,44,8.9,44.4,8.4,44.2,7.8,43.8,7.4,43.7,6.5,43.1,4.6,43.4,3.1,43.1,3,42.5,3,41.9,2.1,41.2,0.8,41,0.7,40.7,0.1,40.1,-0.3,39.3,0.1,38.7,-0.5,38.3,-0.7,37.6,-1.4,37.4,-2.1,36.7,-3.4,36.7,-4.4,36.7,-5,36.3,-5.4,35.9,-5.9,36,-6.2,36.4,-6.5,36.9,-7.5,37.1,-7.9,36.8,-8.4,37,-8.9,36.9,-8.7,37.7,-8.8,38.3,-9.3,38.4,-9.5,38.7,-9.4,39.4,-9,39.8,-9,40.2,-8.8,40.8,-8.8,41.2,-9,41.5,-9,41.9,-9,42.6,-9.4,43,-8,43.7,-6.8,43.6,-5.4,43.6,-4.3,43.4,-3.5,43.5,-1.9,43.4,-1.4,44,-1.2,46,-2.2,47.1,-3,47.6,-4.5,48,-4.6,48.7,-3.3,48.9,-1.6,48.6,-1.9,49.8,-1,49.3,1.3,50.1,1.6,50.9,2.5,51.1,3.3,51.3,3.8,51.6,4.7,53.1,6.1,53.5,6.9,53.5,7.1,53.7,7.9,53.7,8.1,53.5,8.8,54,8.6,54.4,8.5,55,8.1,55.5,8.1,56.5,8.3,56.8,8.5,57.1,9.4,57.2,9.8,57.4,10.6,57.7,10.5,57.2,10.3,56.9,10.4,56.6,10.9,56.5,10.7,56.1,10.4,56.2,9.6,55.5,9.9,55,9.9,54.6,10.9,54.4,10.9,54,12,54.2,12.5,54.5,13.6,54.1,14.1,53.8,14.8,54.1,16.4,54.5,17.6,54.9,18.6,54.7,18.7,54.4,19.7,54.4,19.9,54.9,21.3,55.2,21.1,56,21.1,56.8,21.6,57.4,22.5,57.8,23.3,57,24.1,57,24.3,57.8,24.4,58.4,24.1,58.3,23.4,58.6,23.3,59.2,24.6,59.5,25.9,59.6,26.9,59.4,28,59.5,29.1,60,28.1,60.5,26.3,60.4,24.5,60.1,22.9,59.8,22.3,60.4,21.3,60.7,21.5,61.7,21.1,62.6,21.5,63.2,22.4,63.8,24.7,64.9,25.4,65.1,25.3,65.5,23.9,66,22.2,65.7,21.2,65,21.4,64.4,19.8,63.6,17.8,62.7,17.1,61.3,17.8,60.6,18.8,60.1,17.9,59,16.8,58.7,16.4,57,15.9,56.1,14.7,56.2,14.1,55.4,12.9,55.4,12.6,56.3,11.8,57.4,11,58.9,10.4,59.5,8.4,58.3,7.1,58.1,5.7,58.6,5.3,59.7,5,62,5.9,62.6,8.6,63.5,10.5,64.5,12.4,65.9,14.8,67.8,16.4,68.6,19.2,69.8,21.4,70.3,23,70.2,24.5,71,26.4,71,28.2,71.2,31.3,70.5,30,70.2,31.1,69.6,32.1,69.9,33.8,69.3,36.5,69.1,40.3,67.9,41.1,67.5,41.1,66.8,40,66.3,38.4,66,33.9,66.8,33.2,66.6,34.8,65.9,34.9,64.4,36.2,64.1,37,63.9,37.1,64.3,36.5,64.8,37.2,65.1,39.6,64.5,40.4,64.8,39.8,65.5,42.1,66.5,43,66.4,44,66.1,44.5,66.8,43.7,67.4,44.2,68,43.5,68.6,46.3,68.2,46.8,67.7,45.6,67.6,45.6,67,46.3,66.7,47.9,66.9,48.1,67.5,50.2,68,53.7,68.9,54.5,68.8,53.5,68.2,54.7,68.1,55.4,68.4,57.3,68.5,58.8,68.9,59.9,68.3,61.1,68.9,60,69.5,60.6,69.9,63.5,69.5,64.9,69.2,68.5,68.1,69.2,68.6,68.2,69.1,68.1,69.4,66.9,69.5,67.3,69.9,66.7,70.7,66.7,71,68.5,71.9,69.2,72.8,69.9,73,72.6,72.8,72.8,72.2,71.8,71.4,72.5,71.1,72.8,70.4,72.6,69,73.7,68.4,73.2,67.7,71.3,66.3,72.4,66.2,72.8,66.5,73.9,66.8,74.2,67.3,75.1,67.8,74.5,68.3,74.9,69,73.8,69.1,73.6,69.6,74.4,70.6,73.1,71.4,74.9,72.1,74.7,72.8,75.2,72.9,75.7,72.3,75.3,71.3,76.4,71.2,75.9,71.9,77.6,72.3,79.7,72.3,81.5,71.7,80.6,72.6,80.5,73.6,82.3,73.9,84.7,73.8,86.8,73.9,86,74.5,87.2,75.1,88.3,75.1,90.3,75.6,92.9,75.8,93.2,76,95.9,76.1,96.7,75.9,98.9,76.4,100.8,76.4,101,76.9,102,77.3,104.4,77.7,106.1,77.4,104.7,77.1,107,77,107.2,76.5,108.2,76.7,111.1,76.7,113.3,76.2,114.1,75.8,113.9,75.3,112.8,75,110.2,74.5,109.4,74.2,110.6,74,112.1,73.8,113,74,113.5,73.3,114,73.6,115.6,73.8,118.8,73.6,119,73.1,123.2,73,123.3,73.7,125.4,73.6,127,73.6,128.6,73,129.1,72.4,128.5,72,129.7,71.2,131.3,70.8,132.3,71.8,133.9,71.4,135.6,71.7,137.5,71.3,138.2,71.6,139.9,71.5,139.1,72.4,140.5,72.8,149.5,72.2,150.4,71.6,153,70.8,157,71,159,70.9,159.8,70.5,159.7,69.7,160.9,69.4,162.3,69.6,164.1,69.7,165.9,69.5,167.8,69.6,169.6,68.7,170.8,69,170,69.7,170.5,70.1,173.6,69.8,175.7,69.9,178.6,69.4,-180,69],[49.1,41.3,49.6,40.6,50.1,40.5,50.4,40.3,49.6,40.2,49.4,39.4,49.2,39,48.9,38.8,48.9,38.3,49.2,37.6,50.1,37.4,50.8,36.9,52.3,36.7,53.8,37,53.9,37.2,53.7,37.9,53.9,39,53.1,39.3,53.4,40,52.7,40,52.9,40.9,53.9,40.6,54.7,41,54,41.6,53.7,42.1,52.9,41.9,52.8,41.1,52.5,41.8,52.4,42,52.7,42.4,52.5,42.8,51.3,43.1,50.9,44,50.3,44.3,50.3,44.6,51.3,44.5,51.3,45.2,52.2,45.4,53,45.3,53.2,46.2,53,46.9,52,46.8,51.2,47,50,46.6,49.1,46.4,48.6,45.8,47.7,45.6,46.7,44.6,47.6,43.7,47.5,43,48.6,41.8,49.1,41.3],[-95.6,69.1,-96.3,68.8,-97.6,69.1,-98.4,69,-99.8,69.4,-98.9,69.7,-98.2,70.1,-97.2,69.9,-96.6,69.7,-96.3,69.5,-95.6,69.1],[-180,71.5,180,70.8,178.9,70.8,178.7,71.1,-180,71.5],[-180,71.5,-179.9,71.6,-179,71.6,-177.6,71.3,-177.7,71.1,-178.7,70.9,-180,70.8,-180,71.5],[-90.5,69.5,-90.5,68.5,-89.2,69.3,-88,68.6,-88.3,67.9,-87.3,67.2,-86.3,67.9,-85.6,68.8,-85.5,69.9,-84.1,69.8,-82.6,69.7,-81.3,69.2,-81.2,68.7,-82,68.1,-81.3,67.6,-81.4,67.1,-83.3,66.4,-84.7,66.3,-85.8,66.6,-86.1,66.1,-87,65.2,-87.3,64.8,-88.5,64.1,-89.9,64,-90.7,63.6,-90.8,63,-91.9,62.8,-93.2,62,-94.2,60.9,-94.6,60.1,-94.7,58.9,-93.2,58.8,-92.8,57.8,-92.3,57.1,-90.9,57.3,-89,56.9,-88,56.5,-87.3,56,-86.1,55.7,-85,55.3,-83.4,55.2,-82.3,55.1,-82.4,54.3,-82.1,53.3,-81.4,52.2,-79.9,51.2,-79.1,51.5,-78.6,52.6,-79.1,54.1,-79.8,54.7,-78.2,55.1,-77.1,55.8,-76.5,56.5,-76.6,57.2,-77.3,58.1,-78.5,58.8,-77.3,59.9,-77.8,60.8,-78.1,62.3,-77.4,62.6,-75.7,62.3,-74.7,62.2,-73.8,62.4,-72.9,62.1,-71.7,61.5,-71.4,61.1,-69.6,61.1,-69.6,60.2,-69.3,59,-68.4,58.8,-67.7,58.2,-66.2,58.8,-65.2,59.9,-64.6,60.3,-63.8,59.4,-62.5,58.2,-61.4,57,-61.8,56.3,-60.5,55.8,-59.6,55.2,-58,54.9,-57.3,54.6,-56.9,53.8,-56.2,53.6,-55.8,53.3,-55.7,52.1,-56.4,51.8,-57.1,51.4,-58.8,51.1,-60,50.2,-61.7,50.1,-63.9,50.3,-65.4,50.3,-66.4,50.2,-67.2,49.5,-68.5,49.1,-70,47.7,-71.1,46.8,-70.3,47,-68.7,48.3,-66.6,49.1,-65.1,49.2,-64.2,48.7,-65.1,48.1,-64.8,47,-64.5,46.2,-63.2,45.7,-61.5,45.9,-60.5,47,-60.5,46.3,-59.8,45.9,-61,45.3,-63.3,44.7,-64.2,44.3,-65.4,43.5,-66.1,43.6,-66.2,44.5,-64.4,45.3,-66,45.3,-67.1,45.1,-67,44.8,-68,44.3,-69.1,44,-70.1,43.7,-70.7,43,-70.8,42.9,-70.8,42.3,-70.5,41.8,-70.1,41.8,-70.2,42.1,-69.9,41.9,-70,41.6,-70.6,41.5,-71.1,41.5,-71.9,41.3,-72.3,41.3,-72.9,41.2,-73.7,40.9,-72.2,41.1,-71.9,40.9,-73.3,40.6,-74,40.6,-74,40.8,-74.3,40.5,-74,40.4,-74.2,39.7,-74.9,38.9,-75,39.2,-75.2,39.2,-75.5,39.5,-75.3,39,-75.1,38.8,-75.1,38.4,-75.4,38,-75.9,37.2,-76,37.3,-75.7,37.9,-76.2,38.3,-76.4,39.1,-76.5,38.7,-76.3,38.1,-77,38.2,-76.3,37.9,-76.3,37,-76,36.9,-75.9,36.6,-75.7,35.6,-76.4,34.8,-77.4,34.5,-78.1,33.9,-78.6,33.9,-79.1,33.5,-79.2,33.2,-80.3,32.5,-80.9,32,-81.3,31.4,-81.5,30.7,-81.3,30,-81,29.2,-80.5,28.5,-80.5,28,-80.1,26.9,-80.1,26.2,-80.1,25.8,-80.4,25.2,-80.7,25.1,-81.2,25.2,-81.3,25.6,-81.7,25.9,-82.2,26.7,-82.7,27.5,-82.9,27.9,-82.7,28.6,-82.9,29.1,-83.7,29.9,-84.1,30.1,-85.1,29.6,-85.3,29.7,-85.8,30.2,-86.4,30.4,-87.5,30.3,-88.4,30.4,-89.2,30.3,-89.6,30.2,-89.4,29.9,-89.4,29.5,-89.2,29.3,-89.4,29.2,-89.8,29.3,-90.2,29.1,-90.9,29.1,-91.6,29.7,-92.5,29.6,-93.2,29.8,-93.8,29.7,-94.7,29.5,-95.6,28.7,-96.6,28.3,-97.1,27.8,-97.4,27.4,-97.4,26.7,-97.3,26.2,-97.1,25.9,-97.5,25,-97.7,24.3,-97.8,22.9,-97.9,22.4,-97.7,21.9,-97.4,21.4,-97.2,20.6,-96.5,19.9,-96.3,19.3,-95.9,18.8,-94.8,18.6,-94.4,18.1,-93.5,18.4,-92.8,18.5,-92,18.7,-91.4,18.9,-90.8,19.3,-90.5,19.9,-90.5,20.7,-90.3,21,-89.6,21.3,-88.5,21.5,-87.7,21.5,-87.1,21.5,-86.8,21.3,-86.8,20.8,-87.4,20.3,-87.6,19.6,-87.4,19.5,-87.6,19,-87.8,18.3,-88.1,18.5,-88.3,18.5,-88.3,18.4,-88.1,18.3,-88.1,18.1,-88.3,17.6,-88.2,17.5,-88.3,17.1,-88.2,17,-88.4,16.5,-88.6,16.3,-88.7,16.2,-88.9,15.9,-88.6,15.7,-88.5,15.9,-88.2,15.7,-88.1,15.7,-87.9,15.9,-87.6,15.9,-87.5,15.8,-87.4,15.8,-86.9,15.8,-86.4,15.8,-86.1,15.9,-86,16,-85.7,16,-85.4,15.9,-85.2,15.9,-85,16,-84.5,15.9,-84.4,15.8,-84.1,15.6,-83.8,15.4,-83.4,15.3,-83.1,15,-83.2,14.9,-83.3,14.7,-83.2,14.3,-83.4,14,-83.5,13.6,-83.6,13.1,-83.5,12.9,-83.5,12.4,-83.6,12.3,-83.7,11.9,-83.7,11.6,-83.9,11.4,-83.8,11.1,-83.7,10.9,-83.4,10.4,-83,10,-82.5,9.6,-82.2,9.2,-82.2,9,-81.8,9,-81.7,9,-81.4,8.8,-80.9,8.9,-80.5,9.1,-79.9,9.3,-79.6,9.6,-79,9.6,-79.1,9.5,-78.5,9.4,-78.1,9.2,-77.7,8.9,-77.4,8.7,-76.8,8.6,-76.1,9.3,-75.7,9.4,-75.7,9.8,-75.5,10.6,-74.9,11.1,-74.3,11.1,-74.2,11.3,-73.4,11.2,-72.6,11.7,-72.2,12,-71.8,12.4,-71.4,12.4,-71.1,12.1,-71.3,11.8,-71.4,11.5,-71.9,11.4,-71.6,11,-71.6,10.4,-72.1,9.9,-71.7,9.1,-71.3,9.1,-71,9.9,-71.4,10.2,-71.4,11,-70.2,11.4,-70.3,11.8,-69.9,12.2,-69.6,11.5,-68.9,11.4,-68.2,10.9,-68.2,10.6,-67.3,10.5,-66.2,10.6,-65.7,10.2,-64.9,10.1,-64.3,10.4,-64.3,10.6,-63.1,10.7,-61.9,10.7,-62.7,10.4,-62.4,9.9,-61.6,9.9,-60.8,9.4,-60.7,8.6,-60.2,8.6,-59.8,8.4,-59.1,8,-58.5,7.3,-58.5,6.8,-58.1,6.8,-57.5,6.3,-57.1,6,-55.9,5.8,-55.8,6,-55,6,-54,5.8,-53.6,5.6,-52.9,5.4,-51.8,4.6,-51.7,4.2,-51.3,4.2,-51.1,3.6,-50.5,1.9,-50,1.7,-49.9,1,-50.7,0.2,-50.4,-0.1,-48.6,-0.2,-48.6,-1.2,-47.8,-0.6,-46.6,-0.9,-44.9,-1.6,-44.4,-2.1,-44.6,-2.7,-43.4,-2.4,-41.5,-2.9,-40,-2.9,-38.5,-3.7,-37.2,-4.8,-36.5,-5.1,-35.6,-5.1,-35.2,-5.5,-34.9,-6.7,-34.7,-7.3,-35.1,-9,-35.6,-9.6,-37,-11,-37.7,-12.2,-38.4,-13,-38.7,-13.1,-39,-13.8,-38.9,-15.7,-39.2,-17.2,-39.3,-17.9,-39.6,-18.3,-39.8,-19.6,-40.8,-20.9,-40.9,-21.9,-41.8,-22.4,-42,-23,-43.1,-23,-44.6,-23.4,-45.4,-23.8,-46.5,-24.1,-47.6,-24.9,-48.5,-25.9,-48.6,-26.6,-48.5,-27.2,-48.7,-28.2,-48.9,-28.7,-49.6,-29.2,-50.7,-31,-51.6,-31.8,-52.3,-32.2,-52.7,-33.2,-53.4,-33.8,-53.8,-34.4,-54.9,-35,-55.7,-34.8,-56.2,-34.9,-57.1,-34.4,-57.8,-34.5,-58.4,-33.9,-58.5,-34.4,-57.2,-35.3,-57.4,-36,-56.7,-36.4,-56.8,-36.9,-57.7,-38.2,-59.2,-38.7,-61.2,-38.9,-62.3,-38.8,-62.1,-39.4,-62.3,-40.2,-62.1,-40.7,-62.7,-41,-63.8,-41.2,-64.7,-40.8,-65.1,-41.1,-65,-42.1,-64.3,-42.4,-63.8,-42,-63.5,-42.6,-64.4,-42.9,-65.2,-43.5,-65.3,-44.5,-65.6,-45,-66.5,-45,-67.3,-45.6,-67.6,-46.3,-66.6,-47,-65.6,-47.2,-66,-48.1,-67.2,-48.7,-67.8,-49.9,-68.7,-50.3,-69.1,-50.7,-68.8,-51.8,-68.2,-52.4,-68.6,-52.3,-69.5,-52.3,-69.9,-52.5,-70.8,-52.9,-71,-53.8,-71.4,-53.9,-72.6,-53.5,-73.7,-52.8,-74.9,-52.3,-75.3,-51.6,-75,-51,-75.5,-50.4,-75.6,-48.7,-75.2,-47.7,-74.1,-46.9,-75.6,-46.6,-74.7,-45.8,-74.4,-44.1,-73.2,-44.5,-72.7,-42.4,-73.4,-42.1,-73.7,-43.4,-74.3,-43.2,-74,-41.8,-73.7,-39.9,-73.2,-39.3,-73.5,-38.3,-73.6,-37.2,-73.2,-37.1,-72.6,-35.5,-71.9,-33.9,-71.4,-32.4,-71.7,-30.9,-71.4,-30.1,-71.5,-28.9,-70.9,-27.6,-70.7,-25.7,-70.4,-23.6,-70.1,-21.4,-70.2,-19.8,-70.4,-18.3,-71.4,-17.8,-71.5,-17.4,-73.4,-16.4,-75.2,-15.3,-76,-14.6,-76.4,-13.8,-76.3,-13.5,-77.1,-12.2,-78.1,-10.4,-79,-8.4,-79.4,-7.9,-79.8,-7.2,-80.5,-6.5,-81.3,-6.1,-80.9,-5.7,-81.4,-4.7,-81.1,-4,-80.3,-3.4,-79.8,-2.7,-80,-2.2,-80.4,-2.7,-81,-2.2,-80.8,-2,-80.9,-1.1,-80.6,-0.9,-80.4,-0.3,-80,0.4,-80.1,0.8,-79.5,1,-78.9,1.4,-79,1.7,-78.6,1.8,-78.7,2.3,-78.4,2.6,-77.9,2.7,-77.5,3.3,-77.1,3.8,-77.5,4.1,-77.3,4.7,-77.5,5.6,-77.3,5.8,-77.5,6.7,-77.9,7.2,-78.2,7.5,-78.4,8.1,-78.2,8.3,-78.4,8.4,-78.6,8.7,-79.1,9,-79.6,8.9,-79.8,8.6,-80.2,8.3,-80.4,8.3,-80.5,8.1,-80,7.5,-80.3,7.4,-80.4,7.3,-80.9,7.2,-81.1,7.8,-81.2,7.6,-81.5,7.7,-81.7,8.1,-82.1,8.2,-82.4,8.3,-82.8,8.3,-82.8,8.1,-83,8.2,-83.5,8.4,-83.7,8.7,-83.6,8.8,-83.6,9.1,-83.9,9.3,-84.3,9.5,-84.6,9.6,-84.7,9.9,-85,10.1,-84.9,9.8,-85.1,9.6,-85.3,9.8,-85.7,9.9,-85.8,10.1,-85.8,10.4,-85.7,10.8,-85.9,10.9,-85.7,11.1,-86.1,11.4,-86.5,11.8,-86.7,12.1,-87.2,12.5,-87.7,12.9,-87.6,13.1,-87.4,12.9,-87.3,13,-87.5,13.3,-87.8,13.4,-87.9,13.1,-88.5,13.2,-88.8,13.3,-89.3,13.5,-89.8,13.5,-90.1,13.7,-90.6,13.9,-91.2,13.9,-91.7,14.1,-92.2,14.5,-93.4,15.6,-93.9,15.9,-94.7,16.2,-95.3,16.1,-96.1,15.8,-96.6,15.7,-97.3,15.9,-98,16.1,-98.9,16.6,-99.7,16.7,-100.8,17.2,-101.7,17.6,-101.9,17.9,-102.5,18,-103.5,18.3,-103.9,18.7,-105,19.3,-105.5,19.9,-105.7,20.4,-105.4,20.5,-105.5,20.8,-105.3,21.1,-105.3,21.4,-105.6,21.9,-105.7,22.3,-106,22.8,-106.9,23.8,-107.9,24.5,-108.4,25.2,-109.3,25.6,-109.4,25.8,-109.3,26.4,-109.8,26.7,-110.4,27.2,-110.6,27.9,-111.2,27.9,-111.8,28.5,-112.2,29,-112.3,29.3,-112.8,30,-113.2,30.8,-113.1,31.2,-113.9,31.6,-114.2,31.5,-114.8,31.8,-114.9,31.4,-114.8,30.9,-114.7,30.2,-114.3,29.8,-113.6,29.1,-113.4,28.8,-113.3,28.8,-113.1,28.4,-113,28.4,-112.8,27.8,-112.5,27.5,-112.2,27.2,-111.6,26.7,-111.3,25.7,-111,25.3,-110.7,24.8,-110.7,24.3,-110.2,24.3,-109.8,23.8,-109.4,23.4,-109.4,23.2,-109.9,22.8,-110,22.8,-110.3,23.4,-111,24,-111.7,24.5,-112.2,24.7,-112.2,25.5,-112.3,26,-112.8,26.3,-113.5,26.8,-113.6,26.6,-113.8,26.9,-114.5,27.1,-115.1,27.7,-115,27.8,-114.6,27.7,-114.2,28.1,-114.2,28.6,-114.9,29.3,-115.5,29.6,-115.9,30.2,-116.3,30.8,-116.7,31.6,-117.1,32.5,-117.3,33,-117.9,33.6,-118.4,33.7,-118.5,34,-119.1,34.1,-119.4,34.3,-120.4,34.4,-120.6,34.6,-120.7,35.2,-121.7,36.2,-122.5,37.6,-122.5,37.8,-123,38.1,-123.7,39,-123.9,39.8,-124.4,40.3,-124.2,41.1,-124.2,42,-124.5,42.8,-124.1,43.7,-123.9,45.5,-124.1,46.9,-124.4,47.7,-124.7,48.2,-124.6,48.4,-123.1,48,-122.6,47.1,-122.3,47.4,-122.5,48.2,-122.8,49,-123,49,-124.9,50,-125.6,50.4,-127.4,50.8,-128,51.7,-127.8,52.3,-129.1,52.8,-129.3,53.6,-130.5,54.3,-130.5,54.8,-131.1,55.2,-132,55.5,-132.2,56.4,-133.5,57.2,-134.1,58.1,-135,58.2,-136.6,58.2,-137.8,58.5,-139.9,59.5,-140.8,59.7,-142.6,60.1,-144,60,-145.9,60.5,-147.1,60.9,-148.2,60.7,-148,60,-148.6,59.9,-149.7,59.7,-150.6,59.4,-151.7,59.2,-151.9,59.7,-151.4,60.7,-150.3,61,-150.6,61.3,-151.9,60.7,-152.6,60.1,-154,59.4,-153.3,58.9,-154.2,58.1,-155.3,57.7,-156.3,57.4,-156.6,57,-158.1,56.5,-158.4,56,-159.6,55.6,-160.3,55.6,-161.2,55.4,-162.2,55,-163.1,54.7,-164.8,54.4,-164.9,54.6,-163.8,55,-162.9,55.3,-161.8,55.9,-160.6,56,-160.1,56.4,-158.7,57,-158.5,57.2,-157.7,57.6,-157.6,58.3,-157,58.9,-158.2,58.6,-158.5,58.8,-159.1,58.4,-159.7,58.9,-160,58.6,-160.4,59.1,-161.4,58.7,-162,58.7,-162.1,59.3,-161.9,59.6,-162.5,60,-163.8,59.8,-164.7,60.3,-165.3,60.5,-165.4,61.1,-166.1,61.5,-165.7,62.1,-164.9,62.6,-164.6,63.1,-163.8,63.2,-163.1,63.1,-162.3,63.5,-161.5,63.5,-160.8,63.8,-161,64.2,-161.5,64.4,-160.8,64.8,-161.4,64.8,-162.5,64.6,-162.8,64.3,-163.5,64.6,-165,64.4,-166.4,64.7,-166.8,65.1,-168.1,65.7,-166.7,66.1,-164.5,66.6,-163.7,66.6,-163.8,66.1,-161.7,66.1,-162.5,66.7,-163.7,67.1,-164.4,67.6,-165.4,68,-166.8,68.4,-166.2,68.9,-164.4,68.9,-163.2,69.4,-162.9,69.9,-161.9,70.3,-160.9,70.4,-159,70.9,-158.1,70.8,-156.6,71.4,-155.1,71.1,-154.3,70.7,-153.9,70.9,-152.2,70.8,-152.3,70.6,-150.7,70.4,-149.7,70.5,-147.6,70.2,-145.7,70.1,-144.9,70,-143.6,70.2,-142.1,69.9,-141,69.7,-139.1,69.5,-137.5,69,-136.5,68.9,-135.6,69.3,-134.4,69.6,-132.9,69.5,-131.4,69.9,-129.8,70.2,-129.1,69.8,-128.4,70,-128.1,70.5,-127.4,70.4,-125.8,69.5,-124.4,70.2,-124.3,69.4,-123.1,69.6,-122.7,69.9,-121.5,69.8,-119.9,69.4,-117.6,69,-116.2,68.8,-115.2,68.9,-113.9,68.4,-115.3,67.9,-113.5,67.7,-110.8,67.8,-109.9,68,-108.9,67.4,-107.8,67.9,-108.8,68.3,-108.2,68.7,-107,68.7,-106.1,68.8,-105.3,68.6,-104.3,68,-103.2,68.1,-101.5,67.6,-99.9,67.8,-98.4,67.8,-98.6,68.4,-97.7,68.6,-96.1,68.2,-96.1,67.3,-95.5,68.1,-94.7,68.1,-94.2,69.1,-95.3,69.7,-96.5,70.1,-96.4,71.2,-95.2,71.9,-93.9,71.8,-92.9,71.3,-91.5,70.2,-92.4,69.7,-90.5,69.5],[-114.2,73.1,-114.7,72.7,-112.4,73,-111.1,72.5,-109.9,73,-109,72.6,-108.2,71.7,-107.7,72.1,-108.4,73.1,-107.5,73.2,-106.5,73.1,-105.4,72.7,-104.8,71.7,-104.5,71,-102.8,70.5,-101,70,-101.1,69.6,-102.7,69.5,-102.1,69.1,-102.4,68.8,-104.2,68.9,-106,69.2,-107.1,69.1,-109,68.8,-112,68.6,-113.3,68.5,-113.9,69,-115.2,69.3,-116.1,69.2,-117.3,70,-116.7,70.1,-115.1,70.2,-113.7,70.2,-112.4,70.4,-114.3,70.6,-116.5,70.5,-117.9,70.5,-118.4,70.9,-116.1,71.3,-117.7,71.3,-119.4,71.6,-118.6,72.3,-117.9,72.7,-115.2,73.3,-114.2,73.1],[-104.5,73.4,-105.4,72.8,-106.9,73.5,-106.6,73.6,-105.3,73.6,-104.5,73.4],[-76.3,73.1,-76.3,72.8,-77.3,72.9,-78.4,72.9,-79.5,72.7,-79.8,72.8,-80.9,73.3,-80.8,73.7,-80.4,73.8,-78.1,73.7,-76.3,73.1],[-86.6,73.2,-85.8,72.5,-84.9,73.3,-82.3,73.8,-80.6,72.7,-80.8,72.1,-78.8,72.4,-77.8,72.8,-75.6,72.2,-74.2,71.8,-74.1,71.3,-72.2,71.6,-71.2,70.9,-68.8,70.5,-67.9,70.1,-67,69.2,-68.8,68.7,-66.5,68.1,-64.9,67.8,-63.4,66.9,-61.9,66.9,-62.2,66.2,-63.9,65,-65.1,65.4,-66.7,66.4,-68,66.3,-68.1,65.7,-67.1,65.1,-65.7,64.6,-65.3,64.4,-64.7,63.4,-65,62.7,-66.3,62.9,-68.8,63.7,-67.4,62.9,-66.3,62.3,-66.2,61.9,-68.9,62.3,-71,62.9,-72.2,63.4,-71.9,63.7,-73.4,64.2,-74.8,64.7,-74.8,64.4,-77.7,64.2,-78.6,64.6,-77.9,65.3,-76,65.3,-74,65.5,-74.3,65.8,-73.9,66.3,-72.7,67.3,-72.9,67.7,-73.3,68.1,-74.8,68.6,-76.9,68.9,-76.2,69.1,-77.3,69.8,-78.2,69.8,-79,70.2,-79.5,69.9,-81.3,69.7,-84.9,70,-87.1,70.3,-88.7,70.4,-89.5,70.8,-88.5,71.2,-89.9,71.2,-90.2,72.2,-89.4,73.1,-88.4,73.5,-85.8,73.8,-86.6,73.2],[-100.4,73.8,-99.2,73.6,-97.4,73.8,-97.1,73.5,-98.1,73,-96.5,72.6,-96.7,71.7,-98.4,71.3,-99.3,71.4,-100,71.7,-102.5,72.5,-102.5,72.8,-100.4,72.7,-101.5,73.4,-100.4,73.8],[143.6,73.2,142.1,73.2,140,73.3,139.9,73.4,140.8,73.8,142.1,73.9,143.5,73.5,143.6,73.2],[-93.2,72.8,-94.3,72,-95.4,72.1,-96,72.9,-96,73.4,-95.5,73.9,-94.5,74.1,-92.4,74.1,-90.5,73.9,-92,73,-93.2,72.8],[-120.5,71.4,-123.1,70.9,-123.6,71.3,-125.9,71.9,-125.6,72.2,-124.8,73,-123.9,73.7,-124.9,74.3,-121.5,74.4,-120.1,74.2,-117.6,74.2,-116.6,73.9,-115.5,73.5,-116.8,73.2,-119.2,72.5,-120.5,71.8,-120.5,71.4],[150.7,75.1,149.6,74.7,148,74.8,146.1,75.2,146.4,75.5,148.2,75.3,150.7,75.1],[-93.6,75,-94.2,74.6,-95.6,74.7,-96.8,74.9,-96.3,75.4,-94.9,75.6,-94,75.3,-93.6,75],[145.1,75.6,144.3,74.8,140.6,74.8,139,74.6,137,75.3,137.5,75.9,138.8,76.1,141.5,76.1,145.1,75.6],[-98.5,76.7,-97.7,76.3,-97.7,75.7,-98.2,75,-99.8,74.9,-100.9,75.1,-100.9,75.6,-102.5,75.6,-102.6,76.3,-101.5,76.3,-100,76.6,-98.6,76.6,-98.5,76.7],[-108.2,76.2,-107.8,75.8,-106.9,76,-105.9,76,-105.7,75.5,-106.3,75,-109.7,74.9,-112.2,74.4,-113.7,74.4,-113.9,74.7,-111.8,75.2,-116.3,75,-117.7,75.2,-116.3,76.2,-115.4,76.5,-112.6,76.1,-110.8,75.5,-109.1,75.5,-110.5,76.4,-109.6,76.8,-108.6,76.7,-108.2,76.2],[57.5,70.7,56.9,70.6,53.7,70.8,53.4,71.2,51.6,71.5,51.5,72,52.5,72.2,52.4,72.8,54.4,73.6,53.5,73.8,55.9,74.6,55.6,75.1,57.9,75.6,61.2,76.3,64.5,76.4,66.2,76.8,68.2,76.9,68.9,76.5,68.2,76.2,64.6,75.7,61.6,75.3,58.5,74.3,57,73.3,55.4,72.4,55.6,71.5,57.5,70.7],[-94.7,77.1,-93.6,76.8,-91.6,76.8,-90.7,76.5,-91,76.1,-89.8,75.8,-89.2,75.6,-87.8,75.6,-86.4,75.5,-84.8,75.7,-82.8,75.8,-81.1,75.7,-80.1,75.3,-79.8,74.9,-80.5,74.7,-81.9,74.4,-83.2,74.6,-86.1,74.4,-88.1,74.4,-89.8,74.5,-92.4,74.8,-92.8,75.4,-92.9,75.9,-93.9,76.3,-96,76.4,-97.1,76.8,-96.7,77.2,-94.7,77.1],[-116.2,77.6,-116.3,76.9,-117.1,76.5,-118,76.5,-119.9,76.1,-121.5,75.9,-122.9,76.1,-121.2,76.9,-119.1,77.5,-117.6,77.5,-116.2,77.6],[-93.8,77.5,-94.3,77.5,-96.2,77.6,-96.4,77.8,-94.4,77.8,-93.7,77.6,-93.8,77.5],[-110.2,77.7,-112.1,77.4,-113.5,77.7,-112.7,78.1,-111.3,78.2,-109.9,78,-110.2,77.7],[24.7,77.9,22.5,77.4,20.7,77.7,21.4,77.9,20.8,78.3,22.9,78.5,23.3,78.1,24.7,77.9],[-109.7,78.6,-110.9,78.4,-112.5,78.4,-112.5,78.6,-111.5,78.9,-111,78.8,-109.7,78.6],[-95.8,78.1,-97.3,77.8,-98.1,78.1,-98.6,78.5,-98.6,78.9,-97.3,78.8,-96.8,78.8,-95.6,78.4,-95.8,78.1],[-100.1,78.3,-99.7,77.9,-101.3,78,-102.9,78.3,-105.2,78.4,-104.2,78.7,-105.4,78.9,-105.5,79.3,-103.5,79.2,-100.8,78.8,-100.1,78.3],[105.1,78.3,99.4,77.9,101.3,79.2,102.1,79.3,102.8,79.3,105.4,78.7,105.1,78.3],[18.3,79.7,21.5,79,19,78.6,18.5,77.8,17.6,77.6,17.1,76.8,15.9,76.8,13.8,77.4,14.7,77.7,13.2,78,11.2,78.9,10.4,79.7,13.2,80,13.7,79.7,15.1,79.7,15.5,80,17,80.1,18.3,79.7],[25.4,80.4,27.4,80.1,25.9,79.5,23,79.4,20.1,79.6,19.9,79.8,18.5,79.9,17.4,80.3,20.5,80.6,21.9,80.4,22.9,80.7,25.4,80.4],[51.1,80.5,49.8,80.4,48.9,80.3,48.8,80.2,47.6,80,46.5,80.2,47.1,80.6,44.8,80.6,46.8,80.8,48.3,80.8,48.5,80.5,49.1,80.8,50,80.9,51.5,80.7,51.1,80.5],[99.9,78.9,97.8,78.8,95,79,93.3,79.4,92.5,80.1,91.2,80.3,93.8,81,95.9,81.3,97.9,80.7,100.2,79.8,99.9,78.9],[-87,79.7,-85.8,79.3,-87.2,79,-89,78.3,-90.8,78.2,-92.9,78.3,-94,78.8,-93.9,79.1,-93.1,79.4,-95,79.4,-96.1,79.7,-96.7,80.2,-96,80.6,-95.3,80.9,-94.3,81,-94.7,81.2,-92.4,81.3,-91.1,80.7,-89.4,80.5,-87.8,80.3,-87,79.7],[-68.5,83.1,-65.8,83,-63.7,82.9,-61.9,82.6,-61.9,82.4,-64.3,81.9,-66.8,81.7,-67.7,81.5,-65.5,81.5,-67.8,80.9,-69.5,80.6,-71.2,79.8,-73.2,79.6,-73.9,79.4,-76.9,79.3,-75.5,79.2,-76.2,79,-75.4,78.5,-76.3,78.2,-77.9,77.9,-78.4,77.5,-79.8,77.2,-79.6,77,-77.9,77,-77.9,76.8,-80.6,76.2,-83.2,76.5,-86.1,76.3,-87.6,76.4,-89.5,76.5,-89.6,77,-87.8,77.2,-88.3,77.9,-87.6,78,-85,77.5,-86.3,78.2,-88,78.4,-87.2,78.8,-85.4,79,-85.1,79.3,-86.5,79.7,-86.9,80.3,-84.2,80.2,-83.4,80.1,-81.8,80.5,-84.1,80.6,-87.6,80.5,-89.4,80.9,-90.2,81.3,-91.4,81.6,-91.6,81.9,-90.1,82.1,-88.9,82.1,-87,82.3,-85.5,82.7,-84.3,82.6,-83.2,82.3,-82.4,82.9,-81.1,83,-79.3,83.1,-76.3,83.2,-75.7,83.1,-72.8,83.2,-70.7,83.2,-68.5,83.1],[-27.1,83.5,-20.8,82.7,-22.7,82.3,-26.5,82.3,-31.9,82.2,-31.4,82,-27.9,82.1,-24.8,81.8,-22.9,82.1,-22.1,81.7,-23.2,81.2,-20.6,81.5,-15.8,81.9,-12.8,81.7,-12.2,81.3,-16.3,80.6,-16.8,80.3,-20,80.2,-17.7,80.1,-18.9,79.4,-19.7,78.8,-19.7,77.6,-18.5,77,-20,76.9,-21.7,76.6,-19.8,76.1,-19.6,75.2,-20.7,75.2,-19.4,74.3,-21.6,74.2,-20.4,73.8,-20.8,73.5,-22.2,73.3,-23.6,73.3,-22.3,72.6,-22.3,72.2,-24.3,72.6,-24.8,72.3,-23.4,72.1,-22.1,71.5,-21.8,70.7,-23.5,70.5,-24.3,70.9,-25.5,71.4,-25.2,70.8,-26.4,70.2,-23.7,70.2,-22.3,70.1,-25,69.3,-27.7,68.5,-30.7,68.1,-31.8,68.1,-32.8,67.7,-34.2,66.7,-36.4,66,-37,65.9,-38.4,65.7,-39.8,65.5,-40.7,64.8,-40.7,64.1,-41.2,63.5,-42.8,62.7,-42.4,61.9,-42.9,61.1,-43.4,60.1,-44.8,60,-46.3,60.9,-48.3,60.9,-49.2,61.4,-49.9,62.4,-51.6,63.6,-52.1,64.3,-52.3,65.2,-53.7,66.1,-53.3,66.8,-54,67.2,-53,68.4,-51.5,68.7,-51.1,69.1,-50.9,69.9,-52,69.6,-52.6,69.4,-53.5,69.3,-54.7,69.6,-54.8,70.3,-54.4,70.8,-53.4,70.8,-51.4,70.6,-53.1,71.2,-54,71.5,-55,71.4,-55.8,71.7,-54.7,72.6,-55.3,73,-56.1,73.7,-57.3,74.7,-58.6,75.1,-58.6,75.5,-61.3,76.1,-63.4,76.2,-66.1,76.1,-68.5,76.1,-69.7,76.4,-71.4,77,-68.8,77.3,-66.8,77.4,-71,77.6,-73.3,78,-73.2,78.4,-69.4,78.9,-65.7,79.4,-65.3,79.8,-68,80.1,-67.1,80.5,-63.7,81.2,-62.2,81.3,-62.6,81.8,-60.3,82,-57.2,82.2,-54.1,82.2,-53,81.9,-50.4,82.4,-48,82.1,-46.6,82,-44.5,81.7,-46.9,82.2,-46.8,82.6,-43.4,83.2,-39.9,83.2,-38.6,83.5,-35.1,83.6,-27.1,83.5]]}*
���� 9599f22a5ea76329492447b1ad3bae33
��
data/earth_grid.json��{"note":"DEMO DATA - criterion values are fabricated placeholders (0-1). Replace with real data.","step_deg":2.5,"columns":["lat","lon","geology","topography","aeolian","caves","temperature","uv","aridity","ice","salts","periglacial"],"points":[[-78.75,-161.25,0.34,0.43,0.08,0.02,0.95,0.38,0.45,0.89,0.25,0.86],[-78.75,-148.75,0.35,0.41,0.08,0.02,0.94,0.38,0.45,0.89,0.25,0.8],[-78.75,-136.25,0.34,0.44,0.08,0.02,0.95,0.39,0.45,0.9,0.25,0.77],[-78.75,-123.75,0.35,0.45,0.08,0.02,0.95,0.39,0.45,0.91,0.25,0.75],[-78.75,-111.25,0.35,0.45,0.08,0.02,0.95,0.39,0.45,0.91,0.25,0.73],[-78.75,-98.75,0.35,0.45,0.08,0.02,0.95,0.39,0.45,0.91,0.25,0.71],[-78.75,-86.25,0.34,0.46,0.08,0.02,0.95,0.39,0.45,0.91,0.25,0.73],[-78.75,-48.75,0.37,0.59,0.08,0.02,0.97,0.42,0.45,0.92,0.25,0.76],[-78.75,-23.75,0.36,0.65,0.08,0.02,0.97,0.43,0.45,0.92,0.25,0.77],[-78.75,-11.25,0.35,0.64,0.08,0.02,0.97,0.43,0.45,0.92,0.25,0.77],[-78.75,1.25,0.36,0.63,0.08,0.02,0.97,0.43,0.45,0.91,0.25,0.78],[-78.75,13.75,0.35,0.66,0.08,0.02,0.97,0.43,0.45,0.91,0.25,0.8],[-78.75,26.25,0.35,0.66,0.08,0.02,0.97,0.43,0.45,0.91,0.25,0.8],[-78.75,38.75,0.35,0.6,0.08,0.02,0.97,0.42,0.45,0.9,0.25,0.8],[-78.75,51.25,0.35,0.48,0.08,0.02,0.95,0.4,0.45,0.87,0.25,0.79],[-78.75,63.75,0.35,0.38,0.08,0.02,0.94,0.37,0.45,0.84,0.25,0.74],[-78.75,76.25,0.34,0.34,0.08,0.02,0.94,0.36,0.45,0.83,0.25,0.7],[-78.75,88.75,0.34,0.3,0.08,0.02,0.93,0.35,0.45,0.82,0.25,0.7],[-78.75,101.25,0.35,0.29,0.08,0.02,0.93,0.35,0.45,0.82,0.25,0.69],[-78.75,113.75,0.35,0.28,0.08,0.02,0.93,0.34,0.45,0.82,0.25,0.71],[-78.75,126.25,0.35,0.29,0.08,0.02,0.93,0.34,0.45,0.83,0.25,0.73],[-78.75,138.75,0.34,0.31,0.08,0.02,0.93,0.35,0.45,0.86,0.25,0.75],[-78.75,151.25,0.34,0.35,0.08,0.02,0.94,0.36,0.45,0.88,0.25,0.8],[-78.75,163.75,0.33,0.41,0.08,0.02,0.94,0.38,0.45,0.88,0.25,0.85],[-76.25,-143.19,0.35,0.45,0.08,0.02,0.94,0.41,0.44,0.88,0.25,0.78],[-76.25,-132.67,0.34,0.48,0.08,0.02,0.94,0.41,0.44,0.89,0.25,0.77],[-76.25,-122.15,0.35,0.48,0.08,0.02,0.94,0.41,0.44,0.9,0.25,0.75],[-76.25,-111.63,0.35,0.5,0.08,0.02,0.94,0.42,0.44,0.9,0.25,0.72],[-76.25,-101.11,0.35,0.49,0.08,0.02,0.94,0.42,0.44,0.9,0.25,0.71],[-76.25,-90.6,0.34,0.5,0.08,0.02,0.94,0.42,0.44,0.89,0.25,0.69],[-76.25,-80.08,0.35,0.51,0.08,0.02,0.95,0.42,0.44,0.9,0.25,0.7],[-76.25,-16.97,0.35,0.72,0.08,0.02,0.97,0.47,0.44,0.92,0.25,0.73],[-76.25,-6.45,0.35,0.67,0.08,0.02,0.96,0.45,0.44,0.91,0.25,0.78],[-76.25,4.07,0.35,0.65,0.08,0.02,0.96,0.45,0.44,0.9,0.25,0.78],[-76.25,14.58,0.35,0.69,0.08,0.02,0.96,0.46,0.44,0.91,0.25,0.77],[-76.25,25.1,0.35,0.67,0.08,0.02,0.96,0.46,0.44,0.91,0.25,0.76],[-76.25,35.62,0.35,0.61,0.08,0.02,0.96,0.44,0.44,0.89,0.25,0.79],[-76.25,46.14,0.35,0.58,0.08,0.02,0.95,0.44,0.44,0.88,0.25,0.77],[-76.25,56.66,0.35,0.47,0.08,0.02,0.94,0.41,0.44,0.84,0.25,0.76],[-76.25,67.17,0.35,0.36,0.08,0.02,0.93,0.39,0.44,0.81,0.25,0.73],[-76.25,77.69,0.35,0.31,0.08,0.02,0.92,0.37,0.44,0.79,0.25,0.67],[-76.25,88.21,0.34,0.27,0.08,0.02,0.91,0.36,0.44,0.78,0.25,0.65],[-76.25,98.73,0.34,0.27,0.08,0.02,0.91,0.36,0.44,0.78,0.25,0.65],[-76.25,109.25,0.35,0.27,0.08,0.02,0.91,0.36,0.44,0.79,0.25,0.7],[-76.25,119.77,0.35,0.27,0.08,0.02,0.91,0.36,0.44,0.8,0.25,0.73],[-76.25,130.28,0.35,0.28,0.08,0.02,0.92,0.36,0.44,0.81,0.25,0.74],[-76.25,140.8,0.34,0.29,0.08,0.02,0.92,0.37,0.44,0.83,0.25,0.76],[-76.25,151.32,0.34,0.33,0.08,0.02,0.92,0.38,0.44,0.85,0.25,0.78],[-76.25,161.84,0.34,0.36,0.08,0.02,0.93,0.38,0.44,0.86,0.25,0.81],[-73.75,-121.93,0.4,0.53,0.08,0.08,0.9,0.45,0.42,0.85,0.23,0.71],[-73.75,-95.13,0.35,0.53,0.08,0.02,0.9,0.45,0.42,0.83,0.23,0.65],[-73.75,-86.19,0.35,0.52,0.08,0.02,0.89,0.45,0.42,0.83,0.23,0.64],[-73.75,-77.26,0.35,0.54,0.08,0.02,0.9,0.45,0.42,0.84,0.23,0.65],[-73.75,-68.32,0.35,0.56,0.08,0.02,0.9,0.46,0.42,0.85,0.23,0.66],[-73.75,-14.72,0.35,0.74,0.08,0.02,0.92,0.5,0.42,0.86,0.23,0.67],[-73.75,-5.79,0.35,0.69,0.08,0.02,0.91,0.49,0.42,0.85,0.23,0.71],[-73.75,3.15,0.34,0.69,0.08,0.02,0.91,0.49,0.42,0.85,0.23,0.72],[-73.75,12.08,0.36,0.7,0.08,0.02,0.91,0.49,0.42,0.85,0.23,0.71],[-73.75,21.02,0.35,0.67,0.08,0.02,0.91,0.48,0.42,0.85,0.23,0.69],[-73.75,29.95,0.36,0.56,0.08,0.02,0.9,0.46,0.42,0.83,0.23,0.7],[-73.75,38.88,0.35,0.58,0.08,0.02,0.9,0.46,0.42,0.83,0.23,0.71],[-73.75,47.82,0.35,0.57,0.08,0.02,0.9,0.46,0.42,0.83,0.23,0.7],[-73.75,56.75,0.36,0.46,0.08,0.02,0.89,0.44,0.42,0.79,0.23,0.7],[-73.75,65.69,0.36,0.37,0.08,0.02,0.88,0.41,0.42,0.75,0.23,0.69],[-73.75,74.62,0.35,0.3,0.08,0.02,0.87,0.39,0.42,0.72,0.23,0.65],[-73.75,83.55,0.35,0.27,0.08,0.02,0.86,0.39,0.42,0.71,0.23,0.61],[-73.75,92.49,0.36,0.27,0.08,0.02,0.86,0.39,0.42,0.72,0.23,0.61],[-73.75,101.42,0.35,0.28,0.08,0.02,0.86,0.39,0.42,0.72,0.23,0.63],[-73.75,110.36,0.35,0.28,0.08,0.02,0.86,0.39,0.42,0.73,0.23,0.65],[-73.75,119.29,0.35,0.27,0.08,0.02,0.86,0.39,0.42,0.74,0.23,0.66],[-73.75,128.22,0.34,0.29,0.08,0.02,0.87,0.39,0.42,0.77,0.23,0.67],[-73.75,137.16,0.34,0.28,0.08,0.02,0.87,0.39,0.42,0.77,0.23,0.68],[-73.75,146.09,0.34,0.3,0.08,0.02,0.87,0.4,0.42,0.79,0.23,0.69],[-73.75,155.03,0.34,0.31,0.08,0.02,0.87,0.4,0.42,0.78,0.23,0.7],[-73.75,163.96,0.34,0.35,0.08,0.02,0.87,0.41,0.42,0.79,0.23,0.75],[-71.25,-67.23,0.37,0.54,0.08,0.03,0.81,0.49,0.38,0.75,0.21,0.56],[-71.25,2.77,0.34,0.76,0.08,0.02,0.84,0.53,0.38,0.77,0.21,0.63],[-71.25,10.55,0.35,0.73,0.08,0.02,0.83,0.52,0.38,0.77,0.21,0.62],[-71.25,18.33,0.35,0.68,0.08,0.02,0.83,0.51,0.38,0.77,0.21,0.6],[-71.25,26.1,0.36,0.61,0.08,0.02,0.82,0.5,0.38,0.75,0.21,0.6],[-71.25,33.88,0.36,0.54,0.08,0.02,0.81,0.49,0.38,0.74,0.21,0.62],[-71.25,41.66,0.38,0.56,0.08,0.04,0.82,0.49,0.38,0.74,0.21,0.62],[-71.25,49.44,0.36,0.55,0.08,0.02,0.82,0.49,0.38,0.73,0.21,0.61],[-71.25,57.21,0.36,0.45,0.08,0.02,0.8,0.46,0.38,0.7,0.21,0.61],[-71.25,64.99,0.36,0.37,0.08,0.02,0.79,0.45,0.38,0.67,0.21,0.61],[-71.25,72.77,0.36,0.31,0.08,0.02,0.79,0.43,0.38,0.64,0.21,0.59],[-71.25,80.55,0.35,0.29,0.08,0.02,0.78,0.42,0.38,0.63,0.21,0.57],[-71.25,88.32,0.35,0.26,0.08,0.02,0.78,0.41,0.38,0.61,0.21,0.56],[-71.25,96.1,0.36,0.29,0.08,0.02,0.78,0.42,0.38,0.62,0.21,0.56],[-71.25,103.88,0.35,0.32,0.08,0.02,0.79,0.43,0.38,0.63,0.21,0.57],[-71.25,111.66,0.35,0.31,0.08,0.02,0.79,0.43,0.38,0.65,0.21,0.56],[-71.25,119.43,0.35,0.28,0.08,0.02,0.78,0.42,0.38,0.65,0.21,0.57],[-71.25,127.21,0.34,0.32,0.08,0.02,0.79,0.43,0.38,0.68,0.21,0.58],[-71.25,134.99,0.34,0.31,0.08,0.02,0.79,0.43,0.38,0.69,0.21,0.59],[-71.25,142.77,0.33,0.31,0.08,0.02,0.79,0.43,0.38,0.68,0.21,0.58],[-71.25,150.54,0.34,0.31,0.08,0.02,0.79,0.43,0.38,0.68,0.21,0.59],[-71.25,158.32,0.35,0.34,0.08,0.02,0.79,0.44,0.38,0.68,0.21,0.6],[-71.25,166.1,0.34,0.36,0.08,0.02,0.79,0.44,0.38,0.69,0.21,0.63],[-68.75,-66.19,0.36,0.51,0.08,0.02,0.71,0.51,0.33,0.62,0.18,0.46],[-68.75,44.18,0.43,0.55,0.08,0.08,0.71,0.52,0.33,0.62,0.18,0.51],[-68.75,51.07,0.37,0.52,0.08,0.02,0.71,0.51,0.33,0.61,0.18,0.51],[-68.75,57.97,0.37,0.46,0.08,0.02,0.7,0.5,0.33,0.59,0.18,0.51],[-68.75,64.87,0.36,0.4,0.08,0.02,0.7,0.49,0.33,0.57,0.18,0.5],[-68.75,78.66,0.34,0.3,0.08,0.02,0.68,0.46,0.33,0.52,0.18,0.48],[-68.75,85.56,0.34,0.27,0.08,0.02,0.68,0.45,0.33,0.5,0.18,0.47],[-68.75,92.46,0.35,0.26,0.08,0.02,0.68,0.45,0.33,0.5,0.18,0.47],[-68.75,99.36,0.35,0.31,0.08,0.02,0.68,0.46,0.33,0.51,0.18,0.47],[-68.75,106.26,0.35,0.34,0.08,0.02,0.69,0.47,0.33,0.53,0.18,0.45],[-68.75,113.15,0.35,0.32,0.08,0.02,0.68,0.47,0.33,0.54,0.18,0.46],[-68.75,120.05,0.36,0.31,0.08,0.02,0.68,0.46,0.33,0.55,0.18,0.47],[-68.75,126.95,0.36,0.34,0.08,0.02,0.69,0.47,0.33,0.57,0.18,0.47],[-68.75,133.85,0.35,0.34,0.08,0.02,0.69,0.47,0.33,0.57,0.18,0.48],[-68.75,140.74,0.34,0.34,0.08,0.02,0.69,0.47,0.33,0.56,0.18,0.47],[-68.75,147.64,0.34,0.32,0.08,0.02,0.68,0.47,0.33,0.56,0.18,0.47],[-68.75,154.54,0.34,0.32,0.08,0.02,0.68,0.47,0.33,0.55,0.18,0.47],[-66.25,-65.16,0.36,0.5,0.08,0.02,0.59,0.54,0.27,0.49,0.15,0.36],[-66.25,52.78,0.37,0.5,0.08,0.02,0.59,0.54,0.27,0.48,0.15,0.38],[-66.25,102.44,0.35,0.31,0.08,0.02,0.57,0.49,0.27,0.4,0.15,0.36],[-63.75,-58.47,0.36,0.48,0.08,0.02,0.48,0.57,0.21,0.36,0.11,0.26],[-53.75,-67.96,0.37,0.56,0.08,0.02,0.26,0.69,0.1,0.09,0.05,0.03],[-51.25,-74.16,0.37,0.53,0.08,0.02,0.26,0.7,0.1,0.07,0.05,0.03],[-51.25,-70.16,0.37,0.58,0.08,0.02,0.26,0.71,0.1,0.08,0.05,0.03],[-48.75,-71.94,0.35,0.59,0.08,0.02,0.27,0.73,0.1,0.06,0.05,0.03],[-48.75,-68.15,0.35,0.58,0.08,0.02,0.26,0.72,0.1,0.06,0.05,0.03],[-46.25,-73.35,0.34,0.62,0.08,0.02,0.27,0.75,0.1,0.04,0.05,0.03],[-46.25,-69.73,0.34,0.62,0.08,0.02,0.27,0.75,0.1,0.04,0.05,0.03],[-46.25,168.87,0.35,0.61,0.08,0.02,0.27,0.74,0.1,0.04,0.05,0.03],[-43.75,-70.98,0.34,0.66,0.09,0.02,0.27,0.77,0.11,0.03,0.06,0.03],[-43.75,-67.52,0.34,0.63,0.09,0.02,0.27,0.76,0.11,0.03,0.06,0.03],[-43.75,171.28,0.35,0.58,0.08,0.02,0.27,0.75,0.11,0.03,0.05,0.03],[-41.25,-71.93,0.34,0.61,0.1,0.02,0.27,0.77,0.12,0.02,0.07,0.03],[-41.25,-68.61,0.35,0.61,0.1,0.02,0.27,0.77,0.12,0.02,0.07,0.03],[-41.25,-65.28,0.35,0.58,0.1,0.02,0.27,0.77,0.12,0.02,0.07,0.03],[-41.25,147.53,0.35,0.5,0.08,0.02,0.26,0.75,0.12,0.02,0.06,0.03],[-41.25,174.13,0.35,0.58,0.08,0.02,0.27,0.77,0.12,0.02,0.06,0.03],[-38.75,-72.61,0.35,0.54,0.12,0.02,0.27,0.77,0.16,0.02,0.09,0.03],[-38.75,-69.41,0.36,0.56,0.13,0.02,0.28,0.78,0.16,0.02,0.1,0.03],[-38.75,-66.2,0.37,0.57,0.13,0.02,0.28,0.78,0.16,0.02,0.1,0.03],[-38.75,-63,0.39,0.58,0.12,0.03,0.28,0.78,0.16,0.02,0.1,0.03],[-38.75,-59.79,0.38,0.55,0.1,0.03,0.28,0.77,0.16,0.02,0.1,0.03],[-38.75,177.42,0.35,0.58,0.09,0.02,0.28,0.78,0.16,0.02,0.09,0.03],[-36.25,-69.95,0.39,0.54,0.17,0.02,0.29,0.78,0.23,0.02,0.13,0.03],[-36.25,-66.85,0.44,0.55,0.17,0.05,0.29,0.79,0.23,0.02,0.14,0.03],[-36.25,-63.75,0.51,0.56,0.15,0.18,0.29,0.79,0.23,0.02,0.15,0.03],[-36.25,-60.65,0.44,0.57,0.12,0.06,0.29,0.79,0.23,0.02,0.14,0.03],[-36.25,-57.55,0.41,0.57,0.13,0.03,0.29,0.79,0.23,0.02,0.13,0.03],[-36.25,140.85,0.38,0.46,0.1,0.02,0.28,0.76,0.23,0.02,0.12,0.03],[-36.25,143.95,0.39,0.42,0.12,0.02,0.28,0.76,0.23,0.02,0.11,0.03],[-36.25,147.05,0.39,0.43,0.14,0.02,0.28,0.76,0.23,0.02,0.1,0.03],[-33.75,-70.25,0.43,0.48,0.24,0.02,0.31,0.78,0.35,0.02,0.19,0.03],[-33.75,-67.25,0.43,0.49,0.22,0.02,0.31,0.78,0.35,0.02,0.2,0.03],[-33.75,-64.24,0.45,0.52,0.25,0.03,0.32,0.79,0.35,0.02,0.21,0.03],[-33.75,-61.23,0.47,0.52,0.22,0.06,0.32,0.79,0.35,0.02,0.21,0.03],[-33.75,-58.23,0.47,0.55,0.17,0.07,0.32,0.8,0.34,0.02,0.2,0.03],[-33.75,-55.22,0.57,0.57,0.16,0.33,0.32,0.8,0.34,0.02,0.19,0.03],[-33.75,19.95,0.38,0.38,0.4,0.02,0.3,0.76,0.33,0.02,0.14,0.03],[-33.75,22.95,0.39,0.38,0.41,0.02,0.3,0.76,0.33,0.02,0.14,0.03],[-33.75,116.16,0.42,0.42,0.18,0.02,0.3,0.77,0.36,0.02,0.16,0.03],[-33.75,119.17,0.41,0.39,0.21,0.02,0.3,0.76,0.36,0.02,0.17,0.03],[-33.75,122.18,0.39,0.35,0.27,0.02,0.3,0.75,0.36,0.02,0.19,0.03],[-33.75,140.22,0.41,0.51,0.19,0.02,0.32,0.79,0.35,0.02,0.17,0.03],[-33.75,143.22,0.41,0.5,0.19,0.02,0.31,0.78,0.34,0.02,0.16,0.03],[-33.75,146.23,0.42,0.47,0.28,0.02,0.31,0.78,0.34,0.02,0.15,0.03],[-33.75,149.24,0.42,0.46,0.29,0.02,0.31,0.78,0.34,0.02,0.13,0.03],[-31.25,-70.34,0.49,0.46,0.42,0.02,0.34,0.79,0.49,0.02,0.26,0.03],[-31.25,-67.42,0.49,0.44,0.37,0.02,0.34,0.78,0.5,0.02,0.25,0.03],[-31.25,-64.49,0.49,0.46,0.32,0.02,0.34,0.79,0.5,0.02,0.26,0.03],[-31.25,-61.57,0.49,0.48,0.33,0.02,0.35,0.79,0.49,0.02,0.27,0.03],[-31.25,-58.64,0.51,0.53,0.25,0.06,0.35,0.8,0.5,0.02,0.27,0.03],[-31.25,-55.72,0.49,0.59,0.24,0.04,0.36,0.81,0.49,0.02,0.27,0.03],[-31.25,-52.79,0.53,0.6,0.27,0.15,0.36,0.82,0.49,0.02,0.25,0.03],[-31.25,20.31,0.41,0.44,0.6,0.02,0.34,0.78,0.47,0.02,0.19,0.03],[-31.25,23.24,0.41,0.48,0.6,0.02,0.35,0.79,0.46,0.02,0.19,0.03],[-31.25,26.16,0.42,0.45,0.6,0.02,0.34,0.78,0.46,0.02,0.2,0.03],[-31.25,29.09,0.43,0.44,0.6,0.02,0.34,0.78,0.47,0.02,0.21,0.03],[-31.25,116.81,0.42,0.43,0.24,0.02,0.34,0.78,0.51,0.02,0.24,0.03],[-31.25,119.74,0.42,0.38,0.24,0.02,0.33,0.77,0.51,0.02,0.26,0.03],[-31.25,122.66,0.42,0.34,0.27,0.02,0.33,0.76,0.51,0.02,0.27,0.03],[-31.25,125.59,0.43,0.35,0.32,0.02,0.33,0.76,0.52,0.02,0.28,0.03],[-31.25,128.51,0.43,0.39,0.34,0.02,0.33,0.77,0.52,0.02,0.28,0.03],[-31.25,131.44,0.43,0.44,0.33,0.02,0.34,0.78,0.51,0.02,0.25,0.03],[-31.25,134.36,0.44,0.49,0.32,0.02,0.35,0.79,0.5,0.02,0.22,0.03],[-31.25,137.28,0.44,0.51,0.33,0.02,0.35,0.8,0.5,0.02,0.19,0.03],[-31.25,140.21,0.46,0.56,0.36,0.02,0.35,0.81,0.49,0.02,0.2,0.03],[-31.25,143.13,0.45,0.58,0.34,0.02,0.36,0.81,0.48,0.02,0.22,0.03],[-31.25,146.06,0.45,0.5,0.36,0.02,0.35,0.8,0.48,0.02,0.21,0.03],[-31.25,148.98,0.44,0.44,0.41,0.02,0.34,0.78,0.47,0.02,0.17,0.03],[-31.25,151.91,0.43,0.4,0.42,0.02,0.34,0.77,0.46,0.02,0.16,0.03],[-28.75,-70.22,0.56,0.46,0.56,0.02,0.38,0.8,0.65,0.02,0.3,0.03],[-28.75,-67.37,0.56,0.46,0.54,0.02,0.38,0.8,0.65,0.02,0.28,0.03],[-28.75,-64.51,0.55,0.45,0.45,0.02,0.38,0.79,0.65,0.02,0.31,0.03],[-28.75,-61.66,0.54,0.45,0.46,0.02,0.38,0.79,0.65,0.02,0.32,0.03],[-28.75,-58.81,0.54,0.47,0.45,0.03,0.38,0.8,0.65,0.02,0.33,0.03],[-28.75,-55.96,0.51,0.51,0.45,0.02,0.38,0.81,0.65,0.02,0.33,0.03],[-28.75,-53.11,0.48,0.54,0.52,0.02,0.39,0.81,0.64,0.02,0.3,0.03],[-28.75,-50.26,0.48,0.53,0.54,0.02,0.38,0.81,0.63,0.02,0.26,0.03],[-28.75,18.18,0.47,0.43,0.79,0.02,0.37,0.79,0.62,0.02,0.24,0.03],[-28.75,21.03,0.46,0.49,0.79,0.02,0.38,0.8,0.61,0.02,0.2,0.03],[-28.75,23.88,0.45,0.5,0.79,0.02,0.38,0.8,0.6,0.02,0.22,0.03],[-28.75,26.73,0.46,0.46,0.79,0.02,0.38,0.8,0.59,0.02,0.24,0.03],[-28.75,29.59,0.46,0.43,0.79,0.02,0.37,0.79,0.6,0.02,0.25,0.03],[-28.75,115.13,0.44,0.49,0.44,0.02,0.38,0.8,0.66,0.02,0.33,0.03],[-28.75,117.98,0.43,0.42,0.42,0.02,0.37,0.79,0.67,0.02,0.33,0.03],[-28.75,120.83,0.43,0.36,0.43,0.02,0.36,0.77,0.66,0.02,0.34,0.03],[-28.75,123.69,0.46,0.36,0.45,0.02,0.36,0.77,0.66,0.02,0.34,0.03],[-28.75,126.54,0.46,0.4,0.42,0.02,0.37,0.78,0.66,0.02,0.34,0.03],[-28.75,129.39,0.47,0.45,0.47,0.02,0.38,0.79,0.67,0.02,0.33,0.03],[-28.75,132.24,0.47,0.49,0.5,0.02,0.38,0.8,0.66,0.02,0.28,0.03],[-28.75,135.09,0.49,0.53,0.48,0.02,0.39,0.81,0.65,0.02,0.23,0.03],[-28.75,137.94,0.5,0.54,0.48,0.02,0.39,0.82,0.64,0.02,0.21,0.03],[-28.75,140.8,0.51,0.56,0.52,0.02,0.39,0.82,0.64,0.02,0.23,0.03],[-28.75,143.65,0.49,0.55,0.48,0.02,0.39,0.82,0.62,0.02,0.26,0.03],[-28.75,146.5,0.48,0.47,0.43,0.02,0.38,0.8,0.6,0.02,0.26,0.03],[-28.75,149.35,0.46,0.42,0.44,0.02,0.37,0.79,0.59,0.02,0.22,0.03],[-28.75,152.2,0.44,0.4,0.42,0.02,0.37,0.78,0.59,0.02,0.23,0.03],[-26.25,-69.9,0.6,0.52,0.58,0.02,0.4,0.82,0.73,0.02,0.32,0.03],[-26.25,-67.11,0.6,0.53,0.71,0.02,0.41,0.82,0.74,0.02,0.33,0.03],[-26.25,-64.32,0.59,0.5,0.73,0.02,0.4,0.81,0.74,0.02,0.34,0.03],[-26.25,-61.53,0.58,0.45,0.75,0.02,0.4,0.8,0.74,0.02,0.36,0.03],[-26.25,-58.75,0.56,0.44,0.65,0.02,0.4,0.8,0.74,0.02,0.37,0.03],[-26.25,-55.96,0.55,0.45,0.58,0.02,0.4,0.8,0.74,0.02,0.34,0.03],[-26.25,-53.17,0.52,0.46,0.76,0.02,0.4,0.81,0.73,0.02,0.34,0.03],[-26.25,-50.38,0.48,0.45,0.87,0.02,0.4,0.8,0.72,0.02,0.28,0.03],[-26.25,16.52,0.5,0.44,0.91,0.02,0.4,0.8,0.72,0.02,0.26,0.03],[-26.25,19.3,0.5,0.48,0.91,0.02,0.4,0.81,0.7,0.02,0.23,0.03],[-26.25,22.09,0.49,0.5,0.91,0.02,0.4,0.82,0.68,0.02,0.21,0.03],[-26.25,24.88,0.48,0.46,0.91,0.02,0.4,0.81,0.67,0.02,0.26,0.03],[-26.25,27.67,0.47,0.42,0.91,0.02,0.39,0.8,0.67,0.02,0.29,0.03],[-26.25,30.45,0.47,0.44,0.91,0.02,0.4,0.8,0.68,0.02,0.31,0.03],[-26.25,114.08,0.45,0.47,0.63,0.02,0.4,0.81,0.76,0.02,0.44,0.03],[-26.25,116.86,0.44,0.44,0.68,0.02,0.4,0.8,0.77,0.02,0.41,0.03],[-26.25,119.65,0.43,0.4,0.68,0.02,0.39,0.79,0.77,0.02,0.39,0.03],[-26.25,122.44,0.46,0.41,0.59,0.02,0.39,0.79,0.76,0.02,0.38,0.03],[-26.25,125.23,0.48,0.43,0.51,0.02,0.39,0.8,0.76,0.02,0.37,0.03],[-26.25,128.01,0.48,0.47,0.56,0.02,0.4,0.81,0.75,0.02,0.35,0.03],[-26.25,130.8,0.49,0.55,0.52,0.02,0.41,0.82,0.75,0.02,0.3,0.03],[-26.25,133.59,0.5,0.58,0.57,0.02,0.41,0.83,0.75,0.02,0.25,0.03],[-26.25,136.38,0.52,0.56,0.66,0.02,0.41,0.83,0.74,0.02,0.22,0.03],[-26.25,139.16,0.53,0.53,0.73,0.02,0.41,0.82,0.73,0.02,0.2,0.03],[-26.25,141.95,0.53,0.55,0.5,0.02,0.41,0.83,0.72,0.02,0.23,0.03],[-26.25,144.74,0.5,0.52,0.41,0.02,0.4,0.82,0.7,0.02,0.26,0.03],[-26.25,147.53,0.48,0.47,0.38,0.02,0.4,0.81,0.68,0.02,0.29,0.03],[-26.25,150.31,0.45,0.46,0.43,0.02,0.4,0.8,0.66,0.02,0.32,0.03],[-26.25,153.1,0.42,0.45,0.25,0.02,0.4,0.8,0.66,0.02,0.3,0.03],[-23.75,-69.38,0.59,0.6,0.61,0.02,0.41,0.85,0.72,0.02,0.3,0.03],[-23.75,-66.65,0.61,0.59,0.69,0.02,0.41,0.84,0.73,0.02,0.31,0.03],[-23.75,-63.92,0.61,0.55,0.79,0.02,0.41,0.83,0.74,0.02,0.33,0.03],[-23.75,-61.19,0.59,0.5,0.71,0.02,0.4,0.82,0.73,0.02,0.35,0.03],[-23.75,-58.46,0.57,0.47,0.65,0.02,0.4,0.81,0.73,0.02,0.36,0.03],[-23.75,-55.73,0.55,0.43,0.76,0.02,0.39,0.81,0.73,0.02,0.35,0.03],[-23.75,-52.99,0.52,0.39,0.83,0.02,0.39,0.8,0.73,0.02,0.33,0.03],[-23.75,-50.26,0.5,0.38,0.91,0.02,0.39,0.79,0.72,0.02,0.29,0.03],[-23.75,-47.53,0.49,0.35,0.91,0.02,0.38,0.79,0.7,0.02,0.22,0.03],[-23.75,15.29,0.53,0.5,0.89,0.02,0.4,0.82,0.74,0.02,0.25,0.03],[-23.75,18.02,0.52,0.52,0.91,0.02,0.4,0.83,0.71,0.02,0.22,0.03],[-23.75,20.75,0.5,0.51,0.91,0.02,0.4,0.83,0.69,0.02,0.22,0.03],[-23.75,23.48,0.47,0.49,0.91,0.02,0.4,0.82,0.67,0.02,0.24,0.03],[-23.75,26.21,0.46,0.46,0.91,0.02,0.4,0.81,0.66,0.02,0.32,0.03],[-23.75,28.95,0.46,0.46,0.91,0.02,0.4,0.81,0.66,0.02,0.34,0.03],[-23.75,31.68,0.48,0.48,0.91,0.02,0.4,0.82,0.67,0.02,0.38,0.03],[-23.75,34.41,0.48,0.44,0.91,0.02,0.4,0.81,0.68,0.02,0.42,0.03],[-23.75,45.33,0.51,0.31,0.77,0.02,0.38,0.78,0.66,0.02,0.49,0.03],[-23.75,113.62,0.44,0.42,0.67,0.02,0.39,0.8,0.76,0.02,0.46,0.03],[-23.75,116.35,0.43,0.45,0.69,0.02,0.4,0.81,0.76,0.02,0.44,0.03],[-23.75,119.08,0.44,0.45,0.74,0.02,0.4,0.81,0.77,0.02,0.4,0.03],[-23.75,121.81,0.46,0.46,0.6,0.02,0.4,0.81,0.77,0.02,0.38,0.03],[-23.75,124.54,0.47,0.47,0.56,0.02,0.4,0.82,0.76,0.02,0.37,0.03],[-23.75,127.27,0.49,0.49,0.47,0.02,0.4,0.82,0.76,0.02,0.34,0.03],[-23.75,130,0.49,0.54,0.35,0.02,0.41,0.83,0.75,0.02,0.28,0.03],[-23.75,132.74,0.5,0.57,0.4,0.02,0.41,0.84,0.75,0.02,0.25,0.03],[-23.75,135.47,0.51,0.6,0.64,0.02,0.41,0.84,0.73,0.02,0.25,0.03],[-23.75,138.2,0.52,0.55,0.69,0.02,0.41,0.83,0.73,0.02,0.22,0.03],[-23.75,140.93,0.51,0.57,0.63,0.02,0.41,0.84,0.71,0.02,0.23,0.03],[-23.75,143.66,0.5,0.54,0.52,0.02,0.41,0.83,0.7,0.02,0.27,0.03],[-23.75,146.39,0.46,0.5,0.46,0.02,0.4,0.82,0.68,0.02,0.3,0.03],[-23.75,149.12,0.45,0.48,0.48,0.02,0.4,0.82,0.67,0.02,0.35,0.03],[-21.25,-68.68,0.56,0.63,0.53,0.02,0.4,0.86,0.62,0.02,0.27,0.03],[-21.25,-66,0.58,0.61,0.59,0.02,0.39,0.85,0.63,0.02,0.28,0.03],[-21.25,-63.32,0.59,0.56,0.67,0.02,0.39,0.84,0.63,0.02,0.3,0.03],[-21.25,-60.63,0.57,0.54,0.62,0.02,0.39,0.84,0.64,0.02,0.33,0.03],[-21.25,-57.95,0.55,0.51,0.59,0.02,0.38,0.83,0.63,0.02,0.32,0.03],[-21.25,-55.27,0.54,0.44,0.67,0.02,0.37,0.82,0.63,0.02,0.31,0.03],[-21.25,-52.59,0.52,0.39,0.77,0.02,0.37,0.8,0.62,0.02,0.26,0.03],[-21.25,-49.9,0.49,0.34,0.79,0.02,0.36,0.79,0.62,0.02,0.22,0.03],[-21.25,-47.22,0.47,0.33,0.77,0.02,0.36,0.79,0.63,0.02,0.21,0.03],[-21.25,-44.54,0.45,0.34,0.7,0.02,0.36,0.79,0.63,0.02,0.21,0.03],[-21.25,-41.86,0.45,0.35,0.57,0.02,0.36,0.79,0.62,0.02,0.2,0.03],[-21.25,14.47,0.52,0.54,0.7,0.02,0.39,0.84,0.65,0.02,0.19,0.03],[-21.25,17.15,0.51,0.52,0.77,0.02,0.38,0.83,0.63,0.02,0.19,0.03],[-21.25,19.84,0.48,0.5,0.79,0.02,0.38,0.83,0.6,0.02,0.19,0.03],[-21.25,22.52,0.45,0.47,0.79,0.02,0.38,0.82,0.59,0.02,0.19,0.03],[-21.25,25.2,0.44,0.48,0.79,0.02,0.38,0.83,0.58,0.02,0.24,0.03],[-21.25,27.88,0.44,0.5,0.79,0.02,0.38,0.83,0.57,0.02,0.29,0.03],[-21.25,30.57,0.45,0.5,0.79,0.02,0.38,0.83,0.57,0.02,0.36,0.03],[-21.25,33.25,0.47,0.5,0.79,0.02,0.38,0.83,0.58,0.02,0.4,0.03],[-21.25,43.98,0.5,0.34,0.71,0.02,0.36,0.79,0.57,0.02,0.44,0.03],[-21.25,46.66,0.5,0.33,0.62,0.02,0.36,0.79,0.57,0.02,0.43,0.03],[-21.25,116.4,0.44,0.5,0.54,0.02,0.38,0.83,0.66,0.02,0.38,0.03],[-21.25,119.09,0.45,0.53,0.51,0.02,0.38,0.84,0.67,0.02,0.36,0.03],[-21.25,121.77,0.46,0.53,0.52,0.02,0.38,0.84,0.67,0.02,0.36,0.03],[-21.25,124.45,0.46,0.53,0.45,0.02,0.38,0.84,0.66,0.02,0.33,0.03],[-21.25,127.13,0.47,0.54,0.37,0.02,0.39,0.84,0.66,0.02,0.28,0.03],[-21.25,129.81,0.48,0.56,0.27,0.02,0.39,0.84,0.65,0.02,0.26,0.03],[-21.25,132.5,0.48,0.58,0.31,0.02,0.39,0.85,0.63,0.02,0.25,0.03],[-21.25,135.18,0.49,0.62,0.5,0.02,0.39,0.86,0.62,0.02,0.23,0.03],[-21.25,137.86,0.48,0.59,0.47,0.02,0.39,0.85,0.62,0.02,0.24,0.03],[-21.25,140.54,0.47,0.57,0.47,0.02,0.39,0.84,0.62,0.02,0.23,0.03],[-21.25,143.23,0.46,0.57,0.47,0.02,0.39,0.85,0.6,0.02,0.26,0.03],[-21.25,145.91,0.45,0.56,0.52,0.02,0.39,0.84,0.59,0.02,0.3,0.03],[-21.25,148.59,0.44,0.54,0.54,0.02,0.39,0.84,0.58,0.02,0.34,0.03],[-18.75,-67.8,0.51,0.61,0.24,0.02,0.36,0.86,0.48,0.02,0.2,0.03],[-18.75,-65.16,0.52,0.6,0.35,0.02,0.36,0.86,0.49,0.02,0.22,0.03],[-18.75,-62.52,0.52,0.58,0.44,0.02,0.36,0.85,0.49,0.02,0.24,0.03],[-18.75,-59.87,0.52,0.52,0.48,0.02,0.35,0.84,0.49,0.02,0.25,0.03],[-18.75,-57.23,0.51,0.5,0.5,0.02,0.35,0.84,0.49,0.02,0.25,0.03],[-18.75,-54.59,0.5,0.43,0.52,0.02,0.34,0.82,0.48,0.02,0.22,0.03],[-18.75,-51.95,0.49,0.4,0.55,0.02,0.34,0.81,0.48,0.02,0.17,0.03],[-18.75,-49.31,0.46,0.35,0.57,0.02,0.33,0.8,0.49,0.02,0.18,0.03],[-18.75,-46.67,0.43,0.34,0.52,0.02,0.33,0.8,0.49,0.02,0.18,0.03],[-18.75,-44.03,0.42,0.34,0.42,0.02,0.33,0.8,0.49,0.02,0.18,0.03],[-18.75,-41.39,0.43,0.36,0.32,0.02,0.33,0.8,0.48,0.02,0.18,0.03],[-18.75,14.05,0.48,0.54,0.49,0.02,0.35,0.85,0.5,0.02,0.14,0.03],[-18.75,16.69,0.47,0.54,0.55,0.02,0.35,0.85,0.49,0.02,0.14,0.03],[-18.75,19.33,0.45,0.48,0.58,0.02,0.35,0.83,0.47,0.02,0.16,0.03],[-18.75,21.97,0.43,0.47,0.54,0.02,0.34,0.83,0.45,0.02,0.16,0.03],[-18.75,24.61,0.43,0.5,0.53,0.02,0.35,0.84,0.45,0.02,0.18,0.03],[-18.75,27.25,0.42,0.52,0.59,0.02,0.35,0.84,0.45,0.02,0.22,0.03],[-18.75,29.89,0.43,0.52,0.59,0.02,0.35,0.84,0.45,0.02,0.28,0.03],[-18.75,32.53,0.43,0.5,0.59,0.02,0.35,0.84,0.45,0.02,0.31,0.03],[-18.75,35.17,0.45,0.45,0.57,0.02,0.34,0.82,0.45,0.02,0.33,0.03],[-18.75,45.73,0.45,0.34,0.54,0.02,0.33,0.8,0.44,0.02,0.33,0.03],[-18.75,48.37,0.46,0.29,0.43,0.02,0.32,0.78,0.44,0.02,0.32,0.03],[-18.75,122.29,0.44,0.57,0.26,0.02,0.36,0.85,0.51,0.02,0.28,0.03],[-18.75,124.93,0.43,0.58,0.27,0.02,0.36,0.85,0.51,0.02,0.24,0.03],[-18.75,127.57,0.43,0.6,0.28,0.02,0.36,0.86,0.5,0.02,0.2,0.03],[-18.75,130.21,0.44,0.58,0.19,0.02,0.36,0.86,0.49,0.02,0.18,0.03],[-18.75,132.85,0.43,0.58,0.18,0.02,0.36,0.85,0.47,0.02,0.17,0.03],[-18.75,135.49,0.43,0.61,0.26,0.02,0.36,0.86,0.47,0.02,0.17,0.03],[-18.75,138.13,0.43,0.61,0.26,0.02,0.36,0.86,0.47,0.02,0.19,0.03],[-18.75,140.77,0.43,0.58,0.28,0.02,0.36,0.85,0.47,0.02,0.21,0.03],[-18.75,143.41,0.42,0.58,0.35,0.02,0.36,0.85,0.47,0.02,0.22,0.03],[-18.75,146.05,0.42,0.58,0.43,0.02,0.36,0.85,0.46,0.02,0.24,0.03],[-16.25,-178.7,0.43,0.37,0.29,0.02,0.3,0.81,0.32,0.02,0.19,0.03],[-16.25,-176.09,0.47,0.4,0.35,0.05,0.3,0.82,0.33,0.02,0.18,0.03],[-16.25,-173.49,0.43,0.42,0.36,0.02,0.3,0.83,0.33,0.02,0.17,0.03],[-16.25,-170.89,0.42,0.46,0.3,0.02,0.31,0.83,0.34,0.02,0.16,0.03],[-16.25,-168.28,0.42,0.45,0.24,0.02,0.31,0.83,0.35,0.02,0.15,0.03],[-16.25,-165.68,0.42,0.43,0.19,0.02,0.31,0.83,0.35,0.02,0.15,0.03],[-16.25,-163.07,0.41,0.46,0.13,0.02,0.31,0.83,0.35,0.02,0.16,0.03],[-16.25,-160.47,0.41,0.51,0.09,0.02,0.31,0.84,0.35,0.02,0.16,0.03],[-16.25,-157.87,0.41,0.46,0.08,0.02,0.31,0.83,0.34,0.02,0.16,0.03],[-16.25,-155.26,0.41,0.45,0.08,0.02,0.31,0.83,0.34,0.02,0.16,0.03],[-16.25,-152.66,0.41,0.47,0.08,0.02,0.31,0.84,0.34,0.02,0.18,0.03],[-16.25,-150.05,0.41,0.5,0.08,0.02,0.31,0.84,0.34,0.02,0.21,0.03],[-16.25,-147.45,0.41,0.48,0.08,0.02,0.31,0.84,0.34,0.02,0.21,0.03],[-16.25,-144.85,0.42,0.49,0.12,0.02,0.31,0.84,0.34,0.02,0.21,0.03],[-16.25,-142.24,0.42,0.47,0.24,0.02,0.31,0.84,0.34,0.02,0.21,0.03],[-16.25,-139.64,0.41,0.46,0.3,0.02,0.31,0.83,0.34,0.02,0.2,0.03],[-16.25,-137.03,0.41,0.43,0.35,0.02,0.31,0.83,0.34,0.02,0.2,0.03],[-16.25,-134.43,0.41,0.43,0.38,0.02,0.31,0.83,0.34,0.02,0.21,0.03],[-16.25,-131.83,0.41,0.44,0.4,0.02,0.31,0.83,0.34,0.02,0.21,0.03],[-16.25,-129.22,0.41,0.46,0.39,0.02,0.31,0.83,0.34,0.02,0.18,0.03],[-16.25,-126.62,0.4,0.42,0.32,0.02,0.3,0.82,0.34,0.02,0.17,0.03],[-16.25,-124.01,0.4,0.36,0.21,0.02,0.3,0.81,0.34,0.02,0.16,0.03],[-16.25,-121.41,0.39,0.32,0.15,0.02,0.29,0.8,0.34,0.02,0.14,0.03],[-16.25,-118.81,0.38,0.33,0.09,0.02,0.29,0.8,0.34,0.02,0.13,0.03],[-16.25,-116.2,0.38,0.38,0.08,0.02,0.3,0.81,0.34,0.02,0.12,0.03],[-16.25,-113.6,0.4,0.43,0.08,0.02,0.3,0.83,0.35,0.02,0.11,0.03],[-16.25,-110.99,0.41,0.45,0.08,0.02,0.31,0.83,0.35,0.02,0.1,0.03],[-16.25,-108.39,0.41,0.46,0.09,0.02,0.31,0.83,0.35,0.02,0.09,0.03],[-16.25,-105.79,0.42,0.47,0.12,0.02,0.31,0.84,0.34,0.02,0.11,0.03],[-16.25,-103.18,0.42,0.48,0.14,0.02,0.31,0.84,0.34,0.02,0.14,0.03],[-16.25,-100.58,0.43,0.51,0.16,0.02,0.31,0.84,0.34,0.02,0.16,0.03],[-16.25,-97.97,0.43,0.56,0.18,0.02,0.32,0.86,0.34,0.02,0.18,0.03],[-16.25,-95.37,0.44,0.57,0.2,0.02,0.32,0.86,0.34,0.02,0.2,0.03],[-16.25,-92.76,0.56,0.6,0.15,0.24,0.33,0.87,0.33,0.02,0.22,0.03],[-16.25,-90.16,0.7,0.56,0.13,0.69,0.32,0.86,0.33,0.02,0.21,0.03],[-16.25,-87.56,0.52,0.62,0.16,0.14,0.33,0.87,0.33,0.02,0.22,0.03],[-16.25,-84.95,0.44,0.6,0.18,0.02,0.32,0.87,0.33,0.02,0.2,0.03],[-16.25,-82.35,0.44,0.6,0.2,0.02,0.32,0.86,0.34,0.02,0.19,0.03],[-16.25,-79.74,0.43,0.6,0.18,0.02,0.33,0.87,0.34,0.02,0.17,0.03],[-16.25,-77.14,0.43,0.63,0.16,0.02,0.33,0.87,0.35,0.02,0.16,0.03],[-16.25,-74.54,0.44,0.66,0.15,0.02,0.33,0.88,0.35,0.02,0.14,0.03],[-16.25,-71.93,0.44,0.61,0.11,0.02,0.33,0.87,0.35,0.02,0.15,0.03],[-16.25,-69.33,0.44,0.57,0.11,0.02,0.32,0.86,0.34,0.02,0.15,0.03],[-16.25,-66.72,0.44,0.56,0.16,0.02,0.32,0.86,0.35,0.02,0.15,0.03],[-16.25,-64.12,0.46,0.56,0.23,0.02,0.32,0.86,0.35,0.02,0.17,0.03],[-16.25,-61.52,0.46,0.53,0.28,0.02,0.32,0.85,0.34,0.02,0.17,0.03],[-16.25,-58.91,0.46,0.45,0.32,0.02,0.31,0.83,0.34,0.02,0.18,0.03],[-16.25,-56.31,0.46,0.46,0.33,0.02,0.31,0.83,0.34,0.02,0.17,0.03],[-16.25,-53.7,0.45,0.4,0.3,0.02,0.3,0.82,0.34,0.02,0.15,0.03],[-16.25,-51.1,0.44,0.36,0.3,0.02,0.3,0.81,0.34,0.02,0.13,0.03],[-16.25,-48.5,0.41,0.35,0.32,0.02,0.3,0.81,0.34,0.02,0.13,0.03],[-16.25,-45.89,0.39,0.37,0.27,0.02,0.3,0.81,0.35,0.02,0.13,0.03],[-16.25,-43.29,0.39,0.36,0.19,0.02,0.3,0.81,0.35,0.02,0.14,0.03],[-16.25,-40.68,0.4,0.33,0.15,0.02,0.29,0.8,0.34,0.02,0.15,0.03],[-16.25,-38.08,0.42,0.3,0.12,0.02,0.29,0.79,0.34,0.02,0.15,0.03],[-16.25,-35.48,0.44,0.31,0.11,0.02,0.29,0.8,0.33,0.02,0.15,0.03],[-16.25,-32.87,0.44,0.32,0.11,0.02,0.29,0.8,0.33,0.02,0.15,0.03],[-16.25,-30.27,0.43,0.36,0.11,0.02,0.3,0.81,0.33,0.02,0.17,0.03],[-16.25,-27.66,0.42,0.44,0.13,0.02,0.31,0.83,0.33,0.02,0.18,0.03],[-16.25,-25.06,0.41,0.49,0.19,0.02,0.31,0.84,0.33,0.02,0.19,0.03],[-16.25,-22.46,0.42,0.56,0.26,0.02,0.32,0.86,0.34,0.02,0.21,0.03],[-16.25,-19.85,0.43,0.59,0.31,0.02,0.32,0.86,0.35,0.02,0.22,0.03],[-16.25,-17.25,0.45,0.61,0.31,0.02,0.33,0.87,0.35,0.02,0.21,0.03],[-16.25,-14.64,0.45,0.62,0.27,0.02,0.33,0.87,0.35,0.02,0.21,0.03],[-16.25,-12.04,0.45,0.55,0.23,0.02,0.32,0.85,0.36,0.02,0.19,0.03],[-16.25,-9.44,0.45,0.51,0.21,0.02,0.31,0.84,0.36,0.02,0.17,0.03],[-16.25,-6.83,0.44,0.46,0.16,0.02,0.31,0.83,0.36,0.02,0.16,0.03],[-16.25,-4.23,0.43,0.42,0.11,0.02,0.3,0.82,0.36,0.02,0.15,0.03],[-16.25,-1.62,0.43,0.41,0.08,0.02,0.3,0.82,0.36,0.02,0.13,0.03],[-16.25,0.98,0.44,0.41,0.08,0.02,0.3,0.82,0.36,0.02,0.12,0.03],[-16.25,3.58,0.43,0.43,0.15,0.02,0.31,0.83,0.36,0.02,0.13,0.03],[-16.25,6.19,0.44,0.45,0.18,0.02,0.31,0.83,0.36,0.02,0.13,0.03],[-16.25,8.79,0.44,0.47,0.19,0.02,0.31,0.84,0.35,0.02,0.13,0.03],[-16.25,11.4,0.44,0.5,0.19,0.02,0.31,0.84,0.35,0.02,0.12,0.03],[-16.25,14,0.44,0.53,0.25,0.02,0.32,0.85,0.35,0.02,0.1,0.03],[-16.25,16.6,0.44,0.53,0.31,0.02,0.32,0.85,0.34,0.02,0.1,0.03],[-16.25,19.21,0.43,0.52,0.35,0.02,0.32,0.85,0.33,0.02,0.12,0.03],[-16.25,21.81,0.42,0.51,0.31,0.02,0.31,0.84,0.33,0.02,0.13,0.03],[-16.25,24.42,0.41,0.52,0.26,0.02,0.32,0.85,0.32,0.02,0.13,0.03],[-16.25,27.02,0.41,0.54,0.31,0.02,0.32,0.85,0.32,0.02,0.16,0.03],[-16.25,29.62,0.41,0.53,0.34,0.02,0.32,0.85,0.31,0.02,0.2,0.03],[-16.25,32.23,0.4,0.49,0.34,0.02,0.31,0.84,0.32,0.02,0.22,0.03],[-16.25,34.83,0.4,0.45,0.32,0.02,0.31,0.83,0.32,0.02,0.22,0.03],[-16.25,37.44,0.4,0.4,0.3,0.02,0.3,0.82,0.32,0.02,0.22,0.03],[-16.25,45.25,0.41,0.31,0.38,0.02,0.29,0.8,0.31,0.02,0.23,0.03],[-16.25,47.85,0.42,0.32,0.31,0.02,0.29,0.8,0.31,0.02,0.22,0.03],[-16.25,125.97,0.4,0.64,0.14,0.02,0.33,0.87,0.35,0.02,0.16,0.03],[-16.25,128.58,0.4,0.62,0.14,0.02,0.33,0.87,0.34,0.02,0.14,0.03],[-16.25,131.18,0.39,0.61,0.11,0.02,0.33,0.87,0.33,0.02,0.13,0.03],[-16.25,133.79,0.42,0.56,0.13,0.05,0.32,0.86,0.33,0.02,0.12,0.03],[-16.25,136.39,0.43,0.53,0.17,0.06,0.32,0.85,0.33,0.02,0.13,0.03],[-16.25,141.6,0.4,0.54,0.23,0.02,0.32,0.85,0.33,0.02,0.15,0.03],[-16.25,144.2,0.39,0.54,0.26,0.02,0.32,0.85,0.33,0.02,0.17,0.03],[-13.75,-75.76,0.39,0.6,0.11,0.02,0.3,0.87,0.24,0.02,0.11,0.03],[-13.75,-73.19,0.39,0.58,0.1,0.02,0.3,0.87,0.24,0.02,0.11,0.03],[-13.75,-70.62,0.4,0.52,0.1,0.02,0.29,0.85,0.23,0.02,0.11,0.03],[-13.75,-68.04,0.4,0.52,0.13,0.02,0.29,0.85,0.23,0.02,0.11,0.03],[-13.75,-65.47,0.41,0.5,0.16,0.02,0.29,0.85,0.23,0.02,0.11,0.03],[-13.75,-62.89,0.42,0.51,0.19,0.02,0.29,0.85,0.23,0.02,0.11,0.03],[-13.75,-60.32,0.41,0.47,0.19,0.02,0.28,0.84,0.23,0.02,0.11,0.03],[-13.75,-57.75,0.41,0.44,0.2,0.02,0.28,0.83,0.23,0.02,0.11,0.03],[-13.75,-55.17,0.41,0.41,0.17,0.02,0.28,0.83,0.23,0.02,0.11,0.03],[-13.75,-52.6,0.41,0.37,0.14,0.02,0.27,0.82,0.23,0.02,0.1,0.03],[-13.75,-50.03,0.4,0.37,0.15,0.02,0.27,0.82,0.23,0.02,0.1,0.03],[-13.75,-47.45,0.39,0.37,0.16,0.02,0.27,0.82,0.23,0.02,0.1,0.03],[-13.75,-44.88,0.37,0.38,0.14,0.02,0.27,0.82,0.23,0.02,0.1,0.03],[-13.75,-42.3,0.38,0.36,0.11,0.02,0.27,0.81,0.23,0.02,0.1,0.03],[-13.75,-39.73,0.39,0.31,0.09,0.02,0.26,0.8,0.23,0.02,0.11,0.03],[-13.75,14.32,0.41,0.5,0.11,0.02,0.29,0.85,0.23,0.02,0.08,0.03],[-13.75,16.89,0.4,0.52,0.14,0.02,0.29,0.85,0.23,0.02,0.08,0.03],[-13.75,19.47,0.4,0.56,0.17,0.02,0.29,0.86,0.23,0.02,0.09,0.03],[-13.75,22.04,0.4,0.53,0.18,0.02,0.29,0.85,0.23,0.02,0.09,0.03],[-13.75,24.61,0.4,0.54,0.18,0.02,0.29,0.86,0.22,0.02,0.1,0.03],[-13.75,27.19,0.4,0.55,0.19,0.02,0.29,0.86,0.22,0.02,0.11,0.03],[-13.75,29.76,0.39,0.55,0.19,0.02,0.29,0.86,0.22,0.02,0.13,0.03],[-13.75,32.34,0.37,0.51,0.17,0.02,0.29,0.85,0.22,0.02,0.14,0.03],[-13.75,34.91,0.41,0.47,0.17,0.08,0.28,0.84,0.22,0.02,0.14,0.03],[-13.75,37.48,0.38,0.38,0.17,0.04,0.27,0.82,0.22,0.02,0.14,0.03],[-13.75,40.06,0.36,0.35,0.18,0.02,0.27,0.81,0.22,0.02,0.14,0.03],[-13.75,130.14,0.36,0.63,0.08,0.02,0.3,0.88,0.23,0.02,0.1,0.03],[-13.75,132.71,0.36,0.58,0.09,0.02,0.3,0.86,0.22,0.02,0.09,0.03],[-13.75,135.29,0.36,0.52,0.11,0.02,0.29,0.85,0.22,0.02,0.09,0.03],[-13.75,143.01,0.38,0.5,0.17,0.02,0.29,0.85,0.23,0.02,0.11,0.03],[-11.25,-76.77,0.41,0.45,0.09,0.06,0.26,0.84,0.16,0.02,0.09,0.03],[-11.25,-74.22,0.39,0.45,0.09,0.04,0.26,0.84,0.16,0.02,0.08,0.03],[-11.25,-71.67,0.37,0.46,0.09,0.02,0.26,0.84,0.16,0.02,0.08,0.03],[-11.25,-69.12,0.37,0.43,0.09,0.02,0.26,0.84,0.16,0.02,0.08,0.03],[-11.25,-66.57,0.38,0.45,0.11,0.02,0.26,0.84,0.16,0.02,0.08,0.03],[-11.25,-64.02,0.39,0.45,0.12,0.02,0.26,0.84,0.16,0.02,0.08,0.03],[-11.25,-61.47,0.39,0.47,0.13,0.02,0.27,0.84,0.16,0.02,0.07,0.03],[-11.25,-58.92,0.38,0.45,0.14,0.02,0.26,0.84,0.16,0.02,0.07,0.03],[-11.25,-56.37,0.38,0.41,0.13,0.02,0.26,0.83,0.16,0.02,0.07,0.03],[-11.25,-53.83,0.39,0.38,0.11,0.02,0.26,0.82,0.16,0.02,0.08,0.03],[-11.25,-51.28,0.38,0.37,0.11,0.02,0.25,0.82,0.16,0.02,0.08,0.03],[-11.25,-48.73,0.39,0.35,0.11,0.02,0.25,0.82,0.16,0.02,0.08,0.03],[-11.25,-46.18,0.37,0.39,0.11,0.02,0.26,0.83,0.16,0.02,0.08,0.03],[-11.25,-43.63,0.37,0.37,0.1,0.02,0.25,0.82,0.16,0.02,0.07,0.03],[-11.25,-41.08,0.37,0.34,0.09,0.02,0.25,0.81,0.16,0.02,0.07,0.03],[-11.25,-38.53,0.37,0.31,0.08,0.02,0.25,0.81,0.16,0.02,0.07,0.03],[-11.25,15,0.38,0.49,0.08,0.02,0.27,0.85,0.16,0.02,0.07,0.03],[-11.25,17.55,0.38,0.5,0.1,0.02,0.27,0.85,0.16,0.02,0.07,0.03],[-11.25,20.09,0.38,0.56,0.11,0.02,0.28,0.87,0.16,0.02,0.07,0.03],[-11.25,22.64,0.39,0.56,0.13,0.02,0.28,0.87,0.16,0.02,0.07,0.03],[-11.25,25.19,0.39,0.6,0.13,0.02,0.28,0.87,0.16,0.02,0.08,0.03],[-11.25,27.74,0.38,0.55,0.13,0.02,0.28,0.86,0.15,0.02,0.08,0.03],[-11.25,30.29,0.37,0.54,0.12,0.02,0.27,0.86,0.15,0.02,0.09,0.03],[-11.25,32.84,0.35,0.5,0.1,0.02,0.27,0.85,0.16,0.02,0.09,0.03],[-11.25,35.39,0.34,0.42,0.1,0.02,0.26,0.83,0.16,0.02,0.09,0.03],[-11.25,37.94,0.34,0.35,0.1,0.02,0.25,0.82,0.16,0.02,0.09,0.03],[-11.25,132.25,0.34,0.55,0.08,0.02,0.28,0.86,0.16,0.02,0.07,0.03],[-11.25,142.45,0.38,0.48,0.12,0.02,0.27,0.85,0.16,0.02,0.08,0.03],[-8.75,-77.56,0.45,0.38,0.09,0.15,0.25,0.83,0.12,0.02,0.07,0.03],[-8.75,-75.03,0.48,0.39,0.08,0.23,0.25,0.83,0.12,0.02,0.07,0.03],[-8.75,-72.5,0.48,0.41,0.08,0.22,0.25,0.83,0.12,0.02,0.06,0.03],[-8.75,-69.97,0.39,0.38,0.09,0.05,0.25,0.83,0.12,0.02,0.06,0.03],[-8.75,-67.44,0.36,0.41,0.09,0.02,0.25,0.83,0.12,0.02,0.06,0.03],[-8.75,-64.91,0.37,0.45,0.1,0.02,0.25,0.84,0.12,0.02,0.06,0.03],[-8.75,-62.38,0.37,0.43,0.1,0.02,0.25,0.84,0.12,0.02,0.06,0.03],[-8.75,-59.85,0.36,0.46,0.1,0.02,0.26,0.85,0.12,0.02,0.06,0.03],[-8.75,-57.32,0.37,0.45,0.1,0.02,0.25,0.84,0.12,0.02,0.06,0.03],[-8.75,-54.79,0.38,0.4,0.1,0.02,0.25,0.83,0.12,0.02,0.06,0.03],[-8.75,-52.26,0.37,0.41,0.09,0.02,0.25,0.83,0.12,0.02,0.06,0.03],[-8.75,-49.73,0.36,0.36,0.09,0.02,0.24,0.82,0.12,0.02,0.06,0.03],[-8.75,-47.2,0.36,0.38,0.09,0.02,0.25,0.83,0.12,0.02,0.06,0.03],[-8.75,-44.68,0.36,0.39,0.09,0.02,0.25,0.83,0.12,0.02,0.06,0.03],[-8.75,-42.15,0.36,0.34,0.08,0.02,0.24,0.82,0.12,0.02,0.06,0.03],[-8.75,-39.62,0.36,0.32,0.08,0.02,0.24,0.81,0.12,0.02,0.06,0.03],[-8.75,-37.09,0.37,0.3,0.08,0.02,0.24,0.81,0.12,0.02,0.06,0.03],[-8.75,13.5,0.37,0.49,0.09,0.02,0.26,0.85,0.12,0.02,0.06,0.03],[-8.75,16.03,0.36,0.47,0.09,0.02,0.26,0.85,0.12,0.02,0.06,0.03],[-8.75,18.56,0.37,0.52,0.09,0.02,0.26,0.86,0.12,0.02,0.06,0.03],[-8.75,21.09,0.38,0.56,0.09,0.02,0.27,0.87,0.12,0.02,0.06,0.03],[-8.75,23.62,0.37,0.61,0.1,0.02,0.27,0.88,0.12,0.02,0.06,0.03],[-8.75,26.15,0.38,0.58,0.09,0.02,0.27,0.87,0.12,0.02,0.06,0.03],[-8.75,28.68,0.37,0.53,0.09,0.02,0.26,0.86,0.12,0.02,0.06,0.03],[-8.75,31.21,0.35,0.49,0.09,0.02,0.26,0.85,0.12,0.02,0.07,0.03],[-8.75,33.74,0.34,0.46,0.09,0.02,0.26,0.85,0.12,0.02,0.07,0.03],[-8.75,36.27,0.34,0.39,0.09,0.02,0.25,0.83,0.12,0.02,0.07,0.03],[-8.75,38.8,0.34,0.36,0.09,0.02,0.24,0.82,0.12,0.02,0.07,0.03],[-8.75,117.21,0.36,0.53,0.08,0.02,0.26,0.86,0.12,0.02,0.06,0.03],[-8.75,142.5,0.35,0.45,0.09,0.02,0.26,0.85,0.12,0.02,0.06,0.03],[-8.75,147.56,0.36,0.49,0.1,0.02,0.26,0.85,0.12,0.02,0.07,0.03],[-6.25,-80.66,0.36,0.3,0.08,0.02,0.23,0.81,0.11,0.02,0.06,0.03],[-6.25,-78.14,0.37,0.3,0.08,0.02,0.23,0.81,0.11,0.02,0.06,0.03],[-6.25,-75.63,0.37,0.35,0.08,0.03,0.24,0.82,0.11,0.02,0.06,0.03],[-6.25,-73.11,0.38,0.37,0.08,0.05,0.24,0.83,0.11,0.02,0.06,0.03],[-6.25,-70.6,0.37,0.4,0.08,0.03,0.25,0.84,0.11,0.02,0.05,0.03],[-6.25,-68.08,0.36,0.39,0.09,0.03,0.24,0.83,0.11,0.02,0.05,0.03],[-6.25,-65.57,0.36,0.36,0.09,0.02,0.24,0.82,0.11,0.02,0.05,0.03],[-6.25,-63.05,0.35,0.4,0.09,0.02,0.25,0.84,0.11,0.02,0.05,0.03],[-6.25,-60.54,0.36,0.42,0.09,0.02,0.25,0.84,0.11,0.02,0.05,0.03],[-6.25,-58.03,0.43,0.45,0.09,0.1,0.25,0.85,0.11,0.02,0.05,0.03],[-6.25,-55.51,0.45,0.43,0.09,0.13,0.25,0.84,0.11,0.02,0.05,0.03],[-6.25,-53,0.38,0.41,0.09,0.03,0.25,0.84,0.11,0.02,0.05,0.03],[-6.25,-50.48,0.36,0.39,0.09,0.02,0.24,0.83,0.11,0.02,0.05,0.03],[-6.25,-47.97,0.36,0.37,0.08,0.02,0.24,0.83,0.11,0.02,0.05,0.03],[-6.25,-45.45,0.36,0.36,0.09,0.02,0.24,0.83,0.11,0.02,0.05,0.03],[-6.25,-42.94,0.36,0.39,0.08,0.02,0.24,0.83,0.11,0.02,0.05,0.03],[-6.25,-40.42,0.37,0.37,0.08,0.02,0.24,0.83,0.11,0.02,0.05,0.03],[-6.25,-37.91,0.37,0.35,0.08,0.02,0.24,0.82,0.11,0.02,0.05,0.03],[-6.25,-35.39,0.37,0.36,0.08,0.02,0.24,0.82,0.11,0.02,0.05,0.03],[-6.25,12.39,0.37,0.5,0.08,0.02,0.26,0.86,0.11,0.02,0.05,0.03],[-6.25,14.91,0.37,0.47,0.08,0.02,0.25,0.85,0.11,0.02,0.05,0.03],[-6.25,17.42,0.36,0.49,0.08,0.02,0.26,0.86,0.11,0.02,0.05,0.03],[-6.25,19.94,0.38,0.52,0.09,0.02,0.26,0.86,0.11,0.02,0.05,0.03],[-6.25,22.45,0.38,0.54,0.09,0.02,0.26,0.87,0.11,0.02,0.05,0.03],[-6.25,24.97,0.38,0.55,0.09,0.02,0.26,0.87,0.11,0.02,0.05,0.03],[-6.25,27.48,0.36,0.51,0.08,0.02,0.26,0.86,0.11,0.02,0.05,0.03],[-6.25,30,0.34,0.44,0.08,0.02,0.25,0.84,0.11,0.02,0.05,0.03],[-6.25,32.51,0.33,0.39,0.08,0.02,0.24,0.83,0.11,0.02,0.05,0.03],[-6.25,35.03,0.33,0.38,0.08,0.02,0.24,0.83,0.11,0.02,0.06,0.03],[-6.25,37.54,0.33,0.38,0.08,0.02,0.24,0.83,0.11,0.02,0.05,0.03],[-6.25,140.66,0.34,0.48,0.08,0.02,0.25,0.85,0.11,0.02,0.05,0.03],[-6.25,143.17,0.34,0.47,0.09,0.02,0.25,0.85,0.11,0.02,0.05,0.03],[-6.25,145.69,0.36,0.46,0.09,0.02,0.25,0.85,0.11,0.02,0.05,0.03],[-3.75,-78.53,0.36,0.27,0.08,0.02,0.23,0.8,0.1,0.02,0.05,0.03],[-3.75,-76.03,0.36,0.29,0.08,0.02,0.23,0.81,0.1,0.02,0.05,0.03],[-3.75,-73.52,0.36,0.32,0.08,0.03,0.23,0.82,0.1,0.02,0.05,0.03],[-3.75,-71.02,0.35,0.36,0.08,0.02,0.24,0.83,0.1,0.02,0.05,0.03],[-3.75,-68.51,0.36,0.34,0.08,0.03,0.24,0.82,0.1,0.02,0.05,0.03],[-3.75,-66.01,0.35,0.3,0.08,0.02,0.23,0.81,0.1,0.02,0.05,0.03],[-3.75,-63.5,0.35,0.35,0.08,0.02,0.24,0.82,0.1,0.02,0.05,0.03],[-3.75,-61,0.36,0.4,0.08,0.02,0.24,0.84,0.1,0.02,0.05,0.03],[-3.75,-58.49,0.46,0.41,0.08,0.18,0.25,0.84,0.1,0.02,0.05,0.03],[-3.75,-55.98,0.59,0.44,0.08,0.61,0.25,0.85,0.1,0.02,0.05,0.03],[-3.75,-53.48,0.54,0.41,0.08,0.43,0.25,0.84,0.1,0.02,0.05,0.03],[-3.75,-50.97,0.42,0.37,0.08,0.1,0.24,0.83,0.1,0.02,0.05,0.03],[-3.75,-48.47,0.35,0.36,0.08,0.02,0.24,0.83,0.1,0.02,0.05,0.03],[-3.75,-45.96,0.36,0.35,0.08,0.02,0.24,0.82,0.1,0.02,0.05,0.03],[-3.75,-43.46,0.36,0.39,0.08,0.02,0.24,0.83,0.1,0.02,0.05,0.03],[-3.75,-40.95,0.36,0.42,0.08,0.02,0.25,0.84,0.1,0.02,0.05,0.03],[-3.75,-38.45,0.37,0.38,0.08,0.02,0.24,0.83,0.1,0.02,0.05,0.03],[-3.75,11.66,0.36,0.5,0.08,0.02,0.26,0.86,0.1,0.02,0.05,0.03],[-3.75,14.17,0.36,0.48,0.08,0.02,0.25,0.86,0.1,0.02,0.05,0.03],[-3.75,16.67,0.36,0.47,0.08,0.02,0.25,0.85,0.1,0.02,0.05,0.03],[-3.75,19.18,0.37,0.5,0.08,0.02,0.26,0.86,0.1,0.02,0.05,0.03],[-3.75,21.68,0.38,0.51,0.08,0.02,0.26,0.86,0.1,0.02,0.05,0.03],[-3.75,24.19,0.38,0.49,0.08,0.02,0.26,0.86,0.1,0.02,0.05,0.03],[-3.75,26.69,0.36,0.46,0.08,0.02,0.25,0.85,0.1,0.02,0.05,0.03],[-3.75,29.2,0.35,0.41,0.08,0.02,0.25,0.84,0.1,0.02,0.05,0.03],[-3.75,31.7,0.34,0.34,0.08,0.02,0.24,0.82,0.1,0.02,0.05,0.03],[-3.75,34.21,0.33,0.34,0.08,0.02,0.24,0.82,0.1,0.02,0.05,0.03],[-3.75,36.71,0.34,0.36,0.08,0.02,0.24,0.82,0.1,0.02,0.05,0.03],[-3.75,39.22,0.34,0.38,0.08,0.02,0.24,0.83,0.1,0.02,0.05,0.03],[-3.75,104.36,0.35,0.43,0.08,0.02,0.25,0.84,0.1,0.02,0.05,0.03],[-3.75,121.9,0.35,0.54,0.08,0.02,0.26,0.87,0.1,0.02,0.05,0.03],[-3.75,126.91,0.33,0.52,0.08,0.02,0.26,0.86,0.1,0.02,0.05,0.03],[-3.75,134.42,0.37,0.48,0.08,0.04,0.25,0.86,0.1,0.02,0.05,0.03],[-3.75,136.93,0.35,0.46,0.08,0.03,0.25,0.85,0.1,0.02,0.05,0.03],[-3.75,139.43,0.34,0.44,0.08,0.02,0.25,0.85,0.1,0.02,0.05,0.03],[-3.75,141.94,0.34,0.44,0.08,0.02,0.25,0.84,0.1,0.02,0.05,0.03],[-1.25,-78.73,0.36,0.27,0.08,0.02,0.23,0.8,0.1,0.02,0.05,0.03],[-1.25,-76.23,0.36,0.27,0.08,0.02,0.23,0.8,0.1,0.02,0.05,0.03],[-1.25,-73.72,0.35,0.29,0.08,0.02,0.23,0.81,0.1,0.02,0.05,0.03],[-1.25,-71.22,0.34,0.3,0.08,0.02,0.23,0.81,0.1,0.02,0.05,0.03],[-1.25,-68.72,0.35,0.3,0.08,0.02,0.23,0.81,0.1,0.02,0.05,0.03],[-1.25,-66.22,0.34,0.31,0.08,0.02,0.23,0.81,0.1,0.02,0.05,0.03],[-1.25,-63.72,0.34,0.35,0.08,0.02,0.24,0.82,0.1,0.02,0.05,0.03],[-1.25,-61.22,0.43,0.38,0.08,0.14,0.24,0.83,0.1,0.02,0.05,0.03],[-1.25,-58.72,0.6,0.39,0.08,0.68,0.24,0.83,0.1,0.02,0.05,0.03],[-1.25,-56.22,0.64,0.43,0.08,0.85,0.25,0.84,0.1,0.02,0.05,0.03],[-1.25,-53.72,0.61,0.42,0.08,0.73,0.25,0.84,0.1,0.02,0.05,0.03],[-1.25,-51.22,0.44,0.39,0.08,0.17,0.24,0.83,0.1,0.02,0.05,0.03],[-1.25,-48.72,0.36,0.37,0.08,0.03,0.24,0.83,0.1,0.02,0.05,0.03],[-1.25,-46.22,0.39,0.35,0.08,0.05,0.24,0.82,0.1,0.02,0.05,0.03],[-1.25,11.3,0.36,0.55,0.08,0.02,0.26,0.87,0.1,0.02,0.05,0.03],[-1.25,13.8,0.35,0.53,0.08,0.02,0.26,0.87,0.1,0.02,0.05,0.03],[-1.25,16.3,0.36,0.49,0.08,0.02,0.25,0.86,0.1,0.02,0.05,0.03],[-1.25,18.8,0.37,0.46,0.08,0.02,0.25,0.85,0.1,0.02,0.05,0.03],[-1.25,21.3,0.38,0.47,0.08,0.02,0.25,0.85,0.1,0.02,0.05,0.03],[-1.25,23.8,0.38,0.45,0.08,0.02,0.25,0.85,0.1,0.02,0.05,0.03],[-1.25,26.3,0.37,0.41,0.08,0.02,0.25,0.84,0.1,0.02,0.05,0.03],[-1.25,28.8,0.35,0.4,0.08,0.02,0.24,0.84,0.1,0.02,0.05,0.03],[-1.25,31.3,0.34,0.36,0.08,0.02,0.24,0.83,0.1,0.02,0.05,0.03],[-1.25,33.8,0.34,0.35,0.08,0.02,0.24,0.83,0.1,0.02,0.05,0.03],[-1.25,36.3,0.34,0.37,0.08,0.02,0.24,0.83,0.1,0.02,0.05,0.03],[-1.25,38.8,0.34,0.37,0.08,0.02,0.24,0.83,0.1,0.02,0.05,0.03],[-1.25,41.3,0.34,0.34,0.08,0.02,0.24,0.82,0.1,0.02,0.05,0.03],[-1.25,101.32,0.34,0.38,0.08,0.02,0.24,0.83,0.1,0.02,0.05,0.03],[-1.25,103.82,0.34,0.42,0.08,0.02,0.25,0.84,0.1,0.02,0.05,0.03],[-1.25,111.32,0.36,0.46,0.08,0.02,0.25,0.85,0.1,0.02,0.05,0.03],[-1.25,113.82,0.36,0.5,0.08,0.02,0.26,0.86,0.1,0.02,0.05,0.03],[-1.25,116.32,0.37,0.51,0.08,0.02,0.26,0.86,0.1,0.02,0.05,0.03],[-1.25,121.32,0.41,0.52,0.08,0.09,0.26,0.86,0.1,0.02,0.05,0.03],[-1.25,131.32,0.33,0.5,0.08,0.02,0.26,0.86,0.1,0.02,0.05,0.03],[-1.25,133.82,0.37,0.5,0.08,0.03,0.26,0.86,0.1,0.02,0.05,0.03],[1.25,-78.73,0.37,0.28,0.08,0.02,0.23,0.8,0.1,0.02,0.05,0.03],[1.25,-76.23,0.36,0.26,0.08,0.02,0.22,0.8,0.1,0.02,0.05,0.03],[1.25,-73.72,0.35,0.28,0.08,0.02,0.23,0.8,0.1,0.02,0.05,0.03],[1.25,-71.22,0.34,0.29,0.08,0.02,0.23,0.81,0.1,0.02,0.05,0.03],[1.25,-68.72,0.36,0.3,0.08,0.03,0.23,0.81,0.1,0.02,0.05,0.03],[1.25,-66.22,0.35,0.32,0.08,0.02,0.23,0.82,0.1,0.02,0.05,0.03],[1.25,-63.72,0.34,0.36,0.08,0.02,0.24,0.83,0.1,0.02,0.05,0.03],[1.25,-61.22,0.44,0.39,0.08,0.16,0.24,0.83,0.1,0.02,0.05,0.03],[1.25,-58.72,0.61,0.4,0.08,0.77,0.24,0.84,0.1,0.02,0.05,0.03],[1.25,-56.22,0.63,0.44,0.08,0.84,0.25,0.85,0.1,0.02,0.05,0.03],[1.25,-53.72,0.58,0.43,0.08,0.62,0.25,0.85,0.1,0.02,0.05,0.03],[1.25,-51.22,0.45,0.41,0.08,0.21,0.25,0.84,0.1,0.02,0.05,0.03],[1.25,11.3,0.36,0.56,0.08,0.02,0.26,0.87,0.1,0.02,0.05,0.03],[1.25,13.8,0.35,0.54,0.08,0.02,0.26,0.87,0.1,0.02,0.05,0.03],[1.25,16.3,0.36,0.51,0.08,0.02,0.26,0.86,0.1,0.02,0.05,0.03],[1.25,18.8,0.37,0.46,0.08,0.02,0.25,0.85,0.1,0.02,0.05,0.03],[1.25,21.3,0.37,0.45,0.08,0.02,0.25,0.85,0.1,0.02,0.05,0.03],[1.25,23.8,0.38,0.44,0.08,0.02,0.25,0.85,0.1,0.02,0.05,0.03],[1.25,26.3,0.37,0.42,0.08,0.02,0.25,0.84,0.1,0.02,0.05,0.03],[1.25,28.8,0.34,0.38,0.08,0.02,0.24,0.83,0.1,0.02,0.05,0.03],[1.25,31.3,0.34,0.35,0.08,0.02,0.24,0.82,0.1,0.02,0.05,0.03],[1.25,33.8,0.34,0.36,0.08,0.02,0.24,0.83,0.1,0.02,0.05,0.03],[1.25,36.3,0.34,0.36,0.08,0.02,0.24,0.83,0.1,0.02,0.05,0.03],[1.25,38.8,0.34,0.35,0.08,0.02,0.24,0.82,0.1,0.02,0.05,0.03],[1.25,41.3,0.35,0.34,0.08,0.02,0.24,0.82,0.1,0.02,0.05,0.03],[1.25,43.8,0.34,0.31,0.08,0.02,0.23,0.81,0.1,0.02,0.05,0.03],[1.25,101.32,0.34,0.38,0.08,0.02,0.24,0.83,0.1,0.02,0.05,0.03],[1.25,111.32,0.35,0.45,0.08,0.02,0.25,0.85,0.1,0.02,0.05,0.03],[1.25,113.82,0.36,0.49,0.08,0.02,0.25,0.86,0.1,0.02,0.05,0.03],[1.25,116.32,0.38,0.5,0.08,0.03,0.26,0.86,0.1,0.02,0.05,0.03],[3.75,-76.03,0.36,0.3,0.08,0.02,0.23,0.81,0.1,0.02,0.05,0.03],[3.75,-73.52,0.35,0.28,0.08,0.02,0.23,0.81,0.1,0.02,0.05,0.03],[3.75,-71.02,0.35,0.3,0.08,0.02,0.23,0.81,0.1,0.02,0.05,0.03],[3.75,-68.51,0.34,0.32,0.08,0.02,0.23,0.81,0.1,0.02,0.05,0.03],[3.75,-66.01,0.34,0.34,0.08,0.02,0.24,0.82,0.1,0.02,0.05,0.03],[3.75,-63.5,0.34,0.37,0.08,0.02,0.24,0.83,0.1,0.02,0.05,0.03],[3.75,-61,0.58,0.4,0.08,0.6,0.24,0.84,0.1,0.02,0.05,0.03],[3.75,-58.49,0.64,0.42,0.08,0.87,0.25,0.84,0.1,0.02,0.05,0.03],[3.75,-55.98,0.63,0.46,0.08,0.87,0.25,0.85,0.1,0.02,0.05,0.03],[3.75,-53.48,0.61,0.47,0.08,0.78,0.25,0.85,0.1,0.02,0.05,0.03],[3.75,11.66,0.36,0.56,0.08,0.02,0.26,0.87,0.1,0.02,0.05,0.03],[3.75,14.17,0.36,0.51,0.08,0.02,0.26,0.86,0.1,0.02,0.05,0.03],[3.75,16.67,0.36,0.51,0.08,0.02,0.26,0.86,0.1,0.02,0.05,0.03],[3.75,19.18,0.36,0.45,0.08,0.02,0.25,0.85,0.1,0.02,0.05,0.03],[3.75,21.68,0.36,0.45,0.08,0.02,0.25,0.85,0.1,0.02,0.05,0.03],[3.75,24.19,0.36,0.46,0.08,0.02,0.25,0.85,0.1,0.02,0.05,0.03],[3.75,26.69,0.36,0.42,0.08,0.02,0.25,0.84,0.1,0.02,0.05,0.03],[3.75,29.2,0.35,0.36,0.08,0.02,0.24,0.83,0.1,0.02,0.05,0.03],[3.75,31.7,0.34,0.35,0.08,0.02,0.24,0.82,0.1,0.02,0.05,0.03],[3.75,34.21,0.35,0.37,0.08,0.02,0.24,0.83,0.1,0.02,0.05,0.03],[3.75,36.71,0.35,0.34,0.08,0.02,0.24,0.82,0.1,0.02,0.05,0.03],[3.75,39.22,0.35,0.31,0.08,0.02,0.23,0.81,0.1,0.02,0.05,0.03],[3.75,41.72,0.35,0.3,0.08,0.02,0.23,0.81,0.1,0.02,0.05,0.03],[3.75,44.23,0.35,0.31,0.08,0.02,0.23,0.81,0.1,0.02,0.05,0.03],[3.75,46.74,0.34,0.35,0.08,0.02,0.24,0.82,0.1,0.02,0.05,0.03],[3.75,96.84,0.35,0.45,0.08,0.02,0.25,0.85,0.1,0.02,0.05,0.03],[3.75,101.85,0.34,0.45,0.08,0.02,0.25,0.85,0.1,0.02,0.05,0.03],[3.75,114.38,0.35,0.47,0.08,0.02,0.25,0.85,0.1,0.02,0.05,0.03],[3.75,116.89,0.35,0.48,0.08,0.02,0.25,0.86,0.1,0.02,0.05,0.03],[6.25,-75.63,0.37,0.35,0.08,0.02,0.24,0.82,0.11,0.02,0.06,0.03],[6.25,-73.11,0.36,0.34,0.08,0.02,0.24,0.82,0.11,0.02,0.06,0.03],[6.25,-70.6,0.36,0.33,0.08,0.02,0.24,0.82,0.11,0.02,0.05,0.03],[6.25,-68.08,0.35,0.37,0.09,0.02,0.24,0.83,0.11,0.02,0.05,0.03],[6.25,-65.57,0.37,0.38,0.09,0.04,0.24,0.83,0.11,0.02,0.05,0.03],[6.25,-63.05,0.48,0.38,0.09,0.24,0.24,0.83,0.11,0.02,0.05,0.03],[6.25,-60.54,0.6,0.38,0.09,0.62,0.24,0.83,0.11,0.02,0.05,0.03],[6.25,-58.03,0.64,0.39,0.09,0.87,0.24,0.83,0.11,0.02,0.05,0.03],[6.25,-10.24,0.35,0.56,0.08,0.02,0.26,0.87,0.11,0.02,0.06,0.03],[6.25,-7.73,0.35,0.6,0.09,0.02,0.27,0.88,0.11,0.02,0.06,0.03],[6.25,-5.21,0.35,0.61,0.09,0.02,0.27,0.88,0.11,0.02,0.06,0.03],[6.25,-2.7,0.34,0.62,0.08,0.02,0.27,0.88,0.11,0.02,0.05,0.03],[6.25,-0.18,0.35,0.62,0.08,0.02,0.27,0.88,0.11,0.02,0.05,0.03],[6.25,2.33,0.35,0.59,0.08,0.02,0.27,0.88,0.11,0.02,0.05,0.03],[6.25,4.85,0.36,0.54,0.08,0.02,0.26,0.87,0.11,0.02,0.05,0.03],[6.25,7.36,0.36,0.54,0.08,0.02,0.26,0.87,0.11,0.02,0.05,0.03],[6.25,9.88,0.35,0.53,0.08,0.02,0.26,0.87,0.11,0.02,0.05,0.03],[6.25,12.39,0.35,0.52,0.08,0.02,0.26,0.86,0.11,0.02,0.05,0.03],[6.25,14.91,0.36,0.5,0.08,0.02,0.26,0.86,0.11,0.02,0.05,0.03],[6.25,17.42,0.35,0.47,0.08,0.02,0.25,0.85,0.11,0.02,0.05,0.03],[6.25,19.94,0.36,0.43,0.08,0.02,0.25,0.84,0.11,0.02,0.05,0.03],[6.25,22.45,0.35,0.45,0.08,0.02,0.25,0.85,0.11,0.02,0.05,0.03],[6.25,24.97,0.35,0.43,0.08,0.02,0.25,0.84,0.11,0.02,0.05,0.03],[6.25,27.48,0.35,0.39,0.08,0.02,0.24,0.83,0.11,0.02,0.05,0.03],[6.25,30,0.35,0.35,0.08,0.02,0.24,0.82,0.11,0.02,0.05,0.03],[6.25,32.51,0.35,0.35,0.08,0.02,0.24,0.82,0.11,0.02,0.05,0.03],[6.25,35.03,0.36,0.36,0.08,0.02,0.24,0.83,0.11,0.02,0.05,0.03],[6.25,37.54,0.36,0.34,0.08,0.02,0.24,0.82,0.11,0.02,0.05,0.03],[6.25,40.06,0.35,0.3,0.08,0.02,0.23,0.81,0.11,0.02,0.05,0.03],[6.25,42.57,0.36,0.3,0.08,0.02,0.23,0.81,0.11,0.02,0.05,0.03],[6.25,45.09,0.36,0.35,0.08,0.02,0.24,0.82,0.11,0.02,0.05,0.03],[6.25,47.6,0.35,0.4,0.08,0.02,0.25,0.83,0.11,0.02,0.05,0.03],[6.25,80.3,0.36,0.49,0.09,0.02,0.26,0.85,0.11,0.02,0.06,0.03],[6.25,100.42,0.34,0.52,0.09,0.02,0.26,0.86,0.11,0.02,0.05,0.03],[6.25,125.57,0.36,0.52,0.08,0.02,0.26,0.86,0.11,0.02,0.05,0.03],[8.75,-82.62,0.37,0.41,0.09,0.02,0.25,0.84,0.12,0.02,0.07,0.03],[8.75,-80.09,0.38,0.45,0.1,0.02,0.25,0.84,0.12,0.02,0.07,0.03],[8.75,-77.56,0.37,0.43,0.1,0.02,0.25,0.84,0.12,0.02,0.07,0.03],[8.75,-75.03,0.37,0.42,0.11,0.02,0.25,0.84,0.12,0.02,0.07,0.03],[8.75,-72.5,0.36,0.42,0.1,0.02,0.25,0.84,0.12,0.02,0.06,0.03],[8.75,-69.97,0.35,0.43,0.1,0.02,0.25,0.84,0.12,0.02,0.06,0.03],[8.75,-67.44,0.34,0.44,0.11,0.02,0.25,0.84,0.12,0.02,0.06,0.03],[8.75,-64.91,0.41,0.43,0.11,0.1,0.25,0.84,0.12,0.02,0.06,0.03],[8.75,-62.38,0.43,0.37,0.11,0.14,0.24,0.82,0.13,0.02,0.06,0.03],[8.75,-11.79,0.36,0.46,0.09,0.02,0.26,0.85,0.12,0.02,0.07,0.03],[8.75,-9.26,0.35,0.52,0.09,0.02,0.26,0.86,0.12,0.02,0.07,0.03],[8.75,-6.73,0.35,0.53,0.09,0.02,0.26,0.86,0.12,0.02,0.07,0.03],[8.75,-4.2,0.35,0.56,0.09,0.02,0.27,0.87,0.12,0.02,0.07,0.03],[8.75,-1.67,0.36,0.6,0.08,0.02,0.27,0.88,0.13,0.02,0.07,0.03],[8.75,0.85,0.36,0.62,0.09,0.02,0.27,0.88,0.13,0.02,0.07,0.03],[8.75,3.38,0.36,0.55,0.09,0.02,0.27,0.87,0.12,0.02,0.07,0.03],[8.75,5.91,0.36,0.5,0.1,0.02,0.26,0.86,0.12,0.02,0.06,0.03],[8.75,8.44,0.37,0.52,0.1,0.02,0.26,0.86,0.12,0.02,0.06,0.03],[8.75,10.97,0.36,0.49,0.1,0.02,0.26,0.85,0.12,0.02,0.06,0.03],[8.75,13.5,0.36,0.49,0.1,0.02,0.26,0.85,0.12,0.02,0.06,0.03],[8.75,16.03,0.36,0.46,0.1,0.02,0.26,0.85,0.12,0.02,0.06,0.03],[8.75,18.56,0.36,0.42,0.09,0.02,0.25,0.84,0.12,0.02,0.06,0.03],[8.75,21.09,0.36,0.42,0.09,0.02,0.25,0.84,0.12,0.02,0.06,0.03],[8.75,23.62,0.34,0.41,0.1,0.02,0.25,0.83,0.12,0.02,0.06,0.03],[8.75,26.15,0.34,0.36,0.09,0.02,0.24,0.82,0.12,0.02,0.06,0.03],[8.75,28.68,0.35,0.35,0.09,0.02,0.24,0.82,0.12,0.02,0.06,0.03],[8.75,31.21,0.35,0.36,0.09,0.02,0.24,0.82,0.12,0.02,0.06,0.03],[8.75,33.74,0.36,0.36,0.08,0.02,0.24,0.82,0.12,0.02,0.06,0.03],[8.75,36.27,0.36,0.38,0.09,0.02,0.25,0.83,0.12,0.02,0.06,0.03],[8.75,38.8,0.36,0.35,0.09,0.02,0.24,0.82,0.12,0.02,0.06,0.03],[8.75,41.33,0.36,0.32,0.09,0.02,0.24,0.81,0.12,0.02,0.06,0.03],[8.75,43.86,0.37,0.36,0.08,0.02,0.24,0.82,0.12,0.02,0.06,0.03],[8.75,46.38,0.36,0.41,0.09,0.02,0.25,0.83,0.12,0.02,0.06,0.03],[8.75,48.91,0.35,0.42,0.1,0.02,0.25,0.84,0.12,0.02,0.06,0.03],[8.75,99.5,0.34,0.58,0.09,0.02,0.27,0.87,0.12,0.02,0.06,0.03],[8.75,124.8,0.37,0.45,0.08,0.02,0.26,0.84,0.12,0.02,0.06,0.03],[11.25,-84.41,0.39,0.39,0.12,0.02,0.26,0.83,0.15,0.02,0.09,0.03],[11.25,-74.22,0.38,0.48,0.16,0.02,0.27,0.85,0.16,0.02,0.08,0.03],[11.25,-69.12,0.36,0.46,0.16,0.02,0.26,0.84,0.16,0.02,0.08,0.03],[11.25,-13.04,0.37,0.41,0.12,0.02,0.26,0.83,0.16,0.02,0.09,0.03],[11.25,-10.49,0.37,0.44,0.12,0.02,0.26,0.84,0.16,0.02,0.09,0.03],[11.25,-7.94,0.37,0.48,0.11,0.02,0.27,0.85,0.16,0.02,0.09,0.03],[11.25,-5.4,0.37,0.54,0.11,0.02,0.27,0.86,0.16,0.02,0.09,0.03],[11.25,-2.85,0.38,0.58,0.1,0.02,0.28,0.87,0.16,0.02,0.09,0.03],[11.25,-0.3,0.39,0.61,0.09,0.02,0.28,0.88,0.16,0.02,0.09,0.03],[11.25,2.25,0.38,0.59,0.1,0.02,0.28,0.87,0.16,0.02,0.09,0.03],[11.25,4.8,0.37,0.52,0.13,0.02,0.27,0.86,0.16,0.02,0.09,0.03],[11.25,7.35,0.37,0.49,0.15,0.02,0.27,0.85,0.16,0.02,0.09,0.03],[11.25,9.9,0.38,0.46,0.14,0.02,0.27,0.84,0.16,0.02,0.08,0.03],[11.25,12.45,0.37,0.44,0.14,0.02,0.26,0.84,0.16,0.02,0.08,0.03],[11.25,15,0.37,0.44,0.14,0.02,0.26,0.84,0.16,0.02,0.08,0.03],[11.25,17.55,0.38,0.42,0.13,0.02,0.26,0.83,0.16,0.02,0.08,0.03],[11.25,20.09,0.37,0.42,0.12,0.02,0.26,0.83,0.16,0.02,0.08,0.03],[11.25,22.64,0.36,0.39,0.14,0.02,0.26,0.82,0.16,0.02,0.08,0.03],[11.25,25.19,0.36,0.37,0.15,0.02,0.25,0.82,0.16,0.02,0.08,0.03],[11.25,27.74,0.37,0.35,0.12,0.02,0.25,0.82,0.16,0.02,0.08,0.03],[11.25,30.29,0.37,0.36,0.1,0.02,0.25,0.82,0.16,0.02,0.08,0.03],[11.25,32.84,0.37,0.37,0.1,0.02,0.25,0.82,0.16,0.02,0.08,0.03],[11.25,35.39,0.37,0.41,0.1,0.02,0.26,0.83,0.16,0.02,0.08,0.03],[11.25,37.94,0.36,0.42,0.11,0.02,0.26,0.83,0.16,0.02,0.08,0.03],[11.25,40.49,0.37,0.4,0.11,0.02,0.26,0.83,0.16,0.02,0.08,0.03],[11.25,43.04,0.38,0.42,0.11,0.02,0.26,0.83,0.16,0.02,0.08,0.03],[11.25,48.13,0.43,0.44,0.14,0.08,0.26,0.84,0.16,0.02,0.08,0.03],[11.25,50.68,0.36,0.44,0.16,0.02,0.26,0.84,0.16,0.02,0.08,0.03],[11.25,76.17,0.41,0.53,0.13,0.08,0.27,0.86,0.16,0.02,0.08,0.03],[11.25,78.72,0.36,0.52,0.13,0.02,0.27,0.86,0.16,0.02,0.09,0.03],[11.25,99.11,0.34,0.56,0.1,0.02,0.28,0.87,0.16,0.02,0.08,0.03],[11.25,104.21,0.35,0.47,0.09,0.02,0.27,0.85,0.16,0.02,0.08,0.03],[11.25,106.76,0.41,0.45,0.09,0.08,0.26,0.84,0.16,0.02,0.08,0.03],[11.25,119.5,0.35,0.39,0.08,0.02,0.26,0.83,0.16,0.02,0.09,0.03],[11.25,122.05,0.36,0.4,0.08,0.02,0.26,0.83,0.16,0.02,0.09,0.03],[11.25,124.6,0.38,0.42,0.09,0.02,0.26,0.83,0.16,0.02,0.09,0.03],[13.75,-88.63,0.5,0.33,0.19,0.15,0.27,0.81,0.22,0.02,0.12,0.03],[13.75,-86.06,0.41,0.39,0.2,0.02,0.27,0.82,0.22,0.02,0.12,0.03],[13.75,-83.48,0.41,0.43,0.21,0.02,0.28,0.83,0.22,0.02,0.12,0.03],[13.75,-16.57,0.4,0.38,0.2,0.02,0.27,0.82,0.22,0.02,0.13,0.03],[13.75,-13.99,0.4,0.41,0.2,0.02,0.28,0.83,0.22,0.02,0.13,0.03],[13.75,-11.42,0.4,0.41,0.18,0.02,0.28,0.83,0.23,0.02,0.13,0.03],[13.75,-8.85,0.4,0.46,0.17,0.02,0.28,0.84,0.23,0.02,0.14,0.03],[13.75,-6.27,0.4,0.54,0.17,0.02,0.29,0.86,0.24,0.02,0.14,0.03],[13.75,-3.7,0.4,0.6,0.18,0.02,0.3,0.87,0.24,0.02,0.14,0.03],[13.75,-1.12,0.41,0.62,0.17,0.02,0.3,0.87,0.24,0.02,0.14,0.03],[13.75,1.45,0.41,0.6,0.18,0.02,0.3,0.87,0.24,0.02,0.14,0.03],[13.75,4.02,0.4,0.55,0.23,0.02,0.29,0.86,0.23,0.02,0.13,0.03],[13.75,6.6,0.4,0.46,0.24,0.02,0.28,0.84,0.23,0.02,0.13,0.03],[13.75,9.17,0.4,0.38,0.25,0.02,0.27,0.82,0.23,0.02,0.13,0.03],[13.75,11.75,0.39,0.4,0.24,0.02,0.27,0.82,0.23,0.02,0.12,0.03],[13.75,14.32,0.39,0.42,0.23,0.02,0.28,0.83,0.23,0.02,0.11,0.03],[13.75,16.89,0.39,0.43,0.21,0.02,0.28,0.83,0.23,0.02,0.12,0.03],[13.75,19.47,0.39,0.42,0.2,0.02,0.28,0.83,0.23,0.02,0.12,0.03],[13.75,22.04,0.38,0.38,0.22,0.02,0.27,0.82,0.23,0.02,0.12,0.03],[13.75,24.61,0.38,0.38,0.23,0.02,0.27,0.82,0.23,0.02,0.12,0.03],[13.75,27.19,0.38,0.39,0.21,0.02,0.27,0.82,0.24,0.02,0.12,0.03],[13.75,29.76,0.39,0.37,0.17,0.02,0.27,0.82,0.24,0.02,0.11,0.03],[13.75,32.34,0.39,0.38,0.16,0.02,0.27,0.82,0.23,0.02,0.1,0.03],[13.75,34.91,0.38,0.42,0.17,0.02,0.28,0.83,0.23,0.02,0.1,0.03],[13.75,37.48,0.38,0.46,0.17,0.02,0.28,0.84,0.23,0.02,0.1,0.03],[13.75,40.06,0.38,0.5,0.18,0.02,0.29,0.85,0.23,0.02,0.1,0.03],[13.75,45.2,0.49,0.53,0.21,0.14,0.29,0.86,0.23,0.02,0.11,0.03],[13.75,76.09,0.48,0.5,0.18,0.18,0.29,0.85,0.23,0.02,0.11,0.03],[13.75,78.66,0.4,0.5,0.16,0.04,0.29,0.85,0.23,0.02,0.12,0.03],[13.75,99.25,0.35,0.49,0.1,0.02,0.29,0.85,0.23,0.02,0.11,0.03],[13.75,101.83,0.36,0.48,0.09,0.02,0.28,0.84,0.23,0.02,0.11,0.03],[13.75,104.4,0.37,0.47,0.08,0.02,0.28,0.84,0.23,0.02,0.11,0.03],[13.75,106.97,0.39,0.44,0.09,0.04,0.28,0.84,0.23,0.02,0.12,0.03],[13.75,122.42,0.38,0.45,0.08,0.02,0.28,0.84,0.22,0.02,0.12,0.03],[16.25,-97.97,0.45,0.49,0.3,0.03,0.31,0.84,0.33,0.02,0.16,0.03],[16.25,-95.37,0.43,0.44,0.34,0.02,0.31,0.83,0.33,0.02,0.17,0.03],[16.25,-92.76,0.45,0.4,0.28,0.03,0.3,0.82,0.33,0.02,0.16,0.03],[16.25,-90.16,0.47,0.37,0.29,0.04,0.3,0.81,0.33,0.02,0.16,0.03],[16.25,-14.64,0.44,0.35,0.32,0.02,0.3,0.81,0.33,0.02,0.19,0.03],[16.25,-12.04,0.45,0.41,0.29,0.02,0.3,0.82,0.33,0.02,0.19,0.03],[16.25,-9.44,0.45,0.45,0.3,0.02,0.31,0.83,0.33,0.02,0.2,0.03],[16.25,-6.83,0.45,0.53,0.33,0.02,0.32,0.85,0.34,0.02,0.21,0.03],[16.25,-4.23,0.45,0.57,0.34,0.02,0.32,0.86,0.35,0.02,0.22,0.03],[16.25,-1.62,0.44,0.6,0.36,0.02,0.32,0.86,0.35,0.02,0.21,0.03],[16.25,0.98,0.44,0.6,0.38,0.02,0.33,0.87,0.35,0.02,0.21,0.03],[16.25,3.58,0.44,0.53,0.41,0.02,0.32,0.85,0.35,0.02,0.2,0.03],[16.25,6.19,0.44,0.46,0.41,0.02,0.31,0.83,0.34,0.02,0.2,0.03],[16.25,8.79,0.43,0.39,0.41,0.02,0.3,0.82,0.34,0.02,0.2,0.03],[16.25,11.4,0.43,0.37,0.41,0.02,0.3,0.81,0.33,0.02,0.2,0.03],[16.25,14,0.42,0.39,0.41,0.02,0.3,0.82,0.34,0.02,0.19,0.03],[16.25,16.6,0.42,0.43,0.39,0.02,0.31,0.83,0.34,0.02,0.2,0.03],[16.25,19.21,0.42,0.44,0.37,0.02,0.31,0.83,0.34,0.02,0.2,0.03],[16.25,21.81,0.42,0.41,0.36,0.02,0.3,0.82,0.35,0.02,0.2,0.03],[16.25,24.42,0.42,0.39,0.37,0.02,0.3,0.82,0.35,0.02,0.19,0.03],[16.25,27.02,0.41,0.41,0.38,0.02,0.3,0.82,0.35,0.02,0.19,0.03],[16.25,29.62,0.42,0.41,0.37,0.02,0.3,0.82,0.35,0.02,0.16,0.03],[16.25,32.23,0.41,0.44,0.37,0.02,0.31,0.83,0.35,0.02,0.15,0.03],[16.25,34.83,0.41,0.46,0.34,0.02,0.31,0.83,0.35,0.02,0.14,0.03],[16.25,37.44,0.41,0.5,0.28,0.02,0.31,0.84,0.35,0.02,0.14,0.03],[16.25,45.25,0.46,0.64,0.41,0.06,0.33,0.87,0.34,0.02,0.16,0.03],[16.25,47.85,0.47,0.62,0.41,0.08,0.33,0.87,0.33,0.02,0.15,0.03],[16.25,50.46,0.42,0.6,0.41,0.02,0.32,0.86,0.33,0.02,0.14,0.03],[16.25,73.89,0.56,0.45,0.3,0.34,0.31,0.83,0.34,0.02,0.14,0.03],[16.25,76.5,0.53,0.47,0.18,0.22,0.31,0.84,0.34,0.02,0.15,0.03],[16.25,79.1,0.51,0.5,0.12,0.2,0.31,0.84,0.34,0.02,0.16,0.03],[16.25,94.73,0.37,0.61,0.08,0.02,0.33,0.87,0.34,0.02,0.17,0.03],[16.25,99.93,0.38,0.47,0.11,0.02,0.31,0.84,0.34,0.02,0.17,0.03],[16.25,102.54,0.39,0.45,0.12,0.02,0.31,0.83,0.34,0.02,0.17,0.03],[16.25,105.14,0.4,0.41,0.08,0.02,0.3,0.82,0.34,0.02,0.17,0.03],[16.25,107.75,0.4,0.44,0.08,0.02,0.31,0.83,0.33,0.02,0.18,0.03],[16.25,120.77,0.4,0.51,0.08,0.02,0.31,0.84,0.32,0.02,0.17,0.03],[18.75,-102.12,0.56,0.5,0.44,0.17,0.35,0.84,0.47,0.02,0.23,0.03],[18.75,-99.48,0.63,0.5,0.46,0.36,0.35,0.84,0.47,0.02,0.23,0.03],[18.75,-96.84,0.58,0.48,0.53,0.22,0.35,0.83,0.46,0.02,0.23,0.03],[18.75,-91.56,0.51,0.41,0.5,0.06,0.34,0.82,0.45,0.02,0.2,0.03],[18.75,-88.92,0.48,0.4,0.49,0.02,0.34,0.81,0.45,0.02,0.19,0.03],[18.75,-70.44,0.49,0.56,0.53,0.02,0.35,0.85,0.49,0.02,0.22,0.03],[18.75,-14.99,0.47,0.3,0.47,0.02,0.32,0.79,0.46,0.02,0.26,0.03],[18.75,-12.35,0.48,0.34,0.42,0.02,0.33,0.8,0.46,0.02,0.26,0.03],[18.75,-9.71,0.49,0.39,0.49,0.02,0.33,0.81,0.47,0.02,0.28,0.03],[18.75,-7.07,0.49,0.49,0.56,0.02,0.35,0.83,0.48,0.02,0.3,0.03],[18.75,-4.43,0.5,0.56,0.58,0.02,0.35,0.85,0.48,0.02,0.3,0.03],[18.75,-1.79,0.48,0.58,0.59,0.02,0.36,0.85,0.48,0.02,0.29,0.03],[18.75,0.85,0.48,0.57,0.6,0.02,0.36,0.85,0.48,0.02,0.28,0.03],[18.75,3.49,0.48,0.52,0.6,0.02,0.35,0.84,0.48,0.02,0.29,0.03],[18.75,6.13,0.48,0.47,0.6,0.02,0.34,0.83,0.48,0.02,0.3,0.03],[18.75,8.77,0.47,0.41,0.6,0.02,0.34,0.82,0.47,0.02,0.31,0.03],[18.75,11.41,0.46,0.39,0.6,0.02,0.33,0.81,0.47,0.02,0.3,0.03],[18.75,14.05,0.45,0.35,0.6,0.02,0.33,0.8,0.47,0.02,0.31,0.03],[18.75,16.69,0.45,0.37,0.6,0.02,0.33,0.81,0.47,0.02,0.31,0.03],[18.75,19.33,0.45,0.46,0.59,0.02,0.34,0.83,0.48,0.02,0.31,0.03],[18.75,21.97,0.45,0.46,0.57,0.02,0.34,0.83,0.5,0.02,0.31,0.03],[18.75,24.61,0.46,0.42,0.57,0.02,0.34,0.82,0.5,0.02,0.3,0.03],[18.75,27.25,0.45,0.4,0.59,0.02,0.34,0.81,0.5,0.02,0.28,0.03],[18.75,29.89,0.46,0.45,0.6,0.02,0.34,0.82,0.5,0.02,0.26,0.03],[18.75,32.53,0.45,0.48,0.6,0.02,0.35,0.83,0.5,0.02,0.23,0.03],[18.75,35.17,0.45,0.5,0.58,0.02,0.35,0.84,0.5,0.02,0.2,0.03],[18.75,43.09,0.46,0.68,0.6,0.03,0.37,0.88,0.49,0.02,0.21,0.03],[18.75,45.73,0.49,0.71,0.6,0.06,0.37,0.88,0.49,0.02,0.23,0.03],[18.75,48.37,0.47,0.65,0.6,0.03,0.36,0.87,0.48,0.02,0.22,0.03],[18.75,51.01,0.45,0.62,0.6,0.02,0.36,0.86,0.47,0.02,0.18,0.03],[18.75,53.65,0.45,0.61,0.6,0.02,0.36,0.86,0.46,0.02,0.18,0.03],[18.75,56.29,0.46,0.63,0.6,0.05,0.36,0.86,0.45,0.02,0.18,0.03],[18.75,74.77,0.52,0.44,0.33,0.14,0.34,0.82,0.47,0.02,0.19,0.03],[18.75,77.41,0.56,0.45,0.14,0.22,0.34,0.83,0.48,0.02,0.22,0.03],[18.75,80.05,0.44,0.47,0.11,0.04,0.35,0.83,0.48,0.02,0.23,0.03],[18.75,82.69,0.41,0.57,0.08,0.02,0.36,0.85,0.49,0.02,0.22,0.03],[18.75,95.89,0.42,0.62,0.08,0.02,0.36,0.86,0.5,0.02,0.23,0.03],[18.75,98.53,0.42,0.49,0.09,0.02,0.35,0.83,0.5,0.02,0.24,0.03],[18.75,101.17,0.41,0.4,0.12,0.02,0.34,0.81,0.5,0.02,0.23,0.03],[18.75,103.81,0.41,0.38,0.1,0.02,0.33,0.81,0.49,0.02,0.24,0.03],[18.75,109.09,0.44,0.4,0.08,0.02,0.34,0.81,0.47,0.02,0.25,0.03],[21.25,-103.55,0.61,0.5,0.68,0.16,0.38,0.83,0.6,0.02,0.3,0.03],[21.25,-100.87,0.77,0.49,0.69,0.69,0.38,0.83,0.6,0.02,0.3,0.03],[21.25,-98.19,0.79,0.48,0.67,0.84,0.38,0.83,0.6,0.02,0.3,0.03],[21.25,-87.46,0.56,0.43,0.77,0.11,0.37,0.81,0.57,0.02,0.25,0.03],[21.25,-76.73,0.52,0.43,0.75,0.02,0.37,0.81,0.6,0.02,0.29,0.03],[21.25,-15.03,0.48,0.3,0.42,0.02,0.36,0.78,0.59,0.02,0.32,0.03],[21.25,-12.35,0.49,0.32,0.51,0.02,0.36,0.79,0.59,0.02,0.33,0.03],[21.25,-9.67,0.51,0.35,0.65,0.02,0.36,0.79,0.59,0.02,0.36,0.03],[21.25,-6.99,0.53,0.44,0.79,0.02,0.37,0.82,0.61,0.02,0.37,0.03],[21.25,-4.3,0.53,0.49,0.79,0.02,0.38,0.83,0.61,0.02,0.38,0.03],[21.25,-1.62,0.52,0.52,0.79,0.02,0.38,0.83,0.61,0.02,0.36,0.03],[21.25,1.06,0.51,0.52,0.79,0.02,0.38,0.84,0.6,0.02,0.36,0.03],[21.25,3.74,0.52,0.46,0.79,0.02,0.38,0.82,0.61,0.02,0.38,0.03],[21.25,6.43,0.5,0.41,0.79,0.02,0.37,0.81,0.61,0.02,0.4,0.03],[21.25,9.11,0.49,0.41,0.79,0.02,0.37,0.81,0.6,0.02,0.41,0.03],[21.25,11.79,0.48,0.38,0.79,0.02,0.37,0.8,0.6,0.02,0.4,0.03],[21.25,14.47,0.49,0.34,0.79,0.02,0.36,0.79,0.6,0.02,0.41,0.03],[21.25,17.15,0.48,0.38,0.79,0.02,0.37,0.8,0.61,0.02,0.41,0.03],[21.25,19.84,0.48,0.42,0.75,0.02,0.37,0.81,0.62,0.02,0.41,0.03],[21.25,22.52,0.48,0.41,0.77,0.02,0.37,0.81,0.64,0.02,0.42,0.03],[21.25,25.2,0.49,0.39,0.78,0.02,0.37,0.81,0.65,0.02,0.41,0.03],[21.25,27.88,0.49,0.39,0.79,0.02,0.37,0.8,0.65,0.02,0.37,0.03],[21.25,30.57,0.49,0.44,0.79,0.02,0.37,0.82,0.65,0.02,0.32,0.03],[21.25,33.25,0.5,0.44,0.79,0.02,0.37,0.82,0.64,0.02,0.29,0.03],[21.25,35.93,0.5,0.5,0.79,0.02,0.38,0.83,0.63,0.02,0.29,0.03],[21.25,41.3,0.49,0.65,0.79,0.02,0.4,0.86,0.62,0.02,0.26,0.03],[21.25,43.98,0.48,0.7,0.79,0.02,0.4,0.87,0.63,0.02,0.28,0.03],[21.25,46.66,0.49,0.7,0.79,0.02,0.4,0.87,0.63,0.02,0.27,0.03],[21.25,49.34,0.48,0.65,0.79,0.02,0.4,0.86,0.61,0.02,0.26,0.03],[21.25,52.03,0.48,0.6,0.79,0.02,0.39,0.85,0.6,0.02,0.23,0.03],[21.25,54.71,0.48,0.62,0.79,0.02,0.39,0.86,0.59,0.02,0.23,0.03],[21.25,57.39,0.47,0.6,0.79,0.02,0.39,0.85,0.59,0.02,0.25,0.03],[21.25,70.8,0.49,0.36,0.66,0.12,0.36,0.8,0.59,0.02,0.2,0.03],[21.25,73.48,0.51,0.42,0.48,0.12,0.37,0.81,0.6,0.02,0.24,0.03],[21.25,76.17,0.55,0.46,0.37,0.18,0.38,0.82,0.61,0.02,0.26,0.03],[21.25,78.85,0.44,0.49,0.23,0.02,0.38,0.83,0.62,0.02,0.29,0.03],[21.25,81.53,0.44,0.53,0.1,0.02,0.39,0.84,0.63,0.02,0.3,0.03],[21.25,84.21,0.44,0.61,0.09,0.02,0.39,0.85,0.63,0.02,0.3,0.03],[21.25,86.9,0.48,0.64,0.08,0.02,0.4,0.86,0.63,0.02,0.32,0.03],[21.25,92.26,0.48,0.67,0.08,0.02,0.4,0.87,0.64,0.02,0.32,0.03],[21.25,94.94,0.47,0.61,0.08,0.02,0.39,0.85,0.65,0.02,0.31,0.03],[21.25,97.63,0.47,0.5,0.08,0.02,0.38,0.83,0.65,0.02,0.29,0.03],[21.25,100.31,0.45,0.41,0.08,0.02,0.37,0.81,0.65,0.02,0.3,0.03],[21.25,102.99,0.43,0.36,0.08,0.02,0.36,0.8,0.64,0.02,0.28,0.03],[21.25,105.67,0.43,0.37,0.08,0.02,0.37,0.8,0.63,0.02,0.29,0.03],[23.75,-110.35,0.53,0.44,0.52,0.02,0.4,0.81,0.68,0.02,0.31,0.03],[23.75,-104.89,0.62,0.45,0.77,0.09,0.4,0.81,0.68,0.02,0.31,0.03],[23.75,-102.16,0.81,0.45,0.74,0.67,0.4,0.81,0.68,0.02,0.34,0.03],[23.75,-99.43,0.84,0.44,0.75,0.87,0.4,0.81,0.67,0.02,0.35,0.03],[23.75,-14.76,0.48,0.36,0.46,0.02,0.39,0.79,0.66,0.02,0.33,0.03],[23.75,-12.02,0.49,0.35,0.63,0.02,0.38,0.79,0.67,0.02,0.36,0.03],[23.75,-9.29,0.53,0.38,0.77,0.02,0.39,0.79,0.68,0.02,0.38,0.03],[23.75,-6.56,0.56,0.41,0.91,0.02,0.39,0.8,0.69,0.02,0.4,0.03],[23.75,-3.83,0.55,0.44,0.91,0.02,0.4,0.81,0.69,0.02,0.42,0.03],[23.75,-1.1,0.59,0.48,0.91,0.06,0.4,0.82,0.68,0.02,0.4,0.03],[23.75,1.63,0.64,0.46,0.91,0.16,0.4,0.81,0.68,0.02,0.41,0.03],[23.75,4.36,0.63,0.39,0.91,0.17,0.39,0.8,0.68,0.02,0.47,0.03],[23.75,7.09,0.57,0.37,0.91,0.1,0.39,0.79,0.68,0.02,0.48,0.03],[23.75,9.83,0.51,0.4,0.91,0.02,0.39,0.8,0.68,0.02,0.47,0.03],[23.75,12.56,0.51,0.35,0.91,0.02,0.38,0.79,0.68,0.02,0.46,0.03],[23.75,15.29,0.5,0.35,0.91,0.02,0.38,0.79,0.69,0.02,0.45,0.03],[23.75,18.02,0.49,0.35,0.88,0.02,0.38,0.79,0.7,0.02,0.45,0.03],[23.75,20.75,0.51,0.33,0.86,0.02,0.38,0.78,0.71,0.02,0.47,0.03],[23.75,23.48,0.51,0.37,0.91,0.02,0.39,0.79,0.72,0.02,0.47,0.03],[23.75,26.21,0.52,0.38,0.91,0.02,0.39,0.79,0.73,0.02,0.45,0.03],[23.75,28.95,0.51,0.39,0.91,0.02,0.39,0.8,0.74,0.02,0.39,0.03],[23.75,31.68,0.52,0.42,0.91,0.02,0.39,0.8,0.74,0.02,0.35,0.03],[23.75,34.41,0.53,0.46,0.91,0.02,0.4,0.81,0.72,0.02,0.35,0.03],[23.75,39.87,0.53,0.54,0.91,0.02,0.41,0.83,0.71,0.02,0.33,0.03],[23.75,42.6,0.53,0.63,0.91,0.02,0.42,0.85,0.71,0.02,0.3,0.03],[23.75,45.33,0.51,0.66,0.91,0.02,0.42,0.86,0.71,0.02,0.28,0.03],[23.75,48.06,0.5,0.68,0.9,0.02,0.42,0.86,0.71,0.02,0.29,0.03],[23.75,50.8,0.51,0.63,0.91,0.02,0.42,0.85,0.7,0.02,0.31,0.03],[23.75,53.53,0.5,0.56,0.91,0.02,0.41,0.83,0.68,0.02,0.29,0.03],[23.75,56.26,0.5,0.57,0.91,0.02,0.41,0.84,0.67,0.02,0.29,0.03],[23.75,69.91,0.43,0.44,0.81,0.02,0.4,0.81,0.68,0.02,0.23,0.03],[23.75,72.65,0.43,0.43,0.61,0.02,0.39,0.81,0.68,0.02,0.28,0.03],[23.75,75.38,0.43,0.46,0.55,0.02,0.4,0.81,0.69,0.02,0.32,0.03],[23.75,78.11,0.45,0.5,0.46,0.02,0.4,0.82,0.69,0.02,0.32,0.03],[23.75,80.84,0.46,0.53,0.24,0.02,0.41,0.83,0.71,0.02,0.33,0.03],[23.75,83.57,0.47,0.54,0.08,0.02,0.41,0.83,0.73,0.02,0.33,0.03],[23.75,86.3,0.5,0.59,0.08,0.02,0.41,0.84,0.74,0.02,0.35,0.03],[23.75,89.03,0.52,0.65,0.08,0.02,0.42,0.85,0.74,0.02,0.42,0.03],[23.75,91.77,0.53,0.63,0.08,0.02,0.42,0.85,0.75,0.02,0.42,0.03],[23.75,94.5,0.52,0.53,0.08,0.02,0.41,0.83,0.75,0.02,0.37,0.03],[23.75,97.23,0.49,0.44,0.08,0.02,0.4,0.81,0.74,0.02,0.34,0.03],[23.75,99.96,0.47,0.41,0.08,0.02,0.39,0.8,0.74,0.02,0.32,0.03],[23.75,102.69,0.45,0.35,0.08,0.02,0.38,0.79,0.74,0.02,0.34,0.03],[23.75,105.42,0.44,0.36,0.08,0.02,0.38,0.79,0.72,0.02,0.33,0.03],[23.75,108.15,0.45,0.34,0.08,0.02,0.38,0.78,0.7,0.02,0.35,0.03],[23.75,110.88,0.47,0.38,0.08,0.02,0.39,0.79,0.67,0.02,0.37,0.03],[23.75,113.62,0.49,0.4,0.08,0.02,0.39,0.8,0.64,0.02,0.36,0.03],[23.75,116.35,0.5,0.39,0.08,0.02,0.39,0.8,0.63,0.02,0.32,0.03],[26.25,-111.71,0.53,0.43,0.4,0.02,0.39,0.8,0.68,0.02,0.29,0.03],[26.25,-108.92,0.54,0.42,0.5,0.02,0.39,0.8,0.68,0.02,0.3,0.03],[26.25,-106.13,0.59,0.47,0.77,0.04,0.4,0.81,0.68,0.02,0.32,0.03],[26.25,-103.34,0.79,0.49,0.81,0.57,0.4,0.81,0.69,0.02,0.32,0.03],[26.25,-100.56,0.84,0.48,0.88,0.78,0.4,0.81,0.68,0.02,0.34,0.03],[26.25,-97.77,0.84,0.46,0.91,0.82,0.4,0.81,0.67,0.02,0.35,0.03],[26.25,-81.05,0.52,0.4,0.91,0.02,0.39,0.79,0.64,0.02,0.32,0.03],[26.25,-14.15,0.49,0.42,0.66,0.02,0.39,0.8,0.66,0.02,0.31,0.03],[26.25,-11.36,0.5,0.4,0.66,0.02,0.39,0.79,0.67,0.02,0.34,0.03],[26.25,-8.57,0.51,0.4,0.81,0.02,0.39,0.79,0.68,0.02,0.36,0.03],[26.25,-5.78,0.52,0.42,0.91,0.02,0.39,0.8,0.69,0.02,0.4,0.03],[26.25,-3,0.62,0.42,0.91,0.13,0.39,0.8,0.69,0.02,0.42,0.03],[26.25,-0.21,0.74,0.44,0.91,0.4,0.4,0.8,0.68,0.02,0.42,0.03],[26.25,2.58,0.68,0.39,0.91,0.28,0.39,0.79,0.68,0.02,0.43,0.03],[26.25,5.37,0.7,0.36,0.91,0.4,0.39,0.78,0.67,0.02,0.45,0.03],[26.25,8.15,0.57,0.37,0.91,0.1,0.39,0.78,0.67,0.02,0.46,0.03],[26.25,10.94,0.5,0.37,0.91,0.02,0.39,0.78,0.68,0.02,0.44,0.03],[26.25,13.73,0.5,0.31,0.91,0.02,0.38,0.77,0.69,0.02,0.46,0.03],[26.25,16.52,0.5,0.33,0.87,0.02,0.38,0.77,0.7,0.02,0.45,0.03],[26.25,19.3,0.5,0.33,0.87,0.02,0.38,0.77,0.71,0.02,0.46,0.03],[26.25,22.09,0.51,0.32,0.84,0.02,0.38,0.77,0.71,0.02,0.46,0.03],[26.25,24.88,0.51,0.36,0.91,0.02,0.39,0.78,0.71,0.02,0.46,0.03],[26.25,27.67,0.51,0.38,0.91,0.02,0.39,0.79,0.72,0.02,0.41,0.03],[26.25,30.45,0.51,0.41,0.91,0.02,0.39,0.79,0.72,0.02,0.37,0.03],[26.25,33.24,0.54,0.48,0.9,0.02,0.4,0.81,0.73,0.02,0.36,0.03],[26.25,38.82,0.55,0.56,0.9,0.03,0.41,0.83,0.72,0.02,0.32,0.03],[26.25,41.6,0.54,0.6,0.91,0.03,0.41,0.84,0.72,0.02,0.33,0.03],[26.25,44.39,0.52,0.64,0.9,0.02,0.42,0.84,0.71,0.02,0.31,0.03],[26.25,47.18,0.53,0.64,0.91,0.02,0.42,0.85,0.71,0.02,0.31,0.03],[26.25,49.97,0.52,0.6,0.91,0.02,0.41,0.84,0.71,0.02,0.31,0.03],[26.25,58.33,0.53,0.51,0.91,0.02,0.4,0.82,0.69,0.02,0.31,0.03],[26.25,61.12,0.53,0.52,0.91,0.02,0.4,0.82,0.7,0.02,0.31,0.03],[26.25,63.9,0.52,0.53,0.91,0.02,0.41,0.82,0.69,0.02,0.27,0.03],[26.25,66.69,0.48,0.52,0.91,0.02,0.4,0.82,0.69,0.02,0.23,0.03],[26.25,69.48,0.45,0.5,0.9,0.02,0.4,0.82,0.68,0.02,0.23,0.03],[26.25,72.27,0.44,0.49,0.71,0.02,0.4,0.81,0.68,0.02,0.28,0.03],[26.25,75.05,0.43,0.48,0.45,0.02,0.4,0.81,0.69,0.02,0.31,0.03],[26.25,77.84,0.44,0.47,0.28,0.02,0.4,0.81,0.69,0.02,0.32,0.03],[26.25,80.63,0.47,0.5,0.19,0.02,0.4,0.81,0.7,0.02,0.34,0.03],[26.25,83.42,0.5,0.49,0.09,0.02,0.4,0.81,0.72,0.02,0.35,0.03],[26.25,86.2,0.51,0.53,0.08,0.02,0.41,0.82,0.75,0.02,0.37,0.03],[26.25,88.99,0.52,0.57,0.08,0.02,0.41,0.83,0.77,0.02,0.42,0.03],[26.25,91.78,0.53,0.55,0.09,0.02,0.41,0.83,0.77,0.02,0.41,0.03],[26.25,94.57,0.51,0.47,0.08,0.02,0.4,0.81,0.76,0.02,0.38,0.03],[26.25,97.35,0.49,0.42,0.08,0.02,0.39,0.8,0.74,0.02,0.39,0.03],[26.25,100.14,0.48,0.37,0.08,0.02,0.39,0.78,0.74,0.02,0.39,0.03],[26.25,102.93,0.46,0.33,0.08,0.02,0.38,0.77,0.73,0.02,0.39,0.03],[26.25,105.72,0.46,0.34,0.08,0.02,0.38,0.77,0.71,0.02,0.38,0.03],[26.25,108.5,0.47,0.33,0.08,0.02,0.38,0.77,0.68,0.02,0.36,0.03],[26.25,111.29,0.48,0.35,0.08,0.02,0.38,0.78,0.65,0.02,0.36,0.03],[26.25,114.08,0.48,0.34,0.08,0.02,0.38,0.78,0.63,0.02,0.33,0.03],[26.25,116.86,0.5,0.34,0.08,0.02,0.38,0.78,0.63,0.02,0.32,0.03],[26.25,119.65,0.53,0.35,0.08,0.02,0.38,0.78,0.63,0.02,0.32,0.03],[28.75,-110.14,0.54,0.39,0.44,0.03,0.37,0.78,0.6,0.02,0.24,0.03],[28.75,-107.29,0.54,0.42,0.59,0.02,0.37,0.79,0.6,0.02,0.25,0.03],[28.75,-104.43,0.55,0.48,0.72,0.02,0.38,0.8,0.6,0.02,0.27,0.03],[28.75,-101.58,0.6,0.51,0.77,0.09,0.38,0.81,0.59,0.02,0.31,0.03],[28.75,-98.73,0.71,0.52,0.79,0.41,0.38,0.81,0.58,0.02,0.31,0.03],[28.75,-95.88,0.62,0.52,0.79,0.2,0.38,0.81,0.57,0.02,0.3,0.03],[28.75,-81.62,0.58,0.41,0.79,0.13,0.37,0.78,0.57,0.02,0.28,0.03],[28.75,-10.33,0.49,0.49,0.66,0.02,0.38,0.8,0.59,0.02,0.27,0.03],[28.75,-7.48,0.5,0.42,0.74,0.02,0.37,0.79,0.6,0.02,0.31,0.03],[28.75,-4.63,0.57,0.4,0.79,0.09,0.37,0.78,0.6,0.02,0.34,0.03],[28.75,-1.78,0.71,0.41,0.79,0.4,0.37,0.78,0.6,0.02,0.37,0.03],[28.75,1.07,0.73,0.41,0.79,0.46,0.37,0.78,0.6,0.02,0.38,0.03],[28.75,3.92,0.7,0.37,0.79,0.41,0.37,0.77,0.59,0.02,0.36,0.03],[28.75,6.77,0.69,0.36,0.79,0.45,0.36,0.77,0.59,0.02,0.36,0.03],[28.75,9.63,0.58,0.36,0.79,0.15,0.36,0.77,0.6,0.02,0.38,0.03],[28.75,12.48,0.49,0.33,0.79,0.02,0.36,0.76,0.61,0.02,0.4,0.03],[28.75,15.33,0.48,0.3,0.76,0.02,0.36,0.76,0.62,0.02,0.39,0.03],[28.75,18.18,0.48,0.31,0.72,0.02,0.36,0.76,0.62,0.02,0.4,0.03],[28.75,21.03,0.49,0.32,0.66,0.02,0.36,0.76,0.62,0.02,0.41,0.03],[28.75,23.88,0.49,0.33,0.68,0.02,0.36,0.76,0.63,0.02,0.4,0.03],[28.75,26.73,0.5,0.36,0.79,0.02,0.37,0.77,0.63,0.02,0.35,0.03],[28.75,29.59,0.5,0.4,0.73,0.02,0.37,0.78,0.64,0.02,0.32,0.03],[28.75,32.44,0.5,0.49,0.58,0.02,0.38,0.8,0.64,0.02,0.3,0.03],[28.75,35.29,0.52,0.56,0.54,0.02,0.39,0.82,0.64,0.02,0.28,0.03],[28.75,38.14,0.5,0.58,0.65,0.02,0.39,0.82,0.64,0.02,0.26,0.03],[28.75,40.99,0.54,0.6,0.72,0.05,0.39,0.83,0.63,0.02,0.27,0.03],[28.75,43.84,0.5,0.62,0.71,0.02,0.39,0.83,0.62,0.02,0.28,0.03],[28.75,46.7,0.5,0.58,0.74,0.02,0.39,0.82,0.62,0.02,0.3,0.03],[28.75,52.4,0.5,0.43,0.79,0.02,0.37,0.79,0.61,0.02,0.32,0.03],[28.75,55.25,0.5,0.44,0.79,0.02,0.37,0.79,0.61,0.02,0.3,0.03],[28.75,58.1,0.5,0.44,0.79,0.02,0.37,0.79,0.61,0.02,0.29,0.03],[28.75,60.95,0.5,0.46,0.79,0.02,0.38,0.8,0.61,0.02,0.27,0.03],[28.75,63.8,0.49,0.5,0.79,0.02,0.38,0.81,0.61,0.02,0.27,0.03],[28.75,66.66,0.47,0.57,0.79,0.02,0.39,0.82,0.61,0.02,0.24,0.03],[28.75,69.51,0.46,0.55,0.75,0.02,0.39,0.82,0.61,0.02,0.23,0.03],[28.75,72.36,0.44,0.49,0.52,0.02,0.38,0.8,0.6,0.02,0.26,0.03],[28.75,75.21,0.43,0.45,0.24,0.02,0.38,0.79,0.61,0.02,0.29,0.03],[28.75,78.06,0.44,0.45,0.12,0.02,0.38,0.79,0.62,0.02,0.3,0.03],[28.75,80.91,0.46,0.47,0.12,0.02,0.38,0.8,0.63,0.02,0.31,0.03],[28.75,83.77,0.47,0.49,0.15,0.02,0.38,0.8,0.64,0.02,0.32,0.03],[28.75,86.62,0.49,0.47,0.1,0.02,0.38,0.8,0.66,0.02,0.33,0.03],[28.75,89.47,0.55,0.44,0.1,0.07,0.37,0.79,0.67,0.02,0.36,0.03],[28.75,92.32,0.55,0.43,0.1,0.07,0.37,0.79,0.67,0.02,0.35,0.03],[28.75,95.17,0.52,0.41,0.09,0.04,0.37,0.78,0.66,0.02,0.34,0.03],[28.75,98.02,0.5,0.37,0.08,0.03,0.37,0.77,0.65,0.02,0.37,0.03],[28.75,100.87,0.47,0.36,0.08,0.02,0.36,0.77,0.64,0.02,0.38,0.03],[28.75,103.73,0.46,0.32,0.08,0.02,0.36,0.76,0.63,0.02,0.36,0.03],[28.75,106.58,0.46,0.32,0.08,0.02,0.36,0.76,0.61,0.02,0.33,0.03],[28.75,109.43,0.46,0.29,0.08,0.02,0.35,0.75,0.59,0.02,0.31,0.03],[28.75,112.28,0.46,0.29,0.08,0.02,0.36,0.75,0.57,0.02,0.31,0.03],[28.75,115.13,0.48,0.31,0.08,0.02,0.36,0.76,0.56,0.02,0.28,0.03],[28.75,117.98,0.49,0.32,0.08,0.02,0.36,0.76,0.56,0.02,0.26,0.03],[28.75,120.83,0.5,0.35,0.08,0.02,0.36,0.77,0.56,0.02,0.27,0.03],[31.25,-111.28,0.51,0.42,0.42,0.06,0.34,0.78,0.47,0.02,0.19,0.03],[31.25,-108.36,0.53,0.42,0.52,0.06,0.34,0.78,0.47,0.02,0.18,0.03],[31.25,-105.43,0.5,0.46,0.58,0.02,0.34,0.79,0.47,0.02,0.2,0.03],[31.25,-102.51,0.5,0.51,0.6,0.02,0.35,0.8,0.47,0.02,0.24,0.03],[31.25,-99.58,0.49,0.53,0.6,0.02,0.35,0.8,0.46,0.02,0.25,0.03],[31.25,-96.66,0.47,0.52,0.6,0.02,0.35,0.8,0.45,0.02,0.24,0.03],[31.25,-93.73,0.46,0.49,0.6,0.03,0.35,0.79,0.45,0.02,0.24,0.03],[31.25,-90.81,0.59,0.47,0.6,0.37,0.34,0.79,0.45,0.02,0.25,0.03],[31.25,-87.89,0.59,0.47,0.6,0.34,0.34,0.79,0.45,0.02,0.26,0.03],[31.25,-84.96,0.51,0.44,0.6,0.08,0.34,0.78,0.45,0.02,0.27,0.03],[31.25,-82.04,0.52,0.42,0.6,0.09,0.34,0.78,0.45,0.02,0.25,0.03],[31.25,-8.93,0.54,0.48,0.55,0.07,0.35,0.79,0.46,0.02,0.22,0.03],[31.25,-6.01,0.57,0.41,0.6,0.13,0.34,0.77,0.46,0.02,0.24,0.03],[31.25,-3.08,0.68,0.4,0.6,0.43,0.34,0.77,0.46,0.02,0.25,0.03],[31.25,-0.16,0.72,0.39,0.6,0.55,0.33,0.77,0.47,0.02,0.27,0.03],[31.25,2.77,0.65,0.39,0.6,0.35,0.34,0.77,0.47,0.02,0.26,0.03],[31.25,5.69,0.57,0.36,0.6,0.15,0.33,0.76,0.47,0.02,0.28,0.03],[31.25,8.62,0.53,0.35,0.6,0.08,0.33,0.76,0.47,0.02,0.28,0.03],[31.25,11.54,0.46,0.33,0.59,0.02,0.33,0.75,0.47,0.02,0.29,0.03],[31.25,14.46,0.45,0.32,0.58,0.02,0.33,0.75,0.48,0.02,0.3,0.03],[31.25,20.31,0.45,0.32,0.42,0.02,0.33,0.75,0.49,0.02,0.28,0.03],[31.25,23.24,0.46,0.34,0.36,0.02,0.33,0.76,0.49,0.02,0.29,0.03],[31.25,26.16,0.49,0.34,0.44,0.04,0.33,0.76,0.5,0.02,0.27,0.03],[31.25,34.93,0.49,0.55,0.28,0.04,0.35,0.81,0.5,0.02,0.2,0.03],[31.25,37.86,0.46,0.57,0.36,0.02,0.36,0.81,0.49,0.02,0.21,0.03],[31.25,40.78,0.51,0.59,0.45,0.07,0.36,0.81,0.49,0.02,0.21,0.03],[31.25,43.71,0.46,0.62,0.4,0.03,0.36,0.82,0.49,0.02,0.24,0.03],[31.25,46.63,0.45,0.57,0.42,0.02,0.36,0.81,0.48,0.02,0.25,0.03],[31.25,49.56,0.45,0.47,0.51,0.02,0.34,0.79,0.48,0.02,0.25,0.03],[31.25,52.48,0.45,0.41,0.58,0.02,0.34,0.77,0.47,0.02,0.26,0.03],[31.25,55.4,0.45,0.42,0.6,0.02,0.34,0.78,0.47,0.02,0.25,0.03],[31.25,58.33,0.45,0.43,0.6,0.02,0.34,0.78,0.47,0.02,0.23,0.03],[31.25,61.25,0.45,0.47,0.6,0.02,0.35,0.79,0.48,0.02,0.21,0.03],[31.25,64.18,0.44,0.51,0.6,0.02,0.35,0.8,0.48,0.02,0.22,0.03],[31.25,67.1,0.43,0.58,0.58,0.02,0.36,0.81,0.47,0.02,0.21,0.03],[31.25,70.03,0.43,0.54,0.5,0.02,0.35,0.8,0.47,0.02,0.21,0.03],[31.25,72.95,0.42,0.48,0.24,0.02,0.35,0.79,0.47,0.02,0.22,0.03],[31.25,75.87,0.42,0.45,0.09,0.02,0.34,0.78,0.48,0.02,0.24,0.03],[31.25,78.8,0.43,0.45,0.08,0.02,0.34,0.78,0.49,0.02,0.24,0.03],[31.25,81.72,0.43,0.47,0.11,0.02,0.34,0.79,0.5,0.02,0.25,0.03],[31.25,84.65,0.48,0.48,0.12,0.05,0.35,0.79,0.5,0.02,0.25,0.03],[31.25,87.57,0.72,0.41,0.09,0.7,0.34,0.78,0.51,0.02,0.26,0.03],[31.25,90.5,0.76,0.39,0.11,0.86,0.33,0.77,0.51,0.02,0.28,0.03],[31.25,93.42,0.7,0.38,0.1,0.6,0.33,0.77,0.51,0.02,0.27,0.03],[31.25,96.34,0.62,0.37,0.09,0.3,0.33,0.76,0.5,0.02,0.27,0.03],[31.25,99.27,0.47,0.35,0.09,0.03,0.33,0.76,0.5,0.02,0.28,0.03],[31.25,102.19,0.44,0.32,0.08,0.02,0.33,0.75,0.49,0.02,0.28,0.03],[31.25,105.12,0.45,0.3,0.08,0.02,0.32,0.75,0.48,0.02,0.27,0.03],[31.25,108.04,0.44,0.29,0.09,0.02,0.32,0.74,0.46,0.02,0.25,0.03],[31.25,110.97,0.44,0.29,0.09,0.02,0.32,0.74,0.46,0.02,0.24,0.03],[31.25,113.89,0.45,0.3,0.08,0.02,0.32,0.75,0.45,0.02,0.23,0.03],[31.25,116.81,0.45,0.32,0.08,0.02,0.33,0.75,0.44,0.02,0.21,0.03],[31.25,119.74,0.45,0.35,0.08,0.02,0.33,0.76,0.44,0.02,0.2,0.03],[33.75,-118.36,0.42,0.48,0.26,0.02,0.31,0.78,0.33,0.02,0.14,0.03],[33.75,-115.36,0.44,0.5,0.29,0.03,0.31,0.78,0.34,0.02,0.14,0.03],[33.75,-112.35,0.56,0.48,0.36,0.26,0.31,0.78,0.34,0.02,0.13,0.03],[33.75,-109.34,0.58,0.49,0.39,0.31,0.31,0.78,0.34,0.02,0.12,0.03],[33.75,-106.34,0.52,0.52,0.41,0.11,0.32,0.79,0.34,0.02,0.13,0.03],[33.75,-103.33,0.45,0.53,0.41,0.02,0.32,0.79,0.33,0.02,0.15,0.03],[33.75,-100.32,0.44,0.53,0.41,0.02,0.32,0.79,0.33,0.02,0.17,0.03],[33.75,-97.32,0.43,0.5,0.41,0.02,0.31,0.79,0.33,0.02,0.18,0.03],[33.75,-94.31,0.41,0.46,0.39,0.02,0.31,0.78,0.32,0.02,0.18,0.03],[33.75,-91.3,0.43,0.46,0.39,0.05,0.31,0.77,0.32,0.02,0.19,0.03],[33.75,-88.29,0.41,0.45,0.39,0.03,0.31,0.77,0.32,0.02,0.19,0.03],[33.75,-85.29,0.41,0.47,0.41,0.02,0.31,0.78,0.32,0.02,0.2,0.03],[33.75,-82.28,0.42,0.46,0.41,0.02,0.31,0.77,0.32,0.02,0.19,0.03],[33.75,-79.27,0.45,0.46,0.41,0.02,0.31,0.78,0.33,0.02,0.18,0.03],[33.75,-7.11,0.57,0.44,0.38,0.24,0.31,0.77,0.33,0.02,0.17,0.03],[33.75,-4.11,0.55,0.39,0.41,0.19,0.3,0.76,0.33,0.02,0.18,0.03],[33.75,-1.1,0.62,0.37,0.41,0.37,0.3,0.75,0.33,0.02,0.18,0.03],[33.75,1.91,0.56,0.37,0.41,0.21,0.3,0.75,0.33,0.02,0.19,0.03],[33.75,4.91,0.44,0.38,0.41,0.02,0.3,0.76,0.33,0.02,0.2,0.03],[33.75,7.92,0.43,0.36,0.41,0.02,0.3,0.75,0.33,0.02,0.19,0.03],[33.75,37.99,0.41,0.52,0.19,0.02,0.32,0.79,0.35,0.02,0.14,0.03],[33.75,40.99,0.41,0.58,0.27,0.02,0.32,0.8,0.35,0.02,0.16,0.03],[33.75,44,0.4,0.58,0.25,0.02,0.32,0.8,0.35,0.02,0.18,0.03],[33.75,47.01,0.4,0.54,0.22,0.02,0.32,0.79,0.35,0.02,0.18,0.03],[33.75,50.01,0.4,0.52,0.28,0.02,0.32,0.79,0.34,0.02,0.18,0.03],[33.75,53.02,0.4,0.49,0.36,0.02,0.31,0.78,0.33,0.02,0.18,0.03],[33.75,56.03,0.4,0.49,0.38,0.02,0.31,0.78,0.33,0.02,0.17,0.03],[33.75,59.03,0.4,0.49,0.37,0.02,0.31,0.78,0.33,0.02,0.17,0.03],[33.75,62.04,0.4,0.5,0.38,0.02,0.31,0.79,0.33,0.02,0.17,0.03],[33.75,65.05,0.4,0.49,0.39,0.02,0.31,0.78,0.33,0.02,0.17,0.03],[33.75,68.05,0.4,0.51,0.34,0.02,0.31,0.79,0.33,0.02,0.17,0.03],[33.75,71.06,0.41,0.5,0.23,0.02,0.31,0.78,0.33,0.02,0.15,0.03],[33.75,74.07,0.41,0.47,0.1,0.02,0.31,0.78,0.34,0.02,0.15,0.03],[33.75,77.07,0.41,0.48,0.08,0.02,0.31,0.78,0.34,0.02,0.16,0.03],[33.75,80.08,0.41,0.5,0.08,0.02,0.31,0.78,0.35,0.02,0.16,0.03],[33.75,83.09,0.41,0.48,0.08,0.02,0.31,0.78,0.35,0.02,0.16,0.03],[33.75,86.1,0.61,0.44,0.09,0.48,0.31,0.77,0.36,0.02,0.17,0.03],[33.75,89.1,0.71,0.41,0.11,0.87,0.3,0.76,0.36,0.02,0.2,0.03],[33.75,92.11,0.71,0.41,0.11,0.87,0.3,0.76,0.36,0.02,0.19,0.03],[33.75,95.12,0.61,0.39,0.14,0.44,0.3,0.76,0.36,0.02,0.18,0.03],[33.75,98.12,0.49,0.34,0.13,0.12,0.29,0.75,0.36,0.02,0.19,0.03],[33.75,101.13,0.42,0.31,0.1,0.02,0.29,0.74,0.35,0.02,0.19,0.03],[33.75,104.14,0.43,0.29,0.1,0.02,0.29,0.73,0.34,0.02,0.19,0.03],[33.75,107.14,0.43,0.3,0.08,0.02,0.29,0.73,0.33,0.02,0.18,0.03],[33.75,110.15,0.43,0.32,0.08,0.02,0.29,0.74,0.33,0.02,0.17,0.03],[33.75,113.16,0.42,0.34,0.08,0.02,0.29,0.75,0.33,0.02,0.16,0.03],[33.75,116.16,0.42,0.36,0.08,0.02,0.3,0.75,0.32,0.02,0.16,0.03],[33.75,119.17,0.44,0.38,0.08,0.03,0.3,0.76,0.32,0.02,0.17,0.03],[33.75,134.2,0.43,0.37,0.09,0.06,0.3,0.75,0.33,0.02,0.2,0.03],[36.25,-119.55,0.4,0.51,0.17,0.02,0.29,0.78,0.23,0.02,0.09,0.03],[36.25,-116.45,0.4,0.52,0.21,0.03,0.29,0.78,0.23,0.02,0.09,0.03],[36.25,-113.35,0.49,0.51,0.24,0.16,0.29,0.78,0.23,0.02,0.09,0.03],[36.25,-110.25,0.55,0.54,0.26,0.31,0.29,0.78,0.23,0.02,0.08,0.03],[36.25,-107.15,0.49,0.53,0.26,0.13,0.29,0.78,0.23,0.02,0.09,0.03],[36.25,-104.05,0.41,0.5,0.26,0.02,0.29,0.77,0.23,0.02,0.1,0.03],[36.25,-100.95,0.4,0.52,0.26,0.02,0.29,0.78,0.23,0.02,0.11,0.03],[36.25,-97.85,0.39,0.48,0.26,0.02,0.28,0.77,0.22,0.02,0.12,0.03],[36.25,-94.75,0.37,0.45,0.24,0.02,0.28,0.76,0.22,0.02,0.13,0.03],[36.25,-91.65,0.37,0.44,0.21,0.02,0.28,0.76,0.22,0.02,0.13,0.03],[36.25,-88.55,0.38,0.44,0.22,0.02,0.28,0.76,0.22,0.02,0.13,0.03],[36.25,-85.45,0.38,0.45,0.25,0.02,0.28,0.76,0.22,0.02,0.13,0.03],[36.25,-82.35,0.39,0.47,0.25,0.02,0.28,0.77,0.22,0.02,0.13,0.03],[36.25,-79.25,0.41,0.5,0.26,0.02,0.29,0.77,0.22,0.02,0.13,0.03],[36.25,-76.15,0.43,0.45,0.26,0.02,0.28,0.76,0.23,0.02,0.13,0.03],[36.25,1.35,0.55,0.36,0.26,0.24,0.27,0.74,0.23,0.02,0.13,0.03],[36.25,4.45,0.44,0.39,0.26,0.04,0.27,0.75,0.23,0.02,0.13,0.03],[36.25,7.55,0.4,0.39,0.25,0.02,0.27,0.75,0.23,0.02,0.13,0.03],[36.25,32.35,0.51,0.49,0.13,0.23,0.29,0.77,0.24,0.02,0.09,0.03],[36.25,38.55,0.38,0.5,0.15,0.02,0.29,0.77,0.24,0.02,0.11,0.03],[36.25,41.65,0.38,0.51,0.16,0.02,0.29,0.78,0.24,0.02,0.12,0.03],[36.25,44.75,0.37,0.53,0.17,0.02,0.29,0.78,0.24,0.02,0.12,0.03],[36.25,47.85,0.36,0.55,0.18,0.02,0.29,0.78,0.23,0.02,0.12,0.03],[36.25,50.95,0.36,0.57,0.2,0.02,0.29,0.79,0.23,0.02,0.12,0.03],[36.25,54.05,0.36,0.55,0.21,0.02,0.29,0.79,0.23,0.02,0.11,0.03],[36.25,57.15,0.37,0.52,0.19,0.02,0.29,0.78,0.23,0.02,0.11,0.03],[36.25,60.25,0.36,0.53,0.21,0.02,0.29,0.78,0.23,0.02,0.11,0.03],[36.25,63.35,0.37,0.5,0.19,0.02,0.29,0.77,0.23,0.02,0.12,0.03],[36.25,66.45,0.37,0.49,0.17,0.02,0.29,0.77,0.23,0.02,0.12,0.03],[36.25,69.55,0.38,0.5,0.14,0.02,0.29,0.77,0.23,0.02,0.11,0.03],[36.25,72.65,0.39,0.49,0.1,0.02,0.29,0.77,0.23,0.02,0.11,0.03],[36.25,75.75,0.39,0.49,0.08,0.02,0.29,0.77,0.23,0.02,0.11,0.03],[36.25,78.85,0.38,0.46,0.08,0.02,0.28,0.77,0.23,0.02,0.11,0.03],[36.25,81.95,0.39,0.46,0.08,0.02,0.28,0.76,0.23,0.02,0.11,0.03],[36.25,85.05,0.54,0.47,0.09,0.31,0.28,0.77,0.24,0.02,0.12,0.03],[36.25,88.15,0.66,0.46,0.11,0.79,0.28,0.77,0.24,0.02,0.13,0.03],[36.25,91.25,0.66,0.48,0.11,0.8,0.28,0.77,0.24,0.02,0.13,0.03],[36.25,94.35,0.54,0.45,0.14,0.36,0.28,0.76,0.24,0.02,0.12,0.03],[36.25,97.45,0.48,0.4,0.18,0.15,0.27,0.75,0.24,0.02,0.12,0.03],[36.25,100.55,0.4,0.34,0.12,0.02,0.27,0.74,0.23,0.02,0.12,0.03],[36.25,103.65,0.39,0.32,0.09,0.02,0.27,0.73,0.23,0.02,0.12,0.03],[36.25,106.75,0.39,0.34,0.1,0.02,0.27,0.73,0.23,0.02,0.12,0.03],[36.25,109.85,0.39,0.36,0.09,0.02,0.27,0.74,0.22,0.02,0.11,0.03],[36.25,112.95,0.38,0.38,0.08,0.02,0.27,0.74,0.22,0.02,0.11,0.03],[36.25,116.05,0.39,0.37,0.09,0.02,0.27,0.74,0.22,0.02,0.11,0.03],[36.25,119.15,0.39,0.37,0.12,0.02,0.27,0.74,0.22,0.02,0.12,0.03],[36.25,128.45,0.44,0.33,0.13,0.09,0.27,0.73,0.22,0.02,0.12,0.03],[36.25,137.75,0.43,0.44,0.1,0.1,0.28,0.76,0.22,0.02,0.14,0.03],[38.75,-120.7,0.38,0.51,0.12,0.02,0.27,0.76,0.16,0.02,0.07,0.03],[38.75,-117.49,0.38,0.52,0.14,0.02,0.27,0.77,0.16,0.02,0.07,0.03],[38.75,-114.29,0.38,0.55,0.14,0.02,0.27,0.77,0.16,0.02,0.07,0.03],[38.75,-111.08,0.49,0.55,0.16,0.2,0.28,0.77,0.16,0.02,0.07,0.03],[38.75,-107.87,0.39,0.52,0.16,0.02,0.27,0.77,0.16,0.02,0.07,0.03],[38.75,-104.67,0.38,0.49,0.16,0.02,0.27,0.76,0.16,0.02,0.07,0.03],[38.75,-101.46,0.37,0.5,0.16,0.02,0.27,0.76,0.16,0.02,0.07,0.03],[38.75,-98.26,0.36,0.43,0.16,0.02,0.26,0.75,0.16,0.02,0.08,0.03],[38.75,-95.05,0.36,0.42,0.16,0.02,0.26,0.74,0.16,0.02,0.09,0.03],[38.75,-91.85,0.36,0.4,0.14,0.02,0.26,0.74,0.16,0.02,0.09,0.03],[38.75,-88.64,0.36,0.42,0.14,0.02,0.26,0.74,0.16,0.02,0.09,0.03],[38.75,-85.43,0.36,0.44,0.15,0.02,0.26,0.75,0.16,0.02,0.09,0.03],[38.75,-82.23,0.37,0.45,0.16,0.02,0.26,0.75,0.16,0.02,0.09,0.03],[38.75,-79.02,0.39,0.48,0.16,0.02,0.27,0.76,0.16,0.02,0.09,0.03],[38.75,-75.82,0.4,0.45,0.16,0.02,0.26,0.75,0.16,0.02,0.09,0.03],[38.75,-8.5,0.38,0.45,0.13,0.02,0.26,0.75,0.16,0.02,0.08,0.03],[38.75,-5.29,0.38,0.44,0.15,0.02,0.26,0.75,0.16,0.02,0.09,0.03],[38.75,-2.09,0.45,0.39,0.16,0.09,0.26,0.73,0.16,0.02,0.09,0.03],[38.75,26.76,0.43,0.49,0.1,0.1,0.27,0.76,0.16,0.02,0.07,0.03],[38.75,29.97,0.43,0.5,0.11,0.08,0.27,0.76,0.16,0.02,0.07,0.03],[38.75,33.17,0.43,0.5,0.11,0.08,0.27,0.76,0.17,0.02,0.07,0.03],[38.75,36.38,0.37,0.51,0.11,0.02,0.27,0.76,0.17,0.02,0.08,0.03],[38.75,39.58,0.37,0.47,0.12,0.02,0.27,0.75,0.17,0.02,0.08,0.03],[38.75,42.79,0.37,0.47,0.12,0.02,0.27,0.75,0.17,0.02,0.08,0.03],[38.75,46,0.35,0.52,0.13,0.02,0.27,0.77,0.16,0.02,0.09,0.03],[38.75,55.61,0.34,0.59,0.13,0.02,0.28,0.78,0.16,0.02,0.08,0.03],[38.75,58.82,0.34,0.55,0.12,0.02,0.28,0.77,0.16,0.02,0.08,0.03],[38.75,62.02,0.35,0.53,0.12,0.02,0.27,0.77,0.16,0.02,0.08,0.03],[38.75,65.23,0.35,0.51,0.11,0.02,0.27,0.76,0.16,0.02,0.08,0.03],[38.75,68.43,0.36,0.49,0.1,0.02,0.27,0.76,0.16,0.02,0.08,0.03],[38.75,71.64,0.36,0.52,0.1,0.02,0.27,0.77,0.16,0.02,0.08,0.03],[38.75,74.85,0.36,0.5,0.09,0.02,0.27,0.76,0.16,0.02,0.08,0.03],[38.75,78.05,0.37,0.48,0.08,0.02,0.27,0.76,0.16,0.02,0.08,0.03],[38.75,81.26,0.37,0.47,0.08,0.02,0.27,0.76,0.16,0.02,0.08,0.03],[38.75,84.46,0.5,0.47,0.09,0.24,0.27,0.75,0.16,0.02,0.08,0.03],[38.75,87.67,0.61,0.53,0.1,0.65,0.27,0.77,0.16,0.02,0.08,0.03],[38.75,90.87,0.6,0.52,0.11,0.65,0.27,0.77,0.16,0.02,0.09,0.03],[38.75,94.08,0.57,0.51,0.11,0.51,0.27,0.76,0.16,0.02,0.08,0.03],[38.75,97.28,0.5,0.45,0.12,0.26,0.26,0.75,0.16,0.02,0.08,0.03],[38.75,100.49,0.41,0.39,0.11,0.06,0.26,0.74,0.16,0.02,0.08,0.03],[38.75,103.7,0.37,0.36,0.1,0.02,0.25,0.73,0.16,0.02,0.08,0.03],[38.75,106.9,0.37,0.36,0.1,0.02,0.25,0.73,0.16,0.02,0.08,0.03],[38.75,110.11,0.36,0.36,0.1,0.02,0.25,0.73,0.16,0.02,0.08,0.03],[38.75,113.31,0.36,0.33,0.1,0.02,0.25,0.72,0.16,0.02,0.08,0.03],[38.75,116.52,0.37,0.31,0.1,0.02,0.25,0.71,0.16,0.02,0.08,0.03],[38.75,126.14,0.38,0.31,0.13,0.03,0.25,0.72,0.15,0.02,0.08,0.03],[41.25,-121.81,0.37,0.54,0.09,0.02,0.27,0.76,0.12,0.02,0.06,0.03],[41.25,-118.48,0.37,0.49,0.1,0.02,0.26,0.75,0.12,0.02,0.06,0.03],[41.25,-115.16,0.37,0.5,0.1,0.02,0.26,0.75,0.12,0.02,0.06,0.03],[41.25,-111.83,0.37,0.5,0.11,0.03,0.26,0.75,0.12,0.02,0.06,0.03],[41.25,-108.51,0.36,0.53,0.11,0.02,0.26,0.76,0.12,0.02,0.06,0.03],[41.25,-105.18,0.35,0.55,0.11,0.02,0.27,0.76,0.12,0.02,0.06,0.03],[41.25,-101.86,0.36,0.52,0.11,0.02,0.26,0.75,0.12,0.02,0.06,0.03],[41.25,-98.53,0.35,0.44,0.11,0.02,0.25,0.74,0.12,0.02,0.06,0.03],[41.25,-95.21,0.35,0.41,0.11,0.02,0.25,0.73,0.12,0.02,0.06,0.03],[41.25,-91.88,0.35,0.39,0.11,0.02,0.25,0.72,0.12,0.02,0.06,0.03],[41.25,-88.56,0.35,0.38,0.11,0.02,0.25,0.72,0.12,0.02,0.07,0.03],[41.25,-85.23,0.36,0.41,0.11,0.02,0.25,0.73,0.12,0.02,0.07,0.03],[41.25,-81.91,0.37,0.43,0.11,0.02,0.25,0.73,0.12,0.02,0.07,0.03],[41.25,-78.58,0.38,0.45,0.11,0.02,0.26,0.74,0.12,0.02,0.06,0.03],[41.25,-75.26,0.39,0.44,0.11,0.02,0.25,0.74,0.12,0.02,0.06,0.03],[41.25,-8.75,0.36,0.46,0.1,0.02,0.26,0.74,0.12,0.02,0.06,0.03],[41.25,-5.43,0.36,0.48,0.1,0.02,0.26,0.74,0.12,0.02,0.06,0.03],[41.25,-2.1,0.37,0.41,0.1,0.02,0.25,0.73,0.12,0.02,0.06,0.03],[41.25,1.22,0.37,0.39,0.1,0.02,0.25,0.72,0.12,0.02,0.07,0.03],[41.25,14.52,0.35,0.37,0.1,0.02,0.25,0.72,0.12,0.02,0.06,0.03],[41.25,21.17,0.35,0.42,0.09,0.03,0.25,0.73,0.12,0.02,0.06,0.03],[41.25,24.5,0.35,0.53,0.09,0.02,0.26,0.76,0.12,0.02,0.06,0.03],[41.25,27.82,0.37,0.55,0.09,0.02,0.27,0.76,0.13,0.02,0.06,0.03],[41.25,34.47,0.37,0.5,0.1,0.02,0.26,0.75,0.13,0.02,0.06,0.03],[41.25,41.12,0.36,0.47,0.1,0.02,0.26,0.74,0.13,0.02,0.06,0.03],[41.25,44.45,0.36,0.48,0.1,0.02,0.26,0.74,0.13,0.02,0.06,0.03],[41.25,47.77,0.34,0.48,0.1,0.02,0.26,0.74,0.13,0.02,0.06,0.03],[41.25,54.42,0.35,0.6,0.1,0.02,0.27,0.77,0.12,0.02,0.06,0.03],[41.25,57.75,0.35,0.6,0.1,0.02,0.27,0.77,0.12,0.02,0.06,0.03],[41.25,61.08,0.35,0.56,0.1,0.02,0.27,0.76,0.12,0.02,0.06,0.03],[41.25,64.4,0.35,0.53,0.09,0.02,0.26,0.75,0.12,0.02,0.06,0.03],[41.25,67.73,0.35,0.5,0.09,0.02,0.26,0.75,0.12,0.02,0.06,0.03],[41.25,71.05,0.35,0.5,0.09,0.02,0.26,0.75,0.12,0.02,0.06,0.03],[41.25,74.38,0.35,0.5,0.09,0.02,0.26,0.75,0.12,0.02,0.06,0.03],[41.25,77.7,0.35,0.51,0.09,0.02,0.26,0.75,0.12,0.02,0.06,0.03],[41.25,81.03,0.36,0.5,0.09,0.02,0.26,0.75,0.12,0.02,0.06,0.03],[41.25,84.35,0.44,0.48,0.09,0.12,0.26,0.74,0.12,0.02,0.06,0.03],[41.25,87.68,0.59,0.55,0.09,0.61,0.27,0.76,0.12,0.02,0.06,0.03],[41.25,91,0.6,0.55,0.09,0.64,0.27,0.76,0.12,0.02,0.06,0.03],[41.25,94.33,0.57,0.47,0.09,0.52,0.26,0.74,0.12,0.02,0.06,0.03],[41.25,97.65,0.47,0.43,0.1,0.21,0.25,0.73,0.12,0.02,0.06,0.03],[41.25,100.98,0.37,0.43,0.09,0.03,0.25,0.73,0.12,0.02,0.06,0.03],[41.25,104.3,0.36,0.4,0.09,0.02,0.25,0.73,0.12,0.02,0.06,0.03],[41.25,107.63,0.36,0.37,0.09,0.02,0.25,0.72,0.12,0.02,0.06,0.03],[41.25,110.95,0.35,0.32,0.09,0.02,0.24,0.71,0.12,0.02,0.06,0.03],[41.25,114.28,0.35,0.29,0.1,0.02,0.24,0.7,0.12,0.02,0.06,0.03],[41.25,117.6,0.36,0.29,0.1,0.02,0.23,0.7,0.12,0.02,0.06,0.03],[41.25,120.93,0.37,0.29,0.1,0.02,0.23,0.7,0.12,0.02,0.06,0.03],[41.25,124.25,0.39,0.28,0.11,0.04,0.23,0.69,0.12,0.02,0.06,0.03],[41.25,127.58,0.48,0.29,0.1,0.23,0.23,0.7,0.12,0.02,0.06,0.03],[41.25,140.88,0.38,0.41,0.09,0.04,0.25,0.73,0.12,0.02,0.06,0.03],[43.75,-122.9,0.41,0.53,0.08,0.05,0.26,0.74,0.11,0.03,0.05,0.03],[43.75,-119.43,0.37,0.48,0.09,0.02,0.26,0.73,0.11,0.03,0.05,0.03],[43.75,-115.97,0.36,0.48,0.09,0.02,0.25,0.73,0.11,0.03,0.05,0.03],[43.75,-112.51,0.35,0.49,0.09,0.02,0.26,0.73,0.11,0.03,0.05,0.03],[43.75,-109.05,0.35,0.53,0.09,0.02,0.26,0.74,0.11,0.03,0.05,0.03],[43.75,-105.59,0.35,0.57,0.09,0.02,0.27,0.75,0.11,0.03,0.05,0.03],[43.75,-102.13,0.39,0.56,0.09,0.07,0.26,0.75,0.11,0.03,0.05,0.03],[43.75,-98.67,0.35,0.46,0.09,0.02,0.25,0.73,0.11,0.03,0.05,0.03],[43.75,-95.21,0.34,0.4,0.09,0.02,0.25,0.71,0.11,0.03,0.05,0.03],[43.75,-91.75,0.34,0.36,0.09,0.02,0.24,0.7,0.11,0.03,0.05,0.03],[43.75,-88.29,0.35,0.35,0.09,0.02,0.24,0.7,0.11,0.03,0.05,0.03],[43.75,-84.83,0.35,0.37,0.09,0.02,0.24,0.7,0.11,0.03,0.06,0.03],[43.75,-81.37,0.36,0.4,0.09,0.02,0.25,0.71,0.11,0.03,0.05,0.03],[43.75,-77.9,0.36,0.39,0.09,0.02,0.24,0.71,0.11,0.03,0.05,0.03],[43.75,-74.44,0.38,0.39,0.09,0.02,0.24,0.71,0.11,0.03,0.05,0.03],[43.75,-70.98,0.38,0.4,0.08,0.03,0.25,0.71,0.11,0.03,0.05,0.03],[43.75,1.7,0.36,0.41,0.09,0.02,0.25,0.71,0.11,0.03,0.06,0.03],[43.75,5.16,0.35,0.42,0.08,0.02,0.25,0.72,0.11,0.03,0.06,0.03],[43.75,12.08,0.39,0.35,0.08,0.05,0.24,0.7,0.11,0.03,0.05,0.03],[43.75,19,0.35,0.38,0.08,0.02,0.24,0.71,0.11,0.03,0.05,0.03],[43.75,22.46,0.35,0.46,0.08,0.02,0.25,0.73,0.11,0.03,0.05,0.03],[43.75,25.92,0.36,0.54,0.08,0.02,0.26,0.74,0.11,0.03,0.05,0.03],[43.75,39.76,0.37,0.47,0.09,0.02,0.25,0.73,0.11,0.03,0.05,0.03],[43.75,43.23,0.36,0.46,0.09,0.02,0.25,0.73,0.11,0.03,0.06,0.03],[43.75,46.69,0.36,0.49,0.09,0.02,0.26,0.73,0.11,0.03,0.06,0.03],[43.75,53.61,0.39,0.56,0.09,0.04,0.26,0.75,0.11,0.03,0.05,0.03],[43.75,57.07,0.39,0.57,0.09,0.05,0.26,0.75,0.11,0.03,0.05,0.03],[43.75,60.53,0.37,0.55,0.09,0.02,0.26,0.75,0.11,0.03,0.05,0.03],[43.75,63.99,0.36,0.54,0.08,0.02,0.26,0.74,0.11,0.03,0.05,0.03],[43.75,67.45,0.36,0.48,0.09,0.02,0.26,0.73,0.11,0.03,0.05,0.03],[43.75,70.91,0.35,0.47,0.09,0.02,0.25,0.73,0.11,0.03,0.05,0.03],[43.75,74.37,0.35,0.48,0.09,0.02,0.26,0.73,0.11,0.03,0.05,0.03],[43.75,77.83,0.36,0.5,0.08,0.02,0.26,0.74,0.11,0.03,0.05,0.03],[43.75,81.29,0.36,0.49,0.08,0.02,0.26,0.73,0.11,0.03,0.05,0.03],[43.75,84.76,0.37,0.51,0.08,0.03,0.26,0.74,0.11,0.03,0.05,0.03],[43.75,88.22,0.52,0.56,0.08,0.37,0.26,0.75,0.11,0.03,0.05,0.03],[43.75,91.68,0.58,0.56,0.09,0.6,0.26,0.75,0.11,0.03,0.05,0.03],[43.75,95.14,0.57,0.53,0.09,0.55,0.26,0.74,0.11,0.03,0.05,0.03],[43.75,98.6,0.39,0.48,0.09,0.06,0.26,0.73,0.11,0.03,0.05,0.03],[43.75,102.06,0.35,0.44,0.09,0.02,0.25,0.72,0.11,0.03,0.05,0.03],[43.75,105.52,0.35,0.4,0.08,0.02,0.24,0.71,0.11,0.03,0.05,0.03],[43.75,108.98,0.35,0.35,0.08,0.02,0.24,0.7,0.11,0.03,0.05,0.03],[43.75,112.44,0.34,0.31,0.09,0.02,0.23,0.69,0.11,0.02,0.05,0.03],[43.75,115.9,0.35,0.3,0.09,0.02,0.23,0.69,0.11,0.02,0.05,0.03],[43.75,119.36,0.36,0.3,0.09,0.02,0.23,0.68,0.11,0.02,0.05,0.03],[43.75,122.83,0.46,0.31,0.09,0.17,0.23,0.69,0.11,0.02,0.05,0.03],[43.75,126.29,0.46,0.33,0.09,0.18,0.24,0.69,0.11,0.02,0.05,0.03],[43.75,129.75,0.49,0.34,0.09,0.24,0.24,0.7,0.11,0.02,0.05,0.03],[43.75,133.21,0.38,0.34,0.09,0.04,0.24,0.7,0.11,0.02,0.05,0.03],[43.75,143.59,0.36,0.48,0.08,0.02,0.26,0.73,0.11,0.03,0.05,0.03],[46.25,-123.96,0.49,0.54,0.08,0.22,0.26,0.73,0.1,0.04,0.05,0.03],[46.25,-120.35,0.42,0.49,0.08,0.1,0.26,0.72,0.1,0.04,0.05,0.03],[46.25,-116.73,0.36,0.47,0.08,0.03,0.25,0.72,0.1,0.04,0.05,0.03],[46.25,-113.12,0.35,0.49,0.08,0.02,0.26,0.72,0.1,0.04,0.05,0.03],[46.25,-109.5,0.35,0.54,0.08,0.02,0.26,0.73,0.1,0.04,0.05,0.03],[46.25,-105.89,0.34,0.56,0.08,0.02,0.26,0.74,0.1,0.04,0.05,0.03],[46.25,-102.27,0.34,0.52,0.08,0.02,0.26,0.73,0.1,0.04,0.05,0.03],[46.25,-98.66,0.34,0.47,0.08,0.02,0.25,0.71,0.1,0.04,0.05,0.03],[46.25,-95.04,0.34,0.42,0.08,0.02,0.25,0.7,0.1,0.04,0.05,0.03],[46.25,-91.43,0.34,0.37,0.08,0.02,0.24,0.69,0.1,0.03,0.05,0.03],[46.25,-87.81,0.35,0.37,0.08,0.02,0.24,0.69,0.1,0.03,0.05,0.03],[46.25,-84.2,0.35,0.41,0.08,0.02,0.25,0.7,0.1,0.04,0.05,0.03],[46.25,-80.58,0.35,0.42,0.08,0.02,0.25,0.7,0.1,0.04,0.05,0.03],[46.25,-76.97,0.35,0.4,0.08,0.02,0.24,0.7,0.1,0.04,0.05,0.03],[46.25,-73.35,0.35,0.41,0.08,0.02,0.24,0.7,0.1,0.04,0.05,0.03],[46.25,-69.73,0.35,0.41,0.08,0.02,0.25,0.7,0.1,0.04,0.05,0.03],[46.25,-66.12,0.42,0.45,0.08,0.11,0.25,0.71,0.1,0.04,0.05,0.03],[46.25,-62.5,0.43,0.44,0.08,0.13,0.25,0.71,0.1,0.04,0.05,0.03],[46.25,-1.04,0.35,0.46,0.08,0.02,0.25,0.71,0.1,0.04,0.05,0.03],[46.25,2.57,0.35,0.45,0.08,0.02,0.25,0.71,0.1,0.04,0.05,0.03],[46.25,6.19,0.35,0.39,0.08,0.02,0.24,0.7,0.1,0.03,0.05,0.03],[46.25,9.8,0.37,0.38,0.08,0.03,0.24,0.69,0.1,0.03,0.05,0.03],[46.25,13.42,0.36,0.37,0.08,0.03,0.24,0.69,0.1,0.03,0.05,0.03],[46.25,17.03,0.35,0.37,0.08,0.02,0.24,0.69,0.1,0.03,0.05,0.03],[46.25,20.65,0.35,0.41,0.08,0.02,0.25,0.7,0.1,0.04,0.05,0.03],[46.25,24.26,0.35,0.49,0.08,0.02,0.26,0.72,0.1,0.04,0.05,0.03],[46.25,27.88,0.36,0.52,0.08,0.02,0.26,0.73,0.1,0.04,0.05,0.03],[46.25,38.72,0.37,0.49,0.08,0.02,0.25,0.72,0.1,0.04,0.05,0.03],[46.25,42.34,0.37,0.47,0.08,0.02,0.25,0.72,0.1,0.04,0.05,0.03],[46.25,45.95,0.36,0.47,0.08,0.02,0.25,0.72,0.1,0.04,0.05,0.03],[46.25,56.8,0.48,0.52,0.08,0.21,0.26,0.73,0.1,0.04,0.05,0.03],[46.25,60.41,0.47,0.54,0.08,0.19,0.26,0.73,0.1,0.04,0.05,0.03],[46.25,64.03,0.42,0.55,0.08,0.09,0.26,0.73,0.1,0.04,0.05,0.03],[46.25,67.65,0.38,0.52,0.08,0.03,0.26,0.73,0.1,0.04,0.05,0.03],[46.25,71.26,0.36,0.5,0.08,0.02,0.26,0.72,0.1,0.04,0.05,0.03],[46.25,74.88,0.36,0.5,0.08,0.02,0.26,0.72,0.1,0.04,0.05,0.03],[46.25,78.49,0.36,0.48,0.08,0.02,0.25,0.72,0.1,0.04,0.05,0.03],[46.25,82.11,0.36,0.51,0.08,0.02,0.26,0.72,0.1,0.04,0.05,0.03],[46.25,85.72,0.35,0.57,0.08,0.02,0.26,0.74,0.1,0.04,0.05,0.03],[46.25,89.34,0.49,0.61,0.08,0.3,0.27,0.75,0.1,0.04,0.05,0.03],[46.25,92.95,0.54,0.61,0.08,0.43,0.27,0.74,0.1,0.04,0.05,0.03],[46.25,96.57,0.42,0.59,0.08,0.11,0.27,0.74,0.1,0.04,0.05,0.03],[46.25,100.18,0.35,0.52,0.08,0.02,0.26,0.73,0.1,0.04,0.05,0.03],[46.25,103.8,0.35,0.48,0.08,0.02,0.25,0.72,0.1,0.04,0.05,0.03],[46.25,107.41,0.35,0.38,0.08,0.02,0.24,0.69,0.1,0.03,0.05,0.03],[46.25,111.03,0.35,0.34,0.08,0.02,0.24,0.68,0.1,0.03,0.05,0.03],[46.25,114.64,0.35,0.32,0.08,0.02,0.23,0.68,0.1,0.03,0.05,0.03],[46.25,118.26,0.4,0.29,0.08,0.06,0.23,0.67,0.1,0.03,0.05,0.03],[46.25,121.87,0.47,0.3,0.08,0.22,0.23,0.67,0.1,0.03,0.05,0.03],[46.25,125.49,0.42,0.36,0.08,0.1,0.24,0.69,0.1,0.03,0.05,0.03],[46.25,129.1,0.48,0.38,0.08,0.23,0.24,0.69,0.1,0.03,0.05,0.03],[46.25,132.72,0.39,0.35,0.08,0.05,0.24,0.69,0.1,0.03,0.05,0.03],[46.25,136.34,0.36,0.38,0.08,0.02,0.24,0.69,0.1,0.03,0.05,0.03],[48.75,-125.02,0.48,0.53,0.08,0.19,0.26,0.72,0.1,0.06,0.05,0.03],[48.75,-121.23,0.45,0.51,0.08,0.15,0.26,0.71,0.1,0.05,0.05,0.03],[48.75,-117.44,0.39,0.5,0.08,0.07,0.26,0.71,0.1,0.05,0.05,0.03],[48.75,-113.65,0.38,0.47,0.08,0.06,0.25,0.7,0.1,0.05,0.05,0.03],[48.75,-109.85,0.34,0.47,0.08,0.02,0.25,0.7,0.1,0.05,0.05,0.03],[48.75,-106.06,0.34,0.48,0.08,0.02,0.25,0.7,0.1,0.05,0.05,0.03],[48.75,-102.27,0.34,0.48,0.08,0.02,0.25,0.7,0.1,0.05,0.05,0.03],[48.75,-98.48,0.35,0.46,0.08,0.02,0.25,0.7,0.1,0.05,0.05,0.03],[48.75,-94.69,0.35,0.43,0.08,0.02,0.25,0.69,0.1,0.05,0.05,0.03],[48.75,-90.9,0.36,0.39,0.08,0.03,0.24,0.68,0.1,0.05,0.05,0.03],[48.75,-87.1,0.36,0.42,0.08,0.02,0.25,0.69,0.1,0.05,0.05,0.03],[48.75,-83.31,0.35,0.46,0.08,0.02,0.25,0.7,0.1,0.05,0.05,0.03],[48.75,-79.52,0.36,0.43,0.08,0.02,0.25,0.69,0.1,0.05,0.05,0.03],[48.75,-75.73,0.35,0.4,0.08,0.02,0.24,0.68,0.1,0.05,0.05,0.03],[48.75,-71.94,0.38,0.4,0.08,0.08,0.24,0.68,0.1,0.05,0.05,0.03],[48.75,-64.36,0.53,0.41,0.08,0.43,0.25,0.69,0.1,0.05,0.05,0.03],[48.75,-56.77,0.35,0.35,0.08,0.02,0.24,0.67,0.1,0.04,0.05,0.03],[48.75,-3.69,0.34,0.44,0.08,0.02,0.25,0.69,0.1,0.05,0.05,0.03],[48.75,0.1,0.34,0.47,0.08,0.02,0.25,0.7,0.1,0.05,0.05,0.03],[48.75,3.89,0.35,0.42,0.08,0.02,0.25,0.69,0.1,0.05,0.05,0.03],[48.75,7.69,0.34,0.4,0.08,0.02,0.24,0.68,0.1,0.05,0.05,0.03],[48.75,11.48,0.34,0.41,0.08,0.02,0.25,0.69,0.1,0.05,0.05,0.03],[48.75,15.27,0.35,0.43,0.08,0.02,0.25,0.69,0.1,0.05,0.05,0.03],[48.75,19.06,0.35,0.47,0.08,0.02,0.25,0.7,0.1,0.05,0.05,0.03],[48.75,22.85,0.35,0.5,0.08,0.02,0.26,0.71,0.1,0.05,0.05,0.03],[48.75,26.64,0.36,0.54,0.08,0.02,0.26,0.72,0.1,0.06,0.05,0.03],[48.75,30.44,0.36,0.56,0.08,0.02,0.26,0.72,0.1,0.06,0.05,0.03],[48.75,34.23,0.36,0.56,0.08,0.02,0.26,0.72,0.1,0.06,0.05,0.03],[48.75,38.02,0.36,0.53,0.08,0.02,0.26,0.71,0.1,0.06,0.05,0.03],[48.75,41.81,0.36,0.53,0.08,0.02,0.26,0.71,0.1,0.06,0.05,0.03],[48.75,45.6,0.36,0.47,0.08,0.02,0.25,0.7,0.1,0.05,0.05,0.03],[48.75,49.39,0.36,0.48,0.08,0.02,0.25,0.7,0.1,0.05,0.05,0.03],[48.75,53.19,0.36,0.51,0.08,0.02,0.26,0.71,0.1,0.05,0.05,0.03],[48.75,56.98,0.45,0.54,0.08,0.14,0.26,0.72,0.1,0.06,0.05,0.03],[48.75,60.77,0.5,0.56,0.08,0.24,0.26,0.72,0.1,0.06,0.05,0.03],[48.75,64.56,0.5,0.54,0.08,0.24,0.26,0.72,0.1,0.06,0.05,0.03],[48.75,68.35,0.39,0.57,0.08,0.03,0.26,0.72,0.1,0.06,0.05,0.03],[48.75,72.14,0.37,0.55,0.08,0.02,0.26,0.72,0.1,0.06,0.05,0.03],[48.75,75.94,0.36,0.56,0.08,0.02,0.26,0.72,0.1,0.06,0.05,0.03],[48.75,79.73,0.36,0.53,0.08,0.02,0.26,0.71,0.1,0.06,0.05,0.03],[48.75,83.52,0.36,0.54,0.08,0.02,0.26,0.72,0.1,0.06,0.05,0.03],[48.75,87.31,0.37,0.63,0.08,0.04,0.27,0.74,0.1,0.06,0.05,0.03],[48.75,91.1,0.44,0.65,0.08,0.14,0.27,0.74,0.1,0.06,0.05,0.03],[48.75,94.89,0.35,0.64,0.08,0.02,0.27,0.74,0.1,0.06,0.05,0.03],[48.75,98.69,0.35,0.6,0.08,0.02,0.27,0.73,0.1,0.06,0.05,0.03],[48.75,102.48,0.35,0.54,0.08,0.02,0.26,0.72,0.1,0.06,0.05,0.03],[48.75,106.27,0.35,0.48,0.08,0.02,0.25,0.7,0.1,0.05,0.05,0.03],[48.75,110.06,0.35,0.38,0.08,0.02,0.24,0.68,0.1,0.05,0.05,0.03],[48.75,113.85,0.35,0.32,0.08,0.02,0.23,0.66,0.1,0.04,0.05,0.03],[48.75,117.64,0.34,0.3,0.08,0.02,0.23,0.66,0.1,0.04,0.05,0.03],[48.75,121.44,0.37,0.3,0.08,0.03,0.23,0.66,0.1,0.04,0.05,0.03],[48.75,125.23,0.37,0.35,0.08,0.04,0.24,0.67,0.1,0.04,0.05,0.03],[48.75,129.02,0.46,0.42,0.08,0.19,0.25,0.69,0.1,0.05,0.05,0.03],[48.75,132.81,0.47,0.4,0.08,0.21,0.24,0.68,0.1,0.05,0.05,0.03],[48.75,136.6,0.44,0.41,0.08,0.14,0.25,0.69,0.1,0.05,0.05,0.03],[51.25,-126.08,0.45,0.5,0.08,0.12,0.26,0.69,0.1,0.07,0.05,0.03],[51.25,-122.09,0.51,0.49,0.08,0.33,0.25,0.69,0.1,0.07,0.05,0.03],[51.25,-118.09,0.43,0.47,0.08,0.15,0.25,0.69,0.1,0.07,0.05,0.03],[51.25,-114.1,0.43,0.47,0.08,0.16,0.25,0.69,0.1,0.07,0.05,0.03],[51.25,-110.1,0.4,0.45,0.08,0.1,0.25,0.68,0.1,0.06,0.05,0.03],[51.25,-106.11,0.36,0.44,0.08,0.03,0.25,0.68,0.1,0.06,0.05,0.03],[51.25,-102.12,0.34,0.42,0.08,0.02,0.25,0.67,0.1,0.06,0.05,0.03],[51.25,-98.12,0.34,0.44,0.08,0.02,0.25,0.68,0.1,0.06,0.05,0.03],[51.25,-94.13,0.34,0.45,0.08,0.02,0.25,0.68,0.1,0.06,0.05,0.03],[51.25,-90.13,0.35,0.45,0.08,0.02,0.25,0.68,0.1,0.06,0.05,0.03],[51.25,-86.14,0.34,0.46,0.08,0.02,0.25,0.68,0.1,0.06,0.05,0.03],[51.25,-82.14,0.35,0.44,0.08,0.02,0.25,0.68,0.1,0.06,0.05,0.03],[51.25,-78.15,0.34,0.42,0.08,0.02,0.25,0.67,0.1,0.06,0.05,0.03],[51.25,-74.16,0.32,0.4,0.08,0.02,0.24,0.67,0.1,0.06,0.05,0.03],[51.25,-70.16,0.34,0.42,0.08,0.03,0.25,0.67,0.1,0.06,0.05,0.03],[51.25,-66.17,0.38,0.41,0.08,0.07,0.24,0.67,0.1,0.06,0.05,0.03],[51.25,-62.17,0.41,0.35,0.08,0.08,0.24,0.65,0.1,0.05,0.05,0.03],[51.25,-58.18,0.35,0.34,0.08,0.02,0.24,0.65,0.1,0.05,0.05,0.03],[51.25,-2.26,0.34,0.44,0.08,0.02,0.25,0.68,0.1,0.06,0.05,0.03],[51.25,5.73,0.33,0.42,0.08,0.02,0.25,0.67,0.1,0.06,0.05,0.03],[51.25,9.72,0.33,0.47,0.08,0.02,0.25,0.68,0.1,0.07,0.05,0.03],[51.25,13.71,0.34,0.51,0.08,0.02,0.26,0.7,0.1,0.07,0.05,0.03],[51.25,17.71,0.35,0.52,0.08,0.02,0.26,0.7,0.1,0.07,0.05,0.03],[51.25,21.7,0.35,0.53,0.08,0.02,0.26,0.7,0.1,0.07,0.05,0.03],[51.25,25.7,0.35,0.56,0.08,0.02,0.26,0.71,0.1,0.07,0.05,0.03],[51.25,29.69,0.35,0.56,0.08,0.02,0.26,0.71,0.1,0.08,0.05,0.03],[51.25,33.68,0.35,0.55,0.08,0.02,0.26,0.7,0.1,0.07,0.05,0.03],[51.25,37.68,0.36,0.57,0.08,0.02,0.26,0.71,0.1,0.08,0.05,0.03],[51.25,41.67,0.36,0.56,0.08,0.02,0.26,0.71,0.1,0.08,0.05,0.03],[51.25,45.67,0.36,0.55,0.08,0.02,0.26,0.7,0.1,0.07,0.05,0.03],[51.25,49.66,0.36,0.55,0.08,0.02,0.26,0.7,0.1,0.07,0.05,0.03],[51.25,53.65,0.38,0.53,0.08,0.03,0.26,0.7,0.1,0.07,0.05,0.03],[51.25,57.65,0.42,0.56,0.08,0.06,0.26,0.71,0.1,0.08,0.05,0.03],[51.25,61.64,0.49,0.59,0.08,0.2,0.27,0.71,0.1,0.08,0.05,0.03],[51.25,65.64,0.45,0.61,0.08,0.12,0.27,0.72,0.1,0.08,0.05,0.03],[51.25,69.63,0.41,0.59,0.08,0.05,0.26,0.71,0.1,0.08,0.05,0.03],[51.25,73.63,0.37,0.61,0.08,0.02,0.27,0.72,0.1,0.08,0.05,0.03],[51.25,77.62,0.36,0.61,0.08,0.02,0.27,0.72,0.1,0.08,0.05,0.03],[51.25,81.61,0.35,0.6,0.08,0.02,0.27,0.71,0.1,0.08,0.05,0.03],[51.25,85.61,0.35,0.6,0.08,0.02,0.27,0.71,0.1,0.08,0.05,0.03],[51.25,89.6,0.34,0.61,0.08,0.02,0.27,0.72,0.1,0.08,0.05,0.03],[51.25,93.6,0.35,0.59,0.08,0.02,0.27,0.71,0.1,0.08,0.05,0.03],[51.25,97.59,0.36,0.55,0.08,0.02,0.26,0.7,0.1,0.07,0.05,0.03],[51.25,101.58,0.36,0.57,0.08,0.02,0.26,0.71,0.1,0.08,0.05,0.03],[51.25,105.58,0.36,0.52,0.08,0.02,0.26,0.7,0.1,0.07,0.05,0.03],[51.25,109.57,0.36,0.44,0.08,0.02,0.25,0.68,0.1,0.06,0.05,0.03],[51.25,113.57,0.35,0.35,0.08,0.02,0.24,0.66,0.1,0.05,0.05,0.03],[51.25,117.56,0.34,0.35,0.08,0.02,0.24,0.65,0.1,0.05,0.05,0.03],[51.25,121.55,0.34,0.32,0.08,0.02,0.23,0.65,0.1,0.05,0.05,0.03],[51.25,125.55,0.35,0.36,0.08,0.02,0.24,0.66,0.1,0.05,0.05,0.03],[51.25,129.54,0.37,0.41,0.08,0.02,0.24,0.67,0.1,0.06,0.05,0.03],[51.25,133.54,0.36,0.41,0.08,0.02,0.24,0.67,0.1,0.06,0.05,0.03],[51.25,137.53,0.37,0.4,0.08,0.02,0.24,0.67,0.1,0.06,0.05,0.03],[53.75,-127.15,0.48,0.5,0.08,0.19,0.26,0.68,0.1,0.08,0.05,0.03],[53.75,-122.92,0.45,0.47,0.08,0.18,0.25,0.67,0.1,0.08,0.05,0.03],[53.75,-118.7,0.47,0.45,0.08,0.25,0.25,0.67,0.1,0.08,0.05,0.03],[53.75,-114.47,0.45,0.45,0.08,0.22,0.25,0.67,0.1,0.08,0.05,0.03],[53.75,-110.24,0.4,0.42,0.08,0.11,0.25,0.66,0.1,0.07,0.05,0.03],[53.75,-106.01,0.37,0.4,0.08,0.04,0.24,0.65,0.1,0.07,0.05,0.03],[53.75,-101.78,0.34,0.38,0.08,0.02,0.24,0.65,0.1,0.07,0.05,0.03],[53.75,-97.56,0.34,0.44,0.08,0.02,0.25,0.66,0.1,0.08,0.05,0.03],[53.75,-93.33,0.33,0.49,0.08,0.02,0.25,0.68,0.1,0.08,0.05,0.03],[53.75,-89.1,0.33,0.49,0.08,0.02,0.25,0.67,0.1,0.08,0.05,0.03],[53.75,-84.87,0.34,0.44,0.08,0.02,0.25,0.66,0.1,0.08,0.05,0.03],[53.75,-76.42,0.33,0.39,0.08,0.02,0.24,0.65,0.1,0.07,0.05,0.03],[53.75,-72.19,0.33,0.39,0.08,0.02,0.24,0.65,0.1,0.07,0.05,0.03],[53.75,-67.96,0.34,0.38,0.08,0.02,0.24,0.65,0.1,0.07,0.05,0.03],[53.75,-63.73,0.35,0.36,0.08,0.02,0.24,0.64,0.1,0.06,0.05,0.03],[53.75,-59.5,0.34,0.32,0.08,0.02,0.23,0.63,0.1,0.06,0.05,0.03],[53.75,-8.77,0.34,0.51,0.08,0.02,0.26,0.68,0.1,0.09,0.05,0.03],[53.75,-0.31,0.34,0.47,0.08,0.02,0.25,0.67,0.1,0.08,0.05,0.03],[53.75,12.37,0.34,0.56,0.08,0.02,0.26,0.69,0.1,0.09,0.05,0.03],[53.75,16.6,0.34,0.55,0.08,0.02,0.26,0.69,0.1,0.09,0.05,0.03],[53.75,20.83,0.34,0.55,0.08,0.02,0.26,0.69,0.1,0.09,0.05,0.03],[53.75,25.05,0.34,0.56,0.08,0.02,0.26,0.69,0.1,0.09,0.05,0.03],[53.75,29.28,0.34,0.56,0.08,0.02,0.26,0.69,0.1,0.09,0.05,0.03],[53.75,33.51,0.34,0.55,0.08,0.02,0.26,0.69,0.1,0.09,0.05,0.03],[53.75,37.74,0.35,0.54,0.08,0.02,0.26,0.69,0.1,0.09,0.05,0.03],[53.75,41.96,0.36,0.57,0.08,0.02,0.26,0.69,0.1,0.09,0.05,0.03],[53.75,46.19,0.36,0.59,0.08,0.02,0.27,0.7,0.1,0.1,0.05,0.03],[53.75,50.42,0.36,0.59,0.08,0.02,0.26,0.7,0.1,0.09,0.05,0.03],[53.75,54.65,0.37,0.57,0.08,0.02,0.26,0.69,0.1,0.09,0.05,0.03],[53.75,58.88,0.37,0.57,0.08,0.02,0.26,0.69,0.1,0.09,0.05,0.03],[53.75,63.1,0.38,0.6,0.08,0.03,0.27,0.7,0.1,0.1,0.05,0.03],[53.75,67.33,0.39,0.6,0.08,0.04,0.27,0.7,0.1,0.1,0.05,0.03],[53.75,71.56,0.37,0.6,0.08,0.02,0.27,0.7,0.1,0.1,0.05,0.03],[53.75,75.79,0.36,0.6,0.08,0.02,0.27,0.7,0.1,0.1,0.05,0.03],[53.75,80.02,0.35,0.61,0.08,0.02,0.27,0.7,0.1,0.1,0.05,0.03],[53.75,84.24,0.35,0.59,0.08,0.02,0.27,0.7,0.1,0.1,0.05,0.03],[53.75,88.47,0.34,0.57,0.08,0.02,0.26,0.69,0.1,0.09,0.05,0.03],[53.75,92.7,0.35,0.58,0.08,0.02,0.26,0.69,0.1,0.09,0.05,0.03],[53.75,96.93,0.36,0.57,0.08,0.02,0.26,0.69,0.1,0.09,0.05,0.03],[53.75,101.16,0.36,0.58,0.08,0.02,0.26,0.69,0.1,0.09,0.05,0.03],[53.75,105.38,0.36,0.56,0.08,0.02,0.26,0.69,0.1,0.09,0.05,0.03],[53.75,109.61,0.35,0.49,0.08,0.02,0.25,0.67,0.1,0.08,0.05,0.03],[53.75,113.84,0.35,0.42,0.08,0.02,0.25,0.66,0.1,0.07,0.05,0.03],[53.75,118.07,0.35,0.39,0.08,0.02,0.24,0.65,0.1,0.07,0.05,0.03],[53.75,122.3,0.34,0.38,0.08,0.02,0.24,0.65,0.1,0.07,0.05,0.03],[53.75,126.52,0.35,0.37,0.08,0.02,0.24,0.65,0.1,0.07,0.05,0.03],[53.75,130.75,0.36,0.37,0.08,0.02,0.24,0.65,0.1,0.07,0.05,0.03],[53.75,134.98,0.36,0.36,0.08,0.02,0.24,0.64,0.1,0.06,0.05,0.03],[53.75,139.21,0.36,0.37,0.08,0.02,0.24,0.65,0.1,0.07,0.05,0.03],[53.75,156.12,0.36,0.46,0.08,0.02,0.25,0.67,0.1,0.08,0.05,0.03],[56.25,-159.75,0.4,0.6,0.08,0.05,0.27,0.68,0.1,0.12,0.05,0.04],[56.25,-128.25,0.51,0.57,0.08,0.28,0.27,0.67,0.1,0.11,0.05,0.04],[56.25,-123.75,0.55,0.49,0.08,0.44,0.26,0.66,0.1,0.1,0.05,0.04],[56.25,-119.25,0.49,0.44,0.08,0.29,0.25,0.65,0.1,0.09,0.05,0.04],[56.25,-114.75,0.45,0.43,0.08,0.2,0.25,0.64,0.1,0.09,0.05,0.04],[56.25,-110.25,0.38,0.42,0.08,0.06,0.25,0.64,0.1,0.09,0.05,0.04],[56.25,-105.75,0.36,0.41,0.08,0.03,0.25,0.64,0.1,0.09,0.05,0.04],[56.25,-101.25,0.38,0.44,0.08,0.04,0.25,0.65,0.1,0.09,0.05,0.04],[56.25,-96.75,0.35,0.46,0.08,0.02,0.26,0.65,0.1,0.1,0.05,0.04],[56.25,-92.25,0.34,0.48,0.08,0.02,0.26,0.66,0.1,0.1,0.05,0.04],[56.25,-87.75,0.34,0.47,0.08,0.02,0.26,0.65,0.1,0.1,0.05,0.04],[56.25,-74.25,0.33,0.39,0.08,0.02,0.25,0.63,0.1,0.08,0.05,0.04],[56.25,-69.75,0.34,0.4,0.08,0.02,0.25,0.64,0.1,0.09,0.05,0.04],[56.25,-65.25,0.34,0.38,0.08,0.02,0.25,0.63,0.1,0.08,0.05,0.04],[56.25,15.74,0.33,0.53,0.08,0.02,0.26,0.67,0.1,0.11,0.05,0.04],[56.25,24.74,0.34,0.54,0.08,0.02,0.27,0.67,0.1,0.11,0.05,0.04],[56.25,29.24,0.34,0.55,0.08,0.02,0.27,0.67,0.1,0.11,0.05,0.04],[56.25,33.74,0.34,0.52,0.08,0.02,0.26,0.66,0.1,0.1,0.05,0.04],[56.25,38.24,0.35,0.53,0.08,0.02,0.26,0.67,0.1,0.11,0.05,0.04],[56.25,42.74,0.36,0.57,0.08,0.02,0.27,0.67,0.1,0.11,0.05,0.04],[56.25,47.24,0.36,0.58,0.08,0.02,0.27,0.68,0.1,0.11,0.05,0.04],[56.25,51.74,0.36,0.56,0.08,0.02,0.27,0.67,0.1,0.11,0.05,0.04],[56.25,56.24,0.36,0.54,0.08,0.02,0.27,0.67,0.1,0.11,0.05,0.04],[56.25,60.74,0.36,0.54,0.08,0.02,0.27,0.67,0.1,0.11,0.05,0.04],[56.25,65.24,0.36,0.54,0.08,0.02,0.27,0.67,0.1,0.11,0.05,0.04],[56.25,69.74,0.35,0.57,0.08,0.02,0.27,0.68,0.1,0.11,0.05,0.04],[56.25,74.24,0.35,0.58,0.08,0.02,0.27,0.68,0.1,0.11,0.05,0.04],[56.25,78.74,0.35,0.55,0.08,0.02,0.27,0.67,0.1,0.11,0.05,0.04],[56.25,83.24,0.34,0.53,0.08,0.02,0.26,0.67,0.1,0.11,0.05,0.04],[56.25,87.74,0.34,0.54,0.08,0.02,0.27,0.67,0.1,0.11,0.05,0.04],[56.25,92.24,0.35,0.55,0.08,0.02,0.27,0.67,0.1,0.11,0.05,0.04],[56.25,96.74,0.35,0.55,0.08,0.02,0.27,0.67,0.1,0.11,0.05,0.04],[56.25,101.24,0.35,0.52,0.08,0.02,0.26,0.66,0.1,0.1,0.05,0.04],[56.25,105.74,0.35,0.49,0.08,0.02,0.26,0.66,0.1,0.1,0.05,0.04],[56.25,110.24,0.35,0.44,0.08,0.02,0.25,0.65,0.1,0.09,0.05,0.04],[56.25,114.74,0.35,0.45,0.08,0.02,0.26,0.65,0.1,0.09,0.05,0.04],[56.25,119.24,0.34,0.42,0.08,0.02,0.25,0.64,0.1,0.09,0.05,0.04],[56.25,123.74,0.35,0.35,0.08,0.02,0.24,0.62,0.1,0.08,0.05,0.04],[56.25,128.24,0.35,0.35,0.08,0.02,0.24,0.62,0.1,0.08,0.05,0.04],[56.25,132.74,0.35,0.33,0.08,0.02,0.24,0.62,0.1,0.07,0.05,0.04],[56.25,137.24,0.35,0.32,0.08,0.02,0.24,0.61,0.1,0.07,0.05,0.04],[56.25,159.74,0.35,0.52,0.08,0.02,0.26,0.66,0.1,0.11,0.05,0.04],[58.75,-158.31,0.39,0.56,0.08,0.05,0.31,0.65,0.12,0.17,0.06,0.08],[58.75,-153.5,0.35,0.53,0.08,0.02,0.31,0.64,0.12,0.16,0.06,0.08],[58.75,-134.22,0.37,0.62,0.08,0.02,0.32,0.66,0.12,0.18,0.06,0.08],[58.75,-129.4,0.4,0.61,0.08,0.05,0.32,0.66,0.12,0.18,0.06,0.08],[58.75,-124.58,0.62,0.55,0.08,0.69,0.31,0.65,0.12,0.17,0.06,0.08],[58.75,-119.76,0.59,0.47,0.08,0.61,0.3,0.63,0.12,0.15,0.06,0.08],[58.75,-114.94,0.42,0.44,0.08,0.1,0.3,0.62,0.12,0.15,0.06,0.08],[58.75,-110.12,0.36,0.41,0.08,0.02,0.29,0.62,0.12,0.14,0.06,0.08],[58.75,-105.3,0.35,0.43,0.08,0.02,0.3,0.62,0.12,0.14,0.06,0.08],[58.75,-100.49,0.36,0.46,0.08,0.03,0.3,0.63,0.12,0.15,0.06,0.08],[58.75,-95.67,0.37,0.48,0.08,0.03,0.3,0.63,0.12,0.15,0.06,0.08],[58.75,-76.39,0.34,0.4,0.08,0.02,0.29,0.61,0.12,0.14,0.06,0.08],[58.75,-71.57,0.34,0.41,0.08,0.02,0.29,0.62,0.12,0.14,0.06,0.08],[58.75,15.17,0.35,0.52,0.08,0.02,0.31,0.64,0.12,0.16,0.06,0.08],[58.75,24.81,0.34,0.51,0.08,0.02,0.31,0.64,0.12,0.16,0.06,0.08],[58.75,29.63,0.34,0.52,0.08,0.02,0.31,0.64,0.12,0.16,0.06,0.08],[58.75,34.45,0.35,0.5,0.08,0.02,0.31,0.64,0.12,0.16,0.06,0.08],[58.75,39.27,0.35,0.51,0.08,0.02,0.31,0.64,0.12,0.15,0.06,0.08],[58.75,44.09,0.35,0.53,0.08,0.02,0.31,0.64,0.12,0.16,0.06,0.08],[58.75,48.91,0.35,0.53,0.08,0.02,0.31,0.64,0.12,0.16,0.06,0.08],[58.75,53.72,0.35,0.52,0.08,0.02,0.31,0.64,0.12,0.16,0.06,0.08],[58.75,58.54,0.34,0.53,0.08,0.02,0.31,0.64,0.12,0.16,0.06,0.08],[58.75,63.36,0.34,0.51,0.08,0.02,0.31,0.64,0.12,0.16,0.06,0.08],[58.75,68.18,0.34,0.53,0.08,0.02,0.31,0.64,0.12,0.16,0.06,0.08],[58.75,73,0.34,0.54,0.08,0.02,0.31,0.65,0.12,0.16,0.06,0.08],[58.75,77.82,0.34,0.5,0.08,0.02,0.31,0.64,0.12,0.16,0.06,0.08],[58.75,82.64,0.34,0.49,0.08,0.02,0.3,0.63,0.12,0.16,0.06,0.08],[58.75,87.46,0.34,0.53,0.08,0.02,0.31,0.64,0.12,0.17,0.06,0.08],[58.75,92.28,0.34,0.53,0.08,0.02,0.31,0.64,0.12,0.17,0.06,0.08],[58.75,97.1,0.35,0.48,0.08,0.02,0.3,0.63,0.12,0.16,0.06,0.08],[58.75,101.92,0.35,0.47,0.08,0.02,0.3,0.63,0.12,0.15,0.06,0.08],[58.75,106.73,0.35,0.47,0.08,0.02,0.3,0.63,0.12,0.15,0.06,0.08],[58.75,111.55,0.35,0.45,0.08,0.02,0.3,0.63,0.12,0.15,0.06,0.08],[58.75,116.37,0.35,0.43,0.08,0.02,0.3,0.62,0.12,0.15,0.06,0.08],[58.75,121.19,0.35,0.38,0.08,0.02,0.29,0.61,0.12,0.14,0.06,0.08],[58.75,126.01,0.35,0.34,0.08,0.02,0.29,0.6,0.12,0.13,0.06,0.08],[58.75,130.83,0.36,0.32,0.08,0.02,0.28,0.59,0.12,0.12,0.06,0.08],[58.75,135.65,0.35,0.32,0.08,0.02,0.28,0.59,0.12,0.12,0.06,0.08],[58.75,140.47,0.35,0.29,0.08,0.02,0.28,0.58,0.12,0.12,0.06,0.08],[58.75,159.74,0.35,0.48,0.08,0.02,0.3,0.63,0.12,0.16,0.06,0.08],[61.25,-161.81,0.4,0.46,0.08,0.05,0.38,0.6,0.16,0.24,0.09,0.16],[61.25,-156.61,0.36,0.48,0.08,0.03,0.38,0.6,0.16,0.24,0.09,0.15],[61.25,-151.41,0.35,0.51,0.08,0.02,0.38,0.61,0.16,0.24,0.09,0.15],[61.25,-146.22,0.36,0.52,0.08,0.02,0.38,0.61,0.16,0.25,0.09,0.16],[61.25,-141.02,0.36,0.55,0.08,0.02,0.39,0.62,0.16,0.25,0.09,0.16],[61.25,-135.82,0.36,0.57,0.08,0.02,0.39,0.62,0.16,0.26,0.09,0.16],[61.25,-130.62,0.36,0.58,0.08,0.02,0.39,0.63,0.16,0.26,0.09,0.17],[61.25,-125.42,0.39,0.55,0.08,0.04,0.39,0.62,0.16,0.25,0.09,0.16],[61.25,-120.23,0.43,0.49,0.08,0.11,0.38,0.61,0.16,0.24,0.09,0.16],[61.25,-115.03,0.36,0.46,0.08,0.02,0.38,0.6,0.16,0.23,0.09,0.16],[61.25,-109.83,0.35,0.42,0.08,0.02,0.37,0.59,0.16,0.23,0.09,0.17],[61.25,-104.63,0.35,0.43,0.08,0.02,0.37,0.59,0.16,0.22,0.09,0.16],[61.25,-99.44,0.36,0.46,0.08,0.02,0.38,0.6,0.16,0.23,0.09,0.16],[61.25,-94.24,0.35,0.5,0.08,0.02,0.38,0.61,0.16,0.23,0.09,0.17],[61.25,-73.45,0.34,0.43,0.08,0.02,0.37,0.59,0.16,0.23,0.09,0.16],[61.25,-47.46,0.36,0.51,0.08,0.02,0.38,0.61,0.16,0.26,0.09,0.16],[61.25,9.71,0.36,0.47,0.08,0.02,0.38,0.6,0.16,0.25,0.09,0.16],[61.25,14.91,0.35,0.49,0.08,0.02,0.38,0.61,0.16,0.25,0.09,0.16],[61.25,25.31,0.36,0.44,0.08,0.02,0.38,0.59,0.16,0.23,0.09,0.15],[61.25,30.5,0.35,0.43,0.08,0.02,0.37,0.59,0.16,0.23,0.09,0.16],[61.25,35.7,0.35,0.48,0.08,0.02,0.38,0.6,0.16,0.23,0.09,0.16],[61.25,40.9,0.34,0.47,0.08,0.02,0.38,0.6,0.16,0.23,0.09,0.17],[61.25,46.1,0.35,0.43,0.08,0.02,0.37,0.59,0.16,0.22,0.09,0.16],[61.25,51.29,0.35,0.48,0.08,0.02,0.38,0.6,0.16,0.23,0.09,0.16],[61.25,56.49,0.35,0.49,0.08,0.02,0.38,0.61,0.16,0.24,0.09,0.16],[61.25,61.69,0.33,0.48,0.08,0.02,0.38,0.6,0.16,0.23,0.09,0.16],[61.25,66.89,0.33,0.45,0.08,0.02,0.38,0.6,0.16,0.23,0.09,0.16],[61.25,72.08,0.34,0.45,0.08,0.02,0.38,0.6,0.16,0.24,0.09,0.16],[61.25,77.28,0.34,0.46,0.08,0.02,0.38,0.6,0.16,0.24,0.09,0.16],[61.25,82.48,0.34,0.47,0.08,0.02,0.38,0.6,0.16,0.25,0.09,0.16],[61.25,87.68,0.33,0.5,0.08,0.02,0.38,0.61,0.16,0.25,0.09,0.15],[61.25,92.88,0.34,0.51,0.08,0.02,0.38,0.61,0.16,0.25,0.09,0.15],[61.25,98.07,0.35,0.46,0.08,0.02,0.38,0.6,0.16,0.24,0.09,0.16],[61.25,103.27,0.35,0.45,0.08,0.02,0.38,0.6,0.16,0.24,0.09,0.16],[61.25,108.47,0.35,0.47,0.08,0.02,0.38,0.6,0.16,0.25,0.09,0.16],[61.25,113.67,0.35,0.45,0.08,0.02,0.38,0.6,0.16,0.24,0.09,0.16],[61.25,118.86,0.35,0.4,0.08,0.02,0.37,0.59,0.16,0.23,0.09,0.15],[61.25,124.06,0.35,0.35,0.08,0.02,0.36,0.57,0.16,0.21,0.09,0.15],[61.25,129.26,0.35,0.31,0.08,0.02,0.36,0.56,0.16,0.21,0.09,0.16],[61.25,134.46,0.35,0.28,0.08,0.02,0.35,0.55,0.16,0.2,0.09,0.16],[61.25,139.65,0.34,0.29,0.08,0.02,0.36,0.56,0.16,0.2,0.09,0.16],[61.25,144.85,0.34,0.31,0.08,0.02,0.36,0.56,0.16,0.21,0.09,0.16],[61.25,150.05,0.34,0.32,0.08,0.02,0.36,0.56,0.16,0.21,0.09,0.16],[61.25,155.25,0.36,0.34,0.08,0.03,0.36,0.57,0.16,0.22,0.09,0.16],[61.25,160.44,0.43,0.33,0.08,0.15,0.36,0.57,0.16,0.22,0.09,0.16],[61.25,165.64,0.36,0.39,0.08,0.02,0.37,0.58,0.16,0.23,0.09,0.17],[61.25,170.84,0.36,0.33,0.08,0.02,0.36,0.57,0.16,0.22,0.09,0.17],[63.75,-160.22,0.42,0.38,0.08,0.08,0.47,0.55,0.21,0.33,0.11,0.25],[63.75,-154.56,0.35,0.41,0.08,0.02,0.47,0.56,0.21,0.34,0.11,0.25],[63.75,-148.91,0.35,0.45,0.08,0.02,0.48,0.57,0.21,0.34,0.11,0.26],[63.75,-143.26,0.37,0.54,0.08,0.02,0.49,0.59,0.21,0.36,0.11,0.27],[63.75,-137.61,0.36,0.56,0.08,0.02,0.49,0.59,0.21,0.36,0.11,0.27],[63.75,-131.95,0.36,0.55,0.08,0.02,0.49,0.59,0.21,0.37,0.11,0.26],[63.75,-126.3,0.36,0.52,0.08,0.02,0.48,0.58,0.21,0.36,0.11,0.26],[63.75,-120.65,0.36,0.49,0.08,0.02,0.48,0.58,0.21,0.35,0.11,0.26],[63.75,-115,0.36,0.49,0.08,0.02,0.48,0.58,0.21,0.35,0.11,0.27],[63.75,-109.34,0.35,0.47,0.08,0.02,0.48,0.57,0.21,0.34,0.11,0.27],[63.75,-103.69,0.34,0.41,0.08,0.02,0.47,0.56,0.21,0.33,0.11,0.27],[63.75,-98.04,0.34,0.43,0.08,0.02,0.47,0.56,0.21,0.32,0.11,0.28],[63.75,-92.39,0.35,0.46,0.08,0.02,0.48,0.57,0.21,0.33,0.11,0.27],[63.75,-86.74,0.35,0.47,0.08,0.02,0.48,0.57,0.21,0.33,0.11,0.27],[63.75,-81.08,0.36,0.5,0.08,0.02,0.48,0.58,0.21,0.35,0.11,0.27],[63.75,-69.78,0.35,0.42,0.08,0.02,0.47,0.56,0.21,0.35,0.11,0.27],[63.75,-47.17,0.37,0.54,0.08,0.02,0.49,0.59,0.21,0.38,0.11,0.26],[63.75,-41.52,0.36,0.53,0.08,0.02,0.49,0.58,0.21,0.38,0.11,0.27],[63.75,-18.91,0.36,0.45,0.08,0.02,0.48,0.57,0.21,0.37,0.11,0.27],[63.75,9.36,0.36,0.46,0.08,0.02,0.48,0.57,0.21,0.37,0.11,0.26],[63.75,15.01,0.35,0.45,0.08,0.02,0.48,0.57,0.21,0.36,0.11,0.25],[63.75,26.31,0.37,0.4,0.08,0.02,0.47,0.55,0.21,0.34,0.11,0.25],[63.75,31.97,0.36,0.42,0.08,0.02,0.47,0.56,0.21,0.34,0.11,0.26],[63.75,37.62,0.35,0.45,0.08,0.02,0.48,0.57,0.21,0.34,0.11,0.26],[63.75,43.27,0.33,0.42,0.08,0.02,0.47,0.56,0.21,0.33,0.11,0.26],[63.75,48.92,0.34,0.4,0.08,0.02,0.47,0.55,0.21,0.33,0.11,0.25],[63.75,54.58,0.34,0.43,0.08,0.02,0.47,0.56,0.21,0.34,0.11,0.25],[63.75,60.23,0.33,0.42,0.08,0.02,0.47,0.56,0.21,0.33,0.11,0.26],[63.75,65.88,0.33,0.41,0.08,0.02,0.47,0.56,0.21,0.33,0.11,0.26],[63.75,71.53,0.33,0.43,0.08,0.02,0.47,0.56,0.21,0.35,0.11,0.27],[63.75,77.18,0.33,0.46,0.08,0.02,0.48,0.57,0.21,0.35,0.11,0.27],[63.75,82.84,0.34,0.46,0.08,0.02,0.48,0.57,0.21,0.36,0.11,0.27],[63.75,88.49,0.33,0.46,0.08,0.02,0.48,0.57,0.21,0.36,0.11,0.25],[63.75,94.14,0.34,0.47,0.08,0.02,0.48,0.57,0.21,0.36,0.11,0.26],[63.75,99.79,0.35,0.46,0.08,0.02,0.48,0.57,0.21,0.36,0.11,0.26],[63.75,105.45,0.35,0.47,0.08,0.02,0.48,0.57,0.21,0.37,0.11,0.26],[63.75,111.1,0.34,0.44,0.08,0.02,0.48,0.56,0.21,0.35,0.11,0.26],[63.75,116.75,0.35,0.41,0.08,0.02,0.47,0.56,0.21,0.34,0.11,0.25],[63.75,122.4,0.35,0.34,0.08,0.02,0.46,0.54,0.21,0.33,0.11,0.24],[63.75,128.06,0.35,0.29,0.08,0.02,0.46,0.52,0.21,0.31,0.11,0.24],[63.75,133.71,0.34,0.28,0.08,0.02,0.45,0.52,0.21,0.31,0.11,0.25],[63.75,139.36,0.35,0.27,0.08,0.02,0.45,0.52,0.21,0.31,0.11,0.25],[63.75,145.01,0.34,0.26,0.08,0.02,0.45,0.52,0.21,0.31,0.11,0.26],[63.75,150.67,0.35,0.28,0.08,0.02,0.45,0.52,0.21,0.32,0.11,0.26],[63.75,156.32,0.36,0.27,0.08,0.02,0.45,0.52,0.21,0.32,0.11,0.25],[63.75,161.97,0.5,0.3,0.08,0.3,0.46,0.53,0.21,0.33,0.11,0.27],[63.75,167.62,0.47,0.34,0.08,0.2,0.46,0.54,0.21,0.34,0.11,0.27],[63.75,173.28,0.37,0.31,0.08,0.02,0.46,0.53,0.21,0.34,0.11,0.28],[66.25,-164.48,0.36,0.3,0.08,0.02,0.57,0.49,0.27,0.45,0.15,0.37],[66.25,-158.27,0.36,0.35,0.08,0.02,0.58,0.51,0.27,0.46,0.15,0.36],[66.25,-152.07,0.36,0.38,0.08,0.02,0.58,0.52,0.27,0.46,0.15,0.37],[66.25,-145.86,0.36,0.48,0.08,0.02,0.59,0.54,0.27,0.47,0.15,0.38],[66.25,-139.65,0.37,0.51,0.08,0.02,0.59,0.55,0.27,0.48,0.15,0.39],[66.25,-133.44,0.37,0.48,0.08,0.02,0.59,0.54,0.27,0.48,0.15,0.39],[66.25,-127.24,0.36,0.48,0.08,0.02,0.59,0.54,0.27,0.47,0.15,0.38],[66.25,-121.03,0.35,0.48,0.08,0.02,0.59,0.54,0.27,0.47,0.15,0.37],[66.25,-114.82,0.35,0.46,0.08,0.02,0.59,0.53,0.27,0.47,0.15,0.37],[66.25,-108.62,0.35,0.45,0.08,0.02,0.59,0.53,0.27,0.46,0.15,0.38],[66.25,-102.41,0.34,0.42,0.08,0.02,0.59,0.53,0.27,0.45,0.15,0.39],[66.25,-96.2,0.35,0.43,0.08,0.02,0.59,0.53,0.27,0.44,0.15,0.4],[66.25,-89.99,0.36,0.44,0.08,0.02,0.59,0.53,0.27,0.44,0.15,0.39],[66.25,-83.79,0.35,0.51,0.08,0.02,0.6,0.55,0.27,0.46,0.15,0.39],[66.25,-77.58,0.35,0.53,0.08,0.02,0.6,0.55,0.27,0.48,0.15,0.39],[66.25,-71.37,0.35,0.52,0.08,0.02,0.6,0.55,0.27,0.48,0.15,0.39],[66.25,-65.16,0.35,0.49,0.08,0.02,0.59,0.54,0.27,0.49,0.15,0.38],[66.25,-58.96,0.35,0.53,0.08,0.02,0.6,0.55,0.27,0.5,0.15,0.37],[66.25,-52.75,0.36,0.53,0.08,0.02,0.6,0.55,0.27,0.51,0.15,0.37],[66.25,-46.54,0.37,0.54,0.08,0.02,0.6,0.55,0.27,0.51,0.15,0.38],[66.25,-40.33,0.38,0.54,0.08,0.02,0.6,0.55,0.27,0.51,0.15,0.38],[66.25,-34.13,0.37,0.5,0.08,0.02,0.59,0.54,0.27,0.51,0.15,0.38],[66.25,-27.92,0.37,0.49,0.08,0.02,0.59,0.54,0.27,0.5,0.15,0.39],[66.25,-21.71,0.37,0.49,0.08,0.02,0.59,0.54,0.27,0.51,0.15,0.38],[66.25,-15.5,0.36,0.47,0.08,0.02,0.59,0.54,0.27,0.51,0.15,0.38],[66.25,-9.3,0.39,0.43,0.08,0.05,0.59,0.53,0.27,0.51,0.15,0.38],[66.25,-3.09,0.37,0.41,0.08,0.02,0.58,0.52,0.27,0.51,0.15,0.38],[66.25,3.12,0.37,0.43,0.08,0.02,0.59,0.53,0.27,0.51,0.15,0.38],[66.25,9.32,0.36,0.44,0.08,0.02,0.59,0.53,0.27,0.5,0.15,0.38],[66.25,34.15,0.36,0.4,0.08,0.02,0.58,0.52,0.27,0.47,0.15,0.37],[66.25,40.36,0.35,0.41,0.08,0.02,0.58,0.52,0.27,0.47,0.15,0.36],[68.75,-176.55,0.35,0.3,0.08,0.02,0.68,0.46,0.33,0.59,0.18,0.5],[68.75,-169.65,0.36,0.28,0.08,0.02,0.68,0.45,0.33,0.58,0.18,0.5],[68.75,-162.76,0.37,0.28,0.08,0.02,0.68,0.45,0.33,0.58,0.18,0.47],[68.75,-155.86,0.37,0.33,0.08,0.02,0.69,0.47,0.33,0.58,0.18,0.47],[68.75,-148.96,0.37,0.38,0.08,0.02,0.69,0.48,0.33,0.58,0.18,0.49],[68.75,-142.06,0.37,0.42,0.08,0.02,0.7,0.49,0.33,0.59,0.18,0.51],[68.75,-135.16,0.37,0.42,0.08,0.02,0.7,0.49,0.33,0.59,0.18,0.52],[68.75,-128.27,0.36,0.46,0.08,0.02,0.7,0.5,0.33,0.6,0.18,0.5],[68.75,-121.37,0.36,0.47,0.08,0.02,0.7,0.5,0.33,0.6,0.18,0.49],[68.75,-114.47,0.35,0.46,0.08,0.02,0.7,0.5,0.33,0.59,0.18,0.49],[68.75,-107.57,0.34,0.47,0.08,0.02,0.7,0.5,0.33,0.59,0.18,0.49],[68.75,-100.68,0.34,0.47,0.08,0.02,0.7,0.5,0.33,0.58,0.18,0.52],[68.75,-93.78,0.34,0.47,0.08,0.02,0.7,0.5,0.33,0.57,0.18,0.53],[68.75,-86.88,0.35,0.48,0.08,0.02,0.7,0.5,0.33,0.57,0.18,0.53],[68.75,-79.98,0.35,0.51,0.08,0.02,0.71,0.51,0.33,0.59,0.18,0.52],[68.75,-73.09,0.35,0.52,0.08,0.02,0.71,0.51,0.33,0.6,0.18,0.51],[68.75,-66.19,0.35,0.51,0.08,0.02,0.71,0.51,0.33,0.61,0.18,0.5],[68.75,-59.29,0.36,0.55,0.08,0.02,0.71,0.52,0.33,0.63,0.18,0.49],[68.75,-52.39,0.36,0.56,0.08,0.02,0.71,0.52,0.33,0.63,0.18,0.5],[68.75,-45.49,0.37,0.5,0.08,0.02,0.71,0.51,0.33,0.63,0.18,0.5],[68.75,-38.6,0.38,0.54,0.08,0.02,0.71,0.52,0.33,0.64,0.18,0.5],[68.75,-31.7,0.38,0.51,0.08,0.02,0.71,0.51,0.33,0.64,0.18,0.5],[68.75,-24.8,0.37,0.48,0.08,0.02,0.7,0.5,0.33,0.63,0.18,0.49],[68.75,-17.9,0.37,0.47,0.08,0.02,0.7,0.5,0.33,0.64,0.18,0.5],[68.75,-11.01,0.37,0.42,0.08,0.02,0.7,0.49,0.33,0.64,0.18,0.51],[68.75,-4.11,0.36,0.37,0.08,0.02,0.69,0.48,0.33,0.64,0.18,0.51],[68.75,2.79,0.36,0.36,0.08,0.02,0.69,0.48,0.33,0.63,0.18,0.51],[68.75,9.69,0.36,0.39,0.08,0.02,0.69,0.48,0.33,0.63,0.18,0.5],[68.75,16.59,0.36,0.39,0.08,0.02,0.69,0.48,0.33,0.62,0.18,0.49],[68.75,44.18,0.34,0.4,0.08,0.02,0.7,0.49,0.33,0.6,0.18,0.47],[68.75,51.07,0.35,0.38,0.08,0.02,0.69,0.48,0.33,0.6,0.18,0.47],[68.75,57.97,0.34,0.38,0.08,0.02,0.69,0.48,0.33,0.59,0.18,0.47],[71.25,-121.67,0.36,0.47,0.08,0.02,0.81,0.47,0.38,0.71,0.21,0.61],[71.25,-113.89,0.35,0.47,0.08,0.02,0.81,0.47,0.38,0.71,0.21,0.61],[71.25,-106.11,0.35,0.47,0.08,0.02,0.81,0.47,0.38,0.7,0.21,0.63],[71.25,-82.78,0.34,0.5,0.08,0.02,0.81,0.48,0.38,0.7,0.21,0.66],[71.25,-75,0.35,0.54,0.08,0.02,0.81,0.48,0.38,0.71,0.21,0.64],[71.25,-51.67,0.36,0.57,0.08,0.02,0.82,0.49,0.38,0.75,0.21,0.6],[71.25,-43.89,0.37,0.52,0.08,0.02,0.81,0.48,0.38,0.75,0.21,0.61],[71.25,-36.12,0.37,0.52,0.08,0.02,0.81,0.48,0.38,0.75,0.21,0.63],[71.25,-28.34,0.36,0.49,0.08,0.02,0.81,0.47,0.38,0.75,0.21,0.62],[71.25,-20.56,0.36,0.5,0.08,0.02,0.81,0.48,0.38,0.76,0.21,0.63],[71.25,-12.78,0.36,0.44,0.08,0.02,0.8,0.46,0.38,0.76,0.21,0.64],[71.25,-5.01,0.35,0.37,0.08,0.02,0.79,0.44,0.38,0.75,0.21,0.64],[71.25,2.77,0.36,0.36,0.08,0.02,0.79,0.44,0.38,0.75,0.21,0.65],[71.25,10.55,0.36,0.38,0.08,0.02,0.8,0.45,0.38,0.75,0.21,0.64],[71.25,18.33,0.35,0.39,0.08,0.02,0.8,0.45,0.38,0.74,0.21,0.62],[71.25,26.1,0.35,0.37,0.08,0.02,0.79,0.44,0.38,0.73,0.21,0.6],[71.25,33.88,0.34,0.35,0.08,0.02,0.79,0.44,0.38,0.72,0.21,0.57],[71.25,41.66,0.34,0.36,0.08,0.02,0.79,0.44,0.38,0.72,0.21,0.56],[71.25,80.55,0.34,0.37,0.08,0.02,0.79,0.45,0.38,0.73,0.21,0.63],[71.25,88.32,0.34,0.35,0.08,0.02,0.79,0.44,0.38,0.73,0.21,0.64],[71.25,96.1,0.34,0.34,0.08,0.02,0.79,0.44,0.38,0.73,0.21,0.64],[71.25,103.88,0.34,0.36,0.08,0.02,0.79,0.44,0.38,0.73,0.21,0.63],[71.25,111.66,0.35,0.35,0.08,0.02,0.79,0.44,0.38,0.72,0.21,0.59],[71.25,119.43,0.35,0.31,0.08,0.02,0.79,0.43,0.38,0.7,0.21,0.55],[71.25,127.21,0.36,0.29,0.08,0.02,0.78,0.42,0.38,0.68,0.21,0.53],[71.25,134.99,0.36,0.29,0.08,0.02,0.78,0.42,0.38,0.68,0.21,0.52],[71.25,142.77,0.36,0.27,0.08,0.02,0.78,0.42,0.38,0.67,0.21,0.52],[71.25,150.54,0.35,0.28,0.08,0.02,0.78,0.42,0.38,0.67,0.21,0.54],[73.75,-121.93,0.36,0.48,0.08,0.02,0.89,0.44,0.42,0.8,0.23,0.72],[73.75,-95.13,0.34,0.49,0.08,0.02,0.89,0.44,0.42,0.79,0.23,0.76],[73.75,-86.19,0.34,0.5,0.08,0.02,0.89,0.45,0.42,0.79,0.23,0.76],[73.75,-50.46,0.37,0.54,0.08,0.02,0.9,0.45,0.42,0.83,0.23,0.7],[73.75,-41.52,0.37,0.52,0.08,0.02,0.9,0.45,0.42,0.84,0.23,0.72],[73.75,-32.59,0.36,0.52,0.08,0.02,0.9,0.45,0.42,0.85,0.23,0.73],[73.75,-23.65,0.37,0.52,0.08,0.02,0.89,0.45,0.42,0.85,0.23,0.75],[73.75,56.75,0.34,0.32,0.08,0.02,0.87,0.4,0.42,0.81,0.23,0.68],[73.75,83.55,0.35,0.35,0.08,0.02,0.87,0.41,0.42,0.82,0.23,0.73],[73.75,92.49,0.35,0.35,0.08,0.02,0.87,0.41,0.42,0.82,0.23,0.74],[73.75,101.42,0.35,0.38,0.08,0.02,0.88,0.42,0.42,0.83,0.23,0.71],[73.75,110.36,0.36,0.36,0.08,0.02,0.88,0.41,0.42,0.82,0.23,0.66],[76.25,-122.15,0.36,0.45,0.08,0.02,0.94,0.41,0.44,0.84,0.25,0.77],[76.25,-101.11,0.35,0.48,0.08,0.02,0.94,0.41,0.44,0.85,0.25,0.8],[76.25,-59.04,0.36,0.55,0.08,0.02,0.95,0.43,0.44,0.87,0.25,0.75],[76.25,-48.52,0.36,0.53,0.08,0.02,0.95,0.43,0.44,0.88,0.25,0.77],[76.25,-38.01,0.36,0.51,0.08,0.02,0.95,0.42,0.44,0.89,0.25,0.79],[76.25,-27.49,0.36,0.51,0.08,0.02,0.94,0.42,0.44,0.9,0.25,0.8],[76.25,67.17,0.35,0.39,0.08,0.02,0.93,0.39,0.44,0.87,0.25,0.75],[76.25,98.73,0.36,0.37,0.08,0.02,0.93,0.39,0.44,0.88,0.25,0.79],[76.25,109.25,0.37,0.35,0.08,0.02,0.93,0.38,0.44,0.86,0.25,0.73],[78.75,-111.25,0.35,0.43,0.08,0.02,0.95,0.38,0.45,0.85,0.25,0.81],[78.75,-86.25,0.35,0.47,0.08,0.02,0.95,0.39,0.45,0.86,0.25,0.79],[78.75,-61.25,0.35,0.51,0.08,0.02,0.96,0.4,0.45,0.89,0.25,0.77],[78.75,-48.75,0.36,0.5,0.08,0.02,0.96,0.4,0.45,0.89,0.25,0.79],[78.75,-36.25,0.36,0.5,0.08,0.02,0.96,0.4,0.45,0.9,0.25,0.81],[78.75,-23.75,0.36,0.48,0.08,0.02,0.95,0.4,0.45,0.91,0.25,0.82],[78.75,13.75,0.35,0.43,0.08,0.02,0.95,0.38,0.45,0.91,0.25,0.8],[78.75,101.25,0.37,0.39,0.08,0.02,0.94,0.37,0.45,0.89,0.25,0.77],[81.25,-86.25,0.35,0.46,0.08,0.02,0.95,0.37,0.45,0.87,0.25,0.74],[81.25,-73.75,0.34,0.45,0.08,0.02,0.95,0.37,0.45,0.88,0.25,0.75],[81.25,-61.25,0.35,0.48,0.08,0.02,0.95,0.37,0.45,0.89,0.25,0.76],[81.25,-48.75,0.35,0.49,0.08,0.02,0.95,0.38,0.45,0.89,0.25,0.78],[81.25,-36.25,0.35,0.5,0.08,0.02,0.95,0.38,0.45,0.9,0.25,0.79],[81.25,-23.75,0.36,0.46,0.08,0.02,0.95,0.37,0.45,0.91,0.25,0.8]]}*
���� 8d139ba77280c03ac7007f11fd925912
�u
data/earth_sites.json�u{
 "note": "DEMO DATA - criterion values are fabricated placeholders (0-1). Replace with real data.",
 "criteria": [
  "geology",
  "topography",
  "aeolian",
  "caves",
  "temperature",
  "uv",
  "aridity",
  "ice",
  "salts",
  "periglacial"
 ],
 "sites": [
  {
   "id": "atacama",
   "name": "Yungay, Atacama Desert",
   "country": "Chile",
   "lat": -24.08,
   "lon": -69.92,
   "description": "The driest non-polar desert on Earth. Hyper-arid soils, nitrate and perchlorate salts and extreme UV make it a classic analog for Martian soil chemistry and life detection.",
   "values": {
    "geology": 0.72,
    "topography": 0.62,
    "aeolian": 0.55,
    "caves": 0.12,
    "temperature": 0.58,
    "uv": 0.97,
    "aridity": 0.98,
    "ice": 0.08,
    "salts": 0.86,
    "periglacial": 0.1
   }
  },
  {
   "id": "dryvalleys",
   "name": "Wright Valley, McMurdo Dry Valleys",
   "country": "Antarctica",
   "lat": -77.52,
   "lon": 161.85,
   "description": "Ice-free polar desert with katabatic winds, sublimating ground ice, polygonal terrain and briny ponds. One of the closest climate analogs to Mars.",
   "values": {
    "geology": 0.55,
    "topography": 0.7,
    "aeolian": 0.62,
    "caves": 0.1,
    "temperature": 0.95,
    "uv": 0.7,
    "aridity": 0.94,
    "ice": 0.9,
    "salts": 0.8,
    "periglacial": 0.92
   }
  },
  {
   "id": "donjuan",
   "name": "Don Juan Pond",
   "country": "Antarctica",
   "lat": -77.56,
   "lon": 161.19,
   "description": "A calcium-chloride brine pond that stays liquid down to about −50 °C. Water tracks feeding it are a model for deliquescence-driven brines on Mars.",
   "values": {
    "geology": 0.48,
    "topography": 0.55,
    "aeolian": 0.3,
    "caves": 0.05,
    "temperature": 0.96,
    "uv": 0.68,
    "aridity": 0.9,
    "ice": 0.78,
    "salts": 0.99,
    "periglacial": 0.7
   }
  },
  {
   "id": "haughton",
   "name": "Haughton Crater, Devon Island",
   "country": "Canada",
   "lat": 75.38,
   "lon": -89.68,
   "description": "A 23 km impact crater in a polar desert. Home of the NASA Haughton-Mars Project for testing rovers, suits and field operations.",
   "values": {
    "geology": 0.66,
    "topography": 0.74,
    "aeolian": 0.3,
    "caves": 0.08,
    "temperature": 0.86,
    "uv": 0.55,
    "aridity": 0.8,
    "ice": 0.8,
    "salts": 0.42,
    "periglacial": 0.88
   }
  },
  {
   "id": "riotinto",
   "name": "Río Tinto",
   "country": "Spain",
   "lat": 37.72,
   "lon": -6.55,
   "description": "Acidic, iron-rich river with jarosite and other sulfates that mirror the sulfate deposits seen at Meridiani Planum.",
   "values": {
    "geology": 0.93,
    "topography": 0.48,
    "aeolian": 0.12,
    "caves": 0.2,
    "temperature": 0.38,
    "uv": 0.62,
    "aridity": 0.4,
    "ice": 0.02,
    "salts": 0.55,
    "periglacial": 0.05
   }
  },
  {
   "id": "maunakea",
   "name": "Mauna Kea summit",
   "country": "USA (Hawaiʻi)",
   "lat": 19.82,
   "lon": -155.47,
   "description": "High-altitude basaltic volcano with palagonitic, Mars-like regolith, strong UV and thin air. Used for in-situ resource utilization (ISRU) and rover tests.",
   "values": {
    "geology": 0.85,
    "topography": 0.8,
    "aeolian": 0.25,
    "caves": 0.55,
    "temperature": 0.52,
    "uv": 0.92,
    "aridity": 0.66,
    "ice": 0.2,
    "salts": 0.2,
    "periglacial": 0.32
   }
  },
  {
   "id": "kau",
   "name": "Kaʻū Desert, Kīlauea",
   "country": "USA (Hawaiʻi)",
   "lat": 19.37,
   "lon": -155.33,
   "description": "Basaltic tephra plains, fresh lava flows and skylit lava tubes. A strong analog for volcanic terrain and caves on Mars.",
   "values": {
    "geology": 0.88,
    "topography": 0.58,
    "aeolian": 0.4,
    "caves": 0.82,
    "temperature": 0.35,
    "uv": 0.85,
    "aridity": 0.6,
    "ice": 0.02,
    "salts": 0.22,
    "periglacial": 0.05
   }
  },
  {
   "id": "holuhraun",
   "name": "Holuhraun lava field",
   "country": "Iceland",
   "lat": 64.85,
   "lon": -16.83,
   "description": "One of the youngest flood basalts on Earth, with glacial outwash and black basaltic sand dunes, much like Martian volcanic plains.",
   "values": {
    "geology": 0.86,
    "topography": 0.6,
    "aeolian": 0.58,
    "caves": 0.45,
    "temperature": 0.72,
    "uv": 0.4,
    "aridity": 0.55,
    "ice": 0.55,
    "salts": 0.18,
    "periglacial": 0.66
   }
  },
  {
   "id": "bockfjord",
   "name": "Bockfjord Volcanic Complex, Svalbard",
   "country": "Norway",
   "lat": 79.43,
   "lon": 13.32,
   "description": "Arctic volcanic center with carbonate globules similar to those in Martian meteorite ALH84001. Used as an AMASE test site.",
   "values": {
    "geology": 0.84,
    "topography": 0.66,
    "aeolian": 0.2,
    "caves": 0.18,
    "temperature": 0.88,
    "uv": 0.45,
    "aridity": 0.7,
    "ice": 0.85,
    "salts": 0.3,
    "periglacial": 0.86
   }
  },
  {
   "id": "mdrs",
   "name": "Mars Desert Research Station, Hanksville",
   "country": "USA (Utah)",
   "lat": 38.41,
   "lon": -110.79,
   "description": "Red Jurassic mudstones, clays and gypsum near the Mars Society habitat used for long-duration crew simulations.",
   "values": {
    "geology": 0.8,
    "topography": 0.72,
    "aeolian": 0.6,
    "caves": 0.15,
    "temperature": 0.55,
    "uv": 0.72,
    "aridity": 0.82,
    "ice": 0.05,
    "salts": 0.5,
    "periglacial": 0.12
   }
  },
  {
   "id": "kelso",
   "name": "Kelso Dunes, Mojave Desert",
   "country": "USA (California)",
   "lat": 34.9,
   "lon": -115.7,
   "description": "Tall booming sand dunes and desert pavement. Used to test rover traction and dune morphology.",
   "values": {
    "geology": 0.55,
    "topography": 0.55,
    "aeolian": 0.95,
    "caves": 0.1,
    "temperature": 0.6,
    "uv": 0.8,
    "aridity": 0.88,
    "ice": 0.02,
    "salts": 0.4,
    "periglacial": 0.05
   }
  },
  {
   "id": "badwater",
   "name": "Badwater Basin, Death Valley",
   "country": "USA (California)",
   "lat": 36.23,
   "lon": -116.77,
   "description": "Salt pans, evaporites and extreme heat below sea level, with Mars Hill and ancient lake beds nearby.",
   "values": {
    "geology": 0.7,
    "topography": 0.3,
    "aeolian": 0.55,
    "caves": 0.1,
    "temperature": 0.45,
    "uv": 0.82,
    "aridity": 0.94,
    "ice": 0.01,
    "salts": 0.82,
    "periglacial": 0.08
   }
  },
  {
   "id": "sossusvlei",
   "name": "Sossusvlei, Namib Desert",
   "country": "Namibia",
   "lat": -24.73,
   "lon": 15.29,
   "description": "Giant star and linear dunes with fog-fed moisture, comparable to the large Martian dune fields.",
   "values": {
    "geology": 0.42,
    "topography": 0.5,
    "aeolian": 0.99,
    "caves": 0.05,
    "temperature": 0.5,
    "uv": 0.85,
    "aridity": 0.92,
    "ice": 0,
    "salts": 0.48,
    "periglacial": 0.02
   }
  },
  {
   "id": "timanfaya",
   "name": "Timanfaya, Lanzarote",
   "country": "Spain",
   "lat": 29.02,
   "lon": -13.75,
   "description": "Barren basaltic lava fields, cinder cones and lava tubes. Used by the ESA PANGAEA geology training course.",
   "values": {
    "geology": 0.87,
    "topography": 0.62,
    "aeolian": 0.35,
    "caves": 0.78,
    "temperature": 0.42,
    "uv": 0.78,
    "aridity": 0.75,
    "ice": 0,
    "salts": 0.28,
    "periglacial": 0.02
   }
  },
  {
   "id": "pilbara",
   "name": "Dresser Formation, Pilbara",
   "country": "Australia",
   "lat": -21.15,
   "lon": 119.42,
   "description": "3.5 billion-year-old stromatolites and hydrothermal silica: a reference for searching ancient Martian rocks for biosignatures.",
   "values": {
    "geology": 0.9,
    "topography": 0.52,
    "aeolian": 0.3,
    "caves": 0.12,
    "temperature": 0.4,
    "uv": 0.88,
    "aridity": 0.8,
    "ice": 0,
    "salts": 0.36,
    "periglacial": 0.02
   }
  },
  {
   "id": "lonar",
   "name": "Lonar Crater",
   "country": "India",
   "lat": 19.98,
   "lon": 76.51,
   "description": "A young impact crater in Deccan basalt with a saline, alkaline lake. A rare basalt-hosted impact analog.",
   "values": {
    "geology": 0.86,
    "topography": 0.7,
    "aeolian": 0.1,
    "caves": 0.1,
    "temperature": 0.3,
    "uv": 0.8,
    "aridity": 0.45,
    "ice": 0,
    "salts": 0.62,
    "periglacial": 0.02
   }
  },
  {
   "id": "dallol",
   "name": "Dallol, Danakil Depression",
   "country": "Ethiopia",
   "lat": 14.24,
   "lon": 40.3,
   "description": "Hyper-acidic, hypersaline hydrothermal field with sulfur, iron oxides and potash salts. An extreme habitability test bed.",
   "values": {
    "geology": 0.92,
    "topography": 0.35,
    "aeolian": 0.2,
    "caves": 0.08,
    "temperature": 0.2,
    "uv": 0.9,
    "aridity": 0.85,
    "ice": 0,
    "salts": 0.95,
    "periglacial": 0
   }
  },
  {
   "id": "qaidam",
   "name": "Dalangtan Playa, Qaidam Basin",
   "country": "China",
   "lat": 38.5,
   "lon": 92,
   "description": "High, cold, hyper-arid playa with chlorides, sulfates and wind-carved yardangs, very similar to Martian evaporite basins.",
   "values": {
    "geology": 0.82,
    "topography": 0.78,
    "aeolian": 0.8,
    "caves": 0.05,
    "temperature": 0.7,
    "uv": 0.88,
    "aridity": 0.93,
    "ice": 0.1,
    "salts": 0.88,
    "periglacial": 0.25
   }
  },
  {
   "id": "lavabeds",
   "name": "Lava Beds National Monument",
   "country": "USA (California)",
   "lat": 41.71,
   "lon": -121.51,
   "description": "More than 700 lava tube caves with ice deposits and skylights. Used for cave robotics and subsurface life detection.",
   "values": {
    "geology": 0.8,
    "topography": 0.65,
    "aeolian": 0.12,
    "caves": 0.97,
    "temperature": 0.55,
    "uv": 0.6,
    "aridity": 0.55,
    "ice": 0.35,
    "salts": 0.12,
    "periglacial": 0.2
   }
  },
  {
   "id": "cratersmoon",
   "name": "Craters of the Moon",
   "country": "USA (Idaho)",
   "lat": 43.42,
   "lon": -113.52,
   "description": "Basaltic fissure eruptions, spatter cones and lava tubes. Used in NASA's FINESSE and BASALT field campaigns.",
   "values": {
    "geology": 0.9,
    "topography": 0.68,
    "aeolian": 0.3,
    "caves": 0.88,
    "temperature": 0.62,
    "uv": 0.7,
    "aridity": 0.7,
    "ice": 0.2,
    "salts": 0.15,
    "periglacial": 0.3
   }
  },
  {
   "id": "losthammer",
   "name": "Lost Hammer Spring, Axel Heiberg Island",
   "country": "Canada",
   "lat": 79.07,
   "lon": -90.35,
   "description": "Perennial sub-zero hypersaline spring flowing through permafrost, an analog for brines and methane seeps on Mars.",
   "values": {
    "geology": 0.7,
    "topography": 0.66,
    "aeolian": 0.1,
    "caves": 0.08,
    "temperature": 0.96,
    "uv": 0.45,
    "aridity": 0.72,
    "ice": 0.92,
    "salts": 0.85,
    "periglacial": 0.82
   }
  },
  {
   "id": "uyuni",
   "name": "Salar de Uyuni",
   "country": "Bolivia",
   "lat": -20.13,
   "lon": -67.49,
   "description": "The world's largest salt flat, at 3,650 m. Evaporite crusts, high UV and polygonal salt ridges.",
   "values": {
    "geology": 0.76,
    "topography": 0.85,
    "aeolian": 0.15,
    "caves": 0.02,
    "temperature": 0.62,
    "uv": 0.95,
    "aridity": 0.8,
    "ice": 0.05,
    "salts": 0.92,
    "periglacial": 0.35
   }
  },
  {
   "id": "whitesands",
   "name": "White Sands",
   "country": "USA (New Mexico)",
   "lat": 32.88,
   "lon": -106.33,
   "description": "Gypsum dune field, the largest on Earth, analogous to the sulfate-rich dunes around the Martian north pole.",
   "values": {
    "geology": 0.78,
    "topography": 0.55,
    "aeolian": 0.96,
    "caves": 0.02,
    "temperature": 0.52,
    "uv": 0.78,
    "aridity": 0.8,
    "ice": 0.02,
    "salts": 0.62,
    "periglacial": 0.05
   }
  },
  {
   "id": "tolbachik",
   "name": "Tolbachik volcano, Kamchatka",
   "country": "Russia",
   "lat": 55.83,
   "lon": 160.33,
   "description": "Active basaltic volcano with fumarolic minerals, lava tubes and snowfields. A cold volcanic analog.",
   "values": {
    "geology": 0.88,
    "topography": 0.72,
    "aeolian": 0.3,
    "caves": 0.65,
    "temperature": 0.78,
    "uv": 0.5,
    "aridity": 0.4,
    "ice": 0.6,
    "salts": 0.25,
    "periglacial": 0.62
   }
  },
  {
   "id": "wadirum",
   "name": "Wadi Rum",
   "country": "Jordan",
   "lat": 29.58,
   "lon": 35.42,
   "description": "Red sandstone desert used as a Mars film set and for Austrian Space Forum (ÖWF) AMADEE analog missions.",
   "values": {
    "geology": 0.62,
    "topography": 0.7,
    "aeolian": 0.82,
    "caves": 0.15,
    "temperature": 0.48,
    "uv": 0.84,
    "aridity": 0.9,
    "ice": 0,
    "salts": 0.35,
    "periglacial": 0.02
   }
  },
  {
   "id": "lut",
   "name": "Dasht-e Lut yardangs",
   "country": "Iran",
   "lat": 30.5,
   "lon": 59,
   "description": "Among the hottest surfaces on Earth, with giant wind-sculpted yardangs like those of the Medusae Fossae Formation.",
   "values": {
    "geology": 0.66,
    "topography": 0.6,
    "aeolian": 0.92,
    "caves": 0.05,
    "temperature": 0.3,
    "uv": 0.86,
    "aridity": 0.97,
    "ice": 0,
    "salts": 0.58,
    "periglacial": 0
   }
  },
  {
   "id": "teide",
   "name": "Las Cañadas del Teide, Tenerife",
   "country": "Spain",
   "lat": 28.27,
   "lon": -16.64,
   "description": "High volcanic caldera used to test ExoMars instruments, with basaltic and phonolitic lavas and clear, high-UV skies.",
   "values": {
    "geology": 0.84,
    "topography": 0.82,
    "aeolian": 0.25,
    "caves": 0.45,
    "temperature": 0.5,
    "uv": 0.88,
    "aridity": 0.7,
    "ice": 0.05,
    "salts": 0.2,
    "periglacial": 0.1
   }
  },
  {
   "id": "pinacate",
   "name": "Pinacate Peaks",
   "country": "Mexico",
   "lat": 31.77,
   "lon": -113.5,
   "description": "Maar craters, cinder cones and lava fields bordering the Gran Desierto dune sea. Apollo astronauts trained here.",
   "values": {
    "geology": 0.84,
    "topography": 0.6,
    "aeolian": 0.8,
    "caves": 0.4,
    "temperature": 0.45,
    "uv": 0.82,
    "aridity": 0.88,
    "ice": 0,
    "salts": 0.3,
    "periglacial": 0.02
   }
  },
  {
   "id": "ergchebbi",
   "name": "Erg Chebbi, Sahara",
   "country": "Morocco",
   "lat": 31.15,
   "lon": -3.97,
   "description": "Star dunes beside hamada plains and evaporites. Used for ESA and Mars rover field testing.",
   "values": {
    "geology": 0.55,
    "topography": 0.62,
    "aeolian": 0.97,
    "caves": 0.05,
    "temperature": 0.42,
    "uv": 0.85,
    "aridity": 0.95,
    "ice": 0,
    "salts": 0.45,
    "periglacial": 0
   }
  },
  {
   "id": "utqiagvik",
   "name": "Utqiaġvik polygon tundra",
   "country": "USA (Alaska)",
   "lat": 71.29,
   "lon": -156.79,
   "description": "Ice-wedge polygons on continuous permafrost that closely resemble the patterned ground at the Phoenix landing site.",
   "values": {
    "geology": 0.35,
    "topography": 0.4,
    "aeolian": 0.15,
    "caves": 0.02,
    "temperature": 0.85,
    "uv": 0.4,
    "aridity": 0.45,
    "ice": 0.97,
    "salts": 0.35,
    "periglacial": 0.97
   }
  }
 ]
}*
���� 9090f9f58bd85364ef34bd354286400a
�:
data/mars_regions.json�:{
 "note": "DEMO DATA - criterion values are fabricated placeholders (0-1). Replace with real data.",
 "criteria": [
  "geology",
  "topography",
  "aeolian",
  "caves",
  "temperature",
  "uv",
  "aridity",
  "ice",
  "salts",
  "periglacial"
 ],
 "regions": [
  {
   "name": "Jezero Crater",
   "lat": 18.38,
   "lon": 77.58,
   "description": "Ancient delta and lake basin explored by Perseverance. Carbonates and clays.",
   "values": {
    "geology": 0.84,
    "topography": 0.48,
    "aeolian": 0.55,
    "caves": 0.1,
    "temperature": 0.7,
    "uv": 0.9,
    "aridity": 0.92,
    "ice": 0.22,
    "salts": 0.45,
    "periglacial": 0.2
   }
  },
  {
   "name": "Gale Crater",
   "lat": -5.4,
   "lon": 137.8,
   "description": "Mount Sharp layered sediments explored by Curiosity, with clays, sulfates and active dunes.",
   "values": {
    "geology": 0.8,
    "topography": 0.62,
    "aeolian": 0.78,
    "caves": 0.12,
    "temperature": 0.62,
    "uv": 0.9,
    "aridity": 0.9,
    "ice": 0.15,
    "salts": 0.5,
    "periglacial": 0.15
   }
  },
  {
   "name": "Meridiani Planum",
   "lat": -1.95,
   "lon": -5.5,
   "description": "Hematite blueberries and jarosite sulfates explored by Opportunity.",
   "values": {
    "geology": 0.88,
    "topography": 0.4,
    "aeolian": 0.65,
    "caves": 0.05,
    "temperature": 0.6,
    "uv": 0.92,
    "aridity": 0.94,
    "ice": 0.08,
    "salts": 0.6,
    "periglacial": 0.05
   }
  },
  {
   "name": "Utopia Planitia",
   "lat": 46.7,
   "lon": 117.5,
   "description": "Vast northern plain with scalloped terrain and buried ice.",
   "values": {
    "geology": 0.5,
    "topography": 0.3,
    "aeolian": 0.35,
    "caves": 0.1,
    "temperature": 0.85,
    "uv": 0.75,
    "aridity": 0.85,
    "ice": 0.85,
    "salts": 0.55,
    "periglacial": 0.8
   }
  },
  {
   "name": "Hellas Planitia",
   "lat": -42.4,
   "lon": 70.5,
   "description": "Deepest impact basin. Higher pressure, gullies and debris-covered glaciers.",
   "values": {
    "geology": 0.55,
    "topography": 0.15,
    "aeolian": 0.4,
    "caves": 0.08,
    "temperature": 0.82,
    "uv": 0.65,
    "aridity": 0.8,
    "ice": 0.7,
    "salts": 0.7,
    "periglacial": 0.72
   }
  },
  {
   "name": "Arsia Mons",
   "lat": -8.26,
   "lon": -120.1,
   "description": "Tharsis shield volcano with lava tubes and cave skylights on its flanks.",
   "values": {
    "geology": 0.88,
    "topography": 0.98,
    "aeolian": 0.3,
    "caves": 0.95,
    "temperature": 0.8,
    "uv": 0.98,
    "aridity": 0.95,
    "ice": 0.2,
    "salts": 0.25,
    "periglacial": 0.15
   }
  },
  {
   "name": "Olympus Mons",
   "lat": 18.65,
   "lon": -133.8,
   "description": "The tallest volcano in the Solar System, with basaltic flows and aureole deposits.",
   "values": {
    "geology": 0.9,
    "topography": 1,
    "aeolian": 0.25,
    "caves": 0.6,
    "temperature": 0.82,
    "uv": 0.99,
    "aridity": 0.96,
    "ice": 0.1,
    "salts": 0.2,
    "periglacial": 0.08
   }
  },
  {
   "name": "Candor Chasma",
   "lat": -6.5,
   "lon": -71,
   "description": "Valles Marineris trough with thick layered sulfate deposits.",
   "values": {
    "geology": 0.92,
    "topography": 0.2,
    "aeolian": 0.45,
    "caves": 0.3,
    "temperature": 0.65,
    "uv": 0.85,
    "aridity": 0.9,
    "ice": 0.12,
    "salts": 0.62,
    "periglacial": 0.2
   }
  },
  {
   "name": "Mawrth Vallis",
   "lat": 22.6,
   "lon": -16.5,
   "description": "Some of the richest phyllosilicate (clay) layers on Mars.",
   "values": {
    "geology": 0.95,
    "topography": 0.5,
    "aeolian": 0.4,
    "caves": 0.05,
    "temperature": 0.68,
    "uv": 0.9,
    "aridity": 0.9,
    "ice": 0.15,
    "salts": 0.4,
    "periglacial": 0.1
   }
  },
  {
   "name": "Nili Fossae",
   "lat": 22,
   "lon": 75,
   "description": "Carbonate- and olivine-rich troughs near Syrtis Major.",
   "values": {
    "geology": 0.93,
    "topography": 0.55,
    "aeolian": 0.35,
    "caves": 0.1,
    "temperature": 0.7,
    "uv": 0.9,
    "aridity": 0.92,
    "ice": 0.2,
    "salts": 0.4,
    "periglacial": 0.15
   }
  },
  {
   "name": "Gusev Crater",
   "lat": -14.6,
   "lon": 175.4,
   "description": "Columbia Hills hydrothermal silica found by Spirit.",
   "values": {
    "geology": 0.86,
    "topography": 0.5,
    "aeolian": 0.55,
    "caves": 0.08,
    "temperature": 0.65,
    "uv": 0.92,
    "aridity": 0.94,
    "ice": 0.1,
    "salts": 0.48,
    "periglacial": 0.08
   }
  },
  {
   "name": "Arcadia Planitia",
   "lat": 47.2,
   "lon": -175.8,
   "description": "Shallow, near-surface ice sheets. A candidate site for crewed landings.",
   "values": {
    "geology": 0.48,
    "topography": 0.35,
    "aeolian": 0.3,
    "caves": 0.05,
    "temperature": 0.86,
    "uv": 0.75,
    "aridity": 0.82,
    "ice": 0.92,
    "salts": 0.5,
    "periglacial": 0.85
   }
  },
  {
   "name": "Phoenix landing site",
   "lat": 68.22,
   "lon": -125.7,
   "description": "Polygonal ground with excavated water ice and perchlorate salts.",
   "values": {
    "geology": 0.45,
    "topography": 0.32,
    "aeolian": 0.2,
    "caves": 0.02,
    "temperature": 0.95,
    "uv": 0.6,
    "aridity": 0.8,
    "ice": 0.98,
    "salts": 0.92,
    "periglacial": 0.98
   }
  },
  {
   "name": "Terra Sirenum chlorides",
   "lat": -32,
   "lon": -165,
   "description": "Ancient highlands with widespread chloride salt deposits.",
   "values": {
    "geology": 0.75,
    "topography": 0.7,
    "aeolian": 0.3,
    "caves": 0.05,
    "temperature": 0.75,
    "uv": 0.88,
    "aridity": 0.95,
    "ice": 0.3,
    "salts": 0.95,
    "periglacial": 0.4
   }
  },
  {
   "name": "Russell Crater megadune",
   "lat": -54.3,
   "lon": 12.9,
   "description": "A giant dune with seasonal frost-driven gullies.",
   "values": {
    "geology": 0.5,
    "topography": 0.55,
    "aeolian": 0.98,
    "caves": 0.02,
    "temperature": 0.88,
    "uv": 0.75,
    "aridity": 0.88,
    "ice": 0.6,
    "salts": 0.5,
    "periglacial": 0.88
   }
  },
  {
   "name": "Olympia Undae",
   "lat": 81,
   "lon": -170,
   "description": "Circumpolar gypsum-rich dune sea.",
   "values": {
    "geology": 0.8,
    "topography": 0.3,
    "aeolian": 0.99,
    "caves": 0.02,
    "temperature": 0.96,
    "uv": 0.55,
    "aridity": 0.85,
    "ice": 0.85,
    "salts": 0.65,
    "periglacial": 0.75
   }
  },
  {
   "name": "Syrtis Major",
   "lat": 8.4,
   "lon": 69.5,
   "description": "Dark basaltic volcanic plateau.",
   "values": {
    "geology": 0.92,
    "topography": 0.6,
    "aeolian": 0.5,
    "caves": 0.25,
    "temperature": 0.7,
    "uv": 0.92,
    "aridity": 0.93,
    "ice": 0.12,
    "salts": 0.3,
    "periglacial": 0.08
   }
  },
  {
   "name": "Planum Australe",
   "lat": -84,
   "lon": 160,
   "description": "South polar layered deposits with a CO₂ and water ice cap.",
   "values": {
    "geology": 0.3,
    "topography": 0.65,
    "aeolian": 0.4,
    "caves": 0.02,
    "temperature": 1,
    "uv": 0.5,
    "aridity": 0.75,
    "ice": 1,
    "salts": 0.55,
    "periglacial": 0.92
   }
  },
  {
   "name": "Elysium Mons",
   "lat": 25,
   "lon": 147,
   "description": "Volcanic province with young lava flows and collapse pits.",
   "values": {
    "geology": 0.88,
    "topography": 0.85,
    "aeolian": 0.25,
    "caves": 0.7,
    "temperature": 0.8,
    "uv": 0.95,
    "aridity": 0.94,
    "ice": 0.3,
    "salts": 0.25,
    "periglacial": 0.25
   }
  }
 ]
}*
���� 255d37336d9538eb623c93910f75266c