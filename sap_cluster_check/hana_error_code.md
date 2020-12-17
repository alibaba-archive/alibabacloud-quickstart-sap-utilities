## HANA HA Cluster Check Tool's Error Code

| Task ID             | Error Code                 | Error Message                                                | Solutions                                                    |
| ------------------- | -------------------------- | ------------------------------------------------------------ | ------------------------------------------------------------ |
| CheckOSVersion      | NotSupportedOS             | Not supported (< operating system >).                        | This OS version（ < OS >  < OS Version >）is not supported to check HANA HA cluster. |
| CheckOSVersion      | NotForSAP                  | OS is not SUSE for sap version.                              | The version for sap of OS is recommended.                    |
| CheckUpdateEtcHosts | NotClosedUpdateEtcHosts    | The 'update_etc_hosts' module is turned on, it is recommended to set ' - update_etc_hosts' to '# - update_etc_hosts' in the '/etc/cloud/cloud.cfg' file. | It is recommended to set ' - update_etc_hosts' to '# - update_etc_hosts' in the '/etc/cloud/cloud.cfg' file. |
| CheckNtpService     | NotRunning.chronyd         | chronyd.service(NTP daemon) status is abnormal,please check the serivce with command 'systemctl status chronyd.service'. |                                                              |
| CheckNtpService     | NotRunning.ntpd            | ntpd status(NTP daemon) is abnormal,please check the serivce with command 'systemctl status ntpd'. |                                                              |
| CheckNtpService     | NotSupported.System        | This OS version（ < OS >  < OS Version >）is not supported to check NTP service. |                                                              |
| CheckClockSource    | UnavailableClockSource.tsc | There is no 'tsc' clocksource in available clocksources      |                                                              |
| CheckClockSource    | NotCurrentClockSource.tsc  | Current system clocksource is ${RES}, not set to 'tsc',it is recommended to set to 'tsc'. |                                                              |