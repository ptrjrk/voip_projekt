local function is_business_open()

    local mode = channel.DB("voip/mode"):get()

    -- Demonstration mode
    if mode == "open" then
        return true
    elseif mode == "closed" then
        return false
    end

    -- Real business hours
    local now = os.date("*t")

    local weekday = now.wday
    local hour = now.hour

    return weekday >= 2
       and weekday <= 6
       and hour >= 8
       and hour < 16
end

-- Voicemail fallback
local function route_to_voicemail(mailbox)

    app.NoOp("[LUA] Routing to voicemail")

    app.VoiceMail(mailbox, "u")

    local status = channel.VMSTATUS:get() or "UNKNOWN"

    app.NoOp("[LUA] Voicemail status: " .. status)
end

-- Customer support
local function customer_support()

    local caller = channel.CALLERID("num"):get() or "UNKNOWN"

    local queue = channel.SUPPORT_QUEUE:get() or "support"
    local mailbox = channel.SUPPORT_MAILBOX:get() or "3000@support"
    local timeout = channel.QUEUE_TIMEOUT:get() or "30"

    local uniqueid = channel.UNIQUEID:get() or "UNKNOWN"
    app.NoOp("[LUA] Incoming call from " .. caller .. " | ID=" .. uniqueid)

    app.Answer()

    if is_business_open() then

        app.NoOp("[LUA] Business hours: OPEN")
        app.NoOp("[LUA] Routing to queue")

        app.Queue(queue, "", "", "", timeout)

        local status = channel.QUEUESTATUS:get() or "UNKNOWN"
        local abandoned = channel.ABANDONED:get()

        app.NoOp("[LUA] Queue status: " .. status)

        -- End successfully connected call
        if abandoned == "FALSE" or status == "CONTINUE" then

            app.NoOp("[LUA] Call finished")
            app.Hangup()
            return

        end

    else

        app.NoOp("[LUA] Business hours: CLOSED")

    end

    route_to_voicemail(mailbox)

    app.NoOp("[LUA] Call finished")
    app.Hangup()

end

-- Dialplan contexts
extensions = {

    ["support-lua"] = {

        ["2003"] = function(context, extension)
            customer_support()
        end;
    };

}
