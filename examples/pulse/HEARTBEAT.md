# HEARTBEAT.md

## Periodic Checks

### 1. Revenue Health (daily)
- Check Stripe for: new subscriptions, cancellations, failed payments
- Track MRR trend — flag if significant change (>5% week-over-week)
- Watch for V6 plan leakage (V6 users buying V4 plan IDs)

### 2. Google Ads Performance (2-3x per week)
- Pull latest campaign metrics
- Compare CPA to baseline ($220 blended)
- Flag any campaign with CPA >$300 or sudden spend spikes
- Note high-performing keywords or ad copy

### 3. V6 Pricing Experiment (2-3x per week)
- Check PostHog experiment #362770 results
- Track: conversion rate V4 vs V6, revenue per visitor, plan distribution
- Flag if experiment is reaching statistical significance
- Watch for anomalies in the data

### 4. Weekly Reports (Monday 9 AM ET)
- Google Ads weekly report → #marketing
- V6 pricing weekly report → #marketing

### 5. Monthly Reports (1st of month, 9 AM ET)
- Google Ads monthly summary → #marketing
- Revenue/MRR monthly summary

## State Tracking
Track last check times in `memory/heartbeat-state.json`
