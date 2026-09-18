
*& Include ZBDC_MPE_M4_DASH_BUP
*& Purpose Read-oriented dashboard, ALV and result projections
*& SAP Object is a post-SUCCESS projection only
*& generic detail-screen BDC hand-off sentinel

FORM GET_RECENT_SESSIONS.
  DATA: lt_raw TYPE STANDARD TABLE OF ty_session_disp,
        ls_raw TYPE ty_session_disp,
        ls_row TYPE ty_session_disp.
  FIELD-SYMBOLS <ls_gt_session> TYPE ty_session_disp.

  REFRESH gt_sessions.

 "the 0100 dashboard owns one canonical real-session set assembled
 "from SESSION + STAGING + RESULT. Reuse that exact snapshot here instead of
 "running a second, slightly different session-discovery algorithm.
  LOOP AT gt_kpi_sid_0100 INTO DATA(ls_kpi_sid_0100).
    CLEAR ls_row.
    ls_row-session_id = ls_kpi_sid_0100-session_id.
    ls_row-msg_type   = 'I'.
    ls_row-message    = 'Persisted execution session'.
    APPEND ls_row TO gt_sessions.
  ENDLOOP.

  IF gt_sessions IS INITIAL.
    RETURN.
  ENDIF.

 "Result evidence supplies the newest persisted timestamp for result-only
 "or legacy sessions. ZBDC_SESSION_BUP-START_TIME remains the preferred
 "fallback later in STATUS_0100 when no result timestamp exists.
  SELECT session_id, created_at, msg_type, sap_object_id, message
    FROM zbdc_result_bup
    ORDER BY session_id ASCENDING, created_at DESCENDING
    INTO CORRESPONDING FIELDS OF TABLE @lt_raw.

  SORT gt_sessions BY session_id.
  LOOP AT lt_raw INTO ls_raw.
    IF ls_raw-session_id IS INITIAL OR ls_raw-session_id CP 'GMAIL_REQ_*'.
      CONTINUE.
    ENDIF.

    READ TABLE gt_sessions ASSIGNING <ls_gt_session>
      WITH KEY session_id = ls_raw-session_id BINARY SEARCH.
    IF sy-subrc <> 0.
      CONTINUE.
    ENDIF.

 "lt_raw is newest-first inside each session, so set evidence only once.
    IF <ls_gt_session>-created_at IS INITIAL.
      <ls_gt_session>-created_at    = ls_raw-created_at.
      <ls_gt_session>-msg_type      = ls_raw-msg_type.
      <ls_gt_session>-sap_object_id = ls_raw-sap_object_id.
      <ls_gt_session>-message       = ls_raw-message.
    ENDIF.
  ENDLOOP.
ENDFORM.

FORM prepare_alv_0400.
  DATA ls_alv TYPE ty_staging_alv.

 "Read-only projection. PBO/refresh/display must never validate, normalize,
 "change lifecycle status, write structured errors, or persist staging.
  REFRESH gt_staging_alv.
  LOOP AT gt_staging INTO DATA(ls_stg).
    CLEAR ls_alv.
    MOVE-CORRESPONDING ls_stg TO ls_alv.
    APPEND ls_alv TO gt_staging_alv.
  ENDLOOP.
ENDFORM.

*& Resolve one session's persisted inbound source from ZBDC_FILE_LG_BUP.
*& Dashboard projection never parses result-message text, current preview
*& memory or session-ID prefixes as provenance.

FORM get_session_source
  USING    iv_session_id TYPE zbdc_file_lg_bup-session_id
  CHANGING cv_source     TYPE char20
           cv_ok         TYPE abap_bool
           cv_message    TYPE string.

  DATA: lt_raw   TYPE STANDARD TABLE OF zbdc_file_lg_bup-source,
        lt_canon TYPE SORTED TABLE OF char20 WITH UNIQUE KEY table_line,
        lv_raw   TYPE string,
        lv_canon TYPE char20.

  CLEAR: cv_source, cv_ok, cv_message.
  cv_source = 'UNKNOWN'.
  IF iv_session_id IS INITIAL.
    cv_message = 'Session ID is blank; persisted source cannot be resolved.'.
    RETURN.
  ENDIF.

  SELECT DISTINCT source
    FROM zbdc_file_lg_bup
    INTO TABLE @lt_raw
    WHERE session_id = @iv_session_id
      AND source     <> @space.

  LOOP AT lt_raw INTO DATA(lv_db_source).
    lv_raw = lv_db_source.
    TRANSLATE lv_raw TO UPPER CASE.
    CONDENSE lv_raw NO-GAPS.
    CLEAR lv_canon.

    CASE lv_raw.
      WHEN 'LOCAL' OR 'LOCAL_FILE'.
        lv_canon = 'LOCAL'.
      WHEN 'GDRIVE' OR 'GOOGLE_DRIVE' OR 'GOOGLEDRIVE'.
        lv_canon = 'GDRIVE'.
      WHEN 'GMAIL' OR 'GMAIL_FORM' OR 'GMAIL_DYNAMIC_FORM'
        OR 'EMAIL' OR 'MAILBOX'.
        lv_canon = 'GMAIL'.
      WHEN 'REST' OR 'REST_API' OR 'WEBHOOK'.
        lv_canon = 'REST'.
      WHEN OTHERS.
 "Unknown persisted provenance is not reclassified heuristically.
        CONTINUE.
    ENDCASE.

    INSERT lv_canon INTO TABLE lt_canon.
  ENDLOOP.

  IF lines( lt_canon ) = 1.
    READ TABLE lt_canon INTO cv_source INDEX 1.
    cv_ok = abap_true.
  ELSEIF lt_canon IS INITIAL.
    cv_message = |Session { iv_session_id } has no recognized structured inbound-source evidence.|.
  ELSE.
    cv_message = |Session { iv_session_id } has conflicting inbound-source evidence.|.
  ENDIF.
ENDFORM.

FORM RESET_0300_ALV.
 "KHONG free container/grid cua 0301 nua.
 "Ly do: FREE + CREATE OBJECT lai trong CUNG 1 vong PAI->PBO (khong doi dynpro)
 "khien SAP GUI Control Framework khong repaint container ngay - grid trong den
 "khi user chuyen tab sang 0302 roi quay lai 0301 (buoc do moi force ve lai).
 "MODULE status_0301 OUTPUT da co san nhanh xu ly dung khi container con song:
 " IF go_grid_0301 IS BOUND. go_grid_0301->refresh(...). go_grid_0301->display( ). ENDIF.
 "Nen chi can giu container/grid 0301 song va goi refresh() la du, khong can pha di tao lai.
  IF GO_GRID_0302 IS BOUND.
    FREE GO_GRID_0302.
  ENDIF.
  IF GO_CONTAINER_0302 IS BOUND.
    FREE GO_CONTAINER_0302.
  ENDIF.
  CLEAR: GO_GRID_0302, GO_CONTAINER_0302.
ENDFORM.

FORM reset_0300_all_alv.
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

*&---------------------------------------------------------------------*
*& 0400 immutable context owner
*&---------------------------------------------------------------------*
FORM clear_0400_context.
  CLEAR: gv_0400_context_sid,
         gv_0400_context_batch,
         gv_0400_context_batch_scope,
         gv_0400_context_locked.
ENDFORM.

FORM freeze_0400_context
  USING iv_session_id TYPE any.

  DATA: lv_sid   TYPE zbdc_staging_bup-session_id,
        lv_batch TYPE zbdc_staging_bup-session_id.

  lv_sid = iv_session_id.
  CONDENSE lv_sid.
  IF lv_sid IS INITIAL.
    lv_sid = txtp_session_id.
    CONDENSE lv_sid.
  ENDIF.
  IF lv_sid IS INITIAL.
    lv_sid = txtp_sess.
    CONDENSE lv_sid.
  ENDIF.
  IF lv_sid IS INITIAL.
    READ TABLE gt_staging INTO DATA(ls_ctx_seed) INDEX 1.
    IF sy-subrc = 0.
      lv_sid = ls_ctx_seed-session_id.
      CONDENSE lv_sid.
    ENDIF.
  ENDIF.
  IF lv_sid IS INITIAL.
    RETURN.
  ENDIF.

  gv_0400_context_sid    = lv_sid.
  gv_0400_context_locked = abap_true.

  CLEAR: gv_0400_context_batch,
         gv_0400_context_batch_scope.

  IF gv_0400_batch_scope = abap_true
     AND gv_current_batch_prefix IS NOT INITIAL
     AND lines( gt_current_sessions ) > 1.
    gv_0400_context_batch_scope = abap_true.
    gv_0400_context_batch       = gv_current_batch_prefix.
  ELSE.
    PERFORM batch_prefix_from_sid
      USING    lv_sid
      CHANGING lv_batch.
    gv_0400_context_batch = lv_batch.
  ENDIF.

  txtp_session_id = gv_0400_context_sid.
  txtp_sess       = gv_0400_context_sid.
ENDFORM.

FORM repair_0400_context
  CHANGING cv_ok      TYPE abap_bool
           cv_message TYPE string.

  DATA: lv_sid         TYPE zbdc_staging_bup-session_id,
        lv_batch       TYPE zbdc_staging_bup-session_id,
        lv_row_batch   TYPE zbdc_staging_bup-session_id,
        lv_count       TYPE i,
        lv_stale       TYPE abap_bool,
        lv_has_sid     TYPE abap_bool,
        lv_tcode       TYPE zbdc_prof_bup-tcode,
        lv_profile     TYPE zbdc_prof_bup-profile_name,
        lv_ver         TYPE zbdc_prof_bup-profile_ver,
        lv_found       TYPE abap_bool.

  CLEAR: cv_ok, cv_message, lv_count, lv_stale, lv_has_sid.

  IF gv_0400_context_locked <> abap_true
     OR gv_0400_context_sid IS INITIAL.
    PERFORM freeze_0400_context USING txtp_session_id.
  ENDIF.

  lv_sid = gv_0400_context_sid.
  CONDENSE lv_sid.
  IF lv_sid IS INITIAL.
    cv_message = 'Screen 0400 has no frozen Session ID context.'.
    RETURN.
  ENDIF.

  txtp_session_id = lv_sid.
  txtp_sess       = lv_sid.

  READ TABLE gt_staging
    WITH KEY session_id = lv_sid
    TRANSPORTING NO FIELDS.
  IF sy-subrc = 0.
    lv_has_sid = abap_true.
  ENDIF.

  IF gt_staging IS INITIAL OR lv_has_sid <> abap_true.
    lv_stale = abap_true.
  ELSEIF gv_0400_context_batch_scope = abap_true.
    lv_batch = gv_0400_context_batch.
    IF lv_batch IS INITIAL.
      lv_stale = abap_true.
    ELSE.
      LOOP AT gt_staging INTO DATA(ls_ctx_row).
        CLEAR lv_row_batch.
        PERFORM batch_prefix_from_sid
          USING    ls_ctx_row-session_id
          CHANGING lv_row_batch.
        IF lv_row_batch <> lv_batch.
          lv_stale = abap_true.
          EXIT.
        ENDIF.
      ENDLOOP.
    ENDIF.
  ELSE.
    LOOP AT gt_staging INTO DATA(ls_exact_row).
      IF ls_exact_row-session_id <> lv_sid.
        lv_stale = abap_true.
        EXIT.
      ENDIF.
    ENDLOOP.
  ENDIF.

  IF lv_stale = abap_true.
    REFRESH: gt_staging, gt_staging_alv, gt_exec_disp,
             gt_current_sessions.

    IF gv_0400_context_batch_scope = abap_true
       AND gv_0400_context_batch IS NOT INITIAL.
      PERFORM load_staging_by_batch
        USING    gv_0400_context_batch
        CHANGING lv_count.
    ELSE.
      PERFORM load_staging_by_session
        USING    lv_sid
        CHANGING lv_count.
    ENDIF.

    IF lv_count <= 0 OR gt_staging IS INITIAL.
      cv_message = |Frozen Session { lv_sid } could not be reloaded from staging.|.
      RETURN.
    ENDIF.
  ENDIF.

  REFRESH gt_current_sessions.
  LOOP AT gt_staging INTO DATA(ls_loaded_ctx).
    IF ls_loaded_ctx-session_id IS INITIAL.
      CONTINUE.
    ENDIF.
    READ TABLE gt_current_sessions
      WITH KEY table_line = ls_loaded_ctx-session_id
      TRANSPORTING NO FIELDS.
    IF sy-subrc <> 0.
      APPEND ls_loaded_ctx-session_id TO gt_current_sessions.
    ENDIF.
  ENDLOOP.
  SORT gt_current_sessions.

  IF gv_0400_context_batch_scope = abap_true.
    gv_0400_batch_scope       = abap_true.
    gv_current_batch_prefix   = gv_0400_context_batch.
  ELSE.
    CLEAR gv_0400_batch_scope.
    gv_current_batch_prefix = gv_0400_context_batch.
    IF gv_current_batch_prefix IS INITIAL.
      PERFORM batch_prefix_from_sid
        USING    lv_sid
        CHANGING gv_current_batch_prefix.
    ENDIF.
  ENDIF.

  txtp_session_id = lv_sid.
  txtp_sess       = lv_sid.

  CLEAR: lv_tcode, lv_profile, lv_ver, lv_found.
  PERFORM resolve_session_context
    USING    lv_sid
    CHANGING lv_tcode lv_profile lv_ver lv_found.

  cv_ok = abap_true.
ENDFORM.

FORM sync_0400_scope.
 "0400 must always represent the exact data currently held by 0300.
 "Never reuse a batch/session prefix left over from an older upload.
  DATA: ls_first_0400 TYPE zbdc_staging_bup,
        ls_row_0400   TYPE zbdc_staging_bup,
        lv_first_sid  TYPE zbdc_staging_bup-session_id,
        lv_first_bat  TYPE zbdc_staging_bup-session_id,
        lv_row_bat    TYPE zbdc_staging_bup-session_id,
        lv_seen_sid   TYPE zbdc_staging_bup-session_id,
        lv_same_batch TYPE abap_bool,
        lv_ctx_tcode  TYPE zbdc_prof_bup-tcode,
        lv_ctx_profile TYPE zbdc_prof_bup-profile_name,
        lv_ctx_ver    TYPE zbdc_prof_bup-profile_ver,
        lv_ctx_found  TYPE abap_bool.

  IF gv_0400_context_locked = abap_true
     AND gv_0400_context_sid IS NOT INITIAL.
    REFRESH gt_current_sessions.
    LOOP AT gt_staging INTO ls_row_0400.
      IF ls_row_0400-session_id IS INITIAL.
        CONTINUE.
      ENDIF.
      READ TABLE gt_current_sessions INTO lv_seen_sid
        WITH KEY table_line = ls_row_0400-session_id.
      IF sy-subrc <> 0.
        APPEND ls_row_0400-session_id TO gt_current_sessions.
      ENDIF.
    ENDLOOP.
    SORT gt_current_sessions.
    gv_current_batch_count = lines( gt_current_sessions ).

    txtp_session_id = gv_0400_context_sid.
    txtp_sess       = gv_0400_context_sid.

    IF gv_0400_context_batch_scope = abap_true.
      gv_0400_batch_scope     = abap_true.
      gv_current_batch_prefix = gv_0400_context_batch.
    ELSE.
      CLEAR gv_0400_batch_scope.
      gv_current_batch_prefix = gv_0400_context_batch.
      IF gv_current_batch_prefix IS INITIAL.
        PERFORM batch_prefix_from_sid
          USING    gv_0400_context_sid
          CHANGING gv_current_batch_prefix.
      ENDIF.
    ENDIF.

    CLEAR: lv_ctx_tcode, lv_ctx_profile, lv_ctx_ver, lv_ctx_found.
    PERFORM resolve_session_context
      USING    gv_0400_context_sid
      CHANGING lv_ctx_tcode lv_ctx_profile lv_ctx_ver lv_ctx_found.
    RETURN.
  ENDIF.

  REFRESH gt_current_sessions.
  CLEAR: gv_current_batch_prefix, txtp_session_id, txtp_sess.

  READ TABLE gt_staging INTO ls_first_0400 INDEX 1.
  IF sy-subrc <> 0.
    RETURN.
  ENDIF.

  lv_first_sid = ls_first_0400-session_id.
  PERFORM batch_prefix_from_sid
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
      PERFORM batch_prefix_from_sid
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
 "Keep the two identities separate. TXTP_SESSION_ID is always a real
 "persisted SESSION_ID; the batch prefix belongs only to the dedicated
 "batch context. Batch mode remains explicit; one exact session does not
 "become a batch merely because its prefix can be derived.
    gv_current_batch_prefix = lv_first_bat.
    txtp_session_id         = lv_first_sid.
    txtp_sess               = lv_first_sid.
    IF lines( gt_current_sessions ) <= 1.
      CLEAR gv_0400_batch_scope.
    ENDIF.
  ELSE.
 "Mixed unrelated sessions: show the first real session and avoid a false
 "LIKE-prefix query against result logs.
    CLEAR: gv_current_batch_prefix, gv_0400_batch_scope.
    txtp_session_id = lv_first_sid.
    txtp_sess       = lv_first_sid.
  ENDIF.

  IF ls_first_0400-session_id IS NOT INITIAL.
    PERFORM apply_first_staging_ctx.
  ELSEIF ls_first_0400-tcode IS NOT INITIAL.
    p_transaction = ls_first_0400-tcode.
    CLEAR: txtp_profile_name, gv_profile_ver,
           gv_runtime_script_id, gv_runtime_contract_hash,
           gs_runtime_cert, gv_runtime_cert_loaded.
  ENDIF.
ENDFORM.

FORM open_0400_for_current_staging.

  DATA: lv_session_id  TYPE zbdc_staging_bup-session_id,
        lv_batch_prefix TYPE zbdc_staging_bup-session_id,
        lv_scope_text   TYPE string,
        lv_count        TYPE i,
        lv_reset        TYPE i,
        lv_hist_scope   TYPE abap_bool,
        ls_first_stg    TYPE zbdc_staging_bup.

  CLEAR: lv_session_id,
         lv_batch_prefix,
         lv_scope_text,
         lv_count,
         ls_first_stg.

  PERFORM clear_0400_context.

 "Capture the current upload scope before clearing frontend buffers.
  READ TABLE gt_staging INTO ls_first_stg INDEX 1.
  IF sy-subrc = 0.
    lv_session_id = ls_first_stg-session_id.
    CONDENSE lv_session_id.
  ENDIF.

 "one Upload action may contain several selected files/submissions.
 "When the current batch owns more than one session, Staging must open the
 "whole batch rather than silently displaying only the first session.
  IF gv_current_batch_prefix IS NOT INITIAL
     AND lines( gt_current_sessions ) > 1.
    lv_batch_prefix = gv_current_batch_prefix.
    CONDENSE lv_batch_prefix.
  ENDIF.

  IF lv_session_id IS INITIAL.
    MESSAGE s618(zbdc) DISPLAY LIKE 'W'.
    RETURN.
  ENDIF.

  PERFORM reset_0400_selection.
  PERFORM free_0400_grid.

  CLEAR: gt_staging,
         gt_staging_alv,
         gt_exec_disp.

  REFRESH: gt_staging,
           gt_staging_alv,
           gt_exec_disp.

  CLEAR: txtp_session_id,
         txtp_sess.

  CALL METHOD cl_gui_cfw=>flush
    EXCEPTIONS
      OTHERS = 1.

  IF lv_batch_prefix IS NOT INITIAL.
 "The batch prefix is a query scope only. Never put it into the exact
 "SESSION_ID screen fields; load_exact_staging assigns the first
 "persisted session after the batch has been loaded successfully.
    lv_scope_text = lv_batch_prefix.

    PERFORM load_staging_by_batch
      USING    lv_batch_prefix
      CHANGING lv_count.
  ELSE.
    txtp_session_id = lv_session_id.
    txtp_sess       = lv_session_id.
    lv_scope_text   = lv_session_id.

    PERFORM load_staging_by_session
      USING    lv_session_id
      CHANGING lv_count.
  ENDIF.

  IF lv_count <= 0 OR gt_staging IS INITIAL.
    MESSAGE s619(zbdc) WITH lv_scope_text DISPLAY LIKE 'W'.
    RETURN.
  ENDIF.

 "Staging is a review boundary. Always clear only
 "synthetic runtime setup-gate rows (Profile setup incomplete / not
 "certified) because they are not SAP/data execution results. Real
 "SUCCESS/ERROR/SM35QUEUE/PROCESSED rows remain untouched, including
 "Preview Files history scopes.
  CLEAR: lv_reset, lv_hist_scope.
  IMPORT lv_0300_hist_scope = lv_hist_scope FROM MEMORY ID 'ZBDC_0300_HISTORY_SCOPE'.
  PERFORM reset_stage_setup_gate CHANGING lv_reset.
  IF lv_reset > 0.
    lv_count = lines( gt_staging ).
    IF lv_hist_scope = abap_true.
      MESSAGE s620(zbdc) DISPLAY LIKE 'I'.
    ENDIF.
  ENDIF.

  PERFORM freeze_0400_context USING lv_session_id.
  PERFORM sync_0400_scope.

  gv_0400_view      = gc_view_cockpit.
  gv_0400_edit_mode = space.

  REFRESH: gt_staging_alv,
           gt_exec_disp.

  PERFORM prepare_alv_0400.
  PERFORM build_exec_cockpit.
  PERFORM update_0400_counters.

  CALL SCREEN 0400.

ENDFORM.

FORM UPDATE_GROUP_RESULT USING PT_GROUP  TYPE TY_T_STAGING_ALV
                               PV_STATUS TYPE ANY
                               PV_MSG    TYPE STRING
                               PV_OBJ    TYPE ANY.
  DATA: LS_G      TYPE TY_STAGING_ALV,
        LS_STG    TYPE ZBDC_STAGING_BUP,
        LT_STG_DB TYPE STANDARD TABLE OF ZBDC_STAGING_BUP,
        LS_RES    TYPE ZBDC_RESULT_BUP,
        LV_TYPE   TYPE C LENGTH 1,
        LV_CREATED_TS TYPE TIMESTAMPL,
        LV_DEMO_DATE_836 TYPE SY-DATUM,
        LV_DEMO_TIME_836 TYPE SY-UZEIT.

  FIELD-SYMBOLS: <FS_ALV> TYPE TY_STAGING_ALV,
                 <FS_STG> TYPE ZBDC_STAGING_BUP,
                 <FV>     TYPE ANY.

  LOOP AT PT_GROUP INTO LS_G.
    MOVE-CORRESPONDING LS_G TO LS_STG.
    LS_STG-STATUS = PV_STATUS.
    IF PV_STATUS = GC_ST_SUCCESS OR PV_STATUS = GC_ST_READY OR
       PV_STATUS = GC_ST_PROCESSED.
      CLEAR: LS_STG-ERROR_MSG, LS_STG-LAST_ERROR.
    ELSEIF PV_STATUS = GC_ST_SM35Q.
      LS_STG-ERROR_MSG = PV_MSG.
      CLEAR LS_STG-LAST_ERROR.
    ELSE.
      LS_STG-ERROR_MSG = PV_MSG.
      LS_STG-LAST_ERROR = PV_MSG.
    ENDIF.
    APPEND LS_STG TO LT_STG_DB.

    READ TABLE GT_STAGING_ALV ASSIGNING <FS_ALV>
      WITH KEY SESSION_ID = LS_G-SESSION_ID ROW_INDEX = LS_G-ROW_INDEX.
    IF SY-SUBRC = 0.
      <FS_ALV>-STATUS = PV_STATUS.
      IF PV_STATUS = GC_ST_SUCCESS OR PV_STATUS = GC_ST_READY OR
         PV_STATUS = GC_ST_PROCESSED.
        CLEAR: <FS_ALV>-ERROR_MSG, <FS_ALV>-LAST_ERROR.
      ELSEIF PV_STATUS = GC_ST_SM35Q.
        <FS_ALV>-ERROR_MSG = PV_MSG.
        CLEAR <FS_ALV>-LAST_ERROR.
      ELSE.
        <FS_ALV>-ERROR_MSG = PV_MSG.
        <FS_ALV>-LAST_ERROR = PV_MSG.
      ENDIF.
    ENDIF.

    READ TABLE GT_STAGING ASSIGNING <FS_STG>
      WITH KEY SESSION_ID = LS_G-SESSION_ID ROW_INDEX = LS_G-ROW_INDEX.
    IF SY-SUBRC = 0.
      <FS_STG>-STATUS = PV_STATUS.
      IF PV_STATUS = GC_ST_SUCCESS OR PV_STATUS = GC_ST_READY OR
         PV_STATUS = GC_ST_PROCESSED.
        CLEAR: <FS_STG>-ERROR_MSG, <FS_STG>-LAST_ERROR.
      ELSEIF PV_STATUS = GC_ST_SM35Q.
        <FS_STG>-ERROR_MSG = PV_MSG.
        CLEAR <FS_STG>-LAST_ERROR.
      ELSE.
        <FS_STG>-ERROR_MSG = PV_MSG.
        <FS_STG>-LAST_ERROR = PV_MSG.
      ENDIF.
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
  ELSEIF PV_STATUS = GC_ST_PROCESSED OR
         PV_STATUS = GC_ST_SM35Q.
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
  ASSIGN COMPONENT 'EXEC_STATUS'   OF STRUCTURE LS_RES TO <FV>. IF SY-SUBRC = 0. <FV> = PV_STATUS. ENDIF.
  ASSIGN COMPONENT 'ROW_INDEX'     OF STRUCTURE LS_RES TO <FV>. IF SY-SUBRC = 0. <FV> = LS_G-ROW_INDEX. ENDIF.
  GET TIME STAMP FIELD LV_CREATED_TS.
  PERFORM get_demo_now CHANGING LV_DEMO_DATE_836 LV_DEMO_TIME_836.
  ASSIGN COMPONENT 'CREATED_AT'    OF STRUCTURE LS_RES TO <FV>. IF SY-SUBRC = 0. <FV> = LV_CREATED_TS. ENDIF.
  ASSIGN COMPONENT 'CREATED_TM'    OF STRUCTURE LS_RES TO <FV>. IF SY-SUBRC = 0. <FV> = LV_DEMO_TIME_836. ENDIF.
  ASSIGN COMPONENT 'CREATED_BY'    OF STRUCTURE LS_RES TO <FV>. IF SY-SUBRC = 0. <FV> = SY-UNAME. ENDIF.

  MODIFY ZBDC_RESULT_BUP FROM LS_RES.
ENDFORM.

*& PROCESS_NEXT_BDC_RECORD - Phase 8: run next READY group/record

FORM color_exec_row
  CHANGING cs_exec TYPE ty_exec_disp.

  DATA: ls_color TYPE lvc_s_scol,
        lv_col   TYPE i.

  REFRESH cs_exec-cell_colors.

  CASE cs_exec-run_status.
    WHEN gc_st_success.
      lv_col = 5.
    WHEN gc_st_error.
      lv_col = 6.
    WHEN gc_st_warning OR gc_st_processed OR gc_st_partial OR gc_st_sm35q.
      lv_col = 3.
    WHEN 'PROCESSING' OR 'VERIFYING'.
      lv_col = 4.
    WHEN gc_st_ready OR 'QUEUED'.
      lv_col = 1.
    WHEN OTHERS.
      lv_col = 1.
  ENDCASE.

  DEFINE add_color.
    CLEAR ls_color.
    ls_color-fname = &1.
    ls_color-color-col = lv_col.
    ls_color-color-int = 1.
    APPEND ls_color TO cs_exec-cell_colors.
  END-OF-DEFINITION.

  add_color 'ICON'.
  add_color 'GROUP_KEY'.
  add_color 'RUN_STATUS'.
  add_color 'MESSAGE'.
  add_color 'EXECUTION'.

ENDFORM.

*& exact execution projection for the cockpit/queue
*& One visible value answers: which executor actually ran, and which attempt.
*& READY after a correction shows the next attempt without incrementing it.

FORM fill_execution
  USING    pt_result TYPE ty_t_result_726
  CHANGING cs_exec   TYPE ty_exec_disp.

  DATA: lt_group    TYPE ty_t_result_726,
        ls_res      TYPE zbdc_result_bup,
        lv_executor TYPE char12,
        lv_attempt  TYPE i,
        lv_next     TYPE i.

  CLEAR: cs_exec-execution, lv_attempt, lv_executor.

  LOOP AT pt_result INTO ls_res
    WHERE session_id = cs_exec-session_id
      AND record_key = cs_exec-group_key.
    APPEND ls_res TO lt_group.
    IF ls_res-attempt_no > lv_attempt.
      lv_attempt = ls_res-attempt_no.
    ENDIF.
  ENDLOOP.

  SORT lt_group BY created_at DESCENDING step DESCENDING.
  IF lt_group IS NOT INITIAL.
    PERFORM resolve_executor USING lt_group CHANGING lv_executor.
  ENDIF.

  IF lv_executor = 'UNKNOWN'.
    CLEAR lv_executor.
  ENDIF.
  IF cs_exec-run_status = gc_st_sm35q AND lv_executor IS INITIAL.
    lv_executor = 'BISM'.
  ENDIF.

  cs_exec-attempt = lv_attempt.

  CASE cs_exec-run_status.
    WHEN gc_st_ready.
      IF lv_attempt > 0.
        lv_next = lv_attempt + 1.
        cs_exec-execution = |Ready for Attempt { lv_next }|.
      ELSE.
        cs_exec-execution = 'Not executed'.
      ENDIF.

    WHEN gc_st_sm35q.
      IF lv_attempt > 0.
        cs_exec-execution = |BISM - Attempt { lv_attempt }|.
      ELSE.
        cs_exec-execution = 'BISM - queued'.
      ENDIF.

    WHEN 'PROCESSING' OR 'RUNNING' OR 'QUEUED'.
      IF lv_executor IS NOT INITIAL AND lv_attempt > 0.
        cs_exec-execution = |{ lv_executor } - Attempt { lv_attempt }|.
      ELSEIF lv_executor IS NOT INITIAL.
        cs_exec-execution = |{ lv_executor } - in progress|.
      ELSE.
        cs_exec-execution = 'In progress'.
      ENDIF.

    WHEN OTHERS.
      IF lv_executor IS NOT INITIAL AND lv_attempt > 0.
        cs_exec-execution = |{ lv_executor } - Attempt { lv_attempt }|.
      ELSEIF lv_executor IS NOT INITIAL.
        cs_exec-execution = lv_executor.
      ELSEIF lv_attempt > 0.
        cs_exec-execution = |Attempt { lv_attempt }|.
      ELSE.
        cs_exec-execution = 'No execution evidence'.
      ENDIF.
  ENDCASE.

ENDFORM.

FORM BUILD_EXEC_COCKPIT.
  DATA: LT_RES      TYPE STANDARD TABLE OF ZBDC_RESULT_BUP,
        LS_EXEC     TYPE TY_EXEC_DISP,
        LV_KEY      TYPE ZBDC_STAGING_BUP-RECORD_KEY,
        LV_ALL_OK        TYPE ABAP_BOOL,
        LV_ALL_PROCESSED TYPE ABAP_BOOL,
        LV_ALL_SM35      TYPE ABAP_BOOL,
        LV_BATCH_LIKE TYPE STRING,
        LV_Z576_WAS_SUCCESS TYPE ABAP_BOOL.

  FIELD-SYMBOLS: <FS_ALV>  TYPE TY_STAGING_ALV,
                 <FS_EXEC> TYPE TY_EXEC_DISP.

 "row selection is maintained by CL_GUI_ALV_GRID, not in business data.

  REFRESH GT_EXEC_DISP.
  CLEAR: GV_EXEC_TOTAL_GRP, GV_EXEC_READY_GRP, GV_EXEC_SUCC_GRP,
         GV_EXEC_ERR_GRP, GV_EXEC_WARN_GRP, GV_EXEC_PROC_GRP, GV_EXEC_SM35_GRP,
         GV_EXEC_RETRY_GRP,
         GV_EXEC_PROGRESS, GV_EXEC_HEADER_TXT.

  IF GT_STAGING_ALV IS INITIAL AND GT_STAGING IS NOT INITIAL.
    PERFORM PREPARE_ALV_0400.
  ENDIF.

  IF GT_STAGING_ALV IS NOT INITIAL.
    READ TABLE GT_STAGING_ALV INTO DATA(LS_SESS_FOR_RES) INDEX 1.
    IF SY-SUBRC = 0.
      IF gv_0400_batch_scope = abap_true
         AND gv_current_batch_prefix IS NOT INITIAL
         AND lines( gt_current_sessions ) > 1.
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

 "Group-level display: one row = one generic business group (RECORD_KEY).
  LOOP AT GT_STAGING_ALV ASSIGNING <FS_ALV>.
    LV_KEY = <FS_ALV>-RECORD_KEY.
    IF LV_KEY IS INITIAL.
      LV_KEY = <FS_ALV>-ROW_INDEX.
    ENDIF.

    READ TABLE GT_EXEC_DISP ASSIGNING <FS_EXEC>
      WITH KEY SESSION_ID = <FS_ALV>-SESSION_ID GROUP_KEY = LV_KEY.

    IF SY-SUBRC <> 0.
      CLEAR LS_EXEC.
      PERFORM batch_prefix_from_sid USING <FS_ALV>-SESSION_ID CHANGING LS_EXEC-BATCH_KEY.
      DATA: lv_unit_raw_0400 TYPE string,
            lv_source_msg_0400 TYPE zbdc_result_bup-message,
            lv_file_pos_0400 TYPE i.
      SELECT SINGLE file_name FROM zbdc_file_lg_bup
        WHERE session_id = @<FS_ALV>-SESSION_ID
        INTO @lv_unit_raw_0400.

      "A source filename must never be faked from SESSION_ID. Older/imported
      "sessions may lack a FILE_LG row, but the immutable __SOURCE__ audit row
      "still carries FILE=<unit>. Recover only that persisted evidence.
      IF lv_unit_raw_0400 IS INITIAL.
        SELECT SINGLE message FROM zbdc_result_bup
          WHERE session_id = @<FS_ALV>-SESSION_ID
            AND record_key = '__SOURCE__'
          INTO @lv_source_msg_0400.
        IF sy-subrc = 0 AND lv_source_msg_0400 IS NOT INITIAL.
          FIND ';FILE=' IN lv_source_msg_0400 MATCH OFFSET lv_file_pos_0400.
          IF sy-subrc = 0.
            lv_file_pos_0400 = lv_file_pos_0400 + 6.
            lv_unit_raw_0400 = lv_source_msg_0400+lv_file_pos_0400.
          ENDIF.
        ENDIF.
      ENDIF.

      IF lv_unit_raw_0400 IS NOT INITIAL.
        PERFORM p1_split_unit_name USING lv_unit_raw_0400 CHANGING LS_EXEC-SOURCE_FILE LS_EXEC-SHEET_NAME.
      ELSE.
        CLEAR: LS_EXEC-SOURCE_FILE, LS_EXEC-SHEET_NAME.
      ENDIF.
      LS_EXEC-SESSION_ID = <FS_ALV>-SESSION_ID.
      LS_EXEC-GROUP_KEY  = LV_KEY.
      LS_EXEC-TCODE      = <FS_ALV>-TCODE.
      IF LS_EXEC-TCODE IS INITIAL.
        LS_EXEC-TCODE = P_TRANSACTION.
      ENDIF.
      CLEAR LS_EXEC-DRILL_TCODE.
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
      WHEN GC_ST_PROCESSED.
        <FS_EXEC>-PROCESSED_COUNT = <FS_EXEC>-PROCESSED_COUNT + 1.
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
      WHEN GC_ST_PROCESSING OR GC_ST_SKIPPED OR GC_ST_PARTIAL OR 'RETRY' OR SPACE.
        <FS_EXEC>-WARNING_COUNT = <FS_EXEC>-WARNING_COUNT + 1.
        IF <FS_EXEC>-MESSAGE IS INITIAL.
          <FS_EXEC>-MESSAGE = |Row lifecycle is not executable: { <FS_ALV>-STATUS }. Validate or refresh the exact session.|.
        ENDIF.
      WHEN OTHERS.
        <FS_EXEC>-ERROR_COUNT = <FS_EXEC>-ERROR_COUNT + 1.
        IF <FS_EXEC>-MESSAGE IS INITIAL.
          <FS_EXEC>-MESSAGE = |Unsupported staging lifecycle status: { <FS_ALV>-STATUS }.|.
        ENDIF.
    ENDCASE.

    IF <FS_EXEC>-MESSAGE IS INITIAL AND <FS_ALV>-ERROR_MSG IS NOT INITIAL AND
       ( <FS_ALV>-STATUS = GC_ST_ERROR OR
         <FS_ALV>-STATUS = GC_ST_WARNING OR
         <FS_ALV>-STATUS = GC_ST_SM35Q OR
         <FS_ALV>-STATUS = 'SKIPPED' ).
      <FS_EXEC>-MESSAGE = <FS_ALV>-ERROR_MSG.
    ENDIF.
  ENDLOOP.

  LOOP AT GT_EXEC_DISP ASSIGNING <FS_EXEC>.
    LV_ALL_OK = ABAP_FALSE.
    LV_ALL_PROCESSED = ABAP_FALSE.
    LV_ALL_SM35 = ABAP_FALSE.
    IF <FS_EXEC>-ITEM_COUNT > 0 AND <FS_EXEC>-SUCCESS_COUNT = <FS_EXEC>-ITEM_COUNT.
      LV_ALL_OK = ABAP_TRUE.
    ENDIF.
    IF <FS_EXEC>-ITEM_COUNT > 0 AND <FS_EXEC>-PROCESSED_COUNT = <FS_EXEC>-ITEM_COUNT.
      LV_ALL_PROCESSED = ABAP_TRUE.
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
    ELSEIF LV_ALL_PROCESSED = ABAP_TRUE.
      <FS_EXEC>-ICON        = '@08@'.
      <FS_EXEC>-RUN_STATUS  = GC_ST_PROCESSED.
      <FS_EXEC>-MSG_TYPE    = 'I'.
      <FS_EXEC>-HEALTH_TEXT = 'Execution processed'.
      <FS_EXEC>-ACTION_HINT = 'Review exact SAP protocol'.
      CLEAR: <FS_EXEC>-SAP_OBJECT_ID, <FS_EXEC>-DRILL_TCODE.
      GV_EXEC_PROC_GRP      = GV_EXEC_PROC_GRP + 1.
    ELSEIF <FS_EXEC>-WARNING_COUNT > 0.
      <FS_EXEC>-ICON        = '@09@'.
      <FS_EXEC>-RUN_STATUS  = GC_ST_WARNING.
      <FS_EXEC>-MSG_TYPE    = 'W'.
      IF <FS_EXEC>-MESSAGE CS 'without terminal status' OR
         <FS_EXEC>-MESSAGE CS 'WITHOUT TERMINAL STATUS' OR
         <FS_EXEC>-MESSAGE CS 'no SAP success/error protocol' OR
         <FS_EXEC>-MESSAGE CS 'NO SAP SUCCESS/ERROR PROTOCOL' OR
         <FS_EXEC>-MESSAGE CS 'moved from READY to WARNING' OR
         <FS_EXEC>-MESSAGE CS 'READY was converted to ERROR'.
        <FS_EXEC>-HEALTH_TEXT = 'CT status not confirmed'.
        <FS_EXEC>-ACTION_HINT = 'Review exact SAP protocol before retry'.
      ELSE.
        <FS_EXEC>-HEALTH_TEXT = 'Completed with warning'.
      ENDIF.
      GV_EXEC_WARN_GRP = GV_EXEC_WARN_GRP + 1.
    ELSEIF LV_ALL_OK = ABAP_TRUE.
      <FS_EXEC>-ICON        = '@08@'.
      <FS_EXEC>-RUN_STATUS  = GC_ST_SUCCESS.
      <FS_EXEC>-MSG_TYPE    = 'S'.
      <FS_EXEC>-HEALTH_TEXT = 'SAP execution successful'.
      GV_EXEC_SUCC_GRP      = GV_EXEC_SUCC_GRP + 1.
    ELSEIF LV_ALL_SM35 = ABAP_TRUE.
      <FS_EXEC>-ICON        = '@09@'.
      <FS_EXEC>-RUN_STATUS  = GC_ST_SM35Q.
      <FS_EXEC>-MSG_TYPE    = 'I'.
      IF <FS_EXEC>-MESSAGE CS 'is processing'.
        <FS_EXEC>-HEALTH_TEXT = 'SM35 session processing'.
      ELSEIF <FS_EXEC>-MESSAGE CS 'background job' OR
             <FS_EXEC>-MESSAGE CS 'RSBDCCTU' OR
             <FS_EXEC>-MESSAGE CS 'RSBDCBTC' OR
             <FS_EXEC>-MESSAGE CS 'background processing'.
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
      <FS_EXEC>-RUN_STATUS  = GC_ST_PARTIAL.
      <FS_EXEC>-MSG_TYPE    = 'W'.
      <FS_EXEC>-HEALTH_TEXT = 'Mixed row status in group'.
      GV_EXEC_WARN_GRP      = GV_EXEC_WARN_GRP + 1.
    ENDIF.

 "attempt is projected only from persisted execution evidence.
 "Never invent Attempt 1 for READY and never infer retry count from message text.
    CLEAR <FS_EXEC>-ATTEMPT.
    IF <FS_EXEC>-RUN_STATUS = GC_ST_ERROR.
      PERFORM fill_exec_err_result USING LT_RES CHANGING <FS_EXEC>.
    ENDIF.
    PERFORM scrub_exec_terminal CHANGING <FS_EXEC>.

 "Project document identity/navigation only after execution truth is final.
 "Navigation never changes SUCCESS/ERROR; it is a post-execution capability.
    PERFORM fill_exec_navigation USING LT_RES CHANGING <FS_EXEC>.

    IF <FS_EXEC>-RUN_STATUS = GC_ST_SUCCESS.
      LV_Z576_WAS_SUCCESS = ABAP_TRUE.
      <FS_EXEC>-ICON        = '@08@'.
      <FS_EXEC>-MSG_TYPE    = 'S'.
      <FS_EXEC>-HEALTH_TEXT = 'Execution successful'.
      <FS_EXEC>-ACTION_HINT = 'View exact SAP success message'.
 "on SUCCESS, prefer the exact final SAP S-message already
 "persisted by CT BDCMSGCOLL or the SM35 protocol importer.
      PERFORM fill_exec_success_message USING LT_RES CHANGING <FS_EXEC>.
      IF <FS_EXEC>-MESSAGE IS INITIAL OR <FS_EXEC>-MESSAGE CS 'OBJECT_STATUS='.
        <FS_EXEC>-MESSAGE = 'SAP execution completed successfully; no terminal S-message was returned.'.
      ENDIF.
    ELSE.
      LV_Z576_WAS_SUCCESS = ABAP_FALSE.
    ENDIF.

 "The preliminary group counter was computed from staging lifecycle before
 "the contract projection. Keep dashboard totals truthful if an old/drifted
 "row can no longer satisfy FINAL SUCCESS.
    IF LV_Z576_WAS_SUCCESS = ABAP_TRUE AND <FS_EXEC>-RUN_STATUS <> GC_ST_SUCCESS.
      IF GV_EXEC_SUCC_GRP > 0.
        GV_EXEC_SUCC_GRP = GV_EXEC_SUCC_GRP - 1.
      ENDIF.
      GV_EXEC_WARN_GRP = GV_EXEC_WARN_GRP + 1.
    ENDIF.

    CLEAR <FS_EXEC>-SELECTED.  "Technical compatibility field; hidden in 0400.

    PERFORM SET_EXEC_ACTION_HINT CHANGING <FS_EXEC>.
    PERFORM final_exec_display_guard CHANGING <FS_EXEC>.

 "Group Details was a redundant visible column. Show the exact
 "executor/attempt instead. READY after correction previews the next attempt.
    PERFORM fill_execution USING LT_RES CHANGING <FS_EXEC>.

    PERFORM color_exec_row CHANGING <FS_EXEC>.

    GV_EXEC_TOTAL_GRP = GV_EXEC_TOTAL_GRP + 1.
  ENDLOOP.

  IF GV_EXEC_TOTAL_GRP > 0.
    DATA(LV_PCT) = ( ( GV_EXEC_SUCC_GRP + GV_EXEC_PROC_GRP ) * 100 ) / GV_EXEC_TOTAL_GRP.
    GV_EXEC_PROGRESS = |{ LV_PCT }% completed|.
  ELSE.
    GV_EXEC_PROGRESS = 'No group'.
  ENDIF.

  GV_EXEC_HEADER_TXT = |Groups { GV_EXEC_TOTAL_GRP } | &&
                       |Ready { GV_EXEC_READY_GRP } | &&
                       |Success { GV_EXEC_SUCC_GRP } | &&
                       |Processed { GV_EXEC_PROC_GRP } | &&
                       |Error { GV_EXEC_ERR_GRP } | &&
                       |Warning { GV_EXEC_WARN_GRP } | &&
                       |SM35 { GV_EXEC_SM35_GRP } | &&
                       |Retry { GV_EXEC_RETRY_GRP }|.

  SORT GT_EXEC_DISP BY SESSION_ID GROUP_KEY.
ENDFORM.

FORM get_selected_count CHANGING CV_SELECTED TYPE I.
  DATA LT_ROWS TYPE LVC_T_ROW.

  CLEAR CV_SELECTED.
  IF GV_0400_VIEW <> GC_VIEW_COCKPIT OR GO_EXEC_GRID IS NOT BOUND.
    RETURN.
  ENDIF.

  TRY.
      CALL METHOD GO_EXEC_GRID->GET_SELECTED_ROWS
        IMPORTING ET_INDEX_ROWS = LT_ROWS.
      CV_SELECTED = LINES( LT_ROWS ).
    CATCH CX_ROOT.
      CLEAR CV_SELECTED.
  ENDTRY.
ENDFORM.

FORM RENDER_0400_HEADER.
 "CL_DD_DOCUMENT->ADD_TEXT expects SDYDO_TEXT_ELEMENT, not STRING.
 "UX ONLY: top dynpro strip owns Total/Success/Error/Warning.
 "Cockpit header shows only non-duplicated operational state.
  DATA: LV_TITLE    TYPE SDYDO_TEXT_ELEMENT,
        LV_LINE1    TYPE SDYDO_TEXT_ELEMENT,
        LV_LINE2    TYPE SDYDO_TEXT_ELEMENT,
        LV_SELECTED TYPE I.

  CLEAR LV_SELECTED.
  PERFORM get_selected_count CHANGING LV_SELECTED.

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

 "UX ONLY: remove duplicated Total/Success/Error/Warning from header.
  LV_LINE1 = |Session: { TXTP_SESSION_ID }    Transaction: { P_TRANSACTION }    Batch Size: { TXTP_BATCH_SIZE }    Progress: { GV_EXEC_PROGRESS }|.
  LV_LINE2 = |Ready: { GV_EXEC_READY_GRP }    SM35 Queue: { GV_EXEC_SM35_GRP }    Retry: { GV_EXEC_RETRY_GRP }    Selected: { LV_SELECTED }|.

  CALL METHOD GO_DOC_HEAD_0400->ADD_TEXT
    EXPORTING
      TEXT      = LV_TITLE
      SAP_STYLE = CL_DD_AREA=>HEADING.
  CALL METHOD GO_DOC_HEAD_0400->NEW_LINE.
  CALL METHOD GO_DOC_HEAD_0400->ADD_TEXT EXPORTING TEXT = LV_LINE1.
  CALL METHOD GO_DOC_HEAD_0400->NEW_LINE.
  CALL METHOD GO_DOC_HEAD_0400->ADD_TEXT EXPORTING TEXT = LV_LINE2.

  CALL METHOD GO_DOC_HEAD_0400->DISPLAY_DOCUMENT
    EXPORTING
      PARENT        = GO_CONT_HEAD_0400
      REUSE_CONTROL = 'X'.
ENDFORM.

*& Project exact final SAP success message into the cockpit

*& Raw structured protocol remains authoritative in ZBDC_RESULT_BUP.
*& This routine only chooses the newest S-message for the exact displayed
*& group so SUCCESS shows the same text SAP emitted after SAVE.

FORM fill_exec_success_message
  USING    pt_res  TYPE STANDARD TABLE
  CHANGING cs_exec TYPE ty_exec_disp.

  DATA: lt_res          TYPE STANDARD TABLE OF zbdc_result_bup,
        ls_res          TYPE zbdc_result_bup,
        lv_group_key    TYPE string,
        lv_row_key      TYPE char40,
        lv_sm35_seen    TYPE abap_bool,
        lv_admin_s      TYPE abap_bool,
        lv_sm35_biz_msg TYPE string,
        lv_non_sm35_msg TYPE string.

  lt_res = pt_res.
  SORT lt_res BY created_at DESCENDING step DESCENDING.

  LOOP AT lt_res INTO ls_res.
    IF ls_res-session_id <> cs_exec-session_id OR
       ls_res-msg_type <> 'S' OR
       ls_res-message IS INITIAL.
      CONTINUE.
    ENDIF.

    IF ls_res-record_key IS NOT INITIAL.
      lv_group_key = ls_res-record_key.
    ELSE.
      CLEAR lv_row_key.
      WRITE ls_res-row_index TO lv_row_key LEFT-JUSTIFIED.
      CONDENSE lv_row_key NO-GAPS.
      lv_group_key = lv_row_key.
    ENDIF.

    IF lv_group_key <> cs_exec-group_key.
      CONTINUE.
    ENDIF.

    IF ls_res-field_name = 'SM35'.
      lv_sm35_seen = abap_true.
 "prefer the explicit application-S marker produced while raw
 "BDCLM identity is still available. Keep legacy non-admin fallback for
 "older rows, but never expose Control Framework diagnostics as success.
      IF ls_res-exec_status = 'SM35_DIAG'.
        CONTINUE.
      ENDIF.
      IF ls_res-exec_status = 'SM35_APP_S'.
        IF lv_sm35_biz_msg IS INITIAL.
          lv_sm35_biz_msg = ls_res-message.
        ENDIF.
        CONTINUE.
      ENDIF.
      CLEAR lv_admin_s.
      PERFORM is_sm35_admin_s USING ls_res CHANGING lv_admin_s.
      IF lv_admin_s <> abap_true AND lv_sm35_biz_msg IS INITIAL.
        lv_sm35_biz_msg = ls_res-message.
      ENDIF.
    ELSEIF lv_non_sm35_msg IS INITIAL.
      lv_non_sm35_msg = ls_res-message.
    ENDIF.
  ENDLOOP.

  IF lv_sm35_biz_msg IS NOT INITIAL.
    cs_exec-message = lv_sm35_biz_msg.
    RETURN.
  ENDIF.

 "If this is a BISM result, keep the lifecycle message when SAP persisted
 "only SM35 controller S-messages. Never substitute 'Batch input processing
 "ended' for the transaction's business SAVE message.
  IF lv_sm35_seen = abap_true.
    RETURN.
  ENDIF.

  IF lv_non_sm35_msg IS NOT INITIAL.
    cs_exec-message = lv_non_sm35_msg.
  ENDIF.
ENDFORM.

*&---------------------------------------------------------------------*
*& Read structured SAP message parts from one persisted result row.
*& Dynamic component access keeps this compatible with older result DDIC
*& layouts while still using only structured MSGID/MSGNR/MSGV evidence.
*&---------------------------------------------------------------------*
FORM read_result_message_parts
  USING    is_res   TYPE zbdc_result_bup
  CHANGING cv_msgid TYPE symsgid
           cv_msgnr TYPE symsgno
           cv_v1    TYPE string
           cv_v2    TYPE string
           cv_v3    TYPE string
           cv_v4    TYPE string.

  FIELD-SYMBOLS <lv_any> TYPE any.

  CLEAR: cv_msgid, cv_msgnr, cv_v1, cv_v2, cv_v3, cv_v4.

  ASSIGN COMPONENT 'MSGID' OF STRUCTURE is_res TO <lv_any>.
  IF sy-subrc <> 0.
    ASSIGN COMPONENT 'MSG_ID' OF STRUCTURE is_res TO <lv_any>.
  ENDIF.
  IF sy-subrc = 0.
    cv_msgid = <lv_any>.
  ENDIF.

  ASSIGN COMPONENT 'MSGNR' OF STRUCTURE is_res TO <lv_any>.
  IF sy-subrc <> 0.
    ASSIGN COMPONENT 'MSG_NUMBER' OF STRUCTURE is_res TO <lv_any>.
  ENDIF.
  IF sy-subrc = 0.
    cv_msgnr = <lv_any>.
  ENDIF.

  ASSIGN COMPONENT 'MSGV1' OF STRUCTURE is_res TO <lv_any>.
  IF sy-subrc = 0. cv_v1 = <lv_any>. ENDIF.
  ASSIGN COMPONENT 'MSGV2' OF STRUCTURE is_res TO <lv_any>.
  IF sy-subrc = 0. cv_v2 = <lv_any>. ENDIF.
  ASSIGN COMPONENT 'MSGV3' OF STRUCTURE is_res TO <lv_any>.
  IF sy-subrc = 0. cv_v3 = <lv_any>. ENDIF.
  ASSIGN COMPONENT 'MSGV4' OF STRUCTURE is_res TO <lv_any>.
  IF sy-subrc = 0. cv_v4 = <lv_any>. ENDIF.

  CONDENSE: cv_v1, cv_v2, cv_v3, cv_v4.
ENDFORM.

*&---------------------------------------------------------------------*
*& Bootstrap navigation evidence from one real SUCCESS cockpit row.
*& Navigation certification is independent of execution-profile certification.
*& The user is never asked for profile/version/message internals.
*& Navigation may use one or several exact MSGV values. Composite business
*& keys are represented as a verified set of SPA/GPA bindings; no TCODE or
*& business-field combination is hardcoded.
*&---------------------------------------------------------------------*
FORM derive_nav_bootstrap_evidence
  USING    is_exec    TYPE ty_exec_disp
  CHANGING cs_nav     TYPE ty_nav_evidence
           cv_ok      TYPE abap_bool
           cv_message TYPE string.

  DATA: ls_session TYPE zbdc_session_bup,
        lt_res     TYPE ty_t_result,
        ls_res     TYPE zbdc_result_bup,
        lv_group   TYPE string,
        lv_row_key TYPE char40,
        lv_msgid   TYPE symsgid,
        lv_msgnr   TYPE symsgno,
        lv_v1      TYPE string,
        lv_v2      TYPE string,
        lv_v3      TYPE string,
        lv_v4      TYPE string,
        lv_any_v   TYPE abap_bool,
        lv_fallback_found TYPE abap_bool.

  CLEAR: cs_nav, cv_ok, cv_message.

  IF is_exec-run_status <> gc_st_success OR
     is_exec-session_id IS INITIAL OR
     is_exec-group_key IS INITIAL.
    cv_message = 'Select one SUCCESS row with persisted SAP protocol evidence.'.
    RETURN.
  ENDIF.

  SELECT SINGLE * FROM zbdc_session_bup
    INTO @ls_session
    WHERE session_id = @is_exec-session_id.
  IF sy-subrc <> 0 OR
     ls_session-tcode IS INITIAL OR
     ls_session-profile_name IS INITIAL OR
     ls_session-profile_ver IS INITIAL OR
     ls_session-script_id IS INITIAL OR
     ls_session-contract_hash IS INITIAL.
    cv_message = 'The selected execution row has no complete frozen session context.'.
    RETURN.
  ENDIF.

  SELECT * FROM zbdc_result_bup
    INTO TABLE @lt_res
    WHERE session_id = @is_exec-session_id.
  IF lt_res IS INITIAL.
    cv_message = 'No persisted SAP result rows exist for the selected execution.'.
    RETURN.
  ENDIF.
  SORT lt_res BY created_at DESCENDING step DESCENDING.

  "The cockpit already projects the exact terminal business S-message. Use
  "that same persisted row as bootstrap authority instead of requiring that
  "the message contain only one variable. SAP messages can legitimately carry
  "several variables (for example document type plus document number).
  LOOP AT lt_res INTO ls_res.
    IF ls_res-msg_type <> 'S'.
      CONTINUE.
    ENDIF.

    IF ls_res-record_key IS NOT INITIAL.
      lv_group = ls_res-record_key.
    ELSE.
      CLEAR lv_row_key.
      WRITE ls_res-row_index TO lv_row_key LEFT-JUSTIFIED.
      CONDENSE lv_row_key NO-GAPS.
      lv_group = lv_row_key.
    ENDIF.
    IF lv_group <> is_exec-group_key.
      CONTINUE.
    ENDIF.

    CLEAR: lv_msgid, lv_msgnr, lv_v1, lv_v2, lv_v3, lv_v4, lv_any_v.
    PERFORM read_result_message_parts
      USING    ls_res
      CHANGING lv_msgid lv_msgnr lv_v1 lv_v2 lv_v3 lv_v4.

    IF lv_msgid IS INITIAL OR lv_msgnr IS INITIAL OR lv_msgid = 'ZBDC'.
      CONTINUE.
    ENDIF.
    IF lv_v1 IS NOT INITIAL OR lv_v2 IS NOT INITIAL OR
       lv_v3 IS NOT INITIAL OR lv_v4 IS NOT INITIAL.
      lv_any_v = abap_true.
    ENDIF.
    IF lv_any_v <> abap_true.
      CONTINUE.
    ENDIF.

    "Prefer the exact message currently displayed in the cockpit. Because the
    "result table is sorted newest-first, duplicate protocol rows remain
    "deterministic without inventing business semantics.
    IF is_exec-message IS NOT INITIAL AND ls_res-message = is_exec-message.
      cs_nav-msgid = lv_msgid.
      cs_nav-msgnr = lv_msgnr.
      cs_nav-message_text = ls_res-message.
      cs_nav-msgv1 = lv_v1.
      cs_nav-msgv2 = lv_v2.
      cs_nav-msgv3 = lv_v3.
      cs_nav-msgv4 = lv_v4.
      EXIT.
    ENDIF.

    "Compatibility fallback for older cockpit rows whose projected text was
    "truncated or normalized: remember only the newest structured S-message.
    IF lv_fallback_found <> abap_true.
      cs_nav-msgid = lv_msgid.
      cs_nav-msgnr = lv_msgnr.
      cs_nav-message_text = ls_res-message.
      cs_nav-msgv1 = lv_v1.
      cs_nav-msgv2 = lv_v2.
      cs_nav-msgv3 = lv_v3.
      cs_nav-msgv4 = lv_v4.
      lv_fallback_found = abap_true.
    ENDIF.
  ENDLOOP.

  IF cs_nav-msgid IS INITIAL OR cs_nav-msgnr IS INITIAL OR
     ( cs_nav-msgv1 IS INITIAL AND cs_nav-msgv2 IS INITIAL AND
       cs_nav-msgv3 IS INITIAL AND cs_nav-msgv4 IS INITIAL ).
    cv_message = 'No structured SAP SUCCESS message with navigation candidates could be proven for this row.'.
    RETURN.
  ENDIF.

  cs_nav-session_id    = ls_session-session_id.
  cs_nav-group_key     = is_exec-group_key.
  cs_nav-tcode         = ls_session-tcode.
  cs_nav-profile_name  = ls_session-profile_name.
  cs_nav-profile_ver   = ls_session-profile_ver.
  cs_nav-script_id     = ls_session-script_id.
  cs_nav-contract_hash = ls_session-contract_hash.
  cv_ok = abap_true.
ENDFORM.


*&---------------------------------------------------------------------*
*& Derive the object key from an already-certified exact SAP message
*& contract. This allows old SUCCESS rows to become clickable without
*& rewriting immutable execution/audit rows after the fact.
*&---------------------------------------------------------------------*
FORM nav_evidence_value
  USING    is_nav   TYPE ty_nav_evidence
           iv_idx   TYPE ty_nav_msgv_idx
  CHANGING cv_value TYPE string.

  CLEAR cv_value.
  CASE iv_idx.
    WHEN '1'. cv_value = is_nav-msgv1.
    WHEN '2'. cv_value = is_nav-msgv2.
    WHEN '3'. cv_value = is_nav-msgv3.
    WHEN '4'. cv_value = is_nav-msgv4.
  ENDCASE.
  CONDENSE cv_value.
ENDFORM.


*&---------------------------------------------------------------------*
*& Exact target-screen metadata for AI Navigation (generic)
*& Reads only SAP repository/Screen Painter metadata. No business TCODE,
*& field, table, label or key is hardcoded. The AI may select only from the
*& exact field/action evidence returned here.
*&---------------------------------------------------------------------*
FORM load_nav_screen_meta
  USING    iv_target    TYPE sy-tcode
  CHANGING cv_program   TYPE d020s-prog
           cv_dynpro    TYPE d020s-dnum
           ct_meta      TYPE ty_t_nav_screen_field
           cv_evidence  TYPE string
           cv_ok        TYPE abap_bool
           cv_message   TYPE string.

  DATA: ls_tstc      TYPE tstc,
        ls_head      TYPE d020s,
        ls_rpy_head  TYPE rpy_dyhead,
        lt_fld       TYPE STANDARD TABLE OF d021s,
        lt_flow      TYPE STANDARD TABLE OF d022s,
        lt_txt        TYPE STANDARD TABLE OF d021t,
        ls_fld       TYPE d021s,
        ls_txt        TYPE d021t,
        lt_ext        TYPE dyfatc_tab,
        ls_ext        TYPE rpy_dyfatc,
        ls_meta      TYPE ty_nav_screen_field,
        lv_pid_txt      TYPE string,
        lv_func_txt     TYPE string,
        lv_seq            TYPE i,
        lv_input_count    TYPE i,
        lv_bindable_count TYPE i,
        lv_rpy_input      TYPE abap_bool,
        lv_rpy_row_input  TYPE abap_bool,
        lv_d021_input     TYPE abap_bool,
        lv_requ_txt       TYPE string,
        lv_push_txt       TYPE string,
        lv_param_txt      TYPE string.

  CONSTANTS: lc_d021_edit    TYPE x VALUE '80',
             lc_d021_protect TYPE x VALUE '20'.

  FIELD-SYMBOLS: <lv_paid>       TYPE any,
                 <ls_res1>       TYPE any,
                 <lv_func>       TYPE any,
                 <lv_input_fld>  TYPE any,
                 <lv_outputonly> TYPE any,
                 <lv_invisible>  TYPE any,
                 <lv_requ_entry> TYPE any,
                 <lv_push_fcode> TYPE any,
                 <lv_param_id>   TYPE any.

  CLEAR: cv_program, cv_dynpro, ct_meta, cv_evidence, cv_ok, cv_message.

  SELECT SINGLE * FROM tstc
    INTO @ls_tstc
    WHERE tcode = @iv_target.
  IF sy-subrc <> 0.
    cv_message = |Navigation target { iv_target } does not exist in TSTC.|.
    RETURN.
  ENDIF.

  cv_program = ls_tstc-pgmna.
  cv_dynpro  = ls_tstc-dypno.
  CONDENSE: cv_program NO-GAPS, cv_dynpro NO-GAPS.
  IF cv_program IS INITIAL OR cv_dynpro IS INITIAL.
    cv_message = |Navigation target { iv_target } has no repository start PROGRAM/DYNPRO.|.
    RETURN.
  ENDIF.

  CLEAR ls_head.
  REFRESH: lt_fld, lt_flow.
  CALL FUNCTION 'RS_IMPORT_DYNPRO'
    EXPORTING
      dylang          = sy-langu
      dyname          = cv_program
      dynumb          = cv_dynpro
      request         = space
      suppress_checks = space
    IMPORTING
      header           = ls_head
    TABLES
      ftab             = lt_fld
      pltab            = lt_flow
    EXCEPTIONS
      OTHERS           = 1.
  IF sy-subrc <> 0 OR lt_fld IS INITIAL.
    cv_message = |Screen Painter metadata for { iv_target } { cv_program }/{ cv_dynpro } could not be imported.|.
    RETURN.
  ENDIF.

  "RPY_DYNPRO_READ supplies generic enterable/visible control attributes.
  "This is technical UI metadata only; no business field is recognized here.
  REFRESH lt_ext.
  CLEAR ls_rpy_head.
  CALL FUNCTION 'RPY_DYNPRO_READ'
    EXPORTING
      progname             = cv_program
      dynnr                = cv_dynpro
      suppress_corr_checks = 'X'
    IMPORTING
      header               = ls_rpy_head
    TABLES
      fields_to_containers = lt_ext
    EXCEPTIONS
      cancelled            = 1
      not_found            = 2
      permission_error     = 3
      OTHERS               = 4.
  IF sy-subrc <> 0.
    REFRESH lt_ext.
  ENDIF.

  REFRESH lt_txt.
  SELECT * FROM d021t
    INTO TABLE @lt_txt
    WHERE prog = @cv_program
      AND dynr = @cv_dynpro
      AND lang = @sy-langu.

  cv_evidence = |TARGET={ iv_target }; PROGRAM={ cv_program }; DYNPRO={ cv_dynpro }|.

  LOOP AT lt_fld INTO ls_fld.
    CLEAR: ls_meta, lv_pid_txt, lv_func_txt.

    ls_meta-field_name = ls_fld-fnam.
    CONDENSE ls_meta-field_name NO-GAPS.
    TRANSLATE ls_meta-field_name TO UPPER CASE.

    IF ls_meta-field_name IS NOT INITIAL.
      READ TABLE lt_txt INTO ls_txt WITH KEY fldn = ls_meta-field_name.
      IF sy-subrc = 0 AND ls_txt-dtxt IS NOT INITIAL.
        ls_meta-label = ls_txt-dtxt.
        CONDENSE ls_meta-label.
      ENDIF.
    ENDIF.
    IF ls_meta-label IS INITIAL AND ls_fld-stxt IS NOT INITIAL.
      ls_meta-label = ls_fld-stxt.
      CONDENSE ls_meta-label.
    ENDIF.

    "V17.8.8: one technical dynpro NAME may legitimately occur more than once
    "in RPY_DYNPRO_READ. A DDIC keyword/text element and its I/O TEMPLATE can
    "share the same NAME. Therefore a READ TABLE ... WITH KEY NAME is unsafe:
    "it can land on TEXT first and hide the real I/O field. Aggregate every
    "external element with the exact NAME and accept the NAME when ANY matching
    "element is a real SAP I/O class. No business TCODE/field mapping is used.
    "INPUT_OK remains only a preference; the visible CALL TRANSACTION probe and
    "explicit Certify/Reject are the final runtime proof.
    CLEAR: lv_rpy_input, lv_rpy_row_input, lv_d021_input,
           lv_requ_txt, lv_push_txt, lv_param_txt.

    IF ls_meta-field_name IS NOT INITIAL.
      LOOP AT lt_ext INTO ls_ext WHERE name = ls_meta-field_name.
        CLEAR: lv_rpy_row_input, lv_requ_txt, lv_push_txt, lv_param_txt.

        "Keep action metadata even when this occurrence is a pushbutton rather
        "than the I/O occurrence sharing the same technical NAME.
        UNASSIGN: <lv_push_fcode>, <lv_param_id>.
        ASSIGN COMPONENT 'PUSH_FCODE' OF STRUCTURE ls_ext TO <lv_push_fcode>.
        ASSIGN COMPONENT 'PARAM_ID'   OF STRUCTURE ls_ext TO <lv_param_id>.

        IF <lv_push_fcode> IS ASSIGNED AND <lv_push_fcode> IS NOT INITIAL.
          lv_push_txt = <lv_push_fcode>.
          CONDENSE lv_push_txt NO-GAPS.
          IF strlen( lv_push_txt ) <= 20.
            ls_meta-func_code = lv_push_txt.
          ENDIF.
        ENDIF.

        "SAP external screen element types that carry a dynpro value. A listbox
        "is represented as TEMPLATE plus its DROPDOWN attribute, so no invented
        "DROPDOWN TYPE is required here.
        IF ls_ext-type <> 'TEMPLATE' AND ls_ext-type <> 'RADIO'
           AND ls_ext-type <> 'CHECK'.
          CONTINUE.
        ENDIF.

        ls_meta-bindable = abap_true.
        ls_meta-field_type = ls_ext-type.
        TRANSLATE ls_meta-field_type TO UPPER CASE.
        CONDENSE ls_meta-field_type NO-GAPS.

        UNASSIGN: <lv_input_fld>, <lv_outputonly>, <lv_invisible>,
                  <lv_requ_entry>.
        ASSIGN COMPONENT 'INPUT_FLD'  OF STRUCTURE ls_ext TO <lv_input_fld>.
        ASSIGN COMPONENT 'OUTPUTONLY' OF STRUCTURE ls_ext TO <lv_outputonly>.
        ASSIGN COMPONENT 'INVISIBLE'  OF STRUCTURE ls_ext TO <lv_invisible>.
        ASSIGN COMPONENT 'REQU_ENTRY' OF STRUCTURE ls_ext TO <lv_requ_entry>.

        IF <lv_requ_entry> IS ASSIGNED.
          lv_requ_txt = <lv_requ_entry>.
          TRANSLATE lv_requ_txt TO UPPER CASE.
          CONDENSE lv_requ_txt NO-GAPS.
          IF strlen( lv_requ_txt ) <= 1.
            ls_meta-entry_state = lv_requ_txt.
          ENDIF.
        ENDIF.

        "Static input proof is evaluated PER I/O occurrence and then OR'ed.
        "A TEXT occurrence with the same NAME can no longer clear this proof.
        IF <lv_input_fld> IS ASSIGNED AND <lv_input_fld> IS NOT INITIAL.
          lv_rpy_row_input = abap_true.
        ENDIF.
        IF <lv_requ_entry> IS ASSIGNED AND lv_requ_txt <> 'N'.
          lv_rpy_row_input = abap_true.
        ENDIF.
        IF <lv_invisible> IS ASSIGNED AND <lv_invisible> IS NOT INITIAL.
          CLEAR lv_rpy_row_input.
        ENDIF.
        IF <lv_outputonly> IS ASSIGNED AND <lv_outputonly> IS NOT INITIAL.
          CLEAR lv_rpy_row_input.
        ENDIF.
        IF lv_rpy_row_input = abap_true.
          lv_rpy_input = abap_true.
        ENDIF.

        "Prefer the parameter ID carried by the actual I/O occurrence.
        IF <lv_param_id> IS ASSIGNED AND <lv_param_id> IS NOT INITIAL.
          lv_param_txt = <lv_param_id>.
          TRANSLATE lv_param_txt TO UPPER CASE.
          CONDENSE lv_param_txt NO-GAPS.
          IF strlen( lv_param_txt ) <= 20.
            ls_meta-param_id = lv_param_txt.
          ENDIF.
        ENDIF.
      ENDLOOP.

      "Classic-repository fallback. If RPY does not expose an I/O occurrence,
      "D021S edit/protect bits may still prove the exact named dynpro field is
      "statically input-ready. This fallback never promotes a known RPY text/
      "frame/push element by itself; it only applies to the imported D021S row.
      IF ls_meta-bindable <> abap_true
         AND ls_fld-flg1 O lc_d021_edit
         AND ls_fld-fmb1 Z lc_d021_protect.
        lv_d021_input = abap_true.
        ls_meta-bindable = abap_true.
        IF ls_meta-field_type IS INITIAL.
          ls_meta-field_type = 'D021_IO'.
        ENDIF.
      ENDIF.

      IF lv_rpy_input = abap_true OR lv_d021_input = abap_true.
        ls_meta-input_ok = abap_true.
        lv_input_count = lv_input_count + 1.
      ENDIF.
      IF ls_meta-bindable = abap_true.
        lv_bindable_count = lv_bindable_count + 1.
      ENDIF.
    ENDIF.

    UNASSIGN <lv_paid>.
    ASSIGN COMPONENT 'PAID' OF STRUCTURE ls_fld TO <lv_paid>.
    IF sy-subrc = 0 AND <lv_paid> IS ASSIGNED.
      lv_pid_txt = <lv_paid>.
      TRANSLATE lv_pid_txt TO UPPER CASE.
      CONDENSE lv_pid_txt NO-GAPS.
      IF strlen( lv_pid_txt ) <= 20 AND ls_meta-param_id IS INITIAL.
        ls_meta-param_id = lv_pid_txt.
      ENDIF.
    ENDIF.

    UNASSIGN: <ls_res1>, <lv_func>.
    ASSIGN COMPONENT 'RES1' OF STRUCTURE ls_fld TO <ls_res1>.
    IF sy-subrc = 0 AND <ls_res1> IS ASSIGNED.
      ASSIGN COMPONENT 'FUNCCODE' OF STRUCTURE <ls_res1> TO <lv_func>.
      IF sy-subrc = 0 AND <lv_func> IS ASSIGNED.
        lv_func_txt = <lv_func>.
        CONDENSE lv_func_txt NO-GAPS.
        IF strlen( lv_func_txt ) <= 20 AND ls_meta-func_code IS INITIAL.
          ls_meta-func_code = lv_func_txt.
        ENDIF.
      ENDIF.
    ENDIF.

    IF ls_meta-field_name IS INITIAL AND ls_meta-label IS INITIAL
       AND ls_meta-param_id IS INITIAL AND ls_meta-func_code IS INITIAL.
      CONTINUE.
    ENDIF.

    lv_seq = lv_seq + 1.
    ls_meta-seq = lv_seq.
    APPEND ls_meta TO ct_meta.

    cv_evidence = cv_evidence && cl_abap_char_utilities=>newline &&
      |E{ lv_seq }; FIELD={ ls_meta-field_name }; TYPE={ ls_meta-field_type }; BINDABLE={ ls_meta-bindable }; INPUT={ ls_meta-input_ok }; ENTRY={ ls_meta-entry_state }; LABEL={ ls_meta-label }; PID={ ls_meta-param_id }; ACTION={ ls_meta-func_code }|.
  ENDLOOP.

  IF ct_meta IS INITIAL.
    cv_message = |No usable Screen Painter element metadata was found for { iv_target }.|.
    RETURN.
  ENDIF.

  IF lv_bindable_count <= 0.
    cv_message =
      |SAP repository metadata contains no structurally bindable I/O field on { iv_target } { cv_program }/{ cv_dynpro }.|.
    RETURN.
  ENDIF.

  "A shared dynpro may make fields input-ready only at runtime in PBO. Keep the
  "exact repository I/O candidates and let the visible BDC probe + user
  "Certify/Reject establish the runtime truth instead of falsely blocking here.
  IF lv_input_count <= 0.
    cv_evidence = cv_evidence && cl_abap_char_utilities=>newline &&
      |STATIC_INPUT_NOTE=0 statically proven input fields; { lv_bindable_count } exact I/O field(s) remain runtime-probe candidates.|.
  ENDIF.

  "Universal SAP GUI Enter is an exact BDC control action, not business logic.
  cv_evidence = cv_evidence && cl_abap_char_utilities=>newline &&
                'ACTION=/00; LABEL=SAP standard Enter'.

  cv_ok = abap_true.
  cv_message =
    |Loaded { lines( ct_meta ) } Screen Painter element(s), { lv_bindable_count } bindable, { lv_input_count } statically input-ready, for { iv_target }.|.
ENDFORM.

*&---------------------------------------------------------------------*
*& Load a certified generic navigation binding contract.
*& V17.8.6 supports 1..4 exact MSGV -> SPA/GPA PID bindings. Old single-key
*& NAVMSGV/NAVPID certificates remain readable when NAVCOUNT is absent.
*&---------------------------------------------------------------------*
FORM load_nav_binding_contract
  USING    iv_script_id TYPE zbdc_script_bup-script_id
  CHANGING cv_navstate  TYPE zbdc_config_bup-config_value
           cv_target    TYPE sy-tcode
           cv_program   TYPE d020s-prog
           cv_dynpro    TYPE d020s-dnum
           cv_action    TYPE syucomm
           cv_msgid     TYPE symsgid
           cv_msgnr     TYPE symsgno
           ct_binding   TYPE ty_t_nav_binding
           cv_ok        TYPE abap_bool
           cv_message   TYPE string.

  DATA: lv_mode       TYPE zbdc_config_bup-config_value,
        lv_cfg_target TYPE zbdc_config_bup-config_value,
        lv_cfg_prog   TYPE zbdc_config_bup-config_value,
        lv_cfg_dyn    TYPE zbdc_config_bup-config_value,
        lv_cfg_action TYPE zbdc_config_bup-config_value,
        lv_cfg_msgid  TYPE zbdc_config_bup-config_value,
        lv_cfg_msgnr  TYPE zbdc_config_bup-config_value,
        lv_cfg_count  TYPE zbdc_config_bup-config_value,
        lv_cfg_msgv   TYPE zbdc_config_bup-config_value,
        lv_cfg_src    TYPE zbdc_config_bup-config_value,
        lv_cfg_field  TYPE zbdc_config_bup-config_value,
        lv_cfg_pid    TYPE zbdc_config_bup-config_value,
        lv_kind       TYPE c LENGTH 20,
        lv_idx_text   TYPE c LENGTH 1,
        lv_count      TYPE i,
        lv_i          TYPE i,
        ls_binding    TYPE ty_nav_binding.

  CLEAR: cv_navstate, cv_target, cv_program, cv_dynpro, cv_action,
         cv_msgid, cv_msgnr, ct_binding, cv_ok, cv_message.

  PERFORM get_script_cfg USING iv_script_id 'NAVSTATE'  CHANGING cv_navstate.
  PERFORM get_script_cfg USING iv_script_id 'NAVMODE'   CHANGING lv_mode.
  PERFORM get_script_cfg USING iv_script_id 'NAVTCODE'  CHANGING lv_cfg_target.
  PERFORM get_script_cfg USING iv_script_id 'NAVPROG'   CHANGING lv_cfg_prog.
  PERFORM get_script_cfg USING iv_script_id 'NAVDYN'    CHANGING lv_cfg_dyn.
  PERFORM get_script_cfg USING iv_script_id 'NAVACTION' CHANGING lv_cfg_action.
  PERFORM get_script_cfg USING iv_script_id 'NAVMSGID'  CHANGING lv_cfg_msgid.
  PERFORM get_script_cfg USING iv_script_id 'NAVMSGNR'  CHANGING lv_cfg_msgnr.
  PERFORM get_script_cfg USING iv_script_id 'NAVCOUNT'  CHANGING lv_cfg_count.

  TRANSLATE: cv_navstate TO UPPER CASE, lv_mode TO UPPER CASE,
             lv_cfg_target TO UPPER CASE, lv_cfg_prog TO UPPER CASE,
             lv_cfg_action TO UPPER CASE, lv_cfg_msgid TO UPPER CASE.
  CONDENSE: cv_navstate NO-GAPS, lv_mode NO-GAPS,
            lv_cfg_target NO-GAPS, lv_cfg_prog NO-GAPS,
            lv_cfg_dyn NO-GAPS, lv_cfg_action NO-GAPS,
            lv_cfg_msgid NO-GAPS, lv_cfg_msgnr NO-GAPS,
            lv_cfg_count NO-GAPS.

  IF cv_navstate <> 'CERTIFIED'.
    cv_message = 'Navigation route is not CERTIFIED.'.
    RETURN.
  ENDIF.

  "Accept the two exact 17.9.3.4 route families. Older 17.9.3.4 PARAM
  "certificates were stored as SCREEN_BDC with NAVACTION=@PARAM; keep those
  "readable so the user does not have to re-certify an already verified route.
  IF lv_mode <> 'SCREEN_BDC' AND lv_mode <> 'PARAM_MEMORY'.
    cv_message = 'Certified navigation route uses an unsupported legacy contract and must be rediscovered once.'.
    RETURN.
  ENDIF.

  "V17.9.3.4 route-state fix: PARAM-memory routes are not classic dynpro
  "contracts. They need an exact target/action/message/binding certificate,
  "but PROGRAM/DYNPRO are not runtime prerequisites for SET PARAMETER + CALL
  "TRANSACTION. Existing 17.9.3.4 certificates wrote NAVMODE=SCREEN_BDC even
  "for @PARAM, so keep them backward-compatible by keying off NAVACTION.
  IF lv_cfg_target IS INITIAL OR lv_cfg_action IS INITIAL OR
     lv_cfg_msgid IS INITIAL OR lv_cfg_msgnr IS INITIAL.
    cv_message = 'Certified navigation contract is incomplete.'.
    RETURN.
  ENDIF.
  IF lv_cfg_action <> '@PARAM' AND
     ( lv_cfg_prog IS INITIAL OR lv_cfg_dyn IS INITIAL ).
    cv_message = 'Certified screen-navigation contract is missing its exact target screen.'.
    RETURN.
  ENDIF.

  TRY.
      lv_count = lv_cfg_count.
    CATCH cx_sy_conversion_no_number cx_sy_conversion_overflow.
      cv_message = 'Certified NAVCOUNT is not numeric.'.
      RETURN.
  ENDTRY.
  IF lv_count < 1 OR lv_count > 4.
    cv_message = 'Certified navigation binding count is outside 1..4.'.
    RETURN.
  ENDIF.

  cv_target  = lv_cfg_target.
  cv_program = lv_cfg_prog.
  cv_dynpro  = lv_cfg_dyn.
  cv_action  = lv_cfg_action.
  cv_msgid   = lv_cfg_msgid.
  cv_msgnr   = lv_cfg_msgnr.

  DO lv_count TIMES.
    lv_i = sy-index.
    lv_idx_text = lv_i.
    CONDENSE lv_idx_text NO-GAPS.
    CLEAR: lv_cfg_msgv, lv_cfg_src, lv_cfg_field, lv_cfg_pid, lv_kind, ls_binding.

    "V17.9.3.4 evidence-save fix: NAVSRCn is the canonical compact
    "MSGV-slot certificate. It is written only after live Certify and is
    "read before the older NAVMSGVn key so stale legacy rows cannot shadow
    "the exact source index. Older certificates remain compatible.
    CONCATENATE 'NAVSRC' lv_idx_text INTO lv_kind.
    PERFORM get_script_cfg USING iv_script_id lv_kind CHANGING lv_cfg_src.
    CLEAR lv_kind.
    IF lv_cfg_src IS NOT INITIAL.
      lv_cfg_msgv = lv_cfg_src.
    ELSE.
      CONCATENATE 'NAVMSGV' lv_idx_text INTO lv_kind.
      PERFORM get_script_cfg USING iv_script_id lv_kind CHANGING lv_cfg_msgv.
      CLEAR lv_kind.
    ENDIF.
    CONCATENATE 'NAVFIELD' lv_idx_text INTO lv_kind.
    PERFORM get_script_cfg USING iv_script_id lv_kind CHANGING lv_cfg_field.
    CLEAR lv_kind.
    CONCATENATE 'NAVPID' lv_idx_text INTO lv_kind.
    PERFORM get_script_cfg USING iv_script_id lv_kind CHANGING lv_cfg_pid.

    TRANSLATE: lv_cfg_msgv TO UPPER CASE,
               lv_cfg_field TO UPPER CASE, lv_cfg_pid TO UPPER CASE.
    CONDENSE: lv_cfg_msgv NO-GAPS, lv_cfg_field NO-GAPS, lv_cfg_pid NO-GAPS.

    "V17.9.3.4 stable MSGV-source normalization. Indexed certificates use
    "the compact value 1..4, while some already-persisted revisions used the
    "explicit token MSGV1..MSGV4. Both mean the same exact structured SAP
    "message slot, so normalize the proven legacy spelling instead of
    "downgrading a route that the user has already live-certified.
    IF strlen( lv_cfg_msgv ) = 5 AND lv_cfg_msgv(4) = 'MSGV' AND
       lv_cfg_msgv+4(1) CO '1234'.
      lv_cfg_msgv = lv_cfg_msgv+4(1).
    ENDIF.

    "The reusable route definition (target fields/PIDs) and the current
    "execution evidence are deliberately separate. If an older NAVMSGVn row
    "is missing/corrupt, keep the certified structural route and leave the
    "source blank. The exact tagged SUCCESS row can deterministically recover
    "the source tuple later; ambiguity still fails closed.
    IF lv_cfg_msgv CN '1234' OR strlen( lv_cfg_msgv ) <> 1.
      CLEAR lv_cfg_msgv.
    ENDIF.

    IF lv_cfg_msgv IS NOT INITIAL.
      READ TABLE ct_binding TRANSPORTING NO FIELDS WITH KEY msgv_idx = lv_cfg_msgv.
      IF sy-subrc = 0.
        cv_message = 'Certified navigation contract repeats one MSGV source.'.
        CLEAR ct_binding.
        RETURN.
      ENDIF.
    ENDIF.

    ls_binding-seq      = lv_i.
    ls_binding-msgv_idx = lv_cfg_msgv.

    IF lv_cfg_action = '@PARAM'.
      IF lv_cfg_pid IS INITIAL OR strlen( lv_cfg_pid ) > 20.
        cv_message = |Certified parameter-memory binding { lv_i } has no valid repository-proven PID.|.
        CLEAR ct_binding.
        RETURN.
      ENDIF.

      READ TABLE ct_binding TRANSPORTING NO FIELDS WITH KEY param_id = lv_cfg_pid.
      IF sy-subrc = 0.
        cv_message = 'Certified parameter-memory contract repeats one SPA/GPA PID.'.
        CLEAR ct_binding.
        RETURN.
      ENDIF.

      "Normalize the in-memory binding marker. NAVFIELDn is deliberately not
      "a persistence prerequisite for @PARAM routes.
      ls_binding-field_name = '@PARAM'.
      ls_binding-param_id   = lv_cfg_pid.
    ELSE.
      IF lv_cfg_field IS INITIAL.
        cv_message = |Certified screen navigation binding { lv_i } has no target field.|.
        CLEAR ct_binding.
        RETURN.
      ENDIF.

      READ TABLE ct_binding TRANSPORTING NO FIELDS WITH KEY field_name = lv_cfg_field.
      IF sy-subrc = 0.
        cv_message = 'Certified navigation contract repeats one target screen field.'.
        CLEAR ct_binding.
        RETURN.
      ENDIF.

      ls_binding-field_name = lv_cfg_field.
      IF strlen( lv_cfg_pid ) <= 20.
        ls_binding-param_id = lv_cfg_pid.
      ENDIF.
    ENDIF.

    APPEND ls_binding TO ct_binding.
  ENDDO.

  cv_ok = abap_true.
ENDFORM.

*&---------------------------------------------------------------------*
*& Rehydrate one legacy PARAM_MEMORY MSGV source from exact certified evidence.
*& The only accepted proof is one persisted SUCCESS message row already tagged
*& with the exact SAP_OBJECT_ID during the user's visible Certify step. Exactly
*& one MSGV1..MSGV4 slot must equal that persisted object; ties fail closed.
*&---------------------------------------------------------------------*
FORM hydrate_param_msgv
  USING    is_exec     TYPE ty_exec_disp
           it_res      TYPE ty_t_result
           iv_msgid    TYPE symsgid
           iv_msgnr    TYPE symsgno
           iv_expected TYPE zbdc_result_bup-sap_object_id
  CHANGING ct_binding  TYPE ty_t_nav_binding
           cv_ok       TYPE abap_bool
           cv_message  TYPE string.

  DATA: ls_binding TYPE ty_nav_binding,
        ls_res     TYPE zbdc_result_bup,
        lv_group   TYPE string,
        lv_row_key TYPE char40,
        lv_msgid   TYPE symsgid,
        lv_msgnr   TYPE symsgno,
        lv_v1      TYPE string,
        lv_v2      TYPE string,
        lv_v3      TYPE string,
        lv_v4      TYPE string,
        lv_idx     TYPE ty_nav_msgv_idx,
        lv_found   TYPE ty_nav_msgv_idx,
        lv_matches TYPE i.

  CLEAR: cv_ok, cv_message.
  IF lines( ct_binding ) <> 1 OR iv_expected IS INITIAL.
    cv_message = 'Legacy parameter-memory binding cannot be rehydrated uniquely.'.
    RETURN.
  ENDIF.

  READ TABLE ct_binding INTO ls_binding INDEX 1.
  IF sy-subrc <> 0 OR ls_binding-param_id IS INITIAL.
    cv_message = 'Certified parameter-memory PID is unavailable.'.
    RETURN.
  ENDIF.

  IF ls_binding-msgv_idx CO '1234' AND strlen( ls_binding-msgv_idx ) = 1.
    cv_ok = abap_true.
    RETURN.
  ENDIF.

  LOOP AT it_res INTO ls_res.
    IF ls_res-session_id <> is_exec-session_id OR
       ls_res-msg_type <> 'S' OR
       ls_res-sap_object_id <> iv_expected.
      CONTINUE.
    ENDIF.

    IF ls_res-record_key IS NOT INITIAL.
      lv_group = ls_res-record_key.
    ELSE.
      CLEAR lv_row_key.
      WRITE ls_res-row_index TO lv_row_key LEFT-JUSTIFIED.
      CONDENSE lv_row_key NO-GAPS.
      lv_group = lv_row_key.
    ENDIF.
    IF lv_group <> is_exec-group_key.
      CONTINUE.
    ENDIF.

    CLEAR: lv_msgid, lv_msgnr, lv_v1, lv_v2, lv_v3, lv_v4.
    PERFORM read_result_message_parts
      USING    ls_res
      CHANGING lv_msgid lv_msgnr lv_v1 lv_v2 lv_v3 lv_v4.
    IF lv_msgid <> iv_msgid OR lv_msgnr <> iv_msgnr.
      CONTINUE.
    ENDIF.

    CLEAR: lv_idx, lv_matches.
    CONDENSE: lv_v1, lv_v2, lv_v3, lv_v4.
    IF lv_v1 = iv_expected. lv_idx = '1'. lv_matches = lv_matches + 1. ENDIF.
    IF lv_v2 = iv_expected. lv_idx = '2'. lv_matches = lv_matches + 1. ENDIF.
    IF lv_v3 = iv_expected. lv_idx = '3'. lv_matches = lv_matches + 1. ENDIF.
    IF lv_v4 = iv_expected. lv_idx = '4'. lv_matches = lv_matches + 1. ENDIF.
    IF lv_matches <> 1.
      CONTINUE.
    ENDIF.

    IF lv_found IS INITIAL.
      lv_found = lv_idx.
    ELSEIF lv_found <> lv_idx.
      cv_message = 'Persisted certified SUCCESS evidence points to more than one MSGV slot.'.
      RETURN.
    ENDIF.
  ENDLOOP.

  IF lv_found IS INITIAL.
    cv_message = 'No exact certified SUCCESS row proves the missing parameter-memory MSGV slot.'.
    RETURN.
  ENDIF.

  ls_binding-msgv_idx = lv_found.
  ls_binding-value = iv_expected.
  MODIFY ct_binding FROM ls_binding INDEX 1.
  cv_ok = abap_true.
ENDFORM.

*&---------------------------------------------------------------------*
*& Recover missing MSGV source indexes from exact tagged SUCCESS evidence.
*& No message text parsing and no business/TCode rule is used. The current
*& persisted SAP_OBJECT_ID must equal exactly one ordered tuple of distinct
*& non-empty MSGV1..4 values, in the same binding order certified by the user.
*& Existing valid source indexes are treated as hard constraints.
*&---------------------------------------------------------------------*
FORM recover_nav_sources
  USING    is_exec     TYPE ty_exec_disp
           it_res      TYPE ty_t_result
           iv_msgid    TYPE symsgid
           iv_msgnr    TYPE symsgno
           iv_expected TYPE zbdc_result_bup-sap_object_id
  CHANGING ct_binding  TYPE ty_t_nav_binding
           cv_ok       TYPE abap_bool
           cv_message  TYPE string.

  DATA: ls_res         TYPE zbdc_result_bup,
        ls_binding     TYPE ty_nav_binding,
        lv_group       TYPE string,
        lv_row_key     TYPE char40,
        lv_msgid       TYPE symsgid,
        lv_msgnr       TYPE symsgno,
        lv_v1          TYPE string,
        lv_v2          TYPE string,
        lv_v3          TYPE string,
        lv_v4          TYPE string,
        lv_f1          TYPE string,
        lv_f2          TYPE string,
        lv_f3          TYPE string,
        lv_f4          TYPE string,
        lv_count       TYPE i,
        lv_combo_count TYPE i,
        lv_code        TYPE i,
        lv_work_code   TYPE i,
        lv_pos         TYPE i,
        lv_slot_num    TYPE i,
        lv_slot        TYPE ty_nav_msgv_idx,
        lv_value       TYPE string,
        lv_tuple       TYPE string,
        lv_sig         TYPE c LENGTH 4,
        lv_found_sig   TYPE c LENGTH 4,
        lv_invalid     TYPE abap_bool,
        lv_off         TYPE i,
        lt_used        TYPE SORTED TABLE OF ty_nav_msgv_idx
                       WITH UNIQUE KEY table_line.

  CLEAR: cv_ok, cv_message, lv_found_sig.
  lv_count = lines( ct_binding ).
  IF lv_count < 1 OR lv_count > 4 OR iv_expected IS INITIAL.
    cv_message = 'Certified navigation sources cannot be recovered because the exact binding/object evidence is incomplete.'.
    RETURN.
  ENDIF.

  LOOP AT it_res INTO ls_res.
    IF ls_res-session_id <> is_exec-session_id OR
       ls_res-msg_type <> 'S' OR
       ls_res-sap_object_id <> iv_expected.
      CONTINUE.
    ENDIF.

    IF ls_res-record_key IS NOT INITIAL.
      lv_group = ls_res-record_key.
    ELSE.
      CLEAR lv_row_key.
      WRITE ls_res-row_index TO lv_row_key LEFT-JUSTIFIED.
      CONDENSE lv_row_key NO-GAPS.
      lv_group = lv_row_key.
    ENDIF.
    IF lv_group <> is_exec-group_key.
      CONTINUE.
    ENDIF.

    CLEAR: lv_msgid, lv_msgnr, lv_v1, lv_v2, lv_v3, lv_v4.
    PERFORM read_result_message_parts
      USING    ls_res
      CHANGING lv_msgid lv_msgnr lv_v1 lv_v2 lv_v3 lv_v4.
    IF lv_msgid <> iv_msgid OR lv_msgnr <> iv_msgnr.
      CONTINUE.
    ENDIF.
    CONDENSE: lv_v1, lv_v2, lv_v3, lv_v4.

    lv_combo_count = 1.
    DO lv_count TIMES.
      lv_combo_count = lv_combo_count * 4.
    ENDDO.

    DO lv_combo_count TIMES.
      lv_code = sy-index - 1.
      lv_work_code = lv_code.
      CLEAR: lv_tuple, lv_sig, lv_invalid.
      REFRESH lt_used.

      DO lv_count TIMES.
        lv_pos = sy-index.
        lv_slot_num = lv_work_code MOD 4.
        lv_slot_num = lv_slot_num + 1.
        lv_work_code = lv_work_code DIV 4.
        lv_slot = lv_slot_num.
        CONDENSE lv_slot NO-GAPS.

        INSERT lv_slot INTO TABLE lt_used.
        IF sy-subrc <> 0.
          lv_invalid = abap_true.
          EXIT.
        ENDIF.

        READ TABLE ct_binding INTO ls_binding INDEX lv_pos.
        IF sy-subrc <> 0.
          lv_invalid = abap_true.
          EXIT.
        ENDIF.
        IF ls_binding-msgv_idx CO '1234' AND
           strlen( ls_binding-msgv_idx ) = 1 AND
           ls_binding-msgv_idx <> lv_slot.
          lv_invalid = abap_true.
          EXIT.
        ENDIF.

        CLEAR lv_value.
        CASE lv_slot.
          WHEN '1'. lv_value = lv_v1.
          WHEN '2'. lv_value = lv_v2.
          WHEN '3'. lv_value = lv_v3.
          WHEN '4'. lv_value = lv_v4.
        ENDCASE.
        CONDENSE lv_value.
        IF lv_value IS INITIAL.
          lv_invalid = abap_true.
          EXIT.
        ENDIF.

        CONCATENATE lv_sig lv_slot INTO lv_sig.
        IF lv_tuple IS INITIAL.
          lv_tuple = lv_value.
        ELSE.
          lv_tuple = |{ lv_tuple }/{ lv_value }|.
        ENDIF.
      ENDDO.

      IF lv_invalid = abap_true OR lv_tuple <> iv_expected.
        CONTINUE.
      ENDIF.

      IF lv_found_sig IS INITIAL.
        lv_found_sig = lv_sig.
        lv_f1 = lv_v1.
        lv_f2 = lv_v2.
        lv_f3 = lv_v3.
        lv_f4 = lv_v4.
      ELSEIF lv_found_sig <> lv_sig.
        cv_message = 'Persisted certified SUCCESS evidence allows more than one MSGV source tuple; navigation remains fail-closed.'.
        RETURN.
      ENDIF.
    ENDDO.
  ENDLOOP.

  IF lv_found_sig IS INITIAL.
    cv_message = 'No unique ordered MSGV source tuple reproduces the persisted certified SAP object.'.
    RETURN.
  ENDIF.

  LOOP AT ct_binding INTO ls_binding.
    lv_off = sy-tabix - 1.
    lv_slot = lv_found_sig+lv_off(1).
    CLEAR lv_value.
    CASE lv_slot.
      WHEN '1'. lv_value = lv_f1.
      WHEN '2'. lv_value = lv_f2.
      WHEN '3'. lv_value = lv_f3.
      WHEN '4'. lv_value = lv_f4.
    ENDCASE.
    CONDENSE lv_value.
    IF lv_value IS INITIAL.
      cv_message = 'Recovered MSGV source points to an empty persisted SAP value.'.
      RETURN.
    ENDIF.
    ls_binding-msgv_idx = lv_slot.
    ls_binding-value    = lv_value.
    MODIFY ct_binding FROM ls_binding INDEX sy-tabix.
  ENDLOOP.

  cv_ok = abap_true.
  cv_message = 'Exact MSGV source tuple recovered from the tagged persisted SAP SUCCESS evidence.'.
ENDFORM.

*&---------------------------------------------------------------------*
*& Persist canonical source indexes after a proven/live-certified route.
*& NAVSRCn is the primary compact certificate; NAVMSGVn is maintained for
*& backward compatibility with earlier 17.9.3.4 revisions.
*&---------------------------------------------------------------------*
FORM save_nav_sources
  USING    iv_script_id TYPE zbdc_script_bup-script_id
           it_binding   TYPE ty_t_nav_binding
  CHANGING cv_ok        TYPE abap_bool
           cv_message   TYPE string.

  DATA: ls_binding TYPE ty_nav_binding,
        lv_seq_txt TYPE c LENGTH 1,
        lv_kind    TYPE c LENGTH 20,
        lv_ok      TYPE abap_bool,
        lv_msg     TYPE string.

  CLEAR: cv_ok, cv_message.
  LOOP AT it_binding INTO ls_binding.
    IF ls_binding-seq < 1 OR ls_binding-seq > 4 OR
       ls_binding-msgv_idx CN '1234' OR
       strlen( ls_binding-msgv_idx ) <> 1.
      cv_message = 'A certified navigation source index is invalid; route evidence was not persisted.'.
      RETURN.
    ENDIF.

    lv_seq_txt = ls_binding-seq.
    CONDENSE lv_seq_txt NO-GAPS.

    CLEAR lv_kind.
    CONCATENATE 'NAVSRC' lv_seq_txt INTO lv_kind.
    PERFORM set_script_cfg
      USING    iv_script_id lv_kind ls_binding-msgv_idx
      CHANGING lv_ok lv_msg.
    IF lv_ok <> abap_true.
      cv_message = lv_msg.
      RETURN.
    ENDIF.

    CLEAR lv_kind.
    CONCATENATE 'NAVMSGV' lv_seq_txt INTO lv_kind.
    PERFORM set_script_cfg
      USING    iv_script_id lv_kind ls_binding-msgv_idx
      CHANGING lv_ok lv_msg.
    IF lv_ok <> abap_true.
      cv_message = lv_msg.
      RETURN.
    ENDIF.
  ENDLOOP.

  cv_ok = abap_true.
ENDFORM.

*&---------------------------------------------------------------------*
*& Read-after-write verification. NAVSTATE may become CERTIFIED only when
*& every compact source certificate can be read back exactly as written.
*&---------------------------------------------------------------------*
FORM verify_nav_sources
  USING    iv_script_id TYPE zbdc_script_bup-script_id
           it_binding   TYPE ty_t_nav_binding
  CHANGING cv_ok        TYPE abap_bool
           cv_message   TYPE string.

  DATA: ls_binding TYPE ty_nav_binding,
        lv_seq_txt TYPE c LENGTH 1,
        lv_kind    TYPE c LENGTH 20,
        lv_cfg     TYPE zbdc_config_bup-config_value.

  CLEAR: cv_ok, cv_message.
  LOOP AT it_binding INTO ls_binding.
    lv_seq_txt = ls_binding-seq.
    CONDENSE lv_seq_txt NO-GAPS.
    CLEAR: lv_kind, lv_cfg.
    CONCATENATE 'NAVSRC' lv_seq_txt INTO lv_kind.
    PERFORM get_script_cfg USING iv_script_id lv_kind CHANGING lv_cfg.
    TRANSLATE lv_cfg TO UPPER CASE.
    CONDENSE lv_cfg NO-GAPS.
    IF lv_cfg <> ls_binding-msgv_idx.
      cv_message = |Certified navigation source { lv_seq_txt } could not be read back exactly; NAVSTATE was not committed.|.
      RETURN.
    ENDIF.
  ENDLOOP.

  cv_ok = abap_true.
ENDFORM.

*&---------------------------------------------------------------------*
*& Resolve the exact value tuple for one execution row from the certified
*& MSGID/MSGNR + MSGV binding contract. Different tuples inside one group are
*& treated as ambiguous rather than guessed.
*&---------------------------------------------------------------------*
FORM resolve_nav_bindings_for_exec
  USING    is_exec      TYPE ty_exec_disp
           it_res       TYPE ty_t_result
           iv_msgid     TYPE symsgid
           iv_msgnr     TYPE symsgno
           iv_expected  TYPE zbdc_result_bup-sap_object_id
  CHANGING ct_binding   TYPE ty_t_nav_binding
           cv_object    TYPE zbdc_result_bup-sap_object_id
           cv_tuple_txt TYPE string
           cv_ok        TYPE abap_bool
           cv_message   TYPE string.

  DATA: ls_res       TYPE zbdc_result_bup,
        lv_group     TYPE string,
        lv_row_key   TYPE char40,
        lv_msgid     TYPE symsgid,
        lv_msgnr     TYPE symsgno,
        lv_v1        TYPE string,
        lv_v2        TYPE string,
        lv_v3        TYPE string,
        lv_v4        TYPE string,
        lt_candidate TYPE ty_t_nav_binding,
        ls_binding   TYPE ty_nav_binding,
        lv_value     TYPE string,
        lv_tuple     TYPE string,
        lv_audit     TYPE string,
        lv_first     TYPE string,
        lv_cap       TYPE i,
        lv_bad       TYPE abap_bool,
        lv_tagged_found TYPE abap_bool,
        lv_untagged_ambig TYPE abap_bool.

  CLEAR: cv_object, cv_tuple_txt, cv_ok, cv_message, lv_first,
         lv_tagged_found, lv_untagged_ambig.

  LOOP AT it_res INTO ls_res.
    IF ls_res-session_id <> is_exec-session_id OR ls_res-msg_type <> 'S'.
      CONTINUE.
    ENDIF.

    IF ls_res-record_key IS NOT INITIAL.
      lv_group = ls_res-record_key.
    ELSE.
      CLEAR lv_row_key.
      WRITE ls_res-row_index TO lv_row_key LEFT-JUSTIFIED.
      CONDENSE lv_row_key NO-GAPS.
      lv_group = lv_row_key.
    ENDIF.
    IF lv_group <> is_exec-group_key.
      CONTINUE.
    ENDIF.

    CLEAR: lv_msgid, lv_msgnr, lv_v1, lv_v2, lv_v3, lv_v4.
    PERFORM read_result_message_parts
      USING    ls_res
      CHANGING lv_msgid lv_msgnr lv_v1 lv_v2 lv_v3 lv_v4.
    IF lv_msgid <> iv_msgid OR lv_msgnr <> iv_msgnr.
      CONTINUE.
    ENDIF.

    lt_candidate = ct_binding.
    CLEAR: lv_tuple, lv_audit, lv_bad.
    LOOP AT lt_candidate INTO ls_binding.
      CLEAR lv_value.
      CASE ls_binding-msgv_idx.
        WHEN '1'. lv_value = lv_v1.
        WHEN '2'. lv_value = lv_v2.
        WHEN '3'. lv_value = lv_v3.
        WHEN '4'. lv_value = lv_v4.
        WHEN OTHERS. lv_bad = abap_true.
      ENDCASE.
      CONDENSE lv_value.
      IF lv_value IS INITIAL.
        lv_bad = abap_true.
        EXIT.
      ENDIF.
      ls_binding-value = lv_value.
      MODIFY lt_candidate FROM ls_binding INDEX sy-tabix.
      IF lv_tuple IS INITIAL.
        lv_tuple = lv_value.
      ELSE.
        lv_tuple = |{ lv_tuple }/{ lv_value }|.
      ENDIF.
      IF lv_audit IS INITIAL.
        lv_audit = |MSGV{ ls_binding-msgv_idx }={ lv_value }|.
      ELSE.
        lv_audit = |{ lv_audit }; MSGV{ ls_binding-msgv_idx }={ lv_value }|.
      ENDIF.
    ENDLOOP.
    IF lv_bad = abap_true OR lv_tuple IS INITIAL.
      CONTINUE.
    ENDIF.

    "V17.9.3.4 route-state fix: when the cockpit/result already carries a
    "persisted exact object, it is the anchor. Ignore same-message protocol
    "echoes whose reconstructed tuple is different; never let them downgrade
    "an already certified object to NO_ROUTE. A matching tuple must still be
    "present, so this remains fail-closed and does not trust UI text alone.
    IF iv_expected IS NOT INITIAL AND lv_tuple <> iv_expected.
      CONTINUE.
    ENDIF.

    "V17.9.3.4: after visible Certify, PERSIST_NAV_OBJ_EXEC marks the exact
    "SAP SUCCESS row that was observed by the user. Prefer that tagged row
    "over duplicate/unrelated S-message rows with the same MSGID/MSGNR.
    "This keeps projection and later Document clicks tied to the exact
    "persisted evidence instead of becoming NO_ROUTE from harmless duplicates.
    IF ls_res-sap_object_id IS NOT INITIAL.
      IF ls_res-sap_object_id <> lv_tuple.
        CLEAR: cv_object, cv_tuple_txt, ct_binding.
        cv_message = |Persisted certified object { ls_res-sap_object_id } does not match its exact SAP message tuple { lv_tuple }.|.
        RETURN.
      ENDIF.

      IF lv_tagged_found <> abap_true.
        lv_tagged_found = abap_true.
        lv_first = lv_tuple.
        ct_binding = lt_candidate.
        cv_tuple_txt = lv_audit.
      ELSEIF lv_first <> lv_tuple.
        CLEAR: cv_object, cv_tuple_txt, ct_binding.
        cv_message = 'More than one different persisted certified object tuple exists for this SUCCESS group.'.
        RETURN.
      ENDIF.
      CONTINUE.
    ENDIF.

    "Once an exact persisted certified row exists, untagged protocol echoes
    "are audit-only and cannot make the certified route ambiguous.
    IF lv_tagged_found = abap_true.
      CONTINUE.
    ENDIF.

    IF lv_first IS INITIAL.
      lv_first = lv_tuple.
      ct_binding = lt_candidate.
      cv_tuple_txt = lv_audit.
    ELSEIF lv_first <> lv_tuple.
      "Do not fail yet: a later exact persisted certified row has priority.
      lv_untagged_ambig = abap_true.
    ENDIF.
  ENDLOOP.

  IF lv_tagged_found <> abap_true AND lv_untagged_ambig = abap_true.
    CLEAR: cv_object, cv_tuple_txt, ct_binding.
    cv_message = 'More than one different object-key tuple exists for the same certified SUCCESS message/group.'.
    RETURN.
  ENDIF.

  IF lv_first IS INITIAL.
    cv_message = 'The certified navigation binding values are not present in the exact SAP SUCCESS message.' .
    RETURN.
  ENDIF.

  DESCRIBE FIELD cv_object LENGTH lv_cap IN CHARACTER MODE.
  IF strlen( lv_first ) > lv_cap.
    cv_message = 'The exact composite object label exceeds the SAP Object display field capacity.'.
    RETURN.
  ENDIF.

  cv_object = lv_first.
  cv_ok = abap_true.
ENDFORM.

FORM apply_nav_binding_params
  CHANGING ct_binding TYPE ty_t_nav_binding.

  FIELD-SYMBOLS <ls_binding> TYPE ty_nav_binding.
  LOOP AT ct_binding ASSIGNING <ls_binding>.
    CLEAR <ls_binding>-old_value.
    GET PARAMETER ID <ls_binding>-param_id FIELD <ls_binding>-old_value.
    SET PARAMETER ID <ls_binding>-param_id FIELD <ls_binding>-value.
  ENDLOOP.
ENDFORM.

FORM restore_nav_binding_params
  USING it_binding TYPE ty_t_nav_binding.

  DATA ls_binding TYPE ty_nav_binding.
  LOOP AT it_binding INTO ls_binding.
    IF ls_binding-param_id IS INITIAL.
      CONTINUE.
    ENDIF.
    SET PARAMETER ID ls_binding-param_id FIELD ls_binding-old_value.
  ENDLOOP.
ENDFORM.

*&---------------------------------------------------------------------*
*& V17.9.3 generic SPA/GPA fallback for control-framework transactions
*&
*& Some standard SAP GUI transactions start in a control-framework shell
*& whose TSTC PROGRAM/DYNPRO has no importable classic Screen Painter field
*& list. That is not evidence that the target TCODE is wrong.
*&
*& This fallback contains no business TCODE, field, table, PID or object rule:
*& 1) read only the AI-selected target's own TSTC program;
*& 2) collect literal GET PARAMETER IDs from that program/includes;
*& 3) give AI only that closed repository PID set + exact SUCCESS MSGV values;
*& 4) ABAP accepts only one returned PID + one non-empty MSGV from those exact
*&    evidence sets, then opens the real target for visible Certify/Reject.
*& Current SPA/GPA memory is audit-only and never decides route existence.
*&---------------------------------------------------------------------*
FORM discover_nav_param_mem_route
  USING    iv_target    TYPE sy-tcode
           is_nav       TYPE ty_nav_evidence
  CHANGING cv_program   TYPE d020s-prog
           cv_dynpro    TYPE d020s-dnum
           ct_binding   TYPE ty_t_nav_binding
           cv_ok        TYPE abap_bool
           cv_message   TYPE string.

  DATA: ls_tstc        TYPE tstc,
        lt_includes    TYPE STANDARD TABLE OF sy-repid,
        lv_include     TYPE sy-repid,
        lt_source      TYPE STANDARD TABLE OF string,
        lv_line        TYPE string,
        lv_work        TYPE string,
        lv_stmt        TYPE string,
        lv_after       TYPE string,
        lv_q1          TYPE i,
        lv_q2          TYPE i,
        lt_pid_seen    TYPE SORTED TABLE OF ty_nav_param_id
                       WITH UNIQUE KEY table_line,
        lv_pid         TYPE ty_nav_param_id,
        lv_pid_raw     TYPE string,
        lv_pid_ev      TYPE string,
        lv_endpoint    TYPE string,
        lv_prompt      TYPE string,
        lv_resp        TYPE string,
        lv_json        TYPE string,
        lv_call_ok     TYPE abap_bool,
        lv_status      TYPE string,
        lv_key_source  TYPE string,
        lv_reason      TYPE string,
        lv_idx         TYPE ty_nav_msgv_idx,
        lv_value       TYPE string,
        lv_mem         TYPE c LENGTH 255,
        ls_binding     TYPE ty_nav_binding,
        lt_dynpro      TYPE SORTED TABLE OF d020s-dnum
                       WITH UNIQUE KEY table_line,
        lv_scan_dynpro TYPE d020s-dnum,
        ls_scan_head   TYPE d020s,
        lt_scan_fld    TYPE STANDARD TABLE OF d021s,
        lt_scan_flow   TYPE STANDARD TABLE OF d022s,
        ls_scan_fld    TYPE d021s,
        lt_scan_ext    TYPE dyfatc_tab,
        ls_scan_ext    TYPE rpy_dyfatc,
        lv_scan_field  TYPE string,
        lv_scan_pid    TYPE string,
        lt_screen_pid_seen TYPE SORTED TABLE OF ty_nav_param_id
                           WITH UNIQUE KEY table_line,
        lt_ddic_pid_seen TYPE SORTED TABLE OF ty_nav_param_id
                         WITH UNIQUE KEY table_line,
        lv_ddic_work    TYPE string,
        lv_ddic_tab     TYPE dd03l-tabname,
        lv_ddic_field   TYPE dd03l-fieldname,
        lv_ddic_roll    TYPE dd03l-rollname,
        lv_ddic_pid     TYPE dd04l-memoryid,
        lv_ddic_pos     TYPE i,
        lt_probe_bdc    TYPE STANDARD TABLE OF bdcdata,
        ls_probe_bdc    TYPE bdcdata,
        lt_probe_msg    TYPE STANDARD TABLE OF bdcmsgcoll,
        ls_probe_msg    TYPE bdcmsgcoll,
        lv_probe_prog   TYPE d020s-prog,
        lv_probe_dyn    TYPE d020s-dnum,
        ls_probe_d020   TYPE d020s,
        ls_probe_head   TYPE d020s,
        lt_probe_fld    TYPE STANDARD TABLE OF d021s,
        lt_probe_flow   TYPE STANDARD TABLE OF d022s,
        ls_probe_fld    TYPE d021s,
        lt_probe_ext    TYPE dyfatc_tab,
        ls_probe_ext    TYPE rpy_dyfatc,
        lv_probe_found  TYPE abap_bool.

  FIELD-SYMBOLS: <lv_scan_paid> TYPE any,
                 <lv_scan_param> TYPE any.

  CLEAR: cv_program, cv_dynpro, ct_binding, cv_ok, cv_message.

  SELECT SINGLE * FROM tstc
    INTO @ls_tstc
    WHERE tcode = @iv_target.
  IF sy-subrc <> 0.
    cv_message = |Navigation target { iv_target } does not exist in TSTC.|.
    RETURN.
  ENDIF.

  cv_program = ls_tstc-pgmna.
  cv_dynpro  = ls_tstc-dypno.
  CONDENSE: cv_program NO-GAPS, cv_dynpro NO-GAPS.
  IF cv_program IS INITIAL.
    cv_message = |Navigation target { iv_target } has no repository program for SPA/GPA fallback.|.
    RETURN.
  ENDIF.

  "V17.9.3.16K NAVIGATION BINDING PROOF.
  "First build a CLOSED repository evidence set from source GET PARAMETER,
  "Screen Painter PID metadata and exact DDIC Data Element MEMORYID.
  "Some standard transactions use a technical TSTC controller dynpro that
  "SUPPRESS DIALOG and dispatches into another function group; the first
  "screen the user actually sees is therefore not statically owned by the
  "TSTC start program. If repository evidence stays empty, run one data-free
  "BDC probe containing only the exact TSTC start dynpro. Standard message
  "00-344 then exposes the exact next runtime PROGRAM/DYNPRO requested by the
  "transaction. That exact runtime screen is imported and checked with the
  "same PAID/DDIC/RPY rules. No business TCODE, PID, field or object mapping
  "is hardcoded. AI may select only a PID already present in this closed
  "technical evidence set plus one exact SUCCESS MSGV.
  CLEAR lt_includes.
  CALL FUNCTION 'RS_GET_ALL_INCLUDES'
    EXPORTING
      program    = cv_program
    TABLES
      includetab = lt_includes
    EXCEPTIONS
      OTHERS     = 1.
  IF sy-subrc <> 0.
    CLEAR lt_includes.
  ENDIF.

  READ TABLE lt_includes WITH KEY table_line = cv_program
    TRANSPORTING NO FIELDS.
  IF sy-subrc <> 0.
    INSERT cv_program INTO lt_includes INDEX 1.
  ENDIF.

  CLEAR lv_pid_ev.
  LOOP AT lt_includes INTO lv_include.
    REFRESH lt_source.
    CLEAR lv_stmt.
    READ REPORT lv_include INTO lt_source.
    IF sy-subrc <> 0.
      CONTINUE.
    ENDIF.

    LOOP AT lt_source INTO lv_line.
      lv_work = lv_line.
      IF lv_work IS INITIAL.
        CONTINUE.
      ENDIF.
      IF lv_work(1) = '*'.
        CONTINUE.
      ENDIF.

      FIND FIRST OCCURRENCE OF '"' IN lv_work MATCH OFFSET lv_q1.
      IF sy-subrc = 0.
        lv_work = lv_work(lv_q1).
      ENDIF.
      CONDENSE lv_work.
      IF lv_work IS INITIAL.
        CONTINUE.
      ENDIF.

      IF lv_stmt IS INITIAL.
        lv_stmt = lv_work.
      ELSE.
        CONCATENATE lv_stmt lv_work INTO lv_stmt SEPARATED BY space.
      ENDIF.

      IF lv_stmt NS '.'.
        CONTINUE.
      ENDIF.

      TRANSLATE lv_stmt TO UPPER CASE.
      FIND FIRST OCCURRENCE OF 'GET PARAMETER ID' IN lv_stmt MATCH OFFSET lv_q1.
      IF sy-subrc = 0.
        lv_after = lv_stmt+lv_q1.
        FIND FIRST OCCURRENCE OF '''' IN lv_after MATCH OFFSET lv_q1.
        IF sy-subrc = 0.
          lv_q1 = lv_q1 + 1.
          lv_after = lv_after+lv_q1.
          FIND FIRST OCCURRENCE OF '''' IN lv_after MATCH OFFSET lv_q2.
          IF sy-subrc = 0 AND lv_q2 > 0.
            CLEAR lv_pid.
            lv_pid = lv_after(lv_q2).
            CONDENSE lv_pid NO-GAPS.
            IF lv_pid IS NOT INITIAL AND strlen( lv_pid ) <= 20.
              INSERT lv_pid INTO TABLE lt_pid_seen.
              IF sy-subrc = 0.
                IF lv_pid_ev IS INITIAL.
                  lv_pid_ev = |PID={ lv_pid };STATEMENT={ lv_stmt }|.
                ELSE.
                  lv_pid_ev = |{ lv_pid_ev }\nPID={ lv_pid };STATEMENT={ lv_stmt }|.
                ENDIF.
              ENDIF.
            ENDIF.
          ENDIF.
        ENDIF.
      ENDIF.
      CLEAR lv_stmt.
    ENDLOOP.
  ENDLOOP.

  "Second repository source: Screen Painter parameter-ID metadata on every
  "active/importable dynpro owned by the exact TSTC/SE93 target program. This
  "covers controller start screens whose real object selector lives on a
  "different dynpro/subscreen of the same application program. Only exact
  "D021S-PAID / RPY PARAM_ID values are accepted; labels or business text are
  "never converted into a PID. One evidence row per PID keeps the AI prompt
  "bounded even when the same object field appears on several screens.
  CLEAR: lt_dynpro, lt_screen_pid_seen, lt_ddic_pid_seen.
  SELECT dnum FROM d020s
    INTO TABLE @lt_dynpro
    WHERE prog = @cv_program.

  LOOP AT lt_dynpro INTO lv_scan_dynpro.
    CLEAR ls_scan_head.
    REFRESH: lt_scan_fld, lt_scan_flow.
    CALL FUNCTION 'RS_IMPORT_DYNPRO'
      EXPORTING
        dylang          = sy-langu
        dyname          = cv_program
        dynumb          = lv_scan_dynpro
        request         = space
        suppress_checks = space
      IMPORTING
        header           = ls_scan_head
      TABLES
        ftab             = lt_scan_fld
        pltab            = lt_scan_flow
      EXCEPTIONS
        OTHERS           = 1.
    IF sy-subrc <> 0.
      CONTINUE.
    ENDIF.

    LOOP AT lt_scan_fld INTO ls_scan_fld.
      CLEAR: lv_scan_pid, lv_scan_field.
      lv_scan_field = ls_scan_fld-fnam.
      CONDENSE lv_scan_field NO-GAPS.
      TRANSLATE lv_scan_field TO UPPER CASE.

      UNASSIGN <lv_scan_paid>.
      ASSIGN COMPONENT 'PAID' OF STRUCTURE ls_scan_fld TO <lv_scan_paid>.
      IF sy-subrc = 0 AND <lv_scan_paid> IS ASSIGNED
         AND <lv_scan_paid> IS NOT INITIAL.
        lv_scan_pid = <lv_scan_paid>.
        TRANSLATE lv_scan_pid TO UPPER CASE.
        CONDENSE lv_scan_pid NO-GAPS.
      ENDIF.

      "Independent DDIC evidence: an exact dynpro field such as
      "STRUCTURE-FIELD can carry its SPA/GPA ID on the Data Element in DD04L
      "even when the Screen Painter PAID column is blank. Use only the exact
      "technical field identity from D021S; never derive a PID from labels.
      CLEAR: lv_ddic_work, lv_ddic_tab, lv_ddic_field,
             lv_ddic_roll, lv_ddic_pid, lv_ddic_pos.
      lv_ddic_work = lv_scan_field.
      FIND FIRST OCCURRENCE OF '(' IN lv_ddic_work
        MATCH OFFSET lv_ddic_pos.
      IF sy-subrc = 0 AND lv_ddic_pos > 0.
        lv_ddic_work = lv_ddic_work(lv_ddic_pos).
      ENDIF.

      IF lv_ddic_work CS '-'.
        SPLIT lv_ddic_work AT '-' INTO lv_ddic_tab lv_ddic_field.
        TRANSLATE: lv_ddic_tab TO UPPER CASE,
                   lv_ddic_field TO UPPER CASE.
        CONDENSE: lv_ddic_tab NO-GAPS, lv_ddic_field NO-GAPS.

        IF lv_ddic_tab IS NOT INITIAL AND lv_ddic_field IS NOT INITIAL.
          SELECT SINGLE rollname
            FROM dd03l
            INTO @lv_ddic_roll
            WHERE tabname  = @lv_ddic_tab
              AND fieldname = @lv_ddic_field
              AND as4local  = 'A'.

          IF sy-subrc = 0 AND lv_ddic_roll IS NOT INITIAL.
            SELECT SINGLE memoryid
              FROM dd04l
              INTO @lv_ddic_pid
              WHERE rollname = @lv_ddic_roll
                AND as4local = 'A'.

            IF sy-subrc = 0 AND lv_ddic_pid IS NOT INITIAL.
              TRANSLATE lv_ddic_pid TO UPPER CASE.
              CONDENSE lv_ddic_pid NO-GAPS.
              IF strlen( lv_ddic_pid ) <= 20.
                lv_pid = lv_ddic_pid.
                INSERT lv_pid INTO TABLE lt_pid_seen.
                INSERT lv_pid INTO TABLE lt_ddic_pid_seen.
                IF sy-subrc = 0.
                  IF lv_pid_ev IS INITIAL.
                    lv_pid_ev = |PID={ lv_pid };SOURCE=DDIC_MEMORYID;DYNPRO={ lv_scan_dynpro };FIELD={ lv_scan_field };ROLLNAME={ lv_ddic_roll }|.
                  ELSE.
                    lv_pid_ev = |{ lv_pid_ev }\nPID={ lv_pid };SOURCE=DDIC_MEMORYID;DYNPRO={ lv_scan_dynpro };FIELD={ lv_scan_field };ROLLNAME={ lv_ddic_roll }|.
                  ENDIF.
                ENDIF.
              ENDIF.
            ENDIF.
          ENDIF.
        ENDIF.
      ENDIF.

      IF lv_scan_pid IS INITIAL OR strlen( lv_scan_pid ) > 20.
        CONTINUE.
      ENDIF.

      lv_pid = lv_scan_pid.
      INSERT lv_pid INTO TABLE lt_pid_seen.
      INSERT lv_pid INTO TABLE lt_screen_pid_seen.
      IF sy-subrc = 0.
        IF lv_pid_ev IS INITIAL.
          lv_pid_ev = |PID={ lv_pid };SOURCE=SCREEN_PAID;DYNPRO={ lv_scan_dynpro };FIELD={ lv_scan_field }|.
        ELSE.
          lv_pid_ev = |{ lv_pid_ev }\nPID={ lv_pid };SOURCE=SCREEN_PAID;DYNPRO={ lv_scan_dynpro };FIELD={ lv_scan_field }|.
        ENDIF.
      ENDIF.
    ENDLOOP.

    "Some releases expose the same Set/Get Parameter ID through the external
    "Screen Painter representation rather than directly on the imported D021S
    "row. Read RPY metadata as a second exact representation of THIS dynpro.
    REFRESH lt_scan_ext.
    CALL FUNCTION 'RPY_DYNPRO_READ'
      EXPORTING
        progname             = cv_program
        dynnr                = lv_scan_dynpro
        suppress_corr_checks = 'X'
      TABLES
        fields_to_containers = lt_scan_ext
      EXCEPTIONS
        cancelled            = 1
        not_found            = 2
        permission_error     = 3
        OTHERS               = 4.
    IF sy-subrc <> 0.
      CONTINUE.
    ENDIF.

    LOOP AT lt_scan_ext INTO ls_scan_ext.
      IF ls_scan_ext-type <> 'TEMPLATE' AND ls_scan_ext-type <> 'RADIO'
         AND ls_scan_ext-type <> 'CHECK'.
        CONTINUE.
      ENDIF.

      CLEAR: lv_scan_pid, lv_scan_field.
      lv_scan_field = ls_scan_ext-name.
      CONDENSE lv_scan_field NO-GAPS.
      TRANSLATE lv_scan_field TO UPPER CASE.

      UNASSIGN <lv_scan_param>.
      ASSIGN COMPONENT 'PARAM_ID' OF STRUCTURE ls_scan_ext TO <lv_scan_param>.
      IF sy-subrc = 0 AND <lv_scan_param> IS ASSIGNED
         AND <lv_scan_param> IS NOT INITIAL.
        lv_scan_pid = <lv_scan_param>.
        TRANSLATE lv_scan_pid TO UPPER CASE.
        CONDENSE lv_scan_pid NO-GAPS.
      ENDIF.

      IF lv_scan_pid IS INITIAL OR strlen( lv_scan_pid ) > 20.
        CONTINUE.
      ENDIF.

      lv_pid = lv_scan_pid.
      INSERT lv_pid INTO TABLE lt_pid_seen.
      INSERT lv_pid INTO TABLE lt_screen_pid_seen.
      IF sy-subrc = 0.
        IF lv_pid_ev IS INITIAL.
          lv_pid_ev = |PID={ lv_pid };SOURCE=RPY_PARAM;DYNPRO={ lv_scan_dynpro };FIELD={ lv_scan_field }|.
        ELSE.
          lv_pid_ev = |{ lv_pid_ev }\nPID={ lv_pid };SOURCE=RPY_PARAM;DYNPRO={ lv_scan_dynpro };FIELD={ lv_scan_field }|.
        ENDIF.
      ENDIF.
    ENDLOOP.
  ENDLOOP.

  "Runtime controller-screen fallback.
  "The probe supplies only the repository-proven TSTC start dynpro and no
  "business fields. If that dynpro suppresses its own dialog and dispatches
  "to another function group, batch input stops at the first real visible
  "screen with SAP standard message 00-344:
  "  'No batch input data for screen & &'
  "MSGV1/MSGV2 are therefore exact runtime PROGRAM/DYNPRO evidence.
  IF lt_pid_seen IS INITIAL
     AND cv_program IS NOT INITIAL
     AND cv_dynpro IS NOT INITIAL.

    CLEAR: lv_probe_prog, lv_probe_dyn, lv_probe_found.
    REFRESH: lt_probe_bdc, lt_probe_msg.

    CLEAR ls_probe_bdc.
    ls_probe_bdc-program  = cv_program.
    ls_probe_bdc-dynpro   = cv_dynpro.
    ls_probe_bdc-dynbegin = abap_true.
    APPEND ls_probe_bdc TO lt_probe_bdc.

    CALL TRANSACTION iv_target
      USING lt_probe_bdc
      MODE 'N'
      UPDATE 'S'
      MESSAGES INTO lt_probe_msg.

    LOOP AT lt_probe_msg INTO ls_probe_msg
      WHERE msgid = '00'
        AND msgnr = '344'.
      CLEAR: lv_probe_prog, lv_probe_dyn, ls_probe_d020.
      lv_probe_prog = ls_probe_msg-msgv1.
      lv_probe_dyn  = ls_probe_msg-msgv2.
      CONDENSE: lv_probe_prog NO-GAPS,
                lv_probe_dyn NO-GAPS.
      TRANSLATE lv_probe_prog TO UPPER CASE.

      IF lv_probe_prog IS INITIAL OR lv_probe_dyn IS INITIAL.
        CONTINUE.
      ENDIF.

      SELECT SINGLE *
        FROM d020s
        INTO @ls_probe_d020
        WHERE prog = @lv_probe_prog
          AND dnum = @lv_probe_dyn.
      IF sy-subrc = 0.
        lv_probe_found = abap_true.
        EXIT.
      ENDIF.
    ENDLOOP.

    IF lv_probe_found = abap_true.
      CLEAR ls_probe_head.
      REFRESH: lt_probe_fld, lt_probe_flow.
      CALL FUNCTION 'RS_IMPORT_DYNPRO'
        EXPORTING
          dylang          = sy-langu
          dyname          = lv_probe_prog
          dynumb          = lv_probe_dyn
          request         = space
          suppress_checks = space
        IMPORTING
          header           = ls_probe_head
        TABLES
          ftab             = lt_probe_fld
          pltab            = lt_probe_flow
        EXCEPTIONS
          OTHERS           = 1.

      IF sy-subrc = 0.
        LOOP AT lt_probe_fld INTO ls_probe_fld.
          CLEAR: lv_scan_pid, lv_scan_field.
          lv_scan_field = ls_probe_fld-fnam.
          CONDENSE lv_scan_field NO-GAPS.
          TRANSLATE lv_scan_field TO UPPER CASE.

          UNASSIGN <lv_scan_paid>.
          ASSIGN COMPONENT 'PAID'
            OF STRUCTURE ls_probe_fld TO <lv_scan_paid>.
          IF sy-subrc = 0
             AND <lv_scan_paid> IS ASSIGNED
             AND <lv_scan_paid> IS NOT INITIAL.
            lv_scan_pid = <lv_scan_paid>.
            TRANSLATE lv_scan_pid TO UPPER CASE.
            CONDENSE lv_scan_pid NO-GAPS.
          ENDIF.

          "Exact runtime screen field -> DDIC Data Element -> MEMORYID.
          CLEAR: lv_ddic_work, lv_ddic_tab, lv_ddic_field,
                 lv_ddic_roll, lv_ddic_pid, lv_ddic_pos.
          lv_ddic_work = lv_scan_field.
          FIND FIRST OCCURRENCE OF '(' IN lv_ddic_work
            MATCH OFFSET lv_ddic_pos.
          IF sy-subrc = 0 AND lv_ddic_pos > 0.
            lv_ddic_work = lv_ddic_work(lv_ddic_pos).
          ENDIF.

          IF lv_ddic_work CS '-'.
            SPLIT lv_ddic_work AT '-'
              INTO lv_ddic_tab lv_ddic_field.
            TRANSLATE: lv_ddic_tab TO UPPER CASE,
                       lv_ddic_field TO UPPER CASE.
            CONDENSE: lv_ddic_tab NO-GAPS,
                      lv_ddic_field NO-GAPS.

            IF lv_ddic_tab IS NOT INITIAL
               AND lv_ddic_field IS NOT INITIAL.
              SELECT SINGLE rollname
                FROM dd03l
                INTO @lv_ddic_roll
                WHERE tabname   = @lv_ddic_tab
                  AND fieldname = @lv_ddic_field
                  AND as4local  = 'A'.

              IF sy-subrc = 0 AND lv_ddic_roll IS NOT INITIAL.
                SELECT SINGLE memoryid
                  FROM dd04l
                  INTO @lv_ddic_pid
                  WHERE rollname = @lv_ddic_roll
                    AND as4local = 'A'.

                IF sy-subrc = 0 AND lv_ddic_pid IS NOT INITIAL.
                  TRANSLATE lv_ddic_pid TO UPPER CASE.
                  CONDENSE lv_ddic_pid NO-GAPS.
                  IF strlen( lv_ddic_pid ) <= 20.
                    lv_pid = lv_ddic_pid.
                    INSERT lv_pid INTO TABLE lt_pid_seen.
                    INSERT lv_pid INTO TABLE lt_ddic_pid_seen.
                    IF sy-subrc = 0.
                      IF lv_pid_ev IS INITIAL.
                        lv_pid_ev =
                          |PID={ lv_pid };SOURCE=RUNTIME_DDIC;PROGRAM={ lv_probe_prog };DYNPRO={ lv_probe_dyn };FIELD={ lv_scan_field };ROLLNAME={ lv_ddic_roll }|.
                      ELSE.
                        lv_pid_ev =
                          |{ lv_pid_ev }\nPID={ lv_pid };SOURCE=RUNTIME_DDIC;PROGRAM={ lv_probe_prog };DYNPRO={ lv_probe_dyn };FIELD={ lv_scan_field };ROLLNAME={ lv_ddic_roll }|.
                      ENDIF.
                    ENDIF.
                  ENDIF.
                ENDIF.
              ENDIF.
            ENDIF.
          ENDIF.

          IF lv_scan_pid IS INITIAL
             OR strlen( lv_scan_pid ) > 20.
            CONTINUE.
          ENDIF.

          lv_pid = lv_scan_pid.
          INSERT lv_pid INTO TABLE lt_pid_seen.
          INSERT lv_pid INTO TABLE lt_screen_pid_seen.
          IF sy-subrc = 0.
            IF lv_pid_ev IS INITIAL.
              lv_pid_ev =
                |PID={ lv_pid };SOURCE=RUNTIME_PAID;PROGRAM={ lv_probe_prog };DYNPRO={ lv_probe_dyn };FIELD={ lv_scan_field }|.
            ELSE.
              lv_pid_ev =
                |{ lv_pid_ev }\nPID={ lv_pid };SOURCE=RUNTIME_PAID;PROGRAM={ lv_probe_prog };DYNPRO={ lv_probe_dyn };FIELD={ lv_scan_field }|.
            ENDIF.
          ENDIF.
        ENDLOOP.

        "Read the external Screen Painter representation of the exact runtime
        "screen as an independent PID representation.
        REFRESH lt_probe_ext.
        CALL FUNCTION 'RPY_DYNPRO_READ'
          EXPORTING
            progname             = lv_probe_prog
            dynnr                = lv_probe_dyn
            suppress_corr_checks = 'X'
          TABLES
            fields_to_containers = lt_probe_ext
          EXCEPTIONS
            cancelled            = 1
            not_found            = 2
            permission_error     = 3
            OTHERS               = 4.

        IF sy-subrc = 0.
          LOOP AT lt_probe_ext INTO ls_probe_ext.
            IF ls_probe_ext-type <> 'TEMPLATE'
               AND ls_probe_ext-type <> 'RADIO'
               AND ls_probe_ext-type <> 'CHECK'.
              CONTINUE.
            ENDIF.

            CLEAR: lv_scan_pid, lv_scan_field.
            lv_scan_field = ls_probe_ext-name.
            CONDENSE lv_scan_field NO-GAPS.
            TRANSLATE lv_scan_field TO UPPER CASE.

            UNASSIGN <lv_scan_param>.
            ASSIGN COMPONENT 'PARAM_ID'
              OF STRUCTURE ls_probe_ext TO <lv_scan_param>.
            IF sy-subrc = 0
               AND <lv_scan_param> IS ASSIGNED
               AND <lv_scan_param> IS NOT INITIAL.
              lv_scan_pid = <lv_scan_param>.
              TRANSLATE lv_scan_pid TO UPPER CASE.
              CONDENSE lv_scan_pid NO-GAPS.
            ENDIF.

            IF lv_scan_pid IS INITIAL
               OR strlen( lv_scan_pid ) > 20.
              CONTINUE.
            ENDIF.

            lv_pid = lv_scan_pid.
            INSERT lv_pid INTO TABLE lt_pid_seen.
            INSERT lv_pid INTO TABLE lt_screen_pid_seen.
            IF sy-subrc = 0.
              IF lv_pid_ev IS INITIAL.
                lv_pid_ev =
                  |PID={ lv_pid };SOURCE=RUNTIME_RPY;PROGRAM={ lv_probe_prog };DYNPRO={ lv_probe_dyn };FIELD={ lv_scan_field }|.
              ELSE.
                lv_pid_ev =
                  |{ lv_pid_ev }\nPID={ lv_pid };SOURCE=RUNTIME_RPY;PROGRAM={ lv_probe_prog };DYNPRO={ lv_probe_dyn };FIELD={ lv_scan_field }|.
              ENDIF.
            ENDIF.
          ENDLOOP.
        ENDIF.
      ENDIF.
    ENDIF.
  ENDIF.

  IF lt_pid_seen IS INITIAL.
    IF lv_probe_found = abap_true.
      cv_message =
        |No exact SPA/GPA PID was proven in TSTC repository metadata or runtime screen { lv_probe_prog }/{ lv_probe_dyn }.|.
    ELSE.
      cv_message =
        |No exact SPA/GPA PID was proven, and no exact first-visible runtime screen could be derived from the data-free target probe.|.
    ENDIF.
    RETURN.
  ENDIF.

  PERFORM get_ai_endpoint CHANGING lv_endpoint.
  IF lv_endpoint IS INITIAL.
    cv_message = |Repository PID evidence exists for { iv_target }, but AI binding is unavailable: { gv_z619_ai_http_diag }|.
    RETURN.
  ENDIF.

  lv_prompt =
    |You are an SAP GUI SPA/GPA binding selector. Use ONLY exact PID evidence from ABAP GET PARAMETER, Screen Painter, | &&
    |DDIC Data Element MEMORYID, or the exact first-visible runtime screen proven by SAP message 00-344, | &&
    |plus the exact current SUCCESS message values below. | &&
    |Do not invent or rename a Parameter ID, MSGV source, object value, field, transaction, or business rule. | &&
    |Return ONLY one raw JSON object with exactly these string fields: | &&
    |"status" (CANDIDATE or NOT_PROVEN), "parameter_id", "key_source" (MSGV1, MSGV2, MSGV3, or MSGV4), and "reason" (max 240 chars). | &&
    |parameter_id must exactly equal one PID listed in PID_EVIDENCE. key_source must name one non-empty exact MSGV below. | &&
    |Choose CANDIDATE only when the repository evidence context supports that PID as the object selector for the AI-selected display target. Screen evidence includes exact target dynpro and field identity. | &&
    |The proposal is advisory only: ABAP will validate membership and exact value, then SAP will open the real target and a human must Certify the exact landing. | &&
    |TARGET_TCODE={ iv_target }; TARGET_PROGRAM={ cv_program }; SOURCE_TCODE={ is_nav-tcode }; | &&
    |MSGID={ is_nav-msgid }; MSGNR={ is_nav-msgnr }; MESSAGE_TEXT={ is_nav-message_text }; | &&
    |MSGV1={ is_nav-msgv1 }; MSGV2={ is_nav-msgv2 }; MSGV3={ is_nav-msgv3 }; MSGV4={ is_nav-msgv4 }. | &&
    |PID_EVIDENCE:\n{ lv_pid_ev }|.

  CLEAR: lv_resp, lv_json, lv_call_ok.
  PERFORM call_ai_endpoint
    USING    'NAV' lv_endpoint lv_prompt
    CHANGING lv_resp lv_call_ok.
  IF lv_call_ok <> abap_true OR lv_resp IS INITIAL.
    cv_message = |Repository PID evidence exists for { iv_target }, but AI PID binding failed: { gv_z619_ai_http_diag }|.
    RETURN.
  ENDIF.

  PERFORM extract_openai_text USING lv_resp CHANGING lv_json.
  IF lv_json IS INITIAL.
    lv_json = lv_resp.
  ENDIF.
  REPLACE ALL OCCURRENCES OF '```json' IN lv_json WITH ''.
  REPLACE ALL OCCURRENCES OF '```JSON' IN lv_json WITH ''.
  REPLACE ALL OCCURRENCES OF '```'     IN lv_json WITH ''.
  CONDENSE lv_json.

  CLEAR: lv_status, lv_pid_raw, lv_key_source, lv_reason.
  PERFORM json_get_bup USING lv_json 'status' CHANGING lv_status.
  PERFORM json_get_bup USING lv_json 'parameter_id' CHANGING lv_pid_raw.
  IF lv_pid_raw IS INITIAL.
    PERFORM json_get_bup USING lv_json 'parameterId' CHANGING lv_pid_raw.
  ENDIF.
  PERFORM json_get_bup USING lv_json 'key_source' CHANGING lv_key_source.
  IF lv_key_source IS INITIAL.
    PERFORM json_get_bup USING lv_json 'keySource' CHANGING lv_key_source.
  ENDIF.
  PERFORM json_get_bup USING lv_json 'reason' CHANGING lv_reason.

  TRANSLATE: lv_status TO UPPER CASE,
             lv_pid_raw TO UPPER CASE,
             lv_key_source TO UPPER CASE.
  CONDENSE: lv_status NO-GAPS,
            lv_pid_raw NO-GAPS,
            lv_key_source NO-GAPS.

  IF lv_status <> 'CANDIDATE'.
    IF lv_reason IS INITIAL.
      lv_reason = 'AI could not bind the exact SUCCESS object to one repository-proven target SPA/GPA parameter.'.
    ENDIF.
    cv_message = lv_reason.
    RETURN.
  ENDIF.

  IF lv_pid_raw IS INITIAL OR strlen( lv_pid_raw ) > 20.
    cv_message = 'AI returned an invalid SPA/GPA Parameter ID.'.
    RETURN.
  ENDIF.
  lv_pid = lv_pid_raw.
  READ TABLE lt_pid_seen WITH KEY table_line = lv_pid
    TRANSPORTING NO FIELDS.
  IF sy-subrc <> 0.
    cv_message = |AI returned Parameter ID { lv_pid }, but it is not present in the exact target repository evidence.|.
    RETURN.
  ENDIF.

  CLEAR: lv_idx, lv_value.
  CASE lv_key_source.
    WHEN 'MSGV1'.
      lv_idx = '1'.
      lv_value = is_nav-msgv1.
    WHEN 'MSGV2'.
      lv_idx = '2'.
      lv_value = is_nav-msgv2.
    WHEN 'MSGV3'.
      lv_idx = '3'.
      lv_value = is_nav-msgv3.
    WHEN 'MSGV4'.
      lv_idx = '4'.
      lv_value = is_nav-msgv4.
    WHEN OTHERS.
      cv_message = |AI returned invalid key source { lv_key_source }.|.
      RETURN.
  ENDCASE.
  CONDENSE lv_value.
  IF lv_value IS INITIAL.
    cv_message = |AI selected { lv_key_source }, but that exact SUCCESS message variable is empty.|.
    RETURN.
  ENDIF.

  CLEAR ls_binding.
  ls_binding-seq        = 1.
  ls_binding-msgv_idx   = lv_idx.
  ls_binding-field_name = '@PARAM'.
  ls_binding-param_id   = lv_pid.
  ls_binding-value      = lv_value.
  APPEND ls_binding TO ct_binding.

  "Current SAP memory is audit-only corroboration. It never decides whether
  "the route exists, so prior transactions cannot make demo behavior random.
  CLEAR lv_mem.
  GET PARAMETER ID lv_pid FIELD lv_mem.
  CONDENSE lv_mem.
  IF lv_probe_found = abap_true.
    cv_message =
      |Runtime screen { lv_probe_prog }/{ lv_probe_dyn } + exact PID evidence selected { lv_pid }/{ lv_key_source }. Live landing still requires Certify.|.
  ELSEIF lv_mem = lv_value.
    cv_message =
      |Repository evidence + AI selected { lv_pid }/{ lv_key_source }; current SAP memory also matches. Live landing still requires Certify.|.
  ELSE.
    cv_message =
      |Repository evidence + AI selected { lv_pid }/{ lv_key_source }. Stale/empty SAP memory was ignored; live landing still requires Certify.|.
  ENDIF.
  cv_ok = abap_true.
ENDFORM.

*&---------------------------------------------------------------------*
*& AI-discover a navigation candidate from exact SUCCESS evidence.
*& No technical route input is requested from the business user.
*& AI remains advisory; SAP repository checks and real landing verification
*& are mandatory before the route can become CERTIFIED.
*&---------------------------------------------------------------------*
FORM discover_navigation_route_ai
  USING    is_nav         TYPE ty_nav_evidence
  CHANGING cv_target      TYPE sy-tcode
           cv_program     TYPE d020s-prog
           cv_dynpro      TYPE d020s-dnum
           cv_action      TYPE syucomm
           ct_binding     TYPE ty_t_nav_binding
           cv_object_type TYPE ty_nav_object_type
           cv_confidence  TYPE ty_nav_confidence
           cv_reason      TYPE string
           cv_ok          TYPE abap_bool
           cv_message     TYPE string.

  DATA: lv_endpoint      TYPE string,
        lv_prompt        TYPE string,
        lv_resp          TYPE string,
        lv_json          TYPE string,
        lv_call_ok       TYPE abap_bool,
        lv_status        TYPE string,
        lv_target_raw    TYPE string,
        lv_target        TYPE sy-tcode,
        lv_object_type   TYPE string,
        lv_confidence    TYPE string,
        lv_reason        TYPE string,
        lv_src_ttext     TYPE tstct-ttext,
        lv_src_program   TYPE tstc-pgmna,
        lv_target_ttext  TYPE tstct-ttext,
        lv_screen_ev     TYPE string,
        lt_screen        TYPE ty_t_nav_screen_field,
        ls_screen        TYPE ty_nav_screen_field,
        lv_meta_ok       TYPE abap_bool,
        lv_meta_msg      TYPE string,
        lv_count_txt     TYPE string,
        lv_count         TYPE i,
        lv_i             TYPE i,
        lv_i_txt         TYPE c LENGTH 1,
        lv_src           TYPE string,
        lv_field_raw     TYPE string,
        lv_action_raw    TYPE string,
        lv_kind_src      TYPE string,
        lv_kind_field    TYPE string,
        lv_idx           TYPE ty_nav_msgv_idx,
        lv_value         TYPE string,
        lv_action_found  TYPE abap_bool,
        ls_binding       TYPE ty_nav_binding,
        lv_tstc          TYPE tstc-tcode.

  CLEAR: cv_target, cv_program, cv_dynpro, cv_action, ct_binding,
         cv_object_type, cv_confidence, cv_reason, cv_ok, cv_message.

  PERFORM get_ai_endpoint CHANGING lv_endpoint.
  IF lv_endpoint IS INITIAL.
    cv_message = |AI navigation discovery is unavailable: { gv_z619_ai_http_diag }|.
    RETURN.
  ENDIF.

  SELECT SINGLE ttext FROM tstct
    INTO @lv_src_ttext
    WHERE sprsl = @sy-langu
      AND tcode = @is_nav-tcode.
  SELECT SINGLE pgmna FROM tstc
    INTO @lv_src_program
    WHERE tcode = @is_nav-tcode.

  "Stage 1 discovers only a candidate standard SAP GUI DISPLAY transaction.
  "No field/PID mapping is guessed here.
  lv_prompt =
    |You are an SAP GUI display-route candidate selector. Use ONLY the exact SAP execution evidence below. | &&
    |Do not invent object values, message variables, screen fields, parameter IDs or business data. | &&
    |Return ONLY one raw JSON object with exactly these string fields: | &&
    |"status" (CANDIDATE or NOT_PROVEN), "display_tcode", "object_type", | &&
    |"confidence" (0-100), and "reason" (max 240 chars). | &&
    |CANDIDATE means a standard SAP GUI transaction whose purpose is to DISPLAY the exact object represented by this SUCCESS message. | &&
    |If that cannot be supported from the evidence, return NOT_PROVEN. | &&
    |Execution evidence: TCODE={ is_nav-tcode }; TCODE_TEXT={ lv_src_ttext }; PROGRAM={ lv_src_program }; | &&
    |PROFILE={ is_nav-profile_name }; PROFILE_VERSION={ is_nav-profile_ver }; | &&
    |MSGID={ is_nav-msgid }; MSGNR={ is_nav-msgnr }; MESSAGE_TEXT={ is_nav-message_text }; | &&
    |MSGV1={ is_nav-msgv1 }; MSGV2={ is_nav-msgv2 }; MSGV3={ is_nav-msgv3 }; MSGV4={ is_nav-msgv4 }.|.

  PERFORM call_ai_endpoint
    USING    'NAV' lv_endpoint lv_prompt
    CHANGING lv_resp lv_call_ok.
  IF lv_call_ok <> abap_true OR lv_resp IS INITIAL.
    cv_message = |AI navigation discovery failed: { gv_z619_ai_http_diag }|.
    RETURN.
  ENDIF.

  CLEAR lv_json.
  PERFORM extract_openai_text USING lv_resp CHANGING lv_json.
  IF lv_json IS INITIAL.
    lv_json = lv_resp.
  ENDIF.
  REPLACE ALL OCCURRENCES OF '```json' IN lv_json WITH ''.
  REPLACE ALL OCCURRENCES OF '```JSON' IN lv_json WITH ''.
  REPLACE ALL OCCURRENCES OF '```'     IN lv_json WITH ''.
  CONDENSE lv_json.

  PERFORM json_get_bup USING lv_json 'status' CHANGING lv_status.
  PERFORM json_get_bup USING lv_json 'display_tcode' CHANGING lv_target_raw.
  IF lv_target_raw IS INITIAL.
    PERFORM json_get_bup USING lv_json 'displayTcode' CHANGING lv_target_raw.
  ENDIF.
  PERFORM json_get_bup USING lv_json 'object_type' CHANGING lv_object_type.
  IF lv_object_type IS INITIAL.
    PERFORM json_get_bup USING lv_json 'objectType' CHANGING lv_object_type.
  ENDIF.
  PERFORM json_get_bup USING lv_json 'confidence' CHANGING lv_confidence.
  PERFORM json_get_bup USING lv_json 'reason' CHANGING lv_reason.

  TRANSLATE: lv_status TO UPPER CASE, lv_target_raw TO UPPER CASE.
  CONDENSE: lv_status NO-GAPS, lv_target_raw NO-GAPS.

  IF lv_status <> 'CANDIDATE'.
    IF lv_reason IS INITIAL.
      lv_reason = 'AI did not find a standard SAP GUI display transaction from the exact SUCCESS evidence.'.
    ENDIF.
    cv_message = lv_reason.
    RETURN.
  ENDIF.
  IF lv_target_raw IS INITIAL OR strlen( lv_target_raw ) > 20.
    cv_message = 'AI returned an invalid SAP GUI display transaction.'.
    RETURN.
  ENDIF.

  lv_target = lv_target_raw.
  SELECT SINGLE tcode FROM tstc
    INTO @lv_tstc
    WHERE tcode = @lv_target.
  IF sy-subrc <> 0.
    cv_message = |AI proposed transaction { lv_target }, but it does not exist in this SAP system.|.
    RETURN.
  ENDIF.
  AUTHORITY-CHECK OBJECT 'S_TCODE' ID 'TCD' FIELD lv_target.
  IF sy-subrc <> 0.
    cv_message = |You are not authorized to test AI candidate transaction { lv_target }.|.
    RETURN.
  ENDIF.

  CLEAR: lv_meta_ok, lv_meta_msg, lv_screen_ev, lt_screen.
  PERFORM load_nav_screen_meta
    USING    lv_target
    CHANGING cv_program cv_dynpro lt_screen lv_screen_ev lv_meta_ok lv_meta_msg.
  IF lv_meta_ok <> abap_true.
    "Control-framework start screens may not expose classic fields on the
    "SE93/TSTC start dynpro. Do not reject a repository-valid target merely
    "for that reason. Try one strict generic SPA/GPA proof from the exact
    "target program source + Screen Painter + DDIC Data Element metadata.
    DATA: lv_pid_ok  TYPE abap_bool,
          lv_pid_msg TYPE string.
    CLEAR: cv_program, cv_dynpro, ct_binding, lv_pid_ok, lv_pid_msg.
    PERFORM discover_nav_param_mem_route
      USING    lv_target is_nav
      CHANGING cv_program cv_dynpro ct_binding lv_pid_ok lv_pid_msg.
    IF lv_pid_ok = abap_true.
      cv_target      = lv_target.
      cv_action      = '@PARAM'.
      cv_object_type = lv_object_type.
      cv_confidence  = lv_confidence.
      IF lv_reason IS INITIAL.
        cv_reason = lv_pid_msg.
      ELSE.
        cv_reason = lv_reason.
      ENDIF.
      cv_ok = abap_true.
      RETURN.
    ENDIF.
    cv_message = |{ lv_meta_msg } SPA/GPA fallback: { lv_pid_msg }|.
    RETURN.
  ENDIF.

  SELECT SINGLE ttext FROM tstct
    INTO @lv_target_ttext
    WHERE sprsl = @sy-langu
      AND tcode = @lv_target.

  "Stage 2 maps ALL required key components only to exact target-screen
  "elements/actions discovered from SAP Screen Painter. No business-specific
  "field/PID/TCODE mapping exists in code or prompt.
  CLEAR: lv_prompt, lv_resp, lv_json, lv_call_ok.
  lv_prompt =
    |You are an SAP GUI target-screen binding selector. Use ONLY the exact current SUCCESS values and exact SAP Screen Painter evidence below. | &&
    |Do not invent a field, label, Parameter ID, action code, object value or extra key. | &&
    |Map EVERY key component required to identify the current object on this exact repository-proven target screen. | &&
    |Return ONLY one raw JSON object with exactly these string fields: | &&
    |"status" (CANDIDATE or NOT_PROVEN), "binding_count" (1-4), | &&
    |"key_source_1", "screen_field_1", "key_source_2", "screen_field_2", | &&
    |"key_source_3", "screen_field_3", "key_source_4", "screen_field_4", | &&
    |"action_code", "confidence" (0-100), and "reason" (max 240 chars). | &&
    |Each key_source_N must be exactly one non-empty MSGV1..MSGV4 and unique. | &&
    |Each screen_field_N must exactly equal one FIELD with BINDABLE=X in SCREEN_EVIDENCE and be unique. Prefer INPUT=X when available. | &&
    |If a shared dynpro has no static INPUT=X, a BINDABLE=X field may still become input-ready in transaction PBO; do not invent any field outside the exact evidence. | &&
    |action_code must exactly equal one ACTION value present in SCREEN_EVIDENCE, including /00 when standard Enter is sufficient. | &&
    |Use CANDIDATE only when the complete current object key can be bound to exact repository I/O fields; the following visible SAP runtime probe and user Certify/Reject are the final proof. | &&
    |Target: TCODE={ lv_target }; TEXT={ lv_target_ttext }; PROGRAM={ cv_program }; DYNPRO={ cv_dynpro }. | &&
    |Current SUCCESS: MSGID={ is_nav-msgid }; MSGNR={ is_nav-msgnr }; MESSAGE={ is_nav-message_text }; | &&
    |MSGV1={ is_nav-msgv1 }; MSGV2={ is_nav-msgv2 }; MSGV3={ is_nav-msgv3 }; MSGV4={ is_nav-msgv4 }. | &&
    |SCREEN_EVIDENCE:| && cl_abap_char_utilities=>newline && lv_screen_ev.

  PERFORM call_ai_endpoint
    USING    'NAV' lv_endpoint lv_prompt
    CHANGING lv_resp lv_call_ok.
  IF lv_call_ok <> abap_true OR lv_resp IS INITIAL.
    cv_message = |AI target-screen binding failed: { gv_z619_ai_http_diag }|.
    RETURN.
  ENDIF.

  PERFORM extract_openai_text USING lv_resp CHANGING lv_json.
  IF lv_json IS INITIAL.
    lv_json = lv_resp.
  ENDIF.
  REPLACE ALL OCCURRENCES OF '```json' IN lv_json WITH ''.
  REPLACE ALL OCCURRENCES OF '```JSON' IN lv_json WITH ''.
  REPLACE ALL OCCURRENCES OF '```'     IN lv_json WITH ''.
  CONDENSE lv_json.

  CLEAR: lv_status, lv_count_txt, lv_action_raw, lv_confidence, lv_reason.
  PERFORM json_get_bup USING lv_json 'status' CHANGING lv_status.
  PERFORM json_get_bup USING lv_json 'binding_count' CHANGING lv_count_txt.
  IF lv_count_txt IS INITIAL.
    PERFORM json_get_bup USING lv_json 'bindingCount' CHANGING lv_count_txt.
  ENDIF.
  PERFORM json_get_bup USING lv_json 'action_code' CHANGING lv_action_raw.
  IF lv_action_raw IS INITIAL.
    PERFORM json_get_bup USING lv_json 'actionCode' CHANGING lv_action_raw.
  ENDIF.
  PERFORM json_get_bup USING lv_json 'confidence' CHANGING lv_confidence.
  PERFORM json_get_bup USING lv_json 'reason' CHANGING lv_reason.

  TRANSLATE: lv_status TO UPPER CASE, lv_action_raw TO UPPER CASE.
  CONDENSE: lv_status NO-GAPS, lv_count_txt NO-GAPS, lv_action_raw NO-GAPS.
  IF lv_status <> 'CANDIDATE'.
    IF lv_reason IS INITIAL.
      lv_reason = 'AI could not prove a complete mapping from the current SAP message to exact target-screen fields.'.
    ENDIF.
    cv_message = lv_reason.
    RETURN.
  ENDIF.

  TRY.
      lv_count = lv_count_txt.
    CATCH cx_sy_conversion_no_number cx_sy_conversion_overflow.
      cv_message = 'AI returned an invalid binding_count.'.
      RETURN.
  ENDTRY.
  IF lv_count < 1 OR lv_count > 4.
    cv_message = 'AI binding_count must be between 1 and 4.'.
    RETURN.
  ENDIF.
  IF lv_action_raw IS INITIAL.
    cv_message = 'AI did not return the exact target-screen submit action.'.
    RETURN.
  ENDIF.

  CLEAR lv_action_found.
  IF lv_action_raw = '/00'.
    lv_action_found = abap_true.
  ELSE.
    LOOP AT lt_screen INTO ls_screen WHERE func_code = lv_action_raw.
      lv_action_found = abap_true.
      EXIT.
    ENDLOOP.
  ENDIF.
  IF lv_action_found <> abap_true.
    cv_message = |AI action { lv_action_raw } is not present in the exact SAP Screen Painter evidence.|.
    RETURN.
  ENDIF.

  REFRESH ct_binding.
  DO lv_count TIMES.
    lv_i = sy-index.
    lv_i_txt = lv_i.
    CONDENSE lv_i_txt NO-GAPS.
    CLEAR: lv_src, lv_field_raw, lv_kind_src, lv_kind_field,
           lv_idx, lv_value, ls_binding, ls_screen.

    CONCATENATE 'key_source_' lv_i_txt INTO lv_kind_src.
    CONCATENATE 'screen_field_' lv_i_txt INTO lv_kind_field.
    PERFORM json_get_bup USING lv_json lv_kind_src CHANGING lv_src.
    PERFORM json_get_bup USING lv_json lv_kind_field CHANGING lv_field_raw.
    TRANSLATE: lv_src TO UPPER CASE, lv_field_raw TO UPPER CASE.
    CONDENSE: lv_src NO-GAPS, lv_field_raw NO-GAPS.

    CASE lv_src.
      WHEN 'MSGV1'. lv_idx = '1'.
      WHEN 'MSGV2'. lv_idx = '2'.
      WHEN 'MSGV3'. lv_idx = '3'.
      WHEN 'MSGV4'. lv_idx = '4'.
      WHEN OTHERS.
        cv_message = |AI returned invalid key source { lv_src } for binding { lv_i }.|.
        REFRESH ct_binding.
        RETURN.
    ENDCASE.

    PERFORM nav_evidence_value USING is_nav lv_idx CHANGING lv_value.
    IF lv_value IS INITIAL.
      cv_message = |AI selected MSGV{ lv_idx }, but that exact SAP message variable is empty.|.
      REFRESH ct_binding.
      RETURN.
    ENDIF.
    IF lv_field_raw IS INITIAL.
      cv_message = |AI did not identify an exact SAP screen field for binding { lv_i }.|.
      REFRESH ct_binding.
      RETURN.
    ENDIF.

    READ TABLE lt_screen INTO ls_screen WITH KEY field_name = lv_field_raw.
    IF sy-subrc <> 0 OR ls_screen-field_name IS INITIAL OR ls_screen-bindable <> abap_true.
      cv_message = |AI field { lv_field_raw } is not an exact repository-proven bindable I/O field on the target start screen.|.
      REFRESH ct_binding.
      RETURN.
    ENDIF.

    READ TABLE ct_binding TRANSPORTING NO FIELDS WITH KEY msgv_idx = lv_idx.
    IF sy-subrc = 0.
      cv_message = 'AI repeated one MSGV source in the navigation binding.'.
      REFRESH ct_binding.
      RETURN.
    ENDIF.
    READ TABLE ct_binding TRANSPORTING NO FIELDS WITH KEY field_name = ls_screen-field_name.
    IF sy-subrc = 0.
      cv_message = 'AI repeated one target screen field in the navigation binding.'.
      REFRESH ct_binding.
      RETURN.
    ENDIF.

    ls_binding-seq        = lv_i.
    ls_binding-msgv_idx   = lv_idx.
    ls_binding-field_name = ls_screen-field_name.
    ls_binding-param_id   = ls_screen-param_id.
    ls_binding-value      = lv_value.
    APPEND ls_binding TO ct_binding.
  ENDDO.

  cv_target      = lv_target.
  cv_action      = lv_action_raw.
  cv_object_type = lv_object_type.
  cv_confidence  = lv_confidence.
  cv_reason      = lv_reason.
  cv_ok          = abap_true.
ENDFORM.

*&---------------------------------------------------------------------*
*& AI-discover, live-test and certify navigation from one SUCCESS row.
*& The business user never enters TCODE, Parameter IDs, MSGID/MSGNR or MSGV mappings.
*& AI proposes; SAP repository checks and the real landing prove.
*&---------------------------------------------------------------------*
*&---------------------------------------------------------------------*
*& /o-style disposable AI Navigation launcher
*& Uses SAP standard TH_CREATE_MODE, like the SM35 monitor flow, so the
*& original cockpit remains alive in its own mode. DEL_ON_EOT=1 makes the
*& temporary child mode close when the target transaction ends; Back/Exit
*& therefore returns the user to the original cockpit instead of leaving an
*& orphan SAP Easy Access window.
*&
*& PARAM_MEMORY routes reuse only the exact certified SPA/GPA bindings.
*& Classic SCREEN_BDC routes can be represented losslessly in a child mode
*& only when their exact certified action is standard Enter (/00): the target
*& screen fields are passed through TH_CREATE_MODE-PARAMETERS and the first
*& screen is processed dark. Non-Enter routes deliberately fall back to the
*& existing exact BDC launcher below rather than pretending /o reproduced an
*& action that TH_CREATE_MODE cannot prove.
*&---------------------------------------------------------------------*
FORM open_nav_target_new_mode
  USING    iv_target    TYPE sy-tcode
           iv_action    TYPE syucomm
  CHANGING ct_binding   TYPE ty_t_nav_binding
           cv_handled   TYPE abap_bool
           cv_ok        TYPE abap_bool
           cv_message   TYPE string.

  DATA: lv_mode        TYPE sy-index,
        lv_mode_rc     TYPE sy-subrc,
        lv_parameters  TYPE string,
        lv_piece       TYPE string,
        lv_action_norm TYPE syucomm.

  CLEAR: cv_handled, cv_ok, cv_message,
         lv_mode, lv_mode_rc, lv_parameters, lv_piece, lv_action_norm.

  IF iv_target IS INITIAL OR ct_binding IS INITIAL.
    RETURN.
  ENDIF.

  lv_action_norm = iv_action.
  CONDENSE lv_action_norm NO-GAPS.
  TRANSLATE lv_action_norm TO UPPER CASE.

  IF lv_action_norm = '@PARAM'.
    cv_handled = abap_true.

    LOOP AT ct_binding INTO DATA(ls_param_child).
      IF ls_param_child-param_id IS INITIAL OR ls_param_child-value IS INITIAL.
        cv_message = 'Certified SPA/GPA navigation binding is incomplete for the selected SUCCESS row.'.
        RETURN.
      ENDIF.
    ENDLOOP.

    "Set the exact current-row values only for the short handoff. TH_CREATE_MODE
    "starts the target transaction in the new external mode; restore the caller
    "mode's previous SAP-memory values immediately after the handoff returns.
    PERFORM apply_nav_binding_params CHANGING ct_binding.

    CALL FUNCTION 'TH_CREATE_MODE'
      EXPORTING
        transaktion    = iv_target
        del_on_eot     = 1
        process_dark   = 'X'
      IMPORTING
        mode           = lv_mode
      EXCEPTIONS
        max_sessions   = 1
        internal_error = 2
        no_authority   = 3
        OTHERS         = 4.
    lv_mode_rc = sy-subrc.

    PERFORM restore_nav_binding_params USING ct_binding.

  ELSE.
    "TH_CREATE_MODE processes the first screen with standard Enter. Preserve
    "the exact certified semantics: only /00 is eligible for this child-mode
    "projection. A non-Enter route is left to the exact BDC path in the caller.
    IF lv_action_norm <> '/00'.
      RETURN.
    ENDIF.

    LOOP AT ct_binding INTO DATA(ls_screen_child).
      IF ls_screen_child-field_name IS INITIAL OR ls_screen_child-value IS INITIAL.
        RETURN.
      ENDIF.

      "The PARAMETERS grammar uses ';' as the item separator. If an exact SAP
      "value itself contains that delimiter/newline, do not lossy-escape it;
      "fall back to the existing exact BDC route instead.
      IF ls_screen_child-field_name CS ';' OR
         ls_screen_child-value CS ';' OR
         ls_screen_child-field_name CS cl_abap_char_utilities=>newline OR
         ls_screen_child-value CS cl_abap_char_utilities=>newline.
        RETURN.
      ENDIF.

      lv_piece = |{ ls_screen_child-field_name }={ ls_screen_child-value };|.
      IF lv_parameters IS INITIAL.
        lv_parameters = lv_piece.
      ELSE.
        lv_parameters = lv_parameters && lv_piece.
      ENDIF.
    ENDLOOP.

    IF lv_parameters IS INITIAL.
      RETURN.
    ENDIF.

    cv_handled = abap_true.
    CALL FUNCTION 'TH_CREATE_MODE'
      EXPORTING
        transaktion    = iv_target
        del_on_eot     = 1
        parameters     = lv_parameters
        process_dark   = 'X'
      IMPORTING
        mode           = lv_mode
      EXCEPTIONS
        max_sessions   = 1
        internal_error = 2
        no_authority   = 3
        OTHERS         = 4.
    lv_mode_rc = sy-subrc.
  ENDIF.

  CASE lv_mode_rc.
    WHEN 0.
      cv_ok = abap_true.
      cv_message = |AI Navigation opened { iv_target } in a temporary /o-style SAP mode. Back/Exit there returns to the original cockpit.|.
    WHEN 1.
      cv_message = |AI Navigation could not open { iv_target } in a new SAP mode because the maximum number of modes is already open. Close one SAP mode and try again.|.
    WHEN 3.
      cv_message = |You are not authorized to open transaction { iv_target } in a new SAP mode.|.
    WHEN OTHERS.
      cv_message = |SAP could not create the temporary AI Navigation mode for { iv_target } (TH_CREATE_MODE={ lv_mode_rc }). The cockpit was left unchanged.|.
  ENDCASE.
ENDFORM.

*&---------------------------------------------------------------------*
*& Safe current-row navigation launcher
*& The selected SUCCESS row supplies every key value. The certified route may
*& be shared by Script ID, but no previous user's object value is ever reused.
*& Keep the target's first screen visible: AND SKIP FIRST SCREEN is deliberately
*& forbidden here because a transaction that does not consume the proposed
*& SPA/GPA IDs can otherwise fall through to remembered SAP GUI/application
*& state and appear to open another user's/previous object.
*&---------------------------------------------------------------------*
FORM call_nav_target_safe
  USING    iv_target    TYPE sy-tcode
           iv_program   TYPE d020s-prog
           iv_dynpro    TYPE d020s-dnum
           iv_action    TYPE syucomm
  CHANGING ct_binding   TYPE ty_t_nav_binding
           cv_ok        TYPE abap_bool
           cv_message   TYPE string.

  DATA: lv_tstc       TYPE tstc-tcode,
        lv_live_prog  TYPE d020s-prog,
        lv_live_dyn   TYPE d020s-dnum,
        lv_live_ev    TYPE string,
        lt_live_meta  TYPE ty_t_nav_screen_field,
        ls_live_meta  TYPE ty_nav_screen_field,
        lv_meta_ok    TYPE abap_bool,
        lv_meta_msg   TYPE string,
        lv_action_ok  TYPE abap_bool,
        lv_bdc_action TYPE bdcdata-fval,
        lt_bdc        TYPE STANDARD TABLE OF bdcdata,
        ls_bdc        TYPE bdcdata,
        lt_msg        TYPE STANDARD TABLE OF bdcmsgcoll,
        ls_opt        TYPE ctu_params,
        lv_call_subrc TYPE sy-subrc.

  CLEAR: cv_ok, cv_message.

  IF iv_target IS INITIAL OR iv_action IS INITIAL OR ct_binding IS INITIAL.
    cv_message = 'Navigation target, action and current-row bindings are required.'.
    RETURN.
  ENDIF.
  IF iv_action <> '@PARAM' AND
     ( iv_program IS INITIAL OR iv_dynpro IS INITIAL ).
    cv_message = 'Classic screen navigation requires the exact target program and dynpro.'.
    RETURN.
  ENDIF.

  SELECT SINGLE tcode FROM tstc
    INTO @lv_tstc
    WHERE tcode = @iv_target.
  IF sy-subrc <> 0.
    cv_message = |Navigation target { iv_target } does not exist in this SAP system.|.
    RETURN.
  ENDIF.
  AUTHORITY-CHECK OBJECT 'S_TCODE' ID 'TCD' FIELD iv_target.
  IF sy-subrc <> 0.
    cv_message = |You are not authorized to open transaction { iv_target }.|.
    RETURN.
  ENDIF.

  "V17.9.3 parameter-memory route. Keep the exact current-row binding, but
  "launch it in a disposable /o-style child mode so the 0400 cockpit never
  "leaves its own external SAP mode. Back/Exit from the target closes the child.
  IF iv_action = '@PARAM'.
    DATA: lv_child_handled_pm TYPE abap_bool,
          lv_child_ok_pm      TYPE abap_bool,
          lv_child_msg_pm     TYPE string.

    PERFORM open_nav_target_new_mode
      USING    iv_target iv_action
      CHANGING ct_binding lv_child_handled_pm lv_child_ok_pm lv_child_msg_pm.

    IF lv_child_handled_pm = abap_true.
      cv_ok      = lv_child_ok_pm.
      cv_message = lv_child_msg_pm.
      RETURN.
    ENDIF.

    cv_message = 'Certified SPA/GPA navigation route could not be represented in a separate SAP mode.'.
    RETURN.
  ENDIF.

  "Re-read Screen Painter metadata on every classic screen-BDC launch. A shared
  "certificate is never trusted if the live target screen no longer matches.
  CLEAR: lv_live_prog, lv_live_dyn, lv_live_ev, lv_meta_ok, lv_meta_msg.
  REFRESH lt_live_meta.
  PERFORM load_nav_screen_meta
    USING    iv_target
    CHANGING lv_live_prog lv_live_dyn lt_live_meta lv_live_ev lv_meta_ok lv_meta_msg.
  IF lv_meta_ok <> abap_true.
    cv_message = lv_meta_msg.
    RETURN.
  ENDIF.
  IF lv_live_prog <> iv_program OR lv_live_dyn <> iv_dynpro.
    cv_message = 'Certified navigation start screen no longer matches the current SAP repository.'.
    RETURN.
  ENDIF.

  LOOP AT ct_binding INTO DATA(ls_binding_check).
    IF ls_binding_check-field_name IS INITIAL OR ls_binding_check-value IS INITIAL.
      cv_message = 'Navigation field binding is incomplete for the selected SUCCESS row.'.
      RETURN.
    ENDIF.
    READ TABLE lt_live_meta INTO ls_live_meta
      WITH KEY field_name = ls_binding_check-field_name.
    IF sy-subrc <> 0 OR ls_live_meta-bindable <> abap_true.
      cv_message = |Certified target field { ls_binding_check-field_name } is no longer a repository-proven bindable I/O element on the SAP start screen.|.
      RETURN.
    ENDIF.
  ENDLOOP.

  CLEAR lv_action_ok.
  IF iv_action = '/00'.
    lv_action_ok = abap_true.
  ELSE.
    LOOP AT lt_live_meta INTO ls_live_meta WHERE func_code = iv_action.
      lv_action_ok = abap_true.
      EXIT.
    ENDLOOP.
  ENDIF.
  IF lv_action_ok <> abap_true.
    cv_message = |Certified action { iv_action } no longer exists on the exact target screen.|.
    RETURN.
  ENDIF.

  "Prefer a disposable /o-style child mode whenever the exact classic route
  "can be represented without losing semantics. Standard Enter (/00) routes
  "are passed as first-screen field parameters and processed dark. Routes that
  "need a non-Enter OKCODE stay on the existing exact BDC path below.
  DATA: lv_child_handled_sc TYPE abap_bool,
        lv_child_ok_sc      TYPE abap_bool,
        lv_child_msg_sc     TYPE string.
  PERFORM open_nav_target_new_mode
    USING    iv_target iv_action
    CHANGING ct_binding lv_child_handled_sc lv_child_ok_sc lv_child_msg_sc.
  IF lv_child_handled_sc = abap_true.
    cv_ok      = lv_child_ok_sc.
    cv_message = lv_child_msg_sc.
    RETURN.
  ENDIF.

  REFRESH: lt_bdc, lt_msg.
  CLEAR ls_bdc.
  ls_bdc-program  = iv_program.
  ls_bdc-dynpro   = iv_dynpro.
  ls_bdc-dynbegin = 'X'.
  APPEND ls_bdc TO lt_bdc.

  LOOP AT ct_binding INTO DATA(ls_binding_run).
    CLEAR ls_bdc.
    ls_bdc-fnam = ls_binding_run-field_name.
    ls_bdc-fval = ls_binding_run-value.
    APPEND ls_bdc TO lt_bdc.
  ENDLOOP.

  lv_bdc_action = iv_action.
  IF lv_bdc_action(1) <> '/' AND lv_bdc_action(1) <> '='.
    lv_bdc_action = '=' && lv_bdc_action.
  ENDIF.
  CLEAR ls_bdc.
  ls_bdc-fnam = 'BDC_OKCODE'.
  ls_bdc-fval = lv_bdc_action.
  APPEND ls_bdc TO lt_bdc.

  CLEAR ls_opt.
  "Post-success AI Navigation is an interactive DISPLAY verification. Show the
  "target screens, then leave SAP in normal dialog mode after BDC data ends so
  "the user can inspect the exact object before returning to Certify/Reject.
  ls_opt-dismode = 'A'.
  ls_opt-updmode = 'S'.
  ls_opt-defsize = 'X'.
  ls_opt-nobiend = 'X'.
  CLEAR: ls_opt-racommit, ls_opt-nobinpt, ls_opt-cattmode.

  "This post-success navigation call is deliberately independent of the
  "executor that created the object. CT A/E/N, CT update mode, and every BISM
  "processing mode are irrelevant here: one terminal SUCCESS row is enough.
  CALL TRANSACTION iv_target
    USING lt_bdc
    OPTIONS FROM ls_opt
    MESSAGES INTO lt_msg.
  lv_call_subrc = sy-subrc.

  IF lv_call_subrc <> 0.
    cv_message = |SAP could not consume the display route for { iv_target } (SY-SUBRC={ lv_call_subrc }).|.
    RETURN.
  ENDIF.

  "Do not treat a syntactically accepted BDC call as proof when SAP returned a
  "hard protocol error. Soft/informational messages remain visible for manual
  "landing verification.
  LOOP AT lt_msg INTO DATA(ls_nav_msg).
    IF ls_nav_msg-msgtyp = 'E' OR ls_nav_msg-msgtyp = 'A' OR ls_nav_msg-msgtyp = 'X'.
      cv_message = |SAP rejected the display route for { iv_target }: { ls_nav_msg-msgid }-{ ls_nav_msg-msgnr }.|.
      RETURN.
    ENDIF.
  ENDLOOP.

  cv_ok = abap_true.
  cv_message = |SAP consumed the exact current-row display bindings for { iv_target }.|.
ENDFORM.

*&---------------------------------------------------------------------*
*& Persist a verified current-row object label without changing execution truth.
*& The exact persisted SAP S-message remains the authority; only SAP_OBJECT_ID
*& is annotated after the user has visibly verified the navigation landing.
*&---------------------------------------------------------------------*
FORM persist_nav_obj_exec
  USING    is_exec    TYPE ty_exec_disp
           is_nav     TYPE ty_nav_evidence
           iv_object  TYPE zbdc_result_bup-sap_object_id
           it_binding TYPE ty_t_nav_binding
  CHANGING cv_ok      TYPE abap_bool
           cv_message TYPE string.

  DATA: lt_res       TYPE ty_t_result,
        ls_res       TYPE zbdc_result_bup,
        lv_group     TYPE string,
        lv_row_key   TYPE char40,
        lv_msgid     TYPE symsgid,
        lv_msgnr     TYPE symsgno,
        lv_v1        TYPE string,
        lv_v2        TYPE string,
        lv_v3        TYPE string,
        lv_v4        TYPE string,
        lv_e1        TYPE string,
        lv_e2        TYPE string,
        lv_e3        TYPE string,
        lv_e4        TYPE string,
        lt_candidate TYPE ty_t_nav_binding,
        ls_binding   TYPE ty_nav_binding,
        lv_value     TYPE string,
        lv_expected  TYPE string,
        lv_bad       TYPE abap_bool.

  CLEAR: cv_ok, cv_message.

  IF is_exec-session_id IS INITIAL OR is_exec-group_key IS INITIAL OR
     is_nav-msgid IS INITIAL OR is_nav-msgnr IS INITIAL OR
     iv_object IS INITIAL OR it_binding IS INITIAL.
    cv_message = 'Verified navigation object cannot be persisted because the exact current-row evidence is incomplete.'.
    RETURN.
  ENDIF.

  SELECT * FROM zbdc_result_bup
    INTO TABLE @lt_res
    WHERE session_id = @is_exec-session_id.
  SORT lt_res BY created_at DESCENDING step DESCENDING.

  "V17.9.3.4 composite-key stability: DERIVE_NAV_BOOTSTRAP_EVIDENCE
  "already selected one exact persisted SAP SUCCESS row before AI discovery.
  "After the visible target is Certify'ed, bind SAP_OBJECT_ID back to that
  "same structured message evidence (MSGID/MSGNR + all four MSGV slots), not
  "to a reconstructed display label. This is generic for single- and
  "multi-component keys and cannot leak a route from another TCODE/script.
  lv_e1 = is_nav-msgv1.
  lv_e2 = is_nav-msgv2.
  lv_e3 = is_nav-msgv3.
  lv_e4 = is_nav-msgv4.
  CONDENSE: lv_e1, lv_e2, lv_e3, lv_e4.

  LOOP AT lt_res INTO ls_res.
    IF ls_res-msg_type <> 'S'.
      CONTINUE.
    ENDIF.

    IF ls_res-record_key IS NOT INITIAL.
      lv_group = ls_res-record_key.
    ELSE.
      CLEAR lv_row_key.
      WRITE ls_res-row_index TO lv_row_key LEFT-JUSTIFIED.
      CONDENSE lv_row_key NO-GAPS.
      lv_group = lv_row_key.
    ENDIF.
    IF lv_group <> is_exec-group_key.
      CONTINUE.
    ENDIF.

    CLEAR: lv_msgid, lv_msgnr, lv_v1, lv_v2, lv_v3, lv_v4.
    PERFORM read_result_message_parts
      USING    ls_res
      CHANGING lv_msgid lv_msgnr lv_v1 lv_v2 lv_v3 lv_v4.
    IF lv_msgid <> is_nav-msgid OR lv_msgnr <> is_nav-msgnr.
      CONTINUE.
    ENDIF.

    CONDENSE: lv_v1, lv_v2, lv_v3, lv_v4.
    IF lv_v1 <> lv_e1 OR lv_v2 <> lv_e2 OR
       lv_v3 <> lv_e3 OR lv_v4 <> lv_e4.
      CONTINUE.
    ENDIF.

    "When the bootstrap used the exact cockpit business text, keep that as an
    "additional discriminator. The compatibility fallback still works because
    "IS_NAV-MESSAGE_TEXT was copied from the exact fallback row itself.
    IF is_nav-message_text IS NOT INITIAL AND
       ls_res-message <> is_nav-message_text.
      CONTINUE.
    ENDIF.

    "The AI is never trusted to mutate identity. Every certified binding must
    "still point to the same exact MSGV value carried by this persisted row.
    lt_candidate = it_binding.
    CLEAR lv_bad.
    LOOP AT lt_candidate INTO ls_binding.
      CLEAR: lv_value, lv_expected.
      CASE ls_binding-msgv_idx.
        WHEN '1'. lv_value = lv_v1.
        WHEN '2'. lv_value = lv_v2.
        WHEN '3'. lv_value = lv_v3.
        WHEN '4'. lv_value = lv_v4.
        WHEN OTHERS. lv_bad = abap_true.
      ENDCASE.
      lv_expected = ls_binding-value.
      CONDENSE: lv_value, lv_expected.
      IF lv_bad = abap_true OR lv_value IS INITIAL OR
         lv_expected IS INITIAL OR lv_value <> lv_expected.
        lv_bad = abap_true.
        EXIT.
      ENDIF.
    ENDLOOP.
    IF lv_bad = abap_true.
      CONTINUE.
    ENDIF.

    IF ls_res-sap_object_id IS INITIAL.
      ls_res-sap_object_id = iv_object.
      MODIFY zbdc_result_bup FROM ls_res.
      IF sy-subrc <> 0.
        cv_message = 'The verified current-row object could not be attached to its exact persisted SAP success message.'.
        RETURN.
      ENDIF.
    ELSEIF ls_res-sap_object_id <> iv_object.
      cv_message = |Current-row object conflict: persisted { ls_res-sap_object_id }, verified { iv_object }. Nothing was overwritten.|.
      RETURN.
    ENDIF.

    cv_ok = abap_true.
    cv_message = |Verified current-row object { iv_object } is bound to the exact structured SAP success evidence.|.
    RETURN.
  ENDLOOP.

  cv_message = 'No exact persisted SAP success message matched the selected row; Document was not certified.'.
ENDFORM.

*&---------------------------------------------------------------------*
*& AI-discover, visibly test and certify navigation from one SUCCESS row.
*& Only Screen 0400 owns this action. A certified route is reusable, but every
*& click re-resolves the exact key tuple from the selected current execution.
*&---------------------------------------------------------------------*
FORM configure_selected_navigation.
  DATA: lt_rows          TYPE lvc_t_row,
        ls_row           TYPE lvc_s_row,
        ls_exec          TYPE ty_exec_disp,
        ls_nav           TYPE ty_nav_evidence,
        lt_binding       TYPE ty_t_nav_binding,
        ls_binding       TYPE ty_nav_binding,
        lt_res           TYPE ty_t_result,
        lv_ok            TYPE abap_bool,
        lv_message       TYPE string,
        lv_navstate      TYPE zbdc_config_bup-config_value,
        lv_target        TYPE sy-tcode,
        lv_program       TYPE d020s-prog,
        lv_dynpro        TYPE d020s-dnum,
        lv_action        TYPE syucomm,
        lv_msgid         TYPE symsgid,
        lv_msgnr         TYPE symsgno,
        lv_contract_ok   TYPE abap_bool,
        lv_contract_msg  TYPE string,
        lv_resolve_ok    TYPE abap_bool,
        lv_resolve_msg   TYPE string,
        lv_object        TYPE zbdc_result_bup-sap_object_id,
        lv_tuple_txt     TYPE string,
        lv_object_type   TYPE c LENGTH 60,
        lv_confidence    TYPE c LENGTH 10,
        lv_reason        TYPE string,
        lv_answer        TYPE c LENGTH 1,
        lv_question      TYPE string,
        lv_count_txt     TYPE c LENGTH 1,
        lv_kind          TYPE c LENGTH 20,
        lv_seq_txt       TYPE c LENGTH 1.

  IF sy-dynnr <> '0400' OR gv_0400_view <> gc_view_cockpit OR go_exec_grid IS NOT BOUND.
    MESSAGE 'AI Navigation is available only in the Staging Execution Cockpit.' TYPE 'S' DISPLAY LIKE 'W'.
    RETURN.
  ENDIF.

  CALL METHOD cl_gui_cfw=>flush EXCEPTIONS OTHERS = 1.
  CALL METHOD go_exec_grid->get_selected_rows
    IMPORTING et_index_rows = lt_rows.
  SORT lt_rows BY index.
  DELETE ADJACENT DUPLICATES FROM lt_rows COMPARING index.

  IF lines( lt_rows ) <> 1.
    MESSAGE 'Select exactly one SUCCESS row before AI Navigation.' TYPE 'S' DISPLAY LIKE 'W'.
    RETURN.
  ENDIF.

  READ TABLE lt_rows INTO ls_row INDEX 1.
  READ TABLE gt_exec_disp INTO ls_exec INDEX ls_row-index.

 "V17.9.3.4 scope stability: frontend selection and backend cockpit must refer
 "to the same visible session/batch. A stale ALV index from a prior roundtrip
 "must never launch AI against an older SUCCESS row.
  DATA: lv_visible_sid_934 TYPE zbdc_staging_bup-session_id,
        lv_visible_batch_934 TYPE zbdc_staging_bup-session_id,
        lv_selected_batch_934 TYPE zbdc_staging_bup-session_id,
        lv_scope_member_934 TYPE abap_bool.
  IF gv_0400_context_locked = abap_true
     AND gv_0400_context_sid IS NOT INITIAL.
    lv_visible_sid_934 = gv_0400_context_sid.
  ELSE.
    lv_visible_sid_934 = txtp_session_id.
    CONDENSE lv_visible_sid_934.
    IF lv_visible_sid_934 IS INITIAL.
      lv_visible_sid_934 = txtp_sess.
      CONDENSE lv_visible_sid_934.
    ENDIF.
  ENDIF.
  CONDENSE lv_visible_sid_934.

  CLEAR lv_scope_member_934.
  IF sy-subrc = 0 AND lv_visible_sid_934 IS NOT INITIAL.
    IF ls_exec-session_id = lv_visible_sid_934.
      lv_scope_member_934 = abap_true.
    ELSEIF gv_0400_batch_scope = abap_true
       AND lines( gt_current_sessions ) > 1.
      READ TABLE gt_current_sessions
        WITH KEY table_line = ls_exec-session_id
        TRANSPORTING NO FIELDS.
      IF sy-subrc = 0.
        PERFORM batch_prefix_from_sid
          USING    lv_visible_sid_934
          CHANGING lv_visible_batch_934.
        PERFORM batch_prefix_from_sid
          USING    ls_exec-session_id
          CHANGING lv_selected_batch_934.
        IF lv_visible_batch_934 IS NOT INITIAL
           AND lv_visible_batch_934 = gv_current_batch_prefix
           AND lv_selected_batch_934 = gv_current_batch_prefix.
          lv_scope_member_934 = abap_true.
        ENDIF.
      ENDIF.
    ENDIF.
  ENDIF.

  IF lv_visible_sid_934 IS NOT INITIAL AND lv_scope_member_934 <> abap_true.
    DATA: lv_ctx_repair_ok_934 TYPE abap_bool,
          lv_ctx_repair_msg_934 TYPE string.
    CLEAR: lv_ctx_repair_ok_934, lv_ctx_repair_msg_934.
    PERFORM repair_0400_context
      CHANGING lv_ctx_repair_ok_934 lv_ctx_repair_msg_934.
    IF lv_ctx_repair_ok_934 = abap_true.
      PERFORM prepare_alv_0400.
      PERFORM build_exec_cockpit.
      PERFORM update_0400_counters.
      PERFORM refresh_0400_grid.
      MESSAGE 'Cockpit context was repaired to the frozen Session ID. Reselect the SUCCESS row.' TYPE 'S' DISPLAY LIKE 'W'.
    ELSE.
      MESSAGE lv_ctx_repair_msg_934 TYPE 'S' DISPLAY LIKE 'E'.
    ENDIF.
    RETURN.
  ENDIF.

  "Executor/mode is intentionally irrelevant. Any terminal SUCCESS row from
  "CALL TRANSACTION (A/E/N, any update mode) or BISM/SM35 is eligible.
  IF sy-subrc <> 0 OR ls_exec-run_status <> gc_st_success.
    MESSAGE 'AI Navigation requires exactly one terminal SUCCESS row (CT or BISM).' TYPE 'S' DISPLAY LIKE 'W'.
    RETURN.
  ENDIF.

  CLEAR: ls_nav, lv_ok, lv_message.
  PERFORM derive_nav_bootstrap_evidence
    USING    ls_exec
    CHANGING ls_nav lv_ok lv_message.
  IF lv_ok <> abap_true.
    MESSAGE lv_message TYPE 'S' DISPLAY LIKE 'W'.
    RETURN.
  ENDIF.

  "Reuse only a complete SCREEN_BDC route. Key VALUES are always rebuilt from
  "the currently selected SESSION_ID + GROUP_KEY, never from another user.
  PERFORM get_script_cfg USING ls_nav-script_id 'NAVSTATE' CHANGING lv_navstate.
  TRANSLATE lv_navstate TO UPPER CASE.
  CONDENSE lv_navstate NO-GAPS.

  IF lv_navstate = 'CERTIFIED'.
    CLEAR: lv_contract_ok, lv_contract_msg, lv_target, lv_program, lv_dynpro,
           lv_action, lv_msgid, lv_msgnr, lt_binding, lt_res,
           lv_resolve_ok, lv_resolve_msg, lv_object, lv_tuple_txt.

    PERFORM load_nav_binding_contract
      USING    ls_nav-script_id
      CHANGING lv_navstate lv_target lv_program lv_dynpro lv_action
               lv_msgid lv_msgnr lt_binding lv_contract_ok lv_contract_msg.

    IF lv_contract_ok = abap_true.
      SELECT * FROM zbdc_result_bup
        INTO TABLE @lt_res
        WHERE session_id = @ls_exec-session_id.
      SORT lt_res BY created_at DESCENDING step DESCENDING.

      IF lv_action = '@PARAM' AND lines( lt_binding ) = 1.
        READ TABLE lt_binding INTO DATA(ls_reuse_param) INDEX 1.
        IF sy-subrc = 0 AND
           ( ls_reuse_param-msgv_idx CN '1234' OR
             strlen( ls_reuse_param-msgv_idx ) <> 1 ).
          CLEAR: lv_ok, lv_message.
          PERFORM hydrate_param_msgv
            USING    ls_exec lt_res lv_msgid lv_msgnr ls_exec-sap_object_id
            CHANGING lt_binding lv_ok lv_message.
        ENDIF.
      ENDIF.

      PERFORM resolve_nav_bindings_for_exec
        USING    ls_exec lt_res lv_msgid lv_msgnr ls_exec-sap_object_id
        CHANGING lt_binding lv_object lv_tuple_txt lv_resolve_ok lv_resolve_msg.

      IF lv_resolve_ok = abap_true.
        CLEAR: lv_ok, lv_message.
        PERFORM call_nav_target_safe
          USING    lv_target lv_program lv_dynpro lv_action
          CHANGING lt_binding lv_ok lv_message.
        IF lv_ok = abap_true.
         "Re-pin 0400 to the exact selected SUCCESS session after returning
         "from the certified SAP target. Never let an older batch/session
         "context repaint the cockpit on the next PBO.
          DATA lv_reuse_nav_count_14a TYPE i.
          CLEAR lv_reuse_nav_count_14a.
          PERFORM load_staging_by_session
            USING    ls_nav-session_id
            CHANGING lv_reuse_nav_count_14a.
          IF lv_reuse_nav_count_14a <= 0.
            MESSAGE |Certified navigation returned, but Session { ls_nav-session_id } could not be reloaded.| TYPE 'S' DISPLAY LIKE 'E'.
            RETURN.
          ENDIF.
          PERFORM clear_0400_context.
          PERFORM freeze_0400_context USING ls_nav-session_id.
          PERFORM sync_0400_scope.
          PERFORM prepare_alv_0400.
          gv_0400_view      = gc_view_cockpit.
          gv_0400_edit_mode = space.
          CLEAR: gt_z566_edit_scope, gv_z566_edit_groups.
          MESSAGE |Certified AI Navigation opened the CURRENT object { lv_object }.| TYPE 'S'.
         "14D: external navigation may leave the frontend control tree stale.
         "Force next PBO to rebuild the cockpit while keeping exact session pin.
          gv_0400_render_view = gc_view_detail.
          SET SCREEN 0400.
          LEAVE SCREEN.
        ENDIF.
      ENDIF.
    ENDIF.

    "Incomplete/legacy/stale certificate: rediscover from exact current-row
    "SUCCESS evidence instead of blocking or reusing a stale object.
    CLEAR: lv_navstate, lv_target, lv_program, lv_dynpro, lv_action,
           lv_msgid, lv_msgnr, lt_binding, lt_res, lv_contract_ok,
           lv_contract_msg, lv_resolve_ok, lv_resolve_msg,
           lv_object, lv_tuple_txt, lv_ok, lv_message.
  ENDIF.

  CLEAR: lv_target, lv_program, lv_dynpro, lv_action, lt_binding,
         lv_object_type, lv_confidence, lv_reason, lv_ok, lv_message.
  PERFORM discover_navigation_route_ai
    USING    ls_nav
    CHANGING lv_target lv_program lv_dynpro lv_action lt_binding
             lv_object_type lv_confidence lv_reason lv_ok lv_message.
  IF lv_ok <> abap_true.
    MESSAGE lv_message TYPE 'S' DISPLAY LIKE 'W'.
    RETURN.
  ENDIF.

  "Build a display label only from exact SAP MSGV values; never parse prose.
  CLEAR: lv_object, lv_tuple_txt.
  LOOP AT lt_binding INTO ls_binding.
    IF lv_object IS INITIAL.
      lv_object = ls_binding-value.
      lv_tuple_txt = |MSGV{ ls_binding-msgv_idx }={ ls_binding-value } -> { ls_binding-field_name }|.
    ELSE.
      lv_object = |{ lv_object }/{ ls_binding-value }|.
      lv_tuple_txt = |{ lv_tuple_txt }; MSGV{ ls_binding-msgv_idx }={ ls_binding-value } -> { ls_binding-field_name }|.
    ENDIF.
  ENDLOOP.

  CLEAR: lv_ok, lv_message.
  PERFORM call_nav_target_safe
    USING    lv_target lv_program lv_dynpro lv_action
    CHANGING lt_binding lv_ok lv_message.
  IF lv_ok <> abap_true.
    MESSAGE lv_message TYPE 'S' DISPLAY LIKE 'E'.
    RETURN.
  ENDIF.

  IF lv_object_type IS INITIAL.
    lv_question = |Inspect the SAP landing, Back/Exit to return here, then Certify only if it displayed the exact CURRENT object { lv_object }. Route: { lv_tuple_txt }.|.
  ELSE.
    lv_question = |Inspect the SAP landing, Back/Exit to return here, then Certify only if it displayed the exact CURRENT { lv_object_type } { lv_object }. Route: { lv_tuple_txt }.|.
  ENDIF.

  CALL FUNCTION 'POPUP_TO_CONFIRM'
    EXPORTING
      titlebar              = 'Verify AI Navigation'
      text_question         = lv_question
      text_button_1         = 'Certify'
      text_button_2         = 'Reject'
      default_button        = '2'
      display_cancel_button = space
    IMPORTING
      answer                = lv_answer
    EXCEPTIONS
      OTHERS                = 1.

  IF sy-subrc <> 0 OR lv_answer <> '1'.
    PERFORM set_script_cfg USING ls_nav-script_id 'NAVSTATE' 'AI_REJECTED' CHANGING lv_ok lv_message.
    IF lv_ok = abap_true.
      COMMIT WORK AND WAIT.
    ELSE.
      ROLLBACK WORK.
    ENDIF.

   "14D: Reject must return to the exact current SUCCESS session and a fresh
   "cockpit tree. Never leave 0400 in the frontend state inherited from the
   "temporary SAP landing/navigation roundtrip.
    DATA lv_reject_nav_count_14d TYPE i.
    CLEAR lv_reject_nav_count_14d.
    PERFORM load_staging_by_session
      USING    ls_nav-session_id
      CHANGING lv_reject_nav_count_14d.
    IF lv_reject_nav_count_14d > 0.
      PERFORM clear_0400_context.
      PERFORM freeze_0400_context USING ls_nav-session_id.
      PERFORM sync_0400_scope.
      PERFORM prepare_alv_0400.
      gv_0400_view        = gc_view_cockpit.
      gv_0400_edit_mode   = space.
      gv_0400_render_view = gc_view_detail.
      CLEAR: gt_z566_edit_scope, gv_z566_edit_groups.
      PERFORM build_exec_cockpit.
      PERFORM update_0400_counters.
    ENDIF.

    MESSAGE 'AI navigation candidate rejected. Select the SUCCESS row and run AI Navigation again to rediscover.' TYPE 'S' DISPLAY LIKE 'W'.
    SET SCREEN 0400.
    LEAVE SCREEN.
  ENDIF.

  CLEAR: lv_ok, lv_message.
  PERFORM persist_nav_obj_exec
    USING    ls_exec ls_nav lv_object lt_binding
    CHANGING lv_ok lv_message.
  IF lv_ok <> abap_true.
    ROLLBACK WORK.
    MESSAGE lv_message TYPE 'S' DISPLAY LIKE 'E'.
    RETURN.
  ENDIF.

  IF lv_action = '@PARAM'.
    PERFORM set_script_cfg USING ls_nav-script_id 'NAVMODE' 'PARAM_MEMORY' CHANGING lv_ok lv_message.
  ELSE.
    PERFORM set_script_cfg USING ls_nav-script_id 'NAVMODE' 'SCREEN_BDC' CHANGING lv_ok lv_message.
  ENDIF.
  IF lv_ok <> abap_true. ROLLBACK WORK. MESSAGE lv_message TYPE 'S' DISPLAY LIKE 'E'. RETURN. ENDIF.
  PERFORM set_script_cfg USING ls_nav-script_id 'NAVMSGID' ls_nav-msgid CHANGING lv_ok lv_message.
  IF lv_ok <> abap_true. ROLLBACK WORK. MESSAGE lv_message TYPE 'S' DISPLAY LIKE 'E'. RETURN. ENDIF.
  PERFORM set_script_cfg USING ls_nav-script_id 'NAVMSGNR' ls_nav-msgnr CHANGING lv_ok lv_message.
  IF lv_ok <> abap_true. ROLLBACK WORK. MESSAGE lv_message TYPE 'S' DISPLAY LIKE 'E'. RETURN. ENDIF.
  PERFORM set_script_cfg USING ls_nav-script_id 'NAVTCODE' lv_target CHANGING lv_ok lv_message.
  IF lv_ok <> abap_true. ROLLBACK WORK. MESSAGE lv_message TYPE 'S' DISPLAY LIKE 'E'. RETURN. ENDIF.
  PERFORM set_script_cfg USING ls_nav-script_id 'NAVPROG' lv_program CHANGING lv_ok lv_message.
  IF lv_ok <> abap_true. ROLLBACK WORK. MESSAGE lv_message TYPE 'S' DISPLAY LIKE 'E'. RETURN. ENDIF.
  PERFORM set_script_cfg USING ls_nav-script_id 'NAVDYN' lv_dynpro CHANGING lv_ok lv_message.
  IF lv_ok <> abap_true. ROLLBACK WORK. MESSAGE lv_message TYPE 'S' DISPLAY LIKE 'E'. RETURN. ENDIF.
  PERFORM set_script_cfg USING ls_nav-script_id 'NAVACTION' lv_action CHANGING lv_ok lv_message.
  IF lv_ok <> abap_true. ROLLBACK WORK. MESSAGE lv_message TYPE 'S' DISPLAY LIKE 'E'. RETURN. ENDIF.

  lv_count_txt = lines( lt_binding ).
  CONDENSE lv_count_txt NO-GAPS.
  PERFORM set_script_cfg USING ls_nav-script_id 'NAVCOUNT' lv_count_txt CHANGING lv_ok lv_message.
  IF lv_ok <> abap_true. ROLLBACK WORK. MESSAGE lv_message TYPE 'S' DISPLAY LIKE 'E'. RETURN. ENDIF.

  IF lines( lt_binding ) = 1.
    READ TABLE lt_binding INTO DATA(ls_single_nav) INDEX 1.
    IF sy-subrc = 0.
      PERFORM set_script_cfg USING ls_nav-script_id 'NAVMSGV' ls_single_nav-msgv_idx CHANGING lv_ok lv_message.
      IF lv_ok <> abap_true. ROLLBACK WORK. MESSAGE lv_message TYPE 'S' DISPLAY LIKE 'E'. RETURN. ENDIF.
      IF ls_single_nav-param_id IS NOT INITIAL.
        PERFORM set_script_cfg USING ls_nav-script_id 'NAVPID' ls_single_nav-param_id CHANGING lv_ok lv_message.
        IF lv_ok <> abap_true. ROLLBACK WORK. MESSAGE lv_message TYPE 'S' DISPLAY LIKE 'E'. RETURN. ENDIF.
      ENDIF.
    ENDIF.
  ENDIF.

  LOOP AT lt_binding INTO ls_binding.
    lv_seq_txt = ls_binding-seq.
    CONDENSE lv_seq_txt NO-GAPS.

    CLEAR lv_kind.
    CONCATENATE 'NAVMSGV' lv_seq_txt INTO lv_kind.
    PERFORM set_script_cfg USING ls_nav-script_id lv_kind ls_binding-msgv_idx CHANGING lv_ok lv_message.
    IF lv_ok <> abap_true. ROLLBACK WORK. MESSAGE lv_message TYPE 'S' DISPLAY LIKE 'E'. RETURN. ENDIF.

    CLEAR lv_kind.
    CONCATENATE 'NAVFIELD' lv_seq_txt INTO lv_kind.
    PERFORM set_script_cfg USING ls_nav-script_id lv_kind ls_binding-field_name CHANGING lv_ok lv_message.
    IF lv_ok <> abap_true. ROLLBACK WORK. MESSAGE lv_message TYPE 'S' DISPLAY LIKE 'E'. RETURN. ENDIF.

    IF ls_binding-param_id IS NOT INITIAL.
      CLEAR lv_kind.
      CONCATENATE 'NAVPID' lv_seq_txt INTO lv_kind.
      PERFORM set_script_cfg USING ls_nav-script_id lv_kind ls_binding-param_id CHANGING lv_ok lv_message.
      IF lv_ok <> abap_true. ROLLBACK WORK. MESSAGE lv_message TYPE 'S' DISPLAY LIKE 'E'. RETURN. ENDIF.
    ENDIF.
  ENDLOOP.

  "Persist a canonical compact source certificate and verify the DB read-back
  "before NAVSTATE can become CERTIFIED. This prevents the UI from saying
  "CERTIFIED when the exact MSGV-source evidence was not actually readable.
  CLEAR: lv_ok, lv_message.
  PERFORM save_nav_sources
    USING    ls_nav-script_id lt_binding
    CHANGING lv_ok lv_message.
  IF lv_ok <> abap_true.
    ROLLBACK WORK.
    MESSAGE lv_message TYPE 'S' DISPLAY LIKE 'E'.
    RETURN.
  ENDIF.

  CLEAR: lv_ok, lv_message.
  PERFORM verify_nav_sources
    USING    ls_nav-script_id lt_binding
    CHANGING lv_ok lv_message.
  IF lv_ok <> abap_true.
    ROLLBACK WORK.
    MESSAGE lv_message TYPE 'S' DISPLAY LIKE 'E'.
    RETURN.
  ENDIF.

  IF lv_action = '@PARAM'.
    PERFORM set_script_cfg USING ls_nav-script_id 'NAVSOURCE' 'AI_PARAM_MEMORY_VERIFIED' CHANGING lv_ok lv_message.
  ELSE.
    PERFORM set_script_cfg USING ls_nav-script_id 'NAVSOURCE' 'AI_SCREEN_METADATA_VERIFIED' CHANGING lv_ok lv_message.
  ENDIF.
  IF lv_ok <> abap_true. ROLLBACK WORK. MESSAGE lv_message TYPE 'S' DISPLAY LIKE 'E'. RETURN. ENDIF.
  IF lv_object_type IS NOT INITIAL.
    PERFORM set_script_cfg USING ls_nav-script_id 'NAVOBJECT' lv_object_type CHANGING lv_ok lv_message.
    IF lv_ok <> abap_true. ROLLBACK WORK. MESSAGE lv_message TYPE 'S' DISPLAY LIKE 'E'. RETURN. ENDIF.
  ENDIF.
  IF lv_confidence IS NOT INITIAL.
    PERFORM set_script_cfg USING ls_nav-script_id 'NAVCONF' lv_confidence CHANGING lv_ok lv_message.
    IF lv_ok <> abap_true. ROLLBACK WORK. MESSAGE lv_message TYPE 'S' DISPLAY LIKE 'E'. RETURN. ENDIF.
  ENDIF.
  PERFORM set_script_cfg USING ls_nav-script_id 'NAVSTATE' 'CERTIFIED' CHANGING lv_ok lv_message.
  IF lv_ok <> abap_true. ROLLBACK WORK. MESSAGE lv_message TYPE 'S' DISPLAY LIKE 'E'. RETURN. ENDIF.

  COMMIT WORK AND WAIT.

  "Certification is bound to the exact selected SUCCESS session. Reload that
  "session from DB before repainting so a CALL TRANSACTION target or an older
  "0400 screen frame can never repaint the previous TCODE/session after the
  "user returns from live verification.
  DATA lv_post_cert_count_934 TYPE i.
  CLEAR lv_post_cert_count_934.
  PERFORM load_staging_by_session
    USING    ls_nav-session_id
    CHANGING lv_post_cert_count_934.
  IF lv_post_cert_count_934 <= 0.
    MESSAGE |AI route was certified, but Session { ls_nav-session_id } could not be reloaded for projection.| TYPE 'S' DISPLAY LIKE 'E'.
    RETURN.
  ENDIF.
  "The selected SUCCESS session becomes the only canonical 0400 context
  "after certification. PBO, not this PAI/form, owns the frontend redraw.
  PERFORM clear_0400_context.
  PERFORM freeze_0400_context USING ls_nav-session_id.
  PERFORM sync_0400_scope.
  PERFORM prepare_alv_0400.
  gv_0400_view      = gc_view_cockpit.
  gv_0400_edit_mode = space.
  CLEAR: gt_z566_edit_scope, gv_z566_edit_groups.
  PERFORM build_exec_cockpit.
  PERFORM update_0400_counters.

  READ TABLE gt_exec_disp INTO DATA(ls_nav_proj_new)
    WITH KEY session_id = ls_exec-session_id group_key = ls_exec-group_key.
  IF sy-subrc = 0 AND ls_nav_proj_new-sap_object_text IS NOT INITIAL
     AND ls_nav_proj_new-review_state = 'CERTIFIED'.
    MESSAGE |AI route CERTIFIED. Current Document { ls_nav_proj_new-sap_object_text } is clickable.| TYPE 'S'.
  ELSE.
    IF sy-subrc = 0.
      MESSAGE |AI route was certified, but Document projection state is { ls_nav_proj_new-review_state }.| TYPE 'S' DISPLAY LIKE 'E'.
    ELSE.
      MESSAGE 'AI route was certified, but the current cockpit row could not be rebuilt.' TYPE 'S' DISPLAY LIKE 'E'.
    ENDIF.
  ENDIF.

 "Force a clean 0400 PBO after CALL TRANSACTION / certification. This
 "recreates the cockpit from the frozen exact Session ID. The opposite
 "render marker guarantees FREE_0400_GRID executes even when logical view
 "was COCKPIT before and after navigation.
  gv_0400_render_view = gc_view_detail.
  SET SCREEN 0400.
  LEAVE SCREEN.
ENDFORM.

*&---------------------------------------------------------------------*
*& Project a certified document/navigation contract into Screen 0400.
*& Object identity comes only from persisted execution evidence.
*&---------------------------------------------------------------------*
FORM fill_exec_navigation
  USING    pt_res  TYPE STANDARD TABLE
  CHANGING cs_exec TYPE ty_exec_disp.

  DATA: lt_res          TYPE ty_t_result,
        ls_res          TYPE zbdc_result_bup,
        lv_group        TYPE string,
        lv_row_key      TYPE char40,
        lv_object       TYPE zbdc_result_bup-sap_object_id,
        ls_session      TYPE zbdc_session_bup,
        lv_navstate     TYPE zbdc_config_bup-config_value,
        lv_msgid        TYPE symsgid,
        lv_msgnr        TYPE symsgno,
        lv_nav_tcode    TYPE sy-tcode,
        lv_program      TYPE d020s-prog,
        lv_dynpro       TYPE d020s-dnum,
        lv_action       TYPE syucomm,
        lt_binding      TYPE ty_t_nav_binding,
        ls_binding      TYPE ty_nav_binding,
        lv_need_recover TYPE abap_bool,
        lv_contract_ok  TYPE abap_bool,
        lv_contract_msg TYPE string,
        lv_tstc         TYPE tstc-tcode,
        ls_style        TYPE lvc_s_styl.

  CLEAR: cs_exec-sap_object_id, cs_exec-sap_object_text,
         cs_exec-drill_tcode, cs_exec-review_state.
  REFRESH cs_exec-cell_styles.

  IF cs_exec-run_status <> gc_st_success.
    RETURN.
  ENDIF.

  "V17.9.3.4 projection stability: Document identity is persisted execution
  "evidence. Do not recompute it from duplicate protocol rows on every PBO.
  "The route itself is still accepted only from the exact CERTIFIED contract.
  lt_res = pt_res.
  SORT lt_res BY created_at DESCENDING step DESCENDING.

  LOOP AT lt_res INTO ls_res.
    IF ls_res-session_id <> cs_exec-session_id OR
       ls_res-sap_object_id IS INITIAL.
      CONTINUE.
    ENDIF.

    IF ls_res-record_key IS NOT INITIAL.
      lv_group = ls_res-record_key.
    ELSE.
      CLEAR lv_row_key.
      WRITE ls_res-row_index TO lv_row_key LEFT-JUSTIFIED.
      CONDENSE lv_row_key NO-GAPS.
      lv_group = lv_row_key.
    ENDIF.
    IF lv_group <> cs_exec-group_key.
      CONTINUE.
    ENDIF.

    IF lv_object IS INITIAL.
      lv_object = ls_res-sap_object_id.
    ELSEIF lv_object <> ls_res-sap_object_id.
      cs_exec-review_state = 'AMBIGUOUS'.
      RETURN.
    ENDIF.
  ENDLOOP.

  IF lv_object IS INITIAL.
    cs_exec-review_state = 'NO_OBJECT'.
    RETURN.
  ENDIF.

  cs_exec-sap_object_id   = lv_object.
  cs_exec-sap_object_text = lv_object.
  cs_exec-review_state    = 'NO_ROUTE'.

  SELECT SINGLE * FROM zbdc_session_bup
    INTO @ls_session
    WHERE session_id = @cs_exec-session_id.
  IF sy-subrc <> 0 OR ls_session-script_id IS INITIAL.
    RETURN.
  ENDIF.

  CLEAR: lv_contract_ok, lv_contract_msg, lv_navstate, lv_nav_tcode,
         lv_program, lv_dynpro, lv_action, lv_msgid, lv_msgnr, lt_binding.
  PERFORM load_nav_binding_contract
    USING    ls_session-script_id
    CHANGING lv_navstate lv_nav_tcode lv_program lv_dynpro lv_action
             lv_msgid lv_msgnr lt_binding lv_contract_ok lv_contract_msg.
  IF lv_contract_ok <> abap_true.
    cs_exec-review_state = 'NOT_CERTIFIED'.
    RETURN.
  ENDIF.

  "If an older certificate lost only the serialized MSGV source index, use
  "the exact result row already tagged during visible Certify to rebuild the
  "ordered source tuple. No text parsing or business rule is involved.
  CLEAR lv_need_recover.
  LOOP AT lt_binding INTO ls_binding.
    IF ls_binding-msgv_idx CN '1234' OR
       strlen( ls_binding-msgv_idx ) <> 1.
      lv_need_recover = abap_true.
      EXIT.
    ENDIF.
  ENDLOOP.
  IF lv_need_recover = abap_true.
    CLEAR: lv_contract_ok, lv_contract_msg.
    PERFORM recover_nav_sources
      USING    cs_exec lt_res lv_msgid lv_msgnr lv_object
      CHANGING lt_binding lv_contract_ok lv_contract_msg.
    IF lv_contract_ok <> abap_true.
      cs_exec-review_state = 'BINDING_UNPROVEN'.
      RETURN.
    ENDIF.
  ENDIF.

  SELECT SINGLE tcode FROM tstc
    INTO @lv_tstc
    WHERE tcode = @lv_nav_tcode.
  IF sy-subrc <> 0.
    cs_exec-review_state = 'INVALID_TARGET'.
    RETURN.
  ENDIF.

  "A successful Certify already proved the live landing and persisted the
  "object on its exact result evidence. Projection must not downgrade that
  "proof merely because another same-message protocol row also exists.
  cs_exec-drill_tcode  = lv_nav_tcode.
  cs_exec-review_state = 'CERTIFIED'.
  cs_exec-action_hint  = 'Click Document to open the certified SAP display route'.

  CLEAR ls_style.
  ls_style-fieldname = 'SAP_OBJECT_TEXT'.
  ls_style-style     = cl_gui_alv_grid=>mc_style_hotspot.
  APPEND ls_style TO cs_exec-cell_styles.
ENDFORM.

*&---------------------------------------------------------------------*
*& Open the certified standard-SAP route for one cockpit row.
*&---------------------------------------------------------------------*
FORM open_exec_navigation
  USING iv_index TYPE i.

  DATA: ls_exec          TYPE ty_exec_disp,
        ls_session       TYPE zbdc_session_bup,
        lt_res           TYPE ty_t_result,
        ls_res           TYPE zbdc_result_bup,
        lv_navstate      TYPE zbdc_config_bup-config_value,
        lv_target        TYPE sy-tcode,
        lv_program       TYPE d020s-prog,
        lv_dynpro        TYPE d020s-dnum,
        lv_action        TYPE syucomm,
        lv_msgid         TYPE symsgid,
        lv_msgnr         TYPE symsgno,
        lt_binding       TYPE ty_t_nav_binding,
        ls_binding       TYPE ty_nav_binding,
        lv_contract_ok   TYPE abap_bool,
        lv_contract_msg  TYPE string,
        lv_resolve_ok    TYPE abap_bool,
        lv_resolve_msg   TYPE string,
        lv_object        TYPE zbdc_result_bup-sap_object_id,
        lv_tuple_txt     TYPE string,
        lv_group         TYPE string,
        lv_row_key       TYPE char40,
        lv_row_msgid     TYPE symsgid,
        lv_row_msgnr     TYPE symsgno,
        lv_v1            TYPE string,
        lv_v2            TYPE string,
        lv_v3            TYPE string,
        lv_v4            TYPE string,
        lv_value         TYPE string,
        lv_tagged_ok     TYPE abap_bool,
        lv_need_recover  TYPE abap_bool,
        lv_recovered     TYPE abap_bool.

  READ TABLE gt_exec_disp INTO ls_exec INDEX iv_index.
  IF sy-subrc <> 0.
    RETURN.
  ENDIF.

  "Do not trust a stale UI review-state flag. Re-read the exact persisted
  "session + CERTIFIED route below. This makes a Document click deterministic
  "after PBO/refresh while still failing closed on DB/contract mismatch.
  IF ls_exec-run_status <> gc_st_success OR
     ls_exec-sap_object_id IS INITIAL.
    MESSAGE 'No persisted SAP document exists for this SUCCESS row.' TYPE 'S' DISPLAY LIKE 'W'.
    RETURN.
  ENDIF.

  SELECT SINGLE * FROM zbdc_session_bup
    INTO @ls_session
    WHERE session_id = @ls_exec-session_id.
  IF sy-subrc <> 0 OR ls_session-script_id IS INITIAL.
    MESSAGE 'The exact frozen session context is unavailable; navigation was blocked.' TYPE 'S' DISPLAY LIKE 'E'.
    RETURN.
  ENDIF.

  CLEAR: lv_contract_ok, lv_contract_msg, lv_navstate, lv_target,
         lv_program, lv_dynpro, lv_action, lv_msgid, lv_msgnr, lt_binding.
  PERFORM load_nav_binding_contract
    USING    ls_session-script_id
    CHANGING lv_navstate lv_target lv_program lv_dynpro lv_action
             lv_msgid lv_msgnr lt_binding lv_contract_ok lv_contract_msg.
  IF lv_contract_ok <> abap_true.
    MESSAGE lv_contract_msg TYPE 'S' DISPLAY LIKE 'E'.
    RETURN.
  ENDIF.

  SELECT * FROM zbdc_result_bup
    INTO TABLE @lt_res
    WHERE session_id = @ls_exec-session_id.
  SORT lt_res BY created_at DESCENDING step DESCENDING.

  "General source recovery for legacy/corrupt serialized certificates. The
  "tagged SAP SUCCESS row plus persisted SAP_OBJECT_ID must prove one unique
  "ordered MSGV tuple before any target is called.
  CLEAR: lv_need_recover, lv_recovered.
  LOOP AT lt_binding INTO ls_binding.
    IF ls_binding-msgv_idx CN '1234' OR
       strlen( ls_binding-msgv_idx ) <> 1.
      lv_need_recover = abap_true.
      EXIT.
    ENDIF.
  ENDLOOP.
  IF lv_need_recover = abap_true.
    CLEAR: lv_contract_ok, lv_contract_msg.
    PERFORM recover_nav_sources
      USING    ls_exec lt_res lv_msgid lv_msgnr ls_exec-sap_object_id
      CHANGING lt_binding lv_contract_ok lv_contract_msg.
    IF lv_contract_ok <> abap_true.
      MESSAGE lv_contract_msg TYPE 'S' DISPLAY LIKE 'E'.
      RETURN.
    ENDIF.
    lv_recovered = abap_true.
  ENDIF.

  IF lv_action = '@PARAM' AND lines( lt_binding ) = 1.
    READ TABLE lt_binding INTO ls_binding INDEX 1.
    IF sy-subrc = 0 AND
       ( ls_binding-msgv_idx CN '1234' OR
         strlen( ls_binding-msgv_idx ) <> 1 ).
      CLEAR: lv_contract_ok, lv_contract_msg.
      PERFORM hydrate_param_msgv
        USING    ls_exec lt_res lv_msgid lv_msgnr ls_exec-sap_object_id
        CHANGING lt_binding lv_contract_ok lv_contract_msg.
      IF lv_contract_ok <> abap_true.
        MESSAGE lv_contract_msg TYPE 'S' DISPLAY LIKE 'E'.
        RETURN.
      ENDIF.
    ENDIF.
  ENDIF.

  CLEAR: lv_resolve_ok, lv_resolve_msg, lv_object, lv_tuple_txt.
  PERFORM resolve_nav_bindings_for_exec
    USING    ls_exec lt_res lv_msgid lv_msgnr ls_exec-sap_object_id
    CHANGING lt_binding lv_object lv_tuple_txt lv_resolve_ok lv_resolve_msg.

  "Single-key certified routes have a stronger persisted fallback: the exact
  "result row tagged during Certify. This is not text parsing and does not
  "guess a TCODE/PID. It only rehydrates the one certified binding when the
  "tagged SAP message row proves the same MSGID/MSGNR/MSGV value.
  IF lv_resolve_ok <> abap_true AND lines( lt_binding ) = 1.
    READ TABLE lt_binding INTO ls_binding INDEX 1.
    IF sy-subrc = 0.
      LOOP AT lt_res INTO ls_res.
        IF ls_res-session_id <> ls_exec-session_id OR
           ls_res-msg_type <> 'S' OR
           ls_res-sap_object_id <> ls_exec-sap_object_id.
          CONTINUE.
        ENDIF.

        IF ls_res-record_key IS NOT INITIAL.
          lv_group = ls_res-record_key.
        ELSE.
          CLEAR lv_row_key.
          WRITE ls_res-row_index TO lv_row_key LEFT-JUSTIFIED.
          CONDENSE lv_row_key NO-GAPS.
          lv_group = lv_row_key.
        ENDIF.
        IF lv_group <> ls_exec-group_key.
          CONTINUE.
        ENDIF.

        CLEAR: lv_row_msgid, lv_row_msgnr, lv_v1, lv_v2, lv_v3, lv_v4.
        PERFORM read_result_message_parts
          USING    ls_res
          CHANGING lv_row_msgid lv_row_msgnr lv_v1 lv_v2 lv_v3 lv_v4.
        IF lv_row_msgid <> lv_msgid OR lv_row_msgnr <> lv_msgnr.
          CONTINUE.
        ENDIF.

        CLEAR lv_value.
        CASE ls_binding-msgv_idx.
          WHEN '1'. lv_value = lv_v1.
          WHEN '2'. lv_value = lv_v2.
          WHEN '3'. lv_value = lv_v3.
          WHEN '4'. lv_value = lv_v4.
        ENDCASE.
        CONDENSE lv_value.
        IF lv_value <> ls_exec-sap_object_id.
          CONTINUE.
        ENDIF.

        ls_binding-value = lv_value.
        MODIFY lt_binding FROM ls_binding INDEX 1.
        lv_object = ls_exec-sap_object_id.
        lv_tuple_txt = |MSGV{ ls_binding-msgv_idx }={ lv_value }|.
        lv_resolve_ok = abap_true.
        lv_tagged_ok = abap_true.
        EXIT.
      ENDLOOP.
    ENDIF.
  ENDIF.

  IF lv_resolve_ok <> abap_true.
    IF lv_resolve_msg IS INITIAL.
      lv_resolve_msg = 'Certified route exists, but the exact persisted object binding could not be rebuilt.' .
    ENDIF.
    MESSAGE lv_resolve_msg TYPE 'S' DISPLAY LIKE 'E'.
    RETURN.
  ENDIF.

  CLEAR: lv_contract_ok, lv_contract_msg.
  PERFORM call_nav_target_safe
    USING    lv_target lv_program lv_dynpro lv_action
    CHANGING lt_binding lv_contract_ok lv_contract_msg.
  IF lv_contract_ok <> abap_true.
    MESSAGE lv_contract_msg TYPE 'S' DISPLAY LIKE 'E'.
    RETURN.
  ENDIF.

  "Self-heal only after the real certified target consumed the recovered
  "current-row bindings successfully. The canonical NAVSRCn rows are then
  "read back before commit, so future rows no longer depend on recovery.
  IF lv_recovered = abap_true.
    CLEAR: lv_contract_ok, lv_contract_msg.
    PERFORM save_nav_sources
      USING    ls_session-script_id lt_binding
      CHANGING lv_contract_ok lv_contract_msg.
    IF lv_contract_ok <> abap_true.
      ROLLBACK WORK.
      MESSAGE lv_contract_msg TYPE 'S' DISPLAY LIKE 'E'.
      RETURN.
    ENDIF.
    CLEAR: lv_contract_ok, lv_contract_msg.
    PERFORM verify_nav_sources
      USING    ls_session-script_id lt_binding
      CHANGING lv_contract_ok lv_contract_msg.
    IF lv_contract_ok <> abap_true.
      ROLLBACK WORK.
      MESSAGE lv_contract_msg TYPE 'S' DISPLAY LIKE 'E'.
      RETURN.
    ENDIF.
    COMMIT WORK AND WAIT.
  ENDIF.
ENDFORM.

*& Prefer exact runtime error proof over stale staging hints

FORM fill_exec_err_result
  USING    pt_res TYPE STANDARD TABLE
  CHANGING cs_exec TYPE ty_exec_disp.
  FIELD-SYMBOLS: <ls_res> TYPE any,
                 <fv>     TYPE any.

  DATA: lt_res_local     TYPE STANDARD TABLE OF zbdc_result_bup,
        lv_sid           TYPE string,
        lv_res_batch     TYPE string,
        lv_exec_batch    TYPE string,
        lv_tcode         TYPE string,
        lv_rkey          TYPE string,
        lv_row_index     TYPE string,
        lv_row_norm      TYPE string,
        lv_tkey          TYPE string,
        lv_tkey_suffix   TYPE string,
        lt_key_parts     TYPE STANDARD TABLE OF string,
        lv_part          TYPE string,
        lv_key_lines     TYPE i,
        lv_exec_status   TYPE string,
        lv_msg_type      TYPE string,
        lv_msg           TYPE string,
        lv_msg_upper     TYPE string,
        lv_best_msg      TYPE string,
        lv_exact_match   TYPE abap_bool,
        lv_key_match     TYPE abap_bool,
        lv_batch_like    TYPE string.

  lt_res_local = pt_res.
  SORT lt_res_local BY created_at DESCENDING step DESCENDING.

  lv_tkey = cs_exec-group_key.
  lv_tkey_suffix = lv_tkey.
  SPLIT lv_tkey AT '-' INTO TABLE lt_key_parts.
  lv_key_lines = lines( lt_key_parts ).
  IF lv_key_lines > 0.
    READ TABLE lt_key_parts INTO lv_part INDEX lv_key_lines.
    IF sy-subrc = 0 AND lv_part IS NOT INITIAL.
      lv_tkey_suffix = lv_part.
    ENDIF.
  ENDIF.
  SHIFT lv_tkey_suffix LEFT DELETING LEADING '0'.
  IF lv_tkey_suffix IS INITIAL.
    lv_tkey_suffix = '0'.
  ENDIF.

  lv_exec_batch = cs_exec-batch_key.
  IF lv_exec_batch IS INITIAL.
    PERFORM batch_prefix_from_sid USING cs_exec-session_id CHANGING lv_exec_batch.
  ENDIF.
  lv_batch_like = lv_exec_batch && '*'.

  LOOP AT lt_res_local ASSIGNING <ls_res>.
    CLEAR: lv_sid, lv_res_batch, lv_tcode, lv_rkey, lv_row_index,
           lv_row_norm, lv_exec_status, lv_msg_type, lv_msg, lv_msg_upper,
           lv_exact_match, lv_key_match.

    ASSIGN COMPONENT 'SESSION_ID' OF STRUCTURE <ls_res> TO <fv>.
    IF sy-subrc = 0. lv_sid = <fv>. ENDIF.

    PERFORM batch_prefix_from_sid USING lv_sid CHANGING lv_res_batch.
    IF lv_sid <> cs_exec-session_id AND
       lv_res_batch <> lv_exec_batch AND
       lv_sid NP lv_batch_like.
      CONTINUE.
    ENDIF.

    ASSIGN COMPONENT 'TCODE' OF STRUCTURE <ls_res> TO <fv>.
    IF sy-subrc = 0. lv_tcode = <fv>. ENDIF.
    IF lv_tcode IS NOT INITIAL AND lv_tcode <> cs_exec-tcode.
      CONTINUE.
    ENDIF.

    ASSIGN COMPONENT 'RECORD_KEY' OF STRUCTURE <ls_res> TO <fv>.
    IF sy-subrc = 0. lv_rkey = <fv>. ENDIF.
    ASSIGN COMPONENT 'ROW_INDEX' OF STRUCTURE <ls_res> TO <fv>.
    IF sy-subrc = 0. lv_row_index = <fv>. ENDIF.

    IF lv_rkey IS NOT INITIAL AND lv_rkey = lv_tkey.
      lv_key_match = abap_true.
      lv_exact_match = abap_true.
    ENDIF.

    IF lv_key_match <> abap_true AND lv_row_index IS NOT INITIAL.
      lv_row_norm = lv_row_index.
      CONDENSE lv_row_norm NO-GAPS.
      SHIFT lv_row_norm LEFT DELETING LEADING '0'.
      IF lv_row_norm IS INITIAL.
        lv_row_norm = '0'.
      ENDIF.
      IF lv_row_norm = lv_tkey_suffix OR lv_row_norm = lv_tkey.
        lv_key_match = abap_true.
      ENDIF.
    ENDIF.

    IF lv_key_match <> abap_true.
      CONTINUE.
    ENDIF.

    ASSIGN COMPONENT 'EXEC_STATUS' OF STRUCTURE <ls_res> TO <fv>.
    IF sy-subrc = 0. lv_exec_status = <fv>. ENDIF.
    ASSIGN COMPONENT 'MSG_TYPE' OF STRUCTURE <ls_res> TO <fv>.
    IF sy-subrc = 0. lv_msg_type = <fv>. ENDIF.
    ASSIGN COMPONENT 'MESSAGE' OF STRUCTURE <ls_res> TO <fv>.
    IF sy-subrc = 0. lv_msg = <fv>. ENDIF.
    IF lv_msg IS INITIAL.
      CONTINUE.
    ENDIF.

    lv_msg_upper = lv_msg.
    TRANSLATE lv_msg_upper TO UPPER CASE.

    IF lv_exec_status = gc_st_error OR
       lv_exec_status = 'ERROR' OR
       lv_msg_type = 'E' OR
       lv_msg_upper CS 'NO BATCH INPUT DATA FOUND FOR DYNPRO' OR
       lv_msg_upper CS 'DOES NOT EXIST IN DYNPRO' OR
       lv_msg_upper CS 'TRANSACTION ENDED' OR
       lv_msg_upper CS 'BDC EXECUTION FAILED'.
      IF lv_best_msg IS INITIAL OR lv_exact_match = abap_true.
        lv_best_msg = lv_msg.
      ENDIF.
      IF lv_msg_upper CS 'NO BATCH INPUT DATA FOUND FOR DYNPRO' OR
         lv_msg_upper CS 'DOES NOT EXIST IN DYNPRO' OR
         lv_msg_upper CS 'TRANSACTION ENDED' OR
         lv_msg_upper CS 'BDC EXECUTION FAILED'.
        cs_exec-message = lv_msg.
        EXIT.
      ENDIF.
    ENDIF.
  ENDLOOP.

  IF lv_best_msg IS NOT INITIAL AND cs_exec-message <> lv_best_msg.
    cs_exec-message = lv_best_msg.
  ENDIF.
ENDFORM.

*& Final generic display scrub for terminal business states

FORM scrub_exec_terminal CHANGING cs_exec TYPE ty_exec_disp.
  DATA: lv_msg_upper    TYPE string,
        lv_obj_upper    TYPE string,
        lv_health_upper TYPE string,
        lv_fatal        TYPE abap_bool,
        lv_stale_hint   TYPE abap_bool.

  CLEAR: lv_fatal, lv_stale_hint.
  lv_msg_upper = cs_exec-message.
  TRANSLATE lv_msg_upper TO UPPER CASE.
  CONDENSE lv_msg_upper.
  SHIFT lv_msg_upper LEFT DELETING LEADING space.
  lv_obj_upper = cs_exec-sap_object_id.
  TRANSLATE lv_obj_upper TO UPPER CASE.
  CONDENSE lv_obj_upper.
  lv_health_upper = cs_exec-health_text.
  TRANSLATE lv_health_upper TO UPPER CASE.
  CONDENSE lv_health_upper.

  IF lv_obj_upper CP 'SAP*' OR
     lv_obj_upper CP 'RSBDC*' OR
     lv_obj_upper CS 'DYNPRO' OR
     lv_obj_upper CS 'BDC'.
    CLEAR cs_exec-sap_object_id.
  ENDIF.

  IF cs_exec-run_status = gc_st_error AND
     ( lv_msg_upper CS 'SM35 SESSION NOT CREATED' OR
       lv_msg_upper CS 'SM35 SESSION WAS NOT CREATED' OR
       lv_msg_upper CS 'NO SM35 SESSION WAS CREATED' OR
       lv_msg_upper CS 'NO SELECTED READY GROUP CHANGED STATE' OR
       lv_msg_upper CS 'NO CURRENT READY GROUP REMAINS' OR
       lv_health_upper CS 'SM35 SESSION NOT CREATED' ).
    cs_exec-icon        = '@0A@'.
    cs_exec-msg_type    = 'E'.
    cs_exec-health_text = 'SM35 session not created'.
    cs_exec-action_hint = 'Check profile/setup/scope; use CT certification first'.
    IF cs_exec-message IS INITIAL OR lv_msg_upper CS 'BDC EXECUTION FAILED'.
      CONCATENATE
        'SM35 session not created;'
        'this is a queue setup/preflight issue,'
        'not SAP business rejection.'
        INTO cs_exec-message SEPARATED BY space.
    ENDIF.
    CLEAR cs_exec-sap_object_id.
    RETURN.
  ENDIF.

 "this exact phrase is produced by Z208 staging validation. It is
 "not a SAP BDC protocol and must not be promoted to BDC execution failed.
  IF cs_exec-run_status = gc_st_error AND
     lv_msg_upper CS 'MISSING MANDATORY FIELD'.
    cs_exec-icon        = '@0A@'.
    cs_exec-msg_type    = 'E'.
    cs_exec-health_text = 'Staging validation failed'.
    cs_exec-action_hint = 'Correct source/required contract; validate again'.
    CLEAR cs_exec-sap_object_id.
    RETURN.
  ENDIF.

  IF lv_msg_upper CS 'NO BATCH INPUT DATA FOUND FOR DYNPRO' OR
     lv_msg_upper CS 'DOES NOT EXIST IN DYNPRO' OR
     lv_msg_upper CS 'BDC EXECUTION FAILED' OR
     lv_msg_upper CS 'TRANSACTION ENDED'.
    lv_fatal = abap_true.
  ENDIF.

  IF cs_exec-run_status = gc_st_error AND
     ( lv_msg_upper CS 'PROFILE SETUP INCOMPLETE' OR
       lv_msg_upper CS 'PROFILE SETUP' OR
       lv_msg_upper CS 'PROFILE IS NOT CERTIFIED' OR
       lv_msg_upper CS 'PROFILE IS MAPPED' OR
       lv_msg_upper CS 'PROFILE IS DRAFT' OR
       lv_msg_upper CS 'EXECUTION IS BLOCKED' OR
       lv_msg_upper CS 'FROZEN CERTIFIED SESSION CONTRACT' OR
       lv_msg_upper CS 'FROZEN SESSION CONTRACT' OR
       lv_msg_upper CS 'CURRENT PROFILE CONTRACT' OR
       lv_msg_upper CS 'CERTIFICATION RECORD' OR
       lv_msg_upper CS 'MATCHING CERTIFIED' OR
       lv_msg_upper CS 'MATCHING PENDING_TEST' OR
       lv_msg_upper CS 'IMMUTABLE SCRIPT HEADER' OR
       lv_msg_upper CS 'CONTRACT HASH' OR
       lv_msg_upper CS 'RUNTIME CERTIFICATE' OR
       lv_msg_upper CS 'OBJECT PROOF CONFIG' OR
       lv_msg_upper CS 'TRACE_TABLE' OR
       lv_msg_upper CS 'TRACE_FIELD' OR
       lv_msg_upper CS 'OBJECT_FIELD' OR
       lv_msg_upper CS 'HIDDEN OBJECT CORRELATION' ).
    cs_exec-icon        = '@0A@'.
    cs_exec-msg_type    = 'E'.
    cs_exec-health_text = 'Profile setup incomplete'.
    cs_exec-action_hint = 'Complete profile setup; no data retry'.
    CLEAR cs_exec-sap_object_id.
    RETURN.
  ENDIF.

  IF lv_fatal = abap_true AND cs_exec-run_status <> gc_st_success.
    cs_exec-icon        = '@0A@'.
    cs_exec-msg_type    = 'E'.
    cs_exec-run_status  = gc_st_error.
    IF cs_exec-sap_object_id IS NOT INITIAL.
 "z121 only restores an ERROR object from an exact DB_PROOF row
 "that passes the frozen verifier. A later BDC error must not erase it.
      cs_exec-health_text = 'Failed after SAP Object persisted'.
      cs_exec-action_hint = 'Double-click SAP Object; do not retry'.
    ELSE.
      cs_exec-health_text = 'BDC execution failed'.
      cs_exec-action_hint = 'Open Error Detail or Fix Guide'.
    ENDIF.
    RETURN.
  ENDIF.

  IF lv_msg_upper CP 'ENTER*' OR
     lv_msg_upper CP 'PLEASE*' OR
     lv_msg_upper CS ' PLEASE ' OR
     lv_msg_upper CS ' IS REQUIRED' OR
     lv_msg_upper CS ' REQUIRED FIELD'.
    lv_stale_hint = abap_true.
  ENDIF.

  IF cs_exec-run_status = gc_st_error.
    IF lv_msg_upper CS 'PROFILE SETUP INCOMPLETE' OR
       lv_msg_upper CS 'PROFILE SETUP' OR
       lv_msg_upper CS 'PROFILE IS NOT CERTIFIED' OR
       lv_msg_upper CS 'PROFILE IS MAPPED' OR
       lv_msg_upper CS 'PROFILE IS DRAFT' OR
       lv_msg_upper CS 'EXECUTION IS BLOCKED' OR
       lv_msg_upper CS 'FROZEN CERTIFIED SESSION CONTRACT' OR
       lv_msg_upper CS 'FROZEN SESSION CONTRACT' OR
       lv_msg_upper CS 'CURRENT PROFILE CONTRACT' OR
       lv_msg_upper CS 'CERTIFICATION RECORD' OR
       lv_msg_upper CS 'MATCHING CERTIFIED' OR
       lv_msg_upper CS 'MATCHING PENDING_TEST' OR
       lv_msg_upper CS 'IMMUTABLE SCRIPT HEADER' OR
       lv_msg_upper CS 'CONTRACT HASH' OR
       lv_msg_upper CS 'HIDDEN OBJECT TRACE PROOF' OR
       lv_msg_upper CS 'OBJECT PROOF CONFIG' OR
       lv_msg_upper CS 'RUNTIME CERTIFICATE' OR
       lv_msg_upper CS 'CERTIFIED PROFILE DID NOT INJECT' OR
       lv_msg_upper CS 'TRACE_TABLE' OR
       lv_msg_upper CS 'TRACE_FIELD' OR
       lv_msg_upper CS 'OBJECT_FIELD' OR
       lv_msg_upper CS 'HIDDEN OBJECT CORRELATION'.
      cs_exec-health_text = 'Profile setup incomplete'.
      cs_exec-action_hint = 'Send Error Detail to support; no retry'.
      CLEAR cs_exec-sap_object_id.
      RETURN.
    ENDIF.

    IF lv_health_upper CS 'BDC' OR lv_health_upper CS 'EXECUTION FAILED'.
      cs_exec-health_text = 'BDC execution failed'.
    ENDIF.

    IF cs_exec-sap_object_id IS NOT INITIAL.
      cs_exec-health_text = 'Failed after SAP Object persisted'.
      cs_exec-action_hint = 'Double-click SAP Object; do not retry'.
    ENDIF.

    IF cs_exec-message IS INITIAL OR lv_stale_hint = abap_true.
      cs_exec-message = 'BDC execution failed. Open Error Detail for the exact SAP runtime protocol.'.
    ENDIF.
  ENDIF.

  IF cs_exec-run_status = gc_st_success.
 "execution truth is independent from optional object identity.
 "A blank SAP_OBJECT_ID after a successful CT/SM35 execution means
 "OBJECT_STATUS=UNRESOLVED; it must never downgrade SUCCESS to PARTIAL.
 "Object proof remains fail-closed: no token is fabricated or resurrected.
    IF cs_exec-sap_object_id IS INITIAL.
      cs_exec-run_status  = gc_st_success.
      cs_exec-icon        = '@08@'.
      cs_exec-msg_type    = 'S'.
      cs_exec-health_text = 'Execution successful'.
      cs_exec-action_hint = 'View execution evidence'.
      IF cs_exec-message IS INITIAL.
        cs_exec-message = 'EXECUTION_STATUS=SUCCESS. SAP execution completed without a terminal execution error.'.
      ENDIF.
    ELSE.
      cs_exec-icon     = '@08@'.
      cs_exec-msg_type = 'S'.
      cs_exec-health_text = 'Execution successful'.
    ENDIF.
  ELSE.
 "object evidence may remain in ZBDC_RESULT_BUP for audit and
 "duplicate prevention, but the cockpit SAP Object column is SUCCESS-only.
    CLEAR: cs_exec-sap_object_id, cs_exec-drill_tcode.
  ENDIF.
ENDFORM.

*& Last visible-row guard against stale validation prompts

FORM final_exec_display_guard CHANGING cs_exec TYPE ty_exec_disp.
  DATA lv_msg_upper TYPE string.
  DATA lv_health_upper TYPE string.

  IF cs_exec-run_status <> gc_st_error.
    IF cs_exec-run_status <> gc_st_success.
      CLEAR: cs_exec-sap_object_id, cs_exec-drill_tcode.
    ENDIF.
    RETURN.
  ENDIF.

 "ERROR may retain DB side-effect proof in ZBDC_RESULT_BUP, but never a
 "clickable cockpit drill route.
  CLEAR cs_exec-drill_tcode.

  lv_msg_upper = cs_exec-message.
  TRANSLATE lv_msg_upper TO UPPER CASE.
  CONDENSE lv_msg_upper.
  SHIFT lv_msg_upper LEFT DELETING LEADING space.

  lv_health_upper = cs_exec-health_text.
  TRANSLATE lv_health_upper TO UPPER CASE.
  CONDENSE lv_health_upper.

  IF lv_msg_upper CS 'SM35 SESSION NOT CREATED' OR
     lv_msg_upper CS 'SM35 SESSION WAS NOT CREATED' OR
     lv_msg_upper CS 'NO SM35 SESSION WAS CREATED' OR
     lv_msg_upper CS 'NO SELECTED READY GROUP CHANGED STATE' OR
     lv_msg_upper CS 'NO CURRENT READY GROUP REMAINS' OR
     lv_health_upper CS 'SM35 SESSION NOT CREATED'.
    cs_exec-health_text = 'SM35 session not created'.
    cs_exec-action_hint = 'Check profile/setup/scope; use CT certification first'.
    IF cs_exec-message IS INITIAL OR lv_msg_upper CS 'BDC EXECUTION FAILED'.
      CONCATENATE
        'SM35 session not created;'
        'this is a queue setup/preflight issue,'
        'not SAP business rejection.'
        INTO cs_exec-message SEPARATED BY space.
    ENDIF.
    CLEAR cs_exec-sap_object_id.
    RETURN.
  ENDIF.

  IF lv_msg_upper CS 'HIDDEN OBJECT TRACE PROOF' OR
     lv_msg_upper CS 'OBJECT PROOF CONFIG' OR
     lv_msg_upper CS 'PROFILE IS NOT CERTIFIED' OR
     lv_msg_upper CS 'RUNTIME CERTIFICATE' OR
     lv_msg_upper CS 'CERTIFIED PROFILE DID NOT INJECT' OR
     lv_msg_upper CS 'TRACE_TABLE' OR
     lv_msg_upper CS 'TRACE_FIELD' OR
     lv_msg_upper CS 'OBJECT_FIELD'.
    cs_exec-health_text = 'Profile setup incomplete'.
    cs_exec-action_hint = 'Send Error Detail to support; no retry'.
    CLEAR cs_exec-sap_object_id.
    RETURN.
  ENDIF.

  IF cs_exec-sap_object_id IS NOT INITIAL.
 "keep DB side-effect evidence persisted, but do not expose the SAP
 "Object hotspot on a non-SUCCESS business row.
    CLEAR cs_exec-sap_object_id.
    cs_exec-health_text = 'Failed after a persisted side effect'.
    cs_exec-action_hint = 'Open Error Detail; do not retry business'.
    RETURN.
  ENDIF.

  IF lv_health_upper CS 'BDC' OR cs_exec-health_text IS INITIAL.
    cs_exec-health_text = 'BDC execution failed'.
  ENDIF.

  CLEAR cs_exec-sap_object_id.

  IF cs_exec-message IS INITIAL OR
     lv_msg_upper CP 'ENTER*' OR
     lv_msg_upper CP 'PLEASE*' OR
     lv_msg_upper CS ' PLEASE ' OR
     lv_msg_upper CS ' IS REQUIRED' OR
     lv_msg_upper CS ' REQUIRED FIELD'.
    cs_exec-message = 'BDC execution failed. Open Error Detail for the exact SAP runtime protocol.'.
  ENDIF.
ENDFORM.

FORM UPDATE_0400_COUNTERS.
  CLEAR: TXTGV_TOT, TXTGV_SUC, TXTGV_ERR, TXTGV_WAR,
         TXTGV_TOTAL, TXTGV_OK, TXTGV_SUC_COUNT, TXTGV_WARNING.

 "TXTP_SESSION_ID is an exact persisted session identity. Once screen 0400
 "has frozen a context, counters are presentation-only and must never elect
 "a different session from the first row of GT_STAGING/GT_EXEC_DISP.
  IF gv_0400_context_locked = abap_true
     AND gv_0400_context_sid IS NOT INITIAL.
    TXTP_SESSION_ID = gv_0400_context_sid.
    TXTP_SESS       = gv_0400_context_sid.
  ELSE.
    CLEAR: TXTP_SESSION_ID, TXTP_SESS.
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

 "Run Selected uses native ALV row selectors.
 "The legacy SELECTED field is kept hidden only for old callers.
 "DESIGN ONLY: simplify the cockpit to one purpose per visible column.
 "Underlying GT_EXEC_DISP fields and executor/state logic are unchanged.
  ADD_COL 'SELECTED'       'Run'               4  90.
  ADD_COL 'ICON'           'Health'            5   1.
  ADD_COL 'GROUP_KEY'      'Business Group'   14  2.
  ADD_COL 'TCODE'          'TCode'              8  3.
  ADD_COL 'ITEM_COUNT'     'Items'              5  4.
  ADD_COL 'RUN_STATUS'       'Status'            10  5.
  ADD_COL 'SAP_OBJECT_TEXT'  'Document'          22  6.
  ADD_COL 'MESSAGE'          'Result / Message'  52  7.
  ADD_COL 'EXECUTION'        'Execution'          24  8.

 "Retained in the data model/export path, hidden only from the main cockpit.
  ADD_COL 'ACTION_HINT'    'Full Action'       80 84.
  ADD_COL 'SOURCE_FILE'    'File / Source'     28 85.
  ADD_COL 'HEALTH_TEXT'   'Health Check'      34 86.
  ADD_COL 'ATTEMPT'       'Retry'              6 87.
  ADD_COL 'SHEET_NAME'    'Sheet'             18 88.

 "Technical/context fields are still in GT_EXEC_DISP for logic/export,
 "but not shown in the 0400 demo cockpit.
  ADD_COL 'BATCH_KEY'     'Batch'            22  89.
  ADD_COL 'SESSION_ID'    'Session ID'       24  90.
  ADD_COL 'DRILL_TCODE'   'Review TCode'     12  91.
  ADD_COL 'SAP_OBJECT_ID'  'Object Anchor'    30  92.
  ADD_COL 'REVIEW_STATE'   'Review State'     16  93.
  ADD_COL 'MSG_TYPE'      'Msg Type'         8   94.
  ADD_COL 'READY_COUNT'   'Ready Rows'       10  95.
  ADD_COL 'SUCCESS_COUNT' 'Success Rows'     12  96.
  ADD_COL 'ERROR_COUNT'   'Error Rows'       10  97.
  ADD_COL 'WARNING_COUNT' 'Warning Rows'     12  98.
  ADD_COL 'SM35_COUNT'    'SM35 Rows'         10  99.

  LOOP AT CT_FCAT ASSIGNING FIELD-SYMBOL(<F>).
    CASE <F>-FIELDNAME.
      WHEN 'SELECTED'.
        <F>-NO_OUT   = 'X'.
        <F>-CHECKBOX = SPACE.
        <F>-EDIT     = SPACE.
        <F>-KEY      = SPACE.
        <F>-TECH     = 'X'.
      WHEN 'ACTION_HINT' OR 'SOURCE_FILE' OR 'HEALTH_TEXT' OR 'ATTEMPT' OR 'SHEET_NAME'
        OR 'BATCH_KEY' OR 'SESSION_ID' OR 'DRILL_TCODE' OR 'SAP_OBJECT_ID'
        OR 'REVIEW_STATE' OR 'MSG_TYPE' OR 'READY_COUNT' OR 'SUCCESS_COUNT'
        OR 'ERROR_COUNT' OR 'WARNING_COUNT' OR 'SM35_COUNT'.
        <F>-NO_OUT = 'X'.
      WHEN 'SAP_OBJECT_TEXT'.
        <F>-OUTPUTLEN = 22.
        <F>-DD_OUTLEN = 22.
        <F>-COL_OPT = SPACE.
        "V17.9.3.4: register the column hotspot at field-catalog level as
        "well as per-cell style. OPEN_EXEC_NAVIGATION still revalidates the
        "exact CERTIFIED route, so non-certified rows remain fail-closed.
        <F>-HOTSPOT = 'X'.
      WHEN 'ICON'.
        <F>-ICON = 'X'.
      WHEN 'GROUP_KEY' OR 'RUN_STATUS'.
        <F>-KEY = 'X'.
      WHEN 'MESSAGE' OR 'EXECUTION' OR 'ACTION_HINT' OR 'HEALTH_TEXT'.
        <F>-LOWERCASE = 'X'.
    ENDCASE.
  ENDLOOP.
ENDFORM.

FORM BUILD_DETAIL_FIELDCAT CHANGING CT_FCAT TYPE LVC_T_FCAT.
  DATA: lt_map_all      TYPE STANDARD TABLE OF zbdc_mapping_bup,
        ls_map_candidate TYPE zbdc_mapping_bup,
        ls_map_match     TYPE zbdc_mapping_bup,
        lt_sources       TYPE string_table,
        lv_tcode         TYPE zbdc_prof_bup-tcode,
        lv_profile       TYPE zbdc_prof_bup-profile_name,
        lv_ver           TYPE zbdc_prof_bup-profile_ver,
        lv_found         TYPE abap_bool,
        lv_schema_ok     TYPE abap_bool,
        lv_schema_msg    TYPE string,
        lv_col_pos       TYPE i,
        lv_source        TYPE string,
        lv_norm_source   TYPE zbdc_mapping_bup-source_column,
        lv_map_source    TYPE zbdc_mapping_bup-source_column,
        lv_match_count   TYPE i,
        lv_label         TYPE string,
        lt_hdr_cache     TYPE STANDARD TABLE OF ty_preview_hdr_cache,
        ls_hdr_cache     TYPE ty_preview_hdr_cache,
        lt_target_seen   TYPE SORTED TABLE OF zbdc_mapping_bup-staging_field
                         WITH UNIQUE KEY table_line,
        lv_ltxt          TYPE scrtext_l,
        lv_mtxt          TYPE scrtext_m,
        lv_stxt          TYPE scrtext_s,
        lv_rep           TYPE reptext.

  CALL FUNCTION 'LVC_FIELDCATALOG_MERGE'
    EXPORTING
      I_STRUCTURE_NAME       = 'ZBDC_STAGING_BUP'
      I_CLIENT_NEVER_DISPLAY = 'X'
    CHANGING
      CT_FIELDCAT            = CT_FCAT
    EXCEPTIONS
      OTHERS                 = 1.

  "Edit Staging must be the exact uploaded business schema, not the physical
  "FIELD01..FIELD25 order. Hide everything first; the frozen session schema
  "below is the only authority allowed to expose/edit columns.
  LOOP AT ct_fcat ASSIGNING FIELD-SYMBOL(<ls_hide>).
    <ls_hide>-no_out = 'X'.
    <ls_hide>-tech   = 'X'.
    <ls_hide>-edit   = space.
    <ls_hide>-key    = space.
  ENDLOOP.

  READ TABLE gt_staging_alv INTO DATA(ls_first_edit) INDEX 1.
  IF sy-subrc <> 0 OR ls_first_edit-session_id IS INITIAL.
    RETURN.
  ENDIF.

  PERFORM resolve_session_context
    USING    ls_first_edit-session_id
    CHANGING lv_tcode lv_profile lv_ver lv_found.
  IF lv_found <> abap_true.
    MESSAGE 'Edit Staging cannot resolve the frozen session contract.'
      TYPE 'S' DISPLAY LIKE 'E'.
    RETURN.
  ENDIF.

  "Use the identical schema authority as Preview Data. For a fresh upload this
  "is the parsed header cache; for history it is the immutable session manifest.
  PERFORM preview_get_source_schema
    USING    ls_first_edit-session_id
    CHANGING lt_sources lv_schema_ok lv_schema_msg.
  IF lv_schema_ok <> abap_true OR lt_sources IS INITIAL.
    IF lv_schema_msg IS INITIAL.
      lv_schema_msg = |EDIT_SCHEMA_UNAVAILABLE: session { ls_first_edit-session_id }.|.
    ENDIF.
    MESSAGE lv_schema_msg TYPE 'S' DISPLAY LIKE 'E'.
    RETURN.
  ENDIF.

  SELECT *
    FROM zbdc_mapping_bup
    INTO TABLE @lt_map_all
    WHERE tcode        = @lv_tcode
      AND profile_name = @lv_profile
      AND profile_ver  = @lv_ver.
  IF lt_map_all IS INITIAL.
    lv_schema_msg = |EDIT_MAPPING_UNAVAILABLE: { lv_tcode }/{ lv_profile } v{ lv_ver }.|.
    MESSAGE lv_schema_msg TYPE 'S' DISPLAY LIKE 'E'.
    RETURN.
  ENDIF.

  "Keep the exact spelling/order of the current uploaded header when it is
  "still in memory. Historical sessions fall back to the frozen manifest text.
  LOOP AT gt_preview_hdr_cache INTO ls_hdr_cache
    WHERE session_id = ls_first_edit-session_id.
    APPEND ls_hdr_cache TO lt_hdr_cache.
  ENDLOOP.
  SORT lt_hdr_cache BY col_no.

  REFRESH lt_target_seen.
  CLEAR lv_col_pos.

  LOOP AT lt_sources INTO lv_source.
    lv_col_pos = sy-tabix.
    CLEAR: lv_norm_source, ls_map_match, lv_match_count.
    PERFORM normalize_mapping_source
      USING    lv_source
      CHANGING lv_norm_source.

    IF lv_norm_source IS INITIAL.
      lv_schema_msg = |EDIT_HEADER_INVALID: column { lv_col_pos } has no source identity.|.
      MESSAGE lv_schema_msg TYPE 'S' DISPLAY LIKE 'E'.
      RETURN.
    ENDIF.

    LOOP AT lt_map_all INTO ls_map_candidate.
      CLEAR lv_map_source.
      PERFORM normalize_mapping_source
        USING    ls_map_candidate-source_column
        CHANGING lv_map_source.
      IF lv_map_source <> lv_norm_source.
        CONTINUE.
      ENDIF.

      IF lv_match_count = 0.
        ls_map_match = ls_map_candidate.
        lv_match_count = 1.
      ELSEIF ls_map_candidate-staging_field = ls_map_match-staging_field
         AND ls_map_candidate-bdc_field     = ls_map_match-bdc_field.
        CONTINUE.
      ELSE.
        lv_match_count = lv_match_count + 1.
      ENDIF.
    ENDLOOP.

    IF lv_match_count = 0.
      lv_schema_msg = |EDIT_MAPPING_SOURCE_MISSING: { lv_norm_source }.|.
      MESSAGE lv_schema_msg TYPE 'S' DISPLAY LIKE 'E'.
      RETURN.
    ELSEIF lv_match_count > 1.
      lv_schema_msg = |EDIT_MAPPING_SOURCE_AMBIGUOUS: { lv_norm_source }.|.
      MESSAGE lv_schema_msg TYPE 'S' DISPLAY LIKE 'E'.
      RETURN.
    ENDIF.

    IF ls_map_match-staging_field IS INITIAL.
      lv_schema_msg = |EDIT_MAPPING_TARGET_MISSING: { lv_norm_source }.|.
      MESSAGE lv_schema_msg TYPE 'S' DISPLAY LIKE 'E'.
      RETURN.
    ENDIF.

    "The existing Edit Staging save/audit contract is FIELD01..FIELD25. Do
    "not expose a technical control column as editable merely because an old
    "Mapping row points there; that would display an edit which Save does not
    "own. New ingests are expected to use the frozen FIELDxx business slots.
    IF ls_map_match-staging_field NP 'FIELD*'.
      lv_schema_msg =
        |EDIT_STAGING_TARGET_UNSUPPORTED: { lv_norm_source } -> { ls_map_match-staging_field }.|.
      MESSAGE lv_schema_msg TYPE 'S' DISPLAY LIKE 'E'.
      RETURN.
    ENDIF.

    "One uploaded header -> one staging slot. A collision would make one field
    "overwrite another, exactly the class of DIVISION/field-loss bug being fixed.
    READ TABLE lt_target_seen
      WITH TABLE KEY table_line = ls_map_match-staging_field
      TRANSPORTING NO FIELDS.
    IF sy-subrc = 0.
      lv_schema_msg =
        |EDIT_MAPPING_TARGET_COLLISION: multiple uploaded columns share { ls_map_match-staging_field }.|.
      MESSAGE lv_schema_msg TYPE 'S' DISPLAY LIKE 'E'.
      RETURN.
    ENDIF.
    INSERT ls_map_match-staging_field INTO TABLE lt_target_seen.

    READ TABLE ct_fcat ASSIGNING FIELD-SYMBOL(<ls_fcat>)
      WITH KEY fieldname = ls_map_match-staging_field.
    IF sy-subrc <> 0.
      lv_schema_msg =
        |EDIT_STAGING_BIND_INVALID: { lv_norm_source } -> { ls_map_match-staging_field }.|.
      MESSAGE lv_schema_msg TYPE 'S' DISPLAY LIKE 'E'.
      RETURN.
    ENDIF.

    lv_label = lv_source.
    READ TABLE lt_hdr_cache INTO ls_hdr_cache WITH KEY col_no = lv_col_pos.
    IF sy-subrc = 0 AND ls_hdr_cache-header_text IS NOT INITIAL.
      lv_label = ls_hdr_cache-header_text.
    ENDIF.

    lv_ltxt = lv_label.
    lv_mtxt = lv_label.
    lv_stxt = lv_label.
    lv_rep  = lv_label.

    <ls_fcat>-no_out    = space.
    <ls_fcat>-tech      = space.
    <ls_fcat>-edit      = 'X'.
    <ls_fcat>-key       = space.
    <ls_fcat>-col_pos   = lv_col_pos.
    <ls_fcat>-scrtext_l = lv_ltxt.
    <ls_fcat>-scrtext_m = lv_mtxt.
    <ls_fcat>-scrtext_s = lv_stxt.
    <ls_fcat>-reptext   = lv_rep.
  ENDLOOP.
ENDFORM.

FORM FREE_0400_GRID.
 "14D: this FORM is called only from 0400 PBO lifecycle/rebuild paths.
 "FREE <reference> alone can drop the ABAP reference while the frontend
 "control is still painted. Explicitly release every GUI control child-first
 "and flush before clearing references. This prevents Cockpit/Detail
 "split-brain where PF-STATUS says DETAIL but the old cockpit grid remains.
  IF GO_EXEC_GRID IS BOUND.
    CALL METHOD GO_EXEC_GRID->FREE EXCEPTIONS OTHERS = 1.
  ENDIF.
  IF GO_STAGING_GRID IS BOUND.
    CALL METHOD GO_STAGING_GRID->FREE EXCEPTIONS OTHERS = 1.
  ENDIF.
  IF GO_DOC_HEAD_0400 IS BOUND.
   "CL_DD_DOCUMENT is not a CL_GUI_CONTROL and has no public FREE method.
   "Release only the ABAP document reference; the parent GUI containers below
   "own the rendered frontend control and are freed explicitly afterwards.
    FREE GO_DOC_HEAD_0400.
  ENDIF.
  IF GO_SPLIT_0400 IS BOUND.
    CALL METHOD GO_SPLIT_0400->FREE EXCEPTIONS OTHERS = 1.
  ENDIF.
  IF GO_CONTAINER_0400 IS BOUND.
    CALL METHOD GO_CONTAINER_0400->FREE EXCEPTIONS OTHERS = 1.
  ENDIF.
  CALL METHOD CL_GUI_CFW=>FLUSH EXCEPTIONS OTHERS = 1.

  CLEAR: GO_EXEC_GRID, GO_STAGING_GRID, GO_GRID_0400,
         GO_DOC_HEAD_0400, GO_SPLIT_0400, GO_CONT_HEAD_0400,
         GO_CONT_BODY_0400, GO_CONTAINER_0400, G_0400_GRID_EVENTS,
         GV_0400_RENDER_SID, GV_0400_RENDER_VIEW.
ENDFORM.

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

FORM SWITCH_TO_COCKPIT.
 "PAI changes only logical view state. The 0400 PBO owns the
 "frontend control transition. 14C also pins the render marker to the
 "previous DETAIL view so the next PBO must rebuild the cockpit tree.
  GV_0400_VIEW        = GC_VIEW_COCKPIT.
  GV_0400_EDIT_MODE   = SPACE.
  GV_0400_RENDER_VIEW = GC_VIEW_DETAIL.
  CLEAR: gt_z566_edit_scope, gv_z566_edit_groups.
  PERFORM BUILD_EXEC_COCKPIT.
  PERFORM UPDATE_0400_COUNTERS.
ENDFORM.

FORM SWITCH_TO_DETAIL_EDIT.
 "Never destroy frontend controls in PAI. Pin the render marker to the
 "previous COCKPIT view so the next 0400 PBO always rebuilds DETAIL,
 "including recovery from an old split-brain GUI/internal-session state.
  GV_0400_VIEW        = GC_VIEW_DETAIL.
  GV_0400_EDIT_MODE   = 'X'.
  GV_0400_RENDER_VIEW = GC_VIEW_COCKPIT.
ENDFORM.

FORM ensure_0400_stage_scope
  CHANGING cv_ok      TYPE abap_bool
           cv_message TYPE string.

  DATA: lv_session_id TYPE zbdc_staging_bup-session_id,
        lv_sid_batch  TYPE zbdc_staging_bup-session_id,
        lv_count      TYPE i.

  CLEAR: cv_ok, cv_message, lv_session_id, lv_sid_batch, lv_count.

 "The visible Session ID is the authority for this roundtrip. Read it BEFORE
 "the fast path so a non-empty but stale GT_STAGING buffer cannot overwrite
 "the screen context when Edit Staging is pressed.
  IF gv_0400_context_locked = abap_true
     AND gv_0400_context_sid IS NOT INITIAL.
    lv_session_id = gv_0400_context_sid.
  ELSE.
    lv_session_id = txtp_session_id.
    CONDENSE lv_session_id.
    IF lv_session_id IS INITIAL.
      lv_session_id = txtp_sess.
      CONDENSE lv_session_id.
    ENDIF.
  ENDIF.
  CONDENSE lv_session_id.

 "Fast path is legal only when the visible session is actually present in
 "the loaded backend scope. Otherwise fall through and rehydrate the exact
 "visible session from DB. This is a context repair, not a latest-session pick.
  IF gt_staging IS NOT INITIAL.
    IF lv_session_id IS INITIAL.
      PERFORM sync_0400_scope.
      IF gt_staging_alv IS INITIAL.
        PERFORM prepare_alv_0400.
      ENDIF.
      cv_ok = abap_true.
      RETURN.
    ENDIF.

    READ TABLE gt_staging
      WITH KEY session_id = lv_session_id
      TRANSPORTING NO FIELDS.
    IF sy-subrc = 0.
      PERFORM sync_0400_scope.
      IF gt_staging_alv IS INITIAL.
        PERFORM prepare_alv_0400.
      ENDIF.
      cv_ok = abap_true.
      RETURN.
    ENDIF.

   "Stale backend buffer: discard only projections; exact reload below owns
   "the replacement scope and LOAD_EXACT_STAGING rebuilds session membership.
    REFRESH: gt_staging, gt_staging_alv, gt_exec_disp.
  ENDIF.

 "recovery path: only the exact SESSION_ID already displayed by
 "screen 0400 is allowed to rehydrate a lost backend buffer. Never use
 "MAX(session), newest session, dashboard cache, or another visible row.
  IF lv_session_id IS INITIAL.
    cv_message = 'The visible cockpit has no persisted Session ID to reload.'.
    RETURN.
  ENDIF.

  PERFORM batch_prefix_from_sid
    USING    lv_session_id
    CHANGING lv_sid_batch.

 "A multi-session upload may legitimately own one batch. Reuse that batch
 "only when the displayed session itself proves membership in the current
 "batch and the current context still lists multiple sessions. Otherwise
 "reload the exact displayed session only.
  IF gv_current_batch_prefix IS NOT INITIAL
     AND lines( gt_current_sessions ) > 1
     AND lv_sid_batch = gv_current_batch_prefix.
    PERFORM load_staging_by_batch
      USING    gv_current_batch_prefix
      CHANGING lv_count.
  ELSE.
    PERFORM load_staging_by_session
      USING    lv_session_id
      CHANGING lv_count.
  ENDIF.

  IF lv_count <= 0 OR gt_staging IS INITIAL.
    cv_message = |No persisted staging rows were found for Session { lv_session_id }.|.
    RETURN.
  ENDIF.

 "Rebuild only from the DB rows just loaded. This prevents a stale frontend
 "cockpit from becoming an edit source.
  PERFORM sync_0400_scope.
  PERFORM prepare_alv_0400.

  IF gt_staging_alv IS INITIAL.
    cv_message = |Session { lv_session_id } was reloaded but has no editable staging rows.|.
    RETURN.
  ENDIF.

  cv_ok = abap_true.
ENDFORM.

FORM capture_cockpit_scope
  USING    iv_purpose    TYPE csequence
  CHANGING cv_ok         TYPE abap_bool
           cv_groups     TYPE i
           cv_rows       TYPE i
           cv_message    TYPE string.

  DATA: lt_rows          TYPE lvc_t_row,
        ls_row           TYPE lvc_s_row,
        lt_cells         TYPE lvc_t_cell,
        ls_cell          TYPE lvc_s_cell,
        ls_exec          TYPE ty_exec_disp,
        ls_stg           TYPE zbdc_staging_bup,
        ls_key           TYPE ty_z566_edit_row,
        lv_group_rows    TYPE i,
        lv_batch         TYPE zbdc_staging_bup-session_id,
        lv_first_batch   TYPE zbdc_staging_bup-session_id,
        lv_tcode         TYPE zbdc_prof_bup-tcode,
        lv_profile       TYPE zbdc_prof_bup-profile_name,
        lv_ver           TYPE zbdc_prof_bup-profile_ver,
        lv_found         TYPE abap_bool,
        lv_first_tcode   TYPE zbdc_prof_bup-tcode,
        lv_first_profile TYPE zbdc_prof_bup-profile_name,
        lv_first_ver     TYPE zbdc_prof_bup-profile_ver.

  CLEAR: cv_ok, cv_groups, cv_rows, cv_message,
         gt_z566_edit_scope, gv_z566_edit_groups.

  IF gv_0400_view <> gc_view_cockpit OR go_exec_grid IS NOT BOUND.
    cv_message = 'Select staging groups from the Cockpit before editing or opening Change Audit.'.
    RETURN.
  ENDIF.

  CALL METHOD cl_gui_cfw=>flush
    EXCEPTIONS
      OTHERS = 1.

  CALL METHOD go_exec_grid->get_selected_rows
    IMPORTING et_index_rows = lt_rows.

  "ALV users often Ctrl/Shift-select cells instead of the row selector. Treat
  "every selected cell row as an explicitly selected business group too, so
  "multi-select is deterministic and does not collapse to one highlighted row.
  CALL METHOD go_exec_grid->get_selected_cells
    IMPORTING et_cell = lt_cells.
  LOOP AT lt_cells INTO ls_cell.
    IF ls_cell-row_id-index <= 0.
      CONTINUE.
    ENDIF.
    CLEAR ls_row.
    ls_row-index = ls_cell-row_id-index.
    APPEND ls_row TO lt_rows.
  ENDLOOP.

  IF lt_rows IS INITIAL.
    cv_message = 'Select one, several, or all cockpit groups first. No staging row is edited implicitly.'.
    RETURN.
  ENDIF.

  SORT lt_rows BY index.
  DELETE ADJACENT DUPLICATES FROM lt_rows COMPARING index.

  LOOP AT lt_rows INTO ls_row.
    CLEAR ls_exec.
    READ TABLE gt_exec_disp INTO ls_exec INDEX ls_row-index.
    IF sy-subrc <> 0.
      CLEAR gt_z566_edit_scope.
      cv_message = 'The selected cockpit row is no longer valid; select the scope again.'.
      RETURN.
    ENDIF.

    IF iv_purpose = 'EDIT' AND
       ls_exec-run_status = gc_st_success.
      CLEAR gt_z566_edit_scope.
      cv_message = |Group { ls_exec-group_key } is SUCCESS and is immutable. Select only groups that are not SUCCESS.|.
      RETURN.
    ENDIF.

    CLEAR lv_batch.
    PERFORM batch_prefix_from_sid
      USING    ls_exec-session_id
      CHANGING lv_batch.
    IF lv_batch IS INITIAL.
      lv_batch = ls_exec-session_id.
    ENDIF.
    IF lv_first_batch IS INITIAL.
      lv_first_batch = lv_batch.
    ELSEIF lv_batch <> lv_first_batch.
      CLEAR gt_z566_edit_scope.
      cv_message = 'Selected groups span different ingestion batches. Edit one batch at a time.'.
      RETURN.
    ENDIF.

    CLEAR: lv_tcode, lv_profile, lv_ver, lv_found.
    PERFORM resolve_session_context
      USING    ls_exec-session_id
      CHANGING lv_tcode lv_profile lv_ver lv_found.
    IF lv_found <> abap_true.
      CLEAR gt_z566_edit_scope.
      cv_message = |Frozen profile/version context is missing for selected group { ls_exec-group_key }.|.
      RETURN.
    ENDIF.
    IF lv_first_tcode IS INITIAL.
      lv_first_tcode   = lv_tcode.
      lv_first_profile = lv_profile.
      lv_first_ver     = lv_ver.
    ELSEIF lv_tcode <> lv_first_tcode OR
           lv_profile <> lv_first_profile OR
           lv_ver <> lv_first_ver.
      CLEAR gt_z566_edit_scope.
      cv_message = 'Selected groups use different frozen contracts. Edit one TCODE/Profile/Version contract at a time.'.
      RETURN.
    ENDIF.

    CLEAR lv_group_rows.
    LOOP AT gt_staging INTO ls_stg
      WHERE session_id = ls_exec-session_id
        AND record_key = ls_exec-group_key.
      IF ls_exec-tcode IS NOT INITIAL AND ls_stg-tcode <> ls_exec-tcode.
        CONTINUE.
      ENDIF.
      CLEAR ls_key.
      ls_key-session_id = ls_stg-session_id.
      ls_key-row_index  = ls_stg-row_index.
      ls_key-record_key = ls_stg-record_key.
      ls_key-tcode      = ls_stg-tcode.
      INSERT ls_key INTO TABLE gt_z566_edit_scope.
      IF sy-subrc = 0.
        lv_group_rows = lv_group_rows + 1.
      ENDIF.
    ENDLOOP.

    IF lv_group_rows = 0.
      CLEAR gt_z566_edit_scope.
      cv_message = |Selected group { ls_exec-group_key } has no persisted staging rows in the loaded scope.|.
      RETURN.
    ENDIF.

    cv_groups = cv_groups + 1.
  ENDLOOP.

  cv_rows = lines( gt_z566_edit_scope ).
  IF cv_rows <= 0.
    cv_message = 'No persisted staging rows belong to the selected cockpit groups.'.
    RETURN.
  ENDIF.

  gv_z566_edit_groups = cv_groups.
  cv_ok = abap_true.
ENDFORM.

FORM build_edit_projection
  CHANGING cv_ok      TYPE abap_bool
           cv_message TYPE string.

  DATA: lt_edit TYPE ty_t_staging_alv,
        ls_alv  TYPE ty_staging_alv,
        ls_db   TYPE zbdc_staging_bup.

  CLEAR: cv_ok, cv_message.
  IF gt_z566_edit_scope IS INITIAL.
    cv_message = 'No selected staging rows are available for editing.'.
    RETURN.
  ENDIF.

  LOOP AT gt_z566_edit_scope INTO DATA(ls_key).
    CLEAR ls_db.
    READ TABLE gt_staging INTO ls_db
      WITH KEY session_id = ls_key-session_id row_index = ls_key-row_index.
    IF sy-subrc <> 0.
      cv_message = |Selected staging row { ls_key-row_index } is no longer loaded; select the cockpit scope again.|.
      REFRESH gt_staging_alv.
      RETURN.
    ENDIF.
    CLEAR ls_alv.
    MOVE-CORRESPONDING ls_db TO ls_alv.
    APPEND ls_alv TO lt_edit.
  ENDLOOP.

  IF lt_edit IS INITIAL.
    cv_message = 'The selected cockpit scope contains no editable staging rows.'.
    RETURN.
  ENDIF.

  gt_staging_alv = lt_edit.
  cv_ok = abap_true.
ENDFORM.

FORM insert_edit_audit
  USING    iv_session TYPE any
           iv_row     TYPE any
           iv_tcode   TYPE any
           iv_field   TYPE any
           iv_old     TYPE any
           iv_new     TYPE any
  CHANGING cv_ok      TYPE abap_bool
           cv_message TYPE string.

  CLEAR: cv_ok, cv_message.
  IF iv_old = iv_new.
    cv_ok = abap_true.
    RETURN.
  ENDIF.

  PERFORM insert_change_audit_row
    USING    iv_session iv_row iv_tcode iv_field iv_old iv_new 'DETAIL_EDIT'
    CHANGING cv_ok cv_message.
ENDFORM.

FORM log_edit_audit
  CHANGING cv_ok      TYPE abap_bool
           cv_count   TYPE i
           cv_message TYPE string.

  DATA: lt_map     TYPE STANDARD TABLE OF zbdc_mapping_bup,
        ls_map     TYPE zbdc_mapping_bup,
        ls_db      TYPE zbdc_staging_bup,
        lv_tcode   TYPE zbdc_prof_bup-tcode,
        lv_profile TYPE zbdc_prof_bup-profile_name,
        lv_ver     TYPE zbdc_prof_bup-profile_ver,
        lv_found   TYPE abap_bool,
        lv_old     TYPE string,
        lv_new     TYPE string,
        lv_one_ok  TYPE abap_bool,
        lv_one_msg TYPE string.
  FIELD-SYMBOLS: <lv_old_any> TYPE any,
                 <lv_new_any> TYPE any.

  CLEAR: cv_ok, cv_count, cv_message.
  READ TABLE gt_staging_alv INTO DATA(ls_first) INDEX 1.
  IF sy-subrc <> 0.
    cv_message = 'No selected staging rows are available for audit.'.
    RETURN.
  ENDIF.

  PERFORM resolve_session_context
    USING    ls_first-session_id
    CHANGING lv_tcode lv_profile lv_ver lv_found.
  IF lv_found <> abap_true.
    cv_message = 'Frozen mapping context could not be resolved for Change Audit.'.
    RETURN.
  ENDIF.

  SELECT * FROM zbdc_mapping_bup INTO TABLE @lt_map
    WHERE tcode        = @lv_tcode
      AND profile_name = @lv_profile
      AND profile_ver  = @lv_ver.
  DELETE lt_map WHERE staging_field IS INITIAL OR source_column IS INITIAL.
  SORT lt_map BY staging_field.
  DELETE ADJACENT DUPLICATES FROM lt_map COMPARING staging_field.

  LOOP AT gt_staging_alv INTO DATA(ls_new).
    CLEAR ls_db.
    SELECT SINGLE * FROM zbdc_staging_bup INTO @ls_db
      WHERE session_id = @ls_new-session_id
        AND row_index  = @ls_new-row_index.
    IF sy-subrc <> 0.
      cv_message = |Staging row { ls_new-row_index } disappeared before audit; nothing was saved.|.
      RETURN.
    ENDIF.

    LOOP AT lt_map INTO ls_map.
      IF ls_map-staging_field(5) <> 'FIELD'.
        CONTINUE.
      ENDIF.
      ASSIGN COMPONENT ls_map-staging_field OF STRUCTURE ls_db TO <lv_old_any>.
      ASSIGN COMPONENT ls_map-staging_field OF STRUCTURE ls_new TO <lv_new_any>.
      IF sy-subrc <> 0 OR <lv_old_any> IS NOT ASSIGNED OR <lv_new_any> IS NOT ASSIGNED.
        UNASSIGN: <lv_old_any>, <lv_new_any>.
        CONTINUE.
      ENDIF.
      lv_old = |{ <lv_old_any> }|.
      lv_new = |{ <lv_new_any> }|.
      UNASSIGN: <lv_old_any>, <lv_new_any>.
      IF lv_old = lv_new.
        CONTINUE.
      ENDIF.

      CLEAR: lv_one_ok, lv_one_msg.
      PERFORM insert_edit_audit
        USING    ls_new-session_id ls_new-row_index ls_new-tcode
                 ls_map-staging_field lv_old lv_new
        CHANGING lv_one_ok lv_one_msg.
      IF lv_one_ok <> abap_true.
        cv_message = lv_one_msg.
        RETURN.
      ENDIF.
      cv_count = cv_count + 1.
    ENDLOOP.
  ENDLOOP.

  cv_ok = abap_true.
ENDFORM.

FORM restore_after_validation
  USING    it_full      TYPE ty_t_z566_staging_db
           it_validated TYPE ty_t_z566_staging_db.
  FIELD-SYMBOLS: <ls_full> TYPE zbdc_staging_bup,
                 <ls_val>  TYPE zbdc_staging_bup.

  gt_staging = it_full.
  LOOP AT it_validated ASSIGNING <ls_val>.
    READ TABLE gt_staging ASSIGNING <ls_full>
      WITH KEY session_id = <ls_val>-session_id row_index = <ls_val>-row_index.
    IF sy-subrc = 0.
      <ls_full> = <ls_val>.
    ELSE.
      APPEND <ls_val> TO gt_staging.
    ENDIF.
  ENDLOOP.
ENDFORM.

*&---------------------------------------------------------------------*
*& Edit Staging Business Key merge gate
*&---------------------------------------------------------------------*
*& A user may change FIELD01 (BUSINESS_KEY) after initial Staging.
*& Validate the COMPLETE post-edit destination/source groups, not only the
*& rows currently selected in the editor. This prevents a row from being
*& moved into an existing Business Key and bypassing the cardinality proof.
*& The check is read-only; persistence still happens only after the normal
*& audit + staging validation transaction succeeds.
FORM check_edit_business_key_merge
  CHANGING cv_ok      TYPE abap_bool
           cv_message TYPE string.

  TYPES: BEGIN OF ty_affected_key,
           record_key TYPE zbdc_staging_bup-record_key,
         END OF ty_affected_key.

  DATA: lt_sessions  TYPE SORTED TABLE OF zbdc_staging_bup-session_id
                       WITH UNIQUE KEY table_line,
        lv_session   TYPE zbdc_staging_bup-session_id,
        lt_candidate TYPE ty_t_z566_staging_db,
        lt_group     TYPE ty_t_staging_alv,
        lt_keys      TYPE HASHED TABLE OF ty_affected_key
                       WITH UNIQUE KEY record_key,
        ls_key       TYPE ty_affected_key,
        lv_group_ok  TYPE abap_bool,
        lv_group_msg TYPE string.

  FIELD-SYMBOLS: <ls_candidate> TYPE zbdc_staging_bup.

  CLEAR: cv_ok, cv_message.

  "Edit Staging may contain several explicitly selected groups/files from the
  "same ingestion batch/contract. Validate Business-Key merge semantics per
  "real Session ID; the old code checked only the first session and therefore
  "rejected or ignored rows from additional selected files.
  LOOP AT gt_staging_alv INTO DATA(ls_session_row).
    IF ls_session_row-session_id IS NOT INITIAL.
      INSERT ls_session_row-session_id INTO TABLE lt_sessions.
    ENDIF.
  ENDLOOP.
  IF lt_sessions IS INITIAL.
    cv_message = 'Edit Staging Business Key validation has no Session ID.'.
    RETURN.
  ENDIF.

  LOOP AT lt_sessions INTO lv_session.
    REFRESH: lt_candidate, lt_group.
    CLEAR lt_keys.

    SELECT *
      FROM zbdc_staging_bup
      INTO TABLE @lt_candidate
      WHERE session_id = @lv_session.
    IF sy-subrc <> 0 OR lt_candidate IS INITIAL.
      cv_message = |No persisted staging rows exist for session { lv_session }.|.
      RETURN.
    ENDIF.

    LOOP AT gt_staging_alv INTO DATA(ls_edit)
      WHERE session_id = lv_session.
      READ TABLE lt_candidate ASSIGNING <ls_candidate>
        WITH KEY session_id = ls_edit-session_id
                 row_index  = ls_edit-row_index.
      IF sy-subrc <> 0 OR <ls_candidate> IS NOT ASSIGNED.
        cv_message = |Edited staging row { ls_edit-row_index } no longer exists; reload Edit Staging.|.
        RETURN.
      ENDIF.

      IF <ls_candidate>-record_key IS NOT INITIAL.
        CLEAR ls_key.
        ls_key-record_key = <ls_candidate>-record_key.
        INSERT ls_key INTO TABLE lt_keys.
      ENDIF.

      MOVE-CORRESPONDING ls_edit TO <ls_candidate>.
      <ls_candidate>-record_key = <ls_candidate>-field01.

      IF <ls_candidate>-record_key IS INITIAL.
        cv_message = |Row { ls_edit-row_index }: Business Key cannot be blank after Edit Staging.|.
        RETURN.
      ENDIF.

      CLEAR ls_key.
      ls_key-record_key = <ls_candidate>-record_key.
      INSERT ls_key INTO TABLE lt_keys.
    ENDLOOP.

    LOOP AT lt_keys INTO ls_key WHERE record_key IS NOT INITIAL.
      REFRESH lt_group.
      LOOP AT lt_candidate INTO DATA(ls_candidate)
        WHERE record_key = ls_key-record_key.
        DATA(ls_group_alv) = VALUE ty_staging_alv( ).
        MOVE-CORRESPONDING ls_candidate TO ls_group_alv.
        APPEND ls_group_alv TO lt_group.
      ENDLOOP.

      IF lt_group IS INITIAL.
        CONTINUE.
      ENDIF.

      CLEAR: lv_group_ok, lv_group_msg.
      PERFORM check_group_cardinality_proof
        USING    lt_group
        CHANGING lv_group_ok lv_group_msg.
      IF lv_group_ok <> abap_true.
        cv_message = lv_group_msg.
        IF cv_message IS INITIAL.
          cv_message = |Edited Business Key { ls_key-record_key } is not valid for the frozen recording contract.|.
        ENDIF.
        RETURN.
      ENDIF.

      CLEAR: lv_group_ok, lv_group_msg.
      PERFORM check_blank_contract_group
        USING    lt_group
        CHANGING lv_group_ok lv_group_msg.
      IF lv_group_ok <> abap_true.
        cv_message = lv_group_msg.
        RETURN.
      ENDIF.
    ENDLOOP.
  ENDLOOP.

  cv_ok = abap_true.
ENDFORM.

FORM SAVE_DETAIL_AND_RETURN.
  DATA: lv_can_run      TYPE abap_bool,
        lv_locked       TYPE abap_bool,
        lv_scope_ok     TYPE abap_bool,
        lv_changed      TYPE i,
        lv_scope_msg    TYPE string,
        lv_val_ok       TYPE abap_bool,
        lv_merge_ok     TYPE abap_bool,
        lv_audit_exists TYPE abap_bool,
        lv_audit_ok     TYPE abap_bool,
        lv_audit_count  TYPE i,
        lv_audit_msg    TYPE string,
        lv_merge_msg    TYPE string,
        lv_val_msg      TYPE string,
        lv_session_id   TYPE zbdc_staging_bup-session_id,
        lt_full         TYPE ty_t_z566_staging_db,
        lt_selected     TYPE ty_t_z566_staging_db,
        lt_validated    TYPE ty_t_z566_staging_db,
        lt_user_edit    TYPE ty_t_staging_alv.

  IF gt_z566_edit_scope IS INITIAL.
    MESSAGE s621(zbdc) DISPLAY LIKE 'W'.
    RETURN.
  ENDIF.

  IF go_staging_grid IS BOUND.
    go_staging_grid->check_changed_data( ).
  ENDIF.

  READ TABLE gt_z566_edit_scope INTO DATA(ls_first_key) INDEX 1.
  IF sy-subrc <> 0 OR ls_first_key-session_id IS INITIAL.
    MESSAGE s622(zbdc) DISPLAY LIKE 'E'.
    RETURN.
  ENDIF.
  lv_session_id = ls_first_key-session_id.

  PERFORM acquire_staging_lock_safe
    USING    lv_session_id
    CHANGING lv_can_run lv_locked.
  IF lv_can_run <> abap_true OR lv_locked <> abap_true.
    RETURN.
  ENDIF.

  TRY.
      CLEAR: lv_scope_ok, lv_changed, lv_scope_msg.
      PERFORM check_staging_edit_scope
        CHANGING lv_scope_ok lv_changed lv_scope_msg.

 "A changed BUSINESS_KEY can merge this row into a group that was not part
 "of the edit selection. Validate the complete post-edit affected groups
 "before audit/persistence so Edit Staging cannot bypass the Staging gate.
      CLEAR: lv_merge_ok, lv_merge_msg.
      IF lv_scope_ok = abap_true AND lv_changed > 0.
        PERFORM check_edit_business_key_merge
          CHANGING lv_merge_ok lv_merge_msg.
      ENDIF.

      IF lv_scope_ok <> abap_true.
        ROLLBACK WORK.
      ELSEIF lv_changed = 0.
        ROLLBACK WORK.
        PERFORM switch_to_cockpit.
      ELSEIF lv_merge_ok <> abap_true.
        ROLLBACK WORK.
        lv_val_msg = lv_merge_msg.
      ELSE.
        CLEAR lv_audit_exists.
        PERFORM table_exists USING gc_z16_tab_chg CHANGING lv_audit_exists.
        IF lv_audit_exists <> abap_true.
          ROLLBACK WORK.
          lv_val_msg = 'ZBDC_CHG_BUP is not installed; selected staging changes were not saved because audit is mandatory.'.
        ELSE.
          CLEAR: lv_audit_ok, lv_audit_count, lv_audit_msg.
          PERFORM log_edit_audit
            CHANGING lv_audit_ok lv_audit_count lv_audit_msg.
          IF lv_audit_ok <> abap_true.
            ROLLBACK WORK.
            lv_val_msg = lv_audit_msg.
          ELSEIF lv_audit_count <= 0.
            ROLLBACK WORK.
            lv_changed = 0.
            PERFORM switch_to_cockpit.
          ELSE.
            lt_full      = gt_staging.
            lt_user_edit = gt_staging_alv.

 "Merge only user-selected rows into the full in-memory baseline,
 "then isolate those exact rows for validation/persistence. This
 "prevents Save from revalidating or normalizing unselected groups.
            PERFORM sync_staging_from_alv.
            REFRESH lt_selected.
            LOOP AT gt_z566_edit_scope INTO DATA(ls_scope_key).
              READ TABLE gt_staging INTO DATA(ls_selected_db)
                WITH KEY session_id = ls_scope_key-session_id row_index = ls_scope_key-row_index.
              IF sy-subrc <> 0.
                ROLLBACK WORK.
                lv_val_msg = |Selected staging row { ls_scope_key-row_index } disappeared before validation.|.
                EXIT.
              ENDIF.
              APPEND ls_selected_db TO lt_selected.
            ENDLOOP.

            IF lv_val_msg IS INITIAL.
              gt_staging = lt_selected.
              PERFORM prepare_alv_0400.

              CLEAR: lv_val_ok, lv_val_msg.
              PERFORM validate_staging
                CHANGING lv_val_ok lv_val_msg.

              IF lv_val_ok = abap_true.
                lt_validated = gt_staging.
                PERFORM restore_after_validation
                  USING lt_full lt_validated.
                PERFORM prepare_alv_0400.
                PERFORM switch_to_cockpit.
              ELSE.
                ROLLBACK WORK.
                gt_staging     = lt_full.
                gt_staging_alv = lt_user_edit.
              ENDIF.
            ELSE.
              gt_staging     = lt_full.
              gt_staging_alv = lt_user_edit.
            ENDIF.
          ENDIF.
        ENDIF.
      ENDIF.

    CATCH cx_root INTO DATA(lx_z566_edit).
      ROLLBACK WORK.
      IF lv_locked = abap_true.
        PERFORM release_staging_lock USING lv_session_id.
        CLEAR lv_locked.
      ENDIF.
      RAISE SHORTDUMP lx_z566_edit.
  ENDTRY.

  IF lv_locked = abap_true.
    PERFORM release_staging_lock USING lv_session_id.
    CLEAR lv_locked.
  ENDIF.

  IF lv_scope_ok <> abap_true.
    MESSAGE lv_scope_msg TYPE 'S' DISPLAY LIKE 'E'.
    RETURN.
  ENDIF.

  IF lv_changed = 0.
    MESSAGE s623(zbdc).
    RETURN.
  ENDIF.

  IF lv_merge_ok <> abap_true.
    IF lv_val_msg IS INITIAL.
      lv_val_msg = lv_merge_msg.
    ENDIF.
    MESSAGE lv_val_msg TYPE 'S' DISPLAY LIKE 'E'.
    RETURN.
  ENDIF.

  IF lv_audit_ok <> abap_true.
    IF lv_val_msg IS INITIAL.
      lv_val_msg = lv_audit_msg.
    ENDIF.
    MESSAGE lv_val_msg TYPE 'S' DISPLAY LIKE 'E'.
    RETURN.
  ENDIF.

  IF lv_val_ok <> abap_true.
    MESSAGE lv_val_msg TYPE 'S' DISPLAY LIKE 'E'.
    RETURN.
  ENDIF.

  MESSAGE s624(zbdc) WITH lv_audit_count lv_val_msg.
ENDFORM.

FORM check_staging_edit_scope
  CHANGING cv_ok      TYPE abap_bool
           cv_changed TYPE i
           cv_message TYPE string.

  DATA: ls_db      TYPE zbdc_staging_bup,
        lv_idx     TYPE n LENGTH 2,
        lv_field   TYPE char10,
        lv_old     TYPE string,
        lv_new     TYPE string,
        lv_row_chg TYPE abap_bool.
  FIELD-SYMBOLS: <lv_old_any> TYPE any,
                 <lv_new_any> TYPE any.

  CLEAR: cv_ok, cv_changed, cv_message.

  LOOP AT gt_staging_alv INTO DATA(ls_new).
    CLEAR ls_db.
    SELECT SINGLE *
      FROM zbdc_staging_bup
      INTO @ls_db
      WHERE session_id = @ls_new-session_id
        AND row_index  = @ls_new-row_index.
    IF sy-subrc <> 0.
      cv_message = |Staging row { ls_new-row_index } no longer exists; reload the scope before editing again.|.
      RETURN.
    ENDIF.

    "SUCCESS is the only immutable staging lifecycle. Recheck the persisted
    "row at save time so a group that became SUCCESS after Edit Staging was
    "opened cannot be modified by a stale editor window.
    IF ls_db-status = gc_st_success OR ls_db-status = 'SUCCESS'.
      cv_message = |Business Group { ls_db-record_key } is SUCCESS and cannot be edited. Reload Staging before continuing.|.
      RETURN.
    ENDIF.

    CLEAR lv_row_chg.
    DO 25 TIMES.
      lv_idx = sy-index.
      CONCATENATE 'FIELD' lv_idx INTO lv_field.
      ASSIGN COMPONENT lv_field OF STRUCTURE ls_db TO <lv_old_any>.
      ASSIGN COMPONENT lv_field OF STRUCTURE ls_new TO <lv_new_any>.
      IF sy-subrc = 0 AND <lv_old_any> IS ASSIGNED AND <lv_new_any> IS ASSIGNED.
        lv_old = |{ <lv_old_any> }|.
        lv_new = |{ <lv_new_any> }|.
        IF lv_old <> lv_new.
          lv_row_chg = abap_true.
          UNASSIGN: <lv_old_any>, <lv_new_any>.
          EXIT.
        ENDIF.
      ENDIF.
      UNASSIGN: <lv_old_any>, <lv_new_any>.
    ENDDO.

    IF lv_row_chg <> abap_true.
      CONTINUE.
    ENDIF.

    "No additional lifecycle is locked here. SUCCESS was rechecked above;
    "READY/ERROR/WARNING/RUNNING/queued states remain editable by design.
    cv_changed = cv_changed + 1.
  ENDLOOP.

  cv_ok = abap_true.
ENDFORM.

FORM cancel_detail_edit.
 "GT_STAGING is the persisted baseline until Save. Rebuild the editable
 "projection from it, discarding frontend-only cell edits.
  PERFORM prepare_alv_0400.
  PERFORM switch_to_cockpit.
  MESSAGE s625(zbdc).
ENDFORM.

*& native SAP GUI session-wide Change History

FORM free_change_history.
  IF go_z770_hist_grid IS BOUND.
    CALL METHOD go_z770_hist_grid->free EXCEPTIONS OTHERS = 1.
  ENDIF.
  IF go_z770_before_grid IS BOUND.
    CALL METHOD go_z770_before_grid->free EXCEPTIONS OTHERS = 1.
  ENDIF.
  IF go_z770_after_grid IS BOUND.
    CALL METHOD go_z770_after_grid->free EXCEPTIONS OTHERS = 1.
  ENDIF.
  IF go_z770_split_diff IS BOUND.
    CALL METHOD go_z770_split_diff->free EXCEPTIONS OTHERS = 1.
  ENDIF.
  IF go_z770_split_main IS BOUND.
    CALL METHOD go_z770_split_main->free EXCEPTIONS OTHERS = 1.
  ENDIF.
  IF go_z770_dialog IS BOUND.
    CALL METHOD go_z770_dialog->free EXCEPTIONS OTHERS = 1.
  ENDIF.

  CLEAR: go_z770_hist_grid, go_z770_before_grid, go_z770_after_grid,
         go_z770_split_diff, go_z770_split_main, go_z770_dialog,
         go_z770_hist_cont, go_z770_before_cont, go_z770_after_cont,
         gv_z770_selected_idx.
  REFRESH: gt_z770_before_disp, gt_z770_after_disp.
ENDFORM.

FORM load_change_history
  CHANGING cv_ok      TYPE abap_bool
           cv_message TYPE string.

  DATA: lv_exists  TYPE abap_bool,
        lv_tab     TYPE tabname,
        lv_where   TYPE string,
        lv_session TYPE zbdc_staging_bup-session_id,
        lt_map     TYPE STANDARD TABLE OF zbdc_mapping_bup,
        lv_tcode   TYPE zbdc_prof_bup-tcode,
        lv_profile TYPE zbdc_prof_bup-profile_name,
        lv_ver     TYPE zbdc_prof_bup-profile_ver,
        lv_found   TYPE abap_bool,
        lv_group   TYPE zbdc_staging_bup-record_key,
        lv_label   TYPE char80,
        lv_date    TYPE sy-datum,
        lv_time    TYPE sy-uzeit,
        lv_date_txt TYPE char10,
        lv_time_txt TYPE char8,
        lt_rows_seen TYPE SORTED TABLE OF zbdc_staging_bup-row_index WITH UNIQUE KEY table_line,
        lt_groups_seen TYPE SORTED TABLE OF zbdc_staging_bup-record_key WITH UNIQUE KEY table_line.

  CLEAR: cv_ok, cv_message, gv_z770_total_changes,
         gv_z770_changed_rows, gv_z770_changed_groups.
  REFRESH: gt_z770_audit_raw, gt_z770_audit_disp.

  IF gv_0400_context_locked = abap_true
     AND gv_0400_context_sid IS NOT INITIAL.
    lv_session = gv_0400_context_sid.
  ELSE.
    lv_session = txtp_session_id.
    IF lv_session IS INITIAL.
      lv_session = txtp_sess.
    ENDIF.
  ENDIF.
  IF lv_session IS INITIAL.
    cv_message = 'No current staging session is available for Change History.'.
    RETURN.
  ENDIF.

  PERFORM table_exists USING gc_z16_tab_chg CHANGING lv_exists.
  IF lv_exists <> abap_true.
    cv_message = 'ZBDC_CHG_BUP is not installed; Change History is unavailable.'.
    RETURN.
  ENDIF.

  lv_tab = gc_z16_tab_chg.
  lv_where = |SESSION_ID = '{ lv_session }'|.
  TRY.
      SELECT * FROM (lv_tab)
        INTO CORRESPONDING FIELDS OF TABLE @gt_z770_audit_raw
        WHERE (lv_where).
    CATCH cx_root INTO DATA(lx_hist_read).
      cv_message = lx_hist_read->get_text( ).
      RETURN.
  ENDTRY.

  "INGEST_SNAPSHOT is immutable Preview evidence, not a user change. Keep it
  "out of Change History while manual/retry edits remain fully visible.
  DELETE gt_z770_audit_raw WHERE change_action = 'INGEST_SNAPSHOT'.

  IF gt_z770_audit_raw IS INITIAL.
    cv_message = 'No manual staging changes have been saved in this session.'.
    RETURN.
  ENDIF.

  PERFORM resolve_session_context
    USING    lv_session
    CHANGING lv_tcode lv_profile lv_ver lv_found.
  IF lv_found = abap_true.
    SELECT * FROM zbdc_mapping_bup
      INTO TABLE @lt_map
      WHERE profile_name = @lv_profile
        AND profile_ver  = @lv_ver.
    DELETE lt_map WHERE staging_field IS INITIAL OR source_column IS INITIAL.
    SORT lt_map BY tcode staging_field source_column.
    DELETE ADJACENT DUPLICATES FROM lt_map COMPARING tcode staging_field.
  ENDIF.

  SORT gt_z770_audit_raw BY changed_at DESCENDING change_id DESCENDING.
  LOOP AT gt_z770_audit_raw INTO DATA(ls_raw).
    CLEAR: lv_group, lv_label, lv_date, lv_time, lv_date_txt, lv_time_txt.

    SELECT SINGLE record_key
      FROM zbdc_staging_bup
      INTO @lv_group
      WHERE session_id = @ls_raw-session_id
        AND row_index  = @ls_raw-row_index.
    IF sy-subrc <> 0 OR lv_group IS INITIAL.
      IF ls_raw-field_name = 'FIELD01' AND ls_raw-new_value IS NOT INITIAL.
        lv_group = ls_raw-new_value.
      ELSE.
        lv_group = '-'.
      ENDIF.
    ENDIF.

    READ TABLE lt_map INTO DATA(ls_map) WITH KEY tcode = ls_raw-tcode staging_field = ls_raw-field_name.
    IF sy-subrc = 0 AND ls_map-source_column IS NOT INITIAL.
      lv_label = ls_map-source_column.
    ELSE.
      lv_label = ls_raw-field_name.
    ENDIF.

    PERFORM ts_to_demo USING ls_raw-changed_at CHANGING lv_date lv_time.
    DATA(lv_changed_text) = CONV char19( '' ).
    IF lv_date IS NOT INITIAL.
      CONCATENATE lv_date+0(4) '-' lv_date+4(2) '-' lv_date+6(2)
        INTO lv_date_txt.
      CONCATENATE lv_time+0(2) ':' lv_time+2(2) ':' lv_time+4(2)
        INTO lv_time_txt.
      CONCATENATE lv_date_txt lv_time_txt INTO lv_changed_text SEPARATED BY space.
    ENDIF.

    APPEND VALUE ty_z770_audit_disp(
      seq_no       = lines( gt_z770_audit_disp ) + 1
      changed_at   = ls_raw-changed_at
      changed_text = lv_changed_text
      group_key    = lv_group
      row_index    = ls_raw-row_index
      tcode        = ls_raw-tcode
      field_label  = lv_label
      before_value = ls_raw-old_value
      after_value  = ls_raw-new_value
      changed_by   = ls_raw-changed_by
      change_id    = ls_raw-change_id ) TO gt_z770_audit_disp.

    INSERT ls_raw-row_index INTO TABLE lt_rows_seen.
    IF lv_group IS NOT INITIAL AND lv_group <> '-'.
      INSERT lv_group INTO TABLE lt_groups_seen.
    ENDIF.
  ENDLOOP.

  gv_z770_total_changes  = lines( gt_z770_audit_disp ).
  gv_z770_changed_rows   = lines( lt_rows_seen ).
  gv_z770_changed_groups = lines( lt_groups_seen ).
  cv_ok = abap_true.
ENDFORM.

FORM build_history_fcat CHANGING ct_fcat TYPE lvc_t_fcat.
  DATA ls_fcat TYPE lvc_s_fcat.
  REFRESH ct_fcat.

  DEFINE add_hist_col.
    CLEAR ls_fcat.
    ls_fcat-fieldname = &1.
    ls_fcat-coltext   = &2.
    ls_fcat-outputlen = &3.
    ls_fcat-col_pos   = &4.
    APPEND ls_fcat TO ct_fcat.
  END-OF-DEFINITION.

  add_hist_col 'SEQ_NO'       '#'              5   1.
  add_hist_col 'CHANGED_TEXT' 'Changed At'     19  2.
  add_hist_col 'GROUP_KEY'    'Business Group' 20  3.
  add_hist_col 'ROW_INDEX'    'Input Row'      8   4.
  add_hist_col 'TCODE'        'TCode'          10  5.
  add_hist_col 'FIELD_LABEL'  'Changed Field'  28  6.
  add_hist_col 'BEFORE_VALUE' 'Before'         28  7.
  add_hist_col 'AFTER_VALUE'  'After'          28  8.
  add_hist_col 'CHANGED_BY'   'Changed By'     12  9.

  CLEAR ls_fcat.
  ls_fcat-fieldname = 'CHANGE_ID'.
  ls_fcat-tech = 'X'.
  APPEND ls_fcat TO ct_fcat.
  CLEAR ls_fcat.
  ls_fcat-fieldname = 'CHANGED_AT'.
  ls_fcat-tech = 'X'.
  APPEND ls_fcat TO ct_fcat.
ENDFORM.

FORM build_diff_fcat CHANGING ct_fcat TYPE lvc_t_fcat.
  DATA ls_fcat TYPE lvc_s_fcat.
  REFRESH ct_fcat.

  CLEAR ls_fcat.
  ls_fcat-fieldname = 'FIELD_LABEL'.
  ls_fcat-coltext = 'Input Field'.
  ls_fcat-outputlen = 34.
  ls_fcat-col_pos = 1.
  APPEND ls_fcat TO ct_fcat.

  CLEAR ls_fcat.
  ls_fcat-fieldname = 'FIELD_VALUE'.
  ls_fcat-coltext = 'Value'.
  ls_fcat-outputlen = 54.
  ls_fcat-col_pos = 2.
  APPEND ls_fcat TO ct_fcat.

  CLEAR ls_fcat.
  ls_fcat-fieldname = 'ROW_COLOR'.
  ls_fcat-tech = 'X'.
  APPEND ls_fcat TO ct_fcat.
ENDFORM.

FORM show_audit_detail USING iv_index TYPE i.
  DATA: ls_event    TYPE ty_z770_audit_disp,
        ls_raw      TYPE ty_z770_audit_raw,
        ls_current  TYPE zbdc_staging_bup,
        ls_before   TYPE zbdc_staging_bup,
        ls_after    TYPE zbdc_staging_bup,
        lt_map      TYPE STANDARD TABLE OF zbdc_mapping_bup,
        lv_tcode    TYPE zbdc_prof_bup-tcode,
        lv_profile  TYPE zbdc_prof_bup-profile_name,
        lv_ver      TYPE zbdc_prof_bup-profile_ver,
        lv_found    TYPE abap_bool,
        lv_label    TYPE char80,
        lv_before   TYPE string,
        lv_after    TYPE string,
        lv_changed  TYPE abap_bool,
        ls_stable   TYPE lvc_s_stbl.
  FIELD-SYMBOLS: <lv_any> TYPE any,
                 <lv_bef> TYPE any,
                 <lv_aft> TYPE any.

  IF iv_index <= 0.
    RETURN.
  ENDIF.
  READ TABLE gt_z770_audit_disp INTO ls_event INDEX iv_index.
  IF sy-subrc <> 0.
    RETURN.
  ENDIF.
  READ TABLE gt_z770_audit_raw INTO ls_raw WITH KEY change_id = ls_event-change_id.
  IF sy-subrc <> 0.
    RETURN.
  ENDIF.

  SELECT SINGLE * FROM zbdc_staging_bup
    INTO @ls_current
    WHERE session_id = @ls_raw-session_id
      AND row_index  = @ls_raw-row_index.
  IF sy-subrc <> 0.
    MESSAGE 'The current persisted staging row no longer exists.' TYPE 'S' DISPLAY LIKE 'W'.
    RETURN.
  ENDIF.

  ls_after = ls_current.
 "Start from the latest persisted row and undo every later audit event.
  LOOP AT gt_z770_audit_raw INTO DATA(ls_later)
    WHERE session_id = ls_raw-session_id
      AND row_index  = ls_raw-row_index.
    IF ls_later-changed_at <= ls_raw-changed_at.
      CONTINUE.
    ENDIF.
    ASSIGN COMPONENT ls_later-field_name OF STRUCTURE ls_after TO <lv_any>.
    IF sy-subrc = 0 AND <lv_any> IS ASSIGNED.
      <lv_any> = ls_later-old_value.
    ENDIF.
    UNASSIGN <lv_any>.
  ENDLOOP.

 "Pin the selected event to its persisted NEW value, then derive BEFORE.
  ASSIGN COMPONENT ls_raw-field_name OF STRUCTURE ls_after TO <lv_any>.
  IF sy-subrc = 0 AND <lv_any> IS ASSIGNED.
    <lv_any> = ls_raw-new_value.
  ENDIF.
  UNASSIGN <lv_any>.

  ls_before = ls_after.
  ASSIGN COMPONENT ls_raw-field_name OF STRUCTURE ls_before TO <lv_any>.
  IF sy-subrc = 0 AND <lv_any> IS ASSIGNED.
    <lv_any> = ls_raw-old_value.
  ENDIF.
  UNASSIGN <lv_any>.

  PERFORM resolve_session_context
    USING    ls_raw-session_id
    CHANGING lv_tcode lv_profile lv_ver lv_found.
  IF lv_found = abap_true.
    SELECT * FROM zbdc_mapping_bup
      INTO TABLE @lt_map
      WHERE profile_name = @lv_profile
        AND profile_ver  = @lv_ver.
    DELETE lt_map WHERE staging_field IS INITIAL OR source_column IS INITIAL.
    SORT lt_map BY tcode staging_field source_column.
    DELETE ADJACENT DUPLICATES FROM lt_map COMPARING tcode staging_field.
  ENDIF.

  REFRESH: gt_z770_before_disp, gt_z770_after_disp.
  LOOP AT lt_map INTO DATA(ls_map) WHERE tcode = ls_raw-tcode.
    IF ls_map-staging_field(5) <> 'FIELD'.
      CONTINUE.
    ENDIF.
    ASSIGN COMPONENT ls_map-staging_field OF STRUCTURE ls_before TO <lv_bef>.
    ASSIGN COMPONENT ls_map-staging_field OF STRUCTURE ls_after  TO <lv_aft>.
    IF <lv_bef> IS NOT ASSIGNED OR <lv_aft> IS NOT ASSIGNED.
      UNASSIGN: <lv_bef>, <lv_aft>.
      CONTINUE.
    ENDIF.
    lv_before = |{ <lv_bef> }|.
    lv_after  = |{ <lv_aft> }|.
    UNASSIGN: <lv_bef>, <lv_aft>.

    IF lv_before IS INITIAL AND lv_after IS INITIAL AND
       ls_map-staging_field <> ls_raw-field_name.
      CONTINUE.
    ENDIF.

    CLEAR lv_label.
    PERFORM l2_field_label USING ls_map CHANGING lv_label.
    lv_changed = xsdbool( ls_map-staging_field = ls_raw-field_name ).

    APPEND VALUE ty_z770_diff_disp(
      field_label = lv_label
      field_value = COND #( WHEN lv_before IS INITIAL THEN '-' ELSE lv_before )
      row_color   = COND #( WHEN lv_changed = abap_true THEN 'C610' ELSE space ) )
      TO gt_z770_before_disp.
    APPEND VALUE ty_z770_diff_disp(
      field_label = lv_label
      field_value = COND #( WHEN lv_after IS INITIAL THEN '-' ELSE lv_after )
      row_color   = COND #( WHEN lv_changed = abap_true THEN 'C510' ELSE space ) )
      TO gt_z770_after_disp.
  ENDLOOP.

 "Fail-safe fallback when old/custom mapping metadata is unavailable.
  IF gt_z770_before_disp IS INITIAL.
    APPEND VALUE ty_z770_diff_disp(
      field_label = ls_event-field_label
      field_value = ls_event-before_value
      row_color   = 'C610' ) TO gt_z770_before_disp.
    APPEND VALUE ty_z770_diff_disp(
      field_label = ls_event-field_label
      field_value = ls_event-after_value
      row_color   = 'C510' ) TO gt_z770_after_disp.
  ENDIF.

  gv_z770_selected_idx = iv_index.
  ls_stable-row = 'X'.
  ls_stable-col = 'X'.
  IF go_z770_before_grid IS BOUND.
    CALL METHOD go_z770_before_grid->refresh_table_display
      EXPORTING is_stable = ls_stable.
  ENDIF.
  IF go_z770_after_grid IS BOUND.
    CALL METHOD go_z770_after_grid->refresh_table_display
      EXPORTING is_stable = ls_stable.
  ENDIF.
ENDFORM.

FORM show_change_history.
  DATA: lv_ok      TYPE abap_bool,
        lv_message TYPE string,
        lt_hist_fcat TYPE lvc_t_fcat,
        lt_diff_fcat TYPE lvc_t_fcat,
        ls_hist_layo TYPE lvc_s_layo,
        ls_diff_layo TYPE lvc_s_layo,
        lv_caption TYPE c LENGTH 120,
        lv_session TYPE zbdc_staging_bup-session_id.

  PERFORM free_change_history.
  CLEAR: lv_ok, lv_message.
  PERFORM load_change_history CHANGING lv_ok lv_message.
  IF lv_ok <> abap_true.
    IF lv_message IS INITIAL.
      lv_message = 'No Change History is available for this session.'.
    ENDIF.
    MESSAGE lv_message TYPE 'S' DISPLAY LIKE 'I'.
    RETURN.
  ENDIF.

  IF gv_0400_context_locked = abap_true
     AND gv_0400_context_sid IS NOT INITIAL.
    lv_session = gv_0400_context_sid.
  ELSE.
    lv_session = txtp_session_id.
    IF lv_session IS INITIAL.
      lv_session = txtp_sess.
    ENDIF.
  ENDIF.
  lv_caption = |Change History - { lv_session } - { gv_z770_changed_groups } group(s), { gv_z770_changed_rows } row(s), { gv_z770_total_changes } change(s)|.
  CREATE OBJECT go_z770_dialog
    EXPORTING
      width   = 1420
      height  = 760
      top     = 20
      left    = 20
      caption = lv_caption
    EXCEPTIONS
      cntl_error = 1
      OTHERS     = 2.
  IF sy-subrc <> 0 OR go_z770_dialog IS NOT BOUND.
    MESSAGE 'Change History window could not be created.' TYPE 'S' DISPLAY LIKE 'E'.
    RETURN.
  ENDIF.

  CREATE OBJECT go_z770_split_main
    EXPORTING
      parent  = go_z770_dialog
      rows    = 2
      columns = 1.
  go_z770_hist_cont = go_z770_split_main->get_container( row = 1 column = 1 ).
  DATA(lo_detail_parent) = go_z770_split_main->get_container( row = 2 column = 1 ).
  CALL METHOD go_z770_split_main->set_row_height
    EXPORTING id = 1 height = 54.

  CREATE OBJECT go_z770_split_diff
    EXPORTING
      parent  = lo_detail_parent
      rows    = 1
      columns = 2.
  go_z770_before_cont = go_z770_split_diff->get_container( row = 1 column = 1 ).
  go_z770_after_cont  = go_z770_split_diff->get_container( row = 1 column = 2 ).

  CREATE OBJECT go_z770_hist_grid EXPORTING i_parent = go_z770_hist_cont.
  CREATE OBJECT go_z770_before_grid EXPORTING i_parent = go_z770_before_cont.
  CREATE OBJECT go_z770_after_grid  EXPORTING i_parent = go_z770_after_cont.

  IF g_0400_grid_events IS INITIAL.
    CREATE OBJECT g_0400_grid_events.
  ENDIF.
  SET HANDLER g_0400_grid_events->on_z770_dialog_close FOR go_z770_dialog.
  SET HANDLER g_0400_grid_events->on_z770_audit_double_click FOR go_z770_hist_grid.

  PERFORM build_history_fcat CHANGING lt_hist_fcat.
  CLEAR ls_hist_layo.
  ls_hist_layo-zebra = 'X'.
  ls_hist_layo-cwidth_opt = space.
  ls_hist_layo-sel_mode = 'A'.
  ls_hist_layo-grid_title = |Change History - newest first. Double-click a change to compare Before / After.|.
  CALL METHOD go_z770_hist_grid->set_table_for_first_display
    EXPORTING is_layout = ls_hist_layo
    CHANGING it_outtab = gt_z770_audit_disp it_fieldcatalog = lt_hist_fcat.
  CALL METHOD go_z770_hist_grid->set_ready_for_input
    EXPORTING i_ready_for_input = 0.

  PERFORM build_diff_fcat CHANGING lt_diff_fcat.
  CLEAR ls_diff_layo.
  ls_diff_layo-zebra = 'X'.
  ls_diff_layo-cwidth_opt = space.
  ls_diff_layo-info_fname = 'ROW_COLOR'.
  ls_diff_layo-grid_title = 'BEFORE - Old Version'.
  CALL METHOD go_z770_before_grid->set_table_for_first_display
    EXPORTING is_layout = ls_diff_layo
    CHANGING it_outtab = gt_z770_before_disp it_fieldcatalog = lt_diff_fcat.
  CALL METHOD go_z770_before_grid->set_ready_for_input
    EXPORTING i_ready_for_input = 0.

  ls_diff_layo-grid_title = 'AFTER - New Version'.
  CALL METHOD go_z770_after_grid->set_table_for_first_display
    EXPORTING is_layout = ls_diff_layo
    CHANGING it_outtab = gt_z770_after_disp it_fieldcatalog = lt_diff_fcat.
  CALL METHOD go_z770_after_grid->set_ready_for_input
    EXPORTING i_ready_for_input = 0.

  IF gt_z770_audit_disp IS NOT INITIAL.
    PERFORM show_audit_detail USING 1.
  ENDIF.
ENDFORM.

*& Raw persisted SAP protocol is the drilldown authority

*& Purpose:
*& Do not depend on a second synthetic SAP_PROTO_PROOF row. The exact
*& CALL TRANSACTION BDC protocol is already persisted by
*& SAVE_BDC_MESSAGE_LOGS before lifecycle finalization. Drilldown must
*& read that same source of truth, scoped to SESSION + TCODE + RECORD_KEY,
*& and accept only a real SAP S-message whose persisted text contains the
*& exact SAP Object token. ENGINE/DB_PROOF/SAP_PROTO_PROOF rows are never
*& accepted as runtime SAP protocol evidence.

*& Load immutable synchronous SAP success protocol proof

*& Verify one persisted SAP S-message against the exact object

*& Show exact persisted SAP success protocol proof

*& Load exact frozen display config without requiring DB verifier

*& Exact persisted non-success SAP Object evidence

*& Generic SAP display-route resolver (no TCODE hardcoding)

*& Goal:
*& A SAP Object hotspot should open the real SAP display transaction,
*& not only a proof popup. The route is resolved from SAP repository
*& metadata and Screen Painter SPA/GPA metadata only.

*& Authority order:
*& 1) Frozen/certified DISPLAY_TCODE + PARAM_ID, when already available.
*& 2) Auto-discovery from TSTC/TSTCT + D021S-PAID:
*& candidate transaction must share the same start program as the
*& create transaction;
*& its SAP English transaction text must identify it as DISPLAY;
*& the candidate must be unique;
*& a unique Set/Get parameter ID must be proven from its start screen.
*& 3) If any step is ambiguous, fail closed and keep the exact SAP proof
*& popup. Never guess a TCODE, object field, or parameter ID.

*& Universal review-route resolver for successful SAP Objects

*& Design:
*& Never hardcode create/display transaction pairs, tables, fields, or PIDs.
*& Prefer an exact certified route if the session certificate has one.
*& Otherwise derive object PID from the exact verifier DDIC metadata OR
*& from real SPA/GPA memory / Screen Painter metadata of display candidates.
*& Discover display candidates from SAP repository text + program/package.
*& Accept only one highest-confidence route. Any tie/ambiguity fails closed.
*& Persist a successful unique route to the exact profile/version cert.

*& Fail-closed automatic SAP review navigation

*& Purpose:
*& After exact DB proof has already established business SUCCESS, a click
*& on SAP_OBJECT_ID should open the standard SAP display transaction when
*& the route can be derived uniquely from SAP repository/DDIC metadata.

*& Safety / generic rules:
*& Never hardcode a create/display TCODE pair, business table, field or PID.
*& Derive the SPA/GPA PID only from the exact frozen DB verifier field.
*& Accept only one standard DISPLAY transaction sharing the exact start
*& program with the create transaction. Ambiguity fails closed.
*& Persist only the unique route into the exact frozen session contract.
*& If no unique route exists, keep the existing certified-recording/DB
*& proof fallback. No runtime prompt asks the end user for a TCODE.

*& Exact repository semantic stem for review navigation

*& A create/display pair is never inferred from TCODE spelling. Instead,
*& compare SAP repository texts after removing only the leading lifecycle
*& verb. Example: "Create Sales Order" and "Display Sales Order" share
*& the exact stem "SALES ORDER". Any ambiguity remains blocked.

*& Repository/DDIC review resolver (generic, no TCODE pairs)

*& Why:
*& CREATE and DISPLAY transactions do not always share one TSTC start
*& program. Same-program-only discovery therefore cannot be the universal
*& rule for SAP Object navigation.

*& Authority:
*& 1) SAP Object is already DB verified before this resolver is called.
*& 2) Object SPA/GPA PID comes from the exact DDIC verifier field.
*& 3) DISPLAY candidates come from TSTC/TSTCT repository metadata.
*& 4) Candidate start dynpro must expose that exact PID in Screen Painter.
*& 5) Prefer one exact CREATE/DISPLAY semantic stem across the repository.
*& 6) If no exact semantic hit exists, allow one DISPLAY candidate in the
*& exact same TADIR package that exposes the same object PID.
*& 7) Any tie/ambiguity fails closed. No TCODE/table/field/PID mapping is
*& embedded here.

*& RS_IMPORT_DYNPRO exact interface typing (D020S)
*& Runtime dump CALL_FUNCTION_CONFLICT_TYPE was caused by passing TSTC-DYPNO
*& directly to RS_IMPORT_DYNPRO-DYNUMB, whose interface is D020S-DNUM.
*& Only technical typing is changed; object discovery/review rules are unchanged.

*& Program/subscreen PID evidence for generic review

*& A transaction's object field is not always stored on the TSTC start
*& dynpro itself. Standard applications may place it on a subscreen.
*& Therefore start-screen-only D021S-PAID evidence can reject a valid
*& DISPLAY route even though the same transaction program owns an exact
*& screen field with the DDIC-derived SPA/GPA parameter ID.

*& This routine does NOT infer a transaction pair. It is called only after
*& repository semantics have already selected a DISPLAY candidate. It then
*& scans that candidate's own dynpros and accepts only exact PID evidence.
*& No business TCODE/table/field/PID literals are embedded.

*& Open SQL host variables escaped for target ABAP
*& Resolve SAP Object PID from DISPLAY screen + SAP memory

*& This is review navigation only. It never participates in execution or
*& success proof. The DISPLAY transaction must already have been resolved as
*& one unique repository candidate by Z406_FIND_DISPLAY. From that exact
*& transaction start screen, accept a route only when Screen Painter exposes
*& exactly one nonblank Set/Get parameter ID (D021S-PAID). Any ambiguity is
*& blocked; no TCODE, business table, field, PID or object type is hardcoded.

*& keep every RS_IMPORT_DYNPRO caller interface-exact.

*& /Freeze a protocol-certified review route

*& A synchronous CT SUCCESS may intentionally have no VERIFY_TABLE/FIELD.
*& After the user double-clicks a proven SAP Object, a review route may still
*& be frozen when all of the following are exact: frozen session contract,
*& CERTIFIED runtime certificate, persisted SAP success-protocol proof, one
*& unique DISPLAY transaction, and one unique Screen Painter SPA/GPA PID.

*& Release-safe BOR real SAP object display (generic)

*& Why:
*& Repository text/TSTC guessing cannot guarantee the right display
*& transaction for every application. SAP BOR already defines the
*& generic interfaces ExistenceCheck and Display for business objects.

*& Resolution evidence:
*& release-safe BOR repository metadata
*& exact single-part object key length
*& optional exact SPA/GPA memory match for the same object
*& BOR ExistenceCheck must pass
*& exactly one highest-confidence BOR object type is accepted

*& Display:
*& SWO_CREATE + SWO_INVOKE verb 'Display'. The BOR object itself owns
*& the application-specific display implementation. No create/display
*& TCODE pair, business table, business field, or PID is hardcoded here.

*& obsolete BOR auto-discovery removed from runtime.

*& IFSAP/BOR-owned review resolver (generic, no TCODE mapping)

*& could still fall back to the DB-proof popup on releases where
*& SWO_QUERY_METHODS does not enumerate inherited IFSAP methods in the same
*& way as SWO1. That is not a valid reason to reject a BOR object type:
*& every BOR object type inherits IFSAP, whose standard methods are
*& ExistenceCheck and Display.

*& Generic authority used here:
*& 1) SAP Object already has exact DB proof (VERIFY_TABLE/FIELD).
*& 2) Discover BOR object types and their key fields dynamically.
*& 3) Exact verifier TABLE-FIELD is strongest; exact DDIC data element is
*& only a lower-confidence fallback.
*& 4) SWO_QUERY_METHODS is advisory only. A direct implementation of
*& Display/ExistenceCheck on the candidate adds confidence, but inherited
*& IFSAP methods are never rejected merely because the query omits them.
*& 5) Instantiate the exact key with SWO_CREATE.
*& 6) For an exact TABLE-FIELD key, existing DB proof is the existence
*& authority. For the weaker same-data-element fallback, BOR
*& ExistenceCheck must also succeed.
*& 7) Highest-confidence candidate must be unique.
*& 8) Invoke the standard IFSAP verb Display. The BOR implementation owns
*& the real display/navigation; no CREATE->DISPLAY TCODE pair exists here.

*& /Project frozen CREATE navigation into generic DISPLAY review

*& Problem fixed:
*& BOR Display can correctly identify and open a business object but some
*& SAP applications still have a deterministic navigation dialog before the
*& real display screen (for example a view/variant selection). Stopping on
*& that dialog is not equivalent to opening the object for review.

*& Generic authority only - no CREATE->DISPLAY pair and no business literals:
*& 1) DISPLAY TCODE + SPA/GPA PID are already repository/DDIC resolved.
*& 2) The exact frozen CREATE Script of this session is loaded.
*& 3) The DISPLAY start screen must expose exactly one field with that PID.
*& 4) After the same start dynpro in the frozen Script, find the FIRST screen
*& in the same module pool whose business inputs are deterministic STATIC
*& values only (no DYNAMIC/source-mapped business input). This is treated
*& as a navigation-selection screen, not as document data.
*& 5) Replay only: DISPLAY start screen + exact SAP Object + that one frozen
*& deterministic navigation screen. NOBIEND=X hands control back to the
*& user on the next real SAP display screen.
*& 6) If any proof is missing or BDC rejects the projection, fail closed and
*& allow the existing BOR/repository fallback. Never guess a view/TCODE.

*& Generic DISPLAY-entry action resolver

*& A CREATE and DISPLAY transaction can share the same start dynpro but use
*& different function codes to leave it. Therefore the CREATE recording's
*& first BDC_OKCODE is not authoritative for review. Resolve the DISPLAY
*& action from SAP Screen Painter metadata instead:
*& the next immutable RAW navigation dynpro is already proven structurally;
*& its D020T title is compared with pushbutton text on the DISPLAY start;
*& D021S_RES1-FUNCCODE supplies the actual application function code;
*& exactly one match is accepted. No TCODE, view, field, table or OKCODE
*& literal is coded here.

*& Minimal recorded-context review (generic, fail-closed)

*& A business object can be proven uniquely while its DISPLAY transaction
*& still owns a view/context chooser. Replaying the whole CREATE prefix is
*& too strong: CREATE may have selected many views, so later organization
*& screens describe the union of those views rather than the one screen a
*& reviewer needs first.

*& Generic rule used here:
*& 1) DISPLAY/PID are already repository + DDIC proven.
*& 2) Load the immutable RAW recording of the exact frozen Script.
*& 3) Inspect only the first RAW screen after the DISPLAY start dynpro.
*& 4) If that screen contains exactly one indexed selector family with
*& recorded non-empty selections, choose the first recorded selection.
*& This means "open the first business context used by the certified
*& CREATE recording"; it does not know any TCODE, view name, table or
*& business field.
*& 5) Use the RAW screen's own OKCODE (same technical dynpro); only if that
*& row is absent use the universal Enter command /00.
*& 6) End BDC immediately after that one selector screen with NOBIEND=X.
*& SAP therefore decides whether the next screen is detail or an extra
*& application context screen. No later CREATE-only context is guessed.

*& Ambiguous selector families fail closed to the existing full-prefix/BOR
*& fallbacks. There is no CREATE->DISPLAY map and no TCODE-specific branch.

*& Immutable RAW navigation-prefix review (generic)

*& Purpose:
*& A normalized executable Script is the correct authority for CREATE
*& execution, but it is not lossless UI evidence for a later DISPLAY flow.
*& Selection/context screens can be classified, normalized or ignored by
*& the compiler even though the immutable RAW SHDB snapshot still contains
*& the exact physical dynpro rows and literal selector state accepted by SAP.

*& Generic review contract:
*& 1) DISPLAY TCODE/PID must already be repository + DDIC resolved.
*& 2) Load the immutable RAW snapshot linked to the exact frozen Script ID.
*& 3) Start from the exact DISPLAY entry dynpro found in RAW.
*& 4) Replay every following RAW screen only until the first screen that
*& contains BDC_SUBSCR. BDC_SUBSCR is used only as a structural boundary:
*& the prefix before it is navigation/context; the subscreen container is
*& treated as business-detail territory and is never replayed.
*& 5) RAW owns physical field names, indexed selectors, cursor and OKCODE.
*& If the compiled twin of a RAW field is DYNAMIC, evaluate only that
*& exact field through APPEND_SCRIPT_STEP with the exact session staging
*& row + Mapping, so current runtime context replaces the acquisition
*& sample without inventing business semantics.
*& 6) Keep classic batch-input mode while the proven RAW prefix is consumed;
*& NOBIEND=X switches back to normal dialog only after the prefix ends.
*& Thus SAP receives its exact selector/context BDC and the user receives
*& control on the first real detail screen.

*& No CREATE->DISPLAY pair, no business table/field/view literal and no TCODE
*& branch exists here. Missing/ambiguous evidence fails closed to the older
*& repository/BOR fallbacks.

*& Compile-safe exact BDCMSGCOLL screen-context probe

*& The CREATE recording is authoritative for selector/context input, but its
*& first detail dynpro is not necessarily the DISPLAY detail dynpro. Probe the
*& already-resolved DISPLAY transaction with the proven navigation prefix and
*& intentionally stop before the next screen. SAP's own BDC runtime message
*& then exposes the actual next program/dynpro. Accept only a unique Screen
*& Painter-valid pair; no TCODE, view name, OKCODE, table or business field is
*& hardcoded.

*& Certified review-route recording, no TCODE/BOR guessing

*& Runtime rule:
*& A SUCCESS object is proof-scoped exactly as before.
*& Review navigation is NEVER inferred from create-TCODE names, TSTCT
*& wording, BOR key length, package siblings, or business hardcoding.
*& Each onboarded profile/version has one immutable review contract.
*& If DISPLAY_TCODE/PARAM_ID already exists, keep supporting it.
*& Otherwise the onboarding user records the real DISPLAY transaction
*& once with the exact proven SAP Object. The object input is replaced
*& by technical placeholder @SAP_OBJECT@ and the navigation prefix is
*& saved as a kept %BDC recording. CERT-PARAM_ID stores @R:<GROUPID>.
*& Future double-clicks replay only that certified prefix with NOBIEND=X;
*& after the BDC prefix is consumed SAP returns to normal dialog mode on
*& the real document display screen. No create/display pair is hardcoded.

*& One-time learned Review Contract from resolved DISPLAY route

*& The repository/DDIC resolver supplies only the DISPLAY transaction. When
*& SAP requires application-owned choices (views, org levels, tabs, dialogs),
*& those choices cannot be inferred universally from an object number. This
*& helper learns the exact route once from SAP GUI, persists it as profile
*& contract data, and reuses it for every future object of the same frozen
*& profile/version. No TCODE pair, view, table, field or business value is
*& coded here.

*& Historical DB verifier bootstrap from frozen session evidence

*& This is intentionally fail-closed and context-bound. It is used only when
*& an older SUCCESS row has exact persisted SAP protocol proof but the frozen
*& PENDING_TEST certificate still lacks VERIFY_TABLE/VERIFY_FIELD. The helper
*& reconstructs the same hidden trace from the exact session/group, discovers
*& one unique transparent-table verifier, freezes it into that exact contract,
*& and immediately rechecks the displayed SAP Object. No review TCODE or
*& business table/field is guessed.

*& Canonical SAP Object key for review navigation

*& Purpose:
*& The cockpit may intentionally preserve the external/display
*& representation that SAP returned (for example without leading zeroes).
*& Object proof already normalizes that value through the exact frozen
*& VERIFY_TABLE/VERIFY_FIELD DDIC type. Review navigation must use the same
*& canonical internal key when feeding SPA/GPA memory or a certified @R:
*& BDC review contract; otherwise one proven object can fail to open only
*& because its display representation differs from the DDIC key.

*& Rules:
*& no TCODE/table/field/PID hardcoding;
*& normalization authority is only the exact frozen DB verifier field;
*& the normalized key is used only for navigation, never to rewrite the
*& persisted/audited SAP_OBJECT_ID shown in the cockpit;
*& if exact DB proof exists but canonicalization cannot be reproduced,
*& navigation fails closed instead of guessing another representation.

*&=====================================================================*
*& V7 PRO - FORMS FOR ACTIVE SCREEN LIFECYCLE
*&=====================================================================*
* Screen 0350 - Mapping Profile

FORM append_exec_group
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

FORM reset_0400_selection.
  DATA lt_empty TYPE lvc_t_row.

  CLEAR gt_0400_sel_keys.
  LOOP AT gt_exec_disp ASSIGNING FIELD-SYMBOL(<ls_sel_reset>).
    CLEAR <ls_sel_reset>-selected.
  ENDLOOP.

  IF go_exec_grid IS BOUND.
    CALL METHOD go_exec_grid->set_selected_rows
      EXPORTING it_index_rows = lt_empty.
    CALL METHOD go_exec_grid->refresh_table_display.
  ENDIF.
ENDFORM.

FORM set_0500_progress
  USING iv_curr       TYPE i
        iv_total      TYPE i
        iv_elapsed_ms TYPE i.

  DATA: lv_curr        TYPE i,
        lv_total       TYPE i,
        lv_pct_disp    TYPE p LENGTH 7 DECIMALS 2,
        lv_pct_gui     TYPE i,
        lv_elapsed_sec TYPE p LENGTH 8 DECIMALS 1,
        lv_grid_title  TYPE lvc_title,
        lv_live_text   TYPE c LENGTH 120,
        lv_eta_ms      TYPE i,
        lv_eta_sec     TYPE p LENGTH 8 DECIMALS 1,
        lv_terminal    TYPE abap_bool.

  lv_total = iv_total.
  IF lv_total < 0. lv_total = 0. ENDIF.
  lv_curr = iv_curr.
  IF lv_curr < 0. lv_curr = 0. ENDIF.
  IF lv_total > 0 AND lv_curr > lv_total.
    lv_curr = lv_total.
  ENDIF.

  IF gv_exec_run_active <> abap_true AND
     ( gv_exec_run_phase CS 'Completed' OR
       gv_exec_run_phase CS 'Stopped' ).
    lv_terminal = abap_true.
  ENDIF.

  WRITE lv_curr  TO txtgv_exec_curr LEFT-JUSTIFIED.
  WRITE lv_total TO txtgv_exec_total LEFT-JUSTIFIED.

  IF lv_total > 0.
    lv_pct_disp = lv_curr.
    lv_pct_disp = lv_pct_disp * 100 / lv_total.
    IF lv_pct_disp > 100. lv_pct_disp = 100. ENDIF.
    lv_pct_gui = lv_pct_disp.
  ELSE.
    CLEAR: lv_pct_disp, lv_pct_gui.
  ENDIF.
  WRITE lv_pct_disp TO txtgv_exec_pct LEFT-JUSTIFIED.
  CONDENSE txtgv_exec_pct NO-GAPS.

  lv_elapsed_sec = iv_elapsed_ms / 1000.
  WRITE lv_elapsed_sec TO txtgv_exec_elapsed LEFT-JUSTIFIED.
  CONDENSE txtgv_exec_elapsed NO-GAPS.

  IF lv_terminal = abap_true.
    CLEAR txtgv_exec_eta.
  ELSEIF lv_total > 0 AND lv_curr >= lv_total.
    txtgv_exec_eta = '0.0'.
  ELSEIF lv_total > 0 AND lv_curr > 0 AND iv_elapsed_ms > 0.
    lv_eta_ms = ( iv_elapsed_ms * ( lv_total - lv_curr ) ) / lv_curr.
    lv_eta_sec = lv_eta_ms / 1000.
    WRITE lv_eta_sec TO txtgv_exec_eta LEFT-JUSTIFIED.
    CONDENSE txtgv_exec_eta NO-GAPS.
  ELSE.
    txtgv_exec_eta = 'n/a'.
  ENDIF.

  CONCATENATE txtgv_exec_curr '/' txtgv_exec_total
    INTO gv_exec_progress SEPARATED BY space.

  IF lv_terminal = abap_true.
    lv_grid_title = |Progress { txtgv_exec_curr }/{ txtgv_exec_total } ({ txtgv_exec_pct }%) Elapsed { txtgv_exec_elapsed } sec - { gv_exec_run_phase }|.
  ELSE.
    lv_grid_title = |Progress { txtgv_exec_curr }/{ txtgv_exec_total } ({ txtgv_exec_pct }%) Elapsed { txtgv_exec_elapsed } sec ETA { txtgv_exec_eta } sec - { gv_exec_run_phase }|.
  ENDIF.

  IF go_grid_0500 IS BOUND.
    TRY.
        CALL METHOD go_grid_0500->set_gridtitle
          EXPORTING i_gridtitle = lv_grid_title.
        CALL METHOD cl_gui_cfw=>flush.
      CATCH cx_root.
    ENDTRY.
  ENDIF.

  IF gv_exec_run_active = abap_true.
    lv_live_text = |Processing { txtgv_exec_curr }/{ txtgv_exec_total } ({ txtgv_exec_pct }%) - { gv_exec_run_phase }|.
  ELSE.
    lv_live_text = |{ gv_exec_run_phase }: { txtgv_exec_curr }/{ txtgv_exec_total } ({ txtgv_exec_pct }%)|.
  ENDIF.
  CALL FUNCTION 'SAPGUI_PROGRESS_INDICATOR'
    EXPORTING
      percentage = lv_pct_gui
      text       = lv_live_text.

  PERFORM update_0500_dynpro_vals.
ENDFORM.

FORM update_0500_dynpro_vals.
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

FORM sync_0500_progress_q.
  DATA lv_total TYPE i.
  DATA lv_done  TYPE i.
  DATA lv_ms    TYPE i.

  lv_total = lines( gt_exec_disp ).
  lv_done  = 0.

  LOOP AT gt_exec_disp ASSIGNING FIELD-SYMBOL(<ls_q_prog>).
    CASE <ls_q_prog>-run_status.
      WHEN gc_st_success OR gc_st_error OR gc_st_warning OR gc_st_processed
        OR gc_st_skipped OR gc_st_partial.
        lv_done = lv_done + 1.
      WHEN gc_st_sm35q OR 'SM35QUEUE'.
 "queue dispatch is shown in GV_EXEC_RUN_PHASE/Queued count,
 "but never contributes to business completion. Only terminal exact
 "SUCCESS/ERROR/WARNING proof advances the main progress counter.
        CONTINUE.
    ENDCASE.
  ENDLOOP.

  IF lv_total = 0 AND gt_exec_scope_0500 IS NOT INITIAL.
    lv_total = lines( gt_exec_scope_0500 ).
  ENDIF.

  lv_ms = gv_exec_elapsed.
  PERFORM set_0500_progress USING lv_done lv_total lv_ms.
ENDFORM.

FORM sapgui_progress
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

FORM flush_0500_queue.
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

FORM force_0500_repaint.
 "Do not LEAVE SCREEN here. Leaving screen after a run makes old SAP GUI
 "docking containers survive for one roundtrip and creates duplicated ALV
 "queues. A flush is enough; normal PAI/PBO will repaint the dynpro fields.
  IF go_grid_0500 IS BOUND.
    PERFORM flush_0500_queue.
  ENDIF.
  CALL METHOD cl_gui_cfw=>flush.
ENDFORM.

FORM 0500_profile_text CHANGING cv_text TYPE string.
  DATA lv_mode  TYPE c LENGTH 1.
  DATA lv_upd   TYPE c LENGTH 1.
  DATA lv_bsize TYPE i.
  DATA lv_mode_text TYPE string.
  DATA lv_upd_text  TYPE string.
  DATA lv_engine       TYPE string.
  DATA lv_scope        TYPE string.
  DATA lv_sm35_profile TYPE string.
  DATA lv_runtime_ok  TYPE abap_bool.
  DATA lv_runtime_msg TYPE string.

  PERFORM get_runtime_options
    CHANGING lv_mode lv_upd lv_bsize lv_runtime_ok lv_runtime_msg.
  IF lv_runtime_ok <> abap_true.
    cv_text = |Runtime policy invalid: { lv_runtime_msg }|.
    RETURN.
  ENDIF.

  IF p_bdc_mode = gc_mode_batch.
    CLEAR: lv_mode, lv_upd.
  ENDIF.

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

  PERFORM sm35_profile_label
    USING    lv_mode lv_upd
    CHANGING lv_sm35_profile.

  IF p_bdc_mode = gc_mode_batch.
    lv_engine = 'SM35 batch input'.
  ELSE.
    lv_engine = 'CALL TRANSACTION'.
  ENDIF.

  lv_scope = gv_exec_scope_text.
  IF lv_scope IS INITIAL.
    lv_scope = 'Current READY queue'.
  ENDIF.

  IF p_bdc_mode = gc_mode_batch.
    cv_text = |{ lv_scope } { lv_engine } - BDC Mode/Update radios are disabled and ignored. Run Batch Session only creates a real SM35 session; process it in SM35, then Refresh for protocol/object proof.|.
  ELSE.
    cv_text = |{ lv_scope } | &&
              |{ lv_engine } | &&
              |CTU { lv_mode_text } / Update { lv_upd_text } | &&
              |SM35 { lv_sm35_profile }.|.
  ENDIF.
ENDFORM.

FORM build_0500_queue.
  DATA lt_scope TYPE ty_t_staging_alv.
  DATA lt_all   TYPE ty_t_exec_disp.
  DATA ls_scope TYPE ty_staging_alv.
  DATA ls_exec  TYPE ty_exec_disp.
  DATA lv_profile TYPE string.
  DATA lv_scope_key TYPE char40.
  DATA lv_unit_raw_f TYPE string.

  FIELD-SYMBOLS <ls_scope_exec> TYPE ty_exec_disp.

  PERFORM 0500_profile_text CHANGING lv_profile.

 "During an active 0500 run, the visible queue must come from the
 "current runtime snapshot only. Rebuilding from DB here caused old group keys
 "from previous runs to reappear and made the bottom ALV flash/blank.
  IF gt_exec_qstate IS NOT INITIAL AND
     ( gv_exec_run_active = abap_true OR
       gv_exec_mon_kind IS NOT INITIAL OR
       gv_exec_scope_ready = abap_true ).
    PERFORM build_0500_from_q.
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

 "If 0400 sent a valid selected/run scope but the DB cockpit
 "cannot be rebuilt yet, never paint a blank 0500 queue. Build a
 "minimal group cockpit directly from the frozen scope; later refresh
 "overlays DB/result proof as soon as it exists.
    IF gt_exec_disp IS INITIAL AND lt_scope IS NOT INITIAL.
      LOOP AT lt_scope INTO ls_scope.
        CLEAR lv_scope_key.
        lv_scope_key = ls_scope-record_key.
        IF lv_scope_key IS INITIAL AND ls_scope-row_index IS NOT INITIAL.
          WRITE ls_scope-row_index TO lv_scope_key LEFT-JUSTIFIED.
          CONDENSE lv_scope_key NO-GAPS.
        ENDIF.

        READ TABLE gt_exec_disp ASSIGNING <ls_scope_exec>
          WITH KEY session_id = ls_scope-session_id
                   group_key  = lv_scope_key
                   tcode      = ls_scope-tcode.
        IF sy-subrc <> 0.
          CLEAR ls_exec.
          PERFORM batch_prefix_from_sid
            USING ls_scope-session_id
            CHANGING ls_exec-batch_key.

          CLEAR lv_unit_raw_f.
          SELECT SINGLE file_name FROM zbdc_file_lg_bup
            WHERE session_id = @ls_scope-session_id
            INTO @lv_unit_raw_f.
          IF lv_unit_raw_f IS INITIAL.
            lv_unit_raw_f = ls_scope-session_id.
          ENDIF.
          PERFORM p1_split_unit_name
            USING lv_unit_raw_f
            CHANGING ls_exec-source_file ls_exec-sheet_name.

          ls_exec-session_id = ls_scope-session_id.
          ls_exec-group_key  = lv_scope_key.
          ls_exec-tcode      = ls_scope-tcode.
          IF ls_exec-tcode IS INITIAL.
            ls_exec-tcode = p_transaction.
          ENDIF.
          APPEND ls_exec TO gt_exec_disp.
          READ TABLE gt_exec_disp ASSIGNING <ls_scope_exec> INDEX lines( gt_exec_disp ).
        ENDIF.

        IF <ls_scope_exec> IS ASSIGNED.
          <ls_scope_exec>-item_count = <ls_scope_exec>-item_count + 1.
          CASE ls_scope-status.
            WHEN gc_st_success.
              <ls_scope_exec>-success_count = <ls_scope_exec>-success_count + 1.
            WHEN gc_st_error.
              <ls_scope_exec>-error_count = <ls_scope_exec>-error_count + 1.
              IF <ls_scope_exec>-message IS INITIAL.
                <ls_scope_exec>-message = ls_scope-error_msg.
              ENDIF.
            WHEN gc_st_warning.
              <ls_scope_exec>-warning_count = <ls_scope_exec>-warning_count + 1.
            WHEN gc_st_sm35q OR 'SM35QUEUE' OR 'SM35RUN'.
              <ls_scope_exec>-sm35_count = <ls_scope_exec>-sm35_count + 1.
              IF <ls_scope_exec>-message IS INITIAL.
                <ls_scope_exec>-message = ls_scope-error_msg.
              ENDIF.
            WHEN OTHERS.
              <ls_scope_exec>-ready_count = <ls_scope_exec>-ready_count + 1.
          ENDCASE.
          UNASSIGN <ls_scope_exec>.
        ENDIF.
      ENDLOOP.
    ENDIF.
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
        <ls_exec_0500>-action_hint = 'Reload the execution scope before Execute'.
        <ls_exec_0500>-message = 'Queue stop requested. Running BDC cannot be interrupted mid-screen; stop is applied after the active group returns.'.
      ELSEIF gv_exec_run_active = abap_true AND gv_exec_mon_kind = gc_mon_sm35.
        <ls_exec_0500>-icon        = '@09@'.
        <ls_exec_0500>-msg_type    = 'I'.
        <ls_exec_0500>-run_status  = gc_st_sm35q.
        <ls_exec_0500>-health_text = 'Creating SM35 batch-input session'.
        <ls_exec_0500>-action_hint = 'Wait for BDC_INSERT / BDC_CLOSE_GROUP'.
        <ls_exec_0500>-message     = |SM35 session is being created; BDC Mode/Update are ignored.|.
      ELSE.
        IF chkp_background = 'X'.
          <ls_exec_0500>-health_text = 'Creating SM35 batch session'.
          <ls_exec_0500>-action_hint = 'Wait for BDC_INSERT / BDC_CLOSE_GROUP'.
        ELSE.
          IF p_bdc_mode = gc_mode_batch.
            <ls_exec_0500>-health_text = 'Ready to create SM35 session'.
            <ls_exec_0500>-action_hint = 'Create SM35 Session'.
          ELSE.
            <ls_exec_0500>-health_text = 'Ready for Call Transaction execution'.
            <ls_exec_0500>-action_hint = 'Execute Now'.
          ENDIF.
        ENDIF.
        IF <ls_exec_0500>-message IS INITIAL OR <ls_exec_0500>-message CS 'Scope:'.
          <ls_exec_0500>-message = lv_profile.
        ENDIF.
      ENDIF.
    ENDIF.
  ENDLOOP.

 "Final overlay from the exact selected-run queue. It is applied after
 "the DB projection so an active render cycle cannot repaint queue state
 "back to READY.
  PERFORM exec_q_overlay.

 "BISM queue overlay must never repaint queued rows as SM35RUN.
 "True Batch Input stops at BDC_CLOSE_GROUP; explicit SM35 processing and
 "Refresh/Monitor later reconcile terminal proof.
  IF gv_exec_run_active = abap_true AND gv_exec_mon_kind = gc_mon_sm35.
    LOOP AT gt_exec_disp ASSIGNING <ls_exec_0500>.
      READ TABLE gt_sm35_mon_process TRANSPORTING NO FIELDS
        WITH KEY session_id = <ls_exec_0500>-session_id
                 record_key = <ls_exec_0500>-group_key
                 tcode      = <ls_exec_0500>-tcode.
      IF sy-subrc = 0.
 "never repaint a terminal/proof-positive row back to yellow
 "while the BISM monitor is still active in the same PBO cycle.
        IF <ls_exec_0500>-run_status = gc_st_success OR
           <ls_exec_0500>-run_status = gc_st_error OR
           <ls_exec_0500>-run_status = gc_st_warning OR
           <ls_exec_0500>-run_status = gc_st_processed OR
           <ls_exec_0500>-run_status = gc_st_skipped OR
           <ls_exec_0500>-run_status = gc_st_partial OR
           <ls_exec_0500>-sap_object_id IS NOT INITIAL.
          CONTINUE.
        ENDIF.
        <ls_exec_0500>-icon     = '@09@'.
        <ls_exec_0500>-msg_type = 'I'.
        IF gv_sm35_job_finished = abap_true.
          <ls_exec_0500>-run_status  = gc_st_verifying.
          <ls_exec_0500>-health_text = 'SM35 processing returned; reconciling proof'.
          <ls_exec_0500>-action_hint = 'Wait for SM35 log/object proof; do not duplicate run'.
          IF gv_sm35_last_qstate IS INITIAL.
            <ls_exec_0500>-message =
              |SM35 processing returned for { gv_sm35_mon_group }; APQI state blank/not found. Reconciling proof.|.
          ELSE.
            <ls_exec_0500>-message =
              |SM35 processing returned for { gv_sm35_mon_group }; APQI state { gv_sm35_last_qstate }. Reconciling proof.|.
          ENDIF.
        ELSE.
          <ls_exec_0500>-run_status  = gc_st_sm35q.
          <ls_exec_0500>-health_text = 'SM35 session queued'.
          <ls_exec_0500>-action_hint = 'Process the created session in SM35; return to the cockpit for automatic reconciliation'.
          <ls_exec_0500>-message =
            |SM35 session { gv_sm35_mon_group } is queued/processing in standard SM35. Return to the cockpit after processing; exact-QID reconciliation is automatic.|.
        ENDIF.
      ENDIF.
    ENDLOOP.
  ENDIF.
ENDFORM.

*& Final 0500 visible queue guard after all overlays

FORM final_visible_queue_guard.
  FIELD-SYMBOLS <ls_exec> TYPE ty_exec_disp.

  LOOP AT gt_exec_disp ASSIGNING <ls_exec>.
    PERFORM final_exec_display_guard CHANGING <ls_exec>.
  ENDLOOP.
ENDFORM.


*&---------------------------------------------------------------------*
*& Screen 0500 - persisted execution-attempt history
*&---------------------------------------------------------------------*

FORM free_0500_attempt_history.
  IF go_attempt_0500_grid IS BOUND.
    TRY.
        go_attempt_0500_grid->free( ).
      CATCH cx_root.
    ENDTRY.
    FREE go_attempt_0500_grid.
  ENDIF.

  IF go_attempt_0500_dlg IS BOUND.
    TRY.
        go_attempt_0500_dlg->free( ).
      CATCH cx_root.
    ENDTRY.
    FREE go_attempt_0500_dlg.
  ENDIF.

  REFRESH gt_attempt_0500_disp.
  TRY.
      cl_gui_cfw=>flush( ).
    CATCH cx_root.
  ENDTRY.
ENDFORM.

FORM derive_attempt_status_0500
  USING    pt_result TYPE ty_t_result_726
  CHANGING cv_status TYPE char20.

  DATA: lt_result TYPE ty_t_result_726,
        ls_res    TYPE zbdc_result_bup.

  CLEAR cv_status.
  lt_result = pt_result.
  SORT lt_result BY created_at DESCENDING step DESCENDING.

  "Newest persisted lifecycle-bearing evidence wins inside one attempt.
  "Informational/result-detail rows are skipped; they never invent outcome.
  LOOP AT lt_result INTO ls_res.
    IF ls_res-exec_status = gc_st_success OR
       ls_res-exec_status = 'SUCCESS'.
      cv_status = 'SUCCESS'.
      RETURN.
    ELSEIF ls_res-exec_status = gc_st_error OR
           ls_res-exec_status = 'ERROR' OR
           ls_res-msg_type = 'E' OR
           ls_res-msg_type = 'A' OR
           ls_res-msg_type = 'X'.
      cv_status = 'ERROR'.
      RETURN.
    ELSEIF ls_res-exec_status = gc_st_warning OR
           ls_res-exec_status = 'WARNING'.
      cv_status = 'WARNING'.
      RETURN.
    ELSEIF ls_res-exec_status = gc_st_partial OR
           ls_res-exec_status = 'PARTIAL'.
      cv_status = 'PARTIAL'.
      RETURN.
    ELSEIF ls_res-exec_status = gc_st_processed OR
           ls_res-exec_status = 'PROCESSED'.
      cv_status = 'PROCESSED'.
      RETURN.
    ELSEIF ls_res-exec_status = gc_st_sm35q OR
           ls_res-exec_status = 'SM35QUEUE' OR
           ls_res-exec_status = 'QUEUED_SM35' OR
           ls_res-exec_status = 'SM35RUN'.
      cv_status = 'SM35 QUEUED'.
      RETURN.
    ELSEIF ls_res-exec_status = gc_st_processing OR
           ls_res-exec_status = 'PROCESSING' OR
           ls_res-exec_status = 'RUNNING'.
      cv_status = 'RUNNING'.
      RETURN.
    ENDIF.
  ENDLOOP.

  cv_status = 'EVIDENCE ONLY'.
ENDFORM.

FORM pick_attempt_message_0500
  USING    pt_result TYPE ty_t_result_726
           iv_status TYPE char20
  CHANGING cv_message TYPE char255.

  DATA: lt_result TYPE ty_t_result_726,
        ls_res    TYPE zbdc_result_bup,
        lv_admin  TYPE abap_bool.

  CLEAR cv_message.
  lt_result = pt_result.
  SORT lt_result BY created_at DESCENDING step DESCENDING.

  CASE iv_status.
    WHEN 'SUCCESS'.
      "Prefer the exact application S-message. Standard SM35 controller
      "success rows remain evidence but are not presented as business result.
      LOOP AT lt_result INTO ls_res.
        IF ls_res-msg_type <> 'S' OR ls_res-message IS INITIAL.
          CONTINUE.
        ENDIF.
        CLEAR lv_admin.
        PERFORM is_sm35_admin_s USING ls_res CHANGING lv_admin.
        IF lv_admin = abap_true OR ls_res-exec_status = 'SM35_DIAG'.
          CONTINUE.
        ENDIF.
        cv_message = ls_res-message.
        RETURN.
      ENDLOOP.

      LOOP AT lt_result INTO ls_res.
        IF ( ls_res-exec_status = gc_st_success OR
             ls_res-exec_status = 'SUCCESS' ) AND
           ls_res-message IS NOT INITIAL.
          cv_message = ls_res-message.
          RETURN.
        ENDIF.
      ENDLOOP.

    WHEN 'ERROR'.
      LOOP AT lt_result INTO ls_res.
        IF ( ls_res-exec_status = gc_st_error OR
             ls_res-exec_status = 'ERROR' OR
             ls_res-msg_type = 'E' OR
             ls_res-msg_type = 'A' OR
             ls_res-msg_type = 'X' ) AND
           ls_res-message IS NOT INITIAL.
          cv_message = ls_res-message.
          RETURN.
        ENDIF.
      ENDLOOP.

    WHEN 'WARNING'.
      LOOP AT lt_result INTO ls_res.
        IF ( ls_res-exec_status = gc_st_warning OR
             ls_res-exec_status = 'WARNING' OR
             ls_res-msg_type = 'W' ) AND
           ls_res-message IS NOT INITIAL.
          cv_message = ls_res-message.
          RETURN.
        ENDIF.
      ENDLOOP.

    WHEN OTHERS.
  ENDCASE.

  "Fail-safe presentation fallback: latest persisted non-empty evidence text.
  LOOP AT lt_result INTO ls_res.
    IF ls_res-message IS NOT INITIAL.
      cv_message = ls_res-message.
      RETURN.
    ENDIF.
  ENDLOOP.

  cv_message = 'No persisted result message for this attempt.'.
ENDFORM.

FORM show_0500_attempt_history
  USING iv_index TYPE i.

  TYPES ty_t_attempt_no_0500 TYPE SORTED TABLE OF zbdc_result_bup-attempt_no
    WITH UNIQUE KEY table_line.
  TYPES ty_t_rowidx_0500 TYPE SORTED TABLE OF zbdc_staging_bup-row_index
    WITH UNIQUE KEY table_line.

  DATA: ls_exec       TYPE ty_exec_disp,
        lt_session_res TYPE ty_t_result_726,
        lt_group_res  TYPE ty_t_result_726,
        lt_one        TYPE ty_t_result_726,
        lt_attempts   TYPE ty_t_attempt_no_0500,
        lt_rowidx     TYPE ty_t_rowidx_0500,
        ls_res        TYPE zbdc_result_bup,
        ls_disp       TYPE ty_attempt_0500_disp,
        lv_attempt    TYPE zbdc_result_bup-attempt_no,
        lv_match      TYPE abap_bool,
        lv_min_at     TYPE zbdc_result_bup-created_at,
        lv_max_at     TYPE zbdc_result_bup-created_at,
        lv_caption    TYPE c LENGTH 120,
        lt_fcat       TYPE lvc_t_fcat,
        ls_fcat       TYPE lvc_s_fcat,
        ls_layo       TYPE lvc_s_layo.

  READ TABLE gt_exec_disp INTO ls_exec INDEX iv_index.
  IF sy-subrc <> 0 OR
     ls_exec-session_id IS INITIAL OR
     ls_exec-group_key IS INITIAL.
    MESSAGE 'The selected execution row is no longer available.' TYPE 'S' DISPLAY LIKE 'E'.
    RETURN.
  ENDIF.

  PERFORM free_0500_attempt_history.

  SELECT row_index
    FROM zbdc_staging_bup
    INTO TABLE @lt_rowidx
    WHERE session_id = @ls_exec-session_id
      AND record_key = @ls_exec-group_key.

  SELECT *
    FROM zbdc_result_bup
    INTO TABLE @lt_session_res
    WHERE session_id = @ls_exec-session_id.

  LOOP AT lt_session_res INTO ls_res.
    IF ls_res-attempt_no IS INITIAL OR ls_res-attempt_no <= 0.
      CONTINUE.
    ENDIF.

    CLEAR lv_match.
    IF ls_res-record_key = ls_exec-group_key.
      lv_match = abap_true.
    ELSEIF ls_res-record_key IS INITIAL AND
           ls_res-row_index IS NOT INITIAL.
      READ TABLE lt_rowidx TRANSPORTING NO FIELDS
        WITH TABLE KEY table_line = ls_res-row_index.
      IF sy-subrc = 0.
        lv_match = abap_true.
      ENDIF.
    ENDIF.

    IF lv_match <> abap_true.
      CONTINUE.
    ENDIF.

    APPEND ls_res TO lt_group_res.
    INSERT ls_res-attempt_no INTO TABLE lt_attempts.
  ENDLOOP.

  IF lt_attempts IS INITIAL.
    MESSAGE |No persisted execution attempt exists for { ls_exec-group_key }. The next real CT/BISM run will create Attempt 1.| TYPE 'S' DISPLAY LIKE 'I'.
    RETURN.
  ENDIF.

  REFRESH gt_attempt_0500_disp.

  LOOP AT lt_attempts INTO lv_attempt.
    REFRESH lt_one.
    CLEAR: ls_disp, lv_min_at, lv_max_at.

    LOOP AT lt_group_res INTO ls_res WHERE attempt_no = lv_attempt.
      APPEND ls_res TO lt_one.
      IF ls_res-created_at IS NOT INITIAL.
        IF lv_min_at IS INITIAL OR ls_res-created_at < lv_min_at.
          lv_min_at = ls_res-created_at.
        ENDIF.
        IF lv_max_at IS INITIAL OR ls_res-created_at > lv_max_at.
          lv_max_at = ls_res-created_at.
        ENDIF.
      ENDIF.
    ENDLOOP.

    IF lt_one IS INITIAL.
      CONTINUE.
    ENDIF.

    ls_disp-attempt = lv_attempt.
    SORT lt_one BY created_at DESCENDING step DESCENDING.
    PERFORM resolve_executor USING lt_one CHANGING ls_disp-executor.
    IF ls_disp-executor = 'UNKNOWN'.
      ls_disp-executor = '-'.
    ENDIF.

    PERFORM derive_attempt_status_0500
      USING lt_one CHANGING ls_disp-status.
    PERFORM format_result_time
      USING lv_min_at CHANGING ls_disp-started_at.

    IF ls_disp-status = 'SUCCESS' OR
       ls_disp-status = 'ERROR' OR
       ls_disp-status = 'WARNING' OR
       ls_disp-status = 'PARTIAL' OR
       ls_disp-status = 'PROCESSED'.
      PERFORM format_result_time
        USING lv_max_at CHANGING ls_disp-finished_at.
    ELSE.
      ls_disp-finished_at = '-'.
    ENDIF.

    PERFORM pick_attempt_message_0500
      USING lt_one ls_disp-status
      CHANGING ls_disp-result.

    APPEND ls_disp TO gt_attempt_0500_disp.
  ENDLOOP.

  SORT gt_attempt_0500_disp BY attempt ASCENDING.

  lv_caption = |Execution Attempts - { ls_exec-group_key } - Current: { ls_exec-execution }|.
  CREATE OBJECT go_attempt_0500_dlg
    EXPORTING
      width   = 1320
      height  = 420
      top     = 70
      left    = 70
      caption = lv_caption
    EXCEPTIONS
      cntl_error = 1
      OTHERS     = 2.
  IF sy-subrc <> 0 OR go_attempt_0500_dlg IS NOT BOUND.
    MESSAGE 'Execution Attempt History window could not be created.' TYPE 'S' DISPLAY LIKE 'E'.
    RETURN.
  ENDIF.

  CREATE OBJECT go_attempt_0500_grid
    EXPORTING i_parent = go_attempt_0500_dlg.

  IF g_0500_grid_events IS INITIAL.
    CREATE OBJECT g_0500_grid_events.
  ENDIF.
  SET HANDLER g_0500_grid_events->on_0500_attempt_close FOR go_attempt_0500_dlg.

  DEFINE add_attempt_col.
    CLEAR ls_fcat.
    ls_fcat-fieldname = &1.
    ls_fcat-coltext   = &2.
    ls_fcat-scrtext_l = &2.
    ls_fcat-scrtext_m = &2.
    ls_fcat-scrtext_s = &2.
    ls_fcat-outputlen = &3.
    APPEND ls_fcat TO lt_fcat.
  END-OF-DEFINITION.

  add_attempt_col 'ATTEMPT'     'Attempt'   8.
  add_attempt_col 'EXECUTOR'    'Executor' 10.
  add_attempt_col 'STATUS'      'Status'   14.
  add_attempt_col 'STARTED_AT'  'First Evidence' 19.
  add_attempt_col 'FINISHED_AT' 'Last Evidence'  19.
  add_attempt_col 'RESULT'      'Result / Exact Evidence Summary' 80.

  CLEAR ls_layo.
  ls_layo-zebra      = 'X'.
  ls_layo-cwidth_opt = space.
  ls_layo-sel_mode   = 'A'.
  ls_layo-grid_title = |Persisted execution history for { ls_exec-group_key }. READY preview does not create an attempt.|.

  CALL METHOD go_attempt_0500_grid->set_table_for_first_display
    EXPORTING is_layout = ls_layo
    CHANGING it_outtab = gt_attempt_0500_disp
             it_fieldcatalog = lt_fcat.
  CALL METHOD go_attempt_0500_grid->set_ready_for_input
    EXPORTING i_ready_for_input = 0.

  TRY.
      cl_gui_cfw=>flush( ).
    CATCH cx_root.
  ENDTRY.
ENDFORM.

FORM display_0500_queue.
  DATA lt_fcat   TYPE lvc_t_fcat.
  DATA ls_layo   TYPE lvc_s_layo.
  DATA ls_stable TYPE lvc_s_stbl.
  DATA lv_0500_mode TYPE c LENGTH 1.
  DATA lv_0500_upd  TYPE c LENGTH 1.
  DATA lv_0500_bsz  TYPE i.
  DATA lv_ratio     TYPE i.
  DATA lv_runtime_ok  TYPE abap_bool.
  DATA lv_runtime_msg TYPE string.

  PERFORM get_runtime_options
    CHANGING lv_0500_mode lv_0500_upd lv_0500_bsz
             lv_runtime_ok lv_runtime_msg.
  IF lv_runtime_ok <> abap_true.
    CLEAR lv_0500_mode.
  ENDIF.
  IF p_bdc_mode = gc_mode_batch.
    lv_0500_mode = 'N'.
  ENDIF.
  IF lv_0500_mode = 'A'.
 "All-screens mode uses a true full-client ALV parent instead of a
 "docking container. Therefore there is no draggable splitter and the old
 "0500 progress block is completely covered. The transaction screens
 "are the detailed live execution UI for mode A.
    lv_ratio = 100.
  ELSE.
 "N/E modes keep the 0500 progress header visible above the queue.
    lv_ratio = 45.
  ENDIF.

  IF go_grid_0500 IS BOUND AND gv_0500_layout_mode <> lv_0500_mode.
    PERFORM free_0500_queue.
  ENDIF.

  PERFORM build_0500_queue.
  PERFORM final_visible_queue_guard.
  PERFORM sync_0500_progress_q.
  PERFORM build_exec_fieldcat CHANGING lt_fcat.

  LOOP AT lt_fcat ASSIGNING FIELD-SYMBOL(<ls_fcat_0500>).
    CASE <ls_fcat_0500>-fieldname.
      WHEN 'BATCH_KEY' OR 'SESSION_ID'.
        <ls_fcat_0500>-no_out = space.
      WHEN 'EXECUTION'.
        <ls_fcat_0500>-no_out  = space.
        <ls_fcat_0500>-hotspot = 'X'.
        <ls_fcat_0500>-outputlen = 24.
      WHEN 'SELECTED' OR 'DRILL_TCODE' OR 'MSG_TYPE' OR 'READY_COUNT' OR 'SUCCESS_COUNT'
        OR 'ERROR_COUNT' OR 'WARNING_COUNT' OR 'SM35_COUNT'.
        <ls_fcat_0500>-no_out = 'X'.
    ENDCASE.
  ENDLOOP.

  CLEAR ls_layo.
  ls_layo-ctab_fname = 'CELL_COLORS'.
  ls_layo-cwidth_opt = space.
  ls_layo-sel_mode   = 'A'.
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
    SET HANDLER g_0500_grid_events->on_0500_toolbar FOR go_grid_0500.
    SET HANDLER g_0500_grid_events->on_0500_user_command FOR go_grid_0500.
    SET HANDLER g_0500_grid_events->on_0500_hotspot_click FOR go_grid_0500.

    CALL METHOD go_grid_0500->set_table_for_first_display
      EXPORTING
        is_layout       = ls_layo
      CHANGING
        it_outtab       = gt_exec_disp
        it_fieldcatalog = lt_fcat.

    CALL METHOD go_grid_0500->set_toolbar_interactive.
    TRY.
        CALL METHOD cl_gui_cfw=>flush.
      CATCH cx_root.
    ENDTRY.
  ELSE.
    CALL METHOD go_grid_0500->refresh_table_display
      EXPORTING is_stable = ls_stable.
    TRY.
        CALL METHOD cl_gui_cfw=>flush.
      CATCH cx_root.
    ENDTRY.
  ENDIF.
ENDFORM.

FORM free_0500_queue.
  PERFORM free_0500_attempt_history.

 "A plain FREE of the ABAP reference is not enough for a control whose parent
 "is CL_GUI_CONTAINER=>SCREEN0. Explicitly destroy the frontend control first,
 "flush the CFW queue, and only then references/navigation state.
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

*& Capture the exact Result Dashboard scope.
*& 0400: only rows explicitly selected in the outer cockpit are included.
*& 0500: reuse the exact frozen execution/monitor scope already passed in.
*& There is deliberately no silent ALL-session fallback.

FORM prepare_dash_scope
  CHANGING cv_count   TYPE i
           cv_ok      TYPE abap_bool
           cv_message TYPE string.

  DATA: ls_exec    TYPE ty_exec_disp,
        ls_scope   TYPE ty_staging_alv,
        ls_key     TYPE ty_0400_sel_key,
        lv_session TYPE zbdc_staging_bup-session_id,
        lv_scope_invalid TYPE abap_bool.

  CLEAR: cv_count, cv_ok, cv_message, lv_scope_invalid,
         gv_dash_scope_count_826,
         gv_dash_scope_source_826,
         gv_dash_run_mode_826.
  REFRESH gt_dash_scope_826.

  IF sy-dynnr = '0500'.
    IF gt_exec_scope_0500 IS INITIAL.
      cv_message = 'No exact execution scope is available for Result Dashboard.'.
      RETURN.
    ENDIF.

    LOOP AT gt_exec_scope_0500 INTO ls_scope.
      CLEAR ls_key.
      ls_key-session_id = ls_scope-session_id.
      ls_key-tcode      = ls_scope-tcode.
      IF ls_scope-record_key IS NOT INITIAL.
        ls_key-group_key = ls_scope-record_key.
      ELSE.
        ls_key-group_key = |{ ls_scope-row_index }|.
      ENDIF.
      IF ls_key-session_id IS INITIAL OR ls_key-group_key IS INITIAL.
        CONTINUE.
      ENDIF.
      INSERT ls_key INTO TABLE gt_dash_scope_826.
    ENDLOOP.

    gv_dash_scope_source_826 = 'EXECUTION_SCOPE'.
    CASE gv_exec_scope_0500.
      WHEN 'ALL'.
        gv_dash_run_mode_826 = 'Run All'.
      WHEN 'SELECTED'.
        gv_dash_run_mode_826 = 'Run Selected'.
      WHEN 'MONITOR'.
        gv_dash_run_mode_826 = 'Selected Monitor'.
      WHEN OTHERS.
        gv_dash_run_mode_826 = 'Selected Scope'.
    ENDCASE.

  ELSEIF sy-dynnr = '0400'.
 "Result Dashboard on the outer Staging Area Data Review is a
 "session overview. It must show ALL Business Groups currently belonging
 "to the exact 0400 session and must never require row selection.
    IF gt_exec_disp IS INITIAL.
      IF gt_staging_alv IS INITIAL AND gt_staging IS NOT INITIAL.
        PERFORM prepare_alv_0400.
      ENDIF.
      PERFORM build_exec_cockpit.
    ENDIF.

    lv_session = txtp_session_id.
    CONDENSE lv_session.
    IF lv_session IS INITIAL.
      lv_session = txtp_sess.
      CONDENSE lv_session.
    ENDIF.

 "If the screen context has not populated the session display field yet,
 "derive it only from the currently rendered cockpit data. Never elect a
 "different session from unrelated history/result tables.
    IF lv_session IS INITIAL.
      READ TABLE gt_exec_disp INTO ls_exec INDEX 1.
      IF sy-subrc = 0.
        lv_session = ls_exec-session_id.
      ENDIF.
    ENDIF.

    LOOP AT gt_exec_disp INTO ls_exec.
      IF ls_exec-session_id IS INITIAL OR ls_exec-group_key IS INITIAL.
        CONTINUE.
      ENDIF.
      IF lv_session IS NOT INITIAL AND ls_exec-session_id <> lv_session.
        CONTINUE.
      ENDIF.
      CLEAR ls_key.
      ls_key-session_id = ls_exec-session_id.
      ls_key-group_key  = ls_exec-group_key.
      ls_key-tcode      = ls_exec-tcode.
      INSERT ls_key INTO TABLE gt_dash_scope_826.
    ENDLOOP.

 "Defensive fallback for an initialized staging projection whose cockpit
 "projection has no rows yet. Still exact-session and still ALL groups.
    IF gt_dash_scope_826 IS INITIAL AND gt_staging_alv IS NOT INITIAL.
      LOOP AT gt_staging_alv INTO ls_scope.
        IF ls_scope-session_id IS INITIAL.
          CONTINUE.
        ENDIF.
        IF lv_session IS INITIAL.
          lv_session = ls_scope-session_id.
        ENDIF.
        IF ls_scope-session_id <> lv_session.
          CONTINUE.
        ENDIF.
        CLEAR ls_key.
        ls_key-session_id = ls_scope-session_id.
        ls_key-tcode      = ls_scope-tcode.
        IF ls_scope-record_key IS NOT INITIAL.
          ls_key-group_key = ls_scope-record_key.
        ELSE.
          ls_key-group_key = |{ ls_scope-row_index }|.
        ENDIF.
        IF ls_key-group_key IS NOT INITIAL.
          INSERT ls_key INTO TABLE gt_dash_scope_826.
        ENDIF.
      ENDLOOP.
    ENDIF.

    IF gt_dash_scope_826 IS INITIAL.
      cv_message = 'No Business Groups are available in the current session for Result Dashboard.'.
      RETURN.
    ENDIF.

    gv_dash_scope_source_826 = 'SESSION_ALL'.
    gv_dash_run_mode_826     = 'All Groups'.

  ELSEIF gt_exec_scope_0500 IS NOT INITIAL.
    LOOP AT gt_exec_scope_0500 INTO ls_scope.
      CLEAR ls_key.
      ls_key-session_id = ls_scope-session_id.
      ls_key-tcode      = ls_scope-tcode.
      IF ls_scope-record_key IS NOT INITIAL.
        ls_key-group_key = ls_scope-record_key.
      ELSE.
        ls_key-group_key = |{ ls_scope-row_index }|.
      ENDIF.
      IF ls_key-session_id IS INITIAL OR ls_key-group_key IS INITIAL.
        CONTINUE.
      ENDIF.
      INSERT ls_key INTO TABLE gt_dash_scope_826.
    ENDLOOP.
    gv_dash_scope_source_826 = 'EXECUTION_SCOPE'.
    gv_dash_run_mode_826     = 'Selected Scope'.
  ENDIF.

  IF gt_dash_scope_826 IS INITIAL.
    cv_message = 'No Business Group scope is available for Result Dashboard.'.
    RETURN.
  ENDIF.

  LOOP AT gt_dash_scope_826 INTO ls_key.
    IF lv_session IS INITIAL.
      lv_session = ls_key-session_id.
    ELSEIF lv_session <> ls_key-session_id.
      lv_scope_invalid = abap_true.
      EXIT.
    ENDIF.
  ENDLOOP.

  IF lv_scope_invalid = abap_true.
    REFRESH gt_dash_scope_826.
    cv_message = 'Result Dashboard requires selected groups from one Session ID only.'.
    RETURN.
  ENDIF.

  cv_count = lines( gt_dash_scope_826 ).
  gv_dash_scope_count_826 = cv_count.
  txtp_result_session = lv_session.
  cv_ok = abap_true.
ENDFORM.

*& Build dashboard totals from selected Business Groups only.
*& Counts are group-level, not staging-row-level, so 1,000+ groups remain
*& truthful even when a group contains many uploaded rows/items.

FORM build_selected_summary.
  DATA: ls_sum       TYPE ty_result_summary,
        ls_exec      TYPE ty_exec_disp,
        ls_key       TYPE ty_0400_sel_key,
        lv_processed TYPE i,
        lv_rate      TYPE p DECIMALS 2,
        lv_total_c   TYPE char20,
        lv_proc_c    TYPE char20.

  REFRESH: gt_result_summary, gt_result_all, gt_result_msg.

  IF gt_dash_scope_826 IS INITIAL.
    RETURN.
  ENDIF.

  IF gt_exec_disp IS INITIAL.
    IF gt_staging_alv IS INITIAL AND gt_staging IS NOT INITIAL.
      PERFORM prepare_alv_0400.
    ENDIF.
    PERFORM build_exec_cockpit.
  ENDIF.

  CLEAR ls_sum.
  LOOP AT gt_dash_scope_826 INTO ls_key.
    ls_sum-session_id = ls_key-session_id.
    EXIT.
  ENDLOOP.

  LOOP AT gt_exec_disp INTO ls_exec.
    READ TABLE gt_dash_scope_826 TRANSPORTING NO FIELDS
      WITH TABLE KEY session_id = ls_exec-session_id
                     group_key  = ls_exec-group_key
                     tcode      = ls_exec-tcode.
    IF sy-subrc <> 0.
      CONTINUE.
    ENDIF.

    ADD 1 TO ls_sum-total_records.
    CASE ls_exec-run_status.
      WHEN gc_st_success OR gc_st_processed.
        ADD 1 TO ls_sum-success_records.
        ADD 1 TO ls_sum-processed_records.
      WHEN gc_st_warning OR gc_st_partial OR gc_st_skipped.
        ADD 1 TO ls_sum-warning_records.
        ADD 1 TO ls_sum-processed_records.
      WHEN gc_st_error OR 'BLOCKED_ONBOARDING' OR 'TIMEOUT'.
        ADD 1 TO ls_sum-error_records.
        ADD 1 TO ls_sum-processed_records.
      WHEN gc_st_sm35q OR 'SM35QUEUE' OR 'QUEUED_SM35'.
        ADD 1 TO ls_sum-sm35_queue_records.
      WHEN gc_st_ready.
        ADD 1 TO ls_sum-ready_records.
      WHEN 'RETRY'.
        ADD 1 TO ls_sum-retry_count.
      WHEN OTHERS.
 "Running/processing states remain in Total but are not mislabeled.
    ENDCASE.

    IF ls_exec-message IS NOT INITIAL.
      ls_sum-last_message = ls_exec-message.
    ENDIF.
  ENDLOOP.

  IF ls_sum-total_records < gv_dash_scope_count_826.
    ls_sum-total_records = gv_dash_scope_count_826.
  ENDIF.

  IF ls_sum-session_id IS NOT INITIAL.
    SELECT * FROM zbdc_result_bup
      INTO TABLE @gt_result_all
      FOR ALL ENTRIES IN @gt_dash_scope_826
      WHERE session_id = @gt_dash_scope_826-session_id
        AND record_key = @gt_dash_scope_826-group_key
        AND tcode      = @gt_dash_scope_826-tcode.
    IF sy-subrc = 0.
      gt_result_msg = gt_result_all.
      ls_sum-log_count = lines( gt_result_all ).
    ENDIF.
  ENDIF.

  lv_processed = ls_sum-processed_records.
  IF lv_processed > 0.
    lv_rate = ls_sum-success_records * 100 / lv_processed.
    WRITE lv_rate TO ls_sum-success_rate DECIMALS 1.
    CONDENSE ls_sum-success_rate NO-GAPS.
    CONCATENATE ls_sum-success_rate '%' INTO ls_sum-success_rate.
  ELSE.
    ls_sum-success_rate = '0.0%'.
  ENDIF.

  WRITE ls_sum-total_records TO lv_total_c.
  WRITE ls_sum-processed_records TO lv_proc_c.
  CONDENSE: lv_total_c NO-GAPS, lv_proc_c NO-GAPS.
  CONCATENATE lv_proc_c '/' lv_total_c INTO ls_sum-process_progress.

  IF ls_sum-error_records > 0.
    ls_sum-status_text = 'NEEDS_ATTENTION'.
    ls_sum-next_action = 'Review selected group errors'.
  ELSEIF ls_sum-warning_records > 0.
    ls_sum-status_text = 'HAS_WARNING'.
    ls_sum-next_action = 'Review selected group warnings'.
  ELSEIF ls_sum-sm35_queue_records > 0.
    ls_sum-status_text = 'RUNNING_OR_QUEUED'.
    ls_sum-next_action = 'Selected scope contains SM35 queue work'.
  ELSEIF ls_sum-total_records > 0 AND
         ls_sum-success_records = ls_sum-total_records.
    ls_sum-status_text = 'COMPLETED_SUCCESS'.
    ls_sum-next_action = 'Selected scope completed'.
  ELSEIF ls_sum-ready_records > 0.
    ls_sum-status_text = 'READY_FOR_EXECUTION'.
    ls_sum-next_action = 'Selected scope contains READY groups'.
  ELSE.
    ls_sum-status_text = 'IN_PROGRESS'.
    ls_sum-next_action = 'Selected scope is in progress'.
  ENDIF.

  APPEND ls_sum TO gt_result_summary.
ENDFORM.

FORM open_result_dash_curr.
  DATA: lv_scope_count TYPE i,
        lv_scope_ok    TYPE abap_bool,
        lv_scope_msg   TYPE string.

  CLEAR txtp_result_session.
  CLEAR: lv_scope_count, lv_scope_ok, lv_scope_msg.

  PERFORM prepare_dash_scope
    CHANGING lv_scope_count lv_scope_ok lv_scope_msg.
  IF lv_scope_ok <> abap_true.
    IF lv_scope_msg IS INITIAL.
      lv_scope_msg = 'No valid dashboard scope is available for Result Dashboard.'.
    ENDIF.
    MESSAGE lv_scope_msg TYPE 'S' DISPLAY LIKE 'W'.
    RETURN.
  ENDIF.

  REFRESH: gt_result_all, gt_result_msg, gt_result_summary, gt_result_cards.
  PERFORM build_selected_summary.
  IF gt_result_summary IS INITIAL.
    MESSAGE 'No current data exists for the selected dashboard scope.' TYPE 'S' DISPLAY LIKE 'W'.
    RETURN.
  ENDIF.

  PERFORM build_dash_cards.
  PERFORM show_result_dash_safe.
ENDFORM.

FORM add_dash_card USING pv_section TYPE csequence
                             pv_metric  TYPE csequence
                             pv_value   TYPE csequence
                             pv_detail  TYPE csequence
                             pv_status  TYPE csequence
                             pv_action  TYPE csequence.
  DATA ls_card TYPE ty_result_card.

  CLEAR ls_card.
  ls_card-section     = pv_section.
  ls_card-metric      = pv_metric.
  ls_card-value       = pv_value.
  ls_card-detail      = pv_detail.
  ls_card-status_text = pv_status.
  ls_card-next_action = pv_action.
  APPEND ls_card TO gt_result_cards.
ENDFORM.

FORM build_dash_cards.
  DATA: ls_sum       TYPE ty_result_summary,
        lv_total     TYPE char20,
        lv_ready     TYPE char20,
        lv_sm35      TYPE char20,
        lv_proc      TYPE char20,
        lv_success   TYPE char20,
        lv_warning   TYPE char20,
        lv_error     TYPE char20,
        lv_retry     TYPE char20,
        lv_logs      TYPE char20,
        lv_detail    TYPE char120,
        lv_exec_det  TYPE char120,
        lv_note      TYPE char120.

  REFRESH gt_result_cards.

  IF gt_result_summary IS INITIAL AND gt_dash_scope_826 IS NOT INITIAL.
    PERFORM build_selected_summary.
  ENDIF.

  READ TABLE gt_result_summary INTO ls_sum INDEX 1.
  IF sy-subrc <> 0.
    RETURN.
  ENDIF.

  WRITE ls_sum-total_records TO lv_total.
  WRITE ls_sum-ready_records TO lv_ready.
  WRITE ls_sum-sm35_queue_records TO lv_sm35.
  WRITE ls_sum-processed_records TO lv_proc.
  WRITE ls_sum-success_records TO lv_success.
  WRITE ls_sum-warning_records TO lv_warning.
  WRITE ls_sum-error_records TO lv_error.
  WRITE ls_sum-retry_count TO lv_retry.
  WRITE ls_sum-log_count TO lv_logs.
  CONDENSE lv_total NO-GAPS.
  CONDENSE lv_ready NO-GAPS.
  CONDENSE lv_sm35 NO-GAPS.
  CONDENSE lv_proc NO-GAPS.
  CONDENSE lv_success NO-GAPS.
  CONDENSE lv_warning NO-GAPS.
  CONDENSE lv_error NO-GAPS.
  CONDENSE lv_retry NO-GAPS.
  CONDENSE lv_logs NO-GAPS.

  CONCATENATE 'Mode' ls_sum-bdc_display_mode ', Update'
              ls_sum-update_mode INTO lv_exec_det SEPARATED BY space.
  CONCATENATE 'Ready' lv_ready '| SM35 Queue' lv_sm35 '| Processed'
              lv_proc INTO lv_detail SEPARATED BY space.

  PERFORM add_dash_card USING
    '01 RUN CONTEXT' 'Session' ls_sum-session_id
    lv_exec_det ls_sum-status_text ls_sum-next_action.

  PERFORM add_dash_card USING
    '01 RUN CONTEXT' 'Executor' ls_sum-executor_type
    lv_exec_det ls_sum-status_text ls_sum-next_action.

  PERFORM add_dash_card USING
    '02 LIFECYCLE' 'Total Groups' lv_total
    lv_detail ls_sum-status_text ls_sum-next_action.

  PERFORM add_dash_card USING
    '02 LIFECYCLE' 'Ready' lv_ready
    'Groups not executed yet' ls_sum-status_text 'Run All / Run Selected'.

  PERFORM add_dash_card USING
    '02 LIFECYCLE' 'SM35 Queue' lv_sm35
    'Queued in SM35, not counted as SUCCESS' ls_sum-status_text
    'Process in SM35 then refresh'.

  PERFORM add_dash_card USING
    '02 LIFECYCLE' 'Processed' lv_proc
    'SUCCESS + WARNING + ERROR evidence only' ls_sum-status_text
    'Review result proof'.

  PERFORM add_dash_card USING
    '03 OUTCOME' 'Success' lv_success
    'SAP object created / verified when available' ls_sum-status_text
    'Double-click SAP object if present'.

  PERFORM add_dash_card USING
    '03 OUTCOME' 'Warning' lv_warning
    'Created with warning or proof warning' ls_sum-status_text
    'Review warning before retry'.

  PERFORM add_dash_card USING
    '03 OUTCOME' 'Error' lv_error
    'Hard error from validation / BDC / SM35 result' ls_sum-status_text
    'Open Error Detail / Fix Guide'.

  PERFORM add_dash_card USING
    '04 KPI' 'Success Rate' ls_sum-success_rate
    'SM35QUEUE is pending and is not counted as success' ls_sum-status_text
    'Review after execution'.

  PERFORM add_dash_card USING
    '04 KPI' 'Queue Progress' ls_sum-queue_progress
    'BISM queue progress; N/A for Call Transaction' ls_sum-status_text
    'Open SM35 Monitor if pending'.

  PERFORM add_dash_card USING
    '04 KPI' 'Process Progress' ls_sum-process_progress
    'Real processed progress after CT/SM35 result sync' ls_sum-status_text
    'Reopen dashboard'.

  PERFORM add_dash_card USING
    '05 EVIDENCE' 'BDC Log Rows' lv_logs
    'Rows persisted in ZBDC_RESULT_BUP' ls_sum-status_text
    'Open drilldown / messages'.

  PERFORM add_dash_card USING
    '05 EVIDENCE' 'Retry Count' lv_retry
    'Retry attempts recorded for this session' ls_sum-status_text
    'Retry only retryable ERROR'.

  lv_note = ls_sum-last_message.
  IF lv_note IS INITIAL.
    lv_note = 'No SAP proof message persisted yet'.
  ENDIF.
  PERFORM add_dash_card USING
    '06 PROOF' 'Last Message' lv_note
    'Last persisted SAP/result message for this session' ls_sum-status_text
    ls_sum-next_action.
ENDFORM.

FORM set_dash_col_text USING po_cols  TYPE REF TO cl_salv_columns_table
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

*& Dynamic visual Result Dashboard
*& Purpose:
*& Render the current session as KPI cards + charts in SAP GUI using
*& CL_GUI_HTML_VIEWER. All values are rebuilt from the real session data
*& whenever Result Dashboard is opened; there are no hard-coded metrics.
*& If HTML rendering is unavailable, the existing SALV dashboard remains
*& the fallback. No execution or business-state write is performed here.

FORM free_visual_dash.
  IF go_dash_411_html IS BOUND.
    CALL METHOD go_dash_411_html->free
      EXCEPTIONS
        cntl_error        = 1
        cntl_system_error = 2
        OTHERS            = 3.
    FREE go_dash_411_html.
  ENDIF.

  IF go_dash_411_dlg IS BOUND.
    CALL METHOD go_dash_411_dlg->free
      EXCEPTIONS
        cntl_error        = 1
        cntl_system_error = 2
        OTHERS            = 3.
    FREE go_dash_411_dlg.
  ENDIF.

  CLEAR: go_dash_411_html, go_dash_411_dlg, go_dash_evt_411, gv_dash_411_url.
  CALL METHOD cl_gui_cfw=>flush
    EXCEPTIONS
      cntl_system_error = 1
      cntl_error        = 2
      OTHERS            = 3.
ENDFORM.

FORM html_escape_in_place CHANGING pv_text TYPE string.
  REPLACE ALL OCCURRENCES OF '&' IN pv_text WITH '&amp;'.
  REPLACE ALL OCCURRENCES OF '<' IN pv_text WITH '&lt;'.
  REPLACE ALL OCCURRENCES OF '>' IN pv_text WITH '&gt;'.
  REPLACE ALL OCCURRENCES OF '"' IN pv_text WITH '&quot;'.
ENDFORM.

FORM js_escape CHANGING pv_text TYPE string.
  REPLACE ALL OCCURRENCES OF '\' IN pv_text WITH '\\'.
  REPLACE ALL OCCURRENCES OF '"' IN pv_text WITH '"'.
  REPLACE ALL OCCURRENCES OF '<' IN pv_text WITH '\x3C'.
  REPLACE ALL OCCURRENCES OF '>' IN pv_text WITH '\x3E'.
  REPLACE ALL OCCURRENCES OF cl_abap_char_utilities=>cr_lf IN pv_text WITH space.
  REPLACE ALL OCCURRENCES OF cl_abap_char_utilities=>newline IN pv_text WITH space.
ENDFORM.

FORM build_visual_html
  CHANGING pt_html TYPE ty_t_dash_html_411.

  TYPES: BEGIN OF ty_exec_ev_826,
           session_id TYPE zbdc_result_bup-session_id,
           record_key TYPE zbdc_result_bup-record_key,
           max_attempt TYPE i,
           latest_at TYPE zbdc_result_bup-created_at,
           has_sm35 TYPE abap_bool,
           has_any  TYPE abap_bool,
         END OF ty_exec_ev_826.
  TYPES ty_t_exec_ev_826 TYPE HASHED TABLE OF ty_exec_ev_826
    WITH UNIQUE KEY session_id record_key.
  TYPES ty_t_tcode_826 TYPE SORTED TABLE OF sy-tcode
    WITH UNIQUE KEY table_line.
  TYPES: BEGIN OF ty_dash_row_830,
           group_key   TYPE zbdc_staging_bup-record_key,
           tcode       TYPE sy-tcode,
           status      TYPE c LENGTH 20,
           execution   TYPE c LENGTH 20,
           last_update TYPE c LENGTH 8,
         END OF ty_dash_row_830.
  TYPES ty_t_dash_row_830 TYPE STANDARD TABLE OF ty_dash_row_830
    WITH DEFAULT KEY.

  DATA: ls_sum        TYPE ty_result_summary,
        ls_exec       TYPE ty_exec_disp,
        ls_key        TYPE ty_0400_sel_key,
        ls_res        TYPE zbdc_result_bup,
        ls_ev         TYPE ty_exec_ev_826,
        ls_scope      TYPE ty_staging_alv,
        lt_ev         TYPE ty_t_exec_ev_826,
        lt_tcodes     TYPE ty_t_tcode_826,
        lt_run_keys   TYPE ty_t_0400_sel_key,
        lt_dash_rows_830 TYPE ty_t_dash_row_830,
        ls_dash_row_830 TYPE ty_dash_row_830,
        lv_total      TYPE i,
        lv_processed  TYPE i,
        lv_ready      TYPE i,
        lv_running    TYPE i,
        lv_success    TYPE i,
        lv_warning    TYPE i,
        lv_error      TYPE i,
        lv_queue      TYPE i,
        lv_other      TYPE i,
        lv_ct         TYPE i,
        lv_bism       TYPE i,
        lv_unassigned TYPE i,
        lv_total_items TYPE i,
        lv_proc_items  TYPE i,
        lv_rem_items   TYPE i,
        lv_remaining   TYPE i,
        lv_session_total TYPE i,
        lv_proc_pct   TYPE i,
        lv_ready_pct  TYPE i,
        lv_run_pct    TYPE i,
        lv_success_pct TYPE i,
        lv_warning_pct TYPE i,
        lv_error_pct   TYPE i,
        lv_queue_pct   TYPE i,
        lv_ct_pct      TYPE i,
        lv_bism_pct    TYPE i,
        lv_unass_pct   TYPE i,
        lv_elapsed     TYPE i,
        lv_est_sec     TYPE i,
        lv_min         TYPE i,
        lv_sec         TYPE i,
        lv_scope_match TYPE abap_bool,
        lv_ev_found_830 TYPE abap_bool,
        lv_exec_row_830 TYPE c LENGTH 20,
        lv_upd_date_830 TYPE sy-datum,
        lv_upd_time_830 TYPE sy-uzeit,
        lv_upd_txt_830  TYPE c LENGTH 8,
        lv_scope_text  TYPE string,
        lv_tcode_text  TYPE string,
        lv_exec_mix    TYPE string,
        lv_status_text TYPE string,
        lv_now         TYPE string,
        lv_date_c      TYPE char10,
        lv_time_c      TYPE char8,
        lv_rate_txt    TYPE string,
        lv_est_txt     TYPE string,
        lv_elapsed_txt TYPE string,
        lv_batch_txt   TYPE string,
        lv_total_c     TYPE char20,
        lv_processed_c TYPE char20,
        lv_remaining_c TYPE char20,
        lv_ready_c     TYPE char20,
        lv_running_c   TYPE char20,
        lv_success_c   TYPE char20,
        lv_warning_c   TYPE char20,
        lv_error_c     TYPE char20,
        lv_queue_c     TYPE char20,
        lv_ct_c        TYPE char20,
        lv_bism_c      TYPE char20,
        lv_unass_c     TYPE char20,
        lv_items_c     TYPE char20,
        lv_proc_items_c TYPE char20,
        lv_session_total_c TYPE char20,
        lv_rate_num    TYPE p LENGTH 8 DECIMALS 1,
        lv_success_rate TYPE p LENGTH 8 DECIMALS 1,
        lv_rate_num_txt TYPE c LENGTH 32,
        lv_success_rate_num_txt TYPE c LENGTH 32,
        lv_success_rate_txt TYPE string.
  FIELD-SYMBOLS: <ls_ev> TYPE ty_exec_ev_826.

  REFRESH pt_html.

  READ TABLE gt_result_summary INTO ls_sum INDEX 1.
  IF sy-subrc <> 0 OR gt_dash_scope_826 IS INITIAL.
    RETURN.
  ENDIF.

  LOOP AT gt_result_all INTO ls_res.
    READ TABLE lt_ev ASSIGNING <ls_ev>
      WITH TABLE KEY session_id = ls_res-session_id
                     record_key = ls_res-record_key.
    IF sy-subrc <> 0.
      CLEAR ls_ev.
      ls_ev-session_id = ls_res-session_id.
      ls_ev-record_key = ls_res-record_key.
      INSERT ls_ev INTO TABLE lt_ev ASSIGNING <ls_ev>.
    ENDIF.

    IF <ls_ev>-latest_at IS INITIAL OR ls_res-created_at > <ls_ev>-latest_at.
      <ls_ev>-latest_at = ls_res-created_at.
    ENDIF.

    IF ls_res-attempt_no > <ls_ev>-max_attempt.
      <ls_ev>-max_attempt = ls_res-attempt_no.
      CLEAR: <ls_ev>-has_sm35, <ls_ev>-has_any.
    ENDIF.
    IF ls_res-attempt_no = <ls_ev>-max_attempt AND
       <ls_ev>-max_attempt > 0.
      <ls_ev>-has_any = abap_true.
      IF ls_res-field_name CP 'SM35*' OR ls_res-exec_status CP 'SM35*'.
        <ls_ev>-has_sm35 = abap_true.
      ENDIF.
    ENDIF.
  ENDLOOP.

  LOOP AT gt_exec_scope_0500 INTO ls_scope.
    CLEAR ls_key.
    ls_key-session_id = ls_scope-session_id.
    ls_key-tcode = ls_scope-tcode.
    IF ls_scope-record_key IS NOT INITIAL.
      ls_key-group_key = ls_scope-record_key.
    ELSE.
      ls_key-group_key = |{ ls_scope-row_index }|.
    ENDIF.
    IF ls_key-session_id IS NOT INITIAL AND ls_key-group_key IS NOT INITIAL.
      INSERT ls_key INTO TABLE lt_run_keys.
    ENDIF.
  ENDLOOP.

  lv_scope_match = abap_false.
  IF lt_run_keys IS NOT INITIAL AND
     lines( lt_run_keys ) = lines( gt_dash_scope_826 ).
    lv_scope_match = abap_true.
    LOOP AT gt_dash_scope_826 INTO ls_key.
      READ TABLE lt_run_keys TRANSPORTING NO FIELDS
        WITH TABLE KEY session_id = ls_key-session_id
                       group_key  = ls_key-group_key
                       tcode      = ls_key-tcode.
      IF sy-subrc <> 0.
        lv_scope_match = abap_false.
        EXIT.
      ENDIF.
    ENDLOOP.
  ENDIF.

  LOOP AT gt_exec_disp INTO ls_exec.
    READ TABLE gt_dash_scope_826 TRANSPORTING NO FIELDS
      WITH TABLE KEY session_id = ls_exec-session_id
                     group_key  = ls_exec-group_key
                     tcode      = ls_exec-tcode.
    IF sy-subrc <> 0.
      CONTINUE.
    ENDIF.

    lv_total = lv_total + 1.
    IF ls_exec-tcode IS NOT INITIAL.
      INSERT ls_exec-tcode INTO TABLE lt_tcodes.
    ENDIF.

    IF ls_exec-item_count > 0.
      lv_total_items = lv_total_items + ls_exec-item_count.
    ELSE.
      lv_total_items = lv_total_items + 1.
    ENDIF.

    CASE ls_exec-run_status.
      WHEN gc_st_success OR gc_st_processed.
        lv_success = lv_success + 1.
        lv_processed = lv_processed + 1.
        IF ls_exec-item_count > 0.
          lv_proc_items = lv_proc_items + ls_exec-item_count.
        ELSE.
          lv_proc_items = lv_proc_items + 1.
        ENDIF.
      WHEN gc_st_warning OR gc_st_partial OR gc_st_skipped.
        lv_warning = lv_warning + 1.
        lv_processed = lv_processed + 1.
        IF ls_exec-item_count > 0.
          lv_proc_items = lv_proc_items + ls_exec-item_count.
        ELSE.
          lv_proc_items = lv_proc_items + 1.
        ENDIF.
      WHEN gc_st_error OR 'BLOCKED_ONBOARDING' OR 'TIMEOUT'.
        lv_error = lv_error + 1.
        lv_processed = lv_processed + 1.
        IF ls_exec-item_count > 0.
          lv_proc_items = lv_proc_items + ls_exec-item_count.
        ELSE.
          lv_proc_items = lv_proc_items + 1.
        ENDIF.
      WHEN gc_st_sm35q OR 'SM35QUEUE' OR 'QUEUED_SM35'.
        lv_queue = lv_queue + 1.
      WHEN gc_st_ready.
        lv_ready = lv_ready + 1.
      WHEN 'PROCESSING' OR 'RUNNING' OR 'VERIFYING' OR 'QUEUED'.
        lv_running = lv_running + 1.
      WHEN OTHERS.
        lv_other = lv_other + 1.
    ENDCASE.

    CLEAR: lv_ev_found_830, lv_exec_row_830,
           lv_upd_date_830, lv_upd_time_830, lv_upd_txt_830,
           ls_dash_row_830.
    READ TABLE lt_ev ASSIGNING <ls_ev>
      WITH TABLE KEY session_id = ls_exec-session_id
                     record_key = ls_exec-group_key.
    IF sy-subrc = 0.
      lv_ev_found_830 = abap_true.
    ENDIF.

    IF ls_exec-run_status = gc_st_sm35q OR
       ls_exec-run_status = 'SM35QUEUE' OR
       ls_exec-run_status = 'QUEUED_SM35'.
      lv_bism = lv_bism + 1.
      lv_exec_row_830 = 'SM35 Queue'.
    ELSEIF lv_ev_found_830 = abap_true AND <ls_ev>-max_attempt > 0.
      IF <ls_ev>-has_sm35 = abap_true.
        lv_bism = lv_bism + 1.
        lv_exec_row_830 = 'BISM'.
      ELSE.
        lv_ct = lv_ct + 1.
        lv_exec_row_830 = 'CT'.
      ENDIF.
    ELSE.
      lv_unassigned = lv_unassigned + 1.
      lv_exec_row_830 = 'Not executed'.
    ENDIF.

    ls_dash_row_830-group_key = ls_exec-group_key.
    ls_dash_row_830-tcode     = ls_exec-tcode.
    ls_dash_row_830-status    = ls_exec-run_status.
    IF ls_dash_row_830-status IS INITIAL.
      ls_dash_row_830-status = '-'.
    ENDIF.
    ls_dash_row_830-execution = lv_exec_row_830.

    IF lv_ev_found_830 = abap_true AND <ls_ev>-latest_at IS NOT INITIAL.
      PERFORM ts_to_demo USING <ls_ev>-latest_at CHANGING lv_upd_date_830 lv_upd_time_830.
      IF lv_upd_time_830 IS NOT INITIAL.
        CONCATENATE lv_upd_time_830+0(2) lv_upd_time_830+2(2)
                    lv_upd_time_830+4(2)
          INTO lv_upd_txt_830 SEPARATED BY ':'.
        ls_dash_row_830-last_update = lv_upd_txt_830.
      ENDIF.
    ENDIF.
    IF ls_dash_row_830-last_update IS INITIAL.
      ls_dash_row_830-last_update = '-'.
    ENDIF.
    APPEND ls_dash_row_830 TO lt_dash_rows_830.
  ENDLOOP.

  IF lv_total < gv_dash_scope_count_826.
    lv_other = lv_other + gv_dash_scope_count_826 - lv_total.
    lv_total = gv_dash_scope_count_826.
  ENDIF.

  IF lv_total <= 0.
    RETURN.
  ENDIF.

  lv_remaining = lv_total - lv_processed.
  IF lv_remaining < 0.
    lv_remaining = 0.
  ENDIF.

  lv_rem_items = lv_total_items - lv_proc_items.
  IF lv_rem_items < 0.
    lv_rem_items = 0.
  ENDIF.

  lv_proc_pct    = lv_processed * 100 / lv_total.
  lv_ready_pct   = lv_ready * 100 / lv_total.
  lv_run_pct     = lv_running * 100 / lv_total.
  lv_success_pct = lv_success * 100 / lv_total.
  lv_warning_pct = lv_warning * 100 / lv_total.
  lv_error_pct   = lv_error * 100 / lv_total.
  lv_queue_pct   = lv_queue * 100 / lv_total.
  lv_ct_pct      = lv_ct * 100 / lv_total.
  lv_bism_pct    = lv_bism * 100 / lv_total.
  lv_unass_pct   = lv_unassigned * 100 / lv_total.

  IF lv_processed > 0.
    lv_success_rate = lv_success.
    lv_success_rate = lv_success_rate * 100 / lv_processed.
    CLEAR lv_success_rate_num_txt.
    WRITE lv_success_rate TO lv_success_rate_num_txt DECIMALS 1.
    CONDENSE lv_success_rate_num_txt NO-GAPS.
    CONCATENATE lv_success_rate_num_txt '%' INTO lv_success_rate_txt.
  ELSE.
    lv_success_rate_txt = '0.0%'.
  ENDIF.

  lv_session_total = gv_exec_total_grp.
  IF lv_session_total < lv_total.
    lv_session_total = lv_total.
  ENDIF.

  IF lines( lt_tcodes ) = 1.
    READ TABLE lt_tcodes INTO DATA(lv_one_tcode) INDEX 1.
    lv_tcode_text = lv_one_tcode.
  ELSEIF lines( lt_tcodes ) > 1.
    lv_tcode_text = |Mixed ({ lines( lt_tcodes ) } TCodes)|.
  ELSE.
    lv_tcode_text = 'Not available'.
  ENDIF.

  IF lv_ct > 0 AND lv_bism > 0.
    lv_exec_mix = 'CT + BISM'.
  ELSEIF lv_ct > 0.
    lv_exec_mix = 'CT'.
  ELSEIF lv_bism > 0.
    lv_exec_mix = 'BISM'.
  ELSE.
    lv_exec_mix = 'Not assigned'.
  ENDIF.

  IF lv_error > 0.
    lv_status_text = 'Needs Attention'.
  ELSEIF lv_warning > 0.
    lv_status_text = 'Warning'.
  ELSEIF lv_running > 0 OR lv_queue > 0.
    lv_status_text = 'Running Live'.
  ELSEIF lv_success = lv_total.
    lv_status_text = 'Completed'.
  ELSEIF lv_ready > 0.
    lv_status_text = 'Ready'.
  ELSE.
    lv_status_text = 'In Progress'.
  ENDIF.

  IF gv_dash_scope_source_826 = 'SESSION_ALL'.
    lv_scope_text = |All Groups ({ lv_total })|.
  ELSEIF lv_session_total > lv_total.
    lv_scope_text = |{ lv_total } selected / { lv_session_total } total|.
  ELSE.
    lv_scope_text = |{ lv_total } selected groups|.
  ENDIF.

  lv_elapsed = 0.
  IF lv_scope_match = abap_true AND gv_exec_elapsed > 0.
    lv_elapsed = gv_exec_elapsed.
  ENDIF.

  lv_rate_txt = 'n/a'.
  lv_est_txt = 'n/a'.
  lv_elapsed_txt = 'n/a'.
  IF lv_elapsed > 0.
    lv_min = lv_elapsed DIV 60.
    lv_sec = lv_elapsed MOD 60.
    IF lv_min > 0.
      lv_elapsed_txt = |{ lv_min } min { lv_sec } sec|.
    ELSE.
      lv_elapsed_txt = |{ lv_sec } sec|.
    ENDIF.

    IF lv_proc_items > 0.
      lv_rate_num = lv_proc_items.
      lv_rate_num = lv_rate_num / lv_elapsed.
      IF lv_rate_num > 0.
        CLEAR lv_rate_num_txt.
        WRITE lv_rate_num TO lv_rate_num_txt DECIMALS 1.
        CONDENSE lv_rate_num_txt NO-GAPS.
        CONCATENATE lv_rate_num_txt ' rows/sec' INTO lv_rate_txt.
        lv_est_sec = lv_rem_items / lv_rate_num.
        lv_min = lv_est_sec DIV 60.
        lv_sec = lv_est_sec MOD 60.
        IF lv_min > 0.
          lv_est_txt = |~ { lv_min } min { lv_sec } sec|.
        ELSE.
          lv_est_txt = |~ { lv_sec } sec|.
        ENDIF.
      ENDIF.
    ENDIF.
  ENDIF.

  lv_batch_txt = txtp_batch_size.
  IF lv_batch_txt IS INITIAL.
    lv_batch_txt = 'n/a'.
  ENDIF.

  WRITE lv_total TO lv_total_c.
  WRITE lv_processed TO lv_processed_c.
  WRITE lv_remaining TO lv_remaining_c.
  WRITE lv_ready TO lv_ready_c.
  WRITE lv_running TO lv_running_c.
  WRITE lv_success TO lv_success_c.
  WRITE lv_warning TO lv_warning_c.
  WRITE lv_error TO lv_error_c.
  WRITE lv_queue TO lv_queue_c.
  WRITE lv_ct TO lv_ct_c.
  WRITE lv_bism TO lv_bism_c.
  WRITE lv_unassigned TO lv_unass_c.
  WRITE lv_total_items TO lv_items_c.
  WRITE lv_proc_items TO lv_proc_items_c.
  WRITE lv_session_total TO lv_session_total_c.
  CONDENSE: lv_total_c NO-GAPS, lv_processed_c NO-GAPS,
            lv_remaining_c NO-GAPS, lv_ready_c NO-GAPS, lv_running_c NO-GAPS,
            lv_success_c NO-GAPS, lv_warning_c NO-GAPS,
            lv_error_c NO-GAPS, lv_queue_c NO-GAPS,
            lv_ct_c NO-GAPS, lv_bism_c NO-GAPS,
            lv_unass_c NO-GAPS, lv_items_c NO-GAPS,
            lv_proc_items_c NO-GAPS, lv_session_total_c NO-GAPS.

  PERFORM get_demo_now CHANGING lv_upd_date_830 lv_upd_time_830.
  lv_date_c = |{ lv_upd_date_830+6(2) }.{ lv_upd_date_830+4(2) }.{ lv_upd_date_830+0(4) }|.
  lv_time_c = |{ lv_upd_time_830+0(2) }:{ lv_upd_time_830+2(2) }:{ lv_upd_time_830+4(2) }|.
  CONCATENATE lv_date_c lv_time_c INTO lv_now SEPARATED BY space.

  PERFORM html_escape_in_place CHANGING lv_scope_text.
  PERFORM html_escape_in_place CHANGING lv_tcode_text.
  PERFORM html_escape_in_place CHANGING lv_exec_mix.
  PERFORM html_escape_in_place CHANGING lv_status_text.
  PERFORM html_escape_in_place CHANGING lv_now.
  PERFORM html_escape_in_place CHANGING lv_rate_txt.
  PERFORM html_escape_in_place CHANGING lv_est_txt.
  PERFORM html_escape_in_place CHANGING lv_elapsed_txt.
  PERFORM html_escape_in_place CHANGING lv_batch_txt.

 "keep the donut status distribution, replace the duplicate status-bar panel
 "with a compact Processing Summary, remove the redundant Success Rate KPI, and
 "rename Snapshot to Last Updated. Scope, counting, filters, and pagination stay unchanged.
  APPEND '<!doctype html><html><head><meta charset="utf-8">' TO pt_html.
  APPEND '<meta http-equiv="X-UA-Compatible" content="IE=edge">' TO pt_html.
  APPEND '<style>' TO pt_html.
 "use the browser document itself as the scroll surface. The previous
 "700-high dialog could extend behind the Windows taskbar, leaving the lower
 "scrollbar handle effectively unreachable. Keep the HTML content lossless
 "and let both SESSION_ALL and selected-scope dashboards scroll inside a
 "taskbar-safe dialog, exactly like the long-text renderer.
  APPEND 'html{width:100%;height:100%;margin:0;padding:0;overflow-y:scroll;overflow-x:hidden;background:#f4f7fb;}' TO pt_html.
  APPEND 'body{width:100%;min-height:100%;margin:0;padding:0;background:#f4f7fb;font-family:Arial,sans-serif;color:#153e75;}' TO pt_html.
  APPEND '.wrap{padding:16px 18px 100px 18px;box-sizing:border-box;min-height:100%;}' TO pt_html.
  APPEND '.top{width:100%;border-collapse:separate;border-spacing:0 0;margin-bottom:10px;}' TO pt_html.
  APPEND '.title{font-size:23px;font-weight:700;color:#123b6d;}.sub{font-size:11px;color:#64748b;margin-top:3px;}' TO pt_html.
  APPEND '.snap{font-size:10px;color:#64748b;text-align:right;vertical-align:top;}' TO pt_html.
  APPEND '.meta{width:100%;border-spacing:0;background:#fff;border:1px solid #dce6f2;border-radius:10px;margin-bottom:10px;}' TO pt_html.
  APPEND '.meta td{padding:9px 11px;border-right:1px solid #edf2f7;vertical-align:top;}.meta td:last-child{border-right:0;}' TO pt_html.
  APPEND '.ml{font-size:9px;text-transform:uppercase;color:#718096;}.mv{font-size:12px;font-weight:700;color:#153e75;margin-top:3px;}' TO pt_html.
  APPEND '.kpi{width:100%;border-spacing:8px 6px;margin-left:-8px;margin-bottom:6px;table-layout:fixed;}' TO pt_html.
  APPEND '.card{background:#fff;border:1px solid #dce6f2;border-radius:10px;padding:11px 13px;box-shadow:0 1px 2px #e6edf5;}' TO pt_html.
  APPEND '.kl{font-size:9px;text-transform:uppercase;color:#718096;}.kv{font-size:23px;font-weight:700;margin-top:3px;}' TO pt_html.
  APPEND '.ks{font-size:10px;color:#718096;margin-top:2px;}.blue{color:#1769e0}.green{color:#159455}.orange{color:#d98b00}' TO pt_html.
  APPEND '.red{color:#d92d20}.purple{color:#7c3aed}.grid{width:100%;border-spacing:10px 10px;margin-left:-10px;table-layout:fixed;}' TO pt_html.
  APPEND '.panel{background:#fff;border:1px solid #dce6f2;border-radius:10px;padding:13px;vertical-align:top;box-shadow:0 1px 2px #e6edf5;}' TO pt_html.
  APPEND '.pt{font-size:14px;font-weight:700;color:#153e75;margin-bottom:3px;}.ps{font-size:10px;color:#718096;margin-bottom:9px;}' TO pt_html.
  APPEND '.legend{font-size:10px;color:#475569;line-height:20px;}.dot{display:inline-block;width:8px;height:8px;border-radius:8px;margin-right:5px;}' TO pt_html.
  APPEND '.barrow{width:100%;border-collapse:collapse;margin:7px 0;}.barrow td{font-size:10px;color:#475569;}' TO pt_html.
  APPEND '.track{height:9px;background:#e8eef5;border-radius:6px;overflow:hidden;}.fill{height:9px;border-radius:6px;}' TO pt_html.
  APPEND '.metric{width:100%;border-collapse:collapse;}.metric td{padding:6px 1px;border-bottom:1px solid #edf2f7;font-size:10px;}' TO pt_html.
  APPEND '.metric td:last-child{text-align:right;font-weight:700;color:#153e75;}.split{width:100%;border-spacing:7px 0;table-layout:fixed;}' TO pt_html.
  APPEND '.mini{border:1px solid #e4ebf3;border-radius:8px;padding:10px;background:#fbfdff;}.mnum{font-size:22px;font-weight:700;margin-top:3px;}' TO pt_html.
  APPEND '.load{margin-top:10px;background:#f6f9fd;border-radius:8px;padding:9px;}.load td{font-size:9px;text-align:center;color:#475569;}' TO pt_html.
  APPEND '.foot{font-size:9px;color:#94a3b8;text-align:right;margin-top:4px;}' TO pt_html.
  APPEND '.detail{background:#fff;border:1px solid #dce6f2;border-radius:10px;padding:13px;box-shadow:0 1px 2px #e6edf5;}' TO pt_html.
  APPEND '.tools{width:100%;border-collapse:separate;border-spacing:8px 0;margin:8px 0 10px -8px;table-layout:fixed;}' TO pt_html.
  APPEND '.tl{font-size:9px;color:#718096;margin-bottom:4px;}.inp,.sel{width:100%;height:30px;border:1px solid #d7e2ee;border-radius:7px;background:#fff;color:#153e75;padding:0 9px;box-sizing:border-box;}' TO pt_html.
  APPEND '.tbl{width:100%;border-collapse:collapse;border:1px solid #dce6f2;table-layout:fixed;}.tbl th{background:#f4f7fb;color:#153e75;font-size:10px;text-align:left;padding:8px;border-bottom:1px solid #dce6f2;}' TO pt_html.
  APPEND '.tbl td{font-size:10px;color:#334155;padding:8px;border-bottom:1px solid #edf2f7;white-space:nowrap;overflow:hidden;text-overflow:ellipsis;}' TO pt_html.
  APPEND '.badge{display:inline-block;border-radius:10px;padding:3px 8px;font-size:9px;font-weight:700;}.st-success{background:#dcfce7;color:#16834f;}' TO pt_html.
  APPEND '.st-ready{background:#dbeafe;color:#1769e0;}.st-warning{background:#fef3c7;color:#b66b00;}.st-error{background:#fee2e2;color:#c53030;}' TO pt_html.
  APPEND '.st-queue{background:#ede9fe;color:#6d28d9;}.st-running{background:#cffafe;color:#0e7490;}.st-neutral{background:#eef2f7;color:#64748b;}' TO pt_html.
  APPEND '.tablefoot{width:100%;margin-top:9px;border-collapse:collapse;}.pageinfo{font-size:9px;color:#64748b;}.pager{text-align:right;white-space:nowrap;}' TO pt_html.
  APPEND '.pg{display:inline-block;min-width:27px;height:27px;line-height:27px;margin-left:3px;border:1px solid #d7e2ee;border-radius:6px;background:#fff;color:#1769e0;text-align:center;font-size:9px;cursor:pointer;}' TO pt_html.
  APPEND '.pg.on{background:#1769e0;color:#fff;border-color:#1769e0;}.pg.off{color:#b8c3d1;cursor:default;}.dots{display:inline-block;margin-left:6px;color:#64748b;font-size:10px;}' TO pt_html.
  APPEND '</style></head><body><div class="wrap">' TO pt_html.

  APPEND '<table class="top"><tr><td>' TO pt_html.
  APPEND '<div class="title">BDC Result Dashboard</div>' TO pt_html.
  IF gv_dash_scope_source_826 = 'SESSION_ALL'.
    APPEND '<div class="sub">Scalable monitoring for all Business Groups in the current session</div></td>' TO pt_html.
  ELSE.
    APPEND '<div class="sub">Scalable monitoring for the exact selected Business Group scope</div></td>' TO pt_html.
  ENDIF.
  APPEND |<td class="snap"><b>Last Updated</b><br>{ lv_now }</td></tr></table>| TO pt_html.

  APPEND '<table class="meta"><tr>' TO pt_html.
  APPEND |<td><div class="ml">Session ID</div><div class="mv">{ ls_sum-session_id }</div></td>| TO pt_html.
  APPEND |<td><div class="ml">Scope</div><div class="mv">{ lv_scope_text }</div></td>| TO pt_html.
  APPEND |<td><div class="ml">Transaction</div><div class="mv">{ lv_tcode_text }</div></td>| TO pt_html.
  APPEND |<td><div class="ml">Executor Mix</div><div class="mv">{ lv_exec_mix }</div></td>| TO pt_html.
  APPEND |<td><div class="ml">Status</div><div class="mv">{ lv_status_text }</div></td>| TO pt_html.
  APPEND '</tr></table>' TO pt_html.

  APPEND '<table class="kpi"><tr>' TO pt_html.
  IF gv_dash_scope_source_826 = 'SESSION_ALL'.
    APPEND |<td><div class="card"><div class="kl">Total Groups</div><div class="kv blue">{ lv_total_c }</div><div class="ks">Entire current session</div></div></td>| TO pt_html.
    APPEND |<td><div class="card"><div class="kl">Processed</div><div class="kv green">{ lv_processed_c }</div><div class="ks">{ lv_proc_pct }% of session</div></div></td>| TO pt_html.
  ELSE.
    APPEND |<td><div class="card"><div class="kl">Selected Groups</div><div class="kv blue">{ lv_total_c }</div><div class="ks">Exact outer scope</div></div></td>| TO pt_html.
    APPEND |<td><div class="card"><div class="kl">Processed</div><div class="kv green">{ lv_processed_c }</div><div class="ks">{ lv_proc_pct }% of selected</div></div></td>| TO pt_html.
  ENDIF.
  APPEND |<td><div class="card"><div class="kl">Ready</div><div class="kv blue">{ lv_ready_c }</div><div class="ks">{ lv_ready_pct }%</div></div></td>| TO pt_html.
  APPEND |<td><div class="card"><div class="kl">Success</div><div class="kv green">{ lv_success_c }</div><div class="ks">{ lv_success_pct }%</div></div></td>| TO pt_html.
  APPEND '</tr><tr>' TO pt_html.
  APPEND |<td><div class="card"><div class="kl">Warning</div><div class="kv orange">{ lv_warning_c }</div><div class="ks">{ lv_warning_pct }%</div></div></td>| TO pt_html.
  APPEND |<td><div class="card"><div class="kl">Error</div><div class="kv red">{ lv_error_c }</div><div class="ks">{ lv_error_pct }%</div></div></td>| TO pt_html.
  APPEND |<td><div class="card"><div class="kl">SM35 Queue</div><div class="kv purple">{ lv_queue_c }</div><div class="ks">{ lv_queue_pct }%</div></div></td>| TO pt_html.
  APPEND '<td></td>' TO pt_html.
  APPEND '</tr></table>' TO pt_html.

  APPEND '<table class="grid"><tr>' TO pt_html.
  APPEND '<td width="50%" class="panel"><div class="pt">Status Distribution</div>' TO pt_html.
  IF gv_dash_scope_source_826 = 'SESSION_ALL'.
    APPEND '<div class="ps">All Business Groups in the current session by execution status</div>' TO pt_html.
  ELSE.
    APPEND '<div class="ps">Selected Business Groups by current execution status</div>' TO pt_html.
  ENDIF.
  APPEND '<table width="100%"><tr><td width="52%"><canvas id="donut" width="310" height="220"></canvas></td><td>' TO pt_html.
  APPEND |<div class="legend"><span class="dot" style="background:#2f80ed"></span>Ready&nbsp;&nbsp;<b>{ lv_ready_c }</b> ({ lv_ready_pct }%)</div>| TO pt_html.
  IF lv_running > 0.
    APPEND |<div class="legend"><span class="dot" style="background:#06b6d4"></span>Running&nbsp;&nbsp;<b>{ lv_running_c }</b> ({ lv_run_pct }%)</div>| TO pt_html.
  ENDIF.
  APPEND |<div class="legend"><span class="dot" style="background:#22a06b"></span>Success&nbsp;&nbsp;<b>{ lv_success_c }</b> ({ lv_success_pct }%)</div>| TO pt_html.
  APPEND |<div class="legend"><span class="dot" style="background:#f5a623"></span>Warning&nbsp;&nbsp;<b>{ lv_warning_c }</b> ({ lv_warning_pct }%)</div>| TO pt_html.
  APPEND |<div class="legend"><span class="dot" style="background:#e5484d"></span>Error&nbsp;&nbsp;<b>{ lv_error_c }</b> ({ lv_error_pct }%)</div>| TO pt_html.
  APPEND |<div class="legend"><span class="dot" style="background:#8b5cf6"></span>SM35 Queue&nbsp;&nbsp;<b>{ lv_queue_c }</b> ({ lv_queue_pct }%)</div>| TO pt_html.
  IF lv_other > 0.
    APPEND |<div class="legend"><span class="dot" style="background:#94a3b8"></span>Other&nbsp;&nbsp;<b>{ lv_other }</b></div>| TO pt_html.
  ENDIF.
  APPEND '</td></tr></table></td>' TO pt_html.

  APPEND '<td width="50%" class="panel"><div class="pt">Processing Summary</div>' TO pt_html.
  APPEND '<div class="ps">Overall execution progress and proven scope metrics</div>' TO pt_html.
  APPEND |<div style="font-size:10px;color:#475569;margin-bottom:5px">Processed <b>{ lv_processed_c } / { lv_total_c }</b> ({ lv_proc_pct }%)</div>| TO pt_html.
  APPEND |<div class="track" style="margin-bottom:12px"><div class="fill" style="width:{ lv_proc_pct }%;background:#2f80ed"></div></div>| TO pt_html.
  APPEND '<table class="split"><tr><td width="50%" style="vertical-align:top">' TO pt_html.
  APPEND '<table class="metric">' TO pt_html.
  APPEND |<tr><td>Total Groups</td><td>{ lv_total_c }</td></tr>| TO pt_html.
  APPEND |<tr><td>Processed</td><td>{ lv_processed_c }</td></tr>| TO pt_html.
  APPEND |<tr><td>Remaining</td><td>{ lv_remaining_c }</td></tr>| TO pt_html.
  APPEND |<tr><td>Items Processed</td><td>{ lv_proc_items_c }</td></tr>| TO pt_html.
  APPEND '</table></td><td width="50%" style="vertical-align:top">' TO pt_html.
  APPEND '<table class="metric">' TO pt_html.
  APPEND |<tr><td>Avg. Processing Rate</td><td>{ lv_rate_txt }</td></tr>| TO pt_html.
  APPEND |<tr><td>Estimated Remaining</td><td>{ lv_est_txt }</td></tr>| TO pt_html.
  APPEND |<tr><td>Elapsed Time</td><td>{ lv_elapsed_txt }</td></tr>| TO pt_html.
  APPEND |<tr><td>Items in Scope</td><td>{ lv_items_c }</td></tr>| TO pt_html.
  APPEND '</table></td></tr></table>' TO pt_html.
  APPEND '</td></tr>' TO pt_html.

  APPEND '</table>' TO pt_html.

  APPEND '<div class="detail"><div class="pt">Group Details</div>' TO pt_html.
  APPEND '<div class="ps">Business Groups in the current dashboard scope</div>' TO pt_html.
  APPEND '<table class="tools"><tr>' TO pt_html.
  APPEND '<td width="40%"><div class="tl">Business Group</div><input id="qGroup" class="inp" type="text" placeholder="Search Business Group..." onkeyup="F()"></td>' TO pt_html.
  APPEND '<td width="20%"><div class="tl">TCode</div><select id="fTcode" class="sel" onchange="F()"><option value="">All</option></select></td>' TO pt_html.
  APPEND '<td width="20%"><div class="tl">Status</div><select id="fStatus" class="sel" onchange="F()"><option value="">All</option></select></td>' TO pt_html.
  APPEND '<td width="20%"><div class="tl">Execution</div><select id="fExec" class="sel" onchange="F()"><option value="">All</option></select></td>' TO pt_html.
  APPEND '</tr></table>' TO pt_html.
  APPEND '<table class="tbl"><thead><tr>' TO pt_html.
  APPEND '<th style="width:26%">Business Group</th><th style="width:14%">TCode</th>' TO pt_html.
  APPEND '<th style="width:20%">Status</th><th style="width:20%">Execution</th>' TO pt_html.
  APPEND '<th style="width:20%">Last Update</th></tr></thead><tbody id="gBody"></tbody></table>' TO pt_html.
  APPEND '<table class="tablefoot"><tr><td id="pageInfo" class="pageinfo"></td><td id="pager" class="pager"></td></tr></table></div>' TO pt_html.
  APPEND '<script>var R=[];' TO pt_html.

  LOOP AT lt_dash_rows_830 INTO ls_dash_row_830.
    DATA(lv_js_group_830) = CONV string( ls_dash_row_830-group_key ).
    DATA(lv_js_tcode_830) = CONV string( ls_dash_row_830-tcode ).
    DATA(lv_js_status_830) = CONV string( ls_dash_row_830-status ).
    DATA(lv_js_exec_830) = CONV string( ls_dash_row_830-execution ).
    DATA(lv_js_time_830) = CONV string( ls_dash_row_830-last_update ).
    PERFORM js_escape CHANGING lv_js_group_830.
    PERFORM js_escape CHANGING lv_js_tcode_830.
    PERFORM js_escape CHANGING lv_js_status_830.
    PERFORM js_escape CHANGING lv_js_exec_830.
    PERFORM js_escape CHANGING lv_js_time_830.
    APPEND |R.push(["{ lv_js_group_830 }","{ lv_js_tcode_830 }","{ lv_js_status_830 }","{ lv_js_exec_830 }","{ lv_js_time_830 }"]);| TO pt_html.
  ENDLOOP.
  APPEND 'var P=1,S=5,Q=[];' TO pt_html.
  APPEND 'function H(v){v=String(v==null?"":v);return v.replace(/&/g,"&amp;").replace(/</g,"&lt;").replace(/>/g,"&gt;").replace(/"/g,"&quot;");}' TO pt_html.
  APPEND 'function U(i){var o={},a=[],k,v;for(k=0;k<R.length;k++){v=R[k][i];if(v&&!o[v]){o[v]=1;a.push(v);}}a.sort();return a;}' TO pt_html.
  APPEND 'function FS(id,i){var e=document.getElementById(id),a=U(i),k,o;for(k=0;k<a.length;k++){o=document.createElement("option");o.value=a[k];o.text=a[k];e.appendChild(o);}}' TO pt_html.
  APPEND 'function SC(s){s=String(s).toUpperCase();if(s.indexOf("SUCCESS")>=0||s=="PROCESSED")return"st-success";if(s.indexOf("READY")>=0)return"st-ready";' TO pt_html.
  APPEND 'if(s.indexOf("WARN")>=0||s.indexOf("PARTIAL")>=0)return"st-warning";if(s.indexOf("ERROR")>=0||s.indexOf("TIMEOUT")>=0||s.indexOf("BLOCK")>=0)return"st-error";' TO pt_html.
  APPEND 'if(s.indexOf("SM35")>=0||s.indexOf("QUEUE")>=0)return"st-queue";if(s.indexOf("RUN")>=0||s.indexOf("PROCESS")>=0||s.indexOf("VERIFY")>=0)return"st-running";return"st-neutral";}' TO pt_html.
  APPEND 'function F(){var q=document.getElementById("qGroup").value.toLowerCase(),t=document.getElementById("fTcode").value,s=document.getElementById("fStatus").value,e=document.getElementById("fExec").value,i,r;Q=[];' TO pt_html.
  APPEND 'for(i=0;i<R.length;i++){r=R[i];if(q&&String(r[0]).toLowerCase().indexOf(q)<0)continue;if(t&&r[1]!=t)continue;if(s&&r[2]!=s)continue;if(e&&r[3]!=e)continue;Q.push(r);}P=1;T();}' TO pt_html.
  APPEND 'function G(n){var z=Math.max(1,Math.ceil(Q.length/S));if(n<1||n>z)return;P=n;T();}' TO pt_html.
  APPEND 'function PB(n,c,d){return"<span class="pg"+(c?" on":"")+(d?" off":"")+"""+(d?"":" onclick="G("+n+")"")+">"+n+"</span>";}' TO pt_html.
  APPEND 'function PA(z){var a=[],i;if(z<=5){for(i=1;i<=z;i++)a.push(i);}else if(P<=3){a=[1,2,3,"...",z];}else if(P>=z-2){a=[1,"...",z-2,z-1,z];}else{a=[1,"...",P-1,P,P+1,"...",z];}return a;}' TO pt_html.
  APPEND 'function T(){var b=document.getElementById("gBody"),pi=document.getElementById("pageInfo"),pg=document.getElementById("pager"),z=Math.max(1,Math.ceil(Q.length/S)),a=(P-1)*S,c=Math.min(a+S,Q.length),i,r,h="";' TO pt_html.
  APPEND 'if(P>z)P=z;a=(P-1)*S;c=Math.min(a+S,Q.length);' TO pt_html.
  APPEND 'for(i=a;i<c;i++){r=Q[i];h+="<tr><td title=""+H(r[0])+"">"+H(r[0])+"</td><td>"+H(r[1])+"</td>";' TO pt_html.
  APPEND 'h+="<td><span class="badge "+SC(r[2])+"">"+H(r[2])+"</span></td><td>"+H(r[3])+"</td><td>"+H(r[4])+"</td></tr>";}' TO pt_html.
  APPEND 'if(!Q.length)h="<tr><td colspan="5" style="text-align:center;color:#94a3b8">No groups match the current search and filters.</td></tr>";b.innerHTML=h;' TO pt_html.
  APPEND 'pi.innerHTML=Q.length?("Showing "+(a+1)+"-"+c+" of "+Q.length+" groups"):"Showing 0 groups";var x="",p=PA(z),k;' TO pt_html.
  APPEND 'x+="<span class="pg"+(P==1?" off":"")+"""+(P==1?"":" onclick="G("+(P-1)+")"")+">Prev</span>";' TO pt_html.
  APPEND 'for(k=0;k<p.length;k++){if(p[k]=="...")x+="<span class="dots">...</span>";else x+=PB(p[k],p[k]==P,false);}x+="<span class="pg"+(P==z?" off":"")+"""+(P==z?"":" onclick="G("+(P+1)+")"")+">Next</span>";pg.innerHTML=x;}' TO pt_html.
  APPEND 'function D(){var c=document.getElementById("donut"),x=c.getContext("2d");' TO pt_html.
  APPEND |var v=[{ lv_ready_c },{ lv_running_c },{ lv_success_c },{ lv_warning_c },{ lv_error_c },{ lv_queue_c },{ lv_other }];| TO pt_html.
  APPEND 'var col=["#2f80ed","#06b6d4","#22a06b","#f5a623","#e5484d","#8b5cf6","#94a3b8"];' TO pt_html.
  APPEND 'var t=0,i;for(i=0;i<v.length;i++)t+=v[i];var a=-Math.PI/2;' TO pt_html.
  APPEND 'for(i=0;i<v.length;i++){if(!t||!v[i])continue;var b=a+(Math.PI*2*v[i]/t);' TO pt_html.
  APPEND 'x.beginPath();x.arc(135,105,78,a,b);x.arc(135,105,47,b,a,true);x.closePath();x.fillStyle=col[i];x.fill();a=b;}' TO pt_html.
  APPEND 'x.fillStyle="#153e75";x.font="bold 24px Arial";x.textAlign="center";x.fillText(t,135,102);' TO pt_html.
  IF gv_dash_scope_source_826 = 'SESSION_ALL'.
    APPEND 'x.font="11px Arial";x.fillStyle="#64748b";x.fillText("groups",135,121);}' TO pt_html.
  ELSE.
    APPEND 'x.font="11px Arial";x.fillStyle="#64748b";x.fillText("selected groups",135,121);}' TO pt_html.
  ENDIF.
  APPEND 'FS("fTcode",1);FS("fStatus",2);FS("fExec",3);Q=R.slice(0);D();T();' TO pt_html.
  APPEND '</script></div></body></html>' TO pt_html.
ENDFORM.

FORM show_visual_dash CHANGING cv_ok TYPE abap_bool.
  DATA lt_html TYPE ty_t_dash_html_411.
  DATA lv_dash_caption_829 TYPE c LENGTH 60.

  CLEAR cv_ok.

  PERFORM free_visual_dash.
  PERFORM build_visual_html CHANGING lt_html.
  IF lt_html IS INITIAL.
    RETURN.
  ENDIF.

 "keep the native dialog fully above the Windows taskbar and make
 "the HTML viewer own vertical scrolling. One renderer is shared by both
 "the 0400 all-session Result Dashboard and the 0500 selected-scope view.
  IF gv_dash_scope_source_826 = 'SESSION_ALL'.
    lv_dash_caption_829 = 'BDC Result Dashboard - Session Overview'.
  ELSE.
    lv_dash_caption_829 = 'BDC Result Dashboard - Selected Scope'.
  ENDIF.

  CREATE OBJECT go_dash_411_dlg
    EXPORTING
      width   = 1080
      height  = 440
      top     = 10
      left    = 25
      caption = lv_dash_caption_829
    EXCEPTIONS
      cntl_error = 1
      OTHERS     = 2.
  IF sy-subrc <> 0 OR go_dash_411_dlg IS NOT BOUND.
    PERFORM free_visual_dash.
    RETURN.
  ENDIF.

  CREATE OBJECT go_dash_evt_411.
  SET HANDLER go_dash_evt_411->on_dialog_close FOR go_dash_411_dlg.

  CREATE OBJECT go_dash_411_html
    EXPORTING
      parent = go_dash_411_dlg
    EXCEPTIONS
      cntl_error = 1
      OTHERS     = 2.
  IF sy-subrc <> 0 OR go_dash_411_html IS NOT BOUND.
    PERFORM free_visual_dash.
    RETURN.
  ENDIF.

  CLEAR gv_dash_411_url.
  CALL METHOD go_dash_411_html->load_data
    EXPORTING
      type         = 'text'
      subtype      = 'html'
    IMPORTING
      assigned_url = gv_dash_411_url
    CHANGING
      data_table   = lt_html
    EXCEPTIONS
      dp_invalid_parameter = 1
      dp_error_general     = 2
      cntl_error           = 3
      OTHERS               = 4.
  IF sy-subrc <> 0 OR gv_dash_411_url IS INITIAL.
    PERFORM free_visual_dash.
    RETURN.
  ENDIF.

  CALL METHOD go_dash_411_html->show_url
    EXPORTING
      url      = gv_dash_411_url
      in_place = 'X'
    EXCEPTIONS
      cntl_error             = 1
      cnht_error_not_allowed = 2
      cnht_error_parameter   = 3
      dp_error_general       = 4
      OTHERS                 = 5.
  IF sy-subrc <> 0.
    PERFORM free_visual_dash.
    RETURN.
  ENDIF.

  CALL METHOD cl_gui_cfw=>flush
    EXCEPTIONS
      cntl_system_error = 1
      cntl_error        = 2
      OTHERS            = 3.

  cv_ok = abap_true.
ENDFORM.

FORM show_result_dash_safe.
  DATA lo_alv  TYPE REF TO cl_salv_table.
  DATA lo_cols TYPE REF TO cl_salv_columns_table.
  DATA lx_msg  TYPE REF TO cx_salv_msg.
  DATA lv_visual_ok TYPE abap_bool.

 "the caller already captured an exact selected-group scope.
 "Never rebuild this popup from all session rows.
  IF gt_result_summary IS INITIAL AND gt_dash_scope_826 IS NOT INITIAL.
    PERFORM build_selected_summary.
  ENDIF.

  IF gt_result_summary IS INITIAL.
    MESSAGE s611(zbdc) DISPLAY LIKE 'W'.
    RETURN.
  ENDIF.

 "primary surface: professional dynamic HTML charts.
  CLEAR lv_visual_ok.
  PERFORM show_visual_dash CHANGING lv_visual_ok.
  IF lv_visual_ok = abap_true.
    RETURN.
  ENDIF.

 "Fallback only: preserve the existing SALV evidence view if the frontend
 "HTML control is unavailable on a specific SAP GUI installation.
  PERFORM build_dash_cards.
  IF gt_result_cards IS INITIAL.
    MESSAGE s611(zbdc) DISPLAY LIKE 'W'.
    RETURN.
  ENDIF.

  TRY.
      cl_salv_table=>factory(
        IMPORTING
          r_salv_table = lo_alv
        CHANGING
          t_table      = gt_result_cards ).

      lo_alv->get_functions( )->set_all( abap_true ).
      lo_alv->get_display_settings( )->set_list_header(
        'BDC Result Dashboard - Enterprise Evidence View' ).
      lo_alv->get_display_settings( )->set_striped_pattern( abap_true ).
      lo_cols = lo_alv->get_columns( ).
      lo_cols->set_optimize( abap_true ).

      PERFORM set_dash_col_text USING lo_cols 'SECTION'     'Block'.
      PERFORM set_dash_col_text USING lo_cols 'METRIC'      'Metric'.
      PERFORM set_dash_col_text USING lo_cols 'VALUE'       'Value'.
      PERFORM set_dash_col_text USING lo_cols 'DETAIL'      'Evidence Detail'.
      PERFORM set_dash_col_text USING lo_cols 'STATUS_TEXT' 'Overall Status'.
      PERFORM set_dash_col_text USING lo_cols 'NEXT_ACTION' 'Next Action'.

      lo_alv->display( ).
    CATCH cx_salv_msg INTO lx_msg.
      MESSAGE lx_msg->get_text( ) TYPE 'S' DISPLAY LIKE 'E'.
  ENDTRY.
ENDFORM.

* Runtime issue detail popup

* Screen 0560 - selected-group correction workflow ()

FORM reset_0560.
  CLEAR: p_bus_group, p_fld_name, p_old_val, p_new_val,
         gv_0560_prepared, gv_0560_last_group,
         gv_0560_last_field, gv_0560_group_count.
  REFRESH: gt_0560_map, gt_0560_groups,
           gt_0560_ready_done, gt_0560_old_opt.
ENDFORM.

FORM get_active_group
  CHANGING cs_key     TYPE ty_engine_group_key
           cv_ok      TYPE abap_bool
           cv_message TYPE string.

  CLEAR: cs_key, cv_ok, cv_message.
  IF gt_0560_groups IS INITIAL.
    cv_message = 'Retry correction has no selected failed-group scope.'.
    RETURN.
  ENDIF.

  IF p_bus_group IS INITIAL.
    READ TABLE gt_0560_groups INTO cs_key INDEX 1.
    IF sy-subrc = 0.
      p_bus_group = cs_key-record_key.
    ENDIF.
  ELSE.
    READ TABLE gt_0560_groups INTO cs_key
      WITH KEY record_key = p_bus_group.
  ENDIF.

  IF sy-subrc <> 0 OR cs_key-record_key IS INITIAL.
    cv_message = 'Choose a Business Group from the selected Retry scope.'.
    RETURN.
  ENDIF.

  cv_ok = abap_true.
ENDFORM.

FORM build_group_options
  CHANGING ct_vrm TYPE vrm_values.

  DATA: ls_key TYPE ty_engine_group_key,
        ls_vrm TYPE vrm_value.

  REFRESH ct_vrm.
  LOOP AT gt_0560_groups INTO ls_key.
    IF ls_key-record_key IS INITIAL.
      CONTINUE.
    ENDIF.
    CLEAR ls_vrm.
    ls_vrm-key  = ls_key-record_key.
    ls_vrm-text = ls_key-record_key.
    APPEND ls_vrm TO ct_vrm.
  ENDLOOP.

  IF p_bus_group IS INITIAL.
    READ TABLE gt_0560_groups INTO ls_key INDEX 1.
    IF sy-subrc = 0.
      p_bus_group = ls_key-record_key.
    ENDIF.
  ENDIF.
ENDFORM.

FORM load_0560_map
  CHANGING cv_ok      TYPE abap_bool
           cv_message TYPE string.

  DATA: lv_tcode       TYPE zbdc_prof_bup-tcode,
        lv_profile     TYPE zbdc_prof_bup-profile_name,
        lv_ver         TYPE zbdc_prof_bup-profile_ver,
        lv_found       TYPE abap_bool,
        lv_technical   TYPE abap_bool,
        ls_probe       TYPE zbdc_staging_bup,
        ls_key         TYPE ty_engine_group_key,
        ls_exec        TYPE ty_exec_disp.
  FIELD-SYMBOLS <lv_probe> TYPE any.

  CLEAR: cv_ok, cv_message.
  REFRESH gt_0560_map.

  PERFORM get_active_group
    CHANGING ls_key lv_found cv_message.
  IF lv_found <> abap_true.
    RETURN.
  ENDIF.

  txtp_result_session = ls_key-session_id.
  txtp_po_key         = ls_key-record_key.
  CLEAR: txtp_result_msg, txtp_sap_object_id, g_edit_index.

  READ TABLE gt_exec_disp INTO ls_exec
    WITH KEY session_id = ls_key-session_id group_key = ls_key-record_key.
  IF sy-subrc = 0.
    txtp_result_msg    = ls_exec-message.
    txtp_sap_object_id = ls_exec-sap_object_id.
  ENDIF.
  READ TABLE gt_staging_alv TRANSPORTING NO FIELDS
    WITH KEY session_id = ls_key-session_id record_key = ls_key-record_key.
  IF sy-subrc = 0.
    g_edit_index = sy-tabix.
  ENDIF.

  PERFORM resolve_edit_context
    USING    ls_key-session_id
    CHANGING lv_tcode lv_profile lv_ver lv_found cv_message.
  IF lv_found <> abap_true.
    IF cv_message IS INITIAL.
      cv_message = 'The exact TCode/Profile/Version mapping context for this Business Group is unavailable.'.
    ENDIF.
    RETURN.
  ENDIF.

  SELECT SINGLE * FROM zbdc_staging_bup INTO @ls_probe
    WHERE session_id = @ls_key-session_id
      AND record_key = @ls_key-record_key.
  IF sy-subrc <> 0.
    cv_message = |Business Group { ls_key-record_key } no longer exists in staging.|.
    RETURN.
  ENDIF.
  IF ls_probe-tcode <> lv_tcode.
    cv_message = |Business Group { ls_key-record_key } does not match its persisted TCode context.|.
    RETURN.
  ENDIF.
  IF ls_probe-status <> gc_st_error.
    cv_message = |Retry is available only while Business Group { ls_key-record_key } is ERROR (current: { ls_probe-status }).|.
    RETURN.
  ENDIF.

  SELECT * FROM zbdc_mapping_bup INTO TABLE @gt_0560_map
    WHERE tcode        = @lv_tcode
      AND profile_name = @lv_profile
      AND profile_ver  = @lv_ver.

  DELETE gt_0560_map WHERE staging_field IS INITIAL OR source_column IS INITIAL.

  LOOP AT gt_0560_map ASSIGNING FIELD-SYMBOL(<ls_map>).
    CLEAR lv_technical.
    PERFORM mapping_source_is_technical
      USING    <ls_map>-source_column <ls_map>-bdc_field
      CHANGING lv_technical.
    IF lv_technical = abap_true.
      DELETE gt_0560_map.
      CONTINUE.
    ENDIF.

    UNASSIGN <lv_probe>.
    ASSIGN COMPONENT <ls_map>-staging_field OF STRUCTURE ls_probe TO <lv_probe>.
    IF sy-subrc <> 0 OR <lv_probe> IS NOT ASSIGNED.
      DELETE gt_0560_map.
      CONTINUE.
    ENDIF.
  ENDLOOP.

  SORT gt_0560_map BY staging_field source_column bdc_field.
  DELETE ADJACENT DUPLICATES FROM gt_0560_map COMPARING staging_field.

  IF gt_0560_map IS INITIAL.
    cv_message = 'The frozen mapping contains no editable source field for this Business Group.'.
    RETURN.
  ENDIF.

  cv_ok = abap_true.
ENDFORM.

FORM pick_0560_field
  CHANGING cv_field TYPE char30.

  DATA: lt_res        TYPE STANDARD TABLE OF zbdc_result_bup,
        ls_res        TYPE zbdc_result_bup,
        lv_issue      TYPE zbdc_result_bup-field_name,
        lv_issue_norm TYPE zbdc_mapping_bup-bdc_field,
        lv_map_norm   TYPE zbdc_mapping_bup-bdc_field,
        lv_candidate  TYPE char30,
        lv_ambiguous  TYPE abap_bool,
        lv_internal   TYPE abap_bool.

  CLEAR cv_field.
  IF gt_0560_map IS INITIAL OR txtp_po_key IS INITIAL.
    RETURN.
  ENDIF.

  SELECT * FROM zbdc_result_bup INTO TABLE @lt_res
    WHERE session_id = @txtp_result_session
      AND record_key = @txtp_po_key.
  SORT lt_res BY step DESCENDING.

  LOOP AT lt_res INTO ls_res.
    IF txtp_result_msg IS INITIAL OR ls_res-message <> txtp_result_msg OR
       ls_res-field_name IS INITIAL.
      CONTINUE.
    ENDIF.
    lv_issue = ls_res-field_name.
    EXIT.
  ENDLOOP.

  IF lv_issue IS INITIAL.
    LOOP AT lt_res INTO ls_res.
      IF ls_res-field_name IS INITIAL.
        CONTINUE.
      ENDIF.
      IF ls_res-msg_type = 'E' OR ls_res-msg_type = 'A' OR
         ls_res-msg_type = 'X' OR ls_res-msg_type = 'W' OR
         ls_res-exec_status = gc_st_error OR
         ls_res-exec_status = gc_st_warning OR
         ls_res-exec_status = gc_st_partial.
        lv_issue = ls_res-field_name.
        EXIT.
      ENDIF.
    ENDLOOP.
  ENDIF.
  IF lv_issue IS INITIAL.
    RETURN.
  ENDIF.

  CLEAR lv_internal.
  CASE lv_issue.
    WHEN 'ENGINE' OR 'DB_PROOF' OR 'SAP_PROTO_PROOF' OR
         'SM35_BIND' OR 'SM35' OR 'SM35_PREOBJ' OR 'SM35_PRESET' OR
         'Z264_MARK' OR 'STAGING' OR 'OBJ_RESOLVE'.
      lv_internal = abap_true.
  ENDCASE.
  IF lv_internal = abap_true.
    RETURN.
  ENDIF.

  READ TABLE gt_0560_map INTO DATA(ls_direct)
    WITH KEY staging_field = lv_issue.
  IF sy-subrc = 0.
    cv_field = ls_direct-staging_field.
    RETURN.
  ENDIF.

  CLEAR: lv_candidate, lv_ambiguous.
  LOOP AT gt_0560_map INTO DATA(ls_src_map) WHERE source_column = lv_issue.
    IF lv_candidate IS INITIAL.
      lv_candidate = ls_src_map-staging_field.
    ELSEIF lv_candidate <> ls_src_map-staging_field.
      lv_ambiguous = abap_true.
      EXIT.
    ENDIF.
  ENDLOOP.
  IF lv_candidate IS NOT INITIAL AND lv_ambiguous <> abap_true.
    cv_field = lv_candidate.
    RETURN.
  ENDIF.

  CLEAR: lv_candidate, lv_ambiguous.
  PERFORM normalize_mapping_bdc_field USING lv_issue CHANGING lv_issue_norm.
  IF lv_issue_norm IS INITIAL.
    RETURN.
  ENDIF.

  LOOP AT gt_0560_map INTO DATA(ls_map).
    CLEAR lv_map_norm.
    PERFORM normalize_mapping_bdc_field
      USING ls_map-bdc_field CHANGING lv_map_norm.
    IF lv_map_norm <> lv_issue_norm.
      CONTINUE.
    ENDIF.
    IF lv_candidate IS INITIAL.
      lv_candidate = ls_map-staging_field.
    ELSEIF lv_candidate <> ls_map-staging_field.
      lv_ambiguous = abap_true.
      EXIT.
    ENDIF.
  ENDLOOP.
  IF lv_ambiguous <> abap_true.
    cv_field = lv_candidate.
  ENDIF.
ENDFORM.

FORM build_old_options
  USING    iv_field TYPE char30
  CHANGING ct_vrm   TYPE vrm_values.

  DATA: ls_key      TYPE ty_engine_group_key,
        lt_db       TYPE STANDARD TABLE OF zbdc_staging_bup,
        ls_db       TYPE zbdc_staging_bup,
        ls_opt      TYPE ty_0560_old_opt,
        ls_vrm      TYPE vrm_value,
        lv_value    TYPE string,
        lv_seq      TYPE i,
        lv_seq_txt  TYPE char10,
        lv_key_cap  TYPE i,
        lv_val_len  TYPE i,
        lv_ok       TYPE abap_bool,
        lv_msg      TYPE string.
  FIELD-SYMBOLS <lv_any> TYPE any.

  REFRESH: gt_0560_old_opt, ct_vrm.
  IF iv_field IS INITIAL.
    RETURN.
  ENDIF.

  PERFORM get_active_group
    CHANGING ls_key lv_ok lv_msg.
  IF lv_ok <> abap_true.
    RETURN.
  ENDIF.

  DESCRIBE FIELD ls_vrm-key LENGTH lv_key_cap IN CHARACTER MODE.
  SELECT * FROM zbdc_staging_bup INTO TABLE @lt_db
    WHERE session_id = @ls_key-session_id
      AND record_key = @ls_key-record_key.

  LOOP AT lt_db INTO ls_db.
    UNASSIGN <lv_any>.
    ASSIGN COMPONENT iv_field OF STRUCTURE ls_db TO <lv_any>.
    IF sy-subrc <> 0 OR <lv_any> IS NOT ASSIGNED.
      CONTINUE.
    ENDIF.
    lv_value = |{ <lv_any> }|.
    READ TABLE gt_0560_old_opt TRANSPORTING NO FIELDS WITH KEY value = lv_value.
    IF sy-subrc = 0.
      CONTINUE.
    ENDIF.

    lv_seq = lv_seq + 1.
    CLEAR: ls_opt, lv_seq_txt, lv_val_len.
    IF lv_value IS INITIAL.
      WRITE lv_seq TO lv_seq_txt LEFT-JUSTIFIED.
      CONDENSE lv_seq_txt NO-GAPS.
      CONCATENATE '__BLANK_' lv_seq_txt INTO ls_opt-key.
      ls_opt-text = '<blank>'.
    ELSE.
      lv_val_len = strlen( lv_value ).
      IF lv_val_len <= lv_key_cap.
        ls_opt-key = lv_value.
      ELSE.
        WRITE lv_seq TO lv_seq_txt LEFT-JUSTIFIED.
        CONDENSE lv_seq_txt NO-GAPS.
        CONCATENATE '#V' lv_seq_txt INTO ls_opt-key.
      ENDIF.
      ls_opt-text = lv_value.
    ENDIF.
    ls_opt-value = lv_value.
    APPEND ls_opt TO gt_0560_old_opt.
  ENDLOOP.

  LOOP AT gt_0560_old_opt INTO ls_opt.
    CLEAR ls_vrm.
    ls_vrm-key  = ls_opt-key.
    ls_vrm-text = ls_opt-text.
    APPEND ls_vrm TO ct_vrm.
  ENDLOOP.
ENDFORM.

FORM decode_old_value
  USING    iv_key   TYPE char80
  CHANGING cv_found TYPE abap_bool
           cv_value TYPE string.

  CLEAR: cv_found, cv_value.

  READ TABLE gt_0560_old_opt INTO DATA(ls_opt) WITH KEY key = iv_key.
  IF sy-subrc = 0.
    cv_found = abap_true.
    cv_value = ls_opt-value.
    RETURN.
  ENDIF.

  READ TABLE gt_0560_old_opt INTO ls_opt WITH KEY value = iv_key.
  IF sy-subrc = 0.
    cv_found = abap_true.
    cv_value = ls_opt-value.
    RETURN.
  ENDIF.

  IF iv_key IS INITIAL.
    READ TABLE gt_0560_old_opt INTO ls_opt WITH KEY value = space.
    IF sy-subrc = 0.
      cv_found = abap_true.
      CLEAR cv_value.
    ENDIF.
  ENDIF.
ENDFORM.

FORM prepare_0560_pbo.
  DATA: lv_ok         TYPE abap_bool,
        lv_msg        TYPE string,
        lt_groups     TYPE vrm_values,
        lt_fields     TYPE vrm_values,
        lt_old        TYPE vrm_values,
        ls_value      TYPE vrm_value,
        lv_group_id   TYPE vrm_id VALUE 'P_BUS_GROUP',
        lv_field_id   TYPE vrm_id VALUE 'P_FLD_NAME',
        lv_old_id     TYPE vrm_id VALUE 'P_OLD_VAL',
        lv_text       TYPE string.

  PERFORM build_group_options CHANGING lt_groups.
  CALL FUNCTION 'VRM_SET_VALUES'
    EXPORTING id = lv_group_id values = lt_groups
    EXCEPTIONS id_illegal_name = 1 OTHERS = 2.

  IF p_bus_group <> gv_0560_last_group.
    CLEAR: p_fld_name, p_old_val, p_new_val,
           gv_0560_prepared, gv_0560_last_field.
    REFRESH: gt_0560_map, gt_0560_old_opt.
    gv_0560_last_group = p_bus_group.
  ENDIF.

  IF gv_0560_prepared <> abap_true.
    PERFORM load_0560_map CHANGING lv_ok lv_msg.
    IF lv_ok = abap_true.
      PERFORM pick_0560_field CHANGING p_fld_name.
    ELSEIF lv_msg IS NOT INITIAL.
      MESSAGE lv_msg TYPE 'S' DISPLAY LIKE 'E'.
    ENDIF.
    gv_0560_prepared = abap_true.
  ENDIF.

  REFRESH lt_fields.
  LOOP AT gt_0560_map INTO DATA(ls_map).
    CLEAR: ls_value, lv_text.
    ls_value-key = ls_map-staging_field.
    lv_text = ls_map-source_column.
    IF ls_map-bdc_field IS NOT INITIAL.
      lv_text = |{ lv_text } [{ ls_map-bdc_field }]|.
    ENDIF.
    ls_value-text = lv_text.
    APPEND ls_value TO lt_fields.
  ENDLOOP.

  IF p_fld_name IS INITIAL.
    READ TABLE lt_fields INTO ls_value INDEX 1.
    IF sy-subrc = 0.
      p_fld_name = ls_value-key.
    ENDIF.
  ENDIF.

  CALL FUNCTION 'VRM_SET_VALUES'
    EXPORTING id = lv_field_id values = lt_fields
    EXCEPTIONS id_illegal_name = 1 OTHERS = 2.

  IF p_fld_name <> gv_0560_last_field OR gt_0560_old_opt IS INITIAL.
    CLEAR p_old_val.
    PERFORM build_old_options USING p_fld_name CHANGING lt_old.
    READ TABLE gt_0560_old_opt INTO DATA(ls_first_old) INDEX 1.
    IF sy-subrc = 0.
      p_old_val = ls_first_old-key.
    ENDIF.
    gv_0560_last_field = p_fld_name.
  ELSE.
    REFRESH lt_old.
    LOOP AT gt_0560_old_opt INTO DATA(ls_old_opt).
      CLEAR ls_value.
      ls_value-key  = ls_old_opt-key.
      ls_value-text = ls_old_opt-text.
      APPEND ls_value TO lt_old.
    ENDLOOP.
  ENDIF.

  CALL FUNCTION 'VRM_SET_VALUES'
    EXPORTING id = lv_old_id values = lt_old
    EXCEPTIONS id_illegal_name = 1 OTHERS = 2.
ENDFORM.

FORM select_0500_keys
  USING it_keys TYPE ty_t_engine_group_key.

  DATA: lt_rows TYPE lvc_t_row,
        ls_row  TYPE lvc_s_row,
        ls_key  TYPE ty_engine_group_key.

  IF go_grid_0500 IS NOT BOUND.
    RETURN.
  ENDIF.

  LOOP AT gt_exec_disp INTO DATA(ls_exec).
    READ TABLE it_keys INTO ls_key
      WITH KEY session_id = ls_exec-session_id record_key = ls_exec-group_key.
    IF sy-subrc = 0.
      CLEAR ls_row.
      ls_row-index = sy-tabix.
      APPEND ls_row TO lt_rows.
    ENDIF.
  ENDLOOP.

  TRY.
      CALL METHOD go_grid_0500->set_selected_rows
        EXPORTING it_index_rows = lt_rows.
      CALL METHOD go_grid_0500->refresh_table_display.
    CATCH cx_root.
  ENDTRY.
ENDFORM.

FORM apply_correction.
  DATA: lv_map_ok         TYPE abap_bool,
        lv_old_found      TYPE abap_bool,
        lv_old_text       TYPE string,
        lv_new_text       TYPE string,
        lv_field_len      TYPE i,
        lv_new_len        TYPE i,
        lv_msg            TYPE string,
        lt_db             TYPE STANDARD TABLE OF zbdc_staging_bup,
        lt_group          TYPE ty_t_staging_alv,
        lt_valid          TYPE ty_t_staging_alv,
        lt_group_update   TYPE STANDARD TABLE OF zbdc_staging_bup,
        ls_key            TYPE ty_engine_group_key,
        ls_db             TYPE zbdc_staging_bup,
        ls_current        TYPE zbdc_staging_bup,
        ls_update         TYPE zbdc_staging_bup,
        ls_group          TYPE ty_staging_alv,
        ls_valid          TYPE ty_staging_alv,
        lv_group_match    TYPE i,
        lv_total_rows     TYPE i,
        lv_ok             TYPE abap_bool,
        lv_selected_bad   TYPE abap_bool,
        lv_other_bad      TYPE abap_bool,
        lv_group_ready    TYPE abap_bool,
        lv_norm_new       TYPE string,
        lv_changed        TYPE abap_bool,
        lv_concurrent     TYPE abap_bool,
        lv_contract_ok    TYPE abap_bool,
        lv_contract_block TYPE abap_bool,
        lv_contract_msg   TYPE string,
        lv_remaining      TYPE i.
  FIELD-SYMBOLS: <lv_any>    TYPE any,
                 <lv_valid>  TYPE any,
                 <lv_update> TYPE any,
                 <ls_all>    TYPE ty_staging_alv,
                 <ls_raw>    TYPE zbdc_staging_bup.

  IF gt_0560_groups IS INITIAL.
    MESSAGE 'Correction is blocked: select failed group(s) and choose Retry first.'
      TYPE 'S' DISPLAY LIKE 'E'.
    RETURN.
  ENDIF.

  CLEAR lv_msg.
  PERFORM get_active_group
    CHANGING ls_key lv_ok lv_msg.
  IF lv_ok <> abap_true.
    MESSAGE lv_msg TYPE 'S' DISPLAY LIKE 'E'.
    RETURN.
  ENDIF.

  IF p_fld_name IS INITIAL.
    MESSAGE 'Choose Field to Replace.' TYPE 'S' DISPLAY LIKE 'E'.
    RETURN.
  ENDIF.

  IF gt_0560_map IS INITIAL.
    PERFORM load_0560_map CHANGING lv_ok lv_msg.
    IF lv_ok <> abap_true.
      MESSAGE lv_msg TYPE 'S' DISPLAY LIKE 'E'.
      RETURN.
    ENDIF.
  ENDIF.
  READ TABLE gt_0560_map TRANSPORTING NO FIELDS
    WITH KEY staging_field = p_fld_name.
  IF sy-subrc = 0.
    lv_map_ok = abap_true.
  ENDIF.
  IF lv_map_ok <> abap_true.
    MESSAGE 'The selected field is not an editable source field in the frozen mapping.'
      TYPE 'S' DISPLAY LIKE 'E'.
    RETURN.
  ENDIF.

  PERFORM decode_old_value
    USING p_old_val CHANGING lv_old_found lv_old_text.
  IF lv_old_found <> abap_true.
    MESSAGE 'Choose an Old Value from the values that exist in this Business Group.'
      TYPE 'S' DISPLAY LIKE 'E'.
    RETURN.
  ENDIF.

  lv_new_text = p_new_val.
  IF lv_old_text = lv_new_text.
    MESSAGE 'Old Value and New Value are identical; nothing was saved.'
      TYPE 'S' DISPLAY LIKE 'W'.
    RETURN.
  ENDIF.

  SELECT * FROM zbdc_staging_bup INTO TABLE @lt_db
    WHERE session_id = @ls_key-session_id
      AND record_key = @ls_key-record_key.
  IF lt_db IS INITIAL.
    MESSAGE 'The selected Business Group no longer exists in staging.'
      TYPE 'S' DISPLAY LIKE 'E'.
    RETURN.
  ENDIF.

  LOOP AT lt_db INTO ls_db.
    CLEAR ls_group.
    MOVE-CORRESPONDING ls_db TO ls_group.
    IF ls_group-status <> gc_st_error.
      MESSAGE 'Retry correction is available only while the selected Business Group is ERROR. Reopen Retry.'
        TYPE 'S' DISPLAY LIKE 'E'.
      RETURN.
    ENDIF.
    APPEND ls_group TO lt_group.
  ENDLOOP.

  LOOP AT lt_group ASSIGNING FIELD-SYMBOL(<ls_group_fix>).
    UNASSIGN <lv_any>.
    ASSIGN COMPONENT p_fld_name OF STRUCTURE <ls_group_fix> TO <lv_any>.
    IF sy-subrc <> 0 OR <lv_any> IS NOT ASSIGNED.
      MESSAGE 'The selected field is no longer available in the staging structure.'
        TYPE 'S' DISPLAY LIKE 'E'.
      RETURN.
    ENDIF.
    IF |{ <lv_any> }| = lv_old_text.
      CLEAR: lv_field_len, lv_new_len.
      DESCRIBE FIELD <lv_any> LENGTH lv_field_len IN CHARACTER MODE.
      lv_new_len = strlen( p_new_val ).
      IF lv_field_len > 0 AND lv_new_len > lv_field_len.
        lv_msg = |New Value is too long for { p_fld_name } ({ lv_new_len }; maximum { lv_field_len }).|.
        MESSAGE lv_msg TYPE 'S' DISPLAY LIKE 'E'.
        RETURN.
      ENDIF.
      <lv_any> = p_new_val.
      lv_group_match = lv_group_match + 1.
    ENDIF.
  ENDLOOP.

  IF lv_group_match = 0.
    MESSAGE 'The selected Old Value no longer exists for this field in this Business Group.'
      TYPE 'S' DISPLAY LIKE 'E'.
    RETURN.
  ENDIF.

  READ TABLE lt_group INTO DATA(ls_first) INDEX 1.

  PERFORM validate_retry_group
    USING lt_group CHANGING lt_valid lv_ok lv_msg.
  IF lv_ok = abap_true.
    lv_group_ready = abap_true.
  ELSE.
    LOOP AT lt_valid INTO DATA(ls_val_err) WHERE status = gc_st_error.
      LOOP AT ls_val_err-cell_colors INTO DATA(ls_val_color).
        IF ls_val_color-fname = p_fld_name.
          lv_selected_bad = abap_true.
        ELSEIF ls_val_color-fname IS NOT INITIAL.
          lv_other_bad = abap_true.
        ENDIF.
      ENDLOOP.
    ENDLOOP.

    IF lv_selected_bad = abap_true OR lv_other_bad <> abap_true.
      IF lv_msg IS INITIAL.
        lv_msg = 'The new value did not pass validation for the selected field; nothing was saved.'.
      ENDIF.
      MESSAGE lv_msg TYPE 'S' DISPLAY LIKE 'E'.
      RETURN.
    ENDIF.
  ENDIF.

  IF lv_group_ready = abap_true.
    CLEAR: lv_contract_ok, lv_contract_msg.
    PERFORM ensure_exec_contract
      USING    ls_key-session_id ls_first-tcode
      CHANGING lv_contract_ok lv_contract_msg.
    IF lv_contract_ok <> abap_true.
      lv_group_ready    = abap_false.
      lv_contract_block = abap_true.
      IF lv_contract_msg IS INITIAL.
        lv_contract_msg = 'Correction is valid, but the exact execution contract is not ready.'.
      ENDIF.
    ENDIF.
  ENDIF.

  LOOP AT lt_db INTO ls_db.
    CLEAR ls_current.
    SELECT SINGLE * FROM zbdc_staging_bup INTO @ls_current
      WHERE session_id = @ls_db-session_id
        AND row_index  = @ls_db-row_index.
    IF sy-subrc <> 0 OR ls_current <> ls_db.
      lv_concurrent = abap_true.
      EXIT.
    ENDIF.
  ENDLOOP.
  IF lv_concurrent = abap_true.
    ROLLBACK WORK.
    MESSAGE 'Correction validation became stale. Reopen Retry; nothing was saved.'
      TYPE 'S' DISPLAY LIKE 'E'.
    RETURN.
  ENDIF.

  LOOP AT lt_db INTO ls_db.
    ls_update = ls_db.
    CLEAR lv_changed.

    UNASSIGN <lv_any>.
    ASSIGN COMPONENT p_fld_name OF STRUCTURE ls_db TO <lv_any>.
    IF sy-subrc = 0 AND <lv_any> IS ASSIGNED AND |{ <lv_any> }| = lv_old_text.
      READ TABLE lt_valid INTO ls_valid
        WITH KEY session_id = ls_db-session_id row_index = ls_db-row_index.
      IF sy-subrc <> 0.
        ROLLBACK WORK.
        MESSAGE 'Validated correction rows no longer match staging; nothing was saved.'
          TYPE 'S' DISPLAY LIKE 'E'.
        RETURN.
      ENDIF.
      UNASSIGN <lv_valid>.
      ASSIGN COMPONENT p_fld_name OF STRUCTURE ls_valid TO <lv_valid>.
      UNASSIGN <lv_update>.
      ASSIGN COMPONENT p_fld_name OF STRUCTURE ls_update TO <lv_update>.
      IF sy-subrc <> 0 OR <lv_valid> IS NOT ASSIGNED OR <lv_update> IS NOT ASSIGNED.
        ROLLBACK WORK.
        MESSAGE 'The validated correction field could not be written safely; nothing was saved.'
          TYPE 'S' DISPLAY LIKE 'E'.
        RETURN.
      ENDIF.
      lv_norm_new = |{ <lv_valid> }|.
      PERFORM log_one_change
        USING ls_update-session_id ls_update-row_index ls_update-tcode
              p_fld_name lv_old_text lv_norm_new 'RETRY_CORRECTION'.
      <lv_update> = <lv_valid>.
      lv_changed = abap_true.
      lv_total_rows = lv_total_rows + 1.
    ENDIF.

    IF lv_group_ready = abap_true.
      ls_update-status = gc_st_ready.
      CLEAR: ls_update-error_msg, ls_update-last_error.
      lv_changed = abap_true.
    ELSEIF lv_contract_block = abap_true.
      ls_update-status     = gc_st_error.
      ls_update-error_msg  = lv_contract_msg.
      ls_update-last_error = lv_contract_msg.
      lv_changed = abap_true.
    ELSE.
      READ TABLE lt_valid INTO ls_valid
        WITH KEY session_id = ls_db-session_id row_index = ls_db-row_index.
      ls_update-status = gc_st_error.
      IF sy-subrc = 0 AND ls_valid-error_msg IS NOT INITIAL.
        ls_update-error_msg  = ls_valid-error_msg.
        ls_update-last_error = ls_valid-error_msg.
      ELSEIF lv_msg IS NOT INITIAL.
        ls_update-error_msg  = lv_msg.
        ls_update-last_error = lv_msg.
      ENDIF.
      lv_changed = abap_true.
    ENDIF.

    IF lv_changed = abap_true.
      APPEND ls_update TO lt_group_update.
    ENDIF.
  ENDLOOP.

  MODIFY zbdc_staging_bup FROM TABLE lt_group_update.
  IF sy-subrc <> 0.
    ROLLBACK WORK.
    MESSAGE 'Correction could not be saved to staging; no retry state was changed.'
      TYPE 'S' DISPLAY LIKE 'E'.
    RETURN.
  ENDIF.
  COMMIT WORK AND WAIT.

  LOOP AT lt_group_update INTO ls_update.
    READ TABLE gt_staging_alv ASSIGNING <ls_all>
      WITH KEY session_id = ls_update-session_id row_index = ls_update-row_index.
    IF sy-subrc = 0.
      MOVE-CORRESPONDING ls_update TO <ls_all>.
    ENDIF.
    READ TABLE gt_staging ASSIGNING <ls_raw>
      WITH KEY session_id = ls_update-session_id row_index = ls_update-row_index.
    IF sy-subrc = 0.
      <ls_raw> = ls_update.
    ENDIF.
  ENDLOOP.

  IF lv_group_ready = abap_true.
    PERFORM exec_q_set
      USING ls_key gc_st_ready
            'Correction saved and validation passed; choose CT or BISM to execute.' ''.
    READ TABLE gt_0560_ready_done TRANSPORTING NO FIELDS
      WITH KEY session_id = ls_key-session_id record_key = ls_key-record_key.
    IF sy-subrc <> 0.
      APPEND ls_key TO gt_0560_ready_done.
    ENDIF.
    DELETE gt_0560_groups
      WHERE session_id = ls_key-session_id AND record_key = ls_key-record_key.
  ELSE.
    IF lv_contract_block = abap_true.
      lv_msg = lv_contract_msg.
    ENDIF.
    IF lv_msg IS INITIAL.
      lv_msg = 'Correction saved, but this Business Group still has validation errors.'.
    ENDIF.
    PERFORM exec_q_set USING ls_key gc_st_error lv_msg ''.
  ENDIF.

  PERFORM display_0500_queue.
  CLEAR p_new_val.

  IF lv_group_ready = abap_true.
    lv_remaining = lines( gt_0560_groups ).
    IF lv_remaining > 0.
      CLEAR: p_bus_group, p_fld_name, p_old_val,
             gv_0560_prepared, gv_0560_last_group, gv_0560_last_field.
      REFRESH: gt_0560_map, gt_0560_old_opt.
      lv_msg = |Business Group { ls_key-record_key } is READY. Continue with the next selected failed group ({ lv_remaining } remaining).|.
      MESSAGE lv_msg TYPE 'S'.
      RETURN.
    ENDIF.

    IF gt_0560_ready_done IS NOT INITIAL.
      PERFORM select_0500_keys USING gt_0560_ready_done.
    ENDIF.
    lv_msg = |Correction saved for { ls_key-record_key } ({ lv_total_rows } row value(s)). Validation passed; choose CT or BISM to execute the next attempt.|.
    MESSAGE lv_msg TYPE 'S'.
    PERFORM reset_0560.
    SET SCREEN 0.
    LEAVE SCREEN.
  ELSE.
    CLEAR: p_old_val, gv_0560_last_field.
    REFRESH gt_0560_old_opt.
    lv_msg = |Correction saved for { ls_key-record_key }, but the group is still ERROR. Choose another field/value correction.|.
    MESSAGE lv_msg TYPE 'S' DISPLAY LIKE 'W'.
  ENDIF.
ENDFORM.

* Result Dashboard and Detail
FORM prep_result_invest_0650
  CHANGING cv_ok TYPE abap_bool.

  CLEAR cv_ok.

  "GT07 opens a global investigation workspace. No dashboard session is
  "required, no popup is allowed, and no MAX/latest session is inferred.
  CLEAR: txtp_result_session,
         txtp_po_key,
         txtp_sap_object_id,
         txtp_result_msg,
         txtp_result_group,
         txtp_result_status,
         txtp_result_created,
         txtp_result_executor,
         txtp_result_row_attempt,
         txtp_result_tcode,
         gv_group_pick_0650,
         gv_result_row_index_0650.

  REFRESH: gt_log_0650,
           gt_evidence_0650,
           gt_group_0650,
           gt_group_ctx_0650,
           gt_result_all,
           gt_result_msg.

  IF go_grid_0650 IS BOUND.
    CLEAR go_grid_0650.
  ENDIF.
  IF go_container_0650 IS BOUND.
    TRY.
        go_container_0650->free( ).
      CATCH cx_root.
    ENDTRY.
    CLEAR go_container_0650.
  ENDIF.

  IF go_group_grid_0650 IS BOUND.
    CLEAR go_group_grid_0650.
  ENDIF.
  IF go_group_container_0650 IS BOUND.
    TRY.
        go_group_container_0650->free( ).
      CATCH cx_root.
    ENDTRY.
    CLEAR go_group_container_0650.
  ENDIF.
  CLEAR go_group_evt_0650.

  PERFORM stop_result_timer_0650.
  CLEAR: gv_result_0650_tick,
         gv_result_0650_skip_pbo,
         gv_result_0650_fast_pbo,
         gv_evidence_shape_0650,
         gv_sig_0650.

  "Make 0650 independent from whatever 0100 happened to have in memory.
  PERFORM refresh_kpi_snapshot_0650.
  PERFORM build_result_signature_0650 CHANGING gv_sig_0650.

  CALL METHOD cl_gui_cfw=>flush
    EXCEPTIONS
      OTHERS = 1.

  cv_ok = abap_true.
ENDFORM.


* ============================================================
* 14Y - canonical live Result Investigation snapshot.
* Screen 0650 must not depend on the last 0100 in-memory snapshot.  This form
* rereads the same persisted ingest/staging facts used by the Main Dashboard,
* so a running/updated group becomes visible in 0650 within the live timer.
* ============================================================
FORM refresh_kpi_snapshot_0650.

  TYPES: BEGIN OF ty_0650_kpi_stg,
           session_id TYPE zbdc_staging_bup-session_id,
           record_key TYPE zbdc_staging_bup-record_key,
           row_index  TYPE zbdc_staging_bup-row_index,
           tcode      TYPE zbdc_staging_bup-tcode,
           status     TYPE zbdc_staging_bup-status,
         END OF ty_0650_kpi_stg.

  DATA: lt_kpi_stg       TYPE STANDARD TABLE OF ty_0650_kpi_stg WITH DEFAULT KEY,
        lt_ingested_sids TYPE SORTED TABLE OF ty_kpi_sid_0100
                         WITH UNIQUE KEY session_id,
        ls_group         TYPE ty_kpi_group_0100,
        lv_group_key     TYPE c LENGTH 80,
        lv_status_norm   TYPE char20.

  FIELD-SYMBOLS <ls_group> TYPE ty_kpi_group_0100.

  REFRESH: lt_kpi_stg, lt_ingested_sids,
           gt_kpi_sid_0100, gt_kpi_group_0100.

  SELECT session_id, record_key, row_index, tcode, status
    FROM zbdc_staging_bup
    INTO CORRESPONDING FIELDS OF TABLE @lt_kpi_stg.

  SELECT DISTINCT session_id
    FROM zbdc_file_lg_bup
    INTO CORRESPONDING FIELDS OF TABLE @lt_ingested_sids
    WHERE status = 'IMPORTED'.

  LOOP AT lt_kpi_stg INTO DATA(ls_stg).
    IF ls_stg-session_id IS INITIAL
       OR ls_stg-session_id CP 'GMAIL_REQ_*'.
      CONTINUE.
    ENDIF.

    READ TABLE lt_ingested_sids
      WITH TABLE KEY session_id = ls_stg-session_id
      TRANSPORTING NO FIELDS.
    IF sy-subrc <> 0.
      CONTINUE.
    ENDIF.

    INSERT VALUE ty_kpi_sid_0100( session_id = ls_stg-session_id )
      INTO TABLE gt_kpi_sid_0100.

    CLEAR lv_group_key.
    IF ls_stg-record_key IS NOT INITIAL.
      lv_group_key = |K:{ ls_stg-record_key }|.
    ELSEIF ls_stg-row_index IS NOT INITIAL.
      lv_group_key = |R:{ ls_stg-row_index }|.
    ELSE.
      lv_group_key = |I:{ sy-tabix }|.
    ENDIF.

    UNASSIGN <ls_group>.
    READ TABLE gt_kpi_group_0100 ASSIGNING <ls_group>
      WITH TABLE KEY session_id = ls_stg-session_id
                     group_key  = lv_group_key.
    IF sy-subrc <> 0.
      CLEAR ls_group.
      ls_group-session_id = ls_stg-session_id.
      ls_group-group_key  = lv_group_key.
      ls_group-record_key = ls_stg-record_key.
      ls_group-row_index  = ls_stg-row_index.
      ls_group-tcode      = ls_stg-tcode.
      INSERT ls_group INTO TABLE gt_kpi_group_0100 ASSIGNING <ls_group>.
    ENDIF.

    IF <ls_group> IS ASSIGNED.
      <ls_group>-row_count = <ls_group>-row_count + 1.
      IF <ls_group>-tcode IS INITIAL AND ls_stg-tcode IS NOT INITIAL.
        <ls_group>-tcode = ls_stg-tcode.
      ENDIF.

      lv_status_norm = ls_stg-status.
      TRANSLATE lv_status_norm TO UPPER CASE.
      CONDENSE lv_status_norm NO-GAPS.

      CASE lv_status_norm.
        WHEN 'ERROR'.
          <ls_group>-error_rows = <ls_group>-error_rows + 1.
        WHEN 'WARNING'.
          <ls_group>-warning_rows = <ls_group>-warning_rows + 1.
        WHEN 'SUCCESS'.
          <ls_group>-success_rows = <ls_group>-success_rows + 1.
        WHEN 'SM35QUEUE' OR 'SM35_QUEUED' OR 'SM35RUN' OR 'QUEUED_SM35'.
          <ls_group>-sm35_rows = <ls_group>-sm35_rows + 1.
        WHEN OTHERS.
          <ls_group>-other_rows = <ls_group>-other_rows + 1.
          IF lv_status_norm IS INITIAL.
            lv_status_norm = 'BLANK'.
          ENDIF.
          IF <ls_group>-other_state IS INITIAL.
            <ls_group>-other_state = lv_status_norm.
          ELSEIF <ls_group>-other_state <> lv_status_norm.
            <ls_group>-other_state = 'MIXED'.
          ENDIF.
      ENDCASE.
    ENDIF.
  ENDLOOP.

  LOOP AT gt_kpi_group_0100 ASSIGNING <ls_group>.
    CLEAR <ls_group>-state.
    IF <ls_group>-error_rows > 0.
      <ls_group>-state = 'ERROR'.
    ELSEIF <ls_group>-warning_rows > 0.
      <ls_group>-state = 'WARNING'.
    ELSEIF <ls_group>-row_count > 0
       AND <ls_group>-success_rows = <ls_group>-row_count.
      <ls_group>-state = 'SUCCESS'.
    ELSEIF <ls_group>-row_count > 0
       AND <ls_group>-sm35_rows = <ls_group>-row_count.
      <ls_group>-state = 'SM35QUEUE'.
    ELSEIF <ls_group>-row_count > 0
       AND <ls_group>-other_rows = <ls_group>-row_count
       AND <ls_group>-other_state IS NOT INITIAL.
      <ls_group>-state = <ls_group>-other_state.
    ELSE.
      <ls_group>-state = 'MIXED'.
    ENDIF.
  ENDLOOP.

ENDFORM.

* Deterministic 0650 live signature.  It includes the current canonical group
* state plus RESULT count/latest evidence time, so evidence-only changes also
* repaint even when the group's lifecycle text did not change.
FORM build_result_signature_0650
  CHANGING cv_sig TYPE string.

  DATA: lt_groups      TYPE STANDARD TABLE OF ty_kpi_group_0100 WITH DEFAULT KEY,
        lt_parts       TYPE STANDARD TABLE OF string WITH DEFAULT KEY,
        lv_raw         TYPE string,
        lv_hash        TYPE string,
        lv_result_cnt  TYPE i,
        lv_result_max  TYPE zbdc_result_bup-created_at.

  CLEAR: cv_sig, lv_raw, lv_hash.
  REFRESH: lt_groups, lt_parts.

  LOOP AT gt_kpi_group_0100 INTO DATA(ls_g).
    APPEND ls_g TO lt_groups.
  ENDLOOP.
  SORT lt_groups BY session_id group_key.

  LOOP AT lt_groups INTO ls_g.
    APPEND |G:{ ls_g-session_id }\|{ ls_g-group_key }\|{ ls_g-state }\|{ ls_g-tcode }\|{ ls_g-row_count };|
      TO lt_parts.
  ENDLOOP.

  SELECT COUNT( * ) FROM zbdc_result_bup INTO @lv_result_cnt.
  SELECT MAX( created_at ) FROM zbdc_result_bup INTO @lv_result_max.
  APPEND |R:{ lv_result_cnt }\|{ lv_result_max }| TO lt_parts.

  CONCATENATE LINES OF lt_parts INTO lv_raw.
  TRY.
      cl_abap_message_digest=>calculate_hash_for_char(
        EXPORTING
          if_algorithm     = 'SHA-256'
          if_data          = lv_raw
        IMPORTING
          ef_hashb64string = lv_hash ).
      cv_sig = lv_hash.
    CATCH cx_abap_message_digest.
      cv_sig = lv_raw.
  ENDTRY.

ENDFORM.

FORM build_result_groups_0650.

  "14X Result Investigation organization:
  "  1) one canonical user-facing Business Group name (no raw ROW n labels),
  "  2) newest persisted session first,
  "  3) within a session: ERROR -> WARNING -> SUCCESS -> READY/STAGED -> processing,
  "  4) insert a non-selectable visual Session header before every session block.
  "Exact backend identity is still kept in GT_GROUP_CTX_0650 at the same row index.

  TYPES: BEGIN OF ty_work_0650,
           ctx         TYPE ty_group_0100_disp,
           sort_at     TYPE zbdc_result_bup-created_at,
           status_rank TYPE i,
           canon_group TYPE char80,
         END OF ty_work_0650.

  DATA: lt_work       TYPE STANDARD TABLE OF ty_work_0650 WITH DEFAULT KEY,
        ls_work       TYPE ty_work_0650,
        ls_count      TYPE ty_work_0650,
        ls_kpi        TYPE ty_kpi_group_0100,
        ls_ctx        TYPE ty_group_0100_disp,
        ls_header_ctx TYPE ty_group_0100_disp,
        ls_display    TYPE ty_group_0650_disp,
        ls_cell_type  TYPE salv_s_int4_column,
        ls_session    TYPE zbdc_session_bup,
        lv_num4       TYPE n LENGTH 4,
        lv_prev_sid   TYPE zbdc_staging_bup-session_id,
        lv_group_cnt  TYPE i,
        lv_header_time TYPE char19.

  REFRESH: gt_group_0650, gt_group_ctx_0650, lt_work.

  LOOP AT gt_kpi_group_0100 INTO ls_kpi.
    CLEAR: ls_ctx, ls_work, ls_session, lv_num4.

    ls_ctx-session_id = ls_kpi-session_id.
    ls_ctx-record_key = ls_kpi-record_key.
    ls_ctx-row_index  = ls_kpi-row_index.
    ls_ctx-tcode      = ls_kpi-tcode.
    ls_ctx-row_count  = ls_kpi-row_count.
    ls_ctx-lifecycle  = ls_kpi-state.

    "Canonical user-facing group key. Legacy rows such as 'ROW 1' are a
    "technical fallback and must never be the primary identifier in 0650.
    IF ls_kpi-record_key IS NOT INITIAL AND ls_kpi-record_key NP 'ROW *'.
      ls_ctx-group_key = ls_kpi-record_key.
    ELSEIF ls_kpi-row_index IS NOT INITIAL.
      lv_num4 = ls_kpi-row_index.
      IF ls_kpi-tcode IS NOT INITIAL.
        ls_ctx-group_key = |{ ls_kpi-tcode }-{ lv_num4 }|.
      ELSE.
        ls_ctx-group_key = |GROUP-{ lv_num4 }|.
      ENDIF.
    ELSEIF ls_kpi-group_key IS NOT INITIAL.
      ls_ctx-group_key = ls_kpi-group_key.
    ELSE.
      ls_ctx-group_key = 'UNIDENTIFIED GROUP'.
    ENDIF.

    CASE ls_ctx-lifecycle.
      WHEN 'SM35QUEUE' OR 'SM35_QUEUED' OR 'SM35RUN' OR 'QUEUED_SM35'.
        ls_ctx-lifecycle = 'SM35 QUEUED'.
        ls_ctx-health    = icon_yellow_light.
        ls_work-status_rank = 7.
      WHEN 'PROCESSED'.
        ls_ctx-lifecycle = 'VERIFYING'.
        ls_ctx-health    = icon_yellow_light.
        ls_work-status_rank = 6.
      WHEN 'QUEUED' OR 'MIXED' OR 'PROCESSING' OR 'RUNNING'.
        ls_ctx-lifecycle = 'PROCESSING'.
        ls_ctx-health    = icon_yellow_light.
        ls_work-status_rank = 6.
      WHEN 'ERROR'.
        ls_ctx-health = icon_red_light.
        ls_work-status_rank = 1.
      WHEN 'WARNING'.
        ls_ctx-health = icon_yellow_light.
        ls_work-status_rank = 2.
      WHEN 'SUCCESS'.
        ls_ctx-health = icon_green_light.
        ls_work-status_rank = 3.
      WHEN 'READY'.
        ls_ctx-health = icon_yellow_light.
        ls_work-status_rank = 4.
      WHEN 'STAGED'.
        ls_ctx-health = icon_yellow_light.
        ls_work-status_rank = 5.
      WHEN OTHERS.
        ls_ctx-health = icon_yellow_light.
        ls_work-status_rank = 8.
    ENDCASE.

    "Use the exact persisted session start as the cross-prefix sort key. This
    "avoids lexical mistakes such as SES_... sorting ahead of newer B2026....
    SELECT SINGLE * FROM zbdc_session_bup
      INTO @ls_session
      WHERE session_id = @ls_kpi-session_id.
    IF sy-subrc = 0.
      ls_work-sort_at = ls_session-start_time.
    ENDIF.

    "Legacy sessions can predate ZBDC_SESSION_BUP. Fall back to exact result
    "evidence time for this same session only; never use MAX/latest globally.
    IF ls_work-sort_at IS INITIAL.
      SELECT MAX( created_at ) FROM zbdc_result_bup
        INTO @ls_work-sort_at
        WHERE session_id = @ls_kpi-session_id.
    ENDIF.

    ls_work-ctx         = ls_ctx.
    ls_work-canon_group = ls_ctx-group_key.
    APPEND ls_work TO lt_work.
  ENDLOOP.

  SORT lt_work BY sort_at DESCENDING status_rank ASCENDING canon_group ASCENDING.

  CLEAR lv_prev_sid.
  LOOP AT lt_work INTO ls_work.

    IF lv_prev_sid IS INITIAL OR lv_prev_sid <> ls_work-ctx-session_id.
      lv_prev_sid = ls_work-ctx-session_id.
      CLEAR lv_group_cnt.
      LOOP AT lt_work INTO ls_count.
        IF ls_count-ctx-session_id = lv_prev_sid.
          lv_group_cnt = lv_group_cnt + 1.
        ENDIF.
      ENDLOOP.

      "Header row exists only in the visual projection. Append a blank context
      "row at the same index so display/context row numbers stay 1:1.
      CLEAR: ls_display, lv_header_time.
      ls_display-is_header  = abap_true.
      "15A: keep the session band ASCII-only so non-Unicode SAP GUI/code pages
      "never render the old down-triangle as mojibake such as 'Ã¢â€“Â¼'.
      ls_display-group_key  = |Session { lv_prev_sid } ({ lv_group_cnt } groups)|.
      PERFORM format_result_time USING ls_work-sort_at CHANGING lv_header_time.
      IF lv_header_time IS INITIAL.
        lv_header_time = '-'.
      ENDIF.
      "Keep technical columns semantically clean: SESSION_ID is never reused
      "for a timestamp.  The visual header gets its own Created Time column.
      CLEAR: ls_display-session_id, ls_display-row_count.
      ls_display-session_time = lv_header_time.
      ls_display-line_color = 'C410'.
      APPEND ls_display TO gt_group_0650.
      CLEAR ls_header_ctx.
      APPEND ls_header_ctx TO gt_group_ctx_0650.
    ENDIF.

    ls_ctx = ls_work-ctx.
    APPEND ls_ctx TO gt_group_ctx_0650.

    CLEAR ls_display.
    ls_display-health     = ls_ctx-health.
    ls_display-group_key  = ls_ctx-group_key.
    ls_display-tcode      = ls_ctx-tcode.
    ls_display-row_count  = |{ ls_ctx-row_count }|.
    ls_display-lifecycle  = ls_ctx-lifecycle.
    ls_display-session_id = ls_ctx-session_id.
    CLEAR ls_display-session_time.
    ls_display-is_header  = abap_false.
    CLEAR ls_display-line_color.

    REFRESH ls_display-cell_types.
    CLEAR ls_cell_type.
    ls_cell_type-columnname = 'GROUP_KEY'.
    ls_cell_type-value      = if_salv_c_cell_type=>hotspot.
    APPEND ls_cell_type TO ls_display-cell_types.

    APPEND ls_display TO gt_group_0650.
  ENDLOOP.
ENDFORM.

FORM display_result_groups_0650.

  DATA: lt_fcat_0650 TYPE lvc_t_fcat,
        ls_fcat_0650 TYPE lvc_s_fcat,
        ls_layout_0650 TYPE lvc_s_layo.

  "14U: Result Groups must react to the way the user actually selects a row.
  "The previous CL_SALV_TABLE implementation only emitted LINK_CLICK for the
  "GROUP_KEY hotspot; clicking the normal row selector simply highlighted the
  "row and produced no event, leaving Context/Evidence unchanged. Use the
  "project's existing CL_GUI_ALV_GRID technology and the documented delayed
  "selection event instead. This catches a normal single row selection.
  IF go_group_container_0650 IS INITIAL OR go_group_grid_0650 IS INITIAL.
    PERFORM build_result_groups_0650.

    CREATE OBJECT go_group_container_0650
      EXPORTING container_name = 'CC_GROUP_CONTAINER'.

    CREATE OBJECT go_group_grid_0650
      EXPORTING i_parent = go_group_container_0650.

    CLEAR ls_layout_0650.
    ls_layout_0650-zebra      = abap_true.
    ls_layout_0650-cwidth_opt = abap_false.
    ls_layout_0650-sel_mode   = 'B'.
    ls_layout_0650-info_fname = 'LINE_COLOR'.

    DEFINE add_0650_fcat.
      CLEAR ls_fcat_0650.
      ls_fcat_0650-fieldname = &1.
      ls_fcat_0650-coltext   = &2.
      ls_fcat_0650-scrtext_l = &2.
      ls_fcat_0650-scrtext_m = &2.
      ls_fcat_0650-scrtext_s = &2.
      ls_fcat_0650-outputlen = &3.
      IF &1 = 'GROUP_KEY'.
        ls_fcat_0650-hotspot = abap_true.
      ELSE.
        CLEAR ls_fcat_0650-hotspot.
      ENDIF.
      APPEND ls_fcat_0650 TO lt_fcat_0650.
    END-OF-DEFINITION.

    add_0650_fcat 'HEALTH'        'Health'          5.
    add_0650_fcat 'GROUP_KEY'     'Business Group' 30.
    add_0650_fcat 'TCODE'         'TCode'           8.
    add_0650_fcat 'LIFECYCLE'     'Status'         14.
    add_0650_fcat 'ROW_COUNT'     'Rows'            5.
    add_0650_fcat 'SESSION_ID'    'Session ID'     22.
    add_0650_fcat 'SESSION_TIME'  'Created Time'   19.

    CALL METHOD go_group_grid_0650->set_table_for_first_display
      EXPORTING
        is_layout       = ls_layout_0650
      CHANGING
        it_outtab       = gt_group_0650
        it_fieldcatalog = lt_fcat_0650
      EXCEPTIONS
        invalid_parameter_combination = 1
        program_error                 = 2
        too_many_lines                = 3
        OTHERS                        = 4.

    "14V compatibility: SET_DELAY_CHANGE_SELECTION is PROTECTED on this SAP
    "release when called from an ordinary FORM.  LCL_GRID_EVENTS already
    "implements IF_ALV_RM_GRID_FRIEND and its public CONFIGURE_0400_GRID
    "wrapper is the release-safe project path for the same protected call.
    "Create the handler first, let the friend wrapper configure the delay,
    "then register the public delayed-selection event used by screen 0650.
    IF g_0650_grid_events IS INITIAL.
      CREATE OBJECT g_0650_grid_events.
    ENDIF.

    "14W: immediate path first.  Any click on a visible data cell selects
    "that Result Group and triggers the existing RGSEL PAI/PBO repaint.
    SET HANDLER g_0650_grid_events->on_0650_hotspot_click FOR go_group_grid_0650.

    "Keep row-marker selection as a fallback.  SAP examples register the
    "handler/event before changing the delayed-selection interval.
    SET HANDLER g_0650_grid_events->on_0650_delayed_sel FOR go_group_grid_0650.

    CALL METHOD go_group_grid_0650->register_delayed_event
      EXPORTING
        i_event_id = cl_gui_alv_grid=>mc_evt_delayed_change_select.

    g_0650_grid_events->configure_0400_grid(
      ir_grid = go_group_grid_0650 ).
  ENDIF.

ENDFORM.

FORM select_result_group_0650 USING iv_row TYPE i.

  DATA: ls_group    TYPE ty_group_0100_disp,
        lt_exec     TYPE ty_t_result_726,
        ls_exec     TYPE zbdc_result_bup,
        ls_session  TYPE zbdc_session_bup,
        lv_executor TYPE char12,
        lv_min_at   TYPE zbdc_result_bup-created_at,
        lv_time_txt TYPE char19.

  READ TABLE gt_group_ctx_0650 INTO ls_group INDEX iv_row.
  IF sy-subrc <> 0 OR ls_group-session_id IS INITIAL OR ls_group-group_key IS INITIAL.
    RETURN.
  ENDIF.

  txtp_result_session = ls_group-session_id.
  txtp_result_group   = ls_group-group_key.
  txtp_result_status  = ls_group-lifecycle.
  txtp_result_tcode   = ls_group-tcode.
  txtp_po_key         = ls_group-record_key.
  gv_result_row_index_0650 = ls_group-row_index.

  REFRESH gt_log_0650.
  IF ls_group-record_key IS NOT INITIAL.
    SELECT * FROM zbdc_result_bup
      INTO TABLE @gt_log_0650
      WHERE session_id = @ls_group-session_id
        AND record_key = @ls_group-record_key
      ORDER BY row_index ASCENDING, step ASCENDING.
  ELSEIF ls_group-row_index IS NOT INITIAL.
    SELECT * FROM zbdc_result_bup
      INTO TABLE @gt_log_0650
      WHERE session_id = @ls_group-session_id
        AND row_index  = @ls_group-row_index
      ORDER BY row_index ASCENDING, step ASCENDING.
  ENDIF.

  CLEAR: txtp_sap_object_id,
         txtp_result_msg,
         txtp_result_created,
         txtp_result_executor,
         txtp_result_row_attempt,
         lv_executor,
         lv_min_at,
         lv_time_txt.

  lt_exec = gt_log_0650.
  SORT lt_exec BY created_at DESCENDING step DESCENDING.

  IF lt_exec IS NOT INITIAL.
    PERFORM resolve_executor USING lt_exec CHANGING lv_executor.
    IF lv_executor = 'UNKNOWN'.
      CLEAR lv_executor.
    ENDIF.

    LOOP AT lt_exec INTO ls_exec.
      IF txtp_sap_object_id IS INITIAL AND ls_exec-sap_object_id IS NOT INITIAL.
        txtp_sap_object_id = ls_exec-sap_object_id.
      ENDIF.
      IF txtp_result_msg IS INITIAL AND ls_exec-message IS NOT INITIAL.
        txtp_result_msg = ls_exec-message.
      ENDIF.

      "Never let a legacy/synthetic result row with an empty CREATED_AT erase
      "a real timestamp already found for the selected group. 14L compared
      "initial timestamps as a minimum value, so a later empty row could reset
      "Created Time back to '-'. Only persisted, non-initial evidence times
      "participate in the group-created-time calculation.
      IF ls_exec-created_at IS NOT INITIAL.
        IF lv_min_at IS INITIAL OR ls_exec-created_at < lv_min_at.
          lv_min_at = ls_exec-created_at.
        ENDIF.
      ENDIF.
    ENDLOOP.
  ENDIF.

  IF lv_executor IS INITIAL AND ls_group-lifecycle = 'SM35 QUEUED'.
    lv_executor = 'BISM'.
  ENDIF.
  IF lv_executor IS INITIAL.
    txtp_result_executor = '-'.
  ELSE.
    txtp_result_executor = lv_executor.
  ENDIF.

  "Created Time is evidence-first. Older result rows can have no CREATED_AT,
  "so fall back only to the exact selected session's persisted START_TIME.
  IF lv_min_at IS INITIAL.
    CLEAR ls_session.
    SELECT SINGLE * FROM zbdc_session_bup
      INTO @ls_session
      WHERE session_id = @ls_group-session_id.
    IF sy-subrc = 0 AND ls_session-start_time IS NOT INITIAL.
      lv_min_at = ls_session-start_time.
    ENDIF.
  ENDIF.

  PERFORM format_result_time USING lv_min_at CHANGING lv_time_txt.
  IF lv_time_txt IS INITIAL.
    txtp_result_created = '-'.
  ELSE.
    txtp_result_created = lv_time_txt.
  ENDIF.

  "Screen 0650 presents group cardinality, not an execution-attempt summary.
  "Attempt remains available per evidence row on the right-hand grid.
  IF ls_group-row_count = 1.
    txtp_result_row_attempt = '1 row'.
  ELSE.
    txtp_result_row_attempt = |{ ls_group-row_count } rows|.
  ENDIF.

  "15F fast selection: this FORM has already loaded the exact result rows
  "and populated all context fields. Do not repeat the same DB read in the
  "immediately following 0650 PBO.
  gv_result_0650_fast_pbo = abap_true.

ENDFORM.

FORM load_result_detail.
  DATA lv_session TYPE zbdc_result_bup-session_id.

  lv_session = txtp_result_session.

  "0650 is fail-closed: no group selection means no evidence. Never infer a
  "latest session, never reuse an old result buffer, and never search by SAP
  "object without the exact session/group identity selected in this screen.
  IF lv_session IS INITIAL.
    REFRESH gt_log_0650.
    RETURN.
  ENDIF.

  IF txtp_po_key IS NOT INITIAL.
    SELECT * FROM zbdc_result_bup
      WHERE session_id = @lv_session
        AND record_key = @txtp_po_key
      ORDER BY row_index ASCENDING, step ASCENDING
      INTO TABLE @gt_log_0650.
  ELSEIF gv_result_row_index_0650 IS NOT INITIAL.
    SELECT * FROM zbdc_result_bup
      WHERE session_id = @lv_session
        AND row_index  = @gv_result_row_index_0650
      ORDER BY row_index ASCENDING, step ASCENDING
      INTO TABLE @gt_log_0650.
  ELSE.
    REFRESH gt_log_0650.
  ENDIF.
ENDFORM.

FORM sync_result_created_0650.

  DATA: ls_res     TYPE zbdc_result_bup,
        ls_session TYPE zbdc_session_bup,
        lv_min_at  TYPE zbdc_result_bup-created_at,
        lv_time    TYPE char19.

  CLEAR: lv_min_at, lv_time.

  "The evidence grid is rebuilt on every PBO, while the context fields were
  "historically populated only in SELECT_RESULT_GROUP_0650. That allowed a
  "stale '-' Created Time to remain even when the same exact GT_LOG_0650 rows
  "already showed a real Evidence Time. Re-derive the context timestamp from
  "the exact selected group's result rows on every 0650 PBO.
  LOOP AT gt_log_0650 INTO ls_res.
    IF ls_res-created_at IS NOT INITIAL.
      IF lv_min_at IS INITIAL OR ls_res-created_at < lv_min_at.
        lv_min_at = ls_res-created_at.
      ENDIF.
    ENDIF.
  ENDLOOP.

  "Legacy sessions may have result rows without CREATED_AT. Only then use the
  "persisted START_TIME of the exact selected Session ID; never infer latest.
  IF lv_min_at IS INITIAL AND txtp_result_session IS NOT INITIAL.
    CLEAR ls_session.
    SELECT SINGLE * FROM zbdc_session_bup
      INTO @ls_session
      WHERE session_id = @txtp_result_session.
    IF sy-subrc = 0 AND ls_session-start_time IS NOT INITIAL.
      lv_min_at = ls_session-start_time.
    ENDIF.
  ENDIF.

  PERFORM format_result_time USING lv_min_at CHANGING lv_time.
  IF lv_time IS INITIAL.
    txtp_result_created = '-'.
  ELSE.
    txtp_result_created = lv_time.
  ENDIF.

ENDFORM.

FORM build_evidence_0650.

  DATA: ls_res  TYPE zbdc_result_bup,
        ls_view TYPE ty_evidence_0650,
        lv_time TYPE char19,
        lv_mid  TYPE char20,
        lv_mnr  TYPE char20.
  FIELD-SYMBOLS <lv_comp> TYPE any.

  REFRESH gt_evidence_0650.

  LOOP AT gt_log_0650 INTO ls_res.
    CLEAR: ls_view, lv_time, lv_mid, lv_mnr.

    ls_view-step            = ls_res-step.
    ls_view-row_index       = ls_res-row_index.
    ls_view-attempt         = ls_res-attempt_no.
    ls_view-screen          = ls_res-dynpro.
    ls_view-technical_field = ls_res-field_name.
    ls_view-exact_message   = ls_res-message.
    ls_view-sap_object      = ls_res-sap_object_id.
    ls_view-evidence_source = 'Execution Result Log'.
    ls_view-message_type    = ls_res-msg_type.

    "PROGRAM/MODULE is optional DDIC evidence. Read it dynamically so
    "0650 never requires a non-existent ZBDC_RESULT_BUP component.
    UNASSIGN <lv_comp>.
    ASSIGN COMPONENT 'DYNAME' OF STRUCTURE ls_res TO <lv_comp>.
    IF sy-subrc <> 0.
      ASSIGN COMPONENT 'PROGRAM_NAME' OF STRUCTURE ls_res TO <lv_comp>.
    ENDIF.
    IF sy-subrc <> 0.
      ASSIGN COMPONENT 'MODULE' OF STRUCTURE ls_res TO <lv_comp>.
    ENDIF.
    IF sy-subrc = 0 AND <lv_comp> IS ASSIGNED.
      ls_view-program = <lv_comp>.
    ENDIF.

    "Message ID/number are also schema-optional in older result tables.
    UNASSIGN <lv_comp>.
    ASSIGN COMPONENT 'MSG_ID' OF STRUCTURE ls_res TO <lv_comp>.
    IF sy-subrc <> 0.
      ASSIGN COMPONENT 'MSGID' OF STRUCTURE ls_res TO <lv_comp>.
    ENDIF.
    IF sy-subrc <> 0.
      ASSIGN COMPONENT 'MID' OF STRUCTURE ls_res TO <lv_comp>.
    ENDIF.
    IF sy-subrc = 0 AND <lv_comp> IS ASSIGNED.
      lv_mid = <lv_comp>.
    ENDIF.

    UNASSIGN <lv_comp>.
    ASSIGN COMPONENT 'MSG_NUMBER' OF STRUCTURE ls_res TO <lv_comp>.
    IF sy-subrc <> 0.
      ASSIGN COMPONENT 'MSGNR' OF STRUCTURE ls_res TO <lv_comp>.
    ENDIF.
    IF sy-subrc <> 0.
      ASSIGN COMPONENT 'MSG_NO' OF STRUCTURE ls_res TO <lv_comp>.
    ENDIF.
    IF sy-subrc <> 0.
      ASSIGN COMPONENT 'MNR' OF STRUCTURE ls_res TO <lv_comp>.
    ENDIF.
    IF sy-subrc = 0 AND <lv_comp> IS ASSIGNED.
      lv_mnr = <lv_comp>.
    ENDIF.

    IF lv_mid IS NOT INITIAL OR lv_mnr IS NOT INITIAL.
      CONCATENATE lv_mid lv_mnr INTO ls_view-message_id SEPARATED BY '-'.
      CONDENSE ls_view-message_id NO-GAPS.
    ENDIF.

    PERFORM format_result_time USING ls_res-created_at CHANGING lv_time.
    ls_view-evidence_time = lv_time.

    "Do not show shell rows that have no user-facing evidence. A dynpro number
    "alone is not an execution message and made the grid look empty/broken.
    IF ls_view-exact_message IS INITIAL AND
       ls_view-technical_field IS INITIAL AND
       ls_view-message_id IS INITIAL.
      CONTINUE.
    ENDIF.

    "Result writers can persist the same SAP message more than once (for
    "example summary + terminal success). Screen 0650 is an investigation
    "view, so collapse exact duplicates while keeping the first real log row.
    READ TABLE gt_evidence_0650 TRANSPORTING NO FIELDS
      WITH KEY row_index       = ls_view-row_index
               attempt         = ls_view-attempt
               message_type    = ls_view-message_type
               message_id      = ls_view-message_id
               program         = ls_view-program
               screen          = ls_view-screen
               technical_field = ls_view-technical_field
               exact_message   = ls_view-exact_message
               sap_object      = ls_view-sap_object.
    IF sy-subrc <> 0.
      APPEND ls_view TO gt_evidence_0650.
    ENDIF.
  ENDLOOP.

  "14P empty-state projection: READY/STAGED groups legitimately have no SAP
  "execution log yet, and some pre-execution ERROR groups also have no
  "ZBDC_RESULT_BUP rows. Do not leave the evidence panel as a blank white
  "rectangle. Show a clearly sourced status explanation without pretending it
  "is a SAP protocol message or inventing technical evidence.
  IF gt_evidence_0650 IS INITIAL AND txtp_result_group IS NOT INITIAL.
    CLEAR ls_view.
    ls_view-message_type    = 'I'.
    ls_view-evidence_source = 'Status Context'.

    CASE txtp_result_status.
      WHEN 'READY'.
        ls_view-exact_message =
          'No SAP execution evidence yet. This group is READY and has not been executed.'.
      WHEN 'STAGED'.
        ls_view-exact_message =
          'No SAP execution evidence yet. This group is STAGED and has not been executed.'.
      WHEN 'ERROR'.
        ls_view-exact_message =
          'No SAP execution evidence was persisted for this ERROR group. Use Analyze Error for this selected group.'.
      WHEN 'WARNING'.
        ls_view-exact_message =
          'No SAP execution evidence was persisted for this WARNING group.'.
      WHEN 'SUCCESS'.
        ls_view-exact_message =
          'No persisted SAP execution message was found for this SUCCESS group.'.
      WHEN OTHERS.
        ls_view-exact_message =
          'No SAP execution evidence is available for the selected group.'.
    ENDCASE.

    APPEND ls_view TO gt_evidence_0650.
  ENDIF.

ENDFORM.

FORM display_result_detail.
  DATA: lv_has_message_id TYPE abap_bool,
        lv_has_program    TYPE abap_bool,
        lv_has_tech_field TYPE abap_bool,
        lv_has_screen     TYPE abap_bool,
        lv_has_time       TYPE abap_bool,
        lv_has_rows       TYPE abap_bool,
        lv_shape_0650     TYPE string,
        lv_refreshed_0650 TYPE abap_bool,
        ls_ev_scan        TYPE ty_evidence_0650.

  PERFORM display_result_groups_0650.

  "15F: SELECT_RESULT_GROUP_0650 already performed the exact SELECT in PAI.
  "Skip the historical second SELECT/sync pass on that immediate PBO. This
  "is deliberately local to screen 0650 and does not touch Staging, AI Navi,
  "Preview Data, My Uploads, or All Uploads.
  IF gv_result_0650_fast_pbo = abap_true.
    CLEAR gv_result_0650_fast_pbo.
  ELSE.
    PERFORM load_result_detail.
    PERFORM sync_result_created_0650.
  ENDIF.

  PERFORM build_evidence_0650.

  "Hard consistency rule for 0650: the context Result/Created Time and the
  "visible Evidence Time must come from the same exact selected-group data.
  "If legacy/session timestamp conversion above produced '-', reuse the first
  "non-initial formatted Evidence Time that is already being shown to the user.
  "This is not a guessed time; it is the same persisted result CREATED_AT.
  IF txtp_result_created IS INITIAL OR txtp_result_created = '-'.
    LOOP AT gt_evidence_0650 INTO DATA(ls_created_ev_0650).
      IF ls_created_ev_0650-evidence_time IS NOT INITIAL.
        txtp_result_created = ls_created_ev_0650-evidence_time.
        EXIT.
      ENDIF.
    ENDLOOP.
  ENDIF.

  "Technical result columns are schema/evidence dependent. Do not reserve
  "large empty areas when this selected group never persisted them. Keep the
  "exact SAP message and useful evidence metadata visible by default.
  CLEAR: lv_has_message_id, lv_has_program, lv_has_tech_field,
         lv_has_screen, lv_has_time.
  LOOP AT gt_evidence_0650 INTO ls_ev_scan.
    IF ls_ev_scan-message_id IS NOT INITIAL.
      lv_has_message_id = abap_true.
    ENDIF.
    IF ls_ev_scan-program IS NOT INITIAL.
      lv_has_program = abap_true.
    ENDIF.
    IF ls_ev_scan-technical_field IS NOT INITIAL.
      lv_has_tech_field = abap_true.
    ENDIF.
    IF ls_ev_scan-screen IS NOT INITIAL.
      lv_has_screen = abap_true.
    ENDIF.
    IF ls_ev_scan-evidence_time IS NOT INITIAL.
      lv_has_time = abap_true.
    ENDIF.
  ENDLOOP.

  "15F: Most group selections have the same evidence-column shape. In that
  "common path keep the existing SALV/control and refresh its bound table only.
  "This removes the expensive FREE -> FLUSH -> FACTORY -> DISPLAY cycle from
  "every click. Recreate only when the visible shape changes, preserving the
  "older 0-row -> data reliability fix.
  IF gt_evidence_0650 IS NOT INITIAL.
    lv_has_rows = abap_true.
  ELSE.
    CLEAR lv_has_rows.
  ENDIF.

  lv_shape_0650 =
    |R={ lv_has_rows };MID={ lv_has_message_id };PRG={ lv_has_program };| &&
    |FLD={ lv_has_tech_field };SCR={ lv_has_screen };TIM={ lv_has_time }|.

  IF go_grid_0650 IS BOUND
     AND gv_evidence_shape_0650 = lv_shape_0650.
    CLEAR lv_refreshed_0650.
    TRY.
        go_grid_0650->refresh( refresh_mode = if_salv_c_refresh=>full ).
        lv_refreshed_0650 = abap_true.
      CATCH cx_root.
        CLEAR lv_refreshed_0650.
    ENDTRY.

    IF lv_refreshed_0650 = abap_true.
      RETURN.
    ENDIF.
  ENDIF.

  "Fallback/re-shape path: recreate ONLY the right evidence SALV from the
  "freshly built GT_EVIDENCE_0650. This remains necessary for transitions
  "such as initial empty -> first selected group or when metadata columns
  "appear/disappear. The left Result Groups grid is never rebuilt here.
  IF go_grid_0650 IS BOUND.
    CLEAR go_grid_0650.
  ENDIF.
  IF go_container_0650 IS BOUND.
    TRY.
        go_container_0650->free( ).
      CATCH cx_root.
    ENDTRY.
    CLEAR go_container_0650.
  ENDIF.

  CALL METHOD cl_gui_cfw=>flush
    EXCEPTIONS
      OTHERS = 1.

  IF go_container_0650 IS INITIAL.
    CREATE OBJECT go_container_0650 EXPORTING container_name = 'CC_LOG_CONTAINER'.
    TRY.
        cl_salv_table=>factory(
          EXPORTING r_container  = go_container_0650
          IMPORTING r_salv_table = go_grid_0650
          CHANGING  t_table      = gt_evidence_0650 ).
        go_grid_0650->get_functions( )->set_all( abap_true ).
        go_grid_0650->get_columns( )->set_optimize( abap_false ).
        go_grid_0650->get_selections( )->set_selection_mode( if_salv_c_selection_mode=>row_column ).

        DATA(lo_ev_cols_0650) = go_grid_0650->get_columns( ).
        PERFORM set_dash_col_text USING lo_ev_cols_0650 'STEP'            'Step'.
        PERFORM set_dash_col_text USING lo_ev_cols_0650 'ROW_INDEX'       'Input Row'.
        PERFORM set_dash_col_text USING lo_ev_cols_0650 'ATTEMPT'         'Attempt'.
        PERFORM set_dash_col_text USING lo_ev_cols_0650 'MESSAGE_TYPE'    'Type'.
        PERFORM set_dash_col_text USING lo_ev_cols_0650 'MESSAGE_ID'      'Message ID'.
        PERFORM set_dash_col_text USING lo_ev_cols_0650 'PROGRAM'         'Program / Module'.
        PERFORM set_dash_col_text USING lo_ev_cols_0650 'SCREEN'          'Screen'.
        PERFORM set_dash_col_text USING lo_ev_cols_0650 'TECHNICAL_FIELD' 'Technical Field'.
        PERFORM set_dash_col_text USING lo_ev_cols_0650 'EXACT_MESSAGE'   'Exact SAP Message'.
        PERFORM set_dash_col_text USING lo_ev_cols_0650 'SAP_OBJECT'      'SAP Object'.
        PERFORM set_dash_col_text USING lo_ev_cols_0650 'EVIDENCE_TIME'   'Evidence Time'.
        PERFORM set_dash_col_text USING lo_ev_cols_0650 'EVIDENCE_SOURCE' 'Evidence Source'.

        TRY.
            "User-first order comes from TY_EVIDENCE_0650 in TOP. Keep the
            "message wide enough to be readable before any horizontal scroll.
            lo_ev_cols_0650->get_column( 'STEP' )->set_output_length( 5 ).
            lo_ev_cols_0650->get_column( 'MESSAGE_TYPE' )->set_output_length( 5 ).
            lo_ev_cols_0650->get_column( 'EXACT_MESSAGE' )->set_output_length( 42 ).
            lo_ev_cols_0650->get_column( 'SCREEN' )->set_output_length( 8 ).
            lo_ev_cols_0650->get_column( 'ROW_INDEX' )->set_output_length( 9 ).
            lo_ev_cols_0650->get_column( 'ATTEMPT' )->set_output_length( 7 ).
            lo_ev_cols_0650->get_column( 'MESSAGE_ID' )->set_output_length( 12 ).
            lo_ev_cols_0650->get_column( 'PROGRAM' )->set_output_length( 18 ).
            lo_ev_cols_0650->get_column( 'TECHNICAL_FIELD' )->set_output_length( 22 ).
            lo_ev_cols_0650->get_column( 'EVIDENCE_TIME' )->set_output_length( 19 ).
            lo_ev_cols_0650->get_column( 'EVIDENCE_SOURCE' )->set_output_length( 20 ).

            "Do not show permanently empty technical columns. They remain
            "available automatically whenever the exact selected result group
            "actually persisted values for them. This avoids the large blank
            "regions seen on legacy CT result rows.
            IF lv_has_message_id = abap_false.
              lo_ev_cols_0650->get_column( 'MESSAGE_ID' )->set_visible( abap_false ).
            ENDIF.
            IF lv_has_program = abap_false.
              lo_ev_cols_0650->get_column( 'PROGRAM' )->set_visible( abap_false ).
            ENDIF.
            IF lv_has_tech_field = abap_false.
              lo_ev_cols_0650->get_column( 'TECHNICAL_FIELD' )->set_visible( abap_false ).
            ENDIF.
            IF lv_has_screen = abap_false.
              lo_ev_cols_0650->get_column( 'SCREEN' )->set_visible( abap_false ).
            ENDIF.
            IF lv_has_time = abap_false.
              lo_ev_cols_0650->get_column( 'EVIDENCE_TIME' )->set_visible( abap_false ).
            ENDIF.

            "SAP Object already has a dedicated context field above the grid.
            "Do not waste horizontal space repeating it on every evidence row.
            lo_ev_cols_0650->get_column( 'SAP_OBJECT' )->set_visible( abap_false ).

            "Message ID / Program / Technical Field are backend diagnostics,
            "not primary 0650 information. Keep them out of the user layout;
            "Error Detail / AI analysis can expose them when needed.
            lo_ev_cols_0650->get_column( 'MESSAGE_ID' )->set_technical( abap_true ).
            lo_ev_cols_0650->get_column( 'PROGRAM' )->set_technical( abap_true ).
            lo_ev_cols_0650->get_column( 'TECHNICAL_FIELD' )->set_technical( abap_true ).
            lo_ev_cols_0650->get_column( 'SAP_OBJECT' )->set_technical( abap_true ).

          CATCH cx_salv_not_found.
        ENDTRY.

        go_grid_0650->display( ).
        gv_evidence_shape_0650 = lv_shape_0650.
      CATCH cx_salv_msg INTO DATA(lx_det).
        MESSAGE lx_det->get_text( ) TYPE 'I'.
      CATCH cx_salv_not_found.
    ENDTRY.
  ENDIF.
ENDFORM.

FORM refresh_result_invest_0650.

  DATA: lv_sid      TYPE zbdc_result_bup-session_id,
        lv_group    TYPE char80,
        lv_idx      TYPE i,
        ls_group    TYPE ty_group_0100_disp,
        lv_new_sig  TYPE string.

  lv_sid   = txtp_result_session.
  lv_group = txtp_result_group.

  "Always reread the canonical persisted group state before evaluating a
  "manual or timer refresh.  0650 therefore has the same real-time semantics
  "as 0100 instead of depending on a stale in-memory dashboard snapshot.
  PERFORM refresh_kpi_snapshot_0650.
  PERFORM build_result_signature_0650 CHANGING lv_new_sig.

  "A passive 2-second timer tick with no persisted change must not repaint
  "the grids.  This is the same anti-flicker pattern used by screen 0100.
  IF gv_result_0650_tick = abap_true
     AND gv_sig_0650 = lv_new_sig.
    CLEAR gv_result_0650_tick.
    gv_result_0650_skip_pbo = abap_true.
    RETURN.
  ENDIF.

  gv_sig_0650 = lv_new_sig.
  CLEAR gv_result_0650_tick.

  "Rebuild only the user-facing projection, then refresh the already-created
  "left ALV with a stable row/column viewport.  Normal group selection never
  "rebuilds this list.
  PERFORM build_result_groups_0650.
  IF go_group_grid_0650 IS BOUND.
    DATA(ls_stable_0650) = VALUE lvc_s_stbl( row = abap_true col = abap_true ).
    CALL METHOD go_group_grid_0650->refresh_table_display
      EXPORTING
        is_stable = ls_stable_0650
      EXCEPTIONS
        finished = 1
        OTHERS   = 2.
  ELSE.
    PERFORM display_result_groups_0650.
  ENDIF.

  "Restore the exact selected business group by immutable Session + Group,
  "never by visual row number (headers and sort order can move on refresh).
  IF lv_sid IS NOT INITIAL AND lv_group IS NOT INITIAL.
    CLEAR lv_idx.
    LOOP AT gt_group_ctx_0650 INTO ls_group.
      IF ls_group-session_id = lv_sid AND ls_group-group_key = lv_group.
        lv_idx = sy-tabix.
        EXIT.
      ENDIF.
    ENDLOOP.

    IF lv_idx > 0.
      gv_group_pick_0650 = lv_idx.
      PERFORM select_result_group_0650 USING lv_idx.
    ELSE.
      CLEAR: txtp_result_session, txtp_result_group, txtp_result_status,
             txtp_result_created, txtp_result_executor, txtp_result_row_attempt,
             txtp_result_tcode, txtp_sap_object_id, txtp_result_msg,
             txtp_po_key, gv_result_row_index_0650.
      REFRESH: gt_log_0650, gt_evidence_0650.
    ENDIF.
  ELSE.
    REFRESH: gt_log_0650, gt_evidence_0650.
  ENDIF.

  PERFORM build_evidence_0650.

  IF txtp_result_created IS INITIAL OR txtp_result_created = '-'.
    LOOP AT gt_evidence_0650 INTO DATA(ls_refresh_ev_0650).
      IF ls_refresh_ev_0650-evidence_time IS NOT INITIAL.
        txtp_result_created = ls_refresh_ev_0650-evidence_time.
        EXIT.
      ENDIF.
    ENDLOOP.
  ENDIF.

  "Let the following normal PBO recreate the right evidence control when data
  "really changed; this keeps the 0-row -> 1-row transition reliable.
  CLEAR gv_result_0650_skip_pbo.

ENDFORM.
FORM sync_staging_from_alv.
  LOOP AT gt_staging_alv INTO DATA(ls_alv_final).
    READ TABLE gt_staging ASSIGNING FIELD-SYMBOL(<ls_stg_orig>)
      WITH KEY session_id = ls_alv_final-session_id row_index = ls_alv_final-row_index.
    IF sy-subrc = 0.
      MOVE-CORRESPONDING ls_alv_final TO <ls_stg_orig>.

 "FIELD01 is the frozen generic BUSINESS_KEY slot. RECORD_KEY
 "is the technical grouping key used by execution/dashboard. Keep both
 "identical after user edits so changing BUSINESS_KEY really merges or
 "moves the row to the intended business group instead of only changing
 "the visible Excel value.
      <ls_stg_orig>-record_key = <ls_stg_orig>-field01.
    ENDIF.
  ENDLOOP.
ENDFORM.

*& Generic detail-screen drilldown compatibility
*& Legacy-compatible object-text helper

FORM pick_0100_session
  CHANGING cv_session_id TYPE zbdc_staging_bup-session_id.

  TYPES: BEGIN OF ty_z40_pick,
           session_id TYPE zbdc_staging_bup-session_id,
           tcode      TYPE tcode,
           status     TYPE char40,
           message    TYPE char255,
         END OF ty_z40_pick.

  DATA: lt_pick TYPE STANDARD TABLE OF ty_z40_pick,
        ls_pick TYPE ty_z40_pick,
        lt_ret  TYPE STANDARD TABLE OF ddshretval,
        ls_ret  TYPE ddshretval.

  FIELD-SYMBOLS: <ls_dash> TYPE any,
                 <lv_any>  TYPE any.

  CLEAR cv_session_id.
  REFRESH lt_pick.

 "Build popup list from current 0100 dashboard table.
  LOOP AT gt_dash_0100 ASSIGNING <ls_dash>.

    CLEAR ls_pick.

    ASSIGN COMPONENT 'SESSION_ID' OF STRUCTURE <ls_dash> TO <lv_any>.
    IF sy-subrc = 0 AND <lv_any> IS ASSIGNED.
      ls_pick-session_id = <lv_any>.
    ENDIF.

    ASSIGN COMPONENT 'TCODE' OF STRUCTURE <ls_dash> TO <lv_any>.
    IF sy-subrc = 0 AND <lv_any> IS ASSIGNED.
      ls_pick-tcode = <lv_any>.
    ENDIF.

    ASSIGN COMPONENT 'OVERALL_STATUS' OF STRUCTURE <ls_dash> TO <lv_any>.
    IF sy-subrc = 0 AND <lv_any> IS ASSIGNED.
      ls_pick-status = <lv_any>.
    ENDIF.

    IF ls_pick-status IS INITIAL.
      ASSIGN COMPONENT 'STATUS_TEXT' OF STRUCTURE <ls_dash> TO <lv_any>.
      IF sy-subrc = 0 AND <lv_any> IS ASSIGNED.
        ls_pick-status = <lv_any>.
      ENDIF.
    ENDIF.

    ASSIGN COMPONENT 'PROOF_LAST_MESSAGE' OF STRUCTURE <ls_dash> TO <lv_any>.
    IF sy-subrc = 0 AND <lv_any> IS ASSIGNED.
      ls_pick-message = <lv_any>.
    ENDIF.

    IF ls_pick-message IS INITIAL.
      ASSIGN COMPONENT 'LAST_MESSAGE' OF STRUCTURE <ls_dash> TO <lv_any>.
      IF sy-subrc = 0 AND <lv_any> IS ASSIGNED.
        ls_pick-message = <lv_any>.
      ENDIF.
    ENDIF.

    IF ls_pick-session_id IS NOT INITIAL.
      APPEND ls_pick TO lt_pick.
    ENDIF.

  ENDLOOP.

  IF lt_pick IS INITIAL.
    MESSAGE s617(zbdc) DISPLAY LIKE 'W'.
    RETURN.
  ENDIF.

  CALL FUNCTION 'F4IF_INT_TABLE_VALUE_REQUEST'
    EXPORTING
      retfield        = 'SESSION_ID'
      dynpprog        = sy-repid
      dynpnr          = sy-dynnr
      value_org       = 'S'
      window_title    = 'Choose Staging Session'
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

*& evidence-driven executor projection for dashboard layers

FORM resolve_executor
  USING    pt_result   TYPE ty_t_result_726
  CHANGING cv_executor TYPE char12.

  DATA ls_res TYPE zbdc_result_bup.

  CLEAR cv_executor.

 "callers pass group evidence newest-first. Resolve the newest exact
 "execution method, not "any BISM ever seen". This matters when a group was
 "retried with a different executor. A BISM row may also carry dynpro/field
 "context, so BISM proof is checked before CT on the same evidence row.
  LOOP AT pt_result INTO ls_res.
    IF ls_res-exec_status CP 'SM35*' OR
       ls_res-field_name = 'SM35' OR
       ls_res-message CS 'SM35 session' OR
       ls_res-message CS 'SM35_BIND'.
      cv_executor = 'BISM'.
      RETURN.
    ENDIF.

    IF ls_res-dynpro IS NOT INITIAL OR
       ls_res-field_name IS NOT INITIAL OR
       ls_res-message CS 'CALL TRANSACTION'.
      cv_executor = 'CT'.
      RETURN.
    ENDIF.
  ENDLOOP.

  cv_executor = 'UNKNOWN'.
ENDFORM.

*& choose one useful persisted result text for a current group

*& shared timestamp renderer for the 3-level audit UI

FORM format_result_time
  USING    pv_created TYPE zbdc_result_bup-created_at
  CHANGING cv_text    TYPE char19.

  DATA: lv_date      TYPE sy-datum,
        lv_time      TYPE sy-uzeit,
        lv_date_text TYPE char10,
        lv_time_text TYPE char8.

  CLEAR: cv_text, lv_date, lv_time, lv_date_text, lv_time_text.
  IF pv_created IS INITIAL.
    RETURN.
  ENDIF.

 "keep the typed timestamp conversion, but fail closed on an
 "invalid persisted timestamp and build date/time separately. Plain
 "CONCATENATE ignores an operand that contains only SPACE unless blanks are
 "explicitly respected; that produced values like 2026-09-1012:16:08.
  PERFORM ts_to_demo USING pv_created CHANGING lv_date lv_time.
  IF lv_date IS INITIAL.
    RETURN.
  ENDIF.

  CONCATENATE lv_date+0(4) '-'
              lv_date+4(2) '-'
              lv_date+6(2)
         INTO lv_date_text.
  CONCATENATE lv_time+0(2) ':'
              lv_time+2(2) ':'
              lv_time+4(2)
         INTO lv_time_text.
  CONCATENATE lv_date_text lv_time_text
         INTO cv_text SEPARATED BY space.
ENDFORM.

*& locale-neutral percentage for dashboard/detail UI

FORM format_rate
  USING    pv_num  TYPE i
           pv_den  TYPE i
  CHANGING cv_text TYPE char10.

  DATA: lv_pct  TYPE p LENGTH 5 DECIMALS 1,
        lv_text TYPE char9.

  CLEAR: cv_text, lv_pct, lv_text.
  IF pv_den > 0.
    lv_pct = ( pv_num * 100 ) / pv_den.
  ENDIF.

  WRITE lv_pct TO lv_text DECIMALS 1.
  CONDENSE lv_text NO-GAPS.
  REPLACE ALL OCCURRENCES OF ',' IN lv_text WITH '.'.
  CONCATENATE lv_text '%' INTO cv_text.
ENDFORM.

*& validated timestamp fallback from a generated session ID

FORM format_id_time
  USING    pv_session_id TYPE any
  CHANGING cv_text       TYPE char19
           cv_sort       TYPE char30.

  DATA: lv_src       TYPE string,
        lv_digits    TYPE char30,
        lv_index     TYPE i,
        lv_char      TYPE c LENGTH 1,
        lv_date      TYPE sy-datum,
        lv_time      TYPE sy-uzeit.

  CLEAR: cv_text, cv_sort, lv_src, lv_digits, lv_date, lv_time.
  lv_src = pv_session_id.

  DO strlen( lv_src ) TIMES.
    lv_index = sy-index - 1.
    lv_char = lv_src+lv_index(1).
    IF lv_char CA '0123456789'.
      CONCATENATE lv_digits lv_char INTO lv_digits.
    ENDIF.
  ENDDO.
  CONDENSE lv_digits NO-GAPS.
  IF strlen( lv_digits ) < 14.
    RETURN.
  ENDIF.

 "The first 14 numeric characters are the timestamp component used by this
 "project's generated session IDs. Validate before exposing them as time.
  lv_date = lv_digits+0(8).
  lv_time = lv_digits+8(6).
  IF lv_time+0(2) > '23' OR
     lv_time+2(2) > '59' OR
     lv_time+4(2) > '59'.
    RETURN.
  ENDIF.

 "SESSION_ID digits have no persisted timezone provenance on legacy
 "sessions. Do not expose them as a wall-clock fallback. Keep only the
 "validated digits as a deterministic sort key; visible time stays blank so
 "the caller shows UNKNOWN instead of a potentially wrong server-zone time.
  CALL FUNCTION 'DATE_CHECK_PLAUSIBILITY'
    EXPORTING
      date                      = lv_date
    EXCEPTIONS
      plausibility_check_failed = 1
      OTHERS                    = 2.
  IF sy-subrc <> 0.
    CLEAR: cv_text, cv_sort.
    RETURN.
  ENDIF.
  CLEAR cv_text.
  cv_sort = lv_digits+0(14).
ENDFORM.

*& Level 2 compact expandable Input Data / Changes
*& The main group grid stays narrow. The two hotspot cells show only a
*& count; clicking them opens a compact drop-panel with the full exact data.
*& No SAP execution/protocol evidence is copied into Level 2.

FORM l2_field_label
  USING    is_map   TYPE zbdc_mapping_bup
  CHANGING cv_label TYPE char80.

  DATA: lv_leaf       TYPE zbdc_mapping_bup-source_column,
        lv_src_norm   TYPE string,
        lv_leaf_norm  TYPE string,
        lv_ddic       TYPE char80,
        lv_ddic_found TYPE abap_bool.

  CLEAR cv_label.
  cv_label = is_map-source_column.
  CONDENSE cv_label.

 "Use the user-confirmed/mapped source label by default. Only replace it
 "when it is exactly the technical leaf (or absent) and SAP DDIC proves a
 "friendlier label. No lexical/AI business-name guessing is allowed.
  CLEAR lv_leaf.
  PERFORM get_mapping_leaf_source
    USING    is_map-bdc_field
    CHANGING lv_leaf.

  lv_src_norm  = is_map-source_column.
  lv_leaf_norm = lv_leaf.
  TRANSLATE: lv_src_norm TO UPPER CASE,
             lv_leaf_norm TO UPPER CASE.
  CONDENSE: lv_src_norm NO-GAPS,
            lv_leaf_norm NO-GAPS.

  IF cv_label IS INITIAL OR
     ( lv_leaf_norm IS NOT INITIAL AND lv_src_norm = lv_leaf_norm ).
    CLEAR: lv_ddic, lv_ddic_found.
    PERFORM ddic_label_raw
      USING    is_map-bdc_field
      CHANGING lv_ddic lv_ddic_found.
    IF lv_ddic_found = abap_true AND lv_ddic IS NOT INITIAL.
      cv_label = lv_ddic.
    ENDIF.
  ENDIF.

  IF cv_label IS INITIAL.
    cv_label = is_map-staging_field.
  ENDIF.
ENDFORM.

FORM l2_group_counts
  USING    is_group   TYPE ty_group_0100_disp
  CHANGING cv_inputs  TYPE i
           cv_changes TYPE i.

  TYPES: BEGIN OF ty_z749_chg_raw,
           session_id TYPE zbdc_staging_bup-session_id,
           row_index  TYPE zbdc_staging_bup-row_index,
           field_name TYPE char30,
           old_value  TYPE char255,
           new_value  TYPE char255,
         END OF ty_z749_chg_raw.

  DATA: lt_rows      TYPE STANDARD TABLE OF zbdc_staging_bup,
        lt_map       TYPE STANDARD TABLE OF zbdc_mapping_bup,
        lt_chg       TYPE STANDARD TABLE OF ty_z749_chg_raw,
        ls_map       TYPE zbdc_mapping_bup,
        lv_tcode     TYPE zbdc_prof_bup-tcode,
        lv_profile   TYPE zbdc_prof_bup-profile_name,
        lv_ver       TYPE zbdc_prof_bup-profile_ver,
        lv_found     TYPE abap_bool,
        lv_map_count TYPE i,
        lv_exists    TYPE abap_bool,
        lv_tab       TYPE tabname,
        lv_where     TYPE string.

  CLEAR: cv_inputs, cv_changes.

  IF is_group-record_key IS NOT INITIAL.
    SELECT * FROM zbdc_staging_bup
      INTO TABLE @lt_rows
      WHERE session_id = @is_group-session_id
        AND record_key = @is_group-record_key.
  ELSE.
    SELECT * FROM zbdc_staging_bup
      INTO TABLE @lt_rows
      WHERE session_id = @is_group-session_id
        AND row_index  = @is_group-row_index.
  ENDIF.
  IF lt_rows IS INITIAL.
    RETURN.
  ENDIF.

  PERFORM resolve_session_context
    USING    is_group-session_id
    CHANGING lv_tcode lv_profile lv_ver lv_found.
  IF lv_found = abap_true.
    SELECT * FROM zbdc_mapping_bup
      INTO TABLE @lt_map
      WHERE tcode        = @lv_tcode
        AND profile_name = @lv_profile
        AND profile_ver  = @lv_ver.
    DELETE lt_map WHERE staging_field IS INITIAL OR bdc_field IS INITIAL.
    SORT lt_map BY staging_field source_column.
    DELETE ADJACENT DUPLICATES FROM lt_map COMPARING staging_field.

    LOOP AT lt_map INTO ls_map.
      IF ls_map-staging_field(5) = 'FIELD'.
        lv_map_count = lv_map_count + 1.
      ENDIF.
    ENDLOOP.
    cv_inputs = lv_map_count * lines( lt_rows ).
  ENDIF.

  PERFORM table_exists USING gc_z16_tab_chg CHANGING lv_exists.
  IF lv_exists <> abap_true.
    RETURN.
  ENDIF.

  lv_tab = gc_z16_tab_chg.
  lv_where = |SESSION_ID = '{ is_group-session_id }'|.
  TRY.
      SELECT * FROM (lv_tab)
        INTO CORRESPONDING FIELDS OF TABLE @lt_chg
        WHERE (lv_where).
    CATCH cx_root.
      RETURN.
  ENDTRY.

  LOOP AT lt_chg INTO DATA(ls_chg).
    READ TABLE lt_rows TRANSPORTING NO FIELDS
      WITH KEY row_index = ls_chg-row_index.
    IF sy-subrc = 0.
      cv_changes = cv_changes + 1.
    ENDIF.
  ENDLOOP.
ENDFORM.

*& Level 2 Input Data using the same scrollable long-text style
*& as Runtime Issue Detail / Fix Guide. The hotspot/count logic stays
*& generic; only the presentation surface changes from compact SALV to HTML.

FORM html_open
  USING    iv_title TYPE csequence
  CHANGING ct_html  TYPE ty_t_dash_html_411.

  REFRESH ct_html.
  APPEND '<html><head>' TO ct_html.
  APPEND '<meta http-equiv="X-UA-Compatible" content="IE=edge">' TO ct_html.
  APPEND '<meta charset="utf-8">' TO ct_html.
  APPEND '<style>' TO ct_html.
  APPEND 'html{width:100%;height:100%;margin:0;padding:0;overflow-y:scroll;overflow-x:hidden;background:#f5f7fa;}' TO ct_html.
  APPEND 'body{width:100%;min-height:100%;margin:0;padding:0;background:#f5f7fa;font-family:Arial,sans-serif;color:#172b4d;}' TO ct_html.
  APPEND '.wrap{box-sizing:border-box;padding:14px 16px 110px 16px;min-height:100%;}' TO ct_html.
  APPEND '.title{font-size:18px;font-weight:700;margin:0 0 12px 0;color:#0b4f8a;}' TO ct_html.
  APPEND 'table{width:100%;border-collapse:collapse;table-layout:fixed;background:#fff;border:1px solid #d8dee8;}' TO ct_html.
  APPEND 'td{border-bottom:1px solid #e1e6ee;vertical-align:top;}' TO ct_html.
  APPEND '.label{width:32%;padding:7px 10px;font-weight:600;background:#f7f9fc;overflow-wrap:anywhere;}' TO ct_html.
  APPEND '.value{width:68%;padding:7px 10px;word-wrap:break-word;overflow-wrap:anywhere;}' TO ct_html.
  APPEND '.section{padding:8px 10px;font-weight:700;background:#eaf3ff;color:#153e75;}' TO ct_html.
  APPEND '.txt{font-size:0;line-height:1.45;}' TO ct_html.
  APPEND '.tok{font-size:13px;line-height:1.45;}' TO ct_html.
  APPEND '.title .tok{font-size:18px;font-weight:700;}' TO ct_html.
  APPEND '</style></head><body><div class="wrap">' TO ct_html.
  APPEND '<div class="title txt">' TO ct_html.
  PERFORM append_html_text USING iv_title CHANGING ct_html.
  APPEND '</div><table>' TO ct_html.
ENDFORM.

FORM html_section
  USING    iv_text TYPE csequence
  CHANGING ct_html TYPE ty_t_dash_html_411.

  APPEND '<tr><td class="section txt" colspan="2">' TO ct_html.
  PERFORM append_html_text USING iv_text CHANGING ct_html.
  APPEND '</td></tr>' TO ct_html.
ENDFORM.

FORM html_kv
  USING    iv_label TYPE csequence
           iv_value TYPE csequence
  CHANGING ct_html  TYPE ty_t_dash_html_411.

  APPEND '<tr><td class="label txt">' TO ct_html.
  PERFORM append_html_text USING iv_label CHANGING ct_html.
  APPEND '</td><td class="value txt">' TO ct_html.
  PERFORM append_html_text USING iv_value CHANGING ct_html.
  APPEND '</td></tr>' TO ct_html.
ENDFORM.

FORM html_close
  CHANGING ct_html TYPE ty_t_dash_html_411.
  APPEND '</table></div></body></html>' TO ct_html.
ENDFORM.

FORM show_html_panel
  USING    it_html  TYPE ty_t_dash_html_411
           iv_title TYPE csequence
  CHANGING cv_ok    TYPE abap_bool.

  DATA: lv_caption TYPE c LENGTH 100,
        lt_html    TYPE ty_t_dash_html_411.

  CLEAR cv_ok.
  IF it_html IS INITIAL.
    RETURN.
  ENDIF.

  lt_html = it_html.
  PERFORM free_long_dialog.
  lv_caption = iv_title.

  CREATE OBJECT go_long_812_dlg
    EXPORTING
      width   = 1000
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
      cntl_error = 1
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

FORM l2_show_panel
  USING is_group  TYPE ty_group_0100_disp
        iv_column TYPE any.

  TYPES: BEGIN OF ty_z749_input_disp,
           row_index   TYPE zbdc_staging_bup-row_index,
           field_label TYPE char80,
           field_value TYPE char255,
         END OF ty_z749_input_disp.
  TYPES: BEGIN OF ty_z749_change_raw,
           session_id    TYPE zbdc_staging_bup-session_id,
           row_index     TYPE zbdc_staging_bup-row_index,
           field_name    TYPE char30,
           old_value     TYPE char255,
           new_value     TYPE char255,
           changed_at    TYPE timestampl,
         END OF ty_z749_change_raw.
  TYPES: BEGIN OF ty_z749_change_disp,
           row_index   TYPE zbdc_staging_bup-row_index,
           field_label TYPE char80,
           before_value TYPE char255,
           after_value  TYPE char255,
         END OF ty_z749_change_disp.

  DATA: lt_rows       TYPE STANDARD TABLE OF zbdc_staging_bup,
        lt_map        TYPE STANDARD TABLE OF zbdc_mapping_bup,
        lt_input      TYPE STANDARD TABLE OF ty_z749_input_disp,
        lt_chg_raw    TYPE STANDARD TABLE OF ty_z749_change_raw,
        lt_changes    TYPE STANDARD TABLE OF ty_z749_change_disp,
        lt_html       TYPE ty_t_dash_html_411,
        ls_map        TYPE zbdc_mapping_bup,
        lv_tcode      TYPE zbdc_prof_bup-tcode,
        lv_profile    TYPE zbdc_prof_bup-profile_name,
        lv_ver        TYPE zbdc_prof_bup-profile_ver,
        lv_found      TYPE abap_bool,
        lv_value      TYPE string,
        lv_label      TYPE char80,
        lv_exists     TYPE abap_bool,
        lv_tab        TYPE tabname,
        lv_where      TYPE string,
        lv_title      TYPE lvc_title,
        lv_html_ok    TYPE abap_bool,
        lv_count_text TYPE string,
        lv_row_title  TYPE string,
        lv_prev_row   TYPE zbdc_staging_bup-row_index,
        lo_salv       TYPE REF TO cl_salv_table,
        lo_cols       TYPE REF TO cl_salv_columns_table.
  FIELD-SYMBOLS <lv_value> TYPE any.

  IF is_group-record_key IS NOT INITIAL.
    SELECT * FROM zbdc_staging_bup
      INTO TABLE @lt_rows
      WHERE session_id = @is_group-session_id
        AND record_key = @is_group-record_key
      ORDER BY row_index ASCENDING.
  ELSE.
    SELECT * FROM zbdc_staging_bup
      INTO TABLE @lt_rows
      WHERE session_id = @is_group-session_id
        AND row_index  = @is_group-row_index
      ORDER BY row_index ASCENDING.
  ENDIF.
  IF lt_rows IS INITIAL.
    MESSAGE 'No persisted staging rows exist for this group.' TYPE 'S' DISPLAY LIKE 'I'.
    RETURN.
  ENDIF.

  PERFORM resolve_session_context
    USING    is_group-session_id
    CHANGING lv_tcode lv_profile lv_ver lv_found.
  IF lv_found <> abap_true.
    MESSAGE 'The frozen mapping context for this group is unavailable.' TYPE 'S' DISPLAY LIKE 'I'.
    RETURN.
  ENDIF.

  SELECT * FROM zbdc_mapping_bup
    INTO TABLE @lt_map
    WHERE tcode        = @lv_tcode
      AND profile_name = @lv_profile
      AND profile_ver  = @lv_ver.
  DELETE lt_map WHERE staging_field IS INITIAL OR bdc_field IS INITIAL.
  SORT lt_map BY staging_field source_column.
  DELETE ADJACENT DUPLICATES FROM lt_map COMPARING staging_field.

  IF iv_column = 'INPUT_DATA'.
    LOOP AT lt_rows INTO DATA(ls_row).
      LOOP AT lt_map INTO ls_map.
        IF ls_map-staging_field(5) <> 'FIELD'.
          CONTINUE.
        ENDIF.

        ASSIGN COMPONENT ls_map-staging_field OF STRUCTURE ls_row TO <lv_value>.
        IF sy-subrc <> 0 OR <lv_value> IS NOT ASSIGNED.
          UNASSIGN <lv_value>.
          CONTINUE.
        ENDIF.
        lv_value = |{ <lv_value> }|.
        UNASSIGN <lv_value>.
        IF lv_value IS INITIAL.
          lv_value = '-'.
        ENDIF.

        CLEAR lv_label.
        PERFORM l2_field_label USING ls_map CHANGING lv_label.
        APPEND VALUE ty_z749_input_disp(
          row_index   = ls_row-row_index
          field_label = lv_label
          field_value = lv_value ) TO lt_input.
      ENDLOOP.
    ENDLOOP.

    IF lt_input IS INITIAL.
      MESSAGE 'No mapped input data is available for this group.' TYPE 'S' DISPLAY LIKE 'I'.
      RETURN.
    ENDIF.

 "primary surface: same user-friendly HTML style as Fix Guide /
 "Runtime Issue Detail. Values stay exact and the browser handles wrapping
 "and scrolling; the original SALV remains only as a frontend fallback.
    lv_title = |Input Data - { is_group-group_key }|.
    PERFORM html_open USING lv_title CHANGING lt_html.
    PERFORM html_section USING '1. CONTEXT' CHANGING lt_html.
    PERFORM html_kv USING 'Business Group' is_group-group_key CHANGING lt_html.
    PERFORM html_kv USING 'TCode' lv_tcode CHANGING lt_html.
    lv_count_text = |{ lines( lt_rows ) }|.
    PERFORM html_kv USING 'Input Rows' lv_count_text CHANGING lt_html.
    lv_count_text = |{ lines( lt_input ) }|.
    PERFORM html_kv USING 'Mapped Values' lv_count_text CHANGING lt_html.
    PERFORM html_section USING '2. INPUT DATA' CHANGING lt_html.

    CLEAR lv_prev_row.
    LOOP AT lt_input INTO DATA(ls_input_html).
      IF lines( lt_rows ) > 1 AND ls_input_html-row_index <> lv_prev_row.
        lv_row_title = |Row { ls_input_html-row_index }|.
        PERFORM html_section USING lv_row_title CHANGING lt_html.
        lv_prev_row = ls_input_html-row_index.
      ENDIF.
      PERFORM html_kv
        USING ls_input_html-field_label ls_input_html-field_value
        CHANGING lt_html.
    ENDLOOP.

    PERFORM html_close CHANGING lt_html.
    CLEAR lv_html_ok.
    PERFORM show_html_panel USING lt_html lv_title CHANGING lv_html_ok.
    IF lv_html_ok = abap_true.
      RETURN.
    ENDIF.

    TRY.
        cl_salv_table=>factory(
          IMPORTING r_salv_table = lo_salv
          CHANGING  t_table      = lt_input ).
        lo_salv->get_functions( )->set_all( abap_true ).
        lo_salv->get_columns( )->set_optimize( abap_false ).
        lo_salv->get_display_settings( )->set_striped_pattern( abap_true ).
        lo_cols = lo_salv->get_columns( ).
        PERFORM set_dash_col_text USING lo_cols 'ROW_INDEX'   'Row'.
        PERFORM set_dash_col_text USING lo_cols 'FIELD_LABEL' 'Input Field'.
        PERFORM set_dash_col_text USING lo_cols 'FIELD_VALUE' 'Entered Value'.
        TRY.
            lo_cols->get_column( 'ROW_INDEX' )->set_output_length( 8 ).
            lo_cols->get_column( 'FIELD_LABEL' )->set_output_length( 34 ).
            lo_cols->get_column( 'FIELD_VALUE' )->set_output_length( 55 ).
          CATCH cx_salv_not_found.
        ENDTRY.
        lv_title = |Input Data - { is_group-group_key }|.
        lo_salv->get_display_settings( )->set_list_header( lv_title ).
        lo_salv->set_screen_popup(
          start_column = 52
          end_column   = 158
          start_line   = 7
          end_line     = 24 ).
        lo_salv->display( ).
      CATCH cx_salv_msg INTO DATA(lx_input_salv).
        MESSAGE lx_input_salv->get_text( ) TYPE 'S' DISPLAY LIKE 'E'.
    ENDTRY.
    RETURN.
  ENDIF.

  IF iv_column <> 'CHANGES'.
    RETURN.
  ENDIF.

  PERFORM table_exists USING gc_z16_tab_chg CHANGING lv_exists.
  IF lv_exists <> abap_true.
    MESSAGE 'No persisted change audit is available for this group.' TYPE 'S' DISPLAY LIKE 'I'.
    RETURN.
  ENDIF.

  lv_tab = gc_z16_tab_chg.
  lv_where = |SESSION_ID = '{ is_group-session_id }'|.
  TRY.
      SELECT * FROM (lv_tab)
        INTO CORRESPONDING FIELDS OF TABLE @lt_chg_raw
        WHERE (lv_where).
    CATCH cx_root INTO DATA(lx_change_read).
      MESSAGE lx_change_read->get_text( ) TYPE 'S' DISPLAY LIKE 'E'.
      RETURN.
  ENDTRY.

  SORT lt_chg_raw BY changed_at ASCENDING row_index ASCENDING field_name ASCENDING.
  LOOP AT lt_chg_raw INTO DATA(ls_chg_raw).
    READ TABLE lt_rows INTO DATA(ls_chg_row)
      WITH KEY row_index = ls_chg_raw-row_index.
    IF sy-subrc <> 0.
      CONTINUE.
    ENDIF.

    CLEAR: ls_map, lv_label.
    READ TABLE lt_map INTO ls_map WITH KEY staging_field = ls_chg_raw-field_name.
    IF sy-subrc = 0.
      PERFORM l2_field_label USING ls_map CHANGING lv_label.
    ELSE.
      lv_label = ls_chg_raw-field_name.
    ENDIF.

    APPEND VALUE ty_z749_change_disp(
      row_index    = ls_chg_raw-row_index
      field_label  = lv_label
      before_value = ls_chg_raw-old_value
      after_value  = ls_chg_raw-new_value ) TO lt_changes.
  ENDLOOP.

  IF lt_changes IS INITIAL.
    RETURN.
  ENDIF.

  TRY.
      CLEAR lo_salv.
      cl_salv_table=>factory(
        IMPORTING r_salv_table = lo_salv
        CHANGING  t_table      = lt_changes ).
      lo_salv->get_functions( )->set_all( abap_true ).
      lo_salv->get_columns( )->set_optimize( abap_false ).
      lo_salv->get_display_settings( )->set_striped_pattern( abap_true ).
      lo_cols = lo_salv->get_columns( ).
      PERFORM set_dash_col_text USING lo_cols 'ROW_INDEX'    'Row'.
      PERFORM set_dash_col_text USING lo_cols 'FIELD_LABEL'  'Changed Field'.
      PERFORM set_dash_col_text USING lo_cols 'BEFORE_VALUE' 'Before'.
      PERFORM set_dash_col_text USING lo_cols 'AFTER_VALUE'  'After'.
      TRY.
          lo_cols->get_column( 'ROW_INDEX' )->set_output_length( 8 ).
          lo_cols->get_column( 'FIELD_LABEL' )->set_output_length( 30 ).
          lo_cols->get_column( 'BEFORE_VALUE' )->set_output_length( 38 ).
          lo_cols->get_column( 'AFTER_VALUE' )->set_output_length( 38 ).
        CATCH cx_salv_not_found.
      ENDTRY.
      lv_title = |Changes - { is_group-group_key }|.
      lo_salv->get_display_settings( )->set_list_header( lv_title ).
      lo_salv->set_screen_popup(
        start_column = 42
        end_column   = 162
        start_line   = 7
        end_line     = 22 ).
      lo_salv->display( ).
    CATCH cx_salv_msg INTO DATA(lx_change_salv).
      MESSAGE lx_change_salv->get_text( ) TYPE 'S' DISPLAY LIKE 'E'.
  ENDTRY.
ENDFORM.

*& Open canonical Level 2 from one 0400 cockpit business group
*& Rebuild only the selected session's exact staging-group snapshot from DB.
*& No execution, retry, grouping persistence or result evidence is mutated.

*& Level 2: Session Group Detail with compact expandable data
*& One exact session -> one row per canonical business group.

FORM show_session_groups
  USING is_session TYPE ty_dash_0100_disp.

  TYPES: BEGIN OF ty_l2_tcode_scope_761,
           value TYPE char20,
         END OF ty_l2_tcode_scope_761.
  DATA: ls_kpi         TYPE ty_kpi_group_0100,
        ls_group       TYPE ty_group_0100_disp,
        ls_res         TYPE zbdc_result_bup,
        lt_res         TYPE ty_t_result_726,
        lv_title       TYPE lvc_title,
        lv_group_count TYPE i,
        lv_success     TYPE i,
        lv_warning     TYPE i,
        lv_error       TYPE i,
        lv_open        TYPE i,
        lv_min_at      TYPE zbdc_result_bup-created_at,
        lv_max_at      TYPE zbdc_result_bup-created_at,
        lv_input_count TYPE i,
        lv_change_count TYPE i,
        lv_result_tcode TYPE char20,
        lv_tcode_conflict TYPE abap_bool,
        lt_l2_tcodes TYPE SORTED TABLE OF ty_l2_tcode_scope_761
                       WITH UNIQUE KEY value,
        ls_l2_tcode  TYPE ty_l2_tcode_scope_761,
        lv_l2_tcode_count TYPE i,
        lv_l2_unknown_tcode TYPE i,
        lv_l2_tcode_scope TYPE string,
        lv_l2_group_scope TYPE string,
        lv_single_group_781 TYPE abap_bool,
        ls_single_group_781 TYPE ty_group_0100_disp,
        lo_top         TYPE REF TO cl_salv_form_layout_grid,
        lo_label       TYPE REF TO cl_salv_form_label,
        lo_text        TYPE REF TO cl_salv_form_text,
        ls_cell_type   TYPE salv_s_int4_column,
        lt_focus_rows  TYPE salv_t_row.

  REFRESH gt_group_0100.
  FREE go_group_grid_0100.

  LOOP AT gt_kpi_group_0100 INTO ls_kpi
    WHERE session_id = is_session-session_id.

    CLEAR: ls_group, lv_min_at, lv_max_at.
    REFRESH lt_res.

    ls_group-session_id = ls_kpi-session_id.
    ls_group-record_key = ls_kpi-record_key.
    ls_group-row_index  = ls_kpi-row_index.
    ls_group-tcode      = ls_kpi-tcode.
    ls_group-row_count  = ls_kpi-row_count.
    ls_group-lifecycle  = ls_kpi-state.

 "Level 2: show a user-facing exact business-group identity. Keep
 "the canonical K:/R: projection key internal in LS_KPI/RECORD_KEY.
    IF ls_kpi-record_key IS NOT INITIAL.
      ls_group-group_key = ls_kpi-record_key.
    ELSEIF ls_kpi-row_index IS NOT INITIAL.
      ls_group-group_key = |ROW { ls_kpi-row_index }|.
    ELSE.
      ls_group-group_key = ls_kpi-group_key.
    ENDIF.
 "use the same user-facing lifecycle vocabulary in Level 2.
 "Technical PROCESSED is presented as VERIFYING; SM35 aliases are rendered
 "as the BISM-specific SM35 QUEUED state; internal QUEUED/MIXED are folded
 "into PROCESSING rather than exposing ambiguous implementation states.
    CASE ls_group-lifecycle.
      WHEN 'SM35QUEUE' OR 'SM35_QUEUED' OR 'SM35RUN' OR 'QUEUED_SM35'.
        ls_group-lifecycle = 'SM35 QUEUED'.
      WHEN 'PROCESSED'.
        ls_group-lifecycle = 'VERIFYING'.
      WHEN 'QUEUED' OR 'MIXED'.
        ls_group-lifecycle = 'PROCESSING'.
    ENDCASE.

    IF ls_kpi-record_key IS NOT INITIAL.
      SELECT * FROM zbdc_result_bup
        INTO TABLE @lt_res
        WHERE session_id = @ls_kpi-session_id
          AND record_key = @ls_kpi-record_key
        ORDER BY created_at DESCENDING.
    ELSE.
      SELECT * FROM zbdc_result_bup
        INTO TABLE @lt_res
        WHERE session_id = @ls_kpi-session_id
          AND row_index  = @ls_kpi-row_index
        ORDER BY created_at DESCENDING.
    ENDIF.

    ls_group-evidence_rows = lines( lt_res ).
    PERFORM resolve_executor
      USING    lt_res
      CHANGING ls_group-executor.
    IF ls_group-executor = 'UNKNOWN' AND
       ls_group-lifecycle = 'SM35 QUEUED'.
 "SM35 QUEUED is exact current-group evidence of the BISM executor.
      ls_group-executor = 'BISM'.
    ENDIF.

 "READY means this group has not been executed yet, so there is
 "no user-facing executor to show. Keep UNKNOWN as an internal resolver
 "result, but render a neutral dash in the Level-2 display row only.
    IF ls_group-executor = 'UNKNOWN' AND
       ls_group-lifecycle = 'READY'.
      ls_group-executor = '-'.
    ENDIF.

 "Level 2 must remain group-specific. Never inherit TCode or
 "executor from the common session header; a mixed session may legitimately
 "contain different TCodes and execution methods in different groups.
    CLEAR: lv_result_tcode, lv_tcode_conflict.
    LOOP AT lt_res INTO ls_res.
      IF ls_res-tcode IS NOT INITIAL.
        IF lv_result_tcode IS INITIAL.
          lv_result_tcode = ls_res-tcode.
        ELSEIF lv_result_tcode <> ls_res-tcode.
          lv_tcode_conflict = abap_true.
        ENDIF.
      ENDIF.
      IF ls_res-attempt_no > ls_group-attempt.
        ls_group-attempt = ls_res-attempt_no.
      ENDIF.
      IF lv_min_at IS INITIAL OR ls_res-created_at < lv_min_at.
        lv_min_at = ls_res-created_at.
      ENDIF.
      IF lv_max_at IS INITIAL OR ls_res-created_at > lv_max_at.
        lv_max_at = ls_res-created_at.
      ENDIF.
      IF ls_group-last_evidence IS INITIAL OR
         ls_res-created_at > ls_group-last_evidence.
        ls_group-last_evidence = ls_res-created_at.
      ENDIF.
    ENDLOOP.

    IF ls_group-tcode IS INITIAL.
      IF lv_tcode_conflict = abap_true.
        ls_group-tcode = 'MULTIPLE'.
      ELSEIF lv_result_tcode IS NOT INITIAL.
        ls_group-tcode = lv_result_tcode.
      ELSE.
        ls_group-tcode = 'UNKNOWN'.
      ENDIF.
    ENDIF.

    IF ls_group-attempt > 1.
      ls_group-retry_count = ls_group-attempt - 1.
    ENDIF.

    PERFORM format_result_time
      USING    lv_min_at
      CHANGING ls_group-started_at.

    IF ls_group-lifecycle = 'SUCCESS' OR
       ls_group-lifecycle = 'WARNING' OR
       ls_group-lifecycle = 'ERROR'.
      PERFORM format_result_time
        USING    lv_max_at
        CHANGING ls_group-finished_at.
    ELSE.
      ls_group-finished_at = '-'.
    ENDIF.

    CLEAR: lv_input_count, lv_change_count.
    PERFORM l2_group_counts
      USING    ls_group
      CHANGING lv_input_count lv_change_count.

    REFRESH ls_group-cell_types.

    IF lv_input_count > 0.
      ls_group-input_data = |View { lv_input_count } fields|.
      CLEAR ls_cell_type.
      ls_cell_type-columnname = 'INPUT_DATA'.
      ls_cell_type-value      = if_salv_c_cell_type=>hotspot.
      APPEND ls_cell_type TO ls_group-cell_types.
    ELSE.
      ls_group-input_data = '-'.
    ENDIF.

    IF lv_change_count > 0.
      IF lv_change_count = 1.
        ls_group-changes = 'View 1 change'.
      ELSE.
        ls_group-changes = |View { lv_change_count } changes|.
      ENDIF.
      CLEAR ls_cell_type.
      ls_cell_type-columnname = 'CHANGES'.
      ls_cell_type-value      = if_salv_c_cell_type=>hotspot.
      APPEND ls_cell_type TO ls_group-cell_types.
    ELSE.
      ls_group-changes = '-'.
    ENDIF.

 "Level 2 shows execution state + compact business input access.
 "Exact SAP/SM35 evidence remains only in Level 3.
    CASE ls_group-lifecycle.
      WHEN 'ERROR'.
        ls_group-health = icon_red_light.
        lv_error = lv_error + 1.
      WHEN 'WARNING'.
        ls_group-health = icon_yellow_light.
        lv_warning = lv_warning + 1.
      WHEN 'SUCCESS'.
        ls_group-health = icon_green_light.
        lv_success = lv_success + 1.
      WHEN OTHERS.
        ls_group-health = icon_yellow_light.
        lv_open = lv_open + 1.
    ENDCASE.

    APPEND ls_group TO gt_group_0100.
  ENDLOOP.

  lv_group_count = lines( gt_group_0100 ).
  IF lv_group_count = 0.
    MESSAGE 'This persisted session has no current canonical staging groups.'
      TYPE 'S' DISPLAY LIKE 'I'.
    RETURN.
  ENDIF.

  SORT gt_group_0100 BY group_key.

 "Z775 now feeds only the exact clicked business group. Keep the
 "normal session drilldown unchanged when Level 2 is opened from Level 1.
  CLEAR: lv_single_group_781, ls_single_group_781.
  IF gv_z775_focus_group IS NOT INITIAL AND lines( gt_group_0100 ) = 1.
    lv_single_group_781 = abap_true.
    READ TABLE gt_group_0100 INTO ls_single_group_781 INDEX 1.
  ENDIF.

 "when Level 2 is opened from the 0400 Group Details hotspot,
 "preselect the exact business group that the user clicked. This is
 "presentation only; no staging selection/execution scope is changed.
  REFRESH lt_focus_rows.
  IF gv_z775_focus_group IS NOT INITIAL.
    LOOP AT gt_group_0100 INTO DATA(ls_focus_group_775).
      IF ls_focus_group_775-record_key = gv_z775_focus_group OR
         ls_focus_group_775-group_key  = gv_z775_focus_group.
        APPEND sy-tabix TO lt_focus_rows.
        EXIT.
      ENDIF.
    ENDLOOP.
  ENDIF.

 "Level-2 header summarizes only useful common session context.
 "Execution Method is intentionally NOT aggregated here: CT/BISM belongs to
 "each business-group row, where it is exact and actionable. This also avoids
 "extra executor aggregation code that had no remaining UI consumer.
  REFRESH lt_l2_tcodes.
  CLEAR: lv_l2_unknown_tcode, lv_l2_tcode_scope, lv_l2_group_scope.

  LOOP AT gt_group_0100 INTO DATA(ls_l2_scope_group).
    IF ls_l2_scope_group-tcode IS INITIAL OR
       ls_l2_scope_group-tcode = 'UNKNOWN' OR
       ls_l2_scope_group-tcode = 'MULTIPLE'.
      lv_l2_unknown_tcode = lv_l2_unknown_tcode + 1.
    ELSE.
      CLEAR ls_l2_tcode.
      ls_l2_tcode-value = ls_l2_scope_group-tcode.
      INSERT ls_l2_tcode INTO TABLE lt_l2_tcodes.
    ENDIF.
  ENDLOOP.

  lv_l2_group_scope = |{ lv_group_count }|.

  lv_l2_tcode_count = lines( lt_l2_tcodes ).
  CASE lv_l2_tcode_count.
    WHEN 0.
      lv_l2_tcode_scope = 'Pending'.
    WHEN 1.
      READ TABLE lt_l2_tcodes INTO ls_l2_tcode INDEX 1.
      IF sy-subrc = 0.
        lv_l2_tcode_scope = ls_l2_tcode-value.
      ENDIF.
    WHEN OTHERS.
      lv_l2_tcode_scope = |{ lv_l2_tcode_count } TCodes|.
  ENDCASE.
  IF lv_l2_unknown_tcode > 0 AND lv_l2_tcode_count > 0.
    CONCATENATE lv_l2_tcode_scope '+ pending'
      INTO lv_l2_tcode_scope SEPARATED BY space.
  ENDIF.

  TRY.
      cl_salv_table=>factory(
        IMPORTING r_salv_table = go_group_grid_0100
        CHANGING  t_table      = gt_group_0100 ).

      go_group_grid_0100->get_functions( )->set_all( abap_true ).
      go_group_grid_0100->get_columns( )->set_optimize( abap_false ).
      go_group_grid_0100->get_selections( )->set_selection_mode(
        if_salv_c_selection_mode=>row_column ).
      IF lt_focus_rows IS NOT INITIAL.
        go_group_grid_0100->get_selections( )->set_selected_rows( lt_focus_rows ).
      ENDIF.
      TRY.
          go_group_grid_0100->get_display_settings( )->set_striped_pattern( abap_true ).
        CATCH cx_root.
      ENDTRY.

      DATA(lo_cols) = go_group_grid_0100->get_columns( ).
      PERFORM set_dash_col_text USING lo_cols 'HEALTH'        'Health'.
      PERFORM set_dash_col_text USING lo_cols 'GROUP_KEY'     'Group Key'.
      PERFORM set_dash_col_text USING lo_cols 'TCODE'         'TCode'.
      PERFORM set_dash_col_text USING lo_cols 'ROW_COUNT'     'Rows'.
      PERFORM set_dash_col_text USING lo_cols 'EXECUTOR'      'Executor'.
      PERFORM set_dash_col_text USING lo_cols 'LIFECYCLE'     'Lifecycle'.
      PERFORM set_dash_col_text USING lo_cols 'STARTED_AT'    'Started At'.
      PERFORM set_dash_col_text USING lo_cols 'FINISHED_AT'   'Finished At'.
      PERFORM set_dash_col_text USING lo_cols 'RETRY_COUNT'   'Retry'.
      PERFORM set_dash_col_text USING lo_cols 'INPUT_DATA'     'Input Data'.
      PERFORM set_dash_col_text USING lo_cols 'CHANGES'        'Changes'.

      TRY.
 "fit the complete Level-2 row in the wide popup so users
 "keep the compact Level-2 row visible without horizontal disruption.
          lo_cols->get_column( 'HEALTH' )->set_output_length( 5 ).
          lo_cols->get_column( 'GROUP_KEY' )->set_output_length( 20 ).
          lo_cols->get_column( 'TCODE' )->set_output_length( 8 ).
          lo_cols->get_column( 'ROW_COUNT' )->set_output_length( 5 ).
          lo_cols->get_column( 'EXECUTOR' )->set_output_length( 8 ).
          lo_cols->get_column( 'LIFECYCLE' )->set_output_length( 18 ).
          lo_cols->get_column( 'STARTED_AT' )->set_output_length( 19 ).
          lo_cols->get_column( 'FINISHED_AT' )->set_output_length( 19 ).
          lo_cols->get_column( 'RETRY_COUNT' )->set_output_length( 5 ).
          lo_cols->get_column( 'INPUT_DATA' )->set_output_length( 18 ).
          lo_cols->get_column( 'CHANGES' )->set_output_length( 18 ).
          lo_cols->get_column( 'ATTEMPT' )->set_visible( abap_false ).
          lo_cols->get_column( 'EVIDENCE_ROWS' )->set_visible( abap_false ).
          lo_cols->get_column( 'LAST_EVIDENCE' )->set_visible( abap_false ).
          lo_cols->get_column( 'SESSION_ID' )->set_visible( abap_false ).
          lo_cols->get_column( 'RECORD_KEY' )->set_visible( abap_false ).
          lo_cols->get_column( 'ROW_INDEX' )->set_visible( abap_false ).
          lo_cols->get_column( 'CELL_TYPES' )->set_visible( abap_false ).
        CATCH cx_salv_not_found.
      ENDTRY.

 "apply hotspot style per cell, not per whole column. INPUT_DATA
 "is clickable only when it contains mapped fields. CHANGES is clickable
 "only when real change rows exist. A plain '-' therefore stays ordinary
 "ALV text (no underline) while Started At / Finished At remain separate.
      TRY.
          lo_cols->set_cell_type_column( 'CELL_TYPES' ).
        CATCH cx_salv_data_error.
      ENDTRY.

      IF lv_single_group_781 = abap_true.
        lv_title = |Business Group Detail - { ls_single_group_781-group_key }|.
      ELSE.
        lv_title = |Session Group Detail - { is_session-session_id }|.
      ENDIF.
      go_group_grid_0100->get_display_settings( )->set_list_header( lv_title ).

      CREATE OBJECT lo_top.

      IF lv_single_group_781 = abap_true.
 "exact group mode. Show only facts belonging to the clicked
 "business group; do not present a session-wide overview above it.
        lo_label = lo_top->create_label( row = 1 column = 1 ).
        lo_label->set_text( 'Business Group Overview' ).

        lo_label = lo_top->create_label( row = 2 column = 1 ).
        lo_label->set_text( 'Group Key:' ).
        lo_text = lo_top->create_text( row = 2 column = 2 ).
        lo_text->set_text( ls_single_group_781-group_key ).

        lo_label = lo_top->create_label( row = 2 column = 4 ).
        lo_label->set_text( 'TCode:' ).
        lo_text = lo_top->create_text( row = 2 column = 5 ).
        lo_text->set_text( ls_single_group_781-tcode ).

        lo_label = lo_top->create_label( row = 2 column = 7 ).
        lo_label->set_text( 'Rows:' ).
        lo_text = lo_top->create_text( row = 2 column = 8 ).
        lo_text->set_text( |{ ls_single_group_781-row_count }| ).

        lo_label = lo_top->create_label( row = 3 column = 1 ).
        lo_label->set_text( 'Session ID:' ).
        lo_text = lo_top->create_text( row = 3 column = 2 ).
        lo_text->set_text( ls_single_group_781-session_id ).

        lo_label = lo_top->create_label( row = 3 column = 4 ).
        lo_label->set_text( 'Executor:' ).
        lo_text = lo_top->create_text( row = 3 column = 5 ).
        lo_text->set_text( ls_single_group_781-executor ).

        lo_label = lo_top->create_label( row = 3 column = 7 ).
        lo_label->set_text( 'Status:' ).
        lo_text = lo_top->create_text( row = 3 column = 8 ).
        lo_text->set_text( ls_single_group_781-lifecycle ).
      ELSE.
 "Level 2: balanced 3-block session context header.
 "Keep only common session facts here. Group-specific TCode/Executor/
 "Lifecycle remain in the Level-2 rows; exact evidence remains Level 3.
        lo_label = lo_top->create_label( row = 1 column = 1 ).
        lo_label->set_text( 'Session Overview' ).

        lo_label = lo_top->create_label( row = 2 column = 1 ).
        lo_label->set_text( 'Session ID:' ).
        lo_text = lo_top->create_text( row = 2 column = 2 ).
        lo_text->set_text( is_session-session_id ).

        lo_label = lo_top->create_label( row = 2 column = 4 ).
        lo_label->set_text( 'Created:' ).
        lo_text = lo_top->create_text( row = 2 column = 5 ).
        lo_text->set_text( is_session-created_on ).

        lo_label = lo_top->create_label( row = 2 column = 7 ).
        lo_label->set_text( 'Created By:' ).
        lo_text = lo_top->create_text( row = 2 column = 8 ).
        lo_text->set_text( is_session-created_by ).

        lo_label = lo_top->create_label( row = 3 column = 1 ).
        lo_label->set_text( 'Source:' ).
        lo_text = lo_top->create_text( row = 3 column = 2 ).
        lo_text->set_text( is_session-source_type ).

        lo_label = lo_top->create_label( row = 3 column = 4 ).
        lo_label->set_text( 'Business Groups:' ).
        lo_text = lo_top->create_text( row = 3 column = 5 ).
        lo_text->set_text( lv_l2_group_scope ).

        lo_label = lo_top->create_label( row = 3 column = 7 ).
        lo_label->set_text( 'Transactions:' ).
        lo_text = lo_top->create_text( row = 3 column = 8 ).
        lo_text->set_text( lv_l2_tcode_scope ).
      ENDIF.

      go_group_grid_0100->set_top_of_list( lo_top ).

      go_group_grid_0100->set_screen_popup(
        start_column = 2
        end_column   = 200
        start_line   = 2
        end_line     = 29 ).

      DATA(lo_evt) = go_group_grid_0100->get_event( ).
      CREATE OBJECT go_group_evt_0100.
      SET HANDLER go_group_evt_0100->on_group_double_click FOR lo_evt.
      SET HANDLER go_group_evt_0100->on_group_link_click FOR lo_evt.

      go_group_grid_0100->display( ).

    CATCH cx_salv_msg INTO DATA(lx_salv).
      MESSAGE lx_salv->get_text( ) TYPE 'S' DISPLAY LIKE 'E'.
  ENDTRY.
ENDFORM.

*& append one row to the final two-column evidence card

FORM add_evidence_card
  USING pv_section TYPE any
        pv_detail  TYPE any.

  DATA: ls_card TYPE ty_evidence_card_0100,
        ls_col  TYPE lvc_s_scol,
        lv_text TYPE string.

  CLEAR ls_card.
  ls_card-section = pv_section.
  ls_card-detail  = pv_detail.
  REFRESH ls_card-cell_colors.

 "visually separate Level-3 sections while keeping the same
 "fact-first SALV data model. No evidence/lifecycle logic is changed.
  IF pv_detail IS INITIAL AND pv_section IS NOT INITIAL.
    CLEAR ls_col.
    ls_col-fname     = 'SECTION'.
    ls_col-color-col = 1.
    ls_col-color-int = 1.
    APPEND ls_col TO ls_card-cell_colors.

    CLEAR ls_col.
    ls_col-fname     = 'DETAIL'.
    ls_col-color-col = 1.
    ls_col-color-int = 1.
    APPEND ls_col TO ls_card-cell_colors.
  ELSEIF pv_section = 'Status'.
    lv_text = pv_detail.
    TRANSLATE lv_text TO UPPER CASE.
    CLEAR ls_col.
    ls_col-fname = 'DETAIL'.
    IF lv_text CS 'SUCCESS'.
      ls_col-color-col = 5.
    ELSEIF lv_text CS 'ERROR'.
      ls_col-color-col = 6.
    ELSEIF lv_text CS 'WARNING'.
      ls_col-color-col = 3.
    ELSE.
      ls_col-color-col = 4.
    ENDIF.
    ls_col-color-int = 1.
    APPEND ls_col TO ls_card-cell_colors.
  ELSEIF pv_section = 'Reader Status' OR pv_section = 'Technical Reader Status' OR pv_section = 'Evidence Status'.
    lv_text = pv_detail.
    TRANSLATE lv_text TO UPPER CASE.
    CLEAR ls_col.
    ls_col-fname = 'DETAIL'.
    IF lv_text CP 'OK*' OR lv_text CP 'VERIFIED*'.
      ls_col-color-col = 5.
    ELSEIF lv_text CS 'FAIL' OR lv_text CS 'ERROR'.
      ls_col-color-col = 6.
    ELSE.
      ls_col-color-col = 3.
    ENDIF.
    ls_col-color-int = 1.
    APPEND ls_col TO ls_card-cell_colors.
  ENDIF.

  APPEND ls_card TO gt_evidence_card_0100.
ENDFORM.

*& Level 3: Execution Evidence Detail matching the mockup
*& The card is fact-first. Unsupported cause/message-class data is explicitly
*& reported as not persisted instead of being guessed.

FORM parse_sm35_binding
  USING    pv_text  TYPE csequence
  CHANGING cv_group TYPE apqi-groupid
           cv_qid   TYPE apqi-qid.

  DATA: lv_text  TYPE string,
        lv_tail  TYPE string,
        lv_token TYPE string,
        lv_dummy TYPE string,
        lv_off   TYPE i.

  CLEAR: cv_group, cv_qid.
  lv_text = pv_text.

  FIND FIRST OCCURRENCE OF 'GROUP=' IN lv_text MATCH OFFSET lv_off.
  IF sy-subrc = 0.
    lv_off = lv_off + 6.
    lv_tail = lv_text+lv_off.
    SPLIT lv_tail AT space INTO lv_token lv_dummy.
    CONDENSE lv_token NO-GAPS.
    IF lv_token IS NOT INITIAL.
      cv_group = lv_token.
    ENDIF.
  ENDIF.

  CLEAR: lv_tail, lv_token, lv_dummy, lv_off.
  FIND FIRST OCCURRENCE OF 'QID=' IN lv_text MATCH OFFSET lv_off.
  IF sy-subrc = 0.
    lv_off = lv_off + 4.
    lv_tail = lv_text+lv_off.
    SPLIT lv_tail AT space INTO lv_token lv_dummy.
    CONDENSE lv_token NO-GAPS.
    IF lv_token IS NOT INITIAL.
      cv_qid = lv_token.
    ENDIF.
  ENDIF.
ENDFORM.

*& Resolve exact SM35 binding and transaction index.
*& The transaction index is derived only from groups carrying the SAME
*& persisted exact QID binding. Ordering reproduces build_engine_keys:
*& SESSION_ID + RECORD_KEY + ROW_INDEX. No session/time guess is used.

FORM resolve_sm35_audit
  USING    is_group TYPE ty_group_0100_disp
           it_res   TYPE ty_t_result_726
  CHANGING cv_group TYPE apqi-groupid
           cv_qid   TYPE apqi-qid
           cv_tidx  TYPE i
           cv_tcnt  TYPE i.

  TYPES: BEGIN OF ty_bind_key_734,
           record_key TYPE zbdc_result_bup-record_key,
           row_index  TYPE zbdc_result_bup-row_index,
         END OF ty_bind_key_734.

  DATA: lt_bind      TYPE ty_t_result_726,
        ls_bind      TYPE zbdc_result_bup,
        lt_keys      TYPE STANDARD TABLE OF ty_bind_key_734,
        ls_key       TYPE ty_bind_key_734,
        lv_group     TYPE apqi-groupid,
        lv_qid       TYPE apqi-qid,
        lv_idx       TYPE i.

  CLEAR: cv_group, cv_qid, cv_tidx, cv_tcnt.

 "Newest exact-group binding wins. Z106 writes one durable SM35_BIND row
 "whenever a real BDC_OPEN_GROUP QID is created for that group.
  LOOP AT it_res INTO ls_bind.
    IF ls_bind-field_name <> 'SM35_BIND' AND
       ls_bind-message NP 'SM35_BIND GROUP=*QID=*'.
      CONTINUE.
    ENDIF.
    CLEAR: lv_group, lv_qid.
    PERFORM parse_sm35_binding
      USING    ls_bind-message
      CHANGING lv_group lv_qid.
    IF lv_qid IS NOT INITIAL.
      cv_group = lv_group.
      cv_qid   = lv_qid.
      EXIT.
    ENDIF.
  ENDLOOP.

  IF cv_qid IS INITIAL.
    RETURN.
  ENDIF.

  SELECT * FROM zbdc_result_bup
    INTO TABLE @lt_bind
    WHERE session_id = @is_group-session_id
      AND field_name = 'SM35_BIND'
    ORDER BY created_at ASCENDING.

  LOOP AT lt_bind INTO ls_bind.
    CLEAR: lv_group, lv_qid.
    PERFORM parse_sm35_binding
      USING    ls_bind-message
      CHANGING lv_group lv_qid.
    IF lv_qid <> cv_qid.
      CONTINUE.
    ENDIF.

    CLEAR ls_key.
    ls_key-record_key = ls_bind-record_key.
    ls_key-row_index  = ls_bind-row_index.
    IF ls_key-record_key IS NOT INITIAL.
      CLEAR ls_key-row_index.
    ENDIF.

    READ TABLE lt_keys TRANSPORTING NO FIELDS
      WITH KEY record_key = ls_key-record_key
               row_index  = ls_key-row_index.
    IF sy-subrc <> 0.
      APPEND ls_key TO lt_keys.
    ENDIF.
  ENDLOOP.

  SORT lt_keys BY record_key row_index.
  cv_tcnt = lines( lt_keys ).

  LOOP AT lt_keys INTO ls_key.
    lv_idx = sy-tabix.
    IF is_group-record_key IS NOT INITIAL.
      IF ls_key-record_key = is_group-record_key.
        cv_tidx = lv_idx.
        EXIT.
      ENDIF.
    ELSEIF ls_key-record_key IS INITIAL AND
           ls_key-row_index = is_group-row_index.
      cv_tidx = lv_idx.
      EXIT.
    ENDIF.
  ENDLOOP.
ENDFORM.

*& Format one exact standard SM35 Analyze Session log row

FORM format_sm35_log_line
  USING    is_log  TYPE bdclm
  CHANGING cv_text TYPE char255.

  DATA: lv_v1      TYPE string,
        lv_v2      TYPE string,
        lv_v3      TYPE string,
        lv_v4      TYPE string,
        lv_ok      TYPE abap_bool,
        lv_fmt     TYPE char255,
        lv_fallback TYPE string.

  CLEAR: cv_text, lv_v1, lv_v2, lv_v3, lv_v4, lv_ok, lv_fmt, lv_fallback.

  PERFORM decode_sm35_mpar
    USING    is_log
    CHANGING lv_v1 lv_v2 lv_v3 lv_v4 lv_ok.
  IF lv_ok <> abap_true.
    lv_v1 = is_log-mpar.
  ENDIF.

  IF is_log-mid IS NOT INITIAL AND is_log-mnr IS NOT INITIAL.
    CALL FUNCTION 'FORMAT_MESSAGE'
      EXPORTING
        id   = is_log-mid
        lang = sy-langu
        no   = is_log-mnr
        v1   = lv_v1
        v2   = lv_v2
        v3   = lv_v3
        v4   = lv_v4
      IMPORTING
        msg  = lv_fmt
      EXCEPTIONS
        OTHERS = 1.
  ENDIF.

  IF lv_fmt IS NOT INITIAL.
    cv_text = lv_fmt.
  ELSE.
    lv_fallback =
      |{ is_log-mid }/{ is_log-mnr } { lv_v1 } { lv_v2 } { lv_v3 } { lv_v4 }|.
    CONDENSE lv_fallback.
    cv_text = lv_fallback.
  ENDIF.
ENDFORM.

*& Live exact-QID BISM evidence fallback

*& Reads the same standard SM35 Analyze Session / TemSe protocol shown by
*& SAP GUI. It is used only when the durable RESULT rows do not yet contain
*& the exact business message. Selection is exact by QID + transaction
*& index; no TCODE-specific message IDs and no newest-session/time guessing.
*& For SUCCESS, the LAST non-controller application S-message of the exact
*& transaction wins (for example the post-SAVE business confirmation). The
*& standard 00/355 "transaction processed successfully" line is only a
*& fallback when no application S-message exists.

FORM resolve_sm35_live_evid
  USING    pv_group     TYPE apqi-groupid
           pv_qid       TYPE apqi-qid
           pv_tidx      TYPE i
           pv_lifecycle TYPE csequence
  CHANGING cv_found     TYPE abap_bool
           cs_log       TYPE bdclm
           cv_text      TYPE char255.

  DATA: lt_log         TYPE ty_t_bdclm,
        ls_log         TYPE bdclm,
        ls_app_s       TYPE bdclm,
        ls_tx_ok       TYPE bdclm,
        ls_terminal    TYPE bdclm,
        ls_diag        TYPE bdclm,
        ls_context     TYPE bdclm,
        ls_app_ctx     TYPE bdclm,
        ls_tx_ctx      TYPE bdclm,
        ls_term_ctx    TYPE bdclm,
        ls_diag_ctx    TYPE bdclm,
        ls_selected_ctx TYPE bdclm,
        lv_have_app_s  TYPE abap_bool,
        lv_have_tx_ok  TYPE abap_bool,
        lv_have_term   TYPE abap_bool,
        lv_have_diag   TYPE abap_bool,
        lv_log_end     TYPE abap_bool,
        lv_idx         TYPE i,
        lv_mode        TYPE c LENGTH 1,
        lv_mode_text   TYPE char50,
        lv_line        TYPE char255,
        lv_upper       TYPE string,
        lv_session_ok  TYPE abap_bool.

  CLEAR: cv_found, cs_log, cv_text, lv_mode, lv_mode_text,
         ls_app_s, ls_tx_ok, ls_terminal, ls_diag,
         ls_context, ls_app_ctx, ls_tx_ctx, ls_term_ctx, ls_diag_ctx,
         ls_selected_ctx,
         lv_have_app_s, lv_have_tx_ok, lv_have_term,
         lv_have_diag, lv_log_end.

  IF pv_group IS INITIAL OR pv_qid IS INITIAL OR pv_tidx <= 0.
    RETURN.
  ENDIF.

 "Evidence display must never block SAP GUI with WAIT loops.
 "When the exact SM35 session is terminal, its Analyze Session log is either
 "readable now or it is not. The normal cockpit/timer reconciliation can
 "pick it up on a later refresh; an evidence click performs one exact read.
  REFRESH lt_log.
  CLEAR lv_session_ok.
  PERFORM get_sm35_session_log
    USING    pv_group pv_qid
    CHANGING lt_log lv_session_ok.

  IF lv_session_ok <> abap_true OR lt_log IS INITIAL.
    RETURN.
  ENDIF.

  CLEAR: lv_mode, lv_mode_text.
  PERFORM detect_sm35_mode_from_log
    USING    lt_log
    CHANGING lv_mode lv_mode_text.

  CLEAR: ls_app_s, ls_tx_ok, ls_terminal, ls_diag,
         ls_context, ls_app_ctx, ls_tx_ctx, ls_term_ctx, ls_diag_ctx,
         ls_selected_ctx,
         lv_have_app_s, lv_have_tx_ok, lv_have_term,
         lv_have_diag, lv_log_end.

  LOOP AT lt_log INTO ls_log.
    IF ls_log-mid = '00' AND ls_log-mnr = '382'.
      lv_log_end = abap_true.
    ENDIF.

    lv_idx = ls_log-tcnt.
    IF lv_idx <> pv_tidx.
      CONTINUE.
    ENDIF.

 "keep the nearest exact dynpro context from this same SM35
 "transaction. Some APQLE message rows carry DYNR but leave MODULE blank;
 "the preceding protocol row still contains the exact program context.
    IF ls_log-module IS NOT INITIAL.
      ls_context-module = ls_log-module.
    ENDIF.
    IF ls_log-dynr IS NOT INITIAL.
      ls_context-dynr = ls_log-dynr.
    ENDIF.

    CASE pv_lifecycle.
      WHEN 'SUCCESS'.
        IF ls_log-mart <> 'S'.
          CONTINUE.
        ENDIF.

        IF ls_log-mid = '00'.
          IF ls_log-mnr = '355'.
            ls_tx_ok = ls_log.
            ls_tx_ctx = ls_context.
            lv_have_tx_ok = abap_true.
          ENDIF.
          CONTINUE.
        ENDIF.

        IF ls_log-mid = 'DC'.
          CONTINUE.
        ENDIF.

 "Last application S-message for the exact transaction wins.
        ls_app_s = ls_log.
        ls_app_ctx = ls_context.
        lv_have_app_s = abap_true.

      WHEN 'ERROR'.
        IF ls_log-mart = 'E' OR
           ls_log-mart = 'A' OR
           ls_log-mart = 'X'.
          ls_terminal = ls_log.
          ls_term_ctx = ls_context.
          lv_have_term = abap_true.
          CONTINUE.
        ENDIF.

        IF lv_mode = 'N'.
          CLEAR: lv_line, lv_upper.
          PERFORM format_sm35_log_line
            USING    ls_log
            CHANGING lv_line.
          lv_upper = lv_line.
          TRANSLATE lv_upper TO UPPER CASE.
          IF ( ls_log-mid = 'DC' AND
               ( ls_log-mnr = '001' OR ls_log-mnr = '006' ) ) OR
             lv_upper CS 'CONTROL FRAMEWORK' OR
             lv_upper CS 'GUI CANNOT BE REACHED' OR
             lv_upper CS 'FATAL ERROR' OR
             lv_upper CS 'RAISE_EXCEPTION'.
            ls_diag = ls_log.
            ls_diag_ctx = ls_context.
            lv_have_diag = abap_true.
          ENDIF.
        ENDIF.

      WHEN 'WARNING'.
        IF ls_log-mart = 'W'.
          ls_terminal = ls_log.
          ls_term_ctx = ls_context.
          lv_have_term = abap_true.
        ENDIF.

      WHEN OTHERS.
        CONTINUE.
    ENDCASE.
  ENDLOOP.

  IF pv_lifecycle = 'SUCCESS'.
    IF lv_have_app_s = abap_true.
      cs_log = ls_app_s.
      ls_selected_ctx = ls_app_ctx.
    ELSEIF lv_have_tx_ok = abap_true.
      cs_log = ls_tx_ok.
      ls_selected_ctx = ls_tx_ctx.
    ELSE.
      RETURN.
    ENDIF.
  ELSEIF pv_lifecycle = 'ERROR'.
    IF lv_have_term = abap_true.
      cs_log = ls_terminal.
      ls_selected_ctx = ls_term_ctx.
    ELSEIF lv_have_diag = abap_true.
      cs_log = ls_diag.
      ls_selected_ctx = ls_diag_ctx.
    ELSE.
      RETURN.
    ENDIF.
  ELSEIF pv_lifecycle = 'WARNING' AND lv_have_term = abap_true.
    cs_log = ls_terminal.
    ls_selected_ctx = ls_term_ctx.
  ELSE.
    RETURN.
  ENDIF.

 "Fill only missing display context from the exact same transaction and
 "protocol position; never invent a program or screen name.
  IF cs_log-module IS INITIAL AND ls_selected_ctx-module IS NOT INITIAL.
    cs_log-module = ls_selected_ctx-module.
  ENDIF.
  IF cs_log-dynr IS INITIAL AND ls_selected_ctx-dynr IS NOT INITIAL.
    cs_log-dynr = ls_selected_ctx-dynr.
  ENDIF.

  PERFORM format_sm35_log_line
    USING    cs_log
    CHANGING cv_text.
  IF cv_text IS INITIAL.
    RETURN.
  ENDIF.

  cv_found = abap_true.
ENDFORM.

FORM get_sm35_mode
  USING    pv_group TYPE apqi-groupid
           pv_qid   TYPE apqi-qid
  CHANGING cv_mode  TYPE c
           cv_label TYPE char50.

  DATA: lt_log TYPE ty_t_bdclm,
        lv_ok  TYPE abap_bool.

  CLEAR: cv_mode, cv_label, lv_ok.
  IF pv_group IS INITIAL OR pv_qid IS INITIAL.
    cv_label = 'Not available - exact Session Name / QID is missing'.
    RETURN.
  ENDIF.

  PERFORM get_sm35_session_log
    USING    pv_group pv_qid
    CHANGING lt_log lv_ok.
  IF lv_ok <> abap_true OR lt_log IS INITIAL.
    cv_label = 'Not available - exact SM35 session log is not readable'.
    RETURN.
  ENDIF.

  PERFORM detect_sm35_mode_from_log
    USING    lt_log
    CHANGING cv_mode cv_label.
ENDFORM.

*& Level 3: evidence-first audit detail.
*& Exact SAP Message is populated ONLY from an exact persisted raw result
*& row for the selected Session + Group + current attempt. The Level-2
*& friendly summary (for example "SM35 processing failed") is never promoted
*& into exact evidence. Unsupported metadata is shown as Not persisted.

*& User-facing duration for Level 3.
*& Uses only Level-2 persisted start/finish timestamps (YYYY-MM-DD HH:MM:SS).
*& No runtime guessing: malformed/missing timestamps return '-'.

FORM level3_duration
  USING    pv_start TYPE csequence
           pv_end   TYPE csequence
  CHANGING cv_text  TYPE char30.

  DATA: lv_start_date TYPE sy-datum,
        lv_end_date   TYPE sy-datum,
        lv_days       TYPE i,
        lv_h1         TYPE i,
        lv_m1         TYPE i,
        lv_s1         TYPE i,
        lv_h2         TYPE i,
        lv_m2         TYPE i,
        lv_s2         TYPE i,
        lv_total      TYPE i,
        lv_total_c    TYPE char20.

  CLEAR: cv_text, lv_start_date, lv_end_date, lv_days,
         lv_h1, lv_m1, lv_s1, lv_h2, lv_m2, lv_s2, lv_total, lv_total_c.

  IF pv_start IS INITIAL OR pv_end IS INITIAL OR
     pv_start = '-' OR pv_end = '-'.
    cv_text = '-'.
    RETURN.
  ENDIF.

  IF strlen( pv_start ) < 19 OR strlen( pv_end ) < 19.
    cv_text = '-'.
    RETURN.
  ENDIF.

  IF pv_start+4(1) <> '-' OR pv_start+7(1) <> '-' OR
     pv_start+10(1) <> space OR pv_start+13(1) <> ':' OR pv_start+16(1) <> ':' OR
     pv_end+4(1) <> '-' OR pv_end+7(1) <> '-' OR
     pv_end+10(1) <> space OR pv_end+13(1) <> ':' OR pv_end+16(1) <> ':'.
    cv_text = '-'.
    RETURN.
  ENDIF.

  CONCATENATE pv_start+0(4) pv_start+5(2) pv_start+8(2)
         INTO lv_start_date.
  CONCATENATE pv_end+0(4) pv_end+5(2) pv_end+8(2)
         INTO lv_end_date.

  lv_h1 = pv_start+11(2).
  lv_m1 = pv_start+14(2).
  lv_s1 = pv_start+17(2).
  lv_h2 = pv_end+11(2).
  lv_m2 = pv_end+14(2).
  lv_s2 = pv_end+17(2).

  lv_days  = lv_end_date - lv_start_date.
  lv_total = ( lv_days * 86400 ) +
             ( lv_h2 * 3600 ) + ( lv_m2 * 60 ) + lv_s2 -
             ( lv_h1 * 3600 ) - ( lv_m1 * 60 ) - lv_s1.

  IF lv_total < 0.
    cv_text = '-'.
    RETURN.
  ENDIF.

  WRITE lv_total TO lv_total_c LEFT-JUSTIFIED.
  CONDENSE lv_total_c NO-GAPS.
  IF lv_total = 1.
    CONCATENATE lv_total_c 'second' INTO cv_text SEPARATED BY space.
  ELSE.
    CONCATENATE lv_total_c 'seconds' INTO cv_text SEPARATED BY space.
  ENDIF.
ENDFORM.

FORM show_group_evidence
  USING is_group TYPE ty_group_0100_disp.

  DATA: lt_res          TYPE ty_t_result_726,
        ls_res          TYPE zbdc_result_bup,
        ls_exact        TYPE zbdc_result_bup,
        ls_tx_fallback  TYPE zbdc_result_bup,
        ls_proto        TYPE zbdc_result_bup,
        ls_live         TYPE bdclm,
        lv_title        TYPE lvc_title,
        lv_status       TYPE char255,
        lv_group        TYPE char255,
        lv_exact        TYPE char255,
        lv_protocol     TYPE char255,
        lv_msg_ident    TYPE char255,
        lv_msg_type     TYPE char255,
        lv_dyn_field    TYPE char255,
        lv_binding      TYPE char255,
        lv_tidx_text    TYPE char255,
        lv_attempt_text TYPE char255,
        lv_retry_history TYPE char255,
        lv_time_text    TYPE char19,
        lv_source       TYPE char255,
        lv_status_user  TYPE char255,
        lv_result_summary TYPE char255,
        lv_what_happened TYPE char255,
        lv_user_meaning TYPE char255,
        lv_msg_type_raw TYPE char20,
        lv_why_matters  TYPE char255,
        lv_next_step    TYPE char255,
        lv_audit_note   TYPE char255,
        lv_run_duration TYPE char30,
        lv_evidence_status TYPE char80,
        lv_group_size_text TYPE char40,
        lv_bdc_mode_782 TYPE c LENGTH 1,
        lv_update_mode_782 TYPE c LENGTH 1,
        lv_batch_size_782 TYPE i,
        lv_policy_ok_782 TYPE abap_bool,
        lv_policy_msg_782 TYPE string,
        lv_bdc_mode_text_782 TYPE char40,
        lv_update_mode_text_782 TYPE char40,
        lv_row_count_text_782 TYPE char20,
        lv_popup_end    TYPE i,
        lv_rows         TYPE i,
        lv_current_att  TYPE i,
        lv_mid          TYPE char40,
        lv_mnr          TYPE char20,
        lv_sm35_group   TYPE apqi-groupid,
        lv_sm35_qid     TYPE apqi-qid,
        lv_sm35_mode    TYPE c LENGTH 1,
        lv_sm35_mode_txt TYPE char50,
        lv_reader_diag    TYPE char255,
        lv_tidx         TYPE i,
        lv_tcnt         TYPE i,
        lv_tidx_c       TYPE char20,
        lv_tcnt_c       TYPE char20,
        lv_exact_found  TYPE abap_bool,
        lv_tx_fallback_found TYPE abap_bool,
        lv_live_found   TYPE abap_bool,
        lv_proto_found  TYPE abap_bool,
        lv_exact_source TYPE char255,
        lv_sap_message_785 TYPE char255,
        lv_technical_result_785 TYPE char80,
        lv_subrc_text_785 TYPE char20,
        lv_subrc_marker_785 TYPE char20 VALUE 'SY-SUBRC=',
        lv_subrc_off_785 TYPE i,
        lv_subrc_start_785 TYPE i,
        lv_colon_off_785 TYPE i,
        lv_subrc_len_785 TYPE i,
        lv_msg_start_785 TYPE i.

  FIELD-SYMBOLS: <lv_mid> TYPE any,
                 <lv_mnr> TYPE any.

  REFRESH: gt_evidence_0100, gt_evidence_card_0100.
  FREE go_evidence_grid_0100.

  IF is_group-record_key IS NOT INITIAL.
    SELECT * FROM zbdc_result_bup
      INTO TABLE @lt_res
      WHERE session_id = @is_group-session_id
        AND record_key = @is_group-record_key
      ORDER BY created_at DESCENDING.
  ELSE.
    SELECT * FROM zbdc_result_bup
      INTO TABLE @lt_res
      WHERE session_id = @is_group-session_id
        AND row_index  = @is_group-row_index
      ORDER BY created_at DESCENDING.
  ENDIF.

 "save_sm35_line assigns STEP in exact SAP protocol order.
 "Several APQLE lines are persisted within the same timestamp second, so
 "CREATED_AT alone is not a deterministic ordering key. Screen 0500 already
 "uses STEP DESCENDING; Level-3 Dashboard must use the same authority so the
 "last application S-message (post-SAVE) outranks earlier screen guidance.
  SORT lt_res BY created_at DESCENDING step DESCENDING.

  lv_rows = lines( lt_res ).
  lv_current_att = is_group-attempt.
  IF lv_current_att <= 0.
    LOOP AT lt_res INTO ls_res.
      IF ls_res-attempt_no > lv_current_att.
        lv_current_att = ls_res-attempt_no.
      ENDIF.
    ENDLOOP.
  ENDIF.

 "Select the exact message from persisted raw execution evidence only.
 "For BISM prefer FIELD_NAME=SM35 protocol lines and exclude binding/admin
 "summaries. For success prefer application S before transaction/admin S.
  CASE is_group-lifecycle.
    WHEN 'ERROR'.
      LOOP AT lt_res INTO ls_res.
        IF lv_current_att > 0 AND ls_res-attempt_no > 0 AND
           ls_res-attempt_no <> lv_current_att.
          CONTINUE.
        ENDIF.
        IF ls_res-message IS INITIAL OR ls_res-field_name = 'SM35_BIND'.
          CONTINUE.
        ENDIF.
        IF is_group-executor = 'BISM' AND ls_res-field_name <> 'SM35'.
          CONTINUE.
        ENDIF.
        IF ls_res-msg_type = 'E' OR ls_res-msg_type = 'A' OR
           ls_res-msg_type = 'X' OR
           ( is_group-executor = 'BISM' AND
             ls_res-exec_status = 'SM35_BG_FATAL' ).
          ls_exact = ls_res.
          lv_exact_found = abap_true.
          EXIT.
        ENDIF.
      ENDLOOP.

    WHEN 'WARNING'.
      LOOP AT lt_res INTO ls_res.
        IF lv_current_att > 0 AND ls_res-attempt_no > 0 AND
           ls_res-attempt_no <> lv_current_att.
          CONTINUE.
        ENDIF.
        IF ls_res-message IS INITIAL OR ls_res-field_name = 'SM35_BIND'.
          CONTINUE.
        ENDIF.
        IF is_group-executor = 'BISM' AND ls_res-field_name <> 'SM35'.
          CONTINUE.
        ENDIF.
        IF ls_res-msg_type = 'W'.
          ls_exact = ls_res.
          lv_exact_found = abap_true.
          EXIT.
        ENDIF.
      ENDLOOP.

    WHEN 'SUCCESS'.
      IF is_group-executor = 'BISM'.
        LOOP AT lt_res INTO ls_res.
          IF lv_current_att > 0 AND ls_res-attempt_no > 0 AND
             ls_res-attempt_no <> lv_current_att.
            CONTINUE.
          ENDIF.
          IF ls_res-message IS INITIAL OR ls_res-field_name <> 'SM35'.
            CONTINUE.
          ENDIF.
          IF ls_res-exec_status = 'SM35_APP_S'.
            ls_exact = ls_res.
            lv_exact_found = abap_true.
            EXIT.
          ENDIF.
        ENDLOOP.
        IF lv_exact_found <> abap_true.
          LOOP AT lt_res INTO ls_res.
            IF lv_current_att > 0 AND ls_res-attempt_no > 0 AND
               ls_res-attempt_no <> lv_current_att.
              CONTINUE.
            ENDIF.
            IF ls_res-message IS INITIAL OR ls_res-field_name <> 'SM35'.
              CONTINUE.
            ENDIF.
            IF ls_res-exec_status = 'SM35_TX_OK'.
 "keep controller transaction success only as a fallback.
 "Before promoting it to Exact SAP Message, query the standard
 "Analyze Session log for a later application business S-message.
              ls_tx_fallback = ls_res.
              lv_tx_fallback_found = abap_true.
              EXIT.
            ENDIF.
          ENDLOOP.
        ENDIF.
      ELSE.
        LOOP AT lt_res INTO ls_res.
          IF lv_current_att > 0 AND ls_res-attempt_no > 0 AND
             ls_res-attempt_no <> lv_current_att.
            CONTINUE.
          ENDIF.
          IF ls_res-message IS INITIAL OR ls_res-field_name = 'SM35_BIND'.
            CONTINUE.
          ENDIF.
          IF ls_res-msg_type = 'S'.
            ls_exact = ls_res.
            lv_exact_found = abap_true.
            EXIT.
          ENDIF.
        ENDLOOP.
      ENDIF.

    WHEN OTHERS.
      CLEAR lv_exact_found.
  ENDCASE.

 "resolve the exact SM35 queue identity before finalizing Level 3.
 "If durable RESULT rows do not yet contain the application message, read
 "the standard Analyze Session protocol by exact QID + transaction index.
  PERFORM resolve_sm35_audit
    USING    is_group lt_res
    CHANGING lv_sm35_group lv_sm35_qid lv_tidx lv_tcnt.

  CLEAR: lv_sm35_mode, lv_sm35_mode_txt.
  IF is_group-executor = 'BISM' AND lv_sm35_qid IS NOT INITIAL.
    PERFORM get_sm35_mode
      USING    lv_sm35_group lv_sm35_qid
      CHANGING lv_sm35_mode lv_sm35_mode_txt.
  ENDIF.

 "for BISM, always attempt one exact live Analyze Session read when
 "the persisted Session Name/QID + transaction index are available. The
 "persisted RESULT text remains a fallback, but the live APQLE/TemSe row is
 "the authoritative source for MSGID/MSGNR/MART/MODULE/DYNR metadata.
 "This is evidence enrichment only; no execution/retry lifecycle is changed.
  CLEAR: lv_live_found, ls_live.
  IF is_group-executor = 'BISM' AND
     lv_sm35_qid IS NOT INITIAL AND lv_tidx > 0.
    PERFORM resolve_sm35_live_evid
      USING    lv_sm35_group lv_sm35_qid lv_tidx is_group-lifecycle
      CHANGING lv_live_found ls_live lv_exact.
    IF lv_live_found = abap_true.
      lv_exact_found = abap_true.
      IF lv_sm35_mode IS NOT INITIAL.
        lv_exact_source =
          |SM35 Analyze Session Log - mode { lv_sm35_mode } - exact Session Name + QID + transaction index|.
      ELSE.
        lv_exact_source =
          'SM35 Analyze Session Log - exact Session Name + QID + transaction index'.
      ENDIF.
    ENDIF.
  ENDIF.

 "Only after the live application-message lookup may the standard 00/355
 "transaction-success line become the exact fallback.
  IF lv_exact_found <> abap_true AND lv_tx_fallback_found = abap_true.
    ls_exact = ls_tx_fallback.
    lv_exact_found = abap_true.
  ENDIF.

  IF lv_exact_found = abap_true AND lv_live_found <> abap_true.
    lv_exact = ls_exact-message.
    IF is_group-record_key IS NOT INITIAL.
      lv_exact_source = 'ZBDC_RESULT_BUP - exact SESSION_ID + RECORD_KEY'.
    ELSE.
      lv_exact_source = 'ZBDC_RESULT_BUP - exact SESSION_ID + ROW_INDEX fallback'.
    ENDIF.
  ELSEIF lv_exact_found <> abap_true.
    lv_exact = 'Not available from persisted or exact SAP runtime evidence.'.
  ENDIF.

 "Runtime protocol is a separate persisted technical line when available.
 "For BISM prefer a Control Framework/diagnostic line; otherwise use the
 "selected raw exact line. Never use the Level-2 SAP Result summary.
  IF lv_live_found = abap_true.
    lv_protocol = lv_exact.
    lv_proto_found = abap_true.
  ENDIF.

  IF is_group-executor = 'BISM' AND lv_proto_found <> abap_true.
    LOOP AT lt_res INTO ls_res.
      IF lv_current_att > 0 AND ls_res-attempt_no > 0 AND
         ls_res-attempt_no <> lv_current_att.
        CONTINUE.
      ENDIF.
      IF ls_res-message IS INITIAL OR ls_res-field_name <> 'SM35'.
        CONTINUE.
      ENDIF.
      IF ls_res-exec_status = 'SM35_DIAG' OR
         ls_res-exec_status = 'SM35_BG_FATAL' OR
         ls_res-message CS 'Control Framework' OR
         ls_res-message CS 'GUI cannot be reached'.
        ls_proto = ls_res.
        lv_proto_found = abap_true.
        EXIT.
      ENDIF.
    ENDLOOP.
  ENDIF.

  IF lv_proto_found <> abap_true AND lv_exact_found = abap_true.
    ls_proto = ls_exact.
    lv_proto_found = abap_true.
  ENDIF.

  IF lv_proto_found = abap_true.
 "live Analyze Session evidence already populated LV_PROTOCOL.
 "Do not overwrite it with an initial persisted LS_PROTO structure.
    IF lv_live_found <> abap_true.
      lv_protocol = ls_proto-message.
    ENDIF.
  ELSE.
    lv_protocol = 'No separate runtime protocol row was persisted.'.
  ENDIF.

 "Message identity belongs to the exact selected raw row only.
  CLEAR: lv_mid, lv_mnr, lv_msg_ident.
  IF lv_live_found = abap_true.
    lv_mid = ls_live-mid.
    lv_mnr = ls_live-mnr.
  ELSEIF lv_exact_found = abap_true.
    ASSIGN COMPONENT 'MSG_ID' OF STRUCTURE ls_exact TO <lv_mid>.
    IF sy-subrc <> 0.
      ASSIGN COMPONENT 'MSGID' OF STRUCTURE ls_exact TO <lv_mid>.
    ENDIF.
    IF sy-subrc = 0 AND <lv_mid> IS ASSIGNED.
      lv_mid = <lv_mid>.
    ENDIF.

    ASSIGN COMPONENT 'MSG_NUMBER' OF STRUCTURE ls_exact TO <lv_mnr>.
    IF sy-subrc <> 0.
      ASSIGN COMPONENT 'MSGNR' OF STRUCTURE ls_exact TO <lv_mnr>.
    ENDIF.
    IF sy-subrc <> 0.
      ASSIGN COMPONENT 'MSG_NO' OF STRUCTURE ls_exact TO <lv_mnr>.
    ENDIF.
    IF sy-subrc = 0 AND <lv_mnr> IS ASSIGNED.
      lv_mnr = <lv_mnr>.
    ENDIF.
  ENDIF.

  IF lv_mid IS NOT INITIAL OR lv_mnr IS NOT INITIAL.
    CONCATENATE lv_mid lv_mnr INTO lv_msg_ident SEPARATED BY space.
    CONDENSE lv_msg_ident.
  ELSE.
    lv_msg_ident = '-'.
  ENDIF.

  IF lv_live_found = abap_true.
    lv_msg_type = ls_live-mart.
    IF ls_live-module IS NOT INITIAL OR ls_live-dynr IS NOT INITIAL.
      CONCATENATE ls_live-module ls_live-dynr
             INTO lv_dyn_field SEPARATED BY space.
      CONDENSE lv_dyn_field.
    ELSE.
      lv_dyn_field = 'Not available in the exact SM35 log row.'.
    ENDIF.
  ELSEIF lv_exact_found = abap_true.
    lv_msg_type = ls_exact-msg_type.
    IF lv_msg_type IS INITIAL.
      lv_msg_type = 'Not persisted.'.
    ENDIF.
    IF ls_exact-dynpro IS NOT INITIAL OR ls_exact-field_name IS NOT INITIAL.
      CONCATENATE ls_exact-dynpro ls_exact-field_name
             INTO lv_dyn_field SEPARATED BY space.
      CONDENSE lv_dyn_field.
    ELSE.
      lv_dyn_field = 'Not persisted.'.
    ENDIF.
  ELSE.
    lv_msg_type  = 'Not available.'.
    lv_dyn_field = 'Not available.'.
  ENDIF.

  IF is_group-executor = 'BISM'.
    IF lv_sm35_qid IS NOT INITIAL.
      CONCATENATE lv_sm35_group '/' lv_sm35_qid
             INTO lv_binding SEPARATED BY space.
    ELSE.
      lv_binding = 'Exact SM35 binding was not persisted for this group.'.
    ENDIF.

    IF lv_tidx > 0 AND lv_tcnt > 0.
      WRITE lv_tidx TO lv_tidx_c.
      WRITE lv_tcnt TO lv_tcnt_c.
      CONDENSE: lv_tidx_c NO-GAPS, lv_tcnt_c NO-GAPS.
      CONCATENATE lv_tidx_c 'of' lv_tcnt_c
             INTO lv_tidx_text SEPARATED BY space.
    ELSE.
      lv_tidx_text = 'Not persisted or safely derivable for this execution.'.
    ENDIF.
  ELSE.
    lv_binding   = 'Not applicable - CALL TRANSACTION executor.'.
    lv_tidx_text = 'Not applicable - CALL TRANSACTION executor.'.
  ENDIF.

  IF lv_current_att > 0.
    WRITE lv_current_att TO lv_attempt_text.
    CONDENSE lv_attempt_text NO-GAPS.
  ELSE.
    lv_attempt_text = 'Not persisted.'.
  ENDIF.

  CLEAR lv_time_text.
 "every user-facing wall-clock value must come from a canonical
 "timestamp rendered through the Vietnam UTC+7 helper. Raw SM35 INDATE/
 "INTIME carry SAP-system-zone semantics, so they are never displayed as a
 "fallback. If no canonical timestamp exists, show Not persisted below.
  IF lv_exact_found = abap_true AND ls_exact-created_at IS NOT INITIAL.
    PERFORM format_result_time
      USING    ls_exact-created_at
      CHANGING lv_time_text.
  ELSEIF lv_proto_found = abap_true AND ls_proto-created_at IS NOT INITIAL.
    PERFORM format_result_time
      USING    ls_proto-created_at
      CHANGING lv_time_text.
  ENDIF.
  IF lv_time_text IS INITIAL.
    lv_time_text = 'Not persisted.'.
  ENDIF.

  lv_status = is_group-lifecycle.
  IF lv_status IS INITIAL.
    lv_status = 'UNKNOWN'.
  ENDIF.

  lv_group = is_group-group_key.
  IF is_group-tcode IS NOT INITIAL.
    CONCATENATE lv_group '(' is_group-tcode ')'
           INTO lv_group SEPARATED BY space.
  ENDIF.

  IF lv_exact_source IS NOT INITIAL.
    IF lv_exact_source CP 'SM35 Analyze Session Log*'.
      lv_source = 'SM35 Session Log'.
    ELSE.
      lv_source = 'Execution Result Log'.
    ENDIF.
  ELSEIF is_group-executor = 'BISM' AND
         lv_sm35_qid IS NOT INITIAL AND
         lv_exact_found <> abap_true.
    lv_source = 'SM35 Session Log'.
  ELSE.
    lv_source = 'Execution Result Log'.
  ENDIF.

 "concise Level-3 wording. Exact SAP evidence remains unchanged;
 "only presentation text is simplified for the user.
  CLEAR: lv_status_user, lv_result_summary, lv_what_happened, lv_user_meaning,
         lv_why_matters, lv_next_step, lv_audit_note.
  CASE is_group-lifecycle.
    WHEN 'SUCCESS'.
      lv_status_user    = 'SUCCESS - Completed successfully'.
      lv_result_summary = 'SAP completed this business group successfully.'.
      lv_why_matters    = 'This is the final SAP confirmation for this group.'.
      lv_next_step      = 'None required.'.
      lv_audit_note     = 'Keep this evidence for review or audit when needed.'.
    WHEN 'WARNING'.
      lv_status_user    = 'WARNING - Review required'.
      lv_result_summary = 'SAP completed this business group with a warning.'.
      lv_why_matters    = 'This is the final SAP warning for this group.'.
      lv_next_step      = 'Review the warning and the entered data before deciding the next step.'.
      lv_audit_note     = 'Do not retry automatically until the warning is reviewed.'.
    WHEN 'ERROR'.
      lv_status_user    = 'ERROR - Execution failed'.
      lv_result_summary = 'SAP returned a terminal execution error for this business group.'.
      lv_why_matters    = 'This is the final SAP error for this group.'.
      lv_next_step      = 'Review the SAP error, correct this group, then use controlled retry if eligible.'.
      lv_audit_note     = 'Retry only the failed group after correction.'.
    WHEN 'READY'.
      lv_status_user    = 'READY - Not executed yet'.
      lv_result_summary = 'This business group has not been executed yet.'.
      lv_why_matters    = 'Terminal SAP evidence will appear after execution.'.
      lv_next_step      = 'Run this group when it is ready for execution.'.
      lv_audit_note     = '-'.
    WHEN OTHERS.
      CONCATENATE lv_status '- Execution in progress or nonterminal'
             INTO lv_status_user SEPARATED BY space.
      lv_result_summary = 'This business group has not reached a final SAP result yet.'.
      lv_why_matters    = 'Terminal SAP evidence appears only after a final result.'.
      lv_next_step      = 'Continue monitoring until the group reaches SUCCESS, WARNING, or ERROR.'.
      lv_audit_note     = '-'.
  ENDCASE.

 "Friendly message-type label while preserving the exact SAP code.
  lv_msg_type_raw = lv_msg_type.
  CONDENSE lv_msg_type_raw NO-GAPS.
  CASE lv_msg_type_raw.
    WHEN 'S'. lv_msg_type = 'Success (S)'.
    WHEN 'W'. lv_msg_type = 'Warning (W)'.
    WHEN 'E'. lv_msg_type = 'Error (E)'.
    WHEN 'A'. lv_msg_type = 'Abort (A)'.
    WHEN 'X'. lv_msg_type = 'Exit (X)'.
    WHEN 'I'. lv_msg_type = 'Information (I)'.
    WHEN OTHERS.
      IF lv_msg_type IS INITIAL OR lv_msg_type = 'Not persisted.'.
        lv_msg_type = '-'.
      ENDIF.
  ENDCASE.

 "SAP location is presented in user language, but only from exact
 "evidence already present. Do not guess a program when SM35 persisted only
 "the screen number.
  IF lv_dyn_field IS INITIAL OR
     lv_dyn_field = 'Not persisted.' OR
     lv_dyn_field = 'Not available.'.
    lv_dyn_field = '-'.
  ELSEIF lv_live_found = abap_true.
    IF ls_live-module IS NOT INITIAL AND ls_live-dynr IS NOT INITIAL.
      CONCATENATE 'Program' ls_live-module '/ Screen' ls_live-dynr
             INTO lv_dyn_field SEPARATED BY space.
    ELSEIF ls_live-module IS NOT INITIAL.
      CONCATENATE 'Program' ls_live-module
             INTO lv_dyn_field SEPARATED BY space.
    ELSEIF ls_live-dynr IS NOT INITIAL.
      CONCATENATE 'Screen' ls_live-dynr
             INTO lv_dyn_field SEPARATED BY space.
    ELSE.
      lv_dyn_field = '-'.
    ENDIF.
  ELSEIF lv_exact_found = abap_true.
    IF ls_exact-dynpro IS NOT INITIAL AND ls_exact-field_name IS NOT INITIAL.
      CONCATENATE 'Screen' ls_exact-dynpro '/ Field' ls_exact-field_name
             INTO lv_dyn_field SEPARATED BY space.
    ELSEIF ls_exact-dynpro IS NOT INITIAL.
      CONCATENATE 'Screen' ls_exact-dynpro
             INTO lv_dyn_field SEPARATED BY space.
    ELSEIF ls_exact-field_name IS NOT INITIAL.
      CONCATENATE 'Field' ls_exact-field_name
             INTO lv_dyn_field SEPARATED BY space.
    ELSE.
      lv_dyn_field = '-'.
    ENDIF.
  ENDIF.

  IF lv_time_text IS INITIAL OR lv_time_text = 'Not persisted.'.
    lv_time_text = '-'.
  ENDIF.

  CLEAR lv_reader_diag.
  IF is_group-executor = 'BISM' AND lv_sm35_qid IS NOT INITIAL.
    PERFORM sm35_reader_diag
      USING    lv_sm35_group lv_sm35_qid
      CHANGING lv_reader_diag.
  ENDIF.

 "/keep Level 3 focused on information that changes a user's decision.
 "Attempt 1 is noise; only show an execution attempt after an actual retry.
 "Row count already belongs to Level 2, so do not repeat it in Level 3.
 "SUCCESS needs no duplicate result summary or empty action section.
  CLEAR: lv_run_duration, lv_evidence_status.

  PERFORM level3_duration
    USING    is_group-started_at is_group-finished_at
    CHANGING lv_run_duration.

  IF lv_live_found = abap_true OR lv_exact_found = abap_true.
    lv_evidence_status = 'Verified - Matched to this group'.
  ELSEIF is_group-lifecycle = 'READY'.
    lv_evidence_status = 'Not available - Group not executed yet'.
  ELSE.
    lv_evidence_status = 'Not verified yet'.
  ENDIF.

 "add user-facing execution context without exposing internal keys.
 "Group Size is the exact canonical row count already used by Level 2.
 "BDC/Update Mode are shown only for CALL TRANSACTION groups; BISM keeps
 "its proven SM35 Processing Mode because CTU display/update settings do
 "not describe standard SM35 processing.
  CLEAR: lv_group_size_text, lv_row_count_text_782,
         lv_bdc_mode_782, lv_update_mode_782, lv_batch_size_782,
         lv_policy_ok_782, lv_policy_msg_782,
         lv_bdc_mode_text_782, lv_update_mode_text_782.

  WRITE is_group-row_count TO lv_row_count_text_782 LEFT-JUSTIFIED.
  CONDENSE lv_row_count_text_782 NO-GAPS.
  IF is_group-row_count = 1.
    CONCATENATE lv_row_count_text_782 'input row'
           INTO lv_group_size_text SEPARATED BY space.
  ELSE.
    CONCATENATE lv_row_count_text_782 'input rows'
           INTO lv_group_size_text SEPARATED BY space.
  ENDIF.

 "keep the SAP business message readable for CT errors without
 "discarding the exact engine evidence. The CT executor persists a generic
 "wrapper in the form "CALL TRANSACTION failed, SY-SUBRC=n: <SAP text>".
 "For Level 3 presentation only, split that proven wrapper into three short
 "rows. No TCode/field/business meaning is inferred and persisted evidence
 "is not changed. If the proven wrapper cannot be parsed safely, keep the
 "original exact text unchanged.
  CLEAR: lv_sap_message_785, lv_technical_result_785, lv_subrc_text_785,
         lv_subrc_off_785, lv_subrc_start_785, lv_colon_off_785,
         lv_subrc_len_785, lv_msg_start_785.
  lv_sap_message_785 = lv_exact.

  IF is_group-lifecycle = 'ERROR' AND is_group-executor = 'CT' AND
     lv_exact CP 'CALL TRANSACTION failed, SY-SUBRC=*'.
    FIND FIRST OCCURRENCE OF lv_subrc_marker_785 IN lv_exact
      MATCH OFFSET lv_subrc_off_785.
    FIND FIRST OCCURRENCE OF ':' IN lv_exact
      MATCH OFFSET lv_colon_off_785.

    IF sy-subrc = 0 AND lv_subrc_off_785 >= 0 AND lv_colon_off_785 > 0.
      lv_subrc_start_785 = lv_subrc_off_785 + strlen( lv_subrc_marker_785 ).
      IF lv_colon_off_785 > lv_subrc_start_785.
        lv_subrc_len_785 = lv_colon_off_785 - lv_subrc_start_785.
        lv_subrc_text_785 = lv_exact+lv_subrc_start_785(lv_subrc_len_785).
        CONDENSE lv_subrc_text_785 NO-GAPS.

        lv_msg_start_785 = lv_colon_off_785 + 1.
        IF lv_msg_start_785 < strlen( lv_exact ).
          lv_sap_message_785 = lv_exact+lv_msg_start_785.
          SHIFT lv_sap_message_785 LEFT DELETING LEADING space.
          IF lv_sap_message_785 IS NOT INITIAL.
            lv_technical_result_785 = 'CALL TRANSACTION failed'.
          ELSE.
            lv_sap_message_785 = lv_exact.
            CLEAR: lv_technical_result_785, lv_subrc_text_785.
          ENDIF.
        ENDIF.
      ENDIF.
    ENDIF.
  ENDIF.

  IF is_group-executor = 'CT'.
    PERFORM get_ctu_policy
      CHANGING lv_bdc_mode_782 lv_update_mode_782 lv_batch_size_782
               lv_policy_ok_782 lv_policy_msg_782.
    IF lv_policy_ok_782 = abap_true.
      CASE lv_bdc_mode_782.
        WHEN 'A'. lv_bdc_mode_text_782 = 'A - All screens'.
        WHEN 'E'. lv_bdc_mode_text_782 = 'E - Errors only'.
        WHEN 'N'. lv_bdc_mode_text_782 = 'N - No display'.
        WHEN OTHERS. lv_bdc_mode_text_782 = '-'.
      ENDCASE.
      CASE lv_update_mode_782.
        WHEN 'S'. lv_update_mode_text_782 = 'S - Synchronous'.
        WHEN 'A'. lv_update_mode_text_782 = 'A - Asynchronous'.
        WHEN OTHERS. lv_update_mode_text_782 = '-'.
      ENDCASE.
    ELSE.
      lv_bdc_mode_text_782 = '-'.
      lv_update_mode_text_782 = '-'.
    ENDIF.
  ENDIF.

 "1. OUTCOME - concise execution identity and final state.
  PERFORM add_evidence_card USING '1. OUTCOME'                ''.
  PERFORM add_evidence_card USING 'Status'                    lv_status_user.
  PERFORM add_evidence_card USING 'Business Group'            lv_group.
  PERFORM add_evidence_card USING 'Executor'                  is_group-executor.
  PERFORM add_evidence_card USING 'Group Size'                lv_group_size_text.
  IF lv_current_att > 1.
    CLEAR lv_retry_history.
    CONCATENATE 'Retried - attempt' lv_attempt_text
           INTO lv_retry_history SEPARATED BY space.
    PERFORM add_evidence_card USING 'Retry History'            lv_retry_history.
  ENDIF.

 "2. SAP RESULT - exact business-facing SAP outcome plus useful run context.
  PERFORM add_evidence_card USING '2. SAP RESULT'             ''.
  PERFORM add_evidence_card USING 'Exact SAP Message'         lv_sap_message_785.
  IF lv_technical_result_785 IS NOT INITIAL.
    PERFORM add_evidence_card USING 'Technical Result'         lv_technical_result_785.
  ENDIF.
  IF lv_subrc_text_785 IS NOT INITIAL.
    PERFORM add_evidence_card USING 'SY-SUBRC'                 lv_subrc_text_785.
  ENDIF.
  IF is_group-executor = 'CT'.
    PERFORM add_evidence_card USING 'BDC Mode'                lv_bdc_mode_text_782.
    PERFORM add_evidence_card USING 'Update Mode'             lv_update_mode_text_782.
  ELSEIF is_group-executor = 'BISM'.
    IF lv_sm35_mode_txt IS INITIAL.
      lv_sm35_mode_txt = '-'.
    ENDIF.
    PERFORM add_evidence_card USING 'Processing Mode'         lv_sm35_mode_txt.
  ENDIF.
  PERFORM add_evidence_card USING 'Run Duration'              lv_run_duration.

 "3. EVIDENCE - user-facing verification and provenance only.
  PERFORM add_evidence_card USING '3. EVIDENCE'               ''.
  PERFORM add_evidence_card USING 'Evidence Status'           lv_evidence_status.
  PERFORM add_evidence_card USING 'Evidence Time'             lv_time_text.
  PERFORM add_evidence_card USING 'Evidence Source'           lv_source.

 "4. ACTION is useful only when the user must review or correct something.
  IF is_group-lifecycle = 'WARNING' OR is_group-lifecycle = 'ERROR'.
    PERFORM add_evidence_card USING '4. ACTION'               ''.
    PERFORM add_evidence_card USING 'Action'                  lv_next_step.
  ENDIF.

  TRY.
      cl_salv_table=>factory(
        IMPORTING r_salv_table = go_evidence_grid_0100
        CHANGING  t_table      = gt_evidence_card_0100 ).

      go_evidence_grid_0100->get_functions( )->set_all( abap_true ).
      go_evidence_grid_0100->get_columns( )->set_optimize( abap_false ).
      TRY.
          go_evidence_grid_0100->get_display_settings( )->set_striped_pattern( abap_false ).
        CATCH cx_root.
      ENDTRY.

      DATA(lo_cols) = go_evidence_grid_0100->get_columns( ).
      TRY.
          lo_cols->set_color_column( 'CELL_COLORS' ).
        CATCH cx_salv_data_error.
      ENDTRY.
      PERFORM set_dash_col_text USING lo_cols 'SECTION' 'Section'.
      PERFORM set_dash_col_text USING lo_cols 'DETAIL'  'Detail / Explanation'.
      TRY.
          lo_cols->get_column( 'SECTION' )->set_output_length( 30 ).
          lo_cols->get_column( 'DETAIL' )->set_output_length( 112 ).
        CATCH cx_salv_not_found.
      ENDTRY.

      CONCATENATE 'Execution Evidence Detail -' is_group-group_key
             INTO lv_title SEPARATED BY space.
      go_evidence_grid_0100->get_display_settings( )->set_list_header( lv_title ).

 "size Level 3 to its actual content instead of reserving a
 "large fixed canvas. This removes the empty lower half on concise
 "SUCCESS cards while still leaving room for SALV title/functions.
      lv_popup_end = lines( gt_evidence_card_0100 ) + 9.
      IF lv_popup_end < 16.
        lv_popup_end = 16.
      ELSEIF lv_popup_end > 30.
        lv_popup_end = 30.
      ENDIF.

      go_evidence_grid_0100->set_screen_popup(
        start_column = 12
        end_column   = 154
        start_line   = 3
        end_line     = lv_popup_end ).

      go_evidence_grid_0100->display( ).

    CATCH cx_salv_msg INTO DATA(lx_salv).
      MESSAGE lx_salv->get_text( ) TYPE 'S' DISPLAY LIKE 'E'.
  ENDTRY.
ENDFORM.
