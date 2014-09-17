testRPC = require('../lib/index') "#{__dirname}/test.proto", 'TestRPC'

describe 'RPC', ->

	server = testRPC.createServer()
	server.listen 1234, ->
		console.log 'fistening'

	testRPC.connect 1234, 'localhost', ->
		console.log 'connected'

	it 'x', ->

