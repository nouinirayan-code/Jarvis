--[[
	LE MANOIR DES OMBRES — script serveur
	À placer dans ServerScriptService (type : Script).

	Construit le manoir au lancement, gère les manches, les énigmes, le monstre
	(« le Veilleur »), les cachettes et la lampe torche.
	Le script client (ManoirClient) affiche l'interface et les effets d'horreur.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Lighting = game:GetService("Lighting")
local PathfindingService = game:GetService("PathfindingService")

---------------------------------------------------------------------------
-- RÉGLAGES
---------------------------------------------------------------------------

local ROUND_TIME = 8 * 60 -- durée d'une manche (secondes)
local MONSTER_DELAY = 25 -- le Veilleur se réveille après ce délai
local INTERMISSION = 15 -- pause entre deux manches

local WALK_SPEED = 12 -- la course (Maj) est gérée par le client
local SPRINT_SPEED = 19

local MONSTER_PATROL_SPEED = 9
local MONSTER_CHASE_SPEED = 15.5
local MONSTER_MAX_SPEED = 19
local SIGHT_RANGE = 55 -- distance de vue dans le noir
local SIGHT_RANGE_LAMP = 95 -- une lampe allumée se voit de loin !
local HEARING_RANGE = 42 -- un joueur qui court s'entend
local CATCH_RANGE = 5.5

local BATTERY_DRAIN = 1.25 -- % par seconde, lampe allumée
local WALL_H = 14

---------------------------------------------------------------------------
-- OUTILS
---------------------------------------------------------------------------

local Remotes = Instance.new("Folder")
Remotes.Name = "ManoirRemotes"
Remotes.Parent = ReplicatedStorage

local function remote(name: string): RemoteEvent
	local r = Instance.new("RemoteEvent")
	r.Name = name
	r.Parent = Remotes
	return r
end

local NotifyRemote = remote("Notify") -- (texte, couleur?)
local ObjectiveRemote = remote("Objective") -- (texte)
local NoteRemote = remote("Note") -- (titre, texte)
local KeypadRemote = remote("Keypad") -- serveur -> client : ouvrir ; client -> serveur : code
local JumpscareRemote = remote("Jumpscare")
local RoundRemote = remote("Round") -- (état, secondes restantes)
local EndRemote = remote("End") -- (victoire, texte)
local LampRemote = remote("Lamp") -- client -> serveur : basculer la lampe

local Manor: Folder -- reconstruit à chaque manche

local function part(props: { [string]: any }): BasePart
	local p = Instance.new(props.ClassName or "Part") :: BasePart
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	for k, v in props do
		if k ~= "ClassName" and k ~= "Parent" then
			(p :: any)[k] = v
		end
	end
	if props.CanCollide == false and props.CanQuery == nil then
		p.CanQuery = false
	end
	p.Parent = props.Parent or Manor
	return p
end

local function light(parent: Instance, color: Color3, range: number, brightness: number): PointLight
	local l = Instance.new("PointLight")
	l.Color = color
	l.Range = range
	l.Brightness = brightness
	l.Shadows = true
	l.Parent = parent
	return l
end

local function prompt(p: BasePart, action: string, object: string, hold: number?): ProximityPrompt
	local pr = Instance.new("ProximityPrompt")
	pr.ActionText = action
	pr.ObjectText = object
	pr.HoldDuration = hold or 0
	pr.MaxActivationDistance = 9
	pr.RequiresLineOfSight = false
	pr.Parent = p
	return pr
end

local function notify(target: Player?, text: string, color: Color3?)
	if target then
		NotifyRemote:FireClient(target, text, color)
	else
		NotifyRemote:FireAllClients(text, color)
	end
end

local function surfaceText(p: BasePart, face: Enum.NormalId, text: string, color: Color3, font: Enum.Font?)
	local sg = Instance.new("SurfaceGui")
	sg.Face = face
	sg.CanvasSize = Vector2.new(400, 200)
	sg.LightInfluence = 1
	local t = Instance.new("TextLabel")
	t.Size = UDim2.fromScale(1, 1)
	t.BackgroundTransparency = 1
	t.Text = text
	t.TextScaled = true
	t.TextColor3 = color
	t.Font = font or Enum.Font.Antique
	t.Parent = sg
	sg.Parent = p
	return sg
end

---------------------------------------------------------------------------
-- AMBIANCE
---------------------------------------------------------------------------

Lighting.ClockTime = 0
Lighting.Brightness = 0.4
Lighting.Ambient = Color3.fromRGB(10, 10, 16)
Lighting.OutdoorAmbient = Color3.fromRGB(28, 30, 45)
Lighting.EnvironmentDiffuseScale = 0
Lighting.EnvironmentSpecularScale = 0
Lighting.FogColor = Color3.fromRGB(8, 8, 14)
local atmosphere = Instance.new("Atmosphere")
atmosphere.Density = 0.45
atmosphere.Haze = 2
atmosphere.Color = Color3.fromRGB(30, 30, 45)
atmosphere.Decay = Color3.fromRGB(10, 10, 20)
atmosphere.Parent = Lighting
local grade = Instance.new("ColorCorrectionEffect")
grade.Saturation = -0.35
grade.Contrast = 0.15
grade.TintColor = Color3.fromRGB(215, 220, 255)
grade.Parent = Lighting

Players.RespawnTime = 6

---------------------------------------------------------------------------
-- PLAN DU MANOIR
---------------------------------------------------------------------------
-- x : ouest (-) / est (+) ; z : nord (-) / sud (+). Le sol intérieur est à y = 0.

local ROOMS = {
	{ name = "Hall d'entrée", x1 = -28, x2 = 28, z1 = 6, z2 = 60, color = Color3.fromRGB(120, 112, 100), mat = Enum.Material.Marble },
	{ name = "Salon", x1 = -80, x2 = -28, z1 = 6, z2 = 60, color = Color3.fromRGB(90, 45, 40), mat = Enum.Material.Carpet },
	{ name = "Bureau", x1 = 28, x2 = 80, z1 = 6, z2 = 60, color = Color3.fromRGB(80, 55, 38), mat = Enum.Material.WoodPlanks },
	{ name = "Couloir", x1 = -80, x2 = 80, z1 = -6, z2 = 6, color = Color3.fromRGB(70, 30, 35), mat = Enum.Material.Carpet },
	{ name = "Bibliothèque", x1 = -80, x2 = -30, z1 = -60, z2 = -6, color = Color3.fromRGB(85, 60, 40), mat = Enum.Material.WoodPlanks },
	{ name = "Salle à manger", x1 = -30, x2 = 25, z1 = -60, z2 = -6, color = Color3.fromRGB(95, 70, 50), mat = Enum.Material.WoodPlanks },
	{ name = "Cuisine", x1 = 25, x2 = 80, z1 = -60, z2 = -6, color = Color3.fromRGB(110, 110, 105), mat = Enum.Material.Slate },
	{ name = "Cave", x1 = 40, x2 = 80, z1 = -90, z2 = -60, color = Color3.fromRGB(60, 58, 55), mat = Enum.Material.Cobblestone },
}

local HALL_SPAWN = Vector3.new(0, 3, 42)
local SAFE_ZONE = Vector3.new(0, 3, 150)

local function roomCenter(r): Vector3
	return Vector3.new((r.x1 + r.x2) / 2, 0, (r.z1 + r.z2) / 2)
end

local function insideManor(pos: Vector3): boolean
	return pos.X > -80 and pos.X < 80 and pos.Z > -90 and pos.Z < 60 and pos.Y < 20
end

---------------------------------------------------------------------------
-- ÉTAT DE LA MANCHE
---------------------------------------------------------------------------

type Round = {
	state: string, -- "jeu" | "fin"
	timeLeft: number,
	fuses: number,
	power: boolean,
	safeOpen: boolean,
	hasKey: boolean,
	doorOpen: boolean,
	code: string,
	clockText: string,
	escaped: { [Player]: boolean },
	catches: number,
	roomLights: { PointLight },
	officeDoor: BasePart?,
	frontDoor: BasePart?,
	safeDoor: BasePart?,
	monsterAwake: boolean,
	started: number,
}

local round: Round
local wardrobeOf: { [Player]: any } = {}
local battery: { [Player]: number } = {}
local lampOn: { [Player]: boolean } = {}

local function setObjective(text: string)
	Remotes:SetAttribute("Objective", text)
	ObjectiveRemote:FireAllClients(text)
end

local function refreshInventory()
	Remotes:SetAttribute("Fuses", round.fuses)
	Remotes:SetAttribute("Key", round.hasKey)
	Remotes:SetAttribute("Power", round.power)
end

---------------------------------------------------------------------------
-- CONSTRUCTION
---------------------------------------------------------------------------

local wallColor = Color3.fromRGB(72, 58, 52)

-- Mur horizontal (le long de x) avec ouvertures
local function hwall(z: number, x1: number, x2: number, gaps: { { number } }?)
	local gl: { { number } } = gaps or {}
	local cuts = { x1 }
	for _, g in gl do
		table.insert(cuts, g[1])
		table.insert(cuts, g[2])
	end
	table.insert(cuts, x2)
	for i = 1, #cuts, 2 do
		local a, b = cuts[i], cuts[i + 1]
		if b - a > 0.1 then
			part({ Name = "Mur", Size = Vector3.new(b - a, WALL_H, 1), CFrame = CFrame.new((a + b) / 2, WALL_H / 2, z), Color = wallColor, Material = Enum.Material.Plaster })
			-- Lambris
			part({ Name = "Lambris", Size = Vector3.new(b - a, 4, 1.3), CFrame = CFrame.new((a + b) / 2, 2, z), Color = Color3.fromRGB(55, 35, 25), Material = Enum.Material.Wood })
		end
	end
	for _, g in gl do
		part({ Name = "Linteau", Size = Vector3.new(g[2] - g[1], WALL_H - 10, 1), CFrame = CFrame.new((g[1] + g[2]) / 2, 10 + (WALL_H - 10) / 2, z), Color = wallColor, Material = Enum.Material.Plaster })
	end
end

-- Mur vertical (le long de z)
local function vwall(x: number, z1: number, z2: number, gaps: { { number } }?)
	local gl: { { number } } = gaps or {}
	local cuts = { z1 }
	for _, g in gl do
		table.insert(cuts, g[1])
		table.insert(cuts, g[2])
	end
	table.insert(cuts, z2)
	for i = 1, #cuts, 2 do
		local a, b = cuts[i], cuts[i + 1]
		if b - a > 0.1 then
			part({ Name = "Mur", Size = Vector3.new(1, WALL_H, b - a), CFrame = CFrame.new(x, WALL_H / 2, (a + b) / 2), Color = wallColor, Material = Enum.Material.Plaster })
			part({ Name = "Lambris", Size = Vector3.new(1.3, 4, b - a), CFrame = CFrame.new(x, 2, (a + b) / 2), Color = Color3.fromRGB(55, 35, 25), Material = Enum.Material.Wood })
		end
	end
	for _, g in gl do
		part({ Name = "Linteau", Size = Vector3.new(1, WALL_H - 10, g[2] - g[1]), CFrame = CFrame.new(x, 10 + (WALL_H - 10) / 2, (g[1] + g[2]) / 2), Color = wallColor, Material = Enum.Material.Plaster })
	end
end

local function box(name: string, size: Vector3, pos: Vector3, color: Color3, mat: Enum.Material?, rotY: number?): BasePart
	return part({
		Name = name, Size = size, CFrame = CFrame.new(pos + Vector3.new(0, size.Y / 2, 0)) * CFrame.Angles(0, math.rad(rotY or 0), 0),
		Color = color, Material = mat or Enum.Material.Wood,
	})
end

local function candle(pos: Vector3)
	part({ Name = "Bougie", Size = Vector3.new(0.4, 1.2, 0.4), CFrame = CFrame.new(pos + Vector3.new(0, 0.6, 0)), Color = Color3.fromRGB(235, 225, 200), Material = Enum.Material.SmoothPlastic, CanCollide = false })
	local flame = part({ Name = "Flamme", Shape = Enum.PartType.Ball, Size = Vector3.new(0.35, 0.35, 0.35), CFrame = CFrame.new(pos + Vector3.new(0, 1.35, 0)), Color = Color3.fromRGB(255, 190, 90), Material = Enum.Material.Neon, CanCollide = false })
	local l = light(flame, Color3.fromRGB(255, 160, 80), 14, 0.9)
	l:SetAttribute("Bougie", true)
end

local function painting(pos: Vector3, rotY: number, w: number, h: number, color: Color3)
	local cf = CFrame.new(pos) * CFrame.Angles(0, math.rad(rotY), 0)
	part({ Name = "Cadre", Size = Vector3.new(w + 0.8, h + 0.8, 0.3), CFrame = cf, Color = Color3.fromRGB(120, 90, 30), Material = Enum.Material.Metal })
	part({ Name = "Toile", Size = Vector3.new(w, h, 0.32), CFrame = cf, Color = color, Material = Enum.Material.Fabric })
	-- Silhouette inquiétante
	part({ Name = "Portrait", Shape = Enum.PartType.Ball, Size = Vector3.new(h * 0.35, h * 0.35, h * 0.35), CFrame = cf * CFrame.new(0, h * 0.12, 0), Color = Color3.fromRGB(30, 25, 25), CanCollide = false })
end

local wardrobes = {}

local function makeWardrobe(pos: Vector3, rotY: number)
	local cf = CFrame.new(pos) * CFrame.Angles(0, math.rad(rotY), 0)
	local wood = Color3.fromRGB(60, 38, 24)
	-- Caisse (ouverte vers l'avant = -Z local)
	part({ Name = "Armoire", Size = Vector3.new(6, 10, 0.6), CFrame = cf * CFrame.new(0, 5, 2.2), Color = wood })
	part({ Name = "Armoire", Size = Vector3.new(0.6, 10, 5), CFrame = cf * CFrame.new(-3, 5, 0), Color = wood })
	part({ Name = "Armoire", Size = Vector3.new(0.6, 10, 5), CFrame = cf * CFrame.new(3, 5, 0), Color = wood })
	part({ Name = "Armoire", Size = Vector3.new(6.6, 0.6, 5), CFrame = cf * CFrame.new(0, 10.2, 0), Color = wood })
	part({ Name = "Armoire", Size = Vector3.new(6, 0.6, 5), CFrame = cf * CFrame.new(0, 0.3, 0), Color = wood })
	-- Portes à fentes
	for _, s in { -1, 1 } do
		part({ Name = "PorteArmoire", Size = Vector3.new(2.9, 9.4, 0.3), CFrame = cf * CFrame.new(s * 1.5, 5.1, -2.4), Color = Color3.fromRGB(75, 48, 30), Material = Enum.Material.WoodPlanks })
	end
	local handle = part({ Name = "Poignee", Size = Vector3.new(0.3, 1.2, 0.3), CFrame = cf * CFrame.new(0.4, 5, -2.7), Color = Color3.fromRGB(170, 140, 60), Material = Enum.Material.Metal })
	local w = { inside = cf * CFrame.new(0, 3.2, 0), outside = cf * CFrame.new(0, 3.2, -6), occupant = nil :: Player? }
	table.insert(wardrobes, w)
	local pr = prompt(handle, "Se cacher", "Armoire")
	pr.KeyboardKeyCode = Enum.KeyCode.E
	pr.Triggered:Connect(function(player)
		local char = player.Character
		local hrp = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		if not hrp or not hum or hum.Health <= 0 then
			return
		end
		if w.occupant == player then
			-- Sortir
			w.occupant = nil
			wardrobeOf[player] = nil
			hrp.Anchored = false
			char:PivotTo(w.outside)
			hum.WalkSpeed = WALK_SPEED
			player:SetAttribute("Hidden", false)
			pr.ActionText = "Se cacher"
		elseif w.occupant == nil and not wardrobeOf[player] then
			w.occupant = player
			wardrobeOf[player] = w
			char:PivotTo(w.inside)
			hrp.Anchored = true
			hum.WalkSpeed = 0
			player:SetAttribute("Hidden", true)
			player:SetAttribute("HiddenSince", os.clock())
			pr.ActionText = "Sortir"
		else
			notify(player, "Quelqu'un est déjà caché ici…", Color3.fromRGB(200, 200, 220))
		end
	end)
end

local function releaseHidden(player: Player)
	local w = wardrobeOf[player]
	if w then
		w.occupant = nil
		wardrobeOf[player] = nil
	end
	player:SetAttribute("Hidden", false)
	local hrp = player.Character and player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if hrp then
		hrp.Anchored = false
	end
end

local function makeNote(pos: Vector3, title: string, text: string)
	local paper = part({ Name = "Note", Size = Vector3.new(1.4, 0.06, 1.8), CFrame = CFrame.new(pos + Vector3.new(0, 0.05, 0)) * CFrame.Angles(0, math.random() * 0.6, 0), Color = Color3.fromRGB(230, 220, 190), Material = Enum.Material.Fabric, CanCollide = false, CanQuery = true })
	local glow = light(paper, Color3.fromRGB(255, 240, 200), 5, 0.4)
	glow.Shadows = false
	local pr = prompt(paper, "Lire", title)
	pr.Triggered:Connect(function(player)
		NoteRemote:FireClient(player, title, text)
	end)
end

local function pickup(name: string, pos: Vector3, color: Color3, action: string, onTake: (Player) -> ())
	local item = part({ Name = name, Size = Vector3.new(0.8, 1.4, 0.8), CFrame = CFrame.new(pos + Vector3.new(0, 0.7, 0)), Color = color, Material = Enum.Material.Neon, CanCollide = false, CanQuery = true })
	local l = light(item, color, 7, 0.8)
	l.Shadows = false
	local pr = prompt(item, action, name)
	local taken = false
	pr.Triggered:Connect(function(player)
		if taken then
			return
		end
		taken = true
		item:Destroy()
		onTake(player)
	end)
	return item
end

local function fuseTaken(player: Player)
	round.fuses += 1
	refreshInventory()
	notify(nil, string.format("%s a trouvé un fusible (%d/3)", player.DisplayName, round.fuses), Color3.fromRGB(255, 220, 110))
	if round.fuses >= 3 then
		setObjective("Rétablis le courant : insère les 3 fusibles dans le boîtier de la cave (derrière la cuisine).")
	else
		setObjective(string.format("Trouve les fusibles dans le manoir (%d/3).", round.fuses))
	end
end

local function batteryTaken(player: Player)
	battery[player] = math.min(100, (battery[player] or 0) + 50)
	player:SetAttribute("Battery", battery[player])
	notify(player, "Pile ramassée : batterie +50 %", Color3.fromRGB(140, 255, 160))
end

local function powerOn()
	round.power = true
	refreshInventory()
	for _, l in round.roomLights do
		task.spawn(function()
			for _ = 1, 4 do
				l.Enabled = true
				task.wait(0.08 + math.random() * 0.1)
				l.Enabled = false
				task.wait(0.05 + math.random() * 0.1)
			end
			l.Enabled = true
		end)
	end
	if round.officeDoor then
		local door = round.officeDoor
		TweenService:Create(door, TweenInfo.new(1.2), { CFrame = door.CFrame * CFrame.new(7.5, 0, 0) }):Play()
		task.delay(1.2, function()
			door.CanCollide = false
		end)
	end
	notify(nil, "Le courant est rétabli… La porte du bureau s'est déverrouillée. Un cri résonne dans le manoir.", Color3.fromRGB(255, 120, 120))
	setObjective("Le bureau est ouvert : trouve le code du coffre-fort.")
end

local function openSafe(player: Player)
	round.safeOpen = true
	if round.safeDoor then
		local d = round.safeDoor
		TweenService:Create(d, TweenInfo.new(0.8), { CFrame = d.CFrame * CFrame.new(-1.6, 0, -1.6) * CFrame.Angles(0, math.rad(-90), 0) }):Play()
	end
	notify(nil, player.DisplayName .. " a ouvert le coffre-fort !", Color3.fromRGB(255, 220, 110))
	setObjective("Prends la clé maîtresse dans le coffre-fort du bureau.")
	pickup("Clé maîtresse", Vector3.new(74, 3.2, 33), Color3.fromRGB(255, 210, 70), "Prendre", function(p)
		round.hasKey = true
		refreshInventory()
		notify(nil, p.DisplayName .. " a la clé maîtresse ! Ouvrez la porte d'entrée !", Color3.fromRGB(255, 210, 70))
		setObjective("Ouvre la porte d'entrée du hall avec la clé maîtresse et fuis !")
	end)
end

local function buildManor()
	if Manor then
		Manor:Destroy()
	end
	-- Retire la plaque et le point d'apparition du modèle « Baseplate » de Studio
	for _, child in workspace:GetChildren() do
		if child.Name == "Baseplate" or child:IsA("SpawnLocation") then
			child:Destroy()
		end
	end
	Manor = Instance.new("Folder")
	Manor.Name = "Manoir"
	Manor.Parent = workspace
	table.clear(wardrobes)

	-- Extérieur : pelouse, allée, clôture, arbres morts
	part({ Name = "Pelouse", Size = Vector3.new(420, 2, 420), CFrame = CFrame.new(0, -1, 40), Color = Color3.fromRGB(38, 48, 34), Material = Enum.Material.Grass })
	part({ Name = "Allee", Size = Vector3.new(12, 0.3, 40), CFrame = CFrame.new(0, 0.15, 80), Color = Color3.fromRGB(80, 75, 70), Material = Enum.Material.Cobblestone })
	local fence = Color3.fromRGB(25, 25, 28)
	local function fenceLine(a: Vector3, b: Vector3)
		local len = (b - a).Magnitude
		part({ Name = "Grille", Size = Vector3.new(0.6, 10, len), CFrame = CFrame.lookAt((a + b) / 2 + Vector3.new(0, 5, 0), b + Vector3.new(0, 5, 0)), Color = fence, Material = Enum.Material.Metal })
	end
	fenceLine(Vector3.new(-80, 0, 60), Vector3.new(-80, 0, 100))
	fenceLine(Vector3.new(80, 0, 60), Vector3.new(80, 0, 100))
	fenceLine(Vector3.new(-80, 0, 100), Vector3.new(-8, 0, 100))
	fenceLine(Vector3.new(8, 0, 100), Vector3.new(80, 0, 100))
	for _, s in { -1, 1 } do
		part({ Name = "Pilier", Size = Vector3.new(3, 14, 3), CFrame = CFrame.new(s * 9.5, 7, 100), Color = Color3.fromRGB(70, 68, 65), Material = Enum.Material.Cobblestone })
		local lantern = part({ Name = "Lanterne", Size = Vector3.new(1.6, 1.6, 1.6), CFrame = CFrame.new(s * 9.5, 15, 100), Color = Color3.fromRGB(180, 210, 255), Material = Enum.Material.Neon })
		light(lantern, Color3.fromRGB(160, 190, 255), 30, 1.2)
	end
	local rng = Random.new(5)
	for _ = 1, 18 do
		local x = rng:NextNumber(-180, 180)
		local z = rng:NextNumber(-150, 230)
		if not (x > -95 and x < 95 and z > -105 and z < 115) then
			local h = rng:NextNumber(14, 26)
			part({ Name = "ArbreMort", Size = Vector3.new(1.6, h, 1.6), CFrame = CFrame.new(x, h / 2, z) * CFrame.Angles(rng:NextNumber(-0.15, 0.15), 0, rng:NextNumber(-0.15, 0.15)), Color = Color3.fromRGB(30, 25, 22), Material = Enum.Material.Wood })
			for k = 1, 3 do
				part({ Name = "Branche", Size = Vector3.new(0.6, rng:NextNumber(5, 9), 0.6), CFrame = CFrame.new(x, h * (0.55 + k * 0.12), z) * CFrame.Angles(rng:NextNumber(-1, 1), rng:NextNumber(0, 6), rng:NextNumber(0.6, 1.2)), Color = Color3.fromRGB(30, 25, 22), Material = Enum.Material.Wood })
			end
		end
	end
	-- Lune
	local moon = part({ Name = "Lune", Shape = Enum.PartType.Ball, Size = Vector3.new(30, 30, 30), CFrame = CFrame.new(-150, 220, 320), Color = Color3.fromRGB(220, 225, 255), Material = Enum.Material.Neon, CanCollide = false })
	light(moon, Color3.fromRGB(150, 170, 255), 60, 0.5)

	-- Zone sûre (après le portail)
	part({ Name = "ZoneSure", Size = Vector3.new(40, 1, 40), CFrame = CFrame.new(SAFE_ZONE.X, 0.5, SAFE_ZONE.Z), Color = Color3.fromRGB(60, 70, 50), Material = Enum.Material.Grass })
	local fire = part({ Name = "FeuDeCamp", Size = Vector3.new(3, 1, 3), CFrame = CFrame.new(SAFE_ZONE.X, 1.5, SAFE_ZONE.Z), Color = Color3.fromRGB(60, 40, 25), Material = Enum.Material.Wood })
	local f = Instance.new("Fire")
	f.Size = 6
	f.Parent = fire
	light(fire, Color3.fromRGB(255, 150, 70), 40, 2)

	-- Sols et plafond
	for _, r in ROOMS do
		part({ Name = "Sol", Size = Vector3.new(r.x2 - r.x1, 0.4, r.z2 - r.z1), CFrame = CFrame.new((r.x1 + r.x2) / 2, 0.2, (r.z1 + r.z2) / 2), Color = r.color, Material = r.mat })
	end
	part({ Name = "Plafond", Size = Vector3.new(162, 1, 152), CFrame = CFrame.new(0, WALL_H + 0.5, -15), Color = Color3.fromRGB(40, 32, 30), Material = Enum.Material.Wood })
	part({ Name = "Toit", ClassName = "WedgePart", Size = Vector3.new(162, 30, 76), CFrame = CFrame.new(0, WALL_H + 16, -53) * CFrame.Angles(0, math.rad(180), 0), Color = Color3.fromRGB(35, 30, 35), Material = Enum.Material.Slate })
	part({ Name = "Toit", ClassName = "WedgePart", Size = Vector3.new(162, 30, 76), CFrame = CFrame.new(0, WALL_H + 16, 23), Color = Color3.fromRGB(35, 30, 35), Material = Enum.Material.Slate })

	-- Murs
	hwall(-60, -80, 80, { { 60, 68 } })
	hwall(60, -80, 80, { { -6, 6 } })
	vwall(-80, -60, 60)
	vwall(80, -60, 60)
	hwall(-6, -80, 80, { { -55, -47 }, { -6, 2 }, { 48, 56 } })
	hwall(6, -80, 80, { { -58, -50 }, { -8, 8 }, { 50, 58 } })
	vwall(-30, -60, -6, { { -40, -32 } })
	vwall(25, -60, -6, { { -30, -22 } })
	vwall(-28, 6, 60, { { 30, 38 } })
	vwall(28, 6, 60)
	-- Cave
	vwall(40, -90, -60)
	vwall(80, -90, -60)
	hwall(-90, 40, 80)

	-- Lumières des pièces (éteintes tant que le courant est coupé)
	round.roomLights = {}
	for _, r in ROOMS do
		local c = roomCenter(r)
		local lamp = part({ Name = "Lustre", Size = Vector3.new(3, 1, 3), CFrame = CFrame.new(c.X, WALL_H - 1, c.Z), Color = Color3.fromRGB(200, 180, 120), Material = Enum.Material.Glass, CanCollide = false })
		local l = light(lamp, Color3.fromRGB(255, 220, 160), 45, 1.1)
		l.Enabled = false
		table.insert(round.roomLights, l)
	end

	-- HALL ---------------------------------------------------------------
	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "Apparition"
	spawn.Anchored = true
	spawn.Size = Vector3.new(8, 0.4, 8)
	spawn.CFrame = CFrame.new(HALL_SPAWN.X, 0.45, HALL_SPAWN.Z)
	spawn.Color = Color3.fromRGB(90, 30, 30)
	spawn.Material = Enum.Material.Carpet
	spawn.Duration = 0
	spawn.Neutral = true
	spawn.Parent = Manor
	box("Estrade", Vector3.new(14, 1, 8), Vector3.new(0, 0, 22), Color3.fromRGB(70, 45, 30), Enum.Material.WoodPlanks)
	box("Statue", Vector3.new(3, 8, 3), Vector3.new(0, 1, 22), Color3.fromRGB(150, 150, 145), Enum.Material.Marble)
	box("Console", Vector3.new(6, 3, 2), Vector3.new(-20, 0, 50), Color3.fromRGB(60, 38, 24))
	candle(Vector3.new(-20, 3, 50))
	candle(Vector3.new(20, 3, 50))
	box("Console", Vector3.new(6, 3, 2), Vector3.new(20, 0, 50), Color3.fromRGB(60, 38, 24))
	painting(Vector3.new(0, 9, 59.3), 180, 8, 6, Color3.fromRGB(60, 50, 70))
	makeNote(Vector3.new(-20, 3, 50), "Journal de l'intendant",
		"Le courant a sauté et les fusibles ont disparu dans toute la maison.\n\nLe boîtier électrique est à la cave, derrière la cuisine.\n\nSurtout, ne faites pas de bruit. IL écoute. IL voit la lumière.")
	-- Porte d'entrée (verrouillée)
	local front = part({ Name = "PorteEntree", Size = Vector3.new(12, 11, 1), CFrame = CFrame.new(0, 5.5, 60), Color = Color3.fromRGB(55, 30, 20), Material = Enum.Material.WoodPlanks })
	surfaceText(front, Enum.NormalId.Back, "VERROUILLÉE", Color3.fromRGB(180, 40, 40), Enum.Font.Creepster)
	round.frontDoor = front
	local frontPrompt = prompt(front, "Ouvrir", "Porte d'entrée", 1.5)
	frontPrompt.Triggered:Connect(function(player)
		if round.doorOpen or round.state ~= "jeu" then
			return
		end
		if not round.hasKey then
			notify(player, "La porte est verrouillée. Il faut la clé maîtresse.", Color3.fromRGB(220, 200, 200))
			return
		end
		round.doorOpen = true
		frontPrompt.Enabled = false
		TweenService:Create(front, TweenInfo.new(1.5), { CFrame = front.CFrame * CFrame.new(0, 12, 0) }):Play()
		task.delay(1, function()
			front.CanCollide = false
		end)
		notify(nil, "La porte d'entrée est ouverte ! COUREZ jusqu'au portail !", Color3.fromRGB(140, 255, 160))
		setObjective("Fuis par le portail au bout de l'allée !")
	end)
	-- Sortie (au portail)
	local exitZone = part({ Name = "Sortie", Size = Vector3.new(16, 12, 4), CFrame = CFrame.new(0, 6, 102), Transparency = 1, CanCollide = false })
	exitZone.Touched:Connect(function(hit)
		local player = Players:GetPlayerFromCharacter(hit.Parent)
		if not player or round.state ~= "jeu" or round.escaped[player] or not round.doorOpen then
			return
		end
		round.escaped[player] = true
		player:SetAttribute("Escaped", true)
		local char = player.Character
		if char then
			char:PivotTo(CFrame.new(SAFE_ZONE + Vector3.new(math.random(-8, 8), 0, math.random(-8, 8))))
		end
		notify(nil, player.DisplayName .. " s'est échappé du manoir !", Color3.fromRGB(140, 255, 160))
		EndRemote:FireClient(player, true, "Tu t'es échappé du Manoir des Ombres !")
	end)

	-- SALON --------------------------------------------------------------
	box("Canape", Vector3.new(12, 3, 4), Vector3.new(-54, 0, 40), Color3.fromRGB(110, 30, 35), Enum.Material.Fabric)
	box("Fauteuil", Vector3.new(4, 3, 4), Vector3.new(-66, 0, 30), Color3.fromRGB(110, 30, 35), Enum.Material.Fabric, 30)
	box("TableBasse", Vector3.new(6, 1.6, 3), Vector3.new(-54, 0, 32), Color3.fromRGB(60, 38, 24))
	box("Cheminee", Vector3.new(12, 10, 3), Vector3.new(-54, 0, 58), Color3.fromRGB(90, 85, 80), Enum.Material.Cobblestone)
	local embers = part({ Name = "Braises", Size = Vector3.new(6, 0.6, 1.5), CFrame = CFrame.new(-54, 1, 56.4), Color = Color3.fromRGB(255, 80, 20), Material = Enum.Material.Neon, CanCollide = false })
	light(embers, Color3.fromRGB(255, 100, 40), 18, 0.8)
	painting(Vector3.new(-79.3, 8, 30), 90, 6, 5, Color3.fromRGB(70, 40, 40))
	makeWardrobe(Vector3.new(-74, 0, 12), -90)
	makeNote(Vector3.new(-54, 1.6, 32), "Lettre déchirée",
		"…les armoires. Il ne regarde jamais dedans.\n\nSauf s'il vous a VU y entrer. Alors il vous en arrache.")

	-- BUREAU (verrouillé jusqu'au retour du courant) ------------------------
	local office = part({ Name = "PorteBureau", Size = Vector3.new(8, 10, 1), CFrame = CFrame.new(54, 5, 6), Color = Color3.fromRGB(40, 40, 45), Material = Enum.Material.DiamondPlate })
	surfaceText(office, Enum.NormalId.Front, "⚡ COUPÉ ⚡", Color3.fromRGB(255, 200, 60), Enum.Font.GothamBlack)
	round.officeDoor = office
	box("Bureau", Vector3.new(10, 3.2, 5), Vector3.new(54, 0, 40), Color3.fromRGB(70, 45, 28))
	box("Bibliotheque", Vector3.new(12, 12, 2), Vector3.new(54, 0, 58.5), Color3.fromRGB(55, 35, 22))
	candle(Vector3.new(51, 3.2, 40))
	-- Coffre-fort
	box("Coffre", Vector3.new(5, 5, 5), Vector3.new(74, 0, 33), Color3.fromRGB(50, 52, 58), Enum.Material.DiamondPlate)
	local safeDoor = part({ Name = "PorteCoffre", Size = Vector3.new(0.4, 4.2, 4.2), CFrame = CFrame.new(71.3, 2.5, 33), Color = Color3.fromRGB(70, 72, 80), Material = Enum.Material.Metal })
	round.safeDoor = safeDoor
	local dial = part({ Name = "Cadran", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.3, 1.4, 1.4), CFrame = CFrame.new(71, 2.8, 33), Color = Color3.fromRGB(200, 190, 150), Material = Enum.Material.Metal, CanCollide = false, CanQuery = true })
	local safePrompt = prompt(dial, "Entrer le code", "Coffre-fort")
	safePrompt.Triggered:Connect(function(player)
		if round.safeOpen then
			return
		end
		KeypadRemote:FireClient(player, true)
	end)
	painting(Vector3.new(79.3, 8, 20), -90, 5, 6, Color3.fromRGB(40, 50, 60))

	-- COULOIR ---------------------------------------------------------------
	for x = -70, 70, 20 do
		candle(Vector3.new(x, 0, -4.6))
		if x < 70 then
			painting(Vector3.new(x + 10, 8, -5.3), 0, 4, 5, Color3.fromRGB(math.random(40, 80), 40, 50))
		end
	end
	makeWardrobe(Vector3.new(-76, 0, 0), -90)
	makeWardrobe(Vector3.new(76, 0, 0), 90)

	-- BIBLIOTHÈQUE ------------------------------------------------------------
	for i = 0, 3 do
		box("Rayonnage", Vector3.new(2, 12, 16), Vector3.new(-72 + i * 11, 0, -40), Color3.fromRGB(65, 42, 26))
		for k = 0, 4 do
			part({ Name = "Livres", Size = Vector3.new(2.3, 1.4, 15), CFrame = CFrame.new(-72 + i * 11, 1.5 + k * 2.3, -40), Color = Color3.fromHSV((i * 5 + k) % 7 / 7, 0.5, 0.4), Material = Enum.Material.Fabric })
		end
	end
	box("Pupitre", Vector3.new(4, 3.4, 3), Vector3.new(-40, 0, -16), Color3.fromRGB(70, 45, 28))
	candle(Vector3.new(-39, 3.4, -16))
	makeWardrobe(Vector3.new(-74, 0, -12), -90)
	pickup("Fusible", Vector3.new(-72, 0, -55), Color3.fromRGB(255, 220, 80), "Ramasser", fuseTaken)
	makeNote(Vector3.new(-41, 3.4, -16.5), "Carnet du maître",
		"Je ne fais confiance qu'au temps.\n\nLe coffre de mon bureau s'ouvre à l'heure exacte où l'horloge de la salle à manger s'est arrêtée.\n\n(4 chiffres : heures puis minutes)")

	-- SALLE À MANGER ------------------------------------------------------------
	box("Table", Vector3.new(30, 3.2, 7), Vector3.new(-3, 0, -33), Color3.fromRGB(60, 36, 22))
	for i = -2, 2 do
		for _, s in { -1, 1 } do
			box("Chaise", Vector3.new(2.4, 4.5, 2.4), Vector3.new(-3 + i * 6, 0, -33 + s * 5.5), Color3.fromRGB(50, 30, 18))
		end
	end
	candle(Vector3.new(-10, 3.2, -33))
	candle(Vector3.new(4, 3.2, -33))
	-- Horloge comtoise
	box("Horloge", Vector3.new(4, 13, 3), Vector3.new(-3, 0, -58), Color3.fromRGB(70, 42, 24))
	local face = part({ Name = "Cadran", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.3, 3.4, 3.4), CFrame = CFrame.new(-3, 10.5, -56.4) * CFrame.Angles(0, math.rad(90), 0), Color = Color3.fromRGB(235, 225, 200), Material = Enum.Material.SmoothPlastic, CanCollide = false, CanQuery = true })
	-- Code aléatoire à chaque manche
	local hour = math.random(1, 12)
	local minute = math.random(0, 11) * 5
	round.code = string.format("%02d%02d", hour, minute)
	round.clockText = string.format("%d h %02d", hour, minute)
	local hands = Instance.new("SurfaceGui")
	hands.Face = Enum.NormalId.Front
	hands.CanvasSize = Vector2.new(200, 200)
	hands.LightInfluence = 1
	local function hand(angle: number, length: number, width: number, color: Color3)
		local h = Instance.new("Frame")
		h.AnchorPoint = Vector2.new(0.5, 1)
		h.Position = UDim2.fromScale(0.5, 0.5)
		h.Size = UDim2.fromOffset(width, length)
		h.BackgroundColor3 = color
		h.BorderSizePixel = 0
		h.Rotation = angle
		h.Parent = hands
	end
	for i = 0, 11 do
		local a = math.rad(i * 30)
		local tick = Instance.new("Frame")
		tick.AnchorPoint = Vector2.new(0.5, 0.5)
		tick.Size = UDim2.fromOffset(6, 16)
		tick.Position = UDim2.new(0.5, math.sin(a) * 80, 0.5, -math.cos(a) * 80)
		tick.Rotation = i * 30
		tick.BackgroundColor3 = Color3.fromRGB(30, 25, 20)
		tick.BorderSizePixel = 0
		tick.Parent = hands
	end
	hand((hour % 12 + minute / 60) * 30, 50, 8, Color3.fromRGB(20, 15, 10))
	hand(minute * 6, 78, 4, Color3.fromRGB(20, 15, 10))
	hands.Parent = face
	local clockPrompt = prompt(face, "Examiner", "Horloge")
	clockPrompt.Triggered:Connect(function(player)
		NoteRemote:FireClient(player, "L'horloge", "Le balancier ne bouge plus.\nLes aiguilles sont figées sur " .. round.clockText .. ".")
	end)
	makeWardrobe(Vector3.new(19, 0, -52), 90)
	pickup("Pile", Vector3.new(-25, 0, -10), Color3.fromRGB(120, 255, 140), "Ramasser", batteryTaken)

	-- CUISINE --------------------------------------------------------------------
	box("PlanDeTravail", Vector3.new(30, 3.4, 4), Vector3.new(55, 0, -57), Color3.fromRGB(90, 85, 80), Enum.Material.Marble)
	box("Fourneau", Vector3.new(6, 4, 4), Vector3.new(76, 0, -40), Color3.fromRGB(40, 40, 42), Enum.Material.Metal)
	box("Ilot", Vector3.new(12, 3.4, 6), Vector3.new(50, 0, -32), Color3.fromRGB(80, 60, 40))
	for i = 0, 3 do
		part({ Name = "Casserole", Shape = Enum.PartType.Cylinder, Size = Vector3.new(1, 1.6, 1.6), CFrame = CFrame.new(46 + i * 2.5, 4, -32) * CFrame.Angles(0, 0, math.rad(90)), Color = Color3.fromRGB(110, 80, 60), Material = Enum.Material.Metal })
	end
	candle(Vector3.new(55, 3.4, -57))
	pickup("Fusible", Vector3.new(76, 4, -40), Color3.fromRGB(255, 220, 80), "Ramasser", fuseTaken)
	makeNote(Vector3.new(48, 3.4, -33), "Mot griffonné",
		"Ses yeux CHERCHENT la lumière.\n\nÉteignez vos lampes (F) quand il approche, et ne courez pas : il entend vos pas.")
	makeWardrobe(Vector3.new(31, 0, -45), -90)

	-- CAVE -----------------------------------------------------------------------
	for i = 0, 5 do
		part({ Name = "Tonneau", Shape = Enum.PartType.Cylinder, Size = Vector3.new(5, 4, 4), CFrame = CFrame.new(44 + (i % 3) * 5, 2, -86 + math.floor(i / 3) * 5) * CFrame.Angles(0, 0, math.rad(90)), Color = Color3.fromRGB(90, 60, 35), Material = Enum.Material.Wood })
	end
	local fusebox = part({ Name = "BoitierElectrique", Size = Vector3.new(5, 6, 1.2), CFrame = CFrame.new(70, 6, -89.3), Color = Color3.fromRGB(70, 75, 80), Material = Enum.Material.DiamondPlate })
	local voyant = part({ Name = "Voyant", Size = Vector3.new(0.6, 0.6, 0.3), CFrame = CFrame.new(70, 9.6, -88.6), Color = Color3.fromRGB(255, 40, 40), Material = Enum.Material.Neon, CanCollide = false })
	light(voyant, Color3.fromRGB(255, 40, 40), 10, 1)
	local fusePrompt = prompt(fusebox, "Insérer les fusibles", "Boîtier électrique", 2)
	fusePrompt.Triggered:Connect(function(player)
		if round.power then
			return
		end
		if round.fuses < 3 then
			notify(player, string.format("Il manque des fusibles (%d/3).", round.fuses), Color3.fromRGB(255, 200, 120))
			return
		end
		voyant.Color = Color3.fromRGB(60, 255, 90)
		fusePrompt.Enabled = false
		powerOn()
	end)
	candle(Vector3.new(60, 0, -62))
	pickup("Pile", Vector3.new(76, 0, -64), Color3.fromRGB(120, 255, 140), "Ramasser", batteryTaken)

	-- Le dernier fusible est caché dans le salon (sous le fauteuil)
	pickup("Fusible", Vector3.new(-70, 0, 24), Color3.fromRGB(255, 220, 80), "Ramasser", fuseTaken)
	pickup("Pile", Vector3.new(14, 0, 30), Color3.fromRGB(120, 255, 140), "Ramasser", batteryTaken)
end

---------------------------------------------------------------------------
-- LE VEILLEUR
---------------------------------------------------------------------------

local monster = {
	model = nil :: Model?,
	pos = Vector3.zero,
	facing = Vector3.new(0, 0, 1),
	state = "dort", -- dort | patrouille | chasse | recherche | festin
	target = nil :: Player?,
	lastSeen = Vector3.zero,
	lastSeenAt = 0,
	waypoints = {} :: { Vector3 },
	goal = nil :: Vector3?,
	computing = false,
	pauseUntil = 0,
	speed = MONSTER_PATROL_SPEED,
	t = 0,
}

local MONSTER_HEIGHT = 6.9 -- hauteur du centre du torse au-dessus du sol

local function buildMonster(): Model
	local m = Instance.new("Model")
	m.Name = "LeVeilleur"
	local skin = Color3.fromRGB(20, 18, 24)
	local function add(props)
		props.CanCollide = false
		props.Parent = m
		return part(props)
	end
	local torso = add({ Name = "Torse", Size = Vector3.new(2.6, 5, 1.4), CFrame = CFrame.new(0, 0, 0), Color = skin, Material = Enum.Material.SmoothPlastic })
	add({ Name = "Tete", Size = Vector3.new(1.8, 2.4, 1.8), CFrame = CFrame.new(0, 3.9, -0.3), Color = Color3.fromRGB(205, 200, 195), Material = Enum.Material.SmoothPlastic })
	for _, s in { -1, 1 } do
		add({ Name = "Oeil", Size = Vector3.new(0.5, 0.35, 0.2), CFrame = CFrame.new(s * 0.45, 4.2, -1.25), Color = Color3.new(1, 1, 1), Material = Enum.Material.Neon })
		add({ Name = "Bras", Size = Vector3.new(0.6, 7.5, 0.6), CFrame = CFrame.new(s * 1.7, -1.4, -0.4) * CFrame.Angles(math.rad(-12), 0, 0), Color = skin })
		add({ Name = "Griffe", Size = Vector3.new(0.9, 1.2, 0.3), CFrame = CFrame.new(s * 1.7, -5.3, -1.2), Color = Color3.fromRGB(120, 110, 100), Material = Enum.Material.Slate })
		add({ Name = "Jambe", Size = Vector3.new(0.7, 4, 0.7), CFrame = CFrame.new(s * 0.7, -4.3, 0), Color = skin })
	end
	add({ Name = "Bouche", Size = Vector3.new(1, 0.35, 0.2), CFrame = CFrame.new(0, 3.2, -1.25), Color = Color3.fromRGB(60, 0, 0), Material = Enum.Material.Neon })
	local glow = light(torso, Color3.fromRGB(150, 20, 30), 16, 0.8)
	glow.Shadows = false
	local smoke = Instance.new("ParticleEmitter")
	smoke.Color = ColorSequence.new(Color3.fromRGB(10, 10, 12))
	smoke.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 2), NumberSequenceKeypoint.new(1, 4) })
	smoke.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.5), NumberSequenceKeypoint.new(1, 1) })
	smoke.Lifetime = NumberRange.new(1, 1.6)
	smoke.Rate = 18
	smoke.Speed = NumberRange.new(0.5, 1.5)
	smoke.SpreadAngle = Vector2.new(180, 180)
	smoke.Parent = torso
	m.PrimaryPart = torso
	m.Parent = Manor
	return m
end

local losParams = RaycastParams.new()
losParams.FilterType = Enum.RaycastFilterType.Exclude

local function canSee(from: Vector3, char: Model, to: Vector3): boolean
	local list: { Instance } = { char }
	if monster.model then
		table.insert(list, monster.model)
	end
	losParams.FilterDescendantsInstances = list
	local hit = workspace:Raycast(from, to - from, losParams)
	return hit == nil
end

local path = PathfindingService:CreatePath({ AgentRadius = 2.2, AgentHeight = 8, AgentCanJump = false, WaypointSpacing = 5 })

local function requestPath(goal: Vector3)
	if monster.computing then
		return
	end
	monster.computing = true
	monster.goal = goal
	task.spawn(function()
		local from = Vector3.new(monster.pos.X, 1, monster.pos.Z)
		local ok = pcall(function()
			path:ComputeAsync(from, Vector3.new(goal.X, 1, goal.Z))
		end)
		if ok and path.Status == Enum.PathStatus.Success then
			local pts = {}
			for _, wp in path:GetWaypoints() do
				table.insert(pts, wp.Position)
			end
			table.remove(pts, 1)
			monster.waypoints = pts
		else
			-- Pas de chemin : avancer tout droit seulement si rien ne bloque
			local flat = Vector3.new(goal.X, MONSTER_HEIGHT, goal.Z)
			losParams.FilterDescendantsInstances = if monster.model then { monster.model } else {}
			local hit = workspace:Raycast(monster.pos, flat - monster.pos, losParams)
			monster.waypoints = if hit == nil or (hit.Instance.Parent and hit.Instance.Parent:FindFirstChildOfClass("Humanoid")) then { flat } else {}
		end
		monster.computing = false
	end)
end

local function patrolPoint(): Vector3
	local r = ROOMS[math.random(1, #ROOMS)]
	return Vector3.new(math.random(r.x1 + 8, r.x2 - 8), 0, math.random(r.z1 + 5, r.z2 - 5))
end

local function wakeMonster()
	monster.model = buildMonster()
	monster.pos = Vector3.new(60, MONSTER_HEIGHT, -80) -- il sort de la cave
	monster.state = "patrouille"
	monster.waypoints = {}
	monster.target = nil
	monster.speed = MONSTER_PATROL_SPEED
	round.monsterAwake = true
	notify(nil, "Un grincement monte de la cave… Le Veilleur s'est réveillé.", Color3.fromRGB(255, 90, 90))
end

local function catchPlayer(player: Player)
	local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if not hum or hum.Health <= 0 then
		return
	end
	releaseHidden(player)
	JumpscareRemote:FireClient(player)
	round.catches += 1
	monster.state = "festin"
	monster.pauseUntil = os.clock() + 3
	monster.target = nil
	monster.waypoints = {}
	task.delay(0.15, function()
		hum.Health = 0
	end)
	notify(nil, player.DisplayName .. " a été attrapé par le Veilleur…", Color3.fromRGB(255, 80, 80))
end

-- Choisit la proie la plus visible / audible
local function sense(now: number)
	if not monster.model then
		return
	end
	local eye = monster.pos + Vector3.new(0, 4, 0)
	local best, bestScore, bestPos = nil, math.huge, nil
	for _, plr in Players:GetPlayers() do
		local char = plr.Character
		local hrp = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		if char and hrp and hum and hum.Health > 0 and not round.escaped[plr] and insideManor(hrp.Position) then
			local d = (hrp.Position - monster.pos).Magnitude
			local hidden = plr:GetAttribute("Hidden") == true
			if hidden then
				-- Vu en train de se cacher : il l'arrache de l'armoire
				local since = plr:GetAttribute("HiddenSince") or 0
				if monster.state == "chasse" and monster.target == plr and now - since < 2.5 and d < 14 then
					catchPlayer(plr)
					return
				end
			else
				if d < CATCH_RANGE and canSee(eye, char, hrp.Position) then
					catchPlayer(plr)
					return
				end
				local range = if lampOn[plr] then SIGHT_RANGE_LAMP else SIGHT_RANGE
				local seen = d < range and canSee(eye, char, hrp.Position + Vector3.new(0, 1.5, 0))
				local speed = hrp.AssemblyLinearVelocity.Magnitude
				local heard = speed > WALK_SPEED + 3 and d < HEARING_RANGE
				if (seen or heard) and d < bestScore then
					best, bestScore, bestPos = plr, d, hrp.Position
				end
			end
		end
	end
	if best and bestPos then
		if monster.state ~= "chasse" or monster.target ~= best then
			monster.state = "chasse"
			monster.target = best
			monster.waypoints = {}
		end
		monster.lastSeen = bestPos
		monster.lastSeenAt = now
	elseif monster.state == "chasse" and now - monster.lastSeenAt > 4 then
		monster.state = "recherche"
		monster.target = nil
		monster.waypoints = {}
		requestPath(monster.lastSeen)
	end
end

local function updateMonster(dt: number, now: number)
	if not monster.model then
		return
	end
	monster.t += dt
	if now < monster.pauseUntil then
		return
	end
	if monster.state == "festin" then
		monster.state = "patrouille"
	end

	-- Vitesse : plus rapide à chaque capture, et furieux quand le courant revient
	local base = if monster.state == "chasse" then MONSTER_CHASE_SPEED else MONSTER_PATROL_SPEED
	if round.power then
		base += 1.5
	end
	if round.doorOpen then
		base += 1
	end
	monster.speed = math.min(MONSTER_MAX_SPEED, base + round.catches * 0.6)

	-- Choix de la destination
	if monster.state == "chasse" then
		local goal = monster.lastSeen
		if not monster.goal or (monster.goal - goal).Magnitude > 4 or #monster.waypoints == 0 then
			requestPath(goal)
		end
	elseif #monster.waypoints == 0 and not monster.computing then
		if monster.state == "recherche" then
			monster.state = "patrouille"
		end
		requestPath(patrolPoint())
	end

	-- Avancer le long du chemin
	local wp = monster.waypoints[1]
	if wp then
		local target = Vector3.new(wp.X, MONSTER_HEIGHT, wp.Z)
		local delta = target - monster.pos
		local flat = Vector3.new(delta.X, 0, delta.Z)
		local step = monster.speed * dt
		if delta.Magnitude <= step then
			monster.pos = target
			table.remove(monster.waypoints, 1)
		else
			monster.pos += delta.Unit * step
		end
		if flat.Magnitude > 0.05 then
			monster.facing = flat.Unit
		end
	end

	-- Démarche saccadée
	local twitch = math.sin(monster.t * 9) * 0.25 + (if math.random() < 0.02 then 0.6 else 0)
	local p = monster.pos + Vector3.new(0, math.abs(twitch), 0)
	monster.model:PivotTo(CFrame.lookAt(p, p + monster.facing) * CFrame.Angles(0, 0, math.sin(monster.t * 4.5) * 0.06))
	if Remotes:GetAttribute("MonsterState") ~= monster.state then
		Remotes:SetAttribute("MonsterState", monster.state)
	end
end

---------------------------------------------------------------------------
-- JOUEURS
---------------------------------------------------------------------------

local function setupLamp(player: Player, char: Model)
	local head = char:WaitForChild("Head", 5) :: BasePart?
	if not head then
		return
	end
	local spot = Instance.new("SpotLight")
	spot.Name = "Lampe"
	spot.Range = 48
	spot.Angle = 55
	spot.Brightness = 3.2
	spot.Color = Color3.fromRGB(255, 244, 220)
	spot.Shadows = true
	spot.Face = Enum.NormalId.Front
	spot.Enabled = false
	spot.Parent = head
	lampOn[player] = false
	player:SetAttribute("Lamp", false)
end

local function setLamp(player: Player, on: boolean)
	local head = player.Character and player.Character:FindFirstChild("Head")
	local spot = head and head:FindFirstChild("Lampe") :: SpotLight?
	if on and (battery[player] or 0) <= 0 then
		notify(player, "La batterie est vide ! Trouve des piles.", Color3.fromRGB(255, 160, 120))
		on = false
	end
	lampOn[player] = on
	player:SetAttribute("Lamp", on)
	if spot then
		spot.Enabled = on
	end
end

LampRemote.OnServerEvent:Connect(function(player)
	setLamp(player, not lampOn[player])
end)

local keypadTries: { [Player]: number } = {}
KeypadRemote.OnServerEvent:Connect(function(player, code)
	if typeof(code) ~= "string" or round.safeOpen or round.state ~= "jeu" then
		return
	end
	local now = os.clock()
	if (keypadTries[player] or 0) > now then
		return
	end
	keypadTries[player] = now + 1
	code = code:gsub("%D", "")
	if #code == 3 then
		code = "0" .. code
	end
	-- Le coffre est dans le bureau : il faut y être
	local hrp = player.Character and player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not hrp or (hrp.Position - Vector3.new(72, 3, 33)).Magnitude > 16 then
		return
	end
	if code == round.code then
		KeypadRemote:FireClient(player, false)
		openSafe(player)
	else
		notify(player, "Code incorrect… Un bruit sourd répond au loin.", Color3.fromRGB(255, 120, 120))
		-- L'erreur fait du bruit : le Veilleur vient voir
		if monster.model and monster.state ~= "chasse" then
			monster.state = "recherche"
			monster.waypoints = {}
			requestPath(hrp.Position)
		end
	end
end)

local function onCharacter(player: Player, char: Model)
	local hum = char:WaitForChild("Humanoid") :: Humanoid
	hum.WalkSpeed = WALK_SPEED
	releaseHidden(player)
	task.spawn(setupLamp, player, char)
	if round and round.escaped[player] then
		task.wait(0.1)
		char:PivotTo(CFrame.new(SAFE_ZONE))
	end
	hum.Died:Connect(function()
		lampOn[player] = false
		releaseHidden(player)
	end)
end

local function onPlayer(player: Player)
	battery[player] = 100
	player:SetAttribute("Battery", 100)
	player:SetAttribute("SprintSpeed", SPRINT_SPEED)
	player:SetAttribute("WalkSpeed", WALK_SPEED)
	player.CharacterAdded:Connect(function(char)
		onCharacter(player, char)
	end)
	if player.Character then
		task.spawn(onCharacter, player, player.Character)
	end
	task.wait(1)
	if round then
		ObjectiveRemote:FireClient(player, Remotes:GetAttribute("Objective") or "")
	end
end

Players.PlayerAdded:Connect(onPlayer)
for _, p in Players:GetPlayers() do
	task.spawn(onPlayer, p)
end
Players.PlayerRemoving:Connect(function(player)
	releaseHidden(player)
	battery[player] = nil
	lampOn[player] = nil
	wardrobeOf[player] = nil
	keypadTries[player] = nil
	if round then
		round.escaped[player] = nil
	end
end)

---------------------------------------------------------------------------
-- MANCHES
---------------------------------------------------------------------------

local function startRound()
	round = {
		state = "jeu", timeLeft = ROUND_TIME, fuses = 0, power = false, safeOpen = false,
		hasKey = false, doorOpen = false, code = "0000", clockText = "", escaped = {},
		catches = 0, roomLights = {}, officeDoor = nil, frontDoor = nil, safeDoor = nil,
		monsterAwake = false, started = os.clock(),
	}
	monster.model = nil
	monster.state = "dort"
	monster.waypoints = {}
	buildManor()
	refreshInventory()
	setObjective("Trouve les 3 fusibles cachés dans le manoir (0/3).")
	for _, plr in Players:GetPlayers() do
		plr:SetAttribute("Escaped", false)
		battery[plr] = 100
		plr:SetAttribute("Battery", 100)
		releaseHidden(plr)
		task.spawn(function()
			plr:LoadCharacter()
		end)
	end
	notify(nil, "Les portes se referment derrière vous… Trouvez une sortie avant l'aube.", Color3.fromRGB(220, 200, 255))
end

local function endRound(reason: string)
	round.state = "fin"
	local anyEscaped = false
	for plr in round.escaped do
		if plr.Parent then
			anyEscaped = true
		end
	end
	for _, plr in Players:GetPlayers() do
		if not round.escaped[plr] then
			EndRemote:FireClient(plr, false, reason)
		end
	end
	if monster.model then
		monster.model:Destroy()
		monster.model = nil
	end
	notify(nil, if anyEscaped then "Fin de la manche : certains ont survécu…" else "Fin de la manche : le manoir a gardé tout le monde.", Color3.fromRGB(220, 200, 255))
end

-- Boucle des manches
task.spawn(function()
	while true do
		startRound()
		local last = os.clock()
		while round.state == "jeu" do
			task.wait(1)
			local now = os.clock()
			round.timeLeft -= now - last
			last = now
			RoundRemote:FireAllClients("jeu", math.max(0, math.floor(round.timeLeft)))
			if not round.monsterAwake and now - round.started > MONSTER_DELAY then
				wakeMonster()
			end
			-- Batteries
			for _, plr in Players:GetPlayers() do
				if lampOn[plr] then
					battery[plr] = math.max(0, (battery[plr] or 0) - BATTERY_DRAIN)
					plr:SetAttribute("Battery", battery[plr])
					if battery[plr] <= 0 then
						setLamp(plr, false)
					end
				end
			end
			-- Fin de manche ?
			local inside = 0
			for _, plr in Players:GetPlayers() do
				if not round.escaped[plr] then
					inside += 1
				end
			end
			if round.timeLeft <= 0 then
				endRound("L'aube ne viendra jamais pour vous… Le temps est écoulé.")
			elseif inside == 0 and #Players:GetPlayers() > 0 then
				endRound("Tout le monde s'est échappé !")
			end
		end
		for s = INTERMISSION, 1, -1 do
			RoundRemote:FireAllClients("pause", s)
			task.wait(1)
		end
	end
end)

-- Boucle du monstre
local senseTimer = 0
RunService.Heartbeat:Connect(function(dt)
	if not round or round.state ~= "jeu" then
		return
	end
	local now = os.clock()
	senseTimer -= dt
	if senseTimer <= 0 then
		senseTimer = 0.15
		sense(now)
	end
	updateMonster(dt, now)
end)

print("Le Manoir des Ombres est prêt…")
