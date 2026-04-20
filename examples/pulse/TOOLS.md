# TOOLS.md - Local Notes

## PostHog
- **Host:** https://us.posthog.com (cloud, not self-hosted)
- **API Key file:** `/home/node/.openclaw/posthog_api_key.txt`
- **Key experiments:**
  - V6 pricing: experiment #362770, 50/50 V4 vs V6
  - V5 pricing: flag ID 152083 (killed, 100% control)
- **Use for:** Funnel analysis, feature flags, experiment results, user behavior, event tracking

## Google Ads
- **Customer ID:** 868-350-6396
- **Manager ID:** 785-537-2195
- **Credentials:** `/home/node/.openclaw/google_ads_credentials.json`
- **Report script:** `/home/node/.openclaw/google_ads_report.js`
- **Use for:** Campaign performance, CPA tracking, keyword analysis, budget optimization

## Stripe
- **API Key:** `/home/node/.openclaw/stripe-key.txt` (restricted live key)
- **Use for:** Revenue metrics, MRR, churn, subscription analysis, plan distribution
- **Key plans to track:** V4 plans vs V6 plans (Starter $49, Growth $99, Pro $199, Enterprise $499)
- **Watch for:** V6 plan leakage (V6 users buying V4 plan IDs)

## Slack Channels
- #truelist-team (C0AQS7PN3EF) — inter-bot handoffs and collaboration. Scan for "@pulse" mentions on heartbeat.
- #marketing (C085D6W27NY) — post reports and data insights here
- Grant's DM: D0AC56SRN4W — for urgent findings

## Recurring Report Schedule
- **Weekly Google Ads:** Monday 9 AM ET → #marketing
- **Monthly Google Ads:** 1st of month 9 AM ET → #marketing
- **V6 Pricing Weekly:** Monday 9 AM ET → #marketing

## Key Metrics Quick Reference
- **Healthy validation throughput:** 200-400 emails/sec
- **Current Google Ads spend:** ~$8.6k/mo
- **Target CPA:** <$220 (current blended)
- **Best CPA:** $110 (main search campaign)
