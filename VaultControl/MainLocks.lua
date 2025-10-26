-- startup.lua
-- Secure Vault Lock Numpad (CC:Tweaked)
-- Runs automatically on startup and cannot be terminated (Ctrl+T disabled)

-- === CONFIG ===
local correctCode = ""      
local pulseTime = 10             -- seconds redstone stays active
local outputSide = "back"        -- side for redstone output (vault door)

-- === SECURITY ===
os.pullEvent = os.pullEventRaw   -- disable Ctrl+T termination

-- === DETECT DISPLAY ===
local mon
if peripheral.isPresent("monitor_0") then
    mon = peripheral.wrap("monitor_0")
elseif peripheral.find("monitor") then
    mon = peripheral.find("monitor")
end

local screen = mon or term
if mon then mon.setTextScale(1) end

-- === DRAW HELPERS ===
local buttons = {}
local w, h = screen.getSize()

local function centerText(y, text, color)
    local x = math.floor((w - #text) / 2) + 1
    screen.setCursorPos(x, y)
    if color then screen.setTextColor(color) end
    screen.write(text)
    screen.setTextColor(colors.white)
end

local function drawButton(id, label, x, y, width, height)
    buttons[id] = {x = x, y = y, w = width, h = height, label = label}
    paintutils.drawFilledBox(x, y, x + width - 1, y + height - 1, colors.gray)
    screen.setCursorPos(x + math.floor((width - #label)/2), y + math.floor(height/2))
    screen.setTextColor(colors.white)
    screen.write(label)
end

local function drawUI(entered, message)
    screen.setBackgroundColor(colors.black)
    screen.clear()

    centerText(1, "=== VAULT LOCK ===", colors.cyan)
    centerText(3, string.rep("*", #entered))
    if message then centerText(5, message, colors.yellow) end

    local bw, bh = 7, 3
    local startX = math.floor((w - (bw * 3 + 2)) / 2)
    local startY = 7
    local labels = {
        "1","2","3",
        "4","5","6",
        "7","8","9",
        "CLR","0","ENT"
    }

    local index = 1
    for row = 0,3 do
        for col = 0,2 do
            local label = labels[index]
            drawButton(label, label, startX + col * (bw + 1), startY + row * (bh + 1), bw, bh)
            index = index + 1
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
    local event, side, x, y = os.pullEvent()
    if event == "monitor_touch" or event == "mouse_click" or event == "touch" then
        if not mon and event == "mouse_click" then
            x, y = side, x -- adjust for mouse_click event
        end
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
