-- Smart Meter QuickApp for Fibaro HC3
-- Device: Double Digital Meter (双路电流互感计量器 WiFi版)
-- Tuya category: cz | 2-channel CT clamp energy monitor (read-only)
--
-- DPS map:
--   103 device_state1  enum   (monitor / working)
--   105 cur_power1     value  /10  → W
--   106 cur_current1   value  /1000 → A
--   107 cur_voltage1   value  /10  → V
--   108 total_energy1  value  /1000 → kWh  (raw unit: Wh)
--   109 today_acc_energy1 value /1000 → kWh
--   113 device_state2  enum
--   115 cur_power2     value  /10  → W
--   116 cur_current2   value  /1000 → A
--   117 cur_voltage2   value  /10  → V
--   118 total_energy2  value  /1000 → kWh
--   119 today_acc_energy2 value /1000 → kWh
--   123 all_energy     value  /1000 → kWh  (ch1 + ch2 combined)
--   124 net_state      enum   (cloud_net / …)
--
-- Required QuickApp variables:
--   devID, devKEY, devVER, ip, timeout
--   enableDebug  (set to "true" to enable verbose logging, anything else = off)
--   (child IDs are auto-created: power1Child, energy1Child,
--    power2Child, energy2Child, totalEnergyChild)
--
-- UI labels: labelStatus, labelCh1, labelCh2, labelTotalEnergy, labelNetState

-- ─── Child device classes ─────────────────────────────────────────────────────
-- Must be defined before onInit so initChildDevices() can resolve them.

class 'Meter'(QuickAppChild)
function Meter:__init(device)
    QuickAppChild.__init(self, device)
end

class 'PowerSensor'(QuickAppChild)
function PowerSensor:__init(device)
    QuickAppChild.__init(self, device)
end

-- ─── Per-channel state (kept in sync across partial DPS updates) ──────────────
local ch1 = { state = "—", voltage = 0, current = 0, power = 0, energy = 0, today = 0 }
local ch2 = { state = "—", voltage = 0, current = 0, power = 0, energy = 0, today = 0 }

-- ─── Debug helpers ────────────────────────────────────────────────────────────

function QuickApp:dbg(...)
    if self.enableDebug then
        self:debug(...)
    end
end

-- Convert a binary string to a spaced hex string for logging
function QuickApp:toHex(data)
    if not data then return "<nil>" end
    local bytes = {}
    for i = 1, #data do
        bytes[i] = string.format("%02X", string.byte(data, i))
    end
    return table.concat(bytes, " ")
end

-- ─── Init ─────────────────────────────────────────────────────────────────────

function QuickApp:onInit()
    self:debug("SmartMeter onInit")

    self.childs = {}
    self:createChildDevices()

    self.enabled      = api.get("/devices/" .. self.id).enabled
    self.enableDebug  = (self:getVariable("enableDebug") == "true")
    self.connect_timeout = tonumber(self:getVariable("timeout")) * 1000
    self.devID        = self:getVariable("devID")
    self.devKEY       = self:getVariable("devKEY")
    self.devVER       = self:getVariable("devVER")
    self.ip           = self:getVariable("ip")
    self.port         = 6668
    self.sock         = net.TCPSocket()
    self.stateloopID  = nil
    self.sockloopID   = nil
    self.dataloopID   = nil
    self.pingloopID   = nil
    self.sequenceN    = 1

    self:debug(string.format("Config: ip=%s ver=%s enableDebug=%s",
        self.ip, self.devVER, tostring(self.enableDebug)))
    self:connect()
end

-- ─── Child devices ────────────────────────────────────────────────────────────

function QuickApp:childDeviceExist(deviceId)
    if deviceId == nil then return false end
    local dev = api.get("/devices/" .. tostring(deviceId))
    if dev == nil then return false end
    return dev.parentId == self.id
end

function QuickApp:initChildDevice(variableName, deviceName, devType, class)
    local childId = self:getVariable(variableName)
    if not self:childDeviceExist(childId) then
        local child = self:createChildDevice({ name = deviceName, type = devType }, class)
        childId = child.id
        self:setVariable(variableName, childId)
        self:trace(deviceName, "created:", child.id)
    end
    return self.childDevices[childId]
end

function QuickApp:createChildDevices()
    self:initChildDevices({
        ["com.fibaro.energyMeter"] = Meter,
        ["com.fibaro.powerMeter"]  = PowerSensor,
    })

    -- Channel 1
    self.childs.power1Child = self:initChildDevice(
        "power1Child", "Meter Ch1 Power", "com.fibaro.powerMeter", PowerSensor)
    self.childs.power1Child:updateProperty("rateType", "consumption")

    self.childs.energy1Child = self:initChildDevice(
        "energy1Child", "Meter Ch1 Energy", "com.fibaro.energyMeter", Meter)
    self.childs.energy1Child:updateProperty("rateType", "consumption")

    -- Channel 2
    self.childs.power2Child = self:initChildDevice(
        "power2Child", "Meter Ch2 Power", "com.fibaro.powerMeter", PowerSensor)
    self.childs.power2Child:updateProperty("rateType", "consumption")

    self.childs.energy2Child = self:initChildDevice(
        "energy2Child", "Meter Ch2 Energy", "com.fibaro.energyMeter", Meter)
    self.childs.energy2Child:updateProperty("rateType", "consumption")

    -- Combined total
    self.childs.totalEnergyChild = self:initChildDevice(
        "totalEnergyChild", "Meter Total Energy", "com.fibaro.energyMeter", Meter)
    self.childs.totalEnergyChild:updateProperty("rateType", "consumption")
end

-- ─── TCP connection ───────────────────────────────────────────────────────────

function QuickApp:connect()
    if not self.enabled then return end
    if self.ip == "changeme" then return end

    self:dbg("Connecting to " .. self.ip .. ":" .. self.port)

    local ts = os.time()
    payloadKeys = { gwId = 1, devId = 2, t = 3, uid = 4 }
    payloadMax  = 4
    local payloaddata = {
        gwId  = self.devID,
        devId = self.devID,
        t     = ts,
        uid   = self.devID
    }
    local myoptions = {
        data        = tools.prettyJson(payloaddata),
        key         = self.devKEY,
        version     = self.devVER,
        commandByte = tuyAPI.tuyaCommandType.DP_QUERY
    }
    local payload = tuyAPI.tuyaEncode(myoptions)
    self:dbg("DP_QUERY payload hex: " .. self:toHex(payload))

    self.sock:connect(self.ip, self.port, {
        success = function()
            self:debug("TCP connected, sending DP_QUERY")
            self.sock:write(payload)
            self.pingloopID = setInterval(function() self:pingTuya() end, 60000)
            self:waitForData()
        end,
        error = function(err)
            self:debug("TCP connect error: " .. tostring(err))
            self.sock:close()
            self.sequenceN = 1
            self:disconnect()
            self:updateView("labelStatus", "text", "Connection lost")
            self.sockloopID = fibaro.setTimeout(self.connect_timeout, function() self:connect() end)
        end,
    })
end

function QuickApp:disconnect()
    if self.ip == "changeme" then return end
    tools.try(function()
        if self.stateloopID ~= nil then clearTimeout(self.stateloopID) end
        if self.sockloopID  ~= nil then clearTimeout(self.sockloopID) end
        if self.pingloopID  ~= nil then clearInterval(self.pingloopID) end
        if self.dataloopID  ~= nil then clearTimeout(self.dataloopID) end
    end, function(e)
        if self.stateloopID ~= nil then clearTimeout(self.stateloopID) end
        if self.sockloopID  ~= nil then clearTimeout(self.sockloopID) end
        if self.pingloopID  ~= nil then clearInterval(self.pingloopID) end
        if self.dataloopID  ~= nil then clearTimeout(self.dataloopID) end
    end)
    self.sock:close()
    self:updateView("labelStatus", "text", "Connection lost")
    self.sequenceN = 1
end

-- ─── Data loop ────────────────────────────────────────────────────────────────

function QuickApp:waitForData()
    if not self.enabled then return end
    self.sock:read({
        success = function(data)
            local dataLen = data and #data or 0
            self:dbg(string.format("Packet received: %d bytes", dataLen))

            -- Validate prefix
            local prefix = string.sub(data, 1, 4)
            local expectedPrefix = string.pack(">I", 0x000055AA)
            if prefix ~= expectedPrefix then
                self:debug(string.format(
                    "BAD PREFIX — expected 00 00 55 AA, got: %s | full hex: %s",
                    self:toHex(prefix), self:toHex(data)))
                self:waitForData()
                return
            end

            -- Log raw packet and header fields
            self:dbg("Raw hex: " .. self:toHex(data))
            if dataLen >= 16 then
                local seq = string.unpack(">I4", data, 5)
                local cmd = string.unpack(">I4", data, 9)
                local len = string.unpack(">I4", data, 13)
                self:dbg(string.format(
                    "Header — seq=%d  cmd=%d (%s)  payloadLen=%d",
                    seq, cmd, self:cmdName(cmd), len))

                -- Log first 16 bytes after header to reveal return-code vs version prefix
                if dataLen >= 32 then
                    self:dbg("Bytes 17-32: " .. self:toHex(string.sub(data, 17, 32)))
                end
            end

            self:updateView("labelStatus", "text", "Connected")

            -- Parse
            local ok, payload, commandByte, sequenceN = pcall(function()
                return tuyAPI.parse(data, self.devKEY, self.devVER)
            end)
            if not ok then
                self:debug("tuyAPI.parse threw an error: " .. tostring(payload))
                self:waitForData()
                return
            end

            self:dbg(string.format("Parsed — cb=%s  sn=%s  payload type=%s",
                tostring(commandByte), tostring(sequenceN), type(payload)))
            if type(payload) == "table" then
                self:dbg("Payload JSON: " .. json.encode(payload))
            elseif type(payload) == "string" then
                self:debug("Payload is a string (parse/decrypt issue?): " .. tostring(payload))
            end

            local cb = tonumber(commandByte)
            if cb == tuyAPI.tuyaCommandType.DP_QUERY or
               cb == tuyAPI.tuyaCommandType.STATUS or
               cb == tuyAPI.tuyaCommandType.CONTROL_NEW then
                if payload and type(payload) == "table" and payload.dps then
                    self:dbg("DPS keys: " .. json.encode(payload.dps))
                    self:handleDps(payload.dps)
                else
                    self:debug(string.format(
                        "No dps in payload — cb=%s payload=%s",
                        tostring(cb), tostring(payload)))
                end
            elseif cb == tuyAPI.tuyaCommandType.HEART_BEAT then
                self:dbg("HEART_BEAT ack received")
            else
                self:debug("Unhandled command byte: " .. tostring(cb))
            end

            self:waitForData()
        end,
        error = function(err)
            self:debug("Socket read error: " .. tostring(err))
            self.sock:close()
            self.sequenceN = 1
            self:disconnect()
            -- This meter is push-only: it sends one CONTROL_NEW then closes (EOF).
            -- Reconnect immediately so we are ready for the next push cycle.
            local delay = (err == "End of file") and 100 or self.connect_timeout
            self:updateView("labelStatus", "text", (err == "End of file") and "Waiting for push..." or "Connection error")
            self.dataloopID = fibaro.setTimeout(delay, function() self:connect() end)
        end
    })
end

-- ─── DPS handler ─────────────────────────────────────────────────────────────

function QuickApp:handleDps(resp)
    self:dbg("handleDps called")

    -- Channel 1 ---------------------------------------------------------------
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

    -- Channel 2 ---------------------------------------------------------------
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

    -- Combined ----------------------------------------------------------------
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

    -- Refresh consolidated channel labels -------------------------------------
    self:updateView("labelCh1", "text", string.format(
        "Channel 1  [%s]\n" ..
        "  Voltage:  %.1f V\n" ..
        "  Current:  %.3f A\n" ..
        "  Power:    %.1f W\n" ..
        "  Total:    %.3f kWh\n" ..
        "  Today:    %.3f kWh",
        ch1.state, ch1.voltage, ch1.current, ch1.power, ch1.energy, ch1.today))

    self:updateView("labelCh2", "text", string.format(
        "Channel 2  [%s]\n" ..
        "  Voltage:  %.1f V\n" ..
        "  Current:  %.3f A\n" ..
        "  Power:    %.1f W\n" ..
        "  Total:    %.3f kWh\n" ..
        "  Today:    %.3f kWh",
        ch2.state, ch2.voltage, ch2.current, ch2.power, ch2.energy, ch2.today))
end

-- ─── Keep-alive & state refresh ──────────────────────────────────────────────

function QuickApp:pingTuya()
    if not self.enabled then return end
    local myoptions = {
        data        = json.encode({}),
        commandByte = tuyAPI.tuyaCommandType.HEART_BEAT,
        sequenceN   = self.sequenceN
    }
    local payload = tuyAPI.tuyaEncode(myoptions)
    self.sock:write(payload, {
        success = function()
            self:dbg("HEART_BEAT sent")
            self:updateView("labelStatus", "text", "Connected")
            fibaro.setTimeout(60000, function() self:updateTuyaState() end)
        end,
        error = function(err)
            self:debug("Error sending HEART_BEAT: " .. tostring(err))
            self:disconnect()
            self:updateView("labelStatus", "text", "Connection lost")
            self.sockloopID = fibaro.setTimeout(self.connect_timeout, function() self:connect() end)
        end
    })
end

function QuickApp:updateTuyaState()
    if not self.enabled then return end
    payloadKeys = { gwId = 1, devId = 2, t = 3, dps = 4, uid = 5 }
    payloadMax  = 5
    local ts = os.time()
    local payloaddata = {
        gwId  = self.devID,
        devId = self.devID,
        t     = ts,
        dps   = {},
        uid   = ""
    }
    local myoptions = {
        data        = tools.prettyJson(payloaddata),
        key         = self.devKEY,
        version     = self.devVER,
        commandByte = tuyAPI.tuyaCommandType.DP_QUERY,
        sequenceN   = self.sequenceN
    }
    self.sequenceN = self.sequenceN + 1
    local payload = tuyAPI.tuyaEncode(myoptions)
    self.sock:write(payload, {
        success = function()
            self:dbg("DP_Query sent (sn=" .. (self.sequenceN - 1) .. ")")
        end,
        error = function(err)
            self:debug("Error sending DP_Query: " .. tostring(err))
            self:disconnect()
            self:updateView("labelStatus", "text", "Connection lost")
            self.sockloopID = fibaro.setTimeout(self.connect_timeout, function() self:connect() end)
        end
    })
end

-- ─── Utility ─────────────────────────────────────────────────────────────────

-- Human-readable name for a Tuya command byte
function QuickApp:cmdName(cb)
    local names = {
        [7]  = "CONTROL",
        [8]  = "STATUS",
        [9]  = "HEART_BEAT",
        [10] = "DP_QUERY",
        [13] = "CONTROL_NEW",
        [16] = "DP_QUERY_NEW",
        [18] = "DP_REFRESH",
    }
    return names[cb] or ("?(" .. tostring(cb) .. ")")
end
