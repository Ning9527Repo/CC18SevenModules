# CC18 八模块版 · 1.0

独立仓库 `Ning9527Repo/CC18SevenModules`。从已确认的 `Ning9527Repo/C18ConnectivityFive` 提交 `7f06b36409d4145457947f25f1d4f473a636bb2e` 派生；旧仓库保留且不改动，两套源码分别维护。

## 仅保留的第三方模块

1. 蜂窝4/5G切换
2. 蜂窝管理（SIM 启停）
3. 双卡蜂窝数据切换
4. 清理角标
5. 注销
6. CC VPN
7. 系统开机计时
8. 实时 CPU

这是系统原生模块之外的八项，不是把整个控制中心缩成八个按钮。原生模块、四／五键布局、原有电源功能及其他既有行为保留。

## 删除方式

- 其余22个第三方 bundle 的目录、Info.plist、可执行文件、资源、RootHide 专属链接均从两份 `Vendor/baseline-*.deb` 里实际删除，不是仅隐藏或黑名单过滤。
- 删除帧率模块专用 `CADebugHelper`，保留蜂窝4/5G与SIM helper、原生核心及其共享依赖。
- 删除旧 companion 和过时电源 provider 输入文件，不保留含旧目录映射的备用可执行文件；使用当前源码新编译功能库。
- 清理四／五键名称映射及被删模块专属本地化覆盖。仅保留迁移所需的长度／摘要身份，用于移除旧布局记录和替换失效槽位，不包含被删模块的构造或动作代码。
- 原系统模块与保留八项的程序／资源不改；产品拥有的 SIM 版本字段同步为1.0，旧独立设置 bundle 已移除。
- `tools/retained_modules.py` 对输入和最终包要求第三方目录恰好八项；构建重新带入任何其他第三方 bundle 会失败。删除与保留审计见 `Vendor/retained-seven.json`，这里只含身份／路径／哈希记录，不含被删二进制。

四／五键原有能力限制保留：系统开机计时、CPU等实时统计卡片原来就不支持放进小圆槽，本版不擅自开放。这些模块仍以独立卡片保留。

## 仓库共存与安装

两个仓库共存不等于同时加载两套控制中心引擎。为避免冲突，安装包保持原包标识 `com.evgeniy558.controlcenter18`，新旧版覆盖替换，不可同时安装。版本1.0按用户要求重新编号，低于旧3.0-beta6；包管理器可能需要手动选择降级／替换。

新deb不会包含那22项；通过同包标识升级／替换时由dpkg移除旧包拥有且新版不再提供的文件。若相同模块由别的独立插件包另行安装，本项目不删除其他包拥有的文件。

## 构建及验收

仅 `workflow_dispatch`，`macos-latest`，push不自动构建。一次授权只触发一次，失败后不自动重跑。默认输出普通无根64版（var/jb）及RootHide 64e版（根Library/usr）。CI保留原有双架构编译、签名、核心代码区段不变校验，并加入八模块物理删除与旧槽迁移测试。

```sh
python3 tools/check_source.py
python3 tools/retained_modules.py
python3 tools/test_module_migration.py
python3 tools/test_settings.py
python3 tools/test_power_root.py
```

打包使用原来的Python ar/USTAR/XZ流程，不调用macOS ar。不会自动安装、注入、注销、上软件源或执行电源操作。构建／静态验收通过不代表iOS真机功能已验证。

署名沿用 Ning&evgeniy558；保留模块的原作者元数据不被改写。

## 仅保留四项设置，直接进入系统控制中心页面

`Settings/C18SettingsBridge.m` 与 `C18SettingsActions.m` 为新源码实现，仅向 `CCUISettingsListController` 追加「启用插件、保存预设、导入预设、崩溃日志」及必要分组说明，不创建中间跳转页。

旧 `ControlCenter18Prefs.bundle` 全部程序、独立 PreferenceLoader 入口、介绍大图、警告卡片及旧本地化已从两版 Vendor 输入中物理删除；旧 prefs_cleanup/prepare_prefs/test_prefs 补丁源码删除。不会载入旧根页后仅隐藏行。构建时新编译 `C18FourSettings.dylib`，过滤器只注入系统设置进程。

保留原有系统控制中心页面桥 `ControlCenter18Settings.dylib`，它提供第一张截图已有的系统页面布局（App内访问、还原等）；不是旧插件根设置页。新库通过合并 specifiers 保留系统原行。原控制中心核心、布局和非设置功能不重写。

启用键仍是原CFPreferences域 `com.evgeniy558.controlcenter18` 的 `Enabled`，发布原通知，不自动注销；开关说明明确需要用户手动注销以完整生效。保存／导入兼容原 XML/binary plist 包装及裸布局、原文件路径与reloadLayout通知；没有有效控制配置时不会清空旧配置。布局与控制配置分别原子写入，不是跨文件事务，部分失败会明确提示。

日志仅读取原ControlCenter18日志目录中的`.log`，不扫描系统其他崩溃目录，不删除日志。日志页面和分享属于保留的「崩溃日志」功能。

本次源码包括恢复的「注销」模块：迁移身份不再将该ID及`#2`实例判为已删；原完整目录与中文选项恢复。其他22项仍被物理删除。仓库名保留为`CC18SevenModules`以沿用已经创建的独立仓库，但当前功能实际是八项；不自动重命名或新建第三个仓库。

### 验证边界

新设置源码双架构严格语法、导入格式模型和终包文件检查可在CI验证；目标系统私有PSSpecifier签名、真实页面挂载、iCloud提供器导入导出、启用后的运行态效果仍需真机确认。不会把构建通过说成真机全部可用。
