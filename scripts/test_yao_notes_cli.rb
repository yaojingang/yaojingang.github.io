#!/usr/bin/env ruby
# frozen_string_literal: true

require "minitest/autorun"
require "json"
require "tmpdir"
require "fileutils"
require "socket"
require "open3"
require "rbconfig"
require "time"
require "stringio"
require_relative "../assets/cli/yao-notes"

class YaoNotesCliTest < Minitest::Test
  CLI = File.expand_path("../assets/cli/yao-notes.rb", __dir__)

  def setup
    @root = File.realpath(Dir.mktmpdir("yao-notes-cli-test-"))
    @state_dir = File.join(@root, "state")
    @server = TCPServer.new("127.0.0.1", 0)
    @source = "http://127.0.0.1:#{@server.addr[1]}/"
    @items = notes(1, 12)
    @failure = nil
    @version = "1.0.0"
    @feed_redirect = nil
    @malformed_response = false
    @raw_feed = nil
    @thread = Thread.new do
      loop do
        client = @server.accept
        line = client.gets
        if line
          request_path = line.split[1]
          loop do
            header = client.gets
            break if header.nil? || header == "\r\n"
          end
          serve(client, request_path)
        end
        client.close
      rescue IOError, Errno::EBADF
        break
      end
    end
  end

  def teardown
    @server.close
    @thread.kill
    @thread.join
    FileUtils.remove_entry(@root)
  end

  def notes(first, last)
    (first..last).to_a.reverse.map do |number|
      { "id" => @source + "weekly/#{number}/", "url" => @source + "weekly/#{number}/", "title" => "随笔 #{number}",
        "date_published" => (Time.utc(2026, 1, 1) + number * 86_400).iso8601,
        "content_html" => "<p>第 #{number} 期的完整正文。</p>" }
    end
  end

  def serve(client, path)
    if @malformed_response && path == "/subscribe/feed.json"
      client.write("HTTP/1.1 what\r\n\r\n")
      return
    end
    status, headers = "200 OK", {}
    body = case path
           when "/subscribe/manifest.json"
             JSON.generate("schema_version" => 1, "version" => @version, "subscription_id" => "yaojingang-weekly",
                           "feed_url" => @source + "subscribe/feed.json", "archive_url" => @source + "weekly/",
                           "instructions_url" => @source + "subscribe/agent.txt", "schedule" => { "timezone" => "Asia/Shanghai" })
           when "/subscribe/feed.json"
             if @failure
               status = "503 Service Unavailable"
               "unavailable"
             elsif @feed_redirect
               status, headers = "302 Found", { "Location" => @feed_redirect }
               "redirect"
             else
               @raw_feed || JSON.generate("version" => "https://jsonfeed.org/version/1.1", "items" => @items)
             end
           when "/assets/cli/yao-notes.rb"
             File.binread(CLI)
           else
             status = "404 Not Found"
             "missing"
           end
    client.write("HTTP/1.1 #{status}\r\nContent-Length: #{body.bytesize}\r\nConnection: close\r\n")
    headers.each { |key, value| client.write("#{key}: #{value}\r\n") }
    client.write("\r\n" + body)
  end

  def invoke(*args, cli: CLI)
    out, err, status = Open3.capture3({ "HTTP_PROXY" => nil, "http_proxy" => nil }, RbConfig.ruby, cli,
                                    "--source", @source, "--state-dir", @state_dir, *args)
    [status.success? ? JSON.parse(out) : JSON.parse(err), status.exitstatus]
  end

  def call(*args)
    result, code = invoke(*args)
    assert_equal 0, code, result.inspect
    result
  end

  def state_path
    File.join(@state_dir, "state.json")
  end

  def state
    JSON.parse(File.read(state_path))
  end

  def acknowledge(result)
    call("ack", result.fetch("batch_id"))
  end

  def test_first_preview_and_following_checks_do_not_send_older_issues
    initial = call("init")
    assert_equal "initialized", initial.fetch("status")
    assert_equal [@items.first.fetch("id")], initial.fetch("items").map { |item| item.fetch("id") }
    assert_equal 12, initial.fetch("baseline_count")
    acknowledge(initial)
    assert_equal "idle", call("check").fetch("status")
    assert_equal 1, call("init").fetch("acknowledged_count")
    assert_equal [], call("check").fetch("items")
  end

  def test_only_new_items_are_returned_and_revisions_keep_the_same_identity
    acknowledge(call("init"))
    @items = notes(2, 13)
    update = call("check")
    assert_equal [@items.first.fetch("id")], update.fetch("items").map { |item| item.fetch("id") }
    acknowledge(update)
    @items.first["content_html"] = "<p>修订后的正文。</p>"
    assert_equal "idle", call("check").fetch("status")
  end

  def test_active_batches_are_leased_and_failed_batches_can_be_retried
    initial = call("init")
    assert_equal "busy", call("check").fetch("status")
    call("release", initial.fetch("batch_id"))
    retried = call("check")
    assert_equal initial.fetch("items"), retried.fetch("items")
    refute_equal initial.fetch("batch_id"), retried.fetch("batch_id")
    before = File.binread(state_path)
    error, code = invoke("ack", initial.fetch("batch_id"))
    assert_equal 1, code
    assert_equal "invalid_batch", error.fetch("error").fetch("code")
    assert_equal before, File.binread(state_path)
    acknowledge(retried)
  end

  def test_expired_leases_recover_after_a_process_stops
    initial = call("init")
    stored = state
    stored.fetch("lease")["expires_at"] = "2026-01-01T00:00:00Z"
    File.write(state_path, JSON.generate(stored))
    retried = call("check")
    refute_equal initial.fetch("batch_id"), retried.fetch("batch_id")
    assert_equal initial.fetch("items"), retried.fetch("items")
  end

  def test_network_errors_and_bad_protocols_preserve_the_last_good_state
    acknowledge(call("init"))
    before = File.binread(state_path)
    @failure = true
    error, code = invoke("check")
    assert_equal 1, code
    assert_equal "http_error", error.fetch("error").fetch("code")
    assert_equal before, File.binread(state_path)
    @failure = false
    @version = "2.0.0"
    error, code = invoke("check")
    assert_equal 1, code
    assert_equal "unsupported_protocol", error.fetch("error").fetch("code")
    assert_equal before, File.binread(state_path)
  end

  def test_corrupted_state_and_symbolic_links_are_preserved
    call("init")
    File.write(state_path, "broken JSON")
    error, code = invoke("check")
    assert_equal 1, code
    assert_equal "invalid_state", error.fetch("error").fetch("code")
    assert_equal "broken JSON", File.read(state_path)
    File.unlink(state_path)
    sentinel = File.join(@root, "sentinel.json")
    File.write(sentinel, "keep this file")
    File.symlink(sentinel, state_path)
    error, code = invoke("init")
    assert_equal 1, code
    assert_equal "unsafe_state_path", error.fetch("error").fetch("code")
    assert_equal "keep this file", File.read(sentinel)
  end

  def test_external_redirects_and_future_items_do_not_create_state
    @feed_redirect = "https://untrusted.invalid/feed.json"
    error, code = invoke("init")
    assert_equal 1, code
    assert_equal "untrusted_url", error.fetch("error").fetch("code")
    refute File.exist?(state_path)
    @feed_redirect = nil
    @items.first["date_published"] = "2099-01-01T00:00:00Z"
    error, code = invoke("init")
    assert_equal 1, code
    assert_equal "future_item", error.fetch("error").fetch("code")
    refute File.exist?(state_path)
  end

  def test_empty_feeds_initialize_and_read_only_commands_leave_no_state
    assert_equal "uninitialized", call("status").fetch("status")
    assert_equal 1, call("latest").fetch("items").size
    refute File.exist?(@state_dir)
    @items = []
    assert_equal [], call("init").fetch("items")
    assert_equal "idle", call("check").fetch("status")
  end

  def test_pending_content_survives_a_feed_window_gap
    initial = call("init")
    call("release", initial.fetch("batch_id"))
    stored = state
    stored["last_check_at"] = "2026-01-13T00:00:00Z"
    File.write(state_path, JSON.generate(stored))
    @items = notes(13, 24)
    result = call("check")
    assert_equal true, result.fetch("history_gap")
    assert_includes result.fetch("items"), initial.fetch("items").first
    assert_equal 13, result.fetch("items").length
  end

  def test_repeated_init_preserves_the_discovery_watermark_for_history_gaps
    acknowledge(call("init"))
    stored = state
    stored["last_check_at"] = "2026-01-13T00:00:00Z"
    File.write(state_path, JSON.generate(stored))
    @items = notes(25, 36)
    call("init")
    assert_equal "2026-01-13T00:00:00Z", state.fetch("last_check_at")
    assert_equal true, call("check").fetch("history_gap")
  end

  def test_confirmation_lock_contention_is_a_retryable_error
    initial = call("init")
    before = File.binread(state_path)
    File.open(File.join(@state_dir, "state.lock"), File::RDWR) do |lock|
      lock.flock(File::LOCK_EX)
      error, code = invoke("ack", initial.fetch("batch_id"))
      assert_equal 1, code
      assert_equal "state_busy", error.fetch("error").fetch("code")
      assert_equal before, File.binread(state_path)
    end
    acknowledge(initial)
    assert_equal [], call("check").fetch("items")
  end

  def test_invalid_http_and_port_are_structured_errors
    @malformed_response = true
    error, code = invoke("init")
    assert_equal 1, code
    assert_equal "network_error", error.fetch("error").fetch("code")
    refute File.exist?(state_path)
    error, code = invoke("latest", "--source", "https://127.0.0.1:999999999999999999999/")
    assert_equal 1, code
    assert_equal "invalid_source", error.fetch("error").fetch("code")
  end

  def test_partial_acknowledgement_only_confirms_selected_items
    acknowledge(call("init"))
    @items = notes(3, 14)
    batch = call("check")
    assert_equal 2, batch.fetch("items").size
    first = batch.fetch("items").first.fetch("id")
    call("ack", batch.fetch("batch_id"), first)
    assert_equal 1, state.fetch("pending").size
    before = File.binread(state_path)
    error, code = invoke("ack", batch.fetch("batch_id"), @source + "weekly/999/")
    assert_equal 1, code
    assert_equal "invalid_item", error.fetch("error").fetch("code")
    assert_equal before, File.binread(state_path)
    acknowledge(batch)
    assert_equal "idle", call("check").fetch("status")
  end

  def test_downloaded_cli_runs_from_an_isolated_install_path
    require "net/http"
    uri = URI(@source + "assets/cli/yao-notes.rb")
    downloaded = Net::HTTP.new(uri.host, uri.port, nil).get(uri.request_uri).body
    installed = File.join(@root, "installed", "yao-notes.rb")
    FileUtils.mkdir_p(File.dirname(installed))
    File.binwrite(installed, downloaded)
    result, code = invoke("latest", cli: installed)
    assert_equal 0, code
    assert_equal "latest", result.fetch("status")
    assert_equal @items.first, result.fetch("items").first
    help, error, status = Open3.capture3(RbConfig.ruby, installed, "--help")
    assert status.success?, error
    assert_includes help, "ack BATCH_ID"
    version, error, status = Open3.capture3(RbConfig.ruby, installed, "--version")
    assert status.success?, error
    assert_equal "1.0.0", version.strip
  end

  def test_invalid_utf8_feed_is_a_structured_error_without_state_changes
    @raw_feed = JSON.generate("version" => "https://jsonfeed.org/version/1.1", "items" => @items).b.sub('"title":"'.b, '"title":"'.b + "\xFF".b)
    %w[latest init].each do |command|
      error, code = invoke(command)
      assert_equal 1, code
      assert_equal "invalid_json", error.fetch("error").fetch("code")
      refute File.exist?(state_path)
    end
  end

  def test_invalid_utf8_state_is_preserved
    call("init")
    corrupted = File.binread(state_path).sub('"title": "'.b, '"title": "'.b + "\xFF".b)
    File.binwrite(state_path, corrupted)
    error, code = invoke("check")
    assert_equal 1, code
    assert_equal "invalid_state", error.fetch("error").fetch("code")
    assert_equal corrupted, File.binread(state_path)
  end

  def test_incomplete_pending_items_are_rejected_without_rewriting_state
    initial = call("init")
    call("release", initial.fetch("batch_id"))
    stored = state
    @items = []
    %w[title url].each do |key|
      corrupted = Marshal.load(Marshal.dump(stored))
      corrupted.fetch("pending").values.first.delete(key)
      before = JSON.generate(corrupted)
      File.write(state_path, before)
      error, code = invoke("check")
      assert_equal 1, code
      assert_equal "invalid_state", error.fetch("error").fetch("code")
      assert_equal before.b, File.binread(state_path)
    end
  end

  def lose_confirmation_output(*args)
    broken_output = Object.new
    def broken_output.puts(_value)
      raise Errno::EPIPE
    end
    error = StringIO.new
    code = YaoNotes::Client.new(["--source", @source, "--state-dir", @state_dir, *args], out: broken_output, err: error).run
    assert_equal 1, code
    assert_equal "io_error", JSON.parse(error.string).fetch("error").fetch("code")
  end

  def test_completed_ack_is_replayable_after_output_is_lost
    initial = call("init")
    lose_confirmation_output("ack", initial.fetch("batch_id"))
    assert_empty state.fetch("pending")
    @items = notes(2, 13)
    next_batch = call("check")
    assert_equal "acknowledged", call("ack", initial.fetch("batch_id")).fetch("status")
    assert_equal next_batch.fetch("batch_id"), state.fetch("lease").fetch("token")
    assert_equal 1, state.fetch("pending").size
  end

  def test_partial_ack_replay_accepts_confirmed_and_remaining_ids
    acknowledge(call("init"))
    @items = notes(3, 14)
    batch = call("check")
    ids = batch.fetch("items").map { |item| item.fetch("id") }
    lose_confirmation_output("ack", batch.fetch("batch_id"), ids.first)
    assert_equal 1, state.fetch("pending").size
    assert_equal "acknowledged", call("ack", batch.fetch("batch_id"), ids.first).fetch("status")
    assert_equal "acknowledged", call("ack", batch.fetch("batch_id"), *ids).fetch("status")
    assert_equal "acknowledged", call("ack", batch.fetch("batch_id"), *ids).fetch("status")
    assert_empty state.fetch("pending")
    assert_equal 3, state.fetch("acknowledged").size
  end

  def test_released_batch_replay_preserves_a_new_lease
    initial = call("init")
    lose_confirmation_output("release", initial.fetch("batch_id"))
    assert_nil state.fetch("lease")
    next_batch = call("check")
    assert_equal "released", call("release", initial.fetch("batch_id")).fetch("status")
    assert_equal next_batch.fetch("batch_id"), state.fetch("lease").fetch("token")
    assert_equal next_batch.fetch("items").size, state.fetch("pending").size
  end
end
