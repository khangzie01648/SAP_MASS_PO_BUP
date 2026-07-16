*&---------------------------------------------------------------------*
*& Include          Z_BDC_MASS_PO_ENTRY_TOP_BUP
*& Dinh nghia cau truc du lieu, bang tam va bien toan cuc
*& MUC 1 (giu nguyen 100%) + MUC 2 (bo sung o cuoi file)
*&---------------------------------------------------------------------*
TABLES: sscrfields.
TYPE-POOLS: ICON, LVC.

CLASS lcl_alv_events DEFINITION DEFERRED.
CLASS lcl_grid_events DEFINITION DEFERRED.

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
         health        TYPE icon_d,
         session_id    TYPE zbdc_result_bup-session_id,
         created_on    TYPE char19,
         sort_key      TYPE char30, "technical: YYYYMMDDHHMMSS, hidden in ALV
         created_by    TYPE syuname,
         source_type   TYPE char20,
         tcode         TYPE char20,
         status_text   TYPE char20,
         total_rec     TYPE i,
         ready_rec     TYPE i,
         success_rec   TYPE i,
         warning_rec   TYPE i,
         error_rec     TYPE i,
         success_pct   TYPE p LENGTH 5 DECIMALS 1,
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

DATA: txtgv_total_sessions TYPE char20,
      txtgv_processed_pos  TYPE char20,
      txtgv_success_count  TYPE char20,
      txtgv_warning_count  TYPE char20,
      txtgv_error_count    TYPE char20,
      txtgv_success_pct    TYPE char20,
      txtgv_warning_pct    TYPE char20,
      txtgv_error_pct      TYPE char20.

* ============================================================
* Screen 0200 - BDC Processing Configuration
* ============================================================
DATA: rb_rest     TYPE c LENGTH 1 VALUE 'X',
      rb_sftp     TYPE c LENGTH 1,
      rb_gdrive   TYPE c LENGTH 1,
      rb_local    TYPE c LENGTH 1.

DATA: txtp_webhook_url TYPE string,
      p_auth_type      TYPE char20,
      txtp_api_key     TYPE char255,
      txtp_timeout     TYPE i,
      chkp_retry       TYPE c LENGTH 1,
      txtp_sftp_host   TYPE char60,
      txtp_sftp_port   TYPE char10,
      txtp_username    TYPE char30,
      txtp_password    TYPE char30,
      txtp_gdrive_url  TYPE char255,
      txtp_file_path   TYPE string,
      p_transaction    TYPE char20 VALUE 'ME21N',
      p_format         TYPE char10 VALUE 'CSV',
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
      go_container_0302 TYPE REF TO cl_gui_custom_container,
      go_grid_0302      TYPE REF TO cl_salv_table.

DATA: gv_config_loaded TYPE c,
      gv_0200_saved_sig TYPE string,
      gv_0200_saved_ok  TYPE c LENGTH 1,
      gv_0200_last_stat TYPE char20,
      gv_0200_last_msg  TYPE char255,
      gv_0200_last_at   TYPE char30.

TYPES: BEGIN OF ty_files_disp,
         status_icon  TYPE icon_d,                         "UI only: traffic light
         batch_key    TYPE char22,                         "UI only: batch prefix derived from SESSION_ID
         file_title   TYPE char80,                         "UI only: clean file/source name
         sheet_name   TYPE char40,                         "UI only: Excel sheet / CSV data unit
         tx_code      TYPE char20,                         "UI only: ME21N/MIGO/... resolved per sheet
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
  gc_file_scope_all TYPE c LENGTH 1 VALUE 'A'.

DATA: gt_files_preview       TYPE STANDARD TABLE OF ty_files_disp,
      go_alv_events          TYPE REF TO lcl_alv_events,
      go_alv_file_events     TYPE REF TO lcl_alv_events,
      gv_file_scope          TYPE c LENGTH 1 VALUE 'M'.

* V4R Mass Automation Batch Context (code-only, no new SE11 fields)
* One upload/pull run = one compact batch prefix BYYYYMMDDHHMMSS.
* Each file/attachment/payload = one SESSION_ID with suffix _001/_002/...
* This stays code-only and fits old CHAR20/CHAR22 SESSION_ID designs.
DATA: gv_current_batch_prefix TYPE zbdc_staging_bup-session_id,
      gv_ingest_batch_prefix  TYPE zbdc_staging_bup-session_id,
      gv_forced_session_id    TYPE zbdc_staging_bup-session_id,
      gv_current_batch_count  TYPE i,
      gt_current_sessions     TYPE STANDARD TABLE OF zbdc_staging_bup-session_id.

* V4T File/Sheet data-unit context. No DDIC change: metadata is persisted
* by encoding SHEET in ZBDC_FILE_LG_BUP-FILE_NAME as: <file>|SHEET=<sheet>.
DATA: gv_current_file_name  TYPE string,
      gv_current_sheet_name TYPE char40,
      gv_current_unit_src   TYPE char20.

TYPES: BEGIN OF ty_preview_disp.
TYPES:   batch_key    TYPE char22,
         file_title   TYPE char80,
         sheet_name   TYPE char40,
         tx_code      TYPE char20,
         excel_row    TYPE i,
         business_key TYPE char40,
         status_text  TYPE char20,
         message_text TYPE char80,
         col01        TYPE char80,
         col02        TYPE char80,
         col03        TYPE char80,
         col04        TYPE char80,
         col05        TYPE char80,
         col06        TYPE char80,
         col07        TYPE char80,
         col08        TYPE char80,
         col09        TYPE char80,
         col10        TYPE char80,
         col11        TYPE char80,
         col12        TYPE char80,
         col13        TYPE char80,
         col14        TYPE char80,
         col15        TYPE char80,
         col16        TYPE char80,
         col17        TYPE char80,
         col18        TYPE char80,
         col19        TYPE char80,
         col20        TYPE char80,
         col21        TYPE char80,
         col22        TYPE char80,
         col23        TYPE char80,
         col24        TYPE char80,
         col25        TYPE char80.
TYPES: END OF ty_preview_disp.

DATA gt_preview_data TYPE STANDARD TABLE OF ty_preview_disp.

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
      p_filter          TYPE char1,
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
DATA: txtp_profile_name TYPE char50 VALUE 'DEFAULT_EXCEL_MAP',
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
      on_file_double_click FOR EVENT double_click OF cl_salv_events_table
        IMPORTING row column,
      on_file_function FOR EVENT added_function OF cl_salv_events_table
        IMPORTING e_salv_function.
ENDCLASS.


* ============================================================
* ===== MUC 2 - BDC GENERIC ENGINE (PHASE 4-8) ===============
* ===== Bien & type bo sung - KHONG dung cham code Muc 1 =====
* ============================================================
TYPES: ty_t_staging_alv TYPE STANDARD TABLE OF ty_staging_alv   WITH DEFAULT KEY,
       ty_t_script      TYPE STANDARD TABLE OF zbdc_sct_def_bup WITH DEFAULT KEY,
       ty_t_map         TYPE STANDARD TABLE OF zbdc_mapping_bup WITH DEFAULT KEY.

* V5AG - true database chunk scope: one key represents one SAP document.
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
  GC_ST_STAGED     TYPE C LENGTH 10 VALUE 'STAGED',
  GC_ST_READY      TYPE C LENGTH 10 VALUE 'READY',
  GC_ST_SUCCESS    TYPE C LENGTH 10 VALUE 'SUCCESS',
  GC_ST_ERROR      TYPE C LENGTH 10 VALUE 'ERROR',
  GC_ST_WARNING    TYPE C LENGTH 10 VALUE 'WARNING',
  GC_ST_SM35Q      TYPE C LENGTH 10 VALUE 'SM35QUEUE',

  GC_VT_STATIC     TYPE C LENGTH 10 VALUE 'STATIC',
  GC_VT_DYNAMIC    TYPE C LENGTH 10 VALUE 'DYNAMIC',

  GC_RT_HEADER     TYPE C LENGTH 1  VALUE 'H',
  GC_RT_ITEM       TYPE C LENGTH 1  VALUE 'I',
  GC_PH_INDEX      TYPE C LENGTH 5  VALUE '&IDX&',

  GC_MODE_CALL     TYPE C LENGTH 30 VALUE 'CALL_TRANSACTION',
  GC_MODE_BATCH    TYPE C LENGTH 30 VALUE 'BATCH_INPUT',

  "V5Q: the same A/E/N x S/A profile is consumed by both engines.
  "For CALL TRANSACTION, S/A remains the CTU database update mode.
  "For Batch Input Session, S/A is the managed launch policy:
  "S = start now and wait; A = release/queue and return.
  GC_SM35_SYNC     TYPE C LENGTH 1 VALUE 'S',
  GC_SM35_ASYNC    TYPE C LENGTH 1 VALUE 'A',

  GC_PROF_ME21N    TYPE C LENGTH 50 VALUE 'DEFAULT_EXCEL_MAP',
  GC_PROF_MIGO     TYPE C LENGTH 50 VALUE 'DEFAULT_MIGO_MAP',

  GC_MSGID_PO      TYPE SY-MSGID VALUE '06',
  GC_MSGNR_PO      TYPE SY-MSGNO VALUE '017',
  GC_MSGID_MIGO    TYPE SY-MSGID VALUE 'MIGO',
  GC_MSGNR_MIGO    TYPE SY-MSGNO VALUE '012',

  GC_MAX_ATTEMPTS  TYPE I VALUE 3,
  GC_WAIT_SECONDS  TYPE I VALUE 2,
  GC_BATCH_DEFAULT TYPE I VALUE 100,

* ---- Gemini AI Error Analyst (real LLM, with rule-based fallback) ----
* NOTE: verify the exact model string at ai.google.dev/gemini-api/docs/models
*       before demo; Google renames models often. Change only this constant.
  GC_GEMINI_MODEL  TYPE STRING VALUE 'gemini-3.5-flash',
  GC_GEMINI_HOST   TYPE STRING VALUE 'https://generativelanguage.googleapis.com',
  GC_GEMINI_CFGKEY TYPE C LENGTH 30 VALUE 'GEMINI_API_KEY'.

DATA: G_LAST_ENGINE_TEXT TYPE STRING,
      G_LAST_DOC_ID      TYPE ZBDC_RESULT_BUP-SAP_OBJECT_ID.

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
         ATTEMPT       TYPE I,
         MSG_TYPE      TYPE C LENGTH 1,
         MESSAGE       TYPE C LENGTH 255,
         DRILL_TCODE   TYPE C LENGTH 20,
         HEALTH_TEXT   TYPE C LENGTH 40,
         ACTION_HINT   TYPE C LENGTH 80,
         READY_COUNT   TYPE I,
         SUCCESS_COUNT TYPE I,
         ERROR_COUNT   TYPE I,
         WARNING_COUNT TYPE I,
         SM35_COUNT    TYPE I,
         CELL_COLORS   TYPE LVC_T_SCOL,
       END OF TY_EXEC_DISP.

TYPES: TY_T_EXEC_DISP TYPE STANDARD TABLE OF TY_EXEC_DISP WITH DEFAULT KEY,
       TY_T_RESULT    TYPE STANDARD TABLE OF ZBDC_RESULT_BUP WITH DEFAULT KEY.

DATA: GT_EXEC_DISP       TYPE TY_T_EXEC_DISP,
      GV_0400_VIEW       TYPE C LENGTH 1 VALUE GC_VIEW_COCKPIT,
      GV_0400_EDIT_MODE  TYPE C LENGTH 1,
      GV_EXEC_TOTAL_GRP  TYPE I,
      GV_EXEC_READY_GRP  TYPE I,
      GV_EXEC_SUCC_GRP   TYPE I,
      GV_EXEC_ERR_GRP    TYPE I,
      GV_EXEC_WARN_GRP   TYPE I,
      GV_EXEC_SM35_GRP   TYPE I,
      GV_EXEC_RETRY_GRP  TYPE I,
      GV_EXEC_PROGRESS    TYPE C LENGTH 30,
      GV_EXEC_HEADER_TXT   TYPE C LENGTH 255,
      GV_LAST_SM35_GROUP  TYPE APQI-GROUPID,
      GV_LAST_SM35_QID    TYPE APQI-QID,
      GV_LAST_SM35_MODE   TYPE C LENGTH 1,
      GV_LAST_SM35_POLICY TYPE C LENGTH 1,
      GV_LAST_SM35_PROFILE TYPE C LENGTH 100,
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

* V5AI - persistent, click-by-click row selection for the 0400 cockpit.
* The business key is stored instead of a visual row index, so refresh/sort
* does not silently move a user's selection to another document group.
TYPES: BEGIN OF TY_0400_SEL_KEY,
         SESSION_ID TYPE ZBDC_STAGING_BUP-SESSION_ID,
         GROUP_KEY  TYPE ZBDC_STAGING_BUP-RECORD_KEY,
         TCODE      TYPE SY-TCODE,
       END OF TY_0400_SEL_KEY.
TYPES TY_T_0400_SEL_KEY TYPE HASHED TABLE OF TY_0400_SEL_KEY
  WITH UNIQUE KEY SESSION_ID GROUP_KEY TCODE.

DATA: GT_0400_SEL_KEYS       TYPE TY_T_0400_SEL_KEY,
      GV_0400_SEL_SYNC       TYPE ABAP_BOOL,
      GV_0500_PENDING_RUN    TYPE ABAP_BOOL,
      GV_0500_PENDING_ENGINE TYPE C LENGTH 1,
      GV_0500_CONFIRMED      TYPE ABAP_BOOL.

CLASS LCL_GRID_EVENTS DEFINITION.
  PUBLIC SECTION.
    INTERFACES IF_ALV_RM_GRID_FRIEND.
    METHODS CONFIGURE_0400_GRID IMPORTING IR_GRID TYPE REF TO CL_GUI_ALV_GRID.
    METHODS ON_EXEC_DOUBLE_CLICK FOR EVENT DOUBLE_CLICK OF CL_GUI_ALV_GRID
      IMPORTING E_ROW E_COLUMN ES_ROW_NO.
    METHODS ON_0400_SEL_CHANGE FOR EVENT DELAYED_CHANGED_SEL_CALLBACK OF CL_GUI_ALV_GRID.
    METHODS ON_0400_TOOLBAR FOR EVENT TOOLBAR OF CL_GUI_ALV_GRID
      IMPORTING E_OBJECT E_INTERACTIVE.
    METHODS ON_0400_USER_COMMAND FOR EVENT USER_COMMAND OF CL_GUI_ALV_GRID
      IMPORTING E_UCOMM.
    METHODS ON_0500_TOOLBAR FOR EVENT TOOLBAR OF CL_GUI_ALV_GRID
      IMPORTING E_OBJECT E_INTERACTIVE.
    METHODS ON_0500_USER_COMMAND FOR EVENT USER_COMMAND OF CL_GUI_ALV_GRID
      IMPORTING E_UCOMM.
ENDCLASS.







*&=====================================================================*
*& FIX16 - USER-CENTRIC UX/PRODUCT LOGIC TYPES
*& These types normalize optional setup tables without hardcoding DDIC
*& field names in the main runtime flow.
*&=====================================================================*
CONSTANTS:
  gc_z16_tab_fguide TYPE tabname VALUE 'ZBDC_FGUID_BUP',
  gc_z16_tab_vrule  TYPE tabname VALUE 'ZBDC_VRULE_BUP',
  gc_z16_tab_error  TYPE tabname VALUE 'ZBDC_ERROR_BUP',
  gc_z16_tab_chg    TYPE tabname VALUE 'ZBDC_CHG_BUP'.

TYPES: BEGIN OF ty_z16_guide,
         tcode            TYPE char20,
         source_column    TYPE char80,
         staging_field    TYPE char30,
         display_label    TYPE char80,
         mandatory        TYPE c LENGTH 1,
         example_value    TYPE char120,
         rule_text        TYPE char255,
         suggested_values TYPE char255,
         responsible      TYPE char40,
         display_order    TYPE i,
       END OF ty_z16_guide.
TYPES ty_t_z16_guide TYPE STANDARD TABLE OF ty_z16_guide WITH DEFAULT KEY.

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

DATA: gt_z16_guide TYPE ty_t_z16_guide,
      gt_z16_rule  TYPE ty_t_z16_rule.

*&=====================================================================*
*& V7 PRO - 14 SCREEN LIFECYCLE EXTENSIONS
*& Goal: every designed screen has a real role, no orphan screens.
*&=====================================================================*
CLASS lcl_result_events DEFINITION DEFERRED.

* ------------------------------------------------------------
* Screen 0250 - OBSOLETE in current scope; kept only for old dynpro compatibility
* ------------------------------------------------------------
TYPES: BEGIN OF ty_job_disp,
         jobname    TYPE char32,
         jobcount   TYPE char8,
         status     TYPE char20,
         start_date TYPE sy-datum,
         start_time TYPE sy-uzeit,
         frequency  TYPE char20,
         message    TYPE char100,
       END OF ty_job_disp.
DATA: p_job_name       TYPE char32 VALUE 'ZBDC_MASS_PO_POLL',
      p_job_time       TYPE sy-uzeit,
      p_freq           TYPE char20 VALUE 'HOURLY',
      gt_jobs_0250     TYPE STANDARD TABLE OF ty_job_disp,
      go_container_0250 TYPE REF TO cl_gui_custom_container,
      go_grid_0250      TYPE REF TO cl_salv_table.

* ------------------------------------------------------------
* Screen 0350 - Mapping Profile Configuration
* ------------------------------------------------------------
DATA: gt_mapping_screen TYPE STANDARD TABLE OF zbdc_mapping_bup,
      go_container_0350 TYPE REF TO cl_gui_custom_container,
      go_map_grid       TYPE REF TO cl_gui_alv_grid.

* ------------------------------------------------------------
* Screen 0500 - Execution Monitor
* ------------------------------------------------------------
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

* ------------------------------------------------------------
* V5AN - Asynchronous RFC worker state for live 0500 progress
* Z_BDC_EXEC_ONE_BUP is a remote-enabled generic BDC worker.
* It is shared by ME21N and MIGO because TCODE and BDCDATA are
* supplied dynamically by the main engine.
* ------------------------------------------------------------
TYPES: ty_t_async_bdcdata TYPE STANDARD TABLE OF bdcdata
         WITH DEFAULT KEY,
       ty_t_async_bdcmsg  TYPE STANDARD TABLE OF bdcmsgcoll
         WITH DEFAULT KEY.

* V5AQ - Persistent runtime state for every selected business group.
* The ALV is rebuilt from DB on each PBO, so the queue state must not rely
* only on the currently active group variable. This table prevents selected
* groups from visually falling back to READY while the next RFC task runs.
TYPES: BEGIN OF ty_async_qstate,
         session_id TYPE zbdc_staging_bup-session_id,
         record_key TYPE zbdc_staging_bup-record_key,
         row_index  TYPE zbdc_staging_bup-row_index,
         seq_no     TYPE i,
         state      TYPE c LENGTH 20,
         message    TYPE c LENGTH 255,
         sap_object TYPE zbdc_result_bup-sap_object_id,
       END OF ty_async_qstate.
TYPES ty_t_async_qstate TYPE STANDARD TABLE OF ty_async_qstate
  WITH DEFAULT KEY.

DATA: gt_async_qstate    TYPE ty_t_async_qstate,
      gt_async_bdcdata    TYPE ty_t_async_bdcdata,
      gt_async_bdcmsg     TYPE ty_t_async_bdcmsg,
      gt_async_group      TYPE ty_t_staging_alv,
      gt_async_process    TYPE ty_t_staging_alv,
      gt_async_keys       TYPE ty_t_engine_group_key,
      gv_async_task       TYPE char32,
      gv_async_done       TYPE abap_bool,
      gv_async_active     TYPE abap_bool,
      gv_async_receive_rc TYPE sysubrc,
      gv_async_subrc      TYPE sysubrc,
      gv_async_message    TYPE char255,
      gv_async_system_msg TYPE char255,
      gv_async_tick       TYPE i,
      gv_async_key_index  TYPE i,
      gv_async_total      TYPE i,
      gv_async_run_start  TYPE i,
      gv_async_attempt    TYPE i,
      gv_async_max_try    TYPE i,
      gv_async_updmode    TYPE c LENGTH 1,
      gv_async_tcode      TYPE sy-tcode,
      gv_async_group_key  TYPE char40,
      gv_async_session_id TYPE zbdc_staging_bup-session_id,
      gv_async_lock_sid   TYPE zbdc_staging_bup-session_id,
      gv_async_lock_on    TYPE abap_bool,
      gv_async_any_error  TYPE abap_bool,
      gv_exec_run_queued  TYPE i,
      gv_exec_mon_kind    TYPE c LENGTH 1,
      gv_sm35_mon_qid        TYPE apqi-qid,
      gv_sm35_mon_group      TYPE apqi-groupid,
      gv_sm35_mon_start      TYPE i,
      gv_sm35_mon_timeout    TYPE i VALUE 300,
      gv_sm35_job_finished   TYPE abap_bool,
      gv_sm35_last_qstate    TYPE apqi-qstate,
      gt_sm35_mon_process    TYPE ty_t_staging_alv,
      gv_runtime_mode_override TYPE c LENGTH 1,
      gv_runtime_upd_override  TYPE c LENGTH 1,
      gv_sm35_fallback_active  TYPE abap_bool,
      gv_sm35_fallback_groups  TYPE i,
      gv_sm35_fallback_done    TYPE i,
      gv_sm35_fallback_error   TYPE i,
      gv_sm35_fallback_text    TYPE c LENGTH 255,
      gt_fb_process            TYPE ty_t_staging_alv,
      gt_fb_queue              TYPE ty_t_staging_alv,
      gt_fb_keys               TYPE ty_t_engine_group_key,
      gv_fb_group              TYPE apqi-groupid,
      gv_fb_idx                TYPE i,
      gv_fb_total              TYPE i,
      gv_fb_done               TYPE i,
      gv_fb_error              TYPE i,
      gv_fb_saved_mode         TYPE char30,
      gv_fb_saved_bg           TYPE c LENGTH 1,
      gv_fb_saved_stop         TYPE c LENGTH 1,
      gv_fb_saved_ovr_m        TYPE c LENGTH 1,
      gv_fb_saved_ovr_u        TYPE c LENGTH 1.

* Frontend automation return variables must be global; local IMPORTING targets
* can trigger SYSTEM_POINTER_PENDING when the CFW flush completes later.
DATA gv_z23_file_size_bytes TYPE i.

* ------------------------------------------------------------
* Screen 0550/0551/0552 - Detail Edit Popup
* ------------------------------------------------------------
DATA: g_edit_index       TYPE sy-tabix,
      g_detail_sub       TYPE sy-dynnr VALUE '0551',
      txtp_po_key        TYPE char40,
      txtp_detail_status TYPE char20,
      txtp_vendor        TYPE char50,
      txtp_purch_org     TYPE char20,
      txtp_purch_group   TYPE char20,
      txtp_company_code  TYPE char20,
      txtp_doc_type      TYPE char20,
      txtp_material      TYPE char50,
      txtp_quantity      TYPE char30,
      txtp_plant         TYPE char20,
      txtp_net_price     TYPE char30,
      txtp_stor_loc      TYPE char20,
      txtp_item_no       TYPE char20,
      txtp_delivery_date TYPE char20,
      txtp_fix_message   TYPE char255.

* ------------------------------------------------------------
* Screen 0560 - Mass Replacer
* ------------------------------------------------------------
DATA: p_fld_name        TYPE char30,
      p_old_val         TYPE char80,
      p_new_val         TYPE char80,
      txtgv_replace_cnt TYPE char20.

* ------------------------------------------------------------
* Screen 0600/0601/0602/0603 - Result Dashboard
* ------------------------------------------------------------
TYPES: BEGIN OF ty_result_summary,
         session_id        TYPE zbdc_result_bup-session_id,
         total_records     TYPE i,
         processed_records TYPE i,
         success_records   TYPE i,
         warning_records   TYPE i,
         error_records     TYPE i,
         ready_records     TYPE i,
         log_count         TYPE i,
         retry_count       TYPE i,
         status_text       TYPE char40,
         last_message      TYPE zbdc_result_bup-message,
       END OF ty_result_summary.

CLASS lcl_exec_timer DEFINITION.
  PUBLIC SECTION.
    METHODS on_finished FOR EVENT finished OF cl_gui_timer.
ENDCLASS.

CLASS lcl_result_timer DEFINITION.
  PUBLIC SECTION.
    METHODS on_finished FOR EVENT finished OF cl_gui_timer.
ENDCLASS.

DATA: go_timer_0500      TYPE REF TO cl_gui_timer,
      go_timer_hdl_0500  TYPE REF TO lcl_exec_timer,
      gv_timer_0500_on   TYPE abap_bool,
      gv_timer_0500_sec  TYPE i VALUE 1,  "CL_GUI_TIMER uses whole-second evidence polling
      go_timer_0600      TYPE REF TO cl_gui_timer,
      go_timer_hdl_0600  TYPE REF TO lcl_result_timer,
      gv_timer_0600_on   TYPE abap_bool,
      gv_timer_0600_sec  TYPE i VALUE 5.

DATA: g_result_sub       TYPE sy-dynnr VALUE '0601',
      gt_result_all      TYPE STANDARD TABLE OF zbdc_result_bup,
      gt_result_msg      TYPE STANDARD TABLE OF zbdc_result_bup,
      gt_result_summary  TYPE STANDARD TABLE OF ty_result_summary,
      txtp_result_session TYPE zbdc_result_bup-session_id,
      go_container_0601  TYPE REF TO cl_gui_custom_container,
      go_container_0602  TYPE REF TO cl_gui_custom_container,
      go_container_0603  TYPE REF TO cl_gui_custom_container,
      go_grid_0601       TYPE REF TO cl_salv_table,
      go_grid_0602       TYPE REF TO cl_salv_table,
      go_grid_0603       TYPE REF TO cl_salv_table,
      go_result_events   TYPE REF TO lcl_result_events.

* ------------------------------------------------------------
* Screen 0650/0651 - Result Detail Drilldown
* ------------------------------------------------------------
DATA: gt_log_0650       TYPE STANDARD TABLE OF zbdc_result_bup,
      go_container_0650 TYPE REF TO cl_gui_custom_container,
      go_grid_0650      TYPE REF TO cl_salv_table,
      txtp_sap_object_id TYPE char40,
      txtp_result_msg    TYPE char255.

* ------------------------------------------------------------
* Screen 0700 - Rule-based Error Analyst; Screen 0750 - Fix Guide Knowledge Base
* ------------------------------------------------------------
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
DATA: gt_patterns       TYPE STANDARD TABLE OF ty_ai_pattern,
      gt_ai_archive     TYPE STANDARD TABLE OF ty_ai_pattern,
      go_container_0700 TYPE REF TO cl_gui_custom_container,
      go_pattern_grid   TYPE REF TO cl_salv_table,
      txtp_ai_session   TYPE char30,
      txtp_ai_text      TYPE string,
      p_search          TYPE char80,
      go_container_0750 TYPE REF TO cl_gui_custom_container,
      go_grid_0750      TYPE REF TO cl_salv_table.

* ------------------------------------------------------------
* Screen 0800 - SHDB Recording Editor
* Uses current DDIC table ZBDC_SCT_DEF_BUP, not old ZBDC_SCRIPT_DEF.
* ------------------------------------------------------------
DATA: gt_script_def     TYPE STANDARD TABLE OF zbdc_sct_def_bup,
      go_rec_container  TYPE REF TO cl_gui_custom_container,
      go_rec_grid       TYPE REF TO cl_gui_alv_grid,
      p_rec_tcode       TYPE char20 VALUE 'ME21N'.

CLASS lcl_result_events DEFINITION.
  PUBLIC SECTION.
    METHODS on_result_double_click FOR EVENT double_click OF cl_salv_events_table
      IMPORTING row column.
ENDCLASS.

* ============================================================
* V5AG - Dashboard timer implementation kept with its declaration.
* The timer only posts a lightweight OK code; normal PAI/PBO performs the
* database refresh, so no dynpro control is updated from the event callback.
* ============================================================
CLASS lcl_exec_timer IMPLEMENTATION.
  METHOD on_finished.
    IF gv_timer_0500_on = abap_true.
      TRY.
          IF sy-dynnr = '0500'.
            cl_gui_cfw=>set_new_ok_code( new_code = 'ZLIVE50' ).
            IF go_timer_0500 IS BOUND.
              go_timer_0500->run( ).
            ENDIF.
          ELSE.
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

CLASS lcl_result_timer IMPLEMENTATION.
  METHOD on_finished.
    IF gv_timer_0600_on = abap_true.
      TRY.
          IF sy-dynnr = '0600' OR sy-dynnr = '0601' OR
             sy-dynnr = '0602' OR sy-dynnr = '0603'.
            cl_gui_cfw=>set_new_ok_code( new_code = 'AUTOREF' ).
            IF go_timer_0600 IS BOUND.
              go_timer_0600->run( ).
            ENDIF.
          ELSE.
            "Do not leave an active GUI timer behind after navigation.
            CLEAR gv_timer_0600_on.
            IF go_timer_0600 IS BOUND.
              go_timer_0600->cancel( ).
            ENDIF.
          ENDIF.
        CATCH cx_root.
          "Auto refresh must never interrupt user navigation.
          CLEAR gv_timer_0600_on.
      ENDTRY.
    ENDIF.
  ENDMETHOD.
ENDCLASS.

* ============================================================
* V5AF - Local SALV event implementation kept with declaration
* Prevents cross-include activation/order mismatch for ON_FILE_FUNCTION.
* ============================================================
CLASS lcl_alv_events IMPLEMENTATION.
  METHOD on_double_click.
    READ TABLE gt_sessions INTO DATA(ls_sess) INDEX row.
    IF sy-subrc = 0.
      SELECT * FROM zbdc_staging_bup INTO TABLE gt_staging
        WHERE session_id = ls_sess-session_id.
      IF gt_staging IS NOT INITIAL.
        CLEAR: gt_staging_alv, gt_exec_disp.
        gv_0400_view = gc_view_cockpit.
        CALL SCREEN 0400.
      ELSE.
        MESSAGE 'Session nay rong!' TYPE 'W'.
      ENDIF.
    ENDIF.
  ENDMETHOD.

  METHOD on_file_double_click.
    READ TABLE gt_files_preview INTO DATA(ls_file) INDEX row.
    IF sy-subrc = 0.
      CLEAR gt_staging.
      IF ls_file-session_id IS NOT INITIAL.
        gv_current_batch_prefix = ls_file-session_id.
        REFRESH gt_current_sessions.
        APPEND ls_file-session_id TO gt_current_sessions.
        SELECT * FROM zbdc_staging_bup INTO TABLE gt_staging
          WHERE session_id = ls_file-session_id
          ORDER BY row_index.
      ENDIF.

      DATA(lv_rows_file) = lines( gt_staging ).
      DATA(lv_display_file) = ls_file-file_name.
      DATA(lv_display_sheet) = ls_file-sheet_name.
      IF lv_display_file CS '|SHEET='.
        SPLIT lv_display_file AT '|SHEET='
          INTO lv_display_file lv_display_sheet.
      ENDIF.
      txtp_file_path = lv_display_file.
      txtp_file_size = ls_file-file_size.
      PERFORM z23_recalc_frontend_size USING lv_display_file CHANGING txtp_file_size.
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

      IF gt_staging IS INITIAL.
        MESSAGE |File/source log selected, but no staging rows found for session { ls_file-session_id }.| TYPE 'S' DISPLAY LIKE 'W'.
      ELSEIF ls_file-owner IS INITIAL
          OR ls_file-owner = sy-uname
          OR ls_file-owner = 'UNKNOWN'.
        MESSAGE |Loaded your upload { ls_file-file_title } to Preview Data ({ lv_rows_file } rows).| TYPE 'S'.
      ELSE.
        MESSAGE |Loaded shared upload by { ls_file-owner } in preview mode. Run/Resubmit/Retry will request an exclusive batch lock.| TYPE 'S'.
      ENDIF.
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

    PERFORM z16_prepare_preview_file.
    PERFORM z16_refresh_0302_scope.
  ENDMETHOD.
ENDCLASS.
