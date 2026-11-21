**FREE
ctl-opt nomain bnddir('MTGBND') option(*nodebugio: *srcstmt);

// =====================================================================
// Service Program: MTGDEC_SV
// Purpose: Automated Underwriting Rules Engine & Decision Evaluator
// =====================================================================

/copy qrpglesrc/MTG_H.rpgleinc

// ---------------------------------------------------------------------
// mtg_evaluateDecision: Applies credit & affordability underwriting rules
// ---------------------------------------------------------------------
dcl-proc mtg_evaluateDecision export;
  dcl-pi *n ind;
    pAppId      int(10) const;
    pDecisionDs likeds(ds_DecisionResult);
  end-pi;

  dcl-ds dsApp likeds(ds_Application);
  dcl-ds dsFin likeds(ds_FinancialProfile);
  dcl-s calcLTV packed(5: 2) inz(0.00);
  dcl-s maxAllowedLoan packed(11: 2) inz(0.00);
  dcl-s isAppOk ind;
  dcl-s isFinOk ind;

  clear pDecisionDs;
  pDecisionDs.appId = pAppId;
  pDecisionDs.evaluatedTs = %timestamp();

  // Load application and financial profiles
  isAppOk = mtg_getApplicationStatus(pAppId: dsApp);
  isFinOk = mtg_getFinances(pAppId: dsFin);

  if not isAppOk or not isFinOk;
    pDecisionDs.decisionCode = STAT_REFERRED;
    pDecisionDs.reasonCode = 'INCOMPLETE_DATA';
    pDecisionDs.reasonDesc = 'Application or financial profile is missing data.';
    pDecisionDs.maxLoanAllowed = 0.00;
  else;
    // Calculate core metrics
    calcLTV = mtg_calcLTV(dsApp.loanAmount: dsApp.propertyValue);
    maxAllowedLoan = mtg_calcAffordability(dsFin.grossIncome: dsFin.otherIncome:
                                           dsFin.monthlyExpenses: dsFin.existingDebts);
    pDecisionDs.maxLoanAllowed = maxAllowedLoan;

    // Rule 1: High Loan-To-Value Threshold (> 95%) -> Decline
    if calcLTV > 95.00;
      pDecisionDs.decisionCode = STAT_DECLINED;
      pDecisionDs.reasonCode = 'LTV_EXCEEDS_MAXIMUM';
      pDecisionDs.reasonDesc = 'Loan-to-value ratio (' + %char(calcLTV) + '%) exceeds our maximum lending limit of 95%.';

    // Rule 2: Insufficient Affordability -> Refer to Underwriter
    elseif dsApp.loanAmount > maxAllowedLoan;
      pDecisionDs.decisionCode = STAT_REFERRED;
      pDecisionDs.reasonCode = 'AFFORDABILITY_STRETCH';
      pDecisionDs.reasonDesc = 'Requested loan exceeds calculated borrowing cap based on verified income & commitments.';

    // Rule 3: Adverse Credit Score (< 600) -> Refer for Manual Review
    elseif dsFin.creditScore < 600;
      pDecisionDs.decisionCode = STAT_REFERRED;
      pDecisionDs.reasonCode = 'CREDIT_SCORE_REFERRAL';
      pDecisionDs.reasonDesc = 'Credit profile requires underwriter assessment of recent credit history.';

    // Rule 4: Clean Profile -> Automatic Instant Approval
    else;
      pDecisionDs.decisionCode = STAT_APPROVED;
      pDecisionDs.reasonCode = 'STANDARD_APPROVAL';
      pDecisionDs.reasonDesc = 'Application meets all LTV, income affordability, and credit policy rules.';
    endif;
  endif;

  // Persist decision in MTGDEC table
  exec sql
    INSERT INTO MTGDEC (APP_ID, DECISION_CODE, REASON_CODE, REASON_DESC, MAX_LOAN)
    VALUES (
      :pDecisionDs.appId,
      :pDecisionDs.decisionCode,
      :pDecisionDs.reasonCode,
      :pDecisionDs.reasonDesc,
      :pDecisionDs.maxLoanAllowed
    );

  // Update master application status
  exec sql
    UPDATE MTGAPP
    SET STATUS = :pDecisionDs.decisionCode,
        UPDATED_TS = CURRENT_TIMESTAMP
    WHERE APP_ID = :pAppId;

  return (pDecisionDs.decisionCode <> '');
end-proc;
