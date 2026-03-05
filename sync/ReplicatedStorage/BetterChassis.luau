-- BetterChassis - Fork of A-Chassis (6.52S2) by Ransomwave
-- Provides a better, reusable chassis module for Roblox vehicles. Unlike the original A-Chassis, which is designed to be copy-pasted into each vehicle.

local BetterChassis = {}

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

type SelfType = {
	car: Model,
	config: ModuleScript,
	interface: typeof(script["A-Chassis Interface"]),
	Init: (SelfType) -> (),
	Drive: (SelfType) -> (),
	Destroy: (SelfType) -> (),
}

BetterChassis.Units = {}

function BetterChassis.new(
	car: Model,
	config: ModuleScript,
	interface: typeof(script["A-Chassis Interface"])?
): SelfType
	local self = {}

	self.car = car
	self.config = config
	self.interface = interface

	-- bookkeeping for cleanup
	self._connections = {} -- Connection objects to disconnect on Destroy
	self._destroyed = false -- flag to stop loops/listeners

	setmetatable(self, {
		__index = BetterChassis,
	})

	return (self :: any) :: SelfType
end

-- Utilities
local function makeWeld(x: BasePart, y: BasePart, type: string?, s: number?)
	local newWeld = Instance.new(if type then type else "Weld")
	newWeld.Part0 = x
	newWeld.Part1 = y
	newWeld.C0 = x.CFrame:inverse() * x.CFrame
	newWeld.C1 = y.CFrame:inverse() * x.CFrame
	if type == "Motor" and s ~= nil then newWeld.MaxVelocity = s end

	newWeld.Parent = x

	return newWeld
end

local function modelWeld(a, b)
	if a:IsA("BasePart") then
		makeWeld(b, a, "Weld")
	elseif a:IsA("Model") or a:IsA("Folder") then
		for i, v in pairs(a:GetChildren()) do
			modelWeld(v, b)
		end
	end
end

local function unAnchor(a)
	if a:IsA("BasePart") then a.Anchored = false end
	for i, v in pairs(a:GetChildren()) do
		unAnchor(v)
	end
end

--- Remove Existing Mass
local function dReduce(p)
	for i, v in pairs(p:GetChildren()) do
		if v:IsA("BasePart") then
			if v.CustomPhysicalProperties == nil then
				v.CustomPhysicalProperties = PhysicalProperties.new(v.Material)
			end
			v.CustomPhysicalProperties = PhysicalProperties.new(
				0.001,
				v.CustomPhysicalProperties.Friction,
				v.CustomPhysicalProperties.Elasticity,
				v.CustomPhysicalProperties.FrictionWeight,
				v.CustomPhysicalProperties.ElasticityWeight
			)
		end
		dReduce(v)
	end
end

--Store Reference Orientation Function
local function getParts(model, t, a)
	for i, v in pairs(model:GetChildren()) do
		if v:IsA("BasePart") then
			table.insert(t, { v, a.CFrame:toObjectSpace(v.CFrame) })
		elseif v:IsA("Model") or v:IsA("Folder") then
			getParts(v, t, a)
		end
	end
end

--- Function to get total mass of vehicle
function getMass(p)
	local totalMass = 0
	for i, v in pairs(p:GetChildren()) do
		if v:IsA("BasePart") then
			totalMass += v:GetMass()
		end
		getMass(v)
	end
	return totalMass
end

local function getSeats(p)
	local seatsResult = {}
	for _, v in pairs(p:GetChildren()) do
		if v:IsA("VehicleSeat") or v:IsA("Seat") then
			local seat = {}
			seat.Seat = v
			seat.Parts = {}
			table.insert(seatsResult, seat)
		end
		getSeats(v)
	end
	return seatsResult
end

--Store Physical Properties/Remove Mass Function
function getPProperties(mod, t)
	for _, v in pairs(mod:GetChildren()) do
		if v:IsA("BasePart") then
			if v.CustomPhysicalProperties == nil then
				v.CustomPhysicalProperties = PhysicalProperties.new(v.Material)
			end
			table.insert(t, { v, v.CustomPhysicalProperties })
			v.CustomPhysicalProperties = PhysicalProperties.new(
				0.001,
				v.CustomPhysicalProperties.Friction,
				v.CustomPhysicalProperties.Elasticity,
				v.CustomPhysicalProperties.FrictionWeight,
				v.CustomPhysicalProperties.ElasticityWeight
			)
		end
		getPProperties(v, t)
	end
end

--- Function to initialize chassis after tuning parameters have been set
function BetterChassis:Init()
	print(`Initializing BetterChassis on {self.car.Name}...`)

	self = self :: SelfType

	--[[Weld functions]]

	-- local JS = game:GetService("JointsService")
	local PGS_ON = workspace:PGSIsEnabled()

	--[[Initialize]]

	local interface = script:WaitForChild("A-Chassis Interface")
	self.interface = interface

	local pluginsFolder = script:WaitForChild("Plugins")

	local car = self.car
	local success, _Tune = pcall(require, self.config)
	if not success then
		warn(
			"Failed to load configuration module. Check for errors in the module script.",
			_Tune,
			if RunService:IsServer() then "Server" else "Client"
		)
		return
	end

	task.wait(_Tune.LoadDelay)

	--Weight Scaling
	local weightScaling = _Tune.WeightScaling
	if not workspace:PGSIsEnabled() then weightScaling = _Tune.LegacyScaling end

	local Drive = car.Wheels:GetChildren()

	dReduce(car)

	--[[Wheel Configuration]]

	--PGS/Legacy
	local fDensity = _Tune.FWheelDensity
	local rDensity = _Tune.RWheelDensity
	if not PGS_ON then
		fDensity = _Tune.FWLgcyDensity
		rDensity = _Tune.RWLgcyDensity
	end

	local fDistX = _Tune.FWsBoneLen * math.cos(math.rad(_Tune.FWsBoneAngle))
	local fDistY = _Tune.FWsBoneLen * math.sin(math.rad(_Tune.FWsBoneAngle))
	local rDistX = _Tune.RWsBoneLen * math.cos(math.rad(_Tune.RWsBoneAngle))
	local rDistY = _Tune.RWsBoneLen * math.sin(math.rad(_Tune.RWsBoneAngle))

	local fSLX = _Tune.FSusLength * math.cos(math.rad(_Tune.FSusAngle))
	local fSLY = _Tune.FSusLength * math.sin(math.rad(_Tune.FSusAngle))
	local rSLX = _Tune.RSusLength * math.cos(math.rad(_Tune.RSusAngle))
	local rSLY = _Tune.RSusLength * math.sin(math.rad(_Tune.RSusAngle))

	for _, v in pairs(Drive) do
		--Apply Wheel Density
		if v.Name == "FL" or v.Name == "FR" or v.Name == "F" then
			if v:IsA("BasePart") then
				if v.CustomPhysicalProperties == nil then
					v.CustomPhysicalProperties = PhysicalProperties.new(v.Material)
				end
				v.CustomPhysicalProperties = PhysicalProperties.new(
					fDensity,
					v.CustomPhysicalProperties.Friction,
					v.CustomPhysicalProperties.Elasticity,
					v.CustomPhysicalProperties.FrictionWeight,
					v.CustomPhysicalProperties.ElasticityWeight
				)
			end
		else
			if v:IsA("BasePart") then
				if v.CustomPhysicalProperties == nil then
					v.CustomPhysicalProperties = PhysicalProperties.new(v.Material)
				end
				v.CustomPhysicalProperties = PhysicalProperties.new(
					rDensity,
					v.CustomPhysicalProperties.Friction,
					v.CustomPhysicalProperties.Elasticity,
					v.CustomPhysicalProperties.FrictionWeight,
					v.CustomPhysicalProperties.ElasticityWeight
				)
			end
		end

		--Resurface Wheels
		-- for _,a in pairs({"Top","Bottom","Left","Right","Front","Back"}) do
		-- 	v[a.."Surface"]=Enum.SurfaceType.SmoothNoOutlines
		-- end

		--Store Axle-Anchored/Suspension-Anchored Part Orientation
		local WParts = {}

		local tPos = v.Position - car.DriveSeat.Position
		if v.Name == "FL" or v.Name == "RL" then
			v.CFrame = car.DriveSeat.CFrame * CFrame.Angles(math.rad(90), 0, math.rad(90))
		else
			v.CFrame = car.DriveSeat.CFrame * CFrame.Angles(math.rad(90), 0, math.rad(-90))
		end
		v.CFrame = v.CFrame + tPos

		if v:FindFirstChild("Parts") ~= nil then getParts(v.Parts, WParts, v) end
		if v:FindFirstChild("Fixed") ~= nil then getParts(v.Fixed, WParts, v) end

		--Align Wheels
		if v.Name == "FL" or v.Name == "FR" then
			v.CFrame = v.CFrame * CFrame.Angles(math.rad(_Tune.FCamber), 0, 0)
			if v.Name == "FL" then
				v.CFrame = v.CFrame * CFrame.Angles(0, 0, math.rad(_Tune.FToe))
			else
				v.CFrame = v.CFrame * CFrame.Angles(0, 0, math.rad(-_Tune.FToe))
			end
		elseif v.Name == "RL" or v.Name == "RR" then
			v.CFrame = v.CFrame * CFrame.Angles(math.rad(_Tune.RCamber), 0, 0)
			if v.Name == "RL" then
				v.CFrame = v.CFrame * CFrame.Angles(0, 0, math.rad(_Tune.RToe))
			else
				v.CFrame = v.CFrame * CFrame.Angles(0, 0, math.rad(-_Tune.RToe))
			end
		end

		--Re-orient Axle-Anchored/Suspension-Anchored Parts
		for _, a in pairs(WParts) do
			a[1].CFrame = v.CFrame:toWorldSpace(a[2])
		end

		--[[Chassis Assembly]]
		--Create Steering Axle
		local arm = Instance.new("Part", v)
		arm.Name = "Arm"
		arm.Anchored = true
		arm.CanCollide = false
		arm.FormFactor = Enum.FormFactor.Custom
		arm.Size = Vector3.new(_Tune.AxleSize, _Tune.AxleSize, _Tune.AxleSize)
		arm.CFrame = (v.CFrame * CFrame.new(0, _Tune.StAxisOffset, 0)) * CFrame.Angles(-math.pi / 2, -math.pi / 2, 0)
		arm.CustomPhysicalProperties = PhysicalProperties.new(_Tune.AxleDensity, 0, 0, 100, 100)
		arm.TopSurface = Enum.SurfaceType.Smooth
		arm.BottomSurface = Enum.SurfaceType.Smooth
		arm.Transparency = 1

		--Create Wheel Spindle
		local base = arm:Clone()
		base.Parent = v
		base.Name = "Base"
		base.CFrame = base.CFrame * CFrame.new(0, _Tune.AxleSize, 0)
		base.BottomSurface = Enum.SurfaceType.Hinge

		--Create Steering Anchor
		local axle = arm:Clone()
		axle.Parent = v
		axle.Name = "Axle"
		axle.CFrame = CFrame.new(
			v.Position
				- ((v.CFrame * CFrame.Angles(math.pi / 2, 0, 0)).lookVector * ((v.Size.x / 2) + (axle.Size.x / 2))),
			v.Position
		) * CFrame.Angles(0, math.pi, 0)
		axle.BackSurface = Enum.SurfaceType.Hinge

		if v.Name == "F" or v.Name == "R" then
			local axle2 = arm:Clone()
			axle2.Parent = v
			axle2.Name = "Axle"
			axle2.CFrame = CFrame.new(
				v.Position
					+ ((v.CFrame * CFrame.Angles(math.pi / 2, 0, 0)).lookVector * ((v.Size.x / 2) + (axle2.Size.x / 2))),
				v.Position
			) * CFrame.Angles(0, math.pi, 0)
			axle2.BackSurface = Enum.SurfaceType.Hinge
			makeWeld(arm, axle2)
		end

		--Create Suspension
		if PGS_ON and _Tune.SusEnabled then
			local sa = arm:Clone()
			sa.Parent = v
			sa.Name = "#SA"
			if v.Name == "FL" or v.Name == "FR" or v.Name == "F" then
				local aOff = _Tune.FAnchorOffset
				sa.CFrame = v.CFrame
					* CFrame.new(_Tune.AxleSize / 2, -fDistX, -fDistY)
					* CFrame.new(aOff[3], aOff[1], -aOff[2])
					* CFrame.Angles(-math.pi / 2, -math.pi / 2, 0)
			else
				local aOff = _Tune.RAnchorOffset
				sa.CFrame = v.CFrame
					* CFrame.new(_Tune.AxleSize / 2, -rDistX, -rDistY)
					* CFrame.new(aOff[3], aOff[1], -aOff[2])
					* CFrame.Angles(-math.pi / 2, -math.pi / 2, 0)
			end

			local sb = sa:Clone()
			sb.Parent = v
			sb.Name = "#SB"
			sb.CFrame = sa.CFrame * CFrame.new(0, 0, _Tune.AxleSize)

			sb.FrontSurface = Enum.SurfaceType.Hinge

			local g = Instance.new("BodyGyro", sb)
			g.Name = "Stabilizer"
			g.MaxTorque = Vector3.new(0, 0, 1)
			g.P = 0

			local sf1 = Instance.new("Attachment", sa)
			sf1.Name = "SAtt"

			local sf2 = sf1:Clone()
			sf2.Parent = sb

			if v.Name == "FL" or v.Name == "FR" or v.Name == "F" then
				sf1.Position = Vector3.new(fDistX - fSLX, -fDistY + fSLY, _Tune.AxleSize / 2)
				sf2.Position = Vector3.new(fDistX, -fDistY, -_Tune.AxleSize / 2)
			elseif v.Name == "RL" or v.Name == "RR" or v.Name == "R" then
				sf1.Position = Vector3.new(rDistX - rSLX, -rDistY + rSLY, _Tune.AxleSize / 2)
				sf2.Position = Vector3.new(rDistX, -rDistY, -_Tune.AxleSize / 2)
			end

			sb:MakeJoints()

			local sp = Instance.new("SpringConstraint", v)
			sp.Name = "Spring"
			sp.Attachment0 = sf1
			sp.Attachment1 = sf2
			sp.LimitsEnabled = true

			sp.Visible = _Tune.SusVisible
			sp.Radius = _Tune.SusRadius
			sp.Thickness = _Tune.SusThickness
			sp.Color = BrickColor.new(_Tune.SusColor)
			sp.Coils = _Tune.SusCoilCount

			if v.Name == "FL" or v.Name == "FR" or v.Name == "F" then
				g.D = _Tune.FAntiRoll
				sp.Damping = _Tune.FSusDamping
				sp.Stiffness = _Tune.FSusStiffness
				sp.FreeLength = _Tune.FSusLength + _Tune.FPreCompress
				sp.MaxLength = _Tune.FSusLength + _Tune.FExtensionLim
				sp.MinLength = _Tune.FSusLength - _Tune.FCompressLim
			else
				-- g.D = _Tune.RAntiRoll
				sp.Damping = _Tune.RSusDamping
				sp.Stiffness = _Tune.RSusStiffness
				sp.FreeLength = _Tune.RSusLength + _Tune.RPreCompress
				sp.MaxLength = _Tune.RSusLength + _Tune.RExtensionLim
				sp.MinLength = _Tune.RSusLength - _Tune.RCompressLim
			end

			makeWeld(car.DriveSeat, sa)
			makeWeld(sb, base)
		else
			makeWeld(car.DriveSeat, base)
		end

		--Lock Rear Steering Axle
		if v.Name == "RL" or v.Name == "RR" or v.Name == "R" then makeWeld(base, axle) end

		--Weld Assembly
		if v.Parent.Name == "RL" or v.Parent.Name == "RR" or v.Name == "R" then makeWeld(car.DriveSeat, arm) end

		makeWeld(arm, axle)

		arm:MakeJoints()
		axle:MakeJoints()

		--Weld Miscelaneous Parts
		if v:FindFirstChild("SuspensionFixed") ~= nil then modelWeld(v.SuspensionFixed, car.DriveSeat) end
		if v:FindFirstChild("WheelFixed") ~= nil then modelWeld(v.WheelFixed, axle) end
		if v:FindFirstChild("Fixed") ~= nil then modelWeld(v.Fixed, arm) end

		--Weld Wheel Parts
		if v:FindFirstChild("Parts") ~= nil then modelWeld(v.Parts, v) end

		--Add Steering Gyro
		if v:FindFirstChild("Steer") then v:FindFirstChild("Steer"):Destroy() end

		if v.Name == "FL" or v.Name == "FR" or v.Name == "F" then
			local steer = Instance.new("BodyGyro", arm)
			steer.Name = "Steer"
			steer.P = _Tune.SteerP
			steer.D = _Tune.SteerD
			steer.MaxTorque = Vector3.new(0, _Tune.SteerMaxTorque, 0)
			steer.cframe = v.CFrame * CFrame.Angles(0, -math.pi / 2, 0)
		end

		--Add Stabilization Gyro
		local gyro = Instance.new("BodyGyro", v)
		gyro.Name = "Stabilizer"
		gyro.MaxTorque = Vector3.new(1, 0, 1)
		gyro.P = 0
		if v.Name == "FL" or v.Name == "FR" or v.Name == "F" then
			gyro.D = _Tune.FGyroDamp
		else
			gyro.D = _Tune.RGyroDamp
		end

		--Add Rotational BodyMover
		local AV = Instance.new("BodyAngularVelocity", v)
		AV.Name = "#AV"
		AV.angularvelocity = Vector3.new(0, 0, 0)
		AV.maxTorque = Vector3.new(_Tune.PBrakeForce, 0, _Tune.PBrakeForce)
		AV.P = 1e9
	end

	--[[Vehicle Weight]]
	--Determine Current Mass
	local mass = 0

	mass = getMass(car)

	--Apply Vehicle Weight
	if mass < _Tune.Weight * weightScaling then
		--Calculate Weight Distribution
		local centerF = Vector3.new()
		local centerR = Vector3.new()
		local countF = 0
		local countR = 0

		for i, v in pairs(Drive) do
			if v.Name == "FL" or v.Name == "FR" or v.Name == "F" then
				centerF = centerF + v.CFrame.p
				countF = countF + 1
			else
				centerR = centerR + v.CFrame.p
				countR = countR + 1
			end
		end
		centerF = centerF / countF
		centerR = centerR / countR
		local center = centerR:Lerp(centerF, _Tune.WeightDist / 100)

		--Create Weight Brick
		local weightB = Instance.new("Part", car.Body)
		weightB.Name = "#Weight"
		weightB.Anchored = true
		weightB.CanCollide = false
		weightB.BrickColor = BrickColor.new("Really black")
		weightB.TopSurface = Enum.SurfaceType.Smooth
		weightB.BottomSurface = Enum.SurfaceType.Smooth
		if _Tune.WBVisible then
			weightB.Transparency = 0.75
		else
			weightB.Transparency = 1
		end
		weightB.Size = Vector3.new(_Tune.WeightBSize[1], _Tune.WeightBSize[2], _Tune.WeightBSize[3])
		weightB.CustomPhysicalProperties = PhysicalProperties.new(
			((_Tune.Weight * weightScaling) - mass) / (weightB.Size.x * weightB.Size.y * weightB.Size.z),
			0,
			0,
			0,
			0
		)
		weightB.CFrame = (car.DriveSeat.CFrame - car.DriveSeat.Position + center) * CFrame.new(0, _Tune.CGHeight, 0)
	else
		--Existing Weight Is Too Massive
		warn(
			"\n\t []: Mass too high for specified weight."
				.. "\n\t    Target Mass:\t"
				.. (math.ceil(_Tune.Weight * weightScaling * 100) / 100)
				.. "\n\t    Current Mass:\t"
				.. (math.ceil(mass * 100) / 100)
				.. "\n\t Reduce part size or axle density to achieve desired weight."
		)
	end

	local flipG = Instance.new("BodyGyro", car.DriveSeat)
	flipG.Name = "Flip"
	flipG.D = 0
	flipG.MaxTorque = Vector3.new(0, 0, 0)
	flipG.P = 0

	--[[Finalize Chassis]]
	--Misc Weld
	task.wait()
	for i, v in pairs(script:GetChildren()) do
		if v:IsA("ModuleScript") then require(v) end
	end

	--Weld Body
	task.wait()
	modelWeld(car.Body, car.DriveSeat)

	--Unanchor
	task.wait()
	unAnchor(car)

	--[[Manage Plugins]]

	interface.Car.Value = car
	for _, pluginV in pairs(pluginsFolder:GetChildren()) do
		for _, event in pairs(pluginV:GetChildren()) do
			if event:IsA("BaseRemoteEvent") or event:IsA("RemoteFunction") then
				local eventClone = event:Clone()
				eventClone.Parent = car
				for _, script in pairs(eventClone:GetChildren()) do
					if script:IsA("Script") then script.Disabled = false end
				end
			end
		end

		if interface:FindFirstChild(pluginV.Name) then continue end

		local pluginClone = pluginV:Clone()
		pluginClone.Parent = interface
	end
	-- pluginsFolder:Destroy()

	--[[Remove Character Weight]]
	--Get Seats
	local Seats = {}
	Seats = getSeats(car)

	--Apply Seat Handler
	for i, v in pairs(Seats) do
		--Sit Handler
		do
			local conn = v.Seat.ChildAdded:Connect(function(child)
				if
					child.Name == "SeatWeld"
					and child:IsA("Weld")
					and child.Part1 ~= nil
					and child.Part1.Parent ~= workspace
					and not child.Part1.Parent:IsDescendantOf(car)
				then
					v.Parts = {}
					getPProperties(child.Part1.Parent, v.Parts)
				end
			end)
			table.insert(self._connections, conn)
		end

		--Leave Handler
		do
			local conn = v.Seat.ChildRemoved:Connect(function(child)
				if child.Name == "SeatWeld" and child:IsA("Weld") then
					for i, v in pairs(v.Parts) do
						if v[1] ~= nil and v[2] ~= nil and v[1]:IsDescendantOf(workspace) then
							v[1].CustomPhysicalProperties = v[2]
						end
					end
					v.Parts = {}
				end
			end)
			table.insert(self._connections, conn)
		end
	end

	--[[Driver Handling]]

	--Driver Sit
	do
		local conn = car.DriveSeat.ChildAdded:Connect(function(child)
			if
				child.Name == "SeatWeld"
				and child:IsA("Weld")
				and Players:GetPlayerFromCharacter(child.Part1.Parent) ~= nil
			then
				--Distribute Client Interface
				local p = Players:GetPlayerFromCharacter(child.Part1.Parent)
				car.DriveSeat:SetNetworkOwner(p)
				local g = interface:Clone()
				g.Parent = p.PlayerGui
			end
		end)
		table.insert(self._connections, conn)
	end

	--Driver Leave
	-- do
	-- 	local conn = car.DriveSeat.ChildRemoved:Connect(function(child)
	-- 		if child.Name == "SeatWeld" and child:IsA("Weld") then
	-- 			--Remove Flip Force
	-- 			if car.DriveSeat:FindFirstChild("Flip") ~= nil then car.DriveSeat.Flip.MaxTorque = Vector3.new() end

	-- 			--Remove Wheel Force
	-- 			for i, v in pairs(car.Wheels:GetChildren()) do
	-- 				if v:FindFirstChild("#AV") ~= nil then
	-- 					if v["#AV"]:IsA("BodyAngularVelocity") then
	-- 						if v["#AV"].AngularVelocity.Magnitude > 0 then
	-- 							v["#AV"].AngularVelocity = Vector3.new()
	-- 							v["#AV"].MaxTorque = Vector3.new()
	-- 						end
	-- 					else
	-- 						if v["#AV"].AngularVelocity > 0 then
	-- 							v["#AV"].AngularVelocity = 0
	-- 							v["#AV"].MotorMaxTorque = 0
	-- 						end
	-- 					end
	-- 				end
	-- 			end
	-- 		end
	-- 	end)
	-- 	table.insert(self._connections, conn)
	-- end
end

function BetterChassis:Drive()
	if RunService:IsServer() then
		warn("Drive function must be called on the client.")
		return
	end

	print(`Driving BetterChassis on {self.car.Name}...`)

	self = self :: SelfType

	--[[START]]

	local interface = self.interface

	interface:WaitForChild("Car")
	interface:WaitForChild("IsOn")
	interface:WaitForChild("ControlsOpen")
	interface:WaitForChild("Values")

	--[[Dependencies]]

	local player = Players.LocalPlayer
	local mouse = player:GetMouse()
	local RunService = game:GetService("RunService")
	local UserInputService = game:GetService("UserInputService")
	local car = self.car

	local _Tune = self.config

	-- local success, _Tune = pcall(require, self.config)
	-- if not success then
	-- 	warn("Failed to load configuration module. Check for errors in the module script.", _Tune, self.config)
	-- 	return
	-- end

	--[[Output Scaling Factor]]

	local hpScaling = _Tune.WeightScaling * 10
	local FBrakeForce = _Tune.FBrakeForce
	local RBrakeForce = _Tune.RBrakeForce
	local PBrakeForce = _Tune.PBrakeForce
	if not workspace:PGSIsEnabled() then
		hpScaling = _Tune.LegacyScaling * 10
		FBrakeForce = _Tune.FLgcyBForce
		RBrakeForce = _Tune.RLgcyBForce
		PBrakeForce = _Tune.LgcyPBForce
	end

	--[[Status Vars]]

	local _IsOn = _Tune.AutoStart
	if _Tune.AutoStart then interface.IsOn.Value = true end

	local _GSteerT = 0
	local _GSteerC = 0
	local _GThrot = 0
	local _GBrake = 0

	local _ClutchOn = true
	local _ClPressing = false
	local _RPM = 0
	local _HP = 0
	local _OutTorque = 0
	local _CGear = 0
	local _PGear = _CGear
	local _spLimit = 0

	local _TMode: "Auto" | "Manual" | "Semi" = _Tune.TransModes[1]

	local _MSteer = false
	local _SteerL = false
	local _SteerR = false
	local _PBrake = false
	local _TCS = _Tune.TCSEnabled
	local _TCSActive = false
	local _ABS = _Tune.ABSEnabled
	local _ABSActive = false

	local FlipWait = tick()
	local FlipDB = false

	local _InControls = false

	--[[Shutdown]]
	local driveSeat = car:WaitForChild("DriveSeat")

	do
		local conn = driveSeat.ChildRemoved:Connect(function(child)
			if child.Name == "SeatWeld" and child:IsA("Weld") then
				if interface and interface.Parent then pcall(function()
					interface:Destroy()
				end) end
				if self and self.Destroy then pcall(function()
					self:Destroy()
				end) end
			end
		end)
		table.insert(self._connections, conn)
	end

	--[[Controls]]

	local _CTRL = _Tune.Controls
	local Controls = Instance.new("Folder", interface)
	Controls.Name = "Controls"
	for i, v in pairs(_CTRL) do
		local a = Instance.new("StringValue", Controls)
		a.Name = i
		a.Value = v.Name
		local conn = a.Changed:Connect(function()
			if i == "MouseThrottle" or i == "MouseBrake" then
				if a.Value == "MouseButton1" or a.Value == "MouseButton2" then
					_CTRL[i] = Enum.UserInputType[a.Value]
				else
					_CTRL[i] = Enum.KeyCode[a.Value]
				end
			else
				_CTRL[i] = Enum.KeyCode[a.Value]
			end
		end)
		table.insert(self._connections, conn)
	end

	--Deadzone Adjust
	local _PPH = _Tune.Peripherals
	for i, v in pairs(_PPH) do
		local a = Instance.new("IntValue", Controls)
		a.Name = i
		a.Value = v
		local conn = a.Changed:Connect(function()
			a.Value = math.min(100, math.max(0, a.Value))
			_PPH[i] = a.Value
		end)
		table.insert(self._connections, conn)
	end

	--Input Handler
	local function dealWithInput(input, IsRobloxFunction)
		if (UserInputService:GetFocusedTextBox() == nil) and not _InControls then --Ignore when UI Focus
			--Shift Down [Manual Transmission]
			if
				_IsOn
				and (input.KeyCode == _CTRL["ContlrShiftDown"] or (_MSteer and input.KeyCode == _CTRL["MouseShiftDown"]) or ((not _MSteer) and input.KeyCode == _CTRL["ShiftDown"]))
				and (_TMode == "Semi" or (_TMode == "Manual" and not _ClutchOn))
				and input.UserInputState == Enum.UserInputState.Begin
			then
				if _CGear == 0 and ((_TMode :: "Auto" | "Manual" | "Semi") == "Auto" or not _ClPressing) then
					_ClutchOn = true
				end
				_CGear = math.max(_CGear - 1, -1)

			--Shift Up [Manual Transmission]
			elseif
				_IsOn
				and (input.KeyCode == _CTRL["ContlrShiftUp"] or (_MSteer and input.KeyCode == _CTRL["MouseShiftUp"]) or ((not _MSteer) and input.KeyCode == _CTRL["ShiftUp"]))
				and (_TMode == "Semi" or (_TMode == "Manual" and not _ClutchOn))
				and input.UserInputState == Enum.UserInputState.Begin
			then
				if _CGear == 0 and ((_TMode :: "Auto" | "Manual" | "Semi") == "Auto" or not _ClPressing) then
					_ClutchOn = true
				end
				_CGear = math.min(_CGear + 1, #_Tune.Ratios - 2)

			--Toggle Clutch
			elseif
				_IsOn
				and (input.KeyCode == _CTRL["ContlrClutch"] or (_MSteer and input.KeyCode == _CTRL["MouseClutch"]) or ((not _MSteer) and input.KeyCode == _CTRL["Clutch"]))
				and _TMode == "Manual"
			then
				if input.UserInputState == Enum.UserInputState.Begin then
					_ClutchOn = false
					_ClPressing = true
				elseif input.UserInputState == Enum.UserInputState.End then
					_ClutchOn = true
					_ClPressing = false
				end

			--Toggle PBrake
			elseif
				_IsOn and input.KeyCode == _CTRL["ContlrPBrake"]
				or (_MSteer and input.KeyCode == _CTRL["MousePBrake"])
				or ((not _MSteer) and input.KeyCode == _CTRL["PBrake"])
			then
				if input.UserInputState == Enum.UserInputState.Begin then
					_PBrake = not _PBrake
				elseif input.UserInputState == Enum.UserInputState.End then
					if driveSeat.Velocity.Magnitude > 5 then _PBrake = false end
				end

			--Toggle Transmission Mode
			elseif
				(input.KeyCode == _CTRL["ContlrToggleTMode"] or input.KeyCode == _CTRL["ToggleTransMode"])
				and input.UserInputState == Enum.UserInputState.Begin
			then
				local n = 1
				for i, v in pairs(_Tune.TransModes) do
					if v == _TMode then
						n = i
						break
					end
				end
				n = n + 1
				if n > #_Tune.TransModes then n = 1 end
				_TMode = _Tune.TransModes[n]

			--Throttle
			elseif
				_IsOn
					and ((not _MSteer) and (input.KeyCode == _CTRL["Throttle"] or input.KeyCode == _CTRL["Throttle2"]))
				or (
					(
						(
							(
								_CTRL["MouseThrottle"] == Enum.UserInputType.MouseButton1
								or _CTRL["MouseThrottle"] == Enum.UserInputType.MouseButton2
							) and input.UserInputType == _CTRL["MouseThrottle"]
						) or input.KeyCode == _CTRL["MouseThrottle"]
					) and _MSteer
				)
			then
				if input.UserInputState == Enum.UserInputState.Begin then
					_GThrot = 1
				else
					_GThrot = _Tune.IdleThrottle / 100
				end

			--Brake
			elseif
				((not _MSteer) and (input.KeyCode == _CTRL["Brake"] or input.KeyCode == _CTRL["Brake2"]))
				or (
					(
						(
							(
								_CTRL["MouseBrake"] == Enum.UserInputType.MouseButton1
								or _CTRL["MouseBrake"] == Enum.UserInputType.MouseButton2
							) and input.UserInputType == _CTRL["MouseBrake"]
						) or input.KeyCode == _CTRL["MouseBrake"]
					) and _MSteer
				)
			then
				if input.UserInputState == Enum.UserInputState.Begin then
					_GBrake = 1
				else
					_GBrake = 0
				end

			--Steer Left
			elseif (not _MSteer) and (input.KeyCode == _CTRL["SteerLeft"] or input.KeyCode == _CTRL["SteerLeft2"]) then
				if input.UserInputState == Enum.UserInputState.Begin then
					_GSteerT = -1
					_SteerL = true
				else
					if _SteerR then
						_GSteerT = 1
					else
						_GSteerT = 0
					end
					_SteerL = false
				end

			--Steer Right
			elseif not _MSteer and (input.KeyCode == _CTRL["SteerRight"] or input.KeyCode == _CTRL["SteerRight2"]) then
				if input.UserInputState == Enum.UserInputState.Begin then
					_GSteerT = 1
					_SteerR = true
				else
					if _SteerL then
						_GSteerT = -1
					else
						_GSteerT = 0
					end
					_SteerR = false
				end

			--Toggle Mouse Controls
			elseif input.KeyCode == _CTRL["ToggleMouseDrive"] then
				if input.UserInputState == Enum.UserInputState.End then
					_MSteer = not _MSteer
					_GThrot = _Tune.IdleThrottle / 100
					_GBrake = 0
					_GSteerT = 0
					_ClutchOn = true
				end

			--Toggle TCS
			elseif
				_Tune.TCSEnabled and _IsOn and input.KeyCode == _CTRL["ToggleTCS"]
				or input.KeyCode == _CTRL["ContlrToggleTCS"]
			then
				if input.UserInputState == Enum.UserInputState.End then _TCS = not _TCS end

			--Toggle ABS
			elseif
				_Tune.ABSEnabled and _IsOn and input.KeyCode == _CTRL["ToggleABS"]
				or input.KeyCode == _CTRL["ContlrToggleABS"]
			then
				if input.UserInputState == Enum.UserInputState.End then _ABS = not _ABS end
			end

			--Variable Controls
			if input.UserInputType.Name:find("Gamepad") then
				--Gamepad Steering
				if input.KeyCode == _CTRL["ContlrSteer"] then
					if input.Position.X >= 0 then
						local cDZone = math.min(0.99, _Tune.Peripherals.ControlRDZone / 100)
						if math.abs(input.Position.X) > cDZone then
							_GSteerT = (input.Position.X - cDZone) / (1 - cDZone)
						else
							_GSteerT = 0
						end
					else
						local cDZone = math.min(0.99, _Tune.Peripherals.ControlLDZone / 100)
						if math.abs(input.Position.X) > cDZone then
							_GSteerT = (input.Position.X + cDZone) / (1 - cDZone)
						else
							_GSteerT = 0
						end
					end

				--Gamepad Throttle
				elseif _IsOn and input.KeyCode == _CTRL["ContlrThrottle"] then
					_GThrot = math.max(_Tune.IdleThrottle / 100, input.Position.Z)

				--Gamepad Brake
				elseif input.KeyCode == _CTRL["ContlrBrake"] then
					_GBrake = input.Position.Z
				end
			end
		else
			_GThrot = _Tune.IdleThrottle / 100
			_GSteerT = 0
			_GBrake = 0
			if _CGear ~= 0 then _ClutchOn = true end
		end
	end
	table.insert(self._connections, UserInputService.InputBegan:Connect(dealWithInput))
	table.insert(self._connections, UserInputService.InputChanged:Connect(dealWithInput))
	table.insert(self._connections, UserInputService.InputEnded:Connect(dealWithInput))

	if UserInputService.PreferredInput == Enum.PreferredInput.Touch then
		print(`{script} :: {player}'s preferred input is touch.`)

		local mobileControls = player.PlayerGui:WaitForChild("Mobile")
		mobileControls.Enabled = true

		local buttons = mobileControls:WaitForChild("Buttons")
		local accelerationButtons = buttons:WaitForChild("AccelerationButtons")
		local directionButtons = buttons:WaitForChild("DirectionButtons")

		local accelerate = accelerationButtons:WaitForChild("Accelerate")
		local decelerate = accelerationButtons:WaitForChild("Decelerate")
		local left = directionButtons:WaitForChild("Left")
		local right = directionButtons:WaitForChild("Right")

		if UserInputService.TouchEnabled and not UserInputService.MouseEnabled then buttons.Visible = true end
		local function LeftTurn(Touch, GPE)
			if Touch.UserInputState == Enum.UserInputState.Begin then
				_GSteerT = -1
				_SteerL = true
			else
				if _SteerR then
					_GSteerT = 1
				else
					_GSteerT = 0
				end
				_SteerL = false
			end
		end
		left.InputBegan:Connect(LeftTurn)
		left.InputEnded:Connect(LeftTurn)
		--Left.InputChanged:Connect(LeftTurn)

		local function RightTurn(Touch, GPE)
			if Touch.UserInputState == Enum.UserInputState.Begin then
				_GSteerT = 1
				_SteerR = true
			else
				if _SteerL then
					_GSteerT = -1
				else
					_GSteerT = 0
				end
				_SteerR = false
			end
		end
		right.InputBegan:Connect(RightTurn)
		right.InputEnded:Connect(RightTurn)
		--Right.InputChanged:Connect(RightTurn)

		local function TouchThrottle(input, GPE)
			if input.UserInputState == Enum.UserInputState.Begin and _IsOn then
				_GThrot = 1
			else
				_GThrot = _Tune.IdleThrottle / 100
			end
		end
		accelerate.InputBegan:Connect(TouchThrottle)
		accelerate.InputEnded:Connect(TouchThrottle)
		--Gas.InputChanged:Connect(TouchThrottle)

		local function TouchBrake(input, GPE)
			if input.UserInputState == Enum.UserInputState.Begin then
				_GBrake = 1
			else
				_GBrake = 0
			end
		end
		decelerate.InputBegan:Connect(TouchBrake)
		decelerate.InputEnded:Connect(TouchBrake)
		--Brake.InputChanged:Connect(TouchBrake)
	end

	--[[Drivetrain Initialize]]

	local Drive = {}

	--Power Front Wheels
	if _Tune.Config == "FWD" or _Tune.Config == "AWD" then
		for i, v in pairs(car.Wheels:GetChildren()) do
			if v.Name == "FL" or v.Name == "FR" or v.Name == "F" then table.insert(Drive, v) end
		end
	end

	--Power Rear Wheels
	if _Tune.Config == "RWD" or _Tune.Config == "AWD" then
		for i, v in pairs(car.Wheels:GetChildren()) do
			if v.Name == "RL" or v.Name == "RR" or v.Name == "R" then table.insert(Drive, v) end
		end
	end

	--Determine Wheel Size
	local wDia = 0
	for i, v in pairs(Drive) do
		if v.Size.x > wDia then wDia = v.Size.x end
	end

	--Pre-Toggled PBrake
	for i, v in pairs(car.Wheels:GetChildren()) do
		if v["#AV"]:IsA("BodyAngularVelocity") then
			if math.abs(v["#AV"].maxTorque.Magnitude - PBrakeForce) < 1 then _PBrake = true end
		else
			if math.abs(v["#AV"].MotorMaxTorque - PBrakeForce) < 1 then _PBrake = true end
		end
	end

	--[[Steering]]

	local function Steering()
		--Mouse Steer
		if _MSteer then
			local msWidth = math.max(1, mouse.ViewSizeX * _Tune.Peripherals.MSteerWidth / 200)
			local mdZone = _Tune.Peripherals.MSteerDZone / 100
			local mST = ((mouse.X - mouse.ViewSizeX / 2) / msWidth)
			if math.abs(mST) <= mdZone then
				_GSteerT = 0
			else
				_GSteerT = (math.max(math.min((math.abs(mST) - mdZone), (1 - mdZone)), 0) / (1 - mdZone))
						^ _Tune.MSteerExp
					* (mST / math.abs(mST))
			end
		end

		--Interpolate Steering
		if _GSteerC < _GSteerT then
			if _GSteerC < 0 then
				_GSteerC = math.min(_GSteerT, _GSteerC + _Tune.ReturnSpeed)
			else
				_GSteerC = math.min(_GSteerT, _GSteerC + _Tune.SteerSpeed)
			end
		else
			if _GSteerC > 0 then
				_GSteerC = math.max(_GSteerT, _GSteerC - _Tune.ReturnSpeed)
			else
				_GSteerC = math.max(_GSteerT, _GSteerC - _Tune.SteerSpeed)
			end
		end

		--Steer Decay Multiplier
		local sDecay = (1 - math.min(driveSeat.Velocity.Magnitude / _Tune.SteerDecay, 1 - (_Tune.MinSteer / 100)))

		--Apply Steering
		for i, v in pairs(car.Wheels:GetChildren()) do
			if v.Name == "F" then
				v.Arm.Steer.CFrame = car.Wheels.F.Base.CFrame
					* CFrame.Angles(0, -math.rad(_GSteerC * _Tune.SteerInner * sDecay), 0)
			elseif v.Name == "FL" then
				if _GSteerC >= 0 then
					v.Arm.Steer.CFrame = car.Wheels.FL.Base.CFrame
						* CFrame.Angles(0, -math.rad(_GSteerC * _Tune.SteerOuter * sDecay), 0)
				else
					v.Arm.Steer.CFrame = car.Wheels.FL.Base.CFrame
						* CFrame.Angles(0, -math.rad(_GSteerC * _Tune.SteerInner * sDecay), 0)
				end
			elseif v.Name == "FR" then
				if _GSteerC >= 0 then
					v.Arm.Steer.CFrame = car.Wheels.FR.Base.CFrame
						* CFrame.Angles(0, -math.rad(_GSteerC * _Tune.SteerInner * sDecay), 0)
				else
					v.Arm.Steer.CFrame = car.Wheels.FR.Base.CFrame
						* CFrame.Angles(0, -math.rad(_GSteerC * _Tune.SteerOuter * sDecay), 0)
				end
			end
		end
	end

	--[[Engine]]

	local fFD = _Tune.FinalDrive * _Tune.FDMult
	local fFDr = fFD * 30 / math.pi
	local cGrav = workspace.Gravity * _Tune.InclineComp / 32.2
	local wDRatio = wDia * math.pi / 60
	local cfWRot = CFrame.Angles(math.pi / 2, -math.pi / 2, 0)
	local cfYRot = CFrame.Angles(0, math.pi, 0)
	local rtTwo = (2 ^ 0.5) / 2

	--Horsepower Curve
	local fgc_h = _Tune.Horsepower / 100
	local fgc_n = _Tune.PeakRPM / 1000
	local fgc_a = _Tune.PeakSharpness
	local fgc_c = _Tune.CurveMult

	local function FGC(x)
		x = x / 1000
		return (((-(x - fgc_n) ^ 2) * math.min(fgc_h / (fgc_n ^ 2), fgc_c ^ (fgc_n / fgc_h))) + fgc_h)
			* (x - ((x ^ fgc_a) / ((fgc_a * fgc_n) ^ (fgc_a - 1))))
	end
	local PeakFGC = FGC(_Tune.PeakRPM)

	--Plot Current Horsepower
	local function GetCurve(x, gear)
		local hp = math.max((FGC(x) * _Tune.Horsepower) / PeakFGC, 0)
		return hp, hp * (_Tune.EqPoint / x) * _Tune.Ratios[gear + 2] * fFD * hpScaling
	end

	--Output Cache
	local CacheTorque = true
	local HPCache = {}
	local HPInc = 100

	if CacheTorque then
		for gear, ratio in pairs(_Tune.Ratios) do
			local hpPlot = {}
			for rpm = math.floor(_Tune.IdleRPM / HPInc), math.ceil((_Tune.Redline + 100) / HPInc) do
				local tqPlot = {}
				tqPlot.Horsepower, tqPlot.Torque = GetCurve(rpm * HPInc, gear - 2)
				local hp1, tq1 = GetCurve((rpm + 1) * HPInc, gear - 2)
				tqPlot.HpSlope = (hp1 - tqPlot.Horsepower) / (HPInc / 1000)
				tqPlot.TqSlope = (tq1 - tqPlot.Torque) / (HPInc / 1000)
				hpPlot[rpm] = tqPlot
			end
			table.insert(HPCache, hpPlot)
		end
	end

	--Powertrain

	--Update RPM
	local function RPM()
		--Neutral Gear
		if _CGear == 0 then _ClutchOn = false end

		--Car Is Off
		local revMin = _Tune.IdleRPM
		if not _IsOn then
			revMin = 0
			_CGear = 0
			_ClutchOn = false
			_GThrot = _Tune.IdleThrottle / 100
		end

		--Determine RPM
		local maxSpin = 0
		for i, v in pairs(Drive) do
			if v.RotVelocity.Magnitude > maxSpin then maxSpin = v.RotVelocity.Magnitude end
		end
		if _ClutchOn then
			local aRPM = math.max(math.min(maxSpin * _Tune.Ratios[_CGear + 2] * fFDr, _Tune.Redline + 100), revMin)
			local clutchP = math.min(math.abs(aRPM - _RPM) / _Tune.ClutchTol, 0.9)
			_RPM = _RPM * clutchP + aRPM * (1 - clutchP)
		else
			if _GThrot - (_Tune.IdleThrottle / 100) > 0 then
				if _RPM > _Tune.Redline then
					_RPM = _RPM - _Tune.RevBounce * 2
				else
					_RPM = math.min(_RPM + _Tune.RevAccel * _GThrot, _Tune.Redline + 100)
				end
			else
				_RPM = math.max(_RPM - _Tune.RevDecay, revMin)
			end
		end

		--Rev Limiter
		_spLimit = (_Tune.Redline + 100) / (fFDr * _Tune.Ratios[_CGear + 2])
		if _RPM > _Tune.Redline then
			if _CGear < #_Tune.Ratios - 2 then
				_RPM = _RPM - _Tune.RevBounce
			else
				_RPM = _RPM - _Tune.RevBounce * 0.5
			end
		end
	end

	--Apply Power
	local function Engine()
		--Get Torque
		local maxSpin = 0
		for i, v in pairs(Drive) do
			if v.RotVelocity.Magnitude > maxSpin then maxSpin = v.RotVelocity.Magnitude end
		end
		if _ClutchOn then
			if CacheTorque then
				local cTq =
					HPCache[_CGear + 2][math.floor(math.min(_Tune.Redline, math.max(_Tune.IdleRPM, _RPM)) / HPInc)]
				_HP = cTq.Horsepower + (cTq.HpSlope * (_RPM - math.floor(_RPM / HPInc)) / 1000)
				_OutTorque = cTq.Torque + (cTq.TqSlope * (_RPM - math.floor(_RPM / HPInc)) / 1000)
			else
				_HP, _OutTorque = GetCurve(_RPM, _CGear)
			end
			local iComp = driveSeat.CFrame.lookVector.y * cGrav
			if _CGear == -1 then iComp = -iComp end
			_OutTorque = _OutTorque * math.max(1, (1 + iComp))
		else
			_HP, _OutTorque = 0, 0
		end

		--Automatic Transmission
		if _TMode == "Auto" and _IsOn then
			_ClutchOn = true
			if _CGear == 0 then _CGear = 1 end
			if _CGear >= 1 then
				if _CGear == 1 and _GBrake > 0 and driveSeat.Velocity.Magnitude < 20 then
					_CGear = -1
				else
					if _Tune.AutoShiftMode == "RPM" then
						if _RPM > (_Tune.PeakRPM + _Tune.AutoUpThresh) then
							_CGear = math.min(_CGear + 1, #_Tune.Ratios - 2)
						elseif
							math.max(
								math.min(maxSpin * _Tune.Ratios[_CGear + 1] * fFDr, _Tune.Redline + 100),
								_Tune.IdleRPM
							) < (_Tune.PeakRPM - _Tune.AutoDownThresh)
						then
							_CGear = math.max(_CGear - 1, 1)
						end
					else
						if
							driveSeat.Velocity.Magnitude
							> math.ceil(wDRatio * (_Tune.PeakRPM + _Tune.AutoUpThresh) / _Tune.Ratios[_CGear + 2] / fFD)
						then
							_CGear = math.min(_CGear + 1, #_Tune.Ratios - 2)
						elseif
							driveSeat.Velocity.Magnitude
							< math.ceil(
								wDRatio * (_Tune.PeakRPM - _Tune.AutoDownThresh) / _Tune.Ratios[_CGear + 1] / fFD
							)
						then
							_CGear = math.max(_CGear - 1, 1)
						end
					end
				end
			else
				if _GThrot - (_Tune.IdleThrottle / 100) > 0 and driveSeat.Velocity.Magnitude < 20 then _CGear = 1 end
			end
		end

		--Average Rotational Speed Calculation
		local fwspeed = 0
		local fwcount = 0
		local rwspeed = 0
		local rwcount = 0

		for i, v in pairs(car.Wheels:GetChildren()) do
			if v.Name == "FL" or v.Name == "FR" or v.Name == "F" then
				fwspeed = fwspeed + v.RotVelocity.Magnitude
				fwcount = fwcount + 1
			elseif v.Name == "RL" or v.Name == "RR" or v.Name == "R" then
				rwspeed = rwspeed + v.RotVelocity.Magnitude
				rwcount = rwcount + 1
			end
		end
		fwspeed = fwspeed / fwcount
		rwspeed = rwspeed / rwcount
		local cwspeed = (fwspeed + rwspeed) / 2

		--Update Wheels
		for i, v in pairs(car.Wheels:GetChildren()) do
			--Reference Wheel Orientation
			local Ref = (CFrame.new(v.Position - (v.Arm.CFrame * cfWRot).lookVector, v.Position) * cfYRot).lookVector
			local aRef = 1
			local diffMult = 1
			if v.Name == "FL" or v.Name == "RL" then aRef = -1 end

			--AWD Torque Scaling
			if _Tune.Config == "AWD" then _OutTorque = _OutTorque * rtTwo end

			--Differential/Torque-Vectoring
			if v.Name == "FL" or v.Name == "FR" then
				diffMult = math.max(
					0,
					math.min(
						1,
						1
							+ (
								(
									((v.RotVelocity.Magnitude - fwspeed) / fwspeed)
									/ (math.max(_Tune.FDiffSlipThres, 1) / 100)
								) * ((_Tune.FDiffLockThres - 50) / 50)
							)
					)
				)
				if _Tune.Config == "AWD" then
					diffMult = math.max(
						0,
						math.min(
							1,
							diffMult
								* (
									1
									+ (
										(((fwspeed - cwspeed) / cwspeed) / (math.max(_Tune.CDiffSlipThres, 1) / 100))
										* ((_Tune.CDiffLockThres - 50) / 50)
									)
								)
						)
					)
				end
			elseif v.Name == "RL" or v.Name == "RR" then
				diffMult = math.max(
					0,
					math.min(
						1,
						1
							+ (
								(
									((v.RotVelocity.Magnitude - rwspeed) / rwspeed)
									/ (math.max(_Tune.RDiffSlipThres, 1) / 100)
								) * ((_Tune.RDiffLockThres - 50) / 50)
							)
					)
				)
				if _Tune.Config == "AWD" then
					diffMult = math.max(
						0,
						math.min(
							1,
							diffMult
								* (
									1
									+ (
										(((rwspeed - cwspeed) / cwspeed) / (math.max(_Tune.CDiffSlipThres, 1) / 100))
										* ((_Tune.CDiffLockThres - 50) / 50)
									)
								)
						)
					)
				end
			end

			_TCSActive = false
			_ABSActive = false
			--Output
			if
				_PBrake
				and (
					(
						_Tune.Config ~= "FWD"
						and (
							((v.Name == "FL" or v.Name == "FR") and driveSeat.Velocity.Magnitude < 20)
							or ((v.Name == "RR" or v.Name == "RL") and driveSeat.Velocity.Magnitude >= 20)
						)
					) or (_Tune.Config == "FWD" and (v.Name == "RR" or v.Name == "RL"))
				)
			then
				--PBrake
				v["#AV"].maxTorque = Vector3.new(math.abs(Ref.x), math.abs(Ref.y), math.abs(Ref.z)) * PBrakeForce
				v["#AV"].angularvelocity = Vector3.new()
			else
				--Apply Power
				if
					((_TMode == "Manual" or _TMode == "Semi") and _GBrake == 0)
					or (
						_TMode == "Auto"
						and (
							(_CGear > -1 and _GBrake == 0)
							or (_CGear == -1 and _GThrot - (_Tune.IdleThrottle / 100) == 0)
						)
					)
				then
					local driven = false
					for _, a in pairs(Drive) do
						if a == v then driven = true end
					end
					if driven then
						local on = 1
						if not interface.IsOn.Value then on = 0 end
						local throt = _GThrot
						if _TMode == "Auto" and _CGear == -1 then throt = _GBrake end

						--Apply TCS
						local tqTCS = 1
						if _TCS then
							tqTCS = 1
								- (
									math.min(
										math.max(
											0,
											math.abs(v.RotVelocity.Magnitude * (v.Size.x / 2) - v.Velocity.Magnitude)
												- _Tune.TCSThreshold
										) / _Tune.TCSGradient,
										1
									) * (1 - (_Tune.TCSLimit / 100))
								)
						end
						if tqTCS < 1 then _TCSActive = true end

						--Update Forces
						local dir = 1
						if _CGear == -1 then dir = -1 end
						v["#AV"].maxTorque = Vector3.new(math.abs(Ref.x), math.abs(Ref.y), math.abs(Ref.z))
							* _OutTorque
							* (1 + (v.RotVelocity.Magnitude / 60) ^ 1.15)
							* throt
							* tqTCS
							* diffMult
							* on
						v["#AV"].angularvelocity = Ref * aRef * _spLimit * dir
					else
						v["#AV"].maxTorque = Vector3.new()
						v["#AV"].angularvelocity = Vector3.new()
					end

				--Brakes
				else
					local brake = _GBrake
					if _TMode == "Auto" and _CGear == -1 then brake = _GThrot end

					--Apply ABS
					local tqABS = 1
					if
						_ABS
						and math.abs(v.RotVelocity.Magnitude * (v.Size.x / 2) - v.Velocity.Magnitude)
								- _Tune.ABSThreshold
							> 0
					then
						tqABS = 0
					end
					if tqABS < 1 then _ABSActive = true end

					--Update Forces
					if v.Name == "FL" or v.Name == "FR" or v.Name == "F" then
						v["#AV"].maxTorque = Vector3.new(math.abs(Ref.x), math.abs(Ref.y), math.abs(Ref.z))
							* FBrakeForce
							* brake
							* tqABS
					else
						v["#AV"].maxTorque = Vector3.new(math.abs(Ref.x), math.abs(Ref.y), math.abs(Ref.z))
							* RBrakeForce
							* brake
							* tqABS
					end
					v["#AV"].angularvelocity = Vector3.new()
				end
			end
		end
	end

	--[[Flip]]

	local function Flip()
		--Detect Orientation
		if (driveSeat.CFrame * CFrame.Angles(math.pi / 2, 0, 0)).lookVector.y > 0.1 or FlipDB then
			FlipWait = tick()

		--Apply Flip
		else
			if tick() - FlipWait >= 3 then
				FlipDB = true
				local gyro = driveSeat.Flip
				gyro.maxTorque = Vector3.new(10000, 0, 10000)
				gyro.P = 3000
				gyro.D = 500
				task.wait(1)
				gyro.maxTorque = Vector3.new(0, 0, 0)
				gyro.P = 0
				gyro.D = 0
				FlipDB = false
			end
		end
	end

	--[[Run]]

	--Print Version
	--local ver = require(car["A-Chassis Tune"].README)
	--print("//INSPARE: AC6 Loaded - Build " .. ver)

	--Runtime Loops

	-- ~60 c/s
	local steppedConn = RunService.Stepped:Connect(function()
		--Steering
		Steering()

		--RPM
		RPM()

		--Update External Values
		_IsOn = interface.IsOn.Value
		_InControls = interface.ControlsOpen.Value
		interface.Values.Gear.Value = _CGear
		interface.Values.RPM.Value = _RPM
		interface.Values.Horsepower.Value = _HP
		interface.Values.Torque.Value = _HP * _Tune.EqPoint / _RPM
		interface.Values.TransmissionMode.Value = _TMode
		interface.Values.Throttle.Value = _GThrot
		interface.Values.Brake.Value = _GBrake
		interface.Values.SteerC.Value = _GSteerC
			* (1 - math.min(driveSeat.Velocity.Magnitude / _Tune.SteerDecay, 1 - (_Tune.MinSteer / 100)))
		interface.Values.SteerT.Value = _GSteerT
		interface.Values.PBrake.Value = _PBrake
		interface.Values.TCS.Value = _TCS
		interface.Values.TCSActive.Value = _TCSActive
		interface.Values.ABS.Value = _ABS
		interface.Values.ABSActive.Value = _ABSActive
		interface.Values.MouseSteerOn.Value = _MSteer
		interface.Values.Velocity.Value = driveSeat.Velocity
	end)
	table.insert(self._connections, steppedConn)

	-- ~15 c/s
	while not self._destroyed and task.wait(0.0667) do
		--Power
		Engine()

		--Flip
		if _Tune.AutoFlip then Flip() end
	end

	--[[END]]
end

function BetterChassis:Destroy()
	-- idempotent
	if self._destroyed then return end
	self._destroyed = true

	-- disconnect stored connections
	if self._connections then
		for _, conn in ipairs(self._connections) do
			if conn and conn.Disconnect then pcall(function()
				conn:Disconnect()
			end) end
		end
		self._connections = nil
	end

	-- destroy client interface if still present
	if
		self.interface
		and typeof(self.interface) == "Instance"
		and self.interface.Parent
		and self.interface.Parent:IsA("PlayerGui")
	then
		pcall(function()
			self.interface:Destroy()
		end)
	end

	-- try to zero wheel forces on remaining parts (safe fallback)
	if self.car and self.car:IsDescendantOf(game) then
		for _, v in pairs(self.car:GetDescendants()) do
			if v.Name == "#AV" then
				pcall(function()
					if v:IsA("BodyAngularVelocity") then
						v.AngularVelocity = Vector3.new()
						v.MaxTorque = Vector3.new()
					else
						-- legacy motor
						v.AngularVelocity = 0
						v.MotorMaxTorque = 0
					end
				end)
			end
		end
	end

	-- clear references to allow GC
	self.interface = nil
	self.config = nil
	self.car = nil
end

return BetterChassis
