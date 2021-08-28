TURBO_SSL = true
__TURBO_USE_LUASOCKET__ = true

local turbo = require("turbo")
local json = require("json")

turbo.log.categories.success = false

local ffi = require("ffi")
ffi.cdef[[
void Sleep(int ms);
int poll(struct pollfd *fds, unsigned long nfds, int timeout);
]]

local sleep
if ffi.os == "Windows" then
  function sleep(s)
    ffi.C.Sleep(s*1000)
  end
else
  function sleep(s)
    ffi.C.poll(nil, 0, s*1000)
  end
end

local char_to_hex = function(c)
	return string.format("%%%02X", string.byte(c))
end

local function urlencode(url)
	if url == nil then return end

	url = url:gsub("\n", "\r\n")
	url = url:gsub("([^%w ])", char_to_hex)
	url = url:gsub(" ", "+")

	return url
end

local f = string.format

local appID = 578080
local delay = 3

local list_template = "https://steamcommunity.com/market/search/render/?search_descriptions=0&sort_column=default&sort_dir=desc&appid=%i&norender=1&count=100&start=&i"
local list_url = f(list_template, appID, 0)

local inst = turbo.ioloop.instance()

local function parse_items(list)
	for _, item in ipairs(list.results) do
		-- print("Gathering data for item " .. item.name)

		local item_url = f("https://steamcommunity.com/market/priceoverview/?appid=%i&currency=5&market_hash_name=%s", appID, urlencode(item.hash_name))
		local res = coroutine.yield(turbo.async.HTTPClient({verify_ca = false}):fetch(item_url))

		if res.code == 200 then
			local item_info = json.decode(res.body)
			if not item_info.success then print("Error parsing info for " .. item.name) end

			if item_info.success then
				local lowest = item_info.lowest_price
				local median = item_info.median_price

				local price, price_float = lowest:match("(%d+)[,](%d*)")
				if not price then price, price_float = lowest:match("(%d+)"), 0 end

				lowest = price + price_float / 100

				if not median then
					median = lowest
				else
					price, price_float = median:match("(%d+)[,](%d*)")
					if not price then price, price_float = median:match("(%d+)"), 0 end

					median = price + price_float / 100
				end

				local change = median - lowest
				local profit = -(1 - (median / lowest)) * 100

				if profit > 10 then
					print("Here a chance to get a good gesheft! " .. profit .. " percent profit for " .. item.name)
				end
			end

			sleep(delay)
		end
	end
end

local function parse_list(list_url)
	local res = coroutine.yield(turbo.async.HTTPClient({verify_ca = false}):fetch(list_url))
	local items = json.decode(res.body)

	if not items.success then error("Items parsing error") end
	return items
end

inst:add_callback(function()
	local list = parse_list(list_url)
	parse_items(list)

	local total_count = items.total_count

	if total_count > 100 then
		for i = 1, math.floor((total_count / 100) + 1) do
			list_url = f(list_template, appID, i * 100)
			local list = parse_list(list_url)

			parse_items(list)
		end
	end

	inst:close()
end):start()