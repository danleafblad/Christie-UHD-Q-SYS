-- Runs the plugin against a simulated Christie Access panel.
-- Usage (from the repo root, Lua 5.3 or newer):  lua tests/run_tests.lua
local realPrint = print
local SCENARIOS = {
  { "power_retry", { ["Debug Output"] = true } },
  { "power_fail",  {} },
  { "forced", { ["Debug Output"] = true } },
  { "forced_boot", { ["Debug Output"] = true } },
  { "force_toggle", { ["Debug Output"] = true } },
  { "user", { ["Debug Output"] = true } },
  { "pin", { ["Debug Output"] = true } },
}

local failures = 0
for _, s in ipairs(SCENARIOS) do
  local harness = assert(loadfile("tests/harness.lua"))
  local ok, out = pcall(harness, "ChristieDisplayControl.qplug", s[2], s[1])
  print = realPrint
  realPrint("===== " .. s[1])
  if not ok then
    failures = failures + 1
    realPrint("ERROR " .. tostring(out))
  else
    local results, log = out:match("^(.-)\n%-%-%- log tail %-%-%-\n(.*)$")
    realPrint(results)
    local _, n = results:gsub("FAIL ", "")
    if n > 0 then
      failures = failures + n
      realPrint("--- log tail ---\n" .. log)
    end
  end
end
realPrint(failures == 0 and "\nAll scenarios passed." or ("\n" .. failures .. " failure(s)."))
os.exit(failures == 0 and 0 or 1)
