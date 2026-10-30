local version = "30.10.2026"
script_author("Melvin Costra")
script_name("Auto trade")
script_description("Этот скрипт был создан для автоматизации процесса обмена предметами между игроками во время трейда (/itrade). Он позволяет мгновенно выполнять обмен предметами на основе параметров, заданных игроком, без необходимости ручного вмешательства.")
script_version(version)
script_url("https://github.com/melvin-costra/auto-trade.git")

local ev = require "samp.events"
local imgui = require 'mimgui'
local keys = require "vkeys"
local encoding = require 'encoding'
encoding.default = 'CP1251'
local u8 = encoding.UTF8

local function wrapToGame(fnName)
    local original = _G[fnName]
    _G[fnName] = function(...)
    local n = select("#", ...)
    local args = {...}
    for i = 1, n do
        if type(args[i]) == "string" then
            args[i] = u8:decode(args[i])
        end
    end
    return original(unpack(args, 1, n))
    end
end
wrapToGame("sampAddChatMessage")
wrapToGame("sampSendChat")

local window = imgui.new.bool(false)
local CONFIG_PATH = "moonloader/config/auto-trade.json"
local isTradeInProgress = false
local isSubmitInProgress = false
local ammoValue = nil
local itemsToTrade = {}
local tradeItemToRemove = nil
local acceptTextDrawId = nil
local emptySlotId = 19478
local darkSlotColor = 4280098087
local antiflood = os.clock() * 1000

local cfg = {
    version = version,
    items = {
        { id = 1575, name = "drugs", amount = 50, limit = 50, min = 1, max = 300, step = 25, isSelected = false },
        { id = 347, name = "sdpistol", amount = 50, limit = 50, min = 1, max = 10000, step = 25, isSelected = true },
        { id = 348, name = "deagle", amount = 50, limit = 50, min = 1, max = 10000, step = 25, isSelected = true },
        { id = 349, name = "shotgun", amount = 40, limit = 40, min = 1, max = 10000, step = 25, isSelected = true },
        { id = 353, name = "smg", amount = 150, limit = 150, min = 1, max = 10000, step = 50, isSelected = true },
        { id = 355, name = "ak47", amount = 200, limit = 200, min = 1, max = 10000, step = 50, isSelected = true },
        { id = 356, name = "m4", amount = 200, limit = 200, min = 1, max = 10000, step = 50, isSelected = true },
        { id = 357, name = "rifle", amount = 50, limit = 50, min = 1, max = 10000, step = 25, isSelected = true }
    },
    settings = {
        isActivated = false,
        accept_trade_request = false,
        auto_press_accept = false,
        delay = 300
    }
}

local ui = {
    settings = {
        isActivated = imgui.new.bool(cfg.settings.isActivated),
        acceptTradeRequest = imgui.new.bool(cfg.settings.accept_trade_request),
        autoPressAccept = imgui.new.bool(cfg.settings.auto_press_accept),
        delay = imgui.new.int(cfg.settings.delay)
    },
    items = {
        drugs     = { label = "Drugs" },
        sdpistol  = { label = "SDPistol" },
        deagle    = { label = "Deagle" },
        shotgun   = { label = "Shotgun" },
        smg       = { label = "SMG" },
        ak47      = { label = "AK47" },
        m4        = { label = "M4" },
        rifle     = { label = "Rifle" }
    }
}

local slots_inventory = {
    { 280.5, 164 },
    { 316.5, 164 },
    { 352.5, 164 },
    { 388.5, 164 },
    { 424.5, 164 },
    { 280.5, 205 },
    { 316.5, 205 },
    { 352.5, 205 },
    { 388.5, 205 },
    { 424.5, 205 },
    { 280.5, 246 },
    { 316.5, 246 },
    { 352.5, 246 },
    { 388.5, 246 },
    { 424.5, 246 },
    { 280.5, 287 },
    { 316.5, 287 },
    { 352.5, 287 },
    { 388.5, 287 },
    { 424.5, 287 },
}

function saveCFG(table, path)
    local save = io.open(path, "w")
    if save then
        save:write(encodeJson(table))
        save:close()
    end
end

function loadCFG()
    if not doesDirectoryExist('moonloader/config') then createDirectory("moonloader/config") end

    if not doesFileExist(CONFIG_PATH) then
        saveCFG(cfg, CONFIG_PATH)
    else
        local file = io.open(CONFIG_PATH, 'r')
        if file then
            local fileCFG = decodeJson(file:read('*a'))
            file:close()
            if fileCFG.version == cfg.version then
                cfg = fileCFG
            else
                saveCFG(cfg, CONFIG_PATH)
            end
        end

        for _, item in ipairs(cfg.items) do
            local state = ui.items[item.name]
            state.isSelected = imgui.new.bool(item.isSelected)
            state.amount = imgui.new.int(item.amount)
            state.limit = imgui.new.int(item.limit)
        end
    end
end


function main()
    if not isSampLoaded() or not isSampfuncsLoaded() then return end
    while not isSampAvailable() do wait(100) end

    loadCFG()

    sampRegisterChatCommand("atrade", function()
        window[0] = not window[0]
    end)

    while true do
        wait(0)
        if isTradeInProgress then
            autoTrade()
        elseif isSubmitInProgress then
            sendSubmit()
        end
        if isKeyDown(keys.VK_RBUTTON) and isKeyJustPressed(keys.VK_Q) then
            requestTrade()
        end
    end
end

function printMessage(text)
    sampAddChatMessage("{00FF66}[ATrade]: {FFFFFF}" .. text, -1)
end

function requestTrade()
    local valid, ped = getCharPlayerIsTargeting(PLAYER_HANDLE)
    if valid and doesCharExist(ped) then
        local result, id = sampGetPlayerIdByCharHandle(ped)
        if result then
            sampSendChat("/itrade " .. id)
        end
    end
end

function tradeInventoryItem(posX, posY)
    for i = 0, 2500 do
        if sampTextdrawIsExists(i) then
            local x, y = sampTextdrawGetPos(i)
            local dist = getDistanceBetweenCoords2d(x, y, posX, posY)
            if dist <= 0.3 then
                local model = select(1, sampTextdrawGetModelRotationZoomVehColor(i))
                local _, outlineColor = sampTextdrawGetOutlineColor(i)
                if model == emptySlotId or outlineColor ~= darkSlotColor then
                    return true
                end
                for k, item in ipairs(itemsToTrade) do
                    if model == item.id and sampTextdrawIsExists(i + 1) then
                        local itemAmount = tonumber(sampTextdrawGetString(i + 1):match("^(%d+)/?"))
                        local amountToTrade = 0
                        if itemAmount <= item.limit then
                            printMessage('Достигнут лимит для {00FF66}' .. item.name)
                            table.remove(itemsToTrade, k)
                            return false
                        elseif itemAmount - item.amount < item.limit then
                            amountToTrade = itemAmount - item.limit
                        else
                            amountToTrade = item.amount
                        end
                        ammoValue = amountToTrade
                        tradeItemToRemove = k
                        clickTextdraw(i)
                        return true
                    end
                end
            end
        end
    end
end

function autoTrade()
    if #itemsToTrade > 0 then
        if os.clock() * 1000 - antiflood < cfg.settings.delay then return end
        for _, pos in ipairs(slots_inventory) do
            if tradeInventoryItem(pos[1], pos[2]) then
                return
            end
        end
        if #itemsToTrade > 0 then
            local missing_items = ''
            for _, item in ipairs(itemsToTrade) do
                missing_items = missing_items .. item.name .. ' | '
            end
            printMessage('Отсутствующие предметы: {00FF66}' .. missing_items:sub(0, -4))
        end
        itemsToTrade = {}
        isTradeInProgress = false
        isSubmitInProgress = true
    else
        isTradeInProgress = false
        isSubmitInProgress = true
    end
end

function sendSubmit()
    if os.clock() * 1000 - antiflood < cfg.settings.delay then return end
    if cfg.settings.auto_press_accept and acceptTextDrawId and sampTextdrawIsExists(acceptTextDrawId) then
        clickTextdraw(acceptTextDrawId)
    else
        setInitialValues()
    end
end

function clickTextdraw(textdrawId)
    sampSendClickTextdraw(textdrawId)
    antiflood = os.clock() * 1000
end

function setInitialValues()
    itemsToTrade = {}
    isTradeInProgress = false
    isSubmitInProgress = false
    ammoValue = nil
    tradeItemToRemove = nil
end

function onWindowMessage(m, p)
    if p == keys.VK_ESCAPE and window[0] then
        consumeWindowMessage()
        window[0] = false
    end
end

local function showTooltip(text)
    if imgui.IsItemHovered() then
        imgui.BeginTooltip()
        imgui.PushTextWrapPos(300)
        imgui.TextUnformatted(text)
        imgui.PopTextWrapPos()
        imgui.EndTooltip()
    end
end

imgui.OnInitialize(function()
    imgui.GetIO().IniFilename = nil

    local style = imgui.GetStyle()
    local colors = style.Colors
    local clr = imgui.Col
    local accent = imgui.ImVec4(0.00, 1.00, 0.40, 1.00)
    local accentHover = imgui.ImVec4(0.00, 0.82, 0.33, 1.00)
    local accentActive = imgui.ImVec4(0.00, 0.65, 0.26, 1.00)

    style.WindowRounding = 6.0
    style.FrameRounding = 4.0
    style.ChildRounding = 4.0
    style.PopupRounding = 4.0
    style.ScrollbarRounding = 4.0
    style.WindowBorderSize = 0.0
    style.ChildBorderSize = 0.0
    style.PopupBorderSize = 0.0
    style.FrameBorderSize = 0.0

    colors[clr.WindowBg] = imgui.ImVec4(0.06, 0.07, 0.08, 0.98)
    colors[clr.ChildBg] = imgui.ImVec4(0.08, 0.09, 0.10, 1.00)
    colors[clr.Border] = imgui.ImVec4(0.00, 0.00, 0.00, 0.00)
    colors[clr.TitleBg] = imgui.ImVec4(0.04, 0.05, 0.06, 1.00)
    colors[clr.TitleBgActive] = imgui.ImVec4(0.07, 0.10, 0.08, 1.00)
    colors[clr.FrameBg] = imgui.ImVec4(0.12, 0.14, 0.14, 1.00)
    colors[clr.FrameBgHovered] = imgui.ImVec4(0.15, 0.20, 0.17, 1.00)
    colors[clr.FrameBgActive] = imgui.ImVec4(0.17, 0.24, 0.19, 1.00)
    colors[clr.CheckMark] = accent
    colors[clr.SliderGrab] = accent
    colors[clr.SliderGrabActive] = accentHover
    colors[clr.Button] = imgui.ImVec4(0.00, 0.34, 0.14, 1.00)
    colors[clr.ButtonHovered] = accentHover
    colors[clr.ButtonActive] = accentActive
    colors[clr.Header] = imgui.ImVec4(0.00, 0.30, 0.13, 0.65)
    colors[clr.HeaderHovered] = accentHover
    colors[clr.HeaderActive] = accentActive
    colors[clr.Separator] = imgui.ImVec4(0.18, 0.22, 0.19, 1.00)
    colors[clr.SeparatorHovered] = accentHover
    colors[clr.SeparatorActive] = accentActive
end)

imgui.OnFrame(
    function() return window[0] end,
    function()
        local sw, sh = getScreenResolution()
        local window_width = 420
        local window_height = 380

        imgui.SetNextWindowPos(imgui.ImVec2(sw / 2, sh / 2), imgui.Cond.FirstUseEver, imgui.ImVec2(0.5, 0.5))
        imgui.SetNextWindowSize(imgui.ImVec2(window_width, window_height), imgui.Cond.FirstUseEver)

        imgui.Begin("Auto Trade", window, imgui.WindowFlags.NoResize + imgui.WindowFlags.NoCollapse)

        if imgui.Checkbox("Включить", ui.settings.isActivated) then cfg.settings.isActivated = ui.settings.isActivated[0] saveCFG(cfg, CONFIG_PATH) end
        showTooltip("Главный переключатель: при открытии окна обмена скрипт сам выбирает отмеченные предметы в инвентаре и вводит их количество. Если выключен, выбор предметов не выполняется — работают только остальные опции.")
        imgui.SameLine(0, 20)
        if imgui.Checkbox("Принимать запросы", ui.settings.acceptTradeRequest) then cfg.settings.accept_trade_request = ui.settings.acceptTradeRequest[0] saveCFG(cfg, CONFIG_PATH) end
        showTooltip("Автоматически принимает входящие запросы на обмен: на сообщение «предложил вам обмен предметами» скрипт отправляет /accept invtrade вместо ручного нажатия Y.")
        imgui.SameLine(0, 20)
        if imgui.Checkbox("Нажимать accept", ui.settings.autoPressAccept) then cfg.settings.auto_press_accept = ui.settings.autoPressAccept[0] saveCFG(cfg, CONFIG_PATH) end
        showTooltip("Скрипт сам нажимает кнопку accept в окне обмена, когда вторая сторона согласилась, и доводит сделку до конца. Если выключено, подтверждение нужно нажимать вручную.")
        imgui.NewLine()
        imgui.PushItemWidth(100)
        if imgui.InputInt("Задержка (мс)", ui.settings.delay, 50) then
            ui.settings.delay[0] = math.max(200, math.min(2000, ui.settings.delay[0]))
            cfg.settings.delay = ui.settings.delay[0]
            saveCFG(cfg, CONFIG_PATH)
        end
        imgui.PopItemWidth()
        imgui.NewLine()

        imgui.BeginChild("tradeItems", imgui.ImVec2(-1, -1), true)
        imgui.Columns(4, "tradeItemsColumns", false)
        imgui.Text("Название"); imgui.SetColumnWidth(-1, 100)
        imgui.NextColumn()
        imgui.Text("Вкл."); imgui.SetColumnWidth(-1, 45)
        imgui.NextColumn()
        imgui.Text("Значение"); imgui.SetColumnWidth(-1, 130)
        imgui.NextColumn()
        imgui.Text("Остаток"); imgui.SetColumnWidth(-1, 130)
        imgui.NextColumn()

        for _, item in ipairs(cfg.items) do
            local state = ui.items[item.name]
            imgui.Separator()
            imgui.TextUnformatted(state.label)
            imgui.NextColumn()

            if imgui.Checkbox("##item_enabled_" .. item.name, state.isSelected) then
                item.isSelected = state.isSelected[0]
                saveCFG(cfg, CONFIG_PATH)
            end
            imgui.NextColumn()

            imgui.PushItemWidth(-1)
            if imgui.InputInt("##item_amount_" .. item.name, state.amount, item.step) then
                local amount = math.max(item.min, math.min(item.max, state.amount[0]))
                state.amount[0] = amount
                item.amount = amount
                saveCFG(cfg, CONFIG_PATH)
            end
            imgui.PopItemWidth()
            imgui.NextColumn()

            imgui.PushItemWidth(-1)
            if imgui.InputInt("##item_limit_" .. item.name, state.limit, 1) then
                local limit = math.max(0, math.min(item.max, state.limit[0]))
                state.limit[0] = limit
                item.limit = limit
                saveCFG(cfg, CONFIG_PATH)
            end
            imgui.PopItemWidth()
            imgui.NextColumn()
        end
        imgui.Columns(1)
        imgui.EndChild()

        imgui.End()
    end
)

function ev.onServerMessage(c, text)
    text = u8(text)
    if (isTradeInProgress and text:find("^ У игрока слишком маленький уровень для обмена оружием")) or (isSubmitInProgress and text:find("^ Обмен не может быть пустым")) then
        setInitialValues()
    end
    if cfg.settings.accept_trade_request and text:find("^ .+ предложил вам обмен предметами {FFFFFF}%(%( Нажмите Y/N для принятия/отмены %)%)") then
        sampSendChat("/accept invtrade")
    end
    if cfg.settings.auto_press_accept and text:find("^ .+ согласился на обмен, нажмите accept для принятия") then
        isSubmitInProgress = true
    end
end

function ev.onShowTextDraw(id, data)
    if data.text:find("accept") then
        acceptTextDrawId = id
        if cfg.settings.isActivated then
            for _, item in ipairs(cfg.items) do
                if item.isSelected then
                    table.insert(itemsToTrade, { id = item.id, name = item.name, amount = item.amount, limit = item.limit })
                end
            end
            isTradeInProgress = true
        end
    end
end

function ev.onShowDialog(id, style, title, button1, button2, text)
    title = u8(title)
    text = u8(text)
    if ammoValue ~= nil and style == 1 and text:find("Введите количество:") then
        table.remove(itemsToTrade, tradeItemToRemove)
        sampSendDialogResponse(id, 1, 1, ammoValue)
        ammoValue = nil
        return false
    end
    if isSubmitInProgress and style == 0 and title:find("Обмен") then
        sampSendDialogResponse(id, 1, 1, -1)
        setInitialValues()
        return false
    end
end
