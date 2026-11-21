**FREE
ctl-opt nomain bnddir('MTGBND') option(*nodebugio: *srcstmt);

// =====================================================================
// Service Program: MTGFIN_SV
// Purpose: Applicant Income, Expense, Debt, and Credit Profile Management
// =====================================================================

/copy qrpglesrc/MTG_H.rpgleinc

// ---------------------------------------------------------------------
// mtg_saveFinances: Inserts or updates financial profile for an application
// ---------------------------------------------------------------------
dcl-proc mtg_saveFinances export;
  dcl-pi *n ind;
    pFinProfile likeds(ds_FinancialProfile) const;
  end-pi;

  dcl-s success ind inz(*off);
  dcl-s appCount int(10) inz(0);

  if pFinProfile.appId <= 0;
    return *off;
  endif;

  exec sql
    SELECT COUNT(*) INTO :appCount
    FROM MTGFIN
    WHERE APP_ID = :pFinProfile.appId;

  if appCount = 0;
    exec sql
      INSERT INTO MTGFIN (
        APP_ID, GROSS_INCOME, OTHER_INCOME, MONTHLY_EXP,
        EXISTING_DEBTS, CREDIT_SCORE, EMPLOYMENT_STS
      ) VALUES (
        :pFinProfile.appId,
        :pFinProfile.grossIncome,
        :pFinProfile.otherIncome,
        :pFinProfile.monthlyExpenses,
        :pFinProfile.existingDebts,
        :pFinProfile.creditScore,
        :pFinProfile.employmentSts
      );
  else;
    exec sql
      UPDATE MTGFIN
      SET GROSS_INCOME   = :pFinProfile.grossIncome,
          OTHER_INCOME   = :pFinProfile.otherIncome,
          MONTHLY_EXP    = :pFinProfile.monthlyExpenses,
          EXISTING_DEBTS = :pFinProfile.existingDebts,
          CREDIT_SCORE   = :pFinProfile.creditScore,
          EMPLOYMENT_STS = :pFinProfile.employmentSts
      WHERE APP_ID = :pFinProfile.appId;
  endif;

  if sqlcode = 0;
    success = *on;
  endif;

  return success;
end-proc;

// ---------------------------------------------------------------------
// mtg_getFinances: Retrieves financial profile for given application
// ---------------------------------------------------------------------
dcl-proc mtg_getFinances export;
  dcl-pi *n ind;
    pAppId      int(10) const;
    pFinProfile likeds(ds_FinancialProfile);
  end-pi;

  dcl-s found ind inz(*off);

  clear pFinProfile;

  exec sql
    SELECT APP_ID, GROSS_INCOME, OTHER_INCOME, MONTHLY_EXP,
           EXISTING_DEBTS, CREDIT_SCORE, EMPLOYMENT_STS
    INTO :pFinProfile.appId, :pFinProfile.grossIncome, :pFinProfile.otherIncome,
         :pFinProfile.monthlyExpenses, :pFinProfile.existingDebts,
         :pFinProfile.creditScore, :pFinProfile.employmentSts
    FROM MTGFIN
    WHERE APP_ID = :pAppId;

  if sqlcode = 0;
    found = *on;
  endif;

  return found;
end-proc;
