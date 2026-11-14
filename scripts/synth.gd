extends RefCounted
class_name Synth

const RATE := 22050


static func _to_wav(samples: PackedFloat32Array, loop: bool) -> AudioStreamWAV:
	var data := PackedByteArray()
	data.resize(samples.size() * 2)
	for i in samples.size():
		data.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 32767.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.stereo = false
	w.data = data
	if loop:
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_begin = 0
		w.loop_end = samples.size()
	return w


static func engine() -> AudioStreamWAV:
	var count := int(RATE * 1.0)
	var samples := PackedFloat32Array()
	samples.resize(count)
	for i in count:
		var t := float(i) / RATE
		var v := 0.40 * sin(TAU * 55.0 * t)
		v += 0.24 * sin(TAU * 110.0 * t + 0.4)
		v += 0.14 * sin(TAU * 165.0 * t + 1.1)
		v += 0.07 * sin(TAU * 220.0 * t + 2.0)
		v += 0.04 * sin(TAU * 330.0 * t + 0.3)
		v *= 0.85 + 0.15 * sin(TAU * 55.0 * t * 0.5 + 0.7)
		samples[i] = v * 0.7
	return _to_wav(samples, true)


static func rumble() -> AudioStreamWAV:
	var count := int(RATE * 4.0)
	var samples := PackedFloat32Array()
	samples.resize(count)
	for i in count:
		var t := float(i) / RATE
		var v := 0.34 * sin(TAU * 38.0 * t)
		v += 0.22 * sin(TAU * 51.0 * t + 1.0)
		v += 0.16 * sin(TAU * 19.0 * t + 2.0)
		v += 0.10 * sin(TAU * 76.0 * t + 0.5)
		v *= 0.62 + 0.38 * sin(TAU * 0.25 * t)
		samples[i] = v * 0.6
	return _to_wav(samples, true)


static func screech() -> AudioStreamWAV:
	var count := int(RATE * 1.0)
	var samples := PackedFloat32Array()
	samples.resize(count)
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	var lp := 0.0
	for i in count:
		var t := float(i) / RATE
		var noise := rng.randf_range(-1.0, 1.0)
		lp = lerpf(lp, noise, 0.35)
		var tone := sin(TAU * 1420.0 * t) * 0.35 + sin(TAU * 2130.0 * t) * 0.2
		var env := 0.6 + 0.4 * sin(TAU * 2.0 * t)
		samples[i] = clampf((lp * 0.35 + tone) * env * 0.5, -1.0, 1.0)
	return _to_wav(samples, true)


static func crash() -> AudioStreamWAV:
	var count := int(RATE * 0.9)
	var samples := PackedFloat32Array()
	samples.resize(count)
	var rng := RandomNumberGenerator.new()
	rng.seed = 991
	for i in count:
		var t := float(i) / RATE
		var noise := rng.randf_range(-1.0, 1.0) * exp(-t * 7.0)
		var thump := sin(TAU * 68.0 * t) * exp(-t * 9.0)
		samples[i] = clampf(noise * 0.55 + thump * 0.55, -1.0, 1.0)
	return _to_wav(samples, false)


static func collapse() -> AudioStreamWAV:
	var count := int(RATE * 1.8)
	var samples := PackedFloat32Array()
	samples.resize(count)
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	for i in count:
		var t := float(i) / RATE
		var noise := rng.randf_range(-1.0, 1.0) * 0.4 * exp(-t * 2.2)
		var boom := sin(TAU * (58.0 - 18.0 * t) * t) * exp(-t * 1.4) * 0.55
		var grit := sin(TAU * 23.0 * t) * 0.2 * exp(-t * 1.0)
		samples[i] = clampf(noise + boom + grit, -1.0, 1.0)
	return _to_wav(samples, false)


static func chime() -> AudioStreamWAV:
	var count := int(RATE * 1.1)
	var samples := PackedFloat32Array()
	samples.resize(count)
	var notes := [523.25, 659.25, 783.99]
	for i in count:
		var t := float(i) / RATE
		var v := 0.0
		for n in notes.size():
			var start := float(n) * 0.09
			if t > start:
				var lt := t - start
				v += sin(TAU * notes[n] * lt) * exp(-lt * 4.5) * 0.28
		samples[i] = clampf(v, -1.0, 1.0)
	return _to_wav(samples, false)


static func music() -> AudioStreamWAV:
	var count := int(RATE * 8.0)
	var samples := PackedFloat32Array()
	samples.resize(count)
	var roots := [55.0, 55.0, 65.41, 49.0]
	for i in count:
		var t := float(i) / RATE
		var bar := int(t / 2.0) % roots.size()
		var f: float = roots[bar]
		var local := fmod(t, 2.0)
		var v := 0.30 * sin(TAU * f * t)
		v += 0.16 * sin(TAU * f * 2.0 * t + 0.3)
		v += 0.09 * sin(TAU * f * 3.0 * t + 1.4)
		var pulse := exp(-local * 5.0) * 0.35 * sin(TAU * f * 0.5 * t)
		var swell := 0.75 + 0.25 * sin(TAU * 0.125 * t)
		samples[i] = clampf((v + pulse) * swell * 0.55, -1.0, 1.0)
	return _to_wav(samples, true)
