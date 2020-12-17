[English](README.md) | 简体中文

<h1 align="center">SAP高可用集群检查工具</h1>

## 用途

SAP高可用集群检查工具是基于阿里云上部署SAP系统最佳实践的工具脚本，主要针对在阿里云上部署SAP高可用集群的常见问题和配置的检查，如：操作系统版本、corosync配置、HSR状态、pacemaker状态、crm resource配置等。
+ 支持的操作系统：SUSE Linux Enterprise Server for SAP 12及以上
+ 支持的SAP系统类型：SAP NetWeaver as ABAP高可用集群、SAP HANA高可用集群
+ 支持的STONITH：SBD、Fence agent(建设中)



## 目录结构

```yaml
├── hana_cluster_check.sh           # SAP HANA HA检查脚本
├── hana_error_code.md              # SAP HANA HA错误码文档
├── netweaver_cluster_check.sh      # SAP NetWeaver HA检查脚本(建设中)
├── netweaver_error_code.md         # SAP NetWeaver HA错误码文档(建设中)
```



## 快速开始

阿里云提供了通过运维编排服务(OOS)和手动执行的两种运行方式来使用此工具。运维编排服务(OOS)是提供模版的方式让用户输入相关参数后自动运行工具。手动执行需要下载工具到ECS服务器，然后手工执行脚本。

### 运维编排（OOS）服务

建设中...

### 手动执行

#### 1. 下载工具

下载工具到ECS服务器，或通过跳板机下载然后上传到ECS服务器。下载地址：

1. [hana-cluster-check](https://sh-test-hangzhou.oss-cn-hangzhou.aliyuncs.com/saptool/sap-ha-cluster-check.tar)


#### 2. 运行工具

```shell
# 1.解压工具
tar -xvf sap-ha-cluster-check.tar
# 2.进入解压目录
cd sap-ha-cluster-check/hana-ha
# 3.查看帮助
./hana_cluster_check.sh -h
# 4.执行脚本
./hana_cluster_check.sh
```

Debug模式

```shell
# Debug模式可以显示检查命令及命令执行结果，方便用户调试和问题诊断
./hana_cluster_check.sh --debug
```

#### 3.查看结果

执行结束后会在当前目录自动创建如下三个文件：

```yaml
├── check_tool.log          # 日志文件：工具执行过程日志
├── report.txt              # 检查报告：工具执行结果总结
├── params.cfg              # 参数文件：用户在执行过程中输入的参数记录
```

关于检查报告中的警告和错误，请参考 [HANA HA 检查工具错误码](hana_error_code.md) 文档排查修复。







​




