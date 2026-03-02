# OrbitPay POV Provisioner

This repository contains a **self-service Terraform template** designed to provision isolated **OrbitPay POV environments** on demand.

It creates a fully functional PagerDuty configuration for the OrbitPay simulated enterprise, including Teams, Services, Dependencies, and Event Orchestration.

## ✨ Features

* **Zero Config:** Just bring your API Token. Schedules and Users are auto-configured.
* **Region Support:** Works seamlessly with **US**, **EU**, and **Staging** PagerDuty service regions.
* **Isolated Sandboxes:** Uses Terraform Workspaces (e.g., `pov-acme`) so you can run multiple POVs in the same account without collisions.
* **Full Architecture:** Deploys the standard OrbitPay 4-Team model (Payments, Wallet, CX, Infra) with L1-L3 service dependencies.

## 🚀 Quick Start

### Prerequisites

* [Terraform](https://developer.hashicorp.com/terraform/downloads) (v1.3+)
* PagerDuty **User API Token** (Account Settings -> API Access)
* **Slack** (optional): A Slack workspace connected to PagerDuty, a bot token (`xoxb-...`) with `channels:write` scope, and your Slack Workspace ID (`T...` format).

### Provision a POV

1. Run the provisioner script:

    ```bash
    ./scripts/quickstart.sh
    ```

2. Follow the prompts:
    * **Token:** Paste your PagerDuty API Token.
    * **Email:** Enter your email (you will be placed on-call).
    * **Customer Name:** Enter the prospect's name (e.g., "Acme").

3. **Done!** The script will create a workspace (e.g., `pov-acme`) and deploy the resources.

## 🏗 What Gets Built?

**Teams:**

* Payments Platform (PP)
* Wallet & Ledgers (WL)
* Customer Experience (CX)
* Core Infrastructure (CI)

**Schedules:**

* 4x 24/7 Schedules (one per team), with YOU on call.

**Services:**

* **Business Services:** Payments API, Digital Wallet, etc.
* **Technical Services:** API Gateway, Ledger DB, Service Mesh, etc.
* **Dependencies:** Full topology mapping (L1/L2/L3).

**Automation:**

* Global Event Orchestration (Routing & Severity rules).
* Team Event Orchestrations.

**Slack (optional):**

* 4x Incident channels (`incidents-payments-platform`, `incidents-wallet-and-ledgers`, `incidents-customer-experience`, `incidents-core-infrastructure`)
* PagerDuty team-reference connections (all incident lifecycle events)
* Requires a [Slack bot token](https://docs.slack.dev/app-management/quickstart-app-settings) with `channels:write` scope and the Slack Workspace ID.

## 🧹 Tear Down

To destroy a specific POV environment, run the script with the `--destroy` flag:

```bash
./scripts/quickstart.sh --destroy
```

Follow the prompts to select the Customer Name (workspace) you wish to remove. The script will:

1. Verify credentials.
2. Select the workspace (e.g., `pov-acme`).
3. Run `terraform destroy`.
4. Delete the workspace.
