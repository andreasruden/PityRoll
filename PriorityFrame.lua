local addonName, addon = ...

local TITLE_HEIGHT = 20
local ROW_HEIGHT = 16
local DIVIDER_HEIGHT = 1
local PADDING = 8
local FRAME_WIDTH = 200

local rowPool = {}
local dividerPool = {}

local function SavePriorityFramePosition()
	if not addon.Frames.priorityFrame then
		return
	end

	local point, relativeTo, relativePoint, xOffset, yOffset = addon.Frames.priorityFrame:GetPoint()

	PityRollDB.priorityFramePosition = {
		point = point,
		relativeTo = nil,
		relativePoint = relativePoint,
		xOffset = xOffset,
		yOffset = yOffset
	}
end

local function GetPooledDivider(index)
	local divider = dividerPool[index]
	if not divider then
		divider = addon.Frames.priorityFrame:CreateTexture(nil, "ARTWORK")
		divider:SetColorTexture(0.5, 0.5, 0.5, 0.8)
		divider:SetHeight(DIVIDER_HEIGHT)
		dividerPool[index] = divider
	end
	return divider
end

local function GetPooledRow(index)
	local row = rowPool[index]
	if not row then
		row = addon.Frames.priorityFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
		row:SetJustifyH("LEFT")
		rowPool[index] = row
	end
	return row
end

function addon.CreatePriorityFrame()
	if addon.Frames.priorityFrame then
		return
	end

	addon.Frames.priorityFrame = CreateFrame("Frame", "PityRollPriorityFrame", UIParent)
	addon.Frames.priorityFrame:SetSize(FRAME_WIDTH, TITLE_HEIGHT + PADDING * 2)

	if PityRollDB.priorityFramePosition then
		local pos = PityRollDB.priorityFramePosition
		addon.Frames.priorityFrame:SetPoint(pos.point, UIParent, pos.relativePoint, pos.xOffset, pos.yOffset)
	else
		addon.Frames.priorityFrame:SetPoint("CENTER", UIParent, "CENTER", 200, 100)
	end

	local bg = addon.Frames.priorityFrame:CreateTexture(nil, "BACKGROUND")
	bg:SetAllPoints(true)
	bg:SetColorTexture(0.1, 0.1, 0.1, 0.9)

	addon.Frames.priorityFrame:SetMovable(true)
	addon.Frames.priorityFrame:EnableMouse(true)
	addon.Frames.priorityFrame:RegisterForDrag("LeftButton")
	addon.Frames.priorityFrame:SetScript("OnDragStart", function(self) self:StartMoving() end)
	addon.Frames.priorityFrame:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		SavePriorityFramePosition()
	end)

	local title = addon.Frames.priorityFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	title:SetPoint("TOP", addon.Frames.priorityFrame, "TOP", 0, -PADDING)
	title:SetText("Priorities")
	addon.Frames.priorityFrame.title = title

	local titleDivider = addon.Frames.priorityFrame:CreateTexture(nil, "ARTWORK")
	titleDivider:SetColorTexture(0.5, 0.5, 0.5, 0.8)
	titleDivider:SetHeight(DIVIDER_HEIGHT)
	titleDivider:SetPoint("LEFT", addon.Frames.priorityFrame, "LEFT", PADDING, 0)
	titleDivider:SetPoint("RIGHT", addon.Frames.priorityFrame, "RIGHT", -PADDING, 0)
	titleDivider:SetPoint("TOP", title, "BOTTOM", 0, -4)
	addon.Frames.priorityFrame.titleDivider = titleDivider

	addon.Frames.priorityFrame:Hide()
end

function addon.ShowPriorityFrame(itemLink)
	local itemId = tonumber(itemLink and itemLink:match("item:(%d+)"))
	local tiers = itemId and addon.Priorities[itemId]

	if not tiers or #tiers == 0 then
		addon.HidePriorityFrame()
		return
	end

	addon.CreatePriorityFrame()

	local numTiers = #tiers
	local height = PADDING * 2 + TITLE_HEIGHT + DIVIDER_HEIGHT
		+ (numTiers * ROW_HEIGHT) + ((numTiers - 1) * DIVIDER_HEIGHT)
	addon.Frames.priorityFrame:SetSize(FRAME_WIDTH, height)

	local anchor = addon.Frames.priorityFrame.titleDivider
	for i, tier in ipairs(tiers) do
		local row = GetPooledRow(i)
		row:SetText(table.concat(tier, ", "))
		row:ClearAllPoints()
		row:SetPoint("LEFT", addon.Frames.priorityFrame, "LEFT", PADDING, 0)
		row:SetPoint("RIGHT", addon.Frames.priorityFrame, "RIGHT", -PADDING, 0)
		row:SetPoint("TOP", anchor, "BOTTOM", 0, -4)
		row:Show()

		if i < numTiers then
			local divider = GetPooledDivider(i)
			divider:ClearAllPoints()
			divider:SetPoint("LEFT", addon.Frames.priorityFrame, "LEFT", PADDING, 0)
			divider:SetPoint("RIGHT", addon.Frames.priorityFrame, "RIGHT", -PADDING, 0)
			divider:SetPoint("TOP", row, "BOTTOM", 0, -4)
			divider:Show()
			anchor = divider
		end
	end

	for i = numTiers + 1, #rowPool do
		rowPool[i]:Hide()
	end
	for i = numTiers, #dividerPool do
		dividerPool[i]:Hide()
	end

	addon.Frames.priorityFrame:Show()
end

function addon.HidePriorityFrame()
	if addon.Frames.priorityFrame then
		addon.Frames.priorityFrame:Hide()
	end
end
