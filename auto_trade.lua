local migration = "02.11.2026"
script_author("Melvin Costra")
script_name("Auto trade")
script_description("Этот скрипт был создан для автоматизации процесса обмена предметами между игроками во время трейда (/itrade). Он позволяет мгновенно выполнять обмен предметами на основе параметров, заданных игроком, без необходимости ручного вмешательства.")
script_version("v1.1.0")
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

local function nowMs() return os.clock() * 1000 end

local MAX_TEXTDRAWS, POS_TOLERANCE, MAX_PAGE_SWITCHES = 2500, 0.3, 1
local window = imgui.new.bool(false)
local CONFIG_PATH = "moonloader/config/auto-trade.json"
local state = "idle" -- "idle" | "trading" | "submitting"
local pendingTrade = nil
local itemsToTrade = {}
local acceptTextDrawId = nil
local nextPageTextDrawId = nil
local emptySlotId = 19478
local darkSlotColor = 4280098087
local antiflood = nowMs()
local isPageSwitchInProgress = false
local pagesSwitched = 0
local pageSwitchStartedAt = 0
local pageRenderTimeout = 1500
local pickingCancelKey = false

local cfg = {
    migration = migration,
    items = {
        { id = 1575, name = "drugs", label = "Drugs", amount = 50, limit = 50, min = 1, max = 300, step = 25, isSelected = false },
        { id = 347, name = "sdpistol", label = "SDPistol", amount = 100, limit = 100, min = 1, max = 10000, step = 25, isSelected = true },
        { id = 348, name = "deagle", label = "Deagle", amount = 100, limit = 100, min = 1, max = 10000, step = 25, isSelected = true },
        { id = 349, name = "shotgun", label = "Shotgun", amount = 50, limit = 50, min = 1, max = 10000, step = 25, isSelected = true },
        { id = 353, name = "smg", label = "SMG", amount = 200, limit = 200, min = 1, max = 10000, step = 50, isSelected = true },
        { id = 355, name = "ak47", label = "AK47", amount = 200, limit = 200, min = 1, max = 10000, step = 50, isSelected = true },
        { id = 356, name = "m4", label = "M4", amount = 200, limit = 200, min = 1, max = 10000, step = 50, isSelected = true },
        { id = 357, name = "rifle", label = "Rifle", amount = 50, limit = 50, min = 1, max = 10000, step = 25, isSelected = true }
    },
    settings = {
        isActivated = false,
        accept_trade_request = false,
        auto_press_accept = false,
        delay = 300,
        cancel_key = 78 -- N
    }
}

local ui = {
    settings = {
        isActivated = imgui.new.bool(cfg.settings.isActivated),
        acceptTradeRequest = imgui.new.bool(cfg.settings.accept_trade_request),
        autoPressAccept = imgui.new.bool(cfg.settings.auto_press_accept),
        delay = imgui.new.int(cfg.settings.delay)
    },
    items = {}
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

local amountOffsetX = 17.5
local amountOffsetY = 31

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
            if fileCFG and fileCFG.migration == cfg.migration then
                cfg = fileCFG
            else
                saveCFG(cfg, CONFIG_PATH)
            end
        end
    end

    ui.settings.isActivated[0] = cfg.settings.isActivated
    ui.settings.acceptTradeRequest[0] = cfg.settings.accept_trade_request
    ui.settings.autoPressAccept[0] = cfg.settings.auto_press_accept
    ui.settings.delay[0] = cfg.settings.delay

    ui.items = {}
    for _, item in ipairs(cfg.items) do
        ui.items[item.name] = {
            isSelected = imgui.new.bool(item.isSelected),
            amount = imgui.new.int(item.amount),
            limit = imgui.new.int(item.limit)
        }
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
        if not window[0] then pickingCancelKey = false end
        if pickingCancelKey then
            if isKeyJustPressed(keys.VK_ESCAPE) or isKeyJustPressed(keys.VK_RETURN) then
                pickingCancelKey = false
            else
                for _, key in pairs(keys) do
                    if type(key) == "number" and isKeyJustPressed(key) then
                        cfg.settings.cancel_key = key
                        pickingCancelKey = false
                        saveCFG(cfg, CONFIG_PATH)
                        break
                    end
                end
            end
        elseif state ~= "idle" and isKeyJustPressed(cfg.settings.cancel_key) and not sampIsChatInputActive() and not sampIsDialogActive() then
            resetState()
        end
        if acceptTextDrawId and not sampTextdrawIsExists(acceptTextDrawId) then
            acceptTextDrawId = nil
        end
        if state ~= "idle" and not acceptTextDrawId then
            resetState()
        end
        if state == "trading" then
            autoTrade()
        elseif state == "submitting" then
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

function isQuantityTextDrawAtPos(textDrawId, posX, posY)
    if not sampTextdrawIsExists(textDrawId) then
        return false
    end

    local x, y = sampTextdrawGetPos(textDrawId)
    if getDistanceBetweenCoords2d(x, y, posX, posY) > POS_TOLERANCE then
        return false
    end

    return sampTextdrawGetString(textDrawId):match("^(%d+)/?") ~= nil
end

function findTextDrawAtPos(posX, posY)
    for i = 0, MAX_TEXTDRAWS do
        if isQuantityTextDrawAtPos(i, posX, posY) then
            return i
        end
    end
end

function removeItemToTrade(item)
    for k, v in ipairs(itemsToTrade) do
        if v == item then
            table.remove(itemsToTrade, k)
            return
        end
    end
end

-- Проверяет слот по координатам и пытается кликнуть по подходящему предмету.
-- Возвращает:
--   "clicked" - кликнули по предмету, нужно ждать диалога с количеством
--   "empty"   - слот пустой (или выделен), дальше предметов на странице нет
--   "skip"    - в слоте нет нужного предмета, идём к следующему слоту
function tradeInventoryItem(posX, posY)
    for i = 0, MAX_TEXTDRAWS do
        if sampTextdrawIsExists(i) then
            local x, y = sampTextdrawGetPos(i)
            local dist = getDistanceBetweenCoords2d(x, y, posX, posY)
            if dist <= POS_TOLERANCE then
                local model = select(1, sampTextdrawGetModelRotationZoomVehColor(i))
                local _, outlineColor = sampTextdrawGetOutlineColor(i)
                if model == emptySlotId or outlineColor ~= darkSlotColor then
                    return "empty"
                end
                for k, item in ipairs(itemsToTrade) do
                    if model == item.id then
                        local amountPosX = posX + amountOffsetX
                        local amountPosY = posY + amountOffsetY
                        local amountTextDrawId = i + 1
                        if not isQuantityTextDrawAtPos(amountTextDrawId, amountPosX, amountPosY) then
                            amountTextDrawId = findTextDrawAtPos(amountPosX, amountPosY)
                        end
                        local itemAmount = amountTextDrawId and tonumber(sampTextdrawGetString(amountTextDrawId):match("^(%d+)/?"))
                        if itemAmount then
                            local amountToTrade = 0
                            if itemAmount <= item.limit then
                                printMessage('Достигнут лимит для {00FF66}' .. item.name)
                                table.remove(itemsToTrade, k)
                                return "skip"
                            elseif itemAmount - item.amount < item.limit then
                                amountToTrade = itemAmount - item.limit
                            else
                                amountToTrade = item.amount
                            end
                            pendingTrade = { item = item, amount = amountToTrade }
                            clickTextdraw(i)
                            return "clicked"
                        end
                    end
                end
            end
        end
    end
    return "skip"
end

function autoTrade()
    if isPageSwitchInProgress then
        if nowMs() - pageSwitchStartedAt >= pageRenderTimeout then
            finishPageRender()
        end
        return
    end

    if #itemsToTrade > 0 then
        if nowMs() - antiflood < cfg.settings.delay then return end
        local isEmptySlot = false
        for _, pos in ipairs(slots_inventory) do
            local result = tradeInventoryItem(pos[1], pos[2])
            if result == "clicked" then
                return
            end
            if result == "empty" then
                isEmptySlot = true
                break
            end
        end
        if #itemsToTrade > 0 and not isEmptySlot and pagesSwitched < MAX_PAGE_SWITCHES
            and nextPageTextDrawId and sampTextdrawIsExists(nextPageTextDrawId) then
            switchToNextPage()
            return
        end
        if #itemsToTrade > 0 then
            local missingItems = {}
            for _, item in ipairs(itemsToTrade) do
                missingItems[#missingItems + 1] = item.name
            end
            printMessage('Отсутствующие предметы: {00FF66}' .. table.concat(missingItems, ' | '))
        end
    end

    itemsToTrade = {}
    state = "submitting"
end

function switchToNextPage()
    isPageSwitchInProgress = true
    pageSwitchStartedAt = nowMs()
    clickTextdraw(nextPageTextDrawId)
end

function finishPageRender()
    isPageSwitchInProgress = false
    pagesSwitched = pagesSwitched + 1
end

function getInventorySlotIndex(posX, posY)
    for index, pos in ipairs(slots_inventory) do
        if getDistanceBetweenCoords2d(posX, posY, pos[1], pos[2]) <= POS_TOLERANCE then
            return index
        end
    end
end

function sendSubmit()
    if nowMs() - antiflood < cfg.settings.delay then return end
    if cfg.settings.auto_press_accept and acceptTextDrawId and sampTextdrawIsExists(acceptTextDrawId) then
        clickTextdraw(acceptTextDrawId)
    else
        resetState()
    end
end

function clickTextdraw(textdrawId)
    sampSendClickTextdraw(textdrawId)
    antiflood = nowMs()
end

function resetState()
    itemsToTrade = {}
    state = "idle"
    pendingTrade = nil
    isPageSwitchInProgress = false
    pagesSwitched = 0
    pageSwitchStartedAt = 0
    nextPageTextDrawId = nil
end

function onWindowMessage(m, p)
    if p == keys.VK_ESCAPE and window[0] then
        consumeWindowMessage()
        window[0] = false
    end
end

function showTooltip(text)
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
        showTooltip("Автоматически выбирает отмеченные предметы и вводит их количество в окне обмена.")
        imgui.SameLine(0, 20)
        if imgui.Checkbox("Принимать запросы", ui.settings.acceptTradeRequest) then cfg.settings.accept_trade_request = ui.settings.acceptTradeRequest[0] saveCFG(cfg, CONFIG_PATH) end
        showTooltip("Принимает входящие запросы на обмен командой /accept invtrade.")
        imgui.SameLine(0, 20)
        if imgui.Checkbox("Нажимать accept", ui.settings.autoPressAccept) then cfg.settings.auto_press_accept = ui.settings.autoPressAccept[0] saveCFG(cfg, CONFIG_PATH) end
        showTooltip("Нажимает accept после согласия второй стороны.")
        imgui.NewLine()
        imgui.PushItemWidth(100)
        if imgui.InputInt("Задержка (мс)", ui.settings.delay, 50) then
            ui.settings.delay[0] = math.max(200, math.min(2000, ui.settings.delay[0]))
            cfg.settings.delay = ui.settings.delay[0]
            saveCFG(cfg, CONFIG_PATH)
        end
        imgui.PopItemWidth()
        local cancelKeyName = keys.id_to_name(cfg.settings.cancel_key) or tostring(cfg.settings.cancel_key)
        local cancelKeyButtonLabel = pickingCancelKey and "Нажми клавишу..." or ("Клавиша отмены: " .. cancelKeyName)
        imgui.SameLine()
        imgui.SetCursorPosX(window_width - imgui.CalcTextSize(cancelKeyButtonLabel).x - 32)
        if imgui.Button(cancelKeyButtonLabel) then
            pickingCancelKey = not pickingCancelKey
        end
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
            local itemUi = ui.items[item.name]
            imgui.Separator()
            imgui.TextUnformatted(item.label)
            imgui.NextColumn()

            if imgui.Checkbox("##item_enabled_" .. item.name, itemUi.isSelected) then
                item.isSelected = itemUi.isSelected[0]
                saveCFG(cfg, CONFIG_PATH)
            end
            imgui.NextColumn()

            imgui.PushItemWidth(-1)
            if imgui.InputInt("##item_amount_" .. item.name, itemUi.amount, item.step) then
                local amount = math.max(item.min, math.min(item.max, itemUi.amount[0]))
                itemUi.amount[0] = amount
                item.amount = amount
                saveCFG(cfg, CONFIG_PATH)
            end
            imgui.PopItemWidth()
            imgui.NextColumn()

            imgui.PushItemWidth(-1)
            if imgui.InputInt("##item_limit_" .. item.name, itemUi.limit, item.step) then
                local limit = math.max(0, math.min(item.max, itemUi.limit[0]))
                itemUi.limit[0] = limit
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
    if (state == "trading" and text:find("^ У игрока слишком маленький уровень для обмена оружием")) or (state == "submitting" and text:find("^ Обмен не может быть пустым")) then
        resetState()
    end
    if cfg.settings.accept_trade_request and text:find("^ .+ предложил вам обмен предметами {FFFFFF}%(%( Нажмите Y/N для принятия/отмены %)%)") then
        sampSendChat("/accept invtrade")
    end
    if cfg.settings.auto_press_accept and text:find("^ .+ согласился на обмен, нажмите accept для принятия") then
        state = "submitting"
    end
end

function ev.onShowTextDraw(id, data)
    if isPageSwitchInProgress and getInventorySlotIndex(data.position.x, data.position.y) == #slots_inventory then
        finishPageRender()
    end
    if data.text:find(">>>") and data.position.x == 370.5 and data.position.y == 334.375 then
        nextPageTextDrawId = id
    end
    if data.text:find("accept") and data.position.x == 223 and data.position.y == 315.5 then
        acceptTextDrawId = id
        if cfg.settings.isActivated then
            itemsToTrade = {}
            for _, item in ipairs(cfg.items) do
                if item.isSelected then
                    table.insert(itemsToTrade, { id = item.id, name = item.name, amount = item.amount, limit = item.limit })
                end
            end
            antiflood = nowMs()
            state = "trading"
        end
    end
end

function ev.onShowDialog(id, style, title, button1, button2, text)
    title = u8(title)
    text = u8(text)
    if pendingTrade and style == 1 and text:find("Введите количество:") then
        removeItemToTrade(pendingTrade.item)
        sampSendDialogResponse(id, 1, 1, pendingTrade.amount)
        pendingTrade = nil
        return false
    end
    if state == "submitting" and style == 0 and title:find("Обмен") then
        sampSendDialogResponse(id, 1, 1, -1)
        resetState()
        return false
    end
end