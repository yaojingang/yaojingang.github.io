# Content Guide

## Link Network

- `/link-network/` reads the dated homepage-link snapshot in `_data/link_network.json`.
- Keep its node catalog in sync with `_data/friends.yml` and `_data/friend_products.yml`. A site listed in both has one node. Preserve project paths on shared hosting domains.
- Add a directed edge only when the source homepage actually links to the target. Record the collection date and source homepage; exclude self-links and duplicate edges.
- `collected` records whether a node's homepage was checked. Product homepages are currently outside the collection scope, so their outgoing links remain uncollected.
- Run `ruby scripts/test_link_network.rb` after editing the catalog or snapshot. Also check node selection, incoming/outgoing lists, filters, zoom, panning, keyboard access, and mobile layout in the browser.

## Agent Subscription

- The homepage offers a copyable task prompt for Sundays at 21:00 in `Asia/Shanghai`. The reader's AI workspace creates and manages the scheduled task and notifications.
- `/feed-weekly.xml` contains metadata for the latest 12 published Chinese weekly notes, combining the weekly collection and posts marked `weekly: true`. Exclude future-dated notes before taking the latest 12, because Jekyll retains future collection documents while withholding their generated pages. Agents follow each item link to read its full article. Keep the existing full-text language feeds available.
- The prompt lives in the homepage textarea, which also supplies the clipboard text. Keep feed and archive URLs derived from the Jekyll site URL so each deployment uses its own origin.
- The saved recurring task body includes its own source URLs, schedule, and timezone. At setup, record the existing GUIDs as the historical baseline and queue the latest note for preview; later runs process newly discovered GUIDs and explicit retries. Persist the initialized state with the task so older issues stay outside subsequent deliveries.
- The website confirms clipboard success. Scheduling success, persistent delivery history, device requirements, and cancellation are reported by the reader's AI workspace. Clipboard denial reveals selectable text; the native disclosure also works with JavaScript disabled.
- Run `ruby scripts/test_agent_subscription.rb` to validate the rendered task's source URLs, published-only RSS, XML escaping, and deployment base URL. Check successful and denied clipboard access, keyboard use, and desktop/mobile layouts in an isolated preview.

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
