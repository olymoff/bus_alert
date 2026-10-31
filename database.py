import sqlite3
from typing import List, Dict, Any, Optional
from config import DEFAULT_DRESSING_MIN, DEFAULT_WALKING_MIN, DEFAULT_ADVANCE_MIN

DB_PATH = "bus_schedules.db"


def init_db() -> None:
    """Ma'lumotlar bazasini va jadvallarni yaratish."""
    with sqlite3.connect(DB_PATH) as conn:
        cursor = conn.cursor()
        cursor.execute("""
            CREATE TABLE IF NOT EXISTS user_settings (
                user_id INTEGER PRIMARY KEY,
                dressing_min INTEGER DEFAULT 5,
                walking_min INTEGER DEFAULT 8,
                advance_notice_min INTEGER DEFAULT 20
            )
        """)
        cursor.execute("""
            CREATE TABLE IF NOT EXISTS schedules (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                user_id INTEGER NOT NULL,
                weekday INTEGER NOT NULL,
                stop_id TEXT NOT NULL,
                stop_name TEXT NOT NULL,
                stop_lat REAL NOT NULL,
                stop_lon REAL NOT NULL,
                bus_numbers TEXT NOT NULL,
                target_time TEXT NOT NULL,
                is_active INTEGER DEFAULT 1,
                last_Window_notified_date TEXT DEFAULT '',
                last_leave_notified_date TEXT DEFAULT ''
            )
        """)
        conn.commit()


def get_user_settings(user_id: int) -> Dict[str, int]:
    """Foydalanuvchining vaqt sozlamalarini olish."""
    with sqlite3.connect(DB_PATH) as conn:
        cursor = conn.cursor()
        cursor.execute(
            "SELECT dressing_min, walking_min, advance_notice_min FROM user_settings WHERE user_id = ?",
            (user_id,)
        )
        row = cursor.fetchone()
        if not row:
            cursor.execute(
                "INSERT INTO user_settings (user_id, dressing_min, walking_min, advance_notice_min) VALUES (?, ?, ?, ?)",
                (user_id, DEFAULT_DRESSING_MIN, DEFAULT_WALKING_MIN, DEFAULT_ADVANCE_MIN)
            )
            conn.commit()
            return {
                "dressing_min": DEFAULT_DRESSING_MIN,
                "walking_min": DEFAULT_WALKING_MIN,
                "advance_notice_min": DEFAULT_ADVANCE_MIN
            }
        return {
            "dressing_min": row[0],
            "walking_min": row[1],
            "advance_notice_min": row[2]
        }


def update_user_settings(user_id: int, dressing_min: int, walking_min: int, advance_notice_min: int) -> None:
    """Foydalanuvchining kiyinish, yurish va oldindan xabar olish vaqtlarini yangilash."""
    get_user_settings(user_id)
    with sqlite3.connect(DB_PATH) as conn:
        cursor = conn.cursor()
        cursor.execute(
            """
            UPDATE user_settings
            SET dressing_min = ?, walking_min = ?, advance_notice_min = ?
            WHERE user_id = ?
            """,
            (dressing_min, walking_min, advance_notice_min, user_id)
        )
        conn.commit()


def add_schedule(
    user_id: int,
    weekday: int,
    stop_id: str,
    stop_name: str,
    stop_lat: float,
    stop_lon: float,
    bus_numbers: str,
    target_time: str
) -> int:
    """Yangi kunlik jadval qo'shish."""
    with sqlite3.connect(DB_PATH) as conn:
        cursor = conn.cursor()
        cursor.execute(
            """
            INSERT INTO schedules (user_id, weekday, stop_id, stop_name, stop_lat, stop_lon, bus_numbers, target_time)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?)
            """,
            (user_id, weekday, stop_id, stop_name, stop_lat, stop_lon, bus_numbers, target_time)
        )
        conn.commit()
        return cursor.lastrowid


def get_user_schedules(user_id: int) -> List[Dict[str, Any]]:
    """Foydalanuvchining barcha jadvallarini olish."""
    with sqlite3.connect(DB_PATH) as conn:
        conn.row_factory = sqlite3.Row
        cursor = conn.cursor()
        cursor.execute(
            "SELECT * FROM schedules WHERE user_id = ? AND is_active = 1 ORDER BY weekday ASC, target_time ASC",
            (user_id,)
        )
        return [dict(row) for row in cursor.fetchall()]


def get_active_schedules_for_weekday(weekday: int) -> List[Dict[str, Any]]:
    """Berilgan hafta kunidagi barcha faol jadvallarni olish."""
    with sqlite3.connect(DB_PATH) as conn:
        conn.row_factory = sqlite3.Row
        cursor = conn.cursor()
        cursor.execute(
            "SELECT * FROM schedules WHERE weekday = ? AND is_active = 1",
            (weekday,)
        )
        return [dict(row) for row in cursor.fetchall()]


def delete_schedule(schedule_id: int, user_id: int) -> bool:
    """Jadvalni o'chirish."""
    with sqlite3.connect(DB_PATH) as conn:
        cursor = conn.cursor()
        cursor.execute(
            "DELETE FROM schedules WHERE id = ? AND user_id = ?",
            (schedule_id, user_id)
        )
        conn.commit()
        return cursor.rowcount > 0


def mark_notified(schedule_id: int, stage: str, date_str: str) -> None:
    """Kunlik xabar yuborilganligini belgilash ('window' yoki 'leave')."""
    col = "last_Window_notified_date" if stage == "window" else "last_leave_notified_date"
    with sqlite3.connect(DB_PATH) as conn:
        cursor = conn.cursor()
        cursor.execute(f"UPDATE schedules SET {col} = ? WHERE id = ?", (date_str, schedule_id))
        conn.commit()
