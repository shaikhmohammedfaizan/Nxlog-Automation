# NxLog-Automation
Automated NXLog deployment and Windows log forwarding solution using PowerShell, LGPO, and custom configuration templates. Designed for centralized log collection and enterprise-scale Windows server integration.


# NXLog Automated Deployment & Log Forwarding Framework

## 📌 Overview

This project provides an automated deployment framework for installing and configuring NXLog on Windows systems.  
It includes PowerShell automation scripts, silent installation configurations, LGPO policy deployment, and prebuilt log collection templates for multiple services.

The goal of this project is to standardize and automate Windows log forwarding to a centralized SIEM or log management platform.

---

## 🚀 Features

- Automated NXLog installation (MSI & EXE based)
- Silent deployment using .iss configuration files
- Pre-configured nxlog.conf
- Modular service-specific log configurations
- Local Group Policy (LGPO) automation
- Policy-based configuration using CSV
- Compiled PowerShell executables for production deployment
- Ready-to-use output installer packages

---

## 📂 Project Structure

├── main.ps1
├── nxlog.conf
├── nxlog.d/
│ ├── apache.conf
│ ├── dhcp.conf
│ ├── dns.conf
│ ├── exchange.conf
│ ├── iis.conf
│ ├── mssql.conf
│ ├── oracle.conf
│ ├── ps.conf
├── nxlog-setup.iss
├── nxlog.msi
├── LGPO.exe
├── policy.csv
├── Output/
│ ├── NXLogSetup.exe

---

## 🛠 Technologies Used

- PowerShell
- NXLog
- LGPO (Local Group Policy Object utility)
- Windows Server
- Silent Installer (.iss automation)

---

## ⚙️ How It Works

1. Installs NXLog silently using MSI or EXE installer.
2. Applies predefined NXLog configuration.
3. Deploys modular log collection configs based on server role.
4. Applies Windows audit policies using LGPO.
5. Ensures log forwarding to centralized log collector.

---

## 📌 Supported Log Sources

- IIS
- DNS
- DHCP
- MSSQL
- Oracle
- Exchange
- Apache
- PowerShell logs
- Windows Event Logs

---

Use Case

Enterprise log onboarding

SIEM integration

Centralized log management

Windows server compliance monitoring

SOC environments

⚠️ Disclaimer

This project is intended for internal enterprise deployment and controlled environments.
Always test in a staging environment before production rollout.

👨‍💻 Author

Shaikh Mohammed Faizan
MSc IT (IMS & Cybersecurity)
Interested in Cybersecurity & SIEM Engineering
