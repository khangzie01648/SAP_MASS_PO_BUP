
*& Include Z_BDC_MASS_PO_ENTRY_O01_BUP
*& Purpose PBO status, rendering and read-only screen projection
*& preserve 0350 PAI/template diagnostics

MODULE status_0100 OUTPUT.
  "V17.9.3.14B: obsolete Import child-mode bootstrap removed.
  "Current Import is one-pass RAW SHDB -> exact DDIC mapping and no longer
  "uses the legacy probe-child / ZP1 watcher architecture. Keeping the old
  "PERFORM here referenced a FORM intentionally removed from M2 and caused
  "a program-wide syntax error before any 0400 fix could be activated.
  TYPES: BEGIN OF ty_0100_kpi_stg,
           session_id TYPE zbdc_staging_bup-session_id,
           record_key TYPE zbdc_staging_bup-record_key,
           row_index  TYPE zbdc_staging_bup-row_index,
           tcode      TYPE zbdc_staging_bup-tcode,
           status     TYPE zbdc_staging_bup-status,
         END OF ty_0100_kpi_stg.

 "Level 1 is session-wide scope. Keep only common session facts.
 "Transaction scope stays aggregated here; executor is group-specific and
 "therefore belongs only to Level 2/3.
  TYPES: BEGIN OF ty_0100_tcode_dist,
           tcode TYPE char20,
         END OF ty_0100_tcode_dist.

  DATA: lt_kpi_stg        TYPE STANDARD TABLE OF ty_0100_kpi_stg WITH DEFAULT KEY,
        lt_sess_stg       TYPE STANDARD TABLE OF zbdc_staging_bup,
        lt_sess_res       TYPE STANDARD TABLE OF zbdc_result_bup,
        lt_ingested_sids  TYPE SORTED TABLE OF ty_kpi_sid_0100
                           WITH UNIQUE KEY session_id,
        ls_kpi_sid        TYPE ty_kpi_sid_0100,
        ls_group_0100     TYPE ty_kpi_group_0100,
        lv_group_key      TYPE c LENGTH 80,
        lv_status_norm    TYPE char20,
        lv_tot_sess       TYPE i,
        lv_total_groups   TYPE i,
        lv_succ_cnt       TYPE i,
        lv_warn_cnt       TYPE i,
        lv_err_cnt        TYPE i,
        lv_other_cnt      TYPE i,
        lv_succ_pct       TYPE p LENGTH 5 DECIMALS 1,
        lv_warn_pct       TYPE p LENGTH 5 DECIMALS 1,
        lv_err_pct        TYPE p LENGTH 5 DECIMALS 1,
        lv_other_pct      TYPE p LENGTH 5 DECIMALS 1,
        lv_source_0100    TYPE char20,
        lv_kpi_changed    TYPE abap_bool,
        lv_signature      TYPE string,
        lv_sig_hash       TYPE string,
        lt_sig_parts      TYPE STANDARD TABLE OF string WITH DEFAULT KEY,
        lv_result_count   TYPE i,
        lv_result_max     TYPE zbdc_result_bup-created_at,
        lt_sig_groups     TYPE STANDARD TABLE OF ty_kpi_group_0100 WITH DEFAULT KEY.

  FIELD-SYMBOLS <ls_group_0100> TYPE ty_kpi_group_0100.

 "STATUS_0100 is maintained physically with only the current visible actions:
 "Upload Excel and Result Investigation. No retired FCODE is hidden in code.
  SET PF-STATUS 'STATUS_0100'.
  SET TITLEBAR  'TITLE_0100'.

 "one canonical, all-time dashboard snapshot.
 "V17.9.3.4 DASHBOARD VISIBILITY CONTRACT:
 "A session is user-visible here only after a REAL successful ingest.
 "Proof requires BOTH:
 "  1) ZBDC_FILE_LG_BUP-STATUS = 'IMPORTED' for that exact SESSION_ID, and
 "  2) at least one persisted ZBDC_STAGING_BUP row for that SESSION_ID.
 "Failed upload/hash/duplicate/contract/no-row attempts may keep technical
 "audit evidence in RESULT/SESSION tables, but they must not pollute the
 "Main Dashboard with UNKNOWN / 0-group pseudo sessions.
 "Business-group identity = eligible STAGING SESSION_ID + RECORD_KEY, with
 "ROW_INDEX fallback only when the persisted RECORD_KEY is blank.
 "Header terminal KPIs are intentionally exact: SUCCESS only SUCCESS,
 "WARNING only WARNING, ERROR only ERROR. PARTIAL/SKIPPED/BLOCKED/etc. stay
 "inside Total Groups as Other/Open states and are never relabelled Warning.
  REFRESH: lt_kpi_stg, lt_ingested_sids,
           gt_kpi_sid_0100, gt_kpi_group_0100, lt_sig_groups.

  SELECT session_id, record_key, row_index, tcode, status
    FROM zbdc_staging_bup
    INTO CORRESPONDING FIELDS OF TABLE @lt_kpi_stg.

 "The file log is the structured source-of-truth for successful ingestion.
 "Do not infer success from SESSION/RESULT existence: those records can be
 "written before a later hash/duplicate/frozen-contract gate rejects ingest.
  SELECT DISTINCT session_id
    FROM zbdc_file_lg_bup
    INTO CORRESPONDING FIELDS OF TABLE @lt_ingested_sids
    WHERE status = 'IMPORTED'.

  LOOP AT lt_kpi_stg INTO DATA(ls_kpi_stg_0100).
    IF ls_kpi_stg_0100-session_id IS INITIAL
       OR ls_kpi_stg_0100-session_id CP 'GMAIL_REQ_*'.
      CONTINUE.
    ENDIF.

 "Intersection with persisted staging is deliberate. An IMPORTED file-log
 "row without any canonical staging rows is not a completed ingest scope and
 "therefore is not a dashboard session.
    READ TABLE lt_ingested_sids
      WITH TABLE KEY session_id = ls_kpi_stg_0100-session_id
      TRANSPORTING NO FIELDS.
    IF sy-subrc <> 0.
      CONTINUE.
    ENDIF.

    CLEAR ls_kpi_sid.
    ls_kpi_sid-session_id = ls_kpi_stg_0100-session_id.
    INSERT ls_kpi_sid INTO TABLE gt_kpi_sid_0100.

    CLEAR lv_group_key.
    IF ls_kpi_stg_0100-record_key IS NOT INITIAL.
      lv_group_key = |K:{ ls_kpi_stg_0100-record_key }|.
    ELSEIF ls_kpi_stg_0100-row_index IS NOT INITIAL.
      lv_group_key = |R:{ ls_kpi_stg_0100-row_index }|.
    ELSE.
 "Last-resort projection identity only. It is never persisted and never
 "merges unrelated blank-key rows into one fake business group.
      lv_group_key = |I:{ sy-tabix }|.
    ENDIF.

    UNASSIGN <ls_group_0100>.
    READ TABLE gt_kpi_group_0100 ASSIGNING <ls_group_0100>
      WITH TABLE KEY session_id = ls_kpi_stg_0100-session_id
                     group_key  = lv_group_key.
    IF sy-subrc <> 0.
      CLEAR ls_group_0100.
      ls_group_0100-session_id = ls_kpi_stg_0100-session_id.
      ls_group_0100-group_key  = lv_group_key.
      ls_group_0100-record_key = ls_kpi_stg_0100-record_key.
      ls_group_0100-row_index  = ls_kpi_stg_0100-row_index.
      ls_group_0100-tcode      = ls_kpi_stg_0100-tcode.
      INSERT ls_group_0100 INTO TABLE gt_kpi_group_0100 ASSIGNING <ls_group_0100>.
    ENDIF.

    IF <ls_group_0100> IS ASSIGNED.
      <ls_group_0100>-row_count = <ls_group_0100>-row_count + 1.
      IF <ls_group_0100>-tcode IS INITIAL AND ls_kpi_stg_0100-tcode IS NOT INITIAL.
        <ls_group_0100>-tcode = ls_kpi_stg_0100-tcode.
      ENDIF.

      lv_status_norm = ls_kpi_stg_0100-status.
      TRANSLATE lv_status_norm TO UPPER CASE.
      CONDENSE lv_status_norm NO-GAPS.

      CASE lv_status_norm.
        WHEN 'ERROR'.
          <ls_group_0100>-error_rows = <ls_group_0100>-error_rows + 1.
        WHEN 'WARNING'.
          <ls_group_0100>-warning_rows = <ls_group_0100>-warning_rows + 1.
        WHEN 'SUCCESS'.
          <ls_group_0100>-success_rows = <ls_group_0100>-success_rows + 1.
        WHEN 'SM35QUEUE' OR 'SM35_QUEUED' OR 'SM35RUN' OR 'QUEUED_SM35'.
          <ls_group_0100>-sm35_rows = <ls_group_0100>-sm35_rows + 1.
        WHEN OTHERS.
          <ls_group_0100>-other_rows = <ls_group_0100>-other_rows + 1.
          IF lv_status_norm IS INITIAL.
            lv_status_norm = 'BLANK'.
          ENDIF.
          IF <ls_group_0100>-other_state IS INITIAL.
            <ls_group_0100>-other_state = lv_status_norm.
          ELSEIF <ls_group_0100>-other_state <> lv_status_norm.
            <ls_group_0100>-other_state = 'MIXED'.
          ENDIF.
      ENDCASE.
    ENDIF.
  ENDLOOP.

  CLEAR: lv_succ_cnt, lv_warn_cnt, lv_err_cnt, lv_other_cnt.
  LOOP AT gt_kpi_group_0100 ASSIGNING <ls_group_0100>.
    CLEAR <ls_group_0100>-state.

 "Severity is fail-closed only for the exact current ERROR/WARNING states.
 "Historical RESULT rows never override current staging lifecycle.
    IF <ls_group_0100>-error_rows > 0.
      <ls_group_0100>-state = 'ERROR'.
      lv_err_cnt = lv_err_cnt + 1.
    ELSEIF <ls_group_0100>-warning_rows > 0.
      <ls_group_0100>-state = 'WARNING'.
      lv_warn_cnt = lv_warn_cnt + 1.
    ELSEIF <ls_group_0100>-row_count > 0
       AND <ls_group_0100>-success_rows = <ls_group_0100>-row_count.
      <ls_group_0100>-state = 'SUCCESS'.
      lv_succ_cnt = lv_succ_cnt + 1.
    ELSEIF <ls_group_0100>-row_count > 0
       AND <ls_group_0100>-sm35_rows = <ls_group_0100>-row_count.
      <ls_group_0100>-state = 'SM35QUEUE'.
      lv_other_cnt = lv_other_cnt + 1.
    ELSEIF <ls_group_0100>-row_count > 0
       AND <ls_group_0100>-other_rows = <ls_group_0100>-row_count
       AND <ls_group_0100>-other_state IS NOT INITIAL.
      <ls_group_0100>-state = <ls_group_0100>-other_state.
      lv_other_cnt = lv_other_cnt + 1.
    ELSE.
      <ls_group_0100>-state = 'MIXED'.
      lv_other_cnt = lv_other_cnt + 1.
    ENDIF.
  ENDLOOP.

  lv_tot_sess     = lines( gt_kpi_sid_0100 ).
  lv_total_groups = lines( gt_kpi_group_0100 ).

 "Residual Other/Open protects against any current lifecycle that is not one
 "of the three terminal header KPIs; it remains inside Total Groups only.
  lv_other_cnt = lv_total_groups - lv_succ_cnt - lv_warn_cnt - lv_err_cnt.
  IF lv_other_cnt < 0.
    lv_other_cnt = 0.
  ENDIF.

  CLEAR: lv_succ_pct, lv_warn_pct, lv_err_pct, lv_other_pct.
  IF lv_total_groups > 0.
    lv_succ_pct  = ( lv_succ_cnt  * 100 ) / lv_total_groups.
    lv_warn_pct  = ( lv_warn_cnt  * 100 ) / lv_total_groups.
    lv_err_pct   = ( lv_err_cnt   * 100 ) / lv_total_groups.
    lv_other_pct = ( lv_other_cnt * 100 ) / lv_total_groups.
  ENDIF.

 "Create a deterministic snapshot signature. This catches state swaps where
 "global counts are unchanged, so the session SALV still refreshes correctly.
  CLEAR: lv_signature, lv_sig_hash.
  REFRESH lt_sig_parts.
  LOOP AT gt_kpi_sid_0100 INTO DATA(ls_sig_sid_0100).
    APPEND |S:{ ls_sig_sid_0100-session_id };| TO lt_sig_parts.
  ENDLOOP.

  LOOP AT gt_kpi_group_0100 INTO ls_group_0100.
    APPEND ls_group_0100 TO lt_sig_groups.
  ENDLOOP.
  SORT lt_sig_groups BY session_id group_key.
  LOOP AT lt_sig_groups INTO DATA(ls_sig_group_0100).
    APPEND |G:{ ls_sig_group_0100-session_id }\|{ ls_sig_group_0100-group_key }\|{ ls_sig_group_0100-state }\|{ ls_sig_group_0100-tcode }\|{ ls_sig_group_0100-row_count };|
      TO lt_sig_parts.
  ENDLOOP.

  SELECT COUNT( * ) FROM zbdc_result_bup INTO @lv_result_count.
  SELECT MAX( created_at ) FROM zbdc_result_bup INTO @lv_result_max.
  APPEND |R:{ lv_result_count }\|{ lv_result_max }| TO lt_sig_parts.
  CONCATENATE LINES OF lt_sig_parts INTO lv_signature.

 "The project already relies on the standard ABAP SHA-256 digest class for
 "immutable contract hashes. Reuse it here so the live dashboard keeps only
 "a compact deterministic change token instead of a large raw signature.
  TRY.
      cl_abap_message_digest=>calculate_hash_for_char(
        EXPORTING
          if_algorithm     = 'SHA-256'
          if_data          = lv_signature
        IMPORTING
          ef_hashb64string = lv_sig_hash ).
    CATCH cx_abap_message_digest.
 "Fail safe: raw deterministic signature still detects the same changes.
      lv_sig_hash = lv_signature.
  ENDTRY.

  IF gv_kpi_signature_0100 <> lv_sig_hash.
    lv_kpi_changed = abap_true.
    gv_kpi_signature_0100 = lv_sig_hash.
  ENDIF.

  txtgv_total_sessions = |{ lv_tot_sess }|.
  txtgv_processed_pos  = |{ lv_total_groups }|. "legacy field name; SE51 label = Total Groups
  txtgv_success_count  = |{ lv_succ_cnt }|.
  txtgv_warning_count  = |{ lv_warn_cnt }|.
  txtgv_error_count    = |{ lv_err_cnt }|.
  txtgv_open_count     = |{ lv_other_cnt }|.

 "Compact percentage text keeps all status-rate fields visually identical.
 "three SE51 output-field lengths to at least 6 so 100.0% also fits.
  txtgv_success_pct = |{ lv_succ_pct }%|.
  txtgv_warning_pct = |{ lv_warn_pct }%|.
  txtgv_error_pct   = |{ lv_err_pct }%|.
  txtgv_open_pct    = |{ lv_other_pct }%|.
  CONDENSE txtgv_success_pct NO-GAPS.
  CONDENSE txtgv_warning_pct NO-GAPS.
  CONDENSE txtgv_error_pct NO-GAPS.
  CONDENSE txtgv_open_pct NO-GAPS.

  IF gv_dash_0100_tick = abap_true
     AND lv_kpi_changed <> abap_true
     AND go_grid_0100 IS BOUND.
    CLEAR gv_dash_0100_tick.
    PERFORM start_dash_timer.
    RETURN.
  ENDIF.

 "The expensive session projection is rebuilt only when the deterministic
 "snapshot changed; a no-change timer tick only repaints the bound KPI fields.
  PERFORM get_recent_sessions.

 "Do NOT use current ZBDC_CONFIG_BUP-SOURCE_TYPE for all rows.
 "Source in 0100 must be session-specific. If old sessions have no persisted
 "source marker, show UNKNOWN instead of fake persisted source.
  lv_source_0100 = 'UNKNOWN'.

 "ALV 0100 = Recent Session Summary. One line per session, not raw message log.
  REFRESH gt_dash_0100.

  LOOP AT gt_sessions INTO DATA(ls_sess_0100).
    DATA: ls_dash_0100       TYPE ty_dash_0100_disp,
          ls_sess_db_0100    TYPE zbdc_session_bup,
          ls_sess_group_0100 TYPE ty_kpi_group_0100,
          lv_created_ts_0100 TYPE zbdc_result_bup-created_at,
          lv_ready_0100     TYPE i,
          lv_total_0100     TYPE i,
          lv_success_0100   TYPE i,
          lv_warning_0100   TYPE i,
          lv_error_0100     TYPE i,
          lv_st_ready_0100        TYPE i,
          lv_st_queued_0100       TYPE i,
          lv_st_processing_0100   TYPE i,
          lv_st_verifying_0100    TYPE i,
          lv_st_sm35_0100         TYPE i,
          lv_st_processed_0100    TYPE i,
          lv_st_partial_0100      TYPE i,
          lv_st_skipped_0100      TYPE i,
          lv_st_blocked_0100      TYPE i,
          lv_st_mixed_0100        TYPE i,
          lv_st_other_0100        TYPE i,
          lv_done_0100            TYPE i,
          lv_log_0100       TYPE i,
          lv_retry_yes_0100 TYPE c LENGTH 1,
          lv_main_err_0100  TYPE char120,
          lv_last_obj_0100  TYPE zbdc_result_bup-sap_object_id,
          lv_tcode_0100     TYPE char20,
          lv_res_group_key_0100 TYPE c LENGTH 80,
          lv_source_ok_0100 TYPE abap_bool,
          lv_source_msg_0100 TYPE string,
          lv_source_sid_0100 TYPE zbdc_file_lg_bup-session_id,
          lt_tcodes_0100    TYPE SORTED TABLE OF ty_0100_tcode_dist
                               WITH UNIQUE KEY tcode,
          ls_tcode_dist_0100 TYPE ty_0100_tcode_dist,
          lv_tcode_count_0100 TYPE i.

    CLEAR: ls_dash_0100, ls_sess_db_0100, lv_created_ts_0100,
           lv_ready_0100, lv_total_0100,
           lv_success_0100, lv_warning_0100, lv_error_0100,
           lv_st_ready_0100, lv_st_queued_0100, lv_st_processing_0100,
           lv_st_verifying_0100, lv_st_sm35_0100, lv_st_processed_0100,
           lv_st_partial_0100, lv_st_skipped_0100, lv_st_blocked_0100,
           lv_st_mixed_0100, lv_st_other_0100, lv_done_0100, lv_log_0100,
           lv_retry_yes_0100, lv_main_err_0100, lv_last_obj_0100,
           lv_tcode_0100, lv_res_group_key_0100,
           lv_source_sid_0100, lv_tcode_count_0100.
    REFRESH: lt_sess_stg, lt_sess_res, lt_tcodes_0100.

    ls_dash_0100-session_id  = ls_sess_0100-session_id.
    ls_dash_0100-source_type = lv_source_0100.

    SELECT SINGLE *
      FROM zbdc_session_bup
      INTO @ls_sess_db_0100
      WHERE session_id = @ls_sess_0100-session_id.

    IF ls_sess_db_0100-created_by IS NOT INITIAL.
      ls_dash_0100-created_by = ls_sess_db_0100-created_by.
    ELSE.
 "Strict-real rule: do not fallback to current dashboard user.
 "If no persisted creator evidence exists, show UNKNOWN.
      ls_dash_0100-created_by = 'UNKNOWN'.
    ENDIF.

    SELECT * FROM zbdc_staging_bup
      INTO TABLE @lt_sess_stg
      WHERE session_id = @ls_sess_0100-session_id.

    SELECT * FROM zbdc_result_bup
      INTO TABLE @lt_sess_res
      WHERE session_id = @ls_sess_0100-session_id
      ORDER BY created_at DESCENDING.

    lv_log_0100 = lines( lt_sess_res ).

 "Strict-real creator evidence priority:
 "1) ZBDC_SESSION_BUP-CREATED_BY, written during upload/source ingestion.
 "2) UNKNOWN. Never use SY-UNAME from the current dashboard viewer.
 "Note: ZBDC_RESULT_BUP in this system has no CREATED_BY field.

 "Source provenance comes only from the persisted file/source log.
 "No result-message parsing, current preview fallback or session-prefix guess.
 "Convert once at the dashboard/provenance boundary. The resolver stays
 "strictly typed to the persisted file-log session key.
    lv_source_sid_0100 = ls_sess_0100-session_id.
    PERFORM get_session_source
      USING    lv_source_sid_0100
      CHANGING ls_dash_0100-source_type lv_source_ok_0100 lv_source_msg_0100.
    IF lv_source_ok_0100 <> abap_true.
      ls_dash_0100-source_type = 'UNKNOWN'.
    ENDIF.

 "Level 1 is a session-wide scope summary. Collect every distinct
 "persisted TCode instead of silently showing whichever row happened first.
 "The exact TCode for each business group remains a Level-2 property.
    LOOP AT lt_sess_stg INTO DATA(ls_stg_0100).
      IF ls_stg_0100-tcode IS NOT INITIAL.
        CLEAR ls_tcode_dist_0100.
        ls_tcode_dist_0100-tcode = ls_stg_0100-tcode.
        INSERT ls_tcode_dist_0100 INTO TABLE lt_tcodes_0100.
      ENDIF.
    ENDLOOP.

    LOOP AT lt_sess_res INTO DATA(ls_res_0100).
      IF ls_res_0100-tcode IS NOT INITIAL.
        CLEAR ls_tcode_dist_0100.
        ls_tcode_dist_0100-tcode = ls_res_0100-tcode.
        INSERT ls_tcode_dist_0100 INTO TABLE lt_tcodes_0100.
      ENDIF.

      IF ls_res_0100-retry_flag = 'X'.
        lv_retry_yes_0100 = 'X'.
      ENDIF.
    ENDLOOP.

    CLEAR: lv_total_0100, lv_success_0100, lv_warning_0100,
           lv_error_0100, lv_ready_0100, lv_st_ready_0100,
           lv_st_queued_0100, lv_st_processing_0100,
           lv_st_verifying_0100, lv_st_sm35_0100,
           lv_st_processed_0100, lv_st_partial_0100,
           lv_st_skipped_0100, lv_st_blocked_0100,
           lv_st_mixed_0100, lv_st_other_0100, lv_done_0100.

 "preserve the exact current group states first. READY_REC remains
 "the Level-1 Open counter for compatibility, while the dedicated counters
 "below decide a precise user-facing session Lifecycle.
    LOOP AT gt_kpi_group_0100 INTO ls_sess_group_0100
      WHERE session_id = ls_sess_0100-session_id.
      lv_total_0100 = lv_total_0100 + 1.

 "keep the common Level-1 transaction scope honest. TCode is
 "aggregated from exact per-group facts instead of one arbitrary row.
 "Executor is intentionally not resolved at Level 1.
      IF ls_sess_group_0100-tcode IS NOT INITIAL.
        CLEAR ls_tcode_dist_0100.
        ls_tcode_dist_0100-tcode = ls_sess_group_0100-tcode.
        INSERT ls_tcode_dist_0100 INTO TABLE lt_tcodes_0100.
      ENDIF.

      CASE ls_sess_group_0100-state.
        WHEN 'SUCCESS'.
          lv_success_0100 = lv_success_0100 + 1.
        WHEN 'WARNING'.
          lv_warning_0100 = lv_warning_0100 + 1.
        WHEN 'ERROR'.
          lv_error_0100 = lv_error_0100 + 1.
        WHEN 'SM35QUEUE' OR 'SM35_QUEUED' OR 'SM35RUN' OR 'QUEUED_SM35'.
          lv_ready_0100   = lv_ready_0100 + 1.
          lv_st_sm35_0100 = lv_st_sm35_0100 + 1.
        WHEN 'PROCESSING'.
          lv_ready_0100         = lv_ready_0100 + 1.
          lv_st_processing_0100 = lv_st_processing_0100 + 1.
        WHEN 'VERIFYING'.
          lv_ready_0100        = lv_ready_0100 + 1.
          lv_st_verifying_0100 = lv_st_verifying_0100 + 1.
        WHEN 'PROCESSED'.
 "PROCESSED is a technical intermediate state. At Level 1 it is
 "shown as VERIFYING because final runtime evidence is not closed yet.
          lv_ready_0100        = lv_ready_0100 + 1.
          lv_st_processed_0100 = lv_st_processed_0100 + 1.
        WHEN 'READY'.
          lv_ready_0100    = lv_ready_0100 + 1.
          lv_st_ready_0100 = lv_st_ready_0100 + 1.
        WHEN 'QUEUED'.
 "Internal queue state is not exposed as a separate CT lifecycle.
          lv_ready_0100     = lv_ready_0100 + 1.
          lv_st_queued_0100 = lv_st_queued_0100 + 1.
        WHEN 'PARTIAL'.
          lv_ready_0100      = lv_ready_0100 + 1.
          lv_st_partial_0100 = lv_st_partial_0100 + 1.
        WHEN 'SKIPPED'.
          lv_ready_0100      = lv_ready_0100 + 1.
          lv_st_skipped_0100 = lv_st_skipped_0100 + 1.
        WHEN 'BLOCKED_ONBOARDING'.
          lv_ready_0100      = lv_ready_0100 + 1.
          lv_st_blocked_0100 = lv_st_blocked_0100 + 1.
        WHEN 'MIXED'.
          lv_ready_0100    = lv_ready_0100 + 1.
          lv_st_mixed_0100 = lv_st_mixed_0100 + 1.
        WHEN OTHERS.
          lv_ready_0100    = lv_ready_0100 + 1.
          lv_st_other_0100 = lv_st_other_0100 + 1.
      ENDCASE.
    ENDLOOP.

 "project session scope only after all canonical groups were read.
 "One distinct value stays readable; multiple values are explicitly
 "reported as a scope instead of pretending the first one represents all.
    lv_tcode_count_0100 = lines( lt_tcodes_0100 ).
    CASE lv_tcode_count_0100.
      WHEN 0.
        lv_tcode_0100 = 'UNKNOWN'.
      WHEN 1.
        READ TABLE lt_tcodes_0100 INTO ls_tcode_dist_0100 INDEX 1.
        IF sy-subrc = 0.
          lv_tcode_0100 = ls_tcode_dist_0100-tcode.
        ELSE.
          lv_tcode_0100 = 'UNKNOWN'.
        ENDIF.
      WHEN OTHERS.
        lv_tcode_0100 = |MULTI ({ lv_tcode_count_0100 })|.
    ENDCASE.

    ls_dash_0100-total_rec   = lv_total_0100.
    ls_dash_0100-ready_rec   = lv_ready_0100.
    ls_dash_0100-success_rec = lv_success_0100.
    ls_dash_0100-warning_rec = lv_warning_0100.
    ls_dash_0100-error_rec   = lv_error_0100.
    ls_dash_0100-log_count   = lv_log_0100.
    ls_dash_0100-tcode       = lv_tcode_0100.
    CLEAR ls_dash_0100-last_object. "hidden legacy field

    IF lv_total_0100 > 0.
      ls_dash_0100-success_pct = ( lv_success_0100 * 100 ) / lv_total_0100.
    ENDIF.
    PERFORM format_rate
      USING lv_success_0100 lv_total_0100
      CHANGING ls_dash_0100-success_pct_txt.

 "Session state is calculated internally for Overall Result and next action.
 "The redundant Health traffic-light column is intentionally removed from
 "Level 1; exact state remains available through KPIs and drill-down evidence.
    IF lv_error_0100 > 0.
      ls_dash_0100-status_text = 'ERROR'.
      IF lv_retry_yes_0100 = 'X'.
        ls_dash_0100-retryable   = 'Yes'.
        ls_dash_0100-next_action = 'Retry / Review Error'.
      ELSE.
        ls_dash_0100-retryable   = 'UNKNOWN'.
        ls_dash_0100-next_action = 'Review Error'.
      ENDIF.

    ELSEIF lv_st_blocked_0100 > 0.
      ls_dash_0100-status_text = 'BLOCKED_ONBOARDING'.
      ls_dash_0100-retryable   = 'No'.
      ls_dash_0100-next_action = 'Complete Onboarding'.

    ELSEIF lv_st_processing_0100 > 0 OR
           lv_st_queued_0100 > 0 OR
           lv_st_mixed_0100 > 0.
      ls_dash_0100-status_text = 'PROCESSING'.
      ls_dash_0100-retryable   = 'No'.
      ls_dash_0100-next_action = 'Wait / Refresh'.

    ELSEIF lv_st_verifying_0100 > 0 OR
           lv_st_processed_0100 > 0.
      ls_dash_0100-status_text = 'VERIFYING'.
      ls_dash_0100-retryable   = 'No'.
      ls_dash_0100-next_action = 'Wait for Verification'.

    ELSEIF lv_st_sm35_0100 > 0.
 "SM35 queue is a group state, not a session-wide executor
 "assumption. A mixed CT/BISM session may legitimately contain queued
 "BISM groups. Show SM35 QUEUED only when the whole unfinished session
 "is at that stage; otherwise the common lifecycle is PROCESSING.
      ls_dash_0100-retryable = 'No'.
      IF lv_st_sm35_0100 = lv_ready_0100 AND
         lv_success_0100 = 0 AND lv_warning_0100 = 0 AND lv_error_0100 = 0.
        ls_dash_0100-status_text = 'SM35 QUEUED'.
        ls_dash_0100-next_action = 'Process / Monitor SM35'.
      ELSE.
        ls_dash_0100-status_text = 'PROCESSING'.
        ls_dash_0100-next_action = 'Continue Processing'.
      ENDIF.

    ELSEIF lv_st_partial_0100 > 0.
      ls_dash_0100-status_text = 'PARTIAL'.
      ls_dash_0100-retryable   = 'No'.
      ls_dash_0100-next_action = 'Review Partial Groups'.

    ELSEIF lv_st_skipped_0100 > 0.
      ls_dash_0100-status_text = 'SKIPPED'.
      ls_dash_0100-retryable   = 'No'.
      ls_dash_0100-next_action = 'Review Skipped Groups'.

    ELSEIF lv_ready_0100 > 0.
 "If some groups already finished while others are still generic READY,
 "the session has begun and therefore displays PROCESSING, not READY.
      IF lv_success_0100 > 0 OR lv_warning_0100 > 0.
        ls_dash_0100-status_text = 'PROCESSING'.
        ls_dash_0100-next_action = 'Continue Processing'.
      ELSE.
        ls_dash_0100-status_text = 'READY'.
        ls_dash_0100-next_action = 'Execute'.
      ENDIF.
      ls_dash_0100-retryable = 'No'.

    ELSEIF lv_warning_0100 > 0.
      ls_dash_0100-status_text = 'WARNING'.
      ls_dash_0100-retryable   = 'No'.
      ls_dash_0100-next_action = 'Review Warning'.

    ELSEIF lv_total_0100 > 0 AND lv_success_0100 = lv_total_0100.
      ls_dash_0100-status_text = 'SUCCESS'.
      ls_dash_0100-retryable   = 'No'.
      ls_dash_0100-next_action = 'Done'.

    ELSE.
      ls_dash_0100-status_text = 'NO_DATA'.
      ls_dash_0100-retryable   = 'No'.
      ls_dash_0100-next_action = 'Open Staging'.
    ENDIF.

 "concise plain-language Overall Result. It remains different from
 "Lifecycle (technical stage) and Level-3 evidence (exact SAP protocol).
    lv_done_0100 = lv_success_0100 + lv_warning_0100 + lv_error_0100.
    CLEAR lv_main_err_0100.
    CASE ls_dash_0100-status_text.
      WHEN 'SUCCESS'.
        lv_main_err_0100 = |{ lv_success_0100 }/{ lv_total_0100 } completed successfully|.
      WHEN 'WARNING'.
        lv_main_err_0100 = |{ lv_success_0100 } success - { lv_warning_0100 } warning|.
      WHEN 'ERROR'.
        IF lv_ready_0100 > 0.
          lv_main_err_0100 = |{ lv_success_0100 } success - { lv_error_0100 } failed - { lv_ready_0100 } remaining|.
        ELSE.
          lv_main_err_0100 = |{ lv_success_0100 } success - { lv_error_0100 } failed|.
        ENDIF.
      WHEN 'SM35 QUEUED'.
        lv_main_err_0100 = |{ lv_st_sm35_0100 } waiting in SM35 - { lv_done_0100 } completed|.
      WHEN 'VERIFYING'.
        lv_main_err_0100 = |{ lv_ready_0100 } awaiting final verification|.
      WHEN 'PROCESSING'.
        lv_main_err_0100 = |{ lv_done_0100 }/{ lv_total_0100 } completed - { lv_ready_0100 } in progress|.
      WHEN 'READY'.
        lv_main_err_0100 = |{ lv_ready_0100 }/{ lv_total_0100 } ready to execute|.
      WHEN 'BLOCKED_ONBOARDING'.
        lv_main_err_0100 = |{ lv_st_blocked_0100 } blocked by onboarding|.
      WHEN 'PARTIAL'.
        lv_main_err_0100 = |{ lv_st_partial_0100 } partially completed|.
      WHEN 'SKIPPED'.
        lv_main_err_0100 = |{ lv_st_skipped_0100 } skipped|.
      WHEN OTHERS.
        IF lv_total_0100 > 0.
          lv_main_err_0100 = |{ lv_done_0100 }/{ lv_total_0100 } have a terminal result|.
        ELSE.
          lv_main_err_0100 = 'No execution data available'.
        ENDIF.
    ENDCASE.
    ls_dash_0100-main_error = lv_main_err_0100.

 "render the persisted session timestamp through the same typed,
 "validated formatter as Level 2. Invalid values such as xx:xx:60 are never
 "shown. If persisted time cannot be converted, use the validated timestamp
 "component of this project's generated SESSION_ID; otherwise show UNKNOWN.
    CLEAR: ls_dash_0100-created_on, ls_dash_0100-sort_key, lv_created_ts_0100.
    lv_created_ts_0100 = ls_sess_0100-created_at.
    PERFORM format_result_time
      USING lv_created_ts_0100
      CHANGING ls_dash_0100-created_on.

    IF ls_dash_0100-created_on IS INITIAL AND
       ls_sess_db_0100-start_time IS NOT INITIAL.
      TRY.
          lv_created_ts_0100 = ls_sess_db_0100-start_time.
        CATCH cx_root.
          CLEAR lv_created_ts_0100.
      ENDTRY.
      PERFORM format_result_time
        USING lv_created_ts_0100
        CHANGING ls_dash_0100-created_on.
    ENDIF.

    IF ls_dash_0100-created_on IS NOT INITIAL.
      CONCATENATE ls_dash_0100-created_on+0(4)
                  ls_dash_0100-created_on+5(2)
                  ls_dash_0100-created_on+8(2)
                  ls_dash_0100-created_on+11(2)
                  ls_dash_0100-created_on+14(2)
                  ls_dash_0100-created_on+17(2)
             INTO ls_dash_0100-sort_key.
    ELSE.
      PERFORM format_id_time
        USING ls_dash_0100-session_id
        CHANGING ls_dash_0100-created_on ls_dash_0100-sort_key.
    ENDIF.

    IF ls_dash_0100-created_on IS INITIAL.
      ls_dash_0100-created_on = 'UNKNOWN'.
    ENDIF.

    APPEND ls_dash_0100 TO gt_dash_0100.
  ENDLOOP.

 "Show newest real sessions first. UNKNOWN/blank timestamps go to bottom.
  SORT gt_dash_0100 BY sort_key DESCENDING session_id DESCENDING.

 "do not destroy/recreate the SALV on every PBO/live tick.
 "A soft refresh keeps the custom container stable, avoids flicker and
 "preserves the enterprise-dashboard feel. Recreate only after a real
 "Control Framework failure.
  IF go_grid_0100 IS BOUND AND go_container_0100 IS BOUND.
    TRY.
        "Always restore the original row/column selector on every PBO.
        "This repairs an already-created SALV that was previously switched
        "to SINGLE mode without forcing the user to restart the program.
        go_grid_0100->get_selections( )->set_selection_mode(
          if_salv_c_selection_mode=>row_column ).
        go_grid_0100->refresh( ).
      CATCH cx_root.
        FREE: go_grid_0100, go_container_0100.
    ENDTRY.
  ENDIF.

  IF go_grid_0100 IS NOT BOUND.
    IF go_container_0100 IS BOUND.
      FREE go_container_0100.
    ENDIF.

    CREATE OBJECT go_container_0100
      EXPORTING container_name = 'CC_ALV_CONTAINER'.

    TRY.
      cl_salv_table=>factory(
        EXPORTING r_container  = go_container_0100
        IMPORTING r_salv_table = go_grid_0100
        CHANGING  t_table      = gt_dash_0100 ).
      go_grid_0100->get_functions( )->set_all( abap_true ).

 "Keep the dashboard's original explicit row selector for the actions
 "that still use row selection. GT07 itself no longer depends on a selected
 "dashboard row; it opens the global Result Investigation workspace directly.
      TRY.
          DATA(lo_sel_0100_fix) = go_grid_0100->get_selections( ).
          lo_sel_0100_fix->set_selection_mode(
            if_salv_c_selection_mode=>row_column ).
        CATCH cx_root.
      ENDTRY.

      DATA(lo_cols_0100) = go_grid_0100->get_columns( ).
 "LEVEL-1: match the approved overview reference with a stable,
 "single-view session table. Widths below are intentionally compact so
 "all business columns fit inside a 200-column CC_ALV_CONTAINER without
 "horizontal scrolling. Auto-optimize is disabled because it produced
 "unstable/truncated headers on the target SAP GUI.
      lo_cols_0100->set_optimize( abap_false ).
      TRY.
          go_grid_0100->get_display_settings( )->set_striped_pattern( abap_true ).
        CATCH cx_root.
      ENDTRY.

      TRY.
          DATA(lo_col_0100) = lo_cols_0100->get_column( 'SORT_KEY' ).
          lo_col_0100->set_visible( abap_false ).
        CATCH cx_salv_not_found.
      ENDTRY.

      TRY.
          lo_col_0100 = lo_cols_0100->get_column( 'SESSION_ID' ).
          lo_col_0100->set_short_text( 'Session' ).
          lo_col_0100->set_medium_text( 'Session ID' ).
          lo_col_0100->set_long_text( 'Session ID' ).
          lo_col_0100->set_output_length( 21 ).
        CATCH cx_salv_not_found.
      ENDTRY.

      TRY.
          lo_col_0100 = lo_cols_0100->get_column( 'CREATED_ON' ).
          lo_col_0100->set_short_text( 'Time' ).
          lo_col_0100->set_medium_text( 'Created Time' ).
          lo_col_0100->set_long_text( 'Created Time' ).
          lo_col_0100->set_output_length( 19 ).
        CATCH cx_salv_not_found.
      ENDTRY.

      TRY.
          lo_col_0100 = lo_cols_0100->get_column( 'CREATED_BY' ).
          lo_col_0100->set_short_text( 'User' ).
          lo_col_0100->set_medium_text( 'User' ).
          lo_col_0100->set_long_text( 'User' ).
          lo_col_0100->set_output_length( 7 ).
        CATCH cx_salv_not_found.
      ENDTRY.

      "LEVEL-1 cleanup: inbound Source is provenance/detail evidence, not a
      "session-overview KPI. Keep SOURCE_TYPE populated internally so lower
      "levels/audit remain unchanged, but do not expose it on the Level-1 ALV.
      TRY.
          lo_col_0100 = lo_cols_0100->get_column( 'SOURCE_TYPE' ).
          lo_col_0100->set_visible( abap_false ).
        CATCH cx_salv_not_found.
      ENDTRY.

      TRY.
          lo_col_0100 = lo_cols_0100->get_column( 'TCODE' ).
          lo_col_0100->set_short_text( 'TCode(s)' ).
          lo_col_0100->set_medium_text( 'Transactions' ).
          lo_col_0100->set_long_text( 'Transaction Scope' ).
          lo_col_0100->set_output_length( 12 ).
        CATCH cx_salv_not_found.
      ENDTRY.

 "LEVEL-1 UI: execution method and lifecycle are intentionally
 "hidden from the session overview. A session may contain many TCodes
 "and each business group may independently run by CT or BISM, so the
 "method belongs to Level 2/3. Lifecycle is already represented by the
 "KPI counters + Overall Result and would duplicate it. Keep both values
 "populated internally for aggregation/state logic.
      TRY.
          lo_col_0100 = lo_cols_0100->get_column( 'EXECUTOR' ).
          lo_col_0100->set_visible( abap_false ).
        CATCH cx_salv_not_found.
      ENDTRY.

      TRY.
          lo_col_0100 = lo_cols_0100->get_column( 'STATUS_TEXT' ).
          lo_col_0100->set_visible( abap_false ).
        CATCH cx_salv_not_found.
      ENDTRY.

      TRY.
          lo_col_0100 = lo_cols_0100->get_column( 'TOTAL_REC' ).
          lo_col_0100->set_short_text( 'Groups' ).
          lo_col_0100->set_medium_text( 'Total Groups' ).
          lo_col_0100->set_long_text( 'Total Groups' ).
          lo_col_0100->set_output_length( 12 ).
        CATCH cx_salv_not_found.
      ENDTRY.

      TRY.
          lo_col_0100 = lo_cols_0100->get_column( 'READY_REC' ).
          lo_col_0100->set_short_text( 'Open' ).
          lo_col_0100->set_medium_text( 'Open' ).
          lo_col_0100->set_long_text( 'Open' ).
          lo_col_0100->set_output_length( 5 ).
        CATCH cx_salv_not_found.
      ENDTRY.

      TRY.
          lo_col_0100 = lo_cols_0100->get_column( 'SUCCESS_REC' ).
          lo_col_0100->set_short_text( 'Success' ).
          lo_col_0100->set_medium_text( 'Success' ).
          lo_col_0100->set_long_text( 'Success' ).
          lo_col_0100->set_output_length( 7 ).
        CATCH cx_salv_not_found.
      ENDTRY.

      TRY.
          lo_col_0100 = lo_cols_0100->get_column( 'WARNING_REC' ).
          lo_col_0100->set_short_text( 'Warning' ).
          lo_col_0100->set_medium_text( 'Warning' ).
          lo_col_0100->set_long_text( 'Warning' ).
          lo_col_0100->set_output_length( 7 ).
        CATCH cx_salv_not_found.
      ENDTRY.

      TRY.
          lo_col_0100 = lo_cols_0100->get_column( 'ERROR_REC' ).
          lo_col_0100->set_short_text( 'Error' ).
          lo_col_0100->set_medium_text( 'Error' ).
          lo_col_0100->set_long_text( 'Error' ).
          lo_col_0100->set_output_length( 5 ).
        CATCH cx_salv_not_found.
      ENDTRY.

      TRY.
          lo_col_0100 = lo_cols_0100->get_column( 'SUCCESS_PCT' ).
          lo_col_0100->set_visible( abap_false ).
        CATCH cx_salv_not_found.
      ENDTRY.

      TRY.
          lo_col_0100 = lo_cols_0100->get_column( 'SUCCESS_PCT_TXT' ).
          lo_col_0100->set_short_text( 'Success %' ).
          lo_col_0100->set_medium_text( 'Success %' ).
          lo_col_0100->set_long_text( 'Success %' ).
          lo_col_0100->set_output_length( 10 ).
        CATCH cx_salv_not_found.
      ENDTRY.

      TRY.
          lo_col_0100 = lo_cols_0100->get_column( 'LOG_COUNT' ).
          lo_col_0100->set_visible( abap_false ).
        CATCH cx_salv_not_found.
      ENDTRY.

      TRY.
          lo_col_0100 = lo_cols_0100->get_column( 'LAST_OBJECT' ).
          lo_col_0100->set_visible( abap_false ).
        CATCH cx_salv_not_found.
      ENDTRY.

      TRY.
          lo_col_0100 = lo_cols_0100->get_column( 'MAIN_ERROR' ).
          lo_col_0100->set_short_text( 'Result' ).
          lo_col_0100->set_medium_text( 'Overall Result' ).
          lo_col_0100->set_long_text( 'Overall Result' ).
          lo_col_0100->set_output_length( 30 ).
        CATCH cx_salv_not_found.
      ENDTRY.

      TRY.
          lo_col_0100 = lo_cols_0100->get_column( 'RETRYABLE' ).
          lo_col_0100->set_visible( abap_false ).
        CATCH cx_salv_not_found.
      ENDTRY.

      TRY.
          lo_col_0100 = lo_cols_0100->get_column( 'NEXT_ACTION' ).
          lo_col_0100->set_visible( abap_false ).
        CATCH cx_salv_not_found.
      ENDTRY.

      go_grid_0100->display( ).

      DATA(lo_events) = go_grid_0100->get_event( ).
      CREATE OBJECT go_alv_events.
      SET HANDLER go_alv_events->on_double_click FOR lo_events.
      CATCH cx_salv_msg INTO DATA(lx_salv_0100).
        gv_ui_message = 'Dashboard could not be displayed. Refresh and try again.'.
        MESSAGE gv_ui_message TYPE 'I'.
    ENDTRY.
  ENDIF.

  CLEAR gv_dash_0100_tick.
  PERFORM start_dash_timer.
ENDMODULE.

MODULE status_0300 OUTPUT.
  DATA: lv_clean_path_0300 TYPE string,
        lv_sheet_meta_0300 TYPE string,
        lv_policy_ok_0300  TYPE abap_bool,
        lv_policy_msg_0300 TYPE string.

 "0300 owns runtime/source configuration directly.
 "Runtime configuration is no longer part of the user flow and is not embedded.
 "The runtime policy is loaded once, then PBO validates and renders it.
 "PBO never infers business state from a function code or silently repairs it.
  IF gv_config_loaded IS INITIAL.
    PERFORM load_source_config.
    gv_config_loaded = 'X'.
  ENDIF.

  IF txtp_batch_size IS INITIAL.
    txtp_batch_size = '100'.
  ENDIF.

  PERFORM check_runtime_policy
    CHANGING lv_policy_ok_0300 lv_policy_msg_0300.
  IF lv_policy_ok_0300 <> abap_true.
    PERFORM userize_ui_message USING lv_policy_msg_0300 CHANGING gv_ui_message.
    MESSAGE gv_ui_message TYPE 'S' DISPLAY LIKE 'E'.
  ENDIF.
  PERFORM render_runtime_policy.

 "STATUS_0300 is maintained physically with only Staging and Save Note.
 "Template/Refresh FCODEs are retired from the GUI status, not hidden here.
  SET PF-STATUS 'STATUS_0300'.
  SET TITLEBAR  'TITLE_0300'.

  IF txtp_file_path CS '|SHEET='.
    SPLIT txtp_file_path AT '|SHEET='
      INTO lv_clean_path_0300 lv_sheet_meta_0300.
    txtp_file_path = lv_clean_path_0300.
  ENDIF.

 "the visible tab body on 0300 is the 0301 custom control.
 "Preview Data and Preview Files share the delivered 0301 custom-control body.
 "Switch only the data projection by TS_PREVIEW-ACTIVETAB; no alternate
 "Preview Files dynpro is used by the active 0300 flow.
  IF ts_preview-activetab = 'TAB_FILES' OR ts_preview-activetab = 'TAB_FILE'.
    ts_preview-activetab = 'TAB_FILES'.
  ELSE.
    ts_preview-activetab = 'TAB_PREVIEW'.
  ENDIF.
ENDMODULE.

FORM project_files_to_0301.
  DATA: ls_file TYPE ty_files_disp,
        ls_prev TYPE ty_preview_disp,
        lv_source_774 TYPE char40,
        lv_time_774   TYPE char19.

  REFRESH gt_preview_data.

  LOOP AT gt_files_preview INTO ls_file.
    CLEAR: ls_prev, lv_source_774, lv_time_774.
    ls_prev-batch_key  = ls_file-batch_key.
    ls_prev-file_title = ls_file-file_title.
    ls_prev-sheet_name = ls_file-sheet_name.
    ls_prev-tx_code    = ls_file-tx_code.
    ls_prev-excel_row  = ls_file-rows_loaded.

 "source/time/owner are display fallbacks only. Newly imported
 "rows can already be in GT_FILES_PREVIEW before the persisted history
 "projection is rebuilt, so never leave the friendly columns blank.
    lv_source_774 = ls_file-source_text.
    IF lv_source_774 IS INITIAL.
      CASE ls_file-channel.
        WHEN 'LOCAL' OR 'LOCAL_INGESTION'. lv_source_774 = 'My Computer'.
        WHEN 'GDRIVE' OR 'GDRIVE_INGESTION'. lv_source_774 = 'Google Drive'.
        WHEN 'EMAIL' OR 'EMAIL_INGESTION'. lv_source_774 = 'Email'.
        WHEN 'GMAIL' OR 'GMAIL_FORM'. lv_source_774 = 'Gmail'.
        WHEN 'REST' OR 'REST_INGESTION'. lv_source_774 = 'API'.
        WHEN OTHERS. lv_source_774 = ls_file-channel.
      ENDCASE.
    ENDIF.
    ls_prev-business_key = lv_source_774.

    lv_time_774 = ls_file-processed_on.
    IF lv_time_774 IS INITIAL AND ls_file-upload_date IS NOT INITIAL.
      lv_time_774 = |{ ls_file-upload_date+6(2) }.{ ls_file-upload_date+4(2) }.{ ls_file-upload_date+0(4) } { ls_file-upload_time+0(2) }:{ ls_file-upload_time+2(2) }:{ ls_file-upload_time+4(2) }|.
    ENDIF.
    ls_prev-col01 = lv_time_774.
    ls_prev-col02 = ls_file-owner.
    IF ls_prev-col02 IS INITIAL.
      ls_prev-col02 = ls_file-username.
    ENDIF.

 "Technical lifecycle/status/action fields intentionally stay out of the
 "visible Preview Files projection after .
    APPEND ls_prev TO gt_preview_data.
  ENDLOOP.
ENDFORM.

MODULE status_0301 OUTPUT.
 "use CL_GUI_ALV_GRID for deterministic row refresh on screen 0301.
  DATA: lv_reload_0301 TYPE i,
        lt_fcat_0301   TYPE lvc_t_fcat,
        ls_layout_0301 TYPE lvc_s_layo,
        ls_stable_0301 TYPE lvc_s_stbl,
        lv_title_0301  TYPE lvc_title,
        lv_file_0301   TYPE char80,
        lv_tx_0301     TYPE char20,
        lv_docs_0301   TYPE i,
        lv_rec_txt_0301 TYPE char24,
        lv_doc_txt_0301 TYPE char24.
  DATA lt_doc_keys_0301 TYPE SORTED TABLE OF char40 WITH UNIQUE KEY table_line.

  IF ts_preview-activetab = 'TAB_FILES'.
    "Preview Files is shared DB history, not a session-local cache. Another
    "SAP GUI/user may have committed a new upload since this screen was last
    "rendered. Re-read ZBDC_FILE_LG_BUP on every normal PBO roundtrip so
    "My Uploads / All Uploads never reuse a stale GT_FILES_PREVIEW snapshot.
    PERFORM prepare_preview_file.
    PERFORM project_files_to_0301.
  ELSE.
 "a parser/contract error owns the status message. Do not reload an
 "empty just-created batch in PBO, because that replaced the real cause
 "(for example TEMPLATE_SCHEMA_MISMATCH) with 'no staging rows'.
    IF gt_staging IS INITIAL
       AND gv_current_batch_prefix IS NOT INITIAL
       AND gv_ingest_error_msg IS INITIAL.
      PERFORM load_staging_by_batch
        USING    gv_current_batch_prefix
        CHANGING lv_reload_0301.
    ENDIF.
 "Restore the exact frozen session contract BEFORE reconstructing Preview
 "Data. Otherwise a history row can be rebuilt with the profile/version left
 "behind by a previous upload (for example FI01 rows under ME21N mapping).
    IF gt_staging IS NOT INITIAL.
      PERFORM apply_first_staging_ctx.
      PERFORM build_preview_rows.
    ELSE.
      REFRESH gt_preview_data.
    ENDIF.
  ENDIF.

 "concise user-facing titles provide the file/session context that
 "used to be repeated as technical columns on every row.
  CLEAR: lv_title_0301, lv_file_0301, lv_tx_0301, lv_docs_0301.
  REFRESH lt_doc_keys_0301.
  IF ts_preview-activetab = 'TAB_FILES'.
    IF gv_file_scope = gc_file_scope_all.
      lv_title_0301 = |Preview Files - All Uploads ({ lines( gt_preview_data ) })|.
    ELSE.
      lv_title_0301 = |Preview Files - My Uploads ({ lines( gt_preview_data ) })|.
    ENDIF.
  ELSE.
    LOOP AT gt_preview_data INTO DATA(ls_title_0301).
      IF lv_file_0301 IS INITIAL AND ls_title_0301-file_title IS NOT INITIAL.
        lv_file_0301 = ls_title_0301-file_title.
      ENDIF.
      IF lv_tx_0301 IS INITIAL AND ls_title_0301-tx_code IS NOT INITIAL.
        lv_tx_0301 = ls_title_0301-tx_code.
      ENDIF.
      IF ls_title_0301-business_key IS NOT INITIAL.
        INSERT ls_title_0301-business_key INTO TABLE lt_doc_keys_0301.
      ENDIF.
    ENDLOOP.
    lv_docs_0301 = lines( lt_doc_keys_0301 ).
    IF lv_file_0301 IS INITIAL.
      lv_file_0301 = 'No file selected'.
    ENDIF.
    IF lv_tx_0301 IS INITIAL.
      lv_tx_0301 = p_transaction.
    ENDIF.
    lv_rec_txt_0301 = |{ lines( gt_preview_data ) } records|.
    lv_doc_txt_0301 = |{ lv_docs_0301 } groups|.

 "the full file name is already visible in File Path / Preview
 "Files. Keep the preview title short enough to fit the SAP GUI pane.
    IF lv_file_0301 = 'No file selected'.
      lv_title_0301 = 'Preview Data - No file selected'.
    ELSEIF lv_tx_0301 IS NOT INITIAL.
      CONCATENATE 'Preview Data -' lv_tx_0301
        INTO lv_title_0301 SEPARATED BY space.
    ELSE.
      lv_title_0301 = 'Preview Data - Selected file'.
    ENDIF.
    CONCATENATE lv_title_0301 lv_rec_txt_0301 lv_doc_txt_0301
      INTO lv_title_0301 SEPARATED BY ' | '.
  ENDIF.

  PERFORM build_fcat_0301 CHANGING lt_fcat_0301.

  IF go_container_0301 IS INITIAL.
    CREATE OBJECT go_container_0301
      EXPORTING container_name = 'CC_PREVIEW_CONTAINER'.
  ENDIF.

  IF go_alv_0301 IS INITIAL.
    CREATE OBJECT go_alv_0301
      EXPORTING i_parent = go_container_0301.

    IF g_0301_grid_events IS INITIAL.
      CREATE OBJECT g_0301_grid_events.
    ENDIF.
    SET HANDLER g_0301_grid_events->on_0301_toolbar FOR go_alv_0301.
    SET HANDLER g_0301_grid_events->on_0301_user_command FOR go_alv_0301.
    SET HANDLER g_0301_grid_events->on_0301_double_click FOR go_alv_0301.
    SET HANDLER g_0301_grid_events->on_0301_hotspot_click FOR go_alv_0301.

    ls_layout_0301-zebra      = abap_true.
    ls_layout_0301-cwidth_opt = abap_true.
    ls_layout_0301-sel_mode   = 'A'.
    ls_layout_0301-grid_title = lv_title_0301.

    CALL METHOD go_alv_0301->set_table_for_first_display
      EXPORTING
        is_layout       = ls_layout_0301
      CHANGING
        it_outtab       = gt_preview_data
        it_fieldcatalog = lt_fcat_0301.
    CALL METHOD go_alv_0301->set_toolbar_interactive.
  ELSE.
    CALL METHOD go_alv_0301->set_frontend_fieldcatalog
      EXPORTING
        it_fieldcatalog = lt_fcat_0301.

    ls_layout_0301-zebra      = abap_true.
    ls_layout_0301-cwidth_opt = abap_true.
    ls_layout_0301-sel_mode   = 'A'.
    ls_layout_0301-grid_title = lv_title_0301.
    CALL METHOD go_alv_0301->set_frontend_layout
      EXPORTING is_layout = ls_layout_0301.

    ls_stable_0301-row = abap_true.
    ls_stable_0301-col = abap_true.
    CALL METHOD go_alv_0301->refresh_table_display
      EXPORTING
        is_stable      = ls_stable_0301
        i_soft_refresh = abap_false.
    CALL METHOD go_alv_0301->set_toolbar_interactive.
  ENDIF.
  CALL METHOD cl_gui_cfw=>flush
    EXCEPTIONS
      cntl_system_error = 1
      cntl_error        = 2
      OTHERS            = 3.
ENDMODULE.


MODULE status_0400 OUTPUT.
  DATA lt_excl_0400 TYPE STANDARD TABLE OF sy-ucomm WITH DEFAULT KEY.

 "STATUS_0400 physically contains only the current cockpit actions:
 "EXAL Run All, EXSL Run Selected, GT06 Result Dashboard, GT05 Execution Monitor.
 "Only those real actions are context-hidden while the detail editor owns 0400.
  IF gv_0400_view = gc_view_detail.
    gv_0400_edit_mode = 'X'.
    APPEND 'EXAL' TO lt_excl_0400.
    APPEND 'EXSL' TO lt_excl_0400.
    APPEND 'GT05' TO lt_excl_0400.
  ELSE.
    CLEAR gv_0400_edit_mode.
  ENDIF.

 "every 0400 roundtrip starts with an empty command buffer.
 "A checkbox edit must never reuse EXSL/RUN_SELECTED from an earlier PAI.
  CLEAR: ok_code, save_ok, sy-ucomm.

 "safety net: mode A uses CL_GUI_CONTAINER=>SCREEN0, which belongs to
 "the whole SAP GUI client area rather than only dynpro 0500. If navigation
 "returns to 0400 by any path, remove the 0500 child control before drawing
 "the staging cockpit so its toolbar cannot remain over this screen.
  IF gv_0500_active = abap_true
     OR go_grid_0500 IS BOUND
     OR go_dock_0500 IS BOUND.
    PERFORM free_0500_queue.
  ENDIF.

  IF lt_excl_0400 IS INITIAL.
    SET PF-STATUS 'STATUS_0400'.
  ELSE.
    SET PF-STATUS 'STATUS_0400' EXCLUDING lt_excl_0400.
  ENDIF.
  SET TITLEBAR  'TITLE_0400'.

 "Session ID is a display/filter aid, never a mandatory dynpro input.
 "This keeps BACK/EXIT usable when 0400 is intentionally opened empty.
  LOOP AT SCREEN.
    screen-required = '0'.
    IF screen-name = 'TXTP_SESSION_ID' OR
       screen-name = 'TXTP_SESS'.
      screen-input = '0'.
    ENDIF.
    MODIFY SCREEN.
  ENDLOOP.

 "0400 renders one exact session selected by the preceding command.
 "PBO never elects a session from a dashboard row, execution cache, MAX,
 "or another globally available buffer.
  DATA: lv_scope_session_0400 TYPE zbdc_staging_bup-session_id,
        lv_loaded_session_0400 TYPE zbdc_staging_bup-session_id,
        lv_scope_batch_0400   TYPE zbdc_staging_bup-session_id,
        lv_need_reload_0400   TYPE abap_bool,
        lv_ctx_ok_0400        TYPE abap_bool,
        lv_ctx_msg_0400       TYPE string.

  IF gv_0400_context_locked = abap_true.
    CLEAR: lv_ctx_ok_0400, lv_ctx_msg_0400.
    PERFORM repair_0400_context
      CHANGING lv_ctx_ok_0400 lv_ctx_msg_0400.
    IF lv_ctx_ok_0400 <> abap_true AND lv_ctx_msg_0400 IS NOT INITIAL.
      PERFORM userize_ui_message USING lv_ctx_msg_0400 CHANGING gv_ui_message.
      MESSAGE gv_ui_message TYPE 'S' DISPLAY LIKE 'E'.
    ENDIF.
  ENDIF.

  IF gv_0400_context_locked = abap_true
     AND gv_0400_context_sid IS NOT INITIAL.
    lv_scope_session_0400 = gv_0400_context_sid.
  ELSE.
    lv_scope_session_0400 = txtp_session_id.
  ENDIF.
  CONDENSE lv_scope_session_0400.
  IF lv_scope_session_0400 IS INITIAL
     AND gv_0400_context_locked <> abap_true.
    lv_scope_session_0400 = txtp_sess.
    CONDENSE lv_scope_session_0400.
  ENDIF.

 "A buffer created by the immediately preceding command may establish the
 "context only when the screen has no context yet. It never overrides an
 "already selected session.
  READ TABLE gt_staging INTO DATA(ls_ctx_0400) INDEX 1.
  IF sy-subrc = 0.
    lv_loaded_session_0400 = ls_ctx_0400-session_id.
    IF gv_0400_context_locked = abap_true
       AND gv_0400_context_sid IS NOT INITIAL.
      READ TABLE gt_staging
        WITH KEY session_id = gv_0400_context_sid
        TRANSPORTING NO FIELDS.
      IF sy-subrc = 0.
        lv_loaded_session_0400 = gv_0400_context_sid.
      ENDIF.
    ELSEIF lv_scope_session_0400 IS INITIAL.
      lv_scope_session_0400 = lv_loaded_session_0400.
    ENDIF.
  ENDIF.

  IF lv_scope_session_0400 IS NOT INITIAL.
    txtp_session_id = lv_scope_session_0400.
    txtp_sess       = lv_scope_session_0400.

    IF lv_loaded_session_0400 IS INITIAL OR
       lv_loaded_session_0400 <> lv_scope_session_0400.
      lv_need_reload_0400 = abap_true.
    ENDIF.

    IF lv_need_reload_0400 = abap_true.
      DATA lv_reload_count_0400 TYPE i.

      REFRESH: gt_staging, gt_staging_alv, gt_exec_disp.

 "An upload command may intentionally open several sessions that share
 "one batch prefix. Reload that batch only when the current screen
 "context proves it contains more than one session. A dashboard-selected
 "single session must remain an exact-session scope.
     "V17.9.3.4 scope stability: an old GT_CURRENT_SESSIONS list must never
     "authorize a batch reload for a newly selected exact session. Prove that
     "the visible session itself belongs to the current batch before widening.
      CLEAR lv_scope_batch_0400.
      PERFORM batch_prefix_from_sid
        USING    lv_scope_session_0400
        CHANGING lv_scope_batch_0400.

      IF gv_0400_batch_scope = abap_true
         AND gv_current_batch_prefix IS NOT INITIAL
         AND lines( gt_current_sessions ) > 1
         AND lv_scope_batch_0400 = gv_current_batch_prefix.
        PERFORM load_staging_by_batch
          USING    gv_current_batch_prefix
          CHANGING lv_reload_count_0400.
      ELSE.
        "Exact Session ID is authoritative unless this screen was explicitly
        "opened as a multi-session upload batch. Old GV_CURRENT_BATCH_PREFIX
        "state is never allowed to widen a newly selected session.
        PERFORM load_staging_by_session
          USING    lv_scope_session_0400
          CHANGING lv_reload_count_0400.
      ENDIF.

      IF lv_reload_count_0400 > 0 AND gt_staging IS NOT INITIAL.
        IF gv_0400_context_locked = abap_true
           AND gv_0400_context_sid IS NOT INITIAL.
          lv_scope_session_0400 = gv_0400_context_sid.
          txtp_session_id       = gv_0400_context_sid.
          txtp_sess             = gv_0400_context_sid.
        ELSE.
          READ TABLE gt_staging INTO DATA(ls_reload_ctx_0400) INDEX 1.
          IF sy-subrc = 0.
            lv_scope_session_0400 = ls_reload_ctx_0400-session_id.
            txtp_session_id       = lv_scope_session_0400.
            txtp_sess             = lv_scope_session_0400.
          ENDIF.
        ENDIF.
        PERFORM prepare_alv_0400.
      ENDIF.
    ENDIF.
  ENDIF.

 "BUP V4: learn from reference project style: Header summary + Body ALV.
 "The visible screen is a real execution cockpit; raw staging opens only in EDIT mode.
  DATA: lt_fcat   TYPE lvc_t_fcat,
        ls_layo   TYPE lvc_s_layo,
        ls_stable TYPE lvc_s_stbl.

  IF gv_0400_view IS INITIAL.
    gv_0400_view = gc_view_cockpit.
  ENDIF.

 "Keep scope/counters consistent after reload.
  IF gt_staging IS NOT INITIAL.
    PERFORM sync_0400_scope.
  ENDIF.

  IF gt_staging_alv IS INITIAL AND gt_staging IS NOT INITIAL.
    PERFORM prepare_alv_0400.
  ENDIF.

  IF gv_0400_view = gc_view_cockpit.
    PERFORM sync_visible_sm35.
    PERFORM build_exec_cockpit.
    PERFORM update_0400_counters.
  ELSE.
    IF gv_0400_context_locked = abap_true
       AND gv_0400_context_sid IS NOT INITIAL.
      txtp_session_id = gv_0400_context_sid.
      txtp_sess       = gv_0400_context_sid.
    ELSE.
      READ TABLE gt_staging INTO DATA(ls_first_0400) INDEX 1.
      IF sy-subrc = 0.
        txtp_session_id = ls_first_0400-session_id.
        txtp_sess       = ls_first_0400-session_id.
      ENDIF.
    ENDIF.
  ENDIF.

  CLEAR ls_layo.
  ls_layo-ctab_fname = 'CELL_COLORS'.
 "DESIGN ONLY: cockpit uses deliberate widths so long evidence/action
 "text cannot stretch the ALV into a horizontal-scroll-heavy layout.
  IF gv_0400_view = gc_view_cockpit.
    ls_layo-cwidth_opt = space.
    ls_layo-stylefname = 'CELL_STYLES'.
  ELSE.
    ls_layo-cwidth_opt = 'X'.
    CLEAR ls_layo-stylefname.
  ENDIF.
  ls_layo-sel_mode   = 'A'.
  ls_layo-zebra      = 'X'.
  ls_stable-row      = 'X'.
  ls_stable-col      = 'X'.

  "Logical-view binding. Edit Staging and Cockpit use different ALV toolbars
  "and different outtabs. Rebuild the complete 0400 custom-control tree in
  "PBO whenever the logical view changes. This removes any orphaned frontend
  "grid left by an ALV callback while keeping PAI free of control destruction.
  IF gv_0400_render_view IS NOT INITIAL
     AND gv_0400_render_view <> gv_0400_view.
    PERFORM free_0400_grid.
    CALL METHOD cl_gui_cfw=>flush EXCEPTIONS OTHERS = 1.
  ENDIF.

  "Frontend/backend scope binding. A CL_GUI_ALV_GRID created for Session A
  "must never survive when 0400 is rebound to Session B. Merely refreshing
  "the table can leave the custom control showing the previous session after
  "nested CALL SCREEN / CALL TRANSACTION roundtrips. Recreate the whole 0400
  "control tree on an exact-session switch.
  IF gv_0400_batch_scope <> abap_true
     AND lv_scope_session_0400 IS NOT INITIAL
     AND gv_0400_render_sid IS NOT INITIAL
     AND gv_0400_render_sid <> lv_scope_session_0400.
    PERFORM free_0400_grid.
    CALL METHOD cl_gui_cfw=>flush EXCEPTIONS OTHERS = 1.
    CLEAR gv_0400_render_sid.
  ENDIF.

  IF go_container_0400 IS INITIAL.
    CREATE OBJECT go_container_0400
      EXPORTING container_name = 'CC_STAGING_CONTAINER'.

    CREATE OBJECT go_split_0400
      EXPORTING
        parent  = go_container_0400
        rows    = 2
        columns = 1.

    go_cont_head_0400 = go_split_0400->get_container( row = 1 column = 1 ).
    go_cont_body_0400 = go_split_0400->get_container( row = 2 column = 1 ).

 "DESIGN ONLY: three visible header lines (title + two summaries).
 "Container/control lifecycle remains unchanged.
    CALL METHOD go_split_0400->set_row_height
      EXPORTING
        id     = 1
        height = 18.
  ENDIF.

  PERFORM render_0400_header.

  IF gv_0400_batch_scope = abap_true.
    CLEAR gv_0400_render_sid.
  ELSEIF gv_0400_context_locked = abap_true
     AND gv_0400_context_sid IS NOT INITIAL.
    gv_0400_render_sid = gv_0400_context_sid.
  ELSE.
    gv_0400_render_sid = txtp_session_id.
  ENDIF.
  gv_0400_render_view = gv_0400_view.

  IF gv_0400_view = gc_view_cockpit.

 "State-machine invariant: cockpit view owns exactly one body grid.
 "Always destroy a leftover detail grid even when an old cockpit reference
 "is still bound. This closes the split-brain state seen after 0500 BACK.
    IF go_staging_grid IS BOUND.
      CALL METHOD go_staging_grid->free
        EXCEPTIONS
          OTHERS = 1.
      CLEAR go_staging_grid.
      CALL METHOD cl_gui_cfw=>flush
        EXCEPTIONS
          OTHERS = 1.
    ENDIF.

    IF go_exec_grid IS NOT BOUND.

      CREATE OBJECT go_exec_grid
        EXPORTING i_parent = go_cont_body_0400.

      PERFORM build_exec_fieldcat CHANGING lt_fcat.

 "Run Selected uses native ALV row selection only.
 "The old SELECTED checkbox field remains technical/hidden for compatibility.
      CALL METHOD go_exec_grid->set_table_for_first_display
        EXPORTING
          is_layout       = ls_layo
        CHANGING
          it_outtab       = gt_exec_disp
          it_fieldcatalog = lt_fcat.

      CREATE OBJECT g_0400_grid_events.
      g_0400_grid_events->configure_0400_grid( go_exec_grid ).
      SET HANDLER g_0400_grid_events->on_0400_toolbar FOR go_exec_grid.
      SET HANDLER g_0400_grid_events->on_0400_user_command FOR go_exec_grid.
      SET HANDLER g_0400_grid_events->on_0400_hotspot_click FOR go_exec_grid.
      CALL METHOD go_exec_grid->set_toolbar_interactive.

      CALL METHOD go_exec_grid->register_edit_event
        EXPORTING i_event_id = cl_gui_alv_grid=>mc_evt_modified.
      CALL METHOD go_exec_grid->register_edit_event
        EXPORTING i_event_id = cl_gui_alv_grid=>mc_evt_enter.

 "Cockpit remains read-only; row selectors carry Run Selected intent.
      CALL METHOD go_exec_grid->set_ready_for_input
        EXPORTING i_ready_for_input = 0.

    ELSE.

      CALL METHOD go_exec_grid->set_ready_for_input
        EXPORTING i_ready_for_input = 0.

      CALL METHOD go_exec_grid->refresh_table_display
        EXPORTING is_stable = ls_stable.

    ENDIF.

  ELSE.

 "State-machine invariant in the opposite direction: detail edit owns
 "exactly one body grid. Remove every cockpit grid reference first.
    IF go_exec_grid IS BOUND.
      CALL METHOD go_exec_grid->free
        EXCEPTIONS
          OTHERS = 1.
      CLEAR go_exec_grid.
      CALL METHOD cl_gui_cfw=>flush
        EXCEPTIONS
          OTHERS = 1.
    ENDIF.

    IF go_staging_grid IS NOT BOUND.

      CREATE OBJECT go_staging_grid
        EXPORTING i_parent = go_cont_body_0400.

      IF g_0400_grid_events IS INITIAL.
        CREATE OBJECT g_0400_grid_events.
      ENDIF.
      g_0400_grid_events->configure_0400_grid( go_staging_grid ).
      SET HANDLER g_0400_grid_events->on_0400_toolbar FOR go_staging_grid.
      SET HANDLER g_0400_grid_events->on_0400_user_command FOR go_staging_grid.
      CALL METHOD go_staging_grid->set_toolbar_interactive.

      CALL METHOD go_staging_grid->register_edit_event
        EXPORTING i_event_id = cl_gui_alv_grid=>mc_evt_enter.

      CALL METHOD go_staging_grid->register_edit_event
        EXPORTING i_event_id = cl_gui_alv_grid=>mc_evt_modified.

      PERFORM build_detail_fieldcat CHANGING lt_fcat.

      CALL METHOD go_staging_grid->set_table_for_first_display
        EXPORTING
          is_layout       = ls_layo
        CHANGING
          it_outtab       = gt_staging_alv
          it_fieldcatalog = lt_fcat.

      go_staging_grid->set_ready_for_input( 1 ).

    ELSE.

      go_staging_grid->set_ready_for_input( 1 ).

      CALL METHOD go_staging_grid->refresh_table_display
        EXPORTING is_stable = ls_stable.

    ENDIF.

  ENDIF.

ENDMODULE.

*&=====================================================================*
*& V7 PRO - PBO MODULES FOR ACTIVE SCREEN LIFECYCLE
*&=====================================================================*

MODULE status_0350 OUTPUT.

 "0350 is a standalone Mapping Configuration screen.
 "0300 stays as Upload Center; 0350 handles only mapping profile maintenance.
  DATA: lv_ro_0350      TYPE abap_bool,
        lv_msg_0350     TYPE string,
        lv_ctx_ok_0350  TYPE abap_bool,
        lv_ctx_msg_0350 TYPE string.

  SET TITLEBAR 'TITLE_0350'.

 "FIX:
 "Mapping Config was falling back to old gv_profile_ver, e.g. v10.
 "Resolve only an exact or unambiguous registered Mapping context.
 "never jumps to a global/latest version and PBO never creates DB rows.

  PERFORM resolve_exact_map_ctx
    CHANGING lv_ctx_ok_0350 lv_ctx_msg_0350.

 "After the exact resolver, align both TCODE holders.
  IF p_rec_tcode IS INITIAL AND p_transaction IS NOT INITIAL.
    p_rec_tcode = p_transaction.
  ELSEIF p_transaction IS INITIAL AND p_rec_tcode IS NOT INITIAL.
    p_transaction = p_rec_tcode.
  ENDIF.

 "Do NOT do this anymore:
 "* IF gv_profile_ver IS INITIAL.
 "* gv_profile_ver = '0001'.
 "* ENDIF.

 "PBO is display-only. Never INSERT/COMMIT a Profile merely because
 "0350 was opened. Exact Profile/Version creation belongs to onboarding.

  PERFORM get_mapping_ui_state
    CHANGING lv_ro_0350 lv_msg_0350.

  IF lv_ctx_ok_0350 <> abap_true.
    lv_ro_0350 = abap_true.
    IF lv_msg_0350 IS INITIAL.
      lv_msg_0350 = lv_ctx_msg_0350.
    ENDIF.
  ENDIF.

 "STATUS_0350 is maintained physically with only Generate Template.
 "Retired Refresh/Activate actions are not hidden in source.
  SET PF-STATUS 'STATUS_0350'.

  PERFORM display_mapping_screen.

 "Do not emit Candidate-Review guidance on every PBO.
 "That warning used to overwrite the real PAI error/success message after
 "Generate Template, making a failed command look like a no-op. Only surface
 "an actual unresolved Mapping context here; action diagnostics remain owned
 "by USER_COMMAND_0350 / DOWNLOAD_CURR_PROF_TMPL.
 "Start Recording Candidate Review intentionally has no official
 "exact runtime tuple until Generate Template promotes it. Do not repaint
 "the generic Candidate guidance after PAI, otherwise it overwrites the real
 "Generate Template error/success message and makes the button look inert.
  IF lv_ctx_ok_0350 <> abap_true
     AND lv_msg_0350 IS NOT INITIAL.
 "O01 must not depend on M2_MAP-private candidate state.
 "GV_Z240_MAP_LOCKED is declared in M2_MAP, so referencing it from O01
 "breaks include-level syntax checks depending on include order. Suppress
 "only the known Candidate-Review guidance text; all other real context
 "errors remain visible, while Generate Template PAI messages are not
 "overwritten by the following PBO repaint.
    IF lv_msg_0350 NP 'Auto Template Mapping is ready*'.
      PERFORM userize_ui_message USING lv_msg_0350 CHANGING gv_ui_message.
      MESSAGE gv_ui_message TYPE 'S' DISPLAY LIKE 'W'.
    ENDIF.
  ENDIF.

ENDMODULE.

MODULE status_0500 OUTPUT.

 "STATUS_0500 physically keeps only Dashboard on the PF-status.
 "Execution/queue actions belong only to the state-aware ALV toolbar.

 "0500 is driven by ALV toolbar only.
 "For BDC mode A (All screens), SAP itself is the live progress UI,
 "so the static progress block is hidden and the queue is fixed larger.
  DATA lv_0500_mode TYPE c LENGTH 1.
  DATA lv_0500_upd  TYPE c LENGTH 1.
  DATA lv_0500_bsz  TYPE i.
  DATA lv_pbo_policy_ok_0500  TYPE abap_bool.
  DATA lv_pbo_policy_msg_0500 TYPE string.

  PERFORM get_runtime_options
    CHANGING lv_0500_mode lv_0500_upd lv_0500_bsz
             lv_pbo_policy_ok_0500 lv_pbo_policy_msg_0500.

  IF lv_pbo_policy_ok_0500 = abap_true.
    PERFORM check_runtime_policy
      CHANGING lv_pbo_policy_ok_0500 lv_pbo_policy_msg_0500.
  ENDIF.
  IF lv_pbo_policy_ok_0500 <> abap_true.
    PERFORM userize_ui_message USING lv_pbo_policy_msg_0500 CHANGING gv_ui_message.
    MESSAGE gv_ui_message TYPE 'S' DISPLAY LIKE 'E'.
  ENDIF.

  SET PF-STATUS 'STATUS_0500'.
  SET TITLEBAR  'TITLE_0500'.
  gv_0500_active = abap_true.
  PERFORM 0500_pbo_sync.
  PERFORM init_execution_monitor.
  PERFORM display_0500_queue.

 "Screen 0500 keeps only readonly progress fields. Any old option fields
 "from earlier prototypes are hidden/disabled so the logic is not confused
 "with BDC Mode A/E/N or Update Mode S/A from screen 0100.
  LOOP AT SCREEN.
    screen-required = '0'.

 "Old prototype options are permanently hidden. Engine selection is now
 "done by ALV actions: Run Batch Session and SM35 Monitor.
    IF screen-name = 'CHKP_STOP_ON_ERROR' OR
       screen-name = 'CHKP_BACKGROUND'.
      screen-active = '0'.
      screen-input  = '0'.
    ENDIF.

 "keep the 0500 progress block visible for A/E/N. In A mode the
 "active SAP transaction still owns the GUI while one document is being
 "processed, but the monitor is painted before the call and refreshed at
 "every real document-group boundary after control returns.

    MODIFY SCREEN.
  ENDLOOP.
ENDMODULE.

MODULE status_0560 OUTPUT.
  SET PF-STATUS 'STATUS_0560'.
  SET TITLEBAR  'TITLE_0560'.

  PERFORM prepare_0560_pbo.

  LOOP AT SCREEN.
    IF screen-name = 'P_BUS_GROUP' OR
       screen-name = 'P_FLD_NAME' OR
       screen-name = 'P_OLD_VAL' OR
       screen-name = 'P_NEW_VAL'.
      screen-required = '0'.
    ENDIF.

 "Business Group -> Field -> Old Value are listbox dependencies.
 "Old Value is never free-typed: even one existing value is shown as the
 "single selectable value; multiple existing values remain explicit choices.
    IF screen-name = 'P_BUS_GROUP' OR
       screen-name = 'P_FLD_NAME' OR
       screen-name = 'P_OLD_VAL'.
      screen-input = '1'.
    ENDIF.
    MODIFY SCREEN.
  ENDLOOP.
ENDMODULE.

MODULE status_0650 OUTPUT.

  "STATUS_0650 physically keeps only Analyze Error. Retired Copy/Export,
  "manual Refresh and Open SAP Object actions are removed from the status.
  SET PF-STATUS 'STATUS_0650'.
  SET TITLEBAR  'TITLE_0650'.

  "A no-change live tick performs no repaint at all; keep the user's current
  "scroll/selection exactly where it is.  Real changes still rebuild detail.
  IF gv_result_0650_skip_pbo = abap_true.
    CLEAR gv_result_0650_skip_pbo.
  ELSE.
    PERFORM display_result_detail.
  ENDIF.

  PERFORM start_result_timer_0650.
ENDMODULE.

MODULE status_0700 OUTPUT.

  "Screen 0700 is automatic diagnosis only. Retired manual Diagnose/Export,
  "Recording and Knowledge actions are removed from the source contract.
  SET PF-STATUS 'STATUS_0700'.
  SET TITLEBAR  'TITLE_0700'.

  "Load exact evidence first, then immediately produce one deterministic
  "diagnosis for the selected ERROR group.
  PERFORM display_ai_landing.
  PERFORM auto_diagnose_0700.
ENDMODULE.
MODULE status_0800 OUTPUT.

 "STATUS_0800 physically keeps Import Recording + Mapping Profile only.
 "Start Recording / My Import / All Import remain ALV toolbar actions.
  SET PF-STATUS 'STATUS_0800'.
  SET TITLEBAR  'TITLE_0800'.
  PERFORM display_script_editor.
ENDMODULE.
