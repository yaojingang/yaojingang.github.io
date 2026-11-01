# GEO 实时内测

入口为 https://www.laoyao.cn/geo/ 。点击“实时内测”，输入设置时保存的团队口令即可使用。教学演示保留原有示例。

## 使用与验收

首页内置 10 个测试问题，点击后填入输入框，按“搜索”发起调用。测试内容覆盖概念解释、官方资料、工具比较、地区条件、信息不足和引用复核。

回答完成后，可以查看实际搜索词、接口返回数量、排序分、输入证据、回答段落与引用来源。开启“GEO 透视”，点击回答片段可查看关联选段和原文链接。

六个步骤记录本站执行的检索与生成流程。搜索结果中的排序分保留 0～3 刻度，权威等级保留 0～4 刻度，未知等级单独标注。网页正文和搜索摘要分别标记。服务端验证引用编号存在，结论与证据是否充分对应仍需人工复核。搜索结果覆盖范围会影响答案质量。

中文问题默认附加 Search 文档支持的 `lang:zh` 条件。问题中明确要求英文资料或使用 `lang:en` 时，按对应语言查询。首个查询保留原问题，地区条件由问题本身说明，中文资料也可能包含繁体中文来源。

本站以 API 排序分 1.50 作为来源选用线，最多精读 5 个达标来源。纯标题、导航标签等内容不单独作为证据；正文缺少有效段落时，依次尝试长摘要和短摘要，并标明“搜索摘要”。没有足够资料时显示补充条件的提示，保留候选和执行记录，跳过回答生成。查询含义不明确时，建议写清推荐对象，例如工具、专家或岗位。

实时版与教学版共用来源卡片、折叠进度、查询扇出、段落卡片和引用弹层的样式。实时版展示实际查询、API 原始分数及选段。检索规则升级会使旧版本回答缓存失效，累计费用继续保留。

## 密钥设置与更换

1. 登录 [DeepSeek 开放平台](https://platform.deepseek.com/)，在 API Keys 页面创建本项目专用的 Key，并确认账户有可用余额。
2. 在本机双击本目录的 `configure.command`。粘贴 Key，回车；设置至少 12 个字符的内测访问口令，再输入一次确认。输入过程隐藏字符。
3. 密钥保存在本机 `~/.config/laoyao-geo/credentials.json`，权限为 600。完整 Key 和口令保留在本机，避免写入聊天、前端或仓库。
4. 开发阶段可运行 `run-local.command`，通过 http://127.0.0.1:4010/geo/ 验证页面。离线测试不需要真实 Key。
5. 管理员发布当前提交后，停止本机服务，在项目根目录运行 `ruby ops/geo/provision.rb --install`。程序使用现有博客专用 SSH 连接，通过加密连接的标准输入安装配置。

安装程序会先关闭本机付费入口，再把本机累计费用及在途请求的预留费用写入服务器初始预算。安装结果不明确时，本机继续保持关闭，检查网站状态后可再次运行安装程序。更换 Key 或团队口令时重复第 2、5 步，服务器账本和累计费用保留。现有登录会话最长保留 12 小时。

## 50 元预算

金额以整数微元入账，调用前先预留上限，收到可核算用量后结算。SQLite 事务保证并发请求共用同一预算，重启和更新保留账本。每个登录会话每分钟最多发起 5 次搜索，全站同时最多处理 2 个问题；相同问题结果缓存 15 分钟。

按 2026 年 11 月 1 日的[官方价格](https://api-docs.deepseek.com/zh-cn/quick_start/pricing/)核算：Search、Fetch 每次成功且结果非空的请求为 0.005 元；`deepseek-flash` 按高峰价保守计算，输入每百万 token 2 元，输出每百万 token 8 元。忽略模型缓存折扣和空闲时段折扣，因此页面累计通常高于实际扣款。

一次搜索最多生成 3 个搜索词、执行 3 次 Search、读取 5 个来源、执行 5 次 Fetch，并调用模型两次。Search 已返回正文时跳过 Fetch。网络超时或结果不确定时保留预留费用，停止后续调用，不自动重试付费请求。异常用量超过预留范围时记录观测费用，并持久暂停后续付费调用。

50 元限制覆盖此应用的受控调用。本 Key 在其他工具中的使用、官方调价及账户充值由 DeepSeek 平台管理。上线后以平台账单复核实际扣款；调价后先更新计费规则，再继续内测。

## 运行和部署

后端使用 Ruby、WEBrick、SQLite，部署为 `geo-api` 容器，由博客容器代理 `/geo/api/`。API Key 只保存在服务器 `/etc/laoyao-geo/credentials.json`，以只读文件挂载；账本、缓存和登录会话保存在 Compose 的 `geo-data` 卷。静态构建排除 `backend/` 和 `ops/geo/`。

常规更新继续运行 `ops/laoyao/deploy.sh`。存在 `/etc/laoyao-geo/enabled` 时自动合并本目录的 Compose 配置。安装或更换配置设置 `.git/laoyao-deploy/reconfigure`，即使提交未变化也重建容器；全部健康检查通过后才清除标记。

专用 SSH 入口增加两个精确匹配的应用操作：`geo-configure` 接收有限长度的 JSON，校验提交、Key 格式、口令和预算；`geo-disable` 停止实时服务、恢复原 Nginx 配置并重新部署博客。其他远程命令继续执行原有部署流程。该连接不提供远程终端。

关闭实时内测并恢复博客：

```bash
ssh -i ~/.ssh/id_ed25519_laoyao_blog_deploy -o IdentitiesOnly=yes -o StrictHostKeyChecking=yes root@39.107.137.177 geo-disable
```

关闭操作保留凭据和数据卷。再次启用使用安装程序。不要删除 `geo-data` 卷或费用表，这会丢失累计用量。

容器内部代理只信任回环地址和 Docker 私网代理提供的客户端 IP。外层 Nginx 需传递真实 `X-Forwarded-For`，用于分开不同客户端的登录限流。浏览器登录使用 HttpOnly、SameSite=Strict、生产环境 Secure Cookie。

## 检查命令

```bash
ruby -Ibackend/geo/test -e 'Dir["backend/geo/test/*_test.rb"].sort.each { |path| require File.expand_path(path) }'
bash ops/laoyao/test_deploy.sh
docker build -f backend/geo/Dockerfile -t laoyao-geo:internal .
docker run --rm --network none laoyao-geo:internal ruby -e 'require "sqlite3"; require "webrick"; puts "runtime ready"'
docker run --rm --network none -v "$PWD:/repo:ro" ruby:3.3-alpine ruby /repo/ops/geo/test-provision.rb
```

这些检查使用离线假数据。开发阶段的真实接口检查为 `ruby ops/geo/check-live.rb --run`，会计入预算；安装到服务器后本机付费检查自动关闭。

在本机已配置 Playwright 的 Node 环境中，运行 `node backend/geo/test/ui_test.cjs` 可检查教学与实时版的组件规格、六种宽度、六个过程页及资料不足、错误和停止状态。该脚本启动独立的本地假数据服务，不调用真实 API，截图保存在终端输出的临时目录。

接口说明：[Search](https://api-docs.deepseek.com/zh-cn/api/search/)、[Fetch](https://api-docs.deepseek.com/zh-cn/api/fetch/)。
