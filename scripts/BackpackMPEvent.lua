-- Multiplayer transport. Server exclusively owns inventory state.
BackpackMPEvent={}
BackpackMPEvent.STORE=1
BackpackMPEvent.DROP=2
BackpackMPEvent.SYNC=3
BackpackMPEvent.REQUEST=4
BackpackMPEvent.VISIBILITY=5
BackpackMPEvent.STATE=6
local mt=Class(BackpackMPEvent,Event)
InitEventClass(BackpackMPEvent,"BackpackMPEvent")
function BackpackMPEvent.emptyNew() return Event.new(mt) end
function BackpackMPEvent.new(kind,obj,index,hidden)
    local self=BackpackMPEvent.emptyNew()
    self.kind=kind or 0;self.obj=obj;self.index=index or 0;self.hidden=hidden or false
    return self
end
function BackpackMPEvent.newState(obj,hidden,x,y,z,rigidType)
    local self=BackpackMPEvent.new(BackpackMPEvent.STATE,obj,0,hidden)
    self.x=x;self.y=y;self.z=z;self.rigidType=rigidType
    return self
end
function BackpackMPEvent:writeStream(streamId,connection)
    streamWriteUInt8(streamId,self.kind)
    if self.kind==self.STORE or self.kind==self.VISIBILITY then
        NetworkUtil.writeNodeObject(streamId,self.obj)
        if self.kind==self.VISIBILITY then streamWriteBool(streamId,self.hidden) end
    elseif self.kind==self.STATE then
        NetworkUtil.writeNodeObject(streamId,self.obj)
        streamWriteBool(streamId,self.hidden)
        streamWriteFloat32(streamId,self.x or 0)
        streamWriteFloat32(streamId,self.y or 0)
        streamWriteFloat32(streamId,self.z or 0)
        streamWriteInt32(streamId,self.rigidType or -1)
    elseif self.kind==self.DROP then streamWriteUInt8(streamId,self.index)
    elseif self.kind==self.SYNC then
        for i=1,20 do
            local s=self.slots and self.slots[i]
            streamWriteBool(streamId,s~=nil)
            if s then
                streamWriteString(streamId,s.name or "")
                streamWriteString(streamId,s.baseName or "")
                streamWriteString(streamId,s.configDetails or "")
                streamWriteString(streamId,s.groupKey or "")
                streamWriteString(streamId,s.image or "")
                streamWriteString(streamId,s.xmlFilename or "")
                local configs=s.configSelections or {}
                local keys={}
                for k,_ in pairs(configs) do keys[#keys+1]=k end
                table.sort(keys)
                streamWriteUInt8(streamId,math.min(#keys,50))
                for k=1,math.min(#keys,50) do
                    streamWriteString(streamId,keys[k]);streamWriteString(streamId,configs[keys[k]])
                end
                local fills=s.fillTypes or {}
                streamWriteUInt8(streamId,math.min(#fills,16))
                for k=1,math.min(#fills,16) do streamWriteUInt16(streamId,tonumber(fills[k]) or 0) end
            end
        end
    end
end
function BackpackMPEvent:readStream(streamId,connection)
    self.kind=streamReadUInt8(streamId)
    if self.kind==self.STORE or self.kind==self.VISIBILITY then
        self.obj=NetworkUtil.readNodeObject(streamId)
        if self.kind==self.VISIBILITY then self.hidden=streamReadBool(streamId) end
    elseif self.kind==self.STATE then
        self.obj=NetworkUtil.readNodeObject(streamId)
        self.hidden=streamReadBool(streamId)
        self.x=streamReadFloat32(streamId)
        self.y=streamReadFloat32(streamId)
        self.z=streamReadFloat32(streamId)
        self.rigidType=streamReadInt32(streamId)
    elseif self.kind==self.DROP then self.index=streamReadUInt8(streamId)
    elseif self.kind==self.SYNC then
        self.slots={}
        for i=1,20 do
            if streamReadBool(streamId) then
                local s={
                    name=streamReadString(streamId),
                    baseName=streamReadString(streamId),
                    configDetails=streamReadString(streamId),
                    groupKey=streamReadString(streamId),
                    image=streamReadString(streamId),
                    xmlFilename=streamReadString(streamId)
                }
                s.configSelections={}
                local n=streamReadUInt8(streamId)
                for j=1,n do
                    local key=streamReadString(streamId)
                    local value=streamReadString(streamId)
                    s.configSelections[key]=value
                end
                s.fillTypes={}
                local f=streamReadUInt8(streamId)
                for j=1,f do s.fillTypes[j]=streamReadUInt16(streamId) end
                self.slots[i]=s
            end
        end
    end
    self:run(connection)
end
function BackpackMPEvent:run(connection)
    if not PlayerBackpack then return end
    local b=PlayerBackpack
    if self.kind==self.STORE and not connection:getIsServer() then
        b:serverStore(connection,self.obj)
    elseif self.kind==self.DROP and not connection:getIsServer() then
        b:serverDrop(connection,self.index)
    elseif self.kind==self.REQUEST and not connection:getIsServer() then
        local uid=g_currentMission.userManager:getUniqueUserIdByConnection(connection)
        if uid then b:sendBag(connection,uid) end
    elseif self.kind==self.SYNC and connection:getIsServer() then
        b.slots=self.slots or {}
        for _,s in pairs(b.slots) do b:localizeSlot(s) end
        if b.dialog then b.dialog:rebuildItems() end
    elseif self.kind==self.STATE and connection:getIsServer() and self.obj and self.obj.rootNode then
        local node=self.obj.rootNode
        b.clientOriginalTypes=b.clientOriginalTypes or {}
        if self.hidden then
            -- A client normally holds the rigid body as KINEMATIC, whereas the
            -- server holds it as DYNAMIC. Preserve the client's actual value.
            if b.clientOriginalTypes[self.obj]==nil then
                if getRigidBodyType ~= nil and entityExists(node) then
                    b.clientOriginalTypes[self.obj]=getRigidBodyType(node)
                end
            end
            b:applyObjectState(self.obj,true,self.x,self.y,self.z,nil)
        else
            local old=b.clientOriginalTypes[self.obj]
            if old==nil and self.rigidType~=nil and self.rigidType>=0 then old=self.rigidType end
            if b:applyObjectState(self.obj,false,self.x,self.y,self.z,old) then
                b.clientOriginalTypes[self.obj]=nil
            end
        end
    elseif self.kind==self.VISIBILITY and connection:getIsServer() and self.obj and self.obj.rootNode then
        setVisibility(self.obj.rootNode,not self.hidden)
    end
end
