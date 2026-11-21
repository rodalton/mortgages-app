-- =====================================================================
-- Audit Query Helper & View for Mortgage Application
-- =====================================================================

CREATE OR REPLACE VIEW V_MTG_AUDIT_TRAIL AS
SELECT 
    A.AUDIT_ID,
    A.APP_ID,
    COALESCE(M.CUST_NAME, 'N/A') AS CUST_NAME,
    A.ACTION_VERB,
    A.HTTP_STATUS,
    A.STATUS_CODE,
    A.OUTPUT_PAYLOAD,
    A.USER_PROFILE,
    A.JOB_NAME,
    A.LOGGED_TS
FROM MTGAUDIT A
LEFT JOIN MTGAPP M ON A.APP_ID = M.APP_ID
ORDER BY A.LOGGED_TS DESC;
