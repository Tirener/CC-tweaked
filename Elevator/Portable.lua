-- client_gui.lua
-- Portable Ender Computer with GUI for Create: Additions Elevator
-- Adds "Routine" button: goes down, waits 25s, goes up.

-- === CONFIG ===
local modemSide = "back"
local discoveryTimeout = 2
local serverID = nil
local waitTime = 25 -- seconds for the routine

-- === NETWORK SETUP ===
if not rednet.isOpen(modemSide) then
    rednet.open(modemSide)
end

-- === DISCOVER SERVER ===
local function discover()
    term.setTextColor(colors.yellow)
    print("Discovering elevator server...")
    term.setTextColor(colors.white)
    rednet.broadcast({ command = "whois" })
    local start = os.clock()
    while os.clock() - start < discoveryTimeout do
        local id, msg = rednet.receive(0.5)
        if id and type(msg) == "table" and msg.kind == "server" then
            print("Server found:", id)
            serverID = id
            return true
        end
    end
    print("No server found.")
    return false
end

-- === SEND COMMAND TO SERVER ===
local function sendCommand(cmd)
    if not serverID then
        print("No server connected.")
        return
    end
    rednet.send(serverID, { command = cmd })
    local id, msg = rednet.receive(5)
    if id == serverID and msg then
        return msg
    else
        return { status = "no_reply" }
    end
end

-- === UI HELPERS ===
local buttons = {}

local function drawButton(name, label, x, y, w, h, color)
    buttons[name] = {x = x, y = y, w = w, h = h, color = color, label = label}
    paintutils.drawFilledBox(x, y, x + w - 1, y + h - 1, color)
    term.setCursorPos(x + math.floor((w - #label) / 2), y + math.floor(h / 2))
    term.setTextColor(colors.black)
    term.write(label)
    term.setTextColor(colors.white)
end

local function drawUI(status)
    term.setBackgroundColor(colors.black)
    term.clear()
    term.setCursorPos(1, 1)
    term.setTextColor(colors.cyan)
    print("=== Elevator Control ===")
    term.setTextColor(colors.white)
    print("Server:", serverID or "None")
    print("Status:", status or "Unknown")
    print(" ")

    local w, h = term.getSize()
    local bw = math.floor(w / 2) - 1
    drawButton("up", "UP", 2, 6, bw, 3, colors.lime)
    drawButton("down", "DOWN", bw + 3, 6, bw, 3, colors.red)
    drawButton("stop", "STOP", 2, 10, bw, 3, colors.orange)
    drawButton("routine", "ROUTINE", bw + 3, 10, bw, 3, colors.yellow)
    drawButton("status", "STATUS", 2, 14, bw, 3, colors.lightBlue)
    drawButton("quit", "QUIT", bw + 3, 14, bw, 3, colors.gray)

    term.setCursorPos(1, h)
    term.setTextColor(colors.gray)
    term.write("Touch a button to control elevator.")
    term.setTextColor(colors.white)
end

local function getButtonAt(x, y)
    for name, b in pairs(buttons) do
        if x >= b.x and x < b.x + b.w and y >= b.y and y < b.y + b.h then
            return name
        end
    end
    return nil
end

-- === ROUTINE LOGIC ===
local function routine()
    drawUI("Routine: Going Down")
    sendCommand("down")
    sleep(waitTime)
    drawUI("Routine: Going Up")
    sendCommand("up")
    sleep(3)
    drawUI("Routine Complete")
end

-- === MAIN ===
term.clear()
term.setCursorPos(1, 1)
if not discover() then
    io.write("Enter server ID manually: ")
    serverID = tonumber(io.read())
end

local currentStatus = "Ready"
drawUI(currentStatus)

while true do
    local e, p1, p2, p3 = os.pullEvent()
    if e == "monitor_touch" or e == "mouse_click" or e == "touch" then
        local name = getButtonAt(p2, p3)
        if name then
            if name == "quit" then
                drawUI("Goodbye.")
                sleep(1)
                term.clear()
                term.setCursorPos(1,1)
                break
            elseif name == "up" or name == "down" or name == "stop" then
                drawUI("Sending " .. name:upper())
                sendCommand(name)
            elseif name == "status" then
                local msg = sendCommand("status")
                drawUI(msg.status or "Unknown")
            elseif name == "routine" then
                routine()
            end
        end
    end
end
