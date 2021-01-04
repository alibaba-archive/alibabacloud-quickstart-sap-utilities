#!/bin/bash
###################################################################################################
# hana_backup.sh
# The script use to backup HANA System DB and Tenant DB,only support HANA 2.0 version and higher
# Author: Alibaba Cloud, SAP Product & Solution Team
###################################################################################################
# Versions
VERSION='1.2'
LATEST_VERSION=$(curl -s https://sh-test-hangzhou.oss-cn-hangzhou.aliyuncs.com/sap-utilities/hana-backup/latest-version)
UPDATE_URL='https://sh-test-hangzhou.oss-cn-hangzhou.aliyuncs.com/sap-utilities/hana-backup/hana_backup.sh'


######################################################################
# Global variable
######################################################################
OS_HOSTNAME=$(hostname)
OS_DISTRIBUTOR="$(lsb_release -a | grep 'Distributor ID' | awk  '{print $3}')"
OS_RELEASE="$(lsb_release -a | grep 'Release' | awk  '{print $2}')"

DEFAULT_LOG_FIFO='/tmp/hana_backup.fifo'
DEFAULT_LOG_FILE='hana_backup.log'

# DEFAULT_LOG_LEVEL: ERROR-0 WARNING-1 INFO-2 DEBUG-3
DEFAULT_LOG_LEVEL='2'

LOG_FILE="${DEFAULT_LOG_FILE}"
LOG_LEVEL="${DEFAULT_LOG_LEVEL}"

SILENT_MODE=false
# Default backup file prefix
BACKUP_PREFIX="COMPLETE_DATA_BACKUP_`date +%Y%m%d_%H_%M_%S`"

# Color
COLOR_GREEN='\033[32m'
COLOR_YELLOW='\033[33m'
COLOR_RED='\033[31m'
COLOR_END='\033[0m'

START_TIME="$(date +%s)"


######################################################################
# Help function
######################################################################
function help(){
    cat <<EOF
version: ${VERSION}
help: $1 [options]
    -h, --help              Show this help message and exit
    -v, --version           Show version
    -u, --update            Check and download the latest version
    -s, --silent            Silent mode, for example './hana_backup.sh -s --SID=<SID> --InstanceNumber=<instance number> --MasterPass=<master password> --DatabaseNames=<database names>'
        --SID               SAP HANA DB system ID
        --InstanceNumber    SAP HANA DB instance number
        --MasterPass        SAP HANA DB master password
        --DatabaseNames     SAP HANA DB names, please use ',' as separator, for example 'SYSTEMDB,HDB'
        --BackupDir         Backup directory, the default directory is '/usr/sap/<SID>/HDB<InstanceNumber>/backup/data'
    -D, --debug             Set log level to debug
For example: $0
EOF
    exit 0
}

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


######################################################################
# Version functions
######################################################################
function show_version(){
    echo "${VERSION}"
    exit 0
}

function update(){
    local latest_version="${LATEST_VERSION}"
    if [[ -z "latest_version" ]]
    then
        error_log "Get latest version failed."
        exit 1
    fi
    if [[ $(echo "${latest_version} == ${VERSION}"| bc ) -eq 1 ]]
    then
        info_log "Already the latest version!"
        exit
    fi

    if [[ $(echo "${latest_version} < ${VERSION}"| bc ) -eq 1 ]]
    then
        error_log "Current version is ${VERSION}, but latest version is ${latest_version}！"
        exit
    fi

    if [[ $(echo "${latest_version} > ${VERSION}"| bc ) -eq 1 ]]
    then
        info_log "Current version: ${VERSION}"
        info_log "Latest  version: ${latest_version}"
        wget -q "" -O "hana_backup_v${latest_version}.sh"
        if [[ $? -eq 0 ]]
        then
            error_log "Update failed!"
            exit 1
        fi
        chmod +x "hana_backup_v${latest_version}.sh"
        echo "Downloaded: hana_backup_v${latest_version}.sh"
        exit
    fi
}


######################################################################
# Backup functions
######################################################################
function run_cmd(){
    local command="$1"
    local user="$2"
    if [[ -z "${user}" ]]
    then
        #debug_log "command: ${command}"
        RES="$(eval $command 2>&1)"
    else
        #debug_log "command:su - ${user} -c \"${command}\""
        RES=$(su - "${user}" -c "${command}" 2>&1)
    fi
    RES_CODE=$?

    if [[ ${RES_CODE} -ne 0 ]]
    then
        error_log "$RES"
    fi

    debug_log "command exit code: ${RES_CODE}"
    debug_log "command result: \n${RES}"
}

function get_param(){
    local param_name=$1
    local param_lable=$2
    local param_is_password=$3
    local input_count
    local res_code

    if [[ -n "${param_is_password}" ]]
    then
        local _s=" -s "
    else
        local _s=""
    fi

    param_value="${!param_name}"

    for input_count in 1 2 3
    do
        read ${_s} -p "Please input ${param_lable}：" value
        eval "${param_name}"="${value}"
        check_"${param_name}"
        res_code="$?"
        if [[ $res_code -eq 0 ]]
        then
            break
        else
            [[ ${input_count} -eq 3 ]] && exit 1
        fi

        echo -e "\n"
    done

    [[ -z "${param_is_password}" ]] && info_log "Parameter '${param_name}'：${!param_name}"
}

function check_param(){
    local value="$1"
    local value_re="$2"
    echo "${!value}" | grep -qP "${value_re}"
    if [[ $? -ne 0 ]]
    then
        error_log "${value}(${!value}) does not meet the policy requirements"
        return 1
    fi
}

function get_SID(){
    get_param "SID" "SAP HANA DB system ID"
}

function check_SID(){
    debug_log "SID: ${SID}"
    check_param SID '^([A-Z]{1}[0-9A-Z]{2})$' || return 1

    if ! $(ls /hana/shared | grep -q "${SID}")
    then
        error_log "No directory '${SID}' was found in the directory '/hana/shared', please check SAP HANA DB system ID."
        return 1
    fi
}

function get_SIDAdm(){
    SIDAdm="$(echo ${SID} |tr '[:upper:]' '[:lower:]')adm"
    debug_log "SIDAdm: ${SIDAdm}"
}

function get_InstanceNumber(){
    get_param "InstanceNumber" "SAP HANA DB instance number"
}

function check_InstanceNumber(){
    debug_log "InstanceNumber: ${InstanceNumber}"
    check_param InstanceNumber '^([0-8][0-9]|9[0-6])$' || return 1

    if ! $(ls /hana/shared/${SID} | grep -q "HDB${InstanceNumber}")
    then
        error_log "No directory 'HDB${InstanceNumber}' was found in the directory '/hana/shared/${SID}', please check SAP HANA DB instance number."
        return 1
    fi
}

function get_MasterPass(){
    get_param "MasterPass" "master password" "is_password"
}

function check_MasterPass(){
    if [[ -z "${MasterPass}" ]]
    then
        error_log "Invalid parameter 'MasterPass'."
        return 1
    fi
}

function get_Databases(){
    debug_log 'Query the database list.'
    debug_log "command: hdbsql -u SYSTEM -p ****** -d SYSTEMDB -Axj \"select * from sys_databases.m_services where sql_port !=0\" | sed -e '1,2d' | awk '{print \$2}'"
    run_cmd "hdbsql -u SYSTEM -p ${MasterPass} -d SYSTEMDB -Axj \"select * from sys_databases.m_services where sql_port !=0\" | sed -e '1,2d' | awk '{print \$2}'" "${SIDAdm}"

    if [[ $RES_CODE -ne 0 ]]
    then
        error_log "Failed to query the database."
        exit 1
    fi
    if [[ -z "$RES" ]]
    then
        error_log "Database list is empty."
        exit 1
    fi
    Databases=(${RES})
    info_log "Database list: ${Databases[*]}"
}

function get_DatabaseIndexs(){
    info_log "Current database:"
    for d in $(seq ${#Databases[*]})
    do
        echo "    $((${d} - 1))    ${Databases[$(($d - 1))]}"
    done
    get_param "DatabaseIndexs" "need to backup database index, please use ',' as separator, for example '0,1'"
}

function check_DatabaseIndexs(){
    DatabaseIndexs=(${DatabaseIndexs//,/ })

    debug_log "DatabaseIndexs: ${DatabaseIndexs[*]}"
    DatabaseNames=()
    for index in ${DatabaseIndexs[@]}
    do
        if [[ "$index" -gt "${#Databases[*]}" ]] || [[ "$index" -lt 0 ]]
        then
            error_log "Invalid index(${index})"
            return 1
        fi
        DatabaseNames[${#DatabaseNames[*]}]="${Databases[${index}]}"
    done
    debug_log "DatabaseNames: ${DatabaseNames[*]}"
}

function check_DatabaseNames(){
    local database_name

    debug_log 'DatabaseNames: ${DatabaseNames}'
    if [[ -z "${DatabaseNames}" ]]
    then
        error_log "Invalid parameter 'DatabaseNames'."
        return 1
    fi
    DatabaseNames=(${DatabaseNames//,/ })
    for database_name in ${DatabaseNames[@]}
    do
        echo "${Databases[@]}" | grep -qP "${database_name}"
        if [[ $? -ne 0 ]]
        then
            error_log "Invalid database name(${database_name})"
            return 1
        fi
    done
}

function get_BackupDir(){
    get_param "BackupDir" "backup directory[/usr/sap/${SID}/HDB${InstanceNumber}/backup/data]"
}

function check_BackupDir(){
    local defalut_backup_dir="/usr/sap/${SID}/HDB${InstanceNumber}/backup/data"
    if [[ -z "${BackupDir}" ]]
    then
        info_log "The default backup directory is '${defalut_backup_dir}'"
        BackupDir="${defalut_backup_dir}"
    fi

    debug_log "BackupDir: ${BackupDir}"
}

function backup(){
    local database_name

    for database_name in ${DatabaseNames[@]}
    do
        info_log "Start to backup ${database_name}..."

        local backup_dir="${BackupDir}/${database_name}"
        local backup_prefix="${backup_dir}/${BACKUP_PREFIX}"
        mkdir -p "${backup_dir}"
        if [[ $? -ne 0 ]]
        then
            error_log "Failed to create backup directory(${backup_dir})."
            exit 1
        fi

        chown -R "${SIDAdm}:sapsys" "${backup_dir}"

        debug_log "command: hdbsql -t -u SYSTEM -p ****** -d ${database_name} \"backup data using file('${backup_prefix}')\""
        run_cmd "hdbsql -t -u SYSTEM -p ${MasterPass} -d ${database_name} \"backup data using file('${backup_prefix}')\"" "${SIDAdm}"
        if [[ $? -ne 0 ]]
        then
            error_log "Backup ${database_name} failed."
            exit 1
        fi

        info_log "${database_name} backup directory: ${backup_dir}"
    done

    info_log "Finished backup."
}

function run(){
    # 获取参数
    get_SID
    get_SIDAdm
    get_InstanceNumber
    get_MasterPass
    get_Databases
    get_DatabaseIndexs
    get_BackupDir
    # 执行备份
    backup
}
function silent_run(){
    # 校验参数
    check_SID || exit 1
    get_SIDAdm || exit 1
    check_InstanceNumber || exit 1
    check_MasterPass || exit 1
    get_Databases  || exit 1
    check_DatabaseNames || exit 1
    check_BackupDir || exit 1

    # 执行备份
    backup
}

######################################################################
# Init env
######################################################################
touch "${DEFAULT_LOG_FILE}"
$(ls "/tmp" | grep -q "${DEFAULT_LOG_FIFO##*/}") || mkfifo "${DEFAULT_LOG_FIFO}"
cat ${DEFAULT_LOG_FIFO} | tee -a ${LOG_FILE} &
exec 1>${DEFAULT_LOG_FIFO} 2>&1


######################################################################
# Init options
######################################################################
eval set -- `getopt -o hvD::us:: -l help,version,update,debug::,silent::,SID::,InstanceNumber::,MasterPass::,DatabaseNames::,BackupDir -n "$0" -- "$@"`
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
        -s| --silent)
            SILENT_MODE=true;
            shift 2;;
        --SID)
            SID="$2";
            shift 2;;
        --InstanceNumber)
            InstanceNumber="$2";
            shift 2;;
        --MasterPass)
            MasterPass="$2";
            shift 2;;
        --DatabaseNames)
            DatabaseNames="$2";
            shift 2;;
        --BackupDir)
            BackupDir="$2";
            shift 2;;
        -- ) shift; break ;;
        *) echo "Unknow parameter($1)"; exit 1 ;;
    esac
done


######################################################################
# Run
######################################################################
if ! "${SILENT_MODE}"
then
# 交互模式
    run
fi

if "${SILENT_MODE}"
then
# 静默模式
    silent_run
fi

