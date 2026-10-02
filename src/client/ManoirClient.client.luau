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
	objective.Text = t
	objective.TextColor3 = Color3.fromRGB(255, 220, 140)
	TweenService:Create(objective, TweenInfo.new(1.5), { TextColor3 = INK }):Play()
end)

Remotes:WaitForChild("Round").OnClientEvent:Connect(function(state: string, seconds: number)
	if state == "jeu" then
		timerLabel.Text = string.format("%d:%02d", seconds // 60, seconds % 60)
		timerLabel.TextColor3 = if seconds < 60 then Color3.fromRGB(255, 40, 40) else Color3.fromRGB(220, 60, 60)
	else
		timerLabel.Text = "Nouvelle nuit dans " .. seconds .. " s"
	end
end)

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
local face = frame({ Size = UDim2.fromScale(0.5, 0.75), Position = UDim2.fromScale(0.25, 0.12), BackgroundColor3 = Color3.fromRGB(215, 210, 205), BackgroundTransparency = 0, ZIndex = 51, Parent = scare })
corner(face, 200)
for _, x in { 0.22, 0.58 } do
	local eye = frame({ Size = UDim2.fromScale(0.2, 0.16), Position = UDim2.fromScale(x, 0.3), BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 0, ZIndex = 52, Parent = face })
	corner(eye, 100)
	local pupil = frame({ Size = UDim2.fromScale(0.3, 0.3), Position = UDim2.fromScale(0.35, 0.35), BackgroundColor3 = Color3.new(1, 1, 1), BackgroundTransparency = 0, ZIndex = 53, Parent = eye })
	corner(pupil, 100)
end
local mouth = frame({ Size = UDim2.fromScale(0.5, 0.25), Position = UDim2.fromScale(0.25, 0.62), BackgroundColor3 = Color3.fromRGB(40, 0, 0), BackgroundTransparency = 0, ZIndex = 52, Parent = face })
corner(mouth, 60)
for i = 0, 6 do
	frame({ Size = UDim2.fromScale(0.06, 0.35), Position = UDim2.fromScale(0.07 + i * 0.13, 0), BackgroundColor3 = Color3.fromRGB(230, 225, 210), BackgroundTransparency = 0, ZIndex = 53, Parent = mouth })
end

Remotes:WaitForChild("Jumpscare").OnClientEvent:Connect(function()
	scare.Visible = true
	face.Size = UDim2.fromScale(0.2, 0.3)
	face.Position = UDim2.fromScale(0.4, 0.35)
	TweenService:Create(face, TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Size = UDim2.fromScale(0.9, 1.3), Position = UDim2.fromScale(0.05, -0.15) }):Play()
	local cam = workspace.CurrentCamera
	for _ = 1, 14 do
		face.Rotation = math.random(-6, 6)
		scare.BackgroundColor3 = if math.random() < 0.5 then Color3.new(0, 0, 0) else BLOOD
		if cam then
			cam.CFrame *= CFrame.Angles(math.rad(math.random(-3, 3)), math.rad(math.random(-3, 3)), 0)
		end
		task.wait(0.05)
	end
	task.wait(0.6)
	scare.Visible = false
	scare.BackgroundColor3 = Color3.new(0, 0, 0)
end)

local endScreen = frame({ Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 0.3, Visible = false, ZIndex = 40, Parent = gui })
local endTitle = text({ Size = UDim2.new(1, 0, 0, 90), Position = UDim2.fromScale(0, 0.3), Font = Enum.Font.Creepster, TextSize = 80, ZIndex = 41, Parent = endScreen })
local endText = text({ Size = UDim2.new(0.8, 0, 0, 60), Position = UDim2.fromScale(0.1, 0.45), TextSize = 24, ZIndex = 41, Parent = endScreen })
Remotes:WaitForChild("End").OnClientEvent:Connect(function(win: boolean, msg: string)
	endTitle.Text = if win then "ÉCHAPPÉ !" else "PRIS AU PIÈGE…"
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

local heartT = 0
RunService.RenderStepped:Connect(function(dt)
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	local hrp = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	local hidden = player:GetAttribute("Hidden") == true

	-- Course et souffle
	if hum and not hidden and hum.Health > 0 then
		local moving = hum.MoveDirection.Magnitude > 0.1
		local run = sprinting and moving and stamina > 0.02
		local walk = player:GetAttribute("WalkSpeed") or 12
		local sprint = player:GetAttribute("SprintSpeed") or 19
		hum.WalkSpeed = if run then sprint else walk
		if run then
			stamina = math.max(0, stamina - dt / 5)
		else
			stamina = math.min(1, stamina + dt / (if moving then 9 else 5))
		end
	end
	staminaFill.Size = UDim2.fromScale(stamina, 1)

	-- Batterie
	local battery = player:GetAttribute("Battery") or 0
	batteryFill.Size = UDim2.fromScale(battery / 100, 1)
	batteryText.Text = if player:GetAttribute("Lamp") then "Lampe ●" else "Lampe"
	batteryFill.BackgroundColor3 = if battery < 20 then Color3.fromRGB(230, 80, 60) else Color3.fromRGB(240, 220, 120)

	-- Cachette
	hideView.Visible = hidden
	hideView.BackgroundTransparency = if hidden then 0.15 else 1

	-- Peur : distance au Veilleur
	local intensity = 0
	local manor = workspace:FindFirstChild("Manoir")
	local monster = manor and manor:FindFirstChild("LeVeilleur") :: Model?
	if monster and monster.PrimaryPart and hrp then
		local d = (monster.PrimaryPart.Position - hrp.Position).Magnitude
		intensity = math.clamp(1 - (d - 8) / 50, 0, 1)
		if Remotes:GetAttribute("MonsterState") == "chasse" then
			intensity = math.max(intensity, 0.35)
		end
	end
	heartT += dt * (1.2 + intensity * 2.5)
	local beat = (math.max(0, math.sin(heartT * math.pi * 2)) ^ 6)
	fear.BackgroundTransparency = 1 - intensity * (0.35 + beat * 0.35)
	local cam = workspace.CurrentCamera
	if cam and intensity > 0.5 and not hidden then
		local s = (intensity - 0.5) * 0.012
		cam.CFrame *= CFrame.Angles((math.random() - 0.5) * s, (math.random() - 0.5) * s, 0)
	end
end)

if UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled then
	help.Text = "Boutons Lampe / Courir à droite • Bouton d'action pour interagir"
end
