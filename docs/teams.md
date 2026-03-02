# Teams Maintained (POV Starter Pack)

This repo manages a minimal, shared PagerDuty configuration for OrbitPay's POV starter pack. Per-user demo slices and user-specific services/config are explicitly out of scope.

Code | Team Name
-----|----------
PP  | Payments Platform
WL  | Wallet & Ledgers
CX  | Customer Experience
CI  | Core Infrastructure

## Technical Services (POV)

### Payments Platform (PP)

- Payments API Gateway
- Payments Orchestrator (sync)
- Payments Rules Engine
- Idempotency Token Service

### Wallet & Ledgers (WL)

- Payments Ledger DB Cluster
- Wallet API
- Balance Manager
- Funding Source Linker
- Ledger DB Cluster (wallet)

### Customer Experience (CX)

- Profile Service
- Web Frontend (SSR)
- Mobile API BFF
- Notification Service
- Content & CMS Service
- Accessibility & A/B Testing
- Profile API
- Preferences Service

### Core Infrastructure (CI)

- Service Mesh / mTLS
- Edge WAF/CDN
- Secrets Manager
- CDN/Edge Caching
- Push Gateway

## Business Services and Dependencies

Each business service maps to technical services with a dependency layer:

- L1 = direct, L2 = supporting, L3 = foundational

### Payments API

- Idempotency Token Service (L1)
- Payments API Gateway (L1)
- Payments Orchestrator (sync) (L1)
- Payments Rules Engine (L1)
- Payments Ledger DB Cluster (L2)
- Edge WAF/CDN (L3)
- Service Mesh / mTLS (L3)

### Digital Wallet

- Balance Manager (L1)
- Funding Source Linker (L1)
- Wallet API (L1)
- Ledger DB Cluster (wallet) (L2)
- Profile Service (L2)
- Secrets Manager (L3)

### Customer Experience Portal

- Mobile API BFF (L1)
- Notification Service (L1)
- Web Frontend (SSR) (L1)
- Accessibility & A/B Testing (L2)
- Content & CMS Service (L2)
- CDN/Edge Caching (L3)
- Push Gateway (L3)

### Account Management

- Profile API (L1)
- Preferences Service (L2)

## Source of Truth

- Terraform locals in `main.tf`
- Outputs in `outputs.tf`
