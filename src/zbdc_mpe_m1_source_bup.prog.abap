*&---------------------------------------------------------------------*
*& Include          ZBDC_MPE_M1_SOURCE_BUP
*& Purpose          M1 Inbound Channels - Local, SFTP, Gmail, GDrive, REST
*& Source split     FIX16 V5BR - logic moved from F01
*&---------------------------------------------------------------------*

*>>> FORM SAVE_0200_CONN_LOG - moved from Z_BDC_MASS_PO_ENTRY_F01_BUP

FORM SAVE_0200_CONN_LOG
  USING IV_STATUS TYPE CHAR20
        IV_MESSAGE TYPE CHAR255.
  DATA: LT_CONFIG TYPE STANDARD TABLE OF ZBDC_CONFIG_BUP,
        LS_CONFIG TYPE ZBDC_CONFIG_BUP,
        LV_TS     TYPE TZNTSTMPS,
        LV_AT     TYPE CHAR30,
        LV_MSG    TYPE CHAR255.

  LV_MSG = IV_MESSAGE.
  GET TIME STAMP FIELD LV_TS.
  LV_AT = LV_TS.

  REFRESH LT_CONFIG.

  CLEAR LS_CONFIG.
  LS_CONFIG-CONFIG_KEY   = 'CONN_STATUS'.
  LS_CONFIG-CONFIG_VALUE = IV_STATUS.
  APPEND LS_CONFIG TO LT_CONFIG.

  CLEAR LS_CONFIG.
  LS_CONFIG-CONFIG_KEY   = 'CONN_AT'.
  LS_CONFIG-CONFIG_VALUE = LV_AT.
  APPEND LS_CONFIG TO LT_CONFIG.

  CLEAR LS_CONFIG.
  LS_CONFIG-CONFIG_KEY   = 'CONN_BY'.
  LS_CONFIG-CONFIG_VALUE = SY-UNAME.
  APPEND LS_CONFIG TO LT_CONFIG.

  CLEAR LS_CONFIG.
  LS_CONFIG-CONFIG_KEY   = 'CONN_MSG'.
  LS_CONFIG-CONFIG_VALUE = LV_MSG.
  APPEND LS_CONFIG TO LT_CONFIG.

  MODIFY ZBDC_CONFIG_BUP FROM TABLE LT_CONFIG.
  COMMIT WORK AND WAIT.

  GV_0200_LAST_STAT = IV_STATUS.
  GV_0200_LAST_MSG  = LV_MSG.
  GV_0200_LAST_AT   = LV_AT.
ENDFORM.
*<<< END FORM SAVE_0200_CONN_LOG

*>>> FORM SAVE_SOURCE_CONFIG - moved from Z_BDC_MASS_PO_ENTRY_F01_BUP

FORM SAVE_SOURCE_CONFIG.
  DATA: LT_CONFIG TYPE STANDARD TABLE OF ZBDC_CONFIG_BUP,
        LS_CONFIG TYPE ZBDC_CONFIG_BUP,
        LV_MODE   TYPE CHAR10,
        LV_UPDATE TYPE CHAR10,
        LV_BSIZE  TYPE CHAR10,
        LV_RETRY  TYPE CHAR10,
        LV_TIMEOUT TYPE CHAR20,
        LV_OK     TYPE C LENGTH 1.

  CLEAR GV_0200_SAVED_OK.
  PERFORM VALIDATE_0200_CFG CHANGING LV_OK.
  IF LV_OK IS INITIAL.
    RETURN.
  ENDIF.

  "0200 owns BDC engine settings and an optional SFTP endpoint.
  "Saving here must never change the active inbound source. The real source
  "is selected during ingestion and is logged per session in 0300.

  IF     RB_MODE_N = 'X'.
    LV_MODE = 'N'.
  ELSEIF RB_MODE_E = 'X'.
    LV_MODE = 'E'.
  ELSEIF RB_MODE_A = 'X'.
    LV_MODE = 'A'.
  ELSE.
    LV_MODE = 'N'.
  ENDIF.

  IF     RB_UPD_A = 'X'.
    LV_UPDATE = 'A'.
  ELSEIF RB_UPD_S = 'X'.
    LV_UPDATE = 'S'.
  ELSE.
    LV_UPDATE = 'A'.
  ENDIF.

  WRITE TXTP_BATCH_SIZE TO LV_BSIZE LEFT-JUSTIFIED.
  WRITE TXTP_TIMEOUT    TO LV_TIMEOUT LEFT-JUSTIFIED.
  LV_RETRY = CHKP_RETRY.

  DEFINE ADD_CFG.
    CLEAR LS_CONFIG.
    LS_CONFIG-CONFIG_KEY   = &1.
    LS_CONFIG-CONFIG_VALUE = &2.
    APPEND LS_CONFIG TO LT_CONFIG.
  END-OF-DEFINITION.

  "Do not persist SOURCE_TYPE here. A user may save BDC parameters while
  "using Local, Google Drive, REST/Gmail, or SFTP ingestion.
  "0200 no longer persists TRANSACTION/FORMAT.
  "TCode comes from uploaded staging data; CSV parsing is handled in 0300.
  ADD_CFG 'WEBHOOK_URL'    TXTP_WEBHOOK_URL.
  ADD_CFG 'AUTH_TYPE'      P_AUTH_TYPE.
  ADD_CFG 'API_KEY'        TXTP_API_KEY.
  ADD_CFG 'TIMEOUT'        LV_TIMEOUT.
  ADD_CFG 'RETRY_ENABLED'  LV_RETRY.
  ADD_CFG 'SFTP_HOST'      TXTP_SFTP_HOST.
  ADD_CFG 'SFTP_PORT'      TXTP_SFTP_PORT.
  ADD_CFG 'SFTP_USER'      TXTP_USERNAME.
  ADD_CFG 'SFTP_PASSWORD'  TXTP_PASSWORD. "Demo only; production should use SSF/Secure Store.
  "0200 does not own Google Drive URL or last file path. Do not overwrite them here.
  ADD_CFG 'BDC_MODE'       LV_MODE.       "CALL TRANSACTION display mode N/E/A
  ADD_CFG 'BDC_UPDATE'     LV_UPDATE.
  ADD_CFG 'BDC_EXEC_MODE'  P_BDC_MODE.    "CALL_TRANSACTION / BATCH_INPUT
  ADD_CFG 'BATCH_SIZE'     LV_BSIZE.

  MODIFY ZBDC_CONFIG_BUP FROM TABLE LT_CONFIG.
  IF SY-SUBRC = 0.
    COMMIT WORK AND WAIT.
    GV_0200_SAVED_OK = 'X'.
    PERFORM BUILD_0200_CFG_SIG CHANGING GV_0200_SAVED_SIG.
    IF TXTP_SFTP_HOST IS INITIAL AND TXTP_SFTP_PORT IS INITIAL.
      MESSAGE 'BDC configuration saved. SFTP endpoint is optional and remains blank.' TYPE 'S'.
    ELSE.
      MESSAGE 'BDC configuration and optional SFTP endpoint saved.' TYPE 'S'.
    ENDIF.
  ELSE.
    ROLLBACK WORK.
    MESSAGE 'Error saving configuration.' TYPE 'E'.
  ENDIF.
ENDFORM.
*<<< END FORM SAVE_SOURCE_CONFIG

*>>> FORM TEST_INBOUND_CONNECTION - moved from Z_BDC_MASS_PO_ENTRY_F01_BUP


FORM TEST_INBOUND_CONNECTION.
  DATA: LV_URL      TYPE STRING,
        LV_MSG      TYPE CHAR255,
        LV_PARAMS   TYPE SXPGCOLIST-PARAMETERS,
        LV_STATUS   TYPE C LENGTH 1,
        LV_EXITCODE TYPE I,
        LT_PROTO    TYPE STANDARD TABLE OF BTCXPM,
        LV_OK       TYPE C LENGTH 1.

  "The Test Connection button on screen 0200 tests only the optional SFTP
  "endpoint. It must not be required for saving or changing BDC parameters.
  PERFORM VALIDATE_0200_SFTP_TEST CHANGING LV_OK.
  IF LV_OK IS INITIAL.
    RETURN.
  ENDIF.

  LV_URL = |sftp://{ TXTP_SFTP_HOST }:{ TXTP_SFTP_PORT }/incoming/|.
  TRANSLATE LV_URL TO LOWER CASE.
  CONCATENATE '--insecure' '--connect-timeout 5' '--max-time 10'
              '-u sap_sftp:' '--key /usr/sap/S40/D00/work/sap_sftp_key'
              LV_URL '-o /usr/sap/S40/D00/work/testconn.txt'
         INTO LV_PARAMS SEPARATED BY SPACE.

  CALL FUNCTION 'SXPG_COMMAND_EXECUTE'
    EXPORTING
      COMMANDNAME           = 'ZBDC_SFTP_PULL'
      ADDITIONAL_PARAMETERS = LV_PARAMS
      OPERATINGSYSTEM       = 'Linux'
    IMPORTING
      STATUS                = LV_STATUS
      EXITCODE              = LV_EXITCODE
    TABLES
      EXEC_PROTOCOL         = LT_PROTO
    EXCEPTIONS
      NO_PERMISSION         = 1
      COMMAND_NOT_FOUND     = 2
      PARAMETERS_TOO_LONG   = 3
      SECURITY_RISK         = 4
      OTHERS                = 15.

  IF SY-SUBRC <> 0.
    LV_MSG = |SXPG error sy-subrc={ SY-SUBRC }. Check SM69 ZBDC_SFTP_PULL.|.
    PERFORM SAVE_0200_CONN_LOG USING 'FAILED' LV_MSG.
    MESSAGE LV_MSG TYPE 'E'.
    RETURN.
  ENDIF.

  CASE LV_EXITCODE.
    WHEN 0.
      LV_MSG = |SFTP endpoint OK: { TXTP_SFTP_HOST }:{ TXTP_SFTP_PORT }.|.
      PERFORM SAVE_0200_CONN_LOG USING 'OK' LV_MSG.
      MESSAGE LV_MSG TYPE 'S'.
    WHEN 67.
      LV_MSG = 'Auth failed (exit 67). Check SFTP key/credential.'.
      PERFORM SAVE_0200_CONN_LOG USING 'FAILED' LV_MSG.
      MESSAGE LV_MSG TYPE 'W'.
    WHEN 60.
      LV_MSG = 'Host key not verified (exit 60).'.
      PERFORM SAVE_0200_CONN_LOG USING 'FAILED' LV_MSG.
      MESSAGE LV_MSG TYPE 'W'.
    WHEN 7.
      LV_MSG = 'Endpoint offline or refused connection (exit 7).'.
      PERFORM SAVE_0200_CONN_LOG USING 'FAILED' LV_MSG.
      MESSAGE LV_MSG TYPE 'W'.
    WHEN 28.
      LV_MSG = 'Connection timeout (exit 28).'.
      PERFORM SAVE_0200_CONN_LOG USING 'FAILED' LV_MSG.
      MESSAGE LV_MSG TYPE 'W'.
    WHEN 6.
      LV_MSG = 'Host cannot be resolved (exit 6).'.
      PERFORM SAVE_0200_CONN_LOG USING 'FAILED' LV_MSG.
      MESSAGE LV_MSG TYPE 'W'.
    WHEN OTHERS.
      LV_MSG = |Connection failed with exit code { LV_EXITCODE }.|.
      PERFORM SAVE_0200_CONN_LOG USING 'FAILED' LV_MSG.
      MESSAGE LV_MSG TYPE 'W'.
  ENDCASE.
ENDFORM.



*&---------------------------------------------------------------------*
*& V4R Mass Automation Batch Helpers - code only, no new SE11 fields
*&---------------------------------------------------------------------*
*<<< END FORM TEST_INBOUND_CONNECTION

*>>> FORM BROWSE_FILE - moved from Z_BDC_MASS_PO_ENTRY_F01_BUP


FORM BROWSE_FILE.
  DATA: lt_files   TYPE filetable,
        ls_file    TYPE file_table,
        lv_rc      TYPE i,
        lv_act     TYPE i,
        lv_size    TYPE i,
        lv_file_nm TYPE string,
        lv_size_kb TYPE p DECIMALS 1.

  "Local picker used after the user chooses LOCAL in the 4-channel Browse popup.
  "The screen Browse function may be BTN_BROWSE or FC_BROWSE.
  cl_gui_frontend_services=>file_open_dialog(
    EXPORTING
      window_title   = 'Select one local data file'
      file_filter    = 'Data (*.xlsx;*.csv;*.json;*.xml)|*.xlsx;*.csv;*.json;*.xml|All (*.*)|*.*'
      multiselection = space
    CHANGING
      file_table     = lt_files
      rc             = lv_rc
      user_action    = lv_act
    EXCEPTIONS
      OTHERS         = 1 ).

  IF sy-subrc <> 0
     OR lv_act <> cl_gui_frontend_services=>action_ok
     OR lv_rc <= 0.
    RETURN.
  ENDIF.

  READ TABLE lt_files INTO ls_file INDEX 1.
  IF sy-subrc <> 0 OR ls_file-filename IS INITIAL.
    RETURN.
  ENDIF.

  "Browse must only select a local file. It must not show old upload rows
  "and must not calculate final evidence size before the Upload action.
  "Clear FIRST, then set the selected path. This prevents old preview rows
  "from surviving on screen 0301 after the Browse PAI/PBO roundtrip.
  PERFORM z16_clear_0300_after_browse.
  txtp_file_path = ls_file-filename.
  txtp_file_size = '0 B'.
  PERFORM z16_set_row_count_fields USING 0.

  CALL METHOD cl_gui_cfw=>flush.
  MESSAGE 'Local file selected. Press Upload/Ingest to parse it.' TYPE 'S'.
ENDFORM.
*<<< END FORM BROWSE_FILE

*>>> FORM UPLOAD_AND_PARSE_EXCEL - moved from Z_BDC_MASS_PO_ENTRY_F01_BUP


FORM UPLOAD_AND_PARSE_EXCEL.
  IF TXTP_FILE_PATH IS INITIAL.
    MESSAGE 'Please choose a file or channel first.' TYPE 'E'. RETURN.
  ENDIF.

  IF TXTP_FILE_PATH CP 'GoogleDrive://*'.
    PERFORM DOWNLOAD_FROM_GDRIVE_FILE.
  ELSEIF TXTP_FILE_PATH CP 'REST_API://*'.
    PERFORM UPLOAD_FROM_REST.
  ELSEIF TXTP_FILE_PATH CP 'MAILBOX://*'.
    DATA: LV_MAIL_COUNT TYPE I.
    IF GT_STAGING IS INITIAL AND GV_CURRENT_BATCH_PREFIX IS NOT INITIAL.
      PERFORM Z16_LOAD_STAGING_BY_BATCH USING GV_CURRENT_BATCH_PREFIX CHANGING LV_MAIL_COUNT.
    ELSE.
      LV_MAIL_COUNT = LINES( GT_STAGING ).
    ENDIF.
    PERFORM Z16_SET_ROW_COUNT_FIELDS USING LV_MAIL_COUNT.
    MESSAGE |Email batch data is ready in staging ({ LV_MAIL_COUNT } row(s)).| TYPE 'S'.
  ELSEIF TXTP_FILE_PATH CP 'SFTP://*'.
    PERFORM LOAD_FROM_SFTP_SELECTED.
  ELSE.
    PERFORM UPLOAD_LOCAL_FILE.
  ENDIF.
ENDFORM.
*<<< END FORM UPLOAD_AND_PARSE_EXCEL

*>>> FORM UPLOAD_LOCAL_FILE - moved from Z_BDC_MASS_PO_ENTRY_F01_BUP

FORM UPLOAD_LOCAL_FILE.
  DATA: lt_files      TYPE STANDARD TABLE OF string,
        lv_file       TYPE string,
        lt_raw        TYPE string_table,
        lv_content    TYPE string,
        lv_unit       TYPE string,
        lv_index      TYPE i,
        lv_before     TYPE i,
        lv_after      TYPE i,
        lv_loaded     TYPE i,
        lv_ok_files   TYPE i,
        lv_bad_files  TYPE i,
        lv_session_id TYPE zbdc_staging_bup-session_id,
        lv_xstr       TYPE xstring,
        lv_xok        TYPE abap_bool,
        lv_size_bytes TYPE i,
        lv_size_text  TYPE char20,
        lv_file_str   TYPE string,
        ls_file_meta  TYPE ty_files_disp,
        lv_title      TYPE char80,
        lv_sheet      TYPE char40,
        lv_raw_line  TYPE string,
        lv_size_calc TYPE i,
        lv_line_len  TYPE i.

  IF txtp_file_path IS INITIAL.
    MESSAGE 'Please choose local file(s) first.' TYPE 'E'. RETURN.
  ENDIF.

  SPLIT txtp_file_path AT ';' INTO TABLE lt_files.
  DELETE lt_files WHERE table_line IS INITIAL.
  IF lt_files IS INITIAL.
    MESSAGE 'No local file selected.' TYPE 'E'. RETURN.
  ENDIF.

  REFRESH gt_staging.
  PERFORM z16_start_ingest_batch.
  CLEAR: lv_index, lv_loaded, lv_ok_files, lv_bad_files.

  LOOP AT lt_files INTO lv_file.
    CLEAR: lv_size_bytes, lv_size_text.
    lv_file_str = lv_file.
    cl_gui_frontend_services=>file_get_size(
      EXPORTING
        file_name = lv_file_str
      IMPORTING
        file_size = lv_size_bytes
      EXCEPTIONS
        OTHERS    = 1 ).
    IF sy-subrc = 0.
      PERFORM z23_format_file_size USING lv_size_bytes CHANGING lv_size_text.
    ELSE.
      lv_size_text = 'Unknown'.
    ENDIF.
    txtp_file_size = lv_size_text.

    IF lv_file CP '*.xlsx' OR lv_file CP '*.XLSX'.
      PERFORM z16_read_local_xstr USING lv_file CHANGING lv_xstr lv_xok.
      IF lv_xok = abap_true.
        PERFORM z16_ingest_xlsx_xstr USING lv_file 'LOCAL' lv_xstr
          CHANGING lv_index lv_loaded lv_ok_files lv_bad_files.
      ELSE.
        lv_bad_files = lv_bad_files + 1.
      ENDIF.
      CONTINUE.
    ENDIF.

    lv_index = lv_index + 1.
    PERFORM z16_make_batch_session USING lv_index CHANGING lv_session_id.
    gv_forced_session_id    = lv_session_id.
    gv_current_file_name    = lv_file.
    gv_current_sheet_name   = 'DATA'.
    gv_current_unit_src     = 'LOCAL'.

    REFRESH lt_raw.
    cl_gui_frontend_services=>gui_upload(
      EXPORTING filename = lv_file filetype = 'ASC' codepage = '4110'
      CHANGING  data_tab = lt_raw
      EXCEPTIONS OTHERS  = 1 ).
    IF sy-subrc <> 0.
      lv_bad_files = lv_bad_files + 1.
      CLEAR: gv_forced_session_id, gv_current_file_name, gv_current_sheet_name, gv_current_unit_src.
      CONTINUE.
    ENDIF.

    "Frontend FILE_GET_SIZE is not reliable in every SAP GUI release.
    "If Browse/Upload shows 0 B while rows are loaded, calculate a safe
    "display size from the raw file content after GUI_UPLOAD.
    IF lv_size_bytes IS INITIAL OR lv_size_text = '0 B' OR lv_size_text IS INITIAL.
      CLEAR lv_size_calc.
      LOOP AT lt_raw INTO lv_raw_line.
        lv_line_len = strlen( lv_raw_line ).
        lv_size_calc = lv_size_calc + lv_line_len + 2.
      ENDLOOP.
      IF lv_size_calc > 0.
        lv_size_bytes = lv_size_calc.
        PERFORM z23_format_file_size USING lv_size_bytes CHANGING lv_size_text.
        txtp_file_size = lv_size_text.
      ENDIF.
    ENDIF.

    CONCATENATE LINES OF lt_raw INTO lv_content.
    CONDENSE lv_content.
    lv_before = lines( gt_staging ).

    IF lv_file CP '*.json' OR lv_file CP '*.JSON'
       OR ( lv_content IS NOT INITIAL AND ( lv_content(1) = '[' OR lv_content(1) = '{' ) ).
      PERFORM process_json_rows USING lv_content.
    ELSEIF lv_file CP '*.xml' OR lv_file CP '*.XML'
       OR ( lv_content IS NOT INITIAL AND lv_content(1) = '<' ).
      PERFORM process_xml_rows USING lv_content.
    ELSE.
      PERFORM process_csv_rows USING lt_raw.
    ENDIF.

    lv_after = lines( gt_staging ).
    CLEAR: gv_forced_session_id, gv_current_file_name, gv_current_sheet_name, gv_current_unit_src.
    IF lv_after > lv_before.
      lv_ok_files = lv_ok_files + 1.
      lv_loaded   = lv_loaded + ( lv_after - lv_before ).
      MODIFY zbdc_staging_bup FROM TABLE gt_staging.
      PERFORM z16_compose_unit_name USING lv_file 'DATA' CHANGING lv_unit.
      PERFORM save_ingestion_source_log USING lv_session_id 'LOCAL' lv_unit.
      PERFORM update_session_summary USING lv_session_id.
      PERFORM z16_register_current_session USING lv_session_id.

      CLEAR ls_file_meta.
      PERFORM z16_split_unit_name USING lv_unit CHANGING lv_title lv_sheet.
      ls_file_meta-file_name   = lv_unit.
      ls_file_meta-file_title  = lv_title.
      ls_file_meta-sheet_name  = lv_sheet.
      ls_file_meta-file_size   = lv_size_text.
      ls_file_meta-rows_loaded = lv_after - lv_before.
      ls_file_meta-channel     = 'LOCAL_INGESTION'.
      ls_file_meta-upload_date = sy-datum.
      ls_file_meta-upload_time = sy-uzeit.
      ls_file_meta-username    = sy-uname.
      ls_file_meta-session_id  = lv_session_id.
      ls_file_meta-tx_code = p_transaction.
      APPEND ls_file_meta TO gt_files_preview.
    ELSE.
      lv_bad_files = lv_bad_files + 1.
    ENDIF.
  ENDLOOP.

  CLEAR gv_forced_session_id.
  PERFORM z16_finish_ingest_batch.

  IF lv_loaded > 0.
    COMMIT WORK AND WAIT.
    PERFORM z16_set_row_count_fields USING lv_loaded.
    MESSAGE |Local batch { gv_current_batch_prefix }: loaded { lv_loaded } rows from { lv_ok_files } data unit(s); skipped { lv_bad_files }.| TYPE 'S'.
  ELSE.
    CLEAR: txtp_row_count, txtp_row, txtp_rows, txtp_loaded, txtp_loaded_rows, txtp_rows_loaded.
    MESSAGE 'No data rows were loaded from selected local file(s).' TYPE 'W'.
  ENDIF.
ENDFORM.
*<<< END FORM UPLOAD_LOCAL_FILE

*>>> FORM SELECT_MAIL_INBOX - moved from Z_BDC_MASS_PO_ENTRY_F01_BUP

FORM SELECT_MAIL_INBOX.
  TYPES: BEGIN OF ty_inbox_disp,
           mark         TYPE c LENGTH 1,
           inbox_id     TYPE zbdc_mail_inbox-inbox_id,
           sender       TYPE zbdc_mail_inbox-sender,
           subject      TYPE zbdc_mail_inbox-subject,
           mail_time    TYPE zbdc_mail_inbox-mail_time,
           file_name    TYPE zbdc_mail_inbox-file_name,
           status       TYPE zbdc_mail_inbox-status,
           file_content TYPE zbdc_mail_inbox-file_content,
         END OF ty_inbox_disp.

  DATA: lt_inbox      TYPE STANDARD TABLE OF zbdc_mail_inbox,
        ls_inbox      TYPE zbdc_mail_inbox,
        lt_disp       TYPE STANDARD TABLE OF ty_inbox_disp,
        ls_disp       TYPE ty_inbox_disp,
        lt_fieldcat   TYPE slis_t_fieldcat_alv,
        ls_fieldcat   TYPE slis_fieldcat_alv,
        ls_selfield   TYPE slis_selfield,
        lv_exit       TYPE c,
        lt_raw        TYPE string_table,
        lv_content    TYPE string,
        lv_ok_files   TYPE i,
        lv_bad_files  TYPE i,
        lv_loaded     TYPE i,
        lv_before     TYPE i,
        lv_after      TYPE i,
        lv_index      TYPE i,
        lv_session_id TYPE zbdc_staging_bup-session_id,
        lv_bytes      TYPE i,
        lv_kb_calc    TYPE p DECIMALS 1,
        ls_mail_meta  TYPE ty_files_disp.

  SELECT * FROM zbdc_mail_inbox
    INTO TABLE @lt_inbox
    WHERE status = 'NEW'
    ORDER BY created_at DESCENDING.

  IF lt_inbox IS INITIAL.
    MESSAGE 'Khong co email moi nao chua file .csv.' TYPE 'S'.
    RETURN.
  ENDIF.

  LOOP AT lt_inbox INTO ls_inbox.
    CLEAR ls_disp.
    ls_disp-inbox_id     = ls_inbox-inbox_id.
    ls_disp-sender       = ls_inbox-sender.
    ls_disp-subject      = ls_inbox-subject.
    ls_disp-mail_time    = ls_inbox-mail_time.
    ls_disp-file_name    = ls_inbox-file_name.
    ls_disp-status       = ls_inbox-status.
    ls_disp-file_content = ls_inbox-file_content.
    APPEND ls_disp TO lt_disp.
  ENDLOOP.

  DEFINE add_fcat.
    CLEAR ls_fieldcat.
    ls_fieldcat-fieldname = &1.
    ls_fieldcat-seltext_l = &2.
    ls_fieldcat-outputlen = &3.
    APPEND ls_fieldcat TO lt_fieldcat.
  END-OF-DEFINITION.

  add_fcat 'SENDER'    'Nguoi gui'   40.
  add_fcat 'SUBJECT'   'Tieu de'     30.
  add_fcat 'MAIL_TIME' 'Thoi gian'   18.
  add_fcat 'FILE_NAME' 'Ten file'    25.
  add_fcat 'STATUS'    'Trang thai'  10.

  CALL FUNCTION 'REUSE_ALV_POPUP_TO_SELECT'
    EXPORTING
      i_title               = 'Chon email / attachment CSV can nap'
      i_selection           = 'X'
      i_zebra               = 'X'
      i_checkbox_fieldname  = 'MARK'
      i_tabname             = 'LT_DISP'
      it_fieldcat           = lt_fieldcat
      i_screen_start_column = 5
      i_screen_start_line   = 3
      i_screen_end_column   = 110
      i_screen_end_line     = 22
    IMPORTING
      es_selfield           = ls_selfield
      e_exit                = lv_exit
    TABLES
      t_outtab              = lt_disp
    EXCEPTIONS
      program_error         = 1
      OTHERS                = 2.

  IF lv_exit = 'X' OR sy-subrc <> 0.
    MESSAGE 'Da huy chon file.' TYPE 'S'. RETURN.
  ENDIF.

  REFRESH gt_staging.
  PERFORM z16_start_ingest_batch.
  CLEAR: lv_ok_files, lv_bad_files, lv_loaded, lv_index, txtp_file_path.

  LOOP AT lt_disp INTO ls_disp WHERE mark = 'X'.
    lv_index = lv_index + 1.
    PERFORM z16_make_batch_session USING lv_index CHANGING lv_session_id.
    gv_forced_session_id = lv_session_id.

    lv_content = ls_disp-file_content.
    lv_bytes = strlen( lv_content ).
    IF lv_bytes > 0.
      PERFORM z23_format_file_size USING lv_bytes CHANGING txtp_file_size.
    ENDIF.

    REPLACE ALL OCCURRENCES OF cl_abap_char_utilities=>cr_lf
            IN lv_content WITH cl_abap_char_utilities=>newline.
    REFRESH lt_raw.
    SPLIT lv_content AT cl_abap_char_utilities=>newline INTO TABLE lt_raw.
    IF lines( lt_raw ) <= 1.
      REFRESH lt_raw.
      SPLIT lv_content AT ';' INTO TABLE lt_raw.
    ENDIF.

    lv_before = lines( gt_staging ).
    PERFORM process_csv_rows USING lt_raw.
    lv_after = lines( gt_staging ).

    IF lv_after > lv_before.
      lv_ok_files = lv_ok_files + 1.
      lv_loaded   = lv_loaded + ( lv_after - lv_before ).
      MODIFY zbdc_staging_bup FROM TABLE gt_staging.
      PERFORM save_ingestion_source_log USING lv_session_id 'EMAIL' ls_disp-file_name.
      PERFORM update_session_summary USING lv_session_id.
      PERFORM z16_register_current_session USING lv_session_id.

      UPDATE zbdc_mail_inbox SET status = 'IMPORTED'
        WHERE inbox_id = ls_disp-inbox_id.

      IF txtp_file_path IS INITIAL.
        txtp_file_path = 'MAILBOX://' && ls_disp-file_name.
      ELSE.
        txtp_file_path = txtp_file_path && ';' && ls_disp-file_name.
      ENDIF.

      CLEAR ls_mail_meta.
      ls_mail_meta-file_name   = ls_disp-file_name.
      ls_mail_meta-file_size   = txtp_file_size.
      ls_mail_meta-channel     = 'EMAIL_INGESTION'.
      ls_mail_meta-upload_date = sy-datum.
      ls_mail_meta-upload_time = sy-uzeit.
      ls_mail_meta-username    = sy-uname.
      ls_mail_meta-session_id  = lv_session_id.
      APPEND ls_mail_meta TO gt_files_preview.
    ELSE.
      lv_bad_files = lv_bad_files + 1.
      UPDATE zbdc_mail_inbox SET status = 'ERROR'
        WHERE inbox_id = ls_disp-inbox_id.
    ENDIF.
  ENDLOOP.

  CLEAR gv_forced_session_id.
  PERFORM z16_finish_ingest_batch.

  IF lv_ok_files = 0.
    MESSAGE 'Chua chon file nao hoac file khong co du lieu hop le.' TYPE 'W'. RETURN.
  ENDIF.

  COMMIT WORK AND WAIT.
  PERFORM z16_set_row_count_fields USING lv_loaded.
  MESSAGE |Email batch { gv_current_batch_prefix }: loaded { lv_loaded } rows from { lv_ok_files } attachment(s); skipped { lv_bad_files }.| TYPE 'S'.
ENDFORM.

*&---------------------------------------------------------------------*
*& Form SELECT_GDRIVE_FILE_PATH
*& Flow: popup ME21N/MIGO → mo link Apps Script (truyen ?tcode=)
*&       → user Make a Copy Sheet → dien data → confirm
*&       → OAuth token-relay → liet ke → chon file
*&---------------------------------------------------------------------*
*<<< END FORM SELECT_MAIL_INBOX

*>>> FORM SELECT_GDRIVE_FILE_PATH - moved from Z_BDC_MASS_PO_ENTRY_F01_BUP
FORM SELECT_GDRIVE_FILE_PATH.
  DATA: LO_CLIENT TYPE REF TO IF_HTTP_CLIENT,
        LV_RESP   TYPE STRING,
        LV_URL    TYPE STRING,
        LV_CODE   TYPE I,
        LV_QCODE  TYPE STRING,
        LV_RET    TYPE C,
        LT_SVAL   TYPE STANDARD TABLE OF SVAL,
        LS_SVAL   TYPE SVAL.

  TYPES: BEGIN OF TY_GFILE, ID TYPE STRING, NAME TYPE STRING, END OF TY_GFILE.
  TYPES: BEGIN OF TY_RESP, FILES TYPE STANDARD TABLE OF TY_GFILE WITH DEFAULT KEY, END OF TY_RESP.
  DATA: LS_RESP  TYPE TY_RESP, LS_GFILE TYPE TY_GFILE.

  TYPES: BEGIN OF TY_F4_DATA,
           MARK      TYPE C LENGTH 1,
           SEL_NO    TYPE CHAR4,
           FILE_NAME TYPE C LENGTH 120,
           FILE_TYPE TYPE CHAR20,
           FILE_ID   TYPE CHAR100,
         END OF TY_F4_DATA.
  DATA: LT_F4_TABLE TYPE STANDARD TABLE OF TY_F4_DATA, LS_F4_ROW TYPE TY_F4_DATA.

  DATA: LT_MARK   TYPE STANDARD TABLE OF SPOPLI,
        LS_MARK   TYPE SPOPLI,
        LV_ANSWER TYPE C.

  DATA: lv_gas_base_url TYPE string,
        lv_token_url    TYPE string.

  " ================================================================
  " BUOC 0: Popup hoi ME21N hay MIGO
  " ================================================================
  DATA: lv_tcode_answer TYPE c,
        lv_auth_url     TYPE string,
        lv_ready        TYPE c.

  " Google Drive Web App URL is configuration, not hardcode.
  " Current Apps Script serves BOTH screens with the same /exec endpoint:
  "   /exec?tcode=ME21N|MIGO          -> template portal + 6-digit code
  "   /exec?action=token&code=xxxxxx  -> returns Bearer token from CacheService
  PERFORM LOAD_SOURCE_CONFIG.

  DATA lv_cfg_file_id TYPE string.
  DATA lv_cfg_file_nm TYPE string.
  CLEAR: lv_cfg_file_id, lv_cfg_file_nm.
  SELECT SINGLE config_value
    FROM zbdc_config_bup
    WHERE config_key = 'GDRIVE_FILE_ID'
    INTO @lv_cfg_file_id.
  SELECT SINGLE config_value
    FROM zbdc_config_bup
    WHERE config_key = 'GDRIVE_FILE_NAME'
    INTO @lv_cfg_file_nm.
  CONDENSE lv_cfg_file_id NO-GAPS.
  CONDENSE lv_cfg_file_nm.

  "Direct API-key demo path: no OAuth/list popup, no Apps Script 403.
  IF lv_cfg_file_id IS NOT INITIAL.
    IF lv_cfg_file_nm IS INITIAL.
      lv_cfg_file_nm = 'ConfiguredDriveFile.csv'.
    ENDIF.
    gv_gdrive_file_id_temp = lv_cfg_file_id.
    PERFORM z16_clear_0300_after_browse.
    txtp_file_path = 'GoogleDrive://' && lv_cfg_file_nm.
    txtp_file_size = '0 B'.
    PERFORM z16_set_row_count_fields USING 0.
    CLEAR gv_gdrive_token.
    MESSAGE 'Google Drive file selected from config. Press Upload/Ingest to parse.' TYPE 'S'.
    RETURN.
  ENDIF.

  lv_gas_base_url = TXTP_GDRIVE_URL.
  CONDENSE lv_gas_base_url NO-GAPS.

  IF lv_gas_base_url IS INITIAL.
    MESSAGE 'Google Drive Web App URL is missing in ZBDC_CONFIG_BUP (GDRIVE_URL).' TYPE 'E'.
    RETURN.
  ENDIF.

  IF lv_gas_base_url CS '?'.
    SPLIT lv_gas_base_url AT '?' INTO lv_gas_base_url LV_RESP.
  ENDIF.

  CALL FUNCTION 'POPUP_TO_CONFIRM'
    EXPORTING
      titlebar              = 'Google Drive - Chon Template'
      text_question         = 'Chon loai giao dich de lay template tu Drive:'
      text_button_1         = 'ME21N (Tao PO)'
      text_button_2         = 'MIGO (Nhap kho 101)'
      default_button        = '1'
      display_cancel_button = 'X'
    IMPORTING
      answer                = lv_tcode_answer.

  IF lv_tcode_answer = 'A'. RETURN. ENDIF.

  IF lv_tcode_answer = '1'.
    P_TRANSACTION = 'ME21N'.
    lv_auth_url = lv_gas_base_url && '?tcode=ME21N'.
  ELSE.
    P_TRANSACTION = 'MIGO'.
    lv_auth_url = lv_gas_base_url && '?tcode=MIGO'.
  ENDIF.

  " ================================================================
  " BUOC 1: Mo trinh duyet voi param ?tcode=
  " ================================================================
  CL_GUI_FRONTEND_SERVICES=>EXECUTE( EXPORTING DOCUMENT = lv_auth_url EXCEPTIONS OTHERS = 1 ).
  CALL METHOD CL_GUI_CFW=>FLUSH.

  CALL FUNCTION 'POPUP_TO_CONFIRM'
    EXPORTING
      TITLEBAR      = 'Google Drive Template'
      TEXT_QUESTION  = 'Da tao ban sao/dien du lieu tren Google Drive xong chua?'
      TEXT_BUTTON_1  = 'Da xong - Tiep tuc'
      TEXT_BUTTON_2  = 'Huy'
    IMPORTING
      ANSWER        = lv_ready.
  IF lv_ready <> '1'. RETURN. ENDIF.

  " ================================================================
  " BUOC 2: Nhap ma xac thuc tu trinh duyet
  " ================================================================
  LS_SVAL-TABNAME = 'ZBDC_CONFIG_BUP'. LS_SVAL-FIELDNAME = 'CONFIG_VALUE'.
  LS_SVAL-FIELDTEXT = 'Ma xac thuc 6 so'. APPEND LS_SVAL TO LT_SVAL.
  CALL FUNCTION 'POPUP_GET_VALUES'
    EXPORTING
      POPUP_TITLE = 'Nhap ma xac thuc Google Drive'
    IMPORTING
      RETURNCODE  = LV_RET
    TABLES
      FIELDS      = LT_SVAL.
  IF LV_RET = 'A'. MESSAGE 'Da huy.' TYPE 'S'. RETURN. ENDIF.
  READ TABLE LT_SVAL INTO LS_SVAL INDEX 1. LV_QCODE = LS_SVAL-VALUE.
  CONDENSE LV_QCODE NO-GAPS.
  IF LV_QCODE IS INITIAL. MESSAGE 'Chua nhap ma.' TYPE 'E'. RETURN. ENDIF.

  " ================================================================
  " V5BK: Apps Script KHONG DOI - dung dung flow trong guide:
  " 1) /exec?tcode=... mo trang template + ma 6 so
  " 2) /exec?action=token&code=... doi ma lay Bearer token
  " 3) Drive API list files bang Bearer token
  " 4) Upload/Ingest moi download/export CSV tu file da chon
  " ================================================================
  lv_token_url = lv_gas_base_url && '?action=token&code=' && LV_QCODE.
  LV_URL = lv_token_url.
  CL_HTTP_CLIENT=>CREATE_BY_URL( EXPORTING URL = LV_URL IMPORTING CLIENT = LO_CLIENT EXCEPTIONS OTHERS = 1 ).
  IF SY-SUBRC <> 0. MESSAGE 'Loi HTTP client (token).' TYPE 'E'. RETURN. ENDIF.
  LO_CLIENT->REQUEST->SET_METHOD( 'GET' ).
  LO_CLIENT->PROPERTYTYPE_REDIRECT = LO_CLIENT->CO_ENABLED.
  LO_CLIENT->SEND( EXCEPTIONS OTHERS = 1 ).
  LO_CLIENT->RECEIVE( EXCEPTIONS OTHERS = 1 ).
  LO_CLIENT->RESPONSE->GET_STATUS( IMPORTING CODE = LV_CODE ).
  LV_RESP = LO_CLIENT->RESPONSE->GET_CDATA( ).
  LO_CLIENT->CLOSE( ).
  IF LV_RESP CP 'ERROR:*' OR LV_RESP IS INITIAL.
    MESSAGE 'Ma sai hoac da het han.' TYPE 'E'. RETURN.
  ENDIF.
  GV_GDRIVE_TOKEN = LV_RESP.

  " ================================================================
  " BUOC 4: Liet ke file dung template/tcode, khong bung ca Drive.
  " Apps Script hien tai dung ScriptApp.getOAuthToken() + ma 6 so noi bo.
  " Vì vậy Drive API có thể thấy nhiều file mà token owner có quyền.
  " Query phải lọc chặt theo template_ME21N/template_MIGO để demo sạch.
  " ================================================================
  DATA lv_name_filter TYPE string.

  IF p_transaction = 'MIGO'.
    lv_name_filter = |(name contains 'template_MIGO' or name contains 'MIGO' or name contains 'migo')|.
  ELSE.
    lv_name_filter = |(name contains 'template_ME21N' or name contains 'ME21N' or name contains 'me21n')|.
  ENDIF.

  DO.
    CLEAR: LS_RESP, LS_GFILE, LT_F4_TABLE, LS_F4_ROW, LT_MARK, LS_MARK, LV_ANSWER.

  LV_URL = 'https://www.googleapis.com/drive/v3/files?q='
        && CL_HTTP_UTILITY=>ESCAPE_URL( |{ lv_name_filter } and (mimeType='text/csv' or mimeType='application/vnd.google-apps.spreadsheet') and trashed=false| )
        && '&fields=files(id,name)&pageSize=50'.
  CL_HTTP_CLIENT=>CREATE_BY_URL( EXPORTING URL = LV_URL IMPORTING CLIENT = LO_CLIENT EXCEPTIONS OTHERS = 1 ).
  IF SY-SUBRC <> 0. MESSAGE 'Loi HTTP client (Drive API).' TYPE 'E'. RETURN. ENDIF.
  LO_CLIENT->REQUEST->SET_METHOD( 'GET' ).
  LO_CLIENT->REQUEST->SET_HEADER_FIELD( NAME = 'Authorization' VALUE = |Bearer { GV_GDRIVE_TOKEN }| ).
  LO_CLIENT->SEND( EXCEPTIONS OTHERS = 1 ).
  LO_CLIENT->RECEIVE( EXCEPTIONS OTHERS = 1 ).
  LO_CLIENT->RESPONSE->GET_STATUS( IMPORTING CODE = LV_CODE ).
  LV_RESP = LO_CLIENT->RESPONSE->GET_CDATA( ).
  LO_CLIENT->CLOSE( ).
  IF LV_CODE <> 200.
    IF LV_CODE = 403.
      MESSAGE 'Drive API HTTP 403. Check Apps Script OAuth/deploy scope or use GDRIVE_FILE_ID + GDRIVE_API_KEY.' TYPE 'E'.
    ELSE.
      MESSAGE |Drive API tra HTTP { LV_CODE }.| TYPE 'E'.
    ENDIF.
    RETURN.
  ENDIF.

  /UI2/CL_JSON=>DESERIALIZE(
    EXPORTING JSON = LV_RESP PRETTY_NAME = /UI2/CL_JSON=>PRETTY_MODE-NONE
    CHANGING  DATA = LS_RESP ).

  IF LS_RESP-FILES IS INITIAL.
    MESSAGE 'Khong co file nao tren Drive.' TYPE 'W'. RETURN.
  ENDIF.

  " ================================================================
  " BUOC 5: Professional multi-select Google Drive file chooser
  " ================================================================
  "One-include solution using the standard ALV selection popup:
  "  - visible business columns: No / File Name / File Type
  "  - technical Google FILE_ID remains hidden
  "  - standard popup supplies Select / Select All / Deselect All / Cancel
  "  - Refresh is represented as a clear first action row and reuses token
  "  - real File Size and Rows remain 0 until Upload/Ingest
  DATA: LT_GD_FIELDCAT TYPE SLIS_T_FIELDCAT_ALV,
        LS_GD_FIELDCAT TYPE SLIS_FIELDCAT_ALV,
        LS_GD_SELFIELD TYPE SLIS_SELFIELD,
        LV_GD_EXIT     TYPE C,
        LV_SEQ         TYPE I,
        LV_SEQ_TXT     TYPE C LENGTH 4,
        LV_DISPLAY_NM  TYPE C LENGTH 120,
        LV_FILE_KIND   TYPE C LENGTH 20,
        LV_SELECTED    TYPE I,
        LV_IDS         TYPE STRING,
        LV_NAMES       TYPE STRING,
        LV_REFRESH     TYPE C LENGTH 1.

  CLEAR LS_F4_ROW.
  LS_F4_ROW-SEL_NO    = '0'.
  LS_F4_ROW-FILE_NAME = '[Refresh] Reload Google Drive file list'.
  LS_F4_ROW-FILE_TYPE = 'Action'.
  LS_F4_ROW-FILE_ID   = '__REFRESH__'.
  APPEND LS_F4_ROW TO LT_F4_TABLE.

  CLEAR LV_SEQ.
  LOOP AT LS_RESP-FILES INTO LS_GFILE.
    LV_SEQ = LV_SEQ + 1.
    CLEAR: LS_F4_ROW, LV_SEQ_TXT, LV_DISPLAY_NM, LV_FILE_KIND.

    WRITE LV_SEQ TO LV_SEQ_TXT LEFT-JUSTIFIED.
    CONDENSE LV_SEQ_TXT NO-GAPS.

    LV_DISPLAY_NM = LS_GFILE-NAME.
    CONDENSE LV_DISPLAY_NM.

    IF LV_DISPLAY_NM IS INITIAL OR LV_DISPLAY_NM = LS_GFILE-ID.
      IF P_TRANSACTION = 'MIGO'.
        LV_DISPLAY_NM = |MIGO Drive file { LV_SEQ_TXT }|.
      ELSE.
        LV_DISPLAY_NM = |ME21N Drive file { LV_SEQ_TXT }|.
      ENDIF.
    ENDIF.

    LV_FILE_KIND = 'Google Sheet'.
    IF LV_DISPLAY_NM CP '*.csv' OR LV_DISPLAY_NM CP '*.CSV'.
      LV_FILE_KIND = 'CSV'.
    ELSEIF LV_DISPLAY_NM CP '*.xlsx' OR LV_DISPLAY_NM CP '*.XLSX'.
      LV_FILE_KIND = 'XLSX'.
    ENDIF.

    LS_F4_ROW-SEL_NO    = LV_SEQ_TXT.
    LS_F4_ROW-FILE_NAME = LV_DISPLAY_NM.
    LS_F4_ROW-FILE_TYPE = LV_FILE_KIND.
    LS_F4_ROW-FILE_ID   = LS_GFILE-ID.
    APPEND LS_F4_ROW TO LT_F4_TABLE.
  ENDLOOP.

  DEFINE ADD_GD_FCAT.
    CLEAR LS_GD_FIELDCAT.
    LS_GD_FIELDCAT-FIELDNAME = &1.
    LS_GD_FIELDCAT-SELTEXT_S = &2.
    LS_GD_FIELDCAT-SELTEXT_M = &3.
    LS_GD_FIELDCAT-SELTEXT_L = &3.
    LS_GD_FIELDCAT-OUTPUTLEN = &4.
    LS_GD_FIELDCAT-NO_OUT    = &5.
    APPEND LS_GD_FIELDCAT TO LT_GD_FIELDCAT.
  END-OF-DEFINITION.

  ADD_GD_FCAT 'SEL_NO'    'No'   'No'            4  ''.
  ADD_GD_FCAT 'FILE_NAME' 'File' 'File Name'     62 ''.
  ADD_GD_FCAT 'FILE_TYPE' 'Type' 'File Type'     16 ''.
  ADD_GD_FCAT 'FILE_ID'   'ID'   'Technical ID'  10 'X'.

  CALL FUNCTION 'REUSE_ALV_POPUP_TO_SELECT'
    EXPORTING
      I_TITLE               = 'Google Drive Files'
      I_SELECTION           = 'X'
      I_ZEBRA               = 'X'
      I_CHECKBOX_FIELDNAME  = 'MARK'
      I_TABNAME             = 'LT_F4_TABLE'
      IT_FIELDCAT           = LT_GD_FIELDCAT
      I_SCREEN_START_COLUMN = 8
      I_SCREEN_START_LINE   = 2
      I_SCREEN_END_COLUMN   = 112
      I_SCREEN_END_LINE     = 22
    IMPORTING
      ES_SELFIELD           = LS_GD_SELFIELD
      E_EXIT                = LV_GD_EXIT
    TABLES
      T_OUTTAB              = LT_F4_TABLE
    EXCEPTIONS
      PROGRAM_ERROR         = 1
      OTHERS                = 2.

  IF LV_GD_EXIT = 'X' OR SY-SUBRC <> 0.
    MESSAGE 'Google Drive selection canceled.' TYPE 'S'.
    RETURN.
  ENDIF.

  CLEAR: LV_SELECTED, LV_IDS, LV_NAMES, LV_REFRESH.
  LOOP AT LT_F4_TABLE INTO LS_F4_ROW WHERE MARK = 'X'.
    IF LS_F4_ROW-FILE_ID = '__REFRESH__'.
      LV_REFRESH = 'X'.
      CONTINUE.
    ENDIF.
    IF LS_F4_ROW-FILE_ID IS INITIAL.
      CONTINUE.
    ENDIF.

    LV_SELECTED = LV_SELECTED + 1.
    IF LV_IDS IS INITIAL.
      LV_IDS   = LS_F4_ROW-FILE_ID.
      LV_NAMES = LS_F4_ROW-FILE_NAME.
    ELSE.
      LV_IDS   = LV_IDS   && ';' && LS_F4_ROW-FILE_ID.
      LV_NAMES = LV_NAMES && ';' && LS_F4_ROW-FILE_NAME.
    ENDIF.
  ENDLOOP.

  "Treat the current ALV row as Select when user did not tick a checkbox.
  IF LV_SELECTED = 0 AND LV_REFRESH IS INITIAL
     AND LS_GD_SELFIELD-TABINDEX IS NOT INITIAL.
    READ TABLE LT_F4_TABLE INTO LS_F4_ROW INDEX LS_GD_SELFIELD-TABINDEX.
    IF SY-SUBRC = 0.
      IF LS_F4_ROW-FILE_ID = '__REFRESH__'.
        LV_REFRESH = 'X'.
      ELSEIF LS_F4_ROW-FILE_ID IS NOT INITIAL.
        LV_SELECTED = 1.
        LV_IDS      = LS_F4_ROW-FILE_ID.
        LV_NAMES    = LS_F4_ROW-FILE_NAME.
      ENDIF.
    ENDIF.
  ENDIF.

  IF LV_REFRESH = 'X'.
    IF LV_SELECTED > 0.
      MESSAGE 'Refresh cannot be combined with file selection. Reloading the list.' TYPE 'S' DISPLAY LIKE 'W'.
    ELSE.
      MESSAGE 'Refreshing Google Drive file list...' TYPE 'S'.
    ENDIF.
    CONTINUE.
  ENDIF.

  IF LV_SELECTED = 0.
    MESSAGE 'Select at least one Google Drive file.' TYPE 'W'.
    CONTINUE.
  ENDIF.

  " ================================================================
  " BUOC 6: Record selected IDs only; Upload/Ingest owns real metadata
  " ================================================================
  PERFORM Z16_CLEAR_0300_AFTER_BROWSE.
  CLEAR: TXTP_FILE_PATH, GV_GDRIVE_FILE_ID_TEMP.
  TXTP_FILE_PATH         = 'GoogleDrive://' && LV_NAMES.
  GV_GDRIVE_FILE_ID_TEMP = LV_IDS.
  TXTP_FILE_SIZE         = '0 B'.
  PERFORM Z16_SET_ROW_COUNT_FIELDS USING 0.

  REFRESH: GT_STAGING, GT_STAGING_ALV, GT_PREVIEW_DATA.
  PERFORM Z16_RESET_0300_ALL_ALV.

  MESSAGE |Selected { LV_SELECTED } Google Drive file(s). Press Upload/Ingest to parse.| TYPE 'S'.
  EXIT.
  ENDDO.
ENDFORM.

*&---------------------------------------------------------------------*
*& Form Z23_DOWNLOAD_GDRIVE_SCRIPT_CSV
*& Apps Script CSV endpoint path for Google Drive onboarding.
*& Keeps legacy SFTP/local/SM35 flows untouched.
*&---------------------------------------------------------------------*
*<<< END FORM SELECT_GDRIVE_FILE_PATH

*>>> FORM DOWNLOAD_FROM_GDRIVE_FILE - moved from Z_BDC_MASS_PO_ENTRY_F01_BUP
FORM DOWNLOAD_FROM_GDRIVE_FILE.
  DATA: lo_client       TYPE REF TO if_http_client,
        lv_code         TYPE i,
        lv_url          TYPE string,
        lv_resp         TYPE string,
        lt_marked_files TYPE TABLE OF string,
        lt_file_names   TYPE TABLE OF string,
        lv_current_id   TYPE string,
        lv_file_name    TYPE string,
        lv_path_names   TYPE string,
        lt_raw          TYPE string_table,
        lv_size         TYPE i,
        lv_size_kb      TYPE p DECIMALS 1,
        lv_index        TYPE i,
        lv_file_index   TYPE i,
        lv_before       TYPE i,
        lv_after        TYPE i,
        lv_loaded       TYPE i,
        lv_ok_files     TYPE i,
        lv_bad_files    TYPE i,
        lv_session_id   TYPE zbdc_staging_bup-session_id,
        ls_gdrive_meta  TYPE ty_files_disp,
        lv_payload_xstr TYPE xstring.

  PERFORM load_source_config.

  IF gv_gdrive_file_id_temp = 'APPSCRIPT_CSV'.
    PERFORM z23_download_gdrive_script_csv.
    RETURN.
  ENDIF.

  IF gv_gdrive_file_id_temp IS INITIAL.
    MESSAGE 'Please select Google Drive files first.' TYPE 'E'. RETURN.
  ENDIF.
  IF gv_gdrive_token IS INITIAL AND txtp_api_key IS INITIAL.
    MESSAGE 'Drive token/API key missing. Select Drive file again or maintain GDRIVE_API_KEY.' TYPE 'E'. RETURN.
  ENDIF.

  SPLIT gv_gdrive_file_id_temp AT ';' INTO TABLE lt_marked_files.
  lv_path_names = txtp_file_path.
  REPLACE FIRST OCCURRENCE OF 'GoogleDrive://' IN lv_path_names WITH ''.
  SPLIT lv_path_names AT ';' INTO TABLE lt_file_names.

  REFRESH gt_staging.
  PERFORM z16_start_ingest_batch.
  CLEAR: lv_index, lv_file_index, lv_loaded, lv_ok_files, lv_bad_files.

  LOOP AT lt_marked_files INTO lv_current_id.
    IF lv_current_id IS INITIAL. CONTINUE. ENDIF.
    lv_file_index = lv_file_index + 1.
    READ TABLE lt_file_names INTO lv_file_name INDEX lv_file_index.
    IF lv_file_name IS INITIAL.
      lv_file_name = lv_current_id.
    ENDIF.

    lv_index = lv_index + 1.
    PERFORM z16_make_batch_session USING lv_index CHANGING lv_session_id.
    gv_forced_session_id = lv_session_id.
    gv_current_file_name  = lv_file_name.
    gv_current_sheet_name = 'DATA'.
    gv_current_unit_src   = 'GDRIVE'.

    lv_url = 'https://www.googleapis.com/drive/v3/files/' && lv_current_id && '/export?mimeType=text%2Fcsv'.
    IF gv_gdrive_token IS INITIAL AND txtp_api_key IS NOT INITIAL.
      lv_url = lv_url && '&key=' && txtp_api_key.
    ENDIF.
    cl_http_client=>create_by_url( EXPORTING url = lv_url IMPORTING client = lo_client EXCEPTIONS OTHERS = 1 ).
    IF sy-subrc <> 0.
      lv_bad_files = lv_bad_files + 1. CONTINUE.
    ENDIF.

    lo_client->request->set_method( 'GET' ).
    IF gv_gdrive_token IS NOT INITIAL.
      lo_client->request->set_header_field( name = 'Authorization' value = |Bearer { gv_gdrive_token }| ).
    ENDIF.
    lo_client->send( EXCEPTIONS OTHERS = 1 ).
    lo_client->receive( EXCEPTIONS OTHERS = 1 ).
    lo_client->response->get_status( IMPORTING code = lv_code ).

    IF lv_code <> 200.
      lo_client->close( ).
      lv_url = 'https://www.googleapis.com/drive/v3/files/' && lv_current_id && '?alt=media'.
      IF gv_gdrive_token IS INITIAL AND txtp_api_key IS NOT INITIAL.
        lv_url = lv_url && '&key=' && txtp_api_key.
      ENDIF.
      cl_http_client=>create_by_url( EXPORTING url = lv_url IMPORTING client = lo_client EXCEPTIONS OTHERS = 1 ).
      IF sy-subrc <> 0.
        lv_bad_files = lv_bad_files + 1. CONTINUE.
      ENDIF.
      lo_client->request->set_method( 'GET' ).
      IF gv_gdrive_token IS NOT INITIAL.
        lo_client->request->set_header_field( name = 'Authorization' value = |Bearer { gv_gdrive_token }| ).
      ENDIF.
      lo_client->send( EXCEPTIONS OTHERS = 1 ).
      lo_client->receive( EXCEPTIONS OTHERS = 1 ).
      lo_client->response->get_status( IMPORTING code = lv_code ).
    ENDIF.

    IF lv_code = 200.
      lv_payload_xstr = lo_client->response->get_data( ).
      IF lv_file_name CP '*.xlsx' OR lv_file_name CP '*.XLSX'.
        PERFORM z16_ingest_xlsx_xstr USING lv_file_name 'GDRIVE' lv_payload_xstr
          CHANGING lv_index lv_loaded lv_ok_files lv_bad_files.
        lo_client->close( ).
        CONTINUE.
      ENDIF.
      lv_resp = lo_client->response->get_cdata( ).
      REPLACE ALL OCCURRENCES OF cl_abap_char_utilities=>cr_lf
              IN lv_resp WITH cl_abap_char_utilities=>newline.
      REFRESH lt_raw.
      SPLIT lv_resp AT cl_abap_char_utilities=>newline INTO TABLE lt_raw.

      lv_size = xstrlen( lv_payload_xstr ).
      IF lv_size IS INITIAL AND lv_resp IS NOT INITIAL.
        lv_size = strlen( lv_resp ).
      ENDIF.
      PERFORM z23_format_file_size USING lv_size CHANGING txtp_file_size.

      lv_before = lines( gt_staging ).
      PERFORM process_csv_rows USING lt_raw.
      lv_after = lines( gt_staging ).
      CLEAR: gv_forced_session_id, gv_current_file_name, gv_current_sheet_name, gv_current_unit_src.

      IF lv_after > lv_before.
        lv_ok_files = lv_ok_files + 1.
        lv_loaded   = lv_loaded + ( lv_after - lv_before ).
        MODIFY zbdc_staging_bup FROM TABLE gt_staging.
        DATA lv_gd_unit TYPE string.
        PERFORM z16_compose_unit_name USING lv_file_name 'DATA' CHANGING lv_gd_unit.
        PERFORM save_ingestion_source_log USING lv_session_id 'GDRIVE' lv_gd_unit.
        PERFORM update_session_summary USING lv_session_id.
        PERFORM z16_register_current_session USING lv_session_id.

        CLEAR ls_gdrive_meta.
        ls_gdrive_meta-file_name   = lv_gd_unit.
        PERFORM z16_split_unit_name USING lv_gd_unit CHANGING ls_gdrive_meta-file_title ls_gdrive_meta-sheet_name.
        ls_gdrive_meta-file_size   = txtp_file_size.
        ls_gdrive_meta-rows_loaded = lv_after - lv_before.
        ls_gdrive_meta-channel     = 'GDRIVE_INGESTION'.
        ls_gdrive_meta-upload_date = sy-datum.
        ls_gdrive_meta-upload_time = sy-uzeit.
        ls_gdrive_meta-username    = sy-uname.
        ls_gdrive_meta-session_id  = lv_session_id.
        ls_gdrive_meta-tx_code     = p_transaction.
        APPEND ls_gdrive_meta TO gt_files_preview.
      ELSE.
        lv_bad_files = lv_bad_files + 1.
      ENDIF.
    ELSE.
      lv_bad_files = lv_bad_files + 1.
      IF lv_code = 403.
        MESSAGE |Drive file [{ lv_file_name }] HTTP 403. Share file Anyone Viewer or use valid OAuth token.| TYPE 'W'.
      ELSE.
        MESSAGE |Khong tai duoc Drive file [{ lv_file_name }] (HTTP { lv_code }).| TYPE 'W'.
      ENDIF.
    ENDIF.
    lo_client->close( ).
  ENDLOOP.

  CLEAR gv_forced_session_id.
  PERFORM z16_finish_ingest_batch.

  IF lv_loaded > 0.
    COMMIT WORK AND WAIT.
    PERFORM z16_set_row_count_fields USING lv_loaded.
    MESSAGE |Google Drive batch { gv_current_batch_prefix }: loaded { lv_loaded } rows from { lv_ok_files } file(s); skipped { lv_bad_files }.| TYPE 'S'.
  ELSE.
    MESSAGE 'Khong co du lieu Google Drive hop le.' TYPE 'E'.
  ENDIF.
ENDFORM.
*<<< END FORM DOWNLOAD_FROM_GDRIVE_FILE

*>>> FORM UPLOAD_FROM_REST - moved from Z_BDC_MASS_PO_ENTRY_F01_BUP

FORM UPLOAD_FROM_REST.
  DATA: LO_CLIENT  TYPE REF TO IF_HTTP_CLIENT,
        LV_CODE    TYPE I,
        LV_REASON  TYPE STRING,
        LT_RAW     TYPE STRING_TABLE,
        LV_RESP    TYPE STRING,
        LV_SIZE    TYPE I,
        LV_SIZE_KB TYPE P DECIMALS 1,
        LV_NEW     TYPE I,
        LV_REST_SESSION TYPE ZBDC_STAGING_BUP-SESSION_ID,
        LV_REST_XSTR TYPE XSTRING.

  "Gmail/n8n pushes CSV into SAP ICF table ZBDC_MAIL_INBOX.
  "Use the same popup flow as Browse -> REST so the user selects the real email/file.
  SELECT COUNT(*) FROM ZBDC_MAIL_INBOX INTO @LV_NEW WHERE STATUS = 'NEW'.
  IF LV_NEW > 0.
    PERFORM SELECT_MAIL_INBOX.
    RETURN.
  ENDIF.

  "Fallback for legacy REST pull/demo endpoint returning CSV.
  PERFORM LOAD_SOURCE_CONFIG.
  IF TXTP_WEBHOOK_URL IS INITIAL.
    MESSAGE 'No NEW Gmail webhook message and Webhook URL is empty.' TYPE 'W'.
    RETURN.
  ENDIF.

  CL_HTTP_CLIENT=>CREATE_BY_URL( EXPORTING URL = TXTP_WEBHOOK_URL IMPORTING CLIENT = LO_CLIENT EXCEPTIONS OTHERS = 1 ).
  IF SY-SUBRC <> 0 OR LO_CLIENT IS INITIAL.
    MESSAGE 'Cannot create HTTP client.' TYPE 'E'.
    RETURN.
  ENDIF.

  LO_CLIENT->REQUEST->SET_METHOD( 'GET' ).
  LO_CLIENT->SEND( EXCEPTIONS OTHERS = 1 ).
  LO_CLIENT->RECEIVE( EXCEPTIONS OTHERS = 1 ).
  LO_CLIENT->RESPONSE->GET_STATUS( IMPORTING CODE = LV_CODE REASON = LV_REASON ).

  IF LV_CODE = 200.
    LV_REST_XSTR = LO_CLIENT->RESPONSE->GET_DATA( ).
    LV_RESP = LO_CLIENT->RESPONSE->GET_CDATA( ).
    SPLIT LV_RESP AT CL_ABAP_CHAR_UTILITIES=>NEWLINE INTO TABLE LT_RAW.
    TXTP_FILE_PATH = 'REST_API://' && TXTP_WEBHOOK_URL.
    LV_SIZE = XSTRLEN( LV_REST_XSTR ).
    PERFORM z23_format_file_size USING LV_SIZE CHANGING TXTP_FILE_SIZE.

    REFRESH GT_STAGING.
    PERFORM z16_start_ingest_batch.
    PERFORM z16_make_batch_session USING 1 CHANGING LV_REST_SESSION.
    GV_FORCED_SESSION_ID = LV_REST_SESSION.
    PERFORM PROCESS_CSV_ROWS USING LT_RAW.
    CLEAR GV_FORCED_SESSION_ID.
    PERFORM z16_finish_ingest_batch.
    IF GT_STAGING IS NOT INITIAL.
      MODIFY ZBDC_STAGING_BUP FROM TABLE GT_STAGING.

      DATA: LS_REST_META TYPE TY_FILES_DISP.
      READ TABLE GT_STAGING INTO DATA(LS_STG_RT) INDEX 1.
      LS_REST_META-FILE_NAME   = TXTP_FILE_PATH.
      LS_REST_META-FILE_SIZE   = TXTP_FILE_SIZE.
      LS_REST_META-ROWS_LOADED = LINES( GT_STAGING ).
      LS_REST_META-CHANNEL     = 'REST_API_FALLBACK'.
      LS_REST_META-UPLOAD_DATE = SY-DATUM.
      LS_REST_META-UPLOAD_TIME = SY-UZEIT.
      LS_REST_META-USERNAME    = SY-UNAME.
      LS_REST_META-SESSION_ID  = LS_STG_RT-SESSION_ID.
      APPEND LS_REST_META TO GT_FILES_PREVIEW.
      PERFORM save_ingestion_source_log USING LS_STG_RT-SESSION_ID 'REST' TXTP_FILE_PATH.
      PERFORM update_session_summary USING LS_STG_RT-SESSION_ID.
      PERFORM z16_register_current_session USING LS_STG_RT-SESSION_ID.

      COMMIT WORK AND WAIT.

      "SENIOR FIX: bao dung so dong thuc te, dong bo voi cac kenh khac.
      WRITE LINES( GT_STAGING ) TO TXTP_ROW_COUNT LEFT-JUSTIFIED.
      MESSAGE |Da nap { LINES( GT_STAGING ) } dong tu REST fallback.| TYPE 'S'.
    ELSE.
      "SENIOR FIX: truoc day IM LANG khi response 200 OK nhung khong co dong du lieu nao
      "(vi du dung endpoint sai, tra ve JSON thay vi CSV, hoac file rong). Gio bao ro.
      CLEAR TXTP_ROW_COUNT.
      MESSAGE |REST fallback tra ve HTTP 200 nhung khong co dong du lieu nao de nap.| TYPE 'W'.
    ENDIF.
  ELSE.
    MESSAGE |Failed to fetch from REST fallback (HTTP { LV_CODE }).| TYPE 'E'.
  ENDIF.
  LO_CLIENT->CLOSE( ).
ENDFORM.
*<<< END FORM UPLOAD_FROM_REST

*>>> FORM UPLOAD_FROM_GDRIVE - moved from Z_BDC_MASS_PO_ENTRY_F01_BUP


FORM UPLOAD_FROM_GDRIVE CHANGING CT_RAW TYPE STRING_TABLE.
  PERFORM DOWNLOAD_FROM_GDRIVE_FILE.
ENDFORM.

*&---------------------------------------------------------------------*
*& M123 MERGE HELPERS - Gmail webhook bridge + robust CSV + config mode
*&---------------------------------------------------------------------*
*<<< END FORM UPLOAD_FROM_GDRIVE

*>>> FORM LOAD_GMAIL_WEBHOOK_INBOUND - moved from Z_BDC_MASS_PO_ENTRY_F01_BUP
FORM LOAD_GMAIL_WEBHOOK_INBOUND.
  DATA: LT_MAIL    TYPE STANDARD TABLE OF ZBDC_MAIL_INBOX,
        LS_MAIL    TYPE ZBDC_MAIL_INBOX,
        LV_PAYLOAD TYPE STRING,
        LV_SOURCE  TYPE STRING,
        LV_LOADED  TYPE I,
        LV_INDEX   TYPE I,
        LV_BEFORE  TYPE I,
        LV_AFTER   TYPE I,
        LV_SESSION_ID TYPE ZBDC_STAGING_BUP-SESSION_ID,
        LT_RAW     TYPE STRING_TABLE.

  SELECT * FROM ZBDC_MAIL_INBOX
    INTO TABLE @LT_MAIL
    WHERE STATUS = 'NEW'.

  IF LT_MAIL IS INITIAL.
    MESSAGE 'No NEW Gmail webhook inbound message found.' TYPE 'W'.
    RETURN.
  ENDIF.

  REFRESH GT_STAGING.
  PERFORM z16_start_ingest_batch.
  CLEAR LV_INDEX.

  LOOP AT LT_MAIL INTO LS_MAIL.
    CLEAR: LV_PAYLOAD, LV_SOURCE.
    LV_INDEX = LV_INDEX + 1.
    PERFORM z16_make_batch_session USING LV_INDEX CHANGING LV_SESSION_ID.
    GV_FORCED_SESSION_ID = LV_SESSION_ID.
    PERFORM GET_DYN_COMP_AS_STRING USING LS_MAIL 'PAYLOAD_JSON' CHANGING LV_PAYLOAD.
    IF LV_PAYLOAD IS INITIAL. PERFORM GET_DYN_COMP_AS_STRING USING LS_MAIL 'JSON_PAYLOAD' CHANGING LV_PAYLOAD. ENDIF.
    IF LV_PAYLOAD IS INITIAL. PERFORM GET_DYN_COMP_AS_STRING USING LS_MAIL 'RAW_JSON'     CHANGING LV_PAYLOAD. ENDIF.
    IF LV_PAYLOAD IS INITIAL. PERFORM GET_DYN_COMP_AS_STRING USING LS_MAIL 'RAW_BODY'     CHANGING LV_PAYLOAD. ENDIF.
    IF LV_PAYLOAD IS INITIAL. PERFORM GET_DYN_COMP_AS_STRING USING LS_MAIL 'BODY'         CHANGING LV_PAYLOAD. ENDIF.
    IF LV_PAYLOAD IS INITIAL. PERFORM GET_DYN_COMP_AS_STRING USING LS_MAIL 'PAYLOAD'      CHANGING LV_PAYLOAD. ENDIF.
    PERFORM GET_DYN_COMP_AS_STRING USING LS_MAIL 'MAIL_ID' CHANGING LV_SOURCE.
    IF LV_SOURCE IS INITIAL. PERFORM GET_DYN_COMP_AS_STRING USING LS_MAIL 'MESSAGE_ID' CHANGING LV_SOURCE. ENDIF.
    IF LV_SOURCE IS INITIAL. LV_SOURCE = |WEBHOOK-{ SY-TABIX }|. ENDIF.

    IF LV_PAYLOAD IS INITIAL.
      LS_MAIL-STATUS = 'ERROR'.
      MODIFY ZBDC_MAIL_INBOX FROM LS_MAIL.
      CONTINUE.
    ENDIF.

    SHIFT LV_PAYLOAD LEFT DELETING LEADING SPACE.
    LV_BEFORE = LINES( GT_STAGING ).
    IF LV_PAYLOAD IS NOT INITIAL AND ( LV_PAYLOAD(1) = '[' OR LV_PAYLOAD(1) = '{' ).
      PERFORM INGEST_JSON_PAYLOAD_BUP USING LV_PAYLOAD LV_SOURCE.
    ELSE.
      SPLIT LV_PAYLOAD AT CL_ABAP_CHAR_UTILITIES=>NEWLINE INTO TABLE LT_RAW.
      PERFORM PROCESS_CSV_ROWS USING LT_RAW.
    ENDIF.
    LV_AFTER = LINES( GT_STAGING ).
    CLEAR: GV_FORCED_SESSION_ID, gv_current_file_name, gv_current_sheet_name, gv_current_unit_src.

    IF LV_AFTER > LV_BEFORE.
      MODIFY ZBDC_STAGING_BUP FROM TABLE GT_STAGING.
      PERFORM save_ingestion_source_log USING LV_SESSION_ID 'EMAIL' LV_SOURCE.
      PERFORM update_session_summary USING LV_SESSION_ID.
      PERFORM z16_register_current_session USING LV_SESSION_ID.
      LS_MAIL-STATUS = 'PROCESSED'.
      LV_LOADED = LV_LOADED + 1.
    ELSE.
      LS_MAIL-STATUS = 'ERROR'.
    ENDIF.
    MODIFY ZBDC_MAIL_INBOX FROM LS_MAIL.
  ENDLOOP.

  CLEAR GV_FORCED_SESSION_ID.
  PERFORM z16_finish_ingest_batch.

  IF GT_STAGING IS NOT INITIAL.
    MODIFY ZBDC_STAGING_BUP FROM TABLE GT_STAGING.
    COMMIT WORK AND WAIT.

    DATA: LS_META TYPE TY_FILES_DISP.
    READ TABLE GT_STAGING INTO DATA(LS_STG) INDEX 1.
    LS_META-FILE_NAME   = 'ZBDC_MAIL_INBOX'.
    LS_META-FILE_SIZE   = 'Unknown'.
    LS_META-ROWS_LOADED = LINES( GT_STAGING ).
    LS_META-CHANNEL     = 'GMAIL_WEBHOOK'.
    LS_META-UPLOAD_DATE = SY-DATUM.
    LS_META-UPLOAD_TIME = SY-UZEIT.
    LS_META-USERNAME    = SY-UNAME.
    LS_META-SESSION_ID  = LS_STG-SESSION_ID.
    APPEND LS_META TO GT_FILES_PREVIEW.
  ENDIF.

  MESSAGE |Webhook bridge finished. Messages processed: { LV_LOADED }.| TYPE 'S'.
ENDFORM.
*<<< END FORM LOAD_GMAIL_WEBHOOK_INBOUND

*>>> FORM LOAD_SOURCE_CONFIG - moved from Z_BDC_MASS_PO_ENTRY_F01_BUP

FORM LOAD_SOURCE_CONFIG.
  DATA: LT_CONFIG TYPE STANDARD TABLE OF ZBDC_CONFIG_BUP,
        LS_CONFIG TYPE ZBDC_CONFIG_BUP,
        LV_VAL    TYPE STRING,
        LV_TIMEOUT TYPE STRING.

  SELECT * FROM ZBDC_CONFIG_BUP INTO TABLE @LT_CONFIG.

  LOOP AT LT_CONFIG INTO LS_CONFIG.
    LV_VAL = LS_CONFIG-CONFIG_VALUE.
    CASE LS_CONFIG-CONFIG_KEY.
      WHEN 'SOURCE_TYPE'.
        CLEAR: RB_LOCAL, RB_REST, RB_GDRIVE, RB_SFTP.
        CASE LV_VAL.
          WHEN 'LOCAL'.  RB_LOCAL  = 'X'.
          WHEN 'REST' OR 'GMAIL' OR 'GMAIL_WEBHOOK'. RB_REST = 'X'.
          WHEN 'GDRIVE' OR 'GOOGLE_DRIVE'. RB_GDRIVE = 'X'.
          WHEN 'SFTP'.   RB_SFTP   = 'X'.
          WHEN OTHERS.
            MESSAGE |Invalid SOURCE_TYPE in config: { LV_VAL }. Please re-save 0200.| TYPE 'W'.
        ENDCASE.
      WHEN 'TRANSACTION'.
        "Legacy config key ignored: 0200 no longer controls TCode.
      WHEN 'FORMAT'.
        "Legacy config key ignored: 0300 parser owns file format.
      WHEN 'WEBHOOK_URL'.   TXTP_WEBHOOK_URL = LV_VAL.
      WHEN 'AUTH_TYPE'.     P_AUTH_TYPE      = LV_VAL.
      WHEN 'GDRIVE_AUTH_TYPE'.
        IF LV_VAL IS NOT INITIAL.
          P_AUTH_TYPE = LV_VAL.
        ENDIF.
      WHEN 'API_KEY'.       TXTP_API_KEY     = LV_VAL.
      WHEN 'GDRIVE_API_KEY'.
        IF LV_VAL IS NOT INITIAL.
          TXTP_API_KEY = LV_VAL.
        ENDIF.
      WHEN 'TIMEOUT'.       LV_TIMEOUT       = LV_VAL. TXTP_TIMEOUT = LV_TIMEOUT.
      WHEN 'RETRY_ENABLED'. CHKP_RETRY       = LV_VAL.
      WHEN 'SFTP_HOST'.     TXTP_SFTP_HOST   = LV_VAL.
      WHEN 'SFTP_PORT'.     TXTP_SFTP_PORT   = LV_VAL.
      WHEN 'SFTP_USER' OR 'USERNAME'. TXTP_USERNAME = LV_VAL.
      WHEN 'SFTP_PASSWORD'. TXTP_PASSWORD    = LV_VAL.
      WHEN 'GDRIVE_FOLDER' OR 'GDRIVE_URL' OR 'GDRIVE_SCRIPT_URL'.
        IF LV_VAL IS NOT INITIAL.
          TXTP_GDRIVE_URL = LV_VAL.
        ENDIF.
      WHEN 'FILE_PATH'.     TXTP_FILE_PATH   = LV_VAL.
      WHEN 'BDC_MODE'.
        CLEAR: RB_MODE_N, RB_MODE_E, RB_MODE_A.
        CASE LV_VAL.
          WHEN 'N'. RB_MODE_N = 'X'.
          WHEN 'E'. RB_MODE_E = 'X'.
          WHEN 'A'. RB_MODE_A = 'X'.
          WHEN OTHERS. RB_MODE_N = 'X'.
        ENDCASE.
      WHEN 'BDC_UPDATE'.
        CLEAR: RB_UPD_A, RB_UPD_S.
        CASE LV_VAL.
          WHEN 'A'. RB_UPD_A = 'X'.
          WHEN 'S'. RB_UPD_S = 'X'.
          WHEN OTHERS. RB_UPD_A = 'X'.
        ENDCASE.
      WHEN 'BDC_EXEC_MODE' OR 'BDC_PROCESS_MODE' OR 'BDC_EXECUTION_MODE'.
        P_BDC_MODE = LV_VAL.
      WHEN 'BATCH_SIZE'.
        TXTP_BATCH_SIZE = LV_VAL.
      WHEN 'CONN_STATUS'.
        GV_0200_LAST_STAT = LV_VAL.
      WHEN 'CONN_AT'.
        GV_0200_LAST_AT = LV_VAL.
      WHEN 'CONN_MSG'.
        GV_0200_LAST_MSG = LV_VAL.
    ENDCASE.
  ENDLOOP.

  IF P_BDC_MODE IS INITIAL.
    P_BDC_MODE = GC_MODE_CALL.
  ENDIF.

  IF TXTP_BATCH_SIZE IS INITIAL.
    TXTP_BATCH_SIZE = '100'.
  ENDIF.

  IF RB_MODE_N IS INITIAL AND RB_MODE_E IS INITIAL AND RB_MODE_A IS INITIAL.
    RB_MODE_A = 'X'.
  ENDIF.

  IF RB_UPD_A IS INITIAL AND RB_UPD_S IS INITIAL.
    RB_UPD_S = 'X'.
  ENDIF.

  "Do not force SFTP when opening 0200. The endpoint is optional and the
  "inbound source is selected by the actual ingestion action in 0300.

  PERFORM BUILD_0200_CFG_SIG CHANGING GV_0200_SAVED_SIG.
ENDFORM.
*<<< END FORM LOAD_SOURCE_CONFIG

*>>> FORM SELECT_INBOUND_CHANNEL - moved from Z_BDC_MASS_PO_ENTRY_F01_BUP


FORM SELECT_INBOUND_CHANNEL.
  "V5BX: single-select source chooser.
  "POPUP_TO_DECIDE_LIST shows Select All / Deselect All because it is a
  "multi-checkbox popup. For inbound source we need exactly one choice, so
  "use F4IF_INT_TABLE_VALUE_REQUEST with MULTIPLE_CHOICE = SPACE.
  TYPES: BEGIN OF TY_SOURCE_CHOICE,
           SOURCE_CODE TYPE C LENGTH 10,
           SOURCE_TEXT TYPE C LENGTH 60,
         END OF TY_SOURCE_CHOICE.

  DATA: LT_SOURCE   TYPE STANDARD TABLE OF TY_SOURCE_CHOICE,
        LS_SOURCE   TYPE TY_SOURCE_CHOICE,
        LT_FIELDTAB TYPE STANDARD TABLE OF DFIES,
        LS_FIELDTAB TYPE DFIES,
        LT_RETURN   TYPE STANDARD TABLE OF DDSHRETVAL,
        LS_RETURN   TYPE DDSHRETVAL,
        LV_CHOICE   TYPE C LENGTH 80.

  CLEAR LT_SOURCE.

  CLEAR LS_SOURCE.
  LS_SOURCE-SOURCE_CODE = 'LOCAL'.
  LS_SOURCE-SOURCE_TEXT = 'Local File Ingestion'.
  APPEND LS_SOURCE TO LT_SOURCE.

  CLEAR LS_SOURCE.
  LS_SOURCE-SOURCE_CODE = 'GDRIVE'.
  LS_SOURCE-SOURCE_TEXT = 'Google Drive Cloud Ingestion'.
  APPEND LS_SOURCE TO LT_SOURCE.

  CLEAR LS_SOURCE.
  LS_SOURCE-SOURCE_CODE = 'REST'.
  LS_SOURCE-SOURCE_TEXT = 'Email Inbox CSV Ingestion'.
  APPEND LS_SOURCE TO LT_SOURCE.

  CLEAR LS_SOURCE.
  LS_SOURCE-SOURCE_CODE = 'SFTP'.
  LS_SOURCE-SOURCE_TEXT = 'SFTP Server Folder Ingestion'.
  APPEND LS_SOURCE TO LT_SOURCE.

  CLEAR LS_FIELDTAB.
  LS_FIELDTAB-FIELDNAME = 'SOURCE_CODE'.
  LS_FIELDTAB-REPTEXT   = 'Source Code'.
  LS_FIELDTAB-SCRTEXT_L = 'Source Code'.
  LS_FIELDTAB-FIELDTEXT = 'Source Code'.
  LS_FIELDTAB-DATATYPE  = 'CHAR'.
  LS_FIELDTAB-INTTYPE   = 'C'.
  LS_FIELDTAB-INTLEN    = 10.
  LS_FIELDTAB-OUTPUTLEN = 10.
  APPEND LS_FIELDTAB TO LT_FIELDTAB.

  CLEAR LS_FIELDTAB.
  LS_FIELDTAB-FIELDNAME = 'SOURCE_TEXT'.
  LS_FIELDTAB-REPTEXT   = 'Channel Description'.
  LS_FIELDTAB-SCRTEXT_L = 'Channel Description'.
  LS_FIELDTAB-FIELDTEXT = 'Channel Description'.
  LS_FIELDTAB-DATATYPE  = 'CHAR'.
  LS_FIELDTAB-INTTYPE   = 'C'.
  LS_FIELDTAB-INTLEN    = 60.
  LS_FIELDTAB-OUTPUTLEN = 45.
  APPEND LS_FIELDTAB TO LT_FIELDTAB.

  CALL FUNCTION 'F4IF_INT_TABLE_VALUE_REQUEST'
    EXPORTING
      RETFIELD        = 'SOURCE_CODE'
      DYNPPROG        = SY-REPID
      DYNPNR          = SY-DYNNR
      WINDOW_TITLE    = 'Browse Inbound Source'
      VALUE_ORG       = 'S'
      MULTIPLE_CHOICE = SPACE
    TABLES
      VALUE_TAB       = LT_SOURCE
      FIELD_TAB       = LT_FIELDTAB
      RETURN_TAB      = LT_RETURN
    EXCEPTIONS
      PARAMETER_ERROR = 1
      NO_VALUES_FOUND = 2
      OTHERS          = 3.

  IF SY-SUBRC <> 0.
    RETURN.
  ENDIF.

  CLEAR LV_CHOICE.
  READ TABLE LT_RETURN INTO LS_RETURN INDEX 1.
  IF SY-SUBRC = 0.
    LV_CHOICE = LS_RETURN-FIELDVAL.
  ENDIF.

  IF LV_CHOICE IS INITIAL.
    RETURN.
  ENDIF.

  TRANSLATE LV_CHOICE TO UPPER CASE.
  CONDENSE LV_CHOICE.

  IF LV_CHOICE CS 'GDRIVE' OR LV_CHOICE CS 'GOOGLE'.
    LV_CHOICE = 'GDRIVE'.
  ELSEIF LV_CHOICE CS 'LOCAL'.
    LV_CHOICE = 'LOCAL'.
  ELSEIF LV_CHOICE CS 'REST' OR LV_CHOICE CS 'EMAIL' OR LV_CHOICE CS 'MAIL'.
    LV_CHOICE = 'REST'.
  ELSEIF LV_CHOICE CS 'SFTP'.
    LV_CHOICE = 'SFTP'.
  ENDIF.

  CASE LV_CHOICE.
    WHEN 'LOCAL'.
      PERFORM BROWSE_FILE.

    WHEN 'GDRIVE'.
      "Selecting Drive is source selection only. It opens browser + token
      "flow and sets TXTP_FILE_PATH = GoogleDrive://... after user picks file.
      "No data is parsed here: size/rows must stay 0 until Upload/Ingest.
      PERFORM Z16_CLEAR_0300_AFTER_BROWSE.
      CLEAR: TXTP_FILE_PATH, TXTP_FILE_SIZE, GV_GDRIVE_FILE_ID_TEMP.
      TXTP_FILE_PATH = 'GoogleDrive://[waiting-for-file-selection]'.
      TXTP_FILE_SIZE = '0 B'.
      PERFORM Z16_SET_ROW_COUNT_FIELDS USING 0.
      PERFORM SELECT_GDRIVE_FILE_PATH.
      IF TXTP_FILE_PATH CP 'GoogleDrive://*'.
        TXTP_FILE_SIZE = '0 B'.
        PERFORM Z16_SET_ROW_COUNT_FIELDS USING 0.
        REFRESH: GT_STAGING, GT_STAGING_ALV, GT_PREVIEW_DATA.
        PERFORM Z16_RESET_0300_ALL_ALV.
      ENDIF.

    WHEN 'REST'.
      CLEAR: TXTP_FILE_PATH, TXTP_FILE_SIZE.
      PERFORM Z16_CLEAR_0300_AFTER_BROWSE.
      PERFORM SELECT_MAIL_INBOX.

    WHEN 'SFTP'.
      CLEAR: TXTP_FILE_PATH, TXTP_FILE_SIZE.
      PERFORM Z16_CLEAR_0300_AFTER_BROWSE.
      PERFORM UPLOAD_FROM_SFTP.

    WHEN OTHERS.
      MESSAGE |Unknown inbound source: { LV_CHOICE }| TYPE 'S' DISPLAY LIKE 'W'.
  ENDCASE.
ENDFORM.
*<<< END FORM SELECT_INBOUND_CHANNEL

*>>> FORM UPLOAD_FROM_SFTP - moved from Z_BDC_MASS_PO_ENTRY_F01_BUP

FORM UPLOAD_FROM_SFTP.
  CONSTANTS: LC_SRV_DIR TYPE EPS2FILNAM VALUE '/usr/sap/S40/D00/work/'.

  TYPES: BEGIN OF TY_SFTP_DISP,
           MARK      TYPE C LENGTH 1,
           FILE_NAME TYPE EPSF-EPSFILNAM,
           FILE_SIZE TYPE EPSF-EPSFILSIZ,
         END OF TY_SFTP_DISP.

  DATA: LT_DIR      TYPE STANDARD TABLE OF EPS2FILI,
        LS_DIR      TYPE EPS2FILI,
        LV_DIR      TYPE EPS2FILNAM,
        LT_DISP     TYPE STANDARD TABLE OF TY_SFTP_DISP,
        LS_DISP     TYPE TY_SFTP_DISP,
        LT_FIELDCAT TYPE SLIS_T_FIELDCAT_ALV,
        LS_FIELDCAT TYPE SLIS_FIELDCAT_ALV,
        LS_SELFIELD TYPE SLIS_SELFIELD,
        LV_EXIT     TYPE C,
        LV_CNT      TYPE I.

  LV_DIR = LC_SRV_DIR.
  CALL FUNCTION 'EPS2_GET_DIRECTORY_LISTING'
    EXPORTING
      IV_DIR_NAME            = LV_DIR
    TABLES
      DIR_LIST               = LT_DIR
    EXCEPTIONS
      INVALID_EPS_SUBDIR     = 1
      SAPGPARAM_FAILED       = 2
      BUILD_DIRECTORY_FAILED = 3
      NO_AUTHORIZATION       = 4
      READ_DIRECTORY_FAILED  = 5
      TOO_MANY_READ_ERRORS   = 6
      EMPTY_DIRECTORY_LIST   = 7
      OTHERS                 = 8.

  IF SY-SUBRC <> 0.
    MESSAGE 'Khong doc duoc thu muc SFTP tren server.' TYPE 'E'. RETURN.
  ENDIF.

  LOOP AT LT_DIR INTO LS_DIR.
    IF LS_DIR-NAME NP '*.csv' AND LS_DIR-NAME NP '*.CSV'.
      CONTINUE.
    ENDIF.
    CLEAR LS_DISP.
    LS_DISP-FILE_NAME = LS_DIR-NAME.
    LS_DISP-FILE_SIZE = LS_DIR-SIZE.
    APPEND LS_DISP TO LT_DISP.
  ENDLOOP.

  IF LT_DISP IS INITIAL.
    MESSAGE 'Khong co file CSV nao trong folder SFTP server.' TYPE 'S'.
    RETURN.
  ENDIF.

  DEFINE ADD_FCAT.
    CLEAR LS_FIELDCAT.
    LS_FIELDCAT-FIELDNAME = &1.
    LS_FIELDCAT-SELTEXT_L = &2.
    LS_FIELDCAT-OUTPUTLEN = &3.
    APPEND LS_FIELDCAT TO LT_FIELDCAT.
  END-OF-DEFINITION.

  ADD_FCAT 'FILE_NAME' 'Ten file (tu SFTP server)' 50.
  ADD_FCAT 'FILE_SIZE' 'Kich thuoc (bytes)'        18.

  CALL FUNCTION 'REUSE_ALV_POPUP_TO_SELECT'
    EXPORTING
      I_TITLE               = 'Chon file CSV tu SFTP Server Folder'
      I_SELECTION           = 'X'
      I_ZEBRA               = 'X'
      I_CHECKBOX_FIELDNAME  = 'MARK'
      I_TABNAME             = 'LT_DISP'
      IT_FIELDCAT           = LT_FIELDCAT
      I_SCREEN_START_COLUMN = 5
      I_SCREEN_START_LINE   = 3
      I_SCREEN_END_COLUMN   = 90
      I_SCREEN_END_LINE     = 20
    IMPORTING
      ES_SELFIELD           = LS_SELFIELD
      E_EXIT                = LV_EXIT
    TABLES
      T_OUTTAB              = LT_DISP
    EXCEPTIONS
      PROGRAM_ERROR         = 1
      OTHERS                = 2.

  IF LV_EXIT = 'X' OR SY-SUBRC <> 0.
    MESSAGE 'Da huy chon file.' TYPE 'S'. RETURN.
  ENDIF.

  CLEAR TXTP_FILE_PATH.
  LV_CNT = 0.
  LOOP AT LT_DISP INTO LS_DISP WHERE MARK = 'X'.
    IF TXTP_FILE_PATH IS INITIAL.
      TXTP_FILE_PATH = 'SFTP://' && LS_DISP-FILE_NAME.
    ELSE.
      TXTP_FILE_PATH = TXTP_FILE_PATH && ';' && LS_DISP-FILE_NAME.
    ENDIF.
    LV_CNT = LV_CNT + 1.
  ENDLOOP.

  IF LV_CNT = 0.
    MESSAGE 'Chua tick file nao.' TYPE 'W'. RETURN.
  ENDIF.
  MESSAGE |Da chon { LV_CNT } file SFTP. Bam Upload & Ingest de nap.| TYPE 'S'.
ENDFORM.
*<<< END FORM UPLOAD_FROM_SFTP

*>>> FORM LOAD_FROM_SFTP_SELECTED - moved from Z_BDC_MASS_PO_ENTRY_F01_BUP

FORM LOAD_FROM_SFTP_SELECTED.
  CONSTANTS: LC_SRV_DIR TYPE STRING VALUE '/usr/sap/S40/D00/work/'.

  DATA: LT_FILES   TYPE STANDARD TABLE OF STRING,
        LV_NAME    TYPE STRING,
        LV_PATH    TYPE STRING,
        LV_FULL    TYPE STRING,
        LV_CONTENT TYPE STRING,
        LT_RAW     TYPE STRING_TABLE,
        LV_XSTR    TYPE XSTRING,
        LV_XBUF    TYPE XSTRING,
        LV_XLEN    TYPE I,
        LV_SIZE    TYPE I,
        LO_CONV    TYPE REF TO CL_ABAP_CONV_IN_CE,
        LV_OK      TYPE I,
        LV_SKIPPED TYPE I,
        LV_BEFORE  TYPE I,
        LV_AFTER   TYPE I,
        LV_FIRST_NEW_INDEX TYPE I,
        LS_FIRST_NEW TYPE ZBDC_STAGING_BUP,
        LV_ROWCOUNT TYPE I,
        LV_INDEX   TYPE I,
        LV_SESSION_ID TYPE ZBDC_STAGING_BUP-SESSION_ID,
        LS_SFTP_META TYPE TY_FILES_DISP.

  LV_PATH = TXTP_FILE_PATH.
  REPLACE FIRST OCCURRENCE OF 'SFTP://' IN LV_PATH WITH ''.
  SPLIT LV_PATH AT ';' INTO TABLE LT_FILES.
  DELETE LT_FILES WHERE TABLE_LINE IS INITIAL.

  IF LT_FILES IS INITIAL.
    MESSAGE 'Chua chon file SFTP nao.' TYPE 'W'. RETURN.
  ENDIF.

  "SFTP files are already pulled to the SAP work directory by the SFTP job/SM69 flow.
  "Screen 0300 only previews/ingests selected server-side CSV files.
  "Do NOT delete the server file here: the SFTP guide keeps files for audit/re-browse.
  REFRESH GT_STAGING.
  PERFORM z16_start_ingest_batch.
  CLEAR: LV_OK, LV_SKIPPED, LV_INDEX.

  LOOP AT LT_FILES INTO LV_NAME.
    CONCATENATE LC_SRV_DIR LV_NAME INTO LV_FULL.

    CLEAR: LV_XSTR, LV_CONTENT.
    OPEN DATASET LV_FULL FOR INPUT IN BINARY MODE.
    IF SY-SUBRC <> 0.
      LV_SKIPPED = LV_SKIPPED + 1.
      CONTINUE.
    ENDIF.

    DO.
      CLEAR LV_XBUF.
      READ DATASET LV_FULL INTO LV_XBUF MAXIMUM LENGTH 8192 ACTUAL LENGTH LV_XLEN.
      IF LV_XLEN > 0.
        CONCATENATE LV_XSTR LV_XBUF(LV_XLEN) INTO LV_XSTR IN BYTE MODE.
      ENDIF.
      IF SY-SUBRC <> 0. EXIT. ENDIF.
    ENDDO.
    CLOSE DATASET LV_FULL.

    IF LV_XSTR IS INITIAL.
      LV_SKIPPED = LV_SKIPPED + 1.
      CONTINUE.
    ENDIF.

    LV_SIZE = XSTRLEN( LV_XSTR ).
    PERFORM z23_format_file_size USING LV_SIZE CHANGING TXTP_FILE_SIZE.

    IF LV_NAME CP '*.xlsx' OR LV_NAME CP '*.XLSX'.
      PERFORM z16_ingest_xlsx_xstr USING LV_FULL 'SFTP' LV_XSTR
        CHANGING LV_INDEX LV_ROWCOUNT LV_OK LV_SKIPPED.
      CONTINUE.
    ENDIF.

    TRY.
        LO_CONV = CL_ABAP_CONV_IN_CE=>CREATE(
                    ENCODING = 'UTF-8' REPLACEMENT = '#' INPUT = LV_XSTR ).
        LO_CONV->READ( IMPORTING DATA = LV_CONTENT ).
      CATCH CX_ROOT.
        TRY.
            LO_CONV = CL_ABAP_CONV_IN_CE=>CREATE(
                        ENCODING = '1100' REPLACEMENT = '#' INPUT = LV_XSTR ).
            LO_CONV->READ( IMPORTING DATA = LV_CONTENT ).
          CATCH CX_ROOT.
            LV_SKIPPED = LV_SKIPPED + 1.
            CONTINUE.
        ENDTRY.
    ENDTRY.

    IF LV_CONTENT IS INITIAL.
      LV_SKIPPED = LV_SKIPPED + 1.
      CONTINUE.
    ENDIF.

    REPLACE ALL OCCURRENCES OF CL_ABAP_CHAR_UTILITIES=>CR_LF
            IN LV_CONTENT WITH CL_ABAP_CHAR_UTILITIES=>NEWLINE.
    REFRESH LT_RAW.
    SPLIT LV_CONTENT AT CL_ABAP_CHAR_UTILITIES=>NEWLINE INTO TABLE LT_RAW.

    LV_INDEX = LV_INDEX + 1.
    PERFORM z16_make_batch_session USING LV_INDEX CHANGING LV_SESSION_ID.
    GV_FORCED_SESSION_ID = LV_SESSION_ID.
    gv_current_file_name  = LV_FULL.
    gv_current_sheet_name = 'DATA'.
    gv_current_unit_src   = 'SFTP'.

    LV_BEFORE = LINES( GT_STAGING ).
    PERFORM PROCESS_CSV_ROWS USING LT_RAW.
    LV_AFTER = LINES( GT_STAGING ).

    IF LV_AFTER > LV_BEFORE.
      LV_OK = LV_OK + 1.
      LV_FIRST_NEW_INDEX = LV_BEFORE + 1.
      READ TABLE GT_STAGING INTO LS_FIRST_NEW INDEX LV_FIRST_NEW_INDEX.
      IF SY-SUBRC = 0.
        DATA lv_sftp_unit TYPE string.
        PERFORM z16_compose_unit_name USING LV_FULL 'DATA' CHANGING lv_sftp_unit.
        PERFORM SAVE_INGESTION_SOURCE_LOG USING LS_FIRST_NEW-SESSION_ID 'SFTP' lv_sftp_unit.
        PERFORM UPDATE_SESSION_SUMMARY USING LS_FIRST_NEW-SESSION_ID.
        PERFORM z16_register_current_session USING LS_FIRST_NEW-SESSION_ID.

        CLEAR LS_SFTP_META.
        LS_SFTP_META-FILE_NAME   = lv_sftp_unit.
        PERFORM z16_split_unit_name USING lv_sftp_unit
          CHANGING LS_SFTP_META-FILE_TITLE LS_SFTP_META-SHEET_NAME.
        LS_SFTP_META-FILE_SIZE   = TXTP_FILE_SIZE.
        LS_SFTP_META-ROWS_LOADED = LV_AFTER - LV_BEFORE.
        LS_SFTP_META-CHANNEL     = 'SFTP_INGESTION'.
        LS_SFTP_META-UPLOAD_DATE = SY-DATUM.
        LS_SFTP_META-UPLOAD_TIME = SY-UZEIT.
        LS_SFTP_META-USERNAME    = SY-UNAME.
        LS_SFTP_META-SESSION_ID  = LS_FIRST_NEW-SESSION_ID.
        LS_SFTP_META-TX_CODE     = P_TRANSACTION.
        APPEND LS_SFTP_META TO GT_FILES_PREVIEW.
      ENDIF.
    ELSE.
      LV_SKIPPED = LV_SKIPPED + 1.
    ENDIF.
  ENDLOOP.

  CLEAR GV_FORCED_SESSION_ID.
  PERFORM z16_finish_ingest_batch.

  IF GT_STAGING IS NOT INITIAL.
    READ TABLE GT_STAGING INTO LS_FIRST_NEW INDEX 1.
    LV_ROWCOUNT = LINES( GT_STAGING ).
    PERFORM z16_set_row_count_fields USING LV_ROWCOUNT.

    COMMIT WORK AND WAIT.

    IF LV_SKIPPED > 0.
      MESSAGE |SFTP: nap { LINES( GT_STAGING ) } dong tu { LV_OK } file. Canh bao: { LV_SKIPPED } file bi bo qua.| TYPE 'W'.
    ELSE.
      MESSAGE |SFTP: nap { LINES( GT_STAGING ) } dong tu { LV_OK } file.| TYPE 'S'.
    ENDIF.
  ELSE.
    MESSAGE |Khong nap duoc du lieu SFTP. { LV_SKIPPED }/{ LINES( LT_FILES ) } file bi bo qua.| TYPE 'E'.
  ENDIF.
ENDFORM.
*<<< END FORM LOAD_FROM_SFTP_SELECTED

*>>> FORM save_ingestion_source_log - moved from Z_BDC_MASS_PO_ENTRY_F01_BUP
FORM save_ingestion_source_log
  USING iv_session_id TYPE zbdc_result_bup-session_id
        iv_source     TYPE char20
        iv_file       TYPE csequence.

  DATA: lv_file_str TYPE string,
        ls_res      TYPE zbdc_result_bup,
        ls_sess_src TYPE zbdc_session_bup,
        ls_file_lg  TYPE zbdc_file_lg_bup,
        lv_ts       TYPE tzntstmps,
        lv_msg      TYPE zbdc_result_bup-message,
        lv_hash     TYPE zbdc_file_lg_bup-file_hash,
        lv_rows     TYPE zbdc_file_lg_bup-row_count,
        lv_p_at     TYPE zbdc_file_lg_bup-processed_at.

  IF iv_session_id IS INITIAL OR iv_source IS INITIAL.
    RETURN.
  ENDIF.

  lv_file_str = iv_file.
  GET TIME STAMP FIELD lv_ts.

  CONCATENATE 'INBOUND_SOURCE=' iv_source ';SIZE=' txtp_file_size ';FILE=' lv_file_str ';TCODE=' p_transaction ';USER=' sy-uname INTO lv_msg.

  CLEAR ls_res.
  ls_res-session_id  = iv_session_id.
  ls_res-row_index   = 0.
  ls_res-record_key  = '__SOURCE__'.
  ls_res-tcode       = p_transaction.
  ls_res-msg_type    = 'I'.
  ls_res-message     = lv_msg.
  ls_res-exec_status = 'INFO'.
  ls_res-created_at  = lv_ts.
  ls_res-step        = 0.

  INSERT zbdc_result_bup FROM ls_res.
  IF sy-subrc <> 0.
    MODIFY zbdc_result_bup FROM ls_res.
  ENDIF.

  "File history source of truth for Screen 0302 Preview Files.
  "ZBDC_FILE_LG_BUP structure in this system:
  "FILE_HASH, FILE_NAME, SOURCE, ROW_COUNT, SESSION_ID, PROCESSED_AT, STATUS, ERROR_MSG.
  SELECT COUNT(*)
    FROM zbdc_staging_bup
    INTO @lv_rows
    WHERE session_id = @iv_session_id.

  CONCATENATE sy-datum sy-uzeit INTO lv_p_at.
  CONCATENATE iv_session_id sy-datum sy-uzeit INTO lv_hash.
  IF strlen( lv_hash ) > 32.
    lv_hash = lv_hash+0(32).
  ENDIF.

  CLEAR ls_file_lg.
  ls_file_lg-file_hash    = lv_hash.
  ls_file_lg-file_name    = lv_file_str.
  ls_file_lg-source       = iv_source.
  ls_file_lg-row_count    = lv_rows.
  ls_file_lg-session_id   = iv_session_id.
  ls_file_lg-processed_at = lv_p_at.
  ls_file_lg-status       = 'IMPORTED'.
  CLEAR ls_file_lg-error_msg.

  INSERT zbdc_file_lg_bup FROM ls_file_lg.
  IF sy-subrc <> 0.
    MODIFY zbdc_file_lg_bup FROM ls_file_lg.
  ENDIF.

  "Strict-real creator evidence: ZBDC_RESULT_BUP has no CREATED_BY field in
  "this system, so persist the real upload user in the session summary table.
  CLEAR ls_sess_src.
  SELECT SINGLE *
    FROM zbdc_session_bup
    INTO @ls_sess_src
    WHERE session_id = @iv_session_id.

  IF sy-subrc <> 0.
    CLEAR ls_sess_src.
    ls_sess_src-session_id = iv_session_id.
    ls_sess_src-start_time = lv_ts.
  ELSEIF ls_sess_src-start_time IS INITIAL.
    ls_sess_src-start_time = lv_ts.
  ENDIF.

  IF ls_sess_src-created_by IS INITIAL OR ls_sess_src-created_by = 'UNKNOWN'.
    ls_sess_src-created_by = sy-uname.
  ENDIF.

  MODIFY zbdc_session_bup FROM ls_sess_src.
  COMMIT WORK.

ENDFORM.

*&---------------------------------------------------------------------*
*& update_session_summary
*& Rebuild ZBDC_SESSION_BUP from real staging + result logs.
*& This makes Screen 0100/0600 KPI and SE16N proof complete.
*&---------------------------------------------------------------------*
*<<< END FORM save_ingestion_source_log

*>>> FORM z16_clear_0300_after_browse - moved from Z_BDC_MASS_PO_ENTRY_F01_BUP

FORM z16_clear_0300_after_browse.
  "Selecting a new source/file means the old preview is no longer current.
  "This is a browse-only reset: do not delete DB history, only clear the
  "current in-memory upload preview and all counters on screen 0300.
  REFRESH: gt_staging, gt_staging_alv, gt_errors, gt_preview_data, gt_current_sessions.
  CLEAR: txtp_row_count, txtp_row, txtp_rows, txtp_loaded, txtp_rows_loaded,
         txtp_loaded_rows, txtgv_row_count, txtgv_rows, txtgv_loaded,
         txtgv_total_rows, txtgv_tot_rows,
         gv_current_batch_prefix, gv_ingest_batch_prefix, gv_forced_session_id,
         gv_current_batch_count, gv_current_file_name, gv_current_sheet_name,
         gv_current_unit_src.
  txtp_file_size = '0 B'.
  txtp_file_size = '0 B'.
  PERFORM z16_set_row_count_fields USING 0.
  g_sub_dynpro = '0301'.
  ts_preview-activetab = 'TAB_PREVIEW'.

  "If the 0301 ALV already exists, refresh it immediately so a new Browse
  "does not keep showing rows from the previous upload until the next screen.
  REFRESH gt_preview_data.
  IF go_alv_0301 IS BOUND.
    DATA ls_stable_browse TYPE lvc_s_stbl.
    ls_stable_browse-row = abap_true.
    ls_stable_browse-col = abap_true.
    CALL METHOD go_alv_0301->refresh_table_display
      EXPORTING
        is_stable      = ls_stable_browse
        i_soft_refresh = abap_false.
  ENDIF.

  "Force SALV 0301 to be rebuilt empty. RESET_0300_ALV intentionally keeps
  "0301 alive during normal upload refresh, but Browse needs a hard reset
  "so old rows are not visually reused.
  PERFORM z16_reset_0300_all_alv.
ENDFORM.
*<<< END FORM z16_clear_0300_after_browse

*>>> FORM NEW_UPLOAD_FROM_0100 - moved from Z_BDC_MASS_PO_ENTRY_F01_BUP

FORM NEW_UPLOAD_FROM_0100.
  "Start a clean ingestion flow without deleting persisted DB data.
  REFRESH: GT_STAGING, GT_STAGING_ALV, GT_ERRORS, GT_FILES_PREVIEW, GT_EXEC_DISP.
  CLEAR: TXTP_FILE_PATH, TXTP_FILE_SIZE, TXTP_ROW_COUNT, TXTP_ROW,
         TXTP_ROWS, TXTP_LOADED, TXTP_ROWS_LOADED, TXTP_LOADED_ROWS,
         TXTGv_ROW_COUNT, TXTGv_ROWS, TXTGv_LOADED, TXTGv_TOTAL_ROWS,
         TXTGv_TOT_ROWS,
         G_EXEC_CURR, G_EXEC_SUCCESS, G_EXEC_ERROR, G_STOP_FLAG,
         GV_EXEC_PROGRESS, GV_EXEC_HEADER_TXT.

  G_SUB_DYNPRO = '0301'.
  TS_PREVIEW-ACTIVETAB = 'TAB_PREVIEW'.
  PERFORM RESET_0300_ALV.
  CALL SCREEN 0300.
ENDFORM.
*<<< END FORM NEW_UPLOAD_FROM_0100

*>>> FORM VIEW_SESSION_FROM_0100 - moved from Z_BDC_MASS_PO_ENTRY_F01_BUP

FORM VIEW_SESSION_FROM_0100.
  DATA: LV_SESSION_ID TYPE ZBDC_RESULT_BUP-SESSION_ID,
        LV_COUNT      TYPE I.

  PERFORM GET_0100_SELECTED_SESSION CHANGING LV_SESSION_ID.
  IF LV_SESSION_ID IS INITIAL.
    MESSAGE 'Chon 1 session tren dashboard truoc khi View Session.' TYPE 'W'.
    RETURN.
  ENDIF.

  PERFORM LOAD_STAGING_BY_SESSION USING LV_SESSION_ID CHANGING LV_COUNT.
  IF LV_COUNT <= 0.
    MESSAGE |Session { LV_SESSION_ID } khong co staging data de xem.| TYPE 'W'.
    RETURN.
  ENDIF.

  PERFORM OPEN_0400_FOR_CURRENT_STAGING.
ENDFORM.
*<<< END FORM VIEW_SESSION_FROM_0100
