---
layout: page
title: 归档
permalink: /archive/
kicker: Archive
description: 按时间查看所有文章。
hide_header: true
---

<div class="archive-list">
  {% assign posts_by_year = site.posts | group_by_exp: "post", "post.date | date: '%Y'" %}
  {% for year in posts_by_year %}
  <section class="archive-year">
    <h2>{{ year.name }}</h2>
    <ul>
      {% for post in year.items %}
      <li>
        <div>
          <a href="{{ post.url | relative_url }}">{{ post.title }}</a>
          <p>{{ post.excerpt | strip_html | truncate: 68 }}</p>
        </div>
        <span>{{ post.date | date: "%m-%d" }}</span>
      </li>
      {% endfor %}
    </ul>
  </section>
  {% endfor %}
</div>
