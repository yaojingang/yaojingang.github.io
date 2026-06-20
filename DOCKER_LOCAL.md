# 本地 Docker 调试

这个配置用于在本地通过 Docker 启动博客，避免依赖本机 Ruby/Jekyll 环境。

Docker 会同时加载 `_config.yml` 和 `_config.local.yml`。本地配置只把站点地址覆盖为 `http://127.0.0.1:4000`，不会影响 GitHub Pages 线上构建。

## 启动

```bash
docker compose -f docker-compose.local.yml up --build
```

启动后访问：

```text
http://127.0.0.1:4000/
```

## 后台运行

```bash
docker compose -f docker-compose.local.yml up -d --build
```

查看日志：

```bash
docker compose -f docker-compose.local.yml logs -f blog
```

停止：

```bash
docker compose -f docker-compose.local.yml down
```

## 重新构建

如果 Dockerfile 或 Jekyll 依赖变更，执行：

```bash
docker compose -f docker-compose.local.yml build --no-cache
docker compose -f docker-compose.local.yml up
```
