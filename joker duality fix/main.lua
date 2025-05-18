local mod = RegisterMod('Joker Duality Fix', 1)
local json = require('json')
local game = Game()

if REPENTOGON then
  mod.onGameStartHasRun = false
  mod.stateAngelRoomSpawned = nil
  mod.stateDevilRoomSpawned = nil
  
  mod.state = {}
  mod.state.handleNewRoom = false
  mod.state.maybeHandleNewRoom = false -- glowing hourglass
  mod.state.previousRoomIdx = -1 -- don't get stuck in an infinite loop off the map
  
  function mod:localize(category, key)
    local s = Isaac.GetString(category, key)
    return (s == nil or s == 'StringTable::InvalidCategory' or s == 'StringTable::InvalidKey') and key or s
  end
  
  function mod:onGameStart(isContinue)
    if isContinue and mod:HasData() then
      local _, state = pcall(json.decode, mod:LoadData())
      
      if type(state) == 'table' then
        for _, v in ipairs({ 'handleNewRoom', 'maybeHandleNewRoom' }) do
          if type(state[v]) == 'boolean' then
            mod.state[v] = state[v] -- stage api can break this on continue
          end
        end
        if math.type(state.previousRoomIdx) == 'integer' and state.previousRoomIdx >= 0 then
          mod.state.previousRoomIdx = state.previousRoomIdx
        end
      end
    end
    
    mod.onGameStartHasRun = true
    mod:onNewRoom()
  end
  
  function mod:onGameExit(shouldSave)
    if shouldSave then
      mod:SaveData(json.encode(mod.state))
      mod.state.maybeHandleNewRoom = false
      mod.state.handleNewRoom = false
      mod.state.previousRoomIdx = -1
    else
      mod.state.previousRoomIdx = -1
      mod.state.handleNewRoom = false
      mod.state.maybeHandleNewRoom = false
      mod:SaveData(json.encode(mod.state))
    end
    
    mod.onGameStartHasRun = false
    mod.stateAngelRoomSpawned = nil
    mod.stateDevilRoomSpawned = nil
  end
  
  function mod:onNewRoom()
    if not mod.onGameStartHasRun then
      return
    end
    
    local hud = game:GetHUD()
    local level = game:GetLevel()
    local room = level:GetCurrentRoom()
    local roomDesc = level:GetCurrentRoomDesc()
    
    if mod.state.handleNewRoom and roomDesc.GridIndex == GridRooms.ROOM_DEBUG_IDX and room:GetType() == RoomType.ROOM_ANGEL then
      mod:clearRoom()
      mod:centerPlayers()
      mod:updateRoomColors()
      mod:spawnDevilRoomDoor()
      hud:ShowItemText(mod:localize('Items', '#DUALITY_NAME'), mod:localize('Items', '#DUALITY_DESCRIPTION'), false)
      room:Update() -- looks better when continuing
      
      mod.state.maybeHandleNewRoom = false
      mod.stateAngelRoomSpawned = game:GetStateFlag(GameStateFlag.STATE_FAMINE_SPAWNED) -- repurposed
      mod.stateDevilRoomSpawned = game:GetStateFlag(GameStateFlag.STATE_DEVILROOM_SPAWNED)
    else
      if roomDesc.GridIndex == GridRooms.ROOM_DEVIL_IDX and (room:GetType() == RoomType.ROOM_DEVIL or room:GetType() == RoomType.ROOM_ANGEL) and
         level:GetPreviousRoomIndex() == GridRooms.ROOM_DEBUG_IDX
      then
        if mod.state.handleNewRoom then
          if mod.stateAngelRoomSpawned ~= nil then
            game:SetStateFlag(GameStateFlag.STATE_FAMINE_SPAWNED, mod.stateAngelRoomSpawned) -- reset state (normal joker behavior)
          end
          if mod.stateDevilRoomSpawned ~= nil then
            game:SetStateFlag(GameStateFlag.STATE_DEVILROOM_SPAWNED, mod.stateDevilRoomSpawned)
          end
        end
        
        mod.state.maybeHandleNewRoom = mod.state.handleNewRoom -- glowing hourglass doesn't work on continue
        mod:fixDevilRoomDoors() -- support fixing doors on continue
      else
        mod.state.maybeHandleNewRoom = false
      end
      
      mod.state.handleNewRoom = false
      mod.stateAngelRoomSpawned = nil
      mod.stateDevilRoomSpawned = nil
    end
    
    if level:GetPreviousRoomIndex() >= 0 then
      mod.state.previousRoomIdx = level:GetPreviousRoomIndex()
    end
  end
  
  -- filtered to CARD_JOKER
  -- tarot cloth doesn't seem to call this twice
  function mod:onPreUseCard(card, player, useFlags)
    if mod:hasDuality() and not mod:devilRoomSpawned() then
      mod:gotoDebugRoom(player)
      return true
    end
  end
  
  -- filtered to COLLECTIBLE_TELEPORT_2
  -- includes broken remote synergy
  -- car battery calls this twice, but that's ok
  function mod:onPreUseItem(collectible, rng, player, useFlags, slot, varData)
    if mod:hasDuality() and not mod:devilRoomSpawned() and mod:willTeleport2DevilRoom() then
      mod:gotoDebugRoom(player)
      return true
    end
  end
  
  -- filtered to COLLECTIBLE_GLOWING_HOUR_GLASS
  -- car battery has no effect
  -- this doesn't support rewind or game:StartRoomTransition w/ GLOWING_HOURGLASS anim
  function mod:onUseItem(collectible, rng, player, useFlags, slot, varData)
    local level = game:GetLevel()
    local room = level:GetCurrentRoom()
    local roomDesc = level:GetCurrentRoomDesc()
    
    if roomDesc.GridIndex == GridRooms.ROOM_DEVIL_IDX and (room:GetType() == RoomType.ROOM_DEVIL or room:GetType() == RoomType.ROOM_ANGEL) and
       mod.state.maybeHandleNewRoom and level:GetPreviousRoomIndex() == GridRooms.ROOM_DEBUG_IDX
    then
      local actualVarData = 0
      if useFlags & UseFlag.USE_CUSTOMVARDATA == UseFlag.USE_CUSTOMVARDATA then
        actualVarData = varData
      elseif useFlags & UseFlag.USE_OWNED == UseFlag.USE_OWNED and slot >= ActiveSlot.SLOT_PRIMARY and slot <= ActiveSlot.SLOT_POCKET2 then
        local itemDesc = player:GetActiveItemDesc(slot)
        if itemDesc and itemDesc.Item == collectible then
          actualVarData = itemDesc.VarData
        end
      end
      
      if actualVarData < 3 then -- at 3 acts like a regular hourglass
        mod.state.handleNewRoom = true
      end
    end
  end
  
  -- filtered to PICKUP_REDCHEST
  function mod:onPrePickupCollision(pickup, collider, low)
    if collider.Type == EntityType.ENTITY_PLAYER and pickup.SubType == ChestSubType.CHEST_CLOSED then
      local player = collider:ToPlayer()
      local isBaby = player:GetBabySkin() ~= BabySubType.BABY_UNASSIGNED
      if not isBaby and mod:hasDuality() and not mod:devilRoomSpawned() and mod:willChestTeleportToDevilRoom(pickup) then
        pickup.SubType = ChestSubType.CHEST_OPENED
        mod:gotoDebugRoom(player)
        return true
      end
    end
  end
  
  function mod:gotoDebugRoom(player)
    -- reset debug room flags (just in case)
    local level = game:GetLevel()
    local dbgRoom = level:GetRoomByIdx(GridRooms.ROOM_DEBUG_IDX, Dimension.CURRENT)
    dbgRoom.Flags = RoomDescriptor.FLAG_NO_REWARD -- FLAG_RED_ROOM
    
    Isaac.ExecuteCommand('goto s.angel') -- angel over devil so we don't trigger STATE_DEVILROOM_VISITED
    game:StartRoomTransition(GridRooms.ROOM_DEBUG_IDX, Direction.NO_DIRECTION, RoomTransitionAnim.TELEPORT, player, Dimension.CURRENT)
    mod.state.handleNewRoom = true
  end
  
  function mod:spawnDevilRoomDoor()
    local room = game:GetRoom()
    local lastDevilRoomStage = game:GetLastDevilRoomStage()
    room:TrySpawnDevilRoomDoor(false, true)        -- no animation/sound if we're displaying text
    game:SetLastDevilRoomStage(lastDevilRoomStage) -- reset last devil room stage (normal joker behavior)
  end
  
  -- mimic red room colors
  function mod:updateRoomColors()
    local room = game:GetRoom()
    room:SetFloorColor(Color(1, 1, 1, 1, 0, 0, 0, 1, 0, 0, 0.3))
    room:SetWallColor(Color(1, 1, 1, 1, 0, 0, 0, 1, 0.2, 0.2, 0.8))
  end
  
  function mod:centerPlayers()
    local room = game:GetRoom()
    
    for _, player in ipairs(PlayerManager.GetPlayers()) do
      player.Position = room:GetCenterPos()
    end
  end
  
  function mod:clearRoom()
    local room = game:GetRoom()
    
    for i = 0, room:GetGridSize() - 1 do
      local gridEntity = room:GetGridEntity(i)
      if gridEntity and
         gridEntity:GetType() ~= GridEntityType.GRID_DECORATION and
         gridEntity:GetType() ~= GridEntityType.GRID_WALL and
         gridEntity:GetType() ~= GridEntityType.GRID_DOOR
      then
        room:RemoveGridEntityImmediate(i, 0, false)
      end
    end
    
    for i = 0, DoorSlot.NUM_DOOR_SLOTS - 1 do
      room:RemoveDoor(i)
    end
    
    for _, entity in ipairs(Isaac.GetRoomEntities()) do
      if entity.Type == EntityType.ENTITY_PICKUP or
         entity.Type == EntityType.ENTITY_SLOT or
         (entity.Type == EntityType.ENTITY_EFFECT and (entity.Variant == EffectVariant.DEVIL or entity.Variant == EffectVariant.ANGEL)) or
         entity:CanShutDoors() or
         entity:IsEnemy()
      then
        entity:Remove()
      end
    end
  end
  
  function mod:fixDevilRoomDoors()
    local room = game:GetRoom()
    
    if mod.state.previousRoomIdx >= 0 then
      for i = 0, DoorSlot.NUM_DOOR_SLOTS - 1 do
        local door = room:GetDoor(i)
        if door and door.TargetRoomIndex == GridRooms.ROOM_DEBUG_IDX then
          door.TargetRoomIndex = mod.state.previousRoomIdx
        end
      end
    end
  end
  
  function mod:willTeleport2DevilRoom()
    local isGreedMode = game:IsGreedMode()
    local level = game:GetLevel()
    local stage = level:GetStage()
    local stageType = level:GetStageType()
    local room = level:GetCurrentRoom()
    local rooms = level:GetRooms() -- rooms on the map
    local dimension = level:GetDimension()
    
    if not isGreedMode and stage == LevelStage.STAGE8 then
      local roomDesc = level:GetCurrentRoomDesc()
      if roomDesc.Data.Type == RoomType.ROOM_DUNGEON and roomDesc.Data.Subtype == RoomSubType.CRAWLSPACE_BEAST then
        return false -- the beast
      end
    end
    
    for i = 0, #rooms - 1 do
      local roomDesc = rooms:Get(i)
      -- when you kill mausoleum heart, it sets clear=true for all non-ultrasecret rooms
      if not roomDesc.Clear and roomDesc:GetDimension() == dimension and roomDesc.GridIndex >= 0 and roomDesc.Data then
        if room:IsMirrorWorld() or roomDesc.Data.Type ~= RoomType.ROOM_ULTRASECRET then -- Dimension.MIRROR
          return false
        end
      end
    end
    
    local devilRoom = level:GetRoomByIdx(GridRooms.ROOM_DEVIL_IDX, Dimension.CURRENT)
    if not devilRoom.Clear then
      return true
    end
    
    local challengeEndStage = game:GetChallengeParams():GetEndStage()
    if challengeEndStage == LevelStage.STAGE_NULL then
      challengeEndStage = DailyChallenge.GetChallengeParams():GetEndStage()
    end
    if challengeEndStage ~= LevelStage.STAGE_NULL and stage >= challengeEndStage then -- the game doesn't account for xl floors
      -- no fallback to i am error room
      return true
    end
    
    if isGreedMode then
      if stage == LevelStage.STAGE7_GREED then -- ultra greed
        return true
      end
    else
      if level:IsPreAscent() or -- STAGE3_2 and STAGETYPE_REPENTANCE / STAGETYPE_REPENTANCE_B
         (stage == LevelStage.STAGE4_2 and (stageType == StageType.STAGETYPE_REPENTANCE or stageType == StageType.STAGETYPE_REPENTANCE_B)) or -- corpse ii (not xl)
         stage == LevelStage.STAGE6 or -- dark room / chest
         stage == LevelStage.STAGE7 or -- the void
         stage == LevelStage.STAGE8    -- home
      then
        return true
      end
    end
    
    -- fallback to i am error room
    return false
  end
  
  function mod:willChestTeleportToDevilRoom(chest)
    for _, lootListEntry in ipairs(chest:GetLootList():GetEntries()) do
      -- you can have other items in the chest with this
      -- variants other than 1 will crash the game
      if lootListEntry:GetType() == EntityType.ENTITY_NULL and lootListEntry:GetVariant() == 1 then
        return true
      end
    end
    
    return false
  end
  
  function mod:hasDuality()
    return PlayerManager.AnyoneHasCollectible(CollectibleType.COLLECTIBLE_DUALITY)
  end
  
  function mod:devilRoomSpawned()
    local level = game:GetLevel()
    local devilRoom = level:GetRoomByIdx(GridRooms.ROOM_DEVIL_IDX, Dimension.CURRENT)
    return devilRoom.Data ~= nil
  end
  
  mod:AddCallback(ModCallbacks.MC_POST_GAME_STARTED, mod.onGameStart)
  mod:AddCallback(ModCallbacks.MC_PRE_GAME_EXIT, mod.onGameExit)
  mod:AddCallback(ModCallbacks.MC_POST_NEW_ROOM, mod.onNewRoom)
  mod:AddCallback(ModCallbacks.MC_PRE_USE_CARD, mod.onPreUseCard, Card.CARD_JOKER)
  mod:AddCallback(ModCallbacks.MC_PRE_USE_ITEM, mod.onPreUseItem, CollectibleType.COLLECTIBLE_TELEPORT_2)
  mod:AddCallback(ModCallbacks.MC_USE_ITEM, mod.onUseItem, CollectibleType.COLLECTIBLE_GLOWING_HOUR_GLASS)
  mod:AddCallback(ModCallbacks.MC_PRE_PICKUP_COLLISION, mod.onPrePickupCollision, PickupVariant.PICKUP_REDCHEST)
  -- technically, the following chest types can also teleport you to a devil room, but they don't seem to appear naturally in the game
  -- PICKUP_CHEST, PICKUP_SPIKEDCHEST, PICKUP_MIMICCHEST, PICKUP_OLDCHEST, PICKUP_WOODENCHEST, PICKUP_MOMSCHEST
  -- PICKUP_ETERNALCHEST, PICKUP_MEGACHEST, PICKUP_LOCKEDCHEST : would likely need additional key checking
  -- PICKUP_BOMBCHEST, PICKUP_HAUNTEDCHEST : would likely need different callbacks
end