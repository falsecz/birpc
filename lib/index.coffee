net = require 'net'

module.exports = (protoFile, protoService) ->

	rpc = require('./rpc') protoFile, protoService

	connect: (port, host, callback) ->
		socket = net.connect port, host, ->
			callback null, rpc.createClient socket

	createServer: (callback) ->
		net.createServer (socket) ->
			server = rpc.createServer socket
			socket.on 'handshake', ->
				callback null, server
