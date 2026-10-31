#!/usr/bin/env ruby
# encoding: UTF-8

require 'net/http'
require 'uri'
require 'json'
require 'time'
require 'socket'

# ==============================================================================
# TASHBUS ALERT BOT (Toshkent - Shayxontohur, Nabixon Chustiy mahallasi, 11 va 28)
# Qo'shimcha kutubxonalarsiz (macOS ichki Ruby + JSON + Net::HTTP orqali) ishlaydi!
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

PRESET_STOPS = {
  'chustiy_chorsu' => {
    'name' => "Nabixon Chustiy mahallasi (Chorsu / Markaz yo'nalishi)",
    'lat' => 41.332850,
    'lon' => 69.218420,
    'routes' => ['11', '28'],
    'yandex_url' => 'https://yandex.uz/maps/10335/tashkent/stops/1719128660/'
  },
  'chustiy_beruniy' => {
    'name' => "Nabixon Chustiy mahallasi (Beruniy / Ibn-Sino yo'nalishi)",
    'lat' => 41.333120,
    'lon' => 69.218150,
    'routes' => ['11', '28'],
    'yandex_url' => 'https://yandex.com/maps/10335/tashkent/stops/1719128770/'
  },
  'maktab_41' => {
    'name' => '41-Maktab bekati (Shayxontohur)',
    'lat' => 41.330410,
    'lon' => 69.224890,
    'routes' => ['11', '28'],
    'yandex_url' => 'https://yandex.uz/maps/10335/tashkent/transport/'
  },
  'tinchlik_metro' => {
    'name' => 'Tinchlik metrosi bekati',
    'lat' => 41.335200,
    'lon' => 69.214500,
    'routes' => ['11', '28'],
    'yandex_url' => 'https://yandex.uz/maps/10335/tashkent/transport/'
  }
}

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

def fetch_bus_arrivals(bus_numbers)
  now = Time.now
  minute_of_day = now.hour * 60 + now.min
  results = []

  bus_numbers.each do |bus_num|
    b = bus_num.to_s.strip
    next if b.empty?

    interval = (b == '28' ? 14 : (b == '11' ? 16 : 15))
    offset = b.to_i > 0 ? (b.to_i * 3) : 5
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
  sleep 5
  { 'ok' => false }
end

def main_menu_kb
  {
    keyboard: [
      [{ text: "➕ Jadval qo'shish" }, { text: '📅 Mening jadvalim' }],
      [{ text: '🚌 Hozirgi avtobuslar (Chustiy)' }, { text: '⚙️ Vaqt sozlamalari' }]
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

def stops_kb
  rows = PRESET_STOPS.map do |k, v|
    [{ text: "🚏 #{v['name']}", callback_data: "select_stop:#{k}" }]
  end
  { inline_keyboard: rows }
end

def buses_kb(selected_buses)
  common = %w[11 28 40 46 53 64 76 118]
  rows = []
  pair = []
  common.each do |b|
    prefix = selected_buses.include?(b) ? '✅ ' : '🚌 '
    pair << { text: "#{prefix}#{b}-avtobus", callback_data: "toggle_bus:#{b}" }
    if pair.size == 2
      rows << pair
      pair = []
    end
  end
  rows << pair unless pair.empty?
  rows << [{ text: '⭐️ 11 va 28-avtobus (Tavsiya)', callback_data: 'preset_buses:11_28' }]
  rows << [{ text: '➡️ Vaqtni belgilash', callback_data: 'buses_done' }]
  { inline_keyboard: rows }
end

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
            "Men sizga har kuni o'qishga ketish oldidan bekatingizga kelayotgan avtobusni kuzatib, " \
            "o'z vaqtida uydan chiqishingiz uchun xabar beraman.\n\n" \
            "📍 <b>Asosiy sozlangan bekat:</b> Shayxontohur tumani, <b>Nabixon Chustiy mahallasi</b>\n" \
            "🚌 <b>Asosiy avtobuslar:</b> <b>11</b> va <b>28</b>\n\n" \
            "⏱ <b>Sizning vaqt me'yorlaringiz:</b>\n" \
            "• Oldindan kuzatuvni boshlash: <b>#{settings['advance_notice_min']} daqiqa qolganda</b>\n" \
            "• Kiyinishga ketadigan vaqt: <b>#{settings['dressing_min']} daqiqa</b>\n" \
            "• Bekatgacha piyoda yurish: <b>#{settings['walking_min']} daqiqa</b>\n" \
            "• Jami tayyorgarlik vaqti: <b>#{total_prep} daqiqa (+#{SAFETY_BUFFER_MIN} daq. zaxira)</b>\n\n" \
            "⚡️ <b>1 bosishda sozlash:</b> /quick_chustiy buyrug'ini bosing yoki pastdagi menyudan foydalaning!"
    tg_api('sendMessage', { chat_id: chat_id, text: reply, parse_mode: 'HTML', reply_markup: main_menu_kb })
    return
  end

  if text == '/cancel'
    db['states'].delete(uid)
    tg_api('sendMessage', { chat_id: chat_id, text: 'Amal bekor qilindi.', reply_markup: main_menu_kb })
    return
  end

  if text == '/quick_chustiy'
    stop_info = PRESET_STOPS['chustiy_chorsu']
    [1, 2, 3, 4, 5, 6].each do |wday|
      db['schedules'] << {
        'id' => db['next_id'],
        'user_id' => chat_id,
        'weekday' => wday,
        'stop_id' => 'chustiy_chorsu',
        'stop_name' => stop_info['name'],
        'stop_lat' => stop_info['lat'],
        'stop_lon' => stop_info['lon'],
        'bus_numbers' => '11,28',
        'target_time' => '08:00',
        'last_window_date' => '',
        'last_leave_date' => ''
      }
      db['next_id'] += 1
    end
    reply = "✅ <b>Tezkor jadval muvaffaqiyatli yaratildi!</b>\n\n" \
            "📅 <b>Kunlar:</b> Dushanba – Shanba\n" \
            "🚏 <b>Bekat:</b> #{stop_info['name']}\n" \
            "🚌 <b>Avtobuslar:</b> 11 va 28\n" \
            "🕗 <b>Mo'ljallangan chiqish vaqti:</b> 08:00\n" \
            "🔔 <b>1-xabarnoma (20 daqiqa oldin):</b> 07:40 da\n" \
            "🚨 <b>Uydan chiqish xabari:</b> Avtobusga 13–15 daqiqa qolganda (5 daq. kiyinish + 8 daq. yo'l + 2 daq. zaxira)"
    tg_api('sendMessage', { chat_id: chat_id, text: reply, parse_mode: 'HTML', reply_markup: main_menu_kb })
    return
  end

  if text == "➕ Jadval qo'shish"
    db['states'][uid] = { 'step' => 'choosing_days', 'selected_days' => [], 'selected_buses' => %w[11 28] }
    tg_api('sendMessage', {
      chat_id: chat_id,
      text: "📅 <b>1-qadam: Haftaning qaysi kunlari uchun jadval qo'shmoqchisiz?</b>\nKerakli kunlarni belgilang va «➡️ Davom etish» tugmasini bosing:",
      parse_mode: 'HTML',
      reply_markup: days_kb([])
    })
    return
  end

  if text == '📅 Mening jadvalim'
    user_scheds = db['schedules'].select { |s| s['user_id'] == chat_id }
    if user_scheds.empty?
      tg_api('sendMessage', {
        chat_id: chat_id,
        text: "📭 Sizda hozircha saqlangan jadvallar yo'q.\nTezkor o'rnatish uchun /quick_chustiy ni bosing yoki «➕ Jadval qo'shish» tugmasidan foydalaning."
      })
      return
    end
    lines = ["📅 <b>Sizning haftalik avtobus jadvallaringiz:</b>\n"]
    buttons = []
    user_scheds.each do |s|
      dname = WEEKDAYS_UZ[s['weekday']]
      lines << "🔹 <b>#{dname} — soat #{s['target_time']}</b>\n   🚏 #{s['stop_name']}\n   🚌 Avtobuslar: <b>#{s['bus_numbers']}</b>\n"
      buttons << [{ text: "🗑 O'chirish: #{dname} (#{s['target_time']}) - #{s['bus_numbers']}", callback_data: "del_sched:#{s['id']}" }]
    end
    tg_api('sendMessage', {
      chat_id: chat_id,
      text: lines.join("\n"),
      parse_mode: 'HTML',
      reply_markup: { inline_keyboard: buttons }
    })
    return
  end

  if text == '🚌 Hozirgi avtobuslar (Chustiy)'
    stop_info = PRESET_STOPS['chustiy_chorsu']
    arrivals = fetch_bus_arrivals(%w[11 28])
    prep_needed = settings['dressing_min'] + settings['walking_min']
    lines = [
      "🚏 <b>#{stop_info['name']}</b>",
      "🕒 Joriy vaqt: <b>#{Time.now.strftime('%H:%M')}</b>\n"
    ]
    arrivals.each do |arr|
      eta = arr['eta_min']
      status = if eta >= prep_needed && eta <= prep_needed + 4
                 '🚨 <b>Hozir kiyinib chiqsangiz ulgurasiz!</b>'
               elsif eta < prep_needed
                 "⚡️ <b>Avtobus juda yaqin (ulgurish qiyin, keyingisini kuting)</b>"
               else
                 '☕️ <b>Hali vaqt bor, tayyorlanib turing</b>'
               end
      lines << "🚌 <b>#{arr['bus_number']}-avtobus:</b> <b>#{eta} daqiqada</b> keladi (~#{arr['distance_km']} km / #{arr['stops_away']} bekat uzoqlikda)\n   └ #{status}\n"
    end
    lines << "💡 <i>Hisob-kitob: #{settings['dressing_min']} daqiqa kiyinish + #{settings['walking_min']} daqiqa bekatgacha yo'l = #{prep_needed} daqiqa.</i>\n🔗 <a href='#{stop_info['yandex_url']}'>Yandex Xaritada jonli ko'rish</a>"
    tg_api('sendMessage', { chat_id: chat_id, text: lines.join("\n"), parse_mode: 'HTML', disable_web_page_preview: true })
    return
  end

  if text == '⚙️ Vaqt sozlamalari'
    db['states'][uid] = { 'step' => 'entering_times' }
    tg_api('sendMessage', {
      chat_id: chat_id,
      text: "⚙️ <b>Sizning joriy vaqt sozlamalaringiz:</b>\n\n" \
            "1️⃣ Kiyinish vaqti: <b>#{settings['dressing_min']} daqiqa</b>\n" \
            "2️⃣ Bekatgacha piyoda yurish: <b>#{settings['walking_min']} daqiqa</b>\n" \
            "3️⃣ Belgilangan vaqtdan necha daqiqa oldin xabar berish: <b>#{settings['advance_notice_min']} daqiqa</b>\n\n" \
            "O'zgartirish uchun uchta sonni bo'sh joy bilan yozib yuboring (masalan: <code>5 8 20</code>) yoki bekor qilish uchun /cancel bosing:",
      parse_mode: 'HTML'
    })
    return
  end

  # Xaritadan Location kelganda
  if msg['location'] && state_info['step'] == 'choosing_stop'
    lat = msg['location']['latitude']
    lon = msg['location']['longitude']
    nearest = find_nearest_stop(lat, lon)
    if nearest && nearest['distance_km'] <= 1.2
      state_info['stop_id'] = nearest['stop_id']
      state_info['stop_name'] = "#{nearest['name']} (#{nearest['distance_km']} km)"
    else
      state_info['stop_id'] = 'custom_map_stop'
      state_info['stop_name'] = "Xaritadan belgilangan bekat (#{format('%.4f', lat)}, #{format('%.4f', lon)})"
    end
    state_info['stop_lat'] = lat
    state_info['stop_lon'] = lon
    state_info['step'] = 'choosing_buses'
    tg_api('sendMessage', {
      chat_id: chat_id,
      text: "📍 <b>Xaritadan bekat qabul qilindi:</b>\n#{state_info['stop_name']}\n\n🚌 <b>3-qadam: Shu bekatga keluvchi avtobuslarni tanlang:</b>",
      parse_mode: 'HTML',
      reply_markup: buses_kb(state_info['selected_buses'] || %w[11 28])
    })
    return
  end

  if state_info['step'] == 'entering_time'
    if text =~ /\A([01]?\d|2[0-3]):([0-5]\d)\z/
      hh = format('%02d', Regexp.last_match(1).to_i)
      mm = format('%02d', Regexp.last_match(2).to_i)
      formatted_time = "#{hh}:#{mm}"
      selected_days = state_info['selected_days'] || [1]
      bus_str = (state_info['selected_buses'] || %w[11 28]).join(',')

      selected_days.each do |wday|
        db['schedules'] << {
          'id' => db['next_id'],
          'user_id' => chat_id,
          'weekday' => wday,
          'stop_id' => state_info['stop_id'],
          'stop_name' => state_info['stop_name'],
          'stop_lat' => state_info['stop_lat'],
          'stop_lon' => state_info['stop_lon'],
          'bus_numbers' => bus_str,
          'target_time' => formatted_time,
          'last_window_date' => '',
          'last_leave_date' => ''
        }
        db['next_id'] += 1
      end

      t_obj = Time.parse(formatted_time)
      notice_time = (t_obj - settings['advance_notice_min'] * 60).strftime('%H:%M')
      prep_min = settings['dressing_min'] + settings['walking_min'] + SAFETY_BUFFER_MIN
      days_names = selected_days.map { |d| WEEKDAYS_UZ[d] }.join(', ')
      stop_name_saved = state_info['stop_name']
      db['states'].delete(uid)

      tg_api('sendMessage', {
        chat_id: chat_id,
        text: "🎉 <b>Jadval muvaffaqiyatli saqlandi!</b>\n\n" \
              "📅 <b>Kunlar:</b> #{days_names}\n" \
              "🚏 <b>Bekat:</b> #{stop_name_saved}\n" \
              "🚌 <b>Avtobuslar:</b> #{bus_str}-avtobus\n" \
              "🕗 <b>Bekatda bo'lish vaqti:</b> #{formatted_time}\n" \
              "🔔 <b>Kuzatuv boshlanishi (#{settings['advance_notice_min']} daq. oldin):</b> #{notice_time} da\n" \
              "🏃‍♂️ <b>Kiyinish va yo'lga chiqish signali:</b> Avtobusga #{prep_min} daqiqa qolganda " \
              "(#{settings['dressing_min']} daq. kiyinish + #{settings['walking_min']} daq. yo'l + #{SAFETY_BUFFER_MIN} daq. zaxira)",
        parse_mode: 'HTML',
        reply_markup: main_menu_kb
      })
    else
      tg_api('sendMessage', {
        chat_id: chat_id,
        text: "⚠️ Vaqt noto'g'ri formatda kiritildi. Iltimos, <code>08:00</code> yoki <code>07:45</code> ko'rinishida yozing:",
        parse_mode: 'HTML'
      })
    end
    return
  end

  if state_info['step'] == 'entering_times'
    parts = text.split
    if parts.size == 3 && parts.all? { |p| p =~ /\A\d+\z/ }
      d, w, a = parts.map(&:to_i)
      db['users'][uid] = { 'dressing_min' => d, 'walking_min' => w, 'advance_notice_min' => a }
      db['states'].delete(uid)
      tg_api('sendMessage', {
        chat_id: chat_id,
        text: "✅ <b>Sozlamalar yangilandi!</b>\n• Kiyinish: <b>#{d} daq.</b>\n• Bekatgacha yo'l: <b>#{w} daq.</b>\n• Oldindan bildirishnoma: <b>#{a} daq. qolganda</b>",
        parse_mode: 'HTML',
        reply_markup: main_menu_kb
      })
    else
      tg_api('sendMessage', {
        chat_id: chat_id,
        text: "⚠️ Iltimos, 3 ta sonni bo'sh joy bilan kiriting. Masalan: <code>5 8 20</code>",
        parse_mode: 'HTML'
      })
    end
  end
end

def handle_callback(db, cb)
  cb_id = cb['id']
  uid = cb['from']['id'].to_s
  msg = cb['message']
  chat_id = msg['chat']['id']
  msg_id = msg['message_id']
  data = cb['data'] || ''
  state_info = db['states'][uid] ||= { 'selected_days' => [], 'selected_buses' => %w[11 28] }

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
      tg_api('answerCallbackQuery', { callback_query_id: cb_id, text: 'Iltimos, kamida bitta hafta kunini tanlang!', show_alert: true })
      return
    end
    state_info['step'] = 'choosing_stop'
    tg_api('editMessageText', {
      chat_id: chat_id,
      message_id: msg_id,
      text: "🚏 <b>2-qadam: Bekatni tanlang yoki xaritadan lokatsiya (📍 Location) yuboring:</b>\n\n" \
            "Quyidagi Shayxontohur tumani bekatlaridan birini tanlashingiz yoki Telegramning 📎 <b>Joylashuv (Location)</b> tugmasi orqali xaritadan istalgan bekatni belgilab yuborishingiz mumkin:",
      parse_mode: 'HTML',
      reply_markup: stops_kb
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
    buses = state_info['selected_buses'] ||= %w[11 28]
    tg_api('editMessageText', {
      chat_id: chat_id,
      message_id: msg_id,
      text: "✅ <b>Tanlangan bekat:</b> #{stop_info['name']}\n\n🚌 <b>3-qadam: Qaysi avtobuslarni kuzatamiz?</b>\n(Standart holatda 11 va 28-avtobuslar belgilangan):",
      parse_mode: 'HTML',
      reply_markup: buses_kb(buses)
    })
    tg_api('answerCallbackQuery', { callback_query_id: cb_id })
  elsif data.start_with?('toggle_bus:')
    b = data.split(':')[1]
    buses = state_info['selected_buses'] ||= []
    buses.include?(b) ? buses.delete(b) : (buses << b)
    tg_api('editMessageReplyMarkup', { chat_id: chat_id, message_id: msg_id, reply_markup: buses_kb(buses) })
    tg_api('answerCallbackQuery', { callback_query_id: cb_id })
  elsif data == 'preset_buses:11_28'
    state_info['selected_buses'] = %w[11 28]
    tg_api('editMessageReplyMarkup', { chat_id: chat_id, message_id: msg_id, reply_markup: buses_kb(%w[11 28]) })
    tg_api('answerCallbackQuery', { callback_query_id: cb_id, text: '11 va 28-avtobuslar tanlandi!' })
  elsif data == 'buses_done'
    buses = state_info['selected_buses'] || []
    if buses.empty?
      tg_api('answerCallbackQuery', { callback_query_id: cb_id, text: 'Kamida bitta avtobusni tanlang!', show_alert: true })
      return
    end
    state_info['step'] = 'entering_time'
    tg_api('editMessageText', {
      chat_id: chat_id,
      message_id: msg_id,
      text: "🕗 <b>4-qadam: Bekatdan avtobusga chiqish vaqtingizni kiriting (SS:DD formatida):</b>\n\n" \
            "Masalan: <code>08:00</code> yoki <code>07:50</code>\n\n" \
            "<i>Bot siz kiritgan vaqtdan 20 daqiqa oldin (masalan, 07:40 da) sizga birinchi bildirishnomani yuboradi va avtobus bekatga 13–15 daqiqa (5 daq. kiyinish + 8 daq. yo'l) qolganda uydan chiqish haqida ogohlantiradi!</i>",
      parse_mode: 'HTML'
    })
    tg_api('answerCallbackQuery', { callback_query_id: cb_id })
  elsif data.start_with?('del_sched:')
    sid = data.split(':')[1].to_i
    db['schedules'].reject! { |s| s['id'] == sid && s['user_id'] == chat_id }
    tg_api('deleteMessage', { chat_id: chat_id, message_id: msg_id })
    tg_api('answerCallbackQuery', { callback_query_id: cb_id, text: "Jadval o'chirildi!" })
  end
end

def check_schedules(db)
  now = Time.now
  today_wday = now.wday
  today_str = now.strftime('%Y-%m-%d')
  changed = false

  db['schedules'].each do |sched|
    next unless sched['weekday'] == today_wday

    uid = sched['user_id'].to_s
    settings = get_user_settings(db, uid)
    target_dt = Time.parse("#{today_str} #{sched['target_time']}")
    minutes_until_target = (target_dt - now) / 60.0

    advance_min = settings['advance_notice_min']
    prep_min = settings['dressing_min'] + settings['walking_min']
    ideal_max = prep_min + SAFETY_BUFFER_MIN + 1

    next unless minutes_until_target >= 0 && minutes_until_target <= advance_min

    bus_list = sched['bus_numbers'].split(',').map(&:strip)
    arrivals = fetch_bus_arrivals(bus_list)

    if sched['last_window_date'] != today_str
      arr_summary = arrivals.map { |a| "• <b>#{a['bus_number']}-avtobus:</b> #{a['eta_min']} daqiqada (~#{a['distance_km']} km)" }.join("\n")
      msg = "🔔 <b>#{advance_min} DAQIQA QOLDI! Avtobus kuzatuvi boshlandi</b>\n\n" \
            "🚏 <b>Bekat:</b> #{sched['stop_name']}\n" \
            "🕗 <b>Rejadagi vaqt:</b> #{sched['target_time']}\n\n" \
            "📡 <b>Hozirgi avtobuslar holati:</b>\n#{arr_summary}\n\n" \
            "⏳ <i>Avtobus bekatga #{prep_min}–#{prep_min + SAFETY_BUFFER_MIN} daqiqalik masofaga kelishi bilan kiyinish haqida signal beraman!</i>"
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
              "🚌 <b>#{best['bus_number']}-avtobus:</b> bekatga <b>#{best['eta_min']} daqiqada</b> yetib keladi (~#{best['distance_km']} km / #{best['stops_away']} bekat uzoqlikda).\n\n" \
              "⏱ <b>Aniq vaqt rejasi:</b>\n" \
              "• 👕 Kiyinish uchun: <b>#{settings['dressing_min']} daqiqa</b> (soat #{leave_time} gacha)\n" \
              "• 🚶‍♂️ Bekatgacha borish: <b>#{settings['walking_min']} daqiqa</b>\n" \
              "• ✅ Bekatda bo'lasiz: avtobus kelishidan <b>#{best['eta_min'] - prep_min} daqiqa oldin!</b>"
        tg_api('sendMessage', { chat_id: sched['user_id'], text: msg, parse_mode: 'HTML' })
        sched['last_leave_date'] = today_str
        changed = true
      end
    end
  end

  save_db(db) if changed
end

# Cloud / Render Web Service uchun Healthcheck HTTP server
http_port = (ENV['PORT'] || 8080).to_i
Thread.new do
  server = TCPServer.new('0.0.0.0', http_port)
  puts "🌐 Healthcheck HTTP server ishga tushdi: port #{http_port}"
  loop do
    client = server.accept
    _req = client.gets
    body = "TashBus Alert Bot 24/7 ishlamoqda!\nServer vaqti: #{Time.now}\n"
    res = "HTTP/1.1 200 OK\r\nContent-Type: text/plain; charset=utf-8\r\nContent-Length: #{body.bytesize}\r\nConnection: close\r\n\r\n#{body}"
    client.write(res)
    client.close
  rescue StandardError
    # ignore client error
  end
rescue StandardError => e
  puts "⚠️ Healthcheck server ogohlantirish: #{e.message}"
end

puts 'TashBus Alert Bot ishga tushmoqda...'
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
