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
local ScreechRemote = remote("Screech") -- (position du monstre) : hurlement quand il repère une proie
local LightningRemote = remote("Lightning") -- éclair de l'orage

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
local bloom = Instance.new("BloomEffect")
bloom.Intensity = 0.9
bloom.Size = 32
bloom.Threshold = 0.85
bloom.Parent = Lighting
local dof = Instance.new("DepthOfFieldEffect")
dof.FarIntensity = 0.3
dof.FocusDistance = 18
dof.InFocusRadius = 28
dof.NearIntensity = 0
dof.Parent = Lighting
local clouds = Instance.new("Clouds")
clouds.Cover = 0.8
clouds.Density = 0.75
clouds.Color = Color3.fromRGB(45, 45, 60)
clouds.Parent = workspace.Terrain

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
	-- Les yeux du portrait s'allument quand le Veilleur approche (géré par le client)
	for _, side in { -1, 1 } do
		for _, face in { -1, 1 } do
			part({ Name = "OeilTableau", Size = Vector3.new(h * 0.05, h * 0.03, 0.05), CFrame = cf * CFrame.new(side * h * 0.06, h * 0.15, face * h * 0.18), Color = Color3.fromRGB(20, 15, 15), Material = Enum.Material.Neon, CanCollide = false })
		end
	end
end

-- Fenêtre éclairée par la lune (orientée vers l'intérieur)
local function moonWindow(pos: Vector3, inward: Vector3)
	local cf = CFrame.lookAt(pos, pos + inward)
	local glass = part({ Name = "Fenetre", Size = Vector3.new(5, 6.5, 0.2), CFrame = cf, Color = Color3.fromRGB(120, 140, 210), Material = Enum.Material.Neon, Transparency = 0.55, CanCollide = false, CanQuery = true })
	part({ Name = "Encadrement", Size = Vector3.new(5.8, 0.5, 0.5), CFrame = cf * CFrame.new(0, 3.4, 0), Color = Color3.fromRGB(45, 30, 22), Material = Enum.Material.Wood })
	part({ Name = "Encadrement", Size = Vector3.new(5.8, 0.6, 1), CFrame = cf * CFrame.new(0, -3.4, -0.3), Color = Color3.fromRGB(45, 30, 22), Material = Enum.Material.Wood })
	part({ Name = "Croisillon", Size = Vector3.new(0.25, 6.5, 0.3), CFrame = cf, Color = Color3.fromRGB(35, 25, 20), Material = Enum.Material.Wood, CanCollide = false })
	part({ Name = "Croisillon", Size = Vector3.new(5, 0.25, 0.3), CFrame = cf * CFrame.new(0, 0.8, 0), Color = Color3.fromRGB(35, 25, 20), Material = Enum.Material.Wood, CanCollide = false })
	for _, sx in { -1, 1 } do
		part({ Name = "Rideau", Size = Vector3.new(1.6, 9, 0.3), CFrame = cf * CFrame.new(sx * 3.4, -0.6, -0.4), Color = Color3.fromRGB(80, 15, 22), Material = Enum.Material.Fabric, CanCollide = false })
	end
	local spot = Instance.new("SpotLight")
	spot.Face = Enum.NormalId.Front
	spot.Color = Color3.fromRGB(140, 160, 255)
	spot.Range = 34
	spot.Angle = 70
	spot.Brightness = 1.1
	spot.Shadows = true
	spot.Parent = glass
	glass:SetAttribute("Fenetre", true)
	-- Rayon de lune visible (poussière éclairée)
	local a0 = Instance.new("Attachment")
	a0.Parent = glass
	local a1 = Instance.new("Attachment")
	a1.Position = Vector3.new(0, -6, -14)
	a1.Parent = glass
	local beam = Instance.new("Beam")
	beam.Attachment0 = a0
	beam.Attachment1 = a1
	beam.FaceCamera = true
	beam.Width0 = 4.5
	beam.Width1 = 8
	beam.LightEmission = 1
	beam.LightInfluence = 0
	beam.Color = ColorSequence.new(Color3.fromRGB(150, 170, 255))
	beam.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.8), NumberSequenceKeypoint.new(1, 1) })
	beam.Segments = 1
	beam.Parent = glass
end

-- Toile d'araignée dans un coin du plafond
local function cobweb(corner: Vector3, dirX: number, dirZ: number)
	for i = 0, 4 do
		local a = math.rad(i * 22.5)
		local len = 4.5
		local tip = corner + Vector3.new(dirX * math.cos(a) * len, -math.sin(a) * len * 0.6 - 0.3, dirZ * math.sin(a) * len)
		local mid = (corner + tip) / 2
		part({ Name = "Toile", Size = Vector3.new(0.04, 0.04, (tip - corner).Magnitude), CFrame = CFrame.lookAt(mid, tip), Color = Color3.fromRGB(220, 220, 220), Material = Enum.Material.SmoothPlastic, Transparency = 0.55, CanCollide = false })
	end
	for r = 1, 3 do
		local prev: Vector3? = nil
		for i = 0, 4 do
			local a = math.rad(i * 22.5)
			local len = r * 1.3
			local pt = corner + Vector3.new(dirX * math.cos(a) * len, -math.sin(a) * len * 0.6 - 0.3, dirZ * math.sin(a) * len)
			if prev then
				part({ Name = "Toile", Size = Vector3.new(0.03, 0.03, (pt - prev).Magnitude), CFrame = CFrame.lookAt((prev + pt) / 2, pt), Color = Color3.fromRGB(220, 220, 220), Transparency = 0.6, CanCollide = false })
			end
			prev = pt
		end
	end
end

-- Griffures sur un mur
local function clawMarks(pos: Vector3, inward: Vector3)
	local cf = CFrame.lookAt(pos, pos + inward)
	for i = -1, 1 do
		part({ Name = "Griffure", Size = Vector3.new(0.18, 3.2, 0.05), CFrame = cf * CFrame.new(i * 0.55, -i * 0.15, 0) * CFrame.Angles(0, 0, math.rad(18)), Color = Color3.fromRGB(70, 8, 10), Material = Enum.Material.SmoothPlastic, CanCollide = false })
	end
end

-- Message écrit sur un mur
local function wallWriting(pos: Vector3, inward: Vector3, msg: string)
	local p = part({ Name = "Inscription", Size = Vector3.new(10, 3, 0.05), CFrame = CFrame.lookAt(pos, pos + inward), Transparency = 1, CanCollide = false })
	local sg = surfaceText(p, Enum.NormalId.Front, msg, Color3.fromRGB(110, 10, 12), Enum.Font.Creepster)
	sg.LightInfluence = 1
end

-- Lustre à bougies (allumé avec le courant)
local function chandelier(c: Vector3): PointLight
	part({ Name = "Chaine", Size = Vector3.new(0.15, 2.4, 0.15), CFrame = CFrame.new(c.X, WALL_H - 1.2, c.Z), Color = Color3.fromRGB(40, 38, 35), Material = Enum.Material.Metal, CanCollide = false })
	local ring = part({ Name = "Lustre", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.3, 5, 5), CFrame = CFrame.new(c.X, WALL_H - 2.5, c.Z) * CFrame.Angles(0, 0, math.rad(90)), Color = Color3.fromRGB(70, 60, 40), Material = Enum.Material.Metal, CanCollide = false })
	for i = 0, 5 do
		local a = i / 6 * math.pi * 2
		local p = Vector3.new(c.X + math.cos(a) * 2.2, WALL_H - 2.2, c.Z + math.sin(a) * 2.2)
		part({ Name = "BougieLustre", Size = Vector3.new(0.25, 0.7, 0.25), CFrame = CFrame.new(p), Color = Color3.fromRGB(230, 220, 195), CanCollide = false })
		part({ Name = "FlammeLustre", Shape = Enum.PartType.Ball, Size = Vector3.one * 0.25, CFrame = CFrame.new(p + Vector3.new(0, 0.5, 0)), Color = Color3.fromRGB(255, 200, 110), Material = Enum.Material.Neon, Transparency = 1, CanCollide = false })
		part({ Name = "Pampille", Size = Vector3.new(0.12, 0.6, 0.12), CFrame = CFrame.new(c.X + math.cos(a + 0.5) * 2.4, WALL_H - 3.1, c.Z + math.sin(a + 0.5) * 2.4), Color = Color3.fromRGB(200, 220, 255), Material = Enum.Material.Glass, Transparency = 0.3, CanCollide = false })
	end
	local l = light(ring, Color3.fromRGB(255, 205, 140), 42, 1.2)
	l.Enabled = false
	return l
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
	task.delay(0.6, function()
		for _, d in Manor:GetDescendants() do
			if d.Name == "FlammeLustre" and d:IsA("BasePart") then
				d.Transparency = 0
			end
		end
	end)
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
		table.insert(round.roomLights, chandelier(c))
		-- Poussière qui flotte dans la pièce
		local dustBox = part({ Name = "Poussiere", Size = Vector3.new(r.x2 - r.x1 - 2, WALL_H - 2, r.z2 - r.z1 - 2), CFrame = CFrame.new(c.X, WALL_H / 2, c.Z), Transparency = 1, CanCollide = false })
		local dust = Instance.new("ParticleEmitter")
		dust.Shape = Enum.ParticleEmitterShape.Box
		dust.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
		dust.Rate = math.clamp((r.x2 - r.x1) * (r.z2 - r.z1) / 300, 3, 12)
		dust.Lifetime = NumberRange.new(8, 14)
		dust.Speed = NumberRange.new(0.1, 0.4)
		dust.SpreadAngle = Vector2.new(180, 180)
		dust.Size = NumberSequence.new(0.09)
		dust.Color = ColorSequence.new(Color3.fromRGB(220, 215, 200))
		dust.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.3, 0.45), NumberSequenceKeypoint.new(0.7, 0.45), NumberSequenceKeypoint.new(1, 1) })
		dust.LightEmission = 0.4
		dust.LightInfluence = 1
		dust.Parent = dustBox
		-- Toiles d'araignée dans deux coins
		cobweb(Vector3.new(r.x1 + 0.6, WALL_H - 0.2, r.z1 + 0.6), 1, 1)
		cobweb(Vector3.new(r.x2 - 0.6, WALL_H - 0.2, r.z2 - 0.6), -1, -1)
	end

	-- Fenêtres sur les murs extérieurs
	for _, x in { -66, -44, -14, 12, 36 } do
		moonWindow(Vector3.new(x, 7.5, -59.3), Vector3.new(0, 0, 1))
	end
	for _, x in { -62, -42, 42, 62 } do
		moonWindow(Vector3.new(x, 7.5, 59.3), Vector3.new(0, 0, -1))
	end
	for _, z in { -46, -24, 24, 46 } do
		moonWindow(Vector3.new(-79.3, 7.5, z), Vector3.new(1, 0, 0))
		moonWindow(Vector3.new(79.3, 7.5, z), Vector3.new(-1, 0, 0))
	end

	-- Traces du Veilleur
	clawMarks(Vector3.new(60, 6, -59.4), Vector3.new(0, 0, 1))
	clawMarks(Vector3.new(-30.6, 5, -20), Vector3.new(1, 0, 0))
	clawMarks(Vector3.new(30, 7, 5.4), Vector3.new(0, 0, -1))
	wallWriting(Vector3.new(79.3, 11.6, 0), Vector3.new(-1, 0, 0), "IL VOIT TA LUMIÈRE")
	wallWriting(Vector3.new(52, 9, -59.3), Vector3.new(0, 0, 1), "NE COURS PAS")
	wallWriting(Vector3.new(60, 8, -89.3), Vector3.new(0, 0, 1), "IL DORT ICI")

	-- Orage : pluie autour du manoir
	local rainZones = {
		{ CFrame.new(0, 70, 140), Vector3.new(320, 1, 160) },
		{ CFrame.new(0, 70, -170), Vector3.new(320, 1, 160) },
		{ CFrame.new(-150, 70, -15), Vector3.new(140, 1, 150) },
		{ CFrame.new(150, 70, -15), Vector3.new(140, 1, 150) },
	}
	for _, z in rainZones do
		local cloud = part({ Name = "Pluie", Size = z[2], CFrame = z[1], Transparency = 1, CanCollide = false })
		local rain = Instance.new("ParticleEmitter")
		rain.Shape = Enum.ParticleEmitterShape.Box
		rain.EmissionDirection = Enum.NormalId.Bottom
		rain.Rate = 600
		rain.Lifetime = NumberRange.new(0.9, 1)
		rain.Speed = NumberRange.new(75, 85)
		rain.Size = NumberSequence.new(0.12)
		rain.Squash = NumberSequence.new(4)
		rain.Color = ColorSequence.new(Color3.fromRGB(170, 185, 220))
		rain.Transparency = NumberSequence.new(0.55)
		rain.LightEmission = 0.2
		rain.Orientation = Enum.ParticleOrientation.FacingCameraWorldUp
		rain.Parent = cloud
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
	phase = 0,
	lean = nil :: number?,
}

local MONSTER_HEIGHT = 5.4 -- hauteur des hanches au-dessus du sol

-- Squelette articulé : chaque pièce appartient à un « groupe » animé par le script
type RigPart = { part: BasePart, group: string, offset: CFrame }
local rig: { RigPart } = {}
local rigParts: { BasePart } = {}
local rigCFrames: { CFrame } = {}
local eyeParts: { BasePart } = {}
local headTwitch = { yaw = 0, roll = 0, pitch = 0, next = 0 }

local SKIN = Color3.fromRGB(28, 24, 27)
local BONE = Color3.fromRGB(168, 156, 134)
local EYE = Color3.fromRGB(255, 18, 8)

local function buildMonster(): Model
	local m = Instance.new("Model")
	m.Name = "LeVeilleur"
	table.clear(rig)
	table.clear(rigParts)
	table.clear(rigCFrames)
	table.clear(eyeParts)

	local function add(group: string, offset: CFrame, props: { [string]: any }): BasePart
		props.CanCollide = false
		props.CanQuery = false
		props.CastShadow = true
		props.Parent = m
		props.CFrame = offset
		local p = part(props)
		table.insert(rig, { part = p, group = group, offset = offset })
		table.insert(rigParts, p)
		table.insert(rigCFrames, offset)
		return p
	end

	-- Torse décharné, côtes et colonne hérissée
	local root = add("body", CFrame.new(0, 2, 0), { Name = "Torse", Size = Vector3.new(2.4, 4.2, 1.5), Color = SKIN, Material = Enum.Material.Slate })
	add("body", CFrame.new(0, 0.1, 0), { Name = "Bassin", Size = Vector3.new(2, 1.2, 1.3), Color = SKIN, Material = Enum.Material.Slate })
	for i = 0, 5 do
		local y = 1.2 + i * 0.5
		add("body", CFrame.new(0, y, -0.78), { Name = "Cote", Size = Vector3.new(2.2 - math.abs(i - 2.5) * 0.15, 0.16, 0.12), Color = BONE, Material = Enum.Material.Limestone })
	end
	add("body", CFrame.new(0, 2.4, -0.8), { Name = "Sternum", Size = Vector3.new(0.3, 2.6, 0.14), Color = BONE, Material = Enum.Material.Limestone })
	for i = 0, 5 do
		add("body", CFrame.new(0, 0.6 + i * 0.7, 0.85) * CFrame.Angles(math.rad(35), 0, 0), {
			ClassName = "WedgePart", Name = "Epine", Size = Vector3.new(0.25, 0.9 - i * 0.05, 0.7), Color = BONE, Material = Enum.Material.Limestone,
		})
	end
	-- Bosse et lambeaux qui pendent du dos
	add("body", CFrame.new(0, 3.2, 0.7), { Name = "Bosse", Shape = Enum.PartType.Ball, Size = Vector3.one * 2.6, Color = SKIN, Material = Enum.Material.Slate })
	for i = 0, 6 do
		local x = -1.3 + i * 0.43
		local len = 2.2 + (i * 37 % 7) * 0.35
		add("body", CFrame.new(x, 3.4 - len / 2, 0.9 + math.abs(x) * 0.15) * CFrame.Angles(math.rad(8 + (i % 3) * 6), 0, math.rad((i - 3) * 4)), {
			Name = "Lambeau", Size = Vector3.new(0.38, len, 0.06), Color = Color3.fromRGB(12, 10, 12), Material = Enum.Material.Fabric, Transparency = 0.1,
		})
	end
	-- Cou et crâne allongé
	add("neck", CFrame.new(0, 0.7, -0.1), { Name = "Cou", Size = Vector3.new(0.6, 1.6, 0.6), Color = SKIN, Material = Enum.Material.Slate })
	local skull = add("neck", CFrame.new(0, 1.9, -0.6), { Name = "Crane", Size = Vector3.new(1.7, 1.5, 2.6), Color = BONE, Material = Enum.Material.Limestone })
	add("neck", CFrame.new(0, 2.55, 0.1), { Name = "Crete", Size = Vector3.new(0.9, 0.5, 2.2), Color = Color3.fromRGB(160, 150, 130), Material = Enum.Material.Limestone })
	-- Arcade sourcilière et cavité nasale
	add("neck", CFrame.new(0, 2.75, -1.55) * CFrame.Angles(math.rad(-20), 0, 0), { Name = "Arcade", Size = Vector3.new(1.9, 0.35, 0.6), Color = Color3.fromRGB(120, 110, 95), Material = Enum.Material.Limestone })
	add("neck", CFrame.new(0, 1.6, -1.92), { Name = "Nez", Size = Vector3.new(0.35, 0.45, 0.1), Color = Color3.new(0, 0, 0) })
	-- Cornes recourbées vers l'arrière
	for _, sx in { -1, 1 } do
		local base = CFrame.new(sx * 0.6, 2.6, 0.5)
		local seg = base
		for k = 1, 4 do
			local len = 1.3 - k * 0.18
			seg = seg * CFrame.Angles(math.rad(-38), 0, math.rad(sx * -8)) * CFrame.new(0, len / 2, 0)
			add("neck", seg, { Name = "Corne", Size = Vector3.new(0.42 - k * 0.07, len, 0.42 - k * 0.07), Color = Color3.fromRGB(40, 34, 30), Material = Enum.Material.Basalt })
			seg = seg * CFrame.new(0, len / 2, 0)
		end
	end
	-- Longs crocs qui dépassent
	for _, sx in { -1, 1 } do
		add("neck", CFrame.new(sx * 0.55, 0.75, -1.85) * CFrame.Angles(math.rad(180), 0, 0), {
			ClassName = "WedgePart", Name = "GrandCroc", Size = Vector3.new(0.16, 1.2, 0.25), Color = Color3.fromRGB(240, 235, 215), Material = Enum.Material.Limestone,
		})
	end
	-- Six yeux rouges, de tailles différentes
	local eyeSpots = { { -0.55, 2.15, -1.85, 0.32 }, { 0.55, 2.15, -1.85, 0.32 }, { -0.35, 2.5, -1.7, 0.2 }, { 0.38, 2.48, -1.7, 0.22 }, { -0.72, 1.82, -1.6, 0.18 }, { 0.7, 1.85, -1.6, 0.16 } }
	for _, e in eyeSpots do
		add("neck", CFrame.new(e[1], e[2], e[3] - 0.05), { Name = "Orbite", Shape = Enum.PartType.Ball, Size = Vector3.one * (e[4] + 0.18), Color = Color3.new(0, 0, 0) })
		local eye = add("neck", CFrame.new(e[1], e[2], e[3] - 0.22), { Name = "Oeil", Shape = Enum.PartType.Ball, Size = Vector3.one * e[4], Color = EYE, Material = Enum.Material.Neon })
		table.insert(eyeParts, eye)
	end
	-- Mâchoire supérieure et crocs
	for i = 0, 5 do
		local x = -0.62 + i * 0.25
		add("neck", CFrame.new(x, 1.15, -1.75) * CFrame.Angles(math.rad(180), 0, 0), {
			ClassName = "WedgePart", Name = "Croc", Size = Vector3.new(0.12, 0.55 + (i % 2) * 0.25, 0.18), Color = Color3.fromRGB(235, 228, 205), Material = Enum.Material.Limestone,
		})
	end
	local mouthGlow = add("neck", CFrame.new(0, 1.05, -1.2), { Name = "Gorge", Size = Vector3.new(1.1, 0.4, 1), Color = Color3.fromRGB(120, 0, 0), Material = Enum.Material.Neon })
	-- Mâchoire inférieure (s'ouvre)
	add("jaw", CFrame.new(0, -0.2, -0.9), { Name = "Machoire", Size = Vector3.new(1.4, 0.35, 2), Color = BONE, Material = Enum.Material.Limestone })
	for i = 0, 5 do
		local x = -0.62 + i * 0.25
		add("jaw", CFrame.new(x, 0.2, -1.75), {
			ClassName = "WedgePart", Name = "Croc", Size = Vector3.new(0.12, 0.5 + ((i + 1) % 2) * 0.2, 0.18), Color = Color3.fromRGB(235, 228, 205), Material = Enum.Material.Limestone,
		})
	end
	-- Bras démesurés
	for _, side in { "L", "R" } do
		local s = if side == "L" then -1 else 1
		add("arm" .. side, CFrame.new(0, -2, 0), { Name = "Bras", Size = Vector3.new(0.65, 4.2, 0.65), Color = SKIN, Material = Enum.Material.Slate })
		add("arm" .. side, CFrame.new(0, 0, 0), { Name = "Epaule", Shape = Enum.PartType.Ball, Size = Vector3.one * 1.1, Color = BONE, Material = Enum.Material.Limestone })
		add("fore" .. side, CFrame.new(0, -2.3, 0), { Name = "AvantBras", Size = Vector3.new(0.5, 4.6, 0.5), Color = SKIN, Material = Enum.Material.Slate })
		add("fore" .. side, CFrame.new(0, -4.8, -0.1), { Name = "Main", Size = Vector3.new(0.8, 0.6, 0.9), Color = SKIN, Material = Enum.Material.Slate })
		for k = 0, 3 do
			local x = (-0.36 + k * 0.24) * s
			add("fore" .. side, CFrame.new(x, -5.1, -0.35) * CFrame.Angles(math.rad(-25), 0, 0), { Name = "Doigt", Size = Vector3.new(0.14, 1.1, 0.14), Color = SKIN, Material = Enum.Material.Slate })
			add("fore" .. side, CFrame.new(x, -6.3, -0.95) * CFrame.Angles(math.rad(-35), 0, 0), {
				ClassName = "WedgePart", Name = "Griffe", Size = Vector3.new(0.1, 2.2 - math.abs(k - 1.5) * 0.3, 0.26), Color = Color3.fromRGB(25, 22, 20), Material = Enum.Material.Basalt,
			})
		end
		-- Jambes aux genoux inversés
		add("leg" .. side, CFrame.new(0, -1.4, 0), { Name = "Cuisse", Size = Vector3.new(0.85, 2.9, 0.85), Color = SKIN, Material = Enum.Material.Slate })
		add("shin" .. side, CFrame.new(0, -1.4, 0), { Name = "Tibia", Size = Vector3.new(0.6, 2.9, 0.6), Color = SKIN, Material = Enum.Material.Slate })
		add("shin" .. side, CFrame.new(0, -2.95, -0.55), { Name = "Pied", Size = Vector3.new(0.7, 0.35, 1.6), Color = SKIN, Material = Enum.Material.Slate })
		for k = -1, 1, 2 do
			add("shin" .. side, CFrame.new(k * 0.22, -2.95, -1.5) * CFrame.Angles(math.rad(-90), 0, 0), {
				ClassName = "WedgePart", Name = "Ergot", Size = Vector3.new(0.12, 0.7, 0.25), Color = Color3.fromRGB(30, 26, 22), Material = Enum.Material.Basalt,
			})
		end
	end

	-- Lueurs et fumée
	local eyeLight = light(skull, EYE, 14, 1.4)
	eyeLight.Shadows = false
	local throat = light(mouthGlow, Color3.fromRGB(200, 20, 10), 8, 0.6)
	throat.Shadows = false
	local smoke = Instance.new("ParticleEmitter")
	smoke.Color = ColorSequence.new(Color3.fromRGB(8, 6, 10))
	smoke.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.5), NumberSequenceKeypoint.new(1, 5) })
	smoke.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.55), NumberSequenceKeypoint.new(1, 1) })
	smoke.Lifetime = NumberRange.new(1.2, 2)
	smoke.Rate = 22
	smoke.Speed = NumberRange.new(0.3, 1.2)
	smoke.SpreadAngle = Vector2.new(180, 180)
	smoke.RotSpeed = NumberRange.new(-40, 40)
	smoke.Parent = root
	local drip = Instance.new("ParticleEmitter")
	drip.Name = "Bave"
	drip.Color = ColorSequence.new(Color3.fromRGB(120, 10, 10))
	drip.Size = NumberSequence.new(0.12)
	drip.Lifetime = NumberRange.new(0.6, 0.9)
	drip.Rate = 6
	drip.Speed = NumberRange.new(0, 0.5)
	drip.Acceleration = Vector3.new(0, -30, 0)
	drip.LightEmission = 0.3
	drip.Parent = mouthGlow
	m:SetAttribute("Jaw", 0)
	m.PrimaryPart = root
	m.Parent = Manor
	return m
end

-- Pose procédurale : marche courbée, tête qui se tord, chasse à quatre pattes
local function animateMonster(dt: number, now: number)
	local mdl = monster.model
	if not mdl then
		return
	end
	local chasing = monster.state == "chasse"
	local feasting = monster.state == "festin"
	local moving = #monster.waypoints > 0 and not feasting
	monster.phase = (monster.phase or 0) + dt * (if moving then monster.speed * 0.42 else 1.2)
	local ph = monster.phase

	-- Posture qui change en douceur
	local targetLean = if chasing then math.rad(68) elseif feasting then math.rad(75) else math.rad(42)
	monster.lean = (monster.lean or targetLean) + (targetLean - (monster.lean or targetLean)) * math.min(1, dt * 4)
	local lean = monster.lean

	-- Tête : à-coups brusques en patrouille, fixe en chasse
	if now > headTwitch.next then
		headTwitch.next = now + (if chasing then 0.25 else 0.4 + math.random() * 1.6)
		headTwitch.yaw = if chasing then (math.random() - 0.5) * 0.15 else (math.random() - 0.5) * 1.4
		headTwitch.roll = if chasing then 0 else (math.random() - 0.5) * 1.1
		headTwitch.pitch = (math.random() - 0.5) * 0.4
	end
	local jaw = if chasing then -math.rad(38) - math.sin(now * 14) * 0.12
		elseif feasting then -math.abs(math.sin(now * 16)) * math.rad(45)
		else -math.rad(6) - math.max(0, math.sin(now * 0.9)) * 0.25

	local swing = if moving then math.sin(ph) else 0
	local swing2 = if moving then math.sin(ph + math.pi) else 0
	local bob = if moving then math.abs(math.sin(ph)) * 0.35 else math.sin(now * 2) * 0.06

	local G: { [string]: CFrame } = {}
	G.body = CFrame.new(0, bob, 0) * CFrame.Angles(-lean, 0, swing * 0.08)
	G.neck = G.body * CFrame.new(0, 4.1, -0.3) * CFrame.Angles(lean * 0.85 + headTwitch.pitch, headTwitch.yaw, headTwitch.roll)
	G.jaw = G.neck * CFrame.new(0, 1.1, -0.5) * CFrame.Angles(jaw, 0, 0)
	for _, side in { "L", "R" } do
		local s = if side == "L" then -1 else 1
		local sw = if side == "L" then swing else swing2
		local armPitch, elbow
		if chasing then
			-- Les bras griffent le sol vers l'avant, comme un animal
			armPitch = lean + 0.35 + sw * 0.9
			elbow = 0.5 + math.max(0, -sw) * 0.8
		elseif feasting then
			armPitch = lean + 0.9 + math.sin(now * 12 + s) * 0.2
			elbow = 1.4
		else
			armPitch = lean * 0.75 + sw * 0.35
			elbow = 0.25 + math.sin(now * 1.3 + s) * 0.08
		end
		G["arm" .. side] = G.body * CFrame.new(s * 1.6, 3.6, -0.1) * CFrame.Angles(armPitch, 0, s * 0.18)
		G["fore" .. side] = G["arm" .. side] * CFrame.new(0, -4.1, 0) * CFrame.Angles(elbow, 0, 0)
		local thigh = 0.45 + sw * (if chasing then 0.75 else 0.45)
		G["leg" .. side] = CFrame.new(s * 0.75, bob, 0) * CFrame.Angles(thigh, 0, 0)
		G["shin" .. side] = G["leg" .. side] * CFrame.new(0, -2.8, 0) * CFrame.Angles(-0.95 - math.max(0, sw) * 0.4, 0, 0)
	end

	local tremor = CFrame.Angles(0, 0, math.sin(now * 23) * 0.012)
	local rootCF = CFrame.lookAt(monster.pos, monster.pos + monster.facing) * tremor
	for i, r in rig do
		rigCFrames[i] = rootCF * (G[r.group] or CFrame.identity) * r.offset
	end
	workspace:BulkMoveTo(rigParts, rigCFrames, Enum.BulkMoveMode.FireCFrameChanged)

	-- Les yeux palpitent, plus vifs en chasse
	local glow = if chasing then 0 else 0.25 + math.sin(now * 3) * 0.15
	for _, e in eyeParts do
		e.Transparency = glow
	end
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
			if monster.state ~= "chasse" then
				for _, plr in Players:GetPlayers() do
					local h = plr.Character and plr.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
					if h and (h.Position - monster.pos).Magnitude < 90 then
						ScreechRemote:FireClient(plr, monster.pos)
					end
				end
			end
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
		animateMonster(dt, now)
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

	animateMonster(dt, now)
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
	-- Cône de lumière visible
	local a0 = Instance.new("Attachment")
	a0.Name = "LampeA0"
	a0.Position = Vector3.new(0, 0, -0.8)
	a0.Parent = head
	local a1 = Instance.new("Attachment")
	a1.Name = "LampeA1"
	a1.Position = Vector3.new(0, 0, -26)
	a1.Parent = head
	local cone = Instance.new("Beam")
	cone.Name = "Faisceau"
	cone.Attachment0 = a0
	cone.Attachment1 = a1
	cone.FaceCamera = true
	cone.Width0 = 0.8
	cone.Width1 = 16
	cone.LightEmission = 1
	cone.LightInfluence = 0
	cone.Color = ColorSequence.new(Color3.fromRGB(255, 240, 200))
	cone.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.72), NumberSequenceKeypoint.new(1, 1) })
	cone.Enabled = false
	cone.Parent = head
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
	local cone = head and head:FindFirstChild("Faisceau") :: Beam?
	if cone then
		cone.Enabled = on
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

-- Orage : éclairs réguliers
task.spawn(function()
	while true do
		task.wait(math.random(16, 38))
		LightningRemote:FireAllClients(math.random())
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
