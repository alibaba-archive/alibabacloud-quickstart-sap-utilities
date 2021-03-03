#!/bin/bash
###################################################################################################
# sap_auto_scaling.sh
# The script use to auto scaling AAS instance. 
# Author: Alibaba Cloud, SAP Product & Solution Team
###################################################################################################
# Versions
VERSION='1.0'


######################################################################
# Global variable
######################################################################
DEFAULT_ROOT_DIR='/tmp/sap-auto-scaling'
DEFAULT_PACKAGE_DIR="${DEFAULT_ROOT_DIR}/package"
DEFAULT_LOG_FIFO='/tmp/sap_auto_scaling.fifo'
DEFAULT_LOG_FILE='sap_auto_scaling.log'

# DEFAULT_LOG_LEVEL: ERROR-0 WARNING-1 INFO-2 DEBUG-3
DEFAULT_LOG_LEVEL='2'

LOG_FILE="${DEFAULT_LOG_FILE}"
LOG_LEVEL="${DEFAULT_LOG_LEVEL}"

# Color
COLOR_GREEN='\033[32m'
COLOR_YELLOW='\033[33m'
COLOR_RED='\033[31m'
COLOR_END='\033[0m'

# System file path
ETC_FSTAB_PATH="/etc/fstab"

# Instance information
ECS_INSTANCE_ID=$(curl -s 'http://100.100.100.200/latest/meta-data/instance-id')
ECS_IPADRESS=$(curl -s 'http://100.100.100.200/latest/meta-data/private-ipv4')
ECS_REGION_ID=$(curl -s 'http://100.100.100.200/latest/meta-data/region-id')

if hostname | grep -qP "${ECS_INSTANCE_ID:2:-1}"
then
    ECS_INSTANCE_NUMBER="${RANDOM: -1}${RANDOM: -1}"
    hostname "APP${ECS_INSTANCE_NUMBER}"
    echo "APP${ECS_INSTANCE_NUMBER}" > /etc/hostname
else
    ECS_INSTANCE_NUMBER=$(hostname | grep -o '[0-9][0-9]$')
fi
ECS_HOSTNAME=$(hostname)


######################################################################
# Help function
######################################################################
function help(){
    cat <<EOF
version: ${VERSION}
help: $1 [options]
    -h, --help                  Show this help message and exit
    -v, --version               Show version
    -d, --debug                 Set log level to debug
    -s, --SID                   SAP AS ABAP system ID
    -i, --PASIP                 SAP AS ABAP PAS instance private IP address
    -p, --RootPassword          SAP AS ABAP PAS instance user('root') password
    -u, --Username              SAP AS ABAP PAS instance username
    -P, --UserPassword          SAP AS ABAP PAS instance user password
    -c, --ClientNumber          SAP AS ABAP PAS instance client number
    -C, --ClassName           SAP AS ABAP system group name
    -U, --UsrsapDiskName        '/usr/sap' file system disk name, e.g. 'vdb'
    -S, --SwapDiskName          '/swap' file system disk name, e.g. 'vdc'
For example: $0
EOF
    exit 0
}

function show_version(){
    echo "${VERSION}"
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
# Check Parameters functions
######################################################################
function check_param(){
    local value="$1"
    local value_re="$2"

    if [[ -z "${!value}" ]]
    then
        error_log "option '--${value}' is required"
        exit 1
    fi

    echo "${!value}" | grep -qP "${value_re}"
    if [[ $? -ne 0 ]]
    then
        error_log "${value}(${!value}) does not meet the policy requirements"
        exit 1
    fi
}

function check_UsrsapDiskName(){
    debug_log "UsrsapDiskName: ${UsrsapDiskName}"
    check_param UsrsapDiskName '^vd[b-z]$'
    if ! lsblk | grep -q "${UsrsapDiskName}"
    then
        error_log "Failed to check if the disk is mounted by disk name '${UsrsapDiskName}'"
        exit 1
    fi
}

function check_SwapDiskName(){
    debug_log "SwapDiskName: ${SwapDiskName}"
    check_param SwapDiskName '^vd[b-z]$'
    if ! lsblk | grep -q "${SwapDiskName}"
    then
        error_log "Failed to check if the disk is mounted by disk name '${SwapDiskName}'"
        exit 1
    fi
}

function check_PASIP(){
    debug_log "PASIP: ${PASIP}"
    check_param PASIP '^[0-9.]*$'
    if ! ping "${PASIP}" -c 1 1>/dev/null 2>&1
    then
        error_log "PAS instance IP address(${PASIP}) can not be pinged"
        exit 1
    fi
}

function check_RootPassword(){
    debug_log "RootPassword: ****"
    check_param RootPassword '^.{8,}$'
}

function check_UserPassword(){
    debug_log "UserPassword: ****"
    check_param UserPassword '^.{4,}$'
}

function check_ClientNumber(){
    debug_log "ClientNumber: ${ClientNumber}"
    check_param ClientNumber '^[0-9]{3}$'
}

function check_Username(){
    debug_log "Username: ${Username}"
    check_param Username '^.{1,}$'
}

function check_ClassName(){
    debug_log "ClassName: ${ClassName}"
    check_param ClassName '^.{1,}$'
}

function check_SID(){
    debug_log "SID: ${SID}"
    check_param SID '^([A-Z]{1}[0-9A-Z]{2})$'
}

function check_paramater(){
    info_log "Start to check parameters"
    check_UsrsapDiskName
    check_SwapDiskName
    check_PASIP
    check_RootPassword
    check_Username
    check_UserPassword
    check_ClientNumber
    check_SID
    check_ClassName
}


######################################################################
# Initialize enviroment functions
######################################################################
function check_repo(){
    zypper -qn remove unrar 2>/dev/null
    zypper -qn install unrar 2>/dev/null
}

function init_repo(){
    info_log "Start to check repository"
    check_repo
    if [[ $? -ne 0 ]]
    then
        SUSEConnect --cleanup
        $(systemctl list-units --all | grep -q guestregister.service) && systemctl start guestregister.service
        zypper ref
    else
        return 0
    fi

    check_repo
    if [[ $? -ne 0 ]]
    then
        error_log "zypper repo is unavailable"
        exit 1
    fi
}

function install_package(){
    for package in $@
    do 
        if ! rpm -q ${package}
        then
            info_log "Start to install ${package}."
            zypper --non-interactive --quiet --gpg-auto-import-keys install ${package} > /dev/null|| { error_log "${package} don't install,please check";exit 1; }
        fi
    done
}

function update_aliyun_assist(){
    $(ps -ef | grep -v grep| grep -q qemu-ga) && systemctl stop qemu-ga@virtio\\x2dports-org.qemu.guest_agent.0.service && systemctl disable qemu-ga@virtio\\x2dports-org.qemu.guest_agent.0.service
    rpm -ivh --force "https://aliyun-client-assist-${ECS_REGION_ID}.oss-${ECS_REGION_ID}-internal.aliyuncs.com/linux/aliyun_assist_latest.rpm"
}

function install_software(){
    local pip_="$(which pip3 2>/dev/null || which pip 2>/dev/null)"

    info_log "Start to check software"
    init_repo > /dev/null
    install_package lvm2 expect libltdl7 autofs python3-devel gcc-c++
    "${pip_}" install -q --upgrade pip
    "${pip_}" install -q cython wheel pytest sphinx
    "${pip_}" install -q "https://sh-test-hangzhou.oss-cn-hangzhou.aliyuncs.com/sap-utilities/sap-auto-scaling/pynwrfc-2.3.0-cp36-cp36m-linux_x86_64.whl"

}


######################################################################
# Configure SSH mutual trust functions
######################################################################
function generate_key(){
    info_log "Generate a pair of public key and private key"
    expect << EOF
        set timeout 10
        spawn ssh-keygen -t rsa
        expect {
                "*verwrite" {send "y\r";exp_continue}
                "*Enter*" {send "\r";exp_continue}
                "*SHA256" {send "\r"}
            }
    interact
EOF
}

function init_mutual_trust(){
    local ip="${PASIP}"
    local user="root"
    local password="${RootPassword}"

    if [[ -z "${HOME}" ]]
    then
        HOME='/root'
    fi

    if [[ ! -f "${HOME}/.ssh/id_rsa" ]] || [[ ! -f "${HOME}/.ssh/id_rsa.pub" ]]
    then
        generate_key
    fi

    local cmd=`cat <<EOF
    spawn ssh-copy-id -i ${HOME}/.ssh/id_rsa.pub ${user}@${ip}
    expect {
        "*yes/no" { send "yes\r";exp_continue}
        "*assword:" { send "${password}\r";exp_continue}
        "*were added" { send "\r"}
        "*already installed" { send "\r";exp_continue}
    }
    interact
EOF
`
    info_log "Start to configure mutual trust(${user}@${ip})"
    res=$(expect -c "$cmd")
    debug_log "${res}"
    check_host_mutual_trust "${PASIP}"
    if [[ $? -eq 0 ]]
    then
        error_log "${res}"
        error_log "Failed to configure SSH mutual trust."
        exit 1
    fi
}

function check_host_mutual_trust(){
    debug_log "Start to check mutual trust"
    local hostname="$1"
    local cmd=`cat <<EOF
    spawn ssh -o StrictHostKeyChecking=no root@${hostname} echo testPass
    expect {
        "*assword" {set timeout 1000; send "test\n"; exp_continue ; sleep 1; }
        "yes/no" {send "yes\n"; exp_continue;}
        "Disconnected" {send "\n"; }
        "testPass" {send "\n"; }
    }
    interact
EOF
`
    res=$(expect -c "$cmd")
    debug_log "${res}"
    echo "${res}" | grep -q "assword"
}

function run_cmd_remote(){
    RES="UNSET"
    RES_CODE="UNSET"

    local command="$1"
    debug_log "remote command: ${command}"
    RES=$(ssh "root@${PASIP}" "${command}")
    RES_CODE="$?"

    if [[ ${RES_CODE} -ne 0 ]]
    then
        error_log "${RES}"
    fi
    debug_log "command exit code: ${RES_CODE}"
    debug_log "command result: \n${RES}"
}


######################################################################
# Initialize global variable functions
######################################################################
function get_SIDAdm(){
    SIDAdm="$(echo ${SID} | tr '[:upper:]' '[:lower:]')adm"
    debug_log "SIDAdm: ${SIDAdm}"
}

function get_PASHostname(){
    run_cmd_remote "hostname"
    PASHostname="${RES}"
    debug_log "PASHostname: ${PASHostname}"
}

function get_PASName(){
    run_cmd_remote "ls /usr/sap/${SID}/ | grep -P '^[A-Z]\d\d$' | head -1"
    PASName="${RES}"
    debug_log "PASName: ${PASName}"
}

function get_PASInstanceNumber(){
    PASInstanceNumber=$(echo "${PASName}" | tr -cd "[0-9]")
    debug_log "PASInstanceNumber: ${PASInstanceNumber}"
}

function get_AASInstanceNumber(){
    AASInstanceNumber="${ECS_INSTANCE_NUMBER}"
    debug_log "AASInstanceNumber: ${AASInstanceNumber}"
}

function get_AASName(){
    AASName="D${AASInstanceNumber}"
    debug_log "AASName: ${AASName}"
}

function get_AASHostname(){
    AASHostname="${ECS_HOSTNAME}"
    debug_log "AASHostname: ${AASHostname}"
}

function init_global_var(){
    get_SIDAdm
    get_PASHostname
    get_PASName
    get_PASInstanceNumber
    get_AASInstanceNumber
    get_AASName
    get_AASHostname
}


######################################################################
# Configure system file
######################################################################
function config_hosts(){
    # Copy '/etc/hosts' file
    info_log "Start to configure '/etc/hosts' file"
    scp -pr "root@${PASIP}:/etc/hosts" "/etc/hosts" > /dev/null
    if [[ $? -ne 0 ]]
    then
        error_log "Failed to copy '/etc/hosts' file form PAS instance."
        exit 1
    fi

    local item=$(grep -P "${PASIP}.*${PASHostname}" /etc/hosts | tail -1)
    item="${item//$PASIP/$ECS_IPADRESS}"
    item="${item//$PASHostname/$ECS_HOSTNAME}"

    debug_log "Add '${item}' to '/etc/hosts' file"
    echo "${item}" >> /etc/hosts

    run_cmd_remote "echo ${item} >> /etc/hosts"
}


######################################################################
# Sync group and user functions
######################################################################
function sync_group(){
    local cmd="grep sapsys /etc/group | awk -F ':' '{print \$3}'"
    run_cmd_remote "${cmd}"
    if [[ ${RES_CODE} -ne 0 ]] || [[ -z "${RES}" ]]
    then
        error_log "Filed to get GID of group 'sapsys'."
        exit 1
    fi
    local sapsys_gid=${RES}

    groupadd -g "${sapsys_gid}" sapsys
    if [[ $? -ne 0 ]]
    then
        error_log "Failed to add user group 'sapsys'(gid=${sapsys_gid})"
        exit 1
    fi
    info_log "Added user group 'sapsys'(gid=${sapsys_gid})."
}

function sync_user(){
    local sidadm="${SIDAdm}"
    local cmd="id ${sidadm} -u"
    run_cmd_remote "${cmd}"
    if [[ ${RES_CODE} -ne 0 ]] || [[ -z "${RES}" ]]
    then
        error_log "Filed to get UID of user '${sidadm}'."
        exit 1
    fi

    local uid=${RES}
    useradd -g sapsys -u "${uid}" "${sidadm}"
    if [[ $? -ne 0 ]]
    then
        error_log "Failed to add user '${sidadm}'(uid=${uid})."
        exit 1
    fi
    info_log "Added user '${sidadm}'(uid=${uid})."
}


######################################################################
# File system functions
######################################################################
function mk_swap(){
    local disk_name="/dev/${SwapDiskName}"

    info_log "Start to create SWAP file system(${disk_name})."
    debug_log "Disk name is '${disk_name}'"
    mkswap "${disk_name}" && swapon "${disk_name}"

    if [[ $? -ne 0 ]]
    then
        warning_log "Failed to create SWAP."
        return 1
    fi

    $(grep -q ${disk_name} ${ETC_FSTAB_PATH}) || echo "${disk_name}        swap    swap    defaults        0 0" >> "${ETC_FSTAB_PATH}"
}

function mk_disk(){
    local disk_name="/dev/${UsrsapDiskName}"
    info_log "Start to create file system 'sapvg-usrsaplv' and mount on '/usr/sap'."
    debug_log "Disk name is '${disk_name}'"

    pvcreate "${disk_name}"
    vgcreate sapvg "${disk_name}"
    lvcreate -l 100%free -n usrsaplv sapvg

    if [[ $? -ne 0 ]]
    then
        error_log "Failed to create 'usrsaplv'."
        exit 1
    fi

    mkfs.xfs -f /dev/sapvg/usrsaplv
    mkdir -p /usr/sap
    $(grep -q /dev/sapvg/usrsaplv ${ETC_FSTAB_PATH}) || echo "/dev/sapvg/usrsaplv        /usr/sap  xfs defaults       0 0" >> "${ETC_FSTAB_PATH}"
    mount -a

    if ! df -h | grep -q sapvg-usrsaplv
    then
        error_log "Failed to create file system."
        exit 1
    fi
}

function mk_nas(){
    info_log "Start to configure NAS"
    local cmd="df -h | grep -P /sapmnt | awk '{print \$1}'"
    run_cmd_remote "${cmd}"
    local target_address=${RES}

    if [[ -z "${target_address}" ]]
    then
        error_log "Failed to query target address of '/sapmnt' mount in node ${PASHostname}."
        exit 1
    fi

    echo "${target_address} /sapmnt nfs vers=4,minorversion=0,rsize=1048576,wsize=1048576,hard,timeo=600,retrans=2,_netdev,noresvport 0 0" >> "${ETC_FSTAB_PATH}"

    mkdir -p '/sapmnt'
    mount -a

    if ! df -h | grep -q '/sapmnt'
    then
        error_log "Failed to mount '/sapmnt'."
        exit 1
    fi
}


######################################################################
# Install AAS instance functions
######################################################################
function install_aas(){
    info_log "Start to install AAS instance."
    local sid="${SID}"
    local root_dir="/usr/sap/${sid}"
    local profile_dir="/sapmnt/${sid}/profile"
    local aas_name="${AASName}"
    local pas_name="${PASName}"
    local pas_hostname="${PASHostname}"
    local aas_hostname="${AASHostname}"
    local pas_ip="${PASIP}"
    local pas_instance_number="${PASInstanceNumber}"
    local aas_instance_number="${AASInstanceNumber}"
    local pas_profile_name="${sid}_${pas_name}_${pas_hostname}"
    local aas_profile_name="${sid}_${aas_name}_${aas_hostname}"

    local aas_profile_path="${profile_dir}/${aas_profile_name}"

    local sidadm="${SIDAdm}"
    cmd="rm -rf ${DEFAULT_PACKAGE_DIR} && mkdir -p ${DEFAULT_PACKAGE_DIR}"
    run_cmd_remote "${cmd}"

    # Copy '<sid>adm' user home directory
    info_log "Start to sync '/home/${sidadm}' directory"
    cmd="tar -cPf ${DEFAULT_PACKAGE_DIR}/home_${sidadm}.tar /home/${sidadm}"
    run_cmd_remote "${cmd}"
    scp -pr "root@${pas_ip}:${DEFAULT_PACKAGE_DIR}/home_${sidadm}.tar" "${DEFAULT_PACKAGE_DIR}/" > /dev/null
    tar -xPf "${DEFAULT_PACKAGE_DIR}/home_${sidadm}.tar" -C /
    if [[ $? -ne 0 ]]
    then
        error_log "Failed to copy '/home/${sidadm}' directory form PAS instance."
        exit 1
    fi
    for file in $(ls "/home/${sidadm}");do rename "${pas_hostname}" "${aas_hostname}" "${file}";done
    mv "/home/${sidadm}/.hdb/${pas_hostname}" "/home/${sidadm}/.hdb/${aas_hostname}"

    # Copy '/sap/usr/<SID>/SYS'
    info_log "Start to sync '/usr/sap/${sid}/SYS' directory"
    cmd="tar -cPf ${DEFAULT_PACKAGE_DIR}/SYS.tar /usr/sap/${sid}/SYS"
    run_cmd_remote "${cmd}"
    scp -pr "root@${pas_ip}:${DEFAULT_PACKAGE_DIR}/SYS.tar" "${DEFAULT_PACKAGE_DIR}/" > /dev/null
    tar -xPf "${DEFAULT_PACKAGE_DIR}/SYS.tar" -C /
    if [[ $? -ne 0 ]]
    then
        error_log "Failed to copy '/usr/sap/${sid}/SYS' directory form PAS instance."
        exit 1
    fi

    # Copy 'sapservices' file
    info_log "Start to sync '/usr/sap/sapservices' file"
    scp -pr "root@${pas_ip}:/usr/sap/sapservices" /usr/sap/
    if [[ $? -ne 0 ]]
    then
        error_log "Failed to copy '/usr/sap/sapservices' file form PAS instance."
        exit 1
    fi
    service_item="LD_LIBRARY_PATH=${root_dir}/${aas_name}/exe:\$LD_LIBRARY_PATH; export LD_LIBRARY_PATH; ${root_dir}/${aas_name}/exe/sapstartsrv pf=${root_dir}/SYS/profile/${aas_profile_name} -D -u ${sidadm}"
    grep -q "${service_item}" /usr/sap/sapservices || echo "${service_item}" >> /usr/sap/sapservices

    # Copy directory '/sap/usr/<SID>/<PAS>'
    info_log "Start to sync '/usr/sap/${sid}/SYS' directory"
    mkdir -p "${root_dir}/${aas_name}"
    scp -pr "root@${pas_ip}:${root_dir}/${pas_name}/*" "${root_dir}/${aas_name}/" > /dev/null
    if [[ $? -ne 0 ]]
    then
        error_log "Failed to copy '${root_dir}/${pas_name}/*' file form PAS instance."
        exit 1
    fi
    rm -rf "${root_dir}/${aas_name}/work/"*
    rm -rf "${root_dir}/${aas_name}/data/"*
    chown  -R "${sidadm}:sapsys" "${root_dir}/${aas_name}/"

    # Copy 'hanaclient' directory
    info_log "Start to sync '/usr/sap/${sid}/hdbclient' directory"
    scp -pr "root@${pas_ip}:/usr/sap/${sid}/hdbclient" "/usr/sap/${sid}/"
    if [[ $? -ne 0 ]]
    then
        error_log "Failed to install 'hanaclient' directory."
        exit 1
    fi
    chown  -R "${sidadm}:sapsys" "/usr/sap/${sid}/hdbclient"

    # Copy file '/sapmnt/${SID}/profile/<PAS Profile>'
    info_log "Start to sync '${aas_profile_path}' file"
    cp "${profile_dir}/${pas_profile_name}" "${aas_profile_path}"
    chown  -R "${sidadm}:sapsys" "${aas_profile_path}"

    sed -i "s/SAPSYSTEM = ${pas_instance_number}/SAPSYSTEM = ${aas_instance_number}/g" "${aas_profile_path}"
    sed -i "s/INSTANCE_NAME = ${pas_name}/INSTANCE_NAME = ${aas_name}/g" "${aas_profile_path}"
    sed -i "s/${pas_profile_name}/${aas_profile_name}/g" "${aas_profile_path}"
    echo "rdisp/vbname = ${aas_hostname}_${sid}_${aas_instance_number}" >> "${aas_profile_path}"

    # Start 'sapstartsrv' process
    info_log "Start to run 'sapstartsrv' process"
    su - "${sidadm}" -c "sapstartsrv pf=${aas_profile_path} -D"
    if [[ $? -ne 0 ]]
    then
        error_log "Failed to start 'sapstartsrv' process."
        exit 1
    fi

    # Start AAS
    info_log "Start to run AAS instance"
    su - "${sidadm}" -c "sapcontrol -nr ${aas_instance_number} -function StartService ${sid}"
    if [[ $? -ne 0 ]]
    then
        error_log "Failed to run 'StartService' function."
        exit 1
    fi
    su - "${sidadm}" -c "sapcontrol -nr ${aas_instance_number} -function Start"

    if [[ $? -eq 0 ]]
    then
        return
    fi

    # Try again
    sleep 2m
    su - "${sidadm}" -c "cleanipc all remove" > /dev/null
    su - "${sidadm}" -c "sapcontrol -nr ${aas_instance_number} -function Start"
    if [[ $? -ne 0 ]]
    then
        error_log "Failed to start AAS instance."
        exit 1
    fi
}


######################################################################
# Install SAP NW RFC SDK functions
######################################################################
function install_rfc(){
    info_log "Start to install RFC SDK"
    local url="https://sh-test-hangzhou.oss-cn-hangzhou.aliyuncs.com/sap-utilities/sap-auto-scaling/nwrfc750P_6-70002752.zip"
    wget -q -nv "${url}" -P "${DEFAULT_PACKAGE_DIR}/" -t 2 -c
    if [[ $? -ne 0 ]]
    then
        error_log "Failed to download SAP NW RFC SDK."
        exit 1
    fi
    unzip -q "${DEFAULT_PACKAGE_DIR}/nwrfc*.zip" -d "/usr/sap/"

    mkdir -p "/etc/ld.so.conf.d/"
    echo "/usr/sap/nwrfcsdk/lib" > /etc/ld.so.conf.d/nwrfcsdk.conf
    export SAPNWRFC_HOME=/usr/sap/nwrfcsdk
    grep -q "export SAPNWRFC_HOME=/usr/sap/nwrfcsdk" /etc/profile || echo "export SAPNWRFC_HOME=/usr/sap/nwrfcsdk" >> /etc/profile

    ldconfig
    if [[ $? -ne 0 ]]
    then
        error_log "Failed to update dynamic link library."
        exit 1
    fi
}

function update_group(){
    info_log "Start to update 'Logon' or 'SPACE' group"
    local python_="$(which python3 2>/dev/null || which python 2>/dev/null)"
    local url='https://sh-test-hangzhou.oss-cn-hangzhou.aliyuncs.com/sap-utilities/sap-auto-scaling/sap_auto_scaling.py'

    wget -q -nv "${url}" -P "${DEFAULT_ROOT_DIR}/" -t 2 -c 
    if [[ $? -ne 0 ]]
    then
        error_log "Failed to download 'sap_auto_scaling.py' file."
        exit 1
    fi

    "${python_}" "${DEFAULT_ROOT_DIR}/sap_auto_scaling.py" --hostname "${PASIP}" --username "${Username}" --password "${UserPassword}" --number "${PASInstanceNumber}" --applserver "${AASHostname}_${SID}_${AASInstanceNumber}" --client "${ClientNumber}" --classname "${ClassName}"
    if [[ $? -ne 0 ]]
    then
        error_log "Failed to add AAS instance to '${ClassName}' group."
        exit 1
    fi
}


######################################################################
# Scaling functions
######################################################################
function run(){
    # 1. Sync '/etc/hosts' File
    config_hosts
    # 2. Sync Group And User
    sync_group
    sync_user

    # 3. Create File System
    mk_swap
    mk_disk
    mk_nas

    # 4. Install AAS
    install_aas

    # 5. Add Group
    install_rfc
    update_group
    info_log "Finished scale"
}

######################################################################
# Init env
######################################################################
export LANG=en_US.UTF-8
export LANGUAGE=en_US:

# update_aliyun_assist
mkdir -p "${DEFAULT_PACKAGE_DIR}"
touch "${DEFAULT_LOG_FILE}"
$(ls "/tmp" | grep -q "${DEFAULT_LOG_FIFO##*/}") || mkfifo "${DEFAULT_LOG_FIFO}"
cat ${DEFAULT_LOG_FIFO} | tee -a ${LOG_FILE} &
exec 1>${DEFAULT_LOG_FIFO} 2>&1


######################################################################
# Init options
######################################################################
opt=$(getopt -n sap_auto_scaling -o hvdU:S:s:i:p:u:P:c:a: -l help,version,debug,UsrsapDiskName:,SwapDiskName:,SID:,PASIP:,RootPassword:,Username:,UserPassword:,ClientNumber:,ClassName:, -n "$0" -- "$@")
[[ $? -ne 0 ]] && exit 1
eval set -- "${opt}"
while true
do
    case "$1" in
        -h| --help)
            help;;
        -v| --version)
            show_version;;
        -d| --debug)
            LOG_LEVEL="3";
            shift 1;;
        -U| --UsrsapDiskName)
            UsrsapDiskName="$2";
            shift 2;;
        -S| --SwapDiskName)
            SwapDiskName="$2";
            shift 2;;
        -s| --SID)
            SID="$2";
            shift 2;;
        -i| --PASIP)
            PASIP="$2";
            shift 2;;
        -p| --RootPassword)
            RootPassword="$2";
            shift 2;;
        -u| --Username)
            Username="$2";
            shift 2;;
        -P| --UserPassword)
            UserPassword="$2";
            shift 2;;
        -c| --ClientNumber)
            ClientNumber="$2";
            shift 2;;
        -C| --ClassName)
            ClassName="$2";
            shift 2;;
        -- ) shift; break ;;
        *) echo "Unknow parameter($1)"; exit 1 ;;
    esac
done


######################################################################
# Run
######################################################################
check_paramater
install_software
init_mutual_trust
init_global_var
run