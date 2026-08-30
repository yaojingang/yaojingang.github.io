#!/usr/bin/env ruby
# frozen_string_literal: true

require "minitest/autorun"
require_relative "markdown_image_paths"

class MarkdownImagePathsTest < Minitest::Test
  def test_restores_markdown_and_html_image_paths_after_translation
    source = <<~MD
      ![示例](图片和附件/Codex%20图像.png)
      <img src="图片和附件/image%201.png" alt="示例" loading="lazy">
    MD
    translated = <<~MD
      ![Example](images-and-attachments/Codex%20Image.png)
      <img src="images-and-attachments/image%201.png" alt="Example" loading="lazy">
    MD

    restored = MarkdownImagePaths.restore(source, translated)

    assert_includes restored, "![Example](图片和附件/Codex%20图像.png)"
    assert_includes restored, "src=\"图片和附件/image%201.png\""
    assert_includes restored, "alt=\"Example\""
  end
end
