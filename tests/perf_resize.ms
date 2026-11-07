// perf_resize.ms -- PERF_TEST_PLAN.md §6: window resize / fullscreen toggle / display-mode
// switches while a busy scene renders. Usage: perf_resize.ms runTag mode frames
// modes: resize | fullscreen | modes | rendersprites
import "perfHarness"
import "soda"
mode = shellArgs[2]; F = val(shellArgs[3])
img = Image.create(32, 32, "#40C0FFFF")
sprs = []
for i in range(1, 2000)
	s = new Sprite; s.image = img; s.x = 30 + (i*37)%900; s.y = 30 + (i*53)%580
	s.rotation = i; sprs.push s
end for
display(4).sprites = sprs
sheet = Image.create(128, 128, "#80C0FFFF")
td = new TileDisplay
td.tileSet = sheet; td.tileSetTileSize = 32; td.cellSize = 32; td.extent = [100, 40]
display(6).mode = displayMode.tile
td.clear 5; td.install 6
px = display(5); text = display(3)
perf.resources "mode=" + mode + ",start"
sizes = [[960,640],[640,480],[1200,800],[320,240],[960,640],[1920,1080],[800,600]]
for n in range(1, F)
	if mode == "resize" and n % 5 == 0 then
		sz = sizes[(n / 5) % sizes.len]
		raylib.SetWindowSize sz[0], sz[1]
	end if
	if mode == "fullscreen" and n % 30 == 0 then window.fullScreen = not window.fullScreen
	if mode == "modes" then
		d = display(1 + n % 6)
		if n % 7 == 0 then d.mode = displayMode.off
		if n % 7 == 3 then d.mode = [displayMode.solidColor, displayMode.text, displayMode.pixel, displayMode.sprite, displayMode.tile, displayMode.pixel][(n / 7) % 6]
	end if
	if mode == "rendersprites" then
		// create + drop 200 fresh sprites (with fresh images every 10th frame) each frame, rendered
		fresh = []
		for i in range(1, 200)
			s = new Sprite
			if n % 10 == 0 then s.image = Image.create(16, 16, "#FF00FFFF") else s.image = img
			s.x = (i*37 + n) % 900; s.y = (i*53) % 600
			fresh.push s
		end for
		display(4).sprites = fresh
	end if
	td.scrollX = n * 2 % 1000
	if n % 2 == 0 then text.print "frame " + n
	for i in range(1, 10); px.line (i*47+n)%900, (i*31)%600, (i*47+n)%900 + 30, (i*31)%600 + 15, "#FF8000FF", 2; end for
	px.print "N " + n, 10, 610, "#FFFFFFFF"
	for sp in sprs; sp.rotation = sp.rotation + 1; end for
	if n % 100 == 0 then perf.resources "mode=" + mode + ",frame=" + n + ",size=" + raylib.GetScreenWidth + "x" + raylib.GetScreenHeight
	yield
end for
if window.fullScreen then window.fullScreen = false
perf.resources "mode=" + mode + ",end,frames=" + F
print "DONE " + mode
exit
