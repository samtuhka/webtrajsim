#!/usr/bin/env lsc

{map, merge} = require 'prelude-ls'
require! cheerio
require! rw
P = require \bluebird
require! webpack

#new webpack.ProvidePlugin do
#	three: './three.js/build/three.js'

webpackConfig =
	module:
		loaders:
			* test: /\.ls$/, loader: 'livescript-loader'
			* test: /\.coffee$/, loader: 'coffee-loader'
			* test: /\.css$/, loader: "style-loader!css-loader"
	resolve:
		alias:
			three: './three.js/build/three.js'
	#devtool: "inline-source-map"

webpackFile = (src, dst, config=webpackConfig) ->
	config =  webpackConfig with
		entry: src
		output: filename: dst
	new P (accept, reject) ->
		webpack(config).run (err, result) ->
			# The err flag doesn't seem to work
			if err?
				return reject err
			if result.compilation.errors.length > 0
				return reject result.compilation.errors
			accept dst
manglers =
	script: (data, opts) ->
		$ = cheerio.load data
		els = [$(e) for e in $("script[type!='text/javascript']")]
		P.each els, (e) ->
			if not (src = e.attr \src)?
				throw "Unable to currently handle inline scripts"
			#str = LiveScript.compile e.text!
			#browserifyString str
			webpackFile src, src+".js"
			.then (file) ->
				e.attr \src, file
				e.attr \type, "text/javascript"
		.then -> $.html!

insanify = (data, manglers_=manglers) ->
	orig = data
	p = P.resolve(data)
	for let name, mangler of manglers_
		p := p.then (d) -> mangler d

	p.then (data) ->
		return data if data == orig
		insanify data, manglers

if not module.parent
	if escape_my_crappy_bugs = process.argv[2]
		eval rw.readFileSync escape_my_crappy_bugs, 'utf-8'
	sane = rw.readFileSync '/dev/stdin', 'utf-8'
	insanify sane .then (insane) ->
		rw.writeFileSync '/dev/stdout', insane
