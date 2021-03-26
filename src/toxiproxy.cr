require "uri"
require "http/client"
require "socket"
require "json"
require "./toxiproxy/proxy_collection"

class Toxiproxy
  DEFAULT_URI = "http://127.0.0.1:8474"
  VALID_DIRECTIONS = [:upstream, :downstream]

  class NotFound < Exception; end
  class ProxyExists < Exception; end
  class InvalidToxic < Exception; end

  @@uri : URI?
  @@http : HTTP::Client?

  @upstream : String
  @listen : String
  @name : String
  @enabled : Bool

  getter :listen, :name, :enabled

  def initialize(options)
    @upstream = options[:upstream]
    @listen = options[:listen] || "localhost:0"
    @name = options[:name]
    @enabled = options[:enabled]
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

  private def self.uri
    @@uri ||= URI.parse(DEFAULT_URI)
  end

  private def self.http
    @@http ||= HTTP::Client.new(uri)
  end

  private def http
    self.class.http
  end

  private def self.assert_response(response)
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
