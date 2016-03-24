-- SPL is a toy forth-like language

local function preunaryWord( op )
	return {assert(load(([[return function(vm)
		vm.stack[vm.sp] = %s vm.stack[vm.sp]
		return true
	end]]):format(op)))(), 1, 1}
end

local function postunaryWord( op )
	return {assert(load(([[return function(vm)
		vm.stack[vm.sp] = vm.stack[vm.sp] %s
		return true
	end]]):format(op)))(), 1, 1}
end

local function binaryWord( op )
	return {assert(load(([[return function(vm)
		vm.stack[vm.sp-1] = vm.stack[vm.sp-1] %s vm.stack[vm.sp]
		vm.sp = vm.sp-1
		return true
	end]]):format(op)))(), 2, 1}
end

local function nop()
	return true
end

local function dup( vm )
	vm.sp = vm.sp + 1
	vm.stack[vm.sp] = vm.stack[vm.sp-1]
	return true
end

local function dup2( vm )
	vm.sp = vm.sp + 2
	vm.stack[vm.sp] = vm.stack[vm.sp-2]
	vm.stack[vm.sp-1] = vm.stack[vm.sp-3]
	return true
end
	
local function swap( vm )
	vm.stack[vm.sp], vm.stack[vm.sp-1] = vm.stack[vm.sp-1], vm.stack[vm.sp]
	return true
end

local function over( vm ) 
	vm.sp = vm.sp + 1
	vm.stack[vm.sp] = vm.stack[vm.sp-2]
	return true
end

local function rot( vm )
	if vm.sp > 1 then
		local tmp = vm.stack[vm.sp]
		for i = vm.sp, 2, -1 do
			vm.stack[i] = vm.stack[i-1]
		end
		vm.stack[1] = tmp
	end
	return true
end

local function halt( vm )
	vm.halt = true 
	return true
end

local function drop( vm ) 
	vm.sp = vm.sp - 1
	print( vm.stack[vm.sp+1] )
	return true
end

local function quietdrop( vm )
	vm.sp = vm.sp - 1
	return true
end

local function inspectstack( vm )
	if vm.sp == 0 then
		print( 'stack is empty' )
	else
		io.write('stack: [')
		io.write( tostring( vm.stack[vm.sp] ))
		for i = vm.sp-1, 1, -1 do
			io.write(' ')
			io.write(tostring( vm.stack[i])) 
		end 
		io.write(']\n') 
	end
	return true
end

local function list( vm )
	for k, v in pairs( vm.dict ) do
		print( ('%s (%d -- %s)'):format( k, v[2], v[3] ))
	end
	return true
end

local function eval( vm )
	vm.sp = vm.sp - 1 
	vm:docommand( vm.stack[vm.sp+1] )
	return true
end

local function ifcommand( vm )
	vm.sp = vm.sp - 3
	if vm.stack[vm.sp+1] then
		vm:docommand( vm.stack[vm.sp+2] ) 
	else
		vm:docommand( vm.stack[vm.sp+3] ) 
	end
	return true
end

local function dropall( vm )
	vm.sp = 0
	return true
end

local function reverse( vm )
	local n = vm.sp
	for i = 1, math.floor(n/2) do
		vm.stack[i], vm.stack[n-i+1] = vm.stack[n-i+1], vm.stack[i]
	end
	return true
end

local function define( vm )
	local name = vm.stack[vm.sp]
	if vm.dict[name] then
		if vm.saveoldwords then
			local index = 1
			local oldname = name .. '_' .. index
			while vm.dict[oldname] do
				index = index + 1
				oldname = name .. '_' .. index
			end
			vm.dict[oldname] = vm.dict[name]
			print( 'Redefining word: ', name, 'move old word to:', oldname ) 
		else
			print( 'Redefining word!', name )
		end
	end

	local code = {}
	for i = 1, vm.sp-1 do
		code[i] = vm.stack[i]
	end
	local n = #code
	vm.dict[name] = {function( vm_ )
		for i = 1, n do
			vm_:docommand( code[i] )
		end
	end, 0, 0, code}
	vm.sp = 0
	return true
end

local function dump( vm )
	vm.sp = vm.sp - 1
	local name = vm.stack[vm.sp+1]
	local fio = vm.dict[name]
	if fio then
		if fio[4] then
			io.write( '>> ' )
			for i = 1, #fio[4] do
				io.write( fio[4][i] )
				io.write( ' ' )
			end
			print()
		else
			print('built-in')
		end
	else
		return false, 'NOT_DEFINED', 'Word ' .. tostring( name ) .. ' not defined'
	end
end

local function loadspl( vm )
	vm.sp = vm.sp - 1
	local filename = vm.stack[vm.sp+1]
	local f = io.open( filename, 'r' )
	if f then
		for s in f:lines() do
			vm:interpret( s )
		end
		return true
	else
		return false, 'FILE_NOT_EXIST', 'No such file: ' .. tostring( filename )
	end
end

local function flush( vm )
	vm.sp = vm.sp - 1
	vm.dict[vm.stack[vm.sp+1]] = nil
	return true
end

local DefaultDict = {
	nop = {nop,0,0},
	halt = {halt,0,0},
	neg = preunaryWord('-'),
	swap = {swap,2,2}, dup = {dup,1,2}, over = {over,2,3}, ['.'] = {drop,1,0}, drop = {quietdrop,1,0},
	reverse = {reverse,0,0}, dup2 = {dup2,2,4}, rot = {rot,0,0}, [';'] = {dropall,0,0},
	['.s'] = {inspectstack,0,0},
	dump = {dump,1,0},
	list = {list,0,0},
	eval = {eval,1,'?'},
	['if'] = {ifcommand,3,'?'},
	[':'] = {define,2,0},
	load = {loadspl,1,'?'},
	flush = {flush,1,0}
}

for s in ('not'):gmatch( '(%S+)' ) do
	DefaultDict[s] = preunaryWord( s )
end

for s in ('+ - * / < > <= >= ~= == ^ % and or'):gmatch( '(%S+)' ) do
	DefaultDict[s] = binaryWord( s )
end

local VM = {
	stack = {},
	sp = 0,
	dict = {},
	halt = false,
	saveoldwords = true,
	onerror = function( self, errtype, msg )
		print( ('[%s] %s'):format(errtype,msg) )
	end,
}

function VM.assure( self, n )
	if self.sp >= n then
		return true
	else
		return false, 'STACK_UNDERFLOW', ('sp: %d, needed: %d'):format( self.sp, n )
	end
end

function VM.interpret( self, command )
	if not (command:sub(1,1) == '#') then
		for v in command:gmatch( '(%S+)' ) do
			self:docommand( v )
		end
	end
end

function VM.docommand( self, v )
	v = tostring(v)
	if v:sub(1,1) == '\'' then
		self.sp = self.sp+1
		self.stack[self.sp] = v:sub(2)
	elseif self.dict[v] then
		local fio = self.dict[v]
		if fio then
			local ok, err, msg = self:assure( fio[2] )
			if ok then
				ok, err, msg = pcall( fio[1], self )
			end

			if not ok then
				self:onerror( err, msg )
				return false
			end
		end
	else
		if v == 'true' then
			self.sp = self.sp+1
			self.stack[self.sp] = true
		elseif v == 'false' then
			self.sp = self.sp+1
			self.stack[self.sp] = false
		else
			local n = tonumber( v )
			if n then
				self.sp = self.sp+1
				self.stack[self.sp] = n
			else
				self:onerror( 'BAD_INPUT', ('errortoken: %q'):format( v ) )
				return false
			end
		end
	end
	return true
end

print( 'Welcome to SPL REPL' )

VM.dict = DefaultDict

while not VM.halt do
	VM:interpret( io.read())
end
