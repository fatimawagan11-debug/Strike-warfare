--[[
	Constipated Hub | Strike: Warfare GOD
	Mobile-friendly · Center FOV · Billboard ESP · Working combat
]]

repeat task.wait() until game:IsLoaded() and game:GetService("Players").LocalPlayer

local okOrion, OrionLib = pcall(function()
	return loadstring(game:HttpGet("https://raw.githubusercontent.com/jensonhirst/Orion/main/source"))()
end)
if not okOrion or not OrionLib then
	warn("[Constipated] Orion failed to load")
	return
end

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local VirtualInputManager = game:GetService("VirtualInputManager")
local Lighting = game:GetService("Lighting")
local CoreGui = game:GetService("CoreGui")

local LP = Players.LocalPlayer
local Camera = Workspace.CurrentCamera
local IS_MOBILE = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled

local GENV = (typeof(getgenv) == "function" and getgenv()) or _G
GENV.__ConstipatedSW = (GENV.__ConstipatedSW or 0) + 1
local GEN = GENV.__ConstipatedSW
local function alive()
	return GENV.__ConstipatedSW == GEN
end

-- ===================== REMOTES =====================
local Remotes = {}
local function child(root, ...)
	local c = root
	for _, n in ipairs({ ... }) do
		if not c then return nil end
		c = c:FindFirstChild(n)
	end
	return c
end

local function refreshRemotes()
	local E = child(ReplicatedStorage, "Events")
	if E then
		Remotes.Fire = E:FindFirstChild("FireRemote")
		Remotes.Launch = E:FindFirstChild("LaunchRemote")
		Remotes.Throw = E:FindFirstChild("ThrowRemote")
		Remotes.Homing = E:FindFirstChild("HomingLaunchRemote")
		Remotes.LauncherHit = E:FindFirstChild("LauncherHitRemote")
		Remotes.Heal = E:FindFirstChild("HealRemote")
		Remotes.Repair = E:FindFirstChild("RepairRemote")
	end
	Remotes.Red = ReplicatedStorage:FindFirstChild("RedEvent")
end
refreshRemotes()
task.spawn(function()
	while alive() do
		refreshRemotes()
		task.wait(3)
	end
end)

local function fireR(r, ...)
	if not r then return false end
	local args = { ... }
	local ok = pcall(function()
		if r:IsA("RemoteEvent") then
			r:FireServer(unpack(args))
		elseif r:IsA("RemoteFunction") then
			r:InvokeServer(unpack(args))
		end
	end)
	return ok
end

-- ===================== FLAGS =====================
local F = {
	Aimbot = false,
	SilentAim = false,
	StickyAim = true,
	-- On mobile: when Aimbot on, always aim (no RMB). On PC: hold RMB unless AlwaysOn.
	AimAlwaysOn = IS_MOBILE,
	AimPart = "Head",
	AimFOV = 180,
	AimSmooth = 0.15,
	AimPredict = 0.1,
	TeamCheck = true,
	WallCheck = false,
	ShowFOV = true,
	Priority = "FOV",

	Triggerbot = false,
	TriggerDelay = 0.05,
	TriggerFOVOnly = true,

	Ragebot = false,
	RageFOV = 400,
	RageSmooth = 0.05,
	RageFireRate = 0.06,
	RagePart = "Head",
	RageUseRemote = true,

	ESP = true,
	EspBox = true,
	EspName = true,
	EspDist = true,
	EspHP = true,
	EspChams = true,
	EspTracer = false,
	EspEnemyOnly = true,
	EspMax = 2500,

	Hitbox = false,
	HitboxSize = 6,
	Speed = false,
	SpeedVal = 26,
	InfJump = false,
	Noclip = false,
	FullBright = false,
	NoFog = false,
	AutoHeal = false,
	AutoRepair = false,
}

-- ===================== HELPERS =====================
local function getChar(p)
	return p and p.Character
end
local function getHum(p)
	local c = getChar(p)
	return c and c:FindFirstChildOfClass("Humanoid")
end
local function getHRP(p)
	local c = getChar(p)
	if not c then return nil end
	return c:FindFirstChild("HumanoidRootPart") or c:FindFirstChild("Torso") or c.PrimaryPart
end
local function getPart(p, name)
	local c = getChar(p)
	if not c then return nil end
	return c:FindFirstChild(name)
		or c:FindFirstChild("Head")
		or c:FindFirstChild("UpperTorso")
		or getHRP(p)
end
local function isAlive(p)
	local h = getHum(p)
	return h and h.Health > 0
end
local function sameTeam(p)
	if not p or p == LP then return true end
	local ok, res = pcall(function()
		if LP.Team and p.Team and LP.Team == p.Team then return true end
		if LP.TeamColor and p.TeamColor and LP.TeamColor == p.TeamColor then return true end
		return false
	end)
	return ok and res
end
local function isVisible(pt)
	if not pt then return false end
	local origin = Camera.CFrame.Position
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { LP.Character }
	params.IgnoreWater = true
	local res = Workspace:Raycast(origin, pt.Position - origin, params)
	if not res then return true end
	return res.Instance and pt.Parent and res.Instance:IsDescendantOf(pt.Parent)
end
local function w2s(pos)
	local v, on = Camera:WorldToViewportPoint(pos)
	return Vector2.new(v.X, v.Y), on, v.Z
end
local function screenCenter()
	local v = Camera.ViewportSize
	return Vector2.new(v.X * 0.5, v.Y * 0.5)
end
local function predict(pt, t)
	if not pt then return nil end
	if not t or t <= 0 then return pt.Position end
	local vel = Vector3.zero
	pcall(function()
		vel = pt.AssemblyLinearVelocity
	end)
	return pt.Position + vel * t
end

-- ===================== TARGET =====================
local curTarget, silentPart, stickyUntil = nil, nil, 0

local function getTarget(fov, partName, doWall)
	if F.StickyAim and curTarget and os.clock() < stickyUntil and isAlive(curTarget) then
		if not (F.TeamCheck and sameTeam(curTarget)) then
			local pt = getPart(curTarget, partName)
			if pt then
				local sp, on = w2s(pt.Position)
				if on then
					local d = (sp - screenCenter()).Magnitude
					if d < fov * 1.4 and (not doWall or isVisible(pt)) then
						return curTarget, pt
					end
				end
			end
		end
	end

	local best, bestPt, bestScore = nil, nil, -1e12
	local center = screenCenter()
	local myHRP = getHRP(LP)

	for _, plr in ipairs(Players:GetPlayers()) do
		if plr == LP then continue end
		if F.TeamCheck and sameTeam(plr) then continue end
		if not isAlive(plr) then continue end
		local pt = getPart(plr, partName)
		if not pt then continue end
		if doWall and not isVisible(pt) then continue end

		local sp, on = w2s(predict(pt, F.AimPredict))
		if not on then continue end
		local md = (sp - center).Magnitude
		if md > fov then continue end

		local dist = myHRP and (pt.Position - myHRP.Position).Magnitude or 9999
		local hp = getHum(plr).Health
		local score
		if F.Priority == "Distance" then
			score = -dist
		elseif F.Priority == "Health" then
			score = -hp
		else
			score = -md
		end
		score = score - md * 0.001

		if score > bestScore then
			bestScore = score
			best = plr
			bestPt = pt
		end
	end

	if best then
		curTarget = best
		stickyUntil = os.clock() + 0.5
	end
	return best, bestPt
end

-- ===================== SILENT AIM HOOK =====================
local hooked = false
local function hookSilent()
	if hooked then return end
	if type(getrawmetatable) ~= "function" then return end
	local newcc = newcclosure or function(f) return f end
	hooked = true
	pcall(function()
		local mt = getrawmetatable(game)
		local old = mt.__namecall
		setreadonly(mt, false)
		mt.__namecall = newcc(function(self, ...)
			local method = getnamecallmethod()
			local args = { ... }
			if (F.SilentAim or F.Ragebot) and silentPart and silentPart.Parent then
				if method == "FireServer" or method == "fireServer" then
					local gun = self == Remotes.Fire
						or self == Remotes.Launch
						or self == Remotes.Throw
						or self == Remotes.Homing
						or self == Remotes.LauncherHit
					if gun then
						local origin = Camera.CFrame.Position
						local goal = predict(silentPart, F.AimPredict)
						if goal then
							local dir = goal - origin
							if dir.Magnitude > 0.05 then
								dir = dir.Unit
								if #args >= 2 and typeof(args[1]) == "Vector3" and typeof(args[2]) == "Vector3" then
									args[1] = origin
									args[2] = dir
									return old(self, unpack(args))
								elseif #args >= 1 and typeof(args[1]) == "Vector3" then
									args[1] = goal
									return old(self, unpack(args))
								elseif #args >= 1 and typeof(args[1]) == "CFrame" then
									args[1] = CFrame.new(origin, goal)
									return old(self, unpack(args))
								end
							end
						end
					end
				end
			end
			return old(self, ...)
		end)
		setreadonly(mt, true)
	end)
end
task.defer(hookSilent)

-- ===================== CENTER FOV (Drawing if available) =====================
local hasDrawing = pcall(function()
	return Drawing and Drawing.new
end)
local fovCircle
if hasDrawing then
	fovCircle = Drawing.new("Circle")
	fovCircle.Thickness = 1.5
	fovCircle.NumSides = 64
	fovCircle.Filled = false
	fovCircle.Color = Color3.fromRGB(255, 255, 255)
	fovCircle.Transparency = 0.85
	fovCircle.Visible = false
end

-- GUI FOV ring fallback (works on mobile when Drawing fails)
local fovGui = Instance.new("ScreenGui")
fovGui.Name = "CSW_FOV"
fovGui.ResetOnSpawn = false
fovGui.IgnoreGuiInset = true
pcall(function()
	fovGui.Parent = CoreGui
end)
if not fovGui.Parent then
	fovGui.Parent = LP:WaitForChild("PlayerGui")
end
local fovFrame = Instance.new("Frame")
fovFrame.Name = "Ring"
fovFrame.AnchorPoint = Vector2.new(0.5, 0.5)
fovFrame.Position = UDim2.fromScale(0.5, 0.5)
fovFrame.Size = UDim2.fromOffset(180, 180)
fovFrame.BackgroundTransparency = 1
fovFrame.Visible = false
fovFrame.Parent = fovGui
local fovStroke = Instance.new("UIStroke")
fovStroke.Thickness = 1.5
fovStroke.Color = Color3.fromRGB(255, 255, 255)
fovStroke.Transparency = 0.3
fovStroke.Parent = fovFrame
local fovCorner = Instance.new("UICorner")
fovCorner.CornerRadius = UDim.new(1, 0)
fovCorner.Parent = fovFrame

local function setFOVVisible(on, radius, color)
	if fovCircle then
		local c = screenCenter()
		fovCircle.Position = c
		fovCircle.Radius = radius
		fovCircle.Color = color
		fovCircle.Visible = on
	end
	fovFrame.Visible = on
	fovFrame.Size = UDim2.fromOffset(radius * 2, radius * 2)
	fovFrame.Position = UDim2.fromScale(0.5, 0.5)
	fovStroke.Color = color
end

-- ===================== ESP (BillboardGui — works on mobile) =====================
local espFolder = Instance.new("Folder")
espFolder.Name = "CSW_ESP"
espFolder.Parent = Workspace

local espObjects = {} -- [player] = {bb, hl, ...}

local function clearESP(plr)
	local t = espObjects[plr]
	if not t then return end
	pcall(function()
		if t.bb then t.bb:Destroy() end
		if t.hl then t.hl:Destroy() end
		if t.box then t.box:Destroy() end
	end)
	espObjects[plr] = nil
end

local function clearAllESP()
	for plr in pairs(espObjects) do
		clearESP(plr)
	end
end

local function ensureESP(plr)
	if espObjects[plr] and espObjects[plr].bb and espObjects[plr].bb.Parent then
		return espObjects[plr]
	end
	clearESP(plr)

	local bb = Instance.new("BillboardGui")
	bb.Name = "CSW_" .. plr.Name
	bb.AlwaysOnTop = true
	bb.Size = UDim2.new(0, 120, 0, 50)
	bb.StudsOffset = Vector3.new(0, 3.2, 0)
	bb.MaxDistance = F.EspMax
	bb.Parent = espFolder

	local nameL = Instance.new("TextLabel")
	nameL.Name = "Name"
	nameL.BackgroundTransparency = 1
	nameL.Size = UDim2.new(1, 0, 0, 16)
	nameL.Position = UDim2.new(0, 0, 0, 0)
	nameL.Font = Enum.Font.GothamBold
	nameL.TextSize = 14
	nameL.TextColor3 = Color3.fromRGB(255, 70, 70)
	nameL.TextStrokeTransparency = 0.4
	nameL.Text = plr.DisplayName or plr.Name
	nameL.Parent = bb

	local infoL = Instance.new("TextLabel")
	infoL.Name = "Info"
	infoL.BackgroundTransparency = 1
	infoL.Size = UDim2.new(1, 0, 0, 14)
	infoL.Position = UDim2.new(0, 0, 0, 16)
	infoL.Font = Enum.Font.Gotham
	infoL.TextSize = 12
	infoL.TextColor3 = Color3.fromRGB(220, 220, 220)
	infoL.TextStrokeTransparency = 0.5
	infoL.Text = ""
	infoL.Parent = bb

	local hpBarBG = Instance.new("Frame")
	hpBarBG.Name = "HPBG"
	hpBarBG.Size = UDim2.new(0.8, 0, 0, 4)
	hpBarBG.Position = UDim2.new(0.1, 0, 0, 32)
	hpBarBG.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
	hpBarBG.BorderSizePixel = 0
	hpBarBG.Parent = bb
	local hpCorner = Instance.new("UICorner")
	hpCorner.CornerRadius = UDim.new(1, 0)
	hpCorner.Parent = hpBarBG
	local hpBar = Instance.new("Frame")
	hpBar.Name = "HP"
	hpBar.Size = UDim2.new(1, 0, 1, 0)
	hpBar.BackgroundColor3 = Color3.fromRGB(80, 255, 80)
	hpBar.BorderSizePixel = 0
	hpBar.Parent = hpBarBG
	local hpCorner2 = Instance.new("UICorner")
	hpCorner2.CornerRadius = UDim.new(1, 0)
	hpCorner2.Parent = hpBar

	local hl = Instance.new("Highlight")
	hl.Name = "CSW_HL"
	hl.FillColor = Color3.fromRGB(255, 60, 60)
	hl.OutlineColor = Color3.fromRGB(255, 255, 255)
	hl.FillTransparency = 0.55
	hl.OutlineTransparency = 0.2
	hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	hl.Enabled = false
	hl.Parent = espFolder

	-- selection box on HRP for "box" feel
	local box = Instance.new("BoxHandleAdornment")
	box.Name = "CSW_Box"
	box.AlwaysOnTop = true
	box.ZIndex = 5
	box.Adornee = nil
	box.Size = Vector3.new(4, 6, 2)
	box.Color3 = Color3.fromRGB(255, 60, 60)
	box.Transparency = 0.7
	box.Visible = false
	box.Parent = espFolder

	espObjects[plr] = {
		bb = bb,
		name = nameL,
		info = infoL,
		hpBar = hpBar,
		hpBG = hpBarBG,
		hl = hl,
		box = box,
	}
	return espObjects[plr]
end

Players.PlayerRemoving:Connect(function(plr)
	clearESP(plr)
end)

-- ===================== INPUT =====================
local holdingRMB = false
UserInputService.InputBegan:Connect(function(input, gp)
	if gp then return end
	if input.UserInputType == Enum.UserInputType.MouseButton2 then
		holdingRMB = true
	end
	if input.KeyCode == Enum.KeyCode.Space and F.InfJump then
		local h = getHum(LP)
		if h then
			h:ChangeState(Enum.HumanoidStateType.Jumping)
		end
	end
end)
UserInputService.InputEnded:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton2 then
		holdingRMB = false
	end
end)

local function aimActive()
	if not F.Aimbot then return false end
	if F.AimAlwaysOn then return true end
	return holdingRMB
end

local function doClick()
	-- works on many mobile executors
	pcall(function()
		VirtualInputManager:SendMouseButtonEvent(0, 0, 0, true, game, 1)
		task.wait(0.02)
		VirtualInputManager:SendMouseButtonEvent(0, 0, 0, false, game, 1)
	end)
	-- also try tool activation
	pcall(function()
		local char = LP.Character
		if not char then return end
		local tool = char:FindFirstChildOfClass("Tool")
		if tool then
			tool:Activate()
		end
	end)
end

local function fireAt(pt)
	if not pt then return end
	local origin = Camera.CFrame.Position
	local goal = predict(pt, F.AimPredict) or pt.Position
	local dir = goal - origin
	if dir.Magnitude < 0.05 then return end
	dir = dir.Unit

	if F.RageUseRemote and Remotes.Fire then
		-- try common signatures
		local fired = fireR(Remotes.Fire, origin, dir)
		if not fired then
			fired = fireR(Remotes.Fire, goal)
		end
		if not fired then
			fired = fireR(Remotes.Fire, CFrame.new(origin, goal))
		end
		if not fired then
			fireR(Remotes.Fire)
		end
	end
	doClick()
end

local function crosshairOnEnemy()
	local center = screenCenter()
	local ray = Camera:ViewportPointToRay(center.X, center.Y)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { LP.Character }
	local res = Workspace:Raycast(ray.Origin, ray.Direction * 8000, params)
	if not res or not res.Instance then return false end
	local model = res.Instance:FindFirstAncestorOfClass("Model")
	if not model then return false end
	local plr = Players:GetPlayerFromCharacter(model)
	if not plr or plr == LP then return false end
	if F.TeamCheck and sameTeam(plr) then return false end
	if not isAlive(plr) then return false end
	if F.TriggerFOVOnly then
		local pt = getPart(plr, F.AimPart)
		if pt then
			local sp, on = w2s(pt.Position)
			if not on or (sp - center).Magnitude > F.AimFOV then
				return false
			end
		end
	end
	return true, plr
end

-- hitbox
local origSizes = {}
local function applyHitbox(on)
	for _, plr in ipairs(Players:GetPlayers()) do
		if plr == LP then continue end
		if F.TeamCheck and sameTeam(plr) then continue end
		local c = getChar(plr)
		if not c then continue end
		for _, n in ipairs({ "Head", "UpperTorso", "HumanoidRootPart", "Torso", "LowerTorso" }) do
			local p = c:FindFirstChild(n)
			if p and p:IsA("BasePart") then
				local k = tostring(plr.UserId) .. n
				if on then
					if not origSizes[k] then
						origSizes[k] = p.Size
					end
					p.Size = Vector3.new(F.HitboxSize, F.HitboxSize, F.HitboxSize)
					p.CanCollide = false
				elseif origSizes[k] then
					p.Size = origSizes[k]
					origSizes[k] = nil
				end
			end
		end
	end
end

local noclipConn
local function setNoclip(on)
	if noclipConn then
		noclipConn:Disconnect()
		noclipConn = nil
	end
	if not on then return end
	noclipConn = RunService.Stepped:Connect(function()
		if not F.Noclip or not alive() then return end
		local c = LP.Character
		if not c then return end
		for _, p in ipairs(c:GetDescendants()) do
			if p:IsA("BasePart") then
				p.CanCollide = false
			end
		end
	end)
end

-- ===================== COMBAT LOOP =====================
local lastTrig, lastRage = 0, 0

RunService.RenderStepped:Connect(function()
	if not alive() then return end
	Camera = Workspace.CurrentCamera

	local rad = (F.Ragebot and F.RageFOV) or F.AimFOV
	local col = F.Ragebot and Color3.fromRGB(255, 80, 80) or Color3.fromRGB(255, 255, 255)
	local show = F.ShowFOV and (F.Aimbot or F.SilentAim or F.Ragebot or F.Triggerbot)
	setFOVVisible(show, rad, col)

	if F.Speed then
		local h = getHum(LP)
		if h then
			h.WalkSpeed = F.SpeedVal
		end
	end
	if F.Hitbox then
		applyHitbox(true)
	end
	if F.FullBright then
		Lighting.Brightness = 2
		Lighting.ClockTime = 14
		Lighting.GlobalShadows = false
	end
	if F.NoFog then
		Lighting.FogEnd = 9e9
	end

	silentPart = nil

	-- RAGE
	if F.Ragebot then
		local plr, pt = getTarget(F.RageFOV, F.RagePart, false)
		if plr and pt then
			curTarget = plr
			silentPart = pt
			local goalPos = predict(pt, F.AimPredict) or pt.Position
			local cam = Camera.CFrame
			local goal = CFrame.new(cam.Position, goalPos)
			local s = math.clamp(F.RageSmooth, 0, 0.9)
			Camera.CFrame = (s <= 0.02) and goal or cam:Lerp(goal, 1 - s)
			if (os.clock() - lastRage) >= F.RageFireRate then
				lastRage = os.clock()
				fireAt(pt)
			end
		end
	else
		-- AIMBOT + SILENT
		local wantAim = aimActive() or F.SilentAim
		if wantAim then
			local plr, pt = getTarget(F.AimFOV, F.AimPart, F.WallCheck)
			if plr and pt then
				curTarget = plr
				silentPart = pt
				if aimActive() then
					local goalPos = predict(pt, F.AimPredict) or pt.Position
					local cam = Camera.CFrame
					local goal = CFrame.new(cam.Position, goalPos)
					local s = math.clamp(F.AimSmooth, 0, 0.95)
					Camera.CFrame = (s <= 0.02) and goal or cam:Lerp(goal, 1 - s)
				end
			end
		end

		-- TRIGGER (uses screen CENTER ray — matches centered FOV)
		if F.Triggerbot and (os.clock() - lastTrig) >= F.TriggerDelay then
			local hit, enemy = crosshairOnEnemy()
			if hit then
				lastTrig = os.clock()
				local pt = enemy and getPart(enemy, F.AimPart)
				if pt then
					silentPart = pt
					fireAt(pt)
				else
					doClick()
				end
			end
		end
	end

	if F.AutoHeal and Remotes.Heal and (tick() % 2) < 0.05 then
		fireR(Remotes.Heal)
	end
	if F.AutoRepair and Remotes.Repair and (tick() % 2) < 0.05 then
		fireR(Remotes.Repair)
	end
end)

-- ===================== ESP LOOP =====================
RunService.Heartbeat:Connect(function()
	if not alive() then return end
	if not F.ESP then
		clearAllESP()
		return
	end

	local myHRP = getHRP(LP)
	local seen = {}

	for _, plr in ipairs(Players:GetPlayers()) do
		if plr == LP then continue end
		if F.EspEnemyOnly and sameTeam(plr) then
			clearESP(plr)
			continue
		end
		if not isAlive(plr) then
			clearESP(plr)
			continue
		end

		local rh = getHRP(plr)
		local hm = getHum(plr)
		local hd = getPart(plr, "Head")
		if not rh or not hm then
			clearESP(plr)
			continue
		end

		local dist = myHRP and (rh.Position - myHRP.Position).Magnitude or 0
		if dist > F.EspMax then
			clearESP(plr)
			continue
		end

		seen[plr] = true
		local t = ensureESP(plr)
		local isT = curTarget == plr
		local col = isT and Color3.fromRGB(255, 210, 40) or Color3.fromRGB(255, 60, 60)

		-- attach billboard to head
		local adorn = hd or rh
		if t.bb.Adornee ~= adorn then
			t.bb.Adornee = adorn
		end
		t.bb.MaxDistance = F.EspMax
		t.bb.Enabled = true

		if F.EspName then
			t.name.Text = plr.DisplayName or plr.Name
			t.name.TextColor3 = col
			t.name.Visible = true
		else
			t.name.Visible = false
		end

		local bits = {}
		if F.EspDist then
			table.insert(bits, math.floor(dist) .. "m")
		end
		if F.EspHP then
			table.insert(bits, math.floor(hm.Health) .. "HP")
		end
		t.info.Text = table.concat(bits, " | ")
		t.info.Visible = #bits > 0

		if F.EspHP then
			local ratio = math.clamp(hm.Health / math.max(hm.MaxHealth, 1), 0, 1)
			t.hpBar.Size = UDim2.new(ratio, 0, 1, 0)
			t.hpBar.BackgroundColor3 = Color3.fromRGB(255 * (1 - ratio) + 40, 255 * ratio, 50)
			t.hpBG.Visible = true
		else
			t.hpBG.Visible = false
		end

		if F.EspChams then
			local c = getChar(plr)
			if c then
				t.hl.Adornee = c
				t.hl.FillColor = col
				t.hl.Enabled = true
			end
		else
			t.hl.Enabled = false
		end

		if F.EspBox then
			t.box.Adornee = rh
			t.box.Size = Vector3.new(4, 6, 2)
			t.box.Color3 = col
			t.box.Visible = true
		else
			t.box.Visible = false
		end
	end

	for plr in pairs(espObjects) do
		if not seen[plr] then
			clearESP(plr)
		end
	end
end)

-- ===================== UI =====================
local Window = OrionLib:MakeWindow({
	Name = "Constipated Hub | Strike: Warfare GOD",
	HidePremium = true,
	SaveConfig = false,
	IntroEnabled = false,
})

local TabAim = Window:MakeTab({ Name = "Aimbot", Icon = "rbxassetid://4483345998", PremiumOnly = false })
local TabRage = Window:MakeTab({ Name = "Rage / Trigger", Icon = "rbxassetid://4483345998", PremiumOnly = false })
local TabESP = Window:MakeTab({ Name = "ESP", Icon = "rbxassetid://4483345998", PremiumOnly = false })
local TabMisc = Window:MakeTab({ Name = "Misc", Icon = "rbxassetid://4483345998", PremiumOnly = false })

TabAim:AddToggle({
	Name = "Aimbot",
	Default = false,
	Callback = function(v)
		F.Aimbot = v
	end,
})
TabAim:AddToggle({
	Name = "Silent Aim",
	Default = false,
	Callback = function(v)
		F.SilentAim = v
		hookSilent()
	end,
})
TabAim:AddToggle({
	Name = "Always On (recommended mobile)",
	Default = IS_MOBILE,
	Callback = function(v)
		F.AimAlwaysOn = v
	end,
})
TabAim:AddToggle({
	Name = "Sticky Aim",
	Default = true,
	Callback = function(v)
		F.StickyAim = v
	end,
})
TabAim:AddDropdown({
	Name = "Aim Part",
	Default = "Head",
	Options = { "Head", "UpperTorso", "HumanoidRootPart" },
	Callback = function(v)
		F.AimPart = v
	end,
})
TabAim:AddDropdown({
	Name = "Priority",
	Default = "FOV",
	Options = { "FOV", "Distance", "Health" },
	Callback = function(v)
		F.Priority = v
	end,
})
TabAim:AddSlider({
	Name = "FOV (center screen)",
	Min = 50,
	Max = 500,
	Default = 180,
	Increment = 5,
	Callback = function(v)
		F.AimFOV = v
	end,
})
TabAim:AddSlider({
	Name = "Smooth",
	Min = 0,
	Max = 0.8,
	Default = 0.15,
	Increment = 0.01,
	Callback = function(v)
		F.AimSmooth = v
	end,
})
TabAim:AddSlider({
	Name = "Prediction",
	Min = 0,
	Max = 0.35,
	Default = 0.1,
	Increment = 0.02,
	Callback = function(v)
		F.AimPredict = v
	end,
})
TabAim:AddToggle({
	Name = "Team Check",
	Default = true,
	Callback = function(v)
		F.TeamCheck = v
	end,
})
TabAim:AddToggle({
	Name = "Wall Check",
	Default = false,
	Callback = function(v)
		F.WallCheck = v
	end,
})
TabAim:AddToggle({
	Name = "Show FOV Circle",
	Default = true,
	Callback = function(v)
		F.ShowFOV = v
	end,
})
TabAim:AddLabel(IS_MOBILE and "Mobile: turn Always On + Aimbot" or "PC: hold RMB or enable Always On")

TabRage:AddSection({ Name = "Triggerbot" })
TabRage:AddToggle({
	Name = "Triggerbot",
	Default = false,
	Callback = function(v)
		F.Triggerbot = v
	end,
})
TabRage:AddSlider({
	Name = "Trigger Delay",
	Min = 0.02,
	Max = 0.25,
	Default = 0.05,
	Increment = 0.01,
	Callback = function(v)
		F.TriggerDelay = v
	end,
})
TabRage:AddToggle({
	Name = "Only if in FOV",
	Default = true,
	Callback = function(v)
		F.TriggerFOVOnly = v
	end,
})
TabRage:AddSection({ Name = "Ragebot" })
TabRage:AddToggle({
	Name = "Ragebot",
	Default = false,
	Callback = function(v)
		F.Ragebot = v
	end,
})
TabRage:AddDropdown({
	Name = "Rage Part",
	Default = "Head",
	Options = { "Head", "UpperTorso", "HumanoidRootPart" },
	Callback = function(v)
		F.RagePart = v
	end,
})
TabRage:AddSlider({
	Name = "Rage FOV",
	Min = 80,
	Max = 800,
	Default = 400,
	Increment = 10,
	Callback = function(v)
		F.RageFOV = v
	end,
})
TabRage:AddSlider({
	Name = "Rage Smooth",
	Min = 0,
	Max = 0.4,
	Default = 0.05,
	Increment = 0.01,
	Callback = function(v)
		F.RageSmooth = v
	end,
})
TabRage:AddSlider({
	Name = "Fire Rate",
	Min = 0.03,
	Max = 0.2,
	Default = 0.06,
	Increment = 0.01,
	Callback = function(v)
		F.RageFireRate = v
	end,
})
TabRage:AddToggle({
	Name = "Use FireRemote",
	Default = true,
	Callback = function(v)
		F.RageUseRemote = v
	end,
})

TabESP:AddToggle({
	Name = "ESP Enabled",
	Default = true,
	Callback = function(v)
		F.ESP = v
		if not v then
			clearAllESP()
		end
	end,
})
TabESP:AddToggle({
	Name = "Names",
	Default = true,
	Callback = function(v)
		F.EspName = v
	end,
})
TabESP:AddToggle({
	Name = "Distance",
	Default = true,
	Callback = function(v)
		F.EspDist = v
	end,
})
TabESP:AddToggle({
	Name = "Health Bar",
	Default = true,
	Callback = function(v)
		F.EspHP = v
	end,
})
TabESP:AddToggle({
	Name = "Chams (Highlight)",
	Default = true,
	Callback = function(v)
		F.EspChams = v
	end,
})
TabESP:AddToggle({
	Name = "3D Box",
	Default = true,
	Callback = function(v)
		F.EspBox = v
	end,
})
TabESP:AddToggle({
	Name = "Enemy Only",
	Default = true,
	Callback = function(v)
		F.EspEnemyOnly = v
	end,
})
TabESP:AddSlider({
	Name = "Max Distance",
	Min = 200,
	Max = 4000,
	Default = 2500,
	Increment = 100,
	Callback = function(v)
		F.EspMax = v
	end,
})
TabESP:AddLabel("ESP uses BillboardGui + Highlight (mobile safe)")

TabMisc:AddToggle({
	Name = "Hitbox Expander",
	Default = false,
	Callback = function(v)
		F.Hitbox = v
		if not v then
			applyHitbox(false)
		end
	end,
})
TabMisc:AddSlider({
	Name = "Hitbox Size",
	Min = 2,
	Max = 15,
	Default = 6,
	Increment = 0.5,
	Callback = function(v)
		F.HitboxSize = v
	end,
})
TabMisc:AddToggle({
	Name = "WalkSpeed",
	Default = false,
	Callback = function(v)
		F.Speed = v
	end,
})
TabMisc:AddSlider({
	Name = "Speed",
	Min = 16,
	Max = 50,
	Default = 26,
	Increment = 1,
	Callback = function(v)
		F.SpeedVal = v
	end,
})
TabMisc:AddToggle({
	Name = "Infinite Jump",
	Default = false,
	Callback = function(v)
		F.InfJump = v
	end,
})
TabMisc:AddToggle({
	Name = "Noclip",
	Default = false,
	Callback = function(v)
		F.Noclip = v
		setNoclip(v)
	end,
})
TabMisc:AddToggle({
	Name = "Full Bright",
	Default = false,
	Callback = function(v)
		F.FullBright = v
	end,
})
TabMisc:AddToggle({
	Name = "No Fog",
	Default = false,
	Callback = function(v)
		F.NoFog = v
	end,
})
TabMisc:AddSection({ Name = "Remotes" })
TabMisc:AddToggle({
	Name = "Auto Heal",
	Default = false,
	Callback = function(v)
		F.AutoHeal = v
	end,
})
TabMisc:AddToggle({
	Name = "Auto Repair",
	Default = false,
	Callback = function(v)
		F.AutoRepair = v
	end,
})
TabMisc:AddButton({
	Name = "Refresh Remotes",
	Callback = function()
		refreshRemotes()
		local n = 0
		for _, v in pairs(Remotes) do
			if v then
				n += 1
			end
		end
		OrionLib:MakeNotification({ Name = "Remotes", Content = n .. " bound", Time = 2 })
	end,
})
TabMisc:AddButton({
	Name = "Unload",
	Callback = function()
		GENV.__ConstipatedSW = GEN + 1
		F.Aimbot = false
		F.SilentAim = false
		F.Triggerbot = false
		F.Ragebot = false
		F.ESP = false
		F.Hitbox = false
		F.Noclip = false
		applyHitbox(false)
		setNoclip(false)
		clearAllESP()
		setFOVVisible(false, 0, Color3.new())
		if fovCircle then
			pcall(function()
				fovCircle:Remove()
			end)
		end
		pcall(function()
			fovGui:Destroy()
		end)
		pcall(function()
			espFolder:Destroy()
		end)
		OrionLib:Destroy()
	end,
})

OrionLib:MakeNotification({
	Name = "Constipated Hub",
	Content = IS_MOBILE and "Mobile mode — Always On aim + Billboard ESP" or "PC mode — hold RMB or Always On",
	Time = 5,
})

OrionLib:Init()
