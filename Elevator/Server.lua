-- server.lua
-- CC:Tweaked server controlling a CreateAddition Electrical Motor as an elevator.
-- Modem: on back
-- Motor: on right
-- Meter (optional): on left (used to detect when elevator arrives)

-- Configuration
local modemSide = "back"
local motorSide = "right"
local meterSide = "left"  -- optional
local defaultSpeed = 32   -- RPM (positive)
local safetyTimeout = 30  -- seconds

-- Wrap peripherals
local motor = peripheral.wrap(motorSide)
if not motor then
    error("No electrical motor found on side: " .. motorSide)
end

local hasMeter = peripheral.isPresent(meterSide)
local meter = hasMeter and peripheral.wrap(meterSide) or nil

-- Open rednet
if not rednet.isOpen(modemSide) then
    rednet.open(modemSide)
end

local running = false

-- === Helper Functions ===

local function reply(id, msg)
    if id then
        rednet.send(id, msg)
    end
end

local function stopMotor()
    if motor and motor.getSpeed then
        motor.setSpeed(0)
    end
    running = false
end

local function move(direction, sender)
    if running then
        reply(sender, { status = "busy", reason = "already moving" })
        return
    end

    local dir = (direction == "up") and 1 or (direction == "down" and -1 or 0)
    if dir == 0 then
        reply(sender, { status = "error", reason = "invalid direction" })
        return
    end

    running = true
    local startTime = os.clock()
    reply(sender, { status = "started", direction = direction })

    motor.setSpeed(defaultSpeed * dir)

    local baseEnergy = hasMeter and meter.getEnergy() or nil

    while running do
        sleep(0.1)

        -- Stop if motor unloaded or invalid
        if not peripheral.isPresent(motorSide) then
            running = false
            reply(sender, { status = "error", reason = "motor disconnected" })
            return
        end

        -- Optional: stop when meter stabilizes
        if hasMeter then
            local e = meter.getEnergy()
            if baseEnergy and math.abs(e - baseEnergy) < 0.01 then
                stopMotor()
                reply(sender, { status = "arrived", direction = direction })
                return
            end
        end

        -- Timeout safeguard
        if os.clock() - startTime > safetyTimeout then
            stopMotor()
            reply(sender, { status = "timeout" })
            return
        end

        -- Check for new messages
        local id, msg = rednet.receive(0.05)
        if id and type(msg) == "table" then
            if msg.command == "stop" then
                stopMotor()
                reply(id, { status = "stopped" })
                return
            elseif msg.command == "status" then
                reply(id, { status = running and "moving" or "idle", direction = direction })
            end
        end
    end
end

-- === Routine Command ===
local function routine(sender)
    if running then
        reply(sender, { status = "busy", reason = "already moving" })
        return
    end

    reply(sender, { status = "routine_start" })
    move("down", sender)
    sleep(25)  -- wait time
    move("up", sender)
    reply(sender, { status = "routine_complete" })
end

-- === Main Server Loop ===
print("Elevator server running. Listening for commands...")

while true do
    local id, msg = rednet.receive()
    if type(msg) == "table" and msg.command then
        local cmd = msg.command
        if cmd == "up" or cmd == "down" then
            move(cmd, id)
        elseif cmd == "stop" then
            stopMotor()
            reply(id, { status = "stopped" })
        elseif cmd == "status" then
            local rpm = motor.getSpeed and motor.getSpeed() or 0
            reply(id, { status = running and "moving" or "idle", rpm = rpm })
        elseif cmd == "routine" then
            routine(id)
        elseif cmd == "whois" then
            reply(id, { kind = "server", note = "elevator-server" })
        else
            reply(id, { status = "error", reason = "unknown command: " .. tostring(cmd) })
        end
    end
end
