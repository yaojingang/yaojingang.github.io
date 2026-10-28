require "minitest/autorun"
require "json"
require "yaml"
require "uri"

class LinkNetworkTest < Minitest::Test
  ROOT = File.expand_path("..", __dir__)

  def setup
    @network = JSON.parse(File.read(File.join(ROOT, "_data/link_network.json")))
    @nodes = @network.fetch("nodes")
    @links = @network.fetch("links")
    @by_id = @nodes.each_with_object({}) { |node, result| result[node.fetch("id")] = node }
  end

  def identity(url)
    uri = URI.parse(url)
    uri.host.sub(/\Awww\./, "") + uri.path.sub(%r{/+\z}, "")
  end

  def catalog
    %w[friends friend_products].flat_map do |name|
      YAML.load_file(File.join(ROOT, "_data/#{name}.yml"))
    end
  end

  def test_catalog_and_network_have_the_same_distinct_sites
    expected = (catalog.map { |item| identity(item.fetch("url")) } + [@network.fetch("home")]).uniq.sort
    assert_equal expected, @nodes.map { |node| node.fetch("id") }.sort
    assert_equal @nodes.length, @by_id.length, "Each site must have one node"
    @nodes.each do |node|
      assert_equal "https", URI.parse(node.fetch("url")).scheme
      assert_equal node.fetch("id"), identity(node.fetch("url"))
      refute_empty node.fetch("name")
    end
  end

  def test_edges_are_unique_directed_links_between_existing_nodes
    pairs = @links.map { |edge| [edge.fetch("source"), edge.fetch("target")] }
    assert_equal pairs.length, pairs.uniq.length
    pairs.each do |source, target|
      assert @by_id.key?(source), "Unknown source #{source}"
      assert @by_id.key?(target), "Unknown target #{target}"
      refute_equal source, target, "Self-links are excluded"
    end
  end

  def test_every_outgoing_source_has_a_checked_homepage
    sources = @network.fetch("sources")
    assert_equal sources.length, sources.map { |source| source.fetch("id") }.uniq.length
    checked = sources.select { |source| source.fetch("status") == "ok" }.map { |source| source.fetch("id") }
    sources.each do |source|
      assert @by_id.key?(source.fetch("id"))
      assert_equal source.fetch("id"), identity(source.fetch("url"))
    end
    @links.each do |edge|
      assert_includes checked, edge.fetch("source")
      assert @by_id.fetch(edge.fetch("source")).fetch("collected")
    end
  end

  def test_local_outgoing_links_match_the_homepage_catalog
    actual = @links.select { |edge| edge.fetch("source") == @network.fetch("home") }.map { |edge| edge.fetch("target") }.sort
    assert_equal catalog.map { |item| identity(item.fetch("url")) }.uniq.sort, actual
    assert_match(/\A\d{4}-\d{2}-\d{2}\z/, @network.fetch("updated_at"))
  end
end
