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

class AgentSubscriptionTest < Minitest::Test
  ROOT = File.expand_path("..", __dir__)
  ORIGIN = "https://reader.example/blog"

  def setup
    @directory = Dir.mktmpdir("agent-subscription-test-")
    @source = File.join(@directory, "source")
    @output = File.join(@directory, "public")
    FileUtils.mkdir_p(File.join(@source, "_layouts"))
    File.write(File.join(@source, "_layouts/default.html"), "{{ content }}")
    %w[index.html feed-weekly.xml].each do |name|
      FileUtils.cp(File.join(ROOT, name), File.join(@source, name))
    end
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
    Jekyll::Site.new(configuration).process
  end

  def items
    REXML::XPath.match(REXML::Document.new(File.read(File.join(@output, "feed-weekly.xml"))), "/rss/channel/item")
  end

  def task_body
    build
    html = File.read(File.join(@output, "index.html"))
    textarea = html.match(/<textarea\b[^>]*data-agent-prompt[^>]*>(.*?)<\/textarea>/m)
    refute_nil textarea, "The published homepage must provide the copyable task prompt"
    prompt = CGI.unescapeHTML(textarea[1])
    body = prompt.match(/请把以下执行规则完整保存到定时任务中，让每次运行都能读取：\s*(.*?)\n创建时先/m)
    refute_nil body, "The reusable task body must have an explicit boundary"
    body[1]
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

  def test_saved_task_body_contains_its_own_fetchable_sources
    urls = URI.extract(task_body, %w[http https])
    assert_includes urls, ORIGIN + "/feed-weekly.xml"
    assert_includes urls, ORIGIN + "/weekly/"
  end
end
