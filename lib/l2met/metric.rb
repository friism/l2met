require 'atomic'

module L2met
  module Metric
    extend self

    HISTOGRAM_DEFAULTS = {display_units_long: "ms"}
    COUNTER_DEFAULTS = {display_units_long: "txn"}

    def histogram(data)
      data[:histograms].update do |hash|
        k = key(args)
        hash[k] ||= args.merge(HISTOGRAM_DEFAULTS)
        hash[k][:values] ||= []
        hash[k][:values] << args[:value]
        hash
      end
    end

    def counter(data)
      data[:counters].update do |hash|
        k = key(args)
        hash[k] ||= args.merge(COUNTER_DEFAULTS)
        hash[k][:value] ||= 0
        hash[k][:value] += 1
        hash
      end
    end

    def histograms
      get(:histograms)
    end

    def histograms!
      flush(:histograms)
    end

    def counters
      get(:counters)
    end

    def counters!
      flush(:counters)
    end

    private

    def key(args)
      Digest::SHA1.hexdigest([:name, :source, :lable].map {|k| args[k]}.join)
    end

    def flush(type)
      if data.key?(type)
        get(type).tap {data.delete(type)}
      else
        []
      end
    end

    def get(type)
      data[type].value
    end

    def data
      @data ||= {counters: Atomic.new({}), histograms: Atomic.new({})}
    end

  end
end
