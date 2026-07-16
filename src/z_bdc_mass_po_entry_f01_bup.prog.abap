*&---------------------------------------------------------------------*
*& Include          Z_BDC_MASS_PO_ENTRY_F01_BUP (FORMS)
*& MUC 1: giu nguyen 100% (Local/SFTP/Gmail/GDrive + validation 3 lop)
*& MUC 2: EXECUTE_BDC_ENGINE full (Phase 4-5-6-7-8) o CUOI FILE
*&---------------------------------------------------------------------*

*&---------------------------------------------------------------------*
*& Local event handlers - implementations moved out of TOP include
*&---------------------------------------------------------------------*
* V5AF: LCL_ALV_EVENTS implementation is kept in TOP include so the
* compiler always sees the implementation together with its definition.

CLASS lcl_grid_events IMPLEMENTATION.
  METHOD configure_0400_grid.
    IF ir_grid IS BOUND.
      CALL METHOD ir_grid->set_delay_change_selection
        EXPORTING time = 100
        EXCEPTIONS error = 1 OTHERS = 2.
    ENDIF.
  ENDMETHOD.

  METHOD on_exec_double_click.
    "V5AC: cockpit selection uses the standard ALV row selector. Drilldown
    "remains restricted to the explicit SAP Object hotspot column.
    IF e_column-fieldname <> 'SAP_OBJECT_ID'.
      RETURN.
    ENDIF.

    READ TABLE gt_exec_disp INTO DATA(ls_exec) INDEX e_row-index.
    IF sy-subrc = 0.
      PERFORM drilldown_document USING ls_exec.
    ENDIF.
  ENDMETHOD.

  METHOD on_0400_sel_change.
    "V5AK: native ALV selection is the single source of truth.
  ENDMETHOD.

  METHOD on_0400_toolbar.
    "No checkbox column is used. The native left row marker remains the
    "only visible selector; V5AI makes each normal click additive/toggle.
  ENDMETHOD.

  METHOD on_0400_user_command.
    "V5AC: no custom 0400 ALV commands are required.
  ENDMETHOD.

  METHOD on_0500_toolbar.
    DATA ls_btn  TYPE stb_button.
    DATA lv_busy TYPE c LENGTH 1.

    IF gv_exec_run_active = abap_true OR gv_async_active = abap_true.
      lv_busy = 'X'.
    ENDIF.

    "The toolbar event may be triggered again when the run state changes.
    "Remove previous custom entries first so buttons are never duplicated.
    DELETE e_object->mt_toolbar WHERE function = 'RUN0500'.
    DELETE e_object->mt_toolbar WHERE function = 'SM350500'.
    DELETE e_object->mt_toolbar WHERE function = 'OPENSM35'.
    DELETE e_object->mt_toolbar WHERE function = 'STOP0500'.
    DELETE e_object->mt_toolbar WHERE function = 'REF0500'.
    DELETE e_object->mt_toolbar WHERE function = 'ERR0500'.
    DELETE e_object->mt_toolbar WHERE function = 'FIX0500'.
    DELETE e_object->mt_toolbar WHERE function = 'RET0500'.
    DELETE e_object->mt_toolbar WHERE function = 'DAS0500'.

    "V5D: keep the ALV toolbar aligned with STATUS_0500.
    "Main screen toolbar and ALV toolbar expose the two assignment engines.
    "Both consume the A/E/N x S/A profile configured on the setup screen.
    CLEAR ls_btn.
    ls_btn-function  = 'RUN0500'.
    ls_btn-text      = 'Execute Now'.
    ls_btn-quickinfo = 'Create SAP documents now with direct CALL TRANSACTION using the 0100 profile'.
    ls_btn-butn_type = 0.
    ls_btn-disabled  = lv_busy.
    APPEND ls_btn TO e_object->mt_toolbar.

    CLEAR ls_btn.
    ls_btn-function  = 'SM350500'.
    ls_btn-text      = 'Run Batch Session'.
    ls_btn-quickinfo = 'Create a real Batch Input Session and apply the current A/E/N x S/A managed profile'.
    ls_btn-butn_type = 0.
    ls_btn-disabled  = lv_busy.
    APPEND ls_btn TO e_object->mt_toolbar.

    CLEAR ls_btn.
    ls_btn-function  = 'OPENSM35'.
    ls_btn-text      = 'SM35 Monitor'.
    ls_btn-quickinfo = 'Open the standard SM35 monitor for sessions, processing status, and logs'.
    ls_btn-butn_type = 0.
    ls_btn-disabled  = lv_busy.
    APPEND ls_btn TO e_object->mt_toolbar.

    CLEAR ls_btn.
    ls_btn-function  = 'STOP0500'.
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
    ls_btn-function  = 'REF0500'.
    ls_btn-text      = 'Refresh Queue'.
    ls_btn-quickinfo = 'Refresh execution queue'.
    ls_btn-butn_type = 0.
    ls_btn-disabled  = lv_busy.
    APPEND ls_btn TO e_object->mt_toolbar.

    CLEAR ls_btn.
    ls_btn-butn_type = 3.
    APPEND ls_btn TO e_object->mt_toolbar.

    CLEAR ls_btn.
    ls_btn-function  = 'ERR0500'.
    ls_btn-text      = 'Error Detail'.
    ls_btn-quickinfo = 'Show safe runtime detail for selected or first failed group'.
    ls_btn-butn_type = 0.
    ls_btn-disabled  = lv_busy.
    APPEND ls_btn TO e_object->mt_toolbar.

    CLEAR ls_btn.
    ls_btn-function  = 'FIX0500'.
    ls_btn-text      = 'Fix Guide'.
    ls_btn-quickinfo = 'Show safe Fix Guide preview for runtime issues in the current queue'.
    ls_btn-butn_type = 0.
    ls_btn-disabled  = lv_busy.
    APPEND ls_btn TO e_object->mt_toolbar.

    CLEAR ls_btn.
    ls_btn-function  = 'RET0500'.
    ls_btn-text      = 'Retry'.
    ls_btn-quickinfo = 'Open 0560 mass correction / retry for failed groups'.
    ls_btn-butn_type = 0.
    ls_btn-disabled  = lv_busy.
    APPEND ls_btn TO e_object->mt_toolbar.

    CLEAR ls_btn.
    ls_btn-function  = 'DAS0500'.
    ls_btn-text      = 'Dashboard'.
    ls_btn-quickinfo = 'Open 0600 result dashboard for current execution session'.
    ls_btn-butn_type = 0.
    ls_btn-disabled  = lv_busy.
    APPEND ls_btn TO e_object->mt_toolbar.
  ENDMETHOD.

  METHOD on_0500_user_command.
    IF ( gv_exec_run_active = abap_true OR gv_async_active = abap_true ) AND
       e_ucomm <> 'STOP0500'.
      IF gv_exec_mon_kind = 'B'.
        MESSAGE |Managed SM35 session { gv_sm35_mon_group } is still processing. Use Stop Queue or wait for completion.| TYPE 'S'.
      ELSEIF gv_exec_mon_kind = 'F'.
        MESSAGE |SM35 fallback runner is active: { gv_fb_done }/{ gv_fb_total } completed; 0500 repaints after each PO_KEY.| TYPE 'S'.
      ELSE.
        MESSAGE |Queue is processing group { gv_async_key_index }/{ gv_async_total }; remaining selected groups continue automatically.| TYPE 'S'.
      ENDIF.
      RETURN.
    ENDIF.

    CASE e_ucomm.
      WHEN 'RUN0500'.
        PERFORM z19_request_0500_run USING 'C'.
      WHEN 'SM350500'.
        PERFORM z19_request_0500_run USING 'B'.
      WHEN 'OPENSM35'.
        "V5P: destroy the SCREEN0 queue before opening the standard SM35
        "transaction so the fullscreen 0500 ALV cannot cover SM35.
        PERFORM z16_open_sm35_0500.
      WHEN 'STOP0500'.
        PERFORM stop_bdc_execution.
        gv_exec_stop_req = abap_true.
        PERFORM z16_display_0500_queue.
      WHEN 'REF0500'.
        CLEAR g_stop_flag.
        gv_exec_stop_req = abap_false.
        PERFORM z16_refresh_sm35_state.
        PERFORM z16_display_0500_queue.
        MESSAGE 'Execution queue refreshed; stop request cleared.' TYPE 'S'.
      WHEN 'ERR0500'.
        PERFORM z16_open_0500_error_detail.
      WHEN 'FIX0500'.
        PERFORM z16_open_0500_fix_guide.
      WHEN 'RET0500'.
        PERFORM z16_open_0500_retry.
      WHEN 'DAS0500'.
        "V5J: Screen 0600 currently has a dynpro generation error in SE51.
        "Use the existing no-dump SALV dashboard until Screen 0600 is corrected/activated.
        PERFORM z16_open_result_dash_curr.
    ENDCASE.
  ENDMETHOD.
ENDCLASS.

*&---------------------------------------------------------------------*
*& Legacy F01 kept for local class/event implementations only.
*& Business FORM routines were moved to ZBDC_MPE_M*_BUP includes.
*&---------------------------------------------------------------------*
