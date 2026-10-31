# 🚌 Toshkent Avtobus Xabarnoma Telegram Boti (Shayxontohur — Nabixon Chustiy mahallasi, 11 va 28-avtobuslar)

Ushbu Telegram-bot Toshkent shahri Shayxontohur tumanidagi **Nabixon Chustiy mahallasi** bekatidan o'tuvchi **11** va **28-sonli avtobuslar** (shuningdek, xaritadan belgilangan istalgan boshqa bekat va yo'nalishlar) harakatini kuzatib, o'qishga ketish vaqtingizga **20 daqiqa qolganda** hamda **kiyinib uydan chiqish kerak bo'lgan daqiqada** avtomatik bildirishnoma yuboradi.

---

## ⚙️ Qanday ishlaydi? (Vaqt algoritmi)

Siz bergan me'yorlar asosida bot 2 bosqichli aqlli ogohlantirish tizimida ishlaydi:
1. **Kiyinish vaqti:** `5 daqiqa`
2. **Bekatgacha piyoda yurish vaqti:** `8 daqiqa`
3. **Ehtiyot zaxira (bufer):** `2 daqiqa` (Jami tayyorgarlik: `15 daqiqa`)
4. **Oldindan kuzatish oynasi:** Belgilangan vaqtga `20 daqiqa` qolganda.

**Misol (Soat 08:00 da bekatdan chiqish kerak bo'lsa):**
- **Soat 07:40 da (20 daqiqa qolganda):** Bot uyg'onadi, `11` va `28`-avtobuslarning bekatgacha qolgan vaqtini tekshiradi va sizga birinchi ma'lumot xabarini yuboradi.
- **Avtobus bekatga 13–15 daqiqalik masofaga kelganda:** Bot sizga darhol **"🚨 KIYINISHNI BOSHLANG!"** xabarini yuboradi. Siz 5 daqiqada kiyinib, 8 daqiqada bekatga yetib borganingizda avtobus bekatga kirib kelayotgan bo'ladi.

---

## 🚀 O'rnatish va Ishga Tushirish Qo'llanmasi

### 1-qadam: Telegram'da Bot Token olish
1. Telegram'da [@BotFather](https://t.me/BotFather) ga kiring va `/newbot` buyrug'ini yuboring.
2. Botga nom (masalan: `Chustiy Avtobus Xabarchisi`) va username (masalan: `chustiy_bus_bot`) bering.
3. BotFather bergan **API Token** nusxasini oling.

### 2-qadam: Kutubxonalarni o'rnatish va Tokenni kiritish
Terminalda loyiha papkasiga kirib quyidagi buyruqlarni bajaring:

```bash
python3 -m venv venv
source venv/bin/activate
pip install -r requirements.txt
cp .env.example .env
```

`.env` faylini ochib, `BOT_TOKEN=` qatoriga @BotFather'dan olgan tokeningizni yozing.

### 3-qadam: Botni ishga tushirish

```bash
python3 bot.py
```

---

## 📱 Botdan foydalanish buyruqlari

- `/start` — Botni ishga tushirish va asosiy menyuni ochish.
- `/quick_chustiy` — **1 bosishda sozlash:** Dushanba–Shanba kunlari uchun **Nabixon Chustiy mahallasi** bekati va **11, 28-avtobuslarni** avtomatik jadvalga qo'shish.
- **➕ Jadval qo'shish** — Haftaning har bir kuni uchun bekatni ro'yxatdan yoki **Telegram Xaritasidan (📍 Location)** belgilash, avtobus raqamlarini va vaqtni tanlash.
- **🚌 Hozirgi avtobuslar (Chustiy)** — Ayni damda Nabixon Chustiy bekatiga 11 va 28-avtobuslar necha daqiqada kelishini tekshirish.
- **⚙️ Vaqt sozlamalari** — Kiyinish (5 daq), yo'l (8 daq) va oldindan ogohlantirish (20 daq) vaqtlarini o'zgartirish.
