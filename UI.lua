local addonName, addon = ...
local Constants = addon.Constants
local State = addon.State

local function SaveButtonFramePosition()
	if not addon.Frames.buttonFrame then
		return
	end

	local point, relativeTo, relativePoint, xOffset, yOffset = addon.Frames.buttonFrame:GetPoint()

	PityRollDB.buttonFramePosition = {
		point = point,
		relativeTo = nil,
		relativePoint = relativePoint,
		xOffset = xOffset,
		yOffset = yOffset
	}
end

local function SavePityFramePosition()
	if not addon.Frames.pityRollFrame then
		return
	end

	local point, relativeTo, relativePoint, xOffset, yOffset = addon.Frames.pityRollFrame:GetPoint()

	PityRollDB.pityFramePosition = {
		point = point,
		relativeTo = nil,
		relativePoint = relativePoint,
		xOffset = xOffset,
		yOffset = yOffset
	}
end

function addon.UpdateButtonFrameButtons()
	if not addon.Frames.buttonFrame then
		return
	end

	if addon.Frames.pityRollFrame and addon.Frames.pityRollFrame:IsShown() then
		addon.Frames.buttonFrame.abortButton:Show()
		addon.Frames.buttonFrame.abortButton:Enable()

		if State.tieResolutionMode and not State.selectedWinner then
			addon.Frames.buttonFrame.finishButton:Disable()
		else
			addon.Frames.buttonFrame.finishButton:Enable()
		end
	else
		addon.Frames.buttonFrame.abortButton:Hide()
		addon.Frames.buttonFrame.finishButton:Disable()
	end
end

function addon.CreatePityRollFrame()
	if addon.Frames.pityRollFrame then
		for _, squareData in ipairs(State.gridSquares) do
			squareData.texture:Hide()
			if squareData.nameText then
				squareData.nameText:Hide()
			end
			if squareData.rollText then
				squareData.rollText:Hide()
			end
			if squareData.clickFrame then
				squareData.clickFrame:Hide()
			end
		end
		State.gridSquares = {}
		State.playerRolls = {}
		addon.Frames.pityRollFrame:Show()
		addon.UpdateButtonFrameButtons()
		addon.Frames.eventFrame:RegisterEvent("CHAT_MSG_SYSTEM")
		return
	end

	addon.Frames.pityRollFrame = CreateFrame("Frame", "PityRollFrame", UIParent)
	addon.Frames.pityRollFrame:SetSize(430, 210)

	if PityRollDB.pityFramePosition then
		local pos = PityRollDB.pityFramePosition
		addon.Frames.pityRollFrame:SetPoint(pos.point, UIParent, pos.relativePoint, pos.xOffset, pos.yOffset)
	else
		addon.Frames.pityRollFrame:SetPoint("CENTER")
	end

	local bg = addon.Frames.pityRollFrame:CreateTexture(nil, "BACKGROUND")
	bg:SetAllPoints(true)
	bg:SetColorTexture(0.1, 0.1, 0.1, 0.9)

	addon.Frames.pityRollFrame:SetMovable(true)
	addon.Frames.pityRollFrame:EnableMouse(true)
	addon.Frames.pityRollFrame:RegisterForDrag("LeftButton")
	addon.Frames.pityRollFrame:SetScript("OnDragStart", function(self) self:StartMoving() end)
	addon.Frames.pityRollFrame:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		SavePityFramePosition()
	end)
	addon.Frames.pityRollFrame:SetScript("OnHide", function(self)
		addon.Frames.eventFrame:UnregisterEvent("CHAT_MSG_SYSTEM")
		addon.UpdateButtonFrameButtons()
	end)

	addon.Frames.pityRollFrame:Show()
	addon.UpdateButtonFrameButtons()
	addon.Frames.eventFrame:RegisterEvent("CHAT_MSG_SYSTEM")
end

function addon.CreateButtonFrame()
	if addon.Frames.buttonFrame then
		addon.Frames.buttonFrame:Show()
		return
	end

	addon.Frames.buttonFrame = CreateFrame("Frame", "PityRollButtonFrame", UIParent)
	addon.Frames.buttonFrame:SetSize(310, 30)

	if PityRollDB.buttonFramePosition then
		local pos = PityRollDB.buttonFramePosition
		addon.Frames.buttonFrame:SetPoint(pos.point, UIParent, pos.relativePoint, pos.xOffset, pos.yOffset)
	else
		addon.Frames.buttonFrame:SetPoint("CENTER", UIParent, "CENTER", 0, -200)
	end

	local bg = addon.Frames.buttonFrame:CreateTexture(nil, "BACKGROUND")
	bg:SetAllPoints(true)
	bg:SetColorTexture(0.1, 0.1, 0.1, 0.8)

	addon.Frames.buttonFrame:SetMovable(true)
	addon.Frames.buttonFrame:EnableMouse(true)
	addon.Frames.buttonFrame:RegisterForDrag("LeftButton")
	addon.Frames.buttonFrame:SetScript("OnDragStart", function(self) self:StartMoving() end)
	addon.Frames.buttonFrame:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		SaveButtonFramePosition()
	end)

	local abortButton = CreateFrame("Button", nil, addon.Frames.buttonFrame, "UIPanelButtonTemplate")
	abortButton:SetSize(90, 25)
	abortButton:SetPoint("CENTER", addon.Frames.buttonFrame, "CENTER", -100, 0)
	abortButton:SetText("Abort")
	abortButton:Hide()
	abortButton:SetScript("OnClick", function()
		addon.EndSession()
		print("|cFF00FF00PityRoll|r: Roll session aborted")
	end)

	addon.Frames.buttonFrame.abortButton = abortButton

	local finishButton = CreateFrame("Button", nil, addon.Frames.buttonFrame, "UIPanelButtonTemplate")
	finishButton:SetSize(90, 25)
	finishButton:SetPoint("CENTER", addon.Frames.buttonFrame, "CENTER", 0, 0)
	finishButton:SetText("Award Item")
	finishButton:SetScript("OnClick", function()
		addon.FinishRollSession(nil)
	end)

	addon.Frames.buttonFrame.finishButton = finishButton

	local endBossButton = CreateFrame("Button", nil, addon.Frames.buttonFrame, "UIPanelButtonTemplate")
	endBossButton:SetSize(90, 25)
	endBossButton:SetPoint("CENTER", addon.Frames.buttonFrame, "CENTER", 100, 0)
	endBossButton:SetText("End Boss")
	endBossButton:SetScript("OnClick", function()
		addon.BossEndSession()
	end)

	addon.Frames.buttonFrame.endBossButton = endBossButton

	addon.UpdateButtonFrameButtons()
	addon.Frames.buttonFrame:Show()
end

function addon.HideButtonFrame()
	if addon.Frames.buttonFrame then
		addon.Frames.buttonFrame:Hide()
	end
end
