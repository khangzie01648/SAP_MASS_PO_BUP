REPORT zbdc_mig_vscript_bup.

TABLES zbdc_prof_bup.

SELECT-OPTIONS s_tcode FOR zbdc_prof_bup-tcode.

PARAMETERS:
  p_test TYPE abap_bool AS CHECKBOX DEFAULT abap_true.

TYPES:
  BEGIN OF ty_log,
    tcode        TYPE zbdc_prof_bup-tcode,
    profile_name TYPE zbdc_prof_bup-profile_name,
    profile_ver  TYPE zbdc_prof_bup-profile_ver,
    result       TYPE char20,
    message      TYPE char255,
  END OF ty_log.

TYPES:
  ty_t_profile TYPE STANDARD TABLE OF zbdc_prof_bup
                 WITH DEFAULT KEY,
  ty_t_legacy  TYPE STANDARD TABLE OF zbdc_sct_def_bup
                 WITH DEFAULT KEY,
  ty_t_step    TYPE STANDARD TABLE OF zbdc_sct_ver_bup
                 WITH DEFAULT KEY,
  ty_t_log     TYPE STANDARD TABLE OF ty_log
                 WITH DEFAULT KEY.

DATA:
  gt_profiles TYPE ty_t_profile,
  gt_log      TYPE ty_t_log.

CONSTANTS:
  gc_result_test     TYPE char20 VALUE 'WOULD_MIGRATE',
  gc_result_done     TYPE char20 VALUE 'MIGRATED',
  gc_result_skip     TYPE char20 VALUE 'ALREADY_EXISTS',
  gc_result_blocked  TYPE char20 VALUE 'NEEDS_REIMPORT',
  gc_result_error    TYPE char20 VALUE 'ERROR',
  gc_header_status   TYPE char10 VALUE 'MAPPED'.

START-OF-SELECTION.

  PERFORM load_profiles.

  IF gt_profiles IS INITIAL.
    WRITE: / 'No profile was found for the selected TCODE range.'.
    RETURN.
  ENDIF.

  PERFORM migrate_profiles.
  PERFORM display_result.

*---------------------------------------------------------------------*
* Load registry profiles
*---------------------------------------------------------------------*
FORM load_profiles.

  REFRESH gt_profiles.

  SELECT *
    FROM zbdc_prof_bup
    INTO TABLE @gt_profiles
    WHERE tcode IN @s_tcode.

  SORT gt_profiles BY tcode profile_name profile_ver.

ENDFORM.

*---------------------------------------------------------------------*
* Process every profile separately
*---------------------------------------------------------------------*
FORM migrate_profiles.

  DATA:
    ls_profile TYPE zbdc_prof_bup.

  LOOP AT gt_profiles INTO ls_profile.
    PERFORM migrate_one_profile USING ls_profile.
  ENDLOOP.

ENDFORM.

*---------------------------------------------------------------------*
* Migrate exactly one profile
*---------------------------------------------------------------------*
FORM migrate_one_profile
  USING ps_profile TYPE zbdc_prof_bup.

  DATA:
    lt_legacy            TYPE ty_t_legacy,
    lt_steps             TYPE ty_t_step,
    ls_legacy            TYPE zbdc_sct_def_bup,
    ls_step              TYPE zbdc_sct_ver_bup,
    ls_header            TYPE zbdc_script_bup,
    lv_existing_script   TYPE zbdc_script_bup-script_id,
    lv_script_id         TYPE zbdc_script_bup-script_id,
    lv_tag_profile       TYPE zbdc_prof_bup-profile_name,
    lv_tag_version       TYPE zbdc_prof_bup-profile_ver,
    lv_profile_count     TYPE i,
    lv_invalid           TYPE abap_bool,
    lv_mixed             TYPE abap_bool,
    lv_message           TYPE char255,
    lv_timestamp         TYPE timestampl,
    lx_uuid              TYPE REF TO cx_uuid_error.

  CLEAR:
    lv_existing_script,
    lv_script_id,
    lv_tag_profile,
    lv_tag_version,
    lv_profile_count,
    lv_invalid,
    lv_mixed,
    lv_message.

*---------------------------------------------------------------------*
* Do not create another header for the same profile version
*---------------------------------------------------------------------*
  SELECT SINGLE script_id
    FROM zbdc_script_bup
    INTO @lv_existing_script
    WHERE tcode        = @ps_profile-tcode
      AND profile_name = @ps_profile-profile_name
      AND profile_ver  = @ps_profile-profile_ver.

  IF sy-subrc = 0 AND lv_existing_script IS NOT INITIAL.
    lv_message =
      |Script header { lv_existing_script } already exists.|.

    PERFORM append_log
      USING ps_profile
            gc_result_skip
            lv_message.
    RETURN.
  ENDIF.

*---------------------------------------------------------------------*
* Read the complete legacy script for this TCODE
*
* The legacy primary key is only:
* MANDT + TCODE + STEP_SEQ
*
* Therefore selecting only by PROFILE_NAME could hide mixed/overwritten
* rows. Always inspect the complete TCODE script before migration.
*---------------------------------------------------------------------*
  SELECT *
    FROM zbdc_sct_def_bup
    INTO TABLE @lt_legacy
    WHERE tcode = @ps_profile-tcode.

  IF lt_legacy IS INITIAL.
    lv_message =
      |No legacy script exists for TCODE { ps_profile-tcode }. Re-import SHDB recording.|.

    PERFORM append_log
      USING ps_profile
            gc_result_blocked
            lv_message.
    RETURN.
  ENDIF.

  SORT lt_legacy BY step_seq.

*---------------------------------------------------------------------*
* Count registered profiles for this TCODE
*---------------------------------------------------------------------*
  LOOP AT gt_profiles TRANSPORTING NO FIELDS
    WHERE tcode = ps_profile-tcode.
    lv_profile_count = lv_profile_count + 1.
  ENDLOOP.

*---------------------------------------------------------------------*
* Determine whether legacy rows carry one unambiguous profile owner
*---------------------------------------------------------------------*
  LOOP AT lt_legacy INTO ls_legacy.

    "Half-filled profile context is invalid.
    IF ( ls_legacy-profile_name IS INITIAL AND
         ls_legacy-profile_ver  IS NOT INITIAL )
       OR
       ( ls_legacy-profile_name IS NOT INITIAL AND
         ls_legacy-profile_ver  IS INITIAL ).

      lv_invalid = abap_true.
      EXIT.
    ENDIF.

    "Blank context is allowed only when this TCODE has exactly one profile.
    IF ls_legacy-profile_name IS INITIAL AND
       ls_legacy-profile_ver  IS INITIAL.
      CONTINUE.
    ENDIF.

    IF lv_tag_profile IS INITIAL.
      lv_tag_profile = ls_legacy-profile_name.
      lv_tag_version = ls_legacy-profile_ver.
    ELSEIF lv_tag_profile <> ls_legacy-profile_name OR
           lv_tag_version <> ls_legacy-profile_ver.
      lv_mixed = abap_true.
      EXIT.
    ENDIF.

  ENDLOOP.

  IF lv_invalid = abap_true.
    lv_message =
      |Legacy script contains partially filled Profile/Version fields. Re-import the SHDB recording.|.

    PERFORM append_log
      USING ps_profile
            gc_result_blocked
            lv_message.
    RETURN.
  ENDIF.

  IF lv_mixed = abap_true.
    lv_message =
      |Legacy script contains steps from multiple profiles. Automatic migration was blocked.|.

    PERFORM append_log
      USING ps_profile
            gc_result_blocked
            lv_message.
    RETURN.
  ENDIF.

*---------------------------------------------------------------------*
* Ownership rules
*---------------------------------------------------------------------*
  IF lv_tag_profile IS INITIAL.

    "No profile marker exists in the old script.
    "It is safe only when the TCODE has exactly one registered profile.
    IF lv_profile_count <> 1.
      lv_message =
        |TCODE { ps_profile-tcode } has { lv_profile_count } profiles but its legacy script has no owner.|.

      PERFORM append_log
        USING ps_profile
              gc_result_blocked
              lv_message.
      RETURN.
    ENDIF.

  ELSE.

    "The old script explicitly belongs to another profile.
    IF lv_tag_profile <> ps_profile-profile_name OR
       lv_tag_version <> ps_profile-profile_ver.

      lv_message =
        |Legacy script belongs to { lv_tag_profile } v{ lv_tag_version }, not this profile.|.

      PERFORM append_log
        USING ps_profile
              gc_result_blocked
              lv_message.
      RETURN.
    ENDIF.

  ENDIF.

*---------------------------------------------------------------------*
* Structural validation before copying raw legacy script
*---------------------------------------------------------------------*
  LOOP AT lt_legacy INTO ls_legacy.

    IF ls_legacy-step_seq IS INITIAL.
      lv_invalid = abap_true.
      lv_message = 'Legacy script contains an empty STEP_SEQ.'.
      EXIT.
    ENDIF.

    IF ls_legacy-is_new_screen = 'X'.

      IF ls_legacy-program_name IS INITIAL OR
         ls_legacy-dynpro_no   IS INITIAL.
        lv_invalid = abap_true.
        lv_message =
          |Screen step { ls_legacy-step_seq } has no Program/Dynpro.|.
        EXIT.
      ENDIF.

    ELSE.

      IF ls_legacy-field_name IS INITIAL.
        lv_invalid = abap_true.
        lv_message =
          |Field step { ls_legacy-step_seq } has an empty FIELD_NAME.|.
        EXIT.
      ENDIF.

    ENDIF.

  ENDLOOP.

  IF lv_invalid = abap_true.
    PERFORM append_log
      USING ps_profile
            gc_result_blocked
            lv_message.
    RETURN.
  ENDIF.

*---------------------------------------------------------------------*
* Generate immutable Script ID
*---------------------------------------------------------------------*
  TRY.
      lv_script_id =
        cl_system_uuid=>create_uuid_c32_static( ).
    CATCH cx_uuid_error INTO lx_uuid.
      lv_message = lx_uuid->get_text( ).

      PERFORM append_log
        USING ps_profile
              gc_result_error
              lv_message.
      RETURN.
  ENDTRY.

  GET TIME STAMP FIELD lv_timestamp.

*---------------------------------------------------------------------*
* Build versioned script header
*---------------------------------------------------------------------*
  CLEAR ls_header.

  ls_header-script_id      = lv_script_id.
  ls_header-tcode          = ps_profile-tcode.
  ls_header-profile_name   = ps_profile-profile_name.
  ls_header-profile_ver    = ps_profile-profile_ver.
  ls_header-recording_name = 'LEGACY_MIGRATION'.
  ls_header-status         = gc_header_status.
  CLEAR ls_header-contract_hash.
  ls_header-created_by     = sy-uname.
  ls_header-created_at     = lv_timestamp.
  ls_header-changed_by     = sy-uname.
  ls_header-changed_at     = lv_timestamp.

*---------------------------------------------------------------------*
* Build versioned steps
*---------------------------------------------------------------------*
  REFRESH lt_steps.

  LOOP AT lt_legacy INTO ls_legacy.

    CLEAR ls_step.

    ls_step-script_id     = lv_script_id.
    ls_step-step_seq      = ls_legacy-step_seq.
    ls_step-is_new_screen = ls_legacy-is_new_screen.
    ls_step-field_name    = ls_legacy-field_name.
    ls_step-value_type    = ls_legacy-value_type.
    ls_step-static_value  = ls_legacy-static_value.
    ls_step-source_column = ls_legacy-source_column.
    ls_step-row_type      = ls_legacy-row_type.
    ls_step-program_name  = ls_legacy-program_name.
    ls_step-dynpro_no     = ls_legacy-dynpro_no.

    APPEND ls_step TO lt_steps.

  ENDLOOP.

*---------------------------------------------------------------------*
* Dry run: do not write database
*---------------------------------------------------------------------*
  IF p_test = abap_true.
    lv_message =
      |Would migrate { lines( lt_steps ) } step(s) into Script ID { lv_script_id }.|.

    PERFORM append_log
      USING ps_profile
            gc_result_test
            lv_message.
    RETURN.
  ENDIF.

*---------------------------------------------------------------------*
* Productive migration
*---------------------------------------------------------------------*
  INSERT zbdc_script_bup FROM @ls_header.

  IF sy-subrc <> 0.
    ROLLBACK WORK.

    lv_message =
      |Could not insert script header; SY-SUBRC={ sy-subrc }.|.

    PERFORM append_log
      USING ps_profile
            gc_result_error
            lv_message.
    RETURN.
  ENDIF.

  INSERT zbdc_sct_ver_bup FROM TABLE @lt_steps.

  IF sy-subrc <> 0.
    ROLLBACK WORK.

    lv_message =
      |Could not insert versioned script steps; SY-SUBRC={ sy-subrc }.|.

    PERFORM append_log
      USING ps_profile
            gc_result_error
            lv_message.
    RETURN.
  ENDIF.

  COMMIT WORK AND WAIT.

  lv_message =
    |Migrated { lines( lt_steps ) } step(s) into Script ID { lv_script_id }. Certification is still required.|.

  PERFORM append_log
    USING ps_profile
          gc_result_done
          lv_message.

ENDFORM.

*---------------------------------------------------------------------*
* Append one migration result
*---------------------------------------------------------------------*
FORM append_log
  USING ps_profile TYPE zbdc_prof_bup
        pv_result  TYPE char20
        pv_message TYPE char255.

  DATA ls_log TYPE ty_log.

  CLEAR ls_log.

  ls_log-tcode        = ps_profile-tcode.
  ls_log-profile_name = ps_profile-profile_name.
  ls_log-profile_ver  = ps_profile-profile_ver.
  ls_log-result       = pv_result.
  ls_log-message      = pv_message.

  APPEND ls_log TO gt_log.

ENDFORM.

*---------------------------------------------------------------------*
* Display migration report
*---------------------------------------------------------------------*
FORM display_result.

  DATA:
    ls_log      TYPE ty_log,
    lv_test_txt TYPE char20.

  IF p_test = abap_true.
    lv_test_txt = 'TEST RUN'.
  ELSE.
    lv_test_txt = 'DATABASE UPDATE'.
  ENDIF.

  ULINE.
  WRITE: / 'BDC Versioned Script Migration',
         / 'Mode:', lv_test_txt.
  ULINE.

  WRITE:
    / 'TCODE',
      23 'PROFILE',
      55 'VERSION',
      65 'RESULT',
      88 'MESSAGE'.

  ULINE.

  LOOP AT gt_log INTO ls_log.
    WRITE:
      / ls_log-tcode,
        23 ls_log-profile_name,
        55 ls_log-profile_ver,
        65 ls_log-result,
        88 ls_log-message.
  ENDLOOP.

  ULINE.

  DATA:
    lv_migrate TYPE i,
    lv_blocked TYPE i,
    lv_skip    TYPE i,
    lv_error   TYPE i.

  LOOP AT gt_log INTO ls_log.
    CASE ls_log-result.
      WHEN gc_result_test OR gc_result_done.
        lv_migrate = lv_migrate + 1.
      WHEN gc_result_blocked.
        lv_blocked = lv_blocked + 1.
      WHEN gc_result_skip.
        lv_skip = lv_skip + 1.
      WHEN gc_result_error.
        lv_error = lv_error + 1.
    ENDCASE.
  ENDLOOP.

  WRITE:
    / 'Migratable/Migrated:', lv_migrate,
    / 'Needs re-import:    ', lv_blocked,
    / 'Already exists:     ', lv_skip,
    / 'Technical errors:   ', lv_error.

  IF p_test = abap_true.
    SKIP.
    WRITE:
      / 'No database data was changed.',
      / 'Review every NEEDS_REIMPORT line before executing productive migration.'.
  ENDIF.

ENDFORM.
