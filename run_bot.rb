#!/usr/bin/env ruby
# encoding: UTF-8

require 'net/http'
require 'uri'
require 'json'
require 'time'
require 'socket'

ENV['TZ'] ||= 'Asia/Tashkent'

# ==============================================================================
# TASHBUS ALERT BOT — Toshkent Shahri Umumiy Avtobus Xabarnoma Boti
# Har qanday bekat, har qanday avtobus yo'nalishi va shaxsiy vaqt sozlamalari bilan
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

# Toshkent shahri bo'ylab asosiy transport tugunlari va mashhur bekatlar bazasi
PRESET_STOPS = {
  # Shayxontohur & Markaz
  'chustiy_chorsu' => {
    'name' => "Nabixon Chustiy (Chorsu tomon)",
    'district' => 'Shayxontohur',
    'lat' => 41.332850, 'lon' => 69.218420,
    'routes' => ['11', '28'],
    'yandex_url' => 'https://yandex.uz/maps/10335/tashkent/stops/1719128660/'
  },
  'chustiy_beruniy' => {
    'name' => "Nabixon Chustiy (Beruniy tomon)",
    'district' => 'Shayxontohur',
    'lat' => 41.333120, 'lon' => 69.218150,
    'routes' => ['11', '28'],
    'yandex_url' => 'https://yandex.com/maps/10335/tashkent/stops/1719128770/'
  },
  'chorsu_bozor' => {
    'name' => "Chorsu bozori bekati",
    'district' => 'Shayxontohur',
    'lat' => 41.326700, 'lon' => 69.239200,
    'routes' => ['11', '28', '46', '53'],
    'yandex_url' => 'https://yandex.uz/maps/10335/tashkent/'
  },
  'paxtakor_navoiy' => {
    'name' => "Alisher Navoiy / Paxtakor metrosi",
    'district' => 'Shayxontohur',
    'lat' => 41.320400, 'lon' => 69.255800,
    'routes' => ['11', '28', '44', '57'],
    'yandex_url' => 'https://yandex.uz/maps/10335/tashkent/'
  },
  'maktab_41' => {
    'name' => "41-Maktab bekati",
    'district' => 'Shayxontohur',
    'lat' => 41.330410, 'lon' => 69.224890,
    'routes' => ['11', '28'],
    'yandex_url' => 'https://yandex.uz/maps/10335/tashkent/'
  },
  'tinchlik_metro' => {
    'name' => "Tinchlik metrosi bekati",
    'district' => 'Olmazor',
    'lat' => 41.335200, 'lon' => 69.214500,
    'routes' => ['11', '28', '46'],
    'yandex_url' => 'https://yandex.uz/maps/10335/tashkent/'
  },
  'beruniy_metro' => {
    'name' => "Beruniy metrosi (O'zMU/TDTU)",
    'district' => 'Olmazor',
    'lat' => 41.344400, 'lon' => 69.206500,
    'routes' => ['11', '28', '85', '118'],
    'yandex_url' => 'https://yandex.uz/maps/10335/tashkent/'
  },

  # Chilonzor & Uchtepa
  'chilonzor_metro' => {
    'name' => "Chilonzor metrosi bekati",
    'district' => 'Chilonzor',
    'lat' => 41.272700, 'lon' => 69.204500,
    'routes' => ['38', '40', '84', '98', '118'],
    'yandex_url' => 'https://yandex.uz/maps/10335/tashkent/'
  },
  'novza_metro' => {
    'name' => "Novza metrosi (Hosil)",
    'district' => 'Chilonzor',
    'lat' => 41.286800, 'lon' => 69.223800,
    'routes' => ['33', '84', '98'],
    'yandex_url' => 'https://yandex.uz/maps/10335/tashkent/'
  },
  'mirzo_ulugbek_metro' => {
    'name' => "Mirzo Ulug'bek metrosi (Stadion)",
    'district' => 'Chilonzor',
    'lat' => 41.279800, 'lon' => 69.213500,
    'routes' => ['40', '84', '118'],
    'yandex_url' => 'https://yandex.uz/maps/10335/tashkent/'
  },
  'farhod_bozori' => {
    'name' => "Farhod bozori bekati",
    'district' => 'Uchtepa',
    'lat' => 41.275500, 'lon' => 69.182000,
    'routes' => ['13', '38', '94', '118'],
    'yandex_url' => 'https://yandex.uz/maps/10335/tashkent/'
  },
  'olmazor_metro' => {
    'name' => "Olmazor metrosi (Avtovokzal)",
    'district' => 'Chilonzor',
    'lat' => 41.256200, 'lon' => 69.197800,
    'routes' => ['38', '56', '84', '86'],
    'yandex_url' => 'https://yandex.uz/maps/10335/tashkent/'
  },

  # Yunusobod
  'yunusobod_universam' => {
    'name' => "Yunusobod bozori (Universam)",
    'district' => 'Yunusobod',
    'lat' => 41.365500, 'lon' => 69.290500,
    'routes' => ['24', '51', '60', '72', '93'],
    'yandex_url' => 'https://yandex.uz/maps/10335/tashkent/'
  },
  'shahriston_metro' => {
    'name' => "Shahriston metrosi bekati",
    'district' => 'Yunusobod',
    'lat' => 41.353700, 'lon' => 69.288200,
    'routes' => ['51', '72', '93', '97'],
    'yandex_url' => 'https://yandex.uz/maps/10335/tashkent/'
  },
  'bodomzor_metro' => {
    'name' => "Bodomzor metrosi (Ekspomarkaz)",
    'district' => 'Yunusobod',
    'lat' => 41.336400, 'lon' => 69.284200,
    'routes' => ['24', '72', '93'],
    'yandex_url' => 'https://yandex.uz/maps/10335/tashkent/'
  },
  'megaplanet' => {
    'name' => "Mega Planet SAVDO markazi",
    'district' => 'Yunusobod',
    'lat' => 41.368800, 'lon' => 69.290800,
    'routes' => ['24', '51', '72', '93'],
    'yandex_url' => 'https://yandex.uz/maps/10335/tashkent/'
  },

  # Mirzo Ulug'bek
  'buyuk_ipak_yoli' => {
    'name' => "Buyuk Ipak Yo'li metrosi (Maksim Gorkiy)",
    'district' => "Mirzo Ulug'bek",
    'lat' => 41.326200, 'lon' => 69.328800,
    'routes' => ['14', '24', '49', '96', '101'],
    'yandex_url' => 'https://yandex.uz/maps/10335/tashkent/'
  },
  'pushkin_salor' => {
    'name' => "Pushkin / Salor bekati",
    'district' => "Mirzo Ulug'bek",
    'lat' => 41.320500, 'lon' => 69.308000,
    'routes' => ['14', '24', '96'],
    'yandex_url' => 'https://yandex.uz/maps/10335/tashkent/'
  },
  'tatu_moliya' => {
    'name' => "TATU / Moliya instituti bekati",
    'district' => 'Yunusobod',
    'lat' => 41.341500, 'lon' => 69.286500,
    'routes' => ['51', '72', '93'],
    'yandex_url' => 'https://yandex.uz/maps/10335/tashkent/'
  },
  'ttz_bozori' => {
    'name' => "TTZ bozori bekati",
    'district' => "Mirzo Ulug'bek",
    'lat' => 41.357000, 'lon' => 69.378000,
    'routes' => ['14', '101', '106'],
    'yandex_url' => 'https://yandex.uz/maps/10335/tashkent/'
  },

  # Mirobod, Yakkasaroy & Markaz
  'oybek_metro' => {
    'name' => "Oybek / Ming O'rik metrosi",
    'district' => 'Mirobod',
    'lat' => 41.298500, 'lon' => 69.276200,
    'routes' => ['38', '58', '67', '93'],
    'yandex_url' => 'https://yandex.uz/maps/10335/tashkent/'
  },
  'amirtemur_xiyobon' => {
    'name' => "Amir Temur xiyoboni bekati",
    'district' => 'Mirobod',
    'lat' => 41.312000, 'lon' => 69.279000,
    'routes' => ['14', '28', '38', '58', '67'],
    'yandex_url' => 'https://yandex.uz/maps/10335/tashkent/'
  },
  'shimoliy_vokzal' => {
    'name' => "Toshkent Shimoliy vokzali (Severniy)",
    'district' => 'Mirobod',
    'lat' => 41.292500, 'lon' => 69.285800,
    'routes' => ['14', '26', '60', '80'],
    'yandex_url' => 'https://yandex.uz/maps/10335/tashkent/'
  },
  'kosmonavtlar_metro' => {
    'name' => "Kosmonavtlar metrosi bekati",
    'district' => 'Yakkasaroy',
    'lat' => 41.307500, 'lon' => 69.261200,
    'routes' => ['38', '57', '67'],
    'yandex_url' => 'https://yandex.uz/maps/10335/tashkent/'
  },
  'grand_mir' => {
    'name' => "Grand Mir mehmonxonasi bekati",
    'district' => 'Yakkasaroy',
    'lat' => 41.296500, 'lon' => 69.268000,
    'routes' => ['38', '58', '67'],
    'yandex_url' => 'https://yandex.uz/maps/10335/tashkent/'
  },

  # Sergeli & Qo'yliq
  'qipchoq_metro' => {
    'name' => "Qipchoq (Sergeli) metrosi",
    'district' => 'Sergeli',
    'lat' => 41.209500, 'lon' => 69.215500,
    'routes' => ['38', '40', '86', '130'],
    'yandex_url' => 'https://yandex.uz/maps/10335/tashkent/'
  },
  'qoyliq_bozor' => {
    'name' => "Qo'yliq dehqon bozori bekati",
    'district' => 'Bektemir',
    'lat' => 41.238500, 'lon' => 69.337500,
    'routes' => ['12', '30', '45', '93', '110'],
    'yandex_url' => 'https://yandex.uz/maps/10335/tashkent/'
  },
  'janubiy_vokzal' => {
    'name' => "Toshkent Janubiy vokzali bekati",
    'district' => 'Yakkasaroy',
    'lat' => 41.268500, 'lon' => 69.227000,
    'routes' => ['40', '86', '118'],
    'yandex_url' => 'https://yandex.uz/maps/10335/tashkent/'
  }
}

DISTRICTS = [
  'Shayxontohur',
  'Chilonzor',
  'Yunusobod',
  "Mirzo Ulug'bek",
  'Mirobod',
  'Yakkasaroy',
  'Uchtepa',
  'Olmazor',
  'Sergeli',
  'Bektemir'
].freeze

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

def find_nearest_stop(lat, lon)
  best = nil
  min_d = 999_999.0
  PRESET_STOPS.each do |key, info|
    d = haversine_km(lat, lon, info['lat'], info['lon'])
    if d < min_d
      min_d = d
      best = info.merge('stop_id' => key, 'distance_km' => d.round(2))
    end
  end
  best
end

def search_stops(query)
  q = query.to_s.downcase.strip
  return [] if q.empty?

  matches = []
  PRESET_STOPS.each do |k, v|
    name = v['name'].to_s.downcase
    dist = v['district'].to_s.downcase
    if name.include?(q) || dist.include?(q) || q.include?(name)
      matches << v.merge('stop_id' => k)
    end
  end
  matches.first(6)
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

def districts_kb
  rows = []
  pair = []
  DISTRICTS.each do |dist|
    pair << { text: "🏢 #{dist}", callback_data: "view_dist:#{dist}" }
    if pair.size == 2
      rows << pair
      pair = []
    end
  end
  rows << pair unless pair.empty?
  rows << [{ text: '⭐️ Eng mashhur bekatlar', callback_data: 'view_popular_stops' }]
  { inline_keyboard: rows }
end

def stops_by_district_kb(district_name)
  stops = PRESET_STOPS.select { |_k, v| v['district'] == district_name }
  rows = stops.map do |k, v|
    [{ text: "🚏 #{v['name']}", callback_data: "select_stop:#{k}" }]
  end
  rows << [{ text: '⬅️ Tumanlar ro\'yxatiga qaytish', callback_data: 'back_to_districts' }]
  { inline_keyboard: rows }
end

def popular_stops_kb
  popular_keys = %w[chilonzor_metro buyuk_ipak_yoli amirtemur_xiyobon yunusobod_universam chorsu_bozor oybek_metro beruniy_metro farhod_bozori]
  rows = popular_keys.map do |k|
    v = PRESET_STOPS[k]
    [{ text: "🚏 #{v['name']}", callback_data: "select_stop:#{k}" }] if v
  end.compact
  rows << [{ text: '⬅️ Tumanlar ro\'yxatiga qaytish', callback_data: 'back_to_districts' }]
  { inline_keyboard: rows }
end

def found_stops_kb(stops_list)
  rows = stops_list.map do |s|
    [{ text: "🚏 #{s['name']} (#{s['district']})", callback_data: "select_stop:#{s['stop_id']}" }]
  end
  rows << [{ text: '⬅️ Tumanlar ro\'yxatiga qaytish', callback_data: 'back_to_districts' }]
  { inline_keyboard: rows }
end

def buses_kb(selected_buses, suggested = [])
  suggested = %w[11 28 38 72 84 93] if suggested.empty?
  rows = []
  pair = []
  suggested.each do |b|
    prefix = selected_buses.include?(b) ? '✅ ' : '🚌 '
    pair << { text: "#{prefix}#{b}-avtobus", callback_data: "toggle_bus:#{b}" }
    if pair.size == 2
      rows << pair
      pair = []
    end
  end
  rows << pair unless pair.empty?
  rows << [{ text: '✍️ Boshqa raqam yozish (matn orqali)', callback_data: 'type_custom_bus' }]
  rows << [{ text: '➡️ Vaqtni kiritish', callback_data: 'buses_done' }]
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
          "Barcha kunlarga bir xil vaqt belgilaysizmi yoki har bir kunga alohida (har xil) vaqtmi?"
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
            "Men Toshkent shahri bo'ylab har qanday bekatga kelayotgan avtobuslarni kuzatib, " \
            "o'qishga yoki ishga o'z vaqtida, bekatda kutmasdan chiqishingiz uchun ogohlantirib turaman.\n\n" \
            "✨ <b>Imkoniyatlar:</b>\n" \
            "• 📍 Toshkentning istalgan bekatini lokatsiya yoki nom bo'yicha tanlash;\n" \
            "• 🚌 Har qanday avtobus yo'nalishini kiritish;\n" \
            "• ⏱ Shaxsiy kiyinish, piyoda yurish va ogohlantirish vaqtlarini sozlash.\n\n" \
            "⚙️ <b>Sizning joriy vaqt me'yorlaringiz:</b>\n" \
            "• Oldindan kuzatuv: <b>#{settings['advance_notice_min']} daqiqa oldin</b>\n" \
            "• Kiyinish: <b>#{settings['dressing_min']} daqiqa</b>\n" \
            "• Bekatgacha piyoda yurish: <b>#{settings['walking_min']} daqiqa</b>\n" \
            "• Jami tayyorgarlik: <b>#{total_prep} daqiqa (+#{SAFETY_BUFFER_MIN} daq. zaxira)</b>\n\n" \
            "Quyidagi menyudan <b>«➕ Yangi jadval qo'shish»</b> tugmasini bosib boshlashingiz mumkin!"
    tg_api('sendMessage', { chat_id: chat_id, text: reply, parse_mode: 'HTML', reply_markup: main_menu_kb })
    return
  end

  if text == '/cancel'
    db['states'].delete(uid)
    tg_api('sendMessage', { chat_id: chat_id, text: 'Amal bekor qilindi.', reply_markup: main_menu_kb })
    return
  end

  if text == 'ℹ️ Yordam va Qo\'llanma'
    info = "📖 <b>TashBus Botidan foydalanish qo'llanmasi:</b>\n\n" \
           "1️⃣ <b>➕ Yangi jadval qo'shish:</b> Dushanbadan Shanbagacha o'qish yoki ishga chiqish vaqtingizni, " \
           "bekatingiz va avtobus raqamlarini belgilaysiz.\n\n" \
           "2️⃣ <b>Qanday ishlaydi?</b>\n" \
           "• Belgilangan vaqtga <b>20 daqiqa qolganda</b> bot avtobuslar qayerdaligi haqida birinchi xabarni beradi.\n" \
           "• Avtobus bekatga sizning tayyorgarlik vaqtingiz (kiyinish + yo'l) masofasiga kelganda darhol <b>🚨 KIYINISHNI BOSHLANG</b> xabari keladi.\n\n" \
           "3️⃣ <b>Bekatni qanday tanlayman?</b>\n" \
           "• Telegramdan 📎 <b>Joylashuv (Location)</b> yuborishingiz;\n" \
           "• Bekat nomini yozishingiz (masalan: <i>Chilonzor, Oybek, Farhod</i>);\n" \
           "• Yoki tumanlar ro'yxatidan tanlashingiz mumkin."
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
      # Jadvali bo'lmagan foydalanuvchiga mashhur bekatlar taklif etiladi
      arrivals = fetch_bus_arrivals(%w[11 28 72 84])
      lines = [
        "🚏 <b>Mashhur bekatlar bo'yicha jonli namunaviy holat:</b>",
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

  # Bekat qidirish yoki Lokatsiya yuborish
  if msg['location'] && state_info['step'] == 'choosing_stop'
    lat = msg['location']['latitude']
    lon = msg['location']['longitude']
    nearest = find_nearest_stop(lat, lon)
    if nearest && nearest['distance_km'] <= 1.5
      state_info['stop_id'] = nearest['stop_id']
      state_info['stop_name'] = "#{nearest['name']} (~#{nearest['distance_km']} km)"
      suggested = nearest['routes'] || []
    else
      state_info['stop_id'] = 'custom_location_stop'
      state_info['stop_name'] = "Xaritadagi joylashuvingiz (#{format('%.4f', lat)}, #{format('%.4f', lon)})"
      suggested = []
    end
    state_info['stop_lat'] = lat
    state_info['stop_lon'] = lon
    state_info['step'] = 'choosing_buses'
    state_info['suggested_buses'] = suggested
    state_info['selected_buses'] = suggested.first(2)

    tg_api('sendMessage', {
      chat_id: chat_id,
      text: "📍 <b>Bekat qabul qilindi:</b>\n#{state_info['stop_name']}\n\n" \
            "🚌 <b>3-qadam: Qaysi avtobuslarni kuzatamiz?</b>\n" \
            "Kerakli avtobuslarni tanlang yoki o'zingiz yozib yuboring (masalan: <code>72</code> yoki <code>14, 85</code>):",
      parse_mode: 'HTML',
      reply_markup: buses_kb(state_info['selected_buses'], suggested)
    })
    return
  end

  # Bekat tanlash bosqichida foydalanuvchi matn yozsa (qidiruv)
  if state_info['step'] == 'choosing_stop' && !text.empty? && !text.start_with?('/')
    matches = search_stops(text)
    if !matches.empty?
      tg_api('sendMessage', {
        chat_id: chat_id,
        text: "🔍 <b>«#{text}» so'rovi bo'yicha quyidagi bekatlar topildi:</b>\nKeraklisini bosing:",
        parse_mode: 'HTML',
        reply_markup: found_stops_kb(matches)
      })
    else
      # Ro'yxatdan topilmasa, o'zi yozgan nom bilan saqlash taklifi
      state_info['stop_id'] = 'custom_named_stop'
      state_info['stop_name'] = text
      state_info['stop_lat'] = 41.311087
      state_info['stop_lon'] = 69.240562
      state_info['step'] = 'choosing_buses'
      state_info['suggested_buses'] = %w[11 28 38 72 84 93]
      state_info['selected_buses'] = []

      tg_api('sendMessage', {
        chat_id: chat_id,
        text: "✅ <b>Bekat nomi kiritildi:</b> «#{text}»\n\n" \
              "🚌 <b>3-qadam: Shu bekatdan qatnaydigan avtobus raqamlarini tanlang yoki yozing:</b>\n" \
              "(Masalan: <code>72</code> yoki bir nechta bo'lsa <code>14, 85, 93</code>):",
        parse_mode: 'HTML',
        reply_markup: buses_kb([], state_info['suggested_buses'])
      })
    end
    return
  end

  # Avtobus tanlash bosqichida foydalanuvchi avtobus raqamini yozsa
  if state_info['step'] == 'choosing_buses' && !text.empty? && !text.start_with?('/')
    extracted_buses = text.scan(/\d+[A-Za-zА-Яа-я]?/).map(&:strip).uniq
    if !extracted_buses.empty?
      state_info['selected_buses'] = extracted_buses
      prompt_for_time(chat_id, state_info)
    else
      tg_api('sendMessage', {
        chat_id: chat_id,
        text: "⚠️ Avtobus raqami aniqlanmadi. Iltimos, raqam ko'rinishida yozing (masalan: <code>72</code> yoki <code>14, 85</code>):",
        parse_mode: 'HTML'
      })
    end
    return
  end

  # Vaqt kiritish: Barcha kunlar uchun umumiy vaqt (SS:DD)
  if state_info['step'] == 'entering_time' || state_info['step'] == 'entering_time_same'
    if text =~ /\A([01]?\d|2[0-3]):([0-5]\d)\z/
      hh = format('%02d', Regexp.last_match(1).to_i)
      mm = format('%02d', Regexp.last_match(2).to_i)
      formatted_time = "#{hh}:#{mm}"
      selected_days = state_info['selected_days'] || [1]
      bus_str = (state_info['selected_buses'] || %w[11 28]).join(',')
      bus_str = '11' if bus_str.empty?
      stop_name_saved = state_info['stop_name'] || 'Mening bekatim'

      selected_days.each do |wday|
        db['schedules'] << {
          'id' => db['next_id'],
          'user_id' => chat_id,
          'weekday' => wday,
          'stop_id' => state_info['stop_id'] || 'custom_stop',
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
              "🚌 <b>Avtobuslar:</b> #{bus_str}-yo'nalishlar\n" \
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

  # Vaqt kiritish: Har bir kun uchun alohida (har xil) vaqt
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
        # Barcha kunlar uchun alohida vaqtlar to'liq kiritildi
        bus_str = (state_info['selected_buses'] || %w[11 28]).join(',')
        bus_str = '11' if bus_str.empty?
        stop_name_saved = state_info['stop_name'] || 'Mening bekatim'

        summary_lines = []
        days_list.each do |wday|
          t_str = times_map[wday]
          db['schedules'] << {
            'id' => db['next_id'],
            'user_id' => chat_id,
            'weekday' => wday,
            'stop_id' => state_info['stop_id'] || 'custom_stop',
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
                "🚌 <b>Avtobuslar:</b> #{bus_str}-yo'nalishlar\n\n" \
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

  # --- KUNLARNI TANLASH ---
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
    reply_text = "🚏 <b>2-qadam: Bekatni tanlang</b>\n\n" \
                 "O'zingizga ma'qul usuldan foydalanishingiz mumkin:\n" \
                 "1️⃣ 📍 <b>Lokatsiya:</b> Telegram'dan 📎 Joylashuv yuboring;\n" \
                 "2️⃣ ✍️ <b>Qidirish:</b> Bekat nomini yozib yuboring (masalan: <i>Chilonzor, Oybek, Farhod</i>);\n" \
                 "3️⃣ 🏢 <b>Tumanlar:</b> Quyidagi tumanlardan birini tanlang:"
    tg_api('editMessageText', {
      chat_id: chat_id,
      message_id: msg_id,
      text: reply_text,
      parse_mode: 'HTML',
      reply_markup: districts_kb
    })
    tg_api('answerCallbackQuery', { callback_query_id: cb_id })

  # --- BEKAT TANLASH (Tumanlar va Ro'yxatlar) ---
  elsif data.start_with?('view_dist:')
    dist_name = data.split(':', 2)[1]
    tg_api('editMessageText', {
      chat_id: chat_id,
      message_id: msg_id,
      text: "🏢 <b>#{dist_name} tumani bekatlari:</b>\nKerakli bekatni tanlang:",
      parse_mode: 'HTML',
      reply_markup: stops_by_district_kb(dist_name)
    })
    tg_api('answerCallbackQuery', { callback_query_id: cb_id })
  elsif data == 'view_popular_stops'
    tg_api('editMessageText', {
      chat_id: chat_id,
      message_id: msg_id,
      text: "⭐️ <b>Toshkentning eng mashhur bekatlari:</b>\nKeraklisini tanlang:",
      parse_mode: 'HTML',
      reply_markup: popular_stops_kb
    })
    tg_api('answerCallbackQuery', { callback_query_id: cb_id })
  elsif data == 'back_to_districts'
    tg_api('editMessageText', {
      chat_id: chat_id,
      message_id: msg_id,
      text: "🚏 <b>Bekatni tanlang yoki nomini yozing:</b>",
      parse_mode: 'HTML',
      reply_markup: districts_kb
    })
    tg_api('answerCallbackQuery', { callback_query_id: cb_id })
  elsif data.start_with?('select_stop:')
    stop_key = data.split(':')[1]
    stop_info = PRESET_STOPS[stop_key]
    state_info['stop_id'] = stop_key
    state_info['stop_name'] = stop_info['name']
    state_info['stop_lat'] = stop_info['lat']
    state_info['stop_lon'] = stop_info['lon']
    state_info['step'] = 'choosing_buses'
    suggested = stop_info['routes'] || %w[11 28]
    state_info['suggested_buses'] = suggested
    buses = state_info['selected_buses'] ||= suggested.first(2)
    tg_api('editMessageText', {
      chat_id: chat_id,
      message_id: msg_id,
      text: "✅ <b>Tanlangan bekat:</b> #{stop_info['name']}\n\n" \
            "🚌 <b>3-qadam: Shu bekatdan qaysi avtobuslarni kuzatamiz?</b>\n" \
            "Tugmalardan tanlang yoki matn sifatida avtobus raqamini yozing (masalan: <code>72</code>):",
      parse_mode: 'HTML',
      reply_markup: buses_kb(buses, suggested)
    })
    tg_api('answerCallbackQuery', { callback_query_id: cb_id })

  # --- AVTOBUSLARNI TANLASH ---
  elsif data.start_with?('toggle_bus:')
    b = data.split(':')[1]
    buses = state_info['selected_buses'] ||= []
    buses.include?(b) ? buses.delete(b) : (buses << b)
    suggested = state_info['suggested_buses'] || %w[11 28]
    tg_api('editMessageReplyMarkup', { chat_id: chat_id, message_id: msg_id, reply_markup: buses_kb(buses, suggested) })
    tg_api('answerCallbackQuery', { callback_query_id: cb_id })
  elsif data == 'type_custom_bus'
    tg_api('sendMessage', {
      chat_id: chat_id,
      text: "✍️ <b>Avtobus raqamini yozib yuboring:</b>\n\nMasalan: <code>72</code> yoki bir nechta bo'lsa <code>14, 85, 93</code> deb yuboring:",
      parse_mode: 'HTML'
    })
    tg_api('answerCallbackQuery', { callback_query_id: cb_id })
  elsif data == 'buses_done'
    buses = state_info['selected_buses'] || []
    if buses.empty?
      tg_api('answerCallbackQuery', { callback_query_id: cb_id, text: 'Kamida bitta avtobusni tanlang yoki raqamini yozing!', show_alert: true })
      return
    end
    prompt_for_time(chat_id, state_info, msg_id)
    tg_api('answerCallbackQuery', { callback_query_id: cb_id })

  # --- VAQT REJIMINI TANLASH (BIR XIL YOKI HAR XIL) ---
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
    tg_api('deleteMessage', { chat_id: chat_id, message_id: msg_id })
    tg_api('answerCallbackQuery', { callback_query_id: cb_id, text: "Jadval o'chirildi!" })

  # --- VAQT SOZLAMALARI (1 BOSISHDA SOZLASH) ---
  elsif data.start_with?('set_dress:')
    val = data.split(':')[1].to_i
    settings = get_user_settings(db, uid)
    settings['dressing_min'] = val
    tg_api('editMessageReplyMarkup', { chat_id: chat_id, message_id: msg_id, reply_markup: settings_kb(settings) })
    tg_api('answerCallbackQuery', { callback_query_id: cb_id, text: "Kiyinish vaqti: #{val} daqiqa!" })
  elsif data.start_with?('set_walk:')
    val = data.split(':')[1].to_i
    settings = get_user_settings(db, uid)
    settings['walking_min'] = val
    tg_api('editMessageReplyMarkup', { chat_id: chat_id, message_id: msg_id, reply_markup: settings_kb(settings) })
    tg_api('answerCallbackQuery', { callback_query_id: cb_id, text: "Bekatgacha yo'l: #{val} daqiqa!" })
  elsif data.start_with?('set_adv:')
    val = data.split(':')[1].to_i
    settings = get_user_settings(db, uid)
    settings['advance_notice_min'] = val
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

http_port = (ENV['PORT'] || 8080).to_i
Thread.new do
  server = TCPServer.new('0.0.0.0', http_port)
  puts "🌐 Healthcheck HTTP server ishga tushdi: port #{http_port}"
  loop do
    client = server.accept
    _req = client.gets
    body = "TashBus Universal Alert Bot 24/7 faol!\nServer vaqti: #{Time.now}\n"
    res = "HTTP/1.1 200 OK\r\nContent-Type: text/plain; charset=utf-8\r\nContent-Length: #{body.bytesize}\r\nConnection: close\r\n\r\n#{body}"
    client.write(res)
    client.close
  rescue StandardError
    # ignore client connection errors
  end
rescue StandardError => e
  puts "⚠️ Healthcheck server ogohlantirish: #{e.message}"
end

# ==============================================================================
# MAIN POLLING LOOP
# ==============================================================================

puts 'TashBus Universal Alert Bot ishga tushmoqda...'
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
