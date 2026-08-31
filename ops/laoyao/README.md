# www.laoyao.cn 服务器更新机制

本目录保存 `www.laoyao.cn` 的服务器端代码更新入口。脚本在服务器仓库内运行，负责拉取 `main`、构建 Docker 镜像、启动容器并验证站点。

## 固定环境

- 仓库目录：`/www/wwwroot/www.laoyao.cn/yaojingang.github.io`
- GitHub：`git@github.com:yaojingang/yaojingang.github.io.git`
- GitHub 只读部署密钥：`/root/.ssh/id_ed25519_laoyao_blog_github`
- 分支：`main`
- Docker Compose：`docker-compose.laoyao.yml`
- 本机端口：`127.0.0.1:10001`
- 公网地址：`https://www.laoyao.cn/`

服务器保留以下本地部署文件：

- `DockerfileProd`
- `_config.laoyao.yml`
- `docker-compose.laoyao.yml`
- `docker/`

这些文件由服务器持有，不进入 Git 仓库。部署脚本允许它们保持未跟踪状态，并会拦截其他未知改动。

## 一次性启用

本机制首次发布后，在服务器执行一次常规更新：

```bash
cd /www/wwwroot/www.laoyao.cn/yaojingang.github.io
git remote set-url origin git@github.com:yaojingang/yaojingang.github.io.git
GIT_SSH="$PWD/ops/laoyao/git-ssh.sh" git pull --ff-only origin main
```

确认脚本存在：

```bash
test -f ops/laoyao/deploy.sh
```

## 日常更新

以后每周发布只需要运行：

```bash
cd /www/wwwroot/www.laoyao.cn/yaojingang.github.io
bash ops/laoyao/deploy.sh
```

脚本按以下顺序执行：

1. 检查 `git`、`docker`、`curl`。
2. 获取项目级部署锁，阻止并发发布。
3. 确认当前分支为 `main`，已跟踪文件保持干净。
4. 校验服务器本地部署文件和 Compose 配置。
5. 把 `origin` 统一为 GitHub SSH 地址，并通过 `ops/laoyao/git-ssh.sh` 使用只读部署密钥。
6. 最多尝试三次 `git fetch`。
7. 确认远端提交可以快进合并。
8. 记录更新前提交，再更新到 `FETCH_HEAD`。
9. 确认本地 `HEAD` 与远端目标提交完全一致。
10. 比较目标提交和上次成功部署的容器版本。
11. 按需构建并启动 Docker Compose 服务。
12. 检查容器、日志、本机 HTTP 和公网 HTTP。
13. 健康检查通过后记录本次成功部署的版本。

远端没有新提交，并且容器版本记录与目标提交一致时，脚本跳过镜像构建，只检查现有容器和网站健康状态。首次启用、手工拉取代码或回滚容器后，版本记录缺失或不一致，脚本会重新构建目标版本。

## 安全边界

出现以下情况时，脚本会立即停止：

- 当前分支偏离 `main`。
- 已跟踪文件或暂存区存在改动。
- 出现未知的未跟踪文件。
- 服务器本地部署文件缺失。
- Compose 配置无效。
- GitHub 拉取连续三次失败。
- 远端历史无法快进合并。
- 更新后的提交与 `FETCH_HEAD` 不一致。
- 容器、构建或 HTTP 健康检查失败。

GitHub 拉取失败时，Docker 构建不会启动。这样可以避免旧代码命中缓存后再次上线。

## 发布记录

脚本在 `.git/laoyao-deploy/` 保存两项状态：

```text
.git/laoyao-deploy/previous_commit
.git/laoyao-deploy/deployed_commit
```

- `previous_commit`：最近一次代码快进前的提交，用于回滚。
- `deployed_commit`：最近一次通过全部健康检查的容器版本。

查看当前代码、容器版本记录和回滚点：

```bash
cd /www/wwwroot/www.laoyao.cn/yaojingang.github.io
git rev-parse HEAD
cat .git/laoyao-deploy/deployed_commit
cat .git/laoyao-deploy/previous_commit
```

## 回滚

健康检查失败且需要恢复旧版本时执行：

```bash
cd /www/wwwroot/www.laoyao.cn/yaojingang.github.io

previous_commit=$(cat .git/laoyao-deploy/previous_commit)

git checkout --detach "$previous_commit"
docker compose -f docker-compose.laoyao.yml config
docker compose -f docker-compose.laoyao.yml up -d --build
docker compose -f docker-compose.laoyao.yml ps

curl -fsS http://127.0.0.1:10001/ >/dev/null
curl -fsS https://www.laoyao.cn/ >/dev/null

printf '%s\n' "$previous_commit" > .git/laoyao-deploy/deployed_commit.tmp
mv .git/laoyao-deploy/deployed_commit.tmp .git/laoyao-deploy/deployed_commit

git checkout main
```

容器会继续运行回滚版本，工作区会回到 `main`。下一次运行 `bash ops/laoyao/deploy.sh` 时，脚本会发现容器版本记录与 `main` 不一致，重新构建并恢复最新版。

## 常用检查

```bash
cd /www/wwwroot/www.laoyao.cn/yaojingang.github.io

git status --short --branch
git rev-parse --short HEAD
git config --get remote.origin.url

docker compose -f docker-compose.laoyao.yml ps
docker compose -f docker-compose.laoyao.yml logs --tail=80

curl -I http://127.0.0.1:10001/
curl -I https://www.laoyao.cn/
```

服务器 Git 版本较旧时，可用 `git config --get remote.origin.url` 查看远程地址。
