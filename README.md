# README — Data Engineering Test Workflow
Author: Matheus Bidarra

This guide explains how to set up and run the **n8n workflow** (`dataEngTest.json`) that implements the Data Engineering Test.  

---

## 1. Prerequisites

- **Google Cloud Platform (GCP) account**
  - BigQuery enabled  
  - Google Cloud Storage (GCS) bucket created (default: `n8n-datatest`)
- **n8n instance** (Cloud)
- **OpenAI account** (for the AI agent - I sent by email an already payed key to be used)

---

## 2. Import the Workflow

1. Open your n8n instance.  
2. Go to **Workflows → Import from File**.  
3. Upload `dataEngTest.json`.  
4. You will now see three main sections (marked with Sticky Notes):
   - **KPI INGESTION WORKFLOW**  
   - **API ENDPOINT WORKFLOW (`/metrics`)**  
   - **AI AGENT WORKFLOW (`/askAi`)**

---

## 3. Configure Google Cloud Credentials

### 3.1 Create a Service Account
1. Go to [Google Cloud Console → IAM & Admin → Service Accounts](https://console.cloud.google.com/iam-admin/serviceaccounts).
2. Create a new service account (e.g., `n8n-bigquery-sa`).
3. Grant it roles:
   - `BigQuery Admin` (for creating schemas/functions)
   - `Storage Object Admin` (for writing to GCS)

### 3.2 Create & Download JSON Key
1. On the service account, go to **Keys → Add Key → JSON**.  
2. Save the file locally.

### 3.3 Add Credentials to n8n
1. In n8n, go to **Credentials → Create → Google BigQuery**.  
   - Upload your JSON key.  
   - Ensure **Project ID** = `n8ndatatestproject` (or your project).  
2. Do the same for **Google Cloud Storage**.  
3. Optionally, configure **Google Sheets OAuth** if you want ingestion from Sheets instead of static CSV.

---

## 4. BigQuery Schema Setup (Medallion)

The workflow auto-creates the required schemas/tables, but ensure you allow `CREATE SCHEMA` in your project.

The architecture follows the **Medallion pattern**:
- **Bronze** → `mkt_bronze.mkt_daily_raw`
- **Silver** → `mkt_silver.fact_mkt_daily`
- **Gold** → `mkt_gold.v_mkt_totals_daily` (daily totals view)
- **Lib** → `mkt_lib.fn_kpi_window` (table function for CAC/ROAS)

These will be created automatically by the **ELT** node the first time ingestion runs.

---

## 5. Running Ingestion

There are two triggers:
- **Manual**: Run the node `N8n_Manual_Ingestion`.  
- **Webhook**: Call `POST /ingestion` (protected with Basic Auth).

Flow:
1. Reads dataset from **Google Sheets** (or your CSV).  
2. Normalizes and hashes file (node `Hash_Md5`).  
3. Uploads to GCS (`GCS_BronzeLayer`).  
4. Executes ELT SQL on BigQuery (node `ELT`).  
   - Loads raw → Bronze  
   - MERGE into Silver  
   - Refreshes Gold View

Response: JSON with row counts and date range.

---

## 6. Querying Metrics API

**Endpoint:** `/metrics` (GET, Basic Auth protected)

Parameters:
- `?start=YYYY-MM-DD&end=YYYY-MM-DD` (optional)  
- Default: last 30 days vs previous 30

Example:
```bash
curl -u user:pass   "https://<your-n8n-instance>/metrics?start=2025-01-02&end=2025-02-01"
```

Response:
```json
{
  "window": { "start": "2025-01-02", "end": "2025-02-01" },
  "CAC":  { "current": 30.28, "previous": 33.61, "delta_pct": -0.0991 },
  "ROAS": { "current": 3.30, "previous": 2.97, "delta_pct": 0.1100 }
}
```

---

## 7. Using the AI Agent

**Endpoint:** `/askAi` (POST, Basic Auth protected)

Body:
```json
{ "question": "Compare CAC and ROAS last 30 days vs prior" }
```

Flow:
1. Validates headers & payload.  
2. Sends question to **OpenAI** (node `OpenAI Chat Model`).  
3. Parses with **Structured Output Parser** (JSON Schema enforced).  
4. Normalizes dates/timezone (node `AiOutput_Normalizer`).  
5. Queries BigQuery function `fn_kpi_window`.  
6. Responds with structured JSON.

Example Response:
```json
{
  "question": "Compare CAC and ROAS last 30 days vs prior",
  "window": { "start": "2025-07-01", "end": "2025-07-30" },
  "cac":  { "current": 29.05, "previous": 30.50, "delta_pct": -0.0475 },
  "roas": { "current": 3.44, "previous": 3.27, "delta_pct": 0.0498 }
}
```

---
