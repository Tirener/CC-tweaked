-- worker.lua
-- Mining turtle worker with GPS navigation, fuel, inventory and progress persistence
-- Place on each turtle. Ensure a wireless modem is attached.

local MODEM_SIDE = "right"    -- side of the wireless modem
local FUEL_SLOT = 1           -- reserved slot index for fuel (put coal/lava here)
local ENDER_SLOT = 16         -- reserved slot index for ender chest (place one in this slot)
local PROGRESS_FILE = "progress.txt"
local REFUEL_THRESHOLD = 200  -- minimum fuel level before refuelling
local INVENTORY_UNLOAD_THRESHOLD = 13 -- when inventory slots used exceed this, unload (leaves fuel and chest slots)
local UNLOAD_RETRY = 3
local SAVE_EVERY = 20         -- save progress every N actions
local rednet = rednet
local textutils = textutils
local fs = fs
local gps = gps
local shell = shell

-- Logging
local LOG_FILE = "worker_log.txt"
local function log(msg)
  local line = os.date("%Y-%m-%d %H:%M:%S") .. " - " .. tostring(msg)
  print(line)
  local f = io.open(LOG_FILE, "a")
  if f then
    f:write(line.."\n")
    f:close()
  end
end

-- Open modem and register
rednet.open(MODEM_SIDE)
rednet.broadcast("register")
log("Broadcasted registration.")

-- Wait for ack
local _, ack = rednet.receive(5)
if not ack or ack ~= "registered" then
  log("No registration acknowledgement received. Continuing anyway.")
else
  log("Registered with server.")
end

-- Movement primitives (safe digging)
local function safeForward()
  while not turtle.forward() do
    if turtle.detect() then
      turtle.dig()
    else
      os.sleep(0.5)
    end
  end
end
local function safeUp()
  while not turtle.up() do
    if turtle.detectUp() then
      turtle.digUp()
    else
      os.sleep(0.5)
    end
  end
end
local function safeDown()
  while not turtle.down() do
    if turtle.detectDown() then
      turtle.digDown()
    else
      os.sleep(0.5)
    end
  end
end

-- Orientation utilities
local heading = 0 -- 0 = +x, 1 = +z, 2 = -x, 3 = -z
local function turnLeft()
  turtle.turnLeft(); heading = (heading - 1) % 4
end
local function turnRight()
  turtle.turnRight(); heading = (heading + 1) % 4
end
local function faceDirection(dir)
  -- dir: 0:+x 1:+z 2:-x 3:-z
  local diff = (dir - heading) % 4
  if diff == 1 then turnRight()
  elseif diff == 2 then turnRight(); turnRight()
  elseif diff == 3 then turnLeft()
  end
end

-- Absolute navigation using GPS: move to target (x, y, z)
local function moveTo(targetX, targetY, targetZ)
  -- Use gps.locate for current location (loop until success)
  local cx, cy, cz = gps.locate(5)
  if not cx then
    error("gps.locate failed on moveTo. Ensure GPS towers exist and are in range.")
  end
  -- Move vertically first to avoid getting stuck in tunnels
  while cy < targetY do
    safeUp()
    cy = cy + 1
  end
  while cy > targetY do
    safeDown()
    cy = cy - 1
  end
  -- Move X
  while cx ~= targetX do
    if targetX > cx then
      faceDirection(0) -- +x
    else
      faceDirection(2) -- -x
    end
    safeForward()
    cx = cx + (heading == 0 and 1 or (heading == 2 and -1 or 0))
  end
  -- Move Z
  while cz ~= targetZ do
    if targetZ > cz then
      faceDirection(1) -- +z
    else
      faceDirection(3) -- -z
    end
    safeForward()
    cz = cz + (heading == 1 and 1 or (heading == 3 and -1 or 0))
  end
end

-- Refuel routine: attempts to refuel using FUEL_SLOT; returns true if fuel >= threshold
local function tryRefuelIfNeeded()
  local lvl = turtle.getFuelLevel()
  local cap = turtle.getFuelLimit and turtle.getFuelLimit() or "unknown"
  if lvl ~= "unlimited" and lvl < REFUEL_THRESHOLD then
    -- ensure fuel slot has something
    local saved = turtle.getSelectedSlot and turtle.getSelectedSlot() or nil
    if FUEL_SLOT ~= nil then
      turtle.select(FUEL_SLOT)
      if turtle.getItemCount(FUEL_SLOT) > 0 then
        -- consume one item at a time until threshold
        while turtle.getFuelLevel() < REFUEL_THRESHOLD and turtle.getItemCount(FUEL_SLOT) > 0 do
          turtle.refuel(1)
        end
        log("Refueled. Level now: ".. tostring(turtle.getFuelLevel()))
      else
        -- no fuel in slot; request server (send status)
        log("Fuel slot empty and fuel below threshold.")
        rednet.broadcast(textutils.serialize({type="status", msg="need_fuel"}))
        return false
      end
    end
    if saved then turtle.select(saved) end
  end
  return true
end

-- Inventory functions
local function inventoryUsedSlots()
  local used = 0
  for s = 1, 16 do
    local cnt = turtle.getItemCount(s)
    if cnt > 0 then used = used + 1 end
  end
  return used
end

local function unloadIntoEnderChest()
  -- Expects an ender chest in ENDER_SLOT
  if turtle.getItemCount(ENDER_SLOT) == 0 then
    log("No Ender Chest in reserved slot "..ENDER_SLOT..". Cannot unload.")
    return false
  end

  -- move down to place chest if necessary (we assume ground is under turtle)
  local ok, err
  for attempt = 1, UNLOAD_RETRY do
    turtle.select(ENDER_SLOT)
    -- place down
    ok = turtle.placeDown()
    if ok then break end
    log("Failed to place Ender Chest (attempt "..attempt.."). Retrying...")
    os.sleep(0.5)
  end
  if not ok then
    log("Unable to place ender chest for unloading.")
    return false
  end

  -- drop all items except fuel and ender chest slot
  for s = 1, 16 do
    if s ~= FUEL_SLOT and s ~= ENDER_SLOT then
      turtle.select(s)
      if turtle.getItemCount(s) > 0 then
        turtle.dropDown()
      end
    end
  end

  -- pick up ender chest
  turtle.select(ENDER_SLOT)
  local picked = turtle.suckDown() -- actually we need to pick up the chest as an item; use turtle.digDown then pick up
  -- More robust approach: digDown then wait to collect; but that may drop the chest as an item
  -- We'll try to digDown and then suckDown the chest item
  turtle.digDown()
  os.sleep(0.1)
  -- try to suck up the chest item
  for s = 1, 3 do
    if turtle.suckDown() then break end
    os.sleep(0.1)
  end

  log("Unloaded inventory via Ender Chest.")
  return true
end

-- Progress persistence
local function saveProgress(data)
  local f = io.open(PROGRESS_FILE, "w")
  if f then
    f:write(textutils.serialize(data))
    f:close()
  end
end
local function loadProgress()
  if fs.exists(PROGRESS_FILE) then
    local f = io.open(PROGRESS_FILE, "r")
    if f then
      local content = f:read("*a")
      f:close()
      local ok, t = pcall(textutils.unserialize, content)
      if ok then return t end
    end
  end
  return nil
end

-- Mining routine for assigned zone (x1..x2, z1..z2) relative to originX, originZ
local function mineZone(job)
  -- job: table with originX, originZ, x1,x2,z1,z2,depth
  local originX, originZ = job.originX, job.originZ
  -- determine surface Y via GPS
  local gx, gy, gz = gps.locate(5)
  if not gx then error("Cannot determine GPS location for worker.") end
  local startY = gy

  -- compute absolute bounds
  local ax1, ax2 = originX + job.x1, originX + job.x2
  local az1, az2 = originZ + job.z1, originZ + job.z2
  local depth = job.depth or 64

  log(string.format("Starting mining zone absolute X[%d..%d] Z[%d..%d] from Y=%d down %d", ax1, ax2, az1, az2, startY, depth))

  -- Try to load progress
  local progress = loadProgress() or {x = ax1, z = az1, yDepth = 0, dir = 1, steps = 0}

  -- Outer loop over X and Z with boustrophedon (zig-zag)
  local saveCounter = 0
  for x = ax1, ax2 do
    -- determine z iteration order for zig-zag
    local zStart, zEnd, zStep
    if ((x - ax1) % 2) == 0 then
      zStart, zEnd, zStep = az1, az2, 1
    else
      zStart, zEnd, zStep = az2, az1, -1
    end

    for z = zStart, zEnd, zStep do
      -- Skip if progress says this column already finished
      if progress.x > x or (progress.x == x and ((zStep == 1 and z < progress.z) or (zStep == -1 and z > progress.z))) then
        -- column already done
      else
        -- Move to top of column
        moveTo(x, startY, z)
        -- Check fuel & inventory before starting column
        if not tryRefuelIfNeeded() then
          log("Refuel required but no fuel available. Sending status and waiting.")
          rednet.broadcast(textutils.serialize({type="status", msg="need_fuel"}))
          while not tryRefuelIfNeeded() do
            os.sleep(10)
          end
        end
        if inventoryUsedSlots() >= INVENTORY_UNLOAD_THRESHOLD then
          log("Inventory threshold reached. Unloading...")
          local ok = unloadIntoEnderChest()
          if not ok then
            log("Unable to unload. Will retry later.")
          end
        end

        -- Dig down for 'depth' blocks
        for d = 1, depth do
          turtle.digDown()
          safeDown()
        end
        -- Return to surface
        for d = 1, depth do
          safeUp()
        end

        -- Save progress
        progress.x = x
        progress.z = z + (zStep == 1 and 1 or -1) -- next z to handle (approx)
        progress.steps = (progress.steps or 0) + 1
        saveCounter = saveCounter + 1
        if saveCounter >= SAVE_EVERY then
          saveProgress(progress)
          saveCounter = 0
          log("Progress saved.")
        end
      end
    end
  end

  -- Final progress save and report done
  saveProgress({completed = true})
  rednet.send(rednet.lookup or nil, textutils.serialize({type = "status", msg = "zone_complete"}))
  log("Zone mining complete. Reporting to server.")
  rednet.send(nil, "done") -- send to everyone; server will receive from ID
end

-- Main: wait for job from server
while true do
  local id, msg = rednet.receive()
  if id and msg then
    local ok, job = pcall(textutils.unserialize, msg)
    if ok and type(job) == "table" and job.type == "mine_chunk" then
      log("Received job from server. Starting mining routine.")
      -- Start mining assigned zone
      local success, err = pcall(mineZone, job)
      if not success then
        log("Error during mining: " .. tostring(err))
        rednet.send(nil, textutils.serialize({type="status", msg="error", detail = tostring(err)}))
      end
      -- end of job, continue loop to wait for new job
    else
      log("Received unexpected message: ".. tostring(msg))
    end
  end
end
