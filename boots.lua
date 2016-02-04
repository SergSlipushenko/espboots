local M = {}

function M.connectToAP(file_creds, fallback)
    if fallback == nil then M._fallback = true else M._fallback = fallback end
    local _file_creds = file_creds or 'wifi_creds'
    if not file.list()[_file_creds] then 
	M.onConnectFailure()
        return
    end
    file.open(_file_creds)
    wifi.setmode(wifi.STATION)
    local wifi_name = (file.readline() or ''):sub(1,-2)
    local wifi_pwd = (file.readline() or ''):sub(1,-2)
    wifi.sta.config(wifi_name,wifi_pwd)
    local wifi_ip = (file.readline() or ''):sub(1,-2)
    local wifi_nm = (file.readline() or '255.255.255.0\n'):sub(1,-2)
    local wifi_gw = (file.readline() or '192.168.0.1\n'):sub(1,-2)
    file.close()
    if wifi_ip ~= '' then
        wifi.sta.setip({ip=wifi_ip,netmask=wifi_nm, gateway=wifi_gw})
    end
    wifi.sta.connect()
    tmr.alarm(0,15000,0, function() M.onConnectFailure() end)
    wifi.sta.eventMonReg(wifi.STA_GOTIP, function() M.onConnectSuccess() end)
    wifi.sta.eventMonStart()
end

function M.onConnectSuccess()
    tmr.stop(0)
    print("Device IP: " .. wifi.sta.getip())
    wifi.sta.eventMonStop()   
    wifi.sta.eventMonReg(wifi.STA_GOTIP, "unreg")
    M.setupTelnetServer()
    M.safeDoFile()
end

function M.onConnectFailure()
    print('Unable to connect')
    wifi.sta.eventMonStop()   
    wifi.sta.eventMonReg(wifi.STA_GOTIP, "unreg")
    if M._fallback then M.setupAP() end
end

function M.setupAP()
    wifi.setmode(wifi.SOFTAP)
    local cfg = {ssid=string.format("ESP-%x", node.chipid()):upper()}
    wifi.ap.config(cfg)    
    print('Try to start AP ' .. cfg.ssid)   
    tmr.alarm(0,2000,0, function() print("Device IP: " .. wifi.ap.getip()) end)
    M.setupTelnetServer()
end

function M.safeDoFile(file_name)
    _file_name = file_name or 'user.lua'
    if file.list()['lock-user-run'] then
        print('Possible boot loop detected. Execution stopped')
        return
    end
    if not file.list()[_file_name] then
        print(_file_name .. ' not found. Execution stopped')
        return
    end
    file.open('lock-user-run','w')
    file.close()
    tmr.alarm(1, 30000, 0, function() M.freeLock() end)
    dofile(_file_name)
end

function M.freeLock()
    file.remove('lock-user-run')
end

function M.setupTelnetServer(port)
    local _port = port or 23
    local function listenSocket()
	local inUse = false
	return function(sock)
	    if inUse then
		sock:send("Already in use.\n")
		sock:close()
		return
	    end
	    inUse = true
	    node.output(function(str) 
		if(sock ~=nil) then sock:send(str) end 
	    end, 0)
	    sock:on("receive",function(sock, input) 
		node.input(input) 
	    end)
	    sock:on("disconnection",function(sock) 
		node.output(nil) 
		inUse = false 
	    end)
	    sock:send("Welcome to NodeMCU world.\n> ")
	end
    end
    if not M.httpServer then M.httpServer = net.createServer(net.TCP, 180) end
    M.httpServer:listen(_port, listenSocket())
    print('telnet server is running on port ' .. _port)
end

return M
