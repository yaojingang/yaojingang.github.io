---
layout: page
title: 关于
permalink: /about/
kicker: About
description: 关于我的背景、关注点，以及这个开源内容库的更新方向。
hide_header: true
---

<section class="about-profile">
  <div class="about-lead">
    <p class="card-kicker">About</p>
    <h2>你好，我是姚金刚。</h2>
    <p>
      来自四川，长期在北京工作和创业。AI 时代之前，我的主要职业标签是在线营销和在线教育；AI 时代之后，我把主要精力放在 AI 营销、AI 教育和 AI 工具产品上。
    </p>
    <p>
      2011 到 2020 年，我先后在中赫集团、好未来集团、猿辅导负责营销、品牌和市场管理工作。2019 年创立猎河科技，带团队探索过教育、营销和工具产品。
    </p>
    <p>
      从 2023 年开始，我系统转向 AI 应用和产品创业。目前正在构建两家 AI 创业公司，持续关注 GEO、AI 工作流、AI 教育和企业级 AI 营销。
    </p>
    <p>
      我写过 5 本书，主要方向是营销和教育，也是《AI 营销：从 SEO 到 GEO》作者。这个开源博客会继续沉淀我的随笔、资料、提示词和 AI 创业过程中的方法论。
    </p>
  </div>
</section>

<section class="about-quick-links" aria-label="常用入口">
  <span>Links</span>
  <a href="{{ '/weekly/' | relative_url }}">随笔</a>
  <a href="{{ '/resources/' | relative_url }}">资源</a>
  <a href="https://github.com/{{ site.author.github }}/yaojingang.github.io" target="_blank" rel="noopener noreferrer">GitHub</a>
  <a href="#about-comments">留言</a>
</section>

<section class="about-section about-comments" id="about-comments">
  {% include giscus-comments.html
    kicker="Discussion"
    title="留言交流"
    description="可以在这里留下文章反馈、合作沟通、站点建议或其他问题。留言会进入 GitHub Discussion，公开可见，也方便后续继续回复。"
  %}
</section>
