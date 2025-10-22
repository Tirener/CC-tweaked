-- worker.lua
-- Mining turtle: listens for remote commands (start/stop/return/status)
-- Mines a 9xL horizontal strip (width 9, length L), reports fuel and mined blocks
-- Configuration
local MODEM_SIDE = "right"
local FUEL_SLOT  = 1      -- put fuel (coal/charcoal/lava bucket) here
local PROGRESS_FILE = "progress.txt"
local STATUS_INTERVAL = 10 -- seconds between automatic status broadcasts while mining
local REFUEL_THRESHOLD = 100 -- attempt refuel when below this level

local rednet = rednet
local textutils = textutils
local gps = gps
local turtle = turtle
local fs = fs
local os = os

-- Internal state
local controllerID = nil
local origin = nil -- {x,y,z}
local state = "idle" -- idle | mining | paused | returning
local minedCount = 0
local currentJob = nil -- {length = int, width = 9}
local lastStatusTime = 0

-- Logging helper
local function log(msg)
  local line = os.date("%Y-%m-%d %H:%M:%S") .. " - " .. tostring(msg)
  print(line)
end

-- Open modem & announce presence
rednet.open(MODEM_SIDE)
log("Worker modem opened on " .. MODEM_SIDE)

-- Determine origin via GPS if possible; fallback to nil
local function initOrigin()
  local x,y,z = gps.locate(5)
  if x then
    origin = {x=math.floor(x+0.5), y=math.floor(y+0.5), z=math.floor(z+0.5)}
    log(string.format("Origin set from GPS: %d,%d,%d", origin.x, origin.y, origin.z))
  else
    log("GPS locate failed; origin unknown. 'return' will not work without GPS.")
    origin = nil
  end
end
initOrigin()

-- Save/load progress
local function saveProgress()
  local data = {
    origin = origin,
    state = state,
    minedCount = minedCount,
    currentJob = currentJob
  }
  local fh = io.open(PROGRESS_FILE, "w")
  if fh then
    fh:write(textutils.serialize(data))
    fh:close()
  end
end

local function loadProgress()
  if not fs.exists(PROGRESS_FILE) then return end
  local fh = io.open(PROGRESS_FILE, "r")
  if not fh then return end
  local content = fh:read("*a")
  fh:close()
  local ok, t = pcall(textutils.unserialize, content)
  if ok and type(t) == "table" then
    origin = t.origin or origin
    state = t.state or state
    minedCount = t.minedCount or minedCount
    currentJob = t.currentJob or currentJob
    log("Progress loaded.")
  end
end

loadProgress()

-- Movement primitives (digging safe)
local function safeForward()
  while not turtle.forward() do
    if turtle.detect() then
      turtle.dig()
    else
      os.sleep(0.3)
    end
  end
end
local function safeBack()
  while not turtle.back() do
    os.sleep(0.2)
  end
end
local function safeUp()
  while not turtle.up() do
    if turtle.detectUp() then
      turtle.digUp()
    else
      os.sleep(0.3)
    end
  end
end
local function safeDown()
  while not turtle.down() do
    if turtle.detectDown() then
      turtle.digDown()
    else
      os.sleep(0.3)
    end
  end
end

-- Orientation utilities (track heading 0:+x 1:+z 2:-x 3:-z)
local heading = 0
local function turnLeft()
  turtle.turnLeft(); heading = (heading - 1) % 4
end
local function turnRight()
  turtle.turnRight(); heading = (heading + 1) % 4
end
local function face(dir) -- 0..3
  local diff = (dir - heading) % 4
  if diff == 1 then turnRight()
  elseif diff == 2 then turnRight(); turnRight()
  elseif diff == 3 then turnLeft()
  end
end

-- Simple refuel routine
local function ensureFuel(minNeeded)
  minNeeded = minNeeded or REFUEL_THRESHOLD
  local level = turtle.getFuelLevel()
  if level == "unlimited" then return true end
  if level >= minNeeded then return true end
  -- try to refuel from FUEL_SLOT
  if turtle.getItemCount(FUEL_SLOT) > 0 then
    turtle.select(FUEL_SLOT)
    while turtle.getFuelLevel() < minNeeded and turtle.getItemCount(FUEL_SLOT) > 0 do
      turtle.refuel(1)
    end
  end
  if turtle.getFuelLevel() < minNeeded then
    -- notify controller
    local payload = {type="status", from=os.getComputerID(), data={state=state, fuel=turtle.getFuelLevel(), mined=minedCount, message="need_fuel"}}
    if controllerID then rednet.send(controllerID, textutils.serialize(payload)) else rednet.broadcast(textutils.serialize(payload)) end
    return false
  end
  return true
end

-- Send status to controller (or broadcast)
local function sendStatus(extra)
  local payload = {
    type = "status",
    from = os.getComputerID(),
    data = {
      state = state,
      fuel = turtle.getFuelLevel(),
      mined = minedCount,
      message = extra
    }
  }
  local s = textutils.serialize(payload)
  if controllerID then
    rednet.send(controllerID, s)
  else
    rednet.broadcast(s)
  end
end

-- Grid traversal: clear a 9 x length rectangle.
-- We assume turtle starts at the "near" corner oriented along +z (forward increases length).
-- width = 9 (x from 1..9), length = L (z from 1..L).
-- The turtle will use boustrophedon traversal: for z = 1..L: traverse x=1..9 (or reverse) visiting all cells.
local function mineGrid(length)
  length = length or 0 -- 0 => indefinite (keep going until stopped)
  local width = 9
  local step = 0
  local z = 1
  local indefinite = (length == 0)
  log("Begin mining grid: width="..tostring(width).." length="..tostring(length).." (indefinite="..tostring(indefinite)..")")
  state = "mining"
  saveProgress()
  lastStatusTime = os.time()

  local function mineCellAndMove(nextX)
    -- clean block at turtle position's level (dig up/down/front as needed)
    -- remove the block in front (so turtle can move), and the blocks above if any
    if turtle.detect() then turtle.dig() end
    if turtle.detectUp() then turtle.digUp() end
    if turtle.detectDown() then turtle.digDown() end
  end

  -- We will implement traversal by rows:
  -- For z = 1..length
  --   For x = 1..width: ensure block at (x,z) cleared then move east (or west) except when at end
  -- To move to next z, reposition at column edge, turn and move forward one, then invert direction.
  -- NOTE: This algorithm assumes open area; obstacles will be dug.
  -- We keep track of position logically rather than absolute GPS.

  -- Ensure fuel before starting
  if not ensureFuel(REFUEL_THRESHOLD) then
    log("Insufficient fuel to start mining. Waiting.")
    return
  end

  -- We'll not rely on GPS for the traversal; we assume turtle can move relative.
  local dirRight = 0 -- use local variable for turning decisions
  while true do
    -- For each row z
    for x = 1, width do
      -- For each column, clear current cell and then move forward to next column in row direction
      -- Clear current cell: dig front/up/down to remove blocks
      if turtle.detect() then turtle.dig() end
      if turtle.detectUp() then turtle.digUp() end
      -- Move forward to next cell (if not at last column)
      if x < width then
        -- move laterally across the width: we treat 'forward' as the width axis when traversing the row
        safeForward()
      end
      minedCount = minedCount + 1
      step = step + 1
      -- periodic status and fuel check
      if os.time() - lastStatusTime >= STATUS_INTERVAL then
        sendStatus()
        lastStatusTime = os.time()
      end
      if not ensureFuel(20) then
        log("Out of fuel while mining. Pausing.")
        state = "paused"
        saveProgress()
        return
      end
      -- Check for remote commands without blocking too long
      local id, raw = rednet.receive(0.01)
      if id and raw then
        local ok, msg = pcall(textutils.unserialize, raw)
        if ok and type(msg) == "table" and msg.type == "command" then
          controllerID = msg.from or controllerID
          if msg.cmd == "stop" then
            state = "paused"
            sendStatus("stopped_by_cmd")
            saveProgress()
            return
          elseif msg.cmd == "return" then
            state = "returning"
            sendStatus("returning_by_cmd")
            saveProgress()
            return
          elseif msg.cmd == "status" then
            sendStatus("on_demand")
          end
        end
      end
    end

    -- Row finished: move to next z (length axis)
    -- At the end of a row, we need to reposition to the start of the next row.
    -- Depending on parity of z, we are at either right or left edge (we consider we move 'width-1' times per row).
    -- To move to next row:
    -- turn right, move forward 1, turn right (for one parity) or left,left accordingly.
    -- Implementation:
    if width % 2 == 1 then
      -- if width odd, turtle ends at same side each row; need to go back to original column
      -- simpler approach: move back (width-1) steps to return to starting column, then move one forward to next row
      for i = 1, width-1 do safeBack() end
    else
      -- width even: we will be at the opposite edge; no need to backtrack
    end

    -- move forward 1 to next row (length direction). We assume forward is length axis; if your orientation differs, swap behavior.
    -- In this implementation we treat the then-next-axis as 'up one row ahead' by turning appropriately.
    -- For simplicity, we will just move 'up' one block in the same plane: turn right, safeForward, turn left to restore orientation.
    turnRight()
    safeForward()
    turnLeft()

    z = z + 1
    saveProgress()
    if not indefinite and z > length then
      -- finished desired length
      state = "idle"
      sendStatus("job_complete")
      saveProgress()
      log("Mining job complete.")
      return
    end
    -- fuel check for next row
    if not ensureFuel(20) then
      state = "paused"
      saveProgress()
      return
    end

    -- check for remote immediate commands between rows
    local id, raw = rednet.receive(0.01)
    if id and raw then
      local ok, msg = pcall(textutils.unserialize, raw)
      if ok and type(msg) == "table" and msg.type == "command" then
        controllerID = msg.from or controllerID
        if msg.cmd == "stop" then
          state = "paused"
          sendStatus("stopped_by_cmd")
          saveProgress()
          return
        elseif msg.cmd == "return" then
          state = "returning"
          sendStatus("returning_by_cmd")
          saveProgress()
          return
        elseif msg.cmd == "status" then
          sendStatus("on_demand")
        end
      end
    end
  end
end

-- Return to origin using GPS
local function returnToOrigin()
  if not origin then
    log("Origin unknown; cannot return.")
    sendStatus("no_origin")
    return
  end
  state = "returning"
  sendStatus("starting_return")
  -- get current position via gps
  local cx, cy, cz = gps.locate(5)
  if not cx then
    log("GPS locate failed; cannot compute return path.")
    sendStatus("gps_failed")
    return
  end
  cx = math.floor(cx+0.5); cy = math.floor(cy+0.5); cz = math.floor(cz+0.5)
  -- Simple return: move vertically to origin.y then navigate in X and Z using GPS-relocation.
  -- Move vertically first
  while cy < origin.y do safeUp(); cy = cy + 1 end
  while cy > origin.y do safeDown(); cy = cy - 1 end
  -- Move X
  while cx ~= origin.x do
    if origin.x > cx then face(0) else face(2) end
    safeForward()
    if origin.x > cx then cx = cx + 1 else cx = cx - 1 end
  end
  -- Move Z
  while cz ~= origin.z do
    if origin.z > cz then face(1) else face(3) end
    safeForward()
    if origin.z > cz then cz = cz + 1 else cz = cz - 1 end
  end
  log("Returned to origin.")
  state = "idle"
  sendStatus("returned")
  saveProgress()
end

-- Handle incoming commands. This function blocks and dispatches jobs or control actions.
local function commandLoop()
  while true do
    local id, raw = rednet.receive()
    if id and raw then
      local ok, msg = pcall(textutils.unserialize, raw)
      if not ok or type(msg) ~= "table" then
        log("Received malformed message from " .. tostring(id))
      else
        if msg.type == "command" then
          controllerID = msg.from or id
          -- reply ack
          rednet.send(controllerID, textutils.serialize({type="status", from=os.getComputerID(), data={state=state, fuel=turtle.getFuelLevel(), mined=minedCount, message="ack"}}))
          if msg.cmd == "start" then
            if state == "idle" or state == "paused" then
              local length = tonumber(msg.data.length) or 0
              currentJob = {length = length}
              -- run mining in a separate pcall to capture errors
              local ok, err = pcall(mineGrid, length)
              if not ok then
                log("Error during mining: " .. tostring(err))
                rednet.send(controllerID, textutils.serialize({type="status", from=os.getComputerID(), data={state=state, fuel=turtle.getFuelLevel(), mined=minedCount, message="error:"..tostring(err)}}))
              end
            else
              log("Received start but currently in state: " .. state)
            end
          elseif msg.cmd == "stop" then
            -- stop is handled cooperatively in the mining loop by checking incoming commands
            state = "paused"
            saveProgress()
            sendStatus("stopped")
          elseif msg.cmd == "return" then
            -- stop any mining and return
            state = "returning"
            saveProgress()
            returnToOrigin()
          elseif msg.cmd == "status" then
            sendStatus("on_demand")
          else
            log("Unknown command: " .. tostring(msg.cmd))
          end
        else
          log("Unknown message type: " .. tostring(msg.type))
        end
      end
    end
  end
end

-- Start a background loop to periodically broadcast status if mining
local function statusTicker()
  while true do
    os.sleep(1)
    if state == "mining" and (os.time() - lastStatusTime >= STATUS_INTERVAL) then
      sendStatus()
      lastStatusTime = os.time()
      saveProgress()
    end
  end
end

-- Launch status ticker in a parallel coroutine if possible
local coTicker = coroutine.create(statusTicker)
coroutine.resume(coTicker)

-- Enter the command loop (blocking)
log("Worker ready; entering command loop.")
commandLoop()
