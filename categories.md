---
layout: page
title: 分类
permalink: /categories/
description: 按分类浏览文章。
---

<div class="taxonomy-list">
  {% assign categories = site.categories | sort %}
  {% for category in categories %}
  <section class="taxonomy-group">
    <h2>{{ category[0] }} <span>({{ category[1].size }})</span></h2>
    <ul>
      {% for post in category[1] %}
      <li>
        <a href="{{ post.url | relative_url }}">{{ post.title }}</a>
        <span>{{ post.date | date: "%Y-%m-%d" }}</span>
      </li>
      {% endfor %}
    </ul>
  </section>
  {% endfor %}
</div>
