// perf_sprite_profile.ms -- run with --profile: scenario 1 (5000 bouncing balls) for 300 frames.
import "soda"
ballImg = file.loadImage("../assets/images/soda-128.png")
Ball = new Sprite
Ball.image = ballImg
Ball.scale = 0.5
Ball.vx = 0; Ball.vy = 0; Ball.vrot = 0
Ball.update = function()
	self.vy = self.vy - 1
	self.x = self.x + self.vx
	self.y = self.y + self.vy
	self.rotation = self.rotation + self.vrot * sign(self.vx)
	if self.x < 30 or self.x > 930 then self.vx = -self.vx
	if self.y < 30 and self.vy < 0 then
		self.y = 30
		self.vy = -self.vy
	end if
end function
sprs = []
for i in range(1, 5000)
	b = new Ball
	b.x = 30 + 900*rnd; b.y = 320 + 320*rnd
	b.vx = 20 * (rnd - 0.5); b.vrot = 30 * rnd
	sprs.push b
end for
display(4).sprites = sprs
for f in range(1, 300)
	for b in sprs; b.update; end for
	yield
end for
exit
