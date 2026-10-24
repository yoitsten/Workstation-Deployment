# WORKSTATION DEPLOYMENT SCRIPT



## PROJECT OVERVIEW

This script automates workstation deployment in the following areas:

* Manual IP, Gateway, DNS, Prefix Length, and Hostname configuration
* Active Directory membership assignment

It was designed for a Windows 11 Enterprise VM environment with a dedicated Active Directory server meant to simulate authentic Help Desk troubleshooting scenarios. The script assumes that the workstation in question is freshly installed without any pre-existing network configurations.

The intent behind this project was for the author (with the help of ChatGPT) to learn the basics of PowerShell scripting and syntax with a dual purpose of automating a 5 minute workflow used to set up/add new workstations to their existing Active Directory environment.



## FEATURES

The functionalities of this script include:

* Verification of a workstation's current network configuration and hostname
* Validation of the desired network configuration
* Pre-flight safety checks to reject unsupported configurations and reduce the risk of unintended network changes
* Dedicated log generation upon success / failure of the script's execution
* Application of the desired network configuration / hostname as described in the hash table at the beginning of the script
* Connecting a new workstation to Active Directory



## LAB ENVIRONMENT

The infrastructure built includes a headless Domain Controller based on Windows Server 2025 with Active Directory Domain Services and a DNS forwarder. This server hosts Active-Directory integrated DNS as to prevent internal lookups on the public facing internet while the DNS forwarder functionality enables external lookups. As this is a headless server, an Administrator workstation has also been configured as a quality-of-life feature to enable Active Directory management via GUI. The environment also features a single additional workstation that has been successfully configured using this script. Further workstation deployments are pending.



## PRE-REQUISITES AND CONFIGURATION

The pre-requisites needed for the script to run are:

* PowerShell v5.1.26100.9444 with an elevated terminal (Testing has not been attempted with other versions of PowerShell)
* A supported Windows workstation with the required networking cmdlets
* Administrator privileges
* Network access to the configured Active Directory environment
* Appropriate domain credentials for joining or renaming computers
* Correct configuration values, including the interface alias, IP, gateway, DNS, and domain



In addition, the desired configuration can be easily modified by opening the script via Notepad and modifying the hash table as needed. The hash table format has been pasted below and can be found at the very top of the script when viewing it's contents.



$Config = @{

&#x09;ComputerName = "LI-PC02"

&#x09;DomainName = "leeindustries.test"

&#x09;IPAddress = "10.77.10.102"

&#x09;PrefixLength = 24

&#x09;Gateway = "10.77.10.1"

&#x09;DnsServer = "10.77.10.10"

&#x09;InterfaceAlias = "Ethernet"

}



NOTE: This script is intended for fresh workstation provisioning and supported reruns.



## HOW IT WORKS

This script follows a relatively straightforward workflow:

* Pre-Flight Safety Checks

  * Verifies that the current PowerShell session has administrator privileges
  * Designates and automatically generates the default logging path
  * Validates the desired configuration specified in the starting hash table
  * Inspects the workstation's existing configuration and checks whether the proposed changes are supported by the script's safety policies
* IP Configuration

  * Applies the desired IP configuration specified in the starting hash table if the pre-flight safety checks allow for it
  * Verifies the application of the desired IP configuration
* Gateway Configuration

  * Identifies the current gateway configuration of the workstation
  * Applies desired gateway configuration if allowed
  * Verifies the application of the desired gateway configuration
* DNS Server Assignment

  * Identifies the current DNS configuration of the workstation
  * Applies desired DNS Server assignment if allowed
  * Verifies the application of the DNS Server assignment
  * Tests the connection to the designated DNS server via port 53 (TCP)
  * Queries the designated DNS server for further verification of the DNS assignment
  * Queries Active Directory DNS records to verify domain-controller discovery
* Joining Active Directory

  * Prompts the administrator for valid credentials to the Active Directory
  * Determines if the current workstation is already domain-joined
  * Determines if the current workstation's hostname requires modification
  * Joins the workstation to the desired domain and changes the hostname if needed
  * Verifies connectivity via the Active Directory Secure Channel
* Prompts user to restart the workstation if any changes made require a restart to take effect
* Generates logs for the deployment session



## TESTING AND RESULTS

All testing was done on a Virtual Machine of a Windows 11 Enterprise workstation. Fresh deployment was successful with the exception of testing DNS connectivity, which required the addition of a "for" block that allowed for three attempts at testing connectivity with a 3 second pause between attempts. This allowed the workstation to "settle" into the configuration changes and ensured proper testing of the DNS connectivity.



Error handling was validated via deliberate misconfiguration of the defined hash table values and intentionally incurring a terminating PowerShell error. All error testing returned as expected and log transcripts captured both successful and failed executions.



The script's idempotency was confirmed with subsequent reruns of the script on the same workstation which resulted in the exact same desired configuration after each run.



## LIMITATIONS

Version 1 does not support the following:

* IPv6 addresses
* Automatically migrating workstations from an existing, different Active Directory domain
* Reconfiguring workstations with manual IP configurations
* Prefix Lengths greater than 30
* Reconfiguring workstations with multiple gateways
* Automatic rollback in the event that the script fails after some configuration changes have been made. Failures after configuration changes may leave the workstation partially provisioned

