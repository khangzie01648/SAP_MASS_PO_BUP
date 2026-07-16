*&---------------------------------------------------------------------*
*& Report ZBDC_SFTP_INBOUND_JOB_BUP
*&---------------------------------------------------------------------*
*& Job tu dong (SM36 moi 1 phut):
*&  PHASE 1 PULL : curl key-auth keo .csv tu SFTP /incoming -> work-dir
*&  PHASE 2 INGEST: quet *.csv, dedup 2 tang, nap staging - GIU FILE
*&  KHONG xoa file -> Browse tay 0300 van thay. Dedup chong nap lai.
*&  FIX: ho tro ten file co dau cach (quote URL + parse listing ghep token)
*&---------------------------------------------------------------------*
REPORT zbdc_sftp_inbound_job_bup.

CONSTANTS:
  lc_path    TYPE eps2filnam VALUE '/usr/sap/S40/D00/work/',
  lc_keyfile TYPE string     VALUE '/usr/sap/S40/D00/work/sap_sftp_key',
  lc_listf   TYPE string     VALUE '/usr/sap/S40/D00/work/sftp_listing.txt',
  lc_user    TYPE string     VALUE 'sap_sftp',
  lc_remote  TYPE string     VALUE '/incoming/'.

DATA: gv_host  TYPE string,
      gv_port  TYPE string,
      gv_tcode TYPE zbdc_staging_bup-tcode.

DATA: gt_seen_key TYPE HASHED TABLE OF string
                  WITH UNIQUE KEY table_line.

DATA: gv_pulled  TYPE i,
      gv_files   TYPE i,
      gv_total   TYPE i,
      gv_skipped TYPE i.

*======================================================================*
START-OF-SELECTION.
  PERFORM load_config.
  IF gv_host IS INITIAL OR gv_port IS INITIAL.
    WRITE: / 'ERROR: chua co SFTP_HOST/SFTP_PORT trong zbdc_config_bup.'.
    RETURN.
  ENDIF.

  PERFORM preload_seen_keys.
  PERFORM pull_from_sftp.
  PERFORM ingest_local.

  WRITE: / '====================================='.
  WRITE: / |PULL : { gv_pulled } file keo ve tu SFTP.|.
  WRITE: / |INGEST: { gv_files } file nap, { gv_total } dong moi.|.
  WRITE: / |SKIP : { gv_skipped } file trung (dedup tang 1).|.

*======================================================================*
FORM load_config.
  DATA: lt_cfg TYPE STANDARD TABLE OF zbdc_config_bup,
        ls_cfg TYPE zbdc_config_bup.
  SELECT * FROM zbdc_config_bup INTO TABLE @lt_cfg.
  LOOP AT lt_cfg INTO ls_cfg.
    CASE ls_cfg-config_key.
      WHEN 'SFTP_HOST'.   gv_host  = ls_cfg-config_value.
      WHEN 'SFTP_PORT'.   gv_port  = ls_cfg-config_value.
      WHEN 'TRANSACTION'. gv_tcode = ls_cfg-config_value.
    ENDCASE.
  ENDLOOP.
  TRANSLATE gv_host TO LOWER CASE.
  CONDENSE: gv_host, gv_port.
  IF gv_tcode IS INITIAL. gv_tcode = 'ME21N'. ENDIF.
ENDFORM.

*======================================================================*
FORM preload_seen_keys.
  DATA: lt_key TYPE STANDARD TABLE OF zbdc_staging_bup-record_key,
        lv_key TYPE string.
  SELECT DISTINCT record_key FROM zbdc_staging_bup INTO TABLE @lt_key.
  LOOP AT lt_key INTO lv_key.
    IF lv_key IS NOT INITIAL.
      INSERT lv_key INTO TABLE gt_seen_key.
    ENDIF.
  ENDLOOP.
ENDFORM.

*======================================================================*
FORM run_curl USING iv_params TYPE string
              CHANGING ev_exit TYPE i.
  DATA: lv_par  TYPE sxpgcolist-parameters,
        lv_stat TYPE c LENGTH 1,
        lt_prot TYPE STANDARD TABLE OF btcxpm.
  lv_par = iv_params.
  ev_exit = 99.
  CALL FUNCTION 'SXPG_COMMAND_EXECUTE'
    EXPORTING
      commandname           = 'ZBDC_SFTP_PULL'
      additional_parameters = lv_par
      operatingsystem       = 'Linux'
    IMPORTING
      status                = lv_stat
      exitcode              = ev_exit
    TABLES
      exec_protocol         = lt_prot
    EXCEPTIONS
      OTHERS                = 15.
  IF sy-subrc <> 0.
    ev_exit = 98.
  ENDIF.
ENDFORM.

*======================================================================*
* PHASE 1 — curl list /incoming -> keo tung .csv ve (giu nguyen ten)
* FIX 1: quote URL + output path (chong loi ten file co space)
* FIX 2: parse listing ghep token 9+ (ten file co space bi split nhieu manh)
*======================================================================*
FORM pull_from_sftp.
  DATA: lv_params TYPE string,
        lv_exit   TYPE i,
        lt_list   TYPE STANDARD TABLE OF string,
        lv_line   TYPE string,
        lt_tok    TYPE STANDARD TABLE OF string,
        lv_fname  TYPE string,
        lv_local  TYPE string,
        lv_n      TYPE i,
        lv_ti     TYPE i,
        lv_tok    TYPE string,
        lv_fname_url   TYPE string,
        lv_fname_local TYPE string.

  " --- List thu muc SFTP ---
  lv_params = |--insecure -u { lc_user }: --key { lc_keyfile } | &&
              |sftp://{ gv_host }:{ gv_port }{ lc_remote } -o { lc_listf }|.
  PERFORM run_curl USING lv_params CHANGING lv_exit.
  IF lv_exit <> 0.
    WRITE: / |ERROR: khong lay duoc listing SFTP (curl exit { lv_exit }).|.
    RETURN.
  ENDIF.

  OPEN DATASET lc_listf FOR INPUT IN TEXT MODE ENCODING DEFAULT.
  IF sy-subrc <> 0.
    WRITE: / 'ERROR: khong mo duoc file listing.'.
    RETURN.
  ENDIF.
  DO.
    READ DATASET lc_listf INTO lv_line.
    IF sy-subrc <> 0. EXIT. ENDIF.
    APPEND lv_line TO lt_list.
  ENDDO.
  CLOSE DATASET lc_listf.

  LOOP AT lt_list INTO lv_line.
    CONDENSE lv_line.
    IF lv_line IS INITIAL. CONTINUE. ENDIF.

    REFRESH lt_tok.
    SPLIT lv_line AT space INTO TABLE lt_tok.
    DELETE lt_tok WHERE table_line IS INITIAL.
    DESCRIBE TABLE lt_tok LINES lv_n.
    IF lv_n < 9. CONTINUE. ENDIF.

    " SFTP listing: perm links owner group size mon day time FILENAME...
    " Ghep token 9+ thanh ten file day du (ho tro ten co space)
    CLEAR lv_fname.
    DO.
      lv_ti = 8 + sy-index.
      IF lv_ti > lv_n. EXIT. ENDIF.
      READ TABLE lt_tok INTO lv_tok INDEX lv_ti.
      IF lv_fname IS INITIAL.
        lv_fname = lv_tok.
      ELSE.
        lv_fname = lv_fname && | | && lv_tok.
      ENDIF.
    ENDDO.

    IF lv_fname NP '*.csv' AND lv_fname NP '*.CSV'. CONTINUE. ENDIF.

    " URL-encode: thay space bang %20 cho curl SFTP URL
    lv_fname_url = lv_fname.
    REPLACE ALL OCCURRENCES OF | | IN lv_fname_url WITH '%20'.

    " Sanitize ten file local: thay space bang _ de luu tren Linux
    lv_fname_local = lv_fname.
    REPLACE ALL OCCURRENCES OF | | IN lv_fname_local WITH '_'.

    CONCATENATE lc_path lv_fname_local INTO lv_local.

    lv_params = |--insecure -u { lc_user }: --key { lc_keyfile } | &&
                |sftp://{ gv_host }:{ gv_port }{ lc_remote }{ lv_fname_url } | &&
                |-o { lv_local }|.
    PERFORM run_curl USING lv_params CHANGING lv_exit.
    IF lv_exit = 0.
      gv_pulled = gv_pulled + 1.
      WRITE: / |  PULL OK: { lv_fname } -> { lv_fname_local }|.
    ELSE.
      WRITE: / |  PULL FAIL: { lv_fname } (exit { lv_exit })|.
    ENDIF.
  ENDLOOP.
ENDFORM.

*======================================================================*
* PHASE 2 — quet *.csv, dedup 2 tang, nap staging (GIU FILE)
*======================================================================*
FORM ingest_local.
  DATA: lt_dir  TYPE TABLE OF eps2fili,
        ls_dir  TYPE eps2fili,
        lv_dir  TYPE eps2filnam.

  lv_dir = lc_path.
  CALL FUNCTION 'EPS2_GET_DIRECTORY_LISTING'
    EXPORTING
      iv_dir_name            = lv_dir
    TABLES
      dir_list               = lt_dir
    EXCEPTIONS
      invalid_eps_subdir     = 1
      sapgparam_failed       = 2
      build_directory_failed = 3
      no_authorization       = 4
      read_directory_failed  = 5
      too_many_read_errors   = 6
      empty_directory_list   = 7
      OTHERS                 = 8.

  IF sy-subrc <> 0 OR lt_dir IS INITIAL.
    WRITE: / 'INFO: thu muc rong/loi doc. sy-subrc =', sy-subrc.
    RETURN.
  ENDIF.

  LOOP AT lt_dir INTO ls_dir.
    IF ls_dir-name NP '*.csv' AND ls_dir-name NP '*.CSV'. CONTINUE. ENDIF.
    PERFORM process_one_file USING ls_dir-name.
  ENDLOOP.
ENDFORM.

*======================================================================*
* Xu ly 1 file: binary read -> hash dedup (tang1) -> record_key (tang2)
*& GIU FILE: KHONG xoa. Lan sau dedup hash se SKIP.
*======================================================================*
FORM process_one_file USING iv_name TYPE eps2fili-name.
  DATA: lv_full    TYPE string,
        lv_line    TYPE string,
        lv_content TYPE string,
        lv_hashstr TYPE string,
        lv_hash    TYPE zbdc_file_lg_bup-file_hash,
        ls_log     TYPE zbdc_file_lg_bup,
        lt_stg     TYPE TABLE OF zbdc_staging_bup,
        ls_stg     TYPE zbdc_staging_bup,
        lt_col     TYPE TABLE OF string,
        lt_raw     TYPE STANDARD TABLE OF string,
        lv_sess    TYPE zbdc_staging_bup-session_id,
        lv_idx     TYPE i,
        lv_new     TYPE i,
        lv_dummy   TYPE zbdc_file_lg_bup-file_hash,
        lv_xstr    TYPE xstring,
        lv_xbuf    TYPE xstring,
        lv_xlen    TYPE i,
        lo_conv    TYPE REF TO cl_abap_conv_in_ce.

  CONCATENATE lc_path iv_name INTO lv_full.

  CLEAR: lv_content, lv_xstr.
  REFRESH lt_raw.
  OPEN DATASET lv_full FOR INPUT IN BINARY MODE.
  IF sy-subrc <> 0.
    WRITE: / 'ERROR: khong mo duoc', lv_full. RETURN.
  ENDIF.
  DO.
    CLEAR lv_xbuf.
    READ DATASET lv_full INTO lv_xbuf MAXIMUM LENGTH 8192 ACTUAL LENGTH lv_xlen.
    IF lv_xlen > 0.
      CONCATENATE lv_xstr lv_xbuf(lv_xlen) INTO lv_xstr IN BYTE MODE.
    ENDIF.
    IF sy-subrc <> 0. EXIT. ENDIF.
  ENDDO.
  CLOSE DATASET lv_full.

  IF lv_xstr IS INITIAL.
    RETURN.
  ENDIF.

  TRY.
      lo_conv = cl_abap_conv_in_ce=>create(
                  encoding = 'UTF-8' replacement = '#' input = lv_xstr ).
      lo_conv->read( IMPORTING data = lv_content ).
    CATCH cx_root.
      TRY.
          lo_conv = cl_abap_conv_in_ce=>create(
                      encoding = '1100' replacement = '#' input = lv_xstr ).
          lo_conv->read( IMPORTING data = lv_content ).
        CATCH cx_root.
          WRITE: / |  SKIP { iv_name }: khong doc duoc encoding.|.
          RETURN.
      ENDTRY.
  ENDTRY.

  IF lv_content IS INITIAL.
    RETURN.
  ENDIF.

  REPLACE ALL OCCURRENCES OF cl_abap_char_utilities=>cr_lf
          IN lv_content WITH cl_abap_char_utilities=>newline.
  SPLIT lv_content AT cl_abap_char_utilities=>newline INTO TABLE lt_raw.

  " --- DEDUP TANG 1: hash noi dung file (file da nap -> SKIP, GIU file) ---
  CALL FUNCTION 'CALCULATE_HASH_FOR_CHAR'
    EXPORTING
      alg           = 'SHA1'
      data          = lv_content
    IMPORTING
      hashb64string = lv_hashstr
    EXCEPTIONS
      OTHERS        = 1.
  lv_hash = lv_hashstr.

  SELECT SINGLE file_hash FROM zbdc_file_lg_bup
    INTO @lv_dummy WHERE file_hash = @lv_hash.
  IF sy-subrc = 0.
    gv_skipped = gv_skipped + 1.
    WRITE: / |  SKIP { iv_name }: trung hash (tang 1) - giu file.|.
    RETURN.
  ENDIF.

  " --- parse CSV + DEDUP TANG 2: record_key ---
  CONCATENATE 'SFTP_' sy-datum sy-uzeit INTO lv_sess.
  REFRESH lt_stg.
  lv_idx = 0. lv_new = 0.
  DATA(lv_first) = abap_true.

  LOOP AT lt_raw INTO lv_line.
    IF lv_line IS INITIAL. CONTINUE. ENDIF.

    IF lv_first = abap_true.
      lv_first = abap_false.
      IF lv_line CS 'PO_KEY' OR sy-tabix = 1. CONTINUE. ENDIF.
    ENDIF.

    CLEAR: ls_stg, lt_col.
    SPLIT lv_line AT ',' INTO TABLE lt_col.

    READ TABLE lt_col INTO ls_stg-field01 INDEX 1.
    READ TABLE lt_col INTO ls_stg-field02 INDEX 2.
    READ TABLE lt_col INTO ls_stg-field03 INDEX 3.
    READ TABLE lt_col INTO ls_stg-field04 INDEX 4.
    READ TABLE lt_col INTO ls_stg-field05 INDEX 5.
    READ TABLE lt_col INTO ls_stg-field06 INDEX 6.
    READ TABLE lt_col INTO ls_stg-field07 INDEX 7.
    READ TABLE lt_col INTO ls_stg-field08 INDEX 8.
    READ TABLE lt_col INTO ls_stg-field09 INDEX 9.
    READ TABLE lt_col INTO ls_stg-field10 INDEX 10.

    DATA(lv_k) = CONV string( ls_stg-field01 ).
    READ TABLE gt_seen_key TRANSPORTING NO FIELDS
         WITH KEY table_line = lv_k.
    IF sy-subrc = 0. CONTINUE. ENDIF.
    INSERT lv_k INTO TABLE gt_seen_key.

    lv_idx = lv_idx + 1.
    ls_stg-session_id = lv_sess.
    ls_stg-row_index  = lv_idx.
    ls_stg-record_key = ls_stg-field01.
    ls_stg-tcode      = gv_tcode.
    ls_stg-status     = 'STAGED'.
    ls_stg-field25    = iv_name.
    APPEND ls_stg TO lt_stg.
    lv_new = lv_new + 1.
  ENDLOOP.

  IF lt_stg IS NOT INITIAL.
    MODIFY zbdc_staging_bup FROM TABLE lt_stg.
    IF sy-subrc <> 0.
      ROLLBACK WORK.
      WRITE: / |  ERROR ghi staging: { iv_name }|. RETURN.
    ENDIF.
    COMMIT WORK.
  ENDIF.

  CLEAR ls_log.
  ls_log-file_hash    = lv_hash.
  ls_log-file_name    = iv_name.
  ls_log-source       = 'SFTP'.
  ls_log-row_count    = lv_new.
  ls_log-session_id   = lv_sess.
  ls_log-processed_at = sy-datum.
  INSERT zbdc_file_lg_bup FROM ls_log.
  COMMIT WORK.

  " --- KHONG xoa file -> Browse tay 0300 van thay ---
  gv_files = gv_files + 1.
  gv_total = gv_total + lv_new.
  WRITE: / |  OK { iv_name }: nap { lv_new } dong moi. (Giu file).|.
ENDFORM.
