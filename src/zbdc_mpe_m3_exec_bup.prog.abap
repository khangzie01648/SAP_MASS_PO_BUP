
*& Include ZBDC_MPE_M3_EXEC_BUP
*& Purpose Generic BDCDATA execution through CT and SM35
*& V17.7 cleanup only: dead reset-era declarations/comments removed.

TYPES ty_t_bdcmsgcoll_nav TYPE STANDARD TABLE OF bdcmsgcoll WITH DEFAULT KEY.

"expected flattened executable stream for the currently open SM35
"session. It is reset for every BDC_OPEN_GROUP and compared with SAP's exact
"stored queue object after BDC_CLOSE_GROUP. No business data is persisted here.
DATA: gt_z488_sm35_expected TYPE ty_t_async_bdcdata,
      gv_z488_sm35_fidelity_ok TYPE abap_bool.

"explicit CT side-effect boundary for Screen 0500. A READY group
"after EXECUTE_BDC_ENGINE does not prove that CALL TRANSACTION actually ran;
"profile/readiness gates can intentionally return before SAP replay.
DATA: gv_z579_ct_started     TYPE abap_bool,
      gv_z579_pre_ct_message TYPE string.

"onboarding certification is an explicit UI action, not a production
"Execute Now side effect. TESTING/PENDING_TEST may enter the live CT proof
"path only while this short-lived flag is owned by CERT0500.

"freeze the visible CT display/update choice once at the Execute Now
"command boundary. No lower layer may re-read radio globals and silently
"switch N/E/A while the same physical execution is in progress.
DATA: gv_z597_ctu_frozen TYPE abap_bool,
      gv_z597_ct_mode    TYPE c LENGTH 1,
      gv_z597_ct_upd     TYPE c LENGTH 1,
      gv_z597_ct_bsize   TYPE i.

"Transport-only diagnostic shared by the live AI/error/navigation paths.
"It never contains the endpoint URL/API key or business-row payload; only
"bounded HTTP/schema status text.
DATA gv_z619_ai_http_diag TYPE string.

*& single source of truth for CTU display/update policy

FORM get_ctu_policy
  CHANGING cv_mode    TYPE c
           cv_upd     TYPE c
           cv_bsize   TYPE i
           cv_ok      TYPE abap_bool
           cv_message TYPE string.

  DATA: lv_mem_exec  TYPE char30,
        lv_mem_mode  TYPE char1,
        lv_mem_upd   TYPE char1,
        lv_mem_subrc TYPE sy-subrc,
        lv_norm      TYPE string.

  CLEAR: cv_mode, cv_upd, cv_bsize, cv_ok, cv_message,
         lv_mem_exec, lv_mem_mode, lv_mem_upd, lv_norm.

  IMPORT zexec = lv_mem_exec
         zmode = lv_mem_mode
         zupd  = lv_mem_upd
    FROM MEMORY ID 'ZBDC_CTU_POLICY'.
  lv_mem_subrc = sy-subrc.

  IF lv_mem_subrc = 0
     AND lv_mem_exec = gc_mode_call
     AND ( lv_mem_mode = 'N' OR lv_mem_mode = 'E' OR lv_mem_mode = 'A' )
     AND ( lv_mem_upd = 'S' OR lv_mem_upd = 'A' ).
    cv_mode = lv_mem_mode.
    cv_upd  = lv_mem_upd.

    PERFORM parse_pos_int
      USING    txtp_batch_size 'Batch size'
      CHANGING cv_bsize cv_ok cv_message lv_norm.
    IF cv_ok = abap_true.
      txtp_batch_size = lv_norm.
    ENDIF.
    RETURN.
  ENDIF.

 "Legacy/fallback entry points that never visited Screen 0300 still use the
 "validated radio reader. Once read, publish the same canonical memory
 "snapshot so every lower layer observes the identical N/E/A choice.
  PERFORM get_runtime_options
    CHANGING cv_mode cv_upd cv_bsize cv_ok cv_message.
  IF cv_ok = abap_true.
    lv_mem_exec = gc_mode_call.
    lv_mem_mode = cv_mode.
    lv_mem_upd  = cv_upd.
    EXPORT zexec = lv_mem_exec
           zmode = lv_mem_mode
           zupd  = lv_mem_upd
      TO MEMORY ID 'ZBDC_CTU_POLICY'.
  ENDIF.
ENDFORM.

* LEGACY ONLY - DO NOT USE FOR OFFICIAL MULTI-TCODE FLOW.
* Official Execute Mode uses EXECUTE_BDC_ENGINE:
* Frozen ZBDC_SCRIPT_BUP/ZBDC_SCT_VER_BUP + exact mapping/session -> BDCDATA.

FORM open_batch_group
  USING    pv_group   TYPE apqi-groupid
  CHANGING cv_subrc   TYPE i
           cv_attempt TYPE i
           cv_reason  TYPE string
           cv_qid     TYPE apqi-qid.

  CLEAR: cv_subrc, cv_attempt, cv_reason, cv_qid.
  cv_attempt = 1.

 "One explicit SAP Batch Input session creation attempt. There is no hidden
 "retry loop in the executor; a technical OPEN failure is returned as-is.
  CALL FUNCTION 'BDC_OPEN_GROUP'
    EXPORTING
      client = sy-mandt
      group  = pv_group
      user   = sy-uname
      keep   = 'X'
    IMPORTING
      qid    = cv_qid
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
  cv_subrc = sy-subrc.

  CASE cv_subrc.
    WHEN 0.
      cv_reason = 'BDC_OPEN_GROUP_OK'.
    WHEN 1.  cv_reason = 'CLIENT_INVALID'.
    WHEN 2.  cv_reason = 'DESTINATION_INVALID'.
    WHEN 3.  cv_reason = 'GROUP_INVALID'.
    WHEN 4.  cv_reason = 'GROUP_LOCKED'.
    WHEN 5.  cv_reason = 'HOLDDATE_INVALID'.
    WHEN 6.  cv_reason = 'INTERNAL_ERROR'.
    WHEN 7.  cv_reason = 'QUEUE_ERROR'.
    WHEN 8.  cv_reason = 'SESSION_RUNNING'.
    WHEN 9.  cv_reason = 'SYSTEM_LOCK'.
    WHEN 10. cv_reason = 'USER_INVALID'.
    WHEN OTHERS. cv_reason = 'BDC_OPEN_GROUP_OTHER_ERROR'.
  ENDCASE.
ENDFORM.

*& Insert one transaction into an open session with safe retry

FORM insert_batch_group
  USING    pv_tcode   TYPE sy-tcode
           pt_bdc     TYPE ty_t_async_bdcdata
  CHANGING cv_subrc   TYPE i
           cv_attempt TYPE i
           cv_reason  TYPE string.

  CLEAR: cv_subrc, cv_attempt, cv_reason.
  cv_attempt = 1.

 "Exactly one BDC_INSERT for exactly one prepared business group. Both CT
 "and BISM consume the same PT_BDC bytes; the executor never rebuilds them.
  CALL FUNCTION 'BDC_INSERT'
    EXPORTING
      tcode     = pv_tcode
    TABLES
      dynprotab = pt_bdc
    EXCEPTIONS
      internal_error    = 1
      not_open          = 2
      queue_error       = 3
      tcode_invalid     = 4
      printing_invalid  = 5
      posting_invalid   = 6
      OTHERS            = 7.
  cv_subrc = sy-subrc.

  CASE cv_subrc.
    WHEN 0. cv_reason = 'BDC_INSERT_OK'.
    WHEN 1. cv_reason = 'INTERNAL_ERROR'.
    WHEN 2. cv_reason = 'SESSION_NOT_OPEN'.
    WHEN 3. cv_reason = 'QUEUE_ERROR'.
    WHEN 4. cv_reason = 'TCODE_INVALID'.
    WHEN 5. cv_reason = 'PRINTING_INVALID'.
    WHEN 6. cv_reason = 'POSTING_INVALID'.
    WHEN OTHERS. cv_reason = 'BDC_INSERT_OTHER_ERROR'.
  ENDCASE.
ENDFORM.

*& Read back one closed SAP Batch Input queue and verify fidelity

*& Resolve frozen CALL TRANSACTION COMMIT boundary

*& CTURACOM is Script metadata, not transaction logic:
*& CONTINUE -> CTU_PARAMS-RACOMMIT = X
*& TERMINATE -> standard CALL TRANSACTION boundary (RACOMMIT = space)

*& Compatibility rule for contracts created before
*& PENDING_TEST/non-certified: use TERMINATE because Guided Recording
*& previously used the standard BDC_RECORD_TRANSACTION COMMIT boundary.
*& already CERTIFIED: preserve historical runtime behavior (CONTINUE) so a
*& proven immutable production contract is not silently changed.
*& No TCODE, PROGRAM, DYNPRO or business field is hardcoded.

FORM resolve_ct_racommit
  USING    iv_script_id   TYPE zbdc_script_bup-script_id
           iv_cert_status TYPE zbdc_cert_bup-cert_status
  CHANGING cv_racommit    TYPE c
           cv_source      TYPE string.

  DATA lv_cfg TYPE zbdc_config_bup-config_value.

  CLEAR: cv_racommit, cv_source, lv_cfg.

  IF iv_script_id IS NOT INITIAL.
    PERFORM get_script_cfg
      USING    iv_script_id 'CTURACOM'
      CHANGING lv_cfg.
  ENDIF.

  TRANSLATE lv_cfg TO UPPER CASE.
  CONDENSE lv_cfg NO-GAPS.

  IF lv_cfg = 'CONTINUE'.
    cv_racommit = 'X'.
    cv_source = 'RECORDED_CONTINUE'.
  ELSEIF lv_cfg = 'TERMINATE'.
    CLEAR cv_racommit.
    cv_source = 'RECORDED_TERMINATE'.
  ELSE.
    CLEAR cv_racommit.
    cv_source = 'MISSING'.
  ENDIF.
ENDFORM.

*& CONTRACT_BOUNDARY_V2 - frozen CALL TRANSACTION SY-BINPT policy

*& CTUNOBIN is exact Script acquisition metadata, never transaction logic:
*& ONLINE -> CTU_PARAMS-NOBINPT = X (SY-BINPT stays initial)
*& BATCH -> standard CTU batch semantics (SY-BINPT = X)
*& Missing/unknown metadata fails before SAP starts. Runtime never probes,
*& retries with another environment, or injects a missing dynpro/OKCODE.

FORM resolve_ct_nobinpt
  USING    iv_script_id   TYPE zbdc_script_bup-script_id
           iv_cert_status TYPE zbdc_cert_bup-cert_status
  CHANGING cv_nobinpt     TYPE c
           cv_auto        TYPE abap_bool
           cv_source      TYPE string.

  DATA: lv_cfg    TYPE zbdc_config_bup-config_value,
        lv_origin TYPE zbdc_config_bup-config_value.

  CLEAR: cv_nobinpt, cv_auto, cv_source, lv_cfg, lv_origin.

  IF iv_script_id IS NOT INITIAL.
    PERFORM get_script_cfg
      USING    iv_script_id 'RAWSOURCE'
      CHANGING lv_origin.
    PERFORM get_script_cfg
      USING    iv_script_id 'CTUNOBIN'
      CHANGING lv_cfg.
  ENDIF.

  TRANSLATE lv_origin TO UPPER CASE.
  TRANSLATE lv_cfg TO UPPER CASE.
  CONDENSE lv_origin NO-GAPS.
  CONDENSE lv_cfg NO-GAPS.

 "compatibility: every Guided Start Recording in this codebase calls
 "BDC_RECORD_TRANSACTION with CTU_PARAMS-NOBINPT initial. Older code wrote
 "the opposite ONLINE marker afterward. SAP_APQI provenance therefore proves
 "the standard batch-input SY-BINPT semantics regardless of that stale marker.
  IF lv_origin = 'SAP_APQI'.
    CLEAR cv_nobinpt.
    cv_source = 'START_RECORDING_STANDARD'.
    RETURN.
  ENDIF.

  IF lv_cfg = 'ONLINE'.
    cv_nobinpt = 'X'.
    cv_source = 'RECORDED_ONLINE'.
  ELSEIF lv_cfg = 'BATCH'.
    CLEAR cv_nobinpt.
    cv_source = 'RECORDED_BATCH'.
  ELSE.
 "Imported SHDB recordings have no separate CTU flag. Use SAP standard
 "CALL TRANSACTION batch-input semantics; never guess an online retry.
    CLEAR cv_nobinpt.
    cv_source = 'SAP_STANDARD'.
  ENDIF.
ENDFORM.

*& Generic CT dynpro-mismatch diagnostic (SAP message 00 344)

*& 00-344 is a standard Batch Input technical message, not transaction logic.
*& The diagnostic never changes execution; it only explains whether the dynpro
*& SAP requested was absent from, or merely out-of-sequence with, the prepared
*& immutable BDCDATA stream.

*& /Last-gate BDCDATA sanitizer before CTU / SM35 insert

*& Build the exact selected document keys before DB chunk reads

FORM build_engine_keys
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

*& Read one true database chunk for only the selected group keys

FORM load_engine_chunk
  USING    pt_keys    TYPE ty_t_engine_group_key
  CHANGING ct_chunk   TYPE ty_t_staging_alv
           cv_ok      TYPE abap_bool
           cv_message TYPE string.

  DATA: lt_rec_keys TYPE ty_t_engine_group_key,
        lt_row_keys TYPE ty_t_engine_group_key,
        lt_db       TYPE STANDARD TABLE OF zbdc_staging_bup,
        ls_db       TYPE zbdc_staging_bup,
        ls_key      TYPE ty_engine_group_key,
        ls_row      TYPE ty_staging_alv,
        lv_found    TYPE abap_bool.

  CLEAR: cv_ok, cv_message.
  REFRESH: ct_chunk, lt_rec_keys, lt_row_keys.

  IF pt_keys IS INITIAL.
    cv_message = 'Execution chunk has no exact persisted group key.'.
    RETURN.
  ENDIF.

  LOOP AT pt_keys INTO ls_key.
    IF ls_key-session_id IS INITIAL.
      cv_message = 'Execution chunk contains a key without session identity.'.
      RETURN.
    ENDIF.
    IF ls_key-record_key IS INITIAL.
      IF ls_key-row_index IS INITIAL.
        cv_message = |Execution key for session { ls_key-session_id } has neither record key nor row index.|.
        RETURN.
      ENDIF.
      APPEND ls_key TO lt_row_keys.
    ELSE.
      APPEND ls_key TO lt_rec_keys.
    ENDIF.
  ENDLOOP.

  IF lt_rec_keys IS NOT INITIAL.
    SELECT * FROM zbdc_staging_bup
      INTO TABLE @lt_db
      FOR ALL ENTRIES IN @lt_rec_keys
      WHERE session_id = @lt_rec_keys-session_id
        AND record_key = @lt_rec_keys-record_key.
    LOOP AT lt_db INTO ls_db.
      CLEAR ls_row.
      MOVE-CORRESPONDING ls_db TO ls_row.
      APPEND ls_row TO ct_chunk.
    ENDLOOP.
  ENDIF.

  IF lt_row_keys IS NOT INITIAL.
    REFRESH lt_db.
    SELECT * FROM zbdc_staging_bup
      INTO TABLE @lt_db
      FOR ALL ENTRIES IN @lt_row_keys
      WHERE session_id = @lt_row_keys-session_id
        AND row_index  = @lt_row_keys-row_index.
    LOOP AT lt_db INTO ls_db.
      CLEAR ls_row.
      MOVE-CORRESPONDING ls_db TO ls_row.
      APPEND ls_row TO ct_chunk.
    ENDLOOP.
  ENDIF.

  SORT ct_chunk BY session_id record_key row_index.
  DELETE ADJACENT DUPLICATES FROM ct_chunk
    COMPARING session_id row_index.

 "All execution input must exist in persisted staging. Frontend rows are
 "never substituted for a missing database identity.
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
      REFRESH ct_chunk.
      cv_message =
        |Persisted staging is missing requested group { ls_key-session_id }/{ ls_key-record_key }/{ ls_key-row_index }.|.
      RETURN.
    ENDIF.
  ENDLOOP.

  PERFORM check_process_ctx
    USING    ct_chunk
    CHANGING cv_ok cv_message.
ENDFORM.

*& Process all document groups contained in one loaded DB chunk

FORM process_eng_chunk
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
      PERFORM progress_after_group USING lt_group.

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
    PERFORM progress_after_group USING lt_group.
    IF chkp_stop_on_error = 'X' AND cv_err > lv_err_before.
      g_stop_flag = 'X'.
    ENDIF.
  ENDIF.
ENDFORM.

*& EXECUTE_BDC_ENGINE - single entry point cua Muc 2
*& PT_PROCESS: cac dong da qua validation tren Screen 0400
*& Design:
*& 1. Runtime options from configuration
*& 2. Load frozen versioned Script ID and split PRE/ITEM/POST
*& 3. Load mapping profile tu ZBDC_MAPPING_BUP
*& 4. Group theo RECORD_KEY/business group -> 1 group = 1 SAP document
*& 5. Run CALL TRANSACTION hoac Batch Input Session
*& 6. Commit theo chunk BATCH_SIZE

FORM check_process_ctx
  USING    pt_process LIKE gt_staging_alv
  CHANGING cv_ok      TYPE abap_bool
           cv_message TYPE string.

  TYPES: BEGIN OF ty_ctx,
           session_id    TYPE zbdc_session_bup-session_id,
           tcode         TYPE zbdc_session_bup-tcode,
           profile_name  TYPE zbdc_session_bup-profile_name,
           profile_ver   TYPE zbdc_session_bup-profile_ver,
           script_id     TYPE zbdc_session_bup-script_id,
           contract_hash TYPE zbdc_session_bup-contract_hash,
         END OF ty_ctx.

  DATA: lt_sid TYPE SORTED TABLE OF zbdc_staging_bup-session_id
               WITH UNIQUE KEY table_line,
        ls_ctx TYPE ty_ctx,
        ls_ref TYPE ty_ctx.

  CLEAR: cv_ok, cv_message.
  IF pt_process IS INITIAL.
    cv_message = 'Execution scope is empty.'.
    RETURN.
  ENDIF.

  LOOP AT pt_process INTO DATA(ls_row).
    IF ls_row-status <> gc_st_ready.
      cv_message =
        |Execution scope contains non-READY row { ls_row-session_id }/{ ls_row-row_index } ({ ls_row-status }).|.
      RETURN.
    ENDIF.
    IF ls_row-session_id IS INITIAL.
      cv_message = 'Execution scope contains a row without session identity.'.
      RETURN.
    ENDIF.
    INSERT ls_row-session_id INTO TABLE lt_sid.
  ENDLOOP.

  LOOP AT lt_sid INTO DATA(lv_sid).
    CLEAR ls_ctx.
    SELECT SINGLE session_id, tcode, profile_name, profile_ver,
                  script_id, contract_hash
      FROM zbdc_session_bup
      INTO CORRESPONDING FIELDS OF @ls_ctx
      WHERE session_id = @lv_sid.
    IF sy-subrc <> 0 OR
       ls_ctx-tcode IS INITIAL OR
       ls_ctx-profile_name IS INITIAL OR
       ls_ctx-profile_ver IS INITIAL OR
       ls_ctx-script_id IS INITIAL OR
       ls_ctx-contract_hash IS INITIAL.
      cv_message = |Session { lv_sid } has no complete frozen TCODE/Profile/Version/Script/Hash execution context.|.
      RETURN.
    ENDIF.

    IF ls_ref-session_id IS INITIAL.
      ls_ref = ls_ctx.
    ELSEIF ls_ctx-tcode         <> ls_ref-tcode OR
           ls_ctx-profile_name  <> ls_ref-profile_name OR
           ls_ctx-profile_ver   <> ls_ref-profile_ver OR
           ls_ctx-script_id     <> ls_ref-script_id OR
           ls_ctx-contract_hash <> ls_ref-contract_hash.
      cv_message =
        |Execution scope mixes contracts ({ ls_ref-session_id } and { ls_ctx-session_id }).|.
      RETURN.
    ENDIF.
  ENDLOOP.

  LOOP AT pt_process INTO ls_row.
    IF ls_row-tcode <> ls_ref-tcode.
      cv_message =
        |Execution row TCODE { ls_row-tcode } differs from frozen TCODE { ls_ref-tcode }.|.
      RETURN.
    ENDIF.
  ENDLOOP.

  cv_ok = abap_true.
  cv_message =
    |Execution scope verified: { ls_ref-tcode }/{ ls_ref-profile_name } v{ ls_ref-profile_ver }.|.
ENDFORM.

FORM EXECUTE_BDC_ENGINE USING PT_PROCESS   LIKE GT_STAGING_ALV
                              PV_EXEC_MODE TYPE CSEQUENCE.
  DATA: lt_sorted  TYPE ty_t_staging_alv,
        lt_context TYPE ty_t_staging_alv,
        ls_row     TYPE ty_staging_alv,
        lv_sid     TYPE zbdc_staging_bup-session_id,
        lv_tcode   TYPE zbdc_prof_bup-tcode,
        lv_profile TYPE zbdc_prof_bup-profile_name,
        lv_ver     TYPE zbdc_prof_bup-profile_ver,
        lv_found   TYPE abap_bool,
        lv_scope_ok TYPE abap_bool,
        lv_scope_msg TYPE string.

  IF pt_process IS INITIAL.
    MESSAGE s502(zbdc) DISPLAY LIKE 'W'.
    RETURN.
  ENDIF.

  PERFORM check_process_ctx
    USING    pt_process
    CHANGING lv_scope_ok lv_scope_msg.
  IF lv_scope_ok <> abap_true.
    IF pv_exec_mode = gc_mode_batch.
      gv_last_sm35_action = lv_scope_msg.
    ENDIF.
    PERFORM userize_ui_message USING lv_scope_msg CHANGING gv_ui_message.
    MESSAGE gv_ui_message TYPE 'S' DISPLAY LIKE 'E'.
    RETURN.
  ENDIF.

  lt_sorted = pt_process.
  SORT lt_sorted BY session_id tcode row_index.

  LOOP AT lt_sorted INTO ls_row.
    IF lt_context IS NOT INITIAL AND
       ( ls_row-session_id <> lv_sid OR ls_row-tcode <> lv_tcode ).
      CLEAR: lv_profile, lv_ver, lv_found.
      PERFORM resolve_session_context
        USING    lv_sid
        CHANGING lv_tcode lv_profile lv_ver lv_found.
      IF lv_found = abap_true.
        PERFORM execute_bdc_context
          USING lt_context pv_exec_mode lv_tcode lv_profile lv_ver.
      ELSE.
        DATA(lv_ctx_msg1) = |Session { lv_sid } has no persisted mapping context; execution was blocked.|.
        PERFORM fail_process_scope USING lt_context lv_tcode lv_ctx_msg1.
        PERFORM userize_ui_message USING lv_ctx_msg1 CHANGING gv_ui_message.
        MESSAGE gv_ui_message TYPE 'S' DISPLAY LIKE 'E'.
      ENDIF.
      REFRESH lt_context.
    ENDIF.

    IF lt_context IS INITIAL.
      lv_sid   = ls_row-session_id.
      lv_tcode = ls_row-tcode.
    ENDIF.
    APPEND ls_row TO lt_context.
  ENDLOOP.

  IF lt_context IS NOT INITIAL.
    CLEAR: lv_profile, lv_ver, lv_found.
    PERFORM resolve_session_context
      USING    lv_sid
      CHANGING lv_tcode lv_profile lv_ver lv_found.
    IF lv_found = abap_true.
      PERFORM execute_bdc_context
        USING lt_context pv_exec_mode lv_tcode lv_profile lv_ver.
    ELSE.
      MESSAGE s503(zbdc) WITH lv_sid DISPLAY LIKE 'E'.
    ENDIF.
  ENDIF.
ENDFORM.

*& Legacy technical metadata projection (memory only)

*& Compatibility rule for already-certified contracts produced by older
*& compiler revisions:
*& Never change persisted Script/Profile/Certification/Hash.
*& Never add/remove/reorder a captured step.
*& Never change Program/Dynpro/Field/STATIC_VALUE/ROW_TYPE.
*& Only normalize VALUE_TYPE/SOURCE_COLUMN for SAP technical controls by
*& reusing Z367. The resulting projection must pass the normal Z36 gate.
*& No RAW snapshot/link is required and no business Mapping is inferred.

*& Runtime contract gate

*& Auto-prepare MAPPED profile for controlled TESTING replay

*& Certification requires terminal protocol + generic DB verifier

*& A synchronous terminal SAP success protocol may bind the success message,
*& but certification is promoted only when the same runtime contract owns a
*& generic DDIC/DB verifier. The verifier itself is discovered structurally;
*& no TCODE/table/field rule is hardcoded here.

*& Seal a side-effected onboarding certification

*& Once the controlled PENDING_TEST CALL TRANSACTION may have committed a
*& business object, a failed proof/promotion must never be replayed blindly.
*& Keep CERT_STATUS=PENDING_TEST for audit, but move LAST_TEST_STATUS away
*& from PENDING_TEST so the next Run is blocked until explicit review/reset.

*& Runtime setup gate classifier (generic, no TCODE hardcode)

FORM is_setup_msg
  USING    iv_msg   TYPE csequence
  CHANGING cv_setup TYPE abap_bool.

  DATA lv_msg TYPE string.

  CLEAR cv_setup.
  lv_msg = iv_msg.
  TRANSLATE lv_msg TO UPPER CASE.
  CONDENSE lv_msg.

  IF lv_msg CS 'PROFILE SETUP INCOMPLETE' OR
     lv_msg CS 'PROFILE SETUP' OR
     lv_msg CS 'PROFILE IS NOT CERTIFIED' OR
     lv_msg CS 'PROFILE IS MAPPED' OR
     lv_msg CS 'PROFILE IS DRAFT' OR
     lv_msg CS 'EXECUTION IS BLOCKED' OR
     lv_msg CS 'FROZEN CERTIFIED SESSION CONTRACT' OR
     lv_msg CS 'FROZEN SESSION CONTRACT' OR
     lv_msg CS 'CURRENT PROFILE CONTRACT' OR
     lv_msg CS 'CERTIFICATION RECORD' OR
     lv_msg CS 'MATCHING CERTIFIED' OR
     lv_msg CS 'MATCHING PENDING_TEST' OR
     lv_msg CS 'IMMUTABLE SCRIPT HEADER' OR
     lv_msg CS 'CONTRACT HASH' OR
     lv_msg CS 'RUNTIME CERTIFICATE' OR
     lv_msg CS 'OBJECT PROOF CONFIG' OR
     lv_msg CS 'HIDDEN OBJECT TRACE PROOF' OR
     lv_msg CS 'TRACE_TABLE' OR
     lv_msg CS 'TRACE_FIELD' OR
     lv_msg CS 'OBJECT_FIELD' OR
     lv_msg CS 'HIDDEN OBJECT CORRELATION'.
    cv_setup = abap_true.
  ENDIF.
ENDFORM.

*& Persist real CT pre-run blockers instead of silent READY

FORM fail_process_scope
  USING pt_process TYPE ty_t_staging_alv
        pv_tcode   TYPE sy-tcode
        pv_msg     TYPE csequence.

  DATA: ls_first TYPE ty_staging_alv,
        lv_tcode TYPE sy-tcode,
        lv_msg   TYPE string,
        lv_setup TYPE abap_bool.

  IF pt_process IS INITIAL.
    RETURN.
  ENDIF.

  lv_tcode = pv_tcode.
  IF lv_tcode IS INITIAL.
    READ TABLE pt_process INTO ls_first INDEX 1.
    IF sy-subrc = 0.
      lv_tcode = ls_first-tcode.
    ENDIF.
  ENDIF.

  lv_msg = pv_msg.
  IF lv_msg IS INITIAL.
    MESSAGE ID 'ZBDC' TYPE 'S' NUMBER '891' INTO lv_msg.
  ENDIF.

 "expose the real pre-SAP blocker to Screen 0500. This does not
 "change staging semantics; z96 still persists terminal blockers as before.
  IF p_bdc_mode = gc_mode_call AND gv_z579_ct_started <> abap_true.
    gv_z579_pre_ct_message = lv_msg.
  ENDIF.

  PERFORM is_setup_msg
    USING    lv_msg
    CHANGING lv_setup.
  IF lv_setup = abap_true.
    DATA(lv_zm892_784_1) = |{ lv_msg }|.
    MESSAGE ID 'ZBDC' TYPE 'S' NUMBER '892'
      WITH lv_zm892_784_1 INTO lv_msg.
  ENDIF.

  IF p_bdc_mode = gc_mode_batch.
    gv_last_sm35_action = lv_msg.
  ENDIF.

  PERFORM save_synthetic_engine_log
    USING pt_process lv_tcode 0 gc_st_error lv_msg '' 'X'.
  PERFORM update_group_result USING pt_process gc_st_error lv_msg ''.
  PERFORM update_exec_counters USING pt_process.
  COMMIT WORK AND WAIT.
ENDFORM.

FORM execute_bdc_context
  USING PT_PROCESS   TYPE ty_t_staging_alv
        PV_EXEC_MODE TYPE csequence
        PV_TCODE     TYPE sy-tcode
        PV_PROFILE   TYPE zbdc_prof_bup-profile_name
        PV_VER       TYPE zbdc_prof_bup-profile_ver.
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
        LV_BIGROUP TYPE APQI-GROUPID,
        LV_DEMO_DATE_836 TYPE SY-DATUM,
        LV_DEMO_TIME_836 TYPE SY-UZEIT,
        LV_OPEN_QID TYPE APQI-QID,
        LV_MSG     TYPE STRING,
        LV_PROFILE_OK TYPE ABAP_BOOL,
        LV_CONTRACT_OK TYPE ABAP_BOOL,
        LV_CONTRACT_MSG TYPE STRING,
        LV_REQUESTED_ENGINE TYPE CHAR30,
        LV_RUNTIME_OK       TYPE ABAP_BOOL,
        LV_RUNTIME_MSG      TYPE STRING,
        LV_STD_OK           TYPE ABAP_BOOL,
        LV_STD_KIND         TYPE CHAR20,
        LV_STD_MSG          TYPE STRING,
        LV_CHUNK_OK         TYPE ABAP_BOOL,
        LV_CHUNK_MSG        TYPE STRING,
        LV_BSIZE_NORM       TYPE STRING,
        LS_APQI_VERIFY      TYPE APQI,
        LV_APQI_FOUND       TYPE ABAP_BOOL.

  IF PT_PROCESS IS INITIAL.
    MESSAGE s504(zbdc) DISPLAY LIKE 'W'.
    RETURN.
  ENDIF.

 "The explicit execution command owns the engine. Runtime options are read
 "from validated CTU preferences only; no persisted reload or hidden override.
  PERFORM canon_exec_mode
    USING    PV_EXEC_MODE
    CHANGING LV_REQUESTED_ENGINE LV_RUNTIME_OK LV_RUNTIME_MSG.
  IF LV_RUNTIME_OK <> ABAP_TRUE.
    PERFORM fail_process_scope USING PT_PROCESS PV_TCODE LV_RUNTIME_MSG.
    PERFORM userize_ui_message USING LV_RUNTIME_MSG CHANGING gv_ui_message.
    MESSAGE gv_ui_message TYPE 'S' DISPLAY LIKE 'E'.
    RETURN.
  ENDIF.

  CLEAR: LV_RUNTIME_OK, LV_RUNTIME_MSG, LV_MODE, LV_UPD,
         LV_BSIZE, LV_BSIZE_NORM.
  IF LV_REQUESTED_ENGINE = GC_MODE_CALL.
 "consume the command-boundary CTU snapshot when present.
 "Do not re-read radio globals inside the executor.
    IF gv_z597_ctu_frozen = abap_true.
      LV_MODE       = gv_z597_ct_mode.
      LV_UPD        = gv_z597_ct_upd.
      LV_BSIZE      = gv_z597_ct_bsize.
      LV_RUNTIME_OK = abap_true.
      CLEAR LV_RUNTIME_MSG.
    ELSE.
      PERFORM get_ctu_policy
        CHANGING LV_MODE LV_UPD LV_BSIZE LV_RUNTIME_OK LV_RUNTIME_MSG.
    ENDIF.
  ELSE.
 "True BISM has no CALL TRANSACTION MODE/UPDATE semantics. Only batch size
 "is shared as an engine chunking option.
    PERFORM parse_pos_int
      USING    TXTP_BATCH_SIZE 'Batch size'
      CHANGING LV_BSIZE LV_RUNTIME_OK LV_RUNTIME_MSG LV_BSIZE_NORM.
    IF LV_RUNTIME_OK = ABAP_TRUE.
      TXTP_BATCH_SIZE = LV_BSIZE_NORM.
    ENDIF.
  ENDIF.
  IF LV_RUNTIME_OK <> ABAP_TRUE.
    PERFORM fail_process_scope USING PT_PROCESS PV_TCODE LV_RUNTIME_MSG.
    PERFORM userize_ui_message USING LV_RUNTIME_MSG CHANGING gv_ui_message.
    MESSAGE gv_ui_message TYPE 'S' DISPLAY LIKE 'E'.
    RETURN.
  ENDIF.

  P_BDC_MODE = LV_REQUESTED_ENGINE.

 "Batch Input Session is a separate executor. The disabled
 "runtime configuration BDC/Update radios may still contain dynpro values, but a
 "BISM run must never consume those values. LV_MODE/LV_UPD are kept only
 "for the CALL TRANSACTION executor; true BISM only creates a BI session
 "with BDC_OPEN_GROUP / BDC_INSERT / BDC_CLOSE_GROUP.

  READ TABLE pt_process INTO ls_row INDEX 1.
  lv_tcode = pv_tcode.
  IF lv_tcode IS INITIAL OR pv_profile IS INITIAL OR pv_ver IS INITIAL.
    MESSAGE ID 'ZBDC' TYPE 'S' NUMBER '893' INTO lv_msg.
    PERFORM fail_process_scope USING pt_process lv_tcode lv_msg.
    PERFORM userize_ui_message USING lv_msg CHANGING gv_ui_message.
    MESSAGE gv_ui_message TYPE 'S' DISPLAY LIKE 'E'.
    RETURN.
  ENDIF.

 "profiles created before the standard-only guard must not bypass
 "the rule at execution time. Repository ownership is checked generically;
 "recordability remains the immutable script/recorder contract, not TSTC.
  CLEAR: LV_STD_OK, LV_STD_KIND, LV_STD_MSG.
  PERFORM check_standard_tcode
    USING    LV_TCODE
    CHANGING LV_STD_OK LV_STD_KIND LV_STD_MSG.
  IF LV_STD_OK <> ABAP_TRUE.
    LV_MSG = LV_STD_MSG.
    PERFORM fail_process_scope USING PT_PROCESS LV_TCODE LV_MSG.
    PERFORM userize_ui_message USING LV_MSG CHANGING gv_ui_message.
    MESSAGE gv_ui_message TYPE 'S' DISPLAY LIKE 'E'.
    RETURN.
  ENDIF.

  p_transaction     = lv_tcode.
  txtp_profile_name = pv_profile.
  gv_profile_ver    = pv_ver.
 "Target-transaction authorization is a hard execution boundary.
  AUTHORITY-CHECK OBJECT 'S_TCODE'
    ID 'TCD' FIELD LV_TCODE.
  IF SY-SUBRC <> 0.
    DATA(lv_zm894_927_1) = |{ SY-UNAME }|.
    DATA(lv_zm894_927_2) = |{ LV_TCODE }|.
    MESSAGE ID 'ZBDC' TYPE 'S' NUMBER '894'
      WITH lv_zm894_927_1 lv_zm894_927_2 INTO LV_MSG.
    PERFORM fail_process_scope USING PT_PROCESS LV_TCODE LV_MSG.
    PERFORM userize_ui_message USING LV_MSG CHANGING gv_ui_message.
    MESSAGE gv_ui_message TYPE 'S' DISPLAY LIKE 'E'.
    RETURN.
  ENDIF.

  PERFORM LOAD_SCRIPT_DEFINITION
    USING    LV_TCODE
    CHANGING LT_S_PRE LT_S_ITEM LT_S_POST.

 "The legacy PRE/ITEM/POST projection is no longer an execution gate.
 "The builder loads the current canonical EXEC_RAW/RAW recording directly.

  PERFORM load_mapping_profile_ctx
    USING    lv_tcode pv_profile pv_ver
    CHANGING lt_map.

  IF lt_map IS INITIAL.
    DATA(lv_zm895_945_1) = |{ pv_profile }|.
    DATA(lv_zm895_945_2) = |{ pv_ver }|.
    MESSAGE ID 'ZBDC' TYPE 'S' NUMBER '895'
      WITH lv_zm895_945_1 lv_zm895_945_2 INTO lv_msg.
    PERFORM fail_process_scope USING pt_process lv_tcode lv_msg.
    PERFORM userize_ui_message USING lv_msg CHANGING gv_ui_message.
    MESSAGE gv_ui_message TYPE 'S' DISPLAY LIKE 'E'.
    RETURN.
  ENDIF.

 "CT/BISM normal runtime has no certification gate. Execution readiness is
 "the exact current SHDB recording + Mapping + SAP authorization/options.
  CLEAR: lv_contract_ok, lv_contract_msg.
  lv_contract_ok = abap_true.
  lv_contract_msg = 'CT/BISM normal replay mode: certification gate disabled.'.

 "CONCURRENT-USER LOCK:
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

 "No custom PRE/ITEM/POST execution-plan compiler is used in normal CT/BISM runtime.

 "Build the exact selected document keys before opening SM35. The first
 "real group is compile-only built and validated, so a bad script cannot leave an
 "empty 0-transaction technical session in the user's SM35 list.
  PERFORM build_engine_keys
    USING    PT_PROCESS
    CHANGING LT_KEYS.

  IF lt_keys IS INITIAL.
    MESSAGE ID 'ZBDC' TYPE 'S' NUMBER '896' INTO lv_msg.
    PERFORM fail_process_scope USING pt_process lv_tcode lv_msg.
    PERFORM release_staging_lock USING ls_row-session_id.
    PERFORM userize_ui_message USING lv_msg CHANGING gv_ui_message.
    MESSAGE gv_ui_message TYPE 'S' DISPLAY LIKE 'E'.
    RETURN.
  ENDIF.

 "Run Selected / Run All is production-only. The profile contract
 "was already proven and frozen during onboarding before this point. CT and
 "SM35 only consume that immutable contract; neither executor learns or
 "mutates onboarding metadata from a production business group.

 "Freeze and validate the complete execution scope from persisted READY
 "staging before any SM35 purge/open or CALL TRANSACTION side effect.
  CLEAR: LV_CHUNK_OK, LV_CHUNK_MSG.
  REFRESH LT_PROC.
  PERFORM load_engine_chunk
    USING    LT_KEYS
    CHANGING LT_PROC LV_CHUNK_OK LV_CHUNK_MSG.
  IF LV_CHUNK_OK <> ABAP_TRUE.
    PERFORM fail_process_scope USING PT_PROCESS LV_TCODE LV_CHUNK_MSG.
    PERFORM release_staging_lock USING LS_ROW-SESSION_ID.
    PERFORM userize_ui_message USING LV_CHUNK_MSG CHANGING gv_ui_message.
    MESSAGE gv_ui_message TYPE 'S' DISPLAY LIKE 'E'.
    RETURN.
  ENDIF.
  REFRESH LT_PROC.

 "A new SM35 run must not inherit protocol rows from an older session for
 "the same business group. Purge only SM35 technical logs; keep all normal
 "validation/execution history intact.
  IF P_BDC_MODE = GC_MODE_BATCH.
    LOOP AT LT_KEYS INTO LS_KEY.
      PERFORM purge_sm35_group_log USING LS_KEY.
    ENDLOOP.
    COMMIT WORK AND WAIT.
  ENDIF.

  IF P_BDC_MODE = GC_MODE_BATCH.
    DATA: lv_preflight_ok  TYPE abap_bool,
          lv_preflight_msg TYPE string.

    READ TABLE LT_KEYS INTO LS_KEY INDEX 1.
    REFRESH LT_GROUP.
    PERFORM collect_group_key
      USING    PT_PROCESS LS_KEY
      CHANGING LT_GROUP.

    PERFORM preflight_sm35_group
      USING    LT_GROUP LT_S_PRE LT_S_ITEM LT_S_POST LT_MAP LV_TCODE
      CHANGING lv_preflight_ok lv_preflight_msg.

    REFRESH BDCDATA.
    IF lv_preflight_ok <> abap_true.
      lv_msg = lv_preflight_msg.
      IF lv_msg IS INITIAL.
        MESSAGE ID 'ZBDC' TYPE 'S' NUMBER '897' INTO lv_msg.
      ENDIF.
      PERFORM fail_process_scope USING pt_process lv_tcode lv_msg.
      PERFORM release_staging_lock USING ls_row-session_id.
      PERFORM userize_ui_message USING lv_msg CHANGING gv_ui_message.
      MESSAGE gv_ui_message TYPE 'S' DISPLAY LIKE 'E'.
      RETURN.
    ENDIF.
    DATA: lv_open_subrc   TYPE i,
          lv_open_attempt TYPE i,
          lv_open_reason  TYPE string,
          lv_close_subrc  TYPE i.

    CLEAR: GV_LAST_SM35_GROUP, GV_LAST_SM35_QID,
           GV_LAST_SM35_INSERTED, GV_LAST_SM35_EXPECTED,
           GV_LAST_SM35_JOBNAME, GV_LAST_SM35_JOBCOUNT,
           LV_OPEN_QID.
    REFRESH gt_z488_sm35_expected.
    gv_z488_sm35_fidelity_ok = abap_true.
 "BDC_OPEN_GROUP-GROUP is maximum 12 characters. QID returned by
 "SAP at creation time is the authoritative session identity; GROUP is only
 "the human-readable SM35 name and may legally be reused.
    PERFORM get_demo_now CHANGING LV_DEMO_DATE_836 LV_DEMO_TIME_836.
    CONCATENATE 'ZB' LV_DEMO_DATE_836+4(4) LV_DEMO_TIME_836 INTO LV_BIGROUP.
    PERFORM open_batch_group
      USING    LV_BIGROUP
      CHANGING lv_open_subrc lv_open_attempt lv_open_reason LV_OPEN_QID.

    IF lv_open_subrc <> 0.
      DATA(lv_zm898_1065_1) = |{ lv_open_attempt }|.
      DATA(lv_zm898_1065_2) = |{ lv_open_reason }|.
      DATA(lv_zm898_1065_3) = |{ lv_open_subrc }|.
      MESSAGE ID 'ZBDC' TYPE 'S' NUMBER '898'
        WITH lv_zm898_1065_1 lv_zm898_1065_2 lv_zm898_1065_3
        INTO lv_msg.
      PERFORM fail_process_scope USING pt_process lv_tcode lv_msg.
      PERFORM release_staging_lock USING ls_row-session_id.
      PERFORM userize_ui_message USING lv_msg CHANGING gv_ui_message.
      MESSAGE gv_ui_message TYPE 'S' DISPLAY LIKE 'E'.
      RETURN.
    ENDIF.

    GV_LAST_SM35_GROUP = LV_BIGROUP.
    GV_LAST_SM35_QID   = LV_OPEN_QID.
  ENDIF.

 "/strict chunk processing: LT_KEYS was already built and
 "preflighted before opening a Batch Input Session.
  IF P_BDC_MODE = GC_MODE_BATCH.
    GV_LAST_SM35_EXPECTED = LINES( LT_KEYS ).
  ENDIF.

  CLEAR: G_EXEC_CURR,
         LV_GROUPS, LV_OKGRP, LV_ERRGRP, GV_EXEC_RUN_QUEUED.
  G_STOP_FLAG = SPACE.
  REFRESH LT_KEY_CHUNK.

  LOOP AT LT_KEYS INTO LS_KEY.
    APPEND LS_KEY TO LT_KEY_CHUNK.

    IF LINES( LT_KEY_CHUNK ) >= LV_BSIZE.
      REFRESH LT_PROC.
      CLEAR: LV_CHUNK_OK, LV_CHUNK_MSG.
      PERFORM load_engine_chunk
        USING    LT_KEY_CHUNK
        CHANGING LT_PROC LV_CHUNK_OK LV_CHUNK_MSG.
      IF LV_CHUNK_OK <> ABAP_TRUE.
        G_STOP_FLAG = 'X'.
        PERFORM release_staging_lock USING LS_ROW-SESSION_ID.
        PERFORM userize_ui_message USING LV_CHUNK_MSG CHANGING gv_ui_message.
        MESSAGE gv_ui_message TYPE 'S' DISPLAY LIKE 'E'.
        RETURN.
      ENDIF.
      PERFORM process_eng_chunk
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
    CLEAR: LV_CHUNK_OK, LV_CHUNK_MSG.
    PERFORM load_engine_chunk
      USING    LT_KEY_CHUNK
      CHANGING LT_PROC LV_CHUNK_OK LV_CHUNK_MSG.
    IF LV_CHUNK_OK <> ABAP_TRUE.
      G_STOP_FLAG = 'X'.
      PERFORM release_staging_lock USING LS_ROW-SESSION_ID.
      PERFORM userize_ui_message USING LV_CHUNK_MSG CHANGING gv_ui_message.
      MESSAGE gv_ui_message TYPE 'S' DISPLAY LIKE 'E'.
      RETURN.
    ENDIF.
    PERFORM process_eng_chunk
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
 "Preserve the real BDC_CLOSE_GROUP return code before COMMIT WORK can
 "overwrite SY-SUBRC. Exact APQI/QID verification is valid only after a
 "proven successful close.
    lv_close_subrc = sy-subrc.
    COMMIT WORK AND WAIT.
    IF lv_close_subrc = 0.
      GV_LAST_SM35_GROUP = LV_BIGROUP.
      IF GV_LAST_SM35_QID IS INITIAL.
 "fail-closed identity: never recover a newly created session by
 ""newest APQI row". BDC_OPEN_GROUP's returned QID is the only creation
 "authority. Missing QID is handled by the exact APQI verifier below and
 "quarantines the queue instead of guessing another user's/session row.
        CLEAR GV_LAST_SM35_QID.
      ENDIF.
      CLEAR: LS_APQI_VERIFY, LV_APQI_FOUND.
      gv_z488_sm35_fidelity_ok = abap_false.

 "Source-backed BISM insertion proof: the QID returned by BDC_OPEN_GROUP
 "must exist as the exact BDC APQI session and its transaction count must
 "equal the number of successful one-per-group BDC_INSERT calls.
      IF GV_LAST_SM35_QID IS NOT INITIAL.
        SELECT SINGLE *
          FROM APQI
          INTO @LS_APQI_VERIFY
          WHERE MANDANT = @SY-MANDT
            AND QID     = @GV_LAST_SM35_QID.
        IF SY-SUBRC = 0.
          LV_APQI_FOUND = ABAP_TRUE.
        ENDIF.
      ENDIF.

      IF GV_LAST_SM35_QID IS NOT INITIAL AND
         LV_APQI_FOUND = ABAP_TRUE AND
         LS_APQI_VERIFY-DATATYP = 'BDC' AND
         LS_APQI_VERIFY-GROUPID = LV_BIGROUP AND
         LS_APQI_VERIFY-CREATOR = SY-UNAME AND
         LS_APQI_VERIFY-TRANSCNT = GV_LAST_SM35_INSERTED.
        gv_z488_sm35_fidelity_ok = abap_true.
        PERFORM persist_sm35_binding
          USING PT_PROCESS LV_BIGROUP GV_LAST_SM35_QID.
      ENDIF.

      IF GV_LAST_SM35_INSERTED <= 0.
 "Never execute or label an empty technical session as successful.
 "All rejected groups already carry their real preflight/insert error.
        LV_PROFILE_OK = ABAP_FALSE.
        DATA(lv_zm899_1194_1) = |{ LV_BIGROUP }|.
        MESSAGE ID 'ZBDC' TYPE 'S' NUMBER '899'
          WITH lv_zm899_1194_1 INTO LV_MSG.
        GV_LAST_SM35_ACTION = LV_MSG.
        PERFORM userize_ui_message USING LV_MSG CHANGING gv_ui_message.
        MESSAGE gv_ui_message TYPE 'S' DISPLAY LIKE 'E'.
      ELSEIF gv_z488_sm35_fidelity_ok <> abap_true.
 "Do not guess a session by name/time. If exact returned-QID APQI proof
 "or transaction count is missing, keep the created queue quarantined.
        LV_PROFILE_OK = ABAP_FALSE.
        DATA(lv_zm900_1201_1) = |{ LV_BIGROUP }|.
        DATA(lv_zm900_1201_2) = |{ GV_LAST_SM35_QID }|.
        DATA(lv_zm900_1201_3) = |{ GV_LAST_SM35_INSERTED }|.
        MESSAGE ID 'ZBDC' TYPE 'S' NUMBER '900'
          WITH lv_zm900_1201_1 lv_zm900_1201_2 lv_zm900_1201_3
          INTO LV_MSG.
        GV_LAST_SM35_ACTION = LV_MSG.
        PERFORM stamp_sm35_action USING PT_PROCESS LV_MSG.
        PERFORM userize_ui_message USING LV_MSG CHANGING gv_ui_message.
        MESSAGE gv_ui_message TYPE 'S' DISPLAY LIKE 'E'.
      ELSE.
 "The genuine BI session is closed, exact-QID bound and count-verified.
 "Queue creation is not transaction processing.
        LV_PROFILE_OK = ABAP_TRUE.
        DATA(lv_zm901_1209_1) = |{ LV_BIGROUP }|.
        DATA(lv_zm901_1209_2) = |{ GV_LAST_SM35_INSERTED }|.
        MESSAGE ID 'ZBDC' TYPE 'S' NUMBER '901'
          WITH lv_zm901_1209_1 lv_zm901_1209_2 INTO LV_MSG.
        DATA(lv_zm902_1210_1) = |{ LV_MSG }|.
        MESSAGE ID 'ZBDC' TYPE 'S' NUMBER '902'
          WITH lv_zm902_1210_1 INTO LV_MSG.
        GV_LAST_SM35_ACTION = LV_MSG.
        PERFORM stamp_sm35_action USING PT_PROCESS LV_MSG.
 "successful SM35 handoff is shown only by the explicit
 "SM35 session ready popup on screen 0500. Do not duplicate the same
 "instruction in the SAP status bar; errors still use MESSAGE below.
      ENDIF.
    ELSE.
      DATA(lv_zm903_1218_1) = |{ lv_close_subrc }|.
      MESSAGE ID 'ZBDC' TYPE 'S' NUMBER '903'
        WITH lv_zm903_1218_1 INTO LV_MSG.
      GV_LAST_SM35_ACTION = LV_MSG.
      gv_z488_sm35_fidelity_ok = abap_false.
      PERFORM userize_ui_message USING LV_MSG CHANGING gv_ui_message.
      MESSAGE gv_ui_message TYPE 'S' DISPLAY LIKE 'E'.
    ENDIF.
    PERFORM upd_all_rt_sess_sum.
    COMMIT WORK AND WAIT.
    PERFORM release_staging_lock USING ls_row-session_id.
    RETURN.
  ENDIF.

 " write/rebuild summary for every session in this batch execution.
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
  COMMIT WORK AND WAIT.

  IF G_STOP_FLAG = 'X'.
    DATA(lv_zm904_1244_1) = |{ LV_GROUPS }|.
    DATA(lv_zm904_1244_2) = |{ LV_OKGRP }|.
    DATA(lv_zm904_1244_3) = |{ LV_ERRGRP }|.
    MESSAGE ID 'ZBDC' TYPE 'S' NUMBER '904'
      WITH lv_zm904_1244_1 lv_zm904_1244_2 lv_zm904_1244_3
      INTO LV_MSG.
    PERFORM userize_ui_message USING LV_MSG CHANGING gv_ui_message.
    MESSAGE gv_ui_message TYPE 'S' DISPLAY LIKE 'W'.
  ELSE.
    DATA(lv_zm905_1247_1) = |{ LV_OKGRP }|.
    DATA(lv_zm905_1247_2) = |{ LV_GROUPS }|.
    DATA(lv_zm905_1247_3) = |{ LV_ERRGRP }|.
    MESSAGE ID 'ZBDC' TYPE 'S' NUMBER '905'
      WITH lv_zm905_1247_1 lv_zm905_1247_2 lv_zm905_1247_3
      INTO LV_MSG.
    PERFORM userize_ui_message USING LV_MSG CHANGING gv_ui_message.
    MESSAGE gv_ui_message TYPE 'S'.
  ENDIF.

  PERFORM release_staging_lock USING ls_row-session_id.
ENDFORM.

FORM acquire_staging_lock_safe
  USING    iv_session_id TYPE zbdc_staging_bup-session_id
  CHANGING cv_can_run    TYPE abap_bool
           cv_locked     TYPE abap_bool.

  DATA: lv_batch_key TYPE zbdc_staging_bup-session_id,
        lv_varkey    TYPE rstable-varkey,
        lv_holder    TYPE syuname.

  CLEAR: cv_can_run, cv_locked.

  IF iv_session_id IS INITIAL.
    MESSAGE s505(zbdc) DISPLAY LIKE 'E'.
    RETURN.
  ENDIF.

  PERFORM batch_prefix_from_sid
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
      MESSAGE s506(zbdc) WITH lv_batch_key lv_holder DISPLAY LIKE 'E'.
    WHEN OTHERS.
      MESSAGE s507(zbdc) WITH lv_batch_key sy-subrc DISPLAY LIKE 'E'.
  ENDCASE.
ENDFORM.

FORM release_staging_lock
  USING iv_session_id TYPE zbdc_staging_bup-session_id.

  DATA: lv_batch_key TYPE zbdc_staging_bup-session_id,
        lv_varkey    TYPE rstable-varkey.

  IF iv_session_id IS INITIAL.
    RETURN.
  ENDIF.

  PERFORM batch_prefix_from_sid
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

FORM sm35_profile_label
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

FORM find_sm35_qid
  USING    pv_group TYPE apqi-groupid
  CHANGING cv_qid   TYPE apqi-qid.

  DATA lv_group TYPE apqi-groupid.

 "EXEC_ONLY: never resolve an SM35 queue by newest GROUP/time. The QID
 "returned by BDC_OPEN_GROUP and persisted in SM35_BIND is the only queue
 "identity accepted by reconciliation. If that exact QID is unavailable,
 "the caller must remain unresolved instead of guessing another session.
  IF cv_qid IS INITIAL.
    RETURN.
  ENDIF.

  SELECT SINGLE groupid
    FROM apqi
    INTO @lv_group
    WHERE mandant = @sy-mandt
      AND qid     = @cv_qid
      AND datatyp = 'BDC'.

  IF sy-subrc = 0.
    IF lv_group <> pv_group.
      CLEAR cv_qid.
    ENDIF.
    RETURN.
  ENDIF.

 "After processing, APQI can disappear while TemSe protocol still remains.
 "Keep the persisted exact QID; do not replace it with a different queue.
ENDFORM.

*& Read detailed SM35 protocol lines from the standard TemSe log

*& Build BDCLM-compatible MPAR from APQLE MSGV1..MSGV4

FORM pack_apqle_mpar
  USING    ps_apqle TYPE apqle
  CHANGING cs_bdclm TYPE bdclm.

  DATA: lv_v1      TYPE string,
        lv_v2      TYPE string,
        lv_v3      TYPE string,
        lv_v4      TYPE string,
        lv_value   TYPE string,
        lv_len     TYPE i,
        lv_len2    TYPE n LENGTH 2,
        lv_count   TYPE i,
        lv_payload TYPE string.

  CLEAR: cs_bdclm-mpar, cs_bdclm-mparcnt.

  lv_v1 = ps_apqle-msgv1.
  lv_v2 = ps_apqle-msgv2.
  lv_v3 = ps_apqle-msgv3.
  lv_v4 = ps_apqle-msgv4.

 "APQLE already stores the four SAP message variables separately. BDCLM
 "stores them as 2-digit length-prefixed MPAR. Recreate that representation
 "only so the existing generic formatter/mode detector can consume DB and
 "TemSe protocol rows identically; no business text is invented here.
  DO 4 TIMES.
    CASE sy-index.
      WHEN 1. lv_value = lv_v1.
      WHEN 2. lv_value = lv_v2.
      WHEN 3. lv_value = lv_v3.
      WHEN 4. lv_value = lv_v4.
    ENDCASE.

    lv_len = strlen( lv_value ).
    IF lv_len > 99.
      lv_len = 99.
      lv_value = lv_value+0(99).
    ENDIF.

    lv_len2 = lv_len.
    lv_payload = |{ lv_payload }{ lv_len2 }{ lv_value }|.
    lv_count = lv_count + 1.
  ENDDO.

  cs_bdclm-mparcnt = lv_count.
  cs_bdclm-mpar = lv_payload.
ENDFORM.

FORM get_sm35_log
  USING    pv_qid TYPE apqi-qid
  CHANGING ct_log TYPE ty_t_bdclm.

  TYPES: BEGIN OF ty_plain_log_746,
           enterdate  TYPE btctle-enterdate,
           entertime  TYPE btctle-entertime,
           logmessage TYPE c LENGTH 400,
         END OF ty_plain_log_746.

  DATA: lv_param_name TYPE c LENGTH 60 VALUE 'bdc/protocol/write_in_db',
        lv_param_val  TYPE c LENGTH 20,
        lv_db_mode    TYPE abap_bool VALUE abap_true,
        lt_apqli      TYPE STANDARD TABLE OF apqli,
        ls_apqli      TYPE apqli,
        lt_apqle      TYPE STANDARD TABLE OF apqle,
        ls_apqle      TYPE apqle,
        lt_apql       TYPE STANDARD TABLE OF apql,
        ls_apql       TYPE apql,
        lt_plain      TYPE STANDARD TABLE OF ty_plain_log_746,
        ls_plain      TYPE ty_plain_log_746,
        ls_bdclm      TYPE bdclm,
        lv_handle     TYPE rststype-fbhandle,
        lv_charco     TYPE rststype-charco,
        lv_read_rc    LIKE sy-subrc.

  REFRESH ct_log.
  IF pv_qid IS INITIAL.
    RETURN.
  ENDIF.

 "mirror the actual RSBDC_ANALYSE switch from this SAP system.
 "Since SAP 6.10, bdc/new_protocol/common-log probing is obsolete in the
 "standard analyzer. The active switch is bdc/protocol/write_in_db:
 " TRUE/default -> BDC_PROTOCOL_DB_SELECT_QID + APQLE
 " FALSE -> APQL/TemSe
  CLEAR lv_param_val.
  CALL 'C_SAPGPARAM'
    ID 'NAME'  FIELD lv_param_name
    ID 'VALUE' FIELD lv_param_val.
  IF sy-subrc = 0.
    TRANSLATE lv_param_val TO UPPER CASE.
    IF lv_param_val(5) = 'FALSE'.
      lv_db_mode = abap_false.
    ENDIF.
  ENDIF.

  IF lv_db_mode = abap_true.
    REFRESH lt_apqli.
    CALL FUNCTION 'BDC_PROTOCOL_DB_SELECT_QID'
      EXPORTING
        queue_id = pv_qid
      TABLES
        apqlitab = lt_apqli
      EXCEPTIONS
        OTHERS   = 1.
    IF sy-subrc <> 0 OR lt_apqli IS INITIAL.
      RETURN.
    ENDIF.

 "RSBDC_ANALYSE shows the most recent protocol first and opens index 1.
    SORT lt_apqli BY credate DESCENDING cretime DESCENDING.
    READ TABLE lt_apqli INTO ls_apqli INDEX 1.
    IF sy-subrc <> 0.
      RETURN.
    ENDIF.

    SELECT *
      FROM apqle
      INTO TABLE @lt_apqle
      WHERE qid    = @ls_apqli-qid
        AND lognum = @ls_apqli-lognum
      ORDER BY linenum ASCENDING.
    IF sy-subrc <> 0 OR lt_apqle IS INITIAL.
      RETURN.
    ENDIF.

    LOOP AT lt_apqle INTO ls_apqle.
      CLEAR ls_bdclm.
      MOVE-CORRESPONDING ls_apqle TO ls_bdclm.
      IF ls_bdclm-mcnt > 0.
        ls_bdclm-mcnt = ls_bdclm-mcnt - 1.
      ENDIF.
      PERFORM pack_apqle_mpar
        USING    ls_apqle
        CHANGING ls_bdclm.
      APPEND ls_bdclm TO ct_log.
    ENDLOOP.
    RETURN.
  ENDIF.

 "DB protocol disabled: follow RSBDC_ANALYSE get_logfiles_from_temse and
 "read only the newest APQL/TemSe protocol for this exact QID.
  SELECT *
    FROM apql
    INTO TABLE @lt_apql
    WHERE mandant = @sy-mandt
      AND qid     = @pv_qid
    ORDER BY credate DESCENDING, cretime DESCENDING, temseid DESCENDING.
  IF sy-subrc <> 0 OR lt_apql IS INITIAL.
    RETURN.
  ENDIF.

  READ TABLE lt_apql INTO ls_apql INDEX 1.
  IF sy-subrc <> 0 OR ls_apql-temseid IS INITIAL.
    RETURN.
  ENDIF.

  REFRESH lt_plain.
  CLEAR: lv_handle, lv_charco, lv_read_rc.
  lv_charco = '0000'.

  CALL FUNCTION 'RSTS_GET_ATTRIBUTES'
    EXPORTING
      authority = space
      client    = ls_apql-mandant
      name      = ls_apql-temseid
    IMPORTING
      charco    = lv_charco
    EXCEPTIONS
      OTHERS    = 5.
  IF sy-subrc <> 0.
    RETURN.
  ENDIF.

  IF cl_abap_char_utilities=>charsize > 1.
    lv_charco = '0000'.
  ENDIF.

  CALL FUNCTION 'RSTS_OPEN_RLC'
    EXPORTING
      name      = ls_apql-temseid
      client    = ls_apql-mandant
      authority = 'BATCH'
      prom      = 'I'
      rectyp    = 'VNL----'
      charco    = lv_charco
    IMPORTING
      fbhandle  = lv_handle
    EXCEPTIONS
      OTHERS    = 24.
  IF sy-subrc <> 0.
    RETURN.
  ENDIF.

  CALL FUNCTION 'RSTS_READ'
    EXPORTING
      fbhandle = lv_handle
    TABLES
      datatab  = lt_plain
    EXCEPTIONS
      OTHERS   = 16.
  lv_read_rc = sy-subrc.

  CALL FUNCTION 'RSTS_CLOSE'
    EXPORTING
      fbhandle = lv_handle
    EXCEPTIONS
      OTHERS   = 4.

  IF lv_read_rc <> 0 OR lt_plain IS INITIAL.
    RETURN.
  ENDIF.

  LOOP AT lt_plain INTO ls_plain.
    CLEAR ls_bdclm.
    ls_bdclm-indate = ls_plain-enterdate.
    ls_bdclm-intime = ls_plain-entertime.
    ls_bdclm+14(352) = ls_plain-logmessage.
    IF ls_bdclm-mcnt > 0.
      ls_bdclm-mcnt = ls_bdclm-mcnt - 1.
    ENDIF.
    APPEND ls_bdclm TO ct_log.
  ENDLOOP.
ENDFORM.

FORM get_sm35_session_log
  USING    pv_group TYPE apqi-groupid
           pv_qid   TYPE apqi-qid
  CHANGING ct_log   TYPE ty_t_bdclm
           cv_ok    TYPE abap_bool.

  DATA lv_group TYPE apqi-groupid.

  CLEAR cv_ok.
  REFRESH ct_log.

  IF pv_group IS INITIAL OR pv_qid IS INITIAL.
    RETURN.
  ENDIF.

 "prove Session Name ownership from APQI (the queue itself), not from
 "APQL (the protocol directory). Standard SM35 can display a protocol by the
 "session name even when an exact APQL GROUPID+QID comparison does not hit.
  SELECT SINGLE groupid
    FROM apqi
    INTO @lv_group
    WHERE mandant = @sy-mandt
      AND qid     = @pv_qid
      AND datatyp = 'BDC'.

 "If APQI still exists, it must prove the exact ownership. If SAP already
 "removed the terminal APQI row, keep using the durable Session Name/QID
 "binding persisted by this program; never substitute another queue.
  IF sy-subrc = 0 AND lv_group <> pv_group.
    RETURN.
  ENDIF.

  PERFORM get_sm35_log USING pv_qid CHANGING ct_log.
  IF ct_log IS NOT INITIAL.
    cv_ok = abap_true.
  ENDIF.
ENDFORM.

FORM sm35_reader_diag
  USING    pv_group TYPE apqi-groupid
           pv_qid   TYPE apqi-qid
  CHANGING cv_diag  TYPE char255.

  DATA: ls_apqi       TYPE apqi,
        lv_param_name TYPE c LENGTH 60 VALUE 'bdc/protocol/write_in_db',
        lv_param_val  TYPE c LENGTH 20,
        lv_db_mode    TYPE abap_bool VALUE abap_true,
        lt_apqli      TYPE STANDARD TABLE OF apqli,
        ls_apqli      TYPE apqli,
        lt_apqle      TYPE STANDARD TABLE OF apqle,
        lt_apql       TYPE STANDARD TABLE OF apql,
        ls_apql       TYPE apql,
        lt_log        TYPE ty_t_bdclm,
        lv_rows       TYPE i,
        lv_txt        TYPE string.

  CLEAR cv_diag.
  IF pv_group IS INITIAL OR pv_qid IS INITIAL.
    cv_diag = 'INPUT_FAIL: Session Name or QID is initial'.
    RETURN.
  ENDIF.

  CLEAR ls_apqi.
  SELECT SINGLE *
    FROM apqi
    INTO @ls_apqi
    WHERE mandant = @sy-mandt
      AND qid     = @pv_qid
      AND datatyp = 'BDC'.
  IF sy-subrc = 0 AND ls_apqi-groupid <> pv_group.
    cv_diag = 'APQI_FAIL: exact QID does not own the displayed Session Name'.
    RETURN.
  ENDIF.

  CLEAR lv_param_val.
  CALL 'C_SAPGPARAM'
    ID 'NAME'  FIELD lv_param_name
    ID 'VALUE' FIELD lv_param_val.
  IF sy-subrc = 0.
    TRANSLATE lv_param_val TO UPPER CASE.
    IF lv_param_val(5) = 'FALSE'.
      lv_db_mode = abap_false.
    ENDIF.
  ENDIF.

  IF lv_db_mode = abap_true.
    CALL FUNCTION 'BDC_PROTOCOL_DB_SELECT_QID'
      EXPORTING
        queue_id = pv_qid
      TABLES
        apqlitab = lt_apqli
      EXCEPTIONS
        OTHERS   = 1.
    IF sy-subrc <> 0 OR lt_apqli IS INITIAL.
      lv_rows = lines( lt_apqli ).
      lv_txt = |DB_PROTOCOL_FAIL RC={ sy-subrc } INDEX_ROWS={ lv_rows }|.
      cv_diag = lv_txt.
      RETURN.
    ENDIF.

    SORT lt_apqli BY credate DESCENDING cretime DESCENDING.
    READ TABLE lt_apqli INTO ls_apqli INDEX 1.
    SELECT *
      FROM apqle
      INTO TABLE @lt_apqle
      WHERE qid    = @ls_apqli-qid
        AND lognum = @ls_apqli-lognum
      ORDER BY linenum ASCENDING.
    lv_rows = lines( lt_apqle ).
    IF lv_rows > 0.
      lv_txt = |OK DB LOGNUM={ ls_apqli-lognum } APQLE_ROWS={ lv_rows }|.
    ELSE.
      lv_txt = |DB_PROTOCOL_EMPTY LOGNUM={ ls_apqli-lognum } APQLE_ROWS=0|.
    ENDIF.
    cv_diag = lv_txt.
    RETURN.
  ENDIF.

  SELECT *
    FROM apql
    INTO TABLE @lt_apql
    WHERE mandant = @sy-mandt
      AND qid     = @pv_qid
    ORDER BY credate DESCENDING, cretime DESCENDING, temseid DESCENDING.
  IF lt_apql IS INITIAL.
    cv_diag = 'TEMSE_PROTOCOL_FAIL: no APQL row for exact QID'.
    RETURN.
  ENDIF.

  READ TABLE lt_apql INTO ls_apql INDEX 1.
  PERFORM get_sm35_log USING pv_qid CHANGING lt_log.
  lv_rows = lines( lt_log ).
  IF lv_rows > 0.
    lv_txt = |OK TEMSE={ ls_apql-temseid } RAW={ lv_rows }|.
  ELSE.
    lv_txt = |TEMSE_READ_FAIL TEMSE={ ls_apql-temseid } RAW=0|.
  ENDIF.
  cv_diag = lv_txt.
ENDFORM.

FORM detect_sm35_mode_from_log
  USING    pt_log   TYPE ty_t_bdclm
  CHANGING cv_mode  TYPE c
           cv_label TYPE char50.

  DATA: ls_log   TYPE bdclm,
        lv_v1    TYPE string,
        lv_v2    TYPE string,
        lv_v3    TYPE string,
        lv_v4    TYPE string,
        lv_ok    TYPE abap_bool,
        lv_text  TYPE char255,
        lv_upper TYPE string.

  CLEAR: cv_mode, cv_label.

  LOOP AT pt_log INTO ls_log
    WHERE mid = '00' AND mnr = '300'.

    CLEAR: lv_v1, lv_v2, lv_v3, lv_v4, lv_ok, lv_text, lv_upper.
    PERFORM decode_sm35_mpar
      USING    ls_log
      CHANGING lv_v1 lv_v2 lv_v3 lv_v4 lv_ok.

    IF lv_ok = abap_true.
      CONDENSE lv_v3 NO-GAPS.
      TRANSLATE lv_v3 TO UPPER CASE.
      IF lv_v3 = 'A' OR lv_v3 = 'E' OR lv_v3 = 'N'.
        cv_mode = lv_v3.
        EXIT.
      ENDIF.
    ENDIF.

    PERFORM format_sm35_log_line
      USING    ls_log
      CHANGING lv_text.
    lv_upper = lv_text.
    TRANSLATE lv_upper TO UPPER CASE.
    IF lv_upper CS ' MODE A ' OR lv_upper CP '*MODE A*'.
      cv_mode = 'A'.
      EXIT.
    ELSEIF lv_upper CS ' MODE E ' OR lv_upper CP '*MODE E*'.
      cv_mode = 'E'.
      EXIT.
    ELSEIF lv_upper CS ' MODE N ' OR lv_upper CP '*MODE N*'.
      cv_mode = 'N'.
      EXIT.
    ENDIF.
  ENDLOOP.

  CASE cv_mode.
    WHEN 'A'.
      cv_label = 'A - Process / foreground'.
    WHEN 'E'.
      cv_label = 'E - Display errors only'.
    WHEN 'N'.
      cv_label = 'N - Background / no display'.
    WHEN OTHERS.
      cv_label = 'Unknown - mode not available in SM35 protocol'.
  ENDCASE.
ENDFORM.

FORM collect_group_key
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

FORM purge_sm35_group_log
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

*& Extract SM35 business object by certified DB proof only

*& Decode length-prefixed SM35 TemSe message parameters
*& BDCLM-MPAR is not one FORMAT_MESSAGE V1 value. It contains MPARCNT
*& parameters, each encoded as a two-digit length followed by its text.
*& Decode at most four variables and keep the caller fail-closed.

FORM decode_sm35_mpar
  USING    is_log TYPE bdclm
  CHANGING cv_v1  TYPE string
           cv_v2  TYPE string
           cv_v3  TYPE string
           cv_v4  TYPE string
           cv_ok  TYPE abap_bool.

  DATA: lv_raw       TYPE string,
        lv_count_txt TYPE string,
        lv_count     TYPE i,
        lv_raw_len   TYPE i,
        lv_len_txt   TYPE c LENGTH 2,
        lv_len       TYPE i,
        lv_shift     TYPE i,
        lv_value     TYPE string.

  CLEAR: cv_v1, cv_v2, cv_v3, cv_v4, cv_ok.

  lv_count_txt = is_log-mparcnt.
  CONDENSE lv_count_txt NO-GAPS.
  IF lv_count_txt IS INITIAL OR
     lv_count_txt CN '0123456789'.
    RETURN.
  ENDIF.

  TRY.
      lv_count = lv_count_txt.
    CATCH cx_root.
      RETURN.
  ENDTRY.

  IF lv_count <= 0.
    RETURN.
  ELSEIF lv_count > 4.
    lv_count = 4.
  ENDIF.

  lv_raw = is_log-mpar.

  DO lv_count TIMES.
    lv_raw_len = strlen( lv_raw ).
    IF lv_raw_len < 2.
      RETURN.
    ENDIF.

    lv_len_txt = lv_raw+0(2).
    IF lv_len_txt CN '0123456789'.
      RETURN.
    ENDIF.

    TRY.
        lv_len = lv_len_txt.
      CATCH cx_sy_conversion_no_number
            cx_sy_conversion_overflow.
        RETURN.
    ENDTRY.

    IF lv_len < 0 OR lv_raw_len < lv_len + 2.
      RETURN.
    ENDIF.

    CLEAR lv_value.
    IF lv_len > 0.
      lv_value = lv_raw+2(lv_len).
    ENDIF.

    CASE sy-index.
      WHEN 1. cv_v1 = lv_value.
      WHEN 2. cv_v2 = lv_value.
      WHEN 3. cv_v3 = lv_value.
      WHEN 4. cv_v4 = lv_value.
    ENDCASE.

    lv_shift = lv_len + 2.
    IF lv_shift >= lv_raw_len.
      CLEAR lv_raw.
    ELSE.
      lv_raw = lv_raw+lv_shift.
    ENDIF.
  ENDDO.

  cv_ok = abap_true.
ENDFORM.

FORM save_sm35_line
  USING pt_group    TYPE ty_t_staging_alv
        ps_log      TYPE bdclm
        pv_proc_mode TYPE c.

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
        lv_mpar_ok  TYPE abap_bool,
        lv_msgv1    TYPE string,
        lv_msgv2    TYPE string,
        lv_msgv3    TYPE string,
        lv_msgv4    TYPE string,
        lv_upper    TYPE string.

  FIELD-SYMBOLS <fv> TYPE any.

  READ TABLE pt_group INTO ls_first INDEX 1.
  IF sy-subrc <> 0.
    RETURN.
  ENDIF.

  CLEAR: lv_text, lv_fallback, lv_mpar_ok,
         lv_msgv1, lv_msgv2, lv_msgv3, lv_msgv4.

  PERFORM decode_sm35_mpar
    USING    ps_log
    CHANGING lv_msgv1 lv_msgv2 lv_msgv3 lv_msgv4 lv_mpar_ok.

  IF lv_mpar_ok <> abap_true.
    lv_msgv1 = ps_log-mpar.
  ENDIF.

  IF ps_log-mid IS NOT INITIAL AND ps_log-mnr IS NOT INITIAL.
    CALL FUNCTION 'FORMAT_MESSAGE'
      EXPORTING
        id   = ps_log-mid
        lang = sy-langu
        no   = ps_log-mnr
        v1   = lv_msgv1
        v2   = lv_msgv2
        v3   = lv_msgv3
        v4   = lv_msgv4
      IMPORTING
        msg  = lv_text
      EXCEPTIONS
        OTHERS = 1.
  ENDIF.

  lv_fallback =
    |{ ps_log-mid }/{ ps_log-mnr } { lv_msgv1 } { lv_msgv2 } { lv_msgv3 } { lv_msgv4 }|.
  CONDENSE lv_fallback.
  IF lv_text IS INITIAL.
    lv_text = lv_fallback.
  ENDIF.
  IF lv_text IS INITIAL.
    lv_text = |SM35 protocol message { ps_log-mcnt }|.
  ENDIF.

  lv_upper = lv_text.
  TRANSLATE lv_upper TO UPPER CASE.

 "Execution-only protocol persistence: retain SAP message type/id/number/
 "variables verbatim. Do not extract or verify an SAP Object here and do not
 "require a certified success signature. Group lifecycle is reconciled later
 "from exact TCNT-mapped protocol plus APQI state.
  CLEAR: lv_hint, lv_retry.
  PERFORM build_bdc_action_hint
    USING    lv_text 'SM35'
    CHANGING lv_hint lv_retry.

  CASE ps_log-mart.
    WHEN 'E' OR 'A' OR 'X'.
      lv_status = gc_st_error.
    WHEN 'S'.
 "preserve the raw SAP protocol, but stamp standard SM35
 "controller S-messages at ingestion time while MID/MNR are still
 "available in BDCLM. ZBDC_RESULT_BUP installations are not required
 "to expose MSG_ID / MSG_NUMBER columns, so later classification must
 "not statically address optional DDIC components.
      IF ps_log-mid = '00' AND ps_log-mnr = '355'.
 "Exact standard SAP transaction-level BISM success. This is not an
 "application business message, but it is stronger than folder-end
 "statistics and must be preserved verbatim when no business S-message
 "was persisted by the transaction.
        lv_status = 'SM35_TX_OK'.
      ELSEIF ps_log-mid = 'DC'.
 "in standard SM35 mode N, SAP Control Framework failures may
 "be logged with MART='S'. They are exact failure evidence, not
 "business success. In A/E they remain diagnostic only.
        IF pv_proc_mode = 'N' AND
           ( ps_log-mnr = '001' OR
             ps_log-mnr = '006' OR
             lv_upper CS 'CONTROL FRAMEWORK' OR
             lv_upper CS 'GUI CANNOT BE REACHED' OR
             lv_upper CS 'FATAL ERROR' OR
             lv_upper CS 'RAISE_EXCEPTION' ).
          lv_status = 'SM35_BG_FATAL'.
        ELSE.
          lv_status = 'SM35_DIAG'.
        ENDIF.
      ELSEIF ps_log-mid = '00' AND
         ( ps_log-mnr = '300' OR
           ps_log-mnr = '363' OR
           ps_log-mnr = '364' OR
           ps_log-mnr = '365' OR
           ps_log-mnr = '366' OR
           ps_log-mnr = '370' OR
           ps_log-mnr = '382' ).
        lv_status = 'SM35_ADMIN'.
      ELSE.
 "exact application S-message from SM35 Extended Log.
 "Persist a dedicated generic marker so CT/BISM success evidence can
 "be projected identically without hard-coding TCODE/message classes.
        lv_status = 'SM35_APP_S'.
      ENDIF.
    WHEN OTHERS.
      lv_status = 'INFO'.
  ENDCASE.

  CLEAR lv_step_max.
  SELECT MAX( step ) FROM zbdc_result_bup INTO @lv_step_max
    WHERE session_id = @ls_first-session_id
      AND record_key = @ls_first-record_key
      AND row_index  = @ls_first-row_index.
  lv_step = lv_step_max + 1.

  GET TIME STAMP FIELD lv_ts.
 "normalized user-facing date/time follows the same Vietnam demo clock
 "as CT results and dashboards. Raw SM35 protocol evidence remains in PS_LOG;
 "CREATED_AT keeps the canonical timestamp for exact ordering.
  PERFORM get_demo_now CHANGING lv_date lv_time.
  lv_attempt = gv_sm35_retry_count + 1.

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
  set_sm35_res 'MSGV1'         lv_msgv1.
  set_sm35_res 'MSGV2'         lv_msgv2.
  set_sm35_res 'MSGV3'         lv_msgv3.
  set_sm35_res 'MSGV4'         lv_msgv4.
  set_sm35_res 'MESSAGE'       lv_text.
  set_sm35_res 'MESSAGE_TEXT'  lv_text.
  set_sm35_res 'SAP_OBJECT_ID' ''.
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

FORM sync_sm35_logs
  USING    pt_process TYPE ty_t_staging_alv
           pv_qid     TYPE apqi-qid
  CHANGING cv_count   TYPE i
           cv_retry   TYPE abap_bool
           cv_reason  TYPE string
           cv_mode    TYPE c.

  DATA: lt_log    TYPE ty_t_bdclm,
        ls_log    TYPE bdclm,
        lt_keys   TYPE ty_t_engine_group_key,
        ls_key    TYPE ty_engine_group_key,
        lt_group  TYPE ty_t_staging_alv,
        lv_index  TYPE i,
        lv_total  TYPE i,
        lv_text   TYPE string,
        lv_msgv1  TYPE string,
        lv_msgv2  TYPE string,
        lv_msgv3  TYPE string,
        lv_msgv4  TYPE string,
        lv_mpar_ok TYPE abap_bool,
        lv_fmt    TYPE c LENGTH 255,
        lv_hit    TYPE abap_bool,
        lv_why    TYPE string,
        lv_mode_label TYPE char50.

  CLEAR: cv_count, cv_retry, cv_reason, cv_mode, lv_mode_label.
  PERFORM get_sm35_log USING pv_qid CHANGING lt_log.
  IF lt_log IS INITIAL.
    RETURN.
  ENDIF.

  PERFORM detect_sm35_mode_from_log
    USING    lt_log
    CHANGING cv_mode lv_mode_label.

  PERFORM build_engine_keys USING pt_process CHANGING lt_keys.
  IF lt_keys IS INITIAL.
    RETURN.
  ENDIF.

  LOOP AT lt_keys INTO ls_key.
    PERFORM purge_sm35_group_log USING ls_key.
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

    PERFORM collect_group_key
      USING    pt_process ls_key
      CHANGING lt_group.
    IF lt_group IS INITIAL.
      CONTINUE.
    ENDIF.

    PERFORM save_sm35_line USING lt_group ls_log cv_mode.
    cv_count = cv_count + 1.

    CLEAR: lv_msgv1, lv_msgv2, lv_msgv3, lv_msgv4,
           lv_mpar_ok, lv_fmt, lv_text.
    PERFORM decode_sm35_mpar
      USING    ls_log
      CHANGING lv_msgv1 lv_msgv2 lv_msgv3 lv_msgv4 lv_mpar_ok.
    IF lv_mpar_ok <> abap_true.
      lv_msgv1 = ls_log-mpar.
    ENDIF.
    IF ls_log-mid IS NOT INITIAL AND ls_log-mnr IS NOT INITIAL.
      CALL FUNCTION 'FORMAT_MESSAGE'
        EXPORTING
          id   = ls_log-mid
          lang = sy-langu
          no   = ls_log-mnr
          v1   = lv_msgv1
          v2   = lv_msgv2
          v3   = lv_msgv3
          v4   = lv_msgv4
        IMPORTING
          msg  = lv_fmt
        EXCEPTIONS
          OTHERS = 1.
    ENDIF.
    IF lv_fmt IS NOT INITIAL.
      lv_text = lv_fmt.
    ELSE.
      lv_text =
        |{ ls_log-mid } { ls_log-mnr } { lv_msgv1 } { lv_msgv2 } { lv_msgv3 } { lv_msgv4 }|.
    ENDIF.
    CONDENSE lv_text.

    CLEAR: lv_hit, lv_why.
    PERFORM text_transient
      USING    lv_text
      CHANGING lv_hit lv_why.
    IF lv_hit = abap_true.
      cv_retry  = abap_true.
      cv_reason = lv_why.
    ENDIF.
  ENDLOOP.
ENDFORM.

*& Start exact-QID RSBDCBTC job for a real SM35 queue
*& The BI session is created with BDC_OPEN/INSERT/CLOSE and processed by QID.
*& NOBINPT/RACOMMIT improve compatibility but do not fake support: the real
*& SM35 protocol is inspected afterwards. GUI-Control failures remain protocol evidence; no hidden executor fallback is allowed.

*& Process a real SM35 queue through RSBDCBTC
*& The original queue remains a genuine Batch Input Session. Processing is
*& driven by QID and verified by APQI, SM35 protocol and exact protocol.
*& No success is inferred merely because the RSBDCBTC job finished.

FORM set_sm35_group
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

*& Mandatory hidden trace proof for every onboarded TCODE

*& Generic DB object resolver for CT + BISM
*& Purpose:
*& End user only runs/refreshes. When SAP protocol has no object number,
*& the runtime resolves the new business object from the certified object
*& table/field by a fail-closed high-water mark. No TCODE, table or field
*& name is hardcoded here; VERIFY_TABLE/VERIFY_FIELD are owned by the frozen
*& runtime certificate.

*& Durable technical watermark storage
*& Why:
*& ZBDC_RESULT_BUP is also used for visible group lifecycle rows. On some
*& installations UPDATE_GROUP_RESULT can overwrite/purge a technical result
*& row, so the SM35 refresh no longer finds FIELD_NAME = 'Z264_MARK'.
*& Store the pre-run high-water mark in ZBDC_CONFIG_BUP under a session/group
*& technical key as well. End users still only Run/Refresh.

*& DDIC-aware source literal formatting for generic DB proof

*& DDIC-aware SAP Object literal normalization

*& Protocol messages expose business object numbers in external format
*& while transparent-table keys can store the same object in DDIC internal
*& format. Normalize only for SQL/proof; keep the protocol token unchanged
*& for UI/audit. No TCODE/table/field hardcoding is used.

*& Generic Dynpro-field -> DDIC data-element resolver

*& A SHDB/BDC field often belongs to a screen structure rather than the
*& transparent persistence table. FIELDNAME equality alone therefore misses
*& valid owners. Resolve PREFIX-FIELD through DDIC and expose only its exact
*& ROLLNAME. Callers may use that repository identity to correlate the same
*& semantic field in transparent tables. No TCODE/table/field alias exists.

*& CT DB object proof by source fields (no global high-water trap)

*& Generic Object Proof verifier

*& Protect verified business success from stale SM35 audit errors
*& An Incorrect SM35 session remains visible for audit. Later Refresh/SM35
*& Monitor actions must not overwrite a
*& SAP document that was subsequently created and verified successfully.

*& Classify SM35 controller success vs application success

*& The standard batch-input controller itself writes class 00 success
*& messages (session start/statistics/transaction processed/end). They prove
*& BISM execution but they are not the transaction's business success message.
*& Keep them as raw protocol, but do not let them overwrite an exact
*& application S-message captured by LOGALL=X.

FORM is_sm35_admin_s
  USING    ps_res   TYPE zbdc_result_bup
  CHANGING cv_admin TYPE abap_bool.

  DATA: lv_mid TYPE string,
        lv_mnr TYPE string.
  FIELD-SYMBOLS: <lv_mid> TYPE any,
                 <lv_mnr> TYPE any.

  CLEAR cv_admin.
  IF ps_res-field_name <> 'SM35' OR ps_res-msg_type <> 'S'.
    RETURN.
  ENDIF.

 "compile-safe authority: new protocol rows are stamped while the
 "raw BDCLM MID/MNR are available. EXEC_STATUS is a guaranteed result-table
 "field in this program, unlike optional MSG_ID / MSG_NUMBER extensions.
  IF ps_res-exec_status = 'SM35_ADMIN' OR
     ps_res-exec_status = 'SM35_TX_OK'.
    cv_admin = abap_true.
    RETURN.
  ENDIF.

 "Backward-compatible read for installations that do expose message identity
 "columns. Dynamic component access keeps this include compilable when they
 "do not exist in ZBDC_RESULT_BUP.
  ASSIGN COMPONENT 'MSG_ID' OF STRUCTURE ps_res TO <lv_mid>.
  IF sy-subrc <> 0.
    ASSIGN COMPONENT 'MSGID' OF STRUCTURE ps_res TO <lv_mid>.
  ENDIF.
  ASSIGN COMPONENT 'MSG_NUMBER' OF STRUCTURE ps_res TO <lv_mnr>.
  IF sy-subrc <> 0.
    ASSIGN COMPONENT 'MSGNR' OF STRUCTURE ps_res TO <lv_mnr>.
  ENDIF.
  IF sy-subrc <> 0.
    ASSIGN COMPONENT 'MSG_NO' OF STRUCTURE ps_res TO <lv_mnr>.
  ENDIF.

  IF <lv_mid> IS ASSIGNED.
    lv_mid = <lv_mid>.
  ENDIF.
  IF <lv_mnr> IS ASSIGNED.
    lv_mnr = <lv_mnr>.
  ENDIF.
  CONDENSE lv_mid NO-GAPS.
  CONDENSE lv_mnr NO-GAPS.

  IF lv_mid = '00' AND
     ( lv_mnr = '300' OR
       lv_mnr = '355' OR
       lv_mnr = '363' OR
       lv_mnr = '364' OR
       lv_mnr = '365' OR
       lv_mnr = '366' OR
       lv_mnr = '370' OR
       lv_mnr = '382' ).
    cv_admin = abap_true.
  ENDIF.
ENDFORM.

*& Let the exact TemSe protocol settle after terminal APQI state

*& APQI can reach F before all LOGALL TemSe records are readable. Probe only
*& the persisted exact QID for at most two extra seconds. This is evidence
*& stabilization, not another execution and never a GROUP/time lookup.

FORM wait_sm35_protocol
  USING    pv_qid      TYPE apqi-qid
  CHANGING cv_count    TYPE i
           cv_has_bizs TYPE abap_bool.

  DATA: lt_probe TYPE ty_t_bdclm,
        ls_probe TYPE bdclm,
        lv_admin TYPE abap_bool.

  CLEAR: cv_count, cv_has_bizs.
  IF pv_qid IS INITIAL.
    RETURN.
  ENDIF.

 "UI-safe one-shot read. Do not poll/wait inside screen 0500.
 "If SAP has not committed a terminal protocol yet, reconciliation stays
 "queued/pending and the next normal cockpit refresh/re-entry reads it.
  PERFORM get_sm35_log USING pv_qid CHANGING lt_probe.
  cv_count = lines( lt_probe ).

  LOOP AT lt_probe INTO ls_probe WHERE mart = 'S'.
    CLEAR lv_admin.
    IF ls_probe-mid = '00' AND
       ( ls_probe-mnr = '300' OR
         ls_probe-mnr = '355' OR
         ls_probe-mnr = '363' OR
         ls_probe-mnr = '364' OR
         ls_probe-mnr = '365' OR
         ls_probe-mnr = '366' OR
         ls_probe-mnr = '370' OR
         ls_probe-mnr = '382' ).
      lv_admin = abap_true.
    ENDIF.

    IF lv_admin <> abap_true AND ls_probe-mid <> 'DC'.
      cv_has_bizs = abap_true.
      EXIT.
    ENDIF.
  ENDLOOP.
ENDFORM.

*& BISM current-attempt business outcome authority
*& Exact current rejection > exact current success+DB > unresolved/queued.
*& Historical SUCCESS, DB existence and green session state alone cannot
*& override the current BISM attempt.

FORM apply_sm35_group
  USING    pt_group      TYPE ty_t_staging_alv
           pv_qstate     TYPE c
           pv_session    TYPE apqi-groupid
           pv_msg        TYPE string
           pv_first_err  TYPE string
           pv_error_dynn TYPE string
           pv_scope_groups TYPE i
           pv_proc_mode  TYPE c
  CHANGING cv_success    TYPE i
           cv_error      TYPE i
           cv_warning    TYPE i
           cv_processed  TYPE i
           cv_queued     TYPE i.

  DATA: ls_first        TYPE ty_staging_alv,
        lt_res          TYPE STANDARD TABLE OF zbdc_result_bup,
        ls_res          TYPE zbdc_result_bup,
        lv_has_error    TYPE abap_bool,
        lv_has_success  TYPE abap_bool,
        lv_has_warning  TYPE abap_bool,
        lv_status       TYPE c LENGTH 20,
        lv_final        TYPE string,
        lv_success_text TYPE string,
        lv_business_s   TYPE string,
        lv_tx_success    TYPE string,
        lv_admin_s      TYPE abap_bool,
        lv_text         TYPE string.

  READ TABLE pt_group INTO ls_first INDEX 1.
  IF sy-subrc <> 0.
    RETURN.
  ENDIF.

  IF ls_first-record_key IS INITIAL.
    SELECT * FROM zbdc_result_bup INTO TABLE @lt_res
      WHERE session_id = @ls_first-session_id
        AND row_index  = @ls_first-row_index
        AND field_name = 'SM35'.
  ELSE.
    SELECT * FROM zbdc_result_bup INTO TABLE @lt_res
      WHERE session_id = @ls_first-session_id
        AND record_key = @ls_first-record_key
        AND field_name = 'SM35'.
  ENDIF.
  SORT lt_res BY step.

  LOOP AT lt_res INTO ls_res.
    CASE ls_res-msg_type.
      WHEN 'E' OR 'A' OR 'X'.
        lv_has_error = abap_true.
        IF lv_final IS INITIAL.
          lv_final = ls_res-message.
        ENDIF.

      WHEN 'S'.
 "SAP can log a fatal Control Framework failure with MART='S'
 "during true SM35 background mode N. The importer stamps that exact
 "row SM35_BG_FATAL. It is ERROR evidence, never success evidence.
        IF ls_res-exec_status = 'SM35_BG_FATAL'.
          lv_has_error = abap_true.
          IF lv_final IS INITIAL AND ls_res-message IS NOT INITIAL.
            lv_final = ls_res-message.
          ENDIF.
        ELSEIF ls_res-exec_status <> 'SM35_DIAG'.
          CLEAR lv_admin_s.
          PERFORM is_sm35_admin_s USING ls_res CHANGING lv_admin_s.

          IF ls_res-exec_status = 'SM35_TX_OK'.
            lv_has_success = abap_true.
            IF ls_res-message IS NOT INITIAL.
              lv_tx_success = ls_res-message.
              lv_success_text = ls_res-message.
            ENDIF.
          ELSEIF lv_admin_s <> abap_true.
            lv_has_success = abap_true.
            IF ls_res-message IS NOT INITIAL.
              lv_success_text = ls_res-message.
              lv_business_s = ls_res-message.
            ENDIF.
          ENDIF.
        ENDIF.

      WHEN 'W'.
        lv_has_warning = abap_true.
    ENDCASE.
  ENDLOOP.

  IF lv_has_error = abap_true.
    lv_status = gc_st_error.
    IF lv_final IS INITIAL.
      lv_final = |SM35 exact per-group protocol returned an error for group { ls_first-record_key }.|.
    ENDIF.
    cv_error = cv_error + 1.

  ELSEIF lv_business_s IS NOT INITIAL.
    lv_status = gc_st_success.
    lv_final  = lv_business_s.
    cv_success = cv_success + 1.

  ELSEIF lv_has_success = abap_true.
    lv_status = gc_st_success.
    IF lv_tx_success IS NOT INITIAL.
      lv_final = |Exact SAP BISM transaction success: { lv_tx_success } No application business S-message was persisted for exact group { ls_first-record_key }.|.
    ELSEIF lv_success_text IS NOT INITIAL.
      lv_final = |SM35 session { pv_session } finished exact group { ls_first-record_key } successfully. Exact standard SAP protocol: { lv_success_text }. No application business S-message was persisted.|.
    ELSE.
      lv_final = |SM35 processed exact group { ls_first-record_key } with SAP success protocol; no application business S-message was persisted.|.
    ENDIF.
    cv_success = cv_success + 1.

  ELSE.
    CASE pv_qstate.
      WHEN 'F'.
        IF pv_scope_groups <= 1.
          lv_status = gc_st_success.
          lv_final = |SM35 session { pv_session } finished OK (APQI QSTATE=F) for the single exact group { ls_first-record_key }; no business S-message was persisted.|.
          cv_success = cv_success + 1.
        ELSE.
          lv_status = gc_st_partial.
          lv_final = |SM35 session { pv_session } finished OK at session level, but no exact per-group success protocol was persisted for { ls_first-record_key }; outcome is PARTIAL pending exact evidence.|.
          cv_warning = cv_warning + 1.
        ENDIF.

      WHEN 'E'.
 "QSTATE=E / SM35 Incorrect is a terminal execution failure,
 "not a warning. To preserve multi-group exactness, session-level E
 "may be assigned directly only when this exact scope contains one
 "business group. In a multi-group session, groups without their own
 "TCNT-mapped E/A/X evidence remain PARTIAL rather than smearing the
 "first transaction's error across unrelated groups.
        IF pv_scope_groups <= 1.
          lv_status = gc_st_error.
          IF pv_first_err IS NOT INITIAL.
            lv_text = pv_first_err.
            CONDENSE lv_text.
            lv_final = |SM35 session { pv_session } is Incorrect; execution error: { lv_text }|.
          ELSE.
            lv_final = |SM35 session { pv_session } is Incorrect (APQI QSTATE=E); review the exact SM35 protocol.|.
          ENDIF.
          cv_error = cv_error + 1.
        ELSE.
          lv_status = gc_st_partial.
          lv_final = |SM35 session { pv_session } is Incorrect at session level, but no exact TCNT-mapped E/A/X line proves failure for group { ls_first-record_key }; group outcome is PARTIAL until exact protocol is available.|.
          cv_warning = cv_warning + 1.
        ENDIF.

      WHEN 'R' OR 'S' OR 'C'.
        lv_status = gc_st_sm35q.
        lv_final = |SM35 session { pv_session } is still processing group { ls_first-record_key }.|.
        cv_queued = cv_queued + 1.

      WHEN OTHERS.
        lv_status = gc_st_sm35q.
        IF pv_msg IS INITIAL.
          lv_final = |SM35 session { pv_session } is queued for group { ls_first-record_key }.|.
        ELSE.
          lv_final = |{ pv_msg } Group { ls_first-record_key } remains queued in SM35.|.
        ENDIF.
        cv_queued = cv_queued + 1.
    ENDCASE.
  ENDIF.

  PERFORM set_sm35_group USING pt_group lv_status lv_final ''.
ENDFORM.

FORM reconcile_sm35
  USING pt_process TYPE ty_t_staging_alv
        pv_group   TYPE apqi-groupid
        pv_qid     TYPE apqi-qid
        pv_msg     TYPE string.

  DATA: lv_qstate      TYPE c LENGTH 1,
        lv_qid_local   TYPE apqi-qid,
        lv_log_count   TYPE i,
        lv_log_retry   TYPE abap_bool,
        lv_log_reason  TYPE string,
        lv_run_ok      TYPE abap_bool,
        lv_run_msg     TYPE string,
        lv_retry_attempt TYPE i,
        lt_sorted      TYPE ty_t_staging_alv,
        lt_group       TYPE ty_t_staging_alv,
        ls_row         TYPE ty_staging_alv,
        lv_prev_sid     TYPE zbdc_staging_bup-session_id,
        lv_prev_key     TYPE zbdc_staging_bup-record_key,
        lv_curr_key     TYPE zbdc_staging_bup-record_key,
        lv_first_error  TYPE string,
        lv_error_dynpro TYPE string,
        lv_grp_success   TYPE i,
        lv_grp_error     TYPE i,
        lv_grp_warning   TYPE i,
        lv_grp_processed TYPE i,
        lv_grp_queued    TYPE i,
        lv_bound_group   TYPE apqi-groupid,
        ls_z559_lock_row TYPE ty_staging_alv,
        lv_z559_can_run    TYPE abap_bool,
        lv_z559_locked     TYPE abap_bool,
        lv_z705_probe_count TYPE i,
        lv_z705_has_bizs    TYPE abap_bool,
        lv_z710_bg_gui      TYPE abap_bool,
        lv_z710_bg_msg      TYPE string,
        lv_z710_exact_err   TYPE string,
        lt_z716_keys        TYPE ty_t_engine_group_key,
        lv_z716_scope_groups TYPE i,
        lv_z736_sm35_mode   TYPE c LENGTH 1,
        lx_z560_error      TYPE REF TO cx_root.

  PERFORM find_sm35_group_for_scope
    USING pt_process CHANGING lv_bound_group.
  IF lv_bound_group IS INITIAL OR lv_bound_group <> pv_group.
    DATA(lv_zm906_2685_1) = |{ pv_group }|.
    MESSAGE ID 'ZBDC' TYPE 'S' NUMBER '906'
      WITH lv_zm906_2685_1 INTO gv_last_sm35_action.
    RETURN.
  ENDIF.

 "serialize the complete SM35 reconciliation for this ingestion
 "batch, not only OBJ_RESOLVE persistence. sync_sm35_logs, Z388 proof
 "rows and Z558 markers all allocate RESULT-STEP with MAX(step)+1. Without
 "one outer lock, two cockpit/SAP GUI sessions can read the same MAX and
 "race on the same record. Keep the lock through COMMIT so the next
 "reconciler can only observe committed RESULT rows. CT already uses the
 "same batch lock around its execution/result writers.
  READ TABLE pt_process INTO ls_z559_lock_row INDEX 1.
  IF sy-subrc <> 0 OR ls_z559_lock_row-session_id IS INITIAL.
    MESSAGE ID 'ZBDC' TYPE 'S' NUMBER '907' INTO gv_last_sm35_action.
    RETURN.
  ENDIF.

  CLEAR: lv_z559_can_run, lv_z559_locked.
  PERFORM acquire_staging_lock_safe
    USING    ls_z559_lock_row-session_id
    CHANGING lv_z559_can_run lv_z559_locked.
  IF lv_z559_can_run <> abap_true OR lv_z559_locked <> abap_true.
    MESSAGE ID 'ZBDC' TYPE 'S' NUMBER '908' INTO gv_last_sm35_action.
    RETURN.
  ENDIF.

 "protect the full post-acquire reconciliation transaction.
 "On a caught class-based failure: rollback while still owning the batch lock,
 "the enqueue, then fail loudly with the caught exception in ST22.
  TRY.

  IF gv_sm35_retry_group <> pv_group.
    gv_sm35_retry_group = pv_group.
    CLEAR gv_sm35_retry_count.
  ENDIF.

  lv_qid_local = pv_qid.
  IF lv_qid_local IS INITIAL AND pv_group IS NOT INITIAL.
    PERFORM find_sm35_qid_for_scope
      USING pt_process pv_group CHANGING lv_qid_local.
  ENDIF.

  CLEAR lv_qstate.
  IF lv_qid_local IS NOT INITIAL.
    SELECT SINGLE qstate
      FROM apqi
      INTO @lv_qstate
      WHERE mandant = @sy-mandt
        AND qid     = @lv_qid_local.
  ENDIF.

 "after terminal APQI/job evidence, give LOGALL TemSe a short
 "exact-QID stabilization window before persisting protocol lines. This
 "closes the observed race where QSTATE=F was visible before its log.
  IF lv_qid_local IS NOT INITIAL AND
     ( lv_qstate = 'F' OR lv_qstate = 'E' OR
       gv_last_sm35_jobname IS NOT INITIAL ).
    CLEAR: lv_z705_probe_count, lv_z705_has_bizs.
    PERFORM wait_sm35_protocol
      USING lv_qid_local
      CHANGING lv_z705_probe_count lv_z705_has_bizs.
  ENDIF.

 " Pull the standard SM35 TemSe protocol into ZBDC_RESULT_BUP. The same
 " detailed log then drives Dashboard, drill-down, export and retryability.
  CLEAR lv_z736_sm35_mode.
  PERFORM sync_sm35_logs
    USING    pt_process lv_qid_local
    CHANGING lv_log_count lv_log_retry lv_log_reason
             lv_z736_sm35_mode.
  PERFORM first_sm35_error
    USING lv_qid_local CHANGING lv_first_error lv_error_dynpro.

 "if standard SM35 Background mode itself proves a GUI/Control
 "Framework dependency, surface that exact technical incompatibility as
 "the current-attempt reason. Do not retry automatically and do not
 "hard-code the TCODE; the user can explicitly retry in E/A mode.
  CLEAR: lv_z710_bg_gui, lv_z710_bg_msg, lv_z710_exact_err.
  PERFORM detect_bg_gui_requirement
    USING lv_qid_local
    CHANGING lv_z710_bg_gui lv_z710_bg_msg.
  IF lv_z710_bg_gui = abap_true.
    lv_z710_exact_err = lv_first_error.
    IF lv_z710_exact_err IS INITIAL.
      lv_first_error = lv_z710_bg_msg.
    ELSE.
      lv_first_error = |{ lv_z710_bg_msg } Exact SAP error: { lv_z710_exact_err }|.
    ENDIF.
  ENDIF.

 "APQI=E is session-level evidence only. When TemSe cannot be
 "read, do not stamp the same synthetic ERROR onto every group. Exact group
 "ERROR is assigned later only from a TCNT-mapped SM35 protocol line.
  IF lv_qstate = 'E' AND lv_log_count = 0 AND lv_first_error IS INITIAL.
    lv_first_error = |SM35 session { pv_group } is Incorrect. Exact per-transaction protocol is not currently available.|.
  ENDIF.

 "standard SM35 owns processing. Reconciliation only reads the exact
 "bound QID/protocol after the user processes the session in SM35.
 "Refresh never starts a second execution and Retry never replays blindly.
  CLEAR: lv_run_ok, lv_run_msg, lv_retry_attempt.

 "Reconcile every business group independently. A session-level green icon
 "must never stamp all selected groups as processed without per-group protocol.
  REFRESH lt_z716_keys.
  PERFORM build_engine_keys
    USING    pt_process
    CHANGING lt_z716_keys.
  lv_z716_scope_groups = lines( lt_z716_keys ).
  IF lv_z716_scope_groups <= 0.
    lv_z716_scope_groups = 1.
  ENDIF.

  lt_sorted = pt_process.
  SORT lt_sorted BY session_id record_key row_index.
  CLEAR: lt_group, lv_prev_sid, lv_prev_key,
         lv_grp_success, lv_grp_error, lv_grp_warning,
         lv_grp_processed, lv_grp_queued.

  LOOP AT lt_sorted INTO ls_row.
    lv_curr_key = ls_row-record_key.
    IF lv_curr_key IS INITIAL.
      lv_curr_key = ls_row-row_index.
    ENDIF.

    IF lt_group IS NOT INITIAL AND
       ( ls_row-session_id <> lv_prev_sid OR lv_curr_key <> lv_prev_key ).
      PERFORM apply_sm35_group
        USING    lt_group lv_qstate pv_group pv_msg
                 lv_first_error lv_error_dynpro lv_z716_scope_groups
                 lv_z736_sm35_mode
        CHANGING lv_grp_success lv_grp_error
                 lv_grp_warning lv_grp_processed lv_grp_queued.
      CLEAR lt_group.
    ENDIF.

    APPEND ls_row TO lt_group.
    lv_prev_sid = ls_row-session_id.
    lv_prev_key = lv_curr_key.
  ENDLOOP.

  IF lt_group IS NOT INITIAL.
    PERFORM apply_sm35_group
      USING    lt_group lv_qstate pv_group pv_msg
               lv_first_error lv_error_dynpro lv_z716_scope_groups
               lv_z736_sm35_mode
      CHANGING lv_grp_success lv_grp_error
               lv_grp_warning lv_grp_processed lv_grp_queued.
  ENDIF.

  IF lv_grp_error > 0.
    IF lv_first_error IS NOT INITIAL.
      DATA(lv_zm909_2839_1) = |{ lv_grp_error }|.
      DATA(lv_zm909_2839_2) = |{ lv_grp_processed }|.
      DATA(lv_zm909_2839_3) = |{ lv_grp_warning }|.
      DATA(lv_zm909_2839_4) = |{ lv_first_error }|.
      MESSAGE ID 'ZBDC' TYPE 'S' NUMBER '909'
        WITH lv_zm909_2839_1 lv_zm909_2839_2 lv_zm909_2839_3 lv_zm909_2839_4
        INTO gv_last_sm35_action.
    ELSE.
      DATA(lv_zm910_2841_1) = |{ lv_grp_error }|.
      DATA(lv_zm910_2841_2) = |{ lv_grp_processed }|.
      DATA(lv_zm910_2841_3) = |{ lv_grp_warning }|.
      DATA(lv_zm910_2841_4) = |{ lv_grp_queued }|.
      MESSAGE ID 'ZBDC' TYPE 'S' NUMBER '910'
        WITH lv_zm910_2841_1 lv_zm910_2841_2 lv_zm910_2841_3 lv_zm910_2841_4
        INTO gv_last_sm35_action.
    ENDIF.
  ELSEIF lv_grp_warning > 0.
    DATA(lv_zm911_2844_1) = |{ lv_grp_warning }|.
    DATA(lv_zm911_2844_2) = |{ lv_grp_processed }|.
    MESSAGE ID 'ZBDC' TYPE 'S' NUMBER '911'
      WITH lv_zm911_2844_1 lv_zm911_2844_2 INTO gv_last_sm35_action.
  ELSEIF lv_grp_success > 0 OR lv_grp_processed > 0.
    DATA(lv_zm912_2846_1) = |{ lv_grp_success }|.
    DATA(lv_zm912_2846_2) = |{ lv_grp_processed }|.
    MESSAGE ID 'ZBDC' TYPE 'S' NUMBER '912'
      WITH lv_zm912_2846_1 lv_zm912_2846_2 INTO gv_last_sm35_action.
  ELSEIF lv_grp_queued > 0.
    DATA(lv_zm913_2849_1) = |{ pv_group }|.
    DATA(lv_zm913_2849_2) = |{ lv_grp_queued }|.
    MESSAGE ID 'ZBDC' TYPE 'S' NUMBER '913'
      WITH lv_zm913_2849_1 lv_zm913_2849_2 INTO gv_last_sm35_action.
  ELSE.
    MESSAGE ID 'ZBDC' TYPE 'S' NUMBER '914' INTO gv_last_sm35_action.
  ENDIF.
 "commit every STEP writer while the batch lock is still held.
 "Only then it, so a second reconciler sees the committed MAX(step).
  COMMIT WORK AND WAIT.

  CATCH cx_root INTO lx_z560_error.
 "rollback before DEQUEUE so no second reconciler can enter while
 "this SAP LUW still contains partial uncommitted reconciliation writes.
    ROLLBACK WORK.
    IF lv_z559_locked = abap_true.
      PERFORM release_staging_lock USING ls_z559_lock_row-session_id.
      CLEAR lv_z559_locked.
    ENDIF.
 "Do not downgrade/swallow an internal reconciliation failure.
    RAISE SHORTDUMP lx_z560_error.
  ENDTRY.

  IF lv_z559_locked = abap_true.
    PERFORM release_staging_lock USING ls_z559_lock_row-session_id.
    CLEAR lv_z559_locked.
  ENDIF.
  PERFORM prepare_alv_0400.
  PERFORM build_exec_cockpit.
ENDFORM.

FORM stamp_sm35_action
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

*& PREVIEW_ENGINE_PLAN - thong bao tom tat truoc khi execute

*& COMMIT_CHUNK_IF_DUE - commit theo lo de giam risk update task/lock

*& RUN_BDC_ONE_GROUP - 1 RECORD_KEY/business group = 1 document SAP
*& Responsibilities:
*& Build BDCDATA tu PRE + ITEM(n) + POST
*& Batch Input mode: BDC_INSERT
*& CALL TRANSACTION: retry only transient technical failures
*& Success/object: exact certified SAP protocol, never arbitrary tokens
*& Update staging/result/UI counters

*& runtime rule
*& A deterministic dynpro-contract failure quarantines the exact profile.
*& Productive execution never deletes recorded fields and never retries by
*& mutating BDCDATA, because that would change the certified scenario.

*& Fail-closed generic DB verifier bootstrap (onboarding only)

*& Goal:
*& An explicit onboarding/certification replay may return a real SAP object
*& before VERIFY_TABLE/VERIFY_FIELD has been frozen. Do not promote that
*& object from protocol alone. Instead learn the verifier only when one
*& unique transparent DDIC table can be proven by BOTH:
*& 1) the exact hidden &ZBDC_TRACE& value written by this frozen script;
*& 2) the exact SAP object token in one primary-key field of that row.
*& No TCODE, business table, business field, object number, or "latest"
*& profile is hardcoded or guessed. Ambiguity always fails closed.
*& production Run Selected/Run All never calls this bootstrap path.

*& DDIC-safe SAP Object candidate guard

*& Prevents CONVT_OVERFLOW / conversion dumps while the generic structural
*& verifier scans candidate key fields. A protocol object is compared only
*& with DDIC types that can represent the token without truncation/overflow.
*& This is metadata-driven and contains no TCODE/table/field hardcoding.

*& Generic structural DB verifier bootstrap without trace

*& The bootstrap starts only from:
*& the exact frozen runtime Mapping/Profile,
*& the exact SAP object token from a synchronous success protocol,
*& active DDIC metadata, and
*& exact mapped source values that are present in the candidate DB row.
*& Candidate tables are derived from mapped BDC component names. Generic
*& same-leaf candidates stay strict: transparent table, mapped DDIC overlap,
*& object in a non-client key and one exact source-matched row. adds a
*& stronger direct-contract path for explicit transparent TABLE-FIELD prefixes:
*& only the first non-client primary key may hold the exact terminal SAP object,
*& and one-or-more persisted rows are valid for composite object+item tables.
*& Ties still fail closed. No TCODE/table/field name is hardcoded.

*& DDIC semantic-owner resolver for externally supplied keys

*& Some creation transactions use an object key that is also part of the
*& submitted BDC input. A broad FIELDNAME scan can reach the foreground
*& safety budget before the semantic owner table is tested. Resolve that
*& case from SAP Dictionary semantics first:
*& Mapping BDC field -> exact screen DDIC component -> CHECKTABLE and/or
*& DOMAIN value table -> first non-client primary key -> exact DB row.
*& The protocol candidate must normalize to the exact submitted mapped value.
*& No TCODE, table, object field, message number or business text is known.

*& Semantic header resolver for SAP-generated object numbers

*& intentionally resolves only the case where the terminal object key
*& is also an uploaded source value. Creation transactions may instead let
*& SAP assign the key internally. In that case candidate == source can never
*& be true even though the terminal S-message contains the correct object.

*& This resolver is still fully generic. It derives candidate header tables
*& only from the frozen Mapping and SAP Dictionary metadata:
*& BDC component -> screen DDIC data element (ROLLNAME) -> transparent-table
*& fields using the same field + data element -> table primary key -> exact DB row.

*& A table is accepted only when:
*& it is an active transparent table;
*& it has exactly one non-client primary key (header-object shape);
*& the protocol candidate fits and exists in that primary key;
*& at least one exact submitted mapped value matches the same DB row;
*& one semantic candidate wins uniquely after deterministic ranking.

*& No TCODE, application table, object field, message number or business text
*& is hardcoded. Ambiguity/no match remains fail-closed and falls through to
*& the older broad structural scanner.

*& Session-backed generic Object Discovery context

*& SAP Object discovery must work for every onboarded TCODE without requiring
*& a pre-existing ZBDC_CERT_BUP verifier row. The immutable execution SESSION
*& is the authority for TCODE/Profile/Version/Script/Contract-Hash. We first
*& prove that exact tuple still owns one persisted script header. If an exact
*& certificate exists it is loaded unchanged; otherwise a transient runtime
*& context is constructed from the frozen session tuple. This unlocks the
*& same Mapping + SHDB + DDIC BEFORE/AFTER discovery path for a brand-new
*& transaction while keeping execution and object identity as separate truths.
*& No TCODE/table/key/object value is hardcoded or guessed here.

*& Freeze one deterministic Object Verification Contract

*& A verifier may be filled automatically only after a generic DDIC/DB
*& discovery has ALREADY proved one exact table/key for one real SAP object.
*& Existing verifier metadata is immutable: equal is accepted, different is
*& a hard conflict. No TCODE/table/field/message literal is hardcoded.

*& Generic protocol candidate -> DDIC/DB object verification

*& A terminal SAP success message may expose a candidate object token, but
*& that token is never enough to populate SAP_OBJECT_ID. Resolve the object
*& generically from the frozen Mapping + DDIC structure, then re-read the
*& exact candidate from the discovered transparent table/key.

*& Rules:
*& no TCODE/table/field/message hardcode;
*& an existing frozen verifier is authoritative and may not be replaced;
*& when no verifier exists, post-success discovery may fill only a blank
*& verifier for the exact immutable runtime contract;
*& an existing different verifier is never replaced;
*& caller may claim SAP_OBJECT_ID only when CV_OK = ABAP_TRUE.

*& Frozen certified success-protocol object resolver

*& Purpose:
*& Once onboarding has certified an exact SAP success MSGID/MSGNR (and,
*& where available, the exact MSGV position), later executions must use
*& that frozen protocol contract before falling back to heuristic terminal
*& scanning. Foreground/all-screen runs can leave later informational S
*& messages after the business save; the created object is still carried by
*& the earlier frozen success line. This resolver scans ONLY the frozen
*& message class/number, extracts the object with the frozen MSGV binding or
*& the existing exact-message parser, and requires exact DB verification.
*& Safety:
*& no TCODE/message/table/field hardcode;
*& no newest/high-water object guess;
*& multiple distinct DB-proven objects => conflict;
*& absence of the frozen line => no object guessed.

*& Exact terminal token x repository-key DB proof

*& WHY COULD STILL RETURN NONE:
*& Z609 tried to discover a DB owner for each terminal token by walking a
*& semantic-owner chain. A valid SAP key can exist in the frozen SHDB/DDIC
*& candidate universe yet fail that owner walk (screen structure != persisted
*& header, composite keys, shared data elements). The terminal value was
*& therefore thrown away before the already-known repository key candidates
*& were tested directly.

*& reverses that last dependency without guessing anything:
*& 1) derive TABLE/primary-key candidates only from frozen Mapping + SHDB +
*& active SAP DDIC (Z602);
*& 2) read only direct SAP BDCMSGCOLL MSGV1..4 from S/I protocol rows;
*& 3) test token x candidate pair with exact Open SQL equality through the
*& common DDIC conversion and exact-equality verification;
*& 4) choose only the strongest generated-key tier. Equal object IDs across
*& tables are corroboration; different values at the same strongest tier
*& are CONFLICT, never guessed;
*& 5) AI metadata may break only an equal projection tie. It never supplies
*& the object value and is not required for success.

*& Every DB read is exact equality on an SAP primary-key component. There is no
*& TCODE/table/field/message-class CASE and no high-water/newest-row inference.

*& Direct terminal MSGV token without year/length false negatives

*& Direct BDCMSGCOLL message variables are structured SAP protocol fields,
*& not free-text tokens. The older broad parser intentionally rejected a
*& four-digit numeric value because it might be a year; that rule is unsafe
*& here because a legitimate generated SAP key may itself be 0001/1001/etc.
*& Keep this parser permissive only for direct MSGV1..MSGV4. No token is an
*& SAP Object by itself: Z609_PROBE_TERMINAL_CANDIDATE must still prove one
*& exact transparent DB field for the same frozen execution contract.

*& Read-only terminal candidate -> exact DDIC/DB projection

*& This helper deliberately does NOT persist VERIFY_TABLE/VERIFY_FIELD.
*& It tests, in order:
*& 1) PRE-execution metadata/AI hint (if any),
*& 2) an already frozen verifier,
*& 3) generic DDIC semantic owner,
*& 4) generic semantic header,
*& 5) bounded structural owner discovery.
*& The candidate must exist in the returned DB field. Generated-key rank is
*& returned only as deterministic evidence for resolving composite SAP
*& messages (type/number/version/part); it never manufactures an object ID.

*& Terminal protocol candidates are resolved AFTER DB proof

*& Older logic demanded one unique syntactic token before asking SAP DB. That
*& is backwards for composite success messages: several MSGV values may be
*& valid key qualifiers, while only one is the generated business identifier.
*& first DB-proves every direct terminal MSGV, then selects only among
*& those SAP-proven projections. Highest generated-key rank wins; a PRE
*& metadata/AI TABLE/FIELD hint breaks only an equal-rank metadata tie. The
*& object VALUE always comes from BDCMSGCOLL + SAP DB, never from AI.

*& Bounded repository-owner structural BEFORE snapshots

*& built a full DDIC candidate universe and SELECTed up to 500 rows for
*& every table/key pair before SAP ran. On real systems that made a single
*& create execution take around 100 seconds and still did not improve authority. builds the
*& same repository/DDIC metadata list but snapshots only the top bounded pairs
*& (max 4) by generated/direct/semantic rank. AI-selected metadata is merged
*& separately by Z598. AFTER-BEFORE remains the authority; this form only
*& limits the evidence acquisition cost and contains no TCODE/table hardcode.

*& Deterministic CT SAP Object resolver

*& Authority chain:
*& terminal SAP S-message -> unique strict candidate -> generic DDIC/DB
*& owner proof -> immutable Object Verification Contract -> exact DB recheck.
*& No AI, TCODE branch, business table list or message-class list is used.

*& Deterministic SM35 SAP Object resolver

*& Reads only exact current SM35 S-protocol rows already imported from the
*& bound QID. Each protocol candidate must pass the same generic DDIC/DB proof
*& used by CT. Distinct proven candidates are a conflict; no representative
*& object is guessed for multi-object groups.

*& immediate terminal projection for synchronous CT on screen 0500
*& The business result is already persisted inside RUN_BDC_ONE_GROUP. Do
*& not wait for the outer monitor loop to project that result, because a
*& foreground CALL TRANSACTION roundtrip can return control to SAP GUI before
*& the outer repaint becomes visible. Project the exact terminal group into
*& GT_EXEC_QSTATE immediately, then rebuild/flush the 0500 ALV. This is UI
*& synchronization only: it never changes staging/result truth and it never
*& infers success from SY-SUBRC, message text, TCODE, table or business field.

*& Load the exact persisted Script Version as one ordered stream

*& S1 EXACT execution must not depend on PRE/POST projection arrays. The
*& immutable Script Steps table is the execution source of truth. This keeps
*& every dynpro boundary and every field row in the same STEP_SEQ order that
*& was frozen at publication time. No TCODE/dynpro/business-field knowledge
*& is used here.

*& EXEC FIDELITY - runtime raw SHDB loader

*& Prefer the immutable RAW recording snapshot linked to the frozen Script
*& ID. This bypasses historical compiler VALUE_TYPE/IGNORE transformations.
*& If an older profile has no RAW link, fall back to its persisted compiled
*& stream so existing profiles remain executable. No TCODE-specific logic.

FORM load_runtime_raw
  USING    iv_tcode     TYPE sy-tcode
           iv_script_id TYPE zbdc_script_bup-script_id
  CHANGING ct_script    TYPE ty_t_script
           cv_ok        TYPE abap_bool
           cv_message   TYPE string.

  DATA: lv_raw_cfg    TYPE zbdc_config_bup-config_value,
        lv_raw_id     TYPE zbdc_script_bup-script_id,
        lv_raw_source TYPE zbdc_config_bup-config_value,
        lt_steps      TYPE STANDARD TABLE OF zbdc_sct_ver_bup,
        lt_owner      TYPE STANDARD TABLE OF zbdc_sct_ver_bup,
        ls_step       TYPE zbdc_sct_ver_bup,
        ls_owner      TYPE zbdc_sct_ver_bup,
        ls_script     TYPE ty_script_def_compat,
        lv_prev       TYPE zbdc_sct_ver_bup-step_seq,
        lv_raw_log    TYPE zbdc_mapping_bup-bdc_field,
        lv_own_log    TYPE zbdc_mapping_bup-bdc_field,
        lv_overlay    TYPE abap_bool.

  CLEAR: cv_ok, cv_message, lv_prev, lv_raw_source,
         lv_raw_cfg, lv_raw_id.
  REFRESH: ct_script, lt_steps, lt_owner.

  IF iv_script_id IS INITIAL.
    cv_message = 'Runtime SHDB fidelity loader has no frozen Script ID.'.
    RETURN.
  ENDIF.

 "EXEC_RAW is the immutable execution snapshot captured by the same
 "successful Import/Start Recording action that published this Script. It is
 "the canonical replay source. RAWQID remains audit provenance only; runtime
 "must not silently switch to a different/stale APQI object after onboarding.
  PERFORM get_script_cfg
    USING iv_script_id 'EXEC_RAW'
    CHANGING lv_raw_cfg.
  IF lv_raw_cfg IS INITIAL.
    PERFORM get_script_cfg
      USING iv_script_id 'RAW'
      CHANGING lv_raw_cfg.
  ENDIF.
  lv_raw_id = lv_raw_cfg.

  PERFORM get_script_cfg
    USING iv_script_id 'RAWSOURCE'
    CHANGING lv_raw_source.
  TRANSLATE lv_raw_source TO UPPER CASE.
  CONDENSE lv_raw_source NO-GAPS.

  IF lv_raw_id IS INITIAL.
    IF lv_raw_source = 'SAP_APQI'.
      cv_message =
        'EXEC_SOURCE_MISSING: Start Recording provenance exists but no immutable EXEC_RAW snapshot is bound. Start Recording again; runtime will not use a possibly stale RAWQID.' .
    ELSE.
      cv_message =
        'EXEC_SOURCE_MISSING: no EXEC_RAW/RAW canonical SHDB snapshot is bound to this Script. Import or Start Recording again.' .
    ENDIF.
    RETURN.
  ENDIF.

  SELECT *
    FROM zbdc_sct_ver_bup
    INTO TABLE @lt_steps
    WHERE script_id = @lv_raw_id
    ORDER BY step_seq.

  IF lt_steps IS INITIAL.
    cv_message = |Immutable execution snapshot { lv_raw_id } contains no rows.|.
    RETURN.
  ENDIF.

 "Compiled rows provide metadata only (DYNAMIC/SOURCE_COLUMN/ROW_TYPE).
 "They are never allowed to replace PROGRAM/DYNPRO/FNAM/FVAL from EXEC_RAW.
  SELECT *
    FROM zbdc_sct_ver_bup
    INTO TABLE @lt_owner
    WHERE script_id = @iv_script_id.

  LOOP AT lt_steps INTO ls_step.
    IF lv_prev IS NOT INITIAL AND ls_step-step_seq <= lv_prev.
      cv_message =
        |EXEC_RAW snapshot { lv_raw_id } has non-monotonic STEP_SEQ at { ls_step-step_seq }.|.
      REFRESH ct_script.
      RETURN.
    ENDIF.
    lv_prev = ls_step-step_seq.

    CLEAR ls_script.
    ls_script-tcode         = iv_tcode.
    ls_script-step_seq      = ls_step-step_seq.
    ls_script-is_new_screen = ls_step-is_new_screen.
    ls_script-field_name    = ls_step-field_name.
    ls_script-value_type    = ls_step-value_type.
    ls_script-static_value  = ls_step-static_value.
    ls_script-source_column = ls_step-source_column.
    ls_script-row_type      = ls_step-row_type.
    ls_script-program_name  = ls_step-program_name.
    ls_script-dynpro_no     = ls_step-dynpro_no.

 "Overlay classification only when the compiled row is the exact same
 "occurrence. STEP_SEQ + logical FNAM are both required; no positional or
 "SOURCE_COLUMN-only ownership is accepted.
    CLEAR: ls_owner, lv_overlay, lv_raw_log, lv_own_log.
    READ TABLE lt_owner INTO ls_owner WITH KEY step_seq = ls_step-step_seq.
    IF sy-subrc = 0.
      IF ls_step-is_new_screen = 'X'.
        IF ls_owner-is_new_screen = 'X'
           AND ls_owner-program_name = ls_step-program_name
           AND ls_owner-dynpro_no = ls_step-dynpro_no.
          lv_overlay = abap_true.
        ENDIF.
      ELSEIF ls_step-field_name IS NOT INITIAL
         AND ls_owner-is_new_screen IS INITIAL
         AND ls_owner-field_name IS NOT INITIAL.
        PERFORM logical_bdc_key
          USING ls_step-field_name CHANGING lv_raw_log.
        PERFORM logical_bdc_key
          USING ls_owner-field_name CHANGING lv_own_log.
        IF lv_raw_log IS NOT INITIAL AND lv_raw_log = lv_own_log.
          lv_overlay = abap_true.
        ENDIF.
      ENDIF.
    ENDIF.

    IF lv_overlay = abap_true.
      ls_script-value_type    = ls_owner-value_type.
      ls_script-source_column = ls_owner-source_column.
      ls_script-row_type      = ls_owner-row_type.
    ENDIF.

    APPEND ls_script TO ct_script.
  ENDLOOP.

  IF ct_script IS INITIAL.
    cv_message = |Immutable execution snapshot { lv_raw_id } contains no executable rows.|.
    RETURN.
  ENDIF.

  cv_ok = abap_true.
  cv_message =
    |Canonical EXEC_RAW snapshot { lv_raw_id } loaded; compiled metadata was overlaid only by exact STEP_SEQ/FNAM ownership.|.
ENDFORM.

*& Exact dynpro sequence proof

*& Prove every populated mapped DYNAMIC value reached FINAL BDCDATA

*& This is the missing deterministic boundary between Mapping/Staging and the
*& two executors. A populated mapped source may never disappear silently.
*& For EXACT S1, each such Mapping row must resolve to an existing DYNAMIC
*& Script row and that row must be emitted under its owning Program/Dynpro in
*& the prepared BDCDATA. CT and BISM therefore receive the same proven stream.

*& Z600 - Analyze CURRENT canonical recording with CURRENT Mapping

*& Derive the exact raw repeat window AFTER compiler cardinality proof
*&
*& This helper is not the authority that permits multi-row. M3_VALID first
*& proves the frozen compiled Script contains a compiler-proven ITEM plan.
*& Here Mapping wildcards are used only to locate that proven family inside
*& immutable EXEC_RAW while preserving PROGRAM/DYNPRO/STEP order.

FORM repeat_bounds
  USING    pt_raw       TYPE ty_t_script
           pt_map       TYPE ty_t_map
  CHANGING cv_has_repeat TYPE abap_bool
           cv_start_seq TYPE zbdc_sct_ver_bup-step_seq
           cv_next_seq  TYPE zbdc_sct_ver_bup-step_seq
           cv_message   TYPE string.

  DATA: ls_scr         TYPE ty_script_def_compat,
        ls_map         TYPE zbdc_mapping_bup,
        lv_screen_seq  TYPE zbdc_sct_ver_bup-step_seq,
        lv_last_screen TYPE zbdc_sct_ver_bup-step_seq,
        lv_scr_bdc     TYPE zbdc_mapping_bup-bdc_field,
        lv_scr_log     TYPE zbdc_mapping_bup-bdc_field,
        lv_map_bdc     TYPE zbdc_mapping_bup-bdc_field,
        lv_map_log     TYPE zbdc_mapping_bup-bdc_field,
        lv_pattern     TYPE string.

  CLEAR: cv_has_repeat, cv_start_seq, cv_next_seq, cv_message,
         lv_screen_seq, lv_last_screen.

  LOOP AT pt_raw INTO ls_scr.
    IF ls_scr-is_new_screen = 'X'.
      lv_screen_seq = ls_scr-step_seq.
      CONTINUE.
    ENDIF.
    IF ls_scr-field_name IS INITIAL OR lv_screen_seq IS INITIAL.
      CONTINUE.
    ENDIF.

    lv_scr_bdc = ls_scr-field_name.
    PERFORM normalize_mapping_bdc_field
      USING    lv_scr_bdc
      CHANGING lv_scr_bdc.
    PERFORM logical_bdc_key
      USING    lv_scr_bdc
      CHANGING lv_scr_log.
    IF lv_scr_log IS INITIAL.
      CONTINUE.
    ENDIF.

    LOOP AT pt_map INTO ls_map WHERE bdc_field IS NOT INITIAL.
      lv_pattern = ls_map-bdc_field.
      IF lv_pattern NS '(*)' AND lv_pattern NS '&IDX&'.
        CONTINUE.
      ENDIF.

      lv_map_bdc = ls_map-bdc_field.
      PERFORM normalize_mapping_bdc_field
        USING    lv_map_bdc
        CHANGING lv_map_bdc.
      PERFORM logical_bdc_key
        USING    lv_map_bdc
        CHANGING lv_map_log.

      IF lv_map_log = lv_scr_log.
        IF cv_has_repeat <> abap_true.
          cv_start_seq = lv_screen_seq.
          cv_has_repeat = abap_true.
        ENDIF.
        lv_last_screen = lv_screen_seq.
        EXIT.
      ENDIF.
    ENDLOOP.
  ENDLOOP.

  IF cv_has_repeat <> abap_true.
    cv_message = 'No repeatable Mapping field exists in the current canonical SHDB recording.'.
    RETURN.
  ENDIF.

  LOOP AT pt_raw INTO ls_scr
    WHERE is_new_screen = 'X'
      AND step_seq > lv_last_screen.
    cv_next_seq = ls_scr-step_seq.
    EXIT.
  ENDLOOP.

  cv_message =
    |Recording repeat window derived from Mapping: start={ cv_start_seq }, next={ cv_next_seq }.|.
ENDFORM.

*& Self-contained exact-occurrence replay adapter

*& Keep M3 independent of the historical z590 FORM signature. Some SAP
*& systems may still have the previous active M2 include (4 parameters)
*& while M2 defines z590 with 5 parameters. This adapter owns the
*& exact-occurrence resolution used by M3 and therefore compiles with either
*& active M2 signature. It does NOT call z590.

FORM append_exec_exact_step
  USING    ps_scr TYPE ty_script_def_compat
           ps_row TYPE ty_staging_alv
           pt_map TYPE ty_t_map
           pt_raw TYPE ty_t_script
           pv_idx TYPE any.

  DATA: lv_fnam        TYPE bdcdata-fnam,
        lv_fval        TYPE bdcdata-fval,
        lv_field_text  TYPE string,
        lv_value_text  TYPE string,
        lv_scr_src     TYPE zbdc_mapping_bup-source_column,
        lv_map_src     TYPE zbdc_mapping_bup-source_column,
        lv_scr_bdc     TYPE zbdc_mapping_bup-bdc_field,
        lv_map_bdc     TYPE zbdc_mapping_bup-bdc_field,
        lv_scr_log     TYPE zbdc_mapping_bup-bdc_field,
        lv_map_log     TYPE zbdc_mapping_bup-bdc_field,
        lv_technical   TYPE abap_bool,
        lv_map_count   TYPE i,
        lv_idx_changed TYPE abap_bool,
        ls_map         TYPE zbdc_mapping_bup,
        ls_map_hit     TYPE zbdc_mapping_bup.

  FIELD-SYMBOLS <lv_stage> TYPE any.

  IF gv_bdc_build_failed = abap_true.
    RETURN.
  ENDIF.

  IF ps_scr-is_new_screen = 'X'.
    IF ps_scr-program_name IS INITIAL OR ps_scr-dynpro_no IS INITIAL.
      gv_bdc_build_failed = abap_true.
      gv_bdc_build_message =
        |SHDB fidelity error at step { ps_scr-step_seq }: Program/Dynpro is missing.|.
      RETURN.
    ENDIF.
    PERFORM bdc_dynpro USING ps_scr-program_name ps_scr-dynpro_no.
    RETURN.
  ENDIF.

  IF ps_scr-field_name IS INITIAL.
    gv_bdc_build_failed = abap_true.
    gv_bdc_build_message =
      |SHDB fidelity error at step { ps_scr-step_seq }: field name is blank.|.
    RETURN.
  ENDIF.

  IF ps_scr-static_value CS gc_trace_token.
    RETURN.
  ENDIF.

  lv_field_text = ps_scr-field_name.
  PERFORM exec_apply_idx_token
    USING lv_field_text pv_idx
    CHANGING lv_field_text.
  lv_fnam = lv_field_text.
  lv_value_text = ps_scr-static_value.

  CLEAR lv_technical.
  PERFORM mapping_field_is_technical
    USING ps_scr-field_name
    CHANGING lv_technical.

 "a Mapping row is NOT authority by itself. A value may replace a
 "recorded FVAL only when this exact frozen Script occurrence is DYNAMIC and
 "owns SOURCE_COLUMN, and Mapping agrees on BOTH SAP FNAM and SOURCE_COLUMN.
 "STATIC/blank/technical rows are replayed exactly as recorded.
  IF lv_technical <> abap_true
     AND ps_scr-value_type = 'DYNAMIC'
     AND ps_scr-source_column IS NOT INITIAL.

    CLEAR: lv_scr_bdc, lv_scr_log, lv_scr_src,
           lv_map_count, ls_map_hit.
    PERFORM normalize_mapping_bdc_field
      USING ps_scr-field_name CHANGING lv_scr_bdc.
    PERFORM logical_bdc_key
      USING lv_scr_bdc CHANGING lv_scr_log.
    PERFORM normalize_mapping_source
      USING ps_scr-source_column CHANGING lv_scr_src.

    LOOP AT pt_map INTO ls_map WHERE bdc_field IS NOT INITIAL.
      IF ls_map-staging_field = 'FIELD01'.
        CONTINUE.
      ENDIF.
      CLEAR: lv_map_bdc, lv_map_log, lv_map_src.
      PERFORM normalize_mapping_bdc_field
        USING ls_map-bdc_field CHANGING lv_map_bdc.
      PERFORM logical_bdc_key
        USING lv_map_bdc CHANGING lv_map_log.
      PERFORM normalize_mapping_source
        USING ls_map-source_column CHANGING lv_map_src.
      IF lv_map_log = lv_scr_log AND lv_map_src = lv_scr_src.
        lv_map_count = lv_map_count + 1.
        ls_map_hit = ls_map.
      ENDIF.
    ENDLOOP.

    IF lv_map_count = 0.
      gv_bdc_build_failed = abap_true.
      gv_bdc_build_message =
        |DYNAMIC_MAPPING_MISSING: step { ps_scr-step_seq } field { ps_scr-field_name } source { ps_scr-source_column } has no exact Mapping owner.|.
      RETURN.
    ELSEIF lv_map_count > 1.
      gv_bdc_build_failed = abap_true.
      gv_bdc_build_message =
        |DYNAMIC_MAPPING_CONFLICT: step { ps_scr-step_seq } field { ps_scr-field_name } source { ps_scr-source_column } has { lv_map_count } Mapping owners.|.
      RETURN.
    ENDIF.

    IF ls_map_hit-staging_field IS INITIAL.
      gv_bdc_build_failed = abap_true.
      gv_bdc_build_message =
        |Mapping { ls_map_hit-source_column } has no staging field.|.
      RETURN.
    ENDIF.

    ASSIGN COMPONENT ls_map_hit-staging_field OF STRUCTURE ps_row TO <lv_stage>.
    IF sy-subrc <> 0 OR <lv_stage> IS NOT ASSIGNED.
      gv_bdc_build_failed = abap_true.
      gv_bdc_build_message =
        |Staging field { ls_map_hit-staging_field } does not exist for Mapping { ls_map_hit-source_column }.|.
      RETURN.
    ENDIF.

    lv_value_text = <lv_stage>.
    IF lv_value_text IS INITIAL.
      gv_bdc_build_failed = abap_true.
      gv_bdc_build_message =
        |DYNAMIC_INPUT_BLANK_BLOCKED: { ls_map_hit-source_column } is blank before SAP replay. Dynamic business data never falls back to recorded/static FVAL.|.
      RETURN.
    ENDIF.

    CLEAR lv_idx_changed.
    PERFORM indexed_from_map
      USING ps_scr-field_name pt_map pv_idx
      CHANGING lv_field_text lv_idx_changed.
    IF lv_idx_changed = abap_true.
      lv_fnam = lv_field_text.
    ENDIF.
  ENDIF.

  IF lv_fnam = 'BDC_CURSOR'.
    CLEAR lv_idx_changed.
    PERFORM indexed_from_map
      USING lv_value_text pt_map pv_idx
      CHANGING lv_value_text lv_idx_changed.
    IF lv_idx_changed <> abap_true.
      PERFORM exec_apply_idx_token
        USING lv_value_text pv_idx
        CHANGING lv_value_text.
    ENDIF.
  ENDIF.

  lv_fval = lv_value_text.

 "Exact append: never route through legacy BDC_FIELD, which can drop blank
 "FVAL rows. PROGRAM/DYNPRO/FNAM/order remain recording-owned.
  CLEAR bdcdata.
  bdcdata-fnam = lv_fnam.
  bdcdata-fval = lv_fval.
  APPEND bdcdata.
ENDFORM.

*& Direct immutable EXEC_RAW single-row execution for Start Recording

*& For Guided Start Recording, SAP already owns the canonical %BDC object.
*& A one-row business group needs no item-window expansion, so rebuilding that
*& native BDCDATA through Script rows is unnecessary and can change runtime
*& behavior. This path reads the SAP QID again, strips only the recording
*& transaction wrapper before the first real DYNBEGIN='X', preserves every
*& executable PROGRAM/DYNPRO/FNAM/order byte-for-byte, and changes FVAL only
*& for fields explicitly bound by Mapping. CT and SM35 both consume the same
*& resulting table through Z482. Imported TXT and multi-row groups keep the
*& existing generic projector because they may require repeat expansion.

FORM native_single_bdc
  USING    iv_script_id TYPE zbdc_script_bup-script_id
           ps_row       TYPE ty_staging_alv
           pt_map       TYPE ty_t_map
  CHANGING ct_bdc       TYPE ty_t_async_bdcdata
           cv_handled   TYPE abap_bool
           cv_ok        TYPE abap_bool
           cv_message   TYPE string.

  DATA: lv_source      TYPE zbdc_config_bup-config_value,
        lt_raw         TYPE ty_t_script,
        ls_raw         TYPE ty_script_def_compat,
        lv_raw_ok      TYPE abap_bool,
        lv_raw_msg     TYPE string,
        lv_technical   TYPE abap_bool,
        lv_scr_bdc     TYPE zbdc_mapping_bup-bdc_field,
        lv_scr_log     TYPE zbdc_mapping_bup-bdc_field,
        lv_scr_src     TYPE zbdc_mapping_bup-source_column,
        lv_map_bdc     TYPE zbdc_mapping_bup-bdc_field,
        lv_map_log     TYPE zbdc_mapping_bup-bdc_field,
        lv_map_src     TYPE zbdc_mapping_bup-source_column,
        lv_map_count   TYPE i,
        lv_value_text  TYPE string,
        ls_map         TYPE zbdc_mapping_bup,
        ls_map_hit     TYPE zbdc_mapping_bup,
        ls_out         TYPE bdcdata.

  FIELD-SYMBOLS <lv_stage> TYPE any.

  CLEAR: cv_handled, cv_ok, cv_message, lv_source.
  REFRESH: ct_bdc, lt_raw.

  IF iv_script_id IS INITIAL.
    RETURN.
  ENDIF.

  PERFORM get_script_cfg
    USING iv_script_id 'RAWSOURCE'
    CHANGING lv_source.
  TRANSLATE lv_source TO UPPER CASE.
  CONDENSE lv_source NO-GAPS.

  IF lv_source <> 'SAP_APQI'.
    RETURN.
  ENDIF.

  cv_handled = abap_true.

 "direct replay comes from the immutable EXEC_RAW snapshot, not from
 "RAWQID. Start Recording writes EXEC_RAW and RAWQID in one successful
 "onboarding action; EXEC_RAW is the stable canonical stream while RAWQID is
 "retained only as SAP audit provenance. This prevents an old/rebound APQI
 "queue from silently changing a later runtime path.
  CLEAR: lv_raw_ok, lv_raw_msg.
  PERFORM load_runtime_raw
    USING    ps_row-tcode iv_script_id
    CHANGING lt_raw lv_raw_ok lv_raw_msg.
  IF lv_raw_ok <> abap_true OR lt_raw IS INITIAL.
    cv_message = lv_raw_msg.
    RETURN.
  ENDIF.

  LOOP AT lt_raw INTO ls_raw.
    IF ls_raw-is_new_screen = 'X'.
      IF ls_raw-program_name IS INITIAL OR ls_raw-dynpro_no IS INITIAL.
        REFRESH ct_bdc.
        cv_message =
          |EXEC_RAW_FIDELITY_ERROR: step { ls_raw-step_seq } has no PROGRAM/DYNPRO.|.
        RETURN.
      ENDIF.
      CLEAR ls_out.
      ls_out-program  = ls_raw-program_name.
      ls_out-dynpro   = ls_raw-dynpro_no.
      ls_out-dynbegin = 'X'.
      APPEND ls_out TO ct_bdc.
      CONTINUE.
    ENDIF.

    IF ls_raw-field_name IS INITIAL.
      CONTINUE.
    ENDIF.

    IF ls_raw-static_value CS gc_trace_token.
      CONTINUE.
    ENDIF.

    CLEAR ls_out.
    ls_out-fnam = ls_raw-field_name.
    ls_out-fval = ls_raw-static_value.

    CLEAR lv_technical.
    PERFORM mapping_field_is_technical
      USING ls_raw-field_name CHANGING lv_technical.

    IF lv_technical <> abap_true
       AND ls_raw-value_type = 'DYNAMIC'
       AND ls_raw-source_column IS NOT INITIAL.

      CLEAR: lv_scr_bdc, lv_scr_log, lv_scr_src,
             lv_map_count, ls_map_hit.
      PERFORM normalize_mapping_bdc_field
        USING ls_raw-field_name CHANGING lv_scr_bdc.
      PERFORM logical_bdc_key
        USING lv_scr_bdc CHANGING lv_scr_log.
      PERFORM normalize_mapping_source
        USING ls_raw-source_column CHANGING lv_scr_src.

      LOOP AT pt_map INTO ls_map WHERE bdc_field IS NOT INITIAL.
        IF ls_map-staging_field = 'FIELD01'.
          CONTINUE.
        ENDIF.
        CLEAR: lv_map_bdc, lv_map_log, lv_map_src.
        PERFORM normalize_mapping_bdc_field
          USING ls_map-bdc_field CHANGING lv_map_bdc.
        PERFORM logical_bdc_key
          USING lv_map_bdc CHANGING lv_map_log.
        PERFORM normalize_mapping_source
          USING ls_map-source_column CHANGING lv_map_src.
        IF lv_map_log = lv_scr_log AND lv_map_src = lv_scr_src.
          lv_map_count = lv_map_count + 1.
          ls_map_hit = ls_map.
        ENDIF.
      ENDLOOP.

      IF lv_map_count = 0.
        REFRESH ct_bdc.
        cv_message =
          |EXEC_RAW_DYNAMIC_OWNER_MISSING: step { ls_raw-step_seq } field { ls_raw-field_name } source { ls_raw-source_column } has no exact Mapping owner.|.
        RETURN.
      ELSEIF lv_map_count > 1.
        REFRESH ct_bdc.
        cv_message =
          |EXEC_RAW_DYNAMIC_OWNER_CONFLICT: step { ls_raw-step_seq } field { ls_raw-field_name } has { lv_map_count } exact Mapping owners.|.
        RETURN.
      ENDIF.

      IF ls_map_hit-staging_field IS INITIAL.
        REFRESH ct_bdc.
        cv_message = |Mapping { ls_map_hit-source_column } has no staging field.|.
        RETURN.
      ENDIF.

      ASSIGN COMPONENT ls_map_hit-staging_field OF STRUCTURE ps_row TO <lv_stage>.
      IF sy-subrc <> 0 OR <lv_stage> IS NOT ASSIGNED.
        REFRESH ct_bdc.
        cv_message =
          |Staging field { ls_map_hit-staging_field } is unavailable for Mapping { ls_map_hit-source_column }.|.
        RETURN.
      ENDIF.

      lv_value_text = <lv_stage>.
      IF lv_value_text IS INITIAL.
        REFRESH ct_bdc.
        cv_message =
          |EXEC_RAW_DYNAMIC_BLANK_BLOCKED: { ls_map_hit-source_column } is blank. Dynamic business input never falls back to the recorded FVAL.|.
        RETURN.
      ENDIF.
      ls_out-fval = lv_value_text.
    ENDIF.

    APPEND ls_out TO ct_bdc.
  ENDLOOP.

  IF ct_bdc IS INITIAL.
    cv_message = 'EXEC_RAW_EMPTY: Start Recording execution snapshot produced no BDCDATA.'.
    RETURN.
  ENDIF.

  cv_ok = abap_true.
  cv_message =
    |Direct EXEC_RAW replay prepared { lines( ct_bdc ) } row(s); only exact DYNAMIC STEP_SEQ/FNAM/SOURCE ownership may change FVAL. Recorded popup/OKCODE rows are replayed as captured.|.
ENDFORM.

*& Business Key cardinality authority lives in M3_VALID.
*& Execution reuses the same frozen compiler proof; no second heuristic lives here.

*& Single prepared BDCDATA contract for both executors

*& Build one complete business-document BDC stream from the immutable
*& Script Version + exact Mapping + current staging group. This FORM is the
*& only runtime preparation boundary used by CALL TRANSACTION and BISM.

*& APPEND_SCRIPT_STEP still owns generic script->BDCDATA projection. After
*& the complete stream is built, runtime-only technical normalization is
*& applied ONCE, the shared executable-BDC preflight is applied ONCE, and an
*& exact copy is returned to the executor. The global BDCDATA work area is
*& then cleared so neither executor can accidentally rebuild or mutate it.

FORM prepare_group_bdcdata
  USING    pt_group  TYPE ty_t_staging_alv
           pt_s_pre  TYPE ty_t_script
           pt_s_item TYPE ty_t_script
           pt_s_post TYPE ty_t_script
           pt_map    TYPE ty_t_map
           pv_tcode  TYPE sy-tcode
  CHANGING ct_bdc    TYPE ty_t_async_bdcdata
           cv_ok     TYPE abap_bool
           cv_message TYPE string.

  DATA: ls_first       TYPE ty_staging_alv,
        ls_item        TYPE ty_staging_alv,
        ls_scr         TYPE ty_script_def_compat,
        lt_raw         TYPE ty_t_script,
        lt_run_map     TYPE ty_t_map,
        lv_raw_ok      TYPE abap_bool,
        lv_raw_msg     TYPE string,
        lv_repeat      TYPE abap_bool,
        lv_repeat_msg  TYPE string,
        lv_start_seq   TYPE zbdc_sct_ver_bup-step_seq,
        lv_next_seq    TYPE zbdc_sct_ver_bup-step_seq,
        lv_idx         TYPE n LENGTH 2,
        lv_itemno      TYPE i,
        lv_group_rows  TYPE i,
        lv_native_handled TYPE abap_bool,
        lv_native_ok      TYPE abap_bool,
        lv_native_msg     TYPE string,
        lv_group_cons_ok  TYPE abap_bool,
        lv_group_cons_msg TYPE string.

  CLEAR: cv_ok, cv_message, gv_bdc_build_failed, gv_bdc_build_message.
  REFRESH: ct_bdc, bdcdata, lt_raw.

  READ TABLE pt_group INTO ls_first INDEX 1.
  IF sy-subrc <> 0.
    cv_message = 'BDC preparation failed: business document group is empty.'.
    RETURN.
  ENDIF.

 "Execution consumes the exact frozen Mapping. Blank eligibility has already
 "been proven; MANDATORY metadata cannot alter runtime values.
  lt_run_map = pt_map.

  DESCRIBE TABLE pt_group LINES lv_group_rows.

 "for a single-row Guided Start Recording, consume the immutable
 "EXEC_RAW acquisition snapshot directly. RAWQID is audit provenance only;
 "CALL TRANSACTION/BDC_INSERT receive the exact snapshot plus proven dynamic FVALs.
  IF lv_group_rows <= 1.
    CLEAR: lv_native_handled, lv_native_ok, lv_native_msg.
    PERFORM native_single_bdc
      USING    gv_runtime_script_id ls_first lt_run_map
      CHANGING ct_bdc lv_native_handled lv_native_ok lv_native_msg.
    IF lv_native_handled = abap_true.
      IF lv_native_ok <> abap_true.
        cv_message = lv_native_msg.
        REFRESH ct_bdc.
        RETURN.
      ENDIF.
      cv_ok = abap_true.
      cv_message = lv_native_msg.
      RETURN.
    ENDIF.
  ENDIF.

 "Imported recordings and multi-row groups still need the generic Script
 "projection/repeat engine. Preserve their existing behavior.
  PERFORM load_runtime_raw
    USING    pv_tcode gv_runtime_script_id
    CHANGING lt_raw lv_raw_ok lv_raw_msg.
  IF lv_raw_ok <> abap_true.
    cv_message = lv_raw_msg.
    RETURN.
  ENDIF.

  SORT lt_raw BY step_seq.

  IF lv_group_rows <= 1.
    LOOP AT lt_raw INTO ls_scr.
      PERFORM append_exec_exact_step
        USING ls_scr ls_first lt_run_map lt_raw '01'.
      IF gv_bdc_build_failed = abap_true.
        EXIT.
      ENDIF.
    ENDLOOP.
  ELSE.
    "Defense in depth: Staging already validates duplicate Business Keys, but
    "runtime repeats the exact same frozen compiler proof so direct/retry paths
    "can never bypass the cardinality contract.
    CLEAR: lv_group_cons_ok, lv_group_cons_msg.
    PERFORM check_group_cardinality_proof
      USING    pt_group
      CHANGING lv_group_cons_ok lv_group_cons_msg.
    IF lv_group_cons_ok <> abap_true.
      cv_message = lv_group_cons_msg.
      RETURN.
    ENDIF.

    CLEAR: lv_repeat, lv_repeat_msg, lv_start_seq, lv_next_seq.
    PERFORM repeat_bounds
      USING    lt_raw lt_run_map
      CHANGING lv_repeat lv_start_seq lv_next_seq lv_repeat_msg.

    IF lv_repeat <> abap_true OR lv_start_seq IS INITIAL.
      cv_message =
        |GROUP_REPEAT_WINDOW_INVALID: Business Key { ls_first-record_key } is compiler-proven multi-row, but the frozen Mapping/EXEC_RAW stream cannot derive its exact repeat window. Republish the same recording/mapping contract.|.
      RETURN.
    ENDIF.

 "PRE: exact recorded prefix before the first repeatable screen.
    LOOP AT lt_raw INTO ls_scr WHERE step_seq < lv_start_seq.
      PERFORM append_exec_exact_step
        USING ls_scr ls_first lt_run_map lt_raw '01'.
      IF gv_bdc_build_failed = abap_true.
        EXIT.
      ENDIF.
    ENDLOOP.

 "ITEM: repeat only the exact contiguous SHDB screen window proven by
 "Mapping wildcard fields. No screen/OKCODE is invented or reordered.
    IF gv_bdc_build_failed <> abap_true.
      CLEAR lv_itemno.
      LOOP AT pt_group INTO ls_item.
        lv_itemno = lv_itemno + 1.
        lv_idx = lv_itemno.

        IF lv_next_seq IS INITIAL.
          LOOP AT lt_raw INTO ls_scr WHERE step_seq >= lv_start_seq.
            PERFORM append_exec_exact_step
              USING ls_scr ls_item lt_run_map lt_raw lv_idx.
            IF gv_bdc_build_failed = abap_true.
              EXIT.
            ENDIF.
          ENDLOOP.
        ELSE.
          LOOP AT lt_raw INTO ls_scr
            WHERE step_seq >= lv_start_seq
              AND step_seq < lv_next_seq.
            PERFORM append_exec_exact_step
              USING ls_scr ls_item lt_run_map lt_raw lv_idx.
            IF gv_bdc_build_failed = abap_true.
              EXIT.
            ENDIF.
          ENDLOOP.
        ENDIF.

        IF gv_bdc_build_failed = abap_true.
          EXIT.
        ENDIF.
      ENDLOOP.
    ENDIF.

 "POST: exact recorded suffix after the repeat window.
    IF gv_bdc_build_failed <> abap_true AND lv_next_seq IS NOT INITIAL.
      LOOP AT lt_raw INTO ls_scr WHERE step_seq >= lv_next_seq.
        PERFORM append_exec_exact_step
          USING ls_scr ls_first lt_run_map lt_raw '01'.
        IF gv_bdc_build_failed = abap_true.
          EXIT.
        ENDIF.
      ENDLOOP.
    ENDIF.
  ENDIF.

  IF gv_bdc_build_failed = abap_true.
    cv_message = gv_bdc_build_message.
    IF cv_message IS INITIAL.
      cv_message = 'BDC preparation failed while replaying the canonical SHDB recording.'.
    ENDIF.
    REFRESH bdcdata.
    RETURN.
  ENDIF.

  IF bdcdata[] IS INITIAL.
    cv_message = 'BDC preparation failed: canonical SHDB recording generated no BDCDATA.'.
    RETURN.
  ENDIF.

 "ONE physical BDCDATA stream. CALL TRANSACTION USING and BDC_INSERT
 "DYNPROTAB consume this exact table; neither executor rebuilds it.
  ct_bdc[] = bdcdata[].
  REFRESH bdcdata.

  cv_ok = abap_true.
  cv_message =
    |Prepared SAP-generated-semantics BDCDATA: { lines( ct_bdc ) } row(s).|.
ENDFORM.

*& Generic recorded popup branch resolver

*& SHDB can pass a popup without a manual click because the recording contains
*& the popup DYNPRO plus its exact BDC_OKCODE. Runtime must never guess a
*& button. On 00-344 this resolver may build ONE alternate stream only from
*& SAP-native Start Recording evidence already stored for the same TCODE.
*& Accepted branches are control-only, have one recorded BDC_OKCODE, match the
*& exact predecessor PROGRAM/DYNPRO/BDC_OKCODE, and are unique across evidence.

*& CT_BISM_CANONICAL - Explain runtime dynpro mismatch from local evidence

FORM explain_ct_failure
  USING    it_bdc     TYPE ty_t_async_bdcdata
           iv_subrc   TYPE sy-subrc
           it_msg     TYPE ty_t_async_bdcmsg
  CHANGING cv_message TYPE string.

  DATA: ls_msg      TYPE bdcmsgcoll,
        ls_bdc      TYPE bdcdata,
        lv_req_prog TYPE bdcdata-program,
        lv_req_dyn  TYPE bdcdata-dynpro,
        lv_found    TYPE abap_bool,
        lv_prog     TYPE bdcdata-program,
        lv_dyn      TYPE bdcdata-dynpro.

  LOOP AT it_msg INTO ls_msg.
    IF ls_msg-msgid = '00' AND ls_msg-msgnr = '344'.
      lv_req_prog = ls_msg-msgv1.
      lv_req_dyn  = ls_msg-msgv2.
      EXIT.
    ENDIF.
  ENDLOOP.

  IF lv_req_prog IS INITIAL OR lv_req_dyn IS INITIAL.
    RETURN.
  ENDIF.

  LOOP AT it_bdc INTO ls_bdc.
    IF ls_bdc-dynbegin = 'X'.
      lv_prog = ls_bdc-program.
      lv_dyn  = ls_bdc-dynpro.
      IF lv_prog = lv_req_prog AND lv_dyn = lv_req_dyn.
        lv_found = abap_true.
        EXIT.
      ENDIF.
    ENDIF.
  ENDLOOP.

  IF lv_found = abap_true.
    cv_message =
      |ENGINE_FIDELITY_ERROR: SAP requested { lv_req_prog }/{ lv_req_dyn }, which exists in prepared BDCDATA, but batch input still rejected it. SY-SUBRC={ iv_subrc }.|.
  ELSE.
    cv_message =
      |RUNTIME_EXTRA_DYNPRO: SAP requested { lv_req_prog }/{ lv_req_dyn }, but the current Import/Start Recording execution source does not contain that screen. Engine did not drop it. SY-SUBRC={ iv_subrc }.|.
  ENDIF.
ENDFORM.

*& Failed CT persisted-object delta salvage

*& A CALL TRANSACTION can persist the business object and only then hit a
*& conditional follow-up dynpro/output dialog that is not in the frozen SHDB
*& stream. Never auto-answer or hardcode that unexpected screen. Instead,
*& use ONLY the exact BEFORE/AFTER DB delta captured for this execution.
*& If exactly one new persisted object is proved, return it so the caller can
*& mark the group PARTIAL and block unsafe retry. No source-only fallback,
*& newest-row heuristic, TCODE/table/field/message hardcode or guessed object.

FORM next_business_attempt
  USING    pt_group   TYPE ty_t_staging_alv
  CHANGING cv_attempt TYPE i.

  DATA: ls_first TYPE ty_staging_alv,
        lv_max   TYPE zbdc_result_bup-attempt_no.

  cv_attempt = 1.
  READ TABLE pt_group INTO ls_first INDEX 1.
  IF sy-subrc <> 0 OR ls_first-session_id IS INITIAL.
    RETURN.
  ENDIF.

  CLEAR lv_max.
  IF ls_first-record_key IS NOT INITIAL.
    SELECT MAX( attempt_no ) FROM zbdc_result_bup INTO @lv_max
      WHERE session_id = @ls_first-session_id
        AND record_key = @ls_first-record_key.
  ELSE.
    SELECT MAX( attempt_no ) FROM zbdc_result_bup INTO @lv_max
      WHERE session_id = @ls_first-session_id
        AND row_index  = @ls_first-row_index.
  ENDIF.

  IF lv_max IS NOT INITIAL AND lv_max > 0.
    cv_attempt = lv_max + 1.
  ENDIF.
ENDFORM.

*&---------------------------------------------------------------------*
*& Extract one business-object key from an exact certified SAP message
*& contract. This is profile metadata, not TCODE-specific parsing.
*&---------------------------------------------------------------------*
FORM extract_certified_object
  USING    pt_group  TYPE ty_t_staging_alv
           pv_tcode  TYPE sy-tcode
           pt_msg    TYPE ty_t_bdcmsgcoll_nav
  CHANGING cv_object TYPE zbdc_result_bup-sap_object_id.

  DATA: ls_first     TYPE ty_staging_alv,
        ls_session   TYPE zbdc_session_bup,
        ls_cert      TYPE zbdc_cert_bup,
        ls_msg       TYPE bdcmsgcoll,
        lv_candidate TYPE string,
        lv_object    TYPE zbdc_result_bup-sap_object_id,
        lv_navstate  TYPE zbdc_config_bup-config_value,
        lv_navmode   TYPE zbdc_config_bup-config_value,
        lv_cfg_msgid TYPE zbdc_config_bup-config_value,
        lv_cfg_msgnr TYPE zbdc_config_bup-config_value,
        lv_cfg_msgv  TYPE zbdc_config_bup-config_value,
        lv_msgid     TYPE symsgid,
        lv_msgnr     TYPE symsgno,
        lv_msgv      TYPE c LENGTH 1.

  CLEAR cv_object.
  READ TABLE pt_group INTO ls_first INDEX 1.
  IF sy-subrc <> 0 OR ls_first-session_id IS INITIAL.
    RETURN.
  ENDIF.

  SELECT SINGLE *
    FROM zbdc_session_bup
    INTO @ls_session
    WHERE session_id = @ls_first-session_id.
  IF sy-subrc <> 0 OR
     ls_session-tcode <> pv_tcode OR
     ls_session-profile_name IS INITIAL OR
     ls_session-profile_ver IS INITIAL OR
     ls_session-script_id IS INITIAL OR
     ls_session-contract_hash IS INITIAL.
    RETURN.
  ENDIF.

  SELECT SINGLE *
    FROM zbdc_cert_bup
    INTO @ls_cert
    WHERE tcode         = @ls_session-tcode
      AND profile_name  = @ls_session-profile_name
      AND profile_ver   = @ls_session-profile_ver
      AND script_id     = @ls_session-script_id
      AND contract_hash = @ls_session-contract_hash
      AND cert_status   = 'CERTIFIED'
      AND last_test_status = 'CERTIFIED'.
  IF sy-subrc <> 0.
    RETURN.
  ENDIF.

  PERFORM get_script_cfg USING ls_session-script_id 'NAVSTATE' CHANGING lv_navstate.
  PERFORM get_script_cfg USING ls_session-script_id 'NAVMODE'  CHANGING lv_navmode.
  TRANSLATE lv_navmode TO UPPER CASE.
  CONDENSE lv_navmode NO-GAPS.
  "SCREEN_BDC may bind several MSGVs into one composite object. Runtime
  "object projection is therefore deferred to Screen 0400, which owns the
  "complete certified binding contract. Never persist a partial first MSGV.
  IF lv_navmode = 'SCREEN_BDC' OR lv_navmode = 'PARAM_MEMORY'.
    RETURN.
  ENDIF.
  PERFORM get_script_cfg USING ls_session-script_id 'NAVMSGID' CHANGING lv_cfg_msgid.
  PERFORM get_script_cfg USING ls_session-script_id 'NAVMSGNR' CHANGING lv_cfg_msgnr.
  PERFORM get_script_cfg USING ls_session-script_id 'NAVMSGV'  CHANGING lv_cfg_msgv.

  TRANSLATE: lv_navstate TO UPPER CASE, lv_cfg_msgid TO UPPER CASE.
  CONDENSE: lv_navstate NO-GAPS, lv_cfg_msgid NO-GAPS,
            lv_cfg_msgnr NO-GAPS, lv_cfg_msgv NO-GAPS.

  IF lv_navstate <> 'CERTIFIED' OR
     lv_cfg_msgid IS INITIAL OR
     lv_cfg_msgnr IS INITIAL OR
     lv_cfg_msgv IS INITIAL.
    RETURN.
  ENDIF.

  lv_msgid = lv_cfg_msgid.
  lv_msgnr = lv_cfg_msgnr.
  lv_msgv  = lv_cfg_msgv.

  LOOP AT pt_msg INTO ls_msg
    WHERE msgtyp = 'S'
      AND msgid  = lv_msgid
      AND msgnr  = lv_msgnr.

    CLEAR lv_candidate.
    CASE lv_msgv.
      WHEN '1'.
        lv_candidate = ls_msg-msgv1.
      WHEN '2'.
        lv_candidate = ls_msg-msgv2.
      WHEN '3'.
        lv_candidate = ls_msg-msgv3.
      WHEN '4'.
        lv_candidate = ls_msg-msgv4.
      WHEN OTHERS.
        RETURN.
    ENDCASE.

    CONDENSE lv_candidate.
    IF lv_candidate IS INITIAL.
      CONTINUE.
    ENDIF.

    lv_object = lv_candidate.
    IF cv_object IS INITIAL.
      cv_object = lv_object.
    ELSEIF cv_object <> lv_object.
      CLEAR cv_object.
      RETURN.
    ENDIF.
  ENDLOOP.
ENDFORM.

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

  DATA: ls_first        TYPE ty_staging_alv,
        lt_exec_bdc     TYPE ty_t_async_bdcdata,
        lv_group_ok     TYPE abap_bool,
        lv_group_msg    TYPE string,
        lv_bdc_ok       TYPE abap_bool,
        lv_bdc_msg      TYPE string,
        lv_insert_subrc TYPE i,
        lv_insert_try   TYPE i,
        lv_insert_msg   TYPE string,
        lv_ct_subrc     TYPE sy-subrc,
        lv_ct_mode      TYPE c LENGTH 1,
        lv_ct_upd       TYPE c LENGTH 1,
        lv_has_error    TYPE abap_bool,
        lv_has_warning  TYPE abap_bool,
        lv_has_success  TYPE abap_bool,
        lv_business_attempt TYPE i,
        lv_last_text    TYPE string,
        lv_success_text TYPE string,
        lv_msg          TYPE string,
        lv_sap_object   TYPE zbdc_result_bup-sap_object_id,
        ls_ctu          TYPE ctu_params,
        lv_ct_racommit  TYPE c LENGTH 1,
        lv_ct_nobinpt   TYPE c LENGTH 1,
        lv_ct_auto      TYPE abap_bool,
        lv_ct_rac_src   TYPE string,
        lv_ct_nob_src   TYPE string,
        ls_msg          TYPE bdcmsgcoll,
        ls_terminal     TYPE bdcmsgcoll.

 "BASELINE
 "This executor deliberately knows NOTHING about SAP Object identity.
 "No TABLE/FIELD discovery, DDIC owner ranking, AI object prompt, watermark,
 "CDHDR delta, primary-key delta, verifier metadata or object token
 "is executed here. CT and BISM consume the same generic prepared BDCDATA.

  READ TABLE pt_group INTO ls_first INDEX 1.
  IF sy-subrc <> 0.
    RETURN.
  ENDIF.

  CLEAR: lv_group_ok, lv_group_msg.
  PERFORM group_scope_gate
    USING    pt_group pv_tcode
    CHANGING lv_group_ok lv_group_msg.
  IF lv_group_ok <> abap_true.
    cv_err = cv_err + 1.
    PERFORM save_synthetic_engine_log USING pt_group pv_tcode 0 gc_st_error lv_group_msg '' ''.
    PERFORM update_group_result       USING pt_group gc_st_error lv_group_msg ''.
    PERFORM update_exec_counters USING pt_group.
    RETURN.
  ENDIF.

  CLEAR: lv_bdc_ok, lv_bdc_msg.
  REFRESH lt_exec_bdc.
  PERFORM prepare_group_bdcdata
    USING    pt_group pt_s_pre pt_s_item pt_s_post pt_map pv_tcode
    CHANGING lt_exec_bdc lv_bdc_ok lv_bdc_msg.
  IF lv_bdc_ok <> abap_true.
    cv_err = cv_err + 1.
    IF lv_bdc_msg IS INITIAL.
      lv_bdc_msg = 'Executable BDCDATA preparation failed.'.
    ENDIF.
    PERFORM save_synthetic_engine_log USING pt_group pv_tcode 0 gc_st_error lv_bdc_msg '' ''.
    PERFORM update_group_result       USING pt_group gc_st_error lv_bdc_msg ''.
    PERFORM update_exec_counters USING pt_group.
    RETURN.
  ENDIF.

 "BISM/SM35: queue the exact same prepared BDCDATA. No business-object proof
 "is attempted before or after BDC_INSERT in the reset baseline.
  IF p_bdc_mode = gc_mode_batch.
    CLEAR: lv_insert_subrc, lv_insert_try, lv_insert_msg, lv_business_attempt.
    PERFORM next_business_attempt USING pt_group CHANGING lv_business_attempt.
    PERFORM insert_batch_group
      USING    pv_tcode lt_exec_bdc
      CHANGING lv_insert_subrc lv_insert_try lv_insert_msg.

    IF lv_insert_subrc = 0.
      cv_ok = cv_ok + 1.
      APPEND LINES OF lt_exec_bdc TO gt_z488_sm35_expected.
      DATA(lv_zm915_4283_1) = |{ pv_bigrp }|.
      MESSAGE ID 'ZBDC' TYPE 'S' NUMBER '915'
        WITH lv_zm915_4283_1 INTO lv_msg.
      PERFORM save_synthetic_engine_log USING pt_group pv_tcode lv_business_attempt gc_st_sm35q lv_msg '' ''.
      PERFORM update_group_result       USING pt_group gc_st_sm35q lv_msg ''.
      g_exec_curr = g_exec_curr + lines( pt_group ).
      COMMIT WORK AND WAIT.
    ELSE.
      cv_err = cv_err + 1.
      DATA(lv_zm916_4290_1) = |{ lv_insert_try }|.
      DATA(lv_zm916_4290_2) = |{ lv_insert_msg }|.
      DATA(lv_zm916_4290_3) = |{ lv_insert_subrc }|.
      MESSAGE ID 'ZBDC' TYPE 'S' NUMBER '916'
        WITH lv_zm916_4290_1 lv_zm916_4290_2 lv_zm916_4290_3
        INTO lv_msg.
      PERFORM save_synthetic_engine_log USING pt_group pv_tcode lv_business_attempt gc_st_error lv_msg '' 'X'.
      PERFORM update_group_result       USING pt_group gc_st_error lv_msg ''.
      PERFORM update_exec_counters USING pt_group.
    ENDIF.
    RETURN.
  ENDIF.

 "CALL TRANSACTION: exact prepared BDCDATA, frozen user CTU policy.
  IF gv_z597_ctu_frozen = abap_true.
    lv_ct_mode = gv_z597_ct_mode.
    lv_ct_upd  = gv_z597_ct_upd.
  ELSE.
    lv_ct_mode = pv_mode.
    lv_ct_upd  = pv_upd.
  ENDIF.

  IF ( lv_ct_mode <> 'N' AND lv_ct_mode <> 'E' AND lv_ct_mode <> 'A' ) OR
     ( lv_ct_upd  <> 'S' AND lv_ct_upd  <> 'A' ).
    cv_err = cv_err + 1.
    DATA(lv_zm917_4310_1) = |{ lv_ct_mode }|.
    DATA(lv_zm917_4310_2) = |{ lv_ct_upd }|.
    MESSAGE ID 'ZBDC' TYPE 'S' NUMBER '917'
      WITH lv_zm917_4310_1 lv_zm917_4310_2 INTO lv_msg.
    PERFORM save_synthetic_engine_log USING pt_group pv_tcode 0 gc_st_error lv_msg '' ''.
    PERFORM update_group_result       USING pt_group gc_st_error lv_msg ''.
    PERFORM update_exec_counters USING pt_group.
    RETURN.
  ENDIF.

  CLEAR: ls_ctu, lv_ct_racommit, lv_ct_nobinpt, lv_ct_auto,
         lv_ct_rac_src, lv_ct_nob_src.
  ls_ctu-dismode = lv_ct_mode.
  ls_ctu-updmode = lv_ct_upd.
  CLEAR ls_ctu-cattmode.
  ls_ctu-defsize = 'X'.

  PERFORM resolve_ct_racommit
    USING gv_runtime_script_id gs_runtime_cert-cert_status
    CHANGING lv_ct_racommit lv_ct_rac_src.
  PERFORM resolve_ct_nobinpt
    USING gv_runtime_script_id gs_runtime_cert-cert_status
    CHANGING lv_ct_nobinpt lv_ct_auto lv_ct_nob_src.

  IF lv_ct_mode = 'N' OR lv_ct_mode = 'E'.
    CLEAR lv_ct_nobinpt.
    lv_ct_nob_src = 'DISPLAY_MODE_BATCH_SAFE'.
  ENDIF.
  ls_ctu-racommit = lv_ct_racommit.
  ls_ctu-nobinpt  = lv_ct_nobinpt.
  CLEAR ls_ctu-nobiend.

  CLEAR lv_business_attempt.
  PERFORM next_business_attempt USING pt_group CHANGING lv_business_attempt.

  gv_z579_ct_started = abap_true.
  REFRESH messtab.
  CLEAR: lv_ct_subrc, lv_has_error, lv_has_warning,
         lv_has_success, lv_last_text, lv_success_text,
         lv_msg, ls_terminal.

  CALL TRANSACTION pv_tcode USING lt_exec_bdc
    OPTIONS FROM ls_ctu
    MESSAGES INTO messtab.
  lv_ct_subrc = sy-subrc.

 "Preserve terminal SY-MSG when SAP did not add it to BDCMSGCOLL.
  IF sy-msgid IS NOT INITIAL AND sy-msgno IS NOT INITIAL.
    ls_terminal-msgtyp  = sy-msgty.
    ls_terminal-msgspra = sy-langu.
    ls_terminal-msgid   = sy-msgid.
    ls_terminal-msgnr   = sy-msgno.
    ls_terminal-msgv1   = sy-msgv1.
    ls_terminal-msgv2   = sy-msgv2.
    ls_terminal-msgv3   = sy-msgv3.
    ls_terminal-msgv4   = sy-msgv4.
    READ TABLE messtab TRANSPORTING NO FIELDS
      WITH KEY msgtyp = ls_terminal-msgtyp
               msgid  = ls_terminal-msgid
               msgnr  = ls_terminal-msgnr
               msgv1  = ls_terminal-msgv1
               msgv2  = ls_terminal-msgv2
               msgv3  = ls_terminal-msgv3
               msgv4  = ls_terminal-msgv4.
    IF sy-subrc <> 0.
      APPEND ls_terminal TO messtab.
    ENDIF.
  ENDIF.

  PERFORM save_bdc_message_logs USING pt_group pv_tcode lv_business_attempt ''.

  LOOP AT messtab INTO ls_msg.
    CLEAR lv_last_text.
    PERFORM msg_text USING ls_msg CHANGING lv_last_text.
    IF lv_last_text IS INITIAL.
      lv_last_text = |{ ls_msg-msgid }/{ ls_msg-msgnr }|.
    ENDIF.
    CASE ls_msg-msgtyp.
      WHEN 'E' OR 'A' OR 'X'.
        lv_has_error = abap_true.
        IF lv_msg IS INITIAL.
          lv_msg = lv_last_text.
        ENDIF.
      WHEN 'W'.
        lv_has_warning = abap_true.
      WHEN 'S'.
 "Keep nonterminal S text as evidence only. It does NOT prove completion by
 "itself; terminal SY-MSG or a certified success-object message must do that.
        IF lv_last_text IS NOT INITIAL.
          lv_success_text = lv_last_text.
        ENDIF.
    ENDCASE.
  ENDLOOP.

 "when available, the status message left in SY-MSG* immediately
 "after CALL TRANSACTION is the closest direct equivalent of the SAP GUI
 "post-SAVE status bar. Prefer that exact formatted S-message.
  IF ls_terminal-msgtyp = 'S' AND
     ls_terminal-msgid IS NOT INITIAL AND
     ls_terminal-msgnr IS NOT INITIAL.
    CLEAR lv_last_text.
    PERFORM msg_text USING ls_terminal CHANGING lv_last_text.
    IF lv_last_text IS NOT INITIAL.
      lv_has_success = abap_true.
      lv_success_text = lv_last_text.
    ENDIF.
  ENDIF.

  IF lv_has_error = abap_true OR lv_ct_subrc <> 0.
    cv_err = cv_err + 1.
    IF lv_msg IS INITIAL.
      DATA(lv_zm918_4418_1) = |{ lv_ct_subrc }|.
      MESSAGE ID 'ZBDC' TYPE 'S' NUMBER '918'
        WITH lv_zm918_4418_1 INTO lv_msg.
    ELSE.
      DATA(lv_zm919_4420_1) = |{ lv_ct_subrc }|.
      DATA(lv_zm919_4420_2) = |{ lv_msg }|.
      MESSAGE ID 'ZBDC' TYPE 'S' NUMBER '919'
        WITH lv_zm919_4420_1 lv_zm919_4420_2 INTO lv_msg.
    ENDIF.
    PERFORM explain_ct_failure USING lt_exec_bdc lv_ct_subrc messtab[] CHANGING lv_msg.
    PERFORM save_synthetic_engine_log USING pt_group pv_tcode lv_business_attempt gc_st_error lv_msg '' ''.
    PERFORM update_group_result       USING pt_group gc_st_error lv_msg ''.
    COMMIT WORK AND WAIT.
    PERFORM update_exec_counters USING pt_group.
    RETURN.
  ENDIF.

 "A certified navigation/object success message is also terminal evidence.
 "This is frozen profile metadata, not a TCODE-specific guess.
  CLEAR lv_sap_object.
  PERFORM extract_certified_object
    USING    pt_group pv_tcode messtab[]
    CHANGING lv_sap_object.
  IF lv_sap_object IS NOT INITIAL.
    lv_has_success = abap_true.
  ENDIF.

  "A/E/N controls only display. Outcome is evidence-based for every mode.
  IF lv_has_success = abap_true.
    cv_ok = cv_ok + 1.
    IF lv_success_text IS NOT INITIAL.
      lv_msg = lv_success_text.
    ELSE.
      MESSAGE ID 'ZBDC' TYPE 'S' NUMBER '920' INTO lv_msg.
    ENDIF.
    PERFORM save_synthetic_engine_log USING pt_group pv_tcode lv_business_attempt gc_st_success lv_msg '' ''.
    PERFORM update_group_result       USING pt_group gc_st_success lv_msg lv_sap_object.
    COMMIT WORK AND WAIT.
    PERFORM update_exec_counters USING pt_group.
    RETURN.
  ENDIF.

  cv_ok = cv_ok + 1.
  IF lv_has_warning = abap_true.
    DATA(lv_zm921_4457_1) = |{ lv_ct_mode }|.
    MESSAGE ID 'ZBDC' TYPE 'S' NUMBER '921'
      WITH lv_zm921_4457_1 INTO lv_msg.
  ELSE.
    DATA(lv_zm922_4459_1) = |{ lv_ct_mode }|.
    MESSAGE ID 'ZBDC' TYPE 'S' NUMBER '922'
      WITH lv_zm922_4459_1 INTO lv_msg.
  ENDIF.
  PERFORM save_synthetic_engine_log USING pt_group pv_tcode lv_business_attempt gc_st_partial lv_msg '' ''.
  PERFORM update_group_result       USING pt_group gc_st_partial lv_msg ''.
  COMMIT WORK AND WAIT.
  "PARTIAL is processed, but it is neither SUCCESS nor ERROR.
  g_exec_curr = g_exec_curr + lines( pt_group ).
ENDFORM.

*& structural execution scope integrity

FORM group_scope_gate
  USING    pt_group TYPE ty_t_staging_alv
           pv_tcode TYPE sy-tcode
  CHANGING cv_ok    TYPE abap_bool
           cv_msg   TYPE string.

  DATA: ls_first TYPE ty_staging_alv,
        ls_row   TYPE ty_staging_alv,
        lv_key   TYPE string,
        lv_first_key TYPE string,
        lt_rows TYPE SORTED TABLE OF zbdc_staging_bup-row_index
                WITH UNIQUE KEY table_line.

  CLEAR: cv_ok, cv_msg.
  READ TABLE pt_group INTO ls_first INDEX 1.
  IF sy-subrc <> 0.
    cv_msg = 'Execution group is empty.'.
    RETURN.
  ENDIF.

  lv_first_key = ls_first-record_key.
  IF lv_first_key IS INITIAL.
    lv_first_key = ls_first-row_index.
  ENDIF.

  LOOP AT pt_group INTO ls_row.
    IF ls_row-session_id <> ls_first-session_id.
      cv_msg = 'Execution group mixes more than one application session.'.
      RETURN.
    ENDIF.
    IF ls_row-tcode <> pv_tcode OR ls_row-tcode <> ls_first-tcode.
      cv_msg = 'Execution group mixes more than one transaction contract.'.
      RETURN.
    ENDIF.

    lv_key = ls_row-record_key.
    IF lv_key IS INITIAL.
      lv_key = ls_row-row_index.
    ENDIF.
    IF lv_key <> lv_first_key.
      cv_msg = 'Execution group contains rows from different business keys.'.
      RETURN.
    ENDIF.

    INSERT ls_row-row_index INTO TABLE lt_rows.
    IF sy-subrc <> 0.
      cv_msg = |Execution group contains duplicate staging row { ls_row-row_index }.|.
      RETURN.
    ENDIF.
  ENDLOOP.

  cv_ok = abap_true.
ENDFORM.

*& Retryable-error classifier


FORM text_transient
  USING    pv_text   TYPE csequence
  CHANGING cv_retry  TYPE abap_bool
           cv_reason TYPE string.

  DATA lv_text TYPE string.

  CLEAR: cv_retry, cv_reason.
  lv_text = pv_text.
  TRANSLATE lv_text TO LOWER CASE.
 "BLOCKED contains the substring LOCK. Remove the word BLOCKED
 "before transient-lock classification so an engine safety gate is never
 "misreported as an SAP enqueue/lock condition.
  REPLACE ALL OCCURRENCES OF 'blocked' IN lv_text WITH ' '.
  CONDENSE lv_text.

  IF lv_text CS 'lock' OR lv_text CS 'locked' OR
     lv_text CS 'enqueue' OR lv_text CS 'gesperrt' OR
     lv_text CS 'currently processed' OR
     lv_text CS 'dang xu ly' OR lv_text CS 'Ã„â€˜ang xÃ¡Â»Â­ lÃƒÂ½' OR
     lv_text CS 'khoa' OR lv_text CS 'khÃƒÂ³a'.
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

*& protocol / pre-BDC gate helpers

FORM msg_text
  USING    is_msg  TYPE bdcmsgcoll
  CHANGING cv_text TYPE string.

  DATA lv_text TYPE c LENGTH 255.

  CLEAR cv_text.
  CALL FUNCTION 'MESSAGE_TEXT_BUILD'
    EXPORTING
      msgid               = is_msg-msgid
      msgnr               = is_msg-msgnr
      msgv1               = is_msg-msgv1
      msgv2               = is_msg-msgv2
      msgv3               = is_msg-msgv3
      msgv4               = is_msg-msgv4
    IMPORTING
      message_text_output = lv_text
    EXCEPTIONS
      OTHERS              = 1.

  IF sy-subrc = 0.
    cv_text = lv_text.
  ELSE.
    cv_text = |{ is_msg-msgid }-{ is_msg-msgnr } { is_msg-msgv1 } { is_msg-msgv2 } { is_msg-msgv3 } { is_msg-msgv4 }|.
  ENDIF.
ENDFORM.

*& interactive CT warning/information audit helper

*& MODE A/E may expose SAP dialog to the user. This helper records W/I
*& before terminal success as diagnostic evidence only. Final CT SUCCESS is
*& decided by exact terminal protocol ordering; DB proof may strengthen it.
*& A real pre-terminal E/A/X remains blocking inside z413_terminal_success.
*& No TCODE, business table, field or message number is hardcoded.

*& Explicit LIVE certification confirmation

*& SAP CALL TRANSACTION has no generic rollback/test mode once the called
*& transaction commits. PENDING_TEST is retained only as a legacy persistence
*& status; the first CT certification replay is a LIVE posting attempt.
*& Structural preflight remains side-effect free because it never calls SAP.

*& Explicit onboarding certification boundary for Screen 0500

FORM count_term_scope
  USING    pt_scope TYPE ty_t_staging_alv
  CHANGING cv_done  TYPE i
           cv_total TYPE i.

  DATA: lt_all    TYPE SORTED TABLE OF string WITH UNIQUE KEY table_line,
        lt_done   TYPE SORTED TABLE OF string WITH UNIQUE KEY table_line,
        ls_row    TYPE ty_staging_alv,
        lv_key    TYPE string,
        lv_status TYPE string.

  CLEAR: cv_done, cv_total.

  LOOP AT pt_scope INTO ls_row.
    lv_key = ls_row-record_key.
    IF lv_key IS INITIAL.
      lv_key = ls_row-row_index.
    ENDIF.
    IF lv_key IS INITIAL.
      CONTINUE.
    ENDIF.

    INSERT lv_key INTO TABLE lt_all.

    lv_status = ls_row-status.
    TRANSLATE lv_status TO UPPER CASE.
    IF lv_status = gc_st_success OR
       lv_status = gc_st_error OR
       lv_status = gc_st_warning OR
       lv_status = gc_st_partial OR
       lv_status = gc_st_processed OR
       lv_status = gc_st_sm35q OR
       lv_status = 'SUCCESS' OR
       lv_status = 'ERROR' OR
       lv_status = 'SM35QUEUE'.
      INSERT lv_key INTO TABLE lt_done.
    ENDIF.
  ENDLOOP.

  cv_total = lines( lt_all ).
  cv_done  = lines( lt_done ).
ENDFORM.

FORM UPDATE_EXEC_COUNTERS USING PT_GROUP TYPE TY_T_STAGING_ALV.
  G_EXEC_CURR = G_EXEC_CURR + LINES( PT_GROUP ).
ENDFORM.

*& UPDATE_GROUP_RESULT - update staging internal + DB + result log
*& Professional flow: internal table first, DB staging in one MODIFY TABLE,
*& then exactly 1 result header log per document group.

*& STOP_BDC_EXECUTION - Phase 8: graceful stop after current group

FORM STOP_BDC_EXECUTION.
  G_STOP_FLAG = 'X'.
  MESSAGE s515(zbdc).
ENDFORM.

*& SHDB import is owned by M2 and persists ZBDC_SCRIPT_BUP/ZBDC_SCT_VER_BUP
*& Defensive parser: preserve BDC_CURSOR/BDC_SUBSCR for true SM35
*& batch-input compatibility; confirm before overwrite.
*& Sau upload van can review ROW_TYPE/VALUE_TYPE/SOURCE_COLUMN cho item.

FORM init_execution_monitor.
  DATA lv_den        TYPE i.
  DATA lv_pct_i      TYPE p LENGTH 7 DECIMALS 2.
  DATA lv_scope_done TYPE i.
  DATA lv_scope_total TYPE i.

 "No hidden stop-on-error default. Manual STOP remains explicit.
  chkp_stop_on_error = space.

  IF gt_staging IS INITIAL.
    CLEAR: txtgv_exec_session, txtgv_exec_curr, txtgv_exec_total,
           txtgv_exec_pct, txtgv_exec_elapsed, txtgv_exec_eta.
    RETURN.
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

 "if PBO returns after foreground CALL TRANSACTION, rebuild the
 "header from terminal group statuses as well. This prevents the visible
 "header from staying at 0/15 while the ALV/result rows already show 15/15.
  PERFORM count_term_scope
    USING    gt_exec_scope_0500
    CHANGING lv_scope_done lv_scope_total.
  IF lv_scope_total > 0.
    lv_den = lv_scope_total.
    IF lv_scope_done > g_exec_curr.
      g_exec_curr = lv_scope_done.
    ENDIF.
    IF lv_scope_done > gv_exec_run_done.
      gv_exec_run_done = lv_scope_done.
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

*& Scope builders for 0500
*& Run All / Run Selected decide WHAT to run; 0100 decides HOW to run.

FORM collect_ready_groups_all
  CHANGING ct_process TYPE ty_t_staging_alv.

  DATA ls_exec TYPE ty_exec_disp.
  DATA ls_alv  TYPE ty_staging_alv.

  REFRESH ct_process.

 "execute the exact cockpit snapshot the user reviewed.
 "Do not rebuild it from another transient buffer immediately before scope capture.
  IF gt_exec_disp IS INITIAL.
    IF gt_staging_alv IS INITIAL AND gt_staging IS NOT INITIAL.
      PERFORM prepare_alv_0400.
    ENDIF.
    PERFORM build_exec_cockpit.
  ENDIF.

  LOOP AT gt_exec_disp INTO ls_exec WHERE run_status = gc_st_ready.
    PERFORM append_exec_group USING ls_exec CHANGING ct_process.
  ENDLOOP.

 "Fallback for old/runtime cases where the cockpit is not built yet.
  IF ct_process IS INITIAL.
    LOOP AT gt_staging_alv INTO ls_alv WHERE status = gc_st_ready.
      APPEND ls_alv TO ct_process.
    ENDLOOP.
  ENDIF.
ENDFORM.

FORM collect_ready_groups_selected
  CHANGING ct_process TYPE ty_t_staging_alv.

  DATA: lt_rows TYPE lvc_t_row,
        ls_row  TYPE lvc_s_row,
        ls_exec TYPE ty_exec_disp.

  REFRESH ct_process.

  IF gt_exec_disp IS INITIAL.
    IF gt_staging_alv IS INITIAL AND gt_staging IS NOT INITIAL.
      PERFORM prepare_alv_0400.
    ENDIF.
    PERFORM build_exec_cockpit.
  ENDIF.

 "Run Selected is read from the native left row selectors only.
 "The legacy SELECTED checkbox field is hidden and ignored so execution
 "intent is never carried by a tiny cell or stale edited value.
  CALL METHOD cl_gui_cfw=>flush
    EXCEPTIONS
      OTHERS = 1.

  IF go_exec_grid IS BOUND.
    CALL METHOD go_exec_grid->get_selected_rows
      IMPORTING et_index_rows = lt_rows.
  ENDIF.

  IF lt_rows IS INITIAL.
    RETURN.
  ENDIF.

  SORT lt_rows BY index.
  DELETE ADJACENT DUPLICATES FROM lt_rows COMPARING index.

  LOOP AT lt_rows INTO ls_row.
    READ TABLE gt_exec_disp INTO ls_exec INDEX ls_row-index.
    IF sy-subrc <> 0 OR ls_exec-run_status <> gc_st_ready.
      CONTINUE.
    ENDIF.
    PERFORM append_exec_group USING ls_exec CHANGING ct_process.
  ENDLOOP.
ENDFORM.

*& Execution Monitor follows exact 0400 user selection

FORM append_monitor_group
  USING    is_exec  TYPE ty_exec_disp
  CHANGING ct_scope TYPE ty_t_staging_alv.

  DATA: ls_alv    TYPE ty_staging_alv,
        ls_db     TYPE zbdc_staging_bup,
        lt_db     TYPE STANDARD TABLE OF zbdc_staging_bup,
        lv_key    TYPE string,
        lv_before TYPE i.

  lv_before = lines( ct_scope ).

  LOOP AT gt_staging_alv INTO ls_alv
       WHERE session_id = is_exec-session_id.
    IF is_exec-tcode IS NOT INITIAL AND
       ls_alv-tcode IS NOT INITIAL AND
       ls_alv-tcode <> is_exec-tcode.
      CONTINUE.
    ENDIF.

    lv_key = ls_alv-record_key.
    IF lv_key IS INITIAL.
      lv_key = ls_alv-row_index.
    ENDIF.
    IF lv_key <> is_exec-group_key.
      CONTINUE.
    ENDIF.

    APPEND ls_alv TO ct_scope.
  ENDLOOP.

  IF lines( ct_scope ) > lv_before.
    RETURN.
  ENDIF.

  SELECT * FROM zbdc_staging_bup INTO TABLE @lt_db
    WHERE session_id = @is_exec-session_id.

  LOOP AT lt_db INTO ls_db.
    IF is_exec-tcode IS NOT INITIAL AND
       ls_db-tcode IS NOT INITIAL AND
       ls_db-tcode <> is_exec-tcode.
      CONTINUE.
    ENDIF.

    lv_key = ls_db-record_key.
    IF lv_key IS INITIAL.
      lv_key = ls_db-row_index.
    ENDIF.
    IF lv_key <> is_exec-group_key.
      CONTINUE.
    ENDIF.

    CLEAR ls_alv.
    MOVE-CORRESPONDING ls_db TO ls_alv.
    APPEND ls_alv TO ct_scope.
  ENDLOOP.
ENDFORM.

FORM prepare_monitor_scope
  CHANGING cv_count TYPE i
           cv_ok    TYPE abap_bool.

  DATA: lt_rows       TYPE lvc_t_row,
        ls_row        TYPE lvc_s_row,
        ls_exec       TYPE ty_exec_disp,
        lt_scope      TYPE ty_t_staging_alv,
        lt_group_keys TYPE SORTED TABLE OF string WITH UNIQUE KEY table_line,
        lv_group_id   TYPE string,
        lv_before     TYPE i.

  CLEAR: cv_count, cv_ok.

  IF gt_exec_disp IS INITIAL.
    IF gt_staging_alv IS INITIAL AND gt_staging IS NOT INITIAL.
      PERFORM prepare_alv_0400.
    ENDIF.
    PERFORM build_exec_cockpit.
  ENDIF.

  CALL METHOD cl_gui_cfw=>flush
    EXCEPTIONS
      OTHERS = 1.

  IF go_exec_grid IS BOUND.
    CALL METHOD go_exec_grid->get_selected_rows
      IMPORTING et_index_rows = lt_rows.
  ENDIF.

  IF lt_rows IS INITIAL.
    RETURN.
  ENDIF.

  SORT lt_rows BY index.
  DELETE ADJACENT DUPLICATES FROM lt_rows COMPARING index.

  LOOP AT lt_rows INTO ls_row.
    IF ls_row-index <= 0.
      CONTINUE.
    ENDIF.

    READ TABLE gt_exec_disp INTO ls_exec INDEX ls_row-index.
    IF sy-subrc <> 0.
      CONTINUE.
    ENDIF.

    lv_before = lines( lt_scope ).
    PERFORM append_monitor_group
      USING ls_exec CHANGING lt_scope.
    IF lines( lt_scope ) <= lv_before.
      CONTINUE.
    ENDIF.

    lv_group_id = |{ ls_exec-session_id }#{ ls_exec-tcode }#{ ls_exec-group_key }|.
    INSERT lv_group_id INTO TABLE lt_group_keys.
  ENDLOOP.

  IF lt_scope IS INITIAL OR lt_group_keys IS INITIAL.
    RETURN.
  ENDIF.

 "A monitor-only entry must never inherit a previous ALL/SELECTED execution
 "queue. Freeze exactly the rows the user highlighted on 0400 and let 0500
 "rebuild their current statuses from DB/result proof. No status is changed.
  CLEAR: gt_exec_scope_0500, gt_exec_qstate,
         gv_exec_run_total, gv_exec_run_done, gv_exec_run_start_rt,
         gv_exec_run_active, gv_exec_run_engine, gv_exec_run_queued,
         gv_exec_elapsed, gv_exec_stop_req, gv_exec_mon_kind,
         gv_sm35_mon_group.
  CLEAR g_stop_flag.

  gt_exec_scope_0500  = lt_scope.
  gv_exec_scope_ready = abap_true.
  gv_exec_scope_0500  = 'MONITOR'.
  gv_exec_scope_text  = 'SELECTED group(s) from 0400'.
  gv_exec_run_phase   = 'Review selected execution scope'.

  cv_count = lines( lt_group_keys ).
  txtgv_exec_total   = cv_count.
  txtgv_exec_curr    = '0'.
  txtgv_exec_pct     = '0.00'.
  txtgv_exec_elapsed = '0'.
  txtgv_exec_eta     = 'n/a'.
  g_exec_curr        = 0.

  READ TABLE lt_scope INTO DATA(ls_first_scope) INDEX 1.
  IF sy-subrc = 0.
    txtgv_exec_session = ls_first_scope-session_id.
  ENDIF.

  cv_ok = abap_true.
ENDFORM.

*& Strict 0400 row-selection counter

*& Native 0400 multi-row selection helpers

FORM count_0500_q
  CHANGING cv_done  TYPE i
           cv_total TYPE i.

  CLEAR: cv_done, cv_total.
  cv_total = lines( gt_exec_disp ).

  LOOP AT gt_exec_disp ASSIGNING FIELD-SYMBOL(<ls_q_count>).
    CASE <ls_q_count>-run_status.
 "Progress means processing outcome for the end user, not only
 "business-created documents. SUCCESS/ERROR/WARNING are terminal
 "review states. SM35QUEUE remains pending until the user processes the
 "session in SM35 and refreshes this cockpit.
      WHEN gc_st_success OR gc_st_error OR gc_st_warning OR gc_st_processed
        OR gc_st_skipped OR gc_st_partial OR 'BLOCKED_ONBOARDING'.
        cv_done = cv_done + 1.
    ENDCASE.
  ENDLOOP.
ENDFORM.

*& Terminal outcome counters for 0500 final messages

FORM count_0500_outcome
  CHANGING cv_success TYPE i
           cv_error   TYPE i
           cv_warning TYPE i
           cv_total   TYPE i.

  CLEAR: cv_success, cv_error, cv_warning, cv_total.

  LOOP AT gt_exec_disp ASSIGNING FIELD-SYMBOL(<ls_q121>).
    cv_total = cv_total + 1.
    CASE <ls_q121>-run_status.
      WHEN gc_st_success OR gc_st_processed.
        cv_success = cv_success + 1.
      WHEN gc_st_error.
        cv_error = cv_error + 1.
      WHEN gc_st_warning OR gc_st_partial OR 'BLOCKED_ONBOARDING'.
        cv_warning = cv_warning + 1.
    ENDCASE.
  ENDLOOP.
ENDFORM.

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
         gv_exec_run_queued, gv_exec_elapsed.
  gv_exec_scope_ready = abap_false.
  gv_exec_stop_req    = abap_false.
  g_exec_curr         = 0.
  CLEAR g_stop_flag.
  gv_exec_scope_0500  = iv_scope.

 "scope builders own their source preparation. An unconditional
 "PREPARE_ALV here could erase a valid visible cockpit when GT_STAGING and
 "GT_STAGING_ALV were not synchronized during the preceding PBO.
  IF gt_exec_disp IS INITIAL AND gt_staging IS INITIAL.
    RETURN.
  ENDIF.

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
  PERFORM seed_0500_qstate
    USING gt_exec_scope_0500 gc_st_ready
          'Ready in exact selected execution scope'.
 "The execution scope is now copied by business key. Clear the visual
 "selection so returning from 0500 starts from a predictable empty state.
  PERFORM reset_0400_selection.
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

*& Re-open only stale setup/preflight gates for exact 0500 scope

FORM is_resettable_gate
  USING    ps_row   TYPE ty_staging_alv
  CHANGING cv_reset TYPE abap_bool.

  DATA lv_msg TYPE string.

  CLEAR cv_reset.

  IF ps_row-status <> gc_st_error.
    RETURN.
  ENDIF.

  CONCATENATE ps_row-error_msg ps_row-last_error
    INTO lv_msg SEPARATED BY space.
  TRANSLATE lv_msg TO UPPER CASE.
  CONDENSE lv_msg.

  IF lv_msg CS 'SM35 SESSION NOT CREATED' OR
     lv_msg CS 'NO SELECTED READY GROUP CHANGED STATE' OR
     lv_msg CS 'QUEUE SETUP/PREFLIGHT' OR
     lv_msg CS 'PROFILE SETUP INCOMPLETE' OR
     lv_msg CS 'PROFILE IS PREPARED FOR INITIAL CERTIFICATION' OR
     lv_msg CS 'RUN ONE SELECTED GROUP IN CALL TRANSACTION MODE FIRST' OR
     lv_msg CS 'PENDING_TEST' OR
     lv_msg CS 'CERTIFICATION' OR
     lv_msg CS 'FROZEN SESSION CONTRACT' OR
     lv_msg CS 'FROZEN CERTIFIED SESSION CONTRACT' OR
     lv_msg CS 'CURRENT PROFILE CONTRACT' OR
     lv_msg CS 'OBJECT PROOF' OR
     lv_msg CS 'TRACE_TABLE' OR
     lv_msg CS 'TRACE_FIELD' OR
     lv_msg CS 'OBJECT_FIELD' OR
     lv_msg CS 'RUNTIME CONTRACT' OR
     lv_msg CS 'BEFORE SAP REPLAY'.
    cv_reset = abap_true.
  ENDIF.
ENDFORM.

FORM reopen_ready_scope_row
  USING    is_scope TYPE ty_staging_alv
  CHANGING cs_ready TYPE ty_staging_alv
           cv_done  TYPE abap_bool.

  DATA: ls_db    TYPE zbdc_staging_bup,
        ls_alv   TYPE ty_staging_alv,
        lv_reset TYPE abap_bool.

  CLEAR: cs_ready, cv_done.

  IF is_scope-status <> gc_st_ready.
    RETURN.
  ENDIF.

  SELECT SINGLE *
    FROM zbdc_staging_bup
    INTO @ls_db
    WHERE session_id = @is_scope-session_id
      AND row_index  = @is_scope-row_index.

  IF sy-subrc <> 0.
    RETURN.
  ENDIF.

  IF ls_db-status = gc_st_ready.
    MOVE-CORRESPONDING ls_db TO cs_ready.
    cv_done = abap_true.
    RETURN.
  ENDIF.

  CLEAR ls_alv.
  MOVE-CORRESPONDING ls_db TO ls_alv.
  PERFORM is_resettable_gate
    USING    ls_alv
    CHANGING lv_reset.

  IF lv_reset <> abap_true.
    RETURN.
  ENDIF.

  UPDATE zbdc_staging_bup
    SET status    = @gc_st_ready,
        error_msg = @space,
        last_error = @space
    WHERE session_id = @is_scope-session_id
      AND row_index  = @is_scope-row_index.

  IF sy-subrc = 0.
    ls_db-status = gc_st_ready.
    CLEAR: ls_db-error_msg, ls_db-last_error.
    MOVE-CORRESPONDING ls_db TO cs_ready.
    cv_done = abap_true.
  ENDIF.
ENDFORM.

FORM current_ready_scope
  USING    it_scope TYPE ty_t_staging_alv
  CHANGING ct_ready TYPE ty_t_staging_alv.

  DATA: ls_scope   TYPE ty_staging_alv,
        ls_curr    TYPE ty_staging_alv,
        lv_reopen  TYPE abap_bool,
        lv_changed TYPE abap_bool.

  REFRESH ct_ready.
  PERFORM prepare_alv_0400.

  LOOP AT it_scope INTO ls_scope.
    CLEAR ls_curr.
    READ TABLE gt_staging_alv INTO ls_curr
      WITH KEY session_id = ls_scope-session_id
               row_index  = ls_scope-row_index.
    IF sy-subrc = 0 AND ls_curr-status = gc_st_ready.
      APPEND ls_curr TO ct_ready.
      CONTINUE.
    ENDIF.

    CLEAR: ls_curr, lv_reopen.
    PERFORM reopen_ready_scope_row
      USING    ls_scope
      CHANGING ls_curr lv_reopen.
    IF lv_reopen = abap_true.
      APPEND ls_curr TO ct_ready.
      lv_changed = abap_true.
    ENDIF.
  ENDLOOP.

  IF lv_changed = abap_true.
    COMMIT WORK AND WAIT.
    PERFORM prepare_alv_0400.
  ENDIF.
ENDFORM.

*& Strictly separated 0500 execution actions

*& Close confirmation popup first, execute on next PAI roundtrip

*& Validate 0500 monitor state without repairing or clearing it.
*& A contradictory state is evidence of a lifecycle defect and is blocked
*& until an explicit exact-scope refresh/re-entry reconciles it.

FORM check_0500_state
  CHANGING cv_ok      TYPE abap_bool
           cv_message TYPE string.

  CLEAR: cv_ok, cv_message.

  IF gv_exec_run_active <> abap_true.
    cv_ok = abap_true.
    RETURN.
  ENDIF.

  CASE gv_exec_mon_kind.
    WHEN gc_mon_sm35.
      IF gt_exec_scope_0500 IS INITIAL.
        cv_message = 'Execution state is inconsistent: SM35 monitoring has no exact execution scope.'.
        RETURN.
      ENDIF.

    WHEN OTHERS.
      cv_message = 'Execution state is inconsistent: active monitor kind is missing or unsupported.'.
      RETURN.
  ENDCASE.

  cv_ok = abap_true.
ENDFORM.

FORM request_0500_run USING iv_engine TYPE csequence.
  DATA: lv_state_ok  TYPE abap_bool,
        lv_state_msg TYPE string,
        lv_sel_ok    TYPE abap_bool,
        lv_sel_msg   TYPE string.

  PERFORM check_0500_state
    CHANGING lv_state_ok lv_state_msg.
  IF lv_state_ok <> abap_true.
    PERFORM userize_ui_message USING lv_state_msg CHANGING gv_ui_message.
    MESSAGE gv_ui_message TYPE 'S' DISPLAY LIKE 'E'.
    RETURN.
  ENDIF.

  IF gv_exec_run_active = abap_true.
    MESSAGE s518(zbdc) WITH gv_exec_run_done gv_exec_run_total.
    RETURN.
  ENDIF.

  PERFORM scope_from_0500_sel CHANGING lv_sel_ok lv_sel_msg.
  IF lv_sel_ok <> abap_true.
    PERFORM userize_ui_message USING lv_sel_msg CHANGING gv_ui_message.
    MESSAGE gv_ui_message TYPE 'S' DISPLAY LIKE 'E'.
    RETURN.
  ENDIF.

 "Batch Input creation is a server-side BDC_OPEN/INSERT/CLOSE command.
 "Dispatch it at the explicit PAI command boundary; no synthetic OK-code
 "roundtrip or hidden second execution request is used.
  IF iv_engine = gc_mode_batch.
    gv_exec_run_phase = 'Creating SM35 batch-input session'.
    PERFORM force_0500_repaint.
    PERFORM queue_sm35_0500.
    PERFORM request_0500_pbo.
    RETURN.
  ENDIF.

 "Execute the exact selected CALL TRANSACTION scope at this explicit command
 "boundary. Runtime options are read once and validated before side effects.
  gv_exec_run_phase = 'Starting execution'.
  PERFORM force_0500_repaint.
  PERFORM execute_now_0500.
  PERFORM request_0500_pbo.
ENDFORM.

FORM execute_now_0500.
  DATA: lv_saved_mode    TYPE char30,
        lv_saved_bg      TYPE c LENGTH 1,
        lv_disp_mode     TYPE c LENGTH 1,
        lv_upd_mode      TYPE c LENGTH 1,
        lv_batch_size    TYPE i,
        lv_runtime_ok    TYPE abap_bool,
        lv_runtime_msg   TYPE string,
        lv_issue         TYPE abap_bool,
        lv_done          TYPE i,
        lv_total         TYPE i,
        lv_success_grp   TYPE i,
        lv_error_grp     TYPE i,
        lv_warning_grp   TYPE i,
        lv_ready_msg     TYPE string,
        ls_z580_state    TYPE ty_exec_qstate.

  lv_saved_mode = p_bdc_mode.
  lv_saved_bg   = chkp_background.

 "Direct action always means CALL TRANSACTION. Every display/update
 "combination uses the same synchronous certified generic engine.
  p_bdc_mode         = gc_mode_call.
  CLEAR chkp_background.
 "Mass processing continues with the next independent business group.
 "Only an explicit user STOP or a certified contract quarantine may stop it.
  chkp_stop_on_error = space.

  PERFORM get_ctu_policy
    CHANGING lv_disp_mode lv_upd_mode lv_batch_size
             lv_runtime_ok lv_runtime_msg.
  IF lv_runtime_ok <> abap_true.
    p_bdc_mode      = lv_saved_mode.
    chkp_background = lv_saved_bg.
    PERFORM userize_ui_message USING lv_runtime_msg CHANGING gv_ui_message.
    MESSAGE gv_ui_message TYPE 'S' DISPLAY LIKE 'E'.
    RETURN.
  ENDIF.

 "freeze the exact visible CT policy selected by the user. The old
 "path read the radio buttons again in RUN_EXECUTION_MONITOR and again in
 "execute_bdc_context; that made a later repaint/config reload capable of
 "turning an N run into A. One Execute Now click now owns one immutable mode.
  gv_z597_ctu_frozen = abap_true.
  gv_z597_ct_mode    = lv_disp_mode.
  gv_z597_ct_upd     = lv_upd_mode.
  gv_z597_ct_bsize   = lv_batch_size.

 "No secondary worker path may rebuild or replay a different BDCDATA contract.
  PERFORM run_execution_monitor USING gc_mode_call.

  CLEAR: gv_z597_ctu_frozen, gv_z597_ct_mode,
         gv_z597_ct_upd, gv_z597_ct_bsize.
  p_bdc_mode      = lv_saved_mode.
  chkp_background = lv_saved_bg.

  PERFORM after_0500_execute.
  PERFORM count_0500_q CHANGING lv_done lv_total.
  PERFORM has_0500_issue CHANGING lv_issue.
  PERFORM count_0500_outcome
    CHANGING lv_success_grp lv_error_grp lv_warning_grp lv_total.

 "close the CT evidence attempt explicitly for all 12 CT cases.
 "This prevents stale 'Running Call Transaction / Running interact' headers
 "after 01..12_CT_*_RUN_ALL / RUN_SELECTED complete or finish with issues.
  gv_exec_run_active = abap_false.
  CLEAR gv_exec_mon_kind.
  IF lv_issue = abap_true.
    gv_exec_run_phase = 'Completed with issue(s)'.
  ELSEIF lv_total > 0 AND lv_done >= lv_total.
    gv_exec_run_phase = 'Execution completed'.
  ELSE.
    gv_exec_run_phase = 'Completed with READY group(s) remaining'.
  ENDIF.
  PERFORM set_0500_progress USING lv_done lv_total gv_exec_elapsed.
  PERFORM flush_0500_queue.
  PERFORM refresh_0500_tools.

 "Remain in the monitor. The user can review the exact final queue and
 "choose Dashboard/Error Detail deliberately; no automatic navigation.
  IF lv_issue = abap_true.
    MESSAGE s519(zbdc) WITH lv_error_grp lv_warning_grp lv_success_grp lv_total DISPLAY LIKE 'W'.
  ELSEIF lv_total > 0 AND lv_done >= lv_total.
    MESSAGE s520(zbdc) WITH lv_done lv_total.
  ELSE.
    CLEAR lv_ready_msg.
    LOOP AT gt_exec_qstate INTO ls_z580_state WHERE state = gc_st_ready.
      IF ls_z580_state-message CP 'PROFILE_NOT_READY*'.
        lv_ready_msg = ls_z580_state-message.
        EXIT.
      ENDIF.
    ENDLOOP.
    IF lv_ready_msg IS NOT INITIAL.
      PERFORM userize_ui_message USING lv_ready_msg CHANGING gv_ui_message.
      MESSAGE gv_ui_message TYPE 'S' DISPLAY LIKE 'W'.
    ELSE.
      MESSAGE s521(zbdc) WITH lv_done lv_total DISPLAY LIKE 'W'.
    ENDIF.
  ENDIF.
ENDFORM.

*& Runtime queue projection for every selected business group

FORM exec_q_set
  USING    ps_key   TYPE ty_engine_group_key
           pv_state TYPE csequence
           pv_msg   TYPE csequence
           pv_obj   TYPE zbdc_result_bup-sap_object_id.

  FIELD-SYMBOLS <ls_state> TYPE ty_exec_qstate.

  READ TABLE gt_exec_qstate ASSIGNING <ls_state>
    WITH KEY session_id = ps_key-session_id
             record_key = ps_key-record_key
             row_index  = ps_key-row_index.
  IF sy-subrc <> 0.
    APPEND INITIAL LINE TO gt_exec_qstate ASSIGNING <ls_state>.
    <ls_state>-session_id = ps_key-session_id.
    <ls_state>-record_key = ps_key-record_key.
    <ls_state>-row_index = ps_key-row_index.
    <ls_state>-seq_no = lines( gt_exec_qstate ) + 1.
  ENDIF.

  <ls_state>-state = pv_state.
  <ls_state>-message = pv_msg.
  <ls_state>-sap_object = pv_obj.
ENDFORM.

*& Exact final SAP success text for one execution group

*& Reads only persisted SUCCESS protocol/lifecycle rows for the exact group.
*& The execute layer does not parse business objects or message semantics.
*& The newest S-message is used only to keep the visible 0500 state aligned
*& with the exact SAP post-SAVE text already stored in ZBDC_RESULT_BUP.

FORM get_exact_success_by_key
  USING    is_key     TYPE ty_engine_group_key
  CHANGING cv_found   TYPE abap_bool
           cv_message TYPE string.

  DATA: lt_res TYPE STANDARD TABLE OF zbdc_result_bup,
        ls_res TYPE zbdc_result_bup.

  CLEAR: cv_found, cv_message.

  IF is_key-record_key IS INITIAL.
    SELECT * FROM zbdc_result_bup INTO TABLE @lt_res
      WHERE session_id = @is_key-session_id
        AND row_index  = @is_key-row_index
        AND msg_type   = 'S'.
  ELSE.
    SELECT * FROM zbdc_result_bup INTO TABLE @lt_res
      WHERE session_id = @is_key-session_id
        AND record_key = @is_key-record_key
        AND msg_type   = 'S'.
  ENDIF.

  SORT lt_res BY created_at DESCENDING step DESCENDING.
  LOOP AT lt_res INTO ls_res.
    IF ls_res-message IS INITIAL.
      CONTINUE.
    ENDIF.
    cv_message = ls_res-message.
    cv_found = abap_true.
    RETURN.
  ENDLOOP.
ENDFORM.

*& finalize visible 0500 queue after synchronous CALL TRANSACTION
*& A MESSAGE W/E inside a low-level PERFORM can interrupt PAI before the
*& queue is rebuilt. The engine now writes terminal state into the selected
*& queue explicitly, so the monitor never remains stuck as PROCESSING after
*& a returned SAP error.

FORM finalize_q_from_group
  USING    is_key   TYPE ty_engine_group_key
           it_group TYPE ty_t_staging_alv.

  DATA: ls_src       TYPE ty_staging_alv,
        ls_db        TYPE zbdc_staging_bup,
        lv_total     TYPE i,
        lv_ok        TYPE i,
        lv_err       TYPE i,
        lv_warn      TYPE i,
        lv_processed TYPE i,
        lv_partial   TYPE i,
        lv_skipped   TYPE i,
        lv_sm35      TYPE i,
        lv_ready     TYPE i,
        lv_msg       TYPE string,
        lv_exact_success TYPE abap_bool.

  LOOP AT it_group INTO ls_src.
    CLEAR ls_db.
    SELECT SINGLE * FROM zbdc_staging_bup INTO @ls_db
      WHERE session_id = @ls_src-session_id
        AND row_index  = @ls_src-row_index.
    IF sy-subrc <> 0. MOVE-CORRESPONDING ls_src TO ls_db. ENDIF.
    lv_total = lv_total + 1.
    CASE ls_db-status.
      WHEN gc_st_success.   lv_ok = lv_ok + 1.
      WHEN gc_st_error.     lv_err = lv_err + 1.
      WHEN gc_st_warning.   lv_warn = lv_warn + 1.
      WHEN gc_st_processed. lv_processed = lv_processed + 1.
      WHEN gc_st_partial.   lv_partial = lv_partial + 1.
      WHEN gc_st_skipped.   lv_skipped = lv_skipped + 1.
      WHEN gc_st_sm35q OR 'SM35QUEUE' OR 'SM35RUN'. lv_sm35 = lv_sm35 + 1.
      WHEN gc_st_ready OR space. lv_ready = lv_ready + 1.
    ENDCASE.
    IF lv_msg IS INITIAL AND ls_db-error_msg IS NOT INITIAL. lv_msg = ls_db-error_msg. ENDIF.
  ENDLOOP.

  IF lv_total <= 0. RETURN. ENDIF.

  IF gv_z579_ct_started <> abap_true AND lv_ready = lv_total.
    lv_msg = gv_z579_pre_ct_message.
    IF lv_msg IS INITIAL.
      MESSAGE ID 'ZBDC' TYPE 'S' NUMBER '923' INTO lv_msg.
    ENDIF.
    PERFORM exec_q_set USING is_key 'BLOCKED_ONBOARDING' lv_msg ''.
    RETURN.
  ENDIF.

  IF lv_err > 0.
    IF lv_msg IS INITIAL. MESSAGE ID 'ZBDC' TYPE 'S' NUMBER '924' INTO lv_msg. ENDIF.
    PERFORM exec_q_set USING is_key gc_st_error lv_msg ''.
  ELSEIF lv_warn > 0.
    IF lv_msg IS INITIAL. MESSAGE ID 'ZBDC' TYPE 'S' NUMBER '925' INTO lv_msg. ENDIF.
    PERFORM exec_q_set USING is_key gc_st_warning lv_msg ''.
  ELSEIF lv_partial > 0.
    IF lv_msg IS INITIAL. MESSAGE ID 'ZBDC' TYPE 'S' NUMBER '926' INTO lv_msg. ENDIF.
    PERFORM exec_q_set USING is_key gc_st_partial lv_msg ''.
  ELSEIF lv_ok = lv_total.
 "staging SUCCESS intentionally clears ERROR_MSG, so recover the
 "exact post-SAVE SAP message from the structured result/protocol rows.
    CLEAR lv_exact_success.
    PERFORM get_exact_success_by_key
      USING    is_key
      CHANGING lv_exact_success lv_msg.
    IF lv_exact_success <> abap_true OR lv_msg IS INITIAL.
      MESSAGE ID 'ZBDC' TYPE 'S' NUMBER '927' INTO lv_msg.
    ENDIF.
    PERFORM exec_q_set USING is_key gc_st_success lv_msg ''.
  ELSEIF lv_processed > 0.
    IF lv_msg IS INITIAL. MESSAGE ID 'ZBDC' TYPE 'S' NUMBER '928' INTO lv_msg. ENDIF.
    PERFORM exec_q_set USING is_key gc_st_processed lv_msg ''.
  ELSEIF lv_skipped = lv_total.
    IF lv_msg IS INITIAL. MESSAGE ID 'ZBDC' TYPE 'S' NUMBER '929' INTO lv_msg. ENDIF.
    PERFORM exec_q_set USING is_key gc_st_skipped lv_msg ''.
  ELSEIF lv_sm35 = lv_total.
    IF lv_msg IS INITIAL. MESSAGE ID 'ZBDC' TYPE 'S' NUMBER '930' INTO lv_msg. ENDIF.
    PERFORM exec_q_set USING is_key gc_st_sm35q lv_msg ''.
  ELSE.
    IF lv_msg IS INITIAL. MESSAGE ID 'ZBDC' TYPE 'S' NUMBER '931' INTO lv_msg. ENDIF.
    PERFORM exec_q_set USING is_key gc_st_warning lv_msg ''.
  ENDIF.
ENDFORM.

FORM q_set_all
  USING pv_state TYPE csequence
        pv_msg   TYPE csequence.

  LOOP AT gt_exec_qstate ASSIGNING FIELD-SYMBOL(<ls_q_all>).
    <ls_q_all>-state = pv_state.
    <ls_q_all>-message = pv_msg.
  ENDLOOP.
ENDFORM.

FORM seed_0500_qstate
  USING pt_scope TYPE ty_t_staging_alv
        pv_state TYPE csequence
        pv_msg   TYPE csequence.

  DATA: lt_keys TYPE ty_t_engine_group_key,
        ls_key  TYPE ty_engine_group_key.

  REFRESH gt_exec_qstate.

  IF pt_scope IS INITIAL.
    RETURN.
  ENDIF.

  PERFORM build_engine_keys USING pt_scope CHANGING lt_keys.
  SORT lt_keys BY session_id record_key row_index.

  LOOP AT lt_keys INTO ls_key.
    PERFORM exec_q_set
      USING ls_key pv_state pv_msg ''.
  ENDLOOP.
ENDFORM.

FORM build_0500_from_q.
  TYPES: BEGIN OF ty_sid_0500_q,
           session_id TYPE zbdc_result_bup-session_id,
         END OF ty_sid_0500_q.
  DATA: lt_src       TYPE ty_t_staging_alv,
        ls_state     TYPE ty_exec_qstate,
        ls_src       TYPE ty_staging_alv,
        ls_first     TYPE ty_staging_alv,
        ls_exec      TYPE ty_exec_disp,
        lt_sid       TYPE SORTED TABLE OF ty_sid_0500_q
                       WITH UNIQUE KEY session_id,
        ls_sid       TYPE ty_sid_0500_q,
        lt_result    TYPE ty_t_result_726,
        lv_state_key TYPE char40,
        lv_src_key   TYPE char40,
        lv_unit_raw  TYPE string,
        lv_item_cnt  TYPE i.

  REFRESH gt_exec_disp.

  APPEND LINES OF gt_exec_scope_0500   TO lt_src.
  APPEND LINES OF gt_sm35_mon_process  TO lt_src.
  IF lt_src IS INITIAL AND
     gv_exec_run_active <> abap_true AND
     gv_exec_mon_kind IS INITIAL AND
     gv_exec_scope_ready <> abap_true.
    APPEND LINES OF gt_staging_alv TO lt_src.
  ENDIF.

  "The qstate projection used to leave Execution blank while 0500 was active.
  "Load persisted result evidence once for the exact visible sessions so the
  "Execution column always shows the latest real attempt/history projection.
  LOOP AT gt_exec_qstate INTO ls_state.
    IF ls_state-session_id IS INITIAL.
      CONTINUE.
    ENDIF.
    CLEAR ls_sid.
    ls_sid-session_id = ls_state-session_id.
    INSERT ls_sid INTO TABLE lt_sid.
  ENDLOOP.
  IF lt_sid IS NOT INITIAL.
    SELECT *
      FROM zbdc_result_bup
      INTO TABLE @lt_result
      FOR ALL ENTRIES IN @lt_sid
      WHERE session_id = @lt_sid-session_id.
  ENDIF.

  SORT gt_exec_qstate BY seq_no.
  LOOP AT gt_exec_qstate INTO ls_state.
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

    PERFORM batch_prefix_from_sid
      USING ls_state-session_id
      CHANGING ls_exec-batch_key.

    CLEAR lv_unit_raw.
    SELECT SINGLE file_name FROM zbdc_file_lg_bup
      WHERE session_id = @ls_state-session_id
      INTO @lv_unit_raw.
    IF lv_unit_raw IS INITIAL.
      lv_unit_raw = ls_state-session_id.
    ENDIF.
    PERFORM p1_split_unit_name
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
    CLEAR ls_exec-drill_tcode.
    APPEND ls_exec TO gt_exec_disp.
  ENDLOOP.

  PERFORM exec_q_overlay.
  LOOP AT gt_exec_disp ASSIGNING FIELD-SYMBOL(<ls_q_color>).
    PERFORM fill_execution USING lt_result CHANGING <ls_q_color>.
    PERFORM color_exec_row CHANGING <ls_q_color>.
  ENDLOOP.
ENDFORM.
FORM exec_q_overlay.
  DATA: ls_state     TYPE ty_exec_qstate,
        lv_found     TYPE abap_bool,
        lv_row_key   TYPE char40,
        lv_msg_upper TYPE string.

  IF gt_exec_qstate IS INITIAL. RETURN. ENDIF.

  LOOP AT gt_exec_disp ASSIGNING FIELD-SYMBOL(<ls_exec_q>).
    CLEAR: ls_state, lv_found.
    LOOP AT gt_exec_qstate INTO ls_state WHERE session_id = <ls_exec_q>-session_id.
      CLEAR lv_row_key.
      IF ls_state-row_index IS NOT INITIAL.
        WRITE ls_state-row_index TO lv_row_key LEFT-JUSTIFIED.
        CONDENSE lv_row_key NO-GAPS.
      ENDIF.
      IF ( ls_state-record_key IS NOT INITIAL AND ls_state-record_key = <ls_exec_q>-group_key ) OR
         ( ls_state-record_key IS INITIAL AND lv_row_key IS NOT INITIAL AND <ls_exec_q>-group_key = lv_row_key ).
        lv_found = abap_true. EXIT.
      ENDIF.
    ENDLOOP.
    IF lv_found <> abap_true. CONTINUE. ENDIF.

    lv_msg_upper = ls_state-message. TRANSLATE lv_msg_upper TO UPPER CASE.
    "V17.9.3.4 route-state fix: queue overlay owns execution lifecycle only.
    "A terminal SUCCESS overlay must not erase a navigation projection that
    "BUILD_EXEC_COCKPIT already proved from persisted result + certified route.
    "Non-success queue states still clear navigation to prevent stale links.
    IF ls_state-state <> gc_st_success.
      CLEAR: <ls_exec_q>-sap_object_id, <ls_exec_q>-sap_object_text,
             <ls_exec_q>-drill_tcode, <ls_exec_q>-review_state.
    ENDIF.

    CASE ls_state-state.
      WHEN 'BLOCKED_ONBOARDING'.
        <ls_exec_q>-icon = '@09@'. <ls_exec_q>-msg_type = 'W'. <ls_exec_q>-run_status = 'BLOCKED_ONBOARDING'.
        <ls_exec_q>-health_text = 'Execution context incomplete; SAP not started'.
        <ls_exec_q>-action_hint = 'Restore exact frozen Script/Mapping/session context'.
      WHEN gc_st_ready.
        <ls_exec_q>-icon = '@09@'. <ls_exec_q>-msg_type = 'I'. <ls_exec_q>-run_status = gc_st_ready.
        <ls_exec_q>-health_text = 'Ready for SAP execution'. <ls_exec_q>-action_hint = 'Execute selected/ready group'.
      WHEN gc_st_queued.
        <ls_exec_q>-icon = '@09@'. <ls_exec_q>-msg_type = 'I'. <ls_exec_q>-run_status = gc_st_queued.
        <ls_exec_q>-health_text = 'Waiting in selected queue'. <ls_exec_q>-action_hint = 'Starts after the active group'.
      WHEN gc_st_processing.
        <ls_exec_q>-icon = '@09@'. <ls_exec_q>-msg_type = 'I'. <ls_exec_q>-run_status = gc_st_processing.
        <ls_exec_q>-health_text = 'Running SAP transaction'. <ls_exec_q>-action_hint = 'Wait for executor to return'.
      WHEN gc_st_verifying.
        <ls_exec_q>-icon = '@09@'. <ls_exec_q>-msg_type = 'I'. <ls_exec_q>-run_status = gc_st_verifying.
        <ls_exec_q>-health_text = 'Finalizing execution protocol'. <ls_exec_q>-action_hint = 'Wait for protocol reconciliation'.
      WHEN gc_st_sm35q OR 'SM35QUEUE' OR 'SM35RUN'.
        <ls_exec_q>-icon = '@09@'. <ls_exec_q>-msg_type = 'I'. <ls_exec_q>-run_status = gc_st_sm35q.
        IF gv_last_sm35_group IS NOT INITIAL.
          <ls_exec_q>-health_text = |SM35 queued { gv_last_sm35_group }|.
        ELSE.
          <ls_exec_q>-health_text = 'SM35 session queued'.
        ENDIF.
        <ls_exec_q>-action_hint = 'Open SM35 Monitor; process exact session in SM35; status updates automatically'.
      WHEN gc_st_success.
        <ls_exec_q>-icon = '@08@'. <ls_exec_q>-msg_type = 'S'. <ls_exec_q>-run_status = gc_st_success.
        <ls_exec_q>-health_text = 'Execution successful'. <ls_exec_q>-action_hint = 'View execution evidence'.
      WHEN gc_st_processed.
        <ls_exec_q>-icon = '@08@'. <ls_exec_q>-msg_type = 'I'. <ls_exec_q>-run_status = gc_st_processed.
        <ls_exec_q>-health_text = 'Execution processed'. <ls_exec_q>-action_hint = 'Review exact SAP BDC protocol'.
      WHEN gc_st_warning.
        <ls_exec_q>-icon = '@09@'. <ls_exec_q>-msg_type = 'W'. <ls_exec_q>-run_status = gc_st_warning.
        <ls_exec_q>-health_text = 'Execution completed with warning'. <ls_exec_q>-action_hint = 'Review exact SAP protocol'.
      WHEN gc_st_partial.
        <ls_exec_q>-icon = '@09@'. <ls_exec_q>-msg_type = 'W'. <ls_exec_q>-run_status = gc_st_partial.
        <ls_exec_q>-health_text = 'Partial execution outcome'. <ls_exec_q>-action_hint = 'Review exact SAP protocol before retry'.
      WHEN 'SM35NOSESSION'.
        <ls_exec_q>-icon = '@0A@'. <ls_exec_q>-msg_type = 'E'. <ls_exec_q>-run_status = gc_st_error.
        <ls_exec_q>-health_text = 'SM35 session not created'. <ls_exec_q>-action_hint = 'Review execution preflight and SM35 authorization'.
      WHEN gc_st_error.
        <ls_exec_q>-icon = '@0A@'. <ls_exec_q>-msg_type = 'E'. <ls_exec_q>-run_status = gc_st_error.
        <ls_exec_q>-health_text = 'BDC execution failed'. <ls_exec_q>-action_hint = 'Open Error Detail; review exact SAP protocol'.
      WHEN 'STOPPED'.
        <ls_exec_q>-icon = '@0A@'. <ls_exec_q>-msg_type = 'W'. <ls_exec_q>-run_status = gc_st_skipped.
        <ls_exec_q>-health_text = 'Not started'. <ls_exec_q>-action_hint = 'Run again when ready'.
    ENDCASE.

    <ls_exec_q>-message = ls_state-message.
    IF <ls_exec_q>-message IS INITIAL AND ls_state-state = gc_st_success.
      <ls_exec_q>-message = 'SAP execution completed successfully.'.
    ENDIF.
  ENDLOOP.
ENDFORM.

*& Surface SM35 creation blockers in the exact 0500 scope

FORM mark_no_sm35_scope
  USING pt_process TYPE ty_t_staging_alv
        pv_msg     TYPE string.

  DATA: lt_keys TYPE ty_t_engine_group_key,
        ls_key  TYPE ty_engine_group_key.

  IF pt_process IS INITIAL.
    RETURN.
  ENDIF.

  PERFORM build_engine_keys USING pt_process CHANGING lt_keys.
  LOOP AT lt_keys INTO ls_key.
    PERFORM exec_q_set USING ls_key 'SM35NOSESSION' pv_msg ''.
  ENDLOOP.

  PERFORM display_0500_queue.
ENDFORM.

*& Evidence-only non-blocking 0500 timer/state machine

FORM start_0500_timer.
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

FORM stop_0500_timer.
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

FORM refresh_0500_tools.
  IF go_grid_0500 IS BOUND.
    TRY.
        CALL METHOD go_grid_0500->set_toolbar_interactive.
        CALL METHOD cl_gui_cfw=>flush.
      CATCH cx_root.
    ENDTRY.
  ENDIF.
ENDFORM.

FORM live_elapsed CHANGING cv_elapsed_ms TYPE i.
  DATA lv_now TYPE i.
  GET RUN TIME FIELD lv_now.
  cv_elapsed_ms = lv_now - gv_exec_run_start_rt.
  IF cv_elapsed_ms < 0.
    cv_elapsed_ms = 0.
  ENDIF.
  cv_elapsed_ms = cv_elapsed_ms / 1000.
  gv_exec_elapsed = cv_elapsed_ms.
ENDFORM.

*& Require clean terminal SAP success for DB-verified CT object

*& strict synchronous CT protocol proof

FORM monitor_sm35_tick.
  DATA: lv_qstate      TYPE apqi-qstate,
        lv_apqi_found  TYPE abap_bool,
        lv_job_status  TYPE tbtco-status,
        lv_elapsed     TYPE i,
        lv_elapsed_sec TYPE i,
        lv_done        TYPE i,
        lv_total       TYPE i,
        lv_issue       TYPE abap_bool,
        lv_msg         TYPE string,
        lv_visible     TYPE i,
        lt_probe_log   TYPE ty_t_bdclm,
        ls_probe_log   TYPE bdclm,
        lv_proto_term  TYPE abap_bool,
        lv_proto_end   TYPE abap_bool,
        lv_proto_error TYPE abap_bool,
        lv_proto_bizs  TYPE abap_bool,
        lv_proto_admin TYPE abap_bool.

  PERFORM live_elapsed CHANGING lv_elapsed.
  lv_elapsed_sec = lv_elapsed / 1000.

  IF gv_exec_stop_req = abap_true OR g_stop_flag = 'X'.
    gv_exec_run_active = abap_false.
    gv_exec_run_phase = 'SM35 monitoring stopped; background session continues'.
    CLEAR gv_exec_mon_kind.
    PERFORM stop_0500_timer.
    PERFORM set_0500_progress
      USING gv_exec_run_done gv_exec_run_total lv_elapsed.
    PERFORM refresh_0500_tools.
    MESSAGE s550(zbdc) DISPLAY LIKE 'W'.
    RETURN.
  ENDIF.

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

 "terminal APQI is not sufficient to finalize an Extended-log BISM
 "attempt. SAP can publish QSTATE=F before the TemSe stream contains the
 "transaction's final application S-message. Probe only the persisted exact
 "QID and require the standard end marker S 00 382 before SUCCESS reconcile.
 "For an incorrect session, an exact E/A/X line is sufficient to start error
 "reconciliation. This logic is processing-mode agnostic (A/E/N).
  CLEAR: lv_proto_term, lv_proto_end, lv_proto_error,
         lv_proto_bizs, lv_proto_admin.
  REFRESH lt_probe_log.
  IF gv_sm35_mon_qid IS NOT INITIAL AND
     ( lv_qstate = 'F' OR lv_qstate = 'E' OR
       lv_apqi_found <> abap_true OR lv_job_status = 'F' ).
    PERFORM get_sm35_log
      USING    gv_sm35_mon_qid
      CHANGING lt_probe_log.
    LOOP AT lt_probe_log INTO ls_probe_log.
      IF ls_probe_log-mart = 'S'.
        CLEAR lv_proto_admin.
        IF ls_probe_log-mid = '00' AND
           ( ls_probe_log-mnr = '300' OR
             ls_probe_log-mnr = '355' OR
             ls_probe_log-mnr = '363' OR
             ls_probe_log-mnr = '364' OR
             ls_probe_log-mnr = '365' OR
             ls_probe_log-mnr = '366' OR
             ls_probe_log-mnr = '370' OR
             ls_probe_log-mnr = '382' ).
          lv_proto_admin = abap_true.
          IF ls_probe_log-mnr = '382'.
            lv_proto_end = abap_true.
          ENDIF.
        ENDIF.
        IF lv_proto_admin <> abap_true.
          lv_proto_bizs = abap_true.
        ENDIF.
      ENDIF.
      IF ls_probe_log-mart = 'E' OR
         ls_probe_log-mart = 'A' OR
         ls_probe_log-mart = 'X'.
        lv_proto_error = abap_true.
      ENDIF.
    ENDLOOP.
  ENDIF.

 "once the exact APQI QID itself reaches F/E, enter normal
 "reconciliation immediately. reconcile_sm35 already calls
 "wait_sm35_protocol, which gives Extended-log TemSe time to expose the
 "application business S-message/end marker before persistence. Keeping a
 "second readiness gate here made the GUI timer responsible for TemSe timing
 "and could leave 0500 yellow until the user pressed Refresh Queue.
 "No success/error is inferred here; exact per-group protocol/APQI evidence
 "is still the authority inside reconcile_sm35.

  IF lv_apqi_found <> abap_true.
    IF lv_proto_bizs = abap_true OR
       lv_proto_end = abap_true OR lv_proto_error = abap_true.
      lv_proto_term = abap_true.
    ELSEIF gv_last_sm35_jobname IS INITIAL.
      gv_exec_run_phase =
        |SM35 { gv_sm35_mon_group } left APQI; waiting for complete exact-QID protocol|.
      RETURN.
    ENDIF.
  ENDIF.

 "The RSBDCBTC compatibility job can finish before APQI/log persistence.
 "Only APQI terminal state or a canceled job is final.
  IF lv_job_status = 'A'.
    DATA(lv_zm932_6049_1) = |{ gv_last_sm35_jobname }|.
    DATA(lv_zm932_6049_2) = |{ gv_sm35_mon_group }|.
    MESSAGE ID 'ZBDC' TYPE 'S' NUMBER '932'
      WITH lv_zm932_6049_1 lv_zm932_6049_2 INTO lv_msg.
    PERFORM stamp_sm35_action USING gt_sm35_mon_process lv_msg.
    gv_exec_run_done   = 0.
    gv_exec_run_active = abap_false.
    gv_exec_run_phase  = 'RSBDCBTC job canceled; session still queued'.
    CLEAR: gv_exec_mon_kind, gv_sm35_job_finished.
    PERFORM stop_0500_timer.
    PERFORM prepare_alv_0400.
    PERFORM build_exec_cockpit.
    PERFORM display_0500_queue.
    lv_visible = gv_exec_run_done.
    PERFORM set_0500_progress USING lv_visible gv_exec_run_total lv_elapsed.
    PERFORM refresh_0500_tools.
    PERFORM userize_ui_message USING lv_msg CHANGING gv_ui_message.
    MESSAGE gv_ui_message TYPE 'S' DISPLAY LIKE 'W'.
    RETURN.
  ENDIF.

  IF lv_qstate = 'E' OR lv_qstate = 'F' OR lv_proto_term = abap_true.
    IF lv_qstate = 'E' OR lv_qstate = 'F'.
      DATA(lv_zm933_6069_1) = |{ gv_sm35_mon_group }|.
      DATA(lv_zm933_6069_2) = |{ lv_qstate }|.
      MESSAGE ID 'ZBDC' TYPE 'S' NUMBER '933'
        WITH lv_zm933_6069_1 lv_zm933_6069_2 INTO lv_msg.
    ELSE.
      DATA(lv_zm934_6071_1) = |{ gv_sm35_mon_group }|.
      MESSAGE ID 'ZBDC' TYPE 'S' NUMBER '934'
        WITH lv_zm934_6071_1 INTO lv_msg.
    ENDIF.
    PERFORM q_set_all USING 'VERIFYING' lv_msg.
    PERFORM reconcile_sm35
      USING gt_sm35_mon_process gv_sm35_mon_group
            gv_sm35_mon_qid lv_msg.

  ELSEIF lv_job_status = 'F' AND lv_elapsed_sec >= 10.
 "RSBDCBTC can finish after deleting/moving the APQI row, leaving QSTATE blank.
 "Do not wait blindly for 300 seconds; reconcile real protocol/object proof.
    gv_sm35_job_finished = abap_true.
    IF lv_apqi_found = abap_true.
      DATA(lv_zm935_6083_1) = |{ lv_qstate }|.
      MESSAGE ID 'ZBDC' TYPE 'S' NUMBER '935'
        WITH lv_zm935_6083_1 INTO lv_msg.
    ELSE.
      MESSAGE ID 'ZBDC' TYPE 'S' NUMBER '936' INTO lv_msg.
    ENDIF.
    PERFORM q_set_all USING 'VERIFYING' lv_msg.
    PERFORM reconcile_sm35
      USING gt_sm35_mon_process gv_sm35_mon_group
            gv_sm35_mon_qid lv_msg.

  ELSE.
    IF lv_job_status = 'F'.
      gv_sm35_job_finished = abap_true.
      gv_exec_run_phase =
        |Verifying SM35 { gv_sm35_mon_group }; RSBDCBTC job finished, session state { lv_qstate }|.
    ELSEIF lv_qstate = 'R' OR lv_qstate = 'S' OR lv_qstate = 'C'.
      gv_exec_run_phase =
        |SM35 processing { gv_sm35_mon_group }; session state { lv_qstate }|.
    ELSEIF lv_job_status IS INITIAL.
      gv_exec_run_phase = |SM35 queued { gv_sm35_mon_group }|.
    ELSE.
      gv_exec_run_phase =
        |RSBDCBTC job { lv_job_status }; session state { lv_qstate }|.
    ENDIF.

 "Do not report ERROR merely because RSBDCBTC ended first.
 "Wait for APQI/log evidence to become final.
 "an explicitly processed standard SM35 session is external to
 "this dynpro and can legitimately take longer than the execution timeout.
 "When no compatibility background job exists, keep the exact-QID monitor
 "alive until SAP produces terminal APQI/protocol evidence or the user uses
 "Stop/Back. This is polling only; it never processes the session itself.
    IF gv_last_sm35_jobname IS INITIAL.
 "silent polling while the manual SM35 session is non-terminal.
 "Do not rewrite queue rows, rebuild ALV or trigger progress repaints on
 "every timer tick. The visible row already says SM35QUEUE; repaint once
 "only when exact APQI/TemSe evidence becomes terminal.
      IF lv_qstate = 'R' OR lv_qstate = 'S' OR lv_qstate = 'C'.
        gv_exec_run_phase = |SM35 processing { gv_sm35_mon_group }; exact QID monitored silently|.
      ELSE.
        gv_exec_run_phase = |SM35 queued { gv_sm35_mon_group }; exact QID monitored silently|.
      ENDIF.
      RETURN.
    ENDIF.

    IF gv_sm35_mon_timeout <= 0.
      MESSAGE ID 'ZBDC' TYPE 'S' NUMBER '937' INTO lv_msg.
      PERFORM stamp_sm35_action USING gt_sm35_mon_process lv_msg.
      COMMIT WORK AND WAIT.
      gv_exec_run_active = abap_false.
      gv_exec_run_phase = 'SM35 monitoring blocked by invalid context'.
      CLEAR: gv_exec_mon_kind, gv_sm35_job_finished.
      PERFORM stop_0500_timer.
      PERFORM userize_ui_message USING lv_msg CHANGING gv_ui_message.
      MESSAGE gv_ui_message TYPE 'S' DISPLAY LIKE 'E'.
      RETURN.
    ENDIF.

    IF lv_elapsed_sec < gv_sm35_mon_timeout.
      lv_visible = gv_exec_run_done.
      gv_exec_run_phase = |SM35 processing { gv_exec_run_queued }/{ gv_exec_run_total }; waiting for exact SAP protocol reconciliation|.
      PERFORM q_set_all USING gc_st_sm35q gv_exec_run_phase.
      PERFORM display_0500_queue.
      PERFORM set_0500_progress
        USING lv_visible gv_exec_run_total lv_elapsed.
      RETURN.
    ENDIF.

    DATA(lv_zm938_6149_1) = |{ gv_sm35_mon_timeout }|.
    DATA(lv_zm938_6149_2) = |{ gv_sm35_mon_group }|.
    DATA(lv_zm938_6149_3) = |{ lv_qstate }|.
    MESSAGE ID 'ZBDC' TYPE 'S' NUMBER '938'
      WITH lv_zm938_6149_1 lv_zm938_6149_2 lv_zm938_6149_3
      INTO lv_msg.
    PERFORM stamp_sm35_action USING gt_sm35_mon_process lv_msg.
    COMMIT WORK AND WAIT.
    gv_exec_run_done   = 0.
    gv_exec_run_active = abap_false.
    gv_exec_run_phase  = 'SM35 result still pending'.
    CLEAR: gv_exec_mon_kind, gv_sm35_job_finished.
    PERFORM stop_0500_timer.
    PERFORM prepare_alv_0400.
    PERFORM build_exec_cockpit.
    PERFORM display_0500_queue.
    lv_visible = gv_exec_run_done.
    PERFORM set_0500_progress USING lv_visible gv_exec_run_total lv_elapsed.
    PERFORM refresh_0500_tools.
    PERFORM userize_ui_message USING lv_msg CHANGING gv_ui_message.
    MESSAGE gv_ui_message TYPE 'S' DISPLAY LIKE 'W'.
    RETURN.
  ENDIF.

 "SM35 and CALL TRANSACTION remain independent executors. A terminal
 "session without exact transaction/object proof stays pending or warning;
 "no hidden executor fallback is permitted.

 "stop the active SM35 overlay before rebuilding 0500. Otherwise
 "build_0500_queue paints verified SUCCESS rows back to yellow SM35RUN.
  gv_exec_run_active = abap_false.
  CLEAR gv_exec_mon_kind.
  PERFORM prepare_alv_0400.
  PERFORM build_exec_cockpit.
  PERFORM display_0500_queue.
  PERFORM count_0500_q CHANGING lv_done lv_total.
  PERFORM has_0500_issue CHANGING lv_issue.

  gv_exec_run_done   = lv_done.
  PERFORM refresh_0500_tools.
  IF lv_issue = abap_true.
    gv_exec_run_phase = 'SM35 terminal state reconciled with issue(s)'.
  ELSEIF lv_total > 0 AND lv_done >= lv_total.
    gv_exec_run_phase = 'SM35 terminal state reconciled successfully'.
  ELSE.
    gv_exec_run_phase = 'SM35 status refreshed; SM35 protocol remains pending'.
  ENDIF.
  CLEAR: gv_exec_mon_kind, gv_sm35_job_finished.
  PERFORM stop_0500_timer.
  PERFORM set_0500_progress USING lv_done lv_total lv_elapsed.

  IF lv_issue = abap_true.
    MESSAGE s551(zbdc) DISPLAY LIKE 'E'.
  ELSEIF lv_total > 0 AND lv_done >= lv_total.
    MESSAGE s552(zbdc) WITH lv_done lv_total.
  ELSE.
    DATA(lv_z563_pending) = lv_total - lv_done.
    MESSAGE s553(zbdc) WITH lv_z563_pending.
  ENDIF.
ENDFORM.

FORM monitor_0500_tick.

  IF gv_exec_run_active <> abap_true.
    PERFORM stop_0500_timer.
    RETURN.
  ENDIF.

  IF gv_exec_mon_kind = gc_mon_sm35.
    PERFORM monitor_sm35_tick.
  ELSE.
    gv_exec_run_active = abap_false.
    gv_exec_run_phase = 'Unsupported monitor state blocked'.
    CLEAR gv_exec_mon_kind.
    PERFORM stop_0500_timer.
    MESSAGE s522(zbdc) DISPLAY LIKE 'E'.
  ENDIF.
ENDFORM.

*& Promote SM35 success rows from persisted message + DB proof

*& Sync visible 0500 BISM queue from persisted proof after return

FORM sync_0500_q_db
  USING pt_process TYPE ty_t_staging_alv.

  DATA: lt_keys      TYPE ty_t_engine_group_key,
        ls_key       TYPE ty_engine_group_key,
        lt_group     TYPE ty_t_staging_alv,
        ls_row       TYPE ty_staging_alv,
        ls_db        TYPE zbdc_staging_bup,
        lv_total     TYPE i,
        lv_success   TYPE i,
        lv_processed TYPE i,
        lv_error     TYPE i,
        lv_warning   TYPE i,
        lv_sm35      TYPE i,
        lv_msg       TYPE string,
        lv_done      TYPE i.

  IF pt_process IS INITIAL.
    RETURN.
  ENDIF.

  PERFORM build_engine_keys
    USING    pt_process
    CHANGING lt_keys.

  LOOP AT lt_keys INTO ls_key.
    CLEAR: lt_group, lv_total, lv_success, lv_processed, lv_error,
           lv_warning, lv_sm35, lv_msg.

    PERFORM collect_group_key
      USING    pt_process ls_key
      CHANGING lt_group.

    LOOP AT lt_group INTO ls_row.
      CLEAR ls_db.
      SELECT SINGLE *
        FROM zbdc_staging_bup
        INTO @ls_db
        WHERE session_id = @ls_row-session_id
          AND row_index  = @ls_row-row_index.
      IF sy-subrc <> 0.
        MOVE-CORRESPONDING ls_row TO ls_db.
      ENDIF.

      lv_total = lv_total + 1.
      CASE ls_db-status.
        WHEN gc_st_success.
 "preserve real SUCCESS from exact SM35 reconciliation.
 "incorrectly normalized SUCCESS back to PROCESSED while
 "painting the 0500 queue.
          lv_success = lv_success + 1.
        WHEN gc_st_processed.
          lv_processed = lv_processed + 1.
        WHEN gc_st_error.
          lv_error = lv_error + 1.
        WHEN gc_st_warning.
          lv_warning = lv_warning + 1.
        WHEN gc_st_sm35q OR 'SM35QUEUE' OR 'SM35RUN'.
          lv_sm35 = lv_sm35 + 1.
      ENDCASE.
      IF lv_msg IS INITIAL AND ls_db-error_msg IS NOT INITIAL.
        lv_msg = ls_db-error_msg.
      ENDIF.
    ENDLOOP.

    IF lv_total <= 0.
      CONTINUE.
    ENDIF.

    IF lv_error > 0.
      IF lv_msg IS INITIAL.
        MESSAGE ID 'ZBDC' TYPE 'S' NUMBER '939' INTO lv_msg.
      ENDIF.
      PERFORM exec_q_set USING ls_key gc_st_error lv_msg ''.
      lv_done = lv_done + 1.
    ELSEIF lv_warning > 0.
      IF lv_msg IS INITIAL.
        MESSAGE ID 'ZBDC' TYPE 'S' NUMBER '940' INTO lv_msg.
      ENDIF.
      PERFORM exec_q_set USING ls_key gc_st_warning lv_msg ''.
      lv_done = lv_done + 1.
    ELSEIF lv_success = lv_total.
      IF lv_msg IS INITIAL.
        MESSAGE ID 'ZBDC' TYPE 'S' NUMBER '941' INTO lv_msg.
      ENDIF.
      PERFORM exec_q_set USING ls_key gc_st_success lv_msg ''.
      lv_done = lv_done + 1.
    ELSEIF lv_success + lv_processed = lv_total.
      IF lv_msg IS INITIAL.
        MESSAGE ID 'ZBDC' TYPE 'S' NUMBER '942' INTO lv_msg.
      ENDIF.
      PERFORM exec_q_set USING ls_key gc_st_processed lv_msg ''.
      lv_done = lv_done + 1.
    ELSEIF lv_sm35 > 0.
      IF lv_msg IS INITIAL.
        MESSAGE ID 'ZBDC' TYPE 'S' NUMBER '943' INTO lv_msg.
      ENDIF.
      PERFORM exec_q_set USING ls_key gc_st_sm35q lv_msg ''.
    ENDIF.
  ENDLOOP.

  gv_exec_run_done = lv_done.
  g_exec_curr       = lv_done.
ENDFORM.

FORM queue_sm35_0500.
  DATA: lv_saved_mode TYPE char30,
        lv_saved_bg   TYPE c LENGTH 1,
        lt_process    TYPE ty_t_staging_alv,
        lt_monitor    TYPE ty_t_staging_alv,
        ls_monitor    TYPE ty_staging_alv,
        lt_keys       TYPE ty_t_engine_group_key,
        lv_total      TYPE i,
        lv_queued     TYPE i,
        lv_rt_start   TYPE i,
        lv_rt_end     TYPE i,
        lv_elapsed_ms TYPE i,
        lv_msg        TYPE string,
        lv_issue      TYPE abap_bool,
        lv_block_msg  TYPE string,
        lv_timeout    TYPE i.

  IF gv_exec_run_active = abap_true.
    MESSAGE s554(zbdc) DISPLAY LIKE 'W'.
    RETURN.
  ENDIF.

  lv_timeout = txtp_timeout.
  IF lv_timeout IS INITIAL.
    lv_timeout = 60.
  ENDIF.

  IF lv_timeout < 1 OR lv_timeout > 300.
    MESSAGE s555(zbdc) DISPLAY LIKE 'E'.
    RETURN.
  ENDIF.
  txtp_timeout = lv_timeout.

 "true BISM must not call RUN_EXECUTION_MONITOR recursively.
 "The old path pre-painted the selected group as an SM35 queue, then
 "called RUN_EXECUTION_MONITOR, which rebuilt the READY scope again and could
 "return with 0 inserted groups while the visible row stayed READY. This form
 "now owns the entire BISM queue action in one server-side path:
 " selected/all READY scope -> BDC_OPEN_GROUP -> BDC_INSERT -> BDC_CLOSE_GROUP.
  CLEAR: gv_exec_run_active, gv_exec_mon_kind, gv_sm35_mon_qid,
         gv_sm35_mon_group, gv_sm35_job_finished, gv_sm35_last_qstate,
         gv_last_sm35_jobname, gv_last_sm35_jobcount,
         gv_last_sm35_action, gv_last_sm35_group,
         gv_last_sm35_qid, gv_last_sm35_inserted,
         gv_last_sm35_expected.
  PERFORM stop_0500_timer.

  lv_saved_mode = p_bdc_mode.
  lv_saved_bg   = chkp_background.

  PERFORM prepare_alv_0400.
  IF gt_exec_scope_0500 IS NOT INITIAL.
    PERFORM current_ready_scope
      USING    gt_exec_scope_0500
      CHANGING lt_process.
  ELSE.
    PERFORM collect_ready_groups_all CHANGING lt_process.
    gv_exec_scope_text = 'all READY groups in this session'.
  ENDIF.

  PERFORM build_engine_keys USING lt_process CHANGING lt_keys.
  lv_total = lines( lt_keys ).

  IF lt_process IS INITIAL OR lv_total = 0.
    PERFORM display_0500_queue.
    PERFORM set_0500_progress USING 0 0 0.
    PERFORM refresh_0500_tools.
    MESSAGE s556(zbdc) DISPLAY LIKE 'W'.
    RETURN.
  ENDIF.

  gt_exec_scope_0500[] = lt_process[].
  gv_exec_scope_ready = abap_true.
  gv_0500_active      = abap_true.
  txtgv_exec_total    = lv_total.
  gv_exec_run_total   = lv_total.
  gv_exec_run_done    = 0.
  g_exec_curr         = 0.
  gv_exec_run_engine  = 'B'.
  gv_exec_run_phase   = 'Creating SM35 batch-input session'.
  GET RUN TIME FIELD lv_rt_start.
  gv_exec_run_start_rt = lv_rt_start.

 "Show the exact selected scope before the synchronous SM35 queue build.
 "The 0500 queue is seeded with every selected business group, so live
 "refresh never falls back to unrelated batches while SM35 is being created.
  PERFORM seed_0500_qstate
    USING gt_exec_scope_0500 gc_st_ready
          'Ready in exact selected SM35 scope'.
  PERFORM display_0500_queue.
  PERFORM set_0500_progress USING 0 lv_total 0.
  PERFORM flush_0500_queue.
  PERFORM force_0500_repaint.

  p_bdc_mode         = gc_mode_batch.
  chkp_background    = space.
  chkp_stop_on_error = space.

  PERFORM execute_bdc_engine USING lt_process gc_mode_batch.

  p_bdc_mode      = lv_saved_mode.
  chkp_background = lv_saved_bg.

  GET RUN TIME FIELD lv_rt_end.
  lv_elapsed_ms = lv_rt_end - lv_rt_start.
  IF lv_elapsed_ms < 0.
    lv_elapsed_ms = 0.
  ENDIF.
  lv_elapsed_ms = lv_elapsed_ms / 1000.
  gv_exec_elapsed = lv_elapsed_ms.

 "Reload DB state written by UPDATE_GROUP_RESULT during BDC_INSERT and keep
 "the 0500 grid scoped to exactly this button click.
  COMMIT WORK AND WAIT.
  PERFORM prepare_alv_0400.
  PERFORM build_exec_cockpit.
  PERFORM sync_0500_q_db USING lt_process.

 "after BISM preflight, do not leave a visible READY row with a
 "generic 'SM35 session was not created' message. Reload the exact DB
 "scope and surface the real preflight/gate message when no SM35 group was
 "inserted.
  CLEAR lv_block_msg.
  LOOP AT lt_process INTO ls_monitor.
    READ TABLE gt_staging_alv INTO DATA(ls_block_db)
      WITH KEY session_id = ls_monitor-session_id
               row_index  = ls_monitor-row_index.
    IF sy-subrc = 0 AND ls_block_db-status = gc_st_error.
      CONCATENATE ls_block_db-error_msg ls_block_db-last_error
        INTO lv_block_msg SEPARATED BY space.
      CONDENSE lv_block_msg.
      IF lv_block_msg IS INITIAL.
        lv_block_msg = 'SM35 preflight blocked this group before queue creation. Open Error Detail.'.
      ENDIF.
      EXIT.
    ENDIF.
  ENDLOOP.

  REFRESH lt_monitor.
  LOOP AT lt_process INTO ls_monitor.
    READ TABLE gt_staging_alv INTO DATA(ls_monitor_db)
      WITH KEY session_id = ls_monitor-session_id
               row_index  = ls_monitor-row_index.
    IF sy-subrc = 0 AND ls_monitor_db-status = gc_st_sm35q.
      APPEND ls_monitor_db TO lt_monitor.
    ENDIF.
  ENDLOOP.
  PERFORM display_0500_queue.
  PERFORM count_0500_sm35_queued CHANGING lv_queued lv_total.
  IF lv_total IS INITIAL.
    lv_total = gv_exec_run_total.
  ENDIF.

  IF gv_last_sm35_inserted > lv_queued.
    lv_queued = gv_last_sm35_inserted.
  ENDIF.
  IF lv_queued > lv_total AND lv_total > 0.
    lv_queued = lv_total.
  ENDIF.

  gv_exec_run_queued = lv_queued.
  gv_exec_run_done   = 0.
  g_exec_curr        = 0.
  CLEAR: gv_exec_mon_kind, gv_sm35_mon_qid,
         gv_sm35_mon_group, gv_sm35_job_finished,
         gv_sm35_last_qstate.
  PERFORM stop_0500_timer.

  PERFORM has_0500_issue CHANGING lv_issue.
  gv_exec_run_active = abap_false.
  CLEAR gv_exec_mon_kind.
  PERFORM stop_0500_timer.

  IF gv_last_sm35_group IS NOT INITIAL AND
     gv_last_sm35_qid IS NOT INITIAL AND
     gv_last_sm35_inserted > 0 AND
     gv_z488_sm35_fidelity_ok = abap_true AND
     lt_monitor IS NOT INITIAL.
 "bind the live cockpit monitor to the same exact QID returned by
 "BDC_OPEN_GROUP. Standard SM35 still owns execution; this timer only polls
 "APQI/TemSe and automatically reconciles terminal evidence back to 0500.
    gt_sm35_mon_process[] = lt_monitor[].
    gv_sm35_mon_group     = gv_last_sm35_group.
    gv_sm35_mon_qid       = gv_last_sm35_qid.
    gv_sm35_mon_timeout   = lv_timeout.
    gv_exec_mon_kind      = gc_mon_sm35.
    gv_exec_run_active    = abap_true.
    GET RUN TIME FIELD gv_exec_run_start_rt.

    gv_exec_run_phase = |SM35 session { gv_last_sm35_group } ready; choose SM35 Monitor to continue|.
    DATA(lv_zm944_6528_1) = |{ gv_last_sm35_group }|.
    DATA(lv_zm944_6528_2) = |{ lv_queued }|.
    DATA(lv_zm944_6528_3) = |{ lv_total }|.
    MESSAGE ID 'ZBDC' TYPE 'S' NUMBER '944'
      WITH lv_zm944_6528_1 lv_zm944_6528_2 lv_zm944_6528_3
      INTO lv_msg.
    PERFORM stamp_sm35_action USING lt_monitor lv_msg.
    COMMIT WORK AND WAIT.
    PERFORM set_0500_progress USING 0 lv_total lv_elapsed_ms.
    PERFORM flush_0500_queue.
    PERFORM refresh_0500_tools.
 "make the handoff explicit instead of relying only on the
 "status bar/Next Action column. The popup does not execute SM35; it
 "only tells the user what the next standard-SAP action is. Start the
 "silent exact-QID timer only after the user acknowledges the handoff so
 "the message cannot be visually lost behind timer roundtrips.
    PERFORM show_sm35_handoff
      USING gv_last_sm35_group lv_queued lv_total.
    PERFORM start_0500_timer.
 "popup is the single handoff message. Keep the status bar free
 "of a duplicate long success/info message.
  ELSE.
    gv_exec_run_phase = 'SM35 session was not created cleanly'.
    PERFORM set_0500_progress USING 0 lv_total lv_elapsed_ms.
    PERFORM flush_0500_queue.
    PERFORM refresh_0500_tools.

    IF gv_last_sm35_action IS NOT INITIAL.
      lv_msg = gv_last_sm35_action.
    ELSEIF lv_block_msg IS NOT INITIAL.
      lv_msg = lv_block_msg.
    ELSEIF lv_issue = abap_true.
      CONCATENATE
        'SM35 session not created:'
        'exact frozen execution context or SM35 preflight is incomplete;'
        'no SM35 processing was started. Open Error Detail.'
        INTO lv_msg SEPARATED BY space.
    ELSE.
      CONCATENATE
        'SM35 session not created:'
        'exact READY scope did not reach BDC_INSERT.'
        'This is a scope/preflight/setup issue,'
        'not SAP business rejection.'
        'Re-open Staging, select a READY group,'
        'restore exact frozen Script/Mapping/session context if required,'
        'then create SM35 again.'
        INTO lv_msg SEPARATED BY space.
    ENDIF.

    PERFORM mark_no_sm35_scope USING lt_process lv_msg.
    PERFORM flush_0500_queue.
    PERFORM refresh_0500_tools.

    IF lv_block_msg IS NOT INITIAL OR lv_issue = abap_true.
      PERFORM userize_ui_message USING lv_msg CHANGING gv_ui_message.
      MESSAGE gv_ui_message TYPE 'S' DISPLAY LIKE 'E'.
    ELSE.
      PERFORM userize_ui_message USING lv_msg CHANGING gv_ui_message.
      MESSAGE gv_ui_message TYPE 'S' DISPLAY LIKE 'W'.
    ENDIF.
  ENDIF.

  PERFORM force_0500_repaint.
ENDFORM.

FORM run_execution_monitor USING iv_engine_mode TYPE csequence.
  DATA lt_process  TYPE STANDARD TABLE OF ty_staging_alv.
  DATA lv_rt_start TYPE i.
  DATA lv_rt_end   TYPE i.
  DATA lv_rt_diff  TYPE i.
  DATA lv_scope    TYPE char60.
  DATA lv_old_mode TYPE char30.
  DATA lv_batch_run TYPE abap_bool.
  DATA lv_processed_grp TYPE i.
  DATA lv_final_total   TYPE i.
  DATA lt_run_keys      TYPE ty_t_engine_group_key.
  DATA lv_mode          TYPE c LENGTH 1.
  DATA lv_upd           TYPE c LENGTH 1.
  DATA lv_bsize         TYPE i.
  DATA lv_runtime_ok   TYPE abap_bool.
  DATA lv_runtime_msg  TYPE string.
  DATA lv_engine       TYPE char30.
  DATA lv_engine_ok    TYPE abap_bool.
  DATA lv_engine_msg   TYPE string.
  DATA lv_bsize_norm_exec TYPE string.

 "Mass execution continues independent business groups after a business
 "error. Only an explicit Stop Queue request or a quarantined contract stops
 "the run; no hidden stop-on-first-error policy.
  chkp_stop_on_error = space.

  IF gv_exec_stop_req = abap_true OR g_stop_flag = 'X'.
    MESSAGE s523(zbdc) DISPLAY LIKE 'W'.
    RETURN.
  ENDIF.

  IF gt_staging IS INITIAL.
    MESSAGE s524(zbdc) DISPLAY LIKE 'E'.
    RETURN.
  ENDIF.
  PERFORM prepare_alv_0400.

  IF gt_exec_scope_0500 IS NOT INITIAL.
    PERFORM current_ready_scope
      USING    gt_exec_scope_0500
      CHANGING lt_process.
  ELSE.
    PERFORM collect_ready_groups_all CHANGING lt_process.
    gv_exec_scope_text = 'all READY groups in this session'.
  ENDIF.

  PERFORM build_engine_keys USING lt_process CHANGING lt_run_keys.
  lv_final_total = lines( lt_run_keys ).
  txtgv_exec_total = lv_final_total.

  IF lt_process IS INITIAL OR lv_final_total = 0.
    MESSAGE w525(zbdc).
    RETURN.
  ENDIF.

  lv_scope = gv_exec_scope_text.
  IF lv_scope IS INITIAL.
    lv_scope = 'READY groups in this session'.
  ENDIF.
 "The explicit command is normalized once. It is not inferred from stale
 "checkboxes, background flags or compatibility overrides.
  PERFORM canon_exec_mode
    USING    iv_engine_mode
    CHANGING lv_engine lv_engine_ok lv_engine_msg.
  IF lv_engine_ok <> abap_true.
    PERFORM userize_ui_message USING lv_engine_msg CHANGING gv_ui_message.
    MESSAGE gv_ui_message TYPE 'S' DISPLAY LIKE 'E'.
    RETURN.
  ENDIF.

  CLEAR: lv_mode, lv_upd, lv_bsize, lv_runtime_ok, lv_runtime_msg.
  IF lv_engine = gc_mode_call.
    IF gv_z597_ctu_frozen = abap_true.
      lv_mode       = gv_z597_ct_mode.
      lv_upd        = gv_z597_ct_upd.
      lv_bsize      = gv_z597_ct_bsize.
      lv_runtime_ok = abap_true.
      CLEAR lv_runtime_msg.
    ELSE.
      PERFORM get_ctu_policy
        CHANGING lv_mode lv_upd lv_bsize lv_runtime_ok lv_runtime_msg.
    ENDIF.
  ELSE.
    CLEAR lv_bsize_norm_exec.
    PERFORM parse_pos_int
      USING    txtp_batch_size 'Batch size'
      CHANGING lv_bsize lv_runtime_ok lv_runtime_msg lv_bsize_norm_exec.
    IF lv_runtime_ok = abap_true.
      txtp_batch_size = lv_bsize_norm_exec.
    ENDIF.
  ENDIF.
  IF lv_runtime_ok <> abap_true.
    PERFORM userize_ui_message USING lv_runtime_msg CHANGING gv_ui_message.
    MESSAGE gv_ui_message TYPE 'S' DISPLAY LIKE 'E'.
    RETURN.
  ENDIF.

 "The explicit engine action is the command boundary; no hidden second dispatch.

  GET RUN TIME FIELD lv_rt_start.
  g_stop_flag           = space.
  gv_exec_stop_req      = abap_false.
  g_exec_curr           = 0.
  gv_exec_run_total     = lv_final_total.
  gv_exec_run_done      = 0.
  gv_exec_run_start_rt  = lv_rt_start.
  gv_exec_run_active    = abap_true.
  gv_exec_run_phase     = 'Preparing execution queue'.
  gt_exec_scope_0500[] = lt_process[].
  gv_exec_scope_ready  = abap_true.
  PERFORM seed_0500_qstate
    USING gt_exec_scope_0500 'QUEUED'
          'Waiting in exact selected execution queue'.
  PERFORM set_0500_progress USING 0 lv_final_total 0.
  PERFORM display_0500_queue.
  PERFORM flush_0500_queue.

  lv_old_mode = p_bdc_mode.
  IF lv_engine = gc_mode_batch.
    lv_batch_run = abap_true.
  ELSE.
    lv_batch_run = abap_false.
  ENDIF.

  IF lv_batch_run = abap_true.
 "True BISM path: one real BI session with group-by-group BDC_INSERT.
 "No BDC Mode/Update Mode, no CTU_PARAMS, no RSBDCBTC compatibility
 "processor. The session remains visible in SM35 for explicit processing.
    p_bdc_mode = gc_mode_batch.
    CLEAR: lv_mode, lv_upd.
    gv_exec_run_engine = 'B'.
    gv_exec_run_phase  = 'Creating SM35 batch-input session'.
    PERFORM execute_bdc_engine USING lt_process gc_mode_batch.
    PERFORM sync_0500_q_db USING lt_process.
    g_exec_curr = 0.
  ELSE.
    gv_exec_run_engine = 'C'.
    IF lv_mode = 'A'.
      gv_exec_run_phase  = 'Running interactive All-Screens Call Transaction'.
    ELSEIF lv_upd = 'A'.
      gv_exec_run_phase  = 'Running asynchronous-update Call Transaction'.
    ELSE.
      gv_exec_run_phase  = 'Running Call Transaction'.
    ENDIF.
 "Direct path: force CALL_TRANSACTION and process group-by-group so mode A
 "can show the real transaction/transaction screens.
    p_bdc_mode = gc_mode_call.
    PERFORM run_0500_group_loop USING lt_process lv_rt_start.
  ENDIF.

  p_bdc_mode = lv_old_mode.
  gv_exec_run_active = abap_false.

  GET RUN TIME FIELD lv_rt_end.

  lv_rt_diff = lv_rt_end - lv_rt_start.
  IF lv_rt_diff < 0.
    lv_rt_diff = 0.
  ENDIF.
 "GET RUN TIME returns microseconds. Store milliseconds for screen 0500.
  gv_exec_elapsed = lv_rt_diff / 1000.

 "keep the 0400 scope visible in 0500 after execution.
 "Clearing the scope made the queue/dashboard switch to an unrelated
 "session or all-session cockpit after EXEC/SM35. A new Run All /
 "Run Selected from 0400 will overwrite this scope.
  gv_exec_scope_ready = abap_true.

  PERFORM build_exec_cockpit.

 "progress must follow the exact 0400 scope, not the whole staging
 "session. Run All uses the whole READY queue; Run Selected uses only the
 "selected READY group(s). display_0500_queue filters GT_EXEC_DISP back
 "to GT_EXEC_SCOPE_0500 before counting.
  PERFORM display_0500_queue.
  IF lv_batch_run = abap_true.
    PERFORM count_0500_q CHANGING lv_processed_grp lv_final_total.
  ELSE.
 "The grid can intentionally retain earlier SUCCESS/ERROR rows for review.
 "Numeric progress, however, belongs to this exact attempt only.
    lv_processed_grp = gv_exec_run_done.
    lv_final_total   = gv_exec_run_total.
  ENDIF.
  IF gv_exec_run_total > 0. lv_final_total = gv_exec_run_total. ENDIF.
 "Never carry a previous attempt's cumulative terminal count into a retry
 "or a Refresh/Resume run; this is the 3/1 = 300% hardening.

  IF lv_batch_run = abap_true.
    DATA(lv_sm35_queued_0500) = 0.
    PERFORM count_0500_sm35_queued
      CHANGING lv_sm35_queued_0500 lv_final_total.
    IF lv_sm35_queued_0500 > 0.
 "keep the numeric progress business-real. SM35 queue creation
 "is visible in the phase/text and ALV rows, but it is not completion.
      IF gv_last_sm35_group IS NOT INITIAL.
        gv_exec_run_phase = |SM35 session created { lv_sm35_queued_0500 }/{ lv_final_total }; ready for SM35 Monitor|.
      ELSE.
        gv_exec_run_phase = |SM35 session created { lv_sm35_queued_0500 }/{ lv_final_total }; ready for SM35 Monitor|.
      ENDIF.
    ENDIF.
  ENDIF.

  g_exec_curr = lv_processed_grp.
  gv_exec_run_done = lv_processed_grp.
  IF gv_exec_stop_req = abap_true OR g_stop_flag = 'X'.
    gv_exec_run_phase = 'Stopped after current business group'.
  ELSEIF gv_exec_err_grp > 0 OR gv_exec_warn_grp > 0.
    gv_exec_run_phase = 'Completed with issue(s)'.
  ELSE.
    gv_exec_run_phase = 'Execution completed'.
  ENDIF.
  PERFORM set_0500_progress USING lv_processed_grp lv_final_total gv_exec_elapsed.
  PERFORM flush_0500_queue.

  IF lv_batch_run = abap_true.
    IF gv_last_sm35_action IS NOT INITIAL.
      PERFORM userize_ui_message USING gv_last_sm35_action CHANGING gv_ui_message.
      MESSAGE gv_ui_message TYPE 'S'.
    ELSE.
      MESSAGE s558(zbdc) WITH lv_processed_grp.
    ENDIF.
  ELSEIF gv_exec_stop_req = abap_true OR g_stop_flag = 'X'.
    MESSAGE s526(zbdc) WITH lv_processed_grp lv_final_total DISPLAY LIKE 'W'.
  ELSEIF gv_exec_err_grp > 0 OR gv_exec_warn_grp > 0.
    MESSAGE s527(zbdc) WITH gv_exec_err_grp gv_exec_warn_grp gv_exec_succ_grp lv_final_total DISPLAY LIKE 'W'.
  ELSE.
    MESSAGE s528(zbdc) WITH lv_processed_grp lv_final_total.
  ENDIF.

  PERFORM force_0500_repaint.
ENDFORM.

FORM count_0500_sm35_queued
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

FORM mark_0500_group
  USING iv_session TYPE csequence
        iv_group   TYPE csequence
        iv_status  TYPE csequence
        iv_health  TYPE csequence
        iv_action  TYPE csequence
        iv_msg     TYPE csequence.

  LOOP AT gt_exec_disp ASSIGNING FIELD-SYMBOL(<ls_0500_mark>)
       WHERE session_id = iv_session AND group_key = iv_group.
    <ls_0500_mark>-run_status = iv_status.
    <ls_0500_mark>-health_text = iv_health.
    <ls_0500_mark>-action_hint = iv_action.
    <ls_0500_mark>-message = iv_msg.
  ENDLOOP.

  PERFORM flush_0500_queue.
ENDFORM.

FORM run_0500_group_loop
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

 "direct CALL TRANSACTION is launched from Screen 0500 too.
 "Previously only the SM35 paths asserted this flag, so 's immediate
 "terminal synchronizer returned without doing anything for CT.
  gv_0500_active = abap_true.

 "One progress unit is one business document group, not one item row.
  PERFORM build_engine_keys USING it_process CHANGING lt_keys.
  lv_total_grp = lines( lt_keys ).

  LOOP AT lt_keys INTO ls_key.
    IF gv_exec_stop_req = abap_true OR g_stop_flag = 'X'.
      EXIT.
    ENDIF.

    lv_idx  = sy-tabix.
    lv_prev = lv_idx - 1.
    PERFORM collect_group_key USING it_process ls_key CHANGING lt_one.
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
    IF lv_elapsed_ms < 0.
      lv_elapsed_ms = 0.
    ENDIF.
    lv_elapsed_ms = lv_elapsed_ms / 1000.

    PERFORM set_0500_progress USING lv_prev lv_total_grp lv_elapsed_ms.
    PERFORM exec_q_set
      USING ls_key 'PROCESSING'
            'The next selected group starts after this transaction returns.' ''.
    PERFORM mark_0500_group
      USING ls_first-session_id lv_group_key 'PROCESSING'
            'Running SAP transaction'
            'Wait for the active SAP transaction to return'
            'The next selected group starts after this transaction returns.'.
    PERFORM sapgui_progress USING lv_idx lv_total_grp lv_group_key.
    PERFORM force_0500_repaint.

    lv_err_before = gv_exec_err_grp.
 "each selected group owns an independent CT-start latch.
    CLEAR: gv_z579_ct_started, gv_z579_pre_ct_message.
    PERFORM execute_bdc_engine USING lt_one gc_mode_call.
    IF g_stop_flag = 'X'.
      gv_exec_stop_req = abap_true.
    ENDIF.

    GET RUN TIME FIELD lv_rt_now.
    lv_elapsed_ms = lv_rt_now - iv_rt_start.
    IF lv_elapsed_ms < 0.
      lv_elapsed_ms = 0.
    ENDIF.
    lv_elapsed_ms = lv_elapsed_ms / 1000.

    gv_exec_run_done = lv_idx.
    g_exec_curr       = lv_idx.
    PERFORM prepare_alv_0400.
    PERFORM guard_ct_ready_group USING lt_one lv_group_key.
    PERFORM prepare_alv_0400.
    PERFORM finalize_q_from_group USING ls_key lt_one.

    PERFORM set_0500_progress USING lv_idx lv_total_grp lv_elapsed_ms.
    PERFORM display_0500_queue.
    PERFORM sapgui_progress USING lv_idx lv_total_grp lv_group_key.

    IF chkp_stop_on_error = 'X'
       AND ( gv_exec_err_grp > lv_err_before OR
             gv_exec_stop_req = abap_true ).
      gv_exec_stop_req = abap_true.
      EXIT.
    ENDIF.
  ENDLOOP.
ENDFORM.

*& CT no-silent-ready guard
*& If CALL TRANSACTION returned to 0500 but the exact selected group still
*& has only READY rows, convert it to a real terminal ERROR. This prevents
*& the misleading 0/N READY state without changing SM35/BISM behavior.

FORM guard_ct_ready_group
  USING pt_group     TYPE ty_t_staging_alv
        pv_group_key TYPE string.

  DATA: ls_group    TYPE ty_staging_alv,
        ls_curr     TYPE ty_staging_alv,
        ls_db       TYPE zbdc_staging_bup,
        lv_total    TYPE i,
        lv_ready    TYPE i,
        lv_terminal TYPE i,
        lv_tcode    TYPE sy-tcode,
        lv_msg      TYPE string.

  IF pt_group IS INITIAL.
    RETURN.
  ENDIF.

 "this guard is valid only after the actual CALL TRANSACTION statement
 "was entered. PROFILE_NOT_READY and other pre-SAP gates intentionally leave
 "rows READY and must never be rewritten as a committed/processed attempt.
  IF gv_z579_ct_started <> abap_true.
    RETURN.
  ENDIF.

  LOOP AT pt_group INTO ls_group.
    lv_total = lv_total + 1.
    CLEAR: ls_curr, ls_db.

    READ TABLE gt_staging_alv INTO ls_curr
      WITH KEY session_id = ls_group-session_id
               row_index  = ls_group-row_index.

    IF sy-subrc <> 0.
      SELECT SINGLE *
        FROM zbdc_staging_bup
        INTO @ls_db
        WHERE session_id = @ls_group-session_id
          AND row_index  = @ls_group-row_index.
      IF sy-subrc = 0.
        MOVE-CORRESPONDING ls_db TO ls_curr.
      ELSE.
        ls_curr = ls_group.
      ENDIF.
    ENDIF.

    CASE ls_curr-status.
      WHEN gc_st_success OR gc_st_error OR gc_st_warning
           OR gc_st_sm35q OR 'SM35QUEUE' OR 'SM35RUN'
           OR 'PROCESSING' OR 'VERIFYING' OR 'SKIPPED' OR 'PARTIAL'.
        lv_terminal = lv_terminal + 1.
      WHEN gc_st_ready OR space.
        lv_ready = lv_ready + 1.
      WHEN OTHERS.
        lv_terminal = lv_terminal + 1.
    ENDCASE.
  ENDLOOP.

  IF lv_total > 0 AND lv_ready = lv_total AND lv_terminal = 0.
    READ TABLE pt_group INTO ls_group INDEX 1.
    IF sy-subrc = 0.
      lv_tcode = ls_group-tcode.
    ENDIF.
    IF lv_tcode IS INITIAL.
      lv_tcode = p_transaction.
    ENDIF.

    CONCATENATE 'CALL TRANSACTION returned without terminal status for group'
                pv_group_key
                '- no SAP success/error protocol was captured.'
           INTO lv_msg SEPARATED BY space.
    CONCATENATE lv_msg
                'The group was moved from READY to PROCESSED/REVIEW to prevent silent duplicate execution.'
                'Review the exact SAP protocol and application state before any retry.'
           INTO lv_msg SEPARATED BY space.

    PERFORM save_synthetic_engine_log
      USING pt_group lv_tcode 0 gc_st_processed lv_msg '' 'X'.
    PERFORM update_group_result USING pt_group gc_st_processed lv_msg ''.
    PERFORM update_exec_counters USING pt_group.
    COMMIT WORK AND WAIT.

    gv_exec_err_grp  = gv_exec_err_grp + 1.
    gv_exec_run_phase = 'CALL TRANSACTION returned without terminal status'.
  ENDIF.
ENDFORM.

FORM request_0500_pbo.
  IF gv_0500_active <> abap_true.
    RETURN.
  ENDIF.
  TRY.
      cl_gui_cfw=>set_new_ok_code( new_code = 'ZREF500' ).
    CATCH cx_root.
 "A later user action/PBO will repaint the values.
  ENDTRY.
ENDFORM.

FORM progress_after_group
  USING pt_group TYPE ty_t_staging_alv.

  DATA: ls_first      TYPE ty_staging_alv,
        lv_rt_now     TYPE i,
        lv_elapsed_ms TYPE i,
        lv_group_key  TYPE string.

  IF gv_exec_run_active <> abap_true OR gv_exec_run_engine <> 'B'.
    RETURN.
  ENDIF.

 "BDC_INSERT means the transaction has been queued into the SM35 session.
 "For BISM screen 0500, the live progress bar represents queue creation
 "progress, not final business-document posting. Final execution status is
 "reconciled later from the exact SM35 protocol.
  gv_exec_run_queued = gv_exec_run_queued + 1.
  g_exec_curr        = gv_exec_run_queued.

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

  PERFORM set_0500_progress
    USING gv_exec_run_queued gv_exec_run_total lv_elapsed_ms.
  PERFORM sapgui_progress
    USING gv_exec_run_queued gv_exec_run_total gv_exec_run_phase.
  PERFORM flush_0500_queue.
ENDFORM.

*& Recover and reconcile manually processed SM35 sessions

FORM extract_sm35_group
  USING    pv_text  TYPE csequence
  CHANGING cv_group TYPE apqi-groupid.

  DATA: lv_text   TYPE string,
        lv_tail   TYPE string,
        lv_tok    TYPE string,
        lv_dummy  TYPE string,
        lv_off    TYPE i,
        lv_len    TYPE i,
        lv_pos    TYPE i,
        lv_chr    TYPE c LENGTH 1,
        lv_clean  TYPE string.

  CLEAR cv_group.
  lv_text = pv_text.
  TRANSLATE lv_text TO UPPER CASE.

 "the session name is data, not an application prefix. New durable
 "bindings always carry an explicit GROUP=<name> token. For queues created
 "before , accept only the literal standard message shape
 "SM35 SESSION <name>... . Never assume ZBDC/ZB or any TCODE-specific
 "prefix and never search APQI by newest group/time.
  FIND FIRST OCCURRENCE OF 'GROUP=' IN lv_text MATCH OFFSET lv_off.
  IF sy-subrc = 0.
    lv_off = lv_off + 6.
    lv_tail = lv_text+lv_off.
  ELSE.
    FIND FIRST OCCURRENCE OF 'SM35 SESSION ' IN lv_text MATCH OFFSET lv_off.
    IF sy-subrc <> 0.
      RETURN.
    ENDIF.
    lv_off = lv_off + 13.
    lv_tail = lv_text+lv_off.
  ENDIF.

  SPLIT lv_tail AT space INTO lv_tok lv_dummy.
  CONDENSE lv_tok NO-GAPS.
  IF lv_tok IS INITIAL.
    RETURN.
  ENDIF.

  CLEAR lv_clean.
  lv_len = strlen( lv_tok ).
  DO lv_len TIMES.
    lv_pos = sy-index - 1.
    lv_chr = lv_tok+lv_pos(1).
    IF lv_chr CO 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_'.
      CONCATENATE lv_clean lv_chr INTO lv_clean RESPECTING BLANKS.
    ELSE.
      EXIT.
    ENDIF.
  ENDDO.
  CONDENSE lv_clean NO-GAPS.
  IF lv_clean IS INITIAL.
    RETURN.
  ENDIF.

  cv_group = lv_clean.
ENDFORM.

*& Exact SM35 ownership binding
*& One durable binding row is written per business group. Reconciliation
*& is allowed only when every row in the current scope resolves to the same
*& exact application-session/group binding. No global/latest-session fallback.

FORM persist_sm35_binding
  USING pt_process TYPE ty_t_staging_alv
        pv_group   TYPE apqi-groupid
        pv_qid     TYPE apqi-qid.

  DATA: lt_keys      TYPE ty_t_engine_group_key,
        ls_key       TYPE ty_engine_group_key,
        lt_group     TYPE ty_t_staging_alv,
        ls_first     TYPE ty_staging_alv,
        ls_res       TYPE zbdc_result_bup,
        lv_step_max  TYPE zbdc_result_bup-step,
        lv_step      TYPE zbdc_result_bup-step,
        lv_ts        TYPE tzntstmps,
        lv_demo_date_836 TYPE sy-datum,
        lv_demo_time_836 TYPE sy-uzeit,
        lv_text      TYPE string,
        lv_attempt   TYPE zbdc_result_bup-attempt_no,
        lv_stage_status TYPE zbdc_staging_bup-status.

  FIELD-SYMBOLS <fv> TYPE any.

 "BDC_OPEN_GROUP's returned QID is the only accepted technical
 "identity. Persist it once per exact business group while the caller still
 "holds the ingestion-session lock. Reconciliation can then survive GUI
 "mode changes, program re-entry and APQI deletion after successful SM35
 "processing without ever guessing a queue by group/time.
  IF pt_process IS INITIAL OR pv_group IS INITIAL OR pv_qid IS INITIAL.
    RETURN.
  ENDIF.

  PERFORM build_engine_keys
    USING    pt_process
    CHANGING lt_keys.

  LOOP AT lt_keys INTO ls_key.
    REFRESH lt_group.
    PERFORM collect_group_key
      USING    pt_process ls_key
      CHANGING lt_group.
    READ TABLE lt_group INTO ls_first INDEX 1.
    IF sy-subrc <> 0.
      CONTINUE.
    ENDIF.

 "Persist ownership only for groups that BDC_INSERT actually queued.
    CLEAR lv_stage_status.
    SELECT SINGLE status
      FROM zbdc_staging_bup
      INTO @lv_stage_status
      WHERE session_id = @ls_first-session_id
        AND row_index  = @ls_first-row_index.
    IF sy-subrc <> 0 OR lv_stage_status <> gc_st_sm35q.
      CONTINUE.
    ENDIF.

    CLEAR lv_step_max.
    SELECT MAX( step )
      FROM zbdc_result_bup
      INTO @lv_step_max
      WHERE session_id = @ls_first-session_id
        AND record_key = @ls_first-record_key
        AND row_index  = @ls_first-row_index.
    lv_step = lv_step_max + 1.

    CLEAR lv_attempt.
    SELECT MAX( attempt_no ) FROM zbdc_result_bup INTO @lv_attempt
      WHERE session_id = @ls_first-session_id
        AND record_key = @ls_first-record_key.
    IF lv_attempt IS INITIAL OR lv_attempt <= 0.
      lv_attempt = 1.
    ENDIF.

    GET TIME STAMP FIELD lv_ts.
    PERFORM get_demo_now CHANGING lv_demo_date_836 lv_demo_time_836.
    lv_text = |SM35_BIND GROUP={ pv_group } QID={ pv_qid }|.

    DEFINE set_z703_bind.
      ASSIGN COMPONENT &1 OF STRUCTURE ls_res TO <fv>.
      IF sy-subrc = 0.
        <fv> = &2.
      ENDIF.
    END-OF-DEFINITION.

    CLEAR ls_res.
    set_z703_bind 'SESSION_ID'    ls_first-session_id.
    set_z703_bind 'RECORD_KEY'    ls_first-record_key.
    set_z703_bind 'GROUP_KEY'     ls_first-record_key.
    set_z703_bind 'ROW_INDEX'     ls_first-row_index.
    set_z703_bind 'TCODE'         ls_first-tcode.
    set_z703_bind 'MSG_TYPE'      'I'.
    set_z703_bind 'MSGTYP'        'I'.
    set_z703_bind 'MSG_ID'        'ZBDC'.
    set_z703_bind 'MSGID'         'ZBDC'.
    set_z703_bind 'MSG_NUMBER'    '106'.
    set_z703_bind 'MSGNR'         '106'.
    set_z703_bind 'MSG_NO'        '106'.
    set_z703_bind 'MESSAGE'       lv_text.
    set_z703_bind 'MESSAGE_TEXT'  lv_text.
    set_z703_bind 'PROGRAM_NAME'  'SM35_BIND'.
    set_z703_bind 'DYNAME'        'SM35_BIND'.
    set_z703_bind 'DYNPRO_NO'     '0000'.
    set_z703_bind 'DYNUMB'        '0000'.
    set_z703_bind 'DYNPRO'        '0000'.
    set_z703_bind 'FIELD_NAME'    'SM35_BIND'.
    set_z703_bind 'SCREEN_STEP'   lv_step.
    set_z703_bind 'STEP_SEQ'      lv_step.
    set_z703_bind 'MSG_SEQ'       lv_step.
    set_z703_bind 'RESULT_SEQ'    lv_step.
    set_z703_bind 'STEP'          lv_step.
    set_z703_bind 'EXEC_STATUS'   gc_st_sm35q.
    set_z703_bind 'LOCK_REASON'   'Exact BDC_OPEN_GROUP QID binding'.
    set_z703_bind 'ATTEMPT_NO'    lv_attempt.
    set_z703_bind 'ATTEMPT'       lv_attempt.
    set_z703_bind 'RETRY_FLAG'    ''.
    set_z703_bind 'CREATED_AT'    lv_ts.
    set_z703_bind 'CREATED_ON'    lv_demo_date_836.
    set_z703_bind 'CREATED_TM'    lv_demo_time_836.
    set_z703_bind 'CREATED_TIME'  lv_demo_time_836.
    set_z703_bind 'CREATED_BY'    sy-uname.

    INSERT zbdc_result_bup FROM ls_res.
    IF sy-subrc <> 0.
      MODIFY zbdc_result_bup FROM ls_res.
    ENDIF.
  ENDLOOP.
ENDFORM.

FORM extract_sm35_qid
  USING    pv_text TYPE csequence
  CHANGING cv_qid  TYPE apqi-qid.

  DATA: lv_text  TYPE string,
        lv_tail  TYPE string,
        lv_token TYPE string,
        lv_dummy TYPE string,
        lv_off   TYPE i.

  CLEAR cv_qid.
  lv_text = pv_text.
  FIND FIRST OCCURRENCE OF 'QID=' IN lv_text MATCH OFFSET lv_off.
  IF sy-subrc <> 0.
    RETURN.
  ENDIF.

  lv_off = lv_off + 4.
  lv_tail = lv_text+lv_off.
  SPLIT lv_tail AT space INTO lv_token lv_dummy.
  CONDENSE lv_token NO-GAPS.
  IF lv_token IS NOT INITIAL.
    cv_qid = lv_token.
  ENDIF.
ENDFORM.

FORM get_sm35_binding_row
  USING    ps_row   TYPE ty_staging_alv
  CHANGING cv_group TYPE apqi-groupid
           cv_qid   TYPE apqi-qid
           cv_found TYPE abap_bool.

  DATA: lt_res          TYPE STANDARD TABLE OF zbdc_result_bup,
        ls_res          TYPE zbdc_result_bup,
        lv_text         TYPE string,
        lv_stage_status TYPE zbdc_staging_bup-status,
        lv_stage_msg    TYPE zbdc_staging_bup-error_msg.

  CLEAR: cv_group, cv_qid, cv_found, lv_stage_status, lv_stage_msg.

 "an old binding is eligible only while this exact application row
 "is still queued/error/warning for that SM35 attempt. Once the user fixes it
 "back to READY, or it reaches SUCCESS, the old queue must not be loaded or
 "reconciled again. This closes cross-group, cross-upload and retry poisoning.
  SELECT SINGLE status, error_msg
    FROM zbdc_staging_bup
    INTO (@lv_stage_status, @lv_stage_msg)
    WHERE session_id = @ps_row-session_id
      AND row_index  = @ps_row-row_index.
  IF sy-subrc <> 0.
    lv_stage_status = ps_row-status.
    lv_stage_msg    = ps_row-error_msg.
  ENDIF.

  IF lv_stage_status <> gc_st_sm35q AND
     lv_stage_status <> gc_st_error AND
     lv_stage_status <> gc_st_warning AND
     lv_stage_status <> 'SM35RUN'.
    RETURN.
  ENDIF.

  IF ps_row-record_key IS INITIAL.
    SELECT * FROM zbdc_result_bup
      INTO TABLE @lt_res
      WHERE session_id = @ps_row-session_id
        AND row_index  = @ps_row-row_index
        AND field_name = 'SM35_BIND'.
  ELSE.
    SELECT * FROM zbdc_result_bup
      INTO TABLE @lt_res
      WHERE session_id = @ps_row-session_id
        AND record_key = @ps_row-record_key
        AND field_name = 'SM35_BIND'.
  ENDIF.
  SORT lt_res BY created_at DESCENDING step DESCENDING.
  READ TABLE lt_res INTO ls_res INDEX 1.
  IF sy-subrc = 0.
    lv_text = ls_res-message.
    PERFORM extract_sm35_group USING lv_text CHANGING cv_group.
    PERFORM extract_sm35_qid USING lv_text CHANGING cv_qid.
  ENDIF.

 "Compatibility for pre-queues is restricted to the exact row while
 "it is still persisted as SM35QUEUE. ERROR/READY text is never treated as
 "ownership evidence.
  IF cv_group IS INITIAL AND
     lv_stage_status = gc_st_sm35q AND
     ps_row-error_msg IS NOT INITIAL.
    PERFORM extract_sm35_group USING ps_row-error_msg CHANGING cv_group.
  ENDIF.

  IF cv_group IS NOT INITIAL.
 "ERROR/WARNING may also come from a later CALL TRANSACTION retry. It
 "belongs to this SM35 binding only when the current persisted message
 "names the exact bound session. This prevents an old SM35 attempt from
 "overwriting a newer CT result for the same business group.
    IF ( lv_stage_status = gc_st_error OR
         lv_stage_status = gc_st_warning ) AND
       ( lv_stage_msg IS INITIAL OR lv_stage_msg NS cv_group ).
      CLEAR: cv_group, cv_qid.
      RETURN.
    ENDIF.

    IF cv_qid IS INITIAL.
      PERFORM find_sm35_qid USING cv_group CHANGING cv_qid.
    ENDIF.
    IF cv_qid IS NOT INITIAL.
      SELECT SINGLE groupid
        FROM apqi
        INTO @DATA(lv_owner_group)
        WHERE mandant = @sy-mandt
          AND qid     = @cv_qid
          AND datatyp = 'BDC'.
      IF sy-subrc = 0 AND lv_owner_group <> cv_group.
        CLEAR: cv_group, cv_qid.
        RETURN.
      ENDIF.
    ENDIF.
    cv_found = abap_true.
  ENDIF.
ENDFORM.

FORM find_sm35_qid_for_scope
  USING    pt_scope TYPE ty_t_staging_alv
           pv_group TYPE apqi-groupid
  CHANGING cv_qid   TYPE apqi-qid.

  DATA: lt_keys      TYPE ty_t_engine_group_key,
        ls_key       TYPE ty_engine_group_key,
        lt_one       TYPE ty_t_staging_alv,
        ls_first     TYPE ty_staging_alv,
        lv_row_group TYPE apqi-groupid,
        lv_row_qid   TYPE apqi-qid,
        lv_found     TYPE abap_bool.

  CLEAR cv_qid.
  IF pt_scope IS INITIAL OR pv_group IS INITIAL.
    RETURN.
  ENDIF.

  PERFORM build_engine_keys USING pt_scope CHANGING lt_keys.
  LOOP AT lt_keys INTO ls_key.
    REFRESH lt_one.
    PERFORM collect_group_key USING pt_scope ls_key CHANGING lt_one.
    READ TABLE lt_one INTO ls_first INDEX 1.
    IF sy-subrc <> 0.
      CLEAR cv_qid.
      RETURN.
    ENDIF.

    PERFORM get_sm35_binding_row
      USING ls_first CHANGING lv_row_group lv_row_qid lv_found.
    IF lv_found <> abap_true OR lv_row_group <> pv_group.
      CLEAR cv_qid.
      RETURN.
    ENDIF.
    IF lv_row_qid IS NOT INITIAL.
      IF cv_qid IS INITIAL.
        cv_qid = lv_row_qid.
      ELSEIF cv_qid <> lv_row_qid.
        CLEAR cv_qid.
        RETURN.
      ENDIF.
    ENDIF.
  ENDLOOP.

  IF cv_qid IS INITIAL.
    PERFORM find_sm35_qid USING pv_group CHANGING cv_qid.
  ENDIF.
ENDFORM.

FORM find_sm35_group_for_scope
  USING    pt_scope TYPE ty_t_staging_alv
  CHANGING cv_group TYPE apqi-groupid.

  DATA: lt_keys       TYPE ty_t_engine_group_key,
        ls_key        TYPE ty_engine_group_key,
        lt_one        TYPE ty_t_staging_alv,
        ls_first      TYPE ty_staging_alv,
        lv_row_group  TYPE apqi-groupid,
        lv_row_qid    TYPE apqi-qid,
        lv_found      TYPE abap_bool.

  CLEAR cv_group.
  IF pt_scope IS INITIAL.
    RETURN.
  ENDIF.

  PERFORM build_engine_keys USING pt_scope CHANGING lt_keys.
  LOOP AT lt_keys INTO ls_key.
    REFRESH lt_one.
    PERFORM collect_group_key USING pt_scope ls_key CHANGING lt_one.
    READ TABLE lt_one INTO ls_first INDEX 1.
    IF sy-subrc <> 0.
      CLEAR cv_group.
      RETURN.
    ENDIF.

    PERFORM get_sm35_binding_row
      USING ls_first
      CHANGING lv_row_group lv_row_qid lv_found.
    IF lv_found <> abap_true OR lv_row_group IS INITIAL.
      CLEAR cv_group.
      RETURN.
    ENDIF.

    IF cv_group IS INITIAL.
      cv_group = lv_row_group.
    ELSEIF cv_group <> lv_row_group.
 "A visible scope spans more than one SM35 session. The caller must
 "reconcile each exact binding separately; never reuse one global session.
      CLEAR cv_group.
      RETURN.
    ENDIF.
  ENDLOOP.
ENDFORM.

FORM sync_visible_sm35.
  TYPES: BEGIN OF ty_bind_group,
           groupid TYPE apqi-groupid,
         END OF ty_bind_group,
         BEGIN OF ty_bound_row,
           groupid TYPE apqi-groupid,
           qid     TYPE apqi-qid,
           row     TYPE ty_staging_alv,
         END OF ty_bound_row.
  DATA: lt_groups TYPE SORTED TABLE OF ty_bind_group WITH UNIQUE KEY groupid,
        lt_bound  TYPE STANDARD TABLE OF ty_bound_row,
        ls_group  TYPE ty_bind_group,
        ls_bound  TYPE ty_bound_row,
        lt_scope  TYPE ty_t_staging_alv,
        ls_alv    TYPE ty_staging_alv,
        lv_group  TYPE apqi-groupid,
        lv_qid    TYPE apqi-qid,
        lv_found  TYPE abap_bool.

  IF gt_staging_alv IS INITIAL AND gt_staging IS NOT INITIAL.
    PERFORM prepare_alv_0400.
  ENDIF.

 "Resolve each queued business row once. This scales linearly and keeps
 "large 1000+ group cockpits from repeatedly querying the same binding.
  LOOP AT gt_staging_alv INTO ls_alv.
    IF ls_alv-status <> gc_st_sm35q AND
       ls_alv-status <> gc_st_error AND
       ls_alv-status <> gc_st_warning.
      CONTINUE.
    ENDIF.
    CLEAR: lv_group, lv_qid, lv_found, ls_bound.
    PERFORM get_sm35_binding_row
      USING ls_alv CHANGING lv_group lv_qid lv_found.
    IF lv_found = abap_true AND lv_group IS NOT INITIAL.
      ls_group-groupid = lv_group.
      INSERT ls_group INTO TABLE lt_groups.
      ls_bound-groupid = lv_group.
      ls_bound-qid     = lv_qid.
      ls_bound-row     = ls_alv.
      APPEND ls_bound TO lt_bound.
    ENDIF.
  ENDLOOP.

  LOOP AT lt_groups INTO ls_group.
    REFRESH lt_scope.
    CLEAR lv_qid.
    LOOP AT lt_bound INTO ls_bound
      WHERE groupid = ls_group-groupid.
      APPEND ls_bound-row TO lt_scope.
      IF lv_qid IS INITIAL.
        lv_qid = ls_bound-qid.
      ENDIF.
    ENDLOOP.
    IF lt_scope IS INITIAL.
      CONTINUE.
    ENDIF.
    IF lv_qid IS INITIAL.
      PERFORM find_sm35_qid USING ls_group-groupid CHANGING lv_qid.
    ENDIF.
    IF lv_qid IS NOT INITIAL.
      PERFORM reconcile_sm35
        USING lt_scope ls_group-groupid lv_qid
              'Exact visible SM35 reconciliation'.
    ENDIF.
  ENDLOOP.
ENDFORM.

FORM refresh_sm35_state.
  DATA: lv_group TYPE apqi-groupid,
        lv_msg   TYPE string.

  CLEAR lv_group.
  PERFORM find_sm35_group_for_scope
    USING gt_exec_scope_0500 CHANGING lv_group.

  IF lv_group IS INITIAL.
    PERFORM sync_0500_q_db USING gt_exec_scope_0500.
    PERFORM display_0500_queue.
    PERFORM flush_0500_queue.
    RETURN.
  ENDIF.

  gv_last_sm35_group = lv_group.
  CLEAR gv_last_sm35_qid.
  PERFORM find_sm35_qid_for_scope
    USING gt_exec_scope_0500 gv_last_sm35_group
    CHANGING gv_last_sm35_qid.

  IF gv_last_sm35_qid IS INITIAL.
    DATA(lv_zm945_7596_1) = |{ gv_last_sm35_group }|.
    MESSAGE ID 'ZBDC' TYPE 'S' NUMBER '945'
      WITH lv_zm945_7596_1 INTO lv_msg.
    PERFORM sync_0500_q_db USING gt_exec_scope_0500.
  ELSE.
    PERFORM reconcile_sm35
      USING gt_exec_scope_0500 gv_last_sm35_group gv_last_sm35_qid
            'SM35 processed-session refresh'.
  ENDIF.

  PERFORM sync_0500_q_db USING gt_exec_scope_0500.
  PERFORM display_0500_queue.
  PERFORM sync_0500_progress_q.
  PERFORM flush_0500_queue.
ENDFORM.

*& /Explicit SM35 handoff + generic background incompatibility

*& The cockpit creates the real batch-input session but standard SM35 owns
*& the user's processing-mode choice. Make that handoff explicit and keep
*& the executor generic: no TCODE CASE, no business-object guess.

FORM show_sm35_handoff
  USING pv_group  TYPE apqi-groupid
        pv_queued TYPE i
        pv_total  TYPE i.

  DATA: lv_title TYPE c LENGTH 40,
        lv_txt1  TYPE c LENGTH 70,
        lv_txt2  TYPE c LENGTH 70,
        lv_txt3  TYPE c LENGTH 70,
        lv_txt4  TYPE c LENGTH 70.

  lv_title = 'SM35 session ready'.
  lv_txt1  = |Session { pv_group } created ({ pv_queued }/{ pv_total } group(s)).|.
  lv_txt2  = 'Choose SM35 Monitor to continue in standard SM35.'.
  lv_txt3  = 'Keep Extended log + Default Dynpro Size enabled.'.
  lv_txt4  = 'Background only if the recording is GUI/control-free.'.

  CALL FUNCTION 'POPUP_TO_INFORM'
    EXPORTING
      titel = lv_title
      txt1  = lv_txt1
      txt2  = lv_txt2
      txt3  = lv_txt3
      txt4  = lv_txt4.
ENDFORM.

*& Detect an exact SM35 Background-mode GUI/control requirement

*& "Background" is a standard SM35 mode, but not every recorded transaction
*& is background-capable. Some recordings require SAP GUI / Control
*& Framework. Detect that only from the exact QID protocol produced by SAP;
*& never hard-code a TCODE. This is diagnostic evidence, not a fallback to
*& CALL TRANSACTION and not an automatic replay in another mode.

FORM detect_bg_gui_requirement
  USING    pv_qid TYPE apqi-qid
  CHANGING cv_hit TYPE abap_bool
           cv_msg TYPE string.

  DATA: lt_log       TYPE ty_t_bdclm,
        ls_log       TYPE bdclm,
        lv_mode_n    TYPE abap_bool,
        lv_gui_error TYPE abap_bool,
        lv_text      TYPE string,
        lv_fmt       TYPE c LENGTH 255,
        lv_msgv1     TYPE string,
        lv_msgv2     TYPE string,
        lv_msgv3     TYPE string,
        lv_msgv4     TYPE string,
        lv_mpar_ok   TYPE abap_bool,
        lv_proc_mode TYPE c LENGTH 1,
        lv_mode_label TYPE char50.

  CLEAR: cv_hit, cv_msg, lv_mode_n, lv_gui_error.
  IF pv_qid IS INITIAL.
    RETURN.
  ENDIF.

  PERFORM get_sm35_log USING pv_qid CHANGING lt_log.
  PERFORM detect_sm35_mode_from_log
    USING    lt_log
    CHANGING lv_proc_mode lv_mode_label.
  IF lv_proc_mode = 'N'.
    lv_mode_n = abap_true.
  ENDIF.

  LOOP AT lt_log INTO ls_log.
    CLEAR: lv_text, lv_fmt, lv_msgv1, lv_msgv2, lv_msgv3, lv_msgv4,
           lv_mpar_ok.

    PERFORM decode_sm35_mpar
      USING    ls_log
      CHANGING lv_msgv1 lv_msgv2 lv_msgv3 lv_msgv4 lv_mpar_ok.
    IF lv_mpar_ok <> abap_true.
      lv_msgv1 = ls_log-mpar.
    ENDIF.

    IF ls_log-mid IS NOT INITIAL AND ls_log-mnr IS NOT INITIAL.
      CALL FUNCTION 'FORMAT_MESSAGE'
        EXPORTING
          id   = ls_log-mid
          lang = sy-langu
          no   = ls_log-mnr
          v1   = lv_msgv1
          v2   = lv_msgv2
          v3   = lv_msgv3
          v4   = lv_msgv4
        IMPORTING
          msg  = lv_fmt
        EXCEPTIONS
          OTHERS = 1.
    ENDIF.
    IF lv_fmt IS NOT INITIAL.
      lv_text = lv_fmt.
    ELSE.
      lv_text = |{ ls_log-mid } { ls_log-mnr } { lv_msgv1 } { lv_msgv2 } { lv_msgv3 } { lv_msgv4 }|.
    ENDIF.
    CONDENSE lv_text.

 "Compatibility fallback only when 00/300 MPAR could not be decoded.
    IF lv_proc_mode IS INITIAL AND
       ls_log-mid = '00' AND ls_log-mnr = '300' AND
       ( lv_text CS ' mode N ' OR lv_text CP '*mode N*' ).
      lv_mode_n = abap_true.
    ENDIF.

 "Use SAP's exact technical protocol, not a TCODE name. DC messages are
 "Control Framework messages; text fallback covers installations where
 "message identity is unavailable/localized differently in the reader.
    IF ( ls_log-mid = 'DC' AND
         ( ls_log-mnr = '001' OR ls_log-mnr = '006' ) ) OR
       lv_text CS 'Control Framework' OR
       lv_text CS 'GUI cannot be reached'.
      lv_gui_error = abap_true.
    ENDIF.
  ENDLOOP.

  IF lv_mode_n = abap_true AND lv_gui_error = abap_true.
    cv_hit = abap_true.
    cv_msg =
      'Background mode is not compatible with this exact recording: SAP requires GUI/Control Framework. Retry the same BISM scope with Display errors only or Process/foreground. Keep Extended log + Default Dynpro Size enabled.' .
  ENDIF.
ENDFORM.

FORM open_sm35_0500.
  DATA: lv_sm35_group    TYPE apqi-groupid,
        lv_sm35_qid      TYPE apqi-qid,
        lv_qstate        TYPE apqi-qstate,
        lv_msg           TYPE string,
        lv_new_mode      TYPE sy-index,
        lv_mode_rc       TYPE sy-subrc,
        lv_foreign_rc    TYPE sy-subrc.

 "SM35 Monitor is MONITOR/LAUNCH ONLY. It must never submit
 "RSBDCBTC or process the queue behind the user's back. The exact QID is
 "already durably bound when BDC_OPEN_GROUP succeeds. Keep 0500 alive like
 "/oSM35, let the user process the real session in standard SM35, and let
 "the silent exact-QID timer reconcile only after SAP reaches a terminal
 "state. This removes the /706 race that could process a GUI-dependent
 "recording in background mode N, mark the session Incorrect, disable SM35 Monitor and
 "make screen 0500 flicker every second.
  CLEAR: lv_sm35_group, lv_sm35_qid, lv_qstate, lv_msg.

  PERFORM find_sm35_group_for_scope
    USING gt_exec_scope_0500 CHANGING lv_sm35_group.

  IF lv_sm35_group IS NOT INITIAL.
    PERFORM find_sm35_qid_for_scope
      USING gt_exec_scope_0500 lv_sm35_group
      CHANGING lv_sm35_qid.
  ENDIF.

  IF lv_sm35_group IS INITIAL OR lv_sm35_qid IS INITIAL.
    MESSAGE ID 'ZBDC' TYPE 'S' NUMBER '946' INTO lv_msg.
    PERFORM userize_ui_message USING lv_msg CHANGING gv_ui_message.
    MESSAGE gv_ui_message TYPE 'S' DISPLAY LIKE 'E'.
    RETURN.
  ENDIF.

  SELECT SINGLE qstate
    FROM apqi
    INTO @lv_qstate
    WHERE mandant = @sy-mandt
      AND qid     = @lv_sm35_qid
      AND datatyp = 'BDC'.

 "A previous compatibility/background job must never own this manual SM35
 "monitor flow. Clear only the volatile job monitor identity; the durable
 "GROUP/QID binding and SAP queue are untouched.
  CLEAR: gv_last_sm35_jobname, gv_last_sm35_jobcount, gv_sm35_job_finished.

  gv_exec_run_active = abap_true.
  gv_exec_mon_kind   = gc_mon_sm35.
  gv_sm35_mon_group  = lv_sm35_group.
  gv_sm35_mon_qid    = lv_sm35_qid.
  IF gt_sm35_mon_process IS INITIAL.
    gt_sm35_mon_process[] = gt_exec_scope_0500[].
  ENDIF.

  IF lv_qstate = 'F' OR lv_qstate = 'E'.
    gv_exec_run_phase = |SM35 terminal session { lv_sm35_group }; exact QID will reconcile automatically|.
  ELSEIF lv_qstate = 'R' OR lv_qstate = 'S' OR lv_qstate = 'C'.
    gv_exec_run_phase = |SM35 session { lv_sm35_group } is processing; exact QID monitored silently|.
  ELSE.
    gv_exec_run_phase = |SM35 session { lv_sm35_group } queued; process it in standard SM35|.
  ENDIF.

  DATA(lv_zm947_7802_1) = |{ lv_sm35_group }|.
  MESSAGE ID 'ZBDC' TYPE 'S' NUMBER '947'
    WITH lv_zm947_7802_1 INTO lv_msg.
  gv_exec_run_phase = |SM35 Monitor opened { lv_sm35_group }; waiting for standard SM35 processing|.
  gv_last_sm35_action = lv_msg.
  PERFORM stamp_sm35_action USING gt_exec_scope_0500 lv_msg.
  COMMIT WORK AND WAIT.

 "robust /o-style SM35 launcher. Keep screen 0500 alive. The child mode
 "must persist while SM35 transfers from the overview/process dialog into
 "the selected processing mode; otherwise DEL_ON_EOT can terminate the
 "child mode before the batch-input processor takes ownership. TH_CREATE_MODE is
 "the preferred path because it performs the normal transaction authority
 "check. Some SAP GUI/control-event contexts can return INTERNAL_ERROR even
 "though a separate frontend mode can still be created; in that case only,
 "retry with TH_CREATE_FOREIGN_MODE for the same logged-on user/client.
 "MAX_SESSIONS and NO_AUTHORITY remain fail-closed and are never bypassed.
  CLEAR: lv_new_mode, lv_mode_rc, lv_foreign_rc.

  CALL FUNCTION 'TH_CREATE_MODE'
    EXPORTING
      transaktion    = gc_tcode_sm35
      "Keep the /o-style SM35 child mode alive across SM35's own
      "end-of-transaction handoff into foreground/error/background
      "processing. DEL_ON_EOT=1 can close the child mode exactly when the
      "user presses Process, leaving the BDC session queued as NEW.
      "The original 0500 mode remains alive and monitors the exact QID;
      "the user may close the SM35 child mode after processing finishes.
      del_on_eot     = 0
      process_dark   = space
    IMPORTING
      mode           = lv_new_mode
    EXCEPTIONS
      max_sessions   = 1
      internal_error = 2
      no_authority   = 3
      OTHERS         = 4.
  lv_mode_rc = sy-subrc.

  IF lv_mode_rc = 2 OR lv_mode_rc = 4.
 "Second, still-separate-mode path. This is NOT the CT executor and does
 "not process the BDC queue; it only opens standard SM35 in another mode.
    CALL FUNCTION 'TH_CREATE_FOREIGN_MODE'
      EXPORTING
        client           = sy-mandt
        user             = sy-uname
        tcode            = gc_tcode_sm35
        return_error     = 1
        create_exclusive = 0
      EXCEPTIONS
        user_not_found   = 1
        cant_create_mode = 2
        OTHERS           = 3.
    lv_foreign_rc = sy-subrc.
  ENDIF.

  IF lv_mode_rc = 0 OR
     ( ( lv_mode_rc = 2 OR lv_mode_rc = 4 ) AND lv_foreign_rc = 0 ).
 "The handoff is shown only in the popup created when the BISM session is
 "queued; do not duplicate a normal success message in the status bar.
    gv_last_sm35_action = lv_msg.
  ELSEIF lv_mode_rc = 1.
    DATA(lv_zm948_7862_1) = |{ lv_sm35_group }|.
    MESSAGE ID 'ZBDC' TYPE 'S' NUMBER '948'
      WITH lv_zm948_7862_1 INTO lv_msg.
    gv_last_sm35_action = lv_msg.
    PERFORM userize_ui_message USING lv_msg CHANGING gv_ui_message.
    MESSAGE gv_ui_message TYPE 'S' DISPLAY LIKE 'W'.
  ELSEIF lv_mode_rc = 3.
    DATA(lv_zm949_7866_1) = |{ lv_sm35_group }|.
    MESSAGE ID 'ZBDC' TYPE 'S' NUMBER '949'
      WITH lv_zm949_7866_1 INTO lv_msg.
    gv_last_sm35_action = lv_msg.
    PERFORM userize_ui_message USING lv_msg CHANGING gv_ui_message.
    MESSAGE gv_ui_message TYPE 'S' DISPLAY LIKE 'E'.
  ELSE.
    DATA(lv_zm950_7870_1) = |{ lv_mode_rc }|.
    DATA(lv_zm950_7870_2) = |{ lv_foreign_rc }|.
    DATA(lv_zm950_7870_3) = |{ lv_sm35_group }|.
    MESSAGE ID 'ZBDC' TYPE 'S' NUMBER '950'
      WITH lv_zm950_7870_1 lv_zm950_7870_2 lv_zm950_7870_3
      INTO lv_msg.
    gv_last_sm35_action = lv_msg.
    PERFORM userize_ui_message USING lv_msg CHANGING gv_ui_message.
    MESSAGE gv_ui_message TYPE 'S' DISPLAY LIKE 'W'.
  ENDIF.
 "arm/re-arm the 0500 timer only after the /o-style launcher has
 "returned control to the original mode. Arming it before TH_CREATE_MODE
 "could leave the frontend timer event orphaned during the mode switch,
 "which is why terminal SM35 state sometimes appeared only after Refresh.
  IF gv_exec_run_active = abap_true AND gv_exec_mon_kind = gc_mon_sm35.
    PERFORM start_0500_timer.
  ENDIF.
ENDFORM.

FORM has_0500_issue CHANGING cv_issue TYPE abap_bool.
  CLEAR cv_issue.
  LOOP AT gt_exec_disp ASSIGNING FIELD-SYMBOL(<ls_issue>).
    IF <ls_issue>-run_status = gc_st_error OR
       <ls_issue>-run_status = gc_st_warning OR
       <ls_issue>-run_status = gc_st_skipped OR
       <ls_issue>-run_status = gc_st_partial OR
       <ls_issue>-run_status = 'BLOCKED_ONBOARDING'.
      cv_issue = abap_true.
      EXIT.
    ENDIF.
  ENDLOOP.
ENDFORM.

FORM pick_0500_issue.
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
         ls_exec-run_status = gc_st_skipped OR
         ls_exec-run_status = gc_st_partial OR
         ls_exec-run_status = 'BLOCKED_ONBOARDING' ).
      lv_found = abap_true.
    ENDIF.
  ENDIF.

  IF lv_found IS INITIAL.
    LOOP AT gt_exec_disp INTO ls_exec
      WHERE run_status = gc_st_error OR run_status = gc_st_warning
         OR run_status = gc_st_skipped OR run_status = gc_st_partial
         OR run_status = 'BLOCKED_ONBOARDING'.
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

FORM after_0500_execute.
  DATA: lv_issue TYPE abap_bool,
        lv_done  TYPE i,
        lv_total TYPE i.

  PERFORM count_0500_q CHANGING lv_done lv_total.
  PERFORM has_0500_issue CHANGING lv_issue.

  IF lv_issue = abap_true.
    MESSAGE s529(zbdc) DISPLAY LIKE 'W'.
  ELSEIF lv_total > 0 AND lv_done >= lv_total.
    MESSAGE s530(zbdc).
  ELSE.
    MESSAGE s531(zbdc) DISPLAY LIKE 'W'.
  ENDIF.
ENDFORM.

FORM capture_retry_scope
  CHANGING cv_ok      TYPE abap_bool
           cv_message TYPE string.

  DATA: lt_rows       TYPE lvc_t_row,
        ls_row        TYPE lvc_s_row,
        ls_exec       TYPE ty_exec_disp,
        ls_key        TYPE ty_engine_group_key,
        lv_session    TYPE zbdc_staging_bup-session_id,
        lv_first      TYPE abap_bool VALUE abap_true,
        lv_count      TYPE i.

  CLEAR: cv_ok, cv_message, txtp_result_session, txtp_po_key,
         txtp_sap_object_id, txtp_result_msg, g_edit_index.
  REFRESH gt_0560_groups.

  IF go_grid_0500 IS NOT BOUND.
    cv_message = 'Retry correction is unavailable because the execution queue is not active.'.
    RETURN.
  ENDIF.

  TRY.
      CALL METHOD go_grid_0500->get_selected_rows
        IMPORTING et_index_rows = lt_rows.
    CATCH cx_root.
      CLEAR lt_rows.
  ENDTRY.

  IF lt_rows IS INITIAL.
    cv_message = 'Select one or more failed groups in the queue, then choose Retry.'.
    RETURN.
  ENDIF.

  LOOP AT lt_rows INTO ls_row.
    CLEAR ls_exec.
    READ TABLE gt_exec_disp INTO ls_exec INDEX ls_row-index.
    IF sy-subrc <> 0.
      CONTINUE.
    ENDIF.

    IF ls_exec-run_status <> gc_st_error.
      cv_message = |Retry is available only for ERROR groups. { ls_exec-group_key } is { ls_exec-run_status }.|.
      REFRESH gt_0560_groups.
      RETURN.
    ENDIF.

    IF lv_session IS INITIAL.
      lv_session = ls_exec-session_id.
    ELSEIF lv_session <> ls_exec-session_id.
      cv_message = 'Select retry groups from one execution session only.'.
      REFRESH gt_0560_groups.
      RETURN.
    ENDIF.

    CLEAR ls_key.
    ls_key-session_id = ls_exec-session_id.
    ls_key-record_key = ls_exec-group_key.
    IF ls_key-record_key IS INITIAL.
      cv_message = 'Retry correction requires a persisted business-group key.'.
      REFRESH gt_0560_groups.
      RETURN.
    ENDIF.

    READ TABLE gt_0560_groups TRANSPORTING NO FIELDS
      WITH KEY session_id = ls_key-session_id record_key = ls_key-record_key.
    IF sy-subrc <> 0.
      APPEND ls_key TO gt_0560_groups.
    ENDIF.

    IF lv_first = abap_true.
      txtp_result_session = ls_exec-session_id.
      txtp_po_key         = ls_exec-group_key.
      txtp_sap_object_id  = ls_exec-sap_object_id.
      txtp_result_msg     = ls_exec-message.
      READ TABLE gt_staging_alv TRANSPORTING NO FIELDS
        WITH KEY session_id = ls_exec-session_id record_key = ls_exec-group_key.
      IF sy-subrc = 0.
        g_edit_index = sy-tabix.
      ENDIF.
      lv_first = abap_false.
    ENDIF.
  ENDLOOP.

  lv_count = lines( gt_0560_groups ).
  IF lv_count <= 0.
    cv_message = 'No eligible failed group is selected for Retry.'.
    RETURN.
  ENDIF.

  gv_0560_group_count = lv_count.
  cv_ok = abap_true.
  cv_message = |Retry correction scope contains { lv_count } failed group(s).|.
ENDFORM.

FORM open_0500_retry.
  DATA: lv_ok  TYPE abap_bool,
        lv_msg TYPE string.

  PERFORM reset_0560.
  PERFORM capture_retry_scope CHANGING lv_ok lv_msg.
  IF lv_ok <> abap_true.
    PERFORM userize_ui_message USING lv_msg CHANGING gv_ui_message.
    MESSAGE gv_ui_message TYPE 'S' DISPLAY LIKE 'E'.
    RETURN.
  ENDIF.

  PERFORM userize_ui_message USING lv_msg CHANGING gv_ui_message.
  MESSAGE gv_ui_message TYPE 'S'.
  CALL SCREEN 0560 STARTING AT 10 5 ENDING AT 88 18.
ENDFORM.

FORM scope_from_0500_sel
  CHANGING cv_ok      TYPE abap_bool
           cv_message TYPE string.

  DATA: lt_rows     TYPE lvc_t_row,
        ls_row      TYPE lvc_s_row,
        ls_exec     TYPE ty_exec_disp,
        lt_db       TYPE STANDARD TABLE OF zbdc_staging_bup,
        ls_db       TYPE zbdc_staging_bup,
        ls_alv      TYPE ty_staging_alv,
        lt_scope    TYPE ty_t_staging_alv,
        lt_keys     TYPE ty_t_engine_group_key,
        lv_all_ready TYPE abap_bool,
        lv_groups   TYPE i.

  cv_ok = abap_true.
  CLEAR cv_message.

  IF go_grid_0500 IS NOT BOUND.
    RETURN.
  ENDIF.

  TRY.
      CALL METHOD go_grid_0500->get_selected_rows
        IMPORTING et_index_rows = lt_rows.
    CATCH cx_root.
      CLEAR lt_rows.
  ENDTRY.

 "No visible selection means keep the already frozen execution scope.
  IF lt_rows IS INITIAL.
    RETURN.
  ENDIF.

  LOOP AT lt_rows INTO ls_row.
    CLEAR ls_exec.
    READ TABLE gt_exec_disp INTO ls_exec INDEX ls_row-index.
    IF sy-subrc <> 0.
      CONTINUE.
    ENDIF.
    IF ls_exec-run_status <> gc_st_ready.
      cv_ok = abap_false.
      cv_message = |Select READY groups only before choosing CT/BISM. { ls_exec-group_key } is { ls_exec-run_status }.|.
      RETURN.
    ENDIF.

    REFRESH lt_db.
    SELECT * FROM zbdc_staging_bup INTO TABLE @lt_db
      WHERE session_id = @ls_exec-session_id
        AND record_key = @ls_exec-group_key.
    IF lt_db IS INITIAL.
      cv_ok = abap_false.
      cv_message = |Selected READY group { ls_exec-group_key } is missing from staging.|.
      RETURN.
    ENDIF.

    lv_all_ready = abap_true.
    LOOP AT lt_db INTO ls_db.
      IF ls_db-status <> gc_st_ready.
        lv_all_ready = abap_false.
        EXIT.
      ENDIF.
    ENDLOOP.
    IF lv_all_ready <> abap_true.
      cv_ok = abap_false.
      cv_message = |Selected group { ls_exec-group_key } is not fully READY in persisted staging.|.
      RETURN.
    ENDIF.

    LOOP AT lt_db INTO ls_db.
      CLEAR ls_alv.
      MOVE-CORRESPONDING ls_db TO ls_alv.
      APPEND ls_alv TO lt_scope.
    ENDLOOP.
  ENDLOOP.

  IF lt_scope IS INITIAL.
    RETURN.
  ENDIF.

  PERFORM build_engine_keys USING lt_scope CHANGING lt_keys.
  lv_groups = lines( lt_keys ).
  IF lv_groups <= 0.
    cv_ok = abap_false.
    cv_message = 'The selected READY rows could not be resolved to an execution scope.'.
    RETURN.
  ENDIF.

  gt_exec_scope_0500 = lt_scope.
  gv_exec_scope_ready = abap_true.
  gv_exec_scope_0500 = 'SELECTED'.
  gv_exec_scope_text = 'READY group(s) selected in Screen 0500'.
  gv_exec_run_total = lv_groups.
  txtgv_exec_total = lv_groups.
  PERFORM seed_0500_qstate
    USING gt_exec_scope_0500 gc_st_ready
          'Ready in exact Screen 0500 selection'.
ENDFORM.

*& Opportunistic exact-QID terminal reconcile on any 0500 action

FORM sync_term_sm35
  CHANGING cv_synced TYPE abap_bool.

  DATA: lv_qstate TYPE apqi-qstate,
        lv_found  TYPE abap_bool,
        lt_log    TYPE ty_t_bdclm,
        ls_log    TYPE bdclm,
        lv_term   TYPE abap_bool,
        lv_msg    TYPE string,
        lv_closed TYPE abap_bool.

  CLEAR: cv_synced, lv_qstate, lv_found, lv_term, lv_closed.

  IF gv_exec_run_active <> abap_true OR
     gv_exec_mon_kind <> gc_mon_sm35 OR
     gv_sm35_mon_qid IS INITIAL OR
     gt_sm35_mon_process IS INITIAL.
    RETURN.
  ENDIF.

  SELECT SINGLE qstate
    FROM apqi
    INTO @lv_qstate
    WHERE mandant = @sy-mandt
      AND qid     = @gv_sm35_mon_qid
      AND datatyp = 'BDC'.
  IF sy-subrc = 0.
    lv_found = abap_true.
    IF lv_qstate = 'F' OR lv_qstate = 'E'.
      lv_term = abap_true.
    ENDIF.
  ENDIF.

  IF lv_found <> abap_true.
    REFRESH lt_log.
    PERFORM get_sm35_log
      USING    gv_sm35_mon_qid
      CHANGING lt_log.
    LOOP AT lt_log INTO ls_log.
      IF ls_log-mart = 'E' OR
         ls_log-mart = 'A' OR
         ls_log-mart = 'X' OR
         ( ls_log-mart = 'S' AND
           ls_log-mid  = '00' AND
           ls_log-mnr  = '382' ).
        lv_term = abap_true.
        EXIT.
      ENDIF.
    ENDLOOP.
  ENDIF.

  IF lv_term <> abap_true.
    RETURN.
  ENDIF.

  DATA(lv_zm951_8243_1) = |{ gv_sm35_mon_qid }|.
  MESSAGE ID 'ZBDC' TYPE 'S' NUMBER '951'
    WITH lv_zm951_8243_1 INTO lv_msg.
  PERFORM reconcile_sm35
    USING gt_sm35_mon_process gv_sm35_mon_group
          gv_sm35_mon_qid lv_msg.
  PERFORM sync_0500_q_db USING gt_exec_scope_0500.
  PERFORM display_0500_queue.
  PERFORM close_term_sm35_mon CHANGING lv_closed.

  IF lv_closed = abap_true.
    cv_synced = abap_true.
  ENDIF.
ENDFORM.

*& Close stale SM35 monitor state after terminal queue evidence

FORM close_term_sm35_mon
  CHANGING cv_closed TYPE abap_bool.

  DATA: lv_done  TYPE i,
        lv_total TYPE i,
        lv_issue TYPE abap_bool.

  CLEAR cv_closed.

  IF gv_exec_run_active <> abap_true OR
     gv_exec_mon_kind <> gc_mon_sm35.
    RETURN.
  ENDIF.

  IF gt_exec_disp IS INITIAL.
    RETURN.
  ENDIF.

 "Only persisted/painted terminal queue states may close the volatile
 "monitor. This form never infers SUCCESS from APQI by itself and never
 "executes or retries the SM35 session.
  PERFORM count_0500_q CHANGING lv_done lv_total.
  IF lv_total <= 0 OR lv_done < lv_total.
    RETURN.
  ENDIF.

  PERFORM has_0500_issue CHANGING lv_issue.

  gv_exec_run_done   = lv_done.
  g_exec_curr         = lv_done.
  gv_exec_run_active = abap_false.
  CLEAR: gv_exec_mon_kind,
         gv_exec_stop_req,
         g_stop_flag,
         gv_sm35_job_finished.

  IF lv_issue = abap_true.
    gv_exec_run_phase = 'SM35 terminal state reconciled with issue(s)'.
  ELSE.
    gv_exec_run_phase = 'SM35 terminal state reconciled successfully'.
  ENDIF.

  PERFORM stop_0500_timer.
  PERFORM refresh_0500_tools.
  cv_closed = abap_true.
ENDFORM.

*& 0500 PBO reconciliation after returning from SM35/RSBDCBTC

FORM 0500_pbo_sync.
  DATA lv_z714_closed TYPE abap_bool.
 "while the one-second exact-QID monitor is active, PAI owns the
 "APQI/TemSe probe and reconciliation. PBO only refreshes persisted display
 "state so the same queue is not reconciled twice on every timer roundtrip.
  IF gv_exec_run_active = abap_true AND gv_exec_mon_kind = gc_mon_sm35.
    PERFORM sync_0500_q_db USING gt_exec_scope_0500.
 "DB sync can already paint the whole exact queue terminal while
 "the one-second monitor flag is still TRUE. Close that stale volatile
 "state in the same PBO so Back/Exit and toolbar availability immediately
 "match the persisted SUCCESS/ERROR/WARNING rows.
    PERFORM close_term_sm35_mon CHANGING lv_z714_closed.
    RETURN.
  ENDIF.

 "BISM remains independent from CALL TRANSACTION options. PBO may
 "reconcile only the exact durable SM35 binding for the current scope; it
 "never reuses another session or infers success from job completion.
  IF p_bdc_mode <> gc_mode_batch AND
     gv_exec_run_engine <> 'B' AND
     gv_exec_mon_kind <> gc_mon_sm35.
    RETURN.
  ENDIF.
  IF gt_exec_scope_0500 IS INITIAL.
    RETURN.
  ENDIF.

  CLEAR gv_last_sm35_group.
  PERFORM find_sm35_group_for_scope
    USING gt_exec_scope_0500 CHANGING gv_last_sm35_group.

  IF gv_exec_mon_kind = gc_mon_sm35 OR
     gv_last_sm35_group IS NOT INITIAL OR
     gv_last_sm35_jobname IS NOT INITIAL OR
     gv_sm35_job_finished = abap_true.
    IF gv_last_sm35_group IS INITIAL.
      PERFORM sync_0500_q_db USING gt_exec_scope_0500.
      RETURN.
    ENDIF.
    CLEAR gv_last_sm35_qid.
    PERFORM find_sm35_qid_for_scope
      USING gt_exec_scope_0500 gv_last_sm35_group
      CHANGING gv_last_sm35_qid.
    IF gv_last_sm35_qid IS NOT INITIAL.
      PERFORM reconcile_sm35
        USING gt_exec_scope_0500 gv_last_sm35_group gv_last_sm35_qid
              'Explicit SM35 monitor/refresh reconciliation'.
    ELSE.
      PERFORM sync_0500_q_db USING gt_exec_scope_0500.
    ENDIF.
  ELSE.
    PERFORM sync_0500_q_db USING gt_exec_scope_0500.
  ENDIF.
ENDFORM.

*& Legacy-compatible safe entry points
*& These signatures are retained so existing dynamic callers and transports remain
*& compatible. Unsafe runtime mutation is deliberately fail-closed.
