#!/usr/bin/env ruby
# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require_relative "import_cognitive_notes"

class ImportCognitiveNotesTest < Minitest::Test
  def test_collapses_feishu_wrapper_duplicate_weekly_heading
    lines = <<~MD.lines
      # 2026\\.08\\.09 像大模型一样训练自己

      > 原文链接：[2026\\.08\\.09 像大模型一样训练自己](https://example.com)
      > 
      > 导出时间：2026\\-08\\-09 15:20
      > 
      > 本文档由 [飞书转存专家](https://example.com/) 生成

      ---

      ### 2026\\.08\\.09 像大模型一样训练自己

      #### 像大模型一样训练自己

      有一种成长方式，就是把自己，当成一个大模型去训练
    MD

    entries = find_weekly_entries(lines)

    assert_equal 1, entries.length
    assert_equal "2026-08-09", entries.first[:date]
    assert_equal "像大模型一样训练自己", entries.first[:title]
    assert_equal lines.index { |line| line.start_with?("### ") }, entries.first[:start]
  end

  def test_imports_percent_encoded_feishu_attachment_path
    Dir.mktmpdir("cognitive-note-source") do |source_dir|
      image_dir = File.join(source_dir, "published-images")
      attachment_dir = File.join(source_dir, "图片和附件")
      FileUtils.mkdir_p(attachment_dir)
      File.binwrite(File.join(attachment_dir, "image 1.png"), "image-data")
      File.binwrite(File.join(attachment_dir, "image 2.png"), "html-image-data")

      normalized = normalize_markdown(
        <<~MD.strip,
          ![示例](图片和附件/image%201.png)
          <img src="图片和附件/image%202.png" alt="示例" loading="lazy">
        MD
        image_prefix: "2026-08-30-weekly-2026-08-30",
        source_dir: source_dir,
        image_dir: image_dir
      )

      assert_includes normalized, "![示例](/assets/cognitive-notes/images/2026-08-30-weekly-2026-08-30-image%201.png)"
      assert_includes normalized, "src=\"/assets/cognitive-notes/images/2026-08-30-weekly-2026-08-30-image%202.png\""
      assert_equal "image-data", File.binread(File.join(image_dir, "2026-08-30-weekly-2026-08-30-image 1.png"))
      assert_equal "html-image-data", File.binread(File.join(image_dir, "2026-08-30-weekly-2026-08-30-image 2.png"))
    end
  end

  def test_rejects_image_symlink_that_escapes_source_directory
    Dir.mktmpdir("cognitive-note-boundary") do |root|
      source_dir = File.join(root, "source")
      outside_file = File.join(root, "private.txt")
      FileUtils.mkdir_p(source_dir)
      File.write(outside_file, "private")
      File.symlink(outside_file, File.join(source_dir, "leak.png"))

      assert_nil local_image_source("leak.png", source_dir: source_dir)
    end
  end
end
