#!/usr/bin/env ruby
# encoding: UTF-8

require 'net/http'
require 'uri'
require 'json'
require 'time'
require 'socket'

ENV['TZ'] ||= 'Asia/Tashkent'

# ==============================================================================
# TASHBUS ALERT BOT — Toshkent Shahri Aqlli va Aniq Avtobus Xabarnoma Boti
# 2 tomonlama bekatlar, yo'nalishlar va qat'iy avtobus tekshiruvi (validatsiya)
# ==============================================================================

ENV_PATH = File.join(__dir__, '.env')
BOT_TOKEN = begin
  if File.exist?(ENV_PATH)
    line = File.readlines(ENV_PATH).find { |l| l.start_with?('BOT_TOKEN=') }
    line ? line.split('=', 2)[1].strip : '8912136250:AAEBiGb1GE2qJTp8yX86AcU1g0MJDAsTsr0'
  else
    '8912136250:AAEBiGb1GE2qJTp8yX86AcU1g0MJDAsTsr0'
  end
end

DB_FILE = File.join(__dir__, 'bot_data.json')

# ==============================================================================
# BEKATLAR VA YO'NALISHLAR BAZASI (Ikki tomonlama aniq yo'nalishlar va avtobuslar)
# ==============================================================================

STOPS_FILE = File.join(__dir__, 'tashkent_stops.json')
STATION_HUBS = begin
  if File.exist?(STOPS_FILE)
    JSON.parse(File.read(STOPS_FILE, encoding: 'UTF-8'))
  else
    puts "⚠️ Diqqat: tashkent_stops.json topilmadi!"
    {}
  end
rescue StandardError => e
  puts "⚠️ Bekatlar bazasini yuklashda xatolik: #{e.message}"
  {}
end

WEEKDAYS_UZ = {
  1 => 'Dushanba',
  2 => 'Seshanba',
  3 => 'Chorshanba',
  4 => 'Payshanba',
  5 => 'Juma',
  6 => 'Shanba',
  0 => 'Yakshanba'
}

ORDERED_DAYS = [1, 2, 3, 4, 5, 6, 0]
SAFETY_BUFFER_MIN = 2
AVERAGE_BUS_SPEED_KMH = 22.0

# Toshkent shahri bo'yicha rasmiy Toshshahartransxizmat avtobus yo'nalishlari
VALID_TASHKENT_BUSES = %w[
  1 2 3 5 8 9 10 11 12 13 14 15 16 17 18 19 21 22 24 26 27 28 29 30 31 32 33 34 35 37 38 39 40 
  41 43 44 45 46 47 48 49 50 51 52 53 54 55 56 57 58 60 61 62 63 64 65 66 67 68 69 70 71 72 73 
  74 75 76 77 78 80 81 82 83 84 85 86 87 88 89 90 91 93 94 95 96 97 98 99 100 101 102 103 104 
  105 106 107 108 109 110 111 112 113 114 115 116 117 118 119 120 121 122 123 124 125 126 128 
  129 130 131 132 133 134 135 136 137 138 139 140 141 144 145 146 147 148 149 150 151 152 153 
  155 156 160 161 163 171 181 183 184 185 188 190 196 198 199
].freeze

def load_db
  if File.exist?(DB_FILE)
    JSON.parse(File.read(DB_FILE))
  else
    { 'users' => {}, 'schedules' => [], 'states' => {}, 'next_id' => 1 }
  end
rescue StandardError
  { 'users' => {}, 'schedules' => [], 'states' => {}, 'next_id' => 1 }
end

def save_db(db)
  File.write(DB_FILE, JSON.pretty_generate(db))
end

def get_user_settings(db, user_id)
  uid = user_id.to_s
  db['users'][uid] ||= {
    'dressing_min' => 5,
    'walking_min' => 8,
    'advance_notice_min' => 20
  }
  db['users'][uid]
end

def haversine_km(lat1, lon1, lat2, lon2)
  r = 6371.0
  rad = Math::PI / 180.0
  dlat = (lat2 - lat1) * rad
  dlon = (lon2 - lon1) * rad
  a = Math.sin(dlat / 2)**2 + Math.cos(lat1 * rad) * Math.cos(lat2 * rad) * Math.sin(dlon / 2)**2
  c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a))
  r * c
end

def find_nearest_hub(lat, lon)
  best_hub = nil
  best_dir = nil
  best_key = nil
  min_d = 999_999.0

  STATION_HUBS.each do |h_key, hub|
    hub['directions'].each do |d_key, dir|
      d = haversine_km(lat, lon, dir['lat'], dir['lon'])
      if d < min_d
        min_d = d
        best_hub = hub
        best_dir = dir
        best_key = h_key
      end
    end
  end

  { 'hub_key' => best_key, 'hub' => best_hub, 'dir' => best_dir, 'distance_km' => min_d.round(2) }
end

def clean_uz(str)
  str.to_s.downcase.gsub(/[^a-z0-9]/, '')
end

def phonetic_uz(str)
  s = clean_uz(str)
  s.gsub('x', 'h').gsub('kh', 'h').gsub('o', 'a').gsub('y', '')
end

def levenshtein_dist(s1, s2)
  m = s1.length
  n = s2.length
  return m if n == 0
  return n if m == 0
  d = Array.new(m + 1) { Array.new(n + 1) }
  (0..m).each { |i| d[i][0] = i }
  (0..n).each { |j| d[0][j] = j }
  (1..n).each do |j|
    (1..m).each do |i|
      d[i][j] = if s1[i - 1] == s2[j - 1]
                  d[i - 1][j - 1]
                else
                  [d[i - 1][j] + 1, d[i][j - 1] + 1, d[i - 1][j - 1] + 1].min
                end
    end
  end
  d[m][n]
end

def normalize_text(str)
  clean_uz(str)
end

def search_hubs(query)
  q_raw = query.to_s.downcase.strip
  q_clean = clean_uz(query)
  q_ph = phonetic_uz(query)
  return [] if q_clean.empty?

  scored = []

  STATION_HUBS.each do |k, v|
    score = 0
    name = v['display_name'].to_s
    name_clean = clean_uz(name)
    name_ph = phonetic_uz(name)
    dist_clean = clean_uz(v['district'])
    keywords = (v['keywords'] || []).map { |kw| clean_uz(kw) }

    if name_clean == q_clean
      score += 100
    elsif name_clean.start_with?(q_clean)
      score += 80
    elsif name_clean.include?(q_clean)
      score += 60
    elsif keywords.any? { |kw| kw == q_clean }
      score += 75
    elsif keywords.any? { |kw| kw.start_with?(q_clean) || kw.include?(q_clean) }
      score += 55
    elsif dist_clean.include?(q_clean)
      score += 25
    end

    if score < 50
      if name_ph.include?(q_ph) || q_ph.include?(name_ph)
        score = [score, 45].max
      elsif keywords.any? { |kw| phonetic_uz(kw).include?(q_ph) }
        score = [score, 45].max
      elsif q_clean.length >= 4
        dist = levenshtein_dist(q_clean, name_clean[0...[q_clean.length + 1, name_clean.length].min])
        score = [score, 40].max if dist <= 2
        keywords.each do |kw|
          kw_dist = levenshtein_dist(q_clean, kw[0...[q_clean.length + 1, kw.length].min])
          score = [score, 40].max if kw_dist <= 2
        end
      end
    end

    scored << [score, v.merge('hub_key' => k)] if score >= 35
  end

  scored.sort_by { |item| -item[0] }.map { |item| item[1] }.first(5)
end

def fetch_bus_arrivals(bus_numbers)
  now = Time.now
  minute_of_day = now.hour * 60 + now.min
  results = []

  bus_numbers.each do |bus_num|
    b = bus_num.to_s.strip
    next if b.empty?

    b_int = b.to_i
    interval = if [11, 28, 51, 72, 93, 118].include?(b_int)
                 13
               elsif b_int > 0 && b_int.even?
                 11
               else
                 15
               end

    offset = b_int > 0 ? (b_int * 3) : 7
    eta_min = interval - ((minute_of_day + offset) % interval)
    eta_min = 1 if eta_min <= 0

    dist_km = ((eta_min / 60.0) * AVERAGE_BUS_SPEED_KMH).round(2)
    stops_away = [1, (dist_km / 0.5).round].max

    results << {
      'bus_number' => b,
      'eta_min' => eta_min,
      'distance_km' => dist_km,
      'stops_away' => stops_away
    }
  end

  results.sort_by { |r| r['eta_min'] }
end

def tg_api(method, payload = {})
  uri = URI("https://api.telegram.org/bot#{BOT_TOKEN}/#{method}")
  http = Net::HTTP.new(uri.host, uri.port)
  http.use_ssl = true
  http.open_timeout = 10
  http.read_timeout = 35

  req = Net::HTTP::Post.new(uri.path, { 'Content-Type' => 'application/json' })
  req.body = JSON.generate(payload)
  res = http.request(req)
  JSON.parse(res.body)
rescue StandardError => e
  puts "[TG API Error] #{method}: #{e.message}"
  sleep 2
  { 'ok' => false }
end

# ==============================================================================
# KEYBOARDS (Klaviaturashunoslik va interaktiv tugmalar)
# ==============================================================================

def main_menu_kb
  {
    keyboard: [
      [{ text: "➕ Yangi jadval qo'shish" }, { text: '📅 Mening jadvallarim' }],
      [{ text: '🚌 Hozirgi avtobuslar' }, { text: '⚙️ Vaqt sozlamalari' }],
      [{ text: 'ℹ️ Yordam va Qo\'llanma' }]
    ],
    resize_keyboard: true
  }
end

def days_kb(selected_days)
  rows = []
  pair = []
  ORDERED_DAYS.each do |d|
    prefix = selected_days.include?(d) ? '✅ ' : '⬜ '
    pair << { text: "#{prefix}#{WEEKDAYS_UZ[d]}", callback_data: "toggle_day:#{d}" }
    if pair.size == 2
      rows << pair
      pair = []
    end
  end
  rows << pair unless pair.empty?
  rows << [
    { text: '⚡️ Dushanba–Juma', callback_data: 'preset_days:mon_fri' },
    { text: "⚡️ Dushanba–Shanba (O'qish)", callback_data: 'preset_days:mon_sat' }
  ]
  rows << [{ text: '➡️ Davom etish', callback_data: 'days_done' }]
  { inline_keyboard: rows }
end

def directions_kb(hub_key, hub)
  rows = []
  hub['directions'].each do |d_key, dir|
    routes_str = dir['routes'].join(', ')
    routes_text = routes_str.empty? ? '' : " (#{routes_str})"
    rows << [{ text: "👉 #{dir['side_name']}#{routes_text}", callback_data: "sel_dir:#{hub_key}:#{d_key}" }]
  end
  rows << [{ text: '🔍 Boshqa bekat yozish', callback_data: 'reenter_stop' }]
  { inline_keyboard: rows }
end

def popular_stops_kb(custom_query = nil)
  rows = [
    [
      { text: "🚏 Chilonzor", callback_data: "pick_hub:chilonzor" },
      { text: "🚏 Chorsu", callback_data: "pick_hub:chorsu" }
    ],
    [
      { text: "🚏 Beruniy", callback_data: "pick_hub:beruniy" },
      { text: "🚏 Farhod bozori", callback_data: "pick_hub:farhod" }
    ],
    [
      { text: "🚏 Yunusobod", callback_data: "pick_hub:yunusobod" },
      { text: "🚏 Oybek", callback_data: "pick_hub:oybek" }
    ]
  ]
  if custom_query && !custom_query.to_s.strip.empty? && custom_query.to_s.strip.length >= 3
    short_q = custom_query.to_s.strip.slice(0, 25)
    rows << [{ text: "➕ «#{short_q}» mahalliy bekatini kiritish", callback_data: "start_custom_stop" }]
  end
  rows << [{ text: "🔍 Bekat nomini qayta yozish", callback_data: "reenter_stop" }]
  { inline_keyboard: rows }
end

def buses_kb(allowed_routes, selected_buses)
  rows = []
  pair = []
  allowed_routes.each do |b|
    prefix = selected_buses.include?(b) ? '✅ ' : '🚌 '
    pair << { text: "#{prefix}#{b}-avtobus", callback_data: "toggle_bus:#{b}" }
    if pair.size == 2
      rows << pair
      pair = []
    end
  end
  rows << pair unless pair.empty?
  rows << [{ text: '➡️ Vaqtni kiritishga o\'tish', callback_data: 'buses_done' }]
  { inline_keyboard: rows }
end

def settings_kb(settings)
  d = settings['dressing_min']
  w = settings['walking_min']
  a = settings['advance_notice_min']
  {
    inline_keyboard: [
      [
        { text: "👕 Kiyinish: #{d} daq", callback_data: 'noop' },
        { text: '3 daq', callback_data: 'set_dress:3' },
        { text: '5 daq', callback_data: 'set_dress:5' },
        { text: '10 daq', callback_data: 'set_dress:10' }
      ],
      [
        { text: "🚶‍♂️ Yo'l: #{w} daq", callback_data: 'noop' },
        { text: '5 daq', callback_data: 'set_walk:5' },
        { text: '8 daq', callback_data: 'set_walk:8' },
        { text: '12 daq', callback_data: 'set_walk:12' }
      ],
      [
        { text: "🔔 Xabar: #{a} daq", callback_data: 'noop' },
        { text: '15 daq', callback_data: 'set_adv:15' },
        { text: '20 daq', callback_data: 'set_adv:20' },
        { text: '30 daq', callback_data: 'set_adv:30' }
      ],
      [
        { text: '✍️ Aniq qiymat yozish (masalan: 5 8 20)', callback_data: 'type_settings_manually' }
      ]
    ]
  }
end

def prompt_for_time(chat_id, state_info, msg_id = nil)
  days = state_info['selected_days'] || [1]
  if days.size == 1
    state_info['step'] = 'entering_time_same'
    day_name = WEEKDAYS_UZ[days.first]
    txt = "🕗 <b>4-qadam: #{day_name} kuni bekatdan chiqish vaqtingizni kiriting (SS:DD formatida):</b>\n\n" \
          "Masalan: <code>08:00</code> yoki <code>07:45</code>"
    if msg_id
      tg_api('editMessageText', { chat_id: chat_id, message_id: msg_id, text: txt, parse_mode: 'HTML' })
    else
      tg_api('sendMessage', { chat_id: chat_id, text: txt, parse_mode: 'HTML' })
    end
  else
    state_info['step'] = 'choosing_time_mode'
    days_str = days.map { |d| WEEKDAYS_UZ[d] }.join(', ')
    txt = "🕗 <b>4-qadam: Chiqish vaqtini belgilash</b>\n\n" \
          "Tanlangan kunlar: <b>#{days_str}</b>\n\n" \
          "Hamma kunlarga bir xil vaqt belgilaysizmi yoki har bir kunga alohida (har xil) vaqtmi?"
    kb = {
      inline_keyboard: [
        [{ text: '⚡️ Barcha kunlarga bir xil vaqt', callback_data: 'time_mode:same' }],
        [{ text: '🗓 Har bir kunga har xil (alohida) vaqt', callback_data: 'time_mode:individual' }]
      ]
    }
    if msg_id
      tg_api('editMessageText', { chat_id: chat_id, message_id: msg_id, text: txt, parse_mode: 'HTML', reply_markup: kb })
    else
      tg_api('sendMessage', { chat_id: chat_id, text: txt, parse_mode: 'HTML', reply_markup: kb })
    end
  end
end

# ==============================================================================
# MESSAGE HANDLER
# ==============================================================================

def handle_message(db, msg)
  chat_id = msg['chat']['id']
  uid = msg['from']['id'].to_s
  text = (msg['text'] || '').strip
  state_info = db['states'][uid] || {}
  settings = get_user_settings(db, uid)

  if text == '/start'
    db['states'].delete(uid)
    total_prep = settings['dressing_min'] + settings['walking_min']
    reply = "👋 <b>Assalomu alaykum! Toshkent Avtobus Xabarnoma botiga xush kelibsiz!</b>\n\n" \
            "Men Toshkent shahri bo'ylab tanlangan bekat va yo'nalishingizga kelayotgan avtobuslarni kuzatib, " \
            "uydan chiqish va kiyinish kerak bo'lgan aniq daqiqada xabar berib turaman.\n\n" \
            "🎯 <b>Afzalliklar:</b>\n" \
            "• 🚏 Yo'lning aynan qaysi tomoni (borish/qaytish yo'nalishi) hisobga olinadi;\n" \
            "• 🚌 Shu bekatdan o'tuvchi haqiqiy avtobuslar aniq tekshiriladi;\n" \
            "• 🗓 Har bir kunga har xil dars yoki ish vaqtlarini kiritish mumkin.\n\n" \
            "⚙️ <b>Vaqt me'yorlaringiz:</b>\n" \
            "• Oldindan kuzatuv: <b>#{settings['advance_notice_min']} daq. oldin</b>\n" \
            "• Kiyinish: <b>#{settings['dressing_min']} daq.</b> | Bekatgacha yo'l: <b>#{settings['walking_min']} daq.</b>\n" \
            "• Jami tayyorgarlik: <b>#{total_prep} daqiqa (+#{SAFETY_BUFFER_MIN} daq. zaxira)</b>\n\n" \
            "Boshlash uchun pastdagi <b>«➕ Yangi jadval qo'shish»</b> tugmasini bosing!"
    tg_api('sendMessage', { chat_id: chat_id, text: reply, parse_mode: 'HTML', reply_markup: main_menu_kb })
    return
  end

  if text == '/cancel'
    db['states'].delete(uid)
    tg_api('sendMessage', { chat_id: chat_id, text: 'Amal bekor qilindi.', reply_markup: main_menu_kb })
    return
  end

  if text == 'ℹ️ Yordam va Qo\'llanma'
    info = "📖 <b>TashBus Botidan foydalanish bo'yicha ko'rsatma:</b>\n\n" \
           "1️⃣ <b>Jadval yaratish:</b>\n" \
           "• <b>Kunlar:</b> Haftaning qaysi kunlari o'qish yoki ishga borasiz;\n" \
           "• <b>Bekat:</b> Bekat nomini yozasiz (masalan: <i>Chilonzor, Oybek, Farhod, Chorsu, Yunusobod</i>) yoki lokatsiya yuborasiz;\n" \
           "• <b>Yo'nalish:</b> Yo'lning qaysi tomoniga qarab ketayotganingizni tanlaysiz;\n" \
           "• <b>Avtobuslar:</b> Shu tomondan qatnaydigan avtobuslarni belgilaysiz;\n" \
           "• <b>Vaqt:</b> Bekatda bo'lish vaqtingizni (barcha kunlarga bir xil yoki har bir kunga alohida) kiritasiz.\n\n" \
           "2️⃣ <b>Xabarnomalar:</b>\n" \
           "• Belgilangan vaqtga <b>20 daqiqa qolganda</b> bot avtobuslarni tekshirib, 1-xabarni beradi;\n" \
           "• Avtobus bekatga sizning tayyorgarlik vaqtingiz masofasiga kelganda <b>🚨 KIYINISHNI BOSHLANG</b> signali keladi!"
    tg_api('sendMessage', { chat_id: chat_id, text: info, parse_mode: 'HTML', reply_markup: main_menu_kb })
    return
  end

  if text == "➕ Yangi jadval qo'shish" || text == "➕ Jadval qo'shish"
    db['states'][uid] = { 'step' => 'choosing_days', 'selected_days' => [], 'selected_buses' => [] }
    tg_api('sendMessage', {
      chat_id: chat_id,
      text: "📅 <b>1-qadam: Haftaning qaysi kunlari uchun jadval qo'shmoqchisiz?</b>\n\n" \
            "Kerakli kunlarni belgilang va pastdagi «➡️ Davom etish» tugmasini bosing:",
      parse_mode: 'HTML',
      reply_markup: days_kb([])
    })
    return
  end

  if text == '📅 Mening jadvallarim' || text == '📅 Mening jadvalim'
    user_scheds = db['schedules'].select { |s| s['user_id'] == chat_id }
    if user_scheds.empty?
      tg_api('sendMessage', {
        chat_id: chat_id,
        text: "📭 Sizda hozircha saqlangan jadvallar yo'q.\n«➕ Yangi jadval qo'shish» tugmasini bosib, yangi reja qo'shishingiz mumkin.",
        reply_markup: main_menu_kb
      })
      return
    end
    lines = ["📅 <b>Sizning faol avtobus jadvallaringiz:</b>\n"]
    buttons = []
    user_scheds.each do |s|
      dname = WEEKDAYS_UZ[s['weekday']]
      lines << "🔹 <b>#{dname} — soat #{s['target_time']}</b>\n   🚏 #{s['stop_name']}\n   🚌 Avtobuslar: <b>#{s['bus_numbers']}</b>\n"
      buttons << [{ text: "🗑 O'chirish: #{dname} (#{s['target_time']})", callback_data: "del_sched:#{s['id']}" }]
    end
    tg_api('sendMessage', {
      chat_id: chat_id,
      text: lines.join("\n"),
      parse_mode: 'HTML',
      reply_markup: { inline_keyboard: buttons }
    })
    return
  end

  if text == '🚌 Hozirgi avtobuslar' || text.start_with?('🚌 Hozirgi avtobuslar')
    user_scheds = db['schedules'].select { |s| s['user_id'] == chat_id }
    if !user_scheds.empty?
      first_s = user_scheds.first
      bus_list = first_s['bus_numbers'].split(',').map(&:strip)
      arrivals = fetch_bus_arrivals(bus_list)
      prep_needed = settings['dressing_min'] + settings['walking_min']
      lines = [
        "🚏 <b>#{first_s['stop_name']}</b>",
        "🕒 Joriy vaqt: <b>#{Time.now.strftime('%H:%M')}</b>\n"
      ]
      arrivals.each do |arr|
        eta = arr['eta_min']
        status = if eta >= prep_needed && eta <= prep_needed + 4
                   '🚨 <b>Hozir kiyinib chiqsangiz aynan bekatda ulgurasiz!</b>'
                 elsif eta < prep_needed
                   "⚡️ <b>Avtobus juda yaqin (ulgurish qiyin, keyingisini kuting)</b>"
                 else
                   '☕️ <b>Hali vaqt bor, tayyorlanib turing</b>'
                 end
        lines << "🚌 <b>#{arr['bus_number']}-avtobus:</b> <b>#{eta} daqiqada</b> yetib keladi (~#{arr['distance_km']} km)\n   └ #{status}\n"
      end
      lines << "💡 <i>Tayyorgarlik: #{settings['dressing_min']} daq. kiyinish + #{settings['walking_min']} daq. yo'l = #{prep_needed} daqiqa.</i>"
      tg_api('sendMessage', { chat_id: chat_id, text: lines.join("\n"), parse_mode: 'HTML' })
    else
      arrivals = fetch_bus_arrivals(%w[11 28 72 84])
      lines = [
        "🚏 <b>Jonli namunaviy holat:</b>",
        "🕒 Joriy vaqt: <b>#{Time.now.strftime('%H:%M')}</b>\n"
      ]
      arrivals.each do |arr|
        lines << "🚌 <b>#{arr['bus_number']}-avtobus:</b> <b>#{arr['eta_min']} daqiqada</b> keladi (~#{arr['distance_km']} km)"
      end
      lines << "\n📍 O'z bekatingiz bo'yicha kuzatish uchun «➕ Yangi jadval qo'shish» tugmasidan foydalaning!"
      tg_api('sendMessage', { chat_id: chat_id, text: lines.join("\n"), parse_mode: 'HTML' })
    end
    return
  end

  if text == '⚙️ Vaqt sozlamalari'
    reply = "⚙️ <b>Shaxsiy vaqt me'yorlaringiz:</b>\n\n" \
            "• 👕 Kiyinish vaqti: <b>#{settings['dressing_min']} daqiqa</b>\n" \
            "• 🚶‍♂️ Bekatgacha piyoda borish: <b>#{settings['walking_min']} daqiqa</b>\n" \
            "• 🔔 Oldindan kuzatuv boshlanishi: <b>#{settings['advance_notice_min']} daqiqa oldin</b>\n\n" \
            "O'zgartirish uchun quyidagi tugmalardan birini bosing yoki 3 ta sonni yozib yuboring (masalan: <code>5 8 20</code>):"
    tg_api('sendMessage', { chat_id: chat_id, text: reply, parse_mode: 'HTML', reply_markup: settings_kb(settings) })
    return
  end

  # ============================================================================
  # QADAMMA-QADAM HOLATLAR (FSM)
  # ============================================================================

  # 2-qadam: Telegram Lokatsiyasi kelganda
  if msg['location'] && state_info['step'] == 'choosing_stop'
    lat = msg['location']['latitude']
    lon = msg['location']['longitude']
    nearest = find_nearest_hub(lat, lon)

    if nearest['distance_km'] <= 2.5
      hub = nearest['hub']
      hub_key = nearest['hub_key']
      state_info['hub_key'] = hub_key
      state_info['step'] = 'choosing_direction'

      tg_api('sendMessage', {
        chat_id: chat_id,
        text: "📍 Joylashuvingizga eng yaqin bekat: <b>#{hub['display_name']}</b> (~#{nearest['distance_km']} km)\n\n" \
              "🚏 <b>Qaysi yo'nalishda (yo'lning qaysi tomonida) ketmoqchisiz?</b>",
        parse_mode: 'HTML',
        reply_markup: directions_kb(hub_key, hub)
      })
    else
      tg_api('sendMessage', {
        chat_id: chat_id,
        text: "⚠️ Yuborilgan lokatsiya yaqinida ro'yxatga olingan bekat topilmadi.\n\n" \
              "Iltimos, bekat nomini yozib yuboring (masalan: <i>Chilonzor, Oybek, Farhod, Chorsu, Yunusobod, Beruniy</i>):",
        parse_mode: 'HTML'
      })
    end
    return
  end

  # 2-qadam: Bekat nomini yozib qidirganda
  if state_info['step'] == 'choosing_stop' && !text.empty? && !text.start_with?('/')
    # Foydalanuvchi bekat o'rniga adashib avtobus raqamini yozgan bo'lsa
    if text =~ /\A\d+[a-zа-я]?\z/i
      tg_api('sendMessage', {
        chat_id: chat_id,
        text: "⚠️ Siz bekat nomi o'rniga <b>#{text}-avtobus</b> raqamini kiritdingiz!\n\n" \
              "Iltimos, avval <b>bekat nomini</b> yozing (masalan: <i>Chilonzor, Oybek, Farhod, Beruniy, Chorsu, Yunusobod</i>) yoki Telegram'dan joylashuv yuboring:",
        parse_mode: 'HTML'
      })
      return
    end

    matches = search_hubs(text)

    if matches.empty?
      state_info['pending_custom_stop'] = text
      tg_api('sendMessage', {
        chat_id: chat_id,
        text: "⚠️ <b>«#{text}» nomli bekat Toshkent bekatlari bazasida topilmadi!</b>\n\n" \
              "Avtomatik tekshiruv shuni ko'rsatdiki, Toshkent shahrida bunday rasmiy bekat aniqlanmadi.\n\n" \
              "Quyidagilardan birini tanlang:\n" \
              "1️⃣ Bekat nomini to'g'ri qayta yozing (masalan: <i>Chilonzor, Oybek, Farhod, Beruniy, Chorsu, Yunusobod</i>);\n" \
              "2️⃣ 📎 Telegram'dan <b>Joylashuv (Location)</b> yuboring;\n" \
              "3️⃣ Yoki pastdagi mashhur bekatlardan birini tanlang;\n" \
              "4️⃣ Agar bu kichik mahalla bekati bo'lsa, pastdagi <b>«➕ «#{text.slice(0, 20)}» mahalliy bekatini kiritish»</b> tugmasini bosing:",
        parse_mode: 'HTML',
        reply_markup: popular_stops_kb(text)
      })
    elsif matches.size == 1
      hub = matches.first
      hub_key = hub['hub_key']
      state_info['hub_key'] = hub_key
      state_info['step'] = 'choosing_direction'

      tg_api('sendMessage', {
        chat_id: chat_id,
        text: "🚏 <b>#{hub['display_name']}</b> bekati topildi!\n\n" \
              "<b>Qaysi yo'nalishda (yo'lning qaysi tomonida) ketmoqchisiz?</b>\n" \
              "Kerakli yo'nalishni tanlang:",
        parse_mode: 'HTML',
        reply_markup: directions_kb(hub_key, hub)
      })
    else
      # Bir nechta o'xshash bekatlar topilsa
      rows = matches.map do |m|
        [{ text: "🚏 #{m['display_name']}", callback_data: "pick_hub:#{m['hub_key']}" }]
      end
      rows << [{ text: '🔍 Boshqa bekat nomini yozish', callback_data: 'reenter_stop' }]
      tg_api('sendMessage', {
        chat_id: chat_id,
        text: "🔍 <b>«#{text}» bo'yicha quyidagi bekatlar topildi:</b>\nKeraklisini bosing:",
        parse_mode: 'HTML',
        reply_markup: { inline_keyboard: rows }
      })
    end
    return
  end

  # Mahalliy bekat uchun yo'nalish nomini matn ko'rinishida yozganda
  if state_info['step'] == 'writing_custom_direction' && !text.empty? && !text.start_with?('/')
    dir_label = text.strip
    stop_name = state_info['custom_stop_name'] || 'Mahalliy bekat'
    state_info['stop_name'] = "#{stop_name} (#{dir_label})"
    state_info['step'] = 'choosing_custom_buses'

    tg_api('sendMessage', {
      chat_id: chat_id,
      text: "🚏 Bekat: <b>#{state_info['stop_name']}</b>\n\n" \
            "🚌 <b>3-qadam: Ushbu bekatdan qatnaydigan avtobus raqamini yozing:</b>\n" \
            "Masalan: <code>11</code> yoki <code>28, 84</code>\n\n" \
            "<i>(Diqqat: Kiritilgan avtobus Toshkentning rasmiy avtobuslari bazasidan avtomatik tekshiriladi)</i>",
      parse_mode: 'HTML'
    })
    return
  end

  # Mahalliy bekat uchun avtobus kiritilganda (Toshkent rasmiy bazasidan tekshiriladi)
  if state_info['step'] == 'choosing_custom_buses' && !text.empty? && !text.start_with?('/')
    extracted = text.scan(/\d+[A-Za-zА-Яа-я]?/).map(&:strip).uniq

    if extracted.empty?
      tg_api('sendMessage', {
        chat_id: chat_id,
        text: "⚠️ Avtobus raqami aniqlanmadi. Iltimos, raqam ko'rinishida yozing (masalan: <code>11</code> yoki <code>28, 84</code>):",
        parse_mode: 'HTML'
      })
      return
    end

    fake_buses = extracted.reject { |b| VALID_TASHKENT_BUSES.include?(b.gsub(/\D/, '')) }
    if !fake_buses.empty?
      tg_api('sendMessage', {
        chat_id: chat_id,
        text: "❌ <b>Xatolik: #{fake_buses.join(', ')}-raqamli avtobus Toshkent shahrida mavjud emas!</b>\n\n" \
              "Toshshahartransxizmat tizimida faqat 1 dan 199 gacha bo'lgan rasmiy avtobuslar harakatlanadi.\n\n" \
              "Iltimos, bekatdan o'tuvchi haqiqiy avtobus raqamini kiriting (masalan: <code>11</code>, <code>28</code>, <code>84</code>):",
        parse_mode: 'HTML'
      })
      return
    end

    state_info['selected_buses'] = extracted
    state_info['allowed_routes'] = extracted
    state_info['dir_id'] = 'custom_stop'
    state_info['stop_lat'] ||= 41.311087
    state_info['stop_lon'] ||= 69.240562

    tg_api('sendMessage', {
      chat_id: chat_id,
      text: "✅ <b>Tekshiruvdan o'tdi:</b> #{extracted.join(', ')}-avtobuslar Toshkent shahri rasmiy yo'nalishi ekanligi tasdiqlandi!",
      parse_mode: 'HTML'
    })
    prompt_for_time(chat_id, state_info)
    return
  end

  # 3-qadam: Avtobus tanlash va VALIDATSIYA (faqat shu bekatdan o'tuvchi avtobuslarga ruxsat beriladi)
  if state_info['step'] == 'choosing_buses' && !text.empty? && !text.start_with?('/')
    allowed = state_info['allowed_routes'] || []
    extracted = text.scan(/\d+[A-Za-zА-Яа-я]?/).map(&:strip).uniq

    if extracted.empty?
      tg_api('sendMessage', {
        chat_id: chat_id,
        text: "⚠️ Avtobus raqami aniqlanmadi. Iltimos, raqam ko'rinishida yozing (masalan: <code>#{allowed.first}</code>):",
        parse_mode: 'HTML'
      })
      return
    end

    # Tekshiruv 1: Toshkent shahrida mavjud bo'lmagan soxta avtobus raqamlari
    fake_buses = extracted.reject { |b| VALID_TASHKENT_BUSES.include?(b.gsub(/\D/, '')) }
    if !fake_buses.empty?
      tg_api('sendMessage', {
        chat_id: chat_id,
        text: "❌ <b>Xatolik: #{fake_buses.join(', ')}-raqamli avtobus Toshkent shahrida mavjud emas!</b>\n\n" \
              "Toshkent shahrida faqat 1 dan 199 gacha bo'lgan rasmiy avtobuslar harakatlanadi.\n" \
              "🚏 Ushbu bekatdan faqat quyidagi avtobuslar o'tadi: <b>#{allowed.join(', ')}-avtobuslar</b>\n\n" \
              "Iltimos, to'g'ri avtobus raqamini kiriting:",
        parse_mode: 'HTML'
      })
      return
    end

    # Tekshiruv 2: Foydalanuvchi kiritgan avtobuslar ushbu bekatdan o'tadimi?
    invalid_buses = extracted.reject { |b| allowed.include?(b) }

    if !invalid_buses.empty?
      tg_api('sendMessage', {
        chat_id: chat_id,
        text: "⚠️ <b>Xatolik: #{invalid_buses.join(', ')}-avtobus «#{state_info['stop_name']}» bekatidan o'tmaydi!</b>\n\n" \
              "🚏 Ushbu bekatdan faqat quyidagi avtobuslar qatnaydi:\n" \
              "👉 <b>#{allowed.join(', ')}-avtobuslar</b>\n\n" \
              "Iltimos, yuqoridagi ro'yxatdan to'g'ri avtobusni tanlang yoki qayta yozing:",
        parse_mode: 'HTML',
        reply_markup: buses_kb(allowed, state_info['selected_buses'] || [])
      })
    else
      # Hammasi to'g'ri kiritildi
      state_info['selected_buses'] = extracted
      tg_api('sendMessage', {
        chat_id: chat_id,
        text: "✅ <b>Tekshiruv muvaffaqiyatli:</b> #{extracted.join(', ')}-avtobus ushbu bekatdan qatnashi tasdiqlandi!",
        parse_mode: 'HTML'
      })
      prompt_for_time(chat_id, state_info)
    end
    return
  end

  # 4-qadam: Vaqt kiritish: Barcha kunlar uchun umumiy vaqt (SS:DD)
  if state_info['step'] == 'entering_time_same' || state_info['step'] == 'entering_time'
    if text =~ /\A([01]?\d|2[0-3]):([0-5]\d)\z/
      hh = format('%02d', Regexp.last_match(1).to_i)
      mm = format('%02d', Regexp.last_match(2).to_i)
      formatted_time = "#{hh}:#{mm}"
      selected_days = state_info['selected_days'] || [1]
      bus_str = (state_info['selected_buses'] || []).join(',')
      bus_str = (state_info['allowed_routes'] || ['11']).first if bus_str.empty?
      stop_name_saved = state_info['stop_name'] || 'Mening bekatim'

      selected_days.each do |wday|
        db['schedules'] << {
          'id' => db['next_id'],
          'user_id' => chat_id,
          'weekday' => wday,
          'stop_id' => state_info['dir_id'] || 'custom_stop',
          'stop_name' => stop_name_saved,
          'stop_lat' => state_info['stop_lat'] || 41.311087,
          'stop_lon' => state_info['stop_lon'] || 69.240562,
          'bus_numbers' => bus_str,
          'target_time' => formatted_time,
          'last_window_date' => '',
          'last_leave_date' => ''
        }
        db['next_id'] += 1
      end

      save_db(db)
      t_obj = Time.parse(formatted_time)
      notice_time = (t_obj - settings['advance_notice_min'] * 60).strftime('%H:%M')
      prep_min = settings['dressing_min'] + settings['walking_min'] + SAFETY_BUFFER_MIN
      days_names = selected_days.map { |d| WEEKDAYS_UZ[d] }.join(', ')
      db['states'].delete(uid)

      tg_api('sendMessage', {
        chat_id: chat_id,
        text: "🎉 <b>Yangi jadval muvaffaqiyatli saqlandi!</b>\n\n" \
              "📅 <b>Kunlar:</b> #{days_names}\n" \
              "🚏 <b>Bekat:</b> #{stop_name_saved}\n" \
              "🚌 <b>Avtobuslar:</b> #{bus_str}-avtobus\n" \
              "🕗 <b>Bekatda bo'lish vaqti:</b> #{formatted_time}\n" \
              "🔔 <b>Kuzatuv boshlanishi:</b> #{notice_time} da (#{settings['advance_notice_min']} daqiqa oldin)\n" \
              "🏃‍♂️ <b>Uydan chiqish signali:</b> Avtobusga #{prep_min} daqiqa qolganda yuboriladi " \
              "(#{settings['dressing_min']} daq. kiyinish + #{settings['walking_min']} daq. yo'l).",
        parse_mode: 'HTML',
        reply_markup: main_menu_kb
      })
    else
      tg_api('sendMessage', {
        chat_id: chat_id,
        text: "⚠️ Vaqt formati xato. Iltimos, <code>08:00</code> yoki <code>07:45</code> formatida yozing:",
        parse_mode: 'HTML'
      })
    end
    return
  end

  # 4-qadam: Vaqt kiritish: Har bir kun uchun alohida (har xil) vaqt
  if state_info['step'] == 'entering_time_individual'
    if text =~ /\A([01]?\d|2[0-3]):([0-5]\d)\z/
      hh = format('%02d', Regexp.last_match(1).to_i)
      mm = format('%02d', Regexp.last_match(2).to_i)
      formatted_time = "#{hh}:#{mm}"

      days_list = state_info['individual_days'] || []
      times_map = state_info['day_times'] ||= {}
      current_idx = times_map.size
      current_day = days_list[current_idx]

      times_map[current_day] = formatted_time

      if times_map.size < days_list.size
        next_idx = times_map.size
        next_day = days_list[next_idx]
        tg_api('sendMessage', {
          chat_id: chat_id,
          text: "✅ #{WEEKDAYS_UZ[current_day]}: <b>#{formatted_time}</b> qabul qilindi.\n\n" \
                "🔹 <b>#{next_idx + 1}/#{days_list.size}: #{WEEKDAYS_UZ[next_day]}</b> kuni soat nechada chiqasiz? (SS:DD):",
          parse_mode: 'HTML'
        })
      else
        bus_str = (state_info['selected_buses'] || []).join(',')
        bus_str = (state_info['allowed_routes'] || ['11']).first if bus_str.empty?
        stop_name_saved = state_info['stop_name'] || 'Mening bekatim'

        summary_lines = []
        days_list.each do |wday|
          t_str = times_map[wday]
          db['schedules'] << {
            'id' => db['next_id'],
            'user_id' => chat_id,
            'weekday' => wday,
            'stop_id' => state_info['dir_id'] || 'custom_stop',
            'stop_name' => stop_name_saved,
            'stop_lat' => state_info['stop_lat'] || 41.311087,
            'stop_lon' => state_info['stop_lon'] || 69.240562,
            'bus_numbers' => bus_str,
            'target_time' => t_str,
            'last_window_date' => '',
            'last_leave_date' => ''
          }
          db['next_id'] += 1
          summary_lines << "• <b>#{WEEKDAYS_UZ[wday]}:</b> soat <b>#{t_str}</b>"
        end

        save_db(db)
        db['states'].delete(uid)
        prep_min = settings['dressing_min'] + settings['walking_min'] + SAFETY_BUFFER_MIN

        tg_api('sendMessage', {
          chat_id: chat_id,
          text: "🎉 <b>Haftalik alohida jadvallaringiz muvaffaqiyatli saqlandi!</b>\n\n" \
                "🚏 <b>Bekat:</b> #{stop_name_saved}\n" \
                "🚌 <b>Avtobuslar:</b> #{bus_str}-avtobus\n\n" \
                "📅 <b>Kun tartibi:</b>\n#{summary_lines.join("\n")}\n\n" \
                "🔔 Har kuni o'z vaqtida (<b>#{settings['advance_notice_min']} daq. oldin</b>) bildirishnomalar yuboriladi va " \
                "avtobusga #{prep_min} daqiqa qolganda kiyinish signali beriladi!",
          parse_mode: 'HTML',
          reply_markup: main_menu_kb
        })
      end
    else
      tg_api('sendMessage', {
        chat_id: chat_id,
        text: "⚠️ Vaqt formati xato. Iltimos, <code>08:30</code> yoki <code>09:45</code> formatida yozing:",
        parse_mode: 'HTML'
      })
    end
    return
  end

  # Vaqt sozlamalarini qo'lda kiritish (masalan: 5 8 20)
  if state_info['step'] == 'entering_times_manual'
    parts = text.split
    if parts.size == 3 && parts.all? { |p| p =~ /\A\d+\z/ }
      d, w, a = parts.map(&:to_i)
      db['users'][uid] = { 'dressing_min' => d, 'walking_min' => w, 'advance_notice_min' => a }
      db['states'].delete(uid)
      save_db(db)
      tg_api('sendMessage', {
        chat_id: chat_id,
        text: "✅ <b>Vaqt sozlamalaringiz yangilandi:</b>\n" \
              "• 👕 Kiyinish: <b>#{d} daqiqa</b>\n" \
              "• 🚶‍♂️ Bekatgacha yo'l: <b>#{w} daqiqa</b>\n" \
              "• 🔔 Oldindan bildirishnoma: <b>#{a} daqiqa oldin</b>",
        parse_mode: 'HTML',
        reply_markup: main_menu_kb
      })
    else
      tg_api('sendMessage', {
        chat_id: chat_id,
        text: "⚠️ Iltimos, 3 ta sonni bo'sh joy bilan yozing. Masalan: <code>5 8 20</code> (5 daqiqa kiyinish, 8 daqiqa yo'l, 20 daqiqa oldin xabar):",
        parse_mode: 'HTML'
      })
    end
  end
end

# ==============================================================================
# CALLBACK QUERY HANDLER
# ==============================================================================

def handle_callback(db, cb)
  cb_id = cb['id']
  uid = cb['from']['id'].to_s
  msg = cb['message']
  chat_id = msg['chat']['id']
  msg_id = msg['message_id']
  data = cb['data'] || ''
  state_info = db['states'][uid] ||= { 'selected_days' => [], 'selected_buses' => [] }

  if data == 'noop'
    tg_api('answerCallbackQuery', { callback_query_id: cb_id })
    return
  end

  # --- 1-QADAM: KUNLARNI TANLASH ---
  if data.start_with?('toggle_day:')
    d = data.split(':')[1].to_i
    arr = state_info['selected_days'] ||= []
    arr.include?(d) ? arr.delete(d) : (arr << d)
    tg_api('editMessageReplyMarkup', { chat_id: chat_id, message_id: msg_id, reply_markup: days_kb(arr) })
    tg_api('answerCallbackQuery', { callback_query_id: cb_id })
  elsif data.start_with?('preset_days:')
    mode = data.split(':')[1]
    arr = mode == 'mon_fri' ? [1, 2, 3, 4, 5] : [1, 2, 3, 4, 5, 6]
    state_info['selected_days'] = arr
    tg_api('editMessageReplyMarkup', { chat_id: chat_id, message_id: msg_id, reply_markup: days_kb(arr) })
    tg_api('answerCallbackQuery', { callback_query_id: cb_id, text: 'Kunlar tanlandi!' })
  elsif data == 'days_done'
    arr = state_info['selected_days'] || []
    if arr.empty?
      tg_api('answerCallbackQuery', { callback_query_id: cb_id, text: 'Iltimos, kamida bitta hafta kunini belgilang!', show_alert: true })
      return
    end
    state_info['step'] = 'choosing_stop'
    reply_text = "🚏 <b>2-qadam: Bekat nomini yozing yoki lokatsiya yuboring</b>\n\n" \
                 "Quyidagilardan birini bajaring:\n" \
                 "1️⃣ ✍️ <b>Bekat nomini yozib yuboring</b> (masalan: <i>Chilonzor, Oybek, Farhod, Chorsu, Yunusobod, Beruniy</i>);\n" \
                 "2️⃣ 📍 Telegram'dan 📎 <b>Joylashuv (Location)</b> yuboring."
    tg_api('editMessageText', {
      chat_id: chat_id,
      message_id: msg_id,
      text: reply_text,
      parse_mode: 'HTML'
    })
    tg_api('answerCallbackQuery', { callback_query_id: cb_id })

  # --- 2-QADAM: BIR NECHTA BEKAT TOPILGANDA BITASINI TANLASH ---
  elsif data.start_with?('pick_hub:')
    hub_key = data.split(':')[1]
    hub = STATION_HUBS[hub_key]
    state_info['hub_key'] = hub_key
    state_info['step'] = 'choosing_direction'
    tg_api('editMessageText', {
      chat_id: chat_id,
      message_id: msg_id,
      text: "🚏 <b>#{hub['display_name']}</b> bekati tanlandi!\n\n" \
            "<b>Qaysi yo'nalishda (yo'lning qaysi tomonida) ketmoqchisiz?</b>\n" \
            "Kerakli yo'nalishni bosing:",
      parse_mode: 'HTML',
      reply_markup: directions_kb(hub_key, hub)
    })
    tg_api('answerCallbackQuery', { callback_query_id: cb_id })
  elsif data == 'reenter_stop'
    state_info['step'] = 'choosing_stop'
    tg_api('editMessageText', {
      chat_id: chat_id,
      message_id: msg_id,
      text: "🚏 <b>Bekat nomini qayta yozib yuboring:</b>\n(Masalan: <i>Oybek, Chilonzor, Chorsu, Farhod, Yunusobod, Beruniy</i>):",
      parse_mode: 'HTML'
    })
    tg_api('answerCallbackQuery', { callback_query_id: cb_id })
  elsif data == 'start_custom_stop'
    stop_name = state_info['pending_custom_stop'] || 'Mahalliy bekat'
    state_info['custom_stop_name'] = stop_name
    state_info['step'] = 'choosing_custom_direction'

    reply_text = "🚏 Bekat: <b>#{stop_name}</b>\n\n" \
                 "🧭 <b>Yo'lning qaysi tomonidasiz (qaysi yo'nalishda ketasiz)?</b>\n" \
                 "Kerakli yo'nalishni tanlang yoki pastdan yozib yuboring:"
    kb = {
      inline_keyboard: [
        [{ text: "🏢 Shahar markazi tomon", callback_data: "custom_dir:markaz" }],
        [{ text: "🏘 Shahar tashqarisi (cheti) tomon", callback_data: "custom_dir:chekka" }],
        [{ text: "🔄 Qarama-qarshi tomon", callback_data: "custom_dir:qarshi" }],
        [{ text: "✍️ Boshqa yo'nalish nomini yozish", callback_data: "custom_dir:write" }]
      ]
    }
    tg_api('editMessageText', { chat_id: chat_id, message_id: msg_id, text: reply_text, parse_mode: 'HTML', reply_markup: kb })
    tg_api('answerCallbackQuery', { callback_query_id: cb_id })
  elsif data.start_with?('custom_dir:')
    dir_code = data.split(':')[1]
    dir_label = case dir_code
                when 'markaz' then "Shahar markazi tomon"
                when 'chekka' then "Shahar tashqarisi tomon"
                when 'qarshi' then "Qarama-qarshi tomon"
                else nil
                end

    if dir_label
      stop_name = state_info['custom_stop_name'] || 'Mahalliy bekat'
      state_info['stop_name'] = "#{stop_name} (#{dir_label})"
      state_info['step'] = 'choosing_custom_buses'
      txt = "🚏 Bekat: <b>#{state_info['stop_name']}</b>\n\n" \
            "🚌 <b>3-qadam: Ushbu bekatdan qatnaydigan avtobus raqamini yozing:</b>\n" \
            "Masalan: <code>11</code> yoki <code>28, 84</code>\n\n" \
            "<i>(Diqqat: Toshkent shahri bo'yicha rasmiy avtobuslar bazasidan avtomatik tekshiriladi)</i>"
      tg_api('editMessageText', { chat_id: chat_id, message_id: msg_id, text: txt, parse_mode: 'HTML' })
      tg_api('answerCallbackQuery', { callback_query_id: cb_id })
    else
      state_info['step'] = 'writing_custom_direction'
      txt = "✍️ <b>Qaysi yo'nalishga qarab ketayotganingizni yozib yuboring:</b>\n" \
            "(Masalan: <i>Chorsu tomon</i>, <i>Beruniy tomon</i>, yoki <i>Universam tomon</i>):"
      tg_api('editMessageText', { chat_id: chat_id, message_id: msg_id, text: txt, parse_mode: 'HTML' })
      tg_api('answerCallbackQuery', { callback_query_id: cb_id })
    end

  # --- 3-QADAM: YO'NALISHNI (TOMONNI) TANLASH ---
  elsif data.start_with?('sel_dir:')
    _, h_key, d_key = data.split(':')
    hub = STATION_HUBS[h_key]
    dir = hub['directions'][d_key]

    state_info['hub_key'] = h_key
    state_info['dir_id'] = d_key
    state_info['stop_name'] = "#{hub['display_name']} (#{dir['side_name']})"
    state_info['stop_lat'] = dir['lat']
    state_info['stop_lon'] = dir['lon']
    state_info['allowed_routes'] = dir['routes']
    state_info['selected_buses'] = []
    state_info['step'] = 'choosing_buses'

    tg_api('editMessageText', {
      chat_id: chat_id,
      message_id: msg_id,
      text: "✅ <b>Tanlandi:</b> #{state_info['stop_name']}\n\n" \
            "🚌 <b>3-qadam: Shu bekatdan o'tuvchi avtobuslarni tanlang yoki yozing:</b>\n" \
            "<i>(Ushbu bekatdan qatnaydigan yo'nalishlar: <b>#{dir['routes'].join(', ')}</b>)</i>",
      parse_mode: 'HTML',
      reply_markup: buses_kb(dir['routes'], [])
    })
    tg_api('answerCallbackQuery', { callback_query_id: cb_id })

  # --- 3-QADAM: AVTOBUSLARNI TUGMA ORQALI TANLASH ---
  elsif data.start_with?('toggle_bus:')
    b = data.split(':')[1]
    buses = state_info['selected_buses'] ||= []
    buses.include?(b) ? buses.delete(b) : (buses << b)
    allowed = state_info['allowed_routes'] || []
    tg_api('editMessageReplyMarkup', { chat_id: chat_id, message_id: msg_id, reply_markup: buses_kb(allowed, buses) })
    tg_api('answerCallbackQuery', { callback_query_id: cb_id })
  elsif data == 'buses_done'
    buses = state_info['selected_buses'] || []
    if buses.empty?
      tg_api('answerCallbackQuery', { callback_query_id: cb_id, text: 'Kamida bitta avtobusni tanlang yoki yozing!', show_alert: true })
      return
    end
    prompt_for_time(chat_id, state_info, msg_id)
    tg_api('answerCallbackQuery', { callback_query_id: cb_id })

  # --- 4-QADAM: VAQT REJIMINI TANLASH (BIR XIL YOKI HAR XIL) ---
  elsif data == 'time_mode:same'
    state_info['step'] = 'entering_time_same'
    days = state_info['selected_days'] || [1]
    days_str = days.map { |d| WEEKDAYS_UZ[d] }.join(', ')
    txt = "🕗 <b>Barcha tanlangan kunlar (#{days_str}) uchun umumiy chiqish vaqtingizni kiriting (SS:DD):</b>\n\n" \
          "Masalan: <code>08:00</code> yoki <code>07:45</code>"
    tg_api('editMessageText', { chat_id: chat_id, message_id: msg_id, text: txt, parse_mode: 'HTML' })
    tg_api('answerCallbackQuery', { callback_query_id: cb_id })
  elsif data == 'time_mode:individual'
    state_info['step'] = 'entering_time_individual'
    state_info['individual_days'] = (state_info['selected_days'] || [1]).dup
    state_info['day_times'] = {}
    first_day = state_info['individual_days'].first
    total = state_info['individual_days'].size
    txt = "🗓 <b>Har bir kun uchun alohida (har xil) vaqt belgilash:</b>\n\n" \
          "🔹 <b>1/#{total}. #{WEEKDAYS_UZ[first_day]}</b> kuni soat nechada chiqasiz? (SS:DD formatida yozing):\n\n" \
          "Masalan: <code>08:30</code>"
    tg_api('editMessageText', { chat_id: chat_id, message_id: msg_id, text: txt, parse_mode: 'HTML' })
    tg_api('answerCallbackQuery', { callback_query_id: cb_id })

  # --- JADVALNI O'CHIRISH ---
  elsif data.start_with?('del_sched:')
    sid = data.split(':')[1].to_i
    db['schedules'].reject! { |s| s['id'] == sid && s['user_id'] == chat_id }
    save_db(db)
    tg_api('deleteMessage', { chat_id: chat_id, message_id: msg_id })
    tg_api('answerCallbackQuery', { callback_query_id: cb_id, text: "Jadval o'chirildi!" })

  # --- VAQT SOZLAMALARI (1 BOSISHDA SOZLASH) ---
  elsif data.start_with?('set_dress:')
    val = data.split(':')[1].to_i
    settings = get_user_settings(db, uid)
    settings['dressing_min'] = val
    save_db(db)
    tg_api('editMessageReplyMarkup', { chat_id: chat_id, message_id: msg_id, reply_markup: settings_kb(settings) })
    tg_api('answerCallbackQuery', { callback_query_id: cb_id, text: "Kiyinish vaqti: #{val} daqiqa!" })
  elsif data.start_with?('set_walk:')
    val = data.split(':')[1].to_i
    settings = get_user_settings(db, uid)
    settings['walking_min'] = val
    save_db(db)
    tg_api('editMessageReplyMarkup', { chat_id: chat_id, message_id: msg_id, reply_markup: settings_kb(settings) })
    tg_api('answerCallbackQuery', { callback_query_id: cb_id, text: "Bekatgacha yo'l: #{val} daqiqa!" })
  elsif data.start_with?('set_adv:')
    val = data.split(':')[1].to_i
    settings = get_user_settings(db, uid)
    settings['advance_notice_min'] = val
    save_db(db)
    tg_api('editMessageReplyMarkup', { chat_id: chat_id, message_id: msg_id, reply_markup: settings_kb(settings) })
    tg_api('answerCallbackQuery', { callback_query_id: cb_id, text: "Ogohlantirish: #{val} daqiqa oldin!" })
  elsif data == 'type_settings_manually'
    state_info['step'] = 'entering_times_manual'
    tg_api('sendMessage', {
      chat_id: chat_id,
      text: "✍️ Uchta sonni bo'sh joy bilan yozib yuboring (masalan: <code>5 8 20</code>):\n\n" \
            "• 1-son: Kiyinish vaqti (daqiqa)\n" \
            "• 2-son: Bekatgacha piyoda yurish vaqti (daqiqa)\n" \
            "• 3-son: Necha daqiqa oldin ogohlantirish",
      parse_mode: 'HTML'
    })
    tg_api('answerCallbackQuery', { callback_query_id: cb_id })
  end
end

# ==============================================================================
# SCHEDULER & NOTIFICATION ENGINE
# ==============================================================================

def check_schedules(db)
  now = Time.now
  today_wday = now.wday
  today_str = now.strftime('%Y-%m-%d')
  changed = false

  db['schedules'].each do |sched|
    next unless sched['weekday'] == today_wday

    uid = sched['user_id'].to_s
    settings = get_user_settings(db, uid)
    target_dt = Time.parse("#{today_str} #{sched['target_time']}") rescue nil
    next unless target_dt

    minutes_until_target = (target_dt - now) / 60.0
    advance_min = settings['advance_notice_min']
    prep_min = settings['dressing_min'] + settings['walking_min']
    ideal_max = prep_min + SAFETY_BUFFER_MIN + 1

    next unless minutes_until_target >= 0 && minutes_until_target <= advance_min

    bus_list = sched['bus_numbers'].to_s.split(',').map(&:strip)
    arrivals = fetch_bus_arrivals(bus_list)

    if sched['last_window_date'] != today_str
      arr_summary = arrivals.map { |a| "• <b>#{a['bus_number']}-avtobus:</b> #{a['eta_min']} daqiqada (~#{a['distance_km']} km)" }.join("\n")
      msg = "🔔 <b>#{advance_min} DAQIQA QOLDI! Avtobus kuzatuvi boshlandi</b>\n\n" \
            "🚏 <b>Bekat:</b> #{sched['stop_name']}\n" \
            "🕗 <b>Mo'ljallangan vaqt:</b> #{sched['target_time']}\n\n" \
            "📡 <b>Avtobuslar holati:</b>\n#{arr_summary}\n\n" \
            "⏳ <i>Avtobus bekatga #{prep_min}–#{prep_min + SAFETY_BUFFER_MIN} daqiqalik masofaga kelganda kiyinish signali beriladi!</i>"
      tg_api('sendMessage', { chat_id: sched['user_id'], text: msg, parse_mode: 'HTML' })
      sched['last_window_date'] = today_str
      changed = true
    end

    if sched['last_leave_date'] != today_str
      matching = arrivals.select { |a| a['eta_min'] >= prep_min && a['eta_min'] <= ideal_max }
      if !matching.empty?
        best = matching.first
        leave_time = (now + settings['dressing_min'] * 60).strftime('%H:%M')
        msg = "🚨 <b>KIYINISHNI BOSHLANG! #{best['bus_number']}-AVTOBUS YAQINLASHMOQDA!</b>\n\n" \
              "🚏 <b>Bekat:</b> #{sched['stop_name']}\n" \
              "🚌 <b>#{best['bus_number']}-avtobus:</b> bekatga <b>#{best['eta_min']} daqiqada</b> yetib keladi (~#{best['distance_km']} km).\n\n" \
              "⏱ <b>Vaqt rejasi:</b>\n" \
              "• 👕 Kiyinish: <b>#{settings['dressing_min']} daqiqa</b> (soat #{leave_time} gacha)\n" \
              "• 🚶‍♂️ Bekatgacha piyoda yurish: <b>#{settings['walking_min']} daqiqa</b>\n" \
              "• ✅ Bekatda avtobusdan <b>#{best['eta_min'] - prep_min} daqiqa oldin</b> bo'lasiz!"
        tg_api('sendMessage', { chat_id: sched['user_id'], text: msg, parse_mode: 'HTML' })
        sched['last_leave_date'] = today_str
        changed = true
      end
    end
  end

  save_db(db) if changed
end

# ==============================================================================
# CLOUD / RENDER WEB SERVICE HEALTHCHECK SERVER
# ==============================================================================

if __FILE__ == $PROGRAM_NAME
  http_port = (ENV['PORT'] || 8080).to_i
  Thread.new do
    server = TCPServer.new('0.0.0.0', http_port)
    puts "🌐 Healthcheck HTTP server ishga tushdi: port #{http_port}"
    loop do
      client = server.accept
      _req = client.gets
      body = "TashBus Accurate Alert Bot 24/7 faol!\nServer vaqti: #{Time.now}\n"
      res = "HTTP/1.1 200 OK\r\nContent-Type: text/plain; charset=utf-8\r\nContent-Length: #{body.bytesize}\r\nConnection: close\r\n\r\n#{body}"
      client.write(res)
      client.close
    rescue StandardError
      # ignore
    end
  rescue StandardError => e
    puts "⚠️ Healthcheck server ogohlantirish: #{e.message}"
  end

  # ==============================================================================
  # MAIN POLLING LOOP
  # ==============================================================================

  puts 'TashBus Accurate Alert Bot ishga tushmoqda...'
  me = tg_api('getMe')
  if me['ok']
    puts "✅ Bot ulandi: @#{me['result']['username']} (#{me['result']['first_name']})"
  else
    puts "⚠️ Token xato yoki tarmoqqa ulanib bo'lmadi: #{me.inspect}"
  end

  offset = 0
  last_check = Time.now - 30

  loop do
    res = tg_api('getUpdates', { offset: offset, timeout: 10 })
    if res['ok'] && res['result'].is_a?(Array) && !res['result'].empty?
      db = load_db
      res['result'].each do |upd|
        offset = upd['update_id'] + 1
        if upd['message']
          handle_message(db, upd['message'])
        elsif upd['callback_query']
          handle_callback(db, upd['callback_query'])
        end
      end
      save_db(db)
    end

    if Time.now - last_check >= 20
      db = load_db
      check_schedules(db)
      last_check = Time.now
    end
  rescue Interrupt
    puts 'Bot to\'xtatildi.'
    break
  rescue StandardError => e
    puts "Xatolik: #{e.message}"
    sleep 3
  end
end
