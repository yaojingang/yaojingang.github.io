# frozen_string_literal: true

module MarkdownImagePaths
  MARKDOWN_IMAGE = /(!\[[^\]]*\]\()([^)]+)(\))/
  HTML_IMAGE = /(<img\b[^>]*\bsrc\s*=\s*["'])([^"']+)(["'][^>]*>)/i

  module_function

  def restore(source, translated)
    restored = restore_pattern(source, translated, MARKDOWN_IMAGE, "Markdown image")
    restore_pattern(source, restored, HTML_IMAGE, "HTML image")
  end

  def restore_pattern(source, translated, pattern, label)
    source_paths = source.scan(pattern).map { |match| match[1] }
    translated_paths = translated.scan(pattern).map { |match| match[1] }

    unless source_paths.length == translated_paths.length
      raise "#{label} count changed during translation: source=#{source_paths.length}, translated=#{translated_paths.length}"
    end

    index = 0
    translated.gsub(pattern) do
      path = source_paths.fetch(index)
      index += 1
      "#{Regexp.last_match(1)}#{path}#{Regexp.last_match(3)}"
    end
  end
end
