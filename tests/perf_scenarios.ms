// perf_scenarios.ms -- PERF_TEST_PLAN.md §5 integration scenarios.
//   1 balls xN (with sounds)   2 text adventure   3 scrolling platformer
//   4 paint program            5 everything at once (+ music)
// Each runs 600 frames, phase breakdown via perf.frames.
// Usage (from tests/): ../../raylib-miniscript/build-release/raylib-miniscript perf_scenarios.ms [runIndex] [only]
import "perfHarness"
import "soda"

runIdx = "1"
if shellArgs.len > 1 then runIdx = shellArgs[1]
only = ""
if shellArgs.len > 2 then only = shellArgs[2]
want = function(n); return only == "" or only == str(n); end function

nFrames = 600
ballImg = file.loadImage("../assets/images/soda-128.png")
bongo = file.loadSound("../assets/sounds/bongo.wav")

// ---------- 1. balls ----------
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
		vol = self.vy / 20; if vol > 1 then vol = 1
		bongo.play vol, (self.x - 480)/480, 0.9 + 0.2*rnd
	end if
end function

makeBalls = function(n)
	sprs = []
	for i in range(1, n)
		b = new Ball
		b.x = 30 + 900*rnd; b.y = 320 + 320*rnd
		b.vx = 20 * (rnd - 0.5); b.vrot = 30 * rnd
		sprs.push b
	end for
	return sprs
end function

if want(1) then
	for n in [100, 1000, 5000]
		clear
		sprs = makeBalls(n)
		display(4).sprites = sprs
		f = function()
			for b in sprs; b.update; end for
		end function
		perf.frames "scn1_balls", n, @f, nFrames, 10
		Sound.StopAll
		clear
		perf.resources "scn1-" + n
	end for
end if

// ---------- 2. text adventure ----------
if want(2) then
	clear
	text = display(3)
	st = {"n": 0}
	lines = ["You are standing in an open field west of a white house.",
	  "There is a small mailbox here.", "> open mailbox",
	  "Opening the small mailbox reveals a leaflet.", "> take leaflet", "Taken."]
	f = function()
		st.n = st.n + 1
		text.print lines[st.n % lines.len]
		if st.n % 3 == 0 then text.print "(" + st.n + ") " + "x" * (st.n % 70)
	end function
	perf.frames "scn2_textAdventure", 1, @f, nFrames, 10
	clear
end if

// ---------- 3. scrolling platformer ----------
if want(3) then
	clear
	sheet = Image.create(128, 128, "#80C0FFFF")
	for i in range(0, 127); sheet.setPixel i, i, "#FF0000FF"; end for
	td = new TileDisplay
	td.tileSet = sheet; td.tileSetTileSize = 32; td.cellSize = 32
	td.extent = [200, 50]
	display(6).mode = displayMode.tile
	for y in range(0, 49)
		for x in range(0, 199)
			if y < 20 or (x + y) % 3 == 0 then td.setCell x, y, (x * 7 + y) % 16
		end for
	end for
	td.install 6
	playerImg = Image.create(32, 32, "#40FF40FF")
	enemyImg = Image.create(32, 32, "#FF4040FF")
	mk = function(img, x, y)
		s = new Sprite
		s.image = img; s.x = x; s.y = y
		s.localBounds = new Bounds
		s.localBounds.width = 32; s.localBounds.height = 32
		return s
	end function
	player = mk(playerImg, 480, 300)
	enemies = []
	for i in range(1, 20); enemies.push mk(enemyImg, 100 + i*40, 200 + (i*17)%300); end for
	others = []
	for i in range(1, 29); others.push mk(playerImg, (i*61)%900, (i*29)%600); end for
	display(4).sprites = [player] + enemies + others
	px = display(5)
	hits = {"n": 0}
	st = {"n": 0}
	f = function()
		st.n = st.n + 1
		td.scrollX = st.n * 3 % 4000
		td.scrollY = st.n % 200
		player.x = 480 + 200 * cos(st.n / 30)
		for e in enemies
			e.x = e.x + sign(player.x - e.x)
			if player.overlaps(e) then hits.n = hits.n + 1
		end for
		px.clear "#00000000"
		px.print "SCORE " + (st.n * 10), 10, 610, "#FFFFFFFF"
		px.print "HITS " + hits.n, 10, 590, "#FFFF00FF"
	end function
	perf.frames "scn3_platformer", 1, @f, nFrames, 10
	clear
end if

// ---------- 4. paint program ----------
if want(4) then
	clear
	px = display(5)
	px.clear "#FFFFFFFF"
	st = {"n": 0}
	f = function()
		st.n = st.n + 1
		for i in range(1, 100)
			a = (st.n * 100 + i) * 0.1
			x = 480 + 300 * cos(a); y = 320 + 200 * sin(a * 1.3)
			px.line x, y, x + 20, y + 10, color.rgb(i*2, 100, 255 - i*2), 3
		end for
		for i in range(1, 100)
			px.fillEllipse (i * 37 + st.n) % 900, (i * 53) % 600, 20, 14, color.rgb(255 - i*2, i*2, 120)
		end for
	end function
	perf.frames "scn4_paint", 1, @f, nFrames, 10
	clear
end if

// ---------- 4b. paint program, one batch bracket per frame ----------
if want(4) and PixelDisplay.hasIndex("beginBatch") then
	clear
	px = display(5)
	px.clear "#FFFFFFFF"
	st = {"n": 0}
	f = function()
		st.n = st.n + 1
		px.beginBatch
		for i in range(1, 100)
			a = (st.n * 100 + i) * 0.1
			x = 480 + 300 * cos(a); y = 320 + 200 * sin(a * 1.3)
			px.line x, y, x + 20, y + 10, color.rgb(i*2, 100, 255 - i*2), 3
		end for
		for i in range(1, 100)
			px.fillEllipse (i * 37 + st.n) % 900, (i * 53) % 600, 20, 14, color.rgb(255 - i*2, i*2, 120)
		end for
		px.endBatch
	end function
	perf.frames "scn4_paint_batched", 1, @f, nFrames, 10
	clear
end if

// ---------- 4c. paint program, PixelDisplay.autoBatch = true ----------
if want(4) then
	clear
	PixelDisplay.autoBatch = true
	px = display(5)
	px.clear "#FFFFFFFF"
	st = {"n": 0}
	f = function()
		st.n = st.n + 1
		for i in range(1, 100)
			a = (st.n * 100 + i) * 0.1
			x = 480 + 300 * cos(a); y = 320 + 200 * sin(a * 1.3)
			px.line x, y, x + 20, y + 10, color.rgb(i*2, 100, 255 - i*2), 3
		end for
		for i in range(1, 100)
			px.fillEllipse (i * 37 + st.n) % 900, (i * 53) % 600, 20, 14, color.rgb(255 - i*2, i*2, 120)
		end for
	end function
	perf.frames "scn4_paint_auto", 1, @f, nFrames, 10
	PixelDisplay.autoBatch = false
	clear
end if

// ---------- 4b. paint program, one batch bracket per frame ----------
if want(4) and PixelDisplay.hasIndex("beginBatch") then
	clear
	px = display(5)
	px.clear "#FFFFFFFF"
	st = {"n": 0}
	f = function()
		st.n = st.n + 1
		px.beginBatch
		for i in range(1, 100)
			a = (st.n * 100 + i) * 0.1
			x = 480 + 300 * cos(a); y = 320 + 200 * sin(a * 1.3)
			px.line x, y, x + 20, y + 10, color.rgb(i*2, 100, 255 - i*2), 3
		end for
		for i in range(1, 100)
			px.fillEllipse (i * 37 + st.n) % 900, (i * 53) % 600, 20, 14, color.rgb(255 - i*2, i*2, 120)
		end for
		px.endBatch
	end function
	perf.frames "scn4_paint_auto_batched", 1, @f, nFrames, 10
	PixelDisplay.autoBatch = false
	clear
end if

// ---------- 5. everything at once ----------
if want(5) then
	clear
	music = file.loadSound("../assets/sounds/airRegLoop.mp3")
	music.loop = true
	music.play 0.3
	// tiles on display 6 (below sprites), balls on 4, pixel HUD on 2, text on 3
	sheet = Image.create(128, 128, "#80C0FFFF")
	td = new TileDisplay
	td.tileSet = sheet; td.tileSetTileSize = 32; td.cellSize = 32
	td.extent = [100, 40]
	display(6).mode = displayMode.tile
	td.clear 5
	td.install 6
	display(4).sprites = makeBalls(500)
	px = display(5)
	text = display(3)
	st = {"n": 0}
	balls = display(4).sprites
	f = function()
		st.n = st.n + 1
		for b in balls; b.update; end for
		td.scrollX = st.n * 2 % 1000
		if st.n % 2 == 0 then text.print "frame " + st.n
		for i in range(1, 20)
			px.line (i*47+st.n)%900, (i*31)%600, (i*47+st.n)%900 + 30, (i*31)%600 + 15, "#FF8000FF", 2
		end for
		px.print "N " + st.n, 10, 610, "#FFFFFFFF"
	end function
	perf.frames "scn5_everything", 1, @f, nFrames, 10
	perf.resources "scn5-end"
	Sound.StopAll
	clear
end if

perf.finish "perf_results/perf_scenarios.run" + runIdx + ".csv"
