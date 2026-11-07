// perf_leakbis.ms -- bisect hostMemory growth. Usage: perf_leakbis.ms runTag mode seconds
// modes: empty | line | print | clear | rawline (rl.DrawLineEx into the display texture) | linebatch
import "perfHarness"
import "soda"
mode = shellArgs[2]; D = val(shellArgs[3])
px = display(5)
n = 0; start = time; nextLog = start + 30
perf.resources "mode=" + mode + ",t=0"
while time - start < D
	n = n + 1
	i = n % 20
	if mode == "line" then px.line (i*47+n)%900, (i*31)%600, (i*47+n)%900 + 30, (i*31)%600 + 15, "#FF8000FF", 2
	if mode == "print" then px.print "N " + n, 10, 610, "#FFFFFFFF"
	if mode == "clear" then px.clear "#00000000"
	if mode == "code" then
		for ch in "N 1234"; c = ch.code; end for
	end if
	if mode == "loadFont" then f = PixelDisplay._loadFont("normal")
	if mode == "drawChar" then
		px._beginDraw true
		PixelDisplay._loadFont("normal").drawChar 65, 10, 10, "#FFFFFFFF", "#00000000"
		px._endDraw
	end if
	if mode == "tex" then
		px._beginDraw true
		f = PixelDisplay._loadFont("normal")
		raylib.DrawTexturePro f.texture, [0,0,16,24], [10,10,16,24], [0,0], 0, [255,255,255,255]
		px._endDraw
	end if
	if mode == "concat" then t = "N " + n
	if mode == "concatIter" then
		t = "N " + n
		for ch in t; c = ch; end for
	end if
	if mode == "printConst" then px.print "N 12345", 10, 610, "#FFFFFFFF"
	if mode == "printSpaces" then px.print "          ", 10, 610, "#FFFFFFFF"
	if mode == "printVar" then px.print "N " + n, 10, 610, "#FFFFFFFF"
	if mode == "concatFullGC" then
		t = "N " + n
		if n % 2000 == 0 then gc.collect true
	end if
	if mode == "concatGC" then
		t = "N " + n
		if n % 2000 == 0 then gc.collect
	end if
	if mode == "rawline" then
		raylib.BeginDrawing
		raylib.DrawLineEx [10,10], [100,50], 2, "#FF8000FF"
		raylib.EndDrawing
	end if
	if mode == "linebatch" then
		px.beginBatch
		px.line 10, 10, 100, 50, "#FF8000FF", 2
		px.endBatch
	end if
	if time >= nextLog then
		perf.resources "mode=" + mode + ",t=" + round(time - start) + ",frames=" + n
		nextLog = nextLog + 30
	end if
	yield
end while
perf.resources "mode=" + mode + ",end,frames=" + n
exit
