# ipatool 网页一键脚本：输入 App 名字，ipa 直接下到你的电脑

在 VPS 上装一个小网页。浏览器打开，输入 App 名字（也可以粘 App Store 链接或 Bundle ID），点「下载 IPA」。VPS 用 [ipatool](https://github.com/majd/ipatool) 以你的 Apple ID 从 App Store 下好，再自动保存到你正在用的电脑。也能下历史版本。

全程一问一答：自动认出系统、架构、**小鸡还是母鸡**、是不是 NAT，缺什么装什么，端口、密码、地区都会先问你。64MB 的 KVM 小鸡加上虚拟内存也能用。

可以存好几个不同地区的 Apple ID，在 VPS 终端输入 `qiequ` 就能**切区**。

## 安装（用 root 运行，一行）

```sh
sh -c 'c(){ command -v "$1" >/dev/null 2>&1; }; c curl || c wget || { for pm in "apk add --no-cache" "apt-get install -y" "dnf install -y" "yum install -y" "pacman -Sy --noconfirm" "zypper --non-interactive install"; do b=${pm%% *}; c $b || continue; [ "$b" = apt-get ] && apt-get update -qq 2>/dev/null; $pm curl ca-certificates 2>/dev/null; break; done; c curl || c wget || { echo "装不上 curl / wget，请手动装一个"; exit 1; }; }; ok=""; for u in https://raw.githubusercontent.com/imthnio/vps-ipatool/main/install.sh https://cdn.jsdelivr.net/gh/imthnio/vps-ipatool@main/install.sh; do (wget -qO /tmp/ipa-web-install.sh "$u" || curl -fsSL -o /tmp/ipa-web-install.sh "$u") 2>/dev/null && [ -s /tmp/ipa-web-install.sh ] && head -n 1 /tmp/ipa-web-install.sh | grep -q "^#!/bin/sh" && grep -q ipaweb-onekey-begin /tmp/ipa-web-install.sh && { ok=1; break; }; rm -f /tmp/ipa-web-install.sh; done; [ -n "$ok" ] || { echo "下载 install.sh 失败，请检查网络"; exit 1; }; sh /tmp/ipa-web-install.sh'
```

装好以后直接运行 `ipa-web` 打开管理菜单。

## 安装时会问什么

| 问题 | 说明 |
| --- | --- |
| 网页端口 | 默认随机一个没人用的高位端口。NAT 小鸡会先问商家映射给你的**外网端口**，再问对应的内网端口 |
| HTTPS | 有公网 IP 且 80/443 空着时才问。填一个解析到 VPS 的域名，自动申请证书（Caddy） |
| 网页密码 | 打开网页要输的密码，回车就随机生成 |
| App Store 地区 | 要和 Apple ID 的地区一致，例如 `cn`、`us`、`hk`、`jp` |
| 文件保留时间 | 下好的 ipa 在 VPS 上放多久自动删除，默认 60 分钟 |
| 同时下载数 | 按内存给默认值，多出来的排队 |
| 虚拟内存 | 内存小时才问，见下面 |
| Apple ID | 邮箱、密码、双重认证的 6 位验证码。密码不落盘，登录凭证加密保存在 VPS。以后可以用 `qiequ` 再加别的地区的账号 |

## 自动识别

- **系统**：Debian / Ubuntu / CentOS / Rocky / Alma / Fedora / Alpine / Arch / openSUSE；x86_64、arm64
- **小鸡 / 母鸡**：
  - 容器小鸡（LXC、OpenVZ、Docker、Podman）
  - 虚拟机小鸡（KVM、VMware、Hyper-V、Xen、各家云）
  - 母鸡：物理机 / 独立服务器；装了 PVE、libvirt、LXC/Incus 等正在开小鸡的也算母鸡，装之前会先确认
- **NAT**：本机是内网 IP 就按 NAT 小鸡处理，网址显示外网映射端口
- **启动方式**：systemd、OpenRC（Alpine），都没有就用 cron 保活
- **musl 系统**（Alpine）：自动装 glibc 兼容层，ipatool 才能跑
- **国内机器**：连不上 GitHub 时自动走加速镜像，也可以自己指定：`IPAWEB_GH_PROXY=https://你的镜像/ sh install.sh`

## 小内存（64MB）

ipatool 登录 Apple ID 时实测峰值约 110~180MB（第一次登录要先下载苹果的组件，更多），网页本身约 20MB。

- **KVM / Xen 等虚拟机小鸡**：内存加虚拟内存不到 640MB 时，脚本会建议加一块虚拟内存（按硬盘大小 256MB~1GB），并且**先加虚拟内存再装软件**。64MB 的 KVM 这样就能用。
- **登录时腾内存**：内存小于 256MB 时，登录前会暂停网页服务、清缓存，并收紧 ipatool 的内存回收，登录完自动恢复。
- **同时下载数**：小内存默认 1 个，其余排队。
- **容器小鸡（LXC / OpenVZ）**：自己加不了虚拟内存。内存加虚拟内存不到 200MB 时，脚本会提前说明大概率登录不上，让你决定是否继续。

## 切区

在 VPS 终端输入 `qiequ`：

```
======== 切区 / Apple ID 账号 ========
  1) CN  xxx@icloud.com  ← 正在用
  2) HK  yyy@outlook.com
  3) US  zzz@gmail.com

  输入序号：切到那个账号（也可以输地区代码，例如 us）
  a) 添加账号（登录一个新的 Apple ID）
  r) 重新登录某个账号（网页提示登录过期时用）
  d) 删除某个账号
  0) 退出
```

也可以一步切到位：

```
qiequ us        切到美区账号（同一个地区存了好几个，就轮流切）
qiequ 2         切到第 2 个账号
qiequ list      看看存了哪些账号
```

- 切区不用重启网页，网页十几秒内自己变成新的地区（也可以手动刷新）。
- 已经在排队、在下载的任务，还是用下单时的那个账号下完，不会串号。
- 添加账号时要回答这个 Apple ID 是哪个地区的（ipatool 读不出来），地区不对会搜到下不了的 App。
- 每个账号的登录凭证分开存在 `/opt/ipa-web/accounts/` 下；苹果的组件缓存（约 60MB）所有账号共用一份，小鸡硬盘也够用。

## 管理

```
ipa-web                    管理菜单
ipa-web --status           状态、网址
ipa-web --login            重新登录正在用的 Apple ID（登录过期时用）
qiequ                      切区：切换 / 添加 / 删除 Apple ID 账号
ipa-web --reset-password   换网页密码
ipa-web --settings         改端口、地区、保留时间、同时下载数
ipa-web --log              运行日志
ipa-web --upgrade          更新脚本和 ipatool
ipa-web --uninstall        卸载
```

## 网页能做什么

- 按名字搜索，或者直接粘 App Store 链接、App ID、Bundle ID
- 免费 App 自动「领取」到你的 Apple ID 再下载；付费 App 需要这个账号买过
- 历史版本：列出版本编号，可以查具体版本号再下载
- 下载进度、排队；下好后自动保存到电脑，也可以手动点「保存到电脑」（支持断点续传）
- 网页密码登录，输错 8 次锁 10 分钟

## 常见问题

**下好的 ipa 能装到别人的手机上吗？**
不能。App Store 的 ipa 带苹果的 FairPlay 加密，只能装到登录同一个 Apple ID 的设备上（例如用爱思助手、Apple Configurator 安装）。

**提示「Apple ID 登录已过期」？**
在 VPS 上运行 `qiequ`，选 `r` 重新登录那个账号（或者 `ipa-web --login` 重新登录正在用的账号）。

**双重认证收不到验证码？**
登录时苹果会在你的 iPhone / iPad / Mac 上弹窗，要先点「允许」才显示验证码。点了「不允许」或者错过了，就重新登录一次。

**网页打不开？**
- 普通 VPS：检查云服务商的「安全组 / 防火墙」有没有放行端口。ufw、firewalld 脚本已经自动放行。
- NAT 小鸡：检查商家面板里外网端口有没有映射到安装时填的内网端口。

**安全吗？**
Apple ID 密码只在登录那一刻交给 ipatool，不写进任何文件。登录凭证用随机口令加密存在 `/opt/ipa-web/home`，配置文件只有 root 能读。建议用一个 Apple ID 小号。

## 赞赏支持

如果这个脚本帮到了你，欢迎请我喝杯咖啡。

![赞赏码](./appreciate.png)
