-- vault_lock.lua
-- Simple vault lock for CC:Tweaked
-- User types code into the computer, triggers redstone if correct

-- === CONFIG ===
local correctCode = "4582"   -- set your vault code here
local pulseTime = 10         -- seconds redstone stays on
local outputSide = "back"    -- redstone output side

-- === SECURITY ===
os.pullEvent = os.pullEventRaw   -- disable Ctrl+T termination

-- === MAIN LOOP ===
while true do
    term.clear()
    term.setCursorPos(1,1)
    print("=== VAULT LOCK ===")
    io.write("Enter code: ")
    local entered = read("*")  -- masks input with *

    if entered == correctCode then
        print("ACCESS GRANTED")
        redstone.setOutput(outputSide, true)
        sleep(pulseTime)
        redstone.setOutput(outputSide, false)
        print("LOCKED")
    else
        print("ACCESS DENIED")
        sleep(1.5)
    end
end
