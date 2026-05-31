#!/usr/bin/env ruby
# frozen_string_literal: true

require "date"
require "fileutils"
require "json"
require "net/http"
require "uri"
require "yaml"

STDOUT.sync = true
STDERR.sync = true

ROOT = File.expand_path("..", __dir__)
POSTS_DIR = File.join(ROOT, "_posts")
EN_IMPORT_DIR = File.join(ROOT, "_imports/cognitive-notes/en")

MODEL = ENV.fetch("DASHSCOPE_MODEL", "qwen-plus")
BASE_URL = ENV.fetch("DASHSCOPE_BASE_URL", "https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions")
LIMIT = ENV["LIMIT"] ? Integer(ENV.fetch("LIMIT")) : nil
ONLY_SLUG = ENV["SLUG"]
FORCE = ENV["FORCE"] == "1"
THREADS = [Integer(ENV.fetch("THREADS", "1")), 1].max

COMMON_CJK_REPAIRS = {
  "traffic红利" => "traffic dividend",
  "红利" => "dividend",
  "图文" => "image-and-text",
  "韭菜" => "leeks",
  "敷衍" => "perfunctory work",
  "形态" => "form",
  "雷军" => "Lei Jun",
  "存量" => "stock",
  "增量" => "incremental growth",
  "短视频" => "short-video",
  "精力" => "energy",
  "常识" => "common-sense",
  "GEO公开课" => "GEO public session",
  "eye-care公益" => "eye-care public-interest",
  "公开课" => "public session",
  "公益" => "public-interest"
}.freeze

def read_markdown_file(path)
  text = File.read(path)
  return [{}, text] unless text.start_with?("---\n")

  match = text.match(/\A---\s*\n(.*?)\n---\s*\n/m)
  return [{}, text] unless match

  frontmatter = YAML.safe_load(match[1], permitted_classes: [Date, Time], aliases: true) || {}
  [frontmatter, match.post_match]
end

def slug_for(frontmatter)
  frontmatter.fetch("permalink").match(%r{/cognitive-notes/([^/]+)/})[1]
end

def strip_code_fence(text)
  stripped = text.to_s.strip
  stripped = stripped.sub(/\A```(?:text|markdown)?\s*/i, "")
  stripped.sub(/```\s*\z/, "").strip
end

def clean_line(value)
  value.to_s.strip.sub(/\A["']/, "").sub(/["']\z/, "")
end

def parse_translation_response(text)
  content = strip_code_fence(text)
  match = content.match(/\ATITLE:\s*(.+?)\nDESCRIPTION:\s*(.+?)\nTAGS:\s*(.+?)\n---BODY---\s*\n(.*)\z/m)
  raise "Translation response did not match expected format" unless match

  tags = match[3].split(",").map { |tag| clean_line(tag) }.reject(&:empty?).first(6)
  raise "Translation response did not include tags" if tags.empty?

  {
    "title" => clean_line(match[1]),
    "description" => clean_line(match[2]),
    "tags" => tags,
    "body" => match[4].strip
  }
end

def chat_completion(messages, max_tokens: 12_000)
  api_key = ENV.fetch("DASHSCOPE_API_KEY")
  uri = URI(BASE_URL)
  request = Net::HTTP::Post.new(uri)
  request["Authorization"] = "Bearer #{api_key}"
  request["Content-Type"] = "application/json"
  request.body = {
    model: MODEL,
    messages: messages,
    temperature: 0.25,
    max_tokens: max_tokens
  }.to_json

  response = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https", open_timeout: 30, read_timeout: 600) do |http|
    http.request(request)
  end

  unless response.is_a?(Net::HTTPSuccess)
    raise "DashScope request failed: #{response.code} #{response.body}"
  end

  data = JSON.parse(response.body)
  data.fetch("choices").first.fetch("message").fetch("content")
end

def prose_han_lines(markdown)
  markdown.lines.each_with_index.map do |line, index|
    text = line.dup
    text.gsub!(/!\[[^\]]*\]\([^)]+\)/, "")
    text.gsub!(/`[^`]*`/, "")
    text.gsub!(/<[^>]+>/, "")
    next unless text.match?(/\p{Han}/)

    [index + 1, line.strip]
  end.compact
end

def repair_common_chinese_fragments(text)
  COMMON_CJK_REPAIRS.reduce(text.to_s) do |memo, (from, to)|
    memo.gsub(from, to)
  end
end

def repair_translation_fragments(translation)
  translation.merge(
    "title" => repair_common_chinese_fragments(translation.fetch("title")),
    "description" => repair_common_chinese_fragments(translation.fetch("description")),
    "tags" => translation.fetch("tags").map { |tag| repair_common_chinese_fragments(tag) },
    "body" => repair_common_chinese_fragments(translation.fetch("body"))
  )
end

def cleanup_remaining_chinese(translation)
  translation = repair_translation_fragments(translation)
  metadata = [translation.fetch("title"), translation.fetch("description"), translation.fetch("tags").join(", ")].join("\n")
  raise "Chinese metadata remained after cleanup: #{metadata.inspect}" if metadata.match?(/\p{Han}/)

  flagged = prose_han_lines(translation.fetch("body"))
  return translation if flagged.empty?

  system_prompt = <<~PROMPT
    You are cleaning an English Markdown translation.
    Some prose lines still contain Chinese characters. Rewrite those remaining Chinese parts into natural English.
    Preserve all Markdown structure, URLs, image paths, code spans, HTML, numbers, and meaning.
    Return only the corrected Markdown body. Do not add notes or code fences.
  PROMPT

  user_prompt = <<~PROMPT
    Lines still containing Chinese prose:
    #{flagged.first(20).map { |line_no, line| "#{line_no}: #{line}" }.join("\n")}

    Full Markdown body:
    #{translation.fetch("body")}
  PROMPT

  body = strip_code_fence(
    chat_completion(
      [
        { role: "system", content: system_prompt },
        { role: "user", content: user_prompt }
      ]
    )
  )

  cleaned = repair_translation_fragments(translation.merge("body" => body))
  remaining = prose_han_lines(cleaned.fetch("body"))
  raise "Chinese prose remained after cleanup: #{remaining.first(3).inspect}" unless remaining.empty?
  metadata = [cleaned.fetch("title"), cleaned.fetch("description"), cleaned.fetch("tags").join(", ")].join("\n")
  raise "Chinese metadata remained after cleanup: #{metadata.inspect}" if metadata.match?(/\p{Han}/)

  cleaned
end

def translate_post(post)
  frontmatter = post.fetch(:frontmatter)
  body = post.fetch(:body)

  system_prompt = <<~PROMPT
    You are a senior bilingual editor translating Yao Jingang's Chinese weekly essays into natural English.

    Preserve meaning, stance, examples, dates, names, links, image paths, code, HTML, Markdown tables, and Markdown structure.
    Translate only human-readable Chinese prose. Do not translate URLs, file paths, repository names, code identifiers, or image asset paths.
    Translate mixed Chinese-English expressions into natural English. Do not leave Chinese characters in English prose unless they are inside image URLs, links, code, or necessary proper names with no English equivalent.
    Keep the author's direct first-person voice. Avoid generic AI-sounding phrasing, hype, and academic stiffness.
    Use plain ASCII punctuation where possible.
    Output exactly in this format, without code fences or extra notes:

    TITLE: <natural English title>
    DESCRIPTION: <35-70 English words summarizing the article>
    TAGS: <3-6 concise English tags separated by comma>
    ---BODY---
    <translated Markdown body>
  PROMPT

  user_prompt = <<~PROMPT
    SOURCE TITLE: #{frontmatter.fetch("title")}
    SOURCE DATE: #{frontmatter.fetch("week", frontmatter.fetch("date"))}
    SOURCE DESCRIPTION: #{frontmatter["description"]}
    SOURCE TAGS: #{Array(frontmatter["tags"]).join(", ")}

    SOURCE MARKDOWN:
    #{body.strip}
  PROMPT

  raw = chat_completion(
    [
      { role: "system", content: system_prompt },
      { role: "user", content: user_prompt }
    ]
  )

  cleanup_remaining_chinese(parse_translation_response(raw))
end

def write_import_file(path, translation)
  frontmatter = {
    "title" => translation.fetch("title"),
    "description" => translation.fetch("description"),
    "tags" => translation.fetch("tags")
  }
  FileUtils.mkdir_p(File.dirname(path))
  File.write(path, "#{frontmatter.to_yaml}---\n\n#{translation.fetch("body")}\n")
end

def translate_and_write(post, index, total)
  slug = post.fetch(:slug)
  puts "[#{index + 1}/#{total}] translating #{slug}"

  tries = 0
  begin
    tries += 1
    translation = translate_post(post)
    write_import_file(post.fetch(:en_import_path), translation)
    puts "wrote #{post.fetch(:en_import_path)}"
  rescue StandardError => e
    warn "failed #{slug}: #{e.message}"
    sleep(2 * tries)
    retry if tries < 3
    raise
  end
end

posts = Dir[File.join(POSTS_DIR, "*.md")].map do |path|
  frontmatter, body = read_markdown_file(path)
  next unless frontmatter["weekly"] == true
  next unless frontmatter["lang"] == "zh-CN"

  slug = slug_for(frontmatter)
  next if ONLY_SLUG && slug != ONLY_SLUG

  en_import_path = File.join(EN_IMPORT_DIR, "#{slug}.md")
  en_post_path = File.join(POSTS_DIR, "#{frontmatter.fetch("week")}-#{slug}-en.md")
  next if !FORCE && (File.exist?(en_import_path) || File.exist?(en_post_path))

  {
    path: path,
    frontmatter: frontmatter,
    body: body,
    slug: slug,
    en_import_path: en_import_path
  }
end.compact

posts = posts.sort_by { |post| post.fetch(:frontmatter).fetch("week").to_s }.reverse
posts = posts.first(LIMIT) if LIMIT

if posts.empty?
  puts "No missing English translations."
  exit
end

puts "model=#{MODEL}"
puts "translations_to_write=#{posts.size}"
puts "threads=#{THREADS}"

if THREADS == 1
  posts.each_with_index { |post, index| translate_and_write(post, index, posts.size) }
else
  queue = Queue.new
  posts.each_with_index { |post, index| queue << [post, index] }
  errors = Queue.new

  workers = THREADS.times.map do
    Thread.new do
      loop do
        post, index = queue.pop(true)
        translate_and_write(post, index, posts.size)
      rescue ThreadError
        break
      rescue StandardError => e
        errors << e
      end
    end
  end

  workers.each(&:join)
  raise errors.pop unless errors.empty?
end
