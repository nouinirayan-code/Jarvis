--[[
	L'ÎLE DES RELIQUES — script serveur
	À placer dans ServerScriptService (type : Script).

	Ce script construit toute l'île au lancement (terrain, village, zones, ennemis,
	temple) et gère la logique : quêtes, combat, boutique, sauvegarde.
	Le script client (IleDesReliquesClient) affiche l'interface.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Lighting = game:GetService("Lighting")
local DataStoreService = game:GetService("DataStoreService")
local Debris = game:GetService("Debris")

local Terrain = workspace.Terrain

---------------------------------------------------------------------------
-- RÉGLAGES
---------------------------------------------------------------------------

local SWORD_DAMAGE = { 20, 32, 48 }
local SWORD_COLORS = {
	Color3.fromRGB(190, 190, 200),
	Color3.fromRGB(120, 170, 255),
	Color3.fromRGB(170, 90, 255),
}
local SWORD_NAMES = { "Épée de bois de fer", "Épée d'acier", "Lame de cristal" }
local SWORD_RANGE = 10
local SWORD_COOLDOWN = 0.45

local SHOP_ITEMS = {
	{ id = "epee2", name = "Épée d'acier", price = 120, desc = "Dégâts : 32 (au lieu de 20)" },
	{ id = "epee3", name = "Lame de cristal", price = 350, desc = "Dégâts : 48. Nécessite l'Épée d'acier" },
	{ id = "bottes", name = "Bottes du vent", price = 200, desc = "Vitesse de course +40 %" },
	{ id = "coeur", name = "Cœur de héros", price = 250, desc = "150 points de vie au lieu de 100" },
	{ id = "potion", name = "Potion de soin", price = 25, desc = "Soigne complètement (achat illimité)" },
}

local RELICS = {
	foret = { name = "Relique de la Forêt", color = Color3.fromRGB(80, 230, 120) },
	canyon = { name = "Relique du Cristal", color = Color3.fromRGB(90, 200, 255) },
	volcan = { name = "Relique de la Braise", color = Color3.fromRGB(255, 120, 40) },
}
local RELIC_ORDER = { "foret", "canyon", "volcan" }

-- Centres des zones (studs)
local VILLAGE = Vector3.new(0, 0, 0)
local FOREST = Vector3.new(0, 0, -250)
local CANYON = Vector3.new(260, 0, 100)
local VOLCANO = Vector3.new(-270, 0, 100)
local TEMPLE = Vector3.new(0, 0, 270)
local ARENA = Vector3.new(0, 0, 345)

local ZONES = {
	{ name = "Village de Brisevent", center = VILLAGE, radius = 70 },
	{ name = "Forêt Murmurante", center = FOREST, radius = 130 },
	{ name = "Canyon de Cristal", center = CANYON + Vector3.new(40, 0, 0), radius = 120 },
	{ name = "Mont Braise", center = VOLCANO, radius = 130 },
	{ name = "Temple Oublié", center = TEMPLE, radius = 60 },
	{ name = "Antre du Gardien", center = ARENA, radius = 48 },
}

local ENEMY_TYPES = {
	slime = { name = "Slime", hp = 60, dmg = 8, speed = 11, range = 4.5, cooldown = 1.1, aggro = 45, coins = 3, respawn = 20, height = 2 },
	squelette = { name = "Squelette", hp = 110, dmg = 13, speed = 13, range = 5, cooldown = 1.2, aggro = 55, coins = 6, respawn = 25, height = 3.2 },
	diablotin = { name = "Diablotin de feu", hp = 90, dmg = 16, speed = 16, range = 5, cooldown = 1.0, aggro = 60, coins = 8, respawn = 25, height = 3 },
}

---------------------------------------------------------------------------
-- OUTILS DE CONSTRUCTION
---------------------------------------------------------------------------

local World = Instance.new("Folder")
World.Name = "IleDesReliques"
World.Parent = workspace

local EnemyFolder = Instance.new("Folder")
EnemyFolder.Name = "Ennemis"
EnemyFolder.Parent = workspace

local PickupFolder = Instance.new("Folder")
PickupFolder.Name = "Pieces"
PickupFolder.Parent = workspace

local function part(props: { [string]: any }): BasePart
	local className = props.ClassName or "Part"
	local p = Instance.new(className) :: BasePart
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	for k, v in props do
		if k ~= "ClassName" and k ~= "Parent" then
			(p :: any)[k] = v
		end
	end
	-- Les objets traversables (effets, pièces, feuillage…) sont ignorés par les rayons de sol
	if props.CanCollide == false and props.CanQuery == nil then
		p.CanQuery = false
	end
	p.Parent = props.Parent or World
	return p
end

local function light(parent: Instance, color: Color3, range: number, brightness: number)
	local l = Instance.new("PointLight")
	l.Color = color
	l.Range = range
	l.Brightness = brightness
	l.Parent = parent
	return l
end

local function sparkles(parent: Instance, color: Color3, rate: number)
	local e = Instance.new("ParticleEmitter")
	e.Color = ColorSequence.new(color)
	e.LightEmission = 1
	e.Rate = rate
	e.Lifetime = NumberRange.new(1, 2)
	e.Speed = NumberRange.new(1, 3)
	e.SpreadAngle = Vector2.new(180, 180)
	e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.4), NumberSequenceKeypoint.new(1, 0) })
	e.Parent = parent
	return e
end

local function billboard(parent: BasePart, text: string, color: Color3, offset: number, size: number?)
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromOffset(220, 40)
	gui.StudsOffset = Vector3.new(0, offset, 0)
	gui.AlwaysOnTop = false
	gui.MaxDistance = 90
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Text = text
	label.TextColor3 = color
	label.TextStrokeTransparency = 0.3
	label.Font = Enum.Font.GothamBold
	label.TextSize = size or 20
	label.Parent = gui
	gui.Parent = parent
	return gui
end

-- Hauteur du sol sous un point (terrain ou pièces du décor)
local groundParams = RaycastParams.new()
groundParams.FilterType = Enum.RaycastFilterType.Exclude

local function refreshGroundFilter()
	local list: { Instance } = { EnemyFolder, PickupFolder }
	for _, plr in Players:GetPlayers() do
		if plr.Character then
			table.insert(list, plr.Character)
		end
	end
	groundParams.FilterDescendantsInstances = list
end

local function groundAt(x: number, z: number, fromY: number?): (number?, Instance?)
	local origin = Vector3.new(x, (fromY or 150), z)
	local hit = workspace:Raycast(origin, Vector3.new(0, -400, 0), groundParams)
	if hit then
		return hit.Position.Y, hit.Instance
	end
	return nil, nil
end

---------------------------------------------------------------------------
-- ÉCHANGES CLIENT / SERVEUR
---------------------------------------------------------------------------

local Remotes = Instance.new("Folder")
Remotes.Name = "IleRemotes"
Remotes.Parent = ReplicatedStorage

local function remote(name: string): RemoteEvent
	local r = Instance.new("RemoteEvent")
	r.Name = name
	r.Parent = Remotes
	return r
end

local NotifyRemote = remote("Notify") -- (texte, couleur?)
local DialogRemote = remote("Dialog") -- (nom, lignes)
local QuestRemote = remote("Quest") -- (titre, texte)
local ShopRemote = remote("Shop") -- serveur -> client : ouvrir ; client -> serveur : acheter
local BossRemote = remote("Boss") -- (visible, pv, pvMax)
local VictoryRemote = remote("Victory")
local HitRemote = remote("Hit") -- (position, dégâts) pour les nombres flottants

local function notify(player: Player, text: string, color: Color3?)
	NotifyRemote:FireClient(player, text, color)
end

---------------------------------------------------------------------------
-- AMBIANCE
---------------------------------------------------------------------------

Lighting.ClockTime = 15.5
Lighting.Brightness = 2.2
Lighting.OutdoorAmbient = Color3.fromRGB(135, 130, 150)
Lighting.EnvironmentDiffuseScale = 0.6
local atmosphere = Instance.new("Atmosphere")
atmosphere.Density = 0.32
atmosphere.Haze = 1.4
atmosphere.Color = Color3.fromRGB(200, 215, 235)
atmosphere.Decay = Color3.fromRGB(120, 110, 150)
atmosphere.Parent = Lighting
local bloom = Instance.new("BloomEffect")
bloom.Intensity = 0.6
bloom.Threshold = 1.2
bloom.Parent = Lighting

---------------------------------------------------------------------------
-- TERRAIN
---------------------------------------------------------------------------

local function buildTerrain()
	-- Retire la plaque et le point d'apparition du modèle « Baseplate » de Studio
	for _, child in workspace:GetChildren() do
		if child.Name == "Baseplate" or (child:IsA("SpawnLocation") and child.Parent == workspace) then
			child:Destroy()
		end
	end
	Terrain:Clear()
	-- Océan, plage et île
	Terrain:FillBlock(CFrame.new(0, -16, 0), Vector3.new(1400, 16, 1400), Enum.Material.Water)
	Terrain:FillCylinder(CFrame.new(0, -12, 0), 16, 480, Enum.Material.Sand)
	Terrain:FillCylinder(CFrame.new(0, -8, 0), 16, 440, Enum.Material.Grass)

	-- Collines douces (hors des chemins)
	local rng = Random.new(42)
	for _ = 1, 26 do
		local a = rng:NextNumber(0, math.pi * 2)
		local d = rng:NextNumber(120, 400)
		local p = Vector3.new(math.cos(a) * d, 0, math.sin(a) * d)
		local tooClose = false
		for _, c in { VILLAGE, FOREST, CANYON, VOLCANO, TEMPLE, ARENA } do
			if (Vector3.new(p.X, 0, p.Z) - c).Magnitude < 110 then
				tooClose = true
			end
		end
		if not tooClose then
			Terrain:FillBall(p + Vector3.new(0, -26, 0), rng:NextNumber(30, 45), Enum.Material.Grass)
		end
	end

	-- Chemins de terre battue depuis le village
	local function path(from: Vector3, to: Vector3)
		local mid = (from + to) / 2
		local len = (to - from).Magnitude
		Terrain:FillBlock(CFrame.lookAt(mid + Vector3.new(0, -1.5, 0), to + Vector3.new(0, -1.5, 0)), Vector3.new(10, 4, len), Enum.Material.Ground)
	end
	path(VILLAGE, FOREST + Vector3.new(0, 0, 90))
	path(VILLAGE, CANYON - Vector3.new(60, 0, 0))
	path(VILLAGE, VOLCANO + Vector3.new(120, 0, 0))
	path(VILLAGE, TEMPLE - Vector3.new(0, 0, 40))
	Terrain:FillCylinder(CFrame.new(0, -1.5, 0), 4, 40, Enum.Material.Cobblestone)

	-- Forêt : sol moussu
	Terrain:FillCylinder(CFrame.new(FOREST.X, -1.5, FOREST.Z), 4, 125, Enum.Material.LeafyGrass)

	-- Canyon : gouffre et mesa
	Terrain:FillCylinder(CFrame.new(CANYON.X + 30, -1.5, CANYON.Z), 4, 120, Enum.Material.Sandstone)
	Terrain:FillBlock(CFrame.new(CANYON.X + 27, -30, CANYON.Z), Vector3.new(46, 60, 110), Enum.Material.Air)
	Terrain:FillBlock(CFrame.new(CANYON.X + 80, 14, CANYON.Z), Vector3.new(60, 32, 70), Enum.Material.Sandstone)
	Terrain:FillBlock(CFrame.new(CANYON.X + 80, 1, CANYON.Z), Vector3.new(66, 6, 76), Enum.Material.Rock)
	-- Falaises autour du canyon
	for _, off in { -60, 60 } do
		Terrain:FillBlock(CFrame.new(CANYON.X + 55, 10, CANYON.Z + off), Vector3.new(130, 30, 14), Enum.Material.Rock)
	end

	-- Volcan
	Terrain:FillCylinder(CFrame.new(VOLCANO.X, -1.5, VOLCANO.Z), 4, 125, Enum.Material.Basalt)
	Terrain:FillBall(Vector3.new(VOLCANO.X, -45, VOLCANO.Z), 90, Enum.Material.Basalt)
	Terrain:FillBall(Vector3.new(VOLCANO.X, 58, VOLCANO.Z), 22, Enum.Material.Air)
	Terrain:FillBall(Vector3.new(VOLCANO.X, 20, VOLCANO.Z), 40, Enum.Material.Basalt)
	Terrain:FillBall(Vector3.new(VOLCANO.X, 58, VOLCANO.Z), 20, Enum.Material.Air)

	-- Temple et arène
	Terrain:FillCylinder(CFrame.new(TEMPLE.X, -1.5, TEMPLE.Z + 40), 4, 100, Enum.Material.Slate)
end

---------------------------------------------------------------------------
-- DÉCOR
---------------------------------------------------------------------------

local function makeTree(pos: Vector3, scale: number)
	local trunkH = 12 * scale
	part({
		Name = "Tronc", Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(trunkH, 2.2 * scale, 2.2 * scale),
		CFrame = CFrame.new(pos + Vector3.new(0, trunkH / 2, 0)) * CFrame.Angles(0, 0, math.rad(90)),
		Color = Color3.fromRGB(105, 72, 45), Material = Enum.Material.Wood,
	})
	local green = Color3.fromHSV(0.28 + math.random() * 0.06, 0.6, 0.45 + math.random() * 0.15)
	for i = 1, 3 do
		local off = Vector3.new(math.random(-2, 2) * scale, trunkH + (i - 1) * 2.5 * scale, math.random(-2, 2) * scale)
		part({
			Name = "Feuillage", Shape = Enum.PartType.Ball,
			Size = Vector3.one * (9 - i * 1.5) * scale,
			CFrame = CFrame.new(pos + off), Color = green, Material = Enum.Material.Grass,
		})
	end
end

local function makeRock(pos: Vector3, size: number, color: Color3?)
	part({
		Name = "Rocher", Size = Vector3.new(size, size * 0.7, size * 0.9),
		CFrame = CFrame.new(pos + Vector3.new(0, size * 0.25, 0)) * CFrame.Angles(math.random() * 0.4, math.random() * 3, math.random() * 0.4),
		Color = color or Color3.fromRGB(120, 115, 110), Material = Enum.Material.Slate,
	})
end

local function makeHouse(pos: Vector3, facing: number, roofColor: Color3)
	local cf = CFrame.new(pos) * CFrame.Angles(0, facing, 0)
	local w, d, h = 16, 14, 10
	local wall = Color3.fromRGB(225, 210, 180)
	part({ Name = "Mur", Size = Vector3.new(w, h, 1), CFrame = cf * CFrame.new(0, h / 2, -d / 2), Color = wall, Material = Enum.Material.Plaster })
	part({ Name = "Mur", Size = Vector3.new(1, h, d), CFrame = cf * CFrame.new(-w / 2, h / 2, 0), Color = wall, Material = Enum.Material.Plaster })
	part({ Name = "Mur", Size = Vector3.new(1, h, d), CFrame = cf * CFrame.new(w / 2, h / 2, 0), Color = wall, Material = Enum.Material.Plaster })
	-- Façade avec porte
	part({ Name = "Mur", Size = Vector3.new(6, h, 1), CFrame = cf * CFrame.new(-5, h / 2, d / 2), Color = wall, Material = Enum.Material.Plaster })
	part({ Name = "Mur", Size = Vector3.new(6, h, 1), CFrame = cf * CFrame.new(5, h / 2, d / 2), Color = wall, Material = Enum.Material.Plaster })
	part({ Name = "Linteau", Size = Vector3.new(4, 3, 1), CFrame = cf * CFrame.new(0, h - 1.5, d / 2), Color = wall, Material = Enum.Material.Plaster })
	part({ Name = "Porte", Size = Vector3.new(4, 7, 0.4), CFrame = cf * CFrame.new(0, 3.5, d / 2 + 0.3), Color = Color3.fromRGB(110, 70, 40), Material = Enum.Material.WoodPlanks, CanCollide = false })
	-- Poutres
	for _, x in { -w / 2, w / 2 } do
		part({ Name = "Poutre", Size = Vector3.new(1.2, h, 1.2), CFrame = cf * CFrame.new(x, h / 2, d / 2), Color = Color3.fromRGB(90, 60, 35), Material = Enum.Material.Wood })
	end
	-- Toit (deux pans)
	for _, s in { -1, 1 } do
		part({
			ClassName = "WedgePart", Name = "Toit",
			Size = Vector3.new(d + 2, 6, w / 2 + 1),
			CFrame = cf * CFrame.new(s * (w / 4 + 0.5), h + 3, 0) * CFrame.Angles(0, s * math.rad(90), 0),
			Color = roofColor, Material = Enum.Material.Slate,
		})
	end
	-- Fenêtre éclairée
	local win = part({ Name = "Fenetre", Size = Vector3.new(3, 3, 0.3), CFrame = cf * CFrame.new(-5, 6, d / 2 + 0.6), Color = Color3.fromRGB(255, 210, 120), Material = Enum.Material.Neon })
	light(win, Color3.fromRGB(255, 200, 120), 12, 1)
end

local function makeSign(pos: Vector3, facing: number, text: string)
	part({ Name = "Poteau", Size = Vector3.new(0.8, 7, 0.8), CFrame = CFrame.new(pos + Vector3.new(0, 3.5, 0)), Color = Color3.fromRGB(100, 70, 40), Material = Enum.Material.Wood })
	local board = part({
		Name = "Panneau", Size = Vector3.new(9, 2, 0.4),
		CFrame = CFrame.new(pos + Vector3.new(0, 6, 0)) * CFrame.Angles(0, facing, 0),
		Color = Color3.fromRGB(150, 110, 65), Material = Enum.Material.WoodPlanks,
	})
	local sg = Instance.new("SurfaceGui")
	sg.Face = Enum.NormalId.Front
	sg.CanvasSize = Vector2.new(360, 80)
	local t = Instance.new("TextLabel")
	t.Size = UDim2.fromScale(1, 1)
	t.BackgroundTransparency = 1
	t.Text = text
	t.TextScaled = true
	t.Font = Enum.Font.Fantasy
	t.TextColor3 = Color3.fromRGB(255, 240, 210)
	t.Parent = sg
	sg.Parent = board
	local back = sg:Clone()
	back.Face = Enum.NormalId.Back
	back.Parent = board
end

-- Personnage non joueur (décor + dialogue)
local function makeNPC(pos: Vector3, facing: number, name: string, robe: Color3, hat: Color3): BasePart
	local cf = CFrame.new(pos) * CFrame.Angles(0, facing, 0)
	local skin = Color3.fromRGB(235, 195, 160)
	local body = part({ Name = name, Size = Vector3.new(2.6, 3.4, 1.6), CFrame = cf * CFrame.new(0, 3.7, 0), Color = robe, Material = Enum.Material.Fabric })
	part({ Name = "Robe", Size = Vector3.new(3, 2, 2), CFrame = cf * CFrame.new(0, 1, 0), Color = robe, Material = Enum.Material.Fabric })
	part({ Name = "Tete", Shape = Enum.PartType.Ball, Size = Vector3.new(2.2, 2.2, 2.2), CFrame = cf * CFrame.new(0, 6.5, 0), Color = skin })
	part({ Name = "Chapeau", ClassName = "WedgePart", Size = Vector3.new(2.6, 2.5, 2.6), CFrame = cf * CFrame.new(0, 8.4, 0), Color = hat, Material = Enum.Material.Fabric })
	for _, s in { -1, 1 } do
		part({ Name = "Oeil", Shape = Enum.PartType.Ball, Size = Vector3.new(0.35, 0.35, 0.35), CFrame = cf * CFrame.new(s * 0.45, 6.7, -1), Color = Color3.new(0, 0, 0) })
		part({ Name = "Bras", Size = Vector3.new(0.9, 3, 0.9), CFrame = cf * CFrame.new(s * 1.8, 3.9, 0), Color = robe, Material = Enum.Material.Fabric })
	end
	billboard(body, name, Color3.fromRGB(255, 230, 150), 5.5, 22)
	return body
end

local function addPrompt(p: BasePart, action: string, object: string): ProximityPrompt
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = action
	prompt.ObjectText = object
	prompt.MaxActivationDistance = 12
	prompt.RequiresLineOfSight = false
	prompt.Parent = p
	return prompt
end

---------------------------------------------------------------------------
-- JOUEURS : DONNÉES, SAUVEGARDE
---------------------------------------------------------------------------

local store: DataStore? = nil
pcall(function()
	store = DataStoreService:GetDataStore("IleDesReliques_v1")
end)

type PlayerData = {
	coins: number,
	relics: { [string]: boolean },
	stage: number, -- 0 : parler au sage, 1 : reliques, 2 : temple, 3 : héros
	sword: number,
	bottes: boolean,
	coeur: boolean,
	victories: number,
	checkpoint: { number }?,
}

local DATA: { [Player]: PlayerData } = {}
local saveWarned = false

local function defaultData(): PlayerData
	return { coins = 0, relics = {}, stage = 0, sword = 1, bottes = false, coeur = false, victories = 0, checkpoint = nil }
end

local function relicCount(d: PlayerData): number
	local n = 0
	for _, id in RELIC_ORDER do
		if d.relics[id] then
			n += 1
		end
	end
	return n
end

local function updateStats(player: Player)
	local d = DATA[player]
	if not d then
		return
	end
	local ls = player:FindFirstChild("leaderstats")
	if ls then
		(ls:FindFirstChild("Pièces") :: IntValue).Value = d.coins;
		(ls:FindFirstChild("Reliques") :: IntValue).Value = relicCount(d)
	end
	player:SetAttribute("Coins", d.coins)
	player:SetAttribute("Sword", d.sword)
	for _, id in RELIC_ORDER do
		player:SetAttribute("Relic_" .. id, d.relics[id] == true)
	end
end

local function updateQuest(player: Player)
	local d = DATA[player]
	if not d then
		return
	end
	local n = relicCount(d)
	if d.stage == 1 and n >= 3 then
		d.stage = 2
	end
	local title, text
	if d.stage == 0 then
		title, text = "Un appel à l'aventure", "Parle au Vieux Sage près du puits du village."
	elseif d.stage == 1 then
		local missing = {}
		if not d.relics.foret then
			table.insert(missing, "Forêt Murmurante (nord)")
		end
		if not d.relics.canyon then
			table.insert(missing, "Canyon de Cristal (est)")
		end
		if not d.relics.volcan then
			table.insert(missing, "Mont Braise (ouest)")
		end
		title = string.format("Les trois reliques (%d/3)", n)
		text = "Trouve les reliques : " .. table.concat(missing, ", ") .. "."
	elseif d.stage == 2 then
		title, text = "Le Temple Oublié", "Tu as les 3 reliques ! Ouvre la porte du temple au sud et affronte le Gardien."
	else
		title, text = "Héros de l'île", string.format("Le Gardien a été vaincu %d fois. Affronte-le encore pour gagner des pièces !", d.victories)
	end
	QuestRemote:FireClient(player, title, text)
	updateStats(player)
end

local function addCoins(player: Player, amount: number)
	local d = DATA[player]
	if not d then
		return
	end
	d.coins += amount
	updateStats(player)
end

local function save(player: Player)
	local d = DATA[player]
	if not d or not store then
		return
	end
	local ok, err = pcall(function()
		(store :: DataStore):SetAsync("joueur_" .. player.UserId, d)
	end)
	if not ok and not saveWarned then
		saveWarned = true
		warn("Sauvegarde indisponible (dans Studio, activez « Enable Studio Access to API Services ») : " .. tostring(err))
	end
end

local function loadData(player: Player): PlayerData
	local d = defaultData()
	if store then
		local ok, saved = pcall(function()
			return (store :: DataStore):GetAsync("joueur_" .. player.UserId)
		end)
		if ok and type(saved) == "table" then
			for k, v in saved do
				(d :: any)[k] = v
			end
			d.relics = d.relics or {}
		end
	end
	return d
end

---------------------------------------------------------------------------
-- ÉPÉE ET PERSONNAGE
---------------------------------------------------------------------------

local enemies: { any } = {}
local damageEnemy: (enemy: any, amount: number, player: Player?) -> ()
local boss: any = nil
local damageBoss: (amount: number, player: Player) -> ()

local function makeSword(level: number): Tool
	local tool = Instance.new("Tool")
	tool.Name = SWORD_NAMES[level]
	tool.RequiresHandle = true
	tool.CanBeDropped = false
	tool.ToolTip = "Clic pour frapper"
	-- Prise « épée classique » : la lame (axe +Z de la poignée) pointe vers le haut
	tool.GripForward = Vector3.new(-1, 0, 0)
	tool.GripRight = Vector3.new(0, 1, 0)
	tool.GripUp = Vector3.new(0, 0, 1)
	tool.GripPos = Vector3.new(0, 0, -0.3)

	local handle = Instance.new("Part")
	handle.Name = "Handle"
	handle.Size = Vector3.new(0.5, 0.5, 1.6)
	handle.Color = Color3.fromRGB(90, 55, 30)
	handle.Material = Enum.Material.Wood
	handle.CanCollide = false
	handle.Massless = true
	handle.Parent = tool

	local guard = Instance.new("Part")
	guard.Name = "Garde"
	guard.Size = Vector3.new(1.8, 0.5, 0.3)
	guard.Color = Color3.fromRGB(220, 180, 60)
	guard.Material = Enum.Material.Metal
	guard.CanCollide = false
	guard.Massless = true
	guard.CFrame = handle.CFrame * CFrame.new(0, 0, 0.95)
	guard.Parent = tool

	local blade = Instance.new("Part")
	blade.Name = "Lame"
	blade.Size = Vector3.new(0.4, 0.14, 4.2)
	blade.Color = SWORD_COLORS[level]
	blade.Material = if level == 3 then Enum.Material.Neon else Enum.Material.Metal
	blade.CanCollide = false
	blade.Massless = true
	blade.CFrame = handle.CFrame * CFrame.new(0, 0, 3.2)
	blade.Parent = tool
	if level == 3 then
		light(blade, SWORD_COLORS[3], 8, 1)
	end

	for _, p in { guard, blade } do
		local w = Instance.new("WeldConstraint")
		w.Part0 = handle
		w.Part1 = p
		w.Parent = p
	end
	return tool
end

local lastSwing: { [Player]: number } = {}

local function onSwing(player: Player, tool: Tool)
	local now = os.clock()
	if (lastSwing[player] or 0) + SWORD_COOLDOWN > now then
		return
	end
	lastSwing[player] = now
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		return
	end
	-- Petit mouvement de l'épée
	local rest = tool.Grip
	tool.Grip = rest * CFrame.Angles(0, math.rad(-75), 0)
	task.delay(0.18, function()
		if tool.Parent then
			tool.Grip = rest
		end
	end)

	local d = DATA[player]
	local dmg = SWORD_DAMAGE[d and d.sword or 1]
	local look = root.CFrame.LookVector
	for _, e in enemies do
		if e.alive then
			local offset = e.root.Position - root.Position
			local flat = Vector3.new(offset.X, 0, offset.Z)
			if flat.Magnitude < SWORD_RANGE + e.radius and (flat.Magnitude < 3 or flat.Unit:Dot(look) > 0.2) and math.abs(offset.Y) < 10 then
				damageEnemy(e, dmg, player)
			end
		end
	end
	if boss and boss.alive then
		local offset = boss.root.Position - root.Position
		local flat = Vector3.new(offset.X, 0, offset.Z)
		if flat.Magnitude < SWORD_RANGE + boss.radius and (flat.Magnitude < 1 or flat.Unit:Dot(look) > 0) then
			damageBoss(dmg, player)
		end
	end
end

local function giveSword(player: Player)
	local d = DATA[player]
	if not d then
		return
	end
	local backpack = player:FindFirstChildOfClass("Backpack")
	local char = player.Character
	for _, container in { backpack, char } do
		if container then
			for _, t in container:GetChildren() do
				if t:IsA("Tool") and t:GetAttribute("Epee") then
					t:Destroy()
				end
			end
		end
	end
	local tool = makeSword(d.sword)
	tool:SetAttribute("Epee", true)
	tool.Activated:Connect(function()
		onSwing(player, tool)
	end)
	tool.Parent = backpack
end

local function applyCharacterStats(player: Player)
	local d = DATA[player]
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if not d or not hum then
		return
	end
	hum.WalkSpeed = if d.bottes then 22 else 16
	hum.MaxHealth = if d.coeur then 150 else 100
	hum.Health = hum.MaxHealth
end

---------------------------------------------------------------------------
-- PIÈCES À RAMASSER
---------------------------------------------------------------------------

local coins: { { part: BasePart, base: Vector3, value: number, respawn: boolean } } = {}

local function spawnCoin(pos: Vector3, value: number, respawn: boolean, fling: boolean?)
	local c = part({
		Name = "Piece", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.4, 2.4, 2.4),
		CFrame = CFrame.new(pos), Color = Color3.fromRGB(255, 205, 50), Material = Enum.Material.Neon,
		CanCollide = false, Parent = PickupFolder,
	})
	local entry = { part = c, base = pos, value = value, respawn = respawn }
	table.insert(coins, entry)
	if fling then
		-- petite dispersion visuelle
		entry.base = pos + Vector3.new(math.random(-4, 4), 0, math.random(-4, 4))
	end
	local taken = false
	c.Touched:Connect(function(hit)
		if taken then
			return
		end
		local player = Players:GetPlayerFromCharacter(hit.Parent)
		if not player then
			return
		end
		taken = true
		addCoins(player, value)
		c.Transparency = 1
		if respawn then
			task.delay(35, function()
				taken = false
				c.Transparency = 0
			end)
		else
			local i = table.find(coins, entry)
			if i then
				table.remove(coins, i)
			end
			c:Destroy()
		end
	end)
	if not respawn then
		Debris:AddItem(c, 60)
		task.delay(60, function()
			local i = table.find(coins, entry)
			if i then
				table.remove(coins, i)
			end
		end)
	end
end

---------------------------------------------------------------------------
-- ENNEMIS
---------------------------------------------------------------------------

local function flashModel(model: Model)
	for _, p in model:GetDescendants() do
		if p:IsA("BasePart") and p:GetAttribute("BaseColor") == nil then
			p:SetAttribute("BaseColor", p.Color)
		end
	end
	for _, p in model:GetDescendants() do
		if p:IsA("BasePart") then
			p.Color = Color3.new(1, 1, 1)
		end
	end
	task.delay(0.1, function()
		for _, p in model:GetDescendants() do
			if p:IsA("BasePart") then
				local c = p:GetAttribute("BaseColor")
				if typeof(c) == "Color3" then
					p.Color = c
				end
			end
		end
	end)
end

local function healthBar(root: BasePart, name: string, width: number): Frame
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromOffset(width, 34)
	gui.StudsOffset = Vector3.new(0, 4, 0)
	gui.MaxDistance = 70
	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(1, 0, 0, 16)
	label.BackgroundTransparency = 1
	label.Text = name
	label.Font = Enum.Font.GothamBold
	label.TextSize = 14
	label.TextColor3 = Color3.fromRGB(255, 220, 220)
	label.TextStrokeTransparency = 0.3
	label.Parent = gui
	local back = Instance.new("Frame")
	back.Size = UDim2.new(1, 0, 0, 8)
	back.Position = UDim2.fromOffset(0, 20)
	back.BackgroundColor3 = Color3.fromRGB(30, 10, 10)
	back.BorderSizePixel = 0
	back.Parent = gui
	local fill = Instance.new("Frame")
	fill.Size = UDim2.fromScale(1, 1)
	fill.BackgroundColor3 = Color3.fromRGB(230, 60, 60)
	fill.BorderSizePixel = 0
	fill.Parent = back
	gui.Parent = root
	return fill
end

local function buildEnemyModel(kind: string): (Model, BasePart)
	local model = Instance.new("Model")
	model.Name = ENEMY_TYPES[kind].name
	local root: BasePart
	local function add(props)
		props.CanCollide = false
		props.Parent = model
		return part(props)
	end
	if kind == "slime" then
		local hue = 0.3 + math.random() * 0.1
		root = add({ Name = "Corps", Shape = Enum.PartType.Ball, Size = Vector3.new(4.2, 4.2, 4.2), CFrame = CFrame.new(), Color = Color3.fromHSV(hue, 0.7, 0.8), Material = Enum.Material.SmoothPlastic, Transparency = 0.15 })
		for _, s in { -1, 1 } do
			add({ Name = "Oeil", Shape = Enum.PartType.Ball, Size = Vector3.new(0.9, 0.9, 0.9), CFrame = CFrame.new(s * 0.8, 0.6, -1.7), Color = Color3.new(1, 1, 1) })
			add({ Name = "Pupille", Shape = Enum.PartType.Ball, Size = Vector3.new(0.45, 0.45, 0.45), CFrame = CFrame.new(s * 0.8, 0.6, -2.1), Color = Color3.new(0, 0, 0) })
		end
	elseif kind == "squelette" then
		local bone = Color3.fromRGB(230, 225, 205)
		root = add({ Name = "Torse", Size = Vector3.new(2, 2.4, 1), CFrame = CFrame.new(0, 0.6, 0), Color = bone })
		add({ Name = "Crane", Size = Vector3.new(1.6, 1.6, 1.6), CFrame = CFrame.new(0, 2.6, 0), Color = bone })
		for _, s in { -1, 1 } do
			add({ Name = "Orbite", Size = Vector3.new(0.4, 0.4, 0.2), CFrame = CFrame.new(s * 0.4, 2.7, -0.8), Color = Color3.fromRGB(255, 60, 40), Material = Enum.Material.Neon })
			add({ Name = "Jambe", Size = Vector3.new(0.5, 2.2, 0.5), CFrame = CFrame.new(s * 0.5, -1.7, 0), Color = bone })
			add({ Name = "Bras", Size = Vector3.new(0.45, 2.2, 0.45), CFrame = CFrame.new(s * 1.3, 0.5, 0), Color = bone })
		end
		add({ Name = "Epee", Size = Vector3.new(0.2, 3.4, 0.5), CFrame = CFrame.new(1.3, 0.2, -1.4) * CFrame.Angles(math.rad(-60), 0, 0), Color = Color3.fromRGB(120, 110, 100), Material = Enum.Material.Metal })
	else
		root = add({ Name = "Corps", Shape = Enum.PartType.Ball, Size = Vector3.new(3.4, 3.4, 3.4), CFrame = CFrame.new(), Color = Color3.fromRGB(200, 50, 20), Material = Enum.Material.Neon })
		for _, s in { -1, 1 } do
			add({ Name = "Corne", ClassName = "WedgePart", Size = Vector3.new(0.4, 1.4, 0.8), CFrame = CFrame.new(s * 1, 2, 0), Color = Color3.fromRGB(40, 20, 20) })
			add({ Name = "Oeil", Shape = Enum.PartType.Ball, Size = Vector3.new(0.6, 0.6, 0.6), CFrame = CFrame.new(s * 0.6, 0.4, -1.5), Color = Color3.fromRGB(255, 240, 80), Material = Enum.Material.Neon })
		end
		local fire = Instance.new("Fire")
		fire.Size = 4
		fire.Heat = 6
		fire.Parent = root
		light(root, Color3.fromRGB(255, 120, 40), 14, 2)
	end
	model.PrimaryPart = root
	return model, root
end

local function spawnEnemy(kind: string, home: Vector3)
	local def = ENEMY_TYPES[kind]
	local model, root = buildEnemyModel(kind)
	local y = groundAt(home.X, home.Z) or home.Y
	model:PivotTo(CFrame.new(home.X, y + def.height, home.Z))
	local e = {
		kind = kind, def = def, model = model, root = root, home = home,
		hp = def.hp, alive = true, lastAttack = 0, radius = 2.5, t = math.random() * 5,
		pos = Vector3.new(home.X, y + def.height, home.Z), facing = Vector3.new(0, 0, -1),
		wander = home, wanderAt = 0,
	}
	e.bar = healthBar(root, def.name, 90)
	model.Parent = EnemyFolder
	table.insert(enemies, e)
	return e
end

damageEnemy = function(e, amount: number, player: Player?)
	if not e.alive then
		return
	end
	e.hp -= amount
	e.bar.Size = UDim2.fromScale(math.max(0, e.hp / e.def.hp), 1)
	flashModel(e.model)
	HitRemote:FireAllClients(e.root.Position + Vector3.new(0, 3, 0), amount)
	-- Recul
	if player and player.Character then
		local hrp = player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if hrp then
			local dir = Vector3.new(e.pos.X - hrp.Position.X, 0, e.pos.Z - hrp.Position.Z)
			if dir.Magnitude > 0.1 then
				e.pos += dir.Unit * 3
			end
		end
	end
	if e.hp <= 0 then
		e.alive = false
		local where = e.root.Position
		local burst = sparkles(e.root, Color3.fromRGB(255, 220, 120), 0)
		burst:Emit(30)
		for _ = 1, e.def.coins do
			spawnCoin(where + Vector3.new(0, 1, 0), 1, false, true)
		end
		for _, p in e.model:GetDescendants() do
			if p:IsA("BasePart") then
				TweenService:Create(p, TweenInfo.new(0.4), { Transparency = 1, Size = p.Size * 0.3 }):Play()
			end
		end
		task.delay(0.5, function()
			e.model:Destroy()
		end)
		local i = table.find(enemies, e)
		if i then
			table.remove(enemies, i)
		end
		if not e.noRespawn then
			task.delay(e.def.respawn, function()
				spawnEnemy(e.kind, e.home)
			end)
		end
	end
end

local function nearestPlayer(pos: Vector3, maxDist: number): (Player?, BasePart?, Humanoid?)
	local best, bestRoot, bestHum, bestD = nil, nil, nil, maxDist
	for _, plr in Players:GetPlayers() do
		local char = plr.Character
		local hrp = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		if hrp and hum and hum.Health > 0 then
			local d = (hrp.Position - pos).Magnitude
			if d < bestD then
				best, bestRoot, bestHum, bestD = plr, hrp, hum, d
			end
		end
	end
	return best, bestRoot, bestHum
end

local function isDanger(inst: Instance?): boolean
	return inst ~= nil and (inst.Name == "Lave" or inst.Name == "Vide")
end

local function updateEnemy(e, dt: number, now: number)
	e.t += dt
	local def = e.def
	local _, targetRoot, targetHum = nearestPlayer(e.pos, def.aggro)
	local goal: Vector3? = nil
	local leash = (Vector3.new(e.pos.X, 0, e.pos.Z) - Vector3.new(e.home.X, 0, e.home.Z)).Magnitude
	if targetRoot and targetHum and leash < 90 then
		local tp = targetRoot.Position
		goal = tp
		local flat = Vector3.new(tp.X - e.pos.X, 0, tp.Z - e.pos.Z)
		if flat.Magnitude < def.range + 1 and math.abs(tp.Y - e.pos.Y) < 8 then
			goal = nil
			e.facing = if flat.Magnitude > 0.1 then flat.Unit else e.facing
			if now - e.lastAttack > def.cooldown then
				e.lastAttack = now
				targetHum:TakeDamage(def.dmg)
			end
		end
	else
		-- Errance autour du point d'apparition
		if now > e.wanderAt then
			e.wanderAt = now + math.random(3, 7)
			e.wander = e.home + Vector3.new(math.random(-18, 18), 0, math.random(-18, 18))
		end
		goal = e.wander
	end

	if goal then
		local flat = Vector3.new(goal.X - e.pos.X, 0, goal.Z - e.pos.Z)
		if flat.Magnitude > 1 then
			local speed = if targetRoot then def.speed else def.speed * 0.35
			local step = flat.Unit * math.min(flat.Magnitude, speed * dt)
			local nx, nz = e.pos.X + step.X, e.pos.Z + step.Z
			local gy, inst = groundAt(nx, nz, e.pos.Y + 12)
			-- Ne pas tomber dans la lave ou le vide, ni escalader les murs
			local dy = if gy then gy - (e.pos.Y - def.height) else 0
			if gy and not isDanger(inst) and dy < 3.5 and dy > -6 then
				e.pos = Vector3.new(nx, gy + def.height, nz)
			end
			e.facing = flat.Unit
		end
	end

	local bob = 0
	if e.kind == "slime" then
		bob = math.abs(math.sin(e.t * 6)) * 1.2
	elseif e.kind == "diablotin" then
		bob = math.sin(e.t * 4) * 0.6 + 0.8
	end
	e.model:PivotTo(CFrame.lookAt(e.pos + Vector3.new(0, bob, 0), e.pos + Vector3.new(0, bob, 0) + e.facing))
end

---------------------------------------------------------------------------
-- GARDIEN DE PIERRE (BOSS)
---------------------------------------------------------------------------

local bossCooldownUntil = 0

local function playersInArena(): { Player }
	local list = {}
	for _, plr in Players:GetPlayers() do
		local char = plr.Character
		local hrp = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		if hrp and hum and hum.Health > 0 and (Vector3.new(hrp.Position.X, 0, hrp.Position.Z) - ARENA).Magnitude < 50 then
			table.insert(list, plr)
		end
	end
	return list
end

local function spawnBoss()
	local count = math.max(1, #playersInArena())
	local model = Instance.new("Model")
	model.Name = "Gardien de Pierre"
	local stone = Color3.fromRGB(110, 105, 100)
	local function add(props)
		props.CanCollide = false
		props.Parent = model
		return part(props)
	end
	local root = add({ Name = "Torse", Size = Vector3.new(10, 9, 6), CFrame = CFrame.new(0, 0, 0), Color = stone, Material = Enum.Material.Slate })
	add({ Name = "Tete", Size = Vector3.new(5, 4, 4.5), CFrame = CFrame.new(0, 6.6, -0.5), Color = stone, Material = Enum.Material.Slate })
	add({ Name = "Rune", Size = Vector3.new(3, 3, 0.3), CFrame = CFrame.new(0, 0.5, -3.1), Color = Color3.fromRGB(80, 220, 255), Material = Enum.Material.Neon })
	for _, s in { -1, 1 } do
		add({ Name = "Oeil", Size = Vector3.new(1, 0.6, 0.3), CFrame = CFrame.new(s * 1.1, 7, -2.8), Color = Color3.fromRGB(80, 220, 255), Material = Enum.Material.Neon })
		add({ Name = "Bras", Size = Vector3.new(3.5, 10, 3.5), CFrame = CFrame.new(s * 7.2, -1, 0), Color = stone, Material = Enum.Material.Slate })
		add({ Name = "Poing", Size = Vector3.new(4.5, 4, 4.5), CFrame = CFrame.new(s * 7.2, -7, 0), Color = Color3.fromRGB(90, 85, 80), Material = Enum.Material.Slate })
		add({ Name = "Jambe", Size = Vector3.new(3.5, 6, 3.5), CFrame = CFrame.new(s * 2.6, -7, 0), Color = stone, Material = Enum.Material.Slate })
	end
	light(root, Color3.fromRGB(80, 220, 255), 20, 2)
	model.PrimaryPart = root
	local maxHp = 1400 + (count - 1) * 900
	boss = {
		model = model, root = root, hp = maxHp, maxHp = maxHp, alive = true, radius = 7,
		pos = ARENA + Vector3.new(0, 10, 12), facing = Vector3.new(0, 0, -1),
		nextSlam = os.clock() + 3, telegraphs = {}, attackers = {}, enraged = false, nextMinions = 0,
	}
	model:PivotTo(CFrame.new(boss.pos))
	model.Parent = EnemyFolder
	for _, plr in playersInArena() do
		notify(plr, "Le Gardien de Pierre s'éveille !", Color3.fromRGB(120, 220, 255))
	end
end

local function slam(center: Vector3, radius: number, dmg: number)
	local ring = part({
		Name = "Alerte", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.3, radius * 2, radius * 2),
		CFrame = CFrame.new(center.X, ARENA.Y + 0.3, center.Z) * CFrame.Angles(0, 0, math.rad(90)),
		Color = Color3.fromRGB(255, 50, 50), Material = Enum.Material.Neon, Transparency = 0.5, CanCollide = false,
	})
	TweenService:Create(ring, TweenInfo.new(1.1), { Transparency = 0.1 }):Play()
	task.delay(1.2, function()
		ring:Destroy()
		if not boss or not boss.alive then
			return
		end
		local shock = part({
			Name = "Onde", Shape = Enum.PartType.Ball, Size = Vector3.new(4, 4, 4),
			CFrame = CFrame.new(center.X, ARENA.Y + 1, center.Z), Color = Color3.fromRGB(200, 190, 170),
			Material = Enum.Material.Slate, Transparency = 0.3, CanCollide = false,
		})
		TweenService:Create(shock, TweenInfo.new(0.35), { Size = Vector3.one * radius * 2, Transparency = 1 }):Play()
		Debris:AddItem(shock, 0.4)
		for _, plr in Players:GetPlayers() do
			local char = plr.Character
			local hrp = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
			local hum = char and char:FindFirstChildOfClass("Humanoid")
			if hrp and hum then
				local flat = Vector3.new(hrp.Position.X - center.X, 0, hrp.Position.Z - center.Z)
				if flat.Magnitude < radius and hrp.Position.Y < ARENA.Y + 8 then
					hum:TakeDamage(dmg)
				end
			end
		end
	end)
end

damageBoss = function(amount: number, player: Player)
	if not boss or not boss.alive then
		return
	end
	boss.hp -= amount
	boss.attackers[player] = true
	flashModel(boss.model)
	HitRemote:FireAllClients(boss.root.Position + Vector3.new(0, 8, 0), amount)
	if boss.hp <= boss.maxHp / 2 and not boss.enraged then
		boss.enraged = true
		for _, plr in playersInArena() do
			notify(plr, "Le Gardien entre en rage !", Color3.fromRGB(255, 90, 90))
		end
	end
	if boss.hp <= 0 then
		boss.alive = false
		local winners = playersInArena()
		for plr in boss.attackers do
			if not table.find(winners, plr) and plr.Parent then
				table.insert(winners, plr)
			end
		end
		for _, plr in winners do
			local d = DATA[plr]
			if d then
				local first = d.stage < 3
				d.stage = 3
				d.victories += 1
				addCoins(plr, if first then 500 else 150)
				VictoryRemote:FireClient(plr, first, if first then 500 else 150)
				updateQuest(plr)
				BossRemote:FireClient(plr, false)
			end
		end
		local burst = sparkles(boss.root, Color3.fromRGB(120, 220, 255), 0)
		burst:Emit(120)
		for _, p in boss.model:GetDescendants() do
			if p:IsA("BasePart") then
				p.Anchored = false
				p.CanCollide = true
				p.AssemblyLinearVelocity = Vector3.new(math.random(-30, 30), math.random(20, 50), math.random(-30, 30))
			end
		end
		Debris:AddItem(boss.model, 6)
		boss = nil
		bossCooldownUntil = os.clock() + 20
	end
end

local function updateBoss(dt: number, now: number)
	local inArena = playersInArena()
	if not boss then
		if #inArena > 0 and now > bossCooldownUntil then
			spawnBoss()
		end
		return
	end
	if #inArena == 0 then
		-- Tout le monde est parti ou tombé : le Gardien se rendort et récupère
		boss.model:Destroy()
		boss = nil
		return
	end
	if now > (boss.nextBar or 0) then
		boss.nextBar = now + 0.2
		for _, plr in inArena do
			BossRemote:FireClient(plr, true, boss.hp, boss.maxHp)
		end
	end
	local _, targetRoot = nearestPlayer(boss.pos, 120)
	if targetRoot then
		local flat = Vector3.new(targetRoot.Position.X - boss.pos.X, 0, targetRoot.Position.Z - boss.pos.Z)
		if flat.Magnitude > 9 then
			local speed = if boss.enraged then 11 else 7
			boss.pos += flat.Unit * math.min(flat.Magnitude - 9, speed * dt)
		end
		if flat.Magnitude > 0.1 then
			boss.facing = flat.Unit
		end
		if now > boss.nextSlam then
			boss.nextSlam = now + (if boss.enraged then 2.4 else 3.6)
			slam(targetRoot.Position, if boss.enraged then 14 else 11, 30)
			if boss.enraged then
				-- Deuxième onde décalée
				local side = Vector3.new(math.random(-12, 12), 0, math.random(-12, 12))
				slam(targetRoot.Position + side, 10, 25)
			end
		end
		if boss.enraged and now > boss.nextMinions then
			boss.nextMinions = now + 14
			for _ = 1, 2 do
				local a = math.random() * math.pi * 2
				local minion = spawnEnemy("slime", ARENA + Vector3.new(math.cos(a) * 25, 0, math.sin(a) * 25))
				minion.noRespawn = true
			end
		end
	end
	local stomp = math.abs(math.sin(now * 3)) * 0.8
	boss.model:PivotTo(CFrame.lookAt(boss.pos + Vector3.new(0, stomp, 0), boss.pos + Vector3.new(0, stomp, 0) + boss.facing))
end

---------------------------------------------------------------------------
-- CONSTRUCTION DU MONDE
---------------------------------------------------------------------------

local checkpoints: { BasePart } = {}

local function makeCheckpoint(pos: Vector3, name: string)
	local y = groundAt(pos.X, pos.Z) or pos.Y
	local base = part({ Name = "PointDeControle", Size = Vector3.new(6, 1, 6), CFrame = CFrame.new(pos.X, y + 0.5, pos.Z), Color = Color3.fromRGB(90, 90, 100), Material = Enum.Material.Cobblestone })
	part({ Name = "Mat", Size = Vector3.new(0.5, 9, 0.5), CFrame = CFrame.new(pos.X, y + 5, pos.Z), Color = Color3.fromRGB(200, 200, 210), Material = Enum.Material.Metal })
	local flag = part({ Name = "Drapeau", Size = Vector3.new(3.4, 2, 0.2), CFrame = CFrame.new(pos.X + 1.9, y + 8.2, pos.Z), Color = Color3.fromRGB(80, 160, 255), Material = Enum.Material.Fabric })
	billboard(base, "Point de contrôle — " .. name, Color3.fromRGB(180, 220, 255), 10, 16)
	table.insert(checkpoints, base)
	base.Touched:Connect(function(hit)
		local player = Players:GetPlayerFromCharacter(hit.Parent)
		local d = player and DATA[player]
		if not player or not d then
			return
		end
		local cp = { pos.X, y + 4, pos.Z }
		local cur = d.checkpoint
		if cur and cur[1] == cp[1] and cur[3] == cp[3] then
			return
		end
		d.checkpoint = cp
		notify(player, "Point de contrôle : " .. name, Color3.fromRGB(120, 200, 255))
		flag.Color = Color3.fromRGB(80, 230, 120)
	end)
end

local function makeKillPart(props: { [string]: any })
	local p = part(props)
	p.Touched:Connect(function(hit)
		local hum = hit.Parent and hit.Parent:FindFirstChildOfClass("Humanoid")
		if hum and Players:GetPlayerFromCharacter(hit.Parent) then
			hum.Health = 0
		end
	end)
	return p
end

local function makeRelic(id: string, pos: Vector3)
	local info = RELICS[id]
	local pedestal = part({ Name = "Piedestal", Size = Vector3.new(5, 3, 5), CFrame = CFrame.new(pos + Vector3.new(0, 1.5, 0)), Color = Color3.fromRGB(200, 195, 185), Material = Enum.Material.Marble })
	local gem = part({
		Name = "Relique", Size = Vector3.new(2, 2, 2), CFrame = CFrame.new(pos + Vector3.new(0, 5, 0)),
		Color = info.color, Material = Enum.Material.Neon, CanCollide = false,
	})
	light(gem, info.color, 18, 3)
	sparkles(gem, info.color, 8)
	billboard(gem, info.name, info.color, 3, 18)
	local prompt = addPrompt(pedestal, "Prendre", info.name)
	prompt.HoldDuration = 0.6
	-- Rotation lente
	task.spawn(function()
		local t = 0
		while gem.Parent do
			t += task.wait()
			gem.CFrame = CFrame.new(pos + Vector3.new(0, 5 + math.sin(t * 2) * 0.5, 0)) * CFrame.Angles(t, t * 1.3, 0)
		end
	end)
	prompt.Triggered:Connect(function(player)
		local d = DATA[player]
		if not d then
			return
		end
		if d.relics[id] then
			notify(player, "Tu possèdes déjà cette relique.")
			return
		end
		if d.stage == 0 then
			d.stage = 1
		end
		d.relics[id] = true
		addCoins(player, 50)
		notify(player, info.name .. " obtenue ! (+50 pièces)", info.color)
		updateQuest(player)
		if relicCount(d) >= 3 then
			notify(player, "Les trois reliques brillent… Le Temple Oublié t'attend au sud !", Color3.fromRGB(255, 230, 120))
		end
		save(player)
	end)
end

local function buildVillage()
	local spawn = Instance.new("SpawnLocation")
	spawn.Anchored = true
	spawn.Size = Vector3.new(10, 1, 10)
	spawn.CFrame = CFrame.new(0, 0.6, 12)
	spawn.Color = Color3.fromRGB(200, 190, 170)
	spawn.Material = Enum.Material.Cobblestone
	spawn.Duration = 3
	spawn.Neutral = true
	spawn.Parent = World

	-- Puits
	part({ Name = "Puits", Shape = Enum.PartType.Cylinder, Size = Vector3.new(3, 7, 7), CFrame = CFrame.new(0, 1.5, -6) * CFrame.Angles(0, 0, math.rad(90)), Color = Color3.fromRGB(140, 135, 130), Material = Enum.Material.Cobblestone })
	part({ Name = "Eau", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.2, 5.6, 5.6), CFrame = CFrame.new(0, 2.9, -6) * CFrame.Angles(0, 0, math.rad(90)), Color = Color3.fromRGB(60, 120, 200), Material = Enum.Material.Glass, Transparency = 0.2 })
	for _, s in { -1, 1 } do
		part({ Name = "Montant", Size = Vector3.new(0.6, 6, 0.6), CFrame = CFrame.new(s * 3, 5, -6), Color = Color3.fromRGB(100, 70, 40), Material = Enum.Material.Wood })
	end
	part({ Name = "ToitPuits", ClassName = "WedgePart", Size = Vector3.new(7, 2, 4), CFrame = CFrame.new(0, 9, -6), Color = Color3.fromRGB(150, 60, 50), Material = Enum.Material.Slate })

	-- Maisons
	local roofs = { Color3.fromRGB(170, 60, 50), Color3.fromRGB(60, 90, 160), Color3.fromRGB(70, 130, 70), Color3.fromRGB(150, 110, 60) }
	local spots = { { -34, -22, math.rad(45) }, { 34, -22, math.rad(-45) }, { -38, 26, math.rad(135) }, { 38, 28, math.rad(-135) } }
	for i, s in spots do
		makeHouse(Vector3.new(s[1], 0, s[2]), s[3], roofs[i])
	end

	-- Lanternes
	for i = 0, 7 do
		local a = i / 8 * math.pi * 2
		local p = Vector3.new(math.cos(a) * 24, 0, math.sin(a) * 24)
		part({ Name = "Lanterne", Size = Vector3.new(0.6, 8, 0.6), CFrame = CFrame.new(p + Vector3.new(0, 4, 0)), Color = Color3.fromRGB(50, 50, 55), Material = Enum.Material.Metal })
		local bulb = part({ Name = "Flamme", Size = Vector3.new(1.4, 1.4, 1.4), CFrame = CFrame.new(p + Vector3.new(0, 8.4, 0)), Color = Color3.fromRGB(255, 200, 110), Material = Enum.Material.Neon })
		light(bulb, Color3.fromRGB(255, 190, 110), 16, 1.2)
	end

	-- Le Vieux Sage
	local sage = makeNPC(Vector3.new(-7, 0, -10), math.rad(200), "Le Vieux Sage", Color3.fromRGB(90, 60, 140), Color3.fromRGB(60, 40, 110))
	local sagePrompt = addPrompt(sage, "Parler", "Le Vieux Sage")
	sagePrompt.Triggered:Connect(function(player)
		local d = DATA[player]
		if not d then
			return
		end
		local lines
		if d.stage == 0 then
			lines = {
				"Ah, un voyageur ! Bienvenue à Brisevent.",
				"Jadis, trois reliques protégeaient notre île. Le Gardien de Pierre les a dispersées.",
				"L'une repose au sommet de l'Arbre Ancien, dans la Forêt Murmurante, au nord.",
				"Une autre au-delà du gouffre du Canyon de Cristal, à l'est.",
				"La dernière au bord du cratère du Mont Braise, à l'ouest. Gare à la lave !",
				"Réunis-les, et la porte du Temple Oublié s'ouvrira au sud. Prends cette épée, et bonne chance !",
			}
			d.stage = 1
		elseif d.stage == 1 then
			lines = {
				string.format("Tu as trouvé %d relique%s sur 3. Continue, héros !", relicCount(d), if relicCount(d) > 1 then "s" else ""),
				"Les monstres laissent des pièces : le marchand du village t'équipera mieux.",
			}
		elseif d.stage == 2 then
			lines = {
				"Les trois reliques ! Je sens leur pouvoir d'ici…",
				"Va au Temple Oublié, au sud. Le Gardien frappe le sol : quand le cercle rouge apparaît, écarte-toi !",
			}
		else
			lines = {
				"L'île te doit tout, héros. Les enfants chantent déjà ton nom.",
				"Le Gardien se relève parfois… Tu peux l'affronter encore pour gagner des pièces.",
			}
		end
		DialogRemote:FireClient(player, "Le Vieux Sage", lines)
		updateQuest(player)
	end)

	-- Le marchand
	part({ Name = "Etal", Size = Vector3.new(10, 3, 4), CFrame = CFrame.new(16, 1.5, -10), Color = Color3.fromRGB(130, 90, 55), Material = Enum.Material.WoodPlanks })
	part({ Name = "Auvent", ClassName = "WedgePart", Size = Vector3.new(11, 2, 6), CFrame = CFrame.new(16, 8, -9) * CFrame.Angles(0, math.rad(180), 0), Color = Color3.fromRGB(200, 70, 60), Material = Enum.Material.Fabric })
	for _, s in { -1, 1 } do
		part({ Name = "Pilier", Size = Vector3.new(0.6, 7, 0.6), CFrame = CFrame.new(16 + s * 5, 3.5, -11.5), Color = Color3.fromRGB(100, 70, 40), Material = Enum.Material.Wood })
	end
	local merchant = makeNPC(Vector3.new(16, 0, -14), math.rad(0), "Barnabé le Marchand", Color3.fromRGB(180, 120, 40), Color3.fromRGB(120, 60, 20))
	local shopPrompt = addPrompt(merchant, "Commercer", "Barnabé le Marchand")
	shopPrompt.MaxActivationDistance = 14
	shopPrompt.Triggered:Connect(function(player)
		local d = DATA[player]
		if not d then
			return
		end
		ShopRemote:FireClient(player, SHOP_ITEMS, { sword = d.sword, bottes = d.bottes, coeur = d.coeur })
	end)

	-- Panneaux
	makeSign(Vector3.new(0, 0, -30), 0, "↑ Forêt Murmurante")
	makeSign(Vector3.new(30, 0, 8), math.rad(-70), "→ Canyon de Cristal")
	makeSign(Vector3.new(-30, 0, 8), math.rad(70), "← Mont Braise")
	makeSign(Vector3.new(0, 0, 40), math.rad(180), "↓ Temple Oublié")
end

local function buildForest()
	local rng = Random.new(7)
	for _ = 1, 90 do
		local a = rng:NextNumber(0, math.pi * 2)
		local d = rng:NextNumber(20, 120)
		local p = FOREST + Vector3.new(math.cos(a) * d, 0, math.sin(a) * d)
		local farFromAncient = (Vector3.new(p.X, 0, p.Z) - (FOREST + Vector3.new(0, 0, -45))).Magnitude > 28
		if (math.abs(p.X) > 9 or p.Z < FOREST.Z - 40) and farFromAncient then -- garder le chemin dégagé
			local y = groundAt(p.X, p.Z) or 0
			makeTree(Vector3.new(p.X, y, p.Z), rng:NextNumber(0.9, 1.6))
		end
	end
	-- Champignons lumineux
	for _ = 1, 25 do
		local p = FOREST + Vector3.new(rng:NextNumber(-100, 100), 0, rng:NextNumber(-100, 100))
		local y = groundAt(p.X, p.Z) or 0
		local cap = part({ Name = "Champignon", Shape = Enum.PartType.Ball, Size = Vector3.new(1.8, 1.2, 1.8), CFrame = CFrame.new(p.X, y + 1.2, p.Z), Color = Color3.fromRGB(120, 220, 255), Material = Enum.Material.Neon, CanCollide = false })
		light(cap, Color3.fromRGB(120, 220, 255), 8, 0.8)
	end

	-- L'Arbre Ancien et son escalier en spirale
	local base = FOREST + Vector3.new(0, 0, -45)
	local trunkH = 90
	part({
		Name = "ArbreAncien", Shape = Enum.PartType.Cylinder, Size = Vector3.new(trunkH, 16, 16),
		CFrame = CFrame.new(base + Vector3.new(0, trunkH / 2, 0)) * CFrame.Angles(0, 0, math.rad(90)),
		Color = Color3.fromRGB(95, 65, 40), Material = Enum.Material.Wood,
	})
	for i = 1, 6 do
		local a = i * 1.1
		part({
			Name = "Racine", Size = Vector3.new(3, 3, 14),
			CFrame = CFrame.new(base + Vector3.new(math.cos(a) * 9, 1, math.sin(a) * 9)) * CFrame.Angles(0, -a + math.pi / 2, math.rad(-15)),
			Color = Color3.fromRGB(85, 58, 36), Material = Enum.Material.Wood,
		})
	end
	local steps = 34
	for i = 0, steps - 1 do
		local a = i * 0.55
		local h = 4 + i * 2.45
		local r = 16
		part({
			Name = "Marche", Size = Vector3.new(6, 1, 4.5),
			CFrame = CFrame.new(base + Vector3.new(math.cos(a) * r, h, math.sin(a) * r)) * CFrame.Angles(0, -a, 0),
			Color = Color3.fromRGB(150, 110, 70), Material = Enum.Material.WoodPlanks,
		})
		if i % 6 == 3 then
			local lamp = part({ Name = "Luciole", Shape = Enum.PartType.Ball, Size = Vector3.new(0.8, 0.8, 0.8), CFrame = CFrame.new(base + Vector3.new(math.cos(a) * (r + 3), h + 3, math.sin(a) * (r + 3))), Color = Color3.fromRGB(200, 255, 120), Material = Enum.Material.Neon, CanCollide = false })
			light(lamp, Color3.fromRGB(200, 255, 120), 10, 1)
		end
	end
	local top = base + Vector3.new(0, trunkH, 0)
	part({ Name = "Plateforme", Shape = Enum.PartType.Cylinder, Size = Vector3.new(1.5, 26, 26), CFrame = CFrame.new(top) * CFrame.Angles(0, 0, math.rad(90)), Color = Color3.fromRGB(130, 95, 60), Material = Enum.Material.WoodPlanks })
	for i = 1, 7 do
		local a = i / 7 * math.pi * 2
		part({ Name = "Canopee", Shape = Enum.PartType.Ball, Size = Vector3.one * 22, CFrame = CFrame.new(top + Vector3.new(math.cos(a) * 20, 10, math.sin(a) * 20)), Color = Color3.fromRGB(60, 140, 60), Material = Enum.Material.Grass, CanCollide = false, Transparency = 0.1 })
	end
	makeRelic("foret", top + Vector3.new(0, 0.75, 0))
	makeCheckpoint(FOREST + Vector3.new(0, 0, 70), "Lisière de la forêt")

	for i = 1, 9 do
		local a = i / 9 * math.pi * 2
		spawnEnemy("slime", FOREST + Vector3.new(math.cos(a) * 45, 0, math.sin(a) * 45 + 10))
	end
	for i = 1, 12 do
		local a = i / 12 * math.pi * 2
		spawnCoin(FOREST + Vector3.new(math.cos(a) * 30, (groundAt(FOREST.X + math.cos(a) * 30, FOREST.Z + math.sin(a) * 30) or 0) + 3, math.sin(a) * 30), 1, true)
	end
	-- Pièces le long de l'escalier
	for i = 5, steps - 1, 5 do
		local a = i * 0.55
		spawnCoin(base + Vector3.new(math.cos(a) * 16, 4 + i * 2.45 + 3, math.sin(a) * 16), 2, true)
	end
end

local function buildCanyon()
	local rng = Random.new(11)
	-- Cristaux
	for _ = 1, 40 do
		local p = CANYON + Vector3.new(rng:NextNumber(-60, 130), 0, rng:NextNumber(-50, 50))
		local y = groundAt(p.X, p.Z)
		if y and y > -5 then
			local h = rng:NextNumber(4, 11)
			local c = part({
				Name = "Cristal", Size = Vector3.new(1.6, h, 1.6),
				CFrame = CFrame.new(p.X, y + h / 2 - 0.5, p.Z) * CFrame.Angles(rng:NextNumber(-0.4, 0.4), rng:NextNumber(0, 3), rng:NextNumber(-0.4, 0.4)),
				Color = Color3.fromHSV(0.52 + rng:NextNumber(0, 0.2), 0.6, 1), Material = Enum.Material.Glass, Transparency = 0.2,
			})
			if rng:NextNumber() < 0.3 then
				light(c, c.Color, 12, 1)
			end
		end
	end
	-- Rochers
	for _ = 1, 18 do
		local p = CANYON + Vector3.new(rng:NextNumber(-70, 20), 0, rng:NextNumber(-45, 45))
		local y = groundAt(p.X, p.Z)
		if y and y > -3 then
			makeRock(Vector3.new(p.X, y, p.Z), rng:NextNumber(3, 7), Color3.fromRGB(170, 130, 95))
		end
	end
	-- Gouffre : le vide tue
	makeKillPart({ Name = "Vide", Size = Vector3.new(46, 2, 110), CFrame = CFrame.new(CANYON.X + 27, -40, CANYON.Z), Transparency = 1, CanCollide = false, CanQuery = true })

	-- Pont de cristaux (certains clignotent)
	local startX = CANYON.X + 2
	for i = 0, 5 do
		local pos = Vector3.new(startX + i * 8.5, 3 + i * 4.6, CANYON.Z + (if i % 2 == 0 then -3 else 3))
		local blink = i == 2 or i == 4
		local plat = part({
			Name = "PlateformeCristal", Size = Vector3.new(5, 1.2, 5), CFrame = CFrame.new(pos),
			Color = if blink then Color3.fromRGB(200, 120, 255) else Color3.fromRGB(110, 210, 255),
			Material = Enum.Material.Neon, Transparency = 0.1,
		})
		if blink then
			billboard(plat, "Instable !", Color3.fromRGB(230, 170, 255), 3, 14)
			task.spawn(function()
				local offset = i * 0.7
				task.wait(offset)
				while plat.Parent do
					task.wait(2.2)
					for k = 1, 4 do
						plat.Transparency = if k % 2 == 1 then 0.6 else 0.1
						task.wait(0.15)
					end
					plat.Transparency = 0.9
					plat.CanCollide = false
					task.wait(1.4)
					plat.Transparency = 0.1
					plat.CanCollide = true
				end
			end)
		end
	end
	makeRelic("canyon", CANYON + Vector3.new(85, 30, 0))
	makeCheckpoint(CANYON + Vector3.new(-45, 0, 0), "Entrée du canyon")

	for i = 1, 7 do
		spawnEnemy("squelette", CANYON + Vector3.new(-40 + i * 5, 0, (if i % 2 == 0 then -20 else 20)))
	end
	for i = 1, 2 do
		spawnEnemy("squelette", CANYON + Vector3.new(75 + i * 6, 30, -10 + i * 8))
	end
	for i = 0, 5 do
		spawnCoin(Vector3.new(startX + i * 8.5, 3 + i * 4.6 + 3, CANYON.Z), 2, true)
	end
end

local function buildVolcano()
	local rng = Random.new(3)
	-- Anneau de lave
	local segs = 40
	local rIn, rOut = 96, 116
	for i = 0, segs - 1 do
		local a = i / segs * math.pi * 2
		local r = (rIn + rOut) / 2
		local len = 2 * math.pi * r / segs + 1
		makeKillPart({
			Name = "Lave", Size = Vector3.new(rOut - rIn, 1, len),
			CFrame = CFrame.new(VOLCANO + Vector3.new(math.cos(a) * r, 0.6, math.sin(a) * r)) * CFrame.Angles(0, -a, 0),
			Color = Color3.fromRGB(255, 90, 20), Material = Enum.Material.Neon,
		})
	end
	-- Pierres de gué (côté est, vers le village)
	for i = 0, 3 do
		local r = rOut - 3 - i * 6
		local a = (if i % 2 == 0 then 0.03 else -0.03)
		part({ Name = "Gue", Shape = Enum.PartType.Cylinder, Size = Vector3.new(2, 4.2, 4.2), CFrame = CFrame.new(VOLCANO + Vector3.new(math.cos(a) * r, 1.4, math.sin(a) * r)) * CFrame.Angles(0, 0, math.rad(90)), Color = Color3.fromRGB(60, 55, 55), Material = Enum.Material.Basalt })
	end
	-- Blocs de basalte
	for _ = 1, 16 do
		local a = rng:NextNumber(0, math.pi * 2)
		local d = rng:NextNumber(40, 90)
		local x, z = VOLCANO.X + math.cos(a) * d, VOLCANO.Z + math.sin(a) * d
		local y = groundAt(x, z)
		if y then
			makeRock(Vector3.new(x, y, z), rng:NextNumber(3, 6), Color3.fromRGB(55, 50, 50))
		end
	end
	-- Coulées de lave sur les flancs
	for i = 1, 5 do
		local a = i / 5 * math.pi * 2 + 0.6
		local prev: Vector3? = nil
		for r = 26, 78, 6 do
			local x, z = VOLCANO.X + math.cos(a) * r, VOLCANO.Z + math.sin(a) * r
			local gy = groundAt(x, z, 200)
			if gy then
				local pt = Vector3.new(x, gy + 0.25, z)
				if prev then
					local mid = (prev + pt) / 2
					makeKillPart({ Name = "Lave", Size = Vector3.new(4, 0.8, (pt - prev).Magnitude + 0.5), CFrame = CFrame.lookAt(mid, pt), Color = Color3.fromRGB(255, 110, 30), Material = Enum.Material.Neon })
				end
				prev = pt
			end
		end
	end
	-- Lave du cratère et fumée
	local crater = makeKillPart({ Name = "Lave", Shape = Enum.PartType.Cylinder, Size = Vector3.new(1, 34, 34), CFrame = CFrame.new(VOLCANO + Vector3.new(0, 48, 0)) * CFrame.Angles(0, 0, math.rad(90)), Color = Color3.fromRGB(255, 80, 10), Material = Enum.Material.Neon })
	light(crater, Color3.fromRGB(255, 110, 40), 60, 3)
	local smoke = Instance.new("Smoke")
	smoke.Size = 30
	smoke.RiseVelocity = 12
	smoke.Color = Color3.fromRGB(80, 70, 70)
	smoke.Parent = crater

	-- Relique au bord du cratère, sur un surplomb
	local rimY = groundAt(VOLCANO.X + 30, VOLCANO.Z, 200) or 50
	local relicPos = Vector3.new(VOLCANO.X + 30, rimY, VOLCANO.Z)
	part({ Name = "Surplomb", Size = Vector3.new(12, 2, 12), CFrame = CFrame.new(relicPos + Vector3.new(0, -0.5, 0)), Color = Color3.fromRGB(70, 60, 60), Material = Enum.Material.Basalt })
	makeRelic("volcan", relicPos + Vector3.new(0, 0.5, 0))
	makeCheckpoint(VOLCANO + Vector3.new(135, 0, 0), "Pied du volcan")

	for i = 1, 8 do
		local a = i / 8 * math.pi * 2
		spawnEnemy("diablotin", VOLCANO + Vector3.new(math.cos(a) * 60, 0, math.sin(a) * 60))
	end
	for i = 1, 10 do
		local a = rng:NextNumber(0, math.pi * 2)
		local d = rng:NextNumber(30, 80)
		local x, z = VOLCANO.X + math.cos(a) * d, VOLCANO.Z + math.sin(a) * d
		spawnCoin(Vector3.new(x, (groundAt(x, z) or 0) + 3, z), 3, true)
	end
end

local function buildTemple()
	local stone = Color3.fromRGB(170, 165, 150)
	-- Parvis et colonnes
	part({ Name = "Parvis", Size = Vector3.new(50, 2, 30), CFrame = CFrame.new(TEMPLE + Vector3.new(0, 1, 0)), Color = stone, Material = Enum.Material.Marble })
	for _, x in { -20, -12, 12, 20 } do
		part({ Name = "Colonne", Shape = Enum.PartType.Cylinder, Size = Vector3.new(22, 3.4, 3.4), CFrame = CFrame.new(TEMPLE + Vector3.new(x, 13, -8)) * CFrame.Angles(0, 0, math.rad(90)), Color = stone, Material = Enum.Material.Marble })
	end
	part({ Name = "Fronton", Size = Vector3.new(50, 4, 8), CFrame = CFrame.new(TEMPLE + Vector3.new(0, 25, -8)), Color = stone, Material = Enum.Material.Marble })
	part({ Name = "Toit", ClassName = "WedgePart", Size = Vector3.new(8, 8, 25), CFrame = CFrame.new(TEMPLE + Vector3.new(-12.5, 31, -8)) * CFrame.Angles(0, math.rad(-90), 0), Color = Color3.fromRGB(140, 130, 115), Material = Enum.Material.Slate })
	part({ Name = "Toit", ClassName = "WedgePart", Size = Vector3.new(8, 8, 25), CFrame = CFrame.new(TEMPLE + Vector3.new(12.5, 31, -8)) * CFrame.Angles(0, math.rad(90), 0), Color = Color3.fromRGB(140, 130, 115), Material = Enum.Material.Slate })

	-- Mur d'enceinte de l'arène (fermé : on n'y entre que par la porte)
	local wallR = 55
	local segs = 36
	for i = 0, segs - 1 do
		local a = i / segs * math.pi * 2
		part({
			Name = "Rempart", Size = Vector3.new(4, 34, 2 * math.pi * wallR / segs + 1),
			CFrame = CFrame.new(ARENA + Vector3.new(math.cos(a) * wallR, 16, math.sin(a) * wallR)) * CFrame.Angles(0, -a, 0),
			Color = Color3.fromRGB(120, 115, 105), Material = Enum.Material.Slate,
		})
	end
	part({ Name = "SolArene", Shape = Enum.PartType.Cylinder, Size = Vector3.new(2, wallR * 2, wallR * 2), CFrame = CFrame.new(ARENA + Vector3.new(0, -0.9, 0)) * CFrame.Angles(0, 0, math.rad(90)), Color = Color3.fromRGB(95, 90, 85), Material = Enum.Material.Slate })
	for i = 0, 5 do
		local a = i / 6 * math.pi * 2
		local brazier = part({ Name = "Brasero", Size = Vector3.new(2.5, 5, 2.5), CFrame = CFrame.new(ARENA + Vector3.new(math.cos(a) * 44, 2.5, math.sin(a) * 44)), Color = Color3.fromRGB(60, 55, 50), Material = Enum.Material.Metal })
		local f = Instance.new("Fire")
		f.Color = Color3.fromRGB(80, 200, 255)
		f.SecondaryColor = Color3.fromRGB(30, 80, 255)
		f.Parent = brazier
		light(brazier, Color3.fromRGB(80, 200, 255), 25, 1.5)
	end

	-- Porte scellée (entrée du temple)
	local gate = part({
		Name = "PorteDuTemple", Size = Vector3.new(14, 18, 2), CFrame = CFrame.new(TEMPLE + Vector3.new(0, 11, 2)),
		Color = Color3.fromRGB(90, 85, 80), Material = Enum.Material.Slate,
	})
	for i, id in RELIC_ORDER do
		local slot = part({ Name = "Emplacement", Shape = Enum.PartType.Ball, Size = Vector3.new(1.6, 1.6, 1.6), CFrame = CFrame.new(TEMPLE + Vector3.new(-4 + (i - 1) * 4, 16, 0.8)), Color = RELICS[id].color, Material = Enum.Material.Neon })
		light(slot, RELICS[id].color, 8, 1)
	end
	billboard(gate, "Porte scellée — 3 reliques requises", Color3.fromRGB(255, 230, 160), 11, 18)
	local busy: { [Player]: boolean } = {}
	gate.Touched:Connect(function(hit)
		local player = Players:GetPlayerFromCharacter(hit.Parent)
		local d = player and DATA[player]
		if not player or not d or busy[player] then
			return
		end
		busy[player] = true
		task.delay(2, function()
			busy[player] = nil
		end)
		if relicCount(d) < 3 then
			notify(player, string.format("La porte reste scellée… (%d/3 reliques)", relicCount(d)), Color3.fromRGB(255, 180, 120))
			return
		end
		local char = player.Character
		if char then
			char:PivotTo(CFrame.new(ARENA + Vector3.new(0, 4, -40)) * CFrame.Angles(0, math.rad(180), 0))
			notify(player, "Tu pénètres dans l'Antre du Gardien…", Color3.fromRGB(150, 220, 255))
		end
	end)

	-- Portail de sortie dans l'arène
	local portal = part({ Name = "PortailSortie", Size = Vector3.new(8, 10, 1), CFrame = CFrame.new(ARENA + Vector3.new(0, 5, -52)), Color = Color3.fromRGB(120, 200, 255), Material = Enum.Material.Neon, Transparency = 0.35, CanCollide = false })
	billboard(portal, "Retour au village", Color3.fromRGB(180, 230, 255), 7, 16)
	portal.Touched:Connect(function(hit)
		local player = Players:GetPlayerFromCharacter(hit.Parent)
		if player and player.Character then
			player.Character:PivotTo(CFrame.new(0, 5, 14))
			BossRemote:FireClient(player, false)
		end
	end)
	makeCheckpoint(TEMPLE + Vector3.new(0, 0, -45), "Parvis du temple")
end

---------------------------------------------------------------------------
-- DÉMARRAGE
---------------------------------------------------------------------------

buildTerrain()
refreshGroundFilter()
buildVillage()
buildForest()
buildCanyon()
buildVolcano()
buildTemple()

-- Pièces sur les chemins
for _, target in { FOREST + Vector3.new(0, 0, 90), CANYON - Vector3.new(60, 0, 0), VOLCANO + Vector3.new(120, 0, 0), TEMPLE - Vector3.new(0, 0, 40) } do
	for k = 1, 6 do
		local p = VILLAGE:Lerp(target, k / 7)
		spawnCoin(Vector3.new(p.X, (groundAt(p.X, p.Z) or 0) + 3, p.Z), 1, true)
	end
end

local function onCharacter(player: Player, char: Model)
	refreshGroundFilter()
	local hum = char:WaitForChild("Humanoid") :: Humanoid
	char:WaitForChild("HumanoidRootPart")
	task.wait(0.1)
	local d = DATA[player]
	if d and d.checkpoint then
		local cp = d.checkpoint
		char:PivotTo(CFrame.new(cp[1], cp[2], cp[3]))
	end
	applyCharacterStats(player)
	giveSword(player)
	hum.Died:Connect(function()
		notify(player, "Tu es tombé… Retour au dernier point de contrôle.", Color3.fromRGB(255, 140, 140))
	end)
end

local function onPlayer(player: Player)
	local ls = Instance.new("Folder")
	ls.Name = "leaderstats"
	local c = Instance.new("IntValue")
	c.Name = "Pièces"
	c.Parent = ls
	local r = Instance.new("IntValue")
	r.Name = "Reliques"
	r.Parent = ls
	ls.Parent = player

	DATA[player] = loadData(player)
	player.CharacterAdded:Connect(function(char)
		onCharacter(player, char)
	end)
	if player.Character then
		onCharacter(player, player.Character)
	end
	task.wait(1.5)
	if not DATA[player] then
		return
	end
	updateQuest(player)
	if DATA[player].stage == 0 then
		DialogRemote:FireClient(player, "Une voix lointaine", {
			"Bienvenue sur l'Île des Reliques, voyageur…",
			"Le Vieux Sage t'attend près du puits, au centre du village.",
		})
	end
end

Players.PlayerAdded:Connect(onPlayer)
for _, plr in Players:GetPlayers() do
	task.spawn(onPlayer, plr)
end

Players.PlayerRemoving:Connect(function(player)
	save(player)
	DATA[player] = nil
	lastSwing[player] = nil
	refreshGroundFilter()
end)

game:BindToClose(function()
	for _, plr in Players:GetPlayers() do
		save(plr)
	end
end)

-- Sauvegarde automatique
task.spawn(function()
	while true do
		task.wait(120)
		for _, plr in Players:GetPlayers() do
			save(plr)
		end
	end
end)

-- Boutique
ShopRemote.OnServerEvent:Connect(function(player, itemId)
	local d = DATA[player]
	if not d or typeof(itemId) ~= "string" then
		return
	end
	local item
	for _, it in SHOP_ITEMS do
		if it.id == itemId then
			item = it
		end
	end
	if not item then
		return
	end
	if d.coins < item.price then
		notify(player, "Pas assez de pièces !", Color3.fromRGB(255, 140, 140))
		return
	end
	if itemId == "epee2" then
		if d.sword >= 2 then
			notify(player, "Tu as déjà cette épée.")
			return
		end
		d.sword = 2
	elseif itemId == "epee3" then
		if d.sword >= 3 then
			notify(player, "Tu as déjà cette épée.")
			return
		end
		if d.sword < 2 then
			notify(player, "Il te faut d'abord l'Épée d'acier.")
			return
		end
		d.sword = 3
	elseif itemId == "bottes" then
		if d.bottes then
			notify(player, "Tu as déjà ces bottes.")
			return
		end
		d.bottes = true
	elseif itemId == "coeur" then
		if d.coeur then
			notify(player, "Tu possèdes déjà le Cœur de héros.")
			return
		end
		d.coeur = true
	elseif itemId == "potion" then
		local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
		if hum then
			hum.Health = hum.MaxHealth
		end
	end
	d.coins -= item.price
	notify(player, item.name .. " acheté(e) !", Color3.fromRGB(255, 220, 120))
	if itemId == "epee2" or itemId == "epee3" then
		giveSword(player)
	elseif itemId == "bottes" or itemId == "coeur" then
		local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
		if hum then
			local frac = hum.Health / hum.MaxHealth
			hum.WalkSpeed = if d.bottes then 22 else 16
			hum.MaxHealth = if d.coeur then 150 else 100
			hum.Health = hum.MaxHealth * frac
		end
	end
	updateStats(player)
	ShopRemote:FireClient(player, SHOP_ITEMS, { sword = d.sword, bottes = d.bottes, coeur = d.coeur })
	save(player)
end)

-- Boucle principale : ennemis, boss, pièces, zones
local zoneTimer = 0
RunService.Heartbeat:Connect(function(dt)
	local now = os.clock()
	for i = #enemies, 1, -1 do
		local e = enemies[i]
		if e and e.alive then
			updateEnemy(e, dt, now)
		end
	end
	updateBoss(dt, now)

	local spin = CFrame.Angles(0, now * 2, 0)
	for _, c in coins do
		if c.part.Parent then
			c.part.CFrame = CFrame.new(c.base + Vector3.new(0, math.sin(now * 3 + c.base.X) * 0.4, 0)) * spin
		end
	end

	zoneTimer -= dt
	if zoneTimer <= 0 then
		zoneTimer = 0.5
		for _, plr in Players:GetPlayers() do
			local hrp = plr.Character and plr.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
			if hrp then
				local flat = Vector3.new(hrp.Position.X, 0, hrp.Position.Z)
				local zone = "Terres sauvages"
				for _, z in ZONES do
					if (flat - z.center).Magnitude < z.radius then
						zone = z.name
					end
				end
				if plr:GetAttribute("Zone") ~= zone then
					plr:SetAttribute("Zone", zone)
				end
			end
		end
	end
end)

print("L'Île des Reliques est prête !")
