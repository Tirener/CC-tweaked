-- vault_lock.lua
-- Secure vault lock for CC:Tweaked

local correctCode = "" --add the code
local pulseTime = 10 
local outputSide = "back"

-- Security settings
local maxAttempts = 5
local lockDuration = 600  -- seconds (10 minutes)
local attempts = 0
local lockedUntil = 0

os.pullEvent = os.pullEventRaw

local function logEvent(msg)
    local f = fs.open("vault_log.txt", "a")
    if f then
        f.writeLine(("[%s] %s"):format(os.date("%Y-%m-%d %H:%M:%S"), msg))
        f.close()
    end
end

local function pulseVault()
    local success, err = pcall(function()
        redstone.setOutput(outputSide, true)
        local start = os.clock()
        while os.clock() - start < pulseTime do
            sleep(0.1)
        end
        redstone.setOutput(outputSide, false)
    end)
    if not success then
        print("Redstone error:", err)
        logEvent("Redstone error: " .. tostring(err))
    end
end

while true do
    term.clear()
    term.setCursorPos(1,1)
    print("=== VAULT LOCK ===")

    -- Lockout check
    if os.epoch("utc") < lockedUntil then
        local remaining = math.floor((lockedUntil - os.epoch("utc")) / 1000)
        print("LOCKED OUT. Try again in " .. remaining .. " seconds.")
        sleep(5)
    else
        io.write("Enter code: ")
        local entered = read("*")  -- masks input

        if entered == correctCode then
            print("ACCESS GRANTED")
            logEvent("Access granted.")
            attempts = 0
            pulseVault()
            print("LOCKED")
        else
            attempts = attempts + 1
            print("ACCESS DENIED (" .. attempts .. "/" .. maxAttempts .. ")")
            logEvent("Failed code entry (" .. attempts .. "/" .. maxAttempts .. ")")

            if attempts >= maxAttempts then
                print("Too many failed attempts. System locked for 10 minutes.")
                logEvent("System locked for 10 minutes due to repeated failures.")
                lockedUntil = os.epoch("utc") + lockDuration * 1000
                attempts = 0
        
                http.request("change this", textutils.serializeJSON({ --dont forget the webhook tire
                    content = "@1001244737065455667 Someone is trying to access the server room",
                    username = "Shadiom"
                }))
            end
            sleep(2)
        end
    end
end
