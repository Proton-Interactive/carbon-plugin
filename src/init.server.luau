local HttpService = game:GetService("HttpService")
local Selection = game:GetService("Selection")

local PORT = 8000
local HOST = "http://192.168.68.64:" .. tostring(PORT)

local toolbar = plugin:CreateToolbar("Carbon")
local connectButton = toolbar:CreateButton("Connect", "Connect to Carbon Core", "")

local isConnected = false

local function request(method, path, body)
	local success, response = pcall(function()
		return HttpService:RequestAsync({
			Url = HOST .. path,
			Method = method,
			Headers = {
				["Content-Type"] = "application/json",
			},
			Body = body and HttpService:JSONEncode(body) or nil,
		})
	end)

	if not success then
		return false, response
	end

	if response.Success then
		local decodeSuccess, data = pcall(function()
			return HttpService:JSONDecode(response.Body)
		end)
		return decodeSuccess, data
	else
		return false, response.StatusMessage
	end
end

local function getExtension(script)
	if script:IsA("ModuleScript") then
		return ".luau"
	elseif script:IsA("LocalScript") then
		return ".client.luau"
	elseif script:IsA("Script") then
		return ".server.luau"
	end
	return ".luau"
end

local function collectScripts(parent, pathPrefix, files)
	for _, child in ipairs(parent:GetChildren()) do
		if child:IsA("Script") or child:IsA("LocalScript") or child:IsA("ModuleScript") then
			local fileName = child.Name .. getExtension(child)
			local fullPath = pathPrefix .. "/" .. fileName
			table.insert(files, {
				path = fullPath,
				content = child.Source,
			})
		elseif child:IsA("Folder") then
			collectScripts(child, pathPrefix .. "/" .. child.Name, files)
		end
	end
end

local function sendScriptsToDisk()
	local files = {}

	local services = {
		{ Service = game:GetService("ServerScriptService"), Path = "game/ServerScriptService" },
		{ Service = game:GetService("ReplicatedStorage"), Path = "game/ReplicatedStorage" },
		{
			Service = game:GetService("StarterPlayer").StarterPlayerScripts,
			Path = "game/StarterPlayer/StarterPlayerScripts",
		},
	}

	for _, entry in ipairs(services) do
		if entry.Service then
			collectScripts(entry.Service, entry.Path, files)
		end
	end

	if #files > 0 then
		print("[Carbon] Sending " .. #files .. " scripts to disk...")
		local success, response = request("POST", "/sync/update", { files = files })
		if not success then
			warn("[Carbon] Failed to send scripts: " .. tostring(response))
		end
	else
		warn("[Carbon] No scripts found to sync.")
	end
end

local function sync()
	-- This function polls the server for pending commands (Import/Export triggered from CLI/Zed)
	local success, data = request("GET", "/poll")
	if success and data then
		if data.command == "import" then
			print("[Carbon] Importing scripts from Roblox to Disk...")
			sendScriptsToDisk()
		elseif data.command == "export" then
			print("[Carbon] Exporting scripts from Disk to Roblox...")
			-- TODO: Implement logic to read scripts from server and apply to Roblox
		end
	end
end

local function startPolling()
	isConnected = true
	connectButton:SetActive(true)
	print("[Carbon] Connected to Carbon Core")

	task.spawn(function()
		while isConnected do
			sync()
			task.wait(1)
		end
	end)
end

connectButton.Click:Connect(function()
	if isConnected then
		isConnected = false
		connectButton:SetActive(false)
		print("[Carbon] Disconnected")
	else
		local success, err = request("GET", "/")
		if success then
			startPolling()
		else
			warn("[Carbon] Could not connect to Carbon Core: " .. tostring(err))
			warn("Make sure 'Http Requests' are enabled in Game Settings and the server is running on port " .. PORT)
		end
	end
end)
