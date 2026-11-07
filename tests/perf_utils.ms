// perf_utils.ms -- PERF_TEST_PLAN.md §4.13 scaling micro-benchmarks for the
// Tier C utility modules.  One-shot timing per size (large inputs are slow),
// so look at how cost grows with size, not at the absolute noise floor.
// Usage (from tests/): ../../raylib-miniscript/build-release/raylib-miniscript perf_utils.ms [runIndex]
import "perfHarness"
import "json"
import "grfon"
import "tsv"
import "base64"
import "listUtil"
import "stringUtil"
import "matrixUtil"

runIdx = "1"
if shellArgs.len > 1 then runIdx = shellArgs[1]

// Time one call (twice if it is quick) and report the best, in ms.
once = function(bench, param, f)
	best = null
	for rep in [1, 2]
		t0 = time
		f
		dt = time - t0
		if best == null or dt < best then best = dt
		if dt > 0.5 then break
	end for
	line = ["RESULT", bench, param, "once", round(best*1000, 3), "", "", ""].join(",")
	print line; perf.lines.push line
end function

// --- json / grfon on ~1 KB, 100 KB, 1 MB documents ---
makeDoc = function(targetBytes)
	items = []
	i = 0
	size = 0
	while size < targetBytes
		item = {"id": i, "name": "item number " + i, "price": i * 1.25 + 0.5,
		        "tags": ["red", "green", "blue"], "ok": i % 2 == 0, "nested": {"a": i, "b": "x"}}
		items.push item
		size = size + 120
		i = i + 1
	end while
	return items
end function

for target in [1000, 100000, 1000000]
	doc = makeDoc(target)
	js = json.toJSON(doc)
	gr = grfon.toGRFON(doc)
	param = js.len
	once "json_toJSON", param, function(); s = json.toJSON(doc); end function
	once "json_parse", param, function(); v = json.parse(js); end function
	once "grfon_toGRFON", gr.len, function(); s = grfon.toGRFON(doc); end function
	once "grfon_parse", gr.len, function(); v = grfon.parse(gr); end function
end for

// --- tsv, 10 000 rows ---
TAB = char(9)
for rows in [100, 1000, 10000]
	lines = ["id" + TAB + "name" + TAB + "score" + TAB + "note"]
	for i in range(1, rows)
		lines.push i + TAB + "name" + i + TAB + (i * 3.5) + TAB + "some text here"
	end for
	text = lines.join(char(10))
	once "tsv_parse_rows", rows, function(); v = tsv.parse(text); end function
	once "tsv_parseLines_keyed", rows, function(); v = tsv.parseLines(lines, false); end function
end for

// --- base64 on 1 MB ---
for n in [1000, 100000, 1000000]
	b64 = "QUJD" * floor(n / 3)
	once "base64_toRaw", b64.len, function(); r = base64.toRaw(b64); end function
	once "base64_toString", b64.len, function(); r = base64.toString(b64); end function
end for

// --- listUtil on 1e4 and 1e5 elements ---
for n in [10000, 100000]
	nums = []
	for i in range(1, n); nums.push (i * 7919) % 1000; end for
	once "list_sort(native)", n, function(); c = nums[:]; c.sort; end function
	once "list_shuffle(native)", n, function(); c = nums[:]; c.shuffle; end function
	once "list_distinct", n, function(); r = nums.distinct; end function
	once "list_counts", n, function(); r = nums.counts; end function
	once "list_reversed", n, function(); r = nums.reversed; end function
	once "list_filtered", n, function(); r = nums.filtered(function(x); return x > 500; end function); end function
	once "list_applied", n, function(); r = nums.applied(function(x); return x + 1; end function); end function
	once "list_mean", n, function(); r = nums.mean; end function
	once "list_removeVal_all", n, function(); c = nums[:]; c.removeVal 7, true; end function
	once "list_contains_miss", n, function(); r = nums.contains(-1); end function
end for

// --- stringUtil on large text ---
words = "lorem ipsum dolor sit amet consectetur adipiscing elit sed do eiusmod tempor".split
for n in [1000, 10000, 100000, 400000]
	parts = []
	size = 0
	while size < n
		w = words[parts.len % words.len]
		parts.push w
		size = size + w.len + 1
	end while
	txt = parts.join(" ")
	once "string_wrap67", txt.len, function(); r = txt.wrap(67); end function
	once "string_splitLines", txt.len, function(); r = txt.splitLines; end function
	once "string_compress", txt.len, function(); r = (txt + "      " + txt).compress; end function
	once "string_trim", txt.len, function(); r = (("    " + txt) + "    ").trim; end function
	once "string_reverse", txt.len, function(); r = txt.reverse; end function
end for
for n in [100, 1000]
	a = ("abcdefghij" * n)[:n]; b = ("bcdefghija" * n)[:n]
	once "string_editDistance", n, function(); r = a.editDistance(b); end function
end for

// --- matrixUtil ---
for n in [10, 100]
	rows = []
	for i in range(1, n)
		row = []
		for j in range(1, n); row.push (i * j) % 7; end for
		rows.push row
	end for
	A = Matrix.fromList(rows)
	once "matrix_times", n, function(); C = A.times(A); end function
	once "matrix_transposed", n, function(); C = A.transposed; end function
	once "matrix_fromList", n, function(); C = Matrix.fromList(rows); end function
end for

perf.finish "perf_results/perf_utils.run" + runIdx + ".csv"
