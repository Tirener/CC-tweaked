-- startup.lua
-- Secure Vault Lock Numpad GUI for CC:Tweaked
-- Locks system until correct code entered, triggers redstone on back.

-- === CONFIG ===
local correctCode = "8642"   -- set your vault code
local pulseTime = 10         -- seconds redstone stays on
local outputSide = "back"    -- redstone output side

-- === SECURITY ===
os.pullEvent = os.pullEventRaw   -- disable Ctrl+T

-- === DISPLAY DETECTION ===
local mon = peripheral.find("monitor")
local screen = mon or term
if mon then
    mon.setTextScale(1)
end

-- === DRAW HELPERS ===
local buttons = {}
local w, h = screen.getSize()

local function clearScreen(color)
    screen.setBackgroundColor(color or colors.black)
    screen.clear()
end

local function centerText(y, text, color)
    local x = math.floor((w - #text) / 2) + 1
    screen.setCursorPos(x, y)
    if color then screen.setTextColor(color) end
    screen.write(text)
    screen.setTextColor(colors.white)
end

local function drawButton(id, label, x, y, width, height)
    buttons[id] = {x = x, y = y, w = width, h = height}
    paintutils.drawFilledBox(x, y, x + width - 1, y + height - 1, colors.gray)
    screen.setCursorPos(x + math.floor((width - #label) / 2), y + math.floor(height / 2))
    screen.setTextColor(colors.white)
    screen.write(label)
    screen.setTextColor(colors.white)
end

local function drawUI(entered, message)
    clearScreen(colors.black)
    centerText(1, "=== VAULT LOCK ===", colors.cyan)
    centerText(3, string.rep("*", #entered))
    if message then
        centerText(5, message, colors.yellow)
    end

    local bw, bh = 7, 3
    local startX = math.floor((w - (bw * 3 + 2)) / 2)
    local startY = 7
    local labels = {
        "1", "2", "3",
        "4", "5", "6",
        "7", "8", "9",
        "CLR", "0", "ENT"
    }

    local i = 1
    for row = 0, 3 do
        for col = 0, 2 do
            local label = labels[i]
            if label then
                drawButton(label, label, startX + col * (bw + 1), startY + row * (bh + 1), bw, bh)
            end
            i = i + 1
        end
    end
end

local function getButtonAt(x, y)
    for id, b in pairs(buttons) do
        if x >= b.x and x < b.x + b.w and y >= b.y and y < b.y + b.h then
            return id
        end
    end
    return nil
end

-- === MAIN LOGIC ===
local entered = ""
drawUI(entered)

local function pulseRedstone()
    redstone.setOutput(outputSide, true)
    sleep(pulseTime)
    redstone.setOutput(outputSide, false)
end

while true do
    local event, p1, p2, p3 = os.pullEvent()
    local x, y = nil, nil

    if event == "monitor_touch" then
        x, y = p2, p3
    elseif event == "mouse_click" then
        x, y = p2, p3
    end

    if x and y then
        local btn = getButtonAt(x, y)
        if btn then
            if btn == "CLR" then
                entered = ""
                drawUI(entered)
            elseif btn == "ENT" then
                if entered == correctCode then
                    drawUI("", "ACCESS GRANTED")
                    pulseRedstone()
                    drawUI("", "LOCKED")
                else
                    drawUI("", "ACCESS DENIED")
                    sleep(1.5)
                    entered = ""
                    drawUI(entered)
                end
            else
                if #entered < 4 then
                    entered = entered .. btn
                    drawUI(entered)
                end
            end
        end
    end
end
