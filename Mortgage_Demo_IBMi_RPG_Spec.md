# Lightweight Demo Specification: IBM i RPG Mortgage Showcase Application

## 1. Executive Summary & Purpose

- **Goal:** Showcase a modern mortgage application journey backed by a modular, free-format ILE RPG backend running on IBM i, paired with a lightweight web frontend (HTML/CSS/JS).
- **Scope:** Thin-veneer demonstration application for client presentations.
- **Backend Tech Stack:** IBM i Db2 for i, Free-Format ILE RPG (`**FREE`), Service Programs (`*SRVPGM`), Embedded SQL, JSON exchange.
- **Frontend Tech Stack:** Single-page or multi-step HTML5/CSS/JavaScript communicating via REST/JSON.

---

## 2. Customer Journey & Modular RPG Program Mapping

| Step | Journey Stage | User & System Action | RPG Module / Service Program | Key Subprocedure / Entry Point |
|---|---|---|---|---|
| **1** | **Start Application** | Initialize new mortgage file, assign unique Application ID. | `MTGAPP_SV` (*SRVPGM) | `mtg_createApp()` |
| **2** | **Application & Property Details** | Select purchase/remortgage/mover type, purchase price, loan amount, term. | `MTGAPP_SV` (*SRVPGM) | `mtg_savePropertyDetails()` |
| **3** | **Applicant & Financial Profile** | Enter income, employment, living costs, existing loans/cards. | `MTGFIN_SV` (*SRVPGM) | `mtg_saveApplicant()`, `mtg_saveFinances()` |
| **4** | **Calculations & Affordability** | Compute LTV %, debt-to-income (DTI), max loan, monthly payments. | `MTGCALC_SV` (*SRVPGM) | `mtg_calcLTV()`, `mtg_calcAffordability()`, `mtg_calcRepayment()` |
| **5** | **Product & Rate Catalog** | Filter & display suitable fixed/variable mortgage products. | `MTGPRD_SV` (*SRVPGM) | `mtg_getEligibleProducts()` |
| **6** | **Product Selection & Docs** | Choose product, record simulated ID & document upload metadata. | `MTGPRD_SV` & `MTGDOC_SV` | `mtg_selectProduct()`, `mtg_addDocMetadata()` |
| **7** | **Review & Submission** | Review combined application summary and submit for decisioning. | `MTGAPP_SV` (*SRVPGM) | `mtg_submitApplication()` |
| **8** | **Simulated Underwriting Decision** | Execute rules engine; produce Instant Accept, Refer, or Decline. | `MTGDEC_SV` (*SRVPGM) | `mtg_evaluateDecision()` |
| **9** | **Status & Tracking** | View real-time status, timeline, and pending conditions/actions. | `MTGAPP_SV` (*SRVPGM) | `mtg_getApplicationStatus()` |

---

## 3. High-Level Architecture Diagram

```mermaid
graph TD
    subgraph Frontend [Presentation Layer - Web Veneer]
        UI[HTML5 / JavaScript Single Page App]
    end

    subgraph API_Tier [IBM i Web API / REST Interface]
        ROUTER[MTGREST - RPG REST Controller / Web Dispatcher]
    end

    subgraph RPG_Core [ILE RPG Modular Service Programs (*SRVPGM)]
        APP_SRV[MTGAPP_SV - Application Lifecycle]
        FIN_SRV[MTGFIN_SV - Applicant & Financial Profile]
        CALC_SRV[MTGCALC_SV - Calculation Engine]
        PRD_SRV[MTGPRD_SV - Product Catalog & Matching]
        DOC_SRV[MTGDOC_SV - Document Metadata]
        DEC_SRV[MTGDEC_SV - Rules & Underwriting Decision]
    end

    subgraph Database [IBM i Db2 for i Storage]
        DB[(Mortgage Demo Physical Files / DDL Tables)]
    end

    UI <-->|HTTP / JSON REST API| ROUTER
    ROUTER --> APP_SRV
    ROUTER --> FIN_SRV
    ROUTER --> CALC_SRV
    ROUTER --> PRD_SRV
    ROUTER --> DOC_SRV
    ROUTER --> DEC_SRV

    APP_SRV --> DB
    FIN_SRV --> DB
    PRD_SRV --> DB
    DOC_SRV --> DB
    DEC_SRV --> DB
    DEC_SRV --> CALC_SRV
```

---

## 4. Backend RPG Component Specifications

### 4.1. Common Copybooks & Data Structures (`QCPYSRC`)

#### `MTG_H.rpgleinc` (Prototypes & Global Constants)
```rpgle
**FREE
// Return Code Constants
dcl-c RC_SUCCESS     'OK';
dcl-c RC_REFER       'REFER';
dcl-c RC_DECLINE     'DECLINE';
dcl-c RC_ERROR       'ERR';

// Decision Statuses
dcl-c STAT_DRAFT     'DRAFT';
dcl-c STAT_SUBMITTED 'SUBMITTED';
dcl-c STAT_APPROVED  'APPROVED';
dcl-c STAT_REFERRED  'REFERRED';
dcl-c STAT_DECLINED  'DECLINED';

// Common Data Structures
dcl-ds ds_Application qualified template;
  appId          int(10);
  appType        varchar(20);      // 'FIRST_TIME', 'MOVER', 'REMORTGAGE'
  status         varchar(20);
  propertyValue  packed(11: 2);
  loanAmount     packed(11: 2);
  termYears      int(5);
  selectedProdId varchar(10);
  interestRate   packed(5: 2);
  monthlyPayment packed(9: 2);
  createdTs      timestamp;
end-ds;

dcl-ds ds_FinancialProfile qualified template;
  appId          int(10);
  grossIncome    packed(11: 2);
  otherIncome    packed(11: 2);
  monthlyExpenses packed(9: 2);
  existingDebts  packed(9: 2);
  creditScoreEst int(5);
end-ds;

dcl-ds ds_DecisionResult qualified template;
  appId          int(10);
  decisionCode   varchar(10);     // 'APPROVED', 'REFERRED', 'DECLINED'
  reasonCode     varchar(30);     // e.g. 'LTV_WITHIN_LIMITS', 'DTI_EXCEEDED'
  reasonDesc     varchar(100);
  maxLoanAllowed packed(11: 2);
  evaluatedTs    timestamp;
end-ds;
```

---

### 4.2. Service Program Modules

#### Module 1: `MTGAPP_SV` (Application Lifecycle Management)
- **Object Type:** `*SRVPGM`
- **Source Member:** `MTGAPP_SV.rpgle`
- **Purpose:** Handles application creation, updates, submission transitions, and status inquiries.
- **Exported Subprocedures:**
  - `mtg_createApp(pAppType: varchar(20); pApplicantName: varchar(80)): int(10)`
  - `mtg_savePropertyDetails(pAppId: int(10); pPropValue: packed(11:2); pLoanAmt: packed(11:2); pTermYrs: int(5)): ind`
  - `mtg_submitApplication(pAppId: int(10)): varchar(20)`
  - `mtg_getApplicationStatus(pAppId: int(10); dsOut: likeds(ds_Application)): ind`

#### Module 2: `MTGFIN_SV` (Applicant & Financial Profile)
- **Object Type:** `*SRVPGM`
- **Source Member:** `MTGFIN_SV.rpgle`
- **Purpose:** Manages income, employment details, committed expenditure, and liabilities.
- **Exported Subprocedures:**
  - `mtg_saveFinances(pFinProfile: likeds(ds_FinancialProfile)): ind`
  - `mtg_getFinances(pAppId: int(10); pFinProfile: likeds(ds_FinancialProfile)): ind`

#### Module 3: `MTGCALC_SV` (Financial Calculation Engine)
- **Object Type:** `*SRVPGM`
- **Source Member:** `MTGCALC_SV.rpgle`
- **Purpose:** Pure calculation engine for Loan-To-Value (LTV), debt ratios, borrowing caps, and monthly amortization.
- **Exported Subprocedures:**
  - `mtg_calcLTV(pLoanAmount: packed(11:2); pPropValue: packed(11:2)): packed(5:2)`
    $$\text{LTV} = \frac{\text{Loan Amount}}{\text{Property Value}} \times 100$$
  - `mtg_calcAffordability(pGrossIncome: packed(11:2); pMonthlyExp: packed(9:2); pDebts: packed(9:2)): packed(11:2)`
    $$\text{Max Borrowing} = (\text{Gross Income} \times 4.5) - (\text{Committed Debts} \times 12)$$
  - `mtg_calcRepayment(pPrincipal: packed(11:2); pRatePct: packed(5:2); pTermYears: int(5)): packed(9:2)`
    $$\text{Monthly Payment} = P \times \frac{r(1+r)^n}{(1+r)^n - 1} \quad \text{where } r = \frac{\text{Rate}}{1200}, \; n = \text{Years} \times 12$$

#### Module 4: `MTGPRD_SV` (Product Matching & Catalog)
- **Object Type:** `*SRVPGM`
- **Source Member:** `MTGPRD_SV.rpgle`
- **Purpose:** Returns simulated fixed/variable mortgage rates based on LTV tiers and stores the selected product.
- **Exported Subprocedures:**
  - `mtg_getEligibleProducts(pLTV: packed(5:2); pTermYears: int(5); pJsonOut: varchar(2000)): int(5)`
  - `mtg_selectProduct(pAppId: int(10); pProdId: varchar(10); pRate: packed(5:2)): ind`

#### Module 5: `MTGDOC_SV` (Document & Identity Mock)
- **Object Type:** `*SRVPGM`
- **Source Member:** `MTGDOC_SV.rpgle`
- **Purpose:** Captures document upload metadata (e.g. Payslip, ID) and simulates KYC verification flags.
- **Exported Subprocedures:**
  - `mtg_addDocMetadata(pAppId: int(10); pDocType: varchar(20); pFileName: varchar(100)): ind`
  - `mtg_getDocsList(pAppId: int(10); pJsonOut: varchar(2000)): int(5)`

#### Module 6: `MTGDEC_SV` (Automated Underwriting & Decision Engine)
- **Object Type:** `*SRVPGM`
- **Source Member:** `MTGDEC_SV.rpgle`
- **Purpose:** Evaluates rule thresholds against the application and financial profiles to produce a decision.
- **Business Rules Logic:**
  1. **LTV Check:** If $\text{LTV} > 95\% \rightarrow \text{DECLINED}$ (`LTV_TOO_HIGH`).
  2. **Affordability Check:** If $\text{Loan Amount} > \text{Max Loan Allowed} \rightarrow \text{REFERRED}$ (`AFFORDABILITY_STRETCH`).
  3. **Credit / Default Threshold:** If $\text{Credit Score} < 600 \rightarrow \text{REFERRED}$ (`CREDIT_REVIEW_REQUIRED`).
  4. **Otherwise:** $\rightarrow \text{APPROVED}$ (`STANDARD_APPROVAL`).
- **Exported Subprocedures:**
  - `mtg_evaluateDecision(pAppId: int(10); dsDecision: likeds(ds_DecisionResult)): ind`

---

### 4.3. API Dispatcher Program (`MTGREST.rpgle`)

- **Object Type:** `*PGM` (ILE RPG REST Web Handler / IWS Entry Point)
- **Role:** Accepts HTTP requests with action verbs, converts JSON payloads to RPG data structures, invokes corresponding `*SRVPGM` subprocedures, and returns JSON responses.

#### REST Endpoints Mapping:
1. `POST /api/application/new` $\rightarrow$ Calls `mtg_createApp`
2. `PUT  /api/application/{id}/property` $\rightarrow$ Calls `mtg_savePropertyDetails`
3. `PUT  /api/application/{id}/finances` $\rightarrow$ Calls `mtg_saveFinances`
4. `GET  /api/application/{id}/calculate` $\rightarrow$ Calls `mtg_calcLTV`, `mtg_calcAffordability`, `mtg_calcRepayment`
5. `GET  /api/products?ltv={ltv}` $\rightarrow$ Calls `mtg_getEligibleProducts`
6. `POST /api/application/{id}/select-product` $\rightarrow$ Calls `mtg_selectProduct`
7. `POST /api/application/{id}/documents` $\rightarrow$ Calls `mtg_addDocMetadata`
8. `POST /api/application/{id}/submit` $\rightarrow$ Calls `mtg_submitApplication` & `mtg_evaluateDecision`
9. `GET  /api/application/{id}/status` $\rightarrow$ Calls `mtg_getApplicationStatus`

---

## 5. Lightweight Db2 for i Schema (DDL)

```sql
-- Application Header Table
CREATE OR REPLACE TABLE MTGAPP (
    APP_ID          INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    CUST_NAME       VARCHAR(80)  NOT NULL,
    APP_TYPE        VARCHAR(20)  NOT NULL,
    STATUS          VARCHAR(20)  DEFAULT 'DRAFT',
    PROP_VALUE      DECIMAL(11,2) DEFAULT 0.00,
    LOAN_AMT        DECIMAL(11,2) DEFAULT 0.00,
    TERM_YRS        INT          DEFAULT 25,
    PROD_ID         VARCHAR(10)  DEFAULT '',
    INT_RATE        DECIMAL(5,2) DEFAULT 0.00,
    MONTHLY_PMT     DECIMAL(9,2) DEFAULT 0.00,
    CREATED_TS      TIMESTAMP    DEFAULT CURRENT_TIMESTAMP
);

-- Financials Table
CREATE OR REPLACE TABLE MTGFIN (
    APP_ID          INT PRIMARY KEY REFERENCES MTGAPP(APP_ID),
    GROSS_INCOME    DECIMAL(11,2) DEFAULT 0.00,
    OTHER_INCOME    DECIMAL(11,2) DEFAULT 0.00,
    MONTHLY_EXP     DECIMAL(9,2)  DEFAULT 0.00,
    EXISTING_DEBTS  DECIMAL(9,2)  DEFAULT 0.00,
    CREDIT_SCORE    INT          DEFAULT 720
);

-- Product Catalog Seed Table
CREATE OR REPLACE TABLE MTGPRD (
    PROD_ID         VARCHAR(10) PRIMARY KEY,
    PROD_NAME       VARCHAR(60) NOT NULL,
    RATE_TYPE       VARCHAR(20) NOT NULL, -- 'FIXED_2YR', 'FIXED_5YR', 'VARIABLE'
    INITIAL_RATE    DECIMAL(5,2) NOT NULL,
    MAX_LTV         DECIMAL(5,2) NOT NULL,
    FEE             DECIMAL(7,2) DEFAULT 0.00
);

-- Simulated Seed Products
INSERT INTO MTGPRD (PROD_ID, PROD_NAME, RATE_TYPE, INITIAL_RATE, MAX_LTV, FEE) VALUES
('FIX2_60', '2-Year Fixed Rate (Low LTV)', 'FIXED_2YR', 4.15, 60.00, 995.00),
('FIX2_80', '2-Year Fixed Rate (Standard)', 'FIXED_2YR', 4.45, 80.00, 995.00),
('FIX5_80', '5-Year Fixed Rate (Standard)', 'FIXED_5YR', 4.25, 80.00, 995.00),
('FIX5_90', '5-Year Fixed Rate (High LTV)', 'FIXED_5YR', 4.79, 90.00, 0.00),
('VAR_STD', 'Standard Variable Tracker',    'VARIABLE',  5.25, 95.00, 0.00);

-- Underwriting Decision Log Table
CREATE OR REPLACE TABLE MTGDEC (
    DEC_ID          INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    APP_ID          INT REFERENCES MTGAPP(APP_ID),
    DECISION_CODE   VARCHAR(10) NOT NULL,
    REASON_CODE     VARCHAR(30) NOT NULL,
    REASON_DESC     VARCHAR(100),
    MAX_LOAN        DECIMAL(11,2),
    DECISION_TS     TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Event & Output Audit Log Table
CREATE OR REPLACE TABLE MTGAUDIT (
    AUDIT_ID        INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    APP_ID          INT NOT NULL DEFAULT 0,
    ACTION_VERB     VARCHAR(30) NOT NULL,
    HTTP_STATUS     INT NOT NULL DEFAULT 200,
    STATUS_CODE     VARCHAR(20) NOT NULL DEFAULT '',
    OUTPUT_PAYLOAD  VARCHAR(4000) NOT NULL DEFAULT '',
    USER_PROFILE    VARCHAR(18) NOT NULL DEFAULT USER,
    JOB_NAME        VARCHAR(28) NOT NULL DEFAULT '',
    LOGGED_TS       TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);
```

---

## 6. Frontend Showcase Web Veneer (Single Page App)

- **Layout Structure:**
  - Multi-step wizard banner (Steps 1–9) with visual progress bar.
  - Step Card Container rendering dynamic view for each step.
  - Live side-panel displaying indicative LTV %, Max Borrowing capacity, and Monthly Repayment summary.
- **Tech implementation:** Pure Vanilla HTML5, CSS3, and JavaScript (`fetch()` API) for zero-dependency portability.
