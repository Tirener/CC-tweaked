--[[
 Chat Program for CC:Tweaked
 Works with any computers that have an Ender Modem (on top)
 Author: Tirener Chat Edition
]]

local side = "top"
if not peripheral.isPresent(side) then
    print("No modem found on top.")
    return
end

rednet.open(side)

term.clear()
term.setCursorPos(1,1)

print("=== Wireless Chat ===")
io.write("Enter your username: ")
local username = read()
if username == "" then username = "Anon" .. tostring(os.getComputerID()) end

local CHAT_CHANNEL = 7777

print("Connected. Type messages and press Enter.")
print("Type /exit to leave.\n")

-- Parallel tasks: one listens, one handles input
local function listen()
    while true do
        local id, msg, protocol = rednet.receive(nil, 0.5)
        if msg and protocol == "chat" then
            local packet = textutils.unserialize(msg)
            if packet and packet.user and packet.text then
                term.setTextColor(colors.cyan)
                write("[" .. packet.user .. "] ")
                term.setTextColor(colors.white)
                print(packet.text)
            end
        end
    end
end

local function input()
    while true do
        term.setTextColor(colors.yellow)
        io.write("> ")
        term.setTextColor(colors.white)
        local text = read()
        if text == "/exit" then
            print("Leaving chat.")
            os.shutdown()
            return
        elseif text and text ~= "" then
            local packet = textutils.serialize({
                user = username,
                text = text
            })
            rednet.broadcast(packet, "chat")
        end
    end
end

parallel.waitForAny(listen, input)
