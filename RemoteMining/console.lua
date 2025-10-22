-- console.lua
-- Portable operator console for turtle swarm
-- Commands: start, stop, return, status (per-turtle or broadcast)
-- Adjust MODEM_SIDE if your modem is not on the right side.

local MODEM_SIDE = "right"
local rednet = rednet
local textutils = textutils
local shell = shell
local os = os

-- Open modem
rednet.open(MODEM_SIDE)
print("Console: modem opened on " .. MODEM_SIDE)
print("Console ID:", os.getComputerID())

-- Utility: send a command to a specific turtle (or broadcast if targetID == nil)
local function sendCommand(targetID, cmd, params)
  local payload = {
    type = "command",
    cmd = cmd,
    from = os.getComputerID(),
    data = params or {}
  }
  local serialized = textutils.serialize(payload)
  if targetID then
    rednet.send(targetID, serialized)
  else
    rednet.broadcast(serialized)
  end
end

-- Request status from a specific turtle or all turtles; collect replies for 'timeout' seconds
local function requestStatus(targetID, timeout)
  timeout = timeout or 3
  sendCommand(targetID, "status", {})
  local deadline = os.clock() + timeout
  local replies = {}
  while os.clock() < deadline do
    local id, raw = rednet.receive(timeout)
    if id and raw then
      local ok, msg = pcall(textutils.unserialize, raw)
      if ok and type(msg) == "table" and msg.type == "status" then
        replies[id] = msg.data
      end
    else
      break
    end
  end
  return replies
end

-- Pretty print a status table
local function printStatusTable(replies)
  if not replies or next(replies) == nil then
    print("No status replies received.")
    return
  end
  print(string.format("%-6s %-8s %-10s %-10s %-12s", "TID", "State", "Fuel", "Mined", "Extra"))
  for id, data in pairs(replies) do
    local state = tostring(data.state or "unknown")
    local fuel  = tostring(data.fuel or "unknown")
    local mined = tostring(data.mined or 0)
    local extra = ""
    if data.message then extra = tostring(data.message) end
    print(string.format("%-6s %-8s %-10s %-10s %-12s", tostring(id), state, fuel, mined, extra))
  end
end

-- Simple input helpers
local function prompt(msg)
  io.write(msg .. " ")
  return io.read()
end

-- Menu loop
local function mainMenu()
  while true do
    print("\n=== Swarm Console ===")
    print("1) Start (all)")
    print("2) Stop (all)")
    print("3) Return to origin (all)")
    print("4) Status (all)")
    print("5) Start (single)")
    print("6) Stop (single)")
    print("7) Return (single)")
    print("8) Status (single)")
    print("9) Send raw command")
    print("0) Exit")
    local choice = prompt("Select option:")
    if choice == "1" then
      local length = tonumber(prompt("Enter length (blocks) to mine (or 0 for indefinite):")) or 0
      sendCommand(nil, "start", {length = length})
      print("Start command broadcast.")
    elseif choice == "2" then
      sendCommand(nil, "stop", {})
      print("Stop command broadcast.")
    elseif choice == "3" then
      sendCommand(nil, "return", {})
      print("Return command broadcast.")
    elseif choice == "4" then
      print("Requesting status from all turtles...")
      local replies = requestStatus(nil, 3)
      printStatusTable(replies)
    elseif choice == "5" then
      local tid = tonumber(prompt("Enter target turtle ID:"))
      if tid then
        local length = tonumber(prompt("Enter length (blocks) to mine (or 0 for indefinite):")) or 0
        sendCommand(tid, "start", {length = length})
        print("Start command sent to " .. tid)
      end
    elseif choice == "6" then
      local tid = tonumber(prompt("Enter target turtle ID:"))
      if tid then
        sendCommand(tid, "stop", {})
        print("Stop command sent to " .. tid)
      end
    elseif choice == "7" then
      local tid = tonumber(prompt("Enter target turtle ID:"))
      if tid then
        sendCommand(tid, "return", {})
        print("Return command sent to " .. tid)
      end
    elseif choice == "8" then
      local tid = tonumber(prompt("Enter target turtle ID:"))
      if tid then
        local replies = requestStatus(tid, 3)
        printStatusTable(replies)
      end
    elseif choice == "9" then
      local raw = prompt("Enter raw command (start/stop/return/status):")
      local target = prompt("Target ID (blank for broadcast):")
      local tid = tonumber(target)
      if raw == "start" then
        local length = tonumber(prompt("Enter length (blocks) to mine (or 0 for indefinite):")) or 0
        sendCommand(tid, "start", {length = length})
      else
        sendCommand(tid, raw, {})
      end
      print("Raw command sent.")
    elseif choice == "0" then
      print("Exiting console.")
      rednet.close(MODEM_SIDE)
      return
    else
      print("Invalid selection.")
    end
  end
end

mainMenu()
