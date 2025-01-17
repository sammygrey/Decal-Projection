local Players = game:GetService("Players")
local player = Players.LocalPlayer
local mouse = player:GetMouse()

local workspaceService = game:GetService("Workspace")
local userInputService = game:GetService("UserInputService")

local currentCamera = workspaceService.CurrentCamera

local UserInputService = game:GetService("UserInputService")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local DecalProjection = require(ReplicatedStorage.DecalProjection)
local AddDecal = ReplicatedStorage.AddDecal
local SurfaceAppearance = ReplicatedStorage.SurfaceAppearance

local Players = game.Players
local Player = Players.LocalPlayer

local stickerList = {}

local function getMouseHit(filter: {}, filterType: Enum.RaycastFilterType)
	local mouseLocation = userInputService:GetMouseLocation()
	local viewportRay = currentCamera:ViewportPointToRay(mouseLocation.X, mouseLocation.Y)
	local RayParams = RaycastParams.new()
	RayParams.FilterDescendantsInstances = filter
	RayParams.FilterType = filterType
	local raycastResult = workspaceService:Raycast(viewportRay.Origin, viewportRay.Direction * 1000, RayParams)
	if raycastResult then
		return raycastResult["Instance"]
	else
		return nil
	end
end

local function attemptSpray()
	local Target = getMouseHit(stickerList, Enum.RaycastFilterType.Exclude)
	if Target then
		if Target:IsA("MeshPart") then
			--size can be whatever u want im just doing 1,1 for testing
			local Params: DecalProject.DecalParams = {
				Size = Vector2.new(1,1),
				CFrame = mouse.Hit,
				Texture = SurfaceAppearance,
			}
			--send above data to server via event
			AddDecal:FireServer(Target, Params)
		end
	end
end

userInputService.InputBegan:Connect(function(Input: InputObject)
	if Input.UserInputType == Enum.UserInputType.MouseButton1 then
		attemptSpray()
	end
end)


local function userApply(Target, Params, UUID, User)
	local meshEditor = DecalProjection.CreateAsync(Target)
	task.spawn(function()
		meshEditor:WaitForReady()
	end)
	local success, newMesh = pcall(function()
		meshEditor:ApplyDecalAsync(Params)
	end)
	if success then
		newMesh.Name = UUID
		table.insert(stickerList, newMesh)
	else
		warn(newMesh)
	end
end

AddDecal.OnClientEvent:Connect(function(Target, Params, UUID, User)
	userApply(Target, Params, UUID, User)
end)
