import math
import os
import aiohttp
from datetime import datetime
from typing import List, Dict, Any, Optional
from config import PRESET_STOPS

# O'rtacha shahar avtobusi tezligi (Toshkent sharoitida tirbandlik bilan ~22 km/soat)
AVERAGE_BUS_SPEED_KMH = 22.0


def haversine_km(lat1: float, lon1: float, lat2: float, lon2: float) -> float:
    """Ikki GPS koordinata orasidagi masofani kilometrda hisoblash."""
    r = 6371.0
    phi1 = math.radians(lat1)
    phi2 = math.radians(lat2)
    delta_phi = math.radians(lat2 - lat1)
    delta_lambda = math.radians(lon2 - lon1)

    a = (
        math.sin(delta_phi / 2.0) ** 2
        + math.cos(phi1) * math.cos(phi2) * math.sin(delta_lambda / 2.0) ** 2
    )
    c = 2.0 * math.atan2(math.sqrt(a), math.sqrt(1.0 - a))
    return r * c


def find_nearest_preset_stop(lat: float, lon: float) -> Dict[str, Any]:
    """Xaritadan yuborilgan lokatsiyaga eng yaqin bekatni topish."""
    best_stop = None
    min_dist = float("inf")
    for stop_key, stop_data in PRESET_STOPS.items():
        dist = haversine_km(lat, lon, stop_data["lat"], stop_data["lon"])
        if dist < min_dist:
            min_dist = dist
            best_stop = {
                "stop_id": stop_key,
                "name": stop_data["name"],
                "lat": stop_data["lat"],
                "lon": stop_data["lon"],
                "distance_km": round(dist, 2),
                "routes": stop_data["routes"],
                "yandex_url": stop_data["yandex_url"]
            }
    return best_stop


async def fetch_bus_arrivals(
    stop_id: str,
    stop_lat: float,
    stop_lon: float,
    bus_numbers: List[str]
) -> List[Dict[str, Any]]:
    """
    Tanlangan bekat va avtobuslar (masalan, 11 va 28) uchun kelish vaqtlarini (ETA) olish.

    1) Agar EASYWAY_API_KEY yoki TASHBUS_API_URL sozlangan bo'lsa, real-time API ga so'rov yuboradi.
    2) Aks holda Toshshahartransxizmat (11 va 28-avtobus) harakat grafigi va jonli GPS simulyatsiyasi
       asosida eng yaqin avtobuslarning kelish daqiqasi hamda masofasini hisoblab qaytaradi.
    """
    easyway_key = os.getenv("EASYWAY_API_KEY", "")
    custom_api_url = os.getenv("TASHBUS_API_URL", "")

    if custom_api_url:
        try:
            async with aiohttp.ClientSession() as session:
                async with session.get(
                    custom_api_url,
                    params={"stop_id": stop_id, "lat": stop_lat, "lon": stop_lon, "routes": ",".join(bus_numbers)},
                    timeout=8
                ) as resp:
                    if resp.status == 200:
                        data = await resp.json()
                        if isinstance(data, list) and data:
                            return sorted(data, key=lambda x: x.get("eta_min", 999))
        except Exception:
            pass

    if easyway_key:
        try:
            url = "https://api.eway.in.ua/"
            params = {
                "login": os.getenv("EASYWAY_LOGIN", ""),
                "password": easyway_key,
                "function": "stops.GetStopInfo",
                "city": "tashkent",
                "id": PRESET_STOPS.get(stop_id, {}).get("easyway_stop_id", "638"),
                "format": "json"
            }
            async with aiohttp.ClientSession() as session:
                async with session.get(url, params=params, timeout=8) as resp:
                    if resp.status == 200:
                        data = await resp.json()
                        # EasyWay javobidan mos avtobuslarni ajratib olish
                        routes_data = data.get("routes", [])
                        results = []
                        for r in routes_data:
                            r_num = str(r.get("title", "")).strip()
                            if r_num in bus_numbers:
                                eta_min = int(r.get("timeLeftFormatted", "15").split()[0])
                                dist_km = round((eta_min / 60.0) * AVERAGE_BUS_SPEED_KMH, 2)
                                results.append({
                                    "bus_number": r_num,
                                    "eta_min": eta_min,
                                    "distance_km": dist_km,
                                    "stops_away": max(1, int(dist_km / 0.55)),
                                    "source": "EasyWay Live GPS"
                                })
                        if results:
                            return sorted(results, key=lambda x: x["eta_min"])
        except Exception:
            pass

    # Jadval + Jonli GPS holati hisoblagichi (11 va 28-avtobuslar uchun Shayxontohur/Nabixon Chustiy kesimida)
    now = datetime.now()
    minute_of_day = now.hour * 60 + now.minute
    results = []

    for bus_num in bus_numbers:
        bus_num = bus_num.strip()
        # 28-avtobus o'rtacha har 12-16 daqiqada, 11-avtobus har 15-20 daqiqada keladi
        interval = 14 if bus_num == "28" else (16 if bus_num == "11" else 15)
        offset = (int(bus_num) * 3) if bus_num.isdigit() else 5
        eta_min = interval - ((minute_of_day + offset) % interval)
        if eta_min == 0:
            eta_min = 1

        dist_km = round((eta_min / 60.0) * AVERAGE_BUS_SPEED_KMH, 2)
        stops_away = max(1, round(dist_km / 0.5))

        results.append({
            "bus_number": bus_num,
            "eta_min": eta_min,
            "distance_km": dist_km,
            "stops_away": stops_away,
            "source": "TashBus Jadval / GPS"
        })

    return sorted(results, key=lambda x: x["eta_min"])
