local mod	= DBM:NewMod("KelThuzadVanilla", "DBM-Raids-Vanilla", 1)
local L		= mod:GetLocalizedStrings()

if DBM:IsSeasonal("SeasonOfDiscovery") then
	mod.statTypes = "normal,heroic,mythic"
else
	mod.statTypes = "normal"
end

mod:SetRevision("@file-date-integer@")
mod:SetCreatureID(15990)
mod:SetEncounterID(1114)
--mod:SetModelID(15945)--Doesn't work at all, doesn't even render.
mod:SetMinCombatTime(60)
mod:SetUsedIcons(1, 2, 3, 4, 5, 6, 7, 8)
mod:SetZone(533)

if DBM:IsSeasonal("SeasonOfDiscovery") then
	mod:RegisterCombat("combat")
else
	mod:RegisterCombat("combat_yell", L.Yell)
end

mod:RegisterEventsInCombat(
	"SPELL_AURA_APPLIED 27808 27819 28410",
	"SPELL_AURA_REMOVED 28410",
	"SPELL_CAST_SUCCESS 27810 27819 27808",
	"UNIT_HEALTH mouseover target",
	"UNIT_TARGETABLE_CHANGED"
)

-- New spell ID found in logs on SoD
-- 364341 (Survivor of the Damned) cast on kill, ID looks like SoM, seems irrelevant

-- On SoD ENCOUTNER_START triggers shortly before the yell and is the better trigger. Phase 1 is shorter on SoD
-- Not sure about Era, still using old logic there until we can confirm that ENCOUTNER_START works the same way.
local phase1Duration = DBM:IsSeasonal("SeasonOfDiscovery") and 247 or 330

--[[
ability.id = 27810 or ability.id = 27819 or ability.id = 27808 and type = "cast"
 or (source.type = "NPC" and source.firstSeen = timestamp) or (target.type = "NPC" and target.firstSeen = timestamp)
--]]
local warnAddsSoon			= mod:NewAnnounce("warnAddsSoon", 1, "134321")
local warnPhase2			= mod:NewPhaseAnnounce(2, 3, nil, nil, nil, nil, nil, 2)
local warnBlastTargets		= mod:NewTargetAnnounce(27808, 2)
local warnFissure			= mod:NewTargetAnnounce(27810, 4, nil, nil, nil, nil, nil, 2)
local warnMana				= mod:NewTargetAnnounce(27819, 2)
local warnChainsTargets		= mod:NewTargetNoFilterAnnounce(28410, 4)

local specwarnP2Soon		= mod:NewSpecialWarning("specwarnP2Soon")
local specWarnManaBomb		= mod:NewSpecialWarningMoveAway(27819, nil, nil, nil, 1, 2)
local specWarnBlast			= mod:NewSpecialWarningTarget(27808, "Healer", nil, nil, 1, 2)
local specWarnFissureYou	= mod:NewSpecialWarningYou(27810, nil, nil, nil, 3, 2)
local yellManaBomb			= mod:NewShortYell(27819)
local yellFissure			= mod:NewYell(27810)

--Fissure timer is 13-30 or something pretty wide, so no timer
local timerManaBomb			= mod:NewCDTimer(20, 27819, nil, nil, nil, 3)--20-50 (still true in vanilla, kind of shitty variation too)
local timerFrostBlastCD		= mod:NewVarTimer("v33.5-46", 27808, nil, nil, nil, 3, nil, DBM_COMMON_L.DEADLY_ICON)--33-46
local timerfrostBlast		= mod:NewBuffActiveTimer(4, 27808, nil, nil, nil, 5, nil, DBM_COMMON_L.HEALER_ICON)
local timerMCCD				= mod:NewCDTimer(90, 28410, nil, nil, nil, 3)--Probably should also be made a var timer with good variance data
local timerPhase2			= mod:NewTimer(phase1Duration, "TimerPhase2", "136116", nil, nil, 6)

mod:AddSetIconOption("SetIconOnMC2", 28410, false, 0, {1, 2, 3, 4, 5})
mod:AddSetIconOption("SetIconOnManaBomb", 27819, false, 0, {8})
mod:AddSetIconOption("SetIconOnFrostTomb2", 27808, false, 0, {1, 2, 3, 4, 5, 6, 7, 8})
mod:AddRangeFrameOption(10, 27819)

mod.vb.warnedAdds = false
mod.vb.MCIcon1 = 1
mod.vb.MCIcon2 = 5
local frostBlastTargets = {}

local function AnnounceBlastTargets(self)
	if self.Options.SetIconOnFrostTomb2 then
		for i = #frostBlastTargets, 1, -1 do
			self:SetIcon(frostBlastTargets[i], 8 - i, 4.5)
			frostBlastTargets[i] = nil
		end
	end
	timerfrostBlast:Start(3.5)
end

local function RangeToggle(show)
	if show then
		DBM.RangeCheck:Show(10)
	else
		DBM.RangeCheck:Hide()
	end
end

function mod:OnCombatStart(delay)
	self:SetStage(1)
	table.wipe(frostBlastTargets)
	self.vb.warnedAdds = false
	self.vb.MCIcon1 = 1
	self.vb.MCIcon2 = 5
	specwarnP2Soon:Schedule(phase1Duration - 10 - delay)
	timerPhase2:Start()
	warnPhase2:Schedule(phase1Duration - delay)
	warnPhase2:ScheduleVoice(phase1Duration - delay, "ptwo")
	if self.Options.RangeFrame then
		self:Schedule(phase1Duration - delay, RangeToggle, true)
	end
end

function mod:OnCombatEnd()
	if self.Options.RangeFrame then
		DBM.RangeCheck:Hide()
	end
end

function mod:SPELL_CAST_SUCCESS(args)
	if args:IsSpell(27810) then
		if args.destName then
			if args:IsPlayer() then
				specWarnFissureYou:Show()
				specWarnFissureYou:Play("targetyou")
				yellFissure:Yell()
			else
				warnFissure:Show(args.destName)
			end
		else
			warnFissure:Show(DBM_COMMON_L.UNKNOWN)
		end
	elseif args:IsSpell(27819) then
		timerManaBomb:Start()
	elseif args:IsSpell(27808) then
		timerFrostBlastCD:Start()
	end
end

function mod:SPELL_AURA_APPLIED(args)
	if args:IsSpell(27808) then -- Frost Blast
		table.insert(frostBlastTargets, args.destName)
		self:Unschedule(AnnounceBlastTargets)
		self:Schedule(0.5, AnnounceBlastTargets, self)
		if self.Options.SpecWarn27808target then
			specWarnBlast:CombinedShow(0.5, args.destName)
			specWarnBlast:ScheduleVoice(0.5, "healall")
		else
			warnBlastTargets:CombinedShow(0.5, args.destName)
		end
	elseif args:IsSpell(27819) then -- Mana Bomb
		if self.Options.SetIconOnManaBomb then
			self:SetIcon(args.destName, 8, 5.5)
		end
		if args:IsPlayer() then
			specWarnManaBomb:Show()
			specWarnManaBomb:Play("scatter")
			yellManaBomb:Yell()
		else
			warnMana:Show(args.destName)
		end
	elseif args:IsSpell(28410) then -- Chains of Kel'Thuzad
		if self:AntiSpam() then
			self.vb.MCIcon1 = 1
			self.vb.MCIcon2 = 5
			timerMCCD:Start(60)--60 seconds?
		end
		if self.Options.SetIconOnMC2 then
			local _, _, group = GetRaidRosterInfo(UnitInRaid(args.destName) or 0)
			if group % 2 == 1 then
				self:SetIcon(args.destName, self.vb.MCIcon1)
				self.vb.MCIcon1 = self.vb.MCIcon1 + 1
			else
				self:SetIcon(args.destName, self.vb.MCIcon2)
				self.vb.MCIcon2 = self.vb.MCIcon2 - 1
			end
		end
		warnChainsTargets:CombinedShow(1, args.destName)
	end
end

function mod:SPELL_AURA_REMOVED(args)
	if args:IsSpell(28410) then
		if self.Options.SetIconOnMC2 then
			self:SetIcon(args.destName, 0)
		end
	end
end

function mod:UNIT_HEALTH(uId)
	if not self.vb.warnedAdds and self:GetUnitCreatureId(uId) == 15990 and UnitHealth(uId) / UnitHealthMax(uId) <= 0.48 then
		self.vb.warnedAdds = true
		warnAddsSoon:Show()
	end
end

--Classic probably won't have UNIT_TARGETABLE_CHANGED, so backups are in place
function mod:UNIT_TARGETABLE_CHANGED()
	if self.vb.phase == 1 then
		self:Unschedule(RangeToggle)
		warnPhase2:Cancel()
		warnPhase2:CancelVoice()
		self:SetStage(2)
		warnPhase2:Show()
		warnPhase2:Play("ptwo")
		if self.Options.RangeFrame then
			DBM.RangeCheck:Show(10)
		end
	end
end
