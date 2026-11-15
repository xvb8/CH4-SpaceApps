"""Shared location helpers: longitude normalization and great-circle distance."""

import math

PLANET_RADIUS_KM = {"mars": 3389.5, "earth": 6371.0}

# Default location of the extracted real data (see data/real/README.md).
import os
DATA_ROOT = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "data", "real")


def lon_360(lon):
    """Longitude in [0, 360) east."""
    return lon % 360.0


def lon_180(lon):
    """Longitude in [-180, 180)."""
    return (lon + 180.0) % 360.0 - 180.0


def distance_km(lat1, lon1, lat2, lon2, planet="mars"):
    """Great-circle (haversine) distance in km. Longitude convention does not matter."""
    r = PLANET_RADIUS_KM[planet]
    p1, p2 = math.radians(lat1), math.radians(lat2)
    dp = p2 - p1
    dl = math.radians(lon_180(lon2 - lon1))
    a = math.sin(dp / 2) ** 2 + math.cos(p1) * math.cos(p2) * math.sin(dl / 2) ** 2
    return 2 * r * math.asin(min(1.0, math.sqrt(a)))


def bbox_deg(lat, lon, radius_km, planet="mars"):
    """Loose lat/lon box around a point (for fast pre-filtering before exact distance)."""
    r = PLANET_RADIUS_KM[planet]
    dlat = math.degrees(radius_km / r)
    coslat = max(math.cos(math.radians(lat)), 1e-6)
    dlon = 180.0 if abs(lat) + dlat >= 90 else min(180.0, dlat / coslat)
    return max(-90.0, lat - dlat), min(90.0, lat + dlat), dlon


def within(lat, lon, plat, plon, radius_km, box, planet="mars"):
    """True if point (plat, plon) lies within radius_km of (lat, lon)."""
    lo, hi, dlon = box
    if not lo <= plat <= hi:
        return False
    if abs(lon_180(plon - lon)) > dlon:
        return False
    return distance_km(lat, lon, plat, plon, planet) <= radius_km
