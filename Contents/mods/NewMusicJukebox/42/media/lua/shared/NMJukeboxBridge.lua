--[[
  NewMusicJukebox bridge v1.2.0
  Lets True Music Jukebox play New Music catalog media (NMTrackCatalog).
  Requires: NewMusic, TrueMusicJukebox (load this mod after both).

  Multi-track albums/mixtapes are expanded into virtual playlist entries
  (NMJ#ItemType#N) so every song appears in the jukebox list and Random/skip
  work per-song — including large mixtapes (100+ tracks).
]]

NMJukeboxBridge = NMJukeboxBridge or {}
NMJukeboxBridge._installed = false

local function log(msg)
    print("[NewMusicJukebox] " .. tostring(msg))
end

local function ensureCatalog()
    if type(NMTrackCatalog) ~= "table" then
        pcall(function() require("NMTrackCatalog") end)
    end
    return type(NMTrackCatalog) == "table" and type(NMTrackCatalog.resolveTracks) == "function"
end

-- Virtual playlist keys: "NMJ#" .. itemType .. "#" .. trackIndex
function NMJukeboxBridge.encodeVirtualTrack(itemType, nmIndex)
    return "NMJ#" .. tostring(itemType) .. "#" .. tostring(math.floor(tonumber(nmIndex) or 1))
end

function NMJukeboxBridge.parseVirtualTrack(trackType)
    local s = tostring(trackType or "")
    if string.sub(s, 1, 4) ~= "NMJ#" then
        return nil, nil
    end
    local rest = string.sub(s, 5)
    local last = nil
    local i = 0
    while true do
        local p = string.find(rest, "#", i + 1, true)
        if not p then break end
        last = p
        i = p
    end
    if not last then return nil, nil end
    local itemType = string.sub(rest, 1, last - 1)
    local idx = tonumber(string.sub(rest, last + 1))
    if itemType ~= "" and idx and idx >= 1 then
        return itemType, math.floor(idx)
    end
    return nil, nil
end

function NMJukeboxBridge.baseItemType(trackType)
    local base = NMJukeboxBridge.parseVirtualTrack(trackType)
    if base then return base end
    return trackType and tostring(trackType) or nil
end

local function getJukeboxTable()
    if type(Jukebox) == "table" and type(Jukebox.getSoundFile) == "function" then
        return Jukebox
    end
    -- Prefer already-loaded module
    if package and package.loaded then
        for _, key in ipairs({ "Jukebox/Utility", "Jukebox\\Utility" }) do
            local mod = package.loaded[key]
            if type(mod) == "table" and type(mod.getSoundFile) == "function" then
                return mod
            end
        end
    end
    -- Safe late require (Objects stub is provided by this mod)
    local ok, mod = pcall(function() return require("Jukebox/Utility") end)
    if ok and type(mod) == "table" and type(mod.getSoundFile) == "function" then
        return mod
    end
    return nil
end

local function getJukeboxSoundClass()
    if package and package.loaded then
        for _, key in ipairs({ "Jukebox/Sound", "Jukebox\\Sound" }) do
            local mod = package.loaded[key]
            if type(mod) == "table" and type(mod.play) == "function" then
                return mod
            end
        end
    end
    local ok, mod = pcall(function() return require("Jukebox/Sound") end)
    if ok and type(mod) == "table" then
        return mod
    end
    return nil
end

local function shortTypeOf(itemType)
    local key = tostring(itemType or "")
    local dot = string.find(key, ".", 1, true)
    if dot then
        return string.sub(key, dot + 1), key
    end
    return key, key
end

-- Child packs register catalog keys as Module.ItemType (e.g. newmusicmedkit.GuttedBleed...).
-- True Music Jukebox only passes item:getType() (short name). Map short -> full once.
local function buildShortIndex()
    if NMJukeboxBridge._shortIndex and NMJukeboxBridge._shortIndexBuiltFrom == NMTrackCatalog.entries then
        return NMJukeboxBridge._shortIndex
    end
    local index = {}
    local entries = NMTrackCatalog.entries
    if type(entries) == "table" then
        for fullKey, entry in pairs(entries) do
            if type(entry) == "table" and type(entry.tracks) == "table" and #entry.tracks > 0 then
                local short = shortTypeOf(fullKey)
                if short ~= "" and not index[short] then
                    index[short] = tostring(fullKey)
                end
            end
        end
    end
    NMJukeboxBridge._shortIndex = index
    NMJukeboxBridge._shortIndexBuiltFrom = entries
    return index
end

function NMJukeboxBridge.resolveEntry(itemType)
    if not itemType or itemType == "" or not ensureCatalog() then
        return nil
    end
    -- Virtual playlist entries encode base item type + song index
    local key = tostring(itemType)
    local vBase = NMJukeboxBridge.parseVirtualTrack(key)
    if vBase then
        key = vBase
    end

    local function ok(entry)
        return entry and type(entry.tracks) == "table" and #entry.tracks > 0 and entry or nil
    end

    local entry = ok(NMTrackCatalog.resolveTracks(key))
    if entry then return entry end

    -- Common base module
    if not string.find(key, ".", 1, true) then
        entry = ok(NMTrackCatalog.resolveTracks("NewMusic." .. key))
        if entry then return entry end
    end

    -- Pack modules (newmusicmedkit, MixtapeMegapackNewMusic, NMDaftPunk, KMBK*, ...)
    local short = shortTypeOf(key)
    if short ~= "" then
        local index = buildShortIndex()
        local fullKey = index[short]
        if fullKey then
            entry = ok(NMTrackCatalog.resolveTracks(fullKey))
            if entry then return entry end
        end
        -- Slow fallback if index missed (aliases / late register)
        local entries = NMTrackCatalog.entries
        if type(entries) == "table" then
            local suffix = "." .. short
            for fullKey2, e in pairs(entries) do
                local fk = tostring(fullKey2)
                if fk == short or string.sub(fk, -#suffix) == suffix then
                    entry = ok(e)
                    if entry then
                        index[short] = fk
                        return entry
                    end
                end
            end
        end
    end

    return nil
end

function NMJukeboxBridge.isNewMusicMediaType(itemType)
    return NMJukeboxBridge.resolveEntry(itemType) ~= nil
end

function NMJukeboxBridge.isNewMusicMediaItem(item)
    if not item or not item.getType then
        return false
    end
    if item.getFullType and ensureCatalog() then
        local full = tostring(item:getFullType() or "")
        if full ~= "" then
            local entry = NMTrackCatalog.resolveTracks(full)
            if entry and entry.tracks and #entry.tracks > 0 then
                return true
            end
        end
    end
    return NMJukeboxBridge.isNewMusicMediaType(item:getType())
end

function NMJukeboxBridge.resolvePlaySound(itemType, trackIndex)
    local vBase, vIdx = NMJukeboxBridge.parseVirtualTrack(itemType)
    local baseType = vBase or itemType
    local entry = NMJukeboxBridge.resolveEntry(baseType)
    if not entry then
        return nil
    end
    local idx = tonumber(trackIndex) or vIdx or 1
    if idx < 1 then idx = 1 end
    if idx > #entry.tracks then idx = #entry.tracks end
    local row = entry.tracks[idx]
    if not row or not row.sound or tostring(row.sound) == "" then
        return nil
    end
    return tostring(row.sound), entry, idx
end

function NMJukeboxBridge.getSoundFile(itemType)
    local vBase, vIdx = NMJukeboxBridge.parseVirtualTrack(itemType)
    local soundName = NMJukeboxBridge.resolvePlaySound(vBase or itemType, vIdx or 1)
    if not soundName then
        return nil
    end
    -- TMJ only needs a truthy "has audio" signal for playlist inclusion.
    if not GameSounds or not GameSounds.getSound then
        return true
    end
    local ok, file = pcall(function()
        local gs = GameSounds.getSound(soundName)
        if not gs then return nil end
        local clip = gs:getRandomClip()
        if not clip then
            -- Sound registered but clip not ready yet — still treat as playable
            return true
        end
        if clip.getFile then
            local path = clip:getFile()
            if path and tostring(path) ~= "" then
                return path
            end
        end
        return true
    end)
    if ok and file then return file end
    -- Catalog resolved: allow playlist even if GameSounds probe failed
    return true
end

local function titleFor(itemType, trackIndex, fallbackDisplayName)
    local soundName, entry, idx = NMJukeboxBridge.resolvePlaySound(itemType, trackIndex)
    if entry and entry.tracks and entry.tracks[idx] then
        local label = entry.tracks[idx].label
        if label and tostring(label) ~= "" then
            local text = tostring(label)
            if getTextOrNull then
                local t = getTextOrNull(text)
                if t and t ~= "" then return t end
            end
            if getText then
                local t = getText(text)
                if t and t ~= text then return t end
            end
            if string.sub(text, 1, 3) ~= "UI_" then
                return text
            end
        end
        if soundName then return soundName end
    end
    return fallbackDisplayName or tostring(itemType)
end

function NMJukeboxBridge.install()
    if NMJukeboxBridge._installed then
        return true
    end

    local J = getJukeboxTable()
    if not J then
        log("Jukebox API not ready")
        return false
    end

    if not ensureCatalog() then
        log("NMTrackCatalog not ready (will still wrap; catalog needed at play time)")
    end

    local oldPlayable = J.playableCassetteOrVinyl
    J.playableCassetteOrVinyl = function(item)
        if NMJukeboxBridge.isNewMusicMediaItem(item) then
            return true
        end
        if oldPlayable then return oldPlayable(item) end
        return false
    end

    local oldIsOrHas = J.isOrHasCassetteOrVinyl
    J.isOrHasCassetteOrVinyl = function(item)
        if NMJukeboxBridge.isNewMusicMediaItem(item) then
            return true
        end
        if oldIsOrHas then return oldIsOrHas(item) end
        return false
    end

    local oldGetSoundFile = J.getSoundFile
    J.getSoundFile = function(itemType)
        if NMJukeboxBridge.parseVirtualTrack(itemType) or NMJukeboxBridge.isNewMusicMediaType(itemType) then
            return NMJukeboxBridge.getSoundFile(itemType)
        end
        if oldGetSoundFile then return oldGetSoundFile(itemType) end
        return nil
    end

    local oldHasLoaded = J.hasLoaded
    if oldHasLoaded then
        J.hasLoaded = function(container, trackType)
            local base = NMJukeboxBridge.baseItemType(trackType) or trackType
            return oldHasLoaded(container, base)
        end
    end

    local oldInsertTrack = J.insertTrack
    if oldInsertTrack then
        J.insertTrack = function(jukeboxData, trackType, trackName, trackIndex)
            -- Already a virtual song entry — insert as-is with pretty title
            local vBase, vIdx = NMJukeboxBridge.parseVirtualTrack(trackType)
            if vBase then
                local pretty = titleFor(vBase, vIdx, trackName)
                return oldInsertTrack(jukeboxData, trackType, pretty, trackIndex)
            end

            if NMJukeboxBridge.isNewMusicMediaType(trackType) then
                local entry = NMJukeboxBridge.resolveEntry(trackType)
                if entry and entry.tracks and #entry.tracks > 1 then
                    -- Expand multi-track albums/mixtapes into one playlist row per song
                    -- so the jukebox list, skip, and Random all see every track.
                    local result
                    for i = 1, #entry.tracks do
                        local vType = NMJukeboxBridge.encodeVirtualTrack(trackType, i)
                        local pretty = titleFor(trackType, i, trackName)
                        -- Prefer "Album – Song" style for long mixtapes
                        if trackName and pretty and pretty ~= trackName then
                            local album = trackName
                            if J.prettyName then
                                album = J.prettyName(tostring(trackName)) or album
                            end
                            pretty = tostring(album) .. " – " .. tostring(pretty)
                        end
                        result = oldInsertTrack(jukeboxData, vType, pretty, trackIndex)
                    end
                    return result
                end
                local pretty = titleFor(trackType, 1, trackName)
                return oldInsertTrack(jukeboxData, trackType, pretty, trackIndex)
            end
            return oldInsertTrack(jukeboxData, trackType, trackName, trackIndex)
        end
    end

    -- TMJ skips rebuild when inventorySize already matches. Force rebuild when:
    --  * playlist empty despite NM media, or
    --  * multi-track media not yet expanded into virtual song rows.
    local oldInitPlaylist = J.initializePlaylist
    if oldInitPlaylist then
        J.initializePlaylist = function(jukebox, jukeboxData)
            if jukebox and jukeboxData and jukebox.getItemContainer then
                local container = jukebox:getItemContainer()
                local items = container and container.getItems and container:getItems()
                if items and items:size() > 0 then
                    local playlist = jukeboxData.playlist
                    local playlistEmpty = (not playlist) or (#playlist == 0)
                    local noPlayable = not jukeboxData.hasPlayableTracks
                    local needsExpand = false
                    for i = 0, items:size() - 1 do
                        local item = items:get(i)
                        if item and NMJukeboxBridge.isNewMusicMediaItem(item) then
                            if playlistEmpty or noPlayable then
                                jukeboxData.inventorySize = -1
                                break
                            end
                            local t = item:getType()
                            local entry = NMJukeboxBridge.resolveEntry(t)
                            if entry and entry.tracks and #entry.tracks > 1 then
                                local prefix = "NMJ#" .. tostring(t) .. "#"
                                local hasVirtual = false
                                if type(playlist) == "table" then
                                    for pi = 1, #playlist do
                                        local pt = playlist[pi]
                                        if type(pt) == "string" and string.sub(pt, 1, #prefix) == prefix then
                                            hasVirtual = true
                                            break
                                        end
                                    end
                                end
                                if not hasVirtual then
                                    needsExpand = true
                                    break
                                end
                            end
                        end
                    end
                    if needsExpand then
                        jukeboxData.inventorySize = -1
                    end
                end
            end
            return oldInitPlaylist(jukebox, jukeboxData)
        end
    end

    local JukeboxSound = getJukeboxSoundClass()
    if JukeboxSound and JukeboxSound.play then
        JukeboxSound.play = function(self, soundType)
            local resolved = soundType
            local baseType = soundType
            local vBase, vIdx = NMJukeboxBridge.parseVirtualTrack(soundType)
            if vBase then
                baseType = vBase
                self._nmTrackIndex = vIdx
            end
            if NMJukeboxBridge.isNewMusicMediaType(baseType) then
                local nmIndex = tonumber(self._nmTrackIndex)
                    or tonumber(NMJukeboxBridge._pendingNmIndex)
                    or 1
                self._nmTrackIndex = nmIndex
                local playName = NMJukeboxBridge.resolvePlaySound(baseType, nmIndex)
                if playName then
                    resolved = playName
                end
            end
            -- Keep inventory item type for hasLoaded (virtual keys are not item types)
            self.soundType = baseType
            if self.emitter then
                self:stop()
            elseif IsoWorld and IsoWorld.instance then
                if IsoWorld.instance:getFreeEmitter(self.x, self.y, self.z) then
                    self.emitter = IsoWorld.instance:getFreeEmitter(self.x, self.y, self.z)
                    self:stop()
                else
                    self.emitter = IsoWorld.instance:getFreeEmitter()
                    self:setPosition(self.x, self.y, self.z)
                end
            end
            if not self.emitter or not GameSounds then
                self.id = nil
                return
            end
            local newSound = GameSounds.getSound(resolved)
            if not newSound then
                log("Missing GameSound: " .. tostring(resolved) .. " (item " .. tostring(baseType) .. ")")
                self.id = nil
                return
            end
            local newClip = newSound:getRandomClip()
            if not newClip then
                self.id = nil
                return
            end
            self.id = self.emitter:playClip(newClip, nil)
            self.emitter:setVolume(self.id, self.volume or 0)
            self.emitter:set3D(self.id, self.sound3d == true)
            self.emitter:tick()
            self._nmResolvedSound = resolved
        end
    else
        log("WARN: could not wrap JukeboxSound.play")
    end

    local oldPlaySound = J.playSound
    if oldPlaySound then
        J.playSound = function(jukeboxData, trackType, playNow, beginMuted)
            NMJukeboxBridge._pendingNmIndex = nil
            local vBase, vIdx = NMJukeboxBridge.parseVirtualTrack(trackType)
            local baseType = vBase or trackType
            local entry = baseType and NMJukeboxBridge.resolveEntry(baseType) or nil
            if jukeboxData and entry and entry.tracks then
                local force = tonumber(jukeboxData._nmForceIndex) or vIdx
                if force and force >= 1 then
                    if force > #entry.tracks then force = #entry.tracks end
                    NMJukeboxBridge._pendingNmIndex = force
                    jukeboxData._nmForceIndex = nil
                end
            end

            local result = oldPlaySound(jukeboxData, trackType, playNow, beginMuted)
            NMJukeboxBridge._pendingNmIndex = nil

            if not (jukeboxData and trackType and J.dataToKey and J.activeTracks) then
                return result
            end
            entry = NMJukeboxBridge.resolveEntry(baseType)
            local key = J.dataToKey(jukeboxData)
            local active = key and J.activeTracks[key]
            if active and entry and entry.tracks then
                local idx = vIdx or 1
                if active.sound and active.sound._nmTrackIndex then
                    idx = tonumber(active.sound._nmTrackIndex) or idx
                end
                if idx < 1 then idx = 1 end
                if idx > #entry.tracks then idx = #entry.tracks end
                -- With expanded virtual playlist, each entry is one song — no sub-advance chain
                active.nmTracks = nil
                active.nmIndex = idx
                active.nmItemType = baseType
                if active.sound then
                    active.sound._nmTrackIndex = idx
                    active.sound.soundType = baseType
                end
                if jukeboxData.titles then
                    jukeboxData.titles[trackType] = titleFor(baseType, idx, jukeboxData.titles[trackType])
                end
            end
            return result
        end
    end

    -- Random: every playlist row is one pick (virtual songs already expanded).
    -- Also expand any legacy unexpanded multi-track media still in the list.
    local function buildSongPool(jukeboxData)
        local pool = {}
        if not jukeboxData then return pool end
        local useQueue = type(jukeboxData.queue) == "table" and #jukeboxData.queue > 0
        local source = useQueue and jukeboxData.queue or (jukeboxData.playlist or {})
        for i = 1, #source do
            local trackType = source[i]
            local vBase, vIdx = NMJukeboxBridge.parseVirtualTrack(trackType)
            if vBase then
                pool[#pool + 1] = {
                    index = i,
                    trackType = trackType,
                    nmIndex = vIdx,
                    useQueue = useQueue,
                    baseType = vBase,
                }
            else
                local entry = NMJukeboxBridge.resolveEntry(trackType)
                if entry and entry.tracks and #entry.tracks > 1 then
                    for ti = 1, #entry.tracks do
                        pool[#pool + 1] = {
                            index = i,
                            trackType = NMJukeboxBridge.encodeVirtualTrack(trackType, ti),
                            nmIndex = ti,
                            useQueue = useQueue,
                            baseType = trackType,
                            legacyExpand = true,
                        }
                    end
                else
                    pool[#pool + 1] = {
                        index = i,
                        trackType = trackType,
                        nmIndex = 1,
                        useQueue = useQueue,
                        baseType = trackType,
                    }
                end
            end
        end
        return pool
    end

    local function handleRandom(player, jukebox, key)
        local jukeboxData = J.activeLocations and J.activeLocations[key]
        if not jukeboxData then return false end

        if J.activeTracks and J.activeTracks[key] and J.activeTracks[key].elapsed
            and J.activeTracks[key].elapsed < 10 then
            if J.reportMessage and J.translation and J.translation.movingTooFast then
                J.reportMessage(player, J.translation.movingTooFast)
            end
            return true
        end

        local pool = buildSongPool(jukeboxData)
        if #pool < 1 then return false end

        local currentType = nil
        if J.getCurrentTrack then
            pcall(function() currentType = J.getCurrentTrack(jukeboxData) end)
        end

        local pick = pool[1]
        local rand = J.random or function(max)
            if max < 1 then return 1 end
            return ZombRand(max) + 1
        end
        if #pool == 1 then
            pick = pool[1]
        else
            for _ = 1, 12 do
                pick = pool[rand(#pool)]
                if pick.trackType ~= currentType then
                    break
                end
            end
        end

        jukeboxData._nmForceIndex = pick.nmIndex

        local pretty = jukeboxData.titles and jukeboxData.titles[pick.trackType]
        if not pretty then
            pretty = titleFor(pick.baseType or pick.trackType, pick.nmIndex, pick.trackType)
        end
        if J.reportMessage and J.translation then
            local prefix = J.translation.randomlySelected or "Randomly selected: "
            local suffix = J.translation.trackWillPlayNow or ""
            J.reportMessage(player, prefix .. tostring(pretty) .. ". " .. tostring(suffix))
        end

        -- Prefer playlist index of the chosen virtual row (works for large mixtapes).
        local tracklistIndex = pick.useQueue and "queueIndex" or "playlistIndex"
        local syncIndex = pick.index
        if pick.legacyExpand then
            -- Legacy single media row: force sub-index; stay on that playlist slot
            syncIndex = pick.index
        end

        sendClientCommand("TrueMusicJukebox", "sync", {
            key = key,
            [tracklistIndex] = syncIndex,
            _nmForceIndex = pick.nmIndex,
            afterSync = "skip",
        })
        return true
    end

    local function wrapMenusRandom()
        local ok, Menus = pcall(function() return require("Jukebox/Menu") end)
        if not ok or type(Menus) ~= "table" or type(Menus.interact) ~= "function" then
            return false
        end
        if Menus._nmjRandomWrapped then return true end
        local oldInteract = Menus.interact
        Menus.interact = function(player, jukebox, key, musicChoice, selectedTrack)
            if musicChoice == "Random" then
                local handled = false
                pcall(function()
                    handled = handleRandom(player, jukebox, key) == true
                end)
                if handled then return end
            end
            return oldInteract(player, jukebox, key, musicChoice, selectedTrack)
        end
        -- Eject must use base item type (virtual keys are not inventory types)
        if type(Menus.ejectTrack) == "function" and not Menus._nmjEjectWrapped then
            local oldEject = Menus.ejectTrack
            Menus.ejectTrack = function(jukebox, player, jukeboxData, trackType)
                local base = NMJukeboxBridge.baseItemType(trackType) or trackType
                return oldEject(jukebox, player, jukeboxData, base)
            end
            Menus._nmjEjectWrapped = true
        end
        Menus._nmjRandomWrapped = true
        return true
    end

    if not wrapMenusRandom() then
        log("WARN: could not wrap Random yet (will retry on tick)")
        if Events.OnTick then
            local n = 0
            local function tickMenus()
                n = n + 1
                if wrapMenusRandom() or n >= 120 then
                    Events.OnTick.Remove(tickMenus)
                end
            end
            Events.OnTick.Add(tickMenus)
        end
    end

    if not isServer() and J.updateSound then
        local oldUpdateSound = J.updateSound
        J.updateSound = function()
            -- Legacy path: unexpanded multi-track media (nmTracks set). Advance song and
            -- block TMJ auto-skip for the same tick so it cannot restart song 1.
            if type(J.activeTracks) == "table" and type(J.activeLocations) == "table" then
                for key, active in pairs(J.activeTracks) do
                    if type(active) == "table" and active.nmTracks and active.sound and active.nmItemType then
                        local sound = active.sound
                        local playing = false
                        pcall(function()
                            playing = sound:isPlaying() == true
                        end)
                        if playing and active.nmHoldSkip then
                            active.nmHoldSkip = nil
                            sound.changing = false
                        elseif (not playing) and not sound.changing and active.elapsed and active.elapsed > 9 then
                            local idx = tonumber(active.nmIndex) or 1
                            local tracks = active.nmTracks
                            if type(tracks) == "table" and idx < #tracks then
                                active.nmIndex = idx + 1
                                sound._nmTrackIndex = active.nmIndex
                                local jukeboxData = J.activeLocations[key]
                                if jukeboxData then
                                    pcall(function()
                                        sound:play(active.nmItemType)
                                    end)
                                    active.elapsed = 0
                                    -- Prevent stock TMJ from skipping playlist while we advance album songs
                                    sound.changing = true
                                    active.nmHoldSkip = true
                                    if jukeboxData.titles then
                                        jukeboxData.titles[active.nmItemType] =
                                            titleFor(active.nmItemType, active.nmIndex, jukeboxData.titles[active.nmItemType])
                                    end
                                end
                            end
                        elseif (not playing) and active.nmHoldSkip and active.elapsed and active.elapsed > 60 then
                            -- Safety: don't block forever if next clip failed to start
                            active.nmHoldSkip = nil
                            sound.changing = false
                        end
                    end
                end
            end
            return oldUpdateSound()
        end
    end

    -- TMJ's stock Status Report only print()s raw fields to console.txt.
    -- Replace with a readable in-game report (modal + short Say line).
    local function volumeLabel(jukeboxData)
        local vol = tonumber(jukeboxData and jukeboxData.volume) or 0
        local step = (J.volumesIndex and J.volumesIndex[vol]) or nil
        local pct = math.floor(vol * 100 + 0.5)
        if step then
            return string.format("%d%% (level %d/12)", pct, step)
        end
        return string.format("%d%%", pct)
    end

    local function trackTitle(jukeboxData, trackType)
        if not trackType then return nil end
        if jukeboxData.titles and jukeboxData.titles[trackType] then
            return tostring(jukeboxData.titles[trackType])
        end
        if J.prettyName then
            return J.prettyName(tostring(trackType))
        end
        return tostring(trackType)
    end

    local function buildStatusLines(jukeboxData)
        local lines = {}
        local function add(s)
            lines[#lines + 1] = tostring(s)
        end

        if not jukeboxData then
            add("No jukebox data available.")
            return lines
        end

        add("JUKEBOX STATUS")
        add(string.format("Location: %s, %s, %s",
            tostring(jukeboxData.x), tostring(jukeboxData.y), tostring(jukeboxData.z)))
        add("Power: " .. ((jukeboxData.on and "On") or "Off"))
        add("Volume: " .. volumeLabel(jukeboxData))
        add("Playable media: " .. ((jukeboxData.hasPlayableTracks and "Yes") or "No"))

        local playlist = jukeboxData.playlist or {}
        local queue = jukeboxData.queue
        local playlistCount = #playlist
        local queueCount = (type(queue) == "table" and #queue) or 0
        add(string.format("Playlist: %d track(s)", playlistCount))
        if queueCount > 0 then
            add(string.format("Queue: %d track(s)%s",
                queueCount, jukeboxData.queueLocked and " (locked)" or ""))
        end

        local currentType = nil
        if J.getCurrentTrack then
            pcall(function() currentType = J.getCurrentTrack(jukeboxData) end)
        end
        local currentName = trackTitle(jukeboxData, currentType)
        if not currentName and J.getCurrentTitle then
            pcall(function() currentName = J.getCurrentTitle(jukeboxData) end)
        end
        add("Selected: " .. tostring(currentName or "None"))

        if currentType then
            local entry = NMJukeboxBridge.resolveEntry(currentType)
            if entry and entry.tracks then
                local nmIdx = 1
                if J.dataToKey and J.activeTracks then
                    local key = J.dataToKey(jukeboxData)
                    local active = key and J.activeTracks[key]
                    if active and active.nmIndex then
                        nmIdx = tonumber(active.nmIndex) or 1
                    end
                end
                add(string.format("New Music album: song %d of %d", nmIdx, #entry.tracks))
                local songLabel = titleFor(currentType, nmIdx, nil)
                if songLabel and songLabel ~= "" then
                    add("  Now: " .. songLabel)
                end
            end
        end

        if playlistCount > 0 then
            add("")
            add("Playlist contents:")
            local maxShow = 15
            local idx = tonumber(jukeboxData.playlistIndex) or 0
            for i = 1, math.min(playlistCount, maxShow) do
                local t = playlist[i]
                local mark = (i == idx) and ">" or " "
                add(string.format("%s %d. %s", mark, i, trackTitle(jukeboxData, t) or tostring(t)))
            end
            if playlistCount > maxShow then
                add(string.format("  ... +%d more", playlistCount - maxShow))
            end
        end

        if queueCount > 0 then
            add("")
            add("Queue contents:")
            local maxQ = 10
            local qIdx = tonumber(jukeboxData.queueIndex) or 0
            for i = 1, math.min(queueCount, maxQ) do
                local t = queue[i]
                local mark = (i == qIdx) and ">" or " "
                add(string.format("%s %d. %s", mark, i, trackTitle(jukeboxData, t) or tostring(t)))
            end
            if queueCount > maxQ then
                add(string.format("  ... +%d more", queueCount - maxQ))
            end
        end

        return lines
    end

    local function showStatusModal(text)
        if type(ISModalRichText) ~= "table" or type(ISModalRichText.new) ~= "function" then
            return false
        end
        local ok, err = pcall(function()
            local w, h = 460, 320
            local x = (getCore():getScreenWidth() - w) / 2
            local y = (getCore():getScreenHeight() - h) / 2
            local modal = ISModalRichText:new(x, y, w, h, text, false, nil, nil, nil)
            modal:initialise()
            modal:addToUIManager()
            if modal.setHeightToContents then
                modal:setHeightToContents()
            end
        end)
        if not ok then
            log("Status modal failed: " .. tostring(err))
            return false
        end
        return true
    end

    J.printStatus = function(player, jukeboxData)
        local lines = buildStatusLines(jukeboxData)
        local plain = table.concat(lines, "\n")
        local rich = table.concat(lines, " <LINE> ")

        -- Clean single log block (not the old field-by-field spam)
        print("[TrueMusicJukebox] Status Report\n" .. plain)

        local shown = showStatusModal(rich)
        if not shown and J.reportMessage and player then
            -- Fallback: short spoken lines if modal unavailable
            local summary = {}
            for i = 1, math.min(#lines, 6) do
                summary[#summary + 1] = lines[i]
            end
            J.reportMessage(player, table.concat(summary, " | "))
        elseif J.reportMessage and player then
            local current = "None"
            if J.getCurrentTitle then
                pcall(function() current = J.getCurrentTitle(jukeboxData) or "None" end)
            end
            J.reportMessage(player, "Jukebox status open. Selected: " .. tostring(current))
        end
    end

    if type(Jukebox) ~= "table" then
        Jukebox = J
    end

    NMJukeboxBridge._installed = true
    log("Bridge installed OK")
    return true
end

local function tryInstall()
    if NMJukeboxBridge._installed then
        return
    end
    local ok, err = pcall(function()
        NMJukeboxBridge.install()
    end)
    if not ok then
        log("install error: " .. tostring(err))
    elseif not NMJukeboxBridge._installed then
        log("install deferred (Jukebox not ready yet)")
    end
end

-- Install after world/scripts are up; retry a few times
Events.OnGameStart.Add(function()
    tryInstall()
    if NMJukeboxBridge._installed or not Events.OnTick then
        return
    end
    local n = 0
    local function tick()
        n = n + 1
        tryInstall()
        if NMJukeboxBridge._installed or n >= 300 then
            Events.OnTick.Remove(tick)
            if not NMJukeboxBridge._installed then
                log("FAILED to install after retries — playlist will stay empty for New Music media")
            end
        end
    end
    Events.OnTick.Add(tick)
end)

-- Do NOT install on OnMainMenuEnter: exit-to-menu reloads Lua while APIs
-- are half torn down; re-require/wrap there can contribute to black screens.
