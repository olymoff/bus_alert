import asyncio
import logging
from datetime import datetime, timedelta
from typing import Dict, Any

from aiogram import Bot, Dispatcher, F, Router
from aiogram.filters import Command, CommandStart
from aiogram.fsm.context import FSMContext
from aiogram.fsm.state import State, StatesGroup
from aiogram.types import (
    Message,
    CallbackQuery,
    InlineKeyboardMarkup,
    InlineKeyboardButton,
    ReplyKeyboardMarkup,
    KeyboardButton,
)
from apscheduler.schedulers.asyncio import AsyncIOScheduler

from config import (
    BOT_TOKEN,
    PRESET_STOPS,
    WEEKDAYS_UZ,
    SAFETY_BUFFER_MIN,
)
from database import (
    init_db,
    get_user_settings,
    update_user_settings,
    add_schedule,
    get_user_schedules,
    get_active_schedules_for_weekday,
    delete_schedule,
    mark_notified,
)
from bus_tracker import fetch_bus_arrivals, find_nearest_preset_stop

logging.basicConfig(level=logging.INFO, format="%(asctime)s - %(levelname)s - %(message)s")
logger = logging.getLogger(__name__)

router = Router()


class ScheduleForm(StatesGroup):
    choosing_days = State()
    choosing_stop = State()
    choosing_buses = State()
    entering_time = State()


class SettingsForm(StatesGroup):
    entering_times = State()


def main_menu_kb() -> ReplyKeyboardMarkup:
    return ReplyKeyboardMarkup(
        keyboard=[
            [
                KeyboardButton(text="➕ Jadval qo'shish"),
                KeyboardButton(text="📅 Mening jadvalim"),
            ],
            [
                KeyboardButton(text="🚌 Hozirgi avtobuslar (Chustiy)"),
                KeyboardButton(text="⚙️ Vaqt sozlamalari"),
            ],
        ],
        resize_keyboard=True,
    )


def days_selection_kb(selected_days: list[int]) -> InlineKeyboardMarkup:
    buttons = []
    row = []
    for day_idx, day_name in WEEKDAYS_UZ.items():
        prefix = "✅ " if day_idx in selected_days else "⬜ "
        row.append(
            InlineKeyboardButton(
                text=f"{prefix}{day_name}",
                callback_data=f"toggle_day:{day_idx}",
            )
        )
        if len(row) == 2:
            buttons.append(row)
            row = []
    if row:
        buttons.append(row)

    buttons.append(
        [
            InlineKeyboardButton(
                text="⚡️ Dushanba–Juma (Ish kunlari)",
                callback_data="preset_days:mon_fri",
            ),
            InlineKeyboardButton(
                text="⚡️ Dushanba–Shanba (O'qish kunlari)",
                callback_data="preset_days:mon_sat",
            ),
        ]
    )
    buttons.append(
        [InlineKeyboardButton(text="➡️ Davom etish", callback_data="days_done")]
    )
    return InlineKeyboardMarkup(inline_keyboard=buttons)


def stop_selection_kb() -> InlineKeyboardMarkup:
    buttons = []
    for stop_key, stop_info in PRESET_STOPS.items():
        buttons.append(
            [
                InlineKeyboardButton(
                    text=f"🚏 {stop_info['name']}",
                    callback_data=f"select_stop:{stop_key}",
                )
            ]
        )
    return InlineKeyboardMarkup(inline_keyboard=buttons)


def bus_selection_kb(selected_buses: list[str]) -> InlineKeyboardMarkup:
    common_buses = ["11", "28", "40", "46", "53", "64", "76", "118"]
    buttons = []
    row = []
    for b in common_buses:
        prefix = "✅ " if b in selected_buses else "🚌 "
        row.append(
            InlineKeyboardButton(
                text=f"{prefix}{b}-avtobus",
                callback_data=f"toggle_bus:{b}",
            )
        )
        if len(row) == 2:
            buttons.append(row)
            row = []
    if row:
        buttons.append(row)

    buttons.append(
        [
            InlineKeyboardButton(
                text="⭐️ 11 va 28-avtobus (Tavsiya)",
                callback_data="preset_buses:11_28",
            )
        ]
    )
    buttons.append(
        [InlineKeyboardButton(text="➡️ Vaqtni belgilash", callback_data="buses_done")]
    )
    return InlineKeyboardMarkup(inline_keyboard=buttons)


@router.message(CommandStart())
async def cmd_start(message: Message):
    settings = get_user_settings(message.from_user.id)
    total_prep = settings["dressing_min"] + settings["walking_min"]
    text = (
        "👋 <b>Assalomu alaykum! Toshkent Avtobus Xabarnoma botiga xush kelibsiz!</b>\n\n"
        "Men sizga har kuni o'qishga ketish oldidan bekatingizga kelayotgan avtobusni kuzatib, "
        "o'z vaqtida uydan chiqishingiz uchun xabar beraman.\n\n"
        "📍 <b>Asosiy sozlangan bekat:</b> Shayxontohur tumani, <b>Nabixon Chustiy mahallasi</b>\n"
        "🚌 <b>Asosiy avtobuslar:</b> <b>11</b> va <b>28</b>\n\n"
        "⏱ <b>Sizning vaqt me'yorlaringiz:</b>\n"
        f"• Oldindan kuzatuvni boshlash: <b>{settings['advance_notice_min']} daqiqa qolganda</b>\n"
        f"• Kiyinishga ketadigan vaqt: <b>{settings['dressing_min']} daqiqa</b>\n"
        f"• Bekatgacha piyoda yurish: <b>{settings['walking_min']} daqiqa</b>\n"
        f"• Jami tayyorgarlik vaqti: <b>{total_prep} daqiqa (+{SAFETY_BUFFER_MIN} daq. zaxira)</b>\n\n"
        "Tezkor ravishda <b>Dushanba–Shanba (Nabixon Chustiy bekati, 11 va 28-avtobus)</b> jadvalini "
        "o'rnatish uchun /quick_chustiy buyrug'ini bosing yoki pastdagi menyudan foydalaning!"
    )
    await message.answer(text, parse_mode="HTML", reply_markup=main_menu_kb())


@router.message(Command("quick_chustiy"))
async def cmd_quick_chustiy(message: Message):
    """Nabixon Chustiy bekati (11 va 28 avtobus) uchun Dushanba-Shanba tezkor sozlash."""
    user_id = message.from_user.id
    stop_info = PRESET_STOPS["chustiy_chorsu"]
    for day_idx in range(6):  # Dushanba (0) - Shanba (5)
        add_schedule(
            user_id=user_id,
            weekday=day_idx,
            stop_id="chustiy_chorsu",
            stop_name=stop_info["name"],
            stop_lat=stop_info["lat"],
            stop_lon=stop_info["lon"],
            bus_numbers="11,28",
            target_time="08:00",
        )
    await message.answer(
        "✅ <b>Tezkor jadval muvaffaqiyatli yaratildi!</b>\n\n"
        "📅 <b>Kunlar:</b> Dushanba – Shanba\n"
        "🚏 <b>Bekat:</b> Nabixon Chustiy mahallasi (Shayxontohur)\n"
        "🚌 <b>Avtobuslar:</b> 11 va 28\n"
        "🕗 <b>Mo'ljallangan chiqish vaqti:</b> 08:00\n"
        "🔔 <b>1-xabarnoma (20 daqiqa oldin):</b> 07:40 da\n"
        "🚨 <b>Uydan chiqish xabari:</b> Avtobusga 15 daqiqa qolganda (5 daq. kiyinish + 8 daq. yo'l + 2 daq. zaxira)\n\n"
        "<i>Vaqtni o'zgartirish yoki boshqa kun qo'shish uchun «📅 Mening jadvalim» yoki «➕ Jadval qo'shish» tugmasini bosing.</i>",
        parse_mode="HTML",
    )


@router.message(F.text == "➕ Jadval qo'shish")
async def start_add_schedule(message: Message, state: FSMContext):
    await state.set_state(ScheduleForm.choosing_days)
    await state.update_data(selected_days=[], selected_buses=["11", "28"])
    await message.answer(
        "📅 <b>1-qadam: Haftaning qaysi kunlari uchun jadval qo'shmoqchisiz?</b>\n"
        "Kerakli kunlarni belgilang va «➡️ Davom etish» tugmasini bosing:",
        parse_mode="HTML",
        reply_markup=days_selection_kb([]),
    )


@router.callback_query(ScheduleForm.choosing_days, F.data.startswith("toggle_day:"))
async def toggle_day_cb(callback: CallbackQuery, state: FSMContext):
    day_idx = int(callback.data.split(":")[1])
    data = await state.get_data()
    selected = data.get("selected_days", [])
    if day_idx in selected:
        selected.remove(day_idx)
    else:
        selected.append(day_idx)
    await state.update_data(selected_days=selected)
    await callback.message.edit_reply_markup(reply_markup=days_selection_kb(selected))
    await callback.answer()


@router.callback_query(ScheduleForm.choosing_days, F.data.startswith("preset_days:"))
async def preset_days_cb(callback: CallbackQuery, state: FSMContext):
    mode = callback.data.split(":")[1]
    selected = [0, 1, 2, 3, 4] if mode == "mon_fri" else [0, 1, 2, 3, 4, 5]
    await state.update_data(selected_days=selected)
    await callback.message.edit_reply_markup(reply_markup=days_selection_kb(selected))
    await callback.answer("Kunlar tanlandi!")


@router.callback_query(ScheduleForm.choosing_days, F.data == "days_done")
async def days_done_cb(callback: CallbackQuery, state: FSMContext):
    data = await state.get_data()
    selected = data.get("selected_days", [])
    if not selected:
        await callback.answer("Iltimos, kamida bitta hafta kunini tanlang!", show_alert=True)
        return

    await state.set_state(ScheduleForm.choosing_stop)
    await callback.message.edit_text(
        "🚏 <b>2-qadam: Bekatni tanlang yoki xaritadan lokatsiya (📍 Location) yuboring:</b>\n\n"
        "Quyidagi Shayxontohur tumani bekatlaridan birini tanlashingiz yoki Telegramning "
        "📎 <b>Joylashuv (Location)</b> tugmasi orqali xaritadan istalgan bekatni belgilab yuborishingiz mumkin:",
        parse_mode="HTML",
        reply_markup=stop_selection_kb(),
    )
    await callback.answer()


@router.callback_query(ScheduleForm.choosing_stop, F.data.startswith("select_stop:"))
async def select_stop_cb(callback: CallbackQuery, state: FSMContext):
    stop_key = callback.data.split(":")[1]
    stop_info = PRESET_STOPS[stop_key]
    await state.update_data(
        stop_id=stop_key,
        stop_name=stop_info["name"],
        stop_lat=stop_info["lat"],
        stop_lon=stop_info["lon"],
    )
    data = await state.get_data()
    selected_buses = data.get("selected_buses", ["11", "28"])
    await state.set_state(ScheduleForm.choosing_buses)
    await callback.message.edit_text(
        f"✅ <b>Tanlangan bekat:</b> {stop_info['name']}\n\n"
        "🚌 <b>3-qadam: Qaysi avtobuslarni kuzatamiz?</b>\n"
        "(Standart holatda 11 va 28-avtobuslar belgilangan. Yana qo'shishingiz yoki yozib yuborishingiz mumkin):",
        parse_mode="HTML",
        reply_markup=bus_selection_kb(selected_buses),
    )
    await callback.answer()


@router.message(ScheduleForm.choosing_stop, F.location)
async def location_stop_handler(message: Message, state: FSMContext):
    lat = message.location.latitude
    lon = message.location.longitude
    nearest = find_nearest_preset_stop(lat, lon)

    if nearest and nearest["distance_km"] <= 1.2:
        stop_id = nearest["stop_id"]
        stop_name = f"{nearest['name']} ({nearest['distance_km']} km)"
    else:
        stop_id = "custom_map_stop"
        stop_name = f"Xaritadan belgilangan bekat ({lat:.4f}, {lon:.4f})"

    await state.update_data(
        stop_id=stop_id,
        stop_name=stop_name,
        stop_lat=lat,
        stop_lon=lon,
    )
    data = await state.get_data()
    selected_buses = data.get("selected_buses", ["11", "28"])
    await state.set_state(ScheduleForm.choosing_buses)
    await message.answer(
        f"📍 <b>Xaritadan bekat qabul qilindi:</b>\n{stop_name}\n\n"
        "🚌 <b>3-qadam: Shu bekatga keluvchi avtobuslarni tanlang:</b>",
        parse_mode="HTML",
        reply_markup=bus_selection_kb(selected_buses),
    )


@router.callback_query(ScheduleForm.choosing_buses, F.data.startswith("toggle_bus:"))
async def toggle_bus_cb(callback: CallbackQuery, state: FSMContext):
    bus_num = callback.data.split(":")[1]
    data = await state.get_data()
    selected = data.get("selected_buses", [])
    if bus_num in selected:
        selected.remove(bus_num)
    else:
        selected.append(bus_num)
    await state.update_data(selected_buses=selected)
    await callback.message.edit_reply_markup(reply_markup=bus_selection_kb(selected))
    await callback.answer()


@router.callback_query(ScheduleForm.choosing_buses, F.data == "preset_buses:11_28")
async def preset_buses_cb(callback: CallbackQuery, state: FSMContext):
    selected = ["11", "28"]
    await state.update_data(selected_buses=selected)
    await callback.message.edit_reply_markup(reply_markup=bus_selection_kb(selected))
    await callback.answer("11 va 28-avtobuslar tanlandi!")


@router.callback_query(ScheduleForm.choosing_buses, F.data == "buses_done")
async def buses_done_cb(callback: CallbackQuery, state: FSMContext):
    data = await state.get_data()
    selected = data.get("selected_buses", [])
    if not selected:
        await callback.answer("Iltimos, kamida bitta avtobus raqamini tanlang!", show_alert=True)
        return

    await state.set_state(ScheduleForm.entering_time)
    await callback.message.edit_text(
        "🕗 <b>4-qadam: Bekatdan avtobusga chiqish vaqtingizni kiriting (SS:DD formatida):</b>\n\n"
        "Masalan: <code>08:00</code> yoki <code>07:50</code>\n\n"
        "<i>Bot siz kiritgan vaqtdan 20 daqiqa oldin (masalan, 07:40 da) sizga birinchi bildirishnomani "
        "yuboradi va avtobus bekatga 13–15 daqiqa (5 daqiqa kiyinish + 8 daqiqa bekatgacha yo'l) "
        "qolganda uydan chiqish haqida ogohlantiradi!</i>",
        parse_mode="HTML",
    )
    await callback.answer()


@router.message(ScheduleForm.entering_time)
async def save_schedule_time(message: Message, state: FSMContext):
    time_text = message.text.strip()
    try:
        parsed_time = datetime.strptime(time_text, "%H:%M")
        formatted_time = parsed_time.strftime("%H:%M")
    except ValueError:
        await message.answer(
            "⚠️ Vaqt noto'g'ri formatda kiritildi. Iltimos, <code>08:00</code> yoki <code>07:45</code> ko'rinishida yozing:",
            parse_mode="HTML",
        )
        return

    data = await state.get_data()
    selected_days = sorted(data["selected_days"])
    bus_str = ",".join(data["selected_buses"])

    for day_idx in selected_days:
        add_schedule(
            user_id=message.from_user.id,
            weekday=day_idx,
            stop_id=data["stop_id"],
            stop_name=data["stop_name"],
            stop_lat=data["stop_lat"],
            stop_lon=data["stop_lon"],
            bus_numbers=bus_str,
            target_time=formatted_time,
        )

    settings = get_user_settings(message.from_user.id)
    notice_dt = parsed_time - timedelta(minutes=settings["advance_notice_min"])
    prep_min = settings["dressing_min"] + settings["walking_min"] + SAFETY_BUFFER_MIN
    days_names = ", ".join(WEEKDAYS_UZ[d] for d in selected_days)

    await state.clear()
    await message.answer(
        "🎉 <b>Jadval muvaffaqiyatli saqlandi!</b>\n\n"
        f"📅 <b>Kunlar:</b> {days_names}\n"
        f"🚏 <b>Bekat:</b> {data['stop_name']}\n"
        f"🚌 <b>Avtobuslar:</b> {bus_str}-avtobus\n"
        f"🕗 <b>Bekatda bo'lish vaqti:</b> {formatted_time}\n"
        f"🔔 <b>Kuzatuv boshlanishi ({settings['advance_notice_min']} daq. oldin):</b> {notice_dt.strftime('%H:%M')} da\n"
        f"🏃‍♂️ <b>Kiyinish va yo'lga chiqish signali:</b> Avtobusga {prep_min} daqiqa qolganda "
        f"({settings['dressing_min']} daq. kiyinish + {settings['walking_min']} daq. yo'l + {SAFETY_BUFFER_MIN} daq. zaxira)",
        parse_mode="HTML",
        reply_markup=main_menu_kb(),
    )


@router.message(F.text == "📅 Mening jadvalim")
async def show_my_schedules(message: Message):
    schedules = get_user_schedules(message.from_user.id)
    if not schedules:
        await message.answer(
            "📭 Sizda hozircha saqlangan jadvallar yo'q.\n"
            "Tezkor o'rnatish uchun /quick_chustiy ni bosing yoki «➕ Jadval qo'shish» tugmasidan foydalaning."
        )
        return

    settings = get_user_settings(message.from_user.id)
    lines = ["📅 <b>Sizning haftalik avtobus jadvallaringiz:</b>\n"]
    buttons = []

    for item in schedules:
        day_name = WEEKDAYS_UZ.get(item["weekday"], "Noma'lum")
        t_dt = datetime.strptime(item["target_time"], "%H:%M")
        start_mon = (t_dt - timedelta(minutes=settings["advance_notice_min"])).strftime("%H:%M")
        lines.append(
            f"🔹 <b>{day_name} — soat {item['target_time']}</b> (xabar: {start_mon} dan)\n"
            f"   🚏 {item['stop_name']}\n"
            f"   🚌 Avtobuslar: <b>{item['bus_numbers']}</b>\n"
        )
        buttons.append(
            [
                InlineKeyboardButton(
                    text=f"🗑 O'chirish: {day_name} ({item['target_time']}) - {item['bus_numbers']}",
                    callback_data=f"del_sched:{item['id']}",
                )
            ]
        )

    await message.answer(
        "\n".join(lines),
        parse_mode="HTML",
        reply_markup=InlineKeyboardMarkup(inline_keyboard=buttons),
    )


@router.callback_query(F.data.startswith("del_sched:"))
async def delete_schedule_cb(callback: CallbackQuery):
    sched_id = int(callback.data.split(":")[1])
    deleted = delete_schedule(sched_id, callback.from_user.id)
    if deleted:
        await callback.answer("Jadval o'chirildi!")
        await callback.message.delete()
    else:
        await callback.answer("Topilmadi", show_alert=True)


@router.message(F.text == "🚌 Hozirgi avtobuslar (Chustiy)")
async def check_live_chustiy(message: Message):
    stop_info = PRESET_STOPS["chustiy_chorsu"]
    arrivals = await fetch_bus_arrivals(
        stop_id="chustiy_chorsu",
        stop_lat=stop_info["lat"],
        stop_lon=stop_info["lon"],
        bus_numbers=["11", "28"],
    )
    settings = get_user_settings(message.from_user.id)
    prep_needed = settings["dressing_min"] + settings["walking_min"]

    lines = [
        f"🚏 <b>{stop_info['name']}</b>\n"
        f"🕒 Joriy vaqt: <b>{datetime.now().strftime('%H:%M')}</b>\n"
    ]
    for arr in arrivals:
        eta = arr["eta_min"]
        status = (
            "🚨 <b>Hozir kiyinib chiqsangiz ulgurasiz!</b>"
            if prep_needed <= eta <= prep_needed + 4
            else (
                "⚡️ <b>Avtobus juda yaqin (ulgurish qiyin, keyingisini kuting)</b>"
                if eta < prep_needed
                else "☕️ <b>Hali vaqt bor, tayyorlanib turing</b>"
            )
        )
        lines.append(
            f"🚌 <b>{arr['bus_number']}-avtobus:</b> <b>{eta} daqiqada</b> keladi "
            f"(~{arr['distance_km']} km / {arr['stops_away']} bekat uzoqlikda)\n"
            f"   └ {status}\n"
        )

    lines.append(
        f"\n💡 <i>Hisob-kitob: {settings['dressing_min']} daqiqa kiyinish + "
        f"{settings['walking_min']} daqiqa bekatgacha yo'l = {prep_needed} daqiqa.</i>\n"
        f"🔗 <a href='{stop_info['yandex_url']}'>Yandex Xaritada jonli ko'rish</a>"
    )
    await message.answer("\n".join(lines), parse_mode="HTML", disable_web_page_preview=True)


@router.message(F.text == "⚙️ Vaqt sozlamalari")
async def show_time_settings(message: Message, state: FSMContext):
    settings = get_user_settings(message.from_user.id)
    await state.set_state(SettingsForm.entering_times)
    await message.answer(
        "⚙️ <b>Sizning joriy vaqt sozlamalaringiz:</b>\n\n"
        f"1️⃣ Kiyinish vaqti: <b>{settings['dressing_min']} daqiqa</b>\n"
        f"2️⃣ Bekatgacha piyoda yurish: <b>{settings['walking_min']} daqiqa</b>\n"
        f"3️⃣ Belgilangan vaqtdan necha daqiqa oldin xabar berish: <b>{settings['advance_notice_min']} daqiqa</b>\n\n"
        "O'zgartirish uchun uchta sonni probel bilan yozib yuboring (masalan: <code>5 8 20</code>) "
        "yoki bekor qilish uchun /cancel bosing:",
        parse_mode="HTML",
    )


@router.message(Command("cancel"))
async def cancel_state(message: Message, state: FSMContext):
    await state.clear()
    await message.answer("Amal bekor qilindi.", reply_markup=main_menu_kb())


@router.message(SettingsForm.entering_times)
async def update_times_handler(message: Message, state: FSMContext):
    parts = message.text.strip().split()
    if len(parts) != 3 or not all(p.isdigit() for p in parts):
        await message.answer(
            "⚠️ Iltimos, 3 ta musbat sonni bo'sh joy bilan kiriting. Masalan: <code>5 8 20</code>",
            parse_mode="HTML",
        )
        return
    dressing, walking, advance = map(int, parts)
    update_user_settings(message.from_user.id, dressing, walking, advance)
    await state.clear()
    await message.answer(
        f"✅ <b>Sozlamalar yangilandi!</b>\n"
        f"• Kiyinish: <b>{dressing} daq.</b>\n"
        f"• Bekatgacha yo'l: <b>{walking} daq.</b>\n"
        f"• Oldindan bildirishnoma: <b>{advance} daq. qolganda</b>",
        parse_mode="HTML",
        reply_markup=main_menu_kb(),
    )


async def monitor_schedules_job(bot: Bot):
    """
    Har 30 soniyada ishga tushib, foydalanuvchilar belgilagan vaqtni tekshiradi:
    1. Belgilangan vaqtga 20 daqiqa qolganda (masalan 08:00 bo'lsa, 07:40 da) 1-xabarnomani yuboradi.
    2. Shu 20 daqiqalik oraliqda avtobus bekatga (5 daq kiyinish + 8 daq yo'l + 2 daq bufer = 13-15 daqiqa)
       qolganda "Hozir kiyinishni boshlang va uydan chiqing!" xabarini yuboradi.
    """
    now = datetime.now()
    today_weekday = now.weekday()
    today_str = now.strftime("%Y-%m-%d")

    active_schedules = get_active_schedules_for_weekday(today_weekday)
    for sched in active_schedules:
        user_id = sched["user_id"]
        settings = get_user_settings(user_id)

        target_dt = datetime.strptime(
            f"{today_str} {sched['target_time']}", "%Y-%m-%d %H:%M"
        )
        minutes_until_target = (target_dt - now).total_seconds() / 60.0

        advance_min = settings["advance_notice_min"]  # 20 daqiqa
        prep_min = settings["dressing_min"] + settings["walking_min"]  # 5 + 8 = 13 daqiqa
        ideal_bus_eta_max = prep_min + SAFETY_BUFFER_MIN + 1  # 16 daqiqa

        # Faqat belgilangan vaqtga 20 daqiqa qolgandan to vaqt kelgungacha tekshiramiz
        if 0 <= minutes_until_target <= advance_min:
            bus_list = [b.strip() for b in sched["bus_numbers"].split(",") if b.strip()]
            arrivals = await fetch_bus_arrivals(
                stop_id=sched["stop_id"],
                stop_lat=sched["stop_lat"],
                stop_lon=sched["stop_lon"],
                bus_numbers=bus_list,
            )

            # 1-bosqich: Belgilangan vaqtga 20 daqiqa qolganda dastlabki bildirishnoma
            if sched["last_Window_notified_date"] != today_str:
                arr_summary = "\n".join(
                    f"• <b>{a['bus_number']}-avtobus:</b> {a['eta_min']} daqiqada (~{a['distance_km']} km)"
                    for a in arrivals
                )
                msg = (
                    f"🔔 <b>20 DAQIQA QOLDI! Avtobus kuzatuvi boshlandi</b>\n\n"
                    f"🚏 <b>Bekat:</b> {sched['stop_name']}\n"
                    f"🕗 <b>Rejadagi vaqt:</b> {sched['target_time']}\n\n"
                    f"📡 <b>Hozirgi avtobuslar holati:</b>\n{arr_summary}\n\n"
                    f"⏳ <i>Avtobus bekatga {prep_min}–{prep_min + SAFETY_BUFFER_MIN} daqiqalik masofaga "
                    f"kelishi bilan kiyinish haqida signal beraman!</i>"
                )
                try:
                    await bot.send_message(user_id, msg, parse_mode="HTML")
                    mark_notified(sched["id"], "window", today_str)
                except Exception as e:
                    logger.error(f"Xabar yuborishda xatolik: {e}")

            # 2-bosqich: Avtobus bekatga 13-16 daqiqa qolganda "Kiyinishni boshlang!" signali
            if sched["last_leave_notified_date"] != today_str:
                matching_buses = [
                    a for a in arrivals if prep_min <= a["eta_min"] <= ideal_bus_eta_max
                ]
                if matching_buses:
                    best_bus = matching_buses[0]
                    leave_home_time = (
                        now + timedelta(minutes=settings["dressing_min"])
                    ).strftime("%H:%M")
                    msg = (
                        f"🚨 <b>KIYINISHNI BOSHLANG! {best_bus['bus_number']}-AVTOBUS YAQINLASHMOQDA!</b>\n\n"
                        f"🚏 <b>Bekat:</b> {sched['stop_name']}\n"
                        f"🚌 <b>{best_bus['bus_number']}-avtobus:</b> bekatga <b>{best_bus['eta_min']} daqiqada</b> yetib keladi "
                        f"(~{best_bus['distance_km']} km / {best_bus['stops_away']} bekat uzoqlikda).\n\n"
                        f"⏱ <b>Aniq vaqt rejasi:</b>\n"
                        f"• 👕 Kiyinish uchun: <b>{settings['dressing_min']} daqiqa</b> (soat {leave_home_time} gacha)\n"
                        f"• 🚶‍♂️ Bekatgacha borish: <b>{settings['walking_min']} daqiqa</b>\n"
                        f"• ✅ Bekatda bo'lasiz: avtobus kelishidan <b>{best_bus['eta_min'] - prep_min} daqiqa oldin!</b>"
                    )
                    try:
                        await bot.send_message(user_id, msg, parse_mode="HTML")
                        mark_notified(sched["id"], "leave", today_str)
                    except Exception as e:
                        logger.error(f"Chiqish xabarini yuborishda xatolik: {e}")


async def main():
    init_db()
    if BOT_TOKEN == "YOUR_TELEGRAM_BOT_TOKEN_HERE" or not BOT_TOKEN:
        logger.warning(
            "DIQQAT: BOT_TOKEN o'rnatilmagan! .env fayliga Telegram BotFather dan olingan tokenni kiriting."
        )
        return

    bot = Bot(token=BOT_TOKEN)
    dp = Dispatcher()
    dp.include_router(router)

    scheduler = AsyncIOScheduler()
    scheduler.add_job(monitor_schedules_job, "interval", seconds=30, args=[bot])
    scheduler.start()

    logger.info("TashBus Alert Bot ishga tushdi...")
    await dp.start_polling(bot)


if __name__ == "__main__":
    asyncio.run(main())
