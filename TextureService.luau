local ReplicatedStorage = game:GetService("ReplicatedStorage")
local AddDecal = ReplicatedStorage.AddDecal
local DecalProjection = require(ReplicatedStorage.DecalProjection)

local ServerService = game:GetService("ServerScriptService")
local UUIDGenerator = require(ServerService.UUIDGenerator)

AddDecal.OnServerEvent:Connect(function(User: Player, Target: MeshPart, DecalParams: DecalProjection.DecalParams)
	--this would be a lot easier to maintain if editable instances were shared betwen server and client
	UUIDGenerator:CreateUniqueSeed()
	local UUID = UUIDGenerator:GenerateUUID()
	AddDecal:FireAllClients(Target, DecalParams, UUID, User)
end)