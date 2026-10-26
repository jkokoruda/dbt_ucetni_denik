{{ config(alias='STG_UCETNI_DENIK') }}

/*
 * dbt port of "001-Normalize ucetni-denik".
 * Normalizes the Abra Flexi accounting journal and splits every entry
 * into an MD (debit, negated amounts) row and a DAL (credit) row.
 */

WITH base AS (
    SELECT
        CAST("idUcetniDenik"           AS VARCHAR)                                            AS idUcetniDenik,

        TRY_TO_TIMESTAMP(SPLIT_PART(CAST("lastUpdate"  AS VARCHAR), '+', 1))                 AS lastUpdate,
        TRY_TO_DATE    (SPLIT_PART(CAST("datSplat"     AS VARCHAR), '+', 1))                 AS datSplat,
        TRY_TO_DATE    (SPLIT_PART(CAST("datUhr"       AS VARCHAR), '+', 1))                 AS datUhr,
        TRY_TO_DATE    (SPLIT_PART(CAST("datVyst"      AS VARCHAR), '+', 1))                 AS datVyst,
        TRY_TO_DATE    (SPLIT_PART(CAST("datUcto"      AS VARCHAR), '+', 1))                 AS datUcto,
        TRY_TO_DATE    (SPLIT_PART(CAST("duzpUcto"     AS VARCHAR), '+', 1))                 AS duzpUcto,

        CAST("updatedBy_ref"           AS VARCHAR)                                            AS updatedBy_ref,
        CAST("updatedBy_showAs"        AS VARCHAR)                                            AS updatedBy_showAs,
        CAST("clenDph_ref"             AS VARCHAR)                                            AS clenDph_ref,
        CAST("clenDph_showAs"          AS VARCHAR)                                            AS clenDph_showAs,
        CAST("doklad"                  AS VARCHAR)                                            AS doklad,
        CAST("postingPeriod"           AS VARCHAR)                                            AS postingPeriod,
        CAST("firma_ref"               AS VARCHAR)                                            AS firma_ref,
        CAST("firma_showAs"            AS VARCHAR)                                            AS firma_showAs,
        CAST("mena_ref"                AS VARCHAR)                                            AS mena_ref,
        CAST("mena_showAs"             AS VARCHAR)                                            AS mena_showAs,
        CAST("modulK_showAs"           AS VARCHAR)                                            AS modulK_showAs,
        CAST("nazFirmy"                AS VARCHAR)                                            AS nazFirmy,
        CAST("dic"                     AS VARCHAR)                                            AS dic,
        CAST("popis"                   AS VARCHAR)                                            AS popis,
        CAST("varSym"                  AS VARCHAR)                                            AS varSym,
        CAST("typSzbDphK_showAs"       AS VARCHAR)                                            AS typSzbDphK_showAs,
        CAST("stavUzivK_showAs"        AS VARCHAR)                                            AS stavUzivK_showAs,
        CAST("stredisko_ref"           AS VARCHAR)                                            AS stredisko_ref,
        CAST("stredisko_showAs"        AS VARCHAR)                                            AS stredisko_showAs,
        CAST("mdUcet_ref"              AS VARCHAR)                                            AS mdUcet_ref,
        CAST("mdUcet_showAs"           AS VARCHAR)                                            AS mdUcet_showAs,
        CAST("dalUcet_ref"             AS VARCHAR)                                            AS dalUcet_ref,
        CAST("dalUcet_showAs"          AS VARCHAR)                                            AS dalUcet_showAs,
        CAST("idDokl"                  AS VARCHAR)                                            AS idDokl,
        CAST("zakazka_ref"             AS VARCHAR)                                            AS zakazka_ref,
        CAST("zakazka_showAs"          AS VARCHAR)                                            AS zakazka_showAs,
        CAST("parSymbol"               AS VARCHAR)                                            AS parSymbol,
        CAST("cinnost_ref"             AS VARCHAR)                                            AS cinnost_ref,
        CAST("cinnost_showAs"          AS VARCHAR)                                            AS cinnost_showAs,
        CAST("idPolozek"               AS VARCHAR)                                            AS idPolozek,

        REGEXP_REPLACE(CAST("updatedBy"    AS VARCHAR), '^code:', '')                        AS updatedBy,
        REGEXP_REPLACE(CAST("clenDph"      AS VARCHAR), '^code:', '')                        AS clenDph,
        REGEXP_REPLACE(CAST("firma"        AS VARCHAR), '^code:', '')                        AS firma,
        REGEXP_REPLACE(CAST("mena"         AS VARCHAR), '^code:', '')                        AS mena,
        REGEXP_REPLACE(CAST("modul"        AS VARCHAR), '^code:', '')                        AS modul,
        REGEXP_REPLACE(CAST("modulK"       AS VARCHAR), '^code:', '')                        AS modulK,
        REGEXP_REPLACE(CAST("typSzbDphK"   AS VARCHAR), '^code:', '')                        AS typSzbDphK,
        REGEXP_REPLACE(CAST("stavUzivK"    AS VARCHAR), '^code:', '')                        AS stavUzivK,
        REGEXP_REPLACE(CAST("stredisko"    AS VARCHAR), '^code:', '')                        AS stredisko,
        REGEXP_REPLACE(CAST("mdUcet"       AS VARCHAR), '^code:', '')                        AS mdUcet,
        REGEXP_REPLACE(CAST("dalUcet"      AS VARCHAR), '^code:', '')                        AS dalUcet,
        REGEXP_REPLACE(CAST("zakazka"      AS VARCHAR), '^code:', '')                        AS zakazka,
        REGEXP_REPLACE(CAST("cinnost"      AS VARCHAR), '^code:', '')                        AS cinnost,

        TRY_TO_NUMBER(CAST("kurz"          AS VARCHAR), 18, 6)                               AS kurz,
        TRY_TO_NUMBER(CAST("kurzMnozstvi"  AS VARCHAR), 18, 6)                               AS kurzMnozstvi,
        TRY_TO_NUMBER(CAST("szbDph"        AS VARCHAR), 18, 6)                               AS szbDph,
        TRY_TO_NUMBER(CAST("sumTuz"        AS VARCHAR), 18, 2)                               AS sumTuz,
        TRY_TO_NUMBER(CAST("sumMen"        AS VARCHAR), 18, 2)                               AS sumMen,

        TRY_CAST(CAST("zuctovano"       AS VARCHAR) AS BOOLEAN)                              AS zuctovano,
        TRY_CAST(CAST("vatItem"         AS VARCHAR) AS BOOLEAN)                              AS vatItem,
        TRY_CAST(CAST("accountsSwapped" AS VARCHAR) AS BOOLEAN)                              AS accountsSwapped,
        TRY_CAST(CAST("bezPolozek"      AS VARCHAR) AS BOOLEAN)                              AS bezPolozek

    FROM {{ source('abra_flexi', 'UCETNI_DENIK') }}
),

{#- One row per side; MD side negates the amounts and swaps account/counter-account. -#}
{%- set sides = [
    {'name': 'MD',  'ucet': 'mdUcet',  'counter': 'dalUcet', 'sign': '-'},
    {'name': 'DAL', 'ucet': 'dalUcet', 'counter': 'mdUcet',  'sign': ''}
] %}

{% for s in sides %}
{{ s.name | lower }}_entries AS (
    SELECT
        CONCAT(idUcetniDenik, '_{{ s.name }}')  AS PK_UCETNI_DENIK,
        '{{ s.name }}'                          AS SOURCE,
        {{ s.ucet }}                            AS UCET,
        {{ s.ucet }}_showAs                     AS UCET_SHOW_AS,
        {{ s.counter }}                         AS COUNTER_ACCOUNT,
        idUcetniDenik                   AS ID_UCETNI_DENIK,
        lastUpdate                      AS LAST_UPDATE,
        updatedBy                       AS UPDATED_BY,
        updatedBy_ref                   AS UPDATED_BY_REF,
        updatedBy_showAs                AS UPDATED_BY_SHOW_AS,
        clenDph                         AS CLEN_DPH,
        clenDph_ref                     AS CLEN_DPH_REF,
        clenDph_showAs                  AS CLEN_DPH_SHOW_AS,
        datSplat                        AS DAT_SPLAT,
        datUhr                          AS DAT_UHR,
        datVyst                         AS DAT_VYST,
        datUcto                         AS DAT_UCTO,
        doklad                          AS DOKLAD,
        duzpUcto                        AS DUZP_UCTO,
        postingPeriod                   AS POSTING_PERIOD,
        firma                           AS FIRMA,
        firma_ref                       AS FIRMA_REF,
        firma_showAs                    AS FIRMA_SHOW_AS,
        kurz                            AS KURZ,
        kurzMnozstvi                    AS KURZ_MNOZSTVI,
        mena                            AS MENA,
        mena_ref                        AS MENA_REF,
        mena_showAs                     AS MENA_SHOW_AS,
        modul                           AS MODUL,
        modulK                          AS MODUL_K,
        modulK_showAs                   AS MODUL_K_SHOW_AS,
        nazFirmy                        AS NAZ_FIRMY,
        dic                             AS DIC,
        popis                           AS POPIS,
        varSym                          AS VAR_SYM,
        typSzbDphK                      AS TYP_SZB_DPH_K,
        typSzbDphK_showAs               AS TYP_SZB_DPH_K_SHOW_AS,
        szbDph                          AS SZB_DPH,
        {{ s.sign }}sumTuz                      AS SUM_TUZ,
        {{ s.sign }}sumMen                      AS SUM_MEN,
        stavUzivK                       AS STAV_UZIV_K,
        stavUzivK_showAs                AS STAV_UZIV_K_SHOW_AS,
        stredisko                       AS STREDISKO,
        stredisko_ref                   AS STREDISKO_REF,
        stredisko_showAs                AS STREDISKO_SHOW_AS,
        idDokl                          AS ID_DOKL,
        zuctovano                       AS ZUCTOVANO,
        vatItem                         AS VAT_ITEM,
        accountsSwapped                 AS ACCOUNTS_SWAPPED,
        zakazka                         AS ZAKAZKA,
        zakazka_ref                     AS ZAKAZKA_REF,
        zakazka_showAs                  AS ZAKAZKA_SHOW_AS,
        parSymbol                       AS PAR_SYMBOL,
        cinnost                         AS CINNOST,
        cinnost_ref                     AS CINNOST_REF,
        cinnost_showAs                  AS CINNOST_SHOW_AS,
        idPolozek                       AS ID_POLOZEK,
        bezPolozek                      AS BEZ_POLOZEK
    FROM base
){{ "," if not loop.last }}
{% endfor %}

SELECT * FROM md_entries
UNION ALL
SELECT * FROM dal_entries
