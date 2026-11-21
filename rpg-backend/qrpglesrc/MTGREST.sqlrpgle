**FREE
ctl-opt main(MtgRestMain) bnddir('MTGBND') option(*nodebugio: *srcstmt);

// =====================================================================
// Program: MTGREST (*PGM)
// Purpose: Web REST API Controller / JSON Request Router for IBM i
// Input Parameters:
//   1. pAction     (In)  : Action Verb (e.g., 'NEW_APP', 'SAVE_PROP', 'SUBMIT')
//   2. pInJson     (In)  : Request Payload (JSON string)
//   3. pOutJson    (Out) : Response Payload (JSON string)
//   4. pHttpStatus (Out) : HTTP Status Code (200, 400, 404, 500)
// =====================================================================

/copy qrpglesrc/MTG_H.rpgleinc

dcl-proc MtgRestMain;
  dcl-pi *n;
    pAction     varchar(30)   const;
    pInJson     varchar(4000) const;
    pOutJson    varchar(4000);
    pHttpStatus int(10);
  end-pi;

  dcl-s actionUpper varchar(30);

  // Local Work Variables
  dcl-s appId       int(10) inz(0);
  dcl-s custName    varchar(80) inz('');
  dcl-s appType     varchar(20) inz('');
  dcl-s propValue   packed(11: 2) inz(0.00);
  dcl-s loanAmount  packed(11: 2) inz(0.00);
  dcl-s termYears   int(5) inz(25);
  dcl-s prodId      varchar(10) inz('');
  dcl-s ratePct     packed(5: 2) inz(0.00);
  dcl-s monthlyPmt  packed(9: 2) inz(0.00);
  dcl-s docType     varchar(30) inz('');
  dcl-s fileName    varchar(100) inz('');

  dcl-ds dsFin      likeds(ds_FinancialProfile);
  dcl-ds dsApp      likeds(ds_Application);
  dcl-ds dsDec      likeds(ds_DecisionResult);
  dcl-ds dsProdList likeds(ds_Product) dim(10);
  dcl-s prodCount   int(5) inz(0);
  dcl-s calcLTV     packed(5: 2) inz(0.00);
  dcl-s maxLoan     packed(11: 2) inz(0.00);
  dcl-s i           int(5);
  dcl-s prodJson    varchar(3000);

  actionUpper = %upper(%trim(pAction));
  pHttpStatus = 200;
  pOutJson = '{"status":"OK"}';

  select;

    // -----------------------------------------------------------------
    // Step 1: Start New Application
    // Payload: {"custName": "Jane Doe", "appType": "FIRST_TIME"}
    // -----------------------------------------------------------------
    when actionUpper = 'NEW_APP';
      exec sql
        SELECT COALESCE(JSON_VALUE(:pInJson, '$.custName'), 'Valued Customer'),
               COALESCE(JSON_VALUE(:pInJson, '$.appType'), 'FIRST_TIME')
        INTO :custName, :appType
        FROM SYSIBM.SYSDUMMY1;

      appId = mtg_createApp(appType: custName);

      if appId > 0;
        pOutJson = '{"appId":' + %char(appId) + ',"status":"DRAFT","message":"Application initialized"}';
      else;
        pHttpStatus = 500;
        pOutJson = '{"error":"Failed to create application"}';
      endif;

    // -----------------------------------------------------------------
    // Step 2: Save Property & Mortgage Details
    // Payload: {"appId": 1001, "propValue": 350000.00, "loanAmount": 280000.00, "termYears": 30}
    // -----------------------------------------------------------------
    when actionUpper = 'SAVE_PROP';
      exec sql
        SELECT CAST(COALESCE(JSON_VALUE(:pInJson, '$.appId'), '0') AS INT),
               CAST(COALESCE(JSON_VALUE(:pInJson, '$.propValue'), '0.00') AS DECIMAL(11,2)),
               CAST(COALESCE(JSON_VALUE(:pInJson, '$.loanAmount'), '0.00') AS DECIMAL(11,2)),
               CAST(COALESCE(JSON_VALUE(:pInJson, '$.termYears'), '25') AS INT)
        INTO :appId, :propValue, :loanAmount, :termYears
        FROM SYSIBM.SYSDUMMY1;

      if mtg_savePropertyDetails(appId: propValue: loanAmount: termYears);
        calcLTV = mtg_calcLTV(loanAmount: propValue);
        pOutJson = '{"appId":' + %char(appId) + ',"ltv":' + %char(calcLTV) + ',"status":"SAVED"}';
      else;
        pHttpStatus = 400;
        pOutJson = '{"error":"Failed to save property details"}';
      endif;

    // -----------------------------------------------------------------
    // Step 3: Save Applicant Financial Profile
    // Payload: {"appId": 1001, "grossIncome": 85000.00, "otherIncome": 5000.00,
    //           "monthlyExp": 1800.00, "existingDebts": 350.00, "creditScore": 740}
    // -----------------------------------------------------------------
    when actionUpper = 'SAVE_FIN';
      exec sql
        SELECT CAST(COALESCE(JSON_VALUE(:pInJson, '$.appId'), '0') AS INT),
               CAST(COALESCE(JSON_VALUE(:pInJson, '$.grossIncome'), '0.00') AS DECIMAL(11,2)),
               CAST(COALESCE(JSON_VALUE(:pInJson, '$.otherIncome'), '0.00') AS DECIMAL(11,2)),
               CAST(COALESCE(JSON_VALUE(:pInJson, '$.monthlyExp'), '0.00') AS DECIMAL(9,2)),
               CAST(COALESCE(JSON_VALUE(:pInJson, '$.existingDebts'), '0.00') AS DECIMAL(9,2)),
               CAST(COALESCE(JSON_VALUE(:pInJson, '$.creditScore'), '720') AS INT),
               COALESCE(JSON_VALUE(:pInJson, '$.employmentSts'), 'PERMANENT_FT')
        INTO :dsFin.appId, :dsFin.grossIncome, :dsFin.otherIncome,
             :dsFin.monthlyExpenses, :dsFin.existingDebts, :dsFin.creditScore,
             :dsFin.employmentSts
        FROM SYSIBM.SYSDUMMY1;

      if mtg_saveFinances(dsFin);
        maxLoan = mtg_calcAffordability(dsFin.grossIncome: dsFin.otherIncome:
                                        dsFin.monthlyExpenses: dsFin.existingDebts);
        pOutJson = '{"appId":' + %char(dsFin.appId) + ',"maxBorrowing":' + %char(maxLoan) + ',"status":"SAVED"}';
      else;
        pHttpStatus = 400;
        pOutJson = '{"error":"Failed to save financial profile"}';
      endif;

    // -----------------------------------------------------------------
    // Step 4: Calculate Indicative Figures
    // Payload: {"propValue": 400000.00, "loanAmount": 320000.00, "rate": 4.25, "termYears": 25,
    //           "grossIncome": 85000.00, "otherIncome": 0.00, "monthlyExp": 1200.00, "existingDebts": 200.00}
    // -----------------------------------------------------------------
    when actionUpper = 'CALCULATE';
      exec sql
        SELECT CAST(COALESCE(JSON_VALUE(:pInJson, '$.propValue'), '0.00') AS DECIMAL(11,2)),
               CAST(COALESCE(JSON_VALUE(:pInJson, '$.loanAmount'), '0.00') AS DECIMAL(11,2)),
               CAST(COALESCE(JSON_VALUE(:pInJson, '$.rate'), '4.25') AS DECIMAL(5,2)),
               CAST(COALESCE(JSON_VALUE(:pInJson, '$.termYears'), '25') AS INT),
               CAST(COALESCE(JSON_VALUE(:pInJson, '$.grossIncome'), '0.00') AS DECIMAL(11,2)),
               CAST(COALESCE(JSON_VALUE(:pInJson, '$.otherIncome'), '0.00') AS DECIMAL(11,2)),
               CAST(COALESCE(JSON_VALUE(:pInJson, '$.monthlyExp'), '0.00') AS DECIMAL(9,2)),
               CAST(COALESCE(JSON_VALUE(:pInJson, '$.existingDebts'), '0.00') AS DECIMAL(9,2))
        INTO :propValue, :loanAmount, :ratePct, :termYears,
             :dsFin.grossIncome, :dsFin.otherIncome, :dsFin.monthlyExpenses, :dsFin.existingDebts
        FROM SYSIBM.SYSDUMMY1;

      calcLTV = mtg_calcLTV(loanAmount: propValue);
      maxLoan = mtg_calcAffordability(dsFin.grossIncome: dsFin.otherIncome:
                                      dsFin.monthlyExpenses: dsFin.existingDebts);
      monthlyPmt = mtg_calcRepayment(loanAmount: ratePct: termYears);

      pOutJson = '{"ltv":' + %char(calcLTV) +
                 ',"maxBorrowing":' + %char(maxLoan) +
                 ',"monthlyPayment":' + %char(monthlyPmt) + '}';

    // -----------------------------------------------------------------
    // Step 5: Get Eligible Products
    // Payload: {"ltv": 80.00}
    // -----------------------------------------------------------------
    when actionUpper = 'GET_PRODUCTS';
      exec sql
        SELECT CAST(COALESCE(JSON_VALUE(:pInJson, '$.ltv'), '80.00') AS DECIMAL(5,2))
        INTO :calcLTV
        FROM SYSIBM.SYSDUMMY1;

      prodCount = mtg_getEligibleProducts(calcLTV: dsProdList);

      prodJson = '{"count":' + %char(prodCount) + ',"products":[';
      for i = 1 to prodCount;
        if i > 1;
          prodJson += ',';
        endif;
        prodJson += '{"prodId":"' + %trim(dsProdList(i).prodId) + '"' +
                    ',"prodName":"' + %trim(dsProdList(i).prodName) + '"' +
                    ',"rateType":"' + %trim(dsProdList(i).rateType) + '"' +
                    ',"initialRate":' + %char(dsProdList(i).initialRate) +
                    ',"maxLTV":' + %char(dsProdList(i).maxLTV) +
                    ',"fee":' + %char(dsProdList(i).fee) +
                    ',"description":"' + %trim(dsProdList(i).description) + '"}';
      endfor;
      prodJson += ']}';
      pOutJson = prodJson;

    // -----------------------------------------------------------------
    // Step 6a: Select Mortgage Product
    // Payload: {"appId": 1001, "prodId": "FIX2_80", "rate": 4.45, "monthlyPmt": 1420.50}
    // -----------------------------------------------------------------
    when actionUpper = 'SELECT_PROD';
      exec sql
        SELECT CAST(COALESCE(JSON_VALUE(:pInJson, '$.appId'), '0') AS INT),
               COALESCE(JSON_VALUE(:pInJson, '$.prodId'), ''),
               CAST(COALESCE(JSON_VALUE(:pInJson, '$.rate'), '0.00') AS DECIMAL(5,2)),
               CAST(COALESCE(JSON_VALUE(:pInJson, '$.monthlyPmt'), '0.00') AS DECIMAL(9,2))
        INTO :appId, :prodId, :ratePct, :monthlyPmt
        FROM SYSIBM.SYSDUMMY1;

      if mtg_selectProduct(appId: prodId: ratePct: monthlyPmt);
        pOutJson = '{"appId":' + %char(appId) + ',"selectedProd":"' + %trim(prodId) + '","status":"SAVED"}';
      else;
        pHttpStatus = 400;
        pOutJson = '{"error":"Failed to save product selection"}';
      endif;

    // -----------------------------------------------------------------
    // Step 6b: Upload Document Metadata
    // Payload: {"appId": 1001, "docType": "PAYSLIP", "fileName": "payslip_nov.pdf"}
    // -----------------------------------------------------------------
    when actionUpper = 'ADD_DOC';
      exec sql
        SELECT CAST(COALESCE(JSON_VALUE(:pInJson, '$.appId'), '0') AS INT),
               COALESCE(JSON_VALUE(:pInJson, '$.docType'), 'PAYSLIP'),
               COALESCE(JSON_VALUE(:pInJson, '$.fileName'), 'document.pdf')
        INTO :appId, :docType, :fileName
        FROM SYSIBM.SYSDUMMY1;

      if mtg_addDocMetadata(appId: docType: fileName);
        pOutJson = '{"appId":' + %char(appId) + ',"status":"DOCUMENT_VERIFIED"}';
      else;
        pHttpStatus = 400;
        pOutJson = '{"error":"Failed to register document metadata"}';
      endif;

    // -----------------------------------------------------------------
    // Step 7 & 8: Review & Submit (Triggers Decision Engine)
    // Payload: {"appId": 1001}
    // -----------------------------------------------------------------
    when actionUpper = 'SUBMIT';
      exec sql
        SELECT CAST(COALESCE(JSON_VALUE(:pInJson, '$.appId'), '0') AS INT)
        INTO :appId
        FROM SYSIBM.SYSDUMMY1;

      mtg_submitApplication(appId);

      if mtg_evaluateDecision(appId: dsDec);
        pOutJson = '{"appId":' + %char(appId) +
                   ',"decision":"' + %trim(dsDec.decisionCode) + '"' +
                   ',"reasonCode":"' + %trim(dsDec.reasonCode) + '"' +
                   ',"reasonDesc":"' + %trim(dsDec.reasonDesc) + '"' +
                   ',"maxLoan":' + %char(dsDec.maxLoanAllowed) + '}';
      else;
        pHttpStatus = 500;
        pOutJson = '{"error":"Decision evaluation failed"}';
      endif;

    // -----------------------------------------------------------------
    // Step 9: Get Live Application Status
    // Payload: {"appId": 1001}
    // -----------------------------------------------------------------
    when actionUpper = 'GET_STATUS';
      exec sql
        SELECT CAST(COALESCE(JSON_VALUE(:pInJson, '$.appId'), '0') AS INT)
        INTO :appId
        FROM SYSIBM.SYSDUMMY1;

      if mtg_getApplicationStatus(appId: dsApp);
        pOutJson = '{"appId":' + %char(dsApp.appId) +
                   ',"custName":"' + %trim(dsApp.custName) + '"' +
                   ',"appType":"' + %trim(dsApp.appType) + '"' +
                   ',"status":"' + %trim(dsApp.status) + '"' +
                   ',"propertyValue":' + %char(dsApp.propertyValue) +
                   ',"loanAmount":' + %char(dsApp.loanAmount) +
                   ',"termYears":' + %char(dsApp.termYears) +
                   ',"prodId":"' + %trim(dsApp.prodId) + '"' +
                   ',"interestRate":' + %char(dsApp.interestRate) +
                   ',"monthlyPayment":' + %char(dsApp.monthlyPayment) + '}';
      else;
        pHttpStatus = 404;
        pOutJson = '{"error":"Application not found"}';
      endif;

    // -----------------------------------------------------------------
    // Unknown Action
    // -----------------------------------------------------------------
    other;
      pHttpStatus = 400;
      pOutJson = '{"error":"Unknown action: ' + %trim(pAction) + '"}';

  endsl;

  // -------------------------------------------------------------------
  // Automatically write step output payload to audit log file (MTGAUDIT)
  // -------------------------------------------------------------------
  mtg_writeAudit(appId: actionUpper: pHttpStatus: %trim(dsApp.status): pOutJson);

  return;
end-proc;
