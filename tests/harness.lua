-- Minimal Q-SYS runtime mock + simulated Christie Access panel
local PLUGIN_PATH, PROPS_OVERRIDE, SCENARIO = ...

local now = 0
local events = {}
local function at(t, f) events[#events + 1] = { t = t, f = f, seq = #events } end
local function runUntil(tEnd)
  while true do
    table.sort(events, function(a, b) if a.t == b.t then return a.seq < b.seq end return a.t < b.t end)
    local e = events[1]
    if not e or e.t > tEnd then break end
    table.remove(events, 1)
    now = e.t
    e.f()
  end
  now = tEnd
end
os.time = function() return math.floor(now) end
local LOG = {}
print = function(...) local t = {} for i = 1, select("#", ...) do t[#t+1] = tostring((select(i, ...))) end LOG[#LOG+1] = ("[%7.2f] "):format(now) .. table.concat(t, " ") end

-- Timer
Timer = {}
function Timer.New()
  local tm = { gen = 0 }
  function tm:Start(iv)
    self.gen = self.gen + 1
    local g = self.gen
    local function fire() if self.gen == g then at(now + iv, function() if self.gen == g then fire(); if self.EventHandler then self.EventHandler(self) end end end) end end
    fire()
  end
  function tm:Stop() self.gen = self.gen + 1 end
  return tm
end
function Timer.CallAfter(f, t) at(now + t, f) end

-- Simulated panel
local panel = {
  standby = true, mute = false, volume = 30, source = "VGA",
  ignorePower = 0, ignoreAll = false, dropMuteReply = 0, ignoreMute = 0, unlocked = false,
  toggles = 0, rx = {},
}
local CODES = { ["7"] = "HDMI1", ["8"] = "HDMI2", ["12"] = "VGA", ["18"] = "DVI", ["19"] = "DP", ["20"] = "OPS" }
local function panelHandle(cmd, reply)
  panel.rx[#panel.rx + 1] = cmd
  if panel.ignoreAll then return end
  if cmd:match("^SETUSERSECLEVEL ADMIN 0000$") then panel.unlocked = true; return reply("#*Security level set") end
  if not panel.unlocked then return reply("#*Locked") end
  if cmd == "GETQUICKSTANDBY" then return reply("#*Quick Standby is " .. (panel.standby and "on." or "off.")) end
  local v = cmd:match("^SETQUICKSTANDBY (%a+)$")
  if v then
    if panel.ignorePower > 0 then panel.ignorePower = panel.ignorePower - 1; return end
    local was = panel.standby
    panel.standby = (v == "on")
    if was and not panel.standby then -- waking resets audio to stored defaults
      panel.mute, panel.volume, panel.source = false, 30, "VGA"
    end
    return reply("#*Set Quick Standby " .. v)
  end
  if panel.standby then return end -- audio/video commands ignored in standby
  if cmd == "GETMUTE" then return reply("#*MUTE " .. (panel.mute and "ON" or "OFF")) end
  if cmd == "SETMUTE" then
    if panel.ignoreMute > 0 then panel.ignoreMute = panel.ignoreMute - 1; return end
    panel.mute = not panel.mute; panel.toggles = panel.toggles + 1
    if panel.dropMuteReply > 0 then panel.dropMuteReply = panel.dropMuteReply - 1; return end
    return reply("#*MUTE " .. (panel.mute and "ON" or "OFF"))
  end
  if cmd == "GETVOLUME" then return reply("#*volume level is " .. panel.volume) end
  local n = cmd:match("^STV (%d+)$")
  if n then panel.volume = tonumber(n); return reply("#*Volume set level= " .. n) end
  if cmd == "GETSOURCE" then return reply("#*source is " .. panel.source) end
  local c = cmd:match("^SELECTSOURCE (%d+)$")
  if c then if CODES[c] then panel.source = CODES[c] end; return reply("#*select " .. c .. " source") end
  return reply("#*Invalid command")
end

TcpSocket = { Events = { Connected = "Connected", Data = "Data", Closed = "Closed", Error = "Error", Timeout = "Timeout", Reconnect = "Reconnect" },
  EOL = { Any = "Any" } }
function TcpSocket.New()
  local s = { IsConnected = false, buf = "" }
  function s:Connect(ip, port)
    at(now + 0.1, function() self.IsConnected = true; self.EventHandler(self, "Connected") end)
  end
  function s:Disconnect() self.IsConnected = false end
  function s:Write(data)
    for line in data:gmatch("(.-)\r\n") do
      panelHandle(line, function(r)
        at(now + 0.05, function() self.buf = self.buf .. r .. "\r\n"; self.EventHandler(self, "Data") end)
      end)
    end
  end
  function s:ReadLine()
    local l, rest = self.buf:match("^(.-)\r?\n(.*)$")
    if l then self.buf = rest end
    return l
  end
  return s
end

-- Load plugin (design-time part). Clear runtime globals left by a previous run,
-- otherwise this first load would also start the runtime section.
Controls, Properties = nil, nil
local chunk = assert(loadfile(PLUGIN_PATH, "t", _ENV))
chunk() -- Controls is nil here: defines design functions only

-- Build properties
local props = {}
for _, p in ipairs(GetProperties()) do props[p.Name] = { Value = p.Value } end
for k, v in pairs(PROPS_OVERRIDE) do props[k].Value = v end
props["page_index"] = { Value = 1 }
RectifyProperties(props)
for i = 1, #PageNames do props.page_index.Value = i; local l, g = GetControlLayout(props); assert(type(l) == "table" and type(g) == "table") end
local ctlDefs = GetControls(props)
GetPages(props); GetPrettyName(props); GetColor(props)

-- Controls mock
local function NewControl(def)
  local raw = { Value = 0, String = "", IsDisabled = false, Choices = {} }
  local c = {}
  setmetatable(c, {
    __index = function(_, k)
      if k == "Boolean" then return raw.Value ~= 0 end
      return raw[k]
    end,
    __newindex = function(_, k, v)
      if k == "Boolean" then raw.Value = v and 1 or 0; raw.String = v and "true" or "false"
      elseif k == "Value" then raw.Value = v; if def.ControlType ~= "Indicator" or def.IndicatorType ~= "Status" then raw.String = tostring(v) end
      else raw[k] = v end
    end,
  })
  return c
end
Controls = {}
for _, d in ipairs(ctlDefs) do Controls[d.Name] = NewControl(d) end
Controls["IP Address"].String = "10.246.60.23"
Properties = props

-- user action helper (sets control then fires handler, like a touch screen)
function press(name) Controls[name].EventHandler(Controls[name]) end
function setCtl(name, field, v) Controls[name][field] = v; Controls[name].EventHandler(Controls[name]) end

if SCENARIO == "defaults_boot" then panel.standby = false; panel.volume = 30; panel.source = "VGA" end
if SCENARIO:find("^defaults") then
  Controls["Apply Input On Power-On"].Boolean = true
  Controls["Power-On Input"].String = "HDMI2"
  Controls["Apply Audio On Power-On"].Boolean = true
  Controls["Power-On Volume"].Value = 15
  Controls["Power-On Mute"].Boolean = true
end

if SCENARIO == "pin" then Controls.Password.String = "1234" end

chunk() -- runtime part

local function st() return ("status=%d '%s'"):format(Controls.Status.Value, Controls.Status.String) end
local function state() return ("panel: standby=%s mute=%s vol=%d src=%s toggles=%d"):format(tostring(panel.standby), tostring(panel.mute), panel.volume, panel.source, panel.toggles) end

local out = {}
local function check(name, cond) out[#out + 1] = (cond and "PASS " or "FAIL ") .. name end

local S = SCENARIO
runUntil(2)
check("connected & polled", S == "pin" or (Controls.Connected.Boolean and Controls["Power State"].Boolean == (S == "defaults_boot")))
check("PIN defaults to 0000", S == "pin" or Controls.Password.String == "0000")

if S == "power_retry" then
  panel.ignorePower = 2
  press("Power On")
  runUntil(40)
  check("powered on after ignored cmds", panel.standby == false and Controls["Power State"].Boolean)
  check("status OK", Controls.Status.Value == 0)
  out[#out+1] = st()
  press("Power Off"); runUntil(60)
  check("standby confirmed", panel.standby == true and Controls.Status.Value == 0)
  out[#out+1] = st()
elseif S == "power_fail" then
  panel.ignorePower = 1000
  press("Power On")
  runUntil(120)
  check("fault raised", Controls.Status.Value == 2)
  out[#out+1] = st()
  local n = 0 for _, c in ipairs(panel.rx) do if c == "SETQUICKSTANDBY off" then n = n + 1 end end
  check("sent exactly max attempts (" .. n .. ")", n == Properties["Max Attempts"].Value)
elseif S == "forced" then
  panel.dropMuteReply = 1  -- toggle happens but reply lost: must not double toggle
  press("Power On")
  runUntil(40)
  out[#out+1] = state(); out[#out+1] = st()
  check("forced mute applied", panel.mute == true)
  check("forced volume applied", panel.volume == 0)
  check("forced input applied", panel.source == "HDMI1")
  check("mute toggled exactly once", panel.toggles == 1)
  -- someone unmutes with the remote; plugin should re-mute on next poll
  panel.mute = false
  runUntil(100)
  check("re-muted after drift", panel.mute == true)
  -- user tries to change things: forced, so ignored
  setCtl("Input", "String", "DP"); setCtl("Volume", "Value", 50); runUntil(110)
  check("user changes ignored when forced", panel.source == "HDMI1" and panel.volume == 0)
  -- standby, then wake: audio resets on panel, plugin re-applies
  press("Power Off"); runUntil(140); press("Power On"); runUntil(190)
  out[#out+1] = state(); out[#out+1] = st()
  check("re-applied after wake", panel.mute and panel.volume == 0 and panel.source == "HDMI1")
  check("status OK", Controls.Status.Value == 0)
elseif S == "user" then
  press("Power On"); runUntil(30)
  setCtl("Input", "String", "DP"); runUntil(40)
  check("input DP", panel.source == "DP" and Controls.Input.String == "DP")
  setCtl("Volume", "Value", 41.6); runUntil(50)
  check("volume 42", panel.volume == 42)
  panel.ignoreMute = 2
  setCtl("Mute", "Boolean", true); runUntil(80)
  check("mute on after ignored toggles", panel.mute == true and panel.toggles == 1)
  setCtl("Mute", "Boolean", false); runUntil(100)
  check("mute off", panel.mute == false and panel.toggles == 2)
  out[#out+1] = state(); out[#out+1] = st()
  check("status OK", Controls.Status.Value == 0)
elseif S == "defaults" then
  press("Power On"); runUntil(40)
  out[#out+1] = state(); out[#out+1] = st()
  check("defaults applied on power on", panel.source == "HDMI2" and panel.volume == 15 and panel.mute)
  check("mute toggled once", panel.toggles == 1)
  -- user changes after power-on are kept (not forced)
  setCtl("Input", "String", "DP"); setCtl("Mute", "Boolean", false); setCtl("Volume", "Value", 60); runUntil(80)
  check("user changes kept", panel.source == "DP" and panel.volume == 60 and not panel.mute)
  runUntil(140)
  check("still user values after polls", panel.source == "DP" and panel.volume == 60 and not panel.mute)
  -- standby by plugin, then woken by IR remote (panel resets to VGA/30/unmuted)
  press("Power Off"); runUntil(170)
  panel.standby = false; panel.mute, panel.volume, panel.source = false, 30, "VGA"
  runUntil(230)
  out[#out+1] = state(); out[#out+1] = st()
  check("defaults re-applied after remote wake", panel.source == "HDMI2" and panel.volume == 15 and panel.mute)
  check("status OK", Controls.Status.Value == 0)
elseif S == "defaults_with_forced_mute" then
  Controls["Power-On Mute"].Boolean = false   -- would unmute, but mute is forced
  press("Power On"); runUntil(60)
  out[#out+1] = state(); out[#out+1] = st()
  check("volume/input defaults applied", panel.source == "HDMI2" and panel.volume == 15)
  check("forced mute wins over default", panel.mute and panel.toggles == 1)
  check("power-on mute control disabled", Controls["Power-On Mute"].IsDisabled)
elseif S == "pin" then
  runUntil(60)
  out[#out+1] = st()
  check("wrong PIN: no valid replies flagged", Controls.Status.Value == 1 and Controls.Status.String:find("PIN") ~= nil)
  check("wrong PIN sent", panel.rx[1] == "SETUSERSECLEVEL ADMIN 1234")
  setCtl("Password", "String", "0000"); runUntil(65)
  out[#out+1] = st()
  check("correct PIN: recovers immediately", Controls.Status.Value == 0 and panel.unlocked)
  press("Power On"); runUntil(90)
  check("control works after PIN change", panel.standby == false)
elseif S == "defaults_boot" then
  runUntil(60)
  out[#out+1] = state(); out[#out+1] = st()
  check("no defaults when found already on", panel.source == "VGA" and panel.volume == 30 and not panel.mute)
  press("Power On"); runUntil(100)
  check("Power On press re-applies defaults", panel.source == "HDMI2" and panel.volume == 15 and panel.mute)
end

return table.concat(out, "\n") .. "\n--- log tail ---\n" .. table.concat(LOG, "\n", math.max(1, #LOG - 25))
