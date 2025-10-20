-- energy_report_fixed.lua
-- CC:Tweaked Energy Reporter to Discord Webhook
-- Make sure http.enabled=true in cc-tweaked.conf

local cfg = {
    webhook = "nuh uh",
    username = "CC-EnergyBot"
}

local textutils = textutils

-- Safely wrap a peripheral
local function wrapPeripheral(name)
    local ok, p = pcall(peripheral.wrap, name)
    if ok then return p else return nil end
end

-- Detect if peripheral has any known energy methods
local function isEnergyPeripheral(name)
    local methods = peripheral.getMethods(name) or {}
    for _, m in ipairs(methods) do
        if m == "getEnergy" or m == "getEnergyStored" or m == "getEnergyLevel" then
            return true
        end
    end
    return false
end

-- Safely read energy from a peripheral
local function getEnergy(p)
    if not p then return nil end
    if p.getEnergy then return p.getEnergy() end
    if p.getEnergyStored then return p.getEnergyStored() end
    if p.getEnergyLevel then return p.getEnergyLevel() end
    return nil
end

-- Gather info from all attached peripherals
local function gatherEnergyInfo()
    local result = {}
    for _, name in ipairs(peripheral.getNames()) do
        if isEnergyPeripheral(name) then
            local p = wrapPeripheral(name)
            local energy = getEnergy(p)
            if energy ~= nil then
                table.insert(result, { name = name, energy = tostring(energy) }) -- convert to string
            end
        end
    end
    return result
end

-- Send JSON embed to Discord webhook
local function sendWebhook(energyInfo)
    if not http then
        print("ERROR: HTTP API not enabled!")
        return
    end

    if #energyInfo == 0 then
        print("No energy storage peripherals found.")
        return
    end

    local payload = {
        username = cfg.username,
        embeds = {{
            title = "Energy Report",
            description = "Current energy levels of attached peripherals",
            fields = {},
            timestamp = os.date("!%Y-%m-%dT%H:%M:%SZ")
        }}
    }

    for _, info in ipairs(energyInfo) do
        table.insert(payload.embeds[1].fields, {
            name = tostring(info.name),
            value = tostring(info.energy), -- ensure string
            inline = true
        })
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

-- Main function
local function main()
    local info = gatherEnergyInfo()
    sendWebhook(info)
end

-- Run once (or loop with sleep for periodic updates)
main()
-- Example for periodic update every 60 seconds:
-- while true do
--     main()
--     sleep(60)
-- end
