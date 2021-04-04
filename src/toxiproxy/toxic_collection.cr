require "./toxic"

class Toxiproxy
  class ToxicCollection

    property :toxics
    getter :proxies

    @proxies : Array(Toxiproxy)

    def initialize(proxies)
      @proxies = proxies
      @toxics = [] of Toxiproxy::Toxic
    end

    def apply(&block)
      names = toxics.group_by { |t| [t.name, t.proxy.name] }
      dups = names.values.select { |toxic| toxics.size > 1 }

      unless dups.empty?
        raise ArgumentError.new("There are two toxics with the name #{dups.first[0]} for proxy #{dups.first[1]}, please override the default name (<type>_<direction>)")
      end

      begin
        @toxics.each { |t| t.save }
        yield
      ensure
        @toxics.each { |t| t.destroy }
      end
    end

    def upstream(type, name = "", toxicity = nil, attrs = {String => Int32})
      proxies.each do |proxy|
        toxics << Toxic.new(
          name: name,
          type: type.to_s,
          proxy: proxy,
          stream: "upstream",
          toxicity: attrs.delete("toxicity") || attrs.delete(:toxicity),
          attributes: attrs
        )
      end
      self
    end

    def downstream(type, name = "", toxicity = nil, attrs = {String => Int32})
      proxies.each do |proxy|
        toxics << Toxic.new(
          {
            name: name,
            type: type.to_s,
            proxy: proxy,
            stream: "downstream",
            toxicity: toxicity,
            attributes: attrs
          }
        )
      end
      self
    end
  end
end
