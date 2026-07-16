*&---------------------------------------------------------------------*
*& Include          ZBDC_MPE_M4_DASH_BUP
*& Purpose          M4 Monitoring - dashboard, ALV, result/detail screens
*& Source split     FIX16 V5BR - logic moved from F01
*&---------------------------------------------------------------------*

*>>> FORM CALCULATE_DASHBOARD_STATS - moved from Z_BDC_MASS_PO_ENTRY_F01_BUP


FORM CALCULATE_DASHBOARD_STATS.
ENDFORM.
*<<< END FORM CALCULATE_DASHBOARD_STATS

*>>> FORM GET_RECENT_SESSIONS - moved from Z_BDC_MASS_PO_ENTRY_F01_BUP

FORM GET_RECENT_SESSIONS.
  DATA: lt_raw       TYPE STANDARD TABLE OF ty_session_disp,
        ls_raw       TYPE ty_session_disp,
        ls_row       TYPE ty_session_disp,
        lt_stg_ids   TYPE STANDARD TABLE OF zbdc_staging_bup,
        ls_stg_id    TYPE zbdc_staging_bup.

  REFRESH gt_sessions.

  "STRICT REAL FIX:
  "Dashboard sessions must come from real staging/result data.
  "Do not rely only on result log, because a freshly uploaded LOCAL file may
  "already exist in ZBDC_STAGING_BUP before BDC execution creates result rows.
  "Session ID format SES_YYYYMMDD_HHMMSS is used as real ingestion order.
  SELECT DISTINCT session_id
    FROM zbdc_staging_bup
    INTO CORRESPONDING FIELDS OF TABLE @lt_stg_ids.

  LOOP AT lt_stg_ids INTO ls_stg_id.
    IF ls_stg_id-session_id IS INITIAL.
      CONTINUE.
    ENDIF.

    READ TABLE gt_sessions TRANSPORTING NO FIELDS
      WITH KEY session_id = ls_stg_id-session_id.
    IF sy-subrc = 0.
      CONTINUE.
    ENDIF.

    CLEAR ls_row.
    ls_row-session_id = ls_stg_id-session_id.
    ls_row-msg_type   = 'I'.
    ls_row-message    = 'Staging session'.
    APPEND ls_row TO gt_sessions.

  ENDLOOP.

  "Add real result-only sessions if any exist without staging.
  IF lines( gt_sessions ) < 500.
    SELECT session_id, created_at, msg_type, sap_object_id, message
      FROM zbdc_result_bup
      ORDER BY created_at DESCENDING
      INTO CORRESPONDING FIELDS OF TABLE @lt_raw
      UP TO 500 ROWS.

    LOOP AT lt_raw INTO ls_raw.
      IF ls_raw-session_id IS INITIAL.
        CONTINUE.
      ENDIF.

      READ TABLE gt_sessions TRANSPORTING NO FIELDS
        WITH KEY session_id = ls_raw-session_id.
      IF sy-subrc = 0.
        CONTINUE.
      ENDIF.

      APPEND ls_raw TO gt_sessions.

    ENDLOOP.
  ENDIF.
ENDFORM.
*<<< END FORM GET_RECENT_SESSIONS

*>>> FORM SET_SALV_COLUMN_NAMES - moved from Z_BDC_MASS_PO_ENTRY_F01_BUP

FORM SET_SALV_COLUMN_NAMES USING PO_SALV TYPE REF TO CL_SALV_TABLE.
  DATA: LT_MAP  TYPE STANDARD TABLE OF zbdc_mapping_bup,
        LS_MAP  TYPE zbdc_mapping_bup,
        LO_COLS TYPE REF TO CL_SALV_COLUMNS_TABLE,
        LO_COL  TYPE REF TO CL_SALV_COLUMN,
        LV_NR   TYPE N LENGTH 2,
        LV_FN   TYPE SALV_DE_COLUMN,
        LV_LTXT TYPE SCRTEXT_L,
        LV_MTXT TYPE SCRTEXT_M,
        LV_STXT TYPE SCRTEXT_S.

  SELECT PROFILE_NAME, SOURCE_COLUMN, STAGING_FIELD, BDC_FIELD, MANDATORY
    FROM zbdc_mapping_bup
    WHERE PROFILE_NAME = @TXTP_PROFILE_NAME
    INTO CORRESPONDING FIELDS OF TABLE @LT_MAP.

  LO_COLS = PO_SALV->GET_COLUMNS( ).
  LO_COLS->SET_OPTIMIZE( ABAP_TRUE ).

  TRY. LO_COL = LO_COLS->GET_COLUMN( 'MANDT' ). LO_COL->SET_VISIBLE( ABAP_FALSE ). CATCH CX_SALV_NOT_FOUND. ENDTRY.
  TRY. LO_COL = LO_COLS->GET_COLUMN( 'ERROR_CODE' ). LO_COL->SET_VISIBLE( ABAP_FALSE ). CATCH CX_SALV_NOT_FOUND. ENDTRY.
  TRY. LO_COL = LO_COLS->GET_COLUMN( 'SELECTED' ). LO_COL->SET_VISIBLE( ABAP_FALSE ). CATCH CX_SALV_NOT_FOUND. ENDTRY.

  TRY. LO_COL = LO_COLS->GET_COLUMN( 'SESSION_ID' ).
    LV_LTXT = 'Session ID'. LO_COL->SET_LONG_TEXT( LV_LTXT ). LV_MTXT = 'Session ID'. LO_COL->SET_MEDIUM_TEXT( LV_MTXT ). LV_STXT = 'Session'. LO_COL->SET_SHORT_TEXT( LV_STXT ).
  CATCH CX_SALV_NOT_FOUND. ENDTRY.
  TRY. LO_COL = LO_COLS->GET_COLUMN( 'ROW_INDEX' ).
    LV_LTXT = 'Row'. LO_COL->SET_LONG_TEXT( LV_LTXT ). LV_MTXT = 'Row'. LO_COL->SET_MEDIUM_TEXT( LV_MTXT ). LV_STXT = 'Row'. LO_COL->SET_SHORT_TEXT( LV_STXT ).
  CATCH CX_SALV_NOT_FOUND. ENDTRY.
  TRY. LO_COL = LO_COLS->GET_COLUMN( 'TCODE' ).
    LV_LTXT = 'Transaction'. LO_COL->SET_LONG_TEXT( LV_LTXT ). LV_MTXT = 'TCode'. LO_COL->SET_MEDIUM_TEXT( LV_MTXT ). LV_STXT = 'TCode'. LO_COL->SET_SHORT_TEXT( LV_STXT ).
  CATCH CX_SALV_NOT_FOUND. ENDTRY.
  TRY. LO_COL = LO_COLS->GET_COLUMN( 'RECORD_KEY' ).
    LV_LTXT = 'Record Key'. LO_COL->SET_LONG_TEXT( LV_LTXT ). LV_MTXT = 'Record Key'. LO_COL->SET_MEDIUM_TEXT( LV_MTXT ). LV_STXT = 'Key'. LO_COL->SET_SHORT_TEXT( LV_STXT ).
  CATCH CX_SALV_NOT_FOUND. ENDTRY.
  TRY. LO_COL = LO_COLS->GET_COLUMN( 'STATUS' ).
    LV_LTXT = 'Status'. LO_COL->SET_LONG_TEXT( LV_LTXT ). LV_MTXT = 'Status'. LO_COL->SET_MEDIUM_TEXT( LV_MTXT ). LV_STXT = 'Status'. LO_COL->SET_SHORT_TEXT( LV_STXT ).
  CATCH CX_SALV_NOT_FOUND. ENDTRY.
  TRY. LO_COL = LO_COLS->GET_COLUMN( 'ERROR_MSG' ).
    LV_LTXT = 'Error Message'. LO_COL->SET_LONG_TEXT( LV_LTXT ). LV_MTXT = 'Message'. LO_COL->SET_MEDIUM_TEXT( LV_MTXT ). LV_STXT = 'Message'. LO_COL->SET_SHORT_TEXT( LV_STXT ).
  CATCH CX_SALV_NOT_FOUND. ENDTRY.

  DO 25 TIMES.
    LV_NR = SY-INDEX.
    CONCATENATE 'FIELD' LV_NR INTO LV_FN.
    TRY.
        LO_COL = LO_COLS->GET_COLUMN( LV_FN ).
        READ TABLE LT_MAP INTO LS_MAP WITH KEY STAGING_FIELD = LV_FN.
        IF SY-SUBRC = 0.
          LV_LTXT = LS_MAP-SOURCE_COLUMN. LV_MTXT = LS_MAP-SOURCE_COLUMN. LV_STXT = LS_MAP-SOURCE_COLUMN.
          LO_COL->SET_LONG_TEXT( LV_LTXT ). LO_COL->SET_MEDIUM_TEXT( LV_MTXT ). LO_COL->SET_SHORT_TEXT( LV_STXT ).
          LO_COL->SET_VISIBLE( ABAP_TRUE ).
        ELSE.
          LO_COL->SET_VISIBLE( ABAP_FALSE ).
        ENDIF.
      CATCH CX_SALV_NOT_FOUND.
    ENDTRY.
  ENDDO.
ENDFORM.
*<<< END FORM SET_SALV_COLUMN_NAMES

*>>> FORM SET_FCAT_DYNAMIC_NAMES - moved from Z_BDC_MASS_PO_ENTRY_F01_BUP

FORM SET_FCAT_DYNAMIC_NAMES CHANGING PT_FCAT TYPE LVC_T_FCAT.
  DATA: LT_MAP   TYPE STANDARD TABLE OF zbdc_mapping_bup,
        LS_MAP   TYPE zbdc_mapping_bup,
        LV_FN    TYPE CHAR10,
        LV_CHECK TYPE CHAR5,
        LV_LTXT  TYPE SCRTEXT_L,
        LV_MTXT  TYPE SCRTEXT_M,
        LV_STXT  TYPE SCRTEXT_S,
        LV_REP   TYPE REPTEXT.

  SELECT PROFILE_NAME, SOURCE_COLUMN, STAGING_FIELD, BDC_FIELD, MANDATORY
    FROM zbdc_mapping_bup
    WHERE PROFILE_NAME = @TXTP_PROFILE_NAME
    INTO CORRESPONDING FIELDS OF TABLE @LT_MAP.

  LOOP AT PT_FCAT ASSIGNING FIELD-SYMBOL(<FC>).
    LV_FN = <FC>-FIELDNAME.
    READ TABLE LT_MAP INTO LS_MAP WITH KEY STAGING_FIELD = LV_FN.
    IF SY-SUBRC = 0.
      LV_LTXT = LS_MAP-SOURCE_COLUMN. LV_MTXT = LS_MAP-SOURCE_COLUMN.
      LV_STXT = LS_MAP-SOURCE_COLUMN. LV_REP  = LS_MAP-SOURCE_COLUMN.
      <FC>-SCRTEXT_L = LV_LTXT. <FC>-SCRTEXT_M = LV_MTXT.
      <FC>-SCRTEXT_S = LV_STXT. <FC>-REPTEXT   = LV_REP.
      <FC>-NO_OUT    = SPACE.   <FC>-EDIT      = 'X'.
    ELSE.
      LV_CHECK = LV_FN(5).
      IF LV_CHECK = 'FIELD'. <FC>-NO_OUT = 'X'. ENDIF.
    ENDIF.
  ENDLOOP.
ENDFORM.
*<<< END FORM SET_FCAT_DYNAMIC_NAMES

*>>> FORM PREPARE_ALV_0400 - moved from Z_BDC_MASS_PO_ENTRY_F01_BUP

FORM PREPARE_ALV_0400.
*&---------------------------------------------------------------------*
*& 3-LAYER VALIDATION - re nhanh theo TCODE cua tung dong
*&---------------------------------------------------------------------*
  DATA: LS_ALV TYPE TY_STAGING_ALV.
  DATA: LT_MAP TYPE STANDARD TABLE OF zbdc_mapping_bup, LS_MAP TYPE zbdc_mapping_bup, LV_VAL TYPE STRING.
  DATA: LV_LIFNR_CHK TYPE LIFNR, LV_MATNR_CHK TYPE MATNR, LS_SCOL TYPE LVC_S_SCOL.
  DATA: LV_EBELN_CHK TYPE EBELN, LV_EBELP_CHK TYPE EBELP.
  DATA: LV_SRCCOL TYPE STRING.
  DATA: LV_MATNR_L3 TYPE MATNR, LV_WERKS_L3 TYPE WERKS_D,
        LV_EBELN_L3 TYPE EBELN, LV_EBELP_L3 TYPE EBELP,
        LV_LGORT_L3 TYPE LGORT_D,
        LV_FN_MATNR TYPE LVC_FNAME, LV_FN_WERKS TYPE LVC_FNAME,
        LV_FN_EBELN TYPE LVC_FNAME, LV_FN_EBELP TYPE LVC_FNAME,
        LV_FN_LGORT TYPE LVC_FNAME.
  FIELD-SYMBOLS: <FS_ALV> TYPE TY_STAGING_ALV, <FV> TYPE ANY.

  SELECT * FROM zbdc_mapping_bup WHERE PROFILE_NAME = @TXTP_PROFILE_NAME INTO TABLE @LT_MAP.

  CLEAR GT_STAGING_ALV.
  LOOP AT GT_STAGING INTO DATA(LS_STG). CLEAR LS_ALV. MOVE-CORRESPONDING LS_STG TO LS_ALV. APPEND LS_ALV TO GT_STAGING_ALV. ENDLOOP.

  LOOP AT GT_STAGING_ALV ASSIGNING <FS_ALV> WHERE STATUS = 'STAGED'.
    <FS_ALV>-STATUS = 'READY'. CLEAR: <FS_ALV>-ERROR_MSG, <FS_ALV>-CELL_COLORS.
    CLEAR: LV_MATNR_L3, LV_WERKS_L3, LV_EBELN_L3, LV_EBELP_L3, LV_LGORT_L3,
           LV_FN_MATNR, LV_FN_WERKS, LV_FN_EBELN, LV_FN_EBELP, LV_FN_LGORT.

    LOOP AT LT_MAP INTO LS_MAP.
      ASSIGN COMPONENT LS_MAP-STAGING_FIELD OF STRUCTURE <FS_ALV> TO <FV>.
      IF SY-SUBRC = 0.
        LV_VAL = <FV>. CONDENSE LV_VAL.
        DATA(LV_IS_ERROR) = ABAP_FALSE.

        IF LS_MAP-MANDATORY = 'X' AND LV_VAL IS INITIAL.
          LV_IS_ERROR = ABAP_TRUE. <FS_ALV>-ERROR_MSG = |{ <FS_ALV>-ERROR_MSG } Thieu { LS_MAP-SOURCE_COLUMN };|.
        ENDIF.

        IF LV_VAL IS NOT INITIAL.
          LV_SRCCOL = LS_MAP-SOURCE_COLUMN.
          TRANSLATE LV_SRCCOL TO UPPER CASE. CONDENSE LV_SRCCOL NO-GAPS.

          IF <FS_ALV>-TCODE = 'MIGO'.
            CASE LV_SRCCOL.
              WHEN 'PO_NUMBER'.
                LV_EBELN_CHK = LV_VAL.
                CALL FUNCTION 'CONVERSION_EXIT_ALPHA_INPUT' EXPORTING INPUT = LV_EBELN_CHK IMPORTING OUTPUT = LV_EBELN_CHK.
                SELECT SINGLE EBELN FROM EKKO INTO @DATA(LV_EBELN_DB) WHERE EBELN = @LV_EBELN_CHK.
                IF SY-SUBRC <> 0.
                  LV_IS_ERROR = ABAP_TRUE. <FS_ALV>-ERROR_MSG = |{ <FS_ALV>-ERROR_MSG } PO { LV_VAL } khong ton tai;|.
                ELSE.
                  LV_EBELN_L3 = LV_EBELN_CHK. LV_FN_EBELN = LS_MAP-STAGING_FIELD.
                ENDIF.
              WHEN 'PO_ITEM'.
                TRY.
                    LV_EBELP_CHK = LV_VAL.
                    LV_EBELP_L3 = LV_EBELP_CHK. LV_FN_EBELP = LS_MAP-STAGING_FIELD.
                  CATCH CX_ROOT.
                    LV_IS_ERROR = ABAP_TRUE. <FS_ALV>-ERROR_MSG = |{ <FS_ALV>-ERROR_MSG } PO_ITEM { LV_VAL } ko hop le;|.
                ENDTRY.
              WHEN 'QUANTITY'.
                TRY.
                    DATA(LV_QTY_M) = CONV MNG06( LV_VAL ).
                    IF LV_QTY_M <= 0. LV_IS_ERROR = ABAP_TRUE. <FS_ALV>-ERROR_MSG = |{ <FS_ALV>-ERROR_MSG } SL phai > 0;|. ENDIF.
                  CATCH CX_ROOT. LV_IS_ERROR = ABAP_TRUE. <FS_ALV>-ERROR_MSG = |{ <FS_ALV>-ERROR_MSG } SL ko hop le;|.
                ENDTRY.
              WHEN 'STOR_LOC'.
                LV_LGORT_L3 = LV_VAL. LV_FN_LGORT = LS_MAP-STAGING_FIELD.
            ENDCASE.

          ELSE.
            CASE LS_MAP-BDC_FIELD.
              WHEN 'EKKO-LIFNR'.
                LV_LIFNR_CHK = LV_VAL.
                CALL FUNCTION 'CONVERSION_EXIT_ALPHA_INPUT' EXPORTING INPUT = LV_LIFNR_CHK IMPORTING OUTPUT = LV_LIFNR_CHK.
                SELECT SINGLE LIFNR FROM LFA1 INTO @DATA(LV_LIFNR) WHERE LIFNR = @LV_LIFNR_CHK.
                IF SY-SUBRC <> 0. LV_IS_ERROR = ABAP_TRUE. <FS_ALV>-ERROR_MSG = |{ <FS_ALV>-ERROR_MSG } NCC { LV_VAL } sai;|. ENDIF.
              WHEN 'EKKO-EKORG'.
                SELECT SINGLE EKORG FROM T024E INTO @DATA(LV_EKORG) WHERE EKORG = @LV_VAL.
                IF SY-SUBRC <> 0. LV_IS_ERROR = ABAP_TRUE. <FS_ALV>-ERROR_MSG = |{ <FS_ALV>-ERROR_MSG } Org sai;|. ENDIF.
              WHEN 'EKKO-EKGRP'.
                SELECT SINGLE EKGRP FROM T024 INTO @DATA(LV_EKGRP) WHERE EKGRP = @LV_VAL.
                IF SY-SUBRC <> 0. LV_IS_ERROR = ABAP_TRUE. <FS_ALV>-ERROR_MSG = |{ <FS_ALV>-ERROR_MSG } Nhom mua { LV_VAL } sai;|. ENDIF.
              WHEN 'EKPO-MATNR'.
                LV_MATNR_CHK = LV_VAL.
                CALL FUNCTION 'CONVERSION_EXIT_MATN1_INPUT' EXPORTING INPUT = LV_MATNR_CHK IMPORTING OUTPUT = LV_MATNR_CHK.
                SELECT SINGLE MATNR FROM MARA INTO @DATA(LV_MATNR) WHERE MATNR = @LV_MATNR_CHK.
                IF SY-SUBRC <> 0.
                  LV_IS_ERROR = ABAP_TRUE. <FS_ALV>-ERROR_MSG = |{ <FS_ALV>-ERROR_MSG } VT { LV_VAL } sai;|.
                ELSE.
                  LV_MATNR_L3 = LV_MATNR_CHK. LV_FN_MATNR = LS_MAP-STAGING_FIELD.
                ENDIF.
              WHEN 'EKPO-WERKS'.
                SELECT SINGLE WERKS FROM T001W INTO @DATA(LV_WERKS) WHERE WERKS = @LV_VAL.
                IF SY-SUBRC <> 0.
                  LV_IS_ERROR = ABAP_TRUE. <FS_ALV>-ERROR_MSG = |{ <FS_ALV>-ERROR_MSG } Plant sai;|.
                ELSE.
                  LV_WERKS_L3 = LV_VAL. LV_FN_WERKS = LS_MAP-STAGING_FIELD.
                ENDIF.
              WHEN 'EKPO-MENGE'.
                TRY.
                    DATA(LV_NUM) = CONV MNG06( LV_VAL ).
                    IF LV_NUM <= 0. LV_IS_ERROR = ABAP_TRUE. <FS_ALV>-ERROR_MSG = |{ <FS_ALV>-ERROR_MSG } SL sai;|. ENDIF.
                  CATCH CX_ROOT. LV_IS_ERROR = ABAP_TRUE. <FS_ALV>-ERROR_MSG = |{ <FS_ALV>-ERROR_MSG } SL ko hop le;|.
                ENDTRY.
            ENDCASE.
          ENDIF.
        ENDIF.

        IF LV_IS_ERROR = ABAP_TRUE.
          <FS_ALV>-STATUS = 'ERROR'.
          LS_SCOL-FNAME = LS_MAP-STAGING_FIELD. LS_SCOL-COLOR-COL = 6. LS_SCOL-COLOR-INT = 1. LS_SCOL-COLOR-INV = 0.
          APPEND LS_SCOL TO <FS_ALV>-CELL_COLORS.
        ENDIF.
      ENDIF.
    ENDLOOP.

    IF <FS_ALV>-TCODE = 'ME21N'.
      IF LV_MATNR_L3 IS NOT INITIAL AND LV_WERKS_L3 IS NOT INITIAL.
        SELECT SINGLE MATNR FROM MARC INTO @DATA(LV_MARC) WHERE MATNR = @LV_MATNR_L3 AND WERKS = @LV_WERKS_L3.
        IF SY-SUBRC <> 0.
          <FS_ALV>-STATUS = 'ERROR'.
          <FS_ALV>-ERROR_MSG = |{ <FS_ALV>-ERROR_MSG } VT chua duoc tao o Plant { LV_WERKS_L3 };|.
          LS_SCOL-FNAME = LV_FN_MATNR. LS_SCOL-COLOR-COL = 6. LS_SCOL-COLOR-INT = 1. LS_SCOL-COLOR-INV = 0.
          APPEND LS_SCOL TO <FS_ALV>-CELL_COLORS.
          LS_SCOL-FNAME = LV_FN_WERKS.
          APPEND LS_SCOL TO <FS_ALV>-CELL_COLORS.
        ENDIF.
      ENDIF.

    ELSEIF <FS_ALV>-TCODE = 'MIGO'.
      IF LV_EBELN_L3 IS NOT INITIAL AND LV_EBELP_L3 IS NOT INITIAL.
        SELECT SINGLE EBELP, LOEKZ, WERKS FROM EKPO
          INTO @DATA(LS_EKPO_CHK)
          WHERE EBELN = @LV_EBELN_L3 AND EBELP = @LV_EBELP_L3.
        IF SY-SUBRC <> 0.
          <FS_ALV>-STATUS = 'ERROR'.
          <FS_ALV>-ERROR_MSG = |{ <FS_ALV>-ERROR_MSG } Item { LV_EBELP_L3 } khong co trong PO { LV_EBELN_L3 };|.
          LS_SCOL-FNAME = LV_FN_EBELP. LS_SCOL-COLOR-COL = 6. LS_SCOL-COLOR-INT = 1. LS_SCOL-COLOR-INV = 0.
          APPEND LS_SCOL TO <FS_ALV>-CELL_COLORS.
        ELSEIF LS_EKPO_CHK-LOEKZ IS NOT INITIAL.
          <FS_ALV>-STATUS = 'ERROR'.
          <FS_ALV>-ERROR_MSG = |{ <FS_ALV>-ERROR_MSG } Item { LV_EBELP_L3 } cua PO da bi xoa;|.
          LS_SCOL-FNAME = LV_FN_EBELP. LS_SCOL-COLOR-COL = 6. LS_SCOL-COLOR-INT = 1. LS_SCOL-COLOR-INV = 0.
          APPEND LS_SCOL TO <FS_ALV>-CELL_COLORS.
        ELSE.
          IF LV_LGORT_L3 IS NOT INITIAL AND LS_EKPO_CHK-WERKS IS NOT INITIAL.
            SELECT SINGLE LGORT FROM T001L INTO @DATA(LV_T001L)
              WHERE WERKS = @LS_EKPO_CHK-WERKS AND LGORT = @LV_LGORT_L3.
            IF SY-SUBRC <> 0.
              <FS_ALV>-STATUS = 'ERROR'.
              <FS_ALV>-ERROR_MSG = |{ <FS_ALV>-ERROR_MSG } Kho { LV_LGORT_L3 } ko co o Plant { LS_EKPO_CHK-WERKS };|.
              LS_SCOL-FNAME = LV_FN_LGORT. LS_SCOL-COLOR-COL = 6. LS_SCOL-COLOR-INT = 1. LS_SCOL-COLOR-INV = 0.
              APPEND LS_SCOL TO <FS_ALV>-CELL_COLORS.
            ENDIF.
          ENDIF.
        ENDIF.
      ENDIF.
    ENDIF.

    SHIFT <FS_ALV>-ERROR_MSG LEFT DELETING LEADING SPACE.
  ENDLOOP.

  LOOP AT GT_STAGING_ALV INTO DATA(LS_ALV_FINAL).
    READ TABLE GT_STAGING ASSIGNING FIELD-SYMBOL(<FS_STG_ORIG>) WITH KEY SESSION_ID = LS_ALV_FINAL-SESSION_ID ROW_INDEX = LS_ALV_FINAL-ROW_INDEX.
    IF SY-SUBRC = 0. <FS_STG_ORIG>-STATUS = LS_ALV_FINAL-STATUS. <FS_STG_ORIG>-ERROR_MSG = LS_ALV_FINAL-ERROR_MSG. ENDIF.
  ENDLOOP.

  "FIX16: optional dynamic rules from ZBDC_VRULE_BUP, then persist structured errors.
  PERFORM Z16_APPLY_DYNAMIC_RULES.
  PERFORM Z16_SYNC_STAGING_FROM_ALV.
  PERFORM Z16_WRITE_STRUCTURED_ERRORS.

  IF GT_STAGING IS NOT INITIAL. MODIFY zbdc_staging_bup FROM TABLE gt_staging. ENDIF.
ENDFORM.
*<<< END FORM PREPARE_ALV_0400

*>>> FORM RESET_0300_ALV - moved from Z_BDC_MASS_PO_ENTRY_F01_BUP

FORM RESET_0300_ALV.
  "FIX8b: KHONG free container/grid cua 0301 nua.
  "Ly do: FREE + CREATE OBJECT lai trong CUNG 1 vong PAI->PBO (khong doi dynpro)
  "khien SAP GUI Control Framework khong repaint container ngay - grid trong den
  "khi user chuyen tab sang 0302 roi quay lai 0301 (buoc do moi force ve lai).
  "MODULE status_0301 OUTPUT da co san nhanh xu ly dung khi container con song:
  "   IF go_grid_0301 IS BOUND. go_grid_0301->refresh(...). go_grid_0301->display( ). ENDIF.
  "Nen chi can giu container/grid 0301 song va goi refresh() la du, khong can pha di tao lai.
  IF GO_GRID_0302 IS BOUND.
    FREE GO_GRID_0302.
  ENDIF.
  IF GO_CONTAINER_0302 IS BOUND.
    FREE GO_CONTAINER_0302.
  ENDIF.
  CLEAR: GO_GRID_0302, GO_CONTAINER_0302.
ENDFORM.
*<<< END FORM RESET_0300_ALV

*>>> FORM z16_reset_0300_all_alv - moved from Z_BDC_MASS_PO_ENTRY_F01_BUP

FORM z16_reset_0300_all_alv.
  "Use only when leaving/re-entering 0300. During upload refresh keep 0301 alive.
  IF go_alv_0301 IS BOUND.
    FREE go_alv_0301.
  ENDIF.
  IF go_grid_0301 IS BOUND.
    FREE go_grid_0301.
  ENDIF.
  IF go_container_0301 IS BOUND.
    CALL METHOD go_container_0301->free
      EXCEPTIONS
        cntl_error        = 1
        cntl_system_error = 2
        OTHERS            = 3.
    FREE go_container_0301.
  ENDIF.
  IF go_grid_0302 IS BOUND.
    FREE go_grid_0302.
  ENDIF.
  IF go_container_0302 IS BOUND.
    FREE go_container_0302.
  ENDIF.
  CLEAR: go_alv_0301, go_grid_0301, go_container_0301,
         go_grid_0302, go_container_0302.
ENDFORM.
*<<< END FORM z16_reset_0300_all_alv

*>>> FORM z16_sync_0400_scope - moved from Z_BDC_MASS_PO_ENTRY_F01_BUP

FORM z16_sync_0400_scope.
  "V5T: 0400 must always represent the exact data currently held by 0300.
  "Never reuse a batch/session prefix left over from an older upload.
  DATA: ls_first_0400 TYPE zbdc_staging_bup,
        ls_row_0400   TYPE zbdc_staging_bup,
        lv_first_sid  TYPE zbdc_staging_bup-session_id,
        lv_first_bat  TYPE zbdc_staging_bup-session_id,
        lv_row_bat    TYPE zbdc_staging_bup-session_id,
        lv_seen_sid   TYPE zbdc_staging_bup-session_id,
        lv_same_batch TYPE abap_bool.

  REFRESH gt_current_sessions.
  CLEAR: gv_current_batch_prefix, txtp_session_id, txtp_sess.

  READ TABLE gt_staging INTO ls_first_0400 INDEX 1.
  IF sy-subrc <> 0.
    RETURN.
  ENDIF.

  lv_first_sid = ls_first_0400-session_id.
  PERFORM z16_batch_prefix_from_sid
    USING    lv_first_sid
    CHANGING lv_first_bat.
  IF lv_first_bat IS INITIAL.
    lv_first_bat = lv_first_sid.
  ENDIF.

  lv_same_batch = abap_true.

  LOOP AT gt_staging INTO ls_row_0400.
    IF ls_row_0400-session_id IS NOT INITIAL.
      CLEAR lv_seen_sid.
      READ TABLE gt_current_sessions INTO lv_seen_sid
        WITH KEY table_line = ls_row_0400-session_id.
      IF sy-subrc <> 0.
        APPEND ls_row_0400-session_id TO gt_current_sessions.
      ENDIF.

      CLEAR lv_row_bat.
      PERFORM z16_batch_prefix_from_sid
        USING    ls_row_0400-session_id
        CHANGING lv_row_bat.
      IF lv_row_bat IS INITIAL.
        lv_row_bat = ls_row_0400-session_id.
      ENDIF.
      IF lv_row_bat <> lv_first_bat.
        lv_same_batch = abap_false.
      ENDIF.
    ENDIF.
  ENDLOOP.

  IF lv_same_batch = abap_true.
    gv_current_batch_prefix = lv_first_bat.
    txtp_session_id         = lv_first_bat.
    txtp_sess               = lv_first_bat.
  ELSE.
    "Mixed unrelated sessions: show the first real session and avoid a false
    "LIKE-prefix query against result logs.
    CLEAR gv_current_batch_prefix.
    txtp_session_id = lv_first_sid.
    txtp_sess       = lv_first_sid.
  ENDIF.

  IF ls_first_0400-tcode IS NOT INITIAL.
    p_transaction = ls_first_0400-tcode.
    PERFORM resolve_profile_by_tcode USING ls_first_0400-tcode.
  ENDIF.
ENDFORM.
*<<< END FORM z16_sync_0400_scope

*>>> FORM OPEN_0400_FOR_CURRENT_STAGING - moved from Z_BDC_MASS_PO_ENTRY_F01_BUP


FORM OPEN_0400_FOR_CURRENT_STAGING.
  PERFORM z19_reset_0400_selection.
  IF GT_STAGING IS INITIAL.
    MESSAGE 'Khong co staging data de mo Execution Cockpit.' TYPE 'W'.
    RETURN.
  ENDIF.

  PERFORM z16_sync_0400_scope.

  GV_0400_VIEW      = GC_VIEW_COCKPIT.
  GV_0400_EDIT_MODE = SPACE.

  PERFORM FREE_0400_GRID.
  REFRESH: GT_STAGING_ALV, GT_EXEC_DISP.
  PERFORM PREPARE_ALV_0400.

  CALL SCREEN 0400.
ENDFORM.
*<<< END FORM OPEN_0400_FOR_CURRENT_STAGING

*>>> FORM z19_open_0400_empty - moved from Z_BDC_MASS_PO_ENTRY_F01_BUP

FORM z19_open_0400_empty.
  "Opening Staging without an explicit upload/session must never resurrect
  "the latest historical batch. The user gets a clean, zero-row workspace.
  PERFORM z19_reset_0400_selection.
  CLEAR: gt_staging, gt_staging_alv, gt_exec_disp,
         gv_current_batch_prefix, gv_ingest_batch_prefix,
         txtp_session_id, txtp_sess,
         txtgv_tot, txtgv_total, txtgv_suc, txtgv_suc_count, txtgv_ok,
         txtgv_err, txtgv_war, txtgv_warning,
         gv_exec_header_txt, gv_exec_progress.
  gv_0400_view      = gc_view_cockpit.
  gv_0400_edit_mode = space.
  PERFORM free_0400_grid.
  CALL SCREEN 0400.
ENDFORM.
*<<< END FORM z19_open_0400_empty

*>>> FORM OPEN_0400_LATEST_FOR_TCODE - moved from Z_BDC_MASS_PO_ENTRY_F01_BUP

FORM OPEN_0400_LATEST_FOR_TCODE USING IV_TCODE TYPE CHAR20.
  DATA LV_COUNT TYPE I.

  PERFORM LOAD_LATEST_STAGING_FOR_TCODE USING IV_TCODE CHANGING LV_COUNT.
  IF LV_COUNT <= 0.
    MESSAGE |Khong co du lieu { IV_TCODE } READY/STAGED trong ZBDC_STAGING_BUP.| TYPE 'W'.
    RETURN.
  ENDIF.

  PERFORM OPEN_0400_FOR_CURRENT_STAGING.
ENDFORM.

*&---------------------------------------------------------------------*
*& GET_RUNTIME_OPTIONS - gom logic option ve 1 noi, khong lap PAI/PBO
*&---------------------------------------------------------------------*
*<<< END FORM OPEN_0400_LATEST_FOR_TCODE

*>>> FORM UPDATE_GROUP_RESULT - moved from Z_BDC_MASS_PO_ENTRY_F01_BUP
FORM UPDATE_GROUP_RESULT USING PT_GROUP  TYPE TY_T_STAGING_ALV
                               PV_STATUS TYPE ANY
                               PV_MSG    TYPE STRING
                               PV_OBJ    TYPE ANY.
  DATA: LS_G      TYPE TY_STAGING_ALV,
        LS_STG    TYPE ZBDC_STAGING_BUP,
        LT_STG_DB TYPE STANDARD TABLE OF ZBDC_STAGING_BUP,
        LS_RES    TYPE ZBDC_RESULT_BUP,
        LV_TYPE   TYPE C LENGTH 1.

  FIELD-SYMBOLS: <FS_ALV> TYPE TY_STAGING_ALV,
                 <FS_STG> TYPE ZBDC_STAGING_BUP,
                 <FV>     TYPE ANY.

  LOOP AT PT_GROUP INTO LS_G.
    MOVE-CORRESPONDING LS_G TO LS_STG.
    LS_STG-STATUS    = PV_STATUS.
    LS_STG-ERROR_MSG = PV_MSG.
    APPEND LS_STG TO LT_STG_DB.

    READ TABLE GT_STAGING_ALV ASSIGNING <FS_ALV>
      WITH KEY SESSION_ID = LS_G-SESSION_ID ROW_INDEX = LS_G-ROW_INDEX.
    IF SY-SUBRC = 0.
      <FS_ALV>-STATUS = PV_STATUS.
      <FS_ALV>-ERROR_MSG = PV_MSG.
    ENDIF.

    READ TABLE GT_STAGING ASSIGNING <FS_STG>
      WITH KEY SESSION_ID = LS_G-SESSION_ID ROW_INDEX = LS_G-ROW_INDEX.
    IF SY-SUBRC = 0.
      <FS_STG>-STATUS = PV_STATUS.
      <FS_STG>-ERROR_MSG = PV_MSG.
    ENDIF.
  ENDLOOP.

  IF LT_STG_DB IS NOT INITIAL.
    MODIFY ZBDC_STAGING_BUP FROM TABLE LT_STG_DB.
  ENDIF.

  READ TABLE PT_GROUP INTO LS_G INDEX 1.
  IF SY-SUBRC <> 0.
    RETURN.
  ENDIF.

  IF PV_STATUS = GC_ST_SUCCESS.
    LV_TYPE = 'S'.
  ELSEIF PV_STATUS = GC_ST_WARNING.
    LV_TYPE = 'W'.
  ELSEIF PV_STATUS = GC_ST_SM35Q.
    LV_TYPE = 'I'.
  ELSE.
    LV_TYPE = 'E'.
  ENDIF.

  CLEAR LS_RES.
  ASSIGN COMPONENT 'SESSION_ID'    OF STRUCTURE LS_RES TO <FV>. IF SY-SUBRC = 0. <FV> = LS_G-SESSION_ID. ENDIF.
  ASSIGN COMPONENT 'SAP_OBJECT_ID' OF STRUCTURE LS_RES TO <FV>. IF SY-SUBRC = 0. <FV> = PV_OBJ. ENDIF.
  ASSIGN COMPONENT 'MSG_TYPE'      OF STRUCTURE LS_RES TO <FV>. IF SY-SUBRC = 0. <FV> = LV_TYPE. ENDIF.
  ASSIGN COMPONENT 'MESSAGE'       OF STRUCTURE LS_RES TO <FV>. IF SY-SUBRC = 0. <FV> = PV_MSG. ENDIF.
  ASSIGN COMPONENT 'RECORD_KEY'    OF STRUCTURE LS_RES TO <FV>. IF SY-SUBRC = 0. <FV> = LS_G-RECORD_KEY. ENDIF.
  ASSIGN COMPONENT 'TCODE'         OF STRUCTURE LS_RES TO <FV>. IF SY-SUBRC = 0. <FV> = LS_G-TCODE. ENDIF.
  ASSIGN COMPONENT 'ROW_INDEX'     OF STRUCTURE LS_RES TO <FV>. IF SY-SUBRC = 0. <FV> = LS_G-ROW_INDEX. ENDIF.
  ASSIGN COMPONENT 'CREATED_AT'    OF STRUCTURE LS_RES TO <FV>. IF SY-SUBRC = 0. <FV> = SY-DATUM. ENDIF.
  ASSIGN COMPONENT 'CREATED_TM'    OF STRUCTURE LS_RES TO <FV>. IF SY-SUBRC = 0. <FV> = SY-UZEIT. ENDIF.
  ASSIGN COMPONENT 'CREATED_BY'    OF STRUCTURE LS_RES TO <FV>. IF SY-SUBRC = 0. <FV> = SY-UNAME. ENDIF.

  MODIFY ZBDC_RESULT_BUP FROM LS_RES.
ENDFORM.

*&---------------------------------------------------------------------*
*& PROCESS_NEXT_BDC_RECORD - Phase 8: run next READY group/record
*&---------------------------------------------------------------------*
*<<< END FORM UPDATE_GROUP_RESULT

*>>> FORM BUILD_EXEC_COCKPIT - moved from Z_BDC_MASS_PO_ENTRY_F01_BUP

FORM BUILD_EXEC_COCKPIT.
  DATA: LT_RES      TYPE STANDARD TABLE OF ZBDC_RESULT_BUP,
        LS_EXEC     TYPE TY_EXEC_DISP,
        LV_KEY      TYPE ZBDC_STAGING_BUP-RECORD_KEY,
        LV_ALL_OK   TYPE ABAP_BOOL,
        LV_ALL_SM35 TYPE ABAP_BOOL,
        LV_BATCH_LIKE TYPE STRING,
        LS_COLOR    TYPE LVC_S_SCOL.

  FIELD-SYMBOLS: <FS_ALV>  TYPE TY_STAGING_ALV,
                 <FS_EXEC> TYPE TY_EXEC_DISP.

  "V5AC: row selection is maintained by CL_GUI_ALV_GRID, not in business data.

  REFRESH GT_EXEC_DISP.
  CLEAR: GV_EXEC_TOTAL_GRP, GV_EXEC_READY_GRP, GV_EXEC_SUCC_GRP,
         GV_EXEC_ERR_GRP, GV_EXEC_WARN_GRP, GV_EXEC_SM35_GRP,
         GV_EXEC_RETRY_GRP,
         GV_EXEC_PROGRESS, GV_EXEC_HEADER_TXT.

  IF GT_STAGING_ALV IS INITIAL AND GT_STAGING IS NOT INITIAL.
    PERFORM PREPARE_ALV_0400.
  ENDIF.

  IF GT_STAGING_ALV IS NOT INITIAL.
    READ TABLE GT_STAGING_ALV INTO DATA(LS_SESS_FOR_RES) INDEX 1.
    IF SY-SUBRC = 0.
      IF gv_current_batch_prefix IS NOT INITIAL.
        LV_BATCH_LIKE = gv_current_batch_prefix && '%'.
        SELECT * FROM ZBDC_RESULT_BUP
          INTO TABLE @LT_RES
          WHERE SESSION_ID LIKE @LV_BATCH_LIKE.
      ELSE.
        SELECT * FROM ZBDC_RESULT_BUP
          INTO TABLE @LT_RES
          WHERE SESSION_ID = @LS_SESS_FOR_RES-SESSION_ID.
      ENDIF.
    ENDIF.
  ENDIF.

  "Group-level display: one row = one business document group (PO_KEY / RECORD_KEY).
  LOOP AT GT_STAGING_ALV ASSIGNING <FS_ALV>.
    LV_KEY = <FS_ALV>-RECORD_KEY.
    IF LV_KEY IS INITIAL.
      LV_KEY = <FS_ALV>-ROW_INDEX.
    ENDIF.

    READ TABLE GT_EXEC_DISP ASSIGNING <FS_EXEC>
      WITH KEY SESSION_ID = <FS_ALV>-SESSION_ID GROUP_KEY = LV_KEY.

    IF SY-SUBRC <> 0.
      CLEAR LS_EXEC.
      PERFORM z16_batch_prefix_from_sid USING <FS_ALV>-SESSION_ID CHANGING LS_EXEC-BATCH_KEY.
      DATA lv_unit_raw_0400 TYPE string.
      SELECT SINGLE file_name FROM zbdc_file_lg_bup
        WHERE session_id = @<FS_ALV>-SESSION_ID
        INTO @lv_unit_raw_0400.
      IF lv_unit_raw_0400 IS INITIAL.
        lv_unit_raw_0400 = <FS_ALV>-SESSION_ID.
      ENDIF.
      PERFORM z16_split_unit_name USING lv_unit_raw_0400 CHANGING LS_EXEC-SOURCE_FILE LS_EXEC-SHEET_NAME.
      LS_EXEC-SESSION_ID = <FS_ALV>-SESSION_ID.
      LS_EXEC-GROUP_KEY  = LV_KEY.
      LS_EXEC-TCODE      = <FS_ALV>-TCODE.
      IF LS_EXEC-TCODE IS INITIAL.
        LS_EXEC-TCODE = P_TRANSACTION.
      ENDIF.
      LS_EXEC-DRILL_TCODE = 'DISPLAY'.
      APPEND LS_EXEC TO GT_EXEC_DISP.
      READ TABLE GT_EXEC_DISP ASSIGNING <FS_EXEC> INDEX LINES( GT_EXEC_DISP ).
    ENDIF.

    <FS_EXEC>-ITEM_COUNT = <FS_EXEC>-ITEM_COUNT + 1.

    CASE <FS_ALV>-STATUS.
      WHEN GC_ST_SUCCESS.
        <FS_EXEC>-SUCCESS_COUNT = <FS_EXEC>-SUCCESS_COUNT + 1.
      WHEN GC_ST_ERROR.
        <FS_EXEC>-ERROR_COUNT = <FS_EXEC>-ERROR_COUNT + 1.
        IF <FS_EXEC>-MESSAGE IS INITIAL.
          <FS_EXEC>-MESSAGE = <FS_ALV>-ERROR_MSG.
        ENDIF.
      WHEN GC_ST_WARNING.
        <FS_EXEC>-WARNING_COUNT = <FS_EXEC>-WARNING_COUNT + 1.
        IF <FS_EXEC>-MESSAGE IS INITIAL.
          <FS_EXEC>-MESSAGE = <FS_ALV>-ERROR_MSG.
        ENDIF.
      WHEN GC_ST_SM35Q.
        <FS_EXEC>-SM35_COUNT = <FS_EXEC>-SM35_COUNT + 1.
        IF <FS_EXEC>-MESSAGE IS INITIAL.
          <FS_EXEC>-MESSAGE = <FS_ALV>-ERROR_MSG.
        ENDIF.
      WHEN GC_ST_READY.
        <FS_EXEC>-READY_COUNT = <FS_EXEC>-READY_COUNT + 1.
      WHEN OTHERS.
        <FS_EXEC>-READY_COUNT = <FS_EXEC>-READY_COUNT + 1.
    ENDCASE.

    IF <FS_EXEC>-MESSAGE IS INITIAL AND <FS_ALV>-ERROR_MSG IS NOT INITIAL.
      <FS_EXEC>-MESSAGE = <FS_ALV>-ERROR_MSG.
    ENDIF.
  ENDLOOP.

  LOOP AT GT_EXEC_DISP ASSIGNING <FS_EXEC>.
    LV_ALL_OK = ABAP_FALSE.
    LV_ALL_SM35 = ABAP_FALSE.
    IF <FS_EXEC>-ITEM_COUNT > 0 AND <FS_EXEC>-SUCCESS_COUNT = <FS_EXEC>-ITEM_COUNT.
      LV_ALL_OK = ABAP_TRUE.
    ENDIF.
    IF <FS_EXEC>-ITEM_COUNT > 0 AND <FS_EXEC>-SM35_COUNT = <FS_EXEC>-ITEM_COUNT.
      LV_ALL_SM35 = ABAP_TRUE.
    ENDIF.

    IF <FS_EXEC>-ERROR_COUNT > 0.
      <FS_EXEC>-ICON        = '@0A@'.
      <FS_EXEC>-RUN_STATUS  = GC_ST_ERROR.
      <FS_EXEC>-MSG_TYPE    = 'E'.
      <FS_EXEC>-HEALTH_TEXT = 'Blocked by validation/BDC error'.
      GV_EXEC_ERR_GRP       = GV_EXEC_ERR_GRP + 1.
    ELSEIF <FS_EXEC>-WARNING_COUNT > 0.
      <FS_EXEC>-ICON        = '@09@'.
      <FS_EXEC>-RUN_STATUS  = GC_ST_WARNING.
      <FS_EXEC>-MSG_TYPE    = 'W'.
      <FS_EXEC>-HEALTH_TEXT = 'Completed with warning'.
      GV_EXEC_WARN_GRP      = GV_EXEC_WARN_GRP + 1.
    ELSEIF LV_ALL_OK = ABAP_TRUE.
      <FS_EXEC>-ICON        = '@08@'.
      <FS_EXEC>-RUN_STATUS  = GC_ST_SUCCESS.
      <FS_EXEC>-MSG_TYPE    = 'S'.
      <FS_EXEC>-HEALTH_TEXT = 'SAP document created'.
      GV_EXEC_SUCC_GRP      = GV_EXEC_SUCC_GRP + 1.
    ELSEIF LV_ALL_SM35 = ABAP_TRUE.
      <FS_EXEC>-ICON        = '@09@'.
      <FS_EXEC>-RUN_STATUS  = GC_ST_SM35Q.
      <FS_EXEC>-MSG_TYPE    = 'I'.
      IF <FS_EXEC>-MESSAGE CS 'is processing'.
        <FS_EXEC>-HEALTH_TEXT = 'SM35 session processing'.
      ELSEIF <FS_EXEC>-MESSAGE CS 'background job'.
        <FS_EXEC>-HEALTH_TEXT = 'SM35 background job submitted'.
      ELSEIF <FS_EXEC>-MESSAGE CS 'returned from'.
        <FS_EXEC>-HEALTH_TEXT = 'SM35 processing returned'.
      ELSE.
        <FS_EXEC>-HEALTH_TEXT = 'Queued in SM35 batch session'.
      ENDIF.
      CLEAR <FS_EXEC>-SAP_OBJECT_ID.
      GV_EXEC_SM35_GRP      = GV_EXEC_SM35_GRP + 1.
    ELSEIF <FS_EXEC>-READY_COUNT = <FS_EXEC>-ITEM_COUNT.
      <FS_EXEC>-ICON        = '@09@'.
      <FS_EXEC>-RUN_STATUS  = GC_ST_READY.
      <FS_EXEC>-MSG_TYPE    = 'I'.
      <FS_EXEC>-HEALTH_TEXT = 'Ready for BDC execution'.
      GV_EXEC_READY_GRP     = GV_EXEC_READY_GRP + 1.
    ELSE.
      <FS_EXEC>-ICON        = '@09@'.
      <FS_EXEC>-RUN_STATUS  = 'PARTIAL'.
      <FS_EXEC>-MSG_TYPE    = 'W'.
      <FS_EXEC>-HEALTH_TEXT = 'Mixed row status in group'.
      GV_EXEC_WARN_GRP      = GV_EXEC_WARN_GRP + 1.
    ENDIF.

    IF <FS_EXEC>-MESSAGE CS 'retry' OR <FS_EXEC>-MESSAGE CS 'Retry'.
      <FS_EXEC>-ATTEMPT = GC_MAX_ATTEMPTS.
      GV_EXEC_RETRY_GRP = GV_EXEC_RETRY_GRP + 1.
    ELSEIF <FS_EXEC>-ATTEMPT IS INITIAL.
      <FS_EXEC>-ATTEMPT = 1.
    ENDIF.

    DATA LV_EXEC_MSG_BEFORE TYPE C LENGTH 255.
    LV_EXEC_MSG_BEFORE = <FS_EXEC>-MESSAGE.
    PERFORM FILL_EXEC_OBJECT_FROM_RESULT USING LT_RES CHANGING <FS_EXEC>.
    IF <FS_EXEC>-RUN_STATUS = GC_ST_SM35Q.
      <FS_EXEC>-MSG_TYPE = 'I'.
      IF LV_EXEC_MSG_BEFORE IS NOT INITIAL.
        <FS_EXEC>-MESSAGE = LV_EXEC_MSG_BEFORE.
      ENDIF.
      CLEAR: <FS_EXEC>-SAP_OBJECT_ID, <FS_EXEC>-DRILL_TCODE.
    ENDIF.
    IF <FS_EXEC>-RUN_STATUS <> GC_ST_SM35Q
       AND <FS_EXEC>-SAP_OBJECT_ID IS INITIAL
       AND <FS_EXEC>-MESSAGE IS NOT INITIAL.
      PERFORM EXTRACT_OBJECT_FROM_TEXT USING <FS_EXEC>-MESSAGE CHANGING <FS_EXEC>-SAP_OBJECT_ID.
    ENDIF.

    IF <FS_EXEC>-RUN_STATUS = GC_ST_SUCCESS.
      IF <FS_EXEC>-SAP_OBJECT_ID IS NOT INITIAL.
        <FS_EXEC>-MESSAGE = |SAP document { <FS_EXEC>-SAP_OBJECT_ID } created successfully.|.
      ELSE.
        <FS_EXEC>-MESSAGE = 'SAP document created successfully.'.
      ENDIF.
    ENDIF.

    IF <FS_EXEC>-TCODE = 'ME21N' AND <FS_EXEC>-SAP_OBJECT_ID IS NOT INITIAL.
      <FS_EXEC>-DRILL_TCODE = 'ME23N'.
    ELSEIF <FS_EXEC>-TCODE = 'MIGO' AND <FS_EXEC>-SAP_OBJECT_ID IS NOT INITIAL.
      <FS_EXEC>-DRILL_TCODE = 'MB03/MIGO'.
    ENDIF.

    CLEAR <FS_EXEC>-SELECTED.  "Technical compatibility field; hidden in 0400.

    PERFORM SET_EXEC_ACTION_HINT CHANGING <FS_EXEC>.

    REFRESH <FS_EXEC>-CELL_COLORS.
    CLEAR LS_COLOR.
    LS_COLOR-FNAME = 'RUN_STATUS'.
    CASE <FS_EXEC>-RUN_STATUS.
      WHEN GC_ST_SUCCESS.
        LS_COLOR-COLOR-COL = 5.
      WHEN GC_ST_ERROR.
        LS_COLOR-COLOR-COL = 6.
      WHEN GC_ST_WARNING OR 'PARTIAL' OR GC_ST_SM35Q.
        LS_COLOR-COLOR-COL = 3.
      WHEN OTHERS.
        LS_COLOR-COLOR-COL = 1.
    ENDCASE.
    LS_COLOR-COLOR-INT = 1.
    APPEND LS_COLOR TO <FS_EXEC>-CELL_COLORS.

    IF <FS_EXEC>-SAP_OBJECT_ID IS NOT INITIAL.
      CLEAR LS_COLOR.
      LS_COLOR-FNAME = 'SAP_OBJECT_ID'.
      LS_COLOR-COLOR-COL = 5.
      LS_COLOR-COLOR-INT = 1.
      APPEND LS_COLOR TO <FS_EXEC>-CELL_COLORS.
    ENDIF.

    GV_EXEC_TOTAL_GRP = GV_EXEC_TOTAL_GRP + 1.
  ENDLOOP.

  IF GV_EXEC_TOTAL_GRP > 0.
    DATA(LV_PCT) = ( GV_EXEC_SUCC_GRP * 100 ) / GV_EXEC_TOTAL_GRP.
    GV_EXEC_PROGRESS = |{ LV_PCT }% success|.
  ELSE.
    GV_EXEC_PROGRESS = 'No group'.
  ENDIF.

  GV_EXEC_HEADER_TXT = |Groups { GV_EXEC_TOTAL_GRP } | &&
                       |Ready { GV_EXEC_READY_GRP } | &&
                       |Success { GV_EXEC_SUCC_GRP } | &&
                       |Error { GV_EXEC_ERR_GRP } | &&
                       |Warning { GV_EXEC_WARN_GRP } | &&
                       |SM35 { GV_EXEC_SM35_GRP } | &&
                       |Retry { GV_EXEC_RETRY_GRP }|.

  SORT GT_EXEC_DISP BY SESSION_ID GROUP_KEY.
ENDFORM.
*<<< END FORM BUILD_EXEC_COCKPIT

*>>> FORM RENDER_0400_HEADER - moved from Z_BDC_MASS_PO_ENTRY_F01_BUP

FORM RENDER_0400_HEADER.
  "CL_DD_DOCUMENT->ADD_TEXT expects SDYDO_TEXT_ELEMENT, not STRING.
  "0400 V4M: benchmark-style group cockpit header, no unused workflow wording.
  DATA: LV_TITLE TYPE SDYDO_TEXT_ELEMENT,
        LV_LINE1 TYPE SDYDO_TEXT_ELEMENT,
        LV_LINE2 TYPE SDYDO_TEXT_ELEMENT,
        LV_LINE3 TYPE SDYDO_TEXT_ELEMENT.

  IF GO_CONT_HEAD_0400 IS INITIAL.
    RETURN.
  ENDIF.

  IF GO_DOC_HEAD_0400 IS BOUND.
    FREE GO_DOC_HEAD_0400.
  ENDIF.

  CREATE OBJECT GO_DOC_HEAD_0400.

  IF GV_0400_VIEW = GC_VIEW_COCKPIT.
    LV_TITLE = 'BDC Execution Cockpit - Group Processing'.
  ELSE.
    LV_TITLE = 'Staging Detail - Source Rows'.
  ENDIF.

  LV_LINE1 = |Session: { TXTP_SESSION_ID }   Transaction: { P_TRANSACTION }   Batch Size: { TXTP_BATCH_SIZE }|.
  LV_LINE2 = |Groups: { GV_EXEC_TOTAL_GRP }   Ready: { GV_EXEC_READY_GRP }   Success: { GV_EXEC_SUCC_GRP }   Error: { GV_EXEC_ERR_GRP }   Warning: { GV_EXEC_WARN_GRP }   Retry: { GV_EXEC_RETRY_GRP }|.
  LV_LINE3 = |Progress: { GV_EXEC_PROGRESS }. Flow: Execute -> Refresh -> Dashboard proof. Double-click SAP Object to review.|.

  CALL METHOD GO_DOC_HEAD_0400->ADD_TEXT
    EXPORTING
      TEXT      = LV_TITLE
      SAP_STYLE = CL_DD_AREA=>HEADING.
  CALL METHOD GO_DOC_HEAD_0400->NEW_LINE.
  CALL METHOD GO_DOC_HEAD_0400->ADD_TEXT EXPORTING TEXT = LV_LINE1.
  CALL METHOD GO_DOC_HEAD_0400->NEW_LINE.
  CALL METHOD GO_DOC_HEAD_0400->ADD_TEXT EXPORTING TEXT = LV_LINE2.
  CALL METHOD GO_DOC_HEAD_0400->NEW_LINE.
  CALL METHOD GO_DOC_HEAD_0400->ADD_TEXT EXPORTING TEXT = LV_LINE3.

  CALL METHOD GO_DOC_HEAD_0400->DISPLAY_DOCUMENT
    EXPORTING
      PARENT        = GO_CONT_HEAD_0400
      REUSE_CONTROL = 'X'.
ENDFORM.
*<<< END FORM RENDER_0400_HEADER

*>>> FORM FILL_EXEC_OBJECT_FROM_RESULT - moved from Z_BDC_MASS_PO_ENTRY_F01_BUP

FORM FILL_EXEC_OBJECT_FROM_RESULT
  USING    PT_RES  TYPE TY_T_RESULT
  CHANGING CS_EXEC TYPE TY_EXEC_DISP.

  FIELD-SYMBOLS: <LS_RES> TYPE ANY,
                 <FV>     TYPE ANY.
  DATA: LV_RKEY TYPE STRING,
        LV_TKEY TYPE STRING,
        LV_MSG  TYPE STRING.

  LOOP AT PT_RES ASSIGNING <LS_RES>.
    ASSIGN COMPONENT 'RECORD_KEY' OF STRUCTURE <LS_RES> TO <FV>.
    IF SY-SUBRC = 0.
      LV_RKEY = <FV>.
      LV_TKEY = CS_EXEC-GROUP_KEY.
      IF LV_RKEY IS NOT INITIAL AND LV_RKEY <> LV_TKEY.
        CONTINUE.
      ENDIF.
    ENDIF.

    ASSIGN COMPONENT 'SAP_OBJECT_ID' OF STRUCTURE <LS_RES> TO <FV>.
    IF SY-SUBRC = 0 AND <FV> IS NOT INITIAL AND CS_EXEC-SAP_OBJECT_ID IS INITIAL.
      CS_EXEC-SAP_OBJECT_ID = <FV>.
    ENDIF.

    ASSIGN COMPONENT 'MSG_TYPE' OF STRUCTURE <LS_RES> TO <FV>.
    IF SY-SUBRC = 0 AND <FV> IS NOT INITIAL.
      CS_EXEC-MSG_TYPE = <FV>.
    ENDIF.

    ASSIGN COMPONENT 'MESSAGE' OF STRUCTURE <LS_RES> TO <FV>.
    IF SY-SUBRC = 0 AND <FV> IS NOT INITIAL.
      LV_MSG = <FV>.
      IF CS_EXEC-MESSAGE IS INITIAL OR CS_EXEC-MSG_TYPE = 'S'.
        CS_EXEC-MESSAGE = LV_MSG.
      ENDIF.
    ENDIF.

    IF CS_EXEC-SAP_OBJECT_ID IS NOT INITIAL AND CS_EXEC-MESSAGE IS NOT INITIAL.
      EXIT.
    ENDIF.
  ENDLOOP.
ENDFORM.
*<<< END FORM FILL_EXEC_OBJECT_FROM_RESULT

*>>> FORM EXTRACT_OBJECT_FROM_TEXT - moved from Z_BDC_MASS_PO_ENTRY_F01_BUP

FORM EXTRACT_OBJECT_FROM_TEXT USING PV_TEXT TYPE ANY
                           CHANGING CV_OBJ  TYPE ZBDC_RESULT_BUP-SAP_OBJECT_ID.
  DATA: LV_TEXT TYPE STRING,
        LV_LEN  TYPE I,
        LV_POS  TYPE I,
        LV_CH   TYPE C LENGTH 1,
        LV_BUF  TYPE STRING.

  CLEAR CV_OBJ.
  LV_TEXT = PV_TEXT.
  LV_LEN = STRLEN( LV_TEXT ).
  WHILE LV_POS < LV_LEN.
    LV_CH = LV_TEXT+LV_POS(1).
    IF LV_CH CO '0123456789'.
      LV_BUF = |{ LV_BUF }{ LV_CH }|.
    ELSE.
      IF STRLEN( LV_BUF ) >= 10.
        CV_OBJ = LV_BUF.
        RETURN.
      ENDIF.
      CLEAR LV_BUF.
    ENDIF.
    LV_POS = LV_POS + 1.
  ENDWHILE.
  IF STRLEN( LV_BUF ) >= 10.
    CV_OBJ = LV_BUF.
  ENDIF.
ENDFORM.
*<<< END FORM EXTRACT_OBJECT_FROM_TEXT

*>>> FORM UPDATE_0400_COUNTERS - moved from Z_BDC_MASS_PO_ENTRY_F01_BUP

FORM UPDATE_0400_COUNTERS.
  CLEAR: TXTP_SESSION_ID, TXTP_SESS, TXTGV_TOT, TXTGV_SUC, TXTGV_ERR, TXTGV_WAR,
         TXTGV_TOTAL, TXTGV_OK, TXTGV_SUC_COUNT, TXTGV_WARNING.

  IF gv_current_batch_prefix IS NOT INITIAL.
    TXTP_SESSION_ID = gv_current_batch_prefix.
    TXTP_SESS       = gv_current_batch_prefix.
  ELSE.
    READ TABLE GT_STAGING INTO DATA(LS_FIRST_CNT) INDEX 1.
    IF SY-SUBRC = 0.
      TXTP_SESSION_ID = LS_FIRST_CNT-SESSION_ID.
      TXTP_SESS       = LS_FIRST_CNT-SESSION_ID.
    ELSE.
      READ TABLE GT_EXEC_DISP INTO DATA(LS_FIRST_EXEC) INDEX 1.
      IF SY-SUBRC = 0.
        TXTP_SESSION_ID = LS_FIRST_EXEC-SESSION_ID.
        TXTP_SESS       = LS_FIRST_EXEC-SESSION_ID.
      ENDIF.
    ENDIF.
  ENDIF.

  "Existing screen fields are reused as group KPI counters.
  TXTGV_TOT       = |{ GV_EXEC_TOTAL_GRP }|.
  TXTGV_SUC       = |{ GV_EXEC_SUCC_GRP }|.
  TXTGV_ERR       = |{ GV_EXEC_ERR_GRP }|.
  TXTGV_WAR       = |{ GV_EXEC_WARN_GRP }|.
  TXTGV_TOTAL     = GV_EXEC_TOTAL_GRP.
  TXTGV_OK        = GV_EXEC_SUCC_GRP.
  TXTGV_SUC_COUNT = GV_EXEC_SUCC_GRP.
  TXTGV_WARNING   = GV_EXEC_WARN_GRP.
ENDFORM.
*<<< END FORM UPDATE_0400_COUNTERS

*>>> FORM BUILD_EXEC_FIELDCAT - moved from Z_BDC_MASS_PO_ENTRY_F01_BUP

FORM BUILD_EXEC_FIELDCAT CHANGING CT_FCAT TYPE LVC_T_FCAT.
  DATA LS_FCAT TYPE LVC_S_FCAT.

  REFRESH CT_FCAT.

  DEFINE ADD_COL.
    CLEAR LS_FCAT.
    LS_FCAT-FIELDNAME = &1.
    LS_FCAT-COLTEXT   = &2.
    LS_FCAT-SCRTEXT_L = &2.
    LS_FCAT-SCRTEXT_M = &2.
    LS_FCAT-SCRTEXT_S = &2.
    LS_FCAT-OUTPUTLEN = &3.
    LS_FCAT-COL_POS   = &4.
    APPEND LS_FCAT TO CT_FCAT.
  END-OF-DEFINITION.

  "V5AC: use the standard left-hand ALV row selector. No extra Run checkbox.
  ADD_COL 'ICON'          'Status'           5   1.
  ADD_COL 'SOURCE_FILE'   'File / Source'    28  2.
  ADD_COL 'SHEET_NAME'    'Sheet'            18  3.
  ADD_COL 'GROUP_KEY'     'Group Key'        18  4.
  ADD_COL 'TCODE'         'Transaction'      12  5.
  ADD_COL 'ITEM_COUNT'    'Items'            6   6.
  ADD_COL 'RUN_STATUS'    'Lifecycle'        14  7.
  ADD_COL 'HEALTH_TEXT'   'Health Check'     34  8.
  ADD_COL 'SAP_OBJECT_ID' 'SAP Object'       16  9.
  ADD_COL 'ACTION_HINT'   'Next Action'      50  10.
  ADD_COL 'MESSAGE'       'Fix Hint / Message' 75 11.
  ADD_COL 'ATTEMPT'       'Retry'            6   12.

  "Technical/context fields are still in GT_EXEC_DISP for logic/export,
  "but not shown in the 0400 demo cockpit.
  ADD_COL 'SELECTED'      'Selected'          1  88.
  ADD_COL 'BATCH_KEY'     'Batch'            22  89.
  ADD_COL 'SESSION_ID'    'Session ID'       24  90.
  ADD_COL 'DRILL_TCODE'   'Review TCode'     12  91.
  ADD_COL 'MSG_TYPE'      'Msg Type'         8   92.
  ADD_COL 'READY_COUNT'   'Ready Rows'       10  93.
  ADD_COL 'SUCCESS_COUNT' 'Success Rows'     12  94.
  ADD_COL 'ERROR_COUNT'   'Error Rows'       10  95.
  ADD_COL 'WARNING_COUNT' 'Warning Rows'     12  96.
  ADD_COL 'SM35_COUNT'    'SM35 Rows'         10  97.

  LOOP AT CT_FCAT ASSIGNING FIELD-SYMBOL(<F>).
    CASE <F>-FIELDNAME.
      WHEN 'SELECTED' OR 'BATCH_KEY' OR 'SESSION_ID' OR 'DRILL_TCODE' OR 'MSG_TYPE'
        OR 'READY_COUNT' OR 'SUCCESS_COUNT' OR 'ERROR_COUNT' OR 'WARNING_COUNT'
        OR 'SM35_COUNT'.
        <F>-NO_OUT = 'X'.
      WHEN 'SAP_OBJECT_ID'.
        <F>-HOTSPOT = 'X'.
      WHEN 'ICON'.
        <F>-ICON = 'X'.
      WHEN 'SOURCE_FILE' OR 'SHEET_NAME' OR 'GROUP_KEY' OR 'RUN_STATUS'.
        <F>-KEY = 'X'.
      WHEN 'MESSAGE' OR 'ACTION_HINT' OR 'HEALTH_TEXT'.
        <F>-LOWERCASE = 'X'.
    ENDCASE.
  ENDLOOP.
ENDFORM.
*<<< END FORM BUILD_EXEC_FIELDCAT

*>>> FORM BUILD_DETAIL_FIELDCAT - moved from Z_BDC_MASS_PO_ENTRY_F01_BUP

FORM BUILD_DETAIL_FIELDCAT CHANGING CT_FCAT TYPE LVC_T_FCAT.
  CALL FUNCTION 'LVC_FIELDCATALOG_MERGE'
    EXPORTING
      I_STRUCTURE_NAME       = 'ZBDC_STAGING_BUP'
      I_CLIENT_NEVER_DISPLAY = 'X'
    CHANGING
      CT_FIELDCAT            = CT_FCAT
    EXCEPTIONS
      OTHERS                 = 1.
  PERFORM SET_FCAT_DYNAMIC_NAMES CHANGING CT_FCAT.
  PERFORM Z16_PROTECT_SYSTEM_FIELDS CHANGING CT_FCAT.
ENDFORM.
*<<< END FORM BUILD_DETAIL_FIELDCAT

*>>> FORM FREE_0400_GRID - moved from Z_BDC_MASS_PO_ENTRY_F01_BUP

FORM FREE_0400_GRID.
  IF GO_EXEC_GRID IS BOUND.
    FREE GO_EXEC_GRID.
  ENDIF.
  IF GO_STAGING_GRID IS BOUND.
    FREE GO_STAGING_GRID.
  ENDIF.
  IF GO_DOC_HEAD_0400 IS BOUND.
    FREE GO_DOC_HEAD_0400.
  ENDIF.
  IF GO_SPLIT_0400 IS BOUND.
    FREE GO_SPLIT_0400.
  ENDIF.
  IF GO_CONTAINER_0400 IS BOUND.
    FREE GO_CONTAINER_0400.
  ENDIF.
  CLEAR: GO_EXEC_GRID, GO_STAGING_GRID, GO_GRID_0400,
         GO_DOC_HEAD_0400, GO_SPLIT_0400, GO_CONT_HEAD_0400,
         GO_CONT_BODY_0400, GO_CONTAINER_0400, G_0400_GRID_EVENTS.
ENDFORM.
*<<< END FORM FREE_0400_GRID

*>>> FORM REFRESH_0400_GRID - moved from Z_BDC_MASS_PO_ENTRY_F01_BUP

FORM REFRESH_0400_GRID.
  DATA LS_STABLE TYPE LVC_S_STBL.

  LS_STABLE-ROW = 'X'.
  LS_STABLE-COL = 'X'.

  PERFORM RENDER_0400_HEADER.

  IF GV_0400_VIEW = GC_VIEW_COCKPIT AND GO_EXEC_GRID IS BOUND.
    GO_EXEC_GRID->REFRESH_TABLE_DISPLAY( EXPORTING IS_STABLE = LS_STABLE ).
  ELSEIF GV_0400_VIEW = GC_VIEW_DETAIL AND GO_STAGING_GRID IS BOUND.
    GO_STAGING_GRID->REFRESH_TABLE_DISPLAY( EXPORTING IS_STABLE = LS_STABLE ).
  ENDIF.
ENDFORM.
*<<< END FORM REFRESH_0400_GRID

*>>> FORM SWITCH_TO_COCKPIT - moved from Z_BDC_MASS_PO_ENTRY_F01_BUP

FORM SWITCH_TO_COCKPIT.
  GV_0400_VIEW = GC_VIEW_COCKPIT.
  GV_0400_EDIT_MODE = SPACE.
  PERFORM BUILD_EXEC_COCKPIT.
  PERFORM UPDATE_0400_COUNTERS.
  PERFORM FREE_0400_GRID.
ENDFORM.
*<<< END FORM SWITCH_TO_COCKPIT

*>>> FORM SWITCH_TO_DETAIL_EDIT - moved from Z_BDC_MASS_PO_ENTRY_F01_BUP

FORM SWITCH_TO_DETAIL_EDIT.
  GV_0400_VIEW = GC_VIEW_DETAIL.
  GV_0400_EDIT_MODE = 'X'.
  PERFORM FREE_0400_GRID.
ENDFORM.
*<<< END FORM SWITCH_TO_DETAIL_EDIT

*>>> FORM SAVE_DETAIL_AND_RETURN - moved from Z_BDC_MASS_PO_ENTRY_F01_BUP

FORM SAVE_DETAIL_AND_RETURN.
  IF GO_STAGING_GRID IS BOUND.
    GO_STAGING_GRID->CHECK_CHANGED_DATA( ).
  ENDIF.

  PERFORM Z16_LOG_ALV_CHANGES USING 'DETAIL_EDIT'.
  GT_STAGING = CORRESPONDING #( GT_STAGING_ALV ).
  IF GT_STAGING IS NOT INITIAL.
    MODIFY ZBDC_STAGING_BUP FROM TABLE GT_STAGING.
    COMMIT WORK AND WAIT.
  ENDIF.

  PERFORM PREPARE_ALV_0400.
  PERFORM SWITCH_TO_COCKPIT.
  MESSAGE 'Da luu detail, validate lai, va quay ve Execution Cockpit.' TYPE 'S'.
ENDFORM.
*<<< END FORM SAVE_DETAIL_AND_RETURN

*>>> FORM DRILLDOWN_DOCUMENT - moved from Z_BDC_MASS_PO_ENTRY_F01_BUP

FORM DRILLDOWN_DOCUMENT USING PS_EXEC TYPE TY_EXEC_DISP.
  DATA: LV_OBJ TYPE ZBDC_RESULT_BUP-SAP_OBJECT_ID.

  LV_OBJ = PS_EXEC-SAP_OBJECT_ID.
  IF LV_OBJ IS INITIAL.
    MESSAGE 'Chua co SAP Object ID de drilldown. Hay chay BDC truoc hoac xem Message.' TYPE 'W'.
    RETURN.
  ENDIF.

  IF PS_EXEC-TCODE = 'ME21N'.
    SET PARAMETER ID 'BES' FIELD LV_OBJ.
    CALL TRANSACTION 'ME23N' AND SKIP FIRST SCREEN.
  ELSEIF PS_EXEC-TCODE = 'MIGO'.
    SET PARAMETER ID 'MBN' FIELD LV_OBJ.
    CALL TRANSACTION 'MB03' AND SKIP FIRST SCREEN.
  ELSE.
    MESSAGE |Chua cau hinh drilldown cho TCODE { PS_EXEC-TCODE }. Object={ LV_OBJ }.| TYPE 'I'.
  ENDIF.
ENDFORM.
*<<< END FORM DRILLDOWN_DOCUMENT

*>>> FORM SHOW_GROUP_MESSAGE - moved from Z_BDC_MASS_PO_ENTRY_F01_BUP

FORM SHOW_GROUP_MESSAGE.
  DATA: LT_ROID TYPE LVC_T_ROID,
        LS_EXEC TYPE TY_EXEC_DISP,
        LV_TEXT TYPE STRING.

  IF GO_EXEC_GRID IS NOT BOUND.
    RETURN.
  ENDIF.
  GO_EXEC_GRID->GET_SELECTED_ROWS( IMPORTING ET_ROW_NO = LT_ROID ).
  READ TABLE LT_ROID INTO DATA(LS_ROID) INDEX 1.
  IF SY-SUBRC <> 0.
    MESSAGE 'Chon 1 group de xem message detail.' TYPE 'W'.
    RETURN.
  ENDIF.
  READ TABLE GT_EXEC_DISP INTO LS_EXEC INDEX LS_ROID-ROW_ID.
  IF SY-SUBRC = 0.
    LV_TEXT = |Group { LS_EXEC-GROUP_KEY } - { LS_EXEC-RUN_STATUS }| && CL_ABAP_CHAR_UTILITIES=>NEWLINE &&
              |SAP Object: { LS_EXEC-SAP_OBJECT_ID }   Drilldown: { LS_EXEC-DRILL_TCODE }| && CL_ABAP_CHAR_UTILITIES=>NEWLINE &&
              |Health: { LS_EXEC-HEALTH_TEXT }| && CL_ABAP_CHAR_UTILITIES=>NEWLINE &&
              |Next Action: { LS_EXEC-ACTION_HINT }| && CL_ABAP_CHAR_UTILITIES=>NEWLINE &&
              |Message: { LS_EXEC-MESSAGE }|.
    CALL FUNCTION 'POPUP_TO_DISPLAY_TEXT'
      EXPORTING
        TITEL     = 'BDC Group Message / Fix Hint'
        TEXTLINE1 = LV_TEXT
      EXCEPTIONS
        OTHERS    = 1.
    IF SY-SUBRC <> 0.
      MESSAGE LS_EXEC-MESSAGE TYPE 'I'.
    ENDIF.
  ENDIF.
ENDFORM.



*&=====================================================================*
*& V7 PRO - FORMS FOR 14 SCREEN LIFECYCLE
*&=====================================================================*
CLASS lcl_result_events IMPLEMENTATION.
  METHOD on_result_double_click.
    READ TABLE gt_result_all INTO DATA(ls_res) INDEX row.
    IF sy-subrc = 0.
      txtp_po_key        = ls_res-record_key.
      txtp_sap_object_id = ls_res-sap_object_id.
      txtp_result_msg    = ls_res-message.
      CALL SCREEN 0650.
    ENDIF.
  ENDMETHOD.
ENDCLASS.
*<<< END FORM SHOW_GROUP_MESSAGE

*>>> FORM refresh_current_dashboard - moved from Z_BDC_MASS_PO_ENTRY_F01_BUP

FORM refresh_current_dashboard.
  PERFORM get_recent_sessions.
  PERFORM calculate_dashboard_stats.
ENDFORM.

* ------------------------------------------------------------
* Screen 0250 - OBSOLETE fallback only; current flow does not call 0250
* ------------------------------------------------------------
*<<< END FORM refresh_current_dashboard

*>>> FORM load_jobs_0250 - moved from Z_BDC_MASS_PO_ENTRY_F01_BUP
FORM load_jobs_0250.
  DATA ls_job TYPE ty_job_disp.
  REFRESH gt_jobs_0250.

  CLEAR ls_job.
  ls_job-jobname   = p_job_name.
  ls_job-status    = 'READY_TO_SCHEDULE'.
  ls_job-frequency = p_freq.
  ls_job-message   = 'Use headless report Z_BDC_MASS_PO_BATCH for true background execution.'.
  APPEND ls_job TO gt_jobs_0250.
ENDFORM.
*<<< END FORM load_jobs_0250

*>>> FORM display_jobs_0250 - moved from Z_BDC_MASS_PO_ENTRY_F01_BUP

FORM display_jobs_0250.
  PERFORM load_jobs_0250.
  IF go_container_0250 IS INITIAL.
    CREATE OBJECT go_container_0250
      EXPORTING container_name = 'CC_JOB_GRID'.
    TRY.
        cl_salv_table=>factory(
          EXPORTING r_container  = go_container_0250
          IMPORTING r_salv_table = go_grid_0250
          CHANGING  t_table      = gt_jobs_0250 ).
        go_grid_0250->get_functions( )->set_all( abap_true ).
        go_grid_0250->display( ).
      CATCH cx_salv_msg INTO DATA(lx_job).
        MESSAGE lx_job->get_text( ) TYPE 'I'.
    ENDTRY.
  ELSEIF go_grid_0250 IS BOUND.
    go_grid_0250->refresh( ).
  ENDIF.
ENDFORM.
*<<< END FORM display_jobs_0250

*>>> FORM schedule_job_0250 - moved from Z_BDC_MASS_PO_ENTRY_F01_BUP

FORM schedule_job_0250.
  MESSAGE 'Scheduler UI saved. Create/call report Z_BDC_MASS_PO_BATCH for real background job.' TYPE 'S'.
  PERFORM display_jobs_0250.
ENDFORM.
*<<< END FORM schedule_job_0250

*>>> FORM stop_job_0250 - moved from Z_BDC_MASS_PO_ENTRY_F01_BUP

FORM stop_job_0250.
  MESSAGE 'Stop requested. In production, delete/release job from SM37 by jobcount.' TYPE 'S'.
  PERFORM display_jobs_0250.
ENDFORM.

* ------------------------------------------------------------
* Screen 0350 - Mapping Profile
* ------------------------------------------------------------
*<<< END FORM stop_job_0250

*>>> FORM z16_append_exec_group - moved from Z_BDC_MASS_PO_ENTRY_F01_BUP
FORM z16_append_exec_group
  USING    is_exec TYPE ty_exec_disp
  CHANGING ct_process TYPE ty_t_staging_alv.

  DATA ls_alv   TYPE ty_staging_alv.
  DATA ls_db    TYPE zbdc_staging_bup.
  DATA lt_db    TYPE STANDARD TABLE OF zbdc_staging_bup.
  DATA lv_added TYPE i.

  LOOP AT gt_staging_alv INTO ls_alv
       WHERE session_id = is_exec-session_id
         AND record_key = is_exec-group_key.
    IF is_exec-tcode IS NOT INITIAL AND
       ls_alv-tcode IS NOT INITIAL AND
       ls_alv-tcode <> is_exec-tcode.
      CONTINUE.
    ENDIF.
    IF ls_alv-status <> gc_st_ready.
      CONTINUE.
    ENDIF.
    APPEND ls_alv TO ct_process.
    lv_added = lv_added + 1.
  ENDLOOP.

  IF lv_added = 0.
    SELECT * FROM zbdc_staging_bup INTO TABLE lt_db
      WHERE session_id = is_exec-session_id
        AND record_key = is_exec-group_key.
    LOOP AT lt_db INTO ls_db.
      IF is_exec-tcode IS NOT INITIAL AND
         ls_db-tcode IS NOT INITIAL AND
         ls_db-tcode <> is_exec-tcode.
        CONTINUE.
      ENDIF.
      IF ls_db-status <> gc_st_ready.
        CONTINUE.
      ENDIF.
      CLEAR ls_alv.
      MOVE-CORRESPONDING ls_db TO ls_alv.
      APPEND ls_alv TO ct_process.
    ENDLOOP.
  ENDIF.
ENDFORM.
*<<< END FORM z16_append_exec_group

*>>> FORM z19_toggle_0400_row_sel - moved from Z_BDC_MASS_PO_ENTRY_F01_BUP
FORM z19_toggle_0400_row_sel.
  "Compatibility no-op. Native ALV selection is read only when Run Selected
  "is pressed; no delayed callback or hidden sticky cache is maintained.
ENDFORM.
*<<< END FORM z19_toggle_0400_row_sel

*>>> FORM z19_apply_0400_selection - moved from Z_BDC_MASS_PO_ENTRY_F01_BUP

FORM z19_apply_0400_selection.
  "Compatibility no-op. Never re-select rows automatically.
ENDFORM.
*<<< END FORM z19_apply_0400_selection

*>>> FORM z19_reset_0400_selection - moved from Z_BDC_MASS_PO_ENTRY_F01_BUP

FORM z19_reset_0400_selection.
  DATA lt_empty TYPE lvc_t_row.

  CLEAR gt_0400_sel_keys.
  IF go_exec_grid IS BOUND.
    CALL METHOD go_exec_grid->set_selected_rows
      EXPORTING it_index_rows = lt_empty.
  ENDIF.
ENDFORM.
*<<< END FORM z19_reset_0400_selection

*>>> FORM z16_set_0500_progress - moved from Z_BDC_MASS_PO_ENTRY_F01_BUP

FORM z16_set_0500_progress
  USING iv_curr       TYPE i
        iv_total      TYPE i
        iv_elapsed_ms TYPE i.

  DATA: lv_pct_disp    TYPE p LENGTH 7 DECIMALS 2,
        lv_pct_gui     TYPE i,
        lv_elapsed_sec TYPE p LENGTH 8 DECIMALS 1,
        lv_grid_title  TYPE lvc_title,
        lv_live_text   TYPE c LENGTH 120,
        lv_eta_ms      TYPE i,
        lv_eta_sec     TYPE p LENGTH 8 DECIMALS 1.

  WRITE iv_curr  TO txtgv_exec_curr LEFT-JUSTIFIED.
  WRITE iv_total TO txtgv_exec_total LEFT-JUSTIFIED.

  IF iv_total > 0.
    lv_pct_disp = iv_curr.
    lv_pct_disp = lv_pct_disp * 100 / iv_total.
    lv_pct_gui  = lv_pct_disp.
  ELSE.
    CLEAR: lv_pct_disp, lv_pct_gui.
  ENDIF.
  WRITE lv_pct_disp TO txtgv_exec_pct LEFT-JUSTIFIED.
  CONDENSE txtgv_exec_pct NO-GAPS.

  "The dynpro already displays SEC next to these numeric fields.
  lv_elapsed_sec = iv_elapsed_ms / 1000.
  WRITE lv_elapsed_sec TO txtgv_exec_elapsed LEFT-JUSTIFIED.
  CONDENSE txtgv_exec_elapsed NO-GAPS.

  "ETA becomes useful after the first final business group.  It is still
  "evidence-based: estimated from completed groups and elapsed runtime.
  IF iv_total > 0 AND iv_curr >= iv_total.
    txtgv_exec_eta = '0.0'.
  ELSEIF iv_total > 0 AND iv_curr > 0 AND iv_elapsed_ms > 0.
    lv_eta_ms = ( iv_elapsed_ms * ( iv_total - iv_curr ) ) / iv_curr.
    lv_eta_sec = lv_eta_ms / 1000.
    WRITE lv_eta_sec TO txtgv_exec_eta LEFT-JUSTIFIED.
    CONDENSE txtgv_exec_eta NO-GAPS.
  ELSE.
    txtgv_exec_eta = 'n/a'.
  ENDIF.

  CONCATENATE txtgv_exec_curr '/' txtgv_exec_total
    INTO gv_exec_progress SEPARATED BY space.

  lv_grid_title = |Progress { txtgv_exec_curr }/{ txtgv_exec_total } ({ txtgv_exec_pct }%) Elapsed { txtgv_exec_elapsed } sec ETA { txtgv_exec_eta } sec - { gv_exec_run_phase }|.
  IF go_grid_0500 IS BOUND.
    TRY.
        CALL METHOD go_grid_0500->set_gridtitle
          EXPORTING i_gridtitle = lv_grid_title.
        CALL METHOD cl_gui_cfw=>flush.
      CATCH cx_root.
        "The status-bar indicator below remains the reliable fallback.
    ENDTRY.
  ENDIF.

  lv_live_text = |Processing { txtgv_exec_curr }/{ txtgv_exec_total } ({ txtgv_exec_pct }%) - { gv_exec_run_phase }|.
  CALL FUNCTION 'SAPGUI_PROGRESS_INDICATOR'
    EXPORTING
      percentage = lv_pct_gui
      text       = lv_live_text.

  PERFORM z16_update_0500_dynpro_vals.
ENDFORM.
*<<< END FORM z16_set_0500_progress

*>>> FORM z16_update_0500_dynpro_vals - moved from Z_BDC_MASS_PO_ENTRY_F01_BUP

FORM z16_update_0500_dynpro_vals.
  DATA lt_dynp TYPE STANDARD TABLE OF dynpread.
  DATA ls_dynp TYPE dynpread.

  CLEAR lt_dynp.

  CLEAR ls_dynp.
  ls_dynp-fieldname  = 'TXTGV_EXEC_SESSION'.
  ls_dynp-fieldvalue = txtgv_exec_session.
  APPEND ls_dynp TO lt_dynp.

  CLEAR ls_dynp.
  ls_dynp-fieldname  = 'TXTGV_EXEC_CURR'.
  ls_dynp-fieldvalue = txtgv_exec_curr.
  APPEND ls_dynp TO lt_dynp.

  CLEAR ls_dynp.
  ls_dynp-fieldname  = 'TXTGV_EXEC_TOTAL'.
  ls_dynp-fieldvalue = txtgv_exec_total.
  APPEND ls_dynp TO lt_dynp.

  CLEAR ls_dynp.
  ls_dynp-fieldname  = 'TXTGV_EXEC_PCT'.
  ls_dynp-fieldvalue = txtgv_exec_pct.
  APPEND ls_dynp TO lt_dynp.

  CLEAR ls_dynp.
  ls_dynp-fieldname  = 'TXTGV_EXEC_ELAPSED'.
  ls_dynp-fieldvalue = txtgv_exec_elapsed.
  APPEND ls_dynp TO lt_dynp.

  CLEAR ls_dynp.
  ls_dynp-fieldname  = 'TXTGV_EXEC_ETA'.
  ls_dynp-fieldvalue = txtgv_exec_eta.
  APPEND ls_dynp TO lt_dynp.

  CALL FUNCTION 'DYNP_VALUES_UPDATE'
    EXPORTING
      dyname     = sy-repid
      dynumb     = '0500'
    TABLES
      dynpfields = lt_dynp
    EXCEPTIONS
      OTHERS     = 1.

  CALL METHOD cl_gui_cfw=>flush.
ENDFORM.
*<<< END FORM z16_update_0500_dynpro_vals

*>>> FORM z16_sync_0500_progress_q - moved from Z_BDC_MASS_PO_ENTRY_F01_BUP

FORM z16_sync_0500_progress_q.
  DATA lv_total TYPE i.
  DATA lv_done  TYPE i.
  DATA lv_ms    TYPE i.

  lv_total = lines( gt_exec_disp ).
  lv_done  = 0.

  LOOP AT gt_exec_disp ASSIGNING FIELD-SYMBOL(<ls_q_prog>).
    CASE <ls_q_prog>-run_status.
      "V5BD: the header progress is business-completion progress, not
      "SM35 dispatch progress. Queued/Fallback/Warning rows remain pending
      "until SUCCESS or a real final ERROR is available.
      WHEN gc_st_success OR gc_st_error OR 'SKIPPED' OR 'PARTIAL'.
        lv_done = lv_done + 1.
    ENDCASE.
  ENDLOOP.

  IF lv_total = 0 AND gt_exec_scope_0500 IS NOT INITIAL.
    lv_total = lines( gt_exec_scope_0500 ).
  ENDIF.

  lv_ms = gv_exec_elapsed.
  PERFORM z16_set_0500_progress USING lv_done lv_total lv_ms.
ENDFORM.
*<<< END FORM z16_sync_0500_progress_q

*>>> FORM z16_sapgui_progress - moved from Z_BDC_MASS_PO_ENTRY_F01_BUP

FORM z16_sapgui_progress
  USING iv_curr  TYPE i
        iv_total TYPE i
        iv_text  TYPE csequence.

  DATA lv_pct TYPE i.
  DATA lv_msg TYPE c LENGTH 120.

  IF iv_total > 0.
    lv_pct = ( iv_curr * 100 ) / iv_total.
  ELSE.
    lv_pct = 0.
  ENDIF.

  lv_msg = |0500 executing { iv_curr }/{ iv_total }: { iv_text }|.

  CALL FUNCTION 'SAPGUI_PROGRESS_INDICATOR'
    EXPORTING
      percentage = lv_pct
      text       = lv_msg.
ENDFORM.
*<<< END FORM z16_sapgui_progress

*>>> FORM z16_flush_0500_queue - moved from Z_BDC_MASS_PO_ENTRY_F01_BUP

FORM z16_flush_0500_queue.
  DATA ls_stable TYPE lvc_s_stbl.

  ls_stable-row = 'X'.
  ls_stable-col = 'X'.

  IF go_grid_0500 IS BOUND.
    TRY.
        CALL METHOD go_grid_0500->refresh_table_display
          EXPORTING is_stable = ls_stable.
        CALL METHOD cl_gui_cfw=>flush.
      CATCH cx_root.
    ENDTRY.
  ENDIF.
ENDFORM.
*<<< END FORM z16_flush_0500_queue

*>>> FORM z16_force_0500_repaint - moved from Z_BDC_MASS_PO_ENTRY_F01_BUP


FORM z16_force_0500_repaint.
  "Do not LEAVE SCREEN here. Leaving screen after a run makes old SAP GUI
  "docking containers survive for one roundtrip and creates duplicated ALV
  "queues. A flush is enough; normal PAI/PBO will repaint the dynpro fields.
  IF go_grid_0500 IS BOUND.
    PERFORM z16_flush_0500_queue.
  ENDIF.
  CALL METHOD cl_gui_cfw=>flush.
ENDFORM.
*<<< END FORM z16_force_0500_repaint

*>>> FORM z16_reset_0500_layout - moved from Z_BDC_MASS_PO_ENTRY_F01_BUP

FORM z16_reset_0500_layout.
  "No forced FREE in PBO. Recreating docking containers on every PBO causes
  "duplicate execution queues in SAP GUI. The queue is created once and
  "refreshed; it is freed only when leaving screen 0500.
ENDFORM.
*<<< END FORM z16_reset_0500_layout

*>>> FORM z16_0500_profile_text - moved from Z_BDC_MASS_PO_ENTRY_F01_BUP


FORM z16_0500_profile_text CHANGING cv_text TYPE string.
  DATA lv_mode  TYPE c LENGTH 1.
  DATA lv_upd   TYPE c LENGTH 1.
  DATA lv_bsize TYPE i.
  DATA lv_mode_text TYPE string.
  DATA lv_upd_text  TYPE string.
  DATA lv_engine       TYPE string.
  DATA lv_scope        TYPE string.
  DATA lv_sm35_profile TYPE string.

  PERFORM get_runtime_options CHANGING lv_mode lv_upd lv_bsize.

  CASE lv_mode.
    WHEN 'A'. lv_mode_text = 'A - All screens'.
    WHEN 'E'. lv_mode_text = 'E - Errors only'.
    WHEN 'N'. lv_mode_text = 'N - No display'.
    WHEN OTHERS. lv_mode_text = lv_mode.
  ENDCASE.

  CASE lv_upd.
    WHEN 'S'. lv_upd_text = 'S - Sync'.
    WHEN 'A'. lv_upd_text = 'A - Async'.
    WHEN OTHERS. lv_upd_text = lv_upd.
  ENDCASE.

  PERFORM z16_sm35_profile_label
    USING    lv_mode lv_upd
    CHANGING lv_sm35_profile.

  lv_engine = 'CTU + managed SM35'.

  lv_scope = gv_exec_scope_text.
  IF lv_scope IS INITIAL.
    lv_scope = 'Current READY queue'.
  ENDIF.

  cv_text = |{ lv_scope } | &&
            |{ lv_engine } | &&
            |CTU { lv_mode_text } / Update { lv_upd_text } | &&
            |SM35 { lv_sm35_profile }.|.
ENDFORM.
*<<< END FORM z16_0500_profile_text

*>>> FORM z16_build_0500_queue - moved from Z_BDC_MASS_PO_ENTRY_F01_BUP

FORM z16_build_0500_queue.
  DATA lt_scope TYPE ty_t_staging_alv.
  DATA lt_all   TYPE ty_t_exec_disp.
  DATA ls_scope TYPE ty_staging_alv.
  DATA ls_exec  TYPE ty_exec_disp.
  DATA lv_profile TYPE string.

  PERFORM z16_0500_profile_text CHANGING lv_profile.

  "V5BF: During an active 0500 run, the visible queue must come from the
  "current runtime snapshot only.  Rebuilding from DB here caused old PO_KEYs
  "from previous runs to reappear and made the bottom ALV flash/blank.
  IF gt_async_qstate IS NOT INITIAL AND
     ( gv_exec_run_active = abap_true OR
       gv_sm35_fallback_active = abap_true OR
       gv_exec_mon_kind IS NOT INITIAL ).
    PERFORM z16_build_0500_from_q.
    RETURN.
  ENDIF.

  IF gt_exec_scope_0500 IS NOT INITIAL.
    "Do not display stale READY copies. Rebuild the cockpit from current DB/runtime,
    "then filter it back to the 0400 scope that was sent to 0500.
    lt_scope = gt_exec_scope_0500.
    PERFORM prepare_alv_0400.
    PERFORM build_exec_cockpit.
    lt_all = gt_exec_disp.
    CLEAR gt_exec_disp.

    LOOP AT lt_scope INTO ls_scope.
      READ TABLE lt_all INTO ls_exec
        WITH KEY session_id = ls_scope-session_id
                 group_key  = ls_scope-record_key
                 tcode      = ls_scope-tcode.
      IF sy-subrc = 0.
        APPEND ls_exec TO gt_exec_disp.
      ENDIF.
    ENDLOOP.
  ELSE.
    IF gt_staging_alv IS INITIAL.
      PERFORM prepare_alv_0400.
    ENDIF.
    PERFORM build_exec_cockpit.
  ENDIF.

  LOOP AT gt_exec_disp ASSIGNING FIELD-SYMBOL(<ls_exec_0500>).
    IF <ls_exec_0500>-run_status = gc_st_ready.
      IF gv_exec_stop_req = abap_true OR g_stop_flag = 'X'.
        <ls_exec_0500>-health_text = 'Stopped - waiting for user'.
        <ls_exec_0500>-action_hint = 'Refresh or reload scope before Execute'.
        <ls_exec_0500>-message = 'Queue stop requested. Running BDC cannot be interrupted mid-screen; stop is applied after the active group returns.'.
      ELSEIF gv_exec_run_active = abap_true AND gv_exec_mon_kind = 'C'.
        IF <ls_exec_0500>-session_id = gv_async_session_id AND
           <ls_exec_0500>-group_key  = gv_async_group_key.
          <ls_exec_0500>-icon       = '@09@'.
          <ls_exec_0500>-msg_type   = 'I'.
          IF gv_async_done = abap_true.
            <ls_exec_0500>-run_status  = 'VERIFYING'.
            <ls_exec_0500>-health_text = 'SAP returned; verifying result'.
            <ls_exec_0500>-action_hint = 'Wait for document proof and final status'.
            <ls_exec_0500>-message     = |Verifying { gv_async_tcode } { gv_async_group_key }.|.
          ELSE.
            <ls_exec_0500>-run_status  = 'PROCESSING'.
            <ls_exec_0500>-health_text = 'Running SAP transaction'.
            <ls_exec_0500>-action_hint = 'Current group is executing in RFC worker'.
            <ls_exec_0500>-message     =
              |Processing group { gv_async_key_index }/{ gv_async_total }; remaining selected groups start automatically.|.
          ENDIF.
        ELSE.
          <ls_exec_0500>-icon        = '@09@'.
          <ls_exec_0500>-msg_type    = 'I'.
          <ls_exec_0500>-run_status  = 'QUEUED'.
          <ls_exec_0500>-health_text = 'Waiting in selected run'.
          <ls_exec_0500>-action_hint = 'Starts automatically after current group'.
          <ls_exec_0500>-message     =
            |Queued in this run; completed { gv_exec_run_done }/{ gv_async_total }.|.
        ENDIF.
      ELSEIF gv_exec_run_active = abap_true AND gv_exec_mon_kind = 'B'.
        <ls_exec_0500>-icon        = '@09@'.
        <ls_exec_0500>-msg_type    = 'I'.
        <ls_exec_0500>-run_status  = 'SM35RUN'.
        <ls_exec_0500>-health_text = 'SM35 session is processing'.
        <ls_exec_0500>-action_hint = 'Wait for SM35 terminal state and proof'.
        <ls_exec_0500>-message     = |Managed SM35 session { gv_sm35_mon_group } is running.|.
      ELSE.
        IF chkp_background = 'X'.
          <ls_exec_0500>-health_text = 'Creating SM35 batch session'.
          <ls_exec_0500>-action_hint = 'Wait for BDC_INSERT / BDC_CLOSE_GROUP'.
        ELSE.
          <ls_exec_0500>-health_text = 'Ready - choose execution engine'.
          <ls_exec_0500>-action_hint = 'Execute Now or Queue to SM35'.
        ENDIF.
        IF <ls_exec_0500>-message IS INITIAL OR <ls_exec_0500>-message CS 'Scope:'.
          <ls_exec_0500>-message = lv_profile.
        ENDIF.
      ENDIF.
    ENDIF.
  ENDLOOP.

  "Final overlay from the persistent selected-run queue. This is applied
  "after the DB cockpit rebuild, so queued/processing states cannot fall
  "back to READY between two RFC tasks.
  PERFORM z24_async_q_overlay.

  "V5AR: SM35 runtime overlay applies to every selected group, including
  "rows already persisted as SM35QUEUE. This keeps the user-visible state
  "truthful while RSBDCCTU processes the queue and evidence is persisted.
  IF gv_exec_run_active = abap_true AND gv_exec_mon_kind = 'B'.
    LOOP AT gt_exec_disp ASSIGNING <ls_exec_0500>.
      READ TABLE gt_sm35_mon_process TRANSPORTING NO FIELDS
        WITH KEY session_id = <ls_exec_0500>-session_id
                 record_key = <ls_exec_0500>-group_key
                 tcode      = <ls_exec_0500>-tcode.
      IF sy-subrc = 0.
        <ls_exec_0500>-icon     = '@09@'.
        <ls_exec_0500>-msg_type = 'I'.
        IF gv_sm35_job_finished = abap_true.
          <ls_exec_0500>-run_status  = 'VERIFYING'.
          <ls_exec_0500>-health_text = 'RSBDCCTU done; reconciling proof'.
          <ls_exec_0500>-action_hint = 'Wait for SM35 log/object proof; do not duplicate run'.
          IF gv_sm35_last_qstate IS INITIAL.
            <ls_exec_0500>-message =
              |RSBDCCTU finished for { gv_sm35_mon_group }; APQI state blank/not found. Reconciling proof and checking evidence-based GUI fallback.|.
          ELSE.
            <ls_exec_0500>-message =
              |RSBDCCTU finished for { gv_sm35_mon_group }; APQI state { gv_sm35_last_qstate }. Reconciling proof and checking evidence-based GUI fallback.|.
          ENDIF.
        ELSE.
          <ls_exec_0500>-run_status  = 'SM35RUN'.
          <ls_exec_0500>-health_text = 'SM35 batch processing'.
          <ls_exec_0500>-action_hint = 'Monitor live; do not start a duplicate run'.
          <ls_exec_0500>-message =
            |SM35 session { gv_sm35_mon_group } is queued/processing with profile { gv_last_sm35_profile }.|.
        ENDIF.
      ENDIF.
    ENDLOOP.
  ENDIF.
ENDFORM.
*<<< END FORM z16_build_0500_queue

*>>> FORM z16_display_0500_queue - moved from Z_BDC_MASS_PO_ENTRY_F01_BUP

FORM z16_display_0500_queue.
  DATA lt_fcat   TYPE lvc_t_fcat.
  DATA ls_layo   TYPE lvc_s_layo.
  DATA ls_stable TYPE lvc_s_stbl.
  DATA lv_0500_mode TYPE c LENGTH 1.
  DATA lv_0500_upd  TYPE c LENGTH 1.
  DATA lv_0500_bsz  TYPE i.
  DATA lv_ratio     TYPE i.

  PERFORM get_runtime_options CHANGING lv_0500_mode lv_0500_upd lv_0500_bsz.
  IF lv_0500_mode = 'A'.
    "V5K: All-screens mode uses a true full-client ALV parent instead of a
    "docking container. Therefore there is no draggable splitter and the old
    "0500 progress block is completely covered. The visible ME21N/MIGO screens
    "are the detailed live execution UI for mode A.
    lv_ratio = 100.
  ELSE.
    "N/E modes keep the 0500 progress header visible above the queue.
    lv_ratio = 45.
  ENDIF.

  IF go_grid_0500 IS BOUND AND gv_0500_layout_mode <> lv_0500_mode.
    PERFORM z16_free_0500_queue.
  ENDIF.

  PERFORM z16_build_0500_queue.
  PERFORM z16_sync_0500_progress_q.
  PERFORM build_exec_fieldcat CHANGING lt_fcat.

  LOOP AT lt_fcat ASSIGNING FIELD-SYMBOL(<ls_fcat_0500>).
    CASE <ls_fcat_0500>-fieldname.
      WHEN 'BATCH_KEY' OR 'SESSION_ID'.
        <ls_fcat_0500>-no_out = space.
      WHEN 'SELECTED' OR 'DRILL_TCODE' OR 'MSG_TYPE' OR 'READY_COUNT' OR 'SUCCESS_COUNT'
        OR 'ERROR_COUNT' OR 'WARNING_COUNT' OR 'SM35_COUNT'.
        <ls_fcat_0500>-no_out = 'X'.
    ENDCASE.
  ENDLOOP.

  CLEAR ls_layo.
  ls_layo-ctab_fname = 'CELL_COLORS'.
  ls_layo-cwidth_opt = 'X'.
  ls_layo-sel_mode   = 'D'.
  ls_layo-zebra      = 'X'.
  ls_stable-row      = 'X'.
  ls_stable-col      = 'X'.

  IF go_grid_0500 IS NOT BOUND.
    IF lv_0500_mode = 'A'.
      "Full-screen queue: fixed layout, no splitter to drag.
      CREATE OBJECT go_grid_0500
        EXPORTING i_parent = cl_gui_container=>screen0.
    ELSE.
      CREATE OBJECT go_dock_0500
        EXPORTING
          repid = sy-repid
          dynnr = sy-dynnr
          side  = cl_gui_docking_container=>dock_at_bottom
          ratio = lv_ratio.

      CREATE OBJECT go_grid_0500
        EXPORTING i_parent = go_dock_0500.
    ENDIF.

    gv_0500_layout_mode = lv_0500_mode.

    CREATE OBJECT g_0500_grid_events.
    SET HANDLER g_0500_grid_events->on_exec_double_click FOR go_grid_0500.
    SET HANDLER g_0500_grid_events->on_0500_toolbar FOR go_grid_0500.
    SET HANDLER g_0500_grid_events->on_0500_user_command FOR go_grid_0500.

    CALL METHOD go_grid_0500->set_table_for_first_display
      EXPORTING
        is_layout       = ls_layo
      CHANGING
        it_outtab       = gt_exec_disp
        it_fieldcatalog = lt_fcat.

    CALL METHOD go_grid_0500->set_toolbar_interactive.
  ELSE.
    CALL METHOD go_grid_0500->refresh_table_display
      EXPORTING is_stable = ls_stable.
  ENDIF.
ENDFORM.
*<<< END FORM z16_display_0500_queue

*>>> FORM z16_free_0500_queue - moved from Z_BDC_MASS_PO_ENTRY_F01_BUP

FORM z16_free_0500_queue.
  "A plain FREE of the ABAP reference is not enough for a control whose parent
  "is CL_GUI_CONTAINER=>SCREEN0. Explicitly destroy the frontend control first,
  "flush the CFW queue, and only then release references/navigation state.
  IF go_grid_0500 IS BOUND.
    TRY.
        CALL METHOD go_grid_0500->set_visible
          EXPORTING visible = space.
        CALL METHOD go_grid_0500->free.
      CATCH cx_root.
        "Cleanup must never block Back/Exit.
    ENDTRY.
    FREE go_grid_0500.
  ENDIF.

  IF go_dock_0500 IS BOUND.
    TRY.
        CALL METHOD go_dock_0500->set_visible
          EXPORTING visible = space.
        CALL METHOD go_dock_0500->free.
      CATCH cx_root.
        "Cleanup must never block Back/Exit.
    ENDTRY.
    FREE go_dock_0500.
  ENDIF.

  CLEAR: go_grid_0500,
         go_dock_0500,
         g_0500_grid_events,
         gv_0500_layout_mode,
         gv_0500_active.

  TRY.
      CALL METHOD cl_gui_cfw=>flush.
    CATCH cx_root.
      "The next PBO also contains a safety cleanup guard.
  ENDTRY.
ENDFORM.
*<<< END FORM z16_free_0500_queue

*>>> FORM z16_open_result_screen_curr - moved from Z_BDC_MASS_PO_ENTRY_F01_BUP

FORM z16_open_result_screen_curr.
  "V5K: Never CALL SCREEN 0600 while the custom dynpro cannot be generated.
  "Route every dashboard entry point to the no-dump SALV dashboard. This
  "keeps successful SAP documents/results intact and prevents a UI dynpro
  "error from being confused with a BDC execution failure.
  PERFORM z16_open_result_dash_curr.
ENDFORM.
*<<< END FORM z16_open_result_screen_curr

*>>> FORM z16_prep_popup_retry_0560 - moved from Z_BDC_MASS_PO_ENTRY_F01_BUP

FORM z16_prep_popup_retry_0560.
  DATA ls_stg TYPE ty_staging_alv.

  PERFORM update_popup_detail.
  READ TABLE gt_staging_alv INTO ls_stg INDEX g_edit_index.
  IF sy-subrc = 0.
    REFRESH gt_exec_scope_0500.
    APPEND ls_stg TO gt_exec_scope_0500.
    gv_exec_scope_ready = abap_true.
    gv_exec_scope_0500 = 'RETRY'.
    gv_exec_scope_text = 'Retry corrected group from 0550'.
    txtgv_exec_session = ls_stg-session_id.
  ENDIF.

  CALL SCREEN 0560 STARTING AT 10 5 ENDING AT 88 18.
ENDFORM.
*<<< END FORM z16_prep_popup_retry_0560

*>>> FORM z16_open_result_dash_curr - moved from Z_BDC_MASS_PO_ENTRY_F01_BUP

FORM z16_open_result_dash_curr.
  DATA ls_dash_staging TYPE zbdc_staging_bup.
  DATA ls_dash_alv     TYPE ty_staging_alv.
  DATA ls_dash_exec    TYPE ty_exec_disp.

  "V5E: when Dashboard is opened from 0500, prefer the exact execution
  "queue/session currently on screen. Older txtp_session_id/txtp_sess values
  "can point to a previous SFTP/local run and made the dashboard unrelated.
  CLEAR txtp_result_session.

  IF txtgv_exec_session IS NOT INITIAL.
    txtp_result_session = txtgv_exec_session.
  ELSE.
    READ TABLE gt_exec_disp INTO ls_dash_exec INDEX 1.
    IF sy-subrc = 0 AND ls_dash_exec-session_id IS NOT INITIAL.
      txtp_result_session = ls_dash_exec-session_id.
    ELSE.
      READ TABLE gt_exec_scope_0500 INTO ls_dash_alv INDEX 1.
      IF sy-subrc = 0 AND ls_dash_alv-session_id IS NOT INITIAL.
        txtp_result_session = ls_dash_alv-session_id.
      ELSEIF txtp_session_id IS NOT INITIAL.
        txtp_result_session = txtp_session_id.
      ELSEIF txtp_sess IS NOT INITIAL.
        txtp_result_session = txtp_sess.
      ELSE.
        READ TABLE gt_staging_alv INTO ls_dash_alv INDEX 1.
        IF sy-subrc = 0 AND ls_dash_alv-session_id IS NOT INITIAL.
          txtp_result_session = ls_dash_alv-session_id.
        ELSE.
          READ TABLE gt_staging INTO ls_dash_staging INDEX 1.
          IF sy-subrc = 0 AND ls_dash_staging-session_id IS NOT INITIAL.
            txtp_result_session = ls_dash_staging-session_id.
          ENDIF.
        ENDIF.
      ENDIF.
    ENDIF.
  ENDIF.

  g_result_sub = '0601'.

  "V4N: do not depend on generated Screen 0600 at all.
  "Build dashboard proof directly from current 0400 cockpit/session tables.
  REFRESH: gt_result_all, gt_result_msg, gt_result_summary.
  PERFORM z16_build_dash_from_0400.
  PERFORM z16_show_result_dash_safe.
ENDFORM.
*<<< END FORM z16_open_result_dash_curr

*>>> FORM z16_build_dash_from_0400 - moved from Z_BDC_MASS_PO_ENTRY_F01_BUP

FORM z16_build_dash_from_0400.
  DATA ls_sum TYPE ty_result_summary.

  IF gt_result_summary IS NOT INITIAL.
    RETURN.
  ENDIF.

  IF gt_exec_disp IS INITIAL.
    PERFORM build_exec_cockpit.
  ENDIF.

  CLEAR ls_sum.
  ls_sum-session_id        = txtp_result_session.
  IF ls_sum-session_id IS INITIAL AND txtgv_exec_session IS NOT INITIAL.
    ls_sum-session_id = txtgv_exec_session.
  ENDIF.
  IF ls_sum-session_id IS INITIAL.
    ls_sum-session_id = txtp_session_id.
  ENDIF.
  IF ls_sum-session_id IS INITIAL.
    ls_sum-session_id = txtp_sess.
  ENDIF.

  ls_sum-total_records     = gv_exec_total_grp.
  ls_sum-success_records   = gv_exec_succ_grp.
  ls_sum-warning_records   = gv_exec_warn_grp.
  ls_sum-error_records     = gv_exec_err_grp.
  ls_sum-ready_records     = gv_exec_ready_grp.
  ls_sum-processed_records = gv_exec_succ_grp + gv_exec_warn_grp + gv_exec_err_grp.
  ls_sum-retry_count       = gv_exec_retry_grp.
  ls_sum-log_count         = lines( gt_result_all ).

  IF ls_sum-error_records > 0.
    ls_sum-status_text = 'HAS_ERROR'.
  ELSEIF ls_sum-warning_records > 0.
    ls_sum-status_text = 'HAS_WARNING'.
  ELSEIF ls_sum-total_records > 0 AND ls_sum-success_records = ls_sum-total_records.
    ls_sum-status_text = 'COMPLETED_SUCCESS'.
  ELSEIF ls_sum-ready_records > 0.
    ls_sum-status_text = 'READY_FOR_EXECUTION'.
  ELSE.
    ls_sum-status_text = 'NO_CURRENT_DATA'.
  ENDIF.

  ls_sum-last_message = gv_exec_header_txt.
  APPEND ls_sum TO gt_result_summary.
ENDFORM.
*<<< END FORM z16_build_dash_from_0400

*>>> FORM z16_set_dash_col_text - moved from Z_BDC_MASS_PO_ENTRY_F01_BUP

FORM z16_set_dash_col_text USING po_cols  TYPE REF TO cl_salv_columns_table
                                 pv_name  TYPE lvc_fname
                                 pv_text  TYPE string.
  DATA lo_col TYPE REF TO cl_salv_column_table.
  DATA lv_ltxt TYPE scrtext_l.
  DATA lv_mtxt TYPE scrtext_m.
  DATA lv_stxt TYPE scrtext_s.

  lv_ltxt = pv_text.
  lv_mtxt = pv_text.
  lv_stxt = pv_text.

  TRY.
      lo_col ?= po_cols->get_column( pv_name ).
      lo_col->set_long_text( lv_ltxt ).
      lo_col->set_medium_text( lv_mtxt ).
      lo_col->set_short_text( lv_stxt ).
    CATCH cx_salv_not_found.
  ENDTRY.
ENDFORM.
*<<< END FORM z16_set_dash_col_text

*>>> FORM z16_show_result_dash_safe - moved from Z_BDC_MASS_PO_ENTRY_F01_BUP

FORM z16_show_result_dash_safe.
  DATA lo_alv  TYPE REF TO cl_salv_table.
  DATA lo_cols TYPE REF TO cl_salv_columns_table.
  DATA lx_msg  TYPE REF TO cx_salv_msg.

  IF gt_result_summary IS INITIAL.
    PERFORM z16_build_dash_from_0400.
  ENDIF.

  IF gt_result_summary IS INITIAL.
    MESSAGE 'No dashboard data available for current session yet.' TYPE 'S' DISPLAY LIKE 'W'.
    RETURN.
  ENDIF.

  TRY.
      cl_salv_table=>factory(
        IMPORTING
          r_salv_table = lo_alv
        CHANGING
          t_table      = gt_result_summary ).

      lo_alv->get_functions( )->set_all( abap_true ).
      lo_cols = lo_alv->get_columns( ).
      lo_cols->set_optimize( abap_true ).

      PERFORM z16_set_dash_col_text USING lo_cols 'SESSION_ID'        'Session ID'.
      PERFORM z16_set_dash_col_text USING lo_cols 'TOTAL_RECORDS'     'Total Groups'.
      PERFORM z16_set_dash_col_text USING lo_cols 'PROCESSED_RECORDS' 'Processed'.
      PERFORM z16_set_dash_col_text USING lo_cols 'SUCCESS_RECORDS'   'Success'.
      PERFORM z16_set_dash_col_text USING lo_cols 'WARNING_RECORDS'   'Warning'.
      PERFORM z16_set_dash_col_text USING lo_cols 'ERROR_RECORDS'     'Error'.
      PERFORM z16_set_dash_col_text USING lo_cols 'READY_RECORDS'     'Ready'.
      PERFORM z16_set_dash_col_text USING lo_cols 'LOG_COUNT'         'BDC Logs'.
      PERFORM z16_set_dash_col_text USING lo_cols 'RETRY_COUNT'       'Retry'.
      PERFORM z16_set_dash_col_text USING lo_cols 'STATUS_TEXT'       'Overall Status'.
      PERFORM z16_set_dash_col_text USING lo_cols 'LAST_MESSAGE'      'Proof / Last Message'.

      lo_alv->display( ).
    CATCH cx_salv_msg INTO lx_msg.
      MESSAGE lx_msg->get_text( ) TYPE 'S' DISPLAY LIKE 'E'.
  ENDTRY.
ENDFORM.

* ------------------------------------------------------------
* Screen 0550 - Detail popup
* ------------------------------------------------------------
*<<< END FORM z16_show_result_dash_safe

*>>> FORM open_detail_popup_sel - moved from Z_BDC_MASS_PO_ENTRY_F01_BUP
FORM open_detail_popup_sel.
  "V5L: legacy entry point now uses the same no-dump runtime detail view.
  PERFORM z16_show_issue_detail_safe.
ENDFORM.
*<<< END FORM open_detail_popup_sel

*>>> FORM read_popup_detail - moved from Z_BDC_MASS_PO_ENTRY_F01_BUP

FORM read_popup_detail.
  READ TABLE gt_staging_alv INTO DATA(ls_stg) INDEX g_edit_index.
  IF sy-subrc <> 0.
    READ TABLE gt_staging_alv INTO ls_stg INDEX 1.
    IF sy-subrc <> 0.
      CLEAR ls_stg.
    ENDIF.
  ENDIF.
  txtp_po_key        = ls_stg-record_key.
  IF txtp_po_key IS INITIAL.
    txtp_po_key = ls_stg-field01.
  ENDIF.
  txtp_detail_status = ls_stg-status.
  txtp_vendor        = ls_stg-field02.
  txtp_purch_org     = ls_stg-field03.
  txtp_purch_group   = ls_stg-field04.
  txtp_item_no       = ls_stg-field05.
  txtp_material      = ls_stg-field06.
  txtp_quantity      = ls_stg-field07.
  txtp_plant         = ls_stg-field08.
  txtp_net_price     = ls_stg-field11.
  txtp_stor_loc      = ls_stg-field12.
  txtp_delivery_date = ls_stg-field14.
  txtp_doc_type      = ls_stg-field15.
  txtp_fix_message   = ls_stg-error_msg.
  IF txtp_fix_message IS INITIAL.
    txtp_fix_message = ls_stg-last_error.
  ENDIF.
ENDFORM.
*<<< END FORM read_popup_detail

*>>> FORM update_popup_detail - moved from Z_BDC_MASS_PO_ENTRY_F01_BUP

FORM update_popup_detail.
  READ TABLE gt_staging_alv ASSIGNING FIELD-SYMBOL(<ls_stg>) INDEX g_edit_index.
  IF sy-subrc <> 0.
    MESSAGE 'Khong tim thay dong staging dang sua.' TYPE 'E'.
    RETURN.
  ENDIF.
  DATA ls_z16_before TYPE ty_staging_alv.
  ls_z16_before = <ls_stg>.
  <ls_stg>-field02 = txtp_vendor.
  <ls_stg>-field03 = txtp_purch_org.
  <ls_stg>-field04 = txtp_purch_group.
  <ls_stg>-field05 = txtp_item_no.
  <ls_stg>-field06 = txtp_material.
  <ls_stg>-field07 = txtp_quantity.
  <ls_stg>-field08 = txtp_plant.
  <ls_stg>-field11 = txtp_net_price.
  <ls_stg>-field12 = txtp_stor_loc.
  <ls_stg>-field14 = txtp_delivery_date.
  <ls_stg>-field15 = txtp_doc_type.
  <ls_stg>-status  = gc_st_ready.
  <ls_stg>-error_msg = 'Corrected in popup 0550'.
  <ls_stg>-last_error = 'Corrected in popup 0550'.
  PERFORM Z16_LOG_ROW_CHANGES USING ls_z16_before <ls_stg> 'POPUP_EDIT'.

  DATA ls_db_stg TYPE zbdc_staging_bup.
  MOVE-CORRESPONDING <ls_stg> TO ls_db_stg.
  MODIFY zbdc_staging_bup FROM ls_db_stg.
  COMMIT WORK AND WAIT.
ENDFORM.
*<<< END FORM update_popup_detail

*>>> FORM resubmit_popup_detail - moved from Z_BDC_MASS_PO_ENTRY_F01_BUP

FORM resubmit_popup_detail.
  "V5H: 0550 does not execute directly.  It prepares a retry scope and
  "routes to 0560, then 0560 returns to 0500 for a controlled retry queue.
  PERFORM z16_prep_popup_retry_0560.
ENDFORM.

* ------------------------------------------------------------
* Screen 0560 - Mass Replacer
* ------------------------------------------------------------
*<<< END FORM resubmit_popup_detail

*>>> FORM open_mass_replacer - moved from Z_BDC_MASS_PO_ENTRY_F01_BUP
FORM open_mass_replacer.
  CLEAR: p_fld_name, p_old_val, p_new_val, txtgv_replace_cnt.
  CALL SCREEN 0560 STARTING AT 10 5 ENDING AT 72 15.
ENDFORM.
*<<< END FORM open_mass_replacer

*>>> FORM apply_mass_replace - moved from Z_BDC_MASS_PO_ENTRY_F01_BUP

FORM apply_mass_replace.
  DATA lv_count TYPE i.
  FIELD-SYMBOLS: <ls_stg> TYPE ty_staging_alv,
                 <lv_val> TYPE any.

  IF p_fld_name IS INITIAL.
    MESSAGE 'Nhap field can replace, vi du FIELD02/FIELD06/FIELD08.' TYPE 'W'.
    RETURN.
  ENDIF.

  LOOP AT gt_staging_alv ASSIGNING <ls_stg>.
    ASSIGN COMPONENT p_fld_name OF STRUCTURE <ls_stg> TO <lv_val>.
    IF sy-subrc <> 0.
      MESSAGE |Field { p_fld_name } khong ton tai.| TYPE 'E'.
      RETURN.
    ENDIF.
    IF <lv_val> = p_old_val.
      PERFORM Z16_LOG_ONE_CHANGE USING <ls_stg>-SESSION_ID <ls_stg>-ROW_INDEX <ls_stg>-TCODE p_fld_name p_old_val p_new_val 'MASS_REPLACE'.
      <lv_val> = p_new_val.
      <ls_stg>-status = gc_st_ready.
      <ls_stg>-error_msg = |Mass replace { p_fld_name }: { p_old_val } -> { p_new_val }|.
      <ls_stg>-last_error = <ls_stg>-error_msg.
      lv_count = lv_count + 1.
    ENDIF.
  ENDLOOP.

  IF lv_count > 0.
    gt_staging = CORRESPONDING #( gt_staging_alv ).
    MODIFY zbdc_staging_bup FROM TABLE gt_staging.
    COMMIT WORK AND WAIT.
  ENDIF.
  txtgv_replace_cnt = lv_count.
  MESSAGE |Mass replace done: { lv_count } rows.| TYPE 'S'.
ENDFORM.

* ------------------------------------------------------------
* Screen 0600/0650 - Result Dashboard and Detail
* ------------------------------------------------------------
*<<< END FORM apply_mass_replace

*>>> FORM select_result_session_0600 - moved from Z_BDC_MASS_PO_ENTRY_F01_BUP
FORM select_result_session_0600 CHANGING cv_session TYPE zbdc_result_bup-session_id.
  CLEAR cv_session.

  IF txtp_result_session IS NOT INITIAL.
    cv_session = txtp_result_session.
    RETURN.
  ENDIF.

  READ TABLE gt_staging INTO DATA(ls_stg_sess) INDEX 1.
  IF sy-subrc = 0 AND ls_stg_sess-session_id IS NOT INITIAL.
    cv_session = ls_stg_sess-session_id.
    txtp_result_session = cv_session.
    RETURN.
  ENDIF.

  READ TABLE gt_result_all INTO DATA(ls_res_sess) INDEX 1.
  IF sy-subrc = 0 AND ls_res_sess-session_id IS NOT INITIAL.
    cv_session = ls_res_sess-session_id.
    txtp_result_session = cv_session.
    RETURN.
  ENDIF.

  SELECT session_id FROM zbdc_result_bup
    INTO @cv_session
    UP TO 1 ROWS
    ORDER BY created_at DESCENDING.
  ENDSELECT.

  IF cv_session IS NOT INITIAL.
    txtp_result_session = cv_session.
  ENDIF.
ENDFORM.
*<<< END FORM select_result_session_0600

*>>> FORM z17_start_0600_timer - moved from Z_BDC_MASS_PO_ENTRY_F01_BUP

FORM z17_start_0600_timer.
  IF gv_timer_0600_on = abap_true AND go_timer_0600 IS BOUND.
    RETURN.
  ENDIF.

  TRY.
      IF go_timer_0600 IS NOT BOUND.
        CREATE OBJECT go_timer_0600.
      ENDIF.
      IF go_timer_hdl_0600 IS NOT BOUND.
        CREATE OBJECT go_timer_hdl_0600.
        SET HANDLER go_timer_hdl_0600->on_finished FOR go_timer_0600.
      ENDIF.

      IF gv_timer_0600_sec <= 0.
        gv_timer_0600_sec = 5.
      ENDIF.
      go_timer_0600->interval = gv_timer_0600_sec.
      gv_timer_0600_on = abap_true.
      go_timer_0600->run( ).
    CATCH cx_root.
      CLEAR gv_timer_0600_on.
  ENDTRY.
ENDFORM.
*<<< END FORM z17_start_0600_timer

*>>> FORM z17_stop_0600_timer - moved from Z_BDC_MASS_PO_ENTRY_F01_BUP

FORM z17_stop_0600_timer.
  CLEAR gv_timer_0600_on.
  IF go_timer_0600 IS BOUND.
    TRY.
        go_timer_0600->cancel( ).
      CATCH cx_root.
    ENDTRY.
    FREE go_timer_0600.
  ENDIF.
  FREE go_timer_hdl_0600.
ENDFORM.
*<<< END FORM z17_stop_0600_timer

*>>> FORM load_results_0600 - moved from Z_BDC_MASS_PO_ENTRY_F01_BUP

FORM load_results_0600.
  DATA lv_session TYPE zbdc_result_bup-session_id.

  PERFORM select_result_session_0600 CHANGING lv_session.

  REFRESH: gt_result_all, gt_result_msg, gt_result_summary.

  IF lv_session IS INITIAL.
    SELECT * FROM zbdc_result_bup
      ORDER BY created_at DESCENDING
      INTO TABLE @gt_result_all
      UP TO 500 ROWS.
  ELSE.
    SELECT * FROM zbdc_result_bup
      WHERE session_id = @lv_session
      ORDER BY row_index ASCENDING, step ASCENDING
      INTO TABLE @gt_result_all.
  ENDIF.

  gt_result_msg = gt_result_all.
  PERFORM build_result_summary_0600 USING lv_session.
ENDFORM.
*<<< END FORM load_results_0600

*>>> FORM build_result_summary_0600 - moved from Z_BDC_MASS_PO_ENTRY_F01_BUP

FORM build_result_summary_0600 USING iv_session TYPE zbdc_result_bup-session_id.
  DATA: ls_sum TYPE ty_result_summary,
        lv_session TYPE zbdc_result_bup-session_id.

  lv_session = iv_session.
  IF lv_session IS INITIAL.
    READ TABLE gt_result_all INTO DATA(ls_first_res) INDEX 1.
    IF sy-subrc = 0.
      lv_session = ls_first_res-session_id.
    ENDIF.
  ENDIF.

  IF lv_session IS INITIAL.
    RETURN.
  ENDIF.

  CLEAR ls_sum.
  ls_sum-session_id = lv_session.

  SELECT COUNT(*) FROM zbdc_staging_bup
    WHERE session_id = @lv_session
    INTO @ls_sum-total_records.

  SELECT COUNT(*) FROM zbdc_staging_bup
    WHERE session_id = @lv_session AND status = @gc_st_success
    INTO @ls_sum-success_records.

  SELECT COUNT(*) FROM zbdc_staging_bup
    WHERE session_id = @lv_session AND status = @gc_st_error
    INTO @ls_sum-error_records.

  SELECT COUNT(*) FROM zbdc_staging_bup
    WHERE session_id = @lv_session AND status = @gc_st_warning
    INTO @ls_sum-warning_records.

  SELECT COUNT(*) FROM zbdc_staging_bup
    WHERE session_id = @lv_session AND status = @gc_st_ready
    INTO @ls_sum-ready_records.

  ls_sum-processed_records = ls_sum-success_records + ls_sum-error_records + ls_sum-warning_records.

  SELECT COUNT(*) FROM zbdc_result_bup
    WHERE session_id = @lv_session
    INTO @ls_sum-log_count.

  SELECT COUNT(*) FROM zbdc_result_bup
    WHERE session_id = @lv_session AND retry_flag = 'X'
    INTO @ls_sum-retry_count.

  IF ls_sum-error_records > 0.
    ls_sum-status_text = 'HAS_ERROR'.
  ELSEIF ls_sum-warning_records > 0.
    ls_sum-status_text = 'HAS_WARNING'.
  ELSEIF ls_sum-total_records > 0 AND ls_sum-success_records = ls_sum-total_records.
    ls_sum-status_text = 'COMPLETED_SUCCESS'.
  ELSEIF ls_sum-ready_records > 0.
    ls_sum-status_text = 'READY_OR_PARTIAL'.
  ELSE.
    ls_sum-status_text = 'NO_STAGING_DATA'.
  ENDIF.

  DATA lv_last_idx TYPE i.
  lv_last_idx = lines( gt_result_all ).
  IF lv_last_idx > 0.
    READ TABLE gt_result_all INTO DATA(ls_last_res) INDEX lv_last_idx.
    IF sy-subrc = 0.
      ls_sum-last_message = ls_last_res-message.
    ENDIF.
  ENDIF.

  APPEND ls_sum TO gt_result_summary.
ENDFORM.
*<<< END FORM build_result_summary_0600

*>>> FORM display_result_grid - moved from Z_BDC_MASS_PO_ENTRY_F01_BUP

FORM display_result_grid USING pv_container TYPE csequence
                               CHANGING po_cont TYPE REF TO cl_gui_custom_container
                                        po_grid TYPE REF TO cl_salv_table
                                        pt_table TYPE ANY TABLE.
  IF po_cont IS INITIAL.
    CREATE OBJECT po_cont EXPORTING container_name = pv_container.
    TRY.
        cl_salv_table=>factory(
          EXPORTING r_container  = po_cont
          IMPORTING r_salv_table = po_grid
          CHANGING  t_table      = pt_table ).
        po_grid->get_functions( )->set_all( abap_true ).
        po_grid->get_columns( )->set_optimize( abap_true ).
        po_grid->get_selections( )->set_selection_mode( if_salv_c_selection_mode=>row_column ).
        po_grid->display( ).
      CATCH cx_salv_msg INTO DATA(lx_res).
        MESSAGE lx_res->get_text( ) TYPE 'I'.
      CATCH cx_salv_not_found.
    ENDTRY.
  ELSEIF po_grid IS BOUND.
    po_grid->refresh( refresh_mode = if_salv_c_refresh=>full ).
  ENDIF.
ENDFORM.
*<<< END FORM display_result_grid

*>>> FORM display_result_record_grid - moved from Z_BDC_MASS_PO_ENTRY_F01_BUP

FORM display_result_record_grid.
  PERFORM load_results_0600.
  IF go_container_0602 IS INITIAL.
    CREATE OBJECT go_container_0602 EXPORTING container_name = 'CC_RECORD_CONTAINER'.
    TRY.
        cl_salv_table=>factory(
          EXPORTING r_container  = go_container_0602
          IMPORTING r_salv_table = go_grid_0602
          CHANGING  t_table      = gt_result_all ).
        CREATE OBJECT go_result_events.
        DATA(lo_res_events) = go_grid_0602->get_event( ).
        SET HANDLER go_result_events->on_result_double_click FOR lo_res_events.
        go_grid_0602->get_functions( )->set_all( abap_true ).
        go_grid_0602->get_columns( )->set_optimize( abap_true ).
        go_grid_0602->get_selections( )->set_selection_mode( if_salv_c_selection_mode=>row_column ).
        go_grid_0602->display( ).
      CATCH cx_salv_msg INTO DATA(lx_rec).
        MESSAGE lx_rec->get_text( ) TYPE 'I'.
      CATCH cx_salv_not_found.
    ENDTRY.
  ELSEIF go_grid_0602 IS BOUND.
    go_grid_0602->refresh( refresh_mode = if_salv_c_refresh=>full ).
  ENDIF.
ENDFORM.
*<<< END FORM display_result_record_grid

*>>> FORM open_result_detail_selected - moved from Z_BDC_MASS_PO_ENTRY_F01_BUP

FORM open_result_detail_selected.
  DATA: ls_res TYPE zbdc_result_bup,
        lv_row TYPE i.

  lv_row = 1.
  IF go_grid_0602 IS BOUND.
    DATA(lo_sel) = go_grid_0602->get_selections( ).
    DATA(lt_rows) = lo_sel->get_selected_rows( ).
    READ TABLE lt_rows INTO lv_row INDEX 1.
    IF sy-subrc <> 0 OR lv_row IS INITIAL.
      lv_row = 1.
    ENDIF.
  ENDIF.

  READ TABLE gt_result_all INTO ls_res INDEX lv_row.
  IF sy-subrc <> 0.
    PERFORM load_results_0600.
    READ TABLE gt_result_all INTO ls_res INDEX 1.
  ENDIF.

  IF sy-subrc = 0.
    txtp_result_session = ls_res-session_id.
    txtp_po_key        = ls_res-record_key.
    txtp_sap_object_id = ls_res-sap_object_id.
    txtp_result_msg    = ls_res-message.
  ELSE.
    MESSAGE 'Khong co result record de drill-down.' TYPE 'W'.
    RETURN.
  ENDIF.

  CALL SCREEN 0650.
ENDFORM.
*<<< END FORM open_result_detail_selected

*>>> FORM load_result_detail - moved from Z_BDC_MASS_PO_ENTRY_F01_BUP

FORM load_result_detail.
  DATA lv_session TYPE zbdc_result_bup-session_id.

  lv_session = txtp_result_session.
  IF lv_session IS INITIAL.
    PERFORM select_result_session_0600 CHANGING lv_session.
  ENDIF.

  IF txtp_po_key IS INITIAL AND txtp_sap_object_id IS INITIAL.
    READ TABLE gt_result_all INTO DATA(ls_first) INDEX 1.
    IF sy-subrc = 0.
      txtp_result_session = ls_first-session_id.
      txtp_po_key        = ls_first-record_key.
      txtp_sap_object_id = ls_first-sap_object_id.
      txtp_result_msg    = ls_first-message.
      lv_session         = ls_first-session_id.
    ENDIF.
  ENDIF.

  IF lv_session IS NOT INITIAL AND txtp_po_key IS NOT INITIAL.
    SELECT * FROM zbdc_result_bup
      WHERE session_id = @lv_session
        AND record_key = @txtp_po_key
      ORDER BY row_index ASCENDING, step ASCENDING
      INTO TABLE @gt_log_0650.
  ELSEIF lv_session IS NOT INITIAL AND txtp_sap_object_id IS NOT INITIAL.
    SELECT * FROM zbdc_result_bup
      WHERE session_id = @lv_session
        AND sap_object_id = @txtp_sap_object_id
      ORDER BY row_index ASCENDING, step ASCENDING
      INTO TABLE @gt_log_0650.
  ELSEIF txtp_po_key IS NOT INITIAL.
    SELECT * FROM zbdc_result_bup
      WHERE record_key = @txtp_po_key
      ORDER BY session_id ASCENDING, row_index ASCENDING, step ASCENDING
      INTO TABLE @gt_log_0650.
  ELSE.
    REFRESH gt_log_0650.
  ENDIF.
ENDFORM.
*<<< END FORM load_result_detail

*>>> FORM display_result_detail - moved from Z_BDC_MASS_PO_ENTRY_F01_BUP

FORM display_result_detail.
  PERFORM load_result_detail.
  IF go_container_0650 IS INITIAL.
    CREATE OBJECT go_container_0650 EXPORTING container_name = 'CC_LOG_CONTAINER'.
    TRY.
        cl_salv_table=>factory(
          EXPORTING r_container  = go_container_0650
          IMPORTING r_salv_table = go_grid_0650
          CHANGING  t_table      = gt_log_0650 ).
        go_grid_0650->get_functions( )->set_all( abap_true ).
        go_grid_0650->get_columns( )->set_optimize( abap_true ).
        go_grid_0650->get_selections( )->set_selection_mode( if_salv_c_selection_mode=>row_column ).
        go_grid_0650->display( ).
      CATCH cx_salv_msg INTO DATA(lx_det).
        MESSAGE lx_det->get_text( ) TYPE 'I'.
      CATCH cx_salv_not_found.
    ENDTRY.
  ELSEIF go_grid_0650 IS BOUND.
    go_grid_0650->refresh( refresh_mode = if_salv_c_refresh=>full ).
  ENDIF.
ENDFORM.
*<<< END FORM display_result_detail

*>>> FORM z16_sync_staging_from_alv - moved from Z_BDC_MASS_PO_ENTRY_F01_BUP

FORM z16_sync_staging_from_alv.
  LOOP AT gt_staging_alv INTO DATA(ls_alv_final).
    READ TABLE gt_staging ASSIGNING FIELD-SYMBOL(<ls_stg_orig>)
      WITH KEY session_id = ls_alv_final-session_id row_index = ls_alv_final-row_index.
    IF sy-subrc = 0.
      MOVE-CORRESPONDING ls_alv_final TO <ls_stg_orig>.
    ENDIF.
  ENDLOOP.
ENDFORM.
*<<< END FORM z16_sync_staging_from_alv

*>>> FORM z16_log_alv_changes - moved from Z_BDC_MASS_PO_ENTRY_F01_BUP

FORM z16_log_alv_changes USING iv_action TYPE any.
  DATA ls_old_alv TYPE ty_staging_alv.
  LOOP AT gt_staging_alv INTO DATA(ls_new_alv).
    READ TABLE gt_staging INTO DATA(ls_old_db)
      WITH KEY session_id = ls_new_alv-session_id row_index = ls_new_alv-row_index.
    IF sy-subrc = 0.
      CLEAR ls_old_alv.
      MOVE-CORRESPONDING ls_old_db TO ls_old_alv.
      PERFORM z16_log_row_changes USING ls_old_alv ls_new_alv iv_action.
    ENDIF.
  ENDLOOP.
  COMMIT WORK.
ENDFORM.
*<<< END FORM z16_log_alv_changes
