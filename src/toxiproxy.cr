require "uri"
require "http/client"
require "socket"
require "json"
require "./toxiproxy/proxy_collection"
require "./toxiproxy/toxic_collection"

class Toxiproxy
  DEFAULT_URI = "http://127.0.0.1:8474"
  VALID_DIRECTIONS = [:upstream, :downstream]

  class NotFound < Exception; end
  class ProxyExists < Exception; end
  class InvalidToxic < Exception; end

  @@uri : URI?
  @@http : HTTP::Client?

  @upstream : String?
  @listen : String?
  @name : String?
  @enabled : Bool?

  getter :listen, :name, :enabled

  def initialize(options)
    @upstream = options[:upstream]?
    @listen = options[:listen]? || "localhost:0"
    @name = options[:name]?
    @enabled = options[:enabled]?
  end

  def self.reset
    response = http.post("/reset", headers: HTTP::Headers{"Content-Type" => "application/json"})
    assert_response(response)
    self
  end

  def self.version
    return false unless running?

    response = http.get("/version")
    assert_response(response)
    response.body
  end

  def self.all
    response = http.get("/proxies")
    assert_response(response)

    proxies = JSON.parse(response.body).as_h.map { |name, attrs|
      self.new({
        upstream: attrs["upstream"].to_s,
        listen: attrs["listen"].to_s,
        name: attrs["name"].to_s,
        enabled: attrs["enabled"] == true ? true : false
      })
    }

    ProxyCollection.new(proxies)
  end

  # Sets the toxiproxy host to use.
  def self.host=(host)
    @@uri = host.is_a?(URI) ? host  : URI.parse(host)
  end

  # Convenience method to create a proxy.
  def self.create(options)
    self.new(options).create
  end

  # Find a single proxy by its name.
  def self.find_by_name(name = nil, &block)
    self.all.find { |proxy| p.name == name.to_s }
  end

  def self.find_by_name(name = nil)
    self.all.find { |proxy| proxy.name == name.to_s  }
  end

  def self.find_by_name!(*args)
    proxy = find_by_name(*args)
    raise NotFound.new("#{name} not found in #{self.all.map { |p| p.name }.join(", ")}") unless proxy
    proxy
  end

  def self.[](query)
    return self.all.grep(query) if query.is_a?(Regex)
    find_by_name!(query)
  end

  def self.populate(*proxies)
    proxies = proxies.first if proxies.first.is_a?(Array)

    response = http.post(
      "/populate",
      headers: HTTP::Headers{"Content-Type" => "application/json"},
      body: proxies.to_json
    )
    assert_response(response)

    proxies = JSON.parse(response.body).as_h["proxies"].as_a.map do |attrs|
      self.new({
        upstream: attrs["upstream"].to_s,
        listen: attrs["listen"].to_s,
        name: attrs["name"].to_s,
        enabled: attrs["enabled"] == true ? true : false
      })
    end

    ProxyCollection.new(proxies)
  end

  def self.running?
    TCPSocket.new(uri.host.not_nil!, uri.port).close
    true
  rescue Socket::ConnectError
    false
  end

  def upstream(type, name = nil, toxicity = nil, attrs = {String => Int32})
    return @upstream unless type

    collection = ToxicCollection.new([self])
    collection.upstream(type, attrs)
    collection
  end

  def downstream(type, name = nil, toxicity = nil, attrs = {String => Int32})
    collection = ToxicCollection.new([self])
    collection.downstream(type, name, toxicity, attrs)
    collection
  end

  # Simulates the endpoint is down, by closing the connection and no
  # longer accepting connections. This is useful to simulate critical system
  # failure, such as a data store becoming completely unavailable.
  def down(&block)
    disable
    yield
  ensure
    enable
  end

  # Disables a Toxiproxy. This will drop all active connections and stop the
  # proxy from listening.
  def disable
    response = http.post(
      "/proxies/#{name}",
      headers: HTTP::Headers{"Content-Type" => "application/json"},
      body: {enabled: false}.to_json
    )
    assert_response(response)
    self
  end

  # Enables a Toxiproxy. This will cause the proxy to start listening again.
  def enable
    response = http.post(
      "/proxies/#{name}",
      headers: HTTP::Headers{"Content-Type" => "application/json"},
      body: {enabled: true}.to_json
    )
    assert_response(response)
    self
  end

  # Create a Toxiproxy, proxying traffic from `@listen` (optional argument to
  # the constructor) to `@upstream`. `#down` `#upstream` or `#downstream` can
  # at any time alter the health of this connection.
  def create
    response = http.post(
      "/proxies",
      headers: HTTP::Headers{"Content-Type" => "application/json"},
      body: {
        upstream: upstream.to_s,
        name: name.to_s,
        listen: listen.to_s,
        enabled: enabled,
      }.to_json
    )
    assert_response(response)

    new = JSON.parse(response.body)
    @listen = new["listen"].to_s

    self
  end

  # Destroys a Toxiproxy.
  def destroy
    response = http.delete("/proxies/#{name}")
    assert_response(response)
    serlf
  end

  def toxics
    response = http.get("/proxies/#{name}/toxics")
    assert_response(response)

    JSON.parse(response.body).as_a.map { |attrs|
      Toxic.new(
        type: attrs["type"],
        name: attrs["name"],
        proxy: self,
        stream: attrs["stream"],
        toxicity: attrs["toxicity"],
        attributes: attrs["attributes"],
      )
    }
  end

  private def self.uri
    @@uri ||= URI.parse(DEFAULT_URI)
  end

  protected def self.http
    @@http ||= HTTP::Client.new(uri)
  end

  private def http
    self.class.http
  end

  protected def self.assert_response(response)
    case response
    when HTTP::Status::CONFLICT
      raise ProxyExists.new(response.body)
    when HTTP::Status::NOT_FOUND
      raise NotFound.new(response.body)
    when HTTP::Status::BAD_REQUEST
      raise InvalidToxic.new(response.body)
    else
      raise Exception.new(response.body) unless response.success?
    end
  end

  def assert_response(*args)
    self.class.assert_response(*args)
  end
end
