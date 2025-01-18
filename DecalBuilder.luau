--!native
--!strict
local AssetService = game:GetService("AssetService")

local meshCache = {} :: {
	[string]: EditableMesh
}

local FRONT_FACING = 1
local VALID_AREA = 2

local DECAL_CLIP_MINUSU = 1
local DECAL_CLIP_MINUSV = 2
local DECAL_CLIP_PLUSU = 4
local DECAL_CLIP_PLUSV = 8

export type DecalParams = {
	Size: Vector2,
	CFrame: CFrame,
	Texture: string | Content | SurfaceAppearance,
}

type VertInfo = {
	Flags: number,
	UV: number,
}

type Vertex = {
	Position: number,
	Normal: number,
	UV: number,
}

type ClipState = {
	VertCount: number,
	Indices: {{ number }},

	ClipVerts: { Vertex },
	ClipFlags: { number },

	Pass: number,
}

type Axis =
	| "X"
| "Y"

local DecalBuilder = {}
DecalBuilder.__index = DecalBuilder

export type Class = typeof(setmetatable({} :: {
	_target: MeshPart?,
	_sourceMesh: EditableMesh?,

	_debug: boolean,
	_wireframe: WireframeHandleAdornment,

	_decalMesh: EditableMesh,
	_decal: MeshPart?,

	_idRemap: {
		[number]: number
	},

	_vertInfo: { VertInfo },
}, DecalBuilder))

local function computeClipFlags(mesh: EditableMesh, uvId: number)
	local flags = 0
	local uv = mesh:GetUV(uvId)

	if uv then
		if uv.X < 0 then
			flags += DECAL_CLIP_MINUSU
		elseif uv.X > 1 then
			flags += DECAL_CLIP_PLUSU
		end

		if uv.Y < 0 then
			flags += DECAL_CLIP_MINUSV
		elseif uv.Y > 1 then
			flags += DECAL_CLIP_PLUSV
		end
	end

	return flags
end

local function getRemap(self: Class, value: number, handler: (number) -> number)
	local idRemap = self._idRemap
	local result = idRemap[value]

	if not result then
		result = handler(value)
		idRemap[value] = result
	end

	return result
end

local function intersectPlane(self: Class, state: ClipState, startAt: number, endAt: number, planeAxis: Axis, planeVal: number)
	local mesh = self._decalMesh
	local newIndex = #state.ClipVerts + 1

	local startVert = state.ClipVerts[startAt]
	local endVert = state.ClipVerts[endAt]

	local startPos = mesh:GetPosition(startVert.Position)
	local endPos = mesh:GetPosition(endVert.Position)

	local startNorm = mesh:GetNormal(startVert.Normal) or Vector3.yAxis
	local endNorm = mesh:GetNormal(endVert.Normal) or Vector3.yAxis

	local startUV = mesh:GetUV(startVert.UV) or Vector2.zero
	local endUV = mesh:GetUV(endVert.UV) or Vector2.zero

	local dir = endUV - startUV
	assert(if planeAxis == "X" then dir.X ~= 0 else dir.Y ~= 0)

	local t = if planeAxis == "X"
		then (planeVal - startUV.X) / dir.X
		else (planeVal - startUV.Y) / dir.Y

	local newNorm = startNorm:Lerp(endNorm, t).Unit
	local newPos = startPos:Lerp(endPos, t)
	local newUV = startUV:Lerp(endUV, t)

	local newMesh = self._decalMesh
	local uvId = newMesh:AddUV(newUV)

	state.ClipVerts[newIndex] = {
		Position = newMesh:AddVertex(newPos),
		Normal = newMesh:AddNormal(newNorm),
		UV = uvId,
	}

	state.ClipFlags[newIndex] = computeClipFlags(newMesh, uvId)
	return newIndex
end

local function clipTriangleAgainstPlane(self: Class, state: ClipState, planeAxis: Axis, flag: number, planeVal: number)
	local outVertCount = 0
	local nextPass = state.Pass == 1 and 2 or 1

	local startAt = state.Indices[state.Pass][state.VertCount]
	local startInside = not bit32.btest(state.ClipFlags[startAt], flag)

	for i = 1, state.VertCount do
		local endAt = state.Indices[state.Pass][i]
		local endInside = not bit32.btest(state.ClipFlags[endAt], flag)

		if endInside then
			if not startInside then
				local clipVert = intersectPlane(self, state, startAt, endAt, planeAxis, planeVal)
				state.Indices[nextPass][outVertCount + 1] = clipVert
				outVertCount += 1
			end

			state.Indices[nextPass][outVertCount + 1] = endAt
			outVertCount += 1
		else
			if startInside then
				local clipVert = intersectPlane(self, state, startAt, endAt, planeAxis, planeVal)
				state.Indices[nextPass][outVertCount + 1] = clipVert
				outVertCount += 1
			end
		end

		startAt = endAt
		startInside = endInside
	end

	state.Pass = nextPass
	state.VertCount = outVertCount
end

local function clipDecal(self: Class, clipVerts: { Vertex }, clipFlags: { number })
	local clipState = {
		Indices = { {1, 2, 3}, {} },
		VertCount = 3,
		Pass = 1,

		ClipVerts = clipVerts,
		ClipFlags = clipFlags,
	}

	-- "X = 0" Plane
	clipTriangleAgainstPlane(self, clipState, "X", DECAL_CLIP_MINUSU, 0.0)

	if clipState.VertCount < 3 then
		return
	end

	-- "X = 1" Plane
	clipTriangleAgainstPlane(self, clipState, "X", DECAL_CLIP_PLUSU, 1.0)

	if clipState.VertCount < 3 then
		return
	end

	-- "Y = 0" Plane
	clipTriangleAgainstPlane(self, clipState, "Y", DECAL_CLIP_MINUSV, 0.0)

	if clipState.VertCount < 3 then
		return
	end

	-- "Y = 1" Plane
	clipTriangleAgainstPlane(self, clipState, "Y", DECAL_CLIP_PLUSV, 1.0)

	if clipState.VertCount < 3 then
		return
	end

	local wireframe = self._wireframe

	if self._debug then
		wireframe.Color3 = Color3.new(0, 1, 1)
	end

	local newMesh = self._decalMesh
	local verts = table.create(clipState.VertCount)

	for i = 1, clipState.VertCount do
		local vertIndex = clipState.Indices[clipState.Pass][i]
		verts[i] = clipState.ClipVerts[vertIndex]
	end

	for i = 2, clipState.VertCount - 1 do
		local a, b, c = verts[1], verts[i], verts[i + 1]
		local faceId = newMesh:AddTriangle(a.Position, b.Position, c.Position)

		newMesh:SetFaceNormals(faceId, { a.Normal, b.Normal, c.Normal })
		newMesh:SetFaceUVs(faceId, { a.UV, b.UV, c.UV })

		if self._debug then
			local uvA = newMesh:GetUV(a.UV) or Vector2.zero
			local uvB = newMesh:GetUV(b.UV) or Vector2.zero
			local uvC = newMesh:GetUV(c.UV) or Vector2.zero

			wireframe:AddPath({
				Vector3.new(uvA.X - 0.5, 0.5 - uvA.Y),
				Vector3.new(uvB.X - 0.5, 0.5 - uvB.Y),
				Vector3.new(uvC.X - 0.5, 0.5 - uvC.Y),
			}, true)
		end
	end

	if self._debug then
		wireframe.Color3 = Color3.new(1, 0, 0)
	end
end

function DecalBuilder.CreateAsync(target: MeshPart?): Class
	local decalMesh = AssetService:CreateEditableMesh() :: EditableMesh
	local wireframe = Instance.new("WireframeHandleAdornment")

	local self = setmetatable({
		_idRemap = {},
		_vertInfo = {},

		_debug = false,
		_target = nil,

		_decalMesh = decalMesh,
		_wireframe = wireframe,
	}, DecalBuilder)

	if target then
		self:SetTargetAsync(target)
	end

	return self
end

function DecalBuilder.SetDebugParams(self: Class, enabled: boolean, adornee: PVInstance?)
	local wireframe = self._wireframe
	self._debug = enabled

	if enabled and adornee then
		wireframe.Adornee = adornee
		wireframe.Parent = adornee        
	else
		wireframe.Parent = nil
	end
end

function DecalBuilder.SetTargetAsync(self: Class, target: MeshPart)
	local content = target.MeshContent

	return pcall(function ()
		local uri = content.Uri
		local sourceMesh = uri and meshCache[uri]

		if not sourceMesh then
			sourceMesh = AssetService:CreateEditableMeshAsync(content) :: EditableMesh

			if uri then
				meshCache[uri] = sourceMesh
			end
		end

		self._sourceMesh = sourceMesh
		self._target = target
	end)
end

function DecalBuilder.IsReadyToApplyDecal(self: Class)
	return self._target ~= nil and self._sourceMesh ~= nil
end

function DecalBuilder.WaitForReady(self: Class)
	repeat local bool = self:IsReadyToApplyDecal() until bool == true
end

function DecalBuilder.Destroy(self: Class)
	if self._sourceMesh then
		self._sourceMesh:Destroy()
		self._sourceMesh = nil
	end

	if self._decal then
		self._decal:Destroy()
		self._decal = nil
	end

	if self._decalMesh then
		self._decalMesh:Destroy()
	end

	self._target = nil
end

function DecalBuilder.ApplyDecalAsync(self: Class, params: DecalParams)
	if not self:IsReadyToApplyDecal() then
		return false
	end
	
	local meshPart = self._target
	local mesh = self._sourceMesh

	if not (meshPart and mesh) then
		return false
	end

	local size = meshPart.Size
	local meshSize = meshPart.MeshSize

	local toMeshSpace = meshSize / size
	local toPartSpace = size / meshSize

	local clipCF = params.CFrame
	local clipUp = clipCF.UpVector
	local clipSize = Vector3.new(params.Size.X, params.Size.Y, 1)

	local newMesh = AssetService:CreateEditableMesh() :: EditableMesh
	local idRemap = self._idRemap

	local wireframe = self._wireframe
	wireframe:Clear()

	if not newMesh then
		return false
	end

	if self._debug then
		local scale = math.max(params.Size.X, params.Size.Y)
		wireframe.Color3 = Color3.new(1, 1, 0)
		wireframe.Scale = Vector3.one * scale
		wireframe.CFrame = clipCF

		wireframe:AddPath({
			Vector3.new(-0.5, -0.5, 0),
			Vector3.new( 0.5, -0.5, 0),
			Vector3.new( 0.5,  0.5, 0),
			Vector3.new(-0.5,  0.5, 0),
		}, true)
	end

	self._decalMesh = newMesh
	newMesh:Triangulate()
	table.clear(idRemap)

	local clipRelative = meshPart.CFrame:ToObjectSpace(clipCF)
	local clipOrigin = (clipRelative.Position * toMeshSpace)

	local clipNormal = (clipRelative.ZVector * toMeshSpace).Unit
	local clipLocal = CFrame.lookAlong(clipOrigin, clipNormal, clipUp)

	local vertInfo = self._vertInfo
	table.clear(vertInfo)

	local radius = clipSize.Magnitude
	local invRadius = 1 / radius

	local normalIds = mesh:GetNormals()
	local vertIds = mesh:GetVertices()

	for i, vertId in vertIds do
		if vertInfo[vertId] then
			continue
		end

		local normalId = normalIds[i]
		local vertNormal = mesh:GetNormal(normalId)

		local info = {
			Flags = 0,
			UV = 0,
		}

		if vertNormal and clipNormal:Dot(vertNormal) >= 0.1 then
			local pos = mesh:GetPosition(vertId)
			info.Flags += FRONT_FACING

			local relative = clipLocal:PointToObjectSpace(pos)
			relative *= toPartSpace

			local uv = Vector2.new(relative.X, relative.Y)
			uv = (Vector2.one / 2) - (uv * invRadius * 2)

			info.UV = newMesh:AddUV(uv)

			if math.abs(relative.Z) < radius then
				info.Flags += VALID_AREA
			end
		end

		vertInfo[vertId] = info
	end

	for i, faceId in mesh:GetFaces() do
		local vertIds = mesh:GetFaceVertices(faceId)
		local normIds = mesh:GetFaceNormals(faceId)
		local vertA, vertB, vertC = unpack(vertIds)

		local infoA = vertInfo[vertA]
		local infoB = vertInfo[vertB]
		local infoC = vertInfo[vertC]

		if not bit32.btest(FRONT_FACING, infoA.Flags, infoB.Flags, infoC.Flags) then
			continue
		end

		local allNotInValidArea = bit32.bor(infoA.Flags, infoB.Flags, infoC.Flags)

		if not bit32.btest(VALID_AREA, allNotInValidArea) then
			continue
		end

		local clipFlags = {
			computeClipFlags(newMesh, infoA.UV),
			computeClipFlags(newMesh, infoB.UV),
			computeClipFlags(newMesh, infoC.UV),
		}

		if bit32.btest(table.unpack(clipFlags)) then
			continue
		end

		local clipVerts = table.create(3)

		for i = 1, 3 do
			local vertId = vertIds[i]
			local normId = normIds[i]
			local info = vertInfo[vertId]

			clipVerts[i] = {
				Position = getRemap(self, vertIds[i], function ()
					local pos = mesh:GetPosition(vertId)
					local norm = mesh:GetNormal(normId)

					if norm then
						pos += (norm / 100)
					end

					return newMesh:AddVertex(pos)
				end),

				Normal = getRemap(self, normId, function ()
					local norm = mesh:GetNormal(normId)
					return newMesh:AddNormal(norm)
				end),

				UV = info.UV,
			}
		end

		clipDecal(self, clipVerts, clipFlags)
	end

	local center = newMesh:GetCenter()

	for i, vertId in newMesh:GetVertices() do
		local pos = newMesh:GetPosition(vertId)
		newMesh:SetPosition(vertId, pos - center)
	end

	local success, newMeshPart = pcall(function ()
		local newContent = Content.fromObject(newMesh)

		return AssetService:CreateMeshPartAsync(newContent, {
			CollisionFidelity = Enum.CollisionFidelity.Box,
			RenderFidelity = Enum.RenderFidelity.Precise,
		})
	end)

	if not success then
		return false
	end

	if self._decal and self._decal:IsDescendantOf(game) then
		local weld = self._decal:FindFirstChildOfClass("Weld")
		local surface = self._decal:FindFirstChildOfClass("SurfaceAppearance")
		if surface then
			surface:Destroy()
		end

		if typeof(params.Texture) == "Instance" then
			local copy = params.Texture:Clone()
			copy.Parent = self._decal
		elseif typeof(params.Texture) == "Content" then
			--im not positive if this one contains transparent features
			newMeshPart.TextureContent = params.Texture
		else
			newMeshPart.TextureID = params.Texture
		end

		if weld then
			weld.Part0 = meshPart
			weld.C0 = CFrame.new(center * toPartSpace)
		else
			local attach = Instance.new("Weld")
			attach.C0 = CFrame.new(center * toPartSpace)
			attach.Part0 = meshPart
			attach.Part1 = self._decal
			attach.Parent = self._decal
		end

		local newSize = newMeshPart.Size * toPartSpace
		self._decal:ApplyMesh(newMeshPart)
		self._decal.Parent = meshPart
		self._decal.Size = newSize
	else
		local attach = Instance.new("Weld")
		attach.C0 = CFrame.new(center * toPartSpace)
		attach.Part0 = meshPart
		attach.Part1 = newMeshPart
		attach.Parent = newMeshPart

		if typeof(params.Texture) == "Instance" then
			local copy = params.Texture:Clone()
			copy.Parent = newMeshPart
		elseif typeof(params.Texture) == "Content" then
			newMeshPart.TextureContent = params.Texture
		else
			newMeshPart.TextureID = params.Texture
		end

		newMeshPart.Name = "Decal"
		newMeshPart.Size *= toPartSpace
		newMeshPart.CastShadow = false
		newMeshPart.CanCollide = false
		newMeshPart.CanQuery = false
		newMeshPart.CanTouch = false
		newMeshPart.Massless = true
		newMeshPart.Parent = meshPart

		self._decal = newMeshPart
	end

	return true
end

return DecalBuilder