#########################################################################
# File Name: siri.sh
# Author: wumengdong
# mail: wumengdong@sensorsdata.com.cn
# Created Time: Sat 13 Mar 2021 03:27:22 PM KST
# 增加脚本报错信息输出，避免 1s 出结果问题 2022-06-09
# 适配 zstd 压缩格式 2022-06-09
# 采用 python 调用接口方式获取主机名，避免主机名获取错误问题 2022-06-09
# 优化脚本，日期选择支持正则 2022-12-19
#########################################################################
#!/bin/bash
 
# 定义颜色函数
function color_theme() {
    RED='\E[1;31m'
    GREEN='\E[1;32m'
    YELLOW='\E[1;33m'
    RES='\E[0m'
}
 
# 1：定义 web 日志拉取函数
web_log() {
    log_dir=~/web_log
    if [ -e $log_dir ]; then
        rm -f $log_dir/*.log
    else
        mkdir -p $log_dir
    fi
    # 定义查找日志子函数
    findlog() {
        ssh -p $port $host "pwd" 2>&1 >/dev/null
        if [ $? -ne 0 ]; then
            echo -e "${RED}错误：ssh 连接远程主机${host} 失败，请排查网络问题！${RES}"
            break
        fi
        num_start=$(ssh $host "cat -n ${log}|egrep "$start_time:[0-9]{2}\.[0-9]{3}"" | head -1 | awk -F ' ' {'print $1'})
        if [ -z $num_start ]; then
            echo -e "${RED}错误：这个查询日志开始时间 $start_time 不在日志范围内，请重新输入查询时间！${RES}\n"
            exit
        fi
        num_end=$(ssh $host "cat -n ${log}|egrep "$stop_time:[0-9]{2}\.[0-9]{3}"" | head -1 | awk -F ' ' {'print $1'})
        if [ -z $num_end ]; then
            echo -e "${RED}错误：这个查询日志结束时间 $stop_time 不在日志范围内，请重新输入查询时间!${RES}\n"
            exit
        fi
        ssh -p ${port} $host "sed -n $num_start,${num_end}p $log" >$log_dir/${pj}-web_${host}.log
    }
    # 判断服务器时区是否为 cst，如果不是则发出提醒
    timezone() {
        localtime=$(timedatectl 2>&1 | grep Local | awk -F " " '{print $NF}')
        if [ $localtime != "CST" ]; then
            echo -e "${YELLOW}注意：当前机器时区为 $localtime,非 CST,请按机器实际时间查找日志！！！${RES}"
        fi
    }
    # web 日志拉取的主函数控制体
    main() {
        clear
        cat <<EOF
            ---请选择要查看的日志---
            1: sa 的 web 日志 !
            2: sps 的 web 日志 !
            3: sdg 的 web 日志 !
EOF
        timezone
        read -p "请选择【1/2/3】:" choice
        read -p "请选择查询日志的起始时间[如08:00] : " start_time
        read -p "请选择查询日志的结束时间[如09:00] : " stop_time
        if [ $choice -eq 1 ]; then
            pj="sa"
            log=$SENSORS_ANALYTICS_LOG_DIR/web/web.log
        elif [ $choice -eq 2 ]; then
            pj="sps"
            log=$SENSORS_PERSONAS_LOG_DIR/web/web.log
        elif [ $choice -eq 3 ]; then
            pj="sdg"
            log=$SENSORS_DATA_GOVERNOR_LOG_DIR/web/web.log
        else
            echo "退出！！！"
            exit
        fi
        spadmin config get client -m web 2>&1 | awk -F "//|:" {'print $3'} | grep -v "^$" | grep -v 'INFO' >${log_dir}/host.txt
        host_num=$(cat ${log_dir}/host.txt | wc -l)
        echo
        i=1
        while [ $i -le $host_num ]; do
            host1=$(sed -n ${i}p ${log_dir}/host.txt)
            # 将 hostname 对应的 ip 取出来，有时候主机名 ssh 不过去
            host=$(sudo grep $host1 /etc/hosts | grep -v "#" | awk -F " " '{print $1}')
            findlog
            echo -e "---------------- ${i}:结束查找 $host -----------------"
            i=$(expr $i + 1)
        done
    }
    main
    echo -e "\n${GREEN}=====所有查询结束，结果存放在【 ${log_dir} 】=====${RES}\n"
}
 
# 2：定义 nginx 数据拉取函数
nginx_log() {
    nginx_log=$(spadmin config get server -m nginx -n access_log_dir -p sp 2>&1 | awk -F '"' {'print $2'})
    exec 2>/dev/null
    source /home/sa_cluster/.bashrc
    a=""
    if [ $SENSORS_DATAFLOW_HOME = $a ]; then
        deconding=${SENSORS_PLATFORM_HOME}/extractor/bin/sa-nginx-log-translator
    else
        deconding=${SENSORS_DATAFLOW_HOME}/extractor/bin/sa-nginx-log-translator
    fi
 
    find_nginx_log() {
        cat >$log_dir/find_log.sh <<EOF
            for file in \`ls ${nginx_log}|egrep "$riqi"\`
            do
                cat ${nginx_log}/\${file}|$deconding --all 2>&1 |$search
            done
            for file in \`ls ${nginx_log}/old|egrep "$riqi"\`
                do
                    format=\`echo \$file|awk -F "." '{print \$3}'\`
                    if [ \$format = "gz" ];then
                    echo "当前执行命令：zcat ${nginx_log}/old/\${file}|$deconding --all 2>&1 |$search"
                    zcat ${nginx_log}/old/\${file}|$deconding --all 2>&1 |$search
                    elif [ \$format = "zstd" ];then
                    echo "当前执行命令：cat ${nginx_log}/old/\${file}|zstd -d|$deconding --all 2>&1|$search"
                    cat ${nginx_log}/old/\${file}|zstd -d|$deconding --all 2>&1|$search
                    fi
 
                done
EOF
        ssh -p $port $node "pwd" 2>&1 >/dev/null
        if [ $? -ne 0 ]; then
            echo -e "${RED}错误：ssh 连接远程主机${node} 失败，请排查网络问题！[错误代码：ssh -p $port $node]${RES}"
            break
        else
            ssh -p $port $node <$log_dir/find_log.sh >>${log_out}.$node.log
        fi
    }
    disck() {
        #显示日志路径的磁盘容量信息
        use=$(df ~/nginx_log -h | awk -F " " '{print $5}' | cut -d "%" -f 1 | tail -1)
        if [ $use -gt 80 ]; then
            echo -e "\n${RED}现在日志磁盘使用率为:$use%，为防止影响业务正常使用，请处理完磁盘空间后再使用此脚本拉取日志！${RES}\n" && exit
        else
            echo -e "\r${GREEN}++++++++++++++++ 当前日志磁盘使用率为:${use}%，放心干！++++++++++++++++${RES}"
        fi
    }
    main() {
        disck
        log_dir=~/nginx_log
        if [ -e $log_dir ]; then
            rm -f $log_dir/*.log
        else
            mkdir -p $log_dir
        fi
        log_out="$log_dir/nginx_log"
        #获取 nginx 主机
        cat >$log_dir/NignxHostGet.py <<EOF
#!/usr/bin/env python3
from hyperion_client.deploy_topo import DeployTopo
print(DeployTopo().get_host_list_by_module_name('sp', 'nginx'))
EOF
        #python3 $log_dir/NignxHostGet.py | awk -F "," '{for(i=0;++i<=NF;)a[i]=a[i]?a[i] FS $i:$i}END{for(i=0;i++<NF;)print a[i]}' | sed s#\'##g | sed 's#\[##g' | sed 's#\]##g' > $log_dir/nginx_host.txt
        python3 $log_dir/NignxHostGet.py | awk -F "," '{for(i=0;++i<=NF;)a[i]=a[i]?a[i] FS $i:$i}END{for(i=0;i++<NF;)print a[i]}' | sed s#\'##g | sed 's#\[##g' | sed 's#\]##g' | sed 's/ //g' > $log_dir/nginx_host.txt
         host_num=$(cat $log_dir/nginx_host.txt | wc -l)
        #命令行提示输入
        echo "请输入想要查询日志的日期[ 如 202101010[3-9] ]："
        read -a riqi
        echo "请输入想要查询的关键词(支持正则表达式)[ 如 grep "123" ]: "
        read search
        echo -e "\n"
        i=1
        while [ $i -le $host_num ]; do
            {
                node=$(sed -n ''${i}p'' $log_dir/nginx_host.txt)
                echo -e "${YELLOW}---------------- ${i}:正在查找【$node】请耐心等待 -----------------${RES}"
                disck
                find_nginx_log
                echo -ne "\r${GREEN}++++++++++++++++ ${i}:结束查找【$node】++++++++++++++++\n${RES}"
            } &
            i=$(expr $i + 1)
        done
    }
    main
    wait
    echo -e "\n${GREEN}=====所有查询结束，结果存放在文件夹【 ${log_dir} 】=====${RES}"
}
 
# 3:定义 OOM 查看函数
oom_check() {
    for i in $(python3 $SENSORS_PLATFORM_HOME/tools/optools/get_machine_info.py 2>&1 | egrep ':([0-9]{1,3}\.){3}' | awk -F ":|," '{for(i=0;++i<=NF;)a[i]=a[i]?a[i] FS $i:$i}END{for(i=0;i++<NF;)print a[i]}' | egrep '([0-9]{1,3}\.){3}'); do echo -e "\n主机：$i" && ssh $i "hostname -f && sudo grep "Out" /var/log/messages | tail -5"; done
}
 
# 4:定义 nginx_access 查看函数
nginx_access() {
    hostname=$(spadmin status -m nginx -p sp 2>&1 | egrep -v "INFO|product" | sed 's/+//g' | sed 's/|//g' | grep -v "^$" | sed ":a;N;s/\n//g;ta" | sed 's/ //g' | awk -F "@|:" '{for(i=0;++i<=NF;)a[i]=a[i]?a[i] FS $i:$i}END{for(i=0;i++<NF;)print a[i]}' | egrep -v "nginx|8108")
 
    echo "请输入想要查询日志的日期[ 如 20220101 ]："
    read -a riqi
    echo "请输入想要查询的关键词[如grep "123"]: "
    read search
 
    for i in $hostname; do echo -e "\n主机：$i" && ssh $i "hostname -f && sudo cat $SENSORS_PLATFORM_LOG_DIR/nginx/web.access.log.$riqi" | $search | tail -5; done
}
 
clear
color_theme
#用户检查，脚本必须在 sa_cluster 用户下执行
user_name=$(whoami)
if [ ${user_name} != "sa_cluster" ]; then
    echo -e "${RED_COLOR}please check:usename should be sa_cluster.${RES}" && exit
fi
# 获取主机 ssh 端口
ssh_port=$(sudo cat /etc/ssh/sshd_config | grep -i -w "port" | grep -v "#" |head -1| awk -F " " '{print $NF}')
port=22
if [ $ssh_port ]; then
    port=$ssh_port
fi
# sp 版本检测
sp_ver=$(spadmin upgrader version 2>&1 | grep -w sp | awk '{print $NF}' | awk -F "." '{print $1}')
cat <<EOF
    ---Hi,i am siri,can i help y? ---
    1：想拉取 web 日志！
    2：想查看 nginx 日志！
    3：想看看主机 OOM 情况！
    4: 想查看 nginx 的 web.access.log 请求日志！
EOF
read -p "请选择【1/2/3/4】:" choice
if [ $choice -eq 1 ]; then
    web_log
elif [ $choice -eq 2 ]; then
    nginx_log
elif [ $choice -eq 3 ]; then
    oom_check
elif [ $choice -eq 4 ]; then
    nginx_access
else
    exit
fi
   