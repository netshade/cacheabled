$memcached = MemCache.new 'localhost:11211'

module Cacheable

  def self.acquire_lock(cache_key)
    $memcached.add("lock:#{cache_key}", true, 10).chomp == "STORED"
  end

  # class << self
  #   def cache_key_for_with_inspection(obj)
  #     result = cache_key_for_without_inspection(obj)
  #     puts "INSPECTION: %s" % result
  #     result
  #   end
  #   alias_method_chain :cache_key_for, :inspection
  # end

end
