--!strict
local ChassisUtils = {}

-- Services
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

--[=[
    Initializes a scooter for a player by linking them together with ObjectValues.
    @param player The player to link the scooter to.
    @param scooterModel The scooter model to initialize.
]=]
function ChassisUtils.initCarForPlayer(scooterModel: Model, player: Player)
	-- Link the player and the scooter together using ObjectValues
	local playerValue = (scooterModel:FindFirstChild("PlayerOwner") :: ObjectValue?) or Instance.new("ObjectValue")
	playerValue.Name = "PlayerOwner"
	playerValue.Value = player
	playerValue.Parent = scooterModel

	local carValue = (player:FindFirstChild("OwnedCar") :: ObjectValue?) or Instance.new("ObjectValue")
	carValue.Name = "OwnedCar"
	carValue.Value = scooterModel
	carValue.Parent = player
end

--[=[
	Gets the player associated with a given car model.
	@param car The car model to check.
	@return The player associated with the car, or nil if there is no player linked.
]=]
function ChassisUtils.getPlayerFromCar(car: Model): Player?
	local playerValue = car:FindFirstChild("PlayerOwner") :: ObjectValue?
	if playerValue and playerValue.Value and playerValue.Value:IsA("Player") then return playerValue.Value end
	return nil
end

--[=[
	Gets the car model associated with a given player.
	@param player The player to check.
	@return The car model associated with the player, or nil if there is no car linked.
]=]
function ChassisUtils.getCarFromPlayer(player: Player): Model?
	local carValue = player:FindFirstChild("OwnedCar") :: ObjectValue?
	if carValue and carValue.Value and carValue.Value:IsA("Model") then return carValue.Value end
	return nil
end

local EXCLUDED_PARTS_IN_WHEELS = { "FL", "FR", "RL", "RR" }

--[=[
	Given a part, checks if it's part of a player's car and returns the car model and player if so.
	@param part The part to check.
	@return The car model and player if the part is part of a car, nil otherwise.
]=]
function ChassisUtils.getCarFromPart(part: BasePart): (Model?, Player?)
	if part.Name == "#Weight" then return nil end

	if RunService:IsServer() then
		for _, plr in Players:GetPlayers() do
			local ownedCar = plr:FindFirstChild("OwnedCar") :: ObjectValue?
			if ownedCar and ownedCar.Value and ownedCar.Value:IsA("Model") then
				local car = ownedCar.Value
				if
					part:IsDescendantOf(car:FindFirstChild("Wheels") :: Folder)
					and not table.find(EXCLUDED_PARTS_IN_WHEELS, part.Name)
				then
					-- print(
					-- 	`{script} :: Part {part:GetFullName()} is part of {plr.Name}'s car {ownedCar.Value.Name} (Wheels)`
					-- )
					return nil
				end
				if part:IsDescendantOf(car) then return car, plr end
			end
		end
	elseif RunService:IsClient() then
		local plr = Players.LocalPlayer
		local ownedCar = plr:FindFirstChild("OwnedCar") :: ObjectValue?
		if not (ownedCar and ownedCar.Value and ownedCar.Value:IsA("Model")) then return nil end

		local car = ownedCar.Value
		if part:IsDescendantOf(car) then return car, plr end
	end

	return nil
end

return ChassisUtils
