import os
from dotenv import load_dotenv

load_dotenv()

# Telegram Bot Token (@BotFather dan olinadi)
BOT_TOKEN = os.getenv("BOT_TOKEN", "YOUR_TELEGRAM_BOT_TOKEN_HERE")

# Standart vaqt sozlamalari (daqiqalarda)
DEFAULT_DRESSING_MIN = int(os.getenv("DEFAULT_DRESSING_MIN", "5"))   # Kiyinish uchun: 5 daqiqa
DEFAULT_WALKING_MIN = int(os.getenv("DEFAULT_WALKING_MIN", "8"))     # Bekatgacha borish: 8 daqiqa
DEFAULT_ADVANCE_MIN = int(os.getenv("DEFAULT_ADVANCE_MIN", "20"))    # Belgilangan vaqtdan necha daqiqa oldin kuzatishni boshlash: 20 daqiqa
SAFETY_BUFFER_MIN = int(os.getenv("SAFETY_BUFFER_MIN", "2"))         # Ehtiyot zaxira vaqti: 2 daqiqa

# Toshkent shahri Shayxontohur tumani mashhur bekatlari (standart holatda Nabixon Chustiy mahallasi birinchi turadi)
PRESET_STOPS = {
    "chustiy_chorsu": {
        "name": "Nabixon Chustiy mahallasi (Chorsu / Markaz yo'nalishi)",
        "lat": 41.332850,
        "lon": 69.218420,
        "yandex_stop_id": "1719128660",
        "easyway_stop_id": "638",
        "routes": ["11", "28"],
        "yandex_url": "https://yandex.uz/maps/10335/tashkent/stops/1719128660/"
    },
    "chustiy_beruniy": {
        "name": "Nabixon Chustiy mahallasi (Beruniy / Ibn-Sino yo'nalishi)",
        "lat": 41.333120,
        "lon": 69.218150,
        "yandex_stop_id": "1719128770",
        "easyway_stop_id": "639",
        "routes": ["11", "28"],
        "yandex_url": "https://yandex.com/maps/10335/tashkent/stops/1719128770/"
    },
    "maktab_41": {
        "name": "41-Maktab bekati (Shayxontohur)",
        "lat": 41.330410,
        "lon": 69.224890,
        "yandex_stop_id": "1719128658",
        "easyway_stop_id": "636",
        "routes": ["11", "28"],
        "yandex_url": "https://yandex.uz/maps/10335/tashkent/transport/"
    },
    "tinchlik_metro": {
        "name": "Tinchlik metrosi bekati",
        "lat": 41.335200,
        "lon": 69.214500,
        "yandex_stop_id": "1719128662",
        "easyway_stop_id": "640",
        "routes": ["11", "28"],
        "yandex_url": "https://yandex.uz/maps/10335/tashkent/transport/"
    }
}

WEEKDAYS_UZ = {
    0: "Dushanba",
    1: "Seshanba",
    2: "Chorshanba",
    3: "Payshanba",
    4: "Juma",
    5: "Shanba",
    6: "Yakshanba"
}
