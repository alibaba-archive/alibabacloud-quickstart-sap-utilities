English | [简体中文](README-CN.md)

<h1 align="center">SAP cluster check tool</h1>

## Purpose

The SAP cluster check tool is a tool script based on the best practices of deploying SAP systems on Alibaba Cloud. It mainly focus on cluster configurations such as: operating system version, corosync configuration, HSR Status, pacemaker status, crm resource configuration, etc.
+ Supported OS：SUSE Linux Enterprise Server for SAP 12 and higher
+ Supported SAP system：SAP NetWeaver as ABAP cluster and SAP HANA cluster
+ Supported STONITH：SBD and Fence agent(coming soon)



## Directory Structure

```yaml
├── hana_cluster_check.sh           # SAP HANA HA check script
├── hana_error_code.md              # SAP HANA HA error code reference document
├── netweaver_cluster_check.sh      # SAP NetWeaver HA check script(coming soon)
├── netweaver_error_code.md         # SAP NetWeaver HA error code reference document(coming soon)
```



## Quick start

Alibaba Cloud provides two methods to use this tool.The first one is through the Operation Orchestration Service (OOS)and the second one is manual execution. The Operation Orchestration Service(OOS) is a way to provide templates for users to automatically run this tool. Manual execution requires downloading the tool to the ECS server, and then manually executing the script.

### Operation Orchestration Service (OOS)

Coming soon...

### Manual execution

#### 1. Download tool

Download tool to ECS,or download via RDP server and upload to ECS server. Download link:

1. [hana-cluster-check](https://sh-test-hangzhou.oss-cn-hangzhou.aliyuncs.com/saptool/sap-ha-cluster-check.tar)

#### 2. Run tool

Please use root user to excute below commands. 

```shell
# 1.Unzip tool
tar -xvf sap-ha-cluster-check.tar
# 2.Go to directory
cd sap-ha-cluster-check/hana-ha
# 3.View help
./hana_cluster_check.sh -h
# 4.Execute script
./hana_cluster_check.sh
```

Debug mode

```shell
#Debug mode can display command execution results,it can help users debug and diagnose problems. 
./hana_cluster_check.sh --debug
```

#### 3.View Results

After execution it will create the following three files automatically on current directory：

```yaml
├── check_tool.log          # Log file:excution detail
├── report.txt              # Report summary:tool execution results
├── params.cfg              # Parameter file:the parameter record
```

For warnings and errors in report summary, please refer to the [HANA HA Cluster Check Tool's Error Code](hana_error_code.md) reference document.



