#!/usr/bin/env ruby
require 'benchmark'
require 'bundler'
Bundler.require(:default)

if `which weighttp`.chomp.empty?
  puts "weighttp not installed, install via 'brew install weighttp'"
end

Process.wait(Process.spawn("cd ./test-app && env BUNDLE_GEMFILE=./Gemfile bundle install", :out => STDOUT))

$foreman_pid = Process.spawn("cd ./test-app &&  env BUNDLE_GEMFILE=./Gemfile bundle exec foreman start", :out => STDOUT, :err => STDERR)
$cacheable_pid = Process.spawn("./bin/cacheabled", :out => STDOUT, :err => STDERR)

def suite(url_map, amounts, thread_count = 5, concurrent = 20)
  suite_results = {}
  url_map.each do |name, url|
    suite_results[name] = {}
    amounts.sort.each do |amount|
      results = benchmark(url, thread_count, concurrent, amount)
      suite_results[name][amount] = {
        :time => results[:time],
        :succeeded => results[:succeeded],
        :failed => results[:failed],
        :errored => results[:errored]
      }
      puts "#{name} time for #{amount} requests, #{thread_count} threads, #{concurrent} concurrent clients: %f"  % results[:time]
    end
  end
  keys = suite_results.values.first.keys.sort
  headings = ["App"] + keys
  puts Terminal::Table.new :headings => headings do |t|
    suite_results.each do |name, amounts|
      t << [name] + amounts.keys.sort.collect do |amount|
        amounts[amount]
      end
    end
  end
end


def benchmark(location, thread_count = 5, concurrent = 10, amount = 100_000)
  output = nil
  exec_time = Benchmark.realtime do
    output = `weighttp -n #{amount} -t #{thread_count} -c #{concurrent} #{location}`.chomp
  end
  succeeded = nil
  failed = nil
  errored = nil
  if output =~ /(\d+) succeeded/i
    succeeded = $1.to_i
  end
  if output =~ /(\d+) failed/i
    failed = $1.to_i
  end
  if output =~ /(\d+) errored/i
    errored = $1.to_i
  end
  {
    :time => exec_time,
    :concurrent => concurrent,
    :amount => amount,
    :thread_count => thread_count,
    :location => location,
    :succeeded => succeeded,
    :failed => failed,
    :errored => errored
  }
end


def kill_all
  if $foreman_pid
    begin
      puts "Killing #{$foreman_pid}"
      Process.kill("TERM", $foreman_pid)
      Process.wait($foreman_pid)
    rescue Exception => e
      puts e.message
    end
  end
  if $cacheable_pid
    begin
      puts "Killing #{$cacheable_pid}"
      Process.kill("KILL", $cacheable_pid)
      Process.wait($cacheable_pid)
    rescue Exception => e
      puts e.message
    end
  end
  $thread.kill if $thread
  $thread = nil
  $foreman_pid = nil
  $cacheable_pid = nil
end

trap("SIGINT") do
  kill_all
end

at_exit do
  kill_all
end

$thread = Thread.new do
  sleep 15
  puts "Warming rails server with 10 requests..."
  rails_url = "http://localhost:3000/"
  node_url = "http://localhost:1337/"
  puts "Warm time: %f" % benchmark(rails_url, 1, 1, 10)[:time]

  suite({
    "Rails" => rails_url,
    "Node" => node_url
  },
  [
    100,
    1_000,
    10_000
  ], 5, 20)

  exit(0)
end
Process.wait($foreman_pid) if $foreman_pid
Process.wait($cacheable_pid) if $cacheable_pid
kill_all
