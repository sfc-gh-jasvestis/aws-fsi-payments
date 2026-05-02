import streamlit as st
import pandas as pd
import json
import re
from snowflake.snowpark.context import get_active_session

session = get_active_session()

st.set_page_config(page_title="SG Payments Hub", layout="wide")
st.title("Singapore Cross-Border Payments Hub")
st.caption("Singapore FSI Demo — Snowflake Dynamic Tables + Amazon Bedrock + QuickSight")

with st.sidebar:
    st.markdown("### Architecture")
    st.code("""
┌──────────────────────────┐
│     Amazon S3 / Kinesis  │
│  (Payment Messages)      │
└─────────┬────────────────┘
          │ Snowpipe
          ▼
┌──────────────────────────┐
│      Snowflake           │
│  ┌────────────────────┐  │
│  │ RAW Schema         │  │
│  │ Payments, Settle-  │  │
│  │ ments, FX, Excepts │  │
│  └────────┬───────────┘  │
│           ▼              │
│  ┌────────────────────┐  │
│  │ CURATED (Dynamic)  │  │
│  │ • Payment Enriched │  │
│  │ • Corridor Stats   │  │
│  │ • Exception Queue  │  │
│  └────────┬───────────┘  │
│           ▼              │
│  ┌────────────────────┐  │
│  │ AI Schema          │  │
│  │ • Bedrock Analysis │  │
│  │ • Anomaly Detect   │  │
│  └────────────────────┘  │
└───────────┬──────────────┘
            │ External Access
            ▼
┌──────────────────────────┐
│   Amazon Bedrock         │
│   Claude Sonnet 4        │
└──────────────────────────┘
""", language=None)
    st.divider()
    st.caption("FAST | PayNow | SWIFT | GIRO")

tab1, tab2, tab3, tab4 = st.tabs([
    "Payment Monitor",
    "Settlement Tracker",
    "Exception Queue",
    "Analytics"
])


def parse_result(raw):
    result = str(raw).strip()
    if result.startswith("```"):
        result = re.sub(r"^```(?:json)?\s*", "", result)
        result = re.sub(r"\s*```$", "", result)
    try:
        return json.loads(result)
    except Exception:
        m = re.search(r'\{.*\}', result, re.DOTALL)
        if m:
            try:
                return json.loads(m.group())
            except Exception:
                return {"error": result}
        return {"error": result}


with tab1:
    st.header("Payment Monitor")
    st.markdown("Real-time view of cross-border payment flows across Singapore corridors.")

    kpi_df = session.sql("""
        SELECT
            COUNT(*) AS TOTAL_PAYMENTS,
            ROUND(SUM(AMOUNT_SGD), 0) AS TOTAL_VOLUME,
            ROUND(AVG(AMOUNT_SGD), 0) AS AVG_AMOUNT,
            SUM(CASE WHEN SETTLEMENT_STATUS = 'CLEARED' THEN 1 ELSE 0 END) AS CLEARED,
            SUM(CASE WHEN SETTLEMENT_STATUS = 'PENDING' THEN 1 ELSE 0 END) AS PENDING,
            SUM(CASE WHEN SETTLEMENT_STATUS = 'FAILED' THEN 1 ELSE 0 END) AS FAILED,
            ROUND(SUM(CASE WHEN SETTLEMENT_STATUS = 'CLEARED' THEN 1 ELSE 0 END) * 100.0 / COUNT(*), 1) AS SUCCESS_RATE
        FROM FSI_PAYMENTS.CURATED.PAYMENT_ENRICHED
    """).to_pandas()

    c1, c2, c3, c4 = st.columns(4)
    c1.metric("Total Payments", f"{kpi_df['TOTAL_PAYMENTS'].iloc[0]:,}")
    c2.metric("Volume (SGD)", f"${kpi_df['TOTAL_VOLUME'].iloc[0]:,.0f}")
    c3.metric("Success Rate", f"{kpi_df['SUCCESS_RATE'].iloc[0]}%")
    c4.metric("Avg Amount", f"${kpi_df['AVG_AMOUNT'].iloc[0]:,.0f}")

    s1, s2, s3 = st.columns(3)
    s1.metric("Cleared", f"{kpi_df['CLEARED'].iloc[0]}", delta="OK")
    s2.metric("Pending", f"{kpi_df['PENDING'].iloc[0]}", delta="In Progress")
    s3.metric("Failed", f"{kpi_df['FAILED'].iloc[0]}", delta="Attention", delta_color="inverse")

    st.divider()

    col_left, col_right = st.columns(2)
    with col_left:
        st.subheader("Volume by Corridor")
        corridor_df = session.sql("""
            SELECT CORRIDOR, SUM(AMOUNT_SGD) AS VOLUME
            FROM FSI_PAYMENTS.CURATED.PAYMENT_ENRICHED
            GROUP BY CORRIDOR ORDER BY VOLUME DESC
        """).to_pandas()
        st.bar_chart(corridor_df.set_index("CORRIDOR")["VOLUME"])

    with col_right:
        st.subheader("Payments by Type")
        type_df = session.sql("""
            SELECT PAYMENT_TYPE, COUNT(*) AS CNT
            FROM FSI_PAYMENTS.CURATED.PAYMENT_ENRICHED
            GROUP BY PAYMENT_TYPE ORDER BY CNT DESC
        """).to_pandas()
        st.bar_chart(type_df.set_index("PAYMENT_TYPE")["CNT"])

    st.divider()
    st.subheader("Recent Payments")
    recent_df = session.sql("""
        SELECT PAYMENT_ID, SENDER_BANK, RECEIVER_BANK, AMOUNT_SGD, PAYMENT_TYPE, CORRIDOR, SETTLEMENT_STATUS, SLA_STATUS, INITIATED_AT
        FROM FSI_PAYMENTS.CURATED.PAYMENT_ENRICHED
        ORDER BY INITIATED_AT DESC LIMIT 20
    """).to_pandas()
    recent_df["AMOUNT_SGD"] = recent_df["AMOUNT_SGD"].apply(lambda x: f"${float(x):,.0f}")
    st.dataframe(recent_df, use_container_width=True)


with tab2:
    st.header("Settlement Tracker")
    st.markdown("SLA compliance monitoring across payment types. **FAST: 15 min | PayNow: 5 min | SWIFT: 4 hours | GIRO: 24 hours**")
    st.divider()

    sla_df = session.sql("""
        SELECT
            SLA_STATUS,
            COUNT(*) AS CNT
        FROM FSI_PAYMENTS.CURATED.PAYMENT_ENRICHED
        GROUP BY SLA_STATUS
    """).to_pandas()

    on_time = int(sla_df[sla_df["SLA_STATUS"] == "ON_TIME"]["CNT"].sum()) if "ON_TIME" in sla_df["SLA_STATUS"].values else 0
    at_risk = int(sla_df[sla_df["SLA_STATUS"] == "AT_RISK"]["CNT"].sum()) if "AT_RISK" in sla_df["SLA_STATUS"].values else 0
    breached = int(sla_df[sla_df["SLA_STATUS"] == "BREACHED"]["CNT"].sum()) if "BREACHED" in sla_df["SLA_STATUS"].values else 0
    failed = int(sla_df[sla_df["SLA_STATUS"] == "FAILED"]["CNT"].sum()) if "FAILED" in sla_df["SLA_STATUS"].values else 0
    total = on_time + at_risk + breached + failed

    c1, c2, c3, c4 = st.columns(4)
    c1.metric("On Time", on_time)
    c2.metric("At Risk", at_risk)
    c3.metric("Breached", breached)
    c4.metric("Failed", failed)

    if total > 0:
        compliance_pct = on_time * 100 / total
        st.progress(on_time / total)
        st.caption(f"SLA Compliance: {compliance_pct:.1f}% ({on_time}/{total} on time)")

    st.divider()

    st.subheader("Settlement Performance by Payment Type")
    perf_df = session.sql("""
        SELECT PAYMENT_TYPE,
            COUNT(*) AS TOTAL,
            ROUND(AVG(SETTLEMENT_LATENCY_SECONDS), 0) AS AVG_LATENCY_SEC,
            SUM(CASE WHEN SLA_STATUS = 'ON_TIME' THEN 1 ELSE 0 END) AS ON_TIME,
            ROUND(SUM(CASE WHEN SLA_STATUS = 'ON_TIME' THEN 1 ELSE 0 END) * 100.0 / COUNT(*), 1) AS COMPLIANCE_PCT
        FROM FSI_PAYMENTS.CURATED.PAYMENT_ENRICHED
        WHERE SETTLEMENT_STATUS = 'CLEARED'
        GROUP BY PAYMENT_TYPE ORDER BY PAYMENT_TYPE
    """).to_pandas()
    st.dataframe(perf_df, use_container_width=True)

    st.divider()

    st.subheader("Bank Reconciliation")
    recon_df = session.sql("""
        SELECT SENDER_BANK,
            COUNT(*) AS PAYMENTS_SENT,
            ROUND(SUM(AMOUNT_SGD), 0) AS TOTAL_SENT_SGD,
            SUM(CASE WHEN SETTLEMENT_STATUS = 'CLEARED' THEN 1 ELSE 0 END) AS SETTLED,
            SUM(CASE WHEN SETTLEMENT_STATUS = 'PENDING' THEN 1 ELSE 0 END) AS PENDING,
            SUM(CASE WHEN SETTLEMENT_STATUS = 'FAILED' THEN 1 ELSE 0 END) AS FAILED
        FROM FSI_PAYMENTS.CURATED.PAYMENT_ENRICHED
        GROUP BY SENDER_BANK ORDER BY TOTAL_SENT_SGD DESC
    """).to_pandas()
    recon_df["TOTAL_SENT_SGD"] = recon_df["TOTAL_SENT_SGD"].apply(lambda x: f"${float(x):,.0f}")
    st.dataframe(recon_df, use_container_width=True)


with tab3:
    st.header("Exception Queue")
    st.markdown("Open payment exceptions requiring attention. Run **Amazon Bedrock** analysis for AI-recommended resolution.")
    st.divider()

    exc_df = session.sql("""
        SELECT EXCEPTION_ID, PAYMENT_ID, EXCEPTION_TYPE, SEVERITY, DETAILS,
               SENDER_BANK, RECEIVER_BANK, AMOUNT_SGD, CORRIDOR, PAYMENT_TYPE,
               AGE_MINUTES, RAISED_AT
        FROM FSI_PAYMENTS.CURATED.EXCEPTION_QUEUE
        ORDER BY CASE SEVERITY WHEN 'CRITICAL' THEN 1 WHEN 'HIGH' THEN 2 WHEN 'MEDIUM' THEN 3 ELSE 4 END, AGE_MINUTES DESC
    """).to_pandas()

    if exc_df.empty:
        st.success("No open exceptions. All payments processing normally.")
    else:
        sev_counts = exc_df["SEVERITY"].value_counts()
        c1, c2, c3, c4 = st.columns(4)
        c1.metric("Open Exceptions", len(exc_df))
        c2.metric("Critical", sev_counts.get("CRITICAL", 0))
        c3.metric("High", sev_counts.get("HIGH", 0))
        c4.metric("Medium/Low", sev_counts.get("MEDIUM", 0) + sev_counts.get("LOW", 0))

        st.divider()

        type_filter = st.multiselect("Filter by Type", exc_df["EXCEPTION_TYPE"].unique().tolist())
        filtered = exc_df[exc_df["EXCEPTION_TYPE"].isin(type_filter)] if type_filter else exc_df

        labels = [f"{r['EXCEPTION_ID']} — [{r['SEVERITY']}] {r['EXCEPTION_TYPE']} | {r['CORRIDOR']} | SGD {float(r['AMOUNT_SGD']):,.0f}" for _, r in filtered.iterrows()]
        if labels:
            selected_label = st.selectbox("Select Exception", labels)
            idx = labels.index(selected_label)
            exc_row = filtered.iloc[idx]

            st.divider()
            col_l, col_r = st.columns([2, 1])
            with col_l:
                st.markdown(f"**Exception:** {exc_row['EXCEPTION_ID']}")
                st.markdown(f"**Type:** {exc_row['EXCEPTION_TYPE']}")
                st.markdown(f"**Payment:** {exc_row['PAYMENT_ID']} | {exc_row['PAYMENT_TYPE']} | {exc_row['CORRIDOR']}")
                st.markdown(f"**Amount:** SGD {float(exc_row['AMOUNT_SGD']):,.2f}")
                st.markdown(f"**Banks:** {exc_row['SENDER_BANK']} → {exc_row['RECEIVER_BANK']}")
                st.warning(f"**Details:** {exc_row['DETAILS']}")
            with col_r:
                sev = exc_row["SEVERITY"]
                sev_color = {"CRITICAL": "red", "HIGH": "orange", "MEDIUM": "blue", "LOW": "gray"}.get(sev, "gray")
                st.markdown(f"### :{sev_color}[{sev}]")
                st.metric("Age", f"{int(exc_row['AGE_MINUTES'])} min")
                st.metric("Raised", str(exc_row["RAISED_AT"])[:16])

            st.divider()
            if st.button("Analyze with Amazon Bedrock", type="primary", use_container_width=True):
                with st.spinner("Amazon Bedrock analyzing exception..."):
                    raw = session.sql(f"CALL FSI_PAYMENTS.AI.ANALYZE_EXCEPTION('{exc_row['EXCEPTION_ID']}')").collect()[0][0]
                    result = parse_result(raw)

                if "error" in result:
                    st.error(f"Error: {result['error']}")
                else:
                    action = result.get("recommended_action", "N/A")
                    action_color = {"RELEASE": "green", "RETRY": "blue", "RETURN": "orange", "ESCALATE": "red", "BLOCK": "red"}.get(action, "gray")
                    st.markdown(f"### Recommended Action: :{action_color}[{action}]")

                    r1, r2, r3 = st.columns(3)
                    r1.metric("Risk Level", result.get("risk_level", "N/A"))
                    r2.metric("Est. Resolution", f"{result.get('estimated_resolution_time_minutes', 'N/A')} min")
                    r3.metric("Action", action)

                    analysis = result.get("analysis", "").replace('$', '\\$')
                    st.info(f"**Analysis:** {analysis}")

                    sla_impact = result.get("sla_impact", "").replace('$', '\\$')
                    st.markdown(f"**SLA Impact:** {sla_impact}")

                    if result.get("resolution_steps"):
                        st.markdown("**Resolution Steps:**")
                        for step in result["resolution_steps"]:
                            st.markdown(f"- {step}")

                    reg = result.get("regulatory_considerations", "").replace('$', '\\$')
                    if reg:
                        st.markdown(f"**Regulatory Notes:** {reg}")


with tab4:
    st.header("Payment Analytics")
    st.markdown("Cross-border corridor performance and operational metrics.")
    st.divider()

    st.subheader("Corridor Performance")
    corridor_stats = session.sql("""
        SELECT CORRIDOR, PAYMENT_TYPE, PAYMENT_COUNT, TOTAL_VOLUME_SGD, AVG_AMOUNT_SGD,
               AVG_LATENCY_SECONDS, SUCCESS_RATE_PCT
        FROM FSI_PAYMENTS.CURATED.CORRIDOR_STATS
        ORDER BY TOTAL_VOLUME_SGD DESC
    """).to_pandas()
    corridor_stats["TOTAL_VOLUME_SGD"] = corridor_stats["TOTAL_VOLUME_SGD"].apply(lambda x: f"${float(x):,.0f}")
    corridor_stats["AVG_AMOUNT_SGD"] = corridor_stats["AVG_AMOUNT_SGD"].apply(lambda x: f"${float(x):,.0f}")
    st.dataframe(corridor_stats, use_container_width=True)

    st.divider()

    col_l, col_r = st.columns(2)
    with col_l:
        st.subheader("Success Rate by Corridor")
        sr_df = session.sql("""
            SELECT CORRIDOR, ROUND(AVG(SUCCESS_RATE_PCT), 1) AS SUCCESS_RATE
            FROM FSI_PAYMENTS.CURATED.CORRIDOR_STATS
            GROUP BY CORRIDOR ORDER BY SUCCESS_RATE DESC
        """).to_pandas()
        st.bar_chart(sr_df.set_index("CORRIDOR")["SUCCESS_RATE"])

    with col_r:
        st.subheader("Avg Latency by Payment Type (seconds)")
        lat_df = session.sql("""
            SELECT PAYMENT_TYPE, ROUND(AVG(AVG_LATENCY_SECONDS), 0) AS AVG_LATENCY
            FROM FSI_PAYMENTS.CURATED.CORRIDOR_STATS
            GROUP BY PAYMENT_TYPE ORDER BY AVG_LATENCY
        """).to_pandas()
        st.bar_chart(lat_df.set_index("PAYMENT_TYPE")["AVG_LATENCY"])

    st.divider()

    st.subheader("Exception Distribution")
    exc_type_df = session.sql("""
        SELECT EXCEPTION_TYPE, COUNT(*) AS CNT
        FROM FSI_PAYMENTS.RAW.EXCEPTIONS_RAW
        GROUP BY EXCEPTION_TYPE ORDER BY CNT DESC
    """).to_pandas()
    st.bar_chart(exc_type_df.set_index("EXCEPTION_TYPE")["CNT"])

    st.divider()

    st.subheader("FX Rates (Latest)")
    fx_df = session.sql("""
        SELECT CURRENCY_PAIR, MID_RATE, RATE_TS
        FROM FSI_PAYMENTS.RAW.FX_RATES_RAW
        QUALIFY ROW_NUMBER() OVER (PARTITION BY CURRENCY_PAIR ORDER BY RATE_TS DESC) = 1
        ORDER BY CURRENCY_PAIR
    """).to_pandas()
    st.dataframe(fx_df, use_container_width=True)
