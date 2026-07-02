-- Minimal reference plugin entry: a bar widget that shows a configurable label
-- and glyph, counts clicks, and accepts IPC to change its text at runtime.
--
-- Demonstrates the capability surface:
--   barWidget.*          presentation (text / glyph / tooltip)
--   barWidget.getConfig  settings (seeded from the manifest; single-arg, no fallback)
--   noctalia.tr / trp    translation against this plugin's translations/<lang>.json
--   noctalia.readFile    filesystem, resolved relative to the plugin's own dir
--   noctalia.http        async HTTP (off-thread; response delivered back as a callback)
--   noctalia.state.*     shared data published by this plugin's [[service]] (ticker.luau)
--   noctalia.notify      host notification
--   onIpc                shell-triggered events
--
-- Drive it from the shell:
--   noctalia msg plugin noctalia/example:hello focused set "Hi there"
--   noctalia msg plugin noctalia/example:hello focused fetch "https://example.com"

local label = barWidget.getConfig("label")
local glyph = barWidget.getConfig("glyph")
local showGlyph = barWidget.getConfig("show_glyph")
local showLabel = barWidget.getConfig("show_label")
local updateCommand = barWidget.getConfig("update_cmd")
local checkUpdateCommand = barWidget.getConfig("check_update_cmd")
local updateAvailable = false

local clicks = 0
local dataNote = noctalia.readFile("data.txt") or "(no data file)"
local tick = noctalia.state.get("tick") or 0


local function render()
  local on = true
  barWidget.setGlyph(glyph)
  if showGlyph then
    if updateAvailable then
      barWidget.setVisible(true)
    else
      barWidget.setVisible(false)
    end
  end
  if showLabel then
    barWidget.setText(label)
  end
  barWidget.setTooltip(`{noctalia.trp("clicks", clicks)} — {dataNote} — service tick {tick}`)
end

-- Live updates from the plugin's background service (ticker.luau).
noctalia.state.watch("tick", function(value)
  tick = value
  render()
end)
foundUpdate = false

function checkForUpdates()
  -- noctalia.runAsync("if paru -Qu | grep -q . || flatpak remote-ls --updates 2>/dev/null | grep -q .; then echo 1; else echo 0; fi", function(ret)
  noctalia.runAsync(checkUpdateCommand, function(ret)
    out = ret['exitCode']
    if out and out == 0 then
      foundUpdate = true
    else
      foundUpdate = false
    end
  end)
  updateAvailable = foundUpdate
end

-- Called on widget interval
function update()
  noctalia.setUpdateInterval(1000)
  checkForUpdates()
  render()
end

function onClick()
  --noctalia.runInTerminal("omarchy-update")
  noctalia.runInTerminal(updateCommand)
  render()
end

function onIpc(event, payload)
  if event == "set" then
    label = payload
    render()
  elseif event == "fetch" then
    -- Async: the request runs off-thread and the callback fires when it lands.
    noctalia.http({ url = payload }, function(res)
      if res.ok then
        noctalia.notify(noctalia.tr("title"), `HTTP {res.status} — {#res.body} bytes`)
      else
        noctalia.notify(noctalia.tr("title"), "HTTP request failed")
      end
    end)
  end
end
