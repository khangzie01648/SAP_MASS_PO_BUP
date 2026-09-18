
*& Include ZBDC_MPE_M3_VALID_BUP
*& Purpose Validation rules, eligibility and fail-closed checks
*& validate-time GUI resolution + fidelity gates

*& Shared executable BDCDATA structural contract

*& CALL TRANSACTION and Batch Input Session are two executors over the same
*& prepared BDCDATA. Therefore structural executability is validated here
*& once and is not owned by either executor.

*& Exact executable BDCDATA fingerprint

*& Sanitizer fidelity gate

*& Z116 is allowed to perform exactly one technical normalization:
*& terminal one-digit screen-table indices are padded to two digits in FNAM
*& and BDC_CURSOR values. It must never add/drop/reorder a row or change any
*& Program/Dynpro/OKCODE/business value.

*& Compare expected and SAP-stored SM35 executable streams

*& Legacy compatibility facade. New runtime code uses the shared validator
*& with an explicit prepared table; old callers may still validate BDCDATA.

*& Build and validate one representative group before SM35 opens
*& Prevents empty 0-transaction sessions when the script/mapping is invalid.

FORM preflight_sm35_group
  USING    pt_group  TYPE ty_t_staging_alv
           pt_s_pre  TYPE ty_t_script
           pt_s_item TYPE ty_t_script
           pt_s_post TYPE ty_t_script
           pt_map    TYPE ty_t_map
           pv_tcode  TYPE sy-tcode
  CHANGING cv_ok     TYPE abap_bool
           cv_msg    TYPE string.

  DATA: lt_bdc        TYPE ty_t_async_bdcdata,
        lv_prepare_ok TYPE abap_bool,
        lv_prepare_msg TYPE string.

  CLEAR: cv_ok, cv_msg.
  IF pt_group IS INITIAL.
    MESSAGE ID 'ZBDC' TYPE 'S' NUMBER '406' INTO cv_msg.
    RETURN.
  ENDIF.

 "Dry-run the exact same builder used by CT and BISM. Object/trace proof is
 "not part of executor preflight.
  REFRESH lt_bdc.
  PERFORM prepare_group_bdcdata
    USING    pt_group pt_s_pre pt_s_item pt_s_post pt_map pv_tcode
    CHANGING lt_bdc lv_prepare_ok lv_prepare_msg.
  IF lv_prepare_ok <> abap_true.
    IF lv_prepare_msg IS INITIAL.
      MESSAGE ID 'ZBDC' TYPE 'S' NUMBER '407' INTO cv_msg.
    ELSE.
      MESSAGE ID 'ZBDC' TYPE 'S' NUMBER '408'
        WITH lv_prepare_msg INTO cv_msg.
    ENDIF.
    RETURN.
  ENDIF.

  cv_ok = abap_true.
ENDFORM.

*& Business Key cardinality proof - frozen recording authority
*&
*& BUSINESS_KEY / RECORD_KEY groups source rows; it never proves that the
*& frozen SHDB flow can consume more than one row. Multi-row is accepted only
*& when the exact immutable compiled Script contains the compiler-proven ITEM
*& plan emitted by CANON_ITEM_PROTOTYPES. That compiler writes (&IDX&) only
*& after structural repeat proof; raw FIELD(01), field names, TCODE names and
*& AI are never used as cardinality authority.
*&
*& Once multi-row is proven, all DYNAMIC sources owned by ROW_TYPE = I may
*& differ per source row. DYNAMIC sources owned outside ITEM are single-slot
*& values; later blank continuation values are allowed, but a competing
*& nonblank value is rejected because it would otherwise be silently ignored
*& or overwrite one SAP input occurrence.
FORM check_group_cardinality_proof
  USING    pt_group   TYPE ty_t_staging_alv
  CHANGING cv_ok      TYPE abap_bool
           cv_message TYPE string.

  TYPES: ty_t_source_key TYPE SORTED TABLE OF zbdc_mapping_bup-source_column
                         WITH UNIQUE KEY table_line,
         BEGIN OF ty_source_slot,
           source_column TYPE zbdc_mapping_bup-source_column,
           staging_field TYPE zbdc_mapping_bup-staging_field,
         END OF ty_source_slot,
         ty_t_source_slot TYPE SORTED TABLE OF ty_source_slot
                          WITH UNIQUE KEY source_column staging_field.

  DATA: ls_first       TYPE ty_staging_alv,
        ls_row         TYPE ty_staging_alv,
        ls_step        TYPE zbdc_sct_ver_bup,
        ls_map         TYPE zbdc_mapping_bup,
        lt_steps       TYPE STANDARD TABLE OF zbdc_sct_ver_bup,
        lt_map         TYPE ty_t_map,
        lt_repeat_src  TYPE ty_t_source_key,
        lt_single_src  TYPE ty_t_source_key,
        lt_seen_slot   TYPE ty_t_source_slot,
        ls_slot        TYPE ty_source_slot,
        lv_tcode       TYPE zbdc_prof_bup-tcode,
        lv_profile     TYPE zbdc_prof_bup-profile_name,
        lv_ver         TYPE zbdc_prof_bup-profile_ver,
        lv_found       TYPE abap_bool,
        lv_rows        TYPE i,
        lv_item_token  TYPE string,
        lv_has_proof    TYPE abap_bool,
        lv_source       TYPE zbdc_mapping_bup-source_column,
        lv_first_value  TYPE string,
        lv_row_value    TYPE string,
        lv_comp_have    TYPE zbdc_config_bup-config_value,
        lv_comp_need    TYPE zbdc_config_bup-config_value,
        lv_mapclass_ok  TYPE abap_bool,
        lv_mapclass_msg TYPE string.

  FIELD-SYMBOLS: <lv_first> TYPE any,
                 <lv_row>   TYPE any.

  CLEAR: cv_ok, cv_message.
  DESCRIBE TABLE pt_group LINES lv_rows.
  IF lv_rows <= 1.
    cv_ok = abap_true.
    RETURN.
  ENDIF.

  READ TABLE pt_group INTO ls_first INDEX 1.
  IF sy-subrc <> 0 OR ls_first-session_id IS INITIAL OR
     ls_first-record_key IS INITIAL.
    cv_message =
      'GROUP_CARDINALITY_SCOPE_INVALID: multi-row validation requires one exact Session ID and nonblank Business Key.'.
    RETURN.
  ENDIF.

  LOOP AT pt_group INTO ls_row.
    IF ls_row-session_id <> ls_first-session_id OR
       ls_row-record_key <> ls_first-record_key OR
       ls_row-tcode      <> ls_first-tcode.
      cv_message =
        |GROUP_CARDINALITY_SCOPE_INVALID: Business Key { ls_first-record_key } contains mixed session/TCODE rows.|.
      RETURN.
    ENDIF.
  ENDLOOP.

 "Resolve the exact frozen owner. No latest profile/script fallback is allowed.
  CLEAR: lv_tcode, lv_profile, lv_ver, lv_found.
  PERFORM resolve_session_context
    USING    ls_first-session_id
    CHANGING lv_tcode lv_profile lv_ver lv_found.
  IF lv_found <> abap_true OR lv_tcode <> ls_first-tcode OR
     gv_runtime_script_id IS INITIAL.
    cv_message =
      |GROUP_CARDINALITY_NOT_PROVEN: Business Key { ls_first-record_key } has { lv_rows } rows, but its exact frozen Script/Hash recording proof is unavailable. Keep one row per Business Key or publish a proven multi-row recording.|.
    RETURN.
  ENDIF.

 "Multi-row proof must come from the current strict compiler + Mapping
 "classifier, not a grandfathered historical placeholder.
  CLEAR: lv_comp_have, lv_comp_need.
  PERFORM get_script_cfg
    USING    gv_runtime_script_id 'COMPILER'
    CHANGING lv_comp_have.
  PERFORM current_compiler CHANGING lv_comp_need.
  TRANSLATE lv_comp_have TO UPPER CASE.
  CONDENSE lv_comp_have NO-GAPS.
  TRANSLATE lv_comp_need TO UPPER CASE.
  CONDENSE lv_comp_need NO-GAPS.
  IF lv_comp_have IS INITIAL OR lv_comp_have <> lv_comp_need.
    cv_message =
      |GROUP_CARDINALITY_NOT_PROVEN: Business Key { ls_first-record_key } needs current compiler { lv_comp_need }, but frozen Script { gv_runtime_script_id } has { lv_comp_have }. Re-record/import this profile before grouping multiple rows.|.
    RETURN.
  ENDIF.

  CLEAR: lv_mapclass_ok, lv_mapclass_msg.
  PERFORM mapclass_cert_ok
    USING    gv_runtime_script_id
    CHANGING lv_mapclass_ok lv_mapclass_msg.
  IF lv_mapclass_ok <> abap_true.
    cv_message =
      |GROUP_CARDINALITY_NOT_PROVEN: { lv_mapclass_msg } Duplicate Business Key { ls_first-record_key } is blocked until the Mapping schema is rebuilt.|.
    RETURN.
  ENDIF.

  SELECT *
    FROM zbdc_sct_ver_bup
    INTO TABLE @lt_steps
    WHERE script_id = @gv_runtime_script_id
    ORDER BY step_seq.
  IF lt_steps IS INITIAL.
    cv_message =
      |GROUP_CARDINALITY_NOT_PROVEN: frozen Script { gv_runtime_script_id } has no compiled recording steps for Business Key { ls_first-record_key }.|.
    RETURN.
  ENDIF.

  REFRESH lt_map.
  SELECT *
    FROM zbdc_mapping_bup
    INTO TABLE @lt_map
    WHERE tcode        = @lv_tcode
      AND profile_name = @lv_profile
      AND profile_ver  = @lv_ver.
  IF lt_map IS INITIAL.
    cv_message =
      |GROUP_CARDINALITY_CONTRACT_INVALID: frozen Mapping { lv_profile } v{ lv_ver } is missing for Business Key { ls_first-record_key }.|.
    RETURN.
  ENDIF.

  lv_item_token = '(' && gc_ph_index && ')'.
  CLEAR lv_has_proof.

 "The placeholder is trusted only in the immutable compiled Script. M2 emits
 "it only after SEGMENT_REPEATABLE_PROOF succeeds.
  LOOP AT lt_steps INTO ls_step
    WHERE is_new_screen IS INITIAL
      AND value_type = gc_vt_dynamic
      AND source_column IS NOT INITIAL.

    lv_source = ls_step-source_column.
    PERFORM normalize_mapping_source USING lv_source CHANGING lv_source.
    IF lv_source IS INITIAL.
      CONTINUE.
    ENDIF.

    IF ls_step-row_type = gc_rt_item.
      INSERT lv_source INTO TABLE lt_repeat_src.
      IF ls_step-field_name CS lv_item_token.
        lv_has_proof = abap_true.
      ENDIF.
    ELSE.
      INSERT lv_source INTO TABLE lt_single_src.
    ENDIF.
  ENDLOOP.

  IF lv_has_proof <> abap_true OR lt_repeat_src IS INITIAL.
    cv_message =
      |GROUP_CARDINALITY_NOT_PROVEN: Business Key { ls_first-record_key } has { lv_rows } rows, but frozen recording { gv_runtime_script_id } proves only single-row execution. Record/import a multi-row flow or use separate Business Keys.|.
    RETURN.
  ENDIF.

 "One source cannot simultaneously be both one fixed SAP occurrence and a
 "repeat-row source; such a contract is ambiguous and must be republished.
  LOOP AT lt_repeat_src INTO lv_source.
    READ TABLE lt_single_src TRANSPORTING NO FIELDS
      WITH TABLE KEY table_line = lv_source.
    IF sy-subrc = 0.
      cv_message =
        |GROUP_CARDINALITY_CONTRACT_AMBIGUOUS: source { lv_source } is both single-occurrence and repeatable in frozen Script { gv_runtime_script_id }. Republish the recording/mapping before using duplicate Business Key { ls_first-record_key }.|.
      RETURN.
    ENDIF.
  ENDLOOP.

 "Check only compiler-owned single-occurrence sources. Repeat-row sources are
 "allowed to differ freely between rows; no business field name is hardcoded.
  LOOP AT lt_map INTO ls_map.
    IF ls_map-source_column IS INITIAL OR
       ls_map-staging_field IS INITIAL OR
       ls_map-staging_field = 'FIELD01'.
      CONTINUE.
    ENDIF.

    lv_source = ls_map-source_column.
    PERFORM normalize_mapping_source USING lv_source CHANGING lv_source.
    IF lv_source IS INITIAL.
      CONTINUE.
    ENDIF.

    READ TABLE lt_repeat_src TRANSPORTING NO FIELDS
      WITH TABLE KEY table_line = lv_source.
    IF sy-subrc = 0.
      CONTINUE.
    ENDIF.

    READ TABLE lt_single_src TRANSPORTING NO FIELDS
      WITH TABLE KEY table_line = lv_source.
    IF sy-subrc <> 0.
      CONTINUE.
    ENDIF.

    CLEAR ls_slot.
    ls_slot-source_column = lv_source.
    ls_slot-staging_field = ls_map-staging_field.
    READ TABLE lt_seen_slot TRANSPORTING NO FIELDS
      WITH TABLE KEY source_column = ls_slot-source_column
                     staging_field = ls_slot-staging_field.
    IF sy-subrc = 0.
      CONTINUE.
    ENDIF.
    INSERT ls_slot INTO TABLE lt_seen_slot.

    UNASSIGN <lv_first>.
    ASSIGN COMPONENT ls_map-staging_field OF STRUCTURE ls_first TO <lv_first>.
    IF sy-subrc <> 0 OR <lv_first> IS NOT ASSIGNED.
      cv_message =
        |GROUP_CARDINALITY_CONTRACT_INVALID: staging field { ls_map-staging_field } is unavailable for source { lv_source }.|.
      RETURN.
    ENDIF.

    lv_first_value = |{ <lv_first> }|.
    SHIFT lv_first_value LEFT DELETING LEADING space.
    SHIFT lv_first_value RIGHT DELETING TRAILING space.

    LOOP AT pt_group INTO ls_row FROM 2.
      UNASSIGN <lv_row>.
      ASSIGN COMPONENT ls_map-staging_field OF STRUCTURE ls_row TO <lv_row>.
      IF sy-subrc <> 0 OR <lv_row> IS NOT ASSIGNED.
        cv_message =
          |GROUP_CARDINALITY_CONTRACT_INVALID: staging field { ls_map-staging_field } is unavailable on row { ls_row-row_index }.|.
        RETURN.
      ENDIF.

      lv_row_value = |{ <lv_row> }|.
      SHIFT lv_row_value LEFT DELETING LEADING space.
      SHIFT lv_row_value RIGHT DELETING TRAILING space.

      "Blank continuation is allowed; the first row owns the one fixed slot.
      IF lv_row_value IS INITIAL.
        CONTINUE.
      ENDIF.

      IF lv_first_value IS INITIAL OR lv_row_value <> lv_first_value.
        cv_message =
          |BUSINESS_KEY_SINGLE_SLOT_CONFLICT: key { ls_first-record_key }, source { lv_source }, row { ls_row-row_index } conflicts with the first row. Use another Business Key or record a proven repeatable occurrence.|.
        RETURN.
      ENDIF.
    ENDLOOP.
  ENDLOOP.

  cv_ok = abap_true.
  cv_message =
    |Business Key { ls_first-record_key }: { lv_rows } rows accepted by compiler-proven multi-row recording { gv_runtime_script_id }.|.
ENDFORM.

*& Apply the proof to every duplicate Business Key in the currently loaded
*& staging scope. Invalid grouping is a DATA validation error: mark the whole
*& nonterminal group ERROR and still allow Screen 0400 to open for review/fix.
FORM validate_all_group_cardinality
  CHANGING cv_ok           TYPE abap_bool
           cv_error_groups TYPE i
           cv_message      TYPE string.

  DATA: lt_keys      TYPE ty_t_engine_group_key,
        ls_key       TYPE ty_engine_group_key,
        lt_group     TYPE ty_t_staging_alv,
        lv_group_ok  TYPE abap_bool,
        lv_group_msg TYPE string,
        lv_rows      TYPE i.

  FIELD-SYMBOLS <ls_alv> TYPE ty_staging_alv.

  CLEAR: cv_ok, cv_error_groups, cv_message.
  cv_ok = abap_true.

  IF gt_staging_alv IS INITIAL.
    RETURN.
  ENDIF.

  PERFORM build_engine_keys USING gt_staging_alv CHANGING lt_keys.

  LOOP AT lt_keys INTO ls_key WHERE record_key IS NOT INITIAL.
    REFRESH lt_group.
    PERFORM collect_group_key USING gt_staging_alv ls_key CHANGING lt_group.
    DESCRIBE TABLE lt_group LINES lv_rows.
    IF lv_rows <= 1.
      CONTINUE.
    ENDIF.

    CLEAR: lv_group_ok, lv_group_msg.
    PERFORM check_group_cardinality_proof
      USING    lt_group
      CHANGING lv_group_ok lv_group_msg.

    IF lv_group_ok = abap_true.
      CONTINUE.
    ENDIF.

    cv_error_groups = cv_error_groups + 1.
    IF cv_message IS INITIAL.
      cv_message = lv_group_msg.
    ENDIF.

    LOOP AT gt_staging_alv ASSIGNING <ls_alv>
      WHERE session_id = ls_key-session_id
        AND record_key = ls_key-record_key.
      IF <ls_alv>-status = gc_st_success OR
         <ls_alv>-status = gc_st_sm35q OR
         <ls_alv>-status = 'PROCESSING' OR
         <ls_alv>-status = 'SKIPPED'.
        CONTINUE.
      ENDIF.

      <ls_alv>-status = gc_st_error.
      IF <ls_alv>-error_msg IS INITIAL.
        <ls_alv>-error_msg = lv_group_msg.
      ELSEIF <ls_alv>-error_msg NS lv_group_msg.
        <ls_alv>-error_msg = |{ <ls_alv>-error_msg }; { lv_group_msg }|.
      ENDIF.
    ENDLOOP.
  ENDLOOP.

  IF cv_error_groups > 0.
    cv_message =
      |Staging found { cv_error_groups } invalid duplicate Business Key group(s). Open Staging to review the exact group error; no CT/BISM execution is allowed until corrected.|.
  ENDIF.
ENDFORM.

*&---------------------------------------------------------------------*
*& Strict actual-data blank contract
*&---------------------------------------------------------------------*
*& Mapped business-input columns are the contract. Required/Optional metadata
*& is not allowed to decide blank eligibility. A blank is accepted only when
*& the frozen recording/compiler proves a single-occurrence continuation in a
*& proven multi-row Business Key. Everything else fails closed.
FORM check_blank_contract_group
  USING    pt_group   TYPE ty_t_staging_alv
  CHANGING cv_ok      TYPE abap_bool
           cv_message TYPE string.

  TYPES: ty_t_source_key TYPE SORTED TABLE OF zbdc_mapping_bup-source_column
                         WITH UNIQUE KEY table_line.

  DATA: lt_group       TYPE ty_t_staging_alv,
        ls_first       TYPE ty_staging_alv,
        ls_row         TYPE ty_staging_alv,
        lt_map         TYPE ty_t_mapping_db,
        ls_map         TYPE zbdc_mapping_bup,
        lt_steps       TYPE STANDARD TABLE OF zbdc_sct_ver_bup,
        ls_step        TYPE zbdc_sct_ver_bup,
        lt_single_src  TYPE ty_t_source_key,
        lt_item_src    TYPE ty_t_source_key,
        lv_source      TYPE zbdc_mapping_bup-source_column,
        lv_value       TYPE string,
        lv_first_value TYPE string,
        lv_rows        TYPE i,
        lv_tcode       TYPE zbdc_prof_bup-tcode,
        lv_profile     TYPE zbdc_prof_bup-profile_name,
        lv_ver         TYPE zbdc_prof_bup-profile_ver,
        lv_found       TYPE abap_bool,
        lv_card_ok     TYPE abap_bool,
        lv_card_msg    TYPE string,
        lv_ctx_msg     TYPE string,
        lv_row_pos     TYPE i.

  FIELD-SYMBOLS: <lv_value> TYPE any,
                 <lv_first> TYPE any.

  CLEAR: cv_ok, cv_message.
  lt_group = pt_group.
  SORT lt_group BY row_index.
  DESCRIBE TABLE lt_group LINES lv_rows.
  IF lv_rows <= 0.
    cv_message = 'BLANK_CONTRACT_SCOPE_EMPTY: no staging row was supplied.'.
    RETURN.
  ENDIF.

  READ TABLE lt_group INTO ls_first INDEX 1.
  IF sy-subrc <> 0 OR ls_first-session_id IS INITIAL.
    cv_message = 'BLANK_CONTRACT_SCOPE_INVALID: exact Session ID is missing.'.
    RETURN.
  ENDIF.

  LOOP AT lt_group INTO ls_row.
    lv_value = ls_row-field01.
    CONDENSE lv_value NO-GAPS.
    IF lv_value IS INITIAL OR ls_row-record_key IS INITIAL.
      cv_message =
        |BLANK_CONTRACT_REJECTED: row { ls_row-row_index } has blank BUSINESS_KEY. Every physical input row must carry its Business Key.|.
      RETURN.
    ENDIF.
    IF ls_row-session_id <> ls_first-session_id OR
       ls_row-record_key <> ls_first-record_key OR
       ls_row-tcode      <> ls_first-tcode.
      cv_message =
        |BLANK_CONTRACT_SCOPE_INVALID: Business Key { ls_first-record_key } contains mixed Session/TCODE rows.|.
      RETURN.
    ENDIF.
  ENDLOOP.

  CLEAR: lv_tcode, lv_profile, lv_ver, lv_found, lv_ctx_msg.
  PERFORM resolve_session_context
    USING    ls_first-session_id
    CHANGING lv_tcode lv_profile lv_ver lv_found.
  IF lv_found <> abap_true.
    "Upload/Preview may legitimately own only the exact persisted
    "TCODE/Profile/Version before TEST_READY Script/Hash exists. Use that
    "owner for Mapping/value checks; executable/multi-row proof stays strict.
    PERFORM resolve_edit_context
      USING    ls_first-session_id
      CHANGING lv_tcode lv_profile lv_ver lv_found lv_ctx_msg.
  ENDIF.
  IF lv_found <> abap_true OR lv_tcode <> ls_first-tcode.
    IF lv_ctx_msg IS INITIAL.
      lv_ctx_msg =
        |exact TCODE/Profile/Version owner is unavailable for session { ls_first-session_id }|.
    ENDIF.
    cv_message = |BLANK_CONTRACT_NOT_PROVEN: { lv_ctx_msg }.|.
    RETURN.
  ENDIF.

  SELECT * FROM zbdc_mapping_bup
    INTO TABLE @lt_map
    WHERE tcode        = @lv_tcode
      AND profile_name = @lv_profile
      AND profile_ver  = @lv_ver.
  IF lt_map IS INITIAL.
    cv_message =
      |BLANK_CONTRACT_NOT_PROVEN: frozen Mapping { lv_profile } v{ lv_ver } is unavailable.|.
    RETURN.
  ENDIF.

  PERFORM project_template_schema
    USING    lv_tcode lv_profile lv_ver
    CHANGING lt_map.
  IF lt_map IS INITIAL.
    cv_message =
      |BLANK_CONTRACT_NOT_PROVEN: emitted business-input schema is unavailable for { lv_tcode }/{ lv_profile } v{ lv_ver }.|.
    RETURN.
  ENDIF.

  IF lv_rows > 1.
    CLEAR: lv_card_ok, lv_card_msg.
    PERFORM check_group_cardinality_proof
      USING    lt_group
      CHANGING lv_card_ok lv_card_msg.
    IF lv_card_ok <> abap_true.
      cv_message = lv_card_msg.
      RETURN.
    ENDIF.

    SELECT * FROM zbdc_sct_ver_bup
      INTO TABLE @lt_steps
      WHERE script_id = @gv_runtime_script_id
      ORDER BY step_seq.
    IF lt_steps IS INITIAL.
      cv_message =
        |BLANK_CONTRACT_NOT_PROVEN: compiled recording { gv_runtime_script_id } is unavailable.|.
      RETURN.
    ENDIF.

    LOOP AT lt_steps INTO ls_step
      WHERE is_new_screen IS INITIAL
        AND value_type = gc_vt_dynamic
        AND source_column IS NOT INITIAL.
      lv_source = ls_step-source_column.
      PERFORM normalize_mapping_source USING lv_source CHANGING lv_source.
      IF lv_source IS INITIAL.
        CONTINUE.
      ENDIF.
      IF ls_step-row_type = gc_rt_item.
        INSERT lv_source INTO TABLE lt_item_src.
      ELSE.
        INSERT lv_source INTO TABLE lt_single_src.
      ENDIF.
    ENDLOOP.

    "A source is blank-continuable only when the frozen executable plan proves
    "it is exclusively single-occurrence/header. Any ITEM occurrence wins.
    LOOP AT lt_item_src INTO lv_source.
      DELETE TABLE lt_single_src WITH TABLE KEY table_line = lv_source.
    ENDLOOP.
  ENDIF.

  LOOP AT lt_group INTO ls_row.
    lv_row_pos = sy-tabix.

    LOOP AT lt_map INTO ls_map.
      IF ls_map-source_column IS INITIAL OR ls_map-staging_field IS INITIAL.
        CONTINUE.
      ENDIF.

      UNASSIGN <lv_value>.
      ASSIGN COMPONENT ls_map-staging_field OF STRUCTURE ls_row TO <lv_value>.
      IF sy-subrc <> 0 OR <lv_value> IS NOT ASSIGNED.
        cv_message =
          |BLANK_CONTRACT_BIND_INVALID: { ls_map-source_column } -> { ls_map-staging_field } is unavailable on row { ls_row-row_index }.|.
        RETURN.
      ENDIF.

      lv_value = |{ <lv_value> }|.
      CONDENSE lv_value NO-GAPS.
      IF lv_value IS NOT INITIAL.
        CONTINUE.
      ENDIF.

      IF ls_map-staging_field = 'FIELD01'.
        cv_message =
          |BLANK_CONTRACT_REJECTED: row { ls_row-row_index } has blank { ls_map-source_column }. Every physical input row must carry its Business Key.|.
        RETURN.
      ENDIF.

      IF lv_rows > 1 AND lv_row_pos > 1.
        lv_source = ls_map-source_column.
        PERFORM normalize_mapping_source USING lv_source CHANGING lv_source.
        READ TABLE lt_single_src TRANSPORTING NO FIELDS
          WITH TABLE KEY table_line = lv_source.
        IF sy-subrc = 0.
          UNASSIGN <lv_first>.
          ASSIGN COMPONENT ls_map-staging_field OF STRUCTURE ls_first TO <lv_first>.
          IF sy-subrc = 0 AND <lv_first> IS ASSIGNED.
            lv_first_value = |{ <lv_first> }|.
            CONDENSE lv_first_value NO-GAPS.
            IF lv_first_value IS NOT INITIAL.
              CONTINUE.
            ENDIF.
          ENDIF.
        ENDIF.
      ENDIF.

      cv_message =
        |BLANK_CONTRACT_REJECTED: row { ls_row-row_index }, field { ls_map-source_column } is blank and frozen Investigation/recording does not prove a valid blank continuation.|.
      RETURN.
    ENDLOOP.
  ENDLOOP.

  cv_ok = abap_true.
  cv_message =
    |BLANK_CONTRACT_OK: Business Key { ls_first-record_key } satisfies the frozen actual-data contract.|.
ENDFORM.

FORM check_blank_contract_scope
  USING    pt_scope   TYPE ty_t_staging_alv
  CHANGING cv_ok      TYPE abap_bool
           cv_message TYPE string.

  DATA: lt_keys      TYPE ty_t_engine_group_key,
        ls_key       TYPE ty_engine_group_key,
        lt_group     TYPE ty_t_staging_alv,
        lv_group_ok  TYPE abap_bool,
        lv_group_msg TYPE string.

  CLEAR: cv_ok, cv_message.
  IF pt_scope IS INITIAL.
    cv_message = 'BLANK_CONTRACT_SCOPE_EMPTY: upload contains no business rows.'.
    RETURN.
  ENDIF.

  PERFORM build_engine_keys USING pt_scope CHANGING lt_keys.
  IF lt_keys IS INITIAL.
    cv_message = 'BLANK_CONTRACT_SCOPE_INVALID: no Business Key group could be built.'.
    RETURN.
  ENDIF.

  LOOP AT lt_keys INTO ls_key.
    REFRESH lt_group.
    PERFORM collect_group_key USING pt_scope ls_key CHANGING lt_group.
    CLEAR: lv_group_ok, lv_group_msg.
    PERFORM check_blank_contract_group
      USING    lt_group
      CHANGING lv_group_ok lv_group_msg.
    IF lv_group_ok <> abap_true.
      cv_message = lv_group_msg.
      RETURN.
    ENDIF.
  ENDLOOP.

  cv_ok = abap_true.
ENDFORM.

FORM apply_blank_contract_staging
  CHANGING cv_error_groups TYPE i
           cv_message      TYPE string.

  DATA: lt_keys        TYPE ty_t_engine_group_key,
        ls_key         TYPE ty_engine_group_key,
        lt_group       TYPE ty_t_staging_alv,
        lv_group_ok    TYPE abap_bool,
        lv_group_msg   TYPE string,
        lv_db_count    TYPE i,
        lv_scope_count TYPE i.

  FIELD-SYMBOLS <ls_alv> TYPE ty_staging_alv.

  CLEAR: cv_error_groups, cv_message.
  IF gt_staging_alv IS INITIAL.
    RETURN.
  ENDIF.

  PERFORM build_engine_keys USING gt_staging_alv CHANGING lt_keys.
  LOOP AT lt_keys INTO ls_key.
    REFRESH lt_group.
    PERFORM collect_group_key USING gt_staging_alv ls_key CHANGING lt_group.
    lv_scope_count = lines( lt_group ).
    IF lv_scope_count <= 0.
      CONTINUE.
    ENDIF.

    CLEAR lv_db_count.
    IF ls_key-record_key IS NOT INITIAL.
      SELECT COUNT( * ) FROM zbdc_staging_bup INTO @lv_db_count
        WHERE session_id = @ls_key-session_id
          AND record_key = @ls_key-record_key.
    ELSE.
      lv_db_count = lv_scope_count.
    ENDIF.
    IF lv_db_count > lv_scope_count.
      CONTINUE.
    ENDIF.

    CLEAR: lv_group_ok, lv_group_msg.
    PERFORM check_blank_contract_group
      USING    lt_group
      CHANGING lv_group_ok lv_group_msg.
    IF lv_group_ok = abap_true.
      CONTINUE.
    ENDIF.

    cv_error_groups = cv_error_groups + 1.
    IF cv_message IS INITIAL.
      cv_message = lv_group_msg.
    ENDIF.

    LOOP AT gt_staging_alv ASSIGNING <ls_alv>
      WHERE session_id = ls_key-session_id
        AND record_key = ls_key-record_key.
      IF <ls_alv>-status = gc_st_success OR
         <ls_alv>-status = gc_st_sm35q OR
         <ls_alv>-status = 'PROCESSING' OR
         <ls_alv>-status = 'SKIPPED'.
        CONTINUE.
      ENDIF.
      <ls_alv>-status = gc_st_error.
      IF <ls_alv>-error_msg IS INITIAL.
        <ls_alv>-error_msg = lv_group_msg.
      ELSEIF <ls_alv>-error_msg NS lv_group_msg.
        <ls_alv>-error_msg = |{ <ls_alv>-error_msg }; { lv_group_msg }|.
      ENDIF.
    ENDLOOP.
  ENDLOOP.
ENDFORM.

FORM validate_staging
  CHANGING cv_ok      TYPE abap_bool
           cv_message TYPE string.

  DATA: lt_map          TYPE ty_t_map,
        ls_map          TYPE zbdc_mapping_bup,
        lv_tcode        TYPE zbdc_prof_bup-tcode,
        lv_profile      TYPE zbdc_prof_bup-profile_name,
        lv_ver          TYPE zbdc_prof_bup-profile_ver,
        lv_found        TYPE abap_bool,
        lv_val          TYPE string,
        lv_normalized   TYPE bdcdata-fval,
        lv_format_msg   TYPE string,
        lv_format_ok    TYPE abap_bool,
        lv_value_kind   TYPE string,
        lv_push_policy  TYPE string,
        lv_format_policy TYPE string,
        lv_pad_length   TYPE i,
        lv_pad_char     TYPE string,
        lv_conv_exit    TYPE string,
        lv_ddic_length  TYPE i,
        lv_gui_value     TYPE string,
        lv_gui_applied   TYPE abap_bool,
        lv_gui_ok        TYPE abap_bool,
        lv_gui_msg       TYPE string,
        ls_scol         TYPE lvc_s_scol,
        lv_error_rows   TYPE i.

  FIELD-SYMBOLS: <ls_alv> TYPE ty_staging_alv,
                 <lv_any> TYPE any.

  CLEAR: cv_ok, cv_message.
  IF gt_staging IS INITIAL.
    MESSAGE ID 'ZBDC' TYPE 'S' NUMBER '409' INTO cv_message.
    RETURN.
  ENDIF.

  DATA: lv_ctx_ok  TYPE abap_bool,
        lv_ctx_msg TYPE string.
  PERFORM verify_loaded_ctx
    USING    p_transaction
    CHANGING lv_ctx_ok lv_ctx_msg.
  IF lv_ctx_ok <> abap_true.
    cv_message = lv_ctx_msg.
    RETURN.
  ENDIF.

  PERFORM prepare_alv_0400.

  LOOP AT gt_staging_alv ASSIGNING <ls_alv>.
 "Terminal/executing evidence is immutable. Explicit validation may only
 "re-evaluate non-terminal rows.
    IF <ls_alv>-status = gc_st_success OR
       <ls_alv>-status = gc_st_sm35q OR
       <ls_alv>-status = 'PROCESSING' OR
       <ls_alv>-status = 'SKIPPED'.
      CONTINUE.
    ENDIF.

    <ls_alv>-status = gc_st_ready.
    CLEAR: <ls_alv>-error_msg, <ls_alv>-cell_colors.

    CLEAR: lv_tcode, lv_profile, lv_ver, lv_found.
    PERFORM resolve_session_context
      USING    <ls_alv>-session_id
      CHANGING lv_tcode lv_profile lv_ver lv_found.
    IF lv_found <> abap_true OR lv_tcode <> <ls_alv>-tcode.
      <ls_alv>-status = gc_st_error.
      <ls_alv>-error_msg =
        'Frozen certified session contract is missing or does not match the staging TCODE.'.
      lv_error_rows = lv_error_rows + 1.
      CONTINUE.
    ENDIF.

    REFRESH lt_map.
    SELECT *
      FROM zbdc_mapping_bup
      INTO TABLE @lt_map
      WHERE tcode        = @lv_tcode
        AND profile_name = @lv_profile
        AND profile_ver  = @lv_ver.
    IF lt_map IS INITIAL.
      <ls_alv>-status = gc_st_error.
      <ls_alv>-error_msg = |Frozen profile { lv_profile } v{ lv_ver } has no mapping.|.
      lv_error_rows = lv_error_rows + 1.
      CONTINUE.
    ENDIF.

 "Blank eligibility is not derived from Mapping/Field-Guide MANDATORY.
 "Upload/Ingest and mutable Staging share one fail-closed structural proof.

    LOOP AT lt_map INTO ls_map WHERE bdc_field IS NOT INITIAL.
      ASSIGN COMPONENT ls_map-staging_field OF STRUCTURE <ls_alv> TO <lv_any>.
      IF sy-subrc <> 0 OR <lv_any> IS NOT ASSIGNED.
        CONTINUE.
      ENDIF.

      lv_val = |{ <lv_any> }|.
      CONDENSE lv_val.
      IF lv_val IS INITIAL.
        CONTINUE.
      ENDIF.

      CLEAR: lv_normalized, lv_format_msg, lv_format_ok,
             lv_value_kind, lv_push_policy, lv_format_policy,
             lv_pad_length, lv_pad_char, lv_conv_exit, lv_ddic_length.
      PERFORM read_map_runtime_rule
        USING    ls_map ls_map-bdc_field
        CHANGING lv_value_kind lv_push_policy
                 lv_format_policy lv_pad_length lv_pad_char
                 lv_conv_exit lv_ddic_length.

      IF lv_push_policy = gc_push_skip OR lv_value_kind = gc_sem_skip_bdc.
        CONTINUE.
      ENDIF.

 "resolve the value at Validate time, not only inside the BDC
 "builder. End users may keep SAP GUI display text in the upload; READY
 "rows are normalized once to the technical key before any CT/SM35 side
 "effect. Ambiguous or unknown display values fail here.
      CLEAR: lv_gui_value, lv_gui_applied, lv_gui_ok, lv_gui_msg.
      PERFORM gui_bdc_key_cached
        USING    ls_map-bdc_field lv_val
        CHANGING lv_gui_value lv_gui_applied lv_gui_ok lv_gui_msg.
      IF lv_gui_ok <> abap_true.
        <ls_alv>-status = gc_st_error.
        lv_format_msg = lv_gui_msg.
        IF lv_format_msg IS INITIAL.
          lv_format_msg =
            |SAP GUI value could not be resolved for { ls_map-source_column } ({ ls_map-bdc_field }).|.
        ENDIF.
      ELSE.
        IF lv_gui_applied = abap_true.
          lv_val = lv_gui_value.
        ENDIF.
        PERFORM format_contract_value
          USING    ls_map-bdc_field lv_val lv_value_kind ls_map-source_column
                   lv_format_policy lv_pad_length lv_pad_char lv_conv_exit
          CHANGING lv_normalized lv_format_ok lv_format_msg.
      ENDIF.

      IF lv_gui_ok <> abap_true OR lv_format_ok <> abap_true.
        <ls_alv>-status = gc_st_error.
        IF lv_format_msg IS INITIAL.
          lv_format_msg =
            |Invalid value for { ls_map-source_column } ({ ls_map-bdc_field }).|.
        ENDIF.
        IF <ls_alv>-error_msg IS INITIAL.
          <ls_alv>-error_msg = lv_format_msg.
        ELSE.
          <ls_alv>-error_msg = |{ <ls_alv>-error_msg }; { lv_format_msg }|.
        ENDIF.
        CLEAR ls_scol.
        ls_scol-fname = ls_map-staging_field.
        ls_scol-color-col = 6.
        ls_scol-color-int = 1.
        APPEND ls_scol TO <ls_alv>-cell_colors.
      ELSEIF lv_gui_applied = abap_true OR lv_normalized <> lv_val.
 "If a GUI display text resolved to a technical key, persist the
 "technical formatted value into staging even when formatter output
 "equals LV_VAL. LV_VAL already holds the resolved key at this point.
        <lv_any> = lv_normalized.
      ENDIF.
    ENDLOOP.

    IF <ls_alv>-status = gc_st_error.
      lv_error_rows = lv_error_rows + 1.
    ENDIF.
  ENDLOOP.

  DATA: lv_group_gate_ok     TYPE abap_bool,
        lv_group_error_count TYPE i,
        lv_group_gate_msg    TYPE string,
        lv_blank_error_count TYPE i,
        lv_blank_gate_msg    TYPE string,
        lv_rules_ok          TYPE abap_bool,
        lv_rules_msg         TYPE string.

  CLEAR: lv_blank_error_count, lv_blank_gate_msg.
  PERFORM apply_blank_contract_staging
    CHANGING lv_blank_error_count lv_blank_gate_msg.

 "Business Key duplicates are allowed in Preview. The Staging boundary is
 "where we prove whether one frozen recording can legally consume N rows.
  CLEAR: lv_group_gate_ok, lv_group_error_count, lv_group_gate_msg.
  PERFORM validate_all_group_cardinality
    CHANGING lv_group_gate_ok lv_group_error_count lv_group_gate_msg.
  IF lv_group_gate_ok <> abap_true.
    ROLLBACK WORK.
    cv_message = lv_group_gate_msg.
    RETURN.
  ENDIF.

  PERFORM apply_dynamic_rules
    CHANGING lv_rules_ok lv_rules_msg.
  IF lv_rules_ok <> abap_true.
    ROLLBACK WORK.
    cv_message = lv_rules_msg.
    RETURN.
  ENDIF.

  CLEAR lv_error_rows.
  LOOP AT gt_staging_alv INTO DATA(ls_validated_row)
    WHERE status = gc_st_error.
    lv_error_rows = lv_error_rows + 1.
  ENDLOOP.

  PERFORM sync_staging_from_alv.
  PERFORM write_structured_errors.

  MODIFY zbdc_staging_bup FROM TABLE gt_staging.
  IF sy-subrc <> 0.
    ROLLBACK WORK.
    MESSAGE ID 'ZBDC' TYPE 'S' NUMBER '410' INTO cv_message.
    RETURN.
  ENDIF.

  PERFORM upd_all_rt_sess_sum.
  COMMIT WORK AND WAIT.

  PERFORM prepare_alv_0400.
  cv_ok = abap_true.
  IF lv_error_rows > 0.
    IF lv_group_error_count > 0 AND lv_group_gate_msg IS NOT INITIAL.
      cv_message =
        |{ lv_group_gate_msg } Total invalid staging rows: { lv_error_rows }.|.
    ELSE.
      MESSAGE ID 'ZBDC' TYPE 'S' NUMBER '411'
        WITH lv_error_rows INTO cv_message.
    ENDIF.
  ELSE.
    MESSAGE ID 'ZBDC' TYPE 'S' NUMBER '412' INTO cv_message.
  ENDIF.
ENDFORM.

FORM resolve_edit_context
  USING    iv_session_id TYPE zbdc_staging_bup-session_id
  CHANGING cv_tcode      TYPE zbdc_prof_bup-tcode
           cv_profile    TYPE zbdc_prof_bup-profile_name
           cv_ver        TYPE zbdc_prof_bup-profile_ver
           cv_ok         TYPE abap_bool
           cv_message    TYPE string.

  DATA: ls_session   TYPE zbdc_session_bup,
        lv_prof      TYPE zbdc_prof_bup-profile_name,
        lv_map       TYPE zbdc_mapping_bup-profile_name.

  CLEAR: cv_tcode, cv_profile, cv_ver, cv_ok, cv_message.
  IF iv_session_id IS INITIAL.
    cv_message = 'Session ID is missing for correction context.'.
    RETURN.
  ENDIF.

  SELECT SINGLE * FROM zbdc_session_bup INTO @ls_session
    WHERE session_id = @iv_session_id.
  IF sy-subrc <> 0 OR
     ls_session-tcode IS INITIAL OR
     ls_session-profile_name IS INITIAL OR
     ls_session-profile_ver IS INITIAL.
    cv_message = |Session { iv_session_id } has no exact TCode/Profile/Version owner for correction.|.
    RETURN.
  ENDIF.

  SELECT SINGLE profile_name FROM zbdc_prof_bup INTO @lv_prof
    WHERE tcode        = @ls_session-tcode
      AND profile_name = @ls_session-profile_name
      AND profile_ver  = @ls_session-profile_ver.
  IF sy-subrc <> 0.
    cv_message = |Exact profile owner { ls_session-tcode }/{ ls_session-profile_name } v{ ls_session-profile_ver } no longer exists.|.
    RETURN.
  ENDIF.

  SELECT SINGLE profile_name FROM zbdc_mapping_bup INTO @lv_map
    WHERE tcode        = @ls_session-tcode
      AND profile_name = @ls_session-profile_name
      AND profile_ver  = @ls_session-profile_ver.
  IF sy-subrc <> 0.
    cv_message = |Exact mapping owner { ls_session-profile_name } v{ ls_session-profile_ver } is missing.|.
    RETURN.
  ENDIF.

  cv_tcode   = ls_session-tcode.
  cv_profile = ls_session-profile_name.
  cv_ver     = ls_session-profile_ver.
  cv_ok      = abap_true.
ENDFORM.

FORM ensure_exec_contract
  USING    iv_session_id     TYPE zbdc_staging_bup-session_id
           iv_expected_tcode TYPE zbdc_prof_bup-tcode
  CHANGING cv_ok             TYPE abap_bool
           cv_message        TYPE string.

  DATA: lv_tcode    TYPE zbdc_prof_bup-tcode,
        lv_profile  TYPE zbdc_prof_bup-profile_name,
        lv_ver      TYPE zbdc_prof_bup-profile_ver,
        lv_found    TYPE abap_bool,
        lv_edit_ok  TYPE abap_bool,
        lv_freeze_ok TYPE abap_bool,
        lv_msg      TYPE string.

  CLEAR: cv_ok, cv_message.

  PERFORM resolve_session_context
    USING    iv_session_id
    CHANGING lv_tcode lv_profile lv_ver lv_found.
  IF lv_found = abap_true AND lv_tcode = iv_expected_tcode.
    cv_ok = abap_true.
    RETURN.
  ENDIF.

  CLEAR: lv_tcode, lv_profile, lv_ver, lv_edit_ok, lv_msg.
  PERFORM resolve_edit_context
    USING    iv_session_id
    CHANGING lv_tcode lv_profile lv_ver lv_edit_ok lv_msg.
  IF lv_edit_ok <> abap_true OR lv_tcode <> iv_expected_tcode.
    IF lv_msg IS INITIAL.
      lv_msg = 'Exact retry execution owner could not be resolved.'.
    ENDIF.
    cv_message = lv_msg.
    RETURN.
  ENDIF.

 "Complete only blank proof fields for this exact existing owner.
  p_transaction     = lv_tcode.
  txtp_profile_name = lv_profile.
  gv_profile_ver    = lv_ver.
  CLEAR: lv_freeze_ok, lv_msg.
  PERFORM freeze_session_contract
    USING    iv_session_id
    CHANGING lv_freeze_ok lv_msg.
  IF lv_freeze_ok <> abap_true.
    cv_message = lv_msg.
    RETURN.
  ENDIF.

  CLEAR: lv_tcode, lv_profile, lv_ver, lv_found.
  PERFORM resolve_session_context
    USING    iv_session_id
    CHANGING lv_tcode lv_profile lv_ver lv_found.
  IF lv_found <> abap_true OR lv_tcode <> iv_expected_tcode.
    cv_message = 'Correction was saved, but the exact Script/Hash execution proof is still incomplete.'.
    RETURN.
  ENDIF.

  cv_ok = abap_true.
ENDFORM.

FORM validate_retry_group
  USING    pt_group   TYPE ty_t_staging_alv
  CHANGING ct_valid   TYPE ty_t_staging_alv
           cv_ok      TYPE abap_bool
           cv_message TYPE string.

  DATA: lt_map           TYPE ty_t_map,
        ls_map           TYPE zbdc_mapping_bup,
        lv_tcode         TYPE zbdc_prof_bup-tcode,
        lv_profile       TYPE zbdc_prof_bup-profile_name,
        lv_ver           TYPE zbdc_prof_bup-profile_ver,
        lv_found         TYPE abap_bool,
        lv_val           TYPE string,
        lv_msg           TYPE string,
        lv_normalized    TYPE bdcdata-fval,
        lv_format_msg    TYPE string,
        lv_format_ok     TYPE abap_bool,
        lv_value_kind    TYPE string,
        lv_push_policy   TYPE string,
        lv_format_policy TYPE string,
        lv_pad_length    TYPE i,
        lv_pad_char      TYPE string,
        lv_conv_exit     TYPE string,
        lv_ddic_length   TYPE i,
        lv_gui_value     TYPE string,
        lv_gui_applied   TYPE abap_bool,
        lv_gui_ok        TYPE abap_bool,
        lv_gui_msg       TYPE string,
        lv_rules_ok      TYPE abap_bool,
        lv_rules_msg     TYPE string,
        lv_card_ok       TYPE abap_bool,
        lv_card_msg      TYPE string,
        lt_saved_alv     TYPE ty_t_staging_alv,
        ls_scol          TYPE lvc_s_scol,
        lv_errors        TYPE i,
        lv_group         TYPE zbdc_staging_bup-record_key.

  FIELD-SYMBOLS: <ls_alv> TYPE ty_staging_alv,
                 <lv_any> TYPE any.

  CLEAR: cv_ok, cv_message.
  ct_valid = pt_group.
  IF ct_valid IS INITIAL.
    cv_message = 'Retry validation has no staging rows for the selected group.'.
    RETURN.
  ENDIF.

  READ TABLE ct_valid INTO DATA(ls_first) INDEX 1.
  IF sy-subrc <> 0.
    cv_message = 'Retry validation could not read the selected business group.'.
    RETURN.
  ENDIF.
  lv_group = ls_first-record_key.

  LOOP AT ct_valid ASSIGNING <ls_alv>.
    IF <ls_alv>-session_id <> ls_first-session_id OR
       <ls_alv>-record_key <> ls_first-record_key OR
       <ls_alv>-tcode      <> ls_first-tcode.
      cv_message = 'Retry validation scope contains mixed session/group/TCODE rows.'.
      RETURN.
    ENDIF.

    <ls_alv>-status = gc_st_ready.
    CLEAR: <ls_alv>-error_msg, <ls_alv>-last_error, <ls_alv>-cell_colors.

    CLEAR: lv_tcode, lv_profile, lv_ver, lv_found.
    PERFORM resolve_session_context
      USING    <ls_alv>-session_id
      CHANGING lv_tcode lv_profile lv_ver lv_found.
    IF lv_found <> abap_true.
 "correction validation needs the exact persisted Mapping owner,
 "not yet the executable Script/Hash proof. Legacy/preview sessions may
 "therefore validate safely by TCode/Profile/Version first; READY promotion
 "later requires ensure_exec_contract to prove/complete Script+Hash.
      CLEAR lv_msg.
      PERFORM resolve_edit_context
        USING    <ls_alv>-session_id
        CHANGING lv_tcode lv_profile lv_ver lv_found lv_msg.
    ENDIF.
    IF lv_found <> abap_true OR lv_tcode <> <ls_alv>-tcode.
      <ls_alv>-status = gc_st_error.
      IF lv_msg IS INITIAL.
        lv_msg = 'Exact session TCode/Profile/Version mapping context is missing or does not match the staging TCODE.'.
      ENDIF.
      <ls_alv>-error_msg = lv_msg.
      CONTINUE.
    ENDIF.

    REFRESH lt_map.
    SELECT *
      FROM zbdc_mapping_bup
      INTO TABLE @lt_map
      WHERE tcode        = @lv_tcode
        AND profile_name = @lv_profile
        AND profile_ver  = @lv_ver.
    IF lt_map IS INITIAL.
      <ls_alv>-status = gc_st_error.
      <ls_alv>-error_msg = |Frozen profile { lv_profile } v{ lv_ver } has no mapping.|.
      CONTINUE.
    ENDIF.

    "Retry/Edit uses the same structural blank proof as Upload; Required/
    "Optional metadata is not recreated here.

    LOOP AT lt_map INTO ls_map WHERE bdc_field IS NOT INITIAL.
      UNASSIGN <lv_any>.
      ASSIGN COMPONENT ls_map-staging_field OF STRUCTURE <ls_alv> TO <lv_any>.
      IF sy-subrc <> 0 OR <lv_any> IS NOT ASSIGNED.
        CONTINUE.
      ENDIF.

      lv_val = |{ <lv_any> }|.
      CONDENSE lv_val.
      IF lv_val IS INITIAL.
        CONTINUE.
      ENDIF.

      CLEAR: lv_normalized, lv_format_msg, lv_format_ok,
             lv_value_kind, lv_push_policy, lv_format_policy,
             lv_pad_length, lv_pad_char, lv_conv_exit, lv_ddic_length.
      PERFORM read_map_runtime_rule
        USING    ls_map ls_map-bdc_field
        CHANGING lv_value_kind lv_push_policy
                 lv_format_policy lv_pad_length lv_pad_char
                 lv_conv_exit lv_ddic_length.

      IF lv_push_policy = gc_push_skip OR lv_value_kind = gc_sem_skip_bdc.
        CONTINUE.
      ENDIF.

      CLEAR: lv_gui_value, lv_gui_applied, lv_gui_ok, lv_gui_msg.
      PERFORM gui_bdc_key_cached
        USING    ls_map-bdc_field lv_val
        CHANGING lv_gui_value lv_gui_applied lv_gui_ok lv_gui_msg.
      IF lv_gui_ok <> abap_true.
        <ls_alv>-status = gc_st_error.
        lv_format_msg = lv_gui_msg.
        IF lv_format_msg IS INITIAL.
          lv_format_msg =
            |SAP GUI value could not be resolved for { ls_map-source_column } ({ ls_map-bdc_field }).|.
        ENDIF.
      ELSE.
        IF lv_gui_applied = abap_true.
          lv_val = lv_gui_value.
        ENDIF.
        PERFORM format_contract_value
          USING    ls_map-bdc_field lv_val lv_value_kind ls_map-source_column
                   lv_format_policy lv_pad_length lv_pad_char lv_conv_exit
          CHANGING lv_normalized lv_format_ok lv_format_msg.
      ENDIF.

      IF lv_gui_ok <> abap_true OR lv_format_ok <> abap_true.
        <ls_alv>-status = gc_st_error.
        IF lv_format_msg IS INITIAL.
          lv_format_msg =
            |Invalid value for { ls_map-source_column } ({ ls_map-bdc_field }).|.
        ENDIF.
        IF <ls_alv>-error_msg IS INITIAL.
          <ls_alv>-error_msg = lv_format_msg.
        ELSE.
          <ls_alv>-error_msg = |{ <ls_alv>-error_msg }; { lv_format_msg }|.
        ENDIF.
        CLEAR ls_scol.
        ls_scol-fname = ls_map-staging_field.
        ls_scol-color-col = 6.
        ls_scol-color-int = 1.
        APPEND ls_scol TO <ls_alv>-cell_colors.
      ELSEIF lv_gui_applied = abap_true OR lv_normalized <> lv_val.
        <lv_any> = lv_normalized.
      ENDIF.
    ENDLOOP.
  ENDLOOP.

  CLEAR: lv_card_ok, lv_card_msg.
  PERFORM check_blank_contract_group
    USING    ct_valid
    CHANGING lv_card_ok lv_card_msg.
  IF lv_card_ok <> abap_true.
    LOOP AT ct_valid ASSIGNING <ls_alv>.
      <ls_alv>-status = gc_st_error.
      IF <ls_alv>-error_msg IS INITIAL.
        <ls_alv>-error_msg = lv_card_msg.
      ELSEIF <ls_alv>-error_msg NS lv_card_msg.
        <ls_alv>-error_msg = |{ <ls_alv>-error_msg }; { lv_card_msg }|.
      ENDIF.
    ENDLOOP.
    cv_message = lv_card_msg.
    RETURN.
  ENDIF.

 "Dynamic validation rules operate on GT_STAGING_ALV. Run them against an
 "isolated exact-group projection, then restore the caller's full UI scope.
  lt_saved_alv = gt_staging_alv.
  gt_staging_alv = ct_valid.
  PERFORM apply_dynamic_rules CHANGING lv_rules_ok lv_rules_msg.
  ct_valid = gt_staging_alv.
  gt_staging_alv = lt_saved_alv.

  IF lv_rules_ok <> abap_true.
    cv_message = lv_rules_msg.
    IF cv_message IS INITIAL.
      cv_message = 'Dynamic validation could not be completed for the retry group.'.
    ENDIF.
    RETURN.
  ENDIF.

 "Retry cannot bypass the same Business Key cardinality proof enforced at
 "the Staging boundary. A corrected group must still match its frozen
 "recording's proven single-row/multi-row contract.
  CLEAR: lv_card_ok, lv_card_msg.
  PERFORM check_group_cardinality_proof
    USING    ct_valid
    CHANGING lv_card_ok lv_card_msg.
  IF lv_card_ok <> abap_true.
    LOOP AT ct_valid ASSIGNING <ls_alv>.
      <ls_alv>-status = gc_st_error.
      IF <ls_alv>-error_msg IS INITIAL.
        <ls_alv>-error_msg = lv_card_msg.
      ELSEIF <ls_alv>-error_msg NS lv_card_msg.
        <ls_alv>-error_msg = |{ <ls_alv>-error_msg }; { lv_card_msg }|.
      ENDIF.
    ENDLOOP.
    cv_message = lv_card_msg.
    RETURN.
  ENDIF.

  LOOP AT ct_valid INTO DATA(ls_check) WHERE status = gc_st_error.
    lv_errors = lv_errors + 1.
    IF cv_message IS INITIAL.
      cv_message = ls_check-error_msg.
    ENDIF.
  ENDLOOP.

  IF lv_errors > 0.
    IF cv_message IS INITIAL.
      cv_message = |Pre-execution validation found { lv_errors } invalid row(s) in { lv_group }.|.
    ELSE.
      cv_message = |Pre-execution validation failed for { lv_group }: { cv_message }|.
    ENDIF.
    RETURN.
  ENDIF.

  cv_ok = abap_true.
  cv_message = |Pre-execution validation passed for { lv_group }. Runtime success is confirmed only by retry execution.|.
ENDFORM.

FORM read_rules
  CHANGING ct_rule    TYPE ty_t_z16_rule
           cv_ok      TYPE abap_bool
           cv_message TYPE string.

  DATA: lv_exists     TYPE abap_bool,
        lr_tab        TYPE REF TO data,
        lv_text       TYPE string,
        lv_tcode      TYPE string,
        lv_active     TYPE string,
        ls_rule       TYPE ty_z16_rule,
        lv_target_ok  TYPE abap_bool,
        lv_target_msg TYPE string.

  FIELD-SYMBOLS: <lt_any> TYPE STANDARD TABLE,
                 <ls_any> TYPE any.

  REFRESH ct_rule.
  CLEAR cv_message.
  cv_ok = abap_true.

 "consume explicit ACTIVE validation metadata. The table remains an
 "optional extension: if it is not installed, frozen mapping/format checks
 "still run. But an installed active rule is never silently ignored.
  PERFORM table_exists USING gc_z16_tab_vrule CHANGING lv_exists.
  IF lv_exists <> abap_true.
    RETURN.
  ENDIF.

  TRY.
      CREATE DATA lr_tab TYPE STANDARD TABLE OF (gc_z16_tab_vrule).
      ASSIGN lr_tab->* TO <lt_any>.
      SELECT * FROM (gc_z16_tab_vrule) INTO TABLE @<lt_any>.
    CATCH cx_root INTO DATA(lx_read).
      cv_ok = abap_false.
      DATA(lv_zmsg413_text) = lx_read->get_text( ).
      MESSAGE ID 'ZBDC' TYPE 'S' NUMBER '413'
        WITH lv_zmsg413_text INTO cv_message.
      RETURN.
  ENDTRY.

  LOOP AT <lt_any> ASSIGNING <ls_any>.
    CLEAR: ls_rule, lv_text, lv_tcode, lv_active.

    PERFORM get_optional_comp USING <ls_any> 'IS_ACTIVE' CHANGING lv_active.
    IF lv_active IS INITIAL.
      PERFORM get_optional_comp USING <ls_any> 'ACTIVE' CHANGING lv_active.
    ENDIF.
    TRANSLATE lv_active TO UPPER CASE.
    IF lv_active <> 'X' AND lv_active <> '1' AND lv_active <> 'Y'.
      CONTINUE.
    ENDIF.
    ls_rule-is_active = 'X'.

    CLEAR lv_text.
    PERFORM get_optional_comp USING <ls_any> 'RULE_ID' CHANGING lv_text.
    ls_rule-rule_id = lv_text.

    CLEAR lv_tcode.
    PERFORM get_optional_comp USING <ls_any> 'TCODE' CHANGING lv_tcode.
    IF lv_tcode IS INITIAL.
      PERFORM get_optional_comp USING <ls_any> 'TRANSACTION' CHANGING lv_tcode.
    ENDIF.
    TRANSLATE lv_tcode TO UPPER CASE.
    CONDENSE lv_tcode NO-GAPS.
    ls_rule-tcode = lv_tcode.

    CLEAR lv_text.
    PERFORM get_optional_comp USING <ls_any> 'LAYER' CHANGING lv_text.
    TRANSLATE lv_text TO UPPER CASE.
    ls_rule-layer = lv_text.

    CLEAR lv_text.
    PERFORM get_optional_comp USING <ls_any> 'FIELDNAME' CHANGING lv_text.
    IF lv_text IS INITIAL.
      PERFORM get_optional_comp USING <ls_any> 'FIELD_NAME' CHANGING lv_text.
    ENDIF.
    IF lv_text IS INITIAL.
      PERFORM get_optional_comp USING <ls_any> 'STAGING_FIELD' CHANGING lv_text.
    ENDIF.
    TRANSLATE lv_text TO UPPER CASE.
    CONDENSE lv_text NO-GAPS.
    ls_rule-fieldname = lv_text.

    CLEAR lv_text.
    PERFORM get_optional_comp USING <ls_any> 'RULE_TYPE' CHANGING lv_text.
    TRANSLATE lv_text TO UPPER CASE.
    CONDENSE lv_text NO-GAPS.
    CASE lv_text.
      WHEN 'EXIST_TABLE' OR 'EXISTS_TABLE' OR 'TABLE_EXISTS'
        OR 'LOOKUP_EXISTS' OR 'MASTER_EXISTS'.
        lv_text = 'VALUE_EXISTS'.
      WHEN 'GREATER_THAN_ZERO' OR 'NUMERIC_POSITIVE'.
        lv_text = 'POSITIVE'.
      WHEN 'EXIST_PAIR' OR 'EXISTS_PAIR' OR 'PAIR_EXISTS'
        OR 'CHECK_PAIR' OR 'TABLE_PAIR'.
 "No second lookup-field member exists in the normalized runtime type.
 "Do not infer it from a business field name.
        lv_text = 'SKIP_UNSUPPORTED'.
    ENDCASE.
    ls_rule-rule_type = lv_text.

    CLEAR lv_text.
    PERFORM get_optional_comp USING <ls_any> 'SEVERITY' CHANGING lv_text.
    TRANSLATE lv_text TO UPPER CASE.
    CONDENSE lv_text NO-GAPS.
    IF lv_text IS INITIAL.
      lv_text = 'E'.
    ENDIF.
    ls_rule-severity = lv_text.

    CLEAR lv_text.
    PERFORM get_optional_comp USING <ls_any> 'CHECK_TABLE' CHANGING lv_text.
    TRANSLATE lv_text TO UPPER CASE.
    CONDENSE lv_text NO-GAPS.
    ls_rule-check_table = lv_text.

    CLEAR lv_text.
    PERFORM get_optional_comp USING <ls_any> 'CHECK_FIELD1' CHANGING lv_text.
    TRANSLATE lv_text TO UPPER CASE.
    CONDENSE lv_text NO-GAPS.
    ls_rule-check_field1 = lv_text.

    CLEAR lv_text. PERFORM get_optional_comp USING <ls_any> 'PARAM1' CHANGING lv_text. ls_rule-param1 = lv_text.
    CLEAR lv_text. PERFORM get_optional_comp USING <ls_any> 'PARAM2' CHANGING lv_text. ls_rule-param2 = lv_text.
    CLEAR lv_text. PERFORM get_optional_comp USING <ls_any> 'PARAM3' CHANGING lv_text. ls_rule-param3 = lv_text.
    CLEAR lv_text. PERFORM get_optional_comp USING <ls_any> 'MESSAGE_TEXT' CHANGING lv_text. ls_rule-message_text = lv_text.
    CLEAR lv_text. PERFORM get_optional_comp USING <ls_any> 'HINT_TEXT' CHANGING lv_text. ls_rule-hint_text = lv_text.
    CLEAR lv_text. PERFORM get_optional_comp USING <ls_any> 'SORT_ORDER' CHANGING lv_text.
    IF lv_text IS NOT INITIAL. ls_rule-sort_order = lv_text. ENDIF.

    IF ls_rule-fieldname IS INITIAL OR ls_rule-rule_type IS INITIAL.
      CONTINUE.
    ENDIF.

    IF ls_rule-rule_type = 'MANDATORY' OR
       ls_rule-rule_type = 'REQUIRED' OR
       ls_rule-rule_type = 'NOT_INITIAL'.
      ls_rule-rule_type = 'SKIP_UNSUPPORTED'.
    ENDIF.

    IF ls_rule-rule_type <> 'VALUE_EXISTS' AND
       ls_rule-rule_type <> 'EXISTS' AND
       ls_rule-rule_type <> 'CHECK_TABLE' AND
       ls_rule-rule_type <> 'POSITIVE' AND
       ls_rule-rule_type <> 'GT_ZERO' AND
       ls_rule-rule_type <> 'SKIP_UNSUPPORTED'.
      ls_rule-rule_type = 'SKIP_UNSUPPORTED'.
    ENDIF.

    IF ls_rule-rule_type = 'VALUE_EXISTS' OR
       ls_rule-rule_type = 'EXISTS' OR
       ls_rule-rule_type = 'CHECK_TABLE'.
      IF ls_rule-check_table IS INITIAL OR ls_rule-check_field1 IS INITIAL.
        cv_ok = abap_false.
        MESSAGE ID 'ZBDC' TYPE 'S' NUMBER '414'
          WITH ls_rule-rule_id INTO cv_message.
        REFRESH ct_rule.
        RETURN.
      ENDIF.
      CLEAR: lv_target_ok, lv_target_msg.
      PERFORM validate_check_target
        USING    ls_rule-check_table ls_rule-check_field1
        CHANGING lv_target_ok lv_target_msg.
      IF lv_target_ok <> abap_true.
        cv_ok = abap_false.
        MESSAGE ID 'ZBDC' TYPE 'S' NUMBER '415'
          WITH ls_rule-rule_id lv_target_msg INTO cv_message.
        REFRESH ct_rule.
        RETURN.
      ENDIF.
    ENDIF.

    APPEND ls_rule TO ct_rule.
  ENDLOOP.

  SORT ct_rule BY sort_order rule_id.
ENDFORM.

FORM validate_check_target
  USING    iv_table   TYPE tabname
           iv_field   TYPE fieldname
  CHANGING cv_ok      TYPE abap_bool
           cv_message TYPE string.

  DATA: lv_tabclass TYPE dd02l-tabclass,
        lv_field    TYPE dd03l-fieldname.

  CLEAR: cv_ok, cv_message.
  IF iv_table IS INITIAL OR iv_field IS INITIAL.
    MESSAGE ID 'ZBDC' TYPE 'S' NUMBER '416' INTO cv_message.
    RETURN.
  ENDIF.

  SELECT SINGLE tabclass
    FROM dd02l
    INTO @lv_tabclass
    WHERE tabname  = @iv_table
      AND as4local = 'A'.
  IF sy-subrc <> 0 OR
     ( lv_tabclass <> 'TRANSP' AND lv_tabclass <> 'VIEW' ).
    MESSAGE ID 'ZBDC' TYPE 'S' NUMBER '417'
      WITH iv_table INTO cv_message.
    RETURN.
  ENDIF.

  SELECT SINGLE fieldname
    FROM dd03l
    INTO @lv_field
    WHERE tabname   = @iv_table
      AND fieldname = @iv_field
      AND as4local  = 'A'.
  IF sy-subrc <> 0.
    MESSAGE ID 'ZBDC' TYPE 'S' NUMBER '418'
      WITH iv_field iv_table INTO cv_message.
    RETURN.
  ENDIF.

  cv_ok = abap_true.
ENDFORM.

FORM check_dynamic_exists
  USING    iv_table    TYPE tabname
           iv_field    TYPE fieldname
           iv_value    TYPE string
  CHANGING cv_query_ok TYPE abap_bool
           cv_exists   TYPE abap_bool
           cv_message  TYPE string.

  DATA: lv_where      TYPE string,
        lv_value      TYPE string,
        lv_count      TYPE i,
        lv_target_ok  TYPE abap_bool,
        lv_target_msg TYPE string.

  CLEAR: cv_query_ok, cv_exists, cv_message.
  IF iv_table IS INITIAL OR iv_field IS INITIAL OR iv_value IS INITIAL.
    cv_query_ok = abap_true.
    RETURN.
  ENDIF.

  PERFORM validate_check_target
    USING    iv_table iv_field
    CHANGING lv_target_ok lv_target_msg.
  IF lv_target_ok <> abap_true.
    cv_message = lv_target_msg.
    RETURN.
  ENDIF.

  lv_value = iv_value.
  REPLACE ALL OCCURRENCES OF '''' IN lv_value WITH ''''''.
  lv_where = |{ iv_field } = '{ lv_value }'|.

  TRY.
      SELECT COUNT( * )
        FROM (iv_table)
        INTO @lv_count
        WHERE (lv_where).
      cv_query_ok = abap_true.
      IF lv_count > 0.
        cv_exists = abap_true.
      ENDIF.
    CATCH cx_root INTO DATA(lx_lookup).
 "A value that cannot be converted to the configured DDIC field is a
 "failed lookup for this row, not permission to pass validation.
      cv_query_ok = abap_true.
      CLEAR cv_exists.
      cv_message = lx_lookup->get_text( ).
  ENDTRY.
ENDFORM.

FORM apply_dynamic_rules
  CHANGING cv_ok      TYPE abap_bool
           cv_message TYPE string.

  DATA: lt_rule      TYPE ty_t_z16_rule,
        ls_rule      TYPE ty_z16_rule,
        lv_val       TYPE string,
        lv_msg       TYPE string,
        lv_rules_ok  TYPE abap_bool,
        lv_rules_msg TYPE string,
        lv_query_ok  TYPE abap_bool,
        lv_exists    TYPE abap_bool,
        lv_query_msg TYPE string,
        lv_failed    TYPE abap_bool,
        lv_num       TYPE decfloat34.

  FIELD-SYMBOLS: <ls_alv> TYPE ty_staging_alv,
                 <lv_any> TYPE any.

  CLEAR: cv_ok, cv_message.
  PERFORM read_rules
    CHANGING lt_rule lv_rules_ok lv_rules_msg.
  IF lv_rules_ok <> abap_true.
    cv_message = lv_rules_msg.
    RETURN.
  ENDIF.

  IF lt_rule IS INITIAL.
    cv_ok = abap_true.
    RETURN.
  ENDIF.

  LOOP AT gt_staging_alv ASSIGNING <ls_alv>.
 "Only READY rows are eligibility candidates. Do not rewrite terminal
 "execution evidence during a validation refresh.
    IF <ls_alv>-status <> gc_st_ready.
      CONTINUE.
    ENDIF.

    LOOP AT lt_rule INTO ls_rule.
      IF ls_rule-rule_type = 'SKIP_UNSUPPORTED'.
        CONTINUE.
      ENDIF.
      IF ls_rule-tcode IS NOT INITIAL AND ls_rule-tcode <> <ls_alv>-tcode.
        CONTINUE.
      ENDIF.

      UNASSIGN <lv_any>.
      ASSIGN COMPONENT ls_rule-fieldname OF STRUCTURE <ls_alv> TO <lv_any>.
      IF sy-subrc <> 0 OR <lv_any> IS NOT ASSIGNED.
 "Never guess a business field from column text.
        CONTINUE.
      ENDIF.

      lv_val = |{ <lv_any> }|.
      CONDENSE lv_val.
      CLEAR: lv_msg, lv_failed.
      IF ls_rule-message_text IS NOT INITIAL.
        lv_msg = ls_rule-message_text.
      ELSE.
        lv_msg = |Validation rule { ls_rule-rule_id } failed for { ls_rule-fieldname }.|.
      ENDIF.
      IF ls_rule-hint_text IS NOT INITIAL.
        lv_msg = |{ lv_msg } Fix: { ls_rule-hint_text }|.
      ENDIF.

      CASE ls_rule-rule_type.
        WHEN 'MANDATORY' OR 'REQUIRED' OR 'NOT_INITIAL'.
          CONTINUE.

        WHEN 'VALUE_EXISTS' OR 'EXISTS' OR 'CHECK_TABLE'.
          IF lv_val IS NOT INITIAL.
            CLEAR: lv_query_ok, lv_exists, lv_query_msg.
            PERFORM check_dynamic_exists
              USING    ls_rule-check_table ls_rule-check_field1 lv_val
              CHANGING lv_query_ok lv_exists lv_query_msg.
            IF lv_query_ok <> abap_true.
              MESSAGE ID 'ZBDC' TYPE 'S' NUMBER '419'
                WITH ls_rule-rule_id lv_query_msg INTO cv_message.
              RETURN.
            ENDIF.
            IF lv_exists <> abap_true.
              lv_failed = abap_true.
              IF lv_query_msg IS NOT INITIAL.
                lv_msg = |{ lv_msg } ({ lv_query_msg })|.
              ENDIF.
            ENDIF.
          ENDIF.

        WHEN 'POSITIVE' OR 'GT_ZERO'.
          IF lv_val IS NOT INITIAL.
            TRY.
                lv_num = lv_val.
                IF lv_num <= 0. lv_failed = abap_true. ENDIF.
              CATCH cx_root.
                lv_failed = abap_true.
            ENDTRY.
          ENDIF.
      ENDCASE.

      IF lv_failed = abap_true.
 "An explicit active rule is a pre-execution eligibility gate. A
 "configured warning is still kept out of READY; otherwise known-bad
 "data could be posted and later misclassified by runtime proof.
        IF ls_rule-severity = 'W'.
          lv_msg = |Validation warning blocks execution until reviewed: { lv_msg }|.
        ENDIF.
        PERFORM mark_row_error
          USING    ls_rule-fieldname lv_msg
          CHANGING <ls_alv>.
      ENDIF.
    ENDLOOP.
  ENDLOOP.

  cv_ok = abap_true.
ENDFORM.

FORM log_one_change USING iv_session TYPE any
                              iv_row     TYPE any
                              iv_tcode   TYPE any
                              iv_field   TYPE any
                              iv_old     TYPE any
                              iv_new     TYPE any
                              iv_action  TYPE any.
  DATA: lv_ok  TYPE abap_bool,
        lv_msg TYPE string.

  IF iv_old = iv_new.
    RETURN.
  ENDIF.

  "Retry correction keeps its historical fail-open behavior, but it now uses
  "the same DDIC-compatible append-only ID generator as Edit Staging.
  PERFORM insert_change_audit_row
    USING    iv_session iv_row iv_tcode iv_field iv_old iv_new iv_action
    CHANGING lv_ok lv_msg.
ENDFORM.
