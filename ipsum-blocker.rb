# frozen_string_literal: true

require "net/http"
require "optparse"
require "logger"
require "uri"

class CliLogger
  def initialize(verbose: true)
    @console_logger = Logger.new($stdout)
    @console_logger.level = verbose ? Logger::INFO : Logger::ERROR
    @console_logger.formatter = proc do |severity, datetime, progname, msg|
      "#{msg}\n"
    end
  end

  def out(message)
    @console_logger.info(message)
  end

  def error(message)
    @console_logger.error(message)
  end
end

class IpsumBlocker
  attr_reader :logger, :save_ipset

  def initialize(logger:, save_ipset:)
    @logger = logger
    @save_ipset = save_ipset
  end

  def process
    logger.out(":: Starting ipsum blocker process")
    logger.out(":: Fetching new block list")
    ip_addresses = get_addresses_to_block

    logger.out(":: Setting up Ipset")
    setup_ipset(ip_addresses: ip_addresses)

    logger.out(":: Updating Iptables")
    setup_iptables(ipset_name: Ipset::NAME)

    logger.out(":: Completed successfully")
  end

  private

  def get_addresses_to_block
    blocklist = BlockList.new

    logger.out("   (1/1) Downloading ipsum blocklist from Github")
    blocklist.download

    blocklist.ip_addresses
  end

  def setup_ipset(ip_addresses:)
    steps = save_ipset ? 4 : 3

    logger.out("   (1/#{steps}) Creating ipset \"#{Ipset::NAME}\"")
    Ipset.create

    logger.out("   (2/#{steps}) Flushing old values")
    Ipset.flush

    logger.out("   (3/#{steps}) Adding new IPs to the set")
    Ipset.add_ips_to_set(ip_addresses: ip_addresses)

    if save_ipset
      logger.out("   (4/#{steps}) Saving ipset in #{Ipset::IPSET_CONF}")
      Ipset.save
    end
  end

  def setup_iptables(ipset_name:)
    logger.out("   (1/2) Dropping existing Iptable rules for ipset \"#{ipset_name}\"")
    Iptables.drop_ipset_rule(ipset_name: ipset_name)

    logger.out("   (2/2) Recreating Iptable rules for ipset \"#{ipset_name}\"")
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
  IPSET_CONF = "/etc/ipset.conf"

  class << self
    def create
      system("ipset -quiet -exist create #{NAME} hash:ip")
    end

    def flush
      system("ipset -quiet flush #{NAME}")
    end

    def add_ips_to_set(ip_addresses:)
      ip_addresses.each do |ip|
        system("ipset -quiet add #{NAME} #{ip}")
      end
    end

    def save
      system("ipset save > #{IPSET_CONF}")
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

filename = File.basename(__FILE__)

options = {}
optparse = OptionParser.new do |opts|
  opts.banner = "Usage: #{filename} [options]"
  options[:verbose] = true
  opts.on("-q", "--quiet", "Do not display any output. We default to verbose.") do
    options[:verbose] = false
  end

  options[:save_ipset] = false
  opts.on("-s", "--save", "Save ipset configuration in #{Ipset::IPSET_CONF}") do
    options[:save_ipset] = true
  end

  opts.on( '-h', '--help', 'Display this screen' ) do
    puts opts
    exit
  end
end

optparse.parse!

unless Process.uid == 0
  puts(":: Permissions error. You must run #{filename} as root.")
  exit 1
end

logger = CliLogger.new(verbose: options[:verbose])
IpsumBlocker.new(logger: logger, save_ipset: options[:save_ipset]).process
