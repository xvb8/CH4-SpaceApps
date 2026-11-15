**Criteria for similarities:**

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

## **Accessing Earthdata datasets**

Use this pattern for every NASA Earthdata link (EMIT, ASTER-GED AG100, MLS ML2T, MODIS, GPM, and others). A free Earthdata Login is required.

1. Look up each collection's short name and version in CMR.
2. Search for granules by bounding box and date range with `earthaccess`.
3. Download the granules and open them with `xarray`.

```python
import requests

# 1. Find the collection versions and IDs
for sn in ["EMITL2BMIN", "AG100"]:
    r = requests.get(
        "https://cmr.earthdata.nasa.gov/search/collections.json",
        params={"short_name": sn},
    ).json()
    for c in r["feed"]["entry"]:
        print(sn, c["version_id"], c["id"], c["title"])

# 2. Search granules
# pip install earthaccess
import earthaccess

earthaccess.login()  # Earthdata Login; saves credentials to ~/.netrc

# Example region near Cuprite, Nevada: (west, south, east, north)
bbox = (-117.3, 36.8, -117.0, 37.1)

# EMIT L2B: mineral ID and band depth (60 m, raw geometry)
emit = earthaccess.search_data(
    short_name="EMITL2BMIN",
    version="002",
    bounding_box=bbox,
    temporal=("2023-01-01", "2024-12-31"),
    count=50,
)
print("EMIT granules:", len(emit))

# ASTER-GED AG100: 100 m emissivity tiles (static 2000-2008 composite)
ag100 = earthaccess.search_data(
    short_name="AG100",
    version="003",
    bounding_box=bbox,
)
print("AG100 granules:", len(ag100))

# 3. Download and open
emit_files = earthaccess.download(emit, "./emit_l2b")
ag_files = earthaccess.download(ag100, "./ag100")

import xarray as xr

ds = xr.open_dataset(emit_files[0])
mineral_id = ds["group_1_mineral_id"]
band_depth = ds["group_1_band_depth"]
```

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

