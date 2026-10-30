--[[

  ███╗   ███╗██╗██╗     ██╗     ███████╗███╗   ██╗██╗██╗   ██╗███╗   ███╗
  ████╗ ████║██║██║     ██║     ██╔════╝████╗  ██║██║██║   ██║████╗ ████║
  ██╔████╔██║██║██║     ██║     █████╗  ██╔██╗ ██║██║██║   ██║██╔████╔██║
  ██║╚██╔╝██║██║██║     ██║     ██╔══╝  ██║╚██╗██║██║██║   ██║██║╚██╔╝██║
  ██║ ╚═╝ ██║██║███████╗███████╗███████╗██║ ╚████║██║╚██████╔╝██║ ╚═╝ ██║
  ╚═╝     ╚═╝╚═╝╚══════╝╚══════╝╚══════╝╚═╝  ╚═══╝╚═╝ ╚═════╝ ╚═╝     ╚═╝

  M I L L E N I U M   H U D   ·   2 . 0   ·   "glass" edition
  Hello from Spotik

  Что это:
    Переписанное с нуля ядро HUD в стилистике Hyprland-«стекла»:
    плавающие острова, мягкие тени, акцентное свечение, плавные анимации.

  Что нового по сравнению с 1.4.x:
    • Полностью починен drag: одно полноэкранное окно-канвас в (0,0) =>
      координаты мыши и экрана совпадают, обратной связи «окно убегает
      за мышью» физически больше нет. Перетаскивается каждый остров отдельно,
      с магнитными направляющими. Интерактивность включается только в режиме
      редактирования — HUD больше не перехватывает клики в игре.
    • Радар машин (идея carRadar) переписан на Lua: стеклянный диск,
      кольца дистанции, блипы машин с их ориентацией, предупреждения
      «слева/справа/сзади».
    • Новые виджеты: круг сессии (позиция, круги, CUR/LAST/BEST), топливо
      с расчётом остатка кругов, повреждения, индикаторы ABS/TC/HB/света/пита.
    • Слой безопасного чтения телеметрии: поля CSP проверяются один раз,
      недоступные — аккуратно подменяются на «—» вместо ошибки в логе.
    • Диагностика прямо в настройках: видно, какие поля CSP доступны.

--]]

local VERSION = '2.0.0'
local SCHEMA  = 2

----------------------------------------------------------------------
-- 1. НАСТРОЙКИ (ac.storage сам сохраняет их между сессиями)
----------------------------------------------------------------------
-- Позиции островов — в долях экрана (0..1, центр виджета). Так они
-- не зависят от разрешения и от DPI: 0.5/0.87 — это «низ по центру».
local DEFAULT_POS = {
  speed      = { 0.500, 0.870 },
  pedals     = { 0.353, 0.870 },
  tyres      = { 0.647, 0.870 },
  gear       = { 0.760, 0.870 },
  radar      = { 0.130, 0.735 },
  session    = { 0.872, 0.780 },
  fuel       = { 0.872, 0.895 },
  damage     = { 0.130, 0.930 },
  indicators = { 0.500, 0.060 },
  brand      = { 0.118, 0.048 },
}

local DEFAULTS = {
  schema      = SCHEMA,

  -- виджеты
  hudSpeedo   = true,
  hudPedals   = true,
  hudTyres    = true,
  hudRadar    = true,
  hudSession  = true,
  hudFuel     = true,
  hudDamage   = false,   -- зависит от полей CSP, по умолчанию выключен
  hudInd      = true,    -- индикаторы ABS/TC/HB/света/пита
  hudBrand    = true,
  hudGear     = false,   -- отдельная плашка передачи (как в 1.4.x)

  -- внешний вид
  bgEnabled   = true,    -- подложка-стекло (выкл — чистые цифры поверх игры)
  opacity     = 0.62,    -- плотность стекла 0.15..0.95
  scale       = 1.00,    -- масштаб 0.75..1.45
  shadow      = true,    -- мягкая тень под островами
  sheen       = true,    -- блик по верхней кромке (эффект стекла)
  glow        = true,    -- акцентное свечение активных элементов
  radius      = 1.00,    -- радиус скругления 0.4..1.8
  accentPreset = 1,      -- индекс в ACCENTS
  accentCustom = false,
  accentR     = 0.62,
  accentG     = 0.40,
  accentB     = 1.00,

  -- спидометр
  speedoStyle = 'bar',   -- 'bar' | 'ring' | 'minimal'
  shiftFlash  = true,
  shiftPoint  = 0.94,    -- доля лимитера
  rpmSegments = 0,       -- 0 = авто по лимитеру
  showGearInline = true,

  -- педали / шины
  pedalPct    = true,
  pedalColors = true,    -- семантические цвета (иначе — акцентные)
  tyreUnits   = true,    -- °C / °F
  tyreWearInverted = true,

  -- радар
  radarRange  = 25,      -- метров
  radarRotate = true,    -- true = «по машине», false = «по северу»
  radarLabels = false,   -- подписи дистанции у блипов
  radarWarn   = true,    -- предупреждения слева/справа/сзади
  radarBlipScale = 1.0,
  radarHideAlone = true, -- без машин рядом — радар не рисуется

  -- сессия
  sessionClock = true,   -- показывать время сессии

  -- редактирование
  editMode    = false,
}

-- позиции добавляем в дефолты как плоские ключи: ac.storage надёжно
-- хранит только плоские значения
for id, p in pairs(DEFAULT_POS) do
  DEFAULTS['pos_' .. id .. '_x'] = p[1]
  DEFAULTS['pos_' .. id .. '_y'] = p[2]
end

local cfg = ac.storage(DEFAULTS)

-- миграция: в 1.x была одна общая панель (posX/posY) — раскладываем заново
if cfg.schema ~= SCHEMA then
  cfg.schema = SCHEMA
  for id, p in pairs(DEFAULT_POS) do
    cfg['pos_' .. id .. '_x'] = p[1]
    cfg['pos_' .. id .. '_y'] = p[2]
  end
end

local function posOf(id)
  return cfg['pos_' .. id .. '_x'] or 0.5, cfg['pos_' .. id .. '_y'] or 0.9
end

local function setPos(id, x, y)
  cfg['pos_' .. id .. '_x'] = math.clamp(x, 0.0, 1.0)
  cfg['pos_' .. id .. '_y'] = math.clamp(y, 0.0, 1.0)
end

----------------------------------------------------------------------
-- 2. ТЕМА
----------------------------------------------------------------------
local ACCENTS = {
  { 'Violet',  rgbm(0.62, 0.40, 1.00, 1) },
  { 'Cyan',    rgbm(0.25, 0.85, 1.00, 1) },
  { 'Magenta', rgbm(1.00, 0.35, 0.85, 1) },
  { 'Mint',    rgbm(0.35, 1.00, 0.70, 1) },
  { 'Amber',   rgbm(1.00, 0.66, 0.20, 1) },
  { 'Ice',     rgbm(0.82, 0.90, 1.00, 1) },
}

local COL_OK   = rgbm(0.35, 1.00, 0.60, 1)
local COL_WARN = rgbm(1.00, 0.38, 0.35, 1)
local COL_HOT  = rgbm(1.00, 0.30, 0.25, 1)
local COL_MID  = rgbm(1.00, 0.80, 0.20, 1)

local COL_GAS = rgbm(0.35, 1.00, 0.62, 1)
local COL_BRK = rgbm(1.00, 0.35, 0.38, 1)
local COL_CLT = rgbm(0.35, 0.75, 1.00, 1)
local COL_HB  = rgbm(1.00, 0.72, 0.25, 1)

-- Тема пересобирается раз в кадр (акцент может меняться в настройках)
local TH = {}
local function refreshTheme()
  local a = ACCENTS[math.clamp(tonumber(cfg.accentPreset) or 1, 1, #ACCENTS)][2]
  if cfg.accentCustom then
    a = rgbm(cfg.accentR, cfg.accentG, cfg.accentB, 1)
  end
  TH.accent   = a
  TH.accent2  = rgbm(a.r * 0.75 + 0.06, a.g * 0.70 + 0.04, a.b * 0.90 + 0.10, 1) -- чуть холоднее
  TH.soft     = rgbm(a.r, a.g, a.b, 0.55)
  TH.text     = rgbm(1, 1, 1, 0.95)
  TH.dim      = rgbm(1, 1, 1, 0.46)
  TH.faint    = rgbm(1, 1, 1, 0.20)
end

----------------------------------------------------------------------
-- 3. МИКРО-УТИЛИТЫ: пулы векторов/цветов, математика, время
----------------------------------------------------------------------
-- Каждый кадр рисуется несколько сотен примитивов. Создавать vec2/rgbm
-- на каждый вызов — тысячи объектов в секунду для сборщика мусора,
-- поэтому берём их из маленького пула (CSP отдаёт mutable-структуры).
local V_POOL, V_N, V_SIZE = {}, 0, 48
local function V(x, y)
  V_N = V_N % V_SIZE + 1
  local v = V_POOL[V_N]
  if not v then
    v = vec2(x, y)
    V_POOL[V_N] = v
  else
    v.x, v.y = x, y
  end
  return v
end

local C_POOL, C_N, C_SIZE = {}, 0, 48
local function C(r, g, b, a)
  C_N = C_N % C_SIZE + 1
  local c = C_POOL[C_N]
  if not c then
    c = rgbm(r, g, b, a or 1)
    C_POOL[C_N] = c
  else
    c.r, c.g, c.b, c.mult = r, g, b, a or 1
  end
  return c
end

local function tint(c, a) return C(c.r, c.g, c.b, a) end
local function mixc(c1, c2, t)
  return C(c1.r + (c2.r - c1.r) * t,
           c1.g + (c2.g - c1.g) * t,
           c1.b + (c2.b - c1.b) * t,
           (c1.mult or 1) + ((c2.mult or 1) - (c1.mult or 1)) * t)
end

local T   = 0    -- время, секунды
local DT  = 0    -- кадр, секунды (клампится)
local U   = 1    -- «дизайн-пиксель»: 1.0 при 1080p и scale = 1
local WS  = vec2(1920, 1080)

local function lerp(a, b, t) return a + (b - a) * t end
local function sat(x) return x < 0 and 0 or (x > 1 and 1 or x) end
local function pulse(speed, phase) return 0.5 + 0.5 * math.sin(T * speed + (phase or 0)) end

-- сглаживание, не зависящее от FPS
local ANIM = {}
local function anim(id, target, lag, snap)
  local cur = ANIM[id]
  if cur == nil or snap then
    ANIM[id] = target
    return target
  end
  local k = 1
  if lag and lag > 0 and DT > 0 then k = 1 - math.exp(-DT / lag) end
  cur = cur + (target - cur) * (k > 1 and 1 or k)
  ANIM[id] = cur
  return cur
end

local function fmtLap(ms)
  if ms == nil or ms < 0 then return '--:--.---' end
  local m = math.floor(ms / 60000)
  local s = math.floor((ms % 60000) / 1000)
  local t = math.floor(ms % 1000)
  return string.format('%d:%02d.%03d', m, s, t)
end

local function fmtClock(sec)
  if sec == nil or sec < 0 then return '--:--' end
  local m = math.floor(sec / 60)
  local s = math.floor(sec % 60)
  return string.format('%d:%02d', m, s)
end

local function fmtGear(g)
  g = g or 0
  if g == 0 then return 'N' end
  if g < 0 then return 'R' end
  return tostring(g)
end

----------------------------------------------------------------------
-- 4. ТЕКСТ
----------------------------------------------------------------------
-- DWrite позволяет задать произвольный кегль в пикселях — тогда вся
-- вёрстка считается в дизайн-пикселях и масштабируется идеально.
-- На старых сборках CSP DWrite-текста нет: тихо откатываемся на
-- встроенные кегли (вёрстка остаётся рабочей, просто кегли «ступеньками»).
local function mkfont(name, weight)
  if type(ui.DWriteFont) ~= 'function' then return nil end
  local ok, f = pcall(function() return ui.DWriteFont(name):weight(weight) end)
  if ok and f then return f end
  return nil
end

local fUi    = mkfont('Segoe UI', 450)
local fUiMed = mkfont('Segoe UI', 650)
local fUiBd  = mkfont('Segoe UI', 800)
local fNum   = mkfont('Consolas', 700) or fUiMed
local fNumLt = mkfont('Consolas', 400) or fUi

local DWRITE = (type(ui.dwriteDrawText) == 'function'
                and type(ui.measureDWriteText) == 'function'
                and type(ui.pushDWriteFont) == 'function'
                and fUi ~= nil)

local FONT_OF = {
  ui    = fUi,
  med   = fUiMed,
  bold  = fUiBd,
  num   = fNum,
  numLt = fNumLt,
}

local clippedOk = type(ui.drawTextClipped) == 'function'

local function builtinFontFor(size)
  local F = ui.Font
  if F == nil then return nil end
  if size <= 11 then return F.Small or F.Default end
  if size <= 16 then return F.Default or F.Small end
  if size <= 21 then return F.Big or F.Title or F.Default end
  if size <= 30 then return F.Title or F.Big or F.Default end
  return F.Huge or F.Title or F.Default
end

-- Состояние текущего текстового прогона
local TX = { kind = 'ui', size = 14, track = 0, pushed = false }

local function tbegin(kind, size, track)
  TX.kind  = kind or 'ui'
  TX.size  = math.max(6, size or 14)
  TX.track = track or 0
  if DWRITE then
    ui.pushDWriteFont(FONT_OF[TX.kind] or fUi)
    TX.pushed = true
  else
    local f = builtinFontFor(TX.size)
    if f ~= nil then ui.pushFont(f) end
    TX.pushed = (f ~= nil)
  end
end

local function tend()
  if TX.pushed then
    if DWRITE then ui.popDWriteFont() else ui.popFont() end
    TX.pushed = false
  end
end

-- размер строки в пикселях (y — высота глиф-бокса)
local function tsize(str)
  if DWRITE then
    local v = ui.measureDWriteText(str, TX.size)
    local w = v.x
    if TX.track > 0 and #str > 1 then w = w + TX.track * (#str - 1) end
    return w, v.y
  end
  local v = ui.measureText(str)
  return v.x, v.y
end

local function tdrawRaw(str, x, y, color)
  if DWRITE then
    ui.dwriteDrawText(str, TX.size, V(x, y), color)
  else
    ui.drawText(str, V(x, y), color)
  end
end

local function tdraw(str, x, y, color)
  if TX.track > 0 and DWRITE and #str > 1 then
    local cx = x
    for i = 1, #str do
      local ch = string.sub(str, i, i)
      ui.dwriteDrawText(ch, TX.size, V(cx, y), color)
      cx = cx + ui.measureDWriteText(ch, TX.size).x + TX.track
    end
    return
  end
  tdrawRaw(str, x, y, color)
end

-- optical: DWrite-бокс строки выше самого глифа, цифры «висят» вверх —
-- поэтому при центрировании подталкиваем вниз на долю высоты
local OPT = 0.055

local function tcenter(str, cx, cy, color)
  local w, h = tsize(str)
  tdraw(str, cx - w * 0.5, cy - h * 0.5 + h * OPT, color)
  return w, h
end

local function tleft(str, x, cy, color)
  local w, h = tsize(str)
  tdraw(str, x, cy - h * 0.5 + h * OPT, color)
  return w, h
end

local function tright(str, rx, cy, color)
  local w, h = tsize(str)
  tdraw(str, rx - w, cy - h * 0.5 + h * OPT, color)
  return w, h
end

-- push/pop для окна настроек (ImGui-контекст, без ограничений виджетов)
local function pushUI(kind, size)
  if DWRITE then
    local f = FONT_OF[kind] or fUi
    if f ~= nil then
      ui.pushDWriteFont(f)
      return true
    end
  end
  local f = builtinFontFor(size or 14)
  if f ~= nil then
    ui.pushFont(f)
    return true
  end
  return false
end

local function popUI(pushed)
  if not pushed then return end
  if DWRITE then ui.popDWriteFont() else ui.popFont() end
end

-- короткая обёртка: весь текст виджета по одному стилю
local function txt(kind, size, track, fn)
  tbegin(kind, size, track)
  fn()
  tend()
end

----------------------------------------------------------------------
-- 5. ПРИМИТИВЫ: стекло, полосы, дуги, шевроны
----------------------------------------------------------------------
local function R(px) return math.max(0, px * (cfg.radius or 1)) end

-- подложка-«стекло»: мягкая тень → рамка → плотное тело → блик
local function glass(x0, y0, x1, y1, radius, opt)
  if not cfg.bgEnabled then return end
  opt = opt or {}
  local A = math.clamp(cfg.opacity or 0.6, 0.05, 1) * (opt.alpha or 1)
  local r = math.max(0, radius or 12)

  if cfg.shadow and not opt.noShadow then
    for i = 4, 1, -1 do
      local e = i * 1.7 * U
      ui.drawRectFilled(V(x0 - e, y0 - e * 0.5 + 2.0 * U), V(x1 + e, y1 + e),
        C(0, 0, 0, 0.055 * A), r + e)
    end
  end

  if cfg.glow and opt.glow then
    local a = TH.accent
    for i = 3, 1, -1 do
      local e = i * 2.2 * U
      ui.drawRectFilled(V(x0 - e, y0 - e), V(x1 + e, y1 + e), C(a.r, a.g, a.b, 0.018 * A), r + e)
    end
  end

  -- рамка (светлая кромка) + тело
  ui.drawRectFilled(V(x0, y0), V(x1, y1), C(1, 1, 1, 0.105 * A), r)
  ui.drawRectFilled(V(x0 + 1, y0 + 1), V(x1 - 1, y1 - 1), C(0.030, 0.036, 0.070, A), math.max(0, r - 1))
  ui.drawRectFilled(V(x0 + 1, y0 + 1), V(x1 - 1, y1 - 1), C(1, 1, 1, 0.020 * A), math.max(0, r - 1))

  if cfg.sheen then
    local m = math.min(r * 0.9 + 2 * U, (x1 - x0) * 0.35)
    ui.drawRectFilled(V(x0 + m, y0 + 1), V(x1 - m, y0 + 1 + 1.2 * U), C(1, 1, 1, 0.16 * A))
  end
end

-- тонкая «стеклянная» плашка поменьше (для вложенных блоков)
local function chip(x0, y0, x1, y1, radius, alpha)
  if not cfg.bgEnabled then return end   -- режим «чистых цифр»: ни плашек, ни стекла
  local A = math.clamp(cfg.opacity or 0.6, 0.05, 1)
  ui.drawRectFilled(V(x0, y0), V(x1, y1), C(1, 1, 1, 0.055 * A * (alpha or 1)), math.max(0, radius or 6))
end

local function hline(x0, x1, y, alpha)
  ui.drawRectFilled(V(x0, y), V(x1, y + math.max(1, U)), C(1, 1, 1, alpha or 0.10))
end

-- полоса прогресса с подсветкой
local function bar(x0, y0, x1, y1, frac, color, alpha)
  frac = sat(frac)
  local r = (y1 - y0) * 0.5
  ui.drawRectFilled(V(x0, y0), V(x1, y1), C(1, 1, 1, 0.075 * (alpha or 1)), r)
  if frac > 0.004 then
    local fx = x0 + (x1 - x0) * frac
    if cfg.glow then
      ui.drawRectFilled(V(x0 - 1.5 * U, y0 - 1.5 * U), V(fx + 1.5 * U, y1 + 1.5 * U),
        C(color.r, color.g, color.b, 0.16 * (alpha or 1)), r + 1.5 * U)
    end
    ui.drawRectFilled(V(x0, y0), V(fx, y1), C(color.r, color.g, color.b, 0.95), r)
  end
end

-- сегментная полоса (как тахометр в F1): живёт по сегментам, а не «ползёт»
local function segbar(x0, y0, x1, y1, frac, segs, color, redFrom, alpha)
  local n = math.max(2, math.floor(segs))
  local gap = math.max(1.0 * U, (x1 - x0) * 0.006)
  local sw = ((x1 - x0) - gap * (n - 1)) / n
  local r = math.min((y1 - y0) * 0.5, sw * 0.5)
  local lit = frac * n
  for i = 1, n do
    local sx = x0 + (i - 1) * (sw + gap)
    local on = sat(lit - (i - 1))
    local inRed = redFrom ~= nil and ((i - 0.5) / n) >= redFrom
    local base = inRed and COL_HOT or color
    ui.drawRectFilled(V(sx, y0), V(sx + sw, y1), C(1, 1, 1, 0.070 * (alpha or 1)), r)
    if on > 0.01 then
      if cfg.glow and on > 0.5 then
        ui.drawRectFilled(V(sx - 1.2 * U, y0 - 1.2 * U), V(sx + sw + 1.2 * U, y1 + 1.2 * U),
          C(base.r, base.g, base.b, 0.20 * on), r + 1.2 * U)
      end
      ui.drawRectFilled(V(sx, y0), V(sx + sw, y1),
        C(base.r, base.g, base.b, (0.35 + 0.65 * on)), r)
    end
  end
end

-- дуга из отрезков, углы в градусах по часовой стрелке от «3 часов»
local function arcSeg(cx, cy, radius, a0, a1, color, th, segs)
  segs = segs or math.max(6, math.floor(math.abs(a1 - a0) / 4))
  local px = cx + radius * math.cos(math.rad(a0))
  local py = cy + radius * math.sin(math.rad(a0))
  for i = 1, segs do
    local a = math.rad(a0 + (a1 - a0) * i / segs)
    local qx = cx + radius * math.cos(a)
    local qy = cy + radius * math.sin(a)
    ui.drawLine(V(px, py), V(qx, qy), color, th)
    px, py = qx, qy
  end
end

local function tick(cx, cy, r0, r1, angDeg, color, th)
  local a = math.rad(angDeg)
  ui.drawLine(V(cx + r0 * math.cos(a), cy + r0 * math.sin(a)),
              V(cx + r1 * math.cos(a), cy + r1 * math.sin(a)), color, th)
end

-- шеврон-стрелка «>>» (индикатор стороны / маркер игрока)
local function chevron(cx, cy, size, dir, color, th)
  -- dir: 1 вправо, -1 влево, 0 вверх
  if dir == 0 then
    ui.drawLine(V(cx - size, cy + size * 0.6), V(cx, cy - size * 0.5), color, th)
    ui.drawLine(V(cx + size, cy + size * 0.6), V(cx, cy - size * 0.5), color, th)
    return
  end
  ui.drawLine(V(cx - size * 0.5 * dir, cy - size), V(cx + size * 0.5 * dir, cy), color, th)
  ui.drawLine(V(cx - size * 0.5 * dir, cy + size), V(cx + size * 0.5 * dir, cy), color, th)
end

-- «машинка» на радаре: короткий штрих вдоль курса (angRad: 0 = вверх экрана)
local function carGlyph(cx, cy, len, wid, angRad, color)
  local s, c = math.sin(angRad), math.cos(angRad)
  ui.drawLine(V(cx - s * len * 0.5, cy + c * len * 0.5),
              V(cx + s * len * 0.5, cy - c * len * 0.5), color, math.max(2, wid))
end

----------------------------------------------------------------------
-- 6. БЕЗОПАСНОЕ ЧТЕНИЕ ТЕЛЕМЕТРИИ
----------------------------------------------------------------------
-- Поля ac.StateCar отличаются между сборками CSP (особенно новые:
-- температура ядра шины, ABS/TC, топливо, повреждения). Прямое чтение
-- отсутствующего поля — ошибка Lua в логе и мёртвый HUD. Поэтому:
--   * поле проверяется один раз (pcall), результат кешируется;
--   * недоступное поле дальше просто отдаёт nil, виджет рисует «—».
-- Никаких pcall в горячем пути после первого кадра.

local CAP, CAPORDER = {}, {}
local function capMark(name, ok)
  if CAP[name] == nil then
    CAP[name] = ok
    CAPORDER[#CAPORDER + 1] = name
  end
end

local function field(cands, label)
  local chosen, resolved = nil, false
  local name = label or cands[1]
  return function(obj)
    if obj == nil then return nil end
    if resolved then
      if chosen == nil then return nil end
      return obj[chosen]
    end
    for i = 1, #cands do
      local ok, v = pcall(function() return obj[cands[i]] end)
      if ok and v ~= nil then
        chosen, resolved = cands[i], true
        capMark(name, true)
        return v
      end
    end
    resolved = true
    capMark(name, false)
    return nil
  end
end

local FIELD = {
  -- машина
  look        = field({ 'look' }, 'look'),
  fuel        = field({ 'fuel', 'fuelLiters' }, 'fuel'),
  abs         = field({ 'absInAction', 'isAbsActive', 'absActive' }, 'abs'),
  tc          = field({ 'tractionControlInAction', 'isTcActive', 'tcActive', 'tcInAction' }, 'tc'),
  lights      = field({ 'headlightsActive', 'lightsAreOn', 'isHeadlightOn', 'headlightsOn' }, 'lights'),
  pitLimiter  = field({ 'pitLimiterOn', 'isPitLimiterOn', 'pitLimiter' }, 'pitlim'),
  damage      = field({ 'damage' }, 'damage'),
  turbo       = field({ 'turboBoost' }, 'turbo'),
  -- шины
  wCoreTemp   = field({ 'tyreCoreTemperature', 'coreTemperature', 'tyreCoreTemp' }, 'wTempCore'),
  wTemp       = field({ 'tyreTemperature', 'temperature' }, 'wTemp'),
  wWear       = field({ 'tyreWear', 'wear' }, 'wWear'),
  wPressure   = field({ 'tyrePressure', 'pressure' }, 'wPress'),
  wDisc       = field({ 'discTemperature', 'brakeTemperature' }, 'wDisc'),
  -- симуляция
  simTimeLeft = field({ 'sessionTimeLeft', 'timeLeft' }, 'timeLeft'),
  simLaps     = field({ 'lapsCount', 'totalLaps', 'raceLaps' }, 'lapsTotal'),
  simFocused  = field({ 'focusedCar' }, 'focusedCar'),
  lapsNow     = field({ 'lapCount', 'completedLaps', 'lapsCompleted' }, 'lapsNow'),
}

-- человеческие подписи для панели диагностики
local CAPTITLE = {
  look = 'направление машины', fuel = 'топливо',
  abs = 'ABS в работе', tc = 'TC в работе', lights = 'фары',
  pitlim = 'пита-лимитер', damage = 'повреждения', turbo = 'наддув',
  wTempCore = 'темп. ядра шины', wTemp = 'темп. шины',
  wWear = 'износ шины', wPress = 'давление в шине', wDisc = 'темп. диска',
  timeLeft = 'время сессии', lapsTotal = 'число кругов', focusedCar = 'фокусная машина',
  lapsNow = 'номер круга',
}

local function wheelOf(car, i)
  if car == nil or car.wheels == nil then return nil end
  local ok, w = pcall(function() return car.wheels[i] end)
  if ok then return w end
  return nil
end

-- ориентир машины в мировых осях XZ: forward и right (единичные)
local AXES = { fx = 0, fz = -1, rx = 1, rz = 0, ok = false }
local axesFromWheels = true

local function updateAxes(car)
  if car == nil then return AXES end
  local look = FIELD.look(car)
  if look ~= nil and look.x ~= nil then
    local fx, fz = look.x, look.z
    local l = math.sqrt(fx * fx + fz * fz)
    if l > 1e-4 then
      AXES.fx, AXES.fz = fx / l, fz / l
      -- right = up × forward = (fz, 0, -fx)
      AXES.rx, AXES.rz = AXES.fz, -AXES.fx
      AXES.ok = true
      return AXES
    end
  end
  -- резерв: ось по точкам контакта передних колёс (FL → FR = вправо)
  local fl, fr = wheelOf(car, 0), wheelOf(car, 1)
  if fl ~= nil and fr ~= nil then
    local a, b = fl.contactPoint, fr.contactPoint
    if a ~= nil and b ~= nil then
      local dx, dz = b.x - a.x, b.z - a.z
      local l = math.sqrt(dx * dx + dz * dz)
      if l > 1e-3 then
        AXES.rx, AXES.rz = dx / l, dz / l
        AXES.fx, AXES.fz = -AXES.rz, AXES.rx
        AXES.ok = true
        return AXES
      end
    end
  end
  return AXES -- остаётся предыдущее валидное значение
end

local function axesOf(car)
  local a = { fx = 0, fz = -1, rx = 1, rz = 0 }
  local look = FIELD.look(car)
  if look ~= nil and look.x ~= nil then
    local fx, fz = look.x, look.z
    local l = math.sqrt(fx * fx + fz * fz)
    if l > 1e-4 then
      a.fx, a.fz = fx / l, fz / l
      a.rx, a.rz = a.fz, -a.fx
      return a
    end
  end
  local fl, fr = wheelOf(car, 0), wheelOf(car, 1)
  if fl ~= nil and fr ~= nil then
    local p1, p2 = fl.contactPoint, fr.contactPoint
    if p1 ~= nil and p2 ~= nil then
      local dx, dz = p2.x - p1.x, p2.z - p1.z
      local l = math.sqrt(dx * dx + dz * dz)
      if l > 1e-3 then
        a.rx, a.rz = dx / l, dz / l
        a.fx, a.fz = -a.rz, a.rx
        return a
      end
    end
  end
  return a
end

local function atan2(y, x)
  if x > 0 then return math.atan(y / x) end
  if x < 0 then return math.atan(y / x) + (y >= 0 and math.pi or -math.pi) end
  if y > 0 then return math.pi * 0.5 end
  if y < 0 then return -math.pi * 0.5 end
  return 0
end

----------------------------------------------------------------------
-- 7. ДАННЫЕ: лимитер, круги, топливо, машины рядом
----------------------------------------------------------------------
local DATA = {
  limit       = 8000,
  limitFor    = nil,
  carCount    = 0,

  fuel        = nil,
  fuelAtLap   = nil,
  fuelPerLap  = nil,
  lapsLeft    = nil,

  curLapMs    = 0,
  prevLapMs   = -1,
  lastLapMs   = nil,
  bestLapMs   = nil,
  lastValid   = true,

  sessionLeft = nil,

  near        = {},   -- ближайшие машины для радара
  nearCount   = 0,
  nearest     = nil,  -- самая близкая
  warnLeft    = 0,    -- яркость предупреждения слева (0..1)
  warnRight   = 0,
  warnBack    = 0,
}

-- лимитер из engine.ini установленной модели (кэш по ID машины)
local function refreshLimit(car)
  local id = nil
  local okId, v = pcall(function() return ac.getCarID(car.index) end)
  if okId then id = v end
  if id ~= nil and id == DATA.limitFor then return end
  DATA.limitFor = id
  DATA.limit = 8000
  local ok, ini = pcall(function() return ac.INIConfig.carData(car.index, 'engine.ini') end)
  if ok and ini ~= nil then
    local lim = ini:get('ENGINE_DATA', 'LIMITER', 0)
    if type(lim) == 'number' and lim > 1500 then
      DATA.limit = lim
    end
  end
end

local function rpmFrac(car)
  local r = car ~= nil and car.rpm or 0
  if r == nil or r < 0 then r = 0 end
  return sat(r / (DATA.limit > 1000 and DATA.limit or 8000))
end

local function updateSession(car)
  -- ---- круги: отслеживаем сами, не полагаясь на необязательные поля
  local lapMs = (car.lapTimeMs ~= nil) and car.lapTimeMs or 0
  DATA.curLapMs = lapMs
  if DATA.prevLapMs >= 0 and lapMs + 1500 < DATA.prevLapMs and DATA.prevLapMs > 5000 then
    -- смена круга
    DATA.lastLapMs = DATA.prevLapMs
    local valid = (car.isLastLapValid ~= false)
    DATA.lastValid = valid
    if valid and (DATA.bestLapMs == nil or DATA.prevLapMs < DATA.bestLapMs) then
      DATA.bestLapMs = DATA.prevLapMs
    end
    local f = FIELD.fuel(car)
    if f ~= nil and DATA.fuelAtLap ~= nil then
      local used = DATA.fuelAtLap - f
      if used > 0.05 and used < 40 then
        DATA.fuelPerLap = (DATA.fuelPerLap == nil) and used
          or lerp(DATA.fuelPerLap, used, 0.45)
      end
    end
    DATA.fuelAtLap = f
  end
  if DATA.fuelAtLap == nil then DATA.fuelAtLap = FIELD.fuel(car) end
  DATA.prevLapMs = lapMs

  -- ---- топливо
  local f = FIELD.fuel(car)
  DATA.fuel = f
  if f ~= nil and DATA.fuelPerLap ~= nil and DATA.fuelPerLap > 0.05 then
    DATA.lapsLeft = math.max(0, f / DATA.fuelPerLap)
  else
    DATA.lapsLeft = nil
  end

  -- ---- время сессии
  local sim = ac.getSim()
  if sim ~= nil then
    local t = FIELD.simTimeLeft(sim)
    if type(t) == 'number' then
      DATA.sessionLeft = t
    end
    local laps = FIELD.simLaps(sim)
    if type(laps) == 'number' and laps > 0 then DATA.totalLaps = laps else DATA.totalLaps = nil end
  end
end

-- машины рядом (для радара)
local MAX_NEAR = 16
for i = 1, MAX_NEAR do DATA.near[i] = {} end

local function updateRadar(car)
  local n = 0
  local range = math.max(6, tonumber(cfg.radarRange) or 25)
  local px, pz = car.position.x, car.position.z
  local ax = updateAxes(car)
  local nearest, nearestD = nil, 1e9
  local wl, wr, wb = 0, 0, 0

  for i = 0, 63 do
    local o = ac.getCar(i)
    if o == nil then break end
    DATA.carCount = i + 1
    if i ~= car.index and o.position ~= nil then
      local op = o.position
      local dx, dz = op.x - px, op.z - pz
      local dist = math.sqrt(dx * dx + dz * dz)
      if dist <= range then
        local fwd = dx * ax.fx + dz * ax.fz
        local lat = dx * ax.rx + dz * ax.rz
        local oa = axesOf(o)
        local hFwd = oa.fx * ax.fx + oa.fz * ax.fz
        local hLat = oa.fx * ax.rx + oa.fz * ax.rz
        n = n + 1
        if n <= MAX_NEAR then
          local s = DATA.near[n]
          s.dist, s.dx, s.dz, s.fwd, s.lat = dist, dx, dz, fwd, lat
          s.hFwd, s.hLat = hFwd, hLat
          s.hx, s.hz = oa.fx, oa.fz
          s.index = i
        end
        if dist < nearestD then nearestD, nearest = dist, { dist = dist, fwd = fwd, lat = lat } end

        -- слепая зона: рядом и сзади/сбоку
        if cfg.radarWarn then
          if math.abs(lat) > 1.4 and fwd < 3.0 then
            local k = sat(1 - dist / math.min(range, 18))
            if lat < 0 then wl = math.max(wl, k) else wr = math.max(wr, k) end
          elseif fwd < -2.0 and math.abs(lat) <= 1.4 then
            wb = math.max(wb, sat(1 - dist / math.min(range, 14)))
          end
        end
      end
    end
  end

  DATA.nearCount = n
  DATA.nearest = nearest
  DATA.warnLeft = anim('warnL', wl, 0.12)
  DATA.warnRight = anim('warnR', wr, 0.12)
  DATA.warnBack = anim('warnB', wb, 0.12)
end

local function rdWheel(car, i, getter, fallback)
  local w = wheelOf(car, i)
  if w == nil then return fallback end
  local v = getter(w)
  if type(v) ~= 'number' then return fallback end
  return v
end

----------------------------------------------------------------------
-- 8. ВИДЖЕТЫ
----------------------------------------------------------------------
-- Каждый виджет: function(x0, y0, w, h), где x0/y0 — левый верхний угол
-- в экранных пикселях, w/h — уже отмасштабированный размер.
-- Внутри всё считается в долях от w/h, а кегли — через U (дизайн-пиксель).

local CAR = nil

local function measure(kind, size, str, track)
  tbegin(kind, size, track)
  local w, hh = tsize(str)
  tend()
  return w, hh
end

local function shiftState(frac)
  return cfg.shiftFlash and frac >= cfg.shiftPoint
end

----------------------------------------------------------------------
-- 8.1 СПИДОМЕТР
----------------------------------------------------------------------
local function speedSize()
  local s = cfg.speedoStyle
  if s == 'ring' then return 268, 268 end
  if s == 'minimal' then return 276, 122 end
  return 340, 156
end

local function drawGearPlate(gx0, gy0, gx1, gy1, flash)
  chip(gx0, gy0, gx1, gy1, R(10 * U), 1)
  local ph = gy1 - gy0
  local gear = fmtGear(CAR.gear)
  local col
  if gear == 'N' then
    col = TH.dim
  elseif flash then
    col = C(1, 0.42 + 0.30 * pulse(16), 0.38, 1)
  else
    col = TH.accent
  end
  txt('ui', math.min(8.0 * U, ph * 0.15), 1.4 * U, function()
    tcenter('GEAR', (gx0 + gx1) * 0.5, gy0 + ph * 0.17, TH.faint)
  end)
  txt('num', ph * 0.50, 0, function()
    tcenter(gear, (gx0 + gx1) * 0.5, gy0 + ph * 0.64, col)
  end)
end

local function drawSpeedBar(x0, y0, w, h, spd, frac, flash)
  local pad   = h * 0.095
  local barH  = math.max(5 * U, h * 0.050)
  local barY1 = y0 + h - pad
  local barY0 = barY1 - barH
  local gearW = cfg.showGearInline and (w * 0.205) or 0

  if cfg.showGearInline then
    local gx0 = x0 + w - pad - gearW
    drawGearPlate(gx0, y0 + pad * 0.85, x0 + w - pad, barY0 - pad * 0.55, flash)
  end

  local ax0 = x0 + pad
  local ax1 = x0 + w - pad - (gearW > 0 and (gearW + pad * 0.7) or 0)
  local numSize = (h - barH - pad * 2) * 0.74

  txt('num', numSize, 0, function()
    tcenter(string.format('%.0f', spd), (ax0 + ax1) * 0.5, y0 + h * 0.395, TH.text)
  end)
  txt('ui', math.max(8 * U, h * 0.072), 1.4 * U, function()
    tcenter('КМ/Ч', (ax0 + ax1) * 0.5, y0 + h * 0.665, TH.dim)
  end)

  local segs = (cfg.rpmSegments and cfg.rpmSegments > 0) and cfg.rpmSegments
    or math.clamp(math.floor(DATA.limit / 1000 + 0.5), 6, 14)
  segbar(x0 + pad, barY0, x0 + w - pad, barY1, frac, segs, TH.accent, 0.87)
end

local ARC_A0, ARC_A1 = 135, 405

local function drawSpeedRing(x0, y0, w, h, spd, frac, flash)
  local cx, cy = x0 + w * 0.5, y0 + h * 0.5
  local rad = math.min(w, h) * 0.5 - 14 * U
  local th = math.max(4 * U, rad * 0.055)

  arcSeg(cx, cy, rad, ARC_A0, ARC_A1, C(1, 1, 1, 0.070), th, 64)
  arcSeg(cx, cy, rad, ARC_A0 + (ARC_A1 - ARC_A0) * 0.87, ARC_A1, C(1, 0.25, 0.20, 0.30), th, 20)

  if frac > 0.004 then
    local col = flash and COL_WARN or TH.accent
    local a1 = ARC_A0 + (ARC_A1 - ARC_A0) * frac
    if cfg.glow then
      arcSeg(cx, cy, rad, ARC_A0, a1, tint(col, 0.16), th * 2.5, 48)
    end
    arcSeg(cx, cy, rad, ARC_A0, a1, col, th, 48)
  end

  local tops = math.floor(DATA.limit / 1000)
  for k = 0, tops do
    local a = ARC_A0 + (ARC_A1 - ARC_A0) * (k * 1000) / DATA.limit
    tick(cx, cy, rad - th * 1.0, rad + th * 1.0, a, C(1, 1, 1, 0.22), math.max(1, 1.1 * U))
  end

  local a = math.rad(ARC_A0 + (ARC_A1 - ARC_A0) * frac)
  ui.drawLine(V(cx + rad * 0.63 * math.cos(a), cy + rad * 0.63 * math.sin(a)),
              V(cx + (rad - th * 1.2) * math.cos(a), cy + (rad - th * 1.2) * math.sin(a)),
              flash and COL_WARN or C(1, 1, 1, 0.85), math.max(1.6 * U, 2.2 * U))

  local gear = fmtGear(CAR.gear)
  txt('num', rad * 0.36, 0, function()
    tcenter(gear, cx, cy - rad * 0.42, gear == 'N' and TH.dim or TH.accent)
  end)
  txt('num', rad * 0.60, 0, function()
    tcenter(string.format('%.0f', spd), cx, cy + rad * 0.10, TH.text)
  end)
  txt('ui', math.max(8 * U, rad * 0.115), 1.4 * U, function()
    tcenter('КМ/Ч', cx, cy + rad * 0.52, TH.dim)
  end)
end

local function drawSpeedMinimal(x0, y0, w, h, spd, frac, flash)
  local pad = 14 * U
  local gearW = cfg.showGearInline and (w * 0.20) or 0
  local ax1 = x0 + w - pad - (gearW > 0 and gearW + pad * 0.6 or 0)

  txt('num', h * 0.56, 0, function()
    tcenter(string.format('%.0f', spd), (x0 + pad + ax1) * 0.5, y0 + h * 0.42, TH.text)
  end)
  txt('ui', 8.5 * U, 1.4 * U, function()
    tcenter('КМ/Ч', (x0 + pad + ax1) * 0.5, y0 + h * 0.74, TH.dim)
  end)
  if cfg.showGearInline then
    drawGearPlate(x0 + w - pad - gearW, y0 + pad, x0 + w - pad, y0 + h - pad * 2.4, flash)
  end
  local segs = (cfg.rpmSegments and cfg.rpmSegments > 0) and cfg.rpmSegments
    or math.clamp(math.floor(DATA.limit / 1000 + 0.5), 6, 14)
  segbar(x0 + pad, y0 + h - 3.0 * U, x0 + w - pad, y0 + h - 1.0 * U, frac, segs, TH.accent, 0.87)
end

local function drawSpeed(x0, y0, w, h)
  local spd  = anim('spd', math.max(0, CAR.speedKmh or 0), 0.075)
  local frac = anim('rpm', rpmFrac(CAR), 0.035)
  local flash = shiftState(frac)

  glass(x0, y0, x0 + w, y0 + h, R(h * 0.19), { glow = flash and cfg.glow })

  if cfg.speedoStyle == 'ring' then
    drawSpeedRing(x0, y0, w, h, spd, frac, flash)
  elseif cfg.speedoStyle == 'minimal' then
    drawSpeedMinimal(x0, y0, w, h, spd, frac, flash)
  else
    drawSpeedBar(x0, y0, w, h, spd, frac, flash)
  end

  if flash then
    -- пульсирующая кромка у красной зоны
    local a = 0.25 + 0.45 * pulse(14)
    ui.drawRectFilled(V(x0 + 1, y0 + 1), V(x0 + w - 1, y0 + 2 * U), C(COL_WARN.r, COL_WARN.g, COL_WARN.b, a))
    ui.drawRectFilled(V(x0 + 1, y0 + h - 2 * U), V(x0 + w - 1, y0 + h - 1), C(COL_WARN.r, COL_WARN.g, COL_WARN.b, a))
  end
end

----------------------------------------------------------------------
-- 8.2 ПЕДАЛИ
----------------------------------------------------------------------
local PED_ROWS = {
  { 'GAS', COL_GAS, function(c) return c.gas end },
  { 'BRK', COL_BRK, function(c) return c.brake end },
  { 'CLT', COL_CLT, function(c) return c.clutch ~= nil and (1 - c.clutch) or 0 end },
  { 'HB',  COL_HB,  function(c) return c.handbrake end },
}
local function pedSize() return 210, 142 end

local function drawPedals(x0, y0, w, h)
  glass(x0, y0, x0 + w, y0 + h, R(h * 0.16))
  local pad = 13 * U
  local rowH = (h - pad * 2) / 4
  local barH = math.max(4 * U, rowH * 0.32)
  local labelW = 31 * U
  local pctW = cfg.pedalPct and 25 * U or 0

  for i = 1, 4 do
    local row = PED_ROWS[i]
    local cy = y0 + pad + (i - 0.5) * rowH
    local raw = row[3](CAR)
    local v = sat(anim('ped' .. i, (type(raw) == 'number') and raw or 0, 0.028))
    local baseCol = cfg.pedalColors and row[2] or TH.accent

    txt('ui', 8.5 * U, 1.3 * U, function()
      tleft(row[1], x0 + pad, cy, v > 0.04 and TH.text or TH.dim)
    end)

    local bx0 = x0 + pad + labelW
    local bx1 = x0 + w - pad - pctW
    bar(bx0, cy - barH * 0.5, bx1, cy + barH * 0.5, v, baseCol)

    if cfg.pedalPct then
      txt('num', 9.5 * U, 0, function()
        tright(string.format('%.0f', v * 100), x0 + w - pad, cy, v > 0.02 and TH.text or TH.faint)
      end)
    end
  end
end

----------------------------------------------------------------------
-- 8.3 ШИНЫ
----------------------------------------------------------------------
local TYRE_LABELS = { 'LF', 'RF', 'LR', 'RR' }

local function tyreColor(t)
  if t == nil then return TH.faint end
  if t >= 115 then return COL_HOT end
  if t >= 100 then return COL_MID end
  if t >= 75 then return COL_OK end
  return C(1, 1, 1, 0.42)
end

local function tyreSize() return 210, 150 end

local function drawTyres(x0, y0, w, h)
  glass(x0, y0, x0 + w, y0 + h, R(h * 0.15))
  local pad, gap = 12 * U, 7 * U
  local cw = (w - pad * 2 - gap) * 0.5
  local ch = (h - pad * 2 - gap) * 0.5

  for i = 0, 3 do
    local cx = x0 + pad + (i % 2) * (cw + gap)
    local cy = y0 + pad + math.floor(i * 0.5) * (ch + gap)
    chip(cx, cy, cx + cw, cy + ch, R(9 * U), 1)

    local temp = rdWheel(CAR, i, FIELD.wCoreTemp, nil)
    if temp == nil then temp = rdWheel(CAR, i, FIELD.wTemp, nil) end
    local tcol = tyreColor(temp)

    txt('ui', 8.0 * U, 1.3 * U, function()
      tleft(TYRE_LABELS[i + 1], cx + 8 * U, cy + 10.5 * U, TH.dim)
    end)

    local wear = rdWheel(CAR, i, FIELD.wWear, nil)
    if wear ~= nil then
      local wf = sat(cfg.tyreWearInverted and (1 - wear) or wear)
      txt('ui', 7.5 * U, 0, function()
        tright(string.format('%.0f%%', wf * 100), cx + cw - 8 * U, cy + 10.5 * U, TH.faint)
      end)
      local wcol = wf > 0.55 and COL_OK or (wf > 0.28 and COL_MID or COL_HOT)
      bar(cx + 8 * U, cy + ch - 6.5 * U, cx + cw - 8 * U, cy + ch - 4.2 * U, wf, wcol, 0.9)
    end

    txt('num', ch * 0.36, 0, function()
      tcenter(temp ~= nil and string.format('%.0f°', temp) or '—',
        cx + cw * 0.5, cy + ch * 0.50, tcol)
    end)
  end
end

----------------------------------------------------------------------
-- 8.4 РАДАР МАШИН  (идея carRadar, переписано на Lua/CSP)
----------------------------------------------------------------------
local RAD_W, RAD_H = 254, 300
local function radarSize() return RAD_W, RAD_H end

local function dirWord(fwd, lat)
  local fb = (fwd > 1.5) and 'спереди' or ((fwd < -1.5) and 'сзади' or nil)
  local lr = (lat > 1.5) and 'справа' or ((lat < -1.5) and 'слева' or nil)
  if fb and lr then return fb .. '-' .. lr end
  return fb or lr or 'рядом'
end

local function drawRadar(x0, y0, w, h)
  local range = math.max(6, tonumber(cfg.radarRange) or 25)
  local hasCars = DATA.nearCount > 0
  local vis = anim('radarVis', (hasCars or not cfg.radarHideAlone) and 1 or 0.34, 0.30)

  glass(x0, y0, x0 + w, y0 + h, R(20 * U), { glow = cfg.glow and hasCars and DATA.nearest ~= nil and DATA.nearest.dist < 6 })

  local headH = 25 * U
  local footH = 23 * U

  txt('ui', 8.5 * U, 1.7 * U, function()
    tleft('RADAR', x0 + 14 * U, y0 + headH * 0.55, TH.dim)
  end)
  txt('ui', 8.0 * U, 0.8 * U, function()
    tright(string.format('%.0f М', range), x0 + w - 14 * U, y0 + headH * 0.55, TH.faint)
  end)
  hline(x0 + 13 * U, x0 + w - 13 * U, y0 + headH, 0.07)

  local cx = x0 + w * 0.5
  local cy = y0 + headH + (h - headH - footH) * 0.5
  local rad = math.min(w * 0.5 - 15 * U, (h - headH - footH) * 0.5 - 4 * U)

  ui.drawCircleFilled(V(cx, cy), rad + 1.2 * U, C(1, 1, 1, 0.085 * (0.5 + 0.5 * vis)))
  ui.drawCircleFilled(V(cx, cy), rad, C(0.018, 0.022, 0.048, 0.55))

  for k = 1, 3 do
    arcSeg(cx, cy, rad * k / 3, 0, 360, C(1, 1, 1, (k == 3) and 0.10 or 0.055),
      math.max(1, 1.0 * U), 44)
  end
  ui.drawLine(V(cx, cy - rad * 0.99), V(cx, cy + rad * 0.99), C(1, 1, 1, 0.045), 1)
  ui.drawLine(V(cx - rad * 0.99, cy), V(cx + rad * 0.99, cy), C(1, 1, 1, 0.045), 1)

  -- блипы
  local scale = (rad - 7 * U) / range
  local n = math.min(DATA.nearCount, MAX_NEAR)
  for i = 1, n do
    local s = DATA.near[i]
    local sx, sy, ang
    if cfg.radarRotate then
      sx, sy = s.lat, -s.fwd
      ang = atan2(s.hLat, s.hFwd)
    else
      sx, sy = s.dx, -s.dz
      ang = atan2(s.hx, s.hz)
    end
    local px, py = cx + sx * scale, cy + sy * scale
    local ddx, ddy = px - cx, py - cy
    local dd = math.sqrt(ddx * ddx + ddy * ddy)
    if dd > rad - 5 * U and dd > 0.001 then
      px, py = cx + ddx / dd * (rad - 5 * U), cy + ddy / dd * (rad - 5 * U)
    end

    local col = (s.dist < 3.5) and COL_HOT or ((s.dist < 9) and COL_MID or TH.accent)
    local a = sat(1.25 - s.dist / (range * 1.15)) * vis
    if cfg.glow and s.dist < 9 then
      ui.drawCircleFilled(V(px, py), 6 * U * cfg.radarBlipScale, tint(col, 0.15 * a))
    end
    carGlyph(px, py, 16 * U * cfg.radarBlipScale, 3.4 * U * cfg.radarBlipScale, ang, tint(col, a))
    if cfg.radarLabels and s.dist > 0.5 then
      txt('ui', 7.5 * U, 0, function()
        tcenter(string.format('%.0f', s.dist), px, py - 10 * U, tint(TH.dim, 0.95 * vis))
      end)
    end
  end

  -- маркер игрока
  local ms = 5.5 * U
  local pcol = tint(TH.accent, 0.95 * vis)
  ui.drawLine(V(cx - ms, cy + ms * 0.9), V(cx, cy - ms * 0.8), pcol, math.max(1.6 * U, 2 * U))
  ui.drawLine(V(cx + ms, cy + ms * 0.9), V(cx, cy - ms * 0.8), pcol, math.max(1.6 * U, 2 * U))
  ui.drawLine(V(cx - ms * 0.55, cy + ms * 0.35), V(cx + ms * 0.55, cy + ms * 0.35), tint(pcol, 0.6), math.max(1, 1.4 * U))

  -- предупреждения: дуги у краёв диска
  local function warnMark(side, amount)
    if amount <= 0.02 then return end
    local col = mixc(TH.accent, COL_HOT, sat(amount))
    local a0 = (side > 0) and (-58) or 122
    local a1 = (side > 0) and 58 or 238
    arcSeg(cx, cy, rad - 2 * U, a0, a1, tint(col, 0.30 * amount * vis), math.max(2.4 * U, 3.4 * U), 20)
    local chevX = cx + side * (rad - 8 * U)
    chevron(chevX, cy, 5 * U, side, tint(col, (0.45 + 0.55 * amount) * vis), math.max(1.6 * U, 2 * U))
  end
  warnMark(-1, DATA.warnLeft)
  warnMark(1, DATA.warnRight)

  -- подвал: ближайшая машина
  local nst = DATA.nearest
  txt('ui', 8.2 * U, 0.7 * U, function()
    if nst == nil then
      tcenter('НЕТ МАШИН РЯДОМ', cx, y0 + h - footH * 0.55, TH.faint)
    else
      local col = (nst.dist < 3.5) and COL_HOT or ((nst.dist < 9) and COL_MID or TH.dim)
      tcenter(string.format('%.1f М · %s', nst.dist, string.upper(dirWord(nst.fwd, nst.lat))),
        cx, y0 + h - footH * 0.55, col)
    end
  end)
end

----------------------------------------------------------------------
-- 8.5 СЕССИЯ (позиция, круги, времена)
----------------------------------------------------------------------
local function sessSize() return 258, 152 end

local function drawSession(x0, y0, w, h)
  glass(x0, y0, x0 + w, y0 + h, R(h * 0.15))
  local pad = 14 * U
  local topH = h * 0.36

  local pos = CAR.racePosition or 0
  local total = (DATA.carCount > 0) and DATA.carCount or nil
  local posStr = (pos > 0) and ('P' .. pos) or 'P—'
  local posSize = topH * 0.92
  local pw = measure('num', posSize, posStr)

  txt('ui', 8.0 * U, 1.6 * U, function()
    tleft('POS', x0 + pad, y0 + pad + 4 * U, TH.dim)
  end)
  txt('num', posSize, 0, function()
    tleft(posStr, x0 + pad, y0 + pad + topH * 0.62, TH.text)
  end)
  if total ~= nil then
    txt('ui', posSize * 0.34, 0, function()
      tleft('/' .. total, x0 + pad + pw + 3 * U, y0 + pad + topH * 0.72, TH.faint)
    end)
  end

  -- круг справа сверху
  local lapNow = FIELD.lapsNow(CAR)
  local lapsTotal = DATA.totalLaps
  local lapStr
  if type(lapNow) == 'number' and lapsTotal then
    lapStr = string.format('%d/%d', lapNow, lapsTotal)
  elseif type(lapNow) == 'number' then
    lapStr = tostring(lapNow)
  elseif lapsTotal then
    lapStr = string.format('—/%d', lapsTotal)
  else
    lapStr = '—'
  end
  txt('ui', 8.0 * U, 1.6 * U, function()
    tright('LAP', x0 + w - pad, y0 + pad + 4 * U, TH.dim)
  end)
  txt('num', topH * 0.42, 0, function()
    tright(lapStr, x0 + w - pad, y0 + pad + topH * 0.66, TH.text)
  end)

  hline(x0 + pad, x0 + w - pad, y0 + pad + topH + 4 * U, 0.08)

  -- строки времён
  local rows = {
    { 'CUR',  fmtLap(DATA.curLapMs), TH.text },
    { 'LAST', (DATA.lastLapMs ~= nil) and fmtLap(DATA.lastLapMs) or '--:--.---',
      (DATA.lastLapMs ~= nil and not DATA.lastValid) and COL_WARN
      or ((DATA.lastLapMs ~= nil and DATA.bestLapMs ~= nil and DATA.lastLapMs <= DATA.bestLapMs) and COL_OK or TH.text) },
    { 'BEST', (DATA.bestLapMs ~= nil) and fmtLap(DATA.bestLapMs) or '--:--.---', TH.accent },
  }
  local rowH = (h - pad - (pad + topH + 8 * U)) / 3
  for i = 1, 3 do
    local cy = y0 + pad + topH + 8 * U + (i - 0.5) * rowH
    txt('ui', 8.5 * U, 1.3 * U, function()
      tleft(rows[i][1], x0 + pad, cy, TH.dim)
    end)
    txt('num', math.min(rowH * 0.62, 15 * U), 0, function()
      tright(rows[i][2], x0 + w - pad, cy, rows[i][3])
    end)
  end
end

----------------------------------------------------------------------
-- 8.6 ТОПЛИВО
----------------------------------------------------------------------
local function fuelSize() return 210, 80 end

local function drawFuel(x0, y0, w, h)
  glass(x0, y0, x0 + w, y0 + h, R(h * 0.22))
  local pad = 13 * U
  local f = DATA.fuel

  txt('ui', 8.0 * U, 1.6 * U, function()
    tleft('FUEL', x0 + pad, y0 + pad + 1 * U, TH.dim)
  end)
  if DATA.lapsLeft ~= nil then
    txt('ui', 8.0 * U, 0.6 * U, function()
      tright(string.format('≈ %.0f КР', DATA.lapsLeft), x0 + w - pad, y0 + pad + 1 * U, TH.faint)
    end)
  end

  local valStr = (f ~= nil) and string.format('%.1f', f) or '—'
  local vw = measure('num', h * 0.34, valStr)
  txt('num', h * 0.34, 0, function()
    tleft(valStr, x0 + pad, y0 + h * 0.50, f ~= nil and TH.text or TH.faint)
  end)
  txt('ui', 8.5 * U, 1.0 * U, function()
    tleft('Л', x0 + pad + vw + 3 * U, y0 + h * 0.535, TH.dim)
  end)

  local frac = 0
  if f ~= nil then
    frac = sat(f / 60)
    if DATA.lapsLeft ~= nil then frac = sat(DATA.lapsLeft / 12) end
  end
  local col = frac < 0.12 and COL_HOT or (frac < 0.3 and COL_MID or TH.accent)
  bar(x0 + pad, y0 + h - pad - 5 * U, x0 + w - pad, y0 + h - pad - 0.5 * U, frac, col)
end

----------------------------------------------------------------------
-- 8.7 ПОВРЕЖДЕНИЯ
----------------------------------------------------------------------
local function dmgSize() return 210, 126 end

local DMG = { 'FL', 'FR', 'RL', 'RR' }
local DMG_OUT = {}
local dmgScale = nil

-- car.damage — массив; шкала бывает 0..1 или 0..100, определяем один раз
local function damageValues(car)
  local d = FIELD.damage(car)
  if d == nil then return nil end
  local ok = false
  for i = 0, 3 do
    local good, v = pcall(function() return d[i] end)
    if good and type(v) == 'number' then
      if dmgScale == nil then dmgScale = (v > 1.5) and 100 or 1 end
      DMG_OUT[i + 1] = sat(v / dmgScale)
      ok = true
    else
      DMG_OUT[i + 1] = nil
    end
  end
  if not ok then return nil end
  return DMG_OUT
end

local function drawDamage(x0, y0, w, h)
  glass(x0, y0, x0 + w, y0 + h, R(h * 0.18))
  local pad = 13 * U
  txt('ui', 8.0 * U, 1.6 * U, function()
    tleft('DAMAGE', x0 + pad, y0 + pad + 1 * U, TH.dim)
  end)

  local vals = damageValues(CAR)
  local cw = (w - pad * 2 - 8 * U) * 0.5
  for i = 1, 4 do
    local col = (i - 1) % 2
    local row = math.floor((i - 1) * 0.5)
    local bx = x0 + pad + col * (cw + 8 * U)
    local by = y0 + pad + 14 * U + row * 26 * U
    local v = vals and vals[i] or nil
    txt('ui', 7.5 * U, 1.0 * U, function()
      tleft(DMG[i], bx, by + 5 * U, TH.faint)
    end)
    txt('num', 9.5 * U, 0, function()
      tright(v and string.format('%.0f%%', v * 100) or '—', bx + cw, by + 5 * U,
        v and (v > 0.3 and COL_HOT or (v > 0.08 and COL_MID or TH.dim)) or TH.faint)
    end)
    bar(bx, by + 11 * U, bx + cw, by + 13.5 * U, v or 0, v and (v > 0.3 and COL_HOT or COL_MID) or TH.faint, 0.9)
  end
end

----------------------------------------------------------------------
-- 8.8 ИНДИКАТОРЫ (ABS / TC / HB / свет / пита)
----------------------------------------------------------------------
local IND_CH = {
  { 'ABS',   'abs',       function() return FIELD.abs(CAR) == true end },
  { 'TC',    'tc',        function() return FIELD.tc(CAR) == true end },
  { 'HB',    nil,         function() return (CAR.handbrake or 0) > 0.25 end },
  { 'LIGHT', 'lights',    function() return FIELD.lights(CAR) == true end },
  { 'PIT',   'pitlim',    function() return FIELD.pitLimiter(CAR) == true end },
}

local function indAvailable(base)
  if base == nil then return true end
  -- пока поле не проверено — считаем доступным, чтобы пилюли не мигали
  -- на первом кадре; реально отсутствующие отвалятся после пробы
  return CAP[base] ~= false
end

local IND_OUT = {}

local function indList()
  local out = IND_OUT
  local n = 0
  for i = 1, #IND_CH do
    local ch = IND_CH[i]
    if indAvailable(ch[2]) then
      n = n + 1
      out[n] = ch
      out[n]._active = ch[3]() and true or false
    end
  end
  return out, n
end

local function indSize()
  local list, n = indList()
  if n == 0 then return 0, 0 end
  local wsum = 0
  for i = 1, n do
    wsum = wsum + measure('ui', 9 * U, list[i][1], 1.3 * U) + 20 * U
  end
  return wsum + (n - 1) * 6 * U + 22 * U, 34
end

local function drawIndicators(x0, y0, w, h)
  local list, n = indList()
  if n == 0 then return end
  glass(x0, y0, x0 + w, y0 + h, R(h * 0.5), { noShadow = true, alpha = 0.85 })
  local pad = 11 * U
  local cx = x0 + pad
  local ph = h - pad * 2

  for i = 1, n do
    local ch = list[i]
    local tw = measure('ui', 9 * U, ch[1], 1.3 * U)
    local pw = tw + 16 * U
    local px0, px1 = cx, cx + pw
    local py0, py1 = y0 + pad, y0 + pad + ph
    local on = ch._active
    if on then
      if cfg.glow then
        ui.drawRectFilled(V(px0 - 2 * U, py0 - 2 * U), V(px1 + 2 * U, py1 + 2 * U),
          tint(TH.accent, 0.18), R(ph * 0.5 + 2 * U))
      end
      ui.drawRectFilled(V(px0, py0), V(px1, py1), tint(TH.accent, 0.92), R((py1 - py0) * 0.5))
      txt('ui', 9 * U, 1.3 * U, function()
        tcenter(ch[1], (px0 + px1) * 0.5, (py0 + py1) * 0.5, C(0.05, 0.03, 0.10, 1))
      end)
    else
      ui.drawRectFilled(V(px0, py0), V(px1, py1), C(1, 1, 1, 0.05), R((py1 - py0) * 0.5))
      txt('ui', 9 * U, 1.3 * U, function()
        tcenter(ch[1], (px0 + px1) * 0.5, (py0 + py1) * 0.5, TH.faint)
      end)
    end
    cx = px1 + 6 * U
  end
end

----------------------------------------------------------------------
-- 8.9 БРЕНД
----------------------------------------------------------------------
local function brandSize() return 212, 42 end

local function drawBrand(x0, y0, w, h)
  local a = TH.accent
  ui.drawRectFilled(V(x0, y0 + h * 0.18), V(x0 + 2.5 * U, y0 + h * 0.82), tint(a, 0.9), 2 * U)
  txt('bold', 15 * U, 2.2 * U, function()
    tleft('MILLENIUM', x0 + 9 * U, y0 + h * 0.36, TH.text)
  end)
  txt('ui', 8.0 * U, 1.2 * U, function()
    tleft('HUD · v' .. VERSION .. ' · SPOTIK', x0 + 9.5 * U, y0 + h * 0.74, TH.dim)
  end)
end

----------------------------------------------------------------------
-- 8.10 ОТДЕЛЬНАЯ ПЛАШКА ПЕРЕДАЧИ (наследие 1.4.x)
----------------------------------------------------------------------
local function gearSize() return 104, 142 end

local function drawGear(x0, y0, w, h)
  local frac = anim('rpm2', rpmFrac(CAR), 0.035)
  local flash = shiftState(frac)
  glass(x0, y0, x0 + w, y0 + h, R(h * 0.16), { glow = flash and cfg.glow })
  drawGearPlate(x0 + 8 * U, y0 + 8 * U, x0 + w - 8 * U, y0 + h - 8 * U, flash)
end

----------------------------------------------------------------------
-- 9. РЕЕСТР ВИДЖЕТОВ, РАСКЛАДКА, ПЕРЕТАСКИВАНИЕ
----------------------------------------------------------------------
local REG = {
  { id = 'speed',      key = 'hudSpeedo',  title = 'Спидометр',   size = speedSize, draw = drawSpeed },
  { id = 'gear',       key = 'hudGear',    title = 'Передача',    size = gearSize,  draw = drawGear },
  { id = 'pedals',     key = 'hudPedals',  title = 'Педали',      size = pedSize,   draw = drawPedals },
  { id = 'tyres',      key = 'hudTyres',   title = 'Шины',        size = tyreSize,  draw = drawTyres },
  { id = 'radar',      key = 'hudRadar',   title = 'Радар',       size = radarSize, draw = drawRadar },
  { id = 'session',    key = 'hudSession', title = 'Сессия',      size = sessSize,  draw = drawSession },
  { id = 'fuel',       key = 'hudFuel',    title = 'Топливо',     size = fuelSize,  draw = drawFuel },
  { id = 'damage',     key = 'hudDamage',  title = 'Повреждения', size = dmgSize,   draw = drawDamage },
  { id = 'indicators', key = 'hudInd',     title = 'Индикаторы',  size = indSize,   draw = drawIndicators },
  { id = 'brand',      key = 'hudBrand',   title = 'Подпись',     size = brandSize, draw = drawBrand },
}

local RECTS = {}   -- id -> { x0, y0, x1, y1, cx, cy, w, h }

-- Положение острова: центр задан в долях экрана, размер — в дизайн-пикселях.
-- Края поджимаются, чтобы остров не улетел за экран ни при каком разрешении.
local function layoutWidget(w)
  local dw, dh = w.size()
  if dw == nil or dh == nil or dw <= 1 or dh <= 1 then return nil end
  local pw, ph = dw * U, dh * U
  local hx, hy = pw * 0.5, ph * 0.5
  local fx, fy = posOf(w.id)
  local cx = math.clamp(fx * WS.x, hx + 3, WS.x - hx - 3)
  local cy = math.clamp(fy * WS.y, hy + 3, WS.y - hy - 3)
  return cx - hx, cy - hy, pw, ph, cx, cy
end

local function hitTest(mx, my)
  -- сверху вниз: последний нарисованный остров «ловит» мышь первым
  for i = #REG, 1, -1 do
    local rc = RECTS[REG[i].id]
    if rc and mx >= rc.x0 and mx <= rc.x1 and my >= rc.y0 and my <= rc.y1 then
      return REG[i], rc
    end
  end
  return nil, nil
end

local function dashLine(x0, y0, x1, y1, color, th)
  local dx, dy = x1 - x0, y1 - y0
  local len = math.sqrt(dx * dx + dy * dy)
  if len < 1 then return end
  local ux, uy = dx / len, dy / len
  local step = 8 * U
  local t = 0
  while t < len do
    local t2 = t + step * 0.55
    if t2 > len then t2 = len end
    ui.drawLine(V(x0 + ux * t, y0 + uy * t), V(x0 + ux * t2, y0 + uy * t2), color, th)
    t = t + step
  end
end

local function dashRect(rc, color, th)
  dashLine(rc.x0, rc.y0, rc.x1, rc.y0, color, th)
  dashLine(rc.x0, rc.y1, rc.x1, rc.y1, color, th)
  dashLine(rc.x0, rc.y0, rc.x0, rc.y1, color, th)
  dashLine(rc.x1, rc.y0, rc.x1, rc.y1, color, th)
end

----------------------------------------------------------------------
-- 9.1 РЕЖИМ РЕДАКТИРОВАНИЯ
----------------------------------------------------------------------
-- Почему теперь не «уезжает»:
--   окно HUD — одно, полноэкранное и стоит в (0, 0). Значит координаты
--   мыши и экранные координаты — это одно и то же число, а само окно
--   во время перетаскивания НЕ двигается. В 1.x окно ездило за мышью,
--   и позиция считалась из (позиция окна + позиция мыши), из-за чего
--   каждый кадр к сдвигу добавлялся один и тот же дельта-член —
--   панель ускорялась и улетала.
local EDIT = {
  id = nil, dx = 0, dy = 0,
  prevDown = false,
  idle = 0,
  lastX = nil, lastY = nil,
  guides = false,
}

local function snapValue(v, target, eps)
  if math.abs(v - target) < eps then return target, true end
  return v, false
end

local function drawEditor()
  local m = ui.mousePos()
  local down = ui.mouseDown(ui.MouseButton.Left)
  local mx, my = m.x, m.y

  -- авто-выход из режима при бездействии (мышь не двигалась 25 с)
  if EDIT.lastX ~= nil and (math.abs(mx - EDIT.lastX) > 0.5 or math.abs(my - EDIT.lastY) > 0.5) then
    EDIT.idle = 0
  else
    EDIT.idle = EDIT.idle + DT
  end
  EDIT.lastX, EDIT.lastY = mx, my
  if EDIT.idle > 25 then
    -- автовыход: не оставляем HUD в интерактивном режиме после раскладки
    EDIT.idle, EDIT.id, EDIT.guides = 0, nil, false
    cfg.editMode = false
    return
  end

  local hovered, hoveredRect = hitTest(mx, my)

  -- рамки островов
  for i = 1, #REG do
    local w = REG[i]
    local rc = RECTS[w.id]
    if rc then
      local isHover = (hovered ~= nil and hovered.id == w.id)
      local isDrag = (EDIT.id == w.id)
      local col = isDrag and tint(TH.accent, 0.95)
        or (isHover and tint(TH.accent, 0.70) or tint(TH.accent, 0.30))
      dashRect(rc, col, math.max(1, 1.1 * U))
      if isHover or isDrag then
        local label = w.title
        local lw = measure('ui', 9 * U, label, 0.6 * U) + 12 * U
        ui.drawRectFilled(V(rc.x0, rc.y0 - 16 * U), V(rc.x0 + lw, rc.y0 - 2 * U),
          tint(TH.accent, 0.92), 3 * U)
        txt('ui', 9 * U, 0.6 * U, function()
          tleft(label, rc.x0 + 6 * U, rc.y0 - 9 * U, C(0.05, 0.03, 0.10, 1))
        end)
      end
    end
  end

  -- старт перетаскивания
  if down and not EDIT.prevDown and hovered ~= nil and hoveredRect ~= nil then
    EDIT.id = hovered.id
    EDIT.dx = mx - hoveredRect.cx
    EDIT.dy = my - hoveredRect.cy
    EDIT.idle = 0
  end

  -- само перетаскивание: позиция = мышь минус захват (никакого накопления дельт)
  if EDIT.id ~= nil and down then
    local w = nil
    for i = 1, #REG do
      if REG[i].id == EDIT.id then w = REG[i] break end
    end
    if w ~= nil then
      local dw, dh = w.size()
      if dw ~= nil and dw > 1 then
        local hx, hy = dw * U * 0.5, dh * U * 0.5
        local cx = math.clamp(mx - EDIT.dx, hx + 3, WS.x - hx - 3)
        local cy = math.clamp(my - EDIT.dy, hy + 3, WS.y - hy - 3)
        setPos(w.id, cx / WS.x, cy / WS.y)
      end
    end
    EDIT.guides = true
    EDIT.idle = 0
  elseif EDIT.id ~= nil and not down then
    -- отпустили: магнит к центру/осям
    local w = nil
    for i = 1, #REG do
      if REG[i].id == EDIT.id then w = REG[i] break end
    end
    if w ~= nil then
      local fx, fy = posOf(w.id)
      local nx, sx = snapValue(fx, 0.5, 0.004)
      local ny, sy = snapValue(fy, 0.5, 0.004)
      local ny2, sy2 = snapValue(fy, 0.87, 0.004)
      if sy2 then ny, sy = ny2, true end
      setPos(w.id, nx, ny)
      local _ = sx or sy
    end
    EDIT.id = nil
    EDIT.guides = false
  end
  EDIT.prevDown = down

  -- направляющие
  if EDIT.guides then
    local g = tint(TH.accent, 0.35)
    dashLine(WS.x * 0.5, 0, WS.x * 0.5, WS.y, g, math.max(1, 1.0 * U))
    dashLine(0, WS.y * 0.5, WS.x, WS.y * 0.5, tint(TH.accent, 0.20), math.max(1, 1.0 * U))
  end

  -- подсказка сверху
  local hintStr = 'РЕДАКТИРОВАНИЕ · ТАЩИТЕ ОСТРОВА МЫШЬЮ · ВЫХОД — ГАЛОЧКА В НАСТРОЙКАХ'
  local hw = measure('ui', 9.5 * U, hintStr, 1.1 * U)
  local px0 = WS.x * 0.5 - hw * 0.5 - 18 * U
  local px1 = WS.x * 0.5 + hw * 0.5 + 18 * U
  local py0, py1 = 6 * U, 30 * U
  ui.drawRectFilled(V(px0, py0), V(px1, py1), C(0.03, 0.035, 0.07, 0.92), 16 * U)
  ui.drawRectFilled(V(px0, py0), V(px1, py0 + 1.2 * U), tint(TH.accent, 0.5))
  txt('ui', 9.5 * U, 1.1 * U, function()
    tcenter(hintStr, WS.x * 0.5, (py0 + py1) * 0.5, TH.text)
  end)
end

----------------------------------------------------------------------
-- 10. ГЛАВНЫЙ КАДР
----------------------------------------------------------------------
local function clearAnim()
  for k in pairs(ANIM) do ANIM[k] = nil end
end

local lastScale = nil

function script.drawHud(dt)
  -- CSP передаёт dt, но на старых сборках/в реплеях он может быть nil:
  -- без подстраховки анимации замирали бы навсегда
  DT = math.clamp(tonumber(dt) or (1 / 60), 0, 0.1)
  T  = T + DT
  WS = ui.windowSize()
  U  = (WS.y / 1080) * math.clamp(cfg.scale or 1, 0.5, 2.0)
  refreshTheme()

  CAR = ac.getCar(0)

  if CAR == nil or CAR.position == nil then
    -- загрузка, реплей без машины, выход из сессии — тихо ничего не рисуем
    for k in pairs(RECTS) do RECTS[k] = nil end
    DATA.nearCount, DATA.nearest = 0, nil
    return
  end

  refreshLimit(CAR)
  updateSession(CAR)
  updateRadar(CAR)

  if cfg.editMode and not EDIT.wasOn then
    -- вход в режим редактирования: обнуляем простой и «забываем» мышь
    EDIT.idle, EDIT.lastX, EDIT.lastY = 0, nil, nil
  end
  EDIT.wasOn = cfg.editMode == true

  ui.transparentWindow('##millenium_hud', vec2(0, 0), WS, true, cfg.editMode == true, function()
    for i = 1, #REG do
      local w = REG[i]
      if cfg[w.key] then
        local x0, y0, pw, ph, cx, cy = layoutWidget(w)
        if x0 ~= nil then
          local rc = RECTS[w.id]
          if rc == nil then
            rc = {}
            RECTS[w.id] = rc
          end
          rc.x0, rc.y0, rc.x1, rc.y1 = x0, y0, x0 + pw, y0 + ph
          rc.cx, rc.cy, rc.w, rc.h = cx, cy, pw, ph
          w.draw(x0, y0, pw, ph)
        else
          RECTS[w.id] = nil
        end
      else
        RECTS[w.id] = nil
      end
    end

    if cfg.editMode then
      drawEditor()
    end
  end)

  lastScale = cfg.scale
end

----------------------------------------------------------------------
-- 11. ПРОФИЛИ РАСКЛАДКИ
----------------------------------------------------------------------
local function applyPositions(def)
  for id, p in pairs(def) do
    setPos(id, p[1], p[2])
  end
end

local function setAll(flag)
  cfg.hudSpeedo, cfg.hudPedals, cfg.hudTyres, cfg.hudRadar = flag, flag, flag, flag
  cfg.hudSession, cfg.hudFuel, cfg.hudDamage, cfg.hudInd = flag, flag, flag, flag
  cfg.hudBrand, cfg.hudGear = flag, false
end

local PRESETS = {
  {
    name = 'Гонка',
    apply = function()
      setAll(false)
      cfg.hudSpeedo, cfg.hudPedals, cfg.hudTyres = true, true, true
      cfg.hudRadar, cfg.hudSession, cfg.hudFuel = true, true, true
      cfg.hudInd, cfg.hudBrand = true, true
      applyPositions(DEFAULT_POS)
    end,
  },
  {
    name = 'Минимал',
    apply = function()
      setAll(false)
      cfg.hudSpeedo, cfg.hudRadar, cfg.hudInd = true, true, true
      setPos('speed', 0.500, 0.895)
      setPos('radar', 0.500, 0.700)
      setPos('indicators', 0.500, 0.048)
      cfg.radarRange = 20
    end,
  },
  {
    name = 'Трек-день',
    apply = function()
      setAll(false)
      cfg.hudSpeedo, cfg.hudPedals, cfg.hudTyres = true, true, true
      cfg.hudRadar, cfg.hudBrand = true, true
      applyPositions(DEFAULT_POS)
    end,
  },
  {
    name = 'Сброс',
    apply = function()
      applyPositions(DEFAULT_POS)
    end,
  },
}

----------------------------------------------------------------------
-- 12. ОКНО НАСТРОЕК
----------------------------------------------------------------------
local function hint(text)
  local p = pushUI('ui', 12)
  ui.pushStyleColor(ui.StyleColor.Text, TH.dim)
  ui.text(text)
  ui.popStyleColor()
  popUI(p)
end

local function toggle(key, title, hintText)
  if ui.checkbox(title .. '##' .. key, cfg[key] == true) then
    cfg[key] = not cfg[key]
  end
  if hintText then hint(hintText) end
end

local function sectionTitle(text)
  ui.offsetCursorY(6)
  local p = pushUI('bold', 18)
  ui.pushStyleColor(ui.StyleColor.Text, TH.soft)
  ui.text(text)
  ui.popStyleColor()
  popUI(p)
  ui.separator()
end

local SPEED_STYLES = { 'Полоса RPM', 'Круговой прибор', 'Минимал' }
local STYLE_KEYS = { 'bar', 'ring', 'minimal' }

local function styleIndex()
  for i = 1, #STYLE_KEYS do
    if STYLE_KEYS[i] == cfg.speedoStyle then return i end
  end
  return 1
end

local function tabWidgets()
  sectionTitle('Профили')
  for i = 1, #PRESETS do
    if i > 1 then ui.sameLine(0, 6) end
    if ui.button(PRESETS[i].name .. '##preset' .. i, vec2(88, 24)) then
      PRESETS[i].apply()
      clearAnim()
    end
  end

  sectionTitle('Виджеты')
  toggle('hudSpeedo', 'Спидометр', 'Скорость, передача и тахометр в одном острове.')
  if cfg.hudSpeedo then
    local idx, changed = ui.combo('Стиль##speedostyle', styleIndex(), 0, SPEED_STYLES)
    if changed and type(idx) == 'number' then cfg.speedoStyle = STYLE_KEYS[idx] end
    toggle('showGearInline', 'Передача в острове', 'Передача плашкой справа от скорости.')
    toggle('shiftFlash', 'Вспышка у красной зоны', 'Пульсирующая кромка и подсветка передачи.')
    if cfg.shiftFlash then
      cfg.shiftPoint = ui.slider('Порог вспышки##shiftp', cfg.shiftPoint * 100, 80, 99, 'Вспышка с %.0f%%') / 100
    end
    cfg.rpmSegments = math.floor(ui.slider('Сегментов тахометра##seg', cfg.rpmSegments, 0, 20,
      'Сегментов: %.0f (0 — авто)') + 0.5)
  end

  toggle('hudGear', 'Отдельная плашка передачи', 'Наследие 1.4.x — крупная цифра в собственной плашке.')
  toggle('hudPedals', 'Педали', 'GAS / BRK / CLT / HB. CLT показывает нажатие.')
  if cfg.hudPedals then
    toggle('pedalPct', 'Проценты у шкал', nil)
    toggle('pedalColors', 'Семантические цвета', 'Выкл — все шкалы в акцентном цвете.')
  end
  toggle('hudTyres', 'Шины', 'Температура ядра, износ (если CSP отдаёт), индикация цветом.')
  if cfg.hudTyres then
    toggle('tyreWearInverted', 'Инвертировать износ', 'Если шкала износа смотрит не туда — переключите.')
  end
  toggle('hudRadar', 'Радар машин', 'Стеклянный диск: машины вокруг, предупреждения по сторонам.')
  toggle('hudSession', 'Сессия', 'Позиция, круги, CUR / LAST / BEST.')
  toggle('hudFuel', 'Топливо', 'Литры, полоса и оценка остатка кругов.')
  toggle('hudDamage', 'Повреждения', 'Требует car.damage в сборке CSP — проверьте вкладку «Диагностика».')
  toggle('hudInd', 'Индикаторы', 'ABS / TC / HB / свет / пита — только доступные в вашей сборке.')
  toggle('hudBrand', 'Подпись MILLENIUM', 'Знак в углу экрана.')
end

local function tabRadar()
  sectionTitle('Радар')
  toggle('hudRadar', 'Показывать радар', nil)
  cfg.radarRange = ui.slider('Дальность##rr', cfg.radarRange, 8, 60, 'Дальность: %.0f м')
  toggle('radarRotate', 'По машине', 'Вкл — диск вращается вместе с машиной, выкл — «север сверху».')
  toggle('radarWarn', 'Предупреждения', 'Дуги и шевроны слева/справа, когда машина в слепой зоне.')
  toggle('radarLabels', 'Дистанция у машин', 'Цифры метров у блипов.')
  toggle('radarHideAlone', 'Тускнеть без машин', 'Когда рядом никого — диск становится полупрозрачным.')
  cfg.radarBlipScale = ui.slider('Размер блипов##bs', cfg.radarBlipScale * 100, 60, 160, 'Размер: %.0f%%') / 100
  hint('Блип — короткий штрих вдоль курса машины. Цвет: акцент → жёлтый (< 9 м) → красный (< 3.5 м).')
end

local function tabLook()
  sectionTitle('Стекло и масштаб')
  toggle('bgEnabled', 'Подложка островов', 'Выкл — только цифры поверх игры, без стекла.')
  cfg.opacity = ui.slider('Плотность##op', cfg.opacity * 100, 10, 100, 'Плотность стекла: %.0f%%') / 100
  cfg.scale   = ui.slider('Масштаб##sc', cfg.scale * 100, 60, 160, 'Масштаб: %.0f%%') / 100
  cfg.radius  = ui.slider('Скругление##rad', cfg.radius * 100, 30, 180, 'Скругление: %.0f%%') / 100
  toggle('shadow', 'Тень', nil)
  toggle('sheen', 'Блик по кромке', 'Тонкая светлая полоса сверху — «стекло».')
  toggle('glow', 'Акцентное свечение', 'Мягкий ореол у активных элементов.')

  sectionTitle('Акцент')
  local names = {}
  for i = 1, #ACCENTS do names[i] = ACCENTS[i][1] end
  local idx, changed = ui.combo('Палитра##acc', cfg.accentPreset, 0, names)
  if changed and type(idx) == 'number' then
    cfg.accentPreset = idx
    cfg.accentCustom = false
  end
  local col = rgbm(cfg.accentR, cfg.accentG, cfg.accentB, 1)
  if ui.colorPicker('Свой цвет##accc', col) then
    cfg.accentR, cfg.accentG, cfg.accentB = col.r, col.g, col.b
    cfg.accentCustom = true
  end
  if cfg.accentCustom and ui.button('Вернуть палитру##accreset', vec2(-1, 22)) then
    cfg.accentCustom = false
  end
end

local function tabLayout()
  sectionTitle('Расположение')
  toggle('editMode', 'Режим редактирования', 'Включает перетаскивание островов мышью. Вне этого режима HUD не перехватывает клики.')
  if cfg.editMode then
    ui.pushStyleColor(ui.StyleColor.Text, TH.accent)
    ui.text('Редактирование включено: тащите острова прямо в игре.')
    ui.popStyleColor()
    hint('Автовыход через 25 секунд бездействия мыши.')
  end
  if ui.button('Сбросить раскладку##resetpos', vec2(-1, 24)) then
    applyPositions(DEFAULT_POS)
  end
  hint('Позиции хранятся в долях экрана — раскладка не ломается при смене разрешения.')

  sectionTitle('Текущие координаты')
  for i = 1, #REG do
    local w = REG[i]
    if cfg[w.key] then
      local fx, fy = posOf(w.id)
      local rc = RECTS[w.id]
      local size = rc and string.format('%.0f×%.0f px', rc.w, rc.h) or '—'
      ui.pushStyleColor(ui.StyleColor.Text, TH.dim)
      ui.text(string.format('%s · %.3f / %.3f · %s', w.title, fx, fy, size))
      ui.popStyleColor()
    end
  end
end

local function tabDiag()
  sectionTitle('Сборка')
  local pairsList = {
    { 'CSP DWrite-текст', DWRITE },
    { 'drawTextClipped', clippedOk },
    { 'Разрешение', string.format('%.0f×%.0f', WS.x, WS.y) },
    { 'Дизайн-пиксель U', string.format('%.3f', U) },
    { 'Машина игрока', CAR ~= nil and tostring(CAR.index) or 'нет' },
    { 'Машин в сессии', tostring(DATA.carCount) },
    { 'Машин рядом', tostring(DATA.nearCount) },
    { 'Лимитер', tostring(math.floor(DATA.limit + 0.5)) },
  }
  for i = 1, #pairsList do
    local it = pairsList[i]
    local val = it[2]
    local txtVal = type(val) == 'boolean' and (val and 'да' or 'нет') or tostring(val)
    ui.pushStyleColor(ui.StyleColor.Text, (type(val) == 'boolean') and (val and COL_OK or COL_HOT) or TH.dim)
    ui.text(it[1] .. ': ' .. txtVal)
    ui.popStyleColor()
  end

  sectionTitle('Поля телеметрии')
  hint('Проверяется один раз при старте. «нет» — сборка CSP не отдаёт поле, виджет покажет «—».')
  if #CAPORDER == 0 then
    hint('Ещё не проверялось — сядьте в машину.')
  end
  for i = 1, #CAPORDER do
    local k = CAPORDER[i]
    local ok = CAP[k] == true
    ui.pushStyleColor(ui.StyleColor.Text, ok and COL_OK or TH.faint)
    ui.text((ok and '+ ' or '- ') .. (CAPTITLE[k] or k) .. (ok and '' or '  (нет)'))
    ui.popStyleColor()
  end
end

function script.windowMain(dt)
  refreshTheme()
  WS = ui.windowSize()

  local pH = pushUI('bold', 20)
  ui.pushStyleColor(ui.StyleColor.Text, TH.accent)
  ui.text('MILLENIUM HUD')
  ui.popStyleColor()
  popUI(pH)
  ui.sameLine(0, 8)
  local pS = pushUI('ui', 12)
  ui.pushStyleColor(ui.StyleColor.Text, TH.dim)
  ui.text('v' .. VERSION .. ' · Hello from Spotik')
  ui.popStyleColor()
  popUI(pS)
  ui.separator()

  local okTabs = pcall(function()
    ui.tabBar('##millenium_tabs', function()
      ui.tabItem('Виджеты', tabWidgets)
      ui.tabItem('Радар', tabRadar)
      ui.tabItem('Вид', tabLook)
      ui.tabItem('Раскладка', tabLayout)
      ui.tabItem('Диагностика', tabDiag)
    end)
  end)
  if not okTabs then
    -- очень старые сборки CSP без tabBar — рисуем всё подряд
    tabWidgets(); ui.separator(); tabRadar(); ui.separator()
    tabLook(); ui.separator(); tabLayout(); ui.separator(); tabDiag()
  end

end
