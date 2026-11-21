**FREE
ctl-opt nomain bnddir('MTGBND') option(*nodebugio: *srcstmt);

// =====================================================================
// Service Program: MTGCALC_SV
// Purpose: Pure Financial Calculation Engine for LTV, Affordability, & Repayments
// =====================================================================

/copy qrpglesrc/MTG_H.rpgleinc

// ---------------------------------------------------------------------
// mtg_calcLTV: Calculates Loan-to-Value Percentage
// Formula: (Loan Amount / Property Value) * 100
// ---------------------------------------------------------------------
dcl-proc mtg_calcLTV export;
  dcl-pi *n packed(5: 2);
    pLoanAmount packed(11: 2) const;
    pPropValue  packed(11: 2) const;
  end-pi;

  dcl-s rLTV packed(5: 2) inz(0.00);

  if pPropValue > 0 and pLoanAmount > 0;
    rLTV = (pLoanAmount / pPropValue) * 100.00;
  endif;

  return rLTV;
end-proc;

// ---------------------------------------------------------------------
// mtg_calcAffordability: Calculates Indicative Maximum Borrowing Cap
// Standard UK/IE formula: 4.5x total income minus annual debt obligations
// ---------------------------------------------------------------------
dcl-proc mtg_calcAffordability export;
  dcl-pi *n packed(11: 2);
    pGrossIncome packed(11: 2) const;
    pOtherIncome packed(11: 2) const;
    pMonthlyExp  packed(9: 2) const;
    pDebts       packed(9: 2) const;
  end-pi;

  dcl-s totalAnnualIncome packed(11: 2);
  dcl-s annualDebts       packed(11: 2);
  dcl-s maxBorrowing      packed(11: 2) inz(0.00);

  totalAnnualIncome = pGrossIncome + pOtherIncome;
  annualDebts = pDebts * 12;

  // Maximum loan cap at 4.5x income, adjusted for existing annual debt load
  if totalAnnualIncome > 0;
    maxBorrowing = (totalAnnualIncome * 4.5) - (annualDebts * 1.5);
    if maxBorrowing < 0;
      maxBorrowing = 0.00;
    endif;
  endif;

  return maxBorrowing;
end-proc;

// ---------------------------------------------------------------------
// mtg_calcRepayment: Computes Monthly Capital + Interest Repayment
// Standard amortization formula: M = P * [r(1+r)^n] / [(1+r)^n - 1]
// ---------------------------------------------------------------------
dcl-proc mtg_calcRepayment export;
  dcl-pi *n packed(9: 2);
    pPrincipal packed(11: 2) const;
    pRatePct   packed(5: 2) const;
    pTermYears int(5) const;
  end-pi;

  dcl-s rMonthlyPmt float(8);
  dcl-s monthlyRate float(8);
  dcl-s numPayments int(10);
  dcl-s compound    float(8);

  if pPrincipal <= 0 or pTermYears <= 0;
    return 0.00;
  endif;

  numPayments = pTermYears * 12;

  // Handle zero-interest edge case
  if pRatePct <= 0;
    return %dech(pPrincipal / numPayments: 9: 2);
  endif;

  monthlyRate = (pRatePct / 100.0) / 12.0;
  compound = (1.0 + monthlyRate) ** numPayments;

  rMonthlyPmt = pPrincipal * (monthlyRate * compound) / (compound - 1.0);

  return %dech(rMonthlyPmt: 9: 2);
end-proc;
