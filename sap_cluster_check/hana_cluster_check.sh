#!/bin/bash
######################################################################
# The script will check HANA HA configuration and cluster status
# Author: Alibaba Cloud, SAP Product & Solution Team
######################################################################
# Tool Versions
TOOL_VERSION='1.3'


######################################################################
# Global variable
######################################################################
OS_HOSTNAME=$(hostname)
OS_DISTRIBUTOR="UNKNOWN-OS"
OS_RELEASE="UNKNOWN-VERSION"
OS_INFO=$(zypper --no-remote --no-refresh --xmlout --non-interactive products -i)
which lsb_release >/dev/null 2>&1 && OS_DISTRIBUTOR="$(lsb_release -a | grep 'Distributor ID' | awk  '{print $3}' 2>/dev/null)"
[[ -z "${OS_DISTRIBUTOR}" ]] && OS_DISTRIBUTOR=$(expr "$OS_INFO" : '.*vendor=\"\(\w*\)\".*')
which lsb_release >/dev/null 2>&1 && OS_RELEASE="$(lsb_release -a | grep 'Release' | awk  '{print $2}' 2>/dev/null)"
[[ -z "${OS_RELEASE}" ]] && OS_RELEASE=$(expr "$OS_INFO" : '.*version=\"\([\.0-9]*\)\".*')
OS_FOR_SAP="Not for SAP"
$(cat /etc/issue | tr 'a-z' 'A-Z' |  grep -q "FOR SAP") && OS_FOR_SAP="For SAP"

OS_PRIVATE_IP=$(curl http://100.100.100.200/latest/meta-data/private-ipv4 -s)

DEFAULT_LOG_FIFO='/tmp/check_tool.fifo'
DEFAULT_LOG_FILE='check_tool.log'
DEFAULT_PARAMETERS_FILE='params.cfg'
DEFAULT_REPORT_FILE='report.txt'
# DEFAULT_LOG_LEVEL: ERROR-0 WARNING-1 INFO-2 DEBUG-3
DEFAULT_LOG_LEVEL='2'

LOG_FILE="${DEFAULT_LOG_FILE}"
LOG_LEVEL="${DEFAULT_LOG_LEVEL}"

TASKS_ID=()
# Declare -A TASKS_TAG
declare -A TASKS_NAME
declare -A TASKS_DESCRIBE
declare -A TASKS_STATUS
# Declare -A TASKS_TIME
declare -A TASKS_START_TIME
declare -A TASKS_END_TIME
declare -A TASKS_EXIT_CODE
declare -A TASKS_EXIT_MSG
declare -A TASKS_RES

# Color
COLOR_GREEN='\033[32m'
COLOR_YELLOW='\033[33m'
COLOR_RED='\033[31m'
COLOR_END='\033[0m'

START_TIME="$(date +%s)"


######################################################################
# Init options
######################################################################
function help(){
    cat <<EOF
version: ${TOOL_VERSION}
help: $1 [options]
    -h, --help              Show this help message and exit
    -v, --version           Show version
    -u, --update            Check and download the latest version
    -D, --debug             Set log level to debug
For example: $0
EOF
    exit 0
}

function show_version(){
    echo "${TOOL_VERSION}"
    exit 0
}

function update(){
    local latest_version=$(curl https://sh-test-hangzhou.oss-cn-hangzhou.aliyuncs.com/saptool/latest-version -s)
    if [[ $(echo "${latest_version} == ${TOOL_VERSION}"| bc ) -eq 1 ]]
    then
        echo "Already the latest version!"
        exit
    fi

    if [[ $(echo "${latest_version} < ${TOOL_VERSION}"| bc ) -eq 1 ]]
    then
        echo "Error: current version is ${TOOL_VERSION}, but latest version is ${latest_version}！"
        exit
    fi

    if [[ $(echo "${latest_version} > ${TOOL_VERSION}"| bc ) -eq 1 ]]
    then
        echo "Current version: ${TOOL_VERSION}"
        echo "Latest  version: ${latest_version}"
        wget -q "https://sh-test-hangzhou.oss-cn-hangzhou.aliyuncs.com/saptool/hana_cluster_check.sh" -O "hana_cluster_check_v${latest_version}.sh" || exit 1
        chmod +x "hana_cluster_check_v${latest_version}.sh"
        echo "Downloaded: hana_cluster_check_v${latest_version}.sh"
        exit
    fi
}

eval set -- `getopt -o hvDu:: -l help,version,update,debug:: -n "$0" -- "$@"`
while true
do
    case "$1" in
        -h| --help)
            help;;
        -v| --version)
            show_version;
            shift 2;;
        -u| --update)
            update;
            shift 2;;
        -D| --debug)
            LOG_LEVEL="3";
            shift 2;;
        -- ) shift; break ;;
        *) echo "Unknow parameter($1)"; exit 1 ;;
    esac
done


######################################################################
# Log functions
######################################################################
function log(){
    local msg=$1
    local level=$2
    local datetime=`date +'%F %H:%M:%S'`
    local logformat="${datetime} ${BASH_SOURCE[1]}[`caller 1 | awk '{print $1}'`]: ${msg}"
    if [[ ${level} -le ${LOG_LEVEL} ]]
    then
        case ${level} in
            0)
                echo -e "\033[31m[ERROR] ${logformat}\033[0m";;
            1)
                echo -e "\033[33m[WARNING] ${logformat}\033[0m";;
            2)
                echo -e "\033[32m[INFO] ${logformat}\033[0m";;
            3)
                echo -e "\033[37m[DEBUG] ${logformat}\033[0m";;
        esac
    fi
}

function error_log(){
    log "$*" 0
}

function warning_log(){
    log "$*" 1
}

function info_log(){
    log "$*" 2
}

function debug_log(){
    log "$*" 3
}

function log_title(){
    local title="$1"
    local max_len=100
    local sep="-"
    let str_num=(${max_len} - ${#title})/2
    fill_str=$(eval "printf '%0.1s' '-'{1..$str_num}")
    log "${fill_str}${title}${fill_str}" 2
}

function error_code_log(){
    TASK_CODE="$1"
    TASK_MSG="$2"
    TASK_STATUS="ERROR"
    log "${TASK_CODE}: ${TASK_MSG}" 0
}

function warning_code_log(){
    TASK_CODE="$1"
    TASK_MSG="$2"
    TASK_STATUS="WARNING"
    log "${TASK_CODE}: ${TASK_MSG}" 1
}

######################################################################
# Parameter functions
######################################################################
function save_param(){
    local param_name=$1
    local param_value=$2
    grep -q "^${param_name}" "${DEFAULT_PARAMETERS_FILE}"
    if [[ $? -eq 0 ]]
    then
        debug_log "Set parameter value: ${param_name}=${param_value}"
        sed -i "s/^${param_name}.*/${param_name}=${param_value}/" "${DEFAULT_PARAMETERS_FILE}"
    else
        debug_log "Save parameter: ${param_name}=${param_value}"
        echo "${param_name}=${param_value}" >> "${DEFAULT_PARAMETERS_FILE}"
    fi
}

function get_bool_param(){
    local param_name=$1
    local param_lable=$2
    debug_log "Get boolean type parameter: ${param_name}"
    eval param_value="\$$param_name"
    if [[ -z ${param_value} ]]
    then
        read -p "Please input ${param_lable}(y/n): " value
        if [[ -z "${value}" ]] || [[ "${value}" != "n" && "${value}" != "y" ]]
        then
            read -p "Please input ${param_lable}('y' or 'n'): " value
        fi
        if [[ -z "${value}" ]] || [[ "${value}" != "n" && "${value}" != "y" ]]
        then
            error_log "Invalid parameter(${param_name})"
            exit 1
        fi
        debug_log "Get parameter ${param_name}: ${value}"
        eval "${param_name}=${value}"
    else
        read -p "Please input ${param_lable}(y/n)[${param_value}]: " value
        if [[ -z "${value}" ]]
        then
            return
        fi

        if [[ "${value}" != 'y' ]] && [[ "${value}" != 'n' ]]
        then
            read -p "Please input ${param_lable}(y/n)[${param_value}]: " value
        fi
        if [[ "${value}" -ne 'y' ]] && [[ "${value}" -ne 'n' ]]
        then
            error_log "Invalid boolean type parameter ${param_name}: ${value}"
            exit 1
        fi
        debug_log "Got boolean type parameter ${param_name}: ${value}"
        eval "${param_name}=${value}"
    fi
}

function get_param(){
    local param_name=$1
    local param_lable=$2

    debug_log "Get parameter ${param_name}"
    eval param_value="\$$param_name"
    if [[ -z ${param_value} ]]
    then
        read -p "Please input ${param_lable}: " value
        if [[ -z "${value}" ]]
        then
            read -p "Please input ${param_lable}: " value
        fi
        if [[ -z "${value}" ]]
        then
            error_log "Input parameter(${param_name}) is null"
            exit 1
        fi

        debug_log "Get parameter ${param_name}: ${value}"
        eval "${param_name}=${value}"
    else
        read -p "Please input ${param_lable}[${param_value}]: " value
        if [[ -n "${value}" ]]
        then
            debug_log "Get parameter ${param_name}: ${value}"
            eval "${param_name}=${value}"
        fi
    fi
}

function get_hana_sid(){
    get_param "HANASID" "SAP HANA SID"
    info_log "SAP HANA SID is ${HANASID}"
}

function get_sid_adm(){
    if [[ -z "${HANASID}" ]]
    then
        get_hana_sid
    fi
    SIDAdm="$(echo ${HANASID} |tr '[:upper:]' '[:lower:]')adm"
    info_log "<SID>adm user name is ${SIDAdm}"
}

function get_master_hostname(){
    get_param "MasterNode" "hostname of master node in the cluster"
    info_log "The hostname of master node in the cluster is ${MasterNode}."
}

function get_slave_hostname(){
    get_param "SlaveNode" "hostname of slave node in the cluster"
    info_log "The hostname of slave node in the cluster is ${SlaveNode}."
}

function get_master_ip(){
    get_param "MasterIpAddress" "IP address of master node"
    info_log "The IP address of master node is ${MasterIpAddress}."
}

function get_slave_ip(){
    get_param "SlaveIpAddress" "IP address of slave node"
    info_log "The IP address of slave node is ${SlaveIpAddress}."
}

function get_is_two_net_card(){
    get_bool_param "IsTwoNetworkCard" "Whether to enable redundant NICs"
    info_log "Whether to enable redundant NICs: ${IsTwoNetworkCard}."
}

function get_master_heartbeat_ip(){
    get_param "MasterHeartbeatIpAddress" "heartbeat IP address of master node"
    info_log "Heartbeat IP address of master node is ${MasterHeartbeatIpAddress}."
}

function get_slave_heartbeat_ip(){
    get_param "SlaveHeartbeatIpAddress" "heartbeat IP address of slave node"
    info_log "Heartbeat IP address of slave node is ${SlaveHeartbeatIpAddress}."
}

function get_havip_ip(){
    get_param "HaVipIpAddress" "Highly available virtual IP address"
    info_log "Highly available virtual IP address is ${HaVipIpAddress}."
}

function get_instance_number(){
    get_param "InstanceNumber" "HANA instance number"
    info_log "HANA instance number is ${InstanceNumber}."
}

######################################################################
# Output report functions
######################################################################
function report_head(){
    REPORT_HEAD=`cat <<EOF
######################################################################
SAP HANA High Availability Cluster Check Tool
Version: ${TOOL_VERSION}
######################################################################
Start Time: $(date -d @${START_TIME[${task_id}]} '+%Y-%m-%d %H:%M:%S') 
Operating System :${OS_DISTRIBUTOR} ${OS_RELEASE} ${OS_FOR_SAP}
EOF
`
}

function report_conclusion(){
    REPORT_CONCLUSION=`cat <<EOF
################################
# 1.Report Summary
################################\n
EOF
`
    info_log "Number of failed tasks: ${TASK_FAILED_COUNT}"
    info_log "Number of warning tasks: ${TASK_WARNING_COUNT}"
    if [[ ${TASK_FAILED_COUNT} -eq 0 ]] && [[ ${TASK_WARNING_COUNT} -eq 0 ]]
    then
        REPORT_CONCLUSION_MSG="    \033[32m No warnings and errors, the cluster is running normally.\033[0m"
    fi

    if [[ ${TASK_FAILED_COUNT} -eq 0 ]] && [[ ${TASK_WARNING_COUNT} -ne 0 ]]
    then
        REPORT_CONCLUSION_MSG="    \033[33m The cluster is running with warnings(${TASK_WARNING_COUNT}),please check.\033[0m"
    fi

    if [[ ${TASK_FAILED_COUNT} -ne 0 ]] && [[ ${TASK_WARNING_COUNT} -eq 0 ]]
    then
        REPORT_CONCLUSION_MSG="    \033[31m There are (${TASK_FAILED_COUNT})errors,please check and correct the errors.\033[0m"
    fi

    if [[ ${TASK_FAILED_COUNT} -ne 0 ]] && [[ ${TASK_WARNING_COUNT} -ne 0 ]]
    then
        REPORT_CONCLUSION_MSG="    \033[31m There are (${TASK_FAILED_COUNT})errors and (${TASK_WARNING_COUNT})warnings,please check and correct the errors.\033[0m"
    fi
    REPORT_CONCLUSION+="${REPORT_CONCLUSION_MSG}"
}

function report_cluster_status(){
    local line
    REPORT_CLUSTER_STATUS=`cat <<EOF
################################
# 2.Cluster Status
################################\n
EOF
`
    run_cmd "crm_mon -1 | grep -q 'cluster is not available'"
    if [[ "${RES_CODE}" -eq 0 ]]
    then
        REPORT_CLUSTER_STATUS+="Error: cluster is not available"
        return
    fi

    # crm_mon -1 | sed -e '1,5d' | while read line
    REPORT_CLUSTER_STATUS+=$(crm_mon -1 | while read line ;do echo "    ${line}"; done )
}

function add_table_head(){
    for t in "$@"
    do
        TABLE_HEAD+="|${t}${SEP}"
        BOUNDARY_LINE+="+${SEP}"
    done
    BOUNDARY_LINE+="+\n"
    TABLE_HEAD+="|\n"
    TABLE_HEAD="${BOUNDARY_LINE}${TABLE_HEAD}${BOUNDARY_LINE}"
}

function add_table_line(){
    local cell
    for cell in "$@"
    do
        TABLE_BODY+="|${cell}${SEP}"
    done
    TABLE_BODY+="|\n"
    TABLE_BODY+="${BOUNDARY_LINE}"
}

function report_task_table(){
    REPORT_TASK_TABLE=`cat <<EOF
################################
# 3.Tasks Overview
################################\n
EOF
`
    SEP="#"
    TABLE_HEAD=""
    BOUNDARY_LINE=""
    TABLE_BODY=""
    local task_count=1
    local table

    add_table_head "Index" "Task Name" "Status" "Error Code"
    for task_id in ${TASKS_ID[@]}
    do 
        add_table_line "${task_count}" "${TASKS_NAME[${task_id}]}" "${TASKS_STATUS[${task_id}]}" "${TASKS_EXIT_CODE[${task_id}]}"
        let task_count++
    done

    table=$(echo -e "${TABLE_HEAD}${TABLE_BODY}" | column -s "${SEP}" -t | awk '/^\+/{gsub(" ", "-", $0)}1')
    table=$(echo -e "${table}" | sed -e "s/SUCCESS/\\${COLOR_GREEN}SUCCESS\\${COLOR_END}/g")
    table=$(echo -e "${table}" | sed -e "s/ERROR/\\${COLOR_RED}ERROR\\${COLOR_END}/g")
    table=$(echo -e "${table}" | sed -e "s/WARNING/\\${COLOR_YELLOW}WARNING\\${COLOR_END}/g")
    REPORT_TASK_TABLE+="${table}"
}

function report_detail(){
    local task_id="$1"
    local task_status="${TASKS_STATUS[${task_id}]}"

    [[ "${task_status}" == "SUCCESS" ]] && task_status="${COLOR_GREEN}SUCCESS${COLOR_END}"
    [[ "${task_status}" == "WARNING" ]] && task_status="${COLOR_YELLOW}WARNING${COLOR_END}"
    [[ "${task_status}" == "ERROR" ]] && task_status="${COLOR_RED}ERROR${COLOR_END}"

    info_log "${TASKS_NAME[${task_id}]}: ${task_status}"
    # Task Time       : $((${TASKS_END_TIME[${task_id}]} - ${TASKS_START_TIME[${task_id}]}))s
    REPORT_TASK_DETAIL+=`cat <<EOF
[${task_id}]
    Task Name       : ${TASKS_NAME[${task_id}]}
    Task Status     : ${task_status}
    Task Describe   : ${TASKS_DESCRIBE[${task_id}]}
    Task Start Time : $(date -d @${TASKS_START_TIME[${task_id}]} '+%Y-%m-%d %H:%M:%S') 
    Task End Time   : $(date -d @${TASKS_END_TIME[${task_id}]} '+%Y-%m-%d %H:%M:%S') 
EOF
`
    REPORT_TASK_DETAIL+="\n"
    if [[ "${TASKS_STATUS[${task_id}]}" == "WARNING" ]]
    then
        REPORT_TASK_DETAIL+="    Task WARNING    : ${TASKS_EXIT_CODE[${task_id}]} ${TASKS_EXIT_MSG[${task_id}]}.\n"
    fi
    if [[ "${TASKS_STATUS[${task_id}]}" == "ERROR" ]]
    then
        REPORT_TASK_DETAIL+="    Task Error      : ${TASKS_EXIT_CODE[${task_id}]} ${TASKS_EXIT_MSG[${task_id}]}\n"
    fi
    # REPORT_TASK_DETAIL+="    Task Result     : ${TASKS_RES[${task_id}]}\n"
    REPORT_TASK_DETAIL+="\n"
}

function report(){
    REPORT=""
    REPORT_TASK_DETAIL=`cat <<EOF
################################
# 4.Tasks
################################\n
EOF
`
    TASK_WARNING_COUNT=0
    TASK_FAILED_COUNT=0
    TASK_SUCCESS_COUNT=0
    for task_id in ${TASKS_ID[@]}
    do
        report_detail "${task_id}"

        if [[ "${TASKS_STATUS[${task_id}]}" == "WARNING" ]]
        then
            TASK_WARNING_COUNT=$((${TASK_WARNING_COUNT} + 1))
        fi
        if [[ "${TASKS_STATUS[${task_id}]}" == "ERROR" ]]
        then
            TASK_FAILED_COUNT=$((${TASK_FAILED_COUNT} + 1))
        fi
        if [[ "${TASKS_STATUS[${task_id}]}" == "SUCCESS" ]]
        then
            TASK_SUCCESS_COUNT=$((${TASK_SUCCESS_COUNT} + 1))
        fi
    done

    # Report header
    report_head
    REPORT+="${REPORT_HEAD}"
    REPORT+="\n\n\n\n"

    # Check result
    report_conclusion
    REPORT+="${REPORT_CONCLUSION}"
    REPORT+="\n\n\n\n"

    # Cluster status
    report_cluster_status
    REPORT+="${REPORT_CLUSTER_STATUS}"
    REPORT+="\n\n\n\n"

    # Task list
    report_task_table
    REPORT+="${REPORT_TASK_TABLE}"
    REPORT+="\n\n\n\n"

    # Task detail
    REPORT+="${REPORT_TASK_DETAIL}"

    echo -e "${REPORT}" > "${DEFAULT_REPORT_FILE}"
}


######################################################################
# Exit functions
######################################################################
function err_exit(){
    rm -rf ${DEFAULT_LOG_FIFO}
    exit
}


######################################################################
# Check command functions
######################################################################
function run_cmd(){
    local command="$1"
    local user="$2"
    if [[ -z "${user}" ]]
    then
        debug_log "command: ${command}"
        RES="$(eval $command 2>&1)"
    else
        debug_log "command:su - ${user} -c \"${command}\""
        RES=$(su - "${user}" -c "${command}" 2>&1)
    fi
    RES_CODE=$?
    debug_log "command exit code: ${RES_CODE}"
    debug_log "command result: \n${RES}"
}

function run_cmd_remote(){
    local ip=$1
    local user=$2
    local command=$3
    debug_log "Command: ssh ${user}@${ip} ${command}"
    RES=$(ssh "${user}@${ip}" "${command}" 2>&1)
    RES_CODE=$?
    debug_log "command exit code: ${RES_CODE}"
    debug_log "command result: \n${RES}"
}


######################################################################
# Task functions
######################################################################
# Task Functions
function run_task(){
    TASK_START_TIME="$(date +%s)"

    local task_func="$1"
    local task_run_count="${2:-1}"
    local task_retry_time="${3:-30}"

    if [[ "${#TASK_PARAMETES[*]}" -ne 0 ]]
    then
        task_run_count='3'
        task_retry_time='0'
    fi

    info_log "Start to run task '${TASK_NAME}'"
    for c in $(seq 1 ${task_run_count})
    do
        TASK_CODE=""
        TASK_STATUS=""
        TASK_MSG=""

        ${task_func}
        if [[ "${TASK_STATUS}" != "ERROR" ]]
        then
            break
        fi

        if [[ "${task_run_count}" -eq "1" ]] || [[ "${c}" -eq "${task_run_count}" ]]
        then
            break
        fi

        if [[ "${#TASK_PARAMETES[*]}" -ne 0 ]]
        then
            info_log "Please check the parameters and try again later."
        else
            info_log "Try again after ${task_retry_time} seconds."
            sleep "${task_retry_time}"
        fi
    done

    TASK_END_TIME="$(date +%s)"

    # TASK_COUNT=$((${TASK_COUNT} + 1))
    TASKS_ID[${#TASKS_ID[*]}]="${TASK_ID}"
    # TASKS_TAG+=(["${TASK_ID}"]="${TASK_TAG}")
    TASKS_NAME+=(["${TASK_ID}"]="${TASK_NAME}")
    TASKS_DESCRIBE+=(["${TASK_ID}"]="${TASK_DESCRIBE}")
    # TASKS_TIME+=(["${TASK_ID}"]="${TASK_TIME}")
    TASKS_START_TIME+=(["${TASK_ID}"]="${TASK_START_TIME}")
    TASKS_END_TIME+=(["${TASK_ID}"]="${TASK_END_TIME}")
    TASKS_EXIT_CODE+=(["${TASK_ID}"]="${TASK_CODE}")
    TASKS_EXIT_MSG+=(["${TASK_ID}"]="${TASK_MSG}")
    TASKS_RES+=(["${TASK_ID}"]="${RES}")
    TASKS_STATUS+=(["${TASK_ID}"]="${TASK_STATUS:=SUCCESS}")
    debug_log "TASK_ID: ${TASK_ID}"
    debug_log "TASK_NAME: ${TASK_NAME}"
    debug_log "TASK_STATUS: ${TASK_STATUS}"
    debug_log "TASK_CODE: ${TASK_CODE}"
    debug_log "TASK_MSG: ${TASK_MSG}"
    debug_log "RES: ${RES}"

    # save paramaters
    for param_name in ${TASK_PARAMETES[@]}
    do
        save_param "${param_name}" "${!param_name}"
    done
    info_log "'${TASK_NAME}' running task has been completed."
}

##############################
# Check system services functions
function _check_os_version(){
    info_log "Check whether the OS version is supported."

    if [[ "${OS_DISTRIBUTOR}" != 'SUSE' ]]
    then
        error_code_log "NotSupportedOS.${OS_DISTRIBUTOR}" "Not supported(${OS_DISTRIBUTOR})."
        return
    fi
    
    if [[ "${OS_FOR_SAP}" == 'Not for SAP' ]]
    then
        warning_code_log "NotForSAP" "OS is not SUSE for sap version."
        return
    fi
    info_log "OS is SUSE（${OS_DISTRIBUTOR} ${OS_RELEASE})"
}

function check_os_version(){
    TASK_ID="CheckOSVersion"
    TASK_NAME="OS Version"
    TASK_DESCRIBE="Check whether the OS version is supported"
    TASK_PARAMETES=()
    run_task "_check_os_version"
}

function _check_update_etc_hosts(){
    info_log "Check whether the 'update_etc_hosts' module is turned off."
    run_cmd "grep -qP '^ - update_etc_hosts' /etc/cloud/cloud.cfg"
    if [[ ${RES_CODE} -eq 0 ]]
    then
        warning_code_log "NotClosedUpdateEtcHosts" "The 'update_etc_hosts' module is turned on, it is recommended to set ' - update_etc_hosts' to '# - update_etc_hosts' in the '/etc/cloud/cloud.cfg' file."
    fi
    info_log "The 'update_etc_hosts' module is turned off."
}

function check_update_etc_hosts(){
    TASK_ID="CheckUpdateEtcHosts"
    TASK_NAME="Automatic hostname update"
    TASK_DESCRIBE="Check whether the 'update_etc_hosts' module is turned off"
    TASK_PARAMETES=()
    run_task "_check_update_etc_hosts"
}

function _check_ntp_service(){
    info_log "Check whether the NTP service is activated."

    # SUSE 15 and higher
    if [[ "${OS_DISTRIBUTOR}" == 'SUSE' ]] && [[ $(echo "${OS_RELEASE} >= 15"| bc ) -eq 1 ]]
    then
        run_cmd "systemctl status chronyd.service"
        if [[ ${RES_CODE} -ne 0 ]]
        then
            warning_code_log "NotRunning.chronyd" "chronyd.service(NTP daemon) status is abnormal,please check the serivce with command 'systemctl status chronyd.service'"
            return
        fi
        info_log "Chronyd(NTP daemon) service is running, the NTP serivce is running."
        return
    fi

    # SUSE 12 and higher
    if [[ "${OS_DISTRIBUTOR}" == 'SUSE' ]] && [[ $(echo "${OS_RELEASE} >= 12"| bc ) -eq 1 ]]
    then
        run_cmd "systemctl status ntpd"
        if [[ ${RES_CODE} -ne 0 ]]
        then
            warning_code_log "NotRunning.ntpd" "ntpd status(NTP daemon) is abnormal,please check the serivce with command 'systemctl status ntpd'"
            return
        fi
        info_log "ntpd(NTP daemon) service is running, the NTP serivce is running."
        return
    fi
    # Other OS
    warning_code_log "NotSupported.System" "This OS version(${OS_DISTRIBUTOR} ${OS_RELEASE})is not supported to check NTP service, please manually check the service and configuration of NTP."
}

function check_ntp_service(){
    TASK_ID="CheckNtpService"
    TASK_NAME="NTP serivce"
    TASK_DESCRIBE="Check whether the NTP service is activated"
    TASK_PARAMETES=()
    run_task "_check_ntp_service"
}

function _check_clock_source(){
    info_log "Check whether the system clocksource is set to 'tsc'."
    run_cmd "cat /sys/devices/system/clocksource/clocksource0/available_clocksource | grep tsc | wc -l"
    if [[ "${RES}" -eq 0 ]]
    then
        warning_code_log "UnavailableClockSource.tsc" "There is no 'tsc' clocksource in available clocksources"
        return
    fi

    run_cmd "cat /sys/devices/system/clocksource/clocksource0/current_clocksource"
    if [[ "${RES}" != "tsc" ]]
    then
        warning_code_log "NotCurrentClockSource.tsc" "Current system clocksource is ${RES}, not set to 'tsc',it is recommended to set to 'tsc'."
        return
    fi
    info_log "Current system clocksource is set to 'tsc'."

}

function check_clock_source(){
    TASK_ID="CheckClockSource"
    TASK_NAME="Clocksource"
    TASK_DESCRIBE="Check whether the system clocksource is set to 'tsc'"
    TASK_PARAMETES=()
    run_task "_check_clock_source"
}

##############################
# Check packages functions
function _check_package_installed(){
    local package_name="$1"
    info_log "Check whether it is installed '${package_name}'"
    run_cmd "rpm -qa ${package_name}"
    if [[ -z "${RES}" ]]
    then
        NOT_INSTALLED_PACKAGE+="${package_name}, "
        error_log "'${package_name}' is not installed,please check and install it."
    fi
    info_log "${package_name} version is ${RES}"
}

function _check_package(){
    info_log "Check whether packages are installed"
    NOT_INSTALLED_PACKAGE=""
    _check_package_installed "corosync"
    _check_package_installed "SAPHanaSR"
    _check_package_installed "patterns-ha-ha_sles"
    _check_package_installed "saptune"
    _check_package_installed "resource-agents"
    _check_package_installed "pacemaker"
    _check_package_installed "sbd"

    if [[ -n "${NOT_INSTALLED_PACKAGE}" ]]
    then
        debug_log "NOT_INSTALLED_PACKAGE: ${NOT_INSTALLED_PACKAGE}"
        error_code_log "NotInstalledPackage.[${NOT_INSTALLED_PACKAGE:0:-2}]" "Not install:${NOT_INSTALLED_PACKAGE:0:-2}"
    fi
    info_log "All packages related to SAP high availability are installed."
}

function check_package(){
    TASK_ID="CheckPackage"
    TASK_NAME="Installation packages"
    TASK_DESCRIBE="Check whether packages are installed"
    TASK_PARAMETES=()
    run_task "_check_package"
}

function _check_package_version(){
    info_log "Check whether the package 'resource-agent' version is fulfil the requirement."

    run_cmd "rpm -qa resource-agents"
    if [[ $(echo "${RES} resource-agents-4.0.2" | tr " " "\n" | sort -rV | head -1) == "resource-agents-4.0.2" ]]
    then
        error_code_log "UnavailableVersion.resource-agent" "Resource-agents is (${RES}), lower than 4.0.2,please update or install resource-agent package."
        return
    fi
    info_log "Resource-agent version is higher than 4.0.2 fulfil the requirement"
}

function check_package_version(){
    TASK_ID="CheckPackageVersion"
    TASK_NAME="Packages version"
    TASK_DESCRIBE="Check whether the package 'resource-agent' version is fulfil the requirement"
    TASK_PARAMETES=()
    run_task "_check_package_version"
}


##############################
# Check hostname functions
function _check_dhcp_configure(){
    info_log "Check whether the DHCP configuration is correct in the '/etc/sysconfig/network/dhcp' file."
    run_cmd "grep '^DHCLIENT_SET_HOSTNAME=' /etc/sysconfig/network/dhcp | grep -q 'no'" 
    if [[ ${RES_CODE} -ne 0 ]]
    then
        warning_code_log "WrongDHCPConfiguration.DHCLIENT_SET_HOSTNAME" "Incorrect DHCP configuration,Please check whether the 'DHCLIENT_SET_HOSTNAME' parameter is set to 'no' in the '/etc/sysconfig/network/dhcp' file."
        return
    fi
    info_log "No errors were found in the '/etc/sysconfig/network/dhcp' file."
}

function check_dhcp_configure(){
    TASK_ID="CheckDHCPConfiguration"
    TASK_NAME="DHCP configration"
    TASK_DESCRIBE="Check whether the DHCP configuration is correct"
    TASK_PARAMETES=(
    )
    run_task "_check_dhcp_configure"
}

function _check_hostname_configure(){
    info_log "Check whether the hostname configuration is correct in the '/etc/hosts' file."
    run_cmd "cat /etc/hosts | grep -qP '^127.0.0.1\s+${OS_HOSTNAME}'" 
    if [[ ${RES_CODE} -eq 0 ]]
    then
        error_code_log "WrongHostConfiguration" "There is a wrong item '127.0.0.1 ${OS_HOSTNAME}' in the '/etc/hosts' file,please delete or comment out it."
        return
    fi
    info_log "No errors were found in the '/etc/hosts' file."
}

function check_hostname_configure(){
    TASK_ID="CheckHostnameConfigure"
    TASK_NAME="Hostname configuration"
    TASK_DESCRIBE="Check hostname configuration in the '/etc/hosts' file"
    TASK_PARAMETES=(
    )
    run_task "_check_hostname_configure"
}

function _check_hosts_pingable(){
    info_log "Use command 'ping' to check the connectivity of two nodes in the cluster."
    # Get master node hostname
    get_master_hostname
    # Get slave node hostname
    get_slave_hostname

    if [[ "${OS_HOSTNAME}" == "${MasterNode}" ]]
    then
        # Current HANA node is the primary node
        # Get slave node IP address
        get_slave_ip

        MasterIpAddress="${OS_PRIVATE_IP}"
        ClusterMemberHostname="${SlaveNode}"
        ClusterMemberIp="${SlaveIpAddress}"
    elif [[ "${OS_HOSTNAME}" == "${SlaveNode}" ]]
    then
        # Current HANA node is the secondary node
        # Get master node IP address
        get_master_ip

        SlaveIpAddress="${OS_PRIVATE_IP}"
        ClusterMemberHostname="${MasterNode}"
        ClusterMemberIp="${MasterIpAddress}"
    else
        error_code_log "NotClusterNode.${OS_HOSTNAME}" "Current HANA node is not in the cluster,please check the entered hostname."
        return
    fi
    
    local cluster_member_hostname="${ClusterMemberHostname}"
    local cluster_member_ip="${ClusterMemberIp}"

    run_cmd "ping ${cluster_member_hostname} -c 1"
    if [[ ${RES_CODE} -ne 0 ]]
    then
        error_code_log "NotPingableHost.${cluster_member_hostname}" "Run command:'ping ${cluster_member_hostname}'failed,please check the network connection or '/etc/hosts' file"
        return
    fi

    run_cmd "ping ${cluster_member_hostname} -c 1 | grep -q '${cluster_member_hostname} (${cluster_member_ip})'" 
    if [[ ${RES_CODE} -ne 0 ]]
    then
        error_code_log "UnmatchIPAddress" "Run command:'ping ${cluster_member_hostname}',the node(${cluster_member_hostname}) IP address does not match the entered IP(${cluster_member_ip}), please check the '/etc/hosts' file."
        return
    fi
    info_log "Use command 'ping' to check the node ${cluster_member_hostname},the connectivity of two nodes in the cluster is normal."
}

function check_hosts_pingable(){
    TASK_ID="CheckHostsPingable"
    TASK_NAME="Node connectivity"
    TASK_DESCRIBE="Check the connectivity of two nodes in the cluster"
    TASK_PARAMETES=(
        "MasterNode"
        "SlaveNode"
        "MasterIpAddress"
        "SlaveIpAddress"
    )
    run_task "_check_hosts_pingable"
}

function _check_host_mutual_trust(){
    info_log "Check SSH mutual trust between two nodes"
    local c_hostname="${ClusterMemberHostname}"
    local res=$(
        expect -c "
        spawn ssh -o StrictHostKeyChecking=no root@${c_hostname} echo 1234
        expect {
        \"*assword\" {set timeout 1000; send \"test\n\"; exp_continue ; sleep 1; }
        \"yes/no\" {send \"yes\n\"; exp_continue;}
        \"Disconnected\" {send \"\n\"; }
        \"1234\" {send \"\n\"; }
        }
        interact"
    )
    run_cmd "echo '${res}' | grep -q 'assword'"
    if [[ "${RES_CODE}" -eq 0 ]]
    then
        error_code_log "NotConfiguredMutualTrust.${c_hostname}" "Mutual trust is not configured with node '${c_hostname}'"
    fi
}

function check_host_mutual_trust(){
    TASK_ID="CheckHostMutualTrust"
    TASK_NAME="SSH mutual trust"
    TASK_DESCRIBE="Check SSH mutual trust between two nodes in the cluster"
    TASK_PARAMETES=(
    )
    run_task "_check_host_mutual_trust"
}


###############################################
# Check HANA node role and HSR status functions
function _check_node_role(){
    local sidadm="${SIDAdm}"

    run_cmd "hdbnsutil  -sr_state | grep 'is source system: true'" "${sidadm}"
    if [[ "${RES_CODE}"  -eq '0' ]] && [[ "${MasterNode}" == "${OS_HOSTNAME}" ]]
    then
        info_log "Current HANA node is the primary node."
        MasterNode="${OS_HOSTNAME}"
        SlaveNode="${ClusterMemberHostname}"
        return
    fi
    
    run_cmd "hdbnsutil  -sr_state | grep 'is secondary/consumer system: true'" "${sidadm}"
    if [[ "${RES_CODE}"  -eq '0' ]] && [[ "${SlaveNode}" == "${OS_HOSTNAME}" ]]
    then
        info_log "Current HANA node is the secondary node."
        MasterNode="${ClusterMemberHostname}"
        SlaveNode="${OS_HOSTNAME}"
        return
    fi
    error_code_log "UnkownHANANode" "Unknown role of the HANA node(${NODE_MODE}),please check HSR(HANA system replication) status."
    return 1
}

function _check_hana_node(){
    info_log "Check current HANA node status."
    # Get HANA SID
    get_hana_sid
    if ! $(echo "${HANASID}" | grep -qP '^([A-Z]{1}[0-9A-Z]{2})$')
    then
        error_code_log "WrongHANASID" "The SAP HANA SID(${HANASID}) is 3 characters, can including capital letter or number, and must starting with capital letter."
        return
    fi

    run_cmd "grep -q 'SAPSYSTEMNAME = ${HANASID}' /hana/shared/${HANASID}/profile/DEFAULT.PFL"
    if [[ ${RES_CODE} -ne 0 ]]
    then
        error_code_log "WrongHANASID" "The SAP HANA SID(${HANASID}) not found in '/hana/shared/${HANASID}/profile/DEFAULT.PFL' file."
        return
    fi

    # Get <SID>adm user
    get_sid_adm

    local sidadm="${SIDAdm}"

    _check_node_role || return

    if [[ "${OS_HOSTNAME}" == "${MasterNode}" ]]
    then
        # Check HSR status
        info_log "Check HSR(HANA systyem replication) status."
        run_cmd "cdpy && python systemReplicationStatus.py | grep -q 'overall system replication status: ACTIVE'" "${sidadm}"
        if [[ ${RES_CODE} -ne 0 ]]
        then
            error_code_log "WrongHSRStatus" "The HSR(HANA systyem replication) status is wrong,please check and fix it."
            return
        fi
    fi
    info_log "The HSR(HANA systyem replication) status is correct."
}

function check_hana_node(){
    TASK_ID="CheckHANANodeStatus"
    TASK_NAME="HANA node status"
    TASK_DESCRIBE="Check the HANA node status"
    TASK_PARAMETES=(
        "HANASID"
        "SIDAdm"
    )
    run_task "_check_hana_node"
}


##############################
# Check STONITH functions
function _check_stonith_device(){
    info_log "Check whether the STONITH configuration is correct."
    # Check STONITH device type
    run_cmd "crm_mon -1 | grep -q 'stonith:external/sbd'"
    if [[ ${RES_CODE} -eq 0 ]]
    then
        # Check sbd
        info_log "Current STONITH is SBD(STONITH Block Device)fencing."
        #  Check ​/etc/sysconfig/sbd
        info_log "Check SBD configuration file '/etc/sysconfig/sbd'"
        run_cmd "grep -P '^SBD_DEVICE=' /etc/sysconfig/sbd | sed -e 's/SBD_DEVICE=//g'| sed -e 's/\"//g' | tail -1"

        local sbd_disk="${RES}"
        if [[ -z "${sbd_disk}" ]]
        then
            error_code_log "NotConfigured.SBD.SBD_DEVICE" "The 'SBD_DEVICE' parameter is not configured, please check whether 'SBD_DEVICE=<shared block storage disk path>' is correctly configured in the file '/etc/sysconfig/sbd', for example: SBD_DEVICE=/dev/vdf."
            return
        fi
        info_log "STONITH device is shared storage(${sbd_disk})."

        run_cmd "grep -P '^SBD_STARTMODE=' /etc/sysconfig/sbd | grep -q clean"
        if [[ ${RES_CODE} -ne 0 ]]
        then
            error_code_log "NotConfigured.SBD.SBD_STARTMODE" "The 'SBD_STARTMODE' parameter is not configured, please check whether 'SBD_STARTMODE=clean' is configured in the file '/etc/sysconfig/sbd'."
            return
        fi

        run_cmd "grep -P '^SBD_OPTS=\"\"' /etc/sysconfig/sbd"
        if [[ ${RES_CODE} -eq 0 ]]
        then
            error_code_log "NotConfigured.SBD.SBD_OPTS" "The 'SBD_OPTS' parameter is not configured, please check whether 'SBD_OPTS' is configured in the file '/etc/sysconfig/sbd'."
            return
        fi
        info_log "No errors were found in the '/etc/sysconfig/sbd' file."
        
        # info_log "检查sbd状态"
        # run_cmd " ps -ef | grep sbd | wc -l"
        # if [[ ${RES_CODE} -ne 0 ]]
        # then
        #     error_code_log "NotRunning.sbd" "sbd未运行"
        #     return
        # fi
        # info_log "watchdog已配置开机自启"

        # Check watchdog
        info_log "Check whether the watchdog startup automatically after OS reboot."
        run_cmd "grep -q 'modprobe softdog' /etc/init.d/boot.local"
        if [[ ${RES_CODE} -ne 0 ]]
        then
            error_code_log "NotEnabledBootStart.watchdog" "The watchdog is not configured to startup automatically after OS reboot, please add 'modprobe softdog' to '/etc/init.d/boot.local'"
            return
        fi
        info_log "The watchdog has been configured to startup automatically after OS reboot."

        info_log "Check whether the watchdog configuration is correct."
        run_cmd "ls -l /dev/watchdog* | wc -l"
        if [[ "${RES}" -ne 2 ]]
        then
            error_code_log "NotConfigured.Watchdog" "The watchdog is not configured, please execute the command:'modprobe softdog' and use the command:'ls -l /dev/watch*' to check'/dev/watchdog' and'/dev/watchdog0'."
            return
        fi
        info_log "The watchdog has been configured."
        return
    fi

    run_cmd "crm_mon -1 | grep -q 'stonith:fence_aliyun'"
    if [[ ${RES_CODE} -eq 0 ]]
    then
        info_log "Currently this tool does not support STONITH device 'stonith:fence_aliyun',will support in next version."
    fi
    info_log "No errors were found in STONITH configration."
}

function check_stonith_device(){
    TASK_ID="CheckSTONITHDevice"
    TASK_NAME="STONITH"
    TASK_DESCRIBE="Check STONITH is SBD(STONITH Block Device) fencing with shared storage or fence agent fencing"
    TASK_PARAMETES=(
    )
    run_task "_check_stonith_device"
}


##############################
# Check network functions
function _check_network(){
    info_log "Check whether the NICs configuration are correct."
    # Whether are redundant NICs
    get_is_two_net_card

    if [[ "${IsTwoNetworkCard}" == "n" ]]
    then
        info_log "It is a single NIC configuration, skip the check step."
        return
    fi

    info_log "Check whether the heartbeat NIC configuration is correct."
    # Get parameter HeartbeatIpAddress
    get_slave_heartbeat_ip
    get_master_heartbeat_ip

    if [[ "${OS_HOSTNAME}" == "${MasterNode}" ]]
    then
        ClusterHeartbeatIpAddress="${SlaveHeartbeatIpAddress}"
        CurrentHeartbeatIpAddress="${MasterHeartbeatIpAddress}"
    elif [[ "${OS_HOSTNAME}" == "${SlaveNode}" ]]
    then
        ClusterHeartbeatIpAddress="${MasterHeartbeatIpAddress}"
        CurrentHeartbeatIpAddress="${SlaveHeartbeatIpAddress}"
    else
        error_code_log "NotClusterNode.${OS_HOSTNAME}" "Current HANA node is not in the cluster,please check the entered hostname."
        return
    fi

    run_cmd "ip addr | grep -q ${CurrentHeartbeatIpAddress}"
    if [[ ${RES_CODE} -ne 0 ]]
    then
        error_code_log "NotConfiguredHeartbeatIP" "Run the command 'ip addr | grep -q ${CurrentHeartbeatIpAddress}' failed, please check whether the heartbeat NIC is configured."
        return
    fi

    info_log "The heartbeat NIC has been configured."

    info_log "Check whether the heartbeat IP address is available."
    run_cmd "ping ${CurrentHeartbeatIpAddress} -c 1"
    if [[ ${RES_CODE} -ne 0 ]]
    then
        error_code_log "NotPingableHost.${CurrentHeartbeatIpAddress}" "Run the command 'ping ${CurrentHeartbeatIpAddress} -c 1'failed, please check whether the heartbeat IP address is available."
        return
    fi
    info_log "Heartbeat IP address ${CurrentHeartbeatIpAddress} can be pinged."

    run_cmd "ping ${ClusterHeartbeatIpAddress} -c 1"
    if [[ ${RES_CODE} -ne 0 ]]
    then
        error_code_log "NotPingableHost.${ClusterHeartbeatIpAddress}" "Run the command 'ping ${ClusterHeartbeatIpAddress} -c 1'failed, please check whether the heartbeat IP address is available."
        return
    fi
    info_log "Heartbeat IP address ${ClusterHeartbeatIpAddress} can be pinged."

    info_log "No errors were found in the NICs configuration."
}

function check_network(){
    TASK_ID="CheckNetwork"
    TASK_NAME="NICs configuration"
    TASK_DESCRIBE="Check whether the NICs configuration are correct."
    TASK_PARAMETES=(
        SlaveHeartbeatIpAddress
        MasterHeartbeatIpAddress
    )
    run_task "_check_network"
}


##############################
# Check corosync functions
function _check_corosync_configuration(){
    local transport
    local expected_votes
    info_log "Check whether the corosync configuration is correct in the '/etc/corosync/corosync.conf' file. "

    run_cmd "crm corosync get totem.transport"
    transport="${RES}"
    if [[ "${transport}" != 'udpu' ]]
    then
        error_code_log "NotConfiguredCorosync.totem.transport" "Corosync transport protocol(${transport}) configuration error, please confirm that the configuration item of'totem.transport' is'udpu' in the '/etc/corosync/corosync.conf' file."
        return
    fi
    info_log "Corosync transport protocol is ${transport}."

    run_cmd "crm corosync get quorum.expected_votes"
    expected_votes="${RES}"
    if [[ "${expected_votes}" -ne 2 ]]
    then
        error_code_log "NotConfiguredCorosync.quorum.expected_votes" "Corosync 'expected_votes'(${expected_votes}) configuration item error,please confirm the configuration item 'expected_votes' is set to '2' in the '/etc/corosync/corosync.conf' file."
        return
    fi
    info_log "Corosync expected votes is ${expected_votes}."

    if [[ "${IsTwoNetworkCard}" == "n" ]]
    then
        # Single NIC of corosync configuration file
        info_log "Check whether the single NIC configuration is correct in the '/etc/corosync/corosync.conf' file."
        # nodelist
        run_cmd "crm corosync get nodelist.node.ring0_addr"
        if [[ -z "${RES}" ]]
        then
            error_code_log "NotConfiguredCorosync.nodelist.node" "The item 'Nodelist.node' is not configured, please check the configuration in the '/etc/corosync/corosync.conf' file."
            return
        fi

        for node_ip in $RES
        do
            if [[ "${node_ip}" != "${OS_PRIVATE_IP}" ]] && [[ "${node_ip}" != "${ClusterMemberIp}" ]]
            then
                error_code_log "InvalidNodelistIP.nodelist.node.ring0_addr" "Invalid node IP address(${node_ip}), please check the configuration in the '/etc/corosync/corosync.conf' file."
                return
            fi
            info_log "Node IP address:${node_ip}."
        done
    else
        # Redundant NICs
        # nodelist
        run_cmd "crm corosync get nodelist.node.ring0_addr"
        if [[ -z "${RES}" ]]
        then
            error_code_log "NotConfiguredCorosync.nodelist.node" "'Nodelist.0.node' is not configured, please check the configuration in the '/etc/corosync/corosync.conf' file."
            return
        fi

        for node_ip in $RES
        do
            if [[ "${node_ip}" != "${OS_PRIVATE_IP}" ]] && [[ "${node_ip}" != "${ClusterMemberIp}" ]] && [[ "${node_ip}" != "${MasterHeartbeatIpAddress}" ]] && [[ "${node_ip}" != "${SlaveHeartbeatIpAddress}" ]]
            then
                error_code_log "InvalidNodelistIP.nodelist.node.ring0_addr" "Invalid node IP address(${node_ip}), please check the configuration in the '/etc/corosync/corosync.conf' file."
                return
            fi
            info_log "Node IP address:${node_ip}."
        done

        run_cmd "crm corosync get nodelist.node.ring1_addr"
        if [[ -z "${RES}" ]]
        then
            error_code_log "NotConfiguredCorosync.nodelist.node" "'Nodelist.1.node' is not configured, please check the configuration in the '/etc/corosync/corosync.conf' file."
            return
        fi
        
        for node_ip in $RES
        do
            if [[ "${node_ip}" != "${OS_PRIVATE_IP}" ]] && [[ "${node_ip}" != "${ClusterMemberIp}" ]] && [[ "${node_ip}" != "${MasterHeartbeatIpAddress}" ]] && [[ "${node_ip}" != "${SlaveHeartbeatIpAddress}" ]]
            then
                error_code_log "InvalidNodelistIP.nodelist.node.ring0_addr" "Invalid node IP address(${node_ip}), please check the configuration in the '/etc/corosync/corosync.conf' file."
                return
            fi
            info_log "Node IP address:${node_ip}."
        done
    fi
    info_log "No errors were found in the '/etc/corosync/corosync.conf' file."
}

function check_corosync_configuration(){
    TASK_ID="CheckCorosyncConfiguration"
    TASK_NAME="Corosync configuration"
    TASK_DESCRIBE="Check whether the corosync configuration is correct in the '/etc/corosync/corosync.conf' file"
    TASK_CMD=""
    TASK_PARAMETES=(
        IsTwoNetworkCard
    )
    run_task "_check_corosync_configuration"
}


##################################
# Check cluster resource functions
function _check_resource_configured(){
    local resource_type="$1"
    # Check cluster resouce configuration
    run_cmd "crm configure show | grep '^primitive.*${resource_type}' | cut -d ' ' -f 2"
    if [[ -z "${RES}" ]]
    then
        error_code_log "InvalidResourceConfiguration.${resource_type}" "The cluster crm resource ${resource_type} is not configured.please check and fix it."
        return 1
    fi
}

function _check_resource_params(){
    local resource_type="$1"
    local resource_params_name="$2"
    local resource_params_value="$3"
    local resource_name
    local value

    run_cmd "crm configure show | grep '^primitive.*${resource_type}' | cut -d ' ' -f 2"
    resource_name="${RES}"

    # Check resource value
    for resource_name in $RES
    do
        run_cmd "crm resource param ${resource_name} show ${resource_params_name}"
        value="${RES}"

        run_cmd "echo ${value} | grep -q '${resource_params_value}'"
        if [[ "${RES_CODE}" -ne 0 ]]
        then
            error_code_log "InvalidResourceConfiguration.${resource_name}.${resource_params_name}" "Invalid cluster crm resource configuration parameter value ${resource_params_name}:${value}"
            return 1
        fi
        info_log "${resource_name}.${resource_params_name}: ${value}"
    done
}

function _check_resource_configuration(){
    info_log "Check whether the cluster crm resources configuration are correct."
    # Get parameter HaVipIpAddress
    get_havip_ip
    # Get instance number
    get_instance_number

    local res
    run_cmd "crm configure show"
    if [[ -z "${RES}" ]]
    then
        error_code_log "InvalidResourceConfiguration" "The current node has not configured cluster crm resources or the pacemaker has not started yet.Please check and fix it."
        return
    fi
    # Check ocf:suse:SAPHanaTopology
    _check_resource_configured "ocf:suse:SAPHanaTopology" || return
    _check_resource_params "ocf:suse:SAPHanaTopology" "SID" "${HANASID}" || return
    _check_resource_params "ocf:suse:SAPHanaTopology" "InstanceNumber" "${InstanceNumber}" || return

    # Check ocf:suse:SAPHana
    _check_resource_configured "ocf:suse:SAPHana " || return
    _check_resource_params "ocf:suse:SAPHana " "SID" "${HANASID}" || return
    _check_resource_params "ocf:suse:SAPHana " "InstanceNumber" "${InstanceNumber}" || return


    run_cmd "crm configure show | grep '^primitive.*IPaddr2' | cut -d ' ' -f 2"
    if [[ -n "${RES}" ]]
    then

        # HAVIP
        _check_resource_params "IPaddr2" "ip" "${HaVipIpAddress}" || return
        
        # Check sbd
        _check_resource_configured "stonith:external/sbd" || return
    else
        # move-ip
        run_cmd "crm configure show | grep '^primitive.*ocf:aliyun:vpc-move-ip' | cut -d ' ' -f 2"
        if [[ -n "${RES}" ]]
        then
            _check_resource_params "ocf:aliyun:vpc-move-ip" "address" "${HaVipIpAddress}" || return
            _check_resource_params "ocf:aliyun:vpc-move-ip" "routing_table" "vtb-.*" || return
            _check_resource_params "ocf:aliyun:vpc-move-ip" "endpoint" "vpc.*aliyuncs.com" || return
            _check_resource_params "ocf:aliyun:vpc-move-ip" "interface" "eth." || return
        fi

        # fence_aliyun
        _check_resource_configured "stonith:fence_aliyun" || return
        _check_resource_params "stonith:fence_aliyun" "plug" "i-.*" || return
        _check_resource_params "stonith:fence_aliyun" "ram_role" "..*" || return
        _check_resource_params "stonith:fence_aliyun" "region" "..*" || return
    fi
    info_log "No errors were found in cluster crm resources configuratrion."
}

function check_resource_configuration(){
    TASK_ID="CheckResourceConfiguration"
    TASK_NAME="crm resources configuration"
    TASK_DESCRIBE="Check whether the cluster crm resources configuration are correct"
    TASK_PARAMETES=(
        InstanceNumber
        HaVipIpAddress
    )
    run_task "_check_resource_configuration"
}


##############################
# Check HAVIP functions
function _check_havip_pingable(){
    info_log "Check whether the HaVip(High availability virtual IP) IP address is available."

    run_cmd "ping ${HaVipIpAddress} -c 1"
    if [[ ${RES_CODE} -ne 0 ]]
    then
        error_code_log "NotPingableHost.${HaVipIpAddress}" "Use command 'ping ${HaVipIpAddress} -c 1' failed, please check whether the HaVip(high availability virtual IP) address is available."
        return
    fi
    info_log "'ping' HaVip(High availability virtual IP) IP address is successful,the HaVip(High availability virtual IP) IP address is available."

}

function check_havip_pingable(){
    TASK_ID="CheckHaVipPingable"
    TASK_NAME="HaVip(High availability virtual IP) IP address"
    TASK_DESCRIBE="Check whether the HaVip(High availability virtual IP) IP address is available"
    TASK_PARAMETES=(
    )
    run_task "_check_havip_pingable"
}

##############################
# Check cluster status functions
function _check_cluster_status(){
    local master_node_hostname="${MasterNode}"
    local slave_node_hostname="${SlaveNode}"

    info_log "Check whether the cluster status is correct."

    run_cmd "crm_mon -1 | grep -q 'cluster is not available on this node'"
    if [[ "${RES_CODE}" -eq 0 ]]
    then
        # Pacemaker is not started
        error_code_log "UnknownClusterStatus" "The pacemaker has not started on this node yet,please check the pacemaker status."
        return
    fi

    run_cmd "crm_mon -1 | grep 'Online: \[.*${master_node_hostname}.*\]'"
    if [[ "${RES_CODE}" -ne 0 ]]
    then
        error_code_log "NotOnlineNode.${master_node_hostname}" "'${master_node_hostname}' node is not online,please make the node online."
        return
    fi
    
    run_cmd "crm_mon -1 | grep 'Online: \[.*${slave_node_hostname}.*\]'"
    if [[ "${RES_CODE}" -ne 0 ]]
    then
        error_code_log "NotOnlineNode.${slave_node_hostname}" "'${slave_node_hostname}'node is not online,please make the node online."
        return
    fi
    info_log "Online: ${master_node_hostname} and ${slave_node_hostname}"

    # Check whether the STONITH device is started
    run_cmd "crm_mon -1 | grep -q '(stonith:'"
    if [[ "${RES_CODE}" -ne 0 ]]
    then
        error_code_log "NotConfiguredStonith" "The STONITH has not been configured.Please check and fix it."
        return
    fi

    run_cmd "crm_mon -1 | grep -q 'stonith:external/sbd'"
    if [[ "${RES_CODE}" -eq 0 ]]
    then
        # STONITH is SBD with shared storage
        run_cmd "crm_mon -1 | grep -q 'stonith:external/sbd.*Started'"
        if [[ "${RES_CODE}" -ne 0 ]]
        then
            error_code_log "UnknownSTONITHStatus" "STONITH SBD device has not started yet,please check and fix it."
            return
        fi
        info_log "STONITH SBD device started on ${master_node_hostname}."
    fi

    run_cmd "crm_mon -1 | grep -q 'stonith:fence_aliyun'"
    if [[ "${RES_CODE}" -eq 0 ]]
    then
        # STONITH is fence agent
        run_cmd "crm_mon -1 | grep -q 'stonith:fence_aliyun.*Started ${master_node_hostname}'"
        if [[ "${RES_CODE}" -ne 0 ]]
        then
            error_code_log "UnknownSTONITHStatus.${master_node_hostname}" "The STONITH device is not start or not start on this node '${master_node_hostname}'."
            return
        fi

        run_cmd "crm_mon -1 | grep -q 'stonith:fence_aliyun.*Started ${slave_node_hostname}'"
        if [[ "${RES_CODE}" -ne 0 ]]
        then
            error_code_log "UnknownSTONITHStatus.${slave_node_hostname}" "The STONITH device did not start or not start on this node '${slave_node_hostname}'."
            return
        fi

        info_log "'fence_aliyun' did not start on ${master_node_hostname} and ${slave_node_hostname}."
    fi

    # Check virtual IP crm resources
    run_cmd "crm_mon -1 | grep -q 'ocf::'"
    if [[ "${RES_CODE}" -ne 0 ]]
    then
        error_code_log "NotConfiguredVip" "Virtual IP crm resource is not configured,please check and fix it."
        return
    fi

    # Check HaVip
    run_cmd "crm_mon -1 | grep -q 'ocf::heartbeat:IPaddr2'"
    if [[ "${RES_CODE}" -eq 0 ]]
    then
        run_cmd "crm_mon -1 | grep -q 'ocf::heartbeat:IPaddr2.*Started.*${master_node_hostname}'"
        if [[ "${RES_CODE}" -ne 0 ]]
        then
            error_code_log "UnknownVipStatus.${master_node_hostname}" "The high availability virtual IP crm resource is unavailable or not running on the master node:'${master_node_hostname}.'"
            return
        fi
        info_log "HaVip(High availability virtual IP) started on ${master_node_hostname}"
    fi

    # Check overlay IP(aliyun move-ip)
    run_cmd "crm_mon -1 | grep -q 'ocf::aliyun:vpc-move-ip'"
    if [[ "${RES_CODE}" -eq 0 ]]
    then
        run_cmd "crm_mon -1 | grep -q 'ocf::aliyun:vpc-move-ip.*Started.*${master_node_hostname}'"
        if [[ "${RES_CODE}" -ne 0 ]]
        then
            error_code_log "UnknownVipStatus" "The overlay IP(aliyun move-ip) resource is unavailable or not running on the master node:'${master_node_hostname}'."
            return
        fi
        info_log "The overlay IP(aliyun move-ip) started on ${master_node_hostname}."
    fi

    # Check crm resource msl_SAPHana_<SID> and rsc_SAPHana_<SID> status
    run_cmd "crm_mon -1 | grep -q 'Masters: \[ ${master_node_hostname} \]'"
    if [[ "${RES_CODE}" -ne 0 ]]
    then
        error_code_log "UnknownStatus.MasterNode" "The master node status is unknown, Please check if the master node is online.HANA instance and HSR status are normal."
        return
    fi
    info_log "The master node is: ${master_node_hostname}."

    run_cmd "crm_mon -1 | grep -q 'Slaves: \[ ${slave_node_hostname} \]'"
    if [[ "${RES_CODE}" -ne 0 ]]
    then
        error_code_log "UnknownStatus.SlaveNode" "The slave node status is unknown, Please check if the master node is online.HANA instance and HSR status are normal."
        return
    fi
    info_log "The slave node is: ${slave_node_hostname}."

    # Check crm resource cln_SAPHanaTopology_<SID> and rsc_SAPHanaTopology_<SID> status
    run_cmd "crm_mon -1 | grep 'Started.*\[.*${master_node_hostname}.*' | grep -q 'Started.*${slave_node_hostname}.*'"
    if [[ "${RES_CODE}" -ne 0 ]]
    then
        error_code_log "UnknownStatus.SAPHanaTopology" "SAPHanaTopology crm resouce status is unknown,please check crm resource 'cln_SAPHanaTopology_<SID>' and 'rsc_SAPHanaTopology_<SID>' status."
        return
    fi
    info_log "SAPHanaTopology started on ${master_node_hostname} and ${slave_node_hostname}"
    info_log "The cluster status is correct."
}

function check_cluster_status(){
    TASK_ID="CheckClusterStatus"
    TASK_NAME="Cluster status"
    TASK_DESCRIBE="Check whether the cluster status is correct"
    TASK_PARAMETES=(
    )
    run_task "_check_cluster_status" 3
}


######################################################################
# Init env
######################################################################
#export LESSCHARSET="utf-8"
debug_log "Initialize the operating environment"

debug_log "Initialize the log file and parameters file"
touch "${DEFAULT_LOG_FILE}"
touch "${DEFAULT_PARAMETERS_FILE}"

debug_log "Import parameters file"
source "${DEFAULT_PARAMETERS_FILE}"

debug_log "Create log fifo file"
$(ls "/tmp" | grep -q "${DEFAULT_LOG_FIFO##*/}") || mkfifo "${DEFAULT_LOG_FIFO}"
cat ${DEFAULT_LOG_FIFO} | tee -a ${LOG_FILE} &
exec 1>${DEFAULT_LOG_FIFO} 2>&1

# init_report
######################################################################
# Run Task
######################################################################
log_title "Begain to check HANA HA configuration and cluster status"
# 1. Check system service
log_title "Start to check system service"
# Check OS version
check_os_version
# Check NTP service
check_ntp_service
# 
check_update_etc_hosts
# 
check_clock_source
log_title "Complete the checklist"
info_log "\n"



# 2. Check installation packages
log_title "Start to check installation packages"
# Check sap-suse-cluster-connector、resource-agent packages
check_package
# Check resource-agent package
check_package_version
log_title "Complete the checklist"
info_log "\n"


# 3. Check hostname
log_title "Start to check hostname"
check_hosts_pingable
check_hostname_configure
check_dhcp_configure
check_host_mutual_trust
log_title "Complete the checklist"
info_log "\n"


# 4. Check HANA status
log_title "Start to check HANA status"
check_hana_node
log_title "Complete the checklist"
info_log "\n"

# 5. Check NIC
log_title "Start to check NICs configuration"
check_network
log_title "Complete the checklist"
info_log "\n"

# 6. Check Stonith
log_title "Start to check STONITH"
check_stonith_device
log_title "Complete the checklist"
info_log "\n"

# 7. Check Corosync
log_title "Start to check corosync configuration"
check_corosync_configuration
log_title "Complete the checklist"
info_log "\n"

# 8. Check Resource
log_title "Start to check cluster crm resource configuration"
check_resource_configuration
log_title "Complete the checklist"
info_log "\n"

# 9. Check HaVip
log_title "Start to check HaVip(High availability virtual IP)"
check_havip_pingable
log_title "Complete the checklist"
info_log "\n"

# 9. Check status
log_title "Start to check cluster status"
check_cluster_status
log_title "Complete the checklist"
info_log "\n"


######################################################################
# Exit
######################################################################
# Generate report
log_title "Generating report"
report

# Exit
log_title "Finished"

info_log "Report:${REPORT_CONCLUSION_MSG}"
info_log ""
info_log "Report file: ${DEFAULT_REPORT_FILE}"
info_log "Log file: ${DEFAULT_LOG_FILE}"
info_log "You can view the report '${DEFAULT_REPORT_FILE}' to see the checklist and result in the current directory.You can also check the log file '${DEFAULT_LOG_FILE}' to see the detail information in the current directory."
err_exit 0