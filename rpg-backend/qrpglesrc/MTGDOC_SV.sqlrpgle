**FREE
ctl-opt nomain bnddir('MTGBND') option(*nodebugio: *srcstmt);

// =====================================================================
// Service Program: MTGDOC_SV
// Purpose: Document Metadata & Simulated Identity Verification Tracking
// =====================================================================

/copy qrpglesrc/MTG_H.rpgleinc

// ---------------------------------------------------------------------
// mtg_addDocMetadata: Records simulated document upload event
// ---------------------------------------------------------------------
dcl-proc mtg_addDocMetadata export;
  dcl-pi *n ind;
    pAppId    int(10) const;
    pDocType  varchar(30) const;
    pFileName varchar(100) const;
  end-pi;

  dcl-s success ind inz(*off);

  exec sql
    INSERT INTO MTGDOC (APP_ID, DOC_TYPE, FILE_NAME, VERIFIED_FLAG)
    VALUES (:pAppId, :pDocType, :pFileName, 'Y');

  if sqlcode = 0;
    success = *on;
  endif;

  return success;
end-proc;
