--[[
	LE MANOIR DES OMBRES — script serveur
	À placer dans ServerScriptService (type : Script).

	Construit le camp et le manoir, gère les manches, les énigmes, le monstre
	(le Wendigo), les cachettes, la lampe torche et les sons.
	Le script client (ManoirClient) affiche l'interface et les effets d'horreur.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Lighting = game:GetService("Lighting")
local PathfindingService = game:GetService("PathfindingService")
local Debris = game:GetService("Debris")

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

local LOBBY_COUNTDOWN = 20 -- secondes avant le départ quand des joueurs sont dans le cercle
local LOBBY = Vector3.new(0, 0, 560) -- le camp, loin du manoir

-- SONS : importe les fichiers du dossier « sons » dans Roblox Studio (Gestionnaire de ressources),
-- puis colle ici leurs identifiants (le nombre seul, ou "rbxassetid://123…").
-- Un son laissé vide est simplement ignoré : le jeu fonctionne quand même.
local SOUNDS = {
	ambiance = "", -- bourdon et vent dans le manoir (boucle)
	pluie = "", -- pluie (boucle)
	tonnerre = "",
	coeur = "", -- battement de cœur quand le Wendigo approche
	hurlement = "", -- cri du Wendigo quand il te repère
	rale = "", -- souffle et râle du Wendigo (boucle, en 3D sur lui)
	pas_monstre = "", -- sabots du Wendigo
	jumpscare = "",
	ramasser = "",
	porte = "",
	armoire = "",
	bip = "", -- touches du clavier du coffre
	erreur = "", -- mauvais code
	deverrouillage = "",
	courant = "", -- retour de l'électricité
	lobby = "", -- musique du camp (boucle)
	victoire = "",
	respiration = "", -- souffle du joueur essoufflé ou caché (boucle)
}

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
-- SONS
---------------------------------------------------------------------------

local function soundId(key: string): string?
	local id = SOUNDS[key]
	if not id or id == "" then
		return nil
	end
	if tonumber(id) then
		return "rbxassetid://" .. id
	end
	return id
end

-- Les identifiants sont partagés avec le client (sons d'ambiance, cœur, jumpscare…)
local SoundFolder = Instance.new("Folder")
SoundFolder.Name = "ManoirSons"
for key in SOUNDS do
	local v = Instance.new("StringValue")
	v.Name = key
	v.Value = soundId(key) or ""
	v.Parent = SoundFolder
end
SoundFolder.Parent = ReplicatedStorage

local function playSound(key: string, parent: Instance, volume: number?, maxDist: number?, speed: number?): Sound?
	local id = soundId(key)
	if not id then
		return nil
	end
	local snd = Instance.new("Sound")
	snd.Name = "Son_" .. key
	snd.SoundId = id
	snd.Volume = volume or 1
	snd.RollOffMode = Enum.RollOffMode.InverseTapered
	snd.RollOffMinDistance = 8
	snd.RollOffMaxDistance = maxDist or 80
	snd.PlaybackSpeed = speed or 1
	snd.Parent = parent
	snd:Play()
	Debris:AddItem(snd, 12)
	return snd
end

local function playAt(key: string, pos: Vector3, volume: number?, maxDist: number?, speed: number?)
	if not soundId(key) then
		return
	end
	local anchor = Instance.new("Part")
	anchor.Name = "SourceSonore"
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.Transparency = 1
	anchor.Size = Vector3.new(0.2, 0.2, 0.2)
	anchor.CFrame = CFrame.new(pos)
	anchor.Parent = workspace
	playSound(key, anchor, volume, maxDist, speed)
	Debris:AddItem(anchor, 12)
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
	participants: { [Player]: boolean },
	out: { [Player]: boolean },
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
			playSound("armoire", handle, 0.8, 40)
			hrp.Anchored = false
			char:PivotTo(w.outside)
			hum.WalkSpeed = WALK_SPEED
			player:SetAttribute("Hidden", false)
			pr.ActionText = "Se cacher"
		elseif w.occupant == nil and not wardrobeOf[player] then
			w.occupant = player
			wardrobeOf[player] = w
			playSound("armoire", handle, 0.8, 40)
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
		playAt("ramasser", item.Position, 0.7, 30)
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
		playSound("porte", door, 1.2, 90)
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
		playSound("deverrouillage", d, 1, 50)
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
		playSound("deverrouillage", front, 1.2, 80)
		task.delay(0.4, function()
			playSound("porte", front, 1.8, 140, 0.8)
		end)
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
		local ls = player:FindFirstChild("leaderstats")
		local ev = ls and ls:FindFirstChild("Évasions") :: IntValue?
		if ev then
			ev.Value += 1
		end
		local char = player.Character
		if char then
			char:PivotTo(CFrame.new(SAFE_ZONE + Vector3.new(math.random(-8, 8), 0, math.random(-8, 8))))
		end
		notify(nil, player.DisplayName .. " s'est échappé du manoir !", Color3.fromRGB(140, 255, 160))
		EndRemote:FireClient(player, true, "Tu t'es échappé du Manoir des Ombres ! Retour au camp à la fin de la nuit.")
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
		playSound("courant", fusebox, 1.4, 160)
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
	skull = nil :: BasePart?,
	hoof = nil :: BasePart?,
	lastStep = 0,
}

local MONSTER_HEIGHT = 6.6 -- hauteur des hanches au-dessus du sol (jambes de cerf)

-- Squelette articulé : chaque pièce appartient à un « groupe » animé par le script
type RigPart = { part: BasePart, group: string, offset: CFrame }
local rig: { RigPart } = {}
local rigParts: { BasePart } = {}
local rigCFrames: { CFrame } = {}
local eyeParts: { BasePart } = {}
local headTwitch = { yaw = 0, roll = 0, pitch = 0, next = 0 }

local SKIN = Color3.fromRGB(80, 74, 68) -- peau grise de cadavre
local SKIN_DARK = Color3.fromRGB(58, 50, 46)
local BONE = Color3.fromRGB(182, 170, 148)
local FUR = Color3.fromRGB(26, 22, 20)
local ANTLER = Color3.fromRGB(96, 80, 62)
local HOOF = Color3.fromRGB(18, 16, 15)
local EYE = Color3.fromRGB(255, 18, 8)

-- Portes du manoir : le Wendigo se baisse pour passer dessous
local DOORS = {
	Vector3.new(-51, 0, -6), Vector3.new(-2, 0, -6), Vector3.new(52, 0, -6),
	Vector3.new(-54, 0, 6), Vector3.new(0, 0, 6), Vector3.new(54, 0, 6),
	Vector3.new(-30, 0, -36), Vector3.new(25, 0, -26), Vector3.new(-28, 0, 34),
	Vector3.new(64, 0, -60), Vector3.new(0, 0, 60),
}

-- Grands bois ramifiés (utilisés par le Wendigo et par le totem du camp)
local function buildAntler(add: (CFrame, { [string]: any }) -> (), base: CFrame, side: number)
	local seg = base
	for i = 1, 5 do
		local len = 1.15 - i * 0.07
		local thick = 0.3 - i * 0.035
		-- Vers le haut, vers l'extérieur (roulis) et un peu vers l'arrière (tangage positif)
		seg = seg * CFrame.Angles(math.rad(6 + i * 2), math.rad(side * 4), math.rad(if i == 1 then side * -16 else side * -5))
		add(seg * CFrame.new(0, len / 2, 0), { Name = "Bois", Size = Vector3.new(thick, len, thick), Color = ANTLER, Material = Enum.Material.Wood })
		seg = seg * CFrame.new(0, len, 0)
		-- Andouillers qui pointent vers le haut et l'avant
		if i >= 2 then
			local tine = seg * CFrame.Angles(math.rad(-48), 0, math.rad(side * (10 - i * 4)))
			for k = 1, 2 do
				local tl = 0.85 - k * 0.2 - i * 0.04
				tine = tine * CFrame.Angles(math.rad(14), 0, 0)
				add(tine * CFrame.new(0, tl / 2, 0), { Name = "Andouiller", Size = Vector3.new(thick * 0.7, tl, thick * 0.7), Color = ANTLER, Material = Enum.Material.Wood })
				tine = tine * CFrame.new(0, tl, 0)
			end
		end
	end
	add(seg * CFrame.Angles(math.rad(-20), 0, 0) * CFrame.new(0, 0.3, 0), { Name = "PointeBois", Size = Vector3.new(0.12, 0.6, 0.12), Color = Color3.fromRGB(150, 135, 110), Material = Enum.Material.Wood })
end

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

	-- Torse squelettique : cage thoracique saillante, taille creusée, vertèbres
	local root = add("body", CFrame.new(0, 3.1, 0), { Name = "Torse", Size = Vector3.new(2.1, 2.3, 1.15), Color = SKIN, Material = Enum.Material.Slate })
	add("body", CFrame.new(0, 1.35, 0), { Name = "Taille", Size = Vector3.new(1.15, 1.6, 0.75), Color = SKIN_DARK, Material = Enum.Material.Slate })
	add("body", CFrame.new(0, 0.25, 0), { Name = "Bassin", Size = Vector3.new(1.6, 0.8, 1), Color = SKIN, Material = Enum.Material.Slate })
	for i = 0, 6 do
		local y = 2.15 + i * 0.3
		add("body", CFrame.new(0, y, -0.6), { Name = "Cote", Size = Vector3.new(2.15 - math.abs(i - 3) * 0.12, 0.13, 0.12), Color = BONE, Material = Enum.Material.Limestone })
	end
	add("body", CFrame.new(0, 3.0, -0.63), { Name = "Sternum", Size = Vector3.new(0.25, 2.1, 0.12), Color = BONE, Material = Enum.Material.Limestone })
	for i = 0, 7 do
		local y = 0.6 + i * 0.5
		add("body", CFrame.new(0, y, 0.48), { Name = "Vertebre", Size = Vector3.new(0.34, 0.26, 0.34), Color = BONE, Material = Enum.Material.Limestone })
		add("body", CFrame.new(0, y, 0.72) * CFrame.Angles(math.rad(40), 0, 0), { ClassName = "WedgePart", Name = "Epine", Size = Vector3.new(0.14, 0.45, 0.35), Color = BONE, Material = Enum.Material.Limestone })
	end
	for _, sx in { -1, 1 } do
		add("body", CFrame.new(sx * 0.6, 3.5, 0.58) * CFrame.Angles(0, 0, math.rad(sx * 12)), { Name = "Omoplate", Size = Vector3.new(0.8, 1.1, 0.14), Color = SKIN_DARK, Material = Enum.Material.Slate })
	end
	-- Crinière de poils noirs autour des épaules et du cou
	for i = 0, 15 do
		local a = (i / 15 - 0.5) * math.pi * 1.4
		local len = 1.2 + (i * 53 % 9) * 0.12
		local pos = Vector3.new(math.sin(a) * 1.05, 4.0, math.cos(a) * 0.55)
		add("body", CFrame.new(pos) * CFrame.Angles(math.rad(25 + (i % 3) * 10), a, math.rad((i % 2 == 0) and 12 or -12)) * CFrame.new(0, -len / 2 + 0.3, 0), {
			Name = "Poil", Size = Vector3.new(0.22, len, 0.05), Color = FUR, Material = Enum.Material.Fabric,
		})
	end

	-- Cou et crâne de cerf
	add("neck", CFrame.new(0, 0.8, -0.15) * CFrame.Angles(math.rad(-15), 0, 0), { Name = "Cou", Size = Vector3.new(0.5, 1.8, 0.5), Color = SKIN, Material = Enum.Material.Slate })
	local skull = add("neck", CFrame.new(0, 1.85, -0.45), { Name = "Crane", Size = Vector3.new(1.25, 1.05, 1.35), Color = BONE, Material = Enum.Material.Limestone })
	add("neck", CFrame.new(0, 1.55, -1.65) * CFrame.Angles(math.rad(8), 0, 0), { Name = "Museau", Size = Vector3.new(0.72, 0.58, 1.9), Color = BONE, Material = Enum.Material.Limestone })
	add("neck", CFrame.new(0, 1.4, -2.62) * CFrame.Angles(math.rad(8), 0, 0), { Name = "BoutMuseau", Size = Vector3.new(0.55, 0.42, 0.4), Color = Color3.fromRGB(160, 148, 126), Material = Enum.Material.Limestone })
	for _, sx in { -1, 1 } do
		add("neck", CFrame.new(sx * 0.13, 1.47, -2.84), { Name = "Narine", Size = Vector3.new(0.12, 0.16, 0.06), Color = Color3.new(0, 0, 0) })
		add("neck", CFrame.new(sx * 0.5, 1.55, -1.0), { Name = "Pommette", Size = Vector3.new(0.24, 0.34, 0.95), Color = Color3.fromRGB(150, 138, 118), Material = Enum.Material.Limestone })
		-- Orbites vides où brillent deux yeux rouges
		add("neck", CFrame.new(sx * 0.48, 1.98, -0.98), { Name = "Orbite", Shape = Enum.PartType.Ball, Size = Vector3.one * 0.5, Color = Color3.new(0, 0, 0) })
		local eye = add("neck", CFrame.new(sx * 0.48, 1.98, -1.2), { Name = "Oeil", Shape = Enum.PartType.Ball, Size = Vector3.one * 0.2, Color = EYE, Material = Enum.Material.Neon })
		table.insert(eyeParts, eye)
		-- Crocs de la mâchoire supérieure
		for k = 0, 4 do
			add("neck", CFrame.new(sx * 0.27, 1.2, -1.1 - k * 0.36) * CFrame.Angles(math.rad(180), 0, 0), {
				ClassName = "WedgePart", Name = "Croc", Size = Vector3.new(0.09, 0.32 + (k % 2) * 0.16, 0.14), Color = Color3.fromRGB(225, 215, 190), Material = Enum.Material.Limestone,
			})
		end
	end
	local mouthGlow = add("neck", CFrame.new(0, 1.3, -1.55), { Name = "Gorge", Size = Vector3.new(0.45, 0.2, 1.4), Color = Color3.fromRGB(110, 0, 0), Material = Enum.Material.Neon })
	-- Mâchoire inférieure (s'ouvre)
	add("jaw", CFrame.new(0, -0.08, -1.0), { Name = "Machoire", Size = Vector3.new(0.58, 0.2, 1.95), Color = BONE, Material = Enum.Material.Limestone })
	for _, sx in { -1, 1 } do
		for k = 0, 3 do
			add("jaw", CFrame.new(sx * 0.22, 0.12, -0.6 - k * 0.38), {
				ClassName = "WedgePart", Name = "Croc", Size = Vector3.new(0.08, 0.28 + ((k + 1) % 2) * 0.12, 0.13), Color = Color3.fromRGB(225, 215, 190), Material = Enum.Material.Limestone,
			})
		end
	end
	-- Les bois
	for _, sx in { -1, 1 } do
		buildAntler(function(cf, props)
			add("neck", cf, props)
		end, CFrame.new(sx * 0.42, 2.3, -0.25), sx)
	end

	-- Bras interminables et doigts griffus
	for _, side in { "L", "R" } do
		local sgn = if side == "L" then -1 else 1
		add("arm" .. side, CFrame.new(0, 0, 0), { Name = "Epaule", Shape = Enum.PartType.Ball, Size = Vector3.one * 0.75, Color = BONE, Material = Enum.Material.Limestone })
		add("arm" .. side, CFrame.new(0, -2.2, 0), { Name = "Bras", Size = Vector3.new(0.42, 4.4, 0.42), Color = SKIN, Material = Enum.Material.Slate })
		add("fore" .. side, CFrame.new(0, 0, 0), { Name = "Coude", Shape = Enum.PartType.Ball, Size = Vector3.one * 0.5, Color = SKIN_DARK, Material = Enum.Material.Slate })
		add("fore" .. side, CFrame.new(0, -2.4, 0), { Name = "AvantBras", Size = Vector3.new(0.36, 4.8, 0.36), Color = SKIN, Material = Enum.Material.Slate })
		add("fore" .. side, CFrame.new(0, -4.95, -0.1), { Name = "Main", Size = Vector3.new(0.6, 0.42, 0.62), Color = SKIN_DARK, Material = Enum.Material.Slate })
		for k = 0, 3 do
			local x = (-0.24 + k * 0.16) * sgn
			add("fore" .. side, CFrame.new(x, -5.65, -0.35) * CFrame.Angles(math.rad(-22), 0, 0), { Name = "Doigt", Size = Vector3.new(0.09, 1.35, 0.09), Color = SKIN_DARK, Material = Enum.Material.Slate })
			add("fore" .. side, CFrame.new(x, -6.6, -0.78) * CFrame.Angles(math.rad(-38), 0, 0), {
				ClassName = "WedgePart", Name = "Griffe", Size = Vector3.new(0.07, 1.1 - math.abs(k - 1.5) * 0.15, 0.18), Color = HOOF, Material = Enum.Material.Basalt,
			})
		end
		-- Jambes de cerf : cuisse, tibia, canon et sabot
		add("leg" .. side, CFrame.new(0, -1.5, 0), { Name = "Cuisse", Size = Vector3.new(0.58, 3.0, 0.58), Color = SKIN, Material = Enum.Material.Slate })
		add("shin" .. side, CFrame.new(0, -1.5, 0), { Name = "Tibia", Size = Vector3.new(0.38, 3.0, 0.38), Color = SKIN, Material = Enum.Material.Slate })
		local ankle = CFrame.new(0, -3.0, 0) * CFrame.Angles(math.rad(70), 0, 0)
		add("shin" .. side, ankle * CFrame.new(0, -0.75, 0), { Name = "Canon", Size = Vector3.new(0.3, 1.5, 0.3), Color = SKIN_DARK, Material = Enum.Material.Slate })
		add("shin" .. side, ankle * CFrame.new(0, -1.62, -0.05), { Name = "Sabot", Size = Vector3.new(0.46, 0.36, 0.56), Color = HOOF, Material = Enum.Material.Basalt })
	end

	-- Lueurs, fumée, bave
	local eyeLight = light(skull, EYE, 12, 1.2)
	eyeLight.Shadows = false
	local throat = light(mouthGlow, Color3.fromRGB(200, 20, 10), 6, 0.5)
	throat.Shadows = false
	local smoke = Instance.new("ParticleEmitter")
	smoke.Color = ColorSequence.new(Color3.fromRGB(8, 6, 10))
	smoke.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.2), NumberSequenceKeypoint.new(1, 4) })
	smoke.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.6), NumberSequenceKeypoint.new(1, 1) })
	smoke.Lifetime = NumberRange.new(1.2, 2)
	smoke.Rate = 16
	smoke.Speed = NumberRange.new(0.3, 1.2)
	smoke.SpreadAngle = Vector2.new(180, 180)
	smoke.RotSpeed = NumberRange.new(-40, 40)
	smoke.Parent = root
	local drip = Instance.new("ParticleEmitter")
	drip.Name = "Bave"
	drip.Color = ColorSequence.new(Color3.fromRGB(120, 10, 10))
	drip.Size = NumberSequence.new(0.1)
	drip.Lifetime = NumberRange.new(0.6, 0.9)
	drip.Rate = 5
	drip.Speed = NumberRange.new(0, 0.5)
	drip.Acceleration = Vector3.new(0, -30, 0)
	drip.LightEmission = 0.3
	drip.Parent = mouthGlow

	-- Souffle rauque en boucle, audible en 3D
	local growlId = soundId("rale")
	if growlId then
		local growl = Instance.new("Sound")
		growl.Name = "Rale"
		growl.SoundId = growlId
		growl.Looped = true
		growl.Volume = 1.3
		growl.RollOffMode = Enum.RollOffMode.InverseTapered
		growl.RollOffMinDistance = 6
		growl.RollOffMaxDistance = 75
		growl.Parent = skull
		growl:Play()
	end
	monster.skull = skull
	monster.hoof = rigParts[#rigParts]
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
	local targetLean = if chasing then math.rad(68) elseif feasting then math.rad(75) else math.rad(50)
	-- Il se baisse pour passer sous les portes
	for _, d in DOORS do
		local dx, dz = d.X - monster.pos.X, d.Z - monster.pos.Z
		if dx * dx + dz * dz < 30 then
			targetLean += math.rad(24)
			break
		end
	end
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
	G.neck = G.body * CFrame.new(0, 4.2, -0.15) * CFrame.Angles(lean * 0.85 + headTwitch.pitch, headTwitch.yaw, headTwitch.roll)
	G.jaw = G.neck * CFrame.new(0, 1.25, -0.6) * CFrame.Angles(jaw * 0.8, 0, 0)
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
		G["arm" .. side] = G.body * CFrame.new(s * 1.25, 3.9, -0.05) * CFrame.Angles(armPitch, 0, s * 0.14)
		G["fore" .. side] = G["arm" .. side] * CFrame.new(0, -4.4, 0) * CFrame.Angles(elbow, 0, 0)
		local thigh = 0.45 + sw * (if chasing then 0.7 else 0.4)
		G["leg" .. side] = CFrame.new(s * 0.55, bob, 0) * CFrame.Angles(thigh, 0, 0)
		G["shin" .. side] = G["leg" .. side] * CFrame.new(0, -3.0, 0) * CFrame.Angles(-0.95 - math.max(0, sw) * 0.4, 0, 0)
	end

	local tremor = CFrame.Angles(0, 0, math.sin(now * 23) * 0.012)
	local rootCF = CFrame.lookAt(monster.pos, monster.pos + monster.facing) * tremor
	for i, r in rig do
		rigCFrames[i] = rootCF * (G[r.group] or CFrame.identity) * r.offset
	end
	workspace:BulkMoveTo(rigParts, rigCFrames, Enum.BulkMoveMode.FireCFrameChanged)

	-- Bruit de sabots à chaque pas
	if moving then
		local step = math.floor(ph / math.pi)
		if step ~= monster.lastStep then
			monster.lastStep = step
			if monster.hoof then
				playSound("pas_monstre", monster.hoof, if chasing then 1.6 else 1.1, 70, 0.85 + math.random() * 0.25)
			end
		end
	end

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
	notify(nil, "Un craquement d'os monte de la cave… Le Wendigo s'est réveillé.", Color3.fromRGB(255, 90, 90))
end

local function catchPlayer(player: Player)
	local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if not hum or hum.Health <= 0 then
		return
	end
	releaseHidden(player)
	JumpscareRemote:FireClient(player)
	round.catches += 1
	round.out[player] = true
	player:SetAttribute("InRound", false)
	local ls = player:FindFirstChild("leaderstats")
	local cap = ls and ls:FindFirstChild("Captures") :: IntValue?
	if cap then
		cap.Value += 1
	end
	monster.state = "festin"
	monster.pauseUntil = os.clock() + 3
	monster.target = nil
	monster.waypoints = {}
	task.delay(0.15, function()
		hum.Health = 0
	end)
	notify(nil, player.DisplayName .. " a été dévoré par le Wendigo…", Color3.fromRGB(255, 80, 80))
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
		if char and hrp and hum and hum.Health > 0 and round.participants[plr] and not round.out[plr] and not round.escaped[plr] and insideManor(hrp.Position) then
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
				if monster.skull then
					playSound("hurlement", monster.skull, 2.2, 170, 0.9 + math.random() * 0.2)
				end
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
		playAt("erreur", Vector3.new(72, 3, 33), 1, 60)
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
	if round and round.state == "jeu" and round.participants[player] and not round.out[player] then
		task.wait(0.15)
		if round.escaped[player] then
			char:PivotTo(CFrame.new(SAFE_ZONE))
		else
			char:PivotTo(CFrame.new(HALL_SPAWN + Vector3.new(math.random(-6, 6), 0, math.random(-4, 4))) * CFrame.Angles(0, math.rad(180), 0))
		end
	end
	hum.Died:Connect(function()
		lampOn[player] = false
		releaseHidden(player)
	end)
end

local function onPlayer(player: Player)
	local ls = Instance.new("Folder")
	ls.Name = "leaderstats"
	for _, n in { "Évasions", "Captures" } do
		local v = Instance.new("IntValue")
		v.Name = n
		v.Parent = ls
	end
	ls.Parent = player
	player:SetAttribute("InRound", false)
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
		round.participants[player] = nil
	end
end)

---------------------------------------------------------------------------
-- LE CAMP (LOBBY)
---------------------------------------------------------------------------

local Camp = Instance.new("Folder")
Camp.Name = "Camp"
local boardText: TextLabel
local survivorsText: TextLabel
local READY_CENTER = LOBBY + Vector3.new(0, 0, -30)
local READY_RADIUS = 9

local function campPart(props: { [string]: any }): BasePart
	props.Parent = Camp
	return part(props)
end

local function buildLobby()
	for _, child in workspace:GetChildren() do
		if child.Name == "Baseplate" or child:IsA("SpawnLocation") then
			child:Destroy()
		end
	end
	Camp.Parent = workspace
	local L = LOBBY
	campPart({ Name = "SolCamp", Size = Vector3.new(170, 2, 170), CFrame = CFrame.new(L.X, -1, L.Z), Color = Color3.fromRGB(34, 42, 30), Material = Enum.Material.Grass })
	campPart({ Name = "Terre", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.2, 46, 46), CFrame = CFrame.new(L.X, 0.05, L.Z - 8) * CFrame.Angles(0, 0, math.rad(90)), Color = Color3.fromRGB(70, 55, 40), Material = Enum.Material.Ground })

	-- Point d'apparition
	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "ApparitionCamp"
	spawn.Anchored = true
	spawn.Size = Vector3.new(10, 0.4, 10)
	spawn.CFrame = CFrame.new(L.X, 0.2, L.Z + 16)
	spawn.Color = Color3.fromRGB(60, 45, 35)
	spawn.Material = Enum.Material.WoodPlanks
	spawn.Transparency = 0
	spawn.Duration = 0
	spawn.Neutral = true
	spawn.Parent = Camp

	-- Feu de camp, rondins, tentes
	local fire = campPart({ Name = "FeuDeCamp", Size = Vector3.new(4, 0.8, 4), CFrame = CFrame.new(L.X, 0.4, L.Z), Color = Color3.fromRGB(50, 35, 25), Material = Enum.Material.Wood })
	local f = Instance.new("Fire")
	f.Size = 7
	f.Heat = 9
	f.Parent = fire
	local campLight = light(fire, Color3.fromRGB(255, 150, 70), 45, 2.2)
	campLight:SetAttribute("Bougie", true)
	for i = 0, 5 do
		local a = i / 6 * math.pi * 2
		campPart({ Name = "Pierre", Size = Vector3.new(1.4, 0.9, 1.2), CFrame = CFrame.new(L.X + math.cos(a) * 2.8, 0.45, L.Z + math.sin(a) * 2.8) * CFrame.Angles(0, a, 0), Color = Color3.fromRGB(80, 78, 75), Material = Enum.Material.Slate })
	end
	for i = 0, 3 do
		local a = i / 4 * math.pi * 2 + 0.4
		campPart({ Name = "Banc", Shape = Enum.PartType.Cylinder, Size = Vector3.new(7, 1.6, 1.6), CFrame = CFrame.new(L.X + math.cos(a) * 9, 0.8, L.Z + math.sin(a) * 9) * CFrame.Angles(0, -a + math.pi / 2, 0), Color = Color3.fromRGB(90, 62, 40), Material = Enum.Material.Wood })
	end
	for i, a in { 2.2, 3.1, 4.0 } do
		local p = Vector3.new(L.X + math.cos(a) * 24, 0, L.Z + math.sin(a) * 24)
		local cf = CFrame.lookAt(p, Vector3.new(L.X, 0, L.Z))
		local tent = Color3.fromHSV(0.05 + i * 0.25, 0.4, 0.35)
		for _, sx in { -1, 1 } do
			campPart({ ClassName = "WedgePart", Name = "Tente", Size = Vector3.new(7, 5, 3.5), CFrame = cf * CFrame.new(sx * 1.75, 2.5, 0) * CFrame.Angles(0, math.rad(sx * 90), 0), Color = tent, Material = Enum.Material.Fabric })
		end
	end

	-- Lanternes et tombes
	for i = 0, 7 do
		local a = i / 8 * math.pi * 2
		local p = Vector3.new(L.X + math.cos(a) * 40, 0, L.Z + math.sin(a) * 40)
		campPart({ Name = "Poteau", Size = Vector3.new(0.5, 7, 0.5), CFrame = CFrame.new(p + Vector3.new(0, 3.5, 0)), Color = Color3.fromRGB(45, 32, 22), Material = Enum.Material.Wood })
		local lamp = campPart({ Name = "Lanterne", Size = Vector3.new(1.1, 1.3, 1.1), CFrame = CFrame.new(p + Vector3.new(0, 7.4, 0)), Color = Color3.fromRGB(255, 190, 100), Material = Enum.Material.Neon })
		local l = light(lamp, Color3.fromRGB(255, 180, 100), 18, 0.9)
		l:SetAttribute("Bougie", true)
	end
	local rng = Random.new(9)
	for _ = 1, 14 do
		local a = rng:NextNumber(math.rad(20), math.rad(160))
		local d = rng:NextNumber(46, 56)
		local p = Vector3.new(L.X + math.cos(a) * d, 0, L.Z + math.sin(a) * d)
		local g = campPart({ Name = "Tombe", Size = Vector3.new(2.4, 3.2, 0.6), CFrame = CFrame.lookAt(p + Vector3.new(0, 1.4, 0), Vector3.new(L.X, 1.4, L.Z)) * CFrame.Angles(rng:NextNumber(-0.15, 0.15), 0, rng:NextNumber(-0.12, 0.12)), Color = Color3.fromRGB(105, 105, 110), Material = Enum.Material.Slate })
		_ = g
	end

	-- Forêt morte et murs invisibles tout autour
	for _ = 1, 70 do
		local a = rng:NextNumber(0, math.pi * 2)
		local d = rng:NextNumber(60, 82)
		local x, z = L.X + math.cos(a) * d, L.Z + math.sin(a) * d
		local h = rng:NextNumber(18, 32)
		campPart({ Name = "Arbre", Size = Vector3.new(1.8, h, 1.8), CFrame = CFrame.new(x, h / 2, z) * CFrame.Angles(rng:NextNumber(-0.1, 0.1), 0, rng:NextNumber(-0.1, 0.1)), Color = Color3.fromRGB(32, 26, 22), Material = Enum.Material.Wood })
		for k = 1, 3 do
			campPart({ Name = "Branche", Size = Vector3.new(0.6, rng:NextNumber(5, 10), 0.6), CFrame = CFrame.new(x, h * (0.5 + k * 0.13), z) * CFrame.Angles(rng:NextNumber(-1, 1), rng:NextNumber(0, 6), rng:NextNumber(0.6, 1.2)), Color = Color3.fromRGB(32, 26, 22), Material = Enum.Material.Wood })
		end
	end
	for i = 0, 23 do
		local a = i / 24 * math.pi * 2
		campPart({ Name = "LimiteCamp", Size = Vector3.new(2, 60, 2 * math.pi * 62 / 24 + 2), CFrame = CFrame.new(L.X + math.cos(a) * 62, 30, L.Z + math.sin(a) * 62) * CFrame.Angles(0, -a, 0), Transparency = 1, CanQuery = false })
	end

	-- Lucioles
	local flies = campPart({ Name = "Lucioles", Size = Vector3.new(100, 8, 100), CFrame = CFrame.new(L.X, 5, L.Z), Transparency = 1, CanCollide = false })
	local fe = Instance.new("ParticleEmitter")
	fe.Shape = Enum.ParticleEmitterShape.Box
	fe.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
	fe.Rate = 12
	fe.Lifetime = NumberRange.new(4, 7)
	fe.Speed = NumberRange.new(0.3, 1)
	fe.SpreadAngle = Vector2.new(180, 180)
	fe.Size = NumberSequence.new(0.18)
	fe.Color = ColorSequence.new(Color3.fromRGB(200, 255, 140))
	fe.LightEmission = 1
	fe.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.5, 0.1), NumberSequenceKeypoint.new(1, 1) })
	fe.Parent = flies

	-- Le cercle rituel : on y entre pour participer à la prochaine nuit
	local C = READY_CENTER
	campPart({ Name = "CercleRituel", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.12, READY_RADIUS * 2, READY_RADIUS * 2), CFrame = CFrame.new(C.X, 0.08, C.Z) * CFrame.Angles(0, 0, math.rad(90)), Color = Color3.fromRGB(150, 15, 20), Material = Enum.Material.Neon, Transparency = 0.55, CanCollide = false })
	campPart({ Name = "CercleInterieur", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.14, READY_RADIUS * 2 - 1.2, READY_RADIUS * 2 - 1.2), CFrame = CFrame.new(C.X, 0.1, C.Z) * CFrame.Angles(0, 0, math.rad(90)), Color = Color3.fromRGB(20, 12, 14), Material = Enum.Material.Slate, CanCollide = false })
	for i = 0, 9 do
		local a = i / 10 * math.pi * 2
		local stone = campPart({ Name = "Menhir", Size = Vector3.new(1.4, 4 + (i % 3), 1), CFrame = CFrame.new(C.X + math.cos(a) * (READY_RADIUS + 1.5), 2, C.Z + math.sin(a) * (READY_RADIUS + 1.5)) * CFrame.Angles(0, -a, 0), Color = Color3.fromRGB(70, 68, 66), Material = Enum.Material.Slate })
		if i % 2 == 0 then
			local rune = campPart({ Name = "Rune", Size = Vector3.new(0.2, 1, 0.6), CFrame = stone.CFrame * CFrame.new(-0.72, 0.8, 0), Color = Color3.fromRGB(255, 40, 30), Material = Enum.Material.Neon, CanCollide = false })
			local rl = light(rune, Color3.fromRGB(255, 40, 30), 10, 0.8)
			rl.Shadows = false
		end
	end
	local mist = campPart({ Name = "Brume", Size = Vector3.new(READY_RADIUS * 2, 1, READY_RADIUS * 2), CFrame = CFrame.new(C.X, 0.6, C.Z), Transparency = 1, CanCollide = false })
	local me = Instance.new("ParticleEmitter")
	me.Shape = Enum.ParticleEmitterShape.Box
	me.Rate = 14
	me.Lifetime = NumberRange.new(3, 5)
	me.Speed = NumberRange.new(0.5, 1.5)
	me.EmissionDirection = Enum.NormalId.Top
	me.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.5), NumberSequenceKeypoint.new(1, 4) })
	me.Color = ColorSequence.new(Color3.fromRGB(120, 20, 25))
	me.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.4, 0.75), NumberSequenceKeypoint.new(1, 1) })
	me.LightEmission = 0.4
	me.Parent = mist

	-- Totem au crâne de cerf (un avant-goût du Wendigo)
	local T = C + Vector3.new(0, 0, -15)
	campPart({ Name = "Totem", Size = Vector3.new(0.9, 10, 0.9), CFrame = CFrame.new(T + Vector3.new(0, 5, 0)), Color = Color3.fromRGB(40, 30, 22), Material = Enum.Material.Wood })
	local skullCF = CFrame.new(T + Vector3.new(0, 10.6, 0)) * CFrame.Angles(math.rad(-10), 0, 0)
	campPart({ Name = "CraneTotem", Size = Vector3.new(1.25, 1.05, 1.35), CFrame = skullCF, Color = BONE, Material = Enum.Material.Limestone })
	campPart({ Name = "MuseauTotem", Size = Vector3.new(0.72, 0.58, 1.9), CFrame = skullCF * CFrame.new(0, -0.3, -1.2) * CFrame.Angles(math.rad(8), 0, 0), Color = BONE, Material = Enum.Material.Limestone })
	for _, sx in { -1, 1 } do
		local eye = campPart({ Name = "OeilTotem", Shape = Enum.PartType.Ball, Size = Vector3.one * 0.3, CFrame = skullCF * CFrame.new(sx * 0.42, 0.1, -0.62), Color = Color3.fromRGB(255, 20, 10), Material = Enum.Material.Neon, CanCollide = false })
		_ = eye
		buildAntler(function(cf, props)
			props.CFrame = skullCF * cf
			props.CanCollide = false
			campPart(props)
		end, CFrame.new(sx * 0.42, 0.45, 0.2), sx)
	end
	local tl = light(campPart({ Name = "LueurTotem", Size = Vector3.one * 0.2, CFrame = skullCF * CFrame.new(0, 0, -1.2), Transparency = 1, CanCollide = false }), Color3.fromRGB(255, 30, 20), 14, 1)
	tl.Shadows = false

	-- Panneaux : état de la partie et survivants
	local function board(pos: Vector3, title: string): TextLabel
		local cf = CFrame.lookAt(pos, Vector3.new(L.X, pos.Y, L.Z + 10))
		for _, sx in { -1, 1 } do
			campPart({ Name = "Pied", Size = Vector3.new(0.6, 9, 0.6), CFrame = cf * CFrame.new(sx * 6.4, -2.5, 0.2), Color = Color3.fromRGB(45, 32, 22), Material = Enum.Material.Wood })
		end
		local b = campPart({ Name = "Panneau", Size = Vector3.new(13, 7, 0.4), CFrame = cf, Color = Color3.fromRGB(60, 42, 28), Material = Enum.Material.WoodPlanks })
		local sg = Instance.new("SurfaceGui")
		sg.Face = Enum.NormalId.Front
		sg.CanvasSize = Vector2.new(650, 350)
		sg.LightInfluence = 0.4
		local head = Instance.new("TextLabel")
		head.Size = UDim2.new(1, 0, 0, 80)
		head.BackgroundTransparency = 1
		head.Text = title
		head.Font = Enum.Font.Creepster
		head.TextScaled = true
		head.TextColor3 = Color3.fromRGB(200, 30, 30)
		head.Parent = sg
		local body = Instance.new("TextLabel")
		body.Size = UDim2.new(1, -40, 1, -100)
		body.Position = UDim2.fromOffset(20, 90)
		body.BackgroundTransparency = 1
		body.Text = ""
		body.Font = Enum.Font.SpecialElite
		body.TextScaled = true
		body.TextColor3 = Color3.fromRGB(235, 225, 210)
		body.Parent = sg
		sg.Parent = b
		local lamp = campPart({ Name = "LampePanneau", Size = Vector3.one * 0.6, CFrame = cf * CFrame.new(0, 4.2, -1.4), Color = Color3.fromRGB(255, 200, 120), Material = Enum.Material.Neon })
		light(lamp, Color3.fromRGB(255, 190, 120), 12, 0.9)
		return body
	end
	boardText = board(LOBBY + Vector3.new(-17, 6, -36), "LE MANOIR DES OMBRES")
	survivorsText = board(LOBBY + Vector3.new(17, 6, -36), "SURVIVANTS")
end

local function inLobby(plr: Player): boolean
	return plr:GetAttribute("InRound") ~= true
end

local function refreshSurvivors()
	local list = {}
	for _, plr in Players:GetPlayers() do
		local ls = plr:FindFirstChild("leaderstats")
		local ev = ls and ls:FindFirstChild("Évasions") :: IntValue?
		table.insert(list, { name = plr.DisplayName, n = if ev then ev.Value else 0 })
	end
	table.sort(list, function(a, b)
		return a.n > b.n
	end)
	local lines = {}
	for i = 1, math.min(6, #list) do
		table.insert(lines, string.format("%d. %s — %d évasion%s", i, list[i].name, list[i].n, if list[i].n > 1 then "s" else ""))
	end
	survivorsText.Text = if #lines > 0 then table.concat(lines, "\n") else "Personne n'a encore survécu…"
end

---------------------------------------------------------------------------
-- MANCHES
---------------------------------------------------------------------------

local function startRound(players: { Player })
	round = {
		state = "jeu", timeLeft = ROUND_TIME, fuses = 0, power = false, safeOpen = false,
		hasKey = false, doorOpen = false, code = "0000", clockText = "", escaped = {}, participants = {}, out = {},
		catches = 0, roomLights = {}, officeDoor = nil, frontDoor = nil, safeDoor = nil,
		monsterAwake = false, started = os.clock(),
	}
	monster.model = nil
	monster.state = "dort"
	monster.waypoints = {}
	buildManor()
	refreshInventory()
	setObjective("Trouve les 3 fusibles cachés dans le manoir (0/3).")
	for _, plr in players do
		round.participants[plr] = true
		plr:SetAttribute("InRound", true)
		plr:SetAttribute("Escaped", false)
		battery[plr] = 100
		plr:SetAttribute("Battery", 100)
		releaseHidden(plr)
		task.spawn(function()
			plr:LoadCharacter()
		end)
	end
	notify(nil, "La nuit tombe sur le manoir… Les portes se referment derrière vous.", Color3.fromRGB(220, 200, 255))
end

local function endRound(reason: string)
	round.state = "fin"
	for plr in round.participants do
		if plr.Parent and not round.escaped[plr] and not round.out[plr] then
			EndRemote:FireClient(plr, false, reason)
		end
	end
	if monster.model then
		monster.model:Destroy()
		monster.model = nil
	end
	local n = 0
	for plr in round.escaped do
		if plr.Parent then
			n += 1
		end
	end
	notify(nil, if n > 0 then string.format("Fin de la nuit : %d survivant%s.", n, if n > 1 then "s" else "") else "Fin de la nuit : le manoir a gardé tout le monde…", Color3.fromRGB(220, 200, 255))
	refreshSurvivors()
	-- Retour au camp
	task.delay(6, function()
		for plr in round.participants do
			if plr.Parent and plr:GetAttribute("InRound") then
				plr:SetAttribute("InRound", false)
			end
			if plr.Parent and (round.escaped[plr] or not round.out[plr]) then
				releaseHidden(plr)
				task.spawn(function()
					plr:LoadCharacter()
				end)
			end
		end
	end)
end

-- Boucle principale : camp -> nuit -> camp
buildLobby()
round = {
	state = "camp", timeLeft = 0, fuses = 0, power = false, safeOpen = false, hasKey = false, doorOpen = false,
	code = "0000", clockText = "", escaped = {}, participants = {}, out = {}, catches = 0, roomLights = {},
	officeDoor = nil, frontDoor = nil, safeDoor = nil, monsterAwake = false, started = 0,
}
task.spawn(function()
	while true do
		-- Au camp : on attend que des joueurs entrent dans le cercle rituel
		local countdown = LOBBY_COUNTDOWN
		refreshSurvivors()
		while true do
			task.wait(1)
			local ready, inCamp = {}, 0
			for _, plr in Players:GetPlayers() do
				if inLobby(plr) then
					inCamp += 1
					local hrp = plr.Character and plr.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
					local hum = plr.Character and plr.Character:FindFirstChildOfClass("Humanoid")
					if hrp and hum and hum.Health > 0 then
						local d = Vector3.new(hrp.Position.X - READY_CENTER.X, 0, hrp.Position.Z - READY_CENTER.Z).Magnitude
						if d < READY_RADIUS then
							table.insert(ready, plr)
						end
					end
				end
			end
			if #ready == 0 then
				countdown = LOBBY_COUNTDOWN
				boardText.Text = "Entrez dans le cercle rouge pour affronter la prochaine nuit.\n\nTrouvez les fusibles, le code du coffre et la clé…\nEt ne laissez pas le Wendigo vous voir."
			else
				countdown -= 1
				if #ready == inCamp then
					countdown = math.min(countdown, 5)
				end
				boardText.Text = string.format("%d joueur%s dans le cercle (sur %d)\n\nLa nuit commence dans %d s…", #ready, if #ready > 1 then "s" else "", inCamp, math.max(0, countdown))
			end
			RoundRemote:FireAllClients("camp", math.max(0, countdown), #ready, inCamp)
			if #ready > 0 and countdown <= 0 then
				startRound(ready)
				break
			end
		end

		-- La nuit
		local last = os.clock()
		while round.state == "jeu" do
			task.wait(1)
			local now = os.clock()
			round.timeLeft -= now - last
			last = now
			local active = 0
			for plr in round.participants do
				if plr.Parent and not round.escaped[plr] and not round.out[plr] then
					active += 1
				end
			end
			RoundRemote:FireAllClients("jeu", math.max(0, math.floor(round.timeLeft)), active)
			boardText.Text = string.format("Une nuit est en cours…\n\n%d:%02d avant l'aube\n%d joueur%s encore dans le manoir", math.max(0, math.floor(round.timeLeft)) // 60, math.max(0, math.floor(round.timeLeft)) % 60, active, if active > 1 then "s" else "")
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
			if round.timeLeft <= 0 then
				endRound("L'aube ne viendra jamais pour vous… Le temps est écoulé.")
			elseif active == 0 then
				endRound("La nuit est terminée.")
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
