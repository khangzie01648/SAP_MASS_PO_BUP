*& Exact SAP protocol in Issue Detail + PROCESSED truth-safe classification

*& Include ZBDC_MPE_M4_ERROR_BUP
*& Purpose Structured errors, fix guide, retry evidence and AI advisory
*& direct OpenAI API with workload-specific key routing

FORM batch_prefix_from_sid USING iv_session_id TYPE csequence
                               CHANGING cv_batch_prefix TYPE csequence.
  DATA: lv_sid    TYPE string,
        lv_len    TYPE i,
        lv_pos    TYPE i,
        lv_suffix TYPE string.

  CLEAR cv_batch_prefix.
  lv_sid = iv_session_id.
  CONDENSE lv_sid NO-GAPS.
  lv_len = strlen( lv_sid ).

 "New format: BYYYYMMDDHHMMSS_001 -> BYYYYMMDDHHMMSS.
  IF lv_len >= 5.
    lv_pos = lv_len - 4.
    lv_suffix = lv_sid+lv_pos(4).
    IF lv_suffix+0(1) = '_' AND lv_suffix+1(3) CO '0123456789'.
      cv_batch_prefix = lv_sid+0(lv_pos).
      RETURN.
    ENDIF.
  ENDIF.

 "Compatibility with two-digit suffix: SES_YYYYMMDD_HHMMSS_01.
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

FORM first_sm35_error
  USING    pv_qid    TYPE apqi-qid
  CHANGING cv_text   TYPE string
           cv_dynpro TYPE string.

  DATA: lt_log      TYPE ty_t_bdclm,
        ls_log      TYPE bdclm,
        ls_diag     TYPE bdclm,
        lv_msg      TYPE char255,
        lv_diag_msg TYPE char255,
        lv_mode     TYPE c LENGTH 1,
        lv_mode_txt TYPE char50,
        lv_upper    TYPE string,
        lv_have_diag TYPE abap_bool.

  CLEAR: cv_text, cv_dynpro, lv_mode, lv_mode_txt,
         ls_diag, lv_diag_msg, lv_have_diag.

  PERFORM get_sm35_log USING pv_qid CHANGING lt_log.
  IF lt_log IS INITIAL.
    RETURN.
  ENDIF.

  PERFORM detect_sm35_mode_from_log
    USING    lt_log
    CHANGING lv_mode lv_mode_txt.

 "Primary authority in every SM35 mode: exact E/A/X protocol.
  LOOP AT lt_log INTO ls_log.
    IF ls_log-mart <> 'E' AND
       ls_log-mart <> 'A' AND
       ls_log-mart <> 'X'.
      CONTINUE.
    ENDIF.

    CLEAR lv_msg.
    PERFORM format_sm35_log_line
      USING    ls_log
      CHANGING lv_msg.
    IF lv_msg IS INITIAL.
      CONTINUE.
    ENDIF.

    cv_text   = lv_msg.
    cv_dynpro = |{ ls_log-module }/{ ls_log-dynr }|.
    RETURN.
  ENDLOOP.

 "Mode N special case: Control Framework can be logged as MART='S' while
 "the batch-input transaction terminates as Incorrect. Treat the exact
 "fatal diagnostic as error evidence, never as business success.
  IF lv_mode = 'N'.
    LOOP AT lt_log INTO ls_log.
      CLEAR: lv_msg, lv_upper.
      PERFORM format_sm35_log_line
        USING    ls_log
        CHANGING lv_msg.
      lv_upper = lv_msg.
      TRANSLATE lv_upper TO UPPER CASE.

      IF ( ls_log-mid = 'DC' AND
           ( ls_log-mnr = '001' OR ls_log-mnr = '006' ) ) OR
         lv_upper CS 'CONTROL FRAMEWORK' OR
         lv_upper CS 'GUI CANNOT BE REACHED' OR
         lv_upper CS 'FATAL ERROR' OR
         lv_upper CS 'RAISE_EXCEPTION'.
        ls_diag = ls_log.
        lv_diag_msg = lv_msg.
        lv_have_diag = abap_true.
      ENDIF.
    ENDLOOP.

    IF lv_have_diag = abap_true.
      cv_text   = lv_diag_msg.
      cv_dynpro = |{ ls_diag-module }/{ ls_diag-dynr }|.
    ENDIF.
  ENDIF.
ENDFORM.

*& Read real SM35 proof for one business document group

*& BUILD_ERROR_TEXT - gom message de debug duoc tat ca case
*& Neu khong co E/A thi dump S/W/I de tranh "khong bat duoc message"

*& NORMALIZE_BDC_MESSAGE
*& Converts raw BDCMSGCOLL into one structured message record.
*& Safer than depending on CONVERT_BDCMSGCOLL_TO_BAPIRET2 because every
*& SAP system that supports BDC has BDCMSGCOLL + FORMAT_MESSAGE.

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
 "SAP warning messages are audited as protocol detail,
 "not as lifecycle failure. Group lifecycle is decided later
 "from hard errors + verified terminal execution, so successful documents
 "do not remain WARNING merely because SAP returned a non-blocking W.
      PS_NORM-EXEC_STATUS = 'INFO'.
    WHEN 'I'.
      PS_NORM-EXEC_STATUS = 'INFO'.
    WHEN OTHERS.
      PS_NORM-EXEC_STATUS = GC_ST_ERROR.
  ENDCASE.

  PERFORM BUILD_BDC_ACTION_HINT
    USING    PS_NORM-MESSAGE PS_NORM-FIELD_NAME
    CHANGING PS_NORM-ACTION_HINT PS_NORM-RETRY_FLAG.

ENDFORM.

*& BUILD_BDC_ACTION_HINT
*& Rule-based fix hint for dashboard/export/fix guide.

FORM BUILD_BDC_ACTION_HINT
  USING    PV_MESSAGE TYPE ANY
           PV_FIELD   TYPE ANY
  CHANGING CV_HINT    TYPE ANY
           CV_RETRY   TYPE ANY.

  DATA: lv_text      TYPE string,
        lv_field     TYPE string,
        lv_transient TYPE abap_bool,
        lv_reason    TYPE string.

  CLEAR: cv_hint, cv_retry.
  lv_text  = pv_message.
  lv_field = pv_field.
  TRANSLATE lv_text TO LOWER CASE.
  TRANSLATE lv_field TO LOWER CASE.

  PERFORM text_transient
    USING lv_text
    CHANGING lv_transient lv_reason.
  IF lv_transient = abap_true.
    cv_retry = 'X'.
    cv_hint = |Transient technical issue ({ lv_reason }): wait briefly, refresh, and retry without changing source data first.|.
    RETURN.
  ENDIF.

 "known business rejection/faulty/held outcomes are not transient.
 "If SAP allocated an object number, it must be reviewed before any retry.
  IF lv_text CS 'document still faulty' OR lv_text CS 'still faulty' OR
     lv_text CS 'faulty' OR lv_text CS 'incomplete' OR
     lv_text CS 'not complete' OR lv_text CS 'not saved' OR
     lv_text CS 'was held' OR lv_text CS 'document held' OR
     lv_text CS ' hold' OR lv_text CS 'held' OR
     lv_text CS 'cancel' OR lv_text CS 'terminated'.
    CLEAR cv_retry.
    cv_hint = 'SAP rejected or left the business document incomplete. Correct source/master/customizing; review the exact SAP protocol before any retry.'.
    RETURN.
  ENDIF.

  IF lv_text CS 'screen' OR lv_text CS 'dynpro' OR
     lv_text CS 'field not found' OR
     lv_text CS 'batch input data' OR
     lv_text CS 'no batch input data found'.
    cv_hint = 'Recording/screen contract mismatch: re-record the scenario or regenerate mapping; do not blame source data first.' .
  ELSEIF lv_text CS 'required' OR lv_text CS 'mandatory' OR
         lv_text CS 'missing' OR lv_text CS 'initial' OR
         lv_text CS 'enter'.
    cv_hint = 'Fill the required mapped source column, validate the row, and rerun.' .
  ELSEIF lv_text CS 'authorization' OR lv_text CS 'not authorized' OR
         lv_text CS 'no authorization'.
    cv_hint = 'Request the required SAP authorization for the target transaction or object.' .
  ELSEIF lv_text CS 'not defined' OR lv_text CS 'does not exist' OR
         lv_text CS 'invalid' OR lv_text CS 'not allowed'.
    cv_hint = 'Check the mapped value against SAP master data/customizing, correct it, and validate again.' .
  ELSEIF lv_text CS 'format' OR lv_text CS 'conversion' OR
         lv_text CS 'numeric' OR lv_text CS 'date'.
    cv_hint = 'Correct the source value format according to the generated template and SAP field type.' .
  ELSE.
    cv_hint = 'Open the SAP protocol, correct the mapped source value or recording, validate, and rerun.' .
  ENDIF.
ENDFORM.

*& SAVE_BDC_MESSAGE_LOGS - MUC 3/4: persist normalized BDC messages
*& Raw source: BDCMSGCOLL from CALL TRANSACTION ... MESSAGES INTO MESSTAB
*& Normalized output: ZBDC_RESULT_BUP structured log
*& Supports dashboard, drilldown, retry, AI analyst, fix guide export

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
        LV_TS       TYPE TZNTSTMPS,
        LV_DEMO_DATE_836 TYPE SY-DATUM,
        LV_DEMO_TIME_836 TYPE SY-UZEIT.

  FIELD-SYMBOLS <FV> TYPE ANY.

  READ TABLE PT_GROUP INTO LS_G INDEX 1.
  IF SY-SUBRC <> 0.
    RETURN.
  ENDIF.

  IF MESSTAB[] IS INITIAL.
 "CALL TRANSACTION may return SY-SUBRC=0 without an application message.
 "The caller persists the authoritative final SY-SUBRC decision separately;
 "do not manufacture a warning/error protocol row here.
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
    PERFORM get_demo_now CHANGING LV_DEMO_DATE_836 LV_DEMO_TIME_836.

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
    SET_RES 'CREATED_ON'    LV_DEMO_DATE_836.
    SET_RES 'CREATED_TM'    LV_DEMO_TIME_836.
    SET_RES 'CREATED_TIME'  LV_DEMO_TIME_836.
    SET_RES 'CREATED_BY'    SY-UNAME.

    INSERT ZBDC_RESULT_BUP FROM LS_RES.
    IF SY-SUBRC <> 0.
      MODIFY ZBDC_RESULT_BUP FROM LS_RES.
    ENDIF.
  ENDLOOP.

ENDFORM.

*& SAVE_SYNTHETIC_ENGINE_LOG - logs engine decisions not returned by SAP
*& Examples: empty BDCDATA, BDC_INSERT failure, retry decision, empty MESSTAB

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
        LV_DEMO_DATE_836 TYPE SY-DATUM,
        LV_DEMO_TIME_836 TYPE SY-UZEIT,
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
  ELSEIF PV_STATUS = GC_ST_WARNING OR PV_STATUS = GC_ST_PARTIAL.
    "PARTIAL is an execution/proof state, not automatically an SAP error.
    "The exact SAP application message keeps its own original S/W/E type.
    LV_TYPE = 'W'.
  ELSEIF PV_STATUS = GC_ST_SM35Q OR PV_STATUS = GC_ST_PROCESSED.
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
  PERFORM get_demo_now CHANGING LV_DEMO_DATE_836 LV_DEMO_TIME_836.

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
  SET_RES2 'CREATED_ON'    LV_DEMO_DATE_836.
  SET_RES2 'CREATED_TM'    LV_DEMO_TIME_836.
  SET_RES2 'CREATED_TIME'  LV_DEMO_TIME_836.
  SET_RES2 'CREATED_BY'    SY-UNAME.

  INSERT ZBDC_RESULT_BUP FROM LS_RES.
  IF SY-SUBRC <> 0.
    MODIFY ZBDC_RESULT_BUP FROM LS_RES.
  ENDIF.

ENDFORM.

*& UPDATE_EXEC_COUNTERS - single source for execution counters

FORM SET_EXEC_ACTION_HINT CHANGING CS_EXEC TYPE TY_EXEC_DISP.
  CLEAR CS_EXEC-ACTION_HINT.

  CASE CS_EXEC-RUN_STATUS.
    WHEN GC_ST_READY.
      CS_EXEC-ACTION_HINT = 'Execute All or Execute Selected'.
    WHEN GC_ST_SUCCESS.
 "show the exact success evidence directly in the cockpit when
 "SAP returned one. The full text remains available in Evidence Detail.
      IF CS_EXEC-MESSAGE IS NOT INITIAL AND
         CS_EXEC-MESSAGE NS 'no application business S-message' AND
         CS_EXEC-MESSAGE NS 'no terminal S-message was returned' AND
         CS_EXEC-MESSAGE NS 'EXECUTION_STATUS=SUCCESS'.
        CS_EXEC-ACTION_HINT = |Evidence: { CS_EXEC-MESSAGE }|.
      ELSE.
        CS_EXEC-ACTION_HINT = 'View execution evidence'.
      ENDIF.
    WHEN GC_ST_SM35Q.
      IF CS_EXEC-MESSAGE CS 'is processing'.
        CS_EXEC-ACTION_HINT = 'Refresh cockpit; monitor SM35/SM37 until completion'.
      ELSEIF CS_EXEC-MESSAGE CS 'background job' OR
             CS_EXEC-MESSAGE CS 'RSBDCCTU' OR
             CS_EXEC-MESSAGE CS 'RSBDCBTC' OR
             CS_EXEC-MESSAGE CS 'background processing'.
        CS_EXEC-ACTION_HINT = 'Managed processing started; monitor proof in 0500 or SM37'.
      ELSEIF CS_EXEC-MESSAGE CS 'returned from'.
        CS_EXEC-ACTION_HINT = 'Review SM35 log; correct incorrect transactions if any'.
      ELSE.
        CS_EXEC-ACTION_HINT = 'Managed SM35 processing is pending; Refresh reconciles terminal proof'.
      ENDIF.
    WHEN GC_ST_ERROR.
      CS_EXEC-ACTION_HINT = 'Open Error Detail or Fix Guide'.
    WHEN GC_ST_WARNING OR 'PARTIAL'.
      CS_EXEC-ACTION_HINT = 'Review warning; refresh dashboard before closing'.
    WHEN OTHERS.
      CS_EXEC-ACTION_HINT = 'Refresh cockpit or reload staging session'.
  ENDCASE.
ENDFORM.

FORM set_salv_col_text
  USING    po_cols TYPE REF TO cl_salv_columns_table
           pv_name TYPE lvc_fname
           pv_short TYPE string
           pv_medium TYPE string
           pv_long TYPE string.
  DATA lo_col TYPE REF TO cl_salv_column_table.
  DATA lv_s TYPE scrtext_s.
  DATA lv_m TYPE scrtext_m.
  DATA lv_l TYPE scrtext_l.

  TRY.
      lo_col ?= po_cols->get_column( pv_name ).
      lv_s = pv_short.
      lv_m = pv_medium.
      lv_l = pv_long.
      lo_col->set_short_text( lv_s ).
      lo_col->set_medium_text( lv_m ).
      lo_col->set_long_text( lv_l ).
    CATCH cx_root.
  ENDTRY.
ENDFORM.

FORM set_salv_col_width
  USING    po_cols TYPE REF TO cl_salv_columns_table
           pv_name TYPE lvc_fname
           pv_width TYPE i.
* Explicit SALV output widths are required for popup readability.
* wrapped long text losslessly, but this helper was intentionally a
* no-op from an old compatibility workaround. As a result classic SALV could
* auto-optimize DETAIL to only a few visible characters even though the popup
* had plenty of free space. Use literal SET_OUTPUT_LENGTH calls so the method
* remains syntax-safe on releases where a variable argument is typed narrowly.
  DATA lo_col TYPE REF TO cl_salv_column_table.

  IF po_cols IS INITIAL OR pv_name IS INITIAL OR pv_width <= 0.
    RETURN.
  ENDIF.

  TRY.
      lo_col ?= po_cols->get_column( pv_name ).

      CASE pv_width.
        WHEN 20.
          lo_col->set_output_length( 20 ).
        WHEN 24.
          lo_col->set_output_length( 24 ).
        WHEN 28.
          lo_col->set_output_length( 28 ).
        WHEN 40.
          lo_col->set_output_length( 40 ).
        WHEN 60.
          lo_col->set_output_length( 60 ).
        WHEN 84.
          lo_col->set_output_length( 84 ).
        WHEN 96.
          lo_col->set_output_length( 96 ).
        WHEN 100.
          lo_col->set_output_length( 100 ).
        WHEN 132.
          lo_col->set_output_length( 132 ).
        WHEN OTHERS.
 "All current popup calls use one of the literal widths above.
 "Do not silently guess a dynamic width on older SALV signatures.
          lo_col->set_output_length( 84 ).
      ENDCASE.
    CATCH cx_root.
 "Presentation fallback only; never interrupt execution/evidence logic.
  ENDTRY.
ENDFORM.

* ============================================================
* true long-text renderer for issue detail / Fix Guide.
* Classic SALV visually limits long cell content on some SAP GUI releases.
* HTML viewer keeps each semantic item together and lets the browser wrap the
* value naturally to the available window width. No character-count wrapping,
* no fake continuation rows, and no text is shortened for presentation.
* ============================================================
FORM html_escape_text
  USING    iv_text TYPE csequence
  CHANGING cv_text TYPE string.
  cv_text = iv_text.
  REPLACE ALL OCCURRENCES OF '&' IN cv_text WITH '&amp;'.
  REPLACE ALL OCCURRENCES OF '<' IN cv_text WITH '&lt;'.
  REPLACE ALL OCCURRENCES OF '>' IN cv_text WITH '&gt;'.
ENDFORM.

FORM append_html_text
  USING    iv_text TYPE csequence
  CHANGING ct_html TYPE ty_t_dash_html_411.
  DATA: lt_words TYPE STANDARD TABLE OF string WITH DEFAULT KEY,
        lv_word  TYPE string,
        lv_part  TYPE string,
        lv_esc   TYPE string.

  IF iv_text IS INITIAL.
    RETURN.
  ENDIF.

  SPLIT iv_text AT space INTO TABLE lt_words.
  LOOP AT lt_words INTO lv_word.
    IF lv_word IS INITIAL.
      CONTINUE.
    ENDIF.

 "Keep every physical HTML transport line safely below CHAR255.
 "Adjacent spans have no visible separator; the final span of each word
 "contains the real breakable space used by the browser for natural wrap.
    WHILE strlen( lv_word ) > 30.
      lv_part = lv_word(30).
      SHIFT lv_word BY 30 PLACES LEFT.
      PERFORM html_escape_text USING lv_part CHANGING lv_esc.
      APPEND |<span class="tok">{ lv_esc }</span>| TO ct_html.
    ENDWHILE.

    IF lv_word IS NOT INITIAL.
      PERFORM html_escape_text USING lv_word CHANGING lv_esc.
      APPEND |<span class="tok">{ lv_esc } </span>| TO ct_html.
    ENDIF.
  ENDLOOP.
ENDFORM.

FORM build_cards_html
  USING    it_cards TYPE ty_t_fix_card_789
           iv_title TYPE csequence
  CHANGING ct_html  TYPE ty_t_dash_html_411.
  DATA: ls_card TYPE ty_fix_card_789,
        lv_sec  TYPE string,
        lv_det  TYPE string.

  REFRESH ct_html.

  APPEND '<html><head>' TO ct_html.
  APPEND '<meta http-equiv="X-UA-Compatible" content="IE=edge">' TO ct_html.
  APPEND '<meta charset="utf-8">' TO ct_html.
  APPEND '<style>' TO ct_html.
 "let the embedded browser own vertical scrolling. Absolute full-height
 "scroll panes can become partly unreachable when SAP GUI / Windows DPI or the
 "taskbar reduces the visible work area. Root-document scrolling remains usable
 "with the mouse wheel, scrollbar, PageDown and keyboard focus.
  APPEND 'html{width:100%;height:100%;margin:0;padding:0;overflow-y:scroll;overflow-x:hidden;background:#f5f7fa;}' TO ct_html.
  APPEND 'body{width:100%;min-height:100%;margin:0;padding:0;overflow:visible;background:#f5f7fa;font-family:Arial,sans-serif;color:#172b4d;}' TO ct_html.
  APPEND '.scrollpane{position:static;width:100%;height:auto;overflow:visible;}' TO ct_html.
  APPEND '.wrap{box-sizing:border-box;padding:14px 16px 110px 16px;min-height:100%;}' TO ct_html.
  APPEND '.title{font-size:18px;font-weight:700;margin:0 0 12px 0;color:#0b4f8a;}' TO ct_html.
  APPEND 'table{width:100%;border-collapse:collapse;table-layout:fixed;background:#fff;border:1px solid #d8dee8;}' TO ct_html.
  APPEND 'td{border-bottom:1px solid #e1e6ee;vertical-align:top;}' TO ct_html.
  APPEND '.label{width:220px;padding:7px 10px;font-weight:600;background:#f7f9fc;}' TO ct_html.
  APPEND '.value{padding:7px 10px;word-wrap:break-word;overflow-wrap:anywhere;}' TO ct_html.
  APPEND '.section{padding:8px 10px;font-weight:700;background:#eaf3ff;color:#153e75;}' TO ct_html.
  APPEND '.txt{font-size:0;line-height:1.45;}' TO ct_html.
  APPEND '.tok{font-size:13px;line-height:1.45;}' TO ct_html.
  APPEND '.title .tok{font-size:18px;font-weight:700;}' TO ct_html.
  APPEND '</style></head><body><div class="scrollpane"><div class="wrap">' TO ct_html.
  APPEND '<div class="title txt">' TO ct_html.
  PERFORM append_html_text USING iv_title CHANGING ct_html.
  APPEND '</div><table>' TO ct_html.

  LOOP AT it_cards INTO ls_card.
    lv_sec = ls_card-section.
    lv_det = ls_card-detail.

    IF lv_det IS INITIAL.
      APPEND '<tr><td class="section txt" colspan="2">' TO ct_html.
      PERFORM append_html_text USING lv_sec CHANGING ct_html.
      APPEND '</td></tr>' TO ct_html.
    ELSE.
      APPEND '<tr><td class="label txt">' TO ct_html.
      PERFORM append_html_text USING lv_sec CHANGING ct_html.
      APPEND '</td><td class="value txt">' TO ct_html.
      PERFORM append_html_text USING lv_det CHANGING ct_html.
      APPEND '</td></tr>' TO ct_html.
    ENDIF.
  ENDLOOP.

  APPEND '</table></div></div></body></html>' TO ct_html.
ENDFORM.

FORM free_long_dialog.
  IF go_long_812_html IS BOUND.
    TRY.
        go_long_812_html->free( ).
      CATCH cx_root.
    ENDTRY.
  ENDIF.
  IF go_long_812_dlg IS BOUND.
    TRY.
        go_long_812_dlg->free( ).
      CATCH cx_root.
    ENDTRY.
  ENDIF.
  CLEAR: go_long_812_html, go_long_812_dlg, go_long_evt_812, gv_long_812_url.
ENDFORM.

FORM show_long_cards
  USING    it_cards TYPE ty_t_fix_card_789
           iv_title TYPE csequence
  CHANGING cv_ok    TYPE abap_bool.
  DATA: lt_html    TYPE ty_t_dash_html_411,
        lv_caption TYPE c LENGTH 100.

  CLEAR cv_ok.
  PERFORM free_long_dialog.
  PERFORM build_cards_html USING it_cards iv_title CHANGING lt_html.
  IF lt_html IS INITIAL.
    RETURN.
  ENDIF.

  lv_caption = iv_title.
  CREATE OBJECT go_long_812_dlg
    EXPORTING
      width   = 1000
 "keep the dialog viewport safely above the Windows taskbar on
 "common SAP GUI/DPI combinations. Long content is handled by the browser
 "scrollbar, so dialog height no longer depends on content length.
      height  = 440
      top     = 10
      left    = 20
      caption = lv_caption
    EXCEPTIONS
      cntl_error = 1
      OTHERS     = 2.
  IF sy-subrc <> 0 OR go_long_812_dlg IS NOT BOUND.
    PERFORM free_long_dialog.
    RETURN.
  ENDIF.

  CREATE OBJECT go_long_evt_812.
  SET HANDLER go_long_evt_812->on_dialog_close FOR go_long_812_dlg.

  CREATE OBJECT go_long_812_html
    EXPORTING
      parent = go_long_812_dlg
    EXCEPTIONS
      cntl_error = 1
      OTHERS     = 2.
  IF sy-subrc <> 0 OR go_long_812_html IS NOT BOUND.
    PERFORM free_long_dialog.
    RETURN.
  ENDIF.

  CLEAR gv_long_812_url.
  CALL METHOD go_long_812_html->load_data
    EXPORTING
      type         = 'text'
      subtype      = 'html'
    IMPORTING
      assigned_url = gv_long_812_url
    CHANGING
      data_table   = lt_html
    EXCEPTIONS
      dp_invalid_parameter = 1
      dp_error_general     = 2
      cntl_error           = 3
      OTHERS               = 4.
  IF sy-subrc <> 0 OR gv_long_812_url IS INITIAL.
    PERFORM free_long_dialog.
    RETURN.
  ENDIF.

  CALL METHOD go_long_812_html->show_url
    EXPORTING
      url      = gv_long_812_url
      in_place = 'X'
    EXCEPTIONS
      cntl_error             = 1
      cnht_error_not_allowed = 2
      cnht_error_parameter   = 3
      dp_error_general       = 4
      OTHERS                 = 5.
  IF sy-subrc <> 0.
    PERFORM free_long_dialog.
    RETURN.
  ENDIF.

  CALL METHOD cl_gui_cfw=>flush
    EXCEPTIONS
      cntl_system_error = 1
      cntl_error        = 2
      OTHERS            = 3.

  cv_ok = abap_true.
ENDFORM.

FORM error_prompt_stale
  USING    iv_text TYPE c
  CHANGING cv_stale TYPE abap_bool.
  DATA lv_text TYPE char255.

  CLEAR cv_stale.
  lv_text = iv_text.
  TRANSLATE lv_text TO UPPER CASE.
  CONDENSE lv_text.
  SHIFT lv_text LEFT DELETING LEADING space.

  IF lv_text CP 'ENTER*' OR
     lv_text CP 'PLEASE*' OR
     lv_text CS ' PLEASE ' OR
     lv_text CS ' IS REQUIRED' OR
     lv_text CS ' REQUIRED FIELD'.
    cv_stale = abap_true.
  ENDIF.

  IF lv_text CS 'NO BATCH INPUT DATA FOUND FOR DYNPRO' OR
     lv_text CS 'DOES NOT EXIST IN DYNPRO' OR
     lv_text CS 'TRANSACTION ENDED' OR
     lv_text CS 'BDC EXECUTION FAILED'.
    CLEAR cv_stale.
  ENDIF.
ENDFORM.

FORM pick_protocol
  USING    is_stg TYPE ty_staging_alv
           is_exec TYPE ty_exec_disp
  CHANGING cv_protocol TYPE char255.

  DATA: lv_stale       TYPE abap_bool,
        lt_res          TYPE ty_t_result_726,
        ls_res          TYPE zbdc_result_bup,
        lv_admin_s      TYPE abap_bool,
        lv_sm35_seen    TYPE abap_bool,
        lv_sm35_tx_ok   TYPE string,
        ls_group_735    TYPE ty_group_0100_disp,
        ls_live_735     TYPE bdclm,
        lv_sm35_group_735 TYPE apqi-groupid,
        lv_sm35_qid_735 TYPE apqi-qid,
        lv_tidx_735     TYPE i,
        lv_tcnt_735     TYPE i,
        lv_live_735     TYPE abap_bool,
        lv_live_text_735 TYPE char255.

  CLEAR cv_protocol.

 "Error Detail must show SAP protocol, not the later synthetic
 "engine summary (for example PROCESSED / terminal outcome requires review).
 "Read the persisted CALL TRANSACTION messages first. For PROCESSED,
 "prefer the latest real SAP success line; for other states prefer the
 "latest real SAP message. FIELD_NAME='ENGINE' is synthetic Z logic.
  IF is_stg-record_key IS NOT INITIAL.
 "protocol is group evidence. SM35 protocol is persisted on the
 "canonical row of a multi-row business group, while the selected cockpit
 "row may be a different ROW_INDEX. RECORD_KEY is the group authority.
    SELECT *
      FROM zbdc_result_bup
      INTO TABLE @lt_res
      WHERE session_id = @is_stg-session_id
        AND record_key = @is_stg-record_key.
  ELSE.
    SELECT *
      FROM zbdc_result_bup
      INTO TABLE @lt_res
      WHERE session_id = @is_stg-session_id
        AND row_index  = @is_stg-row_index.
  ENDIF.

  SORT lt_res BY step DESCENDING.

 "SUCCESS evidence is symmetric for both executors.
 "BISM uses the newest exact application S-message from SM35 Extended Log;
 "CT uses the newest exact S-message from BDCMSGCOLL. SM35 controller and
 "diagnostic lines are never presented as the business success message.
  IF is_exec-run_status = GC_ST_SUCCESS.
    CLEAR: lv_sm35_seen, lv_sm35_tx_ok.

 "Detect BISM from durable SM35_BIND as well as protocol rows.
 "A terminal session can have the exact binding persisted before its
 "application success row is copied into RESULT.
    LOOP AT lt_res INTO ls_res.
      IF ls_res-field_name = 'SM35_BIND' OR ls_res-field_name = 'SM35'.
        lv_sm35_seen = abap_true.
        EXIT.
      ENDIF.
    ENDLOOP.

 "1) Durable exact application S-message has highest priority.
    IF lv_sm35_seen = abap_true.
      LOOP AT lt_res INTO ls_res
        WHERE field_name = 'SM35'
          AND msg_type   = 'S'.
        IF ls_res-exec_status = 'SM35_APP_S' AND
           ls_res-message IS NOT INITIAL.
          cv_protocol = ls_res-message.
          EXIT.
        ENDIF.
        IF ls_res-exec_status = 'SM35_TX_OK' AND
           lv_sm35_tx_ok IS INITIAL AND
           ls_res-message IS NOT INITIAL.
          lv_sm35_tx_ok = ls_res-message.
        ENDIF.
      ENDLOOP.

 "2) If the durable business row is missing, read the exact Session Name
 "-> QID -> Analyze Session TemSe log BEFORE accepting any generic
 "APQI/session-success text. This makes screen 0500 and Dashboard Level 3
 "use the same evidence authority.
      IF cv_protocol IS INITIAL.
        CLEAR: ls_group_735, ls_live_735, lv_sm35_group_735, lv_sm35_qid_735,
               lv_tidx_735, lv_tcnt_735, lv_live_735, lv_live_text_735.
        ls_group_735-session_id = is_stg-session_id.
        ls_group_735-record_key = is_stg-record_key.
        ls_group_735-row_index  = is_stg-row_index.
        ls_group_735-group_key  = is_stg-record_key.
        ls_group_735-tcode      = is_stg-tcode.
        ls_group_735-executor   = 'BISM'.
        ls_group_735-lifecycle  = 'SUCCESS'.
        ls_group_735-attempt    = is_exec-attempt.

        PERFORM resolve_sm35_audit
          USING    ls_group_735 lt_res
          CHANGING lv_sm35_group_735 lv_sm35_qid_735
                   lv_tidx_735 lv_tcnt_735.
        IF lv_sm35_qid_735 IS NOT INITIAL AND lv_tidx_735 > 0.
          PERFORM resolve_sm35_live_evid
            USING    lv_sm35_group_735 lv_sm35_qid_735
                     lv_tidx_735 'SUCCESS'
            CHANGING lv_live_735 ls_live_735 lv_live_text_735.
          IF lv_live_735 = abap_true AND
             lv_live_text_735 IS NOT INITIAL.
            cv_protocol = lv_live_text_735.
          ENDIF.
        ENDIF.
      ENDIF.

 "3) Only after exact live evidence fails may a persisted non-admin
 "SM35 success line be used. Controller 00/355 remains the final fallback.
      IF cv_protocol IS INITIAL.
        LOOP AT lt_res INTO ls_res
          WHERE field_name = 'SM35'
            AND msg_type   = 'S'.
          IF ls_res-exec_status = 'SM35_DIAG' OR
             ls_res-exec_status = 'SM35_TX_OK'.
            CONTINUE.
          ENDIF.
          CLEAR lv_admin_s.
          PERFORM is_sm35_admin_s USING ls_res CHANGING lv_admin_s.
          IF lv_admin_s <> abap_true AND ls_res-message IS NOT INITIAL.
            cv_protocol = ls_res-message.
            EXIT.
          ENDIF.
        ENDLOOP.
      ENDIF.

      IF cv_protocol IS INITIAL AND lv_sm35_tx_ok IS NOT INITIAL.
        cv_protocol = lv_sm35_tx_ok.
      ENDIF.

    ELSE.
 "CALL TRANSACTION path: exact final S-message from BDCMSGCOLL/RESULT.
      LOOP AT lt_res INTO ls_res
        WHERE field_name <> 'ENGINE'
          AND field_name <> 'DB_PROOF'
          AND field_name <> 'SAP_PROTO_PROOF'
          AND field_name <> 'SM35_BIND'
          AND field_name <> 'SM35_PREOBJ'
          AND field_name <> 'SM35_PRESET'
          AND field_name <> 'Z264_MARK'
          AND field_name <> 'STAGING'
          AND field_name <> 'OBJ_RESOLVE'
          AND msg_type = 'S'.
        IF ls_res-message IS NOT INITIAL.
          cv_protocol = ls_res-message.
          EXIT.
        ENDIF.
      ENDLOOP.
    ENDIF.
  ENDIF.

 "ERROR/WARNING evidence also resolves from the exact live SM35
 "Analyze Session log when persisted SM35 rows are incomplete. This is the
 "same QID + transaction-index authority as Level 3 and works for A/E/N.
  IF cv_protocol IS INITIAL AND
     ( is_exec-run_status = GC_ST_ERROR OR
       is_exec-run_status = GC_ST_WARNING ).
    CLEAR: ls_group_735, ls_live_735, lv_sm35_group_735, lv_sm35_qid_735,
           lv_tidx_735, lv_tcnt_735, lv_live_735, lv_live_text_735.
    ls_group_735-session_id = is_stg-session_id.
    ls_group_735-record_key = is_stg-record_key.
    ls_group_735-row_index  = is_stg-row_index.
    ls_group_735-group_key  = is_stg-record_key.
    ls_group_735-tcode      = is_stg-tcode.
    ls_group_735-executor   = 'BISM'.
    ls_group_735-lifecycle  = is_exec-run_status.
    ls_group_735-attempt    = is_exec-attempt.

    PERFORM resolve_sm35_audit
      USING    ls_group_735 lt_res
      CHANGING lv_sm35_group_735 lv_sm35_qid_735
               lv_tidx_735 lv_tcnt_735.
    IF lv_sm35_qid_735 IS NOT INITIAL AND lv_tidx_735 > 0.
      PERFORM resolve_sm35_live_evid
        USING    lv_sm35_group_735 lv_sm35_qid_735 lv_tidx_735 is_exec-run_status
        CHANGING lv_live_735 ls_live_735 lv_live_text_735.
      IF lv_live_735 = abap_true AND lv_live_text_735 IS NOT INITIAL.
        cv_protocol = lv_live_text_735.
      ENDIF.
    ENDIF.
  ENDIF.

  IF cv_protocol IS INITIAL AND is_exec-run_status = GC_ST_PROCESSED.
    LOOP AT lt_res INTO ls_res
      WHERE field_name <> 'ENGINE'
        AND field_name <> 'DB_PROOF'
        AND field_name <> 'SAP_PROTO_PROOF'
        AND field_name <> 'SM35_BIND'
        AND field_name <> 'SM35_PREOBJ'
        AND field_name <> 'SM35_PRESET'
        AND field_name <> 'Z264_MARK'
        AND field_name <> 'STAGING'
        AND field_name <> 'OBJ_RESOLVE'
        AND msg_type = 'S'.
      IF ls_res-message IS NOT INITIAL.
        cv_protocol = ls_res-message.
        EXIT.
      ENDIF.
    ENDLOOP.
  ENDIF.

  IF cv_protocol IS INITIAL AND
     NOT ( is_exec-run_status = GC_ST_SUCCESS AND lv_sm35_seen = abap_true ).
    LOOP AT lt_res INTO ls_res
      WHERE field_name <> 'ENGINE'
        AND field_name <> 'DB_PROOF'
        AND field_name <> 'SAP_PROTO_PROOF'
        AND field_name <> 'SM35_BIND'
        AND field_name <> 'SM35_PREOBJ'
        AND field_name <> 'SM35_PRESET'
        AND field_name <> 'Z264_MARK'
        AND field_name <> 'STAGING'
        AND field_name <> 'OBJ_RESOLVE'.
      IF ls_res-message IS NOT INITIAL.
        cv_protocol = ls_res-message.
        EXIT.
      ENDIF.
    ENDLOOP.
  ENDIF.

 "Only after the real persisted SAP rows are exhausted may the display
 "message/staging text be used as fallback.
  IF cv_protocol IS INITIAL AND is_exec-message IS NOT INITIAL.
 "the validator-generated phrase is synthetic pre-SAP evidence.
 "Tag it before generic prompt filtering so Error Detail cannot label it
 "as an SAP runtime protocol.
    IF is_exec-message CS 'Missing mandatory field' OR
       is_exec-message CS 'STAGING_VALIDATION:'.
      cv_protocol = |STAGING_VALIDATION: { is_exec-message }|.
    ELSE.
      cv_protocol = is_exec-message.
      PERFORM error_prompt_stale USING cv_protocol CHANGING lv_stale.
      IF lv_stale = abap_true.
        CLEAR cv_protocol.
      ENDIF.
    ENDIF.
  ENDIF.

  IF cv_protocol IS INITIAL AND is_stg-error_msg IS NOT INITIAL.
 "no persisted SAP protocol exists here; this text came from
 "Staging/engine validation and must not be presented as SAP rejection.
    cv_protocol = |STAGING_VALIDATION: { is_stg-error_msg }|.
  ENDIF.

  IF cv_protocol IS INITIAL AND is_stg-last_error IS NOT INITIAL.
    cv_protocol = is_stg-last_error.
  ENDIF.

  IF cv_protocol IS INITIAL.
    IF is_exec-run_status = GC_ST_PROCESSED.
      cv_protocol = 'No terminal SAP success/error protocol was captured; review the execution evidence before any rerun.'.
    ELSE.
      cv_protocol = 'No exact SAP runtime protocol was captured for this group.'.
    ENDIF.
  ENDIF.
ENDFORM.

FORM classify_protocol
  USING    iv_protocol TYPE c
  CHANGING cv_category TYPE char40
           cv_summary TYPE char120
           cv_cause TYPE char255
           cv_action TYPE char255.
  DATA: lv_text TYPE char255,
        lv_class TYPE char255.

  lv_text = iv_protocol.
  TRANSLATE lv_text TO UPPER CASE.
  lv_class = lv_text.
 "BLOCKED contains LOCK as a substring. Strip only the engine word
 "before lock classification; keep the original protocol text unchanged.
  REPLACE ALL OCCURRENCES OF 'BLOCKED' IN lv_class WITH ' '.

  IF lv_text CS 'STAGING_VALIDATION:'.
    cv_category = 'STAGING / VALIDATION'.
    cv_summary  = 'The group was blocked before SAP replay by staging/profile validation.'.
    cv_cause    = 'No terminal SAP BDC protocol was captured. The visible message is generated by the upload/mapping validation layer, not by the SAP transaction.'.
    cv_action   = 'Correct the source data or explicit required-field contract, validate the group again, then execute it. Do not treat this as an SAP runtime rejection.'.
  ELSEIF lv_text CS 'NO BATCH INPUT DATA FOUND FOR DYNPRO'.
    cv_category = 'BDC SCREEN DRIFT'.
    cv_summary  = 'SAP requested a dynpro outside the current Import/Start Recording replay sequence.'.
    CONCATENATE
      'The runtime screen path diverged from the current canonical SHDB execution source. This can come from a popup/user state, customizing, or a data-dependent branch;'
      'the generic engine does not invent a dynpro that was not recorded.'
      INTO cv_cause SEPARATED BY space.
    cv_action   = 'Compare the requested PROGRAM/DYNPRO with the current Import/Start Recording. Re-record/import the exact runtime path if needed; Mapping can be reused.' .
  ELSEIF lv_text CS 'DOES NOT EXIST IN DYNPRO'.
    cv_category = 'RECORDING CONTRACT'.
    cv_summary  = 'The recording or mapping points to a field that is not available on the current SAP screen.'.
    cv_cause    = 'The SAP GUI layout, SHDB recording, or mapping contract no longer matches the active transaction screen path.'.
    cv_action   = 'Repair the profile or re-record the scenario, save the mapping, upload a new test file, then retry.' .
  ELSEIF lv_text CS 'BLOCKED BEFORE SAP REPLAY' OR
         lv_text CS 'INITIAL CT CERTIFICATION WAS BLOCKED' OR
         lv_text CS 'EXECUTION BLOCKED'.
    cv_category = 'ENGINE / PROOF GATE'.
    cv_summary  = 'The engine blocked replay before SAP execution; this is not an SAP lock.'.
    cv_cause    = 'The runtime proof/certification gate was incomplete or inconsistent for this frozen profile contract.'.
    cv_action   = 'Use the corrected profile/runtime code and run a new test group. Do not retry this old pre-SAP blocked group.' .
  ELSEIF lv_text CS 'INTERACTIVE CALL TRANSACTION ENDED BEFORE A VERIFIED COMMIT' OR
         lv_text CS 'SAP DIALOG DID NOT POST A FINAL VERIFIED DOCUMENT'.
    cv_category = 'USER CANCEL / NO COMMIT'.
    cv_summary  = 'Foreground SAP execution ended before a verified business commit.'.
    cv_cause    = 'The All-Screens/Errors-Only run returned through Back, Exit, Cancel, Stop, or an unresolved dialog before one terminal business commit was verified.'.
    cv_action   = 'Review the SAP protocol/source data; rerun only when you intentionally want a new execution.' .
  ELSEIF lv_class CS 'LOCK' OR lv_class CS 'ENQUEUE'.
    cv_category = 'LOCK / TEMPORARY'.
    cv_summary  = 'SAP reported a lock or temporary runtime condition.'.
    cv_cause    = 'Another user, job, or SAP process may currently hold the object lock.'.
    cv_action   = 'Wait for SAP to release the lock, then retry only the affected item. Do not rerun successful items.' .
  ELSE.
    cv_category = 'RUNTIME / BUSINESS RULE'.
    cv_summary  = 'SAP rejected this group during BDC replay.'.
    cv_cause    = 'The exact SAP protocol must be reviewed to identify the invalid input, missing master data, popup, or business rule.'.
    cv_action   = 'Review the SAP runtime protocol, correct the source value or master data, validate again, then retry this group only.' .
  ENDIF.
ENDFORM.

*& Recover exact DB-verified object for issue/detail displays

FORM classify_issue
  USING    iv_status   TYPE c
           iv_protocol TYPE c
           iv_object   TYPE any
  CHANGING cv_category TYPE char40
           cv_summary  TYPE char120
           cv_cause    TYPE char255
           cv_action   TYPE char255.

 "IV_OBJECT is intentionally ignored. Keep the signature only
 "for backward-compatible callers while identity discovery is absent.
  CLEAR: cv_category, cv_summary, cv_cause, cv_action.

  IF iv_status = GC_ST_SUCCESS.
    cv_category = 'EXECUTION VERIFIED'.
    cv_summary  = 'SAP replay completed successfully and the terminal execution state is verified.'.
    cv_cause    = 'This is a terminal success evidence view, not a runtime error.'.
    cv_action   = 'No retry is required. Review the execution protocol only for audit.'.
    RETURN.
  ENDIF.

  IF iv_status = GC_ST_PROCESSED.
    cv_category = 'EXECUTION RETURNED'.
    cv_summary  = 'SAP replay returned without a terminal execution error; review the exact protocol if the business outcome is unclear.'.
    cv_cause    = 'The RESET baseline reports execution evidence and protocol only; no business identity is inferred.'.
    cv_action   = 'Review the exact SAP protocol and business result before any rerun.'.
    RETURN.
  ENDIF.

  PERFORM classify_protocol
    USING iv_protocol
    CHANGING cv_category cv_summary cv_cause cv_action.
ENDFORM.

FORM show_issue_detail_safe.
  DATA: lt_card TYPE ty_t_fix_card_789,
        ls_card TYPE ty_fix_card_789,
        ls_stg  TYPE ty_staging_alv,
        ls_exec TYPE ty_exec_disp,
        lt_rows TYPE lvc_t_row,
        ls_row  TYPE lvc_s_row,
        lv_cur_row TYPE i,
        ls_sel_exec TYPE ty_exec_disp,
        lv_selected_evidence TYPE abap_bool,
        lo_alv  TYPE REF TO cl_salv_table,
        lo_cols TYPE REF TO cl_salv_columns_table,
        lx_salv TYPE REF TO cx_salv_msg.

  DATA: lv_protocol TYPE char255,
        lv_detail   TYPE char255,
        lv_header   TYPE lvc_title,
        lv_html_ok  TYPE abap_bool,
        lt_issue_res TYPE ty_t_result_726,
        ls_issue_res TYPE zbdc_result_bup,
        ls_exact_issue TYPE zbdc_result_bup,
        lv_executor TYPE char12,
        lv_user_msg TYPE char255,
        lv_protocol_norm TYPE char255,
        lv_technical_result TYPE char120,
        lv_subrc_text TYPE char20,
        lv_validation_stage TYPE char40,
        lv_screen_text TYPE char40,
        lv_affected_input TYPE char80,
        lv_input_row_text TYPE char40,
        lv_raw_line TYPE string,
        lv_raw_label TYPE char28,
        lv_raw_count TYPE i,
        lt_seen_raw TYPE SORTED TABLE OF char255 WITH UNIQUE KEY table_line,
        lv_off TYPE i,
        lv_colon TYPE i,
        lv_comma TYPE i,
        lv_start TYPE i,
        lv_sub_len TYPE i,
        lv_is_internal TYPE abap_bool,
        lv_sm35_group TYPE apqi-groupid,
        lv_sm35_qid TYPE apqi-qid,
        lv_tidx TYPE i,
        lv_tcnt TYPE i,
        lv_object_proof TYPE abap_bool,
        lv_result_msgid TYPE string,
        lv_result_msgnr TYPE string,
        lv_result_prog  TYPE string,
        ls_group_786 TYPE ty_group_0100_disp.

 "Terminal SUCCESS/PROCESSED rows may be inspected as execution evidence.
  CLEAR: lv_selected_evidence, g_edit_index.
  REFRESH lt_rows.
  IF go_grid_0500 IS BOUND.
    TRY.
        CALL METHOD go_grid_0500->get_selected_rows
          IMPORTING et_index_rows = lt_rows.
      CATCH cx_root.
    ENDTRY.
  ENDIF.

  READ TABLE lt_rows INTO ls_row INDEX 1.
  IF sy-subrc = 0.
    READ TABLE gt_exec_disp INTO ls_sel_exec INDEX ls_row-index.
    IF sy-subrc = 0 AND
       ( ls_sel_exec-run_status = gc_st_processed OR
         ls_sel_exec-run_status = gc_st_success ).
      READ TABLE gt_staging_alv TRANSPORTING NO FIELDS
        WITH KEY session_id = ls_sel_exec-session_id
                 record_key = ls_sel_exec-group_key.
      IF sy-subrc <> 0.
        READ TABLE gt_staging_alv TRANSPORTING NO FIELDS
          WITH KEY record_key = ls_sel_exec-group_key.
      ENDIF.
      IF sy-subrc = 0.
        g_edit_index = sy-tabix.
        lv_selected_evidence = abap_true.
      ENDIF.
    ENDIF.
  ENDIF.

  IF lv_selected_evidence <> abap_true AND go_grid_0500 IS BOUND.
    CLEAR lv_cur_row.
    TRY.
        CALL METHOD go_grid_0500->get_current_cell
          IMPORTING e_row = lv_cur_row.
      CATCH cx_root.
    ENDTRY.
    IF lv_cur_row > 0.
      READ TABLE gt_exec_disp INTO ls_sel_exec INDEX lv_cur_row.
      IF sy-subrc = 0 AND
         ( ls_sel_exec-run_status = gc_st_processed OR
           ls_sel_exec-run_status = gc_st_success ).
        READ TABLE gt_staging_alv TRANSPORTING NO FIELDS
          WITH KEY session_id = ls_sel_exec-session_id
                   record_key = ls_sel_exec-group_key.
        IF sy-subrc <> 0.
          READ TABLE gt_staging_alv TRANSPORTING NO FIELDS
            WITH KEY record_key = ls_sel_exec-group_key.
        ENDIF.
        IF sy-subrc = 0.
          g_edit_index = sy-tabix.
          lv_selected_evidence = abap_true.
        ENDIF.
      ENDIF.
    ENDIF.
  ENDIF.

  IF lv_selected_evidence <> abap_true AND lines( gt_exec_disp ) = 1.
    READ TABLE gt_exec_disp INTO ls_sel_exec INDEX 1.
    IF sy-subrc = 0 AND
       ( ls_sel_exec-run_status = gc_st_processed OR
         ls_sel_exec-run_status = gc_st_success ).
      READ TABLE gt_staging_alv TRANSPORTING NO FIELDS
        WITH KEY session_id = ls_sel_exec-session_id
                 record_key = ls_sel_exec-group_key.
      IF sy-subrc <> 0.
        READ TABLE gt_staging_alv TRANSPORTING NO FIELDS
          WITH KEY record_key = ls_sel_exec-group_key.
      ENDIF.
      IF sy-subrc = 0.
        g_edit_index = sy-tabix.
        lv_selected_evidence = abap_true.
      ENDIF.
    ENDIF.
  ENDIF.

  IF lv_selected_evidence <> abap_true.
    PERFORM pick_0500_issue.
  ENDIF.

  IF g_edit_index IS INITIAL.
    CALL FUNCTION 'POPUP_TO_INFORM'
      EXPORTING
        titel = 'No Evidence Row Selected'
        txt1  = 'Select a SUCCESS/PROCESSED row for evidence, or an ERROR/WARNING/SKIPPED/PARTIAL row for issue detail.'
        txt2  = 'The current selection does not contain a supported execution state.'.
    RETURN.
  ENDIF.

  READ TABLE gt_staging_alv INTO ls_stg INDEX g_edit_index.
  IF sy-subrc <> 0.
    CALL FUNCTION 'POPUP_TO_INFORM'
      EXPORTING
        titel = 'Error Detail Unavailable'
        txt1  = 'The execution group could not be matched to staging data.'
        txt2  = 'Refresh the queue and try again.'.
    RETURN.
  ENDIF.

  READ TABLE gt_exec_disp INTO ls_exec
    WITH KEY session_id = ls_stg-session_id
             group_key  = ls_stg-record_key.
  IF sy-subrc <> 0.
    READ TABLE gt_exec_disp INTO ls_exec
      WITH KEY group_key = ls_stg-record_key.
  ENDIF.
  IF sy-subrc <> 0.
    CALL FUNCTION 'POPUP_TO_INFORM'
      EXPORTING
        titel = 'Execution Detail Unavailable'
        txt1  = 'No execution row matches the selected staging group.'
        txt2  = 'Refresh the queue and try again.'.
    RETURN.
  ENDIF.

  CLEAR lv_object_proof.
  IF ls_exec-run_status = GC_ST_PARTIAL AND
     ls_exec-message CP 'OBJECT_PROOF_REQUIRED*'.
    lv_object_proof = abap_true.
  ENDIF.

  PERFORM pick_protocol
    USING ls_stg ls_exec
    CHANGING lv_protocol.

 "Content-driven Error Detail presentation. Each logical item stays
 "on exactly one ALV row. Do not pre-wrap text at an arbitrary character
 "count; SALV sizes the column from the real content and provides horizontal
 "scrolling when a value is wider than the visible popup.
  DEFINE add_card.
    CLEAR ls_card.
    ls_card-section = &1.
    ls_card-detail  = &2.
    APPEND ls_card TO lt_card.
  END-OF-DEFINITION.

  DEFINE add_long_card.
    CLEAR ls_card.
    ls_card-section = &1.
    ls_card-detail  = &2.
    APPEND ls_card TO lt_card.
  END-OF-DEFINITION.

 "Keep the terminal SUCCESS/PROCESSED evidence view backward-compatible.
 "only redesigns issue states into a context-aware evidence card.
  IF ls_exec-run_status = GC_ST_SUCCESS OR
     ls_exec-run_status = GC_ST_PROCESSED.

    CONCATENATE ls_exec-run_status '-' ls_exec-health_text INTO lv_detail
      SEPARATED BY space.
    add_card '1. EXECUTION STATE' ''.
    add_card 'Status' lv_detail.
    lv_detail = |{ ls_stg-record_key } ({ ls_stg-tcode })|.
    add_card 'Business Group' lv_detail.

    add_card '2. EXACT SAP EVIDENCE' ''.
    add_long_card 'Exact SAP Message' lv_protocol.
    IF ls_exec-message IS NOT INITIAL AND ls_exec-message <> lv_protocol.
      add_long_card 'Engine Detail' ls_exec-message.
    ENDIF.

    add_card '3. TRACE' ''.
    IF ls_exec-attempt > 0.
      lv_detail = |Attempt { ls_exec-attempt }|.
      add_card 'Attempt' lv_detail.
    ENDIF.
    IF ls_exec-source_file IS NOT INITIAL.
      add_long_card 'Source File' ls_exec-source_file.
    ENDIF.
    add_card 'Session ID' ls_stg-session_id.

  ELSE.
 "one generic, context-aware issue renderer for CT, BISM/SM35,
 "validation/mapping and previously unseen captured errors. The UI never
 "invents missing fields: available evidence is shown; unavailable rows are
 "simply omitted. Raw captured issue evidence is retained as a catch-all.
    REFRESH: lt_issue_res, lt_seen_raw.
    CLEAR: ls_exact_issue, lv_executor, lv_user_msg, lv_protocol_norm,
           lv_technical_result, lv_subrc_text, lv_validation_stage,
           lv_screen_text, lv_affected_input, lv_input_row_text,
           lv_sm35_group, lv_sm35_qid, lv_tidx, lv_tcnt,
           ls_group_786, lv_raw_count.

    IF ls_stg-record_key IS NOT INITIAL.
      SELECT *
        FROM zbdc_result_bup
        INTO TABLE @lt_issue_res
        WHERE session_id = @ls_stg-session_id
          AND record_key = @ls_stg-record_key.
    ELSE.
      SELECT *
        FROM zbdc_result_bup
        INTO TABLE @lt_issue_res
        WHERE session_id = @ls_stg-session_id
          AND row_index  = @ls_stg-row_index.
    ENDIF.
    SORT lt_issue_res BY step DESCENDING.

    PERFORM resolve_executor
      USING    lt_issue_res
      CHANGING lv_executor.

 "For OBJECT_PROOF_REQUIRED the business transaction already returned an
 "exact SAP success message. Prefer that application S row over the later
 "synthetic proof-gate row, so Message Type/Screen stay truthful.
    IF lv_object_proof = abap_true.
      LOOP AT lt_issue_res INTO ls_issue_res
        WHERE msg_type = 'S'.
        IF ls_issue_res-message = lv_protocol AND
           ls_issue_res-field_name <> 'ENGINE' AND
           ls_issue_res-field_name <> 'DB_PROOF' AND
           ls_issue_res-field_name <> 'SAP_PROTO_PROOF' AND
           ls_issue_res-field_name <> 'SM35_BIND' AND
           ls_issue_res-field_name <> 'SM35_PREOBJ' AND
           ls_issue_res-field_name <> 'SM35_PRESET' AND
           ls_issue_res-field_name <> 'Z264_MARK' AND
           ls_issue_res-field_name <> 'STAGING' AND
           ls_issue_res-field_name <> 'OBJ_RESOLVE'.
          ls_exact_issue = ls_issue_res.
          EXIT.
        ENDIF.
      ENDLOOP.
    ENDIF.

 "Prefer the structured result row that produced the exact displayed
 "protocol, so Message Type/Screen/Field belong to the same evidence.
    IF ls_exact_issue-message IS INITIAL.
      LOOP AT lt_issue_res INTO ls_issue_res.
      IF ls_issue_res-message = lv_protocol AND
         ( ls_issue_res-msg_type = 'E' OR
           ls_issue_res-msg_type = 'A' OR
           ls_issue_res-msg_type = 'X' OR
           ls_issue_res-msg_type = 'W' OR
           ls_issue_res-exec_status = 'ERROR' OR
           ls_issue_res-exec_status = 'WARNING' OR
           ls_issue_res-exec_status = 'PARTIAL' ).
        ls_exact_issue = ls_issue_res.
        EXIT.
      ENDIF.
      ENDLOOP.
    ENDIF.

    IF ls_exact_issue-message IS INITIAL.
      LOOP AT lt_issue_res INTO ls_issue_res.
        IF ls_issue_res-message IS INITIAL.
          CONTINUE.
        ENDIF.
        IF ls_issue_res-msg_type = 'E' OR
           ls_issue_res-msg_type = 'A' OR
           ls_issue_res-msg_type = 'X' OR
           ( ls_exec-run_status = GC_ST_WARNING AND ls_issue_res-msg_type = 'W' ) OR
           ls_issue_res-exec_status = 'ERROR' OR
           ls_issue_res-exec_status = 'WARNING' OR
           ls_issue_res-exec_status = 'PARTIAL'.
          ls_exact_issue = ls_issue_res.
          EXIT.
        ENDIF.
      ENDLOOP.
    ENDIF.

 "Friendly user message is derived only from the exact captured text.
 "No business-field meaning is inferred here.
    lv_user_msg = lv_protocol.
    IF lv_protocol CS 'STAGING_VALIDATION:'.
      lv_validation_stage = 'Staging Validation'.
      REPLACE FIRST OCCURRENCE OF 'STAGING_VALIDATION:'
        IN lv_user_msg WITH ''.
      CONDENSE lv_user_msg.
      IF lv_executor = 'UNKNOWN'.
        lv_executor = 'VALIDATION'.
      ENDIF.
    ELSE.
      FIND FIRST OCCURRENCE OF 'SY-SUBRC=' IN lv_protocol
        MATCH OFFSET lv_off.
      IF sy-subrc = 0.
        FIND FIRST OCCURRENCE OF ':' IN lv_protocol
          MATCH OFFSET lv_colon.
        IF sy-subrc = 0 AND lv_colon > lv_off.
          lv_start = lv_off + 9.
          lv_sub_len = lv_colon - lv_start.
          IF lv_sub_len > 0.
            lv_subrc_text = lv_protocol+lv_start(lv_sub_len).
            CONDENSE lv_subrc_text.
          ENDIF.

          FIND FIRST OCCURRENCE OF ',' IN lv_protocol
            MATCH OFFSET lv_comma.
          IF sy-subrc = 0 AND lv_comma > 0 AND lv_comma < lv_off.
            lv_technical_result = lv_protocol(lv_comma).
          ELSEIF lv_off > 0.
            lv_technical_result = lv_protocol(lv_off).
          ENDIF.
          CONDENSE lv_technical_result.

          lv_start = lv_colon + 1.
          lv_user_msg = lv_protocol+lv_start.
          CONDENSE lv_user_msg.
        ENDIF.
      ENDIF.
    ENDIF.

    IF lv_user_msg IS INITIAL.
      lv_user_msg = lv_protocol.
    ENDIF.

 "compare a normalized copy only for duplicate suppression.
 "The exact protocol itself remains unchanged for evidence display.
    lv_protocol_norm = lv_protocol.
    CONDENSE lv_protocol_norm.

 "Only expose a result FIELD_NAME as affected input when it is an actual
 "captured application field, not one of this program's synthetic markers.
    IF ls_exact_issue-field_name IS NOT INITIAL.
      CLEAR lv_is_internal.
      CASE ls_exact_issue-field_name.
        WHEN 'ENGINE' OR 'DB_PROOF' OR 'SAP_PROTO_PROOF' OR
             'SM35_BIND' OR 'SM35' OR 'SM35_PREOBJ' OR 'SM35_PRESET' OR
             'Z264_MARK' OR 'STAGING' OR 'OBJ_RESOLVE'.
          lv_is_internal = abap_true.
      ENDCASE.
      IF lv_is_internal <> abap_true.
        lv_affected_input = ls_exact_issue-field_name.
      ENDIF.
    ENDIF.

    IF ls_exact_issue-dynpro IS NOT INITIAL.
      lv_screen_text = ls_exact_issue-dynpro.
    ENDIF.
    IF ls_exact_issue-row_index IS NOT INITIAL.
      lv_input_row_text = |Row { ls_exact_issue-row_index }|.
    ENDIF.

    IF lv_executor = 'BISM'.
      ls_group_786-session_id = ls_stg-session_id.
      ls_group_786-record_key = ls_stg-record_key.
      ls_group_786-row_index  = ls_stg-row_index.
      ls_group_786-group_key  = ls_stg-record_key.
      ls_group_786-tcode      = ls_stg-tcode.
      ls_group_786-executor   = 'BISM'.
      ls_group_786-lifecycle  = ls_exec-run_status.
      ls_group_786-attempt    = ls_exec-attempt.
      PERFORM resolve_sm35_audit
        USING    ls_group_786 lt_issue_res
        CHANGING lv_sm35_group lv_sm35_qid lv_tidx lv_tcnt.
    ENDIF.

 "1. ISSUE / PROOF STATE.
    add_card '1. ISSUE' ''.
    IF lv_object_proof = abap_true.
      lv_detail = 'PARTIAL - SAP success; object proof pending'.
    ELSE.
      CONCATENATE ls_exec-run_status '-' ls_exec-health_text INTO lv_detail
        SEPARATED BY space.
    ENDIF.
    add_card 'Status' lv_detail.
    add_card 'Business Group' ls_stg-record_key.
    add_card 'TCode' ls_stg-tcode.
    IF lv_user_msg IS NOT INITIAL AND lv_user_msg <> lv_protocol_norm.
      add_long_card 'User Message' lv_user_msg.
    ENDIF.

 "2. EXACT EVIDENCE - keep SAP success distinct from the Z proof gate.
    IF lv_object_proof = abap_true.
      add_card '2. SAP SUCCESS / OBJECT PROOF' ''.
      add_long_card 'SAP Success Message' lv_protocol.
      add_card 'Proof State' 'Object identity not yet certified'.
    ELSE.
      add_card '2. SAP / VALIDATION EVIDENCE' ''.
      add_long_card 'Exact Message' lv_protocol.
    ENDIF.
    CLEAR: lv_result_msgid, lv_result_msgnr, lv_result_prog.
    PERFORM get_optional_comp USING ls_exact_issue 'MSGID' CHANGING lv_result_msgid.
    IF lv_result_msgid IS INITIAL.
      PERFORM get_optional_comp USING ls_exact_issue 'MSG_ID' CHANGING lv_result_msgid.
    ENDIF.
    PERFORM get_optional_comp USING ls_exact_issue 'MSGNR' CHANGING lv_result_msgnr.
    IF lv_result_msgnr IS INITIAL.
      PERFORM get_optional_comp USING ls_exact_issue 'MSG_NUMBER' CHANGING lv_result_msgnr.
    ENDIF.
    PERFORM get_optional_comp USING ls_exact_issue 'PROGRAM_NAME' CHANGING lv_result_prog.
    IF lv_result_prog IS INITIAL.
      PERFORM get_optional_comp USING ls_exact_issue 'DYNAME' CHANGING lv_result_prog.
    ENDIF.

    IF ls_exact_issue-msg_type IS NOT INITIAL.
      add_card 'Message Type' ls_exact_issue-msg_type.
    ENDIF.
    IF lv_result_msgid IS NOT INITIAL OR
       lv_result_msgnr IS NOT INITIAL.
      lv_detail = |{ lv_result_msgid } / { lv_result_msgnr }|.
      add_card 'Message ID / No' lv_detail.
    ENDIF.
    IF lv_result_prog IS NOT INITIAL.
      add_card 'Program' lv_result_prog.
    ENDIF.
    IF lv_screen_text IS NOT INITIAL.
      add_card 'Dynpro' lv_screen_text.
    ENDIF.
    IF lv_validation_stage IS NOT INITIAL.
      add_card 'Validation Stage' lv_validation_stage.
    ENDIF.

 "3. EXECUTION CONTEXT - CT and BISM expose different exact context.
    add_card '3. EXECUTION CONTEXT' ''.
    IF lv_executor IS NOT INITIAL AND lv_executor <> 'UNKNOWN'.
      add_card 'Execution Method' lv_executor.
    ENDIF.
    IF lv_technical_result IS NOT INITIAL.
      add_card 'Technical Result' lv_technical_result.
    ENDIF.
    IF lv_subrc_text IS NOT INITIAL.
      add_card 'SY-SUBRC' lv_subrc_text.
    ENDIF.
    IF ls_exec-attempt > 0.
      lv_detail = |Attempt { ls_exec-attempt }|.
      add_card 'Attempt' lv_detail.
    ENDIF.
    IF lv_sm35_group IS NOT INITIAL OR lv_sm35_qid IS NOT INITIAL.
      CLEAR lv_detail.
      IF lv_sm35_group IS NOT INITIAL AND lv_sm35_qid IS NOT INITIAL.
        lv_detail = |{ lv_sm35_group } / { lv_sm35_qid }|.
      ELSEIF lv_sm35_group IS NOT INITIAL.
        lv_detail = lv_sm35_group.
      ELSE.
        lv_detail = lv_sm35_qid.
      ENDIF.
      add_long_card 'SM35 Session / QID' lv_detail.
    ENDIF.
    IF lv_tidx > 0.
      IF lv_tcnt > 0.
        lv_detail = |{ lv_tidx } of { lv_tcnt }|.
      ELSE.
        lv_detail = |{ lv_tidx }|.
      ENDIF.
      add_card 'Transaction Index' lv_detail.
    ENDIF.

 "4. INPUT CONTEXT - exact source references only; no AI inference.
    add_card '4. INPUT CONTEXT' ''.
    IF lv_affected_input IS NOT INITIAL.
      IF lv_validation_stage IS NOT INITIAL.
 "Validation-stage FIELD_NAME is an input-side evidence field.
        add_card 'Affected Input' lv_affected_input.
      ELSE.
 "Runtime FIELD_NAME is SAP/BDC technical evidence unless an exact
 "source mapping is separately proven; never present it as a user field.
        add_card 'Affected Technical Field' lv_affected_input.
      ENDIF.
    ENDIF.
    IF lv_input_row_text IS NOT INITIAL.
      add_card 'Input Row' lv_input_row_text.
    ENDIF.
    IF ls_exec-source_file IS NOT INITIAL.
      add_long_card 'Source File' ls_exec-source_file.
    ENDIF.
    IF ls_stg-session_id IS NOT INITIAL.
      add_card 'Session ID' ls_stg-session_id.
    ENDIF.

 "5. ADDITIONAL RAW EVIDENCE - catch-all for captured evidence that was
 "not already shown as Exact Message. Seed the de-dup set with the exact
 "protocol but do not display it twice.
    add_card '5. ADDITIONAL RAW EVIDENCE' ''.
    IF lv_protocol IS NOT INITIAL.
      INSERT lv_protocol INTO TABLE lt_seen_raw.
    ENDIF.

    LOOP AT lt_issue_res INTO ls_issue_res.
      IF ls_issue_res-message IS INITIAL.
        CONTINUE.
      ENDIF.
      IF ls_issue_res-msg_type = 'E' OR
         ls_issue_res-msg_type = 'A' OR
         ls_issue_res-msg_type = 'X' OR
         ls_issue_res-msg_type = 'W' OR
         ls_issue_res-exec_status = 'ERROR' OR
         ls_issue_res-exec_status = 'WARNING' OR
         ls_issue_res-exec_status = 'PARTIAL'.
 "Captured issue evidence - keep it below.
      ELSE.
        CONTINUE.
      ENDIF.

      READ TABLE lt_seen_raw TRANSPORTING NO FIELDS
        WITH TABLE KEY table_line = ls_issue_res-message.
      IF sy-subrc = 0.
        CONTINUE.
      ENDIF.
      INSERT ls_issue_res-message INTO TABLE lt_seen_raw.

      CLEAR: lv_raw_line, lv_is_internal.
      IF ls_issue_res-field_name IS NOT INITIAL.
        CASE ls_issue_res-field_name.
          WHEN 'ENGINE' OR 'DB_PROOF' OR 'SAP_PROTO_PROOF' OR
               'SM35_BIND' OR 'SM35' OR 'SM35_PREOBJ' OR 'SM35_PRESET' OR
               'Z264_MARK' OR 'STAGING' OR 'OBJ_RESOLVE'.
            lv_is_internal = abap_true.
        ENDCASE.
      ENDIF.

      IF lv_object_proof = abap_true AND
         ls_issue_res-field_name = 'ENGINE' AND
         ls_issue_res-message CP 'OBJECT_PROOF_REQUIRED*'.
        lv_raw_line = 'Proof Gate '.
      ELSE.
        IF ls_issue_res-msg_type IS NOT INITIAL.
          lv_raw_line = |[{ ls_issue_res-msg_type }] |.
        ENDIF.
        IF ls_issue_res-dynpro IS NOT INITIAL AND
           lv_is_internal <> abap_true.
          lv_raw_line = |{ lv_raw_line }Screen { ls_issue_res-dynpro } |.
        ENDIF.
        IF ls_issue_res-field_name IS NOT INITIAL AND
           lv_is_internal <> abap_true.
          lv_raw_line = |{ lv_raw_line }Field { ls_issue_res-field_name } |.
        ENDIF.
      ENDIF.
      IF lv_raw_line IS NOT INITIAL.
        lv_raw_line = |{ lv_raw_line }- { ls_issue_res-message }|.
      ELSE.
        lv_raw_line = ls_issue_res-message.
      ENDIF.

      lv_raw_count = lv_raw_count + 1.
      lv_raw_label = |Evidence { lv_raw_count }|.
      add_long_card lv_raw_label lv_raw_line.
    ENDLOOP.

    IF ls_stg-error_msg IS NOT INITIAL.
      READ TABLE lt_seen_raw TRANSPORTING NO FIELDS
        WITH TABLE KEY table_line = ls_stg-error_msg.
      IF sy-subrc <> 0.
        INSERT ls_stg-error_msg INTO TABLE lt_seen_raw.
        add_long_card 'Staging Evidence' ls_stg-error_msg.
      ENDIF.
    ENDIF.

    IF ls_stg-last_error IS NOT INITIAL.
      READ TABLE lt_seen_raw TRANSPORTING NO FIELDS
        WITH TABLE KEY table_line = ls_stg-last_error.
      IF sy-subrc <> 0.
        INSERT ls_stg-last_error INTO TABLE lt_seen_raw.
        add_long_card 'Last Error' ls_stg-last_error.
      ENDIF.
    ENDIF.

    IF ls_exec-message IS NOT INITIAL.
      READ TABLE lt_seen_raw TRANSPORTING NO FIELDS
        WITH TABLE KEY table_line = ls_exec-message.
      IF sy-subrc <> 0.
        INSERT ls_exec-message INTO TABLE lt_seen_raw.
        add_long_card 'Engine Evidence' ls_exec-message.
      ENDIF.
    ENDIF.

 "6. NEXT STEP - proof-gate PARTIAL is not a data error and must never
 "recommend replay. Other issue states keep the normal Fix Guide path.
    add_card '6. NEXT STEP' ''.
    IF lv_object_proof = abap_true.
      lv_detail = |Open AI Navigation for { ls_stg-record_key }, verify the real SAP landing, then choose Certify.|.
      add_card 'Action' lv_detail.
      add_card 'Retry'
        'DO NOT RETRY: SAP already returned success; replay could create a duplicate business object.'.
    ELSE.
      lv_detail = |Open Fix Guide for { ls_stg-record_key } for evidence-grounded diagnosis and correction steps.|.
      add_card 'Action' lv_detail.
    ENDIF.
  ENDIF.

  IF ls_exec-run_status = GC_ST_SUCCESS OR
     ls_exec-run_status = GC_ST_PROCESSED.
    lv_header = 'Execution Evidence Detail - selected group'.
  ELSEIF lv_object_proof = abap_true.
    lv_header = 'Execution Proof Required - selected group'.
  ELSE.
    lv_header = 'Runtime Issue Detail - selected group'.
  ENDIF.

 "primary surface: true long-text rendering. Classic SALV remains a
 "fallback only if the frontend HTML control cannot be created.
  CLEAR lv_html_ok.
  PERFORM show_long_cards USING lt_card lv_header CHANGING lv_html_ok.
  IF lv_html_ok = abap_true.
    RETURN.
  ENDIF.

  TRY.
      cl_salv_table=>factory(
        IMPORTING r_salv_table = lo_alv
        CHANGING  t_table      = lt_card ).
      lo_alv->get_display_settings( )->set_list_header( lv_header ).
      lo_alv->get_functions( )->set_all( abap_true ).
      lo_cols = lo_alv->get_columns( ).
 "no fixed content width. SALV optimizes from the actual rows.
      lo_cols->set_optimize( abap_true ).
      PERFORM set_salv_col_text USING lo_cols 'SECTION'
        'Section' 'Section' 'Section'.
      PERFORM set_salv_col_text USING lo_cols 'DETAIL'
        'Detail' 'Detail' 'Detail / Explanation'.
      CALL METHOD lo_alv->set_screen_popup
        EXPORTING
          start_column = 2
          end_column   = 170
          start_line   = 2
          end_line     = 30.
      lo_alv->display( ).
    CATCH cx_salv_msg INTO lx_salv.
      MESSAGE lx_salv->get_text( ) TYPE 'S' DISPLAY LIKE 'E'.
  ENDTRY.
ENDFORM.

*& Exact Fix Guide input evidence resolver
*& ---------------------------------------------------------------
*& Resolve only facts that are provable from the frozen session/profile,
*& Mapping Profile, the exact staging row and SAP DDIC. No TCODE CASE and
*& no business meaning/value is guessed from field names.
FORM resolve_fixguide_input_evid
  USING    is_stg              TYPE ty_staging_alv
           iv_technical_field  TYPE any
  CHANGING cv_input_row        TYPE i
           cv_source_column    TYPE string
           cv_staging_field    TYPE string
           cv_current_value    TYPE string
           cv_ddic_label       TYPE string
           cv_ddic_rule        TYPE string
           cv_ddic_datatype    TYPE string
           cv_ddic_length      TYPE i
           cv_ddic_convexit    TYPE string
           cv_ddic_domain      TYPE string
           cv_ddic_checktable  TYPE string
           cv_fixed_values     TYPE string
           cv_validation_evid  TYPE string
           cv_mandatory        TYPE c
           cv_mapping_proven   TYPE abap_bool.

  DATA: ls_session       TYPE zbdc_session_bup,
        lt_map           TYPE STANDARD TABLE OF zbdc_mapping_bup,
        ls_map           TYPE zbdc_mapping_bup,
        ls_match         TYPE zbdc_mapping_bup,
        lt_res           TYPE STANDARD TABLE OF zbdc_result_bup,
        ls_res           TYPE zbdc_result_bup,
        ls_value_stg     TYPE ty_staging_alv,
        lv_target_bdc    TYPE zbdc_mapping_bup-bdc_field,
        lv_map_bdc       TYPE zbdc_mapping_bup-bdc_field,
        lv_target_plain  TYPE string,
        lv_source_plain  TYPE string,
        lv_stage_plain   TYPE string,
        lv_match_kind    TYPE c LENGTH 1,
        lv_ambiguous     TYPE abap_bool,
        lv_ddic_bdc      TYPE zbdc_mapping_bup-bdc_field,
        lv_ddic_found    TYPE abap_bool,
        lv_left          TYPE string,
        lv_right         TYPE string,
        lv_dummy         TYPE string,
        lv_tab           TYPE tabname,
        lv_field         TYPE fieldname,
        lt_dfies         TYPE STANDARD TABLE OF dfies,
        ls_dfies         TYPE dfies,
        lt_dom           TYPE STANDARD TABLE OF dd07l,
        ls_dom           TYPE dd07l,
        lv_values        TYPE string,
        lv_token         TYPE string,
        lv_count         TYPE i.
  FIELD-SYMBOLS <lv_any> TYPE any.

  CLEAR: cv_input_row, cv_source_column, cv_staging_field,
         cv_current_value, cv_ddic_label, cv_ddic_rule,
         cv_ddic_datatype, cv_ddic_length, cv_ddic_convexit,
         cv_ddic_domain, cv_ddic_checktable, cv_fixed_values,
         cv_validation_evid, cv_mandatory, cv_mapping_proven.

  PERFORM normalize_mapping_bdc_field
    USING    iv_technical_field
    CHANGING lv_target_bdc.
  IF lv_target_bdc IS INITIAL.
    RETURN.
  ENDIF.

 "Find the exact error row that carried this technical field. This is
 "important for multi-row groups: the selected cockpit row may be only the
 "canonical group row, not the row whose uploaded value SAP rejected.
  SELECT *
    FROM zbdc_result_bup
    INTO TABLE @lt_res
    WHERE session_id = @is_stg-session_id
      AND record_key = @is_stg-record_key.
  SORT lt_res BY step DESCENDING.
  LOOP AT lt_res INTO ls_res.
    IF ls_res-field_name IS INITIAL.
      CONTINUE.
    ENDIF.
    CLEAR lv_map_bdc.
    PERFORM normalize_mapping_bdc_field
      USING    ls_res-field_name
      CHANGING lv_map_bdc.
    IF lv_map_bdc = lv_target_bdc AND
       ( ls_res-msg_type = 'E' OR ls_res-msg_type = 'A' OR
         ls_res-msg_type = 'X' OR ls_res-msg_type = 'W' OR
         ls_res-exec_status = 'ERROR' OR
         ls_res-exec_status = 'WARNING' OR
         ls_res-exec_status = 'PARTIAL' ).
      cv_input_row = ls_res-row_index.
      EXIT.
    ENDIF.
  ENDLOOP.
  IF cv_input_row IS INITIAL.
    cv_input_row = is_stg-row_index.
  ENDIF.

  ls_value_stg = is_stg.
  READ TABLE gt_staging_alv INTO ls_value_stg
    WITH KEY session_id = is_stg-session_id
             row_index  = cv_input_row.
  IF sy-subrc <> 0.
    ls_value_stg = is_stg.
  ENDIF.

 "Frozen session context is the authority for profile/version. Never use a
 "different active UI profile to explain an older execution result.
  SELECT SINGLE profile_name, profile_ver
    FROM zbdc_session_bup
    INTO CORRESPONDING FIELDS OF @ls_session
    WHERE session_id = @is_stg-session_id.

  IF sy-subrc = 0 AND
     ls_session-profile_name IS NOT INITIAL AND
     ls_session-profile_ver  IS NOT INITIAL.
    SELECT *
      FROM zbdc_mapping_bup
      INTO TABLE @lt_map
      WHERE tcode        = @is_stg-tcode
        AND profile_name = @ls_session-profile_name
        AND profile_ver  = @ls_session-profile_ver.
  ENDIF.

 "First preference: exact normalized BDC technical field identity.
  LOOP AT lt_map INTO ls_map.
    CLEAR lv_map_bdc.
    PERFORM normalize_mapping_bdc_field
      USING    ls_map-bdc_field
      CHANGING lv_map_bdc.
    IF lv_map_bdc <> lv_target_bdc.
      CONTINUE.
    ENDIF.
    IF ls_match-bdc_field IS INITIAL.
      ls_match = ls_map.
      lv_match_kind = 'B'.
    ELSEIF ls_match-source_column <> ls_map-source_column OR
           ls_match-staging_field <> ls_map-staging_field.
      lv_ambiguous = abap_true.
    ENDIF.
  ENDLOOP.

 "Validation rows can carry an exact staging/source token rather than a BDC
 "field. Match it only by literal registry identity; no lexical inference.
  IF ls_match-bdc_field IS INITIAL AND lv_ambiguous <> abap_true.
    lv_target_plain = iv_technical_field.
    TRANSLATE lv_target_plain TO UPPER CASE.
    CONDENSE lv_target_plain NO-GAPS.
    LOOP AT lt_map INTO ls_map.
      lv_source_plain = ls_map-source_column.
      lv_stage_plain  = ls_map-staging_field.
      TRANSLATE: lv_source_plain TO UPPER CASE,
                 lv_stage_plain  TO UPPER CASE.
      CONDENSE: lv_source_plain NO-GAPS,
                lv_stage_plain  NO-GAPS.
      IF lv_target_plain = lv_source_plain OR
         lv_target_plain = lv_stage_plain.
        IF ls_match-bdc_field IS INITIAL.
          ls_match = ls_map.
          lv_match_kind = 'S'.
        ELSEIF ls_match-source_column <> ls_map-source_column OR
               ls_match-staging_field <> ls_map-staging_field OR
               ls_match-bdc_field     <> ls_map-bdc_field.
          lv_ambiguous = abap_true.
        ENDIF.
      ENDIF.
    ENDLOOP.
  ENDIF.

  IF lv_ambiguous <> abap_true AND ls_match-bdc_field IS NOT INITIAL.
    cv_mapping_proven = abap_true.
    cv_source_column  = ls_match-source_column.
    cv_staging_field  = ls_match-staging_field.
    cv_mandatory      = ls_match-mandatory.

    IF cv_staging_field IS NOT INITIAL.
      ASSIGN COMPONENT cv_staging_field OF STRUCTURE ls_value_stg TO <lv_any>.
      IF sy-subrc = 0.
        cv_current_value = |{ <lv_any> }|.
      ENDIF.
    ENDIF.
  ENDIF.

 "Validation evidence belongs to the exact row only. It is context for the
 "guide, never promoted to a SAP runtime message.
  IF ls_value_stg-error_msg IS NOT INITIAL.
    cv_validation_evid = ls_value_stg-error_msg.
  ELSEIF ls_value_stg-last_error IS NOT INITIAL.
    cv_validation_evid = ls_value_stg-last_error.
  ENDIF.

 "DDIC evidence can still be resolved from the exact technical field even
 "when source mapping is unavailable. Mapping identity is preferred because
 "it preserves the same normalized field used by the runtime builder.
  IF cv_mapping_proven = abap_true.
    lv_ddic_bdc = ls_match-bdc_field.
  ELSE.
    lv_ddic_bdc = lv_target_bdc.
  ENDIF.

  PERFORM get_mapping_ddic_help
    USING    lv_ddic_bdc
    CHANGING cv_ddic_label cv_ddic_rule.
  PERFORM get_ddic_runtime_traits
    USING    lv_ddic_bdc
    CHANGING cv_ddic_datatype cv_ddic_length
             cv_ddic_convexit lv_ddic_found.

 "Expose domain/check-table metadata and domain fixed values only when SAP
 "DDIC proves them. A check table name is context, not proof of a replacement
 "value; no value is read or invented from it here.
  CLEAR lv_map_bdc.
  PERFORM normalize_mapping_bdc_field
    USING    lv_ddic_bdc
    CHANGING lv_map_bdc.
  IF lv_map_bdc CS '-'.
    REPLACE ALL OCCURRENCES OF '(*)' IN lv_map_bdc WITH ''.
    IF lv_map_bdc CS '('.
      SPLIT lv_map_bdc AT '(' INTO lv_map_bdc lv_dummy.
    ENDIF.
    SPLIT lv_map_bdc AT '-' INTO lv_left lv_right.
    lv_tab   = lv_left.
    lv_field = lv_right.
    IF lv_tab IS NOT INITIAL AND lv_field IS NOT INITIAL.
      CALL FUNCTION 'DDIF_FIELDINFO_GET'
        EXPORTING
          tabname        = lv_tab
          langu          = sy-langu
          all_types      = abap_true
        TABLES
          dfies_tab      = lt_dfies
        EXCEPTIONS
          not_found      = 1
          internal_error = 2
          OTHERS         = 3.
      IF sy-subrc = 0.
        READ TABLE lt_dfies INTO ls_dfies WITH KEY fieldname = lv_field.
        IF sy-subrc = 0.
          cv_ddic_domain     = ls_dfies-domname.
          cv_ddic_checktable = ls_dfies-checktable.
        ENDIF.
      ENDIF.
    ENDIF.
  ENDIF.

  IF cv_ddic_domain IS NOT INITIAL.
    SELECT *
      FROM dd07l
      INTO TABLE @lt_dom
      WHERE domname  = @cv_ddic_domain
        AND as4local = 'A'
        AND as4vers  = '0000'.
    SORT lt_dom BY valpos.
    LOOP AT lt_dom INTO ls_dom.
      IF ls_dom-domvalue_l IS INITIAL AND ls_dom-domvalue_h IS INITIAL.
        CONTINUE.
      ENDIF.
      CLEAR lv_token.
      IF ls_dom-domvalue_h IS INITIAL OR
         ls_dom-domvalue_h = ls_dom-domvalue_l.
        lv_token = ls_dom-domvalue_l.
      ELSE.
        lv_token = |{ ls_dom-domvalue_l }..{ ls_dom-domvalue_h }|.
      ENDIF.
      CONDENSE lv_token.
      IF lv_token IS INITIAL.
        CONTINUE.
      ENDIF.
      lv_count = lv_count + 1.
      IF lv_values IS INITIAL.
        lv_values = lv_token.
      ELSE.
        lv_values = |{ lv_values }, { lv_token }|.
      ENDIF.
      IF lv_count >= 12 OR strlen( lv_values ) > 220.
        EXIT.
      ENDIF.
    ENDLOOP.
    cv_fixed_values = lv_values.
  ENDIF.

ENDFORM.

FORM get_group_ai_advice
  USING    is_stg       TYPE ty_staging_alv
           iv_protocol  TYPE char255
  CHANGING cv_source       TYPE char40
           cv_ai_cause     TYPE char255
           cv_ai_action    TYPE char255
           cv_ground_field TYPE char80
           cv_ai_ok        TYPE abap_bool.

  DATA: lt_exact            TYPE STANDARD TABLE OF zbdc_result_bup,
        lt_saved_patterns   TYPE STANDARD TABLE OF ty_ai_pattern,
        ls_pat              TYPE ty_ai_pattern,
        lv_lines            TYPE string,
        lv_prompt           TYPE string,
        lv_endpoint         TYPE string,
        lv_resp             TYPE string,
        lv_parse_shape      TYPE char30,
        lv_call_ok          TYPE abap_bool,
        lv_ai_attempt       TYPE i,
        lv_ai_diag          TYPE string,
        lv_ai_transient     TYPE abap_bool,
        lv_fix_upper        TYPE string,
        lv_analysis_upper   TYPE string,
        lv_quality_bad      TYPE abap_bool,
        lv_refine_prompt    TYPE string,
        lv_refine_resp      TYPE string,
        lv_refine_shape     TYPE char30,
        lv_refine_ok        TYPE abap_bool,
        lv_refine_root      TYPE string,
        lv_refine_fix       TYPE string,
        lv_refine_quote     TYPE string,
        lv_refine_field     TYPE string,
        lv_refine_dynpro    TYPE string,
        lv_refine_upper     TYPE string,
        lv_refine_an_upper  TYPE string,
        lv_n                TYPE i,
        lv_root             TYPE string,
        lv_fix              TYPE string,
        lv_quote            TYPE string,
        lv_ref_field        TYPE string,
        lv_ref_dynpro       TYPE string,
        lv_quote_upper      TYPE string,
        lv_root_upper       TYPE string,
        lv_ref_field_upper  TYPE string,
        lv_ground_upper     TYPE string,
        lv_ref_dynpro_upper TYPE string,
        lv_evidence_upper   TYPE string,
        lv_anchor           TYPE string,
        lv_ground_field     TYPE char80,
        lv_field_multi      TYPE abap_bool,
        lv_saved_session    TYPE char30,
        lv_cache_key        TYPE char20,
        lv_cause_cap        TYPE i,
        lv_action_cap       TYPE i,
        lv_input_row        TYPE i,
        lv_source_column    TYPE string,
        lv_staging_field    TYPE string,
        lv_current_value    TYPE string,
        lv_ddic_label       TYPE string,
        lv_ddic_rule        TYPE string,
        lv_ddic_datatype    TYPE string,
        lv_ddic_length      TYPE i,
        lv_ddic_convexit    TYPE string,
        lv_ddic_domain      TYPE string,
        lv_ddic_checktable  TYPE string,
        lv_fixed_values     TYPE string,
        lv_validation_evid  TYPE string,
        lv_mandatory        TYPE c LENGTH 1,
        lv_mapping_proven   TYPE abap_bool,
        lv_source_upper     TYPE string.

  CLEAR: cv_source, cv_ai_cause, cv_ai_action, cv_ground_field, cv_ai_ok,
         lv_lines, lv_prompt, lv_endpoint, lv_resp, lv_parse_shape,
         lv_call_ok, lv_ai_attempt, lv_ai_diag, lv_ai_transient,
         lv_fix_upper, lv_analysis_upper, lv_quality_bad,
         lv_refine_prompt, lv_refine_resp, lv_refine_shape, lv_refine_ok,
         lv_refine_root, lv_refine_fix, lv_refine_quote,
         lv_refine_field, lv_refine_dynpro, lv_refine_upper,
         lv_refine_an_upper, lv_n, lv_root, lv_fix,
         lv_quote, lv_ref_field, lv_ref_dynpro, lv_quote_upper,
         lv_root_upper, lv_ref_field_upper, lv_ground_upper,
         lv_ref_dynpro_upper, lv_evidence_upper, lv_anchor,
         lv_ground_field, lv_field_multi, lv_input_row,
         lv_source_column, lv_staging_field, lv_current_value,
         lv_ddic_label, lv_ddic_rule, lv_ddic_datatype,
         lv_ddic_length, lv_ddic_convexit, lv_ddic_domain,
         lv_ddic_checktable, lv_fixed_values, lv_validation_evid,
         lv_mandatory, lv_mapping_proven, lv_source_upper.

 "derive text capacity from the real ABAP destination fields.
 "There is no UI-specific 120/128 character contract anymore.
  DESCRIBE FIELD cv_ai_cause  LENGTH lv_cause_cap  IN CHARACTER MODE.
  DESCRIBE FIELD cv_ai_action LENGTH lv_action_cap IN CHARACTER MODE.

 "AI analyzes only the exact selected group. SAP evidence remains
 "authoritative; OpenAI is advisory and may not create new technical facts.
  SELECT *
    FROM zbdc_result_bup
    INTO TABLE @lt_exact
    WHERE session_id = @is_stg-session_id
      AND record_key = @is_stg-record_key
    ORDER BY row_index ASCENDING, step ASCENDING.

  LOOP AT lt_exact INTO DATA(ls_res)
       WHERE msg_type = 'E' OR msg_type = 'W'.
    ADD 1 TO lv_n.
    IF lv_n > 20.
      EXIT.
    ENDIF.

    IF ls_res-field_name IS NOT INITIAL.
      DATA(lv_internal_field) = abap_false.
      CASE ls_res-field_name.
        WHEN 'ENGINE' OR 'DB_PROOF' OR 'SAP_PROTO_PROOF' OR
             'SM35_BIND' OR 'SM35' OR 'SM35_PREOBJ' OR 'SM35_PRESET' OR
             'Z264_MARK' OR 'STAGING' OR 'OBJ_RESOLVE'.
          lv_internal_field = abap_true.
      ENDCASE.
      IF lv_internal_field <> abap_true.
        IF lv_ground_field IS INITIAL.
          lv_ground_field = ls_res-field_name.
        ELSEIF lv_ground_field <> ls_res-field_name.
          lv_field_multi = abap_true.
        ENDIF.
      ENDIF.
    ENDIF.

    lv_lines = lv_lines
      && |Row { ls_res-row_index } | &&
         |TCode { ls_res-tcode } | &&
         |Dynpro { ls_res-dynpro } | &&
         |Field { ls_res-field_name } | &&
         |MsgType { ls_res-msg_type } | &&
         |Msg: { ls_res-message }|
      && cl_abap_char_utilities=>newline.
  ENDLOOP.

  IF lv_field_multi = abap_true.
    CLEAR lv_ground_field.
  ENDIF.
  cv_ground_field = lv_ground_field.

 "Resolve the exact source-side input and DDIC facts before AI is called.
 "This turns Fix Guide from message-only advice into row/column/value advice
 "without allowing AI to guess a business field or replacement value.
  IF lv_ground_field IS NOT INITIAL.
    PERFORM resolve_fixguide_input_evid
      USING    is_stg lv_ground_field
      CHANGING lv_input_row lv_source_column lv_staging_field
               lv_current_value lv_ddic_label lv_ddic_rule
               lv_ddic_datatype lv_ddic_length lv_ddic_convexit
               lv_ddic_domain lv_ddic_checktable lv_fixed_values
               lv_validation_evid lv_mandatory lv_mapping_proven.

    IF lv_mapping_proven = abap_true.
      lv_lines = lv_lines
        && |PROVEN_INPUT_MAPPING Row={ lv_input_row } SourceColumn={ lv_source_column } |
        && |StagingField={ lv_staging_field } SAPField={ lv_ground_field } |
        && |CurrentValue="{ lv_current_value }" Mandatory={ lv_mandatory }|
        && cl_abap_char_utilities=>newline.
    ENDIF.
    IF lv_ddic_datatype IS NOT INITIAL OR lv_ddic_rule IS NOT INITIAL.
      lv_lines = lv_lines
        && |PROVEN_DDIC Label="{ lv_ddic_label }" Datatype={ lv_ddic_datatype } |
        && |Length={ lv_ddic_length } ConvExit={ lv_ddic_convexit } Domain={ lv_ddic_domain } |
        && |CheckTable={ lv_ddic_checktable } Rule="{ lv_ddic_rule }" |
        && |FixedDomainValues="{ lv_fixed_values }"|
        && cl_abap_char_utilities=>newline.
    ENDIF.
    IF lv_validation_evid IS NOT INITIAL.
      lv_lines = lv_lines
        && |VALIDATION_EVIDENCE "{ lv_validation_evid }"|
        && cl_abap_char_utilities=>newline.
    ENDIF.
  ENDIF.

  IF lv_lines IS INITIAL AND iv_protocol IS NOT INITIAL.
    lv_lines = |Row { is_stg-row_index } TCode { is_stg-tcode } Field <not-proven> Msg: { iv_protocol }|.
  ENDIF.
  IF lv_lines IS INITIAL.
    RETURN.
  ENDIF.

  PERFORM get_ai_endpoint CHANGING lv_endpoint.
  IF lv_endpoint IS INITIAL.
    RETURN.
  ENDIF.

 "Direct OpenAI contract. The model must separate exact evidence from its
 "interpretation and return one decisive correction plan without guessing.
  lv_prompt =
    |You are a senior SAP BDC support analyst writing for an SAP business user, not a developer. | &&
    |Analyze ONLY this exact selected group. Session={ is_stg-session_id }; Group={ is_stg-record_key }; TCode={ is_stg-tcode }. | &&
    |Use plain, decisive language that tells the user what SAP reported, what proven input is affected, | &&
    |what must be corrected, and what must be verified next. When PROVEN_INPUT_MAPPING is supplied, fix_action must name | &&
    |the exact Row and SourceColumn and may quote CurrentValue. When PROVEN_DDIC is supplied, use its rule/metadata as the | &&
    |technical constraint. FixedDomainValues are authoritative only when non-empty; never choose an intended replacement | &&
    |for the user unless the evidence proves one unique replacement. Do not use internal wording such as failed group, | &&
    |business group, selected group, this group, or protocol in user-facing analysis/action. If a group reference is | &&
    |needed, use the exact Group id shown above. The supplied SAP/runtime evidence is the only source of truth. | &&
    |Never invent a SAP field, table, dynpro, business meaning, master-data object, hidden root cause, | &&
    |configuration problem, replacement value, or success claim. | &&
    |An explicit SAP error is a confirmed fact. evidence_quote must copy this exact SAP protocol text: | &&
    |{ iv_protocol }. analysis must visibly include that exact quote and explain only the directly | &&
    |proven failure consequence in one concise sentence. Do not add a deeper cause | &&
    |unless the evidence explicitly proves it. fix_action must be 1-2 decisive imperative sentences | &&
    |that correct the proven problem, validate the corrected group, and state the safe next step. | &&
    |Do not use IF, MAY, MIGHT, COULD, POSSIBLY, PROBABLY, CONSIDER, or vague advice such as | &&
    |review/check the error, protocol, or source data. If SAP says a value already exists, direct | &&
    |changing only the affected proven input to the intended valid unused value; never invent that value. | &&
    |Never recommend changing unrelated data just to make the error disappear. | &&
    |evidence_quote MUST be a short exact verbatim substring copied from the supplied evidence. | &&
    |If analysis or fix_action names a technical field, put that exact token in referenced_field; | &&
    |otherwise leave referenced_field empty. Apply the same rule to referenced_dynpro. | &&
    |Return ONLY one raw JSON object with exactly these fields: "severity", "evidence_quote", | &&
    |"analysis", "referenced_field", "referenced_dynpro", "fix_action". | &&
    |Keep analysis and fix_action concise, complete, specific and user-facing. | &&
    |analysis must fit within { lv_cause_cap } characters and fix_action within { lv_action_cap } characters, | &&
    |because those are the actual SAP destination capacities. No markdown, no code fences. Evidence:| &&
    cl_abap_char_utilities=>newline && lv_lines.

  PERFORM call_ai_endpoint
    USING    'FIX' lv_endpoint lv_prompt
    CHANGING lv_resp lv_call_ok.

 "Retry only transient OpenAI/network failures. Total = 3 attempts.
 "No WAIT UP TO is used because this diagnostic path must not trigger an
 "implicit database commit while the user is only viewing a Fix Guide.
  lv_ai_attempt = 1.
  WHILE ( lv_call_ok <> abap_true OR lv_resp IS INITIAL )
        AND lv_ai_attempt < 3.
    lv_ai_diag = gv_z619_ai_http_diag.
    lv_ai_transient = abap_false.
    IF lv_ai_diag CS 'HTTP_429' OR
       lv_ai_diag CS 'HTTP_5' OR
       lv_ai_diag CS 'SEND_FAIL_OR_TIMEOUT' OR
       lv_ai_diag CS 'RECEIVE_FAIL'.
      lv_ai_transient = abap_true.
    ENDIF.
    IF lv_ai_transient <> abap_true.
      EXIT.
    ENDIF.
    lv_ai_attempt = lv_ai_attempt + 1.
    CLEAR: lv_resp, lv_call_ok.
    PERFORM call_ai_endpoint
      USING    'FIX' lv_endpoint lv_prompt
      CHANGING lv_resp lv_call_ok.
  ENDWHILE.

  IF lv_call_ok <> abap_true OR lv_resp IS INITIAL.
    IF gv_z619_ai_http_diag IS INITIAL.
      gv_z619_ai_http_diag = 'AI_CALL_NO_RESPONSE'.
    ENDIF.
    IF lv_ai_attempt > 1.
      gv_z619_ai_http_diag = |{ gv_z619_ai_http_diag };AUTO_ATTEMPTS={ lv_ai_attempt }|.
    ENDIF.
    RETURN.
  ENDIF.

  PERFORM parse_fixguide_ai_resp
    USING    lv_resp
    CHANGING lv_root
             lv_fix
             lv_quote
             lv_ref_field
             lv_ref_dynpro
             lv_parse_shape
             lv_call_ok.

  IF lv_call_ok <> abap_true OR lv_fix IS INITIAL OR lv_root IS INITIAL.
    gv_z619_ai_http_diag =
      |AI_PARSE_FAIL:NO_SAFE_ANALYSIS_OR_FIX;SHAPE={ lv_parse_shape }|.
    RETURN.
  ENDIF.

  CONDENSE: lv_root, lv_fix, lv_quote, lv_ref_field, lv_ref_dynpro.

 "Professional quality gate: reject conditional, vague or incomplete output.
  lv_fix_upper = lv_fix.
  lv_analysis_upper = lv_root.
  TRANSLATE lv_fix_upper TO UPPER CASE.
  TRANSLATE lv_analysis_upper TO UPPER CASE.
  CONCATENATE space lv_fix_upper space INTO lv_fix_upper.
  CONCATENATE space lv_analysis_upper space INTO lv_analysis_upper.
  lv_quality_bad = abap_false.

 "When exact mapping is proven, generic AI advice is not good enough. The
 "accepted action must name the real template/source column.
  IF lv_mapping_proven = abap_true AND lv_source_column IS NOT INITIAL.
    lv_source_upper = lv_source_column.
    TRANSLATE lv_source_upper TO UPPER CASE.
    IF lv_fix_upper NS lv_source_upper.
      lv_quality_bad = abap_true.
    ENDIF.
  ENDIF.

  IF strlen( lv_fix ) < 45 OR strlen( lv_root ) < 30 OR
     strlen( lv_fix ) > lv_action_cap OR strlen( lv_root ) > lv_cause_cap OR
     lv_fix_upper CS ' IF ' OR lv_fix_upper CS ' MAY ' OR
     lv_fix_upper CS ' MIGHT ' OR lv_fix_upper CS ' COULD ' OR
     lv_fix_upper CS ' POSSIBLY ' OR lv_fix_upper CS ' PROBABLY ' OR
     lv_fix_upper CS ' CONSIDER ' OR lv_fix_upper CS ' CHECK WHETHER ' OR
     lv_fix_upper CS ' VERIFY WHETHER ' OR
     lv_fix_upper CS ' FAILED GROUP ' OR
     lv_fix_upper CS ' BUSINESS GROUP ' OR
     lv_fix_upper CS ' SELECTED GROUP ' OR
     lv_fix_upper CS ' THIS GROUP ' OR
     lv_fix_upper CS ' PROTOCOL ' OR
     lv_fix_upper CS ' REVIEW THE SOURCE DATA ' OR
     lv_fix_upper CS ' REVIEW THE SAP ' OR
     lv_fix_upper CS ' REVIEW THE ERROR ' OR
     lv_fix_upper CS ' REVIEW THE PROTOCOL ' OR
     lv_fix_upper CS ' DO NOT INVENT ' OR
     lv_fix_upper CS ' DO NOT GUESS ' OR
     lv_analysis_upper CS ' MAY ' OR lv_analysis_upper CS ' MIGHT ' OR
     lv_analysis_upper CS ' COULD ' OR lv_analysis_upper CS ' POSSIBLY ' OR
     lv_analysis_upper CS ' PROBABLY ' OR lv_analysis_upper CS ' ASSUME ' OR
     lv_analysis_upper CS ' FAILED GROUP ' OR
     lv_analysis_upper CS ' BUSINESS GROUP ' OR
     lv_analysis_upper CS ' SELECTED GROUP ' OR
     lv_analysis_upper CS ' THIS GROUP ' OR
     lv_analysis_upper CS ' PROTOCOL '.
    lv_quality_bad = abap_true.
  ENDIF.

  IF lv_quality_bad = abap_true.
    lv_refine_prompt =
      |Rewrite one SAP BDC analysis and resolution for the SAP business user for this exact selected group. | &&
      |Previous analysis: { lv_root }. Previous action: { lv_fix }. Use ONLY the evidence below. | &&
      |Use plain decisive language and do not say failed group, business group, selected group, this group, or protocol. | &&
      |If a group reference is needed, use the exact Group id. Keep the SAP error as | &&
      |a confirmed fact. evidence_quote must copy this exact SAP protocol text: { iv_protocol }. | &&
      |analysis must visibly include that exact quote and must not invent a hidden cause. | &&
      |fix_action must be 1-2 decisive imperative sentences that correct only the proven | &&
      |problem, validate the corrected group, and state the safe next step. When PROVEN_INPUT_MAPPING exists, name its exact | &&
      |Row and SourceColumn and use CurrentValue as context. Use PROVEN_DDIC only as stated; do not invent a replacement value. | &&
      |Never use IF, MAY, MIGHT, | &&
      |COULD, POSSIBLY, PROBABLY, CONSIDER, or generic review/check advice. Never invent a value. | &&
      |Do not tell the user not to invent, guess, hallucinate, or trust AI; state the safe correction directly. | &&
      |Technical field/dynpro references must be copied exactly from evidence or left empty. | &&
      |Keep analysis and fix_action complete and specific. analysis must fit within { lv_cause_cap } characters | &&
      |and fix_action within { lv_action_cap } characters, based on the actual SAP destination fields. | &&
      |Return ONLY one raw JSON object with "severity", "evidence_quote", "analysis", | &&
      |"referenced_field", "referenced_dynpro", "fix_action". Evidence:| &&
      cl_abap_char_utilities=>newline && lv_lines.

    CLEAR: lv_refine_resp, lv_refine_shape, lv_refine_ok,
           lv_refine_root, lv_refine_fix, lv_refine_quote,
           lv_refine_field, lv_refine_dynpro, lv_refine_upper,
           lv_refine_an_upper.

    PERFORM call_ai_endpoint
      USING    'FIX' lv_endpoint lv_refine_prompt
      CHANGING lv_refine_resp lv_refine_ok.

    lv_ai_attempt = 1.
    WHILE ( lv_refine_ok <> abap_true OR lv_refine_resp IS INITIAL )
          AND lv_ai_attempt < 3.
      lv_ai_diag = gv_z619_ai_http_diag.
      lv_ai_transient = abap_false.
      IF lv_ai_diag CS 'HTTP_429' OR
         lv_ai_diag CS 'HTTP_5' OR
         lv_ai_diag CS 'SEND_FAIL_OR_TIMEOUT' OR
         lv_ai_diag CS 'RECEIVE_FAIL'.
        lv_ai_transient = abap_true.
      ENDIF.
      IF lv_ai_transient <> abap_true.
        EXIT.
      ENDIF.
      lv_ai_attempt = lv_ai_attempt + 1.
      CLEAR: lv_refine_resp, lv_refine_ok.
      PERFORM call_ai_endpoint
        USING    'FIX' lv_endpoint lv_refine_prompt
        CHANGING lv_refine_resp lv_refine_ok.
    ENDWHILE.

    IF lv_refine_ok = abap_true AND lv_refine_resp IS NOT INITIAL.
      PERFORM parse_fixguide_ai_resp
        USING    lv_refine_resp
        CHANGING lv_refine_root
                 lv_refine_fix
                 lv_refine_quote
                 lv_refine_field
                 lv_refine_dynpro
                 lv_refine_shape
                 lv_refine_ok.
    ENDIF.

    IF lv_refine_ok <> abap_true OR lv_refine_fix IS INITIAL OR
       lv_refine_root IS INITIAL.
      IF lv_ai_attempt > 1 AND lv_refine_resp IS INITIAL.
        gv_z619_ai_http_diag = |{ gv_z619_ai_http_diag };AUTO_ATTEMPTS={ lv_ai_attempt }|.
      ELSE.
        gv_z619_ai_http_diag = 'AI_QUALITY_FAIL:REWRITE_NO_SAFE_RESULT'.
      ENDIF.
      RETURN.
    ENDIF.

    CONDENSE: lv_refine_root, lv_refine_fix, lv_refine_quote,
              lv_refine_field, lv_refine_dynpro.
    lv_refine_upper = lv_refine_fix.
    lv_refine_an_upper = lv_refine_root.
    TRANSLATE lv_refine_upper TO UPPER CASE.
    TRANSLATE lv_refine_an_upper TO UPPER CASE.
    CONCATENATE space lv_refine_upper space INTO lv_refine_upper.
    CONCATENATE space lv_refine_an_upper space INTO lv_refine_an_upper.

    IF lv_mapping_proven = abap_true AND lv_source_column IS NOT INITIAL.
      lv_source_upper = lv_source_column.
      TRANSLATE lv_source_upper TO UPPER CASE.
      IF lv_refine_upper NS lv_source_upper.
        gv_z619_ai_http_diag = 'AI_QUALITY_FAIL:SOURCE_COLUMN_NOT_USED'.
        RETURN.
      ENDIF.
    ENDIF.

    IF strlen( lv_refine_fix ) < 45 OR strlen( lv_refine_root ) < 30 OR
       strlen( lv_refine_fix ) > lv_action_cap OR strlen( lv_refine_root ) > lv_cause_cap OR
       lv_refine_upper CS ' IF ' OR lv_refine_upper CS ' MAY ' OR
       lv_refine_upper CS ' MIGHT ' OR lv_refine_upper CS ' COULD ' OR
       lv_refine_upper CS ' POSSIBLY ' OR lv_refine_upper CS ' PROBABLY ' OR
       lv_refine_upper CS ' CONSIDER ' OR
       lv_refine_upper CS ' FAILED GROUP ' OR
       lv_refine_upper CS ' BUSINESS GROUP ' OR
       lv_refine_upper CS ' SELECTED GROUP ' OR
       lv_refine_upper CS ' THIS GROUP ' OR
       lv_refine_upper CS ' PROTOCOL ' OR
       lv_refine_upper CS ' REVIEW THE SOURCE DATA ' OR
       lv_refine_upper CS ' REVIEW THE SAP ' OR
       lv_refine_upper CS ' REVIEW THE ERROR ' OR
       lv_refine_upper CS ' REVIEW THE PROTOCOL ' OR
       lv_refine_upper CS ' DO NOT INVENT ' OR
       lv_refine_upper CS ' DO NOT GUESS ' OR
       lv_refine_an_upper CS ' MAY ' OR lv_refine_an_upper CS ' MIGHT ' OR
       lv_refine_an_upper CS ' COULD ' OR lv_refine_an_upper CS ' POSSIBLY ' OR
       lv_refine_an_upper CS ' PROBABLY ' OR lv_refine_an_upper CS ' ASSUME ' OR
       lv_refine_an_upper CS ' FAILED GROUP ' OR
       lv_refine_an_upper CS ' BUSINESS GROUP ' OR
       lv_refine_an_upper CS ' SELECTED GROUP ' OR
       lv_refine_an_upper CS ' THIS GROUP ' OR
       lv_refine_an_upper CS ' PROTOCOL '.
      gv_z619_ai_http_diag = 'AI_QUALITY_FAIL:REWRITE_STILL_WEAK'.
      RETURN.
    ENDIF.

    lv_root        = lv_refine_root.
    lv_fix         = lv_refine_fix.
    lv_quote       = lv_refine_quote.
    lv_ref_field   = lv_refine_field.
    lv_ref_dynpro  = lv_refine_dynpro.
    lv_parse_shape = lv_refine_shape.
  ENDIF.

 "Strict evidence gate. No compatibility bypass and no synthesized evidence.
  lv_anchor = iv_protocol.
  CONDENSE lv_anchor.
  IF lv_anchor IS INITIAL.
    gv_z619_ai_http_diag = 'GROUNDING_FAIL:NO_EXACT_PROTOCOL'.
    RETURN.
  ENDIF.
  IF lv_quote IS INITIAL.
    gv_z619_ai_http_diag = 'GROUNDING_FAIL:EVIDENCE_QUOTE_MISSING'.
    RETURN.
  ENDIF.

  lv_evidence_upper = lv_lines && cl_abap_char_utilities=>newline && lv_anchor.
  lv_quote_upper = lv_quote.
  TRANSLATE lv_evidence_upper TO UPPER CASE.
  TRANSLATE lv_quote_upper TO UPPER CASE.
  IF lv_evidence_upper NS lv_quote_upper.
    gv_z619_ai_http_diag = 'GROUNDING_FAIL:EVIDENCE_QUOTE_NOT_FOUND'.
    RETURN.
  ENDIF.

 "AI interpretation must visibly remain anchored to the exact quote.
  lv_root_upper = lv_root.
  TRANSLATE lv_root_upper TO UPPER CASE.
  IF lv_root_upper NS lv_quote_upper.
    gv_z619_ai_http_diag = 'GROUNDING_FAIL:ANALYSIS_NOT_ANCHORED'.
    RETURN.
  ENDIF.

  IF lv_ref_field IS NOT INITIAL.
    lv_ref_field_upper = lv_ref_field.
    lv_ground_upper = lv_ground_field.
    TRANSLATE lv_ref_field_upper TO UPPER CASE.
    TRANSLATE lv_ground_upper TO UPPER CASE.
    IF lv_ground_upper IS INITIAL OR lv_ref_field_upper <> lv_ground_upper.
      gv_z619_ai_http_diag = 'GROUNDING_FAIL:UNPROVEN_FIELD'.
      RETURN.
    ENDIF.
  ENDIF.

  IF lv_ref_dynpro IS NOT INITIAL.
    lv_ref_dynpro_upper = |DYNPRO { lv_ref_dynpro }|.
    TRANSLATE lv_ref_dynpro_upper TO UPPER CASE.
    IF lv_evidence_upper NS lv_ref_dynpro_upper.
      gv_z619_ai_http_diag = 'GROUNDING_FAIL:UNPROVEN_DYNPRO'.
      RETURN.
    ENDIF.
  ENDIF.

  cv_source       = 'OpenAI + verified SAP evidence'.
  cv_ai_cause     = lv_root.
  cv_ai_action    = lv_fix.
  cv_ground_field = lv_ground_field.
  cv_ai_ok        = abap_true.
  gv_z619_ai_http_diag = 'AI_OK:OPENAI_RESPONSES_EVIDENCE_GROUNDED'.

 "Keep AI history separate from SAP execution evidence. It is advisory only.
  CLEAR ls_pat.
  PERFORM make_ai_cache_key USING is_stg CHANGING lv_cache_key.
  ls_pat-session_id = is_stg-session_id.
  ls_pat-pattern_id = lv_cache_key.
  ls_pat-msg_type   = 'E'.
  ls_pat-message    = iv_protocol.
  ls_pat-field_name = cv_ground_field.
  ls_pat-count      = 1.
  ls_pat-fix_hint   = cv_ai_action.
  lt_saved_patterns = gt_patterns.
  lv_saved_session = txtp_ai_session.
  REFRESH gt_patterns.
  APPEND ls_pat TO gt_patterns.
  txtp_ai_session = is_stg-session_id.
  gt_patterns = lt_saved_patterns.
  txtp_ai_session = lv_saved_session.

ENDFORM.

FORM parse_fixguide_ai_resp
  USING    iv_resp       TYPE string
  CHANGING cv_root       TYPE string
           cv_fix        TYPE string
           cv_quote      TYPE string
           cv_ref_field  TYPE string
           cv_ref_dynpro TYPE string
           cv_shape      TYPE char30
           cv_ok         TYPE abap_bool.

  DATA: lv_payload TYPE string,
        lv_nested  TYPE string.

  CLEAR: cv_root, cv_fix, cv_quote, cv_ref_field, cv_ref_dynpro,
         cv_shape, cv_ok, lv_payload, lv_nested.

  IF iv_resp IS INITIAL.
    cv_shape = 'EMPTY'.
    RETURN.
  ENDIF.

 "Attempt 1 - direct JSON / raw JSON array returned by the endpoint.
  lv_payload = iv_resp.
  REPLACE ALL OCCURRENCES OF '```json' IN lv_payload WITH ''.
  REPLACE ALL OCCURRENCES OF '```JSON' IN lv_payload WITH ''.
  REPLACE ALL OCCURRENCES OF '```' IN lv_payload WITH ''.
  PERFORM json_get_bup USING lv_payload 'root_cause' CHANGING cv_root.
  IF cv_root IS INITIAL.
    PERFORM json_get_bup USING lv_payload 'rootCause' CHANGING cv_root.
  ENDIF.
  IF cv_root IS INITIAL.
    PERFORM json_get_bup USING lv_payload 'cause' CHANGING cv_root.
  ENDIF.
  IF cv_root IS INITIAL.
    PERFORM json_get_bup USING lv_payload 'analysis' CHANGING cv_root.
  ENDIF.
  PERFORM json_get_bup USING lv_payload 'fix_action' CHANGING cv_fix.
  IF cv_fix IS INITIAL.
    PERFORM json_get_bup USING lv_payload 'fixAction' CHANGING cv_fix.
  ENDIF.
  IF cv_fix IS INITIAL.
    PERFORM json_get_bup USING lv_payload 'recommended_fix' CHANGING cv_fix.
  ENDIF.
  IF cv_fix IS INITIAL.
    PERFORM json_get_bup USING lv_payload 'recommendedFix' CHANGING cv_fix.
  ENDIF.
  IF cv_fix IS INITIAL.
    PERFORM json_get_bup USING lv_payload 'suggestion' CHANGING cv_fix.
  ENDIF.
  IF cv_fix IS INITIAL.
    PERFORM json_get_bup USING lv_payload 'recommendation' CHANGING cv_fix.
  ENDIF.
  PERFORM json_get_bup USING lv_payload 'evidence_quote' CHANGING cv_quote.
  IF cv_quote IS INITIAL.
    PERFORM json_get_bup USING lv_payload 'evidenceQuote' CHANGING cv_quote.
  ENDIF.
  PERFORM json_get_bup USING lv_payload 'referenced_field' CHANGING cv_ref_field.
  IF cv_ref_field IS INITIAL.
    PERFORM json_get_bup USING lv_payload 'referencedField' CHANGING cv_ref_field.
  ENDIF.
  PERFORM json_get_bup USING lv_payload 'referenced_dynpro' CHANGING cv_ref_dynpro.
  IF cv_ref_dynpro IS INITIAL.
    PERFORM json_get_bup USING lv_payload 'referencedDynpro' CHANGING cv_ref_dynpro.
  ENDIF.
  CONDENSE cv_fix.
  IF cv_fix IS NOT INITIAL.
    cv_shape = 'DIRECT_JSON'.
    cv_ok = abap_true.
    RETURN.
  ENDIF.

 "Attempt 2 - OpenAI Responses envelope: output/content/text.
  CLEAR: cv_root, cv_fix, cv_quote, cv_ref_field, cv_ref_dynpro, lv_nested.
  PERFORM extract_openai_text USING iv_resp CHANGING lv_nested.
  IF lv_nested IS NOT INITIAL.
    REPLACE ALL OCCURRENCES OF '```json' IN lv_nested WITH ''.
    REPLACE ALL OCCURRENCES OF '```JSON' IN lv_nested WITH ''.
    REPLACE ALL OCCURRENCES OF '```' IN lv_nested WITH ''.
    PERFORM json_get_bup USING lv_nested 'root_cause' CHANGING cv_root.
    IF cv_root IS INITIAL.
      PERFORM json_get_bup USING lv_nested 'rootCause' CHANGING cv_root.
    ENDIF.
    IF cv_root IS INITIAL.
      PERFORM json_get_bup USING lv_nested 'cause' CHANGING cv_root.
    ENDIF.
    IF cv_root IS INITIAL.
      PERFORM json_get_bup USING lv_nested 'analysis' CHANGING cv_root.
    ENDIF.
    PERFORM json_get_bup USING lv_nested 'fix_action' CHANGING cv_fix.
    IF cv_fix IS INITIAL.
      PERFORM json_get_bup USING lv_nested 'fixAction' CHANGING cv_fix.
    ENDIF.
    IF cv_fix IS INITIAL.
      PERFORM json_get_bup USING lv_nested 'recommended_fix' CHANGING cv_fix.
    ENDIF.
    IF cv_fix IS INITIAL.
      PERFORM json_get_bup USING lv_nested 'recommendedFix' CHANGING cv_fix.
    ENDIF.
    IF cv_fix IS INITIAL.
      PERFORM json_get_bup USING lv_nested 'suggestion' CHANGING cv_fix.
    ENDIF.
    IF cv_fix IS INITIAL.
      PERFORM json_get_bup USING lv_nested 'recommendation' CHANGING cv_fix.
    ENDIF.
    PERFORM json_get_bup USING lv_nested 'evidence_quote' CHANGING cv_quote.
    IF cv_quote IS INITIAL.
      PERFORM json_get_bup USING lv_nested 'evidenceQuote' CHANGING cv_quote.
    ENDIF.
    PERFORM json_get_bup USING lv_nested 'referenced_field' CHANGING cv_ref_field.
    IF cv_ref_field IS INITIAL.
      PERFORM json_get_bup USING lv_nested 'referencedField' CHANGING cv_ref_field.
    ENDIF.
    PERFORM json_get_bup USING lv_nested 'referenced_dynpro' CHANGING cv_ref_dynpro.
    IF cv_ref_dynpro IS INITIAL.
      PERFORM json_get_bup USING lv_nested 'referencedDynpro' CHANGING cv_ref_dynpro.
    ENDIF.
    CONDENSE cv_fix.
    IF cv_fix IS NOT INITIAL.
      cv_shape = 'OPENAI_TEXT'.
      cv_ok = abap_true.
      RETURN.
    ENDIF.
  ENDIF.

 "Attempt 3 - generic wrapper containing escaped JSON. This is the same
 "transport-normalization pattern already proven by Object Discovery.
  CLEAR: cv_root, cv_fix, cv_quote, cv_ref_field, cv_ref_dynpro.
  lv_payload = iv_resp.
  REPLACE ALL OCCURRENCES OF '\"' IN lv_payload WITH '"'.
  REPLACE ALL OCCURRENCES OF '\"' IN lv_payload WITH '"'.
  REPLACE ALL OCCURRENCES OF '\n' IN lv_payload WITH space.
  REPLACE ALL OCCURRENCES OF '\r' IN lv_payload WITH space.
  REPLACE ALL OCCURRENCES OF '```json' IN lv_payload WITH ''.
  REPLACE ALL OCCURRENCES OF '```JSON' IN lv_payload WITH ''.
  REPLACE ALL OCCURRENCES OF '```' IN lv_payload WITH ''.

  PERFORM json_get_bup USING lv_payload 'root_cause' CHANGING cv_root.
  IF cv_root IS INITIAL.
    PERFORM json_get_bup USING lv_payload 'rootCause' CHANGING cv_root.
  ENDIF.
  IF cv_root IS INITIAL.
    PERFORM json_get_bup USING lv_payload 'cause' CHANGING cv_root.
  ENDIF.
  IF cv_root IS INITIAL.
    PERFORM json_get_bup USING lv_payload 'analysis' CHANGING cv_root.
  ENDIF.
  PERFORM json_get_bup USING lv_payload 'fix_action' CHANGING cv_fix.
  IF cv_fix IS INITIAL.
    PERFORM json_get_bup USING lv_payload 'fixAction' CHANGING cv_fix.
  ENDIF.
  IF cv_fix IS INITIAL.
    PERFORM json_get_bup USING lv_payload 'recommended_fix' CHANGING cv_fix.
  ENDIF.
  IF cv_fix IS INITIAL.
    PERFORM json_get_bup USING lv_payload 'recommendedFix' CHANGING cv_fix.
  ENDIF.
  IF cv_fix IS INITIAL.
    PERFORM json_get_bup USING lv_payload 'suggestion' CHANGING cv_fix.
  ENDIF.
  IF cv_fix IS INITIAL.
    PERFORM json_get_bup USING lv_payload 'recommendation' CHANGING cv_fix.
  ENDIF.
  PERFORM json_get_bup USING lv_payload 'evidence_quote' CHANGING cv_quote.
  IF cv_quote IS INITIAL.
    PERFORM json_get_bup USING lv_payload 'evidenceQuote' CHANGING cv_quote.
  ENDIF.
  PERFORM json_get_bup USING lv_payload 'referenced_field' CHANGING cv_ref_field.
  IF cv_ref_field IS INITIAL.
    PERFORM json_get_bup USING lv_payload 'referencedField' CHANGING cv_ref_field.
  ENDIF.
  PERFORM json_get_bup USING lv_payload 'referenced_dynpro' CHANGING cv_ref_dynpro.
  IF cv_ref_dynpro IS INITIAL.
    PERFORM json_get_bup USING lv_payload 'referencedDynpro' CHANGING cv_ref_dynpro.
  ENDIF.
  CONDENSE cv_fix.
  IF cv_fix IS NOT INITIAL.
    cv_shape = 'ESCAPED_WRAPPER'.
    cv_ok = abap_true.
    RETURN.
  ENDIF.

  cv_shape = 'UNSUPPORTED'.
ENDFORM.

FORM make_ai_cache_key
  USING    is_stg TYPE ty_staging_alv
  CHANGING cv_key TYPE char20.

  DATA lv_row_text TYPE char12.

  CLEAR: cv_key, lv_row_text.
  WRITE is_stg-row_index TO lv_row_text LEFT-JUSTIFIED.
  CONDENSE lv_row_text NO-GAPS.
  CONCATENATE 'FG801' lv_row_text INTO cv_key SEPARATED BY '_'.

ENDFORM.

FORM set_ai_fallback_source
  CHANGING cv_source TYPE char40.

  DATA lv_diag TYPE string.

  lv_diag = gv_z619_ai_http_diag.
  CONDENSE lv_diag.

 "Source is user-facing. The exact technical reason is shown in
 "AI Status, so rejected AI content is never presented as accepted evidence.
  IF lv_diag CS 'GROUNDING_FAIL' OR
     lv_diag CS 'AI_QUALITY_FAIL' OR
     lv_diag CS 'AI_PARSE_FAIL'.
    cv_source = 'Verified SAP evidence (AI not accepted)'.
  ELSEIF lv_diag CS 'HTTP_' OR
         lv_diag CS 'SEND_FAIL_OR_TIMEOUT' OR
         lv_diag CS 'RECEIVE_FAIL' OR
         lv_diag CS 'AI_CALL_NO_RESPONSE' OR
         lv_diag CS 'AI_CONFIG_MISSING' OR
         lv_diag CS 'KEY_MISSING' OR
         lv_diag CS 'AI_DISABLED_BY_CONFIG' OR
         lv_diag CS 'ENDPOINT_REJECTED' OR
         lv_diag CS 'INVALID_MODEL_ID'.
    cv_source = 'Verified SAP evidence (AI unavailable)'.
  ELSE.
    cv_source = 'Verified SAP evidence'.
  ENDIF.

ENDFORM.

FORM build_evidence_fallback
  USING    is_stg          TYPE ty_staging_alv
           iv_protocol     TYPE char255
           iv_ground_field TYPE char80
  CHANGING cv_cause        TYPE char255
           cv_action       TYPE char255.

  DATA: lv_msg       TYPE string,
        lv_upper     TYPE string,
        lv_field     TYPE string,
        lv_group     TYPE string,
        lv_prefix    TYPE string,
        lv_input_row TYPE i,
        lv_source_column TYPE string,
        lv_staging_field TYPE string,
        lv_current_value TYPE string,
        lv_ddic_label TYPE string,
        lv_ddic_rule TYPE string,
        lv_ddic_datatype TYPE string,
        lv_ddic_length TYPE i,
        lv_ddic_convexit TYPE string,
        lv_ddic_domain TYPE string,
        lv_ddic_checktable TYPE string,
        lv_fixed_values TYPE string,
        lv_validation_evid TYPE string,
        lv_mandatory TYPE c LENGTH 1,
        lv_mapping_proven TYPE abap_bool,
        lv_input_ref TYPE string,
        lv_value_ctx TYPE string.

  CLEAR: cv_cause, cv_action.
  lv_msg = iv_protocol.
  CONDENSE lv_msg.
  lv_upper = lv_msg.
  TRANSLATE lv_upper TO UPPER CASE.
  lv_field = iv_ground_field.
  CONDENSE lv_field.
  lv_group = is_stg-record_key.
  CONDENSE lv_group.
  IF lv_group IS INITIAL.
    lv_group = 'the selected group'.
  ENDIF.

  IF lv_field IS NOT INITIAL.
    PERFORM resolve_fixguide_input_evid
      USING    is_stg lv_field
      CHANGING lv_input_row lv_source_column lv_staging_field
               lv_current_value lv_ddic_label lv_ddic_rule
               lv_ddic_datatype lv_ddic_length lv_ddic_convexit
               lv_ddic_domain lv_ddic_checktable lv_fixed_values
               lv_validation_evid lv_mandatory lv_mapping_proven.
    IF lv_mapping_proven = abap_true.
      IF lv_source_column IS NOT INITIAL.
        lv_input_ref = |row { lv_input_row }, template column { lv_source_column }|.
      ELSEIF lv_staging_field IS NOT INITIAL.
        lv_input_ref = |row { lv_input_row }, staging field { lv_staging_field }|.
      ENDIF.
      IF lv_current_value IS NOT INITIAL.
        lv_value_ctx = | Current value: "{ lv_current_value }".|.
      ENDIF.
    ENDIF.
  ENDIF.

  IF lv_msg IS INITIAL.
    cv_cause = |No exact SAP message was captured for { lv_group }. A specific correction cannot be proven safely.|.
    cv_action = 'A safe correction cannot be identified from the available SAP message. Open Error Detail or re-run AI Analysis before changing data.'.
    RETURN.
  ENDIF.

 "State only facts proven by the exact SAP runtime evidence. Never
 "translate a technical field token into an assumed business meaning.
  IF lv_field IS NOT INITIAL.
    IF lv_input_ref IS NOT INITIAL.
      lv_prefix = |SAP rejected { lv_group }. { lv_input_ref } maps exactly to SAP field { lv_field }.{ lv_value_ctx }|.
    ELSE.
      lv_prefix = |SAP rejected { lv_group }. Confirmed affected SAP field: { lv_field }. The exact SAP message shown above is the verified error returned by SAP.|.
    ENDIF.
  ELSE.
    lv_prefix = |SAP rejected { lv_group }. The exact SAP message shown above is the verified error returned by SAP.|.
  ENDIF.
  cv_cause = lv_prefix.

 "Generic message semantics only: no TCODE CASE, no invented object, no
 "guessed replacement value and no hidden root-cause claim.
  IF lv_upper CS 'ALREADY EXISTS' OR lv_upper CS 'ALREADY EXIST'.
    IF lv_field IS NOT INITIAL.
      IF lv_input_ref IS NOT INITIAL.
        cv_action = |Edit { lv_input_ref }.{ lv_value_ctx } Replace only that input with the intended SAP-valid value that is not already in use.|.
      ELSE.
        cv_action = |Correct { lv_field } using the intended SAP-valid value that is not already in use.|.
      ENDIF.
    ELSE.
      cv_action = 'Correct the value that SAP reports as already existing. Use the correct SAP-valid value intended for this transaction that is not already in use.'.
    ENDIF.
  ELSEIF lv_upper CS 'DOES NOT EXIST' OR lv_upper CS 'NOT EXIST' OR
         lv_upper CS 'NOT FOUND' OR lv_upper CS 'UNKNOWN'.
    IF lv_field IS NOT INITIAL.
      IF lv_input_ref IS NOT INITIAL.
        cv_action = |Edit { lv_input_ref }.{ lv_value_ctx } Replace only that input with the intended valid value that actually exists in SAP.|.
      ELSE.
        cv_action = |Replace { lv_field } with the intended valid value that actually exists in SAP.|.
      ENDIF.
    ELSE.
      cv_action = 'Correct the referenced input to the intended valid value that actually exists in SAP.'.
    ENDIF.
  ELSEIF lv_upper CS 'REQUIRED' OR lv_upper CS 'MANDATORY' OR
         lv_upper CS 'ENTER ' OR lv_upper CS 'MUST BE ENTERED'.
    IF lv_field IS NOT INITIAL.
      IF lv_input_ref IS NOT INITIAL.
        cv_action = |Enter the required SAP-valid value in { lv_input_ref }. Leave unrelated inputs unchanged.|.
      ELSE.
        cv_action = |Enter the required SAP-valid value for { lv_field }. Leave unrelated inputs unchanged.|.
      ENDIF.
    ELSE.
      cv_action = 'Enter the required SAP-valid input identified by the SAP message. Leave unrelated inputs unchanged.'.
    ENDIF.
  ELSEIF lv_upper CS 'INVALID' OR lv_upper CS 'NOT VALID' OR
         lv_upper CS 'INCORRECT'.
    IF lv_field IS NOT INITIAL.
      IF lv_input_ref IS NOT INITIAL.
        cv_action = |Edit { lv_input_ref }.{ lv_value_ctx } Correct only that input to a SAP-valid value intended for this transaction.|.
      ELSE.
        cv_action = |Correct { lv_field } to the SAP-valid value intended for this transaction.|.
      ENDIF.
    ELSE.
      cv_action = 'Correct only the invalid input identified by the SAP message, using the SAP-valid value intended for this transaction.'.
    ENDIF.
  ELSEIF lv_upper CS 'LOCKED' OR lv_upper CS 'IS BEING PROCESSED'.
    cv_action = 'Do not change business data to bypass the lock. Retry only after SAP releases the lock and validation passes.'.
  ELSE.
 "Unknown message semantics: do not reuse a generic classifier that may
 "speculate about master data, popups or hidden business rules. Be explicit
 "that no unproven data change is being recommended.
    cv_cause = lv_prefix.
    cv_action = 'The verified SAP message does not prove a specific data correction. Open Error Detail or re-run AI Analysis before changing data or retrying.'.
  ENDIF.

ENDFORM.

FORM ai_diag_friendly CHANGING cv_text TYPE char255.

  DATA lv_diag TYPE string.

  CLEAR cv_text.
  lv_diag = gv_z619_ai_http_diag.
  CONDENSE lv_diag.

  IF lv_diag IS INITIAL.
    cv_text = 'OpenAI did not return a usable evidence-grounded analysis. The guide below uses verified SAP evidence only.'.
  ELSEIF lv_diag CS 'AI_DISABLED_BY_CONFIG'.
    cv_text = 'OpenAI analysis is disabled. The guide below uses verified SAP evidence only.'.
  ELSEIF lv_diag CS 'AI_CONFIG_MISSING' OR lv_diag CS 'OPENAI_CONFIG_MISSING' OR lv_diag CS 'KEY_MISSING'.
    cv_text = 'OpenAI is not configured with a usable API key. The guide below uses verified SAP evidence only.'.
  ELSEIF lv_diag CS 'INVALID_MODEL_ID'.
    cv_text = 'The configured OpenAI model is invalid. The guide below uses verified SAP evidence only.'.
  ELSEIF lv_diag CS 'ENDPOINT_REJECTED'.
    cv_text = 'The configured OpenAI endpoint is not accepted. The guide below uses verified SAP evidence only.'.
  ELSEIF lv_diag CS 'HTTP_401' OR lv_diag CS 'HTTP_403'.
    cv_text = 'OpenAI rejected the configured credential or access. The guide below uses verified SAP evidence only.'.
  ELSEIF lv_diag CS 'HTTP_429' AND lv_diag CS 'AUTO_ATTEMPTS=3'.
    cv_text = 'OpenAI was tried three times, but its quota or rate limit still blocked the request. The guide below uses verified SAP evidence only.'.
  ELSEIF lv_diag CS 'HTTP_429'.
    cv_text = 'OpenAI is temporarily unavailable because its quota or rate limit was reached. The guide below uses verified SAP evidence only.'.
  ELSEIF lv_diag CS 'HTTP_400'.
    cv_text = 'OpenAI rejected the request format or model parameters. The guide below uses verified SAP evidence only.'.
  ELSEIF lv_diag CS 'HTTP_404'.
    cv_text = 'The configured OpenAI model or endpoint was not found. The guide below uses verified SAP evidence only.'.
  ELSEIF lv_diag CS 'HTTP_5' AND lv_diag CS 'AUTO_ATTEMPTS=3'.
    cv_text = 'OpenAI was tried three times, but the server error continued. The guide below uses verified SAP evidence only.'.
  ELSEIF lv_diag CS 'HTTP_5'.
    cv_text = 'OpenAI is temporarily unavailable because the server returned an error. The guide below uses verified SAP evidence only.'.
  ELSEIF ( lv_diag CS 'SEND_FAIL_OR_TIMEOUT' OR lv_diag CS 'RECEIVE_FAIL' ) AND
         lv_diag CS 'AUTO_ATTEMPTS=3'.
    cv_text = 'OpenAI was tried three times, but the network or timeout problem continued. The guide below uses verified SAP evidence only.'.
  ELSEIF lv_diag CS 'SEND_FAIL_OR_TIMEOUT' OR lv_diag CS 'RECEIVE_FAIL'.
    cv_text = 'OpenAI could not be reached because the request timed out or the network failed. The guide below uses verified SAP evidence only.'.
  ELSEIF lv_diag CS 'SERIALIZE_FAIL'.
    cv_text = 'The OpenAI request could not be created safely. The guide below uses verified SAP evidence only.'.
  ELSEIF lv_diag CS 'HTTP_200_EMPTY'.
    cv_text = 'OpenAI returned an empty response. The guide below uses verified SAP evidence only.'.
  ELSEIF lv_diag CS 'HTTP_200_HTML_REJECTED'.
    cv_text = 'OpenAI returned an unexpected response instead of usable JSON. The guide below uses verified SAP evidence only.'.
  ELSEIF lv_diag CS 'AI_PARSE_FAIL'.
    cv_text = 'OpenAI responded, but its answer could not be parsed into a complete safe fix. The answer was not used.'.
  ELSEIF lv_diag CS 'AI_QUALITY_FAIL'.
    cv_text = 'OpenAI responded, but the guidance was vague, conditional, or incomplete. The answer was blocked and not used.'.
  ELSEIF lv_diag CS 'GROUNDING_FAIL:NO_EXACT_PROTOCOL'.
    cv_text = 'OpenAI was not used because there was no exact SAP message available to prove its analysis.'.
  ELSEIF lv_diag CS 'GROUNDING_FAIL:EVIDENCE_QUOTE_MISSING'.
    cv_text = 'OpenAI did not quote the required SAP evidence exactly. The answer was blocked and not used.'.
  ELSEIF lv_diag CS 'GROUNDING_FAIL:EVIDENCE_QUOTE_NOT_FOUND'.
    cv_text = 'OpenAI cited evidence that does not exist in this group. The answer was blocked and not used.'.
  ELSEIF lv_diag CS 'GROUNDING_FAIL:ANALYSIS_NOT_ANCHORED'.
    cv_text = 'OpenAI analysis was not tied directly to the verified SAP message. The answer was blocked and not used.'.
  ELSEIF lv_diag CS 'GROUNDING_FAIL:UNPROVEN_FIELD'.
    cv_text = 'OpenAI referenced a technical field that this group does not prove. The answer was blocked and not used.'.
  ELSEIF lv_diag CS 'GROUNDING_FAIL:UNPROVEN_DYNPRO'.
    cv_text = 'OpenAI referenced a screen that this group does not prove. The answer was blocked and not used.'.
  ELSEIF lv_diag CS 'GROUNDING_FAIL'.
    cv_text = 'OpenAI introduced information not proven by this group. The answer was blocked; the guide uses verified SAP evidence only.'.
  ELSEIF lv_diag CS 'AI_CALL_NO_RESPONSE'.
    cv_text = 'OpenAI did not return a response. The guide below uses verified SAP evidence only.'.
  ELSE.
    cv_text = 'OpenAI did not produce a safe evidence-grounded recommendation. The guide below uses verified SAP evidence only.'.
  ENDIF.

ENDFORM.

FORM build_fixguide_cards
  USING    is_stg          TYPE ty_staging_alv
           is_exec         TYPE ty_exec_disp
           iv_protocol     TYPE char255
           iv_category     TYPE char40
           iv_rule_cause   TYPE char255
           iv_rule_action  TYPE char255
           iv_ai_source    TYPE char40
           iv_ai_cause     TYPE char255
           iv_ai_action    TYPE char255
           iv_ground_field TYPE char80
           iv_ai_ok        TYPE abap_bool.

  DATA: ls_fix            TYPE ty_fix_card_789,
        lv_group          TYPE string,
        lv_scope          TYPE string,
        lv_safe           TYPE string,
        lv_validate       TYPE string,
        lv_ai_diag        TYPE char255,
        lv_protocol_text  TYPE string,
        lv_input_row      TYPE i,
        lv_source_column  TYPE string,
        lv_staging_field  TYPE string,
        lv_current_value  TYPE string,
        lv_ddic_label     TYPE string,
        lv_ddic_rule      TYPE string,
        lv_ddic_datatype  TYPE string,
        lv_ddic_length    TYPE i,
        lv_ddic_convexit  TYPE string,
        lv_ddic_domain    TYPE string,
        lv_ddic_checktable TYPE string,
        lv_fixed_values   TYPE string,
        lv_validation_evid TYPE string,
        lv_mandatory      TYPE c LENGTH 1,
        lv_mapping_proven TYPE abap_bool,
        lv_meta           TYPE string,
        lv_step           TYPE string.

  REFRESH gt_fix_guide_789.

 "General Fix Guide layout. One semantic item = one ALV row.
 "No TCode/message/field-specific wrapping and no arbitrary 120/128 display
 "limit. The actual content drives SALV width; overflow uses horizontal
 "scrolling instead of creating unlabeled continuation rows below.
  DEFINE add_fix_789.
    CLEAR ls_fix.
    ls_fix-section = &1.
    ls_fix-detail  = &2.
    APPEND ls_fix TO gt_fix_guide_789.
  END-OF-DEFINITION.

 "OBJECT_PROOF_REQUIRED is a successful SAP business replay waiting only for
 "certified object identity. It is not a data correction case and must not
 "be described as an SAP rejection or sent to AI error analysis.
  IF is_exec-run_status = GC_ST_PARTIAL AND
     is_exec-message CP 'OBJECT_PROOF_REQUIRED*'.
    add_fix_789 '1. EXECUTION STATE' space.
    add_fix_789 'Status' 'PARTIAL - SAP success; object proof pending'.
    lv_group = |{ is_stg-record_key } ({ is_stg-tcode })|.
    add_fix_789 'Affected Group' lv_group.
    add_fix_789 'SAP Success Message' iv_protocol.

    add_fix_789 '2. WHY IT IS PARTIAL' space.
    add_fix_789 'Analysis Source' 'Verified SAP success evidence'.
    add_fix_789 'Explanation'
      'SAP returned an exact success message, but this execution row is not yet bound to one certified SAP object.'.

    add_fix_789 '3. REQUIRED ACTION' space.
    add_fix_789 'Action'
      'Open AI Navigation, open the real SAP target, verify the landing, then choose Certify. Do not rerun the transaction.'.

    add_fix_789 '4. VERIFY / RETRY' space.
    add_fix_789 'Verification'
      'After certification, refresh the cockpit. The same group must promote to SUCCESS and its certified document route must become available.'.
    add_fix_789 'Retry'
      'DO NOT RETRY: SAP already reported success; replay could create a duplicate business object.'.
    RETURN.
  ENDIF.

 "Resolve concrete input evidence once for the guide. The guide can still
 "operate when mapping is unavailable, but it will say exactly what is and is
 "not proven instead of fabricating a source column.
  IF iv_ground_field IS NOT INITIAL.
    PERFORM resolve_fixguide_input_evid
      USING    is_stg iv_ground_field
      CHANGING lv_input_row lv_source_column lv_staging_field
               lv_current_value lv_ddic_label lv_ddic_rule
               lv_ddic_datatype lv_ddic_length lv_ddic_convexit
               lv_ddic_domain lv_ddic_checktable lv_fixed_values
               lv_validation_evid lv_mandatory lv_mapping_proven.
  ENDIF.

 "1. PROBLEM = diagnosis, not a second Error Detail screen.
  add_fix_789 '1. PROBLEM' space.
  IF iv_ai_ok = abap_true AND iv_ai_cause IS NOT INITIAL.
    add_fix_789 'What SAP Rejected' iv_ai_cause.
  ELSEIF iv_rule_cause IS NOT INITIAL.
    add_fix_789 'What SAP Rejected' iv_rule_cause.
  ELSE.
    add_fix_789 'What SAP Rejected' iv_protocol.
  ENDIF.
  add_fix_789 'Verified SAP Message' iv_protocol.
  add_fix_789 'Analysis Source' iv_ai_source.
  IF iv_ai_ok <> abap_true.
    PERFORM ai_diag_friendly CHANGING lv_ai_diag.
    IF lv_ai_diag IS NOT INITIAL.
      add_fix_789 'AI Status' lv_ai_diag.
    ENDIF.
  ENDIF.

 "2. AFFECTED INPUT = exact mapping/value/DDIC chain.
  add_fix_789 '2. AFFECTED INPUT' space.
  IF lv_mapping_proven = abap_true.
    IF lv_input_row > 0.
      lv_scope = |Row { lv_input_row }|.
      add_fix_789 'Input Row' lv_scope.
    ENDIF.
    IF lv_source_column IS NOT INITIAL.
      add_fix_789 'Template Column' lv_source_column.
    ENDIF.
    IF lv_staging_field IS NOT INITIAL.
      add_fix_789 'Staging Field' lv_staging_field.
    ENDIF.
    IF iv_ground_field IS NOT INITIAL.
      add_fix_789 'SAP Technical Field' iv_ground_field.
    ENDIF.
    IF lv_current_value IS NOT INITIAL.
      add_fix_789 'Current Uploaded Value' lv_current_value.
    ELSE.
      add_fix_789 'Current Uploaded Value' '<blank>'.
    ENDIF.
    IF lv_mandatory = 'X'.
      add_fix_789 'Mapping Requirement' 'Required by the frozen Mapping Profile'.
    ENDIF.
  ELSEIF iv_ground_field IS NOT INITIAL.
    add_fix_789 'SAP Technical Field' iv_ground_field.
    add_fix_789 'Source Mapping'
      'No unique source/template column is proven by the frozen Mapping Profile; unrelated columns must not be changed.'.
  ELSE.
    add_fix_789 'Source Mapping'
      'The captured evidence does not identify one unique technical/input field.'.
  ENDIF.

  IF lv_ddic_label IS NOT INITIAL.
    add_fix_789 'DDIC Label' lv_ddic_label.
  ENDIF.
  CLEAR lv_meta.
  IF lv_ddic_datatype IS NOT INITIAL.
    lv_meta = |Type { lv_ddic_datatype }|.
  ENDIF.
  IF lv_ddic_length > 0.
    IF lv_meta IS INITIAL.
      lv_meta = |Length { lv_ddic_length }|.
    ELSE.
      lv_meta = |{ lv_meta }; length { lv_ddic_length }|.
    ENDIF.
  ENDIF.
  IF lv_ddic_convexit IS NOT INITIAL.
    IF lv_meta IS INITIAL.
      lv_meta = |Conversion exit { lv_ddic_convexit }|.
    ELSE.
      lv_meta = |{ lv_meta }; conversion exit { lv_ddic_convexit }|.
    ENDIF.
  ENDIF.
  IF lv_ddic_domain IS NOT INITIAL.
    IF lv_meta IS INITIAL.
      lv_meta = |Domain { lv_ddic_domain }|.
    ELSE.
      lv_meta = |{ lv_meta }; domain { lv_ddic_domain }|.
    ENDIF.
  ENDIF.
  IF lv_meta IS NOT INITIAL.
    add_fix_789 'DDIC Metadata' lv_meta.
  ENDIF.
  IF lv_ddic_rule IS NOT INITIAL.
    add_fix_789 'Proven Technical Rule' lv_ddic_rule.
  ENDIF.
  IF lv_fixed_values IS NOT INITIAL.
    add_fix_789 'Proven Fixed Values' lv_fixed_values.
  ENDIF.
  IF lv_ddic_checktable IS NOT INITIAL.
    add_fix_789 'DDIC Check Table' lv_ddic_checktable.
  ENDIF.
  IF lv_validation_evid IS NOT INITIAL AND
     lv_validation_evid <> iv_protocol.
    add_fix_789 'Validation Evidence' lv_validation_evid.
  ENDIF.

 "3. HOW TO FIX = concrete user action, grounded by the rows above.
  add_fix_789 '3. HOW TO FIX' space.
  IF iv_category = 'BDC SCREEN DRIFT'.
    lv_step = |Update the recording so it matches the SAP screens actually reached for { is_stg-record_key }.|.
    add_fix_789 'Step 1' lv_step.
  ELSEIF lv_mapping_proven = abap_true AND lv_source_column IS NOT INITIAL.
    IF lv_current_value IS INITIAL.
      lv_step = |Edit row { lv_input_row }, template column { lv_source_column }; the current uploaded value is blank.|.
    ELSE.
      lv_step = |Edit row { lv_input_row }, template column { lv_source_column }; current value = "{ lv_current_value }".|.
    ENDIF.
    add_fix_789 'Step 1' lv_step.
  ELSEIF iv_ground_field IS NOT INITIAL.
    lv_step = |Do not change unrelated inputs. The only proven affected technical field is { iv_ground_field }.|.
    add_fix_789 'Step 1' lv_step.
  ENDIF.

  IF iv_ai_ok = abap_true AND iv_ai_action IS NOT INITIAL.
    add_fix_789 'Step 2 - Correction' iv_ai_action.
  ELSEIF iv_rule_action IS NOT INITIAL.
    add_fix_789 'Step 2 - Correction' iv_rule_action.
  ENDIF.

  IF lv_fixed_values IS NOT INITIAL.
    add_fix_789 'Allowed-Value Evidence'
      'Use only the intended value consistent with the proven DDIC fixed-value set above; the guide does not choose business intent for the user.'.
  ENDIF.

  lv_step = |Run Validate Selected for { is_stg-record_key }. Do not rerun the transaction while validation still reports the same issue.|.
  add_fix_789 'Step 3 - Validate' lv_step.

 "4. VERIFY / RETRY keeps only the acceptance condition and safe replay scope.
  add_fix_789 '4. VERIFY & RETRY' space.
  lv_protocol_text = iv_protocol.
  CONDENSE lv_protocol_text.
  IF lv_protocol_text IS NOT INITIAL.
    lv_validate = |Correction is confirmed only when the exact SAP error "{ lv_protocol_text }" no longer occurs for { is_stg-record_key }.|.
  ELSE.
    lv_validate = |Correction is confirmed only when the recorded issue no longer occurs for { is_stg-record_key }.|.
  ENDIF.
  add_fix_789 'Verification' lv_validate.

  IF is_exec-message CS 'COMMITTED_CONTRACT_ERROR'.
    lv_safe = |Do not retry { is_stg-record_key } yet. SAP may already have saved a business change; confirm the execution evidence first.|.
  ELSEIF iv_category = 'BDC SCREEN DRIFT'.
    lv_safe = |After the recording is corrected and validation passes, retry { is_stg-record_key } only.|.
  ELSE.
    lv_safe = |After validation passes, run { is_stg-record_key } only. Groups already marked SUCCESS remain unchanged.|.
  ENDIF.
  add_fix_789 'Retry' lv_safe.

ENDFORM.

FORM show_fixguide_text
  USING iv_title TYPE csequence
        iv_text  TYPE csequence.

  TYPES: BEGIN OF ty_z799_line,
           line TYPE c LENGTH 100,
         END OF ty_z799_line.

  DATA: lt_lines  TYPE STANDARD TABLE OF ty_z799_line,
        ls_line   TYPE ty_z799_line,
        lv_rest   TYPE string,
        lv_len    TYPE i,
        lv_header TYPE lvc_title,
        lo_salv   TYPE REF TO cl_salv_table,
        lo_cols   TYPE REF TO cl_salv_columns_table,
        lx_salv   TYPE REF TO cx_salv_msg.

  CLEAR: lt_lines, ls_line, lv_rest, lv_header.
  lv_rest = iv_text.

 "Classic SALV has no reliable multiline cell wrapping. Preserve the exact
 "text and present it in fixed 100-character display lines instead of
 "truncating the AI recommendation at the visible column boundary.
  WHILE lv_rest IS NOT INITIAL.
    CLEAR ls_line.
    lv_len = strlen( lv_rest ).
    IF lv_len > 100.
      ls_line-line = lv_rest+0(100).
      lv_rest = lv_rest+100.
    ELSE.
      ls_line-line = lv_rest.
      CLEAR lv_rest.
    ENDIF.
    APPEND ls_line TO lt_lines.
  ENDWHILE.

  IF lt_lines IS INITIAL.
    RETURN.
  ENDIF.

  CONCATENATE 'Full' iv_title INTO lv_header SEPARATED BY space.

  TRY.
      cl_salv_table=>factory(
        IMPORTING r_salv_table = lo_salv
        CHANGING  t_table      = lt_lines ).
      lo_salv->get_display_settings( )->set_list_header( lv_header ).
      lo_salv->get_functions( )->set_all( abap_true ).
      lo_cols = lo_salv->get_columns( ).
      lo_cols->set_optimize( abap_true ).
      PERFORM set_salv_col_text USING lo_cols 'LINE'
        'Text' 'Full Text' 'Full Text'.
      PERFORM set_salv_col_width USING lo_cols 'LINE' 100.
      lo_salv->set_screen_popup(
        start_column = 10
        end_column   = 122
        start_line   = 5
        end_line     = 12 ).
      lo_salv->display( ).
    CATCH cx_salv_msg INTO lx_salv.
      MESSAGE lx_salv->get_text( ) TYPE 'S' DISPLAY LIKE 'E'.
  ENDTRY.

ENDFORM.

FORM run_fixguide_ai.

  DATA: ls_stg           TYPE ty_staging_alv,
        ls_exec          TYPE ty_exec_disp,
        lv_protocol      TYPE char255,
        lv_category      TYPE char40,
        lv_summary       TYPE char120,
        lv_rule_cause    TYPE char255,
        lv_rule_action   TYPE char255,
        lv_ai_source     TYPE char40,
        lv_ai_cause      TYPE char255,
        lv_ai_action     TYPE char255,
        lv_ground_field  TYPE char80,
        lv_ai_ok         TYPE abap_bool.

  IF gv_fixguide_stg_idx_789 IS INITIAL.
    MESSAGE 'Fix Guide context is no longer available. Reopen the guide.' TYPE 'S' DISPLAY LIKE 'W'.
    RETURN.
  ENDIF.

  READ TABLE gt_staging_alv INTO ls_stg INDEX gv_fixguide_stg_idx_789.
  IF sy-subrc <> 0.
    MESSAGE 'Fix Guide staging context is no longer available. Reopen the guide.' TYPE 'S' DISPLAY LIKE 'W'.
    RETURN.
  ENDIF.

  READ TABLE gt_exec_disp INTO ls_exec
    WITH KEY session_id = ls_stg-session_id
             group_key  = ls_stg-record_key.
  IF sy-subrc <> 0.
    READ TABLE gt_exec_disp INTO ls_exec
      WITH KEY group_key = ls_stg-record_key.
  ENDIF.
  IF sy-subrc <> 0.
    MESSAGE 'Fix Guide execution context is no longer available. Reopen the guide.' TYPE 'S' DISPLAY LIKE 'W'.
    RETURN.
  ENDIF.

  PERFORM pick_protocol
    USING ls_stg ls_exec
    CHANGING lv_protocol.
  PERFORM classify_issue
    USING ls_exec-run_status lv_protocol space
    CHANGING lv_category lv_summary lv_rule_cause lv_rule_action.

  CLEAR: lv_ai_source, lv_ai_cause, lv_ai_action, lv_ground_field, lv_ai_ok.

  IF ls_exec-run_status = GC_ST_PARTIAL AND
     ls_exec-message CP 'OBJECT_PROOF_REQUIRED*'.
    lv_ai_source = 'Verified SAP success evidence'.
    PERFORM build_fixguide_cards
      USING ls_stg ls_exec lv_protocol lv_category
            lv_rule_cause lv_rule_action
            lv_ai_source lv_ai_cause lv_ai_action lv_ground_field lv_ai_ok.
    MESSAGE 'No error analysis is required. Verify the real SAP landing with AI Navigation and certify the object.' TYPE 'S' DISPLAY LIKE 'I'.
    IF go_fix_guide_789 IS BOUND.
      TRY.
          go_fix_guide_789->refresh( ).
          cl_gui_cfw=>flush( ).
        CATCH cx_root.
      ENDTRY.
    ENDIF.
    RETURN.
  ENDIF.

 "This is the only Fix Guide path that performs an external OpenAI HTTP
 "request. The user explicitly requested it, so a network wait no longer
 "blocks the normal popup-open path.
  PERFORM get_group_ai_advice
    USING    ls_stg lv_protocol
    CHANGING lv_ai_source lv_ai_cause lv_ai_action lv_ground_field lv_ai_ok.

  IF lv_ai_ok <> abap_true.
    PERFORM set_ai_fallback_source CHANGING lv_ai_source.
    PERFORM build_evidence_fallback
      USING ls_stg lv_protocol lv_ground_field
      CHANGING lv_ai_cause lv_ai_action.
    lv_rule_cause  = lv_ai_cause.
    lv_rule_action = lv_ai_action.
    IF gv_z619_ai_http_diag CS 'HTTP_' OR
       gv_z619_ai_http_diag CS 'SEND_FAIL_OR_TIMEOUT' OR
       gv_z619_ai_http_diag CS 'RECEIVE_FAIL' OR
       gv_z619_ai_http_diag CS 'KEY_MISSING' OR
       gv_z619_ai_http_diag CS 'AI_CONFIG_MISSING'.
      MESSAGE 'OpenAI is unavailable; verified SAP evidence is shown instead.' TYPE 'S' DISPLAY LIKE 'W'.
    ELSE.
      MESSAGE 'OpenAI answer did not pass the evidence checks; verified SAP evidence is shown instead.' TYPE 'S' DISPLAY LIKE 'W'.
    ENDIF.
  ELSE.
    MESSAGE 'AI analysis completed for the selected business group.' TYPE 'S'.
  ENDIF.

  PERFORM build_fixguide_cards
    USING ls_stg ls_exec lv_protocol lv_category
          lv_rule_cause lv_rule_action
          lv_ai_source lv_ai_cause lv_ai_action lv_ground_field lv_ai_ok.

  IF go_fix_guide_789 IS BOUND.
    TRY.
        go_fix_guide_789->refresh( ).
        cl_gui_cfw=>flush( ).
      CATCH cx_root.
    ENDTRY.
  ENDIF.

ENDFORM.

FORM show_fix_guide_safe.

  DATA: ls_exec  TYPE ty_exec_disp,
        ls_stg   TYPE ty_staging_alv,
        lo_cols  TYPE REF TO cl_salv_columns_table,
        lx_salv  TYPE REF TO cx_salv_msg.

  DATA: lv_protocol      TYPE char255,
        lv_category      TYPE char40,
        lv_summary       TYPE char120,
        lv_rule_cause    TYPE char255,
        lv_rule_action   TYPE char255,
        lv_ai_source     TYPE char40,
        lv_ai_cause      TYPE char255,
        lv_ai_action     TYPE char255,
        lv_ground_field  TYPE char80,
        lv_ai_ok         TYPE abap_bool,
        lv_header        TYPE lvc_title,
        lv_html_ok       TYPE abap_bool.

 "Fix Guide uses real OpenAI analysis automatically again.
 "Exact-group grounded AI cache is reused first; only a cache miss calls the
 "external AI endpoint synchronously before the popup is rendered.
  PERFORM pick_0500_issue.

  IF g_edit_index IS INITIAL.
    CALL FUNCTION 'POPUP_TO_INFORM'
      EXPORTING
        titel = 'Select an Issue'
        txt1  = 'Select an ERROR, WARNING, SKIPPED or PARTIAL business group first.'
        txt2  = 'Fix Guide analyzes only the exact selected business group.'.
    RETURN.
  ENDIF.

  READ TABLE gt_staging_alv INTO ls_stg INDEX g_edit_index.
  IF sy-subrc <> 0.
    MESSAGE 'Selected business group could not be matched to staging data.' TYPE 'S' DISPLAY LIKE 'E'.
    RETURN.
  ENDIF.

  READ TABLE gt_exec_disp INTO ls_exec
    WITH KEY session_id = ls_stg-session_id
             group_key  = ls_stg-record_key.
  IF sy-subrc <> 0.
    READ TABLE gt_exec_disp INTO ls_exec
      WITH KEY group_key = ls_stg-record_key.
  ENDIF.
  IF sy-subrc <> 0.
    MESSAGE 'Selected business group has no execution row.' TYPE 'S' DISPLAY LIKE 'E'.
    RETURN.
  ENDIF.

  IF ls_exec-run_status <> 'ERROR'
     AND ls_exec-run_status <> 'WARNING'
     AND ls_exec-run_status <> 'SKIPPED'
     AND ls_exec-run_status <> 'PARTIAL'
     AND ls_exec-run_status <> 'BLOCKED_ONBOARDING'.
    CALL FUNCTION 'POPUP_TO_INFORM'
      EXPORTING
        titel = 'No Fix Guide Required'
        txt1  = 'The selected business group has no runtime issue that requires correction.'
        txt2  = 'Select an ERROR, WARNING, SKIPPED or PARTIAL group.'.
    RETURN.
  ENDIF.

  PERFORM pick_protocol
    USING ls_stg ls_exec
    CHANGING lv_protocol.
  PERFORM classify_issue
    USING ls_exec-run_status lv_protocol space
    CHANGING lv_category lv_summary lv_rule_cause lv_rule_action.

  CLEAR: lv_ai_source, lv_ai_cause, lv_ai_action, lv_ground_field, lv_ai_ok.

 "OBJECT_PROOF_REQUIRED is not an SAP rejection. Do not waste an OpenAI
 "error-analysis call or generate correction advice for a successful replay.
  IF ls_exec-run_status = GC_ST_PARTIAL AND
     ls_exec-message CP 'OBJECT_PROOF_REQUIRED*'.
    lv_ai_source = 'Verified SAP success evidence'.
  ELSE.
 "always analyze the exact current group with direct OpenAI. Do not
 "reuse an older advisory cache as the live Fix Guide analysis.
    PERFORM get_group_ai_advice
      USING    ls_stg lv_protocol
      CHANGING lv_ai_source lv_ai_cause lv_ai_action lv_ground_field lv_ai_ok.
  ENDIF.

  IF ls_exec-run_status = GC_ST_PARTIAL AND
     ls_exec-message CP 'OBJECT_PROOF_REQUIRED*'.
    "No correction fallback is needed for a successful replay awaiting proof.
  ELSEIF lv_ai_ok <> abap_true.
    PERFORM set_ai_fallback_source CHANGING lv_ai_source.
    PERFORM build_evidence_fallback
      USING ls_stg lv_protocol lv_ground_field
      CHANGING lv_ai_cause lv_ai_action.
    lv_rule_cause  = lv_ai_cause.
    lv_rule_action = lv_ai_action.
  ENDIF.

  PERFORM build_fixguide_cards
    USING ls_stg ls_exec lv_protocol lv_category
          lv_rule_cause lv_rule_action
          lv_ai_source lv_ai_cause lv_ai_action lv_ground_field lv_ai_ok.

  gv_fixguide_stg_idx_789 = g_edit_index.
  lv_header = |Fix Guide - { ls_stg-record_key }|.

 "primary surface: render long analysis/action text as real wrapped
 "paragraphs. SALV is retained only as a compatibility fallback.
  CLEAR lv_html_ok.
  PERFORM show_long_cards USING gt_fix_guide_789 lv_header CHANGING lv_html_ok.
  IF lv_html_ok = abap_true.
    RETURN.
  ENDIF.

  TRY.
      CLEAR go_fix_guide_789.
      cl_salv_table=>factory(
        IMPORTING r_salv_table = go_fix_guide_789
        CHANGING  t_table      = gt_fix_guide_789 ).
      go_fix_guide_789->get_display_settings( )->set_list_header( lv_header ).
      go_fix_guide_789->get_functions( )->set_all( abap_true ).

 "Best-effort toolbar action. Some classic SALV popup releases do not
 "support ADD_FUNCTION; the double-click row remains the guaranteed path.
      TRY.
          go_fix_guide_789->get_functions( )->add_function(
            name     = 'ZRUNAI'
            text     = 'Run AI Analysis'
            tooltip  = 'Run direct OpenAI analysis for this exact business group'
            position = if_salv_c_function_position=>left_of_salv_functions ).
        CATCH cx_root.
      ENDTRY.

      IF go_fix_guide_evt_789 IS INITIAL.
        CREATE OBJECT go_fix_guide_evt_789.
      ENDIF.
      DATA(lo_fix_evt_789) = go_fix_guide_789->get_event( ).
      SET HANDLER go_fix_guide_evt_789->on_fixguide_double_click FOR lo_fix_evt_789.
      SET HANDLER go_fix_guide_evt_789->on_fixguide_function FOR lo_fix_evt_789.

      lo_cols = go_fix_guide_789->get_columns( ).
 "columns are sized from real content; no text is pre-wrapped to
 "fit a guessed width. Long values remain on their own row and can scroll.
      lo_cols->set_optimize( abap_true ).
      PERFORM set_salv_col_text USING lo_cols 'SECTION'
        'Section' 'Section' 'Section'.
      PERFORM set_salv_col_text USING lo_cols 'DETAIL'
        'Detail' 'Detail' 'Detail / Explanation'.
      CALL METHOD go_fix_guide_789->set_screen_popup
        EXPORTING
          start_column = 2
          end_column   = 170
          start_line   = 2
          end_line     = 30.
      go_fix_guide_789->display( ).
    CATCH cx_salv_msg INTO lx_salv.
      MESSAGE lx_salv->get_text( ) TYPE 'S' DISPLAY LIKE 'E'.
  ENDTRY.

ENDFORM.

FORM open_0500_error_detail.
 "open a visible modal SALV only for a real runtime issue.
 "Use a safe read-only SALV detail instead of dumping the whole program.
  PERFORM show_issue_detail_safe.
ENDFORM.

FORM open_0500_fix_guide.
 "open a visible modal Fix Guide only when runtime issues exist.
 "The safe Fix Guide keeps preview/export available through SALV functions.
  PERFORM show_fix_guide_safe.
ENDFORM.
* Screen 0700 - Error Analyst / Fix Advisor

*& Screen 0700 is driven by the exact selected ERROR Business Group.

FORM reset_ai_screen.

  REFRESH: gt_patterns, gt_issue_0700.

  CLEAR: txtp_ai_text,
         gv_issue_pick_0700,
         gv_issue_selected_0700,
         gv_ai_selected_root,
         gv_ai_selected_fix,
         gv_ai_selected_verify.

  IF go_container_0700 IS BOUND.
    TRY.
        go_container_0700->free( ).
      CATCH cx_root.
    ENDTRY.
    CLEAR: go_container_0700,
           go_pattern_grid,
           go_issue_evt_0700.
  ENDIF.

  IF go_ai_text_container IS BOUND.
    TRY.
        go_ai_text_container->free( ).
      CATCH cx_root.
    ENDTRY.
    CLEAR: go_ai_text_container,
           go_ai_textedit.
  ENDIF.

ENDFORM.

FORM prepare_ai_session
  USING    iv_session_id TYPE zbdc_result_bup-session_id
  CHANGING cv_ok         TYPE abap_bool.

  DATA: lv_session     TYPE zbdc_result_bup-session_id,
        lt_stage       TYPE STANDARD TABLE OF zbdc_staging_bup,
        ls_stage_issue TYPE zbdc_result_bup,
        lv_has_log     TYPE abap_bool,
        lv_issue_count TYPE i.

  CLEAR cv_ok.

  lv_session = iv_session_id.
  CONDENSE lv_session NO-GAPS.

  IF lv_session IS INITIAL.
    MESSAGE s691(zbdc) DISPLAY LIKE 'W'.
    RETURN.
  ENDIF.

  txtp_ai_session     = lv_session.
  txtp_result_session = lv_session.
  txtp_session_id     = lv_session.
  txtp_sess           = lv_session.

  PERFORM reset_ai_screen.

  REFRESH: gt_result_all,
           gt_result_msg,
           gt_result_summary.

  IF txtp_ai_group IS NOT INITIAL AND txtp_po_key IS NOT INITIAL.
    SELECT *
      FROM zbdc_result_bup
      INTO TABLE @gt_result_all
      WHERE session_id = @lv_session
        AND record_key = @txtp_po_key
      ORDER BY row_index ASCENDING, step ASCENDING.
  ELSEIF txtp_ai_group IS NOT INITIAL
     AND gv_result_row_index_0650 IS NOT INITIAL.
    SELECT *
      FROM zbdc_result_bup
      INTO TABLE @gt_result_all
      WHERE session_id = @lv_session
        AND row_index  = @gv_result_row_index_0650
      ORDER BY row_index ASCENDING, step ASCENDING.
  ELSE.
    SELECT *
      FROM zbdc_result_bup
      INTO TABLE @gt_result_all
      WHERE session_id = @lv_session
      ORDER BY row_index ASCENDING, step ASCENDING.
  ENDIF.

  gt_result_msg = gt_result_all.

  LOOP AT gt_result_all INTO DATA(ls_res_chk)
       WHERE msg_type = 'E' OR msg_type = 'W'.
    lv_has_log = abap_true.
    EXIT.
  ENDLOOP.

  IF lv_has_log = abap_true.
    txtp_ai_source = 'Execution Result Log'.
  ENDIF.

  IF lv_has_log <> abap_true.

    REFRESH lt_stage.
    SELECT *
      FROM zbdc_staging_bup
      INTO TABLE @lt_stage
      WHERE session_id = @lv_session
        AND ( status = @gc_st_error
           OR status = @gc_st_warning
           OR status = 'ERROR'
           OR status = 'WARNING'
           OR status = 'SKIPPED'
           OR status = 'PARTIAL' ).

    IF txtp_ai_group IS NOT INITIAL.
      IF txtp_po_key IS NOT INITIAL.
        DELETE lt_stage WHERE record_key <> txtp_po_key.
      ELSEIF gv_result_row_index_0650 IS NOT INITIAL.
        DELETE lt_stage WHERE row_index <> gv_result_row_index_0650.
      ENDIF.
    ENDIF.

    LOOP AT lt_stage INTO DATA(ls_stage).
      CLEAR ls_stage_issue.
      ls_stage_issue-session_id = ls_stage-session_id.
      ls_stage_issue-record_key = ls_stage-record_key.
      ls_stage_issue-row_index  = ls_stage-row_index.
      ls_stage_issue-tcode      = ls_stage-tcode.
      ls_stage_issue-msg_type   = 'E'.
      ls_stage_issue-field_name = 'STAGING'.
      ls_stage_issue-message    = ls_stage-error_msg.
      IF ls_stage_issue-message IS INITIAL.
        ls_stage_issue-message = ls_stage-last_error.
      ENDIF.
      IF ls_stage_issue-message IS INITIAL.
        ls_stage_issue-message = |Staging status { ls_stage-status } requires correction.|.
      ENDIF.

      "15F: keep STAGING as a neutral source marker here. A staging error can
      "contain several independent field errors in one persisted string. Field
      "identity is therefore derived only AFTER SPLIT_ISSUE_MESSAGE_0700 has
      "separated each fragment; deriving it here would incorrectly stamp the
      "first field onto every subsequent issue.
      APPEND ls_stage_issue TO gt_result_all.
    ENDLOOP.

    gt_result_msg = gt_result_all.

    IF lt_stage IS NOT INITIAL.
      txtp_ai_source = 'Staging Validation'.
    ENDIF.

  ENDIF.

  CLEAR lv_issue_count.
  LOOP AT gt_result_all INTO DATA(ls_res_issue)
       WHERE msg_type = 'E' OR msg_type = 'W'.
    cv_ok = abap_true.
    lv_issue_count = lv_issue_count + 1.
  ENDLOOP.

  IF txtp_ai_group IS NOT INITIAL.
    IF cv_ok = abap_true.
      txtp_ai_evidence = |{ lv_issue_count } issue(s)|.
      txtp_ai_text =
        |ERROR group loaded: { txtp_ai_group } / Session { lv_session }.| &&
        cl_abap_char_utilities=>newline &&
        |Exact persisted evidence is normalized into Issues Found.| &&
        cl_abap_char_utilities=>newline &&
        |Select an issue for deterministic diagnosis; use AI Analysis only for supplemental evidence-grounded guidance.|.
    ELSE.
      txtp_ai_evidence = 'No evidence'.
      txtp_ai_text =
        |ERROR group loaded: { txtp_ai_group } / Session { lv_session }.| &&
        cl_abap_char_utilities=>newline &&
        |No persisted ERROR/WARNING evidence is available for this exact group.|.
    ENDIF.
  ELSEIF cv_ok = abap_true.
    txtp_ai_evidence = |{ lv_issue_count } issue(s)|.
    txtp_ai_text =
      |AI Error Diagnostic is currently scoped to Session { lv_session }.| &&
      cl_abap_char_utilities=>newline &&
      |Use Result Investigation to select one ERROR Business Group for exact-group analysis.|.
  ELSE.
    txtp_ai_evidence = 'No evidence'.
    txtp_ai_text =
      |No ERROR/WARNING evidence is available for Session { lv_session }.|.
  ENDIF.

ENDFORM.

FORM prepare_ai_current
  CHANGING cv_ok TYPE abap_bool.

  DATA lv_session TYPE zbdc_result_bup-session_id.

  CLEAR cv_ok.

  IF txtp_ai_session IS NOT INITIAL.
    lv_session = txtp_ai_session.
  ELSEIF txtp_result_session IS NOT INITIAL.
    lv_session = txtp_result_session.
  ELSEIF txtp_session_id IS NOT INITIAL.
    lv_session = txtp_session_id.
  ELSE.
    READ TABLE gt_staging INTO DATA(ls_stg_ai_current) INDEX 1.
    IF sy-subrc = 0.
      lv_session = ls_stg_ai_current-session_id.
    ENDIF.
  ENDIF.

  IF lv_session IS INITIAL.
    PERFORM pick_ai_error_session CHANGING lv_session.
  ENDIF.

  IF lv_session IS INITIAL.
    MESSAGE s680(zbdc) DISPLAY LIKE 'W'.
    RETURN.
  ENDIF.

  PERFORM prepare_ai_session
    USING    lv_session
    CHANGING cv_ok.

ENDFORM.

FORM pick_ai_error_session
  CHANGING cv_session_id TYPE zbdc_result_bup-session_id.

  TYPES: BEGIN OF ty_z71_pick,
           session_id TYPE zbdc_result_bup-session_id,
           tcode      TYPE char20,
           status     TYPE char20,
           message    TYPE char255,
         END OF ty_z71_pick.

  DATA: lt_pick TYPE STANDARD TABLE OF ty_z71_pick,
        ls_pick TYPE ty_z71_pick,
        lt_ret  TYPE STANDARD TABLE OF ddshretval,
        ls_ret  TYPE ddshretval,
        lt_res  TYPE STANDARD TABLE OF zbdc_result_bup,
        lt_stg  TYPE STANDARD TABLE OF zbdc_staging_bup.

  CLEAR cv_session_id.
  REFRESH: lt_pick, lt_ret, lt_res, lt_stg.

  SELECT *
    FROM zbdc_result_bup
    INTO TABLE @lt_res
    WHERE msg_type = 'E'
       OR msg_type = 'W'.

  SORT lt_res BY created_at DESCENDING.
  DELETE lt_res FROM 301.

  LOOP AT lt_res INTO DATA(ls_res).
    IF ls_res-session_id IS INITIAL.
      CONTINUE.
    ENDIF.
    READ TABLE lt_pick TRANSPORTING NO FIELDS
      WITH KEY session_id = ls_res-session_id.
    IF sy-subrc = 0.
      CONTINUE.
    ENDIF.
    CLEAR ls_pick.
    ls_pick-session_id = ls_res-session_id.
    ls_pick-tcode      = ls_res-tcode.
    ls_pick-status     = ls_res-msg_type.
    ls_pick-message    = ls_res-message.
    APPEND ls_pick TO lt_pick.
  ENDLOOP.

  SELECT *
    FROM zbdc_staging_bup
    INTO TABLE @lt_stg
    WHERE status = @gc_st_error
       OR status = @gc_st_warning
       OR status = 'ERROR'
       OR status = 'WARNING'
       OR status = 'SKIPPED'
       OR status = 'PARTIAL'.

  SORT lt_stg BY session_id row_index.

  LOOP AT lt_stg INTO DATA(ls_stg).
    IF ls_stg-session_id IS INITIAL.
      CONTINUE.
    ENDIF.
    READ TABLE lt_pick TRANSPORTING NO FIELDS
      WITH KEY session_id = ls_stg-session_id.
    IF sy-subrc = 0.
      CONTINUE.
    ENDIF.
    CLEAR ls_pick.
    ls_pick-session_id = ls_stg-session_id.
    ls_pick-tcode      = ls_stg-tcode.
    ls_pick-status     = ls_stg-status.
    ls_pick-message    = ls_stg-error_msg.
    IF ls_pick-message IS INITIAL.
      ls_pick-message = ls_stg-last_error.
    ENDIF.
    APPEND ls_pick TO lt_pick.
  ENDLOOP.

  IF lt_pick IS INITIAL.
    MESSAGE s681(zbdc) DISPLAY LIKE 'W'.
    RETURN.
  ENDIF.

  CALL FUNCTION 'F4IF_INT_TABLE_VALUE_REQUEST'
    EXPORTING
      retfield        = 'SESSION_ID'
      dynpprog        = sy-repid
      dynpnr          = sy-dynnr
      value_org       = 'S'
      window_title    = 'Choose ERROR session for AI Log'
    TABLES
      value_tab       = lt_pick
      return_tab      = lt_ret
    EXCEPTIONS
      parameter_error = 1
      no_values_found = 2
      OTHERS          = 3.

  IF sy-subrc <> 0.
    RETURN.
  ENDIF.

  READ TABLE lt_ret INTO ls_ret INDEX 1.
  IF sy-subrc = 0 AND ls_ret-fieldval IS NOT INITIAL.
    cv_session_id = ls_ret-fieldval.
    CONDENSE cv_session_id.
  ENDIF.

ENDFORM.

*&---------------------------------------------------------------------*
*&---------------------------------------------------------------------*
*& Normalize one persisted message into independent user-facing issues.
*& The split is generic: persisted delimiters/new lines first, plus common
*& sentence boundaries where another "Value ..." error starts.
*&---------------------------------------------------------------------*
FORM split_issue_message_0700
  USING    iv_message TYPE csequence
  CHANGING ct_parts   TYPE ty_t_string_0700.

  DATA: lv_work     TYPE string,
        lv_part     TYPE string,
        lv_part_up  TYPE string,
        lv_last_idx TYPE i,
        lt_clean    TYPE ty_t_string_0700.

  REFRESH: ct_parts, lt_clean.
  lv_work = iv_message.

  REPLACE ALL OCCURRENCES OF cl_abap_char_utilities=>cr_lf
    IN lv_work WITH ';'.
  REPLACE ALL OCCURRENCES OF cl_abap_char_utilities=>newline
    IN lv_work WITH ';'.

  "Some validation producers persist several independent errors in one
  "message string. Create an explicit boundary without hardcoding a field
  "or transaction when a new Value sentence starts.
  REPLACE ALL OCCURRENCES OF `. Value "` IN lv_work WITH `.;Value "`.
  REPLACE ALL OCCURRENCES OF `. Value '` IN lv_work WITH `.;Value '`.
  REPLACE ALL OCCURRENCES OF `. value "` IN lv_work WITH `.;value "`.
  REPLACE ALL OCCURRENCES OF `. value '` IN lv_work WITH `.;value '`.
  REPLACE ALL OCCURRENCES OF `. Missing ` IN lv_work WITH `.;Missing `.
  REPLACE ALL OCCURRENCES OF `. missing ` IN lv_work WITH `.;missing `.
  REPLACE ALL OCCURRENCES OF `. Required ` IN lv_work WITH `.;Required `.
  REPLACE ALL OCCURRENCES OF `. required ` IN lv_work WITH `.;required `.

  SPLIT lv_work AT ';' INTO TABLE ct_parts.

  LOOP AT ct_parts INTO lv_part.
    CONDENSE lv_part.
    IF lv_part IS INITIAL.
      CONTINUE.
    ENDIF.

    lv_part_up = lv_part.
    TRANSLATE lv_part_up TO UPPER CASE.

    IF lt_clean IS INITIAL
       OR lv_part_up CP 'VALUE *'
       OR lv_part_up CP 'FIELD *'
       OR lv_part_up CP 'ENTER *'
       OR lv_part_up CP 'ERROR *'
       OR lv_part_up CP 'INVALID *'
       OR lv_part_up CP 'NO *'
       OR lv_part_up CP 'MANDATORY *'
       OR lv_part_up CP 'REQUIRED *'
       OR lv_part_up CP 'MISSING *'.
      APPEND lv_part TO lt_clean.
    ELSE.
      "A semicolon can also be explanatory punctuation inside one SAP error.
      "Merge non-issue continuations back into the previous fragment.
      lv_last_idx = lines( lt_clean ).
      READ TABLE lt_clean ASSIGNING FIELD-SYMBOL(<lv_last_part>)
        INDEX lv_last_idx.
      IF sy-subrc = 0.
        <lv_last_part> =
          <lv_last_part> && `; ` && lv_part.
      ENDIF.
    ENDIF.
  ENDLOOP.
  ct_parts = lt_clean.

  IF ct_parts IS INITIAL AND lv_work IS NOT INITIAL.
    APPEND lv_work TO ct_parts.
  ENDIF.

ENDFORM.

*&---------------------------------------------------------------------*
*& Derive field/current value from the exact issue fragment.
*& Parsed evidence wins; DDIC/result FIELD_NAME is only a fallback.
*& No TCode/field hardcoding.
*&---------------------------------------------------------------------*
FORM derive_issue_context_0700
  USING    iv_message        TYPE csequence
           iv_existing_field TYPE csequence
  CHANGING cv_field          TYPE char40
           cv_current_value  TYPE char120.

  DATA: lv_msg       TYPE string,
        lv_upper     TYPE string,
        lv_after     TYPE string,
        lv_after_up  TYPE string,
        lv_token     TYPE string,
        lv_rest      TYPE string,
        lv_off       TYPE i,
        lv_end       TYPE i,
        lv_start     TYPE i.

  CLEAR: cv_field, cv_current_value.
  lv_msg = iv_message.
  IF lv_msg IS INITIAL.
    IF iv_existing_field IS NOT INITIAL
       AND iv_existing_field <> 'STAGING'
       AND iv_existing_field <> '-'.
      cv_field = iv_existing_field.
    ENDIF.
    RETURN.
  ENDIF.

  lv_upper = lv_msg.
  TRANSLATE lv_upper TO UPPER CASE.

  "Current value: expose only when exact persisted wording proves it.
  FIND FIRST OCCURRENCE OF `VALUE "` IN lv_upper MATCH OFFSET lv_off.
  IF sy-subrc = 0.
    lv_start = lv_off + 7.
    IF lv_start < strlen( lv_msg ).
      lv_after = lv_msg+lv_start.
      FIND FIRST OCCURRENCE OF `"` IN lv_after MATCH OFFSET lv_end.
      IF sy-subrc = 0 AND lv_end > 0.
        cv_current_value = lv_after(lv_end).
      ENDIF.
    ENDIF.
  ELSE.
    FIND FIRST OCCURRENCE OF `VALUE '` IN lv_upper MATCH OFFSET lv_off.
    IF sy-subrc = 0.
      lv_start = lv_off + 7.
      IF lv_start < strlen( lv_msg ).
        lv_after = lv_msg+lv_start.
        FIND FIRST OCCURRENCE OF `'` IN lv_after MATCH OFFSET lv_end.
        IF sy-subrc = 0 AND lv_end > 0.
          cv_current_value = lv_after(lv_end).
        ENDIF.
      ENDIF.
    ENDIF.
  ENDIF.

  "Field: first use the exact fragment wording "... for <FIELD> ...".
  CLEAR: lv_after, lv_after_up, lv_token, lv_rest.
  FIND FIRST OCCURRENCE OF ' FOR ' IN lv_upper MATCH OFFSET lv_off.
  IF sy-subrc = 0.
    lv_start = lv_off + 5.
    IF lv_start < strlen( lv_msg ).
      lv_after = lv_msg+lv_start.
      lv_after_up = lv_after.
      TRANSLATE lv_after_up TO UPPER CASE.

      IF strlen( lv_after_up ) >= 10
         AND lv_after_up+0(10) = 'THE FIELD '.
        lv_after = lv_after+10.
      ELSEIF strlen( lv_after_up ) >= 6
         AND lv_after_up+0(6) = 'FIELD '.
        lv_after = lv_after+6.
      ENDIF.

      SPLIT lv_after AT space INTO lv_token lv_rest.
    ENDIF.
  ENDIF.

  "Fallback wording "Field <FIELD> ...".
  IF lv_token IS INITIAL.
    FIND FIRST OCCURRENCE OF 'FIELD ' IN lv_upper MATCH OFFSET lv_off.
    IF sy-subrc = 0.
      lv_start = lv_off + 6.
      IF lv_start < strlen( lv_msg ).
        lv_after = lv_msg+lv_start.
        SPLIT lv_after AT space INTO lv_token lv_rest.
      ENDIF.
    ENDIF.
  ENDIF.

  "Validation shorthand commonly persists one issue per token, for example
  ""Missing <FIELD_A>" or "Missing <FIELD_B>". Parse that field from
  "the exact fragment instead of falling back to the first field stored on a
  "compound staging message. No business-field name is hardcoded.
  IF lv_token IS INITIAL AND lv_upper CP 'MISSING MANDATORY FIELD *'.
    lv_after = lv_msg+24.
    SPLIT lv_after AT space INTO lv_token lv_rest.
  ELSEIF lv_token IS INITIAL AND lv_upper CP 'MISSING FIELD *'.
    lv_after = lv_msg+14.
    SPLIT lv_after AT space INTO lv_token lv_rest.
  ELSEIF lv_token IS INITIAL AND lv_upper CP 'MISSING *'.
    lv_after = lv_msg+8.
    SPLIT lv_after AT space INTO lv_token lv_rest.
  ENDIF.

  IF lv_token IS NOT INITIAL.
    REPLACE ALL OCCURRENCES OF `"` IN lv_token WITH ``.
    REPLACE ALL OCCURRENCES OF `'` IN lv_token WITH ``.
    REPLACE ALL OCCURRENCES OF `:` IN lv_token WITH ``.
    REPLACE ALL OCCURRENCES OF `,` IN lv_token WITH ``.
    REPLACE ALL OCCURRENCES OF `.` IN lv_token WITH ``.
    REPLACE ALL OCCURRENCES OF `;` IN lv_token WITH ``.
    REPLACE ALL OCCURRENCES OF `(` IN lv_token WITH ``.
    REPLACE ALL OCCURRENCES OF `)` IN lv_token WITH ``.
    CONDENSE lv_token NO-GAPS.

    IF lv_token IS NOT INITIAL
       AND strlen( lv_token ) <= 40
       AND lv_token <> 'SAP'
       AND lv_token <> 'THE'
       AND lv_token <> 'A'
       AND lv_token <> 'AN'.
      cv_field = lv_token.
    ENDIF.
  ENDIF.

  "Only now use the persisted technical field as a fallback. This prevents
  "the first field in a compound error from being incorrectly assigned to
  "the second issue.
  IF cv_field IS INITIAL
     AND iv_existing_field IS NOT INITIAL
     AND iv_existing_field <> 'STAGING'
     AND iv_existing_field <> '-'.
    cv_field = iv_existing_field.
  ENDIF.

ENDFORM.

*&---------------------------------------------------------------------*
*& Extract a numeric length only when the exact persisted text proves it.
*&---------------------------------------------------------------------*
FORM derive_issue_length_0700
  USING    iv_message TYPE csequence
  CHANGING cv_length  TYPE char20.

  DATA: lv_upper TYPE string,
        lv_after TYPE string,
        lv_token TYPE string,
        lv_rest  TYPE string,
        lv_off   TYPE i,
        lv_start TYPE i.

  CLEAR cv_length.
  lv_upper = iv_message.
  TRANSLATE lv_upper TO UPPER CASE.

  FIND FIRST OCCURRENCE OF 'CONFIGURED LENGTH ' IN lv_upper
    MATCH OFFSET lv_off.
  IF sy-subrc = 0.
    lv_start = lv_off + 18.
  ELSE.
    FIND FIRST OCCURRENCE OF 'MAXIMUM LENGTH ' IN lv_upper
      MATCH OFFSET lv_off.
    IF sy-subrc = 0.
      lv_start = lv_off + 15.
    ELSE.
      FIND FIRST OCCURRENCE OF 'MAX LENGTH ' IN lv_upper
        MATCH OFFSET lv_off.
      IF sy-subrc = 0.
        lv_start = lv_off + 11.
      ELSE.
        RETURN.
      ENDIF.
    ENDIF.
  ENDIF.

  IF lv_start < strlen( lv_upper ).
    lv_after = lv_upper+lv_start.
    SPLIT lv_after AT space INTO lv_token lv_rest.
    REPLACE ALL OCCURRENCES OF `.` IN lv_token WITH ``.
    REPLACE ALL OCCURRENCES OF `,` IN lv_token WITH ``.
    REPLACE ALL OCCURRENCES OF `;` IN lv_token WITH ``.
    REPLACE ALL OCCURRENCES OF `)` IN lv_token WITH ``.
    CONDENSE lv_token NO-GAPS.
    IF lv_token IS NOT INITIAL AND lv_token CO '0123456789'.
      cv_length = lv_token.
    ENDIF.
  ENDIF.

ENDFORM.

*&---------------------------------------------------------------------*
*& Deterministic, user-friendly issue classification and summary.
*&---------------------------------------------------------------------*

FORM derive_val_rule_0700
  USING    iv_message TYPE csequence
  CHANGING cv_rule    TYPE char40.
  DATA: lv_msg TYPE string, lv_upper TYPE string, lv_after TYPE string,
        lv_after_up TYPE string, lv_off TYPE i, lv_end TYPE i, lv_start TYPE i.
  CLEAR cv_rule.
  lv_msg = iv_message.
  IF lv_msg IS INITIAL. RETURN. ENDIF.
  lv_upper = lv_msg. TRANSLATE lv_upper TO UPPER CASE.
  FIND FIRST OCCURRENCE OF 'INVALID ' IN lv_upper MATCH OFFSET lv_off.
  IF sy-subrc <> 0. RETURN. ENDIF.
  lv_start = lv_off + 8.
  IF lv_start >= strlen( lv_msg ). RETURN. ENDIF.
  lv_after = lv_msg+lv_start.
  lv_after_up = lv_after. TRANSLATE lv_after_up TO UPPER CASE.
  FIND FIRST OCCURRENCE OF ' VALUE' IN lv_after_up MATCH OFFSET lv_end.
  IF sy-subrc <> 0 OR lv_end <= 0. RETURN. ENDIF.
  cv_rule = lv_after(lv_end).
  CONDENSE cv_rule.
  TRANSLATE cv_rule TO UPPER CASE.
ENDFORM.

FORM classify_issue_0700
  USING    iv_message TYPE csequence
           iv_value   TYPE csequence
           iv_length  TYPE csequence
           iv_field   TYPE csequence
           iv_source  TYPE csequence
  CHANGING cv_category TYPE char20
           cv_summary  TYPE char120.

  DATA: lv_text   TYPE string,
        lv_val    TYPE string,
        lv_field  TYPE string,
        lv_source TYPE string,
        lv_rule   TYPE char40.

  CLEAR: cv_category, cv_summary.

  lv_text = iv_message.
  TRANSLATE lv_text TO UPPER CASE.
  lv_val = iv_value.
  lv_field = iv_field.
  lv_source = iv_source.
  TRANSLATE lv_source TO UPPER CASE.

  "Strict evidence classifier:
  "Assign a specific category only when the persisted text itself proves it.
  "Earlier broad checks such as MISSING / QUEUE / DOES NOT EXIST alone caused
  "false positives and are deliberately not used here.

  IF ( lv_text CS 'SM35 SESSION'
       AND ( lv_text CS ' IS INCORRECT'
             OR lv_text CS ' STATUS INCORRECT'
             OR lv_text CS ' ENDED INCORRECT'
             OR lv_text CS ' COMPLETED WITH ERRORS' ) )
     OR lv_text CS 'EXACT PER-TRANSACTION PROTOCOL IS NOT CURRENTLY AVAILABLE'.
    cv_category = 'SM35_SESSION'.
    cv_summary  = 'SM35 session status is Incorrect'.

  ELSEIF lv_text CS 'LONGER THAN CONFIGURED LENGTH'
      OR lv_text CS 'LONGER THAN MAXIMUM LENGTH'
      OR lv_text CS 'EXCEEDS THE ALLOWED FIELD LENGTH'
      OR lv_text CS 'EXCEEDS ALLOWED FIELD LENGTH'
      OR lv_text CS 'LENGTH EXCEEDED'
      OR lv_text CS 'VALUE TOO LONG'
      OR lv_text CS 'FIELD VALUE TOO LONG'.
    cv_category = 'LENGTH'.
    IF iv_length IS NOT INITIAL.
      cv_summary =
        |Value exceeds the allowed field length ({ iv_length } characters)|.
    ELSE.
      cv_summary = 'Value exceeds the allowed field length'.
    ENDIF.

  ELSEIF lv_text CS 'VALUE-HELP'
      OR ( lv_text CS 'DDIC' AND lv_text CS 'RESOLV' )
      OR ( lv_text CS 'CHECK TABLE'
           AND ( lv_text CS 'NOT FOUND'
                 OR lv_text CS 'DOES NOT EXIST'
                 OR lv_text CS 'INVALID' ) )
      OR ( lv_text CS 'MASTER DATA'
           AND ( lv_text CS 'NOT FOUND'
                 OR lv_text CS 'DOES NOT EXIST'
                 OR lv_text CS 'INVALID' ) ).
    cv_category = 'REFERENCE'.
    IF lv_val IS NOT INITIAL.
      cv_summary = 'SAP reference/value-help resolution failed'.
    ELSE.
      cv_summary = 'SAP reference/value-help resolution failed'.
    ENDIF.

  ELSEIF lv_text CS 'NOT AUTHORIZED'
      OR lv_text CS 'NO AUTHORIZATION'
      OR lv_text CS 'AUTHORIZATION CHECK FAILED'
      OR lv_text CS 'LACKS AUTHORIZATION'
      OR lv_text CS 'MISSING AUTHORIZATION'.
    cv_category = 'AUTH'.
    cv_summary  = 'SAP authorization error reported'.

  ELSEIF lv_text CS 'ENQUEUE'
      OR lv_text CS 'LOCKED BY'
      OR lv_text CS ' IS LOCKED'
      OR lv_text CS 'LOCK REQUEST'
      OR lv_text CS 'OBJECT LOCKED'.
    cv_category = 'LOCK'.
    cv_summary  = 'SAP lock/enqueue error reported'.

  ELSEIF lv_text CS 'TIMEOUT'
      OR lv_text CS 'TIME OUT'
      OR lv_text CS 'TIME LIMIT EXCEEDED'
      OR lv_text CS 'RUNTIME LIMIT EXCEEDED'.
    cv_category = 'TIMEOUT'.
    cv_summary  = 'SAP timeout/time-limit error reported'.

  ELSEIF lv_text CS 'BATCH INPUT DATA FOR SCREEN'
      OR lv_text CS 'NO BATCH INPUT DATA FOR SCREEN'
      OR ( lv_text CS 'DYNPRO' AND lv_text CS 'DOES NOT EXIST' )
      OR lv_text CS 'SCREEN DOES NOT EXIST'
      OR lv_text CS 'FIELD DOES NOT EXIST IN THE SCREEN'
      OR lv_text CS 'FIELD NOT FOUND ON SCREEN'.
    cv_category = 'RECORDING'.
    cv_summary  = 'BDC screen/field flow mismatch reported'.

  ELSEIF lv_text CS 'MISSING MANDATORY FIELD'
      OR lv_text CS 'MISSING REQUIRED FIELD'
      OR lv_text CS 'MANDATORY FIELD IS MISSING'
      OR lv_text CS 'REQUIRED FIELD IS MISSING'
      OR lv_text CS 'MUST BE ENTERED'
      OR lv_text CS 'MUST NOT BE EMPTY'
      OR lv_text CS 'MAY NOT BE EMPTY'
      OR lv_text CS ' IS REQUIRED'.
    cv_category = 'REQUIRED'.
    IF lv_field IS NOT INITIAL AND lv_field <> '-'.
      cv_summary = |Required value is missing for { lv_field }|.
    ELSE.
      cv_summary = 'A required value is missing'.
    ENDIF.

  ELSEIF lv_text CS 'INVALID '
      AND lv_text CS ' VALUE'
      AND lv_field IS NOT INITIAL
      AND lv_val IS NOT INITIAL.
    CLEAR lv_rule.
    PERFORM derive_val_rule_0700 USING iv_message CHANGING lv_rule.
    cv_category = 'INVALID_VALUE'.
    IF lv_rule IS NOT INITIAL.
      cv_summary = |Invalid { lv_rule } value "{ lv_val }" for { lv_field }|.
    ELSE.
      cv_summary = |Invalid value "{ lv_val }" for { lv_field }|.
    ENDIF.

  ELSEIF lv_text CS 'CANNOT BE CONVERTED'
      OR lv_text CS 'CONVERSION ERROR'
      OR lv_text CS 'CONVERSION FAILED'
      OR lv_text CS 'INVALID DATE'
      OR lv_text CS 'INVALID NUMBER'
      OR lv_text CS 'INVALID FORMAT'
      OR lv_text CS 'FORMAT IS INVALID'.
    cv_category = 'FORMAT'.
    IF lv_field IS NOT INITIAL AND lv_val IS NOT INITIAL.
      cv_summary = |Invalid format/value "{ lv_val }" for { lv_field }|.
    ELSEIF lv_field IS NOT INITIAL.
      cv_summary = |Invalid format/value for { lv_field }|.
    ELSE.
      cv_summary = 'SAP conversion/format error reported'.
    ENDIF.

  ELSEIF lv_text CS 'NO SAP EXECUTION EVIDENCE WAS PERSISTED'
      OR lv_text CS 'EXACT EXECUTION EVIDENCE IS UNAVAILABLE'
      OR lv_text CS 'DETAILED EXECUTION EVIDENCE IS UNAVAILABLE'.
    cv_category = 'EXEC_UNSPEC'.
    cv_summary  = 'Execution error recorded; detailed SAP evidence is unavailable'.

  ELSEIF lv_source CS 'STAGING' OR lv_source CS 'VALIDATION'.
    cv_category = 'VALIDATION_UNSPEC'.
    cv_summary  = 'Validation error recorded; exact cause is not proven'.

  ELSEIF lv_source CS 'EXECUTION'
      OR lv_source CS 'RESULT LOG'
      OR lv_source CS 'SAP LOG'
      OR lv_source CS 'SM35'.
    cv_category = 'EXEC_UNSPEC'.
    cv_summary  = 'Execution error recorded; exact cause is not proven'.

  ELSE.
    cv_category = 'EVIDENCE_UNSPEC'.
    cv_summary  = 'Error recorded; exact cause is not proven'.
  ENDIF.

ENDFORM.

*&---------------------------------------------------------------------*
*& Evidence-grounded root cause + practical fix steps.
*&---------------------------------------------------------------------*
FORM get_issue_guidance_0700
  USING    is_issue TYPE ty_issue_0700_disp
  CHANGING cv_root   TYPE string
           cv_fix    TYPE string
           cv_verify TYPE string.

  DATA: lv_field TYPE string,
        lv_rule  TYPE char40.

  CLEAR: cv_root, cv_fix, cv_verify.
  lv_field = is_issue-field_name.
  IF lv_field IS INITIAL OR lv_field = '-'.
    CLEAR lv_field.
  ENDIF.

  CASE is_issue-category.
    WHEN 'INVALID_VALUE'.
      CLEAR lv_rule.
      PERFORM derive_val_rule_0700 USING is_issue-issue_message CHANGING lv_rule.
      IF lv_field IS NOT INITIAL AND is_issue-current_value IS NOT INITIAL AND lv_rule IS NOT INITIAL.
        cv_root = |The persisted validation evidence proves that "{ is_issue-current_value }" is not accepted for { lv_field } under the { lv_rule } validation rule.|.
        cv_fix = |1. Open Edit Staging for { txtp_ai_group }.| && cl_abap_char_utilities=>newline &&
                 |2. Replace "{ is_issue-current_value }" in { lv_field } with the intended value that satisfies the validated { lv_rule } rule.| && cl_abap_char_utilities=>newline &&
                 |3. Save/apply the correction.| && cl_abap_char_utilities=>newline &&
                 |4. Run validation again.| && cl_abap_char_utilities=>newline &&
                 |5. Retry execution only after validation succeeds.|.
        cv_verify = |Confirm { lv_field } no longer returns the same invalid { lv_rule } value error.|.
      ELSEIF lv_field IS NOT INITIAL AND is_issue-current_value IS NOT INITIAL.
        cv_root = |The persisted validation evidence proves that "{ is_issue-current_value }" is rejected for { lv_field }; the exact validator rule name is not available in the persisted message.|.
        cv_fix = |1. Open Edit Staging for { txtp_ai_group }.| && cl_abap_char_utilities=>newline &&
                 |2. Correct { lv_field } using the intended business value and the exact validation evidence.| && cl_abap_char_utilities=>newline &&
                 |3. Save/apply the correction and run validation again.|.
        cv_verify = |Confirm the same rejected value no longer appears for { lv_field }.|.
      ELSE.
        cv_root = 'The persisted validation message proves an invalid-value condition, but it does not safely identify both the affected field and rejected value.'.
        cv_fix = |1. Review the exact validation message and field evidence.| && cl_abap_char_utilities=>newline &&
                 |2. Correct data only after the affected field/value is proven.| && cl_abap_char_utilities=>newline &&
                 |3. Run validation again.|.
        cv_verify = 'Confirm stronger field/value evidence exists before applying a specific correction.'.
      ENDIF.

    WHEN 'LENGTH'.
      IF lv_field IS NOT INITIAL AND is_issue-allowed_length IS NOT INITIAL.
        cv_root =
          |The persisted evidence proves that the supplied value exceeds the allowed length of { is_issue-allowed_length } characters for { lv_field }.|.
        cv_fix =
          |1. Open Edit Staging for { txtp_ai_group }.| &&
          cl_abap_char_utilities=>newline &&
          |2. Correct { lv_field }.| &&
          cl_abap_char_utilities=>newline &&
          |3. Keep the corrected value within { is_issue-allowed_length } characters.| &&
          cl_abap_char_utilities=>newline &&
          |4. Save and run validation again.| &&
          cl_abap_char_utilities=>newline &&
          |5. Retry only after validation succeeds.|.
      ELSEIF lv_field IS NOT INITIAL.
        cv_root =
          |The persisted evidence proves a field-length violation for { lv_field }, but it does not prove a numeric maximum length.|.
        cv_fix =
          |1. Open Edit Staging for { txtp_ai_group }.| &&
          cl_abap_char_utilities=>newline &&
          |2. Correct { lv_field } using verified SAP field metadata.| &&
          cl_abap_char_utilities=>newline &&
          |3. Save and validate again before retrying.|.
      ELSE.
        cv_root =
          'The persisted evidence proves a field-length violation, but it does not safely identify the affected field.'.
        cv_fix =
          |1. Review the exact error and verified mapping metadata.| &&
          cl_abap_char_utilities=>newline &&
          |2. Correct only the source value that the evidence can tie to this length error.| &&
          cl_abap_char_utilities=>newline &&
          |3. Validate again before retrying.|.
      ENDIF.
      cv_verify =
        'Confirm the same length error no longer appears after validation/execution.'.

    WHEN 'REFERENCE'.
      IF lv_field IS NOT INITIAL.
        cv_root =
          |The persisted evidence proves that SAP DDIC/value-help/reference data could not resolve the supplied value for { lv_field }.|.
        cv_fix =
          |1. Open Edit Staging for { txtp_ai_group }.| &&
          cl_abap_char_utilities=>newline &&
          |2. Check the value entered for { lv_field }.| &&
          cl_abap_char_utilities=>newline &&
          |3. Replace it only with a value verified by SAP value-help/F4, check-table, or master data.| &&
          cl_abap_char_utilities=>newline &&
          |4. Save and validate again before retrying.|.
      ELSE.
        cv_root =
          'The persisted evidence proves a SAP reference-data/value-help resolution failure, but it does not safely identify the affected field.'.
        cv_fix =
          |1. Review the exact error and SAP value-help/reference evidence.| &&
          cl_abap_char_utilities=>newline &&
          |2. Change data only after the affected field and accepted value are verified.| &&
          cl_abap_char_utilities=>newline &&
          |3. Validate again before retrying.|.
      ENDIF.
      cv_verify =
        'Confirm SAP validation/reference lookup accepts the corrected value and the same error no longer appears.'.

    WHEN 'REQUIRED'.
      IF lv_field IS NOT INITIAL.
        cv_root =
          |The persisted evidence explicitly states that { lv_field } is mandatory/required and no acceptable value was supplied.|.
        cv_fix =
          |1. Open Edit Staging for { txtp_ai_group }.| &&
          cl_abap_char_utilities=>newline &&
          |2. Enter a valid value for { lv_field }.| &&
          cl_abap_char_utilities=>newline &&
          |3. Save and run validation again.| &&
          cl_abap_char_utilities=>newline &&
          |4. Retry only after validation succeeds.|.
      ELSE.
        cv_root =
          'The persisted evidence explicitly states that a required value is missing, but it does not safely identify the technical field.'.
        cv_fix =
          |1. Review the exact validation/SAP message.| &&
          cl_abap_char_utilities=>newline &&
          |2. Identify the required field from verified screen/mapping metadata before changing data.| &&
          cl_abap_char_utilities=>newline &&
          |3. Validate again before retrying.|.
      ENDIF.
      cv_verify =
        'Confirm the required-value error no longer appears after validation.'.

    WHEN 'FORMAT'.
      IF lv_field IS NOT INITIAL.
        cv_root =
          |The persisted evidence explicitly reports a conversion/format rejection for { lv_field }.|.
      ELSE.
        cv_root =
          'The persisted evidence explicitly reports a conversion/format rejection, but it does not safely identify the affected field.'.
      ENDIF.
      cv_fix =
        |1. Review the exact rejected value and verified SAP field metadata.| &&
        cl_abap_char_utilities=>newline &&
        |2. Correct only the proven format/conversion issue.| &&
        cl_abap_char_utilities=>newline &&
        |3. Validate again before retrying.|.
      cv_verify =
        'Confirm the same conversion/format error no longer appears.'.

    WHEN 'AUTH'.
      cv_root =
        'The persisted SAP message explicitly proves that an authorization check failed.'.
      cv_fix =
        |1. Do not change business data to bypass the error.| &&
        cl_abap_char_utilities=>newline &&
        |2. Have the SAP authorization owner verify the required access using the exact SAP message/log.| &&
        cl_abap_char_utilities=>newline &&
        |3. Retry the same group only after authorization is corrected.|.
      cv_verify =
        'Confirm the same transaction can run without the authorization error for the intended user.'.

    WHEN 'LOCK'.
      cv_root =
        'The persisted SAP message explicitly proves that a lock/enqueue condition prevented processing.'.
      cv_fix =
        |1. Keep the business data unchanged unless separate evidence proves a data problem.| &&
        cl_abap_char_utilities=>newline &&
        |2. Identify the exact lock owner/object from SAP lock evidence before releasing anything.| &&
        cl_abap_char_utilities=>newline &&
        |3. Retry after the proven lock condition is cleared.|.
      cv_verify =
        'Confirm the retry no longer returns the same lock/enqueue message.'.

    WHEN 'TIMEOUT'.
      cv_root =
        'The persisted SAP message explicitly proves that execution exceeded a timeout/time-limit condition.'.
      cv_fix =
        |1. Do not alter business values unless another error proves a data issue.| &&
        cl_abap_char_utilities=>newline &&
        |2. Review the execution/runtime context that produced the timeout.| &&
        cl_abap_char_utilities=>newline &&
        |3. Retry only after the runtime condition is addressed.|.
      cv_verify =
        'Confirm the retry completes without the same timeout/time-limit message.'.

    WHEN 'RECORDING'.
      cv_root =
        'The persisted BDC/SAP message explicitly proves that the recorded screen/field flow does not match the runtime screen flow.'.
      cv_fix =
        |1. Do not change business values blindly.| &&
        cl_abap_char_utilities=>newline &&
        |2. Review the exact screen/dynpro/field evidence and active recording profile.| &&
        cl_abap_char_utilities=>newline &&
        |3. Re-record or correct the profile only for the mismatch proven by that evidence.| &&
        cl_abap_char_utilities=>newline &&
        |4. Revalidate before retrying.|.
      cv_verify =
        'Confirm the corrected recording/profile replays the proven SAP screen sequence successfully.'.

    WHEN 'SM35_SESSION'.
      cv_root =
        'The persisted session-level evidence proves that the SM35 session status is Incorrect, but exact per-transaction protocol is not available; the business-field/root cause cannot be identified safely yet.'.
      cv_fix =
        |1. Open the exact SM35 session named in the evidence.| &&
        cl_abap_char_utilities=>newline &&
        |2. Open Analyze Session / transaction log and capture the exact failed-transaction SAP message.| &&
        cl_abap_char_utilities=>newline &&
        |3. Do not change source data, mapping, or recording until that transaction-level evidence identifies the cause.| &&
        cl_abap_char_utilities=>newline &&
        |4. Persist/reload the exact protocol and run Analyze Error again.|.
      cv_verify =
        'Confirm exact per-transaction SAP evidence is available and tied to this Business Group before applying a correction.'.

    WHEN 'EXEC_UNSPEC'.
      cv_root =
        'The available execution evidence proves that processing failed, but it does not safely prove a specific technical or business-data cause.'.
      cv_fix =
        |1. Review/capture the detailed SAP execution message or transaction log for this exact group.| &&
        cl_abap_char_utilities=>newline &&
        |2. Do not change data, mapping, recording, or authorization based only on this incomplete evidence.| &&
        cl_abap_char_utilities=>newline &&
        |3. Run Analyze Error again after more specific evidence is persisted.|.
      cv_verify =
        'Confirm a more specific SAP message/protocol is available before applying a cause-specific fix.'.

    WHEN 'VALIDATION_UNSPEC'.
      cv_root =
        'The available validation evidence proves that validation failed, but it does not safely prove a more specific cause.'.
      cv_fix =
        |1. Review the exact validation/error-detail evidence for this group.| &&
        cl_abap_char_utilities=>newline &&
        |2. Do not change a field unless the validation evidence identifies that field and rule.| &&
        cl_abap_char_utilities=>newline &&
        |3. Re-run validation after the verified correction.|.
      cv_verify =
        'Confirm the validation evidence identifies and clears the specific failing rule before retrying execution.'.

    WHEN OTHERS.
      cv_root =
        'An error is persisted for this group, but the available evidence does not safely prove a specific cause.'.
      cv_fix =
        |1. Review the exact persisted evidence.| &&
        cl_abap_char_utilities=>newline &&
        |2. Do not apply a cause-specific correction until stronger evidence is available.| &&
        cl_abap_char_utilities=>newline &&
        |3. Re-run analysis after the exact evidence is captured.|.
      cv_verify =
        'Confirm stronger evidence is available before applying a specific correction.'.
  ENDCASE.

ENDFORM.

*&---------------------------------------------------------------------*
*& Build normalized Issue Landscape. One persisted compound message can
*& become several independent issues; duplicates are removed.
*&---------------------------------------------------------------------*
FORM build_issue_landscape_0700.

  DATA: ls_issue     TYPE ty_issue_0700_disp,
        lt_parts     TYPE ty_t_string_0700,
        lv_part      TYPE string,
        lv_field     TYPE char40,
        lv_value     TYPE char120,
        lv_length    TYPE char20,
        lv_category  TYPE char20,
        lv_summary   TYPE char120,
        ls_cell_type TYPE salv_s_int4_column.

  REFRESH gt_issue_0700.

  LOOP AT gt_result_all INTO DATA(ls_res_0700)
       WHERE msg_type = 'E' OR msg_type = 'W'.

    PERFORM split_issue_message_0700
      USING    ls_res_0700-message
      CHANGING lt_parts.

    LOOP AT lt_parts INTO lv_part.
      CLEAR: ls_issue, lv_field, lv_value, lv_length,
             lv_category, lv_summary, ls_cell_type.

      PERFORM derive_issue_context_0700
        USING    lv_part
                 ls_res_0700-field_name
        CHANGING lv_field
                 lv_value.

      PERFORM derive_issue_length_0700
        USING    lv_part
        CHANGING lv_length.

      PERFORM classify_issue_0700
        USING    lv_part
                 lv_value
                 lv_length
                 lv_field
                 txtp_ai_source
        CHANGING lv_category
                 lv_summary.

      "Deduplicate semantically identical required-field validation entries.
      "A producer can persist both "Missing mandatory field X" and later
      ""Missing X" for the same field. Other categories keep exact-message
      "dedupe so distinct SAP errors on one field remain visible.
      IF lv_category = 'REQUIRED' AND lv_field IS NOT INITIAL.
        READ TABLE gt_issue_0700 TRANSPORTING NO FIELDS
          WITH KEY category   = lv_category
                   field_name = lv_field.
      ELSE.
        READ TABLE gt_issue_0700 TRANSPORTING NO FIELDS
          WITH KEY issue_message = lv_part
                   field_name    = lv_field.
      ENDIF.
      IF sy-subrc = 0.
        CONTINUE.
      ENDIF.

      ls_issue-issue_no         = lines( gt_issue_0700 ) + 1.
      IF ls_res_0700-msg_type = 'E'.
        ls_issue-severity = 'ERROR'.
      ELSE.
        ls_issue-severity = 'WARNING'.
      ENDIF.
      ls_issue-summary          = lv_summary.
      ls_issue-issue_message    = lv_part.
      ls_issue-field_name       = lv_field.
      IF ls_issue-field_name IS INITIAL.
        ls_issue-field_name = '-'.
      ENDIF.
      ls_issue-current_value    = lv_value.
      ls_issue-allowed_length   = lv_length.
      ls_issue-category         = lv_category.
      ls_issue-evidence_source  = txtp_ai_source.
      IF ls_issue-evidence_source IS INITIAL.
        ls_issue-evidence_source = 'Execution Result Log'.
      ENDIF.
      ls_issue-source_row_index = ls_res_0700-row_index.

      ls_cell_type-columnname = 'SUMMARY'.
      ls_cell_type-value      = if_salv_c_cell_type=>hotspot.
      APPEND ls_cell_type TO ls_issue-cell_types.

      APPEND ls_issue TO gt_issue_0700.
    ENDLOOP.
  ENDLOOP.

  IF gt_issue_0700 IS INITIAL.
    txtp_ai_evidence = 'No evidence'.
  ELSE.
    txtp_ai_evidence = |{ lines( gt_issue_0700 ) } issue(s)|.
  ENDIF.

  IF gv_issue_selected_0700 <= 0
     OR gv_issue_selected_0700 > lines( gt_issue_0700 ).
    IF gt_issue_0700 IS NOT INITIAL.
      gv_issue_selected_0700 = 1.
    ELSE.
      CLEAR gv_issue_selected_0700.
    ENDIF.
  ENDIF.

ENDFORM.

*&---------------------------------------------------------------------*
*& Render one selected issue in plain user language.
*&---------------------------------------------------------------------*
FORM render_selected_issue_0700 USING iv_mode TYPE csequence.

  DATA: lv_mode           TYPE string,
        lv_root           TYPE string,
        lv_fix            TYPE string,
        lv_verify         TYPE string,
        lv_source_up      TYPE string,
        lv_report_heading TYPE string,
        lv_rule           TYPE char40,
        lv_count          TYPE i.

  lv_mode = iv_mode.
  TRANSLATE lv_mode TO UPPER CASE.

  lv_count = lines( gt_issue_0700 ).
  IF gv_issue_selected_0700 <= 0 AND lv_count > 0.
    gv_issue_selected_0700 = 1.
  ENDIF.

  READ TABLE gt_issue_0700 INTO DATA(ls_issue_0700)
    INDEX gv_issue_selected_0700.
  IF sy-subrc <> 0.
    txtp_ai_text =
      'No persisted error evidence is available for this group.' &&
      cl_abap_char_utilities=>newline &&
      'Diagnosis cannot be produced safely.'.
    RETURN.
  ENDIF.

  PERFORM get_issue_guidance_0700
    USING    ls_issue_0700
    CHANGING lv_root
             lv_fix
             lv_verify.

  CLEAR lv_rule.
  PERFORM derive_val_rule_0700 USING ls_issue_0700-issue_message CHANGING lv_rule.

  lv_source_up = ls_issue_0700-evidence_source.
  TRANSLATE lv_source_up TO UPPER CASE.
  IF lv_source_up CS 'STAGING' OR lv_source_up CS 'VALIDATION'.
    lv_report_heading = 'WHAT VALIDATION FOUND'.
  ELSE.
    lv_report_heading = 'WHAT SAP REPORTED'.
  ENDIF.

  txtp_ai_text =
    |DIAGNOSIS & FIX GUIDE - Issue { gv_issue_selected_0700 } of { lv_count }| &&
    cl_abap_char_utilities=>newline &&
    |------------------------------------------------------------| &&
    cl_abap_char_utilities=>newline &&
    cl_abap_char_utilities=>newline &&
    |{ lv_report_heading }| &&
    cl_abap_char_utilities=>newline &&
    |{ ls_issue_0700-issue_message }| &&
    cl_abap_char_utilities=>newline &&
    cl_abap_char_utilities=>newline &&
    |WHAT NEEDS ATTENTION| &&
    cl_abap_char_utilities=>newline.

  txtp_ai_text = txtp_ai_text &&
    |Severity: { ls_issue_0700-severity }| &&
    cl_abap_char_utilities=>newline.

  IF ls_issue_0700-field_name IS NOT INITIAL
     AND ls_issue_0700-field_name <> '-'.
    txtp_ai_text = txtp_ai_text &&
      |Field: { ls_issue_0700-field_name }| &&
      cl_abap_char_utilities=>newline.
  ENDIF.

  IF ls_issue_0700-current_value IS NOT INITIAL.
    txtp_ai_text = txtp_ai_text &&
      |Current value: { ls_issue_0700-current_value }| &&
      cl_abap_char_utilities=>newline.
  ENDIF.

  IF lv_rule IS NOT INITIAL.
    txtp_ai_text = txtp_ai_text &&
      |Validation rule: { lv_rule }| &&
      cl_abap_char_utilities=>newline.
  ENDIF.

  IF ls_issue_0700-allowed_length IS NOT INITIAL.
    txtp_ai_text = txtp_ai_text &&
      |Allowed length: { ls_issue_0700-allowed_length } characters| &&
      cl_abap_char_utilities=>newline.
  ENDIF.

  txtp_ai_text = txtp_ai_text &&
    cl_abap_char_utilities=>newline &&
    |WHY THIS HAPPENED| &&
    cl_abap_char_utilities=>newline &&
    |{ lv_root }| &&
    cl_abap_char_utilities=>newline &&
    cl_abap_char_utilities=>newline &&
    |HOW TO FIX IT| &&
    cl_abap_char_utilities=>newline &&
    |{ lv_fix }| &&
    cl_abap_char_utilities=>newline.

  IF lv_verify IS NOT INITIAL.
    txtp_ai_text = txtp_ai_text &&
      cl_abap_char_utilities=>newline &&
      |VERIFY THE FIX| &&
      cl_abap_char_utilities=>newline &&
      |{ lv_verify }| &&
      cl_abap_char_utilities=>newline.
  ENDIF.

  IF ls_issue_0700-category = 'SM35_SESSION'
     OR ls_issue_0700-category = 'EXEC_UNSPEC'
     OR ls_issue_0700-category = 'VALIDATION_UNSPEC'
     OR ls_issue_0700-category = 'EVIDENCE_UNSPEC'.
    txtp_ai_text = txtp_ai_text &&
      cl_abap_char_utilities=>newline &&
      |EVIDENCE LIMITATION| &&
      cl_abap_char_utilities=>newline &&
      |A more specific root cause is not proven by the currently persisted evidence.| &&
      cl_abap_char_utilities=>newline.
  ENDIF.

  txtp_ai_text = txtp_ai_text &&
    cl_abap_char_utilities=>newline &&
    |EVIDENCE| &&
    cl_abap_char_utilities=>newline &&
    |Source: { ls_issue_0700-evidence_source }| &&
    cl_abap_char_utilities=>newline &&
    |Session ID: { txtp_ai_session }| &&
    cl_abap_char_utilities=>newline &&
    |Business Group: { txtp_ai_group }| &&
    cl_abap_char_utilities=>newline &&
    |TCode: { txtp_ai_tcode }|.

  IF lv_mode = 'AI'.
    txtp_ai_text = txtp_ai_text &&
      cl_abap_char_utilities=>newline &&
      cl_abap_char_utilities=>newline &&
      |AI ANALYSIS| &&
      cl_abap_char_utilities=>newline.

    IF gv_ai_selected_root IS NOT INITIAL.
      txtp_ai_text = txtp_ai_text &&
        |Additional explanation: { gv_ai_selected_root }| &&
        cl_abap_char_utilities=>newline.
    ENDIF.
    IF gv_ai_selected_fix IS NOT INITIAL.
      txtp_ai_text = txtp_ai_text &&
        |Additional recommendation: { gv_ai_selected_fix }| &&
        cl_abap_char_utilities=>newline.
    ENDIF.
    IF gv_ai_selected_verify IS NOT INITIAL.
      txtp_ai_text = txtp_ai_text &&
        |How to verify after the fix: { gv_ai_selected_verify }| &&
        cl_abap_char_utilities=>newline.
    ENDIF.
  ENDIF.

ENDFORM.

FORM select_issue_0700 USING iv_row TYPE i.

  IF iv_row <= 0 OR iv_row > lines( gt_issue_0700 ).
    RETURN.
  ENDIF.

  gv_issue_selected_0700 = iv_row.
  CLEAR: gv_ai_selected_root,
         gv_ai_selected_fix,
         gv_ai_selected_verify.

  PERFORM render_selected_issue_0700 USING 'RULE'.
  PERFORM show_ai_text_panel.

ENDFORM.

*&---------------------------------------------------------------------*
*& Compatibility wrapper used by existing rule/AI flows.
*&---------------------------------------------------------------------*
*& Automatic deterministic diagnosis on first entry to Screen 0700.
*& Runs once per exact Session + Business Group + TCode.
*& AI Analysis remains optional and is never auto-called.
*&---------------------------------------------------------------------*
*&---------------------------------------------------------------------*
*& Build normalized rule patterns from the user-facing issue landscape.
*& This is the normalized compatibility entry point used by Screen 0700.
*& Compound persisted messages are already split by BUILD_ISSUE_LANDSCAPE_0700.
*&---------------------------------------------------------------------*
FORM build_ai_patterns.

  DATA: ls_pat    TYPE ty_ai_pattern,
        lv_root   TYPE string,
        lv_fix    TYPE string,
        lv_verify TYPE string,
        lv_ok     TYPE abap_bool.

  REFRESH gt_patterns.
  CLEAR txtp_ai_text.

  IF gt_result_all IS INITIAL.
    PERFORM prepare_ai_current CHANGING lv_ok.
    IF lv_ok <> abap_true.
      txtp_ai_text =
        'No persisted ERROR/WARNING evidence is available for safe diagnosis.'.
      RETURN.
    ENDIF.
  ENDIF.

  IF gt_issue_0700 IS INITIAL.
    PERFORM build_issue_landscape_0700.
  ENDIF.

  LOOP AT gt_issue_0700 INTO DATA(ls_issue_pat).
    CLEAR: ls_pat, lv_root, lv_fix, lv_verify.

    ls_pat-session_id = txtp_ai_session.
    ls_pat-pattern_id = ls_issue_pat-category.
    IF ls_pat-pattern_id IS INITIAL.
      ls_pat-pattern_id = 'GENERAL'.
    ENDIF.

    IF ls_issue_pat-severity = 'WARNING'.
      ls_pat-msg_type = 'W'.
    ELSE.
      ls_pat-msg_type = 'E'.
    ENDIF.

    ls_pat-field_name = ls_issue_pat-field_name.
    ls_pat-message    = ls_issue_pat-issue_message.
    ls_pat-count      = 1.

    "The existing persistence helper interprets a numeric DYNPRO helper
    "as source ROW_INDEX. Keep the exact split issue tied to its source row.
    IF ls_issue_pat-source_row_index IS NOT INITIAL.
      ls_pat-dynpro = |{ ls_issue_pat-source_row_index }|.
    ENDIF.

    PERFORM get_issue_guidance_0700
      USING    ls_issue_pat
      CHANGING lv_root
               lv_fix
               lv_verify.

    ls_pat-fix_hint = lv_fix.
    APPEND ls_pat TO gt_patterns.
  ENDLOOP.

  IF gt_patterns IS INITIAL.
    txtp_ai_text =
      'No persisted ERROR/WARNING evidence is available for safe diagnosis.'.
  ENDIF.

ENDFORM.

*&---------------------------------------------------------------------*
*& Screen 0700 landing renderer.
*& Keeps exact frozen context, shows persisted issues immediately, and never
*& invents evidence when no persisted error exists.
*&---------------------------------------------------------------------*
FORM display_ai_landing.

  DATA lv_ok TYPE abap_bool.

  IF txtp_ai_session IS INITIAL
     AND txtp_result_session IS INITIAL
     AND txtp_session_id IS INITIAL.
    CLEAR lv_ok.
  ELSEIF gt_result_all IS INITIAL.
    PERFORM prepare_ai_current CHANGING lv_ok.
  ELSE.
    lv_ok = abap_true.
  ENDIF.

  PERFORM build_issue_landscape_0700.

  IF txtp_ai_text IS INITIAL.
    IF gt_issue_0700 IS INITIAL.
      txtp_ai_text =
        'No persisted error evidence is available for this group.' &&
        cl_abap_char_utilities=>newline &&
        'Diagnosis cannot be produced safely.'.
    ELSE.
      txtp_ai_text =
        'Select an issue to view its diagnosis and fix guide.'.
    ENDIF.
  ENDIF.

  IF go_container_0700 IS INITIAL OR go_pattern_grid IS INITIAL.
    PERFORM show_ai_pattern_grid.
  ELSEIF go_pattern_grid IS BOUND.
    go_pattern_grid->refresh( ).
  ENDIF.

  PERFORM show_ai_text_panel.

ENDFORM.

*&---------------------------------------------------------------------*
*& Export current diagnosis/fix guide text from Screen 0700.
*&---------------------------------------------------------------------*
FORM export_ai_fix_guide.

  DATA: lt_text     TYPE STANDARD TABLE OF string,
        lv_file     TYPE string,
        lv_path     TYPE string,
        lv_fullpath TYPE string,
        lv_action   TYPE i,
        lv_default  TYPE string.

  IF txtp_ai_text IS INITIAL.
    MESSAGE s682(zbdc) DISPLAY LIKE 'W'.
    RETURN.
  ENDIF.

  lv_default = 'AI_FIX_GUIDE'.
  IF txtp_ai_session IS NOT INITIAL.
    CONCATENATE lv_default txtp_ai_session
      INTO lv_default SEPARATED BY '_'.
  ELSEIF txtp_result_session IS NOT INITIAL.
    CONCATENATE lv_default txtp_result_session
      INTO lv_default SEPARATED BY '_'.
  ELSEIF txtp_session_id IS NOT INITIAL.
    CONCATENATE lv_default txtp_session_id
      INTO lv_default SEPARATED BY '_'.
  ENDIF.
  CONCATENATE lv_default '.txt' INTO lv_default.

  REPLACE ALL OCCURRENCES OF '/' IN lv_default WITH '_'.
  REPLACE ALL OCCURRENCES OF '\' IN lv_default WITH '_'.
  REPLACE ALL OCCURRENCES OF ':' IN lv_default WITH '_'.
  CONDENSE lv_default NO-GAPS.

  CALL METHOD cl_gui_frontend_services=>file_save_dialog
    EXPORTING
      window_title      = 'Export AI Fix Guide'
      default_extension = 'txt'
      default_file_name = lv_default
      file_filter       = 'Text File (*.txt)|*.txt|All Files (*.*)|*.*'
    CHANGING
      filename          = lv_file
      path              = lv_path
      fullpath          = lv_fullpath
      user_action       = lv_action
    EXCEPTIONS
      OTHERS            = 1.

  IF sy-subrc <> 0
     OR lv_action = cl_gui_frontend_services=>action_cancel
     OR lv_fullpath IS INITIAL.
    RETURN.
  ENDIF.

  SPLIT txtp_ai_text AT cl_abap_char_utilities=>newline
    INTO TABLE lt_text.

  CALL METHOD cl_gui_frontend_services=>gui_download
    EXPORTING
      filename = lv_fullpath
      filetype = 'ASC'
    CHANGING
      data_tab = lt_text
    EXCEPTIONS
      OTHERS   = 1.

  IF sy-subrc = 0.
    MESSAGE s683(zbdc) WITH lv_fullpath.
  ELSE.
    MESSAGE s684(zbdc) WITH sy-subrc DISPLAY LIKE 'E'.
  ENDIF.

ENDFORM.

*&---------------------------------------------------------------------*
*& Compatibility action for legacy STATUS_0700 function code.
*& Rule diagnosis is automatic, but this safely re-runs it if invoked.
*&---------------------------------------------------------------------*
FORM run_rule_ai_for_session.

  DATA lv_ok TYPE abap_bool.

  IF gt_result_all IS INITIAL.
    PERFORM prepare_ai_current CHANGING lv_ok.
    IF lv_ok <> abap_true.
      PERFORM display_ai_landing.
      RETURN.
    ENDIF.
  ENDIF.

  PERFORM build_ai_patterns.

  IF gt_patterns IS INITIAL.
    PERFORM display_ai_landing.
    RETURN.
  ENDIF.
  IF gv_issue_selected_0700 <= 0.
    gv_issue_selected_0700 = 1.
  ENDIF.

  PERFORM render_selected_issue_0700 USING 'RULE'.
  PERFORM display_ai_patterns.

ENDFORM.

*&---------------------------------------------------------------------*
*& Return diagnostic timestamp in Vietnam UTC+7 using the project-wide
*& demo/current-time helper.
*&---------------------------------------------------------------------*
*&---------------------------------------------------------------------*
*& Archive current diagnosis patterns for Screen 0750.
*& Exact Session + Pattern + Message is the idempotent archive key.
*&---------------------------------------------------------------------*
FORM auto_diagnose_0700.

  DATA: lv_key TYPE string.

  IF txtp_ai_session IS INITIAL
     OR txtp_ai_group IS INITIAL.
    RETURN.
  ENDIF.

  lv_key = |{ txtp_ai_session }| && `|` &&
           |{ txtp_ai_group }|   && `|` &&
           |{ txtp_ai_tcode }|.

  IF gv_ai_auto_diag_done = abap_true
     AND gv_ai_auto_diag_key = lv_key.
    RETURN.
  ENDIF.

  "Guard before Control Framework rendering so a PBO re-entry cannot
  "run the deterministic diagnosis twice for the same exact group.
  gv_ai_auto_diag_done = abap_true.
  gv_ai_auto_diag_key  = lv_key.

  PERFORM build_ai_patterns.

  IF gt_patterns IS INITIAL.
    IF txtp_ai_text IS INITIAL.
      txtp_ai_text =
        'No persisted ERROR/WARNING evidence is available for safe diagnosis.'.
    ENDIF.
    PERFORM show_ai_text_panel.
    RETURN.
  ENDIF.
  IF gv_issue_selected_0700 <= 0.
    gv_issue_selected_0700 = 1.
  ENDIF.

  PERFORM render_selected_issue_0700 USING 'RULE'.
  PERFORM display_ai_patterns.

ENDFORM.

*& OPENAI AI ERROR ANALYST (real LLM) + rule-based fallback
*& Flow: gom loi that tu ZBDC_RESULT_BUP -> build prompt EN
*& -> direct OpenAI API (CL_HTTP_CLIENT)
*& -> parse JSON -> do vao gt_patterns -> hien 0700
*& Neu BAT KY buoc nao loi (no key / SSL / network / parse) ->
*& tu dong goi build_ai_patterns (rule-based) -> KHONG BAO GIO trang man.
FORM get_ai_endpoint CHANGING cv_endpoint TYPE string.
  DATA: ls_cfg     TYPE zbdc_config_bup,
        lv_enabled TYPE string.

  CLEAR: cv_endpoint, gv_z619_ai_http_diag, lv_enabled.

  "One provider for every external AI workload: OpenAI Responses API.
  CLEAR ls_cfg.
  SELECT SINGLE * FROM zbdc_config_bup INTO @ls_cfg
    WHERE config_key = 'AI_ENABLED'.
  IF sy-subrc = 0.
    lv_enabled = ls_cfg-config_value.
    CONDENSE lv_enabled NO-GAPS.
    TRANSLATE lv_enabled TO UPPER CASE.
    IF lv_enabled IS INITIAL OR
       ( lv_enabled <> 'X' AND lv_enabled <> '1' AND
         lv_enabled <> 'Y' AND lv_enabled <> 'YES' AND
         lv_enabled <> 'TRUE' AND lv_enabled <> 'ON' ).
      gv_z619_ai_http_diag = 'AI_DISABLED_BY_CONFIG'.
      RETURN.
    ENDIF.
  ENDIF.

  cv_endpoint = 'https://api.openai.com/v1/responses'.
ENDFORM.

FORM get_ai_api_key
  USING    iv_purpose TYPE csequence
  CHANGING cv_api_key TYPE string
           cv_cfg_key TYPE string.

  DATA: ls_cfg        TYPE zbdc_config_bup,
        lv_purpose    TYPE string,
        lv_config_key TYPE zbdc_config_bup-config_key.

  CLEAR: cv_api_key, cv_cfg_key, lv_config_key.
  lv_purpose = iv_purpose.
  CONDENSE lv_purpose NO-GAPS.
  TRANSLATE lv_purpose TO UPPER CASE.

  CASE lv_purpose.
    WHEN 'MAPPING'.
      lv_config_key = 'OPENAI_API_KEY_MAPPING'.
    WHEN 'ERROR'.
      lv_config_key = 'OPENAI_API_KEY_ERROR'.
    WHEN 'FIX'.
      lv_config_key = 'OPENAI_API_KEY_FIX'.
    WHEN 'NAV'.
      lv_config_key = 'OPENAI_API_KEY_NAV'.
    WHEN OTHERS.
      gv_z619_ai_http_diag = |AI_KEY_PURPOSE_INVALID:{ lv_purpose }|.
      RETURN.
  ENDCASE.

  "Dedicated workload key wins when configured.
  CLEAR ls_cfg.
  SELECT SINGLE * FROM zbdc_config_bup INTO @ls_cfg
    WHERE config_key = @lv_config_key.
  IF sy-subrc = 0.
    cv_api_key = ls_cfg-config_value.
    CONDENSE cv_api_key NO-GAPS.
    IF cv_api_key IS NOT INITIAL.
      cv_cfg_key = lv_config_key.
    ENDIF.
  ENDIF.

  "The existing Mapping OpenAI key is the safe common fallback. This makes
  "ERROR/FIX/NAV work immediately without copying or exposing a secret.
  IF cv_api_key IS INITIAL AND lv_purpose <> 'MAPPING'.
    CLEAR ls_cfg.
    SELECT SINGLE * FROM zbdc_config_bup INTO @ls_cfg
      WHERE config_key = 'OPENAI_API_KEY_MAPPING'.
    IF sy-subrc = 0.
      cv_api_key = ls_cfg-config_value.
      CONDENSE cv_api_key NO-GAPS.
      IF cv_api_key IS NOT INITIAL.
        cv_cfg_key = 'OPENAI_API_KEY_MAPPING'.
      ENDIF.
    ENDIF.
  ENDIF.

  "Optional account-wide OpenAI fallback.
  IF cv_api_key IS INITIAL.
    CLEAR ls_cfg.
    SELECT SINGLE * FROM zbdc_config_bup INTO @ls_cfg
      WHERE config_key = 'OPENAI_API_KEY'.
    IF sy-subrc = 0.
      cv_api_key = ls_cfg-config_value.
      CONDENSE cv_api_key NO-GAPS.
      IF cv_api_key IS NOT INITIAL.
        cv_cfg_key = 'OPENAI_API_KEY'.
      ENDIF.
    ENDIF.
  ENDIF.

  IF cv_api_key IS INITIAL.
    gv_z619_ai_http_diag = |OPENAI_CONFIG_MISSING:{ lv_config_key }|.
  ENDIF.
ENDFORM.

FORM get_ai_model
  USING    iv_purpose TYPE csequence
  CHANGING cv_model   TYPE string
           cv_cfg_key TYPE string.

  DATA: ls_cfg        TYPE zbdc_config_bup,
        lv_purpose    TYPE string,
        lv_config_key TYPE zbdc_config_bup-config_key.

  CLEAR: cv_model, cv_cfg_key, lv_config_key.
  lv_purpose = iv_purpose.
  CONDENSE lv_purpose NO-GAPS.
  TRANSLATE lv_purpose TO UPPER CASE.

  CASE lv_purpose.
    WHEN 'MAPPING'.
      lv_config_key = 'OPENAI_MODEL_MAPPING'.
    WHEN 'ERROR'.
      lv_config_key = 'OPENAI_MODEL_ERROR'.
    WHEN 'FIX'.
      lv_config_key = 'OPENAI_MODEL_FIX'.
    WHEN 'NAV'.
      lv_config_key = 'OPENAI_MODEL_NAV'.
    WHEN OTHERS.
      gv_z619_ai_http_diag = |AI_MODEL_PURPOSE_INVALID:{ lv_purpose }|.
      RETURN.
  ENDCASE.

  CLEAR ls_cfg.
  SELECT SINGLE * FROM zbdc_config_bup INTO @ls_cfg
    WHERE config_key = @lv_config_key.
  IF sy-subrc = 0.
    cv_model = ls_cfg-config_value.
    CONDENSE cv_model NO-GAPS.
    IF cv_model IS NOT INITIAL.
      cv_cfg_key = lv_config_key.
    ENDIF.
  ENDIF.

  "All non-Mapping workloads inherit the already-tested Mapping model unless
  "a dedicated model is explicitly configured.
  IF cv_model IS INITIAL AND lv_purpose <> 'MAPPING'.
    CLEAR ls_cfg.
    SELECT SINGLE * FROM zbdc_config_bup INTO @ls_cfg
      WHERE config_key = 'OPENAI_MODEL_MAPPING'.
    IF sy-subrc = 0.
      cv_model = ls_cfg-config_value.
      CONDENSE cv_model NO-GAPS.
      IF cv_model IS NOT INITIAL.
        cv_cfg_key = 'OPENAI_MODEL_MAPPING'.
      ENDIF.
    ENDIF.
  ENDIF.

  IF cv_model IS INITIAL.
    cv_model = 'gpt-5.6-sol'.
    cv_cfg_key = 'DEFAULT_GPT_5_6_SOL'.
  ENDIF.

  TRANSLATE cv_model TO LOWER CASE.
  IF cv_model CN 'abcdefghijklmnopqrstuvwxyz0123456789.-_'.
    CLEAR cv_model.
    gv_z619_ai_http_diag = 'OPENAI_INVALID_MODEL_ID'.
  ENDIF.
ENDFORM.
FORM call_ai_endpoint USING iv_purpose TYPE csequence
                           iv_key     TYPE string
                           iv_prompt  TYPE string
                  CHANGING cv_resp    TYPE string
                           cv_ok      TYPE abap_bool.

  DATA: lo_http        TYPE REF TO if_http_client,
        lv_url         TYPE string,
        lv_body        TYPE string,
        lv_code        TYPE i,
        lv_timeout     TYPE i VALUE 60,
        lv_subrc       TYPE sy-subrc,
        lv_err         TYPE string,
        lv_api_key     TYPE string,
        lv_key_cfg     TYPE string,
        lv_model       TYPE string,
        lv_model_cfg   TYPE string,
        lv_prompt_js   TYPE string,
        lv_model_js    TYPE string,
        lv_effort      TYPE string VALUE 'medium',
        lv_effort_js   TYPE string,
        lv_last_code   TYPE i,
        lv_last_msg    TYPE string,
        ls_cfg         TYPE zbdc_config_bup.

  CLEAR: cv_resp, cv_ok, gv_z619_ai_http_diag,
         lv_body, lv_code, lv_err, lv_api_key,
         lv_key_cfg, lv_model, lv_model_cfg,
         lv_prompt_js, lv_model_js, lv_effort_js.

  lv_url = iv_key.
  CONDENSE lv_url NO-GAPS.
  IF lv_url IS INITIAL OR iv_prompt IS INITIAL.
    gv_z619_ai_http_diag = 'OPENAI_INPUT_MISSING'.
    RETURN.
  ENDIF.

  IF lv_url NS 'api.openai.com/v1/responses'.
    gv_z619_ai_http_diag = 'OPENAI_RESPONSES:ENDPOINT_REJECTED'.
    RETURN.
  ENDIF.

  PERFORM get_ai_api_key
    USING    iv_purpose
    CHANGING lv_api_key lv_key_cfg.
  IF lv_api_key IS INITIAL.
    IF gv_z619_ai_http_diag IS INITIAL.
      gv_z619_ai_http_diag =
        |OPENAI_RESPONSES:KEY_MISSING;PURPOSE={ iv_purpose }|.
    ENDIF.
    RETURN.
  ENDIF.

  PERFORM get_ai_model
    USING    iv_purpose
    CHANGING lv_model lv_model_cfg.
  IF lv_model IS INITIAL.
    IF gv_z619_ai_http_diag IS INITIAL.
      gv_z619_ai_http_diag =
        |OPENAI_RESPONSES:MODEL_MISSING;PURPOSE={ iv_purpose }|.
    ENDIF.
    RETURN.
  ENDIF.

  TRY.
      DATA(lv_prompt_send) = iv_prompt.
      IF strlen( lv_prompt_send ) > 16000.
        lv_prompt_send =
          lv_prompt_send+0(16000) &&
          cl_abap_char_utilities=>newline &&
          '[Prompt truncated in SAP before calling OpenAI]'.
      ENDIF.

      lv_prompt_js = /ui2/cl_json=>serialize(
        data     = lv_prompt_send
        compress = abap_true ).
      lv_model_js = /ui2/cl_json=>serialize(
        data     = lv_model
        compress = abap_true ).
      lv_effort_js = /ui2/cl_json=>serialize(
        data     = lv_effort
        compress = abap_true ).
    CATCH cx_root.
      gv_z619_ai_http_diag = 'SERIALIZE_FAIL:OPENAI_RESPONSES'.
      RETURN.
  ENDTRY.

  lv_body =
    '{"model":' && lv_model_js &&
    ',"reasoning":{"effort":' && lv_effort_js && '}' &&
    ',"input":[{"role":"user","content":[{"type":"input_text","text":' &&
    lv_prompt_js &&
    '}]}],"store":false}'.

  CLEAR ls_cfg.
  SELECT SINGLE * FROM zbdc_config_bup INTO @ls_cfg
    WHERE config_key = 'AI_TIMEOUT_SEC'.
  IF sy-subrc = 0 AND ls_cfg-config_value IS NOT INITIAL.
    TRY.
        lv_timeout = CONV i( ls_cfg-config_value ).
      CATCH cx_root.
        lv_timeout = 60.
    ENDTRY.
  ENDIF.
  IF lv_timeout < 30.
    lv_timeout = 30.
  ELSEIF lv_timeout > 180.
    lv_timeout = 180.
  ENDIF.

  cl_http_client=>create_by_url(
    EXPORTING
      url    = lv_url
    IMPORTING
      client = lo_http
    EXCEPTIONS
      OTHERS = 1 ).
  lv_subrc = sy-subrc.
  IF lv_subrc <> 0 OR lo_http IS INITIAL.
    gv_z619_ai_http_diag =
      |CREATE_FAIL:{ lv_subrc };PROVIDER=OPENAI_RESPONSES;PURPOSE={ iv_purpose };KEY={ lv_key_cfg };MODEL={ lv_model }|.
    RETURN.
  ENDIF.

  lo_http->propertytype_redirect = lo_http->co_enabled.
  lo_http->propertytype_logon_popup = lo_http->co_disabled.
  lo_http->request->set_method( 'POST' ).
  lo_http->request->set_content_type( 'application/json; charset=utf-8' ).
  lo_http->request->set_header_field(
    name  = 'Accept'
    value = 'application/json' ).
  lo_http->request->set_header_field(
    name  = 'Authorization'
    value = |Bearer { lv_api_key }| ).
  lo_http->request->set_cdata( lv_body ).

  lo_http->send(
    EXPORTING
      timeout = lv_timeout
    EXCEPTIONS
      OTHERS  = 1 ).
  lv_subrc = sy-subrc.
  IF lv_subrc <> 0.
    gv_z619_ai_http_diag =
      |SEND_FAIL_OR_TIMEOUT:{ lv_subrc };PROVIDER=OPENAI_RESPONSES;PURPOSE={ iv_purpose };MODEL={ lv_model }|.
    lo_http->close( EXCEPTIONS OTHERS = 1 ).
    RETURN.
  ENDIF.

  lo_http->receive(
    EXCEPTIONS
      http_communication_failure = 1
      http_invalid_state         = 2
      http_processing_failed     = 3
      OTHERS                     = 4 ).
  lv_subrc = sy-subrc.
  IF lv_subrc <> 0.
    CLEAR: lv_last_code, lv_last_msg.
    lo_http->get_last_error(
      IMPORTING
        code    = lv_last_code
        message = lv_last_msg ).
    REPLACE ALL OCCURRENCES OF cl_abap_char_utilities=>cr_lf
      IN lv_last_msg WITH space.
    REPLACE ALL OCCURRENCES OF cl_abap_char_utilities=>newline
      IN lv_last_msg WITH space.
    CONDENSE lv_last_msg.
    IF strlen( lv_last_msg ) > 120.
      lv_last_msg = lv_last_msg+0(120).
    ENDIF.
    gv_z619_ai_http_diag =
      |RECEIVE_FAIL:{ lv_subrc };TIMEOUT={ lv_timeout };PROVIDER=OPENAI_RESPONSES;LAST={ lv_last_code }:{ lv_last_msg }|.
    lo_http->close( EXCEPTIONS OTHERS = 1 ).
    RETURN.
  ENDIF.

  lo_http->response->get_status( IMPORTING code = lv_code ).
  cv_resp = lo_http->response->get_cdata( ).
  lo_http->close( EXCEPTIONS OTHERS = 1 ).

  IF lv_code >= 200 AND lv_code < 300.
    IF cv_resp IS INITIAL.
      gv_z619_ai_http_diag =
        'HTTP_200_EMPTY;PROVIDER=OPENAI_RESPONSES'.
      RETURN.
    ENDIF.
    cv_ok = abap_true.
    gv_z619_ai_http_diag =
      |HTTP_{ lv_code }_OK;PROVIDER=OPENAI_RESPONSES;PURPOSE={ iv_purpose };KEY={ lv_key_cfg };MODEL={ lv_model }|.
    RETURN.
  ENDIF.

  lv_err = cv_resp.
  REPLACE ALL OCCURRENCES OF cl_abap_char_utilities=>cr_lf
    IN lv_err WITH space.
  REPLACE ALL OCCURRENCES OF cl_abap_char_utilities=>newline
    IN lv_err WITH space.
  CONDENSE lv_err.
  IF strlen( lv_err ) > 180.
    lv_err = lv_err+0(180).
  ENDIF.

  gv_z619_ai_http_diag =
    |HTTP_{ lv_code };PROVIDER=OPENAI_RESPONSES;PURPOSE={ iv_purpose };KEY={ lv_key_cfg };MODEL={ lv_model };ERR={ lv_err }|.
  CLEAR cv_resp.
ENDFORM.

*& Central OpenAI Vision transport
*& Uses the same AI enablement, model, API key, timeout and HTTP diagnostics
*& as the existing text-AI path. M2 owns only screen correlation semantics.
FORM extract_openai_text USING iv_resp TYPE string
                        CHANGING cv_text TYPE string.

  TYPES: BEGIN OF ty_oa_content,
           text TYPE string,
         END OF ty_oa_content.
  TYPES ty_t_oa_content TYPE STANDARD TABLE OF ty_oa_content
                        WITH DEFAULT KEY.
  TYPES: BEGIN OF ty_oa_output,
           content TYPE ty_t_oa_content,
         END OF ty_oa_output.
  TYPES ty_t_oa_output TYPE STANDARD TABLE OF ty_oa_output
                       WITH DEFAULT KEY.
  TYPES: BEGIN OF ty_oa_response,
           output TYPE ty_t_oa_output,
         END OF ty_oa_response.

  DATA ls_response TYPE ty_oa_response.

  CLEAR cv_text.
  IF iv_resp IS INITIAL.
    RETURN.
  ENDIF.

  TRY.
      /ui2/cl_json=>deserialize(
        EXPORTING
          json = iv_resp
        CHANGING
          data = ls_response ).
    CATCH cx_root.
      RETURN.
  ENDTRY.

  LOOP AT ls_response-output INTO DATA(ls_output).
    LOOP AT ls_output-content INTO DATA(ls_content).
      IF ls_content-text IS NOT INITIAL.
        cv_text = ls_content-text.
        RETURN.
      ENDIF.
    ENDLOOP.
  ENDLOOP.
ENDFORM.
FORM show_ai_pattern_grid.

  DATA: lo_cols TYPE REF TO cl_salv_columns_table,
        lo_col  TYPE REF TO cl_salv_column_table,
        lo_evt  TYPE REF TO cl_salv_events_table.

  IF gt_issue_0700 IS INITIAL.
    PERFORM build_issue_landscape_0700.
  ENDIF.

  IF go_container_0700 IS BOUND.
    TRY.
        go_container_0700->free( ).
      CATCH cx_root.
    ENDTRY.
    CLEAR: go_container_0700,
           go_pattern_grid,
           go_issue_evt_0700.
  ENDIF.

  CREATE OBJECT go_container_0700
    EXPORTING
      container_name = 'CC_PATTERN_CONTAINER'.

  TRY.
      cl_salv_table=>factory(
        EXPORTING
          r_container  = go_container_0700
        IMPORTING
          r_salv_table = go_pattern_grid
        CHANGING
          t_table      = gt_issue_0700 ).

      "Keep the issue list visually quiet. This screen is a diagnosis surface,
      "not a generic ALV workbench.
      go_pattern_grid->get_functions( )->set_all( abap_false ).

      lo_cols = go_pattern_grid->get_columns( ).
      lo_cols->set_optimize( abap_false ).

      lo_cols->set_column_position( columnname = 'ISSUE_NO'   position = 1 ).
      lo_cols->set_column_position( columnname = 'SEVERITY'   position = 2 ).
      lo_cols->set_column_position( columnname = 'SUMMARY'    position = 3 ).
      lo_cols->set_column_position( columnname = 'FIELD_NAME' position = 4 ).

      lo_col ?= lo_cols->get_column( 'ISSUE_NO' ).
      lo_col->set_short_text( '#' ).
      lo_col->set_medium_text( '#' ).
      lo_col->set_long_text( 'Issue' ).
      lo_col->set_output_length( 4 ).

      lo_col ?= lo_cols->get_column( 'SEVERITY' ).
      lo_col->set_short_text( 'Severity' ).
      lo_col->set_medium_text( 'Severity' ).
      lo_col->set_long_text( 'Severity' ).
      lo_col->set_output_length( 10 ).

      lo_col ?= lo_cols->get_column( 'SUMMARY' ).
      lo_col->set_short_text( 'Issue' ).
      lo_col->set_medium_text( 'Error / Issue' ).
      lo_col->set_long_text( 'Error / Issue (Summary)' ).
      lo_col->set_output_length( 48 ).

      lo_col ?= lo_cols->get_column( 'FIELD_NAME' ).
      lo_col->set_short_text( 'Field' ).
      lo_col->set_medium_text( 'Affected Field' ).
      lo_col->set_long_text( 'Affected Field' ).
      lo_col->set_output_length( 24 ).

      lo_col ?= lo_cols->get_column( 'ISSUE_MESSAGE' ).
      lo_col->set_visible( abap_false ).
      lo_col ?= lo_cols->get_column( 'CURRENT_VALUE' ).
      lo_col->set_visible( abap_false ).
      lo_col ?= lo_cols->get_column( 'ALLOWED_LENGTH' ).
      lo_col->set_visible( abap_false ).
      lo_col ?= lo_cols->get_column( 'CATEGORY' ).
      lo_col->set_visible( abap_false ).
      lo_col ?= lo_cols->get_column( 'EVIDENCE_SOURCE' ).
      lo_col->set_visible( abap_false ).
      lo_col ?= lo_cols->get_column( 'SOURCE_ROW_INDEX' ).
      lo_col->set_visible( abap_false ).

      "Use the release-compatible SALV per-cell hotspot mechanism already
      "used elsewhere in this project. SUMMARY is a one-click issue selector.
      TRY.
          lo_cols->set_cell_type_column( 'CELL_TYPES' ).
        CATCH cx_salv_data_error.
      ENDTRY.
      TRY.
          lo_col ?= lo_cols->get_column( 'CELL_TYPES' ).
          lo_col->set_technical( abap_true ).
        CATCH cx_salv_not_found.
      ENDTRY.

      lo_evt = go_pattern_grid->get_event( ).
      CREATE OBJECT go_issue_evt_0700.
      SET HANDLER go_issue_evt_0700->on_issue_0700_dbl  FOR lo_evt.
      SET HANDLER go_issue_evt_0700->on_issue_0700_link FOR lo_evt.

      go_pattern_grid->display( ).

    CATCH cx_salv_not_found INTO DATA(lx_nf).
      MESSAGE lx_nf->get_text( ) TYPE 'S' DISPLAY LIKE 'E'.

    CATCH cx_salv_msg INTO DATA(lx_msg).
      MESSAGE lx_msg->get_text( ) TYPE 'S' DISPLAY LIKE 'E'.

    CATCH cx_root INTO DATA(lx_any).
      MESSAGE lx_any->get_text( ) TYPE 'S' DISPLAY LIKE 'E'.
  ENDTRY.

ENDFORM.

FORM display_ai_patterns.

  PERFORM build_issue_landscape_0700.

  IF go_container_0700 IS INITIAL OR go_pattern_grid IS INITIAL.
    PERFORM show_ai_pattern_grid.
  ELSEIF go_pattern_grid IS BOUND.
    go_pattern_grid->refresh( ).
  ENDIF.

  PERFORM show_ai_text_panel.

ENDFORM.

*& hide_0750_search_ui
*& Purpose: Search Term is retired. Hide common screen element names.
*& For a clean design-time layout, delete the Search Archive block
*& from Screen Painter 0750 as described in the README.
FORM show_ai_text_panel.

  DATA lt_text TYPE STANDARD TABLE OF char255.

  IF txtp_ai_text IS INITIAL.
    txtp_ai_text = 'No diagnosis has been generated yet.'.
  ENDIF.

  REFRESH lt_text.
  SPLIT txtp_ai_text AT cl_abap_char_utilities=>newline INTO TABLE lt_text.

  IF go_ai_text_container IS NOT BOUND.

    CREATE OBJECT go_ai_text_container
      EXPORTING
        container_name = 'CC_TEXT_CONTAINER'.

    CREATE OBJECT go_ai_textedit
      EXPORTING
        parent = go_ai_text_container.

    go_ai_textedit->set_readonly_mode(
      EXPORTING
        readonly_mode = cl_gui_textedit=>true ).

  ENDIF.

  go_ai_textedit->set_text_as_r3table(
    EXPORTING
      table = lt_text ).

  cl_gui_cfw=>flush( EXCEPTIONS OTHERS = 1 ).

ENDFORM.

* Screen 0800 - versioned SHDB editor using the compatibility row structure

FORM mark_row_error USING iv_field TYPE csequence iv_msg TYPE csequence
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

FORM classify_error USING iv_msg TYPE csequence iv_field TYPE csequence CHANGING cv_cat TYPE string.
  DATA lv_text TYPE string.
  cv_cat = 'BDC_RUNTIME'.
  lv_text = |{ iv_msg } { iv_field }|.
  TRANSLATE lv_text TO LOWER CASE.
 "BLOCKED is a safety-gate word, not evidence of an SAP lock.
  REPLACE ALL OCCURRENCES OF 'blocked' IN lv_text WITH ' '.
  IF lv_text CS 'mandatory' OR lv_text CS 'required' OR lv_text CS 'missing'.
    cv_cat = 'TEMPLATE'.
  ELSEIF lv_text CS 'lock' OR lv_text CS 'enqueue' OR lv_text CS 'timeout'.
    cv_cat = 'TRANSIENT'.
  ELSEIF lv_text CS 'auth' OR lv_text CS 'authorization' OR lv_text CS 'not authorized'.
    cv_cat = 'AUTH'.
  ELSEIF lv_text CS 'format' OR lv_text CS 'conversion' OR lv_text CS 'numeric' OR lv_text CS 'date'.
    cv_cat = 'FORMAT'.
  ELSEIF lv_text CS 'screen' OR lv_text CS 'dynpro' OR lv_text CS 'batch input data'.
    cv_cat = 'RECORDING'.
  ELSEIF lv_text CS 'document still faulty' OR lv_text CS 'still faulty' OR
         lv_text CS 'faulty' OR lv_text CS 'incomplete' OR
         lv_text CS 'not complete' OR lv_text CS 'not saved' OR
         lv_text CS 'was held' OR lv_text CS 'document held' OR
         lv_text CS ' hold' OR lv_text CS 'held' OR
         lv_text CS 'cancel' OR lv_text CS 'terminated'.
    cv_cat = 'BUSINESS'.
  ELSEIF lv_text CS 'invalid' OR lv_text CS 'does not exist' OR lv_text CS 'not defined'.
    cv_cat = 'REFERENCE'.
  ENDIF.
ENDFORM.

FORM guess_responsible USING iv_cat TYPE csequence CHANGING cv_resp TYPE string.
  CASE iv_cat.
    WHEN 'MASTER_DATA'. cv_resp = 'Master Data'.
    WHEN 'REFERENCE'.   cv_resp = 'Master Data/Customizing'.
    WHEN 'RECORDING'.   cv_resp = 'Consultant/Recording'.
    WHEN 'FORMAT'.      cv_resp = 'Data Owner'.
    WHEN 'TRANSIENT'.   cv_resp = 'Technical/Retry'.
    WHEN 'AUTH'.        cv_resp = 'Technical/Auth'.
    WHEN 'LOCK'.        cv_resp = 'User/Technical'.
    WHEN 'BUSINESS'.    cv_resp = 'Business User'.
    WHEN OTHERS.        cv_resp = 'User'.
  ENDCASE.
ENDFORM.

FORM insert_error_record USING is_alv TYPE ty_staging_alv
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

  PERFORM table_exists USING gc_z16_tab_error CHANGING lv_exists.
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
  PERFORM classify_error USING is_alv-error_msg iv_field CHANGING lv_cat.
  PERFORM build_bdc_action_hint USING is_alv-error_msg iv_field CHANGING lv_hint lv_retry.
  PERFORM guess_responsible USING lv_cat CHANGING lv_resp.

  PERFORM set_optional_comp USING 'ERROR_ID'         lv_key               CHANGING <ls_any>.
  PERFORM set_optional_comp USING 'SESSION_ID'       is_alv-session_id    CHANGING <ls_any>.
  PERFORM set_optional_comp USING 'ROW_INDEX'        is_alv-row_index     CHANGING <ls_any>.
  PERFORM set_optional_comp USING 'RECORD_KEY'       is_alv-record_key    CHANGING <ls_any>.
  PERFORM set_optional_comp USING 'GROUP_KEY'        is_alv-record_key    CHANGING <ls_any>.
  PERFORM set_optional_comp USING 'DOCUMENT_GROUP'   is_alv-record_key    CHANGING <ls_any>.
  PERFORM set_optional_comp USING 'TCODE'            is_alv-tcode         CHANGING <ls_any>.
  PERFORM set_optional_comp USING 'FIELD_NAME'       iv_field             CHANGING <ls_any>.
  PERFORM set_optional_comp USING 'CURRENT_VALUE'    iv_value             CHANGING <ls_any>.
  PERFORM set_optional_comp USING 'ERROR_CATEGORY'   lv_cat               CHANGING <ls_any>.
  PERFORM set_optional_comp USING 'ERROR_MESSAGE'    is_alv-error_msg     CHANGING <ls_any>.
  PERFORM set_optional_comp USING 'ACTION_HINT'      lv_hint              CHANGING <ls_any>.
  PERFORM set_optional_comp USING 'SUGGESTED_VALUES' ''                   CHANGING <ls_any>.
  PERFORM set_optional_comp USING 'RESPONSIBLE'      lv_resp              CHANGING <ls_any>.
  PERFORM set_optional_comp USING 'RETRYABLE'        lv_retry             CHANGING <ls_any>.
  PERFORM set_optional_comp USING 'STATUS'           'UNFIXED'            CHANGING <ls_any>.
  PERFORM set_optional_comp USING 'CREATED_BY'       sy-uname             CHANGING <ls_any>.
  PERFORM set_optional_comp USING 'CREATED_AT'       lv_ts                CHANGING <ls_any>.

  lv_tab = gc_z16_tab_error.
  TRY.
      MODIFY (lv_tab) FROM <ls_any>.
    CATCH cx_root.
  ENDTRY.
ENDFORM.

FORM write_structured_errors.
  DATA: lv_field TYPE lvc_fname,
        lv_value TYPE string.
  FIELD-SYMBOLS <lv_any> TYPE any.

  LOOP AT gt_staging_alv INTO DATA(ls_err) WHERE status = gc_st_error.
    IF ls_err-cell_colors IS INITIAL.
      PERFORM insert_error_record USING ls_err '' ''.
    ELSE.
      LOOP AT ls_err-cell_colors INTO DATA(ls_color).
        CLEAR: lv_field, lv_value.
        lv_field = ls_color-fname.
        ASSIGN COMPONENT lv_field OF STRUCTURE ls_err TO <lv_any>.
        IF sy-subrc = 0.
          lv_value = |{ <lv_any> }|.
        ENDIF.
        PERFORM insert_error_record USING ls_err lv_field lv_value.
      ENDLOOP.
    ENDIF.
  ENDLOOP.
 "No COMMIT here. The explicit validation command owns the LUW.
ENDFORM.
