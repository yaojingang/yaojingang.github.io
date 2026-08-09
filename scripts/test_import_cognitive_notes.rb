#!/usr/bin/env ruby
# frozen_string_literal: true

require "minitest/autorun"
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
end
