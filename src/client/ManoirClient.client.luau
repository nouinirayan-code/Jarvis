--[[
	LE MANOIR DES OMBRES — script client
	À placer dans StarterPlayer > StarterPlayerScripts (type : LocalScript).

	Interface, course, lampe torche, clavier du coffre, notes, effets d'horreur.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local ContextActionService = game:GetService("ContextActionService")

local player = Players.LocalPlayer
local Remotes = ReplicatedStorage:WaitForChild("ManoirRemotes")

local function inRound(): boolean
	return player:GetAttribute("InRound") == true
end

local INK = Color3.fromRGB(235, 225, 215)
local BLOOD = Color3.fromRGB(170, 20, 30)
local PANEL = Color3.fromRGB(10, 8, 12)

---------------------------------------------------------------------------
-- OUTILS D'INTERFACE
---------------------------------------------------------------------------

local gui = Instance.new("ScreenGui")
gui.Name = "ManoirInterface"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Parent = player:WaitForChild("PlayerGui")

local function corner(o: GuiObject, r: number?)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, r or 8)
	c.Parent = o
end

local function stroke(o: GuiObject, color: Color3?, t: number?)
	local s = Instance.new("UIStroke")
	s.Color = color or Color3.fromRGB(90, 30, 35)
	s.Thickness = t or 1.5
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.Parent = o
end

local function frame(props: { [string]: any }): Frame
	local f = Instance.new("Frame")
	f.BackgroundColor3 = PANEL
	f.BackgroundTransparency = 0.25
	f.BorderSizePixel = 0
	for k, v in props do
		(f :: any)[k] = v
	end
	return f
end

local function text(props: { [string]: any }): TextLabel
	local t = Instance.new("TextLabel")
	t.BackgroundTransparency = 1
	t.TextColor3 = INK
	t.Font = Enum.Font.SpecialElite
	t.TextSize = 18
	t.TextWrapped = true
	for k, v in props do
		(t :: any)[k] = v
	end
	return t
end

local function button(props: { [string]: any }): TextButton
	local b = Instance.new("TextButton")
	b.BackgroundColor3 = Color3.fromRGB(45, 18, 22)
	b.TextColor3 = INK
	b.Font = Enum.Font.SpecialElite
	b.TextSize = 20
	b.BorderSizePixel = 0
	b.AutoButtonColor = true
	for k, v in props do
		(b :: any)[k] = v
	end
	corner(b, 6)
	stroke(b, Color3.fromRGB(130, 40, 45), 1.5)
	return b
end

---------------------------------------------------------------------------
-- EFFETS PLEIN ÉCRAN (sous l'interface)
---------------------------------------------------------------------------

local fear = frame({ Size = UDim2.fromScale(1, 1), BackgroundColor3 = BLOOD, BackgroundTransparency = 1, ZIndex = 1, Parent = gui })
local fearGradient = Instance.new("UIGradient")
fearGradient.Transparency = NumberSequence.new({
	NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.25, 0.7),
	NumberSequenceKeypoint.new(0.75, 0.7), NumberSequenceKeypoint.new(1, 0),
})
fearGradient.Parent = fear

-- Vue depuis l'armoire : noir avec des fentes de lumière
local hideView = frame({ Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 1, ZIndex = 2, Visible = false, Parent = gui })
for i = 0, 5 do
	frame({ Size = UDim2.new(1, 0, 0.11, 0), Position = UDim2.fromScale(0, i * 0.17), BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 0, ZIndex = 2, Parent = hideView })
end
text({ Size = UDim2.new(1, 0, 0, 30), Position = UDim2.new(0, 0, 1, -60), Text = "Tu es caché… Retiens ton souffle. (E pour sortir)", TextSize = 20, ZIndex = 3, Parent = hideView })

---------------------------------------------------------------------------
-- SONS
---------------------------------------------------------------------------

local SoundService = game:GetService("SoundService")
local Debris = game:GetService("Debris")
local SoundIds = ReplicatedStorage:WaitForChild("ManoirSons")

local function sid(key: string): string?
	local v = SoundIds:FindFirstChild(key) :: StringValue?
	if v and v.Value ~= "" then
		return v.Value
	end
	return nil
end

local function makeSound(key: string, looped: boolean, volume: number): Sound?
	local id = sid(key)
	if not id then
		return nil
	end
	local snd = Instance.new("Sound")
	snd.Name = "Local_" .. key
	snd.SoundId = id
	snd.Looped = looped
	snd.Volume = volume
	snd.Parent = SoundService
	return snd
end

local function playLocal(key: string, volume: number?, speed: number?)
	local snd = makeSound(key, false, volume or 1)
	if snd then
		snd.PlaybackSpeed = speed or 1
		snd:Play()
		Debris:AddItem(snd, 15)
	end
end

-- Boucles d'ambiance (volumes ajustés en continu)
local loops: { [string]: Sound } = {}
for _, key in { "ambiance", "pluie", "lobby", "respiration" } do
	local snd = makeSound(key, true, 0)
	if snd then
		snd:Play()
		loops[key] = snd
	end
end
local function fadeLoop(key: string, target: number, dt: number)
	local snd = loops[key]
	if snd then
		snd.Volume += (target - snd.Volume) * math.min(1, dt * 1.5)
	end
end

---------------------------------------------------------------------------
-- HUD
---------------------------------------------------------------------------

local top = frame({ Size = UDim2.fromOffset(520, 64), Position = UDim2.new(0.5, -260, 0, 10), Parent = gui })
corner(top, 10)
stroke(top)
local timerLabel = text({ Size = UDim2.new(1, 0, 0, 26), Position = UDim2.fromOffset(0, 4), Text = "--:--", Font = Enum.Font.Creepster, TextSize = 28, TextColor3 = Color3.fromRGB(220, 60, 60), Parent = top })
local objective = text({ Size = UDim2.new(1, -20, 0, 30), Position = UDim2.fromOffset(10, 30), Text = "", TextSize = 15, Parent = top })

local inv = frame({ Size = UDim2.fromOffset(230, 96), Position = UDim2.new(0, 12, 1, -108), Parent = gui })
corner(inv, 10)
stroke(inv)
local fuseLabel = text({ Size = UDim2.new(1, -16, 0, 22), Position = UDim2.fromOffset(10, 6), Text = "Fusibles : 0/3", TextXAlignment = Enum.TextXAlignment.Left, Parent = inv })
local keyLabel = text({ Size = UDim2.new(1, -16, 0, 22), Position = UDim2.fromOffset(10, 28), Text = "Clé maîtresse : —", TextXAlignment = Enum.TextXAlignment.Left, Parent = inv })
local function bar(y: number, color: Color3, label: string): (Frame, TextLabel)
	local back = frame({ Size = UDim2.new(1, -90, 0, 10), Position = UDim2.fromOffset(80, y + 5), BackgroundColor3 = Color3.fromRGB(30, 25, 28), BackgroundTransparency = 0, Parent = inv })
	corner(back, 5)
	local fill = frame({ Size = UDim2.fromScale(1, 1), BackgroundColor3 = color, BackgroundTransparency = 0, Parent = back })
	corner(fill, 5)
	local l = text({ Size = UDim2.fromOffset(70, 20), Position = UDim2.fromOffset(10, y), Text = label, TextSize = 14, TextXAlignment = Enum.TextXAlignment.Left, Parent = inv })
	return fill, l
end
local batteryFill, batteryText = bar(52, Color3.fromRGB(240, 220, 120), "Lampe")
local staminaFill = bar(72, Color3.fromRGB(130, 190, 255), "Souffle")

local help = text({
	Size = UDim2.fromOffset(460, 22), Position = UDim2.new(1, -470, 1, -32),
	Text = "F : lampe  •  Maj : courir (bruyant !)  •  E : interagir / se cacher",
	TextSize = 14, TextXAlignment = Enum.TextXAlignment.Right, TextColor3 = Color3.fromRGB(180, 170, 165), Parent = gui,
})

local function refreshInventory()
	local fuses = Remotes:GetAttribute("Fuses") or 0
	fuseLabel.Text = string.format("Fusibles : %d/3%s", fuses, if Remotes:GetAttribute("Power") then "  ⚡ courant rétabli" else "")
	keyLabel.Text = "Clé maîtresse : " .. (if Remotes:GetAttribute("Key") then "trouvée ✓" else "—")
end
Remotes.AttributeChanged:Connect(refreshInventory)
refreshInventory()
objective.Text = Remotes:GetAttribute("Objective") or ""

Remotes:WaitForChild("Objective").OnClientEvent:Connect(function(t: string)
	if not inRound() then
		return
	end
	objective.Text = t
	objective.TextColor3 = Color3.fromRGB(255, 220, 140)
	TweenService:Create(objective, TweenInfo.new(1.5), { TextColor3 = INK }):Play()
end)

local CAMP_HELP = "Entre dans le cercle rouge du camp pour participer à la prochaine nuit."
local function refreshMode()
	inv.Visible = inRound()
	if not inRound() then
		objective.Text = CAMP_HELP
	else
		objective.Text = Remotes:GetAttribute("Objective") or ""
	end
end
player:GetAttributeChangedSignal("InRound"):Connect(refreshMode)

Remotes:WaitForChild("Round").OnClientEvent:Connect(function(state: string, seconds: number, a: number?, b: number?)
	timerLabel.TextColor3 = Color3.fromRGB(220, 60, 60)
	if state == "camp" then
		if (a or 0) > 0 then
			timerLabel.Text = string.format("La nuit commence dans %d s  (%d/%d dans le cercle)", seconds, a or 0, b or 0)
		else
			timerLabel.Text = "LE CAMP"
		end
	elseif state == "jeu" then
		if inRound() then
			timerLabel.Text = string.format("%d:%02d", seconds // 60, seconds % 60)
			timerLabel.TextColor3 = if seconds < 60 then Color3.fromRGB(255, 40, 40) else Color3.fromRGB(220, 60, 60)
		else
			timerLabel.Text = string.format("Une nuit est en cours — %d:%02d", seconds // 60, seconds % 60)
			objective.Text = string.format("%d joueur%s encore dans le manoir. Attends la prochaine nuit au camp.", a or 0, if (a or 0) > 1 then "s" else "")
		end
	else
		timerLabel.Text = "Retour au camp…"
	end
end)
refreshMode()

---------------------------------------------------------------------------
-- NOTIFICATIONS
---------------------------------------------------------------------------

local notifs = frame({ Size = UDim2.new(0, 600, 0, 200), Position = UDim2.new(0.5, -300, 0, 84), BackgroundTransparency = 1, Parent = gui })
local layout = Instance.new("UIListLayout")
layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
layout.Padding = UDim.new(0, 4)
layout.Parent = notifs

Remotes:WaitForChild("Notify").OnClientEvent:Connect(function(msg: string, color: Color3?)
	local t = text({ Size = UDim2.new(1, 0, 0, 26), Text = msg, TextColor3 = color or INK, TextSize = 18, TextStrokeTransparency = 0.3, TextTransparency = 1, Parent = notifs })
	TweenService:Create(t, TweenInfo.new(0.3), { TextTransparency = 0 }):Play()
	task.delay(4.5, function()
		TweenService:Create(t, TweenInfo.new(0.6), { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
		task.wait(0.65)
		t:Destroy()
	end)
	local labels = {}
	for _, c in notifs:GetChildren() do
		if c:IsA("TextLabel") then
			table.insert(labels, c)
		end
	end
	if #labels > 5 then
		labels[1]:Destroy()
	end
end)

---------------------------------------------------------------------------
-- NOTES
---------------------------------------------------------------------------

local note = frame({ Size = UDim2.fromOffset(460, 340), Position = UDim2.new(0.5, -230, 0.5, -170), BackgroundColor3 = Color3.fromRGB(225, 212, 180), BackgroundTransparency = 0, Visible = false, ZIndex = 10, Parent = gui })
corner(note, 4)
stroke(note, Color3.fromRGB(90, 70, 50), 2)
local noteTitle = text({ Size = UDim2.new(1, -40, 0, 36), Position = UDim2.fromOffset(20, 16), Font = Enum.Font.SpecialElite, TextSize = 24, TextColor3 = Color3.fromRGB(60, 25, 20), ZIndex = 11, Parent = note })
local noteBody = text({ Size = UDim2.new(1, -40, 1, -110), Position = UDim2.fromOffset(20, 58), TextSize = 18, TextColor3 = Color3.fromRGB(40, 30, 25), TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top, ZIndex = 11, Parent = note })
local noteClose = button({ Size = UDim2.fromOffset(140, 34), Position = UDim2.new(0.5, -70, 1, -48), Text = "Fermer", ZIndex = 11, Parent = note })
noteClose.Activated:Connect(function()
	note.Visible = false
end)
Remotes:WaitForChild("Note").OnClientEvent:Connect(function(title: string, body: string)
	noteTitle.Text = title
	noteBody.Text = body
	note.Visible = true
end)

---------------------------------------------------------------------------
-- CLAVIER DU COFFRE-FORT
---------------------------------------------------------------------------

local KeypadRemote = Remotes:WaitForChild("Keypad") :: RemoteEvent
local keypad = frame({ Size = UDim2.fromOffset(260, 360), Position = UDim2.new(0.5, -130, 0.5, -180), BackgroundColor3 = Color3.fromRGB(35, 37, 42), BackgroundTransparency = 0, Visible = false, ZIndex = 10, Parent = gui })
corner(keypad, 10)
stroke(keypad, Color3.fromRGB(120, 120, 130), 2)
local display = text({ Size = UDim2.new(1, -30, 0, 50), Position = UDim2.fromOffset(15, 15), Text = "____", Font = Enum.Font.Code, TextSize = 36, TextColor3 = Color3.fromRGB(120, 255, 140), BackgroundTransparency = 0, BackgroundColor3 = Color3.fromRGB(10, 20, 12), ZIndex = 11, Parent = keypad })
corner(display, 6)
local entered = ""
local function refreshDisplay()
	display.Text = entered .. string.rep("_", 4 - #entered)
end
local keys = { "1", "2", "3", "4", "5", "6", "7", "8", "9", "✕", "0", "OK" }
for i, k in keys do
	local col, row = (i - 1) % 3, (i - 1) // 3
	local b = button({ Size = UDim2.fromOffset(70, 54), Position = UDim2.fromOffset(15 + col * 80, 80 + row * 62), Text = k, Font = Enum.Font.GothamBold, ZIndex = 11, Parent = keypad })
	b.Activated:Connect(function()
		playLocal("bip", 0.35, if k == "OK" then 0.8 else 1)
		if k == "✕" then
			entered = ""
		elseif k == "OK" then
			if #entered == 4 then
				KeypadRemote:FireServer(entered)
			end
			entered = ""
		elseif #entered < 4 then
			entered ..= k
		end
		refreshDisplay()
	end)
end
local keypadClose = button({ Size = UDim2.fromOffset(28, 28), Position = UDim2.new(1, -24, 0, -12), Text = "✕", TextSize = 16, ZIndex = 12, Parent = keypad })
keypadClose.Activated:Connect(function()
	keypad.Visible = false
end)
KeypadRemote.OnClientEvent:Connect(function(open: boolean)
	entered = ""
	refreshDisplay()
	keypad.Visible = open
end)

---------------------------------------------------------------------------
-- JUMPSCARE ET FIN DE MANCHE
---------------------------------------------------------------------------

local scare = frame({ Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 0, Visible = false, ZIndex = 50, Parent = gui })
local scareGlow = frame({ Size = UDim2.fromScale(1, 1), BackgroundColor3 = BLOOD, BackgroundTransparency = 0.5, ZIndex = 50, Parent = scare })
local glowGrad = Instance.new("UIGradient")
glowGrad.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.5, 1), NumberSequenceKeypoint.new(1, 0) })
glowGrad.Parent = scareGlow
-- Crâne de Wendigo (dessiné sur une toile de 600 x 1000, agrandie par UIScale)
local face = frame({ AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(600, 1000), BackgroundTransparency = 1, ZIndex = 51, Parent = scare })
local faceScale = Instance.new("UIScale")
faceScale.Parent = face
local BONE_UI = Color3.fromRGB(205, 192, 168)
local function seg(x1: number, y1: number, x2: number, y2: number, thick: number, color: Color3, z: number?)
	local dx, dy = x2 - x1, y2 - y1
	frame({
		AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset((x1 + x2) / 2, (y1 + y2) / 2),
		Size = UDim2.fromOffset(thick, math.sqrt(dx * dx + dy * dy) + thick * 0.5), Rotation = math.deg(math.atan2(-dx, dy)),
		BackgroundColor3 = color, BackgroundTransparency = 0, ZIndex = z or 52, Parent = face,
	})
end
local function blob(x: number, y: number, w: number, h: number, color: Color3, z: number, round: number?): Frame
	local f = frame({ Position = UDim2.fromOffset(x, y), Size = UDim2.fromOffset(w, h), BackgroundColor3 = color, BackgroundTransparency = 0, ZIndex = z, Parent = face })
	corner(f, round or 200)
	return f
end
-- Bois ramifiés (gauche puis miroir)
local antlerColor = Color3.fromRGB(110, 92, 70)
local beams = {
	{ 215, 330, 160, 250, 26 }, { 160, 250, 115, 165, 22 }, { 115, 165, 70, 95, 18 }, { 70, 95, 35, 20, 13 },
	{ 160, 250, 205, 165, 14 }, { 205, 165, 225, 110, 10 }, { 115, 165, 160, 85, 12 }, { 160, 85, 170, 35, 9 },
	{ 70, 95, 95, 25, 10 }, { 140, 205, 55, 200, 12 }, { 55, 200, 15, 160, 9 },
}
for _, b in beams do
	seg(b[1], b[2], b[3], b[4], b[5], antlerColor, 51)
	seg(600 - b[1], b[2], 600 - b[3], b[4], b[5], antlerColor, 51)
end
-- Crâne et long museau
local cranium = blob(165, 290, 270, 250, BONE_UI, 52, 120)
local shade = Instance.new("UIGradient")
shade.Color = ColorSequence.new({ ColorSequenceKeypoint.new(0, Color3.fromRGB(235, 225, 205)), ColorSequenceKeypoint.new(1, Color3.fromRGB(120, 108, 92)) })
shade.Rotation = 90
shade.Parent = cranium
local snout = blob(215, 480, 170, 440, BONE_UI, 52, 70)
local shade2 = shade:Clone()
shade2.Parent = snout
-- Orbites et yeux rouges
local scareEyes = {}
for _, x in { 185, 325 } do
	blob(x, 385, 90, 75, Color3.new(0, 0, 0), 53, 60)
	local iris = blob(x + 30, 405, 30, 30, Color3.fromRGB(255, 30, 20), 54, 20)
	table.insert(scareEyes, iris)
end
-- Narines, fissures, crocs
blob(270, 840, 22, 34, Color3.new(0, 0, 0), 53, 12)
blob(308, 840, 22, 34, Color3.new(0, 0, 0), 53, 12)
seg(300, 300, 280, 380, 4, Color3.fromRGB(60, 50, 40), 53)
seg(280, 380, 300, 470, 3, Color3.fromRGB(60, 50, 40), 53)
seg(390, 330, 420, 420, 3, Color3.fromRGB(60, 50, 40), 53)
for i = 0, 7 do
	local y = 560 + i * 42
	seg(222, y, 200, y + 34, 9, Color3.fromRGB(240, 232, 210), 51)
	seg(378, y, 400, y + 34, 9, Color3.fromRGB(240, 232, 210), 51)
end
-- Lueur rouge de la gueule
local maw = blob(240, 520, 120, 300, Color3.fromRGB(90, 0, 0), 51, 60)
maw.BackgroundTransparency = 0.2

-- Effets de post-traitement locaux (n'affectent que ce joueur)
local Lighting = game:GetService("Lighting")
local fearCC = Instance.new("ColorCorrectionEffect")
fearCC.Name = "PeurLocale"
fearCC.Parent = Lighting
local fearBlur = Instance.new("BlurEffect")
fearBlur.Name = "FlouLocal"
fearBlur.Size = 0
fearBlur.Parent = Lighting
local shakeAmount = 0
local fovKick = 0

Remotes:WaitForChild("Jumpscare").OnClientEvent:Connect(function()
	scare.Visible = true
	local viewH = workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize.Y or 800
	faceScale.Scale = viewH / 1000 * 0.15
	face.Visible = true
	playLocal("jumpscare", 2.2)
	fearBlur.Size = 18
	fearCC.TintColor = Color3.fromRGB(255, 120, 120)
	TweenService:Create(faceScale, TweenInfo.new(0.16, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Scale = viewH / 1000 * 1.6 }):Play()
	shakeAmount = 1
	for i = 1, 18 do
		face.Rotation = math.random(-7, 7)
		scare.BackgroundColor3 = if i % 2 == 0 then Color3.new(0, 0, 0) else Color3.fromRGB(90, 0, 0)
		for _, e in scareEyes do
			e.BackgroundColor3 = if math.random() < 0.5 then Color3.fromRGB(255, 30, 20) else Color3.fromRGB(255, 220, 200)
		end
		task.wait(0.045)
	end
	TweenService:Create(scare, TweenInfo.new(0.8), { BackgroundTransparency = 0 }):Play()
	task.wait(0.5)
	face.Visible = false
	task.wait(0.6)
	scare.Visible = false
	fearCC.TintColor = Color3.new(1, 1, 1)
end)

-- Hurlement : le Veilleur t'a repéré
local alert = text({ Size = UDim2.new(1, 0, 0, 120), Position = UDim2.fromScale(0, 0.38), Text = "IL T'A VU", Font = Enum.Font.Creepster, TextSize = 96, TextColor3 = BLOOD, TextStrokeTransparency = 0.2, TextTransparency = 1, ZIndex = 30, Parent = gui })
Remotes:WaitForChild("Screech").OnClientEvent:Connect(function()
	shakeAmount = math.max(shakeAmount, 0.8)
	fovKick = 14
	fearBlur.Size = 10
	alert.TextTransparency = 0
	alert.TextSize = 70
	TweenService:Create(alert, TweenInfo.new(0.4, Enum.EasingStyle.Back), { TextSize = 104 }):Play()
	task.delay(0.9, function()
		TweenService:Create(alert, TweenInfo.new(0.8), { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
	end)
end)

-- Éclairs de l'orage
Remotes:WaitForChild("Lightning").OnClientEvent:Connect(function()
	local amb, out = Lighting.Ambient, Lighting.OutdoorAmbient
	for _ = 1, math.random(1, 3) do
		Lighting.Ambient = Color3.fromRGB(150, 160, 200)
		Lighting.OutdoorAmbient = Color3.fromRGB(200, 210, 255)
		fearCC.Brightness = 0.35
		task.wait(0.06 + math.random() * 0.05)
		Lighting.Ambient = amb
		Lighting.OutdoorAmbient = out
		fearCC.Brightness = 0
		task.wait(0.08 + math.random() * 0.12)
	end
	-- Le tonnerre gronde un peu plus tard
	task.wait(0.8 + math.random())
	playLocal("tonnerre", 0.9, 0.85 + math.random() * 0.3)
	shakeAmount = math.max(shakeAmount, 0.35)
end)

local endScreen = frame({ Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 0.3, Visible = false, ZIndex = 40, Parent = gui })
local endTitle = text({ Size = UDim2.new(1, 0, 0, 90), Position = UDim2.fromScale(0, 0.3), Font = Enum.Font.Creepster, TextSize = 80, ZIndex = 41, Parent = endScreen })
local endText = text({ Size = UDim2.new(0.8, 0, 0, 60), Position = UDim2.fromScale(0.1, 0.45), TextSize = 24, ZIndex = 41, Parent = endScreen })
Remotes:WaitForChild("End").OnClientEvent:Connect(function(win: boolean, msg: string)
	endTitle.Text = if win then "ÉCHAPPÉ !" else "PRIS AU PIÈGE…"
	if win then
		playLocal("victoire", 1)
	end
	endTitle.TextColor3 = if win then Color3.fromRGB(140, 255, 160) else BLOOD
	endText.Text = msg
	endScreen.Visible = true
	endScreen.BackgroundTransparency = 1
	TweenService:Create(endScreen, TweenInfo.new(1), { BackgroundTransparency = 0.3 }):Play()
	task.delay(6, function()
		endScreen.Visible = false
	end)
end)

---------------------------------------------------------------------------
-- COMMANDES : LAMPE ET COURSE
---------------------------------------------------------------------------

local LampRemote = Remotes:WaitForChild("Lamp") :: RemoteEvent
local function toggleLamp(_: string, state: Enum.UserInputState)
	if state == Enum.UserInputState.Begin then
		LampRemote:FireServer()
	end
	return Enum.ContextActionResult.Sink
end
ContextActionService:BindAction("ManoirLampe", toggleLamp, true, Enum.KeyCode.F, Enum.KeyCode.ButtonY)
ContextActionService:SetTitle("ManoirLampe", "Lampe")

local sprinting = false
local function sprintAction(_: string, state: Enum.UserInputState)
	sprinting = state == Enum.UserInputState.Begin
	return Enum.ContextActionResult.Pass
end
ContextActionService:BindAction("ManoirCourse", sprintAction, true, Enum.KeyCode.LeftShift, Enum.KeyCode.ButtonL3)
ContextActionService:SetTitle("ManoirCourse", "Courir")

local stamina = 1

---------------------------------------------------------------------------
-- BOUCLE : peur, course, batterie
---------------------------------------------------------------------------

-- Rayures de vieux film
local scratches = {}
for _ = 1, 3 do
	table.insert(scratches, frame({ Size = UDim2.new(0, 1, 1, 0), BackgroundColor3 = Color3.fromRGB(220, 210, 190), BackgroundTransparency = 1, ZIndex = 3, Parent = gui }))
end

-- Bougies et yeux des portraits (effets purement locaux)
local candleLights: { PointLight } = {}
local portraitEyes: { BasePart } = {}
local function scanManor()
	table.clear(candleLights)
	table.clear(portraitEyes)
	local manor = workspace:FindFirstChild("Manoir")
	if not manor then
		return
	end
	for _, d in manor:GetDescendants() do
		if d:IsA("PointLight") and d:GetAttribute("Bougie") then
			table.insert(candleLights, d)
		elseif d:IsA("BasePart") and d.Name == "OeilTableau" then
			table.insert(portraitEyes, d)
		end
	end
end
task.spawn(function()
	while true do
		scanManor()
		task.wait(4)
	end
end)

local heartT = 0
local bobT = 0
local lastEyes = false
RunService.RenderStepped:Connect(function(dt)
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	local hrp = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	local hidden = player:GetAttribute("Hidden") == true
	local running = false

	-- Course et souffle
	if hum and not hidden and hum.Health > 0 then
		local moving = hum.MoveDirection.Magnitude > 0.1
		running = sprinting and moving and stamina > 0.02
		local walk = player:GetAttribute("WalkSpeed") or 12
		local sprint = player:GetAttribute("SprintSpeed") or 19
		hum.WalkSpeed = if running then sprint else walk
		if running then
			stamina = math.max(0, stamina - dt / 5)
		else
			stamina = math.min(1, stamina + dt / (if moving then 9 else 5))
		end
		if moving then
			bobT += dt * (if running then 14 else 9)
		end
	end
	staminaFill.Size = UDim2.fromScale(stamina, 1)

	-- Batterie (la lampe vacille quand elle est presque vide)
	local battery = player:GetAttribute("Battery") or 0
	batteryFill.Size = UDim2.fromScale(battery / 100, 1)
	batteryText.Text = if player:GetAttribute("Lamp") then "Lampe ●" else "Lampe"
	batteryFill.BackgroundColor3 = if battery < 20 then Color3.fromRGB(230, 80, 60) else Color3.fromRGB(240, 220, 120)
	local head = char and char:FindFirstChild("Head")
	local spot = head and head:FindFirstChild("Lampe") :: SpotLight?
	if spot and spot.Enabled then
		spot.Brightness = if battery < 20 and math.random() < 0.12 then 0.4 else 3.2
	end

	-- Cachette
	hideView.Visible = hidden
	hideView.BackgroundTransparency = if hidden then 0.15 else 1

	-- Peur : distance au Veilleur
	local intensity = 0
	local manor = workspace:FindFirstChild("Manoir")
	local monster = manor and manor:FindFirstChild("LeVeilleur") :: Model?
	local monsterDist = math.huge
	if monster and monster.PrimaryPart and hrp then
		monsterDist = (monster.PrimaryPart.Position - hrp.Position).Magnitude
		intensity = math.clamp(1 - (monsterDist - 8) / 50, 0, 1)
		if Remotes:GetAttribute("MonsterState") == "chasse" then
			intensity = math.max(intensity, 0.35)
		end
	end
	local prevCycle = math.floor(heartT)
	heartT += dt * (1.2 + intensity * 2.5)
	local beat = (math.max(0, math.sin(heartT * math.pi * 2)) ^ 6)
	if math.floor(heartT) ~= prevCycle and intensity > 0.18 then
		playLocal("coeur", 0.25 + intensity * 0.9, 1 + intensity * 0.2)
	end

	-- Ambiance sonore : manoir ou camp, souffle quand on est essoufflé ou caché près de lui
	local playing = inRound()
	fadeLoop("ambiance", if playing then 0.5 else 0, dt)
	fadeLoop("lobby", if playing then 0 else 0.4, dt)
	fadeLoop("pluie", if hidden then 0.06 elseif playing then 0.18 else 0.22, dt)
	fadeLoop("respiration", math.clamp((0.6 - stamina) * 0.9 + (if hidden then intensity * 0.6 else 0), 0, 0.7), dt)
	local reverb = if hidden then Enum.ReverbType.PaddedCell elseif playing then Enum.ReverbType.StoneCorridor else Enum.ReverbType.Forest
	if SoundService.AmbientReverb ~= reverb then
		SoundService.AmbientReverb = reverb
	end
	fear.BackgroundTransparency = 1 - intensity * (0.35 + beat * 0.35)

	-- Image : désaturée, contrastée et floue quand il est proche
	fearCC.Saturation = -0.25 - intensity * 0.6
	fearCC.Contrast = 0.1 + intensity * 0.35 + beat * intensity * 0.15
	if not scare.Visible then
		fearCC.TintColor = Color3.new(1, 1 - intensity * 0.25, 1 - intensity * 0.3)
		local targetBlur = intensity * 3 + beat * intensity * 2
		fearBlur.Size += (targetBlur - fearBlur.Size) * math.min(1, dt * 6)
	end

	-- Caméra : balancement de la marche, champ de vision, tremblements
	local cam = workspace.CurrentCamera
	if cam then
		fovKick = math.max(0, fovKick - dt * 20)
		local targetFov = 70 + (if running then 8 else 0) + intensity * 6 + fovKick
		cam.FieldOfView += (targetFov - cam.FieldOfView) * math.min(1, dt * 5)
		if not hidden and hum and hum.MoveDirection.Magnitude > 0.1 then
			local amp = if running then 0.018 else 0.009
			cam.CFrame *= CFrame.Angles(math.sin(bobT * 2) * amp * 0.5, 0, math.sin(bobT) * amp)
		end
		shakeAmount = math.max(0, shakeAmount - dt * 1.5)
		local shake = shakeAmount * 0.04 + (if intensity > 0.5 and not hidden then (intensity - 0.5) * 0.012 else 0)
		if shake > 0 then
			cam.CFrame *= CFrame.Angles((math.random() - 0.5) * shake, (math.random() - 0.5) * shake, (math.random() - 0.5) * shake * 0.5)
		end
	end

	-- Bougies qui vacillent
	local t = os.clock()
	for i, l in candleLights do
		l.Brightness = 0.75 + math.sin(t * 9 + i * 1.7) * 0.12 + math.sin(t * 23 + i) * 0.08 + (if math.random() < 0.01 then -0.4 else 0)
	end

	-- Les yeux des portraits s'allument quand il rôde près de toi
	local eyesOn = monsterDist < 38
	if eyesOn ~= lastEyes then
		lastEyes = eyesOn
		for _, e in portraitEyes do
			e.Color = if eyesOn then Color3.fromRGB(255, 30, 20) else Color3.fromRGB(20, 15, 15)
		end
	end

	-- Rayures de film
	for _, sc in scratches do
		if math.random() < 0.04 then
			sc.Position = UDim2.fromScale(math.random(), 0)
			sc.BackgroundTransparency = 0.75 + math.random() * 0.2
		else
			sc.BackgroundTransparency = math.min(1, sc.BackgroundTransparency + dt * 6)
		end
	end
end)

if UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled then
	help.Text = "Boutons Lampe / Courir à droite • Bouton d'action pour interagir"
end
