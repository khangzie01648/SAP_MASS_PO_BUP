
*& Include ZBDC_MPE_M0_UTIL_BUP
*& Purpose Side-effect-controlled reusable utilities
*& explicit result contracts

* global Vietnam demo clock buffers.
* Keep these declarations in the utility include because all /
* time-sync consumers call get_demo_now from this include. This also
* makes the fix independent of whether an older TOP include is still active.
DATA: gv_demo_date_837 TYPE sy-datum,
      gv_demo_time_837 TYPE sy-uzeit.

*& Human-readable byte count. The public signature remains TYPE i because
*& SAP GUI FILE_GET_SIZE returns i in this target release.

FORM format_file_size
  USING    pv_bytes TYPE i
  CHANGING cv_text  TYPE char20.

  DATA: lv_value TYPE p LENGTH 12 DECIMALS 1,
        lv_unit  TYPE c LENGTH 2.

  CLEAR cv_text.
  IF pv_bytes < 0.
    cv_text = 'Unknown'.
    RETURN.
  ENDIF.

  IF pv_bytes < 1024.
    WRITE pv_bytes TO cv_text LEFT-JUSTIFIED.
    CONDENSE cv_text.
    CONCATENATE cv_text 'B' INTO cv_text SEPARATED BY space.
    RETURN.
  ENDIF.

  lv_value = pv_bytes.
  IF pv_bytes < 1048576.
    DIVIDE lv_value BY 1024.
    lv_unit = 'KB'.
  ELSE.
    DIVIDE lv_value BY 1048576.
    lv_unit = 'MB'.
  ENDIF.

  WRITE lv_value TO cv_text DECIMALS 1 LEFT-JUSTIFIED.
  CONDENSE cv_text.
  CONCATENATE cv_text lv_unit INTO cv_text SEPARATED BY space.
ENDFORM.

*& Recalculate only a physical frontend path. URI/source classification is
*& owned by source adapters. Existing persisted size is preserved when the
*& path is remote or inaccessible; a local path is always recalculated.

FORM recalc_source_size
  USING    pv_source TYPE csequence
           pv_file   TYPE any
  CHANGING cv_size   TYPE char20.

  DATA: lv_source      TYPE string,
        lv_file        TYPE string,
        lv_bytes       TYPE i,
        lv_get_subrc   TYPE sy-subrc,
        lv_flush_subrc TYPE sy-subrc.

  lv_source = pv_source.
  TRANSLATE lv_source TO UPPER CASE.
  CONDENSE lv_source NO-GAPS.
  lv_file = pv_file.
  CONDENSE lv_file.

 "Only a source adapter may declare a path to be frontend-local. Remote
 "identity is never guessed from punctuation inside a display string.
  IF lv_source <> 'LOCAL' AND lv_source <> 'LOCAL_FILE'.
    IF cv_size IS INITIAL.
      cv_size = 'Unknown'.
    ENDIF.
    RETURN.
  ENDIF.

  IF lv_file IS INITIAL.
    cv_size = 'Unknown'.
    RETURN.
  ENDIF.

  CLEAR lv_bytes.
  cl_gui_frontend_services=>file_get_size(
    EXPORTING
      file_name = lv_file
    IMPORTING
      file_size = lv_bytes
    EXCEPTIONS
      OTHERS    = 1 ).
  lv_get_subrc = sy-subrc.

  CALL METHOD cl_gui_cfw=>flush
    EXCEPTIONS
      OTHERS = 1.
  lv_flush_subrc = sy-subrc.

  IF lv_get_subrc = 0 AND lv_flush_subrc = 0 AND lv_bytes >= 0.
    PERFORM format_file_size USING lv_bytes CHANGING cv_size.
  ELSE.
    cv_size = 'Unknown'.
  ENDIF.
ENDFORM.

*& Read one dynamic component as raw text with explicit result flags.
*& Missing component and blank component are distinct outcomes.

FORM get_comp_raw
  USING    is_any     TYPE any
           iv_comp    TYPE csequence
  CHANGING cv_found   TYPE abap_bool
           cv_ok      TYPE abap_bool
           cv_value   TYPE string.

  FIELD-SYMBOLS <lv_any> TYPE any.

  CLEAR: cv_found, cv_ok, cv_value.
  ASSIGN COMPONENT iv_comp OF STRUCTURE is_any TO <lv_any>.
  IF sy-subrc <> 0 OR <lv_any> IS NOT ASSIGNED.
    RETURN.
  ENDIF.

  cv_found = abap_true.
  TRY.
      cv_value = <lv_any>.
      cv_ok = abap_true.
    CATCH cx_root.
      CLEAR cv_value.
  ENDTRY.
ENDFORM.

*& Read one dynamic component as normalized display/config text.

FORM get_comp_text
  USING    is_any     TYPE any
           iv_comp    TYPE csequence
  CHANGING cv_found   TYPE abap_bool
           cv_ok      TYPE abap_bool
           cv_value   TYPE string.

  PERFORM get_comp_raw
    USING    is_any iv_comp
    CHANGING cv_found cv_ok cv_value.

  IF cv_ok = abap_true.
    CONDENSE cv_value.
  ENDIF.
ENDFORM.

*& Parse a positive integer from a dynpro/config text field.
*& Owns numeric normalization once for every runtime caller. It accepts only
*& decimal digits after UI whitespace is removed; visible non-numeric content
*& remains an error instead of being coerced.

FORM parse_pos_int
  USING    iv_text    TYPE any
           iv_label   TYPE csequence
  CHANGING cv_value   TYPE i
           cv_ok      TYPE abap_bool
           cv_message TYPE string
           cv_norm    TYPE string.

  DATA: lv_text TYPE string,
        lv_len  TYPE i,
        lv_idx  TYPE i,
        lv_char TYPE c LENGTH 1.

  CLEAR: cv_value, cv_ok, cv_message, cv_norm.

  lv_text = iv_text.
  CONDENSE lv_text NO-GAPS.

  IF lv_text IS INITIAL.
    MESSAGE ID 'ZBDC' TYPE 'S' NUMBER '012' WITH iv_label INTO cv_message.
    RETURN.
  ENDIF.

  lv_len = strlen( lv_text ).
  DO lv_len TIMES.
    lv_idx = sy-index - 1.
    lv_char = lv_text+lv_idx(1).
    IF lv_char CO '0123456789'.
      CONCATENATE cv_norm lv_char INTO cv_norm.
    ELSE.
      CLEAR cv_norm.
      MESSAGE ID 'ZBDC' TYPE 'S' NUMBER '013' WITH iv_label lv_text INTO cv_message.
      RETURN.
    ENDIF.
  ENDDO.

  IF cv_norm IS INITIAL.
    MESSAGE ID 'ZBDC' TYPE 'S' NUMBER '012' WITH iv_label INTO cv_message.
    RETURN.
  ENDIF.

  TRY.
      cv_value = cv_norm.
    CATCH cx_root INTO DATA(lx_int).
      CLEAR cv_value.
      cv_message = lx_int->get_text( ).
      RETURN.
  ENDTRY.

  IF cv_value <= 0.
    CLEAR cv_value.
    MESSAGE ID 'ZBDC' TYPE 'S' NUMBER '014' WITH iv_label INTO cv_message.
    RETURN.
  ENDIF.

  cv_ok = abap_true.
ENDFORM.

*& DDIC existence check with a per-internal-session cache.

FORM table_exists
  USING    iv_tabname TYPE tabname
  CHANGING cv_exists  TYPE abap_bool.

  STATICS gt_exists TYPE HASHED TABLE OF tabname
                    WITH UNIQUE KEY table_line.

  DATA: lt_dfies TYPE STANDARD TABLE OF dfies,
        lv_name  TYPE tabname.

  CLEAR cv_exists.
  lv_name = iv_tabname.
  TRANSLATE lv_name TO UPPER CASE.
  CONDENSE lv_name NO-GAPS.
  IF lv_name IS INITIAL.
    RETURN.
  ENDIF.

  READ TABLE gt_exists WITH TABLE KEY table_line = lv_name
    TRANSPORTING NO FIELDS.
  IF sy-subrc = 0.
    cv_exists = abap_true.
    RETURN.
  ENDIF.

  CALL FUNCTION 'DDIF_FIELDINFO_GET'
    EXPORTING
      tabname   = lv_name
    TABLES
      dfies_tab = lt_dfies
    EXCEPTIONS
      not_found = 1
      OTHERS    = 2.

  IF sy-subrc = 0 AND lt_dfies IS NOT INITIAL.
    INSERT lv_name INTO TABLE gt_exists.
    cv_exists = abap_true.
  ENDIF.
ENDFORM.

*& Explicit optional-component reader facade. Missing/conversion failures return blank by design.

FORM get_optional_comp
  USING    is_any   TYPE any
           iv_comp  TYPE csequence
  CHANGING cv_value TYPE string.

  DATA: lv_found TYPE abap_bool,
        lv_ok    TYPE abap_bool.

  PERFORM get_comp_text
    USING    is_any iv_comp
    CHANGING lv_found lv_ok cv_value.
ENDFORM.

*& Explicit dynamic setter result contract.

FORM try_set_comp
  USING    iv_comp    TYPE csequence
           iv_value   TYPE any
  CHANGING cs_any     TYPE any
           cv_found   TYPE abap_bool
           cv_ok      TYPE abap_bool
           cv_message TYPE string.

  FIELD-SYMBOLS <lv_any> TYPE any.

  CLEAR: cv_found, cv_ok, cv_message.
  ASSIGN COMPONENT iv_comp OF STRUCTURE cs_any TO <lv_any>.
  IF sy-subrc <> 0 OR <lv_any> IS NOT ASSIGNED.
    MESSAGE ID 'ZBDC' TYPE 'S' NUMBER '015' WITH iv_comp INTO cv_message.
    RETURN.
  ENDIF.

  cv_found = abap_true.
  TRY.
      <lv_any> = iv_value.
      cv_ok = abap_true.
    CATCH cx_root INTO DATA(lx_set).
      cv_message = lx_set->get_text( ).
  ENDTRY.
ENDFORM.

*& Explicit optional-component setter. DDIC-version-specific metadata may be absent.
*& Mandatory writes must use try_set_comp and inspect FOUND/OK/MESSAGE.

FORM set_optional_comp
  USING    iv_comp  TYPE csequence
           iv_value TYPE any
  CHANGING cs_any   TYPE any.

  DATA: lv_found   TYPE abap_bool,
        lv_ok      TYPE abap_bool,
        lv_message TYPE string.

  PERFORM try_set_comp
    USING    iv_comp iv_value
    CHANGING cs_any lv_found lv_ok lv_message.
ENDFORM.


*&---------------------------------------------------------------------*
*& Build one DDIC-compatible append-only Change Audit ID
*&---------------------------------------------------------------------*
*& CHANGE_ID is transported as an optional/custom DDIC component and may be
*& CHAR or NUMC with a shorter length than SYSUUID_C32. Older code silently
*& swallowed conversion/truncation failures and then INSERTed an initial or
*& repeated key. Build the candidate against the REAL component type/length,
*& write it through TRY_SET_COMP, and verify the stored value before INSERT.
FORM build_change_audit_id
  USING    iv_attempt TYPE i
  CHANGING cs_any     TYPE any
           cv_ok      TYPE abap_bool
           cv_id      TYPE string
           cv_message TYPE string.

  DATA: lv_uuid      TYPE sysuuid_c32,
        lv_ts        TYPE timestampl,
        lv_material  TYPE string,
        lv_type      TYPE c LENGTH 1,
        lv_len       TYPE i,
        lv_found     TYPE abap_bool,
        lv_set_ok    TYPE abap_bool,
        lv_set_msg   TYPE string,
        lv_stored    TYPE string.
  FIELD-SYMBOLS <lv_change_id> TYPE any.

  CLEAR: cv_ok, cv_id, cv_message.

  ASSIGN COMPONENT 'CHANGE_ID' OF STRUCTURE cs_any TO <lv_change_id>.
  IF sy-subrc <> 0 OR <lv_change_id> IS NOT ASSIGNED.
    cv_message = 'ZBDC_CHG_BUP has no CHANGE_ID component; append-only audit cannot be written.'.
    RETURN.
  ENDIF.

  DESCRIBE FIELD <lv_change_id> TYPE lv_type LENGTH lv_len IN CHARACTER MODE.

  TRY.
      lv_uuid = cl_system_uuid=>create_uuid_c32_static( ).
    CATCH cx_uuid_error.
      CLEAR lv_uuid.
  ENDTRY.
  GET TIME STAMP FIELD lv_ts.

  IF lv_uuid IS NOT INITIAL.
    lv_material = |{ lv_uuid }{ iv_attempt }|.
  ELSE.
    lv_material = |{ lv_ts }{ sy-uname }{ iv_attempt }|.
  ENDIF.

  "NUMC/integer-like audit IDs must receive digits only. Keep entropy at the
  "left because short DDIC fields truncate on assignment.
  IF lv_type = 'N' OR lv_type = 'I' OR lv_type = 'P' OR lv_type = '8'.
    TRANSLATE lv_material TO UPPER CASE.
    REPLACE ALL OCCURRENCES OF 'A' IN lv_material WITH '0'.
    REPLACE ALL OCCURRENCES OF 'B' IN lv_material WITH '1'.
    REPLACE ALL OCCURRENCES OF 'C' IN lv_material WITH '2'.
    REPLACE ALL OCCURRENCES OF 'D' IN lv_material WITH '3'.
    REPLACE ALL OCCURRENCES OF 'E' IN lv_material WITH '4'.
    REPLACE ALL OCCURRENCES OF 'F' IN lv_material WITH '5'.
    REPLACE ALL OCCURRENCES OF PCRE '[^0-9]' IN lv_material WITH ''.
  ENDIF.

  IF lv_len > 0 AND strlen( lv_material ) > lv_len.
    lv_material = lv_material(lv_len).
  ENDIF.

  CLEAR: lv_found, lv_set_ok, lv_set_msg.
  PERFORM try_set_comp
    USING    'CHANGE_ID' lv_material
    CHANGING cs_any lv_found lv_set_ok lv_set_msg.
  IF lv_found <> abap_true OR lv_set_ok <> abap_true.
    IF lv_set_msg IS INITIAL.
      lv_set_msg = |CHANGE_ID value is incompatible with DDIC type { lv_type } length { lv_len }.|.
    ENDIF.
    cv_message = lv_set_msg.
    RETURN.
  ENDIF.

  CLEAR lv_stored.
  PERFORM get_optional_comp USING cs_any 'CHANGE_ID' CHANGING lv_stored.
  IF lv_stored IS INITIAL.
    cv_message = 'CHANGE_ID remained initial after DDIC-compatible assignment.'.
    RETURN.
  ENDIF.

  cv_id = lv_stored.
  cv_ok = abap_true.
ENDFORM.

*&---------------------------------------------------------------------*
*& One append-only Change Audit INSERT with DDIC-compatible unique ID
*&---------------------------------------------------------------------*
FORM insert_change_audit_row
  USING    iv_session TYPE any
           iv_row     TYPE any
           iv_tcode   TYPE any
           iv_field   TYPE any
           iv_old     TYPE any
           iv_new     TYPE any
           iv_action  TYPE any
  CHANGING cv_ok      TYPE abap_bool
           cv_message TYPE string.

  DATA: lv_exists TYPE abap_bool,
        lr_line   TYPE REF TO data,
        lv_tab    TYPE tabname,
        lv_ts     TYPE timestampl,
        lv_id     TYPE string,
        lv_id_ok  TYPE abap_bool,
        lv_id_msg TYPE string.
  FIELD-SYMBOLS <ls_any> TYPE any.

  CLEAR: cv_ok, cv_message.
  CLEAR lv_exists.
  PERFORM table_exists USING gc_z16_tab_chg CHANGING lv_exists.
  IF lv_exists <> abap_true.
    cv_message = 'ZBDC_CHG_BUP is not installed.'.
    RETURN.
  ENDIF.

  lv_tab = gc_z16_tab_chg.
  DO 12 TIMES.
    TRY.
        CREATE DATA lr_line TYPE (gc_z16_tab_chg).
        ASSIGN lr_line->* TO <ls_any>.
      CATCH cx_root INTO DATA(lx_create_chg).
        cv_message = |Change Audit row could not be created: { lx_create_chg->get_text( ) }|.
        RETURN.
    ENDTRY.

    CLEAR: lv_id, lv_id_ok, lv_id_msg.
    PERFORM build_change_audit_id
      USING    sy-index
      CHANGING <ls_any> lv_id_ok lv_id lv_id_msg.
    IF lv_id_ok <> abap_true.
      cv_message = |Change Audit CHANGE_ID could not be built: { lv_id_msg }|.
      RETURN.
    ENDIF.

    GET TIME STAMP FIELD lv_ts.
    PERFORM set_optional_comp USING 'SESSION_ID'    iv_session CHANGING <ls_any>.
    PERFORM set_optional_comp USING 'ROW_INDEX'     iv_row     CHANGING <ls_any>.
    PERFORM set_optional_comp USING 'TCODE'         iv_tcode   CHANGING <ls_any>.
    PERFORM set_optional_comp USING 'FIELD_NAME'    iv_field   CHANGING <ls_any>.
    PERFORM set_optional_comp USING 'OLD_VALUE'     iv_old     CHANGING <ls_any>.
    PERFORM set_optional_comp USING 'NEW_VALUE'     iv_new     CHANGING <ls_any>.
    PERFORM set_optional_comp USING 'CHANGED_BY'    sy-uname   CHANGING <ls_any>.
    PERFORM set_optional_comp USING 'CHANGED_AT'    lv_ts      CHANGING <ls_any>.
    PERFORM set_optional_comp USING 'CHANGE_ACTION' iv_action  CHANGING <ls_any>.

    TRY.
        INSERT (lv_tab) FROM <ls_any>.
      CATCH cx_root INTO DATA(lx_insert_chg).
        cv_message = |Change Audit insert failed: { lx_insert_chg->get_text( ) }|.
        RETURN.
    ENDTRY.

    IF sy-subrc = 0.
      cv_ok = abap_true.
      RETURN.
    ENDIF.
  ENDDO.

  cv_message = 'Change Audit INSERT collided after 12 DDIC-compatible IDs; check the key definition of ZBDC_CHG_BUP.'.
ENDFORM.

*& Script compiler metadata registry

*& Compiler metadata is stored outside the immutable Script Header/Steps.
*& The key is the immutable SCRIPT_ID, so Mapping edits on the same candidate
*& keep the same raw acquisition link and compiler certificate.

FORM script_cfg_key
  USING    iv_script_id TYPE zbdc_script_bup-script_id
           iv_kind      TYPE csequence
  CHANGING cv_key       TYPE zbdc_config_bup-config_key.

  DATA: lv_script TYPE string,
        lv_kind   TYPE string.

  CLEAR cv_key.
  lv_script = iv_script_id.
  lv_kind   = iv_kind.
  TRANSLATE: lv_script TO UPPER CASE, lv_kind TO UPPER CASE.
  CONDENSE: lv_script NO-GAPS, lv_kind NO-GAPS.

  IF lv_script IS INITIAL OR lv_kind IS INITIAL.
    RETURN.
  ENDIF.

  CONCATENATE 'Z499' lv_kind lv_script
    INTO cv_key SEPARATED BY ':'.
ENDFORM.

FORM get_script_cfg
  USING    iv_script_id TYPE zbdc_script_bup-script_id
           iv_kind      TYPE csequence
  CHANGING cv_value     TYPE zbdc_config_bup-config_value.

  DATA lv_key TYPE zbdc_config_bup-config_key.

  CLEAR cv_value.
  PERFORM script_cfg_key
    USING    iv_script_id iv_kind
    CHANGING lv_key.
  IF lv_key IS INITIAL.
    RETURN.
  ENDIF.

  SELECT SINGLE config_value
    FROM zbdc_config_bup
    INTO @cv_value
    WHERE config_key = @lv_key.
ENDFORM.

FORM set_script_cfg
  USING    iv_script_id TYPE zbdc_script_bup-script_id
           iv_kind      TYPE csequence
           iv_value     TYPE any
  CHANGING cv_ok        TYPE abap_bool
           cv_message   TYPE string.

  DATA: ls_cfg TYPE zbdc_config_bup,
        lv_key TYPE zbdc_config_bup-config_key,
        lv_val TYPE zbdc_config_bup-config_value.

  CLEAR: cv_ok, cv_message.
  PERFORM script_cfg_key
    USING    iv_script_id iv_kind
    CHANGING lv_key.
  IF lv_key IS INITIAL.
    MESSAGE ID 'ZBDC' TYPE 'S' NUMBER '016' INTO cv_message.
    RETURN.
  ENDIF.

  lv_val = iv_value.
  CONDENSE lv_val.
  IF lv_val IS INITIAL.
    MESSAGE ID 'ZBDC' TYPE 'S' NUMBER '017' INTO cv_message.
    RETURN.
  ENDIF.

  CLEAR ls_cfg.
  ls_cfg-config_key   = lv_key.
  ls_cfg-config_value = lv_val.
  MODIFY zbdc_config_bup FROM @ls_cfg.
  IF sy-subrc <> 0.
    MESSAGE ID 'ZBDC' TYPE 'S' NUMBER '018' INTO cv_message.
    RETURN.
  ENDIF.

  cv_ok = abap_true.
ENDFORM.

*& Simple RAW-first compiler/certificate version

*& One source of truth for the executable-plan compiler version. Bump this
*& only when the RAW->executable projection changes. S1 is the simplified
*& model: preserve SHDB order exactly; only a repeatable segment proven by
*& mapped multi-row evidence may use &IDX&. Runtime never reconstructs RAW.
*& Already LIVE-certified older plans remain immutable/grandfathered.

FORM current_compiler
  CHANGING cv_version TYPE zbdc_config_bup-config_value.

  CLEAR cv_version.
  cv_version = 'S1'.
ENDFORM.

FORM compiler_cert_ok
  USING    iv_script_id TYPE zbdc_script_bup-script_id
  CHANGING cv_ok        TYPE abap_bool
           cv_message   TYPE string.

  DATA: lv_comp        TYPE zbdc_config_bup-config_value,
        lv_required    TYPE zbdc_config_bup-config_value,
        lv_raw         TYPE zbdc_config_bup-config_value,
        lv_raw_id      TYPE zbdc_sct_ver_bup-script_id,
        lv_probe       TYPE zbdc_sct_ver_bup-script_id,
        ls_head        TYPE zbdc_script_bup,
        lv_cert_status TYPE zbdc_cert_bup-cert_status.

  CLEAR: cv_ok, cv_message.
  IF iv_script_id IS INITIAL.
    MESSAGE ID 'ZBDC' TYPE 'S' NUMBER '019' INTO cv_message.
    RETURN.
  ENDIF.

  PERFORM get_script_cfg
    USING    iv_script_id 'COMPILER'
    CHANGING lv_comp.
  TRANSLATE lv_comp TO UPPER CASE.
  CONDENSE lv_comp NO-GAPS.

  CLEAR lv_required.
  PERFORM current_compiler CHANGING lv_required.
  TRANSLATE lv_required TO UPPER CASE.
  CONDENSE lv_required NO-GAPS.

  IF lv_comp <> lv_required.
 "A LIVE-certified immutable plan already proved itself against SAP. Do not
 "silently rewrite it merely because the compiler implementation advanced.
    CLEAR: ls_head, lv_cert_status.
    SELECT SINGLE *
      FROM zbdc_script_bup
      INTO @ls_head
      WHERE script_id = @iv_script_id.
    IF sy-subrc = 0.
      SELECT SINGLE cert_status
        FROM zbdc_cert_bup
        INTO @lv_cert_status
        WHERE tcode            = @ls_head-tcode
          AND profile_name     = @ls_head-profile_name
          AND profile_ver      = @ls_head-profile_ver
          AND cert_status      = 'CERTIFIED'
          AND last_test_status = 'CERTIFIED'.
      IF sy-subrc = 0 AND lv_cert_status = 'CERTIFIED'.
        cv_ok = abap_true.
        RETURN.
      ENDIF.
    ENDIF.

    IF lv_comp IS INITIAL.
      lv_comp = 'LEGACY'.
    ENDIF.
    cv_message =
      |Executable contract compiler { lv_comp } is older than current { lv_required }. The non-certified plan must be recompiled from immutable RAW before CT/SM35.|.
    RETURN.
  ENDIF.

  PERFORM get_script_cfg
    USING    iv_script_id 'RAW'
    CHANGING lv_raw.
  CONDENSE lv_raw NO-GAPS.
  IF lv_raw IS INITIAL.
    cv_message =
      'Compiler certificate exists but its immutable raw recording link is missing.'.
    RETURN.
  ENDIF.

  lv_raw_id = lv_raw.
  CLEAR lv_probe.
  SELECT SINGLE script_id
    FROM zbdc_sct_ver_bup
    INTO @lv_probe
    WHERE script_id = @lv_raw_id.
  IF sy-subrc <> 0 OR lv_probe IS INITIAL.
    cv_message =
      'Compiler certificate exists but its immutable raw recording snapshot is missing.'.
    RETURN.
  ENDIF.

  cv_ok = abap_true.
ENDFORM.

*& Unified real-time display clock for the Vietnam demo

*& Canonical DB timestamps remain GET TIME STAMP. User-facing wall-clock
*& rendering uses a deterministic Vietnam UTC+07:00 offset from UTC.
*& No SAP server/user timezone or TTZZ UTC+7 key participates in the normal
*& classroom-demo display path.

FORM ts_to_demo
  USING    iv_ts   TYPE any
  CHANGING cv_date TYPE sy-datum
           cv_time TYPE sy-uzeit.

  DATA: lv_ts      TYPE timestampl,
        lv_shifted TYPE timestampl.

  CLEAR: cv_date, cv_time, lv_ts, lv_shifted.
  IF iv_ts IS INITIAL.
    RETURN.
  ENDIF.

  TRY.
      lv_ts = iv_ts.
 "Vietnam has a fixed UTC+07:00 civil offset and no daylight saving.
 "Shift the canonical UTC timestamp by exactly seven hours, then render
 "the shifted value in UTC. This avoids any dependency on TTZZ keys or
 "the SAP application-server/user timezone during the classroom demo.
      lv_shifted = cl_abap_tstmp=>add( tstmp = lv_ts secs = 25200 ).
      CONVERT TIME STAMP lv_shifted TIME ZONE 'UTC'
        INTO DATE cv_date TIME cv_time.
    CATCH cx_root.
      CLEAR: cv_date, cv_time.
  ENDTRY.
ENDFORM.

FORM get_demo_now
  CHANGING cv_date TYPE sy-datum
           cv_time TYPE sy-uzeit.

  DATA lv_ts TYPE timestampl.

  CLEAR: cv_date, cv_time, lv_ts.
  GET TIME STAMP FIELD lv_ts.
  PERFORM ts_to_demo USING lv_ts CHANGING cv_date cv_time.

  IF cv_date IS INITIAL.
 "never fall back to SAP user/server local time. A failed
 "Vietnam conversion must remain blank rather than display a potentially
 "German/system-zone clock during the demo.
    CLEAR: cv_date, cv_time.
  ENDIF.
ENDFORM.

FORM format_demo_ts
  USING    iv_ts   TYPE any
  CHANGING cv_text TYPE char19.

  DATA: lv_date TYPE sy-datum,
        lv_time TYPE sy-uzeit,
        lv_dtxt TYPE char10,
        lv_ttxt TYPE char8.

  CLEAR: cv_text, lv_date, lv_time, lv_dtxt, lv_ttxt.
  PERFORM ts_to_demo USING iv_ts CHANGING lv_date lv_time.
  IF lv_date IS INITIAL.
    RETURN.
  ENDIF.

  CONCATENATE lv_date+0(4) '-' lv_date+4(2) '-' lv_date+6(2)
    INTO lv_dtxt.
  CONCATENATE lv_time+0(2) ':' lv_time+2(2) ':' lv_time+4(2)
    INTO lv_ttxt.
  CONCATENATE lv_dtxt lv_ttxt INTO cv_text SEPARATED BY space.
ENDFORM.

*& Standards-correct current UTC text for explicit Z metadata

FORM get_utc_w3cdtf CHANGING cv_text TYPE string.
  DATA: lv_ts   TYPE timestampl,
        lv_date TYPE sy-datum,
        lv_time TYPE sy-uzeit.

  CLEAR: cv_text, lv_ts, lv_date, lv_time.
  GET TIME STAMP FIELD lv_ts.
  TRY.
      CONVERT TIME STAMP lv_ts TIME ZONE 'UTC'
        INTO DATE lv_date TIME lv_time.
    CATCH cx_root.
      RETURN.
  ENDTRY.
  cv_text =
    |{ lv_date+0(4) }-{ lv_date+4(2) }-{ lv_date+6(2) }T| &&
    |{ lv_time+0(2) }:{ lv_time+2(2) }:{ lv_time+4(2) }Z|.
ENDFORM.
