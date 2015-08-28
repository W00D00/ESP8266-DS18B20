local GPIO0 = 3
local temperature = 0

function getTemp(pin)
	local sensors = {}
	local addr = nil
	local count = 0
	ow.setup(pin)
	repeat
		count = count + 1
		addr = ow.reset_search(pin)
		addr = ow.search(pin)
		table.insert(sensors, addr)
		tmr.wdclr()
	until((addr ~= nil) or (count > 100))
	debugPrint("Sensors:", #sensors)
	if (addr == nil) then
		debugPrint('DS18B20 not found')
	end
	local s = string.format("Addr:%02X-%02X-%02X-%02X-%02X-%02X-%02X-%02X", 
		addr:byte(1), addr:byte(2), addr:byte(3), addr:byte(4), 
		addr:byte(5), addr:byte(6), addr:byte(7), addr:byte(8))
	debugPrint(s)
	crc = ow.crc8(string.sub(addr, 1, 7))
	if (crc ~= addr:byte(8)) then
		debugPrint('DS18B20 Addr CRC failed');
	end
	if not((addr:byte(1) == 0x10) or (addr:byte(1) == 0x28)) then
		debugPrint('DS18B20 not found')
	end
	ow.reset(pin)
	ow.select(pin, addr)
	ow.write(pin, 0x44, 1)
	tmr.delay(1000000)
	present = ow.reset(pin)
	if present ~= 1 then
		debugPrint('DS18B20 not present')
	end
	ow.select(pin, addr)
	ow.write(pin, 0xBE, 1)
	local data = nil
	data = string.char(ow.read(pin))
	for i = 1, 8 do
		data = data .. string.char(ow.read(pin))
	end
	s = string.format("Data:%02X-%02X-%02X-%02X-%02X-%02X-%02X-%02X", 
		data:byte(1), data:byte(2), data:byte(3), data:byte(4),
		data:byte(5), data:byte(6), data:byte(7), data:byte(8))
	debugPrint(s)
	crc = ow.crc8(string.sub(data, 1, 8))
	if (crc ~= data:byte(9)) then
		debugPrint('DS18B20 data CRC failed')
	end
	local t0 = (data:byte(1) + data:byte(2) * 256)
	if (t0 > 32767) then
		t0 = t0 - 65536
	end
	t0 = t0 * 625
	temperature = (t0 / 10000) .. "." .. (t0 % 10000)
	debugPrint(string.format("Temperature: %s C", temperature))
end

local function sendDataToThingSpeak()
	debugPrint("send data to ThingSpeak...")
	conn = net.createConnection(net.TCP, 0)
	conn:on("receive", function(conn, payload) debugPrint(payload) end)
	conn:connect(80, '184.106.153.149')
	conn:send("GET /update?key=F12RR28X82LLT0FE&field1="  .. temperature .. " HTTP/1.1\r\n") 
	conn:send("Host: api.thingspeak.com\r\n") 
	conn:send("Accept: */*\r\n") 
	conn:send("User-Agent: Mozilla/4.0 (compatible; esp8266 Lua; Windows NT 5.1)\r\n")
	conn:send("\r\n")
	conn:on("sent", function(conn) debugPrint("Closing connection") conn:close() end)
	conn:on("disconnection", function(conn) debugPrint("Got disconnection...") end)
end

function main()
	getTemp(GPIO0)
	sendDataToThingSpeak()
end

getTemp(GPIO0)

tmr.alarm(1, 60000, 1, function() main() end)

srv = net.createServer(net.TCP)
srv:listen(80, function(conn)
	conn:on("receive", function(conn, payload)
		debugPrint(payload)
		conn:send('HTTP/1.1 200 OK\r\nConnection: keep-alive\r\nCache-Control: private, no-store\r\n\r\n')
		conn:send('<!DOCTYPE HTML>')
		conn:send('<html lang="hu">')
		conn:send('<head>')
		conn:send('<meta http-equiv="Content-Type" content="text/html; charset=utf-8">')
		conn:send('<meta http-equiv="refresh" content="60">')
		conn:send('<meta name="viewport" content="width=device-width, initial-scale=1">')
		conn:send('<title>Hőmérséklet (ESP8266 & DS18B20)</title>')
		conn:send('</head>')
		conn:send('<body>')
		conn:send('<h1>Hőmérséklet (ESP8266 & DS18B20)</h1>')
		conn:send('<h2>')
		conn:send('<input style="text-align: center" type="text" size=4 name="p" value="' .. temperature .. '"> C hőmérséklet<br><br>')
		conn:send('</h2>')
		conn:send('</body></html>')		
		conn:close()
		collectgarbage()
	end)
	conn:on("sent", function(conn) conn:close() end)
end)
