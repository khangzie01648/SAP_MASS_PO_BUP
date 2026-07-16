*&---------------------------------------------------------------------*
*& Include          Z_BDC_MASS_PO_ENTRY_O01_BUP (PBO)
*& MUC 1 giu nguyen 100% - MUC 2 khong can sua gi trong PBO
*&---------------------------------------------------------------------*

MODULE status_0100 OUTPUT.
  TYPES: BEGIN OF ty_0100_sid,
           session_id TYPE zbdc_result_bup-session_id,
         END OF ty_0100_sid.

  TYPES: BEGIN OF ty_0100_group,
           session_id TYPE zbdc_staging_bup-session_id,
           record_key TYPE zbdc_staging_bup-record_key,
           status     TYPE char20,
         END OF ty_0100_group.

  DATA: lt_excl_0100    TYPE STANDARD TABLE OF sy-ucomm WITH DEFAULT KEY,
        lt_all_stg       TYPE STANDARD TABLE OF zbdc_staging_bup,
        lt_sess_stg      TYPE STANDARD TABLE OF zbdc_staging_bup,
        lt_sess_res      TYPE STANDARD TABLE OF zbdc_result_bup,
        lt_result_sids   TYPE STANDARD TABLE OF ty_0100_sid,
        lt_kpi_sids      TYPE SORTED TABLE OF ty_0100_sid WITH UNIQUE KEY session_id,
        lt_groups_global TYPE HASHED TABLE OF ty_0100_group WITH UNIQUE KEY session_id record_key,
        lt_groups_sess   TYPE HASHED TABLE OF ty_0100_group WITH UNIQUE KEY session_id record_key,
        ls_kpi_sid       TYPE ty_0100_sid,
        ls_group_0100    TYPE ty_0100_group,
        lv_group_key     TYPE zbdc_staging_bup-record_key,
        lv_tot_sess      TYPE i,
        lv_total_po      TYPE i,
        lv_succ_cnt      TYPE i,
        lv_warn_cnt      TYPE i,
        lv_err_cnt       TYPE i,
        lv_succ_pct      TYPE p LENGTH 5 DECIMALS 1,
        lv_warn_pct      TYPE p LENGTH 5 DECIMALS 1,
        lv_err_pct       TYPE p LENGTH 5 DECIMALS 1,
        lv_source_0100   TYPE char20.

  FIELD-SYMBOLS: <ls_group_0100> TYPE ty_0100_group.
  APPEND 'NEW_UPLOAD'      TO lt_excl_0100.
  APPEND 'FC_NEW_UPLOAD'   TO lt_excl_0100.
  APPEND 'FC_NEW_UPLD'     TO lt_excl_0100.
  APPEND 'VIEW_SESSION'    TO lt_excl_0100.
  APPEND 'FC_VIEW_SESSION' TO lt_excl_0100.
  APPEND 'FC_VIEW_SESS'    TO lt_excl_0100.
  APPEND 'RESUBMIT'        TO lt_excl_0100.
  APPEND 'FC_RESUBMIT'     TO lt_excl_0100.
  APPEND 'FC_RSUB'         TO lt_excl_0100.

  "0100 itself is the dashboard. Hide self-link and removed shortcuts.
  APPEND 'GT06'            TO lt_excl_0100.
  APPEND 'RESULT'          TO lt_excl_0100.
  APPEND 'RESULTS'         TO lt_excl_0100.
  APPEND 'FC_GOTO_0600'    TO lt_excl_0100.

  SET PF-STATUS 'STATUS_0100' EXCLUDING lt_excl_0100.
  SET TITLEBAR  'TITLE_0100'.

  PERFORM get_recent_sessions.
  PERFORM calculate_dashboard_stats.

  "KPI panel = global system aggregate. Count PO/group once by SESSION_ID + RECORD_KEY.
  REFRESH: lt_all_stg, lt_result_sids, lt_kpi_sids, lt_groups_global.

  SELECT * FROM zbdc_staging_bup INTO TABLE @lt_all_stg.

  LOOP AT lt_all_stg INTO DATA(ls_all_stg_0100).
    IF ls_all_stg_0100-session_id IS NOT INITIAL.
      ls_kpi_sid-session_id = ls_all_stg_0100-session_id.
      INSERT ls_kpi_sid INTO TABLE lt_kpi_sids.
    ENDIF.

    CLEAR lv_group_key.
    IF ls_all_stg_0100-record_key IS NOT INITIAL.
      lv_group_key = ls_all_stg_0100-record_key.
    ELSE.
      lv_group_key = ls_all_stg_0100-row_index.
    ENDIF.

    IF lv_group_key IS INITIAL.
      lv_group_key = 'ROW'.
    ENDIF.

    UNASSIGN <ls_group_0100>.
    READ TABLE lt_groups_global ASSIGNING <ls_group_0100>
      WITH TABLE KEY session_id = ls_all_stg_0100-session_id
                     record_key = lv_group_key.
    IF sy-subrc <> 0.
      CLEAR ls_group_0100.
      ls_group_0100-session_id = ls_all_stg_0100-session_id.
      ls_group_0100-record_key = lv_group_key.
      ls_group_0100-status     = 'READY'.
      INSERT ls_group_0100 INTO TABLE lt_groups_global ASSIGNING <ls_group_0100>.
    ENDIF.

    IF <ls_group_0100> IS ASSIGNED.
      IF ls_all_stg_0100-status = gc_st_error OR ls_all_stg_0100-status = 'ERROR'.
        <ls_group_0100>-status = 'ERROR'.
      ELSEIF ( ls_all_stg_0100-status = gc_st_warning OR ls_all_stg_0100-status = 'WARNING' )
         AND <ls_group_0100>-status <> 'ERROR'.
        <ls_group_0100>-status = 'WARNING'.
      ELSEIF ( ls_all_stg_0100-status = gc_st_success OR ls_all_stg_0100-status = 'SUCCESS' )
         AND <ls_group_0100>-status <> 'ERROR'
         AND <ls_group_0100>-status <> 'WARNING'.
        <ls_group_0100>-status = 'SUCCESS'.
      ENDIF.
    ENDIF.
  ENDLOOP.

  SELECT DISTINCT session_id
    FROM zbdc_result_bup
    INTO CORRESPONDING FIELDS OF TABLE @lt_result_sids.

  LOOP AT lt_result_sids INTO DATA(ls_res_sid_0100).
    IF ls_res_sid_0100-session_id IS NOT INITIAL.
      ls_kpi_sid-session_id = ls_res_sid_0100-session_id.
      INSERT ls_kpi_sid INTO TABLE lt_kpi_sids.
    ENDIF.
  ENDLOOP.

  lv_tot_sess = lines( lt_kpi_sids ).
  lv_total_po = lines( lt_groups_global ).

  LOOP AT lt_groups_global INTO ls_group_0100.
    CASE ls_group_0100-status.
      WHEN 'SUCCESS'.
        lv_succ_cnt = lv_succ_cnt + 1.
      WHEN 'WARNING'.
        lv_warn_cnt = lv_warn_cnt + 1.
      WHEN 'ERROR'.
        lv_err_cnt = lv_err_cnt + 1.
    ENDCASE.
  ENDLOOP.

  IF lv_total_po > 0.
    lv_succ_pct = ( lv_succ_cnt * 100 ) / lv_total_po.
    lv_err_pct  = ( lv_err_cnt  * 100 ) / lv_total_po.
    lv_warn_pct = ( lv_warn_cnt * 100 ) / lv_total_po.
  ENDIF.

  CLEAR: txtgv_total_sessions, txtgv_processed_pos, txtgv_success_count,
         txtgv_error_count, txtgv_warning_count, txtgv_success_pct,
         txtgv_error_pct, txtgv_warning_pct.

  txtgv_total_sessions = |{ lv_tot_sess }|.
  txtgv_processed_pos  = |{ lv_total_po }|.
  txtgv_success_count  = |{ lv_succ_cnt }|.
  txtgv_error_count    = |{ lv_err_cnt }|.
  txtgv_warning_count  = |{ lv_warn_cnt }|.
  txtgv_success_pct    = |{ lv_succ_pct } %|.
  txtgv_error_pct      = |{ lv_err_pct } %|.
  txtgv_warning_pct    = |{ lv_warn_pct } %|.

  "Do NOT use current ZBDC_CONFIG_BUP-SOURCE_TYPE for all rows.
  "Source in 0100 must be session-specific. If old sessions have no persisted
  "source marker, show UNKNOWN instead of fake SFTP/LOCAL.
  lv_source_0100 = 'UNKNOWN'.

  "ALV 0100 = Recent Session Summary. One line per session, not raw message log.
  REFRESH gt_dash_0100.

  LOOP AT gt_sessions INTO DATA(ls_sess_0100).
    DATA: ls_dash_0100      TYPE ty_dash_0100_disp,
          ls_sess_db_0100   TYPE zbdc_session_bup,
          lv_ts_raw_0100    TYPE char30,
          lv_ts_digits_0100 TYPE char30,
          lv_sid_digits_0100 TYPE char30,
          lv_date_0100      TYPE char10,
          lv_time_0100      TYPE char8,
          lv_ready_0100     TYPE i,
          lv_total_0100     TYPE i,
          lv_success_0100   TYPE i,
          lv_warning_0100   TYPE i,
          lv_error_0100     TYPE i,
          lv_log_0100       TYPE i,
          lv_retry_yes_0100 TYPE c LENGTH 1,
          lv_main_err_0100  TYPE char120,
          lv_last_obj_0100  TYPE zbdc_result_bup-sap_object_id,
          lv_tcode_0100     TYPE char20,
          lv_idx_0100       TYPE i,
          lv_one_0100       TYPE c LENGTH 1.

    CLEAR: ls_dash_0100, ls_sess_db_0100, lv_ts_raw_0100, lv_ts_digits_0100,
           lv_sid_digits_0100, lv_date_0100, lv_time_0100, lv_ready_0100, lv_total_0100,
           lv_success_0100, lv_warning_0100, lv_error_0100, lv_log_0100,
           lv_retry_yes_0100, lv_main_err_0100, lv_last_obj_0100, lv_tcode_0100.
    REFRESH: lt_sess_stg, lt_sess_res, lt_groups_sess.

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

    "REAL session source evidence priority:
    "1) persisted result log created by ingestion forms: INBOUND_SOURCE=...
    "2) current runtime file preview metadata for newly loaded sessions
    "3) UNKNOWN for legacy sessions without evidence (never fake from current config)
    LOOP AT lt_sess_res INTO DATA(ls_src_res_0100).
      IF ls_src_res_0100-message CS 'INBOUND_SOURCE=LOCAL'.
        ls_dash_0100-source_type = 'LOCAL'.
        EXIT.
      ELSEIF ls_src_res_0100-message CS 'INBOUND_SOURCE=SFTP'.
        ls_dash_0100-source_type = 'SFTP'.
        EXIT.
      ELSEIF ls_src_res_0100-message CS 'INBOUND_SOURCE=GDRIVE'.
        ls_dash_0100-source_type = 'GDRIVE'.
        EXIT.
      ELSEIF ls_src_res_0100-message CS 'INBOUND_SOURCE=REST'.
        ls_dash_0100-source_type = 'REST'.
        EXIT.
      ELSEIF ls_src_res_0100-message CS 'INBOUND_SOURCE=EMAIL'.
        ls_dash_0100-source_type = 'EMAIL'.
        EXIT.
      ENDIF.
    ENDLOOP.

    IF ls_dash_0100-source_type = 'UNKNOWN'.
      READ TABLE gt_files_preview INTO DATA(ls_file_src_0100)
        WITH KEY session_id = ls_sess_0100-session_id.
      IF sy-subrc = 0.
        IF ls_file_src_0100-channel CS 'SFTP'.
          ls_dash_0100-source_type = 'SFTP'.
        ELSEIF ls_file_src_0100-channel CS 'GDRIVE'.
          ls_dash_0100-source_type = 'GDRIVE'.
        ELSEIF ls_file_src_0100-channel CS 'REST'.
          ls_dash_0100-source_type = 'REST'.
        ELSEIF ls_file_src_0100-channel CS 'EMAIL'.
          ls_dash_0100-source_type = 'EMAIL'.
        ELSEIF ls_file_src_0100-channel CS 'LOCAL'.
          ls_dash_0100-source_type = 'LOCAL'.
        ENDIF.
      ENDIF.
    ENDIF.

    "Legacy evidence from system-generated session-id prefix.
    "This is not a config fallback; it is part of the persisted session key.
    IF ls_dash_0100-source_type = 'UNKNOWN'.
      IF ls_sess_0100-session_id CP 'SFTP_*'.
        ls_dash_0100-source_type = 'SFTP'.
      ELSEIF ls_sess_0100-session_id CP 'GDRIVE_*'.
        ls_dash_0100-source_type = 'GDRIVE'.
      ELSEIF ls_sess_0100-session_id CP 'REST_*'.
        ls_dash_0100-source_type = 'REST'.
      ELSEIF ls_sess_0100-session_id CP 'EMAIL_*'.
        ls_dash_0100-source_type = 'EMAIL'.
      ELSEIF ls_sess_0100-session_id CP 'LOCAL_*'.
        ls_dash_0100-source_type = 'LOCAL'.
      ENDIF.
    ENDIF.

    LOOP AT lt_sess_stg INTO DATA(ls_stg_0100).
      IF lv_tcode_0100 IS INITIAL AND ls_stg_0100-tcode IS NOT INITIAL.
        lv_tcode_0100 = ls_stg_0100-tcode.
      ENDIF.

      CLEAR lv_group_key.
      IF ls_stg_0100-record_key IS NOT INITIAL.
        lv_group_key = ls_stg_0100-record_key.
      ELSE.
        lv_group_key = ls_stg_0100-row_index.
      ENDIF.
      IF lv_group_key IS INITIAL.
        lv_group_key = 'ROW'.
      ENDIF.

      UNASSIGN <ls_group_0100>.
      READ TABLE lt_groups_sess ASSIGNING <ls_group_0100>
        WITH TABLE KEY session_id = ls_stg_0100-session_id
                       record_key = lv_group_key.
      IF sy-subrc <> 0.
        CLEAR ls_group_0100.
        ls_group_0100-session_id = ls_stg_0100-session_id.
        ls_group_0100-record_key = lv_group_key.
        ls_group_0100-status     = 'READY'.
        INSERT ls_group_0100 INTO TABLE lt_groups_sess ASSIGNING <ls_group_0100>.
      ENDIF.

      IF <ls_group_0100> IS ASSIGNED.
        IF ls_stg_0100-status = gc_st_error OR ls_stg_0100-status = 'ERROR'.
          <ls_group_0100>-status = 'ERROR'.
        ELSEIF ( ls_stg_0100-status = gc_st_warning OR ls_stg_0100-status = 'WARNING' )
           AND <ls_group_0100>-status <> 'ERROR'.
          <ls_group_0100>-status = 'WARNING'.
        ELSEIF ( ls_stg_0100-status = gc_st_success OR ls_stg_0100-status = 'SUCCESS' )
           AND <ls_group_0100>-status <> 'ERROR'
           AND <ls_group_0100>-status <> 'WARNING'.
          <ls_group_0100>-status = 'SUCCESS'.
        ELSEIF ls_stg_0100-status = gc_st_ready OR ls_stg_0100-status = 'READY'.
          IF <ls_group_0100>-status IS INITIAL.
            <ls_group_0100>-status = 'READY'.
          ENDIF.
        ENDIF.
      ENDIF.

      IF lv_main_err_0100 IS INITIAL.
        IF ls_stg_0100-error_msg IS NOT INITIAL.
          lv_main_err_0100 = ls_stg_0100-error_msg.
        ELSEIF ls_stg_0100-last_error IS NOT INITIAL.
          lv_main_err_0100 = ls_stg_0100-last_error.
        ENDIF.
      ENDIF.
    ENDLOOP.

    LOOP AT lt_sess_res INTO DATA(ls_res_0100).
      IF lv_tcode_0100 IS INITIAL AND ls_res_0100-tcode IS NOT INITIAL.
        lv_tcode_0100 = ls_res_0100-tcode.
      ENDIF.

      IF lv_last_obj_0100 IS INITIAL AND ls_res_0100-sap_object_id IS NOT INITIAL.
        lv_last_obj_0100 = ls_res_0100-sap_object_id.
      ENDIF.

      IF lv_main_err_0100 IS INITIAL
         AND ( ls_res_0100-msg_type = 'E' OR ls_res_0100-exec_status = 'ERROR' ).
        lv_main_err_0100 = ls_res_0100-message.
      ENDIF.

      IF ls_res_0100-retry_flag = 'X'.
        lv_retry_yes_0100 = 'X'.
      ENDIF.
    ENDLOOP.

    IF lv_tcode_0100 IS INITIAL.
      "Strict-real rule: do not fallback to current selection P_TRANSACTION.
      "If staging/result has no TCode evidence, show UNKNOWN.
      lv_tcode_0100 = 'UNKNOWN'.
    ENDIF.

    lv_total_0100 = lines( lt_groups_sess ).
    LOOP AT lt_groups_sess INTO ls_group_0100.
      CASE ls_group_0100-status.
        WHEN 'SUCCESS'.
          lv_success_0100 = lv_success_0100 + 1.
        WHEN 'WARNING'.
          lv_warning_0100 = lv_warning_0100 + 1.
        WHEN 'ERROR'.
          lv_error_0100 = lv_error_0100 + 1.
        WHEN OTHERS.
          lv_ready_0100 = lv_ready_0100 + 1.
      ENDCASE.
    ENDLOOP.

    ls_dash_0100-total_rec   = lv_total_0100.
    ls_dash_0100-ready_rec   = lv_ready_0100.
    ls_dash_0100-success_rec = lv_success_0100.
    ls_dash_0100-warning_rec = lv_warning_0100.
    ls_dash_0100-error_rec   = lv_error_0100.
    ls_dash_0100-log_count   = lv_log_0100.
    ls_dash_0100-tcode       = lv_tcode_0100.
    ls_dash_0100-last_object = lv_last_obj_0100.
    IF lv_error_0100 > 0 AND lv_main_err_0100 IS INITIAL.
      lv_main_err_0100 = 'UNKNOWN'.
    ENDIF.
    ls_dash_0100-main_error  = lv_main_err_0100.

    IF lv_total_0100 > 0.
      ls_dash_0100-success_pct = ( lv_success_0100 * 100 ) / lv_total_0100.
    ENDIF.

    IF lv_error_0100 > 0.
      ls_dash_0100-health      = icon_red_light.
      ls_dash_0100-status_text = 'ERROR'.
      IF lv_retry_yes_0100 = 'X'.
        ls_dash_0100-retryable = 'Yes'.
        ls_dash_0100-next_action = 'Retry / Review Error'.
      ELSE.
        "No retry evidence exists in DB; keep it explicit instead of guessing.
        ls_dash_0100-retryable = 'UNKNOWN'.
        ls_dash_0100-next_action = 'Review Error'.
      ENDIF.
    ELSEIF lv_warning_0100 > 0.
      ls_dash_0100-health      = icon_yellow_light.
      ls_dash_0100-status_text = 'WARNING'.
      ls_dash_0100-retryable   = 'No'.
      ls_dash_0100-next_action = 'Review Warning'.
    ELSEIF lv_total_0100 > 0 AND lv_success_0100 = lv_total_0100.
      ls_dash_0100-health      = icon_green_light.
      ls_dash_0100-status_text = 'SUCCESS'.
      ls_dash_0100-retryable   = 'No'.
      ls_dash_0100-next_action = 'Done'.
    ELSEIF lv_ready_0100 > 0 OR lv_total_0100 > 0.
      ls_dash_0100-health      = icon_yellow_light.
      ls_dash_0100-status_text = 'READY'.
      ls_dash_0100-retryable   = 'No'.
      ls_dash_0100-next_action = 'Execute'.
    ELSE.
      ls_dash_0100-health      = icon_yellow_light.
      ls_dash_0100-status_text = 'NO_DATA'.
      ls_dash_0100-retryable   = 'No'.
      ls_dash_0100-next_action = 'Open Staging'.
    ENDIF.

    WRITE ls_sess_0100-created_at TO lv_ts_raw_0100.
    IF lv_ts_raw_0100 IS INITIAL AND ls_sess_db_0100-start_time IS NOT INITIAL.
      WRITE ls_sess_db_0100-start_time TO lv_ts_raw_0100.
    ENDIF.

    lv_ts_digits_0100 = lv_ts_raw_0100.
    REPLACE ALL OCCURRENCES OF '.' IN lv_ts_digits_0100 WITH ''.
    REPLACE ALL OCCURRENCES OF ',' IN lv_ts_digits_0100 WITH ''.
    REPLACE ALL OCCURRENCES OF ':' IN lv_ts_digits_0100 WITH ''.
    REPLACE ALL OCCURRENCES OF '-' IN lv_ts_digits_0100 WITH ''.
    CONDENSE lv_ts_digits_0100 NO-GAPS.

    "Strict-real sort/display fallback: session IDs are system-generated
    "with timestamp evidence (e.g. SES_YYYYMMDD_HHMMSS or SFTP_YYYYMMDDHHMMSS).
    "Use that only when DB timestamp is missing; otherwise keep UNKNOWN.
    IF strlen( lv_ts_digits_0100 ) LT 14.
      CLEAR lv_sid_digits_0100.
      DO strlen( ls_dash_0100-session_id ) TIMES.
        lv_idx_0100 = sy-index - 1.
        lv_one_0100 = ls_dash_0100-session_id+lv_idx_0100(1).
        IF lv_one_0100 CA '0123456789'.
          CONCATENATE lv_sid_digits_0100 lv_one_0100 INTO lv_sid_digits_0100.
        ENDIF.
      ENDDO.
      CONDENSE lv_sid_digits_0100 NO-GAPS.
      IF strlen( lv_sid_digits_0100 ) GE 14.
        lv_ts_digits_0100 = lv_sid_digits_0100+0(14).
      ENDIF.
    ENDIF.

    IF strlen( lv_ts_digits_0100 ) GE 14.
      ls_dash_0100-sort_key = lv_ts_digits_0100+0(14).
      CONCATENATE lv_ts_digits_0100+0(4) '-'
                  lv_ts_digits_0100+4(2) '-'
                  lv_ts_digits_0100+6(2)
             INTO lv_date_0100.
      CONCATENATE lv_ts_digits_0100+8(2) ':'
                  lv_ts_digits_0100+10(2) ':'
                  lv_ts_digits_0100+12(2)
             INTO lv_time_0100.
      CONCATENATE lv_date_0100 lv_time_0100
             INTO ls_dash_0100-created_on
             SEPARATED BY space.
    ELSEIF lv_ts_raw_0100 IS NOT INITIAL.
      ls_dash_0100-created_on = lv_ts_raw_0100.
    ELSE.
      ls_dash_0100-created_on = 'UNKNOWN'.
    ENDIF.

    APPEND ls_dash_0100 TO gt_dash_0100.
  ENDLOOP.

  "Show newest real sessions first. UNKNOWN/blank timestamps go to bottom.
  SORT gt_dash_0100 BY sort_key DESCENDING session_id DESCENDING.

  IF go_container_0100 IS NOT INITIAL.
    FREE: go_grid_0100, go_container_0100.
  ENDIF.

  CREATE OBJECT go_container_0100
    EXPORTING container_name = 'CC_ALV_CONTAINER'.

  TRY.
      cl_salv_table=>factory(
        EXPORTING r_container  = go_container_0100
        IMPORTING r_salv_table = go_grid_0100
        CHANGING  t_table      = gt_dash_0100 ).
      go_grid_0100->get_functions( )->set_all( abap_true ).
      go_grid_0100->get_selections( )->set_selection_mode( if_salv_c_selection_mode=>row_column ).

      DATA(lo_cols_0100) = go_grid_0100->get_columns( ).
      lo_cols_0100->set_optimize( abap_true ).

      TRY.
          DATA(lo_col_0100) = lo_cols_0100->get_column( 'SORT_KEY' ).
          lo_col_0100->set_visible( abap_false ).
        CATCH cx_salv_not_found.
      ENDTRY.

      TRY.
          lo_col_0100 = lo_cols_0100->get_column( 'HEALTH' ).
          lo_col_0100->set_short_text( 'Health' ).
          lo_col_0100->set_medium_text( 'Health' ).
          lo_col_0100->set_long_text( 'Session Health' ).
        CATCH cx_salv_not_found.
      ENDTRY.

      TRY.
          lo_col_0100 = lo_cols_0100->get_column( 'SESSION_ID' ).
          lo_col_0100->set_short_text( 'Session' ).
          lo_col_0100->set_medium_text( 'Session ID' ).
          lo_col_0100->set_long_text( 'BDC Session ID' ).
        CATCH cx_salv_not_found.
      ENDTRY.

      TRY.
          lo_col_0100 = lo_cols_0100->get_column( 'CREATED_ON' ).
          lo_col_0100->set_short_text( 'Time' ).
          lo_col_0100->set_medium_text( 'Created Time' ).
          lo_col_0100->set_long_text( 'Created Time' ).
        CATCH cx_salv_not_found.
      ENDTRY.

      TRY.
          lo_col_0100 = lo_cols_0100->get_column( 'CREATED_BY' ).
          lo_col_0100->set_short_text( 'User' ).
          lo_col_0100->set_medium_text( 'Created By' ).
          lo_col_0100->set_long_text( 'Created By' ).
        CATCH cx_salv_not_found.
      ENDTRY.

      TRY.
          lo_col_0100 = lo_cols_0100->get_column( 'SOURCE_TYPE' ).
          lo_col_0100->set_short_text( 'Source' ).
          lo_col_0100->set_medium_text( 'Source' ).
          lo_col_0100->set_long_text( 'Inbound Source' ).
        CATCH cx_salv_not_found.
      ENDTRY.

      TRY.
          lo_col_0100 = lo_cols_0100->get_column( 'TCODE' ).
          lo_col_0100->set_short_text( 'TCode' ).
          lo_col_0100->set_medium_text( 'TCode' ).
          lo_col_0100->set_long_text( 'Transaction Code' ).
        CATCH cx_salv_not_found.
      ENDTRY.

      TRY.
          lo_col_0100 = lo_cols_0100->get_column( 'STATUS_TEXT' ).
          lo_col_0100->set_short_text( 'Status' ).
          lo_col_0100->set_medium_text( 'Status' ).
          lo_col_0100->set_long_text( 'Session Status' ).
        CATCH cx_salv_not_found.
      ENDTRY.

      TRY.
          lo_col_0100 = lo_cols_0100->get_column( 'TOTAL_REC' ).
          lo_col_0100->set_short_text( 'Total' ).
          lo_col_0100->set_medium_text( 'Total Rec' ).
          lo_col_0100->set_long_text( 'Total Records/Groups' ).
        CATCH cx_salv_not_found.
      ENDTRY.

      TRY.
          lo_col_0100 = lo_cols_0100->get_column( 'READY_REC' ).
          lo_col_0100->set_short_text( 'Ready' ).
          lo_col_0100->set_medium_text( 'Ready Rec' ).
          lo_col_0100->set_long_text( 'Ready Records' ).
        CATCH cx_salv_not_found.
      ENDTRY.

      TRY.
          lo_col_0100 = lo_cols_0100->get_column( 'SUCCESS_REC' ).
          lo_col_0100->set_short_text( 'OK' ).
          lo_col_0100->set_medium_text( 'Success Rec' ).
          lo_col_0100->set_long_text( 'Success Records' ).
        CATCH cx_salv_not_found.
      ENDTRY.

      TRY.
          lo_col_0100 = lo_cols_0100->get_column( 'WARNING_REC' ).
          lo_col_0100->set_short_text( 'Warn' ).
          lo_col_0100->set_medium_text( 'Warning Rec' ).
          lo_col_0100->set_long_text( 'Warning Records' ).
        CATCH cx_salv_not_found.
      ENDTRY.

      TRY.
          lo_col_0100 = lo_cols_0100->get_column( 'ERROR_REC' ).
          lo_col_0100->set_short_text( 'Err' ).
          lo_col_0100->set_medium_text( 'Error Rec' ).
          lo_col_0100->set_long_text( 'Error Records' ).
        CATCH cx_salv_not_found.
      ENDTRY.

      TRY.
          lo_col_0100 = lo_cols_0100->get_column( 'SUCCESS_PCT' ).
          lo_col_0100->set_short_text( 'OK %' ).
          lo_col_0100->set_medium_text( 'Success %' ).
          lo_col_0100->set_long_text( 'Session Success %' ).
        CATCH cx_salv_not_found.
      ENDTRY.

      TRY.
          lo_col_0100 = lo_cols_0100->get_column( 'LOG_COUNT' ).
          lo_col_0100->set_short_text( 'Logs' ).
          lo_col_0100->set_medium_text( 'Log Count' ).
          lo_col_0100->set_long_text( 'Result Log Count' ).
        CATCH cx_salv_not_found.
      ENDTRY.

      TRY.
          lo_col_0100 = lo_cols_0100->get_column( 'LAST_OBJECT' ).
          lo_col_0100->set_short_text( 'Object' ).
          lo_col_0100->set_medium_text( 'Last Object' ).
          lo_col_0100->set_long_text( 'Last SAP Object' ).
        CATCH cx_salv_not_found.
      ENDTRY.

      TRY.
          lo_col_0100 = lo_cols_0100->get_column( 'MAIN_ERROR' ).
          lo_col_0100->set_short_text( 'Main Err' ).
          lo_col_0100->set_medium_text( 'Main Error' ).
          lo_col_0100->set_long_text( 'Main Error / Root Cause' ).
        CATCH cx_salv_not_found.
      ENDTRY.

      TRY.
          lo_col_0100 = lo_cols_0100->get_column( 'RETRYABLE' ).
          lo_col_0100->set_short_text( 'Retry' ).
          lo_col_0100->set_medium_text( 'Retryable' ).
          lo_col_0100->set_long_text( 'Retryable' ).
        CATCH cx_salv_not_found.
      ENDTRY.

      TRY.
          lo_col_0100 = lo_cols_0100->get_column( 'NEXT_ACTION' ).
          lo_col_0100->set_short_text( 'Action' ).
          lo_col_0100->set_medium_text( 'Next Action' ).
          lo_col_0100->set_long_text( 'Recommended Next Action' ).
        CATCH cx_salv_not_found.
      ENDTRY.

      go_grid_0100->display( ).

      DATA(lo_events) = go_grid_0100->get_event( ).
      CREATE OBJECT go_alv_events.
      SET HANDLER go_alv_events->on_double_click FOR lo_events.
    CATCH cx_salv_msg INTO DATA(lx_salv_0100).
      MESSAGE lx_salv_0100->get_text( ) TYPE 'I'.
  ENDTRY.
ENDMODULE.

MODULE status_0200 OUTPUT.
  SET PF-STATUS 'STATUS_0200'.
  SET TITLEBAR  'TITLE_0200'.

  IF gv_config_loaded IS INITIAL.
    PERFORM load_source_config.
    gv_config_loaded = 'X'.
  ENDIF.
ENDMODULE.

MODULE status_0300 OUTPUT.
  DATA: lv_clean_path_0300 TYPE string,
        lv_sheet_meta_0300 TYPE string.

  SET PF-STATUS 'STATUS_0300'.
  SET TITLEBAR  'TITLE_0300'.

  IF txtp_file_path CS '|SHEET='.
    SPLIT txtp_file_path AT '|SHEET='
      INTO lv_clean_path_0300 lv_sheet_meta_0300.
    txtp_file_path = lv_clean_path_0300.
  ENDIF.

  IF g_sub_dynpro IS INITIAL.
    g_sub_dynpro = '0301'.
  ENDIF.

  IF g_sub_dynpro = '0301'.
    ts_preview-activetab = 'TAB_PREVIEW'.
  ELSE.
    ts_preview-activetab = 'TAB_FILES'.
  ENDIF.
ENDMODULE.

MODULE status_0301 OUTPUT.
  "V5DD: use CL_GUI_ALV_GRID for deterministic row refresh on screen 0301.
  DATA: lv_reload_0301 TYPE i,
        lt_fcat_0301   TYPE lvc_t_fcat,
        ls_layout_0301 TYPE lvc_s_layo,
        ls_stable_0301 TYPE lvc_s_stbl.

  IF gt_preview_data IS INITIAL.
    IF gt_staging IS INITIAL AND gv_current_batch_prefix IS NOT INITIAL.
      PERFORM z16_load_staging_by_batch
        USING    gv_current_batch_prefix
        CHANGING lv_reload_0301.
    ENDIF.
    IF gt_staging IS NOT INITIAL.
      PERFORM z16_build_preview_rows.
    ENDIF.
  ENDIF.

  READ TABLE gt_staging INTO DATA(ls_chk) INDEX 1.
  IF sy-subrc = 0 AND ls_chk-tcode = 'MIGO'.
    txtp_profile_name = 'DEFAULT_MIGO_MAP'.
  ELSEIF sy-subrc = 0.
    txtp_profile_name = 'DEFAULT_EXCEL_MAP'.
  ENDIF.

  PERFORM z16_build_fcat_0301 CHANGING lt_fcat_0301.

  IF go_container_0301 IS INITIAL.
    CREATE OBJECT go_container_0301
      EXPORTING container_name = 'CC_PREVIEW_CONTAINER'.
  ENDIF.

  IF go_alv_0301 IS INITIAL.
    CREATE OBJECT go_alv_0301
      EXPORTING i_parent = go_container_0301.

    ls_layout_0301-zebra      = abap_true.
    ls_layout_0301-cwidth_opt = abap_true.
    ls_layout_0301-sel_mode   = 'A'.

    CALL METHOD go_alv_0301->set_table_for_first_display
      EXPORTING
        is_layout       = ls_layout_0301
      CHANGING
        it_outtab       = gt_preview_data
        it_fieldcatalog = lt_fcat_0301.
  ELSE.
    CALL METHOD go_alv_0301->set_frontend_fieldcatalog
      EXPORTING
        it_fieldcatalog = lt_fcat_0301.

    ls_stable_0301-row = abap_true.
    ls_stable_0301-col = abap_true.
    CALL METHOD go_alv_0301->refresh_table_display
      EXPORTING
        is_stable      = ls_stable_0301
        i_soft_refresh = abap_false.
  ENDIF.

  CLEAR gv_rebuild_0301.
  CALL METHOD cl_gui_cfw=>flush
    EXCEPTIONS
      cntl_system_error = 1
      cntl_error        = 2
      OTHERS            = 3.
ENDMODULE.

MODULE status_0302 OUTPUT.
  DATA lv_file_header TYPE lvc_title.
  READ TABLE gt_staging INTO DATA(ls_chk2) INDEX 1.
  IF sy-subrc = 0 AND ls_chk2-tcode = 'MIGO'.
    txtp_profile_name = 'DEFAULT_MIGO_MAP'.
  ELSEIF sy-subrc = 0.
    txtp_profile_name = 'DEFAULT_EXCEL_MAP'.
  ENDIF.

  IF go_container_0302 IS NOT INITIAL.
    FREE: go_grid_0302, go_container_0302.
  ENDIF.

  PERFORM filter_errors_only.

  CREATE OBJECT go_container_0302
    EXPORTING container_name = 'CC_FILES_CONTAINER'.
  TRY.
      cl_salv_table=>factory(
        EXPORTING r_container  = go_container_0302
        IMPORTING r_salv_table = go_grid_0302
        CHANGING  t_table      = gt_files_preview ).
      DATA(lo_file_funcs) = go_grid_0302->get_functions( ).
      lo_file_funcs->set_all( abap_true ).
      TRY.
          lo_file_funcs->add_function(
            name     = 'ZMYFILES'
            text     = 'My Uploads'
            tooltip  = 'Show files uploaded by me'
            position = if_salv_c_function_position=>right_of_salv_functions ).
          lo_file_funcs->add_function(
            name     = 'ZALLFILES'
            text     = 'All Uploads'
            tooltip  = 'Show recent uploads from all users'
            position = if_salv_c_function_position=>right_of_salv_functions ).
        CATCH cx_root.
      ENDTRY.

      go_grid_0302->get_selections( )->set_selection_mode( if_salv_c_selection_mode=>row_column ).

      TRY.
          DATA(lo_file_disp) = go_grid_0302->get_display_settings( ).
          lo_file_disp->set_striped_pattern( abap_true ).
          IF gv_file_scope = gc_file_scope_all.
            lv_file_header = |All Uploads - shared history ({ lines( gt_files_preview ) }); double-click to preview|.
          ELSE.
            lv_file_header = |My Uploads ({ lines( gt_files_preview ) }) - latest files first|.
          ENDIF.
          lo_file_disp->set_list_header( lv_file_header ).
        CATCH cx_root.
      ENDTRY.

      DATA(lo_file_events) = go_grid_0302->get_event( ).
      CREATE OBJECT go_alv_file_events.
      SET HANDLER go_alv_file_events->on_file_double_click FOR lo_file_events.
      SET HANDLER go_alv_file_events->on_file_function FOR lo_file_events.

    CATCH cx_salv_msg INTO DATA(lx2).
      MESSAGE lx2->get_text( ) TYPE 'I'.
  ENDTRY.

  IF go_grid_0302 IS BOUND.
    TRY.
        DATA(lo_columns) = go_grid_0302->get_columns( ).
        DATA(lo_col_file) = lo_columns->get_column( 'STATUS_ICON' ).
        lo_columns->set_optimize( abap_true ).

        "Hide raw technical/audit fields. They are still available in the row
        "for double-click loading and still persisted in ZBDC_FILE_LG_BUP.
        TRY. lo_columns->get_column( 'FILE_NAME' )->set_visible( abap_false ). CATCH cx_salv_not_found. ENDTRY.
        TRY. lo_columns->get_column( 'FILE_SIZE' )->set_visible( abap_false ). CATCH cx_salv_not_found. ENDTRY.
        TRY. lo_columns->get_column( 'CHANNEL' )->set_visible( abap_false ). CATCH cx_salv_not_found. ENDTRY.
        TRY. lo_columns->get_column( 'UPLOAD_DATE' )->set_visible( abap_false ). CATCH cx_salv_not_found. ENDTRY.
        TRY. lo_columns->get_column( 'UPLOAD_TIME' )->set_visible( abap_false ). CATCH cx_salv_not_found. ENDTRY.
        TRY. lo_columns->get_column( 'USERNAME' )->set_visible( abap_false ). CATCH cx_salv_not_found. ENDTRY.
        TRY. lo_columns->get_column( 'SESSION_ID' )->set_visible( abap_false ). CATCH cx_salv_not_found. ENDTRY.
        TRY. lo_columns->get_column( 'RAW_STATUS' )->set_visible( abap_false ). CATCH cx_salv_not_found. ENDTRY.
        TRY. lo_columns->get_column( 'RAW_ERROR' )->set_visible( abap_false ). CATCH cx_salv_not_found. ENDTRY.
        TRY. lo_columns->get_column( 'DATA_UNIT' )->set_visible( abap_false ). CATCH cx_salv_not_found. ENDTRY.

        DATA(lv_has_sheet_0302) = abap_false.
        LOOP AT gt_files_preview INTO DATA(ls_sheet_0302).
          IF ls_sheet_0302-sheet_name IS NOT INITIAL AND ls_sheet_0302-sheet_name <> 'DATA'.
            lv_has_sheet_0302 = abap_true.
            EXIT.
          ENDIF.
        ENDLOOP.

        TRY.
            lo_col_file = lo_columns->get_column( 'STATUS_ICON' ).
            lo_col_file->set_short_text( 'Status' ).
            lo_col_file->set_medium_text( 'Status' ).
            lo_col_file->set_long_text( 'File Status' ).
            lo_col_file->set_output_length( 6 ).
            lo_columns->set_column_position( columnname = 'STATUS_ICON' position = 1 ).
          CATCH cx_salv_not_found.
        ENDTRY.

        TRY.
            lo_col_file = lo_columns->get_column( 'BATCH_KEY' ).
            lo_col_file->set_short_text( 'Batch' ).
            lo_col_file->set_medium_text( 'Batch' ).
            lo_col_file->set_long_text( 'Ingestion Batch' ).
            lo_col_file->set_output_length( 18 ).
            lo_columns->set_column_position( columnname = 'BATCH_KEY' position = 2 ).
          CATCH cx_salv_not_found.
        ENDTRY.

        TRY.
            lo_col_file = lo_columns->get_column( 'FILE_TITLE' ).
            lo_col_file->set_short_text( 'File' ).
            lo_col_file->set_medium_text( 'File / Source' ).
            lo_col_file->set_long_text( 'File / Source Name' ).
            lo_col_file->set_output_length( 34 ).
            lo_columns->set_column_position( columnname = 'FILE_TITLE' position = 3 ).
          CATCH cx_salv_not_found.
        ENDTRY.

        TRY.
            lo_col_file = lo_columns->get_column( 'SHEET_NAME' ).
            lo_col_file->set_short_text( 'Sheet' ).
            lo_col_file->set_medium_text( 'Sheet' ).
            lo_col_file->set_long_text( 'Excel Sheet' ).
            lo_col_file->set_output_length( 18 ).
            lo_col_file->set_visible( lv_has_sheet_0302 ).
            lo_columns->set_column_position( columnname = 'SHEET_NAME' position = 4 ).
          CATCH cx_salv_not_found.
        ENDTRY.

        TRY.
            lo_col_file = lo_columns->get_column( 'TX_CODE' ).
            lo_col_file->set_short_text( 'TCode' ).
            lo_col_file->set_medium_text( 'Transaction' ).
            lo_col_file->set_long_text( 'Transaction' ).
            lo_col_file->set_output_length( 12 ).
            lo_columns->set_column_position( columnname = 'TX_CODE' position = 5 ).
          CATCH cx_salv_not_found.
        ENDTRY.

        TRY.
            lo_col_file = lo_columns->get_column( 'SOURCE_TEXT' ).
            lo_col_file->set_short_text( 'Source' ).
            lo_col_file->set_medium_text( 'Source Type' ).
            lo_col_file->set_long_text( 'Inbound Source Type' ).
            lo_col_file->set_output_length( 14 ).
            lo_columns->set_column_position( columnname = 'SOURCE_TEXT' position = 6 ).
          CATCH cx_salv_not_found.
        ENDTRY.

        TRY.
            lo_col_file = lo_columns->get_column( 'ROWS_LOADED' ).
            lo_col_file->set_short_text( 'Rows' ).
            lo_col_file->set_medium_text( 'Rows Loaded' ).
            lo_col_file->set_long_text( 'Rows Loaded' ).
            lo_col_file->set_output_length( 10 ).
            lo_columns->set_column_position( columnname = 'ROWS_LOADED' position = 7 ).
          CATCH cx_salv_not_found.
        ENDTRY.

        TRY.
            lo_col_file = lo_columns->get_column( 'PROCESSED_ON' ).
            lo_col_file->set_short_text( 'Time' ).
            lo_col_file->set_medium_text( 'Processed At' ).
            lo_col_file->set_long_text( 'Processed At' ).
            lo_col_file->set_output_length( 19 ).
            lo_columns->set_column_position( columnname = 'PROCESSED_ON' position = 8 ).
          CATCH cx_salv_not_found.
        ENDTRY.

        TRY.
            lo_col_file = lo_columns->get_column( 'OWNER' ).
            lo_col_file->set_short_text( 'User' ).
            lo_col_file->set_medium_text( 'Created By' ).
            lo_col_file->set_long_text( 'Session User' ).
            lo_col_file->set_output_length( 12 ).
            IF gv_file_scope = gc_file_scope_my.
              lo_col_file->set_visible( abap_false ).
            ELSE.
              lo_col_file->set_visible( abap_true ).
            ENDIF.
            lo_columns->set_column_position( columnname = 'OWNER' position = 9 ).
          CATCH cx_salv_not_found.
        ENDTRY.

        TRY.
            lo_col_file = lo_columns->get_column( 'STATUS_TEXT' ).
            lo_col_file->set_short_text( 'Life' ).
            lo_col_file->set_medium_text( 'Lifecycle' ).
            lo_col_file->set_long_text( 'File Lifecycle Status' ).
            lo_col_file->set_output_length( 14 ).
            lo_columns->set_column_position( columnname = 'STATUS_TEXT' position = 10 ).
          CATCH cx_salv_not_found.
        ENDTRY.

        TRY.
            lo_col_file = lo_columns->get_column( 'NEXT_ACTION' ).
            lo_col_file->set_short_text( 'Action' ).
            lo_col_file->set_medium_text( 'Next Action' ).
            lo_col_file->set_long_text( 'Recommended Next Action' ).
            lo_col_file->set_output_length( 32 ).
            lo_columns->set_column_position( columnname = 'NEXT_ACTION' position = 11 ).
          CATCH cx_salv_not_found.
        ENDTRY.

      CATCH cx_salv_not_found.
    ENDTRY.

    go_grid_0302->refresh( refresh_mode = if_salv_c_refresh=>full ).
    go_grid_0302->display( ).
  ENDIF.
ENDMODULE.

MODULE status_0400 OUTPUT.
  DATA lt_excl_0400 TYPE STANDARD TABLE OF sy-ucomm WITH DEFAULT KEY.

  "V5AB: every 0400 roundtrip starts with an empty command buffer.
  "A checkbox edit must never reuse EXSL/RUN_SELECTED from an earlier PAI.
  CLEAR: ok_code, save_ok, sy-ucomm.

  "V5O safety net: mode A uses CL_GUI_CONTAINER=>SCREEN0, which belongs to
  "the whole SAP GUI client area rather than only dynpro 0500. If navigation
  "returns to 0400 by any path, remove the 0500 child control before drawing
  "the staging cockpit so its toolbar cannot remain over this screen.
  IF gv_0500_active = abap_true
     OR go_grid_0500 IS BOUND
     OR go_dock_0500 IS BOUND.
    PERFORM z16_free_0500_queue.
  ENDIF.

  "V4M: force clean 0400 toolbar even if old SE41 buttons still exist.
  APPEND 'EDIT'  TO lt_excl_0400.
  APPEND 'VALID' TO lt_excl_0400.
  APPEND 'MSG'   TO lt_excl_0400.
  APPEND 'EXPT'  TO lt_excl_0400.
  APPEND 'DETL'  TO lt_excl_0400.
  APPEND 'MREP'  TO lt_excl_0400.
  APPEND 'VALS'  TO lt_excl_0400.

  SET PF-STATUS 'STATUS_0400' EXCLUDING lt_excl_0400.
  SET TITLEBAR  'TITLE_0400'.

  "V5AK: Session ID is a display/filter aid, never a mandatory dynpro input.
  "This keeps BACK/EXIT usable when 0400 is intentionally opened empty.
  LOOP AT SCREEN.
    screen-required = '0'.
    IF screen-name = 'TXTP_SESSION_ID' OR
       screen-name = 'TXTP_SESS'.
      screen-input = '0'.
    ENDIF.
    MODIFY SCREEN.
  ENDLOOP.

  "BUP V4: learn from reference project style: Header summary + Body ALV.
  "The visible screen is a real execution cockpit; raw staging opens only in EDIT mode.
  DATA: LT_FCAT   TYPE LVC_T_FCAT,
        LS_LAYO   TYPE LVC_S_LAYO,
        LS_STABLE TYPE LVC_S_STBL.

  IF GV_0400_VIEW IS INITIAL.
    GV_0400_VIEW = GC_VIEW_COCKPIT.
  ENDIF.

  IF GT_STAGING IS NOT INITIAL.
    PERFORM z16_sync_0400_scope.
  ENDIF.

  IF GT_STAGING_ALV IS INITIAL AND GT_STAGING IS NOT INITIAL.
    PERFORM PREPARE_ALV_0400.
  ENDIF.

  IF GV_0400_VIEW = GC_VIEW_COCKPIT.
    PERFORM BUILD_EXEC_COCKPIT.
    PERFORM UPDATE_0400_COUNTERS.
  ELSE.
    READ TABLE GT_STAGING INTO DATA(LS_FIRST_0400) INDEX 1.
    IF SY-SUBRC = 0.
      TXTP_SESSION_ID = LS_FIRST_0400-SESSION_ID.
      TXTP_SESS       = LS_FIRST_0400-SESSION_ID.
    ENDIF.
  ENDIF.

  CLEAR LS_LAYO.
  LS_LAYO-CTAB_FNAME = 'CELL_COLORS'.
  LS_LAYO-CWIDTH_OPT = 'X'.
  LS_LAYO-SEL_MODE   = 'D'.
  LS_LAYO-ZEBRA      = 'X'.
  LS_STABLE-ROW      = 'X'.
  LS_STABLE-COL      = 'X'.

  IF GO_CONTAINER_0400 IS INITIAL.
    CREATE OBJECT GO_CONTAINER_0400
      EXPORTING CONTAINER_NAME = 'CC_STAGING_CONTAINER'.

    CREATE OBJECT GO_SPLIT_0400
      EXPORTING
        PARENT  = GO_CONTAINER_0400
        ROWS    = 2
        COLUMNS = 1.

    GO_CONT_HEAD_0400 = GO_SPLIT_0400->GET_CONTAINER( ROW = 1 COLUMN = 1 ).
    GO_CONT_BODY_0400 = GO_SPLIT_0400->GET_CONTAINER( ROW = 2 COLUMN = 1 ).

    CALL METHOD GO_SPLIT_0400->SET_ROW_HEIGHT
      EXPORTING
        ID     = 1
        HEIGHT = 22.
  ENDIF.

  PERFORM RENDER_0400_HEADER.

  IF GV_0400_VIEW = GC_VIEW_COCKPIT.
    IF GO_EXEC_GRID IS NOT BOUND.
      "When switching from detail to cockpit, remove old raw staging grid first.
      IF GO_STAGING_GRID IS BOUND.
        FREE GO_STAGING_GRID.
        CLEAR GO_STAGING_GRID.
      ENDIF.

      CREATE OBJECT GO_EXEC_GRID
        EXPORTING I_PARENT = GO_CONT_BODY_0400.

      PERFORM BUILD_EXEC_FIELDCAT CHANGING LT_FCAT.

      "V5AH: native sticky multi-row selection through the left row marker.
      "SEL_MODE = 'D' keeps row-selector buttons and supports multi-row selection, so users can choose
      "several READY groups without a checkbox column or holding CTRL.

      CALL METHOD GO_EXEC_GRID->SET_TABLE_FOR_FIRST_DISPLAY
        EXPORTING
          IS_LAYOUT       = LS_LAYO
        CHANGING
          IT_OUTTAB       = GT_EXEC_DISP
          IT_FIELDCATALOG = LT_FCAT.

      CREATE OBJECT G_0400_GRID_EVENTS.
      G_0400_GRID_EVENTS->CONFIGURE_0400_GRID( GO_EXEC_GRID ).
      SET HANDLER G_0400_GRID_EVENTS->ON_EXEC_DOUBLE_CLICK FOR GO_EXEC_GRID.
      "V5AK: use the native ALV multi-row selector only. The old delayed
      "callback maintained a hidden sticky selection and re-selected rows
      "after BACK/refresh, which felt like the program selected for the user.
      CALL METHOD GO_EXEC_GRID->SET_READY_FOR_INPUT
        EXPORTING I_READY_FOR_INPUT = 0.
    ELSE.
      CALL METHOD GO_EXEC_GRID->SET_READY_FOR_INPUT
        EXPORTING I_READY_FOR_INPUT = 0.
      CALL METHOD GO_EXEC_GRID->REFRESH_TABLE_DISPLAY
        EXPORTING IS_STABLE = LS_STABLE.
    ENDIF.
  ELSE.
    IF GO_STAGING_GRID IS NOT BOUND.
      "When switching from cockpit to edit, remove cockpit grid first.
      IF GO_EXEC_GRID IS BOUND.
        FREE GO_EXEC_GRID.
        CLEAR GO_EXEC_GRID.
      ENDIF.

      CREATE OBJECT GO_STAGING_GRID
        EXPORTING I_PARENT = GO_CONT_BODY_0400.

      CALL METHOD GO_STAGING_GRID->REGISTER_EDIT_EVENT
        EXPORTING I_EVENT_ID = CL_GUI_ALV_GRID=>MC_EVT_ENTER.
      CALL METHOD GO_STAGING_GRID->REGISTER_EDIT_EVENT
        EXPORTING I_EVENT_ID = CL_GUI_ALV_GRID=>MC_EVT_MODIFIED.

      PERFORM BUILD_DETAIL_FIELDCAT CHANGING LT_FCAT.

      CALL METHOD GO_STAGING_GRID->SET_TABLE_FOR_FIRST_DISPLAY
        EXPORTING
          IS_LAYOUT       = LS_LAYO
        CHANGING
          IT_OUTTAB       = GT_STAGING_ALV
          IT_FIELDCATALOG = LT_FCAT.
      GO_STAGING_GRID->SET_READY_FOR_INPUT( 1 ).
    ELSE.
      GO_STAGING_GRID->SET_READY_FOR_INPUT( 1 ).
      CALL METHOD GO_STAGING_GRID->REFRESH_TABLE_DISPLAY
        EXPORTING IS_STABLE = LS_STABLE.
    ENDIF.
  ENDIF.
ENDMODULE.


*&=====================================================================*
*& V7 PRO - PBO MODULES FOR 14 SCREEN LIFECYCLE
*&=====================================================================*
MODULE status_0250 OUTPUT.
  "Obsolete placeholder only. Current capstone flow does not call screen 0250.
  "Keep this module to avoid dynpro activation issues if the old screen still exists.
  SET PF-STATUS 'STATUS_0100'.
  SET TITLEBAR  'TITLE_0100'.
ENDMODULE.

MODULE status_0350 OUTPUT.
  "0350 is a standalone Mapping Configuration screen.
  "0300 stays as Upload Center; 0350 handles only mapping profile maintenance.
  SET PF-STATUS 'STATUS_0350'.
  PERFORM display_mapping_screen.
ENDMODULE.

MODULE status_0500 OUTPUT.
  "V5F: 0500 is driven by ALV toolbar only.
  "For BDC mode A (All screens), SAP itself is the live progress UI,
  "so the static progress block is hidden and the queue is fixed larger.
  DATA lt_excl_0500 TYPE STANDARD TABLE OF sy-ucomm.
  DATA lv_0500_mode TYPE c LENGTH 1.
  DATA lv_0500_upd  TYPE c LENGTH 1.
  DATA lv_0500_bsz  TYPE i.

  PERFORM get_runtime_options CHANGING lv_0500_mode lv_0500_upd lv_0500_bsz.

  APPEND 'EXEC'        TO lt_excl_0500.
  APPEND 'SM35'        TO lt_excl_0500.
  APPEND 'STOP'        TO lt_excl_0500.
  APPEND 'REFR'        TO lt_excl_0500.
  APPEND 'GT06'        TO lt_excl_0500.
  APPEND 'RESULT'      TO lt_excl_0500.
  APPEND 'DASHBOARD'   TO lt_excl_0500.
  APPEND 'CREATE_SM35' TO lt_excl_0500.

  SET PF-STATUS 'STATUS_0500' EXCLUDING lt_excl_0500.
  SET TITLEBAR  'TITLE_0500'.
  gv_0500_active = abap_true.
  PERFORM init_execution_monitor.
  PERFORM z16_display_0500_queue.

  "Screen 0500 keeps only readonly progress fields. Any old option fields
  "from earlier prototypes are hidden/disabled so the logic is not confused
  "with BDC Mode A/E/N or Update Mode S/A from screen 0100.
  LOOP AT SCREEN.
    screen-required = '0'.

    "Old prototype options are permanently hidden. Engine selection is now
    "done by ALV actions: Execute Queue or Create SM35 Session.
    IF screen-name = 'CHKP_STOP_ON_ERROR' OR
       screen-name = 'CHKP_BACKGROUND' OR
       screen-name = 'TXTP_PARALLEL_TASKS' OR
       screen-name = 'P_PAR_TASKS' OR
       screen-name = 'TXTGV_PAR_TASKS'.
      screen-active = '0'.
      screen-input  = '0'.
    ENDIF.

    "V5AL: keep the 0500 progress block visible for A/E/N.  In A mode the
    "active SAP transaction still owns the GUI while one document is being
    "processed, but the monitor is painted before the call and refreshed at
    "every real document-group boundary after control returns.

    MODIFY SCREEN.
  ENDLOOP.
ENDMODULE.

MODULE status_0550 OUTPUT.
  SET PF-STATUS 'STATUS_0550'.
  SET TITLEBAR  'TITLE_0550'.
ENDMODULE.

MODULE status_0551 OUTPUT.
  "Header fields are global screen fields filled in read_popup_detail.
ENDMODULE.

MODULE status_0552 OUTPUT.
  "Item fields are global screen fields filled in read_popup_detail.
ENDMODULE.

MODULE status_0560 OUTPUT.
  SET PF-STATUS 'STATUS_0560'.
  SET TITLEBAR  'TITLE_0560'.

  "V5L: mass-replace fields are optional until the user chooses Apply/Save.
  "Removing the dynpro mandatory flag lets Back/Cancel work even when no
  "field/value was entered and avoids the automatic mandatory-field popup.
  LOOP AT SCREEN.
    IF screen-name = 'P_FLD_NAME'
       OR screen-name = 'P_OLD_VAL'
       OR screen-name = 'P_NEW_VAL'.
      screen-required = '0'.
      MODIFY SCREEN.
    ENDIF.
  ENDLOOP.
ENDMODULE.

MODULE status_0600 OUTPUT.
  SET PF-STATUS 'STATUS_0600'.
  SET TITLEBAR  'TITLE_0600'.
  PERFORM z17_start_0600_timer.
ENDMODULE.

MODULE status_0601 OUTPUT.
  PERFORM load_results_0600.
  PERFORM display_result_grid USING 'CC_SUMMARY_CONTAINER'
    CHANGING go_container_0601 go_grid_0601 gt_result_summary.
ENDMODULE.

MODULE status_0602 OUTPUT.
  PERFORM display_result_record_grid.
ENDMODULE.

MODULE status_0603 OUTPUT.
  PERFORM load_results_0600.
  PERFORM display_result_grid USING 'CC_MSG_CONTAINER'
    CHANGING go_container_0603 go_grid_0603 gt_result_msg.
ENDMODULE.

MODULE status_0650 OUTPUT.
  SET PF-STATUS 'STATUS_0650'.
  SET TITLEBAR  'TITLE_0650'.
  PERFORM display_result_detail.
ENDMODULE.

MODULE status_0651 OUTPUT.
  "Scrollable detail fields are global screen fields.
ENDMODULE.

MODULE status_0700 OUTPUT.
  SET PF-STATUS 'STATUS_0700'.
  SET TITLEBAR  'TITLE_0700'.
  PERFORM display_ai_patterns.
ENDMODULE.

MODULE status_0750 OUTPUT.
  SET PF-STATUS 'STATUS_0750'.
  SET TITLEBAR  'TITLE_0750'.
  PERFORM display_ai_archive.
ENDMODULE.

MODULE status_0800 OUTPUT.
  SET PF-STATUS 'STATUS_0800'.
  SET TITLEBAR  'TITLE_0800'.
  PERFORM display_script_editor.
ENDMODULE.
