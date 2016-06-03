module.exports = (System) ->
	System.config do
		map:
			three: './three.js/build/three.js'
		meta:
			'*.ls': loader: 'system-livescript'
			'*.html': loader: 'system-text'
			'*/cannon.js': format: 'cjs'
