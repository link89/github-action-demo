# GitHub Actions 容器构建约定

本项目用于验证使用 GitHub Actions 自动构建容器。

## 总体约定

- 项目目录为 `{name}/{version}-{build-string}`。`build-string` 参考 conda 风格，记录影响二进制兼容性的关键依赖和构建选项；对应镜像标签为 `{name}:{version}-{build-string}`。
- 每个项目的 `build.sh` 是唯一构建入口。构建镜像时设置 OCI metadata（至少包括 source、revision、version 和 title）。
- 工作流自动发现 `{name}/{version}-{build-string}/build.sh`，每个入口在独立 job 中构建；新增项目无需修改工作流。
- 构建前检查目标标签是否已在仓库发布；已发布则跳过。需要重建时应更新版本或 build-string，避免覆盖已有标签。
- PR 只构建，不发布；合入主分支后才允许发布。发布凭据只用于主分支构建。

## 项目约定

- 先通过 `docker run` 编译，将源码、工具链和产物放在 runner 的 `/mnt/scratch`；再通过 `docker build --build-context` 从 `/mnt/scratch` 的发布产物构建最终镜像。
- `/mnt/scratch` 用作大体积工作目录，以缓解 GitHub Actions runner 根文件系统空间不足。构建前用 `df -h` 和 `mount` 核对它实际所在的文件系统；Docker 镜像层仍占用 Docker 数据目录。
- 区分运行时与构建依赖，`runtime-deps.sh` 只安装运行时依赖，`build-deps.sh` 安装编译工具及开发依赖。最终镜像不运行 `build-deps.sh`。
- 软件安装到 Linux 常规目录（如 `/usr/local/bin`、`/usr/local/lib`、`/usr/local/share`），避免为非标准安装路径额外导出 `PATH`、`LD_LIBRARY_PATH`。
