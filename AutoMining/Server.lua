-- server.lua
-- Central dispatcher for swarm mining
-- Run on a stationary Computer with wireless modem
-- Configuration section

local MODEM_SIDE = "right"         -- change to side where modem is attached
local EXPECTED_WORKERS = 4         -- number of turtles to wait for
local CHUNK_DEPTH = 64             -- how deep to mine (blocks down from starting surface)
local JOBS_FILE = "jobs_queue.txt" -- optional persistent job queue (list of chunk origins)
local LOG_FILE = "server_log.txt"

local rednet = rednet
local textutils = textutils
local fs = fs
local gps = gps
local shell = shell

-- Utilities
local function log(msg)
  local line = os.date("%Y-%m-%d %H:%M:%S") .. " - " .. tostring(msg)
  print(line)
  local f = io.open(LOG_FILE, "a")
  if f then
    f:write(line.."\n")
    f:close()
  end
end

-- Open modem
rednet.open(MODEM_SIDE)
log("Modem opened on " .. MODEM_SIDE)

-- Load job queue (list of chunk origins {x,z})
local jobQueue = {}
if fs.exists(JOBS_FILE) then
  local fh = io.open(JOBS_FILE, "r")
  if fh then
    local content = fh:read("*a")
    fh:close()
    if content and #content > 0 then
      local ok, t = pcall(textutils.unserialize, content)
      if ok and type(t) == "table" then jobQueue = t end
    end
  end
end

-- Helper: save job queue
local function saveJobQueue()
  local fh = io.open(JOBS_FILE, "w")
  if fh then
    fh:write(textutils.serialize(jobQueue))
    fh:close()
  end
end

-- If queue empty, prompt to add a chunk to mine now
if #jobQueue == 0 then
  log("Job queue empty. Determining current chunk to mine (use this computer's GPS).")
  local x, y, z = gps.locate(5)
  if not x then
    error("Cannot locate server GPS. Ensure GPS towers are available and gps.locate() works.")
  end
  local chunkX = math.floor(x / 16)
  local chunkZ = math.floor(z / 16)
  local originX = chunkX * 16
  local originZ = chunkZ * 16
  -- push this chunk as the first job
  table.insert(jobQueue, {originX = originX, originZ = originZ})
  saveJobQueue()
  log(string.format("Added chunk origin (%d, %d) to queue.", originX, originZ))
else
  log("Loaded job queue with " .. tostring(#jobQueue) .. " entries.")
end

-- Wait for worker registration
log("Waiting for " .. EXPECTED_WORKERS .. " workers to register...")

local registered = {}
local workerInfo = {} -- id -> info table

while #registered < EXPECTED_WORKERS do
  local id, msg = rednet.receive()
  if type(msg) == "string" and msg == "register" then
    -- reply with assigned ID acknowledgement
    table.insert(registered, id)
    workerInfo[id] = {status = "idle", lastSeen = os.time()}
    rednet.send(id, "registered")
    log("Worker registered: ".. tostring(id))
  else
    -- ignore unexpected messages while waiting
    log("Received unexpected during registration: " .. tostring(msg))
  end
end

log("All workers registered: " .. tostring(#registered))

-- Function to subdivide a 16x16 chunk into N rectangular zones
local function subdivideChunk(numWorkers)
  local zones = {}
  local cols = math.floor(math.sqrt(numWorkers)) -- try near-square division
  if cols * cols < numWorkers then cols = cols + 1 end
  local rows = math.ceil(numWorkers / cols)
  local cellW = math.floor(16 / cols)
  local cellH = math.floor(16 / rows)
  local idx = 1
  for r = 0, rows - 1 do
    for c = 0, cols - 1 do
      if idx <= numWorkers then
        local x1 = c * cellW
        local z1 = r * cellH
        local x2 = math.min(15, (c+1)*cellW - 1)
        local z2 = math.min(15, (r+1)*cellH - 1)
        -- ensure zone is at least 1x1
        if x2 < x1 then x2 = x1 end
        if z2 < z1 then z2 = z1 end
        table.insert(zones, {x1 = x1, x2 = x2, z1 = z1, z2 = z2})
        idx = idx + 1
      end
    end
  end
  return zones
end

-- Main loop: assign the first job in queue to the registered workers
while #jobQueue > 0 do
  local jobOrigin = table.remove(jobQueue, 1) -- {originX, originZ}
  saveJobQueue()
  log(string.format("Dispatching chunk at origin (%d, %d)", jobOrigin.originX, jobOrigin.originZ))

  local zones = subdivideChunk(#registered)
  for i, id in ipairs(registered) do
    local zone = zones[i]
    local payload = {
      type = "mine_chunk",
      originX = jobOrigin.originX,
      originZ = jobOrigin.originZ,
      startY = nil, -- allow worker to determine surface via gps
      x1 = zone.x1, x2 = zone.x2,
      z1 = zone.z1, z2 = zone.z2,
      depth = CHUNK_DEPTH,
      homeX = nil, homeZ = nil -- server can add "home" coordinates if desired
    }
    rednet.send(id, textutils.serialize(payload))
    workerInfo[id].status = "assigned"
    workerInfo[id].currentJob = payload
    workerInfo[id].lastSeen = os.time()
    log("Sent job to worker ".. tostring(id) .. " zone: ["..zone.x1..","..zone.z1.."] to ["..zone.x2..","..zone.z2.."]")
  end

  -- Wait for completion messages from all workers for this chunk
  local completed = 0
  while completed < #registered do
    local id, msg = rednet.receive()
    workerInfo[id].lastSeen = os.time()
    if type(msg) == "string" then
      if msg == "done" then
        completed = completed + 1
        workerInfo[id].status = "idle"
        log("Worker "..tostring(id).." reported DONE for its zone.")
      else
        -- other messages might be status updates or error reports (serialized)
        local ok, t = pcall(textutils.unserialize, msg)
        if ok and type(t) == "table" and t.type == "status" then
          log("Status from "..tostring(id)..": "..(t.msg or ""))
        else
          log("Unknown message from "..tostring(id)..": ".. tostring(msg))
        end
      end
    end
  end

  log("All workers completed current chunk.")
  -- Optionally continue to next item in jobQueue automatically (loop will continue)
end

log("Job queue exhausted. Server exiting.")
rednet.close(MODEM_SIDE)
