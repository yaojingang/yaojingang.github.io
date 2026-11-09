#!/usr/bin/env ruby
# frozen_string_literal: true

require "minitest/autorun"
require "cgi"
require "fileutils"
require "jekyll"
require "rexml/document"
require "tmpdir"
require "uri"
require "yaml"
require "digest"

class AgentSubscriptionTest < Minitest::Test
  ROOT = File.expand_path("..", __dir__)
  ORIGIN = "https://reader.example/blog"

  def setup
    @directory = File.realpath(Dir.mktmpdir("agent-subscription-test-"))
    @source = File.join(@directory, "source")
    @output = File.join(@directory, "public")
    FileUtils.mkdir_p(File.join(@source, "_layouts"))
    File.write(File.join(@source, "_layouts/default.html"), "{{ content }}")
    %w[index.html feed-weekly.xml _includes/weekly-feed-items.liquid _data/agent_subscription.yml subscribe/index.md subscribe/agent.txt subscribe/manifest.json subscribe/feed.json assets/cli/yao-notes.rb].each do |name|
      FileUtils.mkdir_p(File.dirname(File.join(@source, name)))
      FileUtils.cp(File.join(ROOT, name), File.join(@source, name))
    end
    File.write(File.join(@source, "_layouts/page.html"), "{{ content }}")
  end

  def teardown
    FileUtils.remove_entry(@directory)
  end

  def document(path, metadata)
    destination = File.join(@source, path)
    FileUtils.mkdir_p(File.dirname(destination))
    File.write(destination, metadata.to_yaml + "---\nA complete source paragraph.\n")
  end

  def build
    configuration = Jekyll.configuration(
      "source" => @source,
      "destination" => @output,
      "url" => "https://reader.example",
      "baseurl" => "/blog",
      "collections" => { "weekly" => { "output" => true } },
      "time" => Time.utc(2026, 11, 9),
      "future" => false,
      "quiet" => true,
      "disable_disk_cache" => true
    )
    Dir.chdir(@source) { Jekyll::Site.new(configuration).process }
  end

  def items
    REXML::XPath.match(REXML::Document.new(File.read(File.join(@output, "feed-weekly.xml"))), "/rss/channel/item")
  end

  def test_feed_excludes_future_collection_notes_and_unrelated_content
    13.times do |index|
      date = "2026-01-%02d" % (index + 1)
      document("_posts/#{date}-weekly.md", "title" => "Weekly #{index + 1}", "date" => date, "lang" => "zh-CN", "weekly" => true)
    end
    document("_weekly/current.md", "title" => "Published collection note", "date" => "2026-02-01", "lang" => "zh-Hans")
    document("_weekly/future.md", "title" => "Future collection note", "date" => "2099-01-01", "lang" => "zh-CN")
    document("_weekly/hidden.md", "title" => "Unpublished note", "date" => "2026-03-01", "lang" => "zh-CN", "published" => false)
    document("_posts/2026-04-01-ordinary.md", "title" => "Ordinary article", "date" => "2026-04-01", "lang" => "zh-CN")
    document("_posts/2026-04-02-english.md", "title" => "English translation", "date" => "2026-04-02", "lang" => "en-US", "weekly" => true)
    build

    titles = items.map { |item| item.elements["title"].text }
    assert_equal ["Published collection note"] + 13.downto(3).map { |index| "Weekly #{index}" }, titles
    assert_equal 12, items.size
    items.each do |item|
      url = item.elements["link"].text
      assert_equal url, item.elements["guid"].text
      path = URI.parse(url).path.sub(%r{\A/blog/}, "")
      target = File.join(@output, path)
      assert File.file?(target) || File.file?(File.join(target, "index.html")), "RSS target is missing: #{url}"
    end
  end

  def test_feed_preserves_xml_text_and_deployment_baseurl
    document("_weekly/metadata.md", "title" => "A & B <weekly>", "description" => 'A & B "quoted"', "date" => "2026-02-01")
    build

    assert_equal 1, items.size
    assert_equal "A & B <weekly>", items.first.elements["title"].text
    assert_equal 'A & B "quoted"', items.first.elements["description"].text
    assert items.first.elements["link"].text.start_with?(ORIGIN + "/")
  end

  def test_empty_archive_produces_a_valid_empty_feed
    build
    assert_empty items
  end

  def test_homepage_copies_one_sentence_and_links_to_complete_protocol
    build
    html = File.read(File.join(@output, "index.html"))
    textarea = html.match(/<textarea\b[^>]*data-agent-prompt[^>]*>(.*?)<\/textarea>/m)
    refute_nil textarea
    prompt = CGI.unescapeHTML(textarea[1]).strip
    assert_equal "请读取 #{ORIGIN}/subscribe/，按说明为我订阅姚金刚的每周随笔。", prompt
    assert_operator prompt.length, :<, 150
    assert_includes File.read(File.join(@output, "subscribe/index.html")), "/blog/subscribe/agent.txt"
    protocol = File.read(File.join(@output, "subscribe/agent.txt"))
    %w[subscribe/manifest.json subscribe/feed.json assets/cli/yao-notes.rb weekly/].each do |path|
      assert_includes protocol, ORIGIN + "/" + path
    end
    assert_includes protocol, "Asia/Shanghai"
    assert_includes protocol, "--source #{ORIGIN}/ --state-dir STATE check"
    assert_includes html, "data-agent-toast"
  end

  def test_manifest_integrity_and_json_feed_match_the_rss_items
    document("_weekly/body.md", "title" => "A & B", "date" => "2026-02-01", "lang" => "zh-CN")
    build
    manifest = JSON.parse(File.read(File.join(@output, "subscribe/manifest.json")))
    assert_equal 1, manifest.fetch("schema_version")
    assert_equal "yaojingang-weekly", manifest.fetch("subscription_id")
    assert_equal "Asia/Shanghai", manifest.fetch("schedule").fetch("timezone")
    assert_equal Digest::SHA256.file(File.join(@output, "assets/cli/yao-notes.rb")).hexdigest, manifest.fetch("cli").fetch("sha256")
    json = JSON.parse(File.read(File.join(@output, "subscribe/feed.json")))
    assert_equal "https://jsonfeed.org/version/1.1", json.fetch("version")
    assert_equal items.map { |item| item.elements["guid"].text }, json.fetch("items").map { |item| item.fetch("id") }
    assert_includes json.fetch("items").first.fetch("content_html"), "A complete source paragraph."
    assert_includes json.fetch("items").first.fetch("content_html"), "<p>"
  end
end
