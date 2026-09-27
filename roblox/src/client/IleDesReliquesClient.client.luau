--[[
	L'ÎLE DES RELIQUES — script client (interface)
	À placer dans StarterPlayer > StarterPlayerScripts (type : LocalScript).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Debris = game:GetService("Debris")

local player = Players.LocalPlayer
local Remotes = ReplicatedStorage:WaitForChild("IleRemotes")

local GOLD = Color3.fromRGB(240, 200, 110)
local PANEL = Color3.fromRGB(22, 18, 30)
local TEXT = Color3.fromRGB(245, 235, 215)

local RELIC_COLORS = {
	foret = Color3.fromRGB(80, 230, 120),
	canyon = Color3.fromRGB(90, 200, 255),
	volcan = Color3.fromRGB(255, 120, 40),
}
local RELIC_ORDER = { "foret", "canyon", "volcan" }

---------------------------------------------------------------------------
-- OUTILS D'INTERFACE
---------------------------------------------------------------------------

local gui = Instance.new("ScreenGui")
gui.Name = "IleInterface"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = false
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Parent = player:WaitForChild("PlayerGui")

local function corner(parent: GuiObject, radius: number?)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius or 10)
	c.Parent = parent
end

local function stroke(parent: GuiObject, color: Color3?, thickness: number?)
	local s = Instance.new("UIStroke")
	s.Color = color or GOLD
	s.Thickness = thickness or 2
	s.Transparency = 0.2
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.Parent = parent
end

local function panel(props: { [string]: any }): Frame
	local f = Instance.new("Frame")
	f.BackgroundColor3 = PANEL
	f.BackgroundTransparency = 0.15
	f.BorderSizePixel = 0
	for k, v in props do
		(f :: any)[k] = v
	end
	corner(f)
	stroke(f)
	return f
end

local function label(props: { [string]: any }): TextLabel
	local t = Instance.new("TextLabel")
	t.BackgroundTransparency = 1
	t.TextColor3 = TEXT
	t.Font = Enum.Font.GothamMedium
	t.TextSize = 16
	t.TextWrapped = true
	for k, v in props do
		(t :: any)[k] = v
	end
	return t
end

local function button(props: { [string]: any }): TextButton
	local b = Instance.new("TextButton")
	b.BackgroundColor3 = Color3.fromRGB(120, 80, 30)
	b.TextColor3 = TEXT
	b.Font = Enum.Font.GothamBold
	b.TextSize = 16
	b.AutoButtonColor = true
	b.BorderSizePixel = 0
	for k, v in props do
		(b :: any)[k] = v
	end
	corner(b, 8)
	stroke(b, GOLD, 1.5)
	return b
end

---------------------------------------------------------------------------
-- PIÈCES ET RELIQUES (en haut à gauche)
---------------------------------------------------------------------------

local statsPanel = panel({ Name = "Stats", Size = UDim2.fromOffset(250, 90), Position = UDim2.fromOffset(12, 12), Parent = gui })
local coinIcon = Instance.new("Frame")
coinIcon.Size = UDim2.fromOffset(26, 26)
coinIcon.Position = UDim2.fromOffset(14, 12)
coinIcon.BackgroundColor3 = Color3.fromRGB(255, 205, 50)
coinIcon.Parent = statsPanel
corner(coinIcon, 13)
stroke(coinIcon, Color3.fromRGB(180, 130, 20), 2)
local coinLabel = label({
	Size = UDim2.fromOffset(180, 30), Position = UDim2.fromOffset(50, 10), Text = "0",
	TextXAlignment = Enum.TextXAlignment.Left, Font = Enum.Font.GothamBold, TextSize = 24, TextColor3 = GOLD, Parent = statsPanel,
})
label({
	Size = UDim2.fromOffset(90, 20), Position = UDim2.fromOffset(14, 54), Text = "Reliques",
	TextXAlignment = Enum.TextXAlignment.Left, TextSize = 14, TextColor3 = Color3.fromRGB(200, 190, 170), Parent = statsPanel,
})
local relicSlots: { [string]: Frame } = {}
for i, id in RELIC_ORDER do
	local slot = Instance.new("Frame")
	slot.Size = UDim2.fromOffset(28, 28)
	slot.Position = UDim2.fromOffset(100 + (i - 1) * 42, 50)
	slot.BackgroundColor3 = Color3.fromRGB(50, 45, 60)
	slot.Rotation = 45
	slot.Parent = statsPanel
	corner(slot, 6)
	stroke(slot, RELIC_COLORS[id], 2)
	relicSlots[id] = slot
end

local function refreshStats()
	coinLabel.Text = tostring(player:GetAttribute("Coins") or 0)
	for _, id in RELIC_ORDER do
		local owned = player:GetAttribute("Relic_" .. id) == true
		relicSlots[id].BackgroundColor3 = if owned then RELIC_COLORS[id] else Color3.fromRGB(50, 45, 60)
	end
end
player.AttributeChanged:Connect(function(name)
	if name == "Coins" then
		local old = tonumber(coinLabel.Text) or 0
		local new = player:GetAttribute("Coins") or 0
		if new > old then
			coinLabel.TextSize = 30
			TweenService:Create(coinLabel, TweenInfo.new(0.25), { TextSize = 24 }):Play()
		end
	end
	refreshStats()
end)
refreshStats()

---------------------------------------------------------------------------
-- QUÊTE (à droite)
---------------------------------------------------------------------------

local questPanel = panel({ Name = "Quete", Size = UDim2.fromOffset(300, 96), Position = UDim2.new(1, -312, 0, 12), Parent = gui })
local questTitle = label({
	Size = UDim2.new(1, -24, 0, 24), Position = UDim2.fromOffset(12, 8), Text = "Quête",
	TextXAlignment = Enum.TextXAlignment.Left, Font = Enum.Font.Fantasy, TextSize = 22, TextColor3 = GOLD, Parent = questPanel,
})
local questText = label({
	Size = UDim2.new(1, -24, 1, -40), Position = UDim2.fromOffset(12, 34), Text = "",
	TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top, TextSize = 15, Parent = questPanel,
})

Remotes:WaitForChild("Quest").OnClientEvent:Connect(function(title: string, text: string)
	local changed = questTitle.Text ~= title
	questTitle.Text = title
	questText.Text = text
	if changed then
		questPanel.Position = UDim2.new(1, 20, 0, 12)
		TweenService:Create(questPanel, TweenInfo.new(0.5, Enum.EasingStyle.Back), { Position = UDim2.new(1, -312, 0, 12) }):Play()
	end
end)

---------------------------------------------------------------------------
-- NOTIFICATIONS
---------------------------------------------------------------------------

local notifHolder = Instance.new("Frame")
notifHolder.Size = UDim2.new(0, 520, 0, 200)
notifHolder.Position = UDim2.new(0.5, -260, 0, 120)
notifHolder.BackgroundTransparency = 1
notifHolder.Parent = gui
local list = Instance.new("UIListLayout")
list.HorizontalAlignment = Enum.HorizontalAlignment.Center
list.Padding = UDim.new(0, 6)
list.SortOrder = Enum.SortOrder.LayoutOrder
list.Parent = notifHolder
local notifCount = 0

Remotes:WaitForChild("Notify").OnClientEvent:Connect(function(text: string, color: Color3?)
	notifCount += 1
	local f = panel({ Size = UDim2.fromOffset(500, 38), LayoutOrder = notifCount, Parent = notifHolder })
	local t = label({ Size = UDim2.fromScale(1, 1), Text = text, Font = Enum.Font.GothamBold, TextSize = 17, TextColor3 = color or TEXT, Parent = f })
	f.BackgroundTransparency = 1
	t.TextTransparency = 1
	TweenService:Create(f, TweenInfo.new(0.25), { BackgroundTransparency = 0.15 }):Play()
	TweenService:Create(t, TweenInfo.new(0.25), { TextTransparency = 0 }):Play()
	task.delay(3.5, function()
		TweenService:Create(f, TweenInfo.new(0.4), { BackgroundTransparency = 1 }):Play()
		TweenService:Create(t, TweenInfo.new(0.4), { TextTransparency = 1 }):Play()
		local s = f:FindFirstChildOfClass("UIStroke")
		if s then
			TweenService:Create(s, TweenInfo.new(0.4), { Transparency = 1 }):Play()
		end
		task.wait(0.45)
		f:Destroy()
	end)
	if #notifHolder:GetChildren() > 5 then
		for _, c in notifHolder:GetChildren() do
			if c:IsA("Frame") then
				c:Destroy()
				break
			end
		end
	end
end)

---------------------------------------------------------------------------
-- TITRE DE ZONE
---------------------------------------------------------------------------

local zoneTitle = label({
	Size = UDim2.new(1, 0, 0, 60), Position = UDim2.new(0, 0, 0.28, 0), Text = "",
	Font = Enum.Font.Fantasy, TextSize = 52, TextColor3 = GOLD, TextStrokeTransparency = 0.4, TextTransparency = 1, Parent = gui,
})
local zoneSub = label({
	Size = UDim2.new(1, 0, 0, 24), Position = UDim2.new(0, 0, 0.28, 62), Text = "— Nouvelle région —",
	Font = Enum.Font.GothamMedium, TextSize = 18, TextColor3 = TEXT, TextStrokeTransparency = 0.5, TextTransparency = 1, Parent = gui,
})
local zoneToken = 0
player:GetAttributeChangedSignal("Zone"):Connect(function()
	local zone = player:GetAttribute("Zone")
	if type(zone) ~= "string" or zone == "Terres sauvages" then
		return
	end
	zoneToken += 1
	local my = zoneToken
	zoneTitle.Text = zone
	TweenService:Create(zoneTitle, TweenInfo.new(0.6), { TextTransparency = 0, TextStrokeTransparency = 0.4 }):Play()
	TweenService:Create(zoneSub, TweenInfo.new(0.6), { TextTransparency = 0.1 }):Play()
	task.delay(2.8, function()
		if my ~= zoneToken then
			return
		end
		TweenService:Create(zoneTitle, TweenInfo.new(0.8), { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
		TweenService:Create(zoneSub, TweenInfo.new(0.8), { TextTransparency = 1 }):Play()
	end)
end)

---------------------------------------------------------------------------
-- DIALOGUES
---------------------------------------------------------------------------

local dialog = panel({ Name = "Dialogue", Size = UDim2.new(0, 640, 0, 150), Position = UDim2.new(0.5, -320, 1, -190), Visible = false, Parent = gui })
local speaker = label({
	Size = UDim2.new(1, -30, 0, 28), Position = UDim2.fromOffset(18, 10), Text = "",
	TextXAlignment = Enum.TextXAlignment.Left, Font = Enum.Font.Fantasy, TextSize = 24, TextColor3 = GOLD, Parent = dialog,
})
local lineText = label({
	Size = UDim2.new(1, -36, 1, -80), Position = UDim2.fromOffset(18, 42), Text = "",
	TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top, TextSize = 18, Parent = dialog,
})
local nextBtn = button({ Size = UDim2.fromOffset(150, 32), Position = UDim2.new(1, -165, 1, -42), Text = "Continuer ▶", Parent = dialog })

local dialogLines: { string } = {}
local dialogIndex = 0
local typing = false
local typeToken = 0

local function showLine()
	local text = dialogLines[dialogIndex]
	if not text then
		dialog.Visible = false
		return
	end
	nextBtn.Text = if dialogIndex == #dialogLines then "Fermer ✕" else "Continuer ▶"
	typeToken += 1
	local my = typeToken
	typing = true
	lineText.Text = text
	lineText.MaxVisibleGraphemes = 0
	task.spawn(function()
		local n = utf8.len(text) or #text
		for i = 1, n do
			if my ~= typeToken then
				return
			end
			lineText.MaxVisibleGraphemes = i
			task.wait(0.018)
		end
		typing = false
	end)
end

local function advance()
	if not dialog.Visible then
		return
	end
	if typing then
		typeToken += 1
		typing = false
		lineText.MaxVisibleGraphemes = -1
		return
	end
	dialogIndex += 1
	showLine()
end

nextBtn.Activated:Connect(advance)
UserInputService.InputBegan:Connect(function(input, processed)
	if processed then
		return
	end
	if input.KeyCode == Enum.KeyCode.Return then
		advance()
	end
end)

Remotes:WaitForChild("Dialog").OnClientEvent:Connect(function(name: string, lines: { string })
	speaker.Text = name
	dialogLines = lines
	dialogIndex = 1
	dialog.Visible = true
	showLine()
end)

---------------------------------------------------------------------------
-- BOUTIQUE
---------------------------------------------------------------------------

local ShopRemote = Remotes:WaitForChild("Shop") :: RemoteEvent
local shop = panel({ Name = "Boutique", Size = UDim2.fromOffset(460, 420), Position = UDim2.new(0.5, -230, 0.5, -210), Visible = false, Parent = gui })
label({
	Size = UDim2.new(1, 0, 0, 40), Position = UDim2.fromOffset(0, 10), Text = "Échoppe de Barnabé",
	Font = Enum.Font.Fantasy, TextSize = 30, TextColor3 = GOLD, Parent = shop,
})
local closeShop = button({ Size = UDim2.fromOffset(34, 34), Position = UDim2.new(1, -44, 0, 10), Text = "✕", BackgroundColor3 = Color3.fromRGB(110, 40, 40), Parent = shop })
closeShop.Activated:Connect(function()
	shop.Visible = false
end)
local shopList = Instance.new("Frame")
shopList.Size = UDim2.new(1, -30, 1, -70)
shopList.Position = UDim2.fromOffset(15, 58)
shopList.BackgroundTransparency = 1
shopList.Parent = shop
local shopLayout = Instance.new("UIListLayout")
shopLayout.Padding = UDim.new(0, 8)
shopLayout.Parent = shopList

ShopRemote.OnClientEvent:Connect(function(items, owned)
	for _, c in shopList:GetChildren() do
		if c:IsA("Frame") then
			c:Destroy()
		end
	end
	for _, item in items do
		local row = Instance.new("Frame")
		row.Size = UDim2.new(1, 0, 0, 62)
		row.BackgroundColor3 = Color3.fromRGB(40, 34, 50)
		row.BorderSizePixel = 0
		row.Parent = shopList
		corner(row, 8)
		label({ Size = UDim2.new(1, -150, 0, 24), Position = UDim2.fromOffset(12, 6), Text = item.name, Font = Enum.Font.GothamBold, TextSize = 18, TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = GOLD, Parent = row })
		label({ Size = UDim2.new(1, -150, 0, 26), Position = UDim2.fromOffset(12, 30), Text = item.desc, TextSize = 13, TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = Color3.fromRGB(200, 190, 175), Parent = row })
		local isOwned = (item.id == "epee2" and owned.sword >= 2) or (item.id == "epee3" and owned.sword >= 3)
			or (item.id == "bottes" and owned.bottes) or (item.id == "coeur" and owned.coeur)
		local buy = button({
			Size = UDim2.fromOffset(120, 40), Position = UDim2.new(1, -130, 0.5, -20),
			Text = if isOwned then "Possédé" else ("● " .. item.price),
			BackgroundColor3 = if isOwned then Color3.fromRGB(60, 60, 60) else Color3.fromRGB(150, 100, 30),
			Parent = row,
		})
		if not isOwned then
			buy.Activated:Connect(function()
				ShopRemote:FireServer(item.id)
			end)
		end
	end
	shop.Visible = true
end)

---------------------------------------------------------------------------
-- BARRE DU BOSS
---------------------------------------------------------------------------

local bossPanel = panel({ Name = "Boss", Size = UDim2.fromOffset(520, 56), Position = UDim2.new(0.5, -260, 0, 12), Visible = false, Parent = gui })
label({ Size = UDim2.new(1, 0, 0, 24), Position = UDim2.fromOffset(0, 4), Text = "Le Gardien de Pierre", Font = Enum.Font.Fantasy, TextSize = 22, TextColor3 = Color3.fromRGB(150, 220, 255), Parent = bossPanel })
local bossBack = Instance.new("Frame")
bossBack.Size = UDim2.new(1, -24, 0, 14)
bossBack.Position = UDim2.fromOffset(12, 32)
bossBack.BackgroundColor3 = Color3.fromRGB(40, 15, 15)
bossBack.BorderSizePixel = 0
bossBack.Parent = bossPanel
corner(bossBack, 7)
local bossFill = Instance.new("Frame")
bossFill.Size = UDim2.fromScale(1, 1)
bossFill.BackgroundColor3 = Color3.fromRGB(220, 60, 60)
bossFill.BorderSizePixel = 0
bossFill.Parent = bossBack
corner(bossFill, 7)

Remotes:WaitForChild("Boss").OnClientEvent:Connect(function(visible: boolean, hp: number?, maxHp: number?)
	bossPanel.Visible = visible
	if visible and hp and maxHp then
		TweenService:Create(bossFill, TweenInfo.new(0.15), { Size = UDim2.fromScale(math.max(0, hp / maxHp), 1) }):Play()
	end
end)

---------------------------------------------------------------------------
-- VICTOIRE
---------------------------------------------------------------------------

local victory = panel({ Name = "Victoire", Size = UDim2.fromOffset(520, 260), Position = UDim2.new(0.5, -260, 0.5, -130), Visible = false, Parent = gui })
label({ Size = UDim2.new(1, 0, 0, 70), Position = UDim2.fromOffset(0, 20), Text = "VICTOIRE !", Font = Enum.Font.Fantasy, TextSize = 64, TextColor3 = GOLD, Parent = victory })
local victoryText = label({ Size = UDim2.new(1, -40, 0, 80), Position = UDim2.fromOffset(20, 95), Text = "", TextSize = 18, Parent = victory })
local victoryClose = button({ Size = UDim2.fromOffset(180, 40), Position = UDim2.new(0.5, -90, 1, -60), Text = "Continuer", Parent = victory })
victoryClose.Activated:Connect(function()
	victory.Visible = false
end)

Remotes:WaitForChild("Victory").OnClientEvent:Connect(function(first: boolean, reward: number)
	bossPanel.Visible = false
	victoryText.Text = if first
		then string.format("Le Gardien de Pierre est vaincu !\nL'île est sauvée et tu deviens Héros de l'île.\n+%d pièces", reward)
		else string.format("Le Gardien retourne à la poussière.\n+%d pièces", reward)
	victory.Visible = true
	victory.Size = UDim2.fromOffset(0, 0)
	victory.Position = UDim2.fromScale(0.5, 0.5)
	TweenService:Create(victory, TweenInfo.new(0.5, Enum.EasingStyle.Back), { Size = UDim2.fromOffset(520, 260), Position = UDim2.new(0.5, -260, 0.5, -130) }):Play()
end)

---------------------------------------------------------------------------
-- DÉGÂTS FLOTTANTS
---------------------------------------------------------------------------

Remotes:WaitForChild("Hit").OnClientEvent:Connect(function(pos: Vector3, amount: number)
	local cam = workspace.CurrentCamera
	if cam and (cam.CFrame.Position - pos).Magnitude > 120 then
		return
	end
	local anchor = Instance.new("Part")
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.Transparency = 1
	anchor.Size = Vector3.new(0.2, 0.2, 0.2)
	anchor.CFrame = CFrame.new(pos + Vector3.new(math.random(-10, 10) / 10, 0, math.random(-10, 10) / 10))
	anchor.Parent = workspace
	local bb = Instance.new("BillboardGui")
	bb.Size = UDim2.fromOffset(80, 40)
	bb.AlwaysOnTop = true
	bb.Parent = anchor
	local t = label({ Size = UDim2.fromScale(1, 1), Text = tostring(math.floor(amount)), Font = Enum.Font.GothamBlack, TextSize = 26, TextColor3 = Color3.fromRGB(255, 230, 120), TextStrokeTransparency = 0.2, Parent = bb })
	TweenService:Create(anchor, TweenInfo.new(0.8), { CFrame = anchor.CFrame + Vector3.new(0, 4, 0) }):Play()
	TweenService:Create(t, TweenInfo.new(0.8), { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
	Debris:AddItem(anchor, 0.85)
end)

---------------------------------------------------------------------------
-- AIDE
---------------------------------------------------------------------------

local help = label({
	Size = UDim2.fromOffset(420, 22), Position = UDim2.new(0, 14, 1, -34),
	Text = "Clic : frapper avec l'épée  •  E : parler / prendre  •  Espace : sauter",
	TextXAlignment = Enum.TextXAlignment.Left, TextSize = 14, TextColor3 = Color3.fromRGB(230, 220, 200), TextStrokeTransparency = 0.5, Parent = gui,
})
if UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled then
	help.Text = "Touchez l'écran pour frapper • Bouton d'action pour interagir"
end
