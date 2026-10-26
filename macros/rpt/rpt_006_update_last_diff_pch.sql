{#- Ported 1:1 from Snowflake transformation "006-populate RPT last,diff and percentage changes". Runs as a post-hook on the step's model; tgt = that model. -#}
{% macro rpt_006_update_last_diff_pch(tgt) %}
UPDATE {{ tgt }} target
SET
    SUM_LM    = src.SUM_LM,
    SUM_LQ    = src.SUM_LQ,
    SUM_LYTD  = src.SUM_LYTD,
    SUM_LYM   = src.SUM_LYM,
    DIFF_LM   = src.DIFF_LM,
    DIFF_LQ   = src.DIFF_LQ,
    DIFF_LYTD = src.DIFF_LYTD,
    DIFF_LYM  = src.DIFF_LYM,
    PCH_LM    = src.PCH_LM,
    PCH_LQ    = src.PCH_LQ,
    PCH_LYTD  = src.PCH_LYTD,
    PCH_LYM   = src.PCH_LYM
FROM (
    SELECT
        cur.METRIC_CODE,
        cur.PERIOD,
        cur.STREDISKO,
        cur.ZAKAZKA,
        cur.CINNOST,

        lm.SUM_PM  AS SUM_LM,
        lq.SUM_PQ  AS SUM_LQ,
        ly.SUM_YTD AS SUM_LYTD,
        ly.SUM_PM  AS SUM_LYM,

        cur.SUM_PM  - lm.SUM_PM  AS DIFF_LM,
        cur.SUM_PQ  - lq.SUM_PQ  AS DIFF_LQ,
        cur.SUM_YTD - ly.SUM_YTD AS DIFF_LYTD,
        cur.SUM_PM  - ly.SUM_PM  AS DIFF_LYM,

        (cur.SUM_PM - lm.SUM_PM) / NULLIF(ABS(lm.SUM_PM), 0) * 100 AS PCH_LM,
        (cur.SUM_PQ - lq.SUM_PQ) / NULLIF(ABS(lq.SUM_PQ), 0) * 100 AS PCH_LQ,
        (cur.SUM_YTD - ly.SUM_YTD) / NULLIF(ABS(ly.SUM_YTD), 0) * 100 AS PCH_LYTD,
        (cur.SUM_PM - ly.SUM_PM) / NULLIF(ABS(ly.SUM_PM), 0) * 100 AS PCH_LYM

    FROM {{ tgt }} cur

    LEFT JOIN {{ tgt }} lm
           ON lm.METRIC_CODE IS NOT DISTINCT FROM cur.METRIC_CODE
          AND lm.STREDISKO   IS NOT DISTINCT FROM cur.STREDISKO
          AND lm.ZAKAZKA     IS NOT DISTINCT FROM cur.ZAKAZKA
          AND lm.CINNOST     IS NOT DISTINCT FROM cur.CINNOST
          AND lm.PERIOD = DATEADD(month, -1, cur.PERIOD)

    LEFT JOIN {{ tgt }} lq
           ON lq.METRIC_CODE IS NOT DISTINCT FROM cur.METRIC_CODE
          AND lq.STREDISKO   IS NOT DISTINCT FROM cur.STREDISKO
          AND lq.ZAKAZKA     IS NOT DISTINCT FROM cur.ZAKAZKA
          AND lq.CINNOST     IS NOT DISTINCT FROM cur.CINNOST
          AND lq.PERIOD = DATEADD(quarter, -1, cur.PERIOD)

    LEFT JOIN {{ tgt }} ly
           ON ly.METRIC_CODE IS NOT DISTINCT FROM cur.METRIC_CODE
          AND ly.STREDISKO   IS NOT DISTINCT FROM cur.STREDISKO
          AND ly.ZAKAZKA     IS NOT DISTINCT FROM cur.ZAKAZKA
          AND ly.CINNOST     IS NOT DISTINCT FROM cur.CINNOST
          AND ly.PERIOD = DATEADD(year, -1, cur.PERIOD)
) src
WHERE target.METRIC_CODE IS NOT DISTINCT FROM src.METRIC_CODE
  AND target.STREDISKO   IS NOT DISTINCT FROM src.STREDISKO
  AND target.ZAKAZKA     IS NOT DISTINCT FROM src.ZAKAZKA
  AND target.CINNOST     IS NOT DISTINCT FROM src.CINNOST
  AND target.PERIOD = src.PERIOD
{% endmacro %}
