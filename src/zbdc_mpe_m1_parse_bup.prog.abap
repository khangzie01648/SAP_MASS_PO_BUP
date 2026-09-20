
*& Include ZBDC_MPE_M1_PARSE_BUP
*& Purpose CSV/XLSX parsing, template contract and preview projection
*& reconcile exact pending certification state

FORM extract_file_title_parse USING iv_file TYPE csequence
                            CHANGING cv_title TYPE csequence.
  DATA: lv_file TYPE string,
        lv_dummy TYPE string,
        lt_part TYPE STANDARD TABLE OF string,
        lv_cnt  TYPE i.
  CLEAR cv_title.
  lv_file = iv_file.
  IF lv_file CP 'GmailForm://*' AND lv_file CS '?request='.
    SPLIT lv_file AT '?request=' INTO lv_dummy lv_file.
  ELSEIF lv_file CS '|SHEET='.
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

FORM p1_compose_unit_name USING iv_file  TYPE csequence
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

FORM p1_split_unit_name USING iv_name TYPE csequence
                         CHANGING cv_file_title TYPE csequence
                                  cv_sheet_name TYPE csequence.
  DATA: lv_file  TYPE string,
        lv_sheet TYPE string.
  CLEAR: cv_file_title, cv_sheet_name.
  lv_file = iv_name.
  IF lv_file CS '|SHEET='.
    SPLIT lv_file AT '|SHEET=' INTO lv_file lv_sheet.
  ENDIF.
  IF lv_sheet IS INITIAL.
    lv_sheet = 'DATA'.
  ENDIF.
  PERFORM extract_file_title_parse USING lv_file CHANGING cv_file_title.
  cv_sheet_name = lv_sheet.
ENDFORM.

FORM p1_is_skip_sheet USING iv_sheet TYPE csequence
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

*& Strict immutable template/version resolver
*& One generated template version is an immutable snapshot:
*& TCODE + PROFILE + PROFILE_VER + SCRIPT_ID + CONTRACT_HASH + MAPPING.
*& Upload NEVER creates a version and NEVER rebinds v17/v18 to v19.

FORM p1_resolve_declared_template
  USING    iv_header      TYPE string
  CHANGING cv_declared    TYPE abap_bool
           cv_ok          TYPE abap_bool
           cv_message     TYPE string.

  TYPES: BEGIN OF ty_pair,
           tcode        TYPE zbdc_prof_bup-tcode,
           profile_name TYPE zbdc_prof_bup-profile_name,
         END OF ty_pair.

  DATA: lt_pairs        TYPE STANDARD TABLE OF ty_pair,
        lt_prof         TYPE STANDARD TABLE OF zbdc_prof_bup,
        lt_map          TYPE STANDARD TABLE OF zbdc_mapping_bup,
        lt_headers      TYPE string_table,
        lt_header_order TYPE string_table,
        lt_norm_headers TYPE SORTED TABLE OF string WITH UNIQUE KEY table_line,
        ls_pair         TYPE ty_pair,
        ls_prof         TYPE zbdc_prof_bup,
        ls_cert         TYPE zbdc_cert_bup,
        ls_script       TYPE zbdc_script_bup,
        lv_file         TYPE string,
        lv_prefix       TYPE string,
        lv_suffix       TYPE string,
        lv_header       TYPE string,
        lv_ver_text     TYPE string,
        lv_char         TYPE c LENGTH 1,
        lv_pos          TYPE i,
        lv_start        TYPE i,
        lv_len          TYPE i,
        lv_match_count  TYPE i,
        lv_decl_tcode   TYPE zbdc_prof_bup-tcode,
        lv_decl_profile TYPE zbdc_prof_bup-profile_name,
        lv_decl_ver     TYPE zbdc_prof_bup-profile_ver,
        lv_script_stat  TYPE zbdc_script_bup-status,
        lv_cert_stat    TYPE zbdc_cert_bup-cert_status,
        lv_manifest_ok  TYPE abap_bool,
        lv_manifest_msg TYPE string,
        lv_z469_ts      TYPE timestampl.

  CLEAR: cv_declared, cv_ok, cv_message.

  lv_file = gv_current_file_name.
  IF lv_file IS INITIAL.
    lv_file = txtp_file_path.
  ENDIF.
  TRANSLATE lv_file TO UPPER CASE.

 "Only a system-generated filename claims an exact contract version.
  IF lv_file NS 'TEMPLATE_' OR lv_file NS '_V'.
    RETURN.
  ENDIF.
  cv_declared = abap_true.

  SELECT * FROM zbdc_prof_bup INTO TABLE @lt_prof.
  LOOP AT lt_prof INTO ls_prof.
    CLEAR ls_pair.
    ls_pair-tcode        = ls_prof-tcode.
    ls_pair-profile_name = ls_prof-profile_name.
    APPEND ls_pair TO lt_pairs.
  ENDLOOP.
  SORT lt_pairs BY tcode profile_name.
  DELETE ADJACENT DUPLICATES FROM lt_pairs COMPARING tcode profile_name.

  LOOP AT lt_pairs INTO ls_pair.
    lv_prefix = |TEMPLATE_{ ls_pair-tcode }_{ ls_pair-profile_name }_V|.
    TRANSLATE lv_prefix USING ' _'.
    TRANSLATE lv_prefix TO UPPER CASE.

    FIND FIRST OCCURRENCE OF lv_prefix IN lv_file MATCH OFFSET lv_pos.
    IF sy-subrc <> 0.
      CONTINUE.
    ENDIF.

    lv_start = lv_pos + strlen( lv_prefix ).
    IF lv_start >= strlen( lv_file ).
      CONTINUE.
    ENDIF.
    lv_suffix = lv_file+lv_start.

    CLEAR lv_ver_text.
    lv_len = strlen( lv_suffix ).
    lv_pos = 0.
    WHILE lv_pos < lv_len.
      lv_char = lv_suffix+lv_pos(1).
      IF lv_char CO '0123456789'.
        lv_ver_text = lv_ver_text && lv_char.
        lv_pos = lv_pos + 1.
      ELSE.
        EXIT.
      ENDIF.
    ENDWHILE.
    IF lv_ver_text IS INITIAL.
      CONTINUE.
    ENDIF.

    lv_match_count  = lv_match_count + 1.
    lv_decl_tcode   = ls_pair-tcode.
    lv_decl_profile = ls_pair-profile_name.
    lv_decl_ver     = lv_ver_text.
  ENDLOOP.

  IF lv_match_count <> 1 OR lv_decl_ver IS INITIAL.
    cv_message = 'TEMPLATE_VERSION_INVALID: generated template identity is unknown or ambiguous; upload is blocked.'.
    RETURN.
  ENDIF.

 "Registry identity is exact. A claimed version is valid only when that
 "immutable snapshot exists; no MAX/latest comparison participates in routing.
  CLEAR ls_prof.
  SELECT SINGLE * FROM zbdc_prof_bup
    INTO @ls_prof
    WHERE tcode        = @lv_decl_tcode
      AND profile_name = @lv_decl_profile
      AND profile_ver  = @lv_decl_ver.
  IF sy-subrc <> 0.
    cv_message = |VERSION_NOT_FOUND: exact version v{ lv_decl_ver } does not exist for { lv_decl_tcode }/{ lv_decl_profile }.|.
    RETURN.
  ENDIF.

  CASE ls_prof-status.
    WHEN 'ACTIVE'.
      lv_script_stat = 'ACTIVE'.
      lv_cert_stat   = 'CERTIFIED'.
    WHEN 'TESTING'.
      lv_script_stat = 'TEST_READY'.
      lv_cert_stat   = 'PENDING_TEST'.
    WHEN 'MAPPED' OR 'DRAFT'.
 "A generated template from onboarding may be uploaded for
 "Preview Data/Staging before the runtime proof contract is complete.
 "Execution remains gated elsewhere; do not reject harmless preview.
      CLEAR: lv_script_stat, lv_cert_stat.
    WHEN OTHERS.
      cv_message = |VERSION_NOT_RUNNABLE: exact version v{ lv_decl_ver } has status { ls_prof-status }.|.
      RETURN.
  ENDCASE.

 "Validate the upload against the exact ordered header frozen when Generate
 "Template emitted this immutable version. For pre-manifest templates, a
 "one-time migration replays the same generic BUILD_XLSX_CONTRACT generator
 "for the exact TCODE/Profile/Version and requires exact ordered-header
 "equality before freezing a manifest. No TCODE branch or business-field list
 "is introduced.
  SELECT * FROM zbdc_mapping_bup
    INTO TABLE @lt_map
    WHERE tcode        = @lv_decl_tcode
      AND profile_name = @lv_decl_profile
      AND profile_ver  = @lv_decl_ver.
  IF lt_map IS INITIAL.
    cv_message = |EXACT_MAPPING_MISSING: v{ lv_decl_ver } has no mapping snapshot.|.
    RETURN.
  ENDIF.

  PERFORM split_csv_line USING iv_header CHANGING lt_headers.
  LOOP AT lt_headers INTO lv_header.
    TRANSLATE lv_header TO UPPER CASE.
    CONDENSE lv_header NO-GAPS.
    REPLACE ALL OCCURRENCES OF '*' IN lv_header WITH ''.
    REPLACE ALL OCCURRENCES OF '"' IN lv_header WITH ''.
    IF lv_header IS INITIAL.
      CONTINUE.
    ENDIF.
    INSERT lv_header INTO TABLE lt_norm_headers.
    IF sy-subrc <> 0.
      cv_message = |TEMPLATE_SCHEMA_MISMATCH: duplicate column { lv_header } in uploaded header.|.
      RETURN.
    ENDIF.
    APPEND lv_header TO lt_header_order.
  ENDLOOP.

  IF lt_header_order IS INITIAL.
    cv_message = 'TEMPLATE_SCHEMA_MISMATCH: uploaded header is empty.'.
    RETURN.
  ENDIF.

  CLEAR: lv_manifest_ok, lv_manifest_msg.
  PERFORM validate_tmpl_header_manifest
    USING    lv_decl_tcode lv_decl_profile lv_decl_ver lt_header_order
    CHANGING lv_manifest_ok lv_manifest_msg.
  IF lv_manifest_ok <> abap_true.
    cv_message = lv_manifest_msg.
    IF cv_message IS INITIAL.
      cv_message = |TEMPLATE_SCHEMA_MISMATCH: uploaded header is not the frozen generated schema for v{ lv_decl_ver }.|.
    ENDIF.
    RETURN.
  ENDIF.

  IF ls_prof-status = 'MAPPED' OR ls_prof-status = 'DRAFT'.
    p_transaction             = lv_decl_tcode.
    txtp_profile_name         = lv_decl_profile.
    gv_profile_ver            = lv_decl_ver.
    CLEAR: gv_runtime_script_id,
           gv_runtime_contract_hash,
           gs_runtime_cert,
           gv_runtime_cert_loaded.
    cv_ok = abap_true.
    cv_message = |EXACT_TEMPLATE_PREVIEW_OK: { lv_decl_tcode }/{ lv_decl_profile } v{ lv_decl_ver } is bound for Preview Data; execution remains gated.|.
    RETURN.
  ENDIF.

 "Certification is the immutable manifest that ties v17 to the script/hash
 "created for v17 (and similarly for every other version). Never use latest.
 "manifest existence and certification lifecycle are separate facts.
 "An interrupted/partial certification must never make an existing exact
 "Script/Hash manifest look missing. The only automatic repair allowed here
 "is fail-closed: ACTIVE + PENDING_TEST is downgraded to TESTING after the
 "same exact contract is proven to own a TEST_READY script. Nothing is ever
 "promoted to CERTIFIED by upload/parse.
  CLEAR ls_cert.
  SELECT SINGLE * FROM zbdc_cert_bup
    INTO @ls_cert
    WHERE tcode        = @lv_decl_tcode
      AND profile_name = @lv_decl_profile
      AND profile_ver  = @lv_decl_ver
      AND cert_status  = @lv_cert_stat.

  IF sy-subrc <> 0 AND ls_prof-status = 'ACTIVE'.
    CLEAR ls_cert.
    SELECT SINGLE * FROM zbdc_cert_bup
      INTO @ls_cert
      WHERE tcode        = @lv_decl_tcode
        AND profile_name = @lv_decl_profile
        AND profile_ver  = @lv_decl_ver
        AND cert_status  = 'PENDING_TEST'.

    IF sy-subrc = 0 AND
       ls_cert-script_id IS NOT INITIAL AND
       ls_cert-contract_hash IS NOT INITIAL.
 "PENDING_TEST is authoritative that the exact contract has not
 "completed runtime proof. If a prior interrupted promotion left the
 "same exact Script snapshot ACTIVE, demote only that exact snapshot back
 "to TEST_READY, then restore the Profile to TESTING. This is fail-closed:
 "upload never promotes anything to ACTIVE/CERTIFIED.
      CLEAR ls_script.
      SELECT SINGLE * FROM zbdc_script_bup
        INTO @ls_script
        WHERE script_id     = @ls_cert-script_id
          AND tcode         = @lv_decl_tcode
          AND profile_name  = @lv_decl_profile
          AND profile_ver   = @lv_decl_ver
          AND contract_hash = @ls_cert-contract_hash.
      IF sy-subrc <> 0.
        cv_message = |CERT_STATE_MISMATCH: v{ lv_decl_ver } has PENDING_TEST manifest but its exact Script snapshot is missing.|.
        RETURN.
      ENDIF.

      CASE ls_script-status.
        WHEN 'TEST_READY'.
 "Already fail-closed; only the Profile state needs repair.
        WHEN 'ACTIVE'.
          GET TIME STAMP FIELD lv_z469_ts.
          UPDATE zbdc_script_bup
            SET status     = 'TEST_READY',
                changed_by = @sy-uname,
                changed_at = @lv_z469_ts
            WHERE script_id     = @ls_cert-script_id
              AND tcode         = @lv_decl_tcode
              AND profile_name  = @lv_decl_profile
              AND profile_ver   = @lv_decl_ver
              AND contract_hash = @ls_cert-contract_hash
              AND status        = 'ACTIVE'.
          IF sy-subrc <> 0.
            ROLLBACK WORK.
            cv_message = |CERT_STATE_REPAIR_FAILED: exact Script for v{ lv_decl_ver } could not be restored to TEST_READY.|.
            RETURN.
          ENDIF.
        WHEN OTHERS.
          cv_message = |CERT_STATE_MISMATCH: v{ lv_decl_ver } has PENDING_TEST manifest but exact Script status { ls_script-status } is not repairable.|.
          RETURN.
      ENDCASE.

      PERFORM get_demo_now CHANGING gv_demo_date_837 gv_demo_time_837.
  UPDATE zbdc_prof_bup
        SET status     = 'TESTING',
            changed_by = @sy-uname,
            changed_on = @gv_demo_date_837,
            changed_at = @gv_demo_time_837
        WHERE tcode        = @lv_decl_tcode
          AND profile_name = @lv_decl_profile
          AND profile_ver  = @lv_decl_ver
          AND status       = 'ACTIVE'.
      IF sy-subrc <> 0.
        ROLLBACK WORK.
        cv_message = |CERT_STATE_REPAIR_FAILED: v{ lv_decl_ver } could not be restored from ACTIVE to TESTING.|.
        RETURN.
      ENDIF.
      COMMIT WORK AND WAIT.

      ls_prof-status = 'TESTING'.
      lv_script_stat = 'TEST_READY'.
      lv_cert_stat   = 'PENDING_TEST'.
    ENDIF.
  ENDIF.

 "could already have repaired the exact S1 Script/Hash in a
 "prior session, while the older repair deleted its PENDING_TEST manifest.
 "Restore only that fail-closed pointer from one exact current-S1 TEST_READY
 "contract; never certify success and never pick latest/arbitrary history.
  IF ( ls_cert-script_id IS INITIAL OR ls_cert-contract_hash IS INITIAL )
     AND ls_prof-status = 'TESTING'.
    DATA: lv_z512_ok  TYPE abap_bool,
          lv_z512_msg TYPE string.
    CLEAR: lv_z512_ok, lv_z512_msg.
    PERFORM restore_pending_manifest
      USING    lv_decl_tcode lv_decl_profile lv_decl_ver
      CHANGING lv_z512_ok lv_z512_msg.
    IF lv_z512_ok = abap_true.
      CLEAR ls_cert.
      SELECT SINGLE * FROM zbdc_cert_bup
        INTO @ls_cert
        WHERE tcode        = @lv_decl_tcode
          AND profile_name = @lv_decl_profile
          AND profile_ver  = @lv_decl_ver
          AND cert_status  = 'PENDING_TEST'.
    ELSE.
      cv_message = lv_z512_msg.
      IF cv_message IS INITIAL.
        cv_message = |EXACT_MANIFEST_MISSING: v{ lv_decl_ver } has no exact Script/Hash certification manifest.|.
      ENDIF.
      RETURN.
    ENDIF.
  ENDIF.

  IF ls_cert-script_id IS INITIAL OR
     ls_cert-contract_hash IS INITIAL.
    cv_message = |EXACT_MANIFEST_MISSING: v{ lv_decl_ver } has no exact Script/Hash certification manifest.|.
    RETURN.
  ENDIF.

  IF ls_cert-cert_status <> lv_cert_stat.
    cv_message = |CERT_STATE_MISMATCH: profile v{ lv_decl_ver } expects { lv_cert_stat }, but its exact manifest is { ls_cert-cert_status }.|.
    RETURN.
  ENDIF.

  IF lv_cert_stat = 'CERTIFIED' AND ls_cert-last_test_status <> 'CERTIFIED'.
    cv_message = |VERSION_NOT_CERTIFIED: v{ lv_decl_ver } has no certified runtime proof.|.
    RETURN.
  ENDIF.

  CLEAR ls_script.
  SELECT SINGLE * FROM zbdc_script_bup
    INTO @ls_script
    WHERE script_id     = @ls_cert-script_id
      AND tcode         = @lv_decl_tcode
      AND profile_name  = @lv_decl_profile
      AND profile_ver   = @lv_decl_ver
      AND contract_hash = @ls_cert-contract_hash
      AND status        = @lv_script_stat.
  IF sy-subrc <> 0.
    cv_message = |EXACT_SCRIPT_MISMATCH: v{ lv_decl_ver } does not match its own imported/versioned Script snapshot.|.
    RETURN.
  ENDIF.

  p_transaction             = lv_decl_tcode.
  txtp_profile_name         = lv_decl_profile.
  gv_profile_ver            = lv_decl_ver.
  gv_runtime_script_id      = ls_cert-script_id.
  gv_runtime_contract_hash  = ls_cert-contract_hash.
  gs_runtime_cert           = ls_cert.
  gv_runtime_cert_loaded    = abap_true.

  cv_ok = abap_true.
  cv_message = |EXACT_TEMPLATE_OK: { lv_decl_tcode }/{ lv_decl_profile } v{ lv_decl_ver } is bound to its own immutable Script/Mapping snapshot.|.
ENDFORM.

*& Metadata/exact-version upload guard for every upload unit
*& Runtime upload must never create or reinterpret a profile version.
*& Metadata is authoritative when present; filename exact-template logic
*& remains as legacy fallback. No TCODE/field branch is introduced here.

FORM p1_meta_get_value
  USING    iv_meta  TYPE string
           iv_key   TYPE string
  CHANGING cv_value TYPE string.

  DATA: lt_parts TYPE STANDARD TABLE OF string,
        lv_part  TYPE string,
        lv_key   TYPE string,
        lv_val   TYPE string,
        lv_cmp   TYPE string,
        lv_find  TYPE string.

  CLEAR cv_value.
  lv_find = iv_key.
  TRANSLATE lv_find TO UPPER CASE.

  SPLIT iv_meta AT ';' INTO TABLE lt_parts.
  LOOP AT lt_parts INTO lv_part.
    REPLACE ALL OCCURRENCES OF '#' IN lv_part WITH ''.
    REPLACE ALL OCCURRENCES OF '__BDC_META' IN lv_part WITH ''.
    REPLACE ALL OCCURRENCES OF 'BDC_META' IN lv_part WITH ''.
    CONDENSE lv_part.
    IF lv_part NS '='.
      CONTINUE.
    ENDIF.

    SPLIT lv_part AT '=' INTO lv_key lv_val.
    CONDENSE lv_key NO-GAPS.
    CONDENSE lv_val.
    lv_cmp = lv_key.
    TRANSLATE lv_cmp TO UPPER CASE.

    IF lv_cmp = lv_find.
      cv_value = lv_val.
      RETURN.
    ENDIF.
  ENDLOOP.
ENDFORM.

FORM p1_parse_meta_raw
  USING    pt_raw     TYPE string_table
  CHANGING cv_found   TYPE abap_bool
           cv_tcode   TYPE zbdc_prof_bup-tcode
           cv_profile TYPE zbdc_prof_bup-profile_name
           cv_ver     TYPE zbdc_prof_bup-profile_ver
           cv_script  TYPE zbdc_script_bup-script_id
           cv_hash    TYPE zbdc_script_bup-contract_hash.

  DATA: lv_line  TYPE string,
        lv_upper TYPE string,
        lv_val   TYPE string,
        lv_vtxt  TYPE string,
        lv_char  TYPE c LENGTH 1,
        lv_idx   TYPE i,
        lv_len   TYPE i.

  CLEAR: cv_found, cv_tcode, cv_profile, cv_ver, cv_script, cv_hash.

  LOOP AT pt_raw INTO lv_line.
    IF lv_line IS INITIAL.
      CONTINUE.
    ENDIF.

    lv_upper = lv_line.
    TRANSLATE lv_upper TO UPPER CASE.

 "Only look at optional metadata before the first business header.
    IF lv_line NP '#*' AND lv_upper NS 'BDC_META'.
      EXIT.
    ENDIF.

    IF lv_upper NS 'TCODE=' AND lv_upper NS 'PROFILE=' AND lv_upper NS 'VERSION='.
      CONTINUE.
    ENDIF.

    PERFORM p1_meta_get_value USING lv_line 'TCODE' CHANGING lv_val.
    IF lv_val IS NOT INITIAL.
      cv_tcode = lv_val.
      TRANSLATE cv_tcode TO UPPER CASE.
    ENDIF.

    CLEAR lv_val.
    PERFORM p1_meta_get_value USING lv_line 'PROFILE' CHANGING lv_val.
    IF lv_val IS INITIAL.
      PERFORM p1_meta_get_value USING lv_line 'PROFILE_NAME' CHANGING lv_val.
    ENDIF.
    IF lv_val IS NOT INITIAL.
      cv_profile = lv_val.
      TRANSLATE cv_profile TO UPPER CASE.
    ENDIF.

    CLEAR lv_val.
    PERFORM p1_meta_get_value USING lv_line 'VERSION' CHANGING lv_val.
    IF lv_val IS INITIAL.
      PERFORM p1_meta_get_value USING lv_line 'PROFILE_VER' CHANGING lv_val.
    ENDIF.
    IF lv_val IS NOT INITIAL.
      lv_vtxt = lv_val.
      TRANSLATE lv_vtxt TO UPPER CASE.
      REPLACE ALL OCCURRENCES OF 'V' IN lv_vtxt WITH ''.
      CONDENSE lv_vtxt NO-GAPS.
      CLEAR cv_ver.
      lv_len = strlen( lv_vtxt ).
      lv_idx = 0.
      WHILE lv_idx < lv_len.
        lv_char = lv_vtxt+lv_idx(1).
        IF lv_char CO '0123456789'.
          cv_ver = cv_ver && lv_char.
        ENDIF.
        lv_idx = lv_idx + 1.
      ENDWHILE.
    ENDIF.

    CLEAR lv_val.
    PERFORM p1_meta_get_value USING lv_line 'SCRIPT_ID' CHANGING lv_val.
    IF lv_val IS NOT INITIAL.
      cv_script = lv_val.
    ENDIF.

    CLEAR lv_val.
    PERFORM p1_meta_get_value USING lv_line 'CONTRACT_HASH' CHANGING lv_val.
    IF lv_val IS NOT INITIAL.
      cv_hash = lv_val.
    ENDIF.

    IF cv_tcode IS NOT INITIAL AND
       cv_profile IS NOT INITIAL AND
       cv_ver IS NOT INITIAL.
      cv_found = abap_true.
      RETURN.
    ENDIF.
  ENDLOOP.
ENDFORM.

FORM p1_guard_contract
  USING    iv_tcode   TYPE zbdc_prof_bup-tcode
           iv_profile TYPE zbdc_prof_bup-profile_name
           iv_ver     TYPE zbdc_prof_bup-profile_ver
           iv_script  TYPE zbdc_script_bup-script_id
           iv_hash    TYPE zbdc_script_bup-contract_hash
           iv_header  TYPE string
  CHANGING cv_ok      TYPE abap_bool
           cv_message TYPE string.

  DATA: ls_prof        TYPE zbdc_prof_bup,
        ls_cert        TYPE zbdc_cert_bup,
        ls_script      TYPE zbdc_script_bup,
        lt_map         TYPE STANDARD TABLE OF zbdc_mapping_bup,
        lt_headers     TYPE string_table,
        lt_header_order TYPE string_table,
        lt_norm_hdr    TYPE SORTED TABLE OF string WITH UNIQUE KEY table_line,
        lv_script_stat TYPE zbdc_script_bup-status,
        lv_cert_stat   TYPE zbdc_cert_bup-cert_status,
        lv_z469_ts     TYPE timestampl,
        lv_header      TYPE string,
        lv_manifest_ok TYPE abap_bool,
        lv_manifest_msg TYPE string.

  CLEAR: cv_ok, cv_message.

  IF iv_tcode IS INITIAL OR iv_profile IS INITIAL OR iv_ver IS INITIAL.
    cv_message = 'DECLARED_CONTRACT_INCOMPLETE: TCODE/PROFILE/VERSION metadata is required.'.
    RETURN.
  ENDIF.

 "Validate only the exact immutable registry tuple; never route through
 "a highest/latest version comparison.
  CLEAR ls_prof.
  SELECT SINGLE * FROM zbdc_prof_bup
    INTO @ls_prof
    WHERE tcode        = @iv_tcode
      AND profile_name = @iv_profile
      AND profile_ver  = @iv_ver.
  IF sy-subrc <> 0.
    cv_message = |VERSION_NOT_FOUND: exact version v{ iv_ver } does not exist for { iv_tcode }/{ iv_profile }.|.
    RETURN.
  ENDIF.

  CASE ls_prof-status.
    WHEN 'ACTIVE'.
      lv_script_stat = 'ACTIVE'.
      lv_cert_stat   = 'CERTIFIED'.
    WHEN 'TESTING'.
      lv_script_stat = 'TEST_READY'.
      lv_cert_stat   = 'PENDING_TEST'.
    WHEN 'MAPPED' OR 'DRAFT'.
 "Metadata-bound generated templates may be previewed before
 "runtime proof certification. CT/BISM execution remains gated.
      CLEAR: lv_script_stat, lv_cert_stat.
    WHEN OTHERS.
      cv_message = |VERSION_NOT_RUNNABLE: exact version v{ iv_ver } has status { ls_prof-status }.|.
      RETURN.
  ENDCASE.

  SELECT * FROM zbdc_mapping_bup
    INTO TABLE @lt_map
    WHERE tcode        = @iv_tcode
      AND profile_name = @iv_profile
      AND profile_ver  = @iv_ver.
  IF lt_map IS INITIAL.
    cv_message = |EXACT_MAPPING_MISSING: v{ iv_ver } has no mapping snapshot.|.
    RETURN.
  ENDIF.

 "Metadata-bound uploads consume the same frozen ordered Template manifest as
 "filename-bound generated files. Legacy versions without a manifest are
 "migrated only by replaying the same exact versioned template generator.
  PERFORM split_csv_line USING iv_header CHANGING lt_headers.
  LOOP AT lt_headers INTO lv_header.
    TRANSLATE lv_header TO UPPER CASE.
    CONDENSE lv_header NO-GAPS.
    REPLACE ALL OCCURRENCES OF '*' IN lv_header WITH ''.
    REPLACE ALL OCCURRENCES OF '"' IN lv_header WITH ''.
    IF lv_header IS INITIAL.
      CONTINUE.
    ENDIF.
    INSERT lv_header INTO TABLE lt_norm_hdr.
    IF sy-subrc <> 0.
      cv_message = |TEMPLATE_SCHEMA_MISMATCH: duplicate column { lv_header } in uploaded header.|.
      RETURN.
    ENDIF.
    APPEND lv_header TO lt_header_order.
  ENDLOOP.

  IF lt_header_order IS INITIAL.
    cv_message = 'TEMPLATE_SCHEMA_MISMATCH: uploaded header is empty.'.
    RETURN.
  ENDIF.

  CLEAR: lv_manifest_ok, lv_manifest_msg.
  PERFORM validate_tmpl_header_manifest
    USING    iv_tcode iv_profile iv_ver lt_header_order
    CHANGING lv_manifest_ok lv_manifest_msg.
  IF lv_manifest_ok <> abap_true.
    cv_message = lv_manifest_msg.
    IF cv_message IS INITIAL.
      cv_message = |TEMPLATE_SCHEMA_MISMATCH: uploaded header is not the frozen generated schema for v{ iv_ver }.|.
    ENDIF.
    RETURN.
  ENDIF.

  IF ls_prof-status = 'MAPPED' OR ls_prof-status = 'DRAFT'.
    p_transaction            = iv_tcode.
    txtp_profile_name        = iv_profile.
    gv_profile_ver           = iv_ver.
    CLEAR: gv_runtime_script_id,
           gv_runtime_contract_hash,
           gs_runtime_cert,
           gv_runtime_cert_loaded.
    cv_ok = abap_true.
    cv_message = |EXACT_CONTRACT_PREVIEW_OK: { iv_tcode }/{ iv_profile } v{ iv_ver } is schema-checked for Preview Data; execution remains gated.|.
    RETURN.
  ENDIF.

 "metadata-bound uploads use the same fail-closed state repair as
 "filename-bound generated templates. Do not confuse a lifecycle mismatch
 "with a missing manifest and never promote certification from upload.
  CLEAR ls_cert.
  SELECT SINGLE * FROM zbdc_cert_bup
    INTO @ls_cert
    WHERE tcode        = @iv_tcode
      AND profile_name = @iv_profile
      AND profile_ver  = @iv_ver
      AND cert_status  = @lv_cert_stat.

  IF sy-subrc <> 0 AND ls_prof-status = 'ACTIVE'.
    CLEAR ls_cert.
    SELECT SINGLE * FROM zbdc_cert_bup
      INTO @ls_cert
      WHERE tcode        = @iv_tcode
        AND profile_name = @iv_profile
        AND profile_ver  = @iv_ver
        AND cert_status  = 'PENDING_TEST'.

    IF sy-subrc = 0 AND
       ls_cert-script_id IS NOT INITIAL AND
       ls_cert-contract_hash IS NOT INITIAL.
 "same exact-state repair for metadata-bound generated templates.
      CLEAR ls_script.
      SELECT SINGLE * FROM zbdc_script_bup
        INTO @ls_script
        WHERE script_id     = @ls_cert-script_id
          AND tcode         = @iv_tcode
          AND profile_name  = @iv_profile
          AND profile_ver   = @iv_ver
          AND contract_hash = @ls_cert-contract_hash.
      IF sy-subrc <> 0.
        cv_message = |CERT_STATE_MISMATCH: v{ iv_ver } has PENDING_TEST manifest but its exact Script snapshot is missing.|.
        RETURN.
      ENDIF.

      CASE ls_script-status.
        WHEN 'TEST_READY'.
 "Already fail-closed; only the Profile state needs repair.
        WHEN 'ACTIVE'.
          GET TIME STAMP FIELD lv_z469_ts.
          UPDATE zbdc_script_bup
            SET status     = 'TEST_READY',
                changed_by = @sy-uname,
                changed_at = @lv_z469_ts
            WHERE script_id     = @ls_cert-script_id
              AND tcode         = @iv_tcode
              AND profile_name  = @iv_profile
              AND profile_ver   = @iv_ver
              AND contract_hash = @ls_cert-contract_hash
              AND status        = 'ACTIVE'.
          IF sy-subrc <> 0.
            ROLLBACK WORK.
            cv_message = |CERT_STATE_REPAIR_FAILED: exact Script for v{ iv_ver } could not be restored to TEST_READY.|.
            RETURN.
          ENDIF.
        WHEN OTHERS.
          cv_message = |CERT_STATE_MISMATCH: v{ iv_ver } has PENDING_TEST manifest but exact Script status { ls_script-status } is not repairable.|.
          RETURN.
      ENDCASE.

      PERFORM get_demo_now CHANGING gv_demo_date_837 gv_demo_time_837.
  UPDATE zbdc_prof_bup
        SET status     = 'TESTING',
            changed_by = @sy-uname,
            changed_on = @gv_demo_date_837,
            changed_at = @gv_demo_time_837
        WHERE tcode        = @iv_tcode
          AND profile_name = @iv_profile
          AND profile_ver  = @iv_ver
          AND status       = 'ACTIVE'.
      IF sy-subrc <> 0.
        ROLLBACK WORK.
        cv_message = |CERT_STATE_REPAIR_FAILED: v{ iv_ver } could not be restored from ACTIVE to TESTING.|.
        RETURN.
      ENDIF.
      COMMIT WORK AND WAIT.

      ls_prof-status = 'TESTING'.
      lv_script_stat = 'TEST_READY'.
      lv_cert_stat   = 'PENDING_TEST'.
    ENDIF.
  ENDIF.

 "metadata-bound uploads use the same exact fail-closed repair.
  IF ( ls_cert-script_id IS INITIAL OR ls_cert-contract_hash IS INITIAL )
     AND ls_prof-status = 'TESTING'.
    DATA: lv_z512_ok  TYPE abap_bool,
          lv_z512_msg TYPE string.
    CLEAR: lv_z512_ok, lv_z512_msg.
    PERFORM restore_pending_manifest
      USING    iv_tcode iv_profile iv_ver
      CHANGING lv_z512_ok lv_z512_msg.
    IF lv_z512_ok = abap_true.
      CLEAR ls_cert.
      SELECT SINGLE * FROM zbdc_cert_bup
        INTO @ls_cert
        WHERE tcode        = @iv_tcode
          AND profile_name = @iv_profile
          AND profile_ver  = @iv_ver
          AND cert_status  = 'PENDING_TEST'.
    ELSE.
      cv_message = lv_z512_msg.
      IF cv_message IS INITIAL.
        cv_message = |EXACT_MANIFEST_MISSING: v{ iv_ver } has no exact Script/Hash certification manifest.|.
      ENDIF.
      RETURN.
    ENDIF.
  ENDIF.

  IF ls_cert-script_id IS INITIAL OR
     ls_cert-contract_hash IS INITIAL.
    cv_message = |EXACT_MANIFEST_MISSING: v{ iv_ver } has no exact Script/Hash certification manifest.|.
    RETURN.
  ENDIF.

  IF ls_cert-cert_status <> lv_cert_stat.
    cv_message = |CERT_STATE_MISMATCH: profile v{ iv_ver } expects { lv_cert_stat }, but its exact manifest is { ls_cert-cert_status }.|.
    RETURN.
  ENDIF.

  IF iv_script IS NOT INITIAL AND iv_script <> ls_cert-script_id.
    cv_message = |SCRIPT_ID_MISMATCH: file declares Script { iv_script } but v{ iv_ver } owns Script { ls_cert-script_id }.|.
    RETURN.
  ENDIF.

  IF iv_hash IS NOT INITIAL AND iv_hash <> ls_cert-contract_hash.
    cv_message = |CONTRACT_HASH_MISMATCH: uploaded file hash does not match exact version v{ iv_ver }.|.
    RETURN.
  ENDIF.

  IF lv_cert_stat = 'CERTIFIED' AND ls_cert-last_test_status <> 'CERTIFIED'.
    cv_message = |VERSION_NOT_CERTIFIED: v{ iv_ver } has no certified runtime proof.|.
    RETURN.
  ENDIF.

  CLEAR ls_script.
  SELECT SINGLE * FROM zbdc_script_bup
    INTO @ls_script
    WHERE script_id     = @ls_cert-script_id
      AND tcode         = @iv_tcode
      AND profile_name  = @iv_profile
      AND profile_ver   = @iv_ver
      AND contract_hash = @ls_cert-contract_hash
      AND status        = @lv_script_stat.
  IF sy-subrc <> 0.
    cv_message = |EXACT_SCRIPT_MISMATCH: v{ iv_ver } does not match its own imported/versioned Script snapshot.|.
    RETURN.
  ENDIF.

  p_transaction            = iv_tcode.
  txtp_profile_name        = iv_profile.
  gv_profile_ver           = iv_ver.
  gv_runtime_script_id     = ls_cert-script_id.
  gv_runtime_contract_hash = ls_cert-contract_hash.
  gs_runtime_cert          = ls_cert.
  gv_runtime_cert_loaded   = abap_true.

  cv_ok = abap_true.
  cv_message = |EXACT_CONTRACT_OK: { iv_tcode }/{ iv_profile } v{ iv_ver } is immutable and schema/hash checked.|.
ENDFORM.

FORM p1_resolve_unit_tcode USING iv_header TYPE string
                            CHANGING cv_tcode TYPE char20.
  TYPES: BEGIN OF ty_candidate,
           tcode        TYPE zbdc_prof_bup-tcode,
           profile_name TYPE zbdc_prof_bup-profile_name,
           profile_ver  TYPE zbdc_prof_bup-profile_ver,
           mapped_cnt   TYPE i,
         END OF ty_candidate.

  DATA: lt_headers          TYPE string_table,
        lt_norm_headers     TYPE SORTED TABLE OF string WITH UNIQUE KEY table_line,
        lt_prof             TYPE STANDARD TABLE OF zbdc_prof_bup,
        lt_map              TYPE STANDARD TABLE OF zbdc_mapping_bup,
        lt_exact_candidates TYPE STANDARD TABLE OF ty_candidate,
        lt_active_candidates TYPE STANDARD TABLE OF ty_candidate,
        lt_seen_all         TYPE SORTED TABLE OF string WITH UNIQUE KEY table_line,
        ls_prof             TYPE zbdc_prof_bup,
        ls_map              TYPE zbdc_mapping_bup,
        ls_candidate        TYPE ty_candidate,
        lv_header           TYPE string,
        lv_source           TYPE string,
        lv_mapped_hit       TYPE i,
        lv_source_total     TYPE i,
        lv_header_total     TYPE i,
        lv_file_upper       TYPE string,
        lv_expected_tag     TYPE string,
        lv_expected_tag_raw TYPE string,
        lv_ver_tag          TYPE n LENGTH 4,
        lv_filename_bound   TYPE abap_bool,
        lv_generated_hint   TYPE abap_bool.

  CLEAR: cv_tcode, txtp_profile_name, gv_profile_ver.

  PERFORM split_csv_line USING iv_header CHANGING lt_headers.
  LOOP AT lt_headers INTO lv_header.
    TRANSLATE lv_header TO UPPER CASE.
    CONDENSE lv_header NO-GAPS.
    REPLACE ALL OCCURRENCES OF '*' IN lv_header WITH ''.
    REPLACE ALL OCCURRENCES OF '"' IN lv_header WITH ''.
    IF lv_header IS NOT INITIAL.
      INSERT lv_header INTO TABLE lt_norm_headers.
    ENDIF.
  ENDLOOP.

  IF lt_norm_headers IS INITIAL.
    MESSAGE s150(zbdc) DISPLAY LIKE 'E'.
    RETURN.
  ENDIF.

 "bind a system-generated versioned template to its exact contract.
 "The previous resolver inspected ACTIVE profiles only. Therefore a file
 "generated from TESTING v0017 could silently fall back to an older ACTIVE
 "v0010 when both versions shared the same required header signature.

 "This logic is fully generic: no TCODE/profile/field literal is used.
 "For every profile row we reconstruct the same neutral filename tag used by
 "the template generator: TEMPLATE_<TCODE>_<PROFILE>_V<VER>. If the uploaded
 "filename contains that exact tag (suffixes such as _FILLED are allowed),
 "the full header contract must also match exactly. Only then is that precise
 "ACTIVE/TESTING version selected. A versioned generated-template filename is
 "never allowed to fall back silently to another version.
  lv_file_upper = gv_current_file_name.
  TRANSLATE lv_file_upper TO UPPER CASE.
  IF lv_file_upper CS 'TEMPLATE_' AND lv_file_upper CS '_V'.
    lv_generated_hint = abap_true.
  ENDIF.

  SELECT * FROM zbdc_prof_bup
    INTO TABLE @lt_prof.

  LOOP AT lt_prof INTO ls_prof.
    IF ls_prof-status <> 'ACTIVE' AND ls_prof-status <> 'TESTING'.
      CONTINUE.
    ENDIF.

    SELECT * FROM zbdc_mapping_bup
      INTO TABLE @lt_map
      WHERE tcode        = @ls_prof-tcode
        AND profile_name = @ls_prof-profile_name
        AND profile_ver  = @ls_prof-profile_ver.
    IF lt_map IS INITIAL.
      CONTINUE.
    ENDIF.

 "arbitrary header auto-resolution uses the same emitted template
 "projection as generated-template validation and staging. Technical/audit
 "Mapping rows must never broaden or distort the inbound signature.
    PERFORM project_template_schema
      USING    ls_prof-tcode ls_prof-profile_name ls_prof-profile_ver
      CHANGING lt_map.
    IF lt_map IS INITIAL.
      CONTINUE.
    ENDIF.

    CLEAR: lv_mapped_hit, lv_source_total, lt_seen_all,
           lv_filename_bound, lv_expected_tag, lv_expected_tag_raw,
           lv_ver_tag.

    LOOP AT lt_map INTO ls_map.
      lv_source = ls_map-source_column.
      TRANSLATE lv_source TO UPPER CASE.
      CONDENSE lv_source NO-GAPS.
      REPLACE ALL OCCURRENCES OF '*' IN lv_source WITH ''.
      REPLACE ALL OCCURRENCES OF '"' IN lv_source WITH ''.
      IF lv_source IS INITIAL.
        CONTINUE.
      ENDIF.

      READ TABLE lt_seen_all WITH TABLE KEY table_line = lv_source TRANSPORTING NO FIELDS.
      IF sy-subrc <> 0.
        INSERT lv_source INTO TABLE lt_seen_all.
        READ TABLE lt_norm_headers WITH TABLE KEY table_line = lv_source TRANSPORTING NO FIELDS.
        IF sy-subrc = 0.
          lv_mapped_hit = lv_mapped_hit + 1.
        ENDIF.
      ENDIF.

    ENDLOOP.

    lv_source_total = lines( lt_seen_all ).
    lv_header_total = lines( lt_norm_headers ).

 "template generator persists profile versions using the DDIC
 "display representation (for example v0017), while profile/version ALV
 "and some assignments may expose the same numeric value as 17.
 "reconstructed only one textual representation, so an exact v0017 file
 "could fail provenance binding and be rejected before any CSV row was
 "loaded. Build both representations generically from PROFILE_VER; no
 "TCODE/profile/version literal is hardcoded.
    lv_expected_tag_raw =
      |TEMPLATE_{ ls_prof-tcode }_{ ls_prof-profile_name }_V{ ls_prof-profile_ver }|.
    TRANSLATE lv_expected_tag_raw USING ' _'.
    TRANSLATE lv_expected_tag_raw TO UPPER CASE.

    lv_ver_tag = ls_prof-profile_ver.
    lv_expected_tag =
      |TEMPLATE_{ ls_prof-tcode }_{ ls_prof-profile_name }_V{ lv_ver_tag }|.
    TRANSLATE lv_expected_tag USING ' _'.
    TRANSLATE lv_expected_tag TO UPPER CASE.

    IF lv_file_upper IS NOT INITIAL AND
       ( lv_file_upper CS lv_expected_tag OR
         lv_file_upper CS lv_expected_tag_raw ).
      lv_filename_bound = abap_true.
    ENDIF.

 "Exact generated-template provenance requires the complete contract, not
 "merely the required signature. This prevents a renamed or stale file from
 "claiming a version while carrying a different header schema.
    IF lv_filename_bound = abap_true AND
       lv_source_total > 0 AND
       lv_mapped_hit = lv_source_total AND
       lv_header_total = lv_source_total.
      CLEAR ls_candidate.
      ls_candidate-tcode        = ls_prof-tcode.
      ls_candidate-profile_name = ls_prof-profile_name.
      ls_candidate-profile_ver  = ls_prof-profile_ver.
      ls_candidate-mapped_cnt   = lv_mapped_hit.
      APPEND ls_candidate TO lt_exact_candidates.
    ENDIF.

 "Arbitrary inbound files also resolve only by the COMPLETE emitted
 "business-input schema. Required/Optional metadata is not an upload identity.
    IF ls_prof-status = 'ACTIVE' AND
       lv_source_total > 0 AND
       lv_mapped_hit = lv_source_total AND
       lv_header_total = lv_source_total.
      CLEAR ls_candidate.
      ls_candidate-tcode        = ls_prof-tcode.
      ls_candidate-profile_name = ls_prof-profile_name.
      ls_candidate-profile_ver  = ls_prof-profile_ver.
      ls_candidate-mapped_cnt   = lv_mapped_hit.
      APPEND ls_candidate TO lt_active_candidates.
    ENDIF.
  ENDLOOP.

  IF lines( lt_exact_candidates ) = 1.
    READ TABLE lt_exact_candidates INTO ls_candidate INDEX 1.
    cv_tcode          = ls_candidate-tcode.
    txtp_profile_name = ls_candidate-profile_name.
    gv_profile_ver    = ls_candidate-profile_ver.
    p_transaction     = cv_tcode.
    MESSAGE s151(zbdc)
      WITH cv_tcode txtp_profile_name gv_profile_ver.
    RETURN.
  ELSEIF lines( lt_exact_candidates ) > 1.
    DATA(lv_zm804_1066_1) = |{ lines( lt_exact_candidates ) }|.
    MESSAGE ID 'ZBDC' TYPE 'S' NUMBER '804'
      WITH lv_zm804_1066_1 INTO gv_ingest_error_msg.
    PERFORM userize_ui_message USING gv_ingest_error_msg CHANGING gv_ui_message.
    MESSAGE gv_ui_message TYPE 'S' DISPLAY LIKE 'E'.
    RETURN.
  ENDIF.

 "A filename that carries generated-template provenance must never be rebound
 "to a different ACTIVE version just because its headers look similar.
  IF lv_generated_hint = abap_true.
    MESSAGE ID 'ZBDC' TYPE 'S' NUMBER '805' INTO gv_ingest_error_msg.
    PERFORM userize_ui_message USING gv_ingest_error_msg CHANGING gv_ui_message.
    MESSAGE gv_ui_message TYPE 'S' DISPLAY LIKE 'E'.
    RETURN.
  ENDIF.

  IF lines( lt_active_candidates ) = 1.
    READ TABLE lt_active_candidates INTO ls_candidate INDEX 1.
    cv_tcode          = ls_candidate-tcode.
    txtp_profile_name = ls_candidate-profile_name.
    gv_profile_ver    = ls_candidate-profile_ver.
    p_transaction     = cv_tcode.
    MESSAGE s152(zbdc)
      WITH cv_tcode txtp_profile_name gv_profile_ver.
  ELSEIF lt_active_candidates IS INITIAL.
    MESSAGE ID 'ZBDC' TYPE 'S' NUMBER '806' INTO gv_ingest_error_msg.
    PERFORM userize_ui_message USING gv_ingest_error_msg CHANGING gv_ui_message.
    MESSAGE gv_ui_message TYPE 'S' DISPLAY LIKE 'E'.
  ELSE.
    DATA(lv_zm807_1091_1) = |{ lines( lt_active_candidates ) }|.
    MESSAGE ID 'ZBDC' TYPE 'S' NUMBER '807'
      WITH lv_zm807_1091_1 INTO gv_ingest_error_msg.
    PERFORM userize_ui_message USING gv_ingest_error_msg CHANGING gv_ui_message.
    MESSAGE gv_ui_message TYPE 'S' DISPLAY LIKE 'E'.
  ENDIF.
ENDFORM.

FORM p1_save_skipped_unit USING iv_session_id TYPE zbdc_staging_bup-session_id
                                  iv_source     TYPE char20
                                  iv_file       TYPE string
                                  iv_reason     TYPE string.
  DATA: ls_file_lg TYPE zbdc_file_lg_bup,
        ls_res     TYPE zbdc_result_bup,
        lv_ts      TYPE tzntstmps,
        lv_p_at    TYPE zbdc_file_lg_bup-processed_at,
        lv_hash    TYPE zbdc_file_lg_bup-file_hash,
        lv_demo_date_836 TYPE sy-datum,
        lv_demo_time_836 TYPE sy-uzeit,
        lv_hash_payload TYPE string,
        lv_hash64 TYPE string.
  IF iv_session_id IS INITIAL.
    RETURN.
  ENDIF.
  GET TIME STAMP FIELD lv_ts.
  PERFORM get_demo_now CHANGING lv_demo_date_836 lv_demo_time_836.
  CONCATENATE lv_demo_date_836 lv_demo_time_836 INTO lv_p_at.
  lv_hash_payload = |SKIPPED\|SESSION={ iv_session_id }\|SOURCE={ iv_source }\|FILE={ iv_file }\|REASON={ iv_reason }|.
  TRY.
      cl_abap_message_digest=>calculate_hash_for_char(
        EXPORTING if_algorithm = 'SHA-256' if_data = lv_hash_payload
        IMPORTING ef_hashb64string = lv_hash64 ).
      lv_hash = lv_hash64.
    CATCH cx_abap_message_digest.
      CONCATENATE iv_session_id lv_demo_date_836 lv_demo_time_836 INTO lv_hash.
  ENDTRY.

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

  "Keep Preview Files owner/scope complete even when no staging row exists.
  "The source audit row above carries USER=SY-UNAME, so the normal session
  "summary can persist CREATED_BY without inventing another ownership source.
  PERFORM update_session_summary USING iv_session_id.
  PERFORM register_current_session USING iv_session_id.
ENDFORM.

*& Persist one rejected upload attempt even when parsing creates zero rows.
*& This is ingestion history, not execution truth. It lets My/All Uploads show
*& the exact attempted file, time, source and rejection reason after Ingest.
FORM p1_save_rejected_unit USING iv_session_id TYPE zbdc_staging_bup-session_id
                                    iv_source     TYPE char20
                                    iv_file       TYPE string
                                    iv_reason     TYPE string.
  DATA: ls_file_lg TYPE zbdc_file_lg_bup,
        ls_res     TYPE zbdc_result_bup,
        lv_ts      TYPE tzntstmps,
        lv_p_at    TYPE zbdc_file_lg_bup-processed_at,
        lv_hash    TYPE zbdc_file_lg_bup-file_hash,
        lv_demo_date TYPE sy-datum,
        lv_demo_time TYPE sy-uzeit,
        lv_payload TYPE string,
        lv_hash64  TYPE string.

  IF iv_session_id IS INITIAL.
    RETURN.
  ENDIF.

  GET TIME STAMP FIELD lv_ts.
  PERFORM get_demo_now CHANGING lv_demo_date lv_demo_time.
  CONCATENATE lv_demo_date lv_demo_time INTO lv_p_at.

  lv_payload = |REJECTED\|SESSION={ iv_session_id }\|SOURCE={ iv_source }\|FILE={ iv_file }\|REASON={ iv_reason }|.
  TRY.
      cl_abap_message_digest=>calculate_hash_for_char(
        EXPORTING if_algorithm = 'SHA-256' if_data = lv_payload
        IMPORTING ef_hashb64string = lv_hash64 ).
      lv_hash = lv_hash64.
    CATCH cx_abap_message_digest.
      CONCATENATE iv_session_id lv_demo_date lv_demo_time INTO lv_hash.
  ENDTRY.

  CLEAR ls_file_lg.
  ls_file_lg-file_hash    = lv_hash.
  ls_file_lg-file_name    = iv_file.
  ls_file_lg-source       = iv_source.
  ls_file_lg-row_count    = 0.
  ls_file_lg-session_id   = iv_session_id.
  ls_file_lg-processed_at = lv_p_at.
  ls_file_lg-status       = 'ERROR'.
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
  ls_res-msg_type    = 'E'.
  ls_res-message     = |INBOUND_SOURCE={ iv_source };FILE={ iv_file };REJECTED={ iv_reason };USER={ sy-uname }|.
  ls_res-exec_status = 'ERROR'.
  ls_res-created_at  = lv_ts.
  ls_res-step        = 0.
  INSERT zbdc_result_bup FROM ls_res.
  IF sy-subrc <> 0.
    MODIFY zbdc_result_bup FROM ls_res.
  ENDIF.

  PERFORM update_session_summary USING iv_session_id.
  PERFORM register_current_session USING iv_session_id.
ENDFORM.

FORM p1_sheet_to_raw USING ir_tab TYPE REF TO data
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

FORM ingest_xlsx_xstr USING iv_file TYPE string
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
    cv_unit_idx = cv_unit_idx + 1.
    PERFORM make_batch_session USING cv_unit_idx CHANGING lv_session.
    PERFORM p1_compose_unit_name USING iv_file 'DATA' CHANGING lv_unit.
    PERFORM p1_save_rejected_unit
      USING lv_session iv_source lv_unit 'Workbook payload is empty.'.
    RETURN.
  ENDIF.

  lv_bytes = xstrlen( iv_xstr ).
  PERFORM format_file_size USING lv_bytes CHANGING lv_size_txt.
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
      DATA(lv_xlsx_error_text) = lx_xlsx->get_text( ).
      cv_unit_idx = cv_unit_idx + 1.
      PERFORM make_batch_session USING cv_unit_idx CHANGING lv_session.
      PERFORM p1_compose_unit_name USING iv_file 'DATA' CHANGING lv_unit.
      PERFORM p1_save_rejected_unit
        USING lv_session iv_source lv_unit lv_xlsx_error_text.
      MESSAGE s153(zbdc)
        WITH iv_file lv_xlsx_error_text
        DISPLAY LIKE 'W'.
      RETURN.
  ENDTRY.

  IF lt_sheets IS INITIAL.
    cv_bad = cv_bad + 1.
    cv_unit_idx = cv_unit_idx + 1.
    PERFORM make_batch_session USING cv_unit_idx CHANGING lv_session.
    PERFORM p1_compose_unit_name USING iv_file 'DATA' CHANGING lv_unit.
    PERFORM p1_save_rejected_unit
      USING lv_session iv_source lv_unit 'Workbook contains no worksheet.'.
    RETURN.
  ENDIF.

  LOOP AT lt_sheets INTO lv_sheet.
    CLEAR: lv_skip, lv_reason, lv_unit.
    cv_unit_idx = cv_unit_idx + 1.
    PERFORM make_batch_session USING cv_unit_idx CHANGING lv_session.
    PERFORM p1_compose_unit_name USING iv_file lv_sheet CHANGING lv_unit.
    PERFORM p1_is_skip_sheet USING lv_sheet CHANGING lv_skip lv_reason.
    IF lv_skip = abap_true.
      PERFORM p1_save_skipped_unit USING lv_session iv_source lv_unit lv_reason.
      cv_bad = cv_bad + 1.
      CONTINUE.
    ENDIF.

    TRY.
        lr_data = lo_excel->if_fdt_doc_spreadsheet~get_itab_from_worksheet( lv_sheet ).
      CATCH cx_root INTO DATA(lx_sheet).
        lv_reason = lx_sheet->get_text( ).
        PERFORM p1_save_rejected_unit USING lv_session iv_source lv_unit lv_reason.
        cv_bad = cv_bad + 1.
        CONTINUE.
    ENDTRY.

    PERFORM p1_sheet_to_raw USING lr_data CHANGING lt_raw.
    DELETE lt_raw WHERE table_line IS INITIAL.
    IF lines( lt_raw ) <= 1.
      PERFORM p1_save_rejected_unit USING lv_session iv_source lv_unit 'Empty sheet / no data rows'.
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
      PERFORM register_current_session USING lv_session.
      CLEAR ls_meta.
      PERFORM p1_split_unit_name USING lv_unit CHANGING lv_title lv_sheet_c.
      ls_meta-file_name   = lv_unit.
      ls_meta-file_title  = lv_title.
      ls_meta-sheet_name  = lv_sheet_c.
      ls_meta-file_size   = lv_size_txt.
      ls_meta-rows_loaded = lv_after - lv_before.
      ls_meta-channel     = iv_source.
      PERFORM get_demo_now CHANGING ls_meta-upload_date ls_meta-upload_time.
      ls_meta-username    = sy-uname.
      ls_meta-session_id  = lv_session.
      ls_meta-tx_code = p_transaction.
      APPEND ls_meta TO gt_files_preview.
    ELSE.
      DATA(lv_reject_reason) = gv_ingest_error_msg.
      IF lv_reject_reason IS INITIAL.
        lv_reject_reason = 'No mapped rows loaded'.
      ENDIF.
      PERFORM p1_save_rejected_unit USING lv_session iv_source lv_unit lv_reject_reason.
      cv_bad = cv_bad + 1.
    ENDIF.
  ENDLOOP.
ENDFORM.

FORM read_local_xstr USING iv_file TYPE string
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

*& ---------------------------------------------------------------------*
*& Preview schema loader - exact session contract, no active UI context
*& ---------------------------------------------------------------------*
*& Preview Data is display/audit truth.  A historical row must therefore
*& use the immutable SCRIPT_ID stored on its own ZBDC_SESSION_BUP row, not
*& whichever Profile/Version is currently active in screen memory.
*&
*& Preferred authority: frozen TMPL0001..TMPLnnnn manifest on SCRIPT_ID.
*& Legacy fallback: the exact session Mapping projection only when the old
*& script genuinely has no frozen manifest.  Both header and value rebuild
*& call this same helper so COLnn can never be labelled by one schema and
*& populated by another.
FORM preview_load_session_schema
  USING    iv_session_id TYPE zbdc_staging_bup-session_id
  CHANGING ct_sources    TYPE string_table
           cv_ok         TYPE abap_bool
           cv_message    TYPE string.

  DATA: ls_session      TYPE zbdc_session_bup,
        lv_count_cfg    TYPE zbdc_config_bup-config_value,
        lv_count_text   TYPE string,
        lv_value        TYPE zbdc_config_bup-config_value,
        lv_kind         TYPE string,
        lv_source       TYPE zbdc_mapping_bup-source_column,
        lv_count        TYPE i,
        lv_index        TYPE i,
        lv_count_valid  TYPE abap_bool,
        lt_legacy_map   TYPE STANDARD TABLE OF zbdc_mapping_bup,
        ls_legacy_map   TYPE zbdc_mapping_bup,
        lt_seen         TYPE SORTED TABLE OF zbdc_mapping_bup-source_column
                        WITH UNIQUE KEY table_line.

  CLEAR: cv_ok, cv_message.
  REFRESH ct_sources.

  IF iv_session_id IS INITIAL.
    cv_message = 'PREVIEW_CONTEXT_MISSING: session ID is empty.'.
    RETURN.
  ENDIF.

  SELECT SINGLE *
    FROM zbdc_session_bup
    INTO @ls_session
    WHERE session_id = @iv_session_id.
  IF sy-subrc <> 0 OR
     ls_session-tcode IS INITIAL OR
     ls_session-profile_name IS INITIAL OR
     ls_session-profile_ver IS INITIAL.
    cv_message = |PREVIEW_CONTEXT_MISSING: session { iv_session_id } has no frozen TCODE/Profile/Version.|.
    RETURN.
  ENDIF.

  "Use the exact session-owned script.  Do not resolve 'latest', certification
  "or current screen state for a historical Preview Data request.
  IF ls_session-script_id IS NOT INITIAL.
    CLEAR lv_count_cfg.
    PERFORM get_script_cfg
      USING    ls_session-script_id 'TMPLCNT'
      CHANGING lv_count_cfg.

    lv_count_text = lv_count_cfg.
    CONDENSE lv_count_text NO-GAPS.
    IF lv_count_text IS NOT INITIAL AND lv_count_text CO '0123456789'.
      TRY.
          lv_count = CONV i( lv_count_text ).
          IF lv_count > 0 AND lv_count <= 9999.
            lv_count_valid = abap_true.
          ENDIF.
        CATCH cx_root.
          CLEAR lv_count_valid.
      ENDTRY.
    ENDIF.

    IF lv_count_valid = abap_true.
      IF lv_count > 25.
        cv_message = |PREVIEW_SCHEMA_TOO_WIDE: frozen session { iv_session_id } has { lv_count } input columns; screen 0301 supports 25.|.
        RETURN.
      ENDIF.

      DO lv_count TIMES.
        lv_index = sy-index.
        CLEAR: lv_kind, lv_value, lv_source.
        PERFORM template_manifest_kind USING lv_index CHANGING lv_kind.
        PERFORM get_script_cfg
          USING    ls_session-script_id lv_kind
          CHANGING lv_value.
        IF lv_value IS INITIAL.
          cv_message = |PREVIEW_MANIFEST_INCOMPLETE: session { iv_session_id }, column { lv_index }.|.
          REFRESH ct_sources.
          RETURN.
        ENDIF.
        PERFORM normalize_mapping_source USING lv_value CHANGING lv_source.
        IF lv_source IS INITIAL.
          cv_message = |PREVIEW_MANIFEST_INVALID: session { iv_session_id }, column { lv_index }.|.
          REFRESH ct_sources.
          RETURN.
        ENDIF.
        APPEND lv_source TO ct_sources.
      ENDDO.

      cv_ok = abap_true.
      RETURN.
    ENDIF.

    "Count metadata can be stale. Recover the immutable manifest directly
    "from contiguous TMPL0001.. rows on the exact session SCRIPT_ID.
    DO 9999 TIMES.
      lv_index = sy-index.
      CLEAR: lv_kind, lv_value, lv_source.
      PERFORM template_manifest_kind USING lv_index CHANGING lv_kind.
      PERFORM get_script_cfg
        USING    ls_session-script_id lv_kind
        CHANGING lv_value.
      IF lv_value IS INITIAL.
        EXIT.
      ENDIF.
      IF lv_index > 25.
        cv_message = |PREVIEW_SCHEMA_TOO_WIDE: frozen session { iv_session_id } has more than 25 input columns.|.
        REFRESH ct_sources.
        RETURN.
      ENDIF.
      PERFORM normalize_mapping_source USING lv_value CHANGING lv_source.
      IF lv_source IS INITIAL.
        cv_message = |PREVIEW_MANIFEST_INVALID: session { iv_session_id }, recovered column { lv_index }.|.
        REFRESH ct_sources.
        RETURN.
      ENDIF.
      APPEND lv_source TO ct_sources.
    ENDDO.

    IF ct_sources IS NOT INITIAL.
      cv_ok = abap_true.
      RETURN.
    ENDIF.
  ENDIF.

  "Legacy sessions created before the immutable template manifest existed.
  "Use one deterministic exact-tuple projection for BOTH headers and values.
  SELECT * FROM zbdc_mapping_bup
    INTO TABLE @lt_legacy_map
    WHERE tcode        = @ls_session-tcode
      AND profile_name = @ls_session-profile_name
      AND profile_ver  = @ls_session-profile_ver.
  IF lt_legacy_map IS INITIAL.
    cv_message = |PREVIEW_MAPPING_UNAVAILABLE: no exact Mapping exists for session { iv_session_id }.|.
    RETURN.
  ENDIF.

  PERFORM project_template_schema
    USING    ls_session-tcode ls_session-profile_name ls_session-profile_ver
    CHANGING lt_legacy_map.
  "PROJECT_TEMPLATE_SCHEMA already returns the frozen Field Guide order when it exists.
  "Do not sort by FIELDxx here: doing so can relabel historical COLnn and
  "silently move/miss a real uploaded column.

  LOOP AT lt_legacy_map INTO ls_legacy_map.
    CLEAR lv_source.
    PERFORM normalize_mapping_source
      USING    ls_legacy_map-source_column
      CHANGING lv_source.
    IF lv_source IS INITIAL.
      CONTINUE.
    ENDIF.
    READ TABLE lt_seen WITH TABLE KEY table_line = lv_source
      TRANSPORTING NO FIELDS.
    IF sy-subrc = 0.
      CONTINUE.
    ENDIF.
    INSERT lv_source INTO TABLE lt_seen.
    APPEND lv_source TO ct_sources.
    IF lines( ct_sources ) > 25.
      cv_message = |PREVIEW_SCHEMA_TOO_WIDE: legacy session { iv_session_id } has more than 25 input columns.|.
      REFRESH ct_sources.
      RETURN.
    ENDIF.
  ENDLOOP.

  IF ct_sources IS INITIAL.
    cv_message = |PREVIEW_SCHEMA_UNAVAILABLE: no displayable source schema exists for session { iv_session_id }.|.
    RETURN.
  ENDIF.

  cv_ok = abap_true.
ENDFORM.

FORM preview_get_source_schema
  USING    iv_session_id TYPE zbdc_staging_bup-session_id
  CHANGING ct_sources    TYPE string_table
           cv_ok         TYPE abap_bool
           cv_message    TYPE string.

  DATA: lt_hdr    TYPE STANDARD TABLE OF ty_preview_hdr_cache,
        ls_hdr    TYPE ty_preview_hdr_cache,
        lv_source TYPE zbdc_mapping_bup-source_column.

  CLEAR: cv_ok, cv_message.
  REFRESH ct_sources.

  LOOP AT gt_preview_hdr_cache INTO ls_hdr
    WHERE session_id = iv_session_id.
    APPEND ls_hdr TO lt_hdr.
  ENDLOOP.
  SORT lt_hdr BY col_no.

  LOOP AT lt_hdr INTO ls_hdr.
    CLEAR lv_source.
    PERFORM normalize_mapping_source
      USING    ls_hdr-header_text
      CHANGING lv_source.
    IF lv_source IS INITIAL.
      cv_message = |PREVIEW_HEADER_INVALID: session { iv_session_id }, column { ls_hdr-col_no }.|.
      REFRESH ct_sources.
      RETURN.
    ENDIF.
    APPEND lv_source TO ct_sources.
  ENDLOOP.

  IF ct_sources IS NOT INITIAL.
    cv_ok = abap_true.
    RETURN.
  ENDIF.

  PERFORM preview_load_session_schema
    USING    iv_session_id
    CHANGING ct_sources cv_ok cv_message.
ENDFORM.

*&---------------------------------------------------------------------*
*& Reconstruct immutable Upload/Ingest value from append-only Change Audit
*&---------------------------------------------------------------------*
*& Preview Data is the source snapshot, not the mutable Staging projection.
*& When the in-memory source cache is gone (new Browse / new internal session /
*& My Uploads / All Uploads), start from current staging and replace a changed
*& FIELDxx with the earliest audited OLD_VALUE for that exact session+row+field.
*& Edit Staging is audit-mandatory, so this recreates the original ingest value
*& without adding a new DDIC snapshot table.
FORM preview_original_field_value
  USING    iv_session TYPE zbdc_staging_bup-session_id
           iv_row     TYPE zbdc_staging_bup-row_index
           iv_field   TYPE csequence
           iv_current TYPE any
  CHANGING cv_value   TYPE string.

  DATA: lv_exists TYPE abap_bool,
        lv_tab    TYPE tabname,
        lv_where  TYPE string,
        lt_audit  TYPE ty_t_z770_audit_raw.

  cv_value = |{ iv_current }|.
  IF iv_session IS INITIAL OR iv_row IS INITIAL OR iv_field IS INITIAL.
    RETURN.
  ENDIF.

  CLEAR lv_exists.
  PERFORM table_exists USING gc_z16_tab_chg CHANGING lv_exists.
  IF lv_exists <> abap_true.
    RETURN.
  ENDIF.

  lv_tab = gc_z16_tab_chg.
  lv_where = |SESSION_ID = '{ iv_session }' AND ROW_INDEX = { iv_row } AND FIELD_NAME = '{ iv_field }'|.

  TRY.
      SELECT * FROM (lv_tab)
        INTO CORRESPONDING FIELDS OF TABLE @lt_audit
        WHERE (lv_where).
    CATCH cx_root.
      RETURN.
  ENDTRY.

  IF lt_audit IS INITIAL.
    RETURN.
  ENDIF.

  "14I+ sessions persist an explicit immutable ingest snapshot. It survives
  "validation normalization, Edit Staging, Retry correction, Browse resets,
  "My/All Uploads, and a completely new internal session.
  READ TABLE lt_audit INTO DATA(ls_snapshot)
    WITH KEY change_action = 'INGEST_SNAPSHOT'.
  IF sy-subrc = 0.
    cv_value = ls_snapshot-old_value.
    RETURN.
  ENDIF.

  "Legacy sessions created before snapshot persistence: the earliest audited
  "OLD_VALUE is still safer than mutable current staging for manual edits.
  SORT lt_audit BY changed_at ASCENDING change_id ASCENDING.
  READ TABLE lt_audit INTO DATA(ls_first_audit) INDEX 1.
  IF sy-subrc = 0.
    cv_value = ls_first_audit-old_value.
  ENDIF.
ENDFORM.

*&---------------------------------------------------------------------*
*& Persist immutable Upload/Ingest snapshot in existing Change Audit store
*&---------------------------------------------------------------------*
FORM persist_ingest_snapshot
  USING    is_stg TYPE zbdc_staging_bup
           it_map TYPE ty_t_map
  CHANGING cv_ok  TYPE abap_bool
           cv_message TYPE string.

  DATA: lt_seen TYPE SORTED TABLE OF zbdc_mapping_bup-staging_field
                  WITH UNIQUE KEY table_line,
        lv_value TYPE string,
        lv_one_ok TYPE abap_bool,
        lv_one_msg TYPE string.
  FIELD-SYMBOLS <lv_any> TYPE any.

  CLEAR: cv_ok, cv_message.

  LOOP AT it_map INTO DATA(ls_snap_map).
    IF ls_snap_map-staging_field IS INITIAL OR ls_snap_map-staging_field NP 'FIELD*'.
      CONTINUE.
    ENDIF.
    READ TABLE lt_seen WITH TABLE KEY table_line = ls_snap_map-staging_field
      TRANSPORTING NO FIELDS.
    IF sy-subrc = 0.
      CONTINUE.
    ENDIF.
    INSERT ls_snap_map-staging_field INTO TABLE lt_seen.

    UNASSIGN <lv_any>.
    ASSIGN COMPONENT ls_snap_map-staging_field OF STRUCTURE is_stg TO <lv_any>.
    IF sy-subrc <> 0 OR <lv_any> IS NOT ASSIGNED.
      cv_message = |INGEST_SNAPSHOT_BIND_INVALID: { ls_snap_map-staging_field }.|.
      RETURN.
    ENDIF.
    lv_value = |{ <lv_any> }|.
    UNASSIGN <lv_any>.

    CLEAR: lv_one_ok, lv_one_msg.
    PERFORM insert_change_audit_row
      USING    is_stg-session_id is_stg-row_index is_stg-tcode
               ls_snap_map-staging_field lv_value lv_value 'INGEST_SNAPSHOT'
      CHANGING lv_one_ok lv_one_msg.
    IF lv_one_ok <> abap_true.
      cv_message = |Immutable Preview snapshot could not be persisted: { lv_one_msg }|.
      RETURN.
    ENDIF.
  ENDLOOP.

  IF lt_seen IS INITIAL.
    cv_message = 'Immutable Preview snapshot has no mapped FIELDxx columns.'.
    RETURN.
  ENDIF.

  cv_ok = abap_true.
ENDFORM.

*&---------------------------------------------------------------------*
*& Remove only uncommitted immutable snapshots for one rejected ingest unit
*&---------------------------------------------------------------------*
FORM cleanup_ingest_snapshots
  USING iv_session TYPE zbdc_staging_bup-session_id.

  DATA: lv_exists TYPE abap_bool,
        lv_tab    TYPE tabname,
        lv_where  TYPE string.

  IF iv_session IS INITIAL.
    RETURN.
  ENDIF.

  CLEAR lv_exists.
  PERFORM table_exists USING gc_z16_tab_chg CHANGING lv_exists.
  IF lv_exists <> abap_true.
    RETURN.
  ENDIF.

  lv_tab = gc_z16_tab_chg.
  lv_where = |SESSION_ID = '{ iv_session }' AND CHANGE_ACTION = 'INGEST_SNAPSHOT'|.
  TRY.
      DELETE FROM (lv_tab) WHERE (lv_where).
    CATCH cx_root.
      "The original snapshot failure remains the authoritative rejection reason.
      RETURN.
  ENDTRY.
ENDFORM.

FORM build_preview_rows.
 "0301 is a clean business preview.  One canonical display schema is chosen
 "from the FIRST loaded session. Every other row is aligned by source name,
 "never by a stale Mapping order or by a previous upload's global context.
  DATA: ls_prev          TYPE ty_preview_disp,
        ls_src_cache     TYPE ty_preview_src_cache,
        ls_session_ctx   TYPE zbdc_session_bup,
        ls_map_candidate TYPE zbdc_mapping_bup,
        ls_map_match     TYPE zbdc_mapping_bup,
        lt_map_all       TYPE STANDARD TABLE OF zbdc_mapping_bup,
        lt_display_schema TYPE string_table,
        lt_session_schema TYPE string_table,
        lv_display_schema_ok TYPE abap_bool,
        lv_display_schema_msg TYPE string,
        lv_session_schema_ok TYPE abap_bool,
        lv_session_schema_msg TYPE string,
        lv_source_cached TYPE abap_bool,
        lv_file          TYPE char80,
        lv_sheet         TYPE char40,
        lv_batch         TYPE zbdc_staging_bup-session_id,
        lv_raw           TYPE string,
        lv_nr            TYPE n LENGTH 2,
        lv_dst_col       TYPE string,
        lv_src_col       TYPE string,
        lv_display_source TYPE string,
        lv_map_source    TYPE zbdc_mapping_bup-source_column,
        lv_source_index  TYPE i,
        lv_match_count   TYPE i,
        lv_original_value TYPE string,
        lv_first_sid     TYPE zbdc_staging_bup-session_id,
        lt_hist_targets  TYPE SORTED TABLE OF zbdc_mapping_bup-staging_field
                         WITH UNIQUE KEY table_line.

  FIELD-SYMBOLS: <lv_stg_val>  TYPE any,
                 <lv_disp_val> TYPE any,
                 <lv_cache_val> TYPE any.

  REFRESH gt_preview_data.

  "Freeze one header/value coordinate system for this ALV render.  A single
  "grid cannot safely label each row with a different column order.
  READ TABLE gt_staging INTO DATA(ls_first_preview_stg) INDEX 1.
  IF sy-subrc = 0 AND ls_first_preview_stg-session_id IS NOT INITIAL.
    lv_first_sid = ls_first_preview_stg-session_id.
    CLEAR: lv_display_schema_ok, lv_display_schema_msg.
    PERFORM preview_get_source_schema
      USING    lv_first_sid
      CHANGING lt_display_schema lv_display_schema_ok lv_display_schema_msg.
  ENDIF.

  LOOP AT gt_staging INTO DATA(ls_stg).
    CLEAR: ls_prev, ls_src_cache, ls_session_ctx,
           lv_source_cached, lv_file, lv_sheet, lv_batch, lv_raw.

    READ TABLE gt_preview_src_cache INTO ls_src_cache
      WITH KEY session_id = ls_stg-session_id
               row_index  = ls_stg-row_index.
    IF sy-subrc = 0.
      lv_source_cached = abap_true.
    ENDIF.

    SELECT SINGLE file_name FROM zbdc_file_lg_bup
      WHERE session_id = @ls_stg-session_id
      INTO @lv_raw.
    IF lv_raw IS INITIAL.
      lv_raw = ls_stg-session_id.
    ENDIF.

    PERFORM p1_split_unit_name USING lv_raw CHANGING lv_file lv_sheet.
    PERFORM batch_prefix_from_sid USING ls_stg-session_id CHANGING lv_batch.

    ls_prev-batch_key    = lv_batch.
    ls_prev-file_title   = lv_file.
    ls_prev-sheet_name   = lv_sheet.
    ls_prev-tx_code      = ls_stg-tcode.
    ls_prev-excel_row    = ls_stg-row_index.

    "BUSINESS_KEY is part of the immutable uploaded snapshot too. Fresh upload
    "uses the source cache; history reconstructs FIELD01 before any edit.
    IF lv_source_cached = abap_true.
      ls_prev-business_key = ls_src_cache-preview_row-business_key.
    ELSE.
      CLEAR lv_original_value.
      PERFORM preview_original_field_value
        USING    ls_stg-session_id ls_stg-row_index 'FIELD01' ls_stg-field01
        CHANGING lv_original_value.
      ls_prev-business_key = lv_original_value.
    ENDIF.
    IF ls_prev-business_key IS INITIAL.
      ls_prev-business_key = ls_stg-record_key.
    ENDIF.

    ls_prev-status_text  = ls_stg-status.
    ls_prev-message_text = ls_stg-error_msg.

    IF lv_display_schema_ok <> abap_true OR lt_display_schema IS INITIAL.
      IF lv_display_schema_msg IS INITIAL.
        lv_display_schema_msg = |PREVIEW_SCHEMA_UNAVAILABLE: session { lv_first_sid }.|.
      ENDIF.
      ls_prev-message_text = lv_display_schema_msg.
      APPEND ls_prev TO gt_preview_data.
      CONTINUE.
    ENDIF.

    IF lv_source_cached = abap_true.
      "Fresh Local/Drive/Gmail upload: values come only from the exact source
      "cache.  If several files are in one ingest batch, realign each file by
      "its source header name into the first session's visible header order.
      CLEAR: lv_session_schema_ok, lv_session_schema_msg.
      REFRESH lt_session_schema.
      PERFORM preview_get_source_schema
        USING    ls_stg-session_id
        CHANGING lt_session_schema lv_session_schema_ok lv_session_schema_msg.

      IF lv_session_schema_ok <> abap_true OR lt_session_schema IS INITIAL.
        IF lv_session_schema_msg IS INITIAL.
          lv_session_schema_msg = |PREVIEW_SOURCE_SCHEMA_UNAVAILABLE: session { ls_stg-session_id }.|.
        ENDIF.
        ls_prev-message_text = lv_session_schema_msg.
        APPEND ls_prev TO gt_preview_data.
        CONTINUE.
      ENDIF.

      LOOP AT lt_display_schema INTO lv_display_source.
        lv_source_index = sy-tabix.
        IF lv_source_index > 25.
          EXIT.
        ENDIF.

        READ TABLE lt_session_schema
          WITH KEY table_line = lv_display_source
          TRANSPORTING NO FIELDS.
        IF sy-subrc <> 0 OR sy-tabix <= 0 OR sy-tabix > 25.
          ls_prev-message_text =
            |PREVIEW_SCHEMA_MISMATCH: source { lv_display_source } is missing from session { ls_stg-session_id }.|.
          CONTINUE.
        ENDIF.

        lv_nr = sy-tabix.
        CONCATENATE 'COL' lv_nr INTO lv_src_col.
        lv_nr = lv_source_index.
        CONCATENATE 'COL' lv_nr INTO lv_dst_col.

        UNASSIGN: <lv_cache_val>, <lv_disp_val>.
        ASSIGN COMPONENT lv_src_col
          OF STRUCTURE ls_src_cache-preview_row TO <lv_cache_val>.
        ASSIGN COMPONENT lv_dst_col
          OF STRUCTURE ls_prev TO <lv_disp_val>.
        IF <lv_cache_val> IS ASSIGNED AND <lv_disp_val> IS ASSIGNED.
          <lv_disp_val> = <lv_cache_val>.
        ELSE.
          ls_prev-message_text =
            |PREVIEW_SLOT_INVALID: { lv_src_col } -> { lv_dst_col }.|.
        ENDIF.
      ENDLOOP.

    ELSE.
      "Historical/persisted session: rebuild values against the SAME frozen
      "schema used by the field catalog.  Never PROJECT_TEMPLATE_SCHEMA here;
      "that old second projection could drop/reorder columns after upload.
      SELECT SINGLE * FROM zbdc_session_bup
        INTO @ls_session_ctx
        WHERE session_id = @ls_stg-session_id.
      IF sy-subrc <> 0 OR
         ls_session_ctx-tcode IS INITIAL OR
         ls_session_ctx-profile_name IS INITIAL OR
         ls_session_ctx-profile_ver IS INITIAL.
        ls_prev-message_text =
          |PREVIEW_CONTEXT_MISSING: session { ls_stg-session_id } has no frozen contract.|.
        APPEND ls_prev TO gt_preview_data.
        CONTINUE.
      ENDIF.

      REFRESH lt_map_all.
      SELECT * FROM zbdc_mapping_bup
        INTO TABLE @lt_map_all
        WHERE tcode        = @ls_session_ctx-tcode
          AND profile_name = @ls_session_ctx-profile_name
          AND profile_ver  = @ls_session_ctx-profile_ver.
      IF lt_map_all IS INITIAL.
        ls_prev-message_text =
          |PREVIEW_MAPPING_UNAVAILABLE: { ls_session_ctx-tcode }/{ ls_session_ctx-profile_name } v{ ls_session_ctx-profile_ver }.|.
        APPEND ls_prev TO gt_preview_data.
        CONTINUE.
      ENDIF.

      REFRESH lt_hist_targets.
      LOOP AT lt_display_schema INTO lv_display_source.
        lv_source_index = sy-tabix.
        IF lv_source_index > 25.
          EXIT.
        ENDIF.

        CLEAR: ls_map_match, lv_match_count.
        LOOP AT lt_map_all INTO ls_map_candidate.
          CLEAR lv_map_source.
          PERFORM normalize_mapping_source
            USING    ls_map_candidate-source_column
            CHANGING lv_map_source.
          IF lv_map_source <> lv_display_source.
            CONTINUE.
          ENDIF.

          IF lv_match_count = 0.
            ls_map_match = ls_map_candidate.
            lv_match_count = 1.
          ELSEIF ls_map_candidate-staging_field = ls_map_match-staging_field
             AND ls_map_candidate-bdc_field     = ls_map_match-bdc_field.
            CONTINUE.
          ELSE.
            lv_match_count = lv_match_count + 1.
          ENDIF.
        ENDLOOP.

        IF lv_match_count = 0.
          ls_prev-message_text =
            |PREVIEW_MAPPING_SOURCE_MISSING: { lv_display_source } in session { ls_stg-session_id }.|.
          CONTINUE.
        ELSEIF lv_match_count > 1.
          ls_prev-message_text =
            |PREVIEW_MAPPING_SOURCE_AMBIGUOUS: { lv_display_source } in session { ls_stg-session_id }.|.
          CONTINUE.
        ENDIF.

        READ TABLE lt_hist_targets
          WITH TABLE KEY table_line = ls_map_match-staging_field
          TRANSPORTING NO FIELDS.
        IF sy-subrc = 0.
          ls_prev-message_text =
            |PREVIEW_MAPPING_TARGET_COLLISION: multiple uploaded columns share { ls_map_match-staging_field } in session { ls_stg-session_id }. Re-upload after fixing the Mapping contract.|.
          EXIT.
        ENDIF.
        INSERT ls_map_match-staging_field INTO TABLE lt_hist_targets.

        lv_nr = lv_source_index.
        CONCATENATE 'COL' lv_nr INTO lv_dst_col.
        UNASSIGN: <lv_stg_val>, <lv_disp_val>.
        ASSIGN COMPONENT ls_map_match-staging_field
          OF STRUCTURE ls_stg TO <lv_stg_val>.
        ASSIGN COMPONENT lv_dst_col
          OF STRUCTURE ls_prev TO <lv_disp_val>.
        IF <lv_stg_val> IS ASSIGNED AND <lv_disp_val> IS ASSIGNED.
          CLEAR lv_original_value.
          PERFORM preview_original_field_value
            USING    ls_stg-session_id ls_stg-row_index
                     ls_map_match-staging_field <lv_stg_val>
            CHANGING lv_original_value.
          <lv_disp_val> = lv_original_value.
        ELSE.
          ls_prev-message_text =
            |PREVIEW_STAGING_BIND_INVALID: { lv_display_source } -> { ls_map_match-staging_field }.|.
        ENDIF.
      ENDLOOP.
    ENDIF.

    APPEND ls_prev TO gt_preview_data.
  ENDLOOP.
ENDFORM.

*& Form build_fcat_0301
*& Reliable field catalog for CL_GUI_ALV_GRID on Preview Data (0301)

FORM build_fcat_0301 CHANGING ct_fcat TYPE lvc_t_fcat.
  DATA: ls_fcat TYPE lvc_s_fcat,
        lt_hdr_cache TYPE STANDARD TABLE OF ty_preview_hdr_cache,
        ls_hdr_cache TYPE ty_preview_hdr_cache,
        lt_manifest TYPE string_table,
        lv_schema_ok TYPE abap_bool,
        lv_schema_msg TYPE string,
        ls_first_stg TYPE zbdc_staging_bup,
        lv_nr   TYPE n LENGTH 2,
        lv_coln TYPE lvc_fname,
        lv_text TYPE lvc_txt,
        lv_col_pos TYPE i,
        lv_fixed_cols TYPE i,
        lv_first_tx_774 TYPE char20,
        lv_multi_tx_774 TYPE abap_bool.

  REFRESH ct_fcat.

  IF ts_preview-activetab = 'TAB_FILES'.
    CLEAR ls_fcat.
    ls_fcat-fieldname = 'FILE_TITLE'. ls_fcat-coltext = 'File Name'.
    ls_fcat-scrtext_l = 'File Name'. ls_fcat-scrtext_m = 'File Name'. ls_fcat-scrtext_s = 'File'.
    ls_fcat-outputlen = 40. ls_fcat-hotspot = abap_true. APPEND ls_fcat TO ct_fcat.

    CLEAR ls_fcat.
    ls_fcat-fieldname = 'TX_CODE'. ls_fcat-coltext = 'Transaction'.
    ls_fcat-scrtext_l = 'Transaction'. ls_fcat-scrtext_m = 'Transaction'. ls_fcat-scrtext_s = 'TCode'.
    ls_fcat-outputlen = 12. APPEND ls_fcat TO ct_fcat.

    CLEAR ls_fcat.
    ls_fcat-fieldname = 'EXCEL_ROW'. ls_fcat-coltext = 'Records'.
    ls_fcat-scrtext_l = 'Records'. ls_fcat-scrtext_m = 'Records'. ls_fcat-scrtext_s = 'Rows'.
    ls_fcat-outputlen = 9. APPEND ls_fcat TO ct_fcat.

    CLEAR ls_fcat.
    ls_fcat-fieldname = 'BUSINESS_KEY'. ls_fcat-coltext = 'Uploaded From'.
    ls_fcat-scrtext_l = 'Uploaded From'. ls_fcat-scrtext_m = 'Uploaded From'. ls_fcat-scrtext_s = 'Source'.
    ls_fcat-outputlen = 18. APPEND ls_fcat TO ct_fcat.

    CLEAR ls_fcat.
    ls_fcat-fieldname = 'COL01'. ls_fcat-coltext = 'Uploaded At'.
    ls_fcat-scrtext_l = 'Uploaded At'. ls_fcat-scrtext_m = 'Uploaded At'. ls_fcat-scrtext_s = 'Time'.
    ls_fcat-outputlen = 19. APPEND ls_fcat TO ct_fcat.

    IF gv_file_scope = gc_file_scope_all.
      CLEAR ls_fcat.
      ls_fcat-fieldname = 'COL02'. ls_fcat-coltext = 'Uploaded By'.
      ls_fcat-scrtext_l = 'Uploaded By'. ls_fcat-scrtext_m = 'Uploaded By'. ls_fcat-scrtext_s = 'User'.
      ls_fcat-outputlen = 12. APPEND ls_fcat TO ct_fcat.
    ENDIF.
    RETURN.
  ENDIF.

  "Preview Data is the uploaded file, read-only.
  CLEAR ls_fcat.
  ls_fcat-fieldname = 'EXCEL_ROW'. ls_fcat-coltext = 'Row'.
  ls_fcat-scrtext_l = 'Row'. ls_fcat-scrtext_m = 'Row'. ls_fcat-scrtext_s = 'Row'.
  ls_fcat-outputlen = 6. ls_fcat-col_pos = 1.
  APPEND ls_fcat TO ct_fcat.

  "Transaction is shown only for a mixed-TCODE preview.
  LOOP AT gt_preview_data INTO DATA(ls_tx_774).
    IF ls_tx_774-tx_code IS INITIAL.
      CONTINUE.
    ENDIF.
    IF lv_first_tx_774 IS INITIAL.
      lv_first_tx_774 = ls_tx_774-tx_code.
    ELSEIF ls_tx_774-tx_code <> lv_first_tx_774.
      lv_multi_tx_774 = abap_true.
      EXIT.
    ENDIF.
  ENDLOOP.

  lv_fixed_cols = 1.
  IF lv_multi_tx_774 = abap_true.
    CLEAR ls_fcat.
    ls_fcat-fieldname = 'TX_CODE'. ls_fcat-coltext = 'Transaction'.
    ls_fcat-scrtext_l = 'Transaction'. ls_fcat-scrtext_m = 'Transaction'. ls_fcat-scrtext_s = 'TCode'.
    ls_fcat-outputlen = 12. ls_fcat-col_pos = 2.
    APPEND ls_fcat TO ct_fcat.
    lv_fixed_cols = 2.
  ENDIF.

  "Current upload: exact header text/order captured from the parsed file.
  READ TABLE gt_staging INTO ls_first_stg INDEX 1.
  IF sy-subrc = 0 AND ls_first_stg-session_id IS NOT INITIAL.
    LOOP AT gt_preview_hdr_cache INTO ls_hdr_cache
      WHERE session_id = ls_first_stg-session_id.
      APPEND ls_hdr_cache TO lt_hdr_cache.
    ENDLOOP.
    SORT lt_hdr_cache BY col_no.
  ENDIF.

  "Persisted/old session fallback: use the exact SESSION_ID schema loader.
  "This deliberately does not call RESOLVE_SESSION_CONTEXT/active runtime
  "selection, so history cannot lose its columns when another upload/profile
  "is active or when certification lifecycle changes after the upload.
  IF lt_hdr_cache IS INITIAL
     AND ls_first_stg-session_id IS NOT INITIAL.
    CLEAR: lv_schema_ok, lv_schema_msg.
    REFRESH lt_manifest.
    PERFORM preview_load_session_schema
      USING    ls_first_stg-session_id
      CHANGING lt_manifest lv_schema_ok lv_schema_msg.

    IF lv_schema_ok = abap_true.
      LOOP AT lt_manifest INTO DATA(lv_manifest_header).
        CLEAR ls_hdr_cache.
        ls_hdr_cache-session_id = ls_first_stg-session_id.
        ls_hdr_cache-col_no = sy-tabix.
        ls_hdr_cache-header_text = lv_manifest_header.
        APPEND ls_hdr_cache TO lt_hdr_cache.
      ENDLOOP.
    ENDIF.
  ENDIF.

  "Never render a deceptively empty Preview when data exists but its exact
  "schema cannot be proven.  Expose one explicit diagnostic column instead.
  IF lt_hdr_cache IS INITIAL AND gt_staging IS NOT INITIAL.
    CLEAR ls_fcat.
    ls_fcat-fieldname = 'MESSAGE_TEXT'.
    ls_fcat-coltext   = 'Preview Schema Error'.
    ls_fcat-scrtext_l = 'Preview Schema Error'.
    ls_fcat-scrtext_m = 'Preview Error'.
    ls_fcat-scrtext_s = 'Error'.
    ls_fcat-outputlen = 80.
    ls_fcat-col_pos   = lv_fixed_cols + 1.
    APPEND ls_fcat TO ct_fcat.
    RETURN.
  ENDIF.

  "One file column -> one ALV COLnn in the identical order.
  CLEAR lv_col_pos.
  LOOP AT lt_hdr_cache INTO ls_hdr_cache.
    IF ls_hdr_cache-col_no < 1 OR ls_hdr_cache-col_no > 25.
      CONTINUE.
    ENDIF.

    lv_col_pos = lv_col_pos + 1.
    lv_nr = ls_hdr_cache-col_no.
    CONCATENATE 'COL' lv_nr INTO lv_coln.

    lv_text = ls_hdr_cache-header_text.
    IF lv_text IS INITIAL.
      lv_text = |Column { ls_hdr_cache-col_no }|.
    ENDIF.

    CLEAR ls_fcat.
    ls_fcat-fieldname = lv_coln.
    ls_fcat-coltext   = lv_text.
    ls_fcat-scrtext_l = lv_text.
    ls_fcat-scrtext_m = lv_text.
    ls_fcat-scrtext_s = lv_text.
    ls_fcat-outputlen = 22.
    ls_fcat-col_pos   = lv_col_pos + lv_fixed_cols.
    ls_fcat-no_out    = space.
    ls_fcat-tech      = space.
    APPEND ls_fcat TO ct_fcat.
  ENDLOOP.

  "If an exact historical value cannot be reconstructed, never hide that
  "fact behind a blank cell.  Surface a diagnostic column only for Preview
  "integrity failures; normal staging/business messages stay out of 0301.
  DATA lv_preview_diag TYPE abap_bool.
  LOOP AT gt_preview_data INTO DATA(ls_preview_diag).
    IF ls_preview_diag-message_text CP 'PREVIEW_*'.
      lv_preview_diag = abap_true.
      EXIT.
    ENDIF.
  ENDLOOP.
  IF lv_preview_diag = abap_true.
    CLEAR ls_fcat.
    ls_fcat-fieldname = 'MESSAGE_TEXT'.
    ls_fcat-coltext   = 'Preview Integrity'.
    ls_fcat-scrtext_l = 'Preview Integrity'.
    ls_fcat-scrtext_m = 'Preview Integrity'.
    ls_fcat-scrtext_s = 'Preview'.
    ls_fcat-outputlen = 80.
    ls_fcat-col_pos   = lv_col_pos + lv_fixed_cols + 1.
    APPEND ls_fcat TO ct_fcat.
  ENDIF.
ENDFORM.

FORM process_csv_rows USING pt_raw TYPE string_table.

  DATA: lt_headers    TYPE TABLE OF string,
        lv_header_ln  TYPE string.

  TYPES: BEGIN OF ty_col_idx,
           col_name TYPE string,
           col_no   TYPE i,
         END OF ty_col_idx.

  DATA: lt_col_idx  TYPE TABLE OF ty_col_idx,
        ls_col_idx  TYPE ty_col_idx,
        lt_map      TYPE STANDARD TABLE OF zbdc_mapping_bup,
        ls_map      TYPE zbdc_mapping_bup,
        lv_sess     TYPE zbdc_staging_bup-session_id,
        lv_idx      TYPE i,
        lv_added    TYPE i,
        ls_stg      TYPE zbdc_staging_bup,
        lt_col      TYPE TABLE OF string,
        lv_val      TYPE string,
        lv_src      TYPE string,
        lv_colno    TYPE i,
        lv_rowcount    TYPE i,
        lv_delim       TYPE c LENGTH 1,
        lv_header_cols TYPE i,
        lv_data_cols   TYPE i,
        lv_extra_idx   TYPE i,
        lv_extra_val       TYPE string,
        lv_raw_line_idx    TYPE i,
        lv_initial_staging TYPE i,
        lv_trim_idx        TYPE i,
        lv_csv_ok          TYPE abap_bool,
        lv_csv_msg         TYPE string,
        lv_dup_header      TYPE string,
        lv_demo_date_836    TYPE sy-datum,
        lv_demo_time_836    TYPE sy-uzeit,
        lt_preview_cache_local TYPE STANDARD TABLE OF ty_preview_src_cache,
        ls_preview_cache       TYPE ty_preview_src_cache,
        lt_preview_hdr_local   TYPE STANDARD TABLE OF ty_preview_hdr_cache,
        ls_preview_hdr         TYPE ty_preview_hdr_cache,
        lt_map_all             TYPE STANDARD TABLE OF zbdc_mapping_bup,
        ls_map_match           TYPE zbdc_mapping_bup,
        ls_map_candidate       TYPE zbdc_mapping_bup,
        lv_map_candidate_src   TYPE string,
        lv_map_match_count     TYPE i,
        lv_preview_col         TYPE string,
        lv_preview_nr          TYPE n LENGTH 2,
        lv_preview_file_col    TYPE i,
        lv_preview_value       TYPE string,
        lv_preview_header      TYPE string,
        lv_staged_check        TYPE string,
        lv_expected_check      TYPE string,
        lv_actual_check        TYPE string,
        lv_ctx_ok_ingest       TYPE abap_bool,
        lv_ctx_msg_ingest      TYPE string,
        lt_contract_scope      TYPE ty_t_staging_alv,
        ls_contract_row        TYPE ty_staging_alv,
        ls_contract_db         TYPE zbdc_staging_bup,
        lv_contract_ok         TYPE abap_bool,
        lv_contract_msg        TYPE string,
        lv_snapshot_ok         TYPE abap_bool,
        lv_snapshot_msg        TYPE string.

  DATA: lt_header_seen TYPE SORTED TABLE OF string
                        WITH UNIQUE KEY table_line,
        lt_target_seen TYPE SORTED TABLE OF zbdc_mapping_bup-staging_field
                        WITH UNIQUE KEY table_line.

  DATA lv_header_idx TYPE i.

    DATA: lv_declared_contract TYPE abap_bool,
        lv_declared_ok       TYPE abap_bool,
        lv_declared_msg      TYPE string,
        lv_meta_declared     TYPE abap_bool,
        lv_meta_tcode        TYPE zbdc_prof_bup-tcode,
        lv_meta_profile      TYPE zbdc_prof_bup-profile_name,
        lv_meta_ver          TYPE zbdc_prof_bup-profile_ver,
        lv_meta_script       TYPE zbdc_script_bup-script_id,
        lv_meta_hash         TYPE zbdc_script_bup-contract_hash.

FIELD-SYMBOLS: <fv> TYPE any,
               <pv> TYPE any.

  CLEAR gv_ingest_error_msg.
  lv_initial_staging = lines( gt_staging ).

 " 1. Raw file must not be empty

  IF pt_raw IS INITIAL.
    MESSAGE ID 'ZBDC' TYPE 'S' NUMBER '808' INTO gv_ingest_error_msg.
    PERFORM userize_ui_message USING gv_ingest_error_msg CHANGING gv_ui_message.
    MESSAGE gv_ui_message TYPE 'S' DISPLAY LIKE 'W'.
    RETURN.
  ENDIF.

 " 2. Find first real header line
 " Ignore empty line and comment/meta line starting with #

  CLEAR: lv_header_idx, lv_header_ln.

  LOOP AT pt_raw INTO lv_header_ln.
    IF lv_header_ln IS INITIAL.
      CONTINUE.
    ENDIF.

    IF lv_header_ln CP '#*'.
      CONTINUE.
    ENDIF.

    lv_header_idx = sy-tabix.
    EXIT.
  ENDLOOP.

  IF lv_header_idx IS INITIAL OR lv_header_ln IS INITIAL.
    MESSAGE ID 'ZBDC' TYPE 'S' NUMBER '809' INTO gv_ingest_error_msg.
    PERFORM userize_ui_message USING gv_ingest_error_msg CHANGING gv_ui_message.
    MESSAGE gv_ui_message TYPE 'S' DISPLAY LIKE 'W'.
    RETURN.
  ENDIF.

  REFRESH lt_headers.
  CLEAR: lv_csv_ok, lv_csv_msg.
  PERFORM check_csv_line
    USING    lv_header_ln
    CHANGING lv_csv_ok lv_csv_msg.
  IF lv_csv_ok <> abap_true.
    DATA(lv_zm810_2375_1) = |{ lv_csv_msg }|.
    MESSAGE ID 'ZBDC' TYPE 'S' NUMBER '810'
      WITH lv_zm810_2375_1 INTO gv_ingest_error_msg.
    PERFORM userize_ui_message USING gv_ingest_error_msg CHANGING gv_ui_message.
    MESSAGE gv_ui_message TYPE 'S' DISPLAY LIKE 'E'.
    RETURN.
  ENDIF.

  PERFORM detect_csv_delimiter
    USING    lv_header_ln
    CHANGING lv_delim.
  PERFORM split_csv_line_by_delim
    USING    lv_header_ln lv_delim
    CHANGING lt_headers.

  IF lt_headers IS INITIAL.
    DATA(lv_zm811_2388_1) = |{ lv_header_ln }|.
    MESSAGE ID 'ZBDC' TYPE 'S' NUMBER '811'
      WITH lv_zm811_2388_1 INTO gv_ingest_error_msg.
    PERFORM userize_ui_message USING gv_ingest_error_msg CHANGING gv_ui_message.
    MESSAGE gv_ui_message TYPE 'S' DISPLAY LIKE 'W'.
    RETURN.
  ENDIF.

 "duplicate normalized headers are ambiguous before contract
 "resolution and must never be collapsed into a unique-set signature.
  REFRESH lt_header_seen.
  CLEAR lv_dup_header.
  LOOP AT lt_headers INTO DATA(lv_hdr_pre).
    DATA(lv_hdr_norm_pre) = lv_hdr_pre.
    TRANSLATE lv_hdr_norm_pre TO UPPER CASE.
    CONDENSE lv_hdr_norm_pre NO-GAPS.
    REPLACE ALL OCCURRENCES OF '*' IN lv_hdr_norm_pre WITH ''.
    REPLACE ALL OCCURRENCES OF '"' IN lv_hdr_norm_pre WITH ''.
    IF lv_hdr_norm_pre IS INITIAL.
      CONTINUE.
    ENDIF.
    READ TABLE lt_header_seen
      WITH TABLE KEY table_line = lv_hdr_norm_pre
      TRANSPORTING NO FIELDS.
    IF sy-subrc = 0.
      lv_dup_header = lv_hdr_norm_pre.
      EXIT.
    ENDIF.
    INSERT lv_hdr_norm_pre INTO TABLE lt_header_seen.
  ENDLOOP.
  IF lv_dup_header IS NOT INITIAL.
    DATA(lv_zm812_2416_1) = |{ lv_dup_header }|.
    MESSAGE ID 'ZBDC' TYPE 'S' NUMBER '812'
      WITH lv_zm812_2416_1 INTO gv_ingest_error_msg.
    PERFORM userize_ui_message USING gv_ingest_error_msg CHANGING gv_ui_message.
    MESSAGE gv_ui_message TYPE 'S' DISPLAY LIKE 'E'.
    RETURN.
  ENDIF.

  lv_header_cols = lines( lt_headers ).

  "The upload/staging contract owns FIELD01..FIELD25 and Preview owns
  "COL01..COL25. Never silently truncate column 26+. If a generated
  "template somehow exceeds this invariant, reject before any staging row
  "is created so Preview/Edit Staging can never show an incomplete file.
  IF lv_header_cols > 25.
    DATA(lv_zm813_2429_1) = |{ lv_header_cols }|.
    MESSAGE ID 'ZBDC' TYPE 'S' NUMBER '813'
      WITH lv_zm813_2429_1 INTO gv_ingest_error_msg.
    PERFORM userize_ui_message USING gv_ingest_error_msg CHANGING gv_ui_message.
    MESSAGE gv_ui_message TYPE 'S' DISPLAY LIKE 'E'.
    RETURN.
  ENDIF.

 " 3. Resolve exact immutable contract.
 " A versioned generated template is authoritative: v17 must bind to
 " the import/script/mapping snapshot of v17, never to v18/v19/latest.

  CLEAR: p_transaction, txtp_profile_name, gv_profile_ver,
         gv_runtime_script_id, gv_runtime_contract_hash,
         gs_runtime_cert, gv_runtime_cert_loaded,
         gv_ingest_error_msg,
         lv_declared_contract, lv_declared_ok, lv_declared_msg,
         lv_meta_declared, lv_meta_tcode, lv_meta_profile,
         lv_meta_ver, lv_meta_script, lv_meta_hash.

 "metadata is authoritative when supplied by a generated template.
 "A file claiming v20/v21 is rejected before any staging row can execute;
 "a gap version such as v18 when only v17/v19 exist is rejected as well.
  PERFORM p1_parse_meta_raw
    USING    pt_raw
    CHANGING lv_meta_declared lv_meta_tcode lv_meta_profile lv_meta_ver
             lv_meta_script lv_meta_hash.

  IF lv_meta_declared = abap_true.
    lv_declared_contract = abap_true.
    PERFORM p1_guard_contract
      USING    lv_meta_tcode lv_meta_profile lv_meta_ver
               lv_meta_script lv_meta_hash lv_header_ln
      CHANGING lv_declared_ok lv_declared_msg.
  ELSE.
    PERFORM p1_resolve_declared_template
      USING    lv_header_ln
      CHANGING lv_declared_contract lv_declared_ok lv_declared_msg.
  ENDIF.

  IF lv_declared_contract = abap_true.
    IF lv_declared_ok <> abap_true.
      gv_ingest_error_msg = lv_declared_msg.
      PERFORM userize_ui_message USING gv_ingest_error_msg CHANGING gv_ui_message.
      MESSAGE gv_ui_message TYPE 'S' DISPLAY LIKE 'E'.
      RETURN.
    ENDIF.
  ELSE.
 "Arbitrary inbound files may be resolved only when the structural
 "signature identifies one unique runnable exact contract.
    PERFORM p1_resolve_unit_tcode
      USING    lv_header_ln
      CHANGING p_transaction.

    IF gv_ingest_error_msg IS NOT INITIAL.
      PERFORM userize_ui_message USING gv_ingest_error_msg CHANGING gv_ui_message.
      MESSAGE gv_ui_message TYPE 'S' DISPLAY LIKE 'E'.
      RETURN.
    ENDIF.
  ENDIF.

  IF p_transaction IS INITIAL
     OR txtp_profile_name IS INITIAL
     OR gv_profile_ver IS INITIAL.
    DATA(lv_zm814_2489_1) = |{ gv_current_file_name }|.
    DATA(lv_zm814_2489_2) = |{ gv_current_sheet_name }|.
    MESSAGE ID 'ZBDC' TYPE 'S' NUMBER '814'
      WITH lv_zm814_2489_1 lv_zm814_2489_2 INTO gv_ingest_error_msg.
    PERFORM userize_ui_message USING gv_ingest_error_msg CHANGING gv_ui_message.
    MESSAGE gv_ui_message TYPE 'S' DISPLAY LIKE 'E'.
    RETURN.
  ENDIF.

 " 4. Load mapping by resolved TCODE + Profile + Version

  REFRESH lt_map.

  SELECT * FROM zbdc_mapping_bup
    INTO TABLE @lt_map
    WHERE tcode        = @p_transaction
      AND profile_name = @txtp_profile_name
      AND profile_ver  = @gv_profile_ver.

  IF lt_map IS INITIAL.
    DATA(lv_zm815_2506_1) = |{ txtp_profile_name }|.
    DATA(lv_zm815_2506_2) = |{ gv_profile_ver }|.
    DATA(lv_zm815_2506_3) = |{ p_transaction }|.
    MESSAGE ID 'ZBDC' TYPE 'S' NUMBER '815'
      WITH lv_zm815_2506_1 lv_zm815_2506_2 lv_zm815_2506_3
      INTO gv_ingest_error_msg.
    PERFORM userize_ui_message USING gv_ingest_error_msg CHANGING gv_ui_message.
    MESSAGE gv_ui_message TYPE 'S' DISPLAY LIKE 'W'.
    RETURN.
  ENDIF.

 "The uploaded header has already been proven byte-for-order against the
 "frozen Template manifest above. Use that proven header as the exact inbound
 "membership/order authority. Re-running FIELD_GUIDE projection here can drop
 "valid generated columns when metadata is stale, which previously caused
 "Preview/Staging to keep only a subset of the XLSX.
  lt_map_all = lt_map.
  REFRESH lt_map.

  LOOP AT lt_headers INTO DATA(lv_map_header).
    lv_src = lv_map_header.
    TRANSLATE lv_src TO UPPER CASE.
    CONDENSE lv_src NO-GAPS.
    REPLACE ALL OCCURRENCES OF '*' IN lv_src WITH ''.
    REPLACE ALL OCCURRENCES OF '"' IN lv_src WITH ''.
    IF lv_src IS INITIAL.
      CONTINUE.
    ENDIF.

    CLEAR: ls_map_match, lv_map_match_count.
    LOOP AT lt_map_all INTO ls_map_candidate.
      lv_map_candidate_src = ls_map_candidate-source_column.
      TRANSLATE lv_map_candidate_src TO UPPER CASE.
      CONDENSE lv_map_candidate_src NO-GAPS.
      REPLACE ALL OCCURRENCES OF '*' IN lv_map_candidate_src WITH ''.
      REPLACE ALL OCCURRENCES OF '"' IN lv_map_candidate_src WITH ''.

      IF lv_map_candidate_src <> lv_src.
        CONTINUE.
      ENDIF.

      IF lv_map_match_count = 0.
        ls_map_match = ls_map_candidate.
        lv_map_match_count = 1.
      ELSEIF ls_map_candidate-staging_field = ls_map_match-staging_field
         AND ls_map_candidate-bdc_field     = ls_map_match-bdc_field.
        "Equivalent duplicate repository row: same exact runtime identity.
        CONTINUE.
      ELSE.
        lv_map_match_count = lv_map_match_count + 1.
      ENDIF.
    ENDLOOP.

    IF lv_map_match_count = 0.
      DATA(lv_zm816_2555_1) = |{ lv_src }|.
      DATA(lv_zm816_2555_2) = |{ p_transaction }|.
      DATA(lv_zm816_2555_3) = |{ txtp_profile_name }|.
      DATA(lv_zm816_2555_4) = |{ gv_profile_ver }|.
      MESSAGE ID 'ZBDC' TYPE 'S' NUMBER '816'
        WITH lv_zm816_2555_1 lv_zm816_2555_2 lv_zm816_2555_3 lv_zm816_2555_4
        INTO gv_ingest_error_msg.
      PERFORM userize_ui_message USING gv_ingest_error_msg CHANGING gv_ui_message.
      MESSAGE gv_ui_message TYPE 'S' DISPLAY LIKE 'E'.
      RETURN.
    ELSEIF lv_map_match_count > 1.
      DATA(lv_zm817_2560_1) = |{ lv_src }|.
      MESSAGE ID 'ZBDC' TYPE 'S' NUMBER '817'
        WITH lv_zm817_2560_1 INTO gv_ingest_error_msg.
      PERFORM userize_ui_message USING gv_ingest_error_msg CHANGING gv_ui_message.
      MESSAGE gv_ui_message TYPE 'S' DISPLAY LIKE 'E'.
      RETURN.
    ENDIF.

    APPEND ls_map_match TO lt_map.
  ENDLOOP.

  IF lt_map IS INITIAL.
    DATA(lv_zm818_2570_1) = |{ p_transaction }|.
    DATA(lv_zm818_2570_2) = |{ txtp_profile_name }|.
    DATA(lv_zm818_2570_3) = |{ gv_profile_ver }|.
    MESSAGE ID 'ZBDC' TYPE 'S' NUMBER '818'
      WITH lv_zm818_2570_1 lv_zm818_2570_2 lv_zm818_2570_3
      INTO gv_ingest_error_msg.
    PERFORM userize_ui_message USING gv_ingest_error_msg CHANGING gv_ui_message.
    MESSAGE gv_ui_message TYPE 'S' DISPLAY LIKE 'E'.
    RETURN.
  ENDIF.

  "Lossless staging invariant: two different uploaded headers may NEVER
  "share one STAGING_FIELD. The old flow could assign DIVISION and another
  "source to the same FIELDxx; the later assignment overwrote the earlier
  "one and Preview/Edit Staging then appeared to lose a column. Fail closed
  "before reading row 1 instead of accepting a destructive Mapping contract.
  REFRESH lt_target_seen.
  LOOP AT lt_map INTO ls_map.
    IF ls_map-staging_field IS INITIAL.
      DATA(lv_zm819_2584_1) = |{ ls_map-source_column }|.
      MESSAGE ID 'ZBDC' TYPE 'S' NUMBER '819'
        WITH lv_zm819_2584_1 INTO gv_ingest_error_msg.
      PERFORM userize_ui_message USING gv_ingest_error_msg CHANGING gv_ui_message.
      MESSAGE gv_ui_message TYPE 'S' DISPLAY LIKE 'E'.
      RETURN.
    ENDIF.

    READ TABLE lt_target_seen
      WITH TABLE KEY table_line = ls_map-staging_field
      TRANSPORTING NO FIELDS.
    IF sy-subrc = 0.
      DATA(lv_zm820_2594_1) = |{ ls_map-staging_field }|.
      MESSAGE ID 'ZBDC' TYPE 'S' NUMBER '820'
        WITH lv_zm820_2594_1 INTO gv_ingest_error_msg.
      PERFORM userize_ui_message USING gv_ingest_error_msg CHANGING gv_ui_message.
      MESSAGE gv_ui_message TYPE 'S' DISPLAY LIKE 'E'.
      RETURN.
    ENDIF.
    INSERT ls_map-staging_field INTO TABLE lt_target_seen.
  ENDLOOP.

 " 5. Normalize CSV header into column index table

  REFRESH lt_col_idx.

  LOOP AT lt_headers INTO DATA(lv_hdr).
    CLEAR ls_col_idx.

    ls_col_idx-col_name = lv_hdr.
    TRANSLATE ls_col_idx-col_name TO UPPER CASE.
    CONDENSE ls_col_idx-col_name NO-GAPS.
    REPLACE ALL OCCURRENCES OF '*' IN ls_col_idx-col_name WITH ''.
    REPLACE ALL OCCURRENCES OF '"' IN ls_col_idx-col_name WITH ''.

    ls_col_idx-col_no = sy-tabix.
    APPEND ls_col_idx TO lt_col_idx.
  ENDLOOP.

 " 6. Header membership is already proven against the complete frozen
 " template schema. Required/Optional flags are not an Upload/Ingest contract.

 " 7. Build session id

  IF gv_forced_session_id IS NOT INITIAL.
    lv_sess = gv_forced_session_id.
  ELSE.
    PERFORM get_demo_now CHANGING lv_demo_date_836 lv_demo_time_836.
    CONCATENATE 'SES_' lv_demo_date_836 '_' lv_demo_time_836 INTO lv_sess.
  ENDIF.

  "Persist the exact TCODE/Profile/Version ownership before any staging row
  "is emitted. For ACTIVE/TESTING this freezes Script/Hash; for onboarding
  "DRAFT/MAPPED it saves the non-executable preview owner. Without this,
  "the later source-log/session-summary write can create a blank session row
  "and VERIFY_LOADED_CTX correctly rejects the otherwise parsed upload.
  CLEAR: lv_ctx_ok_ingest, lv_ctx_msg_ingest.
  PERFORM freeze_session_contract
    USING    lv_sess
    CHANGING lv_ctx_ok_ingest lv_ctx_msg_ingest.
  IF lv_ctx_ok_ingest <> abap_true.
    gv_ingest_error_msg = lv_ctx_msg_ingest.
    IF gv_ingest_error_msg IS INITIAL.
      DATA(lv_zm821_2643_1) = |{ lv_sess }|.
      MESSAGE ID 'ZBDC' TYPE 'S' NUMBER '821'
        WITH lv_zm821_2643_1 INTO gv_ingest_error_msg.
    ENDIF.
    PERFORM userize_ui_message USING gv_ingest_error_msg CHANGING gv_ui_message.
    MESSAGE gv_ui_message TYPE 'S' DISPLAY LIKE 'E'.
    RETURN.
  ENDIF.

  CLEAR: lv_idx, lv_added.
  REFRESH: lt_preview_cache_local, lt_preview_hdr_local.

  "Preview Data is the uploaded file itself. Freeze the exact header order
  "that was parsed from this file; do not reconstruct it from Mapping later.
  LOOP AT lt_headers INTO lv_preview_header.
    IF sy-tabix > 25.
      DATA(lv_zm822_2657_1) = |{ lv_header_cols }|.
      MESSAGE ID 'ZBDC' TYPE 'S' NUMBER '822'
        WITH lv_zm822_2657_1 INTO gv_ingest_error_msg.
      PERFORM userize_ui_message USING gv_ingest_error_msg CHANGING gv_ui_message.
      MESSAGE gv_ui_message TYPE 'S' DISPLAY LIKE 'E'.
      RETURN.
    ENDIF.

    CLEAR ls_preview_hdr.
    ls_preview_hdr-session_id = lv_sess.
    ls_preview_hdr-col_no     = sy-tabix.
    ls_preview_hdr-header_text = lv_preview_header.
    APPEND ls_preview_hdr TO lt_preview_hdr_local.
  ENDLOOP.

 " 8. Parse data rows and map source columns into ZBDC_STAGING_BUP fields

  LOOP AT pt_raw INTO DATA(lv_line).

    lv_raw_line_idx = sy-tabix.

    IF lv_raw_line_idx <= lv_header_idx.
      CONTINUE.
    ENDIF.

    IF lv_line IS INITIAL.
      CONTINUE.
    ENDIF.

    IF lv_line CP '#*'.
      CONTINUE.
    ENDIF.

    REFRESH lt_col.

    CLEAR: lv_csv_ok, lv_csv_msg.
    PERFORM check_csv_line
      USING    lv_line
      CHANGING lv_csv_ok lv_csv_msg.
    IF lv_csv_ok <> abap_true.
      DATA(lv_zm823_2695_1) = |{ lv_raw_line_idx }|.
      DATA(lv_zm823_2695_2) = |{ lv_csv_msg }|.
      MESSAGE ID 'ZBDC' TYPE 'S' NUMBER '823'
        WITH lv_zm823_2695_1 lv_zm823_2695_2 INTO gv_ingest_error_msg.
      lv_trim_idx = lines( gt_staging ).
      WHILE lv_trim_idx > lv_initial_staging.
        DELETE gt_staging INDEX lv_trim_idx.
        lv_trim_idx = lv_trim_idx - 1.
      ENDWHILE.
      PERFORM userize_ui_message USING gv_ingest_error_msg CHANGING gv_ui_message.
      MESSAGE gv_ui_message TYPE 'S' DISPLAY LIKE 'E'.
      RETURN.
    ENDIF.

    PERFORM split_csv_line_by_delim
      USING    lv_line lv_delim
      CHANGING lt_col.

 "Skip lines that cannot be split
    IF lt_col IS INITIAL.
      CONTINUE.
    ENDIF.

 "fail closed on data placed outside the emitted header schema.
 "This catches shifted Excel/CSV rows such as a value in an unheaded
 "column instead of silently ignoring it and staging the wrong fields.
    lv_data_cols = lines( lt_col ).
    IF lv_data_cols > lv_header_cols.
      lv_extra_idx = lv_header_cols + 1.
      WHILE lv_extra_idx <= lv_data_cols.
        CLEAR lv_extra_val.
        READ TABLE lt_col INTO lv_extra_val INDEX lv_extra_idx.
        IF sy-subrc = 0.
          CONDENSE lv_extra_val.
          IF lv_extra_val IS NOT INITIAL.
            DATA(lv_zm824_2727_1) = |{ lv_raw_line_idx }|.
            DATA(lv_zm824_2727_2) = |{ lv_extra_val }|.
            DATA(lv_zm824_2727_3) = |{ lv_extra_idx }|.
            DATA(lv_zm824_2727_4) = |{ lv_header_cols }|.
            MESSAGE ID 'ZBDC' TYPE 'S' NUMBER '824'
              WITH lv_zm824_2727_1 lv_zm824_2727_2 lv_zm824_2727_3 lv_zm824_2727_4
              INTO gv_ingest_error_msg.
            lv_trim_idx = lines( gt_staging ).
            WHILE lv_trim_idx > lv_initial_staging.
              DELETE gt_staging INDEX lv_trim_idx.
              lv_trim_idx = lv_trim_idx - 1.
            ENDWHILE.
            PERFORM userize_ui_message USING gv_ingest_error_msg CHANGING gv_ui_message.
            MESSAGE gv_ui_message TYPE 'S' DISPLAY LIKE 'E'.
            RETURN.
          ENDIF.
        ENDIF.
        lv_extra_idx = lv_extra_idx + 1.
      ENDWHILE.
    ENDIF.

    LOOP AT lt_col_idx INTO ls_col_idx WHERE col_name IS INITIAL.
      CLEAR lv_extra_val.
      READ TABLE lt_col INTO lv_extra_val INDEX ls_col_idx-col_no.
      IF sy-subrc = 0.
        CONDENSE lv_extra_val.
        IF lv_extra_val IS NOT INITIAL.
          DATA(lv_zm825_2748_1) = |{ lv_raw_line_idx }|.
          DATA(lv_zm825_2748_2) = |{ lv_extra_val }|.
          DATA(lv_zm825_2748_3) = |{ ls_col_idx-col_no }|.
          MESSAGE ID 'ZBDC' TYPE 'S' NUMBER '825'
            WITH lv_zm825_2748_1 lv_zm825_2748_2 lv_zm825_2748_3
            INTO gv_ingest_error_msg.
          lv_trim_idx = lines( gt_staging ).
          WHILE lv_trim_idx > lv_initial_staging.
            DELETE gt_staging INDEX lv_trim_idx.
            lv_trim_idx = lv_trim_idx - 1.
          ENDWHILE.
          PERFORM userize_ui_message USING gv_ingest_error_msg CHANGING gv_ui_message.
          MESSAGE gv_ui_message TYPE 'S' DISPLAY LIKE 'E'.
          RETURN.
        ENDIF.
      ENDIF.
    ENDLOOP.

    lv_idx = lv_idx + 1.

    "Every source row owns a fresh staging/preview work area.  Without this
    "reset, ERROR/status/control residue from row N can leak into row N+1 and
    "make Preview/Staging look as if fields or row state were carried over.
    CLEAR: ls_stg, ls_preview_cache.

    "Build Preview directly from the parsed file row, column 1 -> COL01,
    "column 2 -> COL02, etc. Mapping/staging is intentionally NOT involved.
    "This guarantees that Preview Data shows every uploaded file column in
    "the exact uploaded header order, including blank cells.
    DO lv_header_cols TIMES.
      lv_preview_file_col = sy-index.
      IF lv_preview_file_col > 25.
        EXIT.
      ENDIF.

      CLEAR lv_preview_value.
      READ TABLE lt_col INTO lv_preview_value INDEX lv_preview_file_col.
      IF sy-subrc <> 0.
        CLEAR lv_preview_value.
      ENDIF.

      lv_preview_nr = lv_preview_file_col.
      CONCATENATE 'COL' lv_preview_nr INTO lv_preview_col.
      ASSIGN COMPONENT lv_preview_col
        OF STRUCTURE ls_preview_cache-preview_row TO <pv>.
      IF sy-subrc <> 0 OR <pv> IS NOT ASSIGNED.
        DATA(lv_zm826_2789_1) = |{ lv_preview_col }|.
        MESSAGE ID 'ZBDC' TYPE 'S' NUMBER '826'
          WITH lv_zm826_2789_1 INTO gv_ingest_error_msg.
        lv_trim_idx = lines( gt_staging ).
        WHILE lv_trim_idx > lv_initial_staging.
          DELETE gt_staging INDEX lv_trim_idx.
          lv_trim_idx = lv_trim_idx - 1.
        ENDWHILE.
        PERFORM userize_ui_message USING gv_ingest_error_msg CHANGING gv_ui_message.
        MESSAGE gv_ui_message TYPE 'S' DISPLAY LIKE 'E'.
        RETURN.
      ENDIF.
      <pv> = lv_preview_value.
      UNASSIGN <pv>.
    ENDDO.

    LOOP AT lt_map INTO ls_map.

      CLEAR: lv_src, lv_val, lv_colno.

      lv_src = ls_map-source_column.
      TRANSLATE lv_src TO UPPER CASE.
      CONDENSE lv_src NO-GAPS.
      REPLACE ALL OCCURRENCES OF '*' IN lv_src WITH ''.
      REPLACE ALL OCCURRENCES OF '"' IN lv_src WITH ''.

      READ TABLE lt_col_idx INTO ls_col_idx WITH KEY col_name = lv_src.

      IF sy-subrc <> 0.
        lv_val = ''.
      ELSE.
        lv_colno = ls_col_idx-col_no.
        READ TABLE lt_col INTO lv_val INDEX lv_colno.
        IF sy-subrc <> 0.
          lv_val = ''.
        ENDIF.
      ENDIF.

      "Preserve the exact source value. Blank eligibility is evaluated only
      "after the complete Business Group is available.

      "Executable staging must never lose a generated-template value silently.
      ASSIGN COMPONENT ls_map-staging_field OF STRUCTURE ls_stg TO <fv>.
      IF sy-subrc <> 0 OR <fv> IS NOT ASSIGNED.
        DATA(lv_zm827_2831_1) = |{ ls_map-source_column }|.
        DATA(lv_zm827_2831_2) = |{ ls_map-staging_field }|.
        MESSAGE ID 'ZBDC' TYPE 'S' NUMBER '827'
          WITH lv_zm827_2831_1 lv_zm827_2831_2 INTO gv_ingest_error_msg.
        lv_trim_idx = lines( gt_staging ).
        WHILE lv_trim_idx > lv_initial_staging.
          DELETE gt_staging INDEX lv_trim_idx.
          lv_trim_idx = lv_trim_idx - 1.
        ENDWHILE.
        PERFORM userize_ui_message USING gv_ingest_error_msg CHANGING gv_ui_message.
        MESSAGE gv_ui_message TYPE 'S' DISPLAY LIKE 'E'.
        RETURN.
      ENDIF.

      <fv> = lv_val.
      lv_staged_check = <fv>.
      IF lv_staged_check <> lv_val.
        DATA(lv_zm828_2845_1) = |{ ls_map-source_column }|.
        DATA(lv_zm828_2845_2) = |{ ls_map-staging_field }|.
        MESSAGE ID 'ZBDC' TYPE 'S' NUMBER '828'
          WITH lv_zm828_2845_1 lv_zm828_2845_2 INTO gv_ingest_error_msg.
        lv_trim_idx = lines( gt_staging ).
        WHILE lv_trim_idx > lv_initial_staging.
          DELETE gt_staging INDEX lv_trim_idx.
          lv_trim_idx = lv_trim_idx - 1.
        ENDWHILE.
        PERFORM userize_ui_message USING gv_ingest_error_msg CHANGING gv_ui_message.
        MESSAGE gv_ui_message TYPE 'S' DISPLAY LIKE 'E'.
        RETURN.
      ENDIF.

      "Preview was already copied directly from LT_COL above. This Mapping loop
      "is execution/staging only; it must never alter what Preview Data shows.
      UNASSIGN <fv>.
    ENDLOOP.

    "Second-pass row proof after ALL assignments. Immediate assignment checks
    "cannot detect a later source overwriting an earlier FIELDxx. Re-read every
    "source cell and prove that the final staging row still contains exactly
    "that value before the row can enter GT_STAGING/ZBDC_STAGING_BUP.
    LOOP AT lt_map INTO ls_map.
      CLEAR: lv_src, lv_colno, lv_expected_check, lv_actual_check.
      lv_src = ls_map-source_column.
      TRANSLATE lv_src TO UPPER CASE.
      CONDENSE lv_src NO-GAPS.
      REPLACE ALL OCCURRENCES OF '*' IN lv_src WITH ''.
      REPLACE ALL OCCURRENCES OF '"' IN lv_src WITH ''.

      READ TABLE lt_col_idx INTO ls_col_idx WITH KEY col_name = lv_src.
      IF sy-subrc = 0.
        lv_colno = ls_col_idx-col_no.
        READ TABLE lt_col INTO lv_expected_check INDEX lv_colno.
        IF sy-subrc <> 0.
          CLEAR lv_expected_check.
        ENDIF.
      ENDIF.

      UNASSIGN <fv>.
      ASSIGN COMPONENT ls_map-staging_field OF STRUCTURE ls_stg TO <fv>.
      IF sy-subrc <> 0 OR <fv> IS NOT ASSIGNED.
        DATA(lv_zm829_2885_1) = |{ ls_map-source_column }|.
        DATA(lv_zm829_2885_2) = |{ ls_map-staging_field }|.
        MESSAGE ID 'ZBDC' TYPE 'S' NUMBER '829'
          WITH lv_zm829_2885_1 lv_zm829_2885_2 INTO gv_ingest_error_msg.
      ELSE.
        lv_actual_check = <fv>.
        IF lv_actual_check <> lv_expected_check.
          DATA(lv_zm830_2890_1) = |{ ls_map-source_column }|.
          DATA(lv_zm830_2890_2) = |{ ls_map-staging_field }|.
          DATA(lv_zm830_2890_3) = |{ lv_raw_line_idx }|.
          MESSAGE ID 'ZBDC' TYPE 'S' NUMBER '830'
            WITH lv_zm830_2890_1 lv_zm830_2890_2 lv_zm830_2890_3
            INTO gv_ingest_error_msg.
        ENDIF.
      ENDIF.
      UNASSIGN <fv>.

      IF gv_ingest_error_msg IS NOT INITIAL.
        lv_trim_idx = lines( gt_staging ).
        WHILE lv_trim_idx > lv_initial_staging.
          DELETE gt_staging INDEX lv_trim_idx.
          lv_trim_idx = lv_trim_idx - 1.
        ENDWHILE.
        PERFORM userize_ui_message USING gv_ingest_error_msg CHANGING gv_ui_message.
        MESSAGE gv_ui_message TYPE 'S' DISPLAY LIKE 'E'.
        RETURN.
      ENDIF.
    ENDLOOP.

    ls_stg-session_id = lv_sess.
    ls_stg-row_index  = lv_idx.
    ls_stg-record_key = ls_stg-field01.
    ls_stg-tcode      = p_transaction.

    IF ls_stg-status IS INITIAL.
      ls_stg-status = 'STAGED'.
    ENDIF.

    ls_preview_cache-session_id = lv_sess.
    ls_preview_cache-row_index  = lv_idx.
    ls_preview_cache-preview_row-tx_code      = p_transaction.
    ls_preview_cache-preview_row-excel_row    = lv_idx.
    ls_preview_cache-preview_row-business_key = ls_stg-record_key.
    APPEND ls_preview_cache TO lt_preview_cache_local.

    APPEND ls_stg TO gt_staging.
    lv_added = lv_added + 1.

  ENDLOOP.

 " 9. No data rows after header

  IF lv_added = 0.
    DATA(lv_zm831_2931_1) = |{ lv_header_ln }|.
    MESSAGE ID 'ZBDC' TYPE 'S' NUMBER '831'
      WITH lv_zm831_2931_1 INTO gv_ingest_error_msg.
    PERFORM userize_ui_message USING gv_ingest_error_msg CHANGING gv_ui_message.
    MESSAGE gv_ui_message TYPE 'S' DISPLAY LIKE 'W'.
    RETURN.
  ENDIF.

 " 10. Strict actual-data contract gate before successful ingest publish

  REFRESH lt_contract_scope.
  LOOP AT gt_staging INTO ls_contract_db WHERE session_id = lv_sess.
    CLEAR ls_contract_row.
    MOVE-CORRESPONDING ls_contract_db TO ls_contract_row.
    APPEND ls_contract_row TO lt_contract_scope.
  ENDLOOP.

  CLEAR: lv_contract_ok, lv_contract_msg.
  PERFORM check_blank_contract_scope
    USING    lt_contract_scope
    CHANGING lv_contract_ok lv_contract_msg.
  IF lv_contract_ok <> abap_true.
    gv_ingest_error_msg = lv_contract_msg.
    lv_trim_idx = lines( gt_staging ).
    WHILE lv_trim_idx > lv_initial_staging.
      DELETE gt_staging INDEX lv_trim_idx.
      lv_trim_idx = lv_trim_idx - 1.
    ENDWHILE.
    PERFORM userize_ui_message USING gv_ingest_error_msg CHANGING gv_ui_message.
    MESSAGE gv_ui_message TYPE 'S' DISPLAY LIKE 'E'.
    RETURN.
  ENDIF.

  LOOP AT gt_staging INTO ls_contract_db WHERE session_id = lv_sess.
    CLEAR: lv_snapshot_ok, lv_snapshot_msg.
    PERFORM persist_ingest_snapshot
      USING    ls_contract_db lt_map
      CHANGING lv_snapshot_ok lv_snapshot_msg.
    IF lv_snapshot_ok <> abap_true.
      gv_ingest_error_msg = lv_snapshot_msg.
      PERFORM cleanup_ingest_snapshots USING lv_sess.
      lv_trim_idx = lines( gt_staging ).
      WHILE lv_trim_idx > lv_initial_staging.
        DELETE gt_staging INDEX lv_trim_idx.
        lv_trim_idx = lv_trim_idx - 1.
      ENDWHILE.
      PERFORM userize_ui_message USING gv_ingest_error_msg CHANGING gv_ui_message.
      MESSAGE gv_ui_message TYPE 'S' DISPLAY LIKE 'E'.
      RETURN.
    ENDIF.
  ENDLOOP.

 " 11. Update row counters

  "Publish Preview only after the whole unit passed parsing and actual-data
  "contract proof.
  "A failed row therefore cannot leave a partial/fake Preview Data snapshot.
  DELETE gt_preview_src_cache WHERE session_id = lv_sess.
  APPEND LINES OF lt_preview_cache_local TO gt_preview_src_cache.
  DELETE gt_preview_hdr_cache WHERE session_id = lv_sess.
  APPEND LINES OF lt_preview_hdr_local TO gt_preview_hdr_cache.

  lv_rowcount = lines( gt_staging ).

  WRITE lv_rowcount TO txtp_row_count LEFT-JUSTIFIED.

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

 " 11. Return parsed rows to the inbound command owner

 "The parser does not persist or commit. Local/Drive/Gmail/REST
 "adapters own one ingestion LUW that includes staging, provenance,
 "frozen session context and summary.
  CLEAR gv_ingest_error_msg.

ENDFORM.


FORM JSON_GET_BUP USING IV_OBJ TYPE STRING IV_KEY TYPE CSEQUENCE CHANGING CV_VAL TYPE STRING.
  DATA: LV_KEY_TEXT    TYPE STRING,
        LV_KEY_PATTERN TYPE STRING,
        LV_POS         TYPE I,
        LV_COLON       TYPE I,
        LV_SCAN        TYPE I,
        LV_START       TYPE I,
        LV_LEN         TYPE I,
        LV_TAIL        TYPE STRING,
        LV_CHAR        TYPE C LENGTH 1.

  CLEAR CV_VAL.

 "CSEQUENCE accepts both fixed-length DDIC CHAR fields and STRING values.
 "Convert once so the remaining JSON parser works with one concrete type.
  LV_KEY_TEXT = IV_KEY.

 "Manual key/value extraction to avoid deprecated POSIX regex warnings.
 "Supports flat JSON values like: " && '"' && "vendor" && '"' && ":" && '"' && "5000001" && '"' && " or quantity:10.
  LV_KEY_PATTERN = '"' && LV_KEY_TEXT && '"'.

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

*& Detect one delimiter from the real header and reuse it for
*& every row. Supports comma, semicolon and horizontal TAB while ignoring
*& separators inside quoted CSV values.

*& Fail closed on an unterminated quoted CSV field.
*& Escaped quotes are represented by two consecutive quote characters.

FORM check_csv_line
  USING    iv_line    TYPE string
  CHANGING cv_ok      TYPE abap_bool
           cv_message TYPE string.

  DATA: lv_pos      TYPE i,
        lv_len      TYPE i,
        lv_next_pos TYPE i,
        lv_char     TYPE c LENGTH 1,
        lv_next     TYPE c LENGTH 1,
        lv_in_quote TYPE abap_bool.

  CLEAR: cv_ok, cv_message.
  lv_len = strlen( iv_line ).

  WHILE lv_pos < lv_len.
    lv_char = iv_line+lv_pos(1).
    IF lv_char = '"'.
      IF lv_in_quote = abap_true AND lv_pos + 1 < lv_len.
        lv_next_pos = lv_pos + 1.
        lv_next = iv_line+lv_next_pos(1).
        IF lv_next = '"'.
          lv_pos = lv_pos + 2.
          CONTINUE.
        ENDIF.
      ENDIF.

      IF lv_in_quote = abap_true.
        lv_in_quote = abap_false.
      ELSE.
        lv_in_quote = abap_true.
      ENDIF.
    ENDIF.
    lv_pos = lv_pos + 1.
  ENDWHILE.

  IF lv_in_quote = abap_true.
    cv_message = 'Quoted CSV field is not terminated on the same physical line.'.
    RETURN.
  ENDIF.

  cv_ok = abap_true.
ENDFORM.

FORM detect_csv_delimiter
  USING    iv_line  TYPE string
  CHANGING cv_delim TYPE c.

  DATA: lv_pos       TYPE i,
        lv_len       TYPE i,
        lv_next_pos  TYPE i,
        lv_char      TYPE c LENGTH 1,
        lv_next      TYPE c LENGTH 1,
        lv_tab       TYPE c LENGTH 1,
        lv_in_quote  TYPE abap_bool,
        lv_comma_cnt TYPE i,
        lv_semi_cnt  TYPE i,
        lv_tab_cnt   TYPE i.

  CLEAR cv_delim.
  lv_tab = cl_abap_char_utilities=>horizontal_tab.
  lv_len = strlen( iv_line ).

  WHILE lv_pos < lv_len.
    lv_char = iv_line+lv_pos(1).

    IF lv_char = '"'.
      IF lv_in_quote = abap_true AND lv_pos + 1 < lv_len.
        lv_next_pos = lv_pos + 1.
        lv_next = iv_line+lv_next_pos(1).
        IF lv_next = '"'.
          lv_pos = lv_pos + 2.
          CONTINUE.
        ENDIF.
      ENDIF.

      IF lv_in_quote = abap_true.
        lv_in_quote = abap_false.
      ELSE.
        lv_in_quote = abap_true.
      ENDIF.

    ELSEIF lv_in_quote = abap_false.
      IF lv_char = ','.
        lv_comma_cnt = lv_comma_cnt + 1.
      ELSEIF lv_char = ';'.
        lv_semi_cnt = lv_semi_cnt + 1.
      ELSEIF lv_char = lv_tab.
        lv_tab_cnt = lv_tab_cnt + 1.
      ENDIF.
    ENDIF.

    lv_pos = lv_pos + 1.
  ENDWHILE.

 "Deterministic tie order keeps the generated comma template unchanged.
  cv_delim = ','.
  IF lv_semi_cnt > lv_comma_cnt AND lv_semi_cnt >= lv_tab_cnt.
    cv_delim = ';'.
  ELSEIF lv_tab_cnt > lv_comma_cnt AND lv_tab_cnt > lv_semi_cnt.
    cv_delim = lv_tab.
  ENDIF.
ENDFORM.

FORM split_csv_line_by_delim
  USING    iv_line  TYPE string
           iv_delim TYPE c
  CHANGING ct_cols  TYPE string_table.

  DATA: lv_pos       TYPE i,
        lv_len       TYPE i,
        lv_char      TYPE c LENGTH 1,
        lv_next      TYPE c LENGTH 1,
        lv_cell      TYPE string,
        lv_in_quote  TYPE abap_bool,
        lv_next_pos  TYPE i,
        lv_delim     TYPE c LENGTH 1.

  REFRESH ct_cols.
  lv_delim = iv_delim.
  IF lv_delim IS INITIAL.
    lv_delim = ','.
  ENDIF.

  lv_len = strlen( iv_line ).

  WHILE lv_pos < lv_len.
    lv_char = iv_line+lv_pos(1).

    IF lv_char = '"'.
      IF lv_in_quote = abap_true AND lv_pos + 1 < lv_len.
        lv_next_pos = lv_pos + 1.
        lv_next = iv_line+lv_next_pos(1).
        IF lv_next = '"'.
          lv_cell = lv_cell && '"'.
          lv_pos = lv_pos + 2.
          CONTINUE.
        ENDIF.
      ENDIF.

      IF lv_in_quote = abap_true.
        lv_in_quote = abap_false.
      ELSE.
        lv_in_quote = abap_true.
      ENDIF.

    ELSEIF lv_char = lv_delim AND lv_in_quote = abap_false.
      APPEND lv_cell TO ct_cols.
      CLEAR lv_cell.
    ELSE.
      lv_cell = lv_cell && lv_char.
    ENDIF.

    lv_pos = lv_pos + 1.
  ENDWHILE.

  APPEND lv_cell TO ct_cols.
ENDFORM.

"Compatibility wrapper for profile-signature/header helpers outside
"PROCESS_CSV_ROWS. It detects the delimiter independently from that line.
FORM split_csv_line
  USING    iv_line TYPE string
  CHANGING ct_cols TYPE string_table.

  DATA lv_delim TYPE c LENGTH 1.

  PERFORM detect_csv_delimiter
    USING    iv_line
    CHANGING lv_delim.
  PERFORM split_csv_line_by_delim
    USING    iv_line lv_delim
    CHANGING ct_cols.
ENDFORM.

*& Read one KEY=VALUE token from persisted __SOURCE__ ingestion evidence.
FORM p1_source_msg_token
  USING    iv_message TYPE csequence
           iv_key     TYPE csequence
  CHANGING cv_value   TYPE string.
  DATA: lt_part   TYPE string_table,
        lv_part   TYPE string,
        lv_prefix TYPE string,
        lv_off    TYPE i.

  CLEAR cv_value.
  lv_prefix = |{ iv_key }=|.
  SPLIT iv_message AT ';' INTO TABLE lt_part.
  LOOP AT lt_part INTO lv_part.
    SHIFT lv_part LEFT DELETING LEADING space.
    IF lv_part CP |{ lv_prefix }*|.
      lv_off = strlen( lv_prefix ).
      IF strlen( lv_part ) >= lv_off.
        cv_value = lv_part+lv_off.
        CONDENSE cv_value.
      ENDIF.
      RETURN.
    ENDIF.
  ENDLOOP.
ENDFORM.

FORM prepare_preview_file.
  TYPES: BEGIN OF ty_file_sid_hist,
           session_id TYPE zbdc_file_lg_bup-session_id,
         END OF ty_file_sid_hist,
         BEGIN OF ty_sess_sid_hist,
           session_id TYPE zbdc_session_bup-session_id,
         END OF ty_sess_sid_hist,
         BEGIN OF ty_owner_hist,
           session_id TYPE zbdc_file_lg_bup-session_id,
           created_by TYPE zbdc_session_bup-created_by,
         END OF ty_owner_hist,
         BEGIN OF ty_size_hist,
           session_id TYPE zbdc_result_bup-session_id,
           message    TYPE zbdc_result_bup-message,
           created_at TYPE zbdc_result_bup-created_at,
         END OF ty_size_hist,
         BEGIN OF ty_source_hist,
           session_id TYPE zbdc_result_bup-session_id,
           tcode      TYPE zbdc_result_bup-tcode,
           message    TYPE zbdc_result_bup-message,
           created_at TYPE zbdc_result_bup-created_at,
         END OF ty_source_hist.

  DATA: ls_meta       TYPE ty_files_disp,
        lv_date       TYPE sy-datum,
        lv_time       TYPE sy-uzeit,
        lv_user       TYPE sy-uname,
        lv_cnt        TYPE i,
        lv_file_title TYPE string,
        lv_source_txt TYPE char20,
        lv_owned      TYPE abap_bool,
        lv_source_msg TYPE string,
        lv_size_text  TYPE string,
        lv_size_check TYPE string,
        lv_size_tail  TYPE string,
        lv_src_file   TYPE string,
        lv_src_source TYPE string,
        lv_src_user   TYPE string,
        lv_src_tcode  TYPE string,
        lv_src_reject TYPE string,
        lv_src_skip   TYPE string,
        lv_stg_error  TYPE zbdc_staging_bup-error_msg,
        lv_stg_tcode  TYPE zbdc_staging_bup-tcode,
        ls_seen_sid   TYPE ty_sess_sid_hist.

  DATA: lt_file_lg    TYPE STANDARD TABLE OF zbdc_file_lg_bup,
        lt_my_sid     TYPE SORTED TABLE OF ty_file_sid_hist
                      WITH UNIQUE KEY session_id,
        lt_lookup_sid TYPE SORTED TABLE OF ty_sess_sid_hist
                      WITH UNIQUE KEY session_id,
        lt_owner_raw  TYPE STANDARD TABLE OF zbdc_session_bup,
        lt_owner      TYPE HASHED TABLE OF ty_owner_hist
                      WITH UNIQUE KEY session_id,
        lt_size_log   TYPE STANDARD TABLE OF ty_size_hist,
        lt_source_log TYPE STANDARD TABLE OF ty_source_hist,
        lt_seen_sid   TYPE SORTED TABLE OF ty_sess_sid_hist
                      WITH UNIQUE KEY session_id.

  REFRESH gt_files_preview.
  IF gv_file_scope IS INITIAL.
    gv_file_scope = gc_file_scope_my.
  ENDIF.

 "Preview Files is a read-only history projection. It must not scan the
 "whole session table or touch frontend files for size while the user is only
 "switching tabs. My Uploads reads all owned sessions plus the current
 "not-yet-summarized session; All Uploads reads the complete file-log history.
  IF gv_file_scope = gc_file_scope_my.
    SELECT session_id created_by
      FROM zbdc_session_bup
      INTO CORRESPONDING FIELDS OF TABLE lt_owner_raw
      WHERE created_by = sy-uname.

    LOOP AT lt_owner_raw INTO DATA(ls_my_owner).
      INSERT VALUE #( session_id = ls_my_owner-session_id )
        INTO TABLE lt_my_sid.
    ENDLOOP.

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
      INTO TABLE @lt_file_lg.
  ENDIF.

  SORT lt_file_lg BY processed_at DESCENDING file_name ASCENDING.

  "Every press of Ingest is also persisted as an exact __SOURCE__ result row.
  "Use that event stream as a safety net for Preview Files. This is important
  "when ZBDC_FILE_LG_BUP cannot store another row for identical content/hash:
  "the new upload attempt must still remain visible instead of disappearing.
  SELECT session_id, tcode, message, created_at
    FROM zbdc_result_bup
    INTO CORRESPONDING FIELDS OF TABLE @lt_source_log
    WHERE record_key = '__SOURCE__'.
  SORT lt_source_log BY session_id created_at DESCENDING.
  DELETE ADJACENT DUPLICATES FROM lt_source_log COMPARING session_id.

 "No artificial row cap: Preview Files shows the complete selected history.

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
      DATA ls_owner_conv TYPE ty_owner_hist.
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
    IF ls_file_lg-session_id IS NOT INITIAL.
      CLEAR ls_seen_sid.
      ls_seen_sid-session_id = ls_file_lg-session_id.
      INSERT ls_seen_sid INTO TABLE lt_seen_sid.
    ENDIF.

    ls_meta-file_name  = ls_file_lg-file_name.
    ls_meta-channel    = ls_file_lg-source.
    ls_meta-session_id = ls_file_lg-session_id.
    ls_meta-raw_status = ls_file_lg-status.
    ls_meta-raw_error  = ls_file_lg-error_msg.

    PERFORM batch_prefix_from_sid
      USING    ls_file_lg-session_id
      CHANGING ls_meta-batch_key.

    PERFORM p1_split_unit_name
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

 "Do not call frontend FILE_GET_SIZE for history rows. Preview Files may
 "contain old local paths or remote pseudo-URIs; probing them on every tab
 "switch makes SAP GUI appear to spin. Use persisted size evidence only.

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
      PERFORM extract_file_title_parse
        USING    ls_file_lg-file_name
        CHANGING ls_meta-file_title.
    ENDIF.

    CASE ls_file_lg-source.
      WHEN 'LOCAL' OR 'LOCAL_INGESTION'.
        lv_source_txt = 'My Computer'.
      WHEN 'GDRIVE' OR 'GDRIVE_INGESTION'.
        lv_source_txt = 'Google Drive'.
      WHEN 'REST' OR 'REST_INGESTION'.
        lv_source_txt = 'REST API'.
      WHEN 'EMAIL' OR 'EMAIL_INGESTION'.
        lv_source_txt = 'Email Inbox'.
      WHEN 'GMAIL' OR 'GMAIL_FORM'.
        lv_source_txt = 'Gmail Form'.
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
        lv_owned = abap_true.
      ELSEIF gv_file_scope = gc_file_scope_my.
 "Older file-log rows may not have a matching session owner record.
 "Preview Files is read-only, so keep them visible in My Uploads
 "instead of showing an empty history because owner evidence is absent.
        lv_user = sy-uname.
        lv_owned = abap_true.
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

    "Preview Files answers one simple ingestion question: was this selected
    "source accepted into staging or rejected? Keep the raw DB lifecycle in
    "RAW_STATUS for audit, but render an unambiguous user-facing result.
    CASE ls_file_lg-status.
      WHEN 'IMPORTED' OR 'UPLOADED' OR 'READY' OR 'SUCCESS'.
        ls_meta-status_text = 'ACCEPTED'.
        ls_meta-status_icon = icon_green_light.
        IF lv_cnt > 0.
          ls_meta-next_action = 'Double-click to preview'.
        ELSE.
          ls_meta-next_action = 'Accepted; no data rows'.
        ENDIF.
      WHEN 'ERROR' OR 'FAILED'.
        ls_meta-status_text = 'REJECTED'.
        ls_meta-status_icon = icon_red_light.
        ls_meta-next_action = 'Review rejection reason'.
      WHEN 'SKIPPED'.
        ls_meta-status_text = 'SKIPPED'.
        ls_meta-status_icon = icon_yellow_light.
        ls_meta-next_action = 'Review skip reason'.
      WHEN 'WARNING' OR 'PARTIAL'.
        ls_meta-status_text = 'REVIEW'.
        ls_meta-status_icon = icon_yellow_light.
        ls_meta-next_action = 'Review data then validate'.
      WHEN 'PROCESSING' OR 'SM35QUEUE'.
        ls_meta-status_text = 'PROCESSING'.
        ls_meta-status_icon = icon_yellow_light.
        ls_meta-next_action = 'Monitor current processing'.
      WHEN OTHERS.
        IF ls_file_lg-status IS INITIAL.
          ls_meta-status_text = 'ACCEPTED'.
          ls_meta-status_icon = icon_green_light.
          ls_meta-next_action = 'Review imported source'.
        ELSE.
          ls_meta-status_text = ls_file_lg-status.
          ls_meta-status_icon = icon_yellow_light.
          ls_meta-next_action = 'Review file/source'.
        ENDIF.
    ENDCASE.

    APPEND ls_meta TO gt_files_preview.
  ENDLOOP.

  "Append ingestion attempts that have exact __SOURCE__ evidence but no visible
  "file-log row for that SESSION_ID. This makes identical-content retries and
  "early parser rejections auditable in both My Uploads and All Uploads.
  LOOP AT lt_source_log INTO DATA(ls_source_hist).
    CLEAR ls_seen_sid.
    ls_seen_sid-session_id = ls_source_hist-session_id.
    READ TABLE lt_seen_sid WITH TABLE KEY session_id = ls_seen_sid-session_id
      TRANSPORTING NO FIELDS.
    IF sy-subrc = 0.
      CONTINUE.
    ENDIF.

    CLEAR: ls_meta, lv_date, lv_time, lv_user, lv_cnt, lv_owned,
           lv_src_file, lv_src_source, lv_src_user, lv_src_tcode,
           lv_src_reject, lv_src_skip, lv_stg_error, lv_stg_tcode,
           lv_size_text, lv_source_txt.

    PERFORM p1_source_msg_token USING ls_source_hist-message 'FILE' CHANGING lv_src_file.
    PERFORM p1_source_msg_token USING ls_source_hist-message 'INBOUND_SOURCE' CHANGING lv_src_source.
    PERFORM p1_source_msg_token USING ls_source_hist-message 'USER' CHANGING lv_src_user.
    PERFORM p1_source_msg_token USING ls_source_hist-message 'TCODE' CHANGING lv_src_tcode.
    PERFORM p1_source_msg_token USING ls_source_hist-message 'SIZE' CHANGING lv_size_text.
    PERFORM p1_source_msg_token USING ls_source_hist-message 'REJECTED' CHANGING lv_src_reject.
    PERFORM p1_source_msg_token USING ls_source_hist-message 'SKIPPED' CHANGING lv_src_skip.

    IF gv_file_scope = gc_file_scope_my.
      IF lv_src_user = sy-uname.
        lv_owned = abap_true.
      ELSE.
        READ TABLE lt_my_sid WITH TABLE KEY session_id = ls_source_hist-session_id
          TRANSPORTING NO FIELDS.
        IF sy-subrc = 0.
          lv_owned = abap_true.
        ENDIF.
      ENDIF.
      IF lv_owned <> abap_true.
        CONTINUE.
      ENDIF.
    ENDIF.

    ls_meta-session_id = ls_source_hist-session_id.
    ls_meta-file_name  = lv_src_file.
    ls_meta-channel    = lv_src_source.
    ls_meta-username   = lv_src_user.
    ls_meta-owner      = lv_src_user.
    IF ls_meta-owner IS INITIAL.
      ls_meta-owner = 'UNKNOWN'.
    ENDIF.
    PERFORM batch_prefix_from_sid USING ls_source_hist-session_id CHANGING ls_meta-batch_key.
    PERFORM p1_split_unit_name USING lv_src_file CHANGING ls_meta-file_title ls_meta-sheet_name.
    IF ls_meta-sheet_name = 'DATA'.
      CLEAR ls_meta-sheet_name.
    ENDIF.
    ls_meta-data_unit = 'File/Sheet'.

    SELECT COUNT(*) FROM zbdc_staging_bup
      INTO @lv_cnt
      WHERE session_id = @ls_source_hist-session_id.
    ls_meta-rows_loaded = lv_cnt.

    SELECT SINGLE tcode FROM zbdc_staging_bup
      INTO @lv_stg_tcode
      WHERE session_id = @ls_source_hist-session_id.
    IF lv_src_tcode IS NOT INITIAL.
      ls_meta-tx_code = lv_src_tcode.
    ELSEIF lv_stg_tcode IS NOT INITIAL.
      ls_meta-tx_code = lv_stg_tcode.
    ELSE.
      ls_meta-tx_code = ls_source_hist-tcode.
    ENDIF.

    IF lv_size_text IS INITIAL.
      ls_meta-file_size = 'Unknown'.
    ELSE.
      ls_meta-file_size = lv_size_text.
    ENDIF.

    PERFORM ts_to_demo USING ls_source_hist-created_at CHANGING lv_date lv_time.
    ls_meta-upload_date = lv_date.
    ls_meta-upload_time = lv_time.
    IF lv_date IS NOT INITIAL.
      ls_meta-processed_on =
        |{ lv_date+6(2) }.{ lv_date+4(2) }.{ lv_date+0(4) } { lv_time+0(2) }:{ lv_time+2(2) }:{ lv_time+4(2) }|.
    ELSE.
      ls_meta-processed_on = '-'.
    ENDIF.

    CASE lv_src_source.
      WHEN 'LOCAL' OR 'LOCAL_INGESTION'. lv_source_txt = 'My Computer'.
      WHEN 'GDRIVE' OR 'GDRIVE_INGESTION'. lv_source_txt = 'Google Drive'.
      WHEN 'REST' OR 'REST_INGESTION'. lv_source_txt = 'REST API'.
      WHEN 'EMAIL' OR 'EMAIL_INGESTION'. lv_source_txt = 'Email Inbox'.
      WHEN 'GMAIL' OR 'GMAIL_FORM'. lv_source_txt = 'Gmail Form'.
      WHEN OTHERS. lv_source_txt = lv_src_source.
    ENDCASE.
    ls_meta-source_text = lv_source_txt.

    IF lv_src_reject IS NOT INITIAL.
      ls_meta-raw_status  = 'ERROR'.
      ls_meta-raw_error   = lv_src_reject.
      ls_meta-status_text = 'REJECTED'.
      ls_meta-status_icon = icon_red_light.
      ls_meta-next_action = 'Review rejection reason'.
    ELSEIF lv_src_skip IS NOT INITIAL.
      ls_meta-raw_status  = 'SKIPPED'.
      ls_meta-raw_error   = lv_src_skip.
      ls_meta-status_text = 'SKIPPED'.
      ls_meta-status_icon = icon_yellow_light.
      ls_meta-next_action = 'Review skip reason'.
    ELSE.
      SELECT SINGLE error_msg FROM zbdc_staging_bup
        INTO @lv_stg_error
        WHERE session_id = @ls_source_hist-session_id
          AND status = @gc_st_error.
      IF sy-subrc = 0 AND lv_stg_error IS NOT INITIAL.
        ls_meta-raw_status  = 'ERROR'.
        ls_meta-raw_error   = lv_stg_error.
        ls_meta-status_text = 'REJECTED'.
        ls_meta-status_icon = icon_red_light.
        ls_meta-next_action = 'Review rejection reason'.
      ELSE.
        ls_meta-raw_status  = 'IMPORTED'.
        ls_meta-status_text = 'ACCEPTED'.
        ls_meta-status_icon = icon_green_light.
        ls_meta-next_action = 'Double-click to preview'.
      ENDIF.
    ENDIF.

    APPEND ls_meta TO gt_files_preview.
    CLEAR ls_seen_sid.
    ls_seen_sid-session_id = ls_source_hist-session_id.
    INSERT ls_seen_sid INTO TABLE lt_seen_sid.
  ENDLOOP.

  SORT gt_files_preview BY upload_date DESCENDING upload_time DESCENDING file_name ASCENDING.
ENDFORM.


FORM 0300_after_ingest USING iv_source TYPE char20.
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
      WHEN 'READY'.
        lv_ready = lv_ready + 1.
      WHEN 'ERROR'.
        lv_error = lv_error + 1.
      WHEN 'WARNING'.
        lv_warn = lv_warn + 1.
      WHEN OTHERS.
 "Fresh upload rows can be STAGED/UPLOADED before the explicit Staging
 "validation command persists READY/ERROR. This is pending validation,
 "not a warning and not executable yet.
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
 "Bind the exact persisted session contract before building Preview Data.
 "This prevents a previous upload's Profile/Version from leaking into the
 "new file when the user switches TCODE/source quickly.
    PERFORM apply_first_staging_ctx.
    PERFORM build_preview_rows.

 "After ingest stay on Preview Data and do not queue a synthetic PREV command.
 "The next normal 0301 PBO refreshes the existing ALV from the rebuilt preview rows.
    ts_preview-activetab = 'TAB_PREVIEW'.
    IF lv_error > 0 OR lv_warn > 0.
      MESSAGE s156(zbdc)
        WITH iv_source lv_sess
        DISPLAY LIKE 'W'.
    ELSEIF lv_ready > 0.
      MESSAGE s157(zbdc)
        WITH iv_source lv_sess lv_total lv_ready.
    ELSE.
      MESSAGE s158(zbdc)
        WITH iv_source lv_sess lv_total.
    ENDIF.

    "Keep Preview Files history current immediately after a successful ingest.
    "PREPARE_PREVIEW_FILE performs a fresh DB projection for the current
    "My Uploads / All Uploads scope; it does not change the active Preview Data tab.
    PERFORM prepare_preview_file.
  ENDIF.
ENDFORM.

*& SCREEN FLOW HELPERS - connect main dashboard, upload, and staging

*& keep 0300 header counters synchronized after optional actions

FORM sync_0300_counts.
  DATA lv_total TYPE i.
  DATA lv_txt   TYPE char20.

  lv_total = lines( gt_staging ).
  WRITE lv_total TO lv_txt LEFT-JUSTIFIED.

  IF lv_total > 0.
    txtp_row_count   = lv_txt.
    txtp_row         = lv_txt.
    txtp_rows        = lv_txt.
    txtp_loaded      = lv_txt.
    txtp_loaded_rows = lv_txt.
    txtp_rows_loaded = lv_txt.
    txtgv_row_count  = lv_txt.
    txtgv_rows       = lv_txt.
    txtgv_loaded     = lv_txt.
    txtgv_total_rows = lv_txt.
    txtgv_tot_rows   = lv_txt.

    IF txtp_file_size IS INITIAL OR txtp_file_size = '0 B'.
      txtp_file_size = 'Imported'.
    ENDIF.
  ENDIF.
ENDFORM.

FORM clear_0300_runtime.
 "Fresh Upload Center: clear only runtime preview buffers, never delete persisted DB history.
  REFRESH: gt_staging, gt_preview_data, gt_files_preview, gt_current_sessions.
  CLEAR: txtp_file_path, txtp_file_size, txtp_row_count, txtp_row, txtp_rows,
         txtp_loaded, txtp_rows_loaded, txtp_loaded_rows,
         txtgv_row_count, txtgv_rows, txtgv_loaded, txtgv_total_rows, txtgv_tot_rows,
         gv_current_batch_prefix, gv_ingest_batch_prefix, gv_forced_session_id,
         gv_current_batch_count, gv_current_file_name, gv_current_sheet_name,
         gv_current_unit_src.
  ts_preview-activetab = 'TAB_PREVIEW'.
  PERFORM reset_0300_all_alv.
ENDFORM.
