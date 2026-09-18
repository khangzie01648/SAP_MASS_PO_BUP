
*& Include Z_BDC_MASS_PO_ENTRY_TOP_BUP
*& Purpose Global types, constants, data and local class definitions
*& ABAP declaration-chain syntax repair


"Screen 0500 command contract. Values remain stable for GUI-status/ALV compatibility.
CONSTANTS: gc_ucomm_run_0500        TYPE syucomm VALUE 'RUN0500',
           gc_ucomm_create_sm35     TYPE syucomm VALUE 'SM350500',
           gc_ucomm_exec_sm35       TYPE syucomm VALUE 'SM35EXEC',
           gc_ucomm_open_sm35       TYPE syucomm VALUE 'OPENSM35',
           gc_ucomm_stop_0500       TYPE syucomm VALUE 'STOP0500',
           gc_ucomm_refresh_0500    TYPE syucomm VALUE 'REF0500',
           gc_ucomm_error_detail    TYPE syucomm VALUE 'ERR0500',
           gc_ucomm_fix_guide       TYPE syucomm VALUE 'FIX0500',
           gc_ucomm_retry_0500      TYPE syucomm VALUE 'RET0500',
           gc_ucomm_dashboard_0500  TYPE syucomm VALUE 'DAS0500',
           gc_ucomm_bism_run        TYPE syucomm VALUE 'BISM_RUN',
           gc_ucomm_bism_all        TYPE syucomm VALUE 'BISM_ALL',
           gc_ucomm_bism_selected   TYPE syucomm VALUE 'BISM_SEL'.

TABLES: sscrfields.
TYPE-POOLS: ICON, LVC, VRM.

CLASS lcl_alv_events DEFINITION DEFERRED.
CLASS lcl_grid_events DEFINITION DEFERRED.

CLASS ltc_clean_utilities DEFINITION FINAL FOR TESTING
  DURATION SHORT
  RISK LEVEL HARMLESS.
  PRIVATE SECTION.
    METHODS split_csv_with_quotes FOR TESTING.
    METHODS escape_html_text FOR TESTING.
ENDCLASS.


TYPES: BEGIN OF ty_session_disp,
         session_id    TYPE zbdc_result_bup-session_id,
         created_at    TYPE zbdc_result_bup-created_at,
         msg_type      TYPE zbdc_result_bup-msg_type,
         sap_object_id TYPE zbdc_result_bup-sap_object_id,
         message       TYPE zbdc_result_bup-message,
       END OF ty_session_disp.

DATA: ok_code TYPE sy-ucomm,
      save_ok TYPE sy-ucomm.

* ============================================================
* Screen 0100 - Main Dashboard
* ============================================================
TYPES: BEGIN OF ty_dash_0100_disp,
         session_id    TYPE zbdc_result_bup-session_id,
         created_on    TYPE char19,
         sort_key      TYPE char30, "technical: YYYYMMDDHHMMSS, hidden in ALV
         created_by    TYPE syuname,
         source_type   TYPE char20,
         tcode         TYPE char20,
         executor      TYPE char12,
         status_text   TYPE char20,
         total_rec     TYPE i,
         ready_rec     TYPE i,
         success_rec   TYPE i,
         warning_rec   TYPE i,
         error_rec     TYPE i,
         success_pct   TYPE p LENGTH 5 DECIMALS 1,
         success_pct_txt TYPE char10, "locale-neutral user display, e.g. 14.3%
         log_count     TYPE i,
         last_object   TYPE zbdc_result_bup-sap_object_id,
         main_error    TYPE char120,
         retryable     TYPE char10,
         next_action   TYPE char40,
       END OF ty_dash_0100_disp.

DATA: gt_sessions       TYPE STANDARD TABLE OF ty_session_disp,
      gt_dash_0100      TYPE STANDARD TABLE OF ty_dash_0100_disp,
      go_container_0100 TYPE REF TO cl_gui_custom_container,
      go_grid_0100      TYPE REF TO cl_salv_table.

* professional three-level dashboard drill-down.
* Level 1 = session overview on 0100.
* Level 2 = one row per canonical business group for the selected session.
* Level 3 = persisted execution evidence rows for the selected group.
TYPES ty_t_result_726 TYPE STANDARD TABLE OF zbdc_result_bup WITH DEFAULT KEY.

TYPES: BEGIN OF ty_group_0100_disp,
         health         TYPE icon_d,
         group_key      TYPE c LENGTH 80,
         tcode          TYPE char20,
         row_count      TYPE i,
         executor       TYPE char12,
         lifecycle      TYPE char20,
         started_at     TYPE char19,
         finished_at    TYPE char19,
         attempt        TYPE i,
         retry_count    TYPE i,
         evidence_rows  TYPE i,
         last_evidence  TYPE zbdc_result_bup-created_at,
         input_data     TYPE char30,
         changes        TYPE char30,
         cell_types     TYPE salv_t_int4_column,
         session_id     TYPE zbdc_staging_bup-session_id,
         record_key     TYPE zbdc_staging_bup-record_key,
         row_index      TYPE zbdc_staging_bup-row_index,
       END OF ty_group_0100_disp.

TYPES: BEGIN OF ty_evidence_0100_disp,
         evidence_kind TYPE char20,
         evidence_at   TYPE zbdc_result_bup-created_at,
         attempt       TYPE i,
         msg_type      TYPE zbdc_result_bup-msg_type,
         exec_status   TYPE c LENGTH 20,
         dynpro        TYPE zbdc_result_bup-dynpro,
         field_name    TYPE zbdc_result_bup-field_name,
         exact_message TYPE char255,
         retry_flag    TYPE zbdc_result_bup-retry_flag,
       END OF ty_evidence_0100_disp.

* final audit card shown at level 3. Only persisted/derived facts are
* displayed; no guessed business field/object meaning is introduced.
TYPES: BEGIN OF ty_evidence_card_0100,
         section     TYPE char30,
         detail      TYPE char255,
         cell_colors TYPE lvc_t_scol,
       END OF ty_evidence_card_0100.

DATA: gt_group_0100       TYPE STANDARD TABLE OF ty_group_0100_disp,
      go_group_grid_0100  TYPE REF TO cl_salv_table,
      go_group_evt_0100   TYPE REF TO lcl_alv_events,
      gv_z775_focus_group TYPE zbdc_staging_bup-record_key,
      gt_evidence_0100    TYPE STANDARD TABLE OF ty_evidence_0100_disp,
      gt_evidence_card_0100 TYPE STANDARD TABLE OF ty_evidence_card_0100,
      go_evidence_grid_0100 TYPE REF TO cl_salv_table.

DATA: txtgv_total_sessions TYPE char20,
      txtgv_processed_pos  TYPE char20,
      txtgv_success_count  TYPE char20,
      txtgv_warning_count  TYPE char20,
      txtgv_error_count    TYPE char20,
      txtgv_success_pct    TYPE char20,
      txtgv_warning_pct    TYPE char20,
      txtgv_error_pct      TYPE char20,
      txtgv_open_count     TYPE char20,
      txtgv_open_pct       TYPE char20.

* live Main Dashboard refresh state.
* SE51 remains the owner of labels/layout; these objects only refresh the
* bound values and SALV projection from persisted SAP tables.
CLASS lcl_dash_timer_0100 DEFINITION.
  PUBLIC SECTION.
    METHODS on_finished FOR EVENT finished OF cl_gui_timer.
ENDCLASS.

DATA: go_timer_0100      TYPE REF TO cl_gui_timer,
      go_timer_hdl_0100  TYPE REF TO lcl_dash_timer_0100,
      gv_timer_0100_on   TYPE abap_bool,
      gv_timer_0100_sec  TYPE i VALUE 2,
      gv_dash_0100_tick  TYPE abap_bool.

* ============================================================
* canonical real-time KPI snapshot for screen 0100.
* One snapshot feeds the visible header counts and session SALV.
* Screen 0100 keeps its original static Text/I-O KPI presentation.
* ============================================================
TYPES: BEGIN OF ty_kpi_sid_0100,
         session_id TYPE zbdc_session_bup-session_id,
       END OF ty_kpi_sid_0100.

TYPES: BEGIN OF ty_kpi_group_0100,
         session_id    TYPE zbdc_staging_bup-session_id,
         group_key     TYPE c LENGTH 80,
         record_key    TYPE zbdc_staging_bup-record_key,
         row_index     TYPE zbdc_staging_bup-row_index,
         tcode         TYPE zbdc_staging_bup-tcode,
         row_count     TYPE i,
         success_rows  TYPE i,
         warning_rows  TYPE i,
         error_rows    TYPE i,
         sm35_rows     TYPE i,
         other_rows    TYPE i,
         other_state   TYPE char20,
         state         TYPE char20,
       END OF ty_kpi_group_0100.

DATA: gt_kpi_sid_0100 TYPE SORTED TABLE OF ty_kpi_sid_0100
                        WITH UNIQUE KEY session_id,
      gt_kpi_group_0100 TYPE HASHED TABLE OF ty_kpi_group_0100
                        WITH UNIQUE KEY session_id group_key,
      gv_kpi_signature_0100 TYPE string.

* ============================================================
* Runtime Processing Configuration (owned by screen 0300)
* ============================================================
DATA: rb_rest     TYPE c LENGTH 1 VALUE 'X',
      rb_gdrive   TYPE c LENGTH 1,
      rb_local    TYPE c LENGTH 1.

DATA: txtp_webhook_url TYPE string,
      p_auth_type      TYPE char20,
      txtp_api_key     TYPE char255,
      txtp_timeout     TYPE i,
      chkp_retry       TYPE c LENGTH 1,
      txtp_gdrive_url  TYPE char255,
      txtp_file_path   TYPE string,
      p_transaction    TYPE char20,
      p_format         TYPE char10 VALUE 'CSV',
      rb_exec_ct       TYPE c LENGTH 1 VALUE 'X',
      rb_exec_bi       TYPE c LENGTH 1,
      rb_mode_n        TYPE c LENGTH 1 VALUE 'X',
      rb_mode_e        TYPE c LENGTH 1,
      rb_mode_a        TYPE c LENGTH 1,
      rb_upd_a         TYPE c LENGTH 1 VALUE 'X',
      rb_upd_s         TYPE c LENGTH 1,
      txtp_batch_size  TYPE char10 VALUE '100'.

* ============================================================
* Screen 0300 - Upload & Ingestion (+0301/0302)
* ============================================================
DATA: g_sub_dynpro      TYPE sy-dynnr VALUE '0301',
      txtp_file_size    TYPE char20,
      txtp_row_count    TYPE char20,
      txtp_row          TYPE char20,
      txtp_rows         TYPE char20,
      txtp_loaded       TYPE char20,
      txtp_rows_loaded  TYPE char20,
      txtp_loaded_rows  TYPE char20,
      txtgv_row_count   TYPE char20,
      txtgv_rows        TYPE char20,
      txtgv_loaded      TYPE char20,
      txtgv_total_rows  TYPE char20,
      txtgv_tot_rows    TYPE char20,
      gt_staging        TYPE STANDARD TABLE OF zbdc_staging_bup,
      gt_errors         TYPE STANDARD TABLE OF zbdc_staging_bup,
      go_container_0301 TYPE REF TO cl_gui_custom_container,
      gv_rebuild_0301   TYPE abap_bool,
      go_grid_0301      TYPE REF TO cl_salv_table,
      go_alv_0301       TYPE REF TO cl_gui_alv_grid,
      g_0301_grid_events TYPE REF TO lcl_grid_events,
      g_0650_grid_events TYPE REF TO lcl_grid_events,
      go_container_0302 TYPE REF TO cl_gui_custom_container,
      go_grid_0302      TYPE REF TO cl_salv_table.

DATA: gv_config_loaded TYPE c,
      GV_RUNTIME_LAST_STAT TYPE char20,
      GV_RUNTIME_LAST_MSG  TYPE char255,
      GV_RUNTIME_LAST_AT   TYPE char30.

TYPES: BEGIN OF ty_files_disp,
         status_icon  TYPE icon_d,                         "UI only: traffic light
         batch_key    TYPE char22,                         "UI only: batch prefix derived from SESSION_ID
         file_title   TYPE char80,                         "UI only: clean file/source name
         sheet_name   TYPE char40,                         "UI only: Excel sheet / CSV data unit
         tx_code      TYPE char20,                         "UI only: transaction context resolved per sheet
         source_text  TYPE char20,                         "UI only: readable source
         rows_loaded  TYPE i,                              "UI only: numeric rows
         processed_on TYPE char19,                         "UI only: DD.MM.YYYY HH:MM:SS
         owner        TYPE sy-uname,                       "UI only: real session creator if available
         status_text  TYPE char20,                         "UI only: lifecycle status
         next_action  TYPE char50,                         "UI only: user action hint
         data_unit    TYPE char30,                         "UI only: File / Sheet / Payload
         file_name    TYPE string,                         "raw/full path + sheet marker, hidden in 0302
         file_size    TYPE char20,                         "legacy compatibility, hidden in 0302
         channel      TYPE string,                         "raw source, hidden in 0302
         upload_date  TYPE sy-datum,                       "raw date, hidden in 0302
         upload_time  TYPE sy-uzeit,                       "raw time, hidden in 0302
         username     TYPE sy-uname,                       "legacy compatibility, hidden in 0302
         session_id   TYPE zbdc_staging_bup-session_id,     "technical, hidden in 0302
         raw_status   TYPE zbdc_file_lg_bup-status,        "raw DB status, hidden in 0302
         raw_error    TYPE zbdc_file_lg_bup-error_msg,     "raw DB message, hidden in 0302
       END OF ty_files_disp.

CONSTANTS:
  gc_file_scope_my  TYPE c LENGTH 1 VALUE 'M',
  gc_file_scope_all TYPE c LENGTH 1 VALUE 'A',
  gc_fc_file_my     TYPE sy-ucomm VALUE 'ZMYFILES',
  gc_fc_file_all    TYPE sy-ucomm VALUE 'ZALLFILES'.

DATA: gt_files_preview       TYPE STANDARD TABLE OF ty_files_disp,
      go_alv_events          TYPE REF TO lcl_alv_events,
      go_alv_file_events     TYPE REF TO lcl_alv_events,
      gv_file_scope          TYPE c LENGTH 1 VALUE 'M',
      gv_0300_history_scope  TYPE abap_bool. "/selected from Preview Files history; keep persisted lifecycle

* Mass Automation Batch Context (code-only, no new SE11 fields)
* One upload/pull run = one compact batch prefix BYYYYMMDDHHMMSS.
* Each file/attachment/payload = one SESSION_ID with suffix _001/_002/...
* This stays code-only and fits old CHAR20/CHAR22 SESSION_ID designs.
DATA: gv_current_batch_prefix TYPE zbdc_staging_bup-session_id,
      gv_ingest_batch_prefix  TYPE zbdc_staging_bup-session_id,
      gv_forced_session_id    TYPE zbdc_staging_bup-session_id,
      gv_current_batch_count  TYPE i,
      gt_current_sessions     TYPE STANDARD TABLE OF zbdc_staging_bup-session_id.

* frontend multi-file picker state.
* Do not serialize N full Windows paths into TXTP_FILE_PATH; that screen field
* is display/navigation state only. The real selected local files live here.
DATA gt_local_selected_files TYPE string_table.

* File/Sheet data-unit context. No DDIC change: metadata is persisted
* by encoding SHEET in ZBDC_FILE_LG_BUP-FILE_NAME as: <file>|SHEET=<sheet>.
DATA: gv_current_file_name  TYPE string,
      gv_current_sheet_name TYPE char40,
      gv_current_unit_src   TYPE char20.
DATA gv_ingest_error_msg TYPE string.

TYPES: BEGIN OF ty_preview_disp.
TYPES:   batch_key    TYPE char22,
         file_title   TYPE char80,
         sheet_name   TYPE char40,
         tx_code      TYPE char20,
         excel_row    TYPE i,
         business_key TYPE char40,
         status_text  TYPE char20,
         message_text TYPE char255,
         col01        TYPE char255,
         col02        TYPE char255,
         col03        TYPE char255,
         col04        TYPE char255,
         col05        TYPE char255,
         col06        TYPE char255,
         col07        TYPE char255,
         col08        TYPE char255,
         col09        TYPE char255,
         col10        TYPE char255,
         col11        TYPE char255,
         col12        TYPE char255,
         col13        TYPE char255,
         col14        TYPE char255,
         col15        TYPE char255,
         col16        TYPE char255,
         col17        TYPE char255,
         col18        TYPE char255,
         col19        TYPE char255,
         col20        TYPE char255,
         col21        TYPE char255,
         col22        TYPE char255,
         col23        TYPE char255,
         col24        TYPE char255,
         col25        TYPE char255.
TYPES: END OF ty_preview_disp.

DATA gt_preview_data TYPE STANDARD TABLE OF ty_preview_disp.

TYPES: BEGIN OF ty_preview_src_cache,
         session_id  TYPE zbdc_staging_bup-session_id,
         row_index   TYPE i,
         preview_row TYPE ty_preview_disp,
       END OF ty_preview_src_cache.
DATA gt_preview_src_cache TYPE STANDARD TABLE OF ty_preview_src_cache.

TYPES: BEGIN OF ty_preview_hdr_cache,
         session_id TYPE zbdc_staging_bup-session_id,
         col_no     TYPE i,
         header_text TYPE char80,
       END OF ty_preview_hdr_cache.
DATA gt_preview_hdr_cache TYPE STANDARD TABLE OF ty_preview_hdr_cache.

CONTROLS: ts_preview TYPE TABSTRIP.

* ============================================================
* Screen 0400 - BUP Execution Cockpit / Detail Edit
* ============================================================
DATA: go_container_0400 TYPE REF TO cl_gui_custom_container,
      go_split_0400     TYPE REF TO cl_gui_splitter_container,
      go_cont_head_0400 TYPE REF TO cl_gui_container,
      go_cont_body_0400 TYPE REF TO cl_gui_container,
      go_doc_head_0400  TYPE REF TO cl_dd_document,
      go_exec_grid      TYPE REF TO cl_gui_alv_grid,
      go_staging_grid   TYPE REF TO cl_gui_alv_grid,
      go_grid_0400      TYPE REF TO cl_gui_alv_grid.

DATA: txtp_session_id   TYPE char22,
      txtp_sess         TYPE char22,
      p_status          TYPE char1,
      p_filter          TYPE char80, "legacy screen field; replaces it with SE51 ZSTGAUD button
      chkp_filter       TYPE char1,
      txtgv_tot         TYPE char20,
      txtgv_total       TYPE i,
      txtgv_suc         TYPE char20,
      txtgv_suc_count   TYPE i,
      txtgv_ok          TYPE i,
      txtgv_err         TYPE char20,
      txtgv_war         TYPE char20,
      txtgv_warning     TYPE i.

* ============================================================
* Google Drive Ingestion Variables
* ============================================================
DATA: gv_gdrive_file_id_temp TYPE string,
      gv_gdrive_token        TYPE string.

* ============================================================
* Screen 0350 - Mapping Profile
* ============================================================
DATA: gv_profile_ver TYPE zbdc_prof_bup-profile_ver VALUE 1.

* ============================================================
* Immutable runtime contract context (profile/version/script)
* ============================================================
DATA: gv_runtime_script_id       TYPE zbdc_script_bup-script_id,
      gv_runtime_contract_hash   TYPE zbdc_script_bup-contract_hash,
      gs_runtime_cert            TYPE zbdc_cert_bup,
      gv_runtime_cert_loaded     TYPE abap_bool,
      gv_bdc_build_failed        TYPE abap_bool,
      gv_bdc_build_message       TYPE string.
DATA: txtp_profile_name TYPE char50,
      p_bdc_mode        TYPE char30 VALUE 'CALL_TRANSACTION'.

TYPES: BEGIN OF ty_staging_alv.
         INCLUDE TYPE zbdc_staging_bup.
TYPES:   cell_colors TYPE lvc_t_scol,
       END OF ty_staging_alv.

DATA: gt_staging_alv TYPE STANDARD TABLE OF ty_staging_alv.

* ============================================================
* BDC Tables
* ============================================================
DATA: bdcdata TYPE TABLE OF bdcdata     WITH HEADER LINE,
      messtab TYPE TABLE OF bdcmsgcoll WITH HEADER LINE.

* Normalized BDC message structure for dashboard/drilldown/retry/export
TYPES: BEGIN OF ty_bdc_msg_norm,
         msg_type     TYPE symsgty,
         msg_id       TYPE symsgid,
         msg_number   TYPE symsgno,
         msgv1        TYPE symsgv,
         msgv2        TYPE symsgv,
         msgv3        TYPE symsgv,
         msgv4        TYPE symsgv,
         program_name TYPE bdcdata-program,
         dynpro_no    TYPE bdcdata-dynpro,
         field_name   TYPE bdcdata-fnam,
         message      TYPE c LENGTH 255,
         exec_status  TYPE c LENGTH 20,
         action_hint  TYPE c LENGTH 120,
         retry_flag   TYPE c LENGTH 1,
       END OF ty_bdc_msg_norm.

CLASS lcl_alv_events DEFINITION.
  PUBLIC SECTION.
    METHODS:
      on_double_click FOR EVENT double_click OF cl_salv_events_table
        IMPORTING row column,
      on_group_double_click FOR EVENT double_click OF cl_salv_events_table
        IMPORTING row column,
      on_group_link_click FOR EVENT link_click OF cl_salv_events_table
        IMPORTING row column,
      on_result_group_dbl FOR EVENT double_click OF cl_salv_events_table
        IMPORTING row column,
      on_result_group_link FOR EVENT link_click OF cl_salv_events_table
        IMPORTING row column,
      on_issue_0700_dbl FOR EVENT double_click OF cl_salv_events_table
        IMPORTING row column,
      on_issue_0700_link FOR EVENT link_click OF cl_salv_events_table
        IMPORTING row column,
      on_file_double_click FOR EVENT double_click OF cl_salv_events_table
        IMPORTING row column,
      on_file_function FOR EVENT added_function OF cl_salv_events_table
        IMPORTING e_salv_function,
      on_fixguide_double_click FOR EVENT double_click OF cl_salv_events_table
        IMPORTING row column,
      on_fixguide_function FOR EVENT added_function OF cl_salv_events_table
        IMPORTING e_salv_function.
ENDCLASS.

* ============================================================
* ===== MUC 2 - BDC GENERIC ENGINE (PHASE 4-8) ===============
* ===== Bien & type bo sung - KHONG dung cham code Muc 1 =====
* ============================================================
* Generic in-memory script line used by the legacy editor and the new
* versioned runtime. It mirrors the old editor shape without depending on
* the obsolete legacy script DDIC table. No transaction-specific fields exist.
TYPES: BEGIN OF ty_script_def_compat,
         mandt          TYPE mandt,
         tcode          TYPE zbdc_prof_bup-tcode,
         step_seq       TYPE zbdc_sct_ver_bup-step_seq,
         is_new_screen  TYPE zbdc_sct_ver_bup-is_new_screen,
         field_name     TYPE zbdc_sct_ver_bup-field_name,
         value_type     TYPE zbdc_sct_ver_bup-value_type,
         static_value   TYPE zbdc_sct_ver_bup-static_value,
         source_column  TYPE zbdc_sct_ver_bup-source_column,
         row_type       TYPE zbdc_sct_ver_bup-row_type,
         program_name   TYPE zbdc_sct_ver_bup-program_name,
         dynpro_no      TYPE zbdc_sct_ver_bup-dynpro_no,
         profile_name   TYPE zbdc_prof_bup-profile_name,
         profile_ver    TYPE zbdc_prof_bup-profile_ver,
       END OF ty_script_def_compat.

TYPES: ty_t_staging_alv TYPE STANDARD TABLE OF ty_staging_alv        WITH DEFAULT KEY,
       ty_t_script      TYPE STANDARD TABLE OF ty_script_def_compat WITH DEFAULT KEY,
       ty_t_map         TYPE STANDARD TABLE OF zbdc_mapping_bup     WITH DEFAULT KEY.

* Generic BDC table contracts used by the certified review route.
* Keep these aliases in TOP so every later include sees one compile-time type.
TYPES: ty_t_async_bdcdata TYPE STANDARD TABLE OF bdcdata    WITH DEFAULT KEY,
       ty_t_async_bdcmsg  TYPE STANDARD TABLE OF bdcmsgcoll WITH DEFAULT KEY.

* true database chunk scope: one key represents one SAP document.
TYPES: BEGIN OF ty_engine_group_key,
         session_id TYPE zbdc_staging_bup-session_id,
         record_key TYPE zbdc_staging_bup-record_key,
         row_index  TYPE zbdc_staging_bup-row_index,
       END OF ty_engine_group_key.
TYPES ty_t_engine_group_key TYPE STANDARD TABLE OF ty_engine_group_key
  WITH DEFAULT KEY.

* Standard Batch Input protocol lines read from the SM35 TemSe log.
TYPES ty_t_bdclm TYPE STANDARD TABLE OF bdclm WITH DEFAULT KEY.

* Phase 8 - bo dem monitoring (Screen 0500)
DATA: g_exec_curr    TYPE i,
      g_exec_success TYPE i,
      g_exec_error   TYPE i,
      g_stop_flag    TYPE c LENGTH 1.

* ============================================================
* MUC 2 - Engine constants / single source of truth
* ============================================================
CONSTANTS:
  GC_ST_READY      TYPE C LENGTH 10 VALUE 'READY',
  GC_ST_SUCCESS    TYPE C LENGTH 10 VALUE 'SUCCESS',
  GC_ST_ERROR      TYPE C LENGTH 10 VALUE 'ERROR',
  GC_ST_WARNING    TYPE C LENGTH 10 VALUE 'WARNING',
  GC_ST_PROCESSED  TYPE C LENGTH 10 VALUE 'PROCESSED',
  GC_ST_PARTIAL    TYPE C LENGTH 10 VALUE 'PARTIAL',
  GC_ST_SKIPPED    TYPE C LENGTH 10 VALUE 'SKIPPED',
  GC_ST_QUEUED     TYPE C LENGTH 10 VALUE 'QUEUED',
  GC_ST_PROCESSING TYPE C LENGTH 12 VALUE 'PROCESSING',
  GC_ST_VERIFYING  TYPE C LENGTH 10 VALUE 'VERIFYING',
  GC_ST_SM35Q      TYPE C LENGTH 10 VALUE 'SM35QUEUE',

  GC_VT_STATIC     TYPE C LENGTH 10 VALUE 'STATIC',
  GC_VT_DYNAMIC    TYPE C LENGTH 10 VALUE 'DYNAMIC',

 "Runtime semantic layer. These values describe what a field IS, not
 "which TCODE it belongs to. CONFIG/profile owns the classification;
 "RUN only consumes the frozen metadata.
  GC_SEM_RAW       TYPE C LENGTH 20 VALUE 'RAW',
  GC_SEM_DATE      TYPE C LENGTH 20 VALUE 'DATE',
  GC_SEM_QUANTITY  TYPE C LENGTH 20 VALUE 'QUANTITY',
  GC_SEM_AMOUNT    TYPE C LENGTH 20 VALUE 'AMOUNT',
  GC_SEM_CURRENCY  TYPE C LENGTH 20 VALUE 'CURRENCY',
  GC_SEM_UNIT      TYPE C LENGTH 20 VALUE 'UNIT',
  GC_SEM_CATEGORY  TYPE C LENGTH 20 VALUE 'CATEGORY',
  GC_SEM_BOOLEAN   TYPE C LENGTH 20 VALUE 'BOOLEAN',
  GC_SEM_SKIP_BDC  TYPE C LENGTH 20 VALUE 'SKIP_BDC',
  GC_PUSH_PUSH     TYPE C LENGTH 20 VALUE 'PUSH',
  GC_PUSH_SKIP     TYPE C LENGTH 20 VALUE 'SKIP_BDC',

 "Generic format contract. These are not TCODE rules. They are
 "format actions stored/derived by CONFIG and consumed by RUN.
  GC_FMT_NONE      TYPE C LENGTH 20 VALUE 'NONE',
  GC_FMT_DATE      TYPE C LENGTH 20 VALUE 'DATE',
  GC_FMT_NUMBER    TYPE C LENGTH 20 VALUE 'NUMBER',
  GC_FMT_PAD_LEFT  TYPE C LENGTH 20 VALUE 'PAD_LEFT',
  GC_FMT_ALPHA     TYPE C LENGTH 20 VALUE 'ALPHA',
  GC_FMT_DDIC_CODE TYPE C LENGTH 20 VALUE 'DDIC_CODE',
  GC_FMT_UPPER     TYPE C LENGTH 20 VALUE 'UPPER',

  GC_RT_HEADER     TYPE C LENGTH 1  VALUE 'H',
  GC_RT_ITEM       TYPE C LENGTH 1  VALUE 'I',
  GC_PH_INDEX      TYPE C LENGTH 5  VALUE '&IDX&',

  GC_MODE_CALL     TYPE C LENGTH 30 VALUE 'CALL_TRANSACTION',
  GC_MODE_BATCH    TYPE C LENGTH 30 VALUE 'BATCH_INPUT',
  GC_MON_SM35      TYPE C LENGTH 1  VALUE 'B',

 "SAP standard Batch Input monitor transaction. This is a platform
 "navigation constant, not a business TCODE dispatch rule.
  GC_TCODE_SM35    TYPE SY-TCODE VALUE 'SM35',

 "Generic technical trace token used by the live engine.
  GC_TRACE_TOKEN   TYPE C LENGTH 20 VALUE '&ZBDC_TRACE&'.

* External AI advisory request/response state is local to M4_ERROR.

* ============================================================
* MUC 2 V3 - Screen 0400 BUP Execution Cockpit (khong con display goc)
* ============================================================
CONSTANTS:
  GC_VIEW_COCKPIT TYPE C LENGTH 1 VALUE 'C',
  GC_VIEW_DETAIL  TYPE C LENGTH 1 VALUE 'D'.

TYPES: BEGIN OF TY_EXEC_DISP,
         SELECTED      TYPE C LENGTH 1,
         ICON          TYPE C LENGTH 4,
         BATCH_KEY     TYPE C LENGTH 22,
         SOURCE_FILE   TYPE C LENGTH 80,
         SHEET_NAME    TYPE C LENGTH 40,
         SESSION_ID    TYPE ZBDC_STAGING_BUP-SESSION_ID,
         GROUP_KEY     TYPE ZBDC_STAGING_BUP-RECORD_KEY,
         TCODE         TYPE ZBDC_STAGING_BUP-TCODE,
         ITEM_COUNT    TYPE I,
         RUN_STATUS    TYPE C LENGTH 20,
         SAP_OBJECT_ID TYPE ZBDC_RESULT_BUP-SAP_OBJECT_ID,
         SAP_OBJECT_TEXT TYPE C LENGTH 80,
         REVIEW_STATE  TYPE C LENGTH 20,
         ATTEMPT       TYPE I,
         MSG_TYPE      TYPE C LENGTH 1,
         MESSAGE       TYPE C LENGTH 255,
         DRILL_TCODE   TYPE C LENGTH 20,
         HEALTH_TEXT   TYPE C LENGTH 40,
         ACTION_HINT   TYPE C LENGTH 80,
         EXECUTION      TYPE C LENGTH 32, "exact executor + attempt projection
         READY_COUNT   TYPE I,
         SUCCESS_COUNT TYPE I,
         ERROR_COUNT   TYPE I,
         WARNING_COUNT TYPE I,
         PROCESSED_COUNT TYPE I,
         SM35_COUNT    TYPE I,
         CELL_COLORS   TYPE LVC_T_SCOL,
         CELL_STYLES   TYPE LVC_T_STYL,
       END OF TY_EXEC_DISP.

TYPES: TY_T_EXEC_DISP TYPE STANDARD TABLE OF TY_EXEC_DISP WITH DEFAULT KEY,
       TY_T_RESULT    TYPE STANDARD TABLE OF ZBDC_RESULT_BUP WITH DEFAULT KEY.

* Named elementary types are required for FORM interface parameters;
* ABAP does not accept inline LENGTH additions in a FORM formal parameter.
TYPES: ty_nav_param_id    TYPE c LENGTH 20,
       ty_nav_msgv_idx    TYPE c LENGTH 1,
       ty_nav_object_type TYPE c LENGTH 60,
       ty_nav_confidence  TYPE c LENGTH 10.

TYPES: BEGIN OF ty_nav_binding,
         seq        TYPE i,
         msgv_idx   TYPE ty_nav_msgv_idx,
         field_name TYPE bdcdata-fnam,
         param_id   TYPE ty_nav_param_id,
         value      TYPE c LENGTH 255,
         old_value  TYPE c LENGTH 255,
       END OF ty_nav_binding,
       ty_t_nav_binding TYPE STANDARD TABLE OF ty_nav_binding WITH DEFAULT KEY.

TYPES: BEGIN OF ty_nav_screen_field,
         seq         TYPE i,
         field_name  TYPE bdcdata-fnam,
         label       TYPE c LENGTH 80,
         param_id    TYPE ty_nav_param_id,
         func_code   TYPE syucomm,
         field_type  TYPE c LENGTH 11,
         entry_state TYPE c LENGTH 1,
         bindable    TYPE abap_bool,
         input_ok    TYPE abap_bool,
       END OF ty_nav_screen_field,
       ty_t_nav_screen_field TYPE STANDARD TABLE OF ty_nav_screen_field WITH DEFAULT KEY.

TYPES: BEGIN OF ty_nav_evidence,
         session_id    TYPE zbdc_session_bup-session_id,
         group_key     TYPE zbdc_staging_bup-record_key,
         tcode         TYPE zbdc_prof_bup-tcode,
         profile_name  TYPE zbdc_prof_bup-profile_name,
         profile_ver   TYPE zbdc_prof_bup-profile_ver,
         script_id     TYPE zbdc_script_bup-script_id,
         contract_hash TYPE zbdc_script_bup-contract_hash,
         msgid          TYPE symsgid,
         msgnr          TYPE symsgno,
         message_text   TYPE string,
         msgv1          TYPE string,
         msgv2          TYPE string,
         msgv3          TYPE string,
         msgv4          TYPE string,
         nav_state      TYPE c LENGTH 20,
       END OF ty_nav_evidence.

DATA: GT_EXEC_DISP       TYPE TY_T_EXEC_DISP,
      GV_0400_VIEW       TYPE C LENGTH 1 VALUE GC_VIEW_COCKPIT,
      GV_0400_EDIT_MODE  TYPE C LENGTH 1,
      GV_0400_BATCH_SCOPE TYPE ABAP_BOOL,
      GV_0400_RENDER_SID  TYPE ZBDC_STAGING_BUP-SESSION_ID,
      GV_0400_RENDER_VIEW TYPE C LENGTH 1,
      GV_0400_CONTEXT_SID TYPE ZBDC_STAGING_BUP-SESSION_ID,
      GV_0400_CONTEXT_BATCH TYPE ZBDC_STAGING_BUP-SESSION_ID,
      GV_0400_CONTEXT_BATCH_SCOPE TYPE ABAP_BOOL,
      GV_0400_CONTEXT_LOCKED TYPE ABAP_BOOL,
      GV_EXEC_TOTAL_GRP  TYPE I,
      GV_EXEC_READY_GRP  TYPE I,
      GV_EXEC_SUCC_GRP   TYPE I,
      GV_EXEC_ERR_GRP    TYPE I,
      GV_EXEC_WARN_GRP   TYPE I,
      GV_EXEC_PROC_GRP   TYPE I,
      GV_EXEC_SM35_GRP   TYPE I,
      GV_EXEC_RETRY_GRP  TYPE I,
      GV_EXEC_PROGRESS    TYPE C LENGTH 30,
      GV_EXEC_HEADER_TXT   TYPE C LENGTH 255,
      GV_LAST_SM35_GROUP  TYPE APQI-GROUPID,
      GV_LAST_SM35_QID    TYPE APQI-QID,
      GV_LAST_SM35_POLICY TYPE C LENGTH 1,
      GV_LAST_SM35_ACTION  TYPE C LENGTH 180,
      GV_LAST_SM35_JOBNAME TYPE TBTCO-JOBNAME,
      GV_LAST_SM35_JOBCOUNT TYPE TBTCO-JOBCOUNT,
      GV_SM35_RETRY_GROUP  TYPE APQI-GROUPID,
      GV_SM35_RETRY_COUNT  TYPE I,
      GV_LAST_SM35_INSERTED TYPE I,
      GV_LAST_SM35_EXPECTED TYPE I,
      GV_EXEC_RUN_TOTAL    TYPE I,
      GV_EXEC_RUN_DONE     TYPE I,
      GV_EXEC_RUN_START_RT TYPE I,
      GV_EXEC_RUN_ACTIVE   TYPE ABAP_BOOL,
      GV_EXEC_RUN_ENGINE   TYPE C LENGTH 1,
      GV_EXEC_RUN_PHASE    TYPE C LENGTH 80,
      G_0400_GRID_EVENTS   TYPE REF TO LCL_GRID_EVENTS.

* persistent, click-by-click row selection for the 0400 cockpit.
* The business key is stored instead of a visual row index, so refresh/sort
* does not silently move a user's selection to another document group.
TYPES: BEGIN OF TY_0400_SEL_KEY,
         SESSION_ID TYPE ZBDC_STAGING_BUP-SESSION_ID,
         GROUP_KEY  TYPE ZBDC_STAGING_BUP-RECORD_KEY,
         TCODE      TYPE SY-TCODE,
       END OF TY_0400_SEL_KEY.
TYPES TY_T_0400_SEL_KEY TYPE HASHED TABLE OF TY_0400_SEL_KEY
  WITH UNIQUE KEY SESSION_ID GROUP_KEY TCODE.

DATA GT_0400_SEL_KEYS TYPE TY_T_0400_SEL_KEY.

* exact user-selected staging edit/audit scope.
* Native cockpit row selection is expanded to persisted staging ROW_INDEX keys
* before entering Detail. Nothing outside this set may be edited or audited.
TYPES: BEGIN OF ty_z566_edit_row,
         session_id TYPE zbdc_staging_bup-session_id,
         row_index  TYPE zbdc_staging_bup-row_index,
         record_key TYPE zbdc_staging_bup-record_key,
         tcode      TYPE zbdc_staging_bup-tcode,
       END OF ty_z566_edit_row.
TYPES ty_t_z566_edit_row TYPE SORTED TABLE OF ty_z566_edit_row
  WITH UNIQUE KEY session_id row_index.
TYPES ty_t_z566_staging_db TYPE STANDARD TABLE OF zbdc_staging_bup WITH DEFAULT KEY.
DATA: gt_z566_edit_scope TYPE ty_t_z566_edit_row,
      gv_z566_edit_groups TYPE i.

*& scalable native SAP GUI Change History / side-by-side diff

TYPES: BEGIN OF ty_z770_audit_raw,
         change_id     TYPE char80,
         session_id    TYPE zbdc_staging_bup-session_id,
         row_index     TYPE zbdc_staging_bup-row_index,
         tcode         TYPE sy-tcode,
         field_name    TYPE char30,
         old_value     TYPE char255,
         new_value     TYPE char255,
         changed_by    TYPE syuname,
         changed_at    TYPE timestampl,
         change_action TYPE char30,
       END OF ty_z770_audit_raw.
TYPES ty_t_z770_audit_raw TYPE STANDARD TABLE OF ty_z770_audit_raw WITH DEFAULT KEY.

TYPES: BEGIN OF ty_z770_audit_disp,
         seq_no       TYPE i,
         changed_at   TYPE timestampl,
         changed_text TYPE char19,
         group_key    TYPE zbdc_staging_bup-record_key,
         row_index    TYPE zbdc_staging_bup-row_index,
         tcode        TYPE sy-tcode,
         field_label  TYPE char80,
         before_value TYPE char255,
         after_value  TYPE char255,
         changed_by   TYPE syuname,
         change_id    TYPE char80,
       END OF ty_z770_audit_disp.
TYPES ty_t_z770_audit_disp TYPE STANDARD TABLE OF ty_z770_audit_disp WITH DEFAULT KEY.

TYPES: BEGIN OF ty_z770_diff_disp,
         field_label TYPE char80,
         field_value TYPE char255,
         row_color   TYPE char4,
       END OF ty_z770_diff_disp.
TYPES ty_t_z770_diff_disp TYPE STANDARD TABLE OF ty_z770_diff_disp WITH DEFAULT KEY.

DATA: gt_z770_audit_raw     TYPE ty_t_z770_audit_raw,
      gt_z770_audit_disp    TYPE ty_t_z770_audit_disp,
      gt_z770_before_disp   TYPE ty_t_z770_diff_disp,
      gt_z770_after_disp    TYPE ty_t_z770_diff_disp,
      gv_z770_selected_idx  TYPE i,
      gv_z770_total_changes TYPE i,
      gv_z770_changed_rows  TYPE i,
      gv_z770_changed_groups TYPE i,
      go_z770_dialog        TYPE REF TO cl_gui_dialogbox_container,
      go_z770_split_main    TYPE REF TO cl_gui_splitter_container,
      go_z770_split_diff    TYPE REF TO cl_gui_splitter_container,
      go_z770_hist_cont     TYPE REF TO cl_gui_container,
      go_z770_before_cont   TYPE REF TO cl_gui_container,
      go_z770_after_cont    TYPE REF TO cl_gui_container,
      go_z770_hist_grid     TYPE REF TO cl_gui_alv_grid,
      go_z770_before_grid   TYPE REF TO cl_gui_alv_grid,
      go_z770_after_grid    TYPE REF TO cl_gui_alv_grid.

CLASS LCL_GRID_EVENTS DEFINITION.
  PUBLIC SECTION.
    INTERFACES IF_ALV_RM_GRID_FRIEND.
    METHODS CONFIGURE_0400_GRID IMPORTING IR_GRID TYPE REF TO CL_GUI_ALV_GRID.
    METHODS ON_0301_TOOLBAR FOR EVENT TOOLBAR OF CL_GUI_ALV_GRID
      IMPORTING E_OBJECT E_INTERACTIVE.
    METHODS ON_0301_USER_COMMAND FOR EVENT USER_COMMAND OF CL_GUI_ALV_GRID
      IMPORTING E_UCOMM.
    METHODS ON_0301_DOUBLE_CLICK FOR EVENT DOUBLE_CLICK OF CL_GUI_ALV_GRID
      IMPORTING E_ROW E_COLUMN ES_ROW_NO.
    METHODS ON_0301_HOTSPOT_CLICK FOR EVENT HOTSPOT_CLICK OF CL_GUI_ALV_GRID
      IMPORTING E_ROW_ID E_COLUMN_ID ES_ROW_NO.
    METHODS ON_0400_TOOLBAR FOR EVENT TOOLBAR OF CL_GUI_ALV_GRID
      IMPORTING E_OBJECT E_INTERACTIVE.
    METHODS ON_0400_USER_COMMAND FOR EVENT USER_COMMAND OF CL_GUI_ALV_GRID
      IMPORTING E_UCOMM.
    METHODS ON_0400_HOTSPOT_CLICK FOR EVENT HOTSPOT_CLICK OF CL_GUI_ALV_GRID
      IMPORTING E_ROW_ID E_COLUMN_ID ES_ROW_NO.
    METHODS ON_0500_TOOLBAR FOR EVENT TOOLBAR OF CL_GUI_ALV_GRID
      IMPORTING E_OBJECT E_INTERACTIVE.
    METHODS ON_0500_USER_COMMAND FOR EVENT USER_COMMAND OF CL_GUI_ALV_GRID
      IMPORTING E_UCOMM.
    METHODS ON_0500_HOTSPOT_CLICK FOR EVENT HOTSPOT_CLICK OF CL_GUI_ALV_GRID
      IMPORTING E_ROW_ID E_COLUMN_ID ES_ROW_NO.
    METHODS ON_0500_ATTEMPT_CLOSE FOR EVENT CLOSE OF CL_GUI_DIALOGBOX_CONTAINER
      IMPORTING SENDER.
    METHODS ON_0650_DELAYED_SEL FOR EVENT DELAYED_CHANGED_SEL_CALLBACK OF CL_GUI_ALV_GRID.
    METHODS ON_0650_HOTSPOT_CLICK FOR EVENT HOTSPOT_CLICK OF CL_GUI_ALV_GRID
      IMPORTING E_ROW_ID E_COLUMN_ID ES_ROW_NO.
    METHODS ON_Z770_AUDIT_DOUBLE_CLICK FOR EVENT DOUBLE_CLICK OF CL_GUI_ALV_GRID
      IMPORTING E_ROW E_COLUMN ES_ROW_NO.
    METHODS ON_Z770_DIALOG_CLOSE FOR EVENT CLOSE OF CL_GUI_DIALOGBOX_CONTAINER
      IMPORTING SENDER.
ENDCLASS.

*&=====================================================================*
*& USER-CENTRIC UX/PRODUCT LOGIC TYPES
*& These types normalize optional setup tables without hardcoding DDIC
*& field names in the main runtime flow.
*&=====================================================================*
CONSTANTS:
  gc_z16_tab_fguide TYPE tabname VALUE 'ZBDC_FGUID_BUP',
  gc_z16_tab_vrule  TYPE tabname VALUE 'ZBDC_VRULE_BUP',
  gc_z16_tab_error  TYPE tabname VALUE 'ZBDC_ERROR_BUP',
  gc_z16_tab_chg    TYPE tabname VALUE 'ZBDC_CHG_BUP'.

TYPES: BEGIN OF ty_z16_rule,
         rule_id      TYPE char30,
         is_active    TYPE c LENGTH 1,
         tcode        TYPE char20,
         layer        TYPE char20,
         fieldname    TYPE char30,
         rule_type    TYPE char30,
         severity     TYPE char10,
         check_table  TYPE tabname,
         check_field1 TYPE fieldname,
         param1       TYPE char120,
         param2       TYPE char120,
         param3       TYPE char120,
         message_text TYPE char255,
         hint_text    TYPE char255,
         sort_order   TYPE i,
       END OF ty_z16_rule.
TYPES ty_t_z16_rule TYPE STANDARD TABLE OF ty_z16_rule WITH DEFAULT KEY.

*&=====================================================================*
*& ACTIVE DYNPRO LIFECYCLE EXTENSIONS
*&=====================================================================*

* Screen 0350 - Mapping Profile Configuration

DATA: gt_mapping_screen TYPE STANDARD TABLE OF zbdc_mapping_bup,
      go_container_0350 TYPE REF TO cl_gui_custom_container,
      go_map_grid       TYPE REF TO cl_gui_alv_grid.

* Screen 0500 - Execution Monitor

DATA: txtgv_exec_session TYPE char30,
      txtgv_exec_curr    TYPE char10,
      txtgv_exec_total   TYPE char10,
      txtgv_exec_pct     TYPE char10,
      txtgv_exec_elapsed TYPE char20,
      txtgv_exec_eta     TYPE char20,
      chkp_stop_on_error TYPE c LENGTH 1,
      chkp_background    TYPE c LENGTH 1,
      gv_exec_start_ts   TYPE timestampl,
      gv_exec_end_ts     TYPE timestampl,

      gv_exec_elapsed    TYPE i,
      gv_exec_scope_0500 TYPE char10,
      gv_exec_scope_text TYPE char60,
      gv_exec_scope_ready TYPE abap_bool,
      gv_exec_stop_req   TYPE abap_bool,
      gt_exec_scope_0500 TYPE STANDARD TABLE OF ty_staging_alv,
      go_dock_0500       TYPE REF TO cl_gui_docking_container,
      go_grid_0500       TYPE REF TO cl_gui_alv_grid,
      g_0500_grid_events TYPE REF TO lcl_grid_events,
      gv_0500_layout_mode TYPE c LENGTH 1,
      gv_0500_active      TYPE abap_bool.

* Screen 0500 - exact persisted execution-attempt history popup.
* One row is one real CT/BISM execution attempt. A READY correction only
* previews the next number in the main Execution column and is not appended
* here until execution evidence with ATTEMPT_NO is actually persisted.
TYPES: BEGIN OF ty_attempt_0500_disp,
         attempt     TYPE i,
         executor    TYPE c LENGTH 12,
         status      TYPE c LENGTH 20,
         started_at  TYPE c LENGTH 19,
         finished_at TYPE c LENGTH 19,
         result      TYPE c LENGTH 255,
       END OF ty_attempt_0500_disp.
TYPES ty_t_attempt_0500_disp TYPE STANDARD TABLE OF ty_attempt_0500_disp
  WITH DEFAULT KEY.

DATA: gt_attempt_0500_disp TYPE ty_t_attempt_0500_disp,
      go_attempt_0500_dlg  TYPE REF TO cl_gui_dialogbox_container,
      go_attempt_0500_grid TYPE REF TO cl_gui_alv_grid.

* Exact runtime queue projection shared by CT and SM35.
* It contains display state only; it is not an alternative executor.

TYPES: BEGIN OF ty_exec_qstate,
         session_id TYPE zbdc_staging_bup-session_id,
         record_key TYPE zbdc_staging_bup-record_key,
         row_index  TYPE zbdc_staging_bup-row_index,
         seq_no     TYPE i,
         state      TYPE c LENGTH 20,
         message    TYPE c LENGTH 255,
         sap_object TYPE zbdc_result_bup-sap_object_id,
       END OF ty_exec_qstate.
TYPES ty_t_exec_qstate TYPE STANDARD TABLE OF ty_exec_qstate
  WITH DEFAULT KEY.

DATA: gt_exec_qstate       TYPE ty_t_exec_qstate,
      gv_exec_run_queued   TYPE i,
      gv_exec_mon_kind     TYPE c LENGTH 1,
      gv_sm35_mon_qid      TYPE apqi-qid,
      gv_sm35_mon_group    TYPE apqi-groupid,
      gv_sm35_mon_timeout  TYPE i,
      gv_sm35_job_finished TYPE abap_bool,
      gv_sm35_last_qstate  TYPE apqi-qstate,
      gt_sm35_mon_process  TYPE ty_t_staging_alv.

* Frontend automation return variables must be global; local IMPORTING targets
* can trigger SYSTEM_POINTER_PENDING when the CFW flush completes later.

* Runtime issue and result-detail context

DATA: g_edit_index TYPE sy-tabix,
      txtp_po_key  TYPE char40.

* Screen 0560 - Selected-group correction scope ()

TYPES: BEGIN OF ty_0560_old_opt,
         key   TYPE char20,
         value TYPE string,
         text  TYPE char80,
       END OF ty_0560_old_opt.
TYPES ty_t_0560_old_opt TYPE STANDARD TABLE OF ty_0560_old_opt
  WITH DEFAULT KEY.

DATA: p_bus_group        TYPE zbdc_staging_bup-record_key,
      p_fld_name         TYPE char30,
      p_old_val          TYPE char80,
      p_new_val          TYPE char255,
      gv_0560_prepared   TYPE abap_bool,
      gv_0560_last_group TYPE zbdc_staging_bup-record_key,
      gv_0560_last_field TYPE char30,
      gv_0560_group_count TYPE i.
DATA: gt_0560_map        TYPE STANDARD TABLE OF zbdc_mapping_bup WITH DEFAULT KEY,
      gt_0560_groups     TYPE ty_t_engine_group_key,
      gt_0560_ready_done TYPE ty_t_engine_group_key,
      gt_0560_old_opt    TYPE ty_t_0560_old_opt.

* Result Dashboard data model (SALV popup + main dashboard)

TYPES: BEGIN OF ty_result_summary,
         session_id        TYPE zbdc_result_bup-session_id,
         executor_type     TYPE char30,
         bdc_display_mode  TYPE char10,
         update_mode       TYPE char10,
         total_records     TYPE i,
         processed_records TYPE i,
         ready_records     TYPE i,
         sm35_queue_records TYPE i,
         success_records   TYPE i,
         warning_records   TYPE i,
         error_records     TYPE i,
         retry_count       TYPE i,
         log_count         TYPE i,
         success_rate      TYPE char20,
         queue_progress    TYPE char30,
         process_progress  TYPE char30,
         status_text       TYPE char40,
         next_action       TYPE char80,
         last_message      TYPE zbdc_result_bup-message,
       END OF ty_result_summary.

TYPES: BEGIN OF ty_result_card,
         section     TYPE char24,
         metric      TYPE char50,
         value       TYPE char80,
         detail      TYPE char120,
         status_text TYPE char40,
         next_action TYPE char100,
       END OF ty_result_card.

CLASS lcl_exec_timer DEFINITION.
  PUBLIC SECTION.
    METHODS on_finished FOR EVENT finished OF cl_gui_timer.
ENDCLASS.
DATA: go_timer_0500     TYPE REF TO cl_gui_timer,
      go_timer_hdl_0500 TYPE REF TO lcl_exec_timer,
      gv_timer_0500_on  TYPE abap_bool,
      gv_timer_0500_sec TYPE i VALUE 1.  "Whole-second evidence polling

DATA: gt_result_all       TYPE STANDARD TABLE OF zbdc_result_bup,
      gt_result_msg       TYPE STANDARD TABLE OF zbdc_result_bup,
      gt_result_summary   TYPE STANDARD TABLE OF ty_result_summary,
      gt_result_cards     TYPE STANDARD TABLE OF ty_result_card,
      txtp_result_session TYPE zbdc_result_bup-session_id.

* Context-aware Result Dashboard scope.
* 0400 Result Dashboard = all Business Groups in the exact current session.
* 0500 Result Dashboard = the exact frozen execution/monitor scope.
DATA: gt_dash_scope_826   TYPE ty_t_0400_sel_key,
      gv_dash_scope_count_826 TYPE i,
      gv_dash_scope_source_826 TYPE char20,
      gv_dash_run_mode_826 TYPE char24.

* Dynamic visual Result Dashboard.
* Read-only frontend controls only; execution/staging/mapping logic is untouched.
TYPES ty_t_dash_html_411 TYPE STANDARD TABLE OF char255 WITH DEFAULT KEY.

CLASS lcl_dash_html_411 DEFINITION.
  PUBLIC SECTION.
    METHODS on_dialog_close FOR EVENT close OF cl_gui_dialogbox_container
      IMPORTING sender.
ENDCLASS.

DATA: go_dash_411_dlg  TYPE REF TO cl_gui_dialogbox_container,
      go_dash_411_html TYPE REF TO cl_gui_html_viewer,
      go_dash_evt_411  TYPE REF TO lcl_dash_html_411,
      gv_dash_411_url  TYPE c LENGTH 255.

* Screen 0650 - Result Investigation workspace

TYPES: BEGIN OF ty_evidence_0650,
         "0650 user-first display order: exact message + provenance are visible
         "before any technical/debug columns. Optional technical evidence stays
         "to the far right and can be hidden when the selected group has none.
         step             TYPE zbdc_result_bup-step,
         message_type     TYPE char1,
         exact_message    TYPE zbdc_result_bup-message,
         evidence_time    TYPE char19,
         evidence_source  TYPE char30,
         screen           TYPE zbdc_result_bup-dynpro,
         row_index        TYPE zbdc_result_bup-row_index,
         attempt          TYPE zbdc_result_bup-attempt_no,
         message_id       TYPE char20,
         program          TYPE char40,
         technical_field  TYPE zbdc_result_bup-field_name,
         sap_object       TYPE zbdc_result_bup-sap_object_id,
       END OF ty_evidence_0650.
TYPES ty_t_evidence_0650 TYPE STANDARD TABLE OF ty_evidence_0650 WITH DEFAULT KEY.

* Screen 0650 uses a dedicated user-facing projection.  Do not bind the SALV
* directly to TY_GROUP_0100_DISP: that structure also contains RECORD_KEY,
* ROW_INDEX and other dashboard transport fields which can reappear through
* horizontal scrolling/layout variants.  Exact selection identity remains in
* GT_GROUP_CTX_0650 and is mapped by the same display row index.
TYPES: BEGIN OF ty_group_0650_disp,
         health      TYPE icon_d,
         group_key   TYPE c LENGTH 80,
         tcode       TYPE char20,
* 14Y: display-only text so a session header can leave Rows blank instead of
* leaking the technical integer value 0 into the user-facing header line.
         row_count   TYPE char10,
         lifecycle   TYPE char20,
* Normal group rows show the exact SESSION_ID.
         session_id  TYPE c LENGTH 30,
* 15A: dedicated user-facing session timestamp column.  Do not overload
* SESSION_ID with a timestamp on visual session-header rows.
         session_time TYPE char19,
* 14X/14Y: technical-only marker for visual session header rows.
         is_header   TYPE abap_bool,
* Whole-row ALV color.  Header rows get a light SAP group-band color without
* introducing fake business data or technical columns.
         line_color  TYPE char4,
* Technical SALV cell-style carrier; never part of the field catalog.
         cell_types  TYPE salv_t_int4_column,
       END OF ty_group_0650_disp.
TYPES ty_t_group_0650_disp TYPE STANDARD TABLE OF ty_group_0650_disp WITH DEFAULT KEY.

DATA: gt_log_0650       TYPE STANDARD TABLE OF zbdc_result_bup,
      gt_evidence_0650  TYPE ty_t_evidence_0650,
      go_container_0650 TYPE REF TO cl_gui_custom_container,
      go_grid_0650      TYPE REF TO cl_salv_table,
      gt_group_0650     TYPE ty_t_group_0650_disp,
      gt_group_ctx_0650 TYPE STANDARD TABLE OF ty_group_0100_disp,
      go_group_container_0650 TYPE REF TO cl_gui_custom_container,
      go_group_grid_0650 TYPE REF TO cl_gui_alv_grid,
      go_group_evt_0650 TYPE REF TO lcl_alv_events,
      gv_group_pick_0650 TYPE i,
      gv_result_row_index_0650 TYPE zbdc_staging_bup-row_index,
      txtp_sap_object_id TYPE char40,
      txtp_result_msg    TYPE char255,
      "Result Investigation (0650) - generic multi-TCode context
      txtp_result_group       TYPE char80,
      txtp_result_status      TYPE char20,
      txtp_result_created     TYPE char19,
      txtp_result_executor    TYPE char20,
      txtp_result_row_attempt TYPE char30,
      txtp_result_tcode       TYPE char20.


* ============================================================
* Screen 0650 - Result Investigation live refresh
* Uses the same Control Framework timer pattern as screen 0100.
* A 2-second timer only posts a silent OK code; database reads and ALV updates
* stay in normal PAI/PBO.  Scroll/selection is kept stable on live ticks.
* ============================================================
CLASS lcl_result_timer_0650 DEFINITION.
  PUBLIC SECTION.
    METHODS on_finished FOR EVENT finished OF cl_gui_timer.
ENDCLASS.

DATA: go_timer_0650       TYPE REF TO cl_gui_timer,
      go_timer_hdl_0650   TYPE REF TO lcl_result_timer_0650,
      gv_timer_0650_on    TYPE abap_bool,
      gv_timer_0650_sec   TYPE i VALUE 2,
      gv_result_0650_tick TYPE abap_bool,
      gv_result_0650_skip_pbo TYPE abap_bool,
      "15F: exact group selection already loaded GT_LOG_0650 in PAI.
      "The following PBO can therefore skip the duplicate SELECT/sync pass.
      gv_result_0650_fast_pbo TYPE abap_bool,
      "15F: evidence grid is recreated only when its visible layout shape
      "changes (for example empty->data or technical metadata appears).
      "Normal group-to-group selection uses SALV refresh instead.
      gv_evidence_shape_0650  TYPE string,
      gv_sig_0650         TYPE string.

* Screen 0700 - Error Analyst / Fix Advisor

TYPES: BEGIN OF ty_ai_pattern,
         pattern_id TYPE char20,
         session_id TYPE zbdc_result_bup-session_id,
         msg_type   TYPE zbdc_result_bup-msg_type,
         msg_id     TYPE char20,
         msg_number TYPE char10,
         dynpro     TYPE char20,
         field_name TYPE char40,
         count      TYPE i,
         message    TYPE char255,
         fix_hint   TYPE char255,
       END OF ty_ai_pattern.

* Screen 0700 left pane is an evidence landscape, not a debug/pattern table.
* Keep only fields a business user needs to understand the selected ERROR group.
TYPES ty_t_string_0700 TYPE STANDARD TABLE OF string WITH DEFAULT KEY.

TYPES: BEGIN OF ty_issue_0700_disp,
         issue_no         TYPE i,
         severity         TYPE char12,
         summary          TYPE char120,
         issue_message    TYPE char255,
         field_name       TYPE char40,
         current_value    TYPE char120,
         allowed_length   TYPE char20,
         category         TYPE char20,
         evidence_source  TYPE char30,
         source_row_index TYPE zbdc_result_bup-row_index,
         cell_types       TYPE salv_t_int4_column,
       END OF ty_issue_0700_disp.
TYPES ty_t_issue_0700_disp TYPE STANDARD TABLE OF ty_issue_0700_disp WITH DEFAULT KEY.

DATA: gt_patterns       TYPE STANDARD TABLE OF ty_ai_pattern,
      gt_issue_0700     TYPE ty_t_issue_0700_disp,
      go_container_0700 TYPE REF TO cl_gui_custom_container,
      go_pattern_grid   TYPE REF TO cl_salv_table,
      go_issue_evt_0700 TYPE REF TO lcl_alv_events,
      gv_issue_pick_0700 TYPE i,
      gv_issue_selected_0700 TYPE i,

 "Right panel: AI Fix Suggestions
      go_ai_text_container TYPE REF TO cl_gui_custom_container,
      go_ai_textedit       TYPE REF TO cl_gui_textedit,

      txtp_ai_session   TYPE char30,
      txtp_ai_text      TYPE string,
      "AI Insight (0700) context fields
      txtp_ai_group      TYPE char80,
      txtp_ai_tcode      TYPE char20,
      txtp_ai_evidence   TYPE char20,
      txtp_ai_source     TYPE char30,
      "0700 auto-diagnose guard: one deterministic pass per exact group.
      gv_ai_auto_diag_done TYPE abap_bool,
      gv_ai_auto_diag_key  TYPE string,
      gv_ai_selected_root  TYPE string,
      gv_ai_selected_fix   TYPE string,
      gv_ai_selected_verify TYPE string.

* non-blocking exact-group Fix Guide AI state.
* The guide opens immediately from deterministic/cached evidence. OpenAI is
* invoked only by an explicit user action and then refreshes the same popup.
TYPES: BEGIN OF ty_fix_card_789,
         section TYPE char32,
         detail  TYPE char255,
       END OF ty_fix_card_789.
TYPES ty_t_fix_card_789 TYPE STANDARD TABLE OF ty_fix_card_789 WITH DEFAULT KEY.
DATA: gt_fix_guide_789        TYPE ty_t_fix_card_789,
      go_fix_guide_789        TYPE REF TO cl_salv_table,
      go_fix_guide_evt_789    TYPE REF TO lcl_alv_events,
      gv_fixguide_stg_idx_789 TYPE i.

* generic long-text renderer for Fix Guide and Runtime Issue Detail.
* Classic SALV cells can visually cap long values even when the popup is wide.
* Use a real HTML long-text surface so content wraps by available window width
* without truncating or creating fake continuation rows.
CLASS lcl_longtext_812 DEFINITION.
  PUBLIC SECTION.
    METHODS on_dialog_close FOR EVENT close OF cl_gui_dialogbox_container
      IMPORTING sender.
ENDCLASS.

DATA: go_long_812_dlg  TYPE REF TO cl_gui_dialogbox_container,
      go_long_812_html TYPE REF TO cl_gui_html_viewer,
      go_long_evt_812  TYPE REF TO lcl_longtext_812,
      gv_long_812_url  TYPE c LENGTH 255.

* Screen 0800 - SHDB Recording Editor
* Uses the local generic script line so the legacy editor remains available.

DATA: gt_script_def     TYPE ty_t_script,
      go_rec_container  TYPE REF TO cl_gui_custom_container,
      go_rec_grid       TYPE REF TO cl_gui_alv_grid,
      p_rec_tcode       TYPE char20.
