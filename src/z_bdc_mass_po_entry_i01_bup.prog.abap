
*& Include Z_BDC_MASS_PO_ENTRY_I01_BUP
*& Purpose PAI command routing to explicit domain commands
*& Generate Template command routing diagnostics

MODULE user_command_0100 INPUT.
  DATA: lv_loaded_count_0100        TYPE i,
      lv_row_idx           TYPE i,
      lv_session_id        TYPE zbdc_staging_bup-session_id,
      ls_dash_sel_fix      TYPE ty_dash_0100_disp,
      lv_result_invest_ok TYPE abap_bool.

 "always consume the command that caused the CURRENT PAI first.
 "CL_GUI_CFW=>SET_NEW_OK_CODE (0100 live timer) updates SY-UCOMM while the
 "screen OK_CODE field can still contain an older toolbar command such as
 "GT05. Reading OK_CODE first therefore replayed Execution Monitor during
 "an unrelated passive-field focus/timer roundtrip.
  save_ok = sy-ucomm.
  IF save_ok IS INITIAL.
    save_ok = ok_code.
  ENDIF.
  CLEAR: ok_code, sy-ucomm.

  CASE save_ok.

    WHEN 'ZLIVE10'.
 "silent 0100 live tick. PBO owns every DB read and repaint.
      gv_dash_0100_tick = abap_true.



    WHEN 'GT25' OR 'JOB' OR 'SCHED'.

      MESSAGE i733(zbdc).

    WHEN 'GT03' OR 'FC_GOTO_0300' OR 'UPLOAD' OR 'INGEST'.

      PERFORM clear_0300_runtime.
      CALL SCREEN 0300.


    WHEN 'GT04' OR 'STAGING' OR 'REVIEW' OR 'FC_GOTO_0400'.

      CLEAR: lv_session_id,
             lv_loaded_count_0100,
             lv_row_idx,
             ls_dash_sel_fix.

 " Open 0400 only by explicit user choice:
 " 1) selected dashboard row
 " 2) if SALV selection is not captured, show session picker popup
 " No auto MAX(session_id), no old TXTP_SESSION_ID reuse.

      IF go_grid_0100 IS BOUND.

        CALL METHOD cl_gui_cfw=>flush
          EXCEPTIONS
            OTHERS = 1.

        DATA(lo_selections_0100) = go_grid_0100->get_selections( ).
        DATA(lt_rows_0100)       = lo_selections_0100->get_selected_rows( ).

        IF lt_rows_0100 IS NOT INITIAL.

          READ TABLE lt_rows_0100 INTO lv_row_idx INDEX 1.

          IF sy-subrc = 0 AND lv_row_idx > 0.

            READ TABLE gt_dash_0100 INTO ls_dash_sel_fix INDEX lv_row_idx.

            IF sy-subrc = 0 AND ls_dash_sel_fix-session_id IS NOT INITIAL.
              lv_session_id = ls_dash_sel_fix-session_id.
              CONDENSE lv_session_id.
            ENDIF.

          ENDIF.

        ENDIF.

      ENDIF.

 "If row selection is not captured, let user choose explicitly.
      IF lv_session_id IS INITIAL.
        PERFORM pick_0100_session CHANGING lv_session_id.
      ENDIF.

      IF lv_session_id IS INITIAL.
        MESSAGE s037(zbdc) DISPLAY LIKE 'W'.
        RETURN.
      ENDIF.

      PERFORM clear_0400_context.
      txtp_session_id = lv_session_id.
      txtp_sess       = lv_session_id.

      CLEAR: gt_staging,
             gt_staging_alv,
             gt_exec_disp.

      REFRESH: gt_staging,
               gt_staging_alv,
               gt_exec_disp.

      IF go_exec_grid IS BOUND.
        CALL METHOD go_exec_grid->free
          EXCEPTIONS
            OTHERS = 1.
        CLEAR go_exec_grid.
      ENDIF.

      IF go_staging_grid IS BOUND.
        CALL METHOD go_staging_grid->free
          EXCEPTIONS
            OTHERS = 1.
        CLEAR go_staging_grid.
      ENDIF.

      IF go_container_0400 IS BOUND.
        CALL METHOD go_container_0400->free
          EXCEPTIONS
            OTHERS = 1.

        CLEAR: go_container_0400,
               go_split_0400,
               go_cont_head_0400,
               go_cont_body_0400.
      ENDIF.

      CALL METHOD cl_gui_cfw=>flush
        EXCEPTIONS
          OTHERS = 1.

      PERFORM load_staging_by_session
        USING    lv_session_id
        CHANGING lv_loaded_count_0100.

      IF lv_loaded_count_0100 <= 0 OR gt_staging IS INITIAL.
        MESSAGE s038(zbdc) WITH lv_session_id DISPLAY LIKE 'W'.
        RETURN.
      ENDIF.

      gv_0400_view      = gc_view_cockpit.
      gv_0400_edit_mode = space.

      PERFORM freeze_0400_context USING lv_session_id.
      PERFORM sync_0400_scope.
      PERFORM prepare_alv_0400.
      PERFORM build_exec_cockpit.
      PERFORM update_0400_counters.

      CALL SCREEN 0400.

    WHEN 'GT05' OR 'EXECUTE' OR 'EXEC' OR 'FC_GOTO_0500'.

      IF gt_staging IS INITIAL.
 "explicit fail-closed silent no-op. No exact loaded staging
 "scope means 0500 cannot be opened, but 0100 must not emit a warning.
        RETURN.
      ENDIF.

      CALL SCREEN 0500.


    WHEN 'GT07'.

      "GT07 is a direct navigation entry to the global Result Investigation
      "workspace. It must not depend on a selected dashboard row and must
      "never open a session-picker popup or infer a latest session.
      CLEAR lv_result_invest_ok.

      PERFORM prep_result_invest_0650
        CHANGING lv_result_invest_ok.

      IF lv_result_invest_ok <> abap_true.
        RETURN.
      ENDIF.

      CALL SCREEN 0650.

    WHEN 'GT08' OR 'SHDB' OR 'SCRIPT' OR 'FC_GOTO_0800'.

      CALL SCREEN 0800.

    WHEN 'BACK' OR 'EXIT' OR 'CANCEL' OR 'CANC' OR '&F03' OR '&F12' OR '&F15'.

      PERFORM stop_dash_timer.
      LEAVE PROGRAM.

  ENDCASE.
ENDMODULE.

MODULE exit_0300 INPUT.
  DATA lv_exit_0300 TYPE sy-ucomm.

  lv_exit_0300 = ok_code.
  IF lv_exit_0300 IS INITIAL.
    lv_exit_0300 = sy-ucomm.
  ENDIF.

  CASE lv_exit_0300.
    WHEN 'EXIT' OR '&F15' OR 'F15' OR 'ENDE' OR 'FC_EXIT'.
      CLEAR ok_code.
      PERFORM clear_0300_runtime.
      LEAVE PROGRAM.

    WHEN 'BACK' OR '&F03' OR 'F03' OR 'RW' OR 'FC_BACK'
      OR 'CANCEL' OR 'CANC' OR 'CLOSE' OR '&F12' OR 'F12' OR 'ECAN' OR 'FC_CANCEL'.
      CLEAR ok_code.
      PERFORM clear_0300_runtime.
      SET SCREEN 0.
      LEAVE SCREEN.
  ENDCASE.
ENDMODULE.

MODULE user_command_0300 INPUT.
  DATA: lv_count_0300    TYPE i,
        lv_source_0300   TYPE char20,
        lv_policy_ok     TYPE abap_bool,
        lv_policy_msg    TYPE string,
        lv_validate_ok   TYPE abap_bool,
        lv_validate_msg  TYPE string,
        lv_hist_scope_0300 TYPE abap_bool,
        lv_tab_act_0300 TYPE c LENGTH 20,
        lv_save_norm_0300 TYPE string,
        lt_sel_rows_0300 TYPE lvc_t_row,
        ls_sel_row_0300 TYPE lvc_s_row.

  save_ok = ok_code.
  IF save_ok IS INITIAL.
    save_ok = sy-ucomm.
  ENDIF.

  CLEAR ok_code.

  lv_tab_act_0300 = ts_preview-activetab.
  TRANSLATE lv_tab_act_0300 TO UPPER CASE.

 "an explicit Preview Files command must always win.
 "Some SAP GUI tabstrips leave TS_PREVIEW-ACTIVETAB on the old tab during
 "PAI; flipping TAB_FILES back to TAB_PREVIEW caused the visible spin/loop
 "and the wrong 'No current upload data' message. Use ACTIVETAB only as a
 "fallback when the function code is empty or clearly still the old tab.
  lv_save_norm_0300 = save_ok.
  TRANSLATE lv_save_norm_0300 TO UPPER CASE.
 "an explicit Preview Data command must win over the old active tab.
 "During PAI TS_PREVIEW-ACTIVETAB can still be TAB_FILES even though the
 "user just clicked Preview Data. Never rewrite explicit TAB_PREVIEW/PREV
 "back to TAB_FILES; otherwise the selection guard below can never run.
  IF lv_tab_act_0300 = 'TAB_FILES'
     AND ( lv_save_norm_0300 IS INITIAL
        OR lv_save_norm_0300 = 'TAB_FILE' ).
    save_ok = 'TAB_FILES'.
  ENDIF.

 "Capture the visible runtime policy once at the PAI boundary.
 "The function code is not a source of truth and never changes resolution.
  PERFORM capture_runtime
    CHANGING lv_policy_ok lv_policy_msg.
  IF lv_policy_ok <> abap_true.
    MESSAGE lv_policy_msg TYPE 'S' DISPLAY LIKE 'E'.
    RETURN.
  ENDIF.

  IF save_ok IS INITIAL.
    RETURN.
  ENDIF.

  CASE save_ok.

    WHEN 'EXIT' OR '&F15' OR 'F15' OR 'ENDE' OR 'FC_EXIT'.
      PERFORM clear_0300_runtime.
      LEAVE PROGRAM.

    WHEN 'BACK' OR '&F03' OR 'F03' OR 'RW' OR 'FC_BACK'
      OR 'CANCEL' OR 'CANC' OR '&F12' OR 'F12' OR 'ECAN' OR 'FC_CANCEL'.
      PERFORM clear_0300_runtime.
      SET SCREEN 0.
      LEAVE SCREEN.

    WHEN 'SAVE' OR '&DATA_SAVE' OR 'SAVE_NOTE' OR 'SVECFG'.
 "Save on 0300 belongs only to runtime execution config.
 "It must not upload, re-parse, change file path, switch preview tab,
 "or persist inbound/source fields.
      PERFORM save_0300_runtime_config.

    WHEN 'RB_EXEC_CT' OR 'RB_EXEC_BI'
      OR 'RB_MODE_N' OR 'RB_MODE_E' OR 'RB_MODE_A'
      OR 'RB_UPD_A'  OR 'RB_UPD_S'
      OR 'CTMA' OR 'BIMA' OR 'BISM' OR 'BISN' OR 'SM35'
      OR 'BDCT' OR 'BDBI' OR 'BDCC' OR 'BDBC'
      OR 'BDMN' OR 'BDME' OR 'BDMA'
      OR 'UPDA' OR 'UPDM' OR 'UPDS' OR 'UPDSYNC'
      OR 'AUPD' OR 'SUPD'
      OR 'ENTER' OR '=ENTR'.
 "Radio-only PAI event. The visible policy was already captured once
 "at the module boundary; no second resolver or function-code mapping runs.



    WHEN 'TAB_PREVIEW' OR 'PREV' OR 'PREVIEW' OR 'PREVIEW_DATA' OR 'FC_PREV' OR 'FC_PREVIEW'.
 "Preview Data previews one concrete file. When the user comes
 "from Preview Files with no already-loaded/uploaded file, use the ALV
 "selection as the file choice. Do not silently open an empty preview.
      IF lv_tab_act_0300 = 'TAB_FILES'.
        REFRESH lt_sel_rows_0300.
        IF go_alv_0301 IS BOUND.
          CALL METHOD go_alv_0301->get_selected_rows
            IMPORTING et_index_rows = lt_sel_rows_0300.
        ENDIF.

        IF lt_sel_rows_0300 IS INITIAL.
          g_sub_dynpro = '0301'.
          ts_preview-activetab = 'TAB_FILES'.
          MESSAGE 'Select one file from Preview Files or upload a file first.'
            TYPE 'S' DISPLAY LIKE 'W'.
          RETURN.
        ENDIF.

        IF lines( lt_sel_rows_0300 ) > 1.
          g_sub_dynpro = '0301'.
          ts_preview-activetab = 'TAB_FILES'.
          MESSAGE 'Select only one file to preview.'
            TYPE 'S' DISPLAY LIKE 'W'.
          RETURN.
        ENDIF.

        READ TABLE lt_sel_rows_0300 INTO ls_sel_row_0300 INDEX 1.
        IF sy-subrc = 0 AND ls_sel_row_0300-index > 0.
          PERFORM open_file_history_row USING ls_sel_row_0300-index.
          RETURN.
        ENDIF.
      ENDIF.

 "Preview Data is display-only. For a new Browse selection, no source
 "may create rows here. Local, Google Drive and Gmail must all cross the
 "same explicit Upload/Ingest boundary first. History rows are handled above
 "because they already represent a previously persisted ingestion.
      g_sub_dynpro = '0301'.
      ts_preview-activetab = 'TAB_PREVIEW'.

      IF gt_staging IS INITIAL.
        PERFORM reset_0300_all_alv.
        IF txtp_file_path IS NOT INITIAL.
          MESSAGE 'Press Upload/Ingest first. Preview Data is available only after a successful ingest.'
            TYPE 'S' DISPLAY LIKE 'W'.
        ELSEIF gv_ingest_error_msg IS NOT INITIAL.
          MESSAGE gv_ingest_error_msg TYPE 'S' DISPLAY LIKE 'E'.
        ELSE.
          MESSAGE s042(zbdc) DISPLAY LIKE 'W'.
        ENDIF.
        RETURN.
      ENDIF.

      PERFORM reset_0300_all_alv.
      lv_count_0300 = lines( gt_staging ).
      MESSAGE s043(zbdc) WITH lv_count_0300.

    WHEN 'BTN_BROWSE' OR 'FC_BROWSE' OR 'BROWSE' OR 'BROW'
      OR 'BROWSE_LOCAL' OR 'PICK_FILE' OR 'PICK' OR 'PICK_LOCAL'.
 "Browse is selection-only for all three supported sources. It may choose
 "a local file, a Drive file, or Gmail submission(s), but it never parses,
 "persists, or populates Preview Data. Upload/Ingest owns that boundary.
      PERFORM select_inbound_channel.
      g_sub_dynpro = '0301'.
      ts_preview-activetab = 'TAB_PREVIEW'.
      FREE MEMORY ID 'ZBDC_0300_HISTORY_SCOPE'.
      PERFORM set_row_count_fields USING 0.
      IF txtp_file_size IS INITIAL.
        txtp_file_size = '0 B'.
      ENDIF.

    WHEN 'TAB_ERRORS' OR 'TAB_FILES' OR 'TAB_FILE'
      OR 'PV_FILE' OR 'PV_FILES'
      OR 'PREVIEW_FILE' OR 'PREVIEW_FILES'
      OR 'PREV_FILE' OR 'PREV_FILES'
      OR 'FILE_PREVIEW' OR 'FILES_PREVIEW'
      OR 'FILE_HISTORY' OR 'HISTORY'
      OR 'FILES' OR 'FC_FILES' OR 'FC_PREVIEW_FILES' OR 'FC_FILE_HISTORY'.
 "Preview Files is controlled only by the tab/function itself.
 "Do not reuse FC_BROWSE here because the screen Browse button uses it.
      IF gv_file_scope IS INITIAL.
        gv_file_scope = gc_file_scope_my.
      ENDIF.
      PERFORM prepare_preview_file.
      g_sub_dynpro = '0301'.
      ts_preview-activetab = 'TAB_FILES'.
      PERFORM reset_0300_all_alv.
      DATA(lv_zm044_456_1) = lines( gt_files_preview ).
      MESSAGE s044(zbdc) WITH lv_zm044_456_1.

    WHEN 'ZMYFILES'
      OR 'MY_UPLOAD' OR 'MY_UPLOADS'
      OR 'MYUP' OR 'MYUPL' OR 'MYUPLD'
      OR 'MYFILES' OR 'FC_MY_UPLOAD' OR 'FC_MY_UPLOADS'.

 "restore My Uploads switch on 0300 even when the GUI status
 "or SALV custom function sends the command directly to screen PAI.
 "This must only switch the file/source history scope; it must not
 "re-parse files, clear current upload data, or alter runtime BDC config.
      gv_file_scope = gc_file_scope_my.
      PERFORM prepare_preview_file.
      g_sub_dynpro = '0301'.
      ts_preview-activetab = 'TAB_FILES'.
      PERFORM reset_0300_all_alv.
      DATA(lv_zm045_472_1) = lines( gt_files_preview ).
      MESSAGE s045(zbdc) WITH lv_zm045_472_1.

    WHEN 'ZALLFILES'
      OR 'ALL_UPLOAD' OR 'ALL_UPLOADS'
      OR 'ALLUP' OR 'ALLUPL' OR 'ALLUPLD'
      OR 'ALLFILES' OR 'FC_ALL_UPLOAD' OR 'FC_ALL_UPLOADS'.

 "restore All Uploads switch on 0300. This is history/preview
 "only; execution/retry still uses the explicit selected/current scope.
      gv_file_scope = gc_file_scope_all.
      PERFORM prepare_preview_file.
      g_sub_dynpro = '0301'.
      ts_preview-activetab = 'TAB_FILES'.
      PERFORM reset_0300_all_alv.
      DATA(lv_zm046_486_1) = lines( gt_files_preview ).
      MESSAGE s046(zbdc) WITH lv_zm046_486_1.


    WHEN 'UPLD' OR 'FC_UPLOAD_EXEC' OR 'UPLOAD_EXEC' OR 'INGEST_NOW'.
 "Upload/Ingest is the single ingestion boundary for Local, Google Drive
 "and Gmail. Browse only selects a source; this action alone may parse,
 "normalize, persist ZBDC_STAGING_BUP, and populate Preview Data.
      IF txtp_file_path IS INITIAL.
        MESSAGE s048(zbdc) DISPLAY LIKE 'W'.
      ELSE.
        CLEAR lv_source_0300.
        IF txtp_file_path CP 'GoogleDrive://*'.
          lv_source_0300 = 'GDRIVE'.
        ELSEIF txtp_file_path CP 'GmailForm://*'.
          lv_source_0300 = 'GMAIL'.
        ELSEIF txtp_file_path CP 'REST_API://*'
            OR txtp_file_path CP 'MAILBOX://*'.
          lv_source_0300 = 'REST'.
        ELSE.
          lv_source_0300 = 'LOCAL'.
        ENDIF.

        IF gt_staging IS INITIAL.
          IF lv_source_0300 = 'GMAIL'.
            PERFORM upload_gmail_pending.
          ELSE.
            PERFORM upload_and_parse_excel.
          ENDIF.
        ENDIF.

        IF gt_staging IS NOT INITIAL.
          lv_count_0300 = lines( gt_staging ).
          PERFORM set_row_count_fields USING lv_count_0300.
          PERFORM 0300_after_ingest USING lv_source_0300.
        ENDIF.
      ENDIF.
 "0300_after_ingest keeps Preview Data active and schedules a PBO rebuild.
      cl_gui_cfw=>flush( ).

    WHEN 'FC_UPLD_LOCAL' OR 'LOCAL' OR 'ULOC'.
 "Legacy source-specific actions are selection-only too. Keeping them from
 "ingesting prevents any alternate route from bypassing Upload/Ingest.
      PERFORM browse_file.
      cl_gui_cfw=>flush( ).

    WHEN 'FC_UPLD_GDRIVE' OR 'GDRIVE' OR 'GDRIV' OR 'GD' OR 'GOOGLE' OR 'GOOGLE_DRIVE' OR 'UDRV'.
      PERFORM select_gdrive_file_path.
      cl_gui_cfw=>flush( ).

    WHEN 'FC_UPLD_REST' OR 'REST' OR 'URES'.
      PERFORM browse_gmail_pending.
      cl_gui_cfw=>flush( ).


    WHEN 'VALID' OR 'VALD' OR 'FC_VALID' OR 'CHECK'.
 "Do not silently validate old DB rows from a previous upload.
      IF gt_staging IS INITIAL.
        MESSAGE w051(zbdc).
      ELSE.
        PERFORM apply_first_staging_ctx.
        PERFORM validate_staging
          CHANGING lv_validate_ok lv_validate_msg.
        IF lv_validate_ok <> abap_true.
          MESSAGE lv_validate_msg TYPE 'S' DISPLAY LIKE 'E'.
          RETURN.
        ENDIF.
        MESSAGE lv_validate_msg TYPE 'S'.
        g_sub_dynpro = '0301'.
        PERFORM reset_0300_alv.
      ENDIF.

    WHEN 'GT04' OR 'STAGING' OR 'FC_UPLOAD_REVIEW' OR 'REVIEW'.
 "Staging reached from Preview Files is a historical review of
 "persisted lifecycle evidence. Do not revalidate that historical scope:
 "validate_staging intentionally resets every non-terminal row to
 "READY before validating, which would erase persisted ERROR/WARNING
 "execution states while SUCCESS survives. Fresh uploads still keep the
 "normal STAGED -> validation -> READY/ERROR boundary.
      IF gt_staging IS NOT INITIAL.
        PERFORM apply_first_staging_ctx.

        CLEAR lv_hist_scope_0300.
        IMPORT lv_0300_hist_scope = lv_hist_scope_0300
          FROM MEMORY ID 'ZBDC_0300_HISTORY_SCOPE'.

        IF lv_hist_scope_0300 <> abap_true.
          PERFORM validate_staging
            CHANGING lv_validate_ok lv_validate_msg.
          IF lv_validate_ok <> abap_true.
            MESSAGE lv_validate_msg TYPE 'S' DISPLAY LIKE 'E'.
            RETURN.
          ENDIF.

          "Duplicate Business Keys are not rejected during Preview. Staging
          "validates them now and opens 0400 with invalid groups marked ERROR.
          IF lv_validate_msg CS 'invalid duplicate Business Key group(s)'.
            MESSAGE lv_validate_msg TYPE 'S' DISPLAY LIKE 'W'.
          ENDIF.
        ENDIF.

        PERFORM open_0400_for_current_staging.
      ELSE.
        MESSAGE w052(zbdc).
      ENDIF.

    WHEN 'GT05' OR 'NEXT' OR 'FC_NEXT' OR 'EXEC' OR 'EXECUTE'.
      "Execute is downstream of explicit ingestion. It must never parse or
      "download an inbound source on behalf of the user.
      IF gt_staging IS INITIAL.
        IF txtp_file_path IS NOT INITIAL.
          MESSAGE 'Press Upload/Ingest first. Execute requires persisted staging data.'
            TYPE 'S' DISPLAY LIKE 'W'.
        ELSEIF gv_ingest_error_msg IS NOT INITIAL.
          MESSAGE gv_ingest_error_msg TYPE 'S' DISPLAY LIKE 'W'.
        ELSE.
          MESSAGE w053(zbdc).
        ENDIF.
      ELSE.
 "Execute has the same mandatory STAGED -> validation -> READY
 "boundary as the explicit Staging command. No inbound channel may
 "enter 0500 with rows that merely exist in memory.
        PERFORM apply_first_staging_ctx.
        CLEAR: lv_validate_ok, lv_validate_msg.
        PERFORM validate_staging
          CHANGING lv_validate_ok lv_validate_msg.
        IF lv_validate_ok <> abap_true.
          MESSAGE lv_validate_msg TYPE 'S' DISPLAY LIKE 'E'.
          RETURN.
        ENDIF.
        IF lv_validate_msg CS 'invalid duplicate Business Key group(s)'.
          MESSAGE lv_validate_msg TYPE 'S' DISPLAY LIKE 'E'.
          RETURN.
        ENDIF.
        CALL SCREEN 0500.
      ENDIF.

    WHEN 'SAVE_NOTE' OR 'SAVE_NOTE_OPT'.
 "only the explicit Save Note button shows a note message.
 "The UPDS function code is used by update-mode radio controls in some
 "systems and is handled above as a silent radio-only event.
      PERFORM sync_0300_counts.
      MESSAGE s054(zbdc).

    WHEN OTHERS.
 "Unknown frontend focus/radio events must not pollute demo videos.
 "A tabstrip may arrive through a system-specific function code; route only
 "file-preview semantics and keep all other frontend noise silent.
      lv_save_norm_0300 = save_ok.
      TRANSLATE lv_save_norm_0300 TO UPPER CASE.
      IF ts_preview-activetab = 'TAB_FILES'
         OR lv_save_norm_0300 CS 'PREVIEW_FILES'
         OR lv_save_norm_0300 CS 'PREV_FILES'
         OR lv_save_norm_0300 CS 'FILE_HISTORY'
         OR ( lv_save_norm_0300 CS 'FILE'
              AND lv_save_norm_0300 NS 'BROW'
              AND lv_save_norm_0300 NS 'UPLD'
              AND lv_save_norm_0300 NS 'UPLOAD' ).
        IF gv_file_scope IS INITIAL.
          gv_file_scope = gc_file_scope_my.
        ENDIF.
        PERFORM prepare_preview_file.
        g_sub_dynpro = '0301'.
        ts_preview-activetab = 'TAB_FILES'.
        PERFORM reset_0300_all_alv.
        DATA(lv_zm055_661_1) = lines( gt_files_preview ).
        MESSAGE s055(zbdc) WITH lv_zm055_661_1.
      ENDIF.

  ENDCASE.
ENDMODULE.

MODULE exit_0350 INPUT.
  DATA lv_exit_0350 TYPE sy-ucomm.

  lv_exit_0350 = ok_code.
  IF lv_exit_0350 IS INITIAL.
    lv_exit_0350 = sy-ucomm.
  ENDIF.

  CASE lv_exit_0350.
    WHEN 'EXIT' OR '&F15' OR 'F15' OR 'ENDE' OR 'FC_EXIT'.
      CLEAR ok_code.
      LEAVE PROGRAM.

    WHEN 'BACK' OR '&F03' OR 'F03' OR 'RW' OR 'FC_BACK'
      OR 'CANCEL' OR 'CANC' OR '&F12' OR 'F12' OR 'ECAN' OR 'FC_CANCEL'.
      CLEAR ok_code.
      SET SCREEN 0.
      LEAVE SCREEN.
  ENDCASE.
ENDMODULE.

MODULE user_command_0350 INPUT.
  DATA: lv_guard_0350_ok  TYPE abap_bool,
        lv_guard_0350_msg TYPE string,
        lv_tmpl_ok_0350   TYPE abap_bool,
        lv_tmpl_msg_0350  TYPE string,
        lv_cmd_norm_0350  TYPE string.

  save_ok = ok_code.
  IF save_ok IS INITIAL.
    save_ok = sy-ucomm.
  ENDIF.
  CLEAR: ok_code, sy-ucomm.

  lv_cmd_norm_0350 = save_ok.
  TRANSLATE lv_cmd_norm_0350 TO UPPER CASE.
  CONDENSE lv_cmd_norm_0350 NO-GAPS.

 "UI_CLEAN: screen 0350 is review/audit + lifecycle only.
 "Manual Save/Add/Delete and duplicate Create Mapping Draft commands were
 "removed from the productive toolbar. Backend draft creation remains intact
 "and is still driven automatically by the onboarding/Mapping Profile flow.
 "do not pre-guard Generate Template here. The template context
 "preparer owns the full lifecycle gate: Candidate Review -> confirm/lock ->
 "normal template validation. A generic read-only guard here would stop the
 "candidate before prepare_template_ctx can call promote_cand_contract.

  CASE save_ok.
    WHEN 'GENERATE' OR 'GEN_TMPL' OR 'PUBLISH'
      OR 'FC_DL_TMPL' OR 'DL_TMPL' OR 'DOWNLOAD_TEMPLATE'
      OR 'GENERATE_TEMPLATE' OR 'FC_GEN_TMPL' OR 'TEMPLATE'
      OR 'GEN_TEMPLATE' OR 'GENTMPL' OR 'SAVE_TEMPLATE'
      OR 'SAVE_TMPL' OR 'ZGEN_TMPL' OR 'ZTMPL'.
      CLEAR: lv_tmpl_ok_0350, lv_tmpl_msg_0350.
      PERFORM prepare_template_ctx
        CHANGING lv_tmpl_ok_0350 lv_tmpl_msg_0350.
      IF lv_tmpl_ok_0350 <> abap_true.
        MESSAGE lv_tmpl_msg_0350 TYPE 'S' DISPLAY LIKE 'E'.
        RETURN.
      ENDIF.
      PERFORM download_curr_prof_tmpl.

    WHEN 'GT04' OR 'STAGING' OR 'FC_UPLOAD_REVIEW' OR 'REVIEW'
      OR 'GT03' OR 'UPLOAD' OR 'INGEST' OR 'FC_GOTO_0300'.
      MESSAGE s056(zbdc) DISPLAY LIKE 'W'.

    WHEN 'EXIT' OR '&F15' OR 'F15' OR 'ENDE' OR 'FC_EXIT'.
      PERFORM stop_result_timer_0650.
      LEAVE PROGRAM.

    WHEN 'BACK' OR '&F03' OR 'F03' OR 'RW' OR 'FC_BACK'
      OR 'CANCEL' OR 'CANC' OR '&F12' OR 'F12' OR 'ECAN' OR 'FC_CANCEL'.
      PERFORM stop_result_timer_0650.
      SET SCREEN 0.
      LEAVE SCREEN.

    WHEN OTHERS.
 "tolerate legacy/custom PF-STATUS function codes whose text is
 "Generate Template but whose FCODE was not one of the historical aliases.
      IF lv_cmd_norm_0350 CS 'GEN'.
        IF lv_cmd_norm_0350 CS 'TMPL' OR lv_cmd_norm_0350 CS 'TEMP'.
          CLEAR: lv_tmpl_ok_0350, lv_tmpl_msg_0350.
          PERFORM prepare_template_ctx
            CHANGING lv_tmpl_ok_0350 lv_tmpl_msg_0350.
          IF lv_tmpl_ok_0350 <> abap_true.
            MESSAGE lv_tmpl_msg_0350 TYPE 'S' DISPLAY LIKE 'E'.
            RETURN.
          ENDIF.
          PERFORM download_curr_prof_tmpl.
        ELSEIF save_ok IS NOT INITIAL.
          MESSAGE s057(zbdc) WITH save_ok DISPLAY LIKE 'W'.
        ENDIF.
      ELSEIF save_ok IS NOT INITIAL.
        MESSAGE s057(zbdc) WITH save_ok DISPLAY LIKE 'W'.
      ENDIF.
  ENDCASE.
ENDMODULE.

MODULE user_command_0400 INPUT.
  DATA: lv_ok_0400        TYPE abap_bool,
        lv_count_0400     TYPE i,
        lv_stage_scope_ok TYPE abap_bool,
        lv_stage_scope_msg TYPE string.

 "only an explicit screen function code may navigate or execute.
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
 "A real staging edit is a transaction boundary. Never execute while the
 "detail editor owns 0400; Save/Cancel first so no unsaved frontend values
 "can leak into an execution scope.
      IF gv_0400_view = gc_view_detail OR gv_0400_edit_mode = 'X'.
        MESSAGE 'Save or Cancel Edit Staging before running execution.' TYPE 'S' DISPLAY LIKE 'W'.
        RETURN.
      ENDIF.
 "Flow B: 0400 is review/scope selection; 0500 is the real executor.
      PERFORM prepare_0500_exec_scope
        USING    'ALL'
        CHANGING lv_count_0400 lv_ok_0400.
      IF lv_ok_0400 <> abap_true.
        MESSAGE w058(zbdc).
        RETURN.
      ENDIF.
      MESSAGE s059(zbdc) WITH lv_count_0400.
 "The suspended 0400 caller must always be the cockpit. BACK from 0500
 "therefore returns to a clean review state, never to a stale edit screen.
      gv_0400_view      = gc_view_cockpit.
      gv_0400_edit_mode = space.
      CLEAR: gt_z566_edit_scope, gv_z566_edit_groups.
      CALL SCREEN 0500.

    WHEN 'EXSL' OR 'RUN_SEL' OR 'RUN_SELECTED' OR 'EXEC_SELECTED'.
      IF gv_0400_view = gc_view_detail OR gv_0400_edit_mode = 'X'.
        MESSAGE 'Save or Cancel Edit Staging before running execution.' TYPE 'S' DISPLAY LIKE 'W'.
        RETURN.
      ENDIF.
 "Flow B: selected rows are captured before leaving 0400.
      PERFORM prepare_0500_exec_scope
        USING    'SELECTED'
        CHANGING lv_count_0400 lv_ok_0400.
      IF lv_ok_0400 <> abap_true.
        MESSAGE w060(zbdc).
        RETURN.
      ENDIF.
      MESSAGE s061(zbdc) WITH lv_count_0400.
      gv_0400_view      = gc_view_cockpit.
      gv_0400_edit_mode = space.
      CLEAR: gt_z566_edit_scope, gv_z566_edit_groups.
      CALL SCREEN 0500.

    WHEN 'ZSTGEDIT'.
      IF gv_0400_view = gc_view_detail.
       "14C self-heal: backend may already say DETAIL while SAP GUI still
       "paints the old cockpit. Never stop at 'already in edit mode'. Force
       "the PBO to rebuild the complete 0400 control tree for DETAIL.
        gv_0400_render_view = gc_view_cockpit.
        SET SCREEN 0400.
        LEAVE SCREEN.
      ELSE.
        CLEAR: lv_stage_scope_ok, lv_stage_scope_msg.
        PERFORM ensure_0400_stage_scope
          CHANGING lv_stage_scope_ok lv_stage_scope_msg.
        IF lv_stage_scope_ok <> abap_true.
          IF lv_stage_scope_msg IS INITIAL.
            lv_stage_scope_msg = 'No editable staging scope is loaded.'.
          ENDIF.
          MESSAGE lv_stage_scope_msg TYPE 'S' DISPLAY LIKE 'W'.
        ELSE.
          DATA: lv_z566_groups TYPE i,
                lv_z566_rows   TYPE i.
          CLEAR: lv_stage_scope_ok, lv_stage_scope_msg,
                 lv_z566_groups, lv_z566_rows.
          PERFORM capture_cockpit_scope
            USING    'EDIT'
            CHANGING lv_stage_scope_ok lv_z566_groups lv_z566_rows lv_stage_scope_msg.
          IF lv_stage_scope_ok <> abap_true.
            MESSAGE lv_stage_scope_msg TYPE 'S' DISPLAY LIKE 'W'.
          ELSE.
            CLEAR: lv_stage_scope_ok, lv_stage_scope_msg.
            PERFORM build_edit_projection
              CHANGING lv_stage_scope_ok lv_stage_scope_msg.
            IF lv_stage_scope_ok <> abap_true.
              MESSAGE lv_stage_scope_msg TYPE 'S' DISPLAY LIKE 'W'.
            ELSE.
              PERFORM switch_to_detail_edit.
              MESSAGE s063(zbdc) WITH lv_z566_groups lv_z566_rows.

             "14C: force the render marker to the previous cockpit view even
             "if an earlier failed roundtrip left it incorrectly on DETAIL.
             "The next PBO therefore tears down the complete old tree and
             "creates the editable staging grid deterministically.
              gv_0400_render_view = gc_view_cockpit.

             "Force one deterministic 0400 dynpro roundtrip. PAI owns only
             "the logical state; the following PBO owns the frontend control
             "transition from GO_EXEC_GRID to the editable GO_STAGING_GRID.
             "Without this explicit roundtrip the backend may already be in
             "DETAIL while SAP GUI still paints the old cockpit grid.
              SET SCREEN 0400.
              LEAVE SCREEN.
            ENDIF.
          ENDIF.
        ENDIF.
      ENDIF.

    WHEN 'ZSTGSAV'.
      IF gv_0400_view <> gc_view_detail.
        MESSAGE s064(zbdc) DISPLAY LIKE 'W'.
      ELSE.
        PERFORM save_detail_and_return.
      ENDIF.

    WHEN 'ZSTGCAN'.
      IF gv_0400_view <> gc_view_detail.
        MESSAGE s064(zbdc) DISPLAY LIKE 'W'.
      ELSE.
        PERFORM cancel_detail_edit.
      ENDIF.

    WHEN 'ZSTGAUD'.
 "Change History is session-wide and read-only. It does not
 "depend on cockpit row selection, so it scales to many business groups
 "without forcing the user to preselect 100/1000 keys.
      PERFORM show_change_history.

    WHEN 'ZNAVSET'.
      PERFORM configure_selected_navigation.

    WHEN 'Z0400UI'.
 "Legacy/internal roundtrip alias retained for compatibility.
      RETURN.

    WHEN 'GT05' OR 'MONITOR' OR 'EXEC_LOG' OR 'EXECUTION_LOG' OR 'FC_GOTO_0500'.
      IF gv_0400_view = gc_view_detail OR gv_0400_edit_mode = 'X'.
        MESSAGE 'Save or Cancel Edit Staging before opening Execution Monitor.' TYPE 'S' DISPLAY LIKE 'W'.
        RETURN.
      ENDIF.
 "Execution Monitor is selection-scoped. 0400 is the user's
 "authoritative view: one highlighted group means one group in 0500;
 "multi-selection means exactly those groups. Never silently expand to
 "all groups from the current batch/file.
      CLEAR: lv_count_0400, lv_ok_0400.
      PERFORM prepare_monitor_scope
        CHANGING lv_count_0400 lv_ok_0400.

      IF lv_ok_0400 <> abap_true.
 "no exact monitor scope = silent no-op and clear any stale
 "status-bar text left by an earlier program load/action. This does
 "not navigate, select, execute, or mutate business/runtime state.
        MESSAGE ' ' TYPE 'S'.
        RETURN.
      ENDIF.

      MESSAGE s066(zbdc) WITH lv_count_0400.
      gv_0400_view      = gc_view_cockpit.
      gv_0400_edit_mode = space.
      CLEAR: gt_z566_edit_scope, gv_z566_edit_groups.
      CALL SCREEN 0500.

    WHEN 'GT06' OR 'RESULT' OR 'RESULTS' OR 'DASHBOARD'.
      PERFORM open_result_dash_curr.
 WHEN 'EXIT' OR '&F15' OR 'F15' OR 'ENDE' OR 'FC_EXIT'.
      PERFORM clear_0400_context.
      LEAVE PROGRAM.

    WHEN 'BACK' OR '&F03' OR 'F03' OR 'RW' OR 'FC_BACK'
      OR 'CANCEL' OR 'CANC' OR '&F12' OR 'F12' OR 'ECAN' OR 'FC_CANCEL'.
      PERFORM clear_0400_context.
      SET SCREEN 0.
      LEAVE SCREEN.

    WHEN OTHERS.
      MESSAGE s067(zbdc) WITH save_ok DISPLAY LIKE 'W'.
  ENDCASE.
ENDMODULE.

MODULE user_command_0500 INPUT.
  DATA: lv_pai_policy_ok_0500   TYPE abap_bool,
        lv_pai_policy_msg_0500  TYPE string,
        lv_state_ok_0500    TYPE abap_bool,
        lv_state_msg_0500   TYPE string,
        lv_cmd_0500         TYPE sy-ucomm,
        lv_z714_closed_0500 TYPE abap_bool,
        lv_z716_synced_0500 TYPE abap_bool.

  save_ok = ok_code.

  IF save_ok IS INITIAL.
    save_ok = sy-ucomm.
  ENDIF.

  CLEAR: ok_code, sy-ucomm.

  PERFORM canon_0500_cmd
    USING save_ok CHANGING lv_cmd_0500.

  PERFORM check_0500_state
    CHANGING lv_state_ok_0500 lv_state_msg_0500.
  IF lv_state_ok_0500 <> abap_true
     AND lv_cmd_0500 <> gc_ucomm_refresh_0500
     AND lv_cmd_0500 <> 'BACK'.
    MESSAGE lv_state_msg_0500 TYPE 'S' DISPLAY LIKE 'E'.
    RETURN.
  ENDIF.

 "before blocking navigation/actions on the volatile running flag,
 "synchronize the exact SM35 scope once on this explicit user command. If
 "all visible groups are already terminal, close only the stale monitor
 "state; never execute/retry anything here.
  CLEAR: lv_z714_closed_0500, lv_z716_synced_0500.
  IF gv_exec_run_active = abap_true AND gv_exec_mon_kind = gc_mon_sm35.
 "if standard SM35 already reached terminal exact-QID evidence,
 "the first 0500 action (including Back) performs the real reconciliation
 "before the busy gate. Refresh Queue is no longer a prerequisite.
    PERFORM sync_term_sm35 CHANGING lv_z716_synced_0500.
    IF lv_z716_synced_0500 <> abap_true.
      PERFORM sync_0500_q_db USING gt_exec_scope_0500.
      PERFORM close_term_sm35_mon
        CHANGING lv_z714_closed_0500.
    ELSE.
      lv_z714_closed_0500 = abap_true.
    ENDIF.
  ENDIF.

 " Block duplicate execution only when a REAL run is active.
 " STOP / REFRESH / BACK / timer commands are still allowed.

  IF gv_exec_run_active = abap_true
     AND lv_cmd_0500 <> gc_ucomm_stop_0500
     AND lv_cmd_0500 <> gc_ucomm_refresh_0500
     AND lv_cmd_0500 <> 'ZLIVE50'
     AND lv_cmd_0500 <> 'ZREF500'
     AND lv_cmd_0500 <> gc_ucomm_open_sm35
     AND lv_cmd_0500 <> 'BACK'.

    IF gv_exec_mon_kind = gc_mon_sm35.
      MESSAGE s031(zbdc) WITH gv_sm35_mon_group DISPLAY LIKE 'W'.
    ELSE.
      MESSAGE s032(zbdc) DISPLAY LIKE 'W'.
    ENDIF.

    RETURN.
  ENDIF.

  CASE lv_cmd_0500.

 " Execute Now - CALL TRANSACTION mode

    WHEN gc_ucomm_run_0500.

      PERFORM check_runtime_policy
        CHANGING lv_pai_policy_ok_0500 lv_pai_policy_msg_0500.
      IF lv_pai_policy_ok_0500 <> abap_true.
        MESSAGE lv_pai_policy_msg_0500 TYPE 'S' DISPLAY LIKE 'E'.
        RETURN.
      ENDIF.
      IF p_bdc_mode = gc_mode_batch.
        MESSAGE s068(zbdc) DISPLAY LIKE 'W'.
        RETURN.
      ENDIF.
      PERFORM request_0500_run USING gc_mode_call.

 " Run Batch Session - Batch Input Session / SM35 mode

    WHEN gc_ucomm_create_sm35.

      PERFORM check_runtime_policy
        CHANGING lv_pai_policy_ok_0500 lv_pai_policy_msg_0500.
      IF lv_pai_policy_ok_0500 <> abap_true.
        MESSAGE lv_pai_policy_msg_0500 TYPE 'S' DISPLAY LIKE 'E'.
        RETURN.
      ENDIF.
      IF p_bdc_mode = gc_mode_call.
        MESSAGE s069(zbdc) DISPLAY LIKE 'W'.
        RETURN.
      ENDIF.
      PERFORM request_0500_run USING gc_mode_batch.

 " Standard SM35 processing / review. intentionally keeps
 " business execution in SAP standard Batch Input; SM35 opens in a separate
 " mode while exact-QID full-log processing auto-reconciles the cockpit.

    WHEN gc_ucomm_exec_sm35 OR gc_ucomm_open_sm35.

      IF p_bdc_mode <> gc_mode_batch.
        MESSAGE s070(zbdc) DISPLAY LIKE 'W'.
        RETURN.
      ENDIF.
      PERFORM open_sm35_0500.

 " Stop queue

    WHEN gc_ucomm_stop_0500.

      IF lv_z714_closed_0500 = abap_true.
        MESSAGE 'Execution is already terminal; no Stop Queue action is required.' TYPE 'S'.
      ELSEIF gv_exec_mon_kind = gc_mon_sm35.
 "SM35 owns the external business execution. Stop Queue on 0500 stops
 "only this cockpit monitor immediately; it must not poison the next
 "Back/Exit with a stale gv_exec_run_active flag.
        gv_exec_run_active = abap_false.
        CLEAR: gv_exec_mon_kind, gv_exec_stop_req, g_stop_flag,
               gv_sm35_job_finished.
        PERFORM stop_0500_timer.
        gv_exec_run_phase = 'SM35 cockpit monitoring stopped; standard SM35 session is unchanged'.
        MESSAGE 'SM35 cockpit monitoring stopped; the standard SM35 session is unchanged.' TYPE 'S' DISPLAY LIKE 'W'.
      ELSE.
        PERFORM stop_bdc_execution.
        gv_exec_stop_req = abap_true.
        gv_exec_run_phase = 'Stop requested; waiting for active business group to return'.
        MESSAGE s034(zbdc).
      ENDIF.
      PERFORM display_0500_queue.
      PERFORM refresh_0500_tools.

 " Refresh queue

    WHEN gc_ucomm_refresh_0500.

      CLEAR: g_stop_flag,
             gv_exec_stop_req.

 "Refresh reconciles the exact current scope. It never clears contradictory
 "runtime flags merely to let another execution start.

      PERFORM refresh_sm35_state.
      PERFORM display_0500_queue.
      CLEAR lv_z714_closed_0500.
      IF gv_exec_run_active = abap_true AND gv_exec_mon_kind = gc_mon_sm35.
        PERFORM close_term_sm35_mon
          CHANGING lv_z714_closed_0500.
      ENDIF.
      PERFORM refresh_0500_tools.

      MESSAGE s035(zbdc).

 " Open error detail

    WHEN gc_ucomm_error_detail.

      PERFORM open_0500_error_detail.

 " Open Fix Guide

    WHEN gc_ucomm_fix_guide.

      PERFORM open_0500_fix_guide.

 " Open Retry screen

    WHEN gc_ucomm_retry_0500.

      PERFORM open_0500_retry.

 " Open Result Dashboard

    WHEN gc_ucomm_dashboard_0500.

      PERFORM open_result_dash_curr.

 " Internal refresh roundtrip

    WHEN 'ZREF500'.

 "Internal roundtrip only. Next PBO repaints progress and queue data.

 " Live monitor timer tick

    WHEN 'ZLIVE50'.

      PERFORM monitor_0500_tick.

 " Back / Exit

    WHEN 'BACK'.

      IF gv_exec_run_active = abap_true.
        MESSAGE s071(zbdc) DISPLAY LIKE 'W'.
        RETURN.
      ENDIF.

      PERFORM stop_0500_timer.

      CLEAR: gv_exec_run_active,
             gv_exec_run_engine,
             gv_exec_run_phase,
             gv_exec_mon_kind,
             gv_exec_run_total,
             gv_exec_run_done,
             gv_exec_run_queued.

      PERFORM reset_0400_selection.
      PERFORM free_0500_queue.
      gv_0400_view      = gc_view_cockpit.
      gv_0400_edit_mode = space.
      CLEAR: gt_z566_edit_scope, gv_z566_edit_groups.

      LEAVE TO SCREEN 0.

    WHEN 'EXIT'.

      IF gv_exec_run_active = abap_true.
        MESSAGE s071(zbdc) DISPLAY LIKE 'W'.
        RETURN.
      ENDIF.

      PERFORM stop_0500_timer.
      CLEAR: gv_exec_run_active,
             gv_exec_run_engine,
             gv_exec_run_phase,
             gv_exec_mon_kind,
             gv_exec_run_total,
             gv_exec_run_done,
             gv_exec_run_queued.
      PERFORM reset_0400_selection.
      PERFORM free_0500_queue.
      LEAVE PROGRAM.

    WHEN 'CANCEL'.

      IF gv_exec_run_active = abap_true.
        MESSAGE s071(zbdc) DISPLAY LIKE 'W'.
        RETURN.
      ENDIF.

      PERFORM stop_0500_timer.
      CLEAR: gv_exec_run_active,
             gv_exec_run_engine,
             gv_exec_run_phase,
             gv_exec_mon_kind,
             gv_exec_run_total,
             gv_exec_run_done,
             gv_exec_run_queued.
      PERFORM reset_0400_selection.
      PERFORM free_0500_queue.
      gv_0400_view      = gc_view_cockpit.
      gv_0400_edit_mode = space.
      CLEAR: gt_z566_edit_scope, gv_z566_edit_groups.
      LEAVE TO SCREEN 0.

    WHEN OTHERS.

      IF lv_cmd_0500 IS NOT INITIAL.
        MESSAGE s072(zbdc) WITH lv_cmd_0500 DISPLAY LIKE 'W'.
      ENDIF.

  ENDCASE.

ENDMODULE.

MODULE user_command_0560 INPUT.
  save_ok = ok_code.
  CLEAR ok_code.
  CASE save_ok.
 "The SE51 button keeps its existing RPAL/APPLY function code. It now means
 "save the selected correction for the selected retry group scope.
    WHEN 'RPAL' OR 'APPLY'.
      PERFORM apply_correction.

 "Business Group is the first dependency in the correction chain.
 "Assign GRPCHG to P_BUS_GROUP in SE51 so Field/Old Value reload immediately.
    WHEN 'GRPCHG'.
      CLEAR: p_fld_name, p_old_val, p_new_val,
             gv_0560_prepared, gv_0560_last_field.
      REFRESH: gt_0560_map, gt_0560_old_opt.

 "Assign FLDCHG to P_FLD_NAME in SE51. Old Value is always system-derived
 "from the selected Business Group + Field and is never typed by the user.
    WHEN 'FLDCHG'.
      CLEAR: p_old_val, p_new_val, gv_0560_last_field.
      REFRESH gt_0560_old_opt.

 "0560 is a modal correction popup. Every standard window-close/back/cancel
 "command closes only this popup and returns to the execution dashboard.
    WHEN 'EXIT' OR '&F15' OR 'F15' OR 'ENDE' OR 'FC_EXIT'
      OR 'BACK' OR '&F03' OR 'F03' OR 'RW' OR 'FC_BACK'
      OR 'CANCEL' OR 'CANC' OR '&F12' OR 'F12' OR 'ECAN' OR 'FC_CANCEL'.
      IF gt_0560_ready_done IS NOT INITIAL.
        PERFORM display_0500_queue.
        PERFORM select_0500_keys USING gt_0560_ready_done.
      ENDIF.
      PERFORM reset_0560.
      SET SCREEN 0.
      LEAVE SCREEN.
  ENDCASE.
ENDMODULE.

MODULE user_command_0650 INPUT.
  DATA: lv_ai_0650_ok     TYPE abap_bool,
        lv_ai_status_0650 TYPE char20,
        lv_err_count_0650 TYPE i.

  "Same protection as 0100: a Control Framework timer writes SY-UCOMM while
  "the screen OK_CODE field can still contain an older toolbar command.
  save_ok = sy-ucomm.
  IF save_ok IS INITIAL.
    save_ok = ok_code.
  ENDIF.
  CLEAR: ok_code, sy-ucomm.

  CASE save_ok.
    WHEN 'ZLIVE65'.
      gv_result_0650_tick = abap_true.
      PERFORM refresh_result_invest_0650.

    WHEN 'RGSEL'.
      PERFORM select_result_group_0650 USING gv_group_pick_0650.

    WHEN 'REFL' OR 'REFR' OR 'REFRESH' OR 'FC_REFRESH'.
      "0650 is live; manual Refresh is intentionally retired.
      RETURN.

    WHEN 'ME23' OR 'DRILL' OR 'OPENOBJ' OR 'OPEN_OBJECT'.
      "Open SAP Object is intentionally retired from the 0650 toolbar.
      RETURN.

    WHEN 'AI' OR 'GT07'.

      IF txtp_result_session IS INITIAL OR txtp_result_group IS INITIAL.
        MESSAGE 'Choose one ERROR Result Group before using Analyze Error.'
          TYPE 'S' DISPLAY LIKE 'W'.
        RETURN.
      ENDIF.

      lv_ai_status_0650 = txtp_result_status.
      CONDENSE lv_ai_status_0650 NO-GAPS.
      TRANSLATE lv_ai_status_0650 TO UPPER CASE.
      IF lv_ai_status_0650 <> 'ERROR'.
        MESSAGE 'Analyze Error is available only for groups with ERROR status.'
          TYPE 'S' DISPLAY LIKE 'W'.
        RETURN.
      ENDIF.

      txtp_ai_session  = txtp_result_session.
      txtp_ai_group    = txtp_result_group.
      txtp_ai_tcode    = txtp_result_tcode.
      txtp_ai_source   = 'Execution Result Log'.

      PERFORM prepare_ai_session
        USING    txtp_result_session
        CHANGING lv_ai_0650_ok.

      IF lv_ai_0650_ok <> abap_true.
        MESSAGE 'The selected ERROR group has no persisted error evidence to analyze.'
          TYPE 'S' DISPLAY LIKE 'W'.
        RETURN.
      ENDIF.

      CLEAR lv_err_count_0650.
      LOOP AT gt_result_all INTO DATA(ls_err_0650) WHERE msg_type = 'E'.
        lv_err_count_0650 = lv_err_count_0650 + 1.
      ENDLOOP.

      IF lv_err_count_0650 <= 0.
        MESSAGE 'The selected ERROR group has no ERROR evidence to analyze.'
          TYPE 'S' DISPLAY LIKE 'W'.
        RETURN.
      ENDIF.

      txtp_ai_evidence = |{ lv_err_count_0650 } error message(s)|.

      "New exact group: allow one fresh automatic deterministic diagnosis.
      CLEAR: gv_ai_auto_diag_done,
             gv_ai_auto_diag_key.

      PERFORM stop_result_timer_0650.
      CALL SCREEN 0700.

    "Historical 0650 COPY/Export Error actions are intentionally inert even
    "if an older GUI status still contains them.
    WHEN 'COPY' OR 'CPY' OR 'FC_EXP_ERR' OR 'EXPT' OR 'EXPORT'.
      RETURN.

    WHEN 'EXIT' OR '&F15' OR 'F15' OR 'ENDE' OR 'FC_EXIT'.
      PERFORM stop_result_timer_0650.
      LEAVE PROGRAM.

    WHEN 'BACK' OR '&F03' OR 'F03' OR 'RW' OR 'FC_BACK'
      OR 'CANCEL' OR 'CANC' OR '&F12' OR 'F12' OR 'ECAN' OR 'FC_CANCEL'.
      PERFORM stop_result_timer_0650.
      SET SCREEN 0.
      LEAVE SCREEN.

    WHEN OTHERS.
      "Fail closed: an unrelated toolbar/menu code must never open a SAP object
      "or mutate investigation context implicitly.
      RETURN.
  ENDCASE.
ENDMODULE.
MODULE user_command_0700 INPUT.

  save_ok = ok_code.

  IF save_ok IS INITIAL.
    save_ok = sy-ucomm.
  ENDIF.

  CLEAR: ok_code, sy-ucomm.

  CASE save_ok.

    WHEN 'ISSEL'.
      PERFORM select_issue_0700 USING gv_issue_pick_0700.

    WHEN 'DIAG' OR 'ANALYZE' OR 'RULE' OR 'RULE_AI' OR 'RULE_BASED'
      OR 'DIAGNOSE'.
      PERFORM run_rule_ai_for_session.

    WHEN 'DOWN' OR 'EXPORT' OR 'EXPFIX' OR 'AI_EXPORT'
      OR 'FC_EXPORT' OR 'EXP_GUIDE' OR 'EXPORT_GUIDE'
      OR 'EXPORT_FIX' OR 'FIX_EXPORT'.
      PERFORM export_ai_fix_guide.

    WHEN 'GT08' OR 'SHDB' OR 'SCRIPT' OR 'REC'.
      CALL SCREEN 0800.

    WHEN 'EXIT' OR '&F15' OR 'F15' OR 'ENDE' OR 'FC_EXIT'.
      PERFORM stop_result_timer_0650.
      LEAVE PROGRAM.

    WHEN 'BACK' OR '&F03' OR 'F03' OR 'RW' OR 'FC_BACK'
      OR 'CANCEL' OR 'CANC' OR '&F12' OR 'F12' OR 'ECAN' OR 'FC_CANCEL'.
      PERFORM stop_result_timer_0650.
      SET SCREEN 0.
      LEAVE SCREEN.

    WHEN OTHERS.
      IF save_ok IS NOT INITIAL.
        MESSAGE s073(zbdc) WITH save_ok DISPLAY LIKE 'W'.
      ENDIF.

  ENDCASE.

ENDMODULE.
*& Module USER_COMMAND_0800 INPUT
*& Configuration / Onboarding navigation

MODULE user_command_0800 INPUT.

  DATA: lv_auto_map_ok  TYPE abap_bool,
        lv_auto_map_msg TYPE string.

  CLEAR save_ok.

  save_ok = ok_code.
  IF save_ok IS INITIAL.
    save_ok = sy-ucomm.
  ENDIF.

  CLEAR: ok_code, sy-ucomm.

  CASE save_ok.

    WHEN 'ZRECSTART'.

 "Some SAP GUI/ALV variants route the 0800 toolbar function
 "through dynpro PAI instead of the CL_GUI_ALV_GRID event callback.
 "Start Recording is an onboarding acquisition command, not Mapping.
      PERFORM start_guided_recording.
      PERFORM display_script_editor.

    WHEN 'IMPORT'.

      PERFORM upload_shdb_recording.
      PERFORM display_script_editor.

    WHEN 'ZMYIMP'.

      PERFORM pick_import_history USING gc_file_scope_my.
      PERFORM display_script_editor.

    WHEN 'ZALLIMP'.

      PERFORM pick_import_history USING gc_file_scope_all.
      PERFORM display_script_editor.

    WHEN 'MAPPING'.

 "do not reject the Mapping command before the shared Mapping
 "preparer has a chance to resolve a fresh Guided/Import acquisition.
 "auto_prep_map_on_open already distinguishes three safe cases:
 " 1) fresh raw Start/Import evidence -> strict candidate Mapping view,
 " 2) an exact pinned immutable tuple -> official Mapping context,
 " 3) no usable evidence/context -> fail closed with a clear message.
 "The old pre-check duplicated only case (2), so a valid Start Recording
 "whose schema was reusable but whose technical recorder rows differed was
 "blocked here before M2 could pin/rebuild its Mapping context.
      IF p_rec_tcode IS NOT INITIAL.
        p_transaction = p_rec_tcode.
      ENDIF.

 "The Mapping command verifies/prepares context but never saves or
 "activates the contract merely by opening screen 0350.
      CLEAR: lv_auto_map_ok, lv_auto_map_msg.
      PERFORM auto_prep_map_on_open
        CHANGING lv_auto_map_ok lv_auto_map_msg.

      IF lv_auto_map_ok <> abap_true.
        IF lv_auto_map_msg IS INITIAL.
          lv_auto_map_msg = 'Mapping context is not exact. Select My Import or All Import first.'.
        ENDIF.
        MESSAGE lv_auto_map_msg TYPE 'S' DISPLAY LIKE 'W'.
        RETURN.
      ENDIF.

      IF lv_auto_map_msg IS NOT INITIAL.
        MESSAGE lv_auto_map_msg TYPE 'S'.
      ENDIF.

      CALL SCREEN 0350.

 "UI_CLEAN: screen 0800 is audit/import navigation only.
 "Manual Save/Insert/Delete commands were removed from the toolbar and PAI.
    WHEN 'EXIT' OR '&F15' OR 'F15' OR 'ENDE' OR 'FC_EXIT'.
      PERFORM stop_result_timer_0650.
      LEAVE PROGRAM.

    WHEN 'BACK' OR '&F03' OR 'F03' OR 'RW' OR 'FC_BACK'
      OR 'CANCEL' OR 'CANC' OR '&F12' OR 'F12' OR 'ECAN' OR 'FC_CANCEL'.
      PERFORM stop_result_timer_0650.
      SET SCREEN 0.
      LEAVE SCREEN.

    WHEN OTHERS.

      IF save_ok IS NOT INITIAL.
        MESSAGE s076(zbdc) WITH save_ok DISPLAY LIKE 'W'.
      ENDIF.

  ENDCASE.

ENDMODULE.

*& 0300 runtime config save only
*& Save on screen 0300 is independent from Upload/Preview.
*& It persists only the execution policy selected on the top config block:
*& execution engine: CALL_TRANSACTION / BATCH_INPUT
*& CT display mode: N / E / A
*& CT update mode: A / S
*& batch size
*& It intentionally does not touch FILE_PATH, SOURCE_TYPE, GDrive/Gmail,
*& staging rows, preview tables, or current session.

FORM save_0300_runtime_config.
  DATA: lv_ok  TYPE abap_bool,
        lv_msg TYPE string.

 "0300 Save is runtime-only. The bounded config service is the single
 "writer for BDC_MODE/BDC_UPDATE/BDC_EXEC_MODE/BATCH_SIZE/TIMEOUT/RETRY.
 "It never persists SOURCE_TYPE, FILE_PATH, TCODE, session, profile,
 "script, contract hash, or connector credentials.
  PERFORM save_runtime_config
    CHANGING lv_ok lv_msg.

  IF lv_ok = abap_true.
    MESSAGE s735(zbdc).
  ELSE.
    MESSAGE s736(zbdc) WITH lv_msg DISPLAY LIKE 'E'.
  ENDIF.
ENDFORM.
