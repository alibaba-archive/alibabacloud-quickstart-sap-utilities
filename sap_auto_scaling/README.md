<h1 align="center">SAP AAS自动扩展服务</h1>

## 用途

SAP AAS(Additional application server)自动扩展服务，基于已有SAP系统的PAS(Primary application server)创建弹性伸缩组，自动或手动扩展ECS实例并部署AAS，并将AAS自动加入SAP Logon groups。


## 目录结构

```yaml
├── sap_auto_scaling.py                # SAP Logon groups更新脚本
├── sap_auto_scaling.sh                # SAP AAS部署脚本
├── ros_s4hana_auto_scaling.json       # SAP应用弹性伸缩ROS模板，用于部署云资源
├── oos_s4hana_auto_scaling.yml        # SAP应用弹性伸缩OOS模板，用于执行云资源部署、云资源配置
```

## 快速开始

### 准备工作

在开始部署前，默认您了解SAP 系统，且了解相关的阿里云服务，如：云服务器ECS、专有网络VPC、弹性伸缩ESS、资源编排ROS和运维编排OOS等。

同时满足如下条件：

+ 账户余额充足
+ 已经部署了SAP S/4HANA系统，并且ASCS和PAS部署于同一台云服务器
+ 部署SAP S/4HANA系统的云服务器，/sapmnt目录和/usr/sap/trans目录使用NAS服务共享

另外目前SAP应用伸缩仅支持AAS自动扩展，不支持AAS的自动缩减。

### 开始部署

1. 登录运维编排控制台，点击'参数仓库'，创建加密参数Logon_User_Password和PAS_Root_Password，分别对应Logon用户密码和PAS实例root用户密码。
2. 登录运维编排控制台，点击'公共模板'，选择'其他'，选择模板[SAP应用弹性伸缩部署模板]()，点击创建执行，执行模式选择自动执行，点击'下一步：设置参数'。
2. 录入参数，开始执行部署








