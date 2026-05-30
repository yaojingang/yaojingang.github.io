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
- All article-page links open in a new tab. In-page anchors, `mailto:`, and `tel:` links are excluded from this rule.
