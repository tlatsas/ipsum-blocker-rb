# frozen_string_literal: true

require "net/http"
require "uri"

class CliLogger
  def initialize
    # TODO initialise from CLI options
  end

  def out(message)
    puts(message)
  end
end

class IpsumBlocker
  attr_reader :logger

  def initialize(logger:)
    @logger = logger
  end

  def process
    logger.out(":: Starting ipsum blocker process")
    logger.out(":: Fetching new block list")
    ip_addresses = get_addresses_to_block

    logger.out(":: Setting up Ipset")
    setup_ipset(ip_addresses: ip_addresses)

    logger.out(":: Updating Iptables")
    setup_iptables(ipset_name: Ipset::NAME)
  end

  private

  def get_addresses_to_block
    blocklist = BlockList.new

    logger.out("   Downloading...")
    blocklist.download

    blocklist.ip_addresses
  end

  def setup_ipset(ip_addresses:)
    logger.out("   Creating ipset \"#{Ipset::NAME}\"")
    Ipset.create

    logger.out("   Flushing old values")
    Ipset.flush

    logger.out("   Adding new IPs to the set")
    Ipset.add_ips_to_set(ip_addresses: ip_addresses)
  end

  def setup_iptables(ipset_name:)
    logger.out("   Dropping existing Iptable rules for ipset \"#{ipset_name}\"")
    Iptables.drop_ipset_rule(ipset_name: ipset_name)

    logger.out("   Recreating Iptable rules for ipset \"#{ipset_name}\"")
    Iptables.create_ipset_rule(ipset_name: ipset_name)
  end
end

class BlockList
  LVL3_LIST_URL = "https://raw.githubusercontent.com/stamparm/ipsum/master/levels/3.txt"

  attr_reader :ip_addresses

  def initialize
    @ip_addresses = []
  end

  def download
    uri = URI.parse(LVL3_LIST_URL)
    Net::HTTP.start(uri.host, uri.port, use_ssl: true) do |http|
      resp = http.get(uri.path)
      @ip_addresses = resp.body.split("\n").map(&:chomp)
    end
  end
end

class Ipset
  NAME = "ipsum"

  class << self
    def create
      system("ipset -quiet -exists create #{NAME} hash:ip")
    end

    def flush
      system("ipset -quiet flush #{NAME}")
    end

    def add_ips_to_set(ip_addresses:)
      ip_addresses.each do |ip|
        system("ipset -quiet add #{NAME} #{ip}")
      end
    end
  end
end

class Iptables
  class << self
    def drop_ipset_rule(ipset_name:)
      system("iptables -D INPUT -m set --match-set #{ipset_name} src -j DROP 2>/dev/null")
    end

    def create_ipset_rule(ipset_name:)
      system("iptables -I INPUT -m set --match-set #{ipset_name} src -j DROP")
    end
  end
end


# TODO add CLI options
IpsumBlocker.new(logger: CliLogger.new).process
