"""
Address Accuracy & Delivery Insights
Full Analysis Workflow
"""

import pandas as pd
import numpy as np
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import matplotlib.gridspec as gridspec
import matplotlib.patches as mpatches
import seaborn as sns
import os
import warnings
warnings.filterwarnings("ignore")

# ─────────────────────────────────────────────
# CONFIG
# ─────────────────────────────────────────────

PALETTE   = ["#1A1A2E", "#16213E", "#0F3460", "#E94560", "#F5A623",
             "#2ECC71", "#3498DB", "#9B59B6", "#E67E22", "#1ABC9C"]
sns.set_theme(style="whitegrid", palette=PALETTE)
plt.rcParams.update({
    "figure.facecolor": "#FAFAFA",
    "axes.facecolor":   "#FFFFFF",
    "axes.edgecolor":   "#CCCCCC",
    "grid.color":       "#EEEEEE",
    "font.family":      "DejaVu Sans",
    "font.size":        11,
    "axes.titlesize":   14,
    "axes.titleweight": "bold",
})

os.makedirs("exports",   exist_ok=True)
os.makedirs("charts",    exist_ok=True)

print("=" * 65)
print("  ADDRESS ACCURACY & DELIVERY INSIGHTS — ANALYSIS WORKFLOW")
print("=" * 65)

# ─────────────────────────────────────────────
# 1. LOAD DATA
# ─────────────────────────────────────────────
print("\n[1/10] Loading dataset …")
df = pd.read_csv("data/address_records.csv", parse_dates=["correction_timestamp"])
print(f"       Loaded {len(df):,} records  |  {df.shape[1]} columns")

# ─────────────────────────────────────────────
# 2. DATA CLEANING
# ─────────────────────────────────────────────
print("\n[2/10] Data cleaning …")

# Normalise booleans that may be stored as strings
for col in ["correction_required", "delivery_success"]:
    if df[col].dtype == object:
        df[col] = df[col].map({"True": True, "False": False, True: True, False: False})

df["city"]             = df["city"].str.strip().str.title()
df["state"]            = df["state"].str.strip().str.title()
df["pincode"]          = df["pincode"].astype(str).str.zfill(6)
df["correct_pincode"]  = df["correct_pincode"].astype(str).str.zfill(6)
df["correction_type"]  = df["correction_type"].str.strip()
df["correction_source"]= df["correction_source"].str.strip()
df["delivery_zone"]    = df["delivery_zone"].str.strip()

# Derived columns
df["pincode_mismatch"]   = df["pincode"] != df["correct_pincode"]
df["accuracy_band"]      = pd.cut(
    df["address_accuracy_score"],
    bins=[0, 50, 65, 80, 90, 100],
    labels=["Critical (<50)", "Low (50-65)", "Medium (65-80)", "High (80-90)", "Excellent (90-100)"]
)
df["correction_date"]    = df["correction_timestamp"].dt.date
df["correction_month"]   = df["correction_timestamp"].dt.to_period("M").astype(str)
df["day_of_week"]        = df["correction_timestamp"].dt.day_name()
df["hour_of_day"]        = df["correction_timestamp"].dt.hour

print(f"       Nulls after cleaning: {df.isnull().sum().sum()}")
print(f"       Pincode mismatches: {df['pincode_mismatch'].sum():,} ({df['pincode_mismatch'].mean()*100:.1f}%)")

# ─────────────────────────────────────────────
# 3. ADDRESS QUALITY ASSESSMENT
# ─────────────────────────────────────────────
print("\n[3/10] Address quality assessment …")

total           = len(df)
corrections     = df["correction_required"].sum()
deliveries_ok   = df["delivery_success"].sum()
pin_mismatches  = df["pincode_mismatch"].sum()
avg_accuracy    = df["address_accuracy_score"].mean()

quality_kpis = {
    "total_records":            total,
    "correction_required":      int(corrections),
    "correction_rate_pct":      round(corrections / total * 100, 2),
    "delivery_success":         int(deliveries_ok),
    "delivery_success_rate_pct":round(deliveries_ok / total * 100, 2),
    "pincode_mismatches":       int(pin_mismatches),
    "pincode_mismatch_rate_pct":round(pin_mismatches / total * 100, 2),
    "avg_address_accuracy_score":round(avg_accuracy, 2),
    "records_below_50_accuracy":int((df["address_accuracy_score"] < 50).sum()),
    "records_above_90_accuracy":int((df["address_accuracy_score"] > 90).sum()),
}

for k, v in quality_kpis.items():
    print(f"       {k:<38}: {v}")

# ─────────────────────────────────────────────
# 4. PINCODE MISMATCH ANALYSIS
# ─────────────────────────────────────────────
print("\n[4/10] Pincode mismatch analysis …")

pincode_mismatch_df = df[df["pincode_mismatch"]].copy()
mismatch_by_city = (
    pincode_mismatch_df.groupby("city")
    .agg(
        mismatch_count=("order_id", "count"),
        avg_accuracy=("address_accuracy_score", "mean"),
        delivery_fail_rate=("delivery_success", lambda x: (1 - x.mean()) * 100),
    )
    .sort_values("mismatch_count", ascending=False)
    .reset_index()
)
mismatch_by_city["avg_accuracy"]      = mismatch_by_city["avg_accuracy"].round(2)
mismatch_by_city["delivery_fail_rate"]= mismatch_by_city["delivery_fail_rate"].round(2)
print(f"       Cities with pincode mismatches: {len(mismatch_by_city)}")
print(mismatch_by_city.head(5).to_string(index=False))

# ─────────────────────────────────────────────
# 5. CORRECTION ACCURACY ANALYSIS
# ─────────────────────────────────────────────
print("\n[5/10] Correction accuracy analysis …")

correction_summary = (
    df[df["correction_required"]]
    .groupby(["correction_type", "correction_source"])
    .agg(
        count=("order_id", "count"),
        avg_score=("address_accuracy_score", "mean"),
        delivery_success_rate=("delivery_success", "mean"),
    )
    .reset_index()
)
correction_summary["avg_score"]            = correction_summary["avg_score"].round(2)
correction_summary["delivery_success_rate"]= (correction_summary["delivery_success_rate"] * 100).round(2)
correction_summary = correction_summary.sort_values("count", ascending=False)

# Source effectiveness
source_eff = (
    df[df["correction_required"]]
    .groupby("correction_source")
    .agg(
        total_corrections=("order_id", "count"),
        avg_score=("address_accuracy_score", "mean"),
        delivery_success_rate=("delivery_success", "mean"),
    )
    .reset_index()
)
source_eff["avg_score"]            = source_eff["avg_score"].round(2)
source_eff["delivery_success_rate"]= (source_eff["delivery_success_rate"] * 100).round(2)
print(source_eff.to_string(index=False))

# ─────────────────────────────────────────────
# 6. ZONE-WISE ERROR ANALYSIS
# ─────────────────────────────────────────────
print("\n[6/10] Zone-wise error analysis …")

zone_summary = (
    df.groupby("delivery_zone")
    .agg(
        total_orders=("order_id", "count"),
        corrections_needed=("correction_required", "sum"),
        pincode_mismatches=("pincode_mismatch", "sum"),
        avg_accuracy=("address_accuracy_score", "mean"),
        delivery_success_rate=("delivery_success", "mean"),
    )
    .reset_index()
)
zone_summary["correction_rate_pct"]    = (zone_summary["corrections_needed"] / zone_summary["total_orders"] * 100).round(2)
zone_summary["pincode_mismatch_pct"]   = (zone_summary["pincode_mismatches"] / zone_summary["total_orders"] * 100).round(2)
zone_summary["avg_accuracy"]           = zone_summary["avg_accuracy"].round(2)
zone_summary["delivery_success_rate"]  = (zone_summary["delivery_success_rate"] * 100).round(2)

print(zone_summary.to_string(index=False))
zone_summary.to_csv("exports/zone_summary.csv", index=False)
print("       Exported → exports/zone_summary.csv")

# ─────────────────────────────────────────────
# 7. ROOT CAUSE ANALYSIS
# ─────────────────────────────────────────────
print("\n[7/10] Root cause analysis …")

root_cause = (
    df[df["correction_required"]]
    .groupby("correction_type")
    .agg(
        frequency=("order_id", "count"),
        avg_accuracy=("address_accuracy_score", "mean"),
        pincode_mismatch_pct=("pincode_mismatch", "mean"),
        delivery_fail_rate=("delivery_success", lambda x: (1 - x.mean()) * 100),
    )
    .reset_index()
    .sort_values("frequency", ascending=False)
)
root_cause["pct_of_all_corrections"] = (root_cause["frequency"] / root_cause["frequency"].sum() * 100).round(2)
root_cause["avg_accuracy"]           = root_cause["avg_accuracy"].round(2)
root_cause["pincode_mismatch_pct"]   = (root_cause["pincode_mismatch_pct"] * 100).round(2)
root_cause["delivery_fail_rate"]     = root_cause["delivery_fail_rate"].round(2)

print(root_cause.to_string(index=False))
root_cause.to_csv("exports/correction_report.csv", index=False)
print("       Exported → exports/correction_report.csv")

# ─────────────────────────────────────────────
# 8. WEEKLY TREND ANALYSIS
# ─────────────────────────────────────────────
print("\n[8/10] Weekly trend analysis …")

weekly_trend = (
    df.groupby("week_number")
    .agg(
        total_orders=("order_id", "count"),
        corrections=("correction_required", "sum"),
        pincode_mismatches=("pincode_mismatch", "sum"),
        avg_accuracy=("address_accuracy_score", "mean"),
        delivery_success=("delivery_success", "sum"),
    )
    .reset_index()
)
weekly_trend["correction_rate_pct"]   = (weekly_trend["corrections"] / weekly_trend["total_orders"] * 100).round(2)
weekly_trend["delivery_success_rate"] = (weekly_trend["delivery_success"] / weekly_trend["total_orders"] * 100).round(2)
weekly_trend["avg_accuracy"]          = weekly_trend["avg_accuracy"].round(2)
weekly_trend["rolling_avg_accuracy"]  = weekly_trend["avg_accuracy"].rolling(4, min_periods=1).mean().round(2)

print(f"       Weeks covered: {weekly_trend['week_number'].min()} – {weekly_trend['week_number'].max()}")

# ─────────────────────────────────────────────
# 9. HOTSPOT DETECTION
# ─────────────────────────────────────────────
print("\n[9/10] Hotspot detection …")

hotspot = (
    df.groupby(["city", "delivery_zone"])
    .agg(
        total_orders=("order_id", "count"),
        corrections=("correction_required", "sum"),
        pincode_mismatches=("pincode_mismatch", "sum"),
        avg_accuracy=("address_accuracy_score", "mean"),
        delivery_failures=("delivery_success", lambda x: (1 - x).sum()),
    )
    .reset_index()
)
hotspot["correction_rate_pct"]   = (hotspot["corrections"] / hotspot["total_orders"] * 100).round(2)
hotspot["delivery_fail_rate_pct"]= (hotspot["delivery_failures"] / hotspot["total_orders"] * 100).round(2)
hotspot["avg_accuracy"]          = hotspot["avg_accuracy"].round(2)
hotspot["hotspot_score"]         = (
    hotspot["correction_rate_pct"] * 0.4 +
    hotspot["delivery_fail_rate_pct"] * 0.4 +
    (100 - hotspot["avg_accuracy"]) * 0.2
).round(2)

hotspot = hotspot.sort_values("hotspot_score", ascending=False).reset_index(drop=True)
hotspot["hotspot_rank"] = hotspot.index + 1
hotspot["is_hotspot"]   = hotspot["hotspot_score"] > hotspot["hotspot_score"].quantile(0.75)

print(f"       Total city-zone combos  : {len(hotspot)}")
print(f"       Identified hotspots (top 25%): {hotspot['is_hotspot'].sum()}")
print(hotspot.head(8).to_string(index=False))

hotspot.to_csv("exports/hotspot_analysis.csv", index=False)
print("       Exported → exports/hotspot_analysis.csv")

# ─────────────────────────────────────────────
# MASTER KPIs
# ─────────────────────────────────────────────
address_kpis = pd.DataFrame([{
    **quality_kpis,
    "total_pincode_corrections": int(df[df["correction_type"] == "Pincode Mismatch"]["correction_required"].sum()),
    "top_error_type":            root_cause.iloc[0]["correction_type"],
    "top_error_pct":             root_cause.iloc[0]["pct_of_all_corrections"],
    "worst_zone":                zone_summary.sort_values("correction_rate_pct", ascending=False).iloc[0]["delivery_zone"],
    "best_zone":                 zone_summary.sort_values("avg_accuracy", ascending=False).iloc[0]["delivery_zone"],
    "best_correction_source":    source_eff.sort_values("delivery_success_rate", ascending=False).iloc[0]["correction_source"],
    "hotspot_city_zones":        int(hotspot["is_hotspot"].sum()),
}])
address_kpis.to_csv("exports/address_kpis.csv", index=False)
print("\n       Exported → exports/address_kpis.csv")

# ─────────────────────────────────────────────
# 10. CHARTS
# ─────────────────────────────────────────────
print("\n[10/10] Generating charts …")

# ── Chart 1: KPI Summary Dashboard ──────────────────────────────────────────
fig, axes = plt.subplots(2, 4, figsize=(20, 9))
fig.suptitle("Address Accuracy & Delivery Insights — KPI Dashboard", fontsize=17, fontweight="bold", y=1.01)
fig.patch.set_facecolor("#F0F4F8")

kpi_cards = [
    ("Total Records",     f"{total:,}",                        "#1A1A2E", "#FFFFFF"),
    ("Correction Rate",   f"{corrections/total*100:.1f}%",     "#E94560", "#FFFFFF"),
    ("Delivery Success",  f"{deliveries_ok/total*100:.1f}%",   "#2ECC71", "#FFFFFF"),
    ("Avg Accuracy Score",f"{avg_accuracy:.1f}",               "#3498DB", "#FFFFFF"),
    ("Pincode Mismatch",  f"{pin_mismatches/total*100:.1f}%",  "#F5A623", "#FFFFFF"),
    ("High Accuracy (>90)",f"{(df['address_accuracy_score']>90).sum()/total*100:.1f}%", "#9B59B6", "#FFFFFF"),
    ("Critical (<50)",    f"{(df['address_accuracy_score']<50).sum():,}", "#E67E22", "#FFFFFF"),
    ("Hotspot Zones",     f"{int(hotspot['is_hotspot'].sum())}", "#0F3460", "#FFFFFF"),
]

for ax, (label, value, bg, fg) in zip(axes.flat, kpi_cards):
    ax.set_facecolor(bg)
    ax.text(0.5, 0.60, value, ha="center", va="center", fontsize=28, fontweight="bold",
            color=fg, transform=ax.transAxes)
    ax.text(0.5, 0.22, label, ha="center", va="center", fontsize=11,
            color=fg, transform=ax.transAxes, alpha=0.85)
    for spine in ax.spines.values():
        spine.set_visible(False)
    ax.set_xticks([])
    ax.set_yticks([])

plt.tight_layout()
plt.savefig("charts/01_kpi_dashboard.png", dpi=150, bbox_inches="tight")
plt.close()
print("       Saved: charts/01_kpi_dashboard.png")

# ── Chart 2: Correction Types Distribution ──────────────────────────────────
fig, (ax1, ax2) = plt.subplots(1, 2, figsize=(18, 7))
fig.suptitle("Correction Type Analysis", fontsize=15, fontweight="bold")

# Bar chart
ct = root_cause.sort_values("frequency")
colors = [PALETTE[i % len(PALETTE)] for i in range(len(ct))]
bars = ax1.barh(ct["correction_type"], ct["frequency"], color=colors, edgecolor="white", linewidth=0.5)
ax1.set_xlabel("Number of Corrections")
ax1.set_title("Frequency by Correction Type")
for bar, val in zip(bars, ct["frequency"]):
    ax1.text(bar.get_width() + 10, bar.get_y() + bar.get_height()/2,
             f"{val:,}", va="center", fontsize=9)

# Pie chart
ct2 = root_cause.sort_values("frequency", ascending=False)
wedge_colors = PALETTE[:len(ct2)]
ax2.pie(ct2["frequency"], labels=ct2["correction_type"], autopct="%1.1f%%",
        colors=wedge_colors, startangle=90,
        wedgeprops={"edgecolor": "white", "linewidth": 1.5})
ax2.set_title("Share of Each Correction Type")

plt.tight_layout()
plt.savefig("charts/02_correction_types.png", dpi=150, bbox_inches="tight")
plt.close()
print("       Saved: charts/02_correction_types.png")

# ── Chart 3: Zone Performance Heatmap ────────────────────────────────────────
zone_corr_type = (
    df[df["correction_required"]]
    .groupby(["delivery_zone", "correction_type"])
    .size()
    .unstack(fill_value=0)
)
fig, ax = plt.subplots(figsize=(16, 6))
sns.heatmap(zone_corr_type, annot=True, fmt="d", cmap="YlOrRd",
            linewidths=0.5, linecolor="white", ax=ax,
            cbar_kws={"label": "Count"})
ax.set_title("Correction Type Distribution by Delivery Zone", fontsize=14, fontweight="bold")
ax.set_xlabel("Correction Type")
ax.set_ylabel("Delivery Zone")
plt.xticks(rotation=35, ha="right")
plt.tight_layout()
plt.savefig("charts/03_zone_heatmap.png", dpi=150, bbox_inches="tight")
plt.close()
print("       Saved: charts/03_zone_heatmap.png")

# ── Chart 4: Weekly Trend ────────────────────────────────────────────────────
fig, axes = plt.subplots(3, 1, figsize=(18, 12), sharex=True)
fig.suptitle("Weekly Performance Trends (2024)", fontsize=15, fontweight="bold")

axes[0].fill_between(weekly_trend["week_number"], weekly_trend["avg_accuracy"],
                     alpha=0.3, color="#3498DB")
axes[0].plot(weekly_trend["week_number"], weekly_trend["avg_accuracy"],
             color="#3498DB", linewidth=2, label="Avg Accuracy")
axes[0].plot(weekly_trend["week_number"], weekly_trend["rolling_avg_accuracy"],
             color="#E94560", linewidth=2, linestyle="--", label="4-Week Rolling Avg")
axes[0].set_ylabel("Accuracy Score")
axes[0].set_title("Average Address Accuracy Score")
axes[0].legend()
axes[0].set_ylim(0, 100)

axes[1].fill_between(weekly_trend["week_number"], weekly_trend["correction_rate_pct"],
                     alpha=0.3, color="#E94560")
axes[1].plot(weekly_trend["week_number"], weekly_trend["correction_rate_pct"],
             color="#E94560", linewidth=2)
axes[1].set_ylabel("Correction Rate (%)")
axes[1].set_title("Weekly Correction Rate (%)")

axes[2].fill_between(weekly_trend["week_number"], weekly_trend["delivery_success_rate"],
                     alpha=0.3, color="#2ECC71")
axes[2].plot(weekly_trend["week_number"], weekly_trend["delivery_success_rate"],
             color="#2ECC71", linewidth=2)
axes[2].set_ylabel("Delivery Success (%)")
axes[2].set_title("Weekly Delivery Success Rate (%)")
axes[2].set_xlabel("Week Number")

for ax in axes:
    ax.grid(axis="y", alpha=0.5)

plt.tight_layout()
plt.savefig("charts/04_weekly_trends.png", dpi=150, bbox_inches="tight")
plt.close()
print("       Saved: charts/04_weekly_trends.png")

# ── Chart 5: Zone Comparison Bar Chart ──────────────────────────────────────
fig, axes = plt.subplots(1, 3, figsize=(18, 6))
fig.suptitle("Delivery Zone Performance Comparison", fontsize=15, fontweight="bold")

metrics = [
    ("correction_rate_pct",    "Correction Rate (%)",    "#E94560"),
    ("avg_accuracy",           "Avg Accuracy Score",     "#3498DB"),
    ("delivery_success_rate",  "Delivery Success (%)",   "#2ECC71"),
]
for ax, (col, label, color) in zip(axes, metrics):
    bars = ax.bar(zone_summary["delivery_zone"], zone_summary[col], color=color,
                  edgecolor="white", linewidth=0.8, alpha=0.85)
    ax.set_title(label)
    ax.set_xlabel("Zone")
    ax.set_ylabel(label)
    for bar, val in zip(bars, zone_summary[col]):
        ax.text(bar.get_x() + bar.get_width()/2, bar.get_height() + 0.3,
                f"{val:.1f}", ha="center", va="bottom", fontsize=10, fontweight="bold")

plt.tight_layout()
plt.savefig("charts/05_zone_comparison.png", dpi=150, bbox_inches="tight")
plt.close()
print("       Saved: charts/05_zone_comparison.png")

# ── Chart 6: Hotspot Analysis ─────────────────────────────────────────────────
top_hotspots = hotspot.head(15)
fig, ax = plt.subplots(figsize=(16, 7))
colors = ["#E94560" if is_hot else "#3498DB" for is_hot in top_hotspots["is_hotspot"]]
labels = top_hotspots["city"] + " / " + top_hotspots["delivery_zone"]
bars = ax.barh(labels, top_hotspots["hotspot_score"], color=colors, edgecolor="white")
ax.set_xlabel("Hotspot Score (composite)")
ax.set_title("Top 15 Delivery Hotspot City-Zone Combinations", fontsize=14, fontweight="bold")
hot_patch  = mpatches.Patch(color="#E94560", label="Hotspot (top 25%)")
norm_patch = mpatches.Patch(color="#3498DB", label="Normal")
ax.legend(handles=[hot_patch, norm_patch])
for bar, val in zip(bars, top_hotspots["hotspot_score"]):
    ax.text(bar.get_width() + 0.2, bar.get_y() + bar.get_height()/2,
            f"{val:.1f}", va="center", fontsize=9)
plt.tight_layout()
plt.savefig("charts/06_hotspot_analysis.png", dpi=150, bbox_inches="tight")
plt.close()
print("       Saved: charts/06_hotspot_analysis.png")

# ── Chart 7: Accuracy Score Distribution ─────────────────────────────────────
fig, axes = plt.subplots(1, 2, figsize=(16, 6))
fig.suptitle("Address Accuracy Score Distribution", fontsize=14, fontweight="bold")

axes[0].hist(df["address_accuracy_score"], bins=40, color="#3498DB",
             edgecolor="white", alpha=0.85)
axes[0].axvline(df["address_accuracy_score"].mean(), color="#E94560", linewidth=2,
                linestyle="--", label=f"Mean: {avg_accuracy:.1f}")
axes[0].set_xlabel("Accuracy Score")
axes[0].set_ylabel("Frequency")
axes[0].set_title("Distribution of Accuracy Scores")
axes[0].legend()

band_counts = df["accuracy_band"].value_counts().sort_index()
band_colors = ["#E94560", "#E67E22", "#F5A623", "#2ECC71", "#1ABC9C"]
axes[1].bar(band_counts.index.astype(str), band_counts.values,
            color=band_colors, edgecolor="white")
axes[1].set_xlabel("Accuracy Band")
axes[1].set_ylabel("Number of Records")
axes[1].set_title("Records by Accuracy Band")
axes[1].tick_params(axis="x", rotation=15)

plt.tight_layout()
plt.savefig("charts/07_accuracy_distribution.png", dpi=150, bbox_inches="tight")
plt.close()
print("       Saved: charts/07_accuracy_distribution.png")

# ── Chart 8: Correction Source Effectiveness ─────────────────────────────────
fig, axes = plt.subplots(1, 2, figsize=(14, 6))
fig.suptitle("Correction Source Effectiveness", fontsize=14, fontweight="bold")

source_order = source_eff.sort_values("delivery_success_rate", ascending=False)
bar_colors   = [PALETTE[i % len(PALETTE)] for i in range(len(source_order))]

axes[0].bar(source_order["correction_source"], source_order["delivery_success_rate"],
            color=bar_colors, edgecolor="white")
axes[0].set_title("Delivery Success Rate by Correction Source")
axes[0].set_ylabel("Delivery Success Rate (%)")
axes[0].tick_params(axis="x", rotation=20)
for i, (_, row) in enumerate(source_order.iterrows()):
    axes[0].text(i, row["delivery_success_rate"] + 0.2,
                 f"{row['delivery_success_rate']:.1f}%", ha="center", fontsize=9)

axes[1].bar(source_order["correction_source"], source_order["avg_score"],
            color=bar_colors, edgecolor="white")
axes[1].set_title("Avg Accuracy Score by Correction Source")
axes[1].set_ylabel("Average Accuracy Score")
axes[1].tick_params(axis="x", rotation=20)

plt.tight_layout()
plt.savefig("charts/08_source_effectiveness.png", dpi=150, bbox_inches="tight")
plt.close()
print("       Saved: charts/08_source_effectiveness.png")

# ── Chart 9: City-level Pincode Mismatch ─────────────────────────────────────
fig, ax = plt.subplots(figsize=(16, 7))
top_mismatch = mismatch_by_city.head(15)
bar_colors = [PALETTE[i % len(PALETTE)] for i in range(len(top_mismatch))]
bars = ax.bar(top_mismatch["city"], top_mismatch["mismatch_count"],
              color=bar_colors, edgecolor="white")
ax.set_title("Top Cities by Pincode Mismatch Count", fontsize=14, fontweight="bold")
ax.set_xlabel("City")
ax.set_ylabel("Mismatch Count")
ax.tick_params(axis="x", rotation=30)
for bar, val in zip(bars, top_mismatch["mismatch_count"]):
    ax.text(bar.get_x() + bar.get_width()/2, bar.get_height() + 1,
            str(val), ha="center", va="bottom", fontsize=9)
plt.tight_layout()
plt.savefig("charts/09_pincode_mismatch_by_city.png", dpi=150, bbox_inches="tight")
plt.close()
print("       Saved: charts/09_pincode_mismatch_by_city.png")

# ── Chart 10: Monthly Accuracy Trend ─────────────────────────────────────────
monthly = (
    df.groupby("correction_month")
    .agg(
        avg_accuracy=("address_accuracy_score", "mean"),
        correction_rate=("correction_required", "mean"),
        delivery_success=("delivery_success", "mean"),
    )
    .reset_index()
    .sort_values("correction_month")
)

fig, ax1 = plt.subplots(figsize=(16, 6))
ax2 = ax1.twinx()

line1, = ax1.plot(monthly["correction_month"], monthly["avg_accuracy"],
                  marker="o", color="#3498DB", linewidth=2.5, label="Avg Accuracy Score")
ax1.fill_between(monthly.index, monthly["avg_accuracy"], alpha=0.15, color="#3498DB")
ax1.set_ylabel("Avg Accuracy Score", color="#3498DB")
ax1.set_ylim(0, 100)

line2, = ax2.plot(monthly["correction_month"], monthly["correction_rate"] * 100,
                  marker="s", color="#E94560", linewidth=2.5, linestyle="--", label="Correction Rate %")
ax2.set_ylabel("Correction Rate (%)", color="#E94560")

ax1.set_title("Monthly Accuracy Score vs Correction Rate Trend", fontsize=14, fontweight="bold")
ax1.tick_params(axis="x", rotation=45)
lines = [line1, line2]
ax1.legend(lines, [l.get_label() for l in lines], loc="upper left")

plt.tight_layout()
plt.savefig("charts/10_monthly_trend.png", dpi=150, bbox_inches="tight")
plt.close()
print("       Saved: charts/10_monthly_trend.png")

# ─────────────────────────────────────────────
# WEEKLY SUMMARY REPORT
# ─────────────────────────────────────────────
print("\n[+] Generating weekly summary report …")

weekly_report_lines = ["ADDRESS ACCURACY & DELIVERY INSIGHTS — WEEKLY ANALYTICAL SUMMARY", "=" * 65, ""]

for _, row in weekly_trend.iterrows():
    week = int(row["week_number"])
    weekly_report_lines.append(f"Week {week:02d}")
    weekly_report_lines.append(f"  Total Orders         : {int(row['total_orders']):,}")
    weekly_report_lines.append(f"  Corrections Needed   : {int(row['corrections']):,}  ({row['correction_rate_pct']:.1f}%)")
    weekly_report_lines.append(f"  Pincode Mismatches   : {int(row['pincode_mismatches']):,}")
    weekly_report_lines.append(f"  Avg Accuracy Score   : {row['avg_accuracy']:.2f}")
    weekly_report_lines.append(f"  Delivery Success Rate: {row['delivery_success_rate']:.1f}%")
    weekly_report_lines.append("")

with open("exports/weekly_summary_report.txt", "w") as f:
    f.write("\n".join(weekly_report_lines))
print("       Exported → exports/weekly_summary_report.txt")

# ─────────────────────────────────────────────
# FINAL SUMMARY
# ─────────────────────────────────────────────
print("\n" + "=" * 65)
print("  ANALYSIS COMPLETE")
print("=" * 65)
print(f"  Records analysed   : {total:,}")
print(f"  Exports generated  : 5  (exports/ folder)")
print(f"  Charts generated   : 10 (charts/ folder)")
print(f"  Avg Accuracy Score : {avg_accuracy:.2f}")
print(f"  Overall Corr. Rate : {corrections/total*100:.1f}%")
print(f"  Delivery Success   : {deliveries_ok/total*100:.1f}%")
print("=" * 65)
