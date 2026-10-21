# Lsky Pro

基于 Laravel 的开源图床，支持图片上传、管理、分享及多种存储后端。

本仓库是 [lsky-org/lsky-pro](https://github.com/lsky-org/lsky-pro) 的独立维护 fork，由 [ShiFangJuMie](https://github.com/ShiFangJuMie) 维护。当前重点是安全修复、运行环境兼容性和 Docker 部署，以支持现有实例继续使用。

[Docker 部署](docs/docker.md) · [参与贡献](#参与贡献) · [提交记录](https://github.com/ShiFangJuMie/lsky-pro/commits) · [上游项目](https://github.com/lsky-org/lsky-pro)

## 维护范围

- PHP 运行环境与基础镜像的安全更新。
- Docker 构建、部署兼容性和已有数据卷的迁移说明。
- 使用中发现的问题修复、依赖兼容性检查及文档改进。

本 fork 的变更、部署方式和问题反馈以本仓库为准；原项目的使用文档可作为既有功能的参考。

## 主要功能

- 图片上传与管理：批量、拖拽、粘贴上传，图片重命名、链接复制和相册管理。
- 多种存储后端：本地、AWS S3、MinIO、阿里云 OSS、腾讯云 COS、七牛云、又拍云、FTP、SFTP 和 WebDAV。
- 用户组与存储策略：为用户组配置多个存储策略、上传频率、文件命名规则和图片审核。
- 图片处理：缩略图、图片水印、文字水印，以及水印的平铺、定位和旋转。
- API 与分享：通过接口上传和管理图片、相册，支持图片广场。
- 数据库与缓存：支持 MySQL、PostgreSQL、SQLite 等数据库，支持文件缓存和 Redis 等缓存后端；具体可用后端取决于部署环境中的驱动。

## Docker 构建与部署

当前镜像使用 **PHP 8.2.35**，包含 CVE-2026-109618、CVE-2026-109619 的上游修复。镜像从本仓库源码构建，应用依赖按 `composer.lock` 安装。

在仓库根目录执行：

```sh
docker build -t lsky-pro:php-8.2.35 .
sh docker/test-image.sh lsky-pro:php-8.2.35
```

测试使用独立临时容器和数据卷，检查 PHP/Apache、HTTP/HTTPS、图片处理和已有卷的启动保护。

镜像兼容原 `halcyonazure/lsky-pro-docker` 的 `/var/www/html` 应用卷，默认 HTTP、HTTPS 容器端口分别为 `8089`、`8088`。替换已有实例前，请先备份并在副本上验证。完整步骤、环境变量和回退方式见 [Docker 部署文档](docs/docker.md)。

应用内置的在线更新仍连接上游服务。更新本 fork 请使用本仓库源码和镜像构建流程，避免上游更新覆盖 fork 的改动。

## 运行环境

当前 Docker 构建使用 PHP 8.2.35、Composer 2，并包含所需的 PHP 扩展。手动部署需满足锁文件中的依赖约束，并核对以下要求：

- PHP 扩展：BCMath、Ctype、cURL、DOM、Fileinfo、FTP、JSON、Mbstring、OpenSSL、PDO、Tokenizer、XML 和 Imagick，以及所选数据库对应的 PDO 驱动。
- PHP 函数：`exec`、`shell_exec`、`readlink`、`symlink`、`putenv`、`getenv`、`chmod`、`chown` 和 `fileperms`。
- Web 根目录指向 `public/`，并配置 URL 重写；运行用户需有应用所需的目录写入权限。

完整依赖约束以 `composer.lock` 为准。手动部署前，可在仓库根目录检查运行环境：

```sh
composer --no-interaction --no-plugins --no-scripts check-platform-reqs --lock --no-dev
```

## 参与贡献

欢迎通过[本仓库的 Pull Requests](https://github.com/ShiFangJuMie/lsky-pro/pulls) 提交修复和文档改进。请说明解决的问题、改动范围及验证方式。

涉及运行问题时，请补充部署方式、PHP 版本、复现步骤和脱敏后的错误信息。

## 上游与致谢

原始项目：[lsky-org/lsky-pro](https://github.com/lsky-org/lsky-pro)。感谢原作者与所有贡献者。

本项目基于 Laravel、Intervention Image、Flysystem、Tailwind CSS 等开源项目构建。各依赖的许可和署名见对应项目及其随附文件。

## 开源许可

沿用上游的 [GNU GPL v3 许可证](LICENSE)，保留原有版权和许可声明。

Copyright (c) 2018-present Lsky Pro.
