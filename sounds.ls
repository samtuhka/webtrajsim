$ = require 'jquery'
P = require 'bluebird'
{sum, sortBy, zip} = require 'prelude-ls'

loadBuffer = (url) -> new Promise (accept, reject) ->
	xhr = new XMLHttpRequest()
	xhr.open('GET', url, true);
	xhr.responseType = 'arraybuffer';

	xhr.onload = (e) ->
		accept xhr.response
	xhr.onerror = (e) ->
		reject e
	xhr.send()

loadAudio = (context, url) ->
	p = loadBuffer url
	p.then (data) -> new Promise (accept, reject) ->
		context.decodeAudioData data, (buffer) ->
			if not buffer
				reject "Failed to decode '#url'"
			source = context.createBufferSource()
			source.buffer = buffer
			accept source

export SoundInterpolator = (ctx, sampleTbl) -> new Promise (accept, reject) ->
	sources = []
	master = ctx.createBiquadFilter()
	master.type = 'lowpass'
	master.frequency.value = 500
	for value, sample of sampleTbl
		sample.loop = 1
		source = ctx.createGain()
		sample.connect source
		source.sample = sample
		sources.push [parseFloat(value), source]
		source.connect master
	sources = sortBy (.0), sources
	master.start = ->
		for [value, source] in sources
			source.sample.start()
	master.stop = ->
		for [value, source] in sources
			source.sample.stop()
	master.setPitch = (pitch) ->
		gains = []
		for [value, source] in sources
			gains.push Math.exp -Math.abs((value - pitch)/1000)
		totalGain = sum gains
		gains = for gain in gains
			gain/totalGain
		for [gain, [value, source]] in zip gains, sources
			source.gain.value = gain
			source.sample.playbackRate.value = pitch/value

	master.setPitch sources[0][0]
	accept master

export DefaultEngineSound = (ctx) ->
	f = (name) -> loadAudio ctx, "./res/sounds/engine/#name.wav"
	P.props do
		400: f 'idle'
		900: f 'low'
		1300: f 'medium'
		1500: f 'high'
	.then (samples) -> SoundInterpolator ctx, samples

