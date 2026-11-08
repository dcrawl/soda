mk = function(upd)
	B = {"x":100,"y":100,"vx":3,"vy":2,"vrot":1,"rotation":0}
	B.update = @upd
	arr = []
	for i in range(1, 2000); b = new B; arr.push b; end for
	return arr
end function
full = function()
	self.vy = self.vy - 1
	self.x = self.x + self.vx
	self.y = self.y + self.vy
	self.rotation = self.rotation + self.vrot * sign(self.vx)
	if self.x < 30 or self.x > 930 then self.vx = -self.vx
end function
nosign = function()
	self.vy = self.vy - 1
	self.x = self.x + self.vx
	self.y = self.y + self.vy
	self.rotation = self.rotation + self.vrot * ((self.vx > 0) - (self.vx < 0))
	if self.x < 30 or self.x > 930 then self.vx = -self.vx
end function
empty = function(); end function
run = function(name, upd)
	arr = mk(@upd)
	best = 1e9
	for r in range(1, 7)
		t = time
		for k in range(1, 20)
			for b in arr; b.update; end for
		end for
		t = time - t
		if t < best then best = t
	end for
	print name + " ns/ball-update: " + round(best / (20 * 2000) * 1e9)
end function
run "full (with sign)", @full
run "no sign call", @nosign
run "empty update (call+loop only)", @empty
exit
