{{ config(
    post_hook=[
        "{{ rpt_005_1_merge_bs_calc_cye(this) }}",
        "{{ rpt_005_2_merge_bs_rollup(this) }}"
    ]
) }}

/*
 * dbt port of "005-Populate RPT_UCETNI_DENIK (BS)".
 * The table is copied from the previous step, then the original SQL statements
 * run on it in the original order (see macros/rpt/).
 */

SELECT * FROM {{ ref('rpt_ucetni_denik_004') }}
