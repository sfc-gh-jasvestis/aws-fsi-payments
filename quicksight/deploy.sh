#!/usr/bin/env bash
set -euo pipefail

REGION="us-west-2"
ACCT="__AWS_ACCOUNT_ID__"
DS_ID="fsi-snowflake-ds"
DS_ARN="arn:aws:quicksight:${REGION}:${ACCT}:datasource/${DS_ID}"
QS_USER_ARN="arn:aws:quicksight:us-west-2:__AWS_ACCOUNT_ID__:user/default/__AWS_ACCOUNT_ID__"

fail() { echo "FAILED: $1"; exit 1; }
ok()   { echo "  OK: $1"; }

echo "=== Payments Hub QuickSight Deployment ==="

# Dataset 1: Payment Enriched
echo "Creating dataset: payments-enriched..."
aws quicksight create-data-set \
  --aws-account-id "$ACCT" --region "$REGION" \
  --data-set-id "payments-enriched" \
  --name "Payment Transactions" \
  --import-mode DIRECT_QUERY \
  --physical-table-map '{
    "payments": {
      "CustomSql": {
        "DataSourceArn": "'"${DS_ARN}"'",
        "Name": "PaymentEnriched",
        "SqlQuery": "SELECT PAYMENT_ID, SENDER_BANK, RECEIVER_BANK, AMOUNT_SGD, PAYMENT_TYPE, CORRIDOR, SETTLEMENT_STATUS, SLA_STATUS, SETTLEMENT_LATENCY_SECONDS, FEES, INITIATED_AT FROM FSI_PAYMENTS.CURATED.PAYMENT_ENRICHED",
        "Columns": [
          {"Name": "PAYMENT_ID", "Type": "STRING"},
          {"Name": "SENDER_BANK", "Type": "STRING"},
          {"Name": "RECEIVER_BANK", "Type": "STRING"},
          {"Name": "AMOUNT_SGD", "Type": "DECIMAL"},
          {"Name": "PAYMENT_TYPE", "Type": "STRING"},
          {"Name": "CORRIDOR", "Type": "STRING"},
          {"Name": "SETTLEMENT_STATUS", "Type": "STRING"},
          {"Name": "SLA_STATUS", "Type": "STRING"},
          {"Name": "SETTLEMENT_LATENCY_SECONDS", "Type": "DECIMAL"},
          {"Name": "FEES", "Type": "DECIMAL"},
          {"Name": "INITIATED_AT", "Type": "DATETIME"}
        ]
      }
    }
  }' \
  --permissions '[{"Principal":"'"${QS_USER_ARN}"'","Actions":["quicksight:DescribeDataSet","quicksight:DescribeDataSetPermissions","quicksight:PassDataSet","quicksight:DescribeIngestion","quicksight:ListIngestions","quicksight:UpdateDataSet","quicksight:DeleteDataSet","quicksight:CreateIngestion","quicksight:CancelIngestion","quicksight:UpdateDataSetPermissions"]}]' \
  2>&1 && ok "Dataset: payments-enriched" || fail "Dataset creation"

# Dataset 2: Exception Queue
echo "Creating dataset: payments-exceptions..."
aws quicksight create-data-set \
  --aws-account-id "$ACCT" --region "$REGION" \
  --data-set-id "payments-exceptions" \
  --name "Payment Exceptions" \
  --import-mode DIRECT_QUERY \
  --physical-table-map '{
    "exceptions": {
      "CustomSql": {
        "DataSourceArn": "'"${DS_ARN}"'",
        "Name": "Exceptions",
        "SqlQuery": "SELECT EXCEPTION_ID, PAYMENT_ID, EXCEPTION_TYPE, SEVERITY, DETAILS, EXCEPTION_STATUS, SENDER_BANK, RECEIVER_BANK, AMOUNT_SGD, CORRIDOR, PAYMENT_TYPE, AGE_MINUTES, RAISED_AT FROM FSI_PAYMENTS.CURATED.EXCEPTION_QUEUE",
        "Columns": [
          {"Name": "EXCEPTION_ID", "Type": "STRING"},
          {"Name": "PAYMENT_ID", "Type": "STRING"},
          {"Name": "EXCEPTION_TYPE", "Type": "STRING"},
          {"Name": "SEVERITY", "Type": "STRING"},
          {"Name": "DETAILS", "Type": "STRING"},
          {"Name": "EXCEPTION_STATUS", "Type": "STRING"},
          {"Name": "SENDER_BANK", "Type": "STRING"},
          {"Name": "RECEIVER_BANK", "Type": "STRING"},
          {"Name": "AMOUNT_SGD", "Type": "DECIMAL"},
          {"Name": "CORRIDOR", "Type": "STRING"},
          {"Name": "PAYMENT_TYPE", "Type": "STRING"},
          {"Name": "AGE_MINUTES", "Type": "DECIMAL"},
          {"Name": "RAISED_AT", "Type": "DATETIME"}
        ]
      }
    }
  }' \
  --permissions '[{"Principal":"'"${QS_USER_ARN}"'","Actions":["quicksight:DescribeDataSet","quicksight:DescribeDataSetPermissions","quicksight:PassDataSet","quicksight:DescribeIngestion","quicksight:ListIngestions","quicksight:UpdateDataSet","quicksight:DeleteDataSet","quicksight:CreateIngestion","quicksight:CancelIngestion","quicksight:UpdateDataSetPermissions"]}]' \
  2>&1 && ok "Dataset: payments-exceptions" || fail "Dataset creation"

# Q Topic
echo "Creating Q topic: payments-hub-q-topic..."
Q_TOPIC_DEF=$(mktemp)
cat > "$Q_TOPIC_DEF" <<EOJSON
{
  "AwsAccountId": "${ACCT}",
  "TopicId": "payments-hub-q-topic",
  "Topic": {
    "Name": "Singapore Payments Hub",
    "Description": "Cross-border payment processing, settlement tracking, and exception management for Singapore corridors",
    "DataSets": [{
      "DatasetArn": "arn:aws:quicksight:${REGION}:${ACCT}:dataset/payments-enriched",
      "DatasetName": "Payment Transactions",
      "Columns": [
        {"ColumnName": "PAYMENT_ID", "ColumnFriendlyName": "Payment ID", "ColumnSynonyms": ["transaction","txn"], "IsIncludedInTopic": true},
        {"ColumnName": "SENDER_BANK", "ColumnFriendlyName": "Sender Bank", "ColumnSynonyms": ["originator","sending bank"], "IsIncludedInTopic": true},
        {"ColumnName": "RECEIVER_BANK", "ColumnFriendlyName": "Receiver Bank", "ColumnSynonyms": ["beneficiary bank","receiving bank"], "IsIncludedInTopic": true},
        {"ColumnName": "AMOUNT_SGD", "ColumnFriendlyName": "Amount (SGD)", "ColumnSynonyms": ["value","amount","payment amount"], "IsIncludedInTopic": true, "Aggregation": "SUM"},
        {"ColumnName": "PAYMENT_TYPE", "ColumnFriendlyName": "Payment Type", "ColumnSynonyms": ["channel","rail","method"], "IsIncludedInTopic": true},
        {"ColumnName": "CORRIDOR", "ColumnFriendlyName": "Corridor", "ColumnSynonyms": ["route","country pair","destination"], "IsIncludedInTopic": true},
        {"ColumnName": "SETTLEMENT_STATUS", "ColumnFriendlyName": "Settlement Status", "ColumnSynonyms": ["status","state"], "IsIncludedInTopic": true},
        {"ColumnName": "SLA_STATUS", "ColumnFriendlyName": "SLA Status", "ColumnSynonyms": ["compliance","on time","breached"], "IsIncludedInTopic": true},
        {"ColumnName": "SETTLEMENT_LATENCY_SECONDS", "ColumnFriendlyName": "Latency (seconds)", "ColumnSynonyms": ["speed","time","duration"], "IsIncludedInTopic": true, "Aggregation": "AVERAGE"},
        {"ColumnName": "FEES", "ColumnFriendlyName": "Fees", "ColumnSynonyms": ["cost","charges","revenue"], "IsIncludedInTopic": true, "Aggregation": "SUM"},
        {"ColumnName": "INITIATED_AT", "ColumnFriendlyName": "Payment Time", "ColumnSynonyms": ["date","when","timestamp"], "IsIncludedInTopic": true}
      ]
    }]
  }
}
EOJSON

aws quicksight create-topic --cli-input-json "file://${Q_TOPIC_DEF}" --region "$REGION" 2>&1 \
  && ok "Q Topic: payments-hub-q-topic" || echo "  WARN: Q Topic may already exist"
rm -f "$Q_TOPIC_DEF"

echo ""
echo "=== Payments Hub QuickSight Done ==="
echo "Q Topic ready for: 'What is the total volume by corridor?' or 'Which payment type has the highest latency?'"
