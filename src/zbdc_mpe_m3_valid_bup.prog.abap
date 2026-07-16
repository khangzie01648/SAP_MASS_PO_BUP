*&---------------------------------------------------------------------*
*& Include          ZBDC_MPE_M3_VALID_BUP
*& Purpose          M3 Processing - validation/rules/system field protection
*& Source split     FIX16 V5BR - logic moved from F01
*&---------------------------------------------------------------------*

*>>> FORM VALIDATE_0200_CFG - moved from Z_BDC_MASS_PO_ENTRY_F01_BUP

FORM VALIDATE_0200_CFG CHANGING CV_OK TYPE C.
  DATA: LV_PORT_TXT  TYPE STRING,
        LV_BATCH_TXT TYPE STRING,
        LV_PORT_NUM  TYPE I,
        LV_BATCH_NUM TYPE I,
        LV_HAS_HOST  TYPE C LENGTH 1,
        LV_HAS_PORT  TYPE C LENGTH 1.

  CV_OK = 'X'.

  "BDC engine parameters are always validatable and saveable, regardless of
  "which inbound source the user later chooses in 0300.
  LV_BATCH_TXT = TXTP_BATCH_SIZE.
  CONDENSE LV_BATCH_TXT NO-GAPS.
  IF LV_BATCH_TXT IS INITIAL.
    LV_BATCH_TXT = '100'.
    TXTP_BATCH_SIZE = LV_BATCH_TXT.
  ENDIF.

  IF LV_BATCH_TXT CN '0123456789'.
    CV_OK = SPACE.
    MESSAGE 'Batch size must be numeric.' TYPE 'S' DISPLAY LIKE 'E'.
    RETURN.
  ENDIF.

  LV_BATCH_NUM = LV_BATCH_TXT.
  IF LV_BATCH_NUM LE 0.
    CV_OK = SPACE.
    MESSAGE 'Batch size must be greater than 0.' TYPE 'S' DISPLAY LIKE 'E'.
    RETURN.
  ENDIF.
  TXTP_BATCH_SIZE = LV_BATCH_TXT.

  IF RB_MODE_N IS INITIAL AND RB_MODE_E IS INITIAL AND RB_MODE_A IS INITIAL.
    RB_MODE_A = 'X'.
  ENDIF.

  IF RB_UPD_A IS INITIAL AND RB_UPD_S IS INITIAL.
    RB_UPD_S = 'X'.
  ENDIF.

  "SFTP is optional on Save. Both fields blank means: user is not configuring
  "SFTP now. If either field is entered, require a complete valid endpoint.
  IF TXTP_SFTP_HOST IS NOT INITIAL.
    LV_HAS_HOST = 'X'.
  ENDIF.
  IF TXTP_SFTP_PORT IS NOT INITIAL.
    LV_HAS_PORT = 'X'.
  ENDIF.

  IF LV_HAS_HOST IS INITIAL AND LV_HAS_PORT IS INITIAL.
    RETURN.
  ENDIF.

  IF LV_HAS_HOST IS INITIAL.
    CV_OK = SPACE.
    MESSAGE 'Enter SFTP Host, or clear Port to save BDC settings only.'
      TYPE 'S' DISPLAY LIKE 'E'.
    RETURN.
  ENDIF.

  IF LV_HAS_PORT IS INITIAL.
    CV_OK = SPACE.
    MESSAGE 'Enter SFTP Port, or clear Host to save BDC settings only.'
      TYPE 'S' DISPLAY LIKE 'E'.
    RETURN.
  ENDIF.

  LV_PORT_TXT = TXTP_SFTP_PORT.
  CONDENSE LV_PORT_TXT NO-GAPS.
  IF LV_PORT_TXT CN '0123456789'.
    CV_OK = SPACE.
    MESSAGE 'SFTP Port must be numeric.' TYPE 'S' DISPLAY LIKE 'E'.
    RETURN.
  ENDIF.

  LV_PORT_NUM = LV_PORT_TXT.
  IF LV_PORT_NUM LE 0 OR LV_PORT_NUM GT 65535.
    CV_OK = SPACE.
    MESSAGE 'SFTP Port must be between 1 and 65535.' TYPE 'S' DISPLAY LIKE 'E'.
    RETURN.
  ENDIF.
  TXTP_SFTP_PORT = LV_PORT_TXT.
ENDFORM.
*<<< END FORM VALIDATE_0200_CFG

*>>> FORM VALIDATE_0200_SFTP_TEST - moved from Z_BDC_MASS_PO_ENTRY_F01_BUP

FORM VALIDATE_0200_SFTP_TEST CHANGING CV_OK TYPE C.
  DATA: LV_PORT_TXT TYPE STRING,
        LV_PORT_NUM TYPE I.

  CV_OK = 'X'.

  IF TXTP_SFTP_HOST IS INITIAL.
    CV_OK = SPACE.
    MESSAGE 'Host is required only when testing the SFTP connection.'
      TYPE 'S' DISPLAY LIKE 'E'.
    RETURN.
  ENDIF.

  LV_PORT_TXT = TXTP_SFTP_PORT.
  CONDENSE LV_PORT_TXT NO-GAPS.
  IF LV_PORT_TXT IS INITIAL.
    CV_OK = SPACE.
    MESSAGE 'Port is required only when testing the SFTP connection.'
      TYPE 'S' DISPLAY LIKE 'E'.
    RETURN.
  ENDIF.

  IF LV_PORT_TXT CN '0123456789'.
    CV_OK = SPACE.
    MESSAGE 'SFTP Port must be numeric.' TYPE 'S' DISPLAY LIKE 'E'.
    RETURN.
  ENDIF.

  LV_PORT_NUM = LV_PORT_TXT.
  IF LV_PORT_NUM LE 0 OR LV_PORT_NUM GT 65535.
    CV_OK = SPACE.
    MESSAGE 'SFTP Port must be between 1 and 65535.' TYPE 'S' DISPLAY LIKE 'E'.
    RETURN.
  ENDIF.

  TXTP_SFTP_PORT = LV_PORT_TXT.
ENDFORM.
*<<< END FORM VALIDATE_0200_SFTP_TEST

*>>> FORM z18_validate_sm35_bdc - moved from Z_BDC_MASS_PO_ENTRY_F01_BUP
FORM z18_validate_sm35_bdc
  USING    pv_tcode TYPE sy-tcode
  CHANGING cv_ok    TYPE abap_bool
           cv_msg   TYPE string.

  DATA: ls_bdc           TYPE bdcdata,
        lv_screen_count  TYPE i,
        lv_okcode_count  TYPE i,
        lv_bad_screen    TYPE abap_bool.

  CLEAR: cv_ok, cv_msg.

  "A Batch Input session needs valid dynpro rows and at least one real user
  "action. BDC_SUBSCR and BDC_CURSOR are technical helpers generated only by
  "some SHDB recordings; their absence is NOT a valid reason to reject an
  "otherwise executable ME21N/MIGO script.
  LOOP AT bdcdata INTO ls_bdc.
    IF ls_bdc-dynbegin = 'X'.
      lv_screen_count = lv_screen_count + 1.
      IF ls_bdc-program IS INITIAL OR ls_bdc-dynpro IS INITIAL.
        lv_bad_screen = abap_true.
      ENDIF.
    ELSEIF ls_bdc-fnam = 'BDC_OKCODE' AND ls_bdc-fval IS NOT INITIAL.
      lv_okcode_count = lv_okcode_count + 1.
    ENDIF.
  ENDLOOP.

  IF lv_screen_count = 0.
    cv_msg = |SM35 preflight failed: no dynpro was generated for { pv_tcode }. Check the SHDB recording and mapping profile.|.
    RETURN.
  ENDIF.

  IF lv_bad_screen = abap_true.
    cv_msg = |SM35 preflight failed: the { pv_tcode } script contains a dynpro row without program/screen number.|.
    RETURN.
  ENDIF.

  IF lv_okcode_count = 0.
    cv_msg = |SM35 preflight failed: the { pv_tcode } script contains no BDC_OKCODE action. Re-record at least Enter/Save in SHDB.|.
    RETURN.
  ENDIF.

  IF pv_tcode = 'ME21N'.
    DATA lv_has_me21n_item TYPE abap_bool.
    PERFORM z26_bdc_has_me21n_item CHANGING lv_has_me21n_item.
    IF lv_has_me21n_item <> abap_true.
      cv_msg = 'ME21N preflight failed: generated BDCDATA has no item-overview fields, so SAP would raise Document contains no items.'.
      RETURN.
    ENDIF.
  ENDIF.

  cv_ok = abap_true.
ENDFORM.

*&---------------------------------------------------------------------*
*& V5AL - Build and validate one representative group before SM35 opens
*& Prevents empty 0-transaction sessions when the script/mapping is invalid.
*&---------------------------------------------------------------------*
*<<< END FORM z18_validate_sm35_bdc

*>>> FORM z20_preflight_sm35_group - moved from Z_BDC_MASS_PO_ENTRY_F01_BUP
FORM z20_preflight_sm35_group
  USING    pt_group  TYPE ty_t_staging_alv
           pt_s_pre  TYPE ty_t_script
           pt_s_item TYPE ty_t_script
           pt_s_post TYPE ty_t_script
           pt_map    TYPE ty_t_map
           pv_tcode  TYPE sy-tcode
  CHANGING cv_ok     TYPE abap_bool
           cv_msg    TYPE string.

  DATA: ls_first  TYPE ty_staging_alv,
        ls_item   TYPE ty_staging_alv,
        ls_scr    TYPE zbdc_sct_def_bup,
        lv_idx    TYPE n LENGTH 2,
        lv_itemno TYPE i.

  CLEAR: cv_ok, cv_msg.
  READ TABLE pt_group INTO ls_first INDEX 1.
  IF sy-subrc <> 0.
    cv_msg = 'SM35 preflight failed: representative document group is empty.'.
    RETURN.
  ENDIF.

  REFRESH bdcdata.

  LOOP AT pt_s_pre INTO ls_scr.
    PERFORM append_script_step USING ls_scr ls_first pt_map '01'.
  ENDLOOP.

  CLEAR lv_itemno.
  LOOP AT pt_group INTO ls_item.
    lv_itemno = lv_itemno + 1.
    lv_idx = lv_itemno.
    LOOP AT pt_s_item INTO ls_scr.
      PERFORM append_script_step USING ls_scr ls_item pt_map lv_idx.
    ENDLOOP.
  ENDLOOP.

  LOOP AT pt_s_post INTO ls_scr.
    PERFORM append_script_step USING ls_scr ls_first pt_map '01'.
  ENDLOOP.

  DATA lv_rebuilt_me21n TYPE abap_bool.
  DATA lv_rebuild_msg   TYPE string.
  PERFORM z26_repair_me21n_bdc
    USING    pv_tcode pt_group pt_map
    CHANGING lv_rebuilt_me21n lv_rebuild_msg.

  IF bdcdata[] IS INITIAL.
    cv_msg = |SM35 preflight failed: script/mapping generated no BDCDATA for group { ls_first-record_key }.|.
    RETURN.
  ENDIF.

  PERFORM z18_validate_sm35_bdc
    USING    pv_tcode
    CHANGING cv_ok cv_msg.
ENDFORM.
*<<< END FORM z20_preflight_sm35_group

*>>> FORM VALIDATE_EXEC_COCKPIT - moved from Z_BDC_MASS_PO_ENTRY_F01_BUP

FORM VALIDATE_EXEC_COCKPIT.
  DATA LV_MSG TYPE STRING.

  IF GO_STAGING_GRID IS BOUND AND GV_0400_VIEW = GC_VIEW_DETAIL.
    GO_STAGING_GRID->CHECK_CHANGED_DATA( ).
  ENDIF.

  PERFORM PREPARE_ALV_0400.
  PERFORM BUILD_EXEC_COCKPIT.
  PERFORM UPDATE_0400_COUNTERS.
  PERFORM REFRESH_0400_GRID.

  "Lifecycle V4: Validate is a real lifecycle step, so update 0100 now.
  PERFORM upd_all_rt_sess_sum.

  IF GV_EXEC_ERR_GRP > 0.
    LV_MSG = |Validation found { GV_EXEC_ERR_GRP } error group(s). Open Message/Fix Hint or Edit Details.|.
    MESSAGE LV_MSG TYPE 'W'.
  ELSEIF GV_EXEC_WARN_GRP > 0.
    LV_MSG = |Validation finished with { GV_EXEC_WARN_GRP } warning group(s). Review before execute.|.
    MESSAGE LV_MSG TYPE 'S'.
  ELSE.
    LV_MSG = |All { GV_EXEC_READY_GRP } ready group(s) can be executed.|.
    MESSAGE LV_MSG TYPE 'S'.
  ENDIF.
ENDFORM.
*<<< END FORM VALIDATE_EXEC_COCKPIT

*>>> FORM z16_validate_curr_corr - moved from Z_BDC_MASS_PO_ENTRY_F01_BUP

FORM z16_validate_curr_corr.
  PERFORM update_popup_detail.
  PERFORM prepare_alv_0400.
  PERFORM build_exec_cockpit.
  MESSAGE 'Correction saved and validated again. Use RSUB to retry or go to 0560.' TYPE 'S'.
ENDFORM.
*<<< END FORM z16_validate_curr_corr

*>>> FORM z16_0560_validate_again - moved from Z_BDC_MASS_PO_ENTRY_F01_BUP

FORM z16_0560_validate_again.
  PERFORM prepare_alv_0400.
  PERFORM build_exec_cockpit.
  PERFORM z16_write_structured_errors.
  MESSAGE 'Validate again finished. ERROR rows updated; retryable groups can be sent back to 0500.' TYPE 'S'.
ENDFORM.
*<<< END FORM z16_0560_validate_again

*>>> FORM z16_read_rules - moved from Z_BDC_MASS_PO_ENTRY_F01_BUP

FORM z16_read_rules CHANGING ct_rule TYPE ty_t_z16_rule.
  DATA: lv_exists TYPE abap_bool,
        lr_tab    TYPE REF TO data,
        lv_text   TYPE string,
        lv_tcode  TYPE string,
        lv_active TYPE string,
        ls_rule   TYPE ty_z16_rule.
  FIELD-SYMBOLS: <lt_any> TYPE STANDARD TABLE,
                 <ls_any> TYPE any.

  REFRESH ct_rule.
  PERFORM z16_table_exists USING gc_z16_tab_vrule CHANGING lv_exists.
  IF lv_exists IS INITIAL.
    RETURN.
  ENDIF.

  TRY.
      CREATE DATA lr_tab TYPE STANDARD TABLE OF (gc_z16_tab_vrule).
      ASSIGN lr_tab->* TO <lt_any>.
      SELECT * FROM (gc_z16_tab_vrule) INTO TABLE @<lt_any>.
    CATCH cx_root.
      RETURN.
  ENDTRY.

  LOOP AT <lt_any> ASSIGNING <ls_any>.
    CLEAR: ls_rule, lv_text, lv_tcode, lv_active.
    PERFORM z16_get_comp_str USING <ls_any> 'IS_ACTIVE' CHANGING lv_active.
    IF lv_active IS INITIAL. PERFORM z16_get_comp_str USING <ls_any> 'ACTIVE' CHANGING lv_active. ENDIF.
    TRANSLATE lv_active TO UPPER CASE.
    IF lv_active IS NOT INITIAL AND lv_active <> 'X' AND lv_active <> '1' AND lv_active <> 'Y'.
      CONTINUE.
    ENDIF.
    ls_rule-is_active = 'X'.

    PERFORM z16_get_comp_str USING <ls_any> 'RULE_ID' CHANGING lv_text. ls_rule-rule_id = lv_text.
    CLEAR lv_text. PERFORM z16_get_comp_str USING <ls_any> 'TCODE' CHANGING lv_tcode. TRANSLATE lv_tcode TO UPPER CASE. ls_rule-tcode = lv_tcode.
    IF ls_rule-tcode IS NOT INITIAL AND ls_rule-tcode <> p_transaction.
      CONTINUE.
    ENDIF.

    CLEAR lv_text. PERFORM z16_get_comp_str USING <ls_any> 'LAYER' CHANGING lv_text. TRANSLATE lv_text TO UPPER CASE. ls_rule-layer = lv_text.
    CLEAR lv_text. PERFORM z16_get_comp_str USING <ls_any> 'FIELDNAME' CHANGING lv_text.
    IF lv_text IS INITIAL. PERFORM z16_get_comp_str USING <ls_any> 'FIELD_NAME' CHANGING lv_text. ENDIF.
    IF lv_text IS INITIAL. PERFORM z16_get_comp_str USING <ls_any> 'STAGING_FIELD' CHANGING lv_text. ENDIF.
    TRANSLATE lv_text TO UPPER CASE. ls_rule-fieldname = lv_text.

    CLEAR lv_text. PERFORM z16_get_comp_str USING <ls_any> 'RULE_TYPE' CHANGING lv_text. TRANSLATE lv_text TO UPPER CASE. ls_rule-rule_type = lv_text.
    CLEAR lv_text. PERFORM z16_get_comp_str USING <ls_any> 'SEVERITY' CHANGING lv_text. TRANSLATE lv_text TO UPPER CASE. ls_rule-severity = lv_text.
    CLEAR lv_text. PERFORM z16_get_comp_str USING <ls_any> 'CHECK_TABLE' CHANGING lv_text. TRANSLATE lv_text TO UPPER CASE. ls_rule-check_table = lv_text.
    CLEAR lv_text. PERFORM z16_get_comp_str USING <ls_any> 'CHECK_FIELD1' CHANGING lv_text. TRANSLATE lv_text TO UPPER CASE. ls_rule-check_field1 = lv_text.
    CLEAR lv_text. PERFORM z16_get_comp_str USING <ls_any> 'PARAM1' CHANGING lv_text. ls_rule-param1 = lv_text.
    CLEAR lv_text. PERFORM z16_get_comp_str USING <ls_any> 'PARAM2' CHANGING lv_text. ls_rule-param2 = lv_text.
    CLEAR lv_text. PERFORM z16_get_comp_str USING <ls_any> 'PARAM3' CHANGING lv_text. ls_rule-param3 = lv_text.
    CLEAR lv_text. PERFORM z16_get_comp_str USING <ls_any> 'MESSAGE_TEXT' CHANGING lv_text. ls_rule-message_text = lv_text.
    CLEAR lv_text. PERFORM z16_get_comp_str USING <ls_any> 'HINT_TEXT' CHANGING lv_text. ls_rule-hint_text = lv_text.
    CLEAR lv_text. PERFORM z16_get_comp_str USING <ls_any> 'SORT_ORDER' CHANGING lv_text. IF lv_text IS NOT INITIAL. ls_rule-sort_order = lv_text. ENDIF.

    IF ls_rule-fieldname IS NOT INITIAL AND ls_rule-rule_type IS NOT INITIAL.
      APPEND ls_rule TO ct_rule.
    ENDIF.
  ENDLOOP.

  SORT ct_rule BY sort_order rule_id.
ENDFORM.
*<<< END FORM z16_read_rules

*>>> FORM z16_check_dynamic_exists - moved from Z_BDC_MASS_PO_ENTRY_F01_BUP

FORM z16_check_dynamic_exists USING iv_table TYPE tabname
                                    iv_field TYPE fieldname
                                    iv_value TYPE string
                              CHANGING cv_exists TYPE abap_bool.
  DATA: lv_where TYPE string,
        lv_value TYPE string,
        lv_count TYPE i.
  CLEAR cv_exists.
  IF iv_table IS INITIAL OR iv_field IS INITIAL OR iv_value IS INITIAL.
    RETURN.
  ENDIF.

  lv_value = iv_value.
  REPLACE ALL OCCURRENCES OF '''' IN lv_value WITH ''''''.
  lv_where = |{ iv_field } = '{ lv_value }'|.

  TRY.
      SELECT COUNT( * ) FROM (iv_table) INTO @lv_count WHERE (lv_where).
      IF lv_count > 0.
        cv_exists = abap_true.
      ENDIF.
    CATCH cx_root.
      CLEAR cv_exists.
  ENDTRY.
ENDFORM.
*<<< END FORM z16_check_dynamic_exists

*>>> FORM z16_apply_dynamic_rules - moved from Z_BDC_MASS_PO_ENTRY_F01_BUP

FORM z16_apply_dynamic_rules.
  DATA: lt_rule TYPE ty_t_z16_rule,
        ls_rule TYPE ty_z16_rule,
        lv_val  TYPE string,
        lv_msg  TYPE string,
        lv_ok   TYPE abap_bool.
  FIELD-SYMBOLS: <ls_alv> TYPE ty_staging_alv,
                 <lv_any> TYPE any.

  PERFORM z16_read_rules CHANGING lt_rule.
  IF lt_rule IS INITIAL.
    RETURN.
  ENDIF.

  LOOP AT gt_staging_alv ASSIGNING <ls_alv>.
    IF <ls_alv>-status = gc_st_success.
      CONTINUE.
    ENDIF.

    LOOP AT lt_rule INTO ls_rule.
      IF ls_rule-tcode IS NOT INITIAL AND ls_rule-tcode <> <ls_alv>-tcode.
        CONTINUE.
      ENDIF.
      ASSIGN COMPONENT ls_rule-fieldname OF STRUCTURE <ls_alv> TO <lv_any>.
      IF sy-subrc <> 0.
        CONTINUE.
      ENDIF.

      lv_val = |{ <lv_any> }|.
      CONDENSE lv_val.
      CLEAR lv_msg.
      IF ls_rule-message_text IS NOT INITIAL.
        lv_msg = ls_rule-message_text.
      ELSE.
        lv_msg = |Rule { ls_rule-rule_id } failed for { ls_rule-fieldname }|.
      ENDIF.

      IF ls_rule-rule_type = 'MANDATORY' OR ls_rule-rule_type = 'REQUIRED' OR ls_rule-rule_type = 'NOT_INITIAL'.
        IF lv_val IS INITIAL.
          PERFORM z16_mark_row_error USING ls_rule-fieldname lv_msg CHANGING <ls_alv>.
        ENDIF.
      ELSEIF ls_rule-rule_type = 'VALUE_EXISTS' OR ls_rule-rule_type = 'EXISTS' OR ls_rule-rule_type = 'CHECK_TABLE'.
        IF lv_val IS NOT INITIAL AND ls_rule-check_table IS NOT INITIAL AND ls_rule-check_field1 IS NOT INITIAL.
          PERFORM z16_check_dynamic_exists USING ls_rule-check_table ls_rule-check_field1 lv_val CHANGING lv_ok.
          IF lv_ok IS INITIAL.
            PERFORM z16_mark_row_error USING ls_rule-fieldname lv_msg CHANGING <ls_alv>.
          ENDIF.
        ENDIF.
      ENDIF.
    ENDLOOP.
  ENDLOOP.
ENDFORM.
*<<< END FORM z16_apply_dynamic_rules

*>>> FORM z16_log_one_change - moved from Z_BDC_MASS_PO_ENTRY_F01_BUP

FORM z16_log_one_change USING iv_session TYPE any
                              iv_row     TYPE any
                              iv_tcode   TYPE any
                              iv_field   TYPE any
                              iv_old     TYPE any
                              iv_new     TYPE any
                              iv_action  TYPE any.
  DATA: lv_exists TYPE abap_bool,
        lr_line   TYPE REF TO data,
        lv_tab    TYPE tabname,
        lv_ts     TYPE timestampl,
        lv_id     TYPE string.
  FIELD-SYMBOLS <ls_any> TYPE any.

  IF iv_old = iv_new.
    RETURN.
  ENDIF.

  PERFORM z16_table_exists USING gc_z16_tab_chg CHANGING lv_exists.
  IF lv_exists IS INITIAL.
    RETURN.
  ENDIF.

  TRY.
      CREATE DATA lr_line TYPE (gc_z16_tab_chg).
      ASSIGN lr_line->* TO <ls_any>.
    CATCH cx_root.
      RETURN.
  ENDTRY.

  GET TIME STAMP FIELD lv_ts.
  lv_id = |CHG_{ sy-datum }_{ sy-uzeit }_{ iv_row }_{ iv_field }|.

  PERFORM z16_set_comp_str USING 'CHANGE_ID'     lv_id      CHANGING <ls_any>.
  PERFORM z16_set_comp_str USING 'SESSION_ID'    iv_session CHANGING <ls_any>.
  PERFORM z16_set_comp_str USING 'ROW_INDEX'     iv_row     CHANGING <ls_any>.
  PERFORM z16_set_comp_str USING 'TCODE'         iv_tcode   CHANGING <ls_any>.
  PERFORM z16_set_comp_str USING 'FIELD_NAME'    iv_field   CHANGING <ls_any>.
  PERFORM z16_set_comp_str USING 'OLD_VALUE'     iv_old     CHANGING <ls_any>.
  PERFORM z16_set_comp_str USING 'NEW_VALUE'     iv_new     CHANGING <ls_any>.
  PERFORM z16_set_comp_str USING 'CHANGED_BY'    sy-uname   CHANGING <ls_any>.
  PERFORM z16_set_comp_str USING 'CHANGED_AT'    lv_ts      CHANGING <ls_any>.
  PERFORM z16_set_comp_str USING 'CHANGE_ACTION' iv_action  CHANGING <ls_any>.

  lv_tab = gc_z16_tab_chg.
  TRY.
      MODIFY (lv_tab) FROM <ls_any>.
    CATCH cx_root.
  ENDTRY.
ENDFORM.
*<<< END FORM z16_log_one_change

*>>> FORM z16_log_row_changes - moved from Z_BDC_MASS_PO_ENTRY_F01_BUP

FORM z16_log_row_changes USING is_old TYPE ty_staging_alv
                               is_new TYPE ty_staging_alv
                               iv_action TYPE any.
  DATA: lv_idx   TYPE n LENGTH 2,
        lv_field TYPE char10,
        lv_old   TYPE string,
        lv_new   TYPE string.
  FIELD-SYMBOLS: <lv_old_any> TYPE any,
                 <lv_new_any> TYPE any.

  DO 25 TIMES.
    lv_idx = sy-index.
    CONCATENATE 'FIELD' lv_idx INTO lv_field.
    ASSIGN COMPONENT lv_field OF STRUCTURE is_old TO <lv_old_any>.
    ASSIGN COMPONENT lv_field OF STRUCTURE is_new TO <lv_new_any>.
    IF sy-subrc = 0.
      lv_old = |{ <lv_old_any> }|.
      lv_new = |{ <lv_new_any> }|.
      IF lv_old <> lv_new.
        PERFORM z16_log_one_change USING is_new-session_id is_new-row_index is_new-tcode lv_field lv_old lv_new iv_action.
      ENDIF.
    ENDIF.
  ENDDO.
ENDFORM.
*<<< END FORM z16_log_row_changes

*>>> FORM z16_protect_system_fields - moved from Z_BDC_MASS_PO_ENTRY_F01_BUP

FORM z16_protect_system_fields CHANGING ct_fcat TYPE lvc_t_fcat.
  LOOP AT ct_fcat ASSIGNING FIELD-SYMBOL(<ls_fcat>).
    CASE <ls_fcat>-fieldname.
      WHEN 'SESSION_ID' OR 'ROW_INDEX' OR 'STATUS' OR 'CREATED_BY' OR 'CREATED_AT'
        OR 'UPDATED_BY' OR 'UPDATED_AT' OR 'RECORD_KEY' OR 'TCODE'
        OR 'ERROR_MSG' OR 'LAST_ERROR' OR 'ATTEMPT_NO' OR 'SELECTED'.
        <ls_fcat>-edit = space.
      WHEN 'MANDT'.
        <ls_fcat>-no_out = 'X'.
        <ls_fcat>-edit = space.
    ENDCASE.
  ENDLOOP.
ENDFORM.
*<<< END FORM z16_protect_system_fields

*>>> FORM z16_confirm_execute - moved from Z_BDC_MASS_PO_ENTRY_F01_BUP

FORM z16_confirm_execute USING iv_scope TYPE csequence CHANGING cv_ok TYPE abap_bool.
  DATA: lv_answer   TYPE c,
        lv_question TYPE c LENGTH 70.
  CLEAR cv_ok.
  lv_question = |Run BDC for { iv_scope }?|.
  CALL FUNCTION 'POPUP_TO_CONFIRM'
    EXPORTING
      titlebar              = 'Confirm BDC Execution'
      text_question         = lv_question
      text_button_1         = 'Run'
      icon_button_1         = 'ICON_EXECUTE_OBJECT'
      text_button_2         = 'Cancel'
      icon_button_2         = 'ICON_CANCEL'
      display_cancel_button = space
    IMPORTING
      answer                = lv_answer
    EXCEPTIONS
      OTHERS                = 1.
  IF sy-subrc = 0 AND lv_answer = '1'.
    cv_ok = abap_true.
  ENDIF.
ENDFORM.
*<<< END FORM z16_confirm_execute
