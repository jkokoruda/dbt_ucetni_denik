/* ===== BLOCK: Block 1 ===== */

/* ===== CODE: Replace STG through PS cutoff then insert PS ===== */

DELETE FROM "STG_UCETNI_DENIK"
WHERE "DAT_UCTO" <= (
    SELECT MAX("DAT_UCTO")
    FROM "PS_UCETNI_DENIK"
);

INSERT INTO "STG_UCETNI_DENIK" (
    "PK_UCETNI_DENIK",
    "SOURCE",
    "UCET",
    "DAT_UCTO",
    "SUM_TUZ"
)
SELECT
    CONCAT('PS_', "UCET", '_', TO_VARCHAR("DAT_UCTO", 'YYYYMMDD')) AS "PK_UCETNI_DENIK",
    'PS' AS "SOURCE",
    "UCET",
    "DAT_UCTO",
    CAST("SUM_TUZ" * -1 AS NUMBER(18, 2)) AS "SUM_TUZ"
FROM "PS_UCETNI_DENIK";

