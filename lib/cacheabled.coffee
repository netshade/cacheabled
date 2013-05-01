MemJS = require('memjs')
Crypto = require("crypto")
Marshal = require("./marshal")
CityHash = require("cityhash")
zlib = require("zlib")
HttpProxy = require("http-proxy")
http = require("http")
url = require('url')

require('nodetime').profile({
    accountKey: '989753323a84d8c01fb9c17bbff1fd4a24ac1137',
    appName: 'cacheabled'
})

class Server

  constructor:(@config = {})->
    # pass
    console.log("Starting up with", @config)
    @endpoints = @config.endpoints
    @clients = []
    for i in [0... (@config?.memcache?.poolSize || 10)]
      @clients.push(MemJS.Client.create(@config?.memcache?.servers || ""))
    @request_backlog = @config.request_backlog || 65536
    @bind_address = @config.bind_address || "0.0.0.0"
    @port = @config.port || 1337
    @proxy = new HttpProxy.RoutingProxy()

  start:()=>
    @server = http.createServer(@_httpListen)
    @server.listen(@port, @bind_address, @request_backlog, ()=>
      console.log("Listening on #{@port}")
    )

  version:()=>
    "0.0.1"

  responseHeaders:(merge_with = {})=>
    headers =
      "X-Served-By": "cacheabled #{@version()}"
    for k, v of merge_with
      headers[k] = v
    headers

  randomEndpoint:()=>
    shuffled = Math.floor(Math.random() * @endpoints.length)
    @endpoints[shuffled]

  randomMemcacheClient:()=>
    shuffled = Math.floor(Math.random() * @clients.length)
    @clients[shuffled]

  forwardToEndpoint:(request, response)=>
    endpoint = @randomEndpoint()
    console.log("Forwarding #{request.url} to endpoint #{endpoint.host}:#{endpoint.port}")
    @proxy.proxyRequest(request, response, endpoint)

  sendResponse:(payload, request, response)=>
    if payload.__ruby_class__ == ':ActiveSupport::Cache::Entry'
      payload = Marshal.load(new Buffer(payload.value), { "strings_as_buffers": true })
    [status, content_type, body, timestamp, location] = payload
    gzip = String(request.headers["accept-encoding"]).indexOf("gzip") >= 0
    if !gzip
      zlib.gunzip(body, (err, uncompressed_body)=>
        if err
          console.log("Error decompressing content", body)
          console.log(err.stack)
          @forwardToEndpoint(request, response)
        else
          @_sendResponse([status, content_type, uncompressed_body, timestamp, location], request, response)
      )
    else
      response.setHeader("Content-Encoding", "gzip")
      @_sendResponse(payload, request, response, true)

  _sendResponse:(payload, request, response, gzip = false)=>
    [status, content_type, body, timestamp, location] = payload
    response.status = status
    response.setHeader("Content-Type", content_type.toString("ascii"))
    response.setHeader("Location", location.toString("ascii")) if location
    response.setHeader("X-Served-By", "cacheabled #{@version()}")
    response.end(body)


  hashKey:(request_url)=>
    url_info = url.parse(request_url)
    key_hash = {
      "key": {
        "request": {
          "env": {
            "PATH_INFO": url_info.pathname,
            "QUERY_STRING": (url_info.query || "")
          }
        }
      },
      "version": {}
    }
    # sorry
    inspected = JSON.stringify(key_hash).replace(/\:/g, "=>")
                                        .replace(/([^\s]),([^\s])/g, "$1, $2")
                                        .replace('"key"', ":key")
                                        .replace('"version"', ":version")
    hash = CityHash.hash128(inspected)
    key = hash.low.value + hash.high.value
    "cachable:#{key}"

  _httpListen:(request, response)=>
    key = @hashKey(request.url)
    if request.headers["if-none-match"]
      if key == request.headers["if-none-match"]
        console.log("Cache hit: client")
        response.writeHead(304, @responseHeaders(
          "cacheable-miss": false,
          "cacheable-store": "client",
        ))
        response.end("")
        return
    d = new Date().getTime()
    console.log("Getting memcache", request.url, key)
    @randomMemcacheClient().get(key, (err, result, extras)=>
      console.log("Memcache response, took (ms)", new Date().getTime() - d)
      if err
        @forwardToEndpoint(request, response)
      else
        try
          console.log("Server hit", key)
          payload = Marshal.load(result, { "strings_as_buffers": true })
          @sendResponse(payload, request, response)
        catch err
          console.log("Error serving from cache", key, err)
          console.log(err.stack)
          @forwardToEndpoint(request, response)

    )


module.exports = Server
