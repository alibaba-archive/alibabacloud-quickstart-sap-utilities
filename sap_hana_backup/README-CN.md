[English](README.md) | 简体中文

<h1 align="center">SAP HANA备份工具</h1>

## 用途

SAP HANA 备份工具用于自动化备份HANA数据库。

## 快速开始

阿里云提供了通过运维编排服务(OOS)和手动执行的两种运行方式来使用此工具。运维编排服务(OOS)是提供模版的方式让用户输入相关参数后自动运行工具。手动执行需要下载工具到ECS服务器，然后手工执行脚本。

### 运维编排服务

建设中...

### 手动执行

#### 1.下载工具

下载工具到ECS服务器，或通过跳板机下载然后上传到ECS服务器。下载地址：

[SAP HANA备份工具](https://raw.githubusercontent.com/aliyun/alibabacloud-quickstart-sap-utilities/master/sap_hana_backup/hana_backup.sh)

#### 2. 运行工具

```shell
# 添加执行权限
chmod +x hana_backup.sh
# 查看帮助
./hana_backup.sh -h
# 查看版本
./hana_backup.sh -v
# 执行备份
./hana_backup.sh
```

##### Debug模式

```shell
# Debug模式可以显示检查命令及命令执行结果，方便调试和问题诊断
./hana_backup.sh --debug
```

##### 静默模式

```shell
./hana_backup.sh -s --SID=<SID> --InstanceNumber=<实例编号> --MasterPass='<Master密码>' --DatabaseNames='<备份数据库名>' --BackupDir='<备份文件目录>'
```

必需参数

+ SID: SAP HANA 数据库系统ID
+ InstanceNumber: SAP HANA 数据库实例编号
+ MasterPass: SAP HANA 数据库master密码
+ DatabaseNames: SAP HANA 数据库名，多个数据库使用','分隔，如：'SYSTEMDB,HDB'

可选参数：

+ BackupDir: 备份文件目录，默认备份目录：'/usr/sap/\<SID>/HDB\<InstanceNumber>/backup/data'

