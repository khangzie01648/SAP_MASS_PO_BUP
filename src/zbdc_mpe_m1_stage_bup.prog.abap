
*& Include ZBDC_MPE_M1_STAGE_BUP
*& Purpose Exact staging, session, file and duplicate context
*& no global-latest session selection

FORM start_ingest_batch.
  DATA: lv_demo_date_836 TYPE sy-datum,
        lv_demo_time_836 TYPE sy-uzeit.
  CLEAR: gv_current_batch_prefix, gv_ingest_batch_prefix,
         gv_forced_session_id, gv_current_batch_count.
  REFRESH gt_current_sessions.
 "compact batch prefix fits old CHAR20/CHAR22 SESSION_ID fields.
 "Example batch: B20260709201500; file sessions: B20260709201500_001.
  PERFORM get_demo_now CHANGING lv_demo_date_836 lv_demo_time_836.
  CONCATENATE 'B' lv_demo_date_836 lv_demo_time_836 INTO gv_ingest_batch_prefix.
  gv_current_batch_prefix = gv_ingest_batch_prefix.
ENDFORM.

FORM make_batch_session USING iv_index TYPE i
                            CHANGING cv_session_id TYPE zbdc_staging_bup-session_id.
  DATA lv_idx TYPE n LENGTH 3.
  IF gv_ingest_batch_prefix IS INITIAL.
    PERFORM start_ingest_batch.
  ENDIF.
  lv_idx = iv_index.
  CONCATENATE gv_ingest_batch_prefix '_' lv_idx INTO cv_session_id.
ENDFORM.

FORM register_current_session USING iv_session_id TYPE zbdc_staging_bup-session_id.
  DATA: lv_exists TYPE zbdc_staging_bup-session_id,
        lv_batch  TYPE zbdc_staging_bup-session_id.
  IF iv_session_id IS INITIAL.
    RETURN.
  ENDIF.
  READ TABLE gt_current_sessions INTO lv_exists WITH KEY table_line = iv_session_id.
  IF sy-subrc <> 0.
    APPEND iv_session_id TO gt_current_sessions.
  ENDIF.
  IF gv_current_batch_prefix IS INITIAL.
    PERFORM batch_prefix_from_sid USING iv_session_id CHANGING lv_batch.
    gv_current_batch_prefix = lv_batch.
  ENDIF.
ENDFORM.

FORM finish_ingest_batch.
  gv_current_batch_count = lines( gt_current_sessions ).
  IF gv_current_batch_prefix IS INITIAL AND gt_current_sessions IS NOT INITIAL.
    READ TABLE gt_current_sessions INTO DATA(lv_sid) INDEX 1.
    IF sy-subrc = 0.
      PERFORM batch_prefix_from_sid USING lv_sid CHANGING gv_current_batch_prefix.
    ENDIF.
  ENDIF.
ENDFORM.

FORM set_row_count_fields USING iv_rows TYPE i.
  WRITE iv_rows TO txtp_row_count LEFT-JUSTIFIED.
  txtp_row         = txtp_row_count.
  txtp_rows        = txtp_row_count.
  txtp_loaded      = txtp_row_count.
  txtp_loaded_rows = txtp_row_count.
  txtp_rows_loaded = txtp_row_count.
  txtgv_row_count  = txtp_row_count.
  txtgv_rows       = txtp_row_count.
  txtgv_loaded     = txtp_row_count.
  txtgv_total_rows = txtp_row_count.
  txtgv_tot_rows   = txtp_row_count.
ENDFORM.

FORM load_staging_by_batch
  USING    iv_batch_prefix TYPE zbdc_staging_bup-session_id
  CHANGING cv_count        TYPE i.

  DATA: lv_ok  TYPE abap_bool,
        lv_msg TYPE string.

  PERFORM load_exact_staging
    USING    space iv_batch_prefix space
    CHANGING cv_count lv_ok lv_msg.
  IF lv_ok <> abap_true.
    CLEAR cv_count.
    IF lv_msg IS NOT INITIAL.
      MESSAGE lv_msg TYPE 'S' DISPLAY LIKE 'W'.
    ENDIF.
  ENDIF.
ENDFORM.

*& File/Sheet Helpers - code only, no DDIC setup


FORM append_gmail_named_bup
  USING it_keys TYPE string_table
        it_vals TYPE string_table
        iv_sid  TYPE zbdc_staging_bup-session_id
        iv_idx  TYPE i.

  DATA: ls_stg TYPE zbdc_staging_bup,
        lt_map_all TYPE STANDARD TABLE OF zbdc_mapping_bup,
        ls_map_candidate TYPE zbdc_mapping_bup,
        ls_map_match TYPE zbdc_mapping_bup,
        lt_target_seen TYPE SORTED TABLE OF zbdc_mapping_bup-staging_field
                         WITH UNIQUE KEY table_line,
        lv_key TYPE string,
        lv_map_src TYPE string,
        lv_value TYPE string,
        lv_staged_check TYPE string,
        lv_col_index TYPE i,
        lv_match_count TYPE i.
  FIELD-SYMBOLS <lv_target> TYPE any.

  CLEAR gv_ingest_error_msg.

  IF iv_sid IS INITIAL.
    gv_ingest_error_msg = 'GMAIL_STAGING_CONTEXT_MISSING: session ID is empty.'.
    RETURN.
  ENDIF.

  IF lines( it_keys ) <> lines( it_vals ) OR it_keys IS INITIAL.
    gv_ingest_error_msg =
      |GMAIL_STAGING_SCHEMA_INVALID: keys={ lines( it_keys ) }, values={ lines( it_vals ) }.|.
    RETURN.
  ENDIF.

  SELECT * FROM zbdc_mapping_bup
    INTO TABLE @lt_map_all
    WHERE tcode        = @p_transaction
      AND profile_name = @txtp_profile_name
      AND profile_ver  = @gv_profile_ver.

  IF lt_map_all IS INITIAL.
    gv_ingest_error_msg =
      |GMAIL_MAPPING_UNAVAILABLE: no exact Mapping exists for { p_transaction }/{ txtp_profile_name } v{ gv_profile_ver }.|.
    RETURN.
  ENDIF.

  CLEAR ls_stg.
  ls_stg-session_id = iv_sid.
  ls_stg-row_index  = iv_idx.
  ls_stg-tcode      = p_transaction.
  ls_stg-status     = 'STAGED'.

  LOOP AT it_keys INTO lv_key.
    lv_col_index = sy-tabix.
    CLEAR: ls_map_match, lv_match_count, lv_value, lv_staged_check.

    LOOP AT lt_map_all INTO ls_map_candidate.
      lv_map_src = ls_map_candidate-source_column.
      TRANSLATE lv_map_src TO UPPER CASE.
      CONDENSE lv_map_src NO-GAPS.
      REPLACE ALL OCCURRENCES OF '*' IN lv_map_src WITH ''.
      REPLACE ALL OCCURRENCES OF '"' IN lv_map_src WITH ''.

      IF lv_map_src <> lv_key.
        CONTINUE.
      ENDIF.

      IF lv_match_count = 0.
        ls_map_match = ls_map_candidate.
        lv_match_count = 1.
      ELSEIF ls_map_candidate-staging_field = ls_map_match-staging_field
         AND ls_map_candidate-bdc_field     = ls_map_match-bdc_field.
        "Equivalent duplicate repository row; same exact runtime identity.
        CONTINUE.
      ELSE.
        lv_match_count = lv_match_count + 1.
      ENDIF.
    ENDLOOP.

    IF lv_match_count = 0.
      gv_ingest_error_msg =
        |GMAIL_MAPPING_SOURCE_MISSING: submitted source { lv_key } has no exact Mapping row for { p_transaction }/{ txtp_profile_name } v{ gv_profile_ver }.|.
      RETURN.
    ELSEIF lv_match_count > 1.
      gv_ingest_error_msg =
        |GMAIL_MAPPING_SOURCE_AMBIGUOUS: submitted source { lv_key } maps to more than one runtime field.|.
      RETURN.
    ENDIF.

    READ TABLE lt_target_seen
      WITH TABLE KEY table_line = ls_map_match-staging_field
      TRANSPORTING NO FIELDS.
    IF sy-subrc = 0.
      gv_ingest_error_msg =
        |GMAIL_MAPPING_TARGET_COLLISION: more than one source column targets { ls_map_match-staging_field }.|.
      RETURN.
    ENDIF.
    INSERT ls_map_match-staging_field INTO TABLE lt_target_seen.

    READ TABLE it_vals INTO lv_value INDEX lv_col_index.
    IF sy-subrc <> 0.
      gv_ingest_error_msg =
        |GMAIL_ROW_VALUE_MISSING: source { lv_key } has no aligned value at column { lv_col_index }.|.
      RETURN.
    ENDIF.

    UNASSIGN <lv_target>.
    ASSIGN COMPONENT ls_map_match-staging_field OF STRUCTURE ls_stg TO <lv_target>.
    IF sy-subrc <> 0 OR <lv_target> IS NOT ASSIGNED.
      gv_ingest_error_msg =
        |GMAIL_STAGING_BIND_INVALID: { lv_key } -> { ls_map_match-staging_field } does not exist in ZBDC_STAGING_BUP.|.
      RETURN.
    ENDIF.

    <lv_target> = lv_value.
    lv_staged_check = <lv_target>.
    IF lv_staged_check <> lv_value.
      gv_ingest_error_msg =
        |GMAIL_STAGING_VALUE_LOSS: { lv_key } could not round-trip through { ls_map_match-staging_field }.|.
      UNASSIGN <lv_target>.
      RETURN.
    ENDIF.
    UNASSIGN <lv_target>.

  ENDLOOP.

  ls_stg-record_key = ls_stg-field01.
  "Whole-submission actual-data proof rejects invalid blanks atomically.
  APPEND ls_stg TO gt_staging.
ENDFORM.

FORM update_session_summary USING iv_session_id TYPE zbdc_session_bup-session_id.

 "STRICT REAL V4 LIFECYCLE SUMMARY
 "Rebuild ZBDC_SESSION_BUP only from persisted evidence:
 "ZBDC_STAGING_BUP statuses, ZBDC_RESULT_BUP logs, and ingestion evidence.
 "No current-user/current-time fallback for old sessions.

  TYPES: BEGIN OF ty_sum_group,
           record_key   TYPE zbdc_staging_bup-record_key,
           status       TYPE char20,
           has_staging  TYPE abap_bool,
           result_set   TYPE abap_bool,
           result_attempt TYPE zbdc_result_bup-attempt_no,
         END OF ty_sum_group.

  DATA: ls_sess      TYPE zbdc_session_bup,
        lt_staging   TYPE STANDARD TABLE OF zbdc_staging_bup,
        lt_result    TYPE STANDARD TABLE OF zbdc_result_bup,
        lt_groups    TYPE HASHED TABLE OF ty_sum_group WITH UNIQUE KEY record_key,
        ls_group     TYPE ty_sum_group,
        lv_key       TYPE zbdc_staging_bup-record_key,
        lv_ready     TYPE i,
        lv_success   TYPE i,
        lv_error     TYPE i,
        lv_warning   TYPE i,
        lv_sm35      TYPE i,
        lv_processed TYPE i,
        lv_total     TYPE i,
        lv_first_ts  TYPE tzntstmps,
        lv_last_ts   TYPE tzntstmps,
        lv_msg       TYPE string,
        lv_user      TYPE string,
        lv_dummy     TYPE string,
        lv_off       TYPE i,
        ls_stg       TYPE zbdc_staging_bup,
        ls_res       TYPE zbdc_result_bup.

  FIELD-SYMBOLS <ls_group> TYPE ty_sum_group.

  IF iv_session_id IS INITIAL.
    RETURN.
  ENDIF.

  SELECT *
    FROM zbdc_staging_bup
    INTO TABLE @lt_staging
    WHERE session_id = @iv_session_id.

  SELECT *
    FROM zbdc_result_bup
    INTO TABLE @lt_result
    WHERE session_id = @iv_session_id.

  LOOP AT lt_staging INTO ls_stg.
    CLEAR lv_key.
    IF ls_stg-record_key IS NOT INITIAL.
      lv_key = ls_stg-record_key.
    ELSE.
      lv_key = ls_stg-row_index.
    ENDIF.
    IF lv_key IS INITIAL.
      lv_key = 'ROW'.
    ENDIF.

    READ TABLE lt_groups ASSIGNING <ls_group> WITH TABLE KEY record_key = lv_key.
    IF sy-subrc <> 0.
      CLEAR ls_group.
      ls_group-record_key = lv_key.
      ls_group-status     = 'READY'.
      INSERT ls_group INTO TABLE lt_groups ASSIGNING <ls_group>.
    ENDIF.

    IF <ls_group> IS ASSIGNED.
      <ls_group>-has_staging = abap_true.
      IF ls_stg-status = gc_st_error OR ls_stg-status = 'ERROR'.
        <ls_group>-status = 'ERROR'.
      ELSEIF ( ls_stg-status = gc_st_warning OR ls_stg-status = 'WARNING' )
         AND <ls_group>-status <> 'ERROR'.
        <ls_group>-status = 'WARNING'.
      ELSEIF ( ls_stg-status = gc_st_success OR ls_stg-status = 'SUCCESS' )
         AND <ls_group>-status <> 'ERROR'
         AND <ls_group>-status <> 'WARNING'.
        <ls_group>-status = 'SUCCESS'.
      ELSEIF ls_stg-status = gc_st_sm35q
         AND <ls_group>-status <> 'ERROR'
         AND <ls_group>-status <> 'WARNING'
         AND <ls_group>-status <> 'SUCCESS'.
        <ls_group>-status = gc_st_sm35q.
      ELSEIF ls_stg-status = gc_st_ready
          OR ls_stg-status = 'READY'
          OR ls_stg-status = 'UPLOADED'
          OR ls_stg-status = 'VALIDATED'.
        IF <ls_group>-status IS INITIAL.
          <ls_group>-status = 'READY'.
        ENDIF.
      ENDIF.
    ENDIF.
  ENDLOOP.

  "Current lifecycle is owned by current staging. Result rows are immutable
  "attempt history/evidence and must never let an old ERROR override a later
  "SUCCESS/READY staging state. For legacy result-only groups, consume only
  "the newest persisted lifecycle-bearing result row.
  SORT lt_result BY record_key row_index attempt_no DESCENDING
                    created_at DESCENDING step DESCENDING.

  LOOP AT lt_result INTO ls_res.
    IF ls_res-created_at IS NOT INITIAL.
      IF lv_first_ts IS INITIAL OR ls_res-created_at < lv_first_ts.
        lv_first_ts = ls_res-created_at.
      ENDIF.
      IF lv_last_ts IS INITIAL OR ls_res-created_at > lv_last_ts.
        lv_last_ts = ls_res-created_at.
      ENDIF.
    ENDIF.

    IF ls_res-record_key = '__SOURCE__'.
      CONTINUE.
    ENDIF.

    CLEAR lv_key.
    IF ls_res-record_key IS NOT INITIAL.
      lv_key = ls_res-record_key.
    ELSEIF ls_res-row_index IS NOT INITIAL.
      lv_key = ls_res-row_index.
    ELSE.
      CONTINUE.
    ENDIF.

    READ TABLE lt_groups ASSIGNING <ls_group> WITH TABLE KEY record_key = lv_key.
    IF sy-subrc <> 0.
      CLEAR ls_group.
      ls_group-record_key = lv_key.
      ls_group-status     = 'READY'.
      INSERT ls_group INTO TABLE lt_groups ASSIGNING <ls_group>.
    ENDIF.

    IF <ls_group> IS ASSIGNED.
      "If current staging exists, it is the lifecycle authority. Historical
      "attempt evidence remains in ZBDC_RESULT_BUP but cannot repaint the
      "group/session back to ERROR after a later successful retry.
      IF <ls_group>-has_staging = abap_true.
        CONTINUE.
      ENDIF.

      "Legacy/result-only fallback: lock to the newest persisted attempt for
      "this group. Never fall back to an older ERROR merely because the newest
      "attempt currently has only informational/queue evidence.
      IF <ls_group>-result_attempt IS INITIAL.
        <ls_group>-result_attempt = ls_res-attempt_no.
      ELSEIF ls_res-attempt_no <> <ls_group>-result_attempt.
        CONTINUE.
      ENDIF.

      IF <ls_group>-result_set = abap_true.
        CONTINUE.
      ENDIF.

      IF ls_res-exec_status = gc_st_success OR
         ls_res-exec_status = 'SUCCESS'.
        <ls_group>-status = 'SUCCESS'.
        <ls_group>-result_set = abap_true.
      ELSEIF ls_res-exec_status = 'ERROR' OR
             ls_res-msg_type = 'E' OR
             ls_res-msg_type = 'A' OR
             ls_res-msg_type = 'X'.
        <ls_group>-status = 'ERROR'.
        <ls_group>-result_set = abap_true.
      ELSEIF ls_res-exec_status = 'WARNING' OR
             ls_res-msg_type = 'W'.
        <ls_group>-status = 'WARNING'.
        <ls_group>-result_set = abap_true.
      ELSEIF ls_res-exec_status = gc_st_sm35q OR
             ls_res-exec_status = 'SM35QUEUE' OR
             ls_res-exec_status = 'QUEUED_SM35' OR
             ls_res-exec_status = 'SM35RUN'.
        <ls_group>-status = gc_st_sm35q.
        <ls_group>-result_set = abap_true.
      ENDIF.
    ENDIF.
  ENDLOOP.

  LOOP AT lt_groups INTO ls_group.
    CASE ls_group-status.
      WHEN 'SUCCESS'.
        lv_success = lv_success + 1.
      WHEN 'WARNING'.
        lv_warning = lv_warning + 1.
      WHEN 'ERROR'.
        lv_error = lv_error + 1.
      WHEN gc_st_sm35q.
        lv_sm35 = lv_sm35 + 1.
      WHEN OTHERS.
        lv_ready = lv_ready + 1.
    ENDCASE.
  ENDLOOP.

  lv_total     = lines( lt_groups ).
  lv_processed = lv_success + lv_error + lv_warning + lv_sm35.

  CLEAR ls_sess.
  SELECT SINGLE *
    FROM zbdc_session_bup
    INTO @ls_sess
    WHERE session_id = @iv_session_id.

  IF sy-subrc <> 0.
    CLEAR ls_sess.
    ls_sess-session_id = iv_session_id.
  ENDIF.

  IF ls_sess-start_time IS INITIAL AND lv_first_ts IS NOT INITIAL.
    ls_sess-start_time = lv_first_ts.
  ENDIF.

  IF ls_sess-created_by IS INITIAL OR ls_sess-created_by = 'UNKNOWN'.
    LOOP AT lt_result INTO ls_res WHERE record_key = '__SOURCE__'.
      lv_msg = ls_res-message.
      FIND 'USER=' IN lv_msg MATCH OFFSET lv_off.
      IF sy-subrc = 0.
        lv_off = lv_off + 5.
        lv_user = lv_msg.
        SHIFT lv_user BY lv_off PLACES LEFT.
        SPLIT lv_user AT ';' INTO lv_user lv_dummy.
        CONDENSE lv_user NO-GAPS.
        IF lv_user IS NOT INITIAL.
          ls_sess-created_by = lv_user.
          EXIT.
        ENDIF.
      ENDIF.
    ENDLOOP.
  ENDIF.

  IF ls_sess-created_by IS INITIAL.
    ls_sess-created_by = 'UNKNOWN'.
  ENDIF.

  IF lv_processed > 0 AND lv_last_ts IS NOT INITIAL.
    ls_sess-end_time = lv_last_ts.
  ENDIF.

  ls_sess-total_rec = lv_total.
  ls_sess-processed = lv_processed.
  ls_sess-success   = lv_success.
  ls_sess-error     = lv_error.
  ls_sess-warning   = lv_warning.

  IF lv_total = 0.
    ls_sess-status = 'NO_DATA'.
  ELSEIF lv_error > 0.
    ls_sess-status = 'ERROR'.
  ELSEIF lv_warning > 0.
    ls_sess-status = 'WARNING'.
  ELSEIF lv_success = lv_total.
    ls_sess-status = 'SUCCESS'.
  ELSEIF lv_sm35 = lv_total.
    ls_sess-status = 'SM35_QUEUED'.
  ELSEIF lv_sm35 > 0 AND ( lv_success > 0 OR lv_ready > 0 ).
    ls_sess-status = 'PARTIAL_SM35'.
  ELSEIF lv_ready > 0 AND lv_processed = 0.
    ls_sess-status = 'READY'.
  ELSEIF lv_ready > 0 AND lv_processed > 0.
    ls_sess-status = 'PARTIAL'.
  ELSE.
    ls_sess-status = 'READY'.
  ENDIF.

  MODIFY zbdc_session_bup FROM ls_sess.

ENDFORM.

*& upd_all_rt_sess_sum
*& Sync dashboard evidence after Upload / Validate / Execute / Resubmit.

FORM upd_all_rt_sess_sum.
  DATA: lt_sid TYPE SORTED TABLE OF zbdc_session_bup-session_id WITH UNIQUE KEY table_line,
        lv_sid TYPE zbdc_session_bup-session_id,
        ls_stg TYPE zbdc_staging_bup.

  LOOP AT gt_staging INTO ls_stg.
    IF ls_stg-session_id IS NOT INITIAL.
      INSERT ls_stg-session_id INTO TABLE lt_sid.
    ENDIF.
  ENDLOOP.

  LOOP AT lt_sid INTO lv_sid.
    PERFORM update_session_summary USING lv_sid.
  ENDLOOP.
ENDFORM.

*& 0300 UX helpers - Preview File/Data and upload summary

FORM save_preview_session
  USING    iv_session_id TYPE zbdc_session_bup-session_id
  CHANGING cv_ok         TYPE abap_bool
           cv_message    TYPE string.

  DATA: ls_session    TYPE zbdc_session_bup,
        lv_ts         TYPE tzntstmps,
        lv_has_owner  TYPE abap_bool.

  CLEAR: cv_ok, cv_message.
  IF iv_session_id IS INITIAL.
    cv_message = 'Session ID is missing; preview context cannot be saved.'.
    RETURN.
  ENDIF.

  CLEAR ls_session.
  SELECT SINGLE *
    FROM zbdc_session_bup
    INTO @ls_session
    WHERE session_id = @iv_session_id.

  IF sy-subrc <> 0.
    CLEAR ls_session.
    ls_session-session_id = iv_session_id.
    GET TIME STAMP FIELD lv_ts.
    ls_session-start_time = lv_ts.
    ls_session-created_by = sy-uname.
  ENDIF.

  lv_has_owner = abap_false.
  IF ls_session-tcode IS NOT INITIAL OR
     ls_session-profile_name IS NOT INITIAL OR
     ls_session-profile_ver IS NOT INITIAL.
    lv_has_owner = abap_true.
  ENDIF.

  IF lv_has_owner = abap_true.
    IF ls_session-tcode        <> p_transaction OR
       ls_session-profile_name <> txtp_profile_name OR
       ls_session-profile_ver  <> gv_profile_ver.
      cv_message = |Session { iv_session_id } already owns another preview/execution context.|.
      RETURN.
    ENDIF.
  ENDIF.

  ls_session-tcode        = p_transaction.
  ls_session-profile_name = txtp_profile_name.
  ls_session-profile_ver  = gv_profile_ver.
  CLEAR: ls_session-script_id, ls_session-contract_hash.

  IF ls_session-start_time IS INITIAL.
    GET TIME STAMP FIELD lv_ts.
    ls_session-start_time = lv_ts.
  ENDIF.
  IF ls_session-created_by IS INITIAL OR ls_session-created_by = 'UNKNOWN'.
    ls_session-created_by = sy-uname.
  ENDIF.

  MODIFY zbdc_session_bup FROM @ls_session.
  IF sy-subrc <> 0.
    cv_message = |Preview context could not be saved for session { iv_session_id }.|.
    RETURN.
  ENDIF.

  cv_ok = abap_true.
  cv_message = |Preview context saved: { p_transaction }/{ txtp_profile_name } v{ gv_profile_ver }; execution remains gated.|.
ENDFORM.

FORM freeze_session_contract
  USING    iv_session_id TYPE zbdc_session_bup-session_id
  CHANGING cv_ok         TYPE abap_bool
           cv_message    TYPE string.

  DATA: ls_profile        TYPE zbdc_prof_bup,
        ls_script         TYPE zbdc_script_bup,
        ls_cert           TYPE zbdc_cert_bup,
        ls_session        TYPE zbdc_session_bup,
        lv_map_found      TYPE zbdc_mapping_bup-profile_name,
        lv_script_status  TYPE zbdc_script_bup-status,
        lv_cert_status    TYPE zbdc_cert_bup-cert_status,
        lv_ts             TYPE tzntstmps,
        lv_has_frozen     TYPE abap_bool.

  CLEAR: cv_ok, cv_message.

 "freeze the exact executable contract at ingestion time.
 "The session owns one immutable TCODE/Profile/Version/Script/Hash tuple.
 "No TCODE-specific branch and no later 'latest profile' lookup is allowed.
  IF iv_session_id IS INITIAL.
    cv_message = 'Session ID is missing; executable contract cannot be frozen.'.
    RETURN.
  ENDIF.

  IF p_transaction IS INITIAL OR
     txtp_profile_name IS INITIAL OR
     gv_profile_ver IS INITIAL.
    cv_message = 'Resolved TCODE/Profile/Version is missing at ingestion time.'.
    RETURN.
  ENDIF.

 "Freeze only an exact existing registry snapshot. Version ordering is not
 "used as identity and no latest/highest fallback is allowed.

  SELECT SINGLE *
    FROM zbdc_prof_bup
    INTO @ls_profile
    WHERE tcode        = @p_transaction
      AND profile_name = @txtp_profile_name
      AND profile_ver  = @gv_profile_ver.
  IF sy-subrc <> 0.
    cv_message = |Exact profile contract { p_transaction }/{ txtp_profile_name } v{ gv_profile_ver } does not exist; no version fallback is allowed.|.
    RETURN.
  ENDIF.

  CASE ls_profile-status.
    WHEN 'ACTIVE'.
 "Productive contracts remain strict: only the already certified immutable
 "Script/Mapping tuple may be frozen into a new ingestion session.
      lv_script_status = 'ACTIVE'.
      lv_cert_status   = 'CERTIFIED'.

    WHEN 'TESTING'.
 "Ingestion consumes an already prepared exact test contract. It never
 "builds certification evidence or advances profile lifecycle.
      lv_script_status = 'TEST_READY'.
      lv_cert_status   = 'PENDING_TEST'.

    WHEN 'MAPPED' OR 'DRAFT'.
 "generated templates from onboarding may be uploaded for
 "Preview Data before the runtime Script/Hash proof is complete.
 "Do not create an executable frozen contract here; save only the
 "exact TCODE/Profile/Version preview owner. CT/BISM remains gated by
 "resolve_session_context and the runtime proof checks.
      PERFORM save_preview_session
        USING    iv_session_id
        CHANGING cv_ok cv_message.
      RETURN.

    WHEN OTHERS.
      cv_message = |Profile { txtp_profile_name } v{ gv_profile_ver } is not executable (status { ls_profile-status }).|.
      RETURN.
  ENDCASE.

 "certification is the immutable manifest of the exact executable
 "Script/Hash pair. Never rediscover the Script with SELECT SINGLE by
 "TCODE/Profile/Version/Status because historical duplicate headers may exist
 "for the same logical version and an arbitrary legacy row may have a blank
 "CONTRACT_HASH. Resolve the manifest first, then address Script by SCRIPT_ID.
  SELECT SINGLE profile_name
    FROM zbdc_mapping_bup
    INTO @lv_map_found
    WHERE tcode        = @p_transaction
      AND profile_name = @txtp_profile_name
      AND profile_ver  = @gv_profile_ver.
  IF sy-subrc <> 0.
    cv_message = |Exact Mapping contract is missing for { txtp_profile_name } v{ gv_profile_ver }.|.
    RETURN.
  ENDIF.

  CLEAR ls_cert.
  SELECT SINGLE *
    FROM zbdc_cert_bup
    INTO @ls_cert
    WHERE tcode        = @p_transaction
      AND profile_name = @txtp_profile_name
      AND profile_ver  = @gv_profile_ver
      AND cert_status  = @lv_cert_status.
  IF sy-subrc <> 0 OR
     ls_cert-script_id IS INITIAL OR
     ls_cert-contract_hash IS INITIAL.
    IF ls_profile-status = 'TESTING'.
 "a TESTING template may be previewed even if the runtime
 "manifest/proof is not ready yet. Upload/Preview must not fail with
 "a missing frozen-context error; execution still requires Script/Hash.
      PERFORM save_preview_session
        USING    iv_session_id
        CHANGING cv_ok cv_message.
      RETURN.
    ENDIF.
    cv_message = |Exact certification manifest (Script/Hash) is missing for { txtp_profile_name } v{ gv_profile_ver }.|.
    RETURN.
  ENDIF.

  IF lv_cert_status = 'CERTIFIED' AND
     ls_cert-last_test_status <> 'CERTIFIED'.
    cv_message = |Certified profile { txtp_profile_name } v{ gv_profile_ver } has no certified test proof.|.
    RETURN.
  ENDIF.

  CLEAR ls_script.
  SELECT SINGLE *
    FROM zbdc_script_bup
    INTO @ls_script
    WHERE script_id    = @ls_cert-script_id
      AND tcode        = @p_transaction
      AND profile_name = @txtp_profile_name
      AND profile_ver  = @gv_profile_ver
      AND status       = @lv_script_status.
  IF sy-subrc <> 0.
    cv_message = |Exact Script { ls_cert-script_id } referenced by certification is missing or has the wrong lifecycle status.|.
    RETURN.
  ENDIF.

  IF ls_script-contract_hash IS INITIAL OR
     ls_script-contract_hash <> ls_cert-contract_hash.
    cv_message = |Exact Script/Certification hash mismatch for { txtp_profile_name } v{ gv_profile_ver }.|.
    RETURN.
  ENDIF.

  CLEAR ls_session.
  SELECT SINGLE *
    FROM zbdc_session_bup
    INTO @ls_session
    WHERE session_id = @iv_session_id.

  IF sy-subrc <> 0.
    CLEAR ls_session.
    ls_session-session_id = iv_session_id.
    GET TIME STAMP FIELD lv_ts.
    ls_session-start_time = lv_ts.
    ls_session-created_by = sy-uname.
  ENDIF.

  lv_has_frozen = abap_false.
  IF ls_session-tcode IS NOT INITIAL OR
     ls_session-profile_name IS NOT INITIAL OR
     ls_session-profile_ver IS NOT INITIAL OR
     ls_session-script_id IS NOT INITIAL OR
     ls_session-contract_hash IS NOT INITIAL.
    lv_has_frozen = abap_true.
  ENDIF.

  IF lv_has_frozen = abap_true.
 "preserve immutable ownership, but allow a legacy/preview session
 "that already owns the exact same TCODE/Profile/Version to COMPLETE blank
 "Script/Hash proof fields from the exact certification manifest. Any
 "nonblank conflicting owner/proof value still blocks mutation.
    IF ( ls_session-tcode IS NOT INITIAL AND
         ls_session-tcode <> p_transaction ) OR
       ( ls_session-profile_name IS NOT INITIAL AND
         ls_session-profile_name <> txtp_profile_name ) OR
       ( ls_session-profile_ver IS NOT INITIAL AND
         ls_session-profile_ver <> gv_profile_ver ) OR
       ( ls_session-script_id IS NOT INITIAL AND
         ls_session-script_id <> ls_script-script_id ) OR
       ( ls_session-contract_hash IS NOT INITIAL AND
         ls_session-contract_hash <> ls_script-contract_hash ).
      cv_message = |Session { iv_session_id } already owns a different frozen contract; mutation is blocked.|.
      RETURN.
    ENDIF.

    IF ls_session-tcode         = p_transaction AND
       ls_session-profile_name  = txtp_profile_name AND
       ls_session-profile_ver   = gv_profile_ver AND
       ls_session-script_id     = ls_script-script_id AND
       ls_session-contract_hash = ls_script-contract_hash.
      cv_ok = abap_true.
      cv_message = |Frozen contract already verified for session { iv_session_id }.|.
      RETURN.
    ENDIF.
 "Otherwise this is the same exact owner with one or more blank proof
 "components. Fall through and fill only the proven exact tuple below.
  ENDIF.

  ls_session-tcode         = p_transaction.
  ls_session-profile_name  = txtp_profile_name.
  ls_session-profile_ver   = gv_profile_ver.
  ls_session-script_id     = ls_script-script_id.
  ls_session-contract_hash = ls_script-contract_hash.

  IF ls_session-start_time IS INITIAL.
    GET TIME STAMP FIELD lv_ts.
    ls_session-start_time = lv_ts.
  ENDIF.
  IF ls_session-created_by IS INITIAL OR ls_session-created_by = 'UNKNOWN'.
    ls_session-created_by = sy-uname.
  ENDIF.

  MODIFY zbdc_session_bup FROM @ls_session.
  IF sy-subrc <> 0.
    cv_message = |Frozen session contract could not be persisted for { iv_session_id }.|.
    RETURN.
  ENDIF.

  cv_ok = abap_true.
  cv_message = |Frozen exact contract: { p_transaction }/{ txtp_profile_name } v{ gv_profile_ver }.|.
ENDFORM.

FORM resolve_session_context
  USING    iv_session_id TYPE zbdc_staging_bup-session_id
  CHANGING cv_tcode      TYPE zbdc_prof_bup-tcode
           cv_profile    TYPE zbdc_prof_bup-profile_name
           cv_ver        TYPE zbdc_prof_bup-profile_ver
           cv_found      TYPE abap_bool.

  DATA: ls_session   TYPE zbdc_session_bup,
        ls_profile   TYPE zbdc_prof_bup,
        ls_script    TYPE zbdc_script_bup,
        lv_map_found TYPE zbdc_mapping_bup-profile_name.

  CLEAR: cv_tcode, cv_profile, cv_ver, cv_found,
         gv_runtime_script_id, gv_runtime_contract_hash,
         gs_runtime_cert, gv_runtime_cert_loaded.

  IF iv_session_id IS INITIAL.
    RETURN.
  ENDIF.

  SELECT SINGLE *
    FROM zbdc_session_bup
    INTO @ls_session
    WHERE session_id = @iv_session_id.

 "EXEC_ONLY: the ingestion session must own one exact immutable execution
 "tuple. Certification/Object metadata is deliberately outside this gate.
  IF sy-subrc <> 0 OR
     ls_session-tcode IS INITIAL OR
     ls_session-profile_name IS INITIAL OR
     ls_session-profile_ver IS INITIAL OR
     ls_session-script_id IS INITIAL OR
     ls_session-contract_hash IS INITIAL.
    RETURN.
  ENDIF.

  SELECT SINGLE *
    FROM zbdc_prof_bup
    INTO @ls_profile
    WHERE tcode        = @ls_session-tcode
      AND profile_name = @ls_session-profile_name
      AND profile_ver  = @ls_session-profile_ver.
  IF sy-subrc <> 0.
    RETURN.
  ENDIF.

  SELECT SINGLE *
    FROM zbdc_script_bup
    INTO @ls_script
    WHERE script_id     = @ls_session-script_id
      AND tcode         = @ls_session-tcode
      AND profile_name  = @ls_session-profile_name
      AND profile_ver   = @ls_session-profile_ver
      AND contract_hash = @ls_session-contract_hash.
  IF sy-subrc <> 0 OR
     ls_script-script_id IS INITIAL OR
     ls_script-status = 'RESERVED' OR
     ( ls_script-status = 'INACTIVE' AND
       ls_script-recording_name = 'BLOCKED_IMPORT' ).
    RETURN.
  ENDIF.

  SELECT SINGLE profile_name
    FROM zbdc_mapping_bup
    INTO @lv_map_found
    WHERE tcode        = @ls_session-tcode
      AND profile_name = @ls_session-profile_name
      AND profile_ver  = @ls_session-profile_ver.
  IF sy-subrc <> 0.
    RETURN.
  ENDIF.

  cv_tcode   = ls_session-tcode.
  cv_profile = ls_session-profile_name.
  cv_ver     = ls_session-profile_ver.
  cv_found   = abap_true.

  p_transaction             = cv_tcode.
  txtp_profile_name         = cv_profile.
  gv_profile_ver            = cv_ver.
  gv_runtime_script_id      = ls_session-script_id.
  gv_runtime_contract_hash  = ls_session-contract_hash.

 "Keep SAP Object/certification state explicitly empty during CT/BISM-only
 "execution so no later helper can accidentally turn it into an executor gate.
  CLEAR: gs_runtime_cert, gv_runtime_cert_loaded.
ENDFORM.

FORM apply_first_staging_ctx.
  DATA: ls_first   TYPE zbdc_staging_bup,
        lv_tcode   TYPE zbdc_prof_bup-tcode,
        lv_profile TYPE zbdc_prof_bup-profile_name,
        lv_ver     TYPE zbdc_prof_bup-profile_ver,
        lv_found   TYPE abap_bool.

  READ TABLE gt_staging INTO ls_first INDEX 1.
  IF sy-subrc <> 0.
    RETURN.
  ENDIF.

  PERFORM resolve_session_context
    USING    ls_first-session_id
    CHANGING lv_tcode lv_profile lv_ver lv_found.

  IF lv_found <> abap_true.
    p_transaction = ls_first-tcode.
    CLEAR: txtp_profile_name, gv_profile_ver.
  ENDIF.
ENDFORM.

FORM verify_loaded_ctx
  USING    iv_expected_tcode TYPE char20
  CHANGING cv_ok             TYPE abap_bool
           cv_message        TYPE string.

  TYPES: BEGIN OF ty_ctx,
           session_id    TYPE zbdc_session_bup-session_id,
           tcode         TYPE zbdc_session_bup-tcode,
           profile_name  TYPE zbdc_session_bup-profile_name,
           profile_ver   TYPE zbdc_session_bup-profile_ver,
           script_id     TYPE zbdc_session_bup-script_id,
           contract_hash TYPE zbdc_session_bup-contract_hash,
         END OF ty_ctx.

  DATA: lv_expected     TYPE char20,
        lt_sid          TYPE SORTED TABLE OF zbdc_staging_bup-session_id
                        WITH UNIQUE KEY table_line,
        ls_ctx          TYPE ty_ctx,
        ls_ref          TYPE ty_ctx,
        lv_ctx_tcode    TYPE zbdc_prof_bup-tcode,
        lv_ctx_profile  TYPE zbdc_prof_bup-profile_name,
        lv_ctx_ver      TYPE zbdc_prof_bup-profile_ver,
        lv_ctx_found    TYPE abap_bool,
        lv_row_tcode    TYPE char20,
        lv_prof_status  TYPE zbdc_prof_bup-status,
        lv_preview_ctx  TYPE abap_bool.

  CLEAR: cv_ok, cv_message, lv_preview_ctx.
  lv_expected = iv_expected_tcode.
  TRANSLATE lv_expected TO UPPER CASE.
  CONDENSE lv_expected NO-GAPS.

  IF gt_staging IS INITIAL.
    cv_message = 'No staging rows are loaded.'.
    RETURN.
  ENDIF.

  LOOP AT gt_staging INTO DATA(ls_stg).
    IF ls_stg-session_id IS INITIAL.
      cv_message = 'A staging row has no session identity.'.
      RETURN.
    ENDIF.

    lv_row_tcode = ls_stg-tcode.
    TRANSLATE lv_row_tcode TO UPPER CASE.
    CONDENSE lv_row_tcode NO-GAPS.
    IF lv_expected IS NOT INITIAL AND lv_row_tcode <> lv_expected.
      cv_message =
        |Loaded staging contains TCODE { lv_row_tcode }, expected { lv_expected }.|.
      RETURN.
    ENDIF.
    INSERT ls_stg-session_id INTO TABLE lt_sid.
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
       ls_ctx-profile_ver IS INITIAL.
      cv_message =
        |Session { lv_sid } has no TCODE/Profile/Version context.|.
      RETURN.
    ENDIF.

    IF ls_ctx-script_id IS INITIAL OR
       ls_ctx-contract_hash IS INITIAL.
      CLEAR lv_prof_status.
      SELECT SINGLE status
        FROM zbdc_prof_bup
        INTO @lv_prof_status
        WHERE tcode        = @ls_ctx-tcode
          AND profile_name = @ls_ctx-profile_name
          AND profile_ver  = @ls_ctx-profile_ver.
      IF sy-subrc = 0 AND
         ( lv_prof_status = 'DRAFT' OR
           lv_prof_status = 'MAPPED' OR
           lv_prof_status = 'TESTING' ).
 "Preview Data may use a non-executable onboarding context.
 "Runtime execution still requires Script/Hash through z30_resolve*.
        lv_preview_ctx = abap_true.
      ELSE.
        cv_message =
          |Session { lv_sid } has no frozen TCODE/Profile/Version/Script/Hash context.|.
        RETURN.
      ENDIF.
    ENDIF.

    IF ls_ref-session_id IS INITIAL.
      ls_ref = ls_ctx.
    ELSEIF ls_ctx-tcode         <> ls_ref-tcode OR
           ls_ctx-profile_name  <> ls_ref-profile_name OR
           ls_ctx-profile_ver   <> ls_ref-profile_ver OR
           ls_ctx-script_id     <> ls_ref-script_id OR
           ls_ctx-contract_hash <> ls_ref-contract_hash.
      cv_message =
        |Loaded scope mixes immutable contracts ({ ls_ref-session_id } and { ls_ctx-session_id }).|.
      RETURN.
    ENDIF.
  ENDLOOP.

  IF lv_expected IS NOT INITIAL AND ls_ref-tcode <> lv_expected.
    cv_message = |Frozen context TCODE { ls_ref-tcode } does not match { lv_expected }.|.
    RETURN.
  ENDIF.

  IF lv_preview_ctx = abap_true.
    p_transaction     = ls_ref-tcode.
    txtp_profile_name = ls_ref-profile_name.
    gv_profile_ver    = ls_ref-profile_ver.
    cv_ok = abap_true.
    cv_message =
      |Verified preview context { ls_ref-tcode }/{ ls_ref-profile_name } v{ ls_ref-profile_ver }; execution remains gated.|.
    RETURN.
  ENDIF.

  PERFORM resolve_session_context
    USING    ls_ref-session_id
    CHANGING lv_ctx_tcode lv_ctx_profile lv_ctx_ver lv_ctx_found.
  IF lv_ctx_found <> abap_true.
    cv_message =
      |Frozen contract for session { ls_ref-session_id } is not runnable/certified.|.
    RETURN.
  ENDIF.

  cv_ok = abap_true.
  cv_message =
    |Verified exact context { ls_ref-tcode }/{ ls_ref-profile_name } v{ ls_ref-profile_ver }.|.
ENDFORM.

*& Staging review must not keep synthetic setup-gate failures

*& The Staging button is a review boundary, not an execution monitor. A
*& previous preflight block such as "Profile setup incomplete" is not a data
*& validation failure and must not make every freshly loaded group look like
*& a BDC/SAP error whenever the user re-opens Staging. Keep real SAP/data
*& errors intact; reset only synthetic runtime-setup gate messages.

FORM is_setup_gate_msg
  USING    iv_text TYPE any
  CHANGING cv_gate TYPE abap_bool.

  DATA lv_text TYPE string.

  CLEAR cv_gate.
  lv_text = iv_text.
  TRANSLATE lv_text TO UPPER CASE.

  IF lv_text CS 'PROFILE SETUP'
     OR lv_text CS 'NOT CERTIFIED'
     OR lv_text CS 'FROZEN CERTIFIED SESSION CONTRACT'
     OR lv_text CS 'RUNTIME PROOF CONTRACT'
     OR lv_text CS 'OBJECT PROOF CONTRACT'
     OR lv_text CS 'BEFORE SAP REPLAY'
     OR lv_text CS 'CERTIFIED RUNTIME CONTRACT'
     OR lv_text CS 'CERTIFY THE OBJECT PROOF'.
    cv_gate = abap_true.
  ENDIF.
ENDFORM.

FORM reset_stage_setup_gate
  CHANGING cv_reset TYPE i.

  DATA: lt_stage_upd  TYPE STANDARD TABLE OF zbdc_staging_bup,
        lt_result     TYPE STANDARD TABLE OF zbdc_result_bup,
        lt_result_del TYPE STANDARD TABLE OF zbdc_result_bup,
        lt_sid        TYPE SORTED TABLE OF zbdc_staging_bup-session_id
                      WITH UNIQUE KEY table_line,
        lv_text       TYPE string,
        lv_gate       TYPE abap_bool,
        lv_sid        TYPE zbdc_staging_bup-session_id.

  FIELD-SYMBOLS: <ls_stage> TYPE zbdc_staging_bup,
                 <ls_res>   TYPE zbdc_result_bup.

  CLEAR cv_reset.

  LOOP AT gt_staging ASSIGNING <ls_stage>.
    CLEAR: lv_text, lv_gate.
    CONCATENATE <ls_stage>-error_msg <ls_stage>-last_error
      INTO lv_text SEPARATED BY space.
    PERFORM is_setup_gate_msg USING lv_text CHANGING lv_gate.

    IF lv_gate = abap_true
       AND ( <ls_stage>-status = gc_st_error OR <ls_stage>-status = 'ERROR' ).
      <ls_stage>-status = gc_st_ready.
      CLEAR: <ls_stage>-error_msg,
             <ls_stage>-last_error.
      APPEND <ls_stage> TO lt_stage_upd.
      INSERT <ls_stage>-session_id INTO TABLE lt_sid.
      cv_reset = cv_reset + 1.
    ENDIF.
  ENDLOOP.

  IF lt_stage_upd IS NOT INITIAL.
    MODIFY zbdc_staging_bup FROM TABLE lt_stage_upd.
  ENDIF.

  LOOP AT lt_sid INTO lv_sid.
    SELECT *
      FROM zbdc_result_bup
      APPENDING TABLE @lt_result
      WHERE session_id = @lv_sid.
  ENDLOOP.

  LOOP AT lt_result ASSIGNING <ls_res>.
    CLEAR: lv_text, lv_gate.
    CONCATENATE <ls_res>-message <ls_res>-exec_status
      INTO lv_text SEPARATED BY space.
    PERFORM is_setup_gate_msg USING lv_text CHANGING lv_gate.
    IF lv_gate = abap_true.
      APPEND <ls_res> TO lt_result_del.
    ENDIF.
  ENDLOOP.

  IF lt_result_del IS NOT INITIAL.
    DELETE zbdc_result_bup FROM TABLE lt_result_del.
  ENDIF.

  IF lt_stage_upd IS NOT INITIAL OR lt_result_del IS NOT INITIAL.
    COMMIT WORK AND WAIT.
  ENDIF.
ENDFORM.

FORM load_exact_staging
  USING    iv_session_id   TYPE zbdc_staging_bup-session_id
           iv_batch_prefix TYPE zbdc_staging_bup-session_id
           iv_tcode        TYPE char20
  CHANGING cv_count        TYPE i
           cv_ok           TYPE abap_bool
           cv_message      TYPE string.

  DATA: lv_tcode TYPE char20,
        lv_like  TYPE string.

  CLEAR: cv_count, cv_ok, cv_message.
  REFRESH: gt_staging, gt_staging_alv, gt_exec_disp.

  lv_tcode = iv_tcode.
  TRANSLATE lv_tcode TO UPPER CASE.
  CONDENSE lv_tcode NO-GAPS.

  IF iv_session_id IS INITIAL AND iv_batch_prefix IS INITIAL.
    cv_message = 'Exact staging context is required: select a session or batch first.'.
    RETURN.
  ENDIF.

  IF iv_batch_prefix IS NOT INITIAL.
    lv_like = iv_batch_prefix && '%'.
    SELECT *
      FROM zbdc_staging_bup
      INTO TABLE @gt_staging
      WHERE session_id LIKE @lv_like.
  ELSE.
    SELECT *
      FROM zbdc_staging_bup
      INTO TABLE @gt_staging
      WHERE session_id = @iv_session_id.
  ENDIF.

  SORT gt_staging BY session_id ASCENDING row_index ASCENDING.
  cv_count = lines( gt_staging ).
  IF cv_count <= 0.
    cv_message = 'The selected exact session/batch has no staging rows.'.
    RETURN.
  ENDIF.

  PERFORM verify_loaded_ctx
    USING    lv_tcode
    CHANGING cv_ok cv_message.
  IF cv_ok <> abap_true.
    REFRESH: gt_staging, gt_staging_alv, gt_exec_disp.
    CLEAR cv_count.
    RETURN.
  ENDIF.

 "V17.9.3.4 scope stability: GT_CURRENT_SESSIONS is context, not history.
 "Rebuild it from the rows that were JUST loaded so a previous upload/batch
 "can never make the next 0400 PBO expand back into an older session set.
  REFRESH gt_current_sessions.
  LOOP AT gt_staging INTO DATA(ls_scope_stg_934).
    READ TABLE gt_current_sessions
      WITH KEY table_line = ls_scope_stg_934-session_id
      TRANSPORTING NO FIELDS.
    IF sy-subrc <> 0 AND ls_scope_stg_934-session_id IS NOT INITIAL.
      APPEND ls_scope_stg_934-session_id TO gt_current_sessions.
    ENDIF.
  ENDLOOP.
  SORT gt_current_sessions.
  gv_current_batch_count = lines( gt_current_sessions ).

  "Root scope invariant: batch rendering is explicit state created only by
  "LOAD_STAGING_BY_BATCH. Resolving a batch prefix from one exact session
  "must never make a later 0400 PBO widen back into an older/multi-session
  "scope.
  CLEAR gv_0400_batch_scope.
  IF iv_batch_prefix IS NOT INITIAL AND gv_current_batch_count > 1.
    gv_0400_batch_scope = abap_true.
  ENDIF.

  IF iv_batch_prefix IS NOT INITIAL.
    gv_current_batch_prefix = iv_batch_prefix.
  ELSE.
    PERFORM batch_prefix_from_sid
      USING    iv_session_id
      CHANGING gv_current_batch_prefix.
  ENDIF.

  READ TABLE gt_staging INTO DATA(ls_first) INDEX 1.
  IF sy-subrc = 0.
    txtp_session_id = ls_first-session_id.
    txtp_sess       = ls_first-session_id.
  ENDIF.
  cv_count = lines( gt_staging ).
ENDFORM.

FORM load_staging_by_session
  USING    iv_session_id TYPE zbdc_staging_bup-session_id
  CHANGING cv_count      TYPE i.

  DATA: lv_ok  TYPE abap_bool,
        lv_msg TYPE string.

  PERFORM load_exact_staging
    USING    iv_session_id space space
    CHANGING cv_count lv_ok lv_msg.
  IF lv_ok <> abap_true.
    CLEAR cv_count.
    IF lv_msg IS NOT INITIAL.
      MESSAGE lv_msg TYPE 'S' DISPLAY LIKE 'W'.
    ENDIF.
  ENDIF.
ENDFORM.
