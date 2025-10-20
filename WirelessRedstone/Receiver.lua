-- listener.lua
-- Listens for rednet JSON messages and controls redstone on the "top" side.
-- Secure: requires a matching token.

local cfg = {
  token = "my_secret_token_here", -- change this to something random on both sides
  protocol = "redstone_control",  -- protocol name for rednet
  defaultPulse = 1.0              -- seconds for "pulse" command
}

local function openModem()
  -- try to open any modem automatically
  for _, side in ipairs({"left","right","top","bottom","front","back"}) do
    if peripheral.getType(side) == "modem" then
      if not rednet.isOpen(side) then
        rednet.open(side)
      end
      return true
    end
  end
  return false
end

local function safeSet(topSide, state)
  -- sets redstone output; wrap in pcall to avoid crashes
  local ok, err = pcall(function() redstone.setOutput(topSide, state) end)
  if not ok then print("Redstone error:", err) end
end

-- helper: pulse top for seconds
local function pulseTop(seconds)
  seconds = tonumber(seconds) or cfg.defaultPulse
  safeSet("top", true)
  sleep(seconds)
  safeSet("top", false)
end

-- start
print("Starting rednet listener...")
if not openModem() then
  print("Warning: no modem found. Attach one and restart.")
end

while true do
  local senderId, msg, proto = rednet.receive(cfg.protocol)
  if not senderId then
    -- timed out or error (shouldn't happen without timeout)
  else
    -- msg can be a stringified JSON or table
    local data = nil
    if type(msg) == "string" then
      local ok, parsed = pcall(textutils.unserializeJSON, msg)
      if ok then data = parsed end
    elseif type(msg) == "table" then
      data = msg
    end

    if not data then
      print("Received malformed message from", senderId)
    else
      -- security check
      if data.token ~= cfg.token then
        print("Rejected message from", senderId, "(invalid token)")
      else
        -- handle commands
        local cmd = data.cmd and string.lower(tostring(data.cmd)) or ""
        if cmd == "on" then
          safeSet("top", true)
          print("Set top ON (from " .. tostring(senderId) .. ")")
        elseif cmd == "off" then
          safeSet("top", false)
          print("Set top OFF (from " .. tostring(senderId) .. ")")
        elseif cmd == "pulse" then
          local dur = tonumber(data.duration) or cfg.defaultPulse
          print("Pulsing top for " .. tostring(dur) .. "s (from " .. tostring(senderId) .. ")")
          -- spawn a coroutine so we can keep listening while pulsing
          parallel.waitForAny(function() pulseTop(dur) end, function() sleep(0) end)
        else
          print("Unknown cmd from", senderId, ":", tostring(cmd))
        end
      end
    end
  end
end
