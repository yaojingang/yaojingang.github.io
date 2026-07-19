---
title: AI Coding Breakthroughs and the Rise of Skill-Centric Development
description: This essay surveys seven cutting-edge open-source AI coding tools - including
  GEOFlow, yao-meta-skill, TokHub, GEORank, and the Tok series - alongside an AI interview
  system and curated skill repositories. It explores how concrete technical artifacts
  enable new inference patterns, refines criteria for identifying pivotal work, and
  frames skill-oriented architecture as foundational for next-generation AI-native
  companies.
tags:
- AI Coding
- open source
- developer tools
- skill engineering
- AI infrastructure
---

## Recent AI Coding Projects

Around April 1, I began sharing open-source projects on GitHub. In just three and a half months, these projects collectively earned over 10,000 stars. Key projects include GEOFlow, Tokhub, GEORank, yao-meta-skill, yao-open-skills, yao-geo-skills, an open collection of prompts, and several smaller internal tools and systems.

During this period, my primary AI coding assistant was Codex - consuming over 18 billion tokens. It helped me build numerous open-source systems that improved internal team management, internal system development, business analysis, and strategic support.

### 1. GEOFlow

Before launching, I did a quick survey and found very few high-quality open-source systems focused on GEO (Geographic Search Optimization). Among the ones I've seen so far, GEOFlow stands out for its functional completeness, content engineering rigor, and delivery standards - and has earned 2.9k stars on GitHub in its first three months.

Especially around GEO content engineering, we built a set of high-standard norms and workflows.

![image.png](/assets/cognitive-notes/images/2026-07-19-ai-coding-image.png)

Since launch, GEOFlow has entered real business use cases - and people are using it in ways even richer than I originally imagined:

- A publicly listed company deployed it as their internal content management system
- A startup forked and extended it for commercialization
- Another company used it as a base to apply for software copyright registration
- Several individuals monetize it directly - e.g., offering deployment and operations services
- Many more use it for GEO content projects: building new websites or upgrading existing ones

Hearing this feedback genuinely makes me happy.

For GEO, there are three core capability modules: data, content, and distribution. GEOFlow currently excels strongest in *content*, followed by *distribution*, then *data*.

Content is the most critical layer: once quality and management are solid, much else falls into place.

![image.png](/assets/cognitive-notes/images/2026-07-19-ai-coding-image-2.png)

At the content layer, GEOFlow's architecture is the most mature - covering end-to-end workflows, automation, knowledge base management, and quality control. Its core strength lies in *content engineering*: turning content creation and governance into a repeatable, scalable discipline.

On distribution, GEOFlow supports single-site sync and multi-channel publishing - managing and releasing content across multiple sites from one system. It also supports API binding (e.g., to WordPress), with extensible interfaces ready for integration with other distribution platforms.

On data, GEOFlow provides foundational analytics: website metrics, content performance, log analysis, and cross-site distribution records - all aggregated into basic statistics and reports.

GitHub repo:
[GEOFlow](https://github.com/yaojingang/GEOFlow)

### 2. yao-meta-skill

Early on, both Professor Xiangyang and I developed a habit: studying and iterating *meta-prompts* - prompts that generate other prompts.

So when exploring "skills" (structured, reusable AI behaviors), we naturally turned our attention to *meta-skills*: skills that generate or refine other skills.

That led to yao-meta-skill - a standalone, open-source GitHub repository now with 2.1k stars.

![image.png](/assets/cognitive-notes/images/2026-07-19-ai-coding-image-3.png)

It helps create higher-quality skills from scratch - and also iterate, audit, and improve existing ones.

Many friends told me they found the *process* behind creating and refining yao-meta-skill even more valuable than the tool itself - so here's a brief walkthrough:

1. **Architecture design**: I drew from public technical analyses of Claude Code, community research, and official skill designs - giving yao-meta-skill a distinct architectural foundation.
2. **Capability scope**: I studied top-tier meta-skills - including Anthropic's Skill Creator and OpenAI's Skill Creator - to synthesize strengths: Anthropic's engineering methodology and iterative feedback loops; OpenAI's lean, focused design.
3. **Workflow refinement**: We especially strengthened *user intent modeling* - clarifying a new skill's inputs/outputs, defining its boundaries, and adding a "silent search" feature that automatically finds and adapts world-class reference designs. That third technique alone significantly lifts skill quality.
4. **Quality assurance**: We added automated AI evaluation experiments - and validated results with both AI scoring *and* five rounds of blind human testing. yao-meta-skill outperformed alternatives across all tests.

![image.png](/assets/cognitive-notes/images/2026-07-19-ai-coding-image-4.png)

Today, nearly every skill I build - from scratch or iteratively - is created and refined using this meta-skill.

Building yao-meta-skill, in essence, was a way to learn from global best practices and deepen my own understanding of skill boundaries, evaluation criteria, engineering patterns, and standards.

GitHub repo:
[yao-meta-skill](https://github.com/yaojingang/yao-meta-skill)

### 3. Open Skill Collections

Two main repositories host these:

- **yao-geo-skills**: All GEO-related skills - e.g., integrated scrapers + cleaners + diagnostic reporters for Doubao, ChatGPT, and DeepSeek; or skills that generate GEO performance evaluation frameworks.
- **yao-open-skills**: Everything else - public skills outside GEO and meta-skills. Examples include:
  - WeRead Report Skill
  - Tutorial Skill
  - Bayesian Decision Skill
  - Game Theory Skill
  - Contradiction Theory Skill
  - Business Model Skill
  - Requirements Elicitation Skill
  - Expert Simulation Skill

![image.png](/assets/cognitive-notes/images/2026-07-19-ai-coding-image-5.png)

My favorite is the **Bayesian Decision Skill**.

It turns Bayes' theorem into an *ongoing, updatable judgment process* for complex decisions.

Here's how it works:
- Starts with an initial assessment based on current information
- Guides users through multi-turn dialogue to add variables, update posterior beliefs, and logs *why* each judgment shifted
- Outputs a bilingual Markdown + HTML decision report: full conversation history, evolving judgments, and concrete action recommendations

It fits product, growth, and business decisions - and equally well for personal choices like travel, relocation, or career shifts.

At its core, it answers: *When information is incomplete and risk uncertain - how do we decide rationally whether to act? And how do we raise the bar on decision quality?*

![image.png](/assets/cognitive-notes/images/2026-07-19-ai-coding-image-6.png)

Then there's the **Tutorial Skill**:

1. You input any topic + reference materials -> AI prioritizes those references, supplements intelligently, and filters out low-quality sources
2. AI generates a custom-deep tutorial - outputting PDF, Word, and HTML versions for self-study
3. Content is structured chapter-by-chapter, with AI-drawn diagrams inserted contextually - grounded in the pedagogical logic from my *Course Marketing* book (written three years ago while running an MCN)

![image.png](/assets/cognitive-notes/images/2026-07-19-ai-coding-image-7.png)

The **yao-geo-skills** repo also hosts several GEO-specific skills - like the ChatGPT scraper + cleaner + analyzer + reporter combo.

Its workflow:

1. Prepare: question list, repetition count, target entity, entity type, OpenCLI profile, sampling interval
2. OpenCLI Browser Bridge connects to your logged-in ChatGPT Web session and runs randomized, spaced queries
3. Data is cleaned, aggregated, and output as JSON, Markdown, Excel, and HTML reports
4. The HTML report analyzes: mention rate, avg. mentions, Top 1/3/5 probability, avg. ranking, sentiment, source domains, URL structure, title intent - and compares your target entity against competitors
5. Entity classification distinguishes people, companies, products, concepts, and noise - excluding generic industry terms, broad category words, or URL parameters from competitor lists

![image.png](/assets/cognitive-notes/images/2026-07-19-ai-coding-image-8.png)

Related links:
[yao-open-skills](https://github.com/yaojingang/yao-open-skills)
[yao-geo-skills](https://github.com/yaojingang/yao-geo-skills)
[doc.laoyao.cn](https://doc.laoyao.cn/) (demos + original design docs)
[yao-open-prompts](https://github.com/yaojingang/yao-open-prompts) (open prompt library)

### 4. TokHub

TokHub is an open-source platform for monitoring, routing, and managing AI API gateways - designed as a unified "AI API middle layer."

Co-conceived and co-built with Professor Xiangyang, it uses:
- Frontend: React + TypeScript
- Backend: Go + go-chi
- Databases: PostgreSQL/TimescaleDB + Redis
- Messaging: NATS
- Deployment: Docker + Helm

![image.png](/assets/cognitive-notes/images/2026-07-19-ai-coding-image-9.png)

Core capabilities:

1. **Public monitoring & channel details**
   View status, success rate, latency, model, pricing, and health scores for monitored API channels

2. **L1 / L2 / L3 layered probing**
   - L1: DNS, TCP, TLS, HTTP connectivity
   - L2: API key validity, model list, model availability
   - L3: Minimal real-generation test - to catch cases where the endpoint is reachable while the model itself is unavailable

3. **User workspaces & private channels**
   Users can bookmark public channels - or add their own endpoints and API keys
   Private keys are encrypted and isolated per organization - never exposed to the platform backend

4. **One-click personal gateway**
   Aggregate multiple public and private channels into a unified gateway for your agents or clients
   Routes requests by latency, success rate, or cost - and logs tokens, latency, cost, error types, and audit events

System architecture:
![image.png](/assets/cognitive-notes/images/2026-07-19-ai-coding-image-10.png)

TokHub supports Docker self-hosting - with production pre-checks, backup/recovery, security scanning, and release validation baked in.

GitHub repo:
[TokHub](https://github.com/yaojingang/TokHub)

### 5. GEORank

GEORank is a curated suite of lightweight GEO tools - iteratively developed and now fully open-sourced.

It measures brand and website visibility in AI search - integrating site diagnostics, AI Q&A, optimization suggestions, keyword expansion, structured content generation, and admin controls into one flow.

Built for GEO, SEO, content, and brand growth teams - and for developers looking to build or extend their own GEO platforms.

Tech stack: FastAPI + Next.js. Currently migrating to version 2.0 frontend.

![image.png](/assets/cognitive-notes/images/2026-07-19-ai-coding-image-11.png)

Live demo: [georankhub.com](https://www.georankhub.com/)
GitHub repo: [GEORank](https://github.com/yaojingang/GEORank)

### 6. Tok-Series Tools

All named with "Tok" - the first three letters of *Token* - then freely combined. Seven main tools, all open-sourced:

#### 1. Toktra
A Chrome extension for webpage translation. Configure your own API. I mostly use it for *highlight-to-translate*.

![image.png](/assets/cognitive-notes/images/2026-07-19-ai-coding-image-12.png)

#### 2. Tokkit
A local token ledger - tracks usage across projects. Shows live stats in the top-right corner and exports an HTML visual report.

![image.png](/assets/cognitive-notes/images/2026-07-19-ai-coding-image-13.png)
![image.png](/assets/cognitive-notes/images/2026-07-19-ai-coding-image-14.png)

#### 3. Tokdoc
A document manager supporting Word, PDF, HTML, PPT, Excel, etc.
- Online editing for Word, PDF, HTML
- Auto-syncs files from local directories
- Tracks views and engagement for public documents

![image.png](/assets/cognitive-notes/images/2026-07-19-ai-coding-image-15.png)

#### 4. Tokscr
A flexible web screenshot tool - with post-capture editing and saving options.

![image.png](/assets/cognitive-notes/images/2026-07-19-ai-coding-image-16.png)

#### 5. TokURL
A personal URL shortener - generate short links instantly, name them manually, or auto-generate random ones.

![image.png](/assets/cognitive-notes/images/2026-07-19-ai-coding-image-17.png)

#### 6. tokchat
A lightweight AI Q&A and learning system - ideal for internal company Q&A or external expert-facing chatbots.

Built during meeting breaks, iterated a few times - stable for internal and light external use.

![image.png](/assets/cognitive-notes/images/2026-07-19-ai-coding-image-18.png)

All tools:
[yao-open-tools](https://github.com/yaojingang/yao-open-tools)

### 7. AI Interview System

To better manage hiring, I built an AI Interview Manager - and kept refining it over the past few months.

It's now deeply integrated with GitHub, Codex, and Feishu - enabling seamless cross-platform data flow and collaboration.

How it works:

1. **AI Interview Manager (core)**
   Central hub for candidates, resumes, AI-first interviews, auto-generated reports, feedback, scheduling, analytics, and sync status

2. **GitHub Data Vault**
   Each candidate gets their own directory in a GitHub repo. Workflow stages flow automatically via folder structure, `workflow.json`, `candidate-index.csv`, and Git commits - creating a natural, versioned evidence trail

3. **Codex Skill (local intelligence layer)**
   Interviewers pull candidate packages, generate evaluations, write first/second-round feedback, save schedules, submit Feishu tasks, and push analytics - all triggered locally

4. **Feishu Execution Layer**
   Feishu CLI auto-creates calendar events, sends private messages, and triggers reminders. Background workers handle async tasks: retries, status updates, and weekly interview data reports

![image.png](/assets/cognitive-notes/images/2026-07-19-ai-coding-image-19.png)

End-to-end flow:

1. HR or candidate uploads a resume -> system parses it asynchronously
2. After AI-first interview, system saves Q&A history, keywords, and scores
3. Report service generates HR- and candidate-facing reports -> agent auto-syncs to GitHub vault
4. Team members view candidate data in GitHub or Codex, generate assessments, and submit feedback
5. If "pass", candidate moves to next-stage folder in GitHub; if "reject" or "hold", only status and notes update
6. Once scheduled, system creates Feishu calendar event -> worker triggers follow-up reminders 1h and 3h post-interview

In this system, the *candidate* becomes a stateful object flowing across AI interviews, GitHub collaboration, Codex agents, and Feishu touchpoints.

That gives hiring four superpowers:
- Automation efficiency
- Clear human accountability boundaries
- Organizational memory of the hiring process
- Full operational traceability

![image.png](/assets/cognitive-notes/images/2026-07-19-ai-coding-image-20.png)

For interviewers, Codex is the central interface - everything else syncs automatically.

Whether HR or interviewers, we all default to asking Codex directly: *"Show me initial interview counts and feedback for the last 7 days."*

![image.png](/assets/cognitive-notes/images/2026-07-19-ai-coding-image-21.png)

The AI Interview System remains private for now. If interest grows, I plan to release it.

In conversations with many friends, we've reached a shared judgment: AI raises access while outcome gaps can still widen.

AI lowers barriers to tool use and product development, and it continuously *raises the market's bar for final results*. As more people use AI to deliver baseline work, what truly differentiates outcomes narrows to just a few things:

- Depth of problem understanding
- Strength of professional judgment
- Quality of taste and aesthetics
- Consistency of execution
- Discipline of iteration

In short: AI raises the floor - and widens the gap.

What matters most now is having sharper ideas, stronger judgment, better taste, and relentless execution - capabilities that sit deep in human practice.

For me, AI's biggest gift is turning ideas into reality - fast. It lets me build exactly the skills, tools, and systems I need - tailored, precise, and immediate.

And because I open-source them, I've met many wonderful new friends.

Over these years, AI has fostered a genuinely warm open-source culture. People share experiences, insights, and code to give, learn, inspire, and connect.

## 10 AI Coding Projects

Last night, I watched the "WaytoAGI Future Silicon World" livestream. Twelve speakers presented ten AI coding projects plus two FDE (Frontline Digital Enablement) case studies - many were genuinely interesting and highly inspiring.

1. **Xiaoer FM** and **Omia**, by Xiaoer: A music dynamic visualization tool and a minimalist reader supporting over 100 formats - both products feel polished and intentional.
2. **Watchless**, by Chen Zixin: A skill that converts long videos and podcasts into illustrated summaries with key frames.
3. **Parent-Child Habit-Building Mini-Program**, by "Fafen de Caomei" (Frustrated Strawberry): Uses points, "mythical beast" hatching, and wish redemption to motivate kids to complete daily check-ins - grounded in a very real, relatable parenting context.
4. **AI Private-Operation Tool**, by Lao Yuan: Automates customer relationship management across personal WeChat and WeCom - identifies purchase intent and routes leads to sales reps. The commercial loop is already live and working.
5. **Whiteboard Explainer Video Tool**, by Yu Xianghua: Turns text, documents, or web pages into narrated whiteboard-style explainer videos with subtitles - ideal for knowledge dissemination.
6. **AI Parent-Child Language Flashcards**, by Nerissa: Snap a photo of any object -> instantly generate foreign-language vocabulary, short phrases, pronunciation audio, and printable flashcards - designed with elegant restraint.
7. **CrewClaw**, by Peng Chao: A platform for hiring and managing digital employees - structured like an App Store for AI agents.
8. **3D Director's Desk**, by Meng Maixiang: Lets you control a 3D camera using your phone's gyroscope - enabling fast, intuitive shot composition optimized for AI video generation. Fun and clever.
9. **WeChat Official Account Editor** and **Perler Bead Maker**, by Shu Tongwen: One solves common image and layout pain points for WeChat content; the other auto-generates perler bead patterns from uploaded images - both born directly from the creator's own workflow needs.
10. **AI Content Studio**, by Ally: Automates end-to-end video production - from material selection and scriptwriting to captioning, editing, and transitions - practical and time-saving for creators.

Two FDE case studies:

11. **Smart Product Detail Page FDE for Footwear & Apparel**, by Lyon: Embedded on-site at Skechers, this project mapped their operational workflows and used AI to automate product recognition, template matching, and bulk layout application - lifting accuracy from 85% to 95%. Later reused successfully at Anta.
12. **Enterprise AI FDE Delivery Case Study**, by Derrick: Drawing on dozens of enterprise deployments, he shared hard-won insights on need-finding, on-premise deployment, data security, and scaling AI solutions across state-owned enterprises, hospitals, law firms, and more.

Some related links for the AI coding projects:

1. Xiaoer FM: [fm.xiaoercamera.xyz](https://fm.xiaoercamera.xyz/)
2. Omia: [xiaoeromia.com](https://xiaoeromia.com/)
3. Watchless: [watchless](https://github.com/chenzixin1/watchless)
4. Zhixingyuan Mental OS: [zhixing.club](https://zhixing.club/landing)
5. Explainer Video: [explainer-video](https://github.com/SpeedPainterOrg/explainer-video)
6. SpeedPainter official site: [speedpainter.org](https://www.speedpainter.org/)
7. CrewClaw: [CrewClaw](https://github.com/staruhub/CrewClaw)
8. OpenFDE: [open-fde.com](https://www.open-fde.com/)

## Small Facts, Big Conclusions

![image.png](/assets/cognitive-notes/images/2026-07-19-ai-coding-image-22.png)

Many of our decisions and judgments hinge on how we interpret facts.

People rarely respond directly to raw facts. More often, they respond to their *own interpretation* of those facts.

That's why it's easy to fall into the "small facts, big conclusions" trap - even drawing conclusions from thin air.

Inside our heads, multiple "governments" are constantly at work.

Long before language kicks in, these internal systems have already debated, negotiated, and competed - multiple rounds deep.

Language, then, acts more like a spokesperson: it justifies the conclusion that has already won.

What truly warrants caution is jumping too quickly - or too far - to an explanation.

Interpretation drives action.
Action produces outcomes.
And those outcomes are then selectively interpreted - often reinforcing the original interpretation.

Before long, we grow increasingly convinced by the "illusion" we ourselves constructed.

So how can we avoid falling into the "small facts, big conclusions" trap?

A few practical strategies:

1. For any single fact, deliberately generate at least three plausible alternative explanations.
2. Actively seek out evidence that could disprove your current judgment.
3. Zoom out: ask whether the observation holds across a larger sample size and over a longer time horizon - is it a fluke, or a stable pattern?

## How to Identify the Most Important Things

![image.png](/assets/cognitive-notes/images/2026-07-19-ai-coding-image-23.png)

We all know our time and energy are limited.

Spending your best energy on truly important things - versus scattering it across many minor ones - leads to vastly different outcomes.

So a critical personal strategy is to reserve your peak energy and sharpest focus each day for what *really matters*.

My current criteria for identifying what really matters:

1. **Highest leverage**: Doing it well triggers cascading positive effects across many other areas.
2. **Long-term compounding**: It builds durable value over time - skills, systems, relationships, or knowledge that keep growing in usefulness.
3. **Requires your direct agency**: You must lead it, meaningfully participate in it, or make a decisive call.
4. **Unblocks the core bottleneck**: It directly resolves the single biggest constraint holding back progress right now.
5. **Sustained personal commitment**: You're willing to invest in it long-term - and it's an area where you can realistically develop a distinctive edge.

The most important things often yield little feedback in the short term while quietly reshaping your trajectory over months and years.

The compound effect of personal productivity hinges on one simple question: *Where do your best few hours of the day actually go?*

## The Next-Generation Company

![image.png](/assets/cognitive-notes/images/2026-07-19-ai-coding-image-24.png)

A friend and I were chatting recently about what future companies might look like.

I said: I've long hoped to build - and see succeed - a company with this profile: a core team of fewer than 10 people, generating over RMB 100 million in annual revenue.

Tiny in size, yet large in impact. Every team member earns well above market-average compensation, enjoys significantly greater autonomy, and experiences higher personal fulfillment.

Such companies are already beginning to emerge - both here and abroad - with early prototypes and real-world examples.

These teams start by deeply integrating AI and autonomous agents - offloading repetitive execution, communication, analysis, and management tasks to intelligent systems.

Using AI well is only the starting point.

Their business must be highly standardized, productized, and scalable, allowing revenue growth to separate from headcount expansion.

They must also solve problems that matter deeply to customers - problems customers are willing to pay a premium for.

Because the team is so small, income has to come from high-value work and dense value creation.

What matters more is *talent density*, *product strength*, and *value density*: growing through sharper insight, tighter execution, and higher-margin outcomes.

Internally, such a company may have only 10 people. Externally, it connects fluidly with partners, open-source communities, suppliers, distribution channels, and thousands of users.

Each core member operates more like a "super individual": empowered by AI to own and deliver an entire end-to-end business outcome across the full chain.

So the most meaningful metrics for the next-generation company go beyond traditional KPIs. They include revenue per person, profit per person, value created per unit of time - and, crucially, how much of that value flows back to each creator.

Do more with less.
And distribute the rewards more fairly among those who create them.

That's the company model I find most compelling in the AI era - and the one I continue to think about, test, and build toward.

## Pinpointing Your Positioning Skill

I built a positioning skill - a tool designed to help you better understand your personal or organizational competitive advantages, and thereby improve the quality of your strategic decision-making.

It also helps clarify key questions like:

1. What single sentence would your target audience use to describe you?
2. Who do they currently see as their alternative?
3. Which difference actually influences their choice?
4. Which advantage do you already have solid evidence for - and can sustain over time?
5. What's the next step to test it, articulate it clearly, and own that position long-term?

It synthesizes core ideas from *Positioning* - mental models, categories, ladders, and focus - with practical additions: competitor analysis, deep demand insight, evidence grading, and D6 Advantage Diagnosis.

It works for personal brands, courses, products, services, and company branding. It ingests Q&A transcripts, attachments, and website content - and outputs:
- A crisp one-sentence positioning statement
- Differentiating tags
- Actionable recommendations
- Validation criteria
- A visual HTML report

GitHub repo:
[yao-positioning-skill](https://github.com/yaojingang/yao-open-skills/tree/main/skills/yao-positioning-skill)
How it works (principles & workflow):
[doc.laoyao.cn](https://doc.laoyao.cn/jghwr5)

<div class="markdown-image-grid markdown-image-grid-2">
  <img src="/assets/cognitive-notes/images/2026-07-19-ai-coding-image-25.png" alt="image.png" loading="lazy">
  <img src="/assets/cognitive-notes/images/2026-07-19-ai-coding-image-26.png" alt="image.png" loading="lazy">
  <img src="/assets/cognitive-notes/images/2026-07-19-ai-coding-image-27.png" alt="image.png" loading="lazy">
  <img src="/assets/cognitive-notes/images/2026-07-19-ai-coding-image-28.png" alt="image.png" loading="lazy">
</div>
