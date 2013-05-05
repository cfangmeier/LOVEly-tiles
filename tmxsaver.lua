local path      = (...):match('^.+[%.\\/]') or ''
local mapdata   = require(path..'mapdata')
local map       = require(path..'map')
local isomap    = require(path..'isomap')

-- ==============================================
-- PATH FUNCTIONS
-- ==============================================

local function getPathComponents(path)
	local dir,name,ext = path:match('^(.-)([^\\/]-)%.?([^\\/%.]*)$')
	if #name == 0 then name = ext; ext = '' end
	return dir,name,ext
end

local function removeUpDirectory(path)
	while path:find('%.%.[\\/]+') do
		path = path:gsub('[^\\/]*[\\/]*%.%.[\\/]+','')
	end
	return path
end

local stripExcessSlash = function(path)
	return path:gsub('[\\/]+','/'):match('^/?(.*)')
end

-- ==============================================
-- FORMAT PROPERTIES TABLE
-- ==============================================

local ok_type = {
	boolean = true,
	string  = true,
	number  = true,
}

local function prepareTableProperties(properties)
	if properties then
		local formatted = {__element = 'properties'}
		for name,value in pairs(properties) do
			if ok_type[type(name)] and ok_type[type(value)] then
				local property = {
					__element= 'property',
					name     = tostring(name),
					value    = tostring(value),
				}
				table.insert(formatted,property)
			end
		end
		return formatted
	end
end

-- ==============================================
-- FORMAT TILESET/TILE LAYER/OBJECT GROUP
-- ==============================================

local makeAndInsertTileset = function(layer,atlasDone,tilesets,firstgid)
	local atlas = layer:getAtlas()
	if not atlasDone[atlas] then
		atlasDone[atlas]= atlas
		local tw,th     = atlas:getqSize()
		local _,_,aw    = atlas:getViewport()
		
		local iw,ih  = atlas:getImageSize()
		local image  = {
			__element= 'image',
			source   = layer:getImagePath(),
			width    = iw,
			height   = ih,
		}
		
		local tiles = {}
		local rows,cols = atlas:getRows(),atlas:getColumns()
		for y = 1,rows do
			for x = 1,cols do
				local index = (y-1)*cols+x
				local prop  = atlas:getProperty(index)
				if prop then
					local id   = index-1
					local tile = {
						__element = 'tile',
						id        = id;
						
						prepareTableProperties( prop ),
					}
					table.insert(tiles,tile)
				end
			end
		end
		
		local to         = atlas.tileoffset
		local tileoffset = to and {
			__element= 'tileoffset',
			x        = to.x,
			y        = to.y
		} 
		
		local _,name = getPathComponents(layer:getAtlasPath())
		local tileset= {
			__element = 'tileset',
			firstgid  = firstgid,
			name      = name or ('tileset '..i),
			tilewidth = tw,
			tileheight= th,
			spacing   = atlas:getSpacings(), 
			margin    = (iw-aw)/2,
			
			prepareTableProperties(atlas.properties),
			image,
			tileoffset,
			-- tile
		}
		
		for i,tile in ipairs(tiles) do
			table.insert(tileset,tile)
		end
		
		table.insert(tilesets,tileset)
		local newgid = 1+(rows*cols)
		return newgid
	end
end

local isEqualAngle = function(angle1,angle2)
	local fullcircle = 2*math.pi
	while angle1 >= fullcircle do
		angle1 = angle1-fullcircle
	end
	while angle1 < 0 do
		angle1 = angle1+fullcircle
	end
	
	while angle2 >= fullcircle do
		angle2 = angle2-fullcircle
	end
	while angle2 < 0 do
		angle2 = angle2+fullcircle
	end
	
	return math.abs(angle1-angle2) < 0.02
end

local getFlipBits = function(x,y,layer)
	local angle   = layer:getAngle(x,y)
	local iszero  = isEqualAngle(angle,0)
	
	local flipx,flipy      = layer:getFlip(x,y)
	local xbit,ybit,diagbit= 0,0,0
	
	-- see tmxloader note for bit flip
	if iszero then
		xbit,ybit = flipx and 2^31 or xbit,flipy and 2^30 or ybit
		diagbit   = 0
	else
		if isEqualAngle(angle,math.pi)then
			xbit    = not flipx and 2^31 or xbit
			ybit    = not flipy and 2^30 or ybit
			diagbit = 0
		elseif isEqualAngle(angle,math.pi/2) then
			xbit    = not flipx and 2^31 or xbit
			ybit    = flipy and 2^30 or ybit
			diagbit = 2^29
		elseif isEqualAngle(angle,3*math.pi/4) then
			xbit    = flipx and 2^31 or xbit
			ybit    = not flipy and 2^30 or ybit
			diagbit = 2^29
		end
	end
		
	return xbit+ybit+diagbit
end

local makeAndInsertTileLayer = function(drawlist,i,layer,layers,firstgid)
	
	local data = layer:export()
	
	for x,y,index in mapdata.array(data,data.width,data.height) do
		if index ~= 0 then
			local flipbits= getFlipBits(x,y,layer)
			local gid     = index + firstgid-1 + flipbits
			local i       = (y-1)*data.width+x
			data[i]       = gid
		end
	end
	
	local rows = {}
	for i = 1,#data,data.width do
		table.insert(rows,table.concat(data,',',i,i+data.width-1))
	end
	local formatteddata = {__element = 'data',encoding = 'csv'; table.concat(rows,',\n')}
	
	local _,name = getPathComponents(drawlist:getLayerPath(i))
	local formattedlayer = {
		__element= 'layer',
		name     = name or ('layer '..i),
		visible  = drawlist:isDrawable(i) and 1 or 0,
		data     = formatteddata,
		width    = data.width,
		height   = data.height,
		opacity  = layer.opacity,
		
		prepareTableProperties(layer.properties),
		formatteddata,
	}
	table.insert(layers,formattedlayer)
end

local makeAndInsertObjGroup = function(layer,layers)
	local copy = {
		__element = 'objectgroup',
		name      = layer.name,
		color     = layer.color,
		x         = layer.x,
		y         = layer.y,
		width     = layer.width,
		height    = layer.height,
		opacity   = layer.opacity,
		visible   = layer.visible,
		prepareTableProperties(layer.properties),
		-- object
	}
	
	local objects = {}
	for _,obj in ipairs(layer.objects) do
		local newobj = {
			__element= 'object',
			name     = obj.name,
			type     = obj.type,
			x        = obj.x,
			y        = obj.y,
			width    = obj.width,
			height   = obj.height,
			rotation = obj.rotation,
			gid      = obj.gid,
			visible  = obj.visible;
			 
			prepareTableProperties(obj.properties),
			-- type
		}
		
		local type = obj.polygon and {__element = 'polygon'} or 
		obj.polyline and {__element = 'polyline'} 
		or obj.ellipse and {__element = 'ellipse'}
		
		if obj.polyline or obj.polygon then
			local points = (obj.polygon or obj.polyline).points
			local str = ''
			for i = 1,#points,2 do
				str = str..points[i]..','..points[i+1]..' '
			end
			type.points = str
		end
		
		table.insert(newobj,type)
		table.insert(objects,newobj)
	end
	
	for i,obj in ipairs(objects) do
		table.insert(copy,obj)
	end
	
	table.insert(layers,copy)
end

-- ==============================================
-- PREPARE AND SAVE
-- ==============================================

local function prepareTable(drawlist,path)
	local orientation = 'orthogonal'
	local dummylayer
	for i,layer in pairs(drawlist.layers) do
		local meta = getmetatable(layer)
		if meta then 
			local class = meta.__index
			if class == isomap then orientation = 'isometric' dummylayer = layer end
			if class == map then dummylayer = layer end
		end
	end
	
	local tw,th  = dummylayer:getTileSize()
	local tmxmap = {
		__element   = 'map',
		version     = '1.0',
		orientation = orientation,
		width       = 0,
		height      = 0,
		tilewidth   = tw,
		tileheight  = th;
		
		prepareTableProperties(drawlist.properties)
		-- tileset
		-- layer
	}
	
	local atlasDone = {}
	local tilesets  = {}
	local layers    = {}
	local firstgid  = 1
	
	for i,layer in ipairs(drawlist.layers) do
		local meta  = getmetatable(layer)
		local class = meta and meta.__index
		if class == map or class == isomap then
			local newgid = makeAndInsertTileset(layer,atlasDone,tilesets,firstgid)
			makeAndInsertTileLayer(drawlist,i,layer,layers,firstgid)
			firstgid = newgid or firstgid
		elseif layer.objects then
			makeAndInsertObjGroup(layer,layers)
		elseif layer.image then
			local _,name = getPathComponents(layer.imagepath)
			local imagelayer  = {
				__element= 'imagelayer',
				name     = name,
				source   = layer.imagepath,
				width    = layer.image:getWidth(),
				height   = layer.image:getHeight(),
				
				prepareTableProperties(layer.properties),
			}
		
			table.insert(layers,imagelayer)
		end
	end
	
	local mw,mh = 0,0
	for i,layer in ipairs(layers) do
		mw,mh = math.max(layer.width,mw),math.max(layer.height,mh)
	end
	tmxmap.width,tmxmap.height = mw,mh
	
	for i,tileset in ipairs(tilesets) do
		table.insert(tmxmap,tileset)
	end
	for i,layer in ipairs(layers) do
		table.insert(tmxmap,layer)
	end
	
	return tmxmap
end

local saveToXML = function(t,filename)
	local file = love.filesystem.newFile(filename)
	
	file:open 'w'
	file:write '<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n'
	
	local recursive
	recursive = function(t,level)
		local element = t.__element
		local tabs    = string.rep('\t',level)
		
		file:write (tabs..'<'..element)
		-- attributes
		for i,v in pairs(t) do
			local itype = type(i)
			local vtype = type(v)
			
			if itype ~= 'number' and vtype ~= 'table' and i ~= '__element' then
				file:write( string.format( ' %s=%q ',tostring(i),tostring(v) ) )
			end
		end
		if t[1] then 
			file:write ('>\n')
			-- subelements/text
			for i,v in ipairs(t) do
				local vtype = type(v)
				
				if vtype == 'table' then
					recursive(v,level+1)
				else
					file:write(tostring(v)..'\n')
				end
			end
			file:write (tabs..'</'..element..'>\n')
		else
			file:write ('/>\n')
		end
	end
	recursive(t,0)
	file:close()
end

return function(drawlist,path)
	saveToXML( prepareTable(drawlist,path),path )
end