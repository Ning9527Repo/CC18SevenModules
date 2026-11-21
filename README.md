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

## 仅保留一个启用开关（最新要求）

系统「设置 → 控制中心」内仅追加「启用插件」开关及必要说明，直接读写原域`com.evgeniy558.controlcenter18`的`Enabled`并发布原prefs通知；默认关闭。不自动注销，不承诺无需手动注销即可完整热切换引擎。

独立插件设置页和PreferenceLoader入口已从两个Vendor中物理删除。本次继续实际删除保存预设、导入预设、日志浏览与分享、文档选择器及其处理源码，原`C18SettingsActions.h/.m`不再存在。改为只含两个偏好读写方法的`C18EnableControl.h/.m`。不保留隐藏页、跳转入口或仅禁用的动作代码。

原生App内访问、还原控制中心、控制中心引擎、四五键和八个保留模块不在删除范围。版本保持1.0，旧仓库不动。

上一版用户反馈四项未显示并且设置App闪退。2026-11-21 20:50:52 的真实报告为NSRangeException：`-[__NSArrayM objectAtIndex:]: index 0 beyond bounds for empty array`，异常链包含系统`ControlCenterSettings`的`_identifierAtIndexPath:`（静态+0x36b0，调用objectAtIndex）及CCSupport的cell呈现。新增分组进入系统按模块行索引的路径，是需要移除的风险点。

本版完全删除旧PSSpecifier设置页、预设／日志和旧入口代码。启用开关直接接入`CCUISettingsListController`原始specifier列表：创建一个标准开关specifier和所属标准分组，发布回同一个`_specifiers`数组；不使用footer，不自绘行，不修改系统table dataSource/delegate或模块数组。新行通过独立动态控制器类隔离。2026-11-21 23:03两份真机崩溃显示旧section门控仍落入CCSupport无条件模块索引链；本次删除手工计数group／缓存section的识别，改用Preferences基类的`specifierAtIndexPath:`解析实际行，以`cellClass`是否属于真实`CCUISettingsListCell`识别模块。所有非模块原生行（不只是新增开关）直接由Preferences生成单元格；模块仅在对应标识数组实际有该行时走原CCSupport链。`_identifierAtIndexPath:`改为数组类型及非负行号／count校验后的安全读取，不再调用系统未检查的objectAtIndex实现。原生App内访问和还原的specifier、动作、读写目标不变。初始化和当前已显示页面均覆盖。

用户23:49截图仍无开关。进一步直接解析本机`ControlCenterSettings`的ObjC方法表：`_identifiersInSection:`在0x3580，真实编码为`@24@0:8Q16`，参数是`NSUInteger`；上一版却要求`q`，严格ABI门控必然提前返回，连原列表子类／init hook都未安装。本次只修正此处为`Q`及对应`NSUInteger`调用，并加入本机方法编码fixture、覆盖安装门控的CI回归，避免只测已安装后的行路由。原列表开关／空数组保护、八模块及删除范围保持不变。

用户随后真机确认新增启用开关显示且有效，但原“App内访问”行消失、其说明仍在。本轮保留动态子类的原系统`class`资源身份；原访问行存在时保持同一对象，缺失时仅在原访问分组后补一个标准PSSwitchCell，仍调用系统`allowedWithinApps:`／`setAllowedWithinApps:specifier:`，不写插件偏好、不重建整页。新增开关、还原、8模块及旧越界保护不变。包显示名仍为ControlCenter18；按本轮要求Author/Maintainer为Ning，Package改为com.ning.controlcenter18，通过Conflicts/Replaces/Provides替换旧ID，运行时旧偏好域保持兼容。未上源。

这是针对已确认启动阻断与越界路径及原生访问行回归的修正，不等同于已完成真机验证。双架构语法、Objective-C路由模型、物理删除与终包签名校验不能替代安装后的开关显示／运行态验证。构建时原库文件名`C18FourSettings`仅为同包替换兼容保留，内容只含一个原列表开关，旧四项类和行为不会打包。
