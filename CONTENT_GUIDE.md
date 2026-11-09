# Content Guide

## Link Network

- `/link-network/` reads the dated homepage-link snapshot in `_data/link_network.json`.
- Keep its node catalog in sync with `_data/friends.yml` and `_data/friend_products.yml`. A site listed in both has one node. Preserve project paths on shared hosting domains.
- Add a directed edge only when the source homepage actually links to the target. Record the collection date and source homepage; exclude self-links and duplicate edges.
- `collected` records whether a node's homepage was checked. Product homepages are currently outside the collection scope, so their outgoing links remain uncollected.
- Run `ruby scripts/test_link_network.rb` after editing the catalog or snapshot. Also check node selection, incoming/outgoing lists, filters, zoom, panning, keyboard access, and mobile layout in the browser.

## Agent Subscription

- The homepage copies one sentence pointing to `/subscribe/` and shows a brief success notification. The textarea contains that same sentence for manual copy when clipboard access or JavaScript is unavailable.
- `/subscribe/` introduces the subscription. Agents read `/subscribe/agent.txt` and `/subscribe/manifest.json` for the versioned protocol, actual content URLs, default Sunday 21:00 `Asia/Shanghai` schedule, and reader CLI download checksum. Derive public URLs from the Jekyll site origin and base URL.
- `/feed-weekly.xml` and `/subscribe/feed.json` share `_includes/weekly-feed-items.liquid` so both select the same latest 12 published Chinese weekly notes. Filter future collection dates before limiting the list. JSON Feed supplies complete rendered article bodies; the existing language feeds remain available.
- `assets/cli/yao-notes.rb` is a standalone Ruby standard-library reader. It reads public content and manages its dedicated state directory. Keep it separate from the private `laoyao` operations entrypoint. It uses no blog credentials and creates no scheduler or notification channel.
- Update `_data/agent_subscription.yml` with the CLI SHA-256 whenever the script changes. The checksum in the rendered manifest and protocol must match the published file. Version changes must remain consistent with the CLI's `--version` output.
- `init` establishes the historical baseline and queues the newest issue. `check` discovers new issues and leases pending content for 15 minutes; interrupted work can retry after expiration. `ack` confirms caller processing and `release` retains the pending batch. Acknowledgement requires the workspace's success confirmation; the CLI does not verify external delivery. A gap beyond the 12-issue window is reported for archive reconciliation before confirmation.
- Repeated initialization preserves the discovery watermark. Confirmation commands report lock contention as a retryable error and retain durable receipts so completed or partial acknowledgements can be replayed after an interrupted response. Reconcile successful previous runs before claiming another batch; terminal-free clients persist the same watermark, archive floor and gap recovery records.
- The reader's AI workspace owns scheduling, notification, cancellation and capability checks. Persist actual source URLs, CLI/state paths and initialized history in the scheduled task; reuse existing schedules and preferences. Workspaces without a terminal can follow the same protocol with JSON Feed and their own persistent state.
- Run `ruby scripts/test_agent_subscription.rb` and `ruby scripts/test_yao_notes_cli.rb`. Validate the downloaded CLI in an isolated directory, initial/new/retried batches, failed reads, corrupted state, and same-origin redirects. Check copy success/denial, the toast, JavaScript-disabled access and desktop/mobile layouts in an isolated browser.
- Keep the feed compatible with both GitHub Pages' Jekyll 3.10 and the main server's Jekyll 4.2. Use single-condition `where_exp` filters; Jekyll 3.10 rejects combined `or` expressions. Run the regression suite with each version before publishing.

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
