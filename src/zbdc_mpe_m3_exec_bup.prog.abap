*&---------------------------------------------------------------------*
*& Include          ZBDC_MPE_M3_EXEC_BUP
*& Purpose          M3 Processing - CALL TRANSACTION, SM35, chunk, retry, 0500
*& Source split     FIX16 V5BR - logic moved from F01
*&---------------------------------------------------------------------*

*>>> FORM SAVE_BDC_EXEC_MODE_CONFIG - moved from Z_BDC_MASS_PO_ENTRY_F01_BUP

FORM SAVE_BDC_EXEC_MODE_CONFIG.
  DATA LS_CONFIG TYPE ZBDC_CONFIG_BUP.
  CLEAR LS_CONFIG.
  LS_CONFIG-CONFIG_KEY   = 'BDC_EXEC_MODE'.
  LS_CONFIG-CONFIG_VALUE = P_BDC_MODE.
  MODIFY ZBDC_CONFIG_BUP FROM LS_CONFIG.
ENDFORM.
*<<< END FORM SAVE_BDC_EXEC_MODE_CONFIG

*>>> FORM RUN_BDC_FOR_SESSION - moved from Z_BDC_MASS_PO_ENTRY_F01_BUP

FORM RUN_BDC_FOR_SESSION USING P_SESSION_ID TYPE ANY.
  DATA: LT_STAGING TYPE STANDARD TABLE OF zbdc_staging_bup, LS_STG TYPE zbdc_staging_bup, LT_MAP TYPE STANDARD TABLE OF zbdc_mapping_bup, LS_MAP TYPE zbdc_mapping_bup.
  DATA: LV_LIFNR TYPE STRING, LV_EKORG TYPE STRING, LV_EKGRP TYPE STRING, LV_BUKRS TYPE STRING, LV_MATNR TYPE STRING, LV_MENGE TYPE STRING, LV_WERKS TYPE STRING, LV_NETPR TYPE STRING.
  FIELD-SYMBOLS: <FV> TYPE ANY.

  SELECT * FROM zbdc_staging_bup INTO TABLE @LT_STAGING WHERE SESSION_ID = @P_SESSION_ID AND STATUS = 'READY'.
  IF LT_STAGING IS INITIAL. MESSAGE 'Session khong co du lieu hop le!' TYPE 'W'. RETURN. ENDIF.
  SELECT * FROM zbdc_mapping_bup WHERE PROFILE_NAME = @TXTP_PROFILE_NAME INTO TABLE @LT_MAP.

  LOOP AT LT_STAGING INTO LS_STG.
    CLEAR: LV_LIFNR, LV_EKORG, LV_EKGRP, LV_BUKRS, LV_MATNR, LV_MENGE, LV_WERKS, LV_NETPR.
    LOOP AT LT_MAP INTO LS_MAP.
      ASSIGN COMPONENT LS_MAP-STAGING_FIELD OF STRUCTURE LS_STG TO <FV>.
      IF SY-SUBRC = 0.
        CASE LS_MAP-BDC_FIELD.
          WHEN 'EKKO-LIFNR'. LV_LIFNR = <FV>. WHEN 'EKKO-EKORG'. LV_EKORG = <FV>. WHEN 'EKKO-EKGRP'. LV_EKGRP = <FV>. WHEN 'EKKO-BUKRS'. LV_BUKRS = <FV>.
          WHEN 'EKPO-MATNR'. LV_MATNR = <FV>. WHEN 'EKPO-MENGE'. LV_MENGE = <FV>. WHEN 'EKPO-WERKS'. LV_WERKS = <FV>. WHEN 'EKPO-NETPR'. LV_NETPR = <FV>.
        ENDCASE.
      ENDIF.
    ENDLOOP.

    REFRESH BDCDATA.
    PERFORM BDC_DYNPRO USING 'SAPLMEGUI' '0014'. PERFORM BDC_FIELD USING 'BDC_OKCODE' '/00'. PERFORM BDC_FIELD USING 'MEPO_TOPLINE-SUPERFIELD' LV_LIFNR.
    PERFORM BDC_DYNPRO USING 'SAPLMEGUI' '0014'. PERFORM BDC_FIELD USING 'BDC_OKCODE' '/00'. PERFORM BDC_FIELD USING 'MEPO1222-EKORG' LV_EKORG. PERFORM BDC_FIELD USING 'MEPO1222-EKGRP' LV_EKGRP. PERFORM BDC_FIELD USING 'MEPO1222-BUKRS' LV_BUKRS.
    PERFORM BDC_DYNPRO USING 'SAPLMEGUI' '0014'. PERFORM BDC_FIELD USING 'BDC_OKCODE' '/00'. PERFORM BDC_FIELD USING 'MEPO1211-EMATN(01)' LV_MATNR. PERFORM BDC_FIELD USING 'MEPO1211-MENGE(01)' LV_MENGE. PERFORM BDC_FIELD USING 'MEPO1211-NETPR(01)'
LV_NETPR. PERFORM BDC_FIELD USING 'MEPO1211-NAME1(01)' LV_WERKS.
    PERFORM BDC_DYNPRO USING 'SAPLMEGUI' '0014'. PERFORM BDC_FIELD USING 'BDC_OKCODE' '=MESAVE'.

    REFRESH MESSTAB.
    CALL TRANSACTION 'ME21N' USING BDCDATA MODE 'N' UPDATE 'S' MESSAGES INTO MESSTAB.

    READ TABLE MESSTAB INTO DATA(LS_MSG) WITH KEY MSGTYP = 'S' MSGID = '06' MSGNR = '017'.
    IF SY-SUBRC = 0. LS_STG-STATUS = 'SUCCESS'. LS_STG-ERROR_MSG = |Tao PO Thanh cong: { LS_MSG-MSGV2 }|.
    ELSE. LS_STG-STATUS = 'ERROR'. LS_STG-ERROR_MSG = 'Loi tao PO!'. ENDIF.
    MODIFY zbdc_staging_bup FROM LS_STG.
  ENDLOOP.

  COMMIT WORK AND WAIT.
  MESSAGE 'Chay BDC tao PO hoan tat!' TYPE 'S'.
ENDFORM.
*<<< END FORM RUN_BDC_FOR_SESSION

*>>> FORM z17_open_batch_group - moved from Z_BDC_MASS_PO_ENTRY_F01_BUP
FORM z17_open_batch_group
  USING    pv_group   TYPE apqi-groupid
  CHANGING cv_subrc   TYPE i
           cv_attempt TYPE i
           cv_reason  TYPE string.

  DATA: lv_max_attempts TYPE i,
        lv_subrc       TYPE i.

  CLEAR: cv_subrc, cv_attempt, cv_reason.
  lv_max_attempts = 1.
  IF chkp_retry = 'X'.
    lv_max_attempts = gc_max_attempts.
  ENDIF.

  DO lv_max_attempts TIMES.
    cv_attempt = sy-index.
    CALL FUNCTION 'BDC_OPEN_GROUP'
      EXPORTING
        client = sy-mandt
        group  = pv_group
        user   = sy-uname
        keep   = 'X'
      EXCEPTIONS
        client_invalid       = 1
        destination_invalid  = 2
        group_invalid        = 3
        group_is_locked      = 4
        holddate_invalid     = 5
        internal_error       = 6
        queue_error          = 7
        running              = 8
        system_lock_error    = 9
        user_invalid         = 10
        OTHERS               = 11.
    lv_subrc = sy-subrc.
    cv_subrc = lv_subrc.

    IF lv_subrc = 0.
      RETURN.
    ENDIF.

    IF lv_subrc = 4 OR lv_subrc = 7 OR
       lv_subrc = 8 OR lv_subrc = 9.
      CASE lv_subrc.
        WHEN 4. cv_reason = 'GROUP_LOCKED'.
        WHEN 7. cv_reason = 'QUEUE_BUSY'.
        WHEN 8. cv_reason = 'SESSION_RUNNING'.
        WHEN 9. cv_reason = 'SYSTEM_LOCK'.
      ENDCASE.
      IF cv_attempt < lv_max_attempts.
        WAIT UP TO gc_wait_seconds SECONDS.
        CONTINUE.
      ENDIF.
    ENDIF.
    EXIT.
  ENDDO.
ENDFORM.

*&---------------------------------------------------------------------*
*& V5AG - Insert one transaction into an open session with safe retry
*&---------------------------------------------------------------------*
*<<< END FORM z17_open_batch_group

*>>> FORM z17_insert_batch_group - moved from Z_BDC_MASS_PO_ENTRY_F01_BUP
FORM z17_insert_batch_group
  USING    pv_tcode   TYPE sy-tcode
  CHANGING cv_subrc   TYPE i
           cv_attempt TYPE i
           cv_reason  TYPE string.

  DATA: lv_max_attempts TYPE i,
        lv_subrc       TYPE i.

  CLEAR: cv_subrc, cv_attempt, cv_reason.
  lv_max_attempts = 1.
  IF chkp_retry = 'X'.
    lv_max_attempts = gc_max_attempts.
  ENDIF.

  DO lv_max_attempts TIMES.
    cv_attempt = sy-index.
    CALL FUNCTION 'BDC_INSERT'
      EXPORTING
        tcode     = pv_tcode
      TABLES
        dynprotab = bdcdata
      EXCEPTIONS
        internal_error    = 1
        not_open          = 2
        queue_error       = 3
        tcode_invalid     = 4
        printing_invalid  = 5
        posting_invalid   = 6
        OTHERS            = 7.
    lv_subrc = sy-subrc.
    cv_subrc = lv_subrc.

    IF lv_subrc = 0.
      RETURN.
    ENDIF.

    IF lv_subrc = 1 OR lv_subrc = 3.
      IF lv_subrc = 1.
        cv_reason = 'SESSION_INTERNAL_BUSY'.
      ELSE.
        cv_reason = 'SESSION_QUEUE_BUSY'.
      ENDIF.
      IF cv_attempt < lv_max_attempts.
        WAIT UP TO gc_wait_seconds SECONDS.
        CONTINUE.
      ENDIF.
    ENDIF.
    EXIT.
  ENDDO.
ENDFORM.

*&---------------------------------------------------------------------*
*& V5AG - Build the exact selected document keys before DB chunk reads
*&---------------------------------------------------------------------*
*<<< END FORM z17_insert_batch_group

*>>> FORM z17_build_engine_keys - moved from Z_BDC_MASS_PO_ENTRY_F01_BUP
FORM z17_build_engine_keys
  USING    pt_process TYPE ty_t_staging_alv
  CHANGING ct_keys    TYPE ty_t_engine_group_key.

  DATA: lt_sorted TYPE ty_t_staging_alv,
        ls_row    TYPE ty_staging_alv,
        ls_key    TYPE ty_engine_group_key.

  REFRESH ct_keys.
  lt_sorted = pt_process.
  SORT lt_sorted BY session_id record_key row_index.

  LOOP AT lt_sorted INTO ls_row.
    CLEAR ls_key.
    ls_key-session_id = ls_row-session_id.
    ls_key-record_key = ls_row-record_key.
    IF ls_key-record_key IS INITIAL.
      ls_key-row_index = ls_row-row_index.
    ELSE.
      CLEAR ls_key-row_index.
    ENDIF.

    READ TABLE ct_keys TRANSPORTING NO FIELDS
      WITH KEY session_id = ls_key-session_id
               record_key = ls_key-record_key
               row_index  = ls_key-row_index.
    IF sy-subrc <> 0.
      APPEND ls_key TO ct_keys.
    ENDIF.
  ENDLOOP.
ENDFORM.

*&---------------------------------------------------------------------*
*& V5AG - Read one true database chunk for only the selected group keys
*&---------------------------------------------------------------------*
*<<< END FORM z17_build_engine_keys

*>>> FORM z17_load_engine_chunk - moved from Z_BDC_MASS_PO_ENTRY_F01_BUP
FORM z17_load_engine_chunk
  USING    pt_keys     TYPE ty_t_engine_group_key
           pt_fallback TYPE ty_t_staging_alv
  CHANGING ct_chunk    TYPE ty_t_staging_alv.

  DATA: lt_rec_keys TYPE ty_t_engine_group_key,
        lt_row_keys TYPE ty_t_engine_group_key,
        lt_db       TYPE STANDARD TABLE OF zbdc_staging_bup,
        ls_db       TYPE zbdc_staging_bup,
        ls_key      TYPE ty_engine_group_key,
        ls_row      TYPE ty_staging_alv,
        ls_fb       TYPE ty_staging_alv,
        lv_found    TYPE abap_bool.

  REFRESH: ct_chunk, lt_rec_keys, lt_row_keys.

  LOOP AT pt_keys INTO ls_key.
    IF ls_key-record_key IS INITIAL.
      APPEND ls_key TO lt_row_keys.
    ELSE.
      APPEND ls_key TO lt_rec_keys.
    ENDIF.
  ENDLOOP.

  IF lt_rec_keys IS NOT INITIAL.
    REFRESH lt_db.
    SELECT * FROM zbdc_staging_bup
      INTO TABLE lt_db
      FOR ALL ENTRIES IN lt_rec_keys
      WHERE session_id = lt_rec_keys-session_id
        AND record_key = lt_rec_keys-record_key.
    LOOP AT lt_db INTO ls_db.
      CLEAR ls_row.
      MOVE-CORRESPONDING ls_db TO ls_row.
      APPEND ls_row TO ct_chunk.
    ENDLOOP.
  ENDIF.

  IF lt_row_keys IS NOT INITIAL.
    REFRESH lt_db.
    SELECT * FROM zbdc_staging_bup
      INTO TABLE lt_db
      FOR ALL ENTRIES IN lt_row_keys
      WHERE session_id = lt_row_keys-session_id
        AND row_index  = lt_row_keys-row_index.
    LOOP AT lt_db INTO ls_db.
      CLEAR ls_row.
      MOVE-CORRESPONDING ls_db TO ls_row.
      APPEND ls_row TO ct_chunk.
    ENDLOOP.
  ENDIF.

  "Fallback protects a just-edited row that has not reached DB yet; normal
  "productive execution is sourced from ZBDC_STAGING_BUP above.
  LOOP AT pt_keys INTO ls_key.
    CLEAR lv_found.
    LOOP AT ct_chunk INTO ls_row
      WHERE session_id = ls_key-session_id.
      IF ( ls_key-record_key IS NOT INITIAL AND
           ls_row-record_key = ls_key-record_key ) OR
         ( ls_key-record_key IS INITIAL AND
           ls_row-row_index = ls_key-row_index ).
        lv_found = abap_true.
        EXIT.
      ENDIF.
    ENDLOOP.

    IF lv_found <> abap_true.
      LOOP AT pt_fallback INTO ls_fb
        WHERE session_id = ls_key-session_id.
        IF ( ls_key-record_key IS NOT INITIAL AND
             ls_fb-record_key = ls_key-record_key ) OR
           ( ls_key-record_key IS INITIAL AND
             ls_fb-row_index = ls_key-row_index ).
          APPEND ls_fb TO ct_chunk.
        ENDIF.
      ENDLOOP.
    ENDIF.
  ENDLOOP.

  SORT ct_chunk BY session_id record_key row_index.
  DELETE ADJACENT DUPLICATES FROM ct_chunk
    COMPARING session_id row_index.
ENDFORM.

*&---------------------------------------------------------------------*
*& V5AG - Process all document groups contained in one loaded DB chunk
*&---------------------------------------------------------------------*
*<<< END FORM z17_load_engine_chunk

*>>> FORM z17_process_eng_chunk - moved from Z_BDC_MASS_PO_ENTRY_F01_BUP
FORM z17_process_eng_chunk
  USING    pt_chunk  TYPE ty_t_staging_alv
           pt_s_pre  TYPE ty_t_script
           pt_s_item TYPE ty_t_script
           pt_s_post TYPE ty_t_script
           pt_map    TYPE ty_t_map
           pv_tcode  TYPE sy-tcode
           pv_mode   TYPE clike
           pv_upd    TYPE clike
           pv_bigrp  TYPE apqi-groupid
  CHANGING cv_groups TYPE i
           cv_ok     TYPE i
           cv_err    TYPE i.

  DATA: lt_sorted     TYPE ty_t_staging_alv,
        lt_group      TYPE ty_t_staging_alv,
        ls_row        TYPE ty_staging_alv,
        lv_prev_key   TYPE zbdc_staging_bup-record_key,
        lv_curr_key   TYPE zbdc_staging_bup-record_key,
        lv_prev_sess  TYPE zbdc_staging_bup-session_id,
        lv_curr_sess  TYPE zbdc_staging_bup-session_id,
        lv_err_before TYPE i.

  IF pt_chunk IS INITIAL.
    RETURN.
  ENDIF.

  lt_sorted = pt_chunk.
  SORT lt_sorted BY session_id record_key row_index.
  REFRESH lt_group.
  CLEAR: lv_prev_key, lv_prev_sess.

  LOOP AT lt_sorted INTO ls_row.
    IF g_stop_flag = 'X'.
      EXIT.
    ENDIF.

    lv_curr_key  = ls_row-record_key.
    lv_curr_sess = ls_row-session_id.
    IF lv_curr_key IS INITIAL.
      lv_curr_key = ls_row-row_index.
    ENDIF.

    IF lt_group IS NOT INITIAL AND
       ( lv_curr_key <> lv_prev_key OR lv_curr_sess <> lv_prev_sess ).
      lv_err_before = cv_err.
      PERFORM run_bdc_one_group
        USING    lt_group pt_s_pre pt_s_item pt_s_post pt_map
                 pv_tcode pv_mode pv_upd pv_bigrp
        CHANGING cv_ok cv_err.
      cv_groups = cv_groups + 1.
      PERFORM z18_progress_after_group USING lt_group.
      IF chkp_stop_on_error = 'X' AND cv_err > lv_err_before.
        g_stop_flag = 'X'.
        EXIT.
      ENDIF.
      REFRESH lt_group.
    ENDIF.

    APPEND ls_row TO lt_group.
    lv_prev_key  = lv_curr_key.
    lv_prev_sess = lv_curr_sess.
  ENDLOOP.

  IF lt_group IS NOT INITIAL AND g_stop_flag <> 'X'.
    lv_err_before = cv_err.
    PERFORM run_bdc_one_group
      USING    lt_group pt_s_pre pt_s_item pt_s_post pt_map
               pv_tcode pv_mode pv_upd pv_bigrp
      CHANGING cv_ok cv_err.
    cv_groups = cv_groups + 1.
    PERFORM z18_progress_after_group USING lt_group.
    IF chkp_stop_on_error = 'X' AND cv_err > lv_err_before.
      g_stop_flag = 'X'.
    ENDIF.
  ENDIF.
ENDFORM.

*&---------------------------------------------------------------------*
*& EXECUTE_BDC_ENGINE - single entry point cua Muc 2
*&   PT_PROCESS: cac dong da qua validation tren Screen 0400
*&   Design:
*&   1. Runtime options tu Screen 0200
*&   2. Load BDC script tu ZBDC_SCT_DEF_BUP va tach PRE/ITEM/POST
*&   3. Load mapping profile tu ZBDC_MAPPING_BUP
*&   4. Group theo RECORD_KEY/PO_KEY -> 1 group = 1 SAP document
*&   5. Run CALL TRANSACTION hoac Batch Input Session
*&   6. Commit theo chunk BATCH_SIZE
*&---------------------------------------------------------------------*
*<<< END FORM z17_process_eng_chunk

*>>> FORM EXECUTE_BDC_ENGINE - moved from Z_BDC_MASS_PO_ENTRY_F01_BUP
FORM EXECUTE_BDC_ENGINE USING PT_PROCESS   LIKE GT_STAGING_ALV
                              PV_EXEC_MODE TYPE CSEQUENCE.
  DATA: LT_PROC      TYPE TY_T_STAGING_ALV,
        LT_GROUP     TYPE TY_T_STAGING_ALV,
        LT_KEYS      TYPE TY_T_ENGINE_GROUP_KEY,
        LT_KEY_CHUNK TYPE TY_T_ENGINE_GROUP_KEY,
        LS_KEY       TYPE TY_ENGINE_GROUP_KEY,
        LS_ROW       TYPE TY_STAGING_ALV,
        LV_TCODE   TYPE SY-TCODE,
        LT_S_PRE   TYPE TY_T_SCRIPT,
        LT_S_ITEM  TYPE TY_T_SCRIPT,
        LT_S_POST  TYPE TY_T_SCRIPT,
        LT_MAP     TYPE TY_T_MAP,
        LV_MODE    TYPE C LENGTH 1,
        LV_UPD     TYPE C LENGTH 1,
        LV_BSIZE   TYPE I,
        LV_GROUPS  TYPE I,
        LV_OKGRP   TYPE I,
        LV_ERRGRP  TYPE I,
        LV_ERR_BEFORE TYPE I,
        LV_PREVKEY TYPE ZBDC_STAGING_BUP-RECORD_KEY,
        LV_CURRKEY TYPE ZBDC_STAGING_BUP-RECORD_KEY,
        LV_PREVSES TYPE ZBDC_STAGING_BUP-SESSION_ID,
        LV_CURRSES TYPE ZBDC_STAGING_BUP-SESSION_ID,
        LV_BIGROUP TYPE APQI-GROUPID,
        LV_MSG     TYPE STRING,
        LV_PROFILE_OK TYPE ABAP_BOOL,
        LV_REQUESTED_ENGINE TYPE CHAR30.

  IF PT_PROCESS IS INITIAL.
    MESSAGE 'Khong co dong nao du dieu kien xu ly.' TYPE 'W'.
    RETURN.
  ENDIF.

  "Freeze the requested engine before GET_RUNTIME_OPTIONS. That form calls
  "LOAD_SOURCE_CONFIG and may overwrite P_BDC_MODE with the saved profile.
  "The button/action parameter is therefore the source of truth for this run.
  LV_REQUESTED_ENGINE = PV_EXEC_MODE.
  PERFORM GET_RUNTIME_OPTIONS CHANGING LV_MODE LV_UPD LV_BSIZE.

  IF LV_REQUESTED_ENGINE = GC_MODE_CALL OR
     LV_REQUESTED_ENGINE = GC_MODE_BATCH.
    P_BDC_MODE = LV_REQUESTED_ENGINE.
  ENDIF.

  READ TABLE PT_PROCESS INTO LS_ROW INDEX 1.
  LV_TCODE = LS_ROW-TCODE.
  IF LV_TCODE IS INITIAL.
    LV_TCODE = P_TRANSACTION.
  ENDIF.
  IF LV_TCODE IS INITIAL.
    MESSAGE 'Khong xac dinh duoc TCODE de chay BDC.' TYPE 'E'.
    RETURN.
  ENDIF.

  "SENIOR NOTE - TARGET TCODE AUTHORIZATION CHECK (SOFT FOR DEMO):
  "Check quyen theo transaction dich that su cua engine (ME21N/MIGO),
  "khong dung SY-TCODE cua report/SE38 nua. Trong production co the doi
  "MESSAGE TYPE 'W' thanh TYPE 'E' + RETURN de chan user thieu quyen.
  AUTHORITY-CHECK OBJECT 'S_TCODE'
    ID 'TCD' FIELD LV_TCODE.
  IF SY-SUBRC <> 0.
    MESSAGE |CANH BAO: user { SY-UNAME } chua co S_TCODE cho target { LV_TCODE }. Kiem tra PFCG truoc khi dung production.| TYPE 'W'.
  ENDIF.

  PERFORM LOAD_SCRIPT_DEFINITION
    USING    LV_TCODE
    CHANGING LT_S_PRE LT_S_ITEM LT_S_POST.

  IF LT_S_PRE IS INITIAL AND LT_S_ITEM IS INITIAL AND LT_S_POST IS INITIAL.
    MESSAGE |Chua co BDC script cho { LV_TCODE } trong ZBDC_SCT_DEF_BUP.| TYPE 'E'.
    RETURN.
  ENDIF.

  PERFORM LOAD_MAPPING_PROFILE
    USING    LV_TCODE
    CHANGING LT_MAP.

  IF LT_MAP IS INITIAL.
    MESSAGE |Mapping profile { TXTP_PROFILE_NAME } rong. Kiem tra ZBDC_MAPPING_BUP.| TYPE 'E'.
    RETURN.
  ENDIF.

  "V5AD CONCURRENT-USER LOCK:
  "Acquire one exclusive lock for the current ingestion batch. Users may
  "review the same history concurrently, but Run/Resubmit/Retry cannot update
  "the same batch at the same time.
  DATA: lv_lock_can_run TYPE abap_bool,
        lv_lock_active  TYPE abap_bool.

  PERFORM acquire_staging_lock_safe
    USING    ls_row-session_id
    CHANGING lv_lock_can_run lv_lock_active.

  IF lv_lock_can_run <> abap_true.
    RETURN.
  ENDIF.

  PERFORM PREVIEW_ENGINE_PLAN USING LV_TCODE LT_S_PRE LT_S_ITEM LT_S_POST LT_MAP LV_BSIZE.

  "Build the exact selected document keys before opening SM35. The first
  "real group is dry-built and validated, so a bad script cannot leave an
  "empty 0-transaction technical session in the user's SM35 list.
  PERFORM z17_build_engine_keys
    USING    PT_PROCESS
    CHANGING LT_KEYS.

  IF LT_KEYS IS INITIAL.
    PERFORM release_staging_lock USING ls_row-session_id.
    MESSAGE 'No document-group key could be built for BDC processing.' TYPE 'E'.
    RETURN.
  ENDIF.

  "A new SM35 run must not inherit protocol rows from an older session for
  "the same business group. Purge only SM35 technical logs; keep all normal
  "validation/execution history intact.
  IF P_BDC_MODE = GC_MODE_BATCH.
    LOOP AT LT_KEYS INTO LS_KEY.
      PERFORM z17_purge_sm35_group_log USING LS_KEY.
    ENDLOOP.
    COMMIT WORK AND WAIT.
  ENDIF.

  IF P_BDC_MODE = GC_MODE_BATCH.
    DATA: lv_preflight_ok  TYPE abap_bool,
          lv_preflight_msg TYPE string.

    READ TABLE LT_KEYS INTO LS_KEY INDEX 1.
    REFRESH LT_GROUP.
    PERFORM z17_collect_group_key
      USING    PT_PROCESS LS_KEY
      CHANGING LT_GROUP.

    PERFORM z20_preflight_sm35_group
      USING    LT_GROUP LT_S_PRE LT_S_ITEM LT_S_POST LT_MAP LV_TCODE
      CHANGING lv_preflight_ok lv_preflight_msg.

    REFRESH BDCDATA.
    IF lv_preflight_ok <> abap_true.
      PERFORM release_staging_lock USING ls_row-session_id.
      MESSAGE lv_preflight_msg TYPE 'S' DISPLAY LIKE 'E'.
      RETURN.
    ENDIF.
    DATA: lv_open_subrc   TYPE i,
          lv_open_attempt TYPE i,
          lv_open_reason  TYPE string.

    CLEAR: GV_LAST_SM35_GROUP, GV_LAST_SM35_QID,
           GV_LAST_SM35_INSERTED, GV_LAST_SM35_EXPECTED.
    CONCATENATE 'ZBDC' SY-DATUM+4(4) SY-UZEIT INTO LV_BIGROUP.
    PERFORM z17_open_batch_group
      USING    LV_BIGROUP
      CHANGING lv_open_subrc lv_open_attempt lv_open_reason.

    IF lv_open_subrc <> 0.
      PERFORM release_staging_lock USING ls_row-session_id.
      MESSAGE |Cannot open Batch Input session after { lv_open_attempt } attempt(s): { lv_open_reason }, sy-subrc={ lv_open_subrc }.| TYPE 'E'.
      RETURN.
    ENDIF.
  ENDIF.

  "V5AG/V5AL strict chunk processing: LT_KEYS was already built and
  "preflighted before opening a Batch Input Session.
  IF P_BDC_MODE = GC_MODE_BATCH.
    GV_LAST_SM35_EXPECTED = LINES( LT_KEYS ).
  ENDIF.

  CLEAR: G_EXEC_CURR, G_EXEC_SUCCESS, G_EXEC_ERROR,
         LV_GROUPS, LV_OKGRP, LV_ERRGRP, GV_EXEC_RUN_QUEUED.
  G_STOP_FLAG = SPACE.
  REFRESH LT_KEY_CHUNK.

  LOOP AT LT_KEYS INTO LS_KEY.
    APPEND LS_KEY TO LT_KEY_CHUNK.

    IF LINES( LT_KEY_CHUNK ) >= LV_BSIZE.
      REFRESH LT_PROC.
      PERFORM z17_load_engine_chunk
        USING    LT_KEY_CHUNK PT_PROCESS
        CHANGING LT_PROC.
      PERFORM z17_process_eng_chunk
        USING    LT_PROC LT_S_PRE LT_S_ITEM LT_S_POST LT_MAP
                 LV_TCODE LV_MODE LV_UPD LV_BIGROUP
        CHANGING LV_GROUPS LV_OKGRP LV_ERRGRP.

      IF P_BDC_MODE = GC_MODE_CALL.
        COMMIT WORK AND WAIT.
      ENDIF.
      REFRESH LT_KEY_CHUNK.

      IF G_STOP_FLAG = 'X'.
        EXIT.
      ENDIF.
    ENDIF.
  ENDLOOP.

  IF LT_KEY_CHUNK IS NOT INITIAL AND G_STOP_FLAG <> 'X'.
    REFRESH LT_PROC.
    PERFORM z17_load_engine_chunk
      USING    LT_KEY_CHUNK PT_PROCESS
      CHANGING LT_PROC.
    PERFORM z17_process_eng_chunk
      USING    LT_PROC LT_S_PRE LT_S_ITEM LT_S_POST LT_MAP
               LV_TCODE LV_MODE LV_UPD LV_BIGROUP
      CHANGING LV_GROUPS LV_OKGRP LV_ERRGRP.

    IF P_BDC_MODE = GC_MODE_CALL.
      COMMIT WORK AND WAIT.
    ENDIF.
  ENDIF.

  IF P_BDC_MODE = GC_MODE_BATCH.
    GV_LAST_SM35_INSERTED = LV_OKGRP.

    CALL FUNCTION 'BDC_CLOSE_GROUP'
      EXCEPTIONS
        NOT_OPEN    = 1
        QUEUE_ERROR = 2
        OTHERS      = 3.
    COMMIT WORK AND WAIT.
    IF SY-SUBRC = 0.
      GV_LAST_SM35_GROUP = LV_BIGROUP.
      PERFORM z16_find_sm35_qid
        USING    LV_BIGROUP
        CHANGING GV_LAST_SM35_QID.

      IF GV_LAST_SM35_INSERTED <= 0.
        "Never execute or label an empty technical session as successful.
        "All rejected groups already carry their real preflight/insert error.
        LV_PROFILE_OK = ABAP_FALSE.
        LV_MSG = |SM35 session { LV_BIGROUP } contains 0 inserted transaction(s); processing was not started. Review Error Detail and re-record/fix the script.|.
        GV_LAST_SM35_ACTION = LV_MSG.
        MESSAGE LV_MSG TYPE 'S' DISPLAY LIKE 'E'.
      ELSE.
        "V5Q: consume the same setup profile used by CALL TRANSACTION.
        "A/E/N controls the Batch Input processing mode. S/A controls whether
        "the session is started now and waited for, or released/queued and returned.
        PERFORM z16_apply_sm35_profile
          USING    LV_BIGROUP GV_LAST_SM35_QID LV_MODE LV_UPD
          CHANGING LV_PROFILE_OK LV_MSG.

        IF LV_MODE = 'N'.
          "Non-blocking managed SM35 path: do not wait/reconcile inside the
          "creation PAI. Screen 0500 owns the timer and will reconcile only
          "after APQI/job status reaches a real terminal state.
          IF GV_LAST_SM35_ACTION IS NOT INITIAL.
            LV_MSG = GV_LAST_SM35_ACTION.
          ENDIF.
        ELSE.
          IF LV_UPD = GC_SM35_SYNC.
            PERFORM z18_wait_sm35_terminal USING GV_LAST_SM35_QID 10.
          ENDIF.
          PERFORM z16_reconcile_sm35
            USING PT_PROCESS LV_BIGROUP GV_LAST_SM35_QID LV_MSG.

          IF GV_LAST_SM35_ACTION IS NOT INITIAL.
            LV_MSG = GV_LAST_SM35_ACTION.
          ENDIF.
        ENDIF.

        IF LV_PROFILE_OK = ABAP_TRUE.
          MESSAGE LV_MSG TYPE 'S'.
        ELSE.
          MESSAGE LV_MSG TYPE 'S' DISPLAY LIKE 'W'.
        ENDIF.
      ENDIF.
    ELSE.
      LV_MSG = |BDC_CLOSE_GROUP failed, sy-subrc={ SY-SUBRC }. Check SM35.|.
      MESSAGE LV_MSG TYPE 'S' DISPLAY LIKE 'W'.
    ENDIF.
    PERFORM upd_all_rt_sess_sum.
    PERFORM release_staging_lock USING ls_row-session_id.
    RETURN.
  ENDIF.

  COMMIT WORK AND WAIT.

  " V4R: write/rebuild summary for every session in this batch execution.
  DATA lt_exec_sid TYPE STANDARD TABLE OF zbdc_staging_bup-session_id.
  DATA lv_exec_sid TYPE zbdc_staging_bup-session_id.
  LOOP AT PT_PROCESS INTO DATA(ls_sum_row).
    READ TABLE lt_exec_sid INTO lv_exec_sid WITH KEY table_line = ls_sum_row-session_id.
    IF sy-subrc <> 0.
      APPEND ls_sum_row-session_id TO lt_exec_sid.
    ENDIF.
  ENDLOOP.
  LOOP AT lt_exec_sid INTO lv_exec_sid.
    PERFORM update_session_summary USING lv_exec_sid.
  ENDLOOP.

  IF G_STOP_FLAG = 'X'.
    LV_MSG = |Da STOP sau { LV_GROUPS } nhom. OK={ LV_OKGRP }, Error={ LV_ERRGRP }.|.
    MESSAGE LV_MSG TYPE 'W'.
  ELSE.
    LV_MSG = |BDC xong: { LV_OKGRP }/{ LV_GROUPS } nhom thanh cong, { LV_ERRGRP } loi.|.
    MESSAGE LV_MSG TYPE 'S'.
  ENDIF.

  PERFORM release_staging_lock USING ls_row-session_id.
ENDFORM.
*<<< END FORM EXECUTE_BDC_ENGINE

*>>> FORM acquire_staging_lock_safe - moved from Z_BDC_MASS_PO_ENTRY_F01_BUP
FORM acquire_staging_lock_safe
  USING    iv_session_id TYPE zbdc_staging_bup-session_id
  CHANGING cv_can_run    TYPE abap_bool
           cv_locked     TYPE abap_bool.

  DATA: lv_batch_key TYPE zbdc_staging_bup-session_id,
        lv_varkey    TYPE rstable-varkey,
        lv_holder    TYPE syuname.

  CLEAR: cv_can_run, cv_locked.

  IF iv_session_id IS INITIAL.
    MESSAGE 'Cannot lock processing scope: session ID is empty.' TYPE 'S' DISPLAY LIKE 'E'.
    RETURN.
  ENDIF.

  PERFORM z16_batch_prefix_from_sid
    USING    iv_session_id
    CHANGING lv_batch_key.

  IF lv_batch_key IS INITIAL.
    lv_batch_key = iv_session_id.
  ENDIF.

  "Standard SAP generic enqueue, scoped by MANDT + batch prefix.
  "Different batches run in parallel; the same batch is exclusive.
  CONCATENATE sy-mandt lv_batch_key INTO lv_varkey.

  CALL FUNCTION 'ENQUEUE_E_TABLE'
    EXPORTING
      mode_rstable   = 'E'
      tabname        = 'ZBDC_STAGING_BUP'
      varkey         = lv_varkey
      _scope         = '1'
      _wait          = space
    EXCEPTIONS
      foreign_lock   = 1
      system_failure = 2
      OTHERS         = 3.

  CASE sy-subrc.
    WHEN 0.
      cv_can_run = abap_true.
      cv_locked  = abap_true.
    WHEN 1.
      lv_holder = sy-msgv1.
      IF lv_holder IS INITIAL.
        lv_holder = 'ANOTHER USER'.
      ENDIF.
      MESSAGE |Batch { lv_batch_key } is already being processed by { lv_holder }. Keep reviewing it read-only and try again after Refresh.| TYPE 'S' DISPLAY LIKE 'E'.
    WHEN OTHERS.
      MESSAGE |Batch lock service failed for { lv_batch_key } (sy-subrc={ sy-subrc }). Processing was not started.| TYPE 'S' DISPLAY LIKE 'E'.
  ENDCASE.
ENDFORM.
*<<< END FORM acquire_staging_lock_safe

*>>> FORM release_staging_lock - moved from Z_BDC_MASS_PO_ENTRY_F01_BUP

FORM release_staging_lock
  USING iv_session_id TYPE zbdc_staging_bup-session_id.

  DATA: lv_batch_key TYPE zbdc_staging_bup-session_id,
        lv_varkey    TYPE rstable-varkey.

  IF iv_session_id IS INITIAL.
    RETURN.
  ENDIF.

  PERFORM z16_batch_prefix_from_sid
    USING    iv_session_id
    CHANGING lv_batch_key.

  IF lv_batch_key IS INITIAL.
    lv_batch_key = iv_session_id.
  ENDIF.

  CONCATENATE sy-mandt lv_batch_key INTO lv_varkey.

  CALL FUNCTION 'DEQUEUE_E_TABLE'
    EXPORTING
      mode_rstable = 'E'
      tabname      = 'ZBDC_STAGING_BUP'
      varkey       = lv_varkey
      _scope       = '1'.
ENDFORM.


*& save_ingestion_source_log
*& Persist REAL inbound source per session. Do not derive 0100 Source from
*& current config, because config may change after old sessions were loaded.
*&---------------------------------------------------------------------*
*<<< END FORM release_staging_lock

*>>> FORM RESUBMIT_SESSION_FROM_0100 - moved from Z_BDC_MASS_PO_ENTRY_F01_BUP

FORM RESUBMIT_SESSION_FROM_0100.
  DATA: LV_SESSION_ID TYPE ZBDC_RESULT_BUP-SESSION_ID,
        LV_COUNT      TYPE I,
        LT_RETRY      TYPE STANDARD TABLE OF ZBDC_STAGING_BUP,
        LV_LOCK_OK    TYPE ABAP_BOOL,
        LV_LOCKED     TYPE ABAP_BOOL.

  PERFORM GET_0100_SELECTED_SESSION CHANGING LV_SESSION_ID.
  IF LV_SESSION_ID IS INITIAL.
    MESSAGE 'Chon 1 session tren dashboard truoc khi Resubmit.' TYPE 'W'.
    RETURN.
  ENDIF.

  SELECT * FROM ZBDC_STAGING_BUP
    INTO TABLE @LT_RETRY
    WHERE SESSION_ID = @LV_SESSION_ID
      AND STATUS     = @GC_ST_ERROR.

  IF LT_RETRY IS INITIAL.
    MESSAGE |Session { LV_SESSION_ID } khong co dong ERROR de resubmit.| TYPE 'S'.
    PERFORM LOAD_STAGING_BY_SESSION USING LV_SESSION_ID CHANGING LV_COUNT.
    IF LV_COUNT > 0.
      PERFORM OPEN_0400_FOR_CURRENT_STAGING.
    ENDIF.
    RETURN.
  ENDIF.

  PERFORM acquire_staging_lock_safe
    USING    LV_SESSION_ID
    CHANGING LV_LOCK_OK LV_LOCKED.
  IF LV_LOCK_OK <> ABAP_TRUE.
    RETURN.
  ENDIF.

  LOOP AT LT_RETRY ASSIGNING FIELD-SYMBOL(<LS_RETRY_0100>).
    <LS_RETRY_0100>-STATUS    = GC_ST_READY.
    <LS_RETRY_0100>-ERROR_MSG = ''.
    MODIFY ZBDC_STAGING_BUP FROM <LS_RETRY_0100>.
  ENDLOOP.
  COMMIT WORK AND WAIT.
  PERFORM update_session_summary USING LV_SESSION_ID.
  PERFORM release_staging_lock USING LV_SESSION_ID.

  PERFORM LOAD_STAGING_BY_SESSION USING LV_SESSION_ID CHANGING LV_COUNT.
  MESSAGE |Resubmit prepared: { LINES( LT_RETRY ) } ERROR row(s) reset to READY. Run Selected/Run All de chay lai.| TYPE 'S'.
  IF LV_COUNT > 0.
    PERFORM OPEN_0400_FOR_CURRENT_STAGING.
  ENDIF.
ENDFORM.
*<<< END FORM RESUBMIT_SESSION_FROM_0100

*>>> FORM z16_sm35_profile_label - moved from Z_BDC_MASS_PO_ENTRY_F01_BUP
FORM z16_sm35_profile_label
  USING    pv_mode   TYPE c
           pv_policy TYPE c
  CHANGING cv_text   TYPE string.

  DATA: lv_upd_text TYPE string,
        lv_upd      TYPE c LENGTH 1.

  lv_upd = pv_policy.
  IF lv_upd <> 'A' AND lv_upd <> 'S'.
    lv_upd = 'S'.
  ENDIF.

  IF lv_upd = 'A'.
    lv_upd_text = 'Async update'.
  ELSE.
    lv_upd_text = 'Sync update'.
  ENDIF.

  CASE pv_mode.
    WHEN 'A'.
      cv_text = |A/{ lv_upd } - All screens / { lv_upd_text }|.
    WHEN 'E'.
      cv_text = |E/{ lv_upd } - Errors only / { lv_upd_text }|.
    WHEN 'N'.
      cv_text = |N/{ lv_upd } - No display / { lv_upd_text }|.
    WHEN OTHERS.
      cv_text = |{ pv_mode }/{ lv_upd } - Invalid Batch Input profile|.
  ENDCASE.
ENDFORM.
*<<< END FORM z16_sm35_profile_label

*>>> FORM z16_find_sm35_qid - moved from Z_BDC_MASS_PO_ENTRY_F01_BUP

FORM z16_find_sm35_qid
  USING    pv_group TYPE apqi-groupid
  CHANGING cv_qid   TYPE apqi-qid.

  "Compatibility-safe lookup: avoid mixing strict Open SQL host escaping
  "with ORDER BY syntax on older ABAP releases. Read matching rows and sort
  "in ABAP, then return the newest queue ID.
  TYPES: BEGIN OF ty_qid_lookup,
           qid     TYPE apqi-qid,
           credate TYPE apqi-credate,
           cretime TYPE apqi-cretime,
         END OF ty_qid_lookup.

  DATA: lt_qid_lookup TYPE STANDARD TABLE OF ty_qid_lookup,
        ls_qid_lookup TYPE ty_qid_lookup.

  CLEAR cv_qid.

  SELECT qid credate cretime
    INTO TABLE lt_qid_lookup
    FROM apqi
    WHERE mandant = sy-mandt
      AND groupid = pv_group
      AND userid  = sy-uname.

  SORT lt_qid_lookup BY credate DESCENDING
                        cretime DESCENDING.

  READ TABLE lt_qid_lookup INTO ls_qid_lookup INDEX 1.
  IF sy-subrc = 0.
    cv_qid = ls_qid_lookup-qid.
  ENDIF.
ENDFORM.

*&---------------------------------------------------------------------*
*& V5AG - Read detailed SM35 protocol lines from the standard TemSe log
*&---------------------------------------------------------------------*
*<<< END FORM z16_find_sm35_qid

*>>> FORM z17_get_sm35_log - moved from Z_BDC_MASS_PO_ENTRY_F01_BUP
FORM z17_get_sm35_log
  USING    pv_qid TYPE apqi-qid
  CHANGING ct_log TYPE ty_t_bdclm.

  DATA: lt_apql  TYPE STANDARD TABLE OF apql,
        ls_apql  TYPE apql,
        lv_handle TYPE rststype-fbhandle.

  REFRESH: ct_log, lt_apql.
  IF pv_qid IS INITIAL.
    RETURN.
  ENDIF.

  CALL FUNCTION 'BDC_PROTOCOL_SELECT_QID'
    EXPORTING
      queue_id = pv_qid
    TABLES
      apqltab  = lt_apql
    EXCEPTIONS
      invalid_data = 1
      OTHERS       = 2.
  IF sy-subrc <> 0 OR lt_apql IS INITIAL.
    RETURN.
  ENDIF.

  LOOP AT lt_apql INTO ls_apql.
    CLEAR lv_handle.
    CALL FUNCTION 'RSTS_OPEN_RLC'
      EXPORTING
        authority = 'BATCH'
        name      = ls_apql-temseid
      IMPORTING
        fbhandle  = lv_handle
      EXCEPTIONS
        OTHERS    = 10.
    IF sy-subrc <> 0.
      CONTINUE.
    ENDIF.

    CALL FUNCTION 'RSTS_READ'
      EXPORTING
        fbhandle = lv_handle
      TABLES
        datatab  = ct_log
      EXCEPTIONS
        OTHERS   = 5.

    CALL FUNCTION 'RSTS_CLOSE'
      EXPORTING
        fbhandle = lv_handle
      EXCEPTIONS
        OTHERS   = 4.
  ENDLOOP.
ENDFORM.
*<<< END FORM z17_get_sm35_log

*>>> FORM z17_collect_group_key - moved from Z_BDC_MASS_PO_ENTRY_F01_BUP

FORM z17_collect_group_key
  USING    pt_process TYPE ty_t_staging_alv
           ps_key     TYPE ty_engine_group_key
  CHANGING ct_group   TYPE ty_t_staging_alv.

  DATA ls_row TYPE ty_staging_alv.
  REFRESH ct_group.

  LOOP AT pt_process INTO ls_row
    WHERE session_id = ps_key-session_id.
    IF ( ps_key-record_key IS NOT INITIAL AND
         ls_row-record_key = ps_key-record_key ) OR
       ( ps_key-record_key IS INITIAL AND
         ls_row-row_index = ps_key-row_index ).
      APPEND ls_row TO ct_group.
    ENDIF.
  ENDLOOP.
ENDFORM.
*<<< END FORM z17_collect_group_key

*>>> FORM z17_purge_sm35_group_log - moved from Z_BDC_MASS_PO_ENTRY_F01_BUP

FORM z17_purge_sm35_group_log
  USING ps_key TYPE ty_engine_group_key.

  IF ps_key-record_key IS INITIAL.
    DELETE FROM zbdc_result_bup
      WHERE session_id  = @ps_key-session_id
        AND row_index   = @ps_key-row_index
        AND field_name = 'SM35'.
  ELSE.
    DELETE FROM zbdc_result_bup
      WHERE session_id  = @ps_key-session_id
        AND record_key  = @ps_key-record_key
        AND field_name = 'SM35'.
  ENDIF.
ENDFORM.
*<<< END FORM z17_purge_sm35_group_log

*>>> FORM z17_save_sm35_line - moved from Z_BDC_MASS_PO_ENTRY_F01_BUP

FORM z17_save_sm35_line
  USING pt_group TYPE ty_t_staging_alv
        ps_log   TYPE bdclm.

  DATA: ls_first    TYPE ty_staging_alv,
        ls_res      TYPE zbdc_result_bup,
        lv_text     TYPE c LENGTH 255,
        lv_fallback TYPE string,
        lv_hint     TYPE c LENGTH 120,
        lv_retry    TYPE c LENGTH 1,
        lv_status   TYPE c LENGTH 20,
        lv_step_max TYPE zbdc_result_bup-step,
        lv_step     TYPE i,
        lv_ts       TYPE tzntstmps,
        lv_date     TYPE sy-datum,
        lv_time     TYPE sy-uzeit,
        lv_attempt  TYPE i,
        lv_candidate TYPE c LENGTH 10,
        lv_digit_buf TYPE string,
        lv_text_len  TYPE i,
        lv_offset    TYPE i,
        lv_char      TYPE c LENGTH 1,
        lv_object    TYPE zbdc_result_bup-sap_object_id,
        lv_tcode     TYPE sy-tcode,
        lv_ebeln     TYPE ekko-ebeln,
        lv_mblnr     TYPE mkpf-mblnr.

  FIELD-SYMBOLS <fv> TYPE any.

  READ TABLE pt_group INTO ls_first INDEX 1.
  IF sy-subrc <> 0.
    RETURN.
  ENDIF.

  CLEAR: lv_text, lv_fallback.
  IF ps_log-mid IS NOT INITIAL AND ps_log-mnr IS NOT INITIAL.
    CALL FUNCTION 'FORMAT_MESSAGE'
      EXPORTING
        id   = ps_log-mid
        lang = sy-langu
        no   = ps_log-mnr
        v1   = ps_log-mpar
      IMPORTING
        msg  = lv_text
      EXCEPTIONS
        OTHERS = 1.
  ENDIF.

  lv_fallback = |{ ps_log-mid }/{ ps_log-mnr } { ps_log-mpar }|.
  CONDENSE lv_fallback.
  IF lv_text IS INITIAL.
    lv_text = lv_fallback.
  ENDIF.
  IF lv_text IS INITIAL.
    lv_text = |SM35 protocol message { ps_log-mcnt }|.
  ENDIF.

  "Capture business-document evidence per transaction/group. A candidate is
  "accepted only when the target application table confirms it.
  CLEAR: lv_candidate, lv_object, lv_tcode.
  lv_tcode = ps_log-tcode.
  IF lv_tcode IS INITIAL.
    lv_tcode = ls_first-tcode.
  ENDIF.
  "Avoid deprecated POSIX regex: scan the first contiguous 10-digit key.
  CLEAR: lv_candidate, lv_digit_buf.
  lv_text_len = strlen( lv_text ).
  DO lv_text_len TIMES.
    lv_offset = sy-index - 1.
    lv_char = lv_text+lv_offset(1).
    IF lv_char CO '0123456789'.
      CONCATENATE lv_digit_buf lv_char INTO lv_digit_buf.
      IF strlen( lv_digit_buf ) = 10.
        lv_candidate = lv_digit_buf.
        EXIT.
      ENDIF.
    ELSE.
      CLEAR lv_digit_buf.
    ENDIF.
  ENDDO.

  IF lv_candidate IS NOT INITIAL.
    CASE lv_tcode.
      WHEN 'ME21N'.
        CLEAR lv_ebeln.
        SELECT SINGLE ebeln
          FROM ekko
          INTO @lv_ebeln
          WHERE ebeln = @lv_candidate.
        IF sy-subrc = 0.
          lv_object = lv_ebeln.
        ENDIF.
      WHEN 'MIGO'.
        CLEAR lv_mblnr.
        SELECT SINGLE mblnr
          FROM mkpf
          INTO @lv_mblnr
          WHERE mblnr = @lv_candidate.
        IF sy-subrc = 0.
          lv_object = lv_mblnr.
        ENDIF.
    ENDCASE.
  ENDIF.

  CLEAR: lv_hint, lv_retry.
  PERFORM build_bdc_action_hint
    USING    lv_text 'SM35'
    CHANGING lv_hint lv_retry.

  CASE ps_log-mart.
    WHEN 'S'. lv_status = gc_st_success.
    WHEN 'W'. lv_status = gc_st_warning.
    WHEN 'I'. lv_status = 'INFO'.
    WHEN OTHERS. lv_status = gc_st_error.
  ENDCASE.

  CLEAR lv_step_max.
  SELECT MAX( step ) FROM zbdc_result_bup INTO @lv_step_max
    WHERE session_id = @ls_first-session_id
      AND record_key = @ls_first-record_key
      AND row_index  = @ls_first-row_index.
  lv_step = lv_step_max + 1.

  GET TIME STAMP FIELD lv_ts.
  lv_date = ps_log-indate.
  lv_time = ps_log-intime.
  lv_attempt = gv_sm35_retry_count + 1.
  IF lv_date IS INITIAL. lv_date = sy-datum. ENDIF.
  IF lv_time IS INITIAL. lv_time = sy-uzeit. ENDIF.

  DEFINE set_sm35_res.
    ASSIGN COMPONENT &1 OF STRUCTURE ls_res TO <fv>.
    IF sy-subrc = 0.
      <fv> = &2.
    ENDIF.
  END-OF-DEFINITION.

  CLEAR ls_res.
  set_sm35_res 'SESSION_ID'    ls_first-session_id.
  set_sm35_res 'RECORD_KEY'    ls_first-record_key.
  set_sm35_res 'GROUP_KEY'     ls_first-record_key.
  set_sm35_res 'ROW_INDEX'     ls_first-row_index.
  set_sm35_res 'TCODE'         ps_log-tcode.
  set_sm35_res 'MSG_TYPE'      ps_log-mart.
  set_sm35_res 'MSGTYP'        ps_log-mart.
  set_sm35_res 'MSG_ID'        ps_log-mid.
  set_sm35_res 'MSGID'         ps_log-mid.
  set_sm35_res 'MSG_NUMBER'    ps_log-mnr.
  set_sm35_res 'MSGNR'         ps_log-mnr.
  set_sm35_res 'MSG_NO'        ps_log-mnr.
  set_sm35_res 'MSGV1'         ps_log-mpar.
  set_sm35_res 'MESSAGE'       lv_text.
  set_sm35_res 'MESSAGE_TEXT'  lv_text.
  set_sm35_res 'SAP_OBJECT_ID' lv_object.
  set_sm35_res 'PROGRAM_NAME'  'SM35_LOG'.
  set_sm35_res 'DYNAME'        ps_log-module.
  set_sm35_res 'DYNPRO_NO'     ps_log-dynr.
  set_sm35_res 'DYNUMB'        ps_log-dynr.
  set_sm35_res 'DYNPRO'        ps_log-dynr.
  set_sm35_res 'FIELD_NAME'    'SM35'.
  set_sm35_res 'SCREEN_STEP'   lv_step.
  set_sm35_res 'STEP_SEQ'      lv_step.
  set_sm35_res 'MSG_SEQ'       lv_step.
  set_sm35_res 'RESULT_SEQ'    lv_step.
  set_sm35_res 'STEP'          lv_step.
  set_sm35_res 'EXEC_STATUS'   lv_status.
  set_sm35_res 'LOCK_REASON'   lv_hint.
  set_sm35_res 'ATTEMPT_NO'    lv_attempt.
  set_sm35_res 'ATTEMPT'       lv_attempt.
  set_sm35_res 'RETRY_FLAG'    lv_retry.
  set_sm35_res 'CREATED_AT'    lv_ts.
  set_sm35_res 'CREATED_ON'    lv_date.
  set_sm35_res 'CREATED_TM'    lv_time.
  set_sm35_res 'CREATED_TIME'  lv_time.
  set_sm35_res 'CREATED_BY'    sy-uname.

  INSERT zbdc_result_bup FROM ls_res.
  IF sy-subrc <> 0.
    MODIFY zbdc_result_bup FROM ls_res.
  ENDIF.
ENDFORM.
*<<< END FORM z17_save_sm35_line

*>>> FORM z17_sync_sm35_logs - moved from Z_BDC_MASS_PO_ENTRY_F01_BUP

FORM z17_sync_sm35_logs
  USING    pt_process TYPE ty_t_staging_alv
           pv_qid     TYPE apqi-qid
  CHANGING cv_count   TYPE i
           cv_retry   TYPE abap_bool
           cv_reason  TYPE string.

  DATA: lt_log    TYPE ty_t_bdclm,
        ls_log    TYPE bdclm,
        lt_keys   TYPE ty_t_engine_group_key,
        ls_key    TYPE ty_engine_group_key,
        lt_group  TYPE ty_t_staging_alv,
        lv_index  TYPE i,
        lv_total  TYPE i,
        lv_text   TYPE string,
        lv_hit    TYPE abap_bool,
        lv_why    TYPE string.

  CLEAR: cv_count, cv_retry, cv_reason.
  PERFORM z17_get_sm35_log USING pv_qid CHANGING lt_log.
  IF lt_log IS INITIAL.
    RETURN.
  ENDIF.

  PERFORM z17_build_engine_keys USING pt_process CHANGING lt_keys.
  IF lt_keys IS INITIAL.
    RETURN.
  ENDIF.

  LOOP AT lt_keys INTO ls_key.
    PERFORM z17_purge_sm35_group_log USING ls_key.
  ENDLOOP.

  lv_total = lines( lt_keys ).
  LOOP AT lt_log INTO ls_log.
    lv_index = ls_log-tcnt.
    IF lv_index <= 0. lv_index = 1. ENDIF.
    IF lv_index > lv_total. lv_index = lv_total. ENDIF.

    READ TABLE lt_keys INTO ls_key INDEX lv_index.
    IF sy-subrc <> 0.
      READ TABLE lt_keys INTO ls_key INDEX 1.
    ENDIF.

    PERFORM z17_collect_group_key
      USING    pt_process ls_key
      CHANGING lt_group.
    IF lt_group IS INITIAL.
      CONTINUE.
    ENDIF.

    PERFORM z17_save_sm35_line USING lt_group ls_log.
    cv_count = cv_count + 1.

    lv_text = |{ ls_log-mid } { ls_log-mnr } { ls_log-mpar }|.
    CLEAR: lv_hit, lv_why.
    PERFORM z17_text_transient
      USING    lv_text
      CHANGING lv_hit lv_why.
    IF lv_hit = abap_true.
      cv_retry  = abap_true.
      cv_reason = lv_why.
    ENDIF.
  ENDLOOP.
ENDFORM.

*&---------------------------------------------------------------------*
*& V5AY - Start one RSBDCCTU job for a real SM35 queue
*& The BI session is created with BDC_OPEN/INSERT/CLOSE and processed by QID.
*& NOBINPT/RACOMMIT improve compatibility but do not fake support: the real
*& SM35 protocol is inspected afterwards. GUI-Control failures are eligible
*& for a narrowly-scoped automatic mode-E fallback; business errors are not.
*&---------------------------------------------------------------------*
*<<< END FORM z17_sync_sm35_logs

*>>> FORM z25_start_ctu_job - moved from Z_BDC_MASS_PO_ENTRY_F01_BUP
FORM z25_start_ctu_job
  USING    pv_group  TYPE apqi-groupid
           pv_qid    TYPE apqi-qid
           pv_mode   TYPE c
           pv_upd    TYPE c
           pv_prefix TYPE string
  CHANGING cv_ok       TYPE abap_bool
           cv_msg      TYPE string
           cv_jobname  TYPE tbtco-jobname
           cv_jobcount TYPE tbtco-jobcount.

  DATA: lt_sel       TYPE STANDARD TABLE OF rsparams,
        ls_sel       TYPE rsparams,
        lv_report    TYPE sy-repid VALUE 'RSBDCCTU',
        lv_prog      TYPE trdir-name,
        lv_jobname   TYPE tbtco-jobname,
        lv_jobcount  TYPE tbtco-jobcount,
        lv_released  TYPE c LENGTH 1,
        lv_mode      TYPE c LENGTH 1,
        lv_upd       TYPE c LENGTH 1.

  CLEAR: cv_ok, cv_msg, cv_jobname, cv_jobcount,
         lv_jobname, lv_jobcount, lv_released.

  IF pv_qid IS INITIAL.
    cv_msg = |SM35 session { pv_group } has no queue ID; RSBDCCTU processing was not started.|.
    RETURN.
  ENDIF.

  lv_mode = pv_mode.
  IF lv_mode <> 'N' AND lv_mode <> 'A' AND lv_mode <> 'E'.
    lv_mode = 'N'.
  ENDIF.

  lv_upd = pv_upd.
  IF lv_upd <> 'A' AND lv_upd <> 'S'.
    lv_upd = 'S'.
  ENDIF.

  SELECT SINGLE name
    FROM trdir
    INTO @lv_prog
    WHERE name = @lv_report.
  IF sy-subrc <> 0.
    cv_msg = |Standard report RSBDCCTU is not available. Session { pv_group } remains safely queued in SM35.|.
    RETURN.
  ENDIF.

  DEFINE add_ctu_job_par.
    CLEAR ls_sel.
    ls_sel-selname = &1.
    ls_sel-kind    = 'P'.
    ls_sel-sign    = 'I'.
    ls_sel-option  = 'EQ'.
    ls_sel-low     = &2.
    APPEND ls_sel TO lt_sel.
  END-OF-DEFINITION.

  add_ctu_job_par 'GROUPID'  pv_group.
  add_ctu_job_par 'QID'      pv_qid.
  add_ctu_job_par 'MODE'     lv_mode.
  add_ctu_job_par 'UPDATE'   lv_upd.
  add_ctu_job_par 'DEFSIZE'  'X'.
  add_ctu_job_par 'RACOMMIT' 'X'.
  add_ctu_job_par 'NOBINPT'  'X'.
  add_ctu_job_par 'NOBIEND'  'X'.

  CONCATENATE pv_prefix sy-datum sy-uzeit INTO lv_jobname.

  CALL FUNCTION 'JOB_OPEN'
    EXPORTING
      jobname          = lv_jobname
    IMPORTING
      jobcount         = lv_jobcount
    EXCEPTIONS
      cant_create_job  = 1
      invalid_job_data = 2
      jobname_missing  = 3
      OTHERS           = 4.
  IF sy-subrc <> 0.
    cv_msg = |Could not create RSBDCCTU job for session { pv_group }; sy-subrc={ sy-subrc }. Session remains queued.|.
    RETURN.
  ENDIF.

  SUBMIT (lv_report)
    USER sy-uname
    VIA JOB lv_jobname NUMBER lv_jobcount
    WITH SELECTION-TABLE lt_sel
    AND RETURN.

  IF sy-subrc <> 0.
    cv_msg = |Could not add RSBDCCTU to job { lv_jobname }; sy-subrc={ sy-subrc }. Session remains queued.|.
    RETURN.
  ENDIF.

  CALL FUNCTION 'JOB_CLOSE'
    EXPORTING
      jobcount             = lv_jobcount
      jobname              = lv_jobname
      strtimmed             = 'X'
    IMPORTING
      job_was_released      = lv_released
    EXCEPTIONS
      cant_start_immediate  = 1
      invalid_startdate     = 2
      jobname_missing       = 3
      job_close_failed      = 4
      job_nosteps           = 5
      job_notex             = 6
      lock_failed           = 7
      invalid_target        = 8
      OTHERS                = 9.

  IF sy-subrc <> 0 OR lv_released <> 'X'.
    cv_msg = |RSBDCCTU job { lv_jobname } was not released; sy-subrc={ sy-subrc }. Session remains queued in SM35.|.
    RETURN.
  ENDIF.

  COMMIT WORK AND WAIT.

  cv_jobname  = lv_jobname.
  cv_jobcount = lv_jobcount.
  cv_ok = abap_true.
  cv_msg = |SM35 session { pv_group } started via RSBDCCTU ({ lv_mode }/{ lv_upd }). Real APQI/log/object verification is active; GUI-Control fallback is evidence-based.|.
ENDFORM.
*<<< END FORM z25_start_ctu_job

*>>> FORM z16_run_sm35_n_sync - moved from Z_BDC_MASS_PO_ENTRY_F01_BUP

FORM z16_run_sm35_n_sync
  USING    pv_group TYPE apqi-groupid
           pv_qid   TYPE apqi-qid
           pv_upd   TYPE c
  CHANGING cv_ok    TYPE abap_bool
           cv_msg   TYPE string.

  DATA: lv_jobname      TYPE tbtco-jobname,
        lv_jobcount     TYPE tbtco-jobcount,
        lv_status       TYPE tbtco-status,
        lv_timeout      TYPE i,
        lv_waited_ticks TYPE i,
        lv_max_ticks    TYPE i,
        lv_waited_sec   TYPE p LENGTH 8 DECIMALS 1,
        lv_sleep_sec    TYPE p LENGTH 2 DECIMALS 1 VALUE '0.1',
        lv_rt_now       TYPE i,
        lv_elapsed_ms   TYPE i,
        lv_started      TYPE abap_bool,
        lv_start_msg    TYPE string.

  CLEAR: cv_ok, cv_msg, lv_jobname, lv_jobcount, lv_status,
         lv_waited_ticks, lv_waited_sec, lv_started, lv_start_msg.

  IF pv_qid IS INITIAL.
    cv_msg = |Session { pv_group } was created, but its queue ID was not resolved. Use SM35 Monitor.|.
    RETURN.
  ENDIF.

  lv_timeout = txtp_timeout.
  IF lv_timeout <= 0.
    lv_timeout = 60.
  ELSEIF lv_timeout > 300.
    lv_timeout = 300.
  ENDIF.

  PERFORM z25_start_ctu_job
    USING    pv_group pv_qid 'N' pv_upd 'ZBDC_NS_'
    CHANGING lv_started lv_start_msg lv_jobname lv_jobcount.

  IF lv_started <> abap_true.
    cv_msg = lv_start_msg.
    RETURN.
  ENDIF.

  gv_last_sm35_jobname  = lv_jobname.
  gv_last_sm35_jobcount = lv_jobcount.

  lv_max_ticks = lv_timeout * 10.
  DO lv_max_ticks TIMES.
    CLEAR lv_status.
    SELECT SINGLE status
      FROM tbtco
      INTO @lv_status
      WHERE jobname  = @lv_jobname
        AND jobcount = @lv_jobcount.

    IF lv_status = 'F'.
      cv_ok = abap_true.
      cv_msg = |RSBDCCTU job { lv_jobname } finished. Verifying APQI, SM35 protocol and business-document evidence.|.
      RETURN.
    ELSEIF lv_status = 'A'.
      cv_msg = |RSBDCCTU job { lv_jobname } was canceled. Session { pv_group } remains available in SM35.|.
      RETURN.
    ENDIF.

    lv_waited_ticks = lv_waited_ticks + 1.
    lv_waited_sec = lv_waited_ticks.
    lv_waited_sec = lv_waited_sec / 10.
    gv_exec_run_phase = |RSBDCCTU processing { pv_group } ({ lv_waited_sec } sec)|.

    GET RUN TIME FIELD lv_rt_now.
    lv_elapsed_ms = lv_rt_now - gv_exec_run_start_rt.
    IF lv_elapsed_ms < 0.
      lv_elapsed_ms = 0.
    ENDIF.
    lv_elapsed_ms = lv_elapsed_ms / 1000.

    PERFORM z16_set_0500_progress
      USING gv_exec_run_done gv_exec_run_total lv_elapsed_ms.
    PERFORM z16_sapgui_progress
      USING gv_exec_run_done gv_exec_run_total gv_exec_run_phase.

    WAIT UP TO lv_sleep_sec SECONDS.
  ENDDO.

  cv_ok = abap_true.
  cv_msg = |RSBDCCTU job { lv_jobname } is still running after { lv_waited_sec } second(s). Live verification continues in SM35/SM37.|.
ENDFORM.
*<<< END FORM z16_run_sm35_n_sync

*>>> FORM z16_run_sm35_sync - moved from Z_BDC_MASS_PO_ENTRY_F01_BUP

FORM z16_run_sm35_sync
  USING    pv_group  TYPE apqi-groupid
           pv_qid    TYPE apqi-qid
           pv_mode   TYPE c
           pv_policy TYPE c
  CHANGING cv_ok     TYPE abap_bool
           cv_msg    TYPE string.

  DATA: lt_sel    TYPE STANDARD TABLE OF rsparams,
        ls_sel    TYPE rsparams,
        lv_report TYPE sy-repid VALUE 'RSBDCCTU',
        lv_prog   TYPE trdir-name,
        lv_mode   TYPE c LENGTH 1,
        lv_upd    TYPE c LENGTH 1.

  CLEAR: cv_ok, cv_msg.

  IF pv_qid IS INITIAL.
    cv_msg = |Session { pv_group } was created, but its queue ID was not resolved. Use SM35 Monitor.|.
    RETURN.
  ENDIF.

  lv_mode = pv_mode.
  IF lv_mode <> 'N' AND lv_mode <> 'A' AND lv_mode <> 'E'.
    lv_mode = 'N'.
  ENDIF.

  lv_upd = pv_policy.
  IF lv_upd <> 'A' AND lv_upd <> 'S'.
    lv_upd = 'S'.
  ENDIF.

  IF lv_mode = 'N'.
    PERFORM z16_run_sm35_n_sync
      USING    pv_group pv_qid lv_upd
      CHANGING cv_ok cv_msg.
    gv_0500_active = abap_true.
    RETURN.
  ENDIF.

  SELECT SINGLE name
    FROM trdir
    INTO @lv_prog
    WHERE name = @lv_report.
  IF sy-subrc <> 0.
    cv_msg = |Standard report RSBDCCTU is not available. Session { pv_group } remains queued in SM35.|.
    RETURN.
  ENDIF.

  "Foreground A/E must own the GUI. Release SCREEN0 first so the fixed
  "fullscreen queue cannot cover the standard transaction screens.
  PERFORM z16_free_0500_queue.
  TRY.
      CALL METHOD cl_gui_cfw=>flush.
    CATCH cx_root.
  ENDTRY.

  DEFINE add_ctu_fg_par.
    CLEAR ls_sel.
    ls_sel-selname = &1.
    ls_sel-kind    = 'P'.
    ls_sel-sign    = 'I'.
    ls_sel-option  = 'EQ'.
    ls_sel-low     = &2.
    APPEND ls_sel TO lt_sel.
  END-OF-DEFINITION.

  add_ctu_fg_par 'GROUPID'  pv_group.
  add_ctu_fg_par 'QID'      pv_qid.
  add_ctu_fg_par 'MODE'     lv_mode.
  add_ctu_fg_par 'UPDATE'   lv_upd.
  add_ctu_fg_par 'DEFSIZE'  'X'.
  add_ctu_fg_par 'RACOMMIT' 'X'.
  add_ctu_fg_par 'NOBINPT'  'X'.
  add_ctu_fg_par 'NOBIEND'  'X'.

  SUBMIT (lv_report)
    WITH SELECTION-TABLE lt_sel
    AND RETURN.

  IF sy-subrc = 0.
    cv_ok = abap_true.
    CASE lv_mode.
      WHEN 'A'.
        cv_msg = |SM35 session { pv_group } returned from RSBDCCTU All-screens processing ({ lv_upd } update).|.
      WHEN 'E'.
        cv_msg = |SM35 session { pv_group } returned from RSBDCCTU Errors-only processing ({ lv_upd } update).|.
      WHEN OTHERS.
        cv_msg = |SM35 session { pv_group } returned from RSBDCCTU processing.|.
    ENDCASE.
  ELSE.
    cv_msg = |RSBDCCTU could not process session { pv_group }; sy-subrc={ sy-subrc }. Session remains available in SM35.|.
  ENDIF.

  gv_0500_active = abap_true.
ENDFORM.
*<<< END FORM z16_run_sm35_sync

*>>> FORM z16_submit_sm35_bg - moved from Z_BDC_MASS_PO_ENTRY_F01_BUP

FORM z16_submit_sm35_bg
  USING    pv_group TYPE apqi-groupid
           pv_qid   TYPE apqi-qid
  CHANGING cv_ok    TYPE abap_bool
           cv_msg   TYPE string.

  DATA: lv_jobname  TYPE tbtco-jobname,
        lv_jobcount TYPE tbtco-jobcount,
        lv_upd      TYPE c LENGTH 1.

  lv_upd = gv_last_sm35_policy.
  IF lv_upd <> 'A' AND lv_upd <> 'S'.
    lv_upd = 'S'.
  ENDIF.

  PERFORM z25_start_ctu_job
    USING    pv_group pv_qid 'N' lv_upd 'ZBDC_BG_'
    CHANGING cv_ok cv_msg lv_jobname lv_jobcount.

  IF cv_ok = abap_true.
    gv_last_sm35_jobname  = lv_jobname.
    gv_last_sm35_jobcount = lv_jobcount.
  ENDIF.
ENDFORM.

*&---------------------------------------------------------------------*
*& V5AY - Process a real SM35 queue through RSBDCCTU
*& The original queue remains a genuine Batch Input Session. Processing is
*& driven by QID and verified by APQI, SM35 protocol and SAP-object proof.
*& No success is inferred merely because the RSBDCCTU job finished.
*&---------------------------------------------------------------------*
*<<< END FORM z16_submit_sm35_bg

*>>> FORM z24_submit_sm35_compat - moved from Z_BDC_MASS_PO_ENTRY_F01_BUP
FORM z24_submit_sm35_compat
  USING    pv_group TYPE apqi-groupid
           pv_qid   TYPE apqi-qid
           pv_mode  TYPE c
           pv_upd   TYPE c
  CHANGING cv_ok    TYPE abap_bool
           cv_msg   TYPE string.

  DATA: lv_jobname  TYPE tbtco-jobname,
        lv_jobcount TYPE tbtco-jobcount.

  CLEAR: cv_ok, cv_msg, gv_last_sm35_jobname,
         gv_last_sm35_jobcount.

  PERFORM z25_start_ctu_job
    USING    pv_group pv_qid pv_mode pv_upd 'ZBDC_CTU_'
    CHANGING cv_ok cv_msg lv_jobname lv_jobcount.

  IF cv_ok = abap_true.
    gv_last_sm35_jobname  = lv_jobname.
    gv_last_sm35_jobcount = lv_jobcount.
    cv_msg = |{ cv_msg } Live APQI/log/object verification is active in screen 0500.|.
  ENDIF.
ENDFORM.
*<<< END FORM z24_submit_sm35_compat

*>>> FORM z16_apply_sm35_profile - moved from Z_BDC_MASS_PO_ENTRY_F01_BUP

FORM z16_apply_sm35_profile
  USING    pv_group  TYPE apqi-groupid
           pv_qid    TYPE apqi-qid
           pv_mode   TYPE c
           pv_policy TYPE c
  CHANGING cv_ok     TYPE abap_bool
           cv_msg    TYPE string.

  DATA lv_profile TYPE string.

  CLEAR: cv_ok, cv_msg.
  PERFORM z16_sm35_profile_label
    USING    pv_mode pv_policy
    CHANGING lv_profile.

  gv_last_sm35_mode    = pv_mode.
  gv_last_sm35_policy  = pv_policy.
  gv_last_sm35_profile = lv_profile.

  CASE pv_mode.
    WHEN 'N'.
      "No-display is detached as an immediate RSBDCCTU job. The queue,
      "APQI state, protocol and SAP-object proof remain independently checked.
      PERFORM z24_submit_sm35_compat
        USING    pv_group pv_qid pv_mode pv_policy
        CHANGING cv_ok cv_msg.

    WHEN 'A' OR 'E'.
      "All-screens and Errors-only are interactive by nature. Execute the
      "same real queue through RSBDCCTU in the user's dialog session.
      PERFORM z16_run_sm35_sync
        USING    pv_group pv_qid pv_mode pv_policy
        CHANGING cv_ok cv_msg.

    WHEN OTHERS.
      cv_msg = |Unsupported SM35 display mode { pv_mode }. Use N, E or A.|.
  ENDCASE.

  gv_last_sm35_action = cv_msg.
ENDFORM.
*<<< END FORM z16_apply_sm35_profile

*>>> FORM z16_set_sm35_group - moved from Z_BDC_MASS_PO_ENTRY_F01_BUP

FORM z16_set_sm35_group
  USING pt_group   TYPE ty_t_staging_alv
        pv_status  TYPE any
        pv_msg     TYPE string
        pv_object  TYPE zbdc_result_bup-sap_object_id.

  DATA ls_first TYPE ty_staging_alv.
  DATA ls_curr  TYPE ty_staging_alv.

  READ TABLE pt_group INTO ls_first INDEX 1.
  IF sy-subrc <> 0.
    RETURN.
  ENDIF.

  READ TABLE gt_staging_alv INTO ls_curr
    WITH KEY session_id = ls_first-session_id
             row_index  = ls_first-row_index.
  IF sy-subrc = 0 AND
     ls_curr-status = pv_status AND
     ls_curr-error_msg = pv_msg AND
     pv_object IS INITIAL.
    RETURN.
  ENDIF.

  PERFORM update_group_result
    USING pt_group pv_status pv_msg pv_object.
ENDFORM.
*<<< END FORM z16_set_sm35_group

*>>> FORM z18_wait_sm35_terminal - moved from Z_BDC_MASS_PO_ENTRY_F01_BUP


FORM z18_wait_sm35_terminal
  USING    pv_qid      TYPE apqi-qid
           pv_seconds  TYPE i.

  DATA: lv_qstate      TYPE apqi-qstate,
        lv_text        TYPE c LENGTH 120,
        lv_ticks       TYPE i,
        lv_max_ticks   TYPE i,
        lv_sleep       TYPE p LENGTH 2 DECIMALS 1 VALUE '0.1',
        lv_rt_now      TYPE i,
        lv_elapsed_ms  TYPE i,
        lv_waited_sec  TYPE p LENGTH 8 DECIMALS 1.

  IF pv_qid IS INITIAL OR pv_seconds <= 0. RETURN. ENDIF.

  lv_max_ticks = pv_seconds * 10.
  DO lv_max_ticks TIMES.
    lv_ticks = sy-index.
    CLEAR lv_qstate.
    SELECT SINGLE qstate FROM apqi INTO @lv_qstate
      WHERE mandant = @sy-mandt AND qid = @pv_qid.
    IF lv_qstate = 'E' OR lv_qstate = 'F'. EXIT. ENDIF.

    lv_waited_sec = lv_ticks.
    lv_waited_sec = lv_waited_sec / 10.
    lv_text = |Verifying SM35 terminal state { lv_waited_sec } sec|.
    gv_exec_run_phase = lv_text.

    GET RUN TIME FIELD lv_rt_now.
    lv_elapsed_ms = lv_rt_now - gv_exec_run_start_rt.
    IF lv_elapsed_ms < 0. lv_elapsed_ms = 0. ENDIF.
    lv_elapsed_ms = lv_elapsed_ms / 1000.

    PERFORM z16_set_0500_progress
      USING gv_exec_run_done gv_exec_run_total lv_elapsed_ms.
    WAIT UP TO lv_sleep SECONDS.
  ENDDO.
ENDFORM.
*<<< END FORM z18_wait_sm35_terminal

*>>> FORM z20_group_sm35_proof - moved from Z_BDC_MASS_PO_ENTRY_F01_BUP
FORM z20_group_sm35_proof
  USING    pt_group   TYPE ty_t_staging_alv
  CHANGING cv_success TYPE abap_bool
           cv_error   TYPE abap_bool
           cv_object  TYPE zbdc_result_bup-sap_object_id
           cv_summary TYPE string.

  DATA: ls_first TYPE ty_staging_alv,
        lt_res   TYPE STANDARD TABLE OF zbdc_result_bup,
        ls_res   TYPE zbdc_result_bup.

  CLEAR: cv_success, cv_error, cv_object, cv_summary.
  READ TABLE pt_group INTO ls_first INDEX 1.
  IF sy-subrc <> 0.
    RETURN.
  ENDIF.

  IF ls_first-record_key IS INITIAL.
    SELECT *
      FROM zbdc_result_bup
      INTO TABLE @lt_res
      WHERE session_id = @ls_first-session_id
        AND row_index  = @ls_first-row_index.
  ELSE.
    SELECT *
      FROM zbdc_result_bup
      INTO TABLE @lt_res
      WHERE session_id = @ls_first-session_id
        AND record_key = @ls_first-record_key.
  ENDIF.

  LOOP AT lt_res INTO ls_res.
    IF cv_summary IS INITIAL AND ls_res-message IS NOT INITIAL.
      cv_summary = ls_res-message.
    ENDIF.
    IF ls_res-sap_object_id IS NOT INITIAL.
      cv_object = ls_res-sap_object_id.
      cv_success = abap_true.
    ENDIF.
    IF ls_res-msg_type = 'E' OR ls_res-msg_type = 'A' OR
       ls_res-exec_status = gc_st_error.
      cv_error = abap_true.
    ELSEIF ls_res-msg_type = 'S' OR
           ls_res-exec_status = gc_st_success.
      cv_success = abap_true.
    ENDIF.
  ENDLOOP.
ENDFORM.

*&---------------------------------------------------------------------*
*& V5AY - Protect verified business success from stale SM35 audit errors
*& An Incorrect SM35 session remains visible for audit after the automatic
*& mode-E fallback. Later Refresh/SM35 Monitor actions must not overwrite a
*& SAP document that was subsequently created and verified successfully.
*&---------------------------------------------------------------------*
*<<< END FORM z20_group_sm35_proof

*>>> FORM z28_group_verified_success - moved from Z_BDC_MASS_PO_ENTRY_F01_BUP
FORM z28_group_verified_success
  USING    pt_group  TYPE ty_t_staging_alv
  CHANGING cv_ok     TYPE abap_bool
           cv_object TYPE zbdc_result_bup-sap_object_id.

  DATA: ls_first    TYPE ty_staging_alv,
        lt_result   TYPE STANDARD TABLE OF zbdc_result_bup,
        ls_result   TYPE zbdc_result_bup,
        lv_verified TYPE abap_bool,
        lv_tcode    TYPE sy-tcode.

  CLEAR: cv_ok, cv_object.
  READ TABLE pt_group INTO ls_first INDEX 1.
  IF sy-subrc <> 0.
    RETURN.
  ENDIF.

  lv_tcode = ls_first-tcode.
  IF lv_tcode IS INITIAL.
    lv_tcode = p_transaction.
  ENDIF.

  IF ls_first-record_key IS INITIAL.
    SELECT *
      FROM zbdc_result_bup
      INTO TABLE @lt_result
      WHERE session_id = @ls_first-session_id
        AND row_index  = @ls_first-row_index
        AND sap_object_id <> ''.
  ELSE.
    SELECT *
      FROM zbdc_result_bup
      INTO TABLE @lt_result
      WHERE session_id = @ls_first-session_id
        AND record_key = @ls_first-record_key
        AND sap_object_id <> ''.
  ENDIF.

  LOOP AT lt_result INTO ls_result.
    CLEAR lv_verified.
    PERFORM z22_verify_current_obj
      USING    lv_tcode ls_result-sap_object_id
      CHANGING lv_verified.
    IF lv_verified = abap_true.
      cv_ok     = abap_true.
      cv_object = ls_result-sap_object_id.
      RETURN.
    ENDIF.
  ENDLOOP.
ENDFORM.
*<<< END FORM z28_group_verified_success

*>>> FORM z20_apply_sm35_group - moved from Z_BDC_MASS_PO_ENTRY_F01_BUP

FORM z20_apply_sm35_group
  USING    pt_group      TYPE ty_t_staging_alv
           pv_qstate     TYPE c
           pv_session    TYPE apqi-groupid
           pv_msg        TYPE string
           pv_first_err  TYPE string
           pv_error_dynn TYPE string
  CHANGING cv_success    TYPE i
           cv_error      TYPE i
           cv_warning    TYPE i
           cv_queued     TYPE i.

  DATA: ls_first       TYPE ty_staging_alv,
        ls_current     TYPE ty_staging_alv,
        lv_has_success TYPE abap_bool,
        lv_has_error   TYPE abap_bool,
        lv_object      TYPE zbdc_result_bup-sap_object_id,
        lv_summary     TYPE string,
        lv_status      TYPE c LENGTH 20,
        lv_final       TYPE string,
        lv_current_ok  TYPE abap_bool,
        lv_current_obj TYPE zbdc_result_bup-sap_object_id.

  READ TABLE pt_group INTO ls_first INDEX 1.
  IF sy-subrc <> 0.
    RETURN.
  ENDIF.

  CLEAR: lv_has_success, lv_has_error, lv_object, lv_summary.
  PERFORM z20_group_sm35_proof
    USING    pt_group
    CHANGING lv_has_success lv_has_error lv_object lv_summary.

  CLEAR ls_current.
  READ TABLE gt_staging_alv INTO ls_current
    WITH KEY session_id = ls_first-session_id
             row_index  = ls_first-row_index.
  IF sy-subrc <> 0.
    ls_current = ls_first.
  ENDIF.

  CLEAR: lv_current_ok, lv_current_obj.
  "Always check existing business-object evidence. This also promotes a
  "previous proof-pending WARNING after asynchronous update A becomes visible.
  PERFORM z28_group_verified_success
    USING    pt_group
    CHANGING lv_current_ok lv_current_obj.

  IF lv_current_ok = abap_true.
    lv_status = gc_st_success.
    lv_object = lv_current_obj.
    lv_final = |Verified SAP object { lv_current_obj } is retained; the earlier SM35 error remains audit history only.|.
    cv_success = cv_success + 1.

  ELSEIF lv_has_error = abap_true.
    lv_status = gc_st_error.
    IF lv_summary IS INITIAL.
      lv_final = |SM35 session { pv_session } returned an error for group { ls_first-record_key }.|.
    ELSE.
      lv_final = |SM35 { pv_session } error for group { ls_first-record_key }: { lv_summary }|.
    ENDIF.
    cv_error = cv_error + 1.

  ELSEIF lv_has_success = abap_true.
    lv_status = gc_st_success.
    IF lv_object IS NOT INITIAL.
      lv_final = |SM35 verified success: SAP object { lv_object } created for group { ls_first-record_key }.|.
    ELSEIF lv_summary IS NOT INITIAL.
      lv_final = |SM35 verified success for group { ls_first-record_key }: { lv_summary }|.
    ELSE.
      lv_final = |SM35 verified success for group { ls_first-record_key }.|.
    ENDIF.
    cv_success = cv_success + 1.

  ELSEIF ls_current-status = gc_st_error.
    "Do not overwrite a real preflight/BDC_INSERT error with session status.
    lv_status = gc_st_error.
    lv_final = ls_current-error_msg.
    IF lv_final IS INITIAL.
      lv_final = |Group { ls_first-record_key } was rejected before SM35 processing.|.
    ENDIF.
    cv_error = cv_error + 1.

  ELSE.
    CASE pv_qstate.
      WHEN 'F'.
        lv_status = gc_st_warning.
        lv_final = |SM35 session { pv_session } is processed, but group { ls_first-record_key } has no positive business-document proof. Review SM35 Log.|.
        cv_warning = cv_warning + 1.
      WHEN 'E'.
        "APQI state E/A is a real failed/aborted Batch Input session. Never downgrade
        "it to WARNING merely because the TemSe protocol could not be mapped.
        lv_status = gc_st_error.
        IF pv_first_err IS NOT INITIAL AND pv_error_dynn IS NOT INITIAL.
          lv_final = |SM35 { pv_session } failed at { pv_error_dynn } for group { ls_first-record_key }: { pv_first_err }|.
        ELSEIF pv_first_err IS NOT INITIAL.
          lv_final = |SM35 { pv_session } failed for group { ls_first-record_key }: { pv_first_err }|.
        ELSE.
          lv_final = |SM35 session { pv_session } ended in Incorrect status for group { ls_first-record_key }. Open SM35 Log/Analysis for the exact SAP message.|.
        ENDIF.
        cv_error = cv_error + 1.
      WHEN 'R' OR 'S' OR 'C'.
        lv_status = gc_st_sm35q.
        lv_final = |SM35 session { pv_session } is still processing; group { ls_first-record_key } is pending verification.|.
        cv_queued = cv_queued + 1.
      WHEN OTHERS.
        lv_status = gc_st_sm35q.
        IF pv_msg IS INITIAL.
          lv_final = |SM35 session { pv_session } is queued; no SAP document exists yet for group { ls_first-record_key }.|.
        ELSE.
          lv_final = |{ pv_msg } Group { ls_first-record_key } is pending in SM35.|.
        ENDIF.
        cv_queued = cv_queued + 1.
    ENDCASE.
  ENDIF.

  PERFORM z16_set_sm35_group
    USING pt_group lv_status lv_final lv_object.
ENDFORM.
*<<< END FORM z20_apply_sm35_group

*>>> FORM z16_reconcile_sm35 - moved from Z_BDC_MASS_PO_ENTRY_F01_BUP

FORM z16_reconcile_sm35
  USING pt_process TYPE ty_t_staging_alv
        pv_group   TYPE apqi-groupid
        pv_qid     TYPE apqi-qid
        pv_msg     TYPE string.

  DATA: lv_qstate      TYPE c LENGTH 1,
        lv_qid_local   TYPE apqi-qid,
        lv_status      TYPE c LENGTH 20,
        lv_final       TYPE string,
        lv_log_count   TYPE i,
        lv_log_retry   TYPE abap_bool,
        lv_log_reason  TYPE string,
        lv_run_ok      TYPE abap_bool,
        lv_run_msg     TYPE string,
        lv_retry_attempt TYPE i,
        lv_tcode       TYPE sy-tcode,
        lt_sorted      TYPE ty_t_staging_alv,
        lt_group       TYPE ty_t_staging_alv,
        ls_row         TYPE ty_staging_alv,
        ls_fb_first    TYPE ty_staging_alv,
        ls_first       TYPE ty_staging_alv,
        lv_prev_sid     TYPE zbdc_staging_bup-session_id,
        lv_prev_key     TYPE zbdc_staging_bup-record_key,
        lv_curr_key     TYPE zbdc_staging_bup-record_key,
        lv_first_error  TYPE string,
        lv_error_dynpro TYPE string,
        lv_grp_success   TYPE i,
        lv_grp_error     TYPE i,
        lv_grp_warning   TYPE i,
        lv_grp_queued    TYPE i.

  IF gv_sm35_retry_group <> pv_group.
    gv_sm35_retry_group = pv_group.
    CLEAR gv_sm35_retry_count.
  ENDIF.

  lv_qid_local = pv_qid.
  IF lv_qid_local IS INITIAL AND pv_group IS NOT INITIAL.
    PERFORM z16_find_sm35_qid
      USING    pv_group
      CHANGING lv_qid_local.
  ENDIF.

  CLEAR lv_qstate.
  IF lv_qid_local IS NOT INITIAL.
    SELECT SINGLE qstate
      FROM apqi
      INTO @lv_qstate
      WHERE mandant = @sy-mandt
        AND qid     = @lv_qid_local.
  ENDIF.

  " Pull the standard SM35 TemSe protocol into ZBDC_RESULT_BUP. The same
  " detailed log then drives Dashboard, drill-down, export and retryability.
  PERFORM z17_sync_sm35_logs
    USING    pt_process lv_qid_local
    CHANGING lv_log_count lv_log_retry lv_log_reason.
  PERFORM z18_first_sm35_error
    USING lv_qid_local CHANGING lv_first_error lv_error_dynpro.

  "Some releases keep APQI=E while the protocol cannot yet be read through
  "BDC_PROTOCOL_SELECT_QID. Persist a truthful technical error instead of
  "showing the business group as an unverified warning.
  IF lv_qstate = 'E' AND lv_log_count = 0.
    READ TABLE pt_process INTO ls_first INDEX 1.
    IF sy-subrc = 0.
      lv_tcode = ls_first-tcode.
    ENDIF.
    IF lv_first_error IS INITIAL.
      lv_first_error = |SM35 session { pv_group } is Incorrect. Open SM35 Log/Analysis for the exact SAP message.|.
    ENDIF.
    PERFORM save_synthetic_engine_log
      USING pt_process lv_tcode 1 gc_st_error
            lv_first_error '' ''.
  ENDIF.

  " Safe automatic SM35 retry: only no-display mode, only transient logs,
  " only when RETRY_ENABLED is on. Repeat is bounded by GC_MAX_ATTEMPTS.
  DO.
    IF lv_qstate <> 'E' OR
       chkp_retry <> 'X' OR
       gv_last_sm35_mode <> 'N' OR
       gv_last_sm35_jobcount IS NOT INITIAL OR
       lv_log_retry <> abap_true OR
       gv_sm35_retry_count >= ( gc_max_attempts - 1 ).
      EXIT.
    ENDIF.

    gv_sm35_retry_count = gv_sm35_retry_count + 1.
    lv_retry_attempt = gv_sm35_retry_count + 1.
    READ TABLE pt_process INTO ls_first INDEX 1.
    IF sy-subrc = 0.
      lv_tcode = ls_first-tcode.
    ENDIF.

    lv_run_msg = |SM35 auto retry { lv_retry_attempt }/{ gc_max_attempts } for transient issue { lv_log_reason }.|.
    PERFORM save_synthetic_engine_log
      USING pt_process lv_tcode lv_retry_attempt gc_st_warning
            lv_run_msg '' 'X'.

    CLEAR: lv_run_ok, lv_run_msg.
    PERFORM z16_run_sm35_n_sync
      USING    pv_group lv_qid_local gv_last_sm35_policy
      CHANGING lv_run_ok lv_run_msg.

    CLEAR lv_qstate.
    SELECT SINGLE qstate
      FROM apqi
      INTO @lv_qstate
      WHERE mandant = @sy-mandt
        AND qid     = @lv_qid_local.

    PERFORM z17_sync_sm35_logs
      USING    pt_process lv_qid_local
      CHANGING lv_log_count lv_log_retry lv_log_reason.
    PERFORM z18_first_sm35_error
      USING lv_qid_local CHANGING lv_first_error lv_error_dynpro.

    IF lv_run_ok <> abap_true AND lv_qstate <> 'E'.
      EXIT.
    ENDIF.
  ENDDO.

  "Reconcile every business group independently. A session-level green icon
  "must never stamp all selected groups with the same object or fake success.
  lt_sorted = pt_process.
  SORT lt_sorted BY session_id record_key row_index.
  CLEAR: lt_group, lv_prev_sid, lv_prev_key,
         lv_grp_success, lv_grp_error, lv_grp_warning, lv_grp_queued.

  LOOP AT lt_sorted INTO ls_row.
    lv_curr_key = ls_row-record_key.
    IF lv_curr_key IS INITIAL.
      lv_curr_key = ls_row-row_index.
    ENDIF.

    IF lt_group IS NOT INITIAL AND
       ( ls_row-session_id <> lv_prev_sid OR lv_curr_key <> lv_prev_key ).
      PERFORM z20_apply_sm35_group
        USING    lt_group lv_qstate pv_group pv_msg
                 lv_first_error lv_error_dynpro
        CHANGING lv_grp_success lv_grp_error
                 lv_grp_warning lv_grp_queued.
      CLEAR lt_group.
    ENDIF.

    APPEND ls_row TO lt_group.
    lv_prev_sid = ls_row-session_id.
    lv_prev_key = lv_curr_key.
  ENDLOOP.

  IF lt_group IS NOT INITIAL.
    PERFORM z20_apply_sm35_group
      USING    lt_group lv_qstate pv_group pv_msg
               lv_first_error lv_error_dynpro
      CHANGING lv_grp_success lv_grp_error
               lv_grp_warning lv_grp_queued.
  ENDIF.

  IF lv_grp_error > 0.
    IF lv_first_error IS NOT INITIAL.
      gv_last_sm35_action = |SM35 failed: { lv_grp_error } error group(s). First error: { lv_first_error }|.
    ELSE.
      gv_last_sm35_action = |SM35 failed: { lv_grp_error } error group(s), { lv_grp_success } success, { lv_grp_warning } warning, { lv_grp_queued } queued. Use Error Detail/SM35 Log.|.
    ENDIF.
  ELSEIF lv_grp_warning > 0.
    gv_last_sm35_action = |SM35 completed with { lv_grp_warning } unverified group(s); { lv_grp_success } group(s) have positive proof. Review SM35 Log.|.
  ELSEIF lv_grp_queued > 0.
    gv_last_sm35_action = |SM35 session { pv_group } is queued/processing: { lv_grp_queued } group(s) pending verification.|.
  ELSE.
    gv_last_sm35_action = |SM35 verified successfully for { lv_grp_success } group(s).|.
  ENDIF.
  COMMIT WORK AND WAIT.
  PERFORM prepare_alv_0400.
  PERFORM build_exec_cockpit.
ENDFORM.
*<<< END FORM z16_reconcile_sm35

*>>> FORM z16_stamp_sm35_action - moved from Z_BDC_MASS_PO_ENTRY_F01_BUP

FORM z16_stamp_sm35_action
  USING pt_process TYPE ty_t_staging_alv
        pv_msg     TYPE string.

  DATA lt_current TYPE ty_t_staging_alv.
  DATA lt_group   TYPE ty_t_staging_alv.
  DATA ls_src     TYPE ty_staging_alv.
  DATA ls_curr    TYPE ty_staging_alv.
  DATA lv_prev_sid TYPE zbdc_staging_bup-session_id.
  DATA lv_prev_key TYPE zbdc_staging_bup-record_key.
  DATA lv_curr_key TYPE zbdc_staging_bup-record_key.

  "Only stamp rows that BDC_INSERT actually placed into the session.
  LOOP AT pt_process INTO ls_src.
    READ TABLE gt_staging_alv INTO ls_curr
      WITH KEY session_id = ls_src-session_id
               row_index  = ls_src-row_index.
    IF sy-subrc = 0 AND ls_curr-status = gc_st_sm35q.
      APPEND ls_curr TO lt_current.
    ENDIF.
  ENDLOOP.

  SORT lt_current BY session_id record_key row_index.
  CLEAR: lt_group, lv_prev_sid, lv_prev_key.

  LOOP AT lt_current INTO ls_curr.
    lv_curr_key = ls_curr-record_key.
    IF lv_curr_key IS INITIAL.
      lv_curr_key = ls_curr-row_index.
    ENDIF.

    IF lt_group IS NOT INITIAL AND
       ( ls_curr-session_id <> lv_prev_sid OR lv_curr_key <> lv_prev_key ).
      PERFORM update_group_result
        USING lt_group gc_st_sm35q pv_msg ''.
      CLEAR lt_group.
    ENDIF.

    APPEND ls_curr TO lt_group.
    lv_prev_sid = ls_curr-session_id.
    lv_prev_key = lv_curr_key.
  ENDLOOP.

  IF lt_group IS NOT INITIAL.
    PERFORM update_group_result
      USING lt_group gc_st_sm35q pv_msg ''.
  ENDIF.
ENDFORM.

*&---------------------------------------------------------------------*
*& PREVIEW_ENGINE_PLAN - thong bao tom tat truoc khi execute
*&---------------------------------------------------------------------*
*<<< END FORM z16_stamp_sm35_action

*>>> FORM PREVIEW_ENGINE_PLAN - moved from Z_BDC_MASS_PO_ENTRY_F01_BUP
FORM PREVIEW_ENGINE_PLAN
  USING PV_TCODE TYPE SY-TCODE
        PT_PRE   TYPE TY_T_SCRIPT
        PT_ITEM  TYPE TY_T_SCRIPT
        PT_POST  TYPE TY_T_SCRIPT
        PT_MAP   TYPE TY_T_MAP
        PV_BSIZE TYPE I.

  DATA: LV_PRE  TYPE I,
        LV_ITEM TYPE I,
        LV_POST TYPE I,
        LV_MAP  TYPE I.

  LV_PRE  = LINES( PT_PRE ).
  LV_ITEM = LINES( PT_ITEM ).
  LV_POST = LINES( PT_POST ).
  LV_MAP  = LINES( PT_MAP ).

  MESSAGE |Engine plan { PV_TCODE }: PRE={ LV_PRE }, ITEM={ LV_ITEM }, POST={ LV_POST }, MAP={ LV_MAP }, BATCH={ PV_BSIZE }.| TYPE 'S'.
ENDFORM.

*&---------------------------------------------------------------------*
*& COMMIT_CHUNK_IF_DUE - commit theo lo de giam risk update task/lock
*&---------------------------------------------------------------------*
*<<< END FORM PREVIEW_ENGINE_PLAN

*>>> FORM COMMIT_CHUNK_IF_DUE - moved from Z_BDC_MASS_PO_ENTRY_F01_BUP
FORM COMMIT_CHUNK_IF_DUE USING PV_GROUPS TYPE I
                               PV_BSIZE  TYPE I.
  IF P_BDC_MODE = GC_MODE_BATCH.
    RETURN.
  ENDIF.
  IF PV_BSIZE <= 0.
    RETURN.
  ENDIF.
  IF PV_GROUPS MOD PV_BSIZE = 0.
    COMMIT WORK AND WAIT.
    MESSAGE |Da commit chunk sau { PV_GROUPS } nhom.| TYPE 'S'.
  ENDIF.
ENDFORM.

*&---------------------------------------------------------------------*
*& RUN_BDC_ONE_GROUP - 1 RECORD_KEY/PO_KEY = 1 document SAP
*& Responsibilities:
*&   - Build BDCDATA tu PRE + ITEM(n) + POST
*&   - Batch Input mode: BDC_INSERT
*&   - Call Transaction mode: retry lock 3 lan, NOBINPT fix cho ME21N
*&   - Extract document number dung MSGV cho ME21N/MIGO
*&   - Update staging/result/UI counters
*&---------------------------------------------------------------------*
*<<< END FORM COMMIT_CHUNK_IF_DUE

*>>> FORM RUN_BDC_ONE_GROUP - moved from Z_BDC_MASS_PO_ENTRY_F01_BUP

FORM RUN_BDC_ONE_GROUP
  USING    PT_GROUP  TYPE TY_T_STAGING_ALV
           PT_S_PRE  TYPE TY_T_SCRIPT
           PT_S_ITEM TYPE TY_T_SCRIPT
           PT_S_POST TYPE TY_T_SCRIPT
           PT_MAP    TYPE TY_T_MAP
           PV_TCODE  TYPE SY-TCODE
           PV_MODE   TYPE CLIKE
           PV_UPD    TYPE CLIKE
           PV_BIGRP  TYPE APQI-GROUPID
  CHANGING CV_OK     TYPE I
           CV_ERR    TYPE I.

  DATA: LS_FIRST    TYPE TY_STAGING_ALV,
        LS_ITEM     TYPE TY_STAGING_ALV,
        LS_SCR      TYPE ZBDC_SCT_DEF_BUP,
        LV_IDX      TYPE N LENGTH 2,
        LV_ITEMNO   TYPE I,
        LV_ATTEMPT      TYPE I,
        LV_RETRIED      TYPE I,
        LV_RETRYABLE    TYPE ABAP_BOOL,
        LV_RETRY_REASON TYPE STRING,
        LV_MAX_ATTEMPTS TYPE I,
        LV_SUCCESS      TYPE ABAP_BOOL,
        LV_VERIFIED     TYPE ABAP_BOOL,
        LV_PROOF_PENDING TYPE ABAP_BOOL,
        LV_VERIFY_TRY   TYPE I,
        LV_VERIFY_MAX   TYPE I,
        LV_VERIFY_WAIT  TYPE P LENGTH 2 DECIMALS 2 VALUE '0.25',
        LV_OBJ      TYPE ZBDC_RESULT_BUP-SAP_OBJECT_ID,
        LV_MSG      TYPE STRING,
        LV_EFFECTIVE_MODE TYPE C LENGTH 1,
        LV_REBUILT_ME21N  TYPE ABAP_BOOL,
        LV_REBUILD_MSG    TYPE STRING,
        LS_CTU      TYPE CTU_PARAMS.

  READ TABLE PT_GROUP INTO LS_FIRST INDEX 1.
  IF SY-SUBRC <> 0.
    RETURN.
  ENDIF.

  REFRESH BDCDATA.

  LOOP AT PT_S_PRE INTO LS_SCR.
    PERFORM APPEND_SCRIPT_STEP USING LS_SCR LS_FIRST PT_MAP '01'.
  ENDLOOP.

  LV_ITEMNO = 0.
  LOOP AT PT_GROUP INTO LS_ITEM.
    LV_ITEMNO = LV_ITEMNO + 1.
    LV_IDX = LV_ITEMNO.
    LOOP AT PT_S_ITEM INTO LS_SCR.
      PERFORM APPEND_SCRIPT_STEP USING LS_SCR LS_ITEM PT_MAP LV_IDX.
    ENDLOOP.
  ENDLOOP.

  LOOP AT PT_S_POST INTO LS_SCR.
    PERFORM APPEND_SCRIPT_STEP USING LS_SCR LS_FIRST PT_MAP '01'.
  ENDLOOP.

  CLEAR: LV_REBUILT_ME21N, LV_REBUILD_MSG.
  PERFORM z26_repair_me21n_bdc
    USING    PV_TCODE PT_GROUP PT_MAP
    CHANGING LV_REBUILT_ME21N LV_REBUILD_MSG.
  IF LV_REBUILT_ME21N = ABAP_TRUE.
    PERFORM SAVE_SYNTHETIC_ENGINE_LOG
      USING PT_GROUP PV_TCODE 0 GC_ST_WARNING LV_REBUILD_MSG '' ''.
  ENDIF.

  IF BDCDATA[] IS INITIAL.
    CV_ERR = CV_ERR + 1.
    LV_MSG = 'BDCDATA rong: script/mapping khong sinh duoc buoc nao.'.
    PERFORM SAVE_SYNTHETIC_ENGINE_LOG
      USING PT_GROUP PV_TCODE 0 GC_ST_ERROR LV_MSG '' ''.
    PERFORM UPDATE_GROUP_RESULT USING PT_GROUP GC_ST_ERROR LV_MSG ''.
    PERFORM UPDATE_EXEC_COUNTERS USING PT_GROUP ABAP_FALSE.
    RETURN.
  ENDIF.

  IF P_BDC_MODE = GC_MODE_BATCH.
    DATA: lv_insert_subrc   TYPE i,
          lv_insert_attempt TYPE i,
          lv_insert_reason  TYPE string,
          lv_sm35_bdc_ok    TYPE abap_bool,
          lv_sm35_bdc_msg   TYPE string.

    PERFORM z18_validate_sm35_bdc
      USING    PV_TCODE
      CHANGING lv_sm35_bdc_ok lv_sm35_bdc_msg.
    IF lv_sm35_bdc_ok <> abap_true.
      CV_ERR = CV_ERR + 1.
      LV_MSG = lv_sm35_bdc_msg.
      PERFORM SAVE_SYNTHETIC_ENGINE_LOG
        USING PT_GROUP PV_TCODE 0 GC_ST_ERROR LV_MSG '' ''.
      PERFORM UPDATE_GROUP_RESULT USING PT_GROUP GC_ST_ERROR LV_MSG ''.
      PERFORM UPDATE_EXEC_COUNTERS USING PT_GROUP ABAP_FALSE.
      RETURN.
    ENDIF.

    PERFORM z17_insert_batch_group
      USING    PV_TCODE
      CHANGING lv_insert_subrc lv_insert_attempt lv_insert_reason.

    IF lv_insert_subrc = 0.
      CV_OK = CV_OK + 1.
      LV_MSG = |Queued in SM35 session { PV_BIGRP }. No SAP document exists yet.|.
      IF lv_insert_attempt > 1.
        LV_MSG = |{ LV_MSG } Insert succeeded after { lv_insert_attempt } attempt(s).|.
      ENDIF.
      PERFORM SAVE_SYNTHETIC_ENGINE_LOG
        USING PT_GROUP PV_TCODE lv_insert_attempt GC_ST_SM35Q LV_MSG '' ''.
      PERFORM UPDATE_GROUP_RESULT USING PT_GROUP GC_ST_SM35Q LV_MSG ''.
      G_EXEC_CURR = G_EXEC_CURR + LINES( PT_GROUP ).
    ELSE.
      CV_ERR = CV_ERR + 1.
      LV_MSG = |BDC_INSERT failed after { lv_insert_attempt } attempt(s): { lv_insert_reason }, sy-subrc={ lv_insert_subrc }.|.
      PERFORM SAVE_SYNTHETIC_ENGINE_LOG
        USING PT_GROUP PV_TCODE lv_insert_attempt GC_ST_ERROR LV_MSG '' 'X'.
      PERFORM UPDATE_GROUP_RESULT USING PT_GROUP GC_ST_ERROR LV_MSG ''.
      PERFORM UPDATE_EXEC_COUNTERS USING PT_GROUP ABAP_FALSE.
    ENDIF.
    RETURN.
  ENDIF.

  CLEAR: LV_SUCCESS, LV_OBJ, LV_MSG, LV_RETRIED.
  LV_MAX_ATTEMPTS = 1.
  IF CHKP_RETRY = 'X' AND PV_UPD = 'S'.
    LV_MAX_ATTEMPTS = GC_MAX_ATTEMPTS.
  ENDIF.

  DO LV_MAX_ATTEMPTS TIMES.
    LV_ATTEMPT = SY-INDEX.
    REFRESH MESSTAB.

    CLEAR LS_CTU.
    LV_EFFECTIVE_MODE = PV_MODE.
    IF PV_TCODE = 'ME21N' AND LV_EFFECTIVE_MODE = 'N'.
      LV_EFFECTIVE_MODE = 'E'.
      IF LV_ATTEMPT = 1.
        LV_MSG = 'ME21N uses SAPLMEGUI; display mode N is switched to E for real automatic BDC in SAP GUI.'.
        PERFORM SAVE_SYNTHETIC_ENGINE_LOG
          USING PT_GROUP PV_TCODE LV_ATTEMPT GC_ST_WARNING LV_MSG '' ''.
      ENDIF.
    ENDIF.
    LS_CTU-DISMODE  = LV_EFFECTIVE_MODE.
    LS_CTU-UPDMODE  = PV_UPD.
    LS_CTU-DEFSIZE  = 'X'.
    LS_CTU-RACOMMIT = 'X'.
    LS_CTU-NOBINPT  = 'X'.  "Critical for Enjoy transactions like ME21N
    LS_CTU-NOBIEND  = 'X'.  "Keep CTU semantics through nested transaction end

    CALL TRANSACTION PV_TCODE USING BDCDATA
      OPTIONS FROM LS_CTU
      MESSAGES INTO MESSTAB.

    PERFORM EXTRACT_DOCUMENT_NUMBER
      USING    PV_TCODE
      CHANGING LV_SUCCESS LV_OBJ.

    "V5AY strict proof: a success message/document number is only a candidate.
    "The target business table must confirm the object before SUCCESS is set.
    "Async update A receives a bounded grace window; no automatic repeat is
    "performed because a delayed commit could otherwise create duplicates.
    CLEAR: LV_VERIFIED, LV_PROOF_PENDING, LV_VERIFY_TRY.
    IF LV_SUCCESS = ABAP_TRUE AND LV_OBJ IS NOT INITIAL.
      LV_VERIFY_MAX = 1.
      IF PV_UPD = 'A'.
        LV_VERIFY_MAX = 20.
      ENDIF.

      DO LV_VERIFY_MAX TIMES.
        LV_VERIFY_TRY = SY-INDEX.
        PERFORM z22_verify_current_obj
          USING    PV_TCODE LV_OBJ
          CHANGING LV_VERIFIED.
        IF LV_VERIFIED = ABAP_TRUE.
          EXIT.
        ENDIF.
        IF PV_UPD = 'A' AND LV_VERIFY_TRY < LV_VERIFY_MAX.
          WAIT UP TO LV_VERIFY_WAIT SECONDS.
        ENDIF.
      ENDDO.

      IF LV_VERIFIED <> ABAP_TRUE.
        LV_PROOF_PENDING = ABAP_TRUE.
        LV_SUCCESS = ABAP_FALSE.
      ENDIF.
    ELSEIF LV_SUCCESS = ABAP_TRUE.
      LV_SUCCESS = ABAP_FALSE.
    ENDIF.

    "MUC 3: ghi moi BDC message cua tung attempt vao ZBDC_RESULT_BUP.
    "Neu MESSTAB rong, form se ghi synthetic technical log de khong mat dau loi.
    PERFORM SAVE_BDC_MESSAGE_LOGS
      USING PT_GROUP PV_TCODE LV_ATTEMPT LV_OBJ.

    IF LV_SUCCESS = ABAP_TRUE.
      EXIT.
    ENDIF.

    CLEAR: LV_RETRYABLE, LV_RETRY_REASON.
    PERFORM z17_is_transient_bdc
      CHANGING LV_RETRYABLE LV_RETRY_REASON.

    IF LV_RETRYABLE = ABAP_TRUE AND LV_ATTEMPT < LV_MAX_ATTEMPTS.
      LV_RETRIED = LV_RETRIED + 1.
      LV_MSG = |Transient BDC issue ({ LV_RETRY_REASON }) - retry { LV_ATTEMPT + 1 }/{ LV_MAX_ATTEMPTS }.|.
      PERFORM SAVE_SYNTHETIC_ENGINE_LOG
        USING PT_GROUP PV_TCODE LV_ATTEMPT GC_ST_WARNING LV_MSG LV_OBJ 'X'.
      WAIT UP TO GC_WAIT_SECONDS SECONDS.
      CONTINUE.
    ELSEIF LV_RETRYABLE = ABAP_TRUE AND CHKP_RETRY <> 'X'.
      LV_MSG = |Transient issue detected ({ LV_RETRY_REASON }), but automatic retry is disabled in configuration.|.
      PERFORM SAVE_SYNTHETIC_ENGINE_LOG
        USING PT_GROUP PV_TCODE LV_ATTEMPT GC_ST_WARNING LV_MSG LV_OBJ 'X'.
    ELSEIF LV_RETRYABLE = ABAP_TRUE AND PV_UPD = 'A'.
      LV_MSG = |Transient issue detected ({ LV_RETRY_REASON }). Async update is not auto-retried to avoid duplicate documents.|.
      PERFORM SAVE_SYNTHETIC_ENGINE_LOG
        USING PT_GROUP PV_TCODE LV_ATTEMPT GC_ST_WARNING LV_MSG LV_OBJ 'X'.
    ENDIF.

    EXIT.
  ENDDO.

  IF LV_SUCCESS = ABAP_TRUE AND LV_VERIFIED = ABAP_TRUE.
    CV_OK = CV_OK + 1.
    LV_MSG = |{ PV_TCODE } OK - SAP object { LV_OBJ } created and verified.|.
    IF LV_RETRIED > 0.
      LV_MSG = |{ LV_MSG } (retry lock { LV_RETRIED } time(s))|.
    ENDIF.
    PERFORM UPDATE_GROUP_RESULT USING PT_GROUP GC_ST_SUCCESS LV_MSG LV_OBJ.
    PERFORM UPDATE_EXEC_COUNTERS USING PT_GROUP ABAP_TRUE.
  ELSEIF LV_PROOF_PENDING = ABAP_TRUE AND LV_OBJ IS NOT INITIAL.
    "A candidate number without database proof is deliberately not ERROR and
    "not SUCCESS. WARNING prevents duplicate reruns while allowing Refresh
    "Queue to verify the object after an asynchronous update completes.
    CV_OK = CV_OK + 1.
    LV_MSG = |SAP returned candidate object { LV_OBJ }, but { PV_TCODE } proof is not visible after { LV_VERIFY_TRY } verification attempt(s). Do not duplicate-run; refresh proof first.|.
    PERFORM SAVE_SYNTHETIC_ENGINE_LOG
      USING PT_GROUP PV_TCODE LV_ATTEMPT GC_ST_WARNING LV_MSG LV_OBJ ''.
    PERFORM UPDATE_GROUP_RESULT USING PT_GROUP GC_ST_WARNING LV_MSG LV_OBJ.
    G_EXEC_CURR = G_EXEC_CURR + LINES( PT_GROUP ).
  ELSE.
    CV_ERR = CV_ERR + 1.
    PERFORM BUILD_ERROR_TEXT CHANGING LV_MSG.
    IF LV_RETRIED > 0.
      LV_MSG = |{ LV_MSG } (retried { LV_RETRIED } time(s))|.
    ENDIF.
    PERFORM UPDATE_GROUP_RESULT USING PT_GROUP GC_ST_ERROR LV_MSG ''.
    PERFORM UPDATE_EXEC_COUNTERS USING PT_GROUP ABAP_FALSE.
  ENDIF.
ENDFORM.

*&---------------------------------------------------------------------*
*& APPEND_SCRIPT_STEP - convert 1 row script -> BDCDATA
*& - IS_NEW_SCREEN='X' => BDC_DYNPRO
*& - STATIC => STATIC_VALUE
*& - DYNAMIC => SOURCE_COLUMN -> ZBDC_MAPPING_BUP-STAGING_FIELD -> value
*& - FIELD_NAME co &IDX& => thay bang 01/02/03...
*&---------------------------------------------------------------------*
*<<< END FORM RUN_BDC_ONE_GROUP

*>>> FORM EXTRACT_DOCUMENT_NUMBER - moved from Z_BDC_MASS_PO_ENTRY_F01_BUP
FORM EXTRACT_DOCUMENT_NUMBER
  USING    PV_TCODE   TYPE SY-TCODE
  CHANGING CV_SUCCESS TYPE ABAP_BOOL
           CV_OBJ     TYPE ZBDC_RESULT_BUP-SAP_OBJECT_ID.

  DATA: LV_CAND TYPE STRING.

  CLEAR: CV_SUCCESS, CV_OBJ.

  IF PV_TCODE = 'MIGO'.
    READ TABLE MESSTAB WITH KEY MSGID = GC_MSGID_MIGO MSGNR = GC_MSGNR_MIGO.
    IF SY-SUBRC = 0.
      CV_SUCCESS = ABAP_TRUE.
      CV_OBJ = MESSTAB-MSGV1.
      CONDENSE CV_OBJ NO-GAPS.
      RETURN.
    ENDIF.
  ELSE.
    READ TABLE MESSTAB WITH KEY MSGID = GC_MSGID_PO MSGNR = GC_MSGNR_PO.
    IF SY-SUBRC = 0.
      CV_SUCCESS = ABAP_TRUE.

      "PO number priority: MSGV2 -> MSGV1 -> MSGV3 -> MSGV4.
      LV_CAND = MESSTAB-MSGV2.
      PERFORM ACCEPT_NUMERIC_OBJECT USING LV_CAND CHANGING CV_OBJ.
      IF CV_OBJ IS INITIAL.
        LV_CAND = MESSTAB-MSGV1.
        PERFORM ACCEPT_NUMERIC_OBJECT USING LV_CAND CHANGING CV_OBJ.
      ENDIF.
      IF CV_OBJ IS INITIAL.
        LV_CAND = MESSTAB-MSGV3.
        PERFORM ACCEPT_NUMERIC_OBJECT USING LV_CAND CHANGING CV_OBJ.
      ENDIF.
      IF CV_OBJ IS INITIAL.
        LV_CAND = MESSTAB-MSGV4.
        PERFORM ACCEPT_NUMERIC_OBJECT USING LV_CAND CHANGING CV_OBJ.
      ENDIF.

      RETURN.
    ENDIF.
  ENDIF.
ENDFORM.

*&---------------------------------------------------------------------*
*& ACCEPT_NUMERIC_OBJECT - chi nhan object id toan so, tranh "StandardP"
*&---------------------------------------------------------------------*
*<<< END FORM EXTRACT_DOCUMENT_NUMBER

*>>> FORM ACCEPT_NUMERIC_OBJECT - moved from Z_BDC_MASS_PO_ENTRY_F01_BUP
FORM ACCEPT_NUMERIC_OBJECT USING    PV_TEXT TYPE ANY
                           CHANGING CV_OBJ  TYPE ZBDC_RESULT_BUP-SAP_OBJECT_ID.
  DATA LV_TEXT TYPE STRING.
  LV_TEXT = PV_TEXT.
  CONDENSE LV_TEXT NO-GAPS.
  IF LV_TEXT IS INITIAL.
    RETURN.
  ENDIF.
  IF LV_TEXT CO '0123456789'.
    CV_OBJ = LV_TEXT.
  ENDIF.
ENDFORM.

*&---------------------------------------------------------------------*
*& IS_LOCK_ERROR - classify retryable errors
*&---------------------------------------------------------------------*
*<<< END FORM ACCEPT_NUMERIC_OBJECT

*>>> FORM z17_text_transient - moved from Z_BDC_MASS_PO_ENTRY_F01_BUP
FORM z17_text_transient
  USING    pv_text   TYPE csequence
  CHANGING cv_retry  TYPE abap_bool
           cv_reason TYPE string.

  DATA lv_text TYPE string.

  CLEAR: cv_retry, cv_reason.
  lv_text = pv_text.
  TRANSLATE lv_text TO LOWER CASE.
  CONDENSE lv_text.

  IF lv_text CS 'lock' OR lv_text CS 'locked' OR
     lv_text CS 'enqueue' OR lv_text CS 'gesperrt' OR
     lv_text CS 'currently processed' OR
     lv_text CS 'dang xu ly' OR lv_text CS 'đang xử lý' OR
     lv_text CS 'khoa' OR lv_text CS 'khóa'.
    cv_retry  = abap_true.
    cv_reason = 'LOCK_OR_ENQUEUE'.
    RETURN.
  ENDIF.

  IF lv_text CS 'temporar' OR lv_text CS 'try again' OR
     lv_text CS 'system busy' OR lv_text CS 'resource busy' OR
     lv_text CS 'timeout' OR lv_text CS 'time out' OR
     lv_text CS 'communication failure' OR
     lv_text CS 'connection terminated'.
    cv_retry  = abap_true.
    cv_reason = 'TEMPORARY_SYSTEM'.
    RETURN.
  ENDIF.

  IF ( lv_text CS 'session' OR lv_text CS 'queue' OR
       lv_text CS 'batch input' ) AND
     ( lv_text CS 'running' OR lv_text CS 'busy' OR
       lv_text CS 'in process' OR lv_text CS 'not available' OR
       lv_text CS 'cannot be opened' OR lv_text CS 'queue error' ).
    cv_retry  = abap_true.
    cv_reason = 'TEMPORARY_SESSION'.
    RETURN.
  ENDIF.

  IF lv_text CS 'update task' AND
     ( lv_text CS 'temporar' OR lv_text CS 'busy' OR
       lv_text CS 'terminated' ).
    cv_retry  = abap_true.
    cv_reason = 'TEMPORARY_UPDATE'.
  ENDIF.
ENDFORM.
*<<< END FORM z17_text_transient

*>>> FORM z17_is_transient_bdc - moved from Z_BDC_MASS_PO_ENTRY_F01_BUP

FORM z17_is_transient_bdc
  CHANGING cv_retry  TYPE abap_bool
           cv_reason TYPE string.

  DATA: lv_raw   TYPE string,
        lv_text  TYPE c LENGTH 255,
        lv_hit   TYPE abap_bool,
        lv_why   TYPE string.

  CLEAR: cv_retry, cv_reason.

  LOOP AT messtab WHERE msgtyp = 'E' OR msgtyp = 'A' OR msgtyp = 'W'.
    CLEAR: lv_raw, lv_text, lv_hit, lv_why.
    CALL FUNCTION 'FORMAT_MESSAGE'
      EXPORTING
        id   = messtab-msgid
        lang = sy-langu
        no   = messtab-msgnr
        v1   = messtab-msgv1
        v2   = messtab-msgv2
        v3   = messtab-msgv3
        v4   = messtab-msgv4
      IMPORTING
        msg  = lv_text
      EXCEPTIONS
        OTHERS = 1.

    lv_raw = |{ messtab-msgid } { messtab-msgnr } { messtab-msgv1 } { messtab-msgv2 } { messtab-msgv3 } { messtab-msgv4 } { lv_text }|.
    PERFORM z17_text_transient
      USING    lv_raw
      CHANGING lv_hit lv_why.
    IF lv_hit = abap_true.
      cv_retry  = abap_true.
      cv_reason = lv_why.
      EXIT.
    ENDIF.
  ENDLOOP.
ENDFORM.
*<<< END FORM z17_is_transient_bdc

*>>> FORM UPDATE_EXEC_COUNTERS - moved from Z_BDC_MASS_PO_ENTRY_F01_BUP
FORM UPDATE_EXEC_COUNTERS USING PT_GROUP TYPE TY_T_STAGING_ALV
                                PV_OK    TYPE ABAP_BOOL.
  DATA LV_ROWS TYPE I.

  LV_ROWS = LINES( PT_GROUP ).
  G_EXEC_CURR = G_EXEC_CURR + LV_ROWS.

  IF PV_OK = ABAP_TRUE.
    G_EXEC_SUCCESS = G_EXEC_SUCCESS + LV_ROWS.
  ELSE.
    G_EXEC_ERROR = G_EXEC_ERROR + LV_ROWS.
  ENDIF.
ENDFORM.

*&---------------------------------------------------------------------*
*& UPDATE_GROUP_RESULT - update staging internal + DB + result log
*& Professional flow: internal table first, DB staging in one MODIFY TABLE,
*& then exactly 1 result header log per document group.
*&---------------------------------------------------------------------*
*<<< END FORM UPDATE_EXEC_COUNTERS

*>>> FORM PROCESS_NEXT_BDC_RECORD - moved from Z_BDC_MASS_PO_ENTRY_F01_BUP
FORM PROCESS_NEXT_BDC_RECORD.
  DATA: LT_ONE TYPE TY_T_STAGING_ALV,
        LV_KEY TYPE ZBDC_STAGING_BUP-RECORD_KEY.

  IF G_STOP_FLAG = 'X'.
    MESSAGE 'Da dung xu ly theo yeu cau STOP.' TYPE 'S'.
    RETURN.
  ENDIF.

  READ TABLE GT_STAGING_ALV INTO DATA(LS_FIRST_READY) WITH KEY STATUS = GC_ST_READY.
  IF SY-SUBRC <> 0.
    MESSAGE 'Het dong READY - da xu ly xong.' TYPE 'S'.
    RETURN.
  ENDIF.

  LV_KEY = LS_FIRST_READY-RECORD_KEY.
  IF LV_KEY IS INITIAL.
    APPEND LS_FIRST_READY TO LT_ONE.
  ELSE.
    LOOP AT GT_STAGING_ALV INTO DATA(LS_R)
      WHERE STATUS = GC_ST_READY AND RECORD_KEY = LV_KEY.
      APPEND LS_R TO LT_ONE.
    ENDLOOP.
  ENDIF.

  PERFORM EXECUTE_BDC_ENGINE USING LT_ONE P_BDC_MODE.
ENDFORM.

*&---------------------------------------------------------------------*
*& STOP_BDC_EXECUTION - Phase 8: graceful stop after current group
*&---------------------------------------------------------------------*
*<<< END FORM PROCESS_NEXT_BDC_RECORD

*>>> FORM STOP_BDC_EXECUTION - moved from Z_BDC_MASS_PO_ENTRY_F01_BUP
FORM STOP_BDC_EXECUTION.
  G_STOP_FLAG = 'X'.
  MESSAGE 'Da gui STOP - engine se dung sau document group hien tai.' TYPE 'S'.
ENDFORM.

*&---------------------------------------------------------------------*
*& UPLOAD_SHDB_RECORDING - SHDB txt parser -> ZBDC_SCT_DEF_BUP
*& Defensive parser: preserve BDC_CURSOR/BDC_SUBSCR for true SM35
*& batch-input compatibility; confirm before overwrite.
*& Sau upload van can review ROW_TYPE/VALUE_TYPE/SOURCE_COLUMN cho item.
*&---------------------------------------------------------------------*
*<<< END FORM STOP_BDC_EXECUTION

*>>> FORM init_execution_monitor - moved from Z_BDC_MASS_PO_ENTRY_F01_BUP
FORM init_execution_monitor.
  DATA lv_total TYPE i.
  DATA lv_den   TYPE i.
  DATA lv_pct_i TYPE p LENGTH 7 DECIMALS 2.

  IF chkp_stop_on_error IS INITIAL.
    chkp_stop_on_error = 'X'.
  ENDIF.

  IF gt_staging IS INITIAL.
    PERFORM load_latest_staging_for_tcode USING p_transaction CHANGING lv_total.
  ENDIF.

  IF gt_exec_scope_0500 IS NOT INITIAL.
    READ TABLE gt_exec_scope_0500 INTO DATA(ls_scope_first) INDEX 1.
    IF sy-subrc = 0.
      txtgv_exec_session = ls_scope_first-session_id.
    ENDIF.
    lv_den = lines( gt_exec_scope_0500 ).
  ELSE.
    READ TABLE gt_staging INTO DATA(ls_first) INDEX 1.
    IF sy-subrc = 0 AND txtgv_exec_session IS INITIAL.
      txtgv_exec_session = ls_first-session_id.
    ENDIF.
    IF txtgv_exec_total IS NOT INITIAL AND txtgv_exec_total <> '0'.
      lv_den = txtgv_exec_total.
    ELSE.
      lv_den = lines( gt_staging ).
    ENDIF.
  ENDIF.

  "After an ALV execution event, use exact business-group counters retained
  "by the engine. GT_EXEC_SCOPE_0500 may contain several item rows per group.
  IF gv_exec_run_total > 0.
    lv_den = gv_exec_run_total.
    IF gv_exec_run_done > g_exec_curr.
      g_exec_curr = gv_exec_run_done.
    ENDIF.
  ENDIF.

  IF lv_den < g_exec_curr.
    lv_den = g_exec_curr.
  ENDIF.

  WRITE g_exec_curr TO txtgv_exec_curr LEFT-JUSTIFIED.
  WRITE lv_den      TO txtgv_exec_total LEFT-JUSTIFIED.

  IF lv_den > 0.
    lv_pct_i = g_exec_curr.
    lv_pct_i = lv_pct_i * 100 / lv_den.
  ELSE.
    lv_pct_i = 0.
  ENDIF.
  WRITE lv_pct_i TO txtgv_exec_pct LEFT-JUSTIFIED.

  IF txtgv_exec_elapsed IS INITIAL.
    WRITE gv_exec_elapsed TO txtgv_exec_elapsed LEFT-JUSTIFIED.
  ENDIF.
  IF txtgv_exec_eta IS INITIAL.
    txtgv_exec_eta = 'n/a'.
  ENDIF.
  CONCATENATE txtgv_exec_curr '/' txtgv_exec_total INTO gv_exec_progress SEPARATED BY space.
ENDFORM.


*&---------------------------------------------------------------------*
*& V5F - Scope builders for 0500
*& Run All / Run Selected decide WHAT to run; 0100 decides HOW to run.
*&---------------------------------------------------------------------*
*<<< END FORM init_execution_monitor

*>>> FORM collect_ready_groups_all - moved from Z_BDC_MASS_PO_ENTRY_F01_BUP

FORM collect_ready_groups_all
  CHANGING ct_process TYPE ty_t_staging_alv.

  DATA ls_exec TYPE ty_exec_disp.
  DATA ls_alv  TYPE ty_staging_alv.

  REFRESH ct_process.

  PERFORM prepare_alv_0400.
  PERFORM build_exec_cockpit.

  LOOP AT gt_exec_disp INTO ls_exec WHERE run_status = gc_st_ready.
    PERFORM z16_append_exec_group USING ls_exec CHANGING ct_process.
  ENDLOOP.

  "Fallback for old/runtime cases where the cockpit is not built yet.
  IF ct_process IS INITIAL.
    LOOP AT gt_staging_alv INTO ls_alv WHERE status = gc_st_ready.
      APPEND ls_alv TO ct_process.
    ENDLOOP.
  ENDIF.
ENDFORM.
*<<< END FORM collect_ready_groups_all

*>>> FORM collect_ready_groups_selected - moved from Z_BDC_MASS_PO_ENTRY_F01_BUP

FORM collect_ready_groups_selected
  CHANGING ct_process TYPE ty_t_staging_alv.

  DATA: lt_rows TYPE lvc_t_row,
        ls_row  TYPE lvc_s_row,
        ls_exec TYPE ty_exec_disp.

  REFRESH ct_process.

  IF gt_exec_disp IS INITIAL.
    PERFORM prepare_alv_0400.
    PERFORM build_exec_cockpit.
  ENDIF.

  "V5AK: read exactly what the user selected in the native left row marker.
  "SEL_MODE = 'D' supports multiple rows and Select All. No hidden/sticky
  "business-key cache is allowed to add old rows after BACK or refresh.
  IF go_exec_grid IS BOUND.
    CALL METHOD go_exec_grid->get_selected_rows
      IMPORTING et_index_rows = lt_rows.
  ELSEIF go_grid_0400 IS BOUND.
    CALL METHOD go_grid_0400->get_selected_rows
      IMPORTING et_index_rows = lt_rows.
  ENDIF.

  SORT lt_rows BY index.
  DELETE ADJACENT DUPLICATES FROM lt_rows COMPARING index.

  LOOP AT lt_rows INTO ls_row.
    READ TABLE gt_exec_disp INTO ls_exec INDEX ls_row-index.
    IF sy-subrc <> 0 OR ls_exec-run_status <> gc_st_ready.
      CONTINUE.
    ENDIF.
    PERFORM z16_append_exec_group USING ls_exec CHANGING ct_process.
  ENDLOOP.
ENDFORM.
*<<< END FORM collect_ready_groups_selected

*>>> FORM z16_select_all_ready - moved from Z_BDC_MASS_PO_ENTRY_F01_BUP

FORM z16_select_all_ready.
  DATA: lt_rows TYPE lvc_t_row,
        ls_row  TYPE lvc_s_row,
        lv_cnt  TYPE i.

  LOOP AT gt_exec_disp INTO DATA(ls_exec_selall)
       WHERE run_status = gc_st_ready.
    CLEAR ls_row.
    ls_row-index = sy-tabix.
    APPEND ls_row TO lt_rows.
    lv_cnt = lv_cnt + 1.
  ENDLOOP.

  IF go_exec_grid IS BOUND.
    CALL METHOD go_exec_grid->set_selected_rows
      EXPORTING it_index_rows = lt_rows.
  ENDIF.
  MESSAGE |Selected { lv_cnt } READY group(s). Press Run Selected.| TYPE 'S'.
ENDFORM.
*<<< END FORM z16_select_all_ready

*>>> FORM z16_clear_exec_sel - moved from Z_BDC_MASS_PO_ENTRY_F01_BUP

FORM z16_clear_exec_sel.
  PERFORM z19_reset_0400_selection.
  MESSAGE 'ALV row selection cleared.' TYPE 'S'.
ENDFORM.

*&---------------------------------------------------------------------*
*& V5AK - Native 0400 multi-row selection helpers
*&---------------------------------------------------------------------*
*<<< END FORM z16_clear_exec_sel

*>>> FORM z16_count_0500_q - moved from Z_BDC_MASS_PO_ENTRY_F01_BUP

FORM z16_count_0500_q
  CHANGING cv_done  TYPE i
           cv_total TYPE i.

  CLEAR: cv_done, cv_total.
  cv_total = lines( gt_exec_disp ).

  LOOP AT gt_exec_disp ASSIGNING FIELD-SYMBOL(<ls_q_count>).
    CASE <ls_q_count>-run_status.
      "V5BB: WARNING / SM35_WAIT / proof-pending is not business-complete.
      "Completion is only a final business result: success, real error,
      "skipped, or explicit partial result. This prevents the 0500 header
      "from showing 100% while SAP Object proof is still missing.
      WHEN gc_st_success OR gc_st_error OR 'SKIPPED' OR 'PARTIAL'.
        cv_done = cv_done + 1.
    ENDCASE.
  ENDLOOP.
ENDFORM.
*<<< END FORM z16_count_0500_q

*>>> FORM prepare_0500_exec_scope - moved from Z_BDC_MASS_PO_ENTRY_F01_BUP

FORM prepare_0500_exec_scope
  USING    iv_scope TYPE csequence
  CHANGING cv_count TYPE i
           cv_ok    TYPE abap_bool.

  DATA lt_process TYPE STANDARD TABLE OF ty_staging_alv.
  DATA lt_group_keys TYPE SORTED TABLE OF string WITH UNIQUE KEY table_line.
  DATA lv_group_key TYPE string.

  CLEAR: cv_count, cv_ok, gt_exec_scope_0500,
         gv_exec_run_total, gv_exec_run_done, gv_exec_run_start_rt,
         gv_exec_run_active, gv_exec_run_engine, gv_exec_run_phase,
         gv_exec_run_queued, gv_exec_elapsed,
         gv_async_done, gv_async_active, gv_async_receive_rc,
         gv_async_subrc, gv_async_message.
  gv_exec_scope_ready = abap_false.
  gv_exec_stop_req    = abap_false.
  g_exec_curr         = 0.
  CLEAR g_stop_flag.
  gv_exec_scope_0500  = iv_scope.

  PERFORM prepare_alv_0400.

  IF iv_scope = 'ALL'.
    PERFORM collect_ready_groups_all CHANGING lt_process.
    gv_exec_scope_text = 'ALL READY groups from 0400'.
  ELSEIF iv_scope = 'SELECTED'.
    PERFORM collect_ready_groups_selected CHANGING lt_process.
    gv_exec_scope_text = 'SELECTED READY group(s) from 0400'.
  ELSE.
    PERFORM collect_ready_groups_all CHANGING lt_process.
    gv_exec_scope_text = 'READY groups from current session'.
  ENDIF.

  IF lt_process IS INITIAL.
    RETURN.
  ENDIF.

  LOOP AT lt_process INTO DATA(ls_count_scope).
    IF ls_count_scope-record_key IS INITIAL.
      lv_group_key = |{ ls_count_scope-session_id }#ROW#{ ls_count_scope-row_index }|.
    ELSE.
      lv_group_key = |{ ls_count_scope-session_id }#{ ls_count_scope-record_key }|.
    ENDIF.
    INSERT lv_group_key INTO TABLE lt_group_keys.
  ENDLOOP.
  cv_count = lines( lt_group_keys ).

  gt_exec_scope_0500  = lt_process.
  gv_exec_scope_ready = abap_true.
  "The execution scope is now copied by business key. Clear the visual
  "selection so returning from 0500 starts from a predictable empty state.
  PERFORM z19_reset_0400_selection.
  g_exec_curr         = 0.
  txtgv_exec_total    = cv_count.
  txtgv_exec_curr     = '0'.
  txtgv_exec_pct      = '0.00'.
  txtgv_exec_elapsed  = '0'.
  txtgv_exec_eta      = 'n/a'.

  READ TABLE lt_process INTO DATA(ls_first) INDEX 1.
  IF sy-subrc = 0.
    txtgv_exec_session = ls_first-session_id.
  ENDIF.

  cv_ok = abap_true.
ENDFORM.
*<<< END FORM prepare_0500_exec_scope

*>>> FORM z16_current_ready_scope - moved from Z_BDC_MASS_PO_ENTRY_F01_BUP

FORM z16_current_ready_scope
  USING    it_scope TYPE ty_t_staging_alv
  CHANGING ct_ready TYPE ty_t_staging_alv.

  DATA ls_scope TYPE ty_staging_alv.
  DATA ls_curr  TYPE ty_staging_alv.

  REFRESH ct_ready.
  PERFORM prepare_alv_0400.

  LOOP AT it_scope INTO ls_scope.
    CLEAR ls_curr.
    READ TABLE gt_staging_alv INTO ls_curr
      WITH KEY session_id = ls_scope-session_id
               row_index  = ls_scope-row_index.
    IF sy-subrc = 0 AND ls_curr-status = gc_st_ready.
      APPEND ls_curr TO ct_ready.
    ENDIF.
  ENDLOOP.
ENDFORM.

*&---------------------------------------------------------------------*
*& V5O - Strictly separated 0500 execution actions
*&---------------------------------------------------------------------*
*&---------------------------------------------------------------------*
*& V5AI - Close confirmation popup first, execute on next PAI roundtrip
*&---------------------------------------------------------------------*
*<<< END FORM z16_current_ready_scope

*>>> FORM z19_request_0500_run - moved from Z_BDC_MASS_PO_ENTRY_F01_BUP
FORM z19_request_0500_run USING iv_engine TYPE c.
  IF gv_0500_pending_run = abap_true OR gv_exec_run_active = abap_true.
    MESSAGE |Queue is already processing { gv_exec_run_done }/{ gv_exec_run_total }; the remaining selected groups continue automatically.| TYPE 'S'.
    RETURN.
  ENDIF.

  "V5AK UX: choosing Execute Now or Run Batch Session is already an explicit
  "user action. Start immediately on the next PAI roundtrip; no confirmation
  "popup is shown and therefore nothing can remain painted over progress.
  gv_0500_pending_engine = iv_engine.
  gv_0500_pending_run    = abap_true.
  CLEAR gv_0500_confirmed.
  gv_exec_run_phase      = 'Starting execution'.
  PERFORM z16_force_0500_repaint.

  TRY.
      cl_gui_cfw=>set_new_ok_code( new_code = 'ZRUN500' ).
    CATCH cx_root.
      CLEAR: gv_0500_pending_run, gv_0500_pending_engine.
      MESSAGE 'Could not start execution roundtrip. Press the engine button again.' TYPE 'S' DISPLAY LIKE 'E'.
  ENDTRY.
ENDFORM.
*<<< END FORM z19_request_0500_run

*>>> FORM z19_execute_pending_0500 - moved from Z_BDC_MASS_PO_ENTRY_F01_BUP

FORM z19_execute_pending_0500.
  DATA lv_engine TYPE c.

  IF gv_0500_pending_run <> abap_true.
    RETURN.
  ENDIF.

  lv_engine = gv_0500_pending_engine.
  CLEAR: gv_0500_pending_run, gv_0500_pending_engine.

  CASE lv_engine.
    WHEN 'B'.
      PERFORM z16_queue_sm35_0500.
    WHEN OTHERS.
      PERFORM z16_execute_now_0500.
  ENDCASE.
  PERFORM z18_request_0500_pbo.
ENDFORM.
*<<< END FORM z19_execute_pending_0500

*>>> FORM z16_execute_now_0500 - moved from Z_BDC_MASS_PO_ENTRY_F01_BUP


FORM z16_execute_now_0500.
  DATA: lv_saved_mode   TYPE char30,
        lv_saved_bg     TYPE c LENGTH 1,
        lv_disp_mode    TYPE c LENGTH 1,
        lv_upd_mode     TYPE c LENGTH 1,
        lv_batch_size   TYPE i,
        lv_async_used   TYPE abap_bool,
        lv_issue        TYPE abap_bool,
        lv_done         TYPE i,
        lv_total        TYPE i.

  lv_saved_mode = p_bdc_mode.
  lv_saved_bg   = chkp_background.

  "Direct action always means CALL TRANSACTION. For display mode N the
  "actual CALL TRANSACTION is delegated to the generic RFC worker so screen
  "0500 remains available for live elapsed/phase updates. Modes A/E remain
  "in the dialog task because they intentionally show SAP transaction screens.
  p_bdc_mode         = gc_mode_call.
  CLEAR chkp_background.
  chkp_stop_on_error = 'X'.

  PERFORM get_runtime_options
    CHANGING lv_disp_mode lv_upd_mode lv_batch_size.

  CLEAR lv_async_used.
  IF lv_disp_mode = 'N'.
    "V5AV: ME21N uses SAPLMEGUI Control Framework. It must not run in the
    "RFC/no-display worker. z21_run_async_call_0500 will decline ME21N and
    "the normal dialog path below will run it in GUI-safe Display-errors-only.
    PERFORM z21_run_async_call_0500
      CHANGING lv_async_used.
  ENDIF.

  IF lv_async_used <> abap_true.
    PERFORM run_execution_monitor USING gc_mode_call.
  ENDIF.

  p_bdc_mode      = lv_saved_mode.
  chkp_background = lv_saved_bg.

  "The asynchronous N-mode path must return from PAI immediately. The GUI
  "timer drives later progress ticks and finalization; doing any final work
  "here would again block repaint until the worker has completed.
  IF lv_async_used = abap_true.
    MESSAGE 'Execution started in background worker. Live evidence will refresh every second.' TYPE 'S'.
    RETURN.
  ENDIF.

  PERFORM z16_after_0500_execute.
  PERFORM z16_count_0500_q CHANGING lv_done lv_total.
  PERFORM z16_has_0500_issue CHANGING lv_issue.

  "Remain in the monitor. The user can review the exact final queue and
  "choose Dashboard/Error Detail deliberately; no automatic navigation.
  IF lv_issue = abap_true.
    MESSAGE |Execution finished with issue(s): { lv_done }/{ lv_total } group(s). Use Error Detail or Fix Guide.| TYPE 'S' DISPLAY LIKE 'W'.
  ELSEIF lv_total > 0 AND lv_done >= lv_total.
    MESSAGE |Execution finished successfully: { lv_done }/{ lv_total } group(s).| TYPE 'S'.
  ELSE.
    MESSAGE |Execution returned with { lv_done }/{ lv_total } group(s) completed; READY groups remain.| TYPE 'S' DISPLAY LIKE 'W'.
  ENDIF.
ENDFORM.


*&---------------------------------------------------------------------*
*& V5AN - Generic asynchronous RFC worker for CALL TRANSACTION mode N
*&---------------------------------------------------------------------*
*<<< END FORM z16_execute_now_0500

*>>> FORM z21_async_bdc_finished - moved from Z_BDC_MASS_PO_ENTRY_F01_BUP
FORM z21_async_bdc_finished USING pv_taskname.
  CLEAR: gv_async_receive_rc, gv_async_system_msg.

  RECEIVE RESULTS FROM FUNCTION 'Z_BDC_EXEC_ONE_BUP'
    IMPORTING
      ev_subrc   = gv_async_subrc
      ev_message = gv_async_message
    TABLES
      et_bdcmsg  = gt_async_bdcmsg
    EXCEPTIONS
      communication_failure = 1
      system_failure        = 2
      OTHERS                = 3.

  gv_async_receive_rc = sy-subrc.
  IF gv_async_receive_rc <> 0 AND gv_async_message IS INITIAL.
    gv_async_message =
      |RFC result receive failed; rc={ gv_async_receive_rc }, task={ pv_taskname }.|.
  ENDIF.

  gv_async_done   = abap_true.
  gv_async_active = abap_false.
ENDFORM.
*<<< END FORM z21_async_bdc_finished

*>>> FORM z21_build_group_bdc - moved from Z_BDC_MASS_PO_ENTRY_F01_BUP

FORM z21_build_group_bdc
  USING    pv_tcode  TYPE sy-tcode
           pt_group  TYPE ty_t_staging_alv
           pt_s_pre  TYPE ty_t_script
           pt_s_item TYPE ty_t_script
           pt_s_post TYPE ty_t_script
           pt_map    TYPE ty_t_map
  CHANGING cv_ok     TYPE abap_bool
           cv_msg    TYPE string.

  DATA: ls_first  TYPE ty_staging_alv,
        ls_item   TYPE ty_staging_alv,
        ls_scr    TYPE zbdc_sct_def_bup,
        lv_idx    TYPE n LENGTH 2,
        lv_itemno TYPE i.

  CLEAR: cv_ok, cv_msg.
  READ TABLE pt_group INTO ls_first INDEX 1.
  IF sy-subrc <> 0.
    cv_msg = 'Cannot build BDCDATA: document group is empty.'.
    RETURN.
  ENDIF.

  REFRESH bdcdata.

  LOOP AT pt_s_pre INTO ls_scr.
    PERFORM append_script_step USING ls_scr ls_first pt_map '01'.
  ENDLOOP.

  CLEAR lv_itemno.
  LOOP AT pt_group INTO ls_item.
    lv_itemno = lv_itemno + 1.
    lv_idx = lv_itemno.
    LOOP AT pt_s_item INTO ls_scr.
      PERFORM append_script_step USING ls_scr ls_item pt_map lv_idx.
    ENDLOOP.
  ENDLOOP.

  LOOP AT pt_s_post INTO ls_scr.
    PERFORM append_script_step USING ls_scr ls_first pt_map '01'.
  ENDLOOP.

  DATA lv_rebuilt_me21n TYPE abap_bool.
  DATA lv_rebuild_msg   TYPE string.
  PERFORM z26_repair_me21n_bdc
    USING    pv_tcode pt_group pt_map
    CHANGING lv_rebuilt_me21n lv_rebuild_msg.

  IF bdcdata[] IS INITIAL.
    cv_msg =
      |BDCDATA is empty for group { ls_first-record_key }. Check recording and mapping.|.
    RETURN.
  ENDIF.

  cv_ok = abap_true.
ENDFORM.
*<<< END FORM z21_build_group_bdc

*>>> FORM z21_start_async_group - moved from Z_BDC_MASS_PO_ENTRY_F01_BUP

FORM z21_start_async_group
  USING    pv_tcode TYPE sy-tcode
           pv_upd   TYPE c
  CHANGING cv_ok    TYPE abap_bool
           cv_msg   TYPE string.

  CLEAR: cv_ok, cv_msg,
         gv_async_done, gv_async_receive_rc, gv_async_subrc,
         gv_async_message, gv_async_system_msg.
  REFRESH: gt_async_bdcdata, gt_async_bdcmsg.

  LOOP AT bdcdata.
    APPEND bdcdata TO gt_async_bdcdata.
  ENDLOOP.

  IF gt_async_bdcdata IS INITIAL.
    cv_msg = 'RFC worker was not started because BDCDATA is empty.'.
    RETURN.
  ENDIF.

  gv_async_tick = gv_async_tick + 1.
  gv_async_task = |ZBDC{ sy-uzeit }{ gv_async_tick }|.
  CONDENSE gv_async_task NO-GAPS.
  gv_async_active = abap_true.

  CALL FUNCTION 'Z_BDC_EXEC_ONE_BUP'
    STARTING NEW TASK gv_async_task
    DESTINATION 'NONE'
    PERFORMING z21_async_bdc_finished ON END OF TASK
    EXPORTING
      iv_tcode   = pv_tcode
      iv_updmode = pv_upd
    TABLES
      it_bdcdata = gt_async_bdcdata
      et_bdcmsg  = gt_async_bdcmsg
    EXCEPTIONS
      communication_failure = 1
      system_failure        = 2
      OTHERS                = 3.

  IF sy-subrc <> 0.
    gv_async_active     = abap_false.
    gv_async_done       = abap_true.
    gv_async_receive_rc = sy-subrc.
    cv_msg = |Could not start RFC BDC worker; sy-subrc={ sy-subrc }.|.
    gv_async_message = cv_msg.
    RETURN.
  ENDIF.

  cv_ok = abap_true.
ENDFORM.
*<<< END FORM z21_start_async_group

*>>> FORM z21_copy_async_messages - moved from Z_BDC_MASS_PO_ENTRY_F01_BUP


FORM z21_copy_async_messages.
  REFRESH messtab.
  LOOP AT gt_async_bdcmsg INTO DATA(ls_async_msg).
    APPEND ls_async_msg TO messtab.
  ENDLOOP.
ENDFORM.







*&---------------------------------------------------------------------*
*& V5AQ - Stable runtime queue state for every selected group
*&---------------------------------------------------------------------*
*<<< END FORM z21_copy_async_messages

*>>> FORM z24_async_q_init - moved from Z_BDC_MASS_PO_ENTRY_F01_BUP
FORM z24_async_q_init.
  DATA: ls_key   TYPE ty_engine_group_key,
        ls_state TYPE ty_async_qstate.

  REFRESH gt_async_qstate.
  LOOP AT gt_async_keys INTO ls_key.
    CLEAR ls_state.
    ls_state-session_id = ls_key-session_id.
    ls_state-record_key = ls_key-record_key.
    ls_state-row_index  = ls_key-row_index.
    ls_state-seq_no     = sy-tabix.
    ls_state-state      = 'QUEUED'.
    ls_state-message    = 'Selected and waiting for its turn.'.
    APPEND ls_state TO gt_async_qstate.
  ENDLOOP.
ENDFORM.
*<<< END FORM z24_async_q_init

*>>> FORM z24_async_q_set - moved from Z_BDC_MASS_PO_ENTRY_F01_BUP

FORM z24_async_q_set
  USING    ps_key   TYPE ty_engine_group_key
           pv_state TYPE csequence
           pv_msg   TYPE csequence
           pv_obj   TYPE zbdc_result_bup-sap_object_id.

  FIELD-SYMBOLS <ls_state> TYPE ty_async_qstate.

  READ TABLE gt_async_qstate ASSIGNING <ls_state>
    WITH KEY session_id = ps_key-session_id
             record_key = ps_key-record_key
             row_index  = ps_key-row_index.
  IF sy-subrc <> 0.
    APPEND INITIAL LINE TO gt_async_qstate ASSIGNING <ls_state>.
    <ls_state>-session_id = ps_key-session_id.
    <ls_state>-record_key = ps_key-record_key.
    <ls_state>-row_index  = ps_key-row_index.
    <ls_state>-seq_no     = gv_async_key_index.
  ENDIF.

  <ls_state>-state      = pv_state.
  <ls_state>-message    = pv_msg.
  <ls_state>-sap_object = pv_obj.
ENDFORM.
*<<< END FORM z24_async_q_set

*>>> FORM z24_q_init_proc - moved from Z_BDC_MASS_PO_ENTRY_F01_BUP

FORM z24_q_init_proc
  USING    pt_process TYPE ty_t_staging_alv
           pv_state   TYPE csequence
           pv_msg     TYPE csequence.

  DATA: lt_keys  TYPE ty_t_engine_group_key,
        ls_key   TYPE ty_engine_group_key,
        ls_state TYPE ty_async_qstate.

  REFRESH gt_async_qstate.
  PERFORM z17_build_engine_keys
    USING    pt_process
    CHANGING lt_keys.

  LOOP AT lt_keys INTO ls_key.
    CLEAR ls_state.
    ls_state-session_id = ls_key-session_id.
    ls_state-record_key = ls_key-record_key.
    ls_state-row_index  = ls_key-row_index.
    ls_state-seq_no     = sy-tabix.
    ls_state-state      = pv_state.
    ls_state-message    = pv_msg.
    APPEND ls_state TO gt_async_qstate.
  ENDLOOP.
ENDFORM.
*<<< END FORM z24_q_init_proc

*>>> FORM z24_q_set_all - moved from Z_BDC_MASS_PO_ENTRY_F01_BUP

FORM z24_q_set_all
  USING pv_state TYPE csequence
        pv_msg   TYPE csequence.

  LOOP AT gt_async_qstate ASSIGNING FIELD-SYMBOL(<ls_q_all>).
    <ls_q_all>-state   = pv_state.
    <ls_q_all>-message = pv_msg.
  ENDLOOP.
ENDFORM.
*<<< END FORM z24_q_set_all

*>>> FORM z16_build_0500_from_q - moved from Z_BDC_MASS_PO_ENTRY_F01_BUP

FORM z16_build_0500_from_q.
  DATA: lt_src       TYPE ty_t_staging_alv,
        ls_state     TYPE ty_async_qstate,
        ls_src       TYPE ty_staging_alv,
        ls_first     TYPE ty_staging_alv,
        ls_exec      TYPE ty_exec_disp,
        lv_state_key TYPE char40,
        lv_src_key   TYPE char40,
        lv_unit_raw  TYPE string,
        lv_item_cnt  TYPE i.

  REFRESH gt_exec_disp.

  APPEND LINES OF gt_exec_scope_0500   TO lt_src.
  APPEND LINES OF gt_sm35_mon_process  TO lt_src.
  APPEND LINES OF gt_fb_queue          TO lt_src.
  APPEND LINES OF gt_async_process     TO lt_src.
  IF lt_src IS INITIAL.
    APPEND LINES OF gt_staging_alv TO lt_src.
  ENDIF.

  SORT gt_async_qstate BY seq_no.
  LOOP AT gt_async_qstate INTO ls_state.
    CLEAR: ls_exec, ls_first, lv_item_cnt, lv_state_key.

    lv_state_key = ls_state-record_key.
    IF lv_state_key IS INITIAL AND ls_state-row_index IS NOT INITIAL.
      WRITE ls_state-row_index TO lv_state_key LEFT-JUSTIFIED.
      CONDENSE lv_state_key NO-GAPS.
    ENDIF.

    LOOP AT lt_src INTO ls_src.
      IF ls_src-session_id <> ls_state-session_id.
        CONTINUE.
      ENDIF.
      CLEAR lv_src_key.
      lv_src_key = ls_src-record_key.
      IF lv_src_key IS INITIAL AND ls_src-row_index IS NOT INITIAL.
        WRITE ls_src-row_index TO lv_src_key LEFT-JUSTIFIED.
        CONDENSE lv_src_key NO-GAPS.
      ENDIF.
      IF lv_src_key <> lv_state_key.
        CONTINUE.
      ENDIF.
      IF lv_item_cnt = 0.
        ls_first = ls_src.
      ENDIF.
      lv_item_cnt = lv_item_cnt + 1.
    ENDLOOP.

    PERFORM z16_batch_prefix_from_sid
      USING ls_state-session_id
      CHANGING ls_exec-batch_key.

    CLEAR lv_unit_raw.
    SELECT SINGLE file_name FROM zbdc_file_lg_bup
      WHERE session_id = @ls_state-session_id
      INTO @lv_unit_raw.
    IF lv_unit_raw IS INITIAL.
      lv_unit_raw = ls_state-session_id.
    ENDIF.
    PERFORM z16_split_unit_name
      USING lv_unit_raw
      CHANGING ls_exec-source_file ls_exec-sheet_name.

    ls_exec-session_id = ls_state-session_id.
    ls_exec-group_key  = lv_state_key.
    ls_exec-tcode      = ls_first-tcode.
    IF ls_exec-tcode IS INITIAL.
      ls_exec-tcode = p_transaction.
    ENDIF.
    ls_exec-item_count = lv_item_cnt.
    IF ls_exec-item_count <= 0.
      ls_exec-item_count = 1.
    ENDIF.
    ls_exec-run_status  = gc_st_ready.
    ls_exec-msg_type    = 'I'.
    ls_exec-icon        = '@09@'.
    ls_exec-message     = ls_state-message.
    ls_exec-drill_tcode = 'DISPLAY'.
    APPEND ls_exec TO gt_exec_disp.
  ENDLOOP.

  PERFORM z24_async_q_overlay.
ENDFORM.
*<<< END FORM z16_build_0500_from_q

*>>> FORM z24_async_q_overlay - moved from Z_BDC_MASS_PO_ENTRY_F01_BUP

FORM z24_async_q_overlay.
  DATA: ls_state   TYPE ty_async_qstate,
        lv_found   TYPE abap_bool,
        lv_row_key TYPE char40.

  IF gt_async_qstate IS INITIAL.
    RETURN.
  ENDIF.

  LOOP AT gt_exec_disp ASSIGNING FIELD-SYMBOL(<ls_exec_q>).
    CLEAR: ls_state, lv_found.

    LOOP AT gt_async_qstate INTO ls_state
      WHERE session_id = <ls_exec_q>-session_id.
      CLEAR lv_row_key.
      IF ls_state-row_index IS NOT INITIAL.
        WRITE ls_state-row_index TO lv_row_key LEFT-JUSTIFIED.
        CONDENSE lv_row_key NO-GAPS.
      ENDIF.
      IF ( ls_state-record_key IS NOT INITIAL AND
           ls_state-record_key = <ls_exec_q>-group_key ) OR
         ( ls_state-record_key IS INITIAL AND
           lv_row_key IS NOT INITIAL AND
           <ls_exec_q>-group_key = lv_row_key ).
        lv_found = abap_true.
        EXIT.
      ENDIF.
    ENDLOOP.

    IF lv_found <> abap_true.
      CONTINUE.
    ENDIF.

    CASE ls_state-state.
      WHEN 'QUEUED'.
        <ls_exec_q>-icon        = '@09@'.
        <ls_exec_q>-msg_type    = 'I'.
        <ls_exec_q>-run_status  = 'QUEUED'.
        <ls_exec_q>-health_text = 'Waiting in selected queue'.
        <ls_exec_q>-action_hint = 'Starts automatically after the active group'.
        <ls_exec_q>-message     = ls_state-message.
      WHEN 'PROCESSING'.
        <ls_exec_q>-icon        = '@09@'.
        <ls_exec_q>-msg_type    = 'I'.
        <ls_exec_q>-run_status  = 'PROCESSING'.
        <ls_exec_q>-health_text = 'Running SAP transaction'.
        <ls_exec_q>-action_hint = 'Wait for the RFC worker result'.
        <ls_exec_q>-message     = ls_state-message.
      WHEN 'VERIFYING'.
        <ls_exec_q>-icon        = '@09@'.
        <ls_exec_q>-msg_type    = 'I'.
        <ls_exec_q>-run_status  = 'VERIFYING'.
        <ls_exec_q>-health_text = 'Verifying SAP document'.
        <ls_exec_q>-action_hint = 'Wait for database proof'.
        <ls_exec_q>-message     = ls_state-message.
      WHEN 'SM35RUN'.
        <ls_exec_q>-icon        = '@09@'.
        <ls_exec_q>-msg_type    = 'I'.
        <ls_exec_q>-run_status  = 'SM35RUN'.
        <ls_exec_q>-health_text = 'SM35 batch processing'.
        <ls_exec_q>-action_hint = 'Wait; auto monitor/fallback is active'.
        <ls_exec_q>-message     = ls_state-message.
      WHEN 'FALLBACK'.
        <ls_exec_q>-icon        = '@09@'.
        <ls_exec_q>-msg_type    = 'I'.
        <ls_exec_q>-run_status  = 'FALLBACK'.
        <ls_exec_q>-health_text = 'GUI fallback running'.
        <ls_exec_q>-action_hint = 'Wait for CALL TRANSACTION E result'.
        <ls_exec_q>-message     = ls_state-message.
      WHEN 'SUCCESS'.
        <ls_exec_q>-icon          = '@08@'.
        <ls_exec_q>-msg_type      = 'S'.
        <ls_exec_q>-run_status    = gc_st_success.
        <ls_exec_q>-health_text   = 'SAP document created'.
        <ls_exec_q>-action_hint   = 'Review SAP Object or Dashboard'.
        <ls_exec_q>-message       = ls_state-message.
        IF ls_state-sap_object IS NOT INITIAL.
          <ls_exec_q>-sap_object_id = ls_state-sap_object.
        ENDIF.
      WHEN 'ERROR'.
        <ls_exec_q>-icon        = '@0A@'.
        <ls_exec_q>-msg_type    = 'E'.
        <ls_exec_q>-run_status  = gc_st_error.
        <ls_exec_q>-health_text = 'BDC execution failed'.
        <ls_exec_q>-action_hint = 'Open Error Detail or Fix Guide'.
        <ls_exec_q>-message     = ls_state-message.
      WHEN 'STOPPED'.
        <ls_exec_q>-icon        = '@0A@'.
        <ls_exec_q>-msg_type    = 'W'.
        <ls_exec_q>-run_status  = 'SKIPPED'.
        <ls_exec_q>-health_text = 'Not started'.
        <ls_exec_q>-action_hint = 'Run again when ready'.
        <ls_exec_q>-message     = ls_state-message.
    ENDCASE.
  ENDLOOP.
ENDFORM.

*&---------------------------------------------------------------------*
*& V5AS - Evidence-only non-blocking 0500 timer/state machine
*&---------------------------------------------------------------------*
*<<< END FORM z24_async_q_overlay

*>>> FORM z22_start_0500_timer - moved from Z_BDC_MASS_PO_ENTRY_F01_BUP
FORM z22_start_0500_timer.
  TRY.
      IF go_timer_0500 IS NOT BOUND.
        CREATE OBJECT go_timer_0500.
      ENDIF.
      IF go_timer_hdl_0500 IS NOT BOUND.
        CREATE OBJECT go_timer_hdl_0500.
        SET HANDLER go_timer_hdl_0500->on_finished FOR go_timer_0500.
      ENDIF.
      IF gv_timer_0500_sec <= 0.
        gv_timer_0500_sec = 1.
      ENDIF.
      go_timer_0500->interval = gv_timer_0500_sec.
      gv_timer_0500_on = abap_true.
      go_timer_0500->run( ).
    CATCH cx_root.
      CLEAR gv_timer_0500_on.
  ENDTRY.
ENDFORM.
*<<< END FORM z22_start_0500_timer

*>>> FORM z22_stop_0500_timer - moved from Z_BDC_MASS_PO_ENTRY_F01_BUP

FORM z22_stop_0500_timer.
  CLEAR gv_timer_0500_on.
  IF go_timer_0500 IS BOUND.
    TRY.
        go_timer_0500->cancel( ).
      CATCH cx_root.
    ENDTRY.
    FREE go_timer_0500.
  ENDIF.
  FREE go_timer_hdl_0500.
ENDFORM.
*<<< END FORM z22_stop_0500_timer

*>>> FORM z23_refresh_0500_tools - moved from Z_BDC_MASS_PO_ENTRY_F01_BUP

FORM z23_refresh_0500_tools.
  IF go_grid_0500 IS BOUND.
    TRY.
        CALL METHOD go_grid_0500->set_toolbar_interactive.
        CALL METHOD cl_gui_cfw=>flush.
      CATCH cx_root.
    ENDTRY.
  ENDIF.
ENDFORM.
*<<< END FORM z23_refresh_0500_tools

*>>> FORM z22_live_elapsed - moved from Z_BDC_MASS_PO_ENTRY_F01_BUP

FORM z22_live_elapsed CHANGING cv_elapsed_ms TYPE i.
  DATA lv_now TYPE i.
  GET RUN TIME FIELD lv_now.
  cv_elapsed_ms = lv_now - gv_async_run_start.
  IF cv_elapsed_ms < 0.
    cv_elapsed_ms = 0.
  ENDIF.
  cv_elapsed_ms = cv_elapsed_ms / 1000.
  gv_exec_elapsed = cv_elapsed_ms.
ENDFORM.
*<<< END FORM z22_live_elapsed

*>>> FORM z22_async_start_next - moved from Z_BDC_MASS_PO_ENTRY_F01_BUP

FORM z22_async_start_next.
  DATA: ls_key       TYPE ty_engine_group_key,
        ls_first     TYPE ty_staging_alv,
        lt_group     TYPE ty_t_staging_alv,
        lt_s_pre     TYPE ty_t_script,
        lt_s_item    TYPE ty_t_script,
        lt_s_post    TYPE ty_t_script,
        lt_map       TYPE ty_t_map,
        lv_tcode     TYPE sy-tcode,
        lv_build_ok  TYPE abap_bool,
        lv_start_ok  TYPE abap_bool,
        lv_msg       TYPE string,
        lv_elapsed   TYPE i.

  DO.
    IF gv_exec_stop_req = abap_true OR g_stop_flag = 'X'.
      LOOP AT gt_async_qstate ASSIGNING FIELD-SYMBOL(<ls_stop>)
        WHERE state = 'QUEUED'.
        <ls_stop>-state   = 'STOPPED'.
        <ls_stop>-message = 'Queue stopped by user before this group started.'.
      ENDLOOP.
      PERFORM z22_async_finish_run.
      RETURN.
    ENDIF.

    IF gv_async_key_index >= gv_async_total.
      PERFORM z22_async_finish_run.
      RETURN.
    ENDIF.

    gv_async_key_index = gv_async_key_index + 1.
    READ TABLE gt_async_keys INTO ls_key INDEX gv_async_key_index.
    IF sy-subrc <> 0.
      gv_async_any_error = abap_true.
      gv_exec_run_done = gv_exec_run_done + 1.
      CONTINUE.
    ENDIF.

    REFRESH lt_group.
    PERFORM z17_collect_group_key
      USING    gt_async_process ls_key
      CHANGING lt_group.
    READ TABLE lt_group INTO ls_first INDEX 1.
    IF sy-subrc <> 0.
      lv_msg = |Selected group { gv_async_key_index } could not be reconstructed.|.
      PERFORM z24_async_q_set
        USING ls_key 'ERROR' lv_msg ''.
      gv_async_any_error = abap_true.
      gv_exec_run_done = gv_exec_run_done + 1.
      CONTINUE.
    ENDIF.

    lv_tcode = ls_first-tcode.
    IF lv_tcode IS INITIAL.
      lv_tcode = p_transaction.
    ENDIF.
    gv_async_tcode      = lv_tcode.
    gv_async_session_id = ls_first-session_id.
    gv_async_group_key  = ls_first-record_key.
    IF gv_async_group_key IS INITIAL.
      gv_async_group_key = ls_first-row_index.
    ENDIF.
    gt_async_group[] = lt_group[].

    REFRESH: lt_s_pre, lt_s_item, lt_s_post, lt_map.
    PERFORM load_script_definition
      USING    lv_tcode
      CHANGING lt_s_pre lt_s_item lt_s_post.
    PERFORM load_mapping_profile
      USING    lv_tcode
      CHANGING lt_map.

    IF ( lt_s_pre IS INITIAL AND lt_s_item IS INITIAL AND
         lt_s_post IS INITIAL ) OR lt_map IS INITIAL.
      lv_msg = |Missing script or mapping profile for { lv_tcode }.|.
      PERFORM save_synthetic_engine_log
        USING lt_group lv_tcode 0 gc_st_error lv_msg '' ''.
      PERFORM update_group_result
        USING lt_group gc_st_error lv_msg ''.
      PERFORM update_exec_counters USING lt_group abap_false.
      PERFORM z24_async_q_set
        USING ls_key 'ERROR' lv_msg ''.
      gv_async_any_error = abap_true.
      gv_exec_run_done = gv_exec_run_done + 1.
      CONTINUE.
    ENDIF.

    CLEAR: lv_build_ok, lv_msg.
    PERFORM z21_build_group_bdc
      USING lv_tcode lt_group lt_s_pre lt_s_item lt_s_post lt_map
      CHANGING lv_build_ok lv_msg.
    IF lv_build_ok <> abap_true.
      PERFORM save_synthetic_engine_log
        USING lt_group lv_tcode 0 gc_st_error lv_msg '' ''.
      PERFORM update_group_result
        USING lt_group gc_st_error lv_msg ''.
      PERFORM update_exec_counters USING lt_group abap_false.
      PERFORM z24_async_q_set
        USING ls_key 'ERROR' lv_msg ''.
      gv_async_any_error = abap_true.
      gv_exec_run_done = gv_exec_run_done + 1.
      CONTINUE.
    ENDIF.

    gv_async_attempt = 1.
    gv_async_max_try = 1.
    IF chkp_retry = 'X' AND gv_async_updmode = 'S'.
      gv_async_max_try = gc_max_attempts.
    ENDIF.

    gv_exec_mon_kind = 'C'.
    gv_exec_run_phase =
      |Processing { gv_async_key_index }/{ gv_async_total }: { lv_tcode } { gv_async_group_key }|.
    lv_msg =
      |Running selected group { gv_async_key_index }/{ gv_async_total }: { gv_async_group_key }.|.
    PERFORM z24_async_q_set
      USING ls_key 'PROCESSING' lv_msg ''.

    CLEAR: lv_start_ok, lv_msg.
    PERFORM z21_start_async_group
      USING    lv_tcode gv_async_updmode
      CHANGING lv_start_ok lv_msg.
    IF lv_start_ok <> abap_true.
      PERFORM save_synthetic_engine_log
        USING lt_group lv_tcode gv_async_attempt gc_st_error lv_msg '' ''.
      PERFORM update_group_result
        USING lt_group gc_st_error lv_msg ''.
      PERFORM update_exec_counters USING lt_group abap_false.
      PERFORM z24_async_q_set
        USING ls_key 'ERROR' lv_msg ''.
      gv_async_any_error = abap_true.
      gv_exec_run_done = gv_exec_run_done + 1.
      CONTINUE.
    ENDIF.

    IF gv_timer_0500_on <> abap_true.
      PERFORM z22_start_0500_timer.
    ENDIF.
    PERFORM z16_display_0500_queue.
    PERFORM z22_live_elapsed CHANGING lv_elapsed.
    PERFORM z16_set_0500_progress
      USING gv_exec_run_done gv_async_total lv_elapsed.
    RETURN.
  ENDDO.
ENDFORM.
*<<< END FORM z22_async_start_next

*>>> FORM z22_verify_current_obj - moved from Z_BDC_MASS_PO_ENTRY_F01_BUP

FORM z22_verify_current_obj
  USING    pv_tcode TYPE sy-tcode
           pv_obj   TYPE zbdc_result_bup-sap_object_id
  CHANGING cv_ok    TYPE abap_bool.

  DATA: lv_ebeln TYPE ekko-ebeln,
        lv_mblnr TYPE mkpf-mblnr.
  CLEAR cv_ok.
  IF pv_obj IS INITIAL.
    RETURN.
  ENDIF.

  CASE pv_tcode.
    WHEN 'ME21N'.
      SELECT SINGLE ebeln FROM ekko INTO @lv_ebeln
        WHERE ebeln = @pv_obj.
      IF sy-subrc = 0 AND lv_ebeln IS NOT INITIAL.
        cv_ok = abap_true.
      ENDIF.
    WHEN 'MIGO'.
      SELECT SINGLE mblnr FROM mkpf INTO @lv_mblnr
        WHERE mblnr = @pv_obj.
      IF sy-subrc = 0 AND lv_mblnr IS NOT INITIAL.
        cv_ok = abap_true.
      ENDIF.
    WHEN OTHERS.
      cv_ok = abap_true.
  ENDCASE.
ENDFORM.
*<<< END FORM z22_verify_current_obj

*>>> FORM z22_async_finalize_current - moved from Z_BDC_MASS_PO_ENTRY_F01_BUP

FORM z22_async_finalize_current.
  DATA: lv_success      TYPE abap_bool,
        lv_verified     TYPE abap_bool,
        lv_retryable    TYPE abap_bool,
        lv_retry_reason TYPE string,
        lv_obj          TYPE zbdc_result_bup-sap_object_id,
        lv_msg          TYPE string,
        lv_start_ok     TYPE abap_bool,
        ls_key          TYPE ty_engine_group_key.

  READ TABLE gt_async_keys INTO ls_key INDEX gv_async_key_index.

  PERFORM z21_copy_async_messages.
  CLEAR: lv_success, lv_verified, lv_obj.
  PERFORM extract_document_number
    USING    gv_async_tcode
    CHANGING lv_success lv_obj.

  PERFORM save_bdc_message_logs
    USING gt_async_group gv_async_tcode gv_async_attempt lv_obj.

  IF lv_success = abap_true AND
     gv_async_receive_rc = 0 AND gv_async_subrc = 0.
    PERFORM z22_verify_current_obj
      USING gv_async_tcode lv_obj
      CHANGING lv_verified.
  ENDIF.

  IF lv_success = abap_true AND lv_verified = abap_true.
    lv_msg = |SAP object { lv_obj } created and verified.|.
    PERFORM update_group_result
      USING gt_async_group gc_st_success lv_msg lv_obj.
    PERFORM update_exec_counters USING gt_async_group abap_true.
    PERFORM z24_async_q_set
      USING ls_key 'SUCCESS' lv_msg lv_obj.
  ELSE.
    CLEAR: lv_retryable, lv_retry_reason.
    PERFORM z17_is_transient_bdc
      CHANGING lv_retryable lv_retry_reason.

    IF lv_retryable = abap_true AND
       gv_async_attempt < gv_async_max_try AND
       gv_exec_stop_req <> abap_true.
      gv_async_attempt = gv_async_attempt + 1.
      gv_exec_run_phase =
        |Retry { gv_async_attempt }/{ gv_async_max_try }: { lv_retry_reason }|.
      lv_msg =
        |Retrying group { gv_async_key_index }/{ gv_async_total }: { lv_retry_reason }.|.
      PERFORM z24_async_q_set
        USING ls_key 'PROCESSING' lv_msg ''.
      CLEAR: lv_start_ok, lv_msg.
      REFRESH bdcdata.
      LOOP AT gt_async_bdcdata INTO DATA(ls_retry_bdc).
        APPEND ls_retry_bdc TO bdcdata.
      ENDLOOP.
      PERFORM z21_start_async_group
        USING gv_async_tcode gv_async_updmode
        CHANGING lv_start_ok lv_msg.
      IF lv_start_ok = abap_true.
        PERFORM z16_display_0500_queue.
        RETURN.
      ENDIF.
    ENDIF.

    CLEAR lv_msg.
    PERFORM build_error_text CHANGING lv_msg.
    IF lv_msg IS INITIAL OR lv_msg CS 'MESSTAB rong'.
      lv_msg = gv_async_message.
    ENDIF.
    IF lv_msg IS INITIAL.
      lv_msg = |RFC worker failed; worker rc={ gv_async_subrc }, receive rc={ gv_async_receive_rc }.|.
    ENDIF.
    PERFORM update_group_result
      USING gt_async_group gc_st_error lv_msg ''.
    PERFORM update_exec_counters USING gt_async_group abap_false.
    PERFORM z24_async_q_set
      USING ls_key 'ERROR' lv_msg ''.
    gv_async_any_error = abap_true.
  ENDIF.

  gv_exec_run_done = gv_exec_run_done + 1.
  g_exec_curr       = gv_exec_run_done.
  CLEAR: gv_async_done, gv_async_active.
  COMMIT WORK AND WAIT.

  "Start the next selected group immediately from the callback roundtrip.
  "Do not rebuild the ALV between groups; that caused a READY flash and made
  "the queue appear stuck after the first document.
  gv_exec_mon_kind = 'C'.
  PERFORM z22_async_start_next.
ENDFORM.
*<<< END FORM z22_async_finalize_current

*>>> FORM z22_async_finish_run - moved from Z_BDC_MASS_PO_ENTRY_F01_BUP

FORM z22_async_finish_run.
  DATA: lt_sid    TYPE STANDARD TABLE OF zbdc_staging_bup-session_id,
        lv_sid    TYPE zbdc_staging_bup-session_id,
        lv_elapsed TYPE i.

  PERFORM z22_stop_0500_timer.
  gv_exec_run_active = abap_false.
  CLEAR: gv_async_active, gv_async_done, gv_exec_mon_kind.
  PERFORM z23_refresh_0500_tools.
  GET TIME STAMP FIELD gv_exec_end_ts.
  PERFORM z22_live_elapsed CHANGING lv_elapsed.

  COMMIT WORK AND WAIT.
  LOOP AT gt_async_process INTO DATA(ls_sum).
    READ TABLE lt_sid WITH KEY table_line = ls_sum-session_id
      TRANSPORTING NO FIELDS.
    IF sy-subrc <> 0.
      APPEND ls_sum-session_id TO lt_sid.
    ENDIF.
  ENDLOOP.
  LOOP AT lt_sid INTO lv_sid.
    PERFORM update_session_summary USING lv_sid.
  ENDLOOP.

  IF gv_async_lock_on = abap_true AND gv_async_lock_sid IS NOT INITIAL.
    PERFORM release_staging_lock USING gv_async_lock_sid.
  ENDIF.
  CLEAR: gv_async_lock_on, gv_async_lock_sid.

  IF gv_async_any_error = abap_true.
    gv_exec_run_phase = 'Completed with issue(s)'.
  ELSE.
    gv_exec_run_phase = 'Completed successfully'.
  ENDIF.
  PERFORM z16_after_0500_execute.
  PERFORM prepare_alv_0400.
  PERFORM build_exec_cockpit.
  PERFORM z16_display_0500_queue.
  PERFORM z16_set_0500_progress
    USING gv_exec_run_done gv_async_total lv_elapsed.

  IF gv_async_any_error = abap_true.
    MESSAGE |Execution finished with issue(s): { gv_exec_run_done }/{ gv_async_total }.| TYPE 'S' DISPLAY LIKE 'W'.
  ELSE.
    MESSAGE |Execution finished successfully: { gv_exec_run_done }/{ gv_async_total } group(s).| TYPE 'S'.
  ENDIF.
ENDFORM.

*&---------------------------------------------------------------------*
*& V5BA - Automatic SM35 N fallback with ME21N no-proof guard
*& The original Batch Input Session remains the audit source. A direct
*& mode-E retry is allowed for groups whose real SM35 protocol contains
*& a Control Framework / GUI-not-reachable error, or for ME21N groups that
*& finish SM35 N without any verified PO proof. Business errors are not retried.
*&---------------------------------------------------------------------*
*<<< END FORM z22_async_finish_run

*>>> FORM z28_collect_sm35_gui_fallback - moved from Z_BDC_MASS_PO_ENTRY_F01_BUP

FORM z28_collect_sm35_gui_fallback
  USING    pt_process  TYPE ty_t_staging_alv
  CHANGING ct_fallback TYPE ty_t_staging_alv
           cv_groups   TYPE i.

  DATA: lt_sorted      TYPE ty_t_staging_alv,
        lt_group       TYPE ty_t_staging_alv,
        ls_row         TYPE ty_staging_alv,
        ls_fb_first    TYPE ty_staging_alv,
        lv_prev_sid    TYPE zbdc_staging_bup-session_id,
        lv_prev_key    TYPE zbdc_staging_bup-record_key,
        lv_curr_key    TYPE zbdc_staging_bup-record_key,
        lv_gui_error   TYPE abap_bool,
        lv_success     TYPE abap_bool,
        lv_error       TYPE abap_bool,
        lv_object      TYPE zbdc_result_bup-sap_object_id,
        lv_summary     TYPE string,
        lv_reason      TYPE string,
        lv_need_auto  TYPE abap_bool,
        lv_auto_reason TYPE string.

  CLEAR cv_groups.
  REFRESH ct_fallback.
  lt_sorted = pt_process.
  SORT lt_sorted BY session_id record_key row_index.

  LOOP AT lt_sorted INTO ls_row.
    lv_curr_key = ls_row-record_key.
    IF lv_curr_key IS INITIAL.
      lv_curr_key = ls_row-row_index.
    ENDIF.

    IF lt_group IS NOT INITIAL AND
       ( ls_row-session_id <> lv_prev_sid OR lv_curr_key <> lv_prev_key ).
      CLEAR: lv_gui_error, lv_success, lv_error, lv_object,
             lv_summary, lv_reason.
      PERFORM z20_group_sm35_proof
        USING    lt_group
        CHANGING lv_success lv_error lv_object lv_summary.
      PERFORM z28_group_gui_control_error
        USING    lt_group
        CHANGING lv_gui_error lv_reason.
      CLEAR: lv_need_auto, lv_auto_reason.
      PERFORM z28_needs_me21n_fallback
        USING    lt_group lv_success lv_error lv_object
        CHANGING lv_need_auto lv_auto_reason.
      IF lv_gui_error = abap_true AND
         lv_object IS INITIAL.
        APPEND LINES OF lt_group TO ct_fallback.
        cv_groups = cv_groups + 1.
      ELSEIF lv_need_auto = abap_true.
        CLEAR ls_fb_first.
        READ TABLE lt_group INTO ls_fb_first INDEX 1.
        PERFORM save_synthetic_engine_log
          USING lt_group ls_fb_first-tcode 1 gc_st_warning
                lv_auto_reason '' 'X'.
        APPEND LINES OF lt_group TO ct_fallback.
        cv_groups = cv_groups + 1.
      ENDIF.
      CLEAR lt_group.
    ENDIF.

    APPEND ls_row TO lt_group.
    lv_prev_sid = ls_row-session_id.
    lv_prev_key = lv_curr_key.
  ENDLOOP.

  IF lt_group IS NOT INITIAL.
    CLEAR: lv_gui_error, lv_success, lv_error, lv_object,
           lv_summary, lv_reason.
    PERFORM z20_group_sm35_proof
      USING    lt_group
      CHANGING lv_success lv_error lv_object lv_summary.
    PERFORM z28_group_gui_control_error
      USING    lt_group
      CHANGING lv_gui_error lv_reason.
    CLEAR: lv_need_auto, lv_auto_reason.
    PERFORM z28_needs_me21n_fallback
      USING    lt_group lv_success lv_error lv_object
      CHANGING lv_need_auto lv_auto_reason.
    IF lv_gui_error = abap_true AND
       lv_object IS INITIAL.
      APPEND LINES OF lt_group TO ct_fallback.
      cv_groups = cv_groups + 1.
    ELSEIF lv_need_auto = abap_true.
      CLEAR ls_fb_first.
      READ TABLE lt_group INTO ls_fb_first INDEX 1.
      PERFORM save_synthetic_engine_log
        USING lt_group ls_fb_first-tcode 1 gc_st_warning
              lv_auto_reason '' 'X'.
      APPEND LINES OF lt_group TO ct_fallback.
      cv_groups = cv_groups + 1.
    ENDIF.
  ENDIF.
ENDFORM.
*<<< END FORM z28_collect_sm35_gui_fallback

*>>> FORM z28_run_sm35_gui_fallback - moved from Z_BDC_MASS_PO_ENTRY_F01_BUP

FORM z28_run_sm35_gui_fallback
  USING    pt_process TYPE ty_t_staging_alv
           pv_group   TYPE apqi-groupid
  CHANGING cv_started TYPE abap_bool
           cv_message TYPE string
           cv_done    TYPE i
           cv_error   TYPE i.

  DATA: lt_fallback TYPE ty_t_staging_alv,
        lv_groups   TYPE i,
        lv_elapsed  TYPE i,
        lv_qmsg     TYPE string.

  CLEAR: cv_started, cv_message, cv_done, cv_error.

  "V5BE: initialize a GUI timer/chunk runner instead of looping through all
  "fallback groups in one PAI.  A CALL TRANSACTION is still synchronous while
  "one PO_KEY is being created, but the screen returns to 0500 between groups:
  "0/n -> 1/n -> 2/n ... with repaint, ETA and SAP object proof after each.
  PERFORM z28_collect_sm35_gui_fallback
    USING    pt_process
    CHANGING lt_fallback lv_groups.
  IF lv_groups <= 0 OR lt_fallback IS INITIAL.
    RETURN.
  ENDIF.

  REFRESH: gt_fb_process, gt_fb_queue, gt_fb_keys.
  gt_fb_process[] = pt_process[].
  gt_fb_queue[]   = lt_fallback[].
  gt_exec_scope_0500[] = lt_fallback[].
  lv_qmsg = 'SM35 N finished without PO proof; automatic GUI fallback is queued.'.
  PERFORM z24_q_init_proc
    USING lt_fallback 'QUEUED' lv_qmsg.
  gv_fb_group     = pv_group.
  gv_fb_idx       = 0.
  gv_fb_total     = lv_groups.
  CLEAR: gv_fb_done, gv_fb_error.

  PERFORM z17_build_engine_keys
    USING    gt_fb_queue
    CHANGING gt_fb_keys.
  IF gt_fb_keys IS INITIAL.
    RETURN.
  ENDIF.

  gv_fb_saved_mode  = p_bdc_mode.
  gv_fb_saved_bg    = chkp_background.
  gv_fb_saved_stop  = chkp_stop_on_error.
  gv_fb_saved_ovr_m = gv_runtime_mode_override.
  gv_fb_saved_ovr_u = gv_runtime_upd_override.

  p_bdc_mode               = gc_mode_call.
  CLEAR chkp_background.
  "Keep the monitor-wide error policy during automatic fallback. Clearing
  "this flag made the fallback timer continue to CALL TRANSACTION for the
  "next PO_KEY even after the current fallback group failed.
  chkp_stop_on_error       = 'X'.
  gv_runtime_mode_override = 'E'.
  gv_runtime_upd_override  = gv_last_sm35_policy.
  IF gv_runtime_upd_override <> 'S' AND
     gv_runtime_upd_override <> 'A'.
    gv_runtime_upd_override = 'S'.
  ENDIF.

  cv_started = abap_true.
  gv_sm35_fallback_active = abap_true.
  gv_sm35_fallback_groups = lv_groups.
  CLEAR: gv_sm35_fallback_done, gv_sm35_fallback_error.
  gv_exec_mon_kind   = 'F'.
  gv_exec_run_engine = 'F'.
  gv_exec_run_active = abap_true.
  gv_exec_run_done   = 0.
  gv_exec_run_total  = lv_groups.
  gv_exec_run_phase  = |SM35 fallback queued 0/{ lv_groups }; first PO_KEY will run on the next timer tick.|.
  gv_sm35_fallback_text =
    |SM35 { pv_group } needs automatic mode-E fallback. Timer/chunk runner queued { lv_groups } group(s).|.
  cv_message = gv_sm35_fallback_text.

  PERFORM z22_live_elapsed CHANGING lv_elapsed.
  PERFORM z16_set_0500_progress USING 0 lv_groups lv_elapsed.
  PERFORM z16_sapgui_progress USING 0 lv_groups gv_exec_run_phase.
  PERFORM z16_display_0500_queue.
  PERFORM z16_flush_0500_queue.
  PERFORM z22_start_0500_timer.
ENDFORM.
*<<< END FORM z28_run_sm35_gui_fallback

*>>> FORM z29_fb_tick - moved from Z_BDC_MASS_PO_ENTRY_F01_BUP

FORM z29_fb_tick.
  DATA: ls_key       TYPE ty_engine_group_key,
        lt_one       TYPE ty_t_staging_alv,
        ls_first     TYPE ty_staging_alv,
        lv_group_key TYPE string,
        lv_audit_msg TYPE string,
        lv_msg       TYPE string,
        lv_status    TYPE zbdc_staging_bup-status,
        lv_elapsed   TYPE i.

  IF gv_exec_stop_req = abap_true OR g_stop_flag = 'X'.
    PERFORM z29_fb_finish USING abap_true.
    RETURN.
  ENDIF.

  IF gv_fb_idx >= gv_fb_total OR gt_fb_keys IS INITIAL.
    PERFORM z29_fb_finish USING abap_false.
    RETURN.
  ENDIF.

  gv_fb_idx = gv_fb_idx + 1.
  READ TABLE gt_fb_keys INTO ls_key INDEX gv_fb_idx.
  IF sy-subrc <> 0.
    gv_fb_error = gv_fb_error + 1.
    gv_fb_done  = gv_fb_done + 1.
    gv_exec_run_done = gv_fb_done.
    RETURN.
  ENDIF.

  REFRESH lt_one.
  PERFORM z17_collect_group_key
    USING    gt_fb_queue ls_key
    CHANGING lt_one.
  READ TABLE lt_one INTO ls_first INDEX 1.
  IF sy-subrc <> 0.
    gv_fb_error = gv_fb_error + 1.
    gv_fb_done  = gv_fb_done + 1.
    gv_exec_run_done = gv_fb_done.
    RETURN.
  ENDIF.

  lv_group_key = ls_first-record_key.
  IF lv_group_key IS INITIAL.
    lv_group_key = ls_first-row_index.
  ENDIF.

  gv_exec_run_phase =
    |SM35 fallback running { gv_fb_idx }/{ gv_fb_total }: { ls_first-tcode } { lv_group_key }|.
  lv_audit_msg =
    |SM35 session { gv_fb_group } could not complete ME21N in background N. Automatic CALL TRANSACTION mode E chunk runner is processing this PO_KEY; original SM35 session is retained for audit.|.

  PERFORM save_synthetic_engine_log
    USING lt_one ls_first-tcode 2 gc_st_warning
          lv_audit_msg '' 'X'.

  PERFORM z24_async_q_set
    USING ls_key 'FALLBACK' lv_audit_msg ''.
  PERFORM z16_display_0500_queue.
  PERFORM z22_live_elapsed CHANGING lv_elapsed.
  PERFORM z16_set_0500_progress USING gv_fb_done gv_fb_total lv_elapsed.
  PERFORM z16_sapgui_progress USING gv_fb_done gv_fb_total gv_exec_run_phase.
  PERFORM z16_flush_0500_queue.

  "One blocking dialog BDC group.  After it returns, PBO can repaint the
  "verified result before the timer triggers the next group.
  PERFORM execute_bdc_engine USING lt_one gc_mode_call.

  CLEAR lv_status.
  SELECT SINGLE status
    FROM zbdc_staging_bup
    INTO @lv_status
    WHERE session_id = @ls_first-session_id
      AND row_index  = @ls_first-row_index.

  DATA(lv_fb_obj) = VALUE zbdc_result_bup-sap_object_id( ).
  IF ls_first-record_key IS INITIAL.
    SELECT SINGLE sap_object_id
      FROM zbdc_result_bup
      INTO @lv_fb_obj
      WHERE session_id = @ls_first-session_id
        AND row_index  = @ls_first-row_index
        AND sap_object_id <> @space.
  ELSE.
    SELECT SINGLE sap_object_id
      FROM zbdc_result_bup
      INTO @lv_fb_obj
      WHERE session_id = @ls_first-session_id
        AND record_key = @ls_first-record_key
        AND sap_object_id <> @space.
  ENDIF.

  gv_fb_done = gv_fb_done + 1.
  gv_sm35_fallback_done = gv_fb_done.
  gv_exec_run_done      = gv_fb_done.
  IF lv_status = gc_st_success.
    lv_msg = |SAP document { lv_fb_obj } created successfully by automatic fallback.|.
    PERFORM z24_async_q_set
      USING ls_key 'SUCCESS' lv_msg lv_fb_obj.
  ELSE.
    gv_fb_error = gv_fb_error + 1.
    gv_sm35_fallback_error = gv_fb_error.
    lv_msg = 'Automatic fallback finished but SAP document proof was not created. Open Error Detail.'.
    PERFORM z24_async_q_set
      USING ls_key 'ERROR' lv_msg ''.
    IF chkp_stop_on_error = 'X'.
      gv_exec_stop_req = abap_true.
      g_stop_flag = 'X'.
    ENDIF.
  ENDIF.

  PERFORM z16_display_0500_queue.
  PERFORM z22_live_elapsed CHANGING lv_elapsed.
  PERFORM z16_set_0500_progress USING gv_fb_done gv_fb_total lv_elapsed.
  PERFORM z16_sapgui_progress USING gv_fb_done gv_fb_total gv_exec_run_phase.
  PERFORM z16_flush_0500_queue.

  IF gv_exec_stop_req = abap_true OR g_stop_flag = 'X'.
    PERFORM z29_fb_finish USING abap_true.
  ELSEIF gv_fb_done >= gv_fb_total.
    PERFORM z29_fb_finish USING abap_false.
  ENDIF.
ENDFORM.
*<<< END FORM z29_fb_tick

*>>> FORM z29_fb_finish - moved from Z_BDC_MASS_PO_ENTRY_F01_BUP

FORM z29_fb_finish USING pv_stopped TYPE abap_bool.
  DATA: lt_sid     TYPE STANDARD TABLE OF zbdc_staging_bup-session_id,
        lv_sid     TYPE zbdc_staging_bup-session_id,
        lv_elapsed TYPE i,
        lv_issue   TYPE abap_bool.

  p_bdc_mode               = gv_fb_saved_mode.
  chkp_background          = gv_fb_saved_bg.
  chkp_stop_on_error       = gv_fb_saved_stop.
  gv_runtime_mode_override = gv_fb_saved_ovr_m.
  gv_runtime_upd_override  = gv_fb_saved_ovr_u.

  PERFORM z22_stop_0500_timer.
  gv_exec_run_active = abap_false.
  gv_sm35_fallback_active = abap_false.
  CLEAR: gv_exec_mon_kind, gv_sm35_job_finished.

  LOOP AT gt_fb_queue INTO DATA(ls_sum).
    READ TABLE lt_sid WITH KEY table_line = ls_sum-session_id
      TRANSPORTING NO FIELDS.
    IF sy-subrc <> 0.
      APPEND ls_sum-session_id TO lt_sid.
    ENDIF.
  ENDLOOP.
  LOOP AT lt_sid INTO lv_sid.
    PERFORM update_session_summary USING lv_sid.
  ENDLOOP.

  PERFORM prepare_alv_0400.
  PERFORM build_exec_cockpit.
  PERFORM z16_display_0500_queue.
  PERFORM z22_live_elapsed CHANGING lv_elapsed.
  PERFORM z16_has_0500_issue CHANGING lv_issue.
  PERFORM z16_set_0500_progress USING gv_fb_done gv_fb_total lv_elapsed.

  IF pv_stopped = abap_true.
    gv_exec_run_phase = |SM35 fallback stopped at { gv_fb_done }/{ gv_fb_total }.|.
    gv_sm35_fallback_text = gv_exec_run_phase.
    MESSAGE gv_exec_run_phase TYPE 'S' DISPLAY LIKE 'W'.
  ELSEIF gv_fb_error > 0 OR lv_issue = abap_true.
    gv_exec_run_phase = 'SM35 fallback completed with issue(s)'.
    gv_sm35_fallback_text =
      |SM35 fallback completed: { gv_fb_done - gv_fb_error } success, { gv_fb_error } error. Success requires verified SAP object proof.|.
    MESSAGE gv_sm35_fallback_text TYPE 'S' DISPLAY LIKE 'W'.
  ELSE.
    gv_exec_run_phase = 'SM35 fallback completed successfully'.
    gv_sm35_fallback_text =
      |SM35 fallback completed successfully for { gv_fb_done } group(s); SAP object proof was verified by the direct BDC engine.|.
    MESSAGE gv_sm35_fallback_text TYPE 'S'.
  ENDIF.

  PERFORM z23_refresh_0500_tools.
ENDFORM.
*<<< END FORM z29_fb_finish

*>>> FORM z22_monitor_sm35_tick - moved from Z_BDC_MASS_PO_ENTRY_F01_BUP

FORM z22_monitor_sm35_tick.
  DATA: lv_qstate      TYPE apqi-qstate,
        lv_apqi_found  TYPE abap_bool,
        lv_job_status  TYPE tbtco-status,
        lv_elapsed     TYPE i,
        lv_elapsed_sec TYPE i,
        lv_done        TYPE i,
        lv_total       TYPE i,
        lv_issue       TYPE abap_bool,
        lv_msg         TYPE string,
        lv_fb_started  TYPE abap_bool,
        lv_fb_message  TYPE string,
        lv_fb_done     TYPE i,
        lv_fb_error    TYPE i,
        lv_visible     TYPE i.

  PERFORM z22_live_elapsed CHANGING lv_elapsed.
  lv_elapsed_sec = lv_elapsed / 1000.
  CLEAR: lv_qstate, lv_apqi_found, lv_job_status.

  IF gv_sm35_mon_qid IS NOT INITIAL.
    SELECT SINGLE qstate
      FROM apqi
      INTO @lv_qstate
      WHERE mandant = @sy-mandt
        AND qid     = @gv_sm35_mon_qid.
    IF sy-subrc = 0.
      lv_apqi_found = abap_true.
    ENDIF.
  ENDIF.
  gv_sm35_last_qstate = lv_qstate.

  IF gv_last_sm35_jobname IS NOT INITIAL AND
     gv_last_sm35_jobcount IS NOT INITIAL.
    SELECT SINGLE status
      FROM tbtco
      INTO @lv_job_status
      WHERE jobname  = @gv_last_sm35_jobname
        AND jobcount = @gv_last_sm35_jobcount.
  ENDIF.

  "The RSBDCCTU compatibility job can finish before APQI/log persistence.
  "Only APQI terminal state or a canceled job is final.
  IF lv_job_status = 'A'.
    lv_msg = |RSBDCCTU compatibility job { gv_last_sm35_jobname } was canceled. Session { gv_sm35_mon_group } remains queued; no business result was inferred.|.
    PERFORM z16_stamp_sm35_action USING gt_sm35_mon_process lv_msg.
    gv_exec_run_done   = 0.
    gv_exec_run_active = abap_false.
    gv_exec_run_phase  = 'RSBDCCTU job canceled; session still queued'.
    CLEAR: gv_exec_mon_kind, gv_sm35_job_finished.
    PERFORM z22_stop_0500_timer.
    PERFORM prepare_alv_0400.
    PERFORM build_exec_cockpit.
    PERFORM z16_display_0500_queue.
    lv_visible = gv_exec_run_queued.
    IF lv_visible <= 0 AND gv_exec_run_total > 0.
      lv_visible = gv_exec_run_total.
    ENDIF.
    PERFORM z16_set_0500_progress USING lv_visible gv_exec_run_total lv_elapsed.
    PERFORM z23_refresh_0500_tools.
    MESSAGE lv_msg TYPE 'S' DISPLAY LIKE 'W'.
    RETURN.
  ENDIF.

  IF lv_qstate = 'E' OR lv_qstate = 'F'.
    lv_msg = |SM35 session { gv_sm35_mon_group } reached terminal state { lv_qstate }.|.
    PERFORM z24_q_set_all USING 'VERIFYING' lv_msg.
    PERFORM z16_reconcile_sm35
      USING gt_sm35_mon_process gv_sm35_mon_group
            gv_sm35_mon_qid lv_msg.

  ELSEIF lv_job_status = 'F' AND lv_elapsed_sec >= 10.
    "RSBDCCTU can finish after deleting/moving the APQI row, leaving QSTATE blank.
    "Do not wait blindly for 300 seconds; reconcile real protocol/object proof.
    gv_sm35_job_finished = abap_true.
    IF lv_apqi_found = abap_true.
      lv_msg = |RSBDCCTU job finished; APQI state { lv_qstate } is not terminal. Reconciling SM35 protocol and SAP-object proof.|.
    ELSE.
      lv_msg = |RSBDCCTU job finished; APQI row is no longer available. Reconciling SM35 protocol and SAP-object proof.|.
    ENDIF.
    PERFORM z24_q_set_all USING 'VERIFYING' lv_msg.
    PERFORM z16_reconcile_sm35
      USING gt_sm35_mon_process gv_sm35_mon_group
            gv_sm35_mon_qid lv_msg.

  ELSE.
    IF lv_job_status = 'F'.
      gv_sm35_job_finished = abap_true.
      gv_exec_run_phase =
        |Verifying SM35 { gv_sm35_mon_group }; RSBDCCTU job finished, session state { lv_qstate }|.
    ELSEIF lv_qstate = 'R' OR lv_qstate = 'S' OR lv_qstate = 'C'.
      gv_exec_run_phase =
        |SM35 processing { gv_sm35_mon_group }; session state { lv_qstate }|.
    ELSEIF lv_job_status IS INITIAL.
      gv_exec_run_phase = |SM35 queued { gv_sm35_mon_group }|.
    ELSE.
      gv_exec_run_phase =
        |RSBDCCTU job { lv_job_status }; session state { lv_qstate }|.
    ENDIF.

    "Do not report ERROR merely because RSBDCCTU ended first.
    "Wait for APQI/log/object evidence to become final.
    IF gv_sm35_mon_timeout <= 0.
      gv_sm35_mon_timeout = 60.
    ENDIF.

    IF lv_elapsed_sec < gv_sm35_mon_timeout.
      "V5BD: keep the header at real business progress while SM35 is
      "running. The queue count is communicated in the phase/status text;
      "it must not make Completion jump to 100% before PO proof exists.
      lv_visible = gv_exec_run_done.
      gv_exec_run_phase = |SM35 queued { gv_exec_run_queued }/{ gv_exec_run_total }; waiting for terminal proof|.
      PERFORM z24_q_set_all USING 'SM35RUN' gv_exec_run_phase.
      PERFORM z16_display_0500_queue.
      PERFORM z16_set_0500_progress
        USING lv_visible gv_exec_run_total lv_elapsed.
      RETURN.
    ENDIF.

    lv_msg =
      |SM35 live monitoring stopped after { gv_sm35_mon_timeout } sec. Session { gv_sm35_mon_group } is still in state { lv_qstate }; the business result remains pending in SM35.|.
    PERFORM z16_stamp_sm35_action USING gt_sm35_mon_process lv_msg.
    COMMIT WORK AND WAIT.
    gv_exec_run_done   = 0.
    gv_exec_run_active = abap_false.
    gv_exec_run_phase  = 'SM35 result still pending'.
    CLEAR: gv_exec_mon_kind, gv_sm35_job_finished.
    PERFORM z22_stop_0500_timer.
    PERFORM prepare_alv_0400.
    PERFORM build_exec_cockpit.
    PERFORM z16_display_0500_queue.
    lv_visible = gv_exec_run_queued.
    IF lv_visible <= 0 AND gv_exec_run_total > 0.
      lv_visible = gv_exec_run_total.
    ENDIF.
    PERFORM z16_set_0500_progress USING lv_visible gv_exec_run_total lv_elapsed.
    PERFORM z23_refresh_0500_tools.
    MESSAGE lv_msg TYPE 'S' DISPLAY LIKE 'W'.
    RETURN.
  ENDIF.

  "V5AY: after the real SM35 protocol has been synchronized/reconciled,
  "fallback only the exact groups that prove a GUI-Control N-mode failure.
  "Business errors, mapping errors and successfully-created SAP objects are
  "never retried through this path.
  "V5BB: always ask the collector whether terminal SM35/no-proof ME21N
  "requires automatic mode-E fallback. Do not depend on GV_LAST_SM35_MODE;
  "the collector limits fallback to the exact business groups that qualify.
  PERFORM z28_run_sm35_gui_fallback
    USING    gt_sm35_mon_process gv_sm35_mon_group
    CHANGING lv_fb_started lv_fb_message lv_fb_done lv_fb_error.

  IF lv_fb_started = abap_true.
    "V5BE: fallback is now a timer/chunk runner.  Do not mark the run
    "inactive here.  The next ZLIVE50 ticks execute exactly one PO_KEY,
    "then repaint 0500 before moving to the next group.
    PERFORM z16_display_0500_queue.
    PERFORM z16_set_0500_progress USING 0 gv_fb_total lv_elapsed.
    PERFORM z23_refresh_0500_tools.
    MESSAGE lv_fb_message TYPE 'S'.
    RETURN.
  ENDIF.

  PERFORM prepare_alv_0400.
  PERFORM build_exec_cockpit.
  PERFORM z16_display_0500_queue.
  PERFORM z16_count_0500_q CHANGING lv_done lv_total.
  PERFORM z16_has_0500_issue CHANGING lv_issue.

  gv_exec_run_done   = lv_done.
  gv_exec_run_active = abap_false.
  PERFORM z23_refresh_0500_tools.
  IF lv_issue = abap_true.
    gv_exec_run_phase = 'SM35 terminal state reconciled with issue(s)'.
  ELSEIF lv_total > 0 AND lv_done >= lv_total.
    gv_exec_run_phase = 'SM35 terminal state reconciled successfully'.
  ELSE.
    gv_exec_run_phase = 'SM35 terminal state reached; proof remains pending'.
  ENDIF.
  CLEAR: gv_exec_mon_kind, gv_sm35_job_finished.
  PERFORM z22_stop_0500_timer.
  PERFORM z16_set_0500_progress USING lv_done lv_total lv_elapsed.

  IF lv_issue = abap_true.
    MESSAGE |SM35 reached a terminal state with issue(s). Review Error Detail or SM35 Log.| TYPE 'S' DISPLAY LIKE 'E'.
  ELSEIF lv_total > 0 AND lv_done >= lv_total.
    MESSAGE |SM35 terminal results were reconciled for { lv_done }/{ lv_total } group(s).| TYPE 'S'.
  ELSE.
    MESSAGE |SM35 is terminal, but { lv_total - lv_done } group(s) still lack verifiable proof.| TYPE 'S' DISPLAY LIKE 'W'.
  ENDIF.
ENDFORM.
*<<< END FORM z22_monitor_sm35_tick

*>>> FORM z22_monitor_0500_tick - moved from Z_BDC_MASS_PO_ENTRY_F01_BUP

FORM z22_monitor_0500_tick.
  DATA: lv_elapsed TYPE i,
        lv_elapsed_sec TYPE p LENGTH 8 DECIMALS 1.

  IF gv_exec_run_active <> abap_true.
    PERFORM z22_stop_0500_timer.
    RETURN.
  ENDIF.

  CASE gv_exec_mon_kind.
    WHEN 'C'.
      PERFORM z22_live_elapsed CHANGING lv_elapsed.
      lv_elapsed_sec = lv_elapsed / 1000.
      IF gv_async_done = abap_true.
        PERFORM z22_async_finalize_current.
      ELSE.
        gv_exec_run_phase =
          |Processing { gv_async_tcode } { gv_async_group_key }; elapsed { lv_elapsed_sec } sec|.
        PERFORM z16_set_0500_progress
          USING gv_exec_run_done gv_async_total lv_elapsed.
      ENDIF.
    WHEN 'B'.
      PERFORM z22_monitor_sm35_tick.
    WHEN 'F'.
      PERFORM z29_fb_tick.
    WHEN OTHERS.
      PERFORM z22_stop_0500_timer.
  ENDCASE.
ENDFORM.
*<<< END FORM z22_monitor_0500_tick

*>>> FORM z21_run_async_call_0500 - moved from Z_BDC_MASS_PO_ENTRY_F01_BUP

FORM z21_run_async_call_0500
  CHANGING cv_handled TYPE abap_bool.

  DATA: lt_process   TYPE ty_t_staging_alv,
        lt_keys      TYPE ty_t_engine_group_key,
        ls_first     TYPE ty_staging_alv,
        lv_total     TYPE i,
        lv_lock_ok   TYPE abap_bool,
        lv_lock_act  TYPE abap_bool,
        lv_disp      TYPE c LENGTH 1,
        lv_upd       TYPE c LENGTH 1,
        lv_bsize     TYPE i.

  CLEAR cv_handled.

  IF gv_exec_run_active = abap_true OR gv_async_active = abap_true.
    MESSAGE 'An execution worker is already active.' TYPE 'S' DISPLAY LIKE 'W'.
    cv_handled = abap_true.
    RETURN.
  ENDIF.

  IF gt_staging IS INITIAL.
    PERFORM load_latest_staging_for_tcode USING p_transaction CHANGING lv_total.
  ENDIF.
  PERFORM prepare_alv_0400.

  IF gt_exec_scope_0500 IS NOT INITIAL.
    PERFORM z16_current_ready_scope
      USING    gt_exec_scope_0500
      CHANGING lt_process.
  ELSE.
    PERFORM collect_ready_groups_all CHANGING lt_process.
    gv_exec_scope_text = 'all READY groups in this session'.
  ENDIF.

  PERFORM z17_build_engine_keys USING lt_process CHANGING lt_keys.
  lv_total = lines( lt_keys ).
  IF lt_process IS INITIAL OR lv_total = 0.
    MESSAGE 'No current READY group remains for Execute Now.' TYPE 'S' DISPLAY LIKE 'W'.
    cv_handled = abap_true.
    RETURN.
  ENDIF.

  READ TABLE lt_process INTO ls_first INDEX 1.
  IF sy-subrc <> 0.
    MESSAGE 'Could not resolve execution scope.' TYPE 'S' DISPLAY LIKE 'E'.
    cv_handled = abap_true.
    RETURN.
  ENDIF.

  DATA lv_has_me21n TYPE abap_bool.
  PERFORM z26_process_has_tcode
    USING    lt_process 'ME21N'
    CHANGING lv_has_me21n.
  IF lv_has_me21n = abap_true.
    "ME21N cannot be executed inside the RFC/no-display worker because
    "SAPLMEGUI requires a reachable SAP GUI. Let the caller fall back to the
    "dialog CALL TRANSACTION path; RUN_BDC_ONE_GROUP forces MODE E when the
    "user selected N, so it remains automatic but real.
    cv_handled = abap_false.
    MESSAGE 'ME21N Execute Now uses GUI-safe Display-errors-only instead of RFC no-display.' TYPE 'S'.
    RETURN.
  ENDIF.

  PERFORM acquire_staging_lock_safe
    USING    ls_first-session_id
    CHANGING lv_lock_ok lv_lock_act.
  IF lv_lock_ok <> abap_true.
    cv_handled = abap_true.
    RETURN.
  ENDIF.

  PERFORM get_runtime_options CHANGING lv_disp lv_upd lv_bsize.

  gt_async_process[] = lt_process[].
  gt_async_keys[]    = lt_keys[].
  PERFORM z24_async_q_init.
  gv_async_total     = lv_total.
  gv_async_key_index = 0.
  gv_async_updmode   = lv_upd.
  gv_async_lock_sid  = ls_first-session_id.
  gv_async_lock_on   = lv_lock_act.
  CLEAR: gv_async_any_error, gv_async_done, gv_async_active,
         gv_async_attempt, gv_async_receive_rc, gv_async_subrc,
         gv_async_message, gv_async_group_key, gv_async_tcode.

  GET RUN TIME FIELD gv_async_run_start.
  GET TIME STAMP FIELD gv_exec_start_ts.
  gv_exec_run_start_rt = gv_async_run_start.
  gv_exec_run_total    = lv_total.
  gv_exec_run_done     = 0.
  gv_exec_run_active   = abap_true.
  gv_exec_run_engine   = 'R'.
  gv_exec_mon_kind     = 'C'.
  gv_exec_run_phase    = 'Preparing first document'.
  gv_exec_stop_req     = abap_false.
  CLEAR: g_stop_flag, g_exec_curr, g_exec_success, g_exec_error.

  PERFORM z16_set_0500_progress USING 0 lv_total 0.
  PERFORM z23_refresh_0500_tools.
  PERFORM z22_start_0500_timer.
  PERFORM z22_async_start_next.

  cv_handled = abap_true.
ENDFORM.
*<<< END FORM z21_run_async_call_0500

*>>> FORM z16_queue_sm35_0500 - moved from Z_BDC_MASS_PO_ENTRY_F01_BUP


FORM z16_queue_sm35_0500.
  DATA: lv_saved_mode TYPE char30,
        lv_saved_bg   TYPE c LENGTH 1,
        lv_saved_rb_n TYPE c LENGTH 1,
        lv_saved_rb_e TYPE c LENGTH 1,
        lv_saved_rb_a TYPE c LENGTH 1,
        lv_mode       TYPE c LENGTH 1,
        lv_upd        TYPE c LENGTH 1,
        lv_bsize      TYPE i,
        lv_msg        TYPE string,
        lt_process    TYPE ty_t_staging_alv,
        lt_keys       TYPE ty_t_engine_group_key,
        lv_total      TYPE i,
        lv_has_me21n  TYPE abap_bool.

  IF gv_exec_run_active = abap_true OR gv_async_active = abap_true.
    MESSAGE 'An execution request is already running.' TYPE 'S' DISPLAY LIKE 'W'.
    RETURN.
  ENDIF.

  lv_saved_mode = p_bdc_mode.
  lv_saved_bg   = chkp_background.
  lv_saved_rb_n = rb_mode_n.
  lv_saved_rb_e = rb_mode_e.
  lv_saved_rb_a = rb_mode_a.

  PERFORM get_runtime_options CHANGING lv_mode lv_upd lv_bsize.

  IF gt_exec_scope_0500 IS NOT INITIAL.
    PERFORM z16_current_ready_scope
      USING gt_exec_scope_0500 CHANGING lt_process.
  ELSE.
    PERFORM collect_ready_groups_all CHANGING lt_process.
  ENDIF.
  PERFORM z17_build_engine_keys USING lt_process CHANGING lt_keys.
  lv_total = lines( lt_keys ).

  "V5BF: freeze exactly this button-click scope for 0500.  The monitor must
  "never keep displaying stale rows from an older run/session.
  gt_exec_scope_0500[] = lt_process[].
  PERFORM z24_q_init_proc
    USING lt_process 'QUEUED'
          'Preparing this run: SM35 session will be created for the selected group(s).'.

  IF lt_process IS INITIAL OR lv_total = 0.
    MESSAGE 'No current READY group remains for Run Batch Session.' TYPE 'S' DISPLAY LIKE 'W'.
    RETURN.
  ENDIF.

  PERFORM z26_process_has_tcode
    USING    lt_process 'ME21N'
    CHANGING lv_has_me21n.

  IF lv_has_me21n <> abap_true.
    DATA(lv_curr_tcode_0500) = p_transaction.
    TRANSLATE lv_curr_tcode_0500 TO UPPER CASE.
    CONDENSE lv_curr_tcode_0500 NO-GAPS.
    IF lv_curr_tcode_0500 = 'ME21N'.
      lv_has_me21n = abap_true.
    ENDIF.
  ENDIF.

  p_bdc_mode         = gc_mode_batch.
  chkp_background    = 'X'.
  chkp_stop_on_error = 'X'.

  IF lv_has_me21n = abap_true AND lv_mode = 'N'.
    "V5AY: preserve the user's real N/S or N/A Batch Input profile. The
    "session is first processed by RSBDCCTU in no-display mode. Only when
    "the resulting SM35 protocol proves a GUI-Control limitation (DC006 /
    "GUI cannot be reached) is an automatic CALL TRANSACTION mode-E fallback
    "started for the affected group(s). Ordinary business/data errors never
    "trigger the fallback and remain genuine SM35 errors.
    MESSAGE 'ME21N SM35 N-mode will run first; GUI-Control failures are detected from the real SM35 log and retried automatically in mode E.' TYPE 'S'.
  ENDIF.

  "Create the real BI session and start its configured six-combination
  "profile (A/E/N x S/A) without silently changing the saved setup.
  PERFORM run_execution_monitor USING gc_mode_batch.

  p_bdc_mode      = lv_saved_mode.
  chkp_background = lv_saved_bg.
  rb_mode_n       = lv_saved_rb_n.
  rb_mode_e       = lv_saved_rb_e.
  rb_mode_a       = lv_saved_rb_a.

  IF lv_mode = 'N' AND
     gv_last_sm35_qid IS NOT INITIAL AND
     gv_last_sm35_jobname IS NOT INITIAL AND
     lv_total > 0.
    gt_sm35_mon_process[] = lt_process[].
    gv_sm35_mon_qid       = gv_last_sm35_qid.
    gv_sm35_mon_group     = gv_last_sm35_group.
    gv_exec_run_total     = lv_total.
    gv_exec_run_done      = 0.
    gv_sm35_mon_timeout   = ( lv_total * 30 ) + 120.
    IF gv_sm35_mon_timeout < 60.
      gv_sm35_mon_timeout = 60.
    ELSEIF gv_sm35_mon_timeout > 7200.
      gv_sm35_mon_timeout = 7200.
    ENDIF.
    CLEAR: gv_sm35_job_finished, gv_sm35_last_qstate.
    gv_exec_run_active    = abap_true.
    gv_exec_run_engine    = 'B'.
    gv_exec_mon_kind      = 'B'.
    gv_exec_run_phase     = |SM35 processing { gv_sm35_mon_group }|.
    lv_msg = |SM35 session { gv_sm35_mon_group } started via RSBDCCTU; waiting for terminal proof.|.
    PERFORM z24_q_set_all
      USING 'SM35RUN' lv_msg.
    GET RUN TIME FIELD gv_async_run_start.
    gv_exec_run_start_rt = gv_async_run_start.
    IF gv_exec_run_queued <= 0.
      gv_exec_run_queued = lv_total.
    ENDIF.
    PERFORM z16_display_0500_queue.
    PERFORM z16_set_0500_progress
      USING 0 lv_total 0.
    PERFORM z23_refresh_0500_tools.
    PERFORM z22_start_0500_timer.
    MESSAGE |SM35 session { gv_sm35_mon_group } started. Live verification is active.| TYPE 'S'.
  ELSEIF lv_mode = 'N' AND gv_last_sm35_qid IS NOT INITIAL.
    MESSAGE |SM35 session { gv_last_sm35_group } was created but automatic processing did not start. Open SM35 Monitor.| TYPE 'S' DISPLAY LIKE 'W'.
  ENDIF.
ENDFORM.
*<<< END FORM z16_queue_sm35_0500

*>>> FORM run_execution_monitor - moved from Z_BDC_MASS_PO_ENTRY_F01_BUP

FORM run_execution_monitor USING iv_engine_mode TYPE csequence.
  DATA lt_process  TYPE STANDARD TABLE OF ty_staging_alv.
  DATA lv_total    TYPE i.
  DATA lv_rt_start TYPE i.
  DATA lv_rt_end   TYPE i.
  DATA lv_rt_diff  TYPE i.
  DATA lv_ok       TYPE abap_bool.
  DATA lv_scope    TYPE char60.
  DATA lv_old_mode TYPE char30.
  DATA lv_batch_run TYPE abap_bool.
  DATA lv_processed_grp TYPE i.
  DATA lv_final_total   TYPE i.
  DATA lt_run_keys      TYPE ty_t_engine_group_key.

  "V5D: 0500 no longer has confusing OPTIONS on screen.
  "Error policy is fixed and explicit: stop queue after first failed group.
  chkp_stop_on_error = 'X'.

  IF gv_exec_stop_req = abap_true OR g_stop_flag = 'X'.
    MESSAGE 'Execution queue is stopped. Press Refresh, clear STOP, then Execute again if needed.' TYPE 'S' DISPLAY LIKE 'W'.
    RETURN.
  ENDIF.

  IF gt_staging IS INITIAL.
    PERFORM load_latest_staging_for_tcode USING p_transaction CHANGING lv_total.
  ENDIF.
  PERFORM prepare_alv_0400.

  IF gt_exec_scope_0500 IS NOT INITIAL.
    PERFORM z16_current_ready_scope
      USING    gt_exec_scope_0500
      CHANGING lt_process.
  ELSE.
    PERFORM collect_ready_groups_all CHANGING lt_process.
    gv_exec_scope_text = 'all READY groups in this session'.
  ENDIF.

  PERFORM z17_build_engine_keys USING lt_process CHANGING lt_run_keys.
  lv_final_total = lines( lt_run_keys ).
  txtgv_exec_total = lv_final_total.

  IF lt_process IS INITIAL OR lv_final_total = 0.
    MESSAGE 'No current READY group remains. SUCCESS and SM35QUEUE groups are protected from duplicate execution.' TYPE 'W'.
    RETURN.
  ENDIF.

  lv_scope = gv_exec_scope_text.
  IF lv_scope IS INITIAL.
    lv_scope = 'READY groups in this session'.
  ENDIF.
  "V5AK: no second confirmation. The explicit engine button is the commit
  "action, which keeps the flow fast and predictable for repeated batches.
  CLEAR gv_0500_confirmed.

  GET TIME STAMP FIELD gv_exec_start_ts.
  GET RUN TIME FIELD lv_rt_start.
  g_stop_flag           = space.
  gv_exec_stop_req      = abap_false.
  g_exec_curr           = 0.
  gv_exec_run_total     = lv_final_total.
  gv_exec_run_done      = 0.
  gv_exec_run_start_rt  = lv_rt_start.
  gv_exec_run_active    = abap_true.
  gv_exec_run_phase     = 'Preparing execution queue'.
  PERFORM z16_set_0500_progress USING 0 lv_final_total 0.

  "Freeze the requested engine before processing. Do not decide from the old
  "hidden CHKP_BACKGROUND field: that was the reason two toolbar actions could
  "fall into the same execution behavior after a dynpro roundtrip.
  lv_old_mode = p_bdc_mode.
  IF iv_engine_mode = gc_mode_batch.
    lv_batch_run = abap_true.
  ELSE.
    lv_batch_run = abap_false.
  ENDIF.

  IF lv_batch_run = abap_true.
    "True queue path: one real session with group-by-group BDC_INSERT and
    "visible progress. CALL TRANSACTION is unreachable in this branch.
    p_bdc_mode = gc_mode_batch.
    gv_exec_run_engine = 'B'.
    gv_exec_run_phase  = 'Creating SM35 batch session'.
    PERFORM execute_bdc_engine USING lt_process gc_mode_batch.
    g_exec_curr = gv_exec_run_done.
  ELSE.
    gv_exec_run_engine = 'C'.
    gv_exec_run_phase  = 'Running Call Transaction'.
    "Direct path: force CALL_TRANSACTION and process group-by-group so mode A
    "can show the real ME21N/MIGO screens.
    p_bdc_mode = gc_mode_call.
    PERFORM z16_run_0500_group_loop USING lt_process lv_rt_start.
  ENDIF.

  p_bdc_mode = lv_old_mode.
  gv_exec_run_active = abap_false.

  GET RUN TIME FIELD lv_rt_end.
  GET TIME STAMP FIELD gv_exec_end_ts.

  lv_rt_diff = lv_rt_end - lv_rt_start.
  IF lv_rt_diff < 0.
    lv_rt_diff = 0.
  ENDIF.
  "GET RUN TIME returns microseconds. Store milliseconds for screen 0500.
  gv_exec_elapsed = lv_rt_diff / 1000.

  "V5E: keep the 0400 scope visible in 0500 after execution.
  "Clearing the scope made the queue/dashboard fall back to an unrelated
  "latest session or all-session cockpit after EXEC/SM35. A new Run All /
  "Run Selected from 0400 will overwrite this scope.
  gv_exec_scope_ready = abap_true.

  PERFORM build_exec_cockpit.

  "V5F: progress must follow the exact 0400 scope, not the whole staging
  "session. Run All uses the whole READY queue; Run Selected uses only the
  "selected READY group(s). z16_display_0500_queue filters GT_EXEC_DISP back
  "to GT_EXEC_SCOPE_0500 before counting.
  PERFORM z16_display_0500_queue.
  PERFORM z16_count_0500_q CHANGING lv_processed_grp lv_final_total.
  IF gv_exec_run_total > 0. lv_final_total = gv_exec_run_total. ENDIF.
  IF gv_exec_run_done > lv_processed_grp. lv_processed_grp = gv_exec_run_done. ENDIF.

  IF lv_batch_run = abap_true.
    DATA(lv_sm35_queued_0500) = 0.
    PERFORM z27_count_0500_sm35_queued
      CHANGING lv_sm35_queued_0500 lv_final_total.
    IF lv_sm35_queued_0500 > 0.
      "V5BD: keep the numeric progress business-real. SM35 queue creation
      "is visible in the phase/text and ALV rows, but it is not completion.
      IF gv_last_sm35_group IS NOT INITIAL.
        gv_exec_run_phase = |SM35 session queued { gv_last_sm35_group }; { lv_sm35_queued_0500 }/{ lv_final_total } queued, SAP document proof pending|.
      ELSE.
        gv_exec_run_phase = |SM35 session queued; { lv_sm35_queued_0500 }/{ lv_final_total } queued, SAP document proof pending|.
      ENDIF.
    ENDIF.
  ENDIF.

  g_exec_curr = lv_processed_grp.
  PERFORM z16_set_0500_progress USING lv_processed_grp lv_final_total gv_exec_elapsed.
  PERFORM z16_flush_0500_queue.

  IF lv_batch_run = abap_true.
    IF gv_last_sm35_action IS NOT INITIAL.
      MESSAGE gv_last_sm35_action TYPE 'S'.
    ELSE.
      MESSAGE |Batch-input session created for { lv_processed_grp } group(s). Check SM35.| TYPE 'S'.
    ENDIF.
  ELSEIF chkp_stop_on_error = 'X' AND gv_exec_err_grp > 0.
    MESSAGE |Stopped on first error. Processed { lv_processed_grp } group(s).| TYPE 'W'.
  ELSE.
    MESSAGE |Execution finished in 0500: { lv_processed_grp } group(s) processed.| TYPE 'S'.
  ENDIF.

  PERFORM z16_force_0500_repaint.
ENDFORM.
*<<< END FORM run_execution_monitor

*>>> FORM z27_count_0500_sm35_queued - moved from Z_BDC_MASS_PO_ENTRY_F01_BUP





FORM z27_count_0500_sm35_queued
  CHANGING cv_queued TYPE i
           cv_total  TYPE i.

  CLEAR cv_queued.
  IF cv_total IS INITIAL.
    cv_total = lines( gt_exec_disp ).
  ENDIF.

  LOOP AT gt_exec_disp ASSIGNING FIELD-SYMBOL(<ls_q_sm35_count>).
    CASE <ls_q_sm35_count>-run_status.
      WHEN gc_st_sm35q OR 'SM35QUEUE' OR 'SM35RUN'.
        cv_queued = cv_queued + 1.
    ENDCASE.
  ENDLOOP.
ENDFORM.
*<<< END FORM z27_count_0500_sm35_queued

*>>> FORM z16_mark_0500_group - moved from Z_BDC_MASS_PO_ENTRY_F01_BUP

FORM z16_mark_0500_group
  USING iv_session TYPE csequence
        iv_group   TYPE csequence
        iv_status  TYPE csequence
        iv_health  TYPE csequence
        iv_action  TYPE csequence
        iv_msg     TYPE csequence.

  LOOP AT gt_exec_disp ASSIGNING FIELD-SYMBOL(<ls_0500_mark>)
       WHERE session_id = iv_session AND group_key = iv_group.
    <ls_0500_mark>-run_status  = iv_status.
    <ls_0500_mark>-health_text = iv_health.
    <ls_0500_mark>-action_hint = iv_action.
    <ls_0500_mark>-message     = iv_msg.
  ENDLOOP.

  PERFORM z16_flush_0500_queue.
ENDFORM.
*<<< END FORM z16_mark_0500_group

*>>> FORM z16_run_0500_group_loop - moved from Z_BDC_MASS_PO_ENTRY_F01_BUP

FORM z16_run_0500_group_loop
  USING it_process  TYPE ty_t_staging_alv
        iv_rt_start TYPE i.

  DATA: lt_keys       TYPE ty_t_engine_group_key,
        ls_key        TYPE ty_engine_group_key,
        lt_one        TYPE ty_t_staging_alv,
        ls_first      TYPE ty_staging_alv,
        lv_total_grp  TYPE i,
        lv_idx        TYPE i,
        lv_prev       TYPE i,
        lv_err_before TYPE i,
        lv_rt_now     TYPE i,
        lv_elapsed_ms TYPE i,
        lv_group_key  TYPE string.

  "One progress unit is one business document group, not one item row.
  PERFORM z17_build_engine_keys USING it_process CHANGING lt_keys.
  lv_total_grp = lines( lt_keys ).

  LOOP AT lt_keys INTO ls_key.
    IF gv_exec_stop_req = abap_true OR g_stop_flag = 'X'.
      EXIT.
    ENDIF.

    lv_idx  = sy-tabix.
    lv_prev = lv_idx - 1.
    PERFORM z17_collect_group_key USING it_process ls_key CHANGING lt_one.
    READ TABLE lt_one INTO ls_first INDEX 1.
    IF sy-subrc <> 0.
      CONTINUE.
    ENDIF.

    lv_group_key = ls_key-record_key.
    IF lv_group_key IS INITIAL.
      lv_group_key = ls_key-row_index.
    ENDIF.

    GET RUN TIME FIELD lv_rt_now.
    lv_elapsed_ms = lv_rt_now - iv_rt_start.
    IF lv_elapsed_ms < 0. lv_elapsed_ms = 0. ENDIF.
    lv_elapsed_ms = lv_elapsed_ms / 1000.

    PERFORM z16_set_0500_progress USING lv_prev lv_total_grp lv_elapsed_ms.
    PERFORM z16_mark_0500_group
      USING ls_first-session_id lv_group_key 'PROCESSING'
            'Running SAP transaction'
            'Wait for the active SAP transaction to return'
            'The next selected group starts after this transaction returns.'.
    PERFORM z16_sapgui_progress USING lv_idx lv_total_grp lv_group_key.
    "Flush the visible monitor before the synchronous CALL TRANSACTION takes
    "control of the GUI. A single document is an atomic progress unit; the
    "next truthful percentage is published only after that document returns.
    PERFORM z16_force_0500_repaint.

    lv_err_before = gv_exec_err_grp.
    PERFORM execute_bdc_engine USING lt_one gc_mode_call.
    IF g_stop_flag = 'X'.
      gv_exec_stop_req = abap_true.
    ENDIF.

    GET RUN TIME FIELD lv_rt_now.
    lv_elapsed_ms = lv_rt_now - iv_rt_start.
    IF lv_elapsed_ms < 0. lv_elapsed_ms = 0. ENDIF.
    lv_elapsed_ms = lv_elapsed_ms / 1000.

    gv_exec_run_done = lv_idx.
    g_exec_curr       = lv_idx.
    PERFORM prepare_alv_0400.
    PERFORM build_exec_cockpit.
    PERFORM z16_set_0500_progress USING lv_idx lv_total_grp lv_elapsed_ms.
    PERFORM z16_flush_0500_queue.
    PERFORM z16_sapgui_progress USING lv_idx lv_total_grp lv_group_key.

    IF chkp_stop_on_error = 'X'
       AND ( gv_exec_err_grp > lv_err_before OR gv_exec_stop_req = abap_true ).
      gv_exec_stop_req = abap_true.
      EXIT.
    ENDIF.
  ENDLOOP.
ENDFORM.
*<<< END FORM z16_run_0500_group_loop

*>>> FORM z18_request_0500_pbo - moved from Z_BDC_MASS_PO_ENTRY_F01_BUP

FORM z18_request_0500_pbo.
  IF gv_0500_active <> abap_true.
    RETURN.
  ENDIF.
  TRY.
      cl_gui_cfw=>set_new_ok_code( new_code = 'ZREF500' ).
    CATCH cx_root.
      "A later user action/PBO will repaint the values.
  ENDTRY.
ENDFORM.
*<<< END FORM z18_request_0500_pbo

*>>> FORM z18_progress_after_group - moved from Z_BDC_MASS_PO_ENTRY_F01_BUP


FORM z18_progress_after_group
  USING pt_group TYPE ty_t_staging_alv.

  DATA: ls_first      TYPE ty_staging_alv,
        lv_rt_now     TYPE i,
        lv_elapsed_ms TYPE i,
        lv_group_key  TYPE string.

  IF gv_exec_run_active <> abap_true OR gv_exec_run_engine <> 'B'.
    RETURN.
  ENDIF.

  "BDC_INSERT means prepared/queued, not business completion. Keep the
  "completion counter factual until SM35 protocol and SAP-object proof are
  "reconciled after the session processor returns.
  gv_exec_run_queued = gv_exec_run_queued + 1.
  g_exec_curr        = gv_exec_run_done.

  GET RUN TIME FIELD lv_rt_now.
  lv_elapsed_ms = lv_rt_now - gv_exec_run_start_rt.
  IF lv_elapsed_ms < 0. lv_elapsed_ms = 0. ENDIF.
  lv_elapsed_ms = lv_elapsed_ms / 1000.

  READ TABLE pt_group INTO ls_first INDEX 1.
  IF sy-subrc = 0.
    lv_group_key = ls_first-record_key.
    IF lv_group_key IS INITIAL. lv_group_key = ls_first-row_index. ENDIF.
  ENDIF.

  gv_exec_run_phase =
    |Prepared SM35 transaction { gv_exec_run_queued }/{ gv_exec_run_total }: { lv_group_key }|.

  PERFORM z16_set_0500_progress
    USING gv_exec_run_done gv_exec_run_total lv_elapsed_ms.
  PERFORM z16_sapgui_progress
    USING gv_exec_run_queued gv_exec_run_total gv_exec_run_phase.
  PERFORM z16_flush_0500_queue.
ENDFORM.
*<<< END FORM z18_progress_after_group

*>>> FORM z16_refresh_sm35_state - moved from Z_BDC_MASS_PO_ENTRY_F01_BUP


FORM z16_refresh_sm35_state.
  IF gv_last_sm35_group IS INITIAL OR gt_exec_scope_0500 IS INITIAL.
    RETURN.
  ENDIF.

  PERFORM z16_find_sm35_qid
    USING gv_last_sm35_group
    CHANGING gv_last_sm35_qid.

  PERFORM z16_reconcile_sm35
    USING gt_exec_scope_0500 gv_last_sm35_group gv_last_sm35_qid
          'Execution-monitor refresh'.
ENDFORM.
*<<< END FORM z16_refresh_sm35_state

*>>> FORM z16_open_sm35_0500 - moved from Z_BDC_MASS_PO_ENTRY_F01_BUP

FORM z16_open_sm35_0500.
  DATA lv_sm35_group TYPE apqi-groupid.

  lv_sm35_group = gv_last_sm35_group.

  "Mode A owns CL_GUI_CONTAINER=>SCREEN0. It must be destroyed before
  "CALL TRANSACTION, otherwise its ALV can remain above the SM35 dynpro.
  PERFORM z16_free_0500_queue.

  TRY.
      CALL METHOD cl_gui_cfw=>flush.
    CATCH cx_root.
      "Navigation to SM35 must remain available even if frontend cleanup
      "reports a harmless control-framework exception.
  ENDTRY.

  IF lv_sm35_group IS INITIAL.
    MESSAGE 'Opening SM35 Monitor.' TYPE 'S'.
  ELSEIF gv_last_sm35_profile IS INITIAL.
    MESSAGE |Opening SM35 Monitor. Latest session: { lv_sm35_group }.| TYPE 'S'.
  ELSE.
    MESSAGE |Opening SM35 Monitor for { lv_sm35_group } ({ gv_last_sm35_profile }).| TYPE 'S'.
  ENDIF.

  CALL TRANSACTION 'SM35'.

  "SM35 Monitor never creates the business error. After Back, read APQI so
  "the cockpit reflects SUCCESS / ERROR / still queued for the latest session.
  IF lv_sm35_group IS NOT INITIAL AND gt_exec_scope_0500 IS NOT INITIAL.
    PERFORM z16_find_sm35_qid
      USING lv_sm35_group
      CHANGING gv_last_sm35_qid.
    PERFORM z16_reconcile_sm35
      USING gt_exec_scope_0500 lv_sm35_group gv_last_sm35_qid
            'Returned from SM35 Monitor'.
  ENDIF.

  "When the user presses Back in SM35, control returns to the current
  "0500 dialog step. In an ALV-toolbar callback there may be no automatic
  "PBO after CALL TRANSACTION, so rebuild the docking/grid immediately.
  gv_0500_active = abap_true.
  PERFORM z16_display_0500_queue.
  PERFORM z16_sync_0500_progress_q.
  PERFORM z16_flush_0500_queue.
  PERFORM z16_force_0500_repaint.
ENDFORM.
*<<< END FORM z16_open_sm35_0500

*>>> FORM z16_has_0500_issue - moved from Z_BDC_MASS_PO_ENTRY_F01_BUP


FORM z16_has_0500_issue CHANGING cv_issue TYPE abap_bool.
  CLEAR cv_issue.
  LOOP AT gt_exec_disp ASSIGNING FIELD-SYMBOL(<ls_issue>).
    IF <ls_issue>-run_status = gc_st_error OR
       <ls_issue>-run_status = gc_st_warning OR
       <ls_issue>-run_status = 'SKIPPED' OR
       <ls_issue>-run_status = 'PARTIAL'.
      cv_issue = abap_true.
      EXIT.
    ENDIF.
  ENDLOOP.
ENDFORM.
*<<< END FORM z16_has_0500_issue

*>>> FORM z16_pick_0500_issue - moved from Z_BDC_MASS_PO_ENTRY_F01_BUP

FORM z16_pick_0500_issue.
  DATA lt_rows  TYPE lvc_t_row.
  DATA ls_row   TYPE lvc_s_row.
  DATA ls_exec  TYPE ty_exec_disp.
  DATA lv_found TYPE abap_bool.

  CLEAR: lv_found, g_edit_index,
         txtp_result_session, txtp_po_key,
         txtp_sap_object_id, txtp_result_msg.

  "Only an actual runtime issue is eligible for Error Detail / Fix Guide.
  "A READY or SUCCESS row must never be treated as an error merely because
  "the user selected it in the queue.
  IF go_grid_0500 IS BOUND.
    TRY.
        CALL METHOD go_grid_0500->get_selected_rows
          IMPORTING et_index_rows = lt_rows.
      CATCH cx_root.
    ENDTRY.
  ENDIF.

  READ TABLE lt_rows INTO ls_row INDEX 1.
  IF sy-subrc = 0.
    READ TABLE gt_exec_disp INTO ls_exec INDEX ls_row-index.
    IF sy-subrc = 0 AND
       ( ls_exec-run_status = gc_st_error OR
         ls_exec-run_status = gc_st_warning OR
         ls_exec-run_status = 'SKIPPED' OR
         ls_exec-run_status = 'PARTIAL' ).
      lv_found = abap_true.
    ENDIF.
  ENDIF.

  IF lv_found IS INITIAL.
    LOOP AT gt_exec_disp INTO ls_exec
      WHERE run_status = gc_st_error OR run_status = gc_st_warning
         OR run_status = 'SKIPPED' OR run_status = 'PARTIAL'.
      lv_found = abap_true.
      EXIT.
    ENDLOOP.
  ENDIF.

  IF lv_found = abap_true.
    READ TABLE gt_staging_alv TRANSPORTING NO FIELDS
      WITH KEY session_id = ls_exec-session_id record_key = ls_exec-group_key.
    IF sy-subrc = 0.
      g_edit_index = sy-tabix.
    ELSE.
      READ TABLE gt_staging_alv TRANSPORTING NO FIELDS
        WITH KEY record_key = ls_exec-group_key.
      IF sy-subrc = 0.
        g_edit_index = sy-tabix.
      ENDIF.
    ENDIF.

    txtp_result_session = ls_exec-session_id.
    txtp_po_key         = ls_exec-group_key.
    txtp_sap_object_id  = ls_exec-sap_object_id.
    txtp_result_msg     = ls_exec-message.
  ENDIF.
ENDFORM.
*<<< END FORM z16_pick_0500_issue

*>>> FORM z16_open_0500_retry - moved from Z_BDC_MASS_PO_ENTRY_F01_BUP

FORM z16_open_0500_retry.
  PERFORM z16_pick_0500_issue.
  CALL SCREEN 0560 STARTING AT 10 5 ENDING AT 88 18.
ENDFORM.
*<<< END FORM z16_open_0500_retry

*>>> FORM z16_after_0500_execute - moved from Z_BDC_MASS_PO_ENTRY_F01_BUP

FORM z16_after_0500_execute.
  DATA lv_issue TYPE abap_bool.
  DATA lv_done  TYPE i.
  DATA lv_total TYPE i.

  PERFORM z16_count_0500_q CHANGING lv_done lv_total.
  PERFORM z16_has_0500_issue CHANGING lv_issue.

  IF lv_issue = abap_true.
    MESSAGE 'Execution has runtime issue(s). Stay in 0500; use Error Detail or Fix Guide when ready.' TYPE 'S' DISPLAY LIKE 'W'.
  ELSEIF lv_total > 0 AND lv_done >= lv_total.
    MESSAGE 'Execution finished successfully. Stay in 0500; open Dashboard when ready.' TYPE 'S'.
  ELSE.
    MESSAGE 'Execution queue still has pending READY group(s). Stay in 0500 or retry/refresh.' TYPE 'S' DISPLAY LIKE 'W'.
  ENDIF.
ENDFORM.
*<<< END FORM z16_after_0500_execute

*>>> FORM z16_0560_retry_to_0500 - moved from Z_BDC_MASS_PO_ENTRY_F01_BUP

FORM z16_0560_retry_to_0500.
  DATA lt_retry TYPE ty_t_staging_alv.
  DATA ls_retry TYPE ty_staging_alv.

  IF gt_exec_scope_0500 IS NOT INITIAL.
    lt_retry = gt_exec_scope_0500.
  ELSE.
    LOOP AT gt_staging_alv INTO ls_retry
      WHERE status = gc_st_error OR status = 'WARNING' OR status = 'SKIPPED'.
      ls_retry-status = gc_st_ready.
      APPEND ls_retry TO lt_retry.
    ENDLOOP.
  ENDIF.

  IF lt_retry IS INITIAL.
    MESSAGE 'No retryable ERROR/WARNING/SKIPPED group found.' TYPE 'S' DISPLAY LIKE 'W'.
    RETURN.
  ENDIF.

  LOOP AT lt_retry ASSIGNING FIELD-SYMBOL(<ls_retry>).
    <ls_retry>-status = gc_st_ready.
    <ls_retry>-error_msg = 'Queued for retry from 0560'.
    <ls_retry>-last_error = <ls_retry>-error_msg.
  ENDLOOP.

  gt_exec_scope_0500 = lt_retry.
  gv_exec_scope_ready = abap_true.
  gv_exec_scope_0500  = 'RETRY'.
  gv_exec_scope_text  = 'Retry queue from 0560'.
  READ TABLE lt_retry INTO ls_retry INDEX 1.
  IF sy-subrc = 0.
    txtgv_exec_session = ls_retry-session_id.
  ENDIF.

  MESSAGE |Retry queue prepared: { lines( lt_retry ) } group(s). Returning to 0500.| TYPE 'S'.
  CALL SCREEN 0500.
ENDFORM.
*<<< END FORM z16_0560_retry_to_0500

*>>> FORM z16_0560_refresh - moved from Z_BDC_MASS_PO_ENTRY_F01_BUP

FORM z16_0560_refresh.
  PERFORM prepare_alv_0400.
  PERFORM build_exec_cockpit.
  MESSAGE '0560 retry/mass-correction worklist refreshed.' TYPE 'S'.
ENDFORM.
*<<< END FORM z16_0560_refresh
