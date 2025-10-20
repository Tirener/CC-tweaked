-- energy_monitor.lua
-- Measures energy drain over 5 seconds and reports to Discord webhook
-- Requires http.enabled=true

local cfg = {
    webhook = "nuh uh",
    username = "CC-EnergyBot",
    sampleTime = 5 -- seconds to measure energy drain
}

local textutils = textutils

-- Wrap peripheral safely
local function wrapPeripheral(name)
    local ok, p = pcall(peripheral.wrap, name)
    if ok then return p else return nil end
end

-- Detect if peripheral has energy methods
local function isEnergyPeripheral(name)
    local methods = peripheral.getMethods(name) or {}
    for _, m in ipairs(methods) do
        if m == "getEnergy" or m == "getEnergyStored" or m == "getEnergyLevel" then
            return true
        end
    end
    return false
end

-- Get current energy
local function getEnergy(p)
    if not p then return nil end
    if p.getEnergy then return p.getEnergy() end
    if p.getEnergyStored then return p.getEnergyStored() end
    if p.getEnergyLevel then return p.getEnergyLevel() end
    return nil
end

-- Get max energy (if available)
local function getMaxEnergy(p)
    if not p then return nil end
    if p.getMaxEnergy then return p.getMaxEnergy() end
    if p.getMaxEnergyStored then return p.getMaxEnergyStored() end
    return nil
end

-- Gather all energy peripherals
local function getEnergyPeripherals()
    local result = {}
    for _, name in ipairs(peripheral.getNames()) do
        if isEnergyPeripheral(name) then
            local p = wrapPeripheral(name)
            local current = getEnergy(p)
            local max = getMaxEnergy(p)
            if current ~= nil then
                table.insert(result, {
                    name = name,
                    peripheral = p,
                    energy = current,
                    maxEnergy = max or current -- fallback if max unknown
                })
            end
        end
    end
    return result
end

-- Measure drain over time
local function measureDrain(peripherals, duration)
    local startEnergy = {}
    local endEnergy = {}

    for _, info in ipairs(peripherals) do
        startEnergy[info.name] = getEnergy(info.peripheral)
    end

    sleep(duration)

    for _, info in ipairs(peripherals) do
        endEnergy[info.name] = getEnergy(info.peripheral)
    end

    local results = {}
    for _, info in ipairs(peripherals) do
        local startE = startEnergy[info.name]
        local endE = endEnergy[info.name]
        local delta = startE - endE
        local drainPerSecond = delta / duration
        local percentFull = (endE / info.maxEnergy) * 100
        local timeRemaining = (drainPerSecond > 0) and (endE / drainPerSecond) or math.huge

        table.insert(results, {
            name = info.name,
            energy = endE,
            maxEnergy = info.maxEnergy,
            percentFull = percentFull,
            drainPerSecond = drainPerSecond,
            timeRemaining = timeRemaining
        })
    end

    return results
end

-- Format for Discord embed
local function formatEmbed(results)
    local fields = {}
    for _, r in ipairs(results) do
        table.insert(fields, {
            name = r.name,
            value = string.format(
                "Energy: %.1f/%.1f (%.1f%%)\nDrain: %.2f/sec\nTime remaining: %s sec",
                r.energy, r.maxEnergy, r.percentFull, r.drainPerSecond, r.timeRemaining == math.huge and "∞" or string.format("%.1f", r.timeRemaining)
            ),
            inline = false
        })
    end
    return {
        username = cfg.username,
        embeds = {{
            title = "Energy Monitor Report",
            description = string.format("Measured over %d seconds", cfg.sampleTime),
            fields = fields,
            timestamp = os.date("!%Y-%m-%dT%H:%M:%SZ")
        }}
    }
end

-- Send to Discord webhook
local function sendWebhook(payload)
    if not http then
        print("ERROR: HTTP API not enabled!")
        return
    end
    local ok, err = pcall(function()
        local headers = { ["Content-Type"] = "application/json" }
        local res = http.post(cfg.webhook, textutils.serializeJSON(payload), headers)
        if res and res.readAll then res.readAll() end
        if res and res.close then res.close() end
    end)
    if ok then
        print("Webhook sent successfully!")
    else
        print("Failed to send webhook:", err)
    end
end

-- Main
local function main()
    local peripherals = getEnergyPeripherals()
    if #peripherals == 0 then
        print("No energy storage peripherals found.")
        return
    end

    print("Measuring energy drain for " .. cfg.sampleTime .. " seconds...")
    local results = measureDrain(peripherals, cfg.sampleTime)

    -- Print to console
    for _, r in ipairs(results) do
        print(string.format(
            "%s: %.1f/%.1f (%.1f%%), Drain %.2f/sec, Time remaining: %s sec",
            r.name, r.energy, r.maxEnergy, r.percentFull, r.drainPerSecond, r.timeRemaining == math.huge and "∞" or string.format("%.1f", r.timeRemaining)
        ))
    end

    -- Send to Discord
    local payload = formatEmbed(results)
    sendWebhook(payload)
end

main()
