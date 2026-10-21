# PHP 安全修复镜像

此镜像针对原 `halcyonazure/lsky-pro-docker` 的 PHP 8.1.28 运行环境，将 PHP 升至 **8.2.35**，覆盖 [CVE-2026-109618](https://github.com/php/php-src/security/advisories/GHSA-w8hw-w9fx-j79w)、[CVE-2026-109619](https://github.com/php/php-src/security/advisories/GHSA-6wmf-4rv5-p3rp) 的上游修复。Laravel、`composer.json`、`composer.lock` 和数据库结构不变。

PHP 8.2.35 官方镜像清单在修复时尚不可用，因此暂时使用固定摘要的官方 8.2.34 Bookworm Apache 底座，下载并校验官方 8.2.35 源码，完整重编译 CLI、Apache 模块和扩展。源码 SHA256 来自 [PHP 官方发布信息](https://www.php.net/releases/index.php?json&version=8.2.35)，编译选项沿用官方底座。后续官方镜像可用时可简化此步骤。8.2 分支安全支持截至 2026 年底，之后仍需规划升级。

## 构建与验证

在仓库根目录运行，首次构建需要联网下载编译工具、源码和锁定的依赖：

```sh
docker build -t lsky-pro:php-8.2.35 .
sh docker/test-image.sh lsky-pro:php-8.2.35
```

镜像支持官方底座提供的 ARM64、AMD64 平台；默认构建本机架构。镜像内包含 Imagick、BCMath、FTP、PDO MySQL/PostgreSQL/SQLite、Redis 和 Composer 所需扩展。构建不执行 Composer scripts/plugins、Artisan、安装或数据库迁移。

测试脚本只创建带唯一名称的临时容器和两个临时卷，不发布端口、不连接外网、不挂载现有应用目录。它通过真正的 HTTP/HTTPS 请求检查 Apache 的 PHP 版本、Imagick、重写规则、Authorization 头、上传目录链接、重启保留数据，并检查不兼容依赖和不完整卷会被拒绝，结束时清理这些测试资源。

## 替换旧镜像

继续沿用现有 Compose/Portainer 中的端口、环境变量、网络和挂载，只将应用的 `image` 替换为你构建的 `lsky-pro:php-8.2.35`。已有卷中的应用代码和 `vendor` 会被保留，修复来自镜像中的新 PHP 运行环境；不会用 fork 的源码覆盖旧应用。

兼容约定：

| 项目 | 默认值 |
| --- | --- |
| 应用卷 | `/var/www/html` |
| HTTP 容器端口 | `8089`，可用 `WEB_PORT` 修改 |
| HTTPS 容器端口 | `8088`，可用 `HTTPS_PORT` 修改 |
| Web 根目录 | `/var/www/html/public` |
| PHP 内存 / 上传限制 | `512M` / `100M` |

HTTPS 默认在首次启动时生成容器自己的自签证书。使用反向代理终止 TLS 的部署可以继续使用 HTTP；需要受信任的容器端 HTTPS 时，将自己的证书和私钥只读挂载到配置中的对应路径。不要沿用第三方镜像内置的共享私钥。

先在**完整备份的副本**上验证，再操作生产容器：

1. 备份整个应用挂载目录（包含隐藏配置、`installed.lock`、`vendor`、上传文件及 SQLite 文件），并单独备份外部数据库；保留旧镜像和原容器配置。这里只描述备份范围，不需要向协作者提供配置或密钥内容。
2. 使用备份副本进行平台检查；将 `/absolute/path/to/lsky-copy` 替换成实际副本路径。这条命令只读挂载、不启动 Laravel、不连接数据库：

   ```sh
   docker run --rm --network none \
     --mount type=bind,src=/absolute/path/to/lsky-copy,dst=/var/www/html,readonly \
     --workdir /var/www/html --entrypoint composer \
     lsky-pro:php-8.2.35 \
     --no-interaction --no-plugins --no-scripts check-platform-reqs --no-dev
   ```

3. 在隔离环境使用副本和测试数据库检查登录、上传、缩略图、图片链接、删除。副本不得连接生产数据库、对象存储写入凭据或生产队列。上述镜像测试不代替这些应用功能验证。
4. 确认兼容后，在维护窗口暂停写入，取得一致备份，再用新镜像重建单个 Lsky 容器。不要删除卷，不要运行 `docker compose down -v`，不要执行安装、升级或迁移命令。
5. 检查 `docker exec lsky-pro php -v`、容器启动日志和实际站点功能。已挂载应用依赖若不兼容 PHP 8.2，入口会拒绝启动；请修复副本中的兼容问题后再切换，不会自动更新依赖。

需要回退时，停止新容器，按原配置用保留的旧镜像重建，继续挂载原卷。本修复不迁移数据库；若应用功能测试修改了数据，则按备份方案恢复一致的数据。

空卷会复制镜像内的应用源码和锁定依赖，初始化目录所有权；已有应用卷不递归改权限，也不覆盖文件。非空但缺少 `public/index.php` 的目录会被拒绝，以免误覆盖挂载路径。新安装仍需按 Lsky 自身文档完成，不能通过此镜像执行破坏性自动安装。

本次只修补 PHP 运行环境；停止维护的 Lsky/Laravel 及其他依赖仍应单独评估，不能据此认为整个应用不存在安全问题。
