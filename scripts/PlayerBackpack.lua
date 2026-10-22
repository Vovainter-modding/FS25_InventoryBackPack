-- InventoryBackPack for Multiplayer, Vovainter.
-- Personal, persistent inventories on dedicated multiplayer servers.
PlayerBackpack = {
    slots={}, serverBags={}, objectOwners={}, selected=1, visible=false,
    actionId=nil, yActionId=nil, logged=false, debugReady=false,
    debugInput=false, cameraState=nil, oldFreeze=nil, iconCache={},
    inputState=nil
}
local PB=PlayerBackpack
-- Capture directory at source load: g_currentModDirectory can change during loadMap.
PB.MOD_DIRECTORY = g_currentModDirectory
local function player()
    return g_localPlayer or (g_currentMission and g_currentMission.player)
end
-- Dedicated server can expose g_client as part of its networking machinery.
-- The only reliable UI target for this mod is a real local gameplay player.
local function localGameplayPlayer()
    if g_dedicatedServer ~= nil then return nil end
    if g_gui == nil or g_localPlayer == nil then return nil end
    return g_localPlayer
end
local function canUse()
    local p=localGameplayPlayer()
    if p==nil or g_currentMission==nil then return false end
    if p.getIsInVehicle~=nil and p:getIsInVehicle() then return false end
    return true
end
local function notice(s)
    if g_currentMission and g_currentMission.showBlinkingWarning then g_currentMission:showBlinkingWarning(s,2600) end
end
-- Physical objects are carried by HandToolHands, not by ordinary hand tools.
local function hands()
    local p=player()
    if not p then return nil end
    local tool = p.getHeldHandTool and p:getHeldHandTool() or nil
    if tool and tool.spec_hands then return tool end
    tool = p.currentHandTool or p.handTool
    if tool and tool.spec_hands then return tool end
    if p.handTools then
        for _,v in pairs(p.handTools) do
            if v and v.spec_hands and v.getIsHoldingItem then return v end
        end
    end
    return nil
end
local function heldNode()
    local h=hands()
    if h and h.getIsHoldingItem and h:getIsHoldingItem() then
        return h:getHeldItem(),h
    end
    return nil,h
end
local function aimedNode()
    local p=player()
    if not p or not p.targeter or not p.targeter.closestTargetsByKey or not HandToolHands then return nil end
    local target=p.targeter.closestTargetsByKey[HandToolHands]
    return target and target.node or nil
end
-- SAFETY: normal FS25 vehicles also implement getCanBePickedUp(), but most
-- return false. Checking only for the presence of this method lets Y put an
-- entire truck into the backpack. A portable item must have the explicit
-- pickup flag AND must not be a drivable vehicle or an implement.
-- Keep this separate from the player's access check so it can also be used
-- when restoring savegame inventories whose owners may be offline.
local function isPortableClass(obj)
    if obj == nil or obj.rootNode == nil or obj.isPlaceable or obj.spec_hands ~= nil then return false end
    if obj.supportsPickUp ~= true or type(obj.getCanBePickedUp) ~= "function" then return false end

    -- The engine models ADS consumables and other hand-held products as
    -- Vehicle objects as well. Do NOT reject all Vehicle instances: reject
    -- only real machinery and components designed to be attached to it.
    if obj.spec_motorized ~= nil or obj.spec_enterable ~= nil
        or obj.spec_drivable ~= nil or obj.spec_wheels ~= nil
        or obj.spec_trailer ~= nil or obj.spec_attachable ~= nil
        or obj.spec_attacherJoints ~= nil or obj.spec_aiVehicle ~= nil
        or obj.spec_crawlers ~= nil then
        return false
    end
    if obj.dynamicMountObject ~= nil or obj.tensionMountObject ~= nil then return false end

    -- A second limit guards unusual modded machinery explicitly marked
    -- supportsPickUp=true. Vehicle mass is measured in tonnes (0.25 = 250 kg).
    if type(obj.getTotalMass) == "function" then
        local mass=obj:getTotalMass(true)
        if type(mass)=="number" and mass>0.25 then return false end
    end
    -- Reject oversized objects even if a mod mistakenly enables pickup.
    local size=type(obj.size)=="table" and obj.size or nil
    local w=obj.sizeWidth or (size and size.width)
    local l=obj.sizeLength or (size and size.length)
    local h=obj.sizeHeight or (size and size.height)
    if (type(w)=="number" and w>2.5) or (type(l)=="number" and l>2.5)
        or (type(h)=="number" and h>2.2) then return false end
    return true
end
PB.isSafePortableObject=isPortableClass

local function isPortable(obj, byPlayer)
    if not isPortableClass(obj) or byPlayer==nil then return false end
    if obj.getIsAIActive then
        if obj:getIsAIActive() then return false end
    end
    -- FS25 Vehicle:getCanBePickedUp(byPlayer) checks supportsPickUp and
    -- player access. The actual BOOL is essential, unlike previous builds.
    return obj:getCanBePickedUp(byPlayer) == true
end

local function getShopObject(node, byPlayer)
    if not node or node==0 or not entityExists(node) then return nil,nil end
    local obj=g_currentMission:getNodeObject(node)
    if not obj or not obj.rootNode or not entityExists(obj.rootNode) then return nil,nil end
    if not isPortable(obj,byPlayer) then return nil,nil end
    local filename=obj.configFileName or obj.xmlFilename
    local item=filename and g_storeManager and g_storeManager:getItemByXMLFilename(filename)
    if not item then return nil,nil end
    return obj,item
end
local function imagePath(item)
    local v=item.imageFilename or item.image
    if type(v)=='string' then return v end
    if type(v)=='table' then
        for _,key in ipairs({'filename','imageFilename','path','filenameSmall','store'}) do
            if type(v[key])=='string' then return v[key] end
        end
    end
    return nil
end
-- Resolve the active shop configuration labels (not their internal numeric IDs).
-- Quantity is chosen when buying multiple objects, not a characteristic of one object.
local function isQuantityConfiguration(key, title)
    local k=tostring(key or ""):lower()
    local t=tostring(title or ""):lower()
    return k=="quantity" or k=="amount" or k=="count" or k=="number" or k=="numitems"
        or k=="buyquantity" or k=="purchasequantity"
        or t=="количество" or t=="quantity" or t=="anzahl"
end
local function configurationLabels(obj, storeItem)
    local result={}
    if type(obj.configurations)~="table" or type(storeItem.configurations)~="table" then return result end
    local sorted={}
    for key, _ in pairs(obj.configurations) do
        if type(key)=="string" and storeItem.configurations[key]~=nil then table.insert(sorted,key) end
    end
    table.sort(sorted)
    for _,key in ipairs(sorted) do
        local selected=obj.configurations[key]
        local options=storeItem.configurations[key]
        local option=type(options)=="table" and (options[selected] or options[tonumber(selected)]) or nil
        if option==nil and type(options)=="table" then
            for _,candidate in pairs(options) do
                if type(candidate)=="table" and (candidate.saveId==selected or tostring(candidate.saveId)==tostring(selected)) then option=candidate;break end
            end
        end
        if type(option)=="table" then
            local value=option.name or option.title or option.desc
            if type(value)=="string" and value~="" then
                local label=key
                -- Legacy g_configurationManager is removed in FS25 1.24.
                -- The option value is enough for the carousel; do not read the old manager.
                -- StoreItem options carry the already localized shop display label.
                if not isQuantityConfiguration(key,label) then
                    table.insert(result,{label=tostring(label),value=value})
                end
            end
        end
    end
    return result
end
-- Client-only resolver: a dedicated server has different absolute mod paths and language.
local function clientStoreItem(xmlFilename)
    if type(xmlFilename)~="string" or xmlFilename=="" or g_storeManager==nil then return nil end
    local direct=g_storeManager:getItemByXMLFilename(xmlFilename)
    if direct~=nil then return direct end
    local normalized=xmlFilename:gsub("\\","/")
    local modName,relative=normalized:match("/(FS25_[^/]+)/(.+)$")
    if modName and relative then
        local info=g_modManager and g_modManager.getModByName and g_modManager:getModByName(modName)
        if info~=nil then
            for _,dir in ipairs({info.modDir or "", info.modDirectory or "", info.modFileDir or "", info.baseDirectory or ""}) do
                if dir~="" then
                    local fname=Utils.getFilename(relative,dir)
                    local found=g_storeManager:getItemByXMLFilename(fname)
                    if found then return found end
                end
            end
        end
        -- Several FS25 builds expose local mod directory through g_modsDirectory.
        if type(g_modsDirectory)=="string" then
            local fname=Utils.getFilename(modName.."/"..relative,g_modsDirectory)
            local found=g_storeManager:getItemByXMLFilename(fname)
            if found then return found end
        end
        -- Search already indexed shop entries by the portable suffix, never server paths.
        local list=g_storeManager.items
        if type(list)=="table" then
            local suffix=("/"..modName.."/"..relative):lower()
            for _,item in pairs(list) do
                if type(item)=="table" then
                    local fn=item.xmlFilename or item.xmlFileName or item.configFilename
                    if type(fn)=="string" and fn:gsub("\\","/"):lower():sub(-#suffix)==suffix then
                        return item
                    end
                end
            end
        end
    end
    return nil
end
function PB:localizeSlot(s)
    if s==nil then return end
    local shop=clientStoreItem(s.xmlFilename)
    if shop==nil then return end
    s.image=imagePath(shop) or s.image
    local configs={}
    for key,value in pairs(s.configSelections or {}) do
        configs[key]=tonumber(value) or value
    end
    local pseudo={configurations=configs}
    local localized=configurationLabels(pseudo,shop)
    local readable={}
    for _,cfg in ipairs(localized) do readable[#readable+1]=cfg.value end
    -- Preserve server-supplied fill text for now; translated filltype indices can be added later.
    if type(s.fillTypes)=="table" then
        for _,ft in ipairs(s.fillTypes) do
            local label=nil
            if g_fillTypeManager and g_fillTypeManager.getFillTypeByIndex then
                local v=g_fillTypeManager:getFillTypeByIndex(tonumber(ft) or 0)
                if type(v)=="table" then label=v.title or v.name end
            end
            if label~=nil and label~="" then readable[#readable+1]=tostring(label) end
        end
    end
    s.baseName=shop.name or s.baseName
    if #readable>0 then s.configDetails=table.concat(readable,"\n") end
end

-- Group only objects with the same XML, every selected shop configuration, and
-- the same actual fill-unit contents. Keep live objects separate in the slots.
local function objectGroupKey(obj)
    local parts={string.lower(tostring(obj.configFileName or obj.xmlFilename or "")):gsub("\\","/")}
    local configurations=obj.configurations
    if type(configurations)=="table" then
        local keys={}
        for k in pairs(configurations) do keys[#keys+1]=k end
        table.sort(keys,function(a,b) return tostring(a)<tostring(b) end)
        for _,k in ipairs(keys) do
            parts[#parts+1]="cfg:"..tostring(k).."="..tostring(configurations[k])
        end
    end
    if obj.getFillUnits~=nil or obj.getFillUnitFillLevel~=nil then
        local units=obj.getFillUnits and obj:getFillUnits() or nil
        local count=type(units)=="table" and #units or 0
        for i=1,count do
            local amount=obj.getFillUnitFillLevel and obj:getFillUnitFillLevel(i) or 0
            local ft=obj.getFillUnitFillType and obj:getFillUnitFillType(i) or 0
            parts[#parts+1]=string.format("fill:%d:%s:%.4f",i,tostring(ft),tonumber(amount) or 0)
        end
    end
    return table.concat(parts,"|")
end
local function fillUnitLabels(obj)
    local result={}
    local seen={}
    local indices={}
    if obj.getFillUnits~=nil then
        local units=obj:getFillUnits()
        if type(units)=="table" then
            for k,_ in pairs(units) do
                local idx=tonumber(k)
                if idx~=nil then indices[#indices+1]=idx end
            end
        end
    end
    if #indices==0 and obj.getFillUnitFillLevel~=nil then
        for i=1,8 do indices[#indices+1]=i end
    end
    table.sort(indices)
    for _,i in ipairs(indices) do
        local amount=obj.getFillUnitFillLevel and tonumber(obj:getFillUnitFillLevel(i)) or 0
        if amount~=nil and amount>0 then
            local ft=obj.getFillUnitFillType and obj:getFillUnitFillType(i) or 0
            local value=nil
            if g_fillTypeManager~=nil then
                if value==nil and g_fillTypeManager.getFillTypeByIndex~=nil then
                    local desc=g_fillTypeManager:getFillTypeByIndex(ft)
                    if type(desc)=="table" then
                        value=desc.title or desc.name or desc.fillTypeTitle
                    end
                end
                if (value==nil or value=="") and g_fillTypeManager.getFillTypeTitleByIndex~=nil then
                    local title=g_fillTypeManager:getFillTypeTitleByIndex(ft)
                    if type(title)=="string" then value=title end
                end
                if (value==nil or value=="") and g_fillTypeManager.getFillTypeNameByIndex~=nil then
                    local name=g_fillTypeManager:getFillTypeNameByIndex(ft)
                    if type(name)=="string" then value=name end
                end
            end
            if type(value)=="string" and value~="" and not seen[value] then
                table.insert(result,{label="Наполнение",value=value})
                seen[value]=true
            end
        end
    end
    return result
end
local function itemDisplayName(obj,storeItem)
    local base=storeItem.name or 'Предмет'
    local configs=configurationLabels(obj,storeItem)
    local fills=fillUnitLabels(obj)
    local values={}
    local valueSeen={}
    local lines={}
    for _,c in ipairs(configs) do
        if type(c.value)=="string" and c.value~="" then
            if not valueSeen[c.value] then
                table.insert(values,c.value)
                valueSeen[c.value]=true
            end
            table.insert(lines,c.label .. ': ' .. c.value)
        end
    end
    for _,f in ipairs(fills) do
        if type(f.value)=="string" and f.value~="" and not valueSeen[f.value] then
            table.insert(lines,f.label .. ': ' .. f.value)
            valueSeen[f.value]=true
        end
    end
    local suffix=table.concat(values,' / ')
    local brief=base
    if suffix~='' then brief=base .. ' — ' .. suffix end
    local details=#lines>0 and table.concat(lines,'\n') or 'Без дополнительных конфигураций'
    return brief, details, base
end

local function captureCamera()
    local p=player()
    if not p then return nil end
    local camera=p.getCurrentCameraNode and p:getCurrentCameraNode() or nil
    if camera and entityExists(camera) then
        local x,y,z=getRotation(camera)
        return {node=camera,x=x,y=y,z=z}
    end
    return nil
end
function PB:setMenuVisible(state)
    if state then
        if self.dialog ~= nil and g_gui ~= nil then
            g_gui:showDialog("InventoryBackpackDialog")
            if g_client and g_client:getServerConnection() then
                g_client:getServerConnection():sendEvent(BackpackMPEvent.new(BackpackMPEvent.REQUEST,nil,0,false))
            end
        else
            notice("Окно рюкзака не загружено")
        end
    elseif self.dialog ~= nil and g_gui ~= nil then
        self.dialog:close()
    end
end
function PB:toggle()
    if not canUse() then return end
    if self.dialog == nil then return end
    if self.dialog.isOpen then self:setMenuVisible(false) else self:setMenuVisible(true) end
end
-- Register only while the game itself is building the PLAYER input context.
-- A dedicated server has no local controls. The optional force flag permits
-- calling this from PlayerInputComponent before g_localPlayer is published.
function PB:register(force)
    if g_dedicatedServer ~= nil or (not force and not canUse()) then return end
    if g_inputBinding==nil or InputAction==nil or InputAction.PB_OPEN==nil then return end
    if self.actionId==nil then
        local ok,id=g_inputBinding:registerActionEvent(InputAction.PB_OPEN,self,self.toggle,false,true,false,true)
        if ok and id then
            self.actionId=id
            if g_inputBinding.setActionEventText then
                g_inputBinding:setActionEventText(id,'Открыть рюкзак')
            end
        end
    end
    if self.yActionId==nil and InputAction.PB_STORE~=nil then
        local ok,id=g_inputBinding:registerActionEvent(InputAction.PB_STORE,self,self.storeByKey,false,true,false,true)
        if ok and id then self.yActionId=id end
    end
end
-- This FS25 hook is invoked on local-player input setup, not every update.
-- If FS25 genuinely rebuilds the player input context, rebind as part of
-- that game event (not through any polling or repeated timer).
function PB:installInputHook()
    if self.inputHookInstalled then return end
    if PlayerInputComponent==nil or type(PlayerInputComponent.registerGlobalPlayerActionEvents)~='function'
        or Utils==nil or type(Utils.appendedFunction)~='function' then return end
    PlayerInputComponent.registerGlobalPlayerActionEvents=Utils.appendedFunction(
        PlayerInputComponent.registerGlobalPlayerActionEvents,
        function(component)
            if g_dedicatedServer~=nil or component==nil or component.player==nil
                or not component.player.isOwner then return end
            local bp=PlayerBackpack
            if bp==nil then return end
            -- The engine may have cleared an earlier action-event table.
            -- Do not accumulate callbacks from previous player contexts.
            if bp.actionId and g_inputBinding then g_inputBinding:removeActionEvent(bp.actionId) end
            if bp.yActionId and g_inputBinding then g_inputBinding:removeActionEvent(bp.yActionId) end
            bp.actionId=nil
            bp.yActionId=nil
            bp:register(true)
        end)
    self.inputHookInstalled=true
end
function PB:firstEmptySlot()
    if self.slots[self.selected]==nil then return self.selected end
    for i=1,15 do if self.slots[i]==nil then return i end end
end
function PB:storeByKey()
    if canUse() and not self.visible then self:store(true) end
end
function PB:getLocalIdentity()
    local p=player()
    return p and p.getUniqueUserId and p:getUniqueUserId() or nil
end
function PB:getBag(uid)
    if uid==nil or uid=="" then return nil end
    if self.serverBags[uid]==nil then self.serverBags[uid]={} end
    return self.serverBags[uid]
end
-- Keep parked objects OUT of the physics world, not just invisible.
-- FS25 consumables usually use Vehicle components with their own rigid bodies;
-- setVisibility() or setRigidBodyType(KINEMATIC) alone cannot clear them.
-- The stable under-terrain position adds a fallback for objects with unusual
-- custom physics implementations, but explicit physics removal is essential.
PB.PARKED_Y = -500

function PB:applyObjectState(obj, hidden, x, y, z, rigidType)
    if obj==nil or obj.rootNode==nil or not entityExists(obj.rootNode) then return false end
    local node=obj.rootNode
    if hidden then
        local removed=false
        if type(obj.removeFromPhysics)=="function" then
            if obj.isAddedToPhysics==false then
                removed=true
            else
                local ret=obj:removeFromPhysics()
                removed=ret~=false
            end
        elseif type(removeFromPhysics)=="function" then
            removeFromPhysics(node)
            removed=true
        end
        -- Never hide a still-collidable item, or the shop spawn point will stay blocked.
        if not removed then return false end
        setWorldTranslation(node,x,y,z)
        setVisibility(node,false)
    else
        -- On the older builds an invisible object could still have live physics.
        -- Detach it before teleporting it back to the player as well.
        if obj.isAddedToPhysics~=false and type(obj.removeFromPhysics)=="function" then
            obj:removeFromPhysics()
        end
        setWorldTranslation(node,x,y,z)
        if rigidType~=nil and rigidType>=0 then
            setRigidBodyType(node,rigidType)
        end
        local added=false
        if type(obj.addToPhysics)=="function" then
            if obj.isAddedToPhysics==true then
                added=true
            else
                local ret=obj:addToPhysics()
                added=ret~=false or obj.isAddedToPhysics==true
            end
        elseif type(addToPhysics)=="function" then
            addToPhysics(node)
            added=true
        end
        -- Retain the inventory record if the object's collision cannot be restored.
        if not added then return false end
        setVisibility(node,true)
    end
    return true
end

function PB:serverSetObjectState(obj, hidden, x, y, z, rigidType)
    if not self:applyObjectState(obj,hidden,x,y,z,rigidType) then return false end
    if g_server then
        g_server:broadcastEvent(BackpackMPEvent.newState(obj,hidden,x,y,z,rigidType),false)
    end
    return true
end

function PB:sendBag(connection,uid)
    local bag=self:getBag(uid)
    if bag==nil then return end
    if connection then
        local e=BackpackMPEvent.new(BackpackMPEvent.SYNC,nil,0,false)
        e.slots={}
        for i=1,20 do
            local s=bag[i]
            if s then
                e.slots[i]={
                    name=s.name or "",baseName=s.baseName or "",
                    configDetails=s.configDetails or "",
                    groupKey=s.groupKey or "",image="",
                    xmlFilename=s.xmlFilename or "",
                    configSelections=s.configSelections or {},
                    fillTypes=s.fillTypes or {}
                }
            end
        end
        connection:sendEvent(e)
    else
        self.slots={}
        for i=1,20 do self.slots[i]=bag[i] end
        if self.dialog then self.dialog:rebuildItems() end
    end
end
function PB:serverStore(connection,obj)
    if not g_server or not g_currentMission or obj==nil or not obj.rootNode then return end
    local uid
    if connection then uid=g_currentMission.userManager:getUniqueUserIdByConnection(connection)
    else uid=self:getLocalIdentity() end
    if not uid then return end
    local p=g_currentMission.playerSystem:getPlayerByUniqueId(uid)
    if not p or not p.rootNode or p.getIsInVehicle and p:getIsInVehicle() then return end
    local x,y,z=getWorldTranslation(p.rootNode)
    local ox,oy,oz=getWorldTranslation(obj.rootNode)
    if (ox-x)^2+(oz-z)^2>36 or math.abs(oy-y)>4 then return end
    local bag=self:getBag(uid)
    if not bag or self.objectOwners[obj]~=nil then return end
    -- v0.2.1.5: at most 15 real objects in the bag. Older savegame records
    -- from slots 16..20 are preserved until the owner takes them out.
    local occupied=0
    for i=1,20 do
        local isPending=self.pendingBagRecords and self.pendingBagRecords[uid]
            and self.pendingBagRecords[uid][i]~=nil
        if bag[i]~=nil or isPending then occupied=occupied+1 end
    end
    if occupied>=15 then return end
    local idx
    for i=1,15 do
        local isPending=self.pendingBagRecords and self.pendingBagRecords[uid] and self.pendingBagRecords[uid][i] ~= nil
        if bag[i]==nil and not isPending then idx=i break end
    end
    if not idx then return end
    local item
    local target=obj.rootNode
    local found,shop=getShopObject(target,p)
    if found~=obj then return end
    local config=shop and shop.name or "Предмет"
    local oldType
    if getRigidBodyType and setRigidBodyType and RigidBodyType and RigidBodyType.KINEMATIC then
        oldType=getRigidBodyType(target)
    end
    if oldType==nil then return end
    -- Refuse items that the base game cannot identify and save persistently.
    -- Otherwise a restart could silently lose the object or duplicate its contents.
    local uniqueId=self:getPersistentObjectId(obj)
    if uniqueId==nil then
        return
    end
    if obj.getNeedsSaving~=nil and not obj:getNeedsSaving() then
        return
    end
    -- Preserve original rigid-body mode on both server and clients. The actual
    -- type switch happens inside the synchronized object-state helper.
    local fullName,details,base=itemDisplayName(obj,shop)
    local selections={}
    if type(obj.configurations)=="table" then
        for k,v in pairs(obj.configurations) do
            if type(k)=="string" and (type(v)=="number" or type(v)=="string") then selections[k]=tostring(v) end
        end
    end
    local fillTypes={}
    if obj.getFillUnits and obj.getFillUnitFillType and obj.getFillUnitFillLevel then
        local units=obj:getFillUnits()
        if type(units)=="table" then
            for k,_ in pairs(units) do
                local i=tonumber(k)
                if i and (tonumber(obj:getFillUnitFillLevel(i)) or 0)>0 then
                    fillTypes[#fillTypes+1]=obj:getFillUnitFillType(i)
                end
            end
        end
    end
    -- Do not update bag ownership unless the rigid bodies were truly removed.
    if not self:serverSetObjectState(obj,true,ox,self.PARKED_Y-idx*4,oz,oldType) then return end
    bag[idx]={
        uniqueId=uniqueId,object=obj,node=target,
        name=fullName,baseName=base,configDetails=details,
        groupKey=objectGroupKey(obj),image=imagePath(shop),
        xmlFilename=obj.configFileName or obj.xmlFilename or "",
        configSelections=selections,fillTypes=fillTypes,
        oldType=oldType,x=ox,y=oy,z=oz
    }
    self.objectOwners[obj]=uid
    self:sendBag(connection,uid)
end
function PB:serverDrop(connection,index)
    if not g_server or not g_currentMission then return end
    local uid=connection and g_currentMission.userManager:getUniqueUserIdByConnection(connection) or self:getLocalIdentity()
    if not uid then return end
    local p=g_currentMission.playerSystem:getPlayerByUniqueId(uid)
    if not p or not p.rootNode or p.getIsInVehicle and p:getIsInVehicle() then return end
    index=math.floor(tonumber(index) or 0)
    if index<1 or index>20 then return end
    local bag=self:getBag(uid)
    local s=bag and bag[index]
    if not s or not s.node or not entityExists(s.node) then return end
    local x,y,z=getWorldTranslation(p.rootNode)
    local yaw=p.getGraphicalYaw and p:getGraphicalYaw() or 0
    local tx,tz=x+math.sin(yaw)*1.8,z+math.cos(yaw)*1.8
    if not self:serverSetObjectState(s.object,false,tx,y+0.65,tz,s.oldType) then return end
    self.objectOwners[s.object]=nil
    bag[index]=nil
    self:sendBag(connection,uid)
end
function PB:store(byAim)
    if not canUse() then return end
    local node,h=heldNode()
    if not node and byAim then node=aimedNode() end
    if not node then notice('Наведитесь на небольшой предмет'); return end
    local obj,item=getShopObject(node,localGameplayPlayer())
    if not obj or not item then notice('Этот предмет пока не поддерживается'); return end
    if g_client and g_client:getServerConnection() then
        g_client:getServerConnection():sendEvent(BackpackMPEvent.new(BackpackMPEvent.STORE,obj,0,false))
    elseif g_server then
        self:serverStore(nil,obj)
    end
end
function PB:drop()
    if not canUse() then return end
    local index=self.selected
    if g_client and g_client:getServerConnection() then
        g_client:getServerConnection():sendEvent(BackpackMPEvent.new(BackpackMPEvent.DROP,nil,index,false))
    elseif g_server then self:serverDrop(nil,index) end
end
function PB:ensureLocalGUI()
    if self.dialog ~= nil or not canUse() then return end
    if InventoryBackpackDialog == nil then
        if not self.guiReported then
            print("[InventoryBackPack] ERROR: GUI class unavailable on client")
            self.guiReported=true
        end
        return
    end
    local guiFilename=Utils.getFilename("gui/InventoryBackpackCarouselDialog.xml",self.MOD_DIRECTORY)
    self.dialog=InventoryBackpackDialog.new()
    self.dialog:setBackpack(self)
    -- The engine will report GUI-loading failures with a full Lua traceback.
    g_gui:loadGui(guiFilename,"InventoryBackpackDialog",self.dialog)
end
-- Temporary console diagnostics; available on the local client even before input registration.
function PB:consoleStatus()
    local line=string.format("[InventoryBackPack] STATUS: map=%s dedicated=%s localPlayer=%s gui=%s dialog=%s open=%s actionI=%s actionY=%s keyI=%s keyY=%s client=%s server=%s",
        tostring(g_currentMission~=nil),tostring(g_dedicatedServer~=nil),tostring(g_localPlayer~=nil),
        tostring(g_gui~=nil),tostring(self.dialog~=nil),tostring(self.dialog and self.dialog.isOpen),
        tostring(InputAction and InputAction.PB_OPEN),tostring(InputAction and InputAction.PB_STORE),
        tostring(self.actionId),tostring(self.yActionId),tostring(g_client~=nil),tostring(g_server~=nil))
    return line
end
function PB:consoleInit()
    if not canUse() then
        return "IBP: local player unavailable; check ibpStatus"
    end
    self:ensureLocalGUI()
    self:register()
    return self:consoleStatus()
end
function PB:consoleOpen()
    if not canUse() then return "IBP: no local player or player inside vehicle" end
    if not self.dialog then self:ensureLocalGUI() end
    if not self.dialog then return "IBP: GUI missing; check client log" end
    self:toggle()
    return "IBP: toggle sent; see log"
end
function PB:consoleKeys()
    if not canUse() then return "IBP: no local player (or inside vehicle)" end
    if self.actionId and g_inputBinding then g_inputBinding:removeActionEvent(self.actionId) end
    if self.yActionId and g_inputBinding then g_inputBinding:removeActionEvent(self.yActionId) end
    self.actionId=nil
    self.yActionId=nil
    self:register()
    return self:consoleStatus()
end
function PB:registerConsole()
    if self.consoleRegistered or addConsoleCommand==nil then return end
    addConsoleCommand("ibpStatus","InventoryBackPack: show diagnostics","consoleStatus",self)
    addConsoleCommand("ibpInit","InventoryBackPack: initialize GUI and keys","consoleInit",self)
    addConsoleCommand("ibpOpen","InventoryBackPack: open or close GUI","consoleOpen",self)
    addConsoleCommand("ibpKeys","InventoryBackPack: rebind I and Y actions","consoleKeys",self)
    self.consoleRegistered=true
end
function PB:removeConsole()
    if self.consoleRegistered and removeConsoleCommand~=nil then
        for _,name in ipairs({"ibpStatus","ibpInit","ibpOpen","ibpKeys"}) do removeConsoleCommand(name) end
    end
    self.consoleRegistered=false
end
function PB:loadMap()
    self.serverBags={}
    self.objectOwners={}
    self.slots={}
    self.pendingBagRecords={}
    self.persistenceLoaded=false
    self.persistenceRetry=0
    self:installPersistenceHooks()
    self:loadPersistedBags()
    self:registerConsole()
    self.actionId=nil
    self.yActionId=nil
    self.dialog=nil
    self.guiReported=false
    self.inputFallbackElapsed=0
    self.inputFallbackDone=false
    self:installInputHook()
end
function PB:update(dt)
    if g_server and self.pendingBagRecords then
        self.persistenceRetry=(self.persistenceRetry or 0)+(dt or 0)
        if self.persistenceRetry>=1000 then
            self.persistenceRetry=0
            if not self.persistenceLoaded then self:loadPersistedBags() end
            self:restorePersistedBags()
        end
    end
    if not canUse() then return end
    self:ensureLocalGUI()
    -- Single, one-shot fallback for rare game versions that do not invoke
    -- PlayerInputComponent's registration hook after this mod initializes.
    -- Runs at most once per join; never re-registers periodically.
    if not self.inputFallbackDone then
        self.inputFallbackElapsed=(self.inputFallbackElapsed or 0)+(dt or 0)
        if self.inputFallbackElapsed>=8000 then
            self.inputFallbackDone=true
            if self.actionId==nil or self.yActionId==nil then self:register() end
        end
    end
end
function PB:deleteMap()
    self:removeConsole()
    if self.dialog and self.dialog.isOpen then self:setMenuVisible(false) end
    if self.actionId and g_inputBinding then g_inputBinding:removeActionEvent(self.actionId) end
    if self.yActionId and g_inputBinding then g_inputBinding:removeActionEvent(self.yActionId) end
    self.actionId=nil;self.yActionId=nil
    -- Do NOT return stored objects into the world on shutdown. The save hook
    -- stores them at a safe physical position in vanilla vehicles.xml, and our
    -- InventoryBackPack.xml records which player/slot must reclaim them.
    self.pendingBagRecords=nil
    self.slots={};self.serverBags={};self.objectOwners={}
end
addModEventListener(PB)
