
*& Include Z_BDC_MASS_PO_ENTRY_F01_BUP
*& Purpose Local ALV/grid/timer event-handler implementations
*& UI event boundary only

*& Local event handlers - implementations moved out of TOP include

* ============================================================
* Dashboard timer implementation.
* The timer only posts a lightweight OK code; normal PAI/PBO performs the
* database refresh, so no dynpro control is updated from the event callback.
* ============================================================
CLASS lcl_exec_timer IMPLEMENTATION.
  METHOD on_finished.
    DATA: lv_qstate TYPE apqi-qstate,
          lv_found  TYPE abap_bool,
          lt_probe_log TYPE ty_t_bdclm,
          ls_probe_log TYPE bdclm,
          lv_proto_ready TYPE abap_bool,
          lv_term_signal TYPE abap_bool.

    IF gv_timer_0500_on = abap_true.
      TRY.
          IF sy-dynnr = '0500'.
            CLEAR lv_term_signal.
 "keep the GUI timer callback lightweight. The old
 "/712 callback attempted to read the SM35 TemSe protocol
 "inside the Control Framework timer event before posting PAI.
 "Across a /o-style second SAP mode that event can be delayed or
 "fail to drive the dynpro roundtrip, so the exact QID was already
 "terminal in SM35 but 0500 stayed yellow until Refresh Queue.

 "For a durable exact QID, APQI F/E is enough to request ONE normal
 "0500 PAI. monitor_sm35_tick/reconcile_sm35 then perform
 "the TemSe stabilization/read in normal dynpro context (including
 "Extended-log business S-message capture). While New/In Process
 "there is still no PAI/PBO every second, so no flicker returns.
            IF gv_exec_run_active = abap_true AND
               gv_exec_mon_kind = gc_mon_sm35 AND
               gv_sm35_mon_qid IS NOT INITIAL.
              CLEAR: lv_qstate, lv_found.
              SELECT SINGLE qstate
                FROM apqi
                INTO @lv_qstate
                WHERE mandant = @sy-mandt
                  AND qid     = @gv_sm35_mon_qid
                  AND datatyp = 'BDC'.
              IF sy-subrc = 0.
                lv_found = abap_true.
              ENDIF.

              IF lv_found = abap_true AND
                 ( lv_qstate = 'F' OR lv_qstate = 'E' ).
                cl_gui_cfw=>set_new_ok_code( new_code = 'ZLIVE50' ).
                lv_term_signal = abap_true.

              ELSEIF lv_found <> abap_true.
 "Rare SAP variants can remove/move APQI before the frontend
 "sees F/E. In that case probe only for terminal exact-QID
 "protocol; do not infer a result from GROUP/time.
                CLEAR lv_proto_ready.
                REFRESH lt_probe_log.
                PERFORM get_sm35_log
                  USING    gv_sm35_mon_qid
                  CHANGING lt_probe_log.
                LOOP AT lt_probe_log INTO ls_probe_log.
                  IF ls_probe_log-mart = 'E' OR
                     ls_probe_log-mart = 'A' OR
                     ls_probe_log-mart = 'X' OR
                     ( ls_probe_log-mart = 'S' AND
                       ls_probe_log-mid  = '00' AND
                       ls_probe_log-mnr  = '382' ).
                    lv_proto_ready = abap_true.
                    EXIT.
                  ENDIF.
                ENDLOOP.
                IF lv_proto_ready = abap_true.
                  cl_gui_cfw=>set_new_ok_code( new_code = 'ZLIVE50' ).
                  lv_term_signal = abap_true.
                ENDIF.
              ENDIF.
            ELSE.
              cl_gui_cfw=>set_new_ok_code( new_code = 'ZLIVE50' ).
            ENDIF.

 "terminal exact-QID notification is one-shot. Do not
 "immediately re-arm the Control Framework timer after posting
 "ZLIVE50; repeated terminal timer events could race/overwrite the
 "pending OK-code and leave the cockpit waiting for manual Refresh.
            IF lv_term_signal = abap_true.
              CLEAR gv_timer_0500_on.
              TRY.
                  cl_gui_cfw=>flush( ).
                CATCH cx_root.
              ENDTRY.
            ELSEIF go_timer_0500 IS BOUND AND gv_timer_0500_on = abap_true.
              go_timer_0500->run( ).
            ENDIF.
          ELSE.
 "This original ABAP session owns the 0500 timer. A separate
 "/o SM35 mode has its own ABAP session and does not modify this
 "timer object.
            CLEAR gv_timer_0500_on.
            IF go_timer_0500 IS BOUND.
              go_timer_0500->cancel( ).
            ENDIF.
          ENDIF.
        CATCH cx_root.
          CLEAR gv_timer_0500_on.
      ENDTRY.
    ENDIF.
  ENDMETHOD.
ENDCLASS.

* ============================================================
* Main Dashboard live timer.
* Only posts a silent dynpro OK-code. Database reads and screen-field changes
* happen in normal PAI/PBO, never inside the Control Framework callback.
* ============================================================
CLASS lcl_dash_timer_0100 IMPLEMENTATION.
  METHOD on_finished.
    IF gv_timer_0100_on <> abap_true.
      RETURN.
    ENDIF.

    TRY.
        IF sy-dynnr = '0100'.
          cl_gui_cfw=>set_new_ok_code( new_code = 'ZLIVE10' ).
          TRY.
              cl_gui_cfw=>flush( ).
            CATCH cx_root.
          ENDTRY.

          IF go_timer_0100 IS BOUND AND gv_timer_0100_on = abap_true.
            go_timer_0100->run( ).
          ENDIF.
        ELSE.
          PERFORM stop_dash_timer.
        ENDIF.
      CATCH cx_root.
        PERFORM stop_dash_timer.
    ENDTRY.
  ENDMETHOD.
ENDCLASS.

FORM start_dash_timer.
  TRY.
      IF go_timer_0100 IS NOT BOUND.
        CREATE OBJECT go_timer_0100.
      ENDIF.

      IF go_timer_hdl_0100 IS NOT BOUND.
        CREATE OBJECT go_timer_hdl_0100.
        SET HANDLER go_timer_hdl_0100->on_finished FOR go_timer_0100.
      ENDIF.

      go_timer_0100->interval = gv_timer_0100_sec.
      IF gv_timer_0100_on <> abap_true.
        gv_timer_0100_on = abap_true.
        go_timer_0100->run( ).
      ENDIF.
    CATCH cx_root.
      CLEAR gv_timer_0100_on.
  ENDTRY.
ENDFORM.

* ============================================================
* Main Dashboard keeps display-only real-time KPIs.
* KPI Text/I-O fields on screen 0100 are presentation only; no click/drill-down
* function codes are registered here.
* ============================================================
FORM stop_dash_timer.
  CLEAR: gv_timer_0100_on, gv_dash_0100_tick.
  IF go_timer_0100 IS BOUND.
    TRY.
        go_timer_0100->cancel( ).
      CATCH cx_root.
    ENDTRY.
  ENDIF.
ENDFORM.


* ============================================================
* Result Investigation live timer (0650).
* Mirrors 0100: timer callback is lightweight and posts only ZLIVE65.
* ============================================================
CLASS lcl_result_timer_0650 IMPLEMENTATION.
  METHOD on_finished.
    IF gv_timer_0650_on <> abap_true.
      RETURN.
    ENDIF.

    TRY.
        IF sy-dynnr = '0650'.
          cl_gui_cfw=>set_new_ok_code( new_code = 'ZLIVE65' ).
          TRY.
              cl_gui_cfw=>flush( ).
            CATCH cx_root.
          ENDTRY.

          IF go_timer_0650 IS BOUND AND gv_timer_0650_on = abap_true.
            go_timer_0650->run( ).
          ENDIF.
        ELSE.
          PERFORM stop_result_timer_0650.
        ENDIF.
      CATCH cx_root.
        PERFORM stop_result_timer_0650.
    ENDTRY.
  ENDMETHOD.
ENDCLASS.

FORM start_result_timer_0650.
  TRY.
      IF go_timer_0650 IS NOT BOUND.
        CREATE OBJECT go_timer_0650.
      ENDIF.

      IF go_timer_hdl_0650 IS NOT BOUND.
        CREATE OBJECT go_timer_hdl_0650.
        SET HANDLER go_timer_hdl_0650->on_finished FOR go_timer_0650.
      ENDIF.

      go_timer_0650->interval = gv_timer_0650_sec.
      IF gv_timer_0650_on <> abap_true.
        gv_timer_0650_on = abap_true.
        go_timer_0650->run( ).
      ENDIF.
    CATCH cx_root.
      CLEAR gv_timer_0650_on.
  ENDTRY.
ENDFORM.

FORM stop_result_timer_0650.
  CLEAR: gv_timer_0650_on, gv_result_0650_tick.
  IF go_timer_0650 IS BOUND.
    TRY.
        go_timer_0650->cancel( ).
      CATCH cx_root.
    ENDTRY.
  ENDIF.
ENDFORM.

* ============================================================
* Result Dashboard native dialog close handler.
* The HTML dashboard has no internal Refresh/Close buttons anymore;
* the SAP GUI dialog X is the single close action.
* ============================================================
CLASS lcl_dash_html_411 IMPLEMENTATION.
  METHOD on_dialog_close.
    PERFORM free_visual_dash.
  ENDMETHOD.
ENDCLASS.

* close handler for generic long-text dialogs.
CLASS lcl_longtext_812 IMPLEMENTATION.
  METHOD on_dialog_close.
    PERFORM free_long_dialog.
  ENDMETHOD.
ENDCLASS.
* ============================================================
* Local SALV event implementation. TOP remains declaration/state only.
* ============================================================
CLASS lcl_alv_events IMPLEMENTATION.
  METHOD on_double_click.
    READ TABLE gt_dash_0100 INTO DATA(ls_dash_0100_evt) INDEX row.
    IF sy-subrc <> 0 OR ls_dash_0100_evt-session_id IS INITIAL.
      MESSAGE s020(zbdc) DISPLAY LIKE 'W'.
      RETURN.
    ENDIF.

 "dashboard double-click is now a read-only drill-down, not a
 "navigation side effect into staging. The Staging toolbar action remains
 "the explicit route to screen 0400 for the selected session.
    PERFORM show_session_groups
      USING ls_dash_0100_evt.
  ENDMETHOD.

  METHOD on_group_double_click.
    READ TABLE gt_group_0100 INTO DATA(ls_group_0100_evt) INDEX row.
    IF sy-subrc <> 0 OR ls_group_0100_evt-session_id IS INITIAL.
      RETURN.
    ENDIF.

 "the two compact Level-2 expand cells own their own click
 "behavior. A double-click there must not fall through into Level 3.
    IF column = 'INPUT_DATA' OR column = 'CHANGES'.
      RETURN.
    ENDIF.

    PERFORM show_group_evidence
      USING ls_group_0100_evt.
  ENDMETHOD.

  METHOD on_group_link_click.
    READ TABLE gt_group_0100 INTO DATA(ls_group_0100_link) INDEX row.
    IF sy-subrc <> 0 OR ls_group_0100_link-session_id IS INITIAL.
      RETURN.
    ENDIF.

    IF column = 'INPUT_DATA' AND ls_group_0100_link-input_data <> '-'.
      PERFORM l2_show_panel
        USING ls_group_0100_link column.
    ELSEIF column = 'CHANGES' AND ls_group_0100_link-changes <> '-'.
      PERFORM l2_show_panel
        USING ls_group_0100_link column.
    ENDIF.
  ENDMETHOD.

  METHOD on_result_group_dbl.
    IF row <= 0.
      RETURN.
    ENDIF.

    "14T: A SALV control event can change backend globals without causing a
    "dynpro PBO. That was the real reason 14S visually stayed on PO_001: the
    "selected row changed, but the screen fields and right evidence control
    "were never repainted. Route the row through the existing RGSEL PAI code
    "so SELECT_RESULT_GROUP_0650 runs in PAI and STATUS_0650 PBO repaints the
    "context/evidence. DISPLAY_RESULT_GROUPS_0650 no longer rebuilds/refreshes
    "the left SALV on normal selection, so its scroll position is preserved.
    gv_group_pick_0650 = row.
    TRY.
        cl_gui_cfw=>set_new_ok_code( new_code = 'RGSEL' ).
      CATCH cx_root.
        "Fallback keeps exact identity pinned; the next normal PBO will paint it.
        PERFORM select_result_group_0650 USING row.
    ENDTRY.
  ENDMETHOD.

  METHOD on_result_group_link.
    IF row <= 0.
      RETURN.
    ENDIF.

    IF column <> 'GROUP_KEY'.
      RETURN.
    ENDIF.

    "14T: Same PAI/PBO bridge for one-click Business Group selection.
    "Do not rebuild or full-refresh the left Result Groups SALV here.
    gv_group_pick_0650 = row.
    TRY.
        cl_gui_cfw=>set_new_ok_code( new_code = 'RGSEL' ).
      CATCH cx_root.
        PERFORM select_result_group_0650 USING row.
    ENDTRY.
  ENDMETHOD.

  METHOD on_issue_0700_dbl.
    IF row <= 0.
      RETURN.
    ENDIF.

    gv_issue_pick_0700 = row.
    TRY.
        cl_gui_cfw=>set_new_ok_code( new_code = 'ISSEL' ).
      CATCH cx_root.
        PERFORM select_issue_0700 USING row.
    ENDTRY.
  ENDMETHOD.

  METHOD on_issue_0700_link.
    IF row <= 0 OR column <> 'SUMMARY'.
      RETURN.
    ENDIF.

    gv_issue_pick_0700 = row.
    TRY.
        cl_gui_cfw=>set_new_ok_code( new_code = 'ISSEL' ).
      CATCH cx_root.
        PERFORM select_issue_0700 USING row.
    ENDTRY.
  ENDMETHOD.

  METHOD on_file_double_click.
    DATA: lv_rows_file    TYPE i,
          lv_load_ok      TYPE abap_bool,
          lv_load_msg     TYPE string,
          lv_display_file TYPE string,
          lv_display_sheet TYPE string.

    READ TABLE gt_files_preview INTO DATA(ls_file) INDEX row.
    IF sy-subrc <> 0.
      RETURN.
    ENDIF.
    IF ls_file-session_id IS INITIAL.
      MESSAGE s022(zbdc) DISPLAY LIKE 'W'.
      RETURN.
    ENDIF.

    PERFORM load_exact_staging
      USING    ls_file-session_id space space
      CHANGING lv_rows_file lv_load_ok lv_load_msg.
    IF lv_load_ok <> abap_true.
      MESSAGE lv_load_msg TYPE 'S' DISPLAY LIKE 'W'.
      RETURN.
    ENDIF.

    REFRESH gt_current_sessions.
    APPEND ls_file-session_id TO gt_current_sessions.

    DATA lv_0300_hist_scope TYPE abap_bool.
    lv_0300_hist_scope = abap_true.
    EXPORT lv_0300_hist_scope = lv_0300_hist_scope TO MEMORY ID 'ZBDC_0300_HISTORY_SCOPE'.

    lv_display_file  = ls_file-file_name.
    lv_display_sheet = ls_file-sheet_name.
    IF lv_display_file CS '|SHEET='.
      SPLIT lv_display_file AT '|SHEET='
        INTO lv_display_file lv_display_sheet.
    ENDIF.
    txtp_file_path = lv_display_file.
    txtp_file_size = ls_file-file_size.
    PERFORM recalc_source_size USING ls_file-channel lv_display_file CHANGING txtp_file_size.
    gv_current_file_name  = ls_file-file_title.
    gv_current_sheet_name = ls_file-sheet_name.
    WRITE lv_rows_file TO txtp_row_count LEFT-JUSTIFIED.
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

    g_sub_dynpro = '0301'.
    ts_preview-activetab = 'TAB_PREVIEW'.
    PERFORM reset_0300_alv.

    TRY.
        cl_gui_cfw=>set_new_ok_code( new_code = 'PREV' ).
      CATCH cx_root.
    ENDTRY.

    IF ls_file-owner IS INITIAL
       OR ls_file-owner = sy-uname
       OR ls_file-owner = 'UNKNOWN'.
      MESSAGE s023(zbdc) WITH ls_file-file_title lv_rows_file.
    ELSE.
      MESSAGE s024(zbdc) WITH ls_file-owner.
    ENDIF.
  ENDMETHOD.

  METHOD on_file_function.
    CASE e_salv_function.
      WHEN 'ZMYFILES'.
        gv_file_scope = gc_file_scope_my.
      WHEN 'ZALLFILES'.
        gv_file_scope = gc_file_scope_all.
      WHEN OTHERS.
        RETURN.
    ENDCASE.

    PERFORM prepare_preview_file.
    PERFORM refresh_0302_scope.
  ENDMETHOD.

  METHOD on_fixguide_double_click.
    READ TABLE gt_fix_guide_789 INTO DATA(ls_fix_evt_789) INDEX row.
    IF sy-subrc <> 0.
      RETURN.
    ENDIF.

    IF ls_fix_evt_789-section = 'Run AI Analysis' OR
       ls_fix_evt_789-section = 'Re-run AI Analysis'.
      PERFORM run_fixguide_ai.
      RETURN.
    ENDIF.

 "classic SALV cannot wrap one cell across multiple display lines.
 "For any long Fix Guide explanation, double-click opens a dedicated
 "read-only full-text popup split into readable lines. No AI/evidence
 "content is shortened or rewritten to make it fit the main grid.
    IF strlen( ls_fix_evt_789-detail ) > 90.
      PERFORM show_fixguide_text
        USING ls_fix_evt_789-section ls_fix_evt_789-detail.
    ENDIF.
  ENDMETHOD.

  METHOD on_fixguide_function.
    IF e_salv_function = 'ZRUNAI'.
      PERFORM run_fixguide_ai.
    ENDIF.
  ENDMETHOD.
ENDCLASS.

FORM open_file_history_row USING iv_row TYPE lvc_index.
  DATA: lv_row_idx       TYPE i,
        lv_rows_file     TYPE i,
        lv_load_ok       TYPE abap_bool,
        lv_load_msg      TYPE string,
        lv_display_file  TYPE string,
        lv_display_sheet TYPE string,
        ls_file          TYPE ty_files_disp.

  lv_row_idx = iv_row.

  READ TABLE gt_files_preview INTO ls_file INDEX lv_row_idx.
  IF sy-subrc <> 0.
    MESSAGE s025(zbdc) DISPLAY LIKE 'W'.
    RETURN.
  ENDIF.

  IF ls_file-session_id IS INITIAL.
    MESSAGE s026(zbdc) DISPLAY LIKE 'W'.
    RETURN.
  ENDIF.

  PERFORM load_exact_staging
    USING    ls_file-session_id space space
    CHANGING lv_rows_file lv_load_ok lv_load_msg.
  IF lv_load_ok <> abap_true.
    MESSAGE lv_load_msg TYPE 'S' DISPLAY LIKE 'W'.
    RETURN.
  ENDIF.

  REFRESH gt_current_sessions.
  APPEND ls_file-session_id TO gt_current_sessions.
  DATA lv_0300_hist_scope TYPE abap_bool.
  lv_0300_hist_scope = abap_true.
  EXPORT lv_0300_hist_scope = lv_0300_hist_scope TO MEMORY ID 'ZBDC_0300_HISTORY_SCOPE'. "history scope without TOP global dependency

  lv_display_file  = ls_file-file_name.
  lv_display_sheet = ls_file-sheet_name.
  IF lv_display_file CS '|SHEET='.
    SPLIT lv_display_file AT '|SHEET='
      INTO lv_display_file lv_display_sheet.
  ENDIF.

  txtp_file_path = lv_display_file.
  txtp_file_size = ls_file-file_size.
  PERFORM recalc_source_size
    USING ls_file-channel lv_display_file
    CHANGING txtp_file_size.

  gv_current_file_name  = ls_file-file_title.
  gv_current_sheet_name = lv_display_sheet.
  gv_current_unit_src   = ls_file-channel.

  WRITE lv_rows_file TO txtp_row_count LEFT-JUSTIFIED.
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

  g_sub_dynpro = '0301'.
  ts_preview-activetab = 'TAB_PREVIEW'.
  PERFORM reset_0300_alv.

  TRY.
      cl_gui_cfw=>set_new_ok_code( new_code = 'PREV' ).
    CATCH cx_root.
  ENDTRY.

  MESSAGE s027(zbdc) WITH ls_file-batch_key lv_rows_file.
ENDFORM.

CLASS lcl_grid_events IMPLEMENTATION.
  METHOD configure_0400_grid.
    IF ir_grid IS BOUND.
      CALL METHOD ir_grid->set_delay_change_selection
        EXPORTING time = 100
        EXCEPTIONS error = 1 OTHERS = 2.
    ENDIF.
  ENDMETHOD.


  METHOD on_0650_delayed_sel.
    DATA: lt_rows_0650 TYPE lvc_t_row,
          ls_row_0650  TYPE lvc_s_row.

    IF go_group_grid_0650 IS NOT BOUND.
      RETURN.
    ENDIF.

    CALL METHOD go_group_grid_0650->get_selected_rows
      IMPORTING
        et_index_rows = lt_rows_0650.

    READ TABLE lt_rows_0650 INTO ls_row_0650 INDEX 1.
    IF sy-subrc <> 0 OR ls_row_0650-index <= 0.
      RETURN.
    ENDIF.

    READ TABLE gt_group_0650 INTO DATA(ls_disp_0650) INDEX ls_row_0650-index.
    IF sy-subrc <> 0 OR ls_disp_0650-is_header = abap_true.
      RETURN.
    ENDIF.

    gv_group_pick_0650 = ls_row_0650-index.

    "14U: row-marker/single-selection must behave exactly like selecting a
    "Result Group. CL_SALV_TABLE has no generic single-row selection event;
    "the 14R/14T hotspot path only fired when GROUP_KEY text itself was
    "clicked, so clicks on the row selector merely highlighted a row and left
    "Context/Evidence unchanged. The 0650 left pane now uses CL_GUI_ALV_GRID
    "and DELAYED_CHANGED_SEL_CALLBACK, then bridges into the existing RGSEL
    "PAI/PBO route. The grid object is not rebuilt on selection, so its viewport
    "stays where the user clicked.
    TRY.
        cl_gui_cfw=>set_new_ok_code( new_code = 'RGSEL' ).
      CATCH cx_root.
        PERFORM select_result_group_0650 USING gv_group_pick_0650.
    ENDTRY.
  ENDMETHOD.

  METHOD on_0650_hotspot_click.
    DATA lv_row_0650 TYPE i.

    lv_row_0650 = es_row_no-row_id.
    IF lv_row_0650 <= 0.
      lv_row_0650 = e_row_id-index.
    ENDIF.

    IF lv_row_0650 <= 0.
      RETURN.
    ENDIF.

    READ TABLE gt_group_0650 INTO DATA(ls_disp_hot_0650) INDEX lv_row_0650.
    IF sy-subrc <> 0 OR ls_disp_hot_0650-is_header = abap_true.
      RETURN.
    ENDIF.

    gv_group_pick_0650 = lv_row_0650.

    "14W: every visible Result Groups cell is a hotspot.  This is the
    "immediate single-click path.  The delayed row-selection event remains
    "only as a fallback for the row-marker area.
    TRY.
        cl_gui_cfw=>set_new_ok_code( new_code = 'RGSEL' ).
      CATCH cx_root.
        PERFORM select_result_group_0650 USING gv_group_pick_0650.
    ENDTRY.
  ENDMETHOD.

  METHOD on_0301_toolbar.
    DATA ls_btn TYPE stb_button.

 "keep the standard ALV filter/sort tools; they are useful for
 "large file histories and data previews and do not change persisted data.

    IF ts_preview-activetab <> 'TAB_FILES'.
      RETURN.
    ENDIF.

    DELETE e_object->mt_toolbar WHERE function = gc_fc_file_my.
    DELETE e_object->mt_toolbar WHERE function = gc_fc_file_all.

    CLEAR ls_btn.
    ls_btn-butn_type = 3.
    INSERT ls_btn INTO e_object->mt_toolbar INDEX 1.

    CLEAR ls_btn.
    ls_btn-function  = gc_fc_file_all.
    ls_btn-text      = 'All Uploads'.
    ls_btn-quickinfo = 'Show shared file/source history'.
    ls_btn-butn_type = 0.
    INSERT ls_btn INTO e_object->mt_toolbar INDEX 1.

    CLEAR ls_btn.
    ls_btn-function  = gc_fc_file_my.
    ls_btn-text      = 'My Uploads'.
    ls_btn-quickinfo = 'Show file/source history uploaded by the current SAP user'.
    ls_btn-butn_type = 0.
    INSERT ls_btn INTO e_object->mt_toolbar INDEX 1.
  ENDMETHOD.

  METHOD on_0301_user_command.
    DATA: lt_fcat_0301   TYPE lvc_t_fcat,
          ls_stable      TYPE lvc_s_stbl,
          ls_layout_0301 TYPE lvc_s_layo.

    IF ts_preview-activetab <> 'TAB_FILES'.
      RETURN.
    ENDIF.

    CASE e_ucomm.
      WHEN gc_fc_file_my.
        gv_file_scope = gc_file_scope_my.
      WHEN gc_fc_file_all.
        gv_file_scope = gc_file_scope_all.
      WHEN OTHERS.
        RETURN.
    ENDCASE.

    PERFORM prepare_preview_file.
    PERFORM project_files_to_0301.
    PERFORM build_fcat_0301 CHANGING lt_fcat_0301.

    IF go_alv_0301 IS BOUND.
      CALL METHOD go_alv_0301->set_frontend_fieldcatalog
        EXPORTING it_fieldcatalog = lt_fcat_0301.

      "Scope switch is a frontend ALV event, so screen PBO does not run here.
      "Update the live grid title explicitly; otherwise the data changes from
      "My Uploads to All Uploads (or back) while the old title stays visible.
      CALL METHOD go_alv_0301->get_frontend_layout
        IMPORTING es_layout = ls_layout_0301.
      IF gv_file_scope = gc_file_scope_all.
        ls_layout_0301-grid_title = |Preview Files - All Uploads ({ lines( gt_files_preview ) })|.
      ELSE.
        ls_layout_0301-grid_title = |Preview Files - My Uploads ({ lines( gt_files_preview ) })|.
      ENDIF.
      CALL METHOD go_alv_0301->set_frontend_layout
        EXPORTING is_layout = ls_layout_0301.

      ls_stable-row = abap_true.
      ls_stable-col = abap_true.
      CALL METHOD go_alv_0301->refresh_table_display
        EXPORTING is_stable = ls_stable
                  i_soft_refresh = abap_false.
      CALL METHOD cl_gui_cfw=>flush
        EXCEPTIONS cntl_system_error = 1 cntl_error = 2 OTHERS = 3.
    ENDIF.

    IF gv_file_scope = gc_file_scope_all.
      DATA(lv_zm028_322_1) = lines( gt_files_preview ).
      MESSAGE s028(zbdc) WITH lv_zm028_322_1.
    ELSE.
      DATA(lv_zm029_324_1) = lines( gt_files_preview ).
      MESSAGE s029(zbdc) WITH lv_zm029_324_1.
    ENDIF.
  ENDMETHOD.

  METHOD on_0301_double_click.
    IF ts_preview-activetab <> 'TAB_FILES'.
      RETURN.
    ENDIF.
    PERFORM open_file_history_row USING e_row-index.
  ENDMETHOD.

  METHOD on_0301_hotspot_click.
    IF ts_preview-activetab <> 'TAB_FILES'.
      RETURN.
    ENDIF.
    IF e_column_id-fieldname = 'BATCH_KEY'
       OR e_column_id-fieldname = 'FILE_TITLE'.
      PERFORM open_file_history_row USING e_row_id-index.
    ENDIF.
  ENDMETHOD.
  METHOD on_0400_toolbar.
    DATA ls_btn TYPE stb_button.

    "Screen 0400 editing is owned by the ALV toolbar, not by SE41.
    "Remove local row operations and generic refresh actions so staging
    "lineage remains upload-created and refresh stays implicit.
    DELETE e_object->mt_toolbar WHERE function = 'ZSTGEDIT'.
    DELETE e_object->mt_toolbar WHERE function = 'ZSTGSAV'.
    DELETE e_object->mt_toolbar WHERE function = 'ZSTGCAN'.
    DELETE e_object->mt_toolbar WHERE function = 'ZSTGAUD'.
    DELETE e_object->mt_toolbar WHERE function = 'ZNAVSET'.
    DELETE e_object->mt_toolbar WHERE function = '&REFRESH'.
    DELETE e_object->mt_toolbar WHERE function = 'REFRESH'.
    DELETE e_object->mt_toolbar WHERE function = '&LOCAL&APPEND'.
    DELETE e_object->mt_toolbar WHERE function = '&LOCAL&INSERT_ROW'.
    DELETE e_object->mt_toolbar WHERE function = '&LOCAL&DELETE_ROW'.
    DELETE e_object->mt_toolbar WHERE function = '&LOCAL&COPY_ROW'.
    DELETE e_object->mt_toolbar WHERE function = '&LOCAL&CUT'.
    DELETE e_object->mt_toolbar WHERE function = '&LOCAL&PASTE'.
    DELETE e_object->mt_toolbar WHERE function = '&LOCAL&PASTE_NEW_ROW'.

    IF gt_staging IS INITIAL.
      RETURN.
    ENDIF.

    CLEAR ls_btn.
    ls_btn-butn_type = 3.
    APPEND ls_btn TO e_object->mt_toolbar.

    IF gv_0400_view = gc_view_cockpit.
      CLEAR ls_btn.
      ls_btn-function  = 'ZSTGEDIT'.
      ls_btn-text      = 'Edit Staging'.
      ls_btn-quickinfo = 'Select one, several, or all cockpit groups first; only uploaded columns can be edited'.
      ls_btn-butn_type = 0.
      APPEND ls_btn TO e_object->mt_toolbar.

      CLEAR ls_btn.
      ls_btn-function  = 'ZNAVSET'.
      ls_btn-text      = 'AI Navigation'.
      ls_btn-quickinfo = 'Select one SUCCESS row; open the current-row SAP route visibly before certification'.
      ls_btn-butn_type = 0.
      APPEND ls_btn TO e_object->mt_toolbar.
    ELSE.
      CLEAR ls_btn.
      ls_btn-function  = 'ZSTGSAV'.
      ls_btn-text      = 'Save Changes'.
      ls_btn-quickinfo = 'Audit changed fields, validate again, and persist the staging update'.
      ls_btn-butn_type = 0.
      APPEND ls_btn TO e_object->mt_toolbar.

      CLEAR ls_btn.
      ls_btn-function  = 'ZSTGCAN'.
      ls_btn-text      = 'Cancel Edit'.
      ls_btn-quickinfo = 'Discard unsaved staging edits and return to the cockpit'.
      ls_btn-butn_type = 0.
      APPEND ls_btn TO e_object->mt_toolbar.
    ENDIF.
  ENDMETHOD.

  METHOD on_0400_user_command.
 "never destroy/rebuild the ALV from inside its own USER_COMMAND
 "callback. The toolbar event only posts an internal dynpro OK_CODE;
 "screen 0400 PAI owns Edit/Save/Cancel/Audit and PBO rebuilds the view.
    CASE e_ucomm.
      WHEN 'ZSTGEDIT' OR 'ZSTGSAV' OR 'ZSTGCAN' OR 'ZSTGAUD' OR 'ZNAVSET'.
        TRY.
            cl_gui_cfw=>set_new_ok_code( new_code = e_ucomm ).
          CATCH cx_root.
 "Fail closed: no direct staging mutation is attempted here.
            RETURN.
        ENDTRY.
      WHEN OTHERS.
        RETURN.
    ENDCASE.
  ENDMETHOD.

  METHOD on_0400_hotspot_click.
    DATA lv_index TYPE i.

    IF gv_0400_view <> gc_view_cockpit OR
       e_column_id-fieldname <> 'SAP_OBJECT_TEXT' OR
       e_row_id-index <= 0.
      RETURN.
    ENDIF.

    lv_index = e_row_id-index.
    PERFORM open_exec_navigation USING lv_index.
  ENDMETHOD.

  METHOD on_z770_audit_double_click.
    DATA lv_index TYPE i.

    IF e_row-index <= 0.
      RETURN.
    ENDIF.

 "CL_GUI_ALV_GRID supplies E_ROW-INDEX with the ALV index
 "type. PERFORM USING is pass-by-reference and therefore requires a
 "technically compatible actual parameter for IV_INDEX TYPE I. Copy
 "the ALV index into a plain TYPE I before calling the existing form.
    lv_index = e_row-index.
    PERFORM show_audit_detail USING lv_index.
  ENDMETHOD.

  METHOD on_z770_dialog_close.
 "the title-bar X of CL_GUI_DIALOGBOX_CONTAINER only raises
 "the CLOSE event. Without a registered handler the frontend window
 "stays alive. Free the complete Change History control tree here.
    PERFORM free_change_history.
  ENDMETHOD.

  METHOD on_0500_toolbar.
    DATA ls_btn    TYPE stb_button.
    DATA lv_busy   TYPE c LENGTH 1.
    DATA lv_batch  TYPE abap_bool.
    DATA lv_sm35_busy TYPE abap_bool.
    DATA lv_has_sm35q TYPE abap_bool.
    DATA lv_has_issue TYPE abap_bool.
    DATA lv_has_retry TYPE abap_bool.

    IF gv_exec_run_active = abap_true.
      lv_busy = 'X'.
    ENDIF.

    CLEAR: lv_batch, lv_sm35_busy, lv_has_sm35q.
    IF p_bdc_mode = gc_mode_batch.
      lv_batch = abap_true.
    ENDIF.
    IF gv_exec_run_active = abap_true
       AND gv_exec_mon_kind = gc_mon_sm35.
      lv_sm35_busy = abap_true.
    ENDIF.

 "issue tools are state-aware. SUCCESS/READY/RUNNING/queued groups
 "must not present Error Detail, Fix Guide or Retry as actionable.
    LOOP AT gt_exec_disp ASSIGNING FIELD-SYMBOL(<ls_sm35_btn>).
      IF <ls_sm35_btn>-run_status = gc_st_sm35q OR
         <ls_sm35_btn>-run_status = 'SM35QUEUE' OR
         <ls_sm35_btn>-run_status = 'SM35RUN'.
        lv_has_sm35q = abap_true.
      ENDIF.

      CASE <ls_sm35_btn>-run_status.
        WHEN gc_st_error OR gc_st_warning OR gc_st_skipped OR gc_st_partial
          OR 'BLOCKED_ONBOARDING'.
          lv_has_issue = abap_true.
      ENDCASE.

      CASE <ls_sm35_btn>-run_status.
        WHEN gc_st_error.
          lv_has_retry = abap_true.
      ENDCASE.

    ENDLOOP.

    DELETE e_object->mt_toolbar WHERE function = gc_ucomm_run_0500.
    DELETE e_object->mt_toolbar WHERE function = gc_ucomm_create_sm35.
    DELETE e_object->mt_toolbar WHERE function = gc_ucomm_exec_sm35.
    DELETE e_object->mt_toolbar WHERE function = gc_ucomm_open_sm35.
    DELETE e_object->mt_toolbar WHERE function = gc_ucomm_stop_0500.
    DELETE e_object->mt_toolbar WHERE function = gc_ucomm_refresh_0500.
    DELETE e_object->mt_toolbar WHERE function = gc_ucomm_error_detail.
    DELETE e_object->mt_toolbar WHERE function = gc_ucomm_fix_guide.
    DELETE e_object->mt_toolbar WHERE function = gc_ucomm_retry_0500.
    DELETE e_object->mt_toolbar WHERE function = gc_ucomm_dashboard_0500.
    DELETE e_object->mt_toolbar WHERE function = 'ZNAVSET'.

 "Normal runtime: no separate certification action. The selected executor
 "runs the exact current SHDB recording + Mapping contract directly.
    IF lv_batch <> abap_true.
      CLEAR ls_btn.
      ls_btn-function  = gc_ucomm_run_0500.
      ls_btn-text      = 'Execute Now'.
      ls_btn-quickinfo = 'Run current CALL TRANSACTION queue using exact SHDB recording + Mapping'.
      ls_btn-butn_type = 0.
      ls_btn-disabled  = lv_busy.
      APPEND ls_btn TO e_object->mt_toolbar.
    ENDIF.

    IF lv_batch = abap_true.
      CLEAR ls_btn.
      ls_btn-function  = gc_ucomm_create_sm35.
      ls_btn-text      = 'Create SM35 Session'.
      ls_btn-quickinfo = 'Create one real batch-input session for the exact current READY scope'.
      ls_btn-butn_type = 0.
      ls_btn-disabled  = lv_busy.
      IF lv_has_sm35q = abap_true.
        ls_btn-disabled = 'X'.
      ENDIF.
      APPEND ls_btn TO e_object->mt_toolbar.

      CLEAR ls_btn.
      ls_btn-function  = gc_ucomm_open_sm35.
      ls_btn-text      = 'SM35 Monitor'.
      ls_btn-quickinfo = 'Open SM35 in a separate SAP mode; process exact QID by standard full logging and auto-reconcile 0500'.
      ls_btn-butn_type = 0.
      ls_btn-disabled  = lv_busy.
 "live polling is not a second executor. Keep the standard SM35
 "entry point usable while the exact-QID monitor is active.
      IF lv_sm35_busy = abap_true.
        CLEAR ls_btn-disabled.
      ENDIF.
      IF lv_has_sm35q <> abap_true.
        ls_btn-disabled = 'X'.
      ENDIF.
      APPEND ls_btn TO e_object->mt_toolbar.
    ENDIF.

    CLEAR ls_btn.
    ls_btn-butn_type = 3.
    APPEND ls_btn TO e_object->mt_toolbar.

    CLEAR ls_btn.
    ls_btn-function  = gc_ucomm_stop_0500.
    ls_btn-text      = 'Stop Queue'.
    ls_btn-quickinfo = 'Request stop after current BDC document/group'.
    ls_btn-butn_type = 0.
    IF lv_busy IS INITIAL.
      ls_btn-disabled = 'X'.
    ENDIF.
    APPEND ls_btn TO e_object->mt_toolbar.

    CLEAR ls_btn.
    ls_btn-butn_type = 3.
    APPEND ls_btn TO e_object->mt_toolbar.

    CLEAR ls_btn.
    ls_btn-function  = gc_ucomm_refresh_0500.
    ls_btn-text      = 'Refresh Queue'.
    ls_btn-quickinfo = 'Refresh the visible queue without starting a new run'.
    ls_btn-butn_type = 0.
    IF lv_sm35_busy = abap_true.
      CLEAR ls_btn-disabled.
    ELSE.
      ls_btn-disabled = lv_busy.
    ENDIF.
    APPEND ls_btn TO e_object->mt_toolbar.

    CLEAR ls_btn.
    ls_btn-butn_type = 3.
    APPEND ls_btn TO e_object->mt_toolbar.

    CLEAR ls_btn.
    ls_btn-function  = gc_ucomm_error_detail.
    ls_btn-text      = 'Error Detail'.
    ls_btn-quickinfo = 'Show runtime detail for selected or first failed group'.
    ls_btn-butn_type = 0.
    ls_btn-disabled  = lv_busy.
    IF lv_has_issue <> abap_true.
      ls_btn-disabled = 'X'.
    ENDIF.
    APPEND ls_btn TO e_object->mt_toolbar.

    CLEAR ls_btn.
    ls_btn-function  = gc_ucomm_fix_guide.
    ls_btn-text      = 'Fix Guide'.
    ls_btn-quickinfo = 'Show Fix Guide preview for runtime issues in the current queue'.
    ls_btn-butn_type = 0.
    ls_btn-disabled  = lv_busy.
    IF lv_has_issue <> abap_true.
      ls_btn-disabled = 'X'.
    ENDIF.
    APPEND ls_btn TO e_object->mt_toolbar.


    CLEAR ls_btn.
    ls_btn-function  = gc_ucomm_retry_0500.
    ls_btn-text      = 'Retry'.
    ls_btn-quickinfo = 'Select ERROR group(s), correct data, validate, and return valid groups to READY'.
    ls_btn-butn_type = 0.
    ls_btn-disabled  = lv_busy.
    IF lv_has_retry <> abap_true.
      ls_btn-disabled = 'X'.
    ENDIF.
    APPEND ls_btn TO e_object->mt_toolbar.

 "Dashboard is also a PF-STATUS business/navigation action, not an ALV
 "support action. Keep it out of the ALV toolbar to avoid duplicates.
  ENDMETHOD.

  METHOD on_0500_user_command.
    DATA: lv_cmd      TYPE sy-ucomm,
          lv_state_ok TYPE abap_bool,
          lv_state_msg TYPE string,
          lv_z714_closed TYPE abap_bool,
          lv_z716_synced TYPE abap_bool.

    PERFORM canon_0500_cmd
      USING e_ucomm CHANGING lv_cmd.

    PERFORM check_0500_state
      CHANGING lv_state_ok lv_state_msg.
    IF lv_state_ok <> abap_true
       AND lv_cmd <> gc_ucomm_refresh_0500
       AND lv_cmd <> 'BACK'.
      MESSAGE lv_state_msg TYPE 'S' DISPLAY LIKE 'E'.
      RETURN.
    ENDIF.

    CLEAR: lv_z714_closed, lv_z716_synced.
    IF gv_exec_run_active = abap_true AND gv_exec_mon_kind = gc_mon_sm35.
 "any explicit 0500 action is also a safe terminal wake-up.
 "If the /o SM35 mode has already finished but the frontend timer event
 "was deferred, reconcile the exact QID here instead of forcing the user
 "to press Refresh Queue first.
      PERFORM sync_term_sm35 CHANGING lv_z716_synced.
      IF lv_z716_synced <> abap_true.
        PERFORM sync_0500_q_db USING gt_exec_scope_0500.
        PERFORM close_term_sm35_mon
          CHANGING lv_z714_closed.
      ELSE.
        lv_z714_closed = abap_true.
      ENDIF.
    ENDIF.

    IF gv_exec_run_active = abap_true
       AND lv_cmd <> gc_ucomm_stop_0500
       AND lv_cmd <> gc_ucomm_refresh_0500
       AND lv_cmd <> gc_ucomm_open_sm35
       AND lv_cmd <> gc_ucomm_dashboard_0500.

      IF gv_exec_mon_kind = gc_mon_sm35.
        MESSAGE s031(zbdc) WITH gv_sm35_mon_group DISPLAY LIKE 'W'.
      ELSE.
        MESSAGE s032(zbdc) DISPLAY LIKE 'W'.
      ENDIF.
      RETURN.
    ENDIF.

    CASE lv_cmd.
      WHEN gc_ucomm_run_0500.
        PERFORM request_0500_run USING gc_mode_call.

      WHEN gc_ucomm_create_sm35.
        PERFORM request_0500_run USING gc_mode_batch.

      WHEN gc_ucomm_exec_sm35 OR gc_ucomm_open_sm35.
 "standard SM35 is the only processing owner for BISM.
        PERFORM open_sm35_0500.

      WHEN gc_ucomm_stop_0500.
        IF lv_z714_closed = abap_true.
          MESSAGE 'Execution is already terminal; no Stop Queue action is required.' TYPE 'S'.
        ELSEIF gv_exec_mon_kind = gc_mon_sm35.
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

      WHEN gc_ucomm_refresh_0500.
        CLEAR: g_stop_flag, gv_exec_stop_req.
        PERFORM refresh_sm35_state.
        PERFORM display_0500_queue.
        CLEAR lv_z714_closed.
        IF gv_exec_run_active = abap_true AND gv_exec_mon_kind = gc_mon_sm35.
          PERFORM close_term_sm35_mon
            CHANGING lv_z714_closed.
        ENDIF.
        PERFORM refresh_0500_tools.
        MESSAGE s035(zbdc).

      WHEN gc_ucomm_error_detail.
        PERFORM open_0500_error_detail.

      WHEN gc_ucomm_fix_guide.
        PERFORM open_0500_fix_guide.


      WHEN gc_ucomm_retry_0500.
        PERFORM open_0500_retry.

      WHEN gc_ucomm_dashboard_0500.
        PERFORM open_result_dash_curr.

      WHEN OTHERS.
        IF lv_cmd IS NOT INITIAL.
          MESSAGE s030(zbdc) WITH lv_cmd DISPLAY LIKE 'W'.
        ENDIF.
    ENDCASE.
  ENDMETHOD.

  METHOD on_0500_hotspot_click.
    DATA lv_index TYPE i.

    IF e_column_id-fieldname <> 'EXECUTION' OR
       e_row_id-index <= 0.
      RETURN.
    ENDIF.

    lv_index = e_row_id-index.
    PERFORM show_0500_attempt_history USING lv_index.
  ENDMETHOD.

  METHOD on_0500_attempt_close.
    PERFORM free_0500_attempt_history.
  ENDMETHOD.
ENDCLASS.

*& Legacy F01 kept for local class/event implementations only.
*& Business FORM routines are in ZBDC_MPE_M*_BUP includes.


CLASS ltc_clean_utilities IMPLEMENTATION.
  METHOD split_csv_with_quotes.
    DATA lt_cols TYPE string_table.
    DATA lv_second TYPE string.

    PERFORM split_csv_line_by_delim
      USING    'A,"B,C",D' ','
      CHANGING lt_cols.

    cl_abap_unit_assert=>assert_equals( act = lines( lt_cols ) exp = 3 ).
    READ TABLE lt_cols INTO lv_second INDEX 2.
    cl_abap_unit_assert=>assert_equals( act = lv_second exp = 'B,C' ).
  ENDMETHOD.

  METHOD escape_html_text.
    DATA lv_text TYPE string.

    PERFORM html_escape_text
      USING    '<A&B>'
      CHANGING lv_text.

    cl_abap_unit_assert=>assert_equals(
      act = lv_text
      exp = '&lt;A&amp;B&gt;' ).
  ENDMETHOD.
ENDCLASS.
