// perf_soak.ms -- PERF_TEST_PLAN.md §6 leak soak: scenario 5 workload for D seconds,
// logging resourceCounts + hostMemory every 30 s.
// Usage (from tests/): ../../raylib-miniscript/build-release/raylib-miniscript perf_soak.ms [runIndex] [seconds]
import "perfHarness"
import "soda"
runIdx = "1"
if shellArgs.len > 1 then runIdx = shellArgs[1]
D = 600
if shellArgs.len > 2 then D = val(shellArgs[2])
off = ""   // sprites | sound | text | pixel | tiles | all(=none of them): component to disable
if shellArgs.len > 3 then off = shellArgs[3]

ballImg = file.loadImage("../assets/images/soda-128.png")
bongo = file.loadSound("../assets/sounds/bongo.wav")
Ball = new Sprite
Ball.image = ballImg; Ball.scale = 0.5
Ball.vx = 0; Ball.vy = 0; Ball.vrot = 0
Ball.update = function()
	self.vy = self.vy - 1
	self.x = self.x + self.vx; self.y = self.y + self.vy
	self.rotation = self.rotation + self.vrot * sign(self.vx)
	if self.x < 30 or self.x > 930 then self.vx = -self.vx
	if self.y < 30 and self.vy < 0 then
		self.y = 30; self.vy = -self.vy
		if (off.indexOf("sound") == null) then bongo.play 0.2, (self.x - 480)/480, 0.9 + 0.2*rnd
	end if
end function
balls = []
for i in range(1, 500)
	b = new Ball
	b.x = 30 + 900*rnd; b.y = 320 + 320*rnd; b.vx = 20*(rnd-0.5); b.vrot = 30*rnd
	balls.push b
end for
music = file.loadSound("../assets/sounds/airRegLoop.mp3")
music.loop = true
if (off.indexOf("sound") == null) then music.play 0.1
sheet = Image.create(128, 128, "#80C0FFFF")
td = new TileDisplay
td.tileSet = sheet; td.tileSetTileSize = 32; td.cellSize = 32; td.extent = [100, 40]
display(6).mode = displayMode.tile
td.clear 5; td.install 6
if (off.indexOf("sprites") == null) then display(4).sprites = balls
px = display(5); text = display(3)
perf.resources "t=0"
start = time; nextLog = start + 30; n = 0
while time - start < D
	n = n + 1
	if (off.indexOf("sprites") == null) then
		for b in balls; b.update; end for
	end if
	if (off.indexOf("tiles") == null) then td.scrollX = n * 2 % 1000
	if n % 2 == 0 and (off.indexOf("text") == null) then text.print "frame " + n
	if (off.indexOf("pixel") == null) then
		for i in range(1, 20)
			px.line (i*47+n)%900, (i*31)%600, (i*47+n)%900 + 30, (i*31)%600 + 15, "#FF8000FF", 2
		end for
		px.print "N " + n, 10, 610, "#FFFFFFFF"
	end if
	if n % 600 == 0 then px.clear "#00000000"
	if time >= nextLog then
		perf.resources "off=" + off + ",t=" + round(time - start) + ",frames=" + n
		nextLog = nextLog + 30
	end if
	yield
end while
perf.resources "off=" + off + ",end,frames=" + n
Sound.StopAll
perf.finish "perf_results/perf_soak.run" + runIdx + ".csv"
