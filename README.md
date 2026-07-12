# Mobility & Billboard Exposure Analysis
### Full Analysis Documentation — Stickearn Technical Assessment

**Author:** Nafidza Shadrina Diva Aulia
**Position Applied:** Data Analyst (Campaign Analyst)

---

## 1. Business Understanding

### 1.1 Business Background

Stickearn is an Out-of-Home (OOH) advertising agency operating in Indonesia, providing billboard media space for brand campaigns. Unlike digital advertising — which offers precise, verifiable impression and click tracking — OOH advertising has traditionally relied on manual traffic estimation or generic footfall assumptions to justify billboard value. This creates a measurement gap: clients pay for billboard space based on rough estimates, not verified audience exposure.

This project simulates a data-driven audience measurement framework, using anonymized mobility data (GPS location logs) as a proxy for physical presence near billboard locations. The objective is to bring OOH measurement closer to the accountability standards seen in digital advertising — quantifying exposure, reach, and frequency in ways that support concrete commercial decisions.

### 1.2 Business Problem

Without granular, data-driven visibility into actual audience exposure, Stickearn faces three commercial challenges:
- **Pricing:** Difficulty objectively justifying premium rates for high-performing billboard locations.
- **Targeting:** Limited ability to advise clients on optimal campaign timing and billboard selection based on audience behavior.
- **Expansion:** No systematic, data-backed method to identify high-potential locations for new billboard placement.

### 1.3 Project Objective

Following the assignment brief, this analysis preprocesses and analyzes anonymized mobility data to generate meaningful insights about **billboard audience exposure and movement behavior in Jakarta** — specifically estimating impressions, reach, and frequency across 100 billboard locations. These exposure metrics are the core analytical output requested. As a natural extension of how OOH media performance insights are used in practice, the findings are further translated into three commercial applications — **pricing, campaign targeting, and expansion planning** — to demonstrate practical business applicability, consistent with the assignment's emphasis on analytical reasoning and scalability.

### 1.4 Audience Journey — Conceptual Framework

To ground the metrics used throughout this analysis in business logic, exposure measurement follows this conceptual funnel:

```
Device Movement (GPS log)
        ↓
Proximity to Billboard (within defined radius)
        ↓
Impression (1 detected proximity event = 1 opportunity-to-see)
        ↓
Reach (unique devices exposed)
        ↓
Frequency (repeat exposure per device = Impressions ÷ Reach)
        ↓
Business Decision (Pricing / Targeting / Expansion)
```

A device's GPS point falling within a billboard's proximity radius is treated as an "opportunity-to-see" (OTS) — a standard industry proxy for exposure, not a confirmed visual interaction. This distinction is discussed further in Section 12 (Limitations).

**Input Gambar: Audience Journey funnel diagram (6-stage visual funnel)**

---

## 2. Datasets

| Dataset | Description | Volume |
|---|---|---|
| Mobility Data | Anonymized device location logs (id, datetime, latitude, longitude, device_os) | 1,000,000 rows (raw) |
| Billboard Data | Physical billboard site coordinates (uuid, name, latitude, longitude) | 100 rows |

**Tools used:** Google BigQuery (SQL, BigQuery GIS), Python (Google Colab — pandas, matplotlib, plotly)

---

## 3. Stage 0–1 — Data Understanding, Cleaning & Jakarta Spatial Filter

### 3.1 Billboard Data

**Schema:** uuid (STRING), name (STRING), latitude (FLOAT64), longitude (FLOAT64) — 100 rows.

**Data quality check:** No missing values, no duplicate rows, no duplicate uuids, all coordinates within valid range. The dataset was already fully clean, requiring no cleaning treatment.

**Spatial validation:** A subset of billboard names referenced areas outside DKI Jakarta's administrative boundary (e.g., "Bekasi," "Tangerang"). Cross-checking against the official DKI Jakarta bounding box (latitude -6.3983 to -5.32, longitude 106.3783 to 106.9717 — converted from official DMS coordinates) confirmed all 100 billboards fall within this boundary. This revealed that **address-level area names are not reliable indicators of actual administrative location** — they reflect colloquial/postal naming conventions, not precise geography. All 100 billboards were retained.

> *Insight & Why It Matters: This finding shaped the Jakarta-filtering methodology for the mobility dataset — coordinate-based bounding box filtering was used as the single source of truth, rather than relying on any text-based location field.*

### 3.2 Mobility Data

**Schema:** id (STRING), latitude (FLOAT64), longitude (FLOAT64), datetime (TIMESTAMP), device_os (STRING) — 1,000,000 rows.

**Row count validation:** CSV source and BigQuery table row counts matched exactly (1,000,000 = 1,000,000), confirming no data loss during ingestion.

**Missing values:** None found across all columns.

**Duplicate handling:**
- *Exact duplicates* (identical id + datetime + latitude + longitude): 3,365 groups found → deduplicated to one row per group.
- *Partial duplicates* (same id + datetime, differing coordinates): 5,313 groups found. Magnitude analysis of coordinate variance showed 5,300 groups (99.75%) had small differences consistent with GPS jitter (tens of meters) → resolved via coordinate averaging. A further 8 groups showed medium variance → also averaged. The remaining **5 groups showed large, physically implausible coordinate discrepancies**, with 4 of the 5 sharing a suspiciously recurring coordinate value (~-6.2114, ~106.844) across different device IDs and times — indicating a likely default/fallback GPS coordinate rather than genuine location noise. These 5 groups were excluded from the dataset.

**Coordinate range validation:** 100% of records fell within the official Jakarta bounding box — no additional spatial filtering was required at this stage.

**device_os validation:** Only two clean categories found (Android: 730,595; iOS: 269,405), no typos or case inconsistencies.

**Datetime validation:** The `datetime` column was already typed as native TIMESTAMP (not STRING), meaning BigQuery had already parsed and standardized the format during ingestion — no additional format-cleaning was required. However, the dataset was found to span only a **single day (January 5, 2024)**, meaning daily/weekly temporal analysis is not possible; all subsequent temporal analysis is hourly only.

> *Insight & Why It Matters: This single-day limitation is treated as a dataset constraint (noted for future scaling — see Section 11), not a data quality flaw. All subsequent time-pattern findings should be interpreted as an hourly snapshot, not validated across multiple days.*

**Outlier detection — implied travel speed:** Beyond structural data quality checks, a movement-plausibility check was applied to sequential points per device (only relevant for devices with more than one record; average was 1.72 records/device). Implied speed was calculated using `ST_DISTANCE` and time deltas between consecutive points. A threshold of **110 km/h** was selected — grounded in Indonesian toll road speed regulations (100-120 km/h under PP 79/2013) with a small buffer for GPS/timestamp rounding tolerance. Sensitivity testing across 100, 110, and 150 km/h thresholds showed minimal difference in flagged transitions (1,302 vs. 1,187 vs. 886 out of 413,477 total transitions), confirming the analysis is not sensitive to the exact threshold chosen within a reasonable range. **1,187 transitions (0.29%)** exceeded 110 km/h and were excluded — specifically the destination point of each anomalous jump, preserving the remainder of each device's valid history.

<img width="989" height="490" alt="image" src="https://github.com/user-attachments/assets/66d76259-b049-416e-809e-2432e299fe28" />

<img width="989" height="490" alt="image" src="https://github.com/user-attachments/assets/21179c11-f35a-4180-93b4-6f3ec7b26ec7" />

> **Note on chronology:** Stage 2's exploratory charts (hourly distribution, density heatmap) were generated using the pre-exclusion dataset (`master_mobility`, before the 1,187-row speed-anomaly exclusion), while Stage 3 onward use the finalized dataset (`master_mobility_final`, 993,460 rows). Cross-validation confirmed the top-density grid values are identical in both datasets, confirming this sequencing had no material impact on findings, given the excluded volume represents just 0.12% of total data.

---

## 4. Stage 2 — Mobility Behavior EDA

### 4.1 Hourly Activity Distribution

<img width="1390" height="590" alt="image" src="https://github.com/user-attachments/assets/9f0d3eca-6c07-435f-9a9a-c247ad968f60" />

<img width="1389" height="590" alt="image" src="https://github.com/user-attachments/assets/021217f5-a571-4640-ab46-bed074b7938e" />

**Finding:** Peak activity occurs at **3:00 AM** (69,337 records, ~56,799 unique devices); lowest activity at **8:00 PM** (13,186 records). Android/iOS proportions remain stable (~73%/27%) throughout the day.

**Insight:** This pattern does not match the typical assumption of commuter-driven urban mobility (which usually peaks around 7-9 AM and 5-7 PM). Instead, the highest intensity occurs outside standard working hours.

**Why It Matters:** This is flagged as a key assumption/limitation for the presentation — the cause could be sample characteristics of the specific device panel represented in this dataset, rather than a universal population pattern. Cross-validation with additional mobility data sources or multi-day data is recommended before using this pattern as the sole basis for ad-scheduling decisions.

### 4.2 Grid-Based Density Heatmap

<img width="727" height="552" alt="Screenshot 2026-07-12 164909" src="https://github.com/user-attachments/assets/5e4392e2-973a-465c-8596-52a2e8079957" />

**Methodology:** Mobility points aggregated into ~100m × 100m grid cells (coordinates rounded to 3 decimal places), summarizing point count and unique device count per grid.

**Finding:** Two dominant hotspots emerged, each exceeding 37,000 points (grid centers approximately at -6.174/106.829 and -6.211/106.845), with a steep drop-off afterward (third-ranked grid at 8,523 points) — indicating a highly skewed distribution rather than evenly spread density.

**Insight:** These two hotspots likely represent central business district / dense commercial zones.

**Why It Matters:** These hotspots became central reference points for the opportunity gap analysis in Stage 5 — both persisted as top-ranked opportunity zones, confirming consistency of findings across analysis stages.

### 4.3 Outlier Detection — Two Distinct Categories

**a. Record count per device:** Distribution ranged from 1 to 74 records/device (median = 1, P95 = 4, P99 = 6). **Decision: not excluded.** A high record count reflects a highly mobile device (e.g., delivery courier, field sales) — a valid behavioral pattern, not an error. Treating record count alone as an anomaly risks removing legitimate data.

**b. Implied travel speed (see Section 3.2):** This is the metric used for actual exclusion, applied only to specific anomalous transitions rather than entire device histories.

***Insight & Why It Matters:** Separating these two outlier types was a deliberate methodological choice — conflating "highly mobile" with "erroneous" would have discarded valid high-frequency movement data.*

---

## 5. Stage 3 — Exposure Estimation & Billboard Ranking

### 5.1 Methodology

**Proximity radius:** The brief recommended a 50-100m range. **100m was selected as the primary/default radius**, supported by external research on effective billboard visibility distance for standard Indonesian arterial roads (100-200m for drivers to read clearly). **50m was used as a sensitivity check** for robustness validation.

**Query optimization:** Given the volume (993,460 mobility points × 100 billboards), a bounding-box pre-filter (±0.002°, ~220m buffer) was applied before precise `ST_DISTANCE` calculation, substantially reducing computational cost versus a naive cross join.

**Metric definitions:**
- **Impressions:** Each mobility point falling within the radius counts as one impression, with **no temporal deduplication** — consistent with standard OOH industry convention for opportunity-to-see measurement. This is a deliberate assumption, discussed further in Section 12.
- **Reach:** `COUNT(DISTINCT device_id)` within the radius.
- **Frequency:** Impressions ÷ Reach.

### 5.2 Sensitivity Check: 50m vs. 100m

| Radius | Total Impressions | Total Unique Devices | Billboards with Exposure |
|---|---|---|---|
| 50m | 1,539 | 1,156 | 100 / 100 |
| 100m | 4,733 | 3,134 | 100 / 100 |

**Insight:** All 100 billboards registered at least some exposure at both radii — no billboard showed zero mobility activity nearby. The relatively low absolute totals (compared to ~993,460 total mobility points) are expected: 100 billboards at a 100m radius cover only ~0.47% of Jakarta's ~662 km² total area, so only a small fraction of city-wide mobility falls within proximity of the analyzed billboards.

### 5.3 Exposure Table Per Billboard

<img width="685" height="436" alt="Screenshot 2026-07-13 012320" src="https://github.com/user-attachments/assets/9a0d7674-0592-4996-98c2-1ed086a93ddd" />

This aggregated table — one row per billboard — is the primary exposure deliverable requested by the brief: total impressions, reach, and frequency computed per site, at both 50m and 100m radii. The full 100-row table is available in the linked spreadsheet.

### 5.4 Top 10 Billboard Ranking (Radius 100m, Default)

**By Impressions:**

| Rank | Billboard | Impressions |
|---|---|---|
| 1 | Jl. R.A. Kartini No.5 | 105 |
| 2 | Jl. Wahid Hasyim No.171 - Jakarta Barat | 100 |
| 3 | Jl. Nasional 1 C - Jakarta Barat | 100 |
| 4 | Jl. Yos Sudarso 221 | 99 |
| 5 | Jl. Tj. Wangi II No.4 | 97 |
| 6 | Sbr. RS Siloam Kb. Jeruk - Jakarta Barat | 96 |
| 7 | Jl. Dewi Sartika  - Tangerang | 84 |
| 8 | Jl. Raya Jatiwaringin No.Rt 02 - Bekasi | 83 |
| 9 | Gg. Mesjid Taman Anggrek No.30 | 83 |
| 10 | Jl. Nasional 1 R | 81 |

**By Reach:**

| Rank | Billboard | Reach |
|---|---|---|
| 1 | Jl. R.A. Kartini No.5 | 94 |
| 2 | Jl. Wahid Hasyim No.171 - Jakarta Barat | 90 |
| 3 | Jl. Nasional 1 C - Jakarta Barat | 90 |
| 4 | Sbr. RS Siloam Kb. Jeruk - Jakarta Barat | 84 |
| 5 | Jl. Yos Sudarso 221 | 84 |
| 6 | Jl. Nasional 1 R | 77 |
| 7 | Gg. Mesjid Taman Anggrek No.30 | 76 |
| 8 | Jl. Arjuna Sel. No.11 | 73 |
| 9 | Jl. Tj. Wangi II No.4 | 71 |
| 10 | Jl. Raya Jatiwaringin No.Rt 02 - Bekasi | 69 |

**By Frequency (Reach-Filtered, threshold ≥ 37, the median reach across all billboards):**

| Rank | Billboard | Frequency |
|---|---|---|
| 1 | Jl. Dewi Sartika - Tangerang | 1.53 |
| 2 | Jl. Raya Hankam No.28 - Bekasi | 1.47 |
| 3 | Jl. Sosial No.1G - Bekasi | 1.47 |
| 4 | Jl. Raya Jati Makmur No.53 - Bekasi | 1.37 |
| 5 | Jl. Tj. Wangi II No.4 | 1.37 |
| 6 | Jl. Nasional 1 AE - Jakarta Utara | 1.35 |
| 7 | Jl. H. Tang No.22 | 1.29 |
| 8 | Jl. Ir H. Juanda No.40A Tangerang Selatan | 1.27 |
| 9 | Jl. Dewi Sartika Blok A2 No.17 | 1.25 |
| 10 | Jl. Raya Jatiwaringin - Bekasi | 1.23 |

<img width="889" height="590" alt="image" src="https://github.com/user-attachments/assets/f1d9374b-3b73-4acc-8f37-8d72ad127fa4" />
<img width="889" height="590" alt="image" src="https://github.com/user-attachments/assets/76fef915-7897-4344-9a2d-8ce1fdfe86b9" />
<img width="890" height="590" alt="image" src="https://github.com/user-attachments/assets/78b61e74-5494-4b77-bd75-ae58358173a2" />

> *Why a reach threshold for frequency ranking? Ranking by frequency without a minimum reach filter is statistically unreliable — a billboard with very low reach (e.g., reach of 23) can produce an extreme frequency ratio purely due to small sample size, which is not comparable in business terms to a billboard with substantially higher reach. Filtering to reach ≥ 37 (the actual median, not an arbitrary cutoff) ensures the frequency comparison reflects a meaningful sample size.*

**Cross-radius note:** `Jl. R.A. Kartini No.5` ranks #1 at the 100m radius (both impressions and reach), but does **not** appear in the 50m top-10 impressions ranking — instead, `Jl. Wibawa Mukti II No.29` leads at 50m. This suggests R.A. Kartini captures traffic passing somewhat further from the exact billboard point (within 50-100m), while Wibawa Mukti II captures traffic immediately adjacent to the site — two distinct spatial exposure profiles rather than a single "best overall" billboard.

`Jl. Tj. Wangi II No.4` appears consistently across all three rankings (impressions, reach, and frequency) — a strong candidate for the "Premium" classification below.

### 5.5 Billboard Classification — Reach vs. Frequency

<img width="989" height="690" alt="image" src="https://github.com/user-attachments/assets/e888ea62-bf73-4ef8-9e27-b87ce59df99e" />
<img width="989" height="690" alt="image" src="https://github.com/user-attachments/assets/a5b18078-6953-44f7-84ef-70bfa1735bb3" />

Each billboard was plotted on a reach (x-axis) vs. frequency (y-axis) scatter, divided into four quadrants using median thresholds:

- **Premium** (High Reach, High Frequency) — top pricing tier candidates
- **Awareness Type** (High Reach, Low Frequency) — suited for brand-reach campaigns
- **Recall Type** (Low Reach, High Frequency) — suited for repetition/reminder campaigns
- **Underperforming** (Low Reach, Low Frequency) — candidates for further review

> *Note: A composite scoring approach (RFM-style) was considered but not used — for a scale of 100 billboards, quadrant classification retains more strategic nuance (why a billboard performs well) than a single composite score would.*

**Classification results:**

| Category | Radius 50m | Radius 100m |
|---|---|---|
| Premium | 25 | 23 |
| Awareness Type | 27 | 27 |
| Recall Type | 26 | 27 |
| Underperforming | 22 | 23 |

**Insight:** Category distribution is nearly identical between 50m and 100m radii — confirming classification results are **not sensitive to the choice of radius** within the brief's recommended range, strengthening the reliability of subsequent business recommendations.

**Why It Matters (Business Recommendation):**
- **Premium** (~23-25 billboards) → priority candidates for premium pricing.
- **Awareness Type** (~27 billboards) → best offered to clients with brand-awareness objectives.
- **Recall Type** (~26-27 billboards) → best suited for repetition/reminder-based campaigns.
- **Underperforming** (~22-23 billboards) → requires further investigation rather than automatic delisting (see Stage 4 for a nuanced finding on this category).

---

## 6. Stage 4 — Exposure Time Pattern

### 6.1 Aggregate Hourly Exposure (All Billboards)

<img width="1389" height="490" alt="image" src="https://github.com/user-attachments/assets/acc6643e-bec0-408d-b301-9b8ff5d26ba0" />

**Finding:** Peak exposure occurs at **10:00-11:00 AM** (415 and 397 total impressions respectively); lowest at **8:00 PM** (28 impressions).

**Insight — Divergence from Stage 2:** This pattern **differs meaningfully** from the city-wide mobility pattern found in Stage 2 (which peaked at 2-3 AM). This is not a contradiction, but an indication that mobility filtered to billboard proximity (arterial/commercial locations) follows a different rhythm than Jakarta's overall device population, which likely includes substantial residential/non-commercial activity.

**Why It Matters:** This confirms current billboard placements are generally well-aligned with commercial peak hours, and identifies **10-11 AM as the optimal ad-flighting window** for campaigns targeting general audiences near billboard locations.

### 6.2 Hourly Exposure Pattern by Billboard Category

<img width="1388" height="690" alt="image" src="https://github.com/user-attachments/assets/3565228e-8be3-4d7b-9a47-6f8b79a281af" />

| Category | Peak Hour | Avg. Impressions |
|---|---|---|
| Premium | 10 AM | 5.41 |
| Awareness Type | 10 AM | 6.48 |
| Recall Type | 6 AM | 3.17 |
| Underperforming | 7 PM | 4.50 |

**Insight — Premium & Awareness Type:** Both peak at 10 AM, consistent with their shared "high reach" characteristic following the general commercial peak.

**Insight — Recall Type:** Peaks earlier, at 6 AM, consistent with a hypothesized morning commuter pattern. **Important caveat:** frequency (the metric defining this category) is calculated as an aggregate ratio across the full day, not measured within a single hour. The 6 AM peak reflects highest impression *volume* at that hour for this category — it does not, by itself, prove that the same devices are repeatedly passing within that specific hour. Validating the "repeat commuter" hypothesis with confidence would require multi-day data to confirm the same devices recur at the same location across different days.

> **Insight — Underperforming spike at 7 PM**
>
> Initial inspection suggested this spike was broadly distributed across the Underperforming category. Deeper verification — cross-checking category-level averages against individual contributing billboards — revealed two separate findings:
> 1. Among the unfiltered top-10 billboards by impressions at 7 PM (across all categories), the majority are located in the Bekasi corridor — indicating a geographic, cross-category evening commuter-return pattern, not one specific to the Underperforming category.
> 2. Within the Underperforming category specifically, only 4 of 23 billboards (17%) recorded any activity at 7 PM, with contributions fairly evenly split among them (no single billboard dominating). The remaining 19 billboards in this category show zero recorded impressions at this hour.
>
> **Verification detail — Underperforming billboards active at hour 19:**
>
> | Billboard | Impressions |
> |---|---|
> | Jl. Apel 1 Blok A1 No.10 - Bekasi | 6 |
> | Jl. Apel 1 Blok A1 No.10 A - Bekasi | 6 |
> | Jl. Raya Jatimekar No.36J - Bekasi | 5 |
> | Jl. Kamal Muara No.88 - Jakarta Utara | 1 |
>
> *4 of 23 Underperforming billboards (17%) show activity at hour 19; contribution is fairly even (not driven by a single outlier), but the category-level average of 4.50 does not represent a category-wide pattern. The evening spike is therefore better characterized as a location-specific phenomenon (Bekasi/North Jakarta corridor) rather than a defining trait of the Underperforming category as a whole.*

**Why It Matters (Business Recommendation — revised):** Rather than generalizing an evening-campaign strategy to the entire Underperforming category, this finding points to a **small, specific set of billboards** (primarily in the Bekasi/North Jakarta corridor) worth evaluating individually for evening/community-targeted campaigns. This nuance — visible only through hour-level and per-billboard verification, not category averages alone — underscores the importance of validating aggregate patterns against individual contributing data points before generalizing a recommendation.

### 6.3 Scope Decision: Per-Billboard Hourly Heatmap (Not Included)

A more granular hour × individual-billboard heatmap was considered but not built for this submission. Aggregate and category-level patterns (6.1 and 6.2) already address the core strategic questions (optimal timing per billboard type); a fully granular breakdown is better suited as a future operational dashboard tool rather than a strategic presentation deliverable (noted under Future Work, Section 11).

---

## 7. Stage 5 — Strategic Opportunity & Expansion Gap Analysis

### 7.1 Movement Heatmap Overlay: Density, Existing Billboards, & Opportunity Gaps

<img width="715" height="498" alt="Screenshot 2026-07-11 203354" src="https://github.com/user-attachments/assets/6f3f6209-a778-42ab-b53e-8d4b63d62d59" />

**Methodology:**
- Background layer: mobility density grid from Stage 2, limited to the top 1,500 highest-density grid cells (of 66,708 total) purely for map readability — displaying all 66,708 cells visually saturated the map and obscured base-map labels; grids with very low density do not meaningfully contribute to hotspot interpretation.
- Middle layer: 100 existing billboard locations.
- Highlight layer: top 30 opportunity gap zones — grid cells with high mobility density located **more than 500m** from the nearest existing billboard.

> *Note on "movement heatmap" interpretation: the brief's request for a "simple movement heatmap" is interpreted here as a density heatmap (not individual device trajectory mapping). This is because the average device in this dataset has only 1.72 records/day — insufficient sequential points to construct meaningful movement trajectories for the vast majority of devices.*

**Why 500m for gap definition?** This differs from the precise 50-100m exposure radius used in Stage 3. Here, the context is coverage feasibility for expansion decisions, not precise exposure measurement. The 500m threshold reflects three considerations: (1) it provides a reasonable buffer above the upper-bound effective billboard visibility distance on arterial roads (~250-300m, per external research); (2) it aligns with the standard "immediate catchment area" concept used in urban/retail site planning (~5-7 minutes walking distance); (3) a smaller radius (e.g., the same 100m used for exposure) would flag nearly all locations as "gaps," since billboards are rarely placed within 100m of each other — making the metric uninformative for expansion decisions.

**Finding:** The two dominant hotspots identified in Stage 2 (Section 4.2) reappear as the top two opportunity gap zones here — both located more than 4,700m from the nearest existing billboard, despite having point counts of 38,404 and 37,765 respectively. This cross-stage consistency reinforces confidence in both the density measurement and the gap identification methodology.

**Scale comparison:**

| | Reach / Unique Devices |
|---|---|
| Best-performing existing billboard (Jl. R.A. Kartini No.5) | 94 |
| Top opportunity gap zone (unique devices) | 24,310 |

The top opportunity gap zone shows roughly **258x more unique devices** than the best-performing existing billboard — indicating a substantial, currently untapped audience.

### 7.2 Gap Zone Categorization by Distance

The top 30 opportunity gap zones were further segmented by distance to the nearest billboard, to differentiate expansion strategy:

| Category | Distance to Nearest Billboard | Strategic Implication |
|---|---|---|
| Near-field | 500m – 1,500m | Faster, lower-risk expansion — surrounding area already familiar/served |
| Mid-range | 1,500m – 3,000m | Requires additional evaluation |
| Far-field | >3,000m | Larger potential audience, but likely an entirely unexplored market requiring deeper due diligence |

**Why It Matters (Business Recommendation):** Stickearn should prioritize ground-truth feasibility surveys at near-field opportunity zones first, as lower-risk, faster-to-execute expansion candidates, while treating far-field zones as longer-horizon strategic bets requiring additional market validation.

---

## 8. Executive Summary

### Key Findings

1. **Exposure measurement is sound, though coverage is inherently limited by radius.** 100 billboards at a 100m radius cover only ~0.47% of Jakarta's total area, explaining the relatively small absolute exposure totals relative to overall city mobility volume.
2. **Billboard performance splits into four distinct, robust strategic profiles** (Premium, Awareness Type, Recall Type, Underperforming), with classification proportions consistent across both 50m and 100m radius sensitivity checks.
3. **Billboard exposure timing diverges meaningfully from city-wide mobility patterns** — city mobility peaks at 2-3 AM, while billboard-proximate exposure peaks at 10-11 AM, indicating current placements are well-aligned with commercial activity.
4. **The largest untapped opportunity lies outside current billboard coverage** — high-density zones (up to 24,310 unique devices) exist more than 500m from any billboard, roughly 258x the reach of the best existing billboard.

### Business Recommendations

**Pricing:** Tiered pricing anchored to reach-frequency classification — Premium billboards justify top rates; Awareness/Recall types priced according to campaign-fit rather than a single volume metric; Underperforming billboards reviewed case-by-case rather than blanket-discounted.

**Targeting & Scheduling:** Ad flighting concentrated around the 10-11 AM commercial peak for general campaigns; Recall Type billboards aligned with the 6 AM commuter window; a small subset of specific billboards in the Bekasi/North Jakarta corridor — identified through per-billboard verification rather than category-wide generalization — show a legitimate 7 PM evening window suited to community/local-targeted campaigns, warranting individual evaluation rather than a blanket Underperforming-category strategy.

**Expansion:** Near-field opportunity zones (500m-1,500m from existing billboards) prioritized for feasibility surveys as low-risk, fast-to-execute candidates; far-field zones (>3,000m) treated as longer-horizon strategic bets pending further market validation.

---

## 9. Scaling to National Level

Extending this methodology beyond Jakarta requires:
1. **City-specific radius calibration** — Jakarta's density profile may not generalize to lower-density cities.
2. **Multi-day data collection** — this analysis was constrained to a single day, limiting temporal analysis to hourly granularity only; a production rollout should capture at least 1-2 weeks to distinguish weekday/weekend patterns.
3. **An automated pipeline** — manual, stage-by-stage query execution is feasible for a single-city pilot but requires orchestration (e.g., scheduled BigQuery jobs, dbt) for multi-city, ongoing measurement.
4. **Data source diversification** — reliance on a single mobility data source introduces coverage bias that a national rollout should mitigate by triangulating multiple providers.

---

## 10. Exit Criteria

| Initiative | Continue if | Adjust if | Stop if |
|---|---|---|---|
| Premium pricing rollout | Client acceptance at new rate | Partial pushback on price | Consistent rejection across clients |
| Near-field expansion | Feasibility survey confirms viability | Site access constraints found | Site physically unviable |
| Underperforming repositioning | Local campaign bookings increase | Flat bookings | No bookings after 2 cycles |

---

## 11. Future Work

- Per-billboard hourly heatmap (operational dashboard, not strategic deck material).
- Multi-day / multi-week data collection to validate hourly patterns across weekday/weekend cycles.
- Automated pipeline orchestration for multi-city rollout.

---

## 12. Limitations & Assumptions (Consolidated)

**Data Scope**
- Mobility data spans a single day (January 5, 2024) — all temporal analysis is hourly only; daily/weekly patterns cannot be assessed with this dataset.

**Data Cleaning Decisions**
- Duplicate resolution: exact duplicates deduplicated; closely-clustered coordinate duplicates (GPS jitter) resolved via averaging; 5 records with physically implausible coordinate discrepancies excluded.
- Implied-speed anomaly threshold set at 110 km/h (grounded in Indonesian toll road speed regulation), excluding 1,187 transitions (0.29% of total) — sensitivity-tested across 100/110/150 km/h with minimal variance in outcome.
- Stage 2 exploratory charts were generated prior to the speed-anomaly exclusion step; cross-validation against post-exclusion data confirmed no material difference in top-density findings (excluded volume = 0.12% of total data).

**Exposure Metrics as Proxy, Not Confirmed Interaction**
- Impressions, reach, and frequency represent an "opportunity-to-see" (OTS) proxy based on GPS proximity alone, not confirmed visual engagement with a billboard.
- Coverage bias: the method only captures devices with active GPS/location-sharing; individuals without smartphones or with location services disabled are invisible to this measurement, meaning actual reach is likely underestimated.
- The `id` field is assumed to represent an anonymized device identifier (e.g., hashed advertising ID), not an IP address — this is an assumption, not a fact confirmed by the brief.
- Multi-device/shared-device bias (one person, multiple devices, or vice versa) is a limitation common to all device-ID-based measurement.
- Impressions are counted without temporal deduplication — each qualifying GPS point counts as one impression, following standard OOH industry convention, though this is a deliberate methodological choice worth noting.

**Scope Boundaries**
- The initial hypothesis that the Underperforming category's 7 PM exposure spike was broadly distributed across the category was revised after per-billboard verification revealed it was driven by only 4 of 23 billboards (17%) within that category. This correction is documented as an example of the verification process applied throughout this analysis — aggregate/category-level patterns were checked against individual contributing data points before being generalized into recommendations.
- Granular per-billboard hourly heatmaps were not included in this submission — noted as a potential future enhancement for an operational dashboard tool, rather than a gap in the current strategic analysis.
- Composite scoring (RFM-style) was considered but not used for billboard classification — quadrant-based reach-frequency classification was judged more interpretable at this scale (100 billboards).

---

## 13. Repository Structure

```
stickearn-billboard-exposure-analysis/
├── README.md
├── docs/
│   ├── full_analysis_documentation.md   (this document)
│   └── images/                          (chart exports referenced above)
├── sql/
│   ├── 01_data_cleaning.sql
│   ├── 02_mobility_eda.sql
│   ├── 03_exposure_estimation.sql
│   └── 04_opportunity_gap.sql
└── stickearn_notebook.ipynb
```

*Spreadsheet: [[link]](https://drive.google.com/drive/folders/1VIoAX0xV0WJ6nh-8emYAeFx0wI1w9NU-?usp=sharing)*
*SQL: [Link](sql/)*
*Python: [Link](stickearn_notebook.ipynb)*
*Google Slides: [[link]](https://docs.google.com/presentation/d/1TcoTYtKHPS9VIBv5h1x4AlPgkgCMqzI6a9a7DypJLns/edit?usp=sharing)*
