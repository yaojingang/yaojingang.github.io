---
layout: page
title: 标签
permalink: /tags/
kicker: Tags
description: 用标签快速定位文章中的细分主题。
---

<section class="blog-filterbar inner-filterbar" aria-label="分类切换">
  <div class="filter-tabs">
    <a class="filter-tab" href="{{ '/categories/' | relative_url }}">Categories</a>
    <a class="filter-tab is-active" href="{{ '/tags/' | relative_url }}">Tags</a>
    <a class="filter-tab" href="{{ '/archive/' | relative_url }}">Archive</a>
    <a class="filter-tab" href="{{ '/resources/' | relative_url }}">Resources</a>
  </div>
</section>

<nav class="tag-cloud" aria-label="标签索引">
  {% assign tags = site.tags | sort %}
  {% for tag in tags %}
  <a href="#{{ tag[0] | slugify }}">{{ tag[0] }} <span>{{ tag[1].size }}</span></a>
  {% endfor %}
</nav>

<div class="taxonomy-grid">
  {% for tag in tags %}
  <section class="taxonomy-group" id="{{ tag[0] | slugify }}">
    <header class="taxonomy-head">
      <div>
        <p class="card-kicker">Tag</p>
        <h2>{{ tag[0] }}</h2>
      </div>
      <span>{{ tag[1].size }}</span>
    </header>
    <ul>
      {% for post in tag[1] %}
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
