{{ config(
    post_hook=[
        "{{ rpt_006_update_last_diff_pch(this) }}"
    ]
) }}

/*
 * dbt port of "006-populate RPT last,diff and percentage changes".
 * The table is copied from the previous step, then the original SQL statements
 * run on it in the original order (see macros/rpt/).
 */

SELECT * FROM {{ ref('rpt_ucetni_denik_005') }}
