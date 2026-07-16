*&---------------------------------------------------------------------*
*& Include          ZBDC_MPE_M1_PARSE_BUP
*& Purpose          M1 Parse/Template/Preview - CSV/XLSX/header/file preview
*& Source split     FIX16 V5BR - logic moved from F01
*&---------------------------------------------------------------------*

*>>> FORM z16_get_file_title_by_session - moved from Z_BDC_MASS_PO_ENTRY_F01_BUP

FORM z16_get_file_title_by_session USING iv_session_id TYPE zbdc_staging_bup-session_id
                                   CHANGING cv_title TYPE csequence.
  DATA: lv_file TYPE string,
        lv_dummy TYPE string,
        lt_part TYPE STANDARD TABLE OF string,
        lv_cnt  TYPE i.
  CLEAR cv_title.
  IF iv_session_id IS INITIAL.
    RETURN.
  ENDIF.
  SELECT SINGLE file_name
    FROM zbdc_file_lg_bup
    WHERE session_id = @iv_session_id
    INTO @lv_file.
  IF lv_file IS INITIAL.
    cv_title = iv_session_id.
    RETURN.
  ENDIF.
  PERFORM z16_extract_file_title USING lv_file CHANGING cv_title.
ENDFORM.
*<<< END FORM z16_get_file_title_by_session

*>>> FORM z16_extract_file_title - moved from Z_BDC_MASS_PO_ENTRY_F01_BUP
FORM z16_extract_file_title USING iv_file TYPE csequence
                            CHANGING cv_title TYPE csequence.
  DATA: lv_file TYPE string,
        lv_dummy TYPE string,
        lt_part TYPE STANDARD TABLE OF string,
        lv_cnt  TYPE i.
  CLEAR cv_title.
  lv_file = iv_file.
  IF lv_file CS '|SHEET='.
    SPLIT lv_file AT '|SHEET=' INTO lv_file lv_dummy.
  ENDIF.
  REPLACE ALL OCCURRENCES OF '\' IN lv_file WITH '/'.
  SPLIT lv_file AT '/' INTO TABLE lt_part.
  DESCRIBE TABLE lt_part LINES lv_cnt.
  IF lv_cnt > 0.
    READ TABLE lt_part INTO lv_file INDEX lv_cnt.
  ENDIF.
  IF lv_file IS INITIAL.
    lv_file = iv_file.
  ENDIF.
  cv_title = lv_file.
ENDFORM.
*<<< END FORM z16_extract_file_title

*>>> FORM z16_compose_unit_name - moved from Z_BDC_MASS_PO_ENTRY_F01_BUP

FORM z16_compose_unit_name USING iv_file  TYPE csequence
                                  iv_sheet TYPE csequence
                            CHANGING cv_name TYPE string.
  DATA: lv_file  TYPE string,
        lv_sheet TYPE string.
  lv_file  = iv_file.
  lv_sheet = iv_sheet.
  CONDENSE lv_sheet.
  IF lv_sheet IS INITIAL.
    lv_sheet = 'DATA'.
  ENDIF.
  cv_name = lv_file && '|SHEET=' && lv_sheet.
ENDFORM.
*<<< END FORM z16_compose_unit_name

*>>> FORM z16_split_unit_name - moved from Z_BDC_MASS_PO_ENTRY_F01_BUP

FORM z16_split_unit_name USING iv_name TYPE csequence
                         CHANGING cv_file_title TYPE csequence
                                  cv_sheet_name TYPE csequence.
  DATA: lv_file  TYPE string,
        lv_sheet TYPE string,
        lv_dummy TYPE string.
  CLEAR: cv_file_title, cv_sheet_name.
  lv_file = iv_name.
  IF lv_file CS '|SHEET='.
    SPLIT lv_file AT '|SHEET=' INTO lv_file lv_sheet.
  ENDIF.
  IF lv_sheet IS INITIAL.
    lv_sheet = 'DATA'.
  ENDIF.
  PERFORM z16_extract_file_title USING lv_file CHANGING cv_file_title.
  cv_sheet_name = lv_sheet.
ENDFORM.
*<<< END FORM z16_split_unit_name

*>>> FORM z16_is_skip_sheet - moved from Z_BDC_MASS_PO_ENTRY_F01_BUP

FORM z16_is_skip_sheet USING iv_sheet TYPE csequence
                       CHANGING cv_skip TYPE abap_bool
                                cv_reason TYPE string.
  DATA lv_sheet TYPE string.
  CLEAR: cv_skip, cv_reason.
  lv_sheet = iv_sheet.
  TRANSLATE lv_sheet TO UPPER CASE.
  CONDENSE lv_sheet NO-GAPS.
  IF lv_sheet CS 'README' OR lv_sheet CS 'INSTRUCTION' OR lv_sheet CS 'GUIDE'
     OR lv_sheet CS 'FIELDGUIDE' OR lv_sheet CS 'CONFIG' OR lv_sheet CS 'MAPPING'
     OR lv_sheet CS 'RULE' OR lv_sheet CS 'NOTE'.
    cv_skip = abap_true.
    cv_reason = 'Instruction/config sheet - skipped by design'.
  ENDIF.
ENDFORM.
*<<< END FORM z16_is_skip_sheet

*>>> FORM z16_resolve_unit_tcode - moved from Z_BDC_MASS_PO_ENTRY_F01_BUP

FORM z16_resolve_unit_tcode USING iv_sheet  TYPE csequence
                                  iv_header TYPE string
                            CHANGING cv_tcode TYPE char20.
  DATA: lv_sheet  TYPE string,
        lv_header TYPE string.
  lv_sheet  = iv_sheet.
  lv_header = iv_header.
  TRANSLATE lv_sheet TO UPPER CASE.
  TRANSLATE lv_header TO UPPER CASE.
  CONDENSE lv_sheet NO-GAPS.
  CONDENSE lv_header NO-GAPS.
  IF lv_sheet CS 'MIGO' OR lv_sheet CS 'GR' OR lv_sheet CS 'GOODSRECEIPT'
     OR lv_header CS 'MIGO_KEY' OR lv_header CS 'PO_NUMBER'.
    cv_tcode = 'MIGO'.
  ELSEIF lv_sheet CS 'ME21N' OR lv_sheet CS 'PO' OR lv_sheet CS 'PURCHASEORDER'
     OR lv_header CS 'PO_KEY' OR lv_header CS 'LIFNR'.
    cv_tcode = 'ME21N'.
  ELSEIF p_transaction IS NOT INITIAL.
    cv_tcode = p_transaction.
  ELSE.
    cv_tcode = 'ME21N'.
  ENDIF.
ENDFORM.
*<<< END FORM z16_resolve_unit_tcode

*>>> FORM z16_save_skipped_unit - moved from Z_BDC_MASS_PO_ENTRY_F01_BUP

FORM z16_save_skipped_unit USING iv_session_id TYPE zbdc_staging_bup-session_id
                                  iv_source     TYPE char20
                                  iv_file       TYPE string
                                  iv_reason     TYPE string.
  DATA: ls_file_lg TYPE zbdc_file_lg_bup,
        ls_res     TYPE zbdc_result_bup,
        lv_ts      TYPE tzntstmps,
        lv_p_at    TYPE zbdc_file_lg_bup-processed_at,
        lv_hash    TYPE zbdc_file_lg_bup-file_hash.
  IF iv_session_id IS INITIAL.
    RETURN.
  ENDIF.
  GET TIME STAMP FIELD lv_ts.
  CONCATENATE sy-datum sy-uzeit INTO lv_p_at.
  CONCATENATE iv_session_id sy-datum sy-uzeit INTO lv_hash.
  IF strlen( lv_hash ) > 32.
    lv_hash = lv_hash+0(32).
  ENDIF.

  CLEAR ls_file_lg.
  ls_file_lg-file_hash    = lv_hash.
  ls_file_lg-file_name    = iv_file.
  ls_file_lg-source       = iv_source.
  ls_file_lg-row_count    = 0.
  ls_file_lg-session_id   = iv_session_id.
  ls_file_lg-processed_at = lv_p_at.
  ls_file_lg-status       = 'SKIPPED'.
  ls_file_lg-error_msg    = iv_reason.
  INSERT zbdc_file_lg_bup FROM ls_file_lg.
  IF sy-subrc <> 0.
    MODIFY zbdc_file_lg_bup FROM ls_file_lg.
  ENDIF.

  CLEAR ls_res.
  ls_res-session_id  = iv_session_id.
  ls_res-row_index   = 0.
  ls_res-record_key  = '__SOURCE__'.
  ls_res-tcode       = p_transaction.
  ls_res-msg_type    = 'W'.
  ls_res-message     = |INBOUND_SOURCE={ iv_source };FILE={ iv_file };SKIPPED={ iv_reason };USER={ sy-uname }|.
  ls_res-exec_status = 'SKIPPED'.
  ls_res-created_at  = lv_ts.
  ls_res-step        = 0.
  INSERT zbdc_result_bup FROM ls_res.
  IF sy-subrc <> 0.
    MODIFY zbdc_result_bup FROM ls_res.
  ENDIF.
ENDFORM.
*<<< END FORM z16_save_skipped_unit

*>>> FORM z16_sheet_to_raw - moved from Z_BDC_MASS_PO_ENTRY_F01_BUP

FORM z16_sheet_to_raw USING ir_tab TYPE REF TO data
                       CHANGING ct_raw TYPE string_table.
  FIELD-SYMBOLS: <lt_tab> TYPE STANDARD TABLE,
                 <ls_row> TYPE any,
                 <lv_cell> TYPE any.
  DATA: lv_line TYPE string,
        lv_cell TYPE string,
        lv_idx  TYPE i.
  REFRESH ct_raw.
  ASSIGN ir_tab->* TO <lt_tab>.
  IF sy-subrc <> 0.
    RETURN.
  ENDIF.
  LOOP AT <lt_tab> ASSIGNING <ls_row>.
    CLEAR lv_line.
    DO 200 TIMES.
      lv_idx = sy-index.
      ASSIGN COMPONENT lv_idx OF STRUCTURE <ls_row> TO <lv_cell>.
      IF sy-subrc <> 0.
        EXIT.
      ENDIF.
      lv_cell = <lv_cell>.
      REPLACE ALL OCCURRENCES OF '"' IN lv_cell WITH '""'.
      IF lv_idx = 1.
        lv_line = '"' && lv_cell && '"'.
      ELSE.
        lv_line = lv_line && ',"' && lv_cell && '"'.
      ENDIF.
    ENDDO.
    IF lv_line IS NOT INITIAL.
      APPEND lv_line TO ct_raw.
    ENDIF.
  ENDLOOP.
ENDFORM.
*<<< END FORM z16_sheet_to_raw

*>>> FORM z16_ingest_xlsx_xstr - moved from Z_BDC_MASS_PO_ENTRY_F01_BUP

FORM z16_ingest_xlsx_xstr USING iv_file TYPE string
                                 iv_source TYPE char20
                                 iv_xstr TYPE xstring
                           CHANGING cv_unit_idx TYPE i
                                    cv_loaded TYPE i
                                    cv_ok TYPE i
                                    cv_bad TYPE i.
  DATA: lo_excel    TYPE REF TO cl_fdt_xl_spreadsheet,
        lt_sheets   TYPE STANDARD TABLE OF string,
        lv_sheet    TYPE string,
        lr_data     TYPE REF TO data,
        lt_raw      TYPE string_table,
        lv_before   TYPE i,
        lv_after    TYPE i,
        lv_session  TYPE zbdc_staging_bup-session_id,
        lv_unit     TYPE string,
        lv_skip     TYPE abap_bool,
        lv_reason   TYPE string,
        ls_meta     TYPE ty_files_disp,
        lv_title    TYPE char80,
        lv_sheet_c  TYPE char40,
        lv_bytes    TYPE i,
        lv_size_txt TYPE char20.

  IF iv_xstr IS INITIAL.
    cv_bad = cv_bad + 1.
    RETURN.
  ENDIF.

  lv_bytes = xstrlen( iv_xstr ).
  PERFORM z23_format_file_size USING lv_bytes CHANGING lv_size_txt.
  txtp_file_size = lv_size_txt.

  TRY.
      CREATE OBJECT lo_excel
        EXPORTING
          document_name = iv_file
          xdocument     = iv_xstr.
      lo_excel->if_fdt_doc_spreadsheet~get_worksheet_names(
        IMPORTING worksheet_names = lt_sheets ).
    CATCH cx_root INTO DATA(lx_xlsx).
      cv_bad = cv_bad + 1.
      MESSAGE |Cannot parse Excel workbook { iv_file }: { lx_xlsx->get_text( ) }| TYPE 'S' DISPLAY LIKE 'W'.
      RETURN.
  ENDTRY.

  IF lt_sheets IS INITIAL.
    cv_bad = cv_bad + 1.
    RETURN.
  ENDIF.

  LOOP AT lt_sheets INTO lv_sheet.
    CLEAR: lv_skip, lv_reason, lv_unit.
    cv_unit_idx = cv_unit_idx + 1.
    PERFORM z16_make_batch_session USING cv_unit_idx CHANGING lv_session.
    PERFORM z16_compose_unit_name USING iv_file lv_sheet CHANGING lv_unit.
    PERFORM z16_is_skip_sheet USING lv_sheet CHANGING lv_skip lv_reason.
    IF lv_skip = abap_true.
      PERFORM z16_save_skipped_unit USING lv_session iv_source lv_unit lv_reason.
      cv_bad = cv_bad + 1.
      CONTINUE.
    ENDIF.

    TRY.
        lr_data = lo_excel->if_fdt_doc_spreadsheet~get_itab_from_worksheet( lv_sheet ).
      CATCH cx_root INTO DATA(lx_sheet).
        lv_reason = lx_sheet->get_text( ).
        PERFORM z16_save_skipped_unit USING lv_session iv_source lv_unit lv_reason.
        cv_bad = cv_bad + 1.
        CONTINUE.
    ENDTRY.

    PERFORM z16_sheet_to_raw USING lr_data CHANGING lt_raw.
    DELETE lt_raw WHERE table_line IS INITIAL.
    IF lines( lt_raw ) <= 1.
      PERFORM z16_save_skipped_unit USING lv_session iv_source lv_unit 'Empty sheet / no data rows'.
      cv_bad = cv_bad + 1.
      CONTINUE.
    ENDIF.

    gv_forced_session_id    = lv_session.
    gv_current_file_name    = iv_file.
    gv_current_sheet_name   = lv_sheet.
    gv_current_unit_src     = iv_source.
    lv_before = lines( gt_staging ).
    PERFORM process_csv_rows USING lt_raw.
    lv_after = lines( gt_staging ).
    CLEAR: gv_forced_session_id, gv_current_file_name, gv_current_sheet_name, gv_current_unit_src.

    IF lv_after > lv_before.
      cv_ok     = cv_ok + 1.
      cv_loaded = cv_loaded + ( lv_after - lv_before ).
      MODIFY zbdc_staging_bup FROM TABLE gt_staging.
      PERFORM save_ingestion_source_log USING lv_session iv_source lv_unit.
      PERFORM update_session_summary USING lv_session.
      PERFORM z16_register_current_session USING lv_session.
      CLEAR ls_meta.
      PERFORM z16_split_unit_name USING lv_unit CHANGING lv_title lv_sheet_c.
      ls_meta-file_name   = lv_unit.
      ls_meta-file_title  = lv_title.
      ls_meta-sheet_name  = lv_sheet_c.
      ls_meta-file_size   = lv_size_txt.
      ls_meta-rows_loaded = lv_after - lv_before.
      ls_meta-channel     = iv_source.
      ls_meta-upload_date = sy-datum.
      ls_meta-upload_time = sy-uzeit.
      ls_meta-username    = sy-uname.
      ls_meta-session_id  = lv_session.
      ls_meta-tx_code = p_transaction.
      APPEND ls_meta TO gt_files_preview.
    ELSE.
      PERFORM z16_save_skipped_unit USING lv_session iv_source lv_unit 'No mapped rows loaded'.
      cv_bad = cv_bad + 1.
    ENDIF.
  ENDLOOP.
ENDFORM.
*<<< END FORM z16_ingest_xlsx_xstr

*>>> FORM z16_read_local_xstr - moved from Z_BDC_MASS_PO_ENTRY_F01_BUP

FORM z16_read_local_xstr USING iv_file TYPE string
                         CHANGING cv_xstr TYPE xstring
                                  cv_ok TYPE abap_bool.
  DATA: lt_bin TYPE solix_tab,
        lv_len TYPE i.
  CLEAR: cv_xstr, cv_ok.
  cl_gui_frontend_services=>gui_upload(
    EXPORTING filename = iv_file filetype = 'BIN'
    IMPORTING filelength = lv_len
    CHANGING  data_tab = lt_bin
    EXCEPTIONS OTHERS = 1 ).
  IF sy-subrc <> 0 OR lt_bin IS INITIAL.
    RETURN.
  ENDIF.
  CALL FUNCTION 'SCMS_BINARY_TO_XSTRING'
    EXPORTING input_length = lv_len
    IMPORTING buffer       = cv_xstr
    TABLES    binary_tab   = lt_bin
    EXCEPTIONS OTHERS      = 1.
  IF sy-subrc = 0 AND cv_xstr IS NOT INITIAL.
    cv_ok = abap_true.
  ENDIF.
ENDFORM.
*<<< END FORM z16_read_local_xstr

*>>> FORM z16_build_preview_rows - moved from Z_BDC_MASS_PO_ENTRY_F01_BUP

FORM z16_build_preview_rows.
  "V4X: 0301 is a clean business preview. Do not expose raw DDIC
  "CHAR255/FIELDxx columns. Build a dedicated display row instead.
  DATA: ls_prev  TYPE ty_preview_disp,
        lv_file  TYPE char80,
        lv_sheet TYPE char40,
        lv_batch TYPE zbdc_staging_bup-session_id,
        lv_raw   TYPE string,
        lv_nr    TYPE n LENGTH 2,
        lv_stgf  TYPE string,
        lv_colf  TYPE string.

  FIELD-SYMBOLS: <lv_stg_val>  TYPE any,
                 <lv_disp_val> TYPE any.

  REFRESH gt_preview_data.

  LOOP AT gt_staging INTO DATA(ls_stg).
    CLEAR: ls_prev, lv_file, lv_sheet, lv_batch, lv_raw.

    SELECT SINGLE file_name FROM zbdc_file_lg_bup
      WHERE session_id = @ls_stg-session_id
      INTO @lv_raw.
    IF lv_raw IS INITIAL.
      lv_raw = ls_stg-session_id.
    ENDIF.

    PERFORM z16_split_unit_name USING lv_raw CHANGING lv_file lv_sheet.
    PERFORM z16_batch_prefix_from_sid USING ls_stg-session_id CHANGING lv_batch.

    ls_prev-batch_key    = lv_batch.
    ls_prev-file_title   = lv_file.
    ls_prev-sheet_name   = lv_sheet.
    ls_prev-tx_code      = ls_stg-tcode.
    ls_prev-excel_row    = ls_stg-row_index.
    ls_prev-business_key = ls_stg-record_key.
    IF ls_prev-business_key IS INITIAL.
      ls_prev-business_key = ls_stg-field01.
    ENDIF.
    ls_prev-status_text  = ls_stg-status.
    ls_prev-message_text = ls_stg-error_msg.

    DO 25 TIMES.
      lv_nr = sy-index.
      CONCATENATE 'FIELD' lv_nr INTO lv_stgf.
      CONCATENATE 'COL'   lv_nr INTO lv_colf.
      ASSIGN COMPONENT lv_stgf OF STRUCTURE ls_stg  TO <lv_stg_val>.
      ASSIGN COMPONENT lv_colf OF STRUCTURE ls_prev TO <lv_disp_val>.
      IF <lv_stg_val> IS ASSIGNED AND <lv_disp_val> IS ASSIGNED.
        <lv_disp_val> = <lv_stg_val>.
      ENDIF.
      UNASSIGN: <lv_stg_val>, <lv_disp_val>.
    ENDDO.

    APPEND ls_prev TO gt_preview_data.
  ENDLOOP.
ENDFORM.
*<<< END FORM z16_build_preview_rows

*>>> FORM z16_col_has_value - moved from Z_BDC_MASS_PO_ENTRY_F01_BUP

FORM z16_col_has_value USING iv_col TYPE csequence
                       CHANGING cv_has_value TYPE abap_bool.
  FIELD-SYMBOLS <lv_val> TYPE any.
  CLEAR cv_has_value.
  LOOP AT gt_preview_data INTO DATA(ls_prev_chk).
    ASSIGN COMPONENT iv_col OF STRUCTURE ls_prev_chk TO <lv_val>.
    IF <lv_val> IS ASSIGNED AND <lv_val> IS NOT INITIAL.
      cv_has_value = abap_true.
      EXIT.
    ENDIF.
  ENDLOOP.
ENDFORM.
*<<< END FORM z16_col_has_value

*&---------------------------------------------------------------------*
*& Form Z16_BUILD_FCAT_0301
*& Reliable field catalog for CL_GUI_ALV_GRID on Preview Data (0301)
*&---------------------------------------------------------------------*
FORM z16_build_fcat_0301 CHANGING ct_fcat TYPE lvc_t_fcat.
  DATA: ls_fcat TYPE lvc_s_fcat,
        lt_map  TYPE STANDARD TABLE OF zbdc_mapping_bup,
        ls_map  TYPE zbdc_mapping_bup,
        lv_nr   TYPE n LENGTH 2,
        lv_coln TYPE lvc_fname,
        lv_stgf TYPE string,
        lv_text TYPE lvc_txt,
        lv_has  TYPE abap_bool,
        lv_real_sheet TYPE abap_bool.

  REFRESH ct_fcat.

  CLEAR ls_fcat.
  ls_fcat-fieldname = 'BATCH_KEY'. ls_fcat-coltext = 'Batch'.
  ls_fcat-scrtext_l = 'Batch'. ls_fcat-scrtext_m = 'Batch'. ls_fcat-scrtext_s = 'Batch'.
  ls_fcat-outputlen = 16. APPEND ls_fcat TO ct_fcat.

  CLEAR ls_fcat.
  ls_fcat-fieldname = 'FILE_TITLE'. ls_fcat-coltext = 'File / Source'.
  ls_fcat-scrtext_l = 'File / Source'. ls_fcat-scrtext_m = 'File'. ls_fcat-scrtext_s = 'File'.
  ls_fcat-outputlen = 28. APPEND ls_fcat TO ct_fcat.

  LOOP AT gt_preview_data INTO DATA(ls_sheet_0301).
    IF ls_sheet_0301-sheet_name IS NOT INITIAL AND ls_sheet_0301-sheet_name <> 'DATA'.
      lv_real_sheet = abap_true.
      EXIT.
    ENDIF.
  ENDLOOP.
  IF lv_real_sheet = abap_true.
    CLEAR ls_fcat.
    ls_fcat-fieldname = 'SHEET_NAME'. ls_fcat-coltext = 'Sheet'.
    ls_fcat-scrtext_l = 'Sheet'. ls_fcat-scrtext_m = 'Sheet'. ls_fcat-scrtext_s = 'Sheet'.
    ls_fcat-outputlen = 18. APPEND ls_fcat TO ct_fcat.
  ENDIF.

  CLEAR ls_fcat.
  ls_fcat-fieldname = 'TX_CODE'. ls_fcat-coltext = 'Transaction'.
  ls_fcat-scrtext_l = 'Transaction'. ls_fcat-scrtext_m = 'Transaction'. ls_fcat-scrtext_s = 'TCode'.
  ls_fcat-outputlen = 10. APPEND ls_fcat TO ct_fcat.

  CLEAR ls_fcat.
  ls_fcat-fieldname = 'EXCEL_ROW'. ls_fcat-coltext = 'Excel Row'.
  ls_fcat-scrtext_l = 'Excel Row'. ls_fcat-scrtext_m = 'Excel Row'. ls_fcat-scrtext_s = 'Row'.
  ls_fcat-outputlen = 8. APPEND ls_fcat TO ct_fcat.

  CLEAR ls_fcat.
  ls_fcat-fieldname = 'BUSINESS_KEY'. ls_fcat-coltext = 'Business Key'.
  ls_fcat-scrtext_l = 'Business Key'. ls_fcat-scrtext_m = 'Business Key'. ls_fcat-scrtext_s = 'Key'.
  ls_fcat-outputlen = 16. APPEND ls_fcat TO ct_fcat.

  CLEAR ls_fcat.
  ls_fcat-fieldname = 'STATUS_TEXT'. ls_fcat-coltext = 'Lifecycle Status'.
  ls_fcat-scrtext_l = 'Lifecycle Status'. ls_fcat-scrtext_m = 'Status'. ls_fcat-scrtext_s = 'Status'.
  ls_fcat-outputlen = 12. APPEND ls_fcat TO ct_fcat.

  CLEAR ls_fcat.
  ls_fcat-fieldname = 'MESSAGE_TEXT'. ls_fcat-coltext = 'Message / Hint'.
  ls_fcat-scrtext_l = 'Message / Hint'. ls_fcat-scrtext_m = 'Message'. ls_fcat-scrtext_s = 'Msg'.
  ls_fcat-outputlen = 35. APPEND ls_fcat TO ct_fcat.

  SELECT profile_name, source_column, staging_field, bdc_field, mandatory
    FROM zbdc_mapping_bup
    WHERE profile_name = @txtp_profile_name
    INTO CORRESPONDING FIELDS OF TABLE @lt_map.

  DO 25 TIMES.
    lv_nr = sy-index.
    CONCATENATE 'COL'   lv_nr INTO lv_coln.
    CONCATENATE 'FIELD' lv_nr INTO lv_stgf.
    CLEAR lv_has.
    PERFORM z16_col_has_value USING lv_coln CHANGING lv_has.
    IF lv_has IS INITIAL.
      CONTINUE.
    ENDIF.

    CLEAR: ls_fcat, lv_text.
    READ TABLE lt_map INTO ls_map WITH KEY staging_field = lv_stgf.
    IF sy-subrc = 0 AND ls_map-source_column IS NOT INITIAL.
      lv_text = ls_map-source_column.
    ELSE.
      CASE lv_stgf.
        WHEN 'FIELD01'. lv_text = 'PO Key'.
        WHEN 'FIELD02'. lv_text = 'Vendor'.
        WHEN 'FIELD03'. lv_text = 'Purch. Org'.
        WHEN 'FIELD04'. lv_text = 'Purch. Group'.
        WHEN 'FIELD05'. lv_text = 'Item'.
        WHEN 'FIELD06'. lv_text = 'Material'.
        WHEN 'FIELD07'. lv_text = 'Quantity'.
        WHEN 'FIELD08'. lv_text = 'Plant'.
        WHEN 'FIELD09'. lv_text = 'Sloc'.
        WHEN 'FIELD10'. lv_text = 'Net Price'.
        WHEN 'FIELD11'. lv_text = 'Delivery Date'.
        WHEN 'FIELD12'. lv_text = 'Doc Type'.
        WHEN OTHERS.    lv_text = lv_stgf.
      ENDCASE.
    ENDIF.

    ls_fcat-fieldname = lv_coln.
    ls_fcat-coltext   = lv_text.
    ls_fcat-scrtext_l = lv_text.
    ls_fcat-scrtext_m = lv_text.
    ls_fcat-scrtext_s = lv_text.
    ls_fcat-outputlen = 16.
    APPEND ls_fcat TO ct_fcat.
  ENDDO.
ENDFORM.

*>>> FORM z16_set_pv_col_names - moved from Z_BDC_MASS_PO_ENTRY_F01_BUP

FORM z16_set_pv_col_names USING po_salv TYPE REF TO cl_salv_table.
  DATA: lt_map  TYPE STANDARD TABLE OF zbdc_mapping_bup,
        ls_map  TYPE zbdc_mapping_bup,
        lo_cols TYPE REF TO cl_salv_columns_table,
        lo_col  TYPE REF TO cl_salv_column,
        lv_nr   TYPE n LENGTH 2,
        lv_coln TYPE salv_de_column,
        lv_stgf TYPE string,
        lv_ltxt TYPE scrtext_l,
        lv_mtxt TYPE scrtext_m,
        lv_stxt TYPE scrtext_s,
        lv_pos  TYPE i,
        lv_has  TYPE abap_bool,
        lv_real_sheet TYPE abap_bool.

  lo_cols = po_salv->get_columns( ).
  lo_cols->set_optimize( abap_true ).

  "Core business columns.
  TRY.
      lo_col = lo_cols->get_column( 'BATCH_KEY' ).
      lv_ltxt = 'Batch'. lv_mtxt = 'Batch'. lv_stxt = 'Batch'.
      lo_col->set_long_text( lv_ltxt ). lo_col->set_medium_text( lv_mtxt ). lo_col->set_short_text( lv_stxt ).
      lo_col->set_output_length( 16 ).
      lo_cols->set_column_position( columnname = 'BATCH_KEY' position = 1 ).
    CATCH cx_salv_not_found. ENDTRY.

  TRY.
      lo_col = lo_cols->get_column( 'FILE_TITLE' ).
      lv_ltxt = 'File / Source'. lv_mtxt = 'File'. lv_stxt = 'File'.
      lo_col->set_long_text( lv_ltxt ). lo_col->set_medium_text( lv_mtxt ). lo_col->set_short_text( lv_stxt ).
      lo_col->set_output_length( 28 ).
      lo_cols->set_column_position( columnname = 'FILE_TITLE' position = 2 ).
    CATCH cx_salv_not_found. ENDTRY.

  "Sheet is useful only when the source is a real workbook sheet. CSV fallback DATA is hidden.
  LOOP AT gt_preview_data INTO DATA(ls_sheet_chk).
    IF ls_sheet_chk-sheet_name IS NOT INITIAL AND ls_sheet_chk-sheet_name <> 'DATA'.
      lv_real_sheet = abap_true.
      EXIT.
    ENDIF.
  ENDLOOP.
  TRY.
      lo_col = lo_cols->get_column( 'SHEET_NAME' ).
      lv_ltxt = 'Sheet'. lv_mtxt = 'Sheet'. lv_stxt = 'Sheet'.
      lo_col->set_long_text( lv_ltxt ). lo_col->set_medium_text( lv_mtxt ). lo_col->set_short_text( lv_stxt ).
      lo_col->set_output_length( 18 ).
      lo_col->set_visible( lv_real_sheet ).
      lo_cols->set_column_position( columnname = 'SHEET_NAME' position = 3 ).
    CATCH cx_salv_not_found. ENDTRY.

  TRY.
      lo_col = lo_cols->get_column( 'TX_CODE' ).
      lv_ltxt = 'Transaction'. lv_mtxt = 'Transaction'. lv_stxt = 'TCode'.
      lo_col->set_long_text( lv_ltxt ). lo_col->set_medium_text( lv_mtxt ). lo_col->set_short_text( lv_stxt ).
      lo_col->set_output_length( 10 ).
      lo_cols->set_column_position( columnname = 'TX_CODE' position = 4 ).
    CATCH cx_salv_not_found. ENDTRY.

  TRY.
      lo_col = lo_cols->get_column( 'EXCEL_ROW' ).
      lv_ltxt = 'Excel Row'. lv_mtxt = 'Excel Row'. lv_stxt = 'Row'.
      lo_col->set_long_text( lv_ltxt ). lo_col->set_medium_text( lv_mtxt ). lo_col->set_short_text( lv_stxt ).
      lo_col->set_output_length( 8 ).
      lo_cols->set_column_position( columnname = 'EXCEL_ROW' position = 5 ).
    CATCH cx_salv_not_found. ENDTRY.

  TRY.
      lo_col = lo_cols->get_column( 'BUSINESS_KEY' ).
      lv_ltxt = 'Business Key'. lv_mtxt = 'Business Key'. lv_stxt = 'Key'.
      lo_col->set_long_text( lv_ltxt ). lo_col->set_medium_text( lv_mtxt ). lo_col->set_short_text( lv_stxt ).
      lo_col->set_output_length( 16 ).
      lo_cols->set_column_position( columnname = 'BUSINESS_KEY' position = 6 ).
    CATCH cx_salv_not_found. ENDTRY.

  TRY.
      lo_col = lo_cols->get_column( 'STATUS_TEXT' ).
      lv_ltxt = 'Lifecycle Status'. lv_mtxt = 'Status'. lv_stxt = 'Status'.
      lo_col->set_long_text( lv_ltxt ). lo_col->set_medium_text( lv_mtxt ). lo_col->set_short_text( lv_stxt ).
      lo_col->set_output_length( 12 ).
      lo_cols->set_column_position( columnname = 'STATUS_TEXT' position = 7 ).
    CATCH cx_salv_not_found. ENDTRY.

  TRY.
      lo_col = lo_cols->get_column( 'MESSAGE_TEXT' ).
      lv_ltxt = 'Message / Hint'. lv_mtxt = 'Message'. lv_stxt = 'Msg'.
      lo_col->set_long_text( lv_ltxt ). lo_col->set_medium_text( lv_mtxt ). lo_col->set_short_text( lv_stxt ).
      lo_col->set_output_length( 35 ).
      lo_cols->set_column_position( columnname = 'MESSAGE_TEXT' position = 8 ).
    CATCH cx_salv_not_found. ENDTRY.

  SELECT profile_name, source_column, staging_field, bdc_field, mandatory
    FROM zbdc_mapping_bup
    WHERE profile_name = @txtp_profile_name
    INTO CORRESPONDING FIELDS OF TABLE @lt_map.

  "COLxx are display-only copies of FIELDxx. Empty columns are hidden.
  DO 25 TIMES.
    lv_nr = sy-index.
    CONCATENATE 'COL'   lv_nr INTO lv_coln.
    CONCATENATE 'FIELD' lv_nr INTO lv_stgf.
    CLEAR lv_has.
    PERFORM z16_col_has_value USING lv_coln CHANGING lv_has.
    TRY.
        lo_col = lo_cols->get_column( lv_coln ).
        IF lv_has IS INITIAL.
          lo_col->set_visible( abap_false ).
        ELSE.
          READ TABLE lt_map INTO ls_map WITH KEY staging_field = lv_stgf.
          IF sy-subrc = 0 AND ls_map-source_column IS NOT INITIAL.
            lv_ltxt = ls_map-source_column.
            lv_mtxt = ls_map-source_column.
            lv_stxt = ls_map-source_column.
          ELSE.
            CASE lv_stgf.
              WHEN 'FIELD01'. lv_ltxt = 'PO Key'.
              WHEN 'FIELD02'. lv_ltxt = 'Vendor'.
              WHEN 'FIELD03'. lv_ltxt = 'Purch. Org'.
              WHEN 'FIELD04'. lv_ltxt = 'Purch. Group'.
              WHEN 'FIELD05'. lv_ltxt = 'Item'.
              WHEN 'FIELD06'. lv_ltxt = 'Material'.
              WHEN 'FIELD07'. lv_ltxt = 'Quantity'.
              WHEN 'FIELD08'. lv_ltxt = 'Plant'.
              WHEN 'FIELD09'. lv_ltxt = 'Sloc'.
              WHEN 'FIELD10'. lv_ltxt = 'Net Price'.
              WHEN 'FIELD11'. lv_ltxt = 'Delivery Date'.
              WHEN 'FIELD12'. lv_ltxt = 'Doc Type'.
              WHEN OTHERS.    lv_ltxt = lv_stgf.
            ENDCASE.
            lv_mtxt = lv_ltxt.
            lv_stxt = lv_ltxt.
          ENDIF.
          lo_col->set_long_text( lv_ltxt ).
          lo_col->set_medium_text( lv_mtxt ).
          lo_col->set_short_text( lv_stxt ).
          lo_col->set_output_length( 16 ).
          lo_col->set_visible( abap_true ).
          lv_pos = 20 + sy-index.
          lo_cols->set_column_position( columnname = lv_coln position = lv_pos ).
        ENDIF.
      CATCH cx_salv_not_found.
    ENDTRY.
  ENDDO.
ENDFORM.
*<<< END FORM z16_set_pv_col_names

*>>> FORM DOWNLOAD_TEMPLATE - moved from Z_BDC_MASS_PO_ENTRY_F01_BUP


FORM DOWNLOAD_TEMPLATE.
  DATA: LV_ANSWER TYPE C,
        LT_DATA   TYPE STANDARD TABLE OF STRING,
        LV_DEF    TYPE STRING,
        LV_FNAME  TYPE STRING,
        LV_PATH   TYPE STRING,
        LV_FULL   TYPE STRING,
        LV_ACTION TYPE I.

  CALL FUNCTION 'POPUP_TO_DECIDE'
    EXPORTING
      TEXTLINE1    = 'Chon loai template can tai:'
      TEXT_OPTION1 = 'ME21N (Tao PO)      '
      TEXT_OPTION2 = 'MIGO  (Nhap kho 101)'
      TITEL        = 'Download Template'
    IMPORTING
      ANSWER       = LV_ANSWER.

  IF LV_ANSWER = 'A'. RETURN. ENDIF.

  REFRESH LT_DATA.
  DATA LV_GUIDE_USED TYPE ABAP_BOOL.
  IF LV_ANSWER = '1'.
    P_TRANSACTION = 'ME21N'.
    LV_DEF = 'template_ME21N.csv'.
    PERFORM Z16_BUILD_TEMPLATE_FROM_GUIDE USING P_TRANSACTION CHANGING LT_DATA LV_GUIDE_USED.
    IF LV_GUIDE_USED IS INITIAL.
      APPEND '# Instruction: Do not change/delete header names. Lines starting with # are ignored by upload.' TO LT_DATA.
      APPEND '# Required fields are marked with *. PO_KEY groups PO items into one purchase order.' TO LT_DATA.
      APPEND '# Flow: upload -> Preview Data -> Validate -> Execute/Retry. Do not fill SAP system fields such as SESSION_ID/STATUS/CREATED_BY.' TO LT_DATA.
      APPEND 'PO_KEY*,VENDOR*,PURCH_ORG*,PURCH_GROUP*,ITEM_NO,MATERIAL*,QUANTITY*,PLANT*' TO LT_DATA.
      APPEND 'PO_001,5001000105,ZFA1,BD1,10,PTOUCHPAD101,12,ZFA5'                         TO LT_DATA.
    ENDIF.
  ELSE.
    P_TRANSACTION = 'MIGO'.
    LV_DEF = 'template_MIGO.csv'.
    PERFORM Z16_BUILD_TEMPLATE_FROM_GUIDE USING P_TRANSACTION CHANGING LT_DATA LV_GUIDE_USED.
    IF LV_GUIDE_USED IS INITIAL.
      APPEND '# Instruction: Do not change/delete header names. Lines starting with # are ignored by upload.' TO LT_DATA.
      APPEND '# Required fields are marked with *. MIGO_KEY groups GR rows.' TO LT_DATA.
      APPEND '# Flow: upload -> Preview Data -> Validate -> Execute/Retry. Do not fill SAP system fields such as SESSION_ID/STATUS/CREATED_BY.' TO LT_DATA.
      APPEND 'MIGO_KEY*,PO_NUMBER*,PO_ITEM*,QUANTITY*' TO LT_DATA.
      APPEND 'MIGO_001,4500003535,00010,23'            TO LT_DATA.
    ENDIF.
  ENDIF.

  CL_GUI_FRONTEND_SERVICES=>FILE_SAVE_DIALOG(
    EXPORTING
      WINDOW_TITLE      = 'Luu template CSV'
      DEFAULT_EXTENSION = 'csv'
      DEFAULT_FILE_NAME = LV_DEF
      FILE_FILTER       = 'CSV (*.csv)|*.csv'
    CHANGING
      FILENAME          = LV_FNAME
      PATH              = LV_PATH
      FULLPATH          = LV_FULL
      USER_ACTION       = LV_ACTION
    EXCEPTIONS OTHERS   = 1 ).
  IF SY-SUBRC <> 0 OR LV_ACTION <> CL_GUI_FRONTEND_SERVICES=>ACTION_OK.
    RETURN.
  ENDIF.

  CL_GUI_FRONTEND_SERVICES=>GUI_DOWNLOAD(
    EXPORTING FILENAME = LV_FULL FILETYPE = 'ASC'
    CHANGING  DATA_TAB = LT_DATA
    EXCEPTIONS OTHERS  = 1 ).
  IF SY-SUBRC <> 0.
    MESSAGE 'Khong ghi duoc file template.' TYPE 'E'. RETURN.
  ENDIF.

  MESSAGE |Da tai { LV_DEF } ({ P_TRANSACTION }).| TYPE 'S'.
ENDFORM.
*<<< END FORM DOWNLOAD_TEMPLATE

*>>> FORM PROCESS_CSV_ROWS - moved from Z_BDC_MASS_PO_ENTRY_F01_BUP

FORM PROCESS_CSV_ROWS USING PT_RAW TYPE STRING_TABLE.
  DATA: LT_HEADERS   TYPE TABLE OF STRING,
        LV_HEADER_LN TYPE STRING.
  TYPES: BEGIN OF TY_COL_IDX,
           COL_NAME TYPE STRING,
           COL_NO   TYPE I,
         END OF TY_COL_IDX.
  DATA: LT_COL_IDX TYPE TABLE OF TY_COL_IDX,
        LS_COL_IDX TYPE TY_COL_IDX,
        LT_MAP     TYPE STANDARD TABLE OF zbdc_mapping_bup,
        LS_MAP     TYPE zbdc_mapping_bup,
        LV_SESS    TYPE zbdc_staging_bup-session_id,
        LV_IDX     TYPE I,
        LS_STG     TYPE zbdc_staging_bup,
        LT_COL     TYPE TABLE OF STRING,
        LV_VAL     TYPE STRING,
        LV_SRC     TYPE STRING,
        LV_COLNO   TYPE I,
        LV_MISSING TYPE STRING,
        LV_MISS_CNT TYPE I.
  FIELD-SYMBOLS: <FV> TYPE ANY.

  IF PT_RAW IS INITIAL. RETURN. ENDIF.

  DATA LV_HEADER_IDX TYPE I.
  LOOP AT PT_RAW INTO LV_HEADER_LN.
    IF LV_HEADER_LN IS INITIAL.
      CONTINUE.
    ENDIF.
    IF LV_HEADER_LN CP '#*'.
      CONTINUE.
    ENDIF.
    LV_HEADER_IDX = SY-TABIX.
    EXIT.
  ENDLOOP.

  IF LV_HEADER_IDX IS INITIAL OR LV_HEADER_LN IS INITIAL.
    MESSAGE 'File CSV khong co dong header.' TYPE 'W'. RETURN.
  ENDIF.
  PERFORM SPLIT_CSV_LINE USING LV_HEADER_LN CHANGING LT_HEADERS.

  PERFORM z16_resolve_unit_tcode USING gv_current_sheet_name LV_HEADER_LN CHANGING P_TRANSACTION.
  IF P_TRANSACTION = 'MIGO'.
    TXTP_PROFILE_NAME = 'DEFAULT_MIGO_MAP'.
  ELSE.
    TXTP_PROFILE_NAME = 'DEFAULT_EXCEL_MAP'.
    P_TRANSACTION     = 'ME21N'.
  ENDIF.

  SELECT PROFILE_NAME, SOURCE_COLUMN, STAGING_FIELD, BDC_FIELD, MANDATORY
    FROM zbdc_mapping_bup
    WHERE PROFILE_NAME = @TXTP_PROFILE_NAME
    INTO CORRESPONDING FIELDS OF TABLE @LT_MAP.

  IF LT_MAP IS INITIAL.
    MESSAGE |Profile '{ TXTP_PROFILE_NAME }' chua co mapping!| TYPE 'W'.
    RETURN.
  ENDIF.

  LOOP AT LT_HEADERS INTO DATA(LV_HDR).
    LS_COL_IDX-COL_NAME = LV_HDR.
    TRANSLATE LS_COL_IDX-COL_NAME TO UPPER CASE.
    CONDENSE LS_COL_IDX-COL_NAME NO-GAPS.
    REPLACE ALL OCCURRENCES OF '*' IN LS_COL_IDX-COL_NAME WITH ''.
    REPLACE ALL OCCURRENCES OF '"' IN LS_COL_IDX-COL_NAME WITH ''.
    LS_COL_IDX-COL_NO = SY-TABIX.
    APPEND LS_COL_IDX TO LT_COL_IDX.
  ENDLOOP.

  "Senior 0300 guard: detect missing required columns before creating staging rows.
  CLEAR: LV_MISSING, LV_MISS_CNT.
  LOOP AT LT_MAP INTO LS_MAP WHERE MANDATORY = 'X'.
    LV_SRC = LS_MAP-SOURCE_COLUMN.
    TRANSLATE LV_SRC TO UPPER CASE.
    CONDENSE LV_SRC NO-GAPS.
    REPLACE ALL OCCURRENCES OF '*' IN LV_SRC WITH ''.
    REPLACE ALL OCCURRENCES OF '"' IN LV_SRC WITH ''.
    READ TABLE LT_COL_IDX INTO LS_COL_IDX WITH KEY COL_NAME = LV_SRC.
    IF SY-SUBRC <> 0.
      LV_MISS_CNT = LV_MISS_CNT + 1.
      IF LV_MISSING IS INITIAL.
        LV_MISSING = LS_MAP-SOURCE_COLUMN.
      ELSE.
        LV_MISSING = LV_MISSING && ', ' && LS_MAP-SOURCE_COLUMN.
      ENDIF.
    ENDIF.
  ENDLOOP.

  IF LV_MISS_CNT > 0.
    MESSAGE |CSV header thieu { LV_MISS_CNT } cot bat buoc: { LV_MISSING }| TYPE 'W'.
    RETURN.
  ENDIF.

  IF gv_forced_session_id IS NOT INITIAL.
    LV_SESS = gv_forced_session_id.
  ELSE.
    CONCATENATE 'SES_' SY-DATUM '_' SY-UZEIT INTO LV_SESS.
  ENDIF.
  LV_IDX = 0.

  LOOP AT PT_RAW INTO DATA(LV_LINE).
    IF SY-TABIX <= LV_HEADER_IDX. CONTINUE. ENDIF.
    IF LV_LINE IS INITIAL. CONTINUE. ENDIF.
    IF LV_LINE CP '#*'. CONTINUE. ENDIF.

    LV_IDX = LV_IDX + 1.
    CLEAR LS_STG.
    PERFORM SPLIT_CSV_LINE USING LV_LINE CHANGING LT_COL.

    LOOP AT LT_MAP INTO LS_MAP.
      LV_SRC = LS_MAP-SOURCE_COLUMN.
      TRANSLATE LV_SRC TO UPPER CASE.
      CONDENSE LV_SRC NO-GAPS.
      REPLACE ALL OCCURRENCES OF '*' IN LV_SRC WITH ''.
      REPLACE ALL OCCURRENCES OF '"' IN LV_SRC WITH ''.

      READ TABLE LT_COL_IDX INTO LS_COL_IDX WITH KEY COL_NAME = LV_SRC.
      IF SY-SUBRC <> 0.
        LV_VAL = ''.
      ELSE.
        LV_COLNO = LS_COL_IDX-COL_NO.
        READ TABLE LT_COL INTO LV_VAL INDEX LV_COLNO.
        IF SY-SUBRC <> 0. LV_VAL = ''. ENDIF.
        CONDENSE LV_VAL.
      ENDIF.

      IF LS_MAP-MANDATORY = 'X' AND LV_VAL IS INITIAL.
        LS_STG-STATUS    = 'ERROR'.
        IF LS_STG-ERROR_MSG IS INITIAL.
          LS_STG-ERROR_MSG = |Missing mandatory field { LS_MAP-SOURCE_COLUMN }|.
        ELSE.
          LS_STG-ERROR_MSG = |{ LS_STG-ERROR_MSG }; Missing { LS_MAP-SOURCE_COLUMN }|.
        ENDIF.
      ENDIF.

      ASSIGN COMPONENT LS_MAP-STAGING_FIELD OF STRUCTURE LS_STG TO <FV>.
      IF SY-SUBRC = 0. <FV> = LV_VAL. ENDIF.
    ENDLOOP.

    LS_STG-SESSION_ID = LV_SESS.
    LS_STG-ROW_INDEX  = LV_IDX.
    LS_STG-RECORD_KEY = LS_STG-FIELD01.
    LS_STG-TCODE      = P_TRANSACTION.
    IF LS_STG-STATUS IS INITIAL.
      LS_STG-STATUS = 'STAGED'.
    ENDIF.
    APPEND LS_STG TO GT_STAGING.
  ENDLOOP.

  DATA(LV_ROWCOUNT) = LINES( GT_STAGING ).
  WRITE LV_ROWCOUNT TO TXTP_ROW_COUNT LEFT-JUSTIFIED.
  TXTP_ROW = TXTP_ROW_COUNT. TXTP_ROWS = TXTP_ROW_COUNT.
  TXTGV_ROWS = TXTP_ROW_COUNT. TXTGV_TOTAL_ROWS = TXTP_ROW_COUNT.

  IF GT_STAGING IS NOT INITIAL.
    MODIFY zbdc_staging_bup FROM TABLE gt_staging.
    COMMIT WORK AND WAIT.
  ENDIF.
ENDFORM.
*<<< END FORM PROCESS_CSV_ROWS

*>>> FORM INGEST_JSON_PAYLOAD_BUP - moved from Z_BDC_MASS_PO_ENTRY_F01_BUP

FORM INGEST_JSON_PAYLOAD_BUP USING IV_JSON TYPE STRING IV_SOURCE TYPE STRING.
  DATA: LV_JSON TYPE STRING,
        LV_TAIL TYPE STRING,
        LV_OBJ  TYPE STRING,
        LT_COLS TYPE STRING_TABLE,
        LV_SID  TYPE ZBDC_STAGING_BUP-SESSION_ID,
        LV_IDX  TYPE I,
        LV_OFF  TYPE I,
        LV_END  TYPE I,
        LV_LEN  TYPE I,
        LV_NEXT TYPE I.

  LV_JSON = IV_JSON.
  IF gv_forced_session_id IS NOT INITIAL.
    LV_SID = gv_forced_session_id.
  ELSE.
    LV_SID = |SES_{ SY-DATUM }_{ SY-UZEIT }|.
  ENDIF.

  "No REGEX: avoids POSIX-deprecated syntax warnings on this SAP system.
  "The webhook JSON used by the demo is flat, so a simple object scanner is enough.
  FIND FIRST OCCURRENCE OF '{' IN LV_JSON MATCH OFFSET LV_OFF.
  WHILE SY-SUBRC = 0.
    LV_TAIL = LV_JSON+LV_OFF.
    FIND FIRST OCCURRENCE OF '}' IN LV_TAIL MATCH OFFSET LV_END.
    IF SY-SUBRC <> 0.
      EXIT.
    ENDIF.

    LV_LEN = LV_END + 1.
    LV_OBJ = LV_TAIL(LV_LEN).

    REFRESH LT_COLS.
    PERFORM JSON_OBJECT_TO_COLS_BUP USING LV_OBJ CHANGING LT_COLS.
    LV_IDX = LV_IDX + 1.
    PERFORM APPEND_STAGING_FROM_COLS_BUP USING LT_COLS LV_SID LV_IDX IV_SOURCE.

    LV_NEXT = LV_OFF + LV_LEN.
    IF LV_NEXT >= STRLEN( LV_JSON ).
      EXIT.
    ENDIF.

    LV_JSON = LV_JSON+LV_NEXT.
    FIND FIRST OCCURRENCE OF '{' IN LV_JSON MATCH OFFSET LV_OFF.
  ENDWHILE.
ENDFORM.
*<<< END FORM INGEST_JSON_PAYLOAD_BUP

*>>> FORM JSON_OBJECT_TO_COLS_BUP - moved from Z_BDC_MASS_PO_ENTRY_F01_BUP

FORM JSON_OBJECT_TO_COLS_BUP USING IV_OBJ TYPE STRING CHANGING CT_COLS TYPE STRING_TABLE.
  DATA LV_VAL TYPE STRING.
  REFRESH CT_COLS.
  CASE P_TRANSACTION.
    WHEN 'MIGO'.
      PERFORM JSON_GET_BUP USING IV_OBJ 'mvt_type' CHANGING LV_VAL. IF LV_VAL IS INITIAL. PERFORM JSON_GET_BUP USING IV_OBJ 'bwart' CHANGING LV_VAL. ENDIF. APPEND LV_VAL TO CT_COLS.
      PERFORM JSON_GET_BUP USING IV_OBJ 'ref_doc' CHANGING LV_VAL. IF LV_VAL IS INITIAL. PERFORM JSON_GET_BUP USING IV_OBJ 'po_number' CHANGING LV_VAL. ENDIF. APPEND LV_VAL TO CT_COLS.
      PERFORM JSON_GET_BUP USING IV_OBJ 'ref_item' CHANGING LV_VAL. IF LV_VAL IS INITIAL. PERFORM JSON_GET_BUP USING IV_OBJ 'po_item' CHANGING LV_VAL. ENDIF. APPEND LV_VAL TO CT_COLS.
      PERFORM JSON_GET_BUP USING IV_OBJ 'material' CHANGING LV_VAL. IF LV_VAL IS INITIAL. PERFORM JSON_GET_BUP USING IV_OBJ 'matnr' CHANGING LV_VAL. ENDIF. APPEND LV_VAL TO CT_COLS.
      PERFORM JSON_GET_BUP USING IV_OBJ 'quantity' CHANGING LV_VAL. IF LV_VAL IS INITIAL. PERFORM JSON_GET_BUP USING IV_OBJ 'menge' CHANGING LV_VAL. ENDIF. APPEND LV_VAL TO CT_COLS.
      PERFORM JSON_GET_BUP USING IV_OBJ 'uom' CHANGING LV_VAL. IF LV_VAL IS INITIAL. PERFORM JSON_GET_BUP USING IV_OBJ 'meins' CHANGING LV_VAL. ENDIF. APPEND LV_VAL TO CT_COLS.
      PERFORM JSON_GET_BUP USING IV_OBJ 'plant' CHANGING LV_VAL. IF LV_VAL IS INITIAL. PERFORM JSON_GET_BUP USING IV_OBJ 'werks' CHANGING LV_VAL. ENDIF. APPEND LV_VAL TO CT_COLS.
      PERFORM JSON_GET_BUP USING IV_OBJ 'storage_loc' CHANGING LV_VAL. IF LV_VAL IS INITIAL. PERFORM JSON_GET_BUP USING IV_OBJ 'lgort' CHANGING LV_VAL. ENDIF. APPEND LV_VAL TO CT_COLS.
    WHEN OTHERS.
      PERFORM JSON_GET_BUP USING IV_OBJ 'doc_type' CHANGING LV_VAL. IF LV_VAL IS INITIAL. PERFORM JSON_GET_BUP USING IV_OBJ 'bsart' CHANGING LV_VAL. ENDIF. APPEND LV_VAL TO CT_COLS.
      PERFORM JSON_GET_BUP USING IV_OBJ 'vendor' CHANGING LV_VAL. IF LV_VAL IS INITIAL. PERFORM JSON_GET_BUP USING IV_OBJ 'lifnr' CHANGING LV_VAL. ENDIF. APPEND LV_VAL TO CT_COLS.
      PERFORM JSON_GET_BUP USING IV_OBJ 'purch_org' CHANGING LV_VAL. IF LV_VAL IS INITIAL. PERFORM JSON_GET_BUP USING IV_OBJ 'ekorg' CHANGING LV_VAL. ENDIF. APPEND LV_VAL TO CT_COLS.
      PERFORM JSON_GET_BUP USING IV_OBJ 'purch_group' CHANGING LV_VAL. IF LV_VAL IS INITIAL. PERFORM JSON_GET_BUP USING IV_OBJ 'ekgrp' CHANGING LV_VAL. ENDIF. APPEND LV_VAL TO CT_COLS.
      PERFORM JSON_GET_BUP USING IV_OBJ 'item_no' CHANGING LV_VAL. IF LV_VAL IS INITIAL. PERFORM JSON_GET_BUP USING IV_OBJ 'ebelp' CHANGING LV_VAL. ENDIF. APPEND LV_VAL TO CT_COLS.
      PERFORM JSON_GET_BUP USING IV_OBJ 'material' CHANGING LV_VAL. IF LV_VAL IS INITIAL. PERFORM JSON_GET_BUP USING IV_OBJ 'matnr' CHANGING LV_VAL. ENDIF. APPEND LV_VAL TO CT_COLS.
      PERFORM JSON_GET_BUP USING IV_OBJ 'quantity' CHANGING LV_VAL. IF LV_VAL IS INITIAL. PERFORM JSON_GET_BUP USING IV_OBJ 'menge' CHANGING LV_VAL. ENDIF. APPEND LV_VAL TO CT_COLS.
      PERFORM JSON_GET_BUP USING IV_OBJ 'plant' CHANGING LV_VAL. IF LV_VAL IS INITIAL. PERFORM JSON_GET_BUP USING IV_OBJ 'werks' CHANGING LV_VAL. ENDIF. APPEND LV_VAL TO CT_COLS.
  ENDCASE.
ENDFORM.
*<<< END FORM JSON_OBJECT_TO_COLS_BUP

*>>> FORM JSON_GET_BUP - moved from Z_BDC_MASS_PO_ENTRY_F01_BUP

FORM JSON_GET_BUP USING IV_OBJ TYPE STRING IV_KEY TYPE STRING CHANGING CV_VAL TYPE STRING.
  DATA: LV_KEY_PATTERN TYPE STRING,
        LV_POS         TYPE I,
        LV_COLON       TYPE I,
        LV_SCAN        TYPE I,
        LV_START       TYPE I,
        LV_LEN         TYPE I,
        LV_TAIL        TYPE STRING,
        LV_CHAR        TYPE C LENGTH 1.

  CLEAR CV_VAL.

  "Manual key/value extraction to avoid deprecated POSIX regex warnings.
  "Supports flat JSON values like: " && '"' && "vendor" && '"' && ":" && '"' && "5000001" && '"' && " or quantity:10.
  LV_KEY_PATTERN = '"' && IV_KEY && '"'.

  FIND FIRST OCCURRENCE OF LV_KEY_PATTERN IN IV_OBJ MATCH OFFSET LV_POS.
  IF SY-SUBRC <> 0.
    RETURN.
  ENDIF.

  LV_SCAN = LV_POS + STRLEN( LV_KEY_PATTERN ).
  LV_TAIL = IV_OBJ+LV_SCAN.
  FIND FIRST OCCURRENCE OF ':' IN LV_TAIL MATCH OFFSET LV_COLON.
  IF SY-SUBRC <> 0.
    RETURN.
  ENDIF.

  LV_SCAN = LV_SCAN + LV_COLON + 1.

  "Skip blanks and an optional opening quote.
  WHILE LV_SCAN < STRLEN( IV_OBJ ).
    LV_CHAR = IV_OBJ+LV_SCAN(1).
    IF LV_CHAR = SPACE OR LV_CHAR = '"'.
      LV_SCAN = LV_SCAN + 1.
    ELSE.
      EXIT.
    ENDIF.
  ENDWHILE.

  LV_START = LV_SCAN.

  "Read until closing quote/comma/object-end/array-end.
  WHILE LV_SCAN < STRLEN( IV_OBJ ).
    LV_CHAR = IV_OBJ+LV_SCAN(1).
    IF LV_CHAR = '"' OR LV_CHAR = ',' OR LV_CHAR = '}' OR LV_CHAR = ']'.
      EXIT.
    ENDIF.
    LV_SCAN = LV_SCAN + 1.
  ENDWHILE.

  LV_LEN = LV_SCAN - LV_START.
  IF LV_LEN > 0.
    CV_VAL = IV_OBJ+LV_START(LV_LEN).
    CONDENSE CV_VAL.
  ENDIF.
ENDFORM.
*<<< END FORM JSON_GET_BUP

*>>> FORM GET_MIN_COLS_BY_TCODE_BUP - moved from Z_BDC_MASS_PO_ENTRY_F01_BUP

FORM GET_MIN_COLS_BY_TCODE_BUP USING IV_TCODE TYPE CHAR20 CHANGING CV_MIN TYPE I.
  CASE IV_TCODE.
    WHEN 'MIGO'. CV_MIN = 7.
    WHEN OTHERS. CV_MIN = 8.
  ENDCASE.
ENDFORM.
*<<< END FORM GET_MIN_COLS_BY_TCODE_BUP

*>>> FORM SPLIT_CSV_LINE - moved from Z_BDC_MASS_PO_ENTRY_F01_BUP

FORM SPLIT_CSV_LINE USING IV_LINE TYPE STRING CHANGING CT_COLS TYPE STRING_TABLE.
  DATA: LV_POS      TYPE I,
        LV_LEN      TYPE I,
        LV_CHAR     TYPE C LENGTH 1,
        LV_NEXT     TYPE C LENGTH 1,
        LV_CELL     TYPE STRING,
        LV_IN_QUOTE TYPE ABAP_BOOL,
        LV_NEXT_POS TYPE I.
  REFRESH CT_COLS.
  LV_LEN = STRLEN( IV_LINE ).

  WHILE LV_POS < LV_LEN.
    LV_CHAR = IV_LINE+LV_POS(1).
    IF LV_CHAR = '"'.
      IF LV_IN_QUOTE = ABAP_TRUE AND LV_POS + 1 < LV_LEN.
        LV_NEXT_POS = LV_POS + 1.
        LV_NEXT = IV_LINE+LV_NEXT_POS(1).
        IF LV_NEXT = '"'.
          LV_CELL = LV_CELL && '"'.
          LV_POS = LV_POS + 2.
          CONTINUE.
        ENDIF.
      ENDIF.
      IF LV_IN_QUOTE = ABAP_TRUE.
        LV_IN_QUOTE = ABAP_FALSE.
      ELSE.
        LV_IN_QUOTE = ABAP_TRUE.
      ENDIF.
    ELSEIF LV_CHAR = ',' AND LV_IN_QUOTE = ABAP_FALSE.
      APPEND LV_CELL TO CT_COLS.
      CLEAR LV_CELL.
    ELSE.
      LV_CELL = LV_CELL && LV_CHAR.
    ENDIF.
    LV_POS = LV_POS + 1.
  ENDWHILE.
  APPEND LV_CELL TO CT_COLS.
ENDFORM.
*<<< END FORM SPLIT_CSV_LINE

*>>> FORM PROCESS_JSON_ROWS - moved from Z_BDC_MASS_PO_ENTRY_F01_BUP

FORM PROCESS_JSON_ROWS USING PV_CONTENT TYPE STRING.
  TYPES: BEGIN OF TY_JSON_ITEM, SUPPLIER TYPE STRING, PURCH_ORG TYPE STRING, PURCH_GRP TYPE STRING, MATERIAL TYPE STRING, QUANTITY TYPE STRING, DELV_DATE TYPE STRING, PLANT TYPE STRING, END OF TY_JSON_ITEM.
  DATA: LT_ITEMS TYPE STANDARD TABLE OF TY_JSON_ITEM, LS_ITEM TYPE TY_JSON_ITEM, LS_STG TYPE zbdc_staging_bup, LT_MAP TYPE STANDARD TABLE OF zbdc_mapping_bup, LS_MAP TYPE zbdc_mapping_bup, LV_SESS TYPE zbdc_staging_bup-session_id, LV_IDX TYPE I.
  FIELD-SYMBOLS: <FV> TYPE ANY, <FS> TYPE ANY.

  /UI2/CL_JSON=>DESERIALIZE( EXPORTING JSON = PV_CONTENT PRETTY_NAME = /UI2/CL_JSON=>PRETTY_MODE-CAMEL_CASE CHANGING DATA = LT_ITEMS ).
  IF LT_ITEMS IS INITIAL. MESSAGE 'File JSON khong co du lieu hop le!' TYPE 'W'. RETURN. ENDIF.

  SELECT PROFILE_NAME, SOURCE_COLUMN, STAGING_FIELD, BDC_FIELD, MANDATORY FROM zbdc_mapping_bup WHERE PROFILE_NAME = @TXTP_PROFILE_NAME INTO CORRESPONDING FIELDS OF TABLE @LT_MAP.
  IF gv_forced_session_id IS NOT INITIAL. LV_SESS = gv_forced_session_id. ELSE. CONCATENATE 'SES_' SY-DATUM '_' SY-UZEIT INTO LV_SESS. ENDIF. LV_IDX = 0.

  LOOP AT LT_ITEMS INTO LS_ITEM. LV_IDX = LV_IDX + 1. CLEAR LS_STG.
    LOOP AT LT_MAP INTO LS_MAP.
      DATA(LV_COL) = LS_MAP-SOURCE_COLUMN. TRANSLATE LV_COL TO UPPER CASE. CONDENSE LV_COL NO-GAPS.
      ASSIGN COMPONENT LV_COL OF STRUCTURE LS_ITEM TO <FS>. ASSIGN COMPONENT LS_MAP-STAGING_FIELD OF STRUCTURE LS_STG TO <FV>.
      IF SY-SUBRC = 0 AND <FS> IS ASSIGNED. <FV> = <FS>. ENDIF. UNASSIGN <FS>.
    ENDLOOP.
    LS_STG-SESSION_ID = LV_SESS. LS_STG-ROW_INDEX = LV_IDX. LS_STG-RECORD_KEY = LS_STG-FIELD01. LS_STG-TCODE = P_TRANSACTION. LS_STG-STATUS = 'STAGED'. APPEND LS_STG TO GT_STAGING.
  ENDLOOP.

  DATA(LV_ROWCOUNT) = LINES( GT_STAGING ). WRITE LV_ROWCOUNT TO TXTP_ROW_COUNT LEFT-JUSTIFIED.
  TXTP_ROW = TXTP_ROW_COUNT. TXTP_ROWS = TXTP_ROW_COUNT. TXTGV_ROWS = TXTP_ROW_COUNT. TXTGV_TOTAL_ROWS = TXTP_ROW_COUNT.
  MESSAGE |Da parse { LV_ROWCOUNT } dong tu file JSON!| TYPE 'S'.
ENDFORM.
*<<< END FORM PROCESS_JSON_ROWS

*>>> FORM PROCESS_XML_ROWS - moved from Z_BDC_MASS_PO_ENTRY_F01_BUP

FORM PROCESS_XML_ROWS USING PV_CONTENT TYPE STRING.
  DATA: LT_MAP TYPE STANDARD TABLE OF zbdc_mapping_bup, LS_MAP TYPE zbdc_mapping_bup, LS_STG TYPE zbdc_staging_bup, LV_SESS TYPE zbdc_staging_bup-session_id, LV_IDX TYPE I, LV_TAG TYPE STRING, LV_VAL TYPE STRING, LV_LINE TYPE STRING, LT_LINES TYPE
STRING_TABLE.
  FIELD-SYMBOLS: <FV> TYPE ANY.

  SELECT PROFILE_NAME, SOURCE_COLUMN, STAGING_FIELD, BDC_FIELD, MANDATORY FROM zbdc_mapping_bup WHERE PROFILE_NAME = @TXTP_PROFILE_NAME INTO CORRESPONDING FIELDS OF TABLE @LT_MAP.
  IF gv_forced_session_id IS NOT INITIAL. LV_SESS = gv_forced_session_id. ELSE. CONCATENATE 'SES_' SY-DATUM '_' SY-UZEIT INTO LV_SESS. ENDIF. LV_IDX = 0.
  SPLIT PV_CONTENT AT CL_ABAP_CHAR_UTILITIES=>NEWLINE INTO TABLE LT_LINES.

  CLEAR LS_STG.
  LOOP AT LT_LINES INTO LV_LINE. CONDENSE LV_LINE NO-GAPS. IF LV_LINE IS INITIAL. CONTINUE. ENDIF.
    IF LV_LINE CP '<Record>*' OR LV_LINE = '<Record>'. CLEAR LS_STG. LV_IDX = LV_IDX + 1. CONTINUE. ENDIF.
    IF LV_LINE CP '</Record>*' OR LV_LINE = '</Record>'.
      LS_STG-SESSION_ID = LV_SESS. LS_STG-ROW_INDEX = LV_IDX. LS_STG-RECORD_KEY = LS_STG-FIELD01. LS_STG-TCODE = P_TRANSACTION. LS_STG-STATUS = 'STAGED'. APPEND LS_STG TO GT_STAGING. CONTINUE.
    ENDIF.
    FIND PCRE '<([^/][^>]*)>(.*?)</[^>]+>' IN LV_LINE SUBMATCHES LV_TAG LV_VAL.
    IF SY-SUBRC = 0. TRANSLATE LV_TAG TO UPPER CASE. CONDENSE LV_TAG NO-GAPS. CONDENSE LV_VAL.
      LOOP AT LT_MAP INTO LS_MAP.
        DATA(LV_SRC) = LS_MAP-SOURCE_COLUMN. TRANSLATE LV_SRC TO UPPER CASE. CONDENSE LV_SRC NO-GAPS.
        IF LV_SRC = LV_TAG. ASSIGN COMPONENT LS_MAP-STAGING_FIELD OF STRUCTURE LS_STG TO <FV>. IF SY-SUBRC = 0. <FV> = LV_VAL. ENDIF. ENDIF.
      ENDLOOP.
    ENDIF.
  ENDLOOP.

  DATA(LV_ROWCOUNT) = LINES( GT_STAGING ). WRITE LV_ROWCOUNT TO TXTP_ROW_COUNT LEFT-JUSTIFIED.
  TXTP_ROW = TXTP_ROW_COUNT. TXTP_ROWS = TXTP_ROW_COUNT. TXTGV_ROWS = TXTP_ROW_COUNT. TXTGV_TOTAL_ROWS = TXTP_ROW_COUNT.
  MESSAGE |Da parse { LV_ROWCOUNT } dong tu file XML!| TYPE 'S'.
ENDFORM.
*<<< END FORM PROCESS_XML_ROWS

*>>> FORM z16_prepare_preview_file - moved from Z_BDC_MASS_PO_ENTRY_F01_BUP
FORM z16_prepare_preview_file.
  TYPES: BEGIN OF ty_file_sid_0302,
           session_id TYPE zbdc_file_lg_bup-session_id,
         END OF ty_file_sid_0302,
         BEGIN OF ty_sess_sid_0302,
           session_id TYPE zbdc_session_bup-session_id,
         END OF ty_sess_sid_0302,
         BEGIN OF ty_owner_0302,
           session_id TYPE zbdc_file_lg_bup-session_id,
           created_by TYPE zbdc_session_bup-created_by,
         END OF ty_owner_0302,
         BEGIN OF ty_size_0302,
           session_id TYPE zbdc_result_bup-session_id,
           message    TYPE zbdc_result_bup-message,
           created_at TYPE zbdc_result_bup-created_at,
         END OF ty_size_0302.

  DATA: ls_meta       TYPE ty_files_disp,
        lv_date       TYPE sy-datum,
        lv_time       TYPE sy-uzeit,
        lv_user       TYPE sy-uname,
        lv_cnt        TYPE i,
        lv_file_title TYPE string,
        lv_source_txt TYPE char20,
        lv_max_rows   TYPE i,
        lv_line_count TYPE i,
        lv_delete_from TYPE i,
        lv_owned      TYPE abap_bool,
        lv_source_msg TYPE string,
        lv_size_text  TYPE string,
        lv_size_check TYPE string,
        lv_size_tail  TYPE string.

  DATA: lt_file_lg    TYPE STANDARD TABLE OF zbdc_file_lg_bup,
        lt_my_sid     TYPE SORTED TABLE OF ty_file_sid_0302
                      WITH UNIQUE KEY session_id,
        lt_lookup_sid TYPE SORTED TABLE OF ty_sess_sid_0302
                      WITH UNIQUE KEY session_id,
        lt_owner_raw  TYPE STANDARD TABLE OF zbdc_session_bup,
        lt_owner      TYPE HASHED TABLE OF ty_owner_0302
                      WITH UNIQUE KEY session_id,
        lt_size_log   TYPE STANDARD TABLE OF ty_size_0302.

  REFRESH gt_files_preview.
  IF gv_file_scope IS INITIAL.
    gv_file_scope = gc_file_scope_my.
  ENDIF.

  "Default UX: own uploads first; shared audit history stays one click away.
  IF gv_file_scope = gc_file_scope_my.
    SELECT session_id created_by
      INTO CORRESPONDING FIELDS OF TABLE lt_owner_raw
      FROM zbdc_session_bup
      WHERE created_by = sy-uname.

    LOOP AT lt_owner_raw INTO DATA(ls_my_owner).
      INSERT VALUE #( session_id = ls_my_owner-session_id )
        INTO TABLE lt_my_sid.
    ENDLOOP.

    "Keep just-uploaded sessions visible before summary persistence finishes.
    LOOP AT gt_current_sessions INTO DATA(lv_current_sid).
      INSERT VALUE #( session_id = lv_current_sid )
        INTO TABLE lt_my_sid.
    ENDLOOP.

    IF lt_my_sid IS NOT INITIAL.
      SELECT *
        INTO TABLE lt_file_lg
        FROM zbdc_file_lg_bup
        FOR ALL ENTRIES IN lt_my_sid
        WHERE session_id = lt_my_sid-session_id.
    ENDIF.
  ELSE.
    SELECT *
      FROM zbdc_file_lg_bup
      ORDER BY processed_at DESCENDING, file_name ASCENDING
      INTO TABLE @lt_file_lg
      UP TO 300 ROWS.
  ENDIF.

  SORT lt_file_lg BY processed_at DESCENDING file_name ASCENDING.

  "Limit only the visual list; database history remains untouched.
  lv_max_rows = 200.
  lv_line_count = lines( lt_file_lg ).
  IF lv_line_count > lv_max_rows.
    lv_delete_from = lv_max_rows + 1.
    DELETE lt_file_lg FROM lv_delete_from TO lv_line_count.
  ENDIF.

  "Resolve owners in one database read, not one SELECT SINGLE per row.
  LOOP AT lt_file_lg INTO DATA(ls_file_sid).
    IF ls_file_sid-session_id IS NOT INITIAL.
      INSERT VALUE #( session_id = ls_file_sid-session_id )
        INTO TABLE lt_lookup_sid.
    ENDIF.
  ENDLOOP.

  IF lt_lookup_sid IS NOT INITIAL.
    REFRESH lt_owner_raw.
    SELECT session_id created_by
      INTO CORRESPONDING FIELDS OF TABLE lt_owner_raw
      FROM zbdc_session_bup
      FOR ALL ENTRIES IN lt_lookup_sid
      WHERE session_id = lt_lookup_sid-session_id.

    LOOP AT lt_owner_raw INTO DATA(ls_owner_raw).
      DATA ls_owner_conv TYPE ty_owner_0302.
      CLEAR ls_owner_conv.
      ls_owner_conv-session_id = ls_owner_raw-session_id.
      ls_owner_conv-created_by = ls_owner_raw-created_by.
      INSERT ls_owner_conv INTO TABLE lt_owner.
    ENDLOOP.

    SELECT session_id message created_at
      INTO CORRESPONDING FIELDS OF TABLE lt_size_log
      FROM zbdc_result_bup
      FOR ALL ENTRIES IN lt_lookup_sid
      WHERE session_id = lt_lookup_sid-session_id
        AND record_key = '__SOURCE__'.

    SORT lt_size_log BY session_id created_at DESCENDING.
  ENDIF.

  LOOP AT lt_file_lg INTO DATA(ls_file_lg).
    CLEAR: ls_meta, lv_date, lv_time, lv_user, lv_cnt,
           lv_file_title, lv_source_txt, lv_owned.

    ls_meta-file_name  = ls_file_lg-file_name.
    ls_meta-channel    = ls_file_lg-source.
    ls_meta-session_id = ls_file_lg-session_id.
    ls_meta-raw_status = ls_file_lg-status.
    ls_meta-raw_error  = ls_file_lg-error_msg.

    PERFORM z16_batch_prefix_from_sid
      USING    ls_file_lg-session_id
      CHANGING ls_meta-batch_key.

    PERFORM z16_split_unit_name
      USING    ls_file_lg-file_name
      CHANGING ls_meta-file_title ls_meta-sheet_name.

    SELECT SINGLE tcode
      FROM zbdc_staging_bup
      WHERE session_id = @ls_file_lg-session_id
      INTO @ls_meta-tx_code.

    IF ls_meta-tx_code IS INITIAL.
      ls_meta-tx_code = p_transaction.
    ENDIF.

    IF ls_meta-sheet_name = 'DATA'.
      CLEAR ls_meta-sheet_name.
    ENDIF.
    ls_meta-data_unit = 'File/Sheet'.

    lv_cnt = ls_file_lg-row_count.
    ls_meta-rows_loaded = lv_cnt.

    CLEAR: lv_source_msg, lv_size_text, lv_size_tail.
    READ TABLE lt_size_log INTO DATA(ls_size_log)
      WITH KEY session_id = ls_file_lg-session_id.
    IF sy-subrc = 0.
      lv_source_msg = ls_size_log-message.
      IF lv_source_msg CS ';SIZE='.
        SPLIT lv_source_msg AT ';SIZE='
          INTO lv_size_tail lv_size_text.
        IF lv_size_text CS ';'.
          SPLIT lv_size_text AT ';'
            INTO lv_size_text lv_size_tail.
        ENDIF.
        CONDENSE lv_size_text.
      ENDIF.
    ENDIF.

    lv_size_check = lv_size_text.
    TRANSLATE lv_size_check TO UPPER CASE.
    IF lv_size_check CS 'ROW' OR
       ( lv_size_check NS ' B' AND
         lv_size_check NS ' KB' AND
         lv_size_check NS ' MB' ).
      CLEAR lv_size_text.
    ENDIF.

    IF lv_size_text IS INITIAL.
      ls_meta-file_size = 'Unknown'.
    ELSE.
      ls_meta-file_size = lv_size_text.
    ENDIF.

    PERFORM z23_recalc_frontend_size USING ls_file_lg-file_name CHANGING ls_meta-file_size.

    IF strlen( ls_file_lg-processed_at ) >= 14.
      lv_date = ls_file_lg-processed_at+0(8).
      lv_time = ls_file_lg-processed_at+8(6).
    ELSEIF strlen( ls_file_lg-processed_at ) >= 8.
      lv_date = ls_file_lg-processed_at+0(8).
      lv_time = '000000'.
    ENDIF.

    ls_meta-upload_date = lv_date.
    ls_meta-upload_time = lv_time.

    IF lv_date IS NOT INITIAL.
      ls_meta-processed_on =
        |{ lv_date+6(2) }.{ lv_date+4(2) }.{ lv_date+0(4) } { lv_time+0(2) }:{ lv_time+2(2) }:{ lv_time+4(2) }|.
    ELSE.
      ls_meta-processed_on = '-'.
    ENDIF.

    IF ls_meta-file_title IS INITIAL.
      PERFORM z16_extract_file_title
        USING    ls_file_lg-file_name
        CHANGING ls_meta-file_title.
    ENDIF.

    CASE ls_file_lg-source.
      WHEN 'LOCAL' OR 'LOCAL_INGESTION'.
        lv_source_txt = 'Local Upload'.
      WHEN 'SFTP' OR 'SFTP_INGESTION'.
        lv_source_txt = 'SFTP Poll'.
      WHEN 'GDRIVE' OR 'GDRIVE_INGESTION'.
        lv_source_txt = 'Google Drive'.
      WHEN 'REST' OR 'REST_INGESTION'.
        lv_source_txt = 'REST API'.
      WHEN 'EMAIL' OR 'EMAIL_INGESTION'.
        lv_source_txt = 'Email Inbox'.
      WHEN OTHERS.
        lv_source_txt = ls_file_lg-source.
    ENDCASE.
    ls_meta-source_text = lv_source_txt.

    READ TABLE lt_owner INTO DATA(ls_owner)
      WITH TABLE KEY session_id = ls_file_lg-session_id.
    IF sy-subrc = 0.
      lv_user = ls_owner-created_by.
    ELSE.
      READ TABLE gt_current_sessions
        WITH KEY table_line = ls_file_lg-session_id
        TRANSPORTING NO FIELDS.
      IF sy-subrc = 0.
        lv_user = sy-uname.
      ELSE.
        lv_user = 'UNKNOWN'.
      ENDIF.
    ENDIF.

    ls_meta-username = lv_user.
    ls_meta-owner    = lv_user.

    IF lv_user = sy-uname.
      lv_owned = abap_true.
    ENDIF.

    IF gv_file_scope = gc_file_scope_my
       AND lv_owned <> abap_true.
      CONTINUE.
    ENDIF.

    IF ls_file_lg-status IS INITIAL.
      ls_meta-status_text = 'IMPORTED'.
    ELSE.
      ls_meta-status_text = ls_file_lg-status.
    ENDIF.

    CASE ls_meta-status_text.
      WHEN 'ERROR' OR 'FAILED'.
        ls_meta-status_icon = icon_red_light.
        ls_meta-next_action = 'Open log / fix source'.
      WHEN 'WARNING' OR 'PARTIAL'.
        ls_meta-status_icon = icon_yellow_light.
        ls_meta-next_action = 'Review data then validate'.
      WHEN 'IMPORTED' OR 'UPLOADED' OR 'READY' OR 'SUCCESS'.
        ls_meta-status_icon = icon_green_light.
        IF lv_cnt > 0.
          ls_meta-next_action = 'Double-click to preview'.
        ELSE.
          ls_meta-next_action = 'Template / no data'.
        ENDIF.
      WHEN 'PROCESSING' OR 'SM35QUEUE'.
        ls_meta-status_icon = icon_yellow_light.
        ls_meta-next_action = 'Monitor current processing'.
      WHEN OTHERS.
        ls_meta-status_icon = icon_yellow_light.
        ls_meta-next_action = 'Review file/source'.
    ENDCASE.

    APPEND ls_meta TO gt_files_preview.
  ENDLOOP.
ENDFORM.
*<<< END FORM z16_prepare_preview_file

*>>> FORM z16_refresh_0302_scope - moved from Z_BDC_MASS_PO_ENTRY_F01_BUP

FORM z16_refresh_0302_scope.
  DATA: lv_header      TYPE lvc_title,
        lv_show_owner  TYPE abap_bool.

  IF go_grid_0302 IS NOT BOUND.
    RETURN.
  ENDIF.

  IF gv_file_scope = gc_file_scope_all.
    lv_header = |All Uploads - shared history ({ lines( gt_files_preview ) }); double-click to preview|.
    lv_show_owner = abap_true.
  ELSE.
    lv_header = |My Uploads ({ lines( gt_files_preview ) }) - latest files first|.
    lv_show_owner = abap_false.
  ENDIF.

  TRY.
      go_grid_0302->get_display_settings( )->set_list_header( lv_header ).
      go_grid_0302->get_columns( )->get_column( 'OWNER' )->set_visible( lv_show_owner ).
      go_grid_0302->refresh( refresh_mode = if_salv_c_refresh=>full ).
    CATCH cx_root.
  ENDTRY.

  IF gv_file_scope = gc_file_scope_all.
    MESSAGE |All Uploads: { lines( gt_files_preview ) } recent rows. Run/Resubmit/Retry obtains an exclusive batch lock.| TYPE 'S'.
  ELSE.
    MESSAGE |My Uploads: { lines( gt_files_preview ) } file/source rows.| TYPE 'S'.
  ENDIF.
ENDFORM.
*<<< END FORM z16_refresh_0302_scope

*>>> FORM z16_0300_after_ingest - moved from Z_BDC_MASS_PO_ENTRY_F01_BUP

FORM z16_0300_after_ingest USING iv_source TYPE char20.
  DATA: lv_total TYPE i,
        lv_error TYPE i,
        lv_ready TYPE i,
        lv_warn  TYPE i,
        lv_sess  TYPE zbdc_staging_bup-session_id.

  lv_total = lines( gt_staging ).
  CLEAR: lv_error, lv_ready, lv_warn, lv_sess.

  LOOP AT gt_staging INTO DATA(ls_stg_sum).
    IF lv_sess IS INITIAL.
      lv_sess = ls_stg_sum-session_id.
    ENDIF.
    CASE ls_stg_sum-status.
      WHEN 'ERROR'.
        lv_error = lv_error + 1.
      WHEN 'WARNING'.
        lv_warn = lv_warn + 1.
      WHEN OTHERS.
        lv_ready = lv_ready + 1.
    ENDCASE.
  ENDLOOP.

  WRITE lv_total TO txtp_row_count LEFT-JUSTIFIED.
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

  IF lv_total > 0.
    "Build the business preview NOW while GT_STAGING is known to contain the
    "new upload.  The visible SALV may still be the startup instance created
    "with an empty table; the rebuild itself is therefore deferred to the next
    "normal STATUS_0301 PBO instead of being performed inside the upload PAI.
    PERFORM z16_build_preview_rows.

    "V5DB: after ingest stay on Preview Data.  Do not hop through 0302 and
    "do not queue a synthetic PREV command.  Mark the existing 0301 SALV for
    "one controlled rebuild in the next normal 0301 PBO, where the frontend
    "control can be safely destroyed and recreated from the new 13+ rows.
    g_sub_dynpro = '0301'.
    ts_preview-activetab = 'TAB_PREVIEW'.
    gv_rebuild_0301 = abap_true.

    IF lv_error > 0 OR lv_warn > 0.
      MESSAGE |{ iv_source }: session { lv_sess } loaded { lv_total } rows; ready { lv_ready }, warning { lv_warn }, error { lv_error }.| TYPE 'S' DISPLAY LIKE 'W'.
    ELSE.
      MESSAGE |{ iv_source }: session { lv_sess } loaded { lv_total } rows. Preview Data is ready.| TYPE 'S'.
    ENDIF.
  ENDIF.
ENDFORM.

*&---------------------------------------------------------------------*
*& SCREEN FLOW HELPERS - make 0100/0200/0300/0400 connected
*&---------------------------------------------------------------------*
*<<< END FORM z16_0300_after_ingest

*>>> FORM z16_clear_0300_runtime - moved from Z_BDC_MASS_PO_ENTRY_F01_BUP

FORM z16_clear_0300_runtime.
  "Fresh Upload Center: clear only runtime preview buffers, never delete persisted DB history.
  REFRESH: gt_staging, gt_errors, gt_preview_data, gt_files_preview, gt_current_sessions.
  CLEAR: txtp_file_path, txtp_file_size, txtp_row_count, txtp_row, txtp_rows,
         txtp_loaded, txtp_rows_loaded, txtp_loaded_rows,
         txtgv_row_count, txtgv_rows, txtgv_loaded, txtgv_total_rows, txtgv_tot_rows,
         gv_current_batch_prefix, gv_ingest_batch_prefix, gv_forced_session_id,
         gv_current_batch_count, gv_current_file_name, gv_current_sheet_name,
         gv_current_unit_src.
  g_sub_dynpro = '0301'.
  ts_preview-activetab = 'TAB_PREVIEW'.
  PERFORM z16_reset_0300_all_alv.
ENDFORM.
*<<< END FORM z16_clear_0300_runtime
