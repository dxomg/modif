#!/bin/bash

red() {
    echo -e "\033[31m\033[01m$1\033[0m"
}

green() {
    echo -e "\033[32m\033[01m$1\033[0m"
}

yellow() {
    echo -e "\033[33m\033[01m$1\033[0m"
}

# 判断系统及定义系统安装依赖方式
REGEX=("debian" "ubuntu" "centos|red hat|kernel|oracle linux|alma|rocky" "'amazon linux'")
RELEASE=("Debian" "Ubuntu" "CentOS" "CentOS")
PACKAGE_UPDATE=("apt -y update" "apt -y update" "yum -y update" "yum -y update")
PACKAGE_INSTALL=("apt -y install" "apt -y install" "yum -y install" "yum -y install")
PACKAGE_REMOVE=("apt -y remove" "apt -y remove" "yum -y remove" "yum -y remove")
PACKAGE_UNINSTALL=("apt -y autoremove" "apt -y autoremove" "yum -y autoremove" "yum -y autoremove")

CMD=("$(grep -i pretty_name /etc/os-release 2>/dev/null | cut -d \" -f2)" "$(hostnamectl 2>/dev/null | grep -i system | cut -d : -f2)" "$(lsb_release -sd 2>/dev/null)" "$(grep -i description /etc/lsb-release 2>/dev/null | cut -d \" -f2)" "$(grep . /etc/redhat-release 2>/dev/null)" "$(grep . /etc/issue 2>/dev/null | cut -d \\ -f1 | sed '/^[ ]*$/d')")

for i in "${CMD[@]}"; do
    SYS="$i" && [[ -n $SYS ]] && break
done

for ((int = 0; int < ${#REGEX[@]}; int++)); do
    [[ $(echo "$SYS" | tr '[:upper:]' '[:lower:]') =~ ${REGEX[int]} ]] && SYSTEM="${RELEASE[int]}" && [[ -n $SYSTEM ]] && break
done

[[ $EUID -ne 0 ]] && red "请在root用户下运行脚本" && exit 1

[[ -z $SYSTEM ]] && red "不支持当前VPS的系统，请使用主流操作系统" && exit 1
[[ -n $(type -P wg-quick) ]] && red "Wgcf-WARP已经安装，脚本即将退出"

main=`uname  -r | awk -F . '{print $1}'`
minor=`uname -r | awk -F . '{print $2}'`
vpsvirt=`systemd-detect-virt`

archAffix(){
    case "$(uname -m)" in
        i686 | i386) echo '386' ;;
        x86_64 | amd64 ) echo 'amd64' ;;
        armv5tel) echo 'armv5' ;;
        armv6l) echo 'armv6' ;;
        armv7 | armv7l) echo 'armv7' ;;
        armv8 | arm64 | aarch64 ) echo 'arm64' ;;
        s390x ) echo 's390x' ;;
        * ) red "不支持的CPU架构！" && exit 1 ;;
    esac
}

check_tun(){
    TUN=$(cat /dev/net/tun 2>&1 | tr '[:upper:]' '[:lower:]')
    if [[ ! $TUN =~ 'in bad state' ]] && [[ ! $TUN =~ '处于错误状态' ]] && [[ ! $TUN =~ 'Die Dateizugriffsnummer ist in schlechter Verfassung' ]]; then
        if [[ $vpsvirt == "openvz" ]]; then
            wget -N --no-check-certificate https://raw.githubusercontents.com/Misaka-blog/tun-script/master/tun.sh && bash tun.sh
        else
            red "检测到未开启TUN模块，请到VPS控制面板处开启" 
            exit 1
        fi
    fi
}

checkCentOS8(){
    if [[ -n $(cat /etc/os-release | grep "CentOS Linux 8") ]]; then
        yellow "检测到当前VPS系统为CentOS 8，是否升级为CentOS Stream 8以确保软件包正常安装？"
        read -p "请输入选项 [y/n]：" comfirmCentOSStream
        if [[ $comfirmCentOSStream == "y" ]]; then
            yellow "正在为你升级到CentOS Stream 8，大概需要10-30分钟的时间"
            sleep 1
            sed -i -e "s|releasever|releasever-stream|g" /etc/yum.repos.d/CentOS-*
            yum clean all && yum makecache
            dnf swap centos-linux-repos centos-stream-repos distro-sync -y
        else
            red "已取消升级过程，脚本即将退出！"
            exit 1
        fi
    fi
}

install_wireguard_centos(){
    ${PACKAGE_INSTALL[int]} epel-release
    ${PACKAGE_INSTALL[int]} net-tools wireguard-tools iptables
    if [[ $main -lt 5 ]] || [[ $minor -lt 6 ]]; then 
        if [[ $vpsvirt =~ "kvm"|"xen"|"microsoft" ]]; then
            vsid=`grep -i version_id /etc/os-release | cut -d \" -f2 | cut -d . -f1`
            curl -Lo /etc/yum.repos.d/wireguard.repo https://copr.fedorainfracloud.org/coprs/jdoss/wireguard/repo/epel-$vsid/jdoss-wireguard-epel-$vsid.repo
            ${PACKAGE_INSTALL[int]} wireguard-dkms
        fi
    fi
}

install_wireguard_debian(){
    ${PACKAGE_INSTALL[int]} lsb-release
    echo "deb http://deb.debian.org/debian $(lsb_release -sc)-backports main" | tee /etc/apt/sources.list.d/backports.list
    ${PACKAGE_UPDATE[int]}
    ${PACKAGE_INSTALL[int]} --no-install-recommends net-tools iproute2 openresolv dnsutils wireguard-tools iptables
    if [[ $main -lt 5 ]] || [[ $minor -lt 6 ]]; then
        if [[ $vpsvirt =~ "kvm"|"xen"|"microsoft" ]]; then
            ${PACKAGE_INSTALL[int]} --no-install-recommends linux-headers-$(uname -r)
            ${PACKAGE_INSTALL[int]} --no-install-recommends wireguard-dkms
        fi
    fi
}

install_wireguard_ubuntu(){
    ${PACKAGE_INSTALL[int]} --no-install-recommends net-tools iproute2 openresolv dnsutils wireguard-tools iptables
}

install_wireguard(){
    ${PACKAGE_UPDATE[int]}
    [[ -z $(type -P curl) ]] && ${PACKAGE_INSTALL[int]} curl
    [[ -z $(type -P sudo) ]] && ${PACKAGE_INSTALL[int]} sudo
    [[ $SYSTEM == CentOS ]] && install_wireguard_centos
    [[ $SYSTEM == Debian ]] && install_wireguard_debian
    [[ $SYSTEM == Ubuntu ]] && install_wireguard_ubuntu
    if [[ $vpsvirt =~ lxc|openvz ]]; then
        wget -N --no-check-certificate https://cdn.jsdelivr.net/gh/Misaka-blog/Misaka-WARP-Script/files/wireguard-go -O /usr/bin/wireguard-go
        chmod +x /usr/bin/wireguard-go
    fi
    if [[ $vpsvirt == zvm ]]; then
        wget -N --no-check-certificate https://cdn.jsdelivr.net/gh/Misaka-blog/Misaka-WARP-Script/files/wireguard-go-s390x -O /usr/bin/wireguard-go
        chmod +x /usr/bin/wireguard-go
    fi
}

install_wgcf(){
    wget -N --no-check-certificate https://cdn.jsdelivr.net/gh/Misaka-blog/Misaka-WARP-Script/files/wgcf_latest_linux_$(archAffix) -O /usr/local/bin/wgcf
    chmod +x /usr/local/bin/wgcf
}

register_wgcf(){
    rm -f wgcf-account.toml
    until [[ -a wgcf-account.toml ]]; do
        yellow "We are applying for an account with CloudFlare WARP, please be patient if you are prompted with 429 Too Many Requests error."
        yes | wgcf register
        sleep 5
    done
    chmod +x wgcf-account.toml
}

generate_wgcf_config(){
    yellow "Please just Press Enter :)"
    read -p "Press Enter" WPPlusKey
    if [[ -n $WPPlusKey ]]; then
        sed -i "s/license_key.*/license_key = \"$WPPlusKey\"/g" wgcf-account.toml
        read -p "请输入自定义设备名，如未输入则使用默认随机设备名：" WPPlusName
        green "注册WARP+账户中，如下方显示：400 Bad Request，则使用WARP免费版账户" 
        if [[ -n $WPPlusName ]]; then
            wgcf update --name $(echo $WPPlusName | sed s/[[:space:]]/_/g)
        else
            wgcf update
        fi
    fi
    wgcf generate
    chmod +x wgcf-profile.conf
    sed -i '/\:\:\/0/d' wgcf-profile.conf
    sed -i 's/engage.cloudflareclient.com/[2606:4700:d0::a29f:c001]/g' wgcf-profile.conf
    sed -i 's/1.1.1.1/2606:4700:4700::1001,2606:4700:4700::1111,2001:4860:4860::8888,2001:4860:4860::8844,1.1.1.1,8.8.8.8,8.8.4.4/g' wgcf-profile.conf
}

get_best_mtu(){
    v66=`curl -s6m8 https://ip.gs -k`
    v44=`curl -s4m8 https://ip.gs -k`
    MTUy=1500
    MTUc=10
    if [[ -n ${v66} && -z ${v44} ]]; then
        ping='ping6'
        IP1='2606:4700:4700::1001'
        IP2='2001:4860:4860::8888'
    else
        ping='ping'
        IP1='1.1.1.1'
        IP2='8.8.8.8'
    fi
    while true; do
        if ${ping} -c1 -W1 -s$((${MTUy} - 28)) -Mdo ${IP1} >/dev/null 2>&1 || ${ping} -c1 -W1 -s$((${MTUy} - 28)) -Mdo ${IP2} >/dev/null 2>&1; then
            MTUc=1
            MTUy=$((${MTUy} + ${MTUc}))
        else
            MTUy=$((${MTUy} - ${MTUc}))
            if [[ ${MTUc} = 1 ]]; then
                break
            fi
        fi
        if [[ ${MTUy} -le 1360 ]]; then
            MTUy='1360'
            break
        fi
    done
    MTU=$((${MTUy} - 80))
    green "MTU optimal value=$MTU is set"
    sed -i "s/MTU.*/MTU = $MTU/g" wgcf-profile.conf
}

cpto_wireguard(){
    if [[ ! -d "/etc/wireguard" ]]; then
        mkdir /etc/wireguard
    fi
    mv -f wgcf-profile.conf /etc/wireguard/wgcf.conf
    mv -f wgcf-account.toml /etc/wireguard/wgcf-account.toml
}

start_wgcf(){
    yellow "Wgcf-WARP is starting"
    wg-quick up wgcf >/dev/null 2>&1
    WgcfWARPStatus=$(curl -s4m8 https://www.cloudflare.com/cdn-cgi/trace -k | grep warp | cut -d= -f2)
    until [[ $WgcfWARPStatus =~ on|plus ]]; do
        red "Unable to start Wgcf-WARP, trying to reboot"
        wg-quick down wgcf >/dev/null 2>&1
        wg-quick up wgcf >/dev/null 2>&1
        WgcfWARPStatus=$(curl -s4m8 https://www.cloudflare.com/cdn-cgi/trace -k | grep warp | cut -d= -f2)
        sleep 8
    done
    systemctl enable wg-quick@wgcf >/dev/null 2>&1
    WgcfIPv4=$(curl -s4m8 https://ip.gs -k)
    green "Wgcf-WARP has been started successfully"
    yellow "The IPv4 IP of Wgcf-WARP is：$WgcfIPv4"
    # rm -f warp64.sh
}

install(){
    install_wireguard
    [[ -z $(type -P wgcf) ]] && install_wgcf
    register_wgcf
    generate_wgcf_config
    get_best_mtu
    cpto_wireguard
    start_wgcf
}

# check_tun
checkCentOS8
install
