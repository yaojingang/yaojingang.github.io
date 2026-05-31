# Content Guide

## Article Summary

The `description` field in each post is the article detail summary.

- Chinese summaries should be 50 to 100 Chinese characters.
- English summaries should keep a similar information density, usually 35 to 70 words.
- The summary should extract the core topic, the main judgment, and the useful takeaway.
- Avoid only listing keywords. It should read like a compact overview of the article.
- The summary appears below the language switch entry and above the article body.

## Markdown Rendering

- Posts should stay compatible with Jekyll Kramdown, including headings, lists, blockquotes, code blocks, tables, images, and inline links.
- Image-only Markdown tables from source notes are normalized into responsive image grids during import, because Kramdown does not reliably parse table blocks that only contain a header image row.
- Normal Markdown tables are kept as tables and styled with light borders, readable padding, and image-safe cell rendering.
- Ordered lists from source notes are normalized to standard Markdown `1. item` syntax, including exported forms such as `1、item`, `1) item`, and `1）item`.
- All article-page links open in a new tab. In-page anchors, `mailto:`, and `tel:` links are excluded from this rule.

## Cognitive Notes Import

- Run `ruby scripts/import_cognitive_notes.rb` to import all weekly Chinese notes from the source Markdown file.
- Run `LIMIT=5 ruby scripts/import_cognitive_notes.rb` for a trial batch.
- Run `ruby scripts/translate_cognitive_notes.rb` to generate missing English source files into `_imports/cognitive-notes/en/`.
- Use `THREADS=4 ruby scripts/translate_cognitive_notes.rb` for controlled parallel translation, and `SLUG=weekly-YYYY-MM-DD FORCE=1 ruby scripts/translate_cognitive_notes.rb` to regenerate one article.
- English source files use front matter for `title`, `description`, and `tags`; the importer reads those fields when creating `_posts/*-en.md`.
- Translation output must preserve Markdown structure, links, image paths, tables, and code. The translation script rejects English prose with remaining Chinese characters outside image paths, code, links, or HTML.
