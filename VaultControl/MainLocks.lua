-- vault_lock.lua
-- Simple vault lock for CC:Tweaked with reliable pulse

local correctCode = "4582"
local pulseTime = 10
local outputSide = "back"

os.pullEvent = os.pullEventRaw

while true do
    term.clear()
    term.setCursorPos(1,1)
    print("=== VAULT LOCK ===")
    io.write("Enter code: ")
    local entered = read("*")  -- masks input

    if entered == correctCode then
        print("ACCESS GRANTED")
        -- Pulse redstone safely
        local success, err = pcall(function()
            redstone.setOutput(outputSide, true)
            local start = os.clock()
            while os.clock() - start < pulseTime do
                sleep(0.1)  -- keep loop alive
            end
            redstone.setOutput(outputSide, false)
        end)
        if not success then
            print("Redstone error:", err)
        end
        print("LOCKED")
    else
        print("ACCESS DENIED")
        sleep(1.5)
    end
end
