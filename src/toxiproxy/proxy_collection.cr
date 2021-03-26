class Toxiproxy
  class ProxyCollection
    include Enumerable(Toxiproxy)

    DELEGATED_METHODS = [:length, :size, :count, :find, :each, :map]
    DEFINED_METHODS = [:select, :reject, :grep, :down]
    METHODS = DEFINED_METHODS + DELEGATED_METHODS

    @collection : Array(Toxiproxy)

    delegate :length, :size, :count, :find, :each, :map, to: @collection

    def initialize(collection : Array(Toxiproxy))
      @collection = collection
    end

    # Sets every proxy in the collection as down. For example:
    #
    #   Toxiproxy.grep(/redis/).down { .. }
    #
    # Would simulate every Redis server being down for the duration of the
    # block.
    def down(&block)
      @collection.inject(block) { |nested, proxy|
        -> { proxy.down(&nested) }
      }.call
    end

    def grep(regex)
      self.class.new(@collection.select { |proxy|
        proxy.name =~ regex
      })
    end

    # Required per:
    #   https://crystal-lang.org/api/1.0.0/Enumerable.html#each(&block:T-%3E_)-instance-method
    def each(&block : T -> _)
    end
  end
end
