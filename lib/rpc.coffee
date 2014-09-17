debug = require('debug') 'birpc:rpc'
ProtoBuf = require 'protobufjs'

{Header, ErrorMessage} = ProtoBuf.loadProtoFile("#{__dirname}/rpc.proto").build()

module.exports = (file, serviceName) ->

	serviceBuilder = ProtoBuf.loadProtoFile file
	throw new Error "Invalid proto file: #{file}" unless serviceBuilder

	delimitBuffer = (buffer) ->
		length = ProtoBuf.ByteBuffer.calculateVarint32 buffer.length
		delimited = new ProtoBuf.ByteBuffer length + buffer.length
		delimited.writeVarint32 buffer.length
		delimited.append buffer
		delimited.clear()
		delimited.toBuffer()

	readDelimited = (payload) ->
		messageLength = payload.readVarint32()
		message = payload.slice payload.offset, payload.offset + messageLength
		payload.offset += messageLength
		message.toBuffer()

	create = (socket, server = yes) ->

		awaitBytes = 0
		buffer = new Buffer 0
		calls = {}
		lastCallId = 0
		handlers = {}

		dataListener = (data) ->
			buffer = Buffer.concat [buffer, data]
			if awaitBytes is 0
				return if buffer.length < 4
				awaitBytes = buffer.readUInt32BE 0
				buffer = buffer.slice 4
				debug "Await bytes: %d", awaitBytes
			return if buffer.length < awaitBytes
			debug "Got whole buffer"
			processMessages buffer.slice 0, awaitBytes
			buffer = buffer.slice awaitBytes
			awaitBytes = 0
			dataListener new Buffer(0) if buffer.length > 1

		handshakeListener = (data) ->
			header = data.slice(0, 4).toString()
			unless header.match 'BRPC'
				debug 'Invalid header: %s', header
				return socket.end()
			debug 'Header received: %s', header
			socket.removeListener 'data', handshakeListener
			socket.on 'data', dataListener
			socket.emit 'handshake'

		if server
			socket.on 'data', handshakeListener
		else
			# <MAGIC 4 byte integer> <1 byte RPC Format Version> <1 byte auth type>
			socket.write Buffer.concat [new Buffer('BRPC'), new Buffer(0x00), new Buffer(0x00)]
			socket.on 'data', dataListener

		socket.on 'end', ->
			console.log 'Socket closed'

		processMessages = (buffer) ->
			payload = ProtoBuf.ByteBuffer.wrap buffer
			header = Header.decode readDelimited payload
			if header.type is Header.Type.REQUEST
				method = serviceBuilder.lookup "#{serviceName}.#{header.method_name}"
				req = method.resolvedRequestType.clazz.decode readDelimited payload
				handlers[header.method_name] req, (e, data) ->
					if e
						resHeader = new Header
							call_id: header.call_id
							type: Header.Type.RESPONSE
							error:
								message: e?.message or e
						return writeMessages [
							resHeader.encode().toBuffer()
						]

					resHeader = new Header
						call_id: header.call_id
						type: Header.Type.RESPONSE

					resData = new method.resolvedResponseType.clazz data

					writeMessages [
						resHeader.encode().toBuffer()
						resData.encode().toBuffer()
					]
			else
				current = calls[header.call_id]
				return console.log "Call #{header.call_id} not found" unless current
				delete calls[header.call_id]
				return current.callback header.error if header.error
				current.callback null, current.clazz.decode readDelimited payload

		writeMessages = (buffers) ->
			messages = Buffer.concat (delimitBuffer b for b in buffers)
			length = new Buffer 4
			length.writeInt32BE messages.length, 0
			socket.write length
			socket.write messages

		service = serviceBuilder.lookup serviceName

		client = new service.clazz (methodName, reqData, callback) ->

			method = serviceBuilder.lookup methodName

			reqHeader = new Header
				call_id: lastCallId++
				type: Header.Type.REQUEST
				method_name: method.name

			calls[reqHeader.call_id] =
				clazz: method.resolvedResponseType.clazz
				callback: callback

			writeMessages [
				reqHeader.encode().toBuffer()
				reqData.encode().toBuffer()
			]

		out = {}

		service.children.forEach (child) ->
			out[child.name] = (req, done) ->
				clazz = child.resolvedRequestType.clazz
				req = new clazz req unless req instanceof clazz
				client[child.name] req, done

		out.handle = (name, callback) ->
			handlers[name] = callback

		out

	createClient: (socket) ->
		create socket, no

	createServer: (socket) ->
		create socket
