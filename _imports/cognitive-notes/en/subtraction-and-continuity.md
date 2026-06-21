---
title: Subtraction and Continuity
description: This essay explores how strategic subtraction, cutting scope, features,
  and distractions, strengthens continuity in AI projects and personal work. It connects
  this principle to model reliability training, a 2.0 overhaul of the author's meta-skill
  framework, OpenAI's AI-native advertising, a DeepSeek GEO diagnostic tool, and 13
  sustainable open-source monetization models.
tags:
- cognition
- AI
- skill
- GEO
- open source
---

## Subtraction and Continuity

A recent insight has stuck with me:

When iterating on open-source projects, it's alarmingly easy to fall into the complexity trap: even simple systems balloon rapidly under AI's influence, and the list of "things we want to build" grows faster than our capacity to sustain them.

But that growth isn't always progress. So I've been deliberately practicing subtraction.

The real benefit of subtraction isn't just simplicity; it's stronger *continuity*.

Continuity is often the quiet engine behind successful long-term projects. It enables consistent feedback loops, steady cognitive gains, and reliable iteration.

Here's a rough formula:

**Continuity = (Clarity of Direction × Consistency of Effort × Quality of Feedback) ÷ (Task-Switching Cost × Maintenance Burden × Choice Noise)**

Of course, continuity comes with a trade-off: it often means dialing back curiosity about shiny new things and holding off on exploration to protect focus.

That restraint isn't loss; it's investment.

Because doing so delivers three concrete benefits:

1. **Fewer task switches → preserved deep attention**: When you shift from one task to another, unfinished mental threads linger and actively degrade performance on the next task.
2. **Lower cognitive load → more stable learning**: Working memory is finite. Clutter, irrelevant context, or poorly structured inputs drain capacity needed for reasoning and retention.
3. **Fewer decisions → less decision fatigue**: More options rarely mean better outcomes; they often mean slower, shallower, or avoidant choices. Reducing low-stakes decisions frees up mental bandwidth for what truly matters.

At its core, subtraction lowers a system's *ongoing cost*.

Many goals stall not because they're unrealistic, but because too many targets, commitments, inputs, and obligations fragment attention, dilute feedback, inflate maintenance, and raise the barrier to the *next* action.

Subtraction sounds simple. Its difficulty lies in execution: it demands ruthless prioritization *without* layering on new "additions" disguised as optimization.

Strategic sharpness shows up first in what you *refuse* to do.

Recognizing that is already half the win.

## Reliability *Can* Be Trained

OpenAI's new paper, *Reinforcement Learning Towards Broadly and Persistently Beneficial Models*, tackles a critical question: Can we train AI models to be reliably beneficial, not just in one narrow setting, but across diverse, unseen contexts?

Background: Many enterprise AI agents fail not from lack of capability, but from behavioral instability. They hallucinate sources, overstate confidence, bypass approvals, flatter users, misuse tools, or ignore boundaries. These failures may share a root cause: inconsistent behavior patterns.

The paper's core hypothesis: *harmful behaviors migrate, and beneficial ones can too*, provided training targets the right underlying traits.

Prior work shows that harmful tendencies, like gaming reward signals, lying, generating unsafe code, or indulging user misconceptions, can generalize across tasks. If bad behavior transfers, can good behavior?

Yes, the paper finds evidence it can.

In controlled experiments, researchers injected a small set of high-quality *beneficial-behavior examples* (e.g., admitting uncertainty, citing sources, correcting errors, respecting constraints) into standard training data. Compared to a control model trained with identical compute and initialization, the augmented model showed significantly stronger stability across dozens of *unseen* benchmarks, including tasks and domains never present in training.

One standout result: Across 50+ independent evaluations, the beneficial-behavior-trained model outperformed the control on most metrics. Traits like honesty, caution, self-correction, and constraint adherence didn't stay confined to their training contexts; they generalized.

What makes this paper especially compelling is how it *operationalizes* subjective ideals: "honesty," "caution," "human oversight," "protecting vulnerable parties"-all become measurable via concrete prompts, dialogue flows, and scoring rubrics.

This resonates deeply with my work on content engineering. We say "high-quality content," but what does that *mean*? "Structured"? Structured *how*? In practice, we *can* define precise, observable traits for even fuzzy terms.

The implications extend beyond models to teams and individuals.

Team culture *is* a reward system. What a company consistently rewards, it inevitably grows.

So if you want your team to embody "accountability," don't just name it; define *what accountability looks like*: Which actions count? What evidence qualifies? What metrics reflect it?

Paper link: [alignment.openai.com](https://alignment.openai.com/beneficial-rl/)

## Updated Meta-Skill (v2.0)

I've just completed a full refactoring and 2.0 upgrade of my meta-skill framework, `yao-meta-skill`. The results are promising.

<div class="markdown-image-grid markdown-image-grid-2">
  <img src="/assets/cognitive-notes/images/OQiGb5qyKodFgcxGOQAcPpGynnc.png" alt="image.png" loading="lazy">
  <img src="/assets/cognitive-notes/images/KpQSbxwx3ohuTsx4VUIcQyQenBj.png" alt="image.png" loading="lazy">
  <img src="/assets/cognitive-notes/images/TDMgbqnjoo2cwRxm8rXcrQtTntc.png" alt="image.png" loading="lazy">
  <img src="/assets/cognitive-notes/images/SMFrbeQpMoaQg9xN6zLcRq5jnRf.png" alt="image.png" loading="lazy">
</div>

Credit where due: Codex keeps getting stronger. For complex engineering tasks, it now autonomously decomposes, commits, debugs, and iterates. This upgrade ran for 38 hours and produced 301 branches.

Meta-skill is the skill that *generates* skills. The v2.0 upgrade rests on five foundational principles:

1. **"Is this worth a skill?" - Prioritize reuse value**
   Only create a skill when a task repeats *and* produces a reusable output contract. One-offs should stay lightweight because over-engineering drains maintenance energy. Skills are assets; assets carry upkeep costs.

2. **Model the real task *before* generating the skill**
   First, capture: What's the user actually trying to accomplish? What should the output look like? What must *not* happen? What constraints apply? Ambiguity here is the #1 cause of skill failure; every skill has boundaries.

3. **Unify semantics with an intermediate representation**
   v2.0 introduces a "skill intermediate representation": a semantic contract specifying trigger conditions, inputs, outputs, boundaries, references, evidence, and expected artifacts. This layer decouples logic from platform and enables stable cross-platform skill packaging.

4. **Guard quality with layered evaluation & review**
   Quality is broken into checkable gates: Does it trigger accurately? Does output meet specs? Is runtime behavior consistent? Are permissions safe? Does the package install cleanly? Is evidence complete? Is public documentation appropriately scoped? Governance intensity scales with risk level.

5. **Drive iteration with operational feedback**
   Publishing isn't the finish line. Usage logs, drift signals, and feedback reports feed back into the loop, prompting updates to docs, new test cases, logic fixes, or tighter governance.

Together, these form a closed cycle: *create → validate → publish → observe → improve*.

Resources:
1. Meta-skill repo: [github.com](https://github.com/yaojingang/yao-meta-skill)
2. v2.0 upgrade plan: [doc.laoyao.cn](https://doc.laoyao.cn/unyyhc)
3. v2.0 vs. v1.0 comparison report: [doc.laoyao.cn](https://doc.laoyao.cn/l3lkgm)

## GEM Advertising

![image.png](/assets/cognitive-notes/images/RmJFbQ3AjofwEvxnqp3cgDk1nwe.png)

I explored OpenAI's ad dashboard; it's refreshingly minimal.

But effective execution? That's deceptively hard.

After reviewing official docs, here's what stands out:

1. **ChatGPT Ads aren't keyword auctions**; they're *intent-and-task-scenario matches*. Context richness matters more than keyword density.
2. **For AI ads, "manual-like" clarity wins**: Be specific, actionable, and immediately useful, like a well-written product manual.
3. **Your landing page's SEO infrastructure is non-negotiable**: OpenAI's crawlers and ad systems need to parse, verify, and trust your page.
4. **Relevance is multi-layered**: Title, ad copy, prompt context, *and* landing page content all contribute to matching quality.

OpenAI calls this *AI-native advertising*. The GEM era is officially underway.

Ad dashboard: [ads.openai.com](https://ads.openai.com/)

## DeepSeek GEO Diagnostic Skill

Over the holiday break, I built and open-sourced a skill that crawls DeepSeek search results, cleans the data, and runs a full GEO (Generative Engine Optimization) diagnostic analysis using OpenCLI.

See resources and demo report links at the end.

The generated report includes multi-dimensional metrics, comparative charts, and actionable insights, tested live on NIO (NIO Inc.) as a real-world case.

<div class="markdown-image-grid markdown-image-grid-2">
  <img src="/assets/cognitive-notes/images/EFuqbhDoVoNWICxwOB8czyVxn0g.png" alt="image.png" loading="lazy">
  <img src="/assets/cognitive-notes/images/IR7obXNknoI6pfxnl2qcOd9onpf.png" alt="image.png" loading="lazy">
  <img src="/assets/cognitive-notes/images/CG4AbE945oHVcaxckprcee2inrb.png" alt="image.png" loading="lazy">
  <img src="/assets/cognitive-notes/images/UI0lbm9j0oibTIxjnV6czzHanDh.png" alt="image.png" loading="lazy">
</div>

This skill helps assess how individuals, brands, or products appear in DeepSeek's generative search and how they compare to competitors. It surfaces current GEO gaps, opportunities, and concrete optimization levers.

**How it works:**
1. Install the skill in Codex or Claude Code. Input: keywords, target entity (e.g., "Google", "Yao Jingang"), entity type, and crawl interval strategy.
2. AI invokes OpenCLI to execute multi-round, randomized-interval crawls per query.
3. Results are cleaned using GEO-aware entity recognition, then logged as structured JSON, exported to Excel, and rendered into a bilingual (EN/CN) HTML diagnostic report with visualizations (see images and links).

**Prerequisites:**
1. *Real crawling requires*: OpenCLI installed + connected via OpenCLI Browser Bridge, and DeepSeek web interface logged in (preferably with a fresh account).
2. *Before running*: Prepare keyword list, desired crawl rounds per keyword, target entity (e.g., "DeepSeek"), optional aliases for the target and competitors (to boost recognition accuracy), and crawl interval (e.g., 1-3 min random, or safer 5-20 min random).

Built for DeepSeek first; support for other AI search platforms will roll out gradually.

Resources:
1. GitHub repo:
[github.com](https://github.com/yaojingang/yao-geo-skills/tree/codex/add-deepseek-crawler-skill/skills/yao-deepseek-crawler)
2. Interactive diagnostic report:
[doc.laoyao.cn](https://doc.laoyao.cn/eg5lq8)
3. Full dataset + analysis bundle:
[ai.laoyao.cn](https://ai.laoyao.cn/XmC7v)

## Open-Source Monetization Models

I reviewed common paths to sustainability for open-source projects and mapped 13 viable revenue models:

1. Sponsorships & donations
2. Enterprise subscriptions + commercial support (free tier for individuals)
3. Premium features in paid enterprise edition (core free)
4. Cloud-hosted SaaS (software free, hosting/managed service paid)
5. API, compute, or usage-based billing (custom APIs + proprietary commercial APIs)
6. Dual licensing (e.g., MySQL: GPL + commercial license for closed OEM/embedded use)
7. Referral & affiliate revenue (integrated plugins or commercial gateways)
8. Professional services & system integration (e.g., Red Hat)
9. Training, certification, and corporate workshops
10. Private, on-premise deployments (custom pricing)
11. Value-added data, models, benchmarks, or workflow tooling (e.g., Hugging Face)
12. Advertising (contextual, non-intrusive)
13. Acquisition or strategic investment
