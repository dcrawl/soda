// perf_sound.ms -- PERF_TEST_PLAN.md §4.9 workloads (Sound.ms).
// Usage (from tests/): ../../raylib-miniscript/build-release/raylib-miniscript perf_sound.ms [runIndex]
import "perfHarness"
import "soda"

runIdx = "1"
if shellArgs.len > 1 then runIdx = shellArgs[1]

// S-A1: synthesis cost (lazy, happens on first play) for 0.1, 1, 5 s
for dur in [0.1, 1, 5]
	perf.timeit "snd_synth", dur, function()
		s = new Sound
		s.init dur, 440, [1, 0]
		x = s._buildSamples
	end function, 2
end for

// with mixes (2 and 8 sub-sounds), 1 s each
for k in [2, 8]
	perf.timeit "snd_synth_mix", k, function()
		s = new Sound
		s.init 1, 440, [1, 0]
		for i in range(2, k)
			m = new Sound
			m.init 1, 220 * i, [1, 0]
			s.mix m, 0.5
		end for
		x = s._buildSamples
	end function, 1
end for

// first play (includes synthesis + load) vs replay
s1 = new Sound
s1.init 1, 440, [1, 0]
t0 = time
s1.play 0.01
perf.lines.push "RESULT,snd_firstPlay_1s,1,once," + (round((time - t0) * 1000, 4)) + ",0,0,0"
print perf.lines[-1]
s1.stop
perf.timeit "snd_replay", 1, function(); s1.play 0.01; s1.stop; end function, 300

// S-A2: parameter setters re-invalidate
perf.timeit "snd_setter_freq", 1, function(); s1.freq = 440; end function, 2000

// UpdateAll with 0, 10, 100 playing sounds
sounds = []
for n in [0, 10, 100]
	Sound.StopAll
	while sounds.len < n
		sn = new Sound
		sn.init 0.2, 300 + sounds.len, [1, 0]
		sn.loop = true
		sn.play 0.0
		sounds.push sn
	end while
	perf.timeit "snd_updateAll", n, function(); Sound.UpdateAll; end function, 200
end for
Sound.StopAll

// rapid re-trigger of one sound (balls.ms pattern)
perf.timeit "snd_retrigger", 1, function(); s1.play 0.0; end function, 500
Sound.StopAll

perf.finish "perf_results/perf_sound.run" + runIdx + ".csv"
