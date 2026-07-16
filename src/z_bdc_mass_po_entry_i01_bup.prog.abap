*&---------------------------------------------------------------------*
*& Include          Z_BDC_MASS_PO_ENTRY_I01_BUP (PAI)
*& LEGACY-FLOW PATCH: keep FIX15B flow, screen 0250 is out of scope
*&---------------------------------------------------------------------*

MODULE user_command_0100 INPUT.
  DATA: lv_count_0100 TYPE i,
        lv_row_idx    TYPE i,
        lv_session_id TYPE zbdc_staging_bup-session_id.

  save_ok = ok_code.
  CLEAR ok_code.

  CASE save_ok.
    WHEN 'NEW_UPLOAD' OR 'NEWUP' OR 'NUPL' OR 'NEWU' OR 'FC_NEW_UPLOAD' OR 'FC_NEW_UPLD'
      OR 'VIEW_SESSION' OR 'VIEWSESS' OR 'VSES' OR 'VSESS' OR 'VIEW' OR 'FC_VIEW_SESSION' OR 'FC_VIEW_SESS'
      OR 'RESUBMIT' OR 'RSUB' OR 'RSUBM' OR 'RESB' OR 'FC_RESUBMIT' OR 'FC_RSUB'.
      MESSAGE 'Button removed from 0100. Use Upload Excel, Staging, or Execution Monitor.' TYPE 'S' DISPLAY LIKE 'I'.

    WHEN 'GT02' OR 'FC_GOTO_0200' OR 'CONFIG' OR 'CFG'.
      CALL SCREEN 0200.

    WHEN 'GT25' OR 'JOB' OR 'SCHED' OR 'FC_GOTO_0250'.
      MESSAGE '0250 removed from scope; use 0200 config or SM37 for jobs.' TYPE 'I'.

    WHEN 'GT03' OR 'FC_GOTO_0300' OR 'UPLOAD' OR 'INGEST'.
      PERFORM z16_clear_0300_runtime.
      CALL SCREEN 0300.

    WHEN 'GT35' OR 'MAP' OR 'MAPPING' OR 'FC_GOTO_0350'.
      MESSAGE 'Mapping screen removed from navigation. Mapping is applied automatically from ZBDC_MAPPING_BUP.' TYPE 'S' DISPLAY LIKE 'I'.

    WHEN 'GT04' OR 'STAGING' OR 'REVIEW' OR 'FC_GOTO_0400'.
      CLEAR lv_session_id.
      IF go_grid_0100 IS BOUND.
        cl_gui_cfw=>flush( ).
        DATA(lo_selections) = go_grid_0100->get_selections( ).
        DATA(lt_rows) = lo_selections->get_selected_rows( ).
        IF lt_rows IS NOT INITIAL.
          READ TABLE lt_rows INTO lv_row_idx INDEX 1.
          READ TABLE gt_sessions INTO DATA(ls_selected_sess) INDEX lv_row_idx.
          IF sy-subrc = 0.
            lv_session_id = ls_selected_sess-session_id.
          ENDIF.
        ENDIF.
      ENDIF.
      IF lv_session_id IS NOT INITIAL.
        PERFORM load_staging_by_session USING lv_session_id CHANGING lv_count_0100.
        PERFORM open_0400_for_current_staging.
      ELSE.
        "No implicit history load: Staging opens as an empty workspace until
        "the user uploads data or explicitly chooses a batch/session.
        PERFORM z19_open_0400_empty.
      ENDIF.

    WHEN 'GT05' OR 'EXECUTE' OR 'EXEC' OR 'FC_GOTO_0500'.
      IF gt_staging IS INITIAL.
        PERFORM load_latest_staging_for_tcode USING p_transaction CHANGING lv_count_0100.
      ENDIF.
      CALL SCREEN 0500.

    WHEN 'GT06' OR 'RESULT' OR 'RESULTS' OR 'FC_GOTO_0600'.
      PERFORM refresh_current_dashboard.
      MESSAGE 'Result Dashboard is shown on Main Dashboard 0100.' TYPE 'S'.

    WHEN 'GT07' OR 'AI' OR 'ANALYST' OR 'FC_GOTO_0700'.
      CALL SCREEN 0700.

    WHEN 'GT75' OR 'KBAS' OR 'KNOWLEDGE' OR 'FC_GOTO_0750'.
      CALL SCREEN 0750.

    WHEN 'GT08' OR 'SHDB' OR 'SCRIPT' OR 'FC_GOTO_0800'.
      CALL SCREEN 0800.

    WHEN 'REFR' OR 'REFRESH' OR 'FC_REFRESH'.
      PERFORM refresh_current_dashboard.

    WHEN 'BACK' OR 'EXIT' OR 'CANCEL' OR 'CANC' OR '&F03' OR '&F12' OR '&F15'.
      LEAVE PROGRAM.
  ENDCASE.
ENDMODULE.

MODULE user_command_0200 INPUT.
  DATA LV_GO_0200 TYPE C LENGTH 1.

  save_ok = ok_code.
  CLEAR ok_code.

  CASE save_ok.
    WHEN 'SAVE' OR '&DATA_SAVE'.
      PERFORM save_source_config.

    WHEN 'TCON' OR 'FC_TEST_CONN'.
      PERFORM test_inbound_connection.

    WHEN 'GT25' OR 'JOB' OR 'SCHED'.
      PERFORM save_source_config.
      MESSAGE '0250 removed from scope; source config saved.' TYPE 'S'.

    WHEN 'GT03' OR 'FC_GOTO_0300' OR 'UPLOAD' OR 'INGEST' OR 'NEXT_UPLOAD'.
      PERFORM confirm_0200_leave CHANGING LV_GO_0200.
      IF LV_GO_0200 IS INITIAL.
        RETURN.
      ENDIF.
      PERFORM z16_clear_0300_runtime.
      CALL SCREEN 0300.

    WHEN 'GT35' OR 'MAP' OR 'MAPPING'.
      MESSAGE 'Mapping screen removed from navigation. Mapping profile is resolved automatically.' TYPE 'S' DISPLAY LIKE 'I'.

    WHEN 'GT04' OR 'FC_GOTO_0400' OR 'STAGING' OR 'REVIEW'.
      MESSAGE 'Open Staging from 0300 after upload, or from 0100 dashboard.' TYPE 'S' DISPLAY LIKE 'W'.

    WHEN 'GT05' OR 'NEXT' OR 'EXEC' OR 'EXECUTE'.
      PERFORM confirm_0200_leave CHANGING LV_GO_0200.
      IF LV_GO_0200 IS INITIAL.
        RETURN.
      ENDIF.
      CALL SCREEN 0500.

    WHEN 'GT08' OR 'SHDB' OR 'SCRIPT'.
      PERFORM confirm_0200_leave CHANGING LV_GO_0200.
      IF LV_GO_0200 IS INITIAL.
        RETURN.
      ENDIF.
      CALL SCREEN 0800.

    WHEN 'BACK' OR 'EXIT' OR 'CANCEL' OR 'CANC' OR '&F03' OR '&F12' OR '&F15'.
      PERFORM confirm_0200_leave CHANGING LV_GO_0200.
      IF LV_GO_0200 IS INITIAL.
        RETURN.
      ENDIF.
      CLEAR gv_config_loaded.
      SET SCREEN 0.
      LEAVE SCREEN.
  ENDCASE.
ENDMODULE.


MODULE exit_0300 INPUT.
  DATA lv_exit_0300 TYPE sy-ucomm.

  lv_exit_0300 = ok_code.
  IF lv_exit_0300 IS INITIAL.
    lv_exit_0300 = sy-ucomm.
  ENDIF.

  CASE lv_exit_0300.
    WHEN 'BACK' OR 'EXIT' OR 'CANCEL' OR 'CANC'
      OR '&F03' OR '&F12' OR '&F15'
      OR 'RW' OR 'ENDE' OR 'ECAN'.
      CLEAR ok_code.
      PERFORM z16_clear_0300_runtime.
      SET SCREEN 0.
      LEAVE SCREEN.
  ENDCASE.
ENDMODULE.

MODULE user_command_0300 INPUT.
  DATA: lv_count_0300  TYPE i,
        lv_source_0300 TYPE char20.

  save_ok = ok_code.
  IF save_ok IS INITIAL.
    save_ok = sy-ucomm.
  ENDIF.

  CLEAR ok_code.

  CASE save_ok.

    WHEN 'BACK' OR 'EXIT' OR 'CANCEL' OR 'CANC'
      OR '&F03' OR '&F12' OR '&F15'
      OR 'RW' OR 'ENDE' OR 'ECAN'.
      PERFORM z16_clear_0300_runtime.
      SET SCREEN 0.
      LEAVE SCREEN.

    WHEN 'GT02' OR 'FC_GOTO_0200' OR 'CONFIG' OR 'CFG'.
      CALL SCREEN 0200.

    WHEN 'GT35' OR 'MAP' OR 'MAPPING' OR 'FC_GOTO_0350'.
      "Mapping is intentionally removed from Upload Center navigation.
      "The parser/BDC engine still uses ZBDC_MAPPING_BUP automatically.
      g_sub_dynpro = '0301'.
      PERFORM reset_0300_alv.
      MESSAGE 'Mapping UI is not part of 0300. Mapping is applied automatically from ZBDC_MAPPING_BUP.' TYPE 'S' DISPLAY LIKE 'I'.

    WHEN 'TAB_PREVIEW' OR 'PREV' OR 'PREVIEW' OR 'PREVIEW_DATA' OR 'FC_PREV' OR 'FC_PREVIEW'.
      g_sub_dynpro = '0301'.
      PERFORM reset_0300_alv.
      IF gt_staging IS INITIAL.
        MESSAGE 'No current upload data. Upload first, or press Refresh to load latest staging.' TYPE 'S' DISPLAY LIKE 'W'.
      ELSE.
        lv_count_0300 = lines( gt_staging ).
        MESSAGE |Preview Data: { lv_count_0300 } current upload rows.| TYPE 'S'.
      ENDIF.

    WHEN 'BTN_BROWSE' OR 'FC_BROWSE' OR 'BROWSE' OR 'BROW'
      OR 'BROWSE_LOCAL' OR 'PICK_FILE' OR 'PICK' OR 'PICK_LOCAL'.
      "Browse beside File Path is the inbound-source chooser.
      "It restores the 4 channels: Local, Google Drive, REST/Email and SFTP.
      PERFORM select_inbound_channel.
      g_sub_dynpro = '0301'.
      PERFORM reset_0300_alv.
      IF gt_staging IS INITIAL.
        "Browse is selection-only. Keep all counters at 0 until Upload/Ingest.
        PERFORM z16_set_row_count_fields USING 0.
        IF txtp_file_size IS INITIAL.
          txtp_file_size = '0 B'.
        ENDIF.
      ENDIF.
      IF txtp_file_path IS INITIAL.
        MESSAGE 'No inbound file/source selected.' TYPE 'S' DISPLAY LIKE 'W'.
      ENDIF.

    WHEN 'TAB_ERRORS' OR 'TAB_FILES' OR 'PV_FILE'
      OR 'PREVIEW_FILE' OR 'FILES'.
      "Preview Files is controlled only by the tab/function itself.
      "Do not reuse FC_BROWSE here because the screen Browse button uses it.
      PERFORM z16_prepare_preview_file.
      g_sub_dynpro = '0302'.
      PERFORM reset_0300_alv.
      MESSAGE 'Preview File/Source opened.' TYPE 'S'.

    WHEN 'FC_DL_TMPL' OR 'DLTMPL' OR 'DL_TMPL' OR 'DOWNLOAD_TEMPLATE' OR 'TMPL'.
      PERFORM download_template.
      g_sub_dynpro = '0301'.
      PERFORM reset_0300_alv.

    WHEN 'UPLD' OR 'FC_UPLOAD_EXEC' OR 'UPLOAD_EXEC' OR 'INGEST_NOW'.
      "Generic Upload/Ingest button: execute the source selected by Browse.
      "The URI prefix determines which of the 4 channels is processed.
      IF txtp_file_path IS INITIAL.
        MESSAGE 'Choose Local, Google Drive, REST/Email or SFTP with Browse first.' TYPE 'S' DISPLAY LIKE 'W'.
      ELSE.
        CLEAR lv_source_0300.
        IF txtp_file_path CP 'GoogleDrive://*'.
          lv_source_0300 = 'GDRIVE'.
        ELSEIF txtp_file_path CP 'REST_API://*'
            OR txtp_file_path CP 'MAILBOX://*'.
          lv_source_0300 = 'REST'.
        ELSEIF txtp_file_path CP 'SFTP://*'.
          lv_source_0300 = 'SFTP'.
        ELSE.
          lv_source_0300 = 'LOCAL'.
        ENDIF.

        PERFORM upload_and_parse_excel.
        PERFORM z16_0300_after_ingest USING lv_source_0300.
      ENDIF.
      "V5DB: Z16_0300_AFTER_INGEST keeps Preview Data active and schedules a PBO rebuild.
      cl_gui_cfw=>flush( ).

    WHEN 'FC_UPLD_LOCAL' OR 'LOCAL' OR 'ULOC'.
      "Direct Local action remains supported when STATUS_0300 has a dedicated button.
      IF txtp_file_path IS INITIAL OR txtp_file_path CP '*://*'.
        PERFORM browse_file.
      ENDIF.
      IF txtp_file_path IS NOT INITIAL AND txtp_file_path NP '*://*'.
        PERFORM upload_and_parse_excel.
        PERFORM z16_0300_after_ingest USING 'LOCAL'.
      ELSEIF txtp_file_path IS INITIAL.
        MESSAGE 'Choose one local file first.' TYPE 'S' DISPLAY LIKE 'W'.
      ENDIF.
      "V5DB: keep Preview Data selected by Z16_0300_AFTER_INGEST.
      cl_gui_cfw=>flush( ).

    WHEN 'FC_UPLD_GDRIVE' OR 'GDRIVE' OR 'UDRV'.
      PERFORM select_gdrive_file_path.
      IF txtp_file_path CP 'GoogleDrive://*'.
        PERFORM upload_and_parse_excel.
        PERFORM z16_0300_after_ingest USING 'GDRIVE'.
      ENDIF.
      "V5DB: keep Preview Data selected by Z16_0300_AFTER_INGEST.
      cl_gui_cfw=>flush( ).

    WHEN 'FC_UPLD_REST' OR 'REST' OR 'URES'.
      PERFORM upload_from_rest.
      PERFORM z16_0300_after_ingest USING 'REST'.
      "V5DB: keep Preview Data selected by Z16_0300_AFTER_INGEST.
      cl_gui_cfw=>flush( ).

    WHEN 'FC_UPLD_SFTP' OR 'SFTP' OR 'USFT'.
      PERFORM upload_from_sftp.
      IF txtp_file_path CP 'SFTP://*'.
        PERFORM upload_and_parse_excel.
        PERFORM z16_0300_after_ingest USING 'SFTP'.
      ENDIF.
      "V5DB: keep Preview Data selected by Z16_0300_AFTER_INGEST.
      cl_gui_cfw=>flush( ).

    WHEN 'FC_UPLD_SHDB' OR 'UPLOAD_REC' OR 'SHDB' OR 'USHD' OR 'GT08'.
      PERFORM upload_shdb_recording.
      g_sub_dynpro = '0302'.
      PERFORM reset_0300_alv.
      CALL SCREEN 0800.

    WHEN 'VALID' OR 'VALD' OR 'FC_VALID' OR 'CHECK'.
      "Do not silently validate old DB rows from a previous upload.
      IF gt_staging IS INITIAL.
        MESSAGE 'No current upload data to validate. Upload first, or press Refresh intentionally.' TYPE 'W'.
      ELSE.
        PERFORM resolve_profile_by_tcode USING p_transaction.
        REFRESH gt_staging_alv.
        PERFORM prepare_alv_0400.
        PERFORM upd_all_rt_sess_sum.
        MESSAGE |Validated preview: { lines( gt_staging_alv ) } rows.| TYPE 'S'.
        g_sub_dynpro = '0301'.
        PERFORM reset_0300_alv.
      ENDIF.

    WHEN 'GT04' OR 'STAGING' OR 'FC_UPLOAD_REVIEW' OR 'REVIEW'.
      "Staging from Upload Center should use current upload rows only.
      "Press Refresh explicitly if the user wants to load latest DB staging.
      IF gt_staging IS NOT INITIAL.
        PERFORM open_0400_for_current_staging.
      ELSE.
        MESSAGE 'No current upload data. Upload first, or press Refresh then Staging.' TYPE 'W'.
      ENDIF.

    WHEN 'GT05' OR 'FC_UPLOAD_EXEC' OR 'NEXT' OR 'FC_NEXT' OR 'EXEC' OR 'EXECUTE'.
      IF gt_staging IS INITIAL.
        MESSAGE 'No current upload data to execute. Upload first, or go to Staging/Dashboard.' TYPE 'W'.
      ELSE.
        CALL SCREEN 0500.
      ENDIF.

    WHEN 'REFR' OR 'REFRESH' OR 'FC_REFRESH'.
      "Refresh follows the active tab.
      "Preview Files = reload upload/source history.
      "Preview Data  = reload latest staging only by explicit user action.
      IF g_sub_dynpro = '0302' OR ts_preview-activetab = 'TAB_FILES'.
        PERFORM z16_prepare_preview_file.
        g_sub_dynpro = '0302'.
        PERFORM reset_0300_alv.
        MESSAGE |Reloaded { lines( gt_files_preview ) } uploaded file/source log rows.| TYPE 'S'.
      ELSE.
        PERFORM load_latest_staging_for_tcode USING p_transaction CHANGING lv_count_0300.
        g_sub_dynpro = '0301'.
        PERFORM reset_0300_alv.
        MESSAGE |Reloaded { lv_count_0300 } latest staging rows for { p_transaction }.| TYPE 'S'.
      ENDIF.

    WHEN OTHERS.
      MESSAGE |0300 function not handled: { save_ok }| TYPE 'S' DISPLAY LIKE 'W'.

  ENDCASE.
ENDMODULE.


MODULE user_command_0250 INPUT.
  save_ok = ok_code.
  CLEAR ok_code.
  CASE save_ok.
    WHEN 'SCHD' OR 'SCHEDULE'.
      PERFORM schedule_job_0250.
    WHEN 'STOP'.
      PERFORM stop_job_0250.
    WHEN 'REFR' OR 'REFRESH'.
      PERFORM display_jobs_0250.
    WHEN 'BACK' OR 'EXIT' OR 'CANCEL' OR 'CANC' OR '&F03' OR '&F12' OR '&F15'.
      SET SCREEN 0.
      LEAVE SCREEN.
  ENDCASE.
ENDMODULE.


MODULE exit_0350 INPUT.
  DATA lv_exit_0350 TYPE sy-ucomm.

  lv_exit_0350 = ok_code.
  IF lv_exit_0350 IS INITIAL.
    lv_exit_0350 = sy-ucomm.
  ENDIF.

  CASE lv_exit_0350.
    WHEN 'BACK' OR 'EXIT' OR 'CANCEL' OR 'CANC'
      OR '&F03' OR '&F12' OR '&F15'
      OR 'RW' OR 'ENDE' OR 'ECAN'.
      CLEAR ok_code.
      SET SCREEN 0.
      LEAVE SCREEN.
  ENDCASE.
ENDMODULE.

MODULE user_command_0350 INPUT.
  save_ok = ok_code.
  IF save_ok IS INITIAL.
    save_ok = sy-ucomm.
  ENDIF.

  CLEAR ok_code.

  CASE save_ok.
    WHEN 'SAVE' OR '&DATA_SAVE'.
      PERFORM save_mapping_screen.
      PERFORM display_mapping_screen.

    WHEN 'ADDR' OR 'INSR' OR 'INSERT'.
      PERFORM insert_mapping_row.
      PERFORM display_mapping_screen.

    WHEN 'DELR' OR 'DELETE'.
      PERFORM delete_mapping_row.
      PERFORM display_mapping_screen.

    WHEN 'REFR' OR 'REFRESH' OR 'FC_REFRESH'.
      PERFORM load_mapping_screen.
      PERFORM display_mapping_screen.
      MESSAGE 'Mapping refreshed.' TYPE 'S'.

    WHEN 'GT04' OR 'STAGING' OR 'FC_UPLOAD_REVIEW' OR 'REVIEW'.
      IF gt_staging IS NOT INITIAL.
        PERFORM open_0400_for_current_staging.
      ELSE.
        MESSAGE 'No current upload data in memory. Return to Upload Center or Refresh staging first.' TYPE 'W'.
      ENDIF.

    WHEN 'GT03' OR 'UPLOAD' OR 'INGEST' OR 'FC_GOTO_0300'.
      SET SCREEN 0.
      LEAVE SCREEN.

    WHEN 'BACK' OR 'EXIT' OR 'CANCEL' OR 'CANC'
      OR '&F03' OR '&F12' OR '&F15'
      OR 'RW' OR 'ENDE' OR 'ECAN'.
      PERFORM z19_reset_0400_selection.
      SET SCREEN 0.
      LEAVE SCREEN.

    WHEN OTHERS.
      MESSAGE |0350 function not handled: { save_ok }| TYPE 'S' DISPLAY LIKE 'W'.
  ENDCASE.
ENDMODULE.



MODULE user_command_0400 INPUT.
  DATA: lt_process_0400 TYPE STANDARD TABLE OF ty_staging_alv,
        lv_ok_0400      TYPE abap_bool,
        lv_count_0400   TYPE i,
        lv_session_0400 TYPE zbdc_staging_bup-session_id.

  "V5AB: only an explicit screen function code may navigate or execute.
  "Checkbox toggles are ALV edits, not commands. Returning immediately on
  "a blank OK_CODE prevents a stale SY-UCOMM (for example EXSL) from being
  "executed again after the first checkbox click.
  CLEAR save_ok.
  save_ok = ok_code.
  CLEAR: ok_code, sy-ucomm.

  IF save_ok IS INITIAL.
    RETURN.
  ENDIF.

  CASE save_ok.
    WHEN 'EXAL' OR 'RUN_ALL' OR 'RUNALL' OR 'EXEC_ALL' OR 'EXECUTE_ALL'.
      "Flow B: 0400 is review/scope selection; 0500 is the real executor.
      PERFORM prepare_0500_exec_scope
        USING    'ALL'
        CHANGING lv_count_0400 lv_ok_0400.
      IF lv_ok_0400 <> abap_true.
        MESSAGE 'No READY group to send to 0500.' TYPE 'W'.
        RETURN.
      ENDIF.
      MESSAGE |Scope loaded: { lv_count_0400 } READY group(s). Execute in 0500.| TYPE 'S'.
      CALL SCREEN 0500.

    WHEN 'EXSL' OR 'RUN_SEL' OR 'RUN_SELECTED' OR 'EXEC_SELECTED'.
      "Flow B: selected rows are captured before leaving 0400.
      PERFORM prepare_0500_exec_scope
        USING    'SELECTED'
        CHANGING lv_count_0400 lv_ok_0400.
      IF lv_ok_0400 <> abap_true.
        MESSAGE 'Select at least one READY group before opening 0500.' TYPE 'W'.
        RETURN.
      ENDIF.
      MESSAGE |Selected scope loaded: { lv_count_0400 } READY group(s). Execute in 0500.| TYPE 'S'.
      CALL SCREEN 0500.

    WHEN 'REFR' OR 'REFRESH' OR 'FC_REFRESH'.
      CLEAR lv_session_0400.
      IF txtp_session_id IS NOT INITIAL.
        lv_session_0400 = txtp_session_id.
      ELSEIF txtp_sess IS NOT INITIAL.
        lv_session_0400 = txtp_sess.
      ENDIF.

      IF gv_current_batch_prefix IS NOT INITIAL.
        PERFORM z16_load_staging_by_batch USING gv_current_batch_prefix CHANGING lv_count_0400.
      ELSEIF lv_session_0400 IS NOT INITIAL.
        PERFORM z16_resolve_batch_from_session USING lv_session_0400 CHANGING gv_current_batch_prefix.
        IF gv_current_batch_prefix IS NOT INITIAL.
          PERFORM z16_load_staging_by_batch USING gv_current_batch_prefix CHANGING lv_count_0400.
        ELSE.
          PERFORM load_staging_by_session USING lv_session_0400 CHANGING lv_count_0400.
        ENDIF.
      ENDIF.
      PERFORM prepare_alv_0400.
      PERFORM build_exec_cockpit.
      PERFORM update_0400_counters.
      PERFORM refresh_0400_grid.
      MESSAGE |Staging cockpit refreshed. Rows: { lv_count_0400 }| TYPE 'S'.

        WHEN 'GT05' OR 'MONITOR' OR 'EXEC_LOG' OR 'EXECUTION_LOG' OR 'FC_GOTO_0500'.
      "V4P: restore the agreed flow 0400 -> 0500.
      "0400 stays as the group-processing cockpit; 0500 is the execution log/monitor.
      CLEAR lv_session_0400.
      IF txtp_session_id IS NOT INITIAL.
        lv_session_0400 = txtp_session_id.
      ELSEIF txtp_sess IS NOT INITIAL.
        lv_session_0400 = txtp_sess.
      ENDIF.

      IF gt_staging IS INITIAL.
        IF gv_current_batch_prefix IS NOT INITIAL.
          PERFORM z16_load_staging_by_batch USING gv_current_batch_prefix CHANGING lv_count_0400.
        ELSEIF lv_session_0400 IS NOT INITIAL.
          PERFORM z16_resolve_batch_from_session USING lv_session_0400 CHANGING gv_current_batch_prefix.
          IF gv_current_batch_prefix IS NOT INITIAL.
            PERFORM z16_load_staging_by_batch USING gv_current_batch_prefix CHANGING lv_count_0400.
          ELSE.
            PERFORM load_staging_by_session USING lv_session_0400 CHANGING lv_count_0400.
          ENDIF.
        ENDIF.
      ENDIF.

      CALL SCREEN 0500.

    WHEN 'GT06' OR 'RESULT' OR 'RESULTS' OR 'DASHBOARD' OR 'FC_GOTO_0600'.
      PERFORM z16_open_result_dash_curr.
 WHEN 'BACK' OR 'EXIT' OR 'CANCEL' OR 'CANC'
      OR '&F03' OR '&F12' OR '&F15'
      OR 'RW' OR 'ENDE' OR 'ECAN'.
      SET SCREEN 0.
      LEAVE SCREEN.

    WHEN OTHERS.
      MESSAGE |0400 function not handled: { save_ok }| TYPE 'S' DISPLAY LIKE 'W'.
  ENDCASE.
ENDMODULE.

MODULE user_command_0500 INPUT.
  save_ok = ok_code.
  CLEAR ok_code.

  "V5G: 0500 top GUI status no longer owns execution actions.
  "Execute / SM35 / Stop / Refresh / Dashboard are handled only by the
  "Execution Queue ALV toolbar, so deleting those buttons from STATUS_0500
  "is safe and no duplicated top-toolbar command can trigger execution.
  CASE save_ok.
    WHEN 'ZRUN500'.
      PERFORM z19_execute_pending_0500.
    WHEN 'ZREF500'.
      "Internal roundtrip: the next PBO repaints progress and queue data.
    WHEN 'ZLIVE50'.
      "True non-blocking live monitor tick. PAI stays short; the following
      "PBO paints elapsed time, phase, queue status, and factual completion.
      PERFORM z22_monitor_0500_tick.
    WHEN 'BACK' OR 'EXIT' OR 'CANCEL' OR 'CANC' OR '&F03' OR '&F12' OR '&F15'.
      "V5AK: BACK is always available. Cancel pending frontend commands,
      "release the full-client control and clear the old row selection before
      "returning to 0400.
      IF gv_exec_run_active = abap_true OR gv_async_active = abap_true.
        MESSAGE 'Execution is still running. Use Stop Queue or wait for the current document to finish.' TYPE 'S' DISPLAY LIKE 'W'.
        RETURN.
      ENDIF.
      PERFORM z22_stop_0500_timer.
      CLEAR: gv_0500_pending_run, gv_0500_pending_engine,
             gv_0500_confirmed, gv_exec_run_active, gv_exec_run_engine,
             gv_exec_run_phase, gv_async_active, gv_async_done,
             gv_async_receive_rc, gv_async_subrc, gv_async_message.
      PERFORM z19_reset_0400_selection.
      PERFORM z16_free_0500_queue.
      LEAVE TO SCREEN 0.
    WHEN OTHERS.
      "No action here by design. 0500 business actions are ALV toolbar only.
  ENDCASE.
ENDMODULE.

MODULE user_command_0550 INPUT.
  save_ok = ok_code.
  CLEAR ok_code.
  CASE save_ok.
    WHEN 'TAB_H' OR 'TAB_HEADER'.
      g_detail_sub = '0551'.
    WHEN 'TAB_I' OR 'TAB_ITEM'.
      g_detail_sub = '0552'.
    WHEN 'SAVE' OR '&DATA_SAVE'.
      PERFORM update_popup_detail.
      MESSAGE 'Detail saved to staging.' TYPE 'S'.
    WHEN 'VALID' OR 'VAGN' OR 'CHECK'.
      PERFORM z16_validate_curr_corr.
    WHEN 'RSUB' OR 'RESUBMIT'.
      PERFORM resubmit_popup_detail.
    WHEN 'BACK' OR 'EXIT' OR 'CANCEL' OR 'CANC' OR '&F03' OR '&F12' OR '&F15'.
      SET SCREEN 0.
      LEAVE SCREEN.
  ENDCASE.
ENDMODULE.

MODULE user_command_0560 INPUT.
  save_ok = ok_code.
  CLEAR ok_code.
  CASE save_ok.
    WHEN 'RPAL' OR 'APPLY'.
      PERFORM apply_mass_replace.
    WHEN 'RTSL' OR 'RETRY' OR 'RSUB'.
      PERFORM z16_0560_retry_to_0500.
    WHEN 'REFR' OR 'REFRESH'.
      PERFORM z16_0560_refresh.
    WHEN 'FC_EXP_FIX' OR 'EXPT' OR 'EXPORT'.
      PERFORM z16_0560_export_fix.
    WHEN 'LDFL' OR 'LOAD'.
      PERFORM z16_0560_load_fixed_file.
    WHEN 'SVFX' OR 'SAVE'.
      PERFORM z16_0560_save_fix.
    WHEN 'VAGN' OR 'VALID' OR 'CHECK'.
      PERFORM z16_0560_validate_again.
    WHEN 'BACK' OR 'EXIT' OR 'CANCEL' OR 'CANC' OR '&F03' OR '&F12' OR '&F15'.
      SET SCREEN 0.
      LEAVE SCREEN.
  ENDCASE.
ENDMODULE.

MODULE user_command_0600 INPUT.
  save_ok = ok_code.
  CLEAR ok_code.
  CASE save_ok.
    WHEN 'GT61' OR 'TAB_SUMMARY' OR 'SUMMARY'.
      g_result_sub = '0601'.
      PERFORM load_results_0600.
    WHEN 'GT62' OR 'TAB_RECORD' OR 'RECORDS'.
      g_result_sub = '0602'.
      PERFORM load_results_0600.
    WHEN 'GT63' OR 'TAB_MSG' OR 'MESSAGES'.
      g_result_sub = '0603'.
      PERFORM load_results_0600.
    WHEN 'REFR' OR 'REFRESH' OR 'AUTOREF'.
      PERFORM load_results_0600.
    WHEN 'DETL' OR 'DRILL'.
      PERFORM open_result_detail_selected.
    WHEN 'RETR' OR 'RETRY'.
      PERFORM retry_error_records_0600.
    WHEN 'EXPT' OR 'EXPORT' OR 'FC_EXPORT'.
      PERFORM export_session_log_csv.
    WHEN 'FC_AI_ANAL' OR 'AI' OR 'GT07'.
      CALL SCREEN 0700.
    WHEN 'GT75' OR 'KBAS' OR 'KNOWLEDGE'.
      CALL SCREEN 0750.
    WHEN 'BACK' OR 'EXIT' OR 'CANCEL' OR 'CANC' OR '&F03' OR '&F12' OR '&F15'.
      PERFORM z17_stop_0600_timer.
      SET SCREEN 0.
      LEAVE SCREEN.
  ENDCASE.
ENDMODULE.

MODULE user_command_0650 INPUT.
  save_ok = ok_code.
  CLEAR ok_code.
  CASE save_ok.
    WHEN 'REFL' OR 'REFR' OR 'REFRESH'.
      PERFORM load_result_detail.
      PERFORM display_result_detail.
    WHEN 'COPY' OR 'CPY'.
      MESSAGE txtp_result_msg TYPE 'I'.
    WHEN 'FC_EXP_ERR' OR 'EXPT' OR 'EXPORT'.
      PERFORM export_session_log_csv.
    WHEN 'ME23' OR 'DRILL'.
      IF txtp_sap_object_id IS NOT INITIAL.
        SET PARAMETER ID 'BES' FIELD txtp_sap_object_id.
        CALL TRANSACTION 'ME23N' AND SKIP FIRST SCREEN.
      ENDIF.
    WHEN 'AI' OR 'GT07'.
      CALL SCREEN 0700.
    WHEN 'BACK' OR 'EXIT' OR 'CANCEL' OR 'CANC' OR '&F03' OR '&F12' OR '&F15'.
      SET SCREEN 0.
      LEAVE SCREEN.
  ENDCASE.
ENDMODULE.

MODULE user_command_0700 INPUT.
  save_ok = ok_code.
  CLEAR ok_code.
  CASE save_ok.
    WHEN 'GEMI' OR 'GEMINI' OR 'AIREAL'.
      "Real LLM analysis (Gemini) with automatic rule-based fallback.
      PERFORM run_ai_error_analysis.
    WHEN 'DIAG' OR 'ANALYZE'.
      "Rule-based only (offline safe) - manual fallback button.
      PERFORM generate_ai_text.
      PERFORM display_ai_patterns.
    WHEN 'DOWN' OR 'EXPORT'.
      MESSAGE txtp_ai_text TYPE 'I'.
    WHEN 'KBAS' OR 'GT75' OR 'ARCHIVE'.
      CALL SCREEN 0750.
    WHEN 'GT08' OR 'SHDB' OR 'SCRIPT' OR 'REC'.
      CALL SCREEN 0800.
    WHEN 'BACK' OR 'EXIT' OR 'CANCEL' OR 'CANC' OR '&F03' OR '&F12' OR '&F15'.
      SET SCREEN 0.
      LEAVE SCREEN.
  ENDCASE.
ENDMODULE.

MODULE user_command_0750 INPUT.
  save_ok = ok_code.
  CLEAR ok_code.
  CASE save_ok.
    WHEN 'FIND' OR 'SEARCH' OR 'REFR' OR 'REFRESH'.
      PERFORM display_ai_archive.
    WHEN 'SAVE' OR '&DATA_SAVE'.
      MESSAGE 'AI Knowledge Base note saved/refreshed for demo scope.' TYPE 'S'.
      PERFORM display_ai_archive.
    WHEN 'BACK' OR 'EXIT' OR 'CANCEL' OR 'CANC' OR '&F03' OR '&F12' OR '&F15'.
      SET SCREEN 0.
      LEAVE SCREEN.
  ENDCASE.
ENDMODULE.

MODULE user_command_0800 INPUT.
  save_ok = ok_code.
  CLEAR ok_code.
  CASE save_ok.
    WHEN 'SAVE' OR '&DATA_SAVE'.
      PERFORM save_script_editor.
    WHEN 'INSR' OR 'INSERT'.
      PERFORM insert_script_row.
    WHEN 'DELR' OR 'DELETE'.
      PERFORM delete_script_row.
    WHEN 'REFR' OR 'REFRESH'.
      PERFORM load_script_editor.
      PERFORM display_script_editor.
    WHEN 'BACK' OR 'EXIT' OR 'CANCEL' OR 'CANC' OR '&F03' OR '&F12' OR '&F15'.
      SET SCREEN 0.
      LEAVE SCREEN.
  ENDCASE.
ENDMODULE.
