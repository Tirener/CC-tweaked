-- client.lua
-- Portable Ender Computer client for elevator control using CreateAddition motor

local modemSide = "back"
local discoveryTimeout = 2
local serverID = nil

if not rednet.isOpen(modemSide) then
    rednet.open(modemSide)
end

local function discover()
    print("Discovering elevator server...")
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

local function sendCommand(cmd)
    if not serverID then
        print("No server connected.")
        return
    end
    rednet.send(serverID, { command = cmd })
    local id, msg = rednet.receive(5)
    if id == serverID and msg then
        print("Reply:", textutils.serialize(msg))
    else
        print("No reply.")
    end
end

if not discover() then
    io.write("Enter server ID manually: ")
    serverID = tonumber(io.read())
end

while true do
    print("\n=== Elevator Control ===")
    print("[U]p  [D]own  [S]top  [T]atus  [Q]uit")
    io.write("> ")
    local c = io.read()
    if not c then break end
    c = c:lower():sub(1,1)
    if c == "u" then
        sendCommand("up")
    elseif c == "d" then
        sendCommand("down")
    elseif c == "s" then
        sendCommand("stop")
    elseif c == "t" then
        sendCommand("status")
    elseif c == "q" then
        print("Goodbye.")
        break
    else
        print("Invalid option.")
    end
end
