-- energy_report.lua
-- Sends energy levels of connected peripherals to a Discord webhook
-- Requires http enabled in cc-tweaked.conf
-- Save your webhook URL in config.lua

local cfg = {
    webhook = "nuh uh",
    username = "CC-EnergyBot"
}

local textutils = textutils

-- Helper function to detect energy storage methods
local function isEnergyPeripheral(peripheral)
    local methods = peripheral.getMethods(peripheral)
    for _, m in ipairs(methods) do
        if m == "getEnergy" or m == "getEnergyStored" or m == "getEnergyLevel" then
            return true
        end
    end
    return false
end

-- Gather energy info from all peripherals
local function gatherEnergyInfo()
    local result = {}
    for side, _ in pairs(peripheral.getNames()) do
        local p = peripheral.wrap(side)
        if p and isEnergyPeripheral(side) then
            local energy = nil
            if p.getEnergy then
                energy = p.getEnergy()
            elseif p.getEnergyStored then
                energy = p.getEnergyStored()
            elseif p.getEnergyLevel then
                energy = p.getEnergyLevel()
            end
            table.insert(result, {
                peripheral = side,
                energy = energy
            })
        end
    end
    return result
end

-- Send JSON to webhook
local function sendWebhook(payload)
    if not http then
        print("HTTP API is not enabled!")
        return false
    end
    local jsonPayload = textutils.serializeJSON(payload)
    local headers = { ["Content-Type"] = "application/json" }
    local res, err = http.post(cfg.webhook, jsonPayload, headers)
    if not res then
        print("Failed to send webhook:", err)
        return false
    end
    if res.readAll then res.readAll() end
    if res.close then res.close() end
    print("Webhook sent successfully!")
    return true
end

-- Main
local function main()
    local energyInfo = gatherEnergyInfo()
    if #energyInfo == 0 then
        print("No energy storage peripherals detected.")
        return
    end

    local payload = {
        username = cfg.username,
        embeds = {{
            title = "Energy Report",
            description = "Current energy levels of connected peripherals",
            fields = {},
            timestamp = os.date("!%Y-%m-%dT%H:%M:%SZ")
        }}
    }

    for _, info in ipairs(energyInfo) do
        table.insert(payload.embeds[1].fields, {
            name = info.peripheral,
            value = tostring(info.energy),
            inline = true
        })
    end

    sendWebhook(payload)
end

-- Run
main()
