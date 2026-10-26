{{ config(
    post_hook=[
        "{{ rpt_004_1_merge_tax(this) }}",
        "{{ rpt_004_2_merge_eat(this) }}"
    ]
) }}

/*
 * dbt port of "004- Recalculate tax in RPT".
 * The table is copied from the previous step, then the original SQL statements
 * run on it in the original order (see macros/rpt/).
 */

SELECT * FROM {{ ref('rpt_ucetni_denik_003') }}
