Proof of concept node.js frontend for exploiting fully cached responses from cacheable <https://github.com/shopify/cacheable>

# Background

Shopify's scaling presentation spoke about how they use the cacheable library to cache full page responses; they put `Marshal#dump`'d compressed page data, location and status codes into MemCache, which they would later retrieve.   Discussion w/ a Shopify rep showed that they had roughly 60% of their responses served via this method.

I was surprised to learn that they were doing this inside the Rails stack (well, realistically, Rack) - or even, really, that they were hitting Unicorn for this.  If 60% of the requests coming in can be served without even occupying a Unicorn worker ( which involves the socket IO to the unicorn process, which in turn talks to a worker, etc. ), that seems like a relatively large win.

So I wrote a proof of concept node.js app that does just that. It would sit in front of a unicorn process, and serve directly from cache when relevant; otherwise, it proxies the request to the unicorn instance, and the cacheable gem's normal behavior can resume.

As expected, the speedup (/local benchmarking, I know, I know/) is drastic.  For a trivial URL, requests can be served up to 140x faster simply by exploiting concurrent reqeust handling and memcache fetching in node.js.  EventMachine could be used to do something quite similar (though likely with slightly less of a speed up).

This is not a bolt in speedup.  Cacheable has enough assumptions about keys, versions and stale data in it that there would need to be some work such that cache info can be shared outside the process. Also, Cacheable uses Marshal to serialize data; I've written a toy implementation of `Marshal#load` in JavaScript, but really, something not Ruby specific would be more desirable (/JSON, really, since most of node.js' MemCache clients seem to think that all MemCache data is UTF-8 strings/).

# Why

Well, really, if you're caching the effective full response, there's no reason to ever hit the stack or occupy a worker.  Getting the Memcache data closer to the Nginx response will maximize availability of the app. On my machine (/I KNOW ALREADY, SHEESH/), which is a 2011 MBP Pro, 2.3Ghz Core i7:

Rails (Unicorn, 7 workers), time to complete:

 * 100 Requests: 9.16sec
 * 1,000 Requests: 88.07sec
 * 10,000 Requests: 869.82sec

Node (1 process), time to complete:

 * 100 Requests: 0.13sec (70x)
 * 1,000 Requests: 0.72sec (122x)
 * 10,000 Requests: 6.20sec (140x)

I'm not claiming these increases are authoritative.  Test on production hardware, test over time, test with the implementation that actually respects the caching logic.  There will be slowdown, but the basic principle is, there is a very, very large performance optimization that you could make by writing something (in any language) that worked to get your cached responses to the browser faster and avoid the slow elephant in the room (synchronous Ruby).

And less servers is more money.

# Summary

In this particular case (/there is a super fast cache of a full response that can be inferred via URL paramters/), concurrency is a dead easy win. Thanks for the talk Shopify people, you have a great product, and it was cool to see what you're doing to scale out. Hope this is useful to you in some fashion.

# Contents

`test-app` contains a Rails app that spins up 7 unicorn workers under a single unicorn process, and using cacheable to cache responses
`bin/cacheabled` will start a node.js reverse http proxy that will respond w/ memcache responses if they are in memcache
`./benchmark.rb` wll just run some benchmarks and give you numbers. It takes a while because Ruby.

Run `npm install` before attempting to run


# Special Note Regarding My Marshal Implementation

I wrote it because it seems like a lot of other folks need node.js to read Ruby's Marshal format.  This is not heavily tested, so if you use it, use it with caution.  It should work for `String` (/only ascii or utf8 strings/), `FixNum`, `true`, `false`, `Hash`, `Array`, `RegExp` (/mostly/) and user defined objects (/sort of/). You are encouraged to read the source. It /should/ blow up if it can't deserialize something, it will not ignore errors.

`Marshal.load(buffer)` requires one argument, a `Buffer` object.  If you need the returned strings returned as buffers (in cases where the strings contain binary information and text encoding would fuck it all up), then a second argument may be provided, a hash with `strings_as_buffers` set to `true`.




