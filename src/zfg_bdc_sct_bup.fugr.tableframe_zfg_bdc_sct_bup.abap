*---------------------------------------------------------------------*
*    program for:   TABLEFRAME_ZFG_BDC_SCT_BUP
*---------------------------------------------------------------------*
FUNCTION TABLEFRAME_ZFG_BDC_SCT_BUP    .

  PERFORM TABLEFRAME TABLES X_HEADER X_NAMTAB DBA_SELLIST DPL_SELLIST
                            EXCL_CUA_FUNCT
                     USING  CORR_NUMBER VIEW_ACTION VIEW_NAME.

ENDFUNCTION.
