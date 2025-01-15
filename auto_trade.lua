script_author("Melvin Costra")
script_name("Auto trade")
script_description("Этот скрипт был создан для автоматизации процесса обмена предметами между игроками во время трейда (/itrade). Он позволяет мгновенно выполнять обмен предметами на основе параметров, заданных игроком, без необходимости ручного вмешательства.")
script_version("v0.2.0")
script_url("https://github.com/melvin-costra/auto-trade.git")

local ev          = require "samp.events"
local imgui       = require 'imgui'
local encoding    = require 'encoding'
encoding.default  = 'CP1251'
u8                = encoding.UTF8
require "lib.moonloader"

local window = imgui.ImBool(false)
local CONFIG_PATH = "moonloader/config/configAutoTrade.json"
local isTradeInProgress = false
local isSubmitInProgress = false
local isNextPageInProgress = false
local ammoValue = nil
local itemsToTrade = {}
local tradeItemToRemove = nil
local inventoryTextDrawId = nil
local acceptTextDrawId = nil
local nextPageTextDrawId = nil
local emptySlotId = 19478
local darkSlotColor = 4280098087
local lastInventoryItem = nil

local cfg = {
    items = {
        { id = 1575, name = "drugs", amount = 50, limit = 50, isSelected = false },
        { id = 348, name = "deagle", amount = 50, limit = 50, isSelected = false },
        { id = 349, name = "shotgun", amount = 40, limit = 35, isSelected = false },
        { id = 353, name = "smg", amount = 150, limit = 150, isSelected = false },
        { id = 355, name = "ak47", amount = 200, limit = 200, isSelected = false },
        { id = 356, name = "m4", amount = 200, limit = 200, isSelected = false },
        { id = 357, name = "rifle", amount = 50, limit = 50, isSelected = false }
    },
    settings = {
        isActivated = false,
        accept_trade_request = false,
        auto_press_accept = false,
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

function checkSavedCFG(savedCFG)
    if savedCFG.items == nil or savedCFG.settings == nil or #savedCFG.items ~= #cfg.items then
        return false
    end
    local count1, count2 = 0, 0
    for key in pairs(cfg.settings) do
        if savedCFG.settings[key] == nil then
            return false
        end
        count1 = count1 + 1
    end

    for key in pairs(savedCFG.settings) do
        count2 = count2 + 1
    end

    return count1 == count2
end

function saveCFG(table, path)
    local save = io.open(path, "w")
    if save then
        save:write(encodeJson(table))
        save:close()
    end
end

function main()
    if not isSampLoaded() or not isSampfuncsLoaded() then return end
    while not isSampAvailable() do wait(100) end

    if not doesDirectoryExist('moonloader/config') then createDirectory("moonloader/config") end

    if not doesFileExist(CONFIG_PATH) then
        saveCFG(cfg, CONFIG_PATH)
    else
        local file = io.open(CONFIG_PATH, 'r')
        if file then
            local fileCFG = decodeJson(file:read('*a'))
            if checkSavedCFG(fileCFG) then
                cfg = fileCFG
            end
        end
    end

    apply_custom_style()
    sampRegisterChatCommand("atrade", function()
        window.v = not window.v
    end)

    while true do
        wait(0)
        imgui.Process = window.v
        if isNextPageInProgress then
            switchToNextPage()
        elseif isTradeInProgress then
            autoTrade()
        elseif isSubmitInProgress then
            sendSubmit()
        end
        if isKeyDown(VK_RBUTTON) and isKeyJustPressed(VK_Q) then
            requestTrade()
        end
    end
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
    for i = 2000, 2500 do
        if sampTextdrawIsExists(i) then
            local x, y = sampTextdrawGetPos(i)
            local dist = getDistanceBetweenCoords2d(x, y, posX, posY)
            if dist <= 0.3 then
                local model = select(1, sampTextdrawGetModelRotationZoomVehColor(i))
                if lastInventoryItem == nil and posX == slots_inventory[#slots_inventory][1] and posY == slots_inventory[#slots_inventory][2] then
                    lastInventoryItem = { id = i, model = model}
                end
                local _, outlineColor = sampTextdrawGetOutlineColor(i)
                if model == emptySlotId or outlineColor ~= darkSlotColor then
                    local missing_items = ''
                    for _, item in ipairs(itemsToTrade) do
                        missing_items = missing_items .. item.name .. ' | '
                    end
                    if missing_items ~= '' then
                        sampAddChatMessage('[AutoTrade]: Отсутствующие предметы:  {638ECB}' .. missing_items:sub(0, -4), -1)
                    end
                    itemsToTrade = {}
                    return true
                end
                for k, item in ipairs(itemsToTrade) do
                    if model == item.id and sampTextdrawIsExists(i + 1) then
                        local itemAmount = tonumber(sampTextdrawGetString(i + 1):match("^(%d+)/?"))
                        local amountToTrade = 0
                        if itemAmount <= item.limit then
                            table.remove(itemsToTrade, k)
                            return false
                        elseif itemAmount - item.amount < item.limit then
                            amountToTrade = itemAmount - item.limit
                        else
                            amountToTrade = item.amount
                        end
                        ammoValue = amountToTrade
                        tradeItemToRemove = k
                        sampSendClickTextdraw(i)
                        return true
                    end
                end
            end
        end
    end
end

function switchToNextPage()
    if nextPageTextDrawId and sampTextdrawIsExists(nextPageTextDrawId) then
        sampSendClickTextdraw(nextPageTextDrawId)
        local model = select(1, sampTextdrawGetModelRotationZoomVehColor(lastInventoryItem.id))
        if not sampTextdrawIsExists(lastInventoryItem.id) or model ~= lastInventoryItem.model then
            isNextPageInProgress = false
            lastInventoryItem = nil
            return
        end
    else
        isNextPageInProgress = false
        itemsToTrade = {}
    end
end

function autoTrade()
    if #itemsToTrade > 0 then
        for i, slot in ipairs(slots_inventory) do
            local x, y = slot[1], slot[2]
            if tradeInventoryItem(x, y) then
                return
            end
        end
        if #itemsToTrade > 0 then
            isNextPageInProgress = true
        end
    else
        isTradeInProgress = false
        isSubmitInProgress = true
    end
end

function sendSubmit()
    if acceptTextDrawId and sampTextdrawIsExists(acceptTextDrawId) then
        sampSendClickTextdraw(acceptTextDrawId)
    else
        acceptTextDrawId = nil
        isSubmitInProgress = false
    end
end

function imgui.OnDrawFrame()
    local sw, sh = getScreenResolution()
    local window_width = 440
    local window_height = 400
    local slider_pos_x = window_width / 4

    checkbox_isActivated =           imgui.ImBool(cfg.settings.isActivated)
    checkbox_accept_trade_request =  imgui.ImBool(cfg.settings.accept_trade_request)
    checkbox_auto_press_accept =     imgui.ImBool(cfg.settings.auto_press_accept)

    checkbox_drugs =        imgui.ImBool(cfg.items[1].isSelected)
    checkbox_deagle =       imgui.ImBool(cfg.items[2].isSelected)
    checkbox_shotgun =      imgui.ImBool(cfg.items[3].isSelected)
    checkbox_smg =          imgui.ImBool(cfg.items[4].isSelected)
    checkbox_ak47 =         imgui.ImBool(cfg.items[5].isSelected)
    checkbox_m4 =           imgui.ImBool(cfg.items[6].isSelected)
    checkbox_rifle =        imgui.ImBool(cfg.items[7].isSelected)

    drugs_amount =          imgui.ImInt(cfg.items[1].amount)
    deagle_amount =         imgui.ImInt(cfg.items[2].amount)
    shotgun_amount =        imgui.ImInt(cfg.items[3].amount)
    smg_amount =            imgui.ImInt(cfg.items[4].amount)
    ak47_amount =           imgui.ImInt(cfg.items[5].amount)
    m4_amount =             imgui.ImInt(cfg.items[6].amount)
    rifle_amount =          imgui.ImInt(cfg.items[7].amount)

    drugs_limit =           imgui.ImInt(cfg.items[1].limit)
    deagle_limit =          imgui.ImInt(cfg.items[2].limit)
    shotgun_limit =         imgui.ImInt(cfg.items[3].limit)
    smg_limit =             imgui.ImInt(cfg.items[4].limit)
    ak47_limit =            imgui.ImInt(cfg.items[5].limit)
    m4_limit =              imgui.ImInt(cfg.items[6].limit)
    rifle_limit =           imgui.ImInt(cfg.items[7].limit)


    imgui.SetNextWindowPos(imgui.ImVec2(sw / 2, sh / 2), imgui.Cond.FirstUseEver, imgui.ImVec2(0.5, 0.5))
    imgui.SetNextWindowSize(imgui.ImVec2(window_width, window_height), imgui.Cond.FirstUseEver)

    imgui.Begin("Auto Trade", window, imgui.WindowFlags.NoResize + imgui.WindowFlags.NoCollapse)

    if imgui.Checkbox("Turn on", checkbox_isActivated) then cfg.settings.isActivated = checkbox_isActivated.v saveCFG(cfg, CONFIG_PATH) end
    imgui.SameLine(slider_pos_x)
    if imgui.Checkbox("Accept trade request", checkbox_accept_trade_request) then cfg.settings.accept_trade_request = checkbox_accept_trade_request.v saveCFG(cfg, CONFIG_PATH) end
    imgui.SameLine(slider_pos_x + 180)
    if imgui.Checkbox("Auto press accept", checkbox_auto_press_accept) then cfg.settings.auto_press_accept = checkbox_auto_press_accept.v saveCFG(cfg, CONFIG_PATH) end
    imgui.NewLine()

    imgui.Separator()
    imgui.SetCursorPosX(slider_pos_x)
    imgui.Text("Trade values")
    imgui.NewLine()

    if imgui.Checkbox("Drugs", checkbox_drugs) then cfg.items[1].isSelected = checkbox_drugs.v saveCFG(cfg, CONFIG_PATH) end
    imgui.SameLine(slider_pos_x)
    if imgui.SliderInt(u8"g.", drugs_amount, 10, 100) then cfg.items[1].amount = drugs_amount.v saveCFG(cfg, CONFIG_PATH) end
    imgui.NewLine()

    if imgui.Checkbox("Deagle", checkbox_deagle) then cfg.items[2].isSelected = checkbox_deagle.v saveCFG(cfg, CONFIG_PATH) end
    imgui.SameLine(slider_pos_x)
    if imgui.SliderInt(u8"pt.", deagle_amount, 20, 100) then cfg.items[2].amount = deagle_amount.v saveCFG(cfg, CONFIG_PATH) end
    imgui.NewLine()

    if imgui.Checkbox("Shotgun", checkbox_shotgun) then cfg.items[3].isSelected = checkbox_shotgun.v saveCFG(cfg, CONFIG_PATH) end
    imgui.SameLine(slider_pos_x)
    if imgui.SliderInt(u8"pt. ", shotgun_amount, 20, 100) then cfg.items[3].amount = shotgun_amount.v saveCFG(cfg, CONFIG_PATH) end
    imgui.NewLine()

    if imgui.Checkbox("SMG", checkbox_smg) then cfg.items[4].isSelected = checkbox_smg.v saveCFG(cfg, CONFIG_PATH) end
    imgui.SameLine(slider_pos_x)
    if imgui.SliderInt(u8"pt.  ", smg_amount, 30, 400) then cfg.items[4].amount = smg_amount.v saveCFG(cfg, CONFIG_PATH) end
    imgui.NewLine()

    if imgui.Checkbox("AK47", checkbox_ak47) then cfg.items[5].isSelected = checkbox_ak47.v saveCFG(cfg, CONFIG_PATH) end
    imgui.SameLine(slider_pos_x)
    if imgui.SliderInt(u8"pt.   ", ak47_amount, 50, 400) then cfg.items[5].amount = ak47_amount.v saveCFG(cfg, CONFIG_PATH) end
    imgui.NewLine()

    if imgui.Checkbox("M4", checkbox_m4) then cfg.items[6].isSelected = checkbox_m4.v saveCFG(cfg, CONFIG_PATH) end
    imgui.SameLine(slider_pos_x)
    if imgui.SliderInt(u8"pt.    ", m4_amount, 50, 400) then cfg.items[6].amount = m4_amount.v saveCFG(cfg, CONFIG_PATH) end
    imgui.NewLine()

    if imgui.Checkbox("Rifle", checkbox_rifle) then cfg.items[7].isSelected = checkbox_rifle.v saveCFG(cfg, CONFIG_PATH) end
    imgui.SameLine(slider_pos_x)
    if imgui.SliderInt(u8"pt.     ", rifle_amount, 10, 100) then cfg.items[7].amount = rifle_amount.v saveCFG(cfg, CONFIG_PATH) end
    imgui.NewLine()

    imgui.Separator()
    imgui.SetCursorPosX(slider_pos_x)
    imgui.Text("Limits")
    imgui.NewLine()

    imgui.Text("Drugs")
    imgui.SameLine(slider_pos_x)
    if imgui.SliderInt(u8"g. ", drugs_limit, 0, 100) then cfg.items[1].limit = drugs_limit.v saveCFG(cfg, CONFIG_PATH) end
    imgui.NewLine()

    imgui.Text("Deagle")
    imgui.SameLine(slider_pos_x)
    if imgui.SliderInt(u8"pt.      ", deagle_limit, 0, 100) then cfg.items[2].limit = deagle_limit.v saveCFG(cfg, CONFIG_PATH) end
    imgui.NewLine()

    imgui.Text("Shotgun")
    imgui.SameLine(slider_pos_x)
    if imgui.SliderInt(u8"pt.       ", shotgun_limit, 0, 100) then cfg.items[3].limit = shotgun_limit.v saveCFG(cfg, CONFIG_PATH) end
    imgui.NewLine()

    imgui.Text("SMG")
    imgui.SameLine(slider_pos_x)
    if imgui.SliderInt(u8"pt.        ", smg_limit, 0, 500) then cfg.items[4].limit = smg_limit.v saveCFG(cfg, CONFIG_PATH) end
    imgui.NewLine()

    imgui.Text("AK47")
    imgui.SameLine(slider_pos_x)
    if imgui.SliderInt(u8"pt.         ", ak47_limit, 0, 500) then cfg.items[5].limit = ak47_limit.v saveCFG(cfg, CONFIG_PATH) end
    imgui.NewLine()

    imgui.Text("M4")
    imgui.SameLine(slider_pos_x)
    if imgui.SliderInt(u8"pt.          ", m4_limit, 0, 500) then cfg.items[6].limit = m4_limit.v saveCFG(cfg, CONFIG_PATH) end
    imgui.NewLine()

    imgui.Text("Rifle")
    imgui.SameLine(slider_pos_x)
    if imgui.SliderInt(u8"pt.           ", rifle_limit, 0, 100) then cfg.items[7].limit = rifle_limit.v saveCFG(cfg, CONFIG_PATH) end
    imgui.NewLine()

    imgui.End()
end

function apply_custom_style()
    local style = imgui.GetStyle()

    style.WindowTitleAlign = imgui.ImVec2(0.5, 0.5)
end

function ev.onServerMessage(c, text)
    if isSubmitInProgress and text:find("Обмен не может быть пустым") then
        isSubmitInProgress = false
    end
    if cfg.settings.accept_trade_request and text:find("(.+) предложил вам обмен предметами .+") then
        sampSendChat("/accept invtrade")
    end
    if cfg.settings.auto_press_accept and text:find("(.+) согласился на обмен, нажмите accept для принятия") then
        isSubmitInProgress = true
    end
end

function ev.onShowTextDraw(id, data)
    if cfg.settings.isActivated and data.text:find("inventory") then
        inventoryTextDrawId = id
    end
    if cfg.settings.isActivated and data.text:find(">>>") then
        nextPageTextDrawId = id
    end
    if cfg.settings.isActivated and data.text:find("accept") and inventoryTextDrawId then
        if cfg.settings.auto_press_accept then
            acceptTextDrawId = id
        end
        for _, item in ipairs(cfg.items) do
            if item.isSelected then
                table.insert(itemsToTrade, { id = item.id, name = item.name, amount = item.amount, limit = item.limit })
            end
        end
        isTradeInProgress = true
    end
end

function ev.onShowDialog(id, style, title, button1, button2, text)
    if ammoValue ~= nil and style == 1 and text:find("Введите количество:") then
        table.remove(itemsToTrade, tradeItemToRemove)
        sampSendDialogResponse(id, 1, 1, ammoValue)
        ammoValue = nil
        return false
    end
    if isSubmitInProgress and style == 0 and title:find("Обмен") then
        sampSendDialogResponse(id, 1, 1, -1)
        isSubmitInProgress = false
        acceptTextDrawId = nil
        return false
    end
end
