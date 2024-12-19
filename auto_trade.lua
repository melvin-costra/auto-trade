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
local ammoValue = nil
local itemsToTrade = {}
local tradeItemToRemove = nil
local inventoryTextDrawId = nil
local acceptTextDrawId = nil

local cfg = {
	items = {
		{ id = 1575, name = "drugs", amount = 50, limit = 50, isSelected = false },
		{ id = 348, name = "deagle", amount = 50, limit = 50, isSelected = false },
		{ id = 349, name = "shotgun", amount = 40, limit = 35, isSelected = false },
		{ id = 355, name = "ak47", amount = 200, limit = 200, isSelected = false },
		{ id = 356, name = "m4", amount = 200, limit = 200, isSelected = false },
		{ id = 357, name = "rifle", amount = 50, limit = 50, isSelected = false }
	},
	settings = {
		isActivated = false,
		auto_accept = false,
		auto_submit = false
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

local inventory_items = {
	{ id = 1575, key = "drugs" },
	{ id = 348, key = "deagle" },
	{ id = 349, key = "shotgun" },
	{ id = 355, key = "ak47" },
	{ id = 356, key = "m4" },
	{ id = 357, key = "rifle" }
}

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
		io.open(CONFIG_PATH, 'w'):close()
	else
		local file = io.open(CONFIG_PATH, 'r')
		if file then
			cfg = decodeJson(file:read('*a'))
		end
	end
	saveCFG(cfg, CONFIG_PATH)

	apply_custom_style()
	sampRegisterChatCommand("atrade", function()
		window.v = not window.v
	end)

	while true do
		wait(0)
		imgui.Process = window.v
		if isTradeInProgress then
			autoTrade()
		elseif isSubmitInProgress then
			sendSubmit()
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

function autoTrade()
	if #itemsToTrade > 0 then
		for i, slot in ipairs(slots_inventory) do
			local x, y = slot[1], slot[2]
			if tradeInventoryItem(x, y) then
				return
			end
		end
		itemsToTrade = {}
	else
		isTradeInProgress = false
		isSubmitInProgress = true
	end
end

function sendSubmit()
	if sampTextdrawIsExists(acceptTextDrawId) then
		sampSendClickTextdraw(acceptTextDrawId)
	else
		acceptTextDrawId = nil
	end
end

function imgui.OnDrawFrame()
   local sw, sh = getScreenResolution()
   local window_width = 440
   local window_height = 400
   local slider_pos_x = window_width / 4
   
   checkbox_isActivated =  imgui.ImBool(cfg.settings.isActivated)
   checkbox_auto_accept =  imgui.ImBool(cfg.settings.auto_accept)
   checkbox_auto_submit =  imgui.ImBool(cfg.settings.auto_submit)

   checkbox_drugs =        imgui.ImBool(cfg.items[1].isSelected)
   checkbox_deagle =       imgui.ImBool(cfg.items[2].isSelected)
   checkbox_shotgun =      imgui.ImBool(cfg.items[3].isSelected)
   checkbox_ak47 =         imgui.ImBool(cfg.items[4].isSelected)
   checkbox_m4 =           imgui.ImBool(cfg.items[5].isSelected)
   checkbox_rifle =        imgui.ImBool(cfg.items[6].isSelected)

   drugs_amount =          imgui.ImInt(cfg.items[1].amount)
   deagle_amount =         imgui.ImInt(cfg.items[2].amount)
   shotgun_amount =        imgui.ImInt(cfg.items[3].amount)
   ak47_amount =           imgui.ImInt(cfg.items[4].amount)
   m4_amount =             imgui.ImInt(cfg.items[5].amount)
   rifle_amount =          imgui.ImInt(cfg.items[6].amount)
   
   drugs_limit =           imgui.ImInt(cfg.items[1].limit)
   deagle_limit =          imgui.ImInt(cfg.items[2].limit)
   shotgun_limit =         imgui.ImInt(cfg.items[3].limit)
   ak47_limit =            imgui.ImInt(cfg.items[4].limit)
   m4_limit =              imgui.ImInt(cfg.items[5].limit)
   rifle_limit =           imgui.ImInt(cfg.items[6].limit)


   imgui.SetNextWindowPos(imgui.ImVec2(sw / 2, sh / 2), imgui.Cond.FirstUseEver, imgui.ImVec2(0.5, 0.5))
   imgui.SetNextWindowSize(imgui.ImVec2(window_width, window_height), imgui.Cond.FirstUseEver)

   imgui.Begin("Auto Trade", window, imgui.WindowFlags.NoResize + imgui.WindowFlags.NoCollapse)
   
   if imgui.Checkbox("Turn on", checkbox_isActivated) then cfg.settings.isActivated = checkbox_isActivated.v saveCFG(cfg, CONFIG_PATH) end
   imgui.SameLine(slider_pos_x)
   if imgui.Checkbox("Auto trade accept", checkbox_auto_accept) then cfg.settings.auto_accept = checkbox_auto_accept.v saveCFG(cfg, CONFIG_PATH) end
   imgui.SameLine(slider_pos_x + 160)
   if imgui.Checkbox("Auto trade submit", checkbox_auto_submit) then cfg.settings.auto_submit = checkbox_auto_submit.v saveCFG(cfg, CONFIG_PATH) end
   imgui.NewLine()

   imgui.Separator()
   imgui.SetCursorPosX(50)
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
   
   if imgui.Checkbox("AK47", checkbox_ak47) then cfg.items[4].isSelected = checkbox_ak47.v saveCFG(cfg, CONFIG_PATH) end
   imgui.SameLine(slider_pos_x)
   if imgui.SliderInt(u8"pt.   ", ak47_amount, 50, 400) then cfg.items[4].amount = ak47_amount.v saveCFG(cfg, CONFIG_PATH) end
   imgui.NewLine()

   if imgui.Checkbox("M4", checkbox_m4) then cfg.items[5].isSelected = checkbox_m4.v saveCFG(cfg, CONFIG_PATH) end
   imgui.SameLine(slider_pos_x)
   if imgui.SliderInt(u8"pt.  ", m4_amount, 50, 400) then cfg.items[5].amount = m4_amount.v saveCFG(cfg, CONFIG_PATH) end
   imgui.NewLine()

   if imgui.Checkbox("Rifle", checkbox_rifle) then cfg.items[6].isSelected = checkbox_rifle.v saveCFG(cfg, CONFIG_PATH) end
   imgui.SameLine(slider_pos_x)
   if imgui.SliderInt(u8"pt.    ", rifle_amount, 10, 100) then cfg.items[6].amount = rifle_amount.v saveCFG(cfg, CONFIG_PATH) end
   imgui.NewLine()

   imgui.Separator()
   imgui.SetCursorPosX(50)
   imgui.Text("Limits")
   imgui.NewLine()
   
   imgui.Text("Drugs")
   imgui.SameLine(slider_pos_x)
   if imgui.SliderInt(u8"g. ", drugs_limit, 0, 100) then cfg.items[1].limit = drugs_limit.v saveCFG(cfg, CONFIG_PATH) end
   imgui.NewLine()
   
   imgui.Text("Deagle")
   imgui.SameLine(slider_pos_x)
   if imgui.SliderInt(u8"pt.     ", deagle_limit, 0, 100) then cfg.items[2].limit = deagle_limit.v saveCFG(cfg, CONFIG_PATH) end
   imgui.NewLine()
   
   imgui.Text("Shotgun")
   imgui.SameLine(slider_pos_x)
   if imgui.SliderInt(u8"pt.      ", shotgun_limit, 0, 100) then cfg.items[3].limit = shotgun_limit.v saveCFG(cfg, CONFIG_PATH) end
   imgui.NewLine()
   
   imgui.Text("AK47")
   imgui.SameLine(slider_pos_x)
   if imgui.SliderInt(u8"pt.       ", ak47_limit, 0, 500) then cfg.items[4].limit = ak47_limit.v saveCFG(cfg, CONFIG_PATH) end
   imgui.NewLine()
   
   imgui.Text("M4")
   imgui.SameLine(slider_pos_x)
   if imgui.SliderInt(u8"pt.        ", m4_limit, 0, 500) then cfg.items[5].limit = m4_limit.v saveCFG(cfg, CONFIG_PATH) end
   imgui.NewLine()
   
   imgui.Text("Rifle")
   imgui.SameLine(slider_pos_x)
   if imgui.SliderInt(u8"pt.         ", rifle_limit, 0, 100) then cfg.items[6].limit = rifle_limit.v saveCFG(cfg, CONFIG_PATH) end
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
	if cfg.settings.auto_accept and text:find("(.+) предложил вам обмен предметами .+") ~= nil then
	    sampSendChat("/accept invtrade")
	end
end

function ev.onShowTextDraw(id, data)
	if cfg.settings.isActivated and data.text:find("inventory") then
		inventoryTextDrawId = id
	elseif cfg.settings.isActivated and data.text:find("accept") and inventoryTextDrawId then
		acceptTextDrawId = id
		for _, item in ipairs(cfg.items) do
			if item.isSelected then
				table.insert(itemsToTrade, { id = item.id, amount = item.amount, limit = item.limit })
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
