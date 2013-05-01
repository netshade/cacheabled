class Marshal

  @sizeOfLong = 4

  @_valueFrom:(str, position, context = {})->
    if position >= str.length
      throw new Error("Position #{position} outside buffer boundary #{str.length}")
    eval_char = String.fromCharCode(str[position])
    switch eval_char
      when '0' # nil
        [null, 1]
      when 'T' # 'T', true
        [true, 1]
      when 'F' # false
        [false, 1]
      when 'i' # int
        [v, len] = @_decodeInt(str, position + 1, context)
        [v, len + 1]
      when '['
        [v, len] = @_decodeArray(str, position + 1, context)
        [v, len + 1]
      when '{'
        [v, len] = @_decodeHash(str, position + 1, context)
        [v, len + 1]
      when ':'
        [v, len] = @_decodeSymbol(str, position + 1, context)
        [v, len + 1]
      when ';'
        [v, len] = @_decodeSymbolLookup(str, position + 1, context)
        [v, len + 1]
      when 'I'
        [v, len] = @_valueFrom(str, position + 1, context)
        [v, len + 1]
      when '"'
        [v, len] = @_decodeString(str, position + 1, context)
        [v, len + 1]
      when '@'
        [v, len] = @_decodeObjectLookup(str, position + 1, context)
        [v, len + 1]
      when 'o'
        [v, len] = @_decodeUserObject(str, position + 1, context)
        [v, len + 1]
      when 'f'
        [v, len] = @_decodeFloat(str, position + 1, context)
        [v, len + 1]
      when '/'
        [v, len] = @_decodeRegex(str, position + 1, context)
        [v, len + 1]
      when 'l'
        [v, len] = @_decodeBignum(str, position + 1, context)
        [v, len + 1]
      else
        throw new Error("Could not decode type #{String.fromCharCode(str[position])} / #{str[position]}")

  @_decodeInt:(str, position, context)->
    code = str.readInt8(position)
    if code == 0
      return [0, 1]
    if code > 0
      if 4 < code && code < 128
        return [code - 5, 1]
      throw new Error("Num too big, #{str[position]} / #{code} bytes large") if code > @sizeOfLong
      shift = 0
      n = 0
      start = position + 1
      for i in [start...start+code]
        n |= (str.readUInt8(i) << shift)
        shift += 8
      return [n, code + 1]
    else
      if -129 < code && code < -4
        return [code + 5, 1]
      code = -code
      throw new Error("Num too big, #{str[position]} / #{code} bytes large") if code > @sizeOfLong
      n = -1
      shift = 0
      start = position + 1
      for i in [start...start+code]
        n &= ~(0xff << shift)
        n |= (str.readUInt8(i) << shift)
        shift += 8
      return [n, code + 1]

  @_decodeArray:(str, position, context)->
    context.object_cache ||= []
    [len, offset] = @_decodeInt(str, position, context)
    result = []
    context.object_cache.push(result)
    offset += position
    for i in [0...len]
      if pair = @_valueFrom(str, offset, context)
        [v, vlen] = pair
        offset += vlen
        result.push(v)
      else
        throw new Error("Expected array to contain #{len} elements, failed to find element at index #{i}")
    [result, offset - position]

  @_decodeHash:(str, position, context)->
    context.object_cache ||= []
    [len, offset] = @_decodeInt(str, position, context)
    result = {}
    context.object_cache.push(result)
    offset += position
    for i in [0...len]
      if keypair = @_valueFrom(str, offset, context)
        [key, keylen] = keypair
        offset += keylen
        if valuepair = @_valueFrom(str, offset, context)
          [value, valuelen] = valuepair
          offset += valuelen
          result[key] = value
        else
          throw new Error("Couldn't find matching value for key #{key}")
      else
        throw new Error("Couldn't find key #{i}")
    return [result, (offset - position)]

  @_decodeIvars:(str, position, context)->
    context.object_cache ||= []
    return [{}, 0] if position >= str.length
    [len, offset] = @_decodeInt(str, position, context)
    result = {}
    offset += position
    for i in [0...len]
      if keypair = @_valueFrom(str, offset, context)
        [key, keylen] = keypair
        offset += keylen
        if valuepair = @_valueFrom(str, offset, context)
          [value, valuelen] = valuepair
          offset += valuelen
          result[key.replace(/^\:\@/, "")] = value
        else
          throw new Error("Couldn't find matching value for key #{key}")
      else
        throw new Error("Couldn't find key #{i}")
    return [result, (offset - position)]

  @_decodeSymbol:(str, position, context)->
    context.symbol_cache ||= []
    [len, offset] = @_decodeInt(str, position, context)
    result = str.slice(position + offset, position + offset + len).toString("utf8")
    result = ":" + result # not so sure about this choice
    context.symbol_cache.push(result)
    [result, len + offset]

  @_decodeSymbolLookup:(str, position, context)->
    [idx, offset] = @_decodeInt(str, position, context)
    if !context.symbol_cache
      throw new Error("Can't lookup symbol #{idx}, no symbol cache")
    if !context.symbol_cache[idx]
      throw new Error("Symbol lookup #{idx} does not exist")
    [context.symbol_cache[idx], offset]

  @_decodeString:(str, position, context)->
    context.object_cache ||= []
    [len, offset] = @_decodeInt(str, position, context)
    result = str.slice(position + offset, position + offset + len)
    idx = context.object_cache.length
    context.object_cache.push(result)
    [ivars, ivaroffset] = @_decodeIvars(str, position + offset + len, context)
    unless context.strings_as_buffers
      if ivars[":E"] == true
        result = result.toString("utf8")
      else if ivars[":E"] == false
        result = result.toString("ascii")
      else if ivars[":encoding"]
        throw new Error("Can't decode string of encoding #{ivars[':encoding']}")
      else
        result = result.toString("ascii")
    context.object_cache[idx] = result
    for k, v of ivars
      result[k] = v
    [result, offset + len + ivaroffset]

  @_decodeObjectLookup:(str, position, context)->
    [idx, offset] = @_decodeInt(str, position, context)
    if !context.object_cache
      throw new Error("Can't lookup object #{idx}, no object cache")
    if !context.object_cache[idx]
      throw new Error("Object lookup #{idx} does not exist")
    [context.object_cache[idx], offset]

  @_decodeUserObject:(str, position, context)->
    context.object_cache ||= []
    [klass, offset] = @_valueFrom(str, position, context)
    result = { '__ruby_class__' : klass }
    context.object_cache.push(result)
    [ivars, ivaroffset] = @_decodeIvars(str, position + offset, context)
    for k, v of ivars
      result[k] = v
    [result, offset + ivaroffset + 1]

  @_decodeFloat:(str, position, context)->
    [len, offset] = @_decodeInt(str, position, context)
    result = str.slice(position + offset, position + offset + len).toString("ascii")
    if result == "inf"
      [Number.POSITIVE_INFINITY, offset + len]
    else if result == "-inf"
      [Number.NEGATIVE_INFINITY, offset + len]
    else if result == "nan"
      [Number.NaN, offset + len]
    else
      [parseFloat(result), offset + len]

  @_decodeRegex:(str, position, context)->
    [result, offset] = @_decodeString(str, position, context)
    [new RegExp(result), offset + 1]

  @_decodeBignum:(str, position, context)->
    sign = if String.fromCharCode(str[position]) == '+'
      1
    else
      -1
    position += 1
    [len, offset] = @_decodeInt(str, position, context)
    console.log("WARNING: BigNum not implemented yet") unless context.silent
    [0, offset + 1]

  @load:(buffer, options = {})->
    major = buffer[0]
    minor = buffer[1]
    stream = buffer.slice(2, buffer.length)
    position = 0
    context = null

    pair = @_valueFrom(stream, 0, options)
    v = undefined
    if pair
      [v, _] = pair
    v



module.exports = Marshal
