# mihomo 多机场配置模板

一份**能同时挂多个机场订阅**的 mihomo (Clash.Meta) 配置：四家机场的节点自动合并进同一个地区组，
一份配置导入所有设备，某个机场跑路/掉速也不会整体失联。

- `config.yaml` —— 模板本体（只有 `REPLACE_ME_A ~ REPLACE_ME_D` 占位，**不含任何真实订阅链接**，可随意公开/分享）
- `airports.example.yaml` —— 机场清单示例（复制成 `airports.yaml` 填链接，已 gitignore）
- `scripts/render.py` —— 把 `airports.yaml` 里的链接注入模板，输出 `dist/config.yaml`
- `scripts/check.sh` —— 用 mihomo 内核校验：语法 + 真机加载（provider / 策略组）
- `.github/workflows/validate.yml` —— 每次 push 自动用 mihomo 校验模板（CI 用假链接，不碰凭证）

---

## 一、3 分钟上手

```bash
git clone https://github.com/AOTUMAN133/mihomo-config && cd mihomo-config

# 方式一：最省事 —— 直接编辑 config.yaml，把 4 处 REPLACE_ME_x 换成订阅链接，完事
# 方式二（推荐）：链接单独放，模板保持干净、可以随时 pull 上游更新
cp airports.example.yaml airports.yaml   # 填 1~4 个机场链接
python3 scripts/render.py                # 生成 dist/config.yaml
bash scripts/check.sh                    # 先语法校验
bash scripts/check.sh --run              # 再真机跑 8 秒，看 provider/策略组有没有加载
```

然后把 `dist/config.yaml`（或改好的 `config.yaml`）喂给客户端：

- **Clash Verge / Clash Verge Rev**：配置 → 新建 → 本地文件 选 `dist/config.yaml`；
  或者放进 `profiles/` 目录。想自动更新就把它放到一个能被 URL 拉到的位置，用「远程」导入。
- **mihomo 内核 / OpenClash**：OpenClash → 配置文件 → 上传/指定路径。
- **Android**：mihomo/clash 系客户端（ClashMetaForAndroid、FlClash 等）导入本地文件。

> 只填了 2 个机场？不用删任何东西 —— `render.py` 会把没填的那些机场的 provider 块、策略组、
> `use:` 引用**整块剔除**，剩下的配置照样是完整可用的。

## 二、这份配置长什么样

```
4 个机场订阅 (proxy-providers, 各自独立测速/更新)
        │
        ├─ 1️⃣ 机场一 / 2️⃣ 机场二 / 3️⃣ 机场三 / 4️⃣ 机场四   （单独用某一家的节点）
        ├─ ♻️ 自动选择 (fallback) / 🔯 故障转移 (fallback) / ⚖️ 负载均衡 (load-balance)
        ├─ 🇭🇰 🇺🇸 🇯🇵 🇸🇬 🇹🇼 🇰🇷 🇨🇦 🇬🇧 🇫🇷 🇩🇪 🇳🇱 🇹🇷 地区组（四家节点按地区自动合并、自动测速）
        └─ 服务组：🤖 ChatGPT / AI服务 / 📹 YouTube / 🎥 Netflix / Disney+ / HBO / Emby /
                   💬 即时通讯 / 🌐 社交媒体 / 🚀 GitHub / 🎮 Steam / 🍎 苹果 / Ⓜ️ 微软 …
                   🛑 广告拦截（默认 REJECT，可切成 DIRECT 一键关掉）
```

**策略组共 51 个**，其中 33 个通过 `use:` 直接引用四家 provider（所以地区组和服务组拿到的是
**合并后的全部节点**，而不是只认一家）。规则集来自
[Aethersailor/Custom_OpenClash_Rules](https://github.com/Aethersailor/Custom_OpenClash_Rules)，
GeoData 走 [Loyalsoldier/v2ray-rules-dat](https://github.com/Loyalsoldier/v2ray-rules-dat)（jsDelivr CDN）。

几个刻意的设计：

| 设计 | 为什么 |
|---|---|
| 每个 provider 层带垃圾节点过滤 `filter:` | 公告/流量/到期这类条目在**入口**就被滤掉，各策略组不必重复配 |
| `health-check.lazy: true` | 按需测速。50 个组 × 4 家机场全量测速很费电费流量，笔记本/手机建议保持 true |
| `profile.store-selected: true` | 手动选过的节点重启后还记得 |
| 机场专组（`1️⃣~4️⃣`） | 想固定只走某一家时直接选它，不用在一堆节点里翻 |
| `⚖️ 负载均衡`（consistent-hashing） | 大流量/多连接场景把请求摊到多家，单家限速时更稳 |
| `airports.yaml` 与模板分离 | 模板可以放公开仓库并持续更新，凭证永远不进 Git |

## 三、验证（交付前的标准动作）

```bash
bash scripts/check.sh          # 语法: 期望 "configuration file ... test is successful"
bash scripts/check.sh --run    # 真机: 看 provider 拉到了多少节点、有没有 error
```

实测样例（用两个公开免费源当替身，只验证管线）：

```
1️⃣ 机场一   URLTest     候选=19
2️⃣ 机场二   URLTest     候选=26
♻️ 自动选择  Fallback    候选=45     ← 两家节点确实合并了
🔯 故障转移  Fallback    候选=45
⚖️ 负载均衡  LoadBalance 候选=45
🚀 手动选择  Selector    候选=61
🇺🇸 美国节点 URLTest     候选=25     ← 地区组跨机场合并生效
```

没有 mihomo 二进制时 `check.sh` 会自动从 GitHub release 下载 `amd64-compatible` 版（老 CPU 也能跑）。

## 四、测速 / 自动选择 / 分流的实测表现

这三个问题的答案取决于内核参数，不是"感觉好不好"，所以直接测：

### 分流（规则命中）—— 16/16 正确
内核跑起来后，通过代理口真实请求，读 debug 日志里的 `match` 记录：

| 域名 | 命中规则 | 目标组 |
|---|---|---|
| www.netflix.com | GeoSite/netflix | 🎥 Netflix |
| www.youtube.com | GeoSite/youtube | 📹 YouTube |
| api.openai.com | GeoSite/openai | 🤖 ChatGPT |
| claude.ai | GeoSite/category-ai-!cn | 🤖 AI服务 |
| www.disneyplus.com / open.spotify.com | GeoSite/disney / spotify | 🎥 / 🎻 |
| api.telegram.org | GeoSite/category-communication | 💬 即时通讯 |
| github.com / steamcommunity.com | GeoSite/github / steam | 🚀 / 🎮 |
| www.google.com / tiktok.com | GeoSite/google / tiktok | 🇬 / 🎶 |
| www.apple.com / www.microsoft.com | GeoSite/apple / microsoft | 🍎 / Ⓜ️ |
| www.baidu.com / bilibili / taobao | GeoSite/cn | 🎯 全球直连（正确直连） |

> 分流由规则集决定，与"几个机场"无关；本次改造没动规则，只改了节点来源。

### 自动选择（选得准不准）—— 已按实测结果修正
**原配置里 `♻️ 自动选择` 是 `fallback` 类型**：按候选**顺序**取第一个能连通的，不是取延迟最低的。
实测（同一次运行，同一批节点）：

| 变体 | `♻️ 自动选择` 类型 | 选中节点延迟 | 组内最快 | 结论 |
|---|---|---|---|---|
| 原样 | fallback | 201 ms | 173 ms | ❌ 慢了 28 ms（它只是"能连"） |
| 改后 | **url-test** (tolerance 50) | 184 ms | 184 ms | ✅ 就是最快 |

4 个测速型组里"选中即最快"的比例：**原样 1/4 → 改后 3/4**（唯一没中的是 `🔯 故障转移`，它本来就该按可用性顺序取，见下）。

所以模板已改成：`♻️ 自动选择` = `url-test`（要最快），`🔯 故障转移` = `fallback`（要"一定有得用"）。
两者语义不同，别混用：**追速度选前者，追可用性/稳定选后者。**

### 测速参数与它的局限
| 参数 | 值 | 作用 |
|---|---|---|
| `unified-delay: true` | 开 | 统一握手耗时口径，跨机场的延迟数字才可比 |
| `tolerance` | 自动选择 50 / 地区组 120 | 延迟差小于该值不切换，避免节点间来回抖动 |
| `interval` | 180 s（自动选择）/ 300 s | 测速周期 |
| `health-check.lazy` | provider 侧 true | 只在该组被使用时才测速，省电省流量 |

局限（别指望它超出能力）：URLTest 测的是**到一个 gstatic 探测点的延迟**，
不等于带宽、不等于流媒体/AI 能不能解锁。所以 Netflix/ChatGPT 这些组建议**手动选**已知解锁的地区节点，
别交给 `自动选择`（它只看延迟，可能挑到一个延迟最低但解不了锁的机房）。

### 广告拦截（已加，实测有效）
新增 `🛑 广告拦截` 组（`select`，默认 `REJECT`，切成 `DIRECT` 即一键关闭）+ 规则
`- RULE-SET,Advertising,🛑 广告拦截`（放在 private 直连之后、其它规则之前）。

规则集用 **mrs 格式**（`MetaCubeX/meta-rules-dat` 的 `category-ads-all`，**8 KB / 910 条**）——
比 blackmatrix7 的 `Advertising_Domain.yaml`（7.6 MB）/`Advertising_Classical.yaml`（10 MB）轻几个数量级，
移动端/盒子上不值得为广告表拉十兆文件。想更全的话把 `rule-providers.Advertising.url` 换成那个大的即可
（记得 `behavior: domain` → `classical`、`format: mrs` → `yaml`）。

实测证据（同一内核，只切换该组的目标）：

| 该组目标 | 请求 doubleclick.net / googleads.g.doubleclick.net | 说明 |
|---|---|---|
| `REJECT`（默认） | 失败，**50 ms** 返回 | 直接拒绝，不去拨号 —— 这就是"已拦"的特征 |
| `DIRECT`（关掉） | 一次成功 650 ms、一次 8 s 超时 | 请求真的发出去了，说明差别来自这条规则 |

- 规则表里位置：`#3 RuleSet Advertising -> 🛑 广告拦截`（规则总数 47 → 48）
- 规则集加载状态：`behavior=Domain、format=MrsRule、ruleCount=910`
- 非广告域名不受影响：netflix/openai 仍命中各自 GeoSite，baidu/taobao 仍直连
- ⚠️ 广告表难免有误杀（某些 App 的统计/推送域名会被拦）。真遇到 App 异常，
  把 `🛑 广告拦截` 切成 `DIRECT` 验证一下是不是它干的；确认误杀就把该域名加 `- DOMAIN-SUFFIX,xxx,🎯 全球直连`（放在广告规则之前）

## 五、常见问题

**首启规则集报 `initial rule provider ... error` / `EOF`**
规则集和 GeoData 要联网拉取，而拉取请求会**按规则走代理**。如果此刻还没有可用节点，
首次会拉失败——节点测速出结果后会自动重试（间隔 3 小时），或重启一次内核即可。
也可以在本地 `rule_provider/`、`geo*` 缓存就绪后再启动代理。

**某家机场的节点没出现在地区组里**
地区组靠节点名里的关键词匹配（`香港|HK|HongKong`、`美国|US|United States`…）。
机场给节点起名太随意（纯数字、`Node1` 这种）就匹配不到。办法：给该 provider 打开
`override.additional-prefix`，或在 `filter:` 里按你看到的实际命名补关键词。

**多个机场有同名节点**
mihomo 的 provider 是**按 provider 隔离**的，同名不会互相覆盖；但 UI 上不易分辨，
打开 `override.additional-prefix: "[A] "` 就会带上来源前缀。

**想让订阅自动更新**
`interval: 3600` 控制拉取间隔（已经是自动的）。机场限速严就调大到 7200。
用 `render.py` 的话，重新跑一次脚本即可；直接改 `config.yaml` 的话改完记得重载配置。

**流媒体/AI 解锁**
配置里 YouTube/Netflix/Disney+/HBO/ChatGPT 等各有独立分组，选一个解锁该服务的地区节点即可
（一般新加坡/日本/美国原生 IP）。`♻️ 自动选择` 只看延迟，**不判断解锁能力**。

## 六、把它变成一条订阅链接（可选，多设备自动更新）

想让手机/电视盒子都只填一个 URL、以后自动更新，把渲染出的 `dist/config.yaml` 放到任何能 HTTP 取到的地方即可：

- **自建静态托管**（推荐）：丢到自己的 nginx / 网盘容器 / 任意 web 目录，得到一个 URL；
  建议 URL 带一段随机串（`/sub/<乱码>/config.yaml`），别裸奔在公网目录里。
- **私有仓库**：渲染产物推到私有仓库，用 raw 链接——注意私有仓库的 raw 需要 token，多数客户端不方便。
- **GitHub Actions 自动渲染**：把 `airports.yaml` 存成仓库 Secret，用一个 workflow 定时渲染并推到私有仓库/Gist。
  需要的话可以按这个思路加，模板仓库本身永远不落凭证。

> 公开仓库里的 `config.yaml` 永远只有占位符；凭证要么在你本地，要么在你自己的私有托管里。

## 七、安全

- 仓库里**没有任何真实订阅链接**。`airports.yaml`、`dist/`、`bin/`、`proxy_provider/` 都在 `.gitignore`
- 订阅链接 = 账号凭证，泄露等于把流量送人；要分享配置请只分享 `config.yaml` 模板
- `external-controller: 0.0.0.0:9090` 是无鉴权的控制接口，建议改为 `127.0.0.1:9090` 并配 `secret`

## 八、致谢

规则与模板结构参考并受益于这些项目：

- [Aethersailor/Custom_OpenClash_Rules](https://github.com/Aethersailor/Custom_OpenClash_Rules) —— 分流规则、策略组结构
- [MetaCubeX/mihomo](https://github.com/MetaCubeX/mihomo) —— 内核与文档
- [Loyalsoldier/v2ray-rules-dat](https://github.com/Loyalsoldier/v2ray-rules-dat) —— GeoIP/GeoSite 数据
