---
layout: page
title: 标签
permalink: /tags/
description: 按标签浏览文章。
---

<div class="tag-cloud">
  {% assign tags = site.tags | sort %}
  {% for tag in tags %}
  <a href="#{{ tag[0] | slugify }}">{{ tag[0] }} <span>{{ tag[1].size }}</span></a>
  {% endfor %}
</div>

<div class="taxonomy-list">
  {% for tag in tags %}
  <section class="taxonomy-group" id="{{ tag[0] | slugify }}">
    <h2>{{ tag[0] }} <span>({{ tag[1].size }})</span></h2>
    <ul>
      {% for post in tag[1] %}
      <li>
        <div>
          <a href="{{ post.url | relative_url }}">{{ post.title }}</a>
          <p>{{ post.excerpt | strip_html | truncate: 64 }}</p>
        </div>
        <span>{{ post.date | date: "%Y-%m-%d" }}</span>
      </li>
      {% endfor %}
    </ul>
  </section>
  {% endfor %}
</div>
