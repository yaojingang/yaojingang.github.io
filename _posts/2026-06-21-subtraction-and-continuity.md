---
layout: post
title: "减法与连续性"
date: 2026-06-21 10:00:00 +0800
categories: ["认知随笔"]
tags: ["认知", "AI", "Skill", "GEO", "开源"]
description: "这篇随笔从减法与连续性谈起，讨论模型可靠性训练、元 Skill 2.0 重构、GEM 广告、DeepSeek 诊断 Skill 和开源项目盈利模式。"
lang: zh-CN
weekly: true
week: 2026-06-21
permalink: /cognitive-notes/subtraction-and-continuity/
translation: /essays/subtraction-and-continuity-en/
translation_title: "Subtraction and Continuity"
---

## 减法与连续性

最近的一个很大的感触

迭代开源项目的时候，总是会很容易陷入复杂度陷进，一个简单的系统，也会很容易在AI的加持下，做得越来越复杂，同时想做的系统，也会越来越多

但这未必是好事，所以一直想做减法

减法的好处，就是可以让很多事情，具有更强的连续性

连续性是很多项目得以成功的核心要素，这背后意味着持续有效反馈、认知提升、迭代，都会更有连续性

一个简单的公式：

连续性 = 方向清晰度 × 投入节奏 × 反馈质量 ÷ 任务切换成本 ÷ 维护负担 ÷ 选择噪音

当然，连续性的另一面，可能就是要一定层面减少对各种新事物的“好奇”与探索

但这种“牺牲”也是必要的

这是因为，这样做了之后，至少有3个好处

1. 减少切换，可以有效的保护我们自己的深度注意力，人在从一项任务切换到另一项任务时，前一项未完成任务会继续占用部分注意力，往往会非常影响下一项任务表现
2. 降低认知负荷，可以让学习与思考更稳定，工作记忆容量有限，任务呈现方式或无关信息带来的额外负荷会削弱学习和表现
3. 降低选择决策，可以减少大脑的无效消耗，更多选项不总能带来更好的决策体验

减法的关键意义在于降低系统的“持续成本”

很多目标无法持续，常见原因常常是目标、任务、信息和承诺过多，导致注意力被切碎、反馈被稀释、维护成本过高、下一次行动的门槛太高

减法看似简单，实际上，它的难点是在于：要求我们做减法的同时，要聚焦自己的关键目标，同时还不能又做一堆的“加法”

战略的锋利，首先体现在不做什么

意识到这一点，也很有价值了

## 可靠，也能被训练

OpenAI的一篇新论文《Reinforcement Learning Towards Broadly and Persistently Beneficial Models》

核心研究的是，如何让模型变得更加可靠

一个研究背景，许多企业Agent失败，原因很多，编造依据、过度自信、绕过审批、迎合用户、滥用工具、忽略边界，但这些失败可能共享底层原因：模型的行为稳定性

论文核心底层逻辑，可以概括为：坏行为会迁移，好行为也可能迁移；关键在于训练的目标是否抓住了底层行为特质

过去的若干研究发现，如果模型在一个窄场景里学会了有害行为，比如钻评分漏洞、说谎、写不安全代码、迎合用户的错误期待，这种坏倾向有时会扩散到别的场景

如果有害倾向可以迁移，那么有益倾向能不能也迁移？

这就是这篇论文的核心研究思路

![image.png](/assets/cognitive-notes/images/Wur1bSTTho3ilUxlA1WcPneyngf.png)

研究发现，答案是有可能的

研究团队做了一组对照实验，他们把少量高质量的有益行为训练数据混入常规训练数据中，再和一个训练起点、训练算力相当的对照模型进行比较，结果显示，经过这种方式训练的模型，在许多没有直接见过的新任务、新领域和新评测中，表现都更稳定

论文里有一个很重要的结果：在五十多个独立评测中，接受有益行为训练的模型，在大部分评测上都优于对照模型。也就是说，模型在一个地方学到的诚实、谨慎、可纠错和遵守约束，并没有只停留在那个地方，而是迁移到了更多场景中

这篇论文有意思的地方在于，就是把“有益”拆成了可以训练、可以评估的行为特质

比如诚实、可纠错、谨慎、遵守约束、保护弱势方、保留人类监督等

通过转化，这些主观词汇，转成了具体场景、具体对话和具体评分标准

这对我最近研究内容工程也很有启发，我们都说要内容质量高，但什么是内容质量高？要有结构化，但什么是结构化？

但实际上我们是可以去定义很多主观词汇的特质

这篇论文，对团队管理，对个人管理，也有启发

一个团队的文化，也是一套奖励系统。公司反复奖励什么，团队就会长成什么样

同时，当我们需要团队如何，就把抽象价值观转成具体评分或者绩效标准，比如想要负责，就需要定义什么是负责，定义哪些与负责有关的绩效指标

论文网址：[alignment.openai.com](https://alignment.openai.com/beneficial-rl/)

## 更新了元skill

这次给元Skill yao-meta-skill 做一次重构和2.0升级，升级后的效果非常不错

<div class="markdown-image-grid markdown-image-grid-2">
  <img src="/assets/cognitive-notes/images/OQiGb5qyKodFgcxGOQAcPpGynnc.png" alt="image.png" loading="lazy">
  <img src="/assets/cognitive-notes/images/KpQSbxwx3ohuTsx4VUIcQyQenBj.png" alt="image.png" loading="lazy">
  <img src="/assets/cognitive-notes/images/TDMgbqnjoo2cwRxm8rXcrQtTntc.png" alt="image.png" loading="lazy">
  <img src="/assets/cognitive-notes/images/SMFrbeQpMoaQg9xN6zLcRq5jnRf.png" alt="image.png" loading="lazy">
</div>

不得不夸下Codex，越来越强了，复杂工程任务已经可以自己持续拆解、提交、修复、迭代

根据升级方案，Codex已经工作了38小时，提交了301个分支

元skill，就是生成skill的skill，这次2.0的升级的底层逻辑，可以概括为这5点

1. 先判断是否值得做成技能

只有当任务有重复使用价值，并且有可复用的输出契约时，才应该创建技能，对于一次性任务，应当避免过度工程化

这背后的逻辑是：

技能是一种资产，资产需要维护成本，所以必须先确认复用价值

2. 先建模真实任务，再生成技能

AI会先捕捉：用户到底要完成什么工作，输出应该长什么样，哪些事情不能做，有哪些约束等等

这一步很重要，因为很多技能失败，就是任务边界一开始就没有说清楚

所有的技能，都有它的适用边界

3. 用中间层统一语义

2.0 的关键抽象是“技能中间表示”，它相当于技能的核心语义合同，负责描述：触发条件、输入、输出、边界、参考资料、证据、预期产物

有了这个中间层，后面才能稳定地生成不同平台的技能包

4. 用评测和审查保护质量

2.0 把质量拆成很多可检查的门槛：触发是否准确，输出是否达标，运行是否一致，权限是否安全，包是否能安装，证据是否完整，公开声明是否过度

不同风险等级，使用不同强度的治理

5. 用运营反馈驱动下一轮迭代

2.0 不把技能发布当成终点，会通过使用记录、漂移信号、反馈日志等，判断技能是否需要改说明、补评测、修逻辑、加治理

通过这5点，形成了一定的迭代闭环，创建技能，验证技能，发布技能，观察技能，改进技能

相关资源与文档分享：

1. 元skill仓库：[github.com](https://github.com/yaojingang/yao-meta-skill)
2. 2.0升级方案：[doc.laoyao.cn](https://doc.laoyao.cn/unyyhc)
3. 2.0与1.0的对比报告：[doc.laoyao.cn](https://doc.laoyao.cn/l3lkgm)

## GEM广告

![image.png](/assets/cognitive-notes/images/RmJFbQ3AjofwEvxnqp3cgDk1nwe.png)

看了下OpenAI的广告后台，非常简单

但感觉要做好这个投放，难度也不小

研究了下官方文档，几个结论分享：

1. ChatGPT Ads的本质不是“买关键词”，广告很依赖丰富的上下文，其实质是在买用户任务场景和意图匹配
2. 对于AI广告，越像说明书，可能越适合 ChatGPT，核心是清楚、有用、具体
3. 投放着陆页的SEO基础设施非常重要，OpenAI的爬虫及广告系统，都需要理解和验证页面
4. 相关性很重要，落地页、标题、文案和上下文提示，都会影响匹配质量

官方，把这个定义为是“AI-native advertising”，也就是“AI 原生广告”

GEM时代，也开始了

OpenAI 广告后台地址：[ads.openai.com](https://ads.openai.com/)

## DeepSeek诊断Skill

放假这两天，基于OpenCLI，写了一个DeepSeek的AI结果爬取、数据清洗和GEO诊断分析的skill，已开源到GitHub

相关资源及演示报告链接见文末

生成的诊断分析报告，有多个维度的指标数据和图表分析，效果还不错

以蔚来作为真实测试示例，给大家进行案例展示

<div class="markdown-image-grid markdown-image-grid-2">
  <img src="/assets/cognitive-notes/images/EFuqbhDoVoNWICxwOB8czyVxn0g.png" alt="image.png" loading="lazy">
  <img src="/assets/cognitive-notes/images/IR7obXNknoI6pfxnl2qcOd9onpf.png" alt="image.png" loading="lazy">
  <img src="/assets/cognitive-notes/images/CG4AbE945oHVcaxckprcee2inrb.png" alt="image.png" loading="lazy">
  <img src="/assets/cognitive-notes/images/UI0lbm9j0oibTIxjnV6czzHanDh.png" alt="image.png" loading="lazy">
</div>

适合分析个人、品牌、产品在DeepSeek的搜索结果综合表现，并分析出与竞品的区别，找到当前目标实体在DeepSeek的GEO优化的问题、潜力与方法

工作流程与逻辑

1. 可以在codex、Claude Code，安装skill后执行，输入需要查询的1个或多个关键词、目标实体（比如人名、公司名、产品名）、实体类型与抓取间隔策略
2. AI调用OpenCLI的能力，开始执行，每个问句多轮重复抓取，每次抓取随机时间间隔
3. 会基于GEO的实体名称与类型，对结果进行清洗，并生成结构化的JSON数据日志，Excel结构化数据表，以及HTML可视化诊断与分析报告，中英文双语（详见图片及链接）

这个Skill的前置条件

1. 真实抓取，需要提前下载openCLI并已连接 OpenCLI Browser Bridge，且DeepSeek 网页端已经登录，建议使用新号测试
2. 执行时的准备，关键词列表、每个关键词轮询次数、目标实体（比如Google、姚金刚）、推荐提供目标实体别名和竞品别名表，用来提升实体识别准确率、抓取间隔，例如 1-3 分钟随机，或更安全的 5-20 分钟随机

这个skill主要基于DeepSeek，其它AI搜索平台，后面陆续开源出来

相关资源链接：

1. GitHub仓库：

[github.com](https://github.com/yaojingang/yao-geo-skills/tree/codex/add-deepseek-crawler-skill/skills/yao-deepseek-crawler)

2. 诊断分析可视化报告：

[doc.laoyao.cn](https://doc.laoyao.cn/eg5lq8)

3. 抓取与分析的所有文件包：

[ai.laoyao.cn](https://ai.laoyao.cn/XmC7v)

## 开源项目的盈利模式

研究了下开源项目如何赚钱，梳理了13种常见的盈利模式：

1. 赞助、捐赠
2. 企业级订阅与商业支持，个人版免费
3. 企业版增值功能付费，个人或部分功能免费
4. 云租赁与SaaS模式，系统本身免费，但需要运行的花可以租用云服务器等
5. API、算力和用量计费，提供自定义API，同时也提供自有商业API
6. 双重许可与商业授权，代表案例MySQL，同一代码以 GPL/开源许可和商业许可并行，闭源嵌入或 OEM 付费
7. 导流分成，植入相关插件或商业产品入口，实现一定的分佣
8. 专业服务与系统集成收费，代表案例Red Hat
9. 培训与认证，提供与之相关的课程、考试、证书、企业培训等服务
10. 企业私有化与专属部署，单独收费
11. 数据、模型、评测与工作流增值，代表案例Hugging Face
12. 广告收入
13. 并购或战略投资
