**FREE
ctl-opt nomain bnddir('MTGBND') option(*nodebugio: *srcstmt);

// =====================================================================
// Service Program: MTGPRD_SV
// Purpose: Product Catalog Inquiries and Customer Product Selection
// =====================================================================

/copy qrpglesrc/MTG_H.rpgleinc

// ---------------------------------------------------------------------
// mtg_getEligibleProducts: Fetches products matching calculated LTV cap
// ---------------------------------------------------------------------
dcl-proc mtg_getEligibleProducts export;
  dcl-pi *n int(5);
    pLTV      packed(5: 2) const;
    pProdList likeds(ds_Product) dim(10);
  end-pi;

  dcl-s prodCount int(5) inz(0);
  dcl-ds dsTemp likeds(ds_Product);

  clear pProdList;

  exec sql
    DECLARE c_products CURSOR FOR
    SELECT PROD_ID, PROD_NAME, RATE_TYPE, INITIAL_RATE, MAX_LTV, FEE, DESCRIPTION
    FROM MTGPRD
    WHERE MAX_LTV >= :pLTV
    ORDER BY INITIAL_RATE ASC;

  exec sql OPEN c_products;

  dow sqlcode = 0 and prodCount < 10;
    exec sql
      FETCH c_products INTO
        :dsTemp.prodId, :dsTemp.prodName, :dsTemp.rateType,
        :dsTemp.initialRate, :dsTemp.maxLTV, :dsTemp.fee,
        :dsTemp.description;

    if sqlcode = 0;
      prodCount += 1;
      pProdList(prodCount) = dsTemp;
    endif;
  enddo;

  exec sql CLOSE c_products;

  return prodCount;
end-proc;

// ---------------------------------------------------------------------
// mtg_selectProduct: Locks product choice and repayment into application
// ---------------------------------------------------------------------
dcl-proc mtg_selectProduct export;
  dcl-pi *n ind;
    pAppId      int(10) const;
    pProdId     varchar(10) const;
    pRate       packed(5: 2) const;
    pMonthlyPmt packed(9: 2) const;
  end-pi;

  dcl-s success ind inz(*off);

  exec sql
    UPDATE MTGAPP
    SET PROD_ID     = :pProdId,
        INT_RATE    = :pRate,
        MONTHLY_PMT = :pMonthlyPmt,
        UPDATED_TS  = CURRENT_TIMESTAMP
    WHERE APP_ID = :pAppId;

  if sqlcode = 0;
    success = *on;
  endif;

  return success;
end-proc;
