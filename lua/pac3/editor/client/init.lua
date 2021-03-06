include("autorun/pac_core_init.lua")

pace = pace or {}
pace.net = include("pac3/libraries/netx.lua")
pace.luadata = include("pac3/libraries/luadata.lua")

include("language.lua")
include("icons.lua")

include("util.lua")
include("wear.lua")

include("select.lua")
include("view.lua")
include("parts.lua")
include("saved_parts.lua")
include("logic.lua")
include("undo.lua")
include("fonts.lua")
include("basic_mode.lua")
include("settings.lua")
include("shortcuts.lua")
include("asset_browser.lua")
include("menu_bar.lua")

include("mctrl.lua")
include("screenvec.lua")

include("panels.lua")
include("tools.lua")
include("spawnmenu.lua")
include("wiki.lua")
include("examples.lua")
include("about.lua")
include("animation_timeline.lua")
include("render_scores.lua")


do
	local hue =
	{
		"red",
		"orange",
		"yellow",
		"green",
		"turquoise",
		"blue",
		"purple",
		"magenta",
	}

	local sat =
	{
		"pale",
		"",
		"strong",
	}

	local val =
	{
		"dark",
		"",
		"bright"
	}

	function pace.HSVToNames(h,s,v)
		return
			hue[math.Round((1+(h/360)*#hue))] or hue[1],
			sat[math.ceil(s*#sat)] or sat[1],
			val[math.ceil(v*#val)] or val[1]
	end

	function pace.ColorToNames(c)
		if c.r == 255 and c.g == 255 and c.b == 255 then return "white", "", "bright" end
		if c.r == 0 and c.g == 0 and c.b == 0 then return "black", "", "bright" end
		return pace.HSVToNames(ColorToHSV(Color(c.r, c.g, c.b)))
	end

end

function pace.CallHook(str, ...)
	return hook.Call("pace_" .. str, GAMEMODE, ...)
end

pace.ActivePanels = pace.ActivePanels or {}
pace.Editor = NULL

function pace.OpenEditor()
	pace.CloseEditor()

	if hook.Run("PrePACEditorOpen", LocalPlayer()) == false then return end

	pac.Enable()

	pace.RefreshFiles()

	pace.SetLanguage()

	local editor = pace.CreatePanel("editor")
		editor:SetSize(240, ScrH())
		editor:MakePopup()
		editor.Close = function()
			editor:OnRemove()
			pace.CloseEditor()
		end
	pace.Editor = editor
	pace.Active = true

	if ctp and ctp.Disable then
		ctp:Disable()
	end

	RunConsoleCommand("pac_in_editor", "1")
	pace.SetInPAC3Editor(true)

	pace.DisableExternalHooks()

	pace.Call("OpenEditor")
end

function pace.CloseEditor()
	pace.RestoreExternalHooks()

	if pace.Editor:IsValid() then
		pace.Editor:OnRemove()
		pace.Editor:Remove()
		pace.Active = false
		pace.Call("CloseEditor")

		if pace.timeline.IsActive() then
			pace.timeline.Close()
		end
	end

	RunConsoleCommand("pac_in_editor", "0")
	pace.SetInPAC3Editor(false)
end

pac.AddHook("pac_Disable", "pac_editor_disable", function()
	pace.CloseEditor()
end)

function pace.RefreshFiles()
	pace.CachedFiles = nil

	if pace.Editor:IsValid() then
		pace.Editor:MakeBar()
	end

	if pace.SpawnlistBrowser:IsValid() then
		pace.SpawnlistBrowser:PopulateFromClient()
	end
end


function pace.Panic()
	pace.CloseEditor()
	for key, pnl in pairs(pace.ActivePanels) do
		if pnl:IsValid() then
			pnl:Remove()
			table.remove(pace.ActivePanels, key)
		end
	end
end

do -- forcing hooks
	pace.ExternalHooks =
	{
		"CalcView",
		"ShouldDrawLocalPlayer",
	}

	function pace.DisableExternalHooks()
		for _, event in pairs(pace.ExternalHooks) do
			local hooks = hook.GetTable()[event]

			if hooks then
				pace.OldHooks = pace.OldHooks or {}
				pace.OldHooks[event] = pace.OldHooks[event] or {}
				pace.OldHooks[event] = table.Copy(hooks)

				for name in pairs(hooks) do
					if type(name) == "string" and name:sub(1, 4) ~= "pace_" then
						hook.Remove(event, name)
					end
				end
			end
		end
	end

	function pace.RestoreExternalHooks()
		if pace.OldHooks then
			for event, hooks in pairs(pace.OldHooks) do
				for name, func in pairs(hooks) do
					if type(name) == "string" and name:sub(1, 4) ~= "pace_" then
						hook.Add(event, name, func)
					end
				end
			end
		end

		pace.OldHooks = nil
	end
end

function pace.IsActive()
	return pace.Active == true
end

concommand.Add("pac_editor_panic", function()
	pace.Panic()
	timer.Simple(0.1, function() pace.OpenEditor() end)
end)

concommand.Add("pac_editor", function(_, _, args)
	if args[1] == "toggle" then
		if pace.IsActive() then
			pace.CloseEditor()
		else
			pace.OpenEditor()
		end
	else
		pace.OpenEditor()
	end
end)

concommand.Add("pac_reset_eye_angles", function() pace.ResetEyeAngles() end)
concommand.Add("pac_toggle_tpose", function() pace.SetTPose(not pace.GetTPose()) end)

function pace.Call(str, ...)
	if pace["On" .. str] then
		if hook.Run("pace_On" .. str, ...) ~= false then
			return pace["On" .. str](...)
		end
	else
		ErrorNoHalt("missing function pace.On" .. str .. "!\n")
	end
end

do
	function pace.SetInPAC3Editor(b)
		net.Start("pac_in_editor")
		net.WriteBit(b)
		net.SendToServer()
	end

	local up = Vector(0,0,10000)

	hook.Add("HUDPaint", "pac_in_editor", function()
		for _, ply in ipairs(player.GetAll()) do
			if ply ~= LocalPlayer() and ply:GetNW2Bool("pac_in_editor") then

				if ply.pac_editor_cam_pos then
					if not IsValid(ply.pac_editor_camera) then
						ply.pac_editor_camera = ClientsideModel("models/tools/camera/camera.mdl")
						ply.pac_editor_camera:SetModelScale(0.25,0)
						local ent = ply.pac_editor_camera
						ply:CallOnRemove("pac_editor_camera", function()
							SafeRemoveEntity(ent)
						end)
					end

					local ent = ply.pac_editor_camera

					local dt = math.Clamp(FrameTime() * 5, 0.0001, 0.5)

					ent:SetPos(LerpVector(dt, ent:GetPos(), ply.pac_editor_cam_pos))
					ent:SetAngles(LerpAngle(dt, ent:GetAngles(), ply.pac_editor_cam_ang))

					local pos_3d = ent:GetPos()
					local dist = pos_3d:Distance(EyePos())

					if dist > 10 then
						local pos_2d = pos_3d:ToScreen()
						if pos_2d.visible then
							local alpha = math.Clamp(pos_3d:Distance(EyePos()) * -1 + 500, 0, 500)/500
							if alpha > 0 then
								draw.DrawText(ply:Nick() .. "'s PAC3 camera", "ChatFont", pos_2d.x, pos_2d.y, Color(255,255,255,alpha*255), 1)

								if not ply.pac_editor_part_pos:IsZero() then
									surface.SetDrawColor(255, 255, 255, alpha*100)
									local endpos = ply.pac_editor_part_pos:ToScreen()
									if endpos.visible then
										surface.DrawLine(pos_2d.x, pos_2d.y, endpos.x, endpos.y)
									end
								end
							end
						end
					end
				end

				local pos_3d = ply:NearestPoint(ply:EyePos() + up) + Vector(0,0,5)
				local alpha = math.Clamp(pos_3d:Distance(EyePos()) * -1 + 500, 0, 500)/500
				if alpha > 0 then
					local pos_2d = pos_3d:ToScreen()
					draw.DrawText("In PAC3 Editor", "ChatFont", pos_2d.x, pos_2d.y, Color(255,255,255,alpha*255), 1)
				end
			else
				if ply.pac_editor_camera then
					SafeRemoveEntity(ply.pac_editor_camera)
					ply.pac_editor_camera = nil
				end
			end
		end
	end)

	timer.Create("pac_in_editor", 0.25, 0, function()
		if not pace.current_part:IsValid() then return end

		net.Start("pac_in_editor_posang", true)
			net.WriteVector(pace.GetViewPos())
			net.WriteAngle(pace.GetViewAngles())
			net.WriteVector((pace.mctrl.GetTargetPos()) or pace.current_part:GetDrawPosition() or vector_origin)
		net.SendToServer()
	end)

	net.Receive("pac_in_editor_posang", function()
		local ply = net.ReadEntity()
		if not ply:IsValid() then return end

		local pos = net.ReadVector()
		local ang = net.ReadAngle()
		local part_pos = net.ReadVector()

		ply.pac_editor_cam_pos = pos
		ply.pac_editor_cam_ang = ang
		ply.pac_editor_part_pos = part_pos
	end)
end

pace.RegisterPanels()
