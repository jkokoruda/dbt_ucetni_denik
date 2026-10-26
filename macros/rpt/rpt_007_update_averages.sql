{#- Ported 1:1 from Snowflake transformation "007-populate RPT with averages". Runs as a post-hook on the step's model; tgt = that model. -#}
{% macro rpt_007_update_averages(tgt) %}
UPDATE {{ tgt }} target
SET
    SUM_AVG3M  = src.SUM_AVG3M,
    SUM_AVG6M  = src.SUM_AVG6M,
    SUM_AVG12M = src.SUM_AVG12M
FROM (
    SELECT
        METRIC_CODE,
        PERIOD,
        STREDISKO,
        ZAKAZKA,
        CINNOST,

        CASE WHEN COUNT(SUM_PM) OVER (
                 PARTITION BY METRIC_CODE, STREDISKO, ZAKAZKA, CINNOST
                 ORDER BY PERIOD
                 ROWS BETWEEN 3 PRECEDING AND 1 PRECEDING
             ) = 3
             THEN AVG(SUM_PM) OVER (
                 PARTITION BY METRIC_CODE, STREDISKO, ZAKAZKA, CINNOST
                 ORDER BY PERIOD
                 ROWS BETWEEN 3 PRECEDING AND 1 PRECEDING
             )
        END AS SUM_AVG3M,

        CASE WHEN COUNT(SUM_PM) OVER (
                 PARTITION BY METRIC_CODE, STREDISKO, ZAKAZKA, CINNOST
                 ORDER BY PERIOD
                 ROWS BETWEEN 6 PRECEDING AND 1 PRECEDING
             ) = 6
             THEN AVG(SUM_PM) OVER (
                 PARTITION BY METRIC_CODE, STREDISKO, ZAKAZKA, CINNOST
                 ORDER BY PERIOD
                 ROWS BETWEEN 6 PRECEDING AND 1 PRECEDING
             )
        END AS SUM_AVG6M,

        CASE WHEN COUNT(SUM_PM) OVER (
                 PARTITION BY METRIC_CODE, STREDISKO, ZAKAZKA, CINNOST
                 ORDER BY PERIOD
                 ROWS BETWEEN 12 PRECEDING AND 1 PRECEDING
             ) = 12
             THEN AVG(SUM_PM) OVER (
                 PARTITION BY METRIC_CODE, STREDISKO, ZAKAZKA, CINNOST
                 ORDER BY PERIOD
                 ROWS BETWEEN 12 PRECEDING AND 1 PRECEDING
             )
        END AS SUM_AVG12M

    FROM {{ tgt }}
) src
WHERE target.METRIC_CODE IS NOT DISTINCT FROM src.METRIC_CODE
  AND target.STREDISKO   IS NOT DISTINCT FROM src.STREDISKO
  AND target.ZAKAZKA     IS NOT DISTINCT FROM src.ZAKAZKA
  AND target.CINNOST     IS NOT DISTINCT FROM src.CINNOST
  AND target.PERIOD = src.PERIOD
{% endmacro %}
