#!/usr/bin/env ruby

def write_info(desc, value, file)
  val = Marshal.dump(value)
  file.write([val.size].pack("I"))
  file.write(val)
  file.write(desc)
  file.write("\r")
end

class Foo
  attr_accessor :bar

  def initialize()
    @bar = "blargh"
    @bzar = "bazaar"
    @sym = :foo
    @num = 23.2382
    @true = true
  end
end

f = File.new("marshal.#{RUBY_VERSION}.txt", "wb")

write_info("true", true, f)
write_info("false", false, f)
write_info("zero", 0, f)
write_info("small int", 10, f)
write_info("small negative int", -20, f)
write_info("larger int", 108, f)
write_info("very large int", 20_000, f)
write_info("larger negative int", -115, f)
write_info("very large negative int", -12_583, f)
write_info("nil", nil, f)
write_info("array of numbers", [1,2,3], f)
write_info("array of very large numbers", [20_000, 12_2832, -128_328], f)
write_info("mixed array", [212_283, true, nil, false], f)
write_info("hash", { 12 => true, 24 => nil}, f)
write_info("hash with array", { 12 => [1,2,3], 24 => [4,5,true] }, f)
write_info("array with hashes and arrays", [{ 22 => [2,2] }, 24, [1,2,3]], f)
write_info("symbol", :foo, f)
write_info("array with symbols", [:foo, :bar, :baz], f)
write_info("symbol multiple times", [:foo, :foo, :foo, :bar, :foo], f)
write_info("ascii string test", "foo", f)
write_info("utf-8 string test", "foo".force_encoding("UTF-8"), f)
write_info("US-ASCII forced string test", "foo".force_encoding("US-ASCII"), f)
a = "foo"
write_info("string multiple times", [a, a, a, 2], f)
write_info("hash with string keys", { "foo" => ["bar", 1], "baz" => [nil, true, 20_000, "hello"]}, f)
write_info("regexp", /asdf/, f)
write_info("float", 23.023, f)
write_info("big float", 121821812.23023, f)
write_info("user object", Foo.new, f)
write_info("bignum", 100_000_000_0000_0000_0000_000_000_000, f)
write_info("SHIFT_JIS string test", "foo".force_encoding("SHIFT_JIS"), f)
f.close
