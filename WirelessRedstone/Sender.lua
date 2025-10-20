-- controller.lua
-- Interactive controller to send rednet commands to a target computer.
-- Usage: specify target ID (or leave blank to broadcast). Uses JSON messages.

local cfg = {
  token = "my_secret_token_here", -- must match listener token
  protocol = "redstone_control"   -- must match listener protocol
}

-- try to open a modem automatically if not opened
local function openModem()
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

local function sendMessage(targetId, payload)
  local msg = textutils.serializeJSON(payload)
  if targetId == nil or targetId == "" then
    -- broadcast
    rednet.broadcast(msg, cfg.protocol)
    print("Broadcasted:", msg)
  else
    local idNum = tonumber(targetId)
    if not idNum then
      print("Invalid target ID. Use a number or leave blank to broadcast.")
      return
    end
    rednet.send(idNum, msg, cfg.protocol)
    print("Sent to", idNum .. ":", msg)
  end
end

-- interactive loop
print("Rednet controller")
if not openModem() then
  print("Warning: no modem found. Attach one and restart.")
end

print("Enter target ID (blank to broadcast):")
local target = read()

while true do
  print("\nCommands:")
  print("  on            -> turn top ON")
  print("  off           -> turn top OFF")
  print("  pulse <sec>   -> pulse top for <sec> seconds (e.g. pulse 2.5)")
  print("  exit          -> quit")
  io.write("> ")
  local line = read()
  if not line then break end
  local parts = {}
  for part in string.gmatch(line, "%S+") do table.insert(parts, part) end
  local cmd = parts[1] and string.lower(parts[1]) or ""
  if cmd == "exit" or cmd == "quit" then
    break
  elseif cmd == "on" then
    sendMessage(target, { token = cfg.token, cmd = "on" })
  elseif cmd == "off" then
    sendMessage(target, { token = cfg.token, cmd = "off" })
  elseif cmd == "pulse" then
    local dur = tonumber(parts[2]) or 1
    sendMessage(target, { token = cfg.token, cmd = "pulse", duration = dur })
  else
    print("Unknown command.")
  end
end

print("Controller exiting.")
