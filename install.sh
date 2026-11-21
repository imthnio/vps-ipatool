#!/bin/sh
#======================================================================
# ipatool 网页一键脚本：浏览器里搜 App，IPA / APK 直接下到你正在用的电脑
#----------------------------------------------------------------------
# 在 Linux VPS 上装好一个小网页。浏览器打开它：
#   - 苹果 iOS（IPA）：输入 App 名字（或粘 App Store 链接），VPS 用 ipatool
#     以你的 Apple ID 从 App Store 下好 IPA，再自动传到你的电脑。也能下历史版本。
#   - 安卓 Android（APK / XAPK / APKS）：不用登录任何账号，内置多源聚合引擎
#     （APKPure、Uptodown、Aptoide、华为应用市场、应用宝、Vivo 应用商店、F-Droid、
#     GitHub Releases）并配备 EFF 开源的 apkeep 下载引擎，支持搜名字、包名、
#     商店链接、GitHub 仓库或直链，多源自动回退，也能查历史版本。
#
# 全程一问一答：自动认出系统、架构、是小鸡还是母鸡、是不是 NAT，
# 缺什么装什么，端口、密码、地区都会先问你。
#
#   sh install.sh                    第一次：一问一答装好。装过：打开管理菜单
#   sh install.sh --status           看看装得怎么样、网址是什么
#   sh install.sh --login            重新登录正在用的 Apple ID（登录过期时用）
#   sh install.sh --reset-password   换一把网页密码
#   sh install.sh --settings         改端口、地区、保留时间、同时下载数、自动更新
#   sh install.sh --log              看最近的运行记录（排查问题用）
#   sh install.sh --upgrade          更新本脚本、ipatool 和 apkeep
#   sh install.sh --update-ipatool   只把 ipatool 和 apkeep 更新到最新版（网页每天也会自动检查）
#   sh install.sh --swap             按机器配置自动开虚拟内存（小内存机器登录被杀时用）
#   sh install.sh --uninstall        卸载
#   装好以后，以上命令都可以用 ipa-web 代替 sh install.sh，例如 ipa-web --status
#
# 切区（可以存好几个不同地区的 Apple ID，随时切换）
#   qiequ                            打开切区菜单：切换、添加、重新登录、删除账号
#   qiequ us                         直接切到美区账号（也可以写序号或邮箱，例如 qiequ 2）
#   qiequ list                       看看存了哪些账号
#
# 名词小词典
#   小鸡           从母鸡上切出来的虚拟机或容器（KVM、LXC、OpenVZ…），一般租到的 VPS 都是小鸡
#   母鸡           物理服务器本身（独立服务器），上面可以再开小鸡
#   NAT 小鸡       没有自己独立的公网 IP，只能用商家映射给你的几个端口
#   端口           网页地址里冒号后面的数字，例如 http://1.2.3.4:23456 里的 23456
#   ipatool        真正去 App Store 下 ipa 的程序（github.com/majd/ipatool）
#   apkeep         EFF 开源的安卓 APK 多源命令行下载器（github.com/EFForg/apkeep）
#   XAPK / APKS    安卓的分包安装包（含主 APK + 架构/语言分包或 OBB 数据包）
#   钥匙串         ipatool 把 Apple ID 登录凭证加密存在 VPS 上的地方
#   切区           换成另一个地区的 Apple ID。每个地区的 App Store 能下的 App 不一样
#   双重认证码     登录 Apple ID 时，你 iPhone / Mac 上弹出的 6 位数字
#   虚拟内存 swap  拿一块硬盘当内存用。慢，但小内存机器登录时不会被系统杀掉
#   HTTPS          加密的网址（https://），需要一个解析到 VPS 的域名
#======================================================================

VERSION=1.4.0
# ipaweb-onekey-begin

REPO=imthnio/vps-ipatool
BASE=/opt/ipa-web
CONF=$BASE/config.json
LOG=/var/log/ipa-web.log
CMD_LINK=/usr/local/bin/ipa-web
QIEQU_LINK=/usr/local/bin/qiequ
SVC=ipa-web
SVC_CADDY=ipa-web-caddy
# ipatool 最低版本：2.8.0 恢复了 App Store 登录（本地生成 Anisette）。
# 2.8.0 之前登录会在双重认证那步失败，苹果返回空响应 / HTTP 503。
IPATOOL_MIN=2.8.0
IPATOOL_FALLBACK=2.8.1
# 低内存机器（<=512MB）下载/查版本专用的轻量版 ipatool：
# 2.8.x 每次下载会同时开多个 Unicorn 模拟器实例，峰值 330~370MB 内存，256MB 小鸡必被 OOM 杀掉；
# 2.7.0 钥匙串与 2.8.x 完全兼容，下载/查版本仅需 ~50MB 内存。登录仍用新版 ipatool。
IPATOOL_LOWMEM_VER=2.7.0
APKEEP_FALLBACK=1.1.0
CADDY_FALLBACK=2.10.2

#----------------------------------------------------------------------
# 屏幕上的颜色和几种说话方式。终端不支持颜色时就不加颜色。
#----------------------------------------------------------------------
if [ -t 1 ]; then
  C_RED=$(printf '\033[0;31m')
  C_GREEN=$(printf '\033[0;32m')
  C_YELLOW=$(printf '\033[1;33m')
  C_BLUE=$(printf '\033[0;36m')
  C_BOLD=$(printf '\033[1m')
  C_NC=$(printf '\033[0m')
else
  C_RED=''
  C_GREEN=''
  C_YELLOW=''
  C_BLUE=''
  C_BOLD=''
  C_NC=''
fi

say_ok()   { printf '%s\n' "${C_GREEN}✓ $*${C_NC}"; }
say_info() { printf '%s\n' "${C_BLUE}$*${C_NC}"; }
say_warn() { printf '%s\n' "${C_YELLOW}! $*${C_NC}"; }
say_err()  { printf '%s\n' "${C_RED}✗ $*${C_NC}" >&2; }
say_step() { printf '\n%s\n' "${C_YELLOW}>>> $*${C_NC}"; }
die()      { say_err "$*"; exit 1; }
have()     { command -v "$1" >/dev/null 2>&1; }

#----------------------------------------------------------------------
# 一问一答。问题从 /dev/tty 读，所以 curl ... | sh 这样跑也能回答。
# 没有终端（比如放在别的脚本里跑）就全用默认值。
#----------------------------------------------------------------------
can_ask() {
  [ -z "${IPAWEB_YES:-}" ] || return 1
  (exec 2>/dev/null; exec </dev/tty)
}

# ask "问题" "默认值"   回答放在 ANSWER 里
ask() {
  ANSWER=
  if can_ask; then
    if [ -n "$2" ]; then
      printf '%s' "${C_BOLD}$1${C_NC} [回车 = $2]: " >/dev/tty
    else
      printf '%s' "${C_BOLD}$1${C_NC}: " >/dev/tty
    fi
    IFS= read -r ANSWER </dev/tty || ANSWER=
    ANSWER=$(printf '%s' "$ANSWER" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')
  fi
  [ -n "$ANSWER" ] || ANSWER=$2
}

# ask_yn "问题" y|n   回答是就返回 0
ask_yn() {
  if [ "$2" = y ]; then hint="Y/n"; else hint="y/N"; fi
  while :; do
    yn=
    if can_ask; then
      printf '%s' "${C_BOLD}$1${C_NC} [$hint]: " >/dev/tty
      IFS= read -r yn </dev/tty || yn=
    fi
    [ -n "$yn" ] || yn=$2
    case "$yn" in
      y|Y|yes|YES|是|好) return 0 ;;
      n|N|no|NO|否|不) return 1 ;;
    esac
    say_warn "请输入 y 或 n"
  done
}

# 输密码时不显示在屏幕上。Ctrl+C 中断也要把回显恢复。
ask_secret() {
  ANSWER=
  can_ask || return 1
  printf '%s' "${C_BOLD}$1${C_NC}: " >/dev/tty
  stty -echo 2>/dev/null </dev/tty
  IFS= read -r ANSWER </dev/tty || ANSWER=
  stty echo 2>/dev/null </dev/tty
  printf '\n' >/dev/tty
}

restore_tty() { stty echo 2>/dev/null </dev/tty || true; }

need_root() {
  [ "$(id -u)" = 0 ] || die "请用 root 运行（先 sudo -i 或 su -）"
}

# 同一时间只让一个本脚本在改东西。
# 菜单等用户选的时候不拿锁，只有真正改东西的那一步才拿，用完就放，
# 不然一个忘关的 qiequ 会一直挡住升级。
LOCK_DIR=/run/ipa-web-install.lock

proc_stat() {
  # proc_stat 进程号：输出 "状态 父进程"，例如 "S 123"。读不到就输出空。
  st=$(cat "/proc/$1/stat" 2>/dev/null) || return 1
  [ -n "$st" ] || return 1
  rest=${st##*) }
  state=${rest%% *}
  rest=${rest#* }
  printf '%s %s' "$state" "${rest%% *}"
}

kill_quietly() {
  # kill_quietly 进程号：先 TERM，等 3 秒，还活着就 KILL。僵尸不用等。
  kill "$1" 2>/dev/null || return 0
  i=0
  while [ $i -lt 3 ]; do
    kill -0 "$1" 2>/dev/null || return 0
    st=$(proc_stat "$1")
    [ "${st%% *}" = "Z" ] && return 0
    sleep 1
    i=$((i+1))
  done
  kill -9 "$1" 2>/dev/null || true
}

lock_take() {
  [ -d /run ] || LOCK_DIR=/tmp/ipa-web-install.lock
  if ! mkdir "$LOCK_DIR" 2>/dev/null; then
    old=$(cat "$LOCK_DIR/pid" 2>/dev/null)
    # 锁是自己（或者调用自己的上一层脚本）拿的，直接用。
    if [ "$old" = "$$" ] || [ "$old" = "${IPAWEB_LOCK_OWNER:-none}" ]; then
      return 0
    fi
    if [ -n "$old" ] && kill -0 "$old" 2>/dev/null; then
      # 拿锁的进程还在：先看看是不是死剩下的。
      st=$(proc_stat "$old")
      state=${st%% *}
      ppid=${st#* }
      if [ "$state" = "Z" ]; then
        # 僵尸：已经死了，只是没人收。kill -0 对僵尸也返回成功，
        # 不特殊处理就会一直以为它还活着。
        say_warn "拿锁的进程 $old 已经死了（僵尸进程），直接清理锁。"
        rm -rf "$LOCK_DIR"
      elif [ "$ppid" = "1" ]; then
        # 孤儿：启动它的终端已经没了，没人能再跟它说话，
        # 留着只会一直挡住别人。结束它，锁也一起清掉。
        say_warn "拿锁的进程 $old 的终端已经断了，结束它并清理锁。"
        kill_quietly "$old"
        rm -rf "$LOCK_DIR"
      else
        # 真有人在用：告诉用户它在干什么，让用户决定要不要结束它。
        cmd=$(tr '\0' ' ' < "/proc/$old/cmdline" 2>/dev/null)
        [ -n "$cmd" ] || cmd=$(ps -o args= -p "$old" 2>/dev/null)
        say_warn "另一个 ipa-web 脚本正在运行（进程 $old）。"
        [ -n "$cmd" ] && say_warn "它在跑：$cmd"
        if ask_yn "结束它并继续吗？（它正在做的事会被打断）" n; then
          kill_quietly "$old"
          rm -rf "$LOCK_DIR"
        else
          die "等它结束再来，或者先到那个终端里把它停掉。"
        fi
      fi
    else
      rm -rf "$LOCK_DIR"
    fi
    mkdir "$LOCK_DIR" 2>/dev/null || die "建不了锁目录 $LOCK_DIR"
  fi
  echo $$ > "$LOCK_DIR/pid"
  IPAWEB_LOCK_OWNER=$$
  export IPAWEB_LOCK_OWNER
  trap 'restore_tty; rm -rf "$LOCK_DIR"' EXIT
  trap 'restore_tty; rm -rf "$LOCK_DIR"; printf "\n"; exit 130' INT TERM
}

lock_release() {
  # 锁是自己拿的才放。放了以后退出时就不用再清一次，
  # 不然可能把别人刚拿的锁误删掉。
  [ "${IPAWEB_LOCK_OWNER:-}" = "$$" ] || return 0
  rm -rf "$LOCK_DIR"
  IPAWEB_LOCK_OWNER=
  export IPAWEB_LOCK_OWNER
  trap 'restore_tty' EXIT
  trap 'restore_tty; printf "\n"; exit 130' INT TERM
}

#----------------------------------------------------------------------
# 认出系统：发行版、装软件的方式、架构、C 库、启动方式、内存、硬盘。
#----------------------------------------------------------------------
read_meminfo_kb() {
  awk -v k="$1" '$1==k {print $2; exit}' /proc/meminfo 2>/dev/null
}

# 容器里的内存上限写在 cgroup 里，比 /proc/meminfo 准。
cgroup_mem_mb() {
  for cgf in /sys/fs/cgroup/memory.max /sys/fs/cgroup/memory/memory.limit_in_bytes; do
    [ -r "$cgf" ] || continue
    cgv=$(tr -d ' \r\n' < "$cgf" 2>/dev/null)
    case "$cgv" in ''|max|*[!0-9]*) continue ;; esac
    [ "${#cgv}" -le 13 ] || continue
    printf '%s' $((cgv / 1024 / 1024))
    return 0
  done
  return 1
}

# 容器里的虚拟内存上限也可能被 cgroup 限制，比 /proc/meminfo 的 SwapTotal 准。
cgroup_swap_mb() {
  if [ -r /sys/fs/cgroup/memory.swap.max ]; then
    cgv=$(tr -d ' \r\n' < /sys/fs/cgroup/memory.swap.max 2>/dev/null)
    case "$cgv" in
      ''|max|*[!0-9]*) ;;
      *)
        if [ "${#cgv}" -le 13 ]; then
          printf '%s' $((cgv / 1024 / 1024))
          return 0
        fi
        ;;
    esac
  fi
  return 1
}

disk_free_mb() {
  df -Pk "$1" 2>/dev/null | awk 'NR==2 {print int($4/1024)}'
}

detect_os() {
  OS_ID=unknown
  OS_PRETTY=Linux
  if [ -f /etc/os-release ]; then
    OS_ID=$(sed -n 's/^ID=//p' /etc/os-release | tr -d '"' | head -n 1)
    OS_PRETTY=$(sed -n 's/^PRETTY_NAME=//p' /etc/os-release | tr -d '"' | head -n 1)
  fi
  [ -n "$OS_PRETTY" ] || OS_PRETTY=$OS_ID
  PM=none
  for p in apt-get apk dnf yum zypper pacman; do
    if have $p; then PM=$p; break; fi
  done
  case "$(uname -m)" in
    x86_64|amd64) ARCH=amd64 ;;
    aarch64|arm64) ARCH=arm64 ;;
    *) ARCH=$(uname -m) ;;
  esac
  LIBC=glibc
  if ls /lib/ld-musl-* >/dev/null 2>&1; then LIBC=musl; fi
  if [ -d /run/systemd/system ] && have systemctl; then
    INIT=systemd
  elif [ -d /run/openrc ] && have rc-service; then
    INIT=openrc
  else
    INIT=other
  fi
  KERNEL=$(uname -r)
  MEM_MB=$(( $(read_meminfo_kb MemTotal:) / 1024 ))
  cg=$(cgroup_mem_mb 2>/dev/null || true)
  MEM_LIMIT_FROM=
  if [ -n "$cg" ] && [ "$cg" -lt "$MEM_MB" ]; then
    MEM_MB=$cg
    MEM_LIMIT_FROM=cgroup
  fi
  # 测试时可以假装成小内存机器，例如 IPAWEB_MEM_MB=64 sh install.sh
  if [ -n "${IPAWEB_MEM_MB:-}" ]; then MEM_MB=$IPAWEB_MEM_MB; fi
  SWAP_MB=$(( $(read_meminfo_kb SwapTotal:) / 1024 ))
  cgsw=$(cgroup_swap_mb 2>/dev/null || true)
  if [ -n "$cgsw" ] && [ "$cgsw" -lt "$SWAP_MB" ]; then
    SWAP_MB=$cgsw
  fi
  DISK_MB=$(disk_free_mb /)
  [ -n "$DISK_MB" ] || DISK_MB=0
}

# 内核版本够不够新。ipatool 是 Go 写的，要 Linux 3.2 以上。
kernel_ok() {
  kmaj=$(printf '%s' "$KERNEL" | cut -d. -f1)
  kmin=$(printf '%s' "$KERNEL" | cut -d. -f2 | tr -cd '0-9')
  [ "${kmaj:-0}" -gt 3 ] || { [ "${kmaj:-0}" -eq 3 ] && [ "${kmin:-0}" -ge 2 ]; }
}

#----------------------------------------------------------------------
# 小鸡还是母鸡。
#   先看是不是容器（LXC、OpenVZ、Docker、Podman…），再看是不是虚拟机（KVM、VMware…）。
#   两样都不是，就是物理机 = 母鸡。物理机上装了 PVE、libvirt 这些开小鸡的软件，就是正在开小鸡的母鸡。
#----------------------------------------------------------------------
# 根目录是什么文件系统。Docker 一般是 overlay。
root_fstype() {
  awk '$5 == "/" { for (i = 6; i <= NF; i++) if ($i == "-") { print $(i + 1); exit } }' /proc/self/mountinfo 2>/dev/null
}

detect_virt() {
  ctn=
  vmn=
  if have systemd-detect-virt; then
    ctn=$(systemd-detect-virt -c 2>/dev/null || true)
    vmn=$(systemd-detect-virt -v 2>/dev/null || true)
    [ "$ctn" = none ] && ctn=
    [ "$vmn" = none ] && vmn=
  fi
  if [ -z "$ctn" ]; then
    if [ -e /proc/user_beancounters ] && [ ! -d /proc/bc ]; then
      ctn=openvz
    elif [ -e /run/.containerenv ]; then
      ctn=podman
    elif [ -e /.dockerenv ]; then
      ctn=docker
    elif tr '\0' '\n' < /proc/1/environ 2>/dev/null | grep -q '^container=lxc' \
      || [ -e /dev/.lxc-boot-id ] || grep -q '/lxc' /proc/1/cgroup 2>/dev/null; then
      ctn=lxc
    elif tr '\0' '\n' < /proc/1/environ 2>/dev/null | grep -q '^container='; then
      ctn=$(tr '\0' '\n' < /proc/1/environ | sed -n 's/^container=//p' | head -n 1)
    elif grep -qE '/(docker|kubepods|containerd)' /proc/1/cgroup 2>/dev/null; then
      ctn=docker
    elif [ -s /run/systemd/container ]; then
      ctn=$(head -n 1 /run/systemd/container)
    elif [ "$(root_fstype)" = overlay ] || [ "$(root_fstype)" = aufs ]; then
      ctn=docker
    elif [ -e /sys/fs/cgroup/memory.max ] && [ -e /sys/fs/cgroup/cgroup.controllers ]; then
      # cgroup v2 的根目录没有 memory.max；看得到它，说明这台机器被关在别人的 cgroup 里，就是容器。
      ctn=容器
    elif [ -e /proc/vz ] && [ ! -d /proc/bc ]; then
      ctn=openvz
    fi
  fi
  if [ -z "$vmn" ]; then
    dmi=$(cat /sys/class/dmi/id/sys_vendor /sys/class/dmi/id/product_name /sys/class/dmi/id/bios_vendor 2>/dev/null | tr '\n' ' ')
    case "$dmi" in
      *QEMU*|*KVM*|*Bochs*|*OpenStack*|*SeaBIOS*) vmn=kvm ;;
      *VMware*) vmn=vmware ;;
      *VirtualBox*|*innotek*) vmn=virtualbox ;;
      *Microsoft*) vmn=hyper-v ;;
      *Xen*) vmn=xen ;;
      *Amazon*EC2*) vmn=amazon ;;
      *Google*) vmn=google ;;
      *Alibaba*) vmn=alibaba ;;
      *Tencent*) vmn=tencent ;;
      *Parallels*) vmn=parallels ;;
      *DigitalOcean*|*Vultr*|*Linode*|*Akamai*|*Hetzner*) vmn=kvm ;;
    esac
    if [ -z "$vmn" ] && [ -r /sys/hypervisor/type ]; then
      vmn=$(cat /sys/hypervisor/type 2>/dev/null)
    fi
    if [ -z "$vmn" ] && grep -qw hypervisor /proc/cpuinfo 2>/dev/null; then
      vmn=虚拟机
    fi
  fi

  # 这台机器自己在开小鸡吗（容器里不算）。
  HOST_SOFT=
  if [ -z "$ctn" ]; then
    if [ -d /etc/pve ] || have pveversion; then
      HOST_SOFT="Proxmox VE"
    elif [ -d /proc/bc ] || have vzctl || have prlctl; then
      HOST_SOFT="OpenVZ / Virtuozzo"
    elif have virsh || have libvirtd; then
      HOST_SOFT="libvirt / KVM"
    elif have incus || have lxd || have lxc-ls; then
      HOST_SOFT="LXC / Incus"
    elif have xl; then
      HOST_SOFT="Xen"
    elif have VBoxManage; then
      HOST_SOFT="VirtualBox"
    fi
  fi

  VT_X=no
  if grep -qwE 'vmx|svm' /proc/cpuinfo 2>/dev/null; then VT_X=yes; fi

  if [ -n "$ctn" ]; then
    ROLE=小鸡
    VIRT_KIND=container
    VIRT_DESC="容器 $ctn"
    [ -n "$vmn" ] && VIRT_DESC="$VIRT_DESC（外面套着 $vmn 虚拟机）"
  elif [ -n "$HOST_SOFT" ]; then
    ROLE=母鸡
    VIRT_KIND=host
    VIRT_DESC="装了 $HOST_SOFT，正在开小鸡"
    [ -n "$vmn" ] && VIRT_DESC="$VIRT_DESC（它自己也是 $vmn 虚拟机，嵌套虚拟化）"
  elif [ -n "$vmn" ]; then
    ROLE=小鸡
    VIRT_KIND=vm
    VIRT_DESC="虚拟机 $vmn"
  else
    ROLE=母鸡
    VIRT_KIND=metal
    VIRT_DESC="物理机 / 独立服务器"
    [ "$VT_X" = yes ] && VIRT_DESC="$VIRT_DESC，CPU 支持虚拟化，可以开小鸡"
  fi
}

#----------------------------------------------------------------------
# 网络：本机 IP、公网 IP、是不是 NAT。
#----------------------------------------------------------------------
fetch_text() {
  if have curl; then
    curl -fsSL -m "${2:-8}" "$1" 2>/dev/null
  else
    wget -qO- -T "${2:-8}" "$1" 2>/dev/null
  fi
}

fetch_file() {
  # fetch_file URL 存到哪
  if have curl; then
    curl -fL --retry 2 --connect-timeout 10 -m 600 -o "$2" "$1" 2>/dev/null
  else
    wget -q -T 30 -O "$2" "$1" 2>/dev/null
  fi
}

is_ipv4() {
  printf '%s' "$1" | grep -qE '^[0-9]{1,3}(\.[0-9]{1,3}){3}$'
}

is_private_v4() {
  case "$1" in
    10.*|192.168.*|127.*|169.254.*) return 0 ;;
    172.1[6-9].*|172.2[0-9].*|172.3[01].*) return 0 ;;
    100.6[4-9].*|100.[7-9][0-9].*|100.1[01][0-9].*|100.12[0-7].*) return 0 ;;
  esac
  return 1
}

local_ipv4() {
  if have ip; then
    ip -4 route get 1.1.1.1 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="src"){print $(i+1); exit}}'
    return
  fi
  hostname -i 2>/dev/null | tr ' ' '\n' | grep -E '^[0-9.]+$' | grep -v '^127\.' | head -n 1
}

public_ip() {
  # public_ip 4|6
  for u in https://api.ipify.org https://ip.sb https://ifconfig.me/ip https://4.ipw.cn; do
    if [ "$1" = 6 ]; then
      case "$u" in *ipify*) u=https://api6.ipify.org ;; *ipw*) u=https://6.ipw.cn ;; esac
    fi
    if have curl; then
      got=$(curl "-$1" -fsS -m 6 "$u" 2>/dev/null | tr -d ' \r\n')
    else
      got=$(wget "-$1" -qO- -T 6 "$u" 2>/dev/null | tr -d ' \r\n')
    fi
    if [ "$1" = 4 ] && is_ipv4 "$got"; then printf '%s' "$got"; return 0; fi
    if [ "$1" = 6 ] && printf '%s' "$got" | grep -qE '^[0-9a-fA-F:]+$' && printf '%s' "$got" | grep -q ':'; then
      printf '%s' "$got"
      return 0
    fi
  done
  return 1
}

detect_net() {
  LOCAL4=$(local_ipv4)
  PUB4=$(public_ip 4 || true)
  PUB6=
  # /proc 里的文件大小总是 0，不能用 -s 判断，要看内容。
  if grep -qv ' lo$' /proc/net/if_inet6 2>/dev/null; then
    PUB6=$(public_ip 6 || true)
  fi
  NAT=0
  if [ -n "$PUB4" ] && [ -n "$LOCAL4" ] && [ "$LOCAL4" != "$PUB4" ] && is_private_v4 "$LOCAL4"; then
    NAT=1
  fi
  HAS_V6=0
  if grep -q . /proc/net/if_inet6 2>/dev/null; then HAS_V6=1; fi
}

#----------------------------------------------------------------------
# 端口：看有没有被占，被谁占。只读 /proc，不用装 ss / netstat。
#----------------------------------------------------------------------
port_inode() {
  hex=$(printf ':%04X' "$1")
  for f in /proc/net/tcp /proc/net/tcp6; do
    [ -r "$f" ] || continue
    awk -v h="$hex" 'NR>1 && $4=="0A" && substr($2, length($2)-4)==h {print $10; exit}' "$f"
  done | head -n 1
}

port_busy() {
  [ -n "$(port_inode "$1")" ]
}

port_owner() {
  ino=$(port_inode "$1")
  [ -n "$ino" ] || return 1
  for fd in /proc/[0-9]*/fd/*; do
    if [ "$(readlink "$fd" 2>/dev/null)" = "socket:[$ino]" ]; then
      pid=${fd#/proc/}
      pid=${pid%%/*}
      printf '%s(进程 %s)' "$(cat "/proc/$pid/comm" 2>/dev/null)" "$pid"
      return 0
    fi
  done
  printf '未知程序'
}

valid_port() {
  case "$1" in ''|*[!0-9]*) return 1 ;; esac
  [ "$1" -ge 1 ] && [ "$1" -le 65535 ]
}

random_free_port() {
  n=0
  while [ $n -lt 50 ]; do
    seed=$(( $$ + n * 7919 + $(date +%s) % 100000 ))
    p=$(awk -v s="$seed" 'BEGIN{srand(s); print int(20000 + rand() * 40000)}')
    if ! port_busy "$p"; then printf '%s' "$p"; return 0; fi
    n=$((n + 1))
  done
  printf '28090'
}

# ask_port "问题" "默认"  -> PORT_ANSWER。自己正在用的端口不算占用。
ask_port() {
  while :; do
    ask "$1" "$2"
    if ! valid_port "$ANSWER"; then
      can_ask || die "没有终端可以提问，端口又没有默认值"
      say_warn "端口是 1 到 65535 之间的数字"
      continue
    fi
    if [ "$ANSWER" -lt 1024 ] && [ "$ANSWER" != 80 ] && [ "$ANSWER" != 443 ]; then
      say_warn "1024 以下的端口一般留给系统服务，建议用 10000 以上的。"
      ask_yn "还是用 $ANSWER 吗？" n || continue
    fi
    if port_busy "$ANSWER" && [ "$ANSWER" != "${CUR_PORT:-}" ]; then
      say_warn "端口 $ANSWER 已经被 $(port_owner "$ANSWER") 占用了，换一个"
      if can_ask; then continue; fi
      die "端口 $ANSWER 被占用"
    fi
    PORT_ANSWER=$ANSWER
    return 0
  done
}

#----------------------------------------------------------------------
# 缺什么装什么。
#----------------------------------------------------------------------
pm_install() {
  case "$PM" in
    apt-get)
      if [ -z "${APT_UPDATED:-}" ]; then
        DEBIAN_FRONTEND=noninteractive apt-get update -qq >/dev/null 2>&1 || true
        APT_UPDATED=1
      fi
      DEBIAN_FRONTEND=noninteractive apt-get install -y -qq "$@" >/dev/null 2>&1
      ;;
    apk) apk add --no-cache "$@" >/dev/null 2>&1 ;;
    dnf) dnf install -y -q "$@" >/dev/null 2>&1 ;;
    yum) yum install -y -q "$@" >/dev/null 2>&1 ;;
    zypper) zypper --non-interactive install "$@" >/dev/null 2>&1 ;;
    pacman) pacman -Sy --noconfirm --needed "$@" >/dev/null 2>&1 ;;
    *) return 1 ;;
  esac
}

ensure_basic_tools() {
  if ! have curl && ! have wget; then
    say_info "安装 curl…"
    pm_install curl ca-certificates || die "装不上 curl，请手动装好 curl 再运行"
  fi
  if [ ! -f /etc/ssl/certs/ca-certificates.crt ] && [ ! -f /etc/ssl/cert.pem ] && [ ! -f /etc/pki/tls/certs/ca-bundle.crt ]; then
    pm_install ca-certificates || true
  fi
}

python_ok() {
  have python3 && python3 -c 'import sys, ssl, hashlib, json; sys.exit(0 if sys.version_info >= (3, 6) else 1)' 2>/dev/null
}

install_deps() {
  say_step "安装需要的软件"
  if ! python_ok; then
    say_info "安装 Python 3…"
    case "$PM" in
      apk) pm_install python3 ;;
      pacman) pm_install python ;;
      *) pm_install python3 ;;
    esac
    python_ok || die "装不上 Python 3.6 以上版本，请手动装好 python3 再运行"
  fi
  say_ok "Python $(python3 -c 'import platform; print(platform.python_version())')"
  have tar || pm_install tar || die "缺少 tar"
  have gzip || pm_install gzip || die "缺少 gzip"
  # ipatool 官方程序是按 glibc 编译的，Alpine 这类 musl 系统要装兼容层。
  if [ "$LIBC" = musl ]; then
    if [ "$PM" = apk ]; then
      pm_install gcompat || pm_install libc6-compat || true
    fi
  fi
  have sha256sum || pm_install coreutils || true
  say_ok "软件都齐了"
}

#----------------------------------------------------------------------
# 小内存机器：登录 Apple ID 时 ipatool 要 100 多 MB 内存，不够就加一块虚拟内存。
# 容器小鸡（LXC、OpenVZ、Docker）自己加不了，只能提醒。
#----------------------------------------------------------------------
SWAP_FILE=/ipa-web.swap
# 内存加虚拟内存凑到这么多，ipatool 第一次登录（要先下苹果的组件）也不会被杀。
SWAP_TARGET_MB=1024
# 少于这么多就不值得加了。
SWAP_MIN_MB=128
# 加完以后硬盘至少还要剩这么多，给下载 ipa 用。
DISK_KEEP_MB=768
# 内存加虚拟内存低于这个数，登录基本必挂，硬盘紧也要挤一块出来。
SWAP_CRITICAL_MB=320

# ipatool 登录时实测要 110~180MB（第一次更多），内存加虚拟内存不到 640MB 就建议加。
need_swap() {
  [ $((MEM_MB + SWAP_MB)) -lt 640 ]
}

# 按这台机器的内存、已有虚拟内存、硬盘剩余算出要加多少 MB。0 表示不用加或者加不了。
#   IPAWEB_SWAP_MB=512 指定大小，IPAWEB_SWAP_MB=0 不加。
swap_plan_mb() {
  if [ -n "${IPAWEB_SWAP_MB:-}" ]; then
    case "$IPAWEB_SWAP_MB" in *[!0-9]*) echo 0 ;; *) echo "$IPAWEB_SWAP_MB" ;; esac
    return
  fi
  [ "$VIRT_KIND" != container ] || { echo 0; return; }
  [ -z "${SWAP_DENIED:-}" ] || { echo 0; return; }
  need_swap || { echo 0; return; }
  sp_have=$((MEM_MB + SWAP_MB))
  sp_want=$((SWAP_TARGET_MB - sp_have))
  [ "$sp_want" -gt 0 ] || { echo 0; return; }
  sp_cap=$((DISK_MB - DISK_KEEP_MB))
  sp_third=$((DISK_MB / 3))
  if [ "$sp_have" -lt "$SWAP_CRITICAL_MB" ] && [ "$sp_third" -gt "$sp_cap" ]; then
    sp_cap=$sp_third
  fi
  [ "$sp_want" -le "$sp_cap" ] || sp_want=$sp_cap
  # 凑成 64MB 的整数倍
  sp_want=$((sp_want / 64 * 64))
  [ "$sp_want" -ge "$SWAP_MIN_MB" ] || sp_want=0
  echo "$sp_want"
}

# swap_probe：用 1MB 的小文件试一下系统让不让开虚拟内存。
#   不让（容器、或者商家禁了）就记下 SWAP_DENIED=1，并把这台机器当容器小鸡处理。
swap_probe() {
  [ -z "${SWAP_PROBED:-}" ] || return 0
  SWAP_PROBED=1
  SWAP_DENIED=
  [ "$VIRT_KIND" != container ] || { SWAP_DENIED=1; return 0; }
  # 已经开着我们的虚拟内存，说明允许。
  grep -q "^$SWAP_FILE" /proc/swaps 2>/dev/null && return 0
  if ! have swapon || ! have mkswap; then return 0; fi
  pf=$SWAP_FILE.probe
  rm -f "$pf"
  : > "$pf" && chmod 600 "$pf"
  chattr +C "$pf" 2>/dev/null || true
  dd if=/dev/zero of="$pf" bs=1M count=1 2>/dev/null
  if mkswap "$pf" >/dev/null 2>&1; then
    if perr=$(swapon "$pf" 2>&1); then
      swapoff "$pf" 2>/dev/null
      rm -f "$pf"
      return 0
    fi
    case "$perr" in
      *ermitted*|*EPERM*|*ermission*)
        SWAP_DENIED=1
        VIRT_KIND=container
        ROLE=小鸡
        VIRT_DESC="$VIRT_DESC（系统不让开虚拟内存，按容器小鸡处理）"
        ;;
    esac
  fi
  rm -f "$pf"
}

# 现在还能用的内存（MB）。容器按 cgroup 的上限减去已用的算。
mem_avail_mb() {
  ma=$(( $(read_meminfo_kb MemAvailable:) / 1024 ))
  if [ -r /sys/fs/cgroup/memory.max ] && [ -r /sys/fs/cgroup/memory.current ]; then
    cmax=$(cat /sys/fs/cgroup/memory.max 2>/dev/null)
    ccur=$(cat /sys/fs/cgroup/memory.current 2>/dev/null)
    case "$cmax$ccur" in
      *[!0-9]*|'') ;;
      *) cfree=$(( (cmax - ccur) / 1024 / 1024 )); [ "$cfree" -lt "$ma" ] && ma=$cfree ;;
    esac
  fi
  printf '%s' "$ma"
}

# 小内存：登录、下载时给 ipatool 限内存（Go 程序），网页服务也省着用。
# ipatool 下载时要在模拟器里跑苹果的框架，实测一个 40MB 的应用就要约 220MB
# 内存；256MB 的机器装了别的服务就很容易被 OOM 杀掉，所以 512MB 及以下都按
# 小内存处理（以前只认 256MB 以下，256MB 的机器会被漏掉）。
LOW_MEM_MB=512
low_mem() {
  [ "${MEM_MB:-1024}" -le "$LOW_MEM_MB" ]
}

drop_page_cache() {
  sync
  { echo 3 > /proc/sys/vm/drop_caches; } 2>/dev/null || true
}

# 已经有 /ipa-web.swap 就用 /ipa-web.swap.2、.3…，不去动正在用的那块（小内存机器 swapoff 可能腾不出地方）。
next_swap_file() {
  nf=$SWAP_FILE
  n=1
  while [ -e "$nf" ]; do
    n=$((n + 1))
    nf=$SWAP_FILE.$n
  done
  printf '%s' "$nf"
}

# 装过的所有虚拟内存文件
swap_files() {
  for f in "$SWAP_FILE" "$SWAP_FILE".*; do
    [ -f "$f" ] && printf '%s\n' "$f"
  done
}

# swap_file_try 文件 大小 方式：用 fallocate 或 dd 做好并打开。
swap_file_try() {
  rm -f "$1"
  : > "$1" || return 1
  chmod 600 "$1"
  # Btrfs 上的虚拟内存文件必须关掉写时复制，别的文件系统这句会失败，不要紧。
  chattr +C "$1" 2>/dev/null || true
  if [ "$3" = fallocate ]; then
    have fallocate && fallocate -l "${2}M" "$1" 2>/dev/null || { rm -f "$1"; return 1; }
  else
    dd if=/dev/zero of="$1" bs=1M count="$2" 2>/dev/null || { rm -f "$1"; return 1; }
  fi
  if mkswap "$1" >/dev/null 2>&1 && swapon "$1" 2>/dev/null; then
    return 0
  fi
  rm -f "$1"
  return 1
}

# 硬盘不够或者文件做的虚拟内存开不了时，试试 zram（在内存里压缩，64MB 的机器大概能多出一倍）。
ZRAM_FLAG=$BASE/zram
zram_on() {
  [ -b /dev/zram0 ] || modprobe zram num_devices=1 2>/dev/null || return 1
  [ -b /dev/zram0 ] || return 1
  grep -q '^/dev/zram0 ' /proc/swaps 2>/dev/null && return 0
  echo 1 > /sys/block/zram0/reset 2>/dev/null
  for alg in lz4 lzo-rle lzo zstd; do
    echo "$alg" > /sys/block/zram0/comp_algorithm 2>/dev/null && break
  done
  echo "${1}M" > /sys/block/zram0/disksize 2>/dev/null || return 1
  mkswap /dev/zram0 >/dev/null 2>&1 && swapon -p 100 /dev/zram0 2>/dev/null
}

# make_swap 大小：加一块虚拟内存。成功返回 0。
make_swap() {
  sf=$(next_swap_file)
  say_info "做一块 ${1}MB 的虚拟内存 $sf …"
  if swap_file_try "$sf" "$1" fallocate || swap_file_try "$sf" "$1" dd; then
    grep -q "^$sf " /etc/fstab 2>/dev/null || echo "$sf none swap sw 0 0" >> /etc/fstab
    # Alpine（OpenRC）要打开 swap 服务，开机才会读 fstab 里的虚拟内存。
    [ "$INIT" = openrc ] && rc-update add swap boot >/dev/null 2>&1
    SWAP_MB=$((SWAP_MB + $1))
    say_ok "虚拟内存开好了（现在共 ${SWAP_MB}MB），重启后也会自动开"
    return 0
  fi
  say_warn "硬盘做的虚拟内存开不了"
  return 1
}

# make_zram：硬盘那条路走不通时的后备，大小是内存的 2 倍。
make_zram() {
  zs=$((MEM_MB * 2))
  [ "$zs" -ge 64 ] || zs=64
  say_info "改用 zram（在内存里压缩出 ${zs}MB 虚拟内存）…"
  if zram_on "$zs"; then
    mkdir -p "$BASE" && printf '%s\n' "$zs" > "$ZRAM_FLAG"
    SWAP_MB=$((SWAP_MB + zs))
    say_ok "zram 开好了，网页服务启动时会自动再开"
    return 0
  fi
  say_warn "这台机器也开不了 zram"
  return 1
}

# 已经开着的虚拟内存够不够、要不要加，打印一句给人看。
swap_report() {
  sr_plan=$(swap_plan_mb)
  if [ "$VIRT_KIND" = container ]; then
    say_info "容器小鸡（${VIRT_DESC}）自己加不了虚拟内存，现在内存 ${MEM_MB}MB + 虚拟内存 ${SWAP_MB}MB。"
  elif [ "$sr_plan" -gt 0 ]; then
    say_info "内存 ${MEM_MB}MB + 虚拟内存 ${SWAP_MB}MB，硬盘剩 ${DISK_MB}MB：自动加 ${sr_plan}MB 虚拟内存。"
  elif need_swap; then
    say_info "内存 ${MEM_MB}MB + 虚拟内存 ${SWAP_MB}MB，硬盘剩 ${DISK_MB}MB：硬盘不够做虚拟内存，会试试 zram。"
  else
    say_ok "内存 ${MEM_MB}MB + 虚拟内存 ${SWAP_MB}MB，够用了"
  fi
}

# auto_swap：按机器配置自动开虚拟内存，不用回答问题。够用返回 0，开不出来返回 1。
auto_swap() {
  [ -n "${MEM_MB:-}" ] || detect_os
  [ -n "${VIRT_KIND:-}" ] || detect_virt
  swap_probe
  [ "${IPAWEB_SWAP_MB:-}" != 0 ] || return 0
  # zram 重启后就没了，标记过的再开一次。
  if [ -f "$ZRAM_FLAG" ] && ! grep -q '^/dev/zram0 ' /proc/swaps 2>/dev/null; then
    zram_on "$(cat "$ZRAM_FLAG")" && SWAP_MB=$(( $(read_meminfo_kb SwapTotal:) / 1024 ))
  fi
  as_plan=$(swap_plan_mb)
  if [ "$as_plan" -gt 0 ]; then
    make_swap "$as_plan" && return 0
  fi
  need_swap || return 0
  [ "$VIRT_KIND" != container ] || return 1
  grep -q '^/dev/zram0 ' /proc/swaps 2>/dev/null && return 0
  make_zram
}

# 登录被系统杀掉以后：再挤一块虚拟内存出来。加上了返回 0，可以马上重试。
grow_swap_after_oom() {
  [ -n "${VIRT_KIND:-}" ] || detect_virt
  swap_probe
  [ "$VIRT_KIND" != container ] || return 1
  [ "${IPAWEB_SWAP_MB:-}" != 0 ] || return 1
  DISK_MB=$(disk_free_mb /)
  SWAP_MB=$(( $(read_meminfo_kb SwapTotal:) / 1024 ))
  # 目标翻倍，硬盘够就再加一块；不够就试 zram。
  go_old=$SWAP_TARGET_MB
  SWAP_TARGET_MB=$((MEM_MB + SWAP_MB + 512))
  go_plan=$(swap_plan_mb)
  SWAP_TARGET_MB=$go_old
  if [ "$go_plan" -gt 0 ] && make_swap "$go_plan"; then return 0; fi
  [ -z "${SWAP_DENIED:-}" ] || return 1
  grep -q '^/dev/zram0 ' /proc/swaps 2>/dev/null && return 1
  make_zram
}

# 卸载时删掉加过的虚拟内存
remove_swap() {
  swap_files | while IFS= read -r f; do
    swapoff "$f" 2>/dev/null
    rm -f "$f"
    sed -i "\#^$f #d" /etc/fstab 2>/dev/null
  done
  if [ -f "$ZRAM_FLAG" ]; then
    swapoff /dev/zram0 2>/dev/null
    echo 1 > /sys/block/zram0/reset 2>/dev/null
  fi
}

#----------------------------------------------------------------------
# 从 GitHub 下东西。国内机器连不上 GitHub 时，自动换加速镜像。
#----------------------------------------------------------------------
GH_PROXIES="${IPAWEB_GH_PROXY:-} https://ghfast.top/ https://gh-proxy.com/"

gh_download() {
  # gh_download https://github.com/... 存到哪
  if fetch_file "$1" "$2" && [ -s "$2" ]; then return 0; fi
  for px in $GH_PROXIES; do
    [ -n "$px" ] || continue
    case "$px" in */) ;; *) px="$px/" ;; esac
    if fetch_file "$px$1" "$2" && [ -s "$2" ]; then return 0; fi
  done
  rm -f "$2"
  return 1
}

latest_tag() {
  # latest_tag owner/repo  -> 去掉 v 的版本号
  tag=$(fetch_text "https://api.github.com/repos/$1/releases/latest" 10 | sed -n 's/.*"tag_name": *"v\{0,1\}\([^"]*\)".*/\1/p' | head -n 1)
  if [ -z "$tag" ] && have curl; then
    tag=$(curl -fsSIL -m 10 -o /dev/null -w '%{url_effective}' "https://github.com/$1/releases/latest" 2>/dev/null | sed -n 's#.*/tag/v\{0,1\}##p')
  fi
  printf '%s' "$tag" | grep -E '^[0-9]+\.[0-9]+' | head -n 1
}

version_newer() {
  # version_newer A B：A 比 B 新就返回 0
  [ "$1" != "$2" ] || return 1
  top=$(printf '%s\n%s\n' "$1" "$2" | sort -t. -k1,1n -k2,2n -k3,3n | tail -n 1)
  [ "$top" = "$1" ]
}

ipatool_version() {
  "$BASE/bin/ipatool" --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -n 1
}

ipatool_dl_version() {
  "$BASE/bin/ipatool-dl" --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -n 1
}

apkeep_version() {
  "$BASE/bin/apkeep" --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -n 1
}

install_apkeep() {
  case "$ARCH" in
    amd64) ak_asset="apkeep-x86_64-unknown-linux-gnu" ;;
    arm64) ak_asset="apkeep-aarch64-unknown-linux-gnu" ;;
    *) return 0 ;;
  esac
  ak_ver=$(latest_tag EFForg/apkeep)
  [ -n "$ak_ver" ] || ak_ver=$APKEEP_FALLBACK
  have_ak=$(apkeep_version)
  if [ -n "$have_ak" ] && ! version_newer "$ak_ver" "$have_ak"; then
    say_ok "安卓下载引擎 apkeep $have_ak 已就绪"
    return 0
  fi
  mkdir -p "$BASE/bin" "$BASE/tmp"
  ak_tmp="$BASE/tmp/apkeep.new"
  ak_ok=
  for ak_url in \
    "https://github.com/EFForg/apkeep/releases/download/$ak_ver/$ak_asset" \
    "https://github.com/EFForg/apkeep/releases/download/v$ak_ver/$ak_asset"; do
    if gh_download "$ak_url" "$ak_tmp"; then
      chmod 755 "$ak_tmp"
      if "$ak_tmp" --version >/dev/null 2>&1; then
        mv -f "$ak_tmp" "$BASE/bin/apkeep"
        ak_ok=1
        break
      fi
    fi
    rm -f "$ak_tmp"
  done
  if [ -n "$ak_ok" ]; then
    say_ok "安卓下载引擎 apkeep $(apkeep_version) 装好了"
  else
    say_info "apkeep 未装上（将完全使用内置 Python 多源引擎下载 APK）"
  fi
}

# download_ipatool_bin 版本 目标路径：下载并校验指定版本的 ipatool 到目标路径。
download_ipatool_bin() {
  dl_ver=$1
  dl_dest=$2
  mkdir -p "$BASE/bin" "$BASE/tmp"
  dl_name="ipatool-$dl_ver-linux-$ARCH.tar.gz"
  dl_url="https://github.com/majd/ipatool/releases/download/v$dl_ver/$dl_name"
  dl_tgz="$BASE/tmp/$dl_name"
  say_info "下载 $dl_name …"
  gh_download "$dl_url" "$dl_tgz" || return 1
  if gh_download "$dl_url.sha256sum" "$dl_tgz.sha256" && have sha256sum; then
    want=$(awk '{print $1; exit}' "$dl_tgz.sha256")
    got=$(sha256sum "$dl_tgz" | awk '{print $1}')
    if [ "$want" != "$got" ]; then
      rm -f "$dl_tgz" "$dl_tgz.sha256"
      say_err "ipatool $dl_ver 下载不完整（校验不对）"
      return 1
    fi
    say_ok "文件校验通过"
  else
    say_warn "拿不到校验文件，跳过校验"
  fi
  rm -rf "$BASE/tmp/x"
  mkdir -p "$BASE/tmp/x"
  tar -xzf "$dl_tgz" -C "$BASE/tmp/x" || { rm -rf "$BASE/tmp/x" "$dl_tgz" "$dl_tgz.sha256"; return 1; }
  dl_bin=$(find "$BASE/tmp/x" -type f -name 'ipatool*' | head -n 1)
  [ -n "$dl_bin" ] || { rm -rf "$BASE/tmp/x" "$dl_tgz" "$dl_tgz.sha256"; return 1; }
  chmod 755 "$dl_bin"
  mv -f "$dl_bin" "$dl_dest"
  rm -rf "$BASE/tmp/x" "$dl_tgz" "$dl_tgz.sha256"
  "$dl_dest" --version >/dev/null 2>&1
}

install_ipatool_dl() {
  low_mem || return 0
  have_dl=$(ipatool_dl_version)
  if [ "$have_dl" = "$IPATOOL_LOWMEM_VER" ]; then
    say_ok "低内存下载引擎 ipatool-dl $have_dl 已就绪"
    return 0
  fi
  say_info "小内存机器（${MEM_MB}MB）：安装低内存下载引擎 ipatool $IPATOOL_LOWMEM_VER（下载仅占约 50MB 内存）…"
  if download_ipatool_bin "$IPATOOL_LOWMEM_VER" "$BASE/bin/ipatool-dl"; then
    say_ok "低内存下载引擎 ipatool-dl $(ipatool_dl_version) 装好了"
  else
    rm -f "$BASE/bin/ipatool-dl"
    say_warn "低内存下载引擎安装失败，将回退使用新版 ipatool（可稍后运行 ipa-web --upgrade 重试）"
  fi
}

install_ipatool() {
  say_step "安装 ipatool"
  case "$ARCH" in
    amd64|arm64) ;;
    *) die "ipatool 只支持 x86_64 和 arm64，这台是 $ARCH" ;;
  esac
  ver=$(latest_tag majd/ipatool)
  if [ -z "$ver" ]; then
    ver=$IPATOOL_FALLBACK
    say_warn "查不到 ipatool 最新版本，用 $ver"
  fi
  have_ver=$(ipatool_version)
  if [ -n "$have_ver" ] && ! version_newer "$ver" "$have_ver"; then
    say_ok "ipatool $have_ver 已经是最新"
  else
    if ! download_ipatool_bin "$ver" "$BASE/bin/ipatool"; then
      if [ "$LIBC" = musl ] && [ -x "$BASE/bin/ipatool" ]; then
        die "ipatool 跑不起来：这是 musl 系统，装 gcompat 兼容层失败了。试试手动 apk add gcompat"
      fi
      die "下载或安装 ipatool 失败。国内机器可以设置加速镜像再试：IPAWEB_GH_PROXY=https://你的镜像/ sh install.sh"
    fi
    say_ok "ipatool $(ipatool_version) 装好了"
  fi
  install_ipatool_dl
  install_apkeep
}

# 登录前检查 ipatool 版本：太旧时登录必定失败（苹果不接受旧的验证方式，
# 双重认证那步直接返回空响应 / HTTP 503），先升级再登录，免得白输密码和验证码。
ensure_ipatool_min_version() {
  have_ver=$(ipatool_version)
  [ -n "$have_ver" ] || return 0
  version_newer "$IPATOOL_MIN" "$have_ver" || return 0
  say_warn "ipatool $have_ver 太旧，苹果已经不接受它的登录方式了，先升级到新版再登录。"
  install_ipatool
}

#----------------------------------------------------------------------
# 配置文件 config.json：用 Python 读写，不怕密码里有特殊字符。
#----------------------------------------------------------------------
cfg_get() {
  [ -f "$CONF" ] && have python3 || return 1
  python3 - "$CONF" "$1" <<'PY' 2>/dev/null
import json, sys
c = json.load(open(sys.argv[1]))
v = c.get(sys.argv[2], "")
print(str(v).lower() if isinstance(v, bool) else v)
PY
}

# cfg_set 键 值 [键 值…]。纯数字存成数字，true/false 存成布尔。
cfg_set() {
  python3 - "$CONF" "$@" <<'PY'
import json, os, sys
path = sys.argv[1]
try:
    c = json.load(open(path))
except Exception:
    c = {}
args = sys.argv[2:]
for k, v in zip(args[::2], args[1::2]):
    if v.isdigit():
        v = int(v)
    elif v in ("true", "false"):
        v = v == "true"
    c[k] = v
tmp = path + ".tmp"
with open(tmp, "w") as f:
    json.dump(c, f, ensure_ascii=False, indent=2)
os.chmod(tmp, 0o600)
os.replace(tmp, path)
PY
}

# 网页密码只存摘要。明文从环境变量传进去，不出现在进程列表里。
set_web_password() {
  IPAWEB_PLAIN="$1" python3 - "$CONF" <<'PY'
import hashlib, json, os, secrets, sys
path = sys.argv[1]
c = json.load(open(path))
salt = secrets.token_hex(16)
it = 200000
h = hashlib.pbkdf2_hmac("sha256", os.environ["IPAWEB_PLAIN"].encode(), bytes.fromhex(salt), it).hex()
c["password_hash"] = "pbkdf2_sha256$%d$%s$%s" % (it, salt, h)
tmp = path + ".tmp"
with open(tmp, "w") as f:
    json.dump(c, f, ensure_ascii=False, indent=2)
os.chmod(tmp, 0o600)
os.replace(tmp, path)
PY
}

rand_text() {
  # 只用字母数字（去掉容易看错的 0 O 1 l I），至少带一个字母，免得被当成数字存。
  while :; do
    t=$(tr -dc 'A-HJ-NP-Za-km-z2-9' < /dev/urandom 2>/dev/null | head -c "$1")
    case "$t" in *[A-Za-z]*) printf '%s' "$t"; return 0 ;; esac
  done
}

#----------------------------------------------------------------------
# 网页程序本体（Python）和网页（HTML）。更新脚本时一起更新。
#----------------------------------------------------------------------
write_app_files() {
  mkdir -p "$BASE/app"
  cat > "$BASE/app/server.py" <<'IPAWEB_SERVER_PY_EOF'
#!/usr/bin/env python3
# -*- coding: utf-8 -*-
#======================================================================
# IPA / APK 网页下载器的后台程序：
#   - iOS (IPA)：浏览器里搜 App，VPS 用 ipatool 下好 ipa 再传到你的电脑。
#   - Android (APK / XAPK / APKS)：免登录，内置多源聚合引擎（APKPure、Uptodown、
#     Aptoide、华为应用市场、腾讯应用宝、Vivo 应用商店、F-Droid、GitHub Releases）
#     并可调用 apkeep 兜底，支持直链、包名、关键词与历史版本。
# 只用 Python 自带的库，不用装任何第三方 pip 包。
#
#   python3 server.py /opt/ipa-web/config.json
#======================================================================

import concurrent.futures
import gzip
import hashlib
import hmac
import json
import os
import platform
import random
import re
import secrets
import shutil
import signal
import socket
import subprocess
import sys
import tarfile
import threading
import time
import urllib.error
import urllib.parse
import urllib.request
import uuid
from http.server import BaseHTTPRequestHandler, HTTPServer
from socketserver import ThreadingMixIn

VERSION = "1.4.0"
HERE = os.path.dirname(os.path.abspath(__file__))
BASE_DIR = os.path.dirname(HERE)  # /opt/ipa-web
TMP_ROOT = os.path.join(BASE_DIR, "tmp")
CONFIG_PATH = sys.argv[1] if len(sys.argv) > 1 else os.path.join(HERE, "config.json")

#----------------------------------------------------------------------
# 读配置。安装脚本写好 config.json，这里只读不改。
#----------------------------------------------------------------------
DEFAULTS = {
    "listen_host": "0.0.0.0",
    "listen_port": 8090,
    "password_hash": "",
    "secret": "",
    "keychain_passphrase": "",
    "ipatool_bin": "/opt/ipa-web/bin/ipatool",
    "ipatool_dl_bin": "",
    "apkeep_bin": "/opt/ipa-web/bin/apkeep",
    "home_dir": "/opt/ipa-web/home",
    "data_dir": "/opt/ipa-web/data",
    "country": "cn",
    "retention_minutes": 60,
    "max_concurrent": 1,
    "auto_update_ipatool": True,
    "apple_id": "",
    "trust_proxy": False,
    "low_memory": False,
}


def load_config():
    with open(CONFIG_PATH, "r", encoding="utf-8") as f:
        cfg = json.load(f)
    for k, v in DEFAULTS.items():
        cfg.setdefault(k, v)
    for k in ("secret", "keychain_passphrase", "password_hash", "apple_id", "country"):
        cfg[k] = str(cfg[k])
    if not cfg["secret"]:
        cfg["secret"] = secrets.token_hex(32)
    return cfg


CFG = load_config()
CFG_STATE = {"mtime": os.stat(CONFIG_PATH).st_mtime}
CFG_LOCK = threading.Lock()
os.makedirs(CFG["data_dir"], exist_ok=True)


def reload_config():
    """qiequ 切区只改 config.json，这里发现变了就重新读，不用重启。"""
    try:
        m = os.stat(CONFIG_PATH).st_mtime
    except OSError:
        return
    if m == CFG_STATE["mtime"]:
        return
    with CFG_LOCK:
        if m == CFG_STATE["mtime"]:
            return
        try:
            new = load_config()
        except Exception as e:
            log("重新读配置失败", e)
            return
        for k in ("home_dir", "country", "apple_id", "accounts", "active",
                  "retention_minutes", "password_hash", "keychain_passphrase",
                  "auto_update_ipatool", "low_memory", "ipatool_dl_bin", "apkeep_bin"):
            if k in new:
                CFG[k] = new[k]
        CFG_STATE["mtime"] = m
        log("配置变了，现在用 %s 区账号 %s" % (CFG["country"].upper(), CFG["apple_id"] or "（无）"))


def log(*args):
    print(time.strftime("%Y-%m-%d %H:%M:%S"), *args, flush=True)


#----------------------------------------------------------------------
# 网页密码。配置里存的是 pbkdf2 摘要，不存明文。
# 登录后发一个签名 cookie，换密码以后旧 cookie 自动失效。
#----------------------------------------------------------------------
SESSION_DAYS = 30


def check_password(plain):
    try:
        algo, iters, salt, want = CFG["password_hash"].split("$")
        assert algo == "pbkdf2_sha256"
        got = hashlib.pbkdf2_hmac("sha256", plain.encode(), bytes.fromhex(salt), int(iters)).hex()
        return hmac.compare_digest(got, want)
    except Exception:
        return False


def _sign(text):
    key = (CFG["secret"] + CFG["password_hash"]).encode()
    return hmac.new(key, text.encode(), hashlib.sha256).hexdigest()


def make_session():
    exp = str(int(time.time()) + SESSION_DAYS * 86400)
    return exp + "." + _sign(exp)


def session_ok(token):
    if not token or "." not in token:
        return False
    exp, sig = token.split(".", 1)
    if not exp.isdigit() or int(exp) < time.time():
        return False
    return hmac.compare_digest(sig, _sign(exp))


# 同一个 IP 10 分钟内输错 8 次就先锁住，防止被人猜密码。
FAILS = {}
FAILS_LOCK = threading.Lock()
FAIL_LIMIT = 8
FAIL_WINDOW = 600


def login_blocked(ip):
    with FAILS_LOCK:
        now = time.time()
        hits = [t for t in FAILS.get(ip, []) if now - t < FAIL_WINDOW]
        FAILS[ip] = hits
        return len(hits) >= FAIL_LIMIT


def login_failed(ip):
    with FAILS_LOCK:
        FAILS.setdefault(ip, []).append(time.time())


#----------------------------------------------------------------------
# 调 ipatool。每次都带上钥匙串口令、JSON 输出、非交互，
# HOME 指到专用目录，登录凭证不会和系统里别的东西混在一起。
# TMPDIR 指到硬盘（/opt/ipa-web/tmp），不走 /tmp：容器里 /tmp 常是 tmpfs（内存盘），
# ipatool 临时解压七十多 MB 苹果组件到 /tmp 会直接吃掉内存和 swap，被杀后还会永久残留。
#----------------------------------------------------------------------
def pick_ipatool_bin(args, force_main=False):
    if not force_main and CFG.get("low_memory"):
        dl_bin = CFG.get("ipatool_dl_bin") or os.path.join(BASE_DIR, "bin", "ipatool-dl")
        if dl_bin and os.path.isfile(dl_bin) and os.access(dl_bin, os.X_OK):
            # server.py 只会调 download / list-versions / get-version-metadata / auth info，
            # 这些命令用 2.7.0 轻量引擎仅占 ~50MB 内存，钥匙串与新版完全兼容。
            if not args or args[0] != "auth" or (len(args) > 1 and args[1] == "info"):
                return dl_bin
    return CFG["ipatool_bin"]


def ipatool(args, timeout=120, home=None, force_main=False):
    bin_path = pick_ipatool_bin(args, force_main=force_main)
    cmd = [bin_path] + args + [
        "--format", "json",
        "--non-interactive",
        "--keychain-passphrase", CFG["keychain_passphrase"],
    ]
    run_tmp = os.path.join(TMP_ROOT, "run-" + secrets.token_hex(6))
    os.makedirs(run_tmp, exist_ok=True)
    env = dict(os.environ, HOME=home or CFG["home_dir"], TMPDIR=run_tmp)
    if CFG["low_memory"]:
        # 小内存机器：让 Go 勤快点回收内存，同时限制 glibc/C 堆 arena 数量。
        env.update(GOMEMLIMIT="32MiB", GOGC="25", GOMAXPROCS="1", MALLOC_ARENA_MAX="2")
    try:
        try:
            p = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, env=env)
        except OSError as e:
            return 127, "ipatool 不可用：%s" % e
        try:
            out, _ = p.communicate(timeout=timeout)
        except subprocess.TimeoutExpired:
            p.kill()
            p.communicate()
            return None, "ipatool 超时没有反应"
        return p.returncode, out.decode("utf-8", "replace")
    finally:
        shutil.rmtree(run_tmp, ignore_errors=True)


def last_json(text):
    """ipatool 一行一个 JSON，取最后一行能解析的。"""
    for line in reversed((text or "").strip().splitlines()):
        line = line.strip()
        if line.startswith("{"):
            try:
                return json.loads(line)
            except ValueError:
                continue
    return {}


#----------------------------------------------------------------------
# ipatool 自动更新：每天查一次 GitHub 有没有新版，有就在没人下载时换掉。
# 换文件是原子操作，正在跑的 ipatool 不受影响；新文件先验校验、验版本，
# 不行就恢复备份，不会把能用的旧版弄坏。关掉：在设置里关「ipatool 自动更新」。
#----------------------------------------------------------------------
IPATOOL_REPO = "majd/ipatool"
IPATOOL_CHECK_INTERVAL = 86400  # 每天检查一次
UPDATE_STATE = {"last_check": 0, "pending": None}


def parse_version(s):
    """'2.8.1' / 'v2.8.1' -> (2, 8, 1)，解析不出返回 None。"""
    m = re.search(r"(\d+)\.(\d+)\.(\d+)", s or "")
    if not m:
        return None
    return tuple(int(x) for x in m.groups())


def fmt_version(v):
    return ".".join(str(x) for x in v)


def local_ipatool_version():
    try:
        p = subprocess.run([CFG["ipatool_bin"], "--version"],
                           stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                           timeout=30)
    except Exception:
        return None
    return parse_version(p.stdout.decode("utf-8", "replace"))


def latest_ipatool_version():
    req = urllib.request.Request(
        "https://api.github.com/repos/%s/releases/latest" % IPATOOL_REPO,
        headers={"User-Agent": "ipa-web", "Accept": "application/vnd.github+json"})
    try:
        with urllib.request.urlopen(req, timeout=10) as r:
            tag = json.load(r).get("tag_name", "")
    except Exception as e:
        log("查 ipatool 新版失败", e)
        return None
    return parse_version(tag)


def jobs_active():
    with JOBS_LOCK:
        return any(j["status"] in ("queued", "running") for j in JOBS.values())


def download_file(url, dest, timeout=120):
    req = urllib.request.Request(url, headers={"User-Agent": "ipa-web"})
    with urllib.request.urlopen(req, timeout=timeout) as r, open(dest, "wb") as f:
        shutil.copyfileobj(r, f, 1024 * 256)


def install_ipatool_version(ver):
    """下载指定版本并换掉现在的 ipatool，成功返回 True。"""
    machine = platform.machine()
    arch = {"x86_64": "amd64", "amd64": "amd64",
            "aarch64": "arm64", "arm64": "arm64"}.get(machine)
    if not arch:
        log("ipatool 自动更新：不支持的架构", machine)
        return False
    ver_s = fmt_version(ver)
    base = os.path.dirname(HERE)  # /opt/ipa-web
    tmp = os.path.join(base, "tmp", "ipatool-update")
    shutil.rmtree(tmp, ignore_errors=True)
    os.makedirs(tmp, exist_ok=True)
    name = "ipatool-%s-linux-%s.tar.gz" % (ver_s, arch)
    url = "https://github.com/%s/releases/download/v%s/%s" % (IPATOOL_REPO, ver_s, name)
    tgz = os.path.join(tmp, name)
    try:
        log("ipatool 自动更新：下载 %s" % name)
        download_file(url, tgz)
        want = None
        try:
            sha_path = tgz + ".sha256"
            download_file(url + ".sha256sum", sha_path, timeout=30)
            with open(sha_path, "r", encoding="utf-8") as f:
                want = f.read().split()[0]
        except Exception:
            pass
        if want:
            h = hashlib.sha256()
            with open(tgz, "rb") as f:
                for chunk in iter(lambda: f.read(1024 * 256), b""):
                    h.update(chunk)
            if h.hexdigest() != want:
                log("ipatool 自动更新：文件校验不对，放弃")
                return False
        xtract = os.path.join(tmp, "x")
        os.makedirs(xtract)
        with tarfile.open(tgz, "r:gz") as t:
            t.extractall(xtract)
        cand = None
        for root, _, files in os.walk(xtract):
            for fn in files:
                if fn.startswith("ipatool"):
                    cand = os.path.join(root, fn)
                    break
            if cand:
                break
        if not cand:
            log("ipatool 自动更新：压缩包里找不到 ipatool")
            return False
        os.chmod(cand, 0o755)
        # 先确认新文件能跑、版本对，再换。
        try:
            p = subprocess.run([cand, "--version"], stdout=subprocess.PIPE,
                               stderr=subprocess.STDOUT, timeout=30)
            got = parse_version(p.stdout.decode("utf-8", "replace"))
        except Exception:
            got = None
        if got != ver:
            log("ipatool 自动更新：新文件版本不对（想要 %s）" % ver_s)
            return False
        bin_path = CFG["ipatool_bin"]
        bak_path = bin_path + ".bak"
        if os.path.exists(bin_path):
            shutil.copy2(bin_path, bak_path)
        os.replace(cand, bin_path)
        if local_ipatool_version() != ver:
            if os.path.exists(bak_path):
                os.replace(bak_path, bin_path)
            log("ipatool 自动更新：换上去的版本不对，已恢复旧版")
            return False
        log("ipatool 已自动更新到 %s" % ver_s)
        return True
    except Exception as e:
        log("ipatool 自动更新失败", e)
        return False
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


def maybe_update_ipatool(now):
    """每天查一次新版，有新版且没人下载时就升级。失败了明天再试。"""
    if not CFG.get("auto_update_ipatool", True):
        return
    if UPDATE_STATE["pending"] is None and now - UPDATE_STATE["last_check"] >= IPATOOL_CHECK_INTERVAL:
        UPDATE_STATE["last_check"] = now
        cur = local_ipatool_version()
        latest = latest_ipatool_version()
        if latest and (cur is None or latest > cur):
            UPDATE_STATE["pending"] = latest
            log("发现 ipatool 新版 %s（现在 %s），没人下载时自动升级"
                % (fmt_version(latest), fmt_version(cur) if cur else "未安装"))
    pending = UPDATE_STATE["pending"]
    if pending is None or jobs_active():
        return
    # 装失败也先清掉，明天检查时再说，避免每分钟重试下载。
    install_ipatool_version(pending)
    UPDATE_STATE["pending"] = None


def explain_error(text, rc=None):
    """把 ipatool 的英文报错翻成人话。rc 是 ipatool 的退出码。
    负数表示被信号杀掉：-9 基本就是内存不够被 OOM 杀掉，这时 ipatool
    来不及输出任何东西，只看输出会误判成「未知错误」，所以要先看 rc。
    """
    if rc is not None and rc < 0:
        if rc == -9:
            return ("VPS 内存不够，ipatool 被系统杀掉了（OOM）。"
                    "请运行 ipa-web --upgrade 启用低内存下载引擎，或等其他任务结束再试。")
        return "ipatool 被系统信号 %d 强制结束了，没有留下错误信息（可能是内存不足，也可能是 ipatool 本身崩了）。" % -rc
    raw = last_json(text).get("error") or (text or "").strip()[-400:]
    if not raw:
        if rc is not None and rc != 0:
            return "ipatool 退出了（退出码 %d），但没有留下错误信息。" % rc
        return "未知错误"
    low = raw.lower()
    if "keyring" in low or "failed to get account" in low:
        return "VPS 上这个账号还没登录。请在 VPS 终端运行 qiequ，选 a 添加账号或 r 重新登录。"
    if "store amd state is not provisioned" in low or "not provisioned" in low:
        return "ipatool 升级后需要重新登录一次 Apple ID 以更新本地认证状态。请在 VPS 终端运行 qiequ，选 r 重新登录这个账号。"
    if ("token" in low and ("expire" in low or "invalid" in low)) or "sign-in request failed" in low or "authentication request failed" in low:
        return "Apple ID 登录已过期。请在 VPS 终端运行 qiequ，选 r 重新登录这个账号。"
    if "password" in low and ("incorrect" in low or "invalid" in low):
        return "Apple ID 凭证失效，请在 VPS 上重新登录。"
    if "paid" in low or "price" in low or "payment" in low:
        return "这是付费 App，需要先用这个 Apple ID 在 iPhone / Mac 上买过才能下载。"
    if "license" in low:
        return "这个 Apple ID 还没有这个 App 的许可，而且没法自动领取（可能是付费 App 或地区不对）。"
    if "not found" in low or "no results" in low:
        return "App Store 找不到这个 App，可能是 Apple ID 所在地区没有上架。"
    if "killed" in low or "signal: killed" in low:
        return "VPS 内存不够，ipatool 被系统杀掉了。可以运行 ipa-web --upgrade 启用低内存下载引擎，或者等别的任务做完再试。"
    if "no space" in low:
        return "VPS 硬盘满了。"
    return raw


#----------------------------------------------------------------------
# 搜索走苹果公开的 iTunes 搜索接口：不用登录、带图标和大小，比 ipatool search 好看。
# 地区要和 Apple ID 所在地区一致，不然搜到的 App 可能下不了。
#----------------------------------------------------------------------
def itunes(path, params):
    params = dict(params, country=CFG["country"])
    url = "https://itunes.apple.com/%s?%s" % (path, urllib.parse.urlencode(params))
    req = urllib.request.Request(url, headers={"User-Agent": "ipa-web/" + VERSION})
    with urllib.request.urlopen(req, timeout=15) as r:
        return json.loads(r.read().decode("utf-8", "replace"))


def slim_app(a):
    return {
        "id": a.get("trackId"),
        "bundle": a.get("bundleId", ""),
        "name": a.get("trackName", ""),
        "seller": a.get("sellerName") or a.get("artistName", ""),
        "version": a.get("version", ""),
        "size": int(a.get("fileSizeBytes") or 0),
        "price": a.get("formattedPrice") or ("免费" if not a.get("price") else str(a.get("price"))),
        "free": not a.get("price"),
        "icon": a.get("artworkUrl100") or a.get("artworkUrl60", ""),
        "minos": a.get("minimumOsVersion", ""),
        "genre": a.get("primaryGenreName", ""),
        "url": a.get("trackViewUrl", ""),
    }


def search_apps(term, limit=20):
    term = term.strip()
    # 直接贴 App Store 链接或者纯数字 ID：按 ID 查。
    m = re.search(r"id(\d{6,})", term) or re.fullmatch(r"(\d{6,})", term)
    if m:
        data = itunes("lookup", {"id": m.group(1)})
    # 看起来像 bundle ID（com.xxx.yyy）：按 bundle ID 查，查不到再当普通关键词。
    elif re.fullmatch(r"[A-Za-z0-9-]+(\.[A-Za-z0-9-]+){2,}", term):
        data = itunes("lookup", {"bundleId": term})
        if not data.get("results"):
            data = itunes("search", {"term": term, "entity": "software", "limit": limit})
    else:
        data = itunes("search", {"term": term, "entity": "software", "limit": limit})
    return [slim_app(a) for a in data.get("results", []) if a.get("trackId")]


#----------------------------------------------------------------------
# 安卓 APK / XAPK / APKS 多源搜索与下载引擎（纯 Python 标准库，免登录）
#   聚合来源：
#     apkpure  - APKPure 移动端 API（海外应用最全，支持历史版本、APK/XAPK）
#     uptodown - Uptodown 移动端 eAPI（海外大库，支持历史版本、APK/XAPK）
#     aptoide  - Aptoide API v7（海外大库，直链稳定）
#     huawei   - 华为应用市场 AppGallery（国内+海外多区，高速官方直链）
#     tencent  - 腾讯应用宝（国内应用极全，官方直链）
#     vivo     - Vivo 应用商店（国内应用极全，官方直链）
#     fdroid   - F-Droid（开源应用库，支持官方+清华镜像回退与历史版本）
#     github   - GitHub Releases（开源安卓项目，支持仓库链接与历史版本）
#   另外支持直接粘贴 .apk/.xapk/.apks 直链，以及可选 apkeep CLI 兜底。
#----------------------------------------------------------------------
APK_SOURCES = [
    {"id": "auto",     "name": "全部源自动聚合"},
    {"id": "apkpure",  "name": "APKPure（海外全量）"},
    {"id": "uptodown", "name": "Uptodown（海外/历史版）"},
    {"id": "aptoide",  "name": "Aptoide（海外应用）"},
    {"id": "huawei",   "name": "华为应用市场"},
    {"id": "tencent",  "name": "腾讯应用宝"},
    {"id": "vivo",     "name": "Vivo 应用商店"},
    {"id": "fdroid",   "name": "F-Droid（开源）"},
    {"id": "github",   "name": "GitHub Releases"},
]
APK_SOURCE_NAMES = {s["id"]: s["name"] for s in APK_SOURCES}
APK_SOURCE_NAMES["direct"] = "直链下载"
APK_SOURCE_NAMES["apkeep"] = "apkeep"

APK_UA_BROWSER = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36"
APK_UA_DALVIK = "Dalvik/2.1.0 (Linux; U; Android 14; SM-G955F Build/AP2A.240805.005)"
APK_EXTS = (".apk", ".xapk", ".apks", ".apkm", ".aab")

# 短暂缓存搜索/版本里的直链和附加信息，避免前端传任意 URL 造成 SSRF
APK_CACHE = {}
APK_CACHE_LOCK = threading.Lock()
APK_CACHE_TTL = 3600


def apk_cache_put(token_key, info):
    with APK_CACHE_LOCK:
        now = time.time()
        if len(APK_CACHE) > 500:
            stale = [k for k, v in APK_CACHE.items() if now - v["t"] > APK_CACHE_TTL]
            for k in stale:
                APK_CACHE.pop(k, None)
        APK_CACHE[token_key] = {"t": now, "data": info}


def apk_cache_get(token_key):
    with APK_CACHE_LOCK:
        entry = APK_CACHE.get(token_key)
        if not entry:
            return None
        if time.time() - entry["t"] > APK_CACHE_TTL:
            APK_CACHE.pop(token_key, None)
            return None
        return entry["data"]


def _http_read(url, headers=None, data=None, timeout=10):
    hdrs = {"User-Agent": APK_UA_BROWSER}
    if headers:
        hdrs.update(headers)
    if isinstance(data, str):
        data = data.encode("utf-8")
    req = urllib.request.Request(url, data=data, headers=hdrs)
    with urllib.request.urlopen(req, timeout=timeout) as r:
        raw = r.read()
        if raw[:2] == b"\x1f\x8b":
            try:
                raw = gzip.decompress(raw)
            except Exception:
                pass
        return r.status, r.headers, raw


def _http_json(url, headers=None, data=None, timeout=10):
    _, _, raw = _http_read(url, headers=headers, data=data, timeout=timeout)
    return json.loads(raw.decode("utf-8", "replace"))


def _is_pkg_name(s):
    return bool(re.fullmatch(r"[A-Za-z][A-Za-z0-9_]*(\.[A-Za-z0-9_]+){1,}", s or ""))


def _guess_pkg_ext(url, headers=None, fallback=".apk"):
    cd = (headers.get("Content-Disposition") or "") if headers else ""
    for text in (cd, urllib.parse.unquote(url or "")):
        m = re.search(r"\.(xapk|apks|apkm|aab|apk)(?:[\"'?;&#\s]|$)", text, re.I)
        if m:
            return "." + m.group(1).lower()
    return fallback if fallback.startswith(".") else "." + fallback


def _extract_android_target(term):
    """解析用户输入：识别直链、GitHub 仓库、各大商店链接、包名或普通关键词。"""
    t = (term or "").strip()
    # 1. 直接粘贴 .apk / .xapk / .apks 下载直链
    if re.match(r"^https?://", t, re.I):
        low_path = urllib.parse.urlparse(t).path.lower()
        if any(low_path.endswith(ext) for ext in APK_EXTS):
            return ("direct", t)
        # Google Play: https://play.google.com/store/apps/details?id=com.xxx
        m = re.search(r"play\.google\.com/store/apps/details.*[?&]id=([A-Za-z0-9_.]+)", t)
        if m:
            return ("package", m.group(1))
        # GitHub 仓库或 release 链接
        m = re.search(r"github\.com/([A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+)", t)
        if m:
            repo = m.group(1).rstrip("/")
            if repo.endswith(".git"):
                repo = repo[:-4]
            return ("github", repo)
        # F-Droid 链接
        m = re.search(r"f-droid\.org/(?:[a-zA-Z_-]+/)?packages/([A-Za-z0-9_.]+)", t)
        if m:
            return ("package", m.group(1))
        # 腾讯应用宝链接
        m = re.search(r"(?:sj\.qq\.com/appdetail/|a\.app\.qq\.com/.*pkgname=)([A-Za-z0-9_.]+)", t)
        if m:
            return ("package", m.group(1))
        # APKPure 链接：https://apkpure.com/app-name/com.xxx.yyy
        m = re.search(r"apkpure\.(?:com|net)/(?:[a-z]{2}/)?[^/]+/([A-Za-z][A-Za-z0-9_]*(?:\.[A-Za-z0-9_]+)+)", t)
        if m:
            return ("package", m.group(1))
        # 华为应用市场链接：https://appgallery.huawei.com/app/C10652857
        m = re.search(r"appgallery\.(?:cloud\.)?huawei\.(?:com|ru)/(?:#/)?app/(C\d+)", t)
        if m:
            return ("huawei_id", m.group(1))
        # Vivo 应用商店链接
        m = re.search(r"vivo\.com\.cn/.*[?&](?:appId|id)=(\d+)", t)
        if m:
            return ("vivo_id", m.group(1))
    # 2. owner/repo 格式（GitHub）
    if re.fullmatch(r"[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+", t) and "." not in t.split("/")[0]:
        return ("github", t)
    # 3. 包名 com.xxx.yyy
    if _is_pkg_name(t):
        return ("package", t)
    return ("keyword", t)


# ---- 1. APKPure 移动端 API ----
_APKPURE_BASE = "https://tapi.pureapk.com/v3"
_APKPURE_AUTH = "qNKrYmW8SSUqJ73k3P2yfMxRTo3sJTR"
_APKPURE_SIGN = "d33cb23fd17fda8ea38be504929b77ef"


def _apkpure_headers(body=None):
    dev_uuid = str(uuid.uuid4())
    project_a = json.dumps({
        "device_info": {
            "abis": ["arm64-v8a", "armeabi-v7a", "x86_64"],
            "android_id": hashlib.md5(dev_uuid.encode()).hexdigest()[:16],
            "brand": "samsung", "country": "United States",
            "country_code": "US", "imei": "", "language": "en-US",
            "manufacturer": "samsung", "mode": "SM-G955F",
            "os_ver": "34", "os_ver_name": "14", "platform": 1,
            "product": "dream2lte", "screen_height": 2888, "screen_width": 1440,
        },
        "host_app_info": {
            "build_no": "873", "channel": "", "md5": "",
            "pkg_name": "com.apkpure.aegon", "sdk_ver": "3.20.6309",
            "version_code": 3206397, "version_name": "3.20.6309",
        },
        "net_info": {
            "carrier_code": 0, "ipv4": "", "ipv6": "", "mac_address": "",
            "net_type": 1, "use_vpn": False, "wifi_bssid": "", "wifi_ssid": "",
        },
        "user_info": {
            "auth_key": _APKPURE_AUTH, "country": "United States",
            "country_code": "US", "guid": "", "language": "en-US",
            "qimei": "", "qimei_token": "", "user_id": "", "uuid": dev_uuid,
        },
    }, separators=(",", ":"))
    ext_info = json.dumps({
        "ext_info": '{"gaid":"","oaid":""}',
        "lbs_info": {
            "accuracy": 0.0, "city": "", "city_code": 0,
            "country": "", "country_code": "", "district": "",
            "latitude": 0.0, "longitude": 0.0, "province": "", "street": "",
        },
    }, separators=(",", ":"))
    hdrs = {
        "User-Agent": APK_UA_DALVIK + "; APKPure/3.20.6309 (Aegon)",
        "Ual-Access-Businessid": "projecta",
        "Ual-Access-ProjectA": project_a,
        "Ual-Access-ExtInfo": ext_info,
        "Ual-Access-Sequence": str(uuid.uuid4()),
        "Ual-Access-Signature": "",
        "Ual-Access-Nonce": "0",
        "Ual-Access-Timestamp": "0",
        "Accept-Encoding": "gzip",
    }
    if body is not None:
        ts = str(int(time.time() * 1000))
        nonce = str(random.randint(10000000, 99999999))
        sig = hashlib.md5((body + ts + _APKPURE_SIGN + nonce).encode()).hexdigest()
        hdrs["Ual-Access-Signature"] = sig
        hdrs["Ual-Access-Nonce"] = nonce
        hdrs["Ual-Access-Timestamp"] = ts
        hdrs["Content-Type"] = "application/json; charset=utf-8"
    return hdrs


def _apkpure_item(ai):
    pkg = ai.get("package_name") or ""
    if not pkg:
        return None
    asset = ai.get("asset") or {}
    icon = ""
    ic = ai.get("icon")
    if isinstance(ic, dict):
        icon = (ic.get("original") or ic.get("thumbnail") or {}).get("url") or ""
    elif isinstance(ic, str):
        icon = ic
    ftype = (asset.get("type") or "APK").upper()
    dl_url = asset.get("url") or ""
    if not dl_url and isinstance(asset.get("urls"), list) and asset["urls"]:
        dl_url = asset["urls"][0]
    return {
        "package": pkg,
        "name": ai.get("title") or pkg,
        "seller": ai.get("developer") or "APKPure",
        "version": ai.get("version_name") or "",
        "version_code": str(ai.get("version_code") or ""),
        "size": int(asset.get("size") or 0),
        "icon": icon,
        "source": "apkpure",
        "pkg_type": ftype,
        "has_versions": True,
        "dl_url": dl_url,
        "dl_headers": {"User-Agent": APK_UA_DALVIK},
    }


def apkpure_search(query, limit=12):
    qs = urllib.parse.urlencode({"hl": "en-US", "key": query, "page": "1", "search_type": "active_search"})
    data = _http_json("%s/search_query_new?%s" % (_APKPURE_BASE, qs), headers=_apkpure_headers(), timeout=8)
    out, seen = [], set()
    for sec in (data.get("data") or {}).get("data") or []:
        for it in sec.get("data") or []:
            ai = it.get("app_info") or {}
            pkg = ai.get("package_name") or ""
            if not pkg or pkg in seen:
                continue
            seen.add(pkg)
            item = _apkpure_item(ai)
            if item:
                out.append(item)
            if len(out) >= limit:
                return out
    return out


def apkpure_detail(pkg):
    body = json.dumps({"package_name": pkg, "hl": "en-US"})
    data = _http_json("%s/get_app_detail" % _APKPURE_BASE, headers=_apkpure_headers(body), data=body, timeout=8)
    detail = data.get("app_detail")
    return _apkpure_item(detail) if isinstance(detail, dict) else None


def apkpure_versions(pkg):
    qs = urllib.parse.urlencode({"package_name": pkg, "hl": "en-US"})
    data = _http_json("%s/get_app_his_version?%s" % (_APKPURE_BASE, qs), headers=_apkpure_headers(), timeout=10)
    out = []
    for v in data.get("version_list") or []:
        asset = v.get("asset") or {}
        urls = asset.get("urls") or ([asset.get("url")] if asset.get("url") else [])
        dl_url = urls[0] if urls else ""
        if not dl_url:
            continue
        archs = v.get("native_code") or []
        arch_str = ",".join(str(x) for x in archs) if isinstance(archs, list) else ""
        out.append({
            "version": v.get("version_name") or str(v.get("version_code") or ""),
            "version_code": str(v.get("version_code") or ""),
            "date": str(v.get("update_date") or "")[:10],
            "size": int(asset.get("size") or 0),
            "pkg_type": (asset.get("type") or "APK").upper(),
            "arch": arch_str,
            "source": "apkpure",
            "dl_url": dl_url,
            "dl_headers": {"User-Agent": APK_UA_DALVIK},
        })
    return out


# ---- 2. Uptodown 移动端 eAPI ----
_UPTODOWN_BASE = "https://www.uptodown.app/eapi"
_UPTODOWN_SECRET = "$(=a%\u00b7!45J&S"


def _uptodown_headers():
    hour_epoch = (int(time.time()) // 3600) * 3600
    apikey = hashlib.sha256((_UPTODOWN_SECRET + str(hour_epoch)).encode("utf-8")).hexdigest()
    return {
        "User-Agent": APK_UA_DALVIK,
        "Identificador": "Uptodown_Android",
        "Identificador-Version": "707",
        "APIKEY": apikey,
    }


def uptodown_search(query, limit=12):
    q = urllib.parse.quote(query, safe="")
    url = "%s/v2/apps/search/%s?page[limit]=%d&page[offset]=0" % (_UPTODOWN_BASE, q, limit)
    data = _http_json(url, headers=_uptodown_headers(), timeout=8)
    items = (data.get("data") or {}).get("results") or []
    out = []
    for it in items[:limit]:
        pkg = it.get("packageName") or it.get("packagename") or ""
        aid = str(it.get("appID") or it.get("id") or "")
        if not pkg and not aid:
            continue
        out.append({
            "package": pkg or ("uptodown:" + aid),
            "name": it.get("name") or pkg,
            "seller": it.get("author") or "Uptodown",
            "version": it.get("version") or it.get("lastVersion") or "",
            "version_code": str(it.get("versionCode") or ""),
            "size": int(it.get("size") or 0),
            "icon": it.get("iconURL") or it.get("icon") or "",
            "source": "uptodown",
            "pkg_type": "APK",
            "has_versions": True,
            "extra": {"app_id": aid},
        })
    return out


def _uptodown_resolve_id(pkg, app_id=""):
    if app_id:
        return str(app_id)
    if pkg.startswith("uptodown:"):
        return pkg.split(":", 1)[1]
    try:
        d = _http_json("%s/apps/byPackagename/%s" % (_UPTODOWN_BASE, urllib.parse.quote(pkg, safe="")),
                       headers=_uptodown_headers(), timeout=6)
        inner = d.get("data") if isinstance(d.get("data"), dict) else d
        aid = inner.get("appID") or inner.get("id")
        if aid:
            return str(aid)
    except urllib.error.HTTPError:
        pass
    except Exception:
        return ""
    for it in uptodown_search(pkg, limit=5):
        if it["package"] == pkg and (it.get("extra") or {}).get("app_id"):
            return str(it["extra"]["app_id"])
    return ""


def uptodown_detail(pkg, app_id=""):
    aid = _uptodown_resolve_id(pkg, app_id)
    if not aid:
        return None
    d = _http_json("%s/v3/apps/%s/device/0?countryIsoCode=US" % (_UPTODOWN_BASE, aid),
                   headers=_uptodown_headers(), timeout=8)
    inner = d.get("data") if isinstance(d.get("data"), dict) else d
    if not isinstance(inner, dict) or not inner.get("name"):
        return None
    return {
        "package": inner.get("packagename") or pkg,
        "name": inner.get("name") or pkg,
        "seller": inner.get("author") or "Uptodown",
        "version": inner.get("lastVersion") or str(inner.get("lastVersionCode") or ""),
        "version_code": str(inner.get("lastVersionCode") or ""),
        "size": int(inner.get("size") or 0),
        "icon": inner.get("iconURL") or inner.get("icon") or "",
        "source": "uptodown",
        "pkg_type": "APK",
        "has_versions": True,
        "extra": {"app_id": aid},
    }


def uptodown_versions(pkg, app_id=""):
    aid = _uptodown_resolve_id(pkg, app_id)
    if not aid:
        return []
    d = _http_json("%s/v3/app/%s/device/1/compatible/versions?page[limit]=25&page[offset]=0" % (_UPTODOWN_BASE, aid),
                   headers=_uptodown_headers(), timeout=10)
    out = []
    for v in d.get("data") or []:
        fid = str(v.get("fileID") or v.get("fileid") or "")
        if not fid:
            continue
        out.append({
            "version": v.get("version") or str(v.get("versionCode") or ""),
            "version_code": str(v.get("versionCode") or ""),
            "date": str(v.get("lastUpdate") or ""),
            "size": int(v.get("size") or 0),
            "pkg_type": (v.get("fileType") or v.get("filetype") or "APK").upper(),
            "arch": "",
            "source": "uptodown",
            "extra": {"app_id": aid, "file_id": fid},
        })
    return out


def uptodown_resolve_download(pkg, extra=None, version=""):
    extra = extra or {}
    aid = _uptodown_resolve_id(pkg, extra.get("app_id", ""))
    if not aid:
        raise RuntimeError("Uptodown 未找到该应用")
    fid = str(extra.get("file_id") or "")
    ftype = "apk"
    ver = version
    if not fid:
        vers = uptodown_versions(pkg, aid)
        if not vers:
            raise RuntimeError("Uptodown 未找到可下载版本")
        target = next((v for v in vers if version and v["version"] == version), vers[0])
        fid = target["extra"]["file_id"]
        ftype = target["pkg_type"].lower()
        ver = target["version"]
    d = _http_json("%s/apps/%s/file/%s/downloadUrl?update=0" % (_UPTODOWN_BASE, aid, fid),
                   headers=_uptodown_headers(), timeout=10)
    dl_url = (d.get("data") or {}).get("downloadURL") or ""
    if not dl_url:
        raise RuntimeError("Uptodown 获取下载链接失败")
    return dl_url, {"User-Agent": APK_UA_DALVIK}, "." + ftype, ver


# ---- 3. Aptoide API v7 ----
_APTOIDE_BASE = "https://ws75.aptoide.com/api/7"


def _aptoide_item(it):
    pkg = it.get("package") or ""
    if not pkg:
        return None
    f = it.get("file") or {}
    dl_url = f.get("path") or ""
    return {
        "package": pkg,
        "name": it.get("name") or pkg,
        "seller": (it.get("developer") or {}).get("name") or (it.get("store") or {}).get("name") or "Aptoide",
        "version": f.get("vername") or "",
        "version_code": str(f.get("vercode") or ""),
        "size": int(it.get("size") or f.get("filesize") or 0),
        "icon": it.get("icon") or "",
        "source": "aptoide",
        "pkg_type": "APK",
        "has_versions": False,
        "dl_url": dl_url,
        "dl_headers": {"User-Agent": APK_UA_BROWSER},
    }


def aptoide_search(query, limit=12):
    qs = urllib.parse.urlencode({"query": query, "limit": str(limit), "aab": "1"})
    data = _http_json("%s/apps/search?%s" % (_APTOIDE_BASE, qs), timeout=8)
    out = []
    for it in (data.get("datalist") or {}).get("list") or []:
        item = _aptoide_item(it)
        if item:
            out.append(item)
    return out


def aptoide_detail(pkg):
    qs = urllib.parse.urlencode({"package_name": pkg, "aab": "1"})
    data = _http_json("%s/app/getMeta?%s" % (_APTOIDE_BASE, qs), timeout=8)
    d = data.get("data")
    return _aptoide_item(d) if isinstance(d, dict) else None


# ---- 4. 华为应用市场 AppGallery ----
_HUAWEI_SESSION = {"t": 0, "host": "", "sign": "", "device_id": ""}
_HUAWEI_LOCK = threading.Lock()
_HUAWEI_HOSTS = {
    "cn": "store-drcn.hispace.dbankcloud.com",
    "asia": "store-dra.hispace.dbankcloud.com",
    "eu": "store-dre.hispace.dbankcloud.com",
}


def _huawei_post(host, params, timeout=8):
    body = "&".join("%s=%s" % (urllib.parse.quote_plus(k), urllib.parse.quote_plus(str(params[k])))
                    for k in sorted(params.keys()))
    hdrs = {
        "User-Agent": "HiSpace##16.5.1.301##google##Pixel 8 Pro",
        "Accept": "application/json",
        "Content-Type": "application/x-www-form-urlencoded",
    }
    return _http_json("https://%s/hwmarket/api/clientApi" % host, headers=hdrs, data=body, timeout=timeout)


def _huawei_common(dev_id, locale="zh_CN"):
    return {
        "ver": "1.1", "locale": locale, "serviceType": "0",
        "ts": str(int(time.time() * 1000)), "net": "1",
        "brand": "google", "manufacturer": "Google", "subBrand": "0",
        "deviceId": dev_id, "deviceIdType": "9",
    }


def _huawei_session(force=False):
    with _HUAWEI_LOCK:
        if not force and _HUAWEI_SESSION["sign"] and time.time() - _HUAWEI_SESSION["t"] < 3600:
            return _HUAWEI_SESSION["host"], _HUAWEI_SESSION["sign"], _HUAWEI_SESSION["device_id"]
        dev_id = "".join(random.choice("0123456789abcdef") for _ in range(64))
        host = _HUAWEI_HOSTS["cn"] if CFG.get("country", "cn").lower() == "cn" else _HUAWEI_HOSTS["asia"]
        p = dict(_huawei_common(dev_id), method="client.front2", version="16.5.1", versionCode="160501301",
                 packageName="com.huawei.appmarket", zone="1", phoneType="Pixel 8 Pro",
                 firmwareVersion="16", isFirstLaunch="1", oobe="0", needServiceZone="0")
        res = _huawei_post(host, p, timeout=8)
        sign = res.get("sign") or ""
        if not sign:
            host = _HUAWEI_HOSTS["eu"]
            res = _huawei_post(host, p, timeout=8)
            sign = res.get("sign") or ""
        if not sign:
            raise RuntimeError("华为应用市场握手失败")
        _HUAWEI_SESSION.update(t=time.time(), host=host, sign=sign, device_id=dev_id)
        return host, sign, dev_id


def _huawei_item(app):
    pkg = app.get("package") or ""
    if not pkg:
        return None
    dl_url = app.get("downurl") or app.get("url") or ""
    size = 0
    for k in ("fullSize", "size", "bundleSize"):
        try:
            v = int(app.get(k) or 0)
            if v > 0:
                size = v
                break
        except Exception:
            pass
    return {
        "package": pkg,
        "name": app.get("name") or pkg,
        "seller": app.get("developer") or "华为应用市场",
        "version": app.get("versionName") or app.get("appVersionName") or "",
        "version_code": str(app.get("versionCode") or ""),
        "size": size,
        "icon": app.get("icon") or app.get("icoUri") or "",
        "source": "huawei",
        "pkg_type": "APK",
        "has_versions": False,
        "dl_url": dl_url,
        "dl_headers": {"User-Agent": APK_UA_BROWSER},
        "extra": {"app_id": str(app.get("appid") or app.get("appId") or "")},
    }


def huawei_search(query, limit=12):
    host, sign, dev_id = _huawei_session()
    p = dict(_huawei_common(dev_id), method="client.getTabDetail", sign=sign,
             uri="searchApp|" + query, maxResults=str(limit), reqPageNum="1", isSupportPage="1")
    res = _huawei_post(host, p, timeout=8)
    out, seen = [], set()
    for layout in res.get("layoutData") or []:
        for item in layout.get("dataList") or []:
            app = item.get("appInfo") if isinstance(item.get("appInfo"), dict) else item
            if not isinstance(app, dict):
                continue
            pkg = app.get("package") or ""
            if not pkg or pkg in seen:
                continue
            if not (app.get("downurl") or app.get("appid")):
                continue
            seen.add(pkg)
            it = _huawei_item(app)
            if it:
                out.append(it)
            if len(out) >= limit:
                return out
    return out


def huawei_detail(pkg="", app_id=""):
    host, sign, dev_id = _huawei_session()
    if app_id:
        p = dict(_huawei_common(dev_id), method="client.appDetailById", sign=sign, id=str(app_id))
        res = _huawei_post(host, p, timeout=8)
        di = res.get("detailInfo") or []
        if isinstance(di, list) and di and isinstance(di[0], dict):
            return _huawei_item(di[0])
    if pkg:
        p = dict(_huawei_common(dev_id), method="client.getTabDetail", sign=sign, uri="package|" + pkg)
        res = _huawei_post(host, p, timeout=8)
        best = {}
        for layout in res.get("layoutData") or []:
            for item in layout.get("dataList") or []:
                if isinstance(item, dict) and item.get("package") == pkg:
                    for k, v in item.items():
                        if v and not best.get(k):
                            best[k] = v
        if best.get("downurl"):
            return _huawei_item(best)
    return None


# ---- 5. 腾讯应用宝 ----
def tencent_detail(pkg):
    url = "https://a.app.qq.com/o/simple.jsp?pkgname=" + urllib.parse.quote(pkg, safe="")
    _, _, raw = _http_read(url, timeout=8)
    body = raw.decode("utf-8", "replace")
    ad = None
    for line in body.splitlines():
        line = line.strip()
        if line.startswith("window.systemData="):
            try:
                ad = json.loads(line[len("window.systemData="):]).get("appDetail")
            except Exception:
                pass
            break
    if not isinstance(ad, dict):
        return None
    dl_url = ad.get("apkUrl64") or ad.get("apkUrl") or ""
    if not dl_url:
        return None
    fsize = ad.get("fileSize") or {}
    size = int(fsize.get("bytes") or 0) if isinstance(fsize, dict) else 0
    return {
        "package": ad.get("packageName") or pkg,
        "name": ad.get("appName") or pkg,
        "seller": ad.get("author") or ad.get("developer") or "腾讯应用宝",
        "version": str(ad.get("versionName") or ""),
        "version_code": str(ad.get("versionCode") or ""),
        "size": size,
        "icon": ad.get("iconUrl") or "",
        "source": "tencent",
        "pkg_type": "APK",
        "has_versions": False,
        "dl_url": dl_url,
        "dl_headers": {"User-Agent": APK_UA_BROWSER},
    }


def tencent_search(query, limit=12):
    url = "https://sj.qq.com/search?q=" + urllib.parse.quote(query, safe="")
    _, _, raw = _http_read(url, timeout=8)
    body = raw.decode("utf-8", "replace")
    m = re.search(r'<script id="__NEXT_DATA__"[^>]*>(.*?)</script>', body, re.S)
    if not m:
        return []
    data = json.loads(m.group(1))
    out, seen = [], set()

    def walk(obj):
        if len(out) >= limit:
            return
        if isinstance(obj, dict):
            pkg = obj.get("pkg_name") or ""
            name = obj.get("name") or ""
            # 过滤掉 PC 应用和无包名项
            if pkg and name and ".pcapp." not in pkg and ".pcgame." not in pkg and pkg not in seen:
                seen.add(pkg)
                try:
                    size = int(obj.get("apk_size") or 0)
                except Exception:
                    size = 0
                out.append({
                    "package": pkg,
                    "name": name,
                    "seller": obj.get("developer") or "腾讯应用宝",
                    "version": str(obj.get("version_name") or ""),
                    "version_code": "",
                    "size": size,
                    "icon": obj.get("icon") or "",
                    "source": "tencent",
                    "pkg_type": "APK",
                    "has_versions": False,
                    "dl_url": obj.get("download_url") or obj.get("apk_url") or "",
                    "dl_headers": {"User-Agent": APK_UA_BROWSER},
                })
            for v in obj.values():
                walk(v)
        elif isinstance(obj, list):
            for x in obj:
                walk(x)

    walk(data)
    return out


# ---- 6. Vivo 应用商店 ----
def _vivo_item(it):
    pkg = it.get("package_name") or ""
    vid = str(it.get("id") or "")
    if not pkg or not vid:
        return None
    # Vivo 返回的 size 单位是 KB
    try:
        size = int(it.get("size") or 0) * 1024
    except Exception:
        size = 0
    return {
        "package": pkg,
        "name": it.get("title_zh") or it.get("title_en") or pkg,
        "seller": it.get("developer") or "Vivo 应用商店",
        "version": str(it.get("version_name") or ""),
        "version_code": str(it.get("version_code") or ""),
        "size": size,
        "icon": it.get("icon_url") or "",
        "source": "vivo",
        "pkg_type": "APK",
        "has_versions": False,
        "dl_url": "https://appstore.vivo.com.cn/appinfo/downloadApkFile?id=" + urllib.parse.quote(vid, safe=""),
        "dl_headers": {"User-Agent": APK_UA_BROWSER},
        "extra": {"app_id": vid},
    }


def vivo_search(query, limit=12):
    qs = urllib.parse.urlencode({
        "app_version": "2100", "page_index": "1", "apps_per_page": str(limit),
        "target": "local", "cfrom": "2", "key": query,
    })
    data = _http_json("https://h5-api.appstore.vivo.com.cn/h5appstore/search/result-list?" + qs, timeout=8)
    items = ((data.get("data") or {}).get("appSearchResponse") or {}).get("value") or []
    out = []
    for it in items[:limit]:
        if isinstance(it, dict):
            item = _vivo_item(it)
            if item:
                out.append(item)
    return out


def vivo_detail(app_id):
    data = _http_json("https://h5-api.appstore.vivo.com.cn/detailInfo?appId=" + urllib.parse.quote(str(app_id), safe=""), timeout=8)
    return _vivo_item(data) if isinstance(data, dict) else None


# ---- 7. F-Droid（支持官方 + 清华镜像回退）----
_FDROID_REPOS = [
    "https://f-droid.org/repo",
    "https://mirrors.tuna.tsinghua.edu.cn/fdroid/repo",
]


def fdroid_search(query, limit=12):
    qs = urllib.parse.urlencode({"q": query})
    _, _, raw = _http_read("https://search.f-droid.org/?" + qs, timeout=8)
    html = raw.decode("utf-8", "replace")
    out, seen = [], set()
    for m in re.finditer(r'<a[^>]+href="[^"]*?/packages/([A-Za-z0-9_.]+)/?"[^>]*>(.*?)</a>', html, re.S):
        pkg, inner = m.group(1), m.group(2)
        if pkg in seen:
            continue
        seen.add(pkg)
        nm = re.search(r'class="package-name"[^>]*>(.*?)</', inner, re.S)
        name = re.sub(r"<[^>]+>", "", nm.group(1)).strip() if nm else pkg
        im = re.search(r'<img[^>]+src="([^"]+)"', inner)
        icon = im.group(1) if im else ""
        if icon.startswith("/"):
            icon = "https://f-droid.org" + icon
        out.append({
            "package": pkg,
            "name": name or pkg,
            "seller": "F-Droid",
            "version": "",
            "version_code": "",
            "size": 0,
            "icon": icon,
            "source": "fdroid",
            "pkg_type": "APK",
            "has_versions": True,
        })
        if len(out) >= limit:
            break
    return out


def _fdroid_meta_from_gitlab(pkg):
    """当 f-droid.org 不可达时，从 GitLab fdroiddata 读取包版本列表，再走清华镜像下载。"""
    url = "https://gitlab.com/fdroid/fdroiddata/-/raw/master/metadata/%s.yml" % urllib.parse.quote(pkg, safe="")
    _, _, raw = _http_read(url, timeout=8)
    text = raw.decode("utf-8", "replace")
    nm = re.search(r"^(?:AutoName|Name):\s*(.+)$", text, re.M)
    name = nm.group(1).strip().strip("'\"") if nm else pkg
    vers = re.findall(r"-\s*versionName:\s*['\"]?([^'\"\n]+)['\"]?\s*\n\s*versionCode:\s*(\d+)", text)
    if not vers:
        cv = re.search(r"^CurrentVersion:\s*(.+)$", text, re.M)
        cc = re.search(r"^CurrentVersionCode:\s*(\d+)$", text, re.M)
        if cv and cc:
            vers = [(cv.group(1).strip().strip("'\""), cc.group(1))]
    packages = [{"versionName": v, "versionCode": int(c)} for v, c in reversed(vers)]
    return {"name": name, "packages": packages}


def fdroid_versions(pkg):
    packages = []
    try:
        d = _http_json("https://f-droid.org/api/v1/packages/" + urllib.parse.quote(pkg, safe=""), timeout=8)
        packages = d.get("packages") or []
    except Exception:
        try:
            packages = _fdroid_meta_from_gitlab(pkg).get("packages") or []
        except Exception:
            packages = []
    out = []
    for p in packages[:25]:
        vc = str(p.get("versionCode") or "")
        vn = str(p.get("versionName") or vc)
        if not vc:
            continue
        out.append({
            "version": vn,
            "version_code": vc,
            "date": "",
            "size": 0,
            "pkg_type": "APK",
            "arch": "",
            "source": "fdroid",
            "dl_url": "%s/%s_%s.apk" % (_FDROID_REPOS[0], pkg, vc),
            "fallback_urls": ["%s/%s_%s.apk" % (r, pkg, vc) for r in _FDROID_REPOS[1:]],
            "dl_headers": {"User-Agent": "F-Droid"},
        })
    return out


def fdroid_detail(pkg):
    vers = fdroid_versions(pkg)
    if not vers:
        return None
    top = vers[0]
    return {
        "package": pkg,
        "name": pkg,
        "seller": "F-Droid",
        "version": top["version"],
        "version_code": top["version_code"],
        "size": 0,
        "icon": "https://f-droid.org/repo/%s/en-US/icon.png" % pkg,
        "source": "fdroid",
        "pkg_type": "APK",
        "has_versions": True,
        "dl_url": top["dl_url"],
        "fallback_urls": top.get("fallback_urls") or [],
        "dl_headers": {"User-Agent": "F-Droid"},
    }


# ---- 8. GitHub Releases ----
def _gh_pick_apk(assets):
    apks = [a for a in (assets or [])
            if any((a.get("name") or "").lower().endswith(ext) for ext in APK_EXTS)]
    if not apks:
        return None
    def score(a):
        n = (a.get("name") or "").lower()
        return (
            1 if ("universal" in n or "all" in n) else 0,
            1 if ("arm64" in n or "v8a" in n) else 0,
            0 if ("x86" in n or "armeabi-v7a" in n) else 1,
            int(a.get("size") or 0),
        )
    return sorted(apks, key=score, reverse=True)[0]


def github_repo_detail(repo):
    hdrs = {"User-Agent": "ipa-web/" + VERSION, "Accept": "application/vnd.github+json"}
    rel = _http_json("https://api.github.com/repos/%s/releases/latest" % repo, headers=hdrs, timeout=8)
    best = _gh_pick_apk(rel.get("assets"))
    if not best:
        # 有些项目最新是 pre-release，扫一次 releases 列表
        rels = _http_json("https://api.github.com/repos/%s/releases?per_page=5" % repo, headers=hdrs, timeout=8)
        for r in rels or []:
            best = _gh_pick_apk(r.get("assets"))
            if best:
                rel = r
                break
    if not best:
        return None
    owner = repo.split("/")[0]
    ext = _guess_pkg_ext(best.get("name", ""))
    return {
        "package": "gh:" + repo,
        "name": repo.split("/")[-1],
        "seller": "GitHub · " + owner,
        "version": (rel.get("tag_name") or "").lstrip("v"),
        "version_code": "",
        "size": int(best.get("size") or 0),
        "icon": "https://github.com/%s.png?size=128" % owner,
        "source": "github",
        "pkg_type": ext.lstrip(".").upper(),
        "has_versions": True,
        "dl_url": best.get("browser_download_url") or "",
        "dl_headers": {"User-Agent": "ipa-web/" + VERSION},
        "extra": {"repo": repo, "asset_name": best.get("name") or ""},
    }


def github_versions(repo):
    hdrs = {"User-Agent": "ipa-web/" + VERSION, "Accept": "application/vnd.github+json"}
    rels = _http_json("https://api.github.com/repos/%s/releases?per_page=20" % repo, headers=hdrs, timeout=10)
    out = []
    for rel in rels or []:
        tag = (rel.get("tag_name") or "").lstrip("v")
        date = str(rel.get("published_at") or "")[:10]
        for a in rel.get("assets") or []:
            aname = a.get("name") or ""
            if not any(aname.lower().endswith(ext) for ext in APK_EXTS):
                continue
            ext = _guess_pkg_ext(aname)
            out.append({
                "version": "%s (%s)" % (tag, aname),
                "version_code": tag,
                "date": date,
                "size": int(a.get("size") or 0),
                "pkg_type": ext.lstrip(".").upper(),
                "arch": "",
                "source": "github",
                "dl_url": a.get("browser_download_url") or "",
                "dl_headers": {"User-Agent": "ipa-web/" + VERSION},
            })
    return out


def github_search(query, limit=6):
    hdrs = {"User-Agent": "ipa-web/" + VERSION, "Accept": "application/vnd.github+json"}
    q = urllib.parse.urlencode({"q": query + " android", "sort": "stars", "per_page": str(limit)})
    data = _http_json("https://api.github.com/search/repositories?" + q, headers=hdrs, timeout=8)
    repos = [it.get("full_name") for it in (data.get("items") or []) if it.get("full_name")]
    out = []
    with concurrent.futures.ThreadPoolExecutor(max_workers=4) as ex:
        futs = [ex.submit(github_repo_detail, r) for r in repos[:limit]]
        for fut in futs:
            try:
                it = fut.result(timeout=8)
                if it:
                    out.append(it)
            except Exception:
                pass
    return out


# ---- 聚合搜索 / 查版本 / 下载解析 ----
def _cache_and_slim_apk(item):
    token = secrets.token_hex(8)
    apk_cache_put(token, item)
    return {
        "token": token,
        "package": item.get("package", ""),
        "name": item.get("name", ""),
        "seller": item.get("seller", ""),
        "version": item.get("version", ""),
        "size": int(item.get("size") or 0),
        "icon": item.get("icon", ""),
        "source": item.get("source", ""),
        "source_name": APK_SOURCE_NAMES.get(item.get("source", ""), item.get("source", "")),
        "pkg_type": item.get("pkg_type", "APK"),
        "has_versions": bool(item.get("has_versions")),
        "extra": item.get("extra") or {},
    }


def search_android(term, source="auto"):
    kind, val = _extract_android_target(term)
    if kind == "direct":
        fname = os.path.basename(urllib.parse.urlparse(val).path) or "app.apk"
        ext = _guess_pkg_ext(val)
        item = {
            "package": fname,
            "name": fname,
            "seller": urllib.parse.urlparse(val).netloc,
            "version": "",
            "size": 0,
            "icon": "",
            "source": "direct",
            "pkg_type": ext.lstrip(".").upper(),
            "has_versions": False,
            "dl_url": val,
            "dl_headers": {"User-Agent": APK_UA_BROWSER},
        }
        return [_cache_and_slim_apk(item)]
    if kind == "github":
        it = github_repo_detail(val)
        return [_cache_and_slim_apk(it)] if it else []
    if kind == "huawei_id":
        it = huawei_detail(app_id=val)
        return [_cache_and_slim_apk(it)] if it else []
    if kind == "vivo_id":
        it = vivo_detail(val)
        return [_cache_and_slim_apk(it)] if it else []

    if source != "auto":
        sources = [source]
    elif kind == "package":
        sources = ["apkpure", "huawei", "tencent", "uptodown", "aptoide", "fdroid"]
    else:
        sources = ["apkpure", "huawei", "tencent", "vivo", "uptodown", "aptoide", "fdroid"]

    def run_one(src):
        if kind == "package":
            fn = {
                "apkpure": apkpure_detail,
                "huawei": lambda p: huawei_detail(pkg=p),
                "tencent": tencent_detail,
                "uptodown": uptodown_detail,
                "aptoide": aptoide_detail,
                "fdroid": fdroid_detail,
                "vivo": lambda p: next((x for x in vivo_search(p, 5) if x["package"] == p), None),
                "github": lambda p: None,
            }.get(src)
            r = fn(val) if fn else None
            return [r] if r else []
        fn = {
            "apkpure": apkpure_search,
            "huawei": huawei_search,
            "tencent": tencent_search,
            "vivo": vivo_search,
            "uptodown": uptodown_search,
            "aptoide": aptoide_search,
            "fdroid": fdroid_search,
            "github": github_search,
        }.get(src)
        return fn(val) if fn else []

    raw_items = []
    ex = concurrent.futures.ThreadPoolExecutor(max_workers=len(sources))
    futs = {ex.submit(run_one, s): s for s in sources}
    try:
        for fut in concurrent.futures.as_completed(futs, timeout=10):
            src = futs[fut]
            try:
                res = fut.result() or []
                raw_items.extend(res)
            except Exception as e:
                log("安卓源搜索失败", src, val, e)
    except concurrent.futures.TimeoutError:
        log("安卓部分源搜索超时，已返回其余源结果", val)
    finally:
        ex.shutdown(wait=False)

    # 关键词搜索时按 (package, source) 去重；如果全部源聚合，把精确命中和有直链的排前面
    out, seen = [], set()
    q_low = val.lower()
    for it in raw_items:
        key = (it.get("package", ""), it.get("source", ""))
        if not key[0] or key in seen:
            continue
        seen.add(key)
        out.append(it)

    if source == "auto":
        src_rank = {"apkpure": 0, "huawei": 1, "tencent": 2, "vivo": 3, "uptodown": 4, "aptoide": 5, "fdroid": 6, "github": 7}
        def rank(it):
            name_l = (it.get("name") or "").lower()
            pkg_l = (it.get("package") or "").lower()
            exact = 0 if (pkg_l == q_low or name_l == q_low) else (1 if q_low in name_l or q_low in pkg_l else 2)
            has_icon = 0 if it.get("icon") else 1
            return (exact, has_icon, src_rank.get(it.get("source", ""), 9))
        out.sort(key=rank)

    return [_cache_and_slim_apk(it) for it in out[:30]]


def android_versions(pkg, source, extra=None):
    extra = extra or {}
    if source == "github" or pkg.startswith("gh:"):
        repo = extra.get("repo") or (pkg[3:] if pkg.startswith("gh:") else pkg)
        vers = github_versions(repo)
    elif source == "apkpure":
        vers = apkpure_versions(pkg)
    elif source == "uptodown":
        vers = uptodown_versions(pkg, extra.get("app_id", ""))
    elif source == "fdroid":
        vers = fdroid_versions(pkg)
    else:
        # 其他源（如华为/应用宝/Vivo/Aptoide）本身不提供历史版，尝试从 APKPure / Uptodown / F-Droid 查同包名历史版
        vers = []
        for fn in (apkpure_versions, uptodown_versions, fdroid_versions):
            try:
                vers = fn(pkg)
                if vers:
                    break
            except Exception:
                pass
    out = []
    for v in vers[:30]:
        tok = secrets.token_hex(8)
        apk_cache_put(tok, dict(v, package=pkg))
        out.append({
            "token": tok,
            "version": v.get("version", ""),
            "version_code": v.get("version_code", ""),
            "date": v.get("date", ""),
            "size": int(v.get("size") or 0),
            "pkg_type": v.get("pkg_type", "APK"),
            "arch": v.get("arch", ""),
            "source": v.get("source", source),
            "source_name": APK_SOURCE_NAMES.get(v.get("source", source), source),
        })
    return out


def _download_apk_stream(url, dest_dir, base_name, version, headers=None, expected_ext=".apk", timeout=7200):
    hdrs = {"User-Agent": APK_UA_BROWSER}
    if headers:
        hdrs.update(headers)
    req = urllib.request.Request(url, headers=hdrs)
    with urllib.request.urlopen(req, timeout=15) as r:
        ext = _guess_pkg_ext(r.geturl() or url, r.headers, expected_ext)
        total = int(r.headers.get("Content-Length") or 0)
        fname = safe_filename(base_name, version, ext=ext)
        part = os.path.join(dest_dir, fname + ".part")
        final = os.path.join(dest_dir, fname)
        got = 0
        first_chunk = b""
        with open(part, "wb") as f:
            while True:
                chunk = r.read(256 * 1024)
                if not chunk:
                    break
                if not first_chunk:
                    first_chunk = chunk[:16]
                    # APK / XAPK / APKS / AAB 都是 ZIP 格式（PK\x03\x04）
                    if not first_chunk.startswith(b"PK"):
                        f.close()
                        os.remove(part)
                        ct = r.headers.get("Content-Type", "")
                        raise RuntimeError("返回的不是有效安装包（Content-Type: %s），可能被源站拦截" % ct)
                f.write(chunk)
                got += len(chunk)
        if total > 0 and got < total:
            os.remove(part)
            raise RuntimeError("文件下载不完整（%d / %d 字节）" % (got, total))
        if got < 4096:
            os.remove(part)
            raise RuntimeError("下载到的文件过小（%d 字节），不是有效安装包" % got)
        os.replace(part, final)
        return final, fname, got


def _apkeep_fallback(pkg, dest_dir, version=""):
    """如果系统装了 EFF apkeep，作为 APKPure / F-Droid 的额外下载兜底。"""
    ak = CFG.get("apkeep_bin") or os.path.join(BASE_DIR, "bin", "apkeep")
    if not (ak and os.path.isfile(ak) and os.access(ak, os.X_OK)):
        return None
    app_arg = "%s@%s" % (pkg, version) if version else pkg
    attempts = [
        [ak, "-a", app_arg, "-d", "apk-pure", "-o", "acknowledge_dangers=true", dest_dir],
        [ak, "-a", app_arg, "-d", "f-droid", dest_dir],
    ]
    for cmd in attempts:
        try:
            p = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=1800)
            if p.returncode == 0:
                for root, _, files in os.walk(dest_dir):
                    for fn in files:
                        if any(fn.lower().endswith(ext) for ext in APK_EXTS):
                            full = os.path.join(root, fn)
                            if os.path.getsize(full) > 4096:
                                return full, fn, os.path.getsize(full)
        except Exception:
            pass
    return None


def download_android_job(job):
    pkg = job["app_id"]
    src = job.get("source", "")
    cached = job.get("apk_info") or {}
    ver = job.get("version", "")
    name = job.get("name") or pkg
    errors = []

    def try_urls(urls, hdrs, ext_hint, label):
        for u in urls:
            if not u:
                continue
            try:
                return _download_apk_stream(u, job["dir"], name, ver, headers=hdrs, expected_ext=ext_hint)
            except Exception as e:
                errors.append("%s: %s" % (label, e))
        return None

    # 1. 优先用已拿到的直链（如 APKPure / 华为 / Vivo / 应用宝 / Aptoide / GitHub / 直链）
    if cached.get("dl_url"):
        urls = [cached["dl_url"]] + list(cached.get("fallback_urls") or [])
        ext_hint = "." + (cached.get("pkg_type") or "apk").lower()
        res = try_urls(urls, cached.get("dl_headers"), ext_hint, APK_SOURCE_NAMES.get(src, src))
        if res:
            return res

    # 2. 按指定源解析下载链接（例如 Uptodown 或搜索结果里不含直链的应用宝）
    if src == "uptodown":
        try:
            u, hdrs, ext_hint, rver = uptodown_resolve_download(pkg, cached.get("extra"), ver)
            if rver and not ver:
                ver = rver
                job["version"] = rver
            res = try_urls([u], hdrs, ext_hint, "Uptodown")
            if res:
                return res
        except Exception as e:
            errors.append("Uptodown: %s" % e)
    elif src == "tencent":
        try:
            d = tencent_detail(pkg)
            if d and d.get("dl_url"):
                res = try_urls([d["dl_url"]], d.get("dl_headers"), ".apk", "腾讯应用宝")
                if res:
                    return res
        except Exception as e:
            errors.append("腾讯应用宝: %s" % e)
    elif src == "huawei":
        try:
            d = huawei_detail(pkg=pkg, app_id=(cached.get("extra") or {}).get("app_id", ""))
            if d and d.get("dl_url"):
                res = try_urls([d["dl_url"]], d.get("dl_headers"), ".apk", "华为应用市场")
                if res:
                    return res
        except Exception as e:
            errors.append("华为应用市场: %s" % e)

    # 3. 多源自动回退（当包名合法且不是直链/GitHub 时）
    if _is_pkg_name(pkg) and not ver:
        fallbacks = [
            ("apkpure", apkpure_detail),
            ("huawei", lambda p: huawei_detail(pkg=p)),
            ("tencent", tencent_detail),
            ("aptoide", aptoide_detail),
            ("fdroid", fdroid_detail),
        ]
        for fb_id, fb_fn in fallbacks:
            if fb_id == src:
                continue
            try:
                d = fb_fn(pkg)
                if d and d.get("dl_url"):
                    urls = [d["dl_url"]] + list(d.get("fallback_urls") or [])
                    ext_hint = "." + (d.get("pkg_type") or "apk").lower()
                    res = try_urls(urls, d.get("dl_headers"), ext_hint, APK_SOURCE_NAMES.get(fb_id, fb_id))
                    if res:
                        job["source"] = fb_id
                        if d.get("version") and not job.get("version"):
                            job["version"] = d["version"]
                        return res
            except Exception as e:
                errors.append("%s: %s" % (APK_SOURCE_NAMES.get(fb_id, fb_id), e))
        # 再试 Uptodown
        if src != "uptodown":
            try:
                u, hdrs, ext_hint, rver = uptodown_resolve_download(pkg)
                res = try_urls([u], hdrs, ext_hint, "Uptodown")
                if res:
                    job["source"] = "uptodown"
                    if rver and not job.get("version"):
                        job["version"] = rver
                    return res
            except Exception as e:
                errors.append("Uptodown: %s" % e)

    # 4. apkeep 命令行兜底
    if _is_pkg_name(pkg):
        res = _apkeep_fallback(pkg, job["dir"], ver)
        if res:
            job["source"] = "apkeep"
            return res

    raise RuntimeError("所有可用安卓源都下载失败：" + ("；".join(errors[-3:]) if errors else "未找到安装包"))


#----------------------------------------------------------------------
# 下载任务。同时只跑 max_concurrent 个任务，小内存机器默认 1 个，其余排队。
#----------------------------------------------------------------------
JOBS = {}
JOBS_LOCK = threading.Lock()
SLOTS = threading.Semaphore(max(1, int(CFG["max_concurrent"])))


def dir_size(path):
    total = 0
    for root, _, files in os.walk(path):
        for name in files:
            try:
                total += os.path.getsize(os.path.join(root, name))
            except OSError:
                pass
    return total


def safe_filename(name, version, ext=".ipa"):
    base = re.sub(r'[\\/:*?"<>|\x00-\x1f]+', "_", name).strip(" .") or "app"
    ver = re.sub(r"[^0-9A-Za-z._-]+", "_", version or "")
    if not ext.startswith("."):
        ext = "." + ext
    if base.lower().endswith(ext.lower()):
        base = base[:-len(ext)]
    return "%s_%s%s" % (base[:80], ver, ext) if ver else "%s%s" % (base[:80], ext)


def job_public(j):
    d = {k: j.get(k) for k in ("id", "platform", "app_id", "name", "version", "icon", "size",
                                "account", "country", "source", "source_name", "pkg_type",
                                "status", "error", "created", "finished", "filename")}
    if j["status"] == "running":
        d["bytes"] = dir_size(j["dir"])
    elif j["status"] == "done":
        d["bytes"] = j.get("file_size", 0)
        d["expires"] = j["finished"] + CFG["retention_minutes"] * 60
    else:
        d["bytes"] = 0
    with JOBS_LOCK:
        d["queue_pos"] = sum(1 for o in JOBS.values()
                             if o["status"] == "queued" and o["created"] < j["created"]) + 1
    return d


def run_job(job):
    with SLOTS:
        if job["status"] == "cancelled":
            return
        job["status"] = "running"
        job["started"] = time.time()
        if job.get("platform") == "android":
            log("开始下载安卓", job["app_id"], job["name"], job.get("source"), job.get("version") or "最新版")
            try:
                fpath, fname, fsize = download_android_job(job)
                job["file"] = fpath
                job["filename"] = fname
                job["file_size"] = fsize
                job["source_name"] = APK_SOURCE_NAMES.get(job.get("source", ""), job.get("source", ""))
                job["pkg_type"] = os.path.splitext(fname)[1].lstrip(".").upper() or "APK"
                job["status"] = "done"
                log("安卓下载完成", job["app_id"], fname, fsize, "字节")
            except Exception as e:
                job["status"] = "error"
                job["error"] = str(e)
                log("安卓下载失败", job["app_id"], job["name"], e)
                shutil.rmtree(job["dir"], ignore_errors=True)
            job["finished"] = time.time()
            return

        log("开始下载", job["app_id"], job["name"], job.get("ext_ver") or "最新版")
        args = ["download", "-i", str(job["app_id"]), "--purchase", "-o", job["dir"]]
        if job.get("ext_ver"):
            args += ["--external-version-id", job["ext_ver"]]
        # 大 App 可能好几个 G，给足两个小时。
        used_dl = pick_ipatool_bin(args) != CFG["ipatool_bin"]
        rc, out = ipatool(args, timeout=7200, home=job["home"])
        # 低内存轻量引擎遇到已下架 App 等仅新版支持的场景，尝试回退新版；若新版被 OOM 杀掉则保留轻量引擎原错。
        if rc != 0 and used_dl:
            low_out = (out or "").lower()
            if "no longer available" in low_out or "invalid response" in low_out:
                log("轻量引擎未命中，尝试新版 ipatool 重试", job["app_id"], job["name"])
                rc2, out2 = ipatool(args, timeout=7200, home=job["home"], force_main=True)
                if rc2 == 0 or (rc2 is not None and rc2 > 0):
                    rc, out = rc2, out2
        info = last_json(out)
        ipa = None
        if rc == 0:
            cand = info.get("output")
            if cand and os.path.isfile(cand):
                ipa = cand
            else:
                for root, _, files in os.walk(job["dir"]):
                    for n in files:
                        if n.endswith(".ipa"):
                            ipa = os.path.join(root, n)
        if ipa:
            job["file"] = ipa
            job["file_size"] = os.path.getsize(ipa)
            job["status"] = "done"
            log("下载完成", job["app_id"], job["name"], job["file_size"], "字节")
        else:
            job["status"] = "error"
            job["error"] = explain_error(out, rc)
            log("下载失败", job["app_id"], job["name"], "rc=%s" % rc, (out or "").strip()[-500:])
            shutil.rmtree(job["dir"], ignore_errors=True)
        job["finished"] = time.time()


def new_job(app_id, ext_ver=""):
    info = {}
    try:
        res = itunes("lookup", {"id": app_id}).get("results") or []
        if res:
            info = slim_app(res[0])
    except Exception as e:
        log("查 App 信息失败", app_id, e)
    jid = secrets.token_hex(8)
    job = {
        "id": jid,
        "platform": "ios",
        "home": CFG["home_dir"],
        "account": CFG["apple_id"],
        "country": CFG["country"],
        "source": "appstore",
        "source_name": "App Store",
        "pkg_type": "IPA",
        "app_id": app_id,
        "ext_ver": ext_ver,
        "name": info.get("name") or str(app_id),
        "version": "" if ext_ver else info.get("version", ""),
        "icon": info.get("icon", ""),
        "size": info.get("size", 0),
        "status": "queued",
        "error": "",
        "created": time.time(),
        "finished": 0,
        "dir": os.path.join(CFG["data_dir"], jid),
    }
    job["filename"] = safe_filename(job["name"], job["version"] or ext_ver, ext=".ipa")
    os.makedirs(job["dir"], exist_ok=True)
    with JOBS_LOCK:
        JOBS[jid] = job
    threading.Thread(target=run_job, args=(job,), daemon=True).start()
    return job


def new_android_job(pkg, source="", version="", name="", icon="", size=0, cached=None):
    cached = cached or {}
    pkg = pkg or cached.get("package") or ""
    source = source or cached.get("source") or "auto"
    version = version or cached.get("version") or ""
    name = name or cached.get("name") or pkg
    icon = icon or cached.get("icon") or ""
    size = int(size or cached.get("size") or 0)
    pkg_type = (cached.get("pkg_type") or "APK").upper()
    jid = secrets.token_hex(8)
    job = {
        "id": jid,
        "platform": "android",
        "home": "",
        "account": "",
        "country": "",
        "source": source,
        "source_name": APK_SOURCE_NAMES.get(source, source),
        "pkg_type": pkg_type,
        "app_id": pkg,
        "ext_ver": version,
        "name": name,
        "version": version,
        "icon": icon,
        "size": size,
        "apk_info": cached,
        "status": "queued",
        "error": "",
        "created": time.time(),
        "finished": 0,
        "dir": os.path.join(CFG["data_dir"], jid),
    }
    job["filename"] = safe_filename(name, version, ext="." + pkg_type.lower())
    os.makedirs(job["dir"], exist_ok=True)
    with JOBS_LOCK:
        JOBS[jid] = job
    threading.Thread(target=run_job, args=(job,), daemon=True).start()
    return job


def cleaner():
    """每分钟扫一遍：过了保留时间的 ipa 删掉，出错的任务一小时后从列表里拿掉。"""
    while True:
        time.sleep(60)
        now = time.time()
        keep = CFG["retention_minutes"] * 60
        with JOBS_LOCK:
            items = list(JOBS.items())
        for jid, j in items:
            gone = False
            if j["status"] == "done" and now - j["finished"] > keep and not j.get("sending"):
                gone = True
            elif j["status"] in ("error", "cancelled") and now - j["finished"] > 3600:
                gone = True
            if gone:
                shutil.rmtree(j["dir"], ignore_errors=True)
                with JOBS_LOCK:
                    JOBS.pop(jid, None)
        maybe_update_ipatool(now)


#----------------------------------------------------------------------
# Apple ID 状态。auth info 要几秒，缓存一分钟。
#----------------------------------------------------------------------
ACCOUNT = {"t": 0, "data": None, "home": ""}
ACCOUNT_LOCK = threading.Lock()


def account_info(force=False):
    with ACCOUNT_LOCK:
        home = CFG["home_dir"]
        if not force and ACCOUNT["data"] and ACCOUNT["home"] == home and time.time() - ACCOUNT["t"] < 60:
            return ACCOUNT["data"]
        rc, out = ipatool(["auth", "info"], timeout=60, home=home)
        j = last_json(out)
        if rc == 0 and j.get("success", True):
            data = {"logged_in": True, "email": j.get("email", CFG["apple_id"]), "name": j.get("name", "")}
        else:
            data = {"logged_in": False, "email": CFG["apple_id"], "error": explain_error(out, rc)}
        # 只缓存「已登录」：刚在 VPS 上登录完，网页马上就能看到。
        ACCOUNT.update(t=time.time() if data["logged_in"] else 0, data=data, home=home)
        return data


#----------------------------------------------------------------------
# 网页。
#----------------------------------------------------------------------
INDEX_PATH = os.path.join(HERE, "index.html")
COOKIE = "ipaweb"


class Handler(BaseHTTPRequestHandler):
    server_version = "ipa-web/" + VERSION
    protocol_version = "HTTP/1.1"

    def log_message(self, fmt, *args):
        pass

    # ---- 小工具 ----
    def client_ip(self):
        ip = self.client_address[0]
        if CFG["trust_proxy"] and ip in ("127.0.0.1", "::1"):
            fwd = self.headers.get("X-Forwarded-For", "")
            if fwd:
                ip = fwd.split(",")[0].strip()
        return ip

    def cookie(self):
        for part in self.headers.get("Cookie", "").split(";"):
            k, _, v = part.strip().partition("=")
            if k == COOKIE:
                return v
        return ""

    def authed(self):
        return session_ok(self.cookie())

    def send_json(self, obj, code=200, extra=None):
        body = json.dumps(obj, ensure_ascii=False).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        for k, v in (extra or []):
            self.send_header(k, v)
        self.end_headers()
        self.wfile.write(body)

    def read_body(self):
        n = int(self.headers.get("Content-Length") or 0)
        if n <= 0 or n > 65536:
            return {}
        try:
            return json.loads(self.rfile.read(n).decode("utf-8"))
        except ValueError:
            return {}

    def need_auth(self):
        if self.authed():
            return False
        self.send_json({"error": "请先登录"}, 401)
        return True

    # ---- 路由 ----
    def do_GET(self):
        reload_config()
        u = urllib.parse.urlparse(self.path)
        q = urllib.parse.parse_qs(u.query)
        path = u.path
        try:
            if path in ("/", "/index.html"):
                return self.send_index()
            if path == "/api/me":
                return self.send_json({"authed": self.authed(), "version": VERSION})
            if self.need_auth():
                return
            if path == "/api/status":
                ak = CFG.get("apkeep_bin") or os.path.join(BASE_DIR, "bin", "apkeep")
                return self.send_json({
                    "account": account_info(force=q.get("force") == ["1"]),
                    "country": CFG["country"],
                    "accounts": [{"email": a.get("email", ""), "country": a.get("country", ""),
                                  "active": a.get("id") == CFG.get("active")}
                                 for a in (CFG.get("accounts") or [])],
                    "retention_minutes": CFG["retention_minutes"],
                    "max_concurrent": CFG["max_concurrent"],
                    "disk_free": shutil.disk_usage(CFG["data_dir"]).free,
                    "android_sources": APK_SOURCES,
                    "has_apkeep": bool(ak and os.path.isfile(ak) and os.access(ak, os.X_OK)),
                })
            if path == "/api/search":
                term = (q.get("q") or [""])[0]
                if not term.strip():
                    return self.send_json({"results": []})
                try:
                    return self.send_json({"results": search_apps(term)})
                except Exception as e:
                    return self.send_json({"error": "搜索失败：%s" % e}, 502)
            if path == "/api/android/search":
                term = (q.get("q") or [""])[0]
                src = (q.get("source") or ["auto"])[0]
                if src not in APK_SOURCE_NAMES:
                    src = "auto"
                if not term.strip():
                    return self.send_json({"results": []})
                try:
                    return self.send_json({"results": search_android(term, src)})
                except Exception as e:
                    return self.send_json({"error": "安卓搜索失败：%s" % e}, 502)
            if path == "/api/android/versions":
                pkg = (q.get("pkg") or [""])[0].strip()
                src = (q.get("source") or [""])[0].strip()
                tok = (q.get("token") or [""])[0].strip()
                cached = apk_cache_get(tok) if tok else None
                if cached:
                    pkg = pkg or cached.get("package", "")
                    src = src or cached.get("source", "")
                if not pkg:
                    return self.send_json({"error": "缺少包名"}, 400)
                try:
                    vers = android_versions(pkg, src, (cached or {}).get("extra"))
                    return self.send_json({"versions": vers})
                except Exception as e:
                    return self.send_json({"error": "查历史版本失败：%s" % e}, 502)
            if path == "/api/versions":
                return self.api_versions(q)
            if path == "/api/version-meta":
                return self.api_version_meta(q)
            if path == "/api/jobs":
                with JOBS_LOCK:
                    jobs = sorted(JOBS.values(), key=lambda j: -j["created"])
                return self.send_json({"jobs": [job_public(j) for j in jobs]})
            m = re.fullmatch(r"/api/file/([0-9a-f]{16})", path)
            if m:
                return self.send_file(m.group(1))
            self.send_json({"error": "not found"}, 404)
        except (BrokenPipeError, ConnectionResetError):
            pass

    def do_POST(self):
        reload_config()
        path = urllib.parse.urlparse(self.path).path
        try:
            if path == "/api/login":
                return self.api_login()
            if path == "/api/logout":
                return self.send_json({"ok": True}, extra=[(
                    "Set-Cookie", "%s=; Path=/; Max-Age=0; HttpOnly; SameSite=Strict" % COOKIE)])
            if self.need_auth():
                return
            body = self.read_body()
            if path == "/api/download":
                app_id = str(body.get("id", "")).strip()
                ext_ver = str(body.get("ext_ver", "") or "").strip()
                if not app_id.isdigit() or (ext_ver and not ext_ver.isdigit()):
                    return self.send_json({"error": "App ID 不对"}, 400)
                if shutil.disk_usage(CFG["data_dir"]).free < 300 * 1024 * 1024:
                    return self.send_json({"error": "VPS 硬盘剩余不到 300MB，先清理一下再下"}, 507)
                with JOBS_LOCK:
                    for j in JOBS.values():
                        if (j.get("platform", "ios") == "ios" and j["app_id"] == app_id and j["ext_ver"] == ext_ver
                                and j["home"] == CFG["home_dir"] and j["status"] in ("queued", "running", "done")):
                            return self.send_json({"job": j["id"], "existing": True})
                job = new_job(app_id, ext_ver)
                return self.send_json({"job": job["id"]})
            if path == "/api/android/download":
                tok = str(body.get("token", "") or "").strip()
                cached = apk_cache_get(tok) if tok else None
                pkg = str(body.get("package", "") or (cached or {}).get("package", "")).strip()
                src = str(body.get("source", "") or (cached or {}).get("source", "") or "auto").strip()
                ver = str(body.get("version", "") or (cached or {}).get("version", "")).strip()
                name = str(body.get("name", "") or (cached or {}).get("name", "") or pkg).strip()
                icon = str(body.get("icon", "") or (cached or {}).get("icon", "")).strip()
                size = int(body.get("size") or (cached or {}).get("size") or 0)
                if not pkg:
                    return self.send_json({"error": "缺少安卓包名或下载信息（搜索结果已过期请重搜）"}, 400)
                if shutil.disk_usage(CFG["data_dir"]).free < 300 * 1024 * 1024:
                    return self.send_json({"error": "VPS 硬盘剩余不到 300MB，先清理一下再下"}, 507)
                with JOBS_LOCK:
                    for j in JOBS.values():
                        if (j.get("platform") == "android" and j["app_id"] == pkg and j.get("source") == src
                                and j.get("version", "") == ver and j["status"] in ("queued", "running", "done")):
                            return self.send_json({"job": j["id"], "existing": True})
                job = new_android_job(pkg, src, ver, name, icon, size, cached=cached)
                return self.send_json({"job": job["id"]})
            m = re.fullmatch(r"/api/jobs/([0-9a-f]{16})/delete", path)
            if m:
                with JOBS_LOCK:
                    j = JOBS.get(m.group(1))
                if not j:
                    return self.send_json({"ok": True})
                if j["status"] == "running":
                    return self.send_json({"error": "正在下载的任务删不了，等它下完"}, 409)
                if j["status"] == "queued":
                    j["status"] = "cancelled"
                    j["finished"] = time.time()
                shutil.rmtree(j["dir"], ignore_errors=True)
                with JOBS_LOCK:
                    JOBS.pop(j["id"], None)
                return self.send_json({"ok": True})
            self.send_json({"error": "not found"}, 404)
        except (BrokenPipeError, ConnectionResetError):
            pass

    # ---- 具体功能 ----
    def send_index(self):
        with open(INDEX_PATH, "rb") as f:
            body = f.read()
        self.send_response(200)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-cache")
        self.send_header("X-Frame-Options", "DENY")
        self.send_header("Referrer-Policy", "no-referrer")
        self.end_headers()
        self.wfile.write(body)

    def api_login(self):
        ip = self.client_ip()
        if login_blocked(ip):
            return self.send_json({"error": "输错太多次了，10 分钟后再试"}, 429)
        body = self.read_body()
        if not check_password(str(body.get("password", ""))):
            login_failed(ip)
            time.sleep(1)
            return self.send_json({"error": "密码不对"}, 403)
        secure = "; Secure" if self.headers.get("X-Forwarded-Proto") == "https" else ""
        cookie = "%s=%s; Path=/; Max-Age=%d; HttpOnly; SameSite=Strict%s" % (
            COOKIE, make_session(), SESSION_DAYS * 86400, secure)
        self.send_json({"ok": True}, extra=[("Set-Cookie", cookie)])

    def api_versions(self, q):
        app_id = (q.get("id") or [""])[0]
        if not app_id.isdigit():
            return self.send_json({"error": "App ID 不对"}, 400)
        rc, out = ipatool(["list-versions", "-i", app_id], timeout=180)
        if rc != 0:
            return self.send_json({"error": explain_error(out, rc)}, 502)
        j = last_json(out)
        ids = j.get("externalVersionIdentifiers")
        if not isinstance(ids, list):
            ids = next((v for v in j.values() if isinstance(v, list)), [])
        ids = [str(x) for x in ids]
        # 苹果返回的是从旧到新，网页上新的放前面。
        ids.reverse()
        self.send_json({"versions": ids, "latest": j.get("latestExternalVersionID", "")})

    def api_version_meta(self, q):
        app_id = (q.get("id") or [""])[0]
        ver = (q.get("ver") or [""])[0]
        if not app_id.isdigit() or not ver.isdigit():
            return self.send_json({"error": "参数不对"}, 400)
        rc, out = ipatool(["get-version-metadata", "-i", app_id, "--external-version-id", ver], timeout=180)
        if rc != 0:
            return self.send_json({"error": explain_error(out, rc)}, 502)
        j = last_json(out)
        self.send_json({
            "display": j.get("displayVersion") or j.get("version") or "",
            "date": j.get("releaseDate") or "",
        })

    def send_file(self, jid):
        if not self.authed():
            return self.send_json({"error": "请先登录"}, 401)
        with JOBS_LOCK:
            j = JOBS.get(jid)
        if not j or j["status"] != "done" or not os.path.isfile(j.get("file", "")):
            return self.send_json({"error": "文件不在了（可能过了保留时间），重新下载一次"}, 404)
        size = os.path.getsize(j["file"])
        # 支持断点续传：网断了浏览器能接着下。
        start, end = 0, size - 1
        rng = self.headers.get("Range", "")
        m = re.fullmatch(r"bytes=(\d*)-(\d*)", rng.strip())
        partial = False
        if m and (m.group(1) or m.group(2)):
            if m.group(1):
                start = int(m.group(1))
                if m.group(2):
                    end = min(int(m.group(2)), size - 1)
            else:
                start = max(0, size - int(m.group(2)))
            if start > end:
                self.send_response(416)
                self.send_header("Content-Range", "bytes */%d" % size)
                self.send_header("Content-Length", "0")
                self.end_headers()
                return
            partial = True
        name = j["filename"]
        ascii_name = re.sub(r"[^A-Za-z0-9._-]+", "_", name) or "app.ipa"
        self.send_response(206 if partial else 200)
        self.send_header("Content-Type", "application/octet-stream")
        self.send_header("Content-Disposition", "attachment; filename=\"%s\"; filename*=UTF-8''%s" % (
            ascii_name, urllib.parse.quote(name)))
        self.send_header("Accept-Ranges", "bytes")
        self.send_header("Content-Length", str(end - start + 1))
        if partial:
            self.send_header("Content-Range", "bytes %d-%d/%d" % (start, end, size))
        self.end_headers()
        j["sending"] = j.get("sending", 0) + 1
        try:
            with open(j["file"], "rb") as f:
                f.seek(start)
                left = end - start + 1
                while left > 0:
                    chunk = f.read(min(256 * 1024, left))
                    if not chunk:
                        break
                    self.wfile.write(chunk)
                    left -= len(chunk)
        finally:
            j["sending"] -= 1


class Server(ThreadingMixIn, HTTPServer):
    daemon_threads = True
    allow_reuse_address = True
    request_queue_size = 64

    def __init__(self, addr, handler):
        if ":" in addr[0]:
            self.address_family = socket.AF_INET6
        HTTPServer.__init__(self, addr, handler)

    def server_bind(self):
        # 监听 :: 时顺便收 IPv4，127.0.0.1 也能访问。
        if self.address_family == socket.AF_INET6:
            try:
                self.socket.setsockopt(socket.IPPROTO_IPV6, socket.IPV6_V6ONLY, 0)
            except (OSError, AttributeError):
                pass
        HTTPServer.server_bind(self)


def cleanup_stale_tmp():
    """清理上次被强杀后残留在硬盘临时目录和 /tmp(tmpfs) 里的 ipatool 临时文件。"""
    os.makedirs(TMP_ROOT, exist_ok=True)
    for name in os.listdir(TMP_ROOT):
        if name.startswith("run-") or name.startswith("ipatool-"):
            shutil.rmtree(os.path.join(TMP_ROOT, name), ignore_errors=True)
    try:
        for name in os.listdir("/tmp"):
            if name.startswith("ipatool-"):
                shutil.rmtree(os.path.join("/tmp", name), ignore_errors=True)
    except OSError:
        pass


def main():
    if CFG["low_memory"]:
        # 每个连接一个线程，线程栈调小一点。
        threading.stack_size(512 * 1024)
    # 上次没传完的文件和残留临时目录，重启后直接清掉，避免占硬盘或 tmpfs 内存。
    for name in os.listdir(CFG["data_dir"]):
        shutil.rmtree(os.path.join(CFG["data_dir"], name), ignore_errors=True)
    cleanup_stale_tmp()
    threading.Thread(target=cleaner, daemon=True).start()
    host, port = CFG["listen_host"], int(CFG["listen_port"])
    try:
        srv = Server((host, port), Handler)
    except OSError as e:
        # 有的容器关了 IPv6，监听 :: 会失败，退回只听 IPv4。
        if host != "::":
            raise
        log("监听 IPv6 失败（%s），改为只监听 IPv4" % e)
        host = "0.0.0.0"
        srv = Server((host, port), Handler)
    CFG["listen_host"] = host
    signal.signal(signal.SIGTERM, lambda *_: (srv.server_close(), sys.exit(0)))
    log("ipa-web %s 已启动，监听 %s:%s" % (VERSION, CFG["listen_host"], CFG["listen_port"]))
    if CFG["low_memory"] and pick_ipatool_bin(["download"]) != CFG["ipatool_bin"]:
        log("低内存模式：下载与查版本使用轻量引擎 %s，临时目录 %s" % (pick_ipatool_bin(["download"]), TMP_ROOT))
    log("ipatool 自动更新：%s" % ("开（每天检查一次）" if CFG.get("auto_update_ipatool", True) else "关"))
    srv.serve_forever()


if __name__ == "__main__":
    main()
IPAWEB_SERVER_PY_EOF
  cat > "$BASE/app/index.html" <<'IPAWEB_INDEX_HTML_EOF'
<!doctype html>
<html lang="zh-CN">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="robots" content="noindex">
<title>IPA / APK 下载</title>
<style>
:root {
  --bg: #f5f6f8; --card: #ffffff; --text: #1d1d1f; --muted: #6e6e73; --line: #e3e4e8;
  --accent: #0a66e8; --accent-text: #ffffff; --ok: #1f9d55; --err: #d93025; --warn: #b26a00;
  --bar: #e8ecf3; --shadow: 0 1px 2px rgba(0,0,0,.05), 0 4px 16px rgba(0,0,0,.04);
  --android: #1f9d55;
}
@media (prefers-color-scheme: dark) {
  :root {
    --bg: #111214; --card: #1c1d20; --text: #f2f2f4; --muted: #a0a0a8; --line: #2c2d32;
    --accent: #4b8dff; --accent-text: #0b0c0e; --ok: #3ccf7b; --err: #ff6b5e; --warn: #f0b04a;
    --bar: #2a2c31; --shadow: none; --android: #3ccf7b;
  }
}
* { box-sizing: border-box; }
html, body { margin: 0; }
body {
  background: var(--bg); color: var(--text);
  font: 15px/1.5 -apple-system, BlinkMacSystemFont, "PingFang SC", "Hiragino Sans GB", "Microsoft YaHei", "Segoe UI", sans-serif;
}
.wrap { max-width: 960px; margin: 0 auto; padding: 20px 16px 60px; }
header { display: flex; align-items: center; gap: 12px; flex-wrap: wrap; margin-bottom: 14px; }
header h1 { font-size: 20px; margin: 0; font-weight: 650; letter-spacing: .2px; }
.tabs { display: inline-flex; background: var(--card); border: 1px solid var(--line); border-radius: 10px; padding: 3px; gap: 3px; }
.tabs button { border: 0; background: none; padding: 5px 12px; border-radius: 7px; font-size: 14px; color: var(--muted); font-weight: 500; }
.tabs button.on { background: var(--accent); color: var(--accent-text); font-weight: 600; }
.tabs button.on.android { background: var(--android); color: #fff; }
.chip { font-size: 13px; padding: 3px 10px; border-radius: 99px; background: var(--card); border: 1px solid var(--line); color: var(--muted); }
.chip.ok { color: var(--ok); } .chip.err { color: var(--err); }
.badge { display: inline-block; font-size: 11px; padding: 1px 6px; border-radius: 5px; border: 1px solid var(--line); color: var(--muted); vertical-align: middle; margin-left: 5px; font-weight: 500; }
.badge.ios { color: var(--accent); border-color: var(--accent); }
.badge.apk { color: var(--android); border-color: var(--android); }
.badge.xapk { color: var(--warn); border-color: var(--warn); }
.spacer { flex: 1; }
button, .btn {
  font: inherit; border: 1px solid var(--line); background: var(--card); color: var(--text);
  padding: 7px 14px; border-radius: 9px; cursor: pointer; white-space: nowrap; text-decoration: none; display: inline-block;
}
button:hover, .btn:hover { border-color: var(--muted); }
button.primary, .btn.primary { background: var(--accent); color: var(--accent-text); border-color: var(--accent); font-weight: 600; }
button:disabled { opacity: .5; cursor: default; }
button.small { padding: 4px 10px; font-size: 13px; }
button.link { border: 0; background: none; color: var(--muted); padding: 4px 6px; }
input, select {
  font: inherit; color: var(--text); background: var(--card); border: 1px solid var(--line);
  border-radius: 10px; padding: 10px 12px; min-width: 0;
}
input { width: 100%; }
select { flex: none; max-width: 210px; cursor: pointer; }
input:focus, select:focus { outline: 2px solid var(--accent); outline-offset: -1px; border-color: transparent; }
.search { display: flex; gap: 8px; margin-bottom: 8px; }
.hint { font-size: 13px; color: var(--muted); margin: 0 0 18px; }
.card { background: var(--card); border: 1px solid var(--line); border-radius: 14px; box-shadow: var(--shadow); }
.results { display: grid; gap: 10px; }
.app { display: flex; gap: 12px; align-items: center; padding: 12px; }
.app img { width: 56px; height: 56px; border-radius: 13px; flex: none; background: var(--bar); object-fit: cover; }
.app .meta { flex: 1; min-width: 0; }
.app .name { font-weight: 600; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
.app .sub { font-size: 13px; color: var(--muted); white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
.app .acts { display: flex; gap: 6px; flex: none; }
h2 { font-size: 15px; margin: 26px 0 10px; color: var(--muted); font-weight: 600; }
.job { padding: 12px; display: flex; gap: 12px; align-items: center; }
.job + .job { border-top: 1px solid var(--line); }
.job img { width: 40px; height: 40px; border-radius: 9px; flex: none; background: var(--bar); object-fit: cover; }
.job .meta { flex: 1; min-width: 0; }
.bar { height: 6px; background: var(--bar); border-radius: 9px; overflow: hidden; margin-top: 6px; }
.bar i { display: block; height: 100%; background: var(--accent); width: 0; transition: width .6s; }
.st-done { color: var(--ok); } .st-error { color: var(--err); } .st-queued { color: var(--warn); }
.empty { padding: 22px; text-align: center; color: var(--muted); font-size: 14px; }
.login { max-width: 360px; margin: 12vh auto 0; padding: 26px 22px; }
.login h1 { font-size: 20px; margin: 0 0 16px; }
.login form { display: grid; gap: 10px; }
.msg { font-size: 14px; color: var(--err); min-height: 1.5em; }
.banner { padding: 10px 14px; border-radius: 10px; margin-bottom: 14px; font-size: 14px; border: 1px solid var(--line); background: var(--card); }
.banner.err { color: var(--err); }
dialog { border: 1px solid var(--line); border-radius: 14px; background: var(--card); color: var(--text); padding: 0; width: min(560px, calc(100vw - 32px)); }
dialog::backdrop { background: rgba(0,0,0,.35); }
.dlg-head { display: flex; align-items: center; padding: 14px 16px; border-bottom: 1px solid var(--line); font-weight: 600; }
.dlg-body { padding: 8px 16px 16px; max-height: 60vh; overflow: auto; }
.ver { display: flex; align-items: center; gap: 8px; padding: 8px 0; border-bottom: 1px solid var(--line); font-size: 14px; }
.ver code { font-size: 13px; color: var(--muted); }
.ver .v { flex: 1; min-width: 0; word-break: break-all; }
@media (max-width: 560px) {
  .search { flex-wrap: wrap; }
  select { max-width: none; width: 100%; }
  .app { flex-wrap: wrap; }
  .app .acts { width: 100%; }
  .app .acts button { flex: 1; }
}
</style>
</head>
<body>
<div class="wrap" id="root"></div>

<dialog id="verDlg">
  <div class="dlg-head"><span id="verTitle">历史版本</span><span class="spacer"></span><button class="link" onclick="verDlg.close()">关闭</button></div>
  <div class="dlg-body" id="verBody"></div>
</dialog>

<script>
"use strict";
const $ = (s, el = document) => el.querySelector(s);
const root = $("#root");
const verDlg = $("#verDlg");
const esc = s => String(s ?? "").replace(/[&<>"']/g, c => ({"&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;","'":"&#39;"}[c]));
const mb = n => n ? (n / 1048576 >= 1024 ? (n / 1073741824).toFixed(2) + " GB" : (n / 1048576).toFixed(1) + " MB") : "";
const FALLBACK_ICON = "data:image/svg+xml," + encodeURIComponent('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 64 64"><rect width="64" height="64" rx="14" fill="#d8dde6"/><path d="M20 26h24v18a4 4 0 0 1-4 4H24a4 4 0 0 1-4-4V26zm6-6a6 6 0 0 1 12 0" fill="none" stroke="#6e6e73" stroke-width="3" stroke-linecap="round"/></svg>');

// 这台浏览器点过「下载」的任务：下好后自动保存到电脑，只自动一次。
const store = {
  get(k, d) { try { return JSON.parse(localStorage.getItem(k)) ?? d; } catch (e) { return d; } },
  set(k, v) { try { localStorage.setItem(k, JSON.stringify(v)); } catch (e) {} },
};
let mine = store.get("ipaweb.mine", {});
let platformMode = store.get("ipaweb.platform", "ios");
let apkSource = store.get("ipaweb.apk_source", "auto");
let lastStatus = null;
let androidResultsMap = {};

async function api(path, opt = {}) {
  const r = await fetch(path, {
    method: opt.body ? "POST" : "GET",
    headers: opt.body ? {"Content-Type": "application/json"} : {},
    body: opt.body ? JSON.stringify(opt.body) : undefined,
    credentials: "same-origin",
  });
  let j = {};
  try { j = await r.json(); } catch (e) {}
  if (r.status === 401) { showLogin(); throw new Error("请先登录"); }
  if (!r.ok) throw new Error(j.error || ("出错了 " + r.status));
  return j;
}

// ---------------- 登录 ----------------
function showLogin() {
  stopPoll();
  root.innerHTML = `
    <div class="card login">
      <h1>IPA / APK 下载</h1>
      <form id="lf">
        <input type="password" id="pw" placeholder="网页密码" autocomplete="current-password" autofocus>
        <button class="primary" type="submit">进入</button>
        <div class="msg" id="lmsg"></div>
      </form>
    </div>`;
  $("#lf").onsubmit = async e => {
    e.preventDefault();
    const b = $("#lf button"); b.disabled = true; $("#lmsg").textContent = "";
    try { await api("/api/login", {body: {password: $("#pw").value}}); showMain(); }
    catch (err) { $("#lmsg").textContent = err.message; b.disabled = false; }
  };
}

// ---------------- 主页面 ----------------
let pollTimer = null;
let statusTimer = null;
let lastCountry = "";
const stopPoll = () => { clearTimeout(pollTimer); pollTimer = null; clearInterval(statusTimer); statusTimer = null; };

function showMain() {
  root.innerHTML = `
    <header>
      <h1>应用下载</h1>
      <div class="tabs">
        <button id="tabIos" type="button">iOS (IPA)</button>
        <button id="tabAndroid" type="button">Android (APK)</button>
      </div>
      <span class="chip" id="acct">加载状态…</span>
      <span class="spacer"></span>
      <button class="link" id="logout">退出</button>
    </header>
    <div id="banner"></div>
    <form class="search" id="sf">
      <select id="srcSel" style="display:none"></select>
      <input id="q" autocomplete="off" autofocus>
      <button class="primary" type="submit">搜索</button>
    </form>
    <p class="hint" id="hint"></p>
    <div class="results" id="results"></div>
    <h2>下载任务</h2>
    <div class="card" id="jobs"><div class="empty">还没有任务</div></div>`;
  $("#logout").onclick = async () => { await api("/api/logout", {body: {}}).catch(() => {}); showLogin(); };
  $("#sf").onsubmit = e => { e.preventDefault(); doSearch(); };
  $("#tabIos").onclick = () => switchPlatform("ios");
  $("#tabAndroid").onclick = () => switchPlatform("android");
  $("#srcSel").onchange = () => {
    apkSource = $("#srcSel").value;
    store.set("ipaweb.apk_source", apkSource);
  };
  applyPlatformUI();
  loadStatus();
  pollJobs();
  // 在 VPS 上用 qiequ 切区后，这里过一会儿自己更新。
  clearInterval(statusTimer);
  statusTimer = setInterval(() => { if ($("#acct")) loadStatus(); }, 15000);
}

function switchPlatform(mode) {
  if (platformMode === mode) return;
  platformMode = mode;
  store.set("ipaweb.platform", mode);
  if ($("#results")) $("#results").innerHTML = "";
  applyPlatformUI();
  renderStatus();
  if ($("#q")) $("#q").focus();
}

function applyPlatformUI() {
  const isAnd = platformMode === "android";
  const tIos = $("#tabIos"), tAnd = $("#tabAndroid"), srcSel = $("#srcSel"), q = $("#q");
  if (tIos) tIos.className = isAnd ? "" : "on";
  if (tAnd) tAnd.className = isAnd ? "on android" : "";
  if (srcSel) srcSel.style.display = isAnd ? "" : "none";
  if (q) {
    q.placeholder = isAnd
      ? "输入安卓 App 名字、包名（如 com.tencent.mm）、商店链接、GitHub 仓库或 .apk/.xapk 直链"
      : "输入 App 名字，或粘贴 App Store 链接 / Bundle ID";
  }
}

function renderStatus() {
  const s = lastStatus;
  if (!s || !$("#acct")) return;
  const el = $("#acct"), cc = (s.country || "cn").toUpperCase();
  const srcSel = $("#srcSel");
  if (srcSel && !srcSel.options.length && Array.isArray(s.android_sources)) {
    srcSel.innerHTML = s.android_sources.map(x =>
      `<option value="${esc(x.id)}"${x.id === apkSource ? " selected" : ""}>${esc(x.name)}</option>`
    ).join("");
  }
  if (platformMode === "android") {
    el.className = "chip ok";
    el.textContent = `安卓免登录 · 多源聚合${s.has_apkeep ? " + apkeep" : ""}`;
    $("#banner").innerHTML = "";
    $("#hint").textContent = `支持 APK / XAPK / APKS，免登录直接下载 · 支持关键词、包名、Google Play / APKPure / 华为 / 应用宝 / F-Droid 链接、GitHub 仓库或安装包直链 · 文件在 VPS 保留 ${s.retention_minutes} 分钟 · 同时下载 ${s.max_concurrent} 个 · VPS 剩余空间 ${mb(s.disk_free)}。`;
    return;
  }
  const a = s.account || {};
  if (a.logged_in) {
    el.className = "chip ok"; el.textContent = `${cc} 区 · ${a.email || a.name || "已登录"}`;
    $("#banner").innerHTML = "";
  } else {
    el.className = "chip err"; el.textContent = `${cc} 区 · 未登录`;
    $("#banner").innerHTML = `<div class="banner err">${esc(a.error || "VPS 上还没登录 Apple ID")}（可切换到上方 Android 直接下载 APK）</div>`;
  }
  const n = (s.accounts || []).length;
  $("#hint").textContent = `App Store 地区：${cc}${n > 1 ? `（存了 ${n} 个账号：${s.accounts.map(x => x.country.toUpperCase()).join("、")}，在 VPS 终端运行 qiequ 切区）` : "（在 VPS 终端运行 qiequ 切区）"} · 下好的文件在 VPS 上保留 ${s.retention_minutes} 分钟 · 同时下载 ${s.max_concurrent} 个 · VPS 剩余空间 ${mb(s.disk_free)}。ipa 带苹果加密，只能装到登录同一个 Apple ID 的设备上。`;
}

async function loadStatus() {
  try {
    const s = await api("/api/status");
    const cc = (s.country || "cn").toUpperCase();
    lastStatus = s;
    renderStatus();
    // 切区以后，旧地区的 iOS 搜索结果可能下不了，清掉。
    if (platformMode === "ios" && lastCountry && lastCountry !== cc && $("#results")) {
      $("#results").innerHTML = `<div class="card empty">已切到 ${cc} 区，重新搜索一下</div>`;
    }
    lastCountry = cc;
  } catch (e) {}
}

async function doSearch() {
  const q = $("#q").value.trim();
  if (!q) return;
  const box = $("#results");
  if (platformMode === "android") {
    box.innerHTML = `<div class="card empty">正在从多个安卓源搜索…</div>`;
    try {
      const {results} = await api(`/api/android/search?q=${encodeURIComponent(q)}&source=${encodeURIComponent(apkSource)}`);
      if (!results.length) {
        box.innerHTML = `<div class="card empty">没搜到。可以换个关键词、切换上面的下载源，或直接输入包名（如 org.telegram.messenger）、GitHub 仓库（owner/repo）或 .apk 直链。</div>`;
        return;
      }
      androidResultsMap = {};
      results.forEach(a => { androidResultsMap[a.token] = a; });
      box.innerHTML = results.map(a => {
        const pt = (a.pkg_type || "APK").toUpperCase();
        const bcls = pt === "APK" ? "apk" : "xapk";
        const metaLine = [a.version ? "v" + a.version : "", mb(a.size), a.source_name || a.source].filter(Boolean).join(" · ");
        return `
          <div class="card app">
            <img src="${esc(a.icon || FALLBACK_ICON)}" alt="" loading="lazy" referrerpolicy="no-referrer" onerror="this.src='${FALLBACK_ICON}'">
            <div class="meta">
              <div class="name" title="${esc(a.name)}">${esc(a.name)}<span class="badge ${bcls}">${esc(pt)}</span></div>
              <div class="sub">${esc(a.seller)} · ${esc(a.package)}</div>
              <div class="sub">${esc(metaLine)}</div>
            </div>
            <div class="acts">
              ${a.source !== "direct" ? `<button class="small" data-aver="${esc(a.token)}">历史版本</button>` : ""}
              <button class="small primary" data-adl="${esc(a.token)}">下载 ${esc(pt)}</button>
            </div>
          </div>`;
      }).join("");
      box.querySelectorAll("[data-adl]").forEach(b => b.onclick = () => startAndroidDownload(androidResultsMap[b.dataset.adl], b));
      box.querySelectorAll("[data-aver]").forEach(b => b.onclick = () => showAndroidVersions(androidResultsMap[b.dataset.aver]));
    } catch (e) {
      box.innerHTML = `<div class="card empty">${esc(e.message)}</div>`;
    }
    return;
  }

  box.innerHTML = `<div class="card empty">搜索中…</div>`;
  try {
    const {results} = await api("/api/search?q=" + encodeURIComponent(q));
    if (!results.length) { box.innerHTML = `<div class="card empty">没搜到。换个关键词，或者直接粘贴 App Store 链接试试。</div>`; return; }
    box.innerHTML = results.map(a => `
      <div class="card app">
        <img src="${esc(a.icon || FALLBACK_ICON)}" alt="" loading="lazy" referrerpolicy="no-referrer">
        <div class="meta">
          <div class="name" title="${esc(a.name)}">${esc(a.name)}<span class="badge ios">IPA</span></div>
          <div class="sub">${esc(a.seller)} · ${esc(a.bundle)}</div>
          <div class="sub">v${esc(a.version)} · ${mb(a.size)} · ${esc(a.price)}${a.minos ? " · iOS " + esc(a.minos) + "+" : ""}</div>
        </div>
        <div class="acts">
          <button class="small" data-ver="${a.id}" data-name="${esc(a.name)}">历史版本</button>
          <button class="small primary" data-dl="${a.id}">${a.free ? "下载 IPA" : "下载（需已购买）"}</button>
        </div>
      </div>`).join("");
    box.querySelectorAll("[data-dl]").forEach(b => b.onclick = () => startDownload(b.dataset.dl, "", b));
    box.querySelectorAll("[data-ver]").forEach(b => b.onclick = () => showVersions(b.dataset.ver, b.dataset.name));
  } catch (e) {
    box.innerHTML = `<div class="card empty">${esc(e.message)}</div>`;
  }
}

async function startDownload(id, extVer, btn) {
  if (btn) btn.disabled = true;
  try {
    const r = await api("/api/download", {body: {id, ext_ver: extVer}});
    mine[r.job] = "pending"; store.set("ipaweb.mine", mine);
    if (btn) btn.textContent = r.existing ? "已在任务里" : "已加入";
    pollJobs();
    $("#jobs").scrollIntoView({behavior: "smooth", block: "nearest"});
  } catch (e) {
    alert(e.message);
    if (btn) btn.disabled = false;
  }
}

async function startAndroidDownload(item, btn) {
  if (!item) return;
  if (btn) btn.disabled = true;
  try {
    const r = await api("/api/android/download", {body: {
      token: item.token,
      package: item.package,
      source: item.source,
      version: item.version || "",
      name: item.name || item.package,
      icon: item.icon || "",
      size: item.size || 0,
    }});
    mine[r.job] = "pending"; store.set("ipaweb.mine", mine);
    if (btn) btn.textContent = r.existing ? "已在任务里" : "已加入";
    pollJobs();
    $("#jobs").scrollIntoView({behavior: "smooth", block: "nearest"});
  } catch (e) {
    alert(e.message);
    if (btn) btn.disabled = false;
  }
}

function saveFile(id) {
  // 用隐藏的链接触发下载，浏览器自己会显示进度，支持断点续传。
  const a = document.createElement("a");
  a.href = "/api/file/" + id; a.download = "";
  document.body.appendChild(a); a.click(); a.remove();
}

async function pollJobs() {
  stopPoll();
  let busy = false;
  try {
    const {jobs} = await api("/api/jobs");
    const box = $("#jobs");
    if (!box) return;
    if (!jobs.length) box.innerHTML = `<div class="empty">还没有任务</div>`;
    else box.innerHTML = jobs.map(jobRow).join("");
    box.querySelectorAll("[data-save]").forEach(b => b.onclick = () => saveFile(b.dataset.save));
    box.querySelectorAll("[data-del]").forEach(b => b.onclick = async () => {
      await api(`/api/jobs/${b.dataset.del}/delete`, {body: {}}).catch(e => alert(e.message));
      pollJobs();
    });
    for (const j of jobs) {
      if (j.status === "queued" || j.status === "running") busy = true;
      if (j.status === "done" && mine[j.id] === "pending") {
        mine[j.id] = "saved"; store.set("ipaweb.mine", mine);
        saveFile(j.id);
      }
    }
    // 只留还在列表里的记录，免得越存越多。
    const ids = new Set(jobs.map(j => j.id));
    for (const k of Object.keys(mine)) if (!ids.has(k)) delete mine[k];
    store.set("ipaweb.mine", mine);
  } catch (e) {}
  pollTimer = setTimeout(pollJobs, busy ? 1500 : 6000);
}

function jobRow(j) {
  let line = "", bar = "", acts = "";
  const isAnd = j.platform === "android";
  const pt = (j.pkg_type || (isAnd ? "APK" : "IPA")).toUpperCase();
  const bcls = isAnd ? (pt === "APK" ? "apk" : "xapk") : "ios";
  const tag = `<span class="badge ${bcls}">${esc(pt)}</span>`;
  const subTag = isAnd
    ? (j.source_name ? ` <span class="sub">· ${esc(j.source_name)}</span>` : "")
    : (j.country ? ` <span class="sub">· ${esc(j.country.toUpperCase())} 区 ${esc(j.account || "")}</span>` : "");
  const name = esc(j.name) + tag + (j.version ? ` <span class="sub">v${esc(j.version)}</span>` : "") + subTag;
  if (j.status === "queued") {
    line = `<span class="st-queued">排队中（第 ${j.queue_pos} 个）</span>`;
    acts = `<button class="small" data-del="${j.id}">取消</button>`;
  } else if (j.status === "running") {
    const pct = j.size ? Math.min(99, Math.floor(j.bytes * 100 / j.size)) : 0;
    const fromTxt = isAnd ? (j.source_name || "安卓源") : "App Store";
    line = `VPS 正在从 ${esc(fromTxt)} 下载… ${mb(j.bytes) || "准备中"}${j.size ? " / 约 " + mb(j.size) : ""}`;
    bar = `<div class="bar"><i style="width:${j.size ? pct : 8}%"></i></div>`;
  } else if (j.status === "done") {
    const left = Math.max(0, Math.round((j.expires * 1000 - Date.now()) / 60000));
    line = `<span class="st-done">下好了</span> · ${mb(j.bytes)} · ${left} 分钟后从 VPS 删除`;
    acts = `<button class="small primary" data-save="${j.id}">保存到电脑</button><button class="small" data-del="${j.id}">删除</button>`;
  } else {
    line = `<span class="st-error">${esc(j.error || "失败")}</span>`;
    acts = `<button class="small" data-del="${j.id}">移除</button>`;
  }
  return `<div class="job">
    <img src="${esc(j.icon || FALLBACK_ICON)}" alt="" referrerpolicy="no-referrer" onerror="this.src='${FALLBACK_ICON}'">
    <div class="meta"><div class="name">${name}</div><div class="sub">${line}</div>${bar}</div>
    <div class="acts">${acts}</div>
  </div>`;
}

// ---------------- 历史版本（iOS） ----------------
async function showVersions(id, name) {
  $("#verTitle").textContent = name + " · 历史版本";
  const body = $("#verBody");
  body.innerHTML = `<div class="empty">向 App Store 查询中，可能要十几秒…</div>`;
  verDlg.showModal();
  try {
    const {versions, latest} = await api("/api/versions?id=" + id);
    if (!versions.length) { body.innerHTML = `<div class="empty">没查到历史版本</div>`; return; }
    body.innerHTML = `<p class="hint" style="margin:8px 0">苹果只给版本编号，点「查版本号」看它是几点几版。</p>` +
      versions.map(v => `
        <div class="ver">
          <div class="v"><code>${esc(v)}</code>${String(v) === String(latest) ? " · 最新" : ""} <span data-meta-out="${esc(v)}"></span></div>
          <button class="small" data-meta="${esc(v)}">查版本号</button>
          <button class="small primary" data-vdl="${esc(v)}">下载</button>
        </div>`).join("");
    body.querySelectorAll("[data-meta]").forEach(b => b.onclick = async () => {
      b.disabled = true;
      const out = body.querySelector(`[data-meta-out="${b.dataset.meta}"]`);
      out.textContent = "查询中…";
      try {
        const m = await api(`/api/version-meta?id=${id}&ver=${b.dataset.meta}`);
        out.textContent = (m.display ? "v" + m.display : "未知") + (m.date ? " · " + String(m.date).slice(0, 10) : "");
      } catch (e) { out.textContent = e.message; b.disabled = false; }
    });
    body.querySelectorAll("[data-vdl]").forEach(b => b.onclick = () => { startDownload(id, b.dataset.vdl, b); });
  } catch (e) {
    body.innerHTML = `<div class="empty">${esc(e.message)}</div>`;
  }
}

// ---------------- 历史版本（Android） ----------------
async function showAndroidVersions(app) {
  if (!app) return;
  $("#verTitle").textContent = app.name + " · 安卓历史版本";
  const body = $("#verBody");
  body.innerHTML = `<div class="empty">正在查询历史版本…</div>`;
  verDlg.showModal();
  try {
    const q = `pkg=${encodeURIComponent(app.package)}&source=${encodeURIComponent(app.source)}&token=${encodeURIComponent(app.token)}`;
    const {versions} = await api("/api/android/versions?" + q);
    if (!versions.length) {
      body.innerHTML = `<div class="empty">该应用暂未查到历史版本（可直接下载最新版）。</div>`;
      return;
    }
    const vMap = {};
    versions.forEach(v => { vMap[v.token] = v; });
    body.innerHTML = versions.map(v => {
      const sub = [v.date, mb(v.size), v.arch, v.pkg_type, v.source_name].filter(Boolean).join(" · ");
      return `
        <div class="ver">
          <div class="v">
            <div><strong>v${esc(v.version)}</strong></div>
            <div class="sub" style="font-size:12px;color:var(--muted)">${esc(sub)}</div>
          </div>
          <button class="small primary" data-avdl="${esc(v.token)}">下载</button>
        </div>`;
    }).join("");
    body.querySelectorAll("[data-avdl]").forEach(b => b.onclick = () => {
      const v = vMap[b.dataset.avdl];
      startAndroidDownload({
        token: v.token,
        package: app.package,
        source: v.source || app.source,
        version: v.version,
        name: app.name,
        icon: app.icon,
        size: v.size || app.size,
      }, b);
    });
  } catch (e) {
    body.innerHTML = `<div class="empty">${esc(e.message)}</div>`;
  }
}

// ---------------- 启动 ----------------
api("/api/me").then(r => r.authed ? showMain() : showLogin()).catch(showLogin);
</script>
</body>
</html>
IPAWEB_INDEX_HTML_EOF
  chmod 644 "$BASE/app/server.py" "$BASE/app/index.html"
}

# 把自己放到 /usr/local/bin/ipa-web，以后直接敲 ipa-web 就能管理。
install_self() {
  src=$1
  [ -f "$src" ] || return 0
  mkdir -p "$(dirname "$CMD_LINK")"
  if [ "$src" != "$CMD_LINK" ]; then
    cp -f "$src" "$CMD_LINK.tmp" && chmod 755 "$CMD_LINK.tmp" && mv -f "$CMD_LINK.tmp" "$CMD_LINK"
  fi
  # 切区快捷命令。别的程序已经占了 qiequ 这个名字就不覆盖。
  if [ -e "$QIEQU_LINK" ] && ! grep -q 'ipa-web' "$QIEQU_LINK" 2>/dev/null; then
    say_warn "$QIEQU_LINK 已经是别的程序，切区请用 ipa-web --qiequ"
  else
    cat > "$QIEQU_LINK" <<EOF
#!/bin/sh
# 切区：切换 / 添加 / 删除 Apple ID 账号（ipa-web 装的快捷命令）
exec $CMD_LINK --qiequ "\$@"
EOF
    chmod 755 "$QIEQU_LINK"
  fi
}

#----------------------------------------------------------------------
# 开机自启和保活：systemd、OpenRC，或者都没有时用 cron 每分钟看一眼。
#----------------------------------------------------------------------
write_run_scripts() {
  cat > "$BASE/run.sh" <<EOF
#!/bin/sh
# zram 重启后就没了，开网页之前先把它开回来。
[ -f $ZRAM_FLAG ] && ! grep -q '^/dev/zram0 ' /proc/swaps 2>/dev/null && $CMD_LINK --swap-boot >/dev/null 2>&1
exec python3 $BASE/app/server.py $CONF
EOF
  chmod 755 "$BASE/run.sh"
  if [ -n "$(cfg_get https_domain)" ]; then
    cat > "$BASE/run-caddy.sh" <<EOF
#!/bin/sh
export HOME=$BASE/caddy XDG_DATA_HOME=$BASE/caddy/data XDG_CONFIG_HOME=$BASE/caddy/config
exec $BASE/bin/caddy run --config $BASE/Caddyfile --adapter caddyfile
EOF
    chmod 755 "$BASE/run-caddy.sh"
  fi
}

svc_install() {
  # svc_install 服务名 启动脚本
  case "$INIT" in
    systemd)
      cat > "/etc/systemd/system/$1.service" <<EOF
[Unit]
Description=$1 (ipatool web)
After=network-online.target
Wants=network-online.target

[Service]
ExecStart=$2
Restart=always
RestartSec=3
StandardOutput=append:$LOG
StandardError=append:$LOG

[Install]
WantedBy=multi-user.target
EOF
      systemctl daemon-reload
      systemctl enable "$1" >/dev/null 2>&1
      ;;
    openrc)
      cat > "/etc/init.d/$1" <<EOF
#!/sbin/openrc-run
name="$1"
description="$1 (ipatool web)"
command="$2"
supervisor=supervise-daemon
respawn_delay=3
respawn_max=0
output_log="$LOG"
error_log="$LOG"

depend() {
  need net
}
EOF
      chmod 755 "/etc/init.d/$1"
      rc-update add "$1" default >/dev/null 2>&1
      ;;
    *)
      cron_line="* * * * * pgrep -f '$2' >/dev/null || nohup $2 >>$LOG 2>&1 &"
      boot_line="@reboot nohup $2 >>$LOG 2>&1 &"
      if have crontab; then
        { crontab -l 2>/dev/null | grep -vF "$2"; echo "$boot_line"; echo "$cron_line"; } | crontab -
      else
        say_warn "没有 systemd、OpenRC，也没有 cron，重启后需要手动运行 ipa-web --restart"
      fi
      ;;
  esac
}

svc_remove() {
  svc_stop "$1" "$2"
  case "$INIT" in
    systemd)
      systemctl disable "$1" >/dev/null 2>&1
      rm -f "/etc/systemd/system/$1.service"
      systemctl daemon-reload
      ;;
    openrc)
      rc-update del "$1" default >/dev/null 2>&1
      rm -f "/etc/init.d/$1"
      ;;
  esac
  if have crontab; then
    crontab -l 2>/dev/null | grep -vF "$2" | crontab - 2>/dev/null || true
  fi
}

svc_start() {
  case "$INIT" in
    systemd) systemctl restart "$1" ;;
    openrc) rc-service "$1" restart >/dev/null 2>&1 || rc-service "$1" start >/dev/null 2>&1 ;;
    *)
      pkill -f "$2" 2>/dev/null
      sleep 1
      nohup "$2" >>"$LOG" 2>&1 &
      ;;
  esac
}

svc_stop() {
  case "$INIT" in
    systemd) systemctl stop "$1" 2>/dev/null ;;
    openrc) rc-service "$1" stop >/dev/null 2>&1 ;;
  esac
  pkill -f "$2" 2>/dev/null || true
}

web_url_local() {
  printf 'http://127.0.0.1:%s/api/me' "$(cfg_get listen_port)"
}

web_alive() {
  fetch_text "$(web_url_local)" 4 | grep -q '"authed"'
}

restart_all() {
  svc_start "$SVC" "$BASE/run.sh"
  if [ -x "$BASE/run-caddy.sh" ]; then svc_start "$SVC_CADDY" "$BASE/run-caddy.sh"; fi
  n=0
  while [ $n -lt 15 ]; do
    sleep 1
    if web_alive; then return 0; fi
    n=$((n + 1))
  done
  return 1
}

#----------------------------------------------------------------------
# 防火墙：系统里开着 ufw / firewalld 就顺手放行端口。
#----------------------------------------------------------------------
open_firewall() {
  for p in "$@"; do
    if have ufw && ufw status 2>/dev/null | grep -q 'Status: active'; then
      ufw allow "$p/tcp" >/dev/null 2>&1 && say_ok "ufw 已放行 $p"
    fi
    if have firewall-cmd && firewall-cmd --state >/dev/null 2>&1; then
      firewall-cmd --permanent --add-port="$p/tcp" >/dev/null 2>&1
      firewall-cmd --reload >/dev/null 2>&1 && say_ok "firewalld 已放行 $p"
    fi
  done
}

close_firewall() {
  for p in "$@"; do
    [ -n "$p" ] || continue
    if have ufw && ufw status 2>/dev/null | grep -q 'Status: active'; then
      ufw delete allow "$p/tcp" >/dev/null 2>&1 || true
    fi
    if have firewall-cmd && firewall-cmd --state >/dev/null 2>&1; then
      firewall-cmd --permanent --remove-port="$p/tcp" >/dev/null 2>&1
      firewall-cmd --reload >/dev/null 2>&1 || true
    fi
  done
}

#----------------------------------------------------------------------
# HTTPS（可选）：用 Caddy 自动申请证书，网页程序只在本机监听。
#----------------------------------------------------------------------
# 这时 Python 可能还没装，用系统自带的查域名工具。
domain_points_here() {
  if have getent; then
    ips=$(getent ahosts "$1" 2>/dev/null | awk '{print $1}')
  elif have nslookup; then
    ips=$(nslookup "$1" 2>/dev/null | awk '/^Address/ && NR>2 {print $NF}')
  else
    ips=$(ping -c 1 -W 2 "$1" 2>/dev/null | sed -n '1s/.*(\([^)]*\)).*/\1/p')
  fi
  for ip in $ips; do
    [ -n "$PUB4" ] && [ "$ip" = "$PUB4" ] && return 0
    [ -n "$PUB6" ] && [ "$ip" = "$PUB6" ] && return 0
  done
  return 1
}

install_caddy() {
  say_step "安装 Caddy（HTTPS）"
  if [ -x "$BASE/bin/caddy" ]; then
    say_ok "Caddy 已经装过"
  else
    ver=$(latest_tag caddyserver/caddy)
    [ -n "$ver" ] || ver=$CADDY_FALLBACK
    mkdir -p "$BASE/tmp/c" "$BASE/bin"
    tgz="$BASE/tmp/caddy.tar.gz"
    gh_download "https://github.com/caddyserver/caddy/releases/download/v$ver/caddy_${ver}_linux_$ARCH.tar.gz" "$tgz" \
      || die "下载 Caddy 失败"
    tar -xzf "$tgz" -C "$BASE/tmp/c" caddy || die "解压 Caddy 失败"
    mv -f "$BASE/tmp/c/caddy" "$BASE/bin/caddy"
    chmod 755 "$BASE/bin/caddy"
    rm -rf "$BASE/tmp"
    "$BASE/bin/caddy" version >/dev/null 2>&1 || die "Caddy 跑不起来"
    say_ok "Caddy $ver 装好了"
  fi
  mkdir -p "$BASE/caddy"
  cat > "$BASE/Caddyfile" <<EOF
$(cfg_get https_domain) {
	encode gzip
	reverse_proxy 127.0.0.1:$(cfg_get listen_port) {
		flush_interval -1
	}
}
EOF
  "$BASE/bin/caddy" validate --config "$BASE/Caddyfile" --adapter caddyfile >/dev/null 2>&1 || die "Caddy 配置不对"
}

#----------------------------------------------------------------------
# Apple ID 账号。可以存好几个不同地区的账号，用 qiequ 切换。
#   每个账号一个目录 $BASE/accounts/<编号>，各放各的登录凭证（钥匙串口令在 config.json）；
#   苹果的组件缓存（约 60MB）大家共用 $BASE/cache，省硬盘。
#   config.json 里 accounts 是账号列表，active 是正在用的那个。
#   home_dir / country / apple_id 跟着正在用的账号走，网页程序只看这三个，
#   改了它会自己发现，不用重启，正在下的任务也不受影响。
#----------------------------------------------------------------------
ACCT_HOME=

ipatool_run() {
  h=$ACCT_HOME
  [ -n "$h" ] || h=$(cfg_get home_dir)
  [ -n "$h" ] || h=$BASE/home
  bin=$BASE/bin/ipatool
  if low_mem && [ -x "$BASE/bin/ipatool-dl" ] && [ "${1:-}" = "auth" ] && [ "${2:-}" = "info" ]; then
    bin=$BASE/bin/ipatool-dl
  fi
  rtmp="$BASE/tmp/run-$$-$(date +%s)"
  mkdir -p "$rtmp"
  if low_mem; then
    # Go 程序的内存回收设紧一点、只用一个线程，TMPDIR 放到硬盘不占 /tmp(tmpfs) 内存。
    TMPDIR="$rtmp" GOMEMLIMIT=32MiB GOGC=25 GOMAXPROCS=1 MALLOC_ARENA_MAX=2 HOME="$h" "$bin" "$@" --format json --non-interactive \
      --keychain-passphrase "$(cfg_get keychain_passphrase)" 2>&1
    rc_run=$?
  else
    TMPDIR="$rtmp" HOME="$h" "$bin" "$@" --format json --non-interactive \
      --keychain-passphrase "$(cfg_get keychain_passphrase)" 2>&1
    rc_run=$?
  fi
  rm -rf "$rtmp"
  return $rc_run
}

# 账号列表的增删改查都交给 Python，config.json 不会被写坏。
acct_py() {
  python3 - "$CONF" "$@" <<'IPAWEB_ACCT_PY'
import json, os, sys
path, cmd, args = sys.argv[1], sys.argv[2], sys.argv[3:]
c = json.load(open(path))
accts = c.get("accounts") or []


def save():
    c["accounts"] = accts
    act = next((a for a in accts if a["id"] == c.get("active")), None)
    if act:
        c["home_dir"], c["country"], c["apple_id"] = act["home"], act["country"], act["email"]
    else:
        c["active"] = ""
        c["apple_id"] = ""
        c["home_dir"] = os.path.join(os.path.dirname(path), "home")
    tmp = path + ".tmp"
    with open(tmp, "w") as f:
        json.dump(c, f, ensure_ascii=False, indent=2)
    os.chmod(tmp, 0o600)
    os.replace(tmp, path)


def find(q):
    q = q.strip().lower()
    if q.isdigit() and 1 <= int(q) <= len(accts) and len(q) <= 3:
        return accts[int(q) - 1]
    for a in accts:
        if q in (a["id"], a["email"].lower()):
            return a
    same = [a for a in accts if a["country"] == q]
    # 同一个地区存了好几个，优先切到不是当前的那个。
    return next((a for a in same if a["id"] != c.get("active")), same[0] if same else None)


if cmd == "list":
    for i, a in enumerate(accts, 1):
        print("|".join([str(i), a["id"], a["email"], a["country"], a["home"],
                        "1" if a["id"] == c.get("active") else "0"]))
elif cmd == "find":
    a = find(args[0])
    if not a:
        sys.exit(1)
    print(a["id"])
elif cmd == "get":
    a = next((a for a in accts if a["id"] == args[0]), None)
    if not a:
        sys.exit(1)
    print(a.get(args[1], ""))
elif cmd == "add":
    accts = [a for a in accts if a["id"] != args[0]]
    accts.append({"id": args[0], "email": args[1], "country": args[2], "home": args[3]})
    save()
elif cmd == "set":
    for a in accts:
        if a["id"] == args[0]:
            a[args[1]] = args[2]
    save()
elif cmd == "use":
    if not any(a["id"] == args[0] for a in accts):
        sys.exit(1)
    c["active"] = args[0]
    save()
elif cmd == "del":
    accts = [a for a in accts if a["id"] != args[0]]
    if c.get("active") == args[0]:
        c["active"] = accts[0]["id"] if accts else ""
    save()
elif cmd == "migrate":
    # 1.0.x 只有一个账号，直接放在 home_dir：变成账号列表里的第一个。
    if "accounts" in c:
        sys.exit(0)
    home = c.get("home_dir") or ""
    if home and os.path.exists(os.path.join(home, ".ipatool", "account")):
        accts = [{"id": args[0], "email": str(c.get("apple_id", "")),
                  "country": str(c.get("country", "cn")), "home": home}]
        c["active"] = args[0]
    save()
IPAWEB_ACCT_PY
}

new_acct_id() {
  printf 'a%s' "$(tr -dc 'a-z0-9' < /dev/urandom 2>/dev/null | head -c 6)"
}

acct_migrate() {
  [ -f "$CONF" ] || return 0
  acct_py migrate "$(new_acct_id)" || true
  # 1.0.x 的组件缓存在旧账号目录里，挪到公共位置给所有账号共用。
  h=$(cfg_get home_dir)
  case "$h" in "$BASE"/*) ;; *) return 0 ;; esac
  if [ -d "$h/.cache" ] && [ ! -L "$h/.cache" ] && [ ! -e "$BASE/cache" ]; then
    mv "$h/.cache" "$BASE/cache" && ln -s "$BASE/cache" "$h/.cache"
  fi
}

acct_count() {
  acct_py list | grep -c .
}

acct_active_index() {
  acct_py list | awk -F'|' '$6 == 1 {print $1}'
}

upper() {
  printf '%s' "$1" | tr 'a-z' 'A-Z'
}

# 某个账号目录里的登录还有没有效。
acct_home_ok() {
  ACCT_HOME=$1
  ipatool_run auth info | grep -q '"success":true'
  ok_rc=$?
  ACCT_HOME=
  return $ok_rc
}

json_error() {
  printf '%s\n' "$1" | sed -n 's/.*"error":"\([^"]*\)".*/\1/p' | tail -n 1
}

explain_login_error() {
  case "$1" in
    *[Ii]ncorrect*|*[Ii]nvalid*credential*|*password*) say_err "Apple ID 或密码不对" ;;
    *验证码*) say_err "$1，再登录一次重试" ;;
    *disabled*|*locked*) say_err "这个 Apple ID 被苹果锁住或停用了（也可能是账号/密码打错）。去 iforgot.apple.com 看看" ;;
    *[Kk]illed*|*memory*) say_err "内存不够，ipatool 被系统杀掉了" ;;
    *timeout*|*connection*|*dial*) say_err "连不上苹果服务器，检查一下 VPS 网络" ;;
    *Store\ pod*|*no\ usable\ authentication\ response*|*non-plist*) say_err "苹果没返回可用的验证响应：ipatool 太旧，或者苹果又改了验证方式。运行 ipa-web --upgrade 升级 ipatool 再试" ;;
    *) say_err "登录失败：$1" ;;
  esac
}

# apple_login 账号目录 邮箱：把这个 Apple ID 登录到这个目录。
apple_login() {
  ACCT_HOME=$1
  mkdir -p "$ACCT_HOME"
  chmod 700 "$ACCT_HOME"
  if [ ! -e "$ACCT_HOME/.cache" ]; then
    mkdir -p "$BASE/cache"
    ln -s "$BASE/cache" "$ACCT_HOME/.cache"
  fi
  say_info "密码只交给 ipatool 登录用，不会写进任何文件。登录凭证加密保存在 $ACCT_HOME。"
  if [ ! -d "$BASE/cache/ipatool" ] && [ ! -d "$ACCT_HOME/.cache/ipatool" ]; then
    say_info "第一次登录 ipatool 要先准备一些文件，可能要等一两分钟。"
  fi
  # 从 qiequ / --login 进来时还没看过机器，先看一眼，虚拟内存不够就自动补上。
  [ -n "${MEM_MB:-}" ] || detect_os
  need_swap && auto_swap
  PAUSED_WEB=
  if low_mem && web_alive; then
    say_info "内存小，登录时先暂停网页服务腾内存，登录完自动恢复。"
    svc_stop "$SVC" "$BASE/run.sh"
    [ -x "$BASE/run-caddy.sh" ] && svc_stop "$SVC_CADDY" "$BASE/run-caddy.sh"
    PAUSED_WEB=1
  fi
  if low_mem; then
    drop_page_cache
    say_info "现在能用的内存 $(mem_avail_mb)MB + 虚拟内存 $(( $(read_meminfo_kb SwapFree:) / 1024 ))MB"
  fi
  ensure_ipatool_min_version
  apple_login_loop "$2"
  rc_login=$?
  if [ -n "$PAUSED_WEB" ]; then
    restart_all >/dev/null || say_warn "网页服务没恢复，运行 ipa-web --restart"
  fi
  ACCT_HOME=
  return $rc_login
}

# ipatool 要验证码时不报错，只打一条普通消息（退出码还是 0），所以要看输出内容。
needs_code() {
  printf '%s' "$1" | grep -qiE '2FA code is required|--auth-code|auth code is required'
}

# 真登录成功：ipatool 说成功，而且钥匙串里确实能读到账号。
login_ok() {
  [ "$1" -eq 0 ] || return 1
  needs_code "$2" && return 1
  ipatool_run auth info | grep -q '"success":true'
}

login_error_text() {
  e=$(json_error "$1")
  [ -n "$e" ] || e=$(printf '%s' "$1" | tail -n 3)
  printf '%s' "$e"
}

apple_login_loop() {
  email=$1
  tries=0
  while [ $tries -lt 3 ]; do
    tries=$((tries + 1))
    ask_secret "$email 的密码（输入时不显示）" || return 1
    pw=$ANSWER
    [ -n "$pw" ] || { say_warn "密码不能为空"; continue; }
    say_info "正在登录…"
    out=$(ipatool_run auth login -e "$email" -p "$pw")
    rc=$?
    if needs_code "$out"; then
      say_info "这个 Apple ID 开了双重认证。苹果刚给你的 iPhone / iPad / Mac 发了 6 位验证码"
      say_info "（设备上先点「允许」才会显示验证码）。"
      ctry=0
      while [ $ctry -lt 3 ]; do
        ctry=$((ctry + 1))
        ask "输入 6 位验证码" ""
        code=$(printf '%s' "$ANSWER" | tr -cd '0-9')
        if [ ${#code} -ne 6 ]; then
          say_warn "验证码是 6 位数字"
          continue
        fi
        say_info "正在验证…"
        out=$(ipatool_run auth login -e "$email" -p "$pw" --auth-code "$code")
        rc=$?
        if login_ok "$rc" "$out"; then break; fi
        if needs_code "$out" || [ $rc -eq 0 ]; then
          say_warn "验证码不对或者过期了。没收到新的话，在设备上打开「设置 → 你的名字 → 登录与安全 → 获取验证码」。"
        else
          say_warn "验证码登录失败：$(login_error_text "$out")"
        fi
      done
    fi
    pw=
    if login_ok "$rc" "$out"; then
      say_ok "Apple ID 登录成功：$email"
      return 0
    fi
    if needs_code "$out"; then
      err="双重认证验证码没通过"
    else
      err=$(login_error_text "$out")
    fi
    [ $rc -eq 137 ] && err=Killed
    explain_login_error "$err"
    case "$err" in
      *[Kk]illed*|*memory*)
        if grow_swap_after_oom; then
          drop_page_cache
          say_info "虚拟内存加上了，重新登录一次（密码要再输一遍）"
          continue
        fi
        if [ "$VIRT_KIND" = container ]; then
          say_warn "这是容器小鸡（${VIRT_DESC}），系统不让加虚拟内存，可用内存只有 $(mem_avail_mb)MB。"
          say_warn "ipatool 登录 Apple ID 要 110MB 以上，这台只能找商家加内存，或者换一台 KVM 小鸡。"
        fi
        ;;
    esac
    ask_yn "再试一次吗？" y || return 1
  done
  return 1
}

apple_status() {
  out=$(ipatool_run auth info)
  if printf '%s' "$out" | grep -q '"success":true'; then
    em=$(printf '%s' "$out" | sed -n 's/.*"email":"\([^"]*\)".*/\1/p' | tail -n 1)
    printf '已登录 %s' "${em:-$(cfg_get apple_id)}"
  else
    printf '未登录'
  fi
}

#----------------------------------------------------------------------
# 切区：添加、切换、重新登录、删除账号。
#----------------------------------------------------------------------
ask_country() {
  say_info "常用：cn 中国大陆　us 美国　hk 香港　tw 台湾　jp 日本　kr 韩国　sg 新加坡　gb 英国"
  while :; do
    ask "这个 Apple ID 是哪个地区的（地区代码）" "$1"
    c=$(printf '%s' "$ANSWER" | tr 'A-Z' 'a-z')
    if printf '%s' "$c" | grep -qE '^[a-z]{2}$'; then
      Q_ACCT_COUNTRY=$c
      return 0
    fi
    can_ask || die "地区代码不对：$ANSWER"
    say_warn "是两个字母，例如 cn、us、hk"
  done
}

acct_print() {
  acct_py list | while IFS='|' read -r i id em co home act; do
    if [ "$act" = 1 ]; then
      printf '  %s) %s  %s  %s\n' "$i" "$(upper "$co")" "$em" "${C_GREEN}← 正在用${C_NC}"
    else
      printf '  %s) %s  %s\n' "$i" "$(upper "$co")" "$em"
    fi
  done
}

# acct_add [地区]：登录一个新的 Apple ID 并存起来。给了地区就不再问。
acct_add() {
  say_step "添加 Apple ID 账号"
  say_info "建议用小号。免费 App 会自动「领取」到这个账号。"
  ask "Apple ID 邮箱（或手机号）" ""
  email=$ANSWER
  [ -n "$email" ] || { say_warn "没填，取消"; return 1; }
  old=$(acct_py find "$email" 2>/dev/null)
  if [ -n "$old" ] && [ "$(acct_py get "$old" email)" = "$email" ]; then
    say_info "这个账号已经存过了，改成重新登录它。"
    acct_relogin "$old"
    return
  fi
  if [ -n "$1" ]; then Q_ACCT_COUNTRY=$1; else ask_country "cn"; fi
  id=$(new_acct_id)
  home=$BASE/accounts/$id
  if apple_login "$home" "$email"; then
    acct_py add "$id" "$email" "$Q_ACCT_COUNTRY" "$home"
    say_ok "已保存：$(upper "$Q_ACCT_COUNTRY")  $email"
    if [ -z "$(cfg_get active)" ] || ask_yn "现在就切到这个账号吗？" y; then
      acct_use "$id" quiet
    fi
    return 0
  fi
  rm -rf "$home"
  return 1
}

acct_relogin() {
  em=$(acct_py get "$1" email) || { say_err "找不到这个账号"; return 1; }
  say_step "重新登录 $em（$(upper "$(acct_py get "$1" country)")）"
  apple_login "$(acct_py get "$1" home)" "$em"
}

# acct_use 编号 [quiet]：切到这个账号，网页马上生效。
acct_use() {
  acct_py use "$1" || { say_err "找不到这个账号"; return 1; }
  em=$(acct_py get "$1" email)
  co=$(upper "$(acct_py get "$1" country)")
  say_ok "已切到 $co 区：$em（网页刷新一下就是新的地区）"
  [ "$2" = quiet ] && return 0
  say_info "检查登录还有没有效…"
  if acct_home_ok "$(acct_py get "$1" home)"; then
    say_ok "登录有效，可以直接下载"
  else
    say_warn "这个账号的登录已经失效了（苹果的登录凭证会过期）。"
    if can_ask && ask_yn "现在重新登录吗？" y; then acct_relogin "$1"; fi
  fi
}

acct_delete() {
  em=$(acct_py get "$1" email) || { say_err "找不到这个账号"; return 1; }
  home=$(acct_py get "$1" home)
  ask_yn "确定删除 $em 吗？（删掉 VPS 上的登录凭证，Apple ID 本身不受影响）" n || return 0
  acct_py del "$1"
  case "$home" in "$BASE"/*) rm -rf "$home" ;; esac
  say_ok "删好了"
  if [ -n "$(cfg_get active)" ]; then
    say_info "现在用的是：$(upper "$(cfg_get country)")  $(cfg_get apple_id)"
  else
    say_warn "一个账号都没有了，网页下载不了。运行 qiequ 选 a 添加一个。"
  fi
}

# 让用户选一个账号，编号放在 PICKED。
acct_pick() {
  ask "$1（输入序号）" "$2"
  PICKED=$(acct_py find "$ANSWER" 2>/dev/null)
  [ -n "$PICKED" ] || { say_warn "没有这个账号"; return 1; }
}

qiequ_menu() {
  while :; do
    printf '\n%s\n' "${C_BOLD}======== 切区 / Apple ID 账号 ========${C_NC}"
    if [ "$(acct_count)" -eq 0 ]; then
      printf '  还没有存账号\n'
    else
      acct_print
    fi
    printf '\n'
    [ "$(acct_count)" -gt 0 ] && printf '  输入序号：切到那个账号（也可以输地区代码，例如 us）\n'
    printf '  a) 添加账号（登录一个新的 Apple ID）\n'
    [ "$(acct_count)" -gt 0 ] && printf '  r) 重新登录某个账号（网页提示登录过期时用）\n'
    [ "$(acct_count)" -gt 0 ] && printf '  d) 删除某个账号\n'
    printf '  0) 退出\n'
    ask "选哪个" "0"
    case "$ANSWER" in
      0|q|Q|'') return 0 ;;
      a|A) lock_take; acct_add; lock_release ;;
      r|R) acct_pick "重新登录哪个" "$(acct_active_index)" && { lock_take; acct_relogin "$PICKED"; lock_release; } ;;
      d|D) acct_pick "删除哪个" "" && { lock_take; acct_delete "$PICKED"; lock_release; } ;;
      *)
        id=$(acct_py find "$ANSWER" 2>/dev/null)
        if [ -n "$id" ]; then
          lock_take; acct_use "$id"; lock_release
          return 0
        fi
        say_warn "没有这个选项"
        ;;
    esac
  done
}

qiequ_main() {
  must_installed
  # 迁移旧账号要写东西，拿一下锁；菜单本身不等锁，选了要改东西的动作再拿。
  lock_take; acct_migrate; lock_release
  case "${1:-}" in
    '') qiequ_menu ;;
    list|ls|-l) acct_print ;;
    add|-a) lock_take; acct_add; lock_release ;;
    -h|--help) sed -n '/^# 切区（/,/^# qiequ list/p' "$CMD_LINK" | sed 's/^#//' ;;
    *)
      id=$(acct_py find "$1" 2>/dev/null) || id=
      [ -n "$id" ] || { acct_print; die "没找到「$1」。可以写序号、地区代码或邮箱"; }
      lock_take; acct_use "$id"; lock_release
      ;;
  esac
}

#----------------------------------------------------------------------
# 网址怎么显示：HTTPS 用域名；NAT 小鸡用商家映射的外网端口。
#----------------------------------------------------------------------
web_urls() {
  dom=$(cfg_get https_domain)
  if [ -n "$dom" ]; then
    printf 'https://%s\n' "$dom"
    return
  fi
  pp=$(cfg_get public_port)
  [ -n "$pp" ] || pp=$(cfg_get listen_port)
  h4=$(cfg_get public_ipv4)
  h6=$(cfg_get public_ipv6)
  [ -n "$h4" ] && printf 'http://%s:%s\n' "$h4" "$pp"
  [ -n "$h6" ] && [ "$(cfg_get nat)" != 1 ] && printf 'http://[%s]:%s\n' "$h6" "$(cfg_get listen_port)"
  [ -z "$h4$h6" ] && printf 'http://你的VPS地址:%s\n' "$pp"
}

show_status() {
  [ -f "$CONF" ] || die "还没安装。运行 sh install.sh 安装"
  detect_os
  printf '\n%s\n' "${C_BOLD}======== ipa-web 状态 ========${C_NC}"
  if web_alive; then
    printf '网页服务：%s\n' "${C_GREEN}运行中${C_NC}"
  else
    printf '网页服务：%s\n' "${C_RED}没在运行${C_NC}（运行 ipa-web --restart 试试，或 ipa-web --log 看原因）"
  fi
  printf '打开网址：\n'
  web_urls | sed 's/^/  /'
  printf '网页密码：忘了就运行 ipa-web --reset-password 换一个\n'
  acct_migrate
  printf 'Apple ID：%s（%s 区）\n' "$(apple_status)" "$(upper "$(cfg_get country)")"
  if [ "$(acct_count)" -gt 1 ]; then
    printf '存了 %s 个账号，运行 qiequ 切区：\n' "$(acct_count)"
    acct_print
  fi
  printf '文件保留：%s 分钟　同时下载：%s 个\n' "$(cfg_get retention_minutes)" "$(cfg_get max_concurrent)"
  if [ "$(cfg_get auto_update_ipatool)" = "false" ]; then au_st="关"; else au_st="开，每天检查"; fi
  dl_v=$(ipatool_dl_version)
  if [ -n "$dl_v" ] && [ "$(cfg_get low_memory)" = "true" ]; then
    printf 'ipatool：%s（自动更新 %s，低内存下载引擎 %s）　脚本：%s\n' "$(ipatool_version)" "$au_st" "$dl_v" "$VERSION"
  else
    printf 'ipatool：%s（自动更新 %s）　脚本：%s\n' "$(ipatool_version)" "$au_st" "$VERSION"
  fi
  ak_v=$(apkeep_version)
  if [ -n "$ak_v" ]; then
    printf '安卓下载：内置 8 源聚合引擎 + apkeep %s（免登录）\n' "$ak_v"
  else
    printf '安卓下载：内置 8 源聚合引擎（免登录）\n'
  fi
  printf '程序目录：%s　日志：%s\n' "$BASE" "$LOG"
  if [ "$(cfg_get nat)" = 1 ]; then
    printf '%s\n' "${C_YELLOW}这是 NAT 小鸡：外网端口 $(cfg_get public_port) 要在商家面板里映射到内网端口 $(cfg_get listen_port)。${C_NC}"
  fi
  printf '\n'
}

#----------------------------------------------------------------------
# 第一次安装：先看机器，再一问一答，最后一次装好。
#----------------------------------------------------------------------
print_machine_report() {
  say_step "检查这台机器"
  printf '  系统：%s（%s，%s）\n' "$OS_PRETTY" "$ARCH" "$LIBC"
  printf '  内核：%s　启动方式：%s\n' "$KERNEL" "$INIT"
  if [ -n "$MEM_LIMIT_FROM" ]; then
    printf '  内存：%s MB（容器限制）　虚拟内存：%s MB\n' "$MEM_MB" "$SWAP_MB"
  else
    printf '  内存：%s MB　虚拟内存：%s MB\n' "$MEM_MB" "$SWAP_MB"
  fi
  printf '  硬盘剩余：%s MB\n' "$DISK_MB"
  printf '  %s这是一台「%s」：%s%s\n' "$C_BOLD" "$ROLE" "$VIRT_DESC" "$C_NC"
  if [ "$NAT" = 1 ]; then
    printf '  网络：%sNAT%s（本机内网 IP %s，公网 IP %s）\n' "$C_YELLOW" "$C_NC" "$LOCAL4" "$PUB4"
  else
    printf '  网络：公网 IPv4 %s%s\n' "${PUB4:-无}" "${PUB6:+　IPv6 $PUB6}"
  fi
}

check_machine() {
  case "$ARCH" in
    amd64|arm64) ;;
    *) die "ipatool 只支持 x86_64 和 arm64 架构，这台是 $ARCH，装不了" ;;
  esac
  if ! kernel_ok; then
    die "内核 $KERNEL 太老（ipatool 需要 3.2 以上）。老 OpenVZ 小鸡常见这个问题，换一台 KVM 小鸡吧"
  fi
  if [ "$DISK_MB" -lt 1024 ]; then
    say_warn "硬盘只剩 ${DISK_MB}MB。ipa 文件动辄几百 MB，硬盘太小大 App 会下不了。"
    ask_yn "还要继续吗？" n || exit 0
  fi
  if [ "$MEM_MB" -le 512 ]; then
    say_info "这台机器内存为 ${MEM_MB}MB：会自动启用低内存下载引擎（ipatool $IPATOOL_LOWMEM_VER，下载仅占约 50MB 内存），"
    say_info "并将临时文件放到硬盘目录 $BASE/tmp，避免占满 /tmp 内存盘导致 OOM。"
  fi
  if [ "$ROLE" = 母鸡 ]; then
    say_warn "这是母鸡（${VIRT_DESC}）。在母鸡上也能装，不过一般建议装在小鸡里，"
    say_warn "免得网页服务和母鸡上开小鸡的程序抢资源、或者把母鸡暴露在公网上。"
    ask_yn "确定装在这台母鸡上吗？" y || exit 0
  fi
}

ask_questions() {
  say_step "回答几个问题（直接回车就用括号里的默认值）"
  CUR_PORT=$(cfg_get listen_port 2>/dev/null || true)

  # 1. 端口
  Q_PUBLIC_PORT=
  if [ "$NAT" = 1 ]; then
    say_info "这是 NAT 小鸡，外面只能通过商家映射给你的端口访问。"
    say_info "请去商家面板看「端口映射 / 端口转发」，挑一个空着的外网端口（不要用 SSH 那个）。"
    while :; do
      ask "外网端口（商家映射给你的）" "$(cfg_get public_port 2>/dev/null || true)"
      valid_port "$ANSWER" && break
      can_ask || die "NAT 小鸡需要回答外网端口，请在终端里运行本脚本"
      say_warn "请输入一个端口数字"
    done
    Q_PUBLIC_PORT=$ANSWER
    say_info "这个外网端口在商家那边映射到的内网端口，一般和外网端口一样。"
    ask_port "对应的内网端口" "$Q_PUBLIC_PORT"
    Q_PORT=$PORT_ANSWER
  else
    def=${CUR_PORT:-$(random_free_port)}
    say_info "网页用哪个端口。随机的高位端口不容易被扫到。"
    ask_port "网页端口" "$def"
    Q_PORT=$PORT_ANSWER
  fi

  # 2. HTTPS
  Q_DOMAIN=
  if [ "$NAT" != 1 ] && [ -n "$PUB4$PUB6" ]; then
    if ! port_busy 80 && ! port_busy 443; then
      say_info "有域名的话可以开 HTTPS（自动申请免费证书），密码不会明文在网上传。"
      if ask_yn "要开 HTTPS 吗？（需要一个已经解析到这台 VPS 的域名）" n; then
        while :; do
          ask "域名（例如 ipa.example.com）" ""
          d=$(printf '%s' "$ANSWER" | tr 'A-Z' 'a-z' | sed 's#^https\{0,1\}://##; s#/.*$##')
          if ! printf '%s' "$d" | grep -qE '^[a-z0-9-]+(\.[a-z0-9-]+)+$'; then
            say_warn "域名格式不对"
            ask_yn "不开 HTTPS 了？" n && break
            continue
          fi
          if domain_points_here "$d"; then
            Q_DOMAIN=$d
            say_ok "$d 已经解析到这台 VPS"
            break
          fi
          say_warn "$d 现在还没解析到这台 VPS（${PUB4:-$PUB6}）。证书会申请失败。"
          if ask_yn "还是用它吗？（如果刚改了解析、或者套了 CDN）" n; then
            Q_DOMAIN=$d
            break
          fi
          ask_yn "换个域名试试？" y || break
        done
      fi
    else
      say_info "80 / 443 端口已经被别的程序占了，跳过 HTTPS（已有 Nginx/Caddy 的话可以自己反代到 $Q_PORT）。"
    fi
  fi

  # 3. 网页密码
  say_info "打开网页时要输的密码，防止别人用你的 Apple ID 下东西。"
  while :; do
    def_pw=$(rand_text 12)
    ask "网页密码（至少 6 位）" "$def_pw"
    if [ ${#ANSWER} -ge 6 ]; then
      Q_PASSWORD=$ANSWER
      break
    fi
    say_warn "至少 6 位"
  done

  # 4. 地区
  say_info "Apple ID 所在的地区（App Store 国家/地区），搜索结果要和它一致才能下载。"
  say_info "常用：cn 中国大陆　us 美国　hk 香港　tw 台湾　jp 日本　kr 韩国　sg 新加坡　gb 英国"
  while :; do
    ask "地区代码" "$(cfg_get country 2>/dev/null || echo cn)"
    c=$(printf '%s' "$ANSWER" | tr 'A-Z' 'a-z')
    if printf '%s' "$c" | grep -qE '^[a-z]{2}$'; then
      Q_COUNTRY=$c
      break
    fi
    say_warn "是两个字母，例如 cn、us"
  done

  # 5. 保留时间
  while :; do
    ask "下好的 ipa 在 VPS 上留多少分钟后自动删除" "$(cfg_get retention_minutes 2>/dev/null || echo 60)"
    case "$ANSWER" in ''|*[!0-9]*) say_warn "请输入分钟数" ; continue ;; esac
    [ "$ANSWER" -ge 5 ] && [ "$ANSWER" -le 10080 ] && { Q_RETENTION=$ANSWER; break; }
    say_warn "5 到 10080 之间（最多一周）"
  done

  # 6. 同时下载数（按内存给默认值）
  if [ "$MEM_MB" -lt 1024 ]; then def_c=1; elif [ "$MEM_MB" -lt 2048 ]; then def_c=2; else def_c=3; fi
  [ -n "$(cfg_get max_concurrent 2>/dev/null || true)" ] && def_c=$(cfg_get max_concurrent)
  say_info "同时最多下几个 App。内存 ${MEM_MB}MB，建议 $def_c 个，多出来的排队。"
  while :; do
    ask "同时下载数" "$def_c"
    case "$ANSWER" in [1-9]) Q_CONCURRENT=$ANSWER; break ;; esac
    say_warn "1 到 9"
  done

  # 7. 虚拟内存：按机器配置自动算，不问。IPAWEB_SWAP_MB=0 可以关掉。
  Q_SWAP=0
  if [ "$VIRT_KIND" = container ] && [ $((MEM_MB + SWAP_MB)) -lt 200 ]; then
    say_warn "内存只有 ${MEM_MB}MB（虚拟内存 ${SWAP_MB}MB），又是容器小鸡，自己加不了虚拟内存。"
    say_warn "ipatool 登录 Apple ID 时实测要 110~180MB，这台大概率登录不上（会被系统杀掉）。"
    say_warn "网页能装，但建议换一台 KVM 小鸡（64MB 的 KVM 加虚拟内存就能用）。"
    ask_yn "还要继续装吗？" n || exit 0
  elif [ "${IPAWEB_SWAP_MB:-}" = 0 ]; then
    say_info "IPAWEB_SWAP_MB=0：不加虚拟内存"
  else
    swap_report
    Q_SWAP=$(swap_plan_mb)
    [ "$Q_SWAP" -gt 0 ] || ! need_swap || [ "$VIRT_KIND" = container ] || Q_SWAP=zram
  fi

  # 8. 确认
  printf '\n%s\n' "${C_BOLD}------- 确认一下 -------${C_NC}"
  printf '  网页端口：%s%s\n' "$Q_PORT" "${Q_PUBLIC_PORT:+（外网端口 $Q_PUBLIC_PORT）}"
  [ -n "$Q_DOMAIN" ] && printf '  HTTPS 域名：%s\n' "$Q_DOMAIN"
  printf '  网页密码：%s\n' "$Q_PASSWORD"
  printf '  App Store 地区：%s\n' "$(printf '%s' "$Q_COUNTRY" | tr 'a-z' 'A-Z')"
  printf '  文件保留：%s 分钟　同时下载：%s 个\n' "$Q_RETENTION" "$Q_CONCURRENT"
  case "$Q_SWAP" in
    0) ;;
    zram) printf '  加虚拟内存：zram（硬盘不够，在内存里压缩）\n' ;;
    *) printf '  加虚拟内存：%s MB（按机器配置自动算的）\n' "$Q_SWAP" ;;
  esac
  printf '  安装到：%s\n' "$BASE"
  ask_yn "开始安装？" y || { say_info "没装，什么都没改。"; exit 0; }
}

write_config() {
  mkdir -p "$BASE/home" "$BASE/data"
  chmod 700 "$BASE" "$BASE/home"
  old_port=$(cfg_get listen_port 2>/dev/null || true)
  if [ ! -f "$CONF" ]; then
    printf '{}\n' > "$CONF"
    chmod 600 "$CONF"
  fi
  [ -n "$(cfg_get keychain_passphrase)" ] || cfg_set keychain_passphrase "$(rand_text 32)"
  [ -n "$(cfg_get secret)" ] || cfg_set secret "$(rand_text 48)"
  if [ -n "$Q_DOMAIN" ]; then
    host=127.0.0.1
    proxy=true
  elif [ "$HAS_V6" = 1 ]; then
    host="::"
    proxy=false
  else
    host=0.0.0.0
    proxy=false
  fi
  cfg_set listen_host "$host" listen_port "$Q_PORT" public_port "${Q_PUBLIC_PORT:-$Q_PORT}" \
    https_domain "$Q_DOMAIN" trust_proxy "$proxy" country "$Q_COUNTRY" \
    retention_minutes "$Q_RETENTION" max_concurrent "$Q_CONCURRENT" \
    ipatool_bin "$BASE/bin/ipatool" apkeep_bin "$BASE/bin/apkeep" home_dir "$BASE/home" data_dir "$BASE/data" \
    public_ipv4 "$PUB4" public_ipv6 "$PUB6" nat "$NAT" script_version "$VERSION"
  if low_mem; then
    cfg_set low_memory true
    if [ -x "$BASE/bin/ipatool-dl" ]; then cfg_set ipatool_dl_bin "$BASE/bin/ipatool-dl"; else cfg_set ipatool_dl_bin ""; fi
  else
    cfg_set low_memory false ipatool_dl_bin ""
  fi
  set_web_password "$Q_PASSWORD"
  # 重装时已经存了账号：home_dir / country 恢复成正在用的账号的。
  acct_migrate
  act=$(cfg_get active)
  [ -n "$act" ] && acct_py use "$act"
  if [ -n "$old_port" ] && [ "$old_port" != "$Q_PORT" ]; then close_firewall "$old_port"; fi
}

fresh_install() {
  need_root
  lock_take
  printf '%s\n' "${C_BOLD}ipatool 网页一键脚本 v$VERSION${C_NC}"
  detect_os
  [ "$PM" != none ] || say_warn "认不出这台机器用什么装软件，缺东西时请自己装"
  ensure_basic_tools
  detect_virt
  swap_probe
  detect_net
  print_machine_report
  check_machine
  ask_questions

  if [ "$Q_SWAP" != 0 ]; then
    say_step "开虚拟内存"
    auto_swap || say_warn "虚拟内存没开出来，登录 Apple ID 可能会被系统杀掉"
  fi
  install_deps
  install_ipatool
  say_step "安装网页"
  write_config
  write_app_files
  write_run_scripts
  install_self "$SELF"
  svc_install "$SVC" "$BASE/run.sh"
  if [ -n "$Q_DOMAIN" ]; then
    install_caddy
    write_run_scripts
    svc_install "$SVC_CADDY" "$BASE/run-caddy.sh"
    open_firewall 80 443
  else
    open_firewall "$Q_PORT"
  fi
  if restart_all; then
    say_ok "网页服务启动了"
  else
    say_err "网页服务没起来，最近的日志："
    tail -n 20 "$LOG" 2>/dev/null
    exit 1
  fi

  if [ -n "$(cfg_get active)" ] && acct_home_ok "$(cfg_get home_dir)"; then
    say_ok "保存的 Apple ID 账号都还在，正在用：$(upper "$(cfg_get country)")  $(cfg_get apple_id)"
  elif can_ask && ask_yn "现在登录 Apple ID 吗？（安卓 APK 免登录直接能下；苹果 IPA 需要登录，以后也能运行 qiequ 添加）" y; then
    acct_add "$Q_COUNTRY" || say_warn "Apple ID 还没登录，之后运行 qiequ 选 a 添加"
  fi

  show_status
  printf '%s\n' "${C_GREEN}${C_BOLD}装好了！${C_NC} 在电脑浏览器打开上面的网址，输入网页密码：${C_BOLD}$Q_PASSWORD${C_NC}"
  printf '以后管理（改设置、更新、卸载）：直接运行 %sipa-web%s\n' "$C_BOLD" "$C_NC"
  printf '切区（存多个地区的 Apple ID，随时切换）：运行 %sqiequ%s\n' "$C_BOLD" "$C_NC"
  if [ "$NAT" = 1 ]; then
    say_warn "NAT 小鸡：如果打不开，检查商家面板里外网端口 $Q_PUBLIC_PORT 是否映射到了内网端口 $Q_PORT。"
  elif [ -z "$Q_DOMAIN" ]; then
    say_info "打不开的话，检查云服务商的「安全组 / 防火墙」有没有放行 TCP $Q_PORT。"
  fi
}

#----------------------------------------------------------------------
# 管理功能
#----------------------------------------------------------------------
must_installed() {
  [ -f "$CONF" ] && [ -f "$BASE/app/server.py" ] || die "还没安装。运行 sh install.sh 安装"
  detect_os
}

do_reset_password() {
  must_installed
  ask "新的网页密码（至少 6 位）" "$(rand_text 12)"
  [ ${#ANSWER} -ge 6 ] || die "至少 6 位"
  set_web_password "$ANSWER"
  restart_all >/dev/null
  say_ok "网页密码改好了：$ANSWER（已登录的浏览器需要重新输入）"
}

do_settings() {
  must_installed
  ask_questions_settings
}

ask_questions_settings() {
  # 只改用户常改的几项，HTTPS 和端口改动需要重装服务的走重装流程。
  while :; do
    # 上一轮万一没放掉锁（输入不对直接 continue 时），这里放掉，
    # 等用户选的时候不占锁。
    lock_release
    printf '\n%s\n' "${C_BOLD}改设置${C_NC}"
    printf '  1) 端口（现在 %s）\n' "$(cfg_get listen_port)"
    printf '  2) 当前账号的地区（现在 %s，切换账号请用 qiequ）\n' "$(cfg_get country | tr 'a-z' 'A-Z')"
    printf '  3) 文件保留时间（现在 %s 分钟）\n' "$(cfg_get retention_minutes)"
    printf '  4) 同时下载数（现在 %s 个）\n' "$(cfg_get max_concurrent)"
    if [ "$(cfg_get auto_update_ipatool)" = "false" ]; then au_lbl="关"; else au_lbl="开"; fi
    printf '  5) ipatool 自动更新（现在 %s）\n' "$au_lbl"
    printf '  0) 返回\n'
    ask "选哪个" "0"
    lock_take
    case "$ANSWER" in
      1)
        CUR_PORT=$(cfg_get listen_port)
        if [ "$(cfg_get nat)" = 1 ]; then
          ask "外网端口（商家映射给你的）" "$(cfg_get public_port)"
          valid_port "$ANSWER" || { say_warn "端口不对"; continue; }
          pp=$ANSWER
          ask_port "对应的内网端口" "$pp"
        else
          ask_port "新端口" "$CUR_PORT"
          pp=$PORT_ANSWER
        fi
        close_firewall "$CUR_PORT"
        cfg_set listen_port "$PORT_ANSWER" public_port "$pp"
        if [ -n "$(cfg_get https_domain)" ]; then
          install_caddy
        else
          open_firewall "$PORT_ANSWER"
        fi
        ;;
      2)
        ask "地区代码（cn us hk tw jp kr sg gb…）" "$(cfg_get country)"
        c=$(printf '%s' "$ANSWER" | tr 'A-Z' 'a-z')
        printf '%s' "$c" | grep -qE '^[a-z]{2}$' || { say_warn "是两个字母"; continue; }
        act=$(cfg_get active)
        if [ -n "$act" ]; then acct_py set "$act" country "$c"; else cfg_set country "$c"; fi
        ;;
      3)
        ask "保留多少分钟" "$(cfg_get retention_minutes)"
        case "$ANSWER" in ''|*[!0-9]*) say_warn "请输入数字"; continue ;; esac
        [ "$ANSWER" -ge 5 ] || { say_warn "至少 5 分钟"; continue; }
        cfg_set retention_minutes "$ANSWER"
        ;;
      4)
        ask "同时下载数（1-9）" "$(cfg_get max_concurrent)"
        case "$ANSWER" in [1-9]) cfg_set max_concurrent "$ANSWER" ;; *) say_warn "1 到 9"; continue ;; esac
        ;;
      5)
        if [ "$(cfg_get auto_update_ipatool)" = "false" ]; then cfg_set auto_update_ipatool true; else cfg_set auto_update_ipatool false; fi
        ;;
      *) lock_release; return 0 ;;
    esac
    if restart_all; then say_ok "改好了，网页服务已重启"; else say_err "网页服务没起来，运行 ipa-web --log 看看"; fi
    lock_release
  done
}

do_login() {
  must_installed
  lock_take
  acct_migrate
  act=$(cfg_get active)
  if [ -n "$act" ]; then acct_relogin "$act"; else acct_add; fi
}

# ipa-web --swap：看看机器，按配置自动把虚拟内存开够。
do_swap() {
  detect_os
  detect_virt
  swap_probe
  say_step "虚拟内存"
  printf '  这是一台「%s」：%s\n' "$ROLE" "$VIRT_DESC"
  printf '  内存：%s MB　虚拟内存：%s MB　硬盘剩余：%s MB\n' "$MEM_MB" "$SWAP_MB" "$DISK_MB"
  swap_report
  if auto_swap; then
    awk 'NR>1 {printf "  %s  %d MB\n", $1, $3/1024}' /proc/swaps
  else
    say_warn "虚拟内存开不出来，登录 Apple ID 可能会被系统杀掉"
  fi
}

do_log() {
  [ -f "$LOG" ] || die "还没有日志"
  tail -n "${1:-60}" "$LOG"
}

do_restart() {
  must_installed
  if restart_all; then say_ok "网页服务重启好了"; else say_err "没起来，最近的日志："; tail -n 20 "$LOG" 2>/dev/null; fi
}

script_ok() {
  head -n 1 "$1" 2>/dev/null | grep -q '^#!/bin/sh' && grep -q 'ipaweb-onekey-begin' "$1"
}

# 用当前这份脚本里的网页程序覆盖装好的，保留配置。
apply_update() {
  must_installed
  lock_take
  detect_os
  need_swap && auto_swap
  install_ipatool
  write_app_files
  write_run_scripts
  install_self "$SELF"
  acct_migrate
  # 清理旧版在 /tmp(tmpfs) 残留的 ipatool 临时目录，释放被占用的内存/swap。
  rm -rf /tmp/ipatool-* "$BASE/tmp/run-"* 2>/dev/null || true
  # 旧版装的时候 low_memory 可能判错了（例如 256MB 的机器），更新时按现在的
  # 机器情况重新判一次，不然配置里一直留着错的。
  if low_mem; then
    cfg_set low_memory true
    if [ -x "$BASE/bin/ipatool-dl" ]; then cfg_set ipatool_dl_bin "$BASE/bin/ipatool-dl"; else cfg_set ipatool_dl_bin ""; fi
  else
    cfg_set low_memory false ipatool_dl_bin ""
  fi
  if [ -x "$BASE/bin/apkeep" ]; then cfg_set apkeep_bin "$BASE/bin/apkeep"; fi
  cfg_set script_version "$VERSION"
  if restart_all; then say_ok "更新好了（脚本 $VERSION，ipatool $(ipatool_version)）"; else say_err "更新后网页服务没起来，运行 ipa-web --log 看看"; fi
}

do_upgrade() {
  must_installed
  say_step "检查新版本"
  new=$BASE/install.sh.new
  ok=
  for u in "https://raw.githubusercontent.com/$REPO/main/install.sh" "https://cdn.jsdelivr.net/gh/$REPO@main/install.sh"; do
    if fetch_file "$u" "$new" && script_ok "$new"; then ok=1; break; fi
  done
  [ -n "$ok" ] || { rm -f "$new"; die "下载新版脚本失败，检查网络"; }
  nv=$(sed -n 's/^VERSION=//p' "$new" | head -n 1)
  if [ -n "$nv" ] && version_newer "$nv" "$VERSION"; then
    say_info "新版本 $nv（现在 $VERSION），开始更新"
  else
    say_ok "脚本已经是最新（$VERSION），顺便检查 ipatool"
  fi
  chmod 755 "$new"
  sh "$new" --apply-update
  rm -f "$new"
}

do_uninstall() {
  [ -f "$CONF" ] || [ -d "$BASE" ] || die "没装过"
  detect_os
  ask_yn "确定卸载吗？会删掉 $BASE（包括 Apple ID 登录凭证和没下完的文件）" n || exit 0
  lock_take
  port=$(cfg_get listen_port 2>/dev/null || true)
  dom=$(cfg_get https_domain 2>/dev/null || true)
  svc_remove "$SVC" "$BASE/run.sh"
  svc_remove "$SVC_CADDY" "$BASE/run-caddy.sh"
  if [ -n "$dom" ]; then close_firewall 80 443; else close_firewall "$port"; fi
  if { [ -n "$(swap_files)" ] || [ -f "$ZRAM_FLAG" ]; } && ask_yn "要把安装时加的虚拟内存也删掉吗？" y; then
    remove_swap
  fi
  rm -rf "$BASE" "$LOG"
  rm -f "$CMD_LINK"
  if grep -q 'ipa-web' "$QIEQU_LINK" 2>/dev/null; then rm -f "$QIEQU_LINK"; fi
  say_ok "卸载干净了"
}

main_menu() {
  must_installed
  inst=$(cfg_get script_version)
  if [ -n "$inst" ] && version_newer "$VERSION" "$inst"; then
    say_info "这份脚本是 $VERSION，装着的是 $inst。"
    if ask_yn "更新到 $VERSION 吗？（保留设置和登录）" y; then apply_update; fi
  fi
  while :; do
    printf '\n%s\n' "${C_BOLD}======== ipa-web 管理 v$VERSION ========${C_NC}"
    printf '  1) 查看状态 / 网址\n'
    printf '  2) 切区 / 管理 Apple ID 账号（也可以直接运行 qiequ）\n'
    printf '  3) 修改网页密码\n'
    printf '  4) 改设置（端口、地区、保留时间、同时下载数、自动更新）\n'
    printf '  5) 重启网页服务\n'
    printf '  6) 看运行日志\n'
    printf '  7) 更新脚本和 ipatool\n'
    printf '  8) 重新安装（重新回答所有问题，保留 Apple ID 登录）\n'
    printf '  9) 卸载\n'
    printf '  s) 虚拟内存：重新检测，不够就自动加\n'
    printf '  0) 退出\n'
    ask "选哪个" "0"
    case "$ANSWER" in
      1) show_status ;;
      2) (qiequ_main) ;;
      3) do_reset_password ;;
      4) (do_settings) ;;
      5) do_restart ;;
      6) do_log ;;
      7) do_upgrade ;;
      8) (fresh_install) ;;
      9) do_uninstall; exit 0 ;;
      s|S) do_swap ;;
      *) exit 0 ;;
    esac
  done
}

usage() {
  sed -n '2,32p' "$SELF" 2>/dev/null | sed 's/^#//'
}

#----------------------------------------------------------------------
# 入口
#----------------------------------------------------------------------
case "$0" in
  /*) SELF=$0 ;;
  *) SELF=$(pwd)/$0 ;;
esac

case "${1:-}" in
  --status) need_root; show_status ;;
  --login) need_root; do_login ;;
  --qiequ) need_root; shift; qiequ_main "$@" ;;
  --reset-password) need_root; do_reset_password ;;
  --settings) need_root; do_settings ;;
  --log) do_log "${2:-60}" ;;
  --restart) need_root; do_restart ;;
  --upgrade) need_root; do_upgrade ;;
  --update-ipatool) need_root; lock_take; detect_os; install_ipatool ;;
  --apply-update) need_root; apply_update ;;
  --uninstall) need_root; do_uninstall ;;
  --reinstall) fresh_install ;;
  --swap) need_root; do_swap ;;
  --swap-boot) need_root; detect_os; [ -f "$ZRAM_FLAG" ] && zram_on "$(cat "$ZRAM_FLAG")" ;;
  -h|--help) usage ;;
  "")
    need_root
    if [ -f "$CONF" ] && [ -f "$BASE/app/server.py" ]; then main_menu; else fresh_install; fi
    ;;
  *) say_err "不认识的参数：$1"; usage; exit 1 ;;
esac
