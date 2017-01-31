module.exports = (System) ->
	System.config do
		meta:
			'*.ls': loader: 'system-livescript'
			'*.html': loader: 'system-text'
			'*.json': loader: 'systemjs-plugin-json'
