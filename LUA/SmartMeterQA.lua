-- Smart Meter QuickApp for Fibaro HC3
-- Device: Double Digital Meter (双路电流互感计量器 WiFi版)
-- Protocol: Tuya LAN v3.5 (AES-128-GCM, 3-step session key negotiation)
--
-- DPS map:
--   103 device_state1  enum   (monitor / working)
--   105 cur_power1     value  /10  → W
--   106 cur_current1   value  /1000 → A
--   107 cur_voltage1   value  /10  → V
--   108 total_energy1  value  /1000 → kWh
--   109 today_acc_energy1 value /1000 → kWh
--   113 device_state2  enum
--   115 cur_power2     value  /10  → W
--   116 cur_current2   value  /1000 → A
--   117 cur_voltage2   value  /10  → V
--   118 total_energy2  value  /1000 → kWh
--   119 today_acc_energy2 value /1000 → kWh
--   123 all_energy     value  /1000 → kWh
--   124 net_state      enum   (cloud_net / …)
--
-- Required QuickApp variables:
--   devID, devKEY, devVER, ip, timeout, enableDebug
--   Auto-created child IDs: power1Child, energy1Child, power2Child, energy2Child, totalEnergyChild
--
-- UI labels : labelStatus, labelCh1, labelCh2, labelTotalEnergy, labelNetState
-- UI buttons: btn_connect, btn_disconnect, btn_refresh

-- ─── Child device classes ─────────────────────────────────────────────────────
class 'Meter'(QuickAppChild)
function Meter:__init(device)
    QuickAppChild.__init(self, device)
end

class 'PowerSensor'(QuickAppChild)
function PowerSensor:__init(device)
    QuickAppChild.__init(self, device)
end

-- ─── Per-channel state ────────────────────────────────────────────────────────
local ch1 = { state="—", voltage=0, current=0, power=0, energy=0, today=0 }
local ch2 = { state="—", voltage=0, current=0, power=0, energy=0, today=0 }

-- ─── Debug helpers ────────────────────────────────────────────────────────────

function QuickApp:dbg(...)
    if self.enableDebug then self:debug(...) end
end

function QuickApp:toHex(data)
    if not data then return "<nil>" end
    local bytes = {}
    for i = 1, #data do
        bytes[i] = string.format("%02X", string.byte(data, i))
    end
    return table.concat(bytes, " ")
end

function QuickApp:cmdName(cb)
    local n = {
        [3]="BIND/SESS_START", [4]="RENAME_GW/SESS_RESP", [5]="RENAME_DEV/SESS_FINISH",
        [7]="CONTROL", [8]="STATUS", [9]="HEART_BEAT", [10]="DP_QUERY",
        [13]="CONTROL_NEW", [16]="DP_QUERY_NEW", [18]="DP_REFRESH",
    }
    return n[cb] or ("?(" .. tostring(cb) .. ")")
end

-- ─── Init ─────────────────────────────────────────────────────────────────────

function QuickApp:onInit()
    self:debug("SmartMeter onInit (v3.5)")

    self.childs = {}
    self:createChildDevices()

    self.enabled        = api.get("/devices/" .. self.id).enabled
    self.enableDebug    = (self:getVariable("enableDebug") == "true")
    self.connect_timeout = tonumber(self:getVariable("timeout") or "30") * 1000
    self.devID          = self:getVariable("devID")
    self.real_local_key = self:getVariable("devKEY")  -- raw 16-byte ASCII key
    self.devVER         = self:getVariable("devVER")
    self.ip             = self:getVariable("ip")
    self.port           = 6668

    -- socket & timer handles
    self.sock       = nil
    self.sockloopID = nil
    self.dataloopID = nil
    self.sequenceN  = 1

    -- v3.5 session state machine
    -- states: "idle", "connecting", "negotiating", "ready"
    self.session_state  = "idle"
    self.session_key    = nil
    self.local_nonce    = nil
    self.remote_nonce   = nil

    self:debug(string.format("Config: ip=%s ver=%s debug=%s",
        self.ip, self.devVER, tostring(self.enableDebug)))

    self:updateView("labelStatus",      "text", "Initialising…")
    self:updateView("labelCh1",         "text", "Channel 1: —")
    self:updateView("labelCh2",         "text", "Channel 2: —")
    self:updateView("labelTotalEnergy", "text", "Total energy: —")
    self:updateView("labelNetState",    "text", "Network: —")

    self:connect()
end

-- ─── Child devices ────────────────────────────────────────────────────────────

function QuickApp:childDeviceExist(deviceId)
    if deviceId == nil then return false end
    local dev = api.get("/devices/" .. tostring(deviceId))
    if dev == nil then return false end
    return dev.parentId == self.id
end

function QuickApp:initChildDevice(varName, devName, devType, cls)
    local childId = self:getVariable(varName)
    if not self:childDeviceExist(childId) then
        local child = self:createChildDevice({ name=devName, type=devType }, cls)
        childId = child.id
        self:setVariable(varName, childId)
        self:trace(devName, "created:", child.id)
    end
    return self.childDevices[childId]
end

function QuickApp:createChildDevices()
    self:initChildDevices({
        ["com.fibaro.energyMeter"] = Meter,
        ["com.fibaro.powerMeter"]  = PowerSensor,
    })
    self.childs.power1Child = self:initChildDevice(
        "power1Child", "Meter Ch1 Power", "com.fibaro.powerMeter", PowerSensor)
    self.childs.power1Child:updateProperty("rateType", "consumption")

    self.childs.energy1Child = self:initChildDevice(
        "energy1Child", "Meter Ch1 Energy", "com.fibaro.energyMeter", Meter)
    self.childs.energy1Child:updateProperty("rateType", "consumption")

    self.childs.power2Child = self:initChildDevice(
        "power2Child", "Meter Ch2 Power", "com.fibaro.powerMeter", PowerSensor)
    self.childs.power2Child:updateProperty("rateType", "consumption")

    self.childs.energy2Child = self:initChildDevice(
        "energy2Child", "Meter Ch2 Energy", "com.fibaro.energyMeter", Meter)
    self.childs.energy2Child:updateProperty("rateType", "consumption")

    self.childs.totalEnergyChild = self:initChildDevice(
        "totalEnergyChild", "Meter Total Energy", "com.fibaro.energyMeter", Meter)
    self.childs.totalEnergyChild:updateProperty("rateType", "consumption")
end

-- ─── Button handlers ──────────────────────────────────────────────────────────

function QuickApp:connectPressed()
    if self.session_state ~= "idle" then
        self:debug("connectPressed: already connected (state=" .. self.session_state .. ")")
        return
    end
    self:debug("connectPressed: initiating connection")
    self:connect()
end

function QuickApp:disconnectPressed()
    self:debug("disconnectPressed: forcing disconnect")
    self:cancelTimers()
    self:closeSocket()
    self.session_state = "idle"
    self:updateView("labelStatus", "text", "Disconnected")
end

function QuickApp:refreshPressed()
    self:debug("refreshPressed: reconnecting")
    -- Cancel any pending reconnect, disconnect cleanly, then reconnect immediately
    self:cancelTimers()
    self:closeSocket()
    self.session_state = "idle"
    self:connect()
end

-- ─── TCP connection ───────────────────────────────────────────────────────────

function QuickApp:connect()
    if not self.enabled then return end
    if self.ip == "changeme" or self.ip == "" then
        self:debug("connect: ip not configured")
        return
    end
    if self.session_state ~= "idle" then
        self:dbg("connect: already in state=" .. self.session_state)
        return
    end

    self.session_state = "connecting"
    self.sequenceN     = 1
    self.session_key   = nil
    self.local_nonce   = nil
    self.remote_nonce  = nil

    -- Fresh socket for each connection
    self.sock = net.TCPSocket()

    self:dbg("TCP connecting to " .. self.ip .. ":" .. self.port)
    self:updateView("labelStatus", "text", "Connecting…")

    self.sock:connect(self.ip, self.port, {
        success = function()
            self:debug("TCP connected — starting v3.5 session")
            self.session_state = "negotiating"
            -- Register read handler FIRST so we never miss a packet
            self:waitForData()
            -- Send CMD3: session key negotiation start
            self:sendSessionStart()
        end,
        error = function(err)
            self:debug("TCP connect error: " .. tostring(err))
            self:closeSocket()
            self.session_state = "idle"
            self:updateView("labelStatus", "text", "Connect failed")
            self.sockloopID = fibaro.setTimeout(
                self.connect_timeout, function() self:connect() end)
        end,
    })
end

-- Cancel all outstanding timers
function QuickApp:cancelTimers()
    if self.sockloopID ~= nil then
        clearTimeout(self.sockloopID)
        self.sockloopID = nil
    end
    if self.dataloopID ~= nil then
        clearTimeout(self.dataloopID)
        self.dataloopID = nil
    end
end

-- Close socket quietly
function QuickApp:closeSocket()
    if self.sock then
        tools.try(function() self.sock:close() end, function() end)
        self.sock = nil
    end
end

-- Full disconnect: cancel timers, close socket, reset session
function QuickApp:disconnect()
    self:cancelTimers()
    self:closeSocket()
    self.session_state = "idle"
    self.session_key   = nil
    self.local_nonce   = nil
    self.remote_nonce  = nil
    self.sequenceN     = 1
    self:updateView("labelStatus", "text", "Disconnected")
end

-- ─── Session negotiation ──────────────────────────────────────────────────────

-- Step 1: Send CMD3 with 16-byte random local_nonce (encrypted with real_local_key)
function QuickApp:sendSessionStart()
    self.local_nonce = gcmlib.random_bytes(16)
    self:dbg("local_nonce: " .. self:toHex(self.local_nonce))

    local pkt = tuyAPI.encode35({
        data        = self.local_nonce,
        key         = self.real_local_key,
        commandByte = tuyAPI.tuyaCommandType.BIND,  -- CMD 3
        sequenceN   = self.sequenceN,
    })
    self.sequenceN = self.sequenceN + 1

    self:dbg("Sending CMD3 (SESS_START): " .. self:toHex(pkt))
    self.sock:write(pkt, {
        success = function()
            self:dbg("CMD3 write OK — waiting for CMD4")
        end,
        error = function(err)
            self:debug("CMD3 write failed: " .. tostring(err))
            self:disconnect()
            self:updateView("labelStatus", "text", "Session start failed")
            self.sockloopID = fibaro.setTimeout(
                self.connect_timeout, function() self:connect() end)
        end,
    })
end

-- Step 2 (received): CMD4 with device HMAC + remote_nonce
-- plaintext = HMAC-SHA256(real_local_key, local_nonce)[32] + remote_nonce[16]
function QuickApp:handleSessionCmd4(plaintext)
    self:dbg("CMD4 raw plaintext (" .. #plaintext .. " bytes): " .. self:toHex(plaintext))

    if #plaintext < 52 then
        self:debug("CMD4 payload too short: " .. #plaintext .. " bytes (expected 52)")
        self:disconnect()
        self.sockloopID = fibaro.setTimeout(
            self.connect_timeout, function() self:connect() end)
        return
    end

    -- Layout: [retcode(4)] + [remote_nonce(16)] + [HMAC-SHA256(real_local_key, local_nonce)(32)]
    -- (retcode is present in raw GCM plaintext; tinytuya strips it before the handler sees it)
    local remote_nonce = string.sub(plaintext, 5, 20)
    local recv_hmac    = string.sub(plaintext, 21, 52)

    -- Verify device's HMAC of our local_nonce
    local expected_hmac = sha256lib.hmac(self.real_local_key, self.local_nonce)
    local match = true
    for i = 1, 32 do
        if string.byte(recv_hmac, i) ~= string.byte(expected_hmac, i) then
            match = false; break
        end
    end
    if not match then
        self:debug("CMD4 HMAC mismatch — wrong key or rogue device, aborting")
        self:disconnect()
        return
    end

    self:dbg("CMD4 HMAC OK")
    self.remote_nonce = remote_nonce
    self:dbg("remote_nonce: " .. self:toHex(self.remote_nonce))

    -- Derive session key:
    --   xor_nonces = local_nonce XOR remote_nonce
    --   session_key = first 16 bytes of GCM-encrypt(real_local_key, local_nonce[1:12], xor_nonces, "")
    local xor_parts = {}
    for i = 1, 16 do
        xor_parts[i] = string.char(
            string.byte(self.local_nonce, i) ~ string.byte(self.remote_nonce, i))
    end
    local xor_nonces = table.concat(xor_parts)
    local gcm_out    = gcmlib.encrypt(
        self.real_local_key,
        string.sub(self.local_nonce, 1, 12),
        xor_nonces,
        "")
    self.session_key = string.sub(gcm_out, 1, 16)
    self:dbg("session_key derived: " .. self:toHex(self.session_key))

    -- Step 3: Send CMD5 with HMAC-SHA256(real_local_key, remote_nonce)
    local hmac5 = sha256lib.hmac(self.real_local_key, self.remote_nonce)
    local pkt5  = tuyAPI.encode35({
        data        = hmac5,
        key         = self.real_local_key,
        commandByte = tuyAPI.tuyaCommandType.RENAME_DEVICE,  -- CMD 5
        sequenceN   = self.sequenceN,
    })
    self.sequenceN = self.sequenceN + 1

    self:dbg("Sending CMD5 (SESS_FINISH): " .. self:toHex(pkt5))
    self.sock:write(pkt5, {
        success = function()
            self:debug("CMD5 write OK — session established with session_key")
            self.session_state = "ready"
            self:updateView("labelStatus", "text", "Connected (v3.5)")
            -- Request data immediately
            self:requestData()
        end,
        error = function(err)
            self:debug("CMD5 write failed: " .. tostring(err))
            self:disconnect()
            self:updateView("labelStatus", "text", "Session finish failed")
            self.sockloopID = fibaro.setTimeout(
                self.connect_timeout, function() self:connect() end)
        end,
    })
end

-- ─── Data request ─────────────────────────────────────────────────────────────

function QuickApp:requestData()
    if self.session_state ~= "ready" then return end
    local ts = os.time()
    local payload_data = json.encode({
        gwId  = self.devID,
        devId = self.devID,
        t     = ts,
        uid   = self.devID,
    })
    local pkt = tuyAPI.encode35({
        data        = payload_data,
        key         = self.session_key,
        commandByte = tuyAPI.tuyaCommandType.DP_QUERY,  -- CMD 10
        sequenceN   = self.sequenceN,
    })
    self.sequenceN = self.sequenceN + 1
    self:dbg("Sending DP_QUERY (sn=" .. (self.sequenceN-1) .. ")")
    self.sock:write(pkt, {
        success = function() self:dbg("DP_QUERY write OK") end,
        error   = function(err)
            self:debug("DP_QUERY write failed: " .. tostring(err))
        end,
    })
end

-- ─── Data loop ────────────────────────────────────────────────────────────────

function QuickApp:waitForData()
    if not self.sock then return end
    self.sock:read({
        success = function(data)
            if not data or #data == 0 then
                self:waitForData()
                return
            end
            self:dbg(string.format("Packet received: %d bytes", #data))
            self:dbg("Raw hex: " .. self:toHex(data))

            -- Determine protocol by prefix
            local prefix = string.unpack(">I4", data, 1)

            if prefix == 0x00006699 then
                -- ── v3.5 packet ────────────────────────────────────────────
                local ct, aad, iv, cmd, seqno, err = tuyAPI.parsePacket35(data)
                if err then
                    self:debug("parsePacket35 error: " .. err)
                    self:waitForData()
                    return
                end
                self:dbg(string.format("v3.5 header — seq=%d  cmd=%d (%s)  ct_len=%d",
                    seqno or 0, cmd or 0, self:cmdName(cmd), #ct))

                -- Choose decryption key
                local dkey
                if cmd == tuyAPI.tuyaCommandType.RENAME_GW then  -- CMD4: device uses real_local_key
                    dkey = self.real_local_key
                elseif self.session_key then
                    dkey = self.session_key
                else
                    dkey = self.real_local_key
                end

                local plaintext, perr = tuyAPI.getPayload35(ct, aad, iv, dkey)
                if perr or not plaintext then
                    self:debug("getPayload35 error: " .. tostring(perr))
                    self:waitForData()
                    return
                end
                self:dbg("Decrypted (" .. #plaintext .. " bytes): " .. self:toHex(plaintext))

                -- Dispatch on command byte
                if cmd == tuyAPI.tuyaCommandType.RENAME_GW then  -- CMD 4
                    self:handleSessionCmd4(plaintext)

                elseif cmd == tuyAPI.tuyaCommandType.STATUS or       -- CMD 8
                       cmd == tuyAPI.tuyaCommandType.CONTROL_NEW or  -- CMD 13
                       cmd == tuyAPI.tuyaCommandType.DP_QUERY or     -- CMD 10
                       cmd == tuyAPI.tuyaCommandType.DP_QUERY_NEW or -- CMD 16
                       cmd == tuyAPI.tuyaCommandType.DP_REFRESH then -- CMD 18
                    self:handleDataPayload(plaintext, cmd)

                elseif cmd == tuyAPI.tuyaCommandType.HEART_BEAT then -- CMD 9
                    self:dbg("HEART_BEAT ack")

                else
                    self:debug("Unhandled v3.5 cmd=" .. tostring(cmd))
                end

            elseif prefix == 0x000055AA then
                -- ── v3.3 packet (unexpected but log gracefully) ────────────
                self:debug("Received v3.3 packet (55AA) — device may not be in v3.5 mode")
                local ok, payload, commandByte = pcall(function()
                    return tuyAPI.parse(data, self.real_local_key, self.devVER)
                end)
                if ok and type(payload) == "table" and payload.dps then
                    self:handleDps(payload.dps)
                end

            else
                self:debug(string.format("Unknown packet prefix 0x%08X", prefix))
            end

            self:waitForData()
        end,

        error = function(err)
            self:debug("Socket read error: " .. tostring(err))
            local was_ready = (self.session_state == "ready")
            self:cancelTimers()
            self:closeSocket()
            self.session_state = "idle"
            if err == "End of file" then
                -- Push-only device: it sends data then closes connection.
                -- Schedule reconnect after the full timeout.
                self:updateView("labelStatus", "text", "Waiting for next push…")
            else
                self:updateView("labelStatus", "text", "Connection error")
            end
            self.dataloopID = fibaro.setTimeout(
                self.connect_timeout, function() self:connect() end)
        end,
    })
end

-- ─── Data payload handler ─────────────────────────────────────────────────────

function QuickApp:handleDataPayload(plaintext, cmd)
    self:dbg(string.format("handleDataPayload cmd=%d (%s)  len=%d",
        cmd, self:cmdName(cmd), #plaintext))

    -- Skip 4-byte return code if present (device-sent data packets start with 00 00 00 00)
    local json_str = plaintext
    if #plaintext >= 4 then
        local rc = string.unpack(">I4", plaintext, 1)
        if rc == 0 then
            json_str = string.sub(plaintext, 5)
            self:dbg("Skipped 4-byte retcode=0")
        end
    end

    -- Remove any leading version prefix bytes ("3.5" etc.) if present
    if #json_str >= 3 and string.sub(json_str, 1, 1) == "3" then
        -- version prefix like "3.5" (3 bytes)
        local maybe_ver = string.sub(json_str, 1, 3)
        if maybe_ver:match("^3%.[0-9]") then
            json_str = string.sub(json_str, 4)
            self:dbg("Stripped version prefix '" .. maybe_ver .. "'")
        end
    end

    self:dbg("JSON string to decode: " .. json_str)

    local ok, result = pcall(json.decode, json_str)
    if not ok then
        self:debug("JSON decode failed: " .. tostring(result))
        self:debug("Raw payload hex: " .. self:toHex(plaintext))
        return
    end

    -- DPS can be at result.dps  OR  result.data.dps  (v3.5 nested format)
    local dps = nil
    if type(result) == "table" then
        if result.dps then
            dps = result.dps
        elseif result.data and type(result.data) == "table" and result.data.dps then
            dps = result.data.dps
        end
    end

    if dps then
        self:dbg("DPS: " .. json.encode(dps))
        self:handleDps(dps)
        self:updateView("labelStatus", "text", "Connected (v3.5)")
    else
        self:debug("No DPS in payload — result: " .. json.encode(result))
    end
end

-- ─── DPS handler ─────────────────────────────────────────────────────────────

function QuickApp:handleDps(resp)
    self:dbg("handleDps called")

    -- Channel 1
    if resp['103'] ~= nil then ch1.state   = tostring(resp['103']) end
    if resp['107'] ~= nil then ch1.voltage = resp['107'] / 10 end
    if resp['106'] ~= nil then ch1.current = resp['106'] / 1000 end
    if resp['105'] ~= nil then
        ch1.power = resp['105'] / 10
        if self.childs.power1Child then
            self.childs.power1Child:updateProperty("value", ch1.power)
        end
    end
    if resp['108'] ~= nil then
        ch1.energy = resp['108'] / 1000
        if self.childs.energy1Child then
            self.childs.energy1Child:updateProperty("value", ch1.energy)
        end
    end
    if resp['109'] ~= nil then ch1.today = resp['109'] / 1000 end

    -- Channel 2
    if resp['113'] ~= nil then ch2.state   = tostring(resp['113']) end
    if resp['117'] ~= nil then ch2.voltage = resp['117'] / 10 end
    if resp['116'] ~= nil then ch2.current = resp['116'] / 1000 end
    if resp['115'] ~= nil then
        ch2.power = resp['115'] / 10
        if self.childs.power2Child then
            self.childs.power2Child:updateProperty("value", ch2.power)
        end
    end
    if resp['118'] ~= nil then
        ch2.energy = resp['118'] / 1000
        if self.childs.energy2Child then
            self.childs.energy2Child:updateProperty("value", ch2.energy)
        end
    end
    if resp['119'] ~= nil then ch2.today = resp['119'] / 1000 end

    -- Combined
    if resp['123'] ~= nil then
        local kwh = resp['123'] / 1000
        self:updateView("labelTotalEnergy", "text",
            string.format("Total energy:  %.3f kWh", kwh))
        if self.childs.totalEnergyChild then
            self.childs.totalEnergyChild:updateProperty("value", kwh)
        end
    end
    if resp['124'] ~= nil then
        self:updateView("labelNetState", "text", "Network: " .. tostring(resp['124']))
    end

    self:dbg(string.format(
        "Ch1: state=%s  U=%.1fV  I=%.3fA  P=%.1fW  E=%.3fkWh  today=%.3fkWh",
        ch1.state, ch1.voltage, ch1.current, ch1.power, ch1.energy, ch1.today))
    self:dbg(string.format(
        "Ch2: state=%s  U=%.1fV  I=%.3fA  P=%.1fW  E=%.3fkWh  today=%.3fkWh",
        ch2.state, ch2.voltage, ch2.current, ch2.power, ch2.energy, ch2.today))

    self:updateView("labelCh1", "text", string.format(
        "Channel 1  [%s]\n"  ..
        "  Voltage:  %.1f V\n"  ..
        "  Current:  %.3f A\n" ..
        "  Power:    %.1f W\n" ..
        "  Total:    %.3f kWh\n" ..
        "  Today:    %.3f kWh",
        ch1.state, ch1.voltage, ch1.current, ch1.power, ch1.energy, ch1.today))

    self:updateView("labelCh2", "text", string.format(
        "Channel 2  [%s]\n"  ..
        "  Voltage:  %.1f V\n"  ..
        "  Current:  %.3f A\n" ..
        "  Power:    %.1f W\n" ..
        "  Total:    %.3f kWh\n" ..
        "  Today:    %.3f kWh",
        ch2.state, ch2.voltage, ch2.current, ch2.power, ch2.energy, ch2.today))
end
