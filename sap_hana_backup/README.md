
English | [简体中文](README-CN.md)

<h1 align="center">sap-hana-backup</h1>

## Purpose

SAP HANA backup tool is used to automatically backup system and tenant databases.

## Quick start
Alibaba Cloud provides two methods to use this tool.The first one is through the Operation Orchestration Service (OOS)and the second one is manual execution.The Operation Orchestration Service(OOS) is a way to provide templates for users to automatically run this tool. Manual execution requires downloading the tool to the ECS server, and then manually executing the script.

### Operation Orchestration Service (OOS)

Coming soon...

### Manual execution

#### 1. Download tool

Download tool to ECS,or download via RDP server and upload to ECS server. Download link:
[SAP HANA backup tool](https://raw.githubusercontent.com/aliyun/alibabacloud-quickstart-sap-utilities/master/sap_hana_backup/hana_backup.sh)

#### 2. Run tool

Please use root user to excute below commands.

```shell
# 1.Change authorization
chmod +x hana_backup.sh
# 2.View help
./hana_backup.sh -h
# 3.View version
./hana_backup.sh -v
# 4.Perform backup
./hana_backup.sh
```

##### Debug mode

```shell
# Debug mode can display command execution results,it can help users debug and diagnose problems.
./hana_backup.sh --debug
```

##### Silent mode

```shell
./hana_backup.sh -s --SID=<SID> --InstanceNumber=<instance number> --MasterPass='<master password>' --DatabaseNames='<database name>' --BackupDir='<target backup file directory>'
```

Required parameters
+ SID: SAP HANA system ID
+ InstanceNumber: SAP HANA instance number
+ MasterPass: SAP HANA master password
+ DatabaseNames: SAP HANA database name，multiple databases are separated by',' such as:'SYSTEMDB,HDB'.

Optional parameters

+ BackupDir: Target backup file directory，default directory：'/usr/sap/\<SID>/HDB\<InstanceNumber>/backup/data'.

  

