---
layout: default
title: 留言板
description: 欢迎通过 GitHub 公开讨论区留言，我会在同一个讨论串里直接回复。
permalink: /guestbook/
---

<section class="guestbook-panel content-card">
  <div class="guestbook-panel-copy">
    <p class="page-kicker">Guestbook</p>
    <h1>欢迎留言</h1>
    <p>
      这里和首页共用同一个 GitHub Discussion 线程。任何 GitHub 用户都可以直接发言，我也会在同一个线程里持续回复。
    </p>
    <div class="guestbook-badges">
      <span>公开可见</span>
      <span>GitHub 账号即可参与</span>
      <span>支持持续追问与回复</span>
    </div>
  </div>
  <div class="guestbook-panel-actions">
    <a class="primary-link-button" href="#guestbook-comments">在本页留言</a>
    <a class="secondary-link-button" href="{{ '/' | relative_url }}">回到首页留言</a>
  </div>
</section>

<section class="guestbook-guide content-card">
  <div>
    <h2>怎么使用</h2>
    <p>点击上面的按钮后，就会进入这个站点绑定的 GitHub Discussion 讨论串。</p>
    <div class="guestbook-steps">
      <span>1. 登录 GitHub</span>
      <span>2. 直接评论</span>
      <span>3. 等待我的回复</span>
    </div>
  </div>
  <div>
    <h2>适合留言的内容</h2>
    <div class="guestbook-rules">
      <span>文章反馈</span>
      <span>合作沟通</span>
      <span>问题交流</span>
      <span>站点建议</span>
    </div>
  </div>
</section>

<div id="guestbook-comments">
  {% include giscus-comments.html
    kicker="Discussion"
    title="访客留言板"
    description="如果想在 GitHub 原生页面里查看，也可以点右侧按钮。"
  %}
</div>
