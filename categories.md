---
layout: page
title: 分类
permalink: /categories/
kicker: Categories
description: 按主题浏览博客文章，适合从内容类型而不是时间线进入。
---

<section class="blog-filterbar inner-filterbar" aria-label="分类切换">
  <div class="filter-tabs">
    <a class="filter-tab is-active" href="{{ '/categories/' | relative_url }}">Categories</a>
    <a class="filter-tab" href="{{ '/tags/' | relative_url }}">Tags</a>
    <a class="filter-tab" href="{{ '/archive/' | relative_url }}">Archive</a>
    <a class="filter-tab" href="{{ '/resources/' | relative_url }}">Resources</a>
  </div>
</section>

<div class="taxonomy-grid">
  {% assign categories = site.categories | sort %}
  {% for category in categories %}
  <section class="taxonomy-group">
    <header class="taxonomy-head">
      <div>
        <p class="card-kicker">Category</p>
        <h2>{{ category[0] }}</h2>
      </div>
      <span>{{ category[1].size }}</span>
    </header>
    <ul>
      {% for post in category[1] %}
      <li>
        <a href="{{ post.url | relative_url }}">
          <div>
            <h3>{{ post.title }}</h3>
            <p>{{ post.description | default: post.excerpt | strip_html | truncate: 74 }}</p>
          </div>
          <time datetime="{{ post.date | date_to_xmlschema }}">{{ post.date | date: "%Y-%m-%d" }}</time>
        </a>
      </li>
      {% endfor %}
    </ul>
  </section>
  {% endfor %}
</div>
