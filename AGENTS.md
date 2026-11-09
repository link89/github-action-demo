# GitHub Actions 容器构建约定

本项目用于验证使用 GitHub Actions 自动构建容器。

## 总体约定

- 项目目录为 `{name}`；同一项目的不同构建配置使用不同入口脚本，如 `make.sh`、`make-avx512.sh`。`build-string` 参考 conda 风格，记录影响二进制兼容性的关键依赖和构建选项；镜像标签在入口脚本中显式设定，不依赖目录结构。
- 构建入口统一命名为 `make*.sh`，源码或组件构建辅助脚本统一命名为 `build-*.sh`，安装和验证脚本分别使用 `install-*.sh`、`verify-*.sh`；重命名时同步更新所有调用方。
- 构建镜像时设置 OCI metadata（至少包括 source、revision、version 和 title）。
- `make*.sh` 在构建及已发布标签检查前输出项目名、版本、构建串、镜像地址、源码提交、发布模式，以及 runner 的系统、CPU、内存、磁盘挂载和 Docker 存储信息，便于核对 CI 日志。不得输出完整环境变量或凭据。
- 工作流显式列出 `make*.sh` 入口，每个入口在独立 job 中构建；新增构建配置时同步修改工作流。
- 构建前检查目标标签是否已在仓库发布；已发布则跳过。需要重建时应更新版本或 build-string，避免覆盖已有标签。
- PR 只构建，不发布；合入主分支后才允许发布。发布凭据只用于主分支构建。

## 项目约定

- 先通过 `docker run` 编译，将源码、工具链和产物放在 runner 的 `/mnt/scratch`；再通过 `docker build --build-context` 从 `/mnt/scratch` 的发布产物构建最终镜像。
- `/mnt/scratch` 用作大体积工作目录，以缓解 GitHub Actions runner 根文件系统空间不足。构建前用 `df -h` 和 `mount` 核对它实际所在的文件系统；Docker 镜像层仍占用 Docker 数据目录。
- 区分运行时与构建依赖，`install-runtime-deps.sh` 只安装运行时依赖，`install-build-deps.sh` 安装编译工具及开发依赖。最终镜像不运行 `install-build-deps.sh`。
- 软件安装到 Linux 常规目录（如 `/usr/local/bin`、`/usr/local/lib`、`/usr/local/share`），避免为非标准安装路径额外导出 `PATH`、`LD_LIBRARY_PATH`。
