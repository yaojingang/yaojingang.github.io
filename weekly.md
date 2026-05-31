---
layout: page
title: 每周随笔
permalink: /weekly/
kicker: Weekly Notes
description: 以周为单位同步的个人随笔归档。这里会成为博客和 GitHub 内容仓库之间的主要同步入口。
hide_header: true
---

{% assign weekly_posts = site.posts | where_exp: "note", "note.weekly" %}
{% assign weekly_notes = site.weekly | concat: weekly_posts | sort: "date" | reverse %}
{% assign chinese_weekly_notes = weekly_notes | where_exp: "note", "note.lang != 'en'" %}
{% assign english_weekly_notes = weekly_notes | where_exp: "note", "note.lang == 'en'" %}

{% if weekly_notes.size > 0 %}
<section class="weekly-tabs" aria-label="随笔语言切换">
  <input class="weekly-tab-input" type="radio" name="weekly-language" id="weekly-tab-zh" checked>
  <input class="weekly-tab-input" type="radio" name="weekly-language" id="weekly-tab-en">
  <span class="weekly-target" id="weekly-english" aria-hidden="true"></span>

  <div class="weekly-tab-list" role="tablist" aria-label="随笔语言">
    <label class="weekly-tab" for="weekly-tab-zh" role="tab">
      <span>中文</span>
      <small>{{ chinese_weekly_notes.size }}</small>
    </label>
    <label class="weekly-tab" for="weekly-tab-en" role="tab">
      <span>English</span>
      <small>{{ english_weekly_notes.size }}</small>
    </label>
  </div>

  <div class="weekly-tab-panel weekly-tab-panel-zh" role="tabpanel" aria-label="中文随笔">
  {% if chinese_weekly_notes.size > 0 %}
  <div class="weekly-list" data-pagination-list data-pagination-param="zh" data-page-size="20">
    {% for note in chinese_weekly_notes %}
    <article class="weekly-row" data-pagination-item>
      <div>
        <p class="weekly-date">{{ note.week | default: note.date | date: "%Y-%m-%d" }}</p>
        <h2><a href="{{ note.url | relative_url }}">{{ note.title }}</a></h2>
        <p>{{ note.description | default: note.excerpt | strip_html | truncate: 120 }}</p>
      </div>
      <div class="weekly-row-links">
        <a class="read-more-link" href="{{ note.url | relative_url }}">阅读</a>
        {% if note.translation %}
        <a class="resource-secondary-link" href="{{ note.translation | relative_url }}">English</a>
        {% endif %}
      </div>
    </article>
    {% endfor %}
  </div>
  <nav class="pagination-control" data-pagination-control aria-label="中文随笔分页"></nav>
  {% else %}
  <div class="weekly-empty">中文随笔会在同步后显示在这里。</div>
  {% endif %}
  </div>

  <div class="weekly-tab-panel weekly-tab-panel-en" role="tabpanel" aria-label="英文随笔">
  {% if english_weekly_notes.size > 0 %}
  <div class="weekly-list" data-pagination-list data-pagination-param="en" data-page-size="20">
    {% for note in english_weekly_notes %}
    <article class="weekly-row" data-pagination-item>
      <div>
        <p class="weekly-date">{{ note.week | default: note.date | date: "%Y-%m-%d" }}</p>
        <h2><a href="{{ note.url | relative_url }}">{{ note.title }}</a></h2>
        <p>{{ note.description | default: note.excerpt | strip_html | truncate: 120 }}</p>
      </div>
      <div class="weekly-row-links">
        <a class="read-more-link" href="{{ note.url | relative_url }}">Read</a>
        {% if note.translation_of %}
        <a class="resource-secondary-link" href="{{ note.translation_of | relative_url }}">中文原文</a>
        {% endif %}
      </div>
    </article>
    {% endfor %}
  </div>
  <nav class="pagination-control" data-pagination-control aria-label="英文随笔分页"></nav>
  {% else %}
  <div class="weekly-empty">英文翻译版会归入这里，不进入首页默认列表。</div>
  {% endif %}
  </div>
</section>
{% else %}
<section class="empty-state">
  <p class="panel-kicker">Ready for Sync</p>
  <h2>每周随笔区已经预留好。</h2>
  <p>
    等你提供随笔文档后，我会把内容按周拆分为 Markdown 文件，生成这里的归档列表和每周详情页。
  </p>
</section>
{% endif %}
