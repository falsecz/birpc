testRPC = require('../lib/index') "#{__dirname}/example.proto", 'TestRPC'

server = testRPC.createServer (e, rpc) ->
	rpc.handle 'test', (req, callback) ->
		callback null, response: 1337
	console.log 'socket connected'

server.listen 1234, ->
	console.log 'fistening'
