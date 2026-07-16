*---------------------------------------------------------------------*
*    program for:   TABLEPROC_ZBDC_CFG
*---------------------------------------------------------------------*
FUNCTION TABLEPROC_ZBDC_CFG_BUP            .
*"--------------------------------------------------------------------
*"*"Global Interface:
*"  IMPORTING
*"     VALUE(FCODE) DEFAULT 'RDED'
*"     VALUE(VIEW_ACTION) DEFAULT 'S'
*"     VALUE(VIEW_NAME) LIKE  DD02V-TABNAME
*"     VALUE(CORR_NUMBER) LIKE  E070-TRKORR DEFAULT ' '
*"  EXPORTING
*"     VALUE(LAST_ACT_ENTRY)
*"     VALUE(UCOMM)
*"     VALUE(UPDATE_REQUIRED)
*"  TABLES
*"      CORR_KEYTAB STRUCTURE  E071K
*"      DBA_SELLIST STRUCTURE  VIMSELLIST
*"      DPL_SELLIST STRUCTURE  VIMSELLIST
*"      EXCL_CUA_FUNCT STRUCTURE  VIMEXCLFUN
*"      EXTRACT
*"      TOTAL
*"      X_HEADER STRUCTURE  VIMDESC
*"      X_NAMTAB STRUCTURE  VIMNAMTAB
*"  EXCEPTIONS
*"      MISSING_CORR_NUMBER
*"      SAVING_CORRECTION_FAILED
*"--------------------------------------------------------------------

  PERFORM TABLEPROC.

ENDFUNCTION.
