#!/usr/bin/env ruby
# frozen_string_literal: true

require "date"
require "cgi"
require "fileutils"
require "uri"
require "yaml"

ROOT = File.expand_path("..", __dir__)
SOURCE_FILE = ENV.fetch("SOURCE_FILE", "/Users/laoyao/AI Coding/04-Content/Articles/《姚金刚认知随笔》/《姚金刚认知随笔》.md")
SOURCE_DIR = ENV.fetch("SOURCE_DIR", File.dirname(SOURCE_FILE))
IMAGE_DIR = File.join(ROOT, "assets/cognitive-notes/images")
POSTS_DIR = File.join(ROOT, "_posts")
EN_IMPORT_DIR = File.join(ROOT, "_imports/cognitive-notes/en")

IMPORT_LIMIT = ENV["LIMIT"] ? Integer(ENV.fetch("LIMIT")) : nil

POSTS = {
  "2026-06-28" => {
    slug: "second-geo-public-session",
    en_title: "The Second GEO Public Session",
    zh_description: "这篇随笔从第二场GEO公开课出发，讨论GEO内容工程、创业边界、好销售、面试判断、丰裕时代心态，以及TokKit、ChatGPT采集Skill和GEOFlow等开源进展。",
    en_description: "This essay starts from the second GEO public session, then explores GEO content engineering, entrepreneurial boundaries, good sales, interview judgment, abundance-era mindsets, and open-source updates across TokKit, a ChatGPT crawler skill, and GEOFlow.",
    zh_tags: %w[GEO AI 商业 开源 认知],
    en_tags: ["GEO", "AI", "Business", "Open Source", "Cognition"]
  },
  "2026-06-21" => {
    slug: "subtraction-and-continuity",
    en_title: "Subtraction and Continuity",
    zh_description: "这篇随笔从减法与连续性谈起，讨论模型可靠性训练、元 Skill 2.0 重构、GEM 广告、DeepSeek 诊断 Skill 和开源项目盈利模式。",
    en_description: "This essay starts with subtraction and continuity, then moves through model reliability training, the 2.0 redesign of yao-meta-skill, GEM advertising, a DeepSeek diagnostic skill for GEO analysis, and practical ways open-source projects can build sustainable revenue.",
    zh_tags: %w[认知 AI Skill GEO 开源],
    en_tags: ["Cognition", "AI", "Skills", "GEO", "Open Source"]
  },
  "2026-05-03" => {
    slug: "meta-skill-value",
    en_title: "The Value of Meta-Skills",
    zh_description: "这篇随笔从元Skill的价值切入，讨论它如何沉淀个人经验、抽象AI协作方式，并延伸到Skill体系、开源协作、团队能力建设和商业信号判断。",
    en_description: "This essay treats meta-skills as more than generators. It explains how they turn personal experience into reusable Skill systems, clarify how people collaborate with AI, and connect open source work with team capability building, business signal judgment, and long-term AI organization design.",
    zh_tags: %w[AI Skill Agent GEO 开源],
    en_tags: ["AI", "Meta Skills", "Agents", "GEO", "Open Source"]
  },
  "2026-04-26" => {
    slug: "agents-outnumber-humans",
    en_title: "When Agents Outnumber Humans",
    zh_description: "这篇随笔从Agent数量超过人类展开，讨论AI协作形态、学习方式、商业信号、贝叶斯决策Skill和Agent组织中的Memory建设。",
    en_description: "This essay starts from the possibility that intelligent agents may outnumber humans, then moves through agent organizations, high-quality learning, business signals, Bayesian decision skills, and the memory systems future AI-native teams will need to coordinate people, tools, customers, and context.",
    zh_tags: %w[AI Agent 学习 决策 组织],
    en_tags: ["AI", "Agents", "Learning", "Decision Making", "Organizations"]
  },
  "2026-04-19" => {
    slug: "three-years-to-agi",
    en_title: "Three Years From AGI",
    zh_description: "这篇随笔围绕AGI临近展开，讨论指数增长、人机融合、健康体系、无限游戏、社群信任、飞书CLI和AI进入团队绩效流程的实践。",
    en_description: "This essay reflects on the accelerating path toward AGI, then connects that shift with health systems, infinite games, community trust, Feishu CLI workflows, and practical ways AI can enter team performance processes, personal habits, and everyday judgment.",
    zh_tags: %w[AI AGI 健康 无限游戏 工作流],
    en_tags: ["AI", "AGI", "Health", "Infinite Games", "Workflow"]
  },
  "2026-04-12" => {
    slug: "geo-conference",
    en_title: "Organizing a GEO Conference",
    zh_description: "这篇随笔记录第一届GEO主题大会后的思考，讨论AI搜索时代的品牌发现、志愿者组织、技术管理、企业Token预算和Agent供应链安全。",
    en_description: "This essay records reflections after the first GEO conference, covering brand discovery in AI search, volunteer organization, technology leadership, enterprise token budgets, AI-driven IT outsourcing, and agent supply-chain security as AI starts reshaping products, teams, and growth.",
    zh_tags: %w[GEO AI 活动 组织 安全],
    en_tags: ["GEO", "AI", "Events", "Organizations", "Security"]
  },
  "2026-04-05" => {
    slug: "ai-native-team",
    en_title: "What an AI Native Team Looks Like",
    zh_description: "这篇随笔从启用X和开源元Skill写起，讨论AI Native团队的协作工具、Agent First思维、习惯形成、执行力和大客户成交方法。",
    en_description: "This essay begins with launching on X and open-sourcing a meta-skill, then explores what an AI-native team needs: Agent First thinking, GitHub-based collaboration, Feishu CLI workflows, habit design, execution, and enterprise sales capability in daily work.",
    zh_tags: ["AI Native", "Agent", "Skill", "GitHub", "习惯"],
    en_tags: ["AI Native", "Agents", "Skills", "GitHub", "Habits"]
  }
}.freeze

def yaml_array(values)
  "[#{values.map { |value| value.to_s.inspect }.join(", ")}]"
end

def read_markdown_file(path)
  text = File.read(path)
  return [{}, text] unless text.start_with?("---\n")

  match = text.match(/\A---\s*\n(.*?)\n---\s*\n/m)
  return [{}, text] unless match

  frontmatter = YAML.safe_load(match[1], permitted_classes: [Date, Time], aliases: true) || {}
  [frontmatter, match.post_match]
end

def fallback_slug(date)
  "weekly-#{date}"
end

def normalize_title(title)
  title.gsub(/<[^>]+>/, "").gsub(/&#x20;|&nbsp;/, " ").strip
end

def public_image_url(raw_path)
  filename = File.basename(raw_path)
  "/assets/cognitive-notes/images/#{filename.gsub(" ", "%20")}"
end

def normalize_markdown(content)
  content = content.gsub(/<span[^>]*>(.*?)<\/span>/m, "\\1")
  content = content.gsub(/&#x20;|&nbsp;/, "")
  content = normalize_links(content)
  content = content.gsub(/^####\s+/, "## ")
  content = content.gsub(/^#####\s+/, "### ")
  content = normalize_numbered_emphasis_headings(content)
  content = normalize_ordered_lists(content)
  content = normalize_obsidian_embeds(content)

  content = content.gsub(/!\[([^\]]*)\]\(([^)]+)\)/) do
    original = Regexp.last_match(0)
    alt = Regexp.last_match(1)
    raw = Regexp.last_match(2).strip
    raw = raw[1..-2] if raw.start_with?("<") && raw.end_with?(">")
    clean = raw.split(/[?#]/).first

    next original unless clean.start_with?("images/")

    src = File.join(SOURCE_DIR, clean)
    dest = File.join(IMAGE_DIR, File.basename(clean))
    raise "Missing image: #{src}" unless File.exist?(src)

    FileUtils.mkdir_p(IMAGE_DIR)
    FileUtils.cp(src, dest)
    "![#{alt}](#{public_image_url(clean)})"
  end

  normalize_image_tables(content)
end

def normalize_obsidian_embeds(content)
  patterns = [
    /!\\\[\\\[([^\]|]+)(?:\|[^\]]+)?\]\]/,
    /!\[\[([^\]|]+)(?:\|[^\]]+)?\]\]/
  ]

  patterns.each do |pattern|
    content = content.gsub(pattern) do
      raw_name = Regexp.last_match(1).strip
      source_path = [
        File.join(SOURCE_DIR, raw_name),
        File.join(SOURCE_DIR, "images", raw_name)
      ].find { |candidate| File.exist?(candidate) }

      unless source_path
        next "<!-- Missing image: #{CGI.escapeHTML(raw_name)} -->"
      end

      FileUtils.mkdir_p(IMAGE_DIR)
      dest = File.join(IMAGE_DIR, File.basename(source_path))
      FileUtils.cp(source_path, dest)
      "![#{File.basename(source_path, '.*')}](#{public_image_url(source_path)})"
    end
  end

  content
end

def normalize_links(content)
  content = normalize_tracking_markdown_links(content)
  replacements = {
    "比如我自己的元Skill：yao-meta-skill（已开源：https://github.com/yaojingang/yao-meta-skill）" =>
      "比如我自己的元Skill：[yao-meta-skill](https://github.com/yaojingang/yao-meta-skill)（已开源）",
    "GitHub开源地址：https://github.com/yaojingang/yao-open-skills/tree/main/skills/yao-tutorial-skill" =>
      "GitHub开源地址：[yao-tutorial-skill](https://github.com/yaojingang/yao-open-skills/tree/main/skills/yao-tutorial-skill)",
    "Hugging Face Papers：https://huggingface.co/papers" =>
      "[Hugging Face Papers](https://huggingface.co/papers)",
    "arXiv：https://arxiv.org" =>
      "[arXiv](https://arxiv.org)",
    "乔木博客：https://blog.qiaomu.ai/" =>
      "[乔木博客](https://blog.qiaomu.ai/)",
    "GitHub地址：\n\nhttps://github.com/yaojingang/yao-open-skills/tree/main/skills/yao-bayesian-skill" =>
      "GitHub地址：[yao-bayesian-skill](https://github.com/yaojingang/yao-open-skills/tree/main/skills/yao-bayesian-skill)",
    "视频播客地址：https://www.youtube.com/watch?v=8iWSNwIRazc" =>
      "视频播客地址：[Kurzweil 访谈视频](https://www.youtube.com/watch?v=8iWSNwIRazc)",
    "乔木博客解读：https://blog.qiaomu.ai/2026-04-17-CtTDFI" =>
      "乔木博客解读：[离 AGI 还有 3 年](https://blog.qiaomu.ai/2026-04-17-CtTDFI)",
    "所有嘉宾老师的干货合集，详见：https://mp.weixin.qq.com/s/2P\\_zSjJkybl-rAyZjMIQAw" =>
      "所有嘉宾老师的干货合集，详见：[GEO 大会干货合集](https://mp.weixin.qq.com/s/2P_zSjJkybl-rAyZjMIQAw)",
    "论文原文：https://arxiv.org/pdf/2604.08407v1" =>
      "论文原文：[Your Agent Is Mine](https://arxiv.org/pdf/2604.08407v1)",
    "受向阳的邀请和推荐，正式了启用了X（Twitter）：https://x.com/laoyaoke" =>
      "受向阳的邀请和推荐，正式启用了 [X（Twitter）](https://x.com/laoyaoke)",
    "GitHub地址：https://github.com/yaojingang/yao-meta-skill" =>
      "GitHub地址：[yao-meta-skill](https://github.com/yaojingang/yao-meta-skill)"
  }

  replacements.each do |from, to|
    content = content.gsub(from, to)
  end

  normalize_bare_urls(content)
end

def normalize_tracking_markdown_links(content)
  content.gsub(/\[(https?:\/\/[^\]\s]+)\]\(https:\/\/t\.co\/[^)]+\)/) do
    url = Regexp.last_match(1)
    "[#{url_label(url)}](#{url})"
  end
end

def url_label(url)
  host = URI.parse(url).host
  host ? host.sub(/\Awww\./, "") : "link"
rescue URI::InvalidURIError
  "link"
end

def normalize_bare_urls(content)
  content.gsub(%r{(?<!\]\()(?<!\()(?<!["'=])https?://[^\s<>)]+}) do |raw_url|
    trailing = raw_url[/[，。；、,.]+\z/].to_s
    url = trailing.empty? ? raw_url : raw_url[0...-trailing.length]
    "[#{url_label(url)}](#{url})#{trailing}"
  end
end

def ordered_list_line?(line)
  line.to_s.match?(/\A[ \t]{0,3}(?:>[ \t]*)?\d{1,3}\.[ \t]+/)
end

def normalize_numbered_emphasis_headings(content)
  content.lines(chomp: true).map do |line|
    line.sub(/\A\*\*(\d{1,3})[、\)）.．][ \t]*(.+?)\s*\*\*\s*\z/) do
      number = Regexp.last_match(1)
      title = Regexp.last_match(2).strip.sub(/[：:]\z/, "")
      "### #{number}. #{title}"
    end
  end.join("\n")
end

def normalize_ordered_list_marker(line)
  normalized = line.sub(/\A([ \t]{0,3}(?:>[ \t]*)?)(\d{1,3})[.．][ \t]+/, "\\1\\2. ")
  normalized = normalized.sub(/\A([ \t]{0,3}(?:>[ \t]*)?)(\d{1,3})[)）][ \t]*/, "\\1\\2. ")
  normalized.sub(/\A([ \t]{0,3}(?:>[ \t]*)?)(\d{1,3})、[ \t]*/, "\\1\\2. ")
end

def normalize_ordered_lists(content)
  lines = content.lines(chomp: true).map { |line| normalize_ordered_list_marker(line) }
  output = []

  lines.each_with_index do |line, index|
    if line.strip.empty? && ordered_list_line?(output.last) && ordered_list_line?(lines[index + 1])
      next
    end

    output << line
  end

  output.join("\n")
end

def table_cells(line)
  stripped = line.to_s.strip
  return [] unless stripped.start_with?("|") && stripped.end_with?("|")

  stripped.split("|", -1)[1...-1].map(&:strip)
end

def markdown_table_separator?(line)
  cells = table_cells(line)
  return false if cells.empty?

  cells.all? { |cell| cell.match?(/\A:?-{3,}:?\z/) }
end

def markdown_image_cell?(cell)
  cell.match?(/\A!\[[^\]]*\]\([^)]+\)\z/)
end

def markdown_image_row?(line)
  cells = table_cells(line)
  return false if cells.empty?

  cells.all? { |cell| markdown_image_cell?(cell) }
end

def image_from_cell(cell)
  match = cell.match(/\A!\[([^\]]*)\]\(([^)]+)\)\z/)
  {
    alt: match[1],
    src: match[2]
  }
end

def image_grid_html(rows, column_count)
  images = rows.flat_map { |row| table_cells(row).map { |cell| image_from_cell(cell) } }
  grid_class = "markdown-image-grid markdown-image-grid-#{[[column_count, 1].max, 4].min}"
  html = ["<div class=\"#{grid_class}\">"]
  images.each do |image|
    html << "  <img src=\"#{CGI.escapeHTML(image[:src])}\" alt=\"#{CGI.escapeHTML(image[:alt])}\" loading=\"lazy\">"
  end
  html << "</div>"
  html.join("\n")
end

def normalize_image_tables(content)
  lines = content.lines(chomp: true)
  output = []
  index = 0

  while index < lines.length
    if markdown_image_row?(lines[index]) && markdown_table_separator?(lines[index + 1])
      rows = [lines[index]]
      cursor = index + 2
      while cursor < lines.length && markdown_image_row?(lines[cursor])
        rows << lines[cursor]
        cursor += 1
      end

      if table_cells(lines[cursor]).empty?
        output << image_grid_html(rows, table_cells(lines[index]).size)
        index = cursor
        next
      end
    end

    output << lines[index]
    index += 1
  end

  output.join("\n")
end

def section_titles(body)
  body.scan(/^##\s+(.+)$/).flatten.map { |title| normalize_title(title) }.reject(&:empty?)
end

def derive_zh_description(title, body)
  topics = section_titles(body).first(4)
  if topics.empty?
    description = "这篇随笔记录「#{title}」相关思考，围绕个人认知、AI工作流、组织协作和长期实践展开，保留当周的观察、判断和方法沉淀。"
  else
    description = "这篇随笔记录「#{title}」相关思考，内容涉及#{topics.join("、")}等主题，并沉淀为个人认知、工作流和组织实践中的阶段性判断。"
  end

  description.length > 100 ? "#{description[0, 96]}。" : description
end

def derive_zh_tags(title, body)
  text = "#{title}\n#{body}"
  rules = [
    [/AI|Agent|智能体|模型|AGI|LLM/i, "AI"],
    [/GEO|搜索|SEO/i, "GEO"],
    [/Skill|技能/i, "Skill"],
    [/组织|团队|管理|协作/, "组织"],
    [/营销|增长|商业|客户|销售/, "商业"],
    [/学习|知识|认知|思考/, "认知"],
    [/自动化|工作流|工具|GitHub|飞书/i, "工作流"]
  ]
  tags = rules.map { |pattern, tag| tag if text.match?(pattern) }.compact
  tags.empty? ? ["认知随笔"] : tags.first(5)
end

def metadata_for(entry, body)
  existing = POSTS[entry[:date]]
  fallback = {
    slug: fallback_slug(entry[:date]),
    en_title: entry[:title],
    zh_description: derive_zh_description(entry[:title], body),
    en_description: "",
    zh_tags: derive_zh_tags(entry[:title], body),
    en_tags: ["Cognitive Notes"]
  }
  fallback.merge(existing || {})
end

def post_frontmatter(meta, title, date, lang:, has_translation: false)
  if lang == :zh
    permalink = "/cognitive-notes/#{meta[:slug]}/"
    translation = "/essays/#{meta[:slug]}-en/"
    translation_fields = has_translation ? "translation: #{translation}\ntranslation_title: #{meta[:en_title].inspect}\n" : ""
    <<~YAML
      ---
      layout: post
      title: #{title.inspect}
      date: #{date} 10:00:00 +0800
      categories: ["认知随笔"]
      tags: #{yaml_array(meta[:zh_tags])}
      description: #{meta[:zh_description].inspect}
      lang: zh-CN
      weekly: true
      week: #{date}
      permalink: #{permalink}
      #{translation_fields.chomp}
      ---

    YAML
  else
    permalink = "/essays/#{meta[:slug]}-en/"
    translation_of = "/cognitive-notes/#{meta[:slug]}/"
    <<~YAML
      ---
      layout: post
      title: #{meta[:en_title].inspect}
      date: #{date} 09:30:00 +0800
      categories: ["essays"]
      tags: #{yaml_array(meta[:en_tags])}
      description: #{meta[:en_description].inspect}
      lang: en
      weekly: true
      week: #{date}
      permalink: #{permalink}
      translation_of: #{translation_of}
      translation_of_title: #{title.inspect}
      ---

    YAML
  end
end

lines = File.readlines(SOURCE_FILE)
entries = []

lines.each_with_index do |line, index|
  next unless line =~ /^###\s+(\d{4})\.(\d{2})\.(\d{2})\s+(.+)$/

  entries << {
    start: index,
    date: "#{Regexp.last_match(1)}-#{Regexp.last_match(2)}-#{Regexp.last_match(3)}",
    title: normalize_title(Regexp.last_match(4))
  }
end

entries_to_import = IMPORT_LIMIT ? entries.first(IMPORT_LIMIT) : entries
written_zh = 0
written_en = 0
kept_en = 0
missing_en = 0

entries_to_import.each_with_index do |entry, index|
  following = entries[index + 1]
  finish = following ? following[:start] : lines.length
  body = normalize_markdown(lines[(entry[:start] + 1)...finish].join.strip)
  meta = metadata_for(entry, body)
  en_source = File.join(EN_IMPORT_DIR, "#{meta[:slug]}.md")
  en_path = File.join(POSTS_DIR, "#{entry[:date]}-#{meta[:slug]}-en.md")
  en_source_frontmatter = {}
  en_source_body = nil

  if File.exist?(en_source)
    en_source_frontmatter, en_source_body = read_markdown_file(en_source)
    meta = meta.merge(
      en_title: en_source_frontmatter["title"] || meta[:en_title],
      en_description: en_source_frontmatter["description"] || meta[:en_description],
      en_tags: en_source_frontmatter["tags"] || meta[:en_tags]
    )
  end

  has_translation = File.exist?(en_source) || File.exist?(en_path)

  zh_path = File.join(POSTS_DIR, "#{entry[:date]}-#{meta[:slug]}.md")
  File.write(zh_path, post_frontmatter(meta, entry[:title], entry[:date], lang: :zh, has_translation: has_translation) + body + "\n")
  written_zh += 1
  puts "wrote #{zh_path}"

  if File.exist?(en_source)
    en_body = normalize_markdown(en_source_body.strip)
    File.write(en_path, post_frontmatter(meta, entry[:title], entry[:date], lang: :en) + en_body + "\n")
    written_en += 1
    puts "wrote #{en_path}"
  elsif File.exist?(en_path)
    kept_en += 1
    puts "kept existing #{en_path}"
  else
    missing_en += 1
  end
end

puts "summary: zh=#{written_zh}, en_written=#{written_en}, en_kept=#{kept_en}, en_missing=#{missing_en}"
