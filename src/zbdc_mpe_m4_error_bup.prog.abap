*&---------------------------------------------------------------------*
*& Include          ZBDC_MPE_M4_ERROR_BUP
*& Purpose          M4 Error/Export/AI - structured errors, fix guide, AI fallback
*& Source split     FIX16 V5BR - logic moved from F01
*&---------------------------------------------------------------------*

*>>> FORM z16_batch_prefix_from_sid - moved from Z_BDC_MASS_PO_ENTRY_F01_BUP

FORM z16_batch_prefix_from_sid USING iv_session_id TYPE csequence
                               CHANGING cv_batch_prefix TYPE csequence.
  DATA: lv_sid    TYPE string,
        lv_len    TYPE i,
        lv_pos    TYPE i,
        lv_suffix TYPE string.

  CLEAR cv_batch_prefix.
  lv_sid = iv_session_id.
  CONDENSE lv_sid NO-GAPS.
  lv_len = strlen( lv_sid ).

  "New V4S format: BYYYYMMDDHHMMSS_001 -> BYYYYMMDDHHMMSS.
  IF lv_len >= 5.
    lv_pos = lv_len - 4.
    lv_suffix = lv_sid+lv_pos(4).
    IF lv_suffix+0(1) = '_' AND lv_suffix+1(3) CO '0123456789'.
      cv_batch_prefix = lv_sid+0(lv_pos).
      RETURN.
    ENDIF.
  ENDIF.

  "Compatibility with V4R two-digit suffix: SES_YYYYMMDD_HHMMSS_01.
  IF lv_len >= 4.
    lv_pos = lv_len - 3.
    lv_suffix = lv_sid+lv_pos(3).
    IF lv_suffix+0(1) = '_' AND lv_suffix+1(2) CO '0123456789'.
      cv_batch_prefix = lv_sid+0(lv_pos).
      RETURN.
    ENDIF.
  ENDIF.

  "Legacy single-session format: SES_YYYYMMDD_HHMMSS.
  IF lv_len >= 19 AND lv_sid+0(4) = 'SES_'.
    cv_batch_prefix = lv_sid+0(19).
  ELSE.
    cv_batch_prefix = iv_session_id.
  ENDIF.
ENDFORM.
*<<< END FORM z16_batch_prefix_from_sid

*>>> FORM FILTER_ERRORS_ONLY - moved from Z_BDC_MASS_PO_ENTRY_F01_BUP

FORM FILTER_ERRORS_ONLY.
  REFRESH GT_ERRORS.
  LOOP AT GT_STAGING INTO DATA(LS_E) WHERE STATUS = 'ERROR'. APPEND LS_E TO GT_ERRORS. ENDLOOP.
ENDFORM.
*<<< END FORM FILTER_ERRORS_ONLY

*>>> FORM z18_first_sm35_error - moved from Z_BDC_MASS_PO_ENTRY_F01_BUP


FORM z18_first_sm35_error
  USING    pv_qid    TYPE apqi-qid
  CHANGING cv_text   TYPE string
           cv_dynpro TYPE string.

  DATA: lt_log TYPE ty_t_bdclm,
        ls_log TYPE bdclm,
        lv_msg TYPE c LENGTH 255.

  CLEAR: cv_text, cv_dynpro.
  PERFORM z17_get_sm35_log USING pv_qid CHANGING lt_log.
  LOOP AT lt_log INTO ls_log WHERE mart = 'E' OR mart = 'A'.
    CLEAR lv_msg.
    IF ls_log-mid IS NOT INITIAL AND ls_log-mnr IS NOT INITIAL.
      CALL FUNCTION 'FORMAT_MESSAGE'
        EXPORTING id = ls_log-mid lang = sy-langu no = ls_log-mnr v1 = ls_log-mpar
        IMPORTING msg = lv_msg
        EXCEPTIONS OTHERS = 1.
    ENDIF.
    IF lv_msg IS INITIAL.
      lv_msg = |{ ls_log-mid }/{ ls_log-mnr } { ls_log-mpar }|.
      CONDENSE lv_msg.
    ENDIF.
    cv_text   = lv_msg.
    cv_dynpro = |{ ls_log-module }/{ ls_log-dynr }|.
    RETURN.
  ENDLOOP.
ENDFORM.

*&---------------------------------------------------------------------*
*& V5AK - Read real SM35 proof for one business document group
*&---------------------------------------------------------------------*
*<<< END FORM z18_first_sm35_error

*>>> FORM IS_LOCK_ERROR - moved from Z_BDC_MASS_PO_ENTRY_F01_BUP

FORM IS_LOCK_ERROR CHANGING CV_LOCKED TYPE ABAP_BOOL.
  DATA lv_reason TYPE string.
  PERFORM z17_is_transient_bdc CHANGING cv_locked lv_reason.
ENDFORM.

*&---------------------------------------------------------------------*
*& BUILD_ERROR_TEXT - gom message de debug duoc tat ca case
*& Neu khong co E/A thi dump S/W/I de tranh "khong bat duoc message"
*&---------------------------------------------------------------------*
*<<< END FORM IS_LOCK_ERROR

*>>> FORM BUILD_ERROR_TEXT - moved from Z_BDC_MASS_PO_ENTRY_F01_BUP
FORM BUILD_ERROR_TEXT CHANGING CV_MSG TYPE STRING.
  DATA: LV_T       TYPE C LENGTH 220,
        LV_LINE    TYPE STRING,
        LV_HAS_ERR TYPE ABAP_BOOL.

  CLEAR CV_MSG.
  LV_HAS_ERR = ABAP_FALSE.

  LOOP AT MESSTAB WHERE MSGTYP = 'E' OR MSGTYP = 'A'.
    LV_HAS_ERR = ABAP_TRUE.
    CLEAR LV_T.
    CALL FUNCTION 'FORMAT_MESSAGE'
      EXPORTING
        ID   = MESSTAB-MSGID
        LANG = SY-LANGU
        NO   = MESSTAB-MSGNR
        V1   = MESSTAB-MSGV1
        V2   = MESSTAB-MSGV2
        V3   = MESSTAB-MSGV3
        V4   = MESSTAB-MSGV4
      IMPORTING
        MSG  = LV_T
      EXCEPTIONS
        OTHERS = 1.
    IF SY-SUBRC <> 0 OR LV_T IS INITIAL.
      LV_T = |{ MESSTAB-MSGID }/{ MESSTAB-MSGNR } { MESSTAB-MSGV1 } { MESSTAB-MSGV2 } { MESSTAB-MSGV3 } { MESSTAB-MSGV4 }|.
    ENDIF.
    LV_LINE = LV_T.
    CONDENSE LV_LINE.
    CV_MSG = |{ CV_MSG } { LV_LINE };|.
    IF STRLEN( CV_MSG ) > 240.
      EXIT.
    ENDIF.
  ENDLOOP.

  IF LV_HAS_ERR = ABAP_FALSE.
    LOOP AT MESSTAB.
      CLEAR LV_T.
      CALL FUNCTION 'FORMAT_MESSAGE'
        EXPORTING
          ID   = MESSTAB-MSGID
          LANG = SY-LANGU
          NO   = MESSTAB-MSGNR
          V1   = MESSTAB-MSGV1
          V2   = MESSTAB-MSGV2
          V3   = MESSTAB-MSGV3
          V4   = MESSTAB-MSGV4
        IMPORTING
          MSG  = LV_T
        EXCEPTIONS
          OTHERS = 1.
      IF SY-SUBRC <> 0 OR LV_T IS INITIAL.
        LV_T = |{ MESSTAB-MSGTYP } { MESSTAB-MSGID }/{ MESSTAB-MSGNR } { MESSTAB-MSGV1 } { MESSTAB-MSGV2 } { MESSTAB-MSGV3 } { MESSTAB-MSGV4 }|.
      ENDIF.
      LV_LINE = LV_T.
      CONDENSE LV_LINE.
      CV_MSG = |{ CV_MSG } { LV_LINE };|.
      IF STRLEN( CV_MSG ) > 240.
        EXIT.
      ENDIF.
    ENDLOOP.
  ENDIF.

  IF CV_MSG IS INITIAL.
    CV_MSG = 'BDC failed: MESSTAB rong. Kiem tra script screen/OKCODE/mode A.'.
  ENDIF.
  SHIFT CV_MSG LEFT DELETING LEADING SPACE.

ENDFORM.

*&---------------------------------------------------------------------*
*& NORMALIZE_BDC_MESSAGE
*& Converts raw BDCMSGCOLL into one structured message record.
*& Safer than depending on CONVERT_BDCMSGCOLL_TO_BAPIRET2 because every
*& SAP system that supports BDC has BDCMSGCOLL + FORMAT_MESSAGE.
*&---------------------------------------------------------------------*
*<<< END FORM BUILD_ERROR_TEXT

*>>> FORM NORMALIZE_BDC_MESSAGE - moved from Z_BDC_MASS_PO_ENTRY_F01_BUP
FORM NORMALIZE_BDC_MESSAGE
  USING    PS_MSG  TYPE BDCMSGCOLL
  CHANGING PS_NORM TYPE TY_BDC_MSG_NORM.

  DATA: LV_TEXT TYPE C LENGTH 255.

  CLEAR: PS_NORM, LV_TEXT.

  CALL FUNCTION 'FORMAT_MESSAGE'
    EXPORTING
      ID   = PS_MSG-MSGID
      LANG = SY-LANGU
      NO   = PS_MSG-MSGNR
      V1   = PS_MSG-MSGV1
      V2   = PS_MSG-MSGV2
      V3   = PS_MSG-MSGV3
      V4   = PS_MSG-MSGV4
    IMPORTING
      MSG  = LV_TEXT
    EXCEPTIONS
      OTHERS = 1.

  IF SY-SUBRC <> 0 OR LV_TEXT IS INITIAL.
    LV_TEXT = |{ PS_MSG-MSGTYP } { PS_MSG-MSGID }/{ PS_MSG-MSGNR } { PS_MSG-MSGV1 } { PS_MSG-MSGV2 } { PS_MSG-MSGV3 } { PS_MSG-MSGV4 }|.
  ENDIF.

  PS_NORM-MSG_TYPE     = PS_MSG-MSGTYP.
  PS_NORM-MSG_ID       = PS_MSG-MSGID.
  PS_NORM-MSG_NUMBER   = PS_MSG-MSGNR.
  PS_NORM-MSGV1        = PS_MSG-MSGV1.
  PS_NORM-MSGV2        = PS_MSG-MSGV2.
  PS_NORM-MSGV3        = PS_MSG-MSGV3.
  PS_NORM-MSGV4        = PS_MSG-MSGV4.
  PS_NORM-PROGRAM_NAME = PS_MSG-DYNAME.
  PS_NORM-DYNPRO_NO    = PS_MSG-DYNUMB.
  PS_NORM-FIELD_NAME   = PS_MSG-FLDNAME.
  PS_NORM-MESSAGE      = LV_TEXT.

  CASE PS_NORM-MSG_TYPE.
    WHEN 'S'.
      PS_NORM-EXEC_STATUS = GC_ST_SUCCESS.
    WHEN 'W'.
      PS_NORM-EXEC_STATUS = GC_ST_WARNING.
    WHEN 'I'.
      PS_NORM-EXEC_STATUS = 'INFO'.
    WHEN OTHERS.
      PS_NORM-EXEC_STATUS = GC_ST_ERROR.
  ENDCASE.

  PERFORM BUILD_BDC_ACTION_HINT
    USING    PS_NORM-MESSAGE PS_NORM-FIELD_NAME
    CHANGING PS_NORM-ACTION_HINT PS_NORM-RETRY_FLAG.

ENDFORM.

*&---------------------------------------------------------------------*
*& BUILD_BDC_ACTION_HINT
*& Rule-based fix hint for dashboard/export/fix guide.
*&---------------------------------------------------------------------*
*<<< END FORM NORMALIZE_BDC_MESSAGE

*>>> FORM BUILD_BDC_ACTION_HINT - moved from Z_BDC_MASS_PO_ENTRY_F01_BUP
FORM BUILD_BDC_ACTION_HINT
  USING    PV_MESSAGE TYPE ANY
           PV_FIELD   TYPE ANY
  CHANGING CV_HINT    TYPE ANY
           CV_RETRY   TYPE ANY.

  DATA: LV_TEXT      TYPE STRING,
        LV_FIELD     TYPE STRING,
        LV_TRANSIENT TYPE ABAP_BOOL,
        LV_REASON    TYPE STRING.

  CLEAR: CV_HINT, CV_RETRY.

  LV_TEXT  = PV_MESSAGE.
  LV_FIELD = PV_FIELD.
  TRANSLATE LV_TEXT TO LOWER CASE.
  TRANSLATE LV_FIELD TO LOWER CASE.

  PERFORM z17_text_transient
    USING    LV_TEXT
    CHANGING LV_TRANSIENT LV_REASON.
  IF LV_TRANSIENT = ABAP_TRUE.
    CV_RETRY = 'X'.
    CV_HINT  = |Transient technical issue ({ LV_REASON }): wait briefly and retry; do not change business data first.|.
    RETURN.
  ENDIF.

  IF LV_TEXT CS 'plant' AND ( LV_TEXT CS 'storage location' OR LV_TEXT CS 'sloc' OR LV_TEXT CS 'lgort' ).
    CV_HINT = 'Check Plant-Storage Location assignment in SAP customizing/master data, then correct staging row.'.
    RETURN.
  ENDIF.

  IF LV_TEXT CS 'storage location' OR LV_TEXT CS 'lgort'.
    CV_HINT = 'Check storage location value and plant assignment, then validate again.'.
    RETURN.
  ENDIF.

  IF LV_TEXT CS 'plant' OR LV_FIELD CS 'werks'.
    CV_HINT = 'Check plant value, material extension for plant, and purchasing organization setup.'.
    RETURN.
  ENDIF.

  IF LV_TEXT CS 'vendor' OR LV_FIELD CS 'lifnr'.
    CV_HINT = 'Check vendor master/purchasing data/block status, then correct vendor in source file.'.
    RETURN.
  ENDIF.

  IF LV_TEXT CS 'material' OR LV_FIELD CS 'matnr'.
    CV_HINT = 'Check material master/plant extension/UoM, then correct material or extend material.'.
    RETURN.
  ENDIF.

  IF LV_TEXT CS 'purchase order'
     OR LV_TEXT CS 'purchasing document'
     OR LV_TEXT CS 'po number'
     OR LV_FIELD CS 'ebeln'.
    CV_HINT = 'Check PO number/item/status before posting MIGO, then correct reference document.'.
    RETURN.
  ENDIF.

  IF LV_TEXT CS 'quantity'
     OR LV_TEXT CS 'qty'
     OR LV_FIELD CS 'menge'.
    CV_HINT = 'Check quantity format, open quantity, unit of measure, and tolerance.'.
    RETURN.
  ENDIF.

  IF LV_TEXT CS 'tax'
     OR LV_TEXT CS 'mwskz'.
    CV_HINT = 'Check tax code validity for company code/country and correct tax field.'.
    RETURN.
  ENDIF.

  IF LV_TEXT CS 'required'
     OR LV_TEXT CS 'mandatory'
     OR LV_TEXT CS 'enter'
     OR LV_TEXT CS 'missing'
     OR LV_TEXT CS 'initial'.
    CV_HINT = 'Fill mandatory field or fix mapping profile, then validate again.'.
    RETURN.
  ENDIF.

  IF LV_TEXT CS 'not defined'
     OR LV_TEXT CS 'does not exist'
     OR LV_TEXT CS 'not exist'
     OR LV_TEXT CS 'invalid'
     OR LV_TEXT CS 'not allowed'
     OR LV_TEXT CS 'not possible'.
    CV_HINT = 'Check SAP master data/customizing and correct the source value.'.
    RETURN.
  ENDIF.

  IF CV_HINT IS INITIAL.
    CV_HINT = 'Open SAP message detail, correct staging row/mapping, validate again, then rerun.'.
  ENDIF.

ENDFORM.

*&---------------------------------------------------------------------*
*& SAVE_BDC_MESSAGE_LOGS - MUC 3/4: persist normalized BDC messages
*&  - Raw source: BDCMSGCOLL from CALL TRANSACTION ... MESSAGES INTO MESSTAB
*&  - Normalized output: ZBDC_RESULT_BUP structured log
*&  - Supports dashboard, drilldown, retry, AI analyst, fix guide export
*&---------------------------------------------------------------------*
*<<< END FORM BUILD_BDC_ACTION_HINT

*>>> FORM SAVE_BDC_MESSAGE_LOGS - moved from Z_BDC_MASS_PO_ENTRY_F01_BUP
FORM SAVE_BDC_MESSAGE_LOGS
  USING PT_GROUP   TYPE TY_T_STAGING_ALV
        PV_TCODE   TYPE SY-TCODE
        PV_ATTEMPT TYPE I
        PV_OBJ     TYPE ANY.

  DATA: LS_G        TYPE TY_STAGING_ALV,
        LS_MSG      TYPE BDCMSGCOLL,
        LS_NORM     TYPE TY_BDC_MSG_NORM,
        LS_RES      TYPE ZBDC_RESULT_BUP,
        LV_SEQ      TYPE I,
        LV_STEP_MAX TYPE ZBDC_RESULT_BUP-STEP,
        LV_TS       TYPE TZNTSTMPS.

  FIELD-SYMBOLS <FV> TYPE ANY.

  READ TABLE PT_GROUP INTO LS_G INDEX 1.
  IF SY-SUBRC <> 0.
    RETURN.
  ENDIF.

  IF MESSTAB[] IS INITIAL.
    PERFORM SAVE_SYNTHETIC_ENGINE_LOG
      USING PT_GROUP PV_TCODE PV_ATTEMPT GC_ST_WARNING
            'MESSTAB rong sau CALL TRANSACTION. Kiem tra mode A, script screen/OKCODE hoac CTU_PARAMS.'
            PV_OBJ ''.
    RETURN.
  ENDIF.

  CLEAR LV_STEP_MAX.
  SELECT MAX( STEP ) FROM ZBDC_RESULT_BUP INTO @LV_STEP_MAX
    WHERE SESSION_ID = @LS_G-SESSION_ID
      AND RECORD_KEY = @LS_G-RECORD_KEY
      AND ROW_INDEX  = @LS_G-ROW_INDEX.
  LV_SEQ = LV_STEP_MAX.

  LOOP AT MESSTAB INTO LS_MSG.
    LV_SEQ = LV_SEQ + 1.
    CLEAR: LS_NORM, LS_RES.

    PERFORM NORMALIZE_BDC_MESSAGE
      USING    LS_MSG
      CHANGING LS_NORM.

    GET TIME STAMP FIELD LV_TS.

    DEFINE SET_RES.
      ASSIGN COMPONENT &1 OF STRUCTURE LS_RES TO <FV>.
      IF SY-SUBRC = 0.
        <FV> = &2.
      ENDIF.
    END-OF-DEFINITION.

    SET_RES 'SESSION_ID'    LS_G-SESSION_ID.
    SET_RES 'RECORD_KEY'    LS_G-RECORD_KEY.
    SET_RES 'GROUP_KEY'     LS_G-RECORD_KEY.
    SET_RES 'ROW_INDEX'     LS_G-ROW_INDEX.
    SET_RES 'TCODE'         PV_TCODE.
    SET_RES 'SAP_OBJECT_ID' PV_OBJ.

    SET_RES 'MSG_TYPE'      LS_NORM-MSG_TYPE.
    SET_RES 'MSGTYP'        LS_NORM-MSG_TYPE.
    SET_RES 'MSG_ID'        LS_NORM-MSG_ID.
    SET_RES 'MSGID'         LS_NORM-MSG_ID.
    SET_RES 'MSG_NUMBER'    LS_NORM-MSG_NUMBER.
    SET_RES 'MSGNR'         LS_NORM-MSG_NUMBER.
    SET_RES 'MSG_NO'        LS_NORM-MSG_NUMBER.
    SET_RES 'MSGV1'         LS_NORM-MSGV1.
    SET_RES 'MSGV2'         LS_NORM-MSGV2.
    SET_RES 'MSGV3'         LS_NORM-MSGV3.
    SET_RES 'MSGV4'         LS_NORM-MSGV4.

    SET_RES 'MESSAGE'       LS_NORM-MESSAGE.
    SET_RES 'MESSAGE_TEXT'  LS_NORM-MESSAGE.

    SET_RES 'PROGRAM_NAME'  LS_NORM-PROGRAM_NAME.
    SET_RES 'DYNAME'        LS_NORM-PROGRAM_NAME.
    SET_RES 'DYNPRO_NO'     LS_NORM-DYNPRO_NO.
    SET_RES 'DYNUMB'        LS_NORM-DYNPRO_NO.
    SET_RES 'DYNPRO'        LS_NORM-DYNPRO_NO.
    SET_RES 'FIELD_NAME'    LS_NORM-FIELD_NAME.

    SET_RES 'SCREEN_STEP'   LV_SEQ.
    SET_RES 'STEP_SEQ'      LV_SEQ.
    SET_RES 'MSG_SEQ'       LV_SEQ.
    SET_RES 'RESULT_SEQ'    LV_SEQ.
    SET_RES 'STEP'          LV_SEQ.

    SET_RES 'EXEC_STATUS'   LS_NORM-EXEC_STATUS.
    SET_RES 'LOCK_REASON'   LS_NORM-ACTION_HINT.
    SET_RES 'ATTEMPT_NO'    PV_ATTEMPT.
    SET_RES 'ATTEMPT'       PV_ATTEMPT.
    SET_RES 'RETRY_FLAG'    LS_NORM-RETRY_FLAG.

    SET_RES 'CREATED_AT'    LV_TS.
    SET_RES 'CREATED_ON'    SY-DATUM.
    SET_RES 'CREATED_TM'    SY-UZEIT.
    SET_RES 'CREATED_TIME'  SY-UZEIT.
    SET_RES 'CREATED_BY'    SY-UNAME.

    INSERT ZBDC_RESULT_BUP FROM LS_RES.
    IF SY-SUBRC <> 0.
      MODIFY ZBDC_RESULT_BUP FROM LS_RES.
    ENDIF.
  ENDLOOP.

ENDFORM.

*&---------------------------------------------------------------------*
*& SAVE_SYNTHETIC_ENGINE_LOG - logs engine decisions not returned by SAP
*& Examples: empty BDCDATA, BDC_INSERT failure, retry decision, empty MESSTAB
*&---------------------------------------------------------------------*
*<<< END FORM SAVE_BDC_MESSAGE_LOGS

*>>> FORM SAVE_SYNTHETIC_ENGINE_LOG - moved from Z_BDC_MASS_PO_ENTRY_F01_BUP
FORM SAVE_SYNTHETIC_ENGINE_LOG
  USING PT_GROUP   TYPE TY_T_STAGING_ALV
        PV_TCODE   TYPE SY-TCODE
        PV_ATTEMPT TYPE I
        PV_STATUS  TYPE ANY
        PV_MSG     TYPE ANY
        PV_OBJ     TYPE ANY
        PV_RETRY   TYPE ANY.

  DATA: LS_G        TYPE TY_STAGING_ALV,
        LS_RES      TYPE ZBDC_RESULT_BUP,
        LV_TYPE     TYPE C LENGTH 1,
        LV_SEQ      TYPE I,
        LV_STEP_MAX TYPE ZBDC_RESULT_BUP-STEP,
        LV_TS       TYPE TZNTSTMPS,
        LV_HINT     TYPE C LENGTH 120,
        LV_RETRY    TYPE C LENGTH 1.

  FIELD-SYMBOLS <FV> TYPE ANY.

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

  CLEAR: LV_HINT, LV_RETRY.
  PERFORM BUILD_BDC_ACTION_HINT
    USING    PV_MSG 'ENGINE'
    CHANGING LV_HINT LV_RETRY.

  IF PV_RETRY IS NOT INITIAL.
    LV_RETRY = PV_RETRY.
  ENDIF.

  CLEAR LV_STEP_MAX.
  SELECT MAX( STEP ) FROM ZBDC_RESULT_BUP INTO @LV_STEP_MAX
    WHERE SESSION_ID = @LS_G-SESSION_ID
      AND RECORD_KEY = @LS_G-RECORD_KEY
      AND ROW_INDEX  = @LS_G-ROW_INDEX.
  LV_SEQ = LV_STEP_MAX + 1.

  GET TIME STAMP FIELD LV_TS.

  DEFINE SET_RES2.
    ASSIGN COMPONENT &1 OF STRUCTURE LS_RES TO <FV>.
    IF SY-SUBRC = 0.
      <FV> = &2.
    ENDIF.
  END-OF-DEFINITION.

  CLEAR LS_RES.
  SET_RES2 'SESSION_ID'    LS_G-SESSION_ID.
  SET_RES2 'RECORD_KEY'    LS_G-RECORD_KEY.
  SET_RES2 'GROUP_KEY'     LS_G-RECORD_KEY.
  SET_RES2 'ROW_INDEX'     LS_G-ROW_INDEX.
  SET_RES2 'TCODE'         PV_TCODE.
  SET_RES2 'SAP_OBJECT_ID' PV_OBJ.

  SET_RES2 'MSG_TYPE'      LV_TYPE.
  SET_RES2 'MSGTYP'        LV_TYPE.
  SET_RES2 'MSG_ID'        'ZBDC'.
  SET_RES2 'MSGID'         'ZBDC'.
  SET_RES2 'MSG_NUMBER'    '000'.
  SET_RES2 'MSGNR'         '000'.
  SET_RES2 'MSG_NO'        '000'.

  SET_RES2 'MESSAGE'       PV_MSG.
  SET_RES2 'MESSAGE_TEXT'  PV_MSG.

  SET_RES2 'PROGRAM_NAME'  'Z_BDC_ENGINE'.
  SET_RES2 'DYNAME'        'Z_BDC_ENGINE'.
  SET_RES2 'DYNPRO_NO'     '0000'.
  SET_RES2 'DYNUMB'        '0000'.
  SET_RES2 'DYNPRO'        '0000'.
  SET_RES2 'FIELD_NAME'    'ENGINE'.

  SET_RES2 'SCREEN_STEP'   LV_SEQ.
  SET_RES2 'STEP_SEQ'      LV_SEQ.
  SET_RES2 'MSG_SEQ'       LV_SEQ.
  SET_RES2 'RESULT_SEQ'    LV_SEQ.
  SET_RES2 'STEP'          LV_SEQ.

  SET_RES2 'EXEC_STATUS'   PV_STATUS.
  SET_RES2 'LOCK_REASON'   LV_HINT.
  SET_RES2 'ATTEMPT_NO'    PV_ATTEMPT.
  SET_RES2 'ATTEMPT'       PV_ATTEMPT.
  SET_RES2 'RETRY_FLAG'    LV_RETRY.

  SET_RES2 'CREATED_AT'    LV_TS.
  SET_RES2 'CREATED_ON'    SY-DATUM.
  SET_RES2 'CREATED_TM'    SY-UZEIT.
  SET_RES2 'CREATED_TIME'  SY-UZEIT.
  SET_RES2 'CREATED_BY'    SY-UNAME.

  INSERT ZBDC_RESULT_BUP FROM LS_RES.
  IF SY-SUBRC <> 0.
    MODIFY ZBDC_RESULT_BUP FROM LS_RES.
  ENDIF.

ENDFORM.

*& UPDATE_EXEC_COUNTERS - single source for execution counters
*&---------------------------------------------------------------------*
*<<< END FORM SAVE_SYNTHETIC_ENGINE_LOG

*>>> FORM SET_EXEC_ACTION_HINT - moved from Z_BDC_MASS_PO_ENTRY_F01_BUP


FORM SET_EXEC_ACTION_HINT CHANGING CS_EXEC TYPE TY_EXEC_DISP.
  CLEAR CS_EXEC-ACTION_HINT.

  CASE CS_EXEC-RUN_STATUS.
    WHEN GC_ST_READY.
      CS_EXEC-ACTION_HINT = 'Execute All or Execute Selected'.
    WHEN GC_ST_SUCCESS.
      IF CS_EXEC-SAP_OBJECT_ID IS NOT INITIAL.
        CS_EXEC-ACTION_HINT = 'Review SAP Object; open Dashboard proof'.
      ELSE.
        CS_EXEC-ACTION_HINT = 'Success; check result log for document number'.
      ENDIF.
    WHEN GC_ST_SM35Q.
      IF CS_EXEC-MESSAGE CS 'is processing'.
        CS_EXEC-ACTION_HINT = 'Refresh cockpit; monitor SM35/SM37 until completion'.
      ELSEIF CS_EXEC-MESSAGE CS 'background job'.
        CS_EXEC-ACTION_HINT = 'Monitor SM37 and inspect the SM35 session log'.
      ELSEIF CS_EXEC-MESSAGE CS 'returned from'.
        CS_EXEC-ACTION_HINT = 'Review SM35 log; correct incorrect transactions if any'.
      ELSE.
        CS_EXEC-ACTION_HINT = 'Open SM35 Monitor; start the configured interactive profile'.
      ENDIF.
    WHEN GC_ST_ERROR.
      CS_EXEC-ACTION_HINT = 'Check Fix Hint; correct source; retry selected group'.
    WHEN GC_ST_WARNING OR 'PARTIAL'.
      CS_EXEC-ACTION_HINT = 'Review warning; refresh dashboard before closing'.
    WHEN OTHERS.
      CS_EXEC-ACTION_HINT = 'Refresh cockpit or reload staging session'.
  ENDCASE.
ENDFORM.
*<<< END FORM SET_EXEC_ACTION_HINT

*>>> FORM EXPORT_EXEC_LOG_CSV - moved from Z_BDC_MASS_PO_ENTRY_F01_BUP

FORM EXPORT_EXEC_LOG_CSV.
  DATA: LT_LINES       TYPE STRING_TABLE,
        LV_LINE        TYPE STRING,
        LV_CELL        TYPE STRING,
        LV_FILENAME    TYPE STRING,
        LV_PATH        TYPE STRING,
        LV_FULLPATH    TYPE STRING,
        LV_USER_ACTION TYPE I.

  IF GT_EXEC_DISP IS INITIAL.
    MESSAGE 'Khong co cockpit log de export.' TYPE 'W'.
    RETURN.
  ENDIF.

  APPEND '<html xmlns:x="urn:schemas-microsoft-com:office:excel">' TO LT_LINES.
  APPEND '<head><meta http-equiv="Content-Type" content="text/html; charset=utf-8" /></head>' TO LT_LINES.
  APPEND '<body><table border="1">' TO LT_LINES.
  APPEND '<tr><th>SESSION_ID</th><th>GROUP_KEY</th><th>TCODE</th><th>ITEM_COUNT</th><th>RUN_STATUS</th><th>HEALTH_TEXT</th><th>SAP_OBJECT_ID</th><th>DRILL_TCODE</th><th>ATTEMPT</th><th>MSG_TYPE</th><th>MESSAGE</th><th>ACTION_HINT</th></tr>' TO LT_LINES.

  LOOP AT GT_EXEC_DISP INTO DATA(LS_EXEC_EXP).
    LV_LINE = '<tr>'.
    PERFORM M4_EXCEL_CELL USING LS_EXEC_EXP-SESSION_ID    CHANGING LV_CELL. LV_LINE = LV_LINE && LV_CELL.
    PERFORM M4_EXCEL_CELL USING LS_EXEC_EXP-GROUP_KEY     CHANGING LV_CELL. LV_LINE = LV_LINE && LV_CELL.
    PERFORM M4_EXCEL_CELL USING LS_EXEC_EXP-TCODE         CHANGING LV_CELL. LV_LINE = LV_LINE && LV_CELL.
    PERFORM M4_EXCEL_CELL USING LS_EXEC_EXP-ITEM_COUNT    CHANGING LV_CELL. LV_LINE = LV_LINE && LV_CELL.
    PERFORM M4_EXCEL_CELL USING LS_EXEC_EXP-RUN_STATUS    CHANGING LV_CELL. LV_LINE = LV_LINE && LV_CELL.
    PERFORM M4_EXCEL_CELL USING LS_EXEC_EXP-HEALTH_TEXT   CHANGING LV_CELL. LV_LINE = LV_LINE && LV_CELL.
    PERFORM M4_EXCEL_CELL USING LS_EXEC_EXP-SAP_OBJECT_ID CHANGING LV_CELL. LV_LINE = LV_LINE && LV_CELL.
    PERFORM M4_EXCEL_CELL USING LS_EXEC_EXP-DRILL_TCODE   CHANGING LV_CELL. LV_LINE = LV_LINE && LV_CELL.
    PERFORM M4_EXCEL_CELL USING LS_EXEC_EXP-ATTEMPT       CHANGING LV_CELL. LV_LINE = LV_LINE && LV_CELL.
    PERFORM M4_EXCEL_CELL USING LS_EXEC_EXP-MSG_TYPE      CHANGING LV_CELL. LV_LINE = LV_LINE && LV_CELL.
    PERFORM M4_EXCEL_CELL USING LS_EXEC_EXP-MESSAGE       CHANGING LV_CELL. LV_LINE = LV_LINE && LV_CELL.
    PERFORM M4_EXCEL_CELL USING LS_EXEC_EXP-ACTION_HINT   CHANGING LV_CELL. LV_LINE = LV_LINE && LV_CELL.
    LV_LINE = LV_LINE && '</tr>'.
    APPEND LV_LINE TO LT_LINES.
  ENDLOOP.

  APPEND '</table></body></html>' TO LT_LINES.

  CL_GUI_FRONTEND_SERVICES=>FILE_SAVE_DIALOG(
    EXPORTING
      WINDOW_TITLE      = 'Export BDC Execution Cockpit Log to Excel'
      DEFAULT_EXTENSION = 'xls'
      DEFAULT_FILE_NAME = 'BDC_Execution_Cockpit_Log.xls'
      FILE_FILTER       = 'Excel Workbook (*.xls)|*.xls|All (*.*)|*.*'
    CHANGING
      FILENAME          = LV_FILENAME
      PATH              = LV_PATH
      FULLPATH          = LV_FULLPATH
      USER_ACTION       = LV_USER_ACTION
    EXCEPTIONS
      OTHERS            = 1 ).

  IF SY-SUBRC <> 0 OR LV_USER_ACTION <> CL_GUI_FRONTEND_SERVICES=>ACTION_OK
     OR LV_FULLPATH IS INITIAL.
    RETURN.
  ENDIF.

  CL_GUI_FRONTEND_SERVICES=>GUI_DOWNLOAD(
    EXPORTING
      FILENAME = LV_FULLPATH
      FILETYPE = 'ASC'
      CODEPAGE = '4110'
    CHANGING
      DATA_TAB = LT_LINES
    EXCEPTIONS
      OTHERS = 1 ).

  IF SY-SUBRC = 0.
    MESSAGE 'Da export BDC cockpit log Excel (.xls).' TYPE 'S'.
  ELSE.
    MESSAGE |Export Excel loi SY-SUBRC={ SY-SUBRC }.| TYPE 'E'.
  ENDIF.
ENDFORM.
*<<< END FORM EXPORT_EXEC_LOG_CSV

*>>> FORM z28_text_is_gui_control_error - moved from Z_BDC_MASS_PO_ENTRY_F01_BUP
FORM z28_text_is_gui_control_error
  USING    pv_text TYPE csequence
  CHANGING cv_hit  TYPE abap_bool.

  DATA lv_text TYPE string.

  CLEAR cv_hit.
  lv_text = pv_text.
  TRANSLATE lv_text TO UPPER CASE.

  IF lv_text CS 'GUI CANNOT BE REACHED' OR
     lv_text CS 'UNABLE TO INITIALIZE ABAP CONTROL FRAMEWORK' OR
     lv_text CS 'CONTROL FRAMEWORK: FATAL ERROR' OR
     lv_text CS 'CONTROL FRAMEWORK FATAL ERROR' OR
     lv_text CS 'SAP GUI CONTROL FRAMEWORK' OR
     lv_text CS 'ABAP CONTROL FRAMEWORK' OR
     lv_text CS 'SAPLMEGUI' OR
     lv_text CS 'RAISE_EXCEPTION' OR
     lv_text CS 'MESSAGE DC 006' OR
     lv_text CS 'DC006' OR
     lv_text CS 'DC 006'.
    cv_hit = abap_true.
  ENDIF.
ENDFORM.
*<<< END FORM z28_text_is_gui_control_error

*>>> FORM z28_group_gui_control_error - moved from Z_BDC_MASS_PO_ENTRY_F01_BUP

FORM z28_group_gui_control_error
  USING    pt_group  TYPE ty_t_staging_alv
  CHANGING cv_hit    TYPE abap_bool
           cv_reason TYPE string.

  DATA: ls_first TYPE ty_staging_alv,
        lt_res   TYPE STANDARD TABLE OF zbdc_result_bup,
        ls_res   TYPE zbdc_result_bup,
        lv_text  TYPE string,
        lv_line_hit TYPE abap_bool.

  CLEAR: cv_hit, cv_reason.
  READ TABLE pt_group INTO ls_first INDEX 1.
  IF sy-subrc <> 0.
    RETURN.
  ENDIF.

  IF ls_first-record_key IS INITIAL.
    SELECT *
      FROM zbdc_result_bup
      INTO TABLE @lt_res
      WHERE session_id = @ls_first-session_id
        AND row_index  = @ls_first-row_index
        AND field_name = 'SM35'.
  ELSE.
    SELECT *
      FROM zbdc_result_bup
      INTO TABLE @lt_res
      WHERE session_id = @ls_first-session_id
        AND record_key = @ls_first-record_key
        AND field_name = 'SM35'.
  ENDIF.

  LOOP AT lt_res INTO ls_res.
    "ZBDC_RESULT_BUP is deliberately DDIC-tolerant: PROGRAM_NAME /
    "DYNPRO_NO are optional columns and must never be referenced statically.
    "The persisted MESSAGE already contains the formatted SM35 protocol text
    "used to identify DC006 / Control Framework failures.
    lv_text = ls_res-message.
    CLEAR lv_line_hit.
    PERFORM z28_text_is_gui_control_error
      USING    lv_text
      CHANGING lv_line_hit.
    IF lv_line_hit = abap_true.
      cv_hit = abap_true.
      cv_reason = ls_res-message.
      IF cv_reason IS INITIAL.
        cv_reason = 'SAP GUI Control Framework is not reachable in SM35 background processing.' .
      ENDIF.
      RETURN.
    ENDIF.
  ENDLOOP.
ENDFORM.
*<<< END FORM z28_group_gui_control_error

*>>> FORM z16_show_issue_detail_safe - moved from Z_BDC_MASS_PO_ENTRY_F01_BUP

FORM z16_show_issue_detail_safe.
  TYPES: BEGIN OF ty_issue_detail,
           session_id    TYPE zbdc_staging_bup-session_id,
           file_source   TYPE char80,
           sheet_name    TYPE char40,
           group_key     TYPE zbdc_staging_bup-record_key,
           tcode         TYPE zbdc_staging_bup-tcode,
           lifecycle     TYPE char20,
           sap_object    TYPE zbdc_result_bup-sap_object_id,
           health_check  TYPE char80,
           error_message TYPE char255,
           next_action   TYPE char120,
         END OF ty_issue_detail.

  DATA: lt_detail TYPE STANDARD TABLE OF ty_issue_detail,
        ls_detail TYPE ty_issue_detail,
        ls_stg    TYPE ty_staging_alv,
        ls_exec   TYPE ty_exec_disp,
        lo_alv    TYPE REF TO cl_salv_table,
        lo_cols   TYPE REF TO cl_salv_columns_table,
        lx_salv   TYPE REF TO cx_salv_msg.

  PERFORM z16_pick_0500_issue.
  IF g_edit_index IS INITIAL.
    CALL FUNCTION 'POPUP_TO_INFORM'
      EXPORTING
        titel = 'No Runtime Error'
        txt1  = 'The current queue has no ERROR, WARNING, SKIPPED or PARTIAL group.'
        txt2  = 'Execute the queue first, or select a failed group before opening Error Detail.'.
    RETURN.
  ENDIF.

  READ TABLE gt_staging_alv INTO ls_stg INDEX g_edit_index.
  IF sy-subrc <> 0.
    CALL FUNCTION 'POPUP_TO_INFORM'
      EXPORTING
        titel = 'Error Detail Unavailable'
        txt1  = 'The failed execution group could not be matched to staging data.'
        txt2  = 'Refresh the queue and try again.'.
    RETURN.
  ENDIF.

  READ TABLE gt_exec_disp INTO ls_exec
    WITH KEY session_id = ls_stg-session_id
             group_key  = ls_stg-record_key.

  ls_detail-session_id    = ls_stg-session_id.
  ls_detail-group_key     = ls_stg-record_key.
  ls_detail-tcode         = ls_stg-tcode.
  ls_detail-lifecycle     = ls_stg-status.
  ls_detail-error_message = ls_stg-error_msg.
  IF ls_detail-error_message IS INITIAL.
    ls_detail-error_message = ls_stg-last_error.
  ENDIF.

  IF sy-subrc = 0.
    ls_detail-file_source  = ls_exec-source_file.
    ls_detail-sheet_name   = ls_exec-sheet_name.
    ls_detail-sap_object   = ls_exec-sap_object_id.
    ls_detail-health_check = ls_exec-health_text.
    ls_detail-next_action  = ls_exec-action_hint.
    IF ls_detail-error_message IS INITIAL.
      ls_detail-error_message = ls_exec-message.
    ENDIF.
  ENDIF.

  IF ls_detail-next_action IS INITIAL.
    ls_detail-next_action = 'Open Retry, correct the staging value, validate again, then resubmit to 0500.'.
  ENDIF.
  APPEND ls_detail TO lt_detail.

  TRY.
      cl_salv_table=>factory(
        IMPORTING r_salv_table = lo_alv
        CHANGING  t_table      = lt_detail ).
      lo_alv->get_display_settings( )->set_list_header( 'Runtime Error Detail - current execution issue' ).
      lo_alv->get_functions( )->set_all( abap_true ).
      lo_cols = lo_alv->get_columns( ).
      lo_cols->set_optimize( abap_true ).
      CALL METHOD lo_alv->set_screen_popup
        EXPORTING
          start_column = 5
          end_column   = 150
          start_line   = 2
          end_line     = 22.
      lo_alv->display( ).
    CATCH cx_salv_msg INTO lx_salv.
      MESSAGE lx_salv->get_text( ) TYPE 'S' DISPLAY LIKE 'E'.
  ENDTRY.
ENDFORM.
*<<< END FORM z16_show_issue_detail_safe

*>>> FORM z16_show_fix_guide_safe - moved from Z_BDC_MASS_PO_ENTRY_F01_BUP

FORM z16_show_fix_guide_safe.
  TYPES: BEGIN OF ty_fix_guide,
           session_id      TYPE zbdc_staging_bup-session_id,
           file_source     TYPE char80,
           sheet_name      TYPE char40,
           group_key       TYPE zbdc_staging_bup-record_key,
           tcode           TYPE zbdc_staging_bup-tcode,
           lifecycle       TYPE char20,
           field_name      TYPE char40,
           current_value   TYPE char80,
           error_message   TYPE char255,
           action_hint     TYPE char120,
           suggested_value TYPE char120,
           responsible     TYPE syuname,
           retryable       TYPE char1,
         END OF ty_fix_guide.

  DATA: lt_fix   TYPE STANDARD TABLE OF ty_fix_guide,
        ls_fix   TYPE ty_fix_guide,
        ls_exec  TYPE ty_exec_disp,
        ls_stg   TYPE ty_staging_alv,
        lo_alv   TYPE REF TO cl_salv_table,
        lo_cols  TYPE REF TO cl_salv_columns_table,
        lx_salv  TYPE REF TO cx_salv_msg.

  LOOP AT gt_exec_disp INTO ls_exec.
    IF ls_exec-run_status <> 'ERROR'
       AND ls_exec-run_status <> 'WARNING'
       AND ls_exec-run_status <> 'SKIPPED'.
      CONTINUE.
    ENDIF.

    CLEAR ls_fix.
    ls_fix-session_id    = ls_exec-session_id.
    ls_fix-file_source   = ls_exec-source_file.
    ls_fix-sheet_name    = ls_exec-sheet_name.
    ls_fix-group_key     = ls_exec-group_key.
    ls_fix-tcode         = ls_exec-tcode.
    ls_fix-lifecycle     = ls_exec-run_status.
    ls_fix-field_name    = 'RUNTIME / BUSINESS RULE'.
    ls_fix-error_message = ls_exec-message.
    ls_fix-action_hint   = ls_exec-action_hint.
    ls_fix-suggested_value = 'Correct staging or master data, validate again, then use Retry Selected.'.
    ls_fix-responsible   = sy-uname.
    ls_fix-retryable     = 'X'.

    READ TABLE gt_staging_alv INTO ls_stg
      WITH KEY session_id = ls_exec-session_id
               record_key = ls_exec-group_key.
    IF sy-subrc = 0.
      IF ls_fix-error_message IS INITIAL.
        ls_fix-error_message = ls_stg-error_msg.
      ENDIF.
      IF ls_fix-error_message IS INITIAL.
        ls_fix-error_message = ls_stg-last_error.
      ENDIF.
    ENDIF.
    APPEND ls_fix TO lt_fix.
  ENDLOOP.

  IF lt_fix IS INITIAL.
    CALL FUNCTION 'POPUP_TO_INFORM'
      EXPORTING
        titel = 'No Fix Guide Required'
        txt1  = 'The current queue has no runtime issue that requires correction.'
        txt2  = 'Fix Guide is available only for ERROR, WARNING, SKIPPED or PARTIAL groups.'.
    RETURN.
  ENDIF.

  TRY.
      cl_salv_table=>factory(
        IMPORTING r_salv_table = lo_alv
        CHANGING  t_table      = lt_fix ).
      lo_alv->get_display_settings( )->set_list_header( 'Fix Guide Preview - runtime issues in current queue' ).
      lo_alv->get_functions( )->set_all( abap_true ).
      lo_cols = lo_alv->get_columns( ).
      lo_cols->set_optimize( abap_true ).
      CALL METHOD lo_alv->set_screen_popup
        EXPORTING
          start_column = 5
          end_column   = 150
          start_line   = 2
          end_line     = 22.
      lo_alv->display( ).
    CATCH cx_salv_msg INTO lx_salv.
      MESSAGE lx_salv->get_text( ) TYPE 'S' DISPLAY LIKE 'E'.
  ENDTRY.
ENDFORM.
*<<< END FORM z16_show_fix_guide_safe

*>>> FORM z16_open_0500_error_detail - moved from Z_BDC_MASS_PO_ENTRY_F01_BUP

FORM z16_open_0500_error_detail.
  "V5M: open a visible modal SALV only for a real runtime issue.
  "Use a safe read-only SALV detail instead of dumping the whole program.
  PERFORM z16_show_issue_detail_safe.
ENDFORM.
*<<< END FORM z16_open_0500_error_detail

*>>> FORM z16_open_0500_fix_guide - moved from Z_BDC_MASS_PO_ENTRY_F01_BUP

FORM z16_open_0500_fix_guide.
  "V5M: open a visible modal Fix Guide only when runtime issues exist.
  "The safe Fix Guide keeps preview/export available through SALV functions.
  PERFORM z16_show_fix_guide_safe.
ENDFORM.
*<<< END FORM z16_open_0500_fix_guide

*>>> FORM z16_0560_load_fixed_file - moved from Z_BDC_MASS_PO_ENTRY_F01_BUP

FORM z16_0560_load_fixed_file.
  MESSAGE 'Load Fixed File: use 0300 upload/Preview Data to ingest corrected file, then return to 0400/0500.' TYPE 'S' DISPLAY LIKE 'I'.
ENDFORM.
*<<< END FORM z16_0560_load_fixed_file

*>>> FORM z16_0560_save_fix - moved from Z_BDC_MASS_PO_ENTRY_F01_BUP

FORM z16_0560_save_fix.
  PERFORM apply_mass_replace.
  MESSAGE 'Fix saved. Use Validate Again, then Retry Selected.' TYPE 'S'.
ENDFORM.
*<<< END FORM z16_0560_save_fix

*>>> FORM z16_0560_export_fix - moved from Z_BDC_MASS_PO_ENTRY_F01_BUP

FORM z16_0560_export_fix.
  PERFORM export_session_log_csv.
ENDFORM.
*<<< END FORM z16_0560_export_fix

*>>> FORM retry_error_records_0600 - moved from Z_BDC_MASS_PO_ENTRY_F01_BUP

FORM retry_error_records_0600.
  DATA: lv_session TYPE zbdc_result_bup-session_id,
        lt_err     TYPE STANDARD TABLE OF zbdc_staging_bup,
        ls_alv     TYPE ty_staging_alv,
        lt_process TYPE ty_t_staging_alv,
        lv_cnt     TYPE i,
        lv_lock_ok TYPE abap_bool,
        lv_locked  TYPE abap_bool.

  PERFORM select_result_session_0600 CHANGING lv_session.
  IF lv_session IS INITIAL.
    MESSAGE 'Khong xac dinh duoc session de retry.' TYPE 'W'.
    RETURN.
  ENDIF.

  SELECT * FROM zbdc_staging_bup
    INTO TABLE @lt_err
    WHERE session_id = @lv_session
      AND status     = @gc_st_error.

  IF lt_err IS INITIAL.
    MESSAGE |Session { lv_session } khong co record ERROR de retry.| TYPE 'S'.
    RETURN.
  ENDIF.

  PERFORM acquire_staging_lock_safe
    USING    lv_session
    CHANGING lv_lock_ok lv_locked.
  IF lv_lock_ok <> abap_true.
    RETURN.
  ENDIF.

  LOOP AT lt_err ASSIGNING FIELD-SYMBOL(<ls_retry_stg>).
    <ls_retry_stg>-status = gc_st_ready.
    <ls_retry_stg>-error_msg = ''.
    MODIFY zbdc_staging_bup FROM <ls_retry_stg>.

    CLEAR ls_alv.
    MOVE-CORRESPONDING <ls_retry_stg> TO ls_alv.
    APPEND ls_alv TO lt_process.
  ENDLOOP.
  COMMIT WORK AND WAIT.
  PERFORM release_staging_lock USING lv_session.

  lv_cnt = lines( lt_process ).
  MESSAGE |Retry manual: { lv_cnt } ERROR record(s) re-queued from staging, no source reload.| TYPE 'S'.

  IF lt_process IS NOT INITIAL.
    PERFORM execute_bdc_engine USING lt_process p_bdc_mode.
  ENDIF.

  SELECT * FROM zbdc_staging_bup
    INTO TABLE @gt_staging
    WHERE session_id = @lv_session.
  REFRESH gt_staging_alv.
  PERFORM prepare_alv_0400.
  PERFORM build_exec_cockpit.
  PERFORM load_results_0600.
ENDFORM.
*<<< END FORM retry_error_records_0600

*>>> FORM m4_csv_cell - moved from Z_BDC_MASS_PO_ENTRY_F01_BUP

FORM m4_csv_cell USING iv_value TYPE any CHANGING cv_value TYPE string.
  cv_value = |{ iv_value }|.
  REPLACE ALL OCCURRENCES OF '"' IN cv_value WITH '""'.
  cv_value = '"' && cv_value && '"'.
ENDFORM.
*<<< END FORM m4_csv_cell

*>>> FORM m4_excel_cell - moved from Z_BDC_MASS_PO_ENTRY_F01_BUP

FORM m4_excel_cell USING iv_value TYPE any CHANGING cv_value TYPE string.
  cv_value = |{ iv_value }|.
  REPLACE ALL OCCURRENCES OF '&' IN cv_value WITH '&amp;'.
  REPLACE ALL OCCURRENCES OF '<' IN cv_value WITH '&lt;'.
  REPLACE ALL OCCURRENCES OF '>' IN cv_value WITH '&gt;'.
  REPLACE ALL OCCURRENCES OF '"' IN cv_value WITH '&quot;'.
  cv_value = '<td style="mso-number-format:\@">' && cv_value && '</td>'.
ENDFORM.
*<<< END FORM m4_excel_cell

*>>> FORM export_session_log_csv - moved from Z_BDC_MASS_PO_ENTRY_F01_BUP


FORM export_session_log_csv.
  DATA: lv_session     TYPE zbdc_result_bup-session_id,
        lt_lines       TYPE string_table,
        lv_line        TYPE string,
        lv_cell        TYPE string,
        lv_filename    TYPE string,
        lv_path        TYPE string,
        lv_fullpath    TYPE string,
        lv_user_action TYPE i,
        lv_cat         TYPE string,
        lv_hint        TYPE string,
        lv_retry       TYPE string,
        lv_resp        TYPE string.

  PERFORM load_results_0600.
  PERFORM select_result_session_0600 CHANGING lv_session.

  IF gt_result_all IS INITIAL.
    MESSAGE 'Khong co session log de export.' TYPE 'W'.
    RETURN.
  ENDIF.

  APPEND '<html xmlns:x="urn:schemas-microsoft-com:office:excel">' TO lt_lines.
  APPEND '<head><meta http-equiv="Content-Type" content="text/html; charset=utf-8" /></head>' TO lt_lines.
  APPEND '<body><table border="1">' TO lt_lines.
  CLEAR lv_line.
  CONCATENATE lv_line '<tr><th>SESSION_ID</th><th>RECORD_KEY</th><th>ROW_INDEX</th>'
    INTO lv_line.
  CONCATENATE lv_line '<th>STEP</th><th>TCODE</th><th>DYNPRO</th><th>FIELD_NAME</th>'
    INTO lv_line.
  CONCATENATE lv_line '<th>MSG_TYPE</th><th>MESSAGE</th><th>SAP_OBJECT_ID</th>'
    INTO lv_line.
  CONCATENATE lv_line '<th>CREATED_AT</th><th>ATTEMPT_NO</th><th>RETRY_FLAG</th>'
    INTO lv_line.
  CONCATENATE lv_line '<th>EXEC_STATUS</th><th>LOCK_REASON</th>'
    INTO lv_line.
  CONCATENATE lv_line '<th>ERROR_CATEGORY</th><th>ACTION_HINT</th><th>RESPONSIBLE</th><th>RETRYABLE</th></tr>'
    INTO lv_line.
  APPEND lv_line TO lt_lines.

  LOOP AT gt_result_all INTO DATA(ls_exp_res).
    lv_line = '<tr>'.
    PERFORM m4_excel_cell USING ls_exp_res-session_id    CHANGING lv_cell. lv_line = lv_line && lv_cell.
    PERFORM m4_excel_cell USING ls_exp_res-record_key    CHANGING lv_cell. lv_line = lv_line && lv_cell.
    PERFORM m4_excel_cell USING ls_exp_res-row_index     CHANGING lv_cell. lv_line = lv_line && lv_cell.
    PERFORM m4_excel_cell USING ls_exp_res-step          CHANGING lv_cell. lv_line = lv_line && lv_cell.
    PERFORM m4_excel_cell USING ls_exp_res-tcode         CHANGING lv_cell. lv_line = lv_line && lv_cell.
    PERFORM m4_excel_cell USING ls_exp_res-dynpro        CHANGING lv_cell. lv_line = lv_line && lv_cell.
    PERFORM m4_excel_cell USING ls_exp_res-field_name    CHANGING lv_cell. lv_line = lv_line && lv_cell.
    PERFORM m4_excel_cell USING ls_exp_res-msg_type      CHANGING lv_cell. lv_line = lv_line && lv_cell.
    PERFORM m4_excel_cell USING ls_exp_res-message       CHANGING lv_cell. lv_line = lv_line && lv_cell.
    PERFORM m4_excel_cell USING ls_exp_res-sap_object_id CHANGING lv_cell. lv_line = lv_line && lv_cell.
    PERFORM m4_excel_cell USING ls_exp_res-created_at    CHANGING lv_cell. lv_line = lv_line && lv_cell.
    PERFORM m4_excel_cell USING ls_exp_res-attempt_no    CHANGING lv_cell. lv_line = lv_line && lv_cell.
    PERFORM m4_excel_cell USING ls_exp_res-retry_flag    CHANGING lv_cell. lv_line = lv_line && lv_cell.
    PERFORM m4_excel_cell USING ls_exp_res-exec_status   CHANGING lv_cell. lv_line = lv_line && lv_cell.
    PERFORM m4_excel_cell USING ls_exp_res-lock_reason   CHANGING lv_cell. lv_line = lv_line && lv_cell.
    CLEAR: lv_cat, lv_hint, lv_retry, lv_resp.
    PERFORM z16_classify_error USING ls_exp_res-message ls_exp_res-field_name CHANGING lv_cat.
    PERFORM build_bdc_action_hint USING ls_exp_res-message ls_exp_res-field_name CHANGING lv_hint lv_retry.
    PERFORM z16_guess_responsible USING lv_cat CHANGING lv_resp.
    PERFORM m4_excel_cell USING lv_cat   CHANGING lv_cell. lv_line = lv_line && lv_cell.
    PERFORM m4_excel_cell USING lv_hint  CHANGING lv_cell. lv_line = lv_line && lv_cell.
    PERFORM m4_excel_cell USING lv_resp  CHANGING lv_cell. lv_line = lv_line && lv_cell.
    PERFORM m4_excel_cell USING lv_retry CHANGING lv_cell. lv_line = lv_line && lv_cell.
    lv_line = lv_line && '</tr>'.
    APPEND lv_line TO lt_lines.
  ENDLOOP.

  APPEND '</table></body></html>' TO lt_lines.

  CL_GUI_FRONTEND_SERVICES=>FILE_SAVE_DIALOG(
    EXPORTING
      window_title      = 'Export full BDC session log to Excel'
      default_extension = 'xls'
      default_file_name = |BDC_Session_Log_{ lv_session }.xls|
      file_filter       = 'Excel Workbook (*.xls)|*.xls|All (*.*)|*.*'
    CHANGING
      filename          = lv_filename
      path              = lv_path
      fullpath          = lv_fullpath
      user_action       = lv_user_action
    EXCEPTIONS
      OTHERS            = 1 ).

  IF sy-subrc <> 0 OR lv_user_action <> cl_gui_frontend_services=>action_ok
     OR lv_fullpath IS INITIAL.
    RETURN.
  ENDIF.

  CL_GUI_FRONTEND_SERVICES=>GUI_DOWNLOAD(
    EXPORTING
      filename = lv_fullpath
      filetype = 'ASC'
      codepage = '4110'
    CHANGING
      data_tab = lt_lines
    EXCEPTIONS
      OTHERS = 1 ).

  IF sy-subrc = 0.
    MESSAGE |Exported full session log to Excel: { lines( gt_result_all ) } log rows.| TYPE 'S'.
  ELSE.
    MESSAGE |Export session log failed SY-SUBRC={ sy-subrc }.| TYPE 'E'.
  ENDIF.
ENDFORM.

* ------------------------------------------------------------
* Screen 0700/0750 - Rule-based Error Analyst (AI-ready; no external LLM)
* ------------------------------------------------------------
*<<< END FORM export_session_log_csv

*>>> FORM build_ai_patterns - moved from Z_BDC_MASS_PO_ENTRY_F01_BUP
FORM build_ai_patterns. "Rule-based pattern mining from real ZBDC_RESULT_BUP logs
  DATA ls_pat TYPE ty_ai_pattern.
  DATA lv_key TYPE char120.
  FIELD-SYMBOLS <ls_pat> TYPE ty_ai_pattern.

  REFRESH gt_patterns.
  IF gt_result_all IS INITIAL.
    PERFORM load_results_0600.
  ENDIF.

  LOOP AT gt_result_all INTO DATA(ls_res) WHERE msg_type = 'E' OR msg_type = 'W'.
    CLEAR: ls_pat, lv_key.
    ls_pat-session_id = ls_res-session_id.
    ls_pat-msg_type   = ls_res-msg_type.
    ls_pat-message    = ls_res-message.
    ls_pat-count      = 1.
    ls_pat-fix_hint   = 'Check master data/customizing; correct staging row; validate again; resubmit from 0550/0400.'.
    IF ls_res-message CS 'Vendor' OR ls_res-message CS 'vendor'.
      ls_pat-pattern_id = 'VENDOR'.
      ls_pat-fix_hint = 'Vendor missing/blocked/wrong purchasing org: check XK03/BP and purchasing data; then correct FIELD02.'.
    ELSEIF ls_res-message CS 'Plant' OR ls_res-message CS 'plant'.
      ls_pat-pattern_id = 'PLANT'.
      ls_pat-fix_hint = 'Plant/sloc/material extension error: check MARC/MARD and correct FIELD08/FIELD12.'.
    ELSEIF ls_res-message CS 'Material' OR ls_res-message CS 'material'.
      ls_pat-pattern_id = 'MATERIAL'.
      ls_pat-fix_hint = 'Material not extended or wrong item data: check MM03 plant data and correct FIELD06/FIELD08.'.
    ELSE.
      ls_pat-pattern_id = 'GENERAL'.
    ENDIF.

    READ TABLE gt_patterns ASSIGNING <ls_pat> WITH KEY pattern_id = ls_pat-pattern_id message = ls_pat-message.
    IF sy-subrc = 0.
      <ls_pat>-count = <ls_pat>-count + 1.
    ELSE.
      APPEND ls_pat TO gt_patterns.
    ENDIF.
  ENDLOOP.

  gt_ai_archive = gt_patterns.
ENDFORM.

*&---------------------------------------------------------------------*
*& GEMINI AI ERROR ANALYST (real LLM) + rule-based fallback
*&  Flow: gom loi that tu ZBDC_RESULT_BUP -> build prompt EN
*&        -> POST generativelanguage.googleapis.com (CL_HTTP_CLIENT)
*&        -> parse JSON -> do vao gt_patterns -> hien 0700
*&  Neu BAT KY buoc nao loi (no key / SSL / network / parse) ->
*&        tu dong goi build_ai_patterns (rule-based) -> KHONG BAO GIO trang man.
*&---------------------------------------------------------------------*
*<<< END FORM build_ai_patterns

*>>> FORM run_ai_error_analysis - moved from Z_BDC_MASS_PO_ENTRY_F01_BUP
FORM run_ai_error_analysis.
  DATA: lv_key    TYPE string,
        lv_prompt TYPE string,
        lv_resp   TYPE string,
        lv_ok     TYPE abap_bool.

  CLEAR lv_ok.

  "1) Lay API key tu config (khong hardcode, khong in ra man hinh/log).
  PERFORM get_gemini_api_key CHANGING lv_key.
  IF lv_key IS INITIAL.
    MESSAGE 'Gemini API key chua cau hinh (ZBDC_CONFIG_BUP/GEMINI_API_KEY). Dung rule-based thay the.' TYPE 'S'.
    PERFORM display_ai_patterns.
    RETURN.
  ENDIF.

  "2) Gom loi that thanh prompt. Neu khong co loi -> rule-based cho gon.
  PERFORM build_gemini_prompt CHANGING lv_prompt.
  IF lv_prompt IS INITIAL.
    PERFORM display_ai_patterns.
    RETURN.
  ENDIF.

  "3) Goi Gemini that. Loi mang/SSL -> lv_ok = abap_false.
  PERFORM call_gemini_api USING lv_key lv_prompt CHANGING lv_resp lv_ok.
  IF lv_ok = abap_false OR lv_resp IS INITIAL.
    MESSAGE 'Khong goi duoc Gemini (mang/SSL/API). Tu dong chuyen sang rule-based.' TYPE 'S'.
    PERFORM display_ai_patterns.
    RETURN.
  ENDIF.

  "4) Parse JSON tra ve -> gt_patterns. Loi parse -> fallback.
  PERFORM parse_gemini_response USING lv_resp CHANGING lv_ok.
  IF lv_ok = abap_false OR gt_patterns IS INITIAL.
    MESSAGE 'Gemini tra ve du lieu khong doc duoc. Tu dong chuyen sang rule-based.' TYPE 'S'.
    PERFORM display_ai_patterns.
    RETURN.
  ENDIF.

  "5) Ghi hint AI that vao ZBDC_RESULT_BUP.LOCK_REASON (dong bo dashboard/export).
  PERFORM persist_ai_hints_to_result.

  "6) Hien grid 0700 voi ket qua that tu Gemini.
  gt_ai_archive = gt_patterns.
  PERFORM show_ai_pattern_grid.
  MESSAGE |Gemini AI analysis xong: { lines( gt_patterns ) } pattern loi (real LLM).| TYPE 'S'.
ENDFORM.

*&---------------------------------------------------------------------*
*<<< END FORM run_ai_error_analysis

*>>> FORM get_gemini_api_key - moved from Z_BDC_MASS_PO_ENTRY_F01_BUP
FORM get_gemini_api_key CHANGING cv_key TYPE string.
  DATA ls_cfg TYPE zbdc_config_bup.
  CLEAR cv_key.
  SELECT SINGLE * FROM zbdc_config_bup INTO @ls_cfg
    WHERE config_key = @gc_gemini_cfgkey.
  IF sy-subrc = 0.
    cv_key = ls_cfg-config_value.
    CONDENSE cv_key NO-GAPS.
  ENDIF.
ENDFORM.

*&---------------------------------------------------------------------*
*<<< END FORM get_gemini_api_key

*>>> FORM build_gemini_prompt - moved from Z_BDC_MASS_PO_ENTRY_F01_BUP
FORM build_gemini_prompt CHANGING cv_prompt TYPE string.
  DATA: lv_lines TYPE string,
        lv_n     TYPE i.

  CLEAR: cv_prompt, lv_lines, lv_n.

  IF gt_result_all IS INITIAL.
    PERFORM load_results_0600.
  ENDIF.

  "Gom toi da 40 dong loi that de tranh prompt qua dai.
  LOOP AT gt_result_all INTO DATA(ls_res)
       WHERE msg_type = 'E' OR msg_type = 'W'.
    lv_n = lv_n + 1.
    IF lv_n > 40.
      EXIT.
    ENDIF.
    lv_lines = lv_lines
      && |Row { ls_res-row_index } | && |TCode { ls_res-tcode } |
      && |Dynpro { ls_res-dynpro } | && |Field { ls_res-field_name } |
      && |MsgType { ls_res-msg_type } | && |Msg: { ls_res-message }|
      && cl_abap_char_utilities=>newline.
  ENDLOOP.

  IF lv_lines IS INITIAL.
    RETURN. "khong co loi -> caller se dung rule-based
  ENDIF.

  "Prompt tieng Anh, ep tra ve JSON array thuan de parse.
  cv_prompt =
    |You are an SAP BDC error analyst for Purchase Order (ME21N) and Goods | &&
    |Movement (MIGO) batch data entry. Analyze the following real BDC error | &&
    |log lines and, for each distinct error pattern, return a fix suggestion | &&
    |for the data-entry user. | &&
    |Respond ONLY with a raw JSON array (no markdown, no code fences). | &&
    |Each element must have exactly these fields: | &&
    |"pattern_id" (short uppercase code e.g. VENDOR, PLANT, MATERIAL, PO, QTY, LOCK, GENERAL), | &&
    |"severity" (HIGH, MEDIUM or LOW), | &&
    |"message" (the SAP error summarized in English, max 200 chars), | &&
    |"root_cause" (why it happened, max 200 chars), | &&
    |"fix_action" (concrete step to fix the source data or config, max 200 chars), | &&
    |"example_row" (the Row number from the log line this pattern is based on, integer). | &&
    |Here are the error lines:| && cl_abap_char_utilities=>newline && lv_lines.
ENDFORM.

*&---------------------------------------------------------------------*
*<<< END FORM build_gemini_prompt

*>>> FORM call_gemini_api - moved from Z_BDC_MASS_PO_ENTRY_F01_BUP
FORM call_gemini_api USING iv_key    TYPE string
                           iv_prompt TYPE string
                  CHANGING cv_resp   TYPE string
                           cv_ok     TYPE abap_bool.
  DATA: lo_http  TYPE REF TO if_http_client,
        lv_url   TYPE string,
        lv_body  TYPE string,
        lv_pbody TYPE string,
        lv_code  TYPE i.

  CLEAR: cv_resp, cv_ok.

  "URL: v1beta generateContent. Key di qua HEADER x-goog-api-key (chuan REST moi,
  "tranh key nam trong URL bi ghi vao trace/log/ICM).
  lv_url = |{ gc_gemini_host }/v1beta/models/{ gc_gemini_model }:generateContent|.

  "Escape prompt cho JSON body (quote, backslash, xuong dong).
  lv_pbody = iv_prompt.
  REPLACE ALL OCCURRENCES OF '\' IN lv_pbody WITH '\\'.
  REPLACE ALL OCCURRENCES OF '"' IN lv_pbody WITH '\"'.
  REPLACE ALL OCCURRENCES OF cl_abap_char_utilities=>cr_lf IN lv_pbody WITH '\n'.
  REPLACE ALL OCCURRENCES OF cl_abap_char_utilities=>newline IN lv_pbody WITH '\n'.

  "Body: ep tra JSON bang responseMimeType.
  lv_body =
    |\{ "contents": [\{ "parts": [\{ "text": "{ lv_pbody }" \}] \}], | &&
    |"generationConfig": \{ "responseMimeType": "application/json", "temperature": 0.2 \} \}|.

  cl_http_client=>create_by_url(
    EXPORTING url = lv_url
    IMPORTING client = lo_http
    EXCEPTIONS OTHERS = 1 ).
  IF sy-subrc <> 0 OR lo_http IS INITIAL.
    RETURN. "cv_ok = false -> caller fallback
  ENDIF.

  lo_http->request->set_method( 'POST' ).
  lo_http->request->set_header_field( name = 'Content-Type'   value = 'application/json' ).
  lo_http->request->set_header_field( name = 'x-goog-api-key' value = iv_key ).
  lo_http->request->set_cdata( lv_body ).

  lo_http->send( EXCEPTIONS OTHERS = 1 ).
  IF sy-subrc <> 0.
    lo_http->close( EXCEPTIONS OTHERS = 1 ).
    RETURN.
  ENDIF.

  lo_http->receive( EXCEPTIONS OTHERS = 1 ).
  IF sy-subrc <> 0.
    lo_http->close( EXCEPTIONS OTHERS = 1 ).
    RETURN.
  ENDIF.

  lo_http->response->get_status( IMPORTING code = lv_code ).
  IF lv_code = 200.
    cv_resp = lo_http->response->get_cdata( ).
    cv_ok   = abap_true.
  ELSE.
    "Log HTTP code de debug, nhung khong dump.
    MESSAGE |Gemini HTTP { lv_code }. Chuyen rule-based.| TYPE 'S'.
  ENDIF.

  lo_http->close( EXCEPTIONS OTHERS = 1 ).
ENDFORM.

*&---------------------------------------------------------------------*
*<<< END FORM call_gemini_api

*>>> FORM parse_gemini_response - moved from Z_BDC_MASS_PO_ENTRY_F01_BUP
FORM parse_gemini_response USING iv_resp TYPE string
                          CHANGING cv_ok  TYPE abap_bool.
  "Cau truc tra ve Gemini: candidates[0].content.parts[0].text = JSON array (string).
  "Vi text la JSON long trong JSON, ta rut phan text roi parse array bang /UI2/CL_JSON.
  DATA: lv_inner TYPE string,
        lv_arr   TYPE string.

  TYPES: BEGIN OF ty_g_item,
           pattern_id  TYPE string,
           severity    TYPE string,
           message     TYPE string,
           root_cause  TYPE string,
           fix_action  TYPE string,
           example_row TYPE string,
         END OF ty_g_item.
  DATA lt_items TYPE STANDARD TABLE OF ty_g_item.
  DATA ls_pat   TYPE ty_ai_pattern.

  CLEAR cv_ok.
  REFRESH gt_patterns.

  "1) Rut chuoi text ben trong "text": "...."
  PERFORM extract_gemini_text USING iv_resp CHANGING lv_inner.
  IF lv_inner IS INITIAL.
    RETURN.
  ENDIF.

  "2) Bo code fence neu Gemini lo them ```json ... ```
  REPLACE ALL OCCURRENCES OF '```json' IN lv_inner WITH ''.
  REPLACE ALL OCCURRENCES OF '```'     IN lv_inner WITH ''.
  CONDENSE lv_inner.
  lv_arr = lv_inner.

  "3) Parse JSON array -> internal table.
  TRY.
      /ui2/cl_json=>deserialize(
        EXPORTING json = lv_arr
        CHANGING  data = lt_items ).
    CATCH cx_root.
      RETURN. "parse loi -> caller fallback
  ENDTRY.

  IF lt_items IS INITIAL.
    RETURN.
  ENDIF.

  "4) Map sang ty_ai_pattern de tai su dung grid/archive san co.
  LOOP AT lt_items INTO DATA(ls_it).
    CLEAR ls_pat.
    ls_pat-pattern_id = ls_it-pattern_id.
    ls_pat-msg_type   = 'E'.
    ls_pat-message    = ls_it-message.
    ls_pat-count      = 1.
    "Muon dung field dynpro (khong dung o nhanh Gemini) de mang row goc,
    "phuc vu update LOCK_REASON theo ROW_INDEX (chinh xac hon match theo message).
    "Row Gemini tra ve co the bi sai format. Chi gan khi la so de tranh dump
    "luc persist ve ROW_INDEX.
    DATA(lv_exrow) = ls_it-example_row.
    CONDENSE lv_exrow NO-GAPS.
    IF lv_exrow IS NOT INITIAL AND lv_exrow CO '0123456789'.
      ls_pat-dynpro = lv_exrow.
    ENDIF.
    "Gop root cause + fix action + severity vao fix_hint (cot san co).
    ls_pat-fix_hint =
      |[{ ls_it-severity }] Cause: { ls_it-root_cause } => Fix: { ls_it-fix_action }|.
    APPEND ls_pat TO gt_patterns.
  ENDLOOP.

  IF gt_patterns IS NOT INITIAL.
    cv_ok = abap_true.
  ENDIF.
ENDFORM.

*&---------------------------------------------------------------------*
*<<< END FORM parse_gemini_response

*>>> FORM extract_gemini_text - moved from Z_BDC_MASS_PO_ENTRY_F01_BUP
FORM extract_gemini_text USING iv_resp TYPE string
                        CHANGING cv_text TYPE string.
  "Tim "text": " roi doc den dau ngoac kep dong chua escape.
  "Viet tay de khong phu thuoc parse toan bo cau truc long cua Gemini.
  DATA: lv_pos      TYPE i,
        lv_start    TYPE i,
        lv_len      TYPE i,
        lv_scan     TYPE i,
        lv_back     TYPE i,
        lv_bs_count TYPE i,
        lv_char     TYPE c LENGTH 1,
        lv_prev     TYPE c LENGTH 1.

  CLEAR cv_text.

  FIND FIRST OCCURRENCE OF '"text":' IN iv_resp MATCH OFFSET lv_pos.
  IF sy-subrc <> 0.
    RETURN.
  ENDIF.

  lv_scan = lv_pos + 7.
  "Bo qua khoang trang va dau " mo dau.
  WHILE lv_scan < strlen( iv_resp ).
    lv_char = iv_resp+lv_scan(1).
    IF lv_char = space OR lv_char = '"'.
      lv_scan = lv_scan + 1.
      IF lv_char = '"'.
        EXIT. "da qua dau mo chuoi
      ENDIF.
    ELSE.
      EXIT.
    ENDIF.
  ENDWHILE.

  lv_start = lv_scan.
  "Doc den dau " dong ma khong bi escape (ky tu truoc khong phai \).
  WHILE lv_scan < strlen( iv_resp ).
    lv_char = iv_resp+lv_scan(1).
    IF lv_char = '"'.
      "Chi coi la dau dong chuoi neu so dau backslash lien tiep truoc no la chan.
      "Vi JSON escape quote bang ", con \" van co the xuat hien trong response.
      CLEAR lv_bs_count.
      lv_back = lv_scan - 1.
      WHILE lv_back >= 0.
        lv_prev = iv_resp+lv_back(1).
        IF lv_prev = '\'.
          lv_bs_count = lv_bs_count + 1.
          lv_back = lv_back - 1.
        ELSE.
          EXIT.
        ENDIF.
      ENDWHILE.
      IF lv_bs_count MOD 2 = 0.
        EXIT.
      ENDIF.
    ENDIF.
    lv_scan = lv_scan + 1.
  ENDWHILE.

  lv_len = lv_scan - lv_start.
  IF lv_len > 0.
    cv_text = iv_resp+lv_start(lv_len).
    "Un-escape cac ky tu JSON co ban trong chuoi text.
    REPLACE ALL OCCURRENCES OF '\n' IN cv_text WITH cl_abap_char_utilities=>newline.
    REPLACE ALL OCCURRENCES OF '\"' IN cv_text WITH '"'.
    REPLACE ALL OCCURRENCES OF '\\' IN cv_text WITH '\'.
  ENDIF.
ENDFORM.

*&---------------------------------------------------------------------*
*<<< END FORM extract_gemini_text

*>>> FORM persist_ai_hints_to_result - moved from Z_BDC_MASS_PO_ENTRY_F01_BUP
FORM persist_ai_hints_to_result.
  "Ghi hint AI vao LOCK_REASON cua cac dong loi cung session (best-effort).
  "Khong ghi de neu khong match; loi update khong lam hong flow.
  DATA lv_session TYPE zbdc_result_bup-session_id.

  READ TABLE gt_result_all INTO DATA(ls_first) INDEX 1.
  IF sy-subrc <> 0.
    RETURN.
  ENDIF.
  lv_session = ls_first-session_id.

  DATA: lv_short TYPE c LENGTH 50,
        lv_row   TYPE zbdc_result_bup-row_index,
        lv_exrow TYPE string.
  LOOP AT gt_patterns INTO DATA(ls_pat).
    "LOCK_REASON la CHAR50 -> cat gon de tranh mat du lieu khi UPDATE.
    "Ban day du van hien tren grid 0700 (fix_hint char255).
    CLEAR: lv_short, lv_row, lv_exrow.
    lv_short = ls_pat-fix_hint.
    lv_exrow = ls_pat-dynpro.
    CONDENSE lv_exrow NO-GAPS.

    IF lv_exrow IS NOT INITIAL AND lv_exrow CO '0123456789'.
      "Gemini co tra example_row hop le -> update theo ROW_INDEX (chinh xac,
      "khong phu thuoc message da bi Gemini viet lai bang tieng Anh).
      lv_row = lv_exrow.
      UPDATE zbdc_result_bup
         SET lock_reason = @lv_short
       WHERE session_id  = @lv_session
         AND row_index   = @lv_row.
    ELSEIF ls_pat-message IS NOT INITIAL.
      "Khong co row hop le -> thu match theo message (best-effort).
      UPDATE zbdc_result_bup
         SET lock_reason = @lv_short
       WHERE session_id  = @lv_session
         AND message     = @ls_pat-message.
    ENDIF.
  ENDLOOP.
  COMMIT WORK.
ENDFORM.

*&---------------------------------------------------------------------*
*<<< END FORM persist_ai_hints_to_result

*>>> FORM show_ai_pattern_grid - moved from Z_BDC_MASS_PO_ENTRY_F01_BUP
FORM show_ai_pattern_grid.
  IF go_container_0700 IS INITIAL.
    CREATE OBJECT go_container_0700 EXPORTING container_name = 'CC_PATTERN_CONTAINER'.
    TRY.
        cl_salv_table=>factory(
          EXPORTING r_container  = go_container_0700
          IMPORTING r_salv_table = go_pattern_grid
          CHANGING  t_table      = gt_patterns ).
        go_pattern_grid->get_functions( )->set_all( abap_true ).
        go_pattern_grid->display( ).
      CATCH cx_salv_msg INTO DATA(lx_ai2).
        MESSAGE lx_ai2->get_text( ) TYPE 'I'.
    ENDTRY.
  ELSEIF go_pattern_grid IS BOUND.
    go_pattern_grid->refresh( ).
  ENDIF.
ENDFORM.
*<<< END FORM show_ai_pattern_grid

*>>> FORM display_ai_patterns - moved from Z_BDC_MASS_PO_ENTRY_F01_BUP

FORM display_ai_patterns.
  PERFORM build_ai_patterns. "Rule-based pattern mining from real ZBDC_RESULT_BUP logs
  IF go_container_0700 IS INITIAL.
    CREATE OBJECT go_container_0700 EXPORTING container_name = 'CC_PATTERN_CONTAINER'.
    TRY.
        cl_salv_table=>factory(
          EXPORTING r_container  = go_container_0700
          IMPORTING r_salv_table = go_pattern_grid
          CHANGING  t_table      = gt_patterns ).
        go_pattern_grid->get_functions( )->set_all( abap_true ).
        go_pattern_grid->display( ).
      CATCH cx_salv_msg INTO DATA(lx_ai).
        MESSAGE lx_ai->get_text( ) TYPE 'I'.
    ENDTRY.
  ELSEIF go_pattern_grid IS BOUND.
    go_pattern_grid->refresh( ).
  ENDIF.
ENDFORM.
*<<< END FORM display_ai_patterns

*>>> FORM generate_ai_text - moved from Z_BDC_MASS_PO_ENTRY_F01_BUP

FORM generate_ai_text.
  PERFORM build_ai_patterns. "Rule-based pattern mining from real ZBDC_RESULT_BUP logs
  txtp_ai_text = |Rule-based Diagnostics (AI-ready): { lines( gt_patterns ) } error pattern(s). |.
  LOOP AT gt_patterns INTO DATA(ls_pat).
    CONCATENATE txtp_ai_text cl_abap_char_utilities=>newline
      ls_pat-pattern_id ':' ls_pat-message '=> ' ls_pat-fix_hint
      INTO txtp_ai_text SEPARATED BY space.
  ENDLOOP.
  MESSAGE 'Rule-based diagnostic generated from real ZBDC_RESULT_BUP logs.' TYPE 'S'.
ENDFORM.
*<<< END FORM generate_ai_text

*>>> FORM display_ai_archive - moved from Z_BDC_MASS_PO_ENTRY_F01_BUP

FORM display_ai_archive.
  IF gt_ai_archive IS INITIAL.
    PERFORM build_ai_patterns. "Rule-based pattern mining from real ZBDC_RESULT_BUP logs
  ENDIF.
  IF p_search IS NOT INITIAL.
    DATA lt_filter TYPE STANDARD TABLE OF ty_ai_pattern.
    LOOP AT gt_ai_archive INTO DATA(ls_a).
      IF ls_a-message CS p_search OR ls_a-fix_hint CS p_search OR ls_a-pattern_id CS p_search.
        APPEND ls_a TO lt_filter.
      ENDIF.
    ENDLOOP.
    gt_ai_archive = lt_filter.
  ENDIF.
  IF go_container_0750 IS INITIAL.
    CREATE OBJECT go_container_0750 EXPORTING container_name = 'CC_KB_CONTAINER'.
    TRY.
        cl_salv_table=>factory(
          EXPORTING r_container  = go_container_0750
          IMPORTING r_salv_table = go_grid_0750
          CHANGING  t_table      = gt_ai_archive ).
        go_grid_0750->get_functions( )->set_all( abap_true ).
        go_grid_0750->display( ).
      CATCH cx_salv_msg INTO DATA(lx_kb).
        MESSAGE lx_kb->get_text( ) TYPE 'I'.
    ENDTRY.
  ELSEIF go_grid_0750 IS BOUND.
    go_grid_0750->refresh( ).
  ENDIF.
ENDFORM.

* ------------------------------------------------------------
* Screen 0800 - SHDB Recording Editor using ZBDC_SCT_DEF_BUP
* ------------------------------------------------------------
*<<< END FORM display_ai_archive

*>>> FORM z16_mark_row_error - moved from Z_BDC_MASS_PO_ENTRY_F01_BUP

FORM z16_mark_row_error USING iv_field TYPE csequence iv_msg TYPE csequence
                        CHANGING cs_alv TYPE ty_staging_alv.
  DATA ls_scol TYPE lvc_s_scol.
  cs_alv-status = gc_st_error.
  IF cs_alv-error_msg IS INITIAL.
    cs_alv-error_msg = iv_msg.
  ELSEIF cs_alv-error_msg NS iv_msg.
    cs_alv-error_msg = |{ cs_alv-error_msg } { iv_msg }|.
  ENDIF.
  cs_alv-last_error = cs_alv-error_msg.

  IF iv_field IS NOT INITIAL.
    CLEAR ls_scol.
    ls_scol-fname = iv_field.
    ls_scol-color-col = 6.
    ls_scol-color-int = 1.
    APPEND ls_scol TO cs_alv-cell_colors.
  ENDIF.
ENDFORM.
*<<< END FORM z16_mark_row_error

*>>> FORM z16_classify_error - moved from Z_BDC_MASS_PO_ENTRY_F01_BUP

FORM z16_classify_error USING iv_msg TYPE csequence iv_field TYPE csequence CHANGING cv_cat TYPE string.
  DATA lv_text TYPE string.
  cv_cat = 'BDC_RUNTIME'.
  lv_text = |{ iv_msg } { iv_field }|.
  TRANSLATE lv_text TO LOWER CASE.
  IF lv_text CS 'mandatory' OR lv_text CS 'required' OR lv_text CS 'thieu' OR lv_text CS 'missing'.
    cv_cat = 'TEMPLATE'.
  ELSEIF lv_text CS 'vendor' OR lv_text CS 'material' OR lv_text CS 'plant' OR lv_text CS 'storage' OR lv_text CS 'master'.
    cv_cat = 'MASTER_DATA'.
  ELSEIF lv_text CS 'lock' OR lv_text CS 'enqueue' OR lv_text CS 'locked'.
    cv_cat = 'LOCK'.
  ELSEIF lv_text CS 'auth' OR lv_text CS 'authorization' OR lv_text CS 'not authorized'.
    cv_cat = 'AUTH'.
  ELSEIF lv_text CS 'po' OR lv_text CS 'purchase order' OR lv_text CS 'quantity' OR lv_text CS 'tax'.
    cv_cat = 'BUSINESS'.
  ENDIF.
ENDFORM.
*<<< END FORM z16_classify_error

*>>> FORM z16_guess_responsible - moved from Z_BDC_MASS_PO_ENTRY_F01_BUP

FORM z16_guess_responsible USING iv_cat TYPE csequence CHANGING cv_resp TYPE string.
  CASE iv_cat.
    WHEN 'MASTER_DATA'. cv_resp = 'Master Data'.
    WHEN 'AUTH'.        cv_resp = 'Technical/Auth'.
    WHEN 'LOCK'.        cv_resp = 'User/Technical'.
    WHEN 'BUSINESS'.    cv_resp = 'Business User'.
    WHEN OTHERS.        cv_resp = 'User'.
  ENDCASE.
ENDFORM.
*<<< END FORM z16_guess_responsible

*>>> FORM z16_insert_error_record - moved from Z_BDC_MASS_PO_ENTRY_F01_BUP

FORM z16_insert_error_record USING is_alv TYPE ty_staging_alv
                                   iv_field TYPE csequence
                                   iv_value TYPE csequence.
  DATA: lv_exists TYPE abap_bool,
        lr_line   TYPE REF TO data,
        lv_tab    TYPE tabname,
        lv_cat    TYPE string,
        lv_hint   TYPE string,
        lv_retry  TYPE string,
        lv_resp   TYPE string,
        lv_ts     TYPE timestampl,
        lv_key    TYPE string.
  FIELD-SYMBOLS <ls_any> TYPE any.

  PERFORM z16_table_exists USING gc_z16_tab_error CHANGING lv_exists.
  IF lv_exists IS INITIAL OR is_alv-error_msg IS INITIAL.
    RETURN.
  ENDIF.

  TRY.
      CREATE DATA lr_line TYPE (gc_z16_tab_error).
      ASSIGN lr_line->* TO <ls_any>.
    CATCH cx_root.
      RETURN.
  ENDTRY.

  GET TIME STAMP FIELD lv_ts.
  lv_key = |ERR_{ is_alv-session_id }_{ is_alv-row_index }_{ iv_field }|.
  PERFORM z16_classify_error USING is_alv-error_msg iv_field CHANGING lv_cat.
  PERFORM build_bdc_action_hint USING is_alv-error_msg iv_field CHANGING lv_hint lv_retry.
  PERFORM z16_guess_responsible USING lv_cat CHANGING lv_resp.

  PERFORM z16_set_comp_str USING 'ERROR_ID'         lv_key               CHANGING <ls_any>.
  PERFORM z16_set_comp_str USING 'SESSION_ID'       is_alv-session_id    CHANGING <ls_any>.
  PERFORM z16_set_comp_str USING 'ROW_INDEX'        is_alv-row_index     CHANGING <ls_any>.
  PERFORM z16_set_comp_str USING 'PO_KEY'           is_alv-record_key    CHANGING <ls_any>.
  PERFORM z16_set_comp_str USING 'RECORD_KEY'       is_alv-record_key    CHANGING <ls_any>.
  PERFORM z16_set_comp_str USING 'TCODE'            is_alv-tcode         CHANGING <ls_any>.
  PERFORM z16_set_comp_str USING 'FIELD_NAME'       iv_field             CHANGING <ls_any>.
  PERFORM z16_set_comp_str USING 'CURRENT_VALUE'    iv_value             CHANGING <ls_any>.
  PERFORM z16_set_comp_str USING 'ERROR_CATEGORY'   lv_cat               CHANGING <ls_any>.
  PERFORM z16_set_comp_str USING 'ERROR_MESSAGE'    is_alv-error_msg     CHANGING <ls_any>.
  PERFORM z16_set_comp_str USING 'ACTION_HINT'      lv_hint              CHANGING <ls_any>.
  PERFORM z16_set_comp_str USING 'SUGGESTED_VALUES' ''                   CHANGING <ls_any>.
  PERFORM z16_set_comp_str USING 'RESPONSIBLE'      lv_resp              CHANGING <ls_any>.
  PERFORM z16_set_comp_str USING 'RETRYABLE'        lv_retry             CHANGING <ls_any>.
  PERFORM z16_set_comp_str USING 'STATUS'           'UNFIXED'            CHANGING <ls_any>.
  PERFORM z16_set_comp_str USING 'CREATED_BY'       sy-uname             CHANGING <ls_any>.
  PERFORM z16_set_comp_str USING 'CREATED_AT'       lv_ts                CHANGING <ls_any>.

  lv_tab = gc_z16_tab_error.
  TRY.
      MODIFY (lv_tab) FROM <ls_any>.
    CATCH cx_root.
  ENDTRY.
ENDFORM.
*<<< END FORM z16_insert_error_record

*>>> FORM z16_write_structured_errors - moved from Z_BDC_MASS_PO_ENTRY_F01_BUP

FORM z16_write_structured_errors.
  DATA: lv_field TYPE lvc_fname,
        lv_value TYPE string.
  FIELD-SYMBOLS <lv_any> TYPE any.

  LOOP AT gt_staging_alv INTO DATA(ls_err) WHERE status = gc_st_error.
    IF ls_err-cell_colors IS INITIAL.
      PERFORM z16_insert_error_record USING ls_err '' ''.
    ELSE.
      LOOP AT ls_err-cell_colors INTO DATA(ls_color).
        CLEAR: lv_field, lv_value.
        lv_field = ls_color-fname.
        ASSIGN COMPONENT lv_field OF STRUCTURE ls_err TO <lv_any>.
        IF sy-subrc = 0.
          lv_value = |{ <lv_any> }|.
        ENDIF.
        PERFORM z16_insert_error_record USING ls_err lv_field lv_value.
      ENDLOOP.
    ENDIF.
  ENDLOOP.
  COMMIT WORK.
ENDFORM.
*<<< END FORM z16_write_structured_errors
