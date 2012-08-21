require 'scrolls'
require 'securerandom'
require 'l2met/db'
require 'l2met/mem'

module L2met
  module MemOutlet
    extend self
    INTERVAL = 30

    def start
      Thread.new do
        loop do
          sleep(INTERVAL)
          Thread.new {snapshot}
        end
      end
    end

    def snapshot
      snapshot_histograms
      snapshot_counters
    end

    def snapshot_counter
      Mem.counters!.each do |k, metric|
        name = [metric[:name], "count"].map(&:to_s).join(".")
        DB.put('counters', k, SecureRandom.uuid, metric[:value],
                name: name, source: metric[:source])
      end
    end

    def snapshot_histogram
      Mem.histograms!.each do |k, metric|
        values = metric[:values].sort
        data = {min: Stats.min(values),
          max: Stats.max(values),
          mean: Stats.mean(values),
          median: Stats.median(values),
          perc95: Stats.perc95(values),
          perc99: Stats.perc99(values)}
        DB.put('histograms', k, SecureRandom.uuid, 0,
              {name: name, source: metric[:source]}.merge(data))
      end
    end

    def log(data, &blk)
      Scrolls.log({ns: "mem-outlet"}.merge(data), &blk)
    end

  end
end