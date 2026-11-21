**FREE
ctl-opt nomain bnddir('MTGBND') option(*nodebugio: *srcstmt);

// =====================================================================
// Service Program: MTGAPP_SV
// Purpose: Application Master Lifecycle & Workflow Management
// =====================================================================

/copy qrpglesrc/MTG_H.rpgleinc

// ---------------------------------------------------------------------
// mtg_createApp: Creates a new application record in MTGAPP
// ---------------------------------------------------------------------
dcl-proc mtg_createApp export;
  dcl-pi *n int(10);
    pAppType  varchar(20) const;
    pCustName varchar(80) const;
  end-pi;

  dcl-s newAppId int(10) inz(0);
  dcl-s appTypeClean varchar(20);
  dcl-s custNameClean varchar(80);

  appTypeClean = %trim(pAppType);
  if appTypeClean = '';
    appTypeClean = 'FIRST_TIME';
  endif;

  custNameClean = %trim(pCustName);
  if custNameClean = '';
    custNameClean = 'Valued Customer';
  endif;

  exec sql
    INSERT INTO MTGAPP (CUST_NAME, APP_TYPE, STATUS)
    VALUES (:custNameClean, :appTypeClean, 'DRAFT');

  if sqlcode = 0;
    exec sql
      VALUES IDENTITY_VAL_LOCAL() INTO :newAppId;
  endif;

  return newAppId;
end-proc;

// ---------------------------------------------------------------------
// mtg_savePropertyDetails: Updates property value, loan amount, and term
// ---------------------------------------------------------------------
dcl-proc mtg_savePropertyDetails export;
  dcl-pi *n ind;
    pAppId     int(10) const;
    pPropValue packed(11: 2) const;
    pLoanAmt   packed(11: 2) const;
    pTermYrs   int(5) const;
  end-pi;

  dcl-s success ind inz(*off);

  exec sql
    UPDATE MTGAPP
    SET PROP_VALUE = :pPropValue,
        LOAN_AMT   = :pLoanAmt,
        TERM_YRS   = :pTermYrs,
        UPDATED_TS = CURRENT_TIMESTAMP
    WHERE APP_ID = :pAppId;

  if sqlcode = 0;
    success = *on;
  endif;

  return success;
end-proc;

// ---------------------------------------------------------------------
// mtg_submitApplication: Transitions status from DRAFT to SUBMITTED
// ---------------------------------------------------------------------
dcl-proc mtg_submitApplication export;
  dcl-pi *n varchar(20);
    pAppId int(10) const;
  end-pi;

  dcl-s newStatus varchar(20) inz(STAT_SUBMITTED);

  exec sql
    UPDATE MTGAPP
    SET STATUS = 'SUBMITTED',
        UPDATED_TS = CURRENT_TIMESTAMP
    WHERE APP_ID = :pAppId;

  if sqlcode <> 0;
    newStatus = RC_ERROR;
  endif;

  return newStatus;
end-proc;

// ---------------------------------------------------------------------
// mtg_getApplicationStatus: Retrieves full application master state
// ---------------------------------------------------------------------
dcl-proc mtg_getApplicationStatus export;
  dcl-pi *n ind;
    pAppId int(10) const;
    pAppDs likeds(ds_Application);
  end-pi;

  dcl-s found ind inz(*off);

  clear pAppDs;

  exec sql
    SELECT APP_ID, CUST_NAME, APP_TYPE, STATUS, PROP_VALUE, LOAN_AMT,
           TERM_YRS, PROD_ID, INT_RATE, MONTHLY_PMT, CREATED_TS, UPDATED_TS
    INTO :pAppDs.appId, :pAppDs.custName, :pAppDs.appType, :pAppDs.status,
         :pAppDs.propertyValue, :pAppDs.loanAmount, :pAppDs.termYears,
         :pAppDs.prodId, :pAppDs.interestRate, :pAppDs.monthlyPayment,
         :pAppDs.createdTs, :pAppDs.updatedTs
    FROM MTGAPP
    WHERE APP_ID = :pAppId;

  if sqlcode = 0;
    found = *on;
  endif;

  return found;
end-proc;

// ---------------------------------------------------------------------
// mtg_writeAudit: Logs application step outputs and events to MTGAUDIT
// ---------------------------------------------------------------------
dcl-proc mtg_writeAudit export;
  dcl-pi *n ind;
    pAppId      int(10) const;
    pAction     varchar(30) const;
    pHttpStatus int(10) const;
    pStatusCode varchar(20) const;
    pOutputJson varchar(4000) const;
  end-pi;

  dcl-s success ind inz(*off);

  exec sql
    INSERT INTO MTGAUDIT (
      APP_ID, ACTION_VERB, HTTP_STATUS, STATUS_CODE, OUTPUT_PAYLOAD
    ) VALUES (
      :pAppId, :pAction, :pHttpStatus, :pStatusCode, :pOutputJson
    );

  if sqlcode = 0;
    success = *on;
  endif;

  return success;
end-proc;
