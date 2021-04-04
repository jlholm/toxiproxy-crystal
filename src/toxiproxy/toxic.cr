class Toxiproxy
  class Toxic
    property :attributes, :toxicity
    getter :name, :type, :stream, :proxy

    alias AttributesHash = Hash(String, Int32)

    @type : String
    @stream : String?
    @name : String?
    @proxy : Toxiproxy
    @toxicity : Float64?
    @attributes : AttributesHash

    def initialize(attrs)
      raise "Toxic type is required" unless attrs[:type]
      @type = attrs[:type]
      @stream = attrs[:stream]? || "downstream"
      @name = attrs[:name]? || "#{@type}_#{@stream}"
      @proxy = attrs[:proxy].not_nil!
      @toxicity = attrs[:toxicity]? || 1.0
      @attributes = attrs[:attributes]
    end

    def save
      response = Toxiproxy.http.post(
        "/proxies/#{proxy.name}/toxics",
        headers: HTTP::Headers{"Content-Type" => "application/json"},
        body: as_json
      )
      Toxiproxy.assert_response(response)

      json = JSON.parse(response.body)
      @attributes = AttributesHash.new.tap do |accum|
        json["attributes"].as_h.each do |key, value|
          accum[key] = value.as_i
        end
      end
      @toxicity = Float64.new(json["toxicity"].to_s)

      self
    end

    def destroy
      response = Toxiproxy.http.delete("/proxies/#{proxy.name}/toxics/#{name}")
      Toxiproxy.assert_response(response)
      self
    end

    def as_json
      {
        name: name,
        type: type,
        stream: stream,
        toxicity: toxicity,
        attributes: attributes
      }.to_json
    end

  end
end
