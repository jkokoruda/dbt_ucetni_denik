{{ config(
    alias='RPT_UCETNI_DENIK',
    post_hook=[
        "{{ rpt_007_update_averages(this) }}"
    ]
) }}

/*
 * dbt port of "007-populate RPT with averages".
 * The table is copied from the previous step, then the original SQL statements
 * run on it in the original order (see macros/rpt/).
 */

SELECT * FROM {{ ref('rpt_ucetni_denik_006') }}
