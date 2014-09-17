
module.exports = (conn) ->

	writeHeader = () ->
		v = new Buffer 1
		v.writeUInt8 0, 0

		a = new Buffer 1
		a.writeUInt8 0, 0
		header = Buffer.concat [new Buffer("BRPC"), v, a]
		conn.write header
