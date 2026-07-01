LoadoutLocker = LoadoutLocker or {}
local Menu = {}
LoadoutLocker.Menu = Menu
local Shell = LoadoutLocker.MenuShell
local Widgets = LoadoutLocker.MenuWidgets
local C = LoadoutLocker.Constants
local DB = LoadoutLocker.DB
local Loadout = LoadoutLocker.Loadout
local Gear = LoadoutLocker.Gear
local Dungeons = LoadoutLocker.Dungeons
local Raids = LoadoutLocker.Raids
local Delves = LoadoutLocker.Delves
local PvP = LoadoutLocker.PvP
local subTabBuildToken = { dungeons = 0, delves = 0 }
local subTabButtons = { dungeons = {}, delves = {} }
local selectedSubTabSectionKey = { dungeons = nil, delves = nil }
local HELP_TEXT = "Equip gear, select a talent loadout, then save with the talent panel button or |cffffffff/locker save|r. Changing loadouts automatically equips the saved gear set.\n\n"
    .. "|cffffffffCommands|r\n"
    .. "/locker - open this menu\n"
    .. "/locker save - save equipped gear to the active loadout\n"
    .. "/locker list - list saved gear sets\n"
    .. "/locker scan - check bags for upgrades\n"
    .. "/locker delete - remove saved gear for the active loadout\n\n"
    .. "Also available under |cffffffffEsc > Options > AddOns|r."
local TAB_INTRO = {
    general = "LoadoutLocker saves your equipped gear to each talent loadout and swaps it when you change builds.",
    priority = "When upgrade prompts appear, higher stats at the top break ties between same item level and track.",
    loadouts = "Review talent loadouts across all specializations, manage saved gear sets, ignored upgrade slots, and copying between loadouts.",
    dungeons = "Set a default talent loadout and optional per-dungeon overrides from any saved loadout (Spec-Talent name). Use the category buttons above to browse season and expansion dungeons.",
    raids = "Set a default raid loadout and optional per-boss overrides from any saved loadout. In-game prompts respect your lockout progress and can switch specialization.",
    delves = "Set a default delve loadout and optional per-delve overrides from any saved loadout. Use the Midnight or TWW buttons above to browse delves.",
    pvp = "Set a default PvP loadout and optional overrides for arenas and battlegrounds from any saved loadout.",
}
local selectedManageLoadoutKey
local selectedCopySourceKey
local selectedCopyTargetKey
local RefreshUI = LoadoutLocker.RefreshUI
local function RequestTabRefresh(tabID)
    if Shell.activeTab == tabID then
        Shell:RefreshTab(tabID)
    else
        Shell:SelectTab(tabID)
    end
end
local function FindListEntryByKey(list, key)
    for _, entry in ipairs(list) do
        if entry.key == key then
            return entry
        end
    end
end

local function SelectFirstExcluding(list, excludeKey)
    for _, entry in ipairs(list) do
        if entry.key ~= excludeKey then
            return entry.key
        end
    end
end

local function ResolveLoadoutDropdownValue(ref, emptyValue)
    if not ref then
        return emptyValue
    end
    if type(ref) == "table" then
        return Loadout.EncodeLoadoutKey(ref.specID, ref.configID)
    end
    return tostring(ref)
end

local function CopyDropdownList(source)
    local copy = {}
    if source then
        for key, label in pairs(source) do
            copy[key] = label
        end
    end
    return copy
end

local function BuildLoadoutKeyDropdownList(entries, options)
    options = options or {}
    local list = {}
    if options.includeNone then
        list[""] = "None"
    end
    if options.includeUseDefault then
        list.default = "Use default"
    end
    if options.emptyLabel then
        list[""] = options.emptyLabel
        return list
    end
    for _, entry in ipairs(entries) do
        local name = entry.label
        if options.markSaved and entry.hasSavedGear then
            name = name .. " (saved)"
        end
        list[entry.key] = name
    end
    return list
end

local function EnsureLoadoutInDropdown(list, ref)
    if type(ref) ~= "table" or not ref.specID or not ref.configID then
        return list
    end

    local key = Loadout.EncodeLoadoutKey(ref.specID, ref.configID)
    if not list[key] then
        list[key] = Loadout.FormatLoadoutLabel(ref.specID, Loadout.GetLoadoutName(ref.configID))
    end
    return list
end

local function GetOverrideDropdownState(overrideList, override)
    if type(override) == "number" then
        override = {
            specID = Loadout.GetSpecID(),
            configID = override,
        }
    end

    local value = ResolveLoadoutDropdownValue(override, "default")
    if type(override) ~= "table" or not override.specID or not override.configID then
        return value, overrideList
    end

    local key = Loadout.EncodeLoadoutKey(override.specID, override.configID)
    if overrideList[key] then
        return value, overrideList
    end

    local list = CopyDropdownList(overrideList)
    list[key] = Loadout.FormatLoadoutLabel(override.specID, Loadout.GetLoadoutName(override.configID))
    return value, list
end

local function AddDefaultLoadoutDropdown(builder, getDefaultRef, setDefaultRef)
    local defaultRef = getDefaultRef()
    local list = BuildLoadoutKeyDropdownList(Loadout.GetAllConfigList(), { includeNone = true })
    list = EnsureLoadoutInDropdown(list, defaultRef)
    return Widgets.AddDropdown(
        builder,
        220,
        list,
        ResolveLoadoutDropdownValue(defaultRef, ""),
        function(value)
            setDefaultRef(value == "" and nil or value)
        end
    )
end
local function ResolveManageLoadoutKey(savedSets)
    if #savedSets == 0 then
        return nil
    end
    if not selectedManageLoadoutKey or not FindListEntryByKey(savedSets, selectedManageLoadoutKey) then
        selectedManageLoadoutKey = savedSets[1].key
    end
    return selectedManageLoadoutKey
end
local function ResolveCopyLoadoutKeys(savedSets, allLoadouts)
    if #savedSets == 0 then
        selectedCopySourceKey = nil
    elseif not selectedCopySourceKey or not FindListEntryByKey(savedSets, selectedCopySourceKey) then
        selectedCopySourceKey = savedSets[1].key
    end
    if #allLoadouts == 0 then
        selectedCopyTargetKey = nil
    elseif not selectedCopyTargetKey
        or not FindListEntryByKey(allLoadouts, selectedCopyTargetKey)
        or selectedCopyTargetKey == selectedCopySourceKey
    then
        selectedCopyTargetKey = SelectFirstExcluding(allLoadouts, selectedCopySourceKey)
    end
end
local function BuildGeneralTab(content)
    Shell:ClearScroll(content.scrollChild)
    local builder = Widgets.NewBuilder(content.scrollChild)
    Widgets.AddTabIntro(builder, TAB_INTRO.general)
    Widgets.AddHeading(builder, "Prompts")
    Widgets.AddCheckbox(builder, "Offer upgrade prompts when swapping loadouts", DB:AreUpgradeChecksEnabled(), function(value)
        DB:SetUpgradeChecksEnabled(value)
    end)
    Widgets.AddCheckbox(builder, "Prompt to switch loadouts when entering dungeons", DB:AreDungeonPromptsEnabled(), function(value)
        DB:SetDungeonPromptsEnabled(value)
    end)
    Widgets.AddCheckbox(builder, "Prompt to switch loadouts when entering raids or after boss kills", DB:AreRaidPromptsEnabled(), function(value)
        DB:SetRaidPromptsEnabled(value)
    end)
    Widgets.AddCheckbox(builder, "Prompt to switch loadouts when entering delves", DB:AreDelvePromptsEnabled(), function(value)
        DB:SetDelvePromptsEnabled(value)
    end)
    Widgets.AddCheckbox(builder, "Prompt to switch loadouts when entering PvP", DB:ArePvPPromptsEnabled(), function(value)
        DB:SetPvPPromptsEnabled(value)
    end)
    Widgets.AddGap(builder, 12)
    Widgets.AddHeading(builder, "Commands")
    Widgets.AddLabel(builder, HELP_TEXT)
    Widgets.FinishBuilder(builder)
end
local function RefreshPriorityRows(content)
    local priority = DB:GetTertiaryPriority()
    for index, field in ipairs(priority) do
        local row = content.priorityRows[index]
        if row then
            row:Refresh(index, C.GetTertiarySettingLabel(field), index <= 1, index >= #priority)
        end
    end
end
local function BuildPriorityTab(content)
    if content.priorityRows then
        RefreshPriorityRows(content)
        return
    end
    Shell:ClearScroll(content.scrollChild)
    local builder = Widgets.NewBuilder(content.scrollChild)
    Widgets.AddTabIntro(builder, TAB_INTRO.priority)
    Widgets.AddHeading(builder, "Tertiary stat priority")
    content.priorityRows = {}
    local priority = DB:GetTertiaryPriority()
    for index, field in ipairs(priority) do
        local _, row = Widgets.AddPriorityRow(
            builder,
            index,
            C.GetTertiarySettingLabel(field),
            function()
                local currentField = DB:GetTertiaryPriority()[index]
                if currentField and DB:MoveTertiaryPriority(currentField, "up") then
                    RequestTabRefresh("priority")
                end
            end,
            function()
                local currentField = DB:GetTertiaryPriority()[index]
                if currentField and DB:MoveTertiaryPriority(currentField, "down") then
                    RequestTabRefresh("priority")
                end
            end,
            index <= 1,
            index >= #priority
        )
        content.priorityRows[index] = row
    end
    Widgets.AddButton(builder, "Reset Priority", 140, function()
        DB:ResetTertiaryPriority()
        content.priorityRows = nil
        RequestTabRefresh("priority")
    end)
    Widgets.FinishBuilder(builder)
end
local function BuildLoadoutOverviewRows(savedSets)
    local rows = {}
    local currentSpecID = Loadout.GetSpecID()
    local activeConfigID = currentSpecID and Loadout.GetLoadoutConfigID(currentSpecID)
    for _, entry in ipairs(savedSets) do
        rows[#rows + 1] = {
            specName = entry.specName,
            name = entry.name,
            equipmentSetName = entry.equipmentSetName or "",
            isActive = entry.specID == currentSpecID and entry.configID == activeConfigID,
        }
    end
    return rows
end
local function BuildLoadoutsTab(content)
    Shell:ClearScroll(content.scrollChild)
    local builder = Widgets.NewBuilder(content.scrollChild)
    Widgets.AddTabIntro(builder, TAB_INTRO.loadouts)
    local savedSets = Loadout.GetAllSavedLoadoutList()
    Widgets.AddHeading(builder, "Overview")
    Widgets.AddLoadoutOverviewTable(builder, BuildLoadoutOverviewRows(savedSets))
    Widgets.AddGap(builder, 16)
    local manageKey = ResolveManageLoadoutKey(savedSets)
    local manageSpecID, manageConfigID = Loadout.DecodeLoadoutKey(manageKey)
    local allLoadouts = Loadout.GetAllConfigList()
    ResolveCopyLoadoutKeys(savedSets, allLoadouts)
    Widgets.AddHeading(builder, "Manage saved gear set")
    if #savedSets == 0 then
        Widgets.AddEmptyDropdown(builder, 220, "No saved gear sets")
    else
        Widgets.AddDropdownButtonRow(
            builder,
            220,
            BuildLoadoutKeyDropdownList(savedSets),
            manageKey,
            function(value)
                selectedManageLoadoutKey = value
                RequestTabRefresh("loadouts")
            end,
            "Delete Gear Set",
            120,
            function()
                if manageSpecID and manageConfigID and Gear.DeleteSavedGear(manageConfigID, manageSpecID) then
                    RequestTabRefresh("loadouts")
                end
            end,
            not manageKey
        )
    end
    Widgets.AddLabel(builder, "Ignored upgrade slots")
    local slots = manageSpecID and manageConfigID and DB:GetIgnoredUpgradeSlotList(manageSpecID, manageConfigID) or {}
    local ignoredPanelWidth = math.floor((builder.parent:GetWidth() - 8) / 2)
    Widgets.AddInsetPanel(builder, function(panel)
        if #slots == 0 then
            Widgets.AddLabel(panel, "No ignored upgrade prompts for this loadout.")
        else
            for _, slot in ipairs(slots) do
                Widgets.AddSlotClearRow(panel, C.GetSlotLabel(slot), function()
                    if manageSpecID and manageConfigID then
                        DB:ClearIgnoredUpgradeSlot(manageSpecID, manageConfigID, slot)
                        RequestTabRefresh("loadouts")
                    end
                end)
            end
        end
    end, 40, ignoredPanelWidth)
    Widgets.AddGap(builder, 8)
    Widgets.AddButton(builder, "Clear All Ignored", 150, function()
        if manageSpecID and manageConfigID and DB:ClearAllIgnoredUpgradeSlots(manageSpecID, manageConfigID) then
            RequestTabRefresh("loadouts")
        end
    end, #slots == 0)
    Widgets.AddGap(builder, 24)
    Widgets.AddHeading(builder, "Copy gear set")
    local copySourceSpecID, copySourceConfigID = Loadout.DecodeLoadoutKey(selectedCopySourceKey)
    local copyTargetSpecID, copyTargetConfigID = Loadout.DecodeLoadoutKey(selectedCopyTargetKey)
    local canCopy = copySourceSpecID
        and copySourceConfigID
        and copyTargetSpecID
        and copyTargetConfigID
        and selectedCopySourceKey ~= selectedCopyTargetKey
    if #savedSets == 0 then
        Widgets.AddEmptyDropdown(builder, 220, "No saved gear sets")
    else
        Widgets.AddDropdownButtonRow(
            builder,
            220,
            BuildLoadoutKeyDropdownList(savedSets),
            selectedCopySourceKey,
            function(value)
                selectedCopySourceKey = value
                RequestTabRefresh("loadouts")
            end,
            "Copy Gear Set",
            120,
            function()
                if Gear.CopyGearSetToLoadout(
                    copySourceConfigID,
                    copyTargetConfigID,
                    copySourceSpecID,
                    copyTargetSpecID
                ) then
                    RefreshUI()
                    RequestTabRefresh("loadouts")
                end
            end,
            not canCopy
        )
    end
    Widgets.AddLabel(builder, "To")
    if #allLoadouts == 0 then
        Widgets.AddEmptyDropdown(builder, 220, "No loadouts found")
    else
        Widgets.AddDropdown(builder, 220, BuildLoadoutKeyDropdownList(allLoadouts, { markSaved = true }), selectedCopyTargetKey, function(value)
            selectedCopyTargetKey = value
            RequestTabRefresh("loadouts")
        end)
    end
    Widgets.FinishBuilder(builder)
end
local function IsAssignmentSectionBuildValid(token, tabID)
    return Shell.activeTab == tabID and token == subTabBuildToken[tabID]
end
local function BuildAssignmentSection(scrollChild, items, overrideList, token, tabID, assignmentKey, getAssignments, clearLoadoutRef, setLoadoutRef, onChanged)
    if not IsAssignmentSectionBuildValid(token, tabID) then
        return
    end
    local builder = Widgets.NewBuilder(scrollChild)
    local assignments = getAssignments()
    local overrides = assignments and assignments[assignmentKey]
    for _, item in ipairs(items) do
        if not IsAssignmentSectionBuildValid(token, tabID) then
            return
        end
        Widgets.AddAssignmentRow(
            builder,
            item.name,
            function()
                return GetOverrideDropdownState(overrideList, overrides and overrides[item.key])
            end,
            function(key)
                if key == "default" then
                    clearLoadoutRef(item.key)
                else
                    setLoadoutRef(item.key, key)
                end
                if onChanged then
                    onChanged()
                end
            end
        )
    end
    Widgets.FinishBuilder(builder)
end
local function SelectAssignmentSection(content, section, overrideList, opts)
    opts.bumpToken()
    local token = opts.getToken()
    Shell:ClearScroll(content.scrollChild)
    for _, button in ipairs(opts.buttons) do
        button:SetSelected(button.sectionKey == section.key)
    end
    if section then
        if opts.setSelectedKey then
            opts.setSelectedKey(section.key)
        end
        BuildAssignmentSection(
            content.scrollChild,
            section[opts.itemsKey],
            overrideList,
            token,
            opts.tabID,
            opts.assignmentKey,
            opts.getAssignments,
            opts.clearLoadoutRef,
            opts.setLoadoutRef,
            opts.onChanged
        )
    end
end
local SUB_TAB_CONFIG = {
    dungeons = {
        tabID = "dungeons",
        intro = TAB_INTRO.dungeons,
        defaultLoadoutLabel = "Default dungeon loadout",
        subBarRows = 2,
        itemsKey = "dungeons",
        assignmentKey = "dungeons",
        getSections = Dungeons.GetMenuSections,
        getDefaultLoadoutRef = function()
            return DB:GetDungeonDefaultLoadoutRef()
        end,
        setDefaultLoadoutRef = function(value)
            DB:SetDungeonDefaultConfigID(nil, value)
        end,
        getAssignments = function()
            return DB:GetDungeonAssignmentsIfExists()
        end,
        clearLoadoutRef = function(key)
            DB:ClearDungeonConfigID(nil, key)
        end,
        setLoadoutRef = function(key, value)
            DB:SetDungeonConfigID(nil, key, value)
        end,
        onAssignmentChanged = function()
            RequestTabRefresh("dungeons")
        end,
    },
    delves = {
        tabID = "delves",
        intro = TAB_INTRO.delves,
        defaultLoadoutLabel = "Default delve loadout",
        subBarRows = 1,
        itemsKey = "delves",
        assignmentKey = "delves",
        getSections = Delves.GetMenuSections,
        getDefaultLoadoutRef = function()
            return DB:GetDelveDefaultLoadoutRef()
        end,
        setDefaultLoadoutRef = function(value)
            DB:SetDelveDefaultConfigID(nil, value)
        end,
        getAssignments = function()
            return DB:GetDelveAssignmentsIfExists()
        end,
        clearLoadoutRef = function(key)
            DB:ClearDelveConfigID(nil, key)
        end,
        setLoadoutRef = function(key, value)
            DB:SetDelveConfigID(nil, key, value)
        end,
    },
}
local function LayoutSubTabButtons(subBar, sections, subBarRows, buttons, onClick)
    local subRowHeight = 28
    local subRowGap = 4
    wipe(buttons)

    local function addButton(index, section, x, y)
        local tabLabel = section.shortTabText or section.tabText
        local buttonWidth = math.min(118, math.max(68, #tabLabel * 7 + 18))
        local button = Widgets.CreateHeaderButton(subBar, section.tabText, buttonWidth, subRowHeight)
        button:SetPoint("TOPLEFT", subBar, "TOPLEFT", x, y)
        button.sectionKey = section.key
        button:SetScript("OnClick", function()
            onClick(section)
        end)
        if tabLabel ~= section.tabText then
            button.label:SetText(tabLabel)
        end
        buttons[index] = button
        return buttonWidth + 4
    end

    if subBarRows <= 1 then
        local x = 4
        for index, section in ipairs(sections) do
            x = x + addButton(index, section, x, -2)
        end
        return
    end

    local splitAt = math.ceil(#sections / 2)
    local rowX = { 4, 4 }
    local rowY = { -2, -(subRowHeight + subRowGap + 2) }
    for index, section in ipairs(sections) do
        local row = index <= splitAt and 1 or 2
        rowX[row] = rowX[row] + addButton(index, section, rowX[row], rowY[row])
    end
end
local function SelectSubTabSection(content, section, overrideList, config)
    SelectAssignmentSection(content, section, overrideList, {
        tabID = config.tabID,
        itemsKey = config.itemsKey,
        assignmentKey = config.assignmentKey,
        buttons = subTabButtons[config.tabID],
        bumpToken = function()
            subTabBuildToken[config.tabID] = subTabBuildToken[config.tabID] + 1
        end,
        getToken = function()
            return subTabBuildToken[config.tabID]
        end,
        setSelectedKey = function(key)
            selectedSubTabSectionKey[config.tabID] = key
        end,
        getAssignments = config.getAssignments,
        clearLoadoutRef = config.clearLoadoutRef,
        setLoadoutRef = config.setLoadoutRef,
        onChanged = config.onAssignmentChanged,
    })
end
local function BuildSubTabAssignmentsTab(content, config)
    local tabID = config.tabID
    Shell:ClearFrame(content.subBar)
    Shell:ClearFrame(content.header)
    local overrideList = BuildLoadoutKeyDropdownList(Loadout.GetAllConfigList(), { includeUseDefault = true })
    local sections = config.getSections()
    LayoutSubTabButtons(content.subBar, sections, config.subBarRows, subTabButtons[tabID], function(section)
        SelectSubTabSection(content, section, overrideList, config)
    end)
    local headerBuilder = Widgets.NewBuilder(content.header)
    Widgets.AddLabel(headerBuilder, config.intro)
    Widgets.AddLabel(headerBuilder, config.defaultLoadoutLabel)
    AddDefaultLoadoutDropdown(headerBuilder, config.getDefaultLoadoutRef, config.setDefaultLoadoutRef)
    Widgets.FinishBuilder(headerBuilder)
    content.header:SetHeight(math.max(headerBuilder.y + 8, 1))
    Shell:LayoutSubTabContent(content, config.subBarRows)
    local activeSection = sections[1]
    local selectedKey = selectedSubTabSectionKey[tabID]
    if selectedKey then
        for _, section in ipairs(sections) do
            if section.key == selectedKey then
                activeSection = section
                break
            end
        end
    end
    if activeSection then
        SelectSubTabSection(content, activeSection, overrideList, config)
    end
end
local function BuildDungeonsTab(content)
    BuildSubTabAssignmentsTab(content, SUB_TAB_CONFIG.dungeons)
end
local function BuildRaidsTab(content)
    Shell:ClearScroll(content.scrollChild)
    local builder = Widgets.NewBuilder(content.scrollChild)
    Widgets.AddTabIntro(builder, TAB_INTRO.raids)
    Widgets.AddLabel(builder, "Default raid loadout")
    AddDefaultLoadoutDropdown(builder, function()
        return DB:GetRaidDefaultLoadoutRef()
    end, function(value)
        DB:SetRaidDefaultConfigID(nil, value)
    end)
    Widgets.AddGap(builder, 10)
    local overrideList = BuildLoadoutKeyDropdownList(Loadout.GetAllConfigList(), { includeUseDefault = true })
    for _, section in ipairs(Raids.GetMenuSections()) do
        Widgets.AddHeading(builder, section.header)
        for raidIndex, raid in ipairs(section.raids) do
            local raidAssignment = DB:GetRaidAssignmentIfExists(nil, raid.key)
            if raidIndex > 1 then
                Widgets.AddSeparator(builder)
                Widgets.AddGap(builder, 6)
            end
            Widgets.AddHeading(builder, raid.name)
            for _, boss in ipairs(raid.bosses) do
                Widgets.AddAssignmentRow(
                    builder,
                    boss.name,
                    function()
                        return GetOverrideDropdownState(overrideList, raidAssignment and raidAssignment.bosses[boss.key])
                    end,
                    function(key)
                        if key == "default" then
                            DB:ClearRaidBossConfigID(nil, raid.key, boss.key)
                        else
                            DB:SetRaidBossConfigID(nil, raid.key, boss.key, key)
                        end
                    end
                )
            end
        end
    end
    Widgets.FinishBuilder(builder)
end
local function BuildContentAssignmentsTab(builder, intro, getDefaultLoadoutRef, setDefaultLoadoutRef, getSections, getOverride, clearLoadoutRef, setLoadoutRef, collectionKey)
    Widgets.AddTabIntro(builder, intro)
    Widgets.AddLabel(builder, "Default loadout")
    AddDefaultLoadoutDropdown(builder, getDefaultLoadoutRef, setDefaultLoadoutRef)
    Widgets.AddGap(builder, 10)
    local overrideList = BuildLoadoutKeyDropdownList(Loadout.GetAllConfigList(), { includeUseDefault = true })
    for _, section in ipairs(getSections()) do
        Widgets.AddHeading(builder, section.header)
        for _, item in ipairs(section[collectionKey]) do
            Widgets.AddAssignmentRow(
                builder,
                item.name,
                function()
                    return GetOverrideDropdownState(overrideList, getOverride(item.key))
                end,
                function(key)
                    if key == "default" then
                        clearLoadoutRef(item.key)
                    else
                        setLoadoutRef(item.key, key)
                    end
                end
            )
        end
    end
    Widgets.FinishBuilder(builder)
end
local function BuildDelvesTab(content)
    BuildSubTabAssignmentsTab(content, SUB_TAB_CONFIG.delves)
end
local function BuildPvPTab(content)
    Shell:ClearScroll(content.scrollChild)
    local builder = Widgets.NewBuilder(content.scrollChild)
    BuildContentAssignmentsTab(
        builder,
        TAB_INTRO.pvp,
        function()
            return DB:GetPvPDefaultLoadoutRef()
        end,
        function(value)
            DB:SetPvPDefaultConfigID(nil, value)
        end,
        PvP.GetMenuSections,
        function(key)
            local store = DB:GetPvPAssignments()
            return store and store.modes and store.modes[key]
        end,
        function(key)
            DB:ClearPvPConfigID(nil, key)
        end,
        function(key, value)
            DB:SetPvPConfigID(nil, key, value)
        end,
        "modes"
    )
end
local TAB_BUILDERS = {
    general = BuildGeneralTab,
    priority = BuildPriorityTab,
    loadouts = BuildLoadoutsTab,
    dungeons = BuildDungeonsTab,
    raids = BuildRaidsTab,
    delves = BuildDelvesTab,
    pvp = BuildPvPTab,
}
local function OnTabSelected(content, tabID)
    subTabBuildToken.dungeons = subTabBuildToken.dungeons + 1
    subTabBuildToken.delves = subTabBuildToken.delves + 1
    if tabID == "dungeons" or tabID == "delves" then
        Shell:EnsureSubTabContent(content)
    else
        Shell:EnsurePlainContent(content)
    end
    local builder = TAB_BUILDERS[tabID]
    if builder then
        builder(content)
    end
end
Shell:SetOnTabSelected(OnTabSelected)
function Menu.Show(tabID)
    local savedSets = Loadout.GetAllSavedLoadoutList()
    if #savedSets > 0 then
        local specID = Loadout.GetSpecID()
        local configID = specID and Loadout.GetLoadoutConfigID(specID)
        local activeKey = Loadout.EncodeLoadoutKey(specID, configID)
        if FindListEntryByKey(savedSets, activeKey) then
            selectedManageLoadoutKey = activeKey
        else
            selectedManageLoadoutKey = savedSets[1].key
        end
    end
    Shell:Show(tabID or "general")
end
function Menu.IsShown()
    return Shell:IsShown()
end
local optionsPanel
local optionsCategory
local optionsRegistered
local function EnsureOptionsPanel()
    if optionsPanel then
        return optionsPanel
    end
    local panel = CreateFrame("Frame", "LoadoutLockerOptionsPanel")
    panel.name = "LoadoutLocker"
    panel:SetScript("OnShow", function()
        C_Timer.After(0, function()
            if SettingsPanel and SettingsPanel:IsShown() then
                HideUIPanel(SettingsPanel)
            end
            Menu.Show()
        end)
    end)
    optionsPanel = panel
    return panel
end
function Menu.RegisterWithSettings()
    if optionsRegistered then
        return
    end
    if not Settings or not Settings.RegisterCanvasLayoutCategory then
        return
    end
    local panel = EnsureOptionsPanel()
    optionsCategory = Settings.RegisterCanvasLayoutCategory(panel, "LoadoutLocker")
    optionsCategory.ID = "LoadoutLocker"
    Settings.RegisterAddOnCategory(optionsCategory)
    optionsRegistered = true
end
