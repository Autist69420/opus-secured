local class  = require('opus.class')
local Region = require('opus.ui.region')
local Util   = require('opus.util')

local _rep   = string.rep
local _sub   = string.sub
local _gsub  = string.gsub
local colors = _G.colors

local Canvas = class()

Canvas.colorPalette = { }
Canvas.darkPalette = { }
Canvas.grayscalePalette = { }

for n = 1, 16 do
	Canvas.colorPalette[2 ^ (n - 1)]     = _sub("0123456789abcdef", n, n)
	Canvas.grayscalePalette[2 ^ (n - 1)] = _sub("088888878877787f", n, n)
	Canvas.darkPalette[2 ^ (n - 1)]      = _sub("8777777f77fff77f", n, n)
end

--[[
	A canvas can have more lines than canvas.height in order to scroll

	TODO: finish vertical scrolling
]]
function Canvas:init(args)
	self.bg = colors.black
	self.fg = colors.white

	Util.merge(self, args)

	self.x = self.x or 1
	self.y = self.y or 1
	self.ex = self.x + self.width - 1
	self.ey = self.y + self.height - 1

	if not self.palette then
		if self.isColor then
			self.palette = Canvas.colorPalette
		else
			self.palette = Canvas.grayscalePalette
		end
	end

	self.lines = { }
	for i = 1, self.height do
		self.lines[i] = { }
	end

	self:clear()
end

function Canvas:move(x, y)
	self.x, self.y = x, y
	self.ex = self.x + self.width - 1
	self.ey = self.y + self.height - 1
	if self.parent then
		self.parent:dirty(true)
	end
end

function Canvas:resize(w, h)
	self:resizeBuffer(w, h)

	self.ex = self.x + w - 1
	self.ey = self.y + h - 1
	self.width = w
	self.height = h
end

-- resize the canvas buffer - not the canvas itself
function Canvas:resizeBuffer(w, h)
	for i = #self.lines, h do
		self.lines[i] = { }
		self:clearLine(i)
	end

	while #self.lines > h do
		table.remove(self.lines, #self.lines)
	end

	if w < self.width then
		for i = 1, h do
			local ln = self.lines[i]
			ln.text = _sub(ln.text, 1, w)
			ln.fg = _sub(ln.fg, 1, w)
			ln.bg = _sub(ln.bg, 1, w)
		end
	elseif w > self.width then
		local d = w - self.width
		local text = _rep(' ', d)
		local fg = _rep(self.palette[self.fg], d)
		local bg = _rep(self.palette[self.bg], d)
		for i = 1, h do
			local ln = self.lines[i]
			ln.text = ln.text .. text
			ln.fg = ln.fg .. fg
			ln.bg = ln.bg .. bg
			ln.dirty = true
		end
	end
end

function Canvas:copy()
	local b = Canvas({
		x       = self.x,
		y       = self.y,
		width   = self.width,
		height  = self.height,
		isColor = self.isColor,
	})
	for i = 1, #self.lines do
		b.lines[i].text = self.lines[i].text
		b.lines[i].fg = self.lines[i].fg
		b.lines[i].bg = self.lines[i].bg
	end
	return b
end

function Canvas:addLayer(layer)
	local canvas = Canvas({
		x       = layer.x,
		y       = layer.y,
		width   = layer.width,
		height  = layer.height,
		isColor = self.isColor,
	})
	canvas.parent = self
	if not self.children then
		self.children = { }
	end
	table.insert(self.children, canvas)
	return canvas
end

function Canvas:removeLayer()
	for k, layer in pairs(self.parent.children) do
		if layer == self then
			self:setVisible(false)
			table.remove(self.parent.children, k)
			break
		end
	end
end

function Canvas:setVisible(visible)
	self.visible = visible  -- TODO: use self.active = visible
	if not visible and self.parent then
		self.parent:dirty()
		-- TODO: set parent's lines to dirty for each line in self
	end
end

-- Push a layer to the top
function Canvas:raise()
	if self.parent and self.parent.children then
		for k, v in pairs(self.parent.children) do
			if v == self then
				table.insert(self.parent.children, table.remove(self.parent.children, k))
				break
			end
		end
	end
end

function Canvas:write(x, y, text, bg, fg)
	if bg then
		bg = _rep(self.palette[bg], #text)
	end
	if fg then
		fg = _rep(self.palette[fg] or self.palette[1], #text)
	end
	self:blit(x, y, text, bg, fg)
end

function Canvas:blit(x, y, text, bg, fg)
	if y > 0 and y <= #self.lines and x <= self.width then
		local width = #text

		-- fix ffs
		if x < 1 then
			text = _sub(text, 2 - x)
			if bg then
				bg = _sub(bg, 2 - x)
			end
			if fg then
				fg = _sub(fg, 2 - x)
			end
			width = width + x - 1
			x = 1
		end

		if x + width - 1 > self.width then
			text = _sub(text, 1, self.width - x + 1)
			if bg then
				bg = _sub(bg, 1, self.width - x + 1)
			end
			if fg then
				fg = _sub(fg, 1, self.width - x + 1)
			end
			width = #text
		end

		if width > 0 then

			local function replace(sstr, pos, rstr)
				if pos == 1 and width == self.width then
					return rstr
				elseif pos == 1 then
					return rstr .. _sub(sstr, pos+width)
				elseif pos + width > self.width then
					return _sub(sstr, 1, pos-1) .. rstr
				end
				return _sub(sstr, 1, pos-1) .. rstr .. _sub(sstr, pos+width)
			end

			local line = self.lines[y]
			if line then
				line.dirty = true
				line.text = replace(line.text, x, text, width)
				if fg then
					line.fg = replace(line.fg, x, fg, width)
				end
				if bg then
					line.bg = replace(line.bg, x, bg, width)
				end
			end
		end
	end
end

function Canvas:writeLine(y, text, fg, bg)
	if y > 0 and y <= #self.lines then
		self.lines[y].dirty = true
		self.lines[y].text = text
		self.lines[y].fg = fg
		self.lines[y].bg = bg
	end
end

function Canvas:clearLine(y, bg, fg)
	fg = _rep(self.palette[fg or self.fg], self.width)
	bg = _rep(self.palette[bg or self.bg], self.width)
	self:writeLine(y, _rep(' ', self.width), fg, bg)
end

function Canvas:clear(bg, fg)
	local text = _rep(' ', self.width)
	fg = _rep(self.palette[fg or self.fg], self.width)
	bg = _rep(self.palette[bg or self.bg], self.width)
	for i = 1, #self.lines do
		self:writeLine(i, text, fg, bg)
	end
end

function Canvas:isDirty()
	for i = 1, #self.lines do
		if self.lines[i].dirty then
			return true
		end
	end
end

function Canvas:dirty(includingChildren)
	if self.lines then
		for i = 1, #self.lines do
			self.lines[i].dirty = true
		end

		if includingChildren and self.children then
			for _, child in pairs(self.children) do
				child:dirty(true)
			end
		end
	end
end

function Canvas:clean()
	for i = 1, #self.lines do
		self.lines[i].dirty = nil
	end
end

function Canvas:applyPalette(palette)
	local lookup = { }
	for n = 1, 16 do
		lookup[self.palette[2 ^ (n - 1)]] = palette[2 ^ (n - 1)]
	end

	for _, l in pairs(self.lines) do
		l.fg = _gsub(l.fg, '%w', lookup)
		l.bg = _gsub(l.bg, '%w', lookup)
		l.dirty = true
	end

	self.palette = palette
end

function Canvas:render(device)
	local offset = { x = 0, y = 0 }

	-- WIP
	local function getRegion(canvas)
		local region
		if canvas.parent then
			region = getRegion(canvas.parent)
		else
			region = Region.new(self.x, self.y, self.ex, self.ey)
		end
		offset.x = offset.x + canvas.x - 1
		offset.y = offset.y + canvas.y - 1
		-- clip against parent
		return region
	end

	-- this code works - but is all kinds of wrong
	-- adding a margin to UI.Page will cause issues
	-- and could be clipping issues
	offset = { x = self.x - 1, y = self.y - 1 }
	local parent = self.parent
	while parent do
		offset.x = offset.x + parent.x - 1
		offset.y = offset.y + parent.y - 1
		parent = parent.parent
	end

	-- TODO: need to clip if there is a parent
	--self.regions = Region.new(self.x + offset.x, self.y + offset.y, self.ex + offset.x, self.ey + offset.y)
	--self:__renderLayers(device, offset)

	self.regions = Region.new(self.x, self.y, self.ex, self.ey)
	self:__renderLayers(device, { x = self.x - 1, y = self.y - 1 })
end

-- regions are comprised of absolute values that correspond to the output device.
-- canvases have coordinates relative to their parent.
-- canvas layer's stacking order is determined by the position within the array.
-- layers in the beginning of the array are overlayed by layers further down in
-- the array.
function Canvas:__renderLayers(device, offset)
	if self.children then
		for i = #self.children, 1, -1 do
			local canvas = self.children[i]
			if canvas.visible or canvas.enabled then
				-- get the area to render for this layer
				canvas.regions = Region.new(
					canvas.x + offset.x - (self.offx or 0),
					canvas.y + offset.y - (self.offy or 0),
					canvas.ex + offset.x - (self.offx or 0),
					canvas.ey + offset.y - (self.offy or 0))

				-- contain within parent
				canvas.regions:andRegion(self.regions)

				-- punch out this area from the parent's canvas
				self.regions:subRect(
					canvas.x + offset.x - (self.offx or 0),
					canvas.y + offset.y - (self.offy or 0),
					canvas.ex + offset.x - (self.offx or 0),
					canvas.ey + offset.y - (self.offy or 0))

				if #canvas.regions.region > 0 then
					canvas:__renderLayers(device, {
						x = canvas.x + offset.x - 1 - (self.offx or 0),
						y = canvas.y + offset.y - 1 - (self.offy or 0),
					})
				end
				canvas.regions = nil
			end
		end
	end

	for _,region in ipairs(self.regions.region) do
		self:__blitRect(device,
			{ x = region[1] - offset.x,
			  y = region[2] - offset.y,
			  ex = region[3] - offset.x,
			  ey = region[4] - offset.y },
			{ x = region[1], y = region[2] })
	end
	self.regions = nil

	self:clean()
end

-- performance can probably be improved by using one more buffer tied to the device
function Canvas:__blitRect(device, src, tgt)
	src = src or { x = 1, y = 1, ex = self.ex - self.x + 1, ey = self.ey - self.y + 1 }
	tgt = tgt or self

	-- for visualizing updates on the screen
	if Canvas.__visualize or self.visualize then
		local drew
		local t  = _rep(' ', src.ex-src.x + 1)
		local bg = _rep(2,   src.ex-src.x + 1)
		for i = 0, src.ey - src.y do
			local line = self.lines[src.y + i + (self.offy or 0)]
			if line and line.dirty then
				drew = true
				device.setCursorPos(tgt.x, tgt.y + i)
				device.blit(t, bg, bg)
			end
		end
		if drew then
			local c = os.clock()
			repeat until os.clock()-c > .03
		end
	end
	for i = 0, src.ey - src.y do
		local line = self.lines[src.y + i + (self.offy or 0)]
		if line and line.dirty then
			local t, fg, bg = line.text, line.fg, line.bg
			if src.x > 1 or src.ex < self.ex then
				t  = _sub(t, src.x, src.ex)
				fg = _sub(fg, src.x, src.ex)
				bg = _sub(bg, src.x, src.ex)
			end
			device.setCursorPos(tgt.x, tgt.y + i)
			device.blit(t, fg, bg)
		end
	end
end

if not ({ ... })[1] then
	local UI = require('opus.ui')

	UI:setPage(UI.Page {
		button = UI.Button {
			x = 5, y = 5,
			text = 'abc'
		}
	})
	UI:start()
end

return Canvas
