*---------------------------------------------------------------------*
*    program for:   TABLEFRAME_ZBDC_CFG
*---------------------------------------------------------------------*
FUNCTION TABLEFRAME_ZBDC_CFG_BUP           .
*"--------------------------------------------------------------------
*"*"Local Interface:
*"  IMPORTING
*"     VALUE(VIEW_ACTION) DEFAULT 'S'
*"     VALUE(VIEW_NAME) LIKE  DD02V-TABNAME
*"     VALUE(CORR_NUMBER) LIKE  E070-TRKORR DEFAULT ' '
*"  TABLES
*"      DBA_SELLIST STRUCTURE  VIMSELLIST
*"      DPL_SELLIST STRUCTURE  VIMSELLIST
*"      EXCL_CUA_FUNCT STRUCTURE  VIMEXCLFUN
*"      X_HEADER STRUCTURE  VIMDESC
*"      X_NAMTAB STRUCTURE  VIMNAMTAB
*"  EXCEPTIONS
*"      MISSING_CORR_NUMBER
*"--------------------------------------------------------------------

  PERFORM TABLEFRAME TABLES X_HEADER X_NAMTAB DBA_SELLIST DPL_SELLIST
                            EXCL_CUA_FUNCT
                     USING  CORR_NUMBER VIEW_ACTION VIEW_NAME.

ENDFUNCTION.
