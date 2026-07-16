*&---------------------------------------------------------------------*
*& Include          ZBDC_MPE_M2_MAP_BUP
*& Purpose          M2 Recording Manager + Mapping + BDCDATA builder
*& Source split     FIX16 V5BR - logic moved from F01
*&---------------------------------------------------------------------*

*>>> FORM z23_download_gdrive_script_csv - moved from Z_BDC_MASS_PO_ENTRY_F01_BUP
FORM z23_download_gdrive_script_csv.
  DATA: lo_client      TYPE REF TO if_http_client,
        lv_code        TYPE i,
        lv_url         TYPE string,
        lv_base_url    TYPE string,
        lv_dummy       TYPE string,
        lv_resp        TYPE string,
        lt_raw         TYPE string_table,
        lv_before      TYPE i,
        lv_after       TYPE i,
        lv_loaded      TYPE i,
        lv_bytes       TYPE i,
        lv_session_id  TYPE zbdc_staging_bup-session_id,
        ls_meta        TYPE ty_files_disp,
        lv_unit_name   TYPE string,
        lv_file_name   TYPE string,
        lv_tcode       TYPE string.

  lv_base_url = txtp_gdrive_url.
  CONDENSE lv_base_url NO-GAPS.

  IF lv_base_url IS INITIAL.
    MESSAGE 'GDRIVE_URL is missing. Maintain Apps Script /exec URL first.' TYPE 'E'.
    RETURN.
  ENDIF.

  IF lv_base_url CS '?'.
    SPLIT lv_base_url AT '?' INTO lv_base_url lv_dummy.
  ENDIF.

  IF p_transaction IS INITIAL.
    p_transaction = 'ME21N'.
  ENDIF.

  lv_tcode = p_transaction.
  TRANSLATE lv_tcode TO UPPER CASE.
  lv_url = lv_base_url && '?action=csv&tcode=' && lv_tcode.
  IF gv_gdrive_token IS NOT INITIAL.
    lv_url = lv_url && '&code=' && gv_gdrive_token.
  ENDIF.

  cl_http_client=>create_by_url( EXPORTING url = lv_url IMPORTING client = lo_client EXCEPTIONS OTHERS = 1 ).
  IF sy-subrc <> 0.
    MESSAGE 'Cannot create HTTP client for Apps Script CSV endpoint.' TYPE 'E'.
    RETURN.
  ENDIF.

  lo_client->request->set_method( 'GET' ).
  lo_client->propertytype_redirect = lo_client->co_enabled.
  lo_client->send( EXCEPTIONS OTHERS = 1 ).
  lo_client->receive( EXCEPTIONS OTHERS = 1 ).
  lo_client->response->get_status( IMPORTING code = lv_code ).
  lv_resp = lo_client->response->get_cdata( ).
  lo_client->close( ).

  IF lv_code <> 200.
    IF lv_code = 403.
      MESSAGE 'Apps Script CSV endpoint HTTP 403. Re-deploy Web App as Me/Anyone and use /exec URL.' TYPE 'E'.
    ELSE.
      MESSAGE |Apps Script CSV endpoint HTTP { lv_code }.| TYPE 'E'.
    ENDIF.
    RETURN.
  ENDIF.

  IF lv_resp IS INITIAL.
    MESSAGE 'Apps Script CSV endpoint returned empty response.' TYPE 'E'.
    RETURN.
  ENDIF.

  IF lv_resp CS '<html' OR lv_resp CS '<!DOCTYPE' OR lv_resp CS '<body'.
    MESSAGE 'Apps Script returned HTML, not CSV. Test /exec?action=csv&tcode=... in browser and deploy latest version.' TYPE 'E'.
    RETURN.
  ENDIF.

  REFRESH gt_staging.
  PERFORM z16_start_ingest_batch.
  PERFORM z16_make_batch_session USING 1 CHANGING lv_session_id.

  gv_forced_session_id = lv_session_id.
  lv_file_name = lv_tcode && '_AppsScript.csv'.
  gv_current_file_name  = lv_file_name.
  gv_current_sheet_name = 'DATA'.
  gv_current_unit_src   = 'GDRIVE'.
  txtp_file_path        = 'GoogleDrive://' && lv_file_name.

  REPLACE ALL OCCURRENCES OF cl_abap_char_utilities=>cr_lf
          IN lv_resp WITH cl_abap_char_utilities=>newline.
  REFRESH lt_raw.
  SPLIT lv_resp AT cl_abap_char_utilities=>newline INTO TABLE lt_raw.

  lv_bytes = strlen( lv_resp ).
  PERFORM z23_format_file_size USING lv_bytes CHANGING txtp_file_size.

  lv_before = lines( gt_staging ).
  PERFORM process_csv_rows USING lt_raw.
  lv_after = lines( gt_staging ).
  lv_loaded = lv_after - lv_before.

  CLEAR: gv_forced_session_id, gv_current_file_name, gv_current_sheet_name, gv_current_unit_src.
  PERFORM z16_finish_ingest_batch.

  IF lv_loaded <= 0.
    MESSAGE 'Apps Script CSV loaded but no valid staging rows were parsed. Check headers/template.' TYPE 'E'.
    RETURN.
  ENDIF.

  MODIFY zbdc_staging_bup FROM TABLE gt_staging.

  PERFORM z16_compose_unit_name USING lv_file_name 'DATA' CHANGING lv_unit_name.
  PERFORM save_ingestion_source_log USING lv_session_id 'GDRIVE' lv_unit_name.
  PERFORM update_session_summary USING lv_session_id.
  PERFORM z16_register_current_session USING lv_session_id.

  CLEAR ls_meta.
  ls_meta-file_name   = lv_unit_name.
  PERFORM z16_split_unit_name USING lv_unit_name CHANGING ls_meta-file_title ls_meta-sheet_name.
  ls_meta-file_size   = txtp_file_size.
  ls_meta-rows_loaded = lv_loaded.
  ls_meta-channel     = 'GDRIVE_INGESTION'.
  ls_meta-upload_date = sy-datum.
  ls_meta-upload_time = sy-uzeit.
  ls_meta-username    = sy-uname.
  ls_meta-session_id  = lv_session_id.
  ls_meta-tx_code     = p_transaction.
  APPEND ls_meta TO gt_files_preview.

  COMMIT WORK AND WAIT.
  PERFORM z16_set_row_count_fields USING lv_loaded.
  PERFORM z16_prepare_preview_file.

  MESSAGE |Google Drive Apps Script CSV loaded { lv_loaded } row(s).| TYPE 'S'.
ENDFORM.

*&---------------------------------------------------------------------*
*& Form DOWNLOAD_FROM_GDRIVE_FILE
*&---------------------------------------------------------------------*
*<<< END FORM z23_download_gdrive_script_csv

*>>> FORM BDC_DYNPRO - moved from Z_BDC_MASS_PO_ENTRY_F01_BUP

FORM BDC_DYNPRO USING PROGRAM DYNPRO.
  CLEAR BDCDATA. BDCDATA-PROGRAM = PROGRAM. BDCDATA-DYNPRO = DYNPRO. BDCDATA-DYNBEGIN = 'X'. APPEND BDCDATA.
ENDFORM.
*<<< END FORM BDC_DYNPRO

*>>> FORM BDC_FIELD - moved from Z_BDC_MASS_PO_ENTRY_F01_BUP

FORM BDC_FIELD USING FNAM FVAL.
  IF FVAL IS NOT INITIAL. CLEAR BDCDATA. BDCDATA-FNAM = FNAM. BDCDATA-FVAL = FVAL. APPEND BDCDATA. ENDIF.
ENDFORM.


*&---------------------------------------------------------------------*
*& V5AV - ME21N GUI-safe BDC guard and item-grid fallback
*&---------------------------------------------------------------------*
*<<< END FORM BDC_FIELD

*>>> FORM z26_process_has_tcode - moved from Z_BDC_MASS_PO_ENTRY_F01_BUP
FORM z26_process_has_tcode
  USING    pt_process TYPE ty_t_staging_alv
           pv_tcode   TYPE sy-tcode
  CHANGING cv_has     TYPE abap_bool.

  DATA ls_row TYPE ty_staging_alv.
  DATA lv_row_tcode  TYPE sy-tcode.
  DATA lv_find_tcode TYPE sy-tcode.

  CLEAR cv_has.
  lv_find_tcode = pv_tcode.
  TRANSLATE lv_find_tcode TO UPPER CASE.
  CONDENSE lv_find_tcode NO-GAPS.

  LOOP AT pt_process INTO ls_row.
    lv_row_tcode = ls_row-tcode.
    IF lv_row_tcode IS INITIAL.
      lv_row_tcode = p_transaction.
    ENDIF.
    TRANSLATE lv_row_tcode TO UPPER CASE.
    CONDENSE lv_row_tcode NO-GAPS.
    IF lv_row_tcode = lv_find_tcode.
      cv_has = abap_true.
      RETURN.
    ENDIF.
  ENDLOOP.
ENDFORM.
*<<< END FORM z26_process_has_tcode

*>>> FORM z26_get_map_value - moved from Z_BDC_MASS_PO_ENTRY_F01_BUP

FORM z26_get_map_value
  USING    pt_map       TYPE ty_t_map
           ps_row       TYPE ty_staging_alv
           pv_bdc_field TYPE csequence
  CHANGING cv_value     TYPE string.

  DATA ls_map TYPE zbdc_mapping_bup.
  FIELD-SYMBOLS <lv_any> TYPE any.

  CLEAR cv_value.
  LOOP AT pt_map INTO ls_map WHERE bdc_field = pv_bdc_field.
    IF ls_map-staging_field IS INITIAL.
      CONTINUE.
    ENDIF.
    ASSIGN COMPONENT ls_map-staging_field OF STRUCTURE ps_row TO <lv_any>.
    IF sy-subrc = 0 AND <lv_any> IS ASSIGNED.
      cv_value = <lv_any>.
      CONDENSE cv_value.
      IF cv_value IS NOT INITIAL.
        RETURN.
      ENDIF.
    ENDIF.
  ENDLOOP.
ENDFORM.
*<<< END FORM z26_get_map_value

*>>> FORM z26_bdc_has_me21n_item - moved from Z_BDC_MASS_PO_ENTRY_F01_BUP

FORM z26_bdc_has_me21n_item
  CHANGING cv_has TYPE abap_bool.

  DATA ls_bdc TYPE bdcdata.
  CLEAR cv_has.
  LOOP AT bdcdata INTO ls_bdc WHERE dynbegin IS INITIAL.
    IF ls_bdc-fnam CS 'MEPO1211-' OR
       ls_bdc-fnam CS 'EKPO-' OR
       ls_bdc-fnam CS 'MEREQ3211-'.
      cv_has = abap_true.
      RETURN.
    ENDIF.
  ENDLOOP.
ENDFORM.
*<<< END FORM z26_bdc_has_me21n_item

*>>> FORM z26_build_me21n_fallback_bdc - moved from Z_BDC_MASS_PO_ENTRY_F01_BUP

FORM z26_build_me21n_fallback_bdc
  USING    pt_group TYPE ty_t_staging_alv
           pt_map   TYPE ty_t_map
  CHANGING cv_ok    TYPE abap_bool
           cv_msg   TYPE string.

  DATA: ls_first TYPE ty_staging_alv,
        ls_item  TYPE ty_staging_alv,
        lv_idx   TYPE c LENGTH 2,
        lv_i     TYPE i,
        lv_lifnr TYPE string,
        lv_ekorg TYPE string,
        lv_ekgrp TYPE string,
        lv_bukrs TYPE string,
        lv_matnr TYPE string,
        lv_menge TYPE string,
        lv_meins TYPE string,
        lv_netpr TYPE string,
        lv_werks TYPE string,
        lv_fnam  TYPE bdcdata-fnam,
        lv_item_ok TYPE abap_bool.

  CLEAR: cv_ok, cv_msg, lv_item_ok.
  READ TABLE pt_group INTO ls_first INDEX 1.
  IF sy-subrc <> 0.
    cv_msg = 'ME21N fallback cannot build BDCDATA: document group is empty.'.
    RETURN.
  ENDIF.

  PERFORM z26_get_map_value USING pt_map ls_first 'EKKO-LIFNR' CHANGING lv_lifnr.
  PERFORM z26_get_map_value USING pt_map ls_first 'EKKO-EKORG' CHANGING lv_ekorg.
  PERFORM z26_get_map_value USING pt_map ls_first 'EKKO-EKGRP' CHANGING lv_ekgrp.
  PERFORM z26_get_map_value USING pt_map ls_first 'EKKO-BUKRS' CHANGING lv_bukrs.

  IF lv_lifnr IS INITIAL OR lv_ekorg IS INITIAL OR lv_ekgrp IS INITIAL.
    cv_msg = 'ME21N fallback blocked: vendor / purchasing org / purchasing group is missing in mapping or staging.'.
    RETURN.
  ENDIF.

  REFRESH bdcdata.

  "Header: the user's system records ME21N on SAPLMEGUI/0013. Keep the
  "sequence GUI-safe and compatible with Display-errors-only / Foreground.
  PERFORM bdc_dynpro USING 'SAPLMEGUI' '0013'.
  PERFORM bdc_field  USING 'BDC_OKCODE' '/00'.
  PERFORM bdc_field  USING 'MEPO_TOPLINE-SUPERFIELD' lv_lifnr.

  PERFORM bdc_dynpro USING 'SAPLMEGUI' '0013'.
  PERFORM bdc_field  USING 'BDC_OKCODE' '/00'.
  PERFORM bdc_field  USING 'MEPO1222-EKORG' lv_ekorg.
  PERFORM bdc_field  USING 'MEPO1222-EKGRP' lv_ekgrp.
  PERFORM bdc_field  USING 'MEPO1222-BUKRS' lv_bukrs.

  CLEAR lv_i.
  LOOP AT pt_group INTO ls_item.
    CLEAR: lv_matnr, lv_menge, lv_meins, lv_netpr, lv_werks.
    PERFORM z26_get_map_value USING pt_map ls_item 'EKPO-MATNR' CHANGING lv_matnr.
    PERFORM z26_get_map_value USING pt_map ls_item 'EKPO-MENGE' CHANGING lv_menge.
    PERFORM z26_get_map_value USING pt_map ls_item 'EKPO-MEINS' CHANGING lv_meins.
    PERFORM z26_get_map_value USING pt_map ls_item 'EKPO-NETPR' CHANGING lv_netpr.
    PERFORM z26_get_map_value USING pt_map ls_item 'EKPO-WERKS' CHANGING lv_werks.

    IF lv_matnr IS INITIAL OR lv_menge IS INITIAL OR lv_werks IS INITIAL.
      CONTINUE.
    ENDIF.

    lv_item_ok = abap_true.
    lv_i = lv_i + 1.
    lv_idx = lv_i.

    PERFORM bdc_dynpro USING 'SAPLMEGUI' '0013'.
    PERFORM bdc_field  USING 'BDC_OKCODE' '/00'.

    lv_fnam = |MEPO1211-EMATN({ lv_idx })|.
    PERFORM bdc_field USING 'BDC_CURSOR' lv_fnam.
    PERFORM bdc_field USING lv_fnam lv_matnr.

    lv_fnam = |MEPO1211-MENGE({ lv_idx })|.
    PERFORM bdc_field USING lv_fnam lv_menge.

    IF lv_meins IS NOT INITIAL.
      lv_fnam = |MEPO1211-MEINS({ lv_idx })|.
      PERFORM bdc_field USING lv_fnam lv_meins.
    ENDIF.

    IF lv_netpr IS NOT INITIAL.
      lv_fnam = |MEPO1211-NETPR({ lv_idx })|.
      PERFORM bdc_field USING lv_fnam lv_netpr.
    ENDIF.

    "In many ME21N SHDB recordings the item overview plant column is exposed
    "as MEPO1211-NAME1, not EKPO-WERKS. This matches the existing project
    "recording and prevents the old 'Document contains no items' case.
    lv_fnam = |MEPO1211-NAME1({ lv_idx })|.
    PERFORM bdc_field USING lv_fnam lv_werks.
  ENDLOOP.

  IF lv_item_ok <> abap_true.
    cv_msg = |ME21N fallback blocked: no item has material, quantity and plant for group { ls_first-record_key }.|.
    RETURN.
  ENDIF.

  PERFORM bdc_dynpro USING 'SAPLMEGUI' '0013'.
  PERFORM bdc_field  USING 'BDC_OKCODE' '=MESAVE'.

  cv_ok  = abap_true.
  cv_msg = |ME21N fallback BDCDATA built with { lv_i } item(s).|.
ENDFORM.
*<<< END FORM z26_build_me21n_fallback_bdc

*>>> FORM z26_repair_me21n_bdc - moved from Z_BDC_MASS_PO_ENTRY_F01_BUP

FORM z26_repair_me21n_bdc
  USING    pv_tcode   TYPE sy-tcode
           pt_group   TYPE ty_t_staging_alv
           pt_map     TYPE ty_t_map
  CHANGING cv_rebuilt TYPE abap_bool
           cv_msg     TYPE string.

  DATA lv_has_item TYPE abap_bool.
  DATA lv_ok       TYPE abap_bool.
  DATA lv_msg      TYPE string.

  CLEAR: cv_rebuilt, cv_msg.
  IF pv_tcode <> 'ME21N'.
    RETURN.
  ENDIF.

  PERFORM z26_bdc_has_me21n_item CHANGING lv_has_item.
  IF lv_has_item = abap_true.
    RETURN.
  ENDIF.

  PERFORM z26_build_me21n_fallback_bdc
    USING    pt_group pt_map
    CHANGING lv_ok lv_msg.

  IF lv_ok = abap_true.
    cv_rebuilt = abap_true.
    cv_msg = lv_msg.
  ELSE.
    cv_msg = lv_msg.
  ENDIF.
ENDFORM.

*&=====================================================================*
*&=====================================================================*
*&=====================================================================*
*&        MUC 2 - BDC GENERIC ENGINE 10/10 (PHASE 4-5-6-7-8)           *
*&  Dynamic script execution + multi-item grouping + lock retry         *
*&  + chunk commit + Batch Input Session + SHDB upload + clean log      *
*&=====================================================================*
*&=====================================================================*

*&---------------------------------------------------------------------*
*& V5AG - Open a Batch Input Session with bounded transient retry
*&---------------------------------------------------------------------*
*<<< END FORM z26_repair_me21n_bdc

*>>> FORM RESOLVE_PROFILE_BY_TCODE - moved from Z_BDC_MASS_PO_ENTRY_F01_BUP
FORM RESOLVE_PROFILE_BY_TCODE USING IV_TCODE TYPE CHAR20.
  DATA LV_TCODE TYPE CHAR20.

  LV_TCODE = IV_TCODE.
  TRANSLATE LV_TCODE TO UPPER CASE.
  CONDENSE LV_TCODE NO-GAPS.

  IF LV_TCODE = 'MIGO'.
    TXTP_PROFILE_NAME = GC_PROF_MIGO.
  ELSE.
    TXTP_PROFILE_NAME = GC_PROF_ME21N.
  ENDIF.
ENDFORM.
*<<< END FORM RESOLVE_PROFILE_BY_TCODE

*>>> FORM GET_RUNTIME_OPTIONS - moved from Z_BDC_MASS_PO_ENTRY_F01_BUP
FORM GET_RUNTIME_OPTIONS CHANGING CV_MODE  TYPE C
                                  CV_UPD   TYPE C
                                  CV_BSIZE TYPE I.
  DATA LV_BSIZE_CHAR TYPE CHAR10.

  PERFORM LOAD_SOURCE_CONFIG.

  IF RB_MODE_A = 'X'.
    CV_MODE = 'A'.
  ELSEIF RB_MODE_E = 'X'.
    CV_MODE = 'E'.
  ELSE.
    CV_MODE = 'N'.
  ENDIF.

  IF RB_UPD_S = 'X'.
    CV_UPD = 'S'.
  ELSE.
    CV_UPD = 'A'.
  ENDIF.

  "V5AY: a short-lived runtime override is used only by the evidence-based
  "SM35 fallback. LOAD_SOURCE_CONFIG may reload the persisted N/A/E profile,
  "so the fallback must have an explicit, scoped way to enforce GUI-safe E
  "without changing the user's saved six-combination setup.
  IF GV_RUNTIME_MODE_OVERRIDE = 'A' OR
     GV_RUNTIME_MODE_OVERRIDE = 'E' OR
     GV_RUNTIME_MODE_OVERRIDE = 'N'.
    CV_MODE = GV_RUNTIME_MODE_OVERRIDE.
  ENDIF.

  IF GV_RUNTIME_UPD_OVERRIDE = 'S' OR
     GV_RUNTIME_UPD_OVERRIDE = 'A'.
    CV_UPD = GV_RUNTIME_UPD_OVERRIDE.
  ENDIF.

  LV_BSIZE_CHAR = TXTP_BATCH_SIZE.
  CONDENSE LV_BSIZE_CHAR NO-GAPS.
  IF LV_BSIZE_CHAR IS INITIAL.
    CV_BSIZE = GC_BATCH_DEFAULT.
  ELSE.
    CV_BSIZE = LV_BSIZE_CHAR.
  ENDIF.

  IF CV_BSIZE <= 0.
    CV_BSIZE = GC_BATCH_DEFAULT.
  ENDIF.
ENDFORM.

*&---------------------------------------------------------------------*
*& LOAD_SCRIPT_DEFINITION - doc script va tach PRE / ITEM / POST
*& Quy uoc:
*&   - ROW_TYPE = 'I' la item block, duoc lap theo tung item
*&   - Header truoc item = PRE
*&   - Header sau item  = POST
*&---------------------------------------------------------------------*
*<<< END FORM GET_RUNTIME_OPTIONS

*>>> FORM LOAD_SCRIPT_DEFINITION - moved from Z_BDC_MASS_PO_ENTRY_F01_BUP
FORM LOAD_SCRIPT_DEFINITION
  USING    PV_TCODE TYPE SY-TCODE
  CHANGING CT_PRE   TYPE TY_T_SCRIPT
           CT_ITEM  TYPE TY_T_SCRIPT
           CT_POST  TYPE TY_T_SCRIPT.

  DATA: LT_SCRIPT TYPE TY_T_SCRIPT,
        LS_SCR    TYPE ZBDC_SCT_DEF_BUP,
        LV_SEEN_I TYPE ABAP_BOOL.

  REFRESH: CT_PRE, CT_ITEM, CT_POST.

  SELECT * FROM ZBDC_SCT_DEF_BUP
    WHERE TCODE = @PV_TCODE
    ORDER BY STEP_SEQ
    INTO TABLE @LT_SCRIPT.

  LV_SEEN_I = ABAP_FALSE.
  LOOP AT LT_SCRIPT INTO LS_SCR.
    IF LS_SCR-ROW_TYPE = GC_RT_ITEM.
      LV_SEEN_I = ABAP_TRUE.
      APPEND LS_SCR TO CT_ITEM.
    ELSEIF LV_SEEN_I = ABAP_FALSE.
      APPEND LS_SCR TO CT_PRE.
    ELSE.
      APPEND LS_SCR TO CT_POST.
    ENDIF.
  ENDLOOP.
ENDFORM.

*&---------------------------------------------------------------------*
*& LOAD_MAPPING_PROFILE - mapping theo transaction
*&---------------------------------------------------------------------*
*<<< END FORM LOAD_SCRIPT_DEFINITION

*>>> FORM LOAD_MAPPING_PROFILE - moved from Z_BDC_MASS_PO_ENTRY_F01_BUP
FORM LOAD_MAPPING_PROFILE
  USING    PV_TCODE TYPE SY-TCODE
  CHANGING CT_MAP   TYPE TY_T_MAP.

  REFRESH CT_MAP.

  IF PV_TCODE = 'MIGO'.
    TXTP_PROFILE_NAME = GC_PROF_MIGO.
  ELSE.
    TXTP_PROFILE_NAME = GC_PROF_ME21N.
  ENDIF.

  SELECT * FROM ZBDC_MAPPING_BUP
    WHERE PROFILE_NAME = @TXTP_PROFILE_NAME
    INTO TABLE @CT_MAP.
ENDFORM.

*&---------------------------------------------------------------------*
*& V5Q - Managed Batch Input profile: A/E/N x S/A
*&---------------------------------------------------------------------*
*&---------------------------------------------------------------------*
*& V5AT - Managed Batch Input profile: display mode N/E/A x update A/S
*&---------------------------------------------------------------------*
*<<< END FORM LOAD_MAPPING_PROFILE

*>>> FORM APPEND_SCRIPT_STEP - moved from Z_BDC_MASS_PO_ENTRY_F01_BUP
FORM APPEND_SCRIPT_STEP USING PS_SCR TYPE ZBDC_SCT_DEF_BUP
                              PS_ROW TYPE TY_STAGING_ALV
                              PT_MAP TYPE TY_T_MAP
                              PV_IDX TYPE ANY.
  DATA: LV_FNAM TYPE BDCDATA-FNAM,
        LV_FVAL TYPE BDCDATA-FVAL,
        LS_MAP  TYPE ZBDC_MAPPING_BUP,
        LV_SRC  TYPE STRING,
        LV_IDXC TYPE C LENGTH 2.
  FIELD-SYMBOLS <FV> TYPE ANY.

  IF PS_SCR-IS_NEW_SCREEN = 'X'.
    IF PS_SCR-PROGRAM_NAME IS INITIAL OR PS_SCR-DYNPRO_NO IS INITIAL.
      RETURN.
    ENDIF.
    PERFORM BDC_DYNPRO USING PS_SCR-PROGRAM_NAME PS_SCR-DYNPRO_NO.
    RETURN.
  ENDIF.

  IF PS_SCR-FIELD_NAME IS INITIAL.
    RETURN.
  ENDIF.

  LV_FNAM = PS_SCR-FIELD_NAME.
  LV_IDXC = PV_IDX.
  REPLACE ALL OCCURRENCES OF GC_PH_INDEX IN LV_FNAM WITH LV_IDXC.

  IF PS_SCR-VALUE_TYPE = GC_VT_DYNAMIC.
    CLEAR LV_FVAL.
    LV_SRC = PS_SCR-SOURCE_COLUMN.
    TRANSLATE LV_SRC TO UPPER CASE.
    CONDENSE LV_SRC NO-GAPS.

    READ TABLE PT_MAP INTO LS_MAP WITH KEY SOURCE_COLUMN = LV_SRC.
    IF SY-SUBRC <> 0.
      RETURN.
    ENDIF.

    ASSIGN COMPONENT LS_MAP-STAGING_FIELD OF STRUCTURE PS_ROW TO <FV>.
    IF SY-SUBRC <> 0.
      RETURN.
    ENDIF.

    LV_FVAL = <FV>.
    CONDENSE LV_FVAL.
  ELSE.
    LV_FVAL = PS_SCR-STATIC_VALUE.
  ENDIF.

  PERFORM BDC_FIELD USING LV_FNAM LV_FVAL.
ENDFORM.

*&---------------------------------------------------------------------*
*& EXTRACT_DOCUMENT_NUMBER - lay object id dung theo message SAP
*& ME21N: msg 06/017 => MSGV2 moi la PO number trong case "Standard PO..."
*& MIGO : msg MIGO/012 => thuong MSGV1 la Material Document
*&---------------------------------------------------------------------*
*<<< END FORM APPEND_SCRIPT_STEP

*>>> FORM UPLOAD_SHDB_RECORDING - moved from Z_BDC_MASS_PO_ENTRY_F01_BUP
FORM UPLOAD_SHDB_RECORDING.
  DATA: LT_RAW   TYPE STRING_TABLE,
        LV_LINE  TYPE STRING,
        LT_TOK   TYPE STRING_TABLE,
        LV_PROG  TYPE STRING,
        LV_DYNP  TYPE STRING,
        LV_FLAG  TYPE STRING,
        LV_FNAM  TYPE STRING,
        LV_FVAL  TYPE STRING,
        LV_TCODE TYPE SY-TCODE,
        LS_SCR   TYPE ZBDC_SCT_DEF_BUP,
        LT_SCR   TYPE STANDARD TABLE OF ZBDC_SCT_DEF_BUP,
        LT_OLD   TYPE STANDARD TABLE OF ZBDC_SCT_DEF_BUP,
        LS_OLD   TYPE ZBDC_SCT_DEF_BUP,
        LV_SEQ   TYPE N LENGTH 4 VALUE '0000',
        LV_OLD_FROM TYPE SY-TABIX VALUE 1,
        LV_LAST_RT  TYPE ZBDC_SCT_DEF_BUP-ROW_TYPE,
        LV_ANS   TYPE C,
        LT_FILES TYPE FILETABLE,
        LV_RC    TYPE I,
        LV_ACT   TYPE I,
        LV_FILE  TYPE STRING.

  CL_GUI_FRONTEND_SERVICES=>FILE_OPEN_DIALOG(
    EXPORTING
      WINDOW_TITLE = 'Chon file SHDB export (.txt)'
      FILE_FILTER  = 'Text (*.txt)|*.txt|All (*.*)|*.*'
    CHANGING
      FILE_TABLE   = LT_FILES
      RC           = LV_RC
      USER_ACTION  = LV_ACT
    EXCEPTIONS
      OTHERS       = 1 ).

  IF SY-SUBRC <> 0 OR LV_ACT <> CL_GUI_FRONTEND_SERVICES=>ACTION_OK.
    RETURN.
  ENDIF.

  READ TABLE LT_FILES INTO DATA(LS_F) INDEX 1.
  IF SY-SUBRC <> 0.
    RETURN.
  ENDIF.
  LV_FILE = LS_F-FILENAME.

  CL_GUI_FRONTEND_SERVICES=>GUI_UPLOAD(
    EXPORTING
      FILENAME = LV_FILE
      FILETYPE = 'ASC'
      CODEPAGE = '4110'
    CHANGING
      DATA_TAB = LT_RAW
    EXCEPTIONS
      FILE_OPEN_ERROR         = 1
      FILE_READ_ERROR         = 2
      NO_BATCH                = 3
      GUI_REFUSE_FILETRANSFER = 4
      INVALID_TYPE            = 5
      NO_AUTHORITY            = 6
      UNKNOWN_ERROR           = 7
      OTHERS                  = 8 ).

  IF SY-SUBRC <> 0.
    MESSAGE |Khong doc duoc file SHDB. sy-subrc={ SY-SUBRC }.| TYPE 'E'.
    RETURN.
  ENDIF.

  LOOP AT LT_RAW INTO LV_LINE.
    REFRESH LT_TOK.
    SPLIT LV_LINE AT CL_ABAP_CHAR_UTILITIES=>HORIZONTAL_TAB INTO TABLE LT_TOK.
    CLEAR: LV_PROG, LV_DYNP, LV_FLAG, LV_FNAM, LV_FVAL.
    READ TABLE LT_TOK INTO LV_PROG INDEX 1.
    READ TABLE LT_TOK INTO LV_DYNP INDEX 2.
    READ TABLE LT_TOK INTO LV_FLAG INDEX 3.
    READ TABLE LT_TOK INTO LV_FNAM INDEX 4.
    READ TABLE LT_TOK INTO LV_FVAL INDEX 5.
    CONDENSE: LV_PROG, LV_DYNP, LV_FLAG, LV_FNAM.

    IF LV_FLAG = 'T'.
      LV_TCODE = LV_FNAM.
      CONTINUE.
    ENDIF.

    CLEAR LS_SCR.
    LS_SCR-TCODE = LV_TCODE.
    LV_SEQ = LV_SEQ + 10.
    LS_SCR-STEP_SEQ = LV_SEQ.

    IF LV_FLAG = 'X'.
      LS_SCR-PROGRAM_NAME  = LV_PROG.
      LS_SCR-DYNPRO_NO     = LV_DYNP.
      LS_SCR-IS_NEW_SCREEN = 'X'.
    ELSE.
      IF LV_FNAM IS INITIAL.
        CONTINUE.
      ENDIF.
      LS_SCR-FIELD_NAME   = LV_FNAM.
      LS_SCR-VALUE_TYPE   = GC_VT_STATIC.
      LS_SCR-STATIC_VALUE = LV_FVAL.
    ENDIF.

    LS_SCR-ROW_TYPE = GC_RT_HEADER.
    APPEND LS_SCR TO LT_SCR.
  ENDLOOP.

  IF LV_TCODE IS INITIAL OR LT_SCR IS INITIAL.
    MESSAGE 'File khong dung dinh dang SHDB export tab-separated.' TYPE 'E'.
    RETURN.
  ENDIF.

  "Preserve existing business metadata while restoring the technical SHDB
  "rows. Re-uploading must not destroy ITEM/HEADER grouping or dynamic mapping.
  SELECT * FROM ZBDC_SCT_DEF_BUP
    WHERE TCODE = @LV_TCODE
    ORDER BY STEP_SEQ
    INTO TABLE @LT_OLD.

  LOOP AT LT_SCR ASSIGNING FIELD-SYMBOL(<LS_NEW_SCR>).
    IF <LS_NEW_SCR>-FIELD_NAME = 'BDC_CURSOR' OR
       <LS_NEW_SCR>-FIELD_NAME = 'BDC_SUBSCR'.
      IF LV_LAST_RT IS NOT INITIAL.
        <LS_NEW_SCR>-ROW_TYPE = LV_LAST_RT.
      ENDIF.
      CONTINUE.
    ENDIF.

    LOOP AT LT_OLD INTO LS_OLD FROM LV_OLD_FROM.
      DATA(LV_OLD_HIT) = ABAP_FALSE.
      IF <LS_NEW_SCR>-IS_NEW_SCREEN = 'X' AND LS_OLD-IS_NEW_SCREEN = 'X' AND
         <LS_NEW_SCR>-PROGRAM_NAME = LS_OLD-PROGRAM_NAME AND
         <LS_NEW_SCR>-DYNPRO_NO    = LS_OLD-DYNPRO_NO.
        LV_OLD_HIT = ABAP_TRUE.
      ELSEIF <LS_NEW_SCR>-IS_NEW_SCREEN IS INITIAL AND
             LS_OLD-IS_NEW_SCREEN IS INITIAL AND
             <LS_NEW_SCR>-FIELD_NAME = LS_OLD-FIELD_NAME.
        LV_OLD_HIT = ABAP_TRUE.
      ENDIF.

      IF LV_OLD_HIT = ABAP_TRUE.
        IF LS_OLD-ROW_TYPE IS NOT INITIAL.
          <LS_NEW_SCR>-ROW_TYPE = LS_OLD-ROW_TYPE.
        ENDIF.
        IF LS_OLD-VALUE_TYPE IS NOT INITIAL.
          <LS_NEW_SCR>-VALUE_TYPE = LS_OLD-VALUE_TYPE.
        ENDIF.
        IF LS_OLD-SOURCE_COLUMN IS NOT INITIAL.
          <LS_NEW_SCR>-SOURCE_COLUMN = LS_OLD-SOURCE_COLUMN.
        ENDIF.
        LV_LAST_RT  = <LS_NEW_SCR>-ROW_TYPE.
        LV_OLD_FROM = SY-TABIX + 1.
        EXIT.
      ENDIF.
    ENDLOOP.
  ENDLOOP.

  CALL FUNCTION 'POPUP_TO_CONFIRM'
    EXPORTING
      TITLEBAR      = 'Upload SHDB Recording'
      TEXT_QUESTION = |Ghi de script { LV_TCODE } bang { LINES( LT_SCR ) } buoc moi?|
      TEXT_BUTTON_1 = 'Ghi de'
      TEXT_BUTTON_2 = 'Huy'
    IMPORTING
      ANSWER        = LV_ANS.

  IF LV_ANS <> '1'.
    RETURN.
  ENDIF.

  DELETE FROM ZBDC_SCT_DEF_BUP WHERE TCODE = @LV_TCODE.
  MODIFY ZBDC_SCT_DEF_BUP FROM TABLE LT_SCR.
  COMMIT WORK AND WAIT.

  MESSAGE |Da nap { LINES( LT_SCR ) } buoc cho { LV_TCODE }. Review ROW_TYPE/VALUE_TYPE/SOURCE_COLUMN truoc khi execute.| TYPE 'S'.
ENDFORM.


*&=====================================================================*
*& MUC 2 V2 - EXECUTION COCKPIT / DISPLAY FLOW 10-10
*&=====================================================================*
*<<< END FORM UPLOAD_SHDB_RECORDING

*>>> FORM load_mapping_screen - moved from Z_BDC_MASS_PO_ENTRY_F01_BUP
FORM load_mapping_screen.
  DATA lv_profile TYPE zbdc_mapping_bup-profile_name.
  lv_profile = txtp_profile_name.
  IF lv_profile IS INITIAL.
    lv_profile = gc_prof_me21n.
  ENDIF.
  SELECT * FROM zbdc_mapping_bup
    INTO TABLE @gt_mapping_screen
    WHERE profile_name = @lv_profile.
ENDFORM.
*<<< END FORM load_mapping_screen

*>>> FORM display_mapping_screen - moved from Z_BDC_MASS_PO_ENTRY_F01_BUP

FORM display_mapping_screen.
  PERFORM load_mapping_screen.
  IF go_container_0350 IS INITIAL.
    CREATE OBJECT go_container_0350
      EXPORTING container_name = 'CC_GRID_CONTAINER'.
    CREATE OBJECT go_map_grid
      EXPORTING i_parent = go_container_0350.
    go_map_grid->set_table_for_first_display(
      EXPORTING i_structure_name = 'ZBDC_MAPPING_BUP'
      CHANGING  it_outtab        = gt_mapping_screen ).
  ELSEIF go_map_grid IS BOUND.
    go_map_grid->refresh_table_display( ).
  ENDIF.
ENDFORM.
*<<< END FORM display_mapping_screen

*>>> FORM save_mapping_screen - moved from Z_BDC_MASS_PO_ENTRY_F01_BUP

FORM save_mapping_screen.
  IF go_map_grid IS BOUND.
    go_map_grid->check_changed_data( ).
  ENDIF.
  IF gt_mapping_screen IS NOT INITIAL.
    MODIFY zbdc_mapping_bup FROM TABLE gt_mapping_screen.
  ENDIF.
  PERFORM save_bdc_exec_mode_config.
  COMMIT WORK AND WAIT.
  MESSAGE |Mapping profile { txtp_profile_name } and BDC execution mode saved.| TYPE 'S'.
ENDFORM.
*<<< END FORM save_mapping_screen

*>>> FORM insert_mapping_row - moved from Z_BDC_MASS_PO_ENTRY_F01_BUP

FORM insert_mapping_row.
  DATA ls_map TYPE zbdc_mapping_bup.
  ls_map-profile_name = txtp_profile_name.
  APPEND ls_map TO gt_mapping_screen.
  IF go_map_grid IS BOUND.
    go_map_grid->refresh_table_display( ).
  ENDIF.
ENDFORM.
*<<< END FORM insert_mapping_row

*>>> FORM delete_mapping_row - moved from Z_BDC_MASS_PO_ENTRY_F01_BUP

FORM delete_mapping_row.
  DATA lt_rows TYPE lvc_t_row.
  DATA ls_row  TYPE lvc_s_row.
  IF go_map_grid IS BOUND.
    go_map_grid->get_selected_rows( IMPORTING et_index_rows = lt_rows ).
    SORT lt_rows BY index DESCENDING.
    LOOP AT lt_rows INTO ls_row.
      DELETE gt_mapping_screen INDEX ls_row-index.
    ENDLOOP.
    go_map_grid->refresh_table_display( ).
  ENDIF.
ENDFORM.

* ------------------------------------------------------------
* Screen 0500 - Execution Monitor
* ------------------------------------------------------------
*<<< END FORM delete_mapping_row

*>>> FORM z28_needs_me21n_fallback - moved from Z_BDC_MASS_PO_ENTRY_F01_BUP


FORM z28_needs_me21n_fallback
  USING    pt_group   TYPE ty_t_staging_alv
           pv_success TYPE abap_bool
           pv_error   TYPE abap_bool
           pv_object  TYPE zbdc_result_bup-sap_object_id
  CHANGING cv_needed  TYPE abap_bool
           cv_reason  TYPE string.

  DATA: ls_first TYPE ty_staging_alv,
        lv_tcode TYPE sy-tcode.

  CLEAR: cv_needed, cv_reason.
  "V5BB: this guard must not depend on GV_LAST_SM35_MODE because some
  "systems clear/normalize the mode after RSBDCCTU returns. The evidence
  "that matters here is: ME21N group + SM35 terminal + no verified PO proof.
  "Keep the business-error guard: data/mapping errors without GUI-control
  "evidence must remain real errors, not automatic retries.
  IF pv_error = abap_true.
    RETURN.
  ENDIF.
  IF pv_object IS NOT INITIAL.
    RETURN.
  ENDIF.

  READ TABLE pt_group INTO ls_first INDEX 1.
  IF sy-subrc <> 0.
    RETURN.
  ENDIF.

  lv_tcode = ls_first-tcode.
  IF lv_tcode IS INITIAL.
    lv_tcode = p_transaction.
  ENDIF.
  TRANSLATE lv_tcode TO UPPER CASE.
  CONDENSE lv_tcode NO-GAPS.

  IF lv_tcode = 'ME21N'.
    cv_needed = abap_true.
    IF pv_success = abap_true.
      cv_reason = |ME21N SM35 N finished without verified PO object; automatic mode-E BDC fallback is required to avoid false success.|.
    ELSE.
      cv_reason = |ME21N SM35 N finished without business-object proof; automatic mode-E BDC fallback is required for SAPLMEGUI/Control-Framework safety.|.
    ENDIF.
  ENDIF.
ENDFORM.
*<<< END FORM z28_needs_me21n_fallback

*>>> FORM load_script_editor - moved from Z_BDC_MASS_PO_ENTRY_F01_BUP
FORM load_script_editor.
  DATA lv_tcode TYPE zbdc_sct_def_bup-tcode.
  lv_tcode = p_rec_tcode.
  IF lv_tcode IS INITIAL.
    lv_tcode = p_transaction.
  ENDIF.
  IF lv_tcode IS INITIAL.
    lv_tcode = 'ME21N'.
  ENDIF.
  SELECT * FROM zbdc_sct_def_bup
    INTO TABLE @gt_script_def
    WHERE tcode = @lv_tcode
    ORDER BY step_seq.
ENDFORM.
*<<< END FORM load_script_editor

*>>> FORM display_script_editor - moved from Z_BDC_MASS_PO_ENTRY_F01_BUP

FORM display_script_editor.
  PERFORM load_script_editor.
  IF go_rec_container IS INITIAL.
    CREATE OBJECT go_rec_container EXPORTING container_name = 'CC_REC_GRID'.
    CREATE OBJECT go_rec_grid EXPORTING i_parent = go_rec_container.
    go_rec_grid->set_table_for_first_display(
      EXPORTING i_structure_name = 'ZBDC_SCT_DEF_BUP'
      CHANGING  it_outtab        = gt_script_def ).
  ELSEIF go_rec_grid IS BOUND.
    go_rec_grid->refresh_table_display( ).
  ENDIF.
ENDFORM.
*<<< END FORM display_script_editor

*>>> FORM save_script_editor - moved from Z_BDC_MASS_PO_ENTRY_F01_BUP

FORM save_script_editor.
  IF go_rec_grid IS BOUND.
    go_rec_grid->check_changed_data( ).
  ENDIF.
  IF gt_script_def IS NOT INITIAL.
    MODIFY zbdc_sct_def_bup FROM TABLE gt_script_def.
    COMMIT WORK AND WAIT.
  ENDIF.
  MESSAGE |SHDB script saved for { p_rec_tcode }.| TYPE 'S'.
ENDFORM.
*<<< END FORM save_script_editor

*>>> FORM insert_script_row - moved from Z_BDC_MASS_PO_ENTRY_F01_BUP

FORM insert_script_row.
  DATA ls_script TYPE zbdc_sct_def_bup.
  ls_script-tcode = p_rec_tcode.
  ls_script-step_seq = lines( gt_script_def ) + 1.
  APPEND ls_script TO gt_script_def.
  IF go_rec_grid IS BOUND.
    go_rec_grid->refresh_table_display( ).
  ENDIF.
ENDFORM.
*<<< END FORM insert_script_row

*>>> FORM delete_script_row - moved from Z_BDC_MASS_PO_ENTRY_F01_BUP

FORM delete_script_row.
  DATA lt_rows TYPE lvc_t_row.
  DATA ls_row  TYPE lvc_s_row.
  IF go_rec_grid IS BOUND.
    go_rec_grid->get_selected_rows( IMPORTING et_index_rows = lt_rows ).
    SORT lt_rows BY index DESCENDING.
    LOOP AT lt_rows INTO ls_row.
      DELETE gt_script_def INDEX ls_row-index.
    ENDLOOP.
    go_rec_grid->refresh_table_display( ).
  ENDIF.
ENDFORM.
*&=====================================================================*
*& FIX16 - USER-CENTRIC 16/16 RUNTIME INTEGRATION
*& Scope:
*&   - Use optional setup tables already created in SE11/SM30:
*&       ZBDC_FGUID_BUP  Field Guide / Template help
*&       ZBDC_VRULE_BUP  Dynamic validation rules
*&       ZBDC_ERROR_BUP  Structured error/fix-guide records
*&       ZBDC_CHG_BUP    Audit/change log
*&   - Keep legacy Dynpro flow and all GUI statuses except obsolete 0250.
*&   - All dynamic table usage is guarded so the core BDC still runs even
*&     if one optional polish table is not transported yet.
*&=====================================================================*
*<<< END FORM delete_script_row

*>>> FORM z16_read_guide - moved from Z_BDC_MASS_PO_ENTRY_F01_BUP

FORM z16_read_guide CHANGING ct_guide TYPE ty_t_z16_guide.
  DATA: lv_exists TYPE abap_bool,
        lr_tab    TYPE REF TO data,
        lv_text   TYPE string,
        lv_tcode  TYPE string,
        lv_active TYPE string,
        ls_guide  TYPE ty_z16_guide.
  FIELD-SYMBOLS: <lt_any> TYPE STANDARD TABLE,
                 <ls_any> TYPE any.

  REFRESH ct_guide.
  PERFORM z16_table_exists USING gc_z16_tab_fguide CHANGING lv_exists.
  IF lv_exists IS INITIAL.
    RETURN.
  ENDIF.

  TRY.
      CREATE DATA lr_tab TYPE STANDARD TABLE OF (gc_z16_tab_fguide).
      ASSIGN lr_tab->* TO <lt_any>.
      SELECT * FROM (gc_z16_tab_fguide) INTO TABLE @<lt_any>.
    CATCH cx_root.
      RETURN.
  ENDTRY.

  LOOP AT <lt_any> ASSIGNING <ls_any>.
    CLEAR: ls_guide, lv_text, lv_tcode, lv_active.

    PERFORM z16_get_comp_str USING <ls_any> 'IS_ACTIVE' CHANGING lv_active.
    IF lv_active IS INITIAL. PERFORM z16_get_comp_str USING <ls_any> 'ACTIVE' CHANGING lv_active. ENDIF.
    TRANSLATE lv_active TO UPPER CASE.
    IF lv_active IS NOT INITIAL AND lv_active <> 'X' AND lv_active <> '1' AND lv_active <> 'Y'.
      CONTINUE.
    ENDIF.

    PERFORM z16_get_comp_str USING <ls_any> 'TCODE' CHANGING lv_tcode.
    IF lv_tcode IS INITIAL. PERFORM z16_get_comp_str USING <ls_any> 'TRANSACTION' CHANGING lv_tcode. ENDIF.
    TRANSLATE lv_tcode TO UPPER CASE.
    IF lv_tcode IS NOT INITIAL AND lv_tcode <> p_transaction.
      CONTINUE.
    ENDIF.
    ls_guide-tcode = lv_tcode.

    PERFORM z16_get_comp_str USING <ls_any> 'SOURCE_COLUMN' CHANGING lv_text.
    IF lv_text IS INITIAL. PERFORM z16_get_comp_str USING <ls_any> 'EXCEL_HEADER' CHANGING lv_text. ENDIF.
    IF lv_text IS INITIAL. PERFORM z16_get_comp_str USING <ls_any> 'HEADER_NAME' CHANGING lv_text. ENDIF.
    ls_guide-source_column = lv_text.

    CLEAR lv_text.
    PERFORM z16_get_comp_str USING <ls_any> 'STAGING_FIELD' CHANGING lv_text.
    IF lv_text IS INITIAL. PERFORM z16_get_comp_str USING <ls_any> 'FIELDNAME' CHANGING lv_text. ENDIF.
    IF lv_text IS INITIAL. PERFORM z16_get_comp_str USING <ls_any> 'FIELD_NAME' CHANGING lv_text. ENDIF.
    ls_guide-staging_field = lv_text.

    CLEAR lv_text.
    PERFORM z16_get_comp_str USING <ls_any> 'DISPLAY_LABEL' CHANGING lv_text.
    IF lv_text IS INITIAL. PERFORM z16_get_comp_str USING <ls_any> 'FIELD_LABEL' CHANGING lv_text. ENDIF.
    IF lv_text IS INITIAL. PERFORM z16_get_comp_str USING <ls_any> 'LABEL' CHANGING lv_text. ENDIF.
    ls_guide-display_label = lv_text.

    CLEAR lv_text.
    PERFORM z16_get_comp_str USING <ls_any> 'MANDATORY' CHANGING lv_text.
    IF lv_text IS INITIAL. PERFORM z16_get_comp_str USING <ls_any> 'IS_REQUIRED' CHANGING lv_text. ENDIF.
    IF lv_text IS INITIAL. PERFORM z16_get_comp_str USING <ls_any> 'REQUIRED' CHANGING lv_text. ENDIF.
    TRANSLATE lv_text TO UPPER CASE.
    IF lv_text = 'X' OR lv_text = '1' OR lv_text = 'Y'. ls_guide-mandatory = 'X'. ENDIF.

    CLEAR lv_text.
    PERFORM z16_get_comp_str USING <ls_any> 'EXAMPLE_VALUE' CHANGING lv_text.
    IF lv_text IS INITIAL. PERFORM z16_get_comp_str USING <ls_any> 'EXAMPLE' CHANGING lv_text. ENDIF.
    ls_guide-example_value = lv_text.

    CLEAR lv_text.
    PERFORM z16_get_comp_str USING <ls_any> 'RULE_TEXT' CHANGING lv_text.
    IF lv_text IS INITIAL. PERFORM z16_get_comp_str USING <ls_any> 'DESCRIPTION' CHANGING lv_text. ENDIF.
    ls_guide-rule_text = lv_text.

    CLEAR lv_text.
    PERFORM z16_get_comp_str USING <ls_any> 'SUGGESTED_VALUES' CHANGING lv_text.
    IF lv_text IS INITIAL. PERFORM z16_get_comp_str USING <ls_any> 'VALUE_HELP' CHANGING lv_text. ENDIF.
    ls_guide-suggested_values = lv_text.

    CLEAR lv_text.
    PERFORM z16_get_comp_str USING <ls_any> 'RESPONSIBLE' CHANGING lv_text.
    IF lv_text IS INITIAL. lv_text = 'User'. ENDIF.
    ls_guide-responsible = lv_text.

    CLEAR lv_text.
    PERFORM z16_get_comp_str USING <ls_any> 'DISPLAY_ORDER' CHANGING lv_text.
    IF lv_text IS NOT INITIAL. ls_guide-display_order = lv_text. ENDIF.

    IF ls_guide-source_column IS INITIAL AND ls_guide-display_label IS NOT INITIAL.
      ls_guide-source_column = ls_guide-display_label.
    ENDIF.
    IF ls_guide-source_column IS INITIAL AND ls_guide-staging_field IS NOT INITIAL.
      ls_guide-source_column = ls_guide-staging_field.
    ENDIF.

    IF ls_guide-source_column IS NOT INITIAL.
      APPEND ls_guide TO ct_guide.
    ENDIF.
  ENDLOOP.

  SORT ct_guide BY display_order source_column.
ENDFORM.
*<<< END FORM z16_read_guide

*>>> FORM z16_build_template_from_guide - moved from Z_BDC_MASS_PO_ENTRY_F01_BUP

FORM z16_build_template_from_guide USING iv_tcode TYPE char20
                                   CHANGING ct_data TYPE string_table
                                            cv_used TYPE abap_bool.
  DATA: lt_guide TYPE ty_t_z16_guide,
        ls_guide TYPE ty_z16_guide,
        lv_header TYPE string,
        lv_sample TYPE string,
        lv_req    TYPE string,
        lv_part   TYPE string.

  CLEAR cv_used.
  REFRESH ct_data.
  PERFORM z16_read_guide CHANGING lt_guide.
  IF lt_guide IS INITIAL.
    RETURN.
  ENDIF.

  APPEND '# Instruction: Do not change/delete the real CSV header row below.' TO ct_data.
  APPEND '# Lines starting with # are ignored by upload. Field meanings come from ZBDC_FGUID_BUP.' TO ct_data.
  APPEND '# Flow: fill template -> upload -> validate -> fix guide -> retry only failed rows.' TO ct_data.

  CLEAR: lv_header, lv_sample, lv_req.
  LOOP AT lt_guide INTO ls_guide.
    lv_part = ls_guide-source_column.
    IF ls_guide-mandatory = 'X'.
      lv_part = lv_part && '*'.
    ENDIF.
    IF lv_header IS INITIAL. lv_header = lv_part. ELSE. lv_header = lv_header && ',' && lv_part. ENDIF.

    lv_part = ls_guide-example_value.
    IF lv_sample IS INITIAL. lv_sample = lv_part. ELSE. lv_sample = lv_sample && ',' && lv_part. ENDIF.

    IF ls_guide-mandatory = 'X'.
      lv_part = ls_guide-source_column && '=required'.
    ELSE.
      lv_part = ls_guide-source_column && '=optional'.
    ENDIF.
    IF lv_req IS INITIAL. lv_req = '# Required: ' && lv_part. ELSE. lv_req = lv_req && '; ' && lv_part. ENDIF.
  ENDLOOP.

  APPEND lv_req TO ct_data.
  APPEND lv_header TO ct_data.
  APPEND lv_sample TO ct_data.
  cv_used = abap_true.
ENDFORM.
*<<< END FORM z16_build_template_from_guide
