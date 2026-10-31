# 🚌 Toshkent Avtobus Xabarnoma Telegram Boti (TashBus Alert Bot)

Toshkent shahri bo'ylab har qanday bekat, har qanday avtobus yo'nalishi va shaxsiy vaqt me'yorlari asosida ishlaydigan aqlli Telegram boti.

O'qishga yoki ishga ketish oldidan bekatingizga kelayotgan avtobuslarni kuzatib, **uydan kiyinib chiqish kerak bo'lgan aniq daqiqada** avtomatik ogohlantiruvchi bildirishnoma yuboradi.

---

## ⚙️ Qanday ishlaydi? (Vaqt algoritmi)

Har bir inson uchun shaxsiy tayyorgarlik me'yorlari asosida:
1. **👕 Kiyinish vaqti:** masalan `5 daqiqa` (sozlanadi)
2. **🚶‍♂️ Bekatgacha piyoda yurish:** masalan `8 daqiqa` (sozlanadi)
3. **🛡 Ehtiyot zaxira:** `2 daqiqa`
4. **🔔 Kuzatuv oynasi:** belgilangan vaqtdan `20 daqiqa oldin`

**Misol (Soat 08:00 da bekatda bo'lish kerak bo'lsa):**
- **07:40 da (20 daqiqa oldin):** Bot uyg'onadi va bekatingizga kelayotgan avtobuslar holatini tekshirib, dastlabki xabarni yuboradi.
- **Avtobus bekatga 13–15 daqiqalik masofaga kelganda:** Bot **"🚨 KIYINISHNI BOSHLANG!"** xabarini beradi. Siz 5 daqiqada kiyinib, 8 daqiqada bekatga yetib borganingizda avtobus kirib kelayotgan bo'ladi.

---

## 🌟 Asosiy Imkoniyatlar

- 📍 **Istalgan bekatni tanlash:**
  - Telegram'dan 📎 **Joylashuv (Location)** yuborish orqali avtomatik eng yaqin bekatni topish;
  - Bekat nomini yozib qidirish (masalan: *Chilonzor, Oybek, Farhod bozori, Chorsu, Yunusobod*);
  - Tumanlar bo'yicha saralangan mashhur bekatlar ro'yxatidan tanlash.
- 🚌 **Istalgan avtobus:**
  - Faqat tayyor raqamlar emas, istalgan avtobus raqamini qo'lda yozib kiritish (masalan: `72, 85, 93, 118`).
- ⚙️ **1 bosishda shaxsiy vaqt sozlamalari:**
  - Kiyinish, piyoda yo'l va ogohlantirish daqiqalarini o'zingizga moslash.
- ☁️ **24/7 Bulutda ishlash:**
  - Render.com va Docker orqali kompyuteringiz o'chiq bo'lsa ham mustaqil ishlaydi.

---

## 📱 Bot buyruqlari

- `/start` — Botni ishga tushirish va asosiy menyuni ochish
- `➕ Yangi jadval qo'shish` — Hafta kunlari, bekat, avtobuslar va vaqtni belgilash
- `📅 Mening jadvallarim` — Saqlangan jadvallarni ko'rish va o'chirish
- `🚌 Hozirgi avtobuslar` — Bekatga kelayotgan avtobuslarni jonli tekshirish
- `⚙️ Vaqt sozlamalari` — Kiyinish va yo'l vaqtlarini moslash
- `ℹ️ Yordam va Qo'llanma` — Botdan foydalanish bo'yicha ko'rsatma
