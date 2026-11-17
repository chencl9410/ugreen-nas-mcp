# Codex 绿联云连接器

在 Codex 中读写绿联 NAS 文件、上传和下载文件，以及管理容器、下载任务和应用。连接器通过 MCP 调用绿联官方 `unc` CLI，支持的操作由 CLI、NAS 固件和访问令牌权限共同决定，没有额外的只读开关。

这是社区项目。本项目不附带官方 CLI，也不保存或分发访问令牌。每位使用者都需要安装 `unc`，并在自己的电脑上授权自己的 NAS。WorkBuddy 已在同一电脑完成授权时，可以复用该用户的 CLI 登录缓存，无需保持 WorkBuddy 运行。

## 支持的平台

连接器支持 **macOS、Linux（包括 Ubuntu）和 Windows**。三者共用同一套 MCP 工具与官方绿联 `unc`。macOS 还可以选用登录钥匙串保存授权。

| 平台 | 绿联 CLI | Codex 注册脚本 |
| --- | --- | --- |
| macOS（Apple Silicon / Intel） | 官方 `install.sh` | `./scripts/install.sh`，可选 `--keychain` |
| Linux（Ubuntu，ARM64 / x86-64） | 官方 `install.sh` | `./scripts/install.sh` |
| Windows | 官方 `install.ps1` | `& .\scripts\install.ps1` |

## 快速开始

准备 Git、[Node.js 22 或更新版本](https://nodejs.org/)、可在终端运行的 `codex` 命令，以及支持开放 CLI 的绿联 NAS。所有平台都从本仓库默认分支安装。

```sh
git clone https://github.com/chencl9410/ugreen-nas-mcp.git
cd ugreen-nas-mcp
npm ci --ignore-scripts
```

### 安装绿联官方 CLI

已安装 `unc` 可直接复用。macOS 和 Linux 使用绿联的同一个安装脚本，它会选择对应的系统和架构。

```sh
unc_installer=$(mktemp)
curl -fsSL -o "$unc_installer" https://file1-cn.ugnas.com/nas-cli/install.sh &&
  UNC_NO_SKILLS=1 sh "$unc_installer"
rm -f "$unc_installer"
"$HOME/.local/bin/unc" version
```

Windows 在 PowerShell 中运行绿联的 Windows 安装脚本。

```powershell
irm "https://file1-cn.ugnas.com/nas-cli/install.ps1" | iex
& "$env:USERPROFILE\.local\bin\unc.exe" version
```

CLI 默认安装到当前用户的 `.local/bin`。自定义路径时，先在终端把 `UGREEN_UNC_BIN` 设置为官方可执行文件的绝对路径。Windows 若还需要在 Codex 中使用自定义路径，在服务的 `env` 配置段设置同一个变量。

### 授权与验证

从 NAS 的「个人中心 → 本地账号 → 访问与授权」创建访问令牌。在项目目录运行下列命令。已有有效的官方 CLI 授权会直接复用。

```sh
npm run connect
npm run check
```

首次连接会打开本机授权页，在网页中填写 NAS 地址和令牌。Linux 桌面环境用 `xdg-open` 打开浏览器。没有图形界面的 Ubuntu 可以在本机终端运行 `"$HOME/.local/bin/unc" auth login` 交互授权，再运行 `npm run check`。如果同一台机器有浏览器但自动打开失败，运行 `npm run connect -- --no-open`，在该机器的浏览器中打开本次生成的地址。

### 注册到 Codex

macOS 和 Ubuntu/Linux 使用：

```sh
./scripts/install.sh
```

Windows 在 PowerShell 中使用：

```powershell
& .\scripts\install.ps1
```

脚本会备份现有配置。重新启动 Codex CLI 后可用 `/mcp` 查看 `ugreen-nas`，桌面端也可在「设置 → MCP servers」查看。项目目录是 MCP 的启动目录，请保留。传输大文件或安装应用超过 Codex 默认工具超时时，可在该服务器的配置里设置 `tool_timeout_sec = 1860`。 [Codex MCP 文档](https://learn.chatgpt.com/docs/extend/mcp?surface=cli)

在新聊天中可直接说「列出我的 NAS 共享文件夹」或「查看 NAS 存储卷和 Docker 容器状态」。

### 使用 macOS 登录钥匙串

钥匙串是可选的认证方式。需要 Xcode 或 Xcode Command Line Tools，可用 `xcrun --find clang` 检查。先在项目根目录编译本机启动器。

```sh
npm run keychain -- build
```

如果官方 `unc` 不在 `~/.local/bin/unc`，先在当前终端设置 `UGREEN_KEYCHAIN_UNC_BIN` 为官方可执行文件的绝对路径。根据已有的授权，选择一种方式：

| 场景 | 命令 |
| --- | --- |
| 首次保存或更换令牌 | `npm run keychain -- store` |
| 导入当前用户的 `~/.unc/auth.json` | `npm run keychain -- import-cache` |
| 导入此前本机启动器保存的 **UGREEN NAS for Codex** 条目 | `npm run keychain -- import-legacy-keychain` |

`store` 会询问 NAS 的完整 HTTPS 地址（例如 `https://nas.example.net:9443`）和访问令牌。令牌输入不回显。使用 UGREENlink ID 时，先通过 `npm run connect` 完成官方授权，再用 `import-cache` 导入已解析的地址。若中继地址后续变化，重新完成官方授权并导入。

保存和导入都会通过 `unc` 验证连接，成功后才更新名为 **UGREEN NAS MCP (macOS)** 的钥匙串条目。导入会保留原登录缓存或旧钥匙串条目。在 MCP 运行时，启动器从钥匙串读取地址和令牌，仅通过环境传给本次调用的 `unc`。令牌不需要放进命令参数、Codex 配置或 Git。

可先在终端确认钥匙串授权可用，再为新的 Codex 安装注册启动器。

```sh
npm run keychain -- check
UGREEN_UNC_BIN="$PWD/build/unc-keychain" npm run check
./scripts/install.sh --keychain
```

如果已经配置了 MCP，在现有服务器的 `.env` 配置段里，把 `UGREEN_UNC_BIN` 改成项目下 `build/unc-keychain` 的绝对路径。官方 `unc` 自定义安装时，再加 `UGREEN_KEYCHAIN_UNC_BIN` 指向官方可执行文件。保留已有的工具权限和代理设置，然后重新打开 Codex。若 macOS 弹出钥匙串访问提示，请核对本机启动器路径。

验证通过后，如需清理官方 `unc` 的明文缓存，先确认 WorkBuddy 或直接运行的 `unc` 已经不再依赖它，再运行官方 `unc auth logout`。之后重跑 `npm run keychain -- check`。自定义路径时，请直接运行对应路径下的官方 `unc`。

## 授权网页怎么填

这就是 WorkBuddy 点击绿联云图标时打开的官方页面，由本机 `unc` 提供。Codex 通过连接助手打开同一页面，不需要先安装或运行 WorkBuddy。

### 地址与访问令牌

字段旁的 `ⓘ` 是填写说明，不代表连接故障。鼠标移到图标上可以查看提示：

| 页面项目 | 网页提示与填写方法 |
| --- | --- |
| `UGREENlink ID` | 提示为“在「绿联云」App 的‘控制面板 > 设备连接 > 远程访问’中查看”。填写自己的纯 ID，例如 `your-id`，不要粘贴 `https://ug.link/your-id`；ID 只包含字母、数字和连字符。 |
| `DDNS` 页签 | 地址标签为“DDNS（动态域名）”，提示“可填写DDNS域名或IP地址”。也用于局域网 IP。输入框已固定显示 `https://`，后面填写域名或 IP 及实际 HTTPS 端口，例如 `192.168.1.10:9443`；`9443` 只是示例，以自己 NAS 的设置为准。不要重复填写前缀，也不要填写 `http://`。 |
| `访问令牌` | 提示为“在「绿联云」App 的‘个人中心 > 本地账号 > 访问与授权’中创建”。在该入口创建访问令牌，按需要选择查询或读写权限，再粘贴到本机网页。使用开放平台令牌，通常以 `ugpoa_v1.` 开头，不是 NAS 登录密码。 |
| 令牌框右侧眼睛 | 切换显示或隐藏令牌，方便自己核对。不要把显示令牌的截图、令牌正文或认证缓存分享出去。 |
| `连接` 按钮 | 地址与令牌都填写后才可点击；任一项为空时显示为灰色。提交过程中显示“连接中”。 |

自有域名经反向代理时，在 DDNS 页签填外部域名和 HTTPS 端口。如果 OpenCLI 返回 `secure_transport_required`，检查反向代理到 NAS 的上游地址是否也使用 HTTPS。NAS 的实际 HTTPS 端口可在「控制面板 → 设备连接 → 门户设置」查看。

令牌决定允许执行哪些方法，连接器没有额外的只读限制。需要写入时，应在创建令牌时授予对应读写权限；部分管理功能还要求管理员账号。需要扩大权限时，请在 NAS 上检查授权，必要时新建具有所需权限的令牌并重新授权。

### 证书提示与连接结果

页面顶部说明“所有连接均使用HTTPS加密，遇到不可信证书时，将由你确认后再继续”。出现“不可信证书”弹框时，会提供“取消”和“仍要继续”：请你亲自核对目标地址，确认这是自己的 NAS 后再决定是否继续。Codex 不会代替你点击接受。

成功页显示“授权已完成”，下面仍写着“请返回 WorkBuddy，等待连接结果”。这是官方页面的固定文案；使用本项目时返回 Codex 即可，连接助手会继续检查授权结果。随后运行 `npm run check`，确认连接和根目录查询通过，再重启 Codex 或重新加载 MCP。

若显示带 `!` 的“本次授权已失效”，或临时地址已无法打开，请重新运行 `npm run connect` 获取新页面。不要刷新、收藏或继续使用旧链接；重新启动会替换旧会话。

### 临时链接与等待时间

授权页地址形如 `http://127.0.0.1:<随机端口>/login/<随机串>/#/`。`127.0.0.1` 只指向当前电脑；端口和路径每次生成，不能作为固定入口，也不能分享给其他人使用。其他使用者在自己的电脑运行连接助手，为自己的 NAS 授权。

这里的 `http://127.0.0.1` 是本机授权网页地址，填写的 NAS 地址仍使用 HTTPS；两者用途不同。令牌只在自己的本机页面输入，不需要发送到 Codex 聊天或公开仓库。

本项目的 `npm run connect` 默认等待 **10 分钟**并持续检查状态。直接调用官方 `unc auth workbuddy` 时，CLI 默认等待 **5 分钟**，且需要调用方持续检查登录状态；日常连接优先使用本项目助手，等待时保持运行终端打开。

### 常见提示

| 提示或现象 | 处理方式 |
| --- | --- |
| `请输入 UGREENlink ID` / `请输入 DDNS 地址` / `请输入访问令牌` | 补齐对应字段。令牌只在本机网页填写。 |
| `UGREENlink ID…格式不正确，只能包含字母、数字和连字符` | 填纯 ID，不要填写整条 UGLink 网页地址。 |
| `ug.link 是跳转域名，请改用「UGREENlink ID」方式并填写你的 ID` | 切换到 `UGREENlink ID` 页签并填写自己的 ID。 |
| `IP 地址必须带端口` / `IPv6 地址必须带端口` / `主机名必须带端口` | 填入 NAS 实际 HTTPS 端口，例如 `192.168.1.10:9443`。IPv6 按页面给出的示例填写。 |
| `连接必须使用 HTTPS，请去掉地址里的 http://` | 去掉输入内容中的 `http://`，使用输入框自带的 `https://`，并核对 HTTPS 端口。 |
| `未找到 UGREENlink ID…` | 在绿联云 App 的远程访问设置中核对 ID。 |
| `查询 UGREENlink ID…失败` / `无法连接到…` | 检查 NAS 是否开机、地址与端口是否正确，以及当前网络和代理是否可达。 |
| `访问令牌无效，请检查后重试` | 检查是否粘贴完整、是否已过期或停用；必要时新建令牌后在网页重新授权。 |
| `该 NAS 暂不支持连接器，请升级 NAS 系统或检查地址` | 检查 NAS 系统对开放 CLI 通道的支持及连接地址；不要反复换令牌。 |
| `确认已过期，请重新填写并连接` | 证书确认已过期，重新填写并连接；若会话也失效，重新运行连接助手。 |
| `凭证保存失败` / `连接失败…详细原因见日志` | 按提示检查本机连接日志；可使用 `unc auth log --lines 50` 查看，分享日志前移除私人信息。 |
| 已连接，但操作提示`访问令牌未授权该方法` | 按错误中的方法名新建具有相应权限的令牌，再重新授权；连接成功不等于具备每项操作权限。 |

## 提供的工具

1.2.0 提供 18 个 MCP 工具，保留原有工具接口；网页授权由本机连接助手完成。

| 工具 | 用途 |
| --- | --- |
| `ugreen_connection_status` | 查看登录状态，默认真实联网检查 |
| `ugreen_list_files` | 列出个人/共享根目录或指定文件夹，支持分页 |
| `ugreen_file_stat` | 查询文件或目录元数据 |
| `ugreen_read_file` | 分段读取文本，每次最多 256 KiB；二进制或不完整 UTF-8 字节段返回 Base64 |
| `ugreen_search` | 按名称搜索，可限定目录和后缀 |
| `ugreen_search_results` | 根据搜索任务继续获取结果 |
| `ugreen_download_file` | 下载到用户指定的本机绝对路径，默认拒绝覆盖 |
| `ugreen_nas_info` | 查询存储、容器、镜像、Compose、已装应用和实时负载 |
| `ugreen_upload_file` | 从本机绝对路径上传到 NAS，支持冲突处理和校验 |
| `ugreen_create_directory` | 创建目录，可按需创建父目录和设置八进制权限 |
| `ugreen_create_file` | 创建文件并可写入初始文本，默认要求文件不存在 |
| `ugreen_write_file` | 覆盖、追加或按字节偏移写入文本 |
| `ugreen_copy_file` | 复制到指定 NAS 目录，支持冲突处理 |
| `ugreen_move_file` | 移动到指定 NAS 目录，或在同一目录中重命名 |
| `ugreen_delete_file` | 删除指定文件或目录，默认不递归、移入回收站 |
| `ugreen_restore_file` | 从回收站路径恢复文件 |
| `ugreen_cli_help` | 查看允许的业务命令帮助，无需认证 |
| `ugreen_execute` | 执行允许的官方 CLI 业务命令，覆盖文件、Docker、下载、应用和控制面板等功能 |

上传、复制和移动的 `on_conflict` 可选 `rename`、`skip`、`replace`；上传默认 `rename`。覆盖需要用户明确要求。创建目录默认权限为 `0755`，创建文件默认权限为 `0644`。创建文件的初始文本最多 16 KiB，写入文本每次最多 256 KiB，均按 UTF-8 字节计；`patch` 写入必须指定 `offset`。`ugreen_write_file` 只写入已存在的文件，新文件使用 `ugreen_create_file` 或上传。

专用文件写工具均支持 `dry_run`。通用工具 `ugreen_execute` 接收业务叶命令 `command`、字符串数组 `arguments`、可选文本 `stdin`，以及默认 `false` 的 `dry_run`。先用 `ugreen_cli_help` 确认当前 CLI 的具体参数；通用工具的 `--yes` 按命令要求放在 `arguments` 中，专用写工具自动处理 CLI 确认参数。

`ugreen_execute` 只开放已实现的业务命令，包含 `file`、`docker`、`download`、`app`、`ctl`、`storage`、`network`、`taskmgr`、`search` 和 `doctor`。它不执行 shell，也不开放令牌导出、切换认证、升级或卸载 CLI 等本机管理操作。当前官方 CLI 的存储、网络和任务管理器接口只提供查询；控制面板写操作包括创建用户、向自建群组追加成员。连接器不提供 CLI 尚未公开的功能，例如修改文件 ACL。

通用工具的命令和参数清单依据官方 `unc 0.1.61`，覆盖 99 个业务叶命令。CLI 将来新增的命令或参数，需要同步更新连接器清单。

## 写操作与结果核对

每次操作按用户给定的对象和范围执行。删除、覆盖、启停服务等重要操作先用 `dry_run: true` 核对影响；已有明确业务授权时可继续执行，超出范围再向用户确认。连接器开发和升级的授权，不包含修改或删除用户现有 NAS 文件来测试。

预演可能由 NAS 处理，也可能由 CLI 返回本地计划，以返回说明为准；预演不表示已经执行，也不保证真实操作成功。`--yes` 仅处理 CLI 确认，不提升令牌权限。写操作失败、超时或断线后应先查询当前状态，不自动重试，避免重复创建或修改。批量结果需逐项检查 `success`，异步任务应核实终态后再报告完成。

实测部分新文件创建预演会因目标尚不存在而返回 `NotFound`；这不能单独证明令牌只读，也不能证明真实创建一定失败。连接器保留原始错误，不把预演失败改成真实执行。

跨目录移动时，`destination` 必须是目标目录；同目录重命名时使用纯新文件名。永久删除需要显式设置 `permanent: true` 并有对应授权；递归删除需要显式设置 `recursive: true`。创建共享注册项后，CLI 没有注销接口，清理共享应在 NAS 管理界面完成，不能用删除文件代替。

目录列表和搜索可能有多页，需根据返回的分页字段继续查询；搜索使用 `task_id` 和 `next_offset`。容器查询最多返回一页 100 项，进程和服务查询返回按 CPU 排序的前 20 项。

先列出根目录，再使用结果中的路径。`/volume1` 等卷根路径不能代替共享文件夹路径。工具保留官方 CLI 的 JSON 结构，64 位数值可能以字符串返回。

不同固件、套件版本和令牌权限支持的功能不同。遇到权限或兼容性错误时，查看返回的 `error_detail` 与 `compatibility_hint`；部分方法在旧固件上不可用，重复登录不会补齐功能。

## 维护与移除

在原项目目录更新代码和依赖，再重启 Codex。使用钥匙串的 Mac 如果更新了启动器源码，再运行 `npm run keychain -- build`。

```sh
git pull --ff-only
npm ci --ignore-scripts
npm test
```

`npm test` 用模拟 CLI 验证工具和参数。已授权的设备可用 `npm run check` 验证真实 MCP 连接和根目录查询。检查结果只打印状态和数量。

| 平台 | 移除 Codex 注册 |
| --- | --- |
| macOS、Linux | `./scripts/install.sh --remove` |
| Windows | `& .\scripts\install.ps1 -Remove` |

移除注册后，官方 CLI 缓存和 macOS 钥匙串的授权仍可复用。使用官方 CLI 缓存且需要改绑时，可在终端运行官方 `unc auth login --force`。使用钥匙串时，按上面的步骤重新保存或导入。原始令牌和本机 Codex 配置应保存在本机。

## 致谢与许可

本项目基于 [xudong7587 的绿联 NAS MCP](https://github.com/xudong7587/ugreen-nas-mcp)，沿用其 Windows 支持、MCP 工具与授权流程，并补充 macOS 与 Linux 的安装入口。早期连接方式见 [investigation.md](investigation.md)。

本适配器按 [MIT 许可证](LICENSE)发布。绿联官方 CLI 单独获取，适用其自身的使用条款。
