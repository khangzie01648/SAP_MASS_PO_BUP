*&---------------------------------------------------------------------*
*& Include          ZBDC_MPE_M1_STAGE_BUP
*& Purpose          M1 Staging - batch/session/staging/file log/duplicate
*& Source split     FIX16 V5BR - logic moved from F01
*&---------------------------------------------------------------------*

*>>> FORM z16_start_ingest_batch - moved from Z_BDC_MASS_PO_ENTRY_F01_BUP
FORM z16_start_ingest_batch.
  CLEAR: gv_current_batch_prefix, gv_ingest_batch_prefix,
         gv_forced_session_id, gv_current_batch_count.
  REFRESH gt_current_sessions.
  "V4S: compact batch prefix fits old CHAR20/CHAR22 SESSION_ID fields.
  "Example batch: B20260709201500; file sessions: B20260709201500_001.
  CONCATENATE 'B' sy-datum sy-uzeit INTO gv_ingest_batch_prefix.
  gv_current_batch_prefix = gv_ingest_batch_prefix.
ENDFORM.
*<<< END FORM z16_start_ingest_batch

*>>> FORM z16_make_batch_session - moved from Z_BDC_MASS_PO_ENTRY_F01_BUP

FORM z16_make_batch_session USING iv_index TYPE i
                            CHANGING cv_session_id TYPE zbdc_staging_bup-session_id.
  DATA lv_idx TYPE n LENGTH 3.
  IF gv_ingest_batch_prefix IS INITIAL.
    PERFORM z16_start_ingest_batch.
  ENDIF.
  lv_idx = iv_index.
  CONCATENATE gv_ingest_batch_prefix '_' lv_idx INTO cv_session_id.
ENDFORM.
*<<< END FORM z16_make_batch_session

*>>> FORM z16_register_current_session - moved from Z_BDC_MASS_PO_ENTRY_F01_BUP

FORM z16_register_current_session USING iv_session_id TYPE zbdc_staging_bup-session_id.
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
    PERFORM z16_batch_prefix_from_sid USING iv_session_id CHANGING lv_batch.
    gv_current_batch_prefix = lv_batch.
  ENDIF.
ENDFORM.
*<<< END FORM z16_register_current_session

*>>> FORM z16_finish_ingest_batch - moved from Z_BDC_MASS_PO_ENTRY_F01_BUP

FORM z16_finish_ingest_batch.
  gv_current_batch_count = lines( gt_current_sessions ).
  IF gv_current_batch_prefix IS INITIAL AND gt_current_sessions IS NOT INITIAL.
    READ TABLE gt_current_sessions INTO DATA(lv_sid) INDEX 1.
    IF sy-subrc = 0.
      PERFORM z16_batch_prefix_from_sid USING lv_sid CHANGING gv_current_batch_prefix.
    ENDIF.
  ENDIF.
ENDFORM.
*<<< END FORM z16_finish_ingest_batch

*>>> FORM z16_set_row_count_fields - moved from Z_BDC_MASS_PO_ENTRY_F01_BUP

FORM z16_set_row_count_fields USING iv_rows TYPE i.
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
*<<< END FORM z16_set_row_count_fields

*>>> FORM z16_load_staging_by_batch - moved from Z_BDC_MASS_PO_ENTRY_F01_BUP

FORM z16_load_staging_by_batch USING iv_batch_prefix TYPE zbdc_staging_bup-session_id
                               CHANGING cv_count TYPE i.
  DATA lv_like TYPE string.
  CLEAR cv_count.
  REFRESH: gt_staging, gt_staging_alv, gt_exec_disp.
  IF iv_batch_prefix IS INITIAL.
    RETURN.
  ENDIF.
  lv_like = iv_batch_prefix && '%'.
  SELECT *
    FROM zbdc_staging_bup
    INTO TABLE @gt_staging
    WHERE session_id LIKE @lv_like.
  SORT gt_staging BY session_id ASCENDING row_index ASCENDING.
  cv_count = lines( gt_staging ).
  gv_current_batch_prefix = iv_batch_prefix.
ENDFORM.
*<<< END FORM z16_load_staging_by_batch

*>>> FORM z16_resolve_batch_from_session - moved from Z_BDC_MASS_PO_ENTRY_F01_BUP

FORM z16_resolve_batch_from_session USING iv_session_id TYPE zbdc_staging_bup-session_id
                                    CHANGING cv_batch_prefix TYPE zbdc_staging_bup-session_id.
  PERFORM z16_batch_prefix_from_sid USING iv_session_id CHANGING cv_batch_prefix.
ENDFORM.


*&---------------------------------------------------------------------*
*& V4T File/Sheet Helpers - code only, no DDIC setup
*&---------------------------------------------------------------------*
*<<< END FORM z16_resolve_batch_from_session

*>>> FORM APPEND_STAGING_FROM_COLS_BUP - moved from Z_BDC_MASS_PO_ENTRY_F01_BUP

FORM APPEND_STAGING_FROM_COLS_BUP USING IT_COLS TYPE STRING_TABLE IV_SID TYPE ZBDC_STAGING_BUP-SESSION_ID IV_IDX TYPE I IV_SOURCE TYPE STRING.
  DATA: LS_STG TYPE ZBDC_STAGING_BUP,
        LV_MIN TYPE I,
        LV_CNT TYPE I,
        LV_PREF TYPE CHAR10.
  FIELD-SYMBOLS <COL> TYPE STRING.

  LV_CNT = LINES( IT_COLS ).
  PERFORM GET_MIN_COLS_BY_TCODE_BUP USING P_TRANSACTION CHANGING LV_MIN.
  CLEAR LS_STG.
  LS_STG-SESSION_ID = IV_SID.
  LS_STG-ROW_INDEX  = IV_IDX.
  LS_STG-TCODE      = P_TRANSACTION.
  LS_STG-STATUS     = GC_ST_READY.
  IF P_TRANSACTION = 'MIGO'. LV_PREF = 'MIGO'. ELSE. LV_PREF = 'PO'. ENDIF.
  LS_STG-RECORD_KEY = |{ LV_PREF }{ IV_IDX }|.

  READ TABLE IT_COLS INDEX 1 ASSIGNING <COL>. IF SY-SUBRC = 0. LS_STG-FIELD01 = <COL>. ENDIF.
  READ TABLE IT_COLS INDEX 2 ASSIGNING <COL>. IF SY-SUBRC = 0. LS_STG-FIELD02 = <COL>. ENDIF.
  READ TABLE IT_COLS INDEX 3 ASSIGNING <COL>. IF SY-SUBRC = 0. LS_STG-FIELD03 = <COL>. ENDIF.
  READ TABLE IT_COLS INDEX 4 ASSIGNING <COL>. IF SY-SUBRC = 0. LS_STG-FIELD04 = <COL>. ENDIF.
  READ TABLE IT_COLS INDEX 5 ASSIGNING <COL>. IF SY-SUBRC = 0. LS_STG-FIELD05 = <COL>. ENDIF.
  READ TABLE IT_COLS INDEX 6 ASSIGNING <COL>. IF SY-SUBRC = 0. LS_STG-FIELD06 = <COL>. ENDIF.
  READ TABLE IT_COLS INDEX 7 ASSIGNING <COL>. IF SY-SUBRC = 0. LS_STG-FIELD07 = <COL>. ENDIF.
  READ TABLE IT_COLS INDEX 8 ASSIGNING <COL>. IF SY-SUBRC = 0. LS_STG-FIELD08 = <COL>. ENDIF.
  READ TABLE IT_COLS INDEX 9 ASSIGNING <COL>. IF SY-SUBRC = 0. LS_STG-FIELD09 = <COL>. ENDIF.
  READ TABLE IT_COLS INDEX 10 ASSIGNING <COL>. IF SY-SUBRC = 0. LS_STG-FIELD10 = <COL>. ENDIF.
  READ TABLE IT_COLS INDEX 11 ASSIGNING <COL>. IF SY-SUBRC = 0. LS_STG-FIELD11 = <COL>. ENDIF.
  READ TABLE IT_COLS INDEX 12 ASSIGNING <COL>. IF SY-SUBRC = 0. LS_STG-FIELD12 = <COL>. ENDIF.
  READ TABLE IT_COLS INDEX 13 ASSIGNING <COL>. IF SY-SUBRC = 0. LS_STG-FIELD13 = <COL>. ENDIF.
  READ TABLE IT_COLS INDEX 14 ASSIGNING <COL>. IF SY-SUBRC = 0. LS_STG-FIELD14 = <COL>. ENDIF.
  READ TABLE IT_COLS INDEX 15 ASSIGNING <COL>. IF SY-SUBRC = 0. LS_STG-FIELD15 = <COL>. ENDIF.

  IF LV_CNT < LV_MIN.
    LS_STG-STATUS = GC_ST_ERROR.
    LS_STG-ERROR_MSG = |Invalid { P_TRANSACTION } webhook row: expected at least { LV_MIN } columns, got { LV_CNT }.|.
  ELSEIF P_TRANSACTION = 'MIGO'.
    IF LS_STG-FIELD01 IS INITIAL OR LS_STG-FIELD04 IS INITIAL OR LS_STG-FIELD05 IS INITIAL OR LS_STG-FIELD07 IS INITIAL.
      LS_STG-STATUS = GC_ST_ERROR.
      LS_STG-ERROR_MSG = 'Missing MIGO mandatory field: movement/material/quantity/plant'.
    ENDIF.
  ELSE.
    IF LS_STG-FIELD02 IS INITIAL OR LS_STG-FIELD06 IS INITIAL OR LS_STG-FIELD08 IS INITIAL.
      LS_STG-STATUS = GC_ST_ERROR.
      LS_STG-ERROR_MSG = 'Missing ME21N mandatory field: vendor/material/plant'.
    ENDIF.
  ENDIF.
  APPEND LS_STG TO GT_STAGING.
ENDFORM.
*<<< END FORM APPEND_STAGING_FROM_COLS_BUP

*>>> FORM update_session_summary - moved from Z_BDC_MASS_PO_ENTRY_F01_BUP
FORM update_session_summary USING iv_session_id TYPE zbdc_session_bup-session_id.

  "STRICT REAL V4 LIFECYCLE SUMMARY
  "Rebuild ZBDC_SESSION_BUP only from persisted evidence:
  "ZBDC_STAGING_BUP statuses, ZBDC_RESULT_BUP logs, and ingestion evidence.
  "No current-user/current-time fallback for old sessions.

  TYPES: BEGIN OF ty_sum_group,
           record_key TYPE zbdc_staging_bup-record_key,
           status     TYPE char20,
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
      IF ls_res-exec_status = 'ERROR' OR ls_res-msg_type = 'E'.
        <ls_group>-status = 'ERROR'.
      ELSEIF ( ls_res-msg_type = 'W' OR ls_res-exec_status = 'WARNING' )
         AND <ls_group>-status <> 'ERROR'.
        <ls_group>-status = 'WARNING'.
      ELSEIF ( ls_res-exec_status = gc_st_success
            OR ls_res-exec_status = 'SUCCESS'
            OR ( ls_res-msg_type = 'S' AND ls_res-sap_object_id IS NOT INITIAL ) )
         AND <ls_group>-status <> 'ERROR'
         AND <ls_group>-status <> 'WARNING'.
        <ls_group>-status = 'SUCCESS'.
      ELSEIF ls_res-exec_status = gc_st_sm35q
         AND <ls_group>-status <> 'ERROR'
         AND <ls_group>-status <> 'WARNING'
         AND <ls_group>-status <> 'SUCCESS'.
        <ls_group>-status = gc_st_sm35q.
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
  COMMIT WORK AND WAIT.

ENDFORM.

*&---------------------------------------------------------------------*
*& upd_all_rt_sess_sum
*& Sync dashboard evidence after Upload / Validate / Execute / Resubmit.
*&---------------------------------------------------------------------*
*<<< END FORM update_session_summary

*>>> FORM upd_all_rt_sess_sum - moved from Z_BDC_MASS_PO_ENTRY_F01_BUP
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



*&---------------------------------------------------------------------*
*& 0300 UX helpers - Preview File/Data and upload summary
*&---------------------------------------------------------------------*
*<<< END FORM upd_all_rt_sess_sum

*>>> FORM GET_0100_SELECTED_SESSION - moved from Z_BDC_MASS_PO_ENTRY_F01_BUP



FORM GET_0100_SELECTED_SESSION CHANGING CV_SESSION_ID TYPE ZBDC_RESULT_BUP-SESSION_ID.
  DATA LV_ROW_IDX TYPE I.

  CLEAR CV_SESSION_ID.

  "Try selected row first.
  IF GO_GRID_0100 IS BOUND.
    TRY.
        CL_GUI_CFW=>FLUSH( ).
        DATA(LO_SELECTIONS_0100) = GO_GRID_0100->GET_SELECTIONS( ).
        DATA(LT_ROWS_0100)       = LO_SELECTIONS_0100->GET_SELECTED_ROWS( ).
        IF LT_ROWS_0100 IS NOT INITIAL.
          READ TABLE LT_ROWS_0100 INTO LV_ROW_IDX INDEX 1.
          READ TABLE GT_SESSIONS INTO DATA(LS_SESS_0100) INDEX LV_ROW_IDX.
          IF SY-SUBRC = 0.
            CV_SESSION_ID = LS_SESS_0100-SESSION_ID.
          ENDIF.
        ENDIF.
      CATCH CX_ROOT.
        CLEAR CV_SESSION_ID.
    ENDTRY.
  ENDIF.

  "Fallback: newest row on dashboard, so toolbar buttons still feel responsive.
  IF CV_SESSION_ID IS INITIAL.
    READ TABLE GT_SESSIONS INTO DATA(LS_FIRST_SESS_0100) INDEX 1.
    IF SY-SUBRC = 0.
      CV_SESSION_ID = LS_FIRST_SESS_0100-SESSION_ID.
    ENDIF.
  ENDIF.
ENDFORM.
*<<< END FORM GET_0100_SELECTED_SESSION

*>>> FORM LOAD_STAGING_BY_SESSION - moved from Z_BDC_MASS_PO_ENTRY_F01_BUP

FORM LOAD_STAGING_BY_SESSION USING IV_SESSION_ID TYPE ZBDC_STAGING_BUP-SESSION_ID
                             CHANGING CV_COUNT TYPE I.
  DATA LS_FIRST TYPE ZBDC_STAGING_BUP.

  CLEAR CV_COUNT.
  REFRESH: GT_STAGING, GT_STAGING_ALV, GT_EXEC_DISP.

  IF IV_SESSION_ID IS INITIAL.
    RETURN.
  ENDIF.

  SELECT *
    FROM ZBDC_STAGING_BUP
    INTO TABLE @GT_STAGING
    WHERE SESSION_ID = @IV_SESSION_ID.

  SORT GT_STAGING BY ROW_INDEX ASCENDING.

  READ TABLE GT_STAGING INTO LS_FIRST INDEX 1.
  IF SY-SUBRC = 0.
    P_TRANSACTION = LS_FIRST-TCODE.
    PERFORM RESOLVE_PROFILE_BY_TCODE USING LS_FIRST-TCODE.
  ENDIF.

  CV_COUNT = LINES( GT_STAGING ).
ENDFORM.
*<<< END FORM LOAD_STAGING_BY_SESSION

*>>> FORM LOAD_LATEST_STAGING_FOR_TCODE - moved from Z_BDC_MASS_PO_ENTRY_F01_BUP

FORM LOAD_LATEST_STAGING_FOR_TCODE USING IV_TCODE TYPE CHAR20
                                   CHANGING CV_COUNT TYPE I.
  DATA: lv_tcode        TYPE char20,
        lv_latest_sess  TYPE zbdc_staging_bup-session_id,
        lv_batch_prefix TYPE zbdc_staging_bup-session_id,
        lv_like         TYPE string.

  CLEAR cv_count.
  lv_tcode = iv_tcode.
  TRANSLATE lv_tcode TO UPPER CASE.
  CONDENSE lv_tcode NO-GAPS.
  IF lv_tcode IS INITIAL.
    lv_tcode = 'ME21N'.
  ENDIF.

  p_transaction = lv_tcode.
  PERFORM resolve_profile_by_tcode USING lv_tcode.

  REFRESH: gt_staging, gt_staging_alv, gt_exec_disp.

  IF gv_current_batch_prefix IS NOT INITIAL.
    PERFORM z16_load_staging_by_batch USING gv_current_batch_prefix CHANGING cv_count.
    IF cv_count > 0.
      RETURN.
    ENDIF.
  ENDIF.

  CLEAR lv_latest_sess.
  SELECT MAX( session_id )
    FROM zbdc_file_lg_bup
    INTO @lv_latest_sess.

  IF lv_latest_sess IS NOT INITIAL.
    PERFORM z16_resolve_batch_from_session USING lv_latest_sess CHANGING lv_batch_prefix.
    IF lv_batch_prefix IS NOT INITIAL.
      PERFORM z16_load_staging_by_batch USING lv_batch_prefix CHANGING cv_count.
      IF cv_count > 0.
        RETURN.
      ENDIF.
    ENDIF.
  ENDIF.

  CLEAR lv_latest_sess.
  SELECT MAX( session_id )
    FROM zbdc_staging_bup
    INTO @lv_latest_sess
    WHERE tcode = @lv_tcode
      AND ( status = @gc_st_ready OR status = @gc_st_staged OR status = @gc_st_error OR status = @gc_st_warning ).

  IF lv_latest_sess IS INITIAL.
    RETURN.
  ENDIF.

  PERFORM z16_resolve_batch_from_session USING lv_latest_sess CHANGING lv_batch_prefix.
  IF lv_batch_prefix IS NOT INITIAL AND lv_batch_prefix <> lv_latest_sess.
    lv_like = lv_batch_prefix && '%'.
    SELECT *
      FROM zbdc_staging_bup
      INTO TABLE @gt_staging
      WHERE session_id LIKE @lv_like.
  ELSE.
    SELECT *
      FROM zbdc_staging_bup
      INTO TABLE @gt_staging
      WHERE session_id = @lv_latest_sess.
  ENDIF.

  SORT gt_staging BY session_id ASCENDING row_index ASCENDING.
  cv_count = lines( gt_staging ).
ENDFORM.
*<<< END FORM LOAD_LATEST_STAGING_FOR_TCODE
